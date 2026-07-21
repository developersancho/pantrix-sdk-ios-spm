//
//  PantrixCrashRecord.h
//  PantrixCrash
//
//  The fixed-layout binary crash record written at crash time and read on the next launch. Deliberately
//  a compact binary blob (not JSON): every field is emitted with a bounded memcpy into a fixed on-stack
//  buffer + write(2), so the writer stays async-signal-safe. The reader (Swift, next launch) mirrors
//  this layout to build a `PantrixCrashReport`.
//
//  BYTE LAYOUT (all integers little-endian, no alignment padding):
//    Header:
//      u32 magic (PANTRIX_CRASH_MAGIC)
//      u16 version (PANTRIX_CRASH_FORMAT_VERSION)
//      u16 flags            bit0 = foreground
//      u32 crash_type       PANTRIX_CRASH_TYPE_*
//      i32 signum
//      i32 sigcode
//      u64 fault_address
//      u64 timestamp_ms     epoch milliseconds
//      u64 thread_id
//      u32 frame_count
//      u32 image_count
//      u16 type_len
//      u16 name_len
//      u16 reason_len
//    Payload (in order):
//      type   [type_len]    the signal/exception type string, e.g. "SIGSEGV" (no NUL)
//      name   [name_len]    crashed thread name
//      reason [reason_len]  message / reason
//      frames [frame_count x u64]                       raw return addresses (PAC already stripped)
//      images [image_count x { u64 load_address; u64 size; u8 uuid[16]; u16 path_len; char path[path_len] }]
//    Trailer (version >= 2 only, appended AFTER images so v1 readers see a byte-identical prefix):
//      u16 session_id_len
//      u16 screen_id_len
//      u16 screen_name_len
//      u16 screen_category_len
//      u16 screen_entered_at_len
//      i64 screen_load_time    epoch/relative ms; -1 == unknown
//      i64 screen_duration     ms; -1 == unknown
//      session_id       [session_id_len]        crash-time session id
//      screen_id        [screen_id_len]         crash-time screen id
//      screen_name      [screen_name_len]       crash-time screen name
//      screen_category  [screen_category_len]   crash-time screen type name (e.g. "VIEW_CONTROLLER")
//      screen_entered_at[screen_entered_at_len] crash-time screen enteredAt (ISO-8601)
//    Trailer (version >= 3 only, appended AFTER the v2 trailer, same reason):
//      image_count x { i32 cputype; i32 cpusubtype }   parallel to `images`, same order
//    Trailer (version >= 4 only, appended AFTER the v3 trailer, same append-only reason):
//      u32 other_thread_count
//      other_thread_count x { u16 name_len; char name[name_len]; u32 frame_count; u64 frames[frame_count] }
//      The crashed thread is NOT repeated here — it is the header's thread_id / name / frames. This trailer
//      is the OTHER live threads (matching Android's `ExceptionThread[]` shape). Only the Mach catcher fills
//      it, from a suspend-the-world snapshot; the signal / NSException / C++ catchers write count = 0.
//
//  `size` is the image's __TEXT segment vmsize; the reader maps a frame address to its image via the
//  half-open range [load_address, load_address + size). The v2 trailer carries the crash-TIME session +
//  screen (staged from a normal thread via PantrixCrashState) so a next-launch report is attributed to
//  the session/screen that actually crashed, not the launch session.
//
//  Every version APPENDS; no existing field ever moves. That keeps the v1/v2 parse path untouched — the
//  reader adds a "if version >= N, read more" step and cannot break what already worked. (An older reader
//  rejects a newer record outright on the `version <= PANTRIX_CRASH_FORMAT_VERSION` gate, so it never
//  half-parses one.)
//
//  v3's arch is a PARALLEL array rather than a field inside each image entry, purely to keep that
//  promise. The arch itself is NOT a symbolication input: a dSYM is found by LC_UUID alone, and each
//  slice carries its own, so slices are already distinct keys. It rides along as builds-UI metadata —
//  see D3 in Docs/CRASH_SYMBOLICATION_PLAN.md, which retracts the reason it was first captured for.
//

#ifndef PANTRIX_CRASH_RECORD_H
#define PANTRIX_CRASH_RECORD_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PANTRIX_CRASH_MAGIC 0x50435258u          /* 'P','C','R','X' as a LE u32 */
#define PANTRIX_CRASH_FORMAT_VERSION 4u          /* v4 appends the all-other-threads trailer */

#define PANTRIX_CRASH_TYPE_SIGNAL 0u
#define PANTRIX_CRASH_TYPE_NSEXCEPTION 1u
#define PANTRIX_CRASH_TYPE_CPP_TERMINATE 2u

/// One loaded binary image, for offline symbolication.
typedef struct {
    uint64_t load_address;
    uint64_t size;      /* __TEXT segment vmsize — the code range [load_address, load_address+size) */
    uint8_t uuid[16];
    const char *path;   /* NUL-terminated; may be NULL */
    int32_t cputype;    /* mach_header_64.cputype    — 0 when unknown */
    int32_t cpusubtype; /* mach_header_64.cpusubtype — 0 when unknown */
} PantrixCrashImage;

/// One NON-crashing thread's stack, for the v4 all-threads trailer. The crashed thread is carried by the
/// header (thread_id / name / frames), never here. `frames` are PAC-stripped return addresses; `name` may
/// be NULL. All pointers are borrowed and must stay valid for the write.
typedef struct {
    const char *name;
    const uintptr_t *frames;
    uint32_t frame_count;
} PantrixCrashThread;

/// The captured crash state handed to the writer. All pointers are borrowed (not owned) and must stay
/// valid for the duration of the write.
typedef struct {
    uint32_t crash_type;
    int32_t signum;
    int32_t sigcode;
    uint64_t fault_address;
    uint64_t timestamp_ms;
    uint64_t thread_id;
    bool foreground;
    const char *type;    /* e.g. "SIGSEGV" / NSException name; may be NULL */
    const char *name;    /* crashed thread name; may be NULL */
    const char *reason;  /* message; may be NULL */
    const uintptr_t *frames;
    uint32_t frame_count;
    const PantrixCrashImage *images;
    uint32_t image_count;
    /* Crash-time attribution (v2 trailer). All string pointers are borrowed and may be NULL. */
    const char *session_id;         /* crash-time session id */
    const char *screen_id;          /* crash-time screen id */
    const char *screen_name;        /* crash-time screen name */
    const char *screen_category;    /* crash-time screen type name, e.g. "VIEW_CONTROLLER" */
    const char *screen_entered_at;  /* crash-time screen enteredAt, ISO-8601 */
    int64_t screen_load_time;       /* crash-time screen load time (ms); -1 == unknown */
    int64_t screen_duration;        /* crash-time screen duration (ms); -1 == unknown */
    /* All-other-threads snapshot (v4 trailer). Borrowed; NULL / 0 when only the crashed thread was captured
       (the signal / NSException / C++ paths). Only the Mach catcher populates it. */
    const PantrixCrashThread *other_threads;
    uint32_t other_thread_count;
} PantrixCrashContext;

/// Serializes `ctx` to a fresh file at `path` in the layout above, async-signal-safely (open with
/// O_EXCL, write()-loop, close — no malloc / stdio / locks). Returns true on success.
bool pantrixcrash_write_report(const PantrixCrashContext *ctx, const char *path);

/// Test/fixture helper: builds a known synthetic context and writes it through `pantrixcrash_write_report`
/// so the format can be round-tripped from a unit test. Returns true on success.
bool pantrixcrash_write_sample_record(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_RECORD_H */
