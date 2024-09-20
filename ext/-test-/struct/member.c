#include "ruby.h"

static VALUE
bug_struct_get(VALUE obj, VALUE name)
{
    ID id = rb_check_id(&name);

    if (!id) {
        rb_name_error_str(name, "'%"PRIsVALUE"' is not a struct member", name);
    }
    return rb_struct_getmember(obj, id);
}

void
Init_member(VALUE klass)
{
    rb_define_method(klass, "get", bug_struct_get, 1);
}
