//
//  PantrixCrashSignal.h
//  PantrixCrash
//
//  The POSIX-signal fatal-crash catcher. Installs a sigaction handler (on a pre-allocated alternate
//  stack) for SIGSEGV/SIGABRT/SIGBUS/SIGILL/SIGFPE/SIGTRAP; on a fault it captures the crashed thread's
//  backtrace + the loaded images and writes a crash record, then restores the previous handlers and
//  re-raises so the process still terminates correctly (chaining, so it coexists with other reporters).
//

#ifndef PANTRIX_CRASH_SIGNAL_H
#define PANTRIX_CRASH_SIGNAL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Shared crash-capture primitives, used by both the signal catcher and the Mach exception catcher.

/// Strips a pointer-authentication code off a code pointer, so return addresses are usable for offline
/// symbolication.
///
/// The `__has_feature` test is the whole point, and `__has_include(<ptrauth.h>)` was the wrong one: the
/// header exists in every SDK, but the intrinsic compiles to **nothing** unless the target is arm64e —
/// and we ship arm64. We would still find PAC bits on the stack, because an arm64 app calls into the
/// arm64e system libraries (libdispatch, UIKit, …) that a crash or a hang usually sits inside, and those
/// sign the return addresses they push. So the arm64 build masks by hand: user-space addresses fit in 47
/// bits and the signature sits above them, which makes the mask exactly what `xpaci` would compute — and
/// a no-op on an address that was never signed. Same fix, same reasoning as KSCrash 2.6.0's
/// `kscpu_normaliseInstructionPointer`. Kept in lockstep with `MainThreadStackProviderImpl`'s Swift copy.
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#define PANTRIX_STRIP_RET(p) ((uintptr_t)ptrauth_strip((void *)(uintptr_t)(p), ptrauth_key_return_address))
#elif defined(__arm64__) || defined(__aarch64__)
#define PANTRIX_STRIP_RET(p) ((uintptr_t)(p) & 0x00007FFFFFFFFFFFULL)
#else
#define PANTRIX_STRIP_RET(p) ((uintptr_t)(p))
#endif

#define PANTRIX_MAX_FRAMES 128
// A modern app with several third-party SDKs loads 400-800 dyld images; capping at 512 silently truncated
// system images (and their frames became unsymbolicatable). The capture buffer is a static array of
// `PantrixCrashImage` (48 bytes each, borrowed path pointer), so 2048 costs ~96 KB of BSS per catcher —
// negligible, and it lets the reader see every system image a frame points into. See G2/A0 in
// Docs/CRASH_REPORT_PARITY_PLAN.md.
#define PANTRIX_MAX_IMAGES 2048

/// Frame-pointer stack walk shared by the signal + Mach catchers: records `pc`, then walks the fp chain
/// (each record is `{ saved_fp, return_address }`), PAC-stripping every address, with alignment +
/// strictly-increasing-fp + bounded-count guards. Returns the frame count (<= `max`). Async-signal-safe.
uint32_t pantrixcrash_walk_frames(uintptr_t pc, uintptr_t fp, uintptr_t *frames, uint32_t max);

/// Maps a fatal signal number to its name (e.g. "SIGSEGV"); "SIGNAL" for anything unrecognized.
const char *pantrixcrash_signal_name(int signum);

/// Installs the signal handlers. `record_directory` (NUL-terminated) is where the crash record is
/// written on a fault; the path is rendered once here (normal context). Idempotent.
void pantrix_crash_signal_install(const char *record_directory);

/// Restores the previous signal handlers this module installed. Async-signal-safe (sigaction only — it
/// does NOT free the alternate stack, which the handler may be running on).
void pantrix_crash_signal_uninstall(void);

/// TEST ONLY: forks a child that installs the handler, starts the image cache and `raise(signum)`s, so
/// the handler writes a record to `record_directory`; the parent's own handlers are untouched. Returns
/// the signal the child was terminated by (should equal `signum` after the handler re-raises), or -1 on
/// fork failure.
int pantrixcrash_test_fork_and_crash(const char *record_directory, int signum);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_SIGNAL_H */
