//
//  PantrixCrashNSException.m
//  PantrixCrash
//
//  See PantrixCrashNSException.h. Adapted from KSCrash's KSCrashMonitor_NSException (save + chain the
//  previous handler; capture name/reason/callStackReturnAddresses), scoped to a telemetry recorder.
//

#import <Foundation/Foundation.h>

#import "PantrixCrashNSException.h"
#import "PantrixCrashRecord.h"
#import "PantrixCrashImageCache.h"
#import "PantrixCrashState.h"
#import "PantrixCrashThread.h"

#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/time.h>

#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#define PANTRIX_STRIP_RET(p) ((uintptr_t)ptrauth_strip((void *)(uintptr_t)(p), ptrauth_key_return_address))
#else
#define PANTRIX_STRIP_RET(p) ((uintptr_t)(p))
#endif

#define PANTRIX_NS_MAX_FRAMES 128
#define PANTRIX_NS_MAX_IMAGES 512

static atomic_bool g_ns_installed = false;
static NSUncaughtExceptionHandler *g_previous_handler = NULL;
static uintptr_t g_ns_frames[PANTRIX_NS_MAX_FRAMES];
static PantrixCrashImage g_ns_images[PANTRIX_NS_MAX_IMAGES];

/// Builds a crash record from `exception` and writes it through the shared writer. Returns whether the
/// write succeeded. The caller owns the dedup gate (must have won `pantrixcrash_begin_handling`).
static bool writeExceptionReport(NSException *exception) {
    NSArray<NSNumber *> *addresses = exception.callStackReturnAddresses;
    uint32_t frame_count = 0;
    for (NSNumber *address in addresses) {
        if (frame_count >= PANTRIX_NS_MAX_FRAMES) {
            break;
        }
        g_ns_frames[frame_count++] = PANTRIX_STRIP_RET(address.unsignedLongLongValue);
    }

    uint32_t total = pcimg_image_count();
    if (total > PANTRIX_NS_MAX_IMAGES) {
        total = PANTRIX_NS_MAX_IMAGES;
    }
    uint32_t image_count = 0;
    for (uint32_t i = 0; i < total; i++) {
        if (pcimg_get_image(i, &g_ns_images[image_count])) {
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
    ctx.crash_type = PANTRIX_CRASH_TYPE_NSEXCEPTION;
    ctx.signum = SIGABRT;   // an uncaught NSException ends in abort() → SIGABRT
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
    ctx.type = exception.name.UTF8String;
    ctx.reason = exception.reason.UTF8String;   // nil reason → NULL
    // Çöken thread'in kendisinde, NORMAL context'te koşuyoruz (signal kısıtı yok), o yüzden
    // `pthread_getname_np` serbest. Ad boşsa (iOS main thread'inde tipik) resolver "main"e düşer.
    char pth_name[64] = {0};
    pthread_getname_np(pthread_self(), pth_name, sizeof(pth_name));
    char thread_name_buf[64];
    ctx.name = pantrixcrash_thread_name(thread_id, pth_name, thread_name_buf, sizeof(thread_name_buf));
    ctx.frames = g_ns_frames;
    ctx.frame_count = frame_count;
    ctx.images = g_ns_images;
    ctx.image_count = image_count;

    return pantrixcrash_write_report(&ctx, pantrixcrash_get_record_path());
}

static void handleUncaughtException(NSException *exception) {
    // Snapshot the previous handler once (a concurrent uninstall could NULL the global between the check
    // and the call otherwise).
    NSUncaughtExceptionHandler *previous = g_previous_handler;
    // Dedup gate: only the first catcher writes. The abort()->SIGABRT that follows sees the gate set.
    if (pantrixcrash_begin_handling()) {
        writeExceptionReport(exception);   // result irrelevant on the die-path
    }
    // Chain the previous handler so the runtime still aborts and any other reporter runs.
    if (previous != NULL) {
        previous(exception);
    }
}

void pantrix_crash_nsexception_install(const char *record_directory) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&g_ns_installed, &expected, true)) {
        return;
    }
    pantrixcrash_set_record_path(record_directory);
    g_previous_handler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&handleUncaughtException);
}

void pantrix_crash_nsexception_uninstall(void) {
    if (!atomic_exchange(&g_ns_installed, false)) {
        return;
    }
    NSSetUncaughtExceptionHandler(g_previous_handler);
    g_previous_handler = NULL;
}

bool pantrixcrash_test_nsexception_write(const char *record_directory, const char *name, const char *reason) {
    pantrixcrash_reset_handling();
    pantrixcrash_set_record_path(record_directory);

    NSException *exception = [NSException exceptionWithName:@(name)
                                                    reason:(reason ? @(reason) : nil)
                                                  userInfo:nil];
    @try {
        [exception raise];
    } @catch (NSException *caught) {
        if (pantrixcrash_begin_handling()) {
            return writeExceptionReport(caught);   // `caught` has its callStackReturnAddresses populated
        }
    }
    return false;
}
