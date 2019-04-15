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

MJIT_SYMBOL_EXPORT_BEGIN
size_t rb_debug_counter[numberof(debug_counter_names)];
MJIT_SYMBOL_EXPORT_END

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

VALUE
rb_debug_counter_reset(void)
{
    for (int i = 0; i < RB_DEBUG_COUNTER_MAX; i++) {
        switch (i) {
          case RB_DEBUG_COUNTER_mjit_length_unit_queue:
          case RB_DEBUG_COUNTER_mjit_length_active_units:
          case RB_DEBUG_COUNTER_mjit_length_compact_units:
          case RB_DEBUG_COUNTER_mjit_length_stale_units:
            // These counters may be decreased and should not be reset.
            break;
          default:
            rb_debug_counter[i] = 0;
            break;
        }
    }
    return Qnil;
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
