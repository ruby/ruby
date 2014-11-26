
#include "ruby/ruby.h"

void ruby_Init_Continuation_body(void);

void
Init_continuation(void)
{
    rb_warn("callcc is obsolete; use Fiber instead");
    ruby_Init_Continuation_body();
}
