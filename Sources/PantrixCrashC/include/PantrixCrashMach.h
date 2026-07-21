//
//  PantrixCrashMach.h
//  PantrixCrash
//
//  The Mach exception catcher — the PRIMARY fatal-crash handler. The kernel delivers a hardware fault
//  (EXC_BAD_ACCESS / EXC_BAD_INSTRUCTION / EXC_ARITHMETIC / EXC_BREAKPOINT) to a task exception port
//  BEFORE it synthesizes the corresponding BSD signal, and it does so on a dedicated healthy thread with
//  its own stack — so it catches faults the signal handler can't (a corrupted signal-stack / stack
//  overflow) and runs off the crashed thread entirely.
//
//  It shares the one-shot crash gate with the signal catcher: a fault caught here is recorded once, and
//  the ensuing signal no-ops. On a fault we restore the previously-registered exception ports and reply
//  KERN_FAILURE, so the process still dies through the OS with the correct signal. Under a debugger (which
//  owns the exception ports) we do not install — the signal catcher remains as the fallback.
//

#ifndef PANTRIX_CRASH_MACH_H
#define PANTRIX_CRASH_MACH_H

#ifdef __cplusplus
extern "C" {
#endif

/// Installs the Mach exception handler (allocates a port, registers it for the hardware-fault mask, and
/// spawns the handler thread). `record_directory` is where the crash record is written. Idempotent.
/// No-op when a debugger is attached (it owns the exception ports).
void pantrix_crash_mach_install(const char *record_directory);

/// Restores the previously-registered task exception ports and tears down the handler thread. Does NOT
/// deallocate the exception port (deallocating it can hang on a later crash — reused on re-install).
void pantrix_crash_mach_uninstall(void);

/// TEST ONLY: forks a child that installs the Mach handler and triggers a REAL EXC_BAD_ACCESS (a directed
/// `raise()` would bypass the exception port). The child dies from the forwarded signal; returns the
/// terminating signal (SIGSEGV), or -1 on fork failure.
int pantrixcrash_test_mach_fork_and_crash(const char *record_directory);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_MACH_H */
