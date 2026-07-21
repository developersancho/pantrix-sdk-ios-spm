//
//  PantrixCrashThread.h
//  PantrixCrash
//
//  Crash anında çöken thread'in ADINI çözer. Ayrı bir dosya, çünkü dört catcher da (Mach / signal /
//  NSException / C++) aynı sorunu paylaşıyor ve her biri farklı bir async-safety kısıtı altında:
//
//    · Signal handler async-signal-safe olmak zorunda — `pthread_getname_np` orada YASAK.
//    · Mach handler sağlıklı, ayrı bir thread'de koşar ve çöken thread'e SELF değildir; onun adını
//      `pthread_getname_np(pthread_self())` ile ALAMAZ, kernel'e Mach trap'iyle sormak gerekir.
//    · NSException / C++ çöken thread'in kendisinde, NORMAL context'te koşar; orada `pthread_getname_np`
//      serbest.
//
//  Ortak nokta: main-thread crash'inde ad "main" olmalı (Android `thread.name` paritesi), ama
//  main tespiti de context'e göre değişir. Bunu tek yerde, enable anında saklanan main-thread id ile
//  çözüyoruz — böylece dört catcher da aynı, async-safe yardımcıyı çağırır.
//

#ifndef PANTRIX_CRASH_THREAD_H
#define PANTRIX_CRASH_THREAD_H

#include <stdint.h>
#include <stddef.h>

// C++ catcher (PantrixCrashCPPException.mm) bu C fonksiyonlarını çağırıyor — `extern "C"` olmadan
// C++ derleyicisi adları mangle'lar ve link kopar.
#ifdef __cplusplus
extern "C" {
#endif

/// `enable()` sırasında (MAIN thread'de) çağrılır ve main-thread'in id'sini saklar. Crash anında
/// hiçbir catcher güvenle "bu main mi" diye soramaz (async-safety, ya da çöken thread self değil),
/// o yüzden cevabı önceden yakalıyoruz. `pantrix_crash_install`'ın ilk işi budur.
void pantrixcrash_capture_main_thread(void);

/// Çöken thread'in adını çözer — crash-time GÜVENLİ (malloc yok, kilit yok, ObjC yok).
///
/// - [pth_name] doluysa [buf]'a kopyalanıp döndürülür (catcher'ın kendi kaynağından aldığı ad).
/// - Boşsa ve [thread_id] saklanan main-thread id'sine eşitse sabit `"main"` döndürülür.
/// - Aksi halde NULL (writer bunu boş ada çevirir).
///
/// Dönen pointer ya [buf] ya bir string literal'dir; writer senkron kopyaladığı için [buf]'un
/// çağıranın stack'inde write anına kadar yaşaması yeterli.
const char *pantrixcrash_thread_name(uint64_t thread_id, const char *pth_name, char *buf, size_t buflen);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_THREAD_H */
