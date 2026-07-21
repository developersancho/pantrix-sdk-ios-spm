//
//  PantrixCrashThread.c
//  PantrixCrash
//
//  Bkz. PantrixCrashThread.h — çöken thread adının tek, async-safe çözüm noktası.
//

#include "PantrixCrashThread.h"
#include <pthread.h>
#include <string.h>

// `pantrix_crash_install` (yani `enable()`) MAIN thread'de çağrılır, o yüzden burada okunan id main'in.
// Değişmez bir kimlik: bir kez yazılır, crash anında yalnızca okunur — kilit gerekmez.
static uint64_t g_main_thread_id = 0;

void pantrixcrash_capture_main_thread(void) {
    pthread_threadid_np(pthread_self(), &g_main_thread_id);
}

const char *pantrixcrash_thread_name(uint64_t thread_id, const char *pth_name, char *buf, size_t buflen) {
    // `strlcpy` async-signal-safe (malloc/kilit yok); adlandırılmış thread'ler (background queue'lar)
    // gerçek adlarıyla gelir.
    if (pth_name != NULL && pth_name[0] != '\0') {
        strlcpy(buf, pth_name, buflen);
        return buf;
    }
    // Ad yok: main thread ise "main" (iOS main thread'inin pthread adı genelde boştur, ama Android
    // `thread.name`'i "main" der — pariteyi burada kuruyoruz). String literal, kopyalanmaz.
    if (g_main_thread_id != 0 && thread_id == g_main_thread_id) {
        return "main";
    }
    return NULL;
}
