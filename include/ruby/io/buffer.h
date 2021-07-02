/**
 * @file
 * @author     Samuel Williams
 * @date       Fri  2 Jul 2021 16:29:01 NZST
 * @copyright  Copyright (C) 2021 Samuel Williams
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#pragma once

#include "ruby/ruby.h"
#include "ruby/internal/config.h"

RUBY_SYMBOL_EXPORT_BEGIN

RUBY_EXTERN VALUE rb_cIOBuffer;
RUBY_EXTERN size_t RUBY_IO_BUFFER_PAGE_SIZE;

enum rb_io_buffer_flags {
    // The memory in the buffer is owned by someone else.
    RB_IO_BUFFER_EXTERNAL = 0,
    // The memory in the buffer is allocated internally.
    RB_IO_BUFFER_INTERNAL = 1,
    // The memory in the buffer is mapped.
    RB_IO_BUFFER_MAPPED = 2,

    // The buffer is locked and cannot be resized.
    RB_IO_BUFFER_LOCKED = 16,

    // The buffer mapping is private and will not impact other processes or the underlying file.
    RB_IO_BUFFER_PRIVATE = 32,

    // The buffer is read-only and cannot be modified.
    RB_IO_BUFFER_IMMUTABLE = 64
};

enum rb_io_buffer_endian {
    RB_IO_BUFFER_LITTLE_ENDIAN = 4,
    RB_IO_BUFFER_BIG_ENDIAN = 8,

#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    RB_IO_BUFFER_HOST_ENDIAN = RB_IO_BUFFER_LITTLE_ENDIAN,
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    RB_IO_BUFFER_HOST_ENDIAN = RB_IO_BUFFER_BIG_ENDIAN,
#elif REG_DWORD == REG_DWORD_LITTLE_ENDIAN
    RB_IO_BUFFER_HOST_ENDIAN = RB_IO_BUFFER_LITTLE_ENDIAN,
#elif REG_DWORD == REG_DWORD_BIG_ENDIAN
    RB_IO_BUFFER_HOST_ENDIAN = RB_IO_BUFFER_BIG_ENDIAN,
#endif

    RB_IO_BUFFER_NETWORK_ENDIAN = RB_IO_BUFFER_BIG_ENDIAN,
};

VALUE rb_io_buffer_new(void *base, size_t size, enum rb_io_buffer_flags flags);
VALUE rb_io_buffer_map(VALUE io, size_t size, off_t offset, enum rb_io_buffer_flags flags);

VALUE rb_io_buffer_lock(VALUE self);
VALUE rb_io_buffer_unlock(VALUE self);
VALUE rb_io_buffer_free(VALUE self);

void rb_io_buffer_get_mutable(VALUE self, void **base, size_t *size);
void rb_io_buffer_get_immutable(VALUE self, const void **base, size_t *size);

void rb_io_buffer_copy(VALUE self, VALUE source, size_t offset);
void rb_io_buffer_resize(VALUE self, size_t size, size_t preserve);
void rb_io_buffer_clear(VALUE self, uint8_t value, size_t offset, size_t length);

RUBY_SYMBOL_EXPORT_END
