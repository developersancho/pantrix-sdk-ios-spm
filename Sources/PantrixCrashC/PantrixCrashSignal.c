//
//  PantrixCrashSignal.c
//  PantrixCrash
//
//  POSIX-signal catcher. Adapted from KSCrash's KSCrashMonitor_Signal (release/2.6.0's async-safety
//  discipline: restore handlers only from the handler — never free() the sigaltstack we're running on),
//  scoped down to a telemetry recorder. See PantrixCrashSignal.h.
//

#include "PantrixCrashSignal.h"
#include "PantrixCrashRecord.h"
#include "PantrixCrashImageCache.h"
#include "PantrixCrashState.h"
#include "PantrixCrashThread.h"

#include <errno.h>
#include <limits.h>
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

// PANTRIX_STRIP_RET, PANTRIX_MAX_FRAMES/IMAGES, pantrixcrash_walk_frames + pantrixcrash_signal_name are
// shared with the Mach catcher — declared in PantrixCrashSignal.h.

static const int kFatalSignals[] = { SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP };
static const int kFatalSignalCount = (int)(sizeof(kFatalSignals) / sizeof(kFatalSignals[0]));

static atomic_bool g_installed = false;
static struct sigaction g_previous[6];
static stack_t g_signal_stack;

// Crash-time scratch — static so the handler never allocates.
static uintptr_t g_frames[PANTRIX_MAX_FRAMES];
static PantrixCrashImage g_images[PANTRIX_MAX_IMAGES];

const char *pantrixcrash_signal_name(int signum) {
    switch (signum) {
        case SIGSEGV: return "SIGSEGV";
        case SIGABRT: return "SIGABRT";
        case SIGBUS:  return "SIGBUS";
        case SIGILL:  return "SIGILL";
        case SIGFPE:  return "SIGFPE";
        case SIGTRAP: return "SIGTRAP";
        default:      return "SIGNAL";
    }
}

/// Reads the { saved_fp, return_address } pair at `fp` WITHOUT faulting. `vm_read_overwrite` is a Mach
/// trap that returns an error for unmapped / protected memory instead of raising — essential on the Mach
/// handler thread, where a raw dereference of a corrupt fp would fault and (its own exception port having
/// no other receiver) deadlock the process. Async-signal-safe. Returns false on an unreadable address.
static bool read_frame_record(uintptr_t fp, uintptr_t *saved_fp, uintptr_t *ret) {
    uintptr_t record[2] = { 0, 0 };
    vm_size_t out = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)fp,
                                         sizeof(record), (vm_address_t)record, &out);
    if (kr != KERN_SUCCESS || out != sizeof(record)) {
        return false;
    }
    *saved_fp = record[0];
    *ret = record[1];
    return true;
}

/// Frame-pointer stack walk shared by the signal + Mach catchers. Records `pc` then walks the fp chain
/// (each record is { saved_fp, return_address }), reading each record through a fault-free Mach trap so a
/// corrupt/unmapped fp stops the walk instead of faulting. Cheap corruption guards (fp aligned + strictly
/// increasing + bounded count) cut loops short. Every address is PAC-stripped for offline symbolication.
uint32_t pantrixcrash_walk_frames(uintptr_t pc, uintptr_t fp, uintptr_t *frames, uint32_t max) {
    if (frames == NULL || max == 0) {
        return 0;
    }
    uint32_t n = 0;
    if (pc != 0) {
        frames[n++] = PANTRIX_STRIP_RET(pc);
    }
    while (fp != 0 && (fp & (sizeof(uintptr_t) - 1)) == 0 && n < max) {
        uintptr_t saved_fp = 0;
        uintptr_t ret = 0;
        if (!read_frame_record(fp, &saved_fp, &ret)) {
            break;   // unmapped / corrupt fp — stop safely rather than fault
        }
        if (ret == 0) {
            break;
        }
        frames[n++] = PANTRIX_STRIP_RET(ret);
        if (saved_fp <= fp) {   // fp must move up the (downward-growing) stack — guards against loops
            break;
        }
        fp = saved_fp;
    }
    return n;
}

/// Seeds the shared fp-walk from the signal machine context (the crashing thread is the current thread).
static uint32_t walk_stack(const ucontext_t *uc, uintptr_t *frames, uint32_t max) {
    if (uc == NULL || uc->uc_mcontext == NULL) {
        return 0;
    }
    uintptr_t pc = 0;
    uintptr_t fp = 0;
#if defined(__arm64__) || defined(__aarch64__)
    pc = (uintptr_t)uc->uc_mcontext->__ss.__pc;
    fp = (uintptr_t)uc->uc_mcontext->__ss.__fp;
#elif defined(__x86_64__)
    pc = (uintptr_t)uc->uc_mcontext->__ss.__rip;
    fp = (uintptr_t)uc->uc_mcontext->__ss.__rbp;
#else
    return 0;
#endif
    return pantrixcrash_walk_frames(pc, fp, frames, max);
}

/// Allocates the alternate signal stack once (the handler's only malloc, done off the crash path).
/// Idempotent — a second call is a no-op, and after a fork the child inherits it (COW) so its install
/// does not malloc.
static void ensure_signal_stack(void) {
    if (g_signal_stack.ss_sp != NULL) {
        return;
    }
    size_t stack_size = (size_t)SIGSTKSZ;
    if (stack_size < 16384) {
        stack_size = 16384;
    }
    g_signal_stack.ss_sp = malloc(stack_size);
    g_signal_stack.ss_size = stack_size;
    g_signal_stack.ss_flags = 0;
}

