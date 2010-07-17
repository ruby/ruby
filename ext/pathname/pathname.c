#include "ruby.h"

static VALUE rb_cPathname;

void
Init_pathname()
{
    rb_cPathname = rb_define_class("Pathname", rb_cObject);
}
