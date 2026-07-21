//
//  PantrixCrashState.c
//  PantrixCrash
//
//  See PantrixCrashState.h.
//

#include "PantrixCrashState.h"

#include <limits.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/// The one-shot fatal gate. `atomic_flag` is the only C type guaranteed lock-free + async-signal-safe.
static atomic_flag g_crash_handled = ATOMIC_FLAG_INIT;

/// Last-known foreground state, readable from a signal handler.
static volatile sig_atomic_t g_foreground = 0;

/// The crash-record path, rendered at install and read from the crash path.
static char g_record_path[PATH_MAX];

bool pantrixcrash_begin_handling(void) {
    // test_and_set returns the PREVIOUS value: false → we're the first (begin), true → already owned.
    return !atomic_flag_test_and_set_explicit(&g_crash_handled, memory_order_acq_rel);
}

void pantrixcrash_reset_handling(void) {
    atomic_flag_clear_explicit(&g_crash_handled, memory_order_release);
}

void pantrixcrash_set_foreground(bool foreground) {
    g_foreground = foreground ? 1 : 0;
}

bool pantrixcrash_get_foreground(void) {
    return g_foreground != 0;
}

void pantrixcrash_set_record_path(const char *directory) {
    // Rendered at install (normal context); snprintf with %s/%d is fine here, never from a handler.
    if (directory != NULL) {
        snprintf(g_record_path, sizeof(g_record_path), "%s/crash-%d.pcrx", directory, getpid());
    } else {
        g_record_path[0] = '\0';
    }
}

const char *pantrixcrash_get_record_path(void) {
    return g_record_path;
}

// MARK: - Crash-time attribution staging (seqlock, snapshot-by-value)

/// Copies `src` (or "" if NULL) into `dst`, always NUL-terminated, so a snapshot can never over-read.
/// `strlcpy` truncates safely to `size` and always leaves a NUL at `dst[size-1]`.
static void copy_bounded(char *dst, const char *src, size_t size) {
    strlcpy(dst, src ? src : "", size);
}

/// The single staged buffer, guarded by a seqlock. Setters run single-writer (the Swift relay serializes
/// them), so they need no lock — only the odd/even sequence publish. Static (BSS) zero-init, but the two
/// times start at -1 == "unknown" so an un-staged screen reads as absent, not duration 0.
static PantrixCrashStagedContext g_staged = { .screen_load_time = -1, .screen_duration = -1 };
static _Atomic uint32_t g_staged_seq = 0;   // even = stable, odd = write in progress

void pantrixcrash_set_session(const char *session_id) {
    uint32_t s = atomic_load_explicit(&g_staged_seq, memory_order_relaxed);
    atomic_store_explicit(&g_staged_seq, s + 1, memory_order_release);   // begin
    copy_bounded(g_staged.session_id, session_id, sizeof(g_staged.session_id));
    atomic_store_explicit(&g_staged_seq, s + 2, memory_order_release);   // end
}

void pantrixcrash_set_screen(const char *screen_id,
                             const char *screen_name,
                             const char *screen_category,
                             const char *screen_entered_at,
                             int64_t load_time,
                             int64_t duration) {
    uint32_t s = atomic_load_explicit(&g_staged_seq, memory_order_relaxed);
    atomic_store_explicit(&g_staged_seq, s + 1, memory_order_release);   // begin
    copy_bounded(g_staged.screen_id, screen_id, sizeof(g_staged.screen_id));
    copy_bounded(g_staged.screen_name, screen_name, sizeof(g_staged.screen_name));
    copy_bounded(g_staged.screen_category, screen_category, sizeof(g_staged.screen_category));
    copy_bounded(g_staged.screen_entered_at, screen_entered_at, sizeof(g_staged.screen_entered_at));
    g_staged.screen_load_time = load_time;
    g_staged.screen_duration = duration;
    atomic_store_explicit(&g_staged_seq, s + 2, memory_order_release);   // end
}

void pantrixcrash_snapshot_context(PantrixCrashStagedContext *out) {
    // Async-signal-safe seqlock read: bounded retries + memcpy, no locks/allocation. Default to "absent"
    // so a torn read that never stabilises (relentless writer) still yields a valid, bounded result.
    memset(out, 0, sizeof(*out));
    out->screen_load_time = -1;
    out->screen_duration = -1;
    for (int attempt = 0; attempt < 8; attempt++) {
        uint32_t s1 = atomic_load_explicit(&g_staged_seq, memory_order_acquire);
        if (s1 & 1u) { continue; }                       // a writer is mid-update
        memcpy(out, &g_staged, sizeof(*out));
        atomic_thread_fence(memory_order_acquire);       // keep the copy before the re-check
        uint32_t s2 = atomic_load_explicit(&g_staged_seq, memory_order_acquire);
        if (s1 == s2) { return; }                        // stable, consistent snapshot
    }
    // Fell through: `out` holds the last (possibly mixed) copy — still fixed-size + NUL-terminated.
}
