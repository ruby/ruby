/**********************************************************************

  memory_view.c - Memory View

  Copyright (C) 2020 Kenta Murata <mrkn@mrkn.jp>

**********************************************************************/

#include "internal.h"
#include "internal/hash.h"
#include "internal/variable.h"
#include "internal/util.h"
#include "ruby/memory_view.h"

#define STRUCT_ALIGNOF(T, result) do { \
    (result) = RUBY_ALIGNOF(T); \
} while(0)

// Exported Object Registry

VALUE rb_memory_view_exported_object_registry = Qundef;

static int
exported_object_registry_mark_key_i(st_data_t key, st_data_t value, st_data_t data)
{
    rb_gc_mark(key);
    return ST_CONTINUE;
}

static void
exported_object_registry_mark(void *ptr)
{
    st_table *table = ptr;
    st_foreach(table, exported_object_registry_mark_key_i, 0);
}

static void
exported_object_registry_free(void *ptr)
{
    st_table *table = ptr;
    st_clear(table);
    st_free_table(table);
}

const rb_data_type_t rb_memory_view_exported_object_registry_data_type = {
    "memory_view/exported_object_registry",
    {
	exported_object_registry_mark,
	exported_object_registry_free,
	0,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static void
init_exported_object_registry(void)
{
    if (rb_memory_view_exported_object_registry != Qundef) {
        return;
    }

    st_table *table = rb_init_identtable();
    VALUE obj = TypedData_Wrap_Struct(
        0, &rb_memory_view_exported_object_registry_data_type, table);
    rb_gc_register_mark_object(obj);
    rb_memory_view_exported_object_registry = obj;
}

static inline st_table *
get_exported_object_table(void)
{
    st_table *table;
    TypedData_Get_Struct(rb_memory_view_exported_object_registry, st_table,
                         &rb_memory_view_exported_object_registry_data_type,
                         table);
    return table;
}

static int
update_exported_object_ref_count(st_data_t *key, st_data_t *val, st_data_t arg, int existing)
{
    if (existing) {
        *val += 1;
    }
    else {
        *val = 1;
    }
    return ST_CONTINUE;
}

static void
register_exported_object(VALUE obj)
{
    if (rb_memory_view_exported_object_registry == Qundef) {
        init_exported_object_registry();
    }

    st_table *table = get_exported_object_table();

    st_update(table, (st_data_t)obj, update_exported_object_ref_count, 0);
}

static void
unregister_exported_object(VALUE obj)
{
    if (rb_memory_view_exported_object_registry == Qundef) {
        return;
    }

    st_table *table = get_exported_object_table();

    st_data_t count;
    if (!st_lookup(table, (st_data_t)obj, &count)) {
        return;
    }

    if (--count == 0) {
        st_data_t key = (st_data_t)obj;
        st_delete(table, &key, &count);
    }
    else {
        st_insert(table, (st_data_t)obj, count);
    }
}

// MemoryView

static ID id_memory_view;

static const rb_data_type_t memory_view_entry_data_type = {
    "memory_view/entry",
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
    VALUE entry_obj = rb_ivar_lookup(klass, id_memory_view, Qnil);
    if (! NIL_P(entry_obj)) {
        rb_warning("Duplicated registration of memory view to %"PRIsVALUE, klass);
        return false;
    }
    else {
        entry_obj = TypedData_Wrap_Struct(0, &memory_view_entry_data_type, (void *)entry);
        rb_ivar_set(klass, id_memory_view, entry_obj);
        return true;
    }
}

/* Examine whether the given memory view has row-major order strides. */
bool
rb_memory_view_is_row_major_contiguous(const rb_memory_view_t *view)
{
    const ssize_t ndim = view->ndim;
    const ssize_t *shape = view->shape;
    const ssize_t *strides = view->strides;
    ssize_t n = view->item_size;
    ssize_t i;
    for (i = ndim - 1; i >= 0; --i) {
        if (strides[i] != n) return false;
        n *= shape[i];
    }
    return true;
}

/* Examine whether the given memory view has column-major order strides. */
bool
rb_memory_view_is_column_major_contiguous(const rb_memory_view_t *view)
{
    const ssize_t ndim = view->ndim;
    const ssize_t *shape = view->shape;
    const ssize_t *strides = view->strides;
    ssize_t n = view->item_size;
    ssize_t i;
    for (i = 0; i < ndim; ++i) {
        if (strides[i] != n) return false;
        n *= shape[i];
    }
    return true;
}

/* Initialize strides array to represent the specified contiguous array. */
void
rb_memory_view_fill_contiguous_strides(const ssize_t ndim, const ssize_t item_size, const ssize_t *const shape, const bool row_major_p, ssize_t *const strides)
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
rb_memory_view_init_as_byte_array(rb_memory_view_t *view, VALUE obj, void *data, const ssize_t len, const bool readonly)
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
get_format_size(const char *format, bool *native_p, ssize_t *alignment, endianness_t *endianness, ssize_t *count, const char **next_format, VALUE *error)
{
    RUBY_ASSERT(format != NULL);
    RUBY_ASSERT(native_p != NULL);
    RUBY_ASSERT(endianness != NULL);
    RUBY_ASSERT(count != NULL);
    RUBY_ASSERT(next_format != NULL);

    *native_p = false;
    *endianness = ENDIANNESS_NATIVE;
    *count = 1;

    const int type_char = *format;

    int i = 1;
    while (format[i]) {
        switch (format[i]) {
          case '!':
          case '_':
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

    // parse count
    int ch = format[i];
    if ('0' <= ch && ch <= '9') {
        ssize_t n = 0;
        while ('0' <= (ch = format[i]) && ch <= '9') {
            n = 10*n + ruby_digit36_to_number_table[ch];
            ++i;
        }
        *count = n;
    }

    *next_format = &format[i];

    switch (type_char) {
      case 'x':  // padding
        return 1;

      case 'c':  // signed char
      case 'C':  // unsigned char
        return sizeof(char);

      case 's':  // s for int16_t, s! for signed short
      case 'S':  // S for uint16_t, S! for unsigned short
        if (*native_p) {
            STRUCT_ALIGNOF(short, *alignment);
            return sizeof(short);
        }
        // fall through

      case 'n':  // n for big-endian 16bit unsigned integer
      case 'v':  // v for little-endian 16bit unsigned integer
        STRUCT_ALIGNOF(int16_t, *alignment);
        return 2;

      case 'i':  // i and i! for signed int
      case 'I':  // I and I! for unsigned int
        STRUCT_ALIGNOF(int, *alignment);
        return sizeof(int);

      case 'l':  // l for int32_t, l! for signed long
      case 'L':  // L for uint32_t, L! for unsigned long
        if (*native_p) {
            STRUCT_ALIGNOF(long, *alignment);
            return sizeof(long);
        }
        // fall through

      case 'N':  // N for big-endian 32bit unsigned integer
      case 'V':  // V for little-endian 32bit unsigned integer
        STRUCT_ALIGNOF(int32_t, *alignment);
        return 4;

      case 'f':  // f for native float
      case 'e':  // e for little-endian float
      case 'g':  // g for big-endian float
        STRUCT_ALIGNOF(float, *alignment);
        return sizeof(float);

      case 'q':  // q for int64_t, q! for signed long long
      case 'Q':  // Q for uint64_t, Q! for unsigned long long
        if (*native_p) {
            STRUCT_ALIGNOF(LONG_LONG, *alignment);
            return sizeof(LONG_LONG);
        }
        STRUCT_ALIGNOF(int64_t, *alignment);
        return 8;

      case 'd':  // d for native double
      case 'E':  // E for little-endian double
      case 'G':  // G for big-endian double
        STRUCT_ALIGNOF(double, *alignment);
        return sizeof(double);

      case 'j':  // j for intptr_t
      case 'J':  // J for uintptr_t
        STRUCT_ALIGNOF(intptr_t, *alignment);
        return sizeof(intptr_t);

      default:
        *alignment = -1;
        if (error) {
            *error = rb_exc_new_str(rb_eArgError, rb_sprintf("Invalid type character '%c'", type_char));
        }
        return -1;
    }
}

static inline ssize_t
calculate_padding(ssize_t total, ssize_t alignment_size) {
    if (alignment_size > 1) {
        ssize_t res = total % alignment_size;
        if (res > 0) {
            return alignment_size - res;
        }
    }
    return 0;
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
    ssize_t max_alignment_size = 0;

    const char *p = format;
    if (*p == '|') {  // alginment specifier
        alignment = true;
        ++format;
        ++p;
    }
    while (*p) {
        const char *q = p;

        // ignore spaces
        if (ISSPACE(*p)) {
            while (ISSPACE(*p)) ++p;
            continue;
        }

        bool native_size_p = false;
        ssize_t alignment_size = 0;
        endianness_t endianness = ENDIANNESS_NATIVE;
        ssize_t count = 0;
        const ssize_t size = get_format_size(p, &native_size_p, &alignment_size, &endianness, &count, &p, &error);
        if (size < 0) {
            if (err) *err = q;
            return -1;
        }
        if (max_alignment_size < alignment_size) {
            max_alignment_size = alignment_size;
        }

        const ssize_t padding = alignment ? calculate_padding(total, alignment_size) : 0;
        total += padding + size * count;

        if (*q != 'x') {
            ++len;
        }
    }

    // adjust total size with the alignment size of the largest element
    if (alignment && max_alignment_size > 0) {
        const ssize_t padding = calculate_padding(total, max_alignment_size);
        total += padding;
    }

    if (members && n_members) {
        rb_memory_view_item_component_t *buf = ALLOC_N(rb_memory_view_item_component_t, len);

        ssize_t i = 0, offset = 0;
        const char *p = format;
        while (*p) {
            const int type_char = *p;

            bool native_size_p;
            ssize_t alignment_size = 0;
            endianness_t endianness = ENDIANNESS_NATIVE;
            ssize_t count = 0;
            const ssize_t size = get_format_size(p, &native_size_p, &alignment_size, &endianness, &count, &p, NULL);

            const ssize_t padding = alignment ? calculate_padding(offset, alignment_size) : 0;
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
                  case 'v':
                  case 'V':
                    little_endian_p = true;
                    break;
                  case 'g':
                  case 'G':
                  case 'n':
                  case 'N':
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
        ssize_t stride = view->strides != NULL ? view->strides[0] : view->item_size;
        return ptr + indices[0] * stride;
    }

    assert(view->shape != NULL);

    ssize_t i;
    if (view->strides == NULL) {
        // row-major contiguous array
        ssize_t stride = view->item_size;
        for (i = 0; i < view->ndim; ++i) {
            stride *= view->shape[i];
        }
        for (i = 0; i < view->ndim; ++i) {
            stride /= view->shape[i];
            ptr += indices[i] * stride;
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
lookup_memory_view_entry(VALUE klass)
{
    VALUE entry_obj = rb_ivar_lookup(klass, id_memory_view, Qnil);
    while (NIL_P(entry_obj)) {
        klass = rb_class_get_superclass(klass);

        if (klass == rb_cBasicObject || klass == rb_cObject)
            return NULL;

        entry_obj = rb_ivar_lookup(klass, id_memory_view, Qnil);
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
    if (entry) {
        if (!(*entry->available_p_func)(obj)) {
            return 0;
        }

        int rv = (*entry->get_func)(obj, view, flags);
        if (rv) {
            register_exported_object(view->obj);
        }
        return rv;
    }
    else
        return 0;
}

/* Release the memory view obtained from obj. */
int
rb_memory_view_release(rb_memory_view_t* view)
{
    VALUE klass = CLASS_OF(view->obj);
    const rb_memory_view_entry_t *entry = lookup_memory_view_entry(klass);
    if (entry) {
        int rv = 1;
        if (entry->release_func) {
            rv = (*entry->release_func)(view->obj, view);
        }
        if (rv) {
            unregister_exported_object(view->obj);
            view->obj = Qnil;
        }
        return rv;
    }
    else
        return 0;
}

void
Init_MemoryView(void)
{
    id_memory_view = rb_intern_const("__memory_view__");
}
