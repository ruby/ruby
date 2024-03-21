#include <stdio.h>
#include <stdlib.h>
#include "rubygc.h"

RUBY_FUNC_EXPORTED void
GC_Init(void)
{
    if (getenv("RUBY_SHARED_GC")) {
        fprintf(stderr, "Loading the GC from CRuby\n");
    }
}
