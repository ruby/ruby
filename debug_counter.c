/**********************************************************************

  debug_counter.c -

  created at: Tue Feb 21 16:51:18 2017

  Copyright (C) 2017 Koichi Sasada

**********************************************************************/

#include "debug_counter.h"
#if USE_DEBUG_COUNTER
#include <stdio.h>
#include <locale.h>
#include "internal.h"

static const char *const debug_counter_names[] = {
    ""
#define RB_DEBUG_COUNTER(name) #name,
#include "debug_counter.h"
#undef RB_DEBUG_COUNTER
};

size_t rb_debug_counter[numberof(debug_counter_names)];

void
rb_debug_counter_show_results(const char *msg)
{
    const char *env = getenv("RUBY_DEBUG_COUNTER_DISABLE");

    setlocale(LC_NUMERIC, "");

    if (env == NULL || strcmp("1", env) != 0) {
	int i;
        fprintf(stderr, "[RUBY_DEBUG_COUNTER]\t%d %s\n", getpid(), msg);
	for (i=0; i<RB_DEBUG_COUNTER_MAX; i++) {
            fprintf(stderr, "[RUBY_DEBUG_COUNTER]\t%-30s\t%'14"PRIuSIZE"\n",
		    debug_counter_names[i],
		    rb_debug_counter[i]);
	}
    }
}

__attribute__((destructor))
static void
debug_counter_show_results_at_exit(void)
{
    rb_debug_counter_show_results("normal exit.");
}
#else
void
rb_debug_counter_show_results(const char *msg)
{
}
#endif /* USE_DEBUG_COUNTER */
