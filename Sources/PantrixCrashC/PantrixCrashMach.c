//
//  PantrixCrashMach.c
//  PantrixCrash
//
//  Mach exception catcher. Recipe cross-checked against KSCrash 2.6.0 and sentry-cocoa (both KSCrash
//  descendants agree on the load-bearing core): one RECEIVE port + MAKE_SEND right, registered for the
//  hardware-fault mask with EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES; a dedicated thread blocked in
//  mach_msg(); on a fault, read the crashed thread's state, write the shared .pcrx record, restore the
//  prior ports and reply KERN_FAILURE so the process still dies with the correct signal.
//
//  Scoped down vs KSCrash: single handler thread (no secondary). It DOES do a suspend-the-world pass over
//  the peer threads for the v4 all-threads snapshot (`capture_other_threads` below) — but per-thread
//  suspend/walk/resume, not a whole-task freeze. The Mach exception is mapped onto the signal record fields
//  for the crashed thread — see PantrixCrashSignal.h for the shared walk + signal-name helpers.
//

#include "PantrixCrashMach.h"
#include "PantrixCrashRecord.h"
#include "PantrixCrashImageCache.h"
#include "PantrixCrashState.h"
#include "PantrixCrashThread.h"   // pantrixcrash_thread_name
#include "PantrixCrashSignal.h"   // pantrixcrash_walk_frames, pantrixcrash_signal_name, PANTRIX_MAX_*

#include <mach/mach.h>
#include <mach/exception_types.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// The hardware-fault exceptions we own. NOT EXC_MASK_SOFTWARE (no fatal machine fault) and NOT
// EXC_MASK_CRASH (abort()/EXC_GUARD — a directed SIGABRT that never traverses the port; owned by the
// signal / NSException / C++ catchers, so there is zero overlap).
#define PANTRIX_EXC_MASK \
    (EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION | EXC_MASK_ARITHMETIC | EXC_MASK_BREAKPOINT)

#pragma pack(4)
// The mach_exception_raise (MACH_EXCEPTION_CODES) request as generated from mach_exc.defs. `padding`
// gives MACH_RCV_LARGE room so an oversized message never truncates.
typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t thread;
    mach_msg_port_descriptor_t task;
    NDR_record_t ndr;
    exception_type_t exception;
    mach_msg_type_number_t code_count;
    mach_exception_data_type_t code[2];
    char padding[512];
} PantrixMachRequest;

typedef struct {
    mach_msg_header_t header;
    NDR_record_t ndr;
    kern_return_t return_code;
} PantrixMachReply;
#pragma pack()

// Saved prior exception ports, restored on a fault (so the process dies through them) and on uninstall.
typedef struct {
    exception_mask_t masks[EXC_TYPES_COUNT];
    exception_handler_t ports[EXC_TYPES_COUNT];
    exception_behavior_t behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t count;
} PantrixPreviousPorts;

static atomic_bool g_installed = false;
static mach_port_t g_exception_port = MACH_PORT_NULL;
static mach_port_t g_handler_thread = MACH_PORT_NULL;   // the handler pthread's mach port, for teardown
static PantrixPreviousPorts g_previous_ports;
static char g_record_dir[1024];

// Crash-time scratch — static so the handler never allocates.
static uintptr_t g_mach_frames[PANTRIX_MAX_FRAMES];
static PantrixCrashImage g_mach_images[PANTRIX_MAX_IMAGES];

// v4 all-threads capture scratch: one frame buffer + name buffer per captured peer thread. Bounded by
// PANTRIX_MAX_THREADS (Android's MAX_THREADS_IN_EXCEPTION) so the record and the suspend window stay small.
#define PANTRIX_MAX_THREADS 16
static uintptr_t g_mach_thread_frames[PANTRIX_MAX_THREADS][PANTRIX_MAX_FRAMES];
static char g_mach_thread_names[PANTRIX_MAX_THREADS][64];
static PantrixCrashThread g_mach_threads[PANTRIX_MAX_THREADS];

/// True when a debugger is attached — it owns the task exception ports, so we must not install over it.
/// Runs at install on a normal thread; `sysctl` here is fine (not the crash path).
static bool is_being_traced(void) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    memset(&info, 0, sizeof(info));
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        return false;   // can't tell → assume not traced
    }
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

