//
//  PantrixCrashNSException.h
//  PantrixCrash
//
//  The uncaught-NSException catcher. Installs an NSUncaughtExceptionHandler that captures the exception
//  (name / reason / call-stack return addresses) + the loaded images, writes a crash record, then chains
//  the previously-installed handler so the runtime still aborts and other reporters run. It shares the
//  one-shot dedup gate with the signal catcher, so the abort()->SIGABRT that follows an uncaught
//  exception is not recorded a second time.
//
//  It runs SYNCHRONOUSLY on the crashing thread (not a POSIX signal context), so Obj-C messaging is
//  permitted here — only the record write goes through the shared async-safe writer.
//

#ifndef PANTRIX_CRASH_NSEXCEPTION_H
#define PANTRIX_CRASH_NSEXCEPTION_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Installs the uncaught-exception handler, saving and chaining any previous one. `record_directory` is
/// the shared crash-record location. Idempotent.
void pantrix_crash_nsexception_install(const char *record_directory);

/// Restores the previously-installed uncaught-exception handler.
void pantrix_crash_nsexception_uninstall(void);

/// TEST ONLY: raises + catches an NSException(name, reason) and runs the record path in-process (no
/// chaining, no abort), writing a record under `record_directory`. Returns true if a record was written.
bool pantrixcrash_test_nsexception_write(const char *record_directory, const char *name, const char *reason);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_NSEXCEPTION_H */
