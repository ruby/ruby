#ifndef RUBY_MEMORY_VIEW_H
#define RUBY_MEMORY_VIEW_H 1
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Memory View.
 */

#include "ruby/internal/dllexport.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"
#include "ruby/intern.h"

enum ruby_memory_view_flags {
    RUBY_MEMORY_VIEW_SIMPLE            = 0,
    RUBY_MEMORY_VIEW_WRITABLE          = (1<<0),
    RUBY_MEMORY_VIEW_FORMAT            = (1<<1),
    RUBY_MEMORY_VIEW_MULTI_DIMENSIONAL = (1<<2),
    RUBY_MEMORY_VIEW_STRIDES           = (1<<3) | RUBY_MEMORY_VIEW_MULTI_DIMENSIONAL,
    RUBY_MEMORY_VIEW_ROW_MAJOR         = (1<<4) | RUBY_MEMORY_VIEW_STRIDES,
    RUBY_MEMORY_VIEW_COLUMN_MAJOR      = (1<<5) | RUBY_MEMORY_VIEW_STRIDES,
    RUBY_MEMORY_VIEW_ANY_CONTIGUOUS    = RUBY_MEMORY_VIEW_ROW_MAJOR | RUBY_MEMORY_VIEW_COLUMN_MAJOR,
    RUBY_MEMORY_VIEW_INDIRECT          = (1<<6) | RUBY_MEMORY_VIEW_STRIDES,
};

typedef struct {
    char format;
    int native_size_p;
    size_t offset;
    size_t size;
    size_t repeat;
} rb_memory_view_item_component_t;

typedef struct {
    /* The original object that have the memory exported via this memory view.
     * The consumer of this memory view has the responsibility to call rb_gc_mark
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
     * a RGB color triplet. */
    const char *format;

    /* The number of bytes in each element.
     * item_size should equal to rb_memory_view_item_size_from_format(format). */
    ssize_t item_size;

    struct {
        /* The array of rb_memory_view_item_component_t that describes the
         * item structure. */
        rb_memory_view_item_component_t *components;

        /* The number of components in an item. */
        ssize_t length;
    } item_desc;

    /* The number of dimension. */
    int ndim;

    /* ndim size array indicating the number of elements in each dimension.
     * This can be NULL when ndim == 1. */
    ssize_t *shape;

    /* ndim size array indicating the number of bytes to skip to go to the
     * next element in each dimension. */
    ssize_t *strides;

    /* The offset in each dimension when this memory view exposes a nested array.
     * Or, NULL when this memory view exposes a flat array. */
    ssize_t *sub_offsets;

    /* the private data for managing this exported memory */
    void *const private;
} rb_memory_view_t;

typedef int (* rb_memory_view_get_func_t)(VALUE obj, rb_memory_view_t *view, int flags);
typedef int (* rb_memory_view_release_func_t)(VALUE obj, rb_memory_view_t *view);
typedef int (* rb_memory_view_available_p_func_t)(VALUE obj);

typedef struct {
    rb_memory_view_get_func_t get_func;
    rb_memory_view_release_func_t release_func;
    rb_memory_view_available_p_func_t available_p_func;
} rb_memory_view_entry_t;

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* memory_view.c */
bool rb_memory_view_register(VALUE klass, const rb_memory_view_entry_t *entry);

#define rb_memory_view_is_contiguous(view) ( \
    rb_memory_view_is_row_major_contiguous(view) \
    || rb_memory_view_is_column_major_contiguous(view))

int rb_memory_view_is_row_major_contiguous(const rb_memory_view_t *view);
int rb_memory_view_is_column_major_contiguous(const rb_memory_view_t *view);
void rb_memory_view_fill_contiguous_strides(const int ndim, const int item_size, const ssize_t *const shape, ssize_t *const strides, const int row_major_p);
int rb_memory_view_init_as_byte_array(rb_memory_view_t *view, VALUE obj, void *data, const ssize_t len, const int readonly);
ssize_t rb_memory_view_parse_item_format(const char *format,
                                         rb_memory_view_item_component_t **members,
                                         ssize_t *n_members, const char **err);
ssize_t rb_memory_view_item_size_from_format(const char *format, const char **err);
void *rb_memory_view_get_item_pointer(rb_memory_view_t *view, const ssize_t *indices);

int rb_memory_view_available_p(VALUE obj);
int rb_memory_view_get(VALUE obj, rb_memory_view_t* memory_view, int flags);
int rb_memory_view_release(VALUE obj, rb_memory_view_t* memory_view);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_BUFFER_H */
