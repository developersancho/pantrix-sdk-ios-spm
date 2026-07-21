//
//  PantrixCrashImageCache.h
//  PantrixCrash
//
//  Async-signal-safe access to the loaded binary images, for offline symbolication. Borrows dyld's own
//  append-only `all_image_infos->infoArray` (snapshotted once via task_info) — no `dladdr` (not
//  async-signal-safe; it takes dyld locks and can deadlock or underflow in a crash).
//

#ifndef PANTRIX_CRASH_IMAGE_CACHE_H
#define PANTRIX_CRASH_IMAGE_CACHE_H

#include "PantrixCrashRecord.h"

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Snapshots the dyld all-image-infos pointer (one `task_info` call). Call once at SDK activation, on a
/// normal thread — NOT from the crash path. Idempotent.
void pcimg_start(void);

/// Count of currently-loaded images (read from dyld's infoArray). Returns 0 before `pcimg_start`.
uint32_t pcimg_image_count(void);

/// Fills `out` (load_address, size = __TEXT vmsize, uuid, borrowed path) for the image at `index`.
/// Async-signal-safe: only reads dyld's borrowed array + walks the image's load commands. `out->path`
/// borrows dyld's string (valid for the image's lifetime). Returns false for a bad index or an
/// unreadable / non-64-bit image.
bool pcimg_get_image(uint32_t index, PantrixCrashImage *out);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_IMAGE_CACHE_H */
