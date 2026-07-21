//
//  PantrixCrashCPPException.mm
//  PantrixCrash
//
//  See PantrixCrashCPPException.h. Adapted from KSCrash's KSCrashMonitor_CPPException (release/2.6.0's
//  vtable+PAC isNSException guard + null-tinfo guard), WITHOUT the __cxa_throw fishhook (MVP).
//

#include "PantrixCrashCPPException.h"
#include "PantrixCrashRecord.h"
#include "PantrixCrashImageCache.h"
#include "PantrixCrashState.h"
#include "PantrixCrashThread.h"

#include <cxxabi.h>
#include <exception>
#include <stdexcept>
#include <typeinfo>

#include <execinfo.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

// The Itanium C++ ABI type_info vtable for an Obj-C exception — a private libobjc symbol.
extern "C" const void *objc_ehtype_vtable[];

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#define PANTRIX_STRIP_VTABLE(p) ptrauth_strip((void *)(uintptr_t)(p), ptrauth_key_cxx_vtable_pointer)
#else
#define PANTRIX_STRIP_VTABLE(p) ((void *)(uintptr_t)(p))
#endif

#define PANTRIX_CPP_MAX_FRAMES 128
#define PANTRIX_CPP_MAX_IMAGES 512

static atomic_bool g_cpp_installed = false;
static std::terminate_handler g_previous_terminate = nullptr;
static uintptr_t g_cpp_frames[PANTRIX_CPP_MAX_FRAMES];
static PantrixCrashImage g_cpp_images[PANTRIX_CPP_MAX_IMAGES];

/// True if `tinfo` is an Obj-C exception type. Its type_info vtable pointer equals `objc_ehtype_vtable+2`
/// (the Itanium ABI offset-to-top + RTTI prefix); both are PAC-stripped before comparing on arm64e.
static bool isObjCException(const std::type_info *tinfo) {
    if (tinfo == nullptr) {
        return false;
    }
    const void *tinfo_vtable = *reinterpret_cast<const void *const *>(tinfo);
    const void *objc_vtable = reinterpret_cast<const void *>(objc_ehtype_vtable + 2);
    return PANTRIX_STRIP_VTABLE(tinfo_vtable) == PANTRIX_STRIP_VTABLE(objc_vtable);
}

/// Writes a C++ crash record. Runs synchronously on the crashing thread (not a signal context), so
/// backtrace()/malloc are permitted; the record write itself uses the shared writer. Returns success.
static bool writeCPPReport(const char *type, const char *reason) {
    void *addresses[PANTRIX_CPP_MAX_FRAMES];
    int count = backtrace(addresses, PANTRIX_CPP_MAX_FRAMES);
    uint32_t frame_count = 0;
    for (int i = 0; i < count && frame_count < PANTRIX_CPP_MAX_FRAMES; i++) {
        g_cpp_frames[frame_count++] = (uintptr_t)addresses[i];
    }

    uint32_t total = pcimg_image_count();
    if (total > PANTRIX_CPP_MAX_IMAGES) {
        total = PANTRIX_CPP_MAX_IMAGES;
    }
    uint32_t image_count = 0;
    for (uint32_t i = 0; i < total; i++) {
        if (pcimg_get_image(i, &g_cpp_images[image_count])) {
            image_count++;
        }
    }

    struct timeval tv;
    gettimeofday(&tv, nullptr);
    uint64_t timestamp_ms = (uint64_t)tv.tv_sec * 1000ull + (uint64_t)tv.tv_usec / 1000ull;
    uint64_t thread_id = 0;
    pthread_threadid_np(pthread_self(), &thread_id);

    PantrixCrashContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.crash_type = PANTRIX_CRASH_TYPE_CPP_TERMINATE;
    ctx.signum = SIGABRT;   // std::terminate ends in abort() → SIGABRT
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
    ctx.type = type;        // mangled type name — the backend demangles
    ctx.reason = reason;
    // std::terminate çöken thread'de, NORMAL context'te koşar (bkz. dosya başı: malloc/backtrace izinli),
    // o yüzden `pthread_getname_np` serbest. Ad boşsa resolver "main"e düşer.
    char pth_name[64] = {0};
    pthread_getname_np(pthread_self(), pth_name, sizeof(pth_name));
    char thread_name_buf[64];
    ctx.name = pantrixcrash_thread_name(thread_id, pth_name, thread_name_buf, sizeof(thread_name_buf));
    ctx.frames = g_cpp_frames;
    ctx.frame_count = frame_count;
    ctx.images = g_cpp_images;
    ctx.image_count = image_count;

    return pantrixcrash_write_report(&ctx, pantrixcrash_get_record_path());
}

