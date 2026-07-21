//
//  PantrixCrashC.h
//  PantrixCrash
//
//  The low-level, async-signal-safe crash-capture C layer for the opt-in PantrixCrash add-on.
//  It MUST stay a separate C-family target: the Swift runtime is not async-signal-safe (metadata
//  lookups, ARC, allocation are all forbidden in a signal handler), and SPM does not allow mixing
//  Swift with C/Obj-C/C++ in one target.
//
//  Phase 3 (this file): scaffolding only — the functions below are stubs. The real POSIX-signal /
//  NSException / C++-terminate handlers, the async-signal-safe record writer and the dyld binary-image
//  cache land in a later phase.
//

#ifndef PANTRIX_CRASH_C_H
#define PANTRIX_CRASH_C_H

// Umbrella: expose the whole C module surface.
#include "PantrixCrashRecord.h"
#include "PantrixCrashFileUtils.h"
#include "PantrixCrashImageCache.h"
#include "PantrixCrashState.h"
#include "PantrixCrashThread.h"
#include "PantrixCrashMach.h"
#include "PantrixCrashSignal.h"
#include "PantrixCrashNSException.h"
#include "PantrixCrashCPPException.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Installs the crash handlers. On a fatal crash the handler writes a fixed-layout record into a file
/// under `record_directory`, to be read and reported on the next launch. Chains any previously-installed
/// handlers so it coexists with other crash reporters. `record_directory` is a NUL-terminated UTF-8 path;
/// may be NULL (then nothing is armed).
void pantrix_crash_install(const char *record_directory);

/// Removes the crash handlers this module installed and restores the previous ones. Safe to call when
/// nothing was installed.
void pantrix_crash_uninstall(void);

/// Starts the background binary-image cache (dyld add/remove-image observers) so the crash path can emit
/// the image list (load address + UUID + path) for offline symbolication without calling `dladdr`
/// (which is not async-signal-safe). Idempotent.
void pantrix_crash_bic_start(void);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_C_H */
