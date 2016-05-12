#include "ruby/ruby.h"

NORETURN(void *dln_load(const char *));
void*
dln_load(const char *file)
{
    rb_loaderror("this executable file can't load extension libraries");

    UNREACHABLE;
}
