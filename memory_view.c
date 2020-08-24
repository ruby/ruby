/**********************************************************************

  memory_view.c - Memory View

  Copyright (C) 2020 Kenta Murata <mrkn@mrkn.jp>

**********************************************************************/

#include "internal.h"
#include "internal/util.h"
#include "ruby/memory_view.h"

static ID id_memory_view;

static const rb_data_type_t memory_view_entry_data_type = {
    "memory_view",
    {
	0,
	0,
	0,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

/* Register memory view functions for the given class */
bool
rb_memory_view_register(VALUE klass, const rb_memory_view_entry_t *entry) {
    VALUE entry_obj = rb_ivar_get(klass, id_memory_view);
    if (! NIL_P(entry_obj)) {
        rb_warning("Duplicated registration of memory_view to %"PRIsVALUE, klass);
        return 0;
    }
    else {
        entry_obj = TypedData_Wrap_Struct(0, &memory_view_entry_data_type, (void *)entry);
        rb_ivar_set(klass, id_memory_view, entry_obj);
        return 1;
    }
}

/* Examine whether the given memory view has row-major order strides. */
int
rb_memory_view_is_row_major_contiguous(const rb_memory_view_t *view)
{
    const ssize_t ndim = view->ndim;
    const ssize_t *shape = view->shape;
    const ssize_t *strides = view->strides;
    ssize_t n = view->item_size;
    ssize_t i;
    for (i = ndim - 1; i >= 0; --i) {
        if (strides[i] != n) return 0;
        n *= shape[i];
    }
    return 1;
}

/* Examine whether the given memory view has column-major order strides. */
int
rb_memory_view_is_column_major_contiguous(const rb_memory_view_t *view)
{
    const ssize_t ndim = view->ndim;
    const ssize_t *shape = view->shape;
    const ssize_t *strides = view->strides;
    ssize_t n = view->item_size;
    ssize_t i;
    for (i = 0; i < ndim; ++i) {
        if (strides[i] != n) return 0;
        n *= shape[i];
    }
    return 1;
}

/* Initialize strides array to represent the specified contiguous array. */
void
rb_memory_view_fill_contiguous_strides(const int ndim, const int item_size, const ssize_t *const shape, ssize_t *const strides, const int row_major_p)
{
    ssize_t i, n = item_size;
    if (row_major_p) {
        for (i = ndim - 1; i >= 0; --i) {
            strides[i] = n;
            n *= shape[i];
        }
    }
    else {  // column-major
        for (i = 0; i < ndim; ++i) {
            strides[i] = n;
            n *= shape[i];
        }
    }
}

/* Initialize view to expose a simple byte array */
int
rb_memory_view_init_as_byte_array(rb_memory_view_t *view, VALUE obj, void *data, const ssize_t len, const int readonly)
{
    view->obj = obj;
    view->data = data;
    view->len = len;
    view->readonly = readonly;
    view->format = NULL;
    view->item_size = 1;
    view->ndim = 1;
    view->shape = NULL;
    view->strides = NULL;
    view->sub_offsets = NULL;
    *((void **)&view->private) = NULL;

    return 1;
}

/* Return the item size. */
ssize_t
rb_memory_view_item_size_from_format(const char *format, const char **err)
{
    if (format == NULL) return 1;

    ssize_t size = 0;
    while (*format) {
        const char *s = format;
        ssize_t count = 0;

        int ch = *format;
        if ('0' <= ch && ch <= '9') {
            while ('0' <= (ch = *format) && ch <= '9') {
                count = 10*count + ruby_digit36_to_number_table[ch];
                ++format;
            }
        }
        else {
            count = 1;
        }

        ssize_t n = 0;
        switch (*format) {
          case 'x':  // padding
            n += count;
            break;

          case 'c':  // signed char
          case 'C':  // unsigned char
            n += count * sizeof(char);
            break;

          case 's':  // s for int16_t, s! for signed short
          case 'S':  // S for uint16_t, S! for unsigned short
            if (format[1] == '!') {
                ++format;
                n += count * sizeof(short);
                break;
            }
            // fall through

          case 'n':  // n for big-endian 16bit unsigned integer
          case 'v':  // v for little-endian 16bit unsigned integer
            n += count * 2;
            break;

          case 'i':  // i and i! for signed int
          case 'I':  // I and I! for unsigned int
            if (format[1] == '!') ++format;
            n += count * sizeof(int);
            break;

          case 'l':  // l for int32_t, l! for signed long
          case 'L':  // L for uint32_t, L! for unsigned long
            if (format[1] == '!') {
                ++format;
                n += count * sizeof(long);
                break;
            }
            // fall through

          case 'N':  // N for big-endian 32bit unsigned integer
          case 'V':  // V for little-endian 32bit unsigned integer
          case 'f':  // f for native float
          case 'e':  // e for little-endian float
          case 'g':  // g for big-endian float
            n += 4;
            break;

          case 'q':  // q for int64_t, q! for signed long long
          case 'Q':  // Q for uint64_t, Q! for unsigned long long
            if (format[1] == '!') {
                ++format;
                n += count * sizeof(LONG_LONG);
                break;
            }
            // fall through

          case 'd':  // d for native double
          case 'E':  // E for little-endian double
          case 'G':  // G for big-endian double
            n += count * 8;
            break;

          case 'j':  // j for intptr_t
          case 'J':  // J for uintptr_t
            n += count * sizeof(intptr_t);
            break;

          default:
            if (err) *err = s;
            return -1;
        }

        size += n;
        ++format;
    }

    return size;
}

/* Return the pointer to the item located by the given indices. */
void *
rb_memory_view_get_item_pointer(rb_memory_view_t *view, const ssize_t *indices)
{
    uint8_t *ptr = view->data;

    if (view->ndim == 1) {
        return ptr + indices[0] * view->item_size;
    }

    assert(view->shape != NULL);

    int i;
    if (view->strides == NULL) {
        // row-major contiguous array
        for (i = 0; i < view->ndim; ++i) {
            ptr += indices[i] * view->shape[i] * view->item_size;
        }
    }
    else if (view->sub_offsets == NULL) {
        // flat strided array
        for (i = 0; i < view->ndim; ++i) {
            ptr += indices[i] * view->strides[i];
        }
    }
    else {
        // indirect strided array
        for (i = 0; i < view->ndim; ++i) {
            ptr += indices[i] * view->strides[i];
            if (view->sub_offsets[i] >= 0) {
                ptr = *(uint8_t **)ptr + view->sub_offsets[i];
            }
        }
    }

    return ptr;
}

static const rb_memory_view_entry_t *
lookup_memory_view_entry(VALUE klass) {
    VALUE entry_obj = rb_ivar_get(klass, id_memory_view);
    while (NIL_P(entry_obj)) {
        klass = rb_class_get_superclass(klass);

        if (klass == rb_cBasicObject || klass == rb_cObject)
            return NULL;

        entry_obj = rb_ivar_get(klass, id_memory_view);
    }

    if (! rb_typeddata_is_kind_of(entry_obj, &memory_view_entry_data_type))
        return NULL;

    return (const rb_memory_view_entry_t *)RTYPEDDATA_DATA(entry_obj);
}

/* Examine whether the given object supports memory view. */
int
rb_memory_view_available_p(VALUE obj)
{
    VALUE klass = CLASS_OF(obj);
    const rb_memory_view_entry_t *entry = lookup_memory_view_entry(klass);
    if (entry)
        return (* entry->available_p_func)(obj);
    else
        return 0;
}

/* Obtain a memory view from obj, and substitute the information to view. */
int
rb_memory_view_get(VALUE obj, rb_memory_view_t* view, int flags)
{
    VALUE klass = CLASS_OF(obj);
    const rb_memory_view_entry_t *entry = lookup_memory_view_entry(klass);
    if (entry)
        return (*entry->get_func)(obj, view, flags);
    else
        return 0;
}

/* Release the memory view obtained from obj. */
int
rb_memory_view_release(VALUE obj, rb_memory_view_t* view)
{
    VALUE klass = CLASS_OF(obj);
    const rb_memory_view_entry_t *entry = lookup_memory_view_entry(klass);
    if (entry)
        return (*entry->release_func)(obj, view);
    else
        return 0;
}

void
Init_MemoryView(void)
{
    id_memory_view = rb_intern("__memory_view__");
}
