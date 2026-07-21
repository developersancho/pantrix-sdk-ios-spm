//
//  PantrixCrashState.h
//  PantrixCrash
//
//  Process-wide crash-handling state shared by every catcher (signal / NSException / C++). The dedup
//  gate is the single most important correctness piece: one crash must be recorded once, even though it
//  can surface through several catchers (e.g. an uncaught NSException fires the NSException handler and
//  then abort() → SIGABRT). It uses `atomic_flag` specifically — the one type the C standard guarantees
//  is always lock-free and async-signal-safe.
//

#ifndef PANTRIX_CRASH_STATE_H
#define PANTRIX_CRASH_STATE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Claims the one-shot fatal-crash gate. Returns true to the FIRST caller only; every later caller
/// (another catcher, or the same on another thread) gets false and must not write a report. Async-safe.
bool pantrixcrash_begin_handling(void);

/// Clears the gate. TEST ONLY — the gate is intentionally one-shot per process in production.
void pantrixcrash_reset_handling(void);

/// Records the last-known app foreground state, sampled from a lifecycle callback on a normal thread and
/// read (as a `sig_atomic_t`) from the crash path. `UIApplication.applicationState` is ObjC/main-thread
/// only and unsafe in a handler, so it is cached here.
void pantrixcrash_set_foreground(bool foreground);
bool pantrixcrash_get_foreground(void);

/// Renders the shared crash-record path once, at install (normal context — never the handler): a
/// per-process file `<directory>/crash-<pid>.pcrx`. Every catcher writes to the same path (a process has
/// one fatal crash), so whichever catcher wins the dedup gate uses this.
void pantrixcrash_set_record_path(const char *directory);

/// The rendered record path (empty string before `set`). Async-signal-safe (returns a static buffer).
const char *pantrixcrash_get_record_path(void);

// MARK: - Crash-time attribution staging
//
// The current session id and current screen are pushed here from a NORMAL thread (session at install,
// screen on every navigation) and read from the crash path, so a next-launch report is attributed to the
// session/screen that actually crashed. A single buffer is protected by a seqlock; the setters run
// single-writer (the Swift relay serializes them). The crash path takes a by-value SNAPSHOT — it must NOT
// hold a live pointer into the buffer across the record write, or a concurrent screen change on a still-
// running sibling thread could overwrite the bytes being serialized.

/// A by-value copy of the staged attribution. Fixed-size, NUL-terminated fields — the crash handler owns
/// one on its stack for the whole write, so nothing it serializes can be mutated underneath it.
typedef struct {
    char session_id[64];
    char screen_id[128];
    char screen_name[256];
    char screen_category[32];
    char screen_entered_at[64];
    int64_t screen_load_time;   /* -1 == unknown */
    int64_t screen_duration;    /* -1 == unknown */
} PantrixCrashStagedContext;

/// Stages the crash-time session id. Pass NULL/"" for "no session". Single-writer.
void pantrixcrash_set_session(const char *session_id);

/// Stages the crash-time screen. Pass NULL/"" strings and -1 times for "no screen". Single-writer.
void pantrixcrash_set_screen(const char *screen_id,
                             const char *screen_name,
                             const char *screen_category,
                             const char *screen_entered_at,
                             int64_t load_time,
                             int64_t duration);

/// Copies a consistent snapshot of the staged session + screen into `out`. Async-signal-safe: a bounded
/// seqlock retry + memcpy, no locks / allocation / stdio. Empty strings and -1 times when nothing was
/// staged (or, after exhausting retries under a relentless writer, a still-bounded NUL-terminated copy).
void pantrixcrash_snapshot_context(PantrixCrashStagedContext *out);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_STATE_H */
