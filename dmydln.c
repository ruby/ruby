// This file is used by miniruby, not ruby.
// ruby uses dln.c.

#include "ruby/ruby.h"

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

NORETURN(void *dln_open(const char *library, const char **error));
void*
dln_open(const char *library, const char **error)
{
    rb_loaderror("this executable file can't load extension libraries");

    UNREACHABLE_RETURN(NULL);
}

