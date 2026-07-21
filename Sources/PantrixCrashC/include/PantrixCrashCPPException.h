//
//  PantrixCrashCPPException.h
//  PantrixCrash
//
//  The uncaught-C++-exception catcher (std::set_terminate). Captures the exception type + description +
//  the crashed-thread backtrace and writes a crash record, then chains the previous terminate handler.
//  It shares the one-shot dedup gate, and — crucially — SKIPS Obj-C exceptions (which reach terminate via
//  the C++ ABI) because the NSException catcher already owns those, so a single uncaught NSException is
//  recorded once.
//
//  MVP: no __cxa_throw fishhook (so the backtrace is the terminate-handler stack, not the throw site).
//

#ifndef PANTRIX_CRASH_CPPEXCEPTION_H
#define PANTRIX_CRASH_CPPEXCEPTION_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Installs the C++ terminate handler, saving and chaining any previous one. Idempotent.
void pantrix_crash_cppexception_install(const char *record_directory);

/// Restores the previously-installed terminate handler.
void pantrix_crash_cppexception_uninstall(void);

/// TEST ONLY: writes a C++-terminate record with the given type/reason in-process (no terminate/abort).
/// Returns whether the record was written.
bool pantrixcrash_test_cpp_write(const char *record_directory, const char *type, const char *reason);

/// TEST ONLY: true if our terminate handler is the currently-installed one.
bool pantrixcrash_test_cpp_installed(void);

/// TEST ONLY: throws + catches a std::runtime_error and runs the terminate handler's exact extraction
/// (type name + rethrow-for-what()) in-process — no terminate/abort/fork — writing a record under
/// `record_directory`. Returns whether the record was written.
bool pantrixcrash_test_cpp_extract_write(const char *record_directory);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_CPPEXCEPTION_H */
