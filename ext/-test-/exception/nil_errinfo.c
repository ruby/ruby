#include <ruby.h>

static VALUE
raise_boom(VALUE _arg)
{
    rb_raise(rb_eRuntimeError, "boom");
    UNREACHABLE_RETURN(Qnil);
}

/*
 * If a native extension catches an exception with rb_protect()
 * and then uses rb_funcall to run Ruby code that rescues an exception
 * the errinfo will be set to Qnil before the extension calls rb_jump_tag.
 * We want to defend against that.
 *
 * Extensions should save the errinfo before the call and restore it afterward.
 */
static VALUE
raise_after_rescue_cleanup(VALUE self)
{
    int state = 0;

    rb_protect(raise_boom, Qnil, &state);

    if (state) {
        /* Any begin/rescue that catches an exception clears ec->errinfo. */
        rb_funcall(self, rb_intern("cleanup_with_rescue"), 0);
        /* ec->errinfo is now Qnil, but state is still TAG_RAISE. */
        rb_jump_tag(state);
    }
    return Qnil;
}

void
Init_nil_errinfo(VALUE klass)
{
    rb_define_singleton_method(klass, "raise_after_rescue_cleanup",
                               raise_after_rescue_cleanup, 0);
}
