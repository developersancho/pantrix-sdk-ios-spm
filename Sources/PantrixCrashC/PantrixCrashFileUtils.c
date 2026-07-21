//
//  PantrixCrashFileUtils.c
//  PantrixCrash
//
//  See PantrixCrashFileUtils.h. Async-signal-safe: only open/write/close + memcpy.
//

#include "PantrixCrashFileUtils.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

/// Writes exactly `length` bytes, looping over partial writes and retrying on EINTR. Returns false on a
/// hard error. Only write(2) — async-signal-safe.
static bool write_all(int fd, const char *bytes, int length) {
    while (length > 0) {
        ssize_t written = write(fd, bytes, (size_t)length);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        if (written == 0) {
            return false;   // no progress (unexpected for a regular file) — don't spin
        }
        bytes += written;
        length -= (int)written;
    }
    return true;
}

bool pantrix_bw_open(PantrixBufferedWriter *writer, const char *path, char *buffer, int buffer_length) {
    if (writer == NULL || path == NULL || buffer == NULL || buffer_length <= 0) {
        return false;
    }
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (fd < 0) {
        return false;
    }
    writer->fd = fd;
    writer->buffer = buffer;
    writer->buffer_length = buffer_length;
    writer->position = 0;
    return true;
}

bool pantrix_bw_flush(PantrixBufferedWriter *writer) {
    if (writer == NULL || writer->fd < 0) {
        return false;
    }
    if (writer->position > 0) {
        bool ok = write_all(writer->fd, writer->buffer, writer->position);
        // Consume the buffer either way: on failure we discard it so a later flush (e.g. from close)
        // can't re-emit an already-partially-written prefix (clean truncation, not duplicated garbage).
        writer->position = 0;
        return ok;
    }
    return true;
}

bool pantrix_bw_write(PantrixBufferedWriter *writer, const void *data, int length) {
    if (writer == NULL || writer->fd < 0 || data == NULL || length < 0) {
        return false;
    }
    if (length == 0) {
        return true;
    }
    // Too big to buffer: flush what we have, then write straight through.
    if (length >= writer->buffer_length) {
        if (!pantrix_bw_flush(writer)) {
            return false;
        }
        return write_all(writer->fd, (const char *)data, length);
    }
    // Won't fit in what's left: flush first.
    if (writer->position + length > writer->buffer_length) {
        if (!pantrix_bw_flush(writer)) {
            return false;
        }
    }
    memcpy(writer->buffer + writer->position, data, (size_t)length);
    writer->position += length;
    return true;
}

bool pantrix_bw_close(PantrixBufferedWriter *writer) {
    if (writer == NULL || writer->fd < 0) {
        return false;
    }
    // The final flush is where a fully-buffered small record (i.e. essentially every crash record) is
    // actually written, so its result — and close()'s, which can surface a deferred write error — are
    // the ones that matter. Both must be reported, not swallowed.
    bool flushed = pantrix_bw_flush(writer);
    bool closed = (close(writer->fd) == 0);
    writer->fd = -1;
    return flushed && closed;
}
