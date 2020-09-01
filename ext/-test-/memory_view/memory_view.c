#include "ruby.h"
#include "ruby/memory_view.h"

static ID id_str;
static VALUE sym_format;
static VALUE sym_native_size_p;
static VALUE sym_offset;
static VALUE sym_size;
static VALUE sym_repeat;
static VALUE sym_obj;
static VALUE sym_len;
static VALUE sym_readonly;
static VALUE sym_format;
static VALUE sym_item_size;
static VALUE sym_ndim;
static VALUE sym_shape;
static VALUE sym_strides;
static VALUE sym_sub_offsets;
static VALUE sym_endianness;
static VALUE sym_little_endian;
static VALUE sym_big_endian;

static VALUE exported_objects;

typedef struct { char c; short     x; } short_alignment_s;
typedef struct { char c; int       x; } int_alignment_s;
typedef struct { char c; long      x; } long_alignment_s;
typedef struct { char c; LONG_LONG x; } long_long_alignment_s;
typedef struct { char c; int16_t   x; } int16_alignment_s;
typedef struct { char c; int32_t   x; } int32_alignment_s;
typedef struct { char c; int64_t   x; } int64_alignment_s;
typedef struct { char c; intptr_t  x; } intptr_alignment_s;

#define SHORT_ALIGNMENT      (sizeof(short_alignment_s) - sizeof(short))
#define INT_ALIGNMENT        (sizeof(int_alignment_s) - sizeof(int))
#define LONG_ALIGNMENT       (sizeof(long_alignment_s) - sizeof(long))
#define LONG_LONG_ALIGNMENT  (sizeof(long_long_alignment_s) - sizeof(LONG_LONG))
#define INT16_ALIGNMENT      (sizeof(int16_alignment_s) - sizeof(int16_t))
#define INT32_ALIGNMENT      (sizeof(int32_alignment_s) - sizeof(int32_t))
#define INT64_ALIGNMENT      (sizeof(int64_alignment_s) - sizeof(int64_t))
#define INTPTR_ALIGNMENT     (sizeof(intptr_alignment_s) - sizeof(intptr_t))

static int
exportable_string_get_memory_view(VALUE obj, rb_memory_view_t *view, int flags)
{
    VALUE str = rb_ivar_get(obj, id_str);
    rb_memory_view_init_as_byte_array(view, obj, RSTRING_PTR(str), RSTRING_LEN(str), true);

    VALUE count = rb_hash_lookup2(exported_objects, obj, INT2FIX(0));
    count = rb_funcall(count, '+', 1, INT2FIX(1));
    rb_hash_aset(exported_objects, obj, count);

    return 1;
}

static int
exportable_string_release_memory_view(VALUE obj, rb_memory_view_t *view)
{
    VALUE count = rb_hash_lookup2(exported_objects, obj, INT2FIX(0));
    if (INT2FIX(1) == count) {
        rb_hash_delete(exported_objects, obj);
    }
    else if (INT2FIX(0) == count) {
        rb_raise(rb_eRuntimeError, "Duplicated releasing of a memory view has been occurred for %"PRIsVALUE, obj);
    }
    else {
        count = rb_funcall(count, '-', 1, INT2FIX(1));
        rb_hash_aset(exported_objects, obj, count);
    }

    return 1;
}

static int
exportable_string_memory_view_available_p(VALUE obj)
{
    return Qtrue;
}

static const rb_memory_view_entry_t exportable_string_memory_view_entry = {
    exportable_string_get_memory_view,
    exportable_string_release_memory_view,
    exportable_string_memory_view_available_p
};

static VALUE
memory_view_available_p(VALUE mod, VALUE obj)
{
    return rb_memory_view_available_p(obj) ? Qtrue : Qfalse;
}

static VALUE
memory_view_register(VALUE mod, VALUE obj)
{
    return rb_memory_view_register(obj, &exportable_string_memory_view_entry) ? Qtrue : Qfalse;
}

