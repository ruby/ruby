#include "ruby.h"
#include <stddef.h>

struct T {
    char _;
    double t;
};

RBIMPL_STATIC_ASSERT(RUBY_ALIGNOF, RUBY_ALIGNOF(double) == offsetof(struct T, t));

void
Init_RUBY_ALIGNOF()
{
    // Windows linker mandates this symbol to exist.
}
