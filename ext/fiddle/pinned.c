#include <fiddle.h>

VALUE rb_cPinned;
VALUE rb_eFiddleClearedReferenceError;

struct pinned_data {
    VALUE ptr;
};

static void
pinned_mark(void *ptr)
{
    struct pinned_data *data = (struct pinned_data*)ptr;
    /* Ensure reference is pinned */
    if (data->ptr) {
        rb_gc_mark(data->ptr);
    }
}

static size_t
pinned_memsize(const void *ptr)
{
    return sizeof(struct pinned_data);
}

static const rb_data_type_t pinned_data_type = {
    .wrap_struct_name = "fiddle/pinned",
    .function = {
        .dmark = pinned_mark,
        .dfree = RUBY_TYPED_DEFAULT_FREE,
        .dsize = pinned_memsize,
    },
    .flags = FIDDLE_DEFAULT_TYPED_DATA_FLAGS,
};

static VALUE
allocate(VALUE klass)
{
    struct pinned_data *data;
    VALUE obj = TypedData_Make_Struct(klass, struct pinned_data, &pinned_data_type, data);
    data->ptr = 0;
    return obj;
}

/*
 * call-seq:
 *    Fiddle::Pinned.new(object)      => pinned_object
 *
 * Create a new pinned object reference.  The Fiddle::Pinned instance will
 * prevent the GC from moving +object+.
 */
static VALUE
initialize(VALUE self, VALUE ref)
{
    struct pinned_data *data;
    TypedData_Get_Struct(self, struct pinned_data, &pinned_data_type, data);
    RB_OBJ_WRITE(self, &data->ptr, ref);
    return self;
}

/*
 * call-seq: ref
 *
 * Return the object that this pinned instance references.
 */
static VALUE
ref(VALUE self)
{
    struct pinned_data *data;
    TypedData_Get_Struct(self, struct pinned_data, &pinned_data_type, data);
    if (data->ptr) {
      return data->ptr;
    } else {
      rb_raise(rb_eFiddleClearedReferenceError, "`ref` called on a cleared object");
    }
}

/*
 * call-seq: clear
 *
 * Clear the reference to the object this is pinning.
 */
static VALUE
clear(VALUE self)
{
    struct pinned_data *data;
    TypedData_Get_Struct(self, struct pinned_data, &pinned_data_type, data);
    data->ptr = 0;
    return self;
}

/*
 * call-seq: cleared?
 *
 * Returns true if the reference has been cleared, otherwise returns false.
 */
static VALUE
cleared_p(VALUE self)
{
    struct pinned_data *data;
    TypedData_Get_Struct(self, struct pinned_data, &pinned_data_type, data);
    if (data->ptr) {
        return Qfalse;
    } else {
        return Qtrue;
    }
}

extern VALUE rb_eFiddleError;

void
Init_fiddle_pinned(void)
{
    rb_cPinned = rb_define_class_under(mFiddle, "Pinned", rb_cObject);
    rb_define_alloc_func(rb_cPinned, allocate);
    rb_define_method(rb_cPinned, "initialize", initialize, 1);
    rb_define_method(rb_cPinned, "ref", ref, 0);
    rb_define_method(rb_cPinned, "clear", clear, 0);
    rb_define_method(rb_cPinned, "cleared?", cleared_p, 0);

    /*
     * Document-class: Fiddle::ClearedReferenceError
     *
     * Cleared reference exception
     */
    rb_eFiddleClearedReferenceError = rb_define_class_under(mFiddle, "ClearedReferenceError", rb_eFiddleError);
}
