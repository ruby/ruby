#include "ruby.h"
#include "internal/io_buffer.h"

static VALUE
io_buffer_get_string(VALUE buffer, VALUE argument)
{
    (void)argument;
    return rb_funcall(buffer, rb_intern("get_string"), 0);
}

static VALUE
io_buffer_readonly_p(VALUE buffer, VALUE argument)
{
    (void)argument;
    return rb_funcall(buffer, rb_intern("readonly?"), 0);
}

static VALUE
io_buffer_object_id(VALUE buffer, VALUE argument)
{
    (void)argument;
    return rb_obj_id(buffer);
}

static VALUE
io_buffer_set_string(VALUE buffer, VALUE string)
{
    return rb_funcall(buffer, rb_intern("set_string"), 1, string);
}

static VALUE
io_buffer_modify_string(VALUE buffer, VALUE string)
{
    (void)buffer;
    rb_str_cat(string, "!", 1);
    return Qnil;
}

static VALUE
io_buffer_raise(VALUE buffer, VALUE argument)
{
    (void)buffer;
    (void)argument;
    rb_raise(rb_eRuntimeError, "interrupted");
}

static VALUE
io_buffer_for_reading_get_string(VALUE self, VALUE object)
{
    return rb_io_buffer_for_reading(object, io_buffer_get_string, Qnil);
}

static VALUE
io_buffer_for_reading_readonly_p(VALUE self, VALUE object)
{
    return rb_io_buffer_for_reading(object, io_buffer_readonly_p, Qnil);
}

static VALUE
io_buffer_for_reading_object_id(VALUE self, VALUE object)
{
    return rb_io_buffer_for_reading(object, io_buffer_object_id, Qnil);
}

static VALUE
io_buffer_for_reading_raise(VALUE self, VALUE string)
{
    StringValue(string);
    return rb_io_buffer_for_reading(string, io_buffer_raise, Qnil);
}

static VALUE
io_buffer_for_writing_set_string(VALUE self, VALUE object, VALUE string)
{
    StringValue(string);
    return rb_io_buffer_for_writing(object, io_buffer_set_string, string);
}

static VALUE
io_buffer_for_writing_readonly_p(VALUE self, VALUE object)
{
    return rb_io_buffer_for_writing(object, io_buffer_readonly_p, Qnil);
}

static VALUE
io_buffer_for_writing_modify_string(VALUE self, VALUE string)
{
    StringValue(string);
    return rb_io_buffer_for_writing(string, io_buffer_modify_string, string);
}

void
Init_io_buffer(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE mIOBuffer = rb_define_module_under(mBug, "IOBuffer");

    rb_define_singleton_method(mIOBuffer, "for_reading_get_string", io_buffer_for_reading_get_string, 1);
    rb_define_singleton_method(mIOBuffer, "for_reading_readonly?", io_buffer_for_reading_readonly_p, 1);
    rb_define_singleton_method(mIOBuffer, "for_reading_object_id", io_buffer_for_reading_object_id, 1);
    rb_define_singleton_method(mIOBuffer, "for_reading_raise", io_buffer_for_reading_raise, 1);
    rb_define_singleton_method(mIOBuffer, "for_writing_set_string", io_buffer_for_writing_set_string, 2);
    rb_define_singleton_method(mIOBuffer, "for_writing_readonly?", io_buffer_for_writing_readonly_p, 1);
    rb_define_singleton_method(mIOBuffer, "for_writing_modify_string", io_buffer_for_writing_modify_string, 1);
}
