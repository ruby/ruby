#include "ruby/ruby.h"

void ruby_Init_refinement(void);

void
Init_refinement(void)
{
    rb_warn("Refinements are experimental, and the behavior may change in future versions of Ruby!");
    ruby_Init_refinement();
}