static VALUE
memory_view_item_size_from_format(VALUE mod, VALUE format)
{
    const char *c_str = NULL;
    if (!NIL_P(format))
        c_str = StringValueCStr(format);
    const char *err = NULL;
    ssize_t item_size = rb_memory_view_item_size_from_format(c_str, &err);
    if (!err)
        return rb_assoc_new(SSIZET2NUM(item_size), Qnil);
    else 
        return rb_assoc_new(SSIZET2NUM(item_size), rb_str_new_cstr(err));
}

static VALUE
memory_view_parse_item_format(VALUE mod, VALUE format)
{
    const char *c_str = NULL;
    if (!NIL_P(format))
        c_str = StringValueCStr(format);
    const char *err = NULL;

    rb_memory_view_item_component_t *members;
    ssize_t n_members;
    ssize_t item_size = rb_memory_view_parse_item_format(c_str, &members, &n_members, &err);

    VALUE result = rb_ary_new_capa(3);
    rb_ary_push(result, SSIZET2NUM(item_size));

    if (!err) {
        VALUE ary = rb_ary_new_capa(n_members);
        ssize_t i;
        for (i = 0; i < n_members; ++i) {
            VALUE member = rb_hash_new();
            rb_hash_aset(member, sym_format, rb_str_new(&members[i].format, 1));
            rb_hash_aset(member, sym_native_size_p, members[i].native_size_p ? Qtrue : Qfalse);
            rb_hash_aset(member, sym_endianness, members[i].little_endian_p ? sym_little_endian : sym_big_endian);
            rb_hash_aset(member, sym_offset, SSIZET2NUM(members[i].offset));
            rb_hash_aset(member, sym_size, SSIZET2NUM(members[i].size));
            rb_hash_aset(member, sym_repeat, SSIZET2NUM(members[i].repeat));
            rb_ary_push(ary, member);
        }
        xfree(members);
        rb_ary_push(result, ary);
        rb_ary_push(result, Qnil);
    }
    else {
        rb_ary_push(result, Qnil); // members
        rb_ary_push(result, rb_str_new_cstr(err));
    }

    return result;
}

static VALUE
memory_view_get_memory_view_info(VALUE mod, VALUE obj)
{
    rb_memory_view_t view;

    if (!rb_memory_view_get(obj, &view, 0)) {
        return Qnil;
    }

    VALUE hash = rb_hash_new();
    rb_hash_aset(hash, sym_obj, view.obj);
    rb_hash_aset(hash, sym_len, SSIZET2NUM(view.len));
    rb_hash_aset(hash, sym_readonly, view.readonly ? Qtrue : Qfalse);
    rb_hash_aset(hash, sym_format, view.format ? rb_str_new_cstr(view.format) : Qnil);
    rb_hash_aset(hash, sym_item_size, SSIZET2NUM(view.item_size));
    rb_hash_aset(hash, sym_ndim, SSIZET2NUM(view.ndim));

    if (view.shape) {
        VALUE shape = rb_ary_new_capa(view.ndim);
        rb_hash_aset(hash, sym_shape, shape);
    }
    else {
        rb_hash_aset(hash, sym_shape, Qnil);
    }

    if (view.strides) {
        VALUE strides = rb_ary_new_capa(view.ndim);
        rb_hash_aset(hash, sym_strides, strides);
    }
    else {
        rb_hash_aset(hash, sym_strides, Qnil);
    }

    if (view.sub_offsets) {
        VALUE sub_offsets = rb_ary_new_capa(view.ndim);
        rb_hash_aset(hash, sym_sub_offsets, sub_offsets);
    }
    else {
        rb_hash_aset(hash, sym_sub_offsets, Qnil);
    }

    rb_memory_view_release(&view);

    return hash;
}

static VALUE
memory_view_fill_contiguous_strides(VALUE mod, VALUE ndim_v, VALUE item_size_v, VALUE shape_v, VALUE row_major_p)
{
    int i, ndim = FIX2INT(ndim_v);

    Check_Type(shape_v, T_ARRAY);
    ssize_t *shape = ALLOC_N(ssize_t, ndim);
    for (i = 0; i < ndim; ++i) {
        shape[i] = NUM2SSIZET(RARRAY_AREF(shape_v, i));
    }

    ssize_t *strides = ALLOC_N(ssize_t, ndim);
    rb_memory_view_fill_contiguous_strides(ndim, NUM2SSIZET(item_size_v), shape, RTEST(row_major_p), strides);

    VALUE result = rb_ary_new_capa(ndim);
    for (i = 0; i < ndim; ++i) {
        rb_ary_push(result, SSIZET2NUM(strides[i]));
    }

    xfree(strides);
    xfree(shape);

    return result;
}

