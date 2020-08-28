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

static VALUE exported_objects;

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

    exported_objects = rb_hash_new();
    rb_gc_register_mark_object(exported_objects);
}
