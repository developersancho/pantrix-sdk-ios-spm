//
//  PantrixCrashFileUtils.h
//  PantrixCrash
//
//  A minimal async-signal-safe buffered writer (KSCrash's KSFileUtils buffered-writer, scoped down):
//  a caller-provided fixed buffer + open(O_EXCL) / write()-loop / close, no stdio, no malloc, no locks.
//  Safe to drive from a signal handler.
//

#ifndef PANTRIX_CRASH_FILE_UTILS_H
#define PANTRIX_CRASH_FILE_UTILS_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int fd;
    char *buffer;         /* caller-owned scratch */
    int buffer_length;
    int position;
} PantrixBufferedWriter;

/// Opens `path` fresh (O_WRONLY|O_CREAT|O_EXCL, 0644 — atomic create, no symlink follow, no truncate) and
/// initializes the writer over `buffer`. Returns false if the open fails or the args are invalid.
bool pantrix_bw_open(PantrixBufferedWriter *writer, const char *path, char *buffer, int buffer_length);

/// Buffers `length` bytes, flushing as needed; data larger than the buffer is written straight through.
/// Returns false on write error.
bool pantrix_bw_write(PantrixBufferedWriter *writer, const void *data, int length);

/// Flushes the buffer to the fd. Returns false on write error.
bool pantrix_bw_flush(PantrixBufferedWriter *writer);

/// Flushes and closes the fd. Returns false if the final flush OR the close reports an error — for a
/// fully-buffered small record this is the only signal that the bytes actually reached disk.
bool pantrix_bw_close(PantrixBufferedWriter *writer);

#ifdef __cplusplus
}
#endif

#endif /* PANTRIX_CRASH_FILE_UTILS_H */
