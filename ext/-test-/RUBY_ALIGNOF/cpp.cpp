#include "ruby.h"
#include <cstddef>

struct T {
    char _;
    double t;
};

RBIMPL_STATIC_ASSERT(RUBY_ALIGNOF, RUBY_ALIGNOF(double) == offsetof(T, t));

extern "C" void
Init_RUBY_ALIGNOF()
{
    // Windows linker mandates this symbol to exist.
}
