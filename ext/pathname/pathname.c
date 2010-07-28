#include "ruby.h"

static VALUE rb_cPathname;
static ID id_at_path, id_to_path;

static VALUE
get_strpath(VALUE obj)
{
    VALUE strpath;
    strpath = rb_ivar_get(obj, id_at_path);
    if (TYPE(strpath) != T_STRING)
        rb_raise(rb_eTypeError, "unexpected @path");
    return strpath;
}

static void
set_strpath(VALUE obj, VALUE val)
{
    rb_ivar_set(obj, id_at_path, val);
}

/*
 * Create a Pathname object from the given String (or String-like object).
 * If +path+ contains a NUL character (<tt>\0</tt>), an ArgumentError is raised.
 */
static VALUE
path_initialize(VALUE self, VALUE arg)
{
    VALUE str;
    if (TYPE(arg) == T_STRING) {
        str = arg;
    }
    else {
        str = rb_check_funcall(arg, id_to_path, 0, NULL);
        if (str == Qundef)
            str = arg;
        StringValue(str);
    }
    if (memchr(RSTRING_PTR(str), '\0', RSTRING_LEN(str)))
        rb_raise(rb_eArgError, "pathname contains null byte");
    str = rb_obj_dup(str);

    set_strpath(self, str);
    OBJ_INFECT(self, str);
    return self;
}

static VALUE
path_freeze(VALUE self)
{
    rb_call_super(0, 0);
    rb_str_freeze(get_strpath(self));
    return self;
}

static VALUE
path_taint(VALUE self)
{
    rb_call_super(0, 0);
    rb_obj_taint(get_strpath(self));
    return self;
}

static VALUE
path_untaint(VALUE self)
{
    rb_call_super(0, 0);
    rb_obj_untaint(get_strpath(self));
    return self;
}

/*
 *  Compare this pathname with +other+.  The comparison is string-based.
 *  Be aware that two different paths (<tt>foo.txt</tt> and <tt>./foo.txt</tt>)
 *  can refer to the same file.
 */
static VALUE
path_eq(VALUE self, VALUE other)
{
    if (!rb_obj_is_kind_of(other, rb_cPathname))
        return Qfalse;
    return rb_str_equal(get_strpath(self), get_strpath(other));
}

void
Init_pathname()
{
    id_at_path = rb_intern("@path");
    id_to_path = rb_intern("to_path");

    rb_cPathname = rb_define_class("Pathname", rb_cObject);
    rb_define_method(rb_cPathname, "initialize", path_initialize, 1);
    rb_define_method(rb_cPathname, "freeze", path_freeze, 0);
    rb_define_method(rb_cPathname, "taint", path_taint, 0);
    rb_define_method(rb_cPathname, "untaint", path_untaint, 0);
    rb_define_method(rb_cPathname, "==", path_eq, 1);
    rb_define_method(rb_cPathname, "===", path_eq, 1);
    rb_define_method(rb_cPathname, "eql?", path_eq, 1);
}
