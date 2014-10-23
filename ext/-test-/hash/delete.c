#include "ruby.h"

static VALUE
hash_delete(VALUE hash, VALUE key)
{
    VALUE ret = rb_hash_delete(hash, key);
    return ret == Qundef ? Qfalse : Qtrue;
}

void
Init_delete(VALUE klass)
{
    rb_define_method(klass, "delete", hash_delete, 1);
}
