#include <ruby.h>

static VALUE
yield_block(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    return rb_block_call(self, rb_to_id(argv[0]), argc-1, argv+1, rb_yield_block, 0);
}

void
Init_yield(VALUE klass)
{
    VALUE yield = rb_define_module_under(klass, "Yield");

    rb_define_method(yield, "yield_block", yield_block, -1);
}
