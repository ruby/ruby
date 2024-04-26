// This file is used by miniruby, not ruby.
// ruby uses dln.c.

#include "ruby/ruby.h"

bool
dln_supported_p(void)
{
    return false;
}

NORETURN(void *dln_load(const char *));
void*
dln_load(const char *file)
{
    rb_loaderror("this executable file can't load extension libraries");

    UNREACHABLE_RETURN(NULL);
}

NORETURN(void *dln_symbol(void*,const char*));
void*
dln_symbol(void *handle, const char *symbol)
{
    rb_loaderror("this executable file can't load extension libraries");

    UNREACHABLE_RETURN(NULL);
}

void*
dln_open(const char *library, char *error, size_t size)
{
    static const char *error_str = "this executable file can't load extension libraries";
    strlcpy(error, error_str, size);
    return NULL;
}

