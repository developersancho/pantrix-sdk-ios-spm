//
//  PantrixCrashC.c
//  PantrixCrash
//
//  Top-level orchestration: the public C entry points the Swift facade drives, delegating to the
//  individual catchers. (NSException / C++ catchers are wired in as they land.)
//

#include "PantrixCrashC.h"
#include "PantrixCrashMach.h"
#include "PantrixCrashSignal.h"
#include "PantrixCrashNSException.h"
#include "PantrixCrashCPPException.h"
#include "PantrixCrashImageCache.h"
#include "PantrixCrashThread.h"

void pantrix_crash_install(const char *record_directory) {
    // MAIN thread id'sini ÖNCE yakala — bu fonksiyon `enable()` üzerinden main thread'de çağrılır, ve
    // crash anında hiçbir catcher "bu main mi" diye güvenle soramaz (async-safety / çöken thread self
    // değil). Cevabı burada saklayıp handler'ların async-safe okumasına bırakıyoruz.
    pantrixcrash_capture_main_thread();

    // Mach FIRST — it is the primary catcher; the kernel delivers hardware faults to the exception port
    // before the BSD signal, so the shared crash gate makes the ensuing signal handler no-op.
    pantrix_crash_mach_install(record_directory);
    pantrix_crash_signal_install(record_directory);
    pantrix_crash_nsexception_install(record_directory);
    pantrix_crash_cppexception_install(record_directory);
}

void pantrix_crash_uninstall(void) {
    pantrix_crash_cppexception_uninstall();
    pantrix_crash_nsexception_uninstall();
    pantrix_crash_signal_uninstall();
    pantrix_crash_mach_uninstall();   // LAST — reverse of install
}

void pantrix_crash_bic_start(void) {
    pcimg_start();
}
