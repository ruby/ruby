#ifndef RUBY_BUFFER_H
#define RUBY_BUFFER_H 1
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Buffer Protocol.
 */

#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

enum ruby_buffer_flags {
    RUBY_BUFFER_SIMPLE            = 0,
    RUBY_BUFFER_WRITABLE          = (1<<0),
    RUBY_BUFFER_FORMAT            = (1<<1),
    RUBY_BUFFER_MULTI_DIMENSIONAL = (1<<2),
    RUBY_BUFFER_STRIDES           = (1<<3) | RUBY_BUFFER_MULTI_DIMENSIONAL,
    RUBY_BUFFER_ROW_MAJOR         = (1<<4) | RUBY_BUFFER_STRIDES,
    RUBY_BUFFER_COLUMN_MAJOR      = (1<<5) | RUBY_BUFFER_STRIDES,
    RUBY_BUFFER_ANY_CONTIGUOUS    = RUBY_BUFFER_ROW_MAJOR | RUBY_BUFFER_COLUMN_MAJOR,
    RUBY_BUFFER_INDIRECT          = (1<<6) | RUBY_BUFFER_STRIDES,
};

typedef struct {
    /* The original object that have the memory exported via this buffer.
     * The consumer of this buffer has the responsibility to call rb_gc_mark
     * for preventing this obj collected by GC.  */
    VALUE obj;

    /* The pointer to the exported memory. */
    void *data;

    /* The number of bytes in data. */
    ssize_t len;

    /* 1 for readonly memory, 0 for writable memory. */
    int readonly;

    /* A string to describe the format of an element, or NULL for unsigned byte.
     * The format string is a sequence the following pack-template specifiers:
     *
     *   c, C, s, s!, S, S!, n, v, i, i!, I, I!, l, l!,
     *   L, L!, N, V, f, e, g, d, E, G, j, J
     *
     * For example, "dd" for an element that consists of two double values,
     * and "CCC" for an element that consists of three bytes, such as
     * a RGB color triplet.
     */
    const char *format;

    /* The number of bytes in each element.
     * item_size should equal to rb_buffer_item_size_from_format(format). */
    ssize_t item_size;

    /* The number of dimension. */
    int ndim;

    /* ndim size array indicating the number of elements in each dimension.
     * This can be NULL when ndim == 1. */
    ssize_t *shape;

    /* ndim size array indicating the number of bytes to skip to go to the
     * next element in each dimension. */
    ssize_t *strides;

    /* The offset in each dimension when this buffer exposes a nested array.
     * Or, NULL when this buffer exposes a flat array. */
    ssize_t *sub_offsets;

    /* the private data for managing this exported memory */
    void *const private;
} rb_buffer_t;

typedef int (* rb_get_buffer_func_t)(VALUE obj, rb_buffer_t *view, int flags);
typedef int (* rb_release_buffer_func_t)(VALUE obj, rb_buffer_t *view);

typedef struct {
    rb_get_buffer_func_t get_buffer_func;
    rb_release_buffer_func_t release_buffer_func;
} rb_buffer_protocol_entry_t;

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* buffer.c */
int rb_buffer_protocol_register_klass(VALUE klass, const buffer_protocol_entry_t *entry);

#define rb_buffer_is_contiguous(view) ( \
    rb_buffer_is_row_major_contiguous(view) \
    || rb_buffer_is_column_major_contiguous(view))

int rb_buffer_is_row_major_contiguous(const rb_buffer_t *view);
int rb_buffer_is_column_major_contiguous(const rb_buffer_t *view);
void rb_buffer_fill_contiguous_strides(int ndim, int item_size, const ssize_t *shape, ssize_t *strides, int row_major_p)
int rb_buffer_init_as_byte_array(rb_buffer_t *view, void *data, ssize_t len, int readonly, int flags);
ssize_t rb_buffer_item_size_from_format(const char *format);
void *rb_buffer_get_item_pointer(rb_buffer_t *view, ssize_t *indices);

int rb_obj_has_buffer_protocol(VALUE obj);
int rb_obj_get_buffer(VALUE obj, rb_buffer_t* buffer);
int rb_obj_release_buffer(VALUE obj, rb_buffer_t* buffer);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_BUFFER_H */
