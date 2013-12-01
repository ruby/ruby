#include "ruby.h"

struct weak_object {
    VALUE obj;
    VALUE queue;
};

#define WOBJ_FINALIZED ((struct weak_object *)-1)
#define WOBJ_VALID_P(wh) ((wh) && (wh) != WOBJ_FINALIZED)

static void
wobj_mark(void *p)
{
    struct weak_object *wh = p;
    if (!WOBJ_VALID_P(wh)) return;
    if (!NIL_P(wh->queue)) rb_gc_mark(wh->queue);
}

static void
wobj_free(void *p)
{
    struct weak_object *wh = p;
    if (WOBJ_VALID_P(wh)) {
	VALUE obj = wh->obj;
	if (!NIL_P(obj)) rb_undefine_finalizer(obj);
    }
}

static size_t
wobj_memsize(const void *p)
{
    return p ? sizeof(struct weak_object) : 0;
}

static const rb_data_type_t weakobject_type = {
    "weakobject",
    {
	wobj_mark,
	wobj_free,
	wobj_memsize,
    },
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
wobj_allocate(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &weakobject_type, NULL);
}

static VALUE
wobj_deref(VALUE wobj)
{
    struct weak_object *wh = DATA_PTR(wobj);
    return WOBJ_VALID_P(wh) ? wh->obj : Qnil;
}

static VALUE
wobj_alive_p(VALUE wobj)
{
    struct weak_object *wh = DATA_PTR(wobj);
    return WOBJ_VALID_P(wh) ? Qtrue : Qfalse;
}

static VALUE
wobj_initialize(int argc, VALUE *argv, VALUE wobj)
{
    VALUE obj, queue;
    struct weak_object *wh;

    rb_scan_args(argc, argv, "11", &obj, &queue);

    if (DATA_PTR(wobj)) {
	rb_raise(rb_eArgError, "already initialized");
    }
    while (rb_typeddata_is_kind_of(obj, &weakobject_type)) {
	obj = wobj_deref(obj);
    }
    DATA_PTR(wobj) = wh = ALLOC(struct weak_object);
    rb_define_finalizer(obj, wobj);
    wh->obj = obj;
    wh->queue = queue;
    return wobj;
}

static VALUE
wobj_finalize(int argc, VALUE *argv, VALUE wobj)
{
    struct weak_object *wh = DATA_PTR(wobj);
    if (WOBJ_VALID_P(wh)) {
	VALUE queue = wh->queue;
	DATA_PTR(wobj) = WOBJ_FINALIZED;
	xfree(wh);
	if (!NIL_P(queue)) {
	    rb_funcallv(queue, rb_intern("push"), 1, &wobj);
	}
    }
    return Qnil;
}

static VALUE
wobj_inspect(VALUE wobj)
{
    VALUE str = rb_any_to_s(wobj);
    struct weak_object *wh = DATA_PTR(wobj);
    VALUE obj;
    if (WOBJ_VALID_P(wh) && !NIL_P(obj = wh->obj)) {
	rb_str_set_len(str, RSTRING_LEN(str)-1);
	rb_str_cat2(str, ": ");
	rb_str_append(str, rb_inspect(wh->obj));
	rb_str_cat2(str, ">");
    }
    return str;
}

void
Init_weak(void)
{
    VALUE rb_cWeakObject = rb_define_class("Weak", rb_cObject);
    rb_define_alloc_func(rb_cWeakObject, wobj_allocate);
    rb_define_singleton_method(rb_cWeakObject, "ref", rb_class_new_instance, -1);
    rb_define_private_method(rb_cWeakObject, "call", wobj_finalize, -1);
    rb_define_method(rb_cWeakObject, "initialize", wobj_initialize, -1);
    rb_define_method(rb_cWeakObject, "get", wobj_deref, 0);
    rb_define_method(rb_cWeakObject, "alive?", wobj_alive_p, 0);
    rb_define_method(rb_cWeakObject, "inspect", wobj_inspect, 0);
}
