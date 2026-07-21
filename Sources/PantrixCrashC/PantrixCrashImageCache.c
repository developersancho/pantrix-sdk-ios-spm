//
//  PantrixCrashImageCache.c
//  PantrixCrash
//
//  See PantrixCrashImageCache.h. Adapted from KSCrash's KSBinaryImageCache (release/2.6.0's core
//  insight: borrow dyld's infoArray, no dladdr), scoped down to what a telemetry recorder needs —
//  {load address, __TEXT size, uuid, path} per image. No precomputed segment cache, no notifier swizzle.
//
//  One addition over dyld's infoArray: dyld ITSELF. dyld is the loader, so it is NOT in its own
//  infoArray — which means the `start` / `_dyld_start` frames at the very bottom of EVERY thread's stack
//  map to no image and stay address-only ("." in the UI, unsymbolicatable). dyld's Mach-O header is in the
//  same struct (`dyldImageLoadAddress`), so we surface it as one extra trailing image; its own frames then
//  carry a module + load address + LC_UUID like any other, and resolve to `start`/`_dyld_start` once dyld's
//  symbols are ingested (DeviceSupport on device).
//

#include "PantrixCrashImageCache.h"

#include <mach/mach.h>
#include <mach/task.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>
#include <stdatomic.h>
#include <string.h>

/// dyld's all-image-infos, snapshotted once at start. Stored with release / loaded with acquire so a
/// crash on ANY thread sees the fully-initialized pointer; dyld's append-only-then-bump-count contract
/// is what makes the array itself safe to read from a signal handler.
static _Atomic(const struct dyld_all_image_infos *) g_all_image_infos = NULL;

void pcimg_start(void) {
    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (result != KERN_SUCCESS) {
        return;
    }
    const struct dyld_all_image_infos *infos =
        (const struct dyld_all_image_infos *)(uintptr_t)dyld_info.all_image_info_addr;
    atomic_store_explicit(&g_all_image_infos, infos, memory_order_release);
}

/// Fill `out` from a Mach-O header. `path` is borrowed (valid for the image's lifetime). Returns false if
/// the header is not a 64-bit Mach-O (iOS 13+ is 64-bit only; bail rather than misparse). Walks the load
/// commands once: LC_UUID → uuid, __TEXT LC_SEGMENT_64 → the code-range size. The bounds are self-
/// consistent with the header's OWN declared sizeofcmds/ncmds — no cmdsize==0 spin, no read past the
/// declared command region, no wrap (64-bit only). They do NOT prove the region is actually mapped: a wild
/// (post-dlclose) or scribbled header pointer can still fault here. That secondary fault is absorbed by the
/// signal handler's re-entrancy guard (which re-raises to the previous handler) — the same accepted tradeoff
/// KSCrash makes rather than vm_read-guarding every read.
static bool pcimg_fill_from_header(const struct mach_header *header, const char *path, PantrixCrashImage *out) {
    if (header == NULL) {
        return false;
    }
    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    if (header64->magic != MH_MAGIC_64) {
        return false;
    }

    out->load_address = (uint64_t)(uintptr_t)header;
    out->path = path;   // borrowed
    out->size = 0;
    // cputype/cpusubtype are builds-UI metadata, NOT a symbolication input — the symbolicator resolves a
    // dSYM by LC_UUID alone (each slice carries its own). See D3 in Docs/CRASH_SYMBOLICATION_PLAN.md.
    out->cputype = header64->cputype;
    out->cpusubtype = header64->cpusubtype;
    memset(out->uuid, 0, sizeof(out->uuid));

    uintptr_t cursor = (uintptr_t)header + sizeof(struct mach_header_64);
    uintptr_t end = cursor + header64->sizeofcmds;
    for (uint32_t i = 0; i < header64->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > end) {
            break;
        }
        const struct load_command *cmd = (const struct load_command *)cursor;
        uint32_t cmdsize = cmd->cmdsize;
        if (cmdsize < sizeof(struct load_command) || cursor + cmdsize > end) {
            break;
        }
        if (cmd->cmd == LC_UUID && cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uc = (const struct uuid_command *)cmd;
            memcpy(out->uuid, uc->uuid, sizeof(out->uuid));
        } else if (cmd->cmd == LC_SEGMENT_64 && cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cmd;
            if (strncmp(seg->segname, SEG_TEXT, sizeof(seg->segname)) == 0) {
                out->size = seg->vmsize;
            }
        }
        cursor += cmdsize;
    }
    return true;
}

uint32_t pcimg_image_count(void) {
    const struct dyld_all_image_infos *infos = atomic_load_explicit(&g_all_image_infos, memory_order_acquire);
    if (infos == NULL || infos->infoArray == NULL) {
        return 0;
    }
    // +1 for dyld itself (the trailing synthetic image; see the file header) when its header is available.
    uint32_t n = infos->infoArrayCount;
    if (infos->dyldImageLoadAddress != NULL) {
        n += 1;
    }
    return n;
}

bool pcimg_get_image(uint32_t index, PantrixCrashImage *out) {
    if (out == NULL) {
        return false;
    }
    const struct dyld_all_image_infos *infos = atomic_load_explicit(&g_all_image_infos, memory_order_acquire);
    if (infos == NULL || infos->infoArray == NULL) {
        return false;
    }

    if (index < infos->infoArrayCount) {
        const struct dyld_image_info *info = &infos->infoArray[index];
        return pcimg_fill_from_header(info->imageLoadAddress, info->imageFilePath, out);
    }
    // The one synthetic trailing image (index == infoArrayCount): dyld itself.
    if (index == infos->infoArrayCount && infos->dyldImageLoadAddress != NULL) {
        // `dyldPath` is version >= 15 (iOS 10.0+); every iOS 13+ target is newer, but short-circuit on the
        // version anyway and fall back to the canonical path. The path only feeds the module name
        // (basename "dyld") + the system flag — never symbolication, which keys on LC_UUID.
        const char *path = (infos->version >= 15 && infos->dyldPath != NULL) ? infos->dyldPath : "/usr/lib/dyld";
        return pcimg_fill_from_header(infos->dyldImageLoadAddress, path, out);
    }
    return false;
}