/// Maps a Mach exception to the BSD signal the OS would raise, so the record's signal fields carry the
/// SAME value a signal-caught crash would (the kernel's `ux_exception` translation): EXC_BAD_ACCESS is
/// SIGSEGV only for KERN_INVALID_ADDRESS, else SIGBUS (protection failures, unaligned, etc.).
static int mach_exception_to_signal(exception_type_t exception, mach_exception_data_type_t code0) {
    switch (exception) {
        case EXC_BAD_ACCESS:      return (code0 == KERN_INVALID_ADDRESS) ? SIGSEGV : SIGBUS;
        case EXC_BAD_INSTRUCTION: return SIGILL;
        case EXC_ARITHMETIC:      return SIGFPE;
        case EXC_BREAKPOINT:      return SIGTRAP;
        default:                  return SIGSEGV;
    }
}

/// Restores the exception ports that were registered before us (so a forwarded fault re-delivers to them).
static void restore_previous_ports(void) {
    for (mach_msg_type_number_t i = 0; i < g_previous_ports.count; i++) {
        task_set_exception_ports(mach_task_self(),
                                 g_previous_ports.masks[i],
                                 g_previous_ports.ports[i],
                                 g_previous_ports.behaviors[i],
                                 g_previous_ports.flavors[i]);
    }
}

/// Suspend-the-world snapshot of every OTHER live thread — the crashed thread is captured separately (from
/// the exception message + header). Ported from KSCrash's `ksmc_suspendEnvironment` (KSMachineContext.c),
/// scoped to a per-thread suspend → read state → walk → resume so the freeze window per peer is tiny and no
/// lock a peer holds can wedge us: this handler never allocates, and every read is a fault-free Mach trap
/// (thread_get_state / thread_info / the vm_read_overwrite inside pantrixcrash_walk_frames), so a corrupt
/// peer stack fails the read rather than re-crashing. Peers are matched/skipped by `thread_id` (stable and
/// comparable), NOT by port name — task_threads and the exception message hand out different send rights to
/// the same thread. Fills g_mach_threads[0..return) and returns the count (<= PANTRIX_MAX_THREADS).
static uint32_t capture_other_threads(uint64_t crashed_tid) {
    thread_act_array_t list = NULL;
    mach_msg_type_number_t count = 0;
    if (task_threads(mach_task_self(), &list, &count) != KERN_SUCCESS || list == NULL) {
        return 0;
    }

    // Our own (handler) thread — must NEVER suspend self (it would freeze this handler forever).
    thread_t self = mach_thread_self();
    uint64_t self_tid = 0;
    thread_identifier_info_data_t self_ti;
    mach_msg_type_number_t self_tic = THREAD_IDENTIFIER_INFO_COUNT;
    if (thread_info(self, THREAD_IDENTIFIER_INFO, (thread_info_t)&self_ti, &self_tic) == KERN_SUCCESS) {
        self_tid = self_ti.thread_id;
    }

    uint32_t n = 0;
    for (mach_msg_type_number_t i = 0; i < count && n < PANTRIX_MAX_THREADS; i++) {
        thread_t t = list[i];

        uint64_t tid = 0;
        thread_identifier_info_data_t ti;
        mach_msg_type_number_t tic = THREAD_IDENTIFIER_INFO_COUNT;
        if (thread_info(t, THREAD_IDENTIFIER_INFO, (thread_info_t)&ti, &tic) == KERN_SUCCESS) {
            tid = ti.thread_id;
        }
        // Skip self (running us) and the crashed thread (already in the header) — and any thread we can't id.
        if (tid == 0 || tid == self_tid || tid == crashed_tid) {
            continue;
        }
        // Freeze this peer for a consistent register+stack read; exited/unsuspendable → skip.
        if (thread_suspend(t) != KERN_SUCCESS) {
            continue;
        }

        uintptr_t pc = 0, fp = 0;
#if defined(__arm64__) || defined(__aarch64__)
        arm_thread_state64_t ss;
        mach_msg_type_number_t sc = ARM_THREAD_STATE64_COUNT;
        if (thread_get_state(t, ARM_THREAD_STATE64, (thread_state_t)&ss, &sc) == KERN_SUCCESS) {
            pc = (uintptr_t)arm_thread_state64_get_pc(ss);
            fp = (uintptr_t)arm_thread_state64_get_fp(ss);
        }
#elif defined(__x86_64__)
        x86_thread_state64_t ss;
        mach_msg_type_number_t sc = x86_THREAD_STATE64_COUNT;
        if (thread_get_state(t, x86_THREAD_STATE64, (thread_state_t)&ss, &sc) == KERN_SUCCESS) {
            pc = (uintptr_t)ss.__rip;
            fp = (uintptr_t)ss.__rbp;
        }
#endif
        uint32_t fc = pantrixcrash_walk_frames(pc, fp, g_mach_thread_frames[n], PANTRIX_MAX_FRAMES);

        thread_extended_info_data_t ext;
        memset(&ext, 0, sizeof(ext));
        mach_msg_type_number_t ec = THREAD_EXTENDED_INFO_COUNT;
        (void)thread_info(t, THREAD_EXTENDED_INFO, (thread_info_t)&ext, &ec);
        // Copies into g_mach_thread_names[n] (or returns a static literal / NULL) — never the local `ext`.
        const char *name = pantrixcrash_thread_name(tid, ext.pth_name,
                                                    g_mach_thread_names[n], sizeof(g_mach_thread_names[n]));

        thread_resume(t);

        // A peer we couldn't walk at all yields zero frames: thread_get_state failed, or the thread is
        // mid-create / mid-teardown with no GP registers yet, so `pc` stayed 0 and the walker had no PC to
        // seed frame 0 (a live thread with a valid PC always yields >= 1 frame). Emitting {name, frames:[]}
        // would put a degenerate, unsymbolicatable entry on the wire — drop it; a thread with no capturable
        // frame carries no diagnostic value. `n` is not advanced, so the next peer reuses these buffers.
        if (fc == 0) {
            continue;
        }

        g_mach_threads[n].name = name;
        g_mach_threads[n].frames = g_mach_thread_frames[n];
        g_mach_threads[n].frame_count = fc;
        n++;
    }

    // Release every port task_threads handed back (a send right per thread) + our mach_thread_self() right +
    // the array. Leaking on the crash path is survivable (the process dies), but KSCrash releases them.
    for (mach_msg_type_number_t i = 0; i < count; i++) {
        mach_port_deallocate(mach_task_self(), list[i]);
    }
    mach_port_deallocate(mach_task_self(), self);
    vm_deallocate(mach_task_self(), (vm_address_t)list, count * sizeof(thread_t));
    return n;
}

