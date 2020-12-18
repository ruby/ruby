#include <stdbool.h>
#include <ruby/ruby.h>

#ifdef HAVE_RUBY_MEMORY_VIEW_H
# include <ruby/memory_view.h>
#endif

#if SIZEOF_INTPTR_T == SIZEOF_LONG_LONG
#   define INTPTR2NUM LL2NUM
#   define UINTPTR2NUM ULL2NUM
#elif SIZEOF_INTPTR_T == SIZEOF_LONG
#   define INTPTR2NUM LONG2NUM
#   define UINTPTR2NUM ULONG2NUM
#else
#   define INTPTR2NUM INT2NUM
#   define UINTPTR2NUM UINT2NUM
#endif

#include <fiddle.h>

#ifdef FIDDLE_MEMORY_VIEW
VALUE rb_cMemoryView = Qnil;

struct memview_data {
    rb_memory_view_t view;
    rb_memory_view_item_component_t *members;
    size_t n_members;
};

static void
fiddle_memview_mark(void *ptr)
{
    const struct memview_data *data = ptr;
    rb_gc_mark(data->view.obj);
}

static void
fiddle_memview_free(void *ptr)
{
    struct memview_data *data = ptr;
    rb_memory_view_release(&data->view);
    if (data->members)
        xfree(data->members);
    xfree(ptr);
}

static size_t
fiddle_memview_memsize(const void *ptr)
{
    const struct memview_data *data = ptr;
    return sizeof(*data) + sizeof(rb_memory_view_item_component_t)*data->n_members + (size_t)data->view.len;
}

static const rb_data_type_t fiddle_memview_data_type = {
    "fiddle/memory_view",
    {fiddle_memview_mark, fiddle_memview_free, fiddle_memview_memsize,},
};

static VALUE
rb_fiddle_memview_s_allocate(VALUE klass)
{
    struct memview_data *data;
    VALUE obj = TypedData_Make_Struct(klass, struct memview_data, &fiddle_memview_data_type, data);
    data->view.obj = Qnil;
    data->members = NULL;
    data->n_members = 0;
    return obj;
}

static VALUE
rb_fiddle_memview_initialize(VALUE obj, VALUE target)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (!rb_memory_view_get(target, &data->view, 0)) {
        rb_raise(rb_eArgError, "Unable to get a memory view from %+"PRIsVALUE, target);
    }

    return Qnil;
}

static VALUE
rb_fiddle_memview_get_obj(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    return data->view.obj;
}

static VALUE
rb_fiddle_memview_get_length(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;
    return SSIZET2NUM(data->view.len);
}

static VALUE
rb_fiddle_memview_get_readonly(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;
    return data->view.readonly ? Qtrue : Qfalse;
}

static VALUE
rb_fiddle_memview_get_format(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;
    return data->view.format == NULL ? Qnil : rb_str_new_cstr(data->view.format);
}

static VALUE
rb_fiddle_memview_get_item_size(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;
    return SSIZET2NUM(data->view.item_size);
}

static VALUE
rb_fiddle_memview_get_ndim(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;
    return SSIZET2NUM(data->view.ndim);
}

static VALUE
rb_fiddle_memview_get_shape(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;
    if (data->view.shape == NULL) return Qnil;

    const ssize_t ndim = data->view.ndim;
    VALUE shape = rb_ary_new_capa(ndim);
    ssize_t i;
    for (i = 0; i < ndim; ++i) {
        rb_ary_push(shape, SSIZET2NUM(data->view.shape[i]));
    }
    return shape;
}

static VALUE
rb_fiddle_memview_get_strides(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;
    if (data->view.strides == NULL) return Qnil;

    const ssize_t ndim = data->view.ndim;
    VALUE strides = rb_ary_new_capa(ndim);
    ssize_t i;
    for (i = 0; i < ndim; ++i) {
        rb_ary_push(strides, SSIZET2NUM(data->view.strides[i]));
    }
    return strides;
}

static VALUE
rb_fiddle_memview_get_sub_offsets(VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;
    if (data->view.sub_offsets == NULL) return Qnil;

    const ssize_t ndim = data->view.ndim;
    VALUE sub_offsets = rb_ary_new_capa(ndim);
    ssize_t i;
    for (i = 0; i < ndim; ++i) {
        rb_ary_push(sub_offsets, SSIZET2NUM(data->view.sub_offsets[i]));
    }
    return sub_offsets;
}

static VALUE
rb_fiddle_memview_aref(int argc, VALUE *argv, VALUE obj)
{
    struct memview_data *data;
    TypedData_Get_Struct(obj, struct memview_data, &fiddle_memview_data_type, data);

    if (NIL_P(data->view.obj)) return Qnil;

    const ssize_t ndim = data->view.ndim;
    if (argc != ndim) {
        rb_raise(rb_eIndexError, "wrong number of index (%d for %"PRIdSIZE")", argc, ndim);
    }

    VALUE indices_v = 0;
    ssize_t *indices = ALLOCV_N(ssize_t, indices_v, ndim);

    ssize_t i;
    for (i = 0; i < ndim; ++i) {
        ssize_t x = NUM2SSIZET(argv[i]);
        indices[i] = x;
    }

    uint8_t *ptr = rb_memory_view_get_item_pointer(&data->view, indices);
    ALLOCV_END(indices_v);

    if (data->view.format == NULL) {
        return INT2FIX(*ptr);
    }

    if (!data->members) {
        const char *err;
        if (rb_memory_view_parse_item_format(data->view.format, &data->members, &data->n_members, &err) < 0) {
            rb_raise(rb_eRuntimeError, "Unable to recognize item format at %"PRIdSIZE" in \"%s\"",
                     err - data->view.format, data->view.format);
        }
    }

    return rb_memory_view_extract_item_members(ptr, data->members, data->n_members);
}

void
Init_fiddle_memory_view(void)
{
    rb_cMemoryView = rb_define_class_under(mFiddle, "MemoryView", rb_cObject);
    rb_define_alloc_func(rb_cMemoryView, rb_fiddle_memview_s_allocate);
    rb_define_method(rb_cMemoryView, "initialize", rb_fiddle_memview_initialize, 1);
    rb_define_method(rb_cMemoryView, "obj", rb_fiddle_memview_get_obj, 0);
    rb_define_method(rb_cMemoryView, "length", rb_fiddle_memview_get_length, 0);
    rb_define_method(rb_cMemoryView, "readonly?", rb_fiddle_memview_get_readonly, 0);
    rb_define_method(rb_cMemoryView, "format", rb_fiddle_memview_get_format, 0);
    rb_define_method(rb_cMemoryView, "item_size", rb_fiddle_memview_get_item_size, 0);
    rb_define_method(rb_cMemoryView, "ndim", rb_fiddle_memview_get_ndim, 0);
    rb_define_method(rb_cMemoryView, "shape", rb_fiddle_memview_get_shape, 0);
    rb_define_method(rb_cMemoryView, "strides", rb_fiddle_memview_get_strides, 0);
    rb_define_method(rb_cMemoryView, "sub_offsets", rb_fiddle_memview_get_sub_offsets, 0);
    rb_define_method(rb_cMemoryView, "[]", rb_fiddle_memview_aref, -1);
}

#endif /* FIDDLE_MEMORY_VIEW */
