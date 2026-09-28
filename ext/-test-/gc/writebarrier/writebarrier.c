#include "ruby.h"
#include "internal/gc.h"

struct wb_box {
    VALUE child;
};

static void
wb_box_mark(void *ptr)
{
    struct wb_box *box = ptr;
    rb_gc_mark(box->child);
}

static size_t
wb_box_memsize(const void *ptr)
{
    return ptr ? sizeof(struct wb_box) : 0;
}

static const rb_data_type_t wb_box_type = {
    "Bug::GC::WriteBarrier::Box",
    {wb_box_mark, RUBY_TYPED_DEFAULT_FREE, wb_box_memsize,},
    NULL, NULL,
    RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FROZEN_SHAREABLE,
};

static VALUE
wb_box_alloc(VALUE klass)
{
    struct wb_box *box;
    VALUE obj = TypedData_Make_Struct(klass, struct wb_box, &wb_box_type, box);
    box->child = Qnil;
    return obj;
}

/* No rb_check_frozen: the point of this box is to keep storing after
 * Ractor.make_shareable froze it, so a test can build a shareable -> unshareable edge
 * across objspaces. */
static VALUE
wb_box_store(VALUE self, VALUE child)
{
    struct wb_box *box;
    TypedData_Get_Struct(self, struct wb_box, &wb_box_type, box);
    RB_OBJ_WRITE(self, &box->child, child);
    return child;
}

static VALUE
wb_box_child(VALUE self)
{
    struct wb_box *box;
    TypedData_Get_Struct(self, struct wb_box, &wb_box_type, box);
    return box->child;
}

static VALUE
wb_remember(VALUE self, VALUE obj)
{
    rb_gc_writebarrier_remember(obj);
    return obj;
}

void
Init_writebarrier(void)
{
    rb_ext_ractor_safe(true);

    VALUE mBug = rb_define_module("Bug");
    VALUE mGC = rb_define_module_under(mBug, "GC");
    VALUE mWB = rb_define_module_under(mGC, "WriteBarrier");
    rb_define_singleton_method(mWB, "remember", wb_remember, 1);

    VALUE cBox = rb_define_class_under(mWB, "Box", rb_cObject);
    rb_define_alloc_func(cBox, wb_box_alloc);
    rb_define_method(cBox, "store", wb_box_store, 1);
    rb_define_method(cBox, "child", wb_box_child, 0);
}