/// Reads the crashed thread's registers + fault address, walks its (kernel-suspended) stack, and writes
/// the record. Runs on the handler thread — a normal thread with a healthy stack — but keeps the
/// no-malloc / no-ObjC discipline because the victim thread is frozen mid-fault and may hold heap locks.
static void handle_exception(const PantrixMachRequest *request) {
    // One-shot gate: if the signal / NS / C++ catcher already owns this crash, don't double-record.
    if (!pantrixcrash_begin_handling()) {
        return;
    }

    thread_t crashed = (thread_t)request->thread.name;
    exception_type_t exception = request->exception;
    mach_exception_data_type_t code0 = (request->code_count > 0) ? request->code[0] : 0;

    uintptr_t pc = 0;
    uintptr_t fp = 0;
    uint64_t fault = 0;
#if defined(__arm64__) || defined(__aarch64__)
    arm_thread_state64_t ss;
    mach_msg_type_number_t ss_count = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(crashed, ARM_THREAD_STATE64, (thread_state_t)&ss, &ss_count) == KERN_SUCCESS) {
        // These accessors work in both opaque and non-opaque SDK modes and strip PAC.
        pc = (uintptr_t)arm_thread_state64_get_pc(ss);
        fp = (uintptr_t)arm_thread_state64_get_fp(ss);
    }
    arm_exception_state64_t es;
    mach_msg_type_number_t es_count = ARM_EXCEPTION_STATE64_COUNT;
    if (thread_get_state(crashed, ARM_EXCEPTION_STATE64, (thread_state_t)&es, &es_count) == KERN_SUCCESS) {
        fault = (uint64_t)es.__far;
    }
#elif defined(__x86_64__)
    x86_thread_state64_t ss;
    mach_msg_type_number_t ss_count = x86_THREAD_STATE64_COUNT;
    if (thread_get_state(crashed, x86_THREAD_STATE64, (thread_state_t)&ss, &ss_count) == KERN_SUCCESS) {
        pc = (uintptr_t)ss.__rip;
        fp = (uintptr_t)ss.__rbp;
    }
    x86_exception_state64_t es;
    mach_msg_type_number_t es_count = x86_EXCEPTION_STATE64_COUNT;
    if (thread_get_state(crashed, x86_EXCEPTION_STATE64, (thread_state_t)&es, &es_count) == KERN_SUCCESS) {
        fault = (uint64_t)es.__faultvaddr;
    }
