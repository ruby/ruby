#pragma once

#include <ruby/ruby.h>
#include <ruby/io/buffer.h>

RUBY_SYMBOL_EXPORT_BEGIN

/**
 * Wrap string_or_buffer as a read-only IO::Buffer view and invoke callback(buffer, argument).
 *
 * - IO::Buffer: callback is called directly with no wrapping.
 * - String: locked to prevent GC compaction from moving the backing memory,
 *   wrapped in a read-only IO::Buffer, callback called inside rb_ensure, buffer
 *   freed and string unlocked on exit.
 * - Other: TypeError raised.
 */
VALUE rb_io_buffer_for_reading(VALUE string_or_buffer, VALUE (*callback)(VALUE buffer, VALUE argument), VALUE argument);

/**
 * Wrap string_or_buffer as a writable IO::Buffer view and invoke callback(buffer, argument).
 *
 * - Read-only IO::Buffer: ArgumentError raised.
 * - IO::Buffer: callback is called directly with no wrapping.
 * - String: locked, wrapped in a writable IO::Buffer, callback called inside
 *   rb_ensure, buffer freed and string unlocked on exit.
 * - Other: TypeError raised.
 */
VALUE rb_io_buffer_for_writing(VALUE string_or_buffer, VALUE (*callback)(VALUE buffer, VALUE argument), VALUE argument);

RUBY_SYMBOL_EXPORT_END
