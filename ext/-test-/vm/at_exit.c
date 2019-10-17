#include <ruby/ruby.h>
#include <ruby/vm.h>

static void
do_nothing(ruby_vm_t *vm)
{
}

static void
print_begin(ruby_vm_t *vm)
{
    printf("begin\n");
}

static void
print_end(ruby_vm_t *vm)
{
    printf("end\n");
}

static VALUE
register_at_exit(VALUE self, VALUE t)
{
    switch (t) {
      case Qtrue:
	ruby_vm_at_exit(print_begin);
	break;
      case Qfalse:
	ruby_vm_at_exit(print_end);
	break;
      default:
	ruby_vm_at_exit(do_nothing);
	break;
    }
    return self;
}

void
Init_at_exit(void)
{
    VALUE m = rb_define_module("Bug");
    VALUE c = rb_define_class_under(m, "VM", rb_cObject);
    rb_define_singleton_method(c, "register_at_exit", register_at_exit, 1);
}