#endif

    uint32_t frame_count = pantrixcrash_walk_frames(pc, fp, g_mach_frames, PANTRIX_MAX_FRAMES);

    uint32_t total_images = pcimg_image_count();
    if (total_images > PANTRIX_MAX_IMAGES) {
        total_images = PANTRIX_MAX_IMAGES;
    }
    uint32_t image_count = 0;
    for (uint32_t i = 0; i < total_images; i++) {
        if (pcimg_get_image(i, &g_mach_images[image_count])) {
            image_count++;
        }
    }

    struct timeval tv;
    gettimeofday(&tv, NULL);
    uint64_t timestamp_ms = (uint64_t)tv.tv_sec * 1000ull + (uint64_t)tv.tv_usec / 1000ull;

    // The crashed thread's id (NOT the handler thread's) via a Mach trap.
    uint64_t thread_id = 0;
    thread_identifier_info_data_t tid_info;
    mach_msg_type_number_t tid_count = THREAD_IDENTIFIER_INFO_COUNT;
    if (thread_info(crashed, THREAD_IDENTIFIER_INFO, (thread_info_t)&tid_info, &tid_count) == KERN_SUCCESS) {
        thread_id = tid_info.thread_id;
    }

    // v4: snapshot every OTHER live thread (a suspend-the-world pass). Mach-only — the signal / NSException /
    // C++ catchers stay single-thread (they run ON a live thread and cannot safely suspend their peers).
    uint32_t other_thread_count = capture_other_threads(thread_id);

    // Çöken thread'in ADI: aynı Mach-trap ailesinden `THREAD_EXTENDED_INFO`. `pthread_getname_np`
    // BURADA KULLANILAMAZ — bu handler ayrı, sağlıklı bir thread'de koşar ve çöken thread self değildir;
    // adı yalnızca kernel'e çöken thread'in port'uyla sorarak alınır (yukarıdaki `THREAD_IDENTIFIER_INFO`
    // çağrısıyla birebir aynı güvenlik). Başarısız olursa `pth_name` boş kalır ve resolver "main"e /
    // NULL'a düşer.
    thread_extended_info_data_t ext_info;
    memset(&ext_info, 0, sizeof(ext_info));
    mach_msg_type_number_t ext_count = THREAD_EXTENDED_INFO_COUNT;
    (void)thread_info(crashed, THREAD_EXTENDED_INFO, (thread_info_t)&ext_info, &ext_count);
    char thread_name_buf[64];

    int signum = mach_exception_to_signal(exception, code0);

    PantrixCrashContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.crash_type = PANTRIX_CRASH_TYPE_SIGNAL;   // mapped onto the signal fields — no format change
    ctx.signum = signum;
    ctx.sigcode = (int32_t)code0;
    ctx.fault_address = (exception == EXC_BAD_ACCESS) ? fault : (uint64_t)pc;
    ctx.timestamp_ms = timestamp_ms;
    ctx.thread_id = thread_id;
    ctx.foreground = pantrixcrash_get_foreground();
    PantrixCrashStagedContext staged;
    pantrixcrash_snapshot_context(&staged);
    ctx.session_id = staged.session_id;
    ctx.screen_id = staged.screen_id;
    ctx.screen_name = staged.screen_name;
    ctx.screen_category = staged.screen_category;
    ctx.screen_entered_at = staged.screen_entered_at;
    ctx.screen_load_time = staged.screen_load_time;
    ctx.screen_duration = staged.screen_duration;
    ctx.type = pantrixcrash_signal_name(signum);
    ctx.name = pantrixcrash_thread_name(thread_id, ext_info.pth_name, thread_name_buf, sizeof(thread_name_buf));
    ctx.reason = NULL;
    ctx.frames = g_mach_frames;
    ctx.frame_count = frame_count;
    ctx.images = g_mach_images;
    ctx.image_count = image_count;
    ctx.other_threads = g_mach_threads;
    ctx.other_thread_count = other_thread_count;

    pantrixcrash_write_report(&ctx, pantrixcrash_get_record_path());
}

/// The dedicated handler thread: blocks in mach_msg, handles one fatal exception, forwards it to the
/// prior handler so the process dies correctly.
static void *handler_thread_main(void *arg) {
    (void)arg;
    PantrixMachRequest request;
    PantrixMachReply reply;

    for (;;) {
        memset(&request, 0, sizeof(request));
        kern_return_t kr = mach_msg(&request.header,
                                    MACH_RCV_MSG | MACH_RCV_LARGE,
                                    0,
                                    sizeof(request),
                                    g_exception_port,
                                    MACH_MSG_TIMEOUT_NONE,
                                    MACH_PORT_NULL);
        if (kr != KERN_SUCCESS) {
            continue;   // spurious receive; keep listening
        }

        handle_exception(&request);

        // Restore the prior ports, then reply KERN_FAILURE ("not handled") so the kernel re-delivers the
        // fault to them — the process dies with the correct signal. (KERN_SUCCESS would retry the faulting
        // instruction → an infinite fault loop.)
        restore_previous_ports();

        memset(&reply, 0, sizeof(reply));
        reply.header.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(request.header.msgh_bits), 0);
        reply.header.msgh_remote_port = request.header.msgh_remote_port;
        reply.header.msgh_local_port = MACH_PORT_NULL;
        reply.header.msgh_size = sizeof(reply);
        reply.header.msgh_id = request.header.msgh_id + 100;   // MIG reply id convention
        reply.ndr = request.ndr;
        reply.return_code = KERN_FAILURE;
        mach_msg(&reply.header, MACH_SEND_MSG, sizeof(reply), 0, MACH_PORT_NULL,
                 MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    }
    return NULL;
}

