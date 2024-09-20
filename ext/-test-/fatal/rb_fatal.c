#include <ruby.h>

static VALUE
ruby_fatal(VALUE obj, VALUE msg)
{
    const char *cmsg = NULL;

    (void)obj;

    cmsg = RSTRING_PTR(msg);
    rb_fatal("%s", cmsg);
    return 0; /* never reached */
}

void
Init_rb_fatal(VALUE mBug)
{
    rb_define_singleton_method(mBug, "rb_fatal", ruby_fatal, 1);
}