static VALUE
expstr_initialize(VALUE obj, VALUE s)
{
    rb_ivar_set(obj, id_str, s);
    return Qnil;
}

void
Init_memory_view(void)
{
    VALUE mMemoryViewTestUtils = rb_define_module("MemoryViewTestUtils");

    rb_define_module_function(mMemoryViewTestUtils, "available?", memory_view_available_p, 1);
    rb_define_module_function(mMemoryViewTestUtils, "register", memory_view_register, 1);
    rb_define_module_function(mMemoryViewTestUtils, "item_size_from_format", memory_view_item_size_from_format, 1);
    rb_define_module_function(mMemoryViewTestUtils, "parse_item_format", memory_view_parse_item_format, 1);
    rb_define_module_function(mMemoryViewTestUtils, "get_memory_view_info", memory_view_get_memory_view_info, 1);
    rb_define_module_function(mMemoryViewTestUtils, "fill_contiguous_strides", memory_view_fill_contiguous_strides, 4);

    VALUE cExportableString = rb_define_class_under(mMemoryViewTestUtils, "ExportableString", rb_cObject);

    rb_define_method(cExportableString, "initialize", expstr_initialize, 1);

    rb_memory_view_register(cExportableString, &exportable_string_memory_view_entry);

    id_str = rb_intern("__str__");
    sym_format = ID2SYM(rb_intern("format"));
    sym_native_size_p = ID2SYM(rb_intern("native_size_p"));
    sym_offset = ID2SYM(rb_intern("offset"));
    sym_size = ID2SYM(rb_intern("size"));
    sym_repeat = ID2SYM(rb_intern("repeat"));
    sym_obj = ID2SYM(rb_intern("obj"));
    sym_len = ID2SYM(rb_intern("len"));
    sym_readonly = ID2SYM(rb_intern("readonly"));
    sym_format = ID2SYM(rb_intern("format"));
    sym_item_size = ID2SYM(rb_intern("item_size"));
    sym_ndim = ID2SYM(rb_intern("ndim"));
    sym_shape = ID2SYM(rb_intern("shape"));
    sym_strides = ID2SYM(rb_intern("strides"));
    sym_sub_offsets = ID2SYM(rb_intern("sub_offsets"));
    sym_endianness = ID2SYM(rb_intern("endianness"));
    sym_little_endian = ID2SYM(rb_intern("little_endian"));
    sym_big_endian = ID2SYM(rb_intern("big_endian"));

#ifdef WORDS_BIGENDIAN
    rb_const_set(mMemoryViewTestUtils, rb_intern("NATIVE_ENDIAN"), sym_big_endian);
#else
    rb_const_set(mMemoryViewTestUtils, rb_intern("NATIVE_ENDIAN"), sym_little_endian);
#endif

#define DEF_ALIGNMENT_CONST(TYPE) rb_const_set(mMemoryViewTestUtils, rb_intern(#TYPE "_ALIGNMENT"), INT2FIX(TYPE ## _ALIGNMENT))

    DEF_ALIGNMENT_CONST(SHORT);
    DEF_ALIGNMENT_CONST(INT);
    DEF_ALIGNMENT_CONST(LONG);
    DEF_ALIGNMENT_CONST(LONG_LONG);
    DEF_ALIGNMENT_CONST(INT16);
    DEF_ALIGNMENT_CONST(INT32);
    DEF_ALIGNMENT_CONST(INT64);
    DEF_ALIGNMENT_CONST(INTPTR);

#undef DEF_ALIGNMENT_CONST

    exported_objects = rb_hash_new();
    rb_gc_register_mark_object(exported_objects);
}
