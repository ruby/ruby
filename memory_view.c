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
    Check_Type(klass, T_CLASS);
    VALUE entry_obj = rb_ivar_get(klass, id_memory_view);
    if (! NIL_P(entry_obj)) {
        rb_warning("Duplicated registration of memory view to %"PRIsVALUE, klass);
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
rb_memory_view_fill_contiguous_strides(const int ndim, const int item_size, const ssize_t *const shape, const int row_major_p, ssize_t *const strides)
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

#ifdef HAVE_TRUE_LONG_LONG
static const char native_types[] = "sSiIlLqQjJ";
#else
static const char native_types[] = "sSiIlLjJ";
#endif
static const char endianness_types[] = "sSiIlLqQjJ";

typedef enum {
    ENDIANNESS_NATIVE,
    ENDIANNESS_LITTLE,
    ENDIANNESS_BIG
} endianness_t;

static ssize_t
get_format_size(const char *format, bool *native_p, ssize_t *alignment, endianness_t *endianness, VALUE *error)
{
    RUBY_ASSERT(format != NULL);
    RUBY_ASSERT(native_p != NULL);
    RUBY_ASSERT(endianness != NULL);

    *native_p = false;

    const int type_char = *format;

    int i = 1;
    while (format[i]) {
        switch (format[i]) {
          case '!':
            if (strchr(native_types, type_char)) {
                *native_p = true;
                ++i;
            }
            else {
                if (error) {
                    *error = rb_exc_new_str(rb_eArgError,
                                            rb_sprintf("Unable to specify native size for '%c'", type_char));
                }
                return -1;
            }
            continue;

          case '<':
          case '>':
            if (!strchr(endianness_types, type_char)) {
                if (error) {
                    *error = rb_exc_new_str(rb_eArgError,
                                            rb_sprintf("Unable to specify endianness for '%c'", type_char));
                }
                return -1;
            }
            if (*endianness != ENDIANNESS_NATIVE) {
                *error = rb_exc_new_cstr(rb_eArgError, "Unable to use both '<' and '>' multiple times");
                return -1;
            }
            *endianness = (format[i] == '<') ? ENDIANNESS_LITTLE : ENDIANNESS_BIG;
            ++i;
            continue;

          default:
            break;
        }

        break;
    }

    switch (type_char) {
      case 'x':  // padding
        return 1;

      case 'c':  // signed char
      case 'C':  // unsigned char
        return sizeof(char);

      case 's':  // s for int16_t, s! for signed short
      case 'S':  // S for uint16_t, S! for unsigned short
        if (*native_p) {
            *alignment = RUBY_ALIGNOF(short);
            return sizeof(short);
        }
        // fall through

      case 'n':  // n for big-endian 16bit unsigned integer
      case 'v':  // v for little-endian 16bit unsigned integer
        *alignment = RUBY_ALIGNOF(int16_t);
        return 2;

      case 'i':  // i and i! for signed int
      case 'I':  // I and I! for unsigned int
        *alignment = RUBY_ALIGNOF(int);
        return sizeof(int);

      case 'l':  // l for int32_t, l! for signed long
      case 'L':  // L for uint32_t, L! for unsigned long
        if (*native_p) {
            *alignment = RUBY_ALIGNOF(long);
            return sizeof(long);
        }
        // fall through

      case 'N':  // N for big-endian 32bit unsigned integer
      case 'V':  // V for little-endian 32bit unsigned integer
        *alignment = RUBY_ALIGNOF(int32_t);
        return 4;

      case 'f':  // f for native float
      case 'e':  // e for little-endian float
      case 'g':  // g for big-endian float
        *alignment = RUBY_ALIGNOF(float);
        return sizeof(float);

      case 'q':  // q for int64_t, q! for signed long long
      case 'Q':  // Q for uint64_t, Q! for unsigned long long
        if (*native_p) {
            *alignment = RUBY_ALIGNOF(LONG_LONG);
            return sizeof(LONG_LONG);
        }
        *alignment = RUBY_ALIGNOF(int64_t);
        return 8;

      case 'd':  // d for native double
      case 'E':  // E for little-endian double
      case 'G':  // G for big-endian double
        *alignment = RUBY_ALIGNOF(double);
        return sizeof(double);

      case 'j':  // j for intptr_t
      case 'J':  // J for uintptr_t
        *alignment = RUBY_ALIGNOF(intptr_t);
        return sizeof(intptr_t);

      default:
        *alignment = -1;
        if (error) {
            *error = rb_exc_new_str(rb_eArgError, rb_sprintf("Invalid type character '%c'", type_char));
        }
        return -1;
    }
}

ssize_t
rb_memory_view_parse_item_format(const char *format,
                                 rb_memory_view_item_component_t **members,
                                 ssize_t *n_members, const char **err)
{
    if (format == NULL) return 1;

    VALUE error = Qnil;
    ssize_t total = 0;
    ssize_t len = 0;
    bool alignment = false;

    const char *p = format;
    if (*p == '|') {  // alginment specifier
        alignment = true;
        ++format;
        ++p;
    }
    while (*p) {
        const char *q = p;
        ssize_t count = 0;

        // ignore spaces
        if (ISSPACE(*p)) {
            while (ISSPACE(*p)) ++p;
            continue;
        }

        bool native_size_p = false;
        ssize_t alignment_size = 0;
        endianness_t endianness = ENDIANNESS_NATIVE;
        const ssize_t size = get_format_size(p, &native_size_p, &alignment_size, &endianness, &error);
        if (size < 0) {
            if (err) *err = q;
            return -1;
        }

        const int type_char = *p;
        p += 1 + (int)native_size_p + (endianness != ENDIANNESS_NATIVE);

        // count modifiers
        int ch = *p;
        if ('0' <= ch && ch <= '9') {
            while ('0' <= (ch = *p) && ch <= '9') {
                count = 10*count + ruby_digit36_to_number_table[ch];
                ++p;
            }
        }
        else {
            count = 1;
        }

        ssize_t padding = 0;
        if (alignment && alignment_size > 1) {
            ssize_t res = total % alignment_size;
            if (res > 0) {
                padding = alignment_size - res;
            }
        }

        if (type_char != 'x') {
            ++len;
        }

        total += padding + size * count;
    }

    if (members && n_members) {
        rb_memory_view_item_component_t *buf = ALLOC_N(rb_memory_view_item_component_t, len);

        ssize_t i = 0, offset = 0;
        const char *p = format;
        while (*p) {
            ssize_t count = 0;

            bool native_size_p;
            ssize_t alignment_size = 0;
            endianness_t endianness = ENDIANNESS_NATIVE;
            const ssize_t size = get_format_size(p, &native_size_p, &alignment_size, &endianness, NULL);

            const int type_char = *p;
            p += 1 + (int)native_size_p + (endianness != ENDIANNESS_NATIVE);

            // count modifiers
            int ch = *p;
            if ('0' <= ch && ch <= '9') {
                while ('0' <= (ch = *p) && ch <= '9') {
                    count = 10*count + ruby_digit36_to_number_table[ch];
                    ++p;
                }
            }
            else {
                count = 1;
            }

            ssize_t padding = 0;
            if (alignment && alignment_size > 1) {
                ssize_t res = offset % alignment_size;
                if (res > 0) {
                    padding = alignment_size - res;
                }
            }

            offset += padding;

            if (type_char != 'x') {
#ifdef WORDS_BIGENDIAN
                bool little_endian_p = (endianness == ENDIANNESS_LITTLE);
#else
                bool little_endian_p = (endianness != ENDIANNESS_BIG);
#endif

                switch (type_char) {
                  case 'e':
                  case 'E':
                    little_endian_p = true;
                    break;
                  case 'g':
                  case 'G':
                    little_endian_p = false;
                    break;
                  default:
                    break;
                }

                buf[i++] = (rb_memory_view_item_component_t){
                    .format = type_char,
                    .native_size_p = native_size_p,
                    .little_endian_p = little_endian_p,
                    .offset = offset,
                    .size = size,
                    .repeat = count
                };
            }

            offset += size * count;
        }

        *members = buf;
        *n_members = len;
    }

    return total;
}

/* Return the item size. */
ssize_t
rb_memory_view_item_size_from_format(const char *format, const char **err)
{
    return rb_memory_view_parse_item_format(format, NULL, NULL, err);
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
rb_memory_view_release(rb_memory_view_t* view)
{
    VALUE klass = CLASS_OF(view->obj);
    const rb_memory_view_entry_t *entry = lookup_memory_view_entry(klass);
    if (entry)
        return (*entry->release_func)(view->obj, view);
    else
        return 0;
}

void
Init_MemoryView(void)
{
    id_memory_view = rb_intern("__memory_view__");
}