static void restore_handlers(void) {
    if (!atomic_exchange(&g_installed, false)) {
        return;   // restore once
    }
    for (int i = 0; i < kFatalSignalCount; i++) {
        sigaction(kFatalSignals[i], &g_previous[i], NULL);
    }
    // Deliberately NOT freeing / resetting g_signal_stack — the handler may be executing on it (2.6.0).
}

static void handle_signal(int signum, siginfo_t *info, void *uc_void) {
    // One-shot gate FIRST: if a fatal crash is already owned (another catcher, or the abort()->SIGABRT
    // that follows an NSException), just chain and bail — one report, never two.
    if (!pantrixcrash_begin_handling()) {
        restore_handlers();
        raise(signum);
        return;
    }

    const ucontext_t *uc = (const ucontext_t *)uc_void;
    uint32_t frame_count = walk_stack(uc, g_frames, PANTRIX_MAX_FRAMES);

    uint32_t total_images = pcimg_image_count();
    if (total_images > PANTRIX_MAX_IMAGES) {
        total_images = PANTRIX_MAX_IMAGES;
    }
    uint32_t image_count = 0;
    for (uint32_t i = 0; i < total_images; i++) {
        if (pcimg_get_image(i, &g_images[image_count])) {
            image_count++;
        }
    }

    struct timeval tv;
    gettimeofday(&tv, NULL);
    uint64_t timestamp_ms = (uint64_t)tv.tv_sec * 1000ull + (uint64_t)tv.tv_usec / 1000ull;

    uint64_t thread_id = 0;
    pthread_threadid_np(pthread_self(), &thread_id);

    PantrixCrashContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.crash_type = PANTRIX_CRASH_TYPE_SIGNAL;
    ctx.signum = signum;
    ctx.sigcode = info ? info->si_code : 0;
    ctx.fault_address = info ? (uint64_t)(uintptr_t)info->si_addr : 0;
    ctx.timestamp_ms = timestamp_ms;
    ctx.thread_id = thread_id;
    ctx.foreground = pantrixcrash_get_foreground();
    // Snapshot the staged session/screen by value — `staged` lives for the whole write, so a screen
    // change on a still-running sibling thread can't mutate the bytes we serialize.
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
    // `pthread_getname_np` async-signal-safe DEĞİL, o yüzden adı BURADA okuyamayız. Ama main tespiti
    // saklanan id ile async-safe: main-thread sinyali (baskın durum, ör. main'de SIGABRT) "main" olur,
    // diğer thread'ler NULL. Adlandırılmış non-main thread'lerin çoğu zaten Mach handler'ından gerçek
    // adıyla geçer.
    char thread_name_buf[64];
    ctx.name = pantrixcrash_thread_name(thread_id, NULL, thread_name_buf, sizeof(thread_name_buf));
    ctx.reason = NULL;
    ctx.frames = g_frames;
    ctx.frame_count = frame_count;
    ctx.images = g_images;
    ctx.image_count = image_count;

    pantrixcrash_write_report(&ctx, pantrixcrash_get_record_path());

    // Restore + re-raise: the (usually default) previous disposition terminates the process with the
    // correct signal, and any other reporter's handler in the chain still runs.
    restore_handlers();
    raise(signum);
}

void pantrix_crash_signal_install(const char *record_directory) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&g_installed, &expected, true)) {
        return;   // already installed
    }

    // Render the shared record path once, now (normal context — snprintf is fine here, never in the
    // handler). One file per process (pid), so records from different launches don't collide under O_EXCL.
    pantrixcrash_set_record_path(record_directory);

    // Pre-allocate the alternate stack once so a stack-overflow SIGSEGV still has stack to run on. Never
    // freed / never touched from the handler.
    ensure_signal_stack();
    if (g_signal_stack.ss_sp != NULL) {
        sigaltstack(&g_signal_stack, NULL);
    }

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
#ifdef SA_64REGSET
    action.sa_flags |= SA_64REGSET;
#endif
    sigemptyset(&action.sa_mask);
    action.sa_sigaction = &handle_signal;

    for (int i = 0; i < kFatalSignalCount; i++) {
        sigaction(kFatalSignals[i], &action, &g_previous[i]);
    }
}

void pantrix_crash_signal_uninstall(void) {
    restore_handlers();
}

// MARK: - Test support

int pantrixcrash_test_fork_and_crash(const char *record_directory, int signum) {
    // Allocate the alt stack in the PARENT so the child's install() doesn't malloc (malloc isn't
    // async-signal-safe after fork). The child inherits the allocation via COW.
    ensure_signal_stack();

    pid_t pid = fork();
    if (pid < 0) {
        return -1;
    }
    if (pid == 0) {
        // Child: only async-safe C from here (other threads are frozen by fork). Arm the engine and
        // raise the signal; the handler writes the record and re-raises, so the child dies from `signum`.
        pcimg_start();
        pantrixcrash_reset_handling();
        pantrix_crash_signal_install(record_directory);
        raise(signum);
        _exit(0);   // unreached — the handler re-raises
    }
    int status = 0;
    waitpid(pid, &status, 0);
    if (WIFSIGNALED(status)) {
        return WTERMSIG(status);
    }
    return 0;
}
