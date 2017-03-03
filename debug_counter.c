/**********************************************************************

  debug_counter.c -

  created at: Tue Feb 21 16:51:18 2017

  Copyright (C) 2017 Koichi Sasada

**********************************************************************/

#include "debug_counter.h"
#include <stdio.h>

#if USE_DEBUG_COUNTER

/* do not modify manually. use a script above */
const char * const debug_counter_names[] = {
#include "debug_counter_names.inc"
    ""
};

size_t rb_debug_counter[RB_DEBUG_COUNTER_MAX + 1];

__attribute__((destructor))
static void
rb_debug_counter_show_results(void)
{
    const char *env = getenv("RUBY_DEBUG_COUNTER_DISABLE");
    if (env == NULL || strcmp("1", env) != 0) {
	int i;
	for (i=0; i<RB_DEBUG_COUNTER_MAX; i++) {
	    fprintf(stderr, "[RUBY_DEBUG_COUNTER]\t%s\t%"PRIuSIZE"\n",
		    debug_counter_names[i],
		    rb_debug_counter[i]);
	}
    }
}

#endif /* USE_DEBUG_COUNTER */