void pantrix_crash_mach_install(const char *record_directory) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&g_installed, &expected, true)) {
        return;   // already installed
    }

    // A debugger owns the exception ports — installing over it fights lldb and captures nothing. Leave the
    // signal catcher as the sole handler. (Roll the install flag back so a later non-traced re-install works.)
    if (is_being_traced()) {
        atomic_store(&g_installed, false);
        return;
    }

    if (record_directory != NULL) {
        strlcpy(g_record_dir, record_directory, sizeof(g_record_dir));
    }
    pantrixcrash_set_record_path(record_directory);

    mach_port_t task = mach_task_self();

    // Save the ports registered before us, so we can restore + forward.
    g_previous_ports.count = EXC_TYPES_COUNT;
    if (task_get_exception_ports(task, PANTRIX_EXC_MASK,
                                 g_previous_ports.masks, &g_previous_ports.count,
                                 g_previous_ports.ports, g_previous_ports.behaviors,
                                 g_previous_ports.flavors) != KERN_SUCCESS) {
        g_previous_ports.count = 0;
    }

    // Reuse the port across re-installs (deallocating it can hang on a later crash).
    if (g_exception_port == MACH_PORT_NULL) {
        if (mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, &g_exception_port) != KERN_SUCCESS) {
            atomic_store(&g_installed, false);
            return;
        }
        if (mach_port_insert_right(task, g_exception_port, g_exception_port,
                                   MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
            atomic_store(&g_installed, false);
            return;
        }
    }

    // Spawn the receiver thread BEFORE arming the port: if the port were armed with no thread in the
    // mach_msg receive loop, a fault would suspend the faulting thread forever awaiting a reply nobody
    // sends. The thread simply blocks (no exceptions route to the port yet) until we arm below.
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t thread;
    int rc = pthread_create(&thread, &attr, &handler_thread_main, NULL);
    pthread_attr_destroy(&attr);
    if (rc != 0) {
        atomic_store(&g_installed, false);   // never armed → nothing to restore
        return;
    }
    g_handler_thread = pthread_mach_thread_np(thread);

    // Arm last: exceptions now route to our port, and the thread is already receiving on it.
    if (task_set_exception_ports(task, PANTRIX_EXC_MASK, g_exception_port,
                                 (exception_behavior_t)(EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES),
                                 THREAD_STATE_NONE) != KERN_SUCCESS) {
        if (g_handler_thread != MACH_PORT_NULL) {
            thread_terminate(g_handler_thread);   // tear down the now-idle handler thread
            g_handler_thread = MACH_PORT_NULL;
        }
        atomic_store(&g_installed, false);
        return;
    }
}

void pantrix_crash_mach_uninstall(void) {
    bool expected = true;
    if (!atomic_compare_exchange_strong(&g_installed, &expected, false)) {
        return;   // not installed
    }
    restore_previous_ports();   // stop receiving on our port; faults go back to the prior handler
    if (g_handler_thread != MACH_PORT_NULL && g_handler_thread != mach_thread_self()) {
        thread_terminate(g_handler_thread);   // it's blocked in mach_msg on a port that no longer receives
        g_handler_thread = MACH_PORT_NULL;
    }
    // Deliberately NOT mach_port_deallocate(g_exception_port) — kept for reuse on re-install.
}

// MARK: - Test support

int pantrixcrash_test_mach_fork_and_crash(const char *record_directory) {
    pid_t pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid == 0) {
        // Child: fork left only this thread alive, so the task's ports + handler thread must be set here.
        // Trigger a REAL machine fault (a directed raise() would skip the exception port).
        pcimg_start();
        pantrixcrash_reset_handling();
        pantrix_crash_mach_install(record_directory);
        volatile int *bad = (volatile int *)0;
        *bad = 0;          // EXC_BAD_ACCESS → recorded by the Mach handler, forwarded → SIGSEGV
        _exit(0);          // unreached
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFSIGNALED(status) ? WTERMSIG(status) : 0;
}
