//
//  PantrixCrashWriter.c
//  PantrixCrash
//
//  Serializes a captured crash context to the fixed-layout binary record (see PantrixCrashRecord.h),
//  async-signal-safely — only the buffered writer (open/write/close) + memcpy/strnlen. No malloc, no
//  stdio, no Objective-C.
//

#include "PantrixCrashRecord.h"
#include "PantrixCrashFileUtils.h"

#include <mach/machine.h>   // CPU_TYPE_ARM64 — the sample record only

#include <string.h>

/// Bounded length of a possibly-NULL C string, capped so it fits a u16 length field.
static uint16_t bounded_len(const char *s) {
    return s ? (uint16_t)strnlen(s, 0xFFFF) : 0;
}

bool pantrixcrash_write_report(const PantrixCrashContext *ctx, const char *path) {
    if (ctx == NULL || path == NULL) {
        return false;
    }

    char buffer[2048];
    PantrixBufferedWriter writer;
    if (!pantrix_bw_open(&writer, path, buffer, (int)sizeof(buffer))) {
        return false;
    }

    uint32_t magic = PANTRIX_CRASH_MAGIC;
    uint16_t version = (uint16_t)PANTRIX_CRASH_FORMAT_VERSION;
    uint16_t flags = ctx->foreground ? 1u : 0u;
    uint16_t type_len = bounded_len(ctx->type);
    uint16_t name_len = bounded_len(ctx->name);
    uint16_t reason_len = bounded_len(ctx->reason);

    bool ok = true;
    ok = ok && pantrix_bw_write(&writer, &magic, sizeof(magic));
    ok = ok && pantrix_bw_write(&writer, &version, sizeof(version));
    ok = ok && pantrix_bw_write(&writer, &flags, sizeof(flags));
    ok = ok && pantrix_bw_write(&writer, &ctx->crash_type, sizeof(uint32_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->signum, sizeof(int32_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->sigcode, sizeof(int32_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->fault_address, sizeof(uint64_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->timestamp_ms, sizeof(uint64_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->thread_id, sizeof(uint64_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->frame_count, sizeof(uint32_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->image_count, sizeof(uint32_t));
    ok = ok && pantrix_bw_write(&writer, &type_len, sizeof(uint16_t));
    ok = ok && pantrix_bw_write(&writer, &name_len, sizeof(uint16_t));
    ok = ok && pantrix_bw_write(&writer, &reason_len, sizeof(uint16_t));

    if (ok && type_len) { ok = pantrix_bw_write(&writer, ctx->type, type_len); }
    if (ok && name_len) { ok = pantrix_bw_write(&writer, ctx->name, name_len); }
    if (ok && reason_len) { ok = pantrix_bw_write(&writer, ctx->reason, reason_len); }

    for (uint32_t i = 0; ok && i < ctx->frame_count; i++) {
        uint64_t address = (uint64_t)ctx->frames[i];   // fixed 8 bytes regardless of uintptr_t width
        ok = pantrix_bw_write(&writer, &address, sizeof(uint64_t));
    }

    for (uint32_t i = 0; ok && i < ctx->image_count; i++) {
        const PantrixCrashImage *image = &ctx->images[i];
        uint16_t path_len = bounded_len(image->path);
        ok = ok && pantrix_bw_write(&writer, &image->load_address, sizeof(uint64_t));
        ok = ok && pantrix_bw_write(&writer, &image->size, sizeof(uint64_t));
        ok = ok && pantrix_bw_write(&writer, image->uuid, 16);
        ok = ok && pantrix_bw_write(&writer, &path_len, sizeof(uint16_t));
        if (ok && path_len) { ok = pantrix_bw_write(&writer, image->path, path_len); }
    }

    // v2 trailer: crash-time session + screen, appended after images (v1 readers see an identical prefix).
    uint16_t session_id_len = bounded_len(ctx->session_id);
    uint16_t screen_id_len = bounded_len(ctx->screen_id);
    uint16_t screen_name_len = bounded_len(ctx->screen_name);
    uint16_t screen_category_len = bounded_len(ctx->screen_category);
    uint16_t screen_entered_at_len = bounded_len(ctx->screen_entered_at);
    ok = ok && pantrix_bw_write(&writer, &session_id_len, sizeof(uint16_t));
    ok = ok && pantrix_bw_write(&writer, &screen_id_len, sizeof(uint16_t));
    ok = ok && pantrix_bw_write(&writer, &screen_name_len, sizeof(uint16_t));
    ok = ok && pantrix_bw_write(&writer, &screen_category_len, sizeof(uint16_t));
    ok = ok && pantrix_bw_write(&writer, &screen_entered_at_len, sizeof(uint16_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->screen_load_time, sizeof(int64_t));
    ok = ok && pantrix_bw_write(&writer, &ctx->screen_duration, sizeof(int64_t));
    if (ok && session_id_len) { ok = pantrix_bw_write(&writer, ctx->session_id, session_id_len); }
    if (ok && screen_id_len) { ok = pantrix_bw_write(&writer, ctx->screen_id, screen_id_len); }
    if (ok && screen_name_len) { ok = pantrix_bw_write(&writer, ctx->screen_name, screen_name_len); }
    if (ok && screen_category_len) { ok = pantrix_bw_write(&writer, ctx->screen_category, screen_category_len); }
    if (ok && screen_entered_at_len) { ok = pantrix_bw_write(&writer, ctx->screen_entered_at, screen_entered_at_len); }

    // v3 trailer: one { cputype, cpusubtype } per image, parallel to `images` and in the same order.
    // Appended rather than folded into each image entry so the v1/v2 image layout never moves.
    for (uint32_t i = 0; ok && i < ctx->image_count; i++) {
        ok = ok && pantrix_bw_write(&writer, &ctx->images[i].cputype, sizeof(int32_t));
        ok = ok && pantrix_bw_write(&writer, &ctx->images[i].cpusubtype, sizeof(int32_t));
    }

    // v4 trailer: the OTHER live threads (the crashed one is the header). count = 0 for the non-Mach paths.
    ok = ok && pantrix_bw_write(&writer, &ctx->other_thread_count, sizeof(uint32_t));
    for (uint32_t i = 0; ok && i < ctx->other_thread_count; i++) {
        const PantrixCrashThread *thread = &ctx->other_threads[i];
        uint16_t tname_len = bounded_len(thread->name);
        ok = ok && pantrix_bw_write(&writer, &tname_len, sizeof(uint16_t));
        if (ok && tname_len) { ok = pantrix_bw_write(&writer, thread->name, tname_len); }
        ok = ok && pantrix_bw_write(&writer, &thread->frame_count, sizeof(uint32_t));
        for (uint32_t f = 0; ok && f < thread->frame_count; f++) {
            uint64_t address = (uint64_t)thread->frames[f];
            ok = pantrix_bw_write(&writer, &address, sizeof(uint64_t));
        }
    }

    // close() always runs (fd cleanup) even after an earlier failure; its result — the real write for a
    // fully-buffered record — folds into success.
    bool closed = pantrix_bw_close(&writer);
    return ok && closed;
}

bool pantrixcrash_write_sample_record(const char *path) {
    static const uintptr_t frames[] = { (uintptr_t)0x1044c8f30ull, (uintptr_t)0x1044c8000ull };

    PantrixCrashImage image;
    image.load_address = 0x104400000ull;
    image.size = 0x100000ull;   // covers the sample frames so the reader maps them into this image
    for (int i = 0; i < 16; i++) {
        image.uuid[i] = (uint8_t)i;
    }
    image.path = "/var/containers/Bundle/Application/MyApp.app/MyApp";
    image.cputype = CPU_TYPE_ARM64;
    image.cpusubtype = CPU_SUBTYPE_ARM64_ALL;

    PantrixCrashContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.crash_type = PANTRIX_CRASH_TYPE_SIGNAL;
    ctx.signum = 11;   // SIGSEGV
    ctx.sigcode = 1;
    ctx.fault_address = 0xdeadbeefull;
    ctx.timestamp_ms = 1600000000000ull;
    ctx.thread_id = 42;
    ctx.foreground = true;
    ctx.type = "SIGSEGV";
    ctx.name = "main";
    ctx.reason = "sample crash";
    ctx.frames = frames;
    ctx.frame_count = 2;
    ctx.images = &image;
    ctx.image_count = 1;
    ctx.session_id = "11111111-2222-3333-4444-555555555555";
    ctx.screen_id = "scr_home";
    ctx.screen_name = "HomeViewController";
    ctx.screen_category = "VIEW_CONTROLLER";
    ctx.screen_entered_at = "2026-07-15T10:00:00.000Z";
    ctx.screen_load_time = 120;
    ctx.screen_duration = 5000;

    // v4: one sample non-crashing thread so the reader can round-trip the all-threads trailer.
    static const uintptr_t thread2_frames[] = { (uintptr_t)0x1044c9000ull };
    static const PantrixCrashThread other[] = {
        { "com.apple.uikit.eventfetch-thread", thread2_frames, 1 },
    };
    ctx.other_threads = other;
    ctx.other_thread_count = 1;

    return pantrixcrash_write_report(&ctx, path);
}
