#include "ruby.h"

void
Init_path_to_class(void)
{
    VALUE klass = rb_path2class("Test_PathToClass");

    rb_define_singleton_method(klass, "path_to_class", rb_path_to_class, 1);
}