static void handleTerminate() {
    std::terminate_handler previous = g_previous_terminate;   // snapshot once
    const std::type_info *tinfo = abi::__cxa_current_exception_type();

    // Obj-C exceptions reach terminate via the C++ ABI — the NSException catcher owns them, so skip here.
    if (!isObjCException(tinfo) && pantrixcrash_begin_handling()) {
        const char *type = (tinfo != nullptr) ? tinfo->name() : nullptr;
        char reason[512];
        reason[0] = '\0';
        if (tinfo != nullptr) {
            // Rethrow the in-flight exception to extract a description. Guarded on tinfo != null so a bare
            // `throw` with no active exception can't recurse into terminate.
            try {
                throw;
            } catch (const std::exception &e) {
                strlcpy(reason, e.what(), sizeof(reason));
            } catch (...) {
                // non-std exception — no description available
            }
        }
        writeCPPReport(type, reason[0] != '\0' ? reason : nullptr);
    }

    // Chain the previous handler, then abort as a backstop so the process always terminates.
    if (previous != nullptr) {
        previous();
    }
    abort();
}

void pantrix_crash_cppexception_install(const char *record_directory) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&g_cpp_installed, &expected, true)) {
        return;
    }
    pantrixcrash_set_record_path(record_directory);
    // set_terminate atomically swaps + returns the old handler; g_previous_terminate is only set after.
    // A terminate firing in the microscopic gap would chain nothing (still aborts, still writes our
    // report). Harmless and inherent to set_terminate's swap semantics — install runs once at startup.
    g_previous_terminate = std::set_terminate(&handleTerminate);
}

void pantrix_crash_cppexception_uninstall(void) {
    if (!atomic_exchange(&g_cpp_installed, false)) {
        return;
    }
    std::set_terminate(g_previous_terminate);
    g_previous_terminate = nullptr;
}

// MARK: - Test support

bool pantrixcrash_test_cpp_write(const char *record_directory, const char *type, const char *reason) {
    pantrixcrash_reset_handling();
    pantrixcrash_set_record_path(record_directory);
    if (pantrixcrash_begin_handling()) {
        return writeCPPReport(type, reason);
    }
    return false;
}

bool pantrixcrash_test_cpp_installed(void) {
    return std::get_terminate() == &handleTerminate;
}

bool pantrixcrash_test_cpp_extract_write(const char *record_directory) {
    pantrixcrash_reset_handling();
    pantrixcrash_set_record_path(record_directory);
    try {
        throw std::runtime_error("extracted reason");
    } catch (...) {
        // Inside the catch there IS a current exception — exercise the terminate handler's exact
        // extraction (type name + rethrow-for-what()) without terminate/abort.
        const std::type_info *tinfo = abi::__cxa_current_exception_type();
        const char *type = (tinfo != nullptr) ? tinfo->name() : nullptr;
        char reason[512];
        reason[0] = '\0';
        if (tinfo != nullptr) {
            try {
                throw;
            } catch (const std::exception &e) {
                strlcpy(reason, e.what(), sizeof(reason));
            } catch (...) {
            }
        }
        if (pantrixcrash_begin_handling()) {
            return writeCPPReport(type, reason[0] != '\0' ? reason : nullptr);
        }
    }
    return false;
}
