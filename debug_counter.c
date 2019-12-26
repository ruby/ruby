/**********************************************************************

  debug_counter.c -

  created at: Tue Feb 21 16:51:18 2017

  Copyright (C) 2017 Koichi Sasada

**********************************************************************/

#include "internal.h"
#include "debug_counter.h"
#include <stdio.h>
#include <locale.h>

#if USE_DEBUG_COUNTER
static const char *const debug_counter_names[] = {
    ""
#define RB_DEBUG_COUNTER(name) #name,
#include "debug_counter.h"
#undef RB_DEBUG_COUNTER
};

MJIT_SYMBOL_EXPORT_BEGIN
size_t rb_debug_counter[numberof(debug_counter_names)];
MJIT_SYMBOL_EXPORT_END

int debug_counter_disable_show_at_exit = 0;

// note that this operation is not atomic.
void
ruby_debug_counter_reset(void)
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
}

// note that this operation is not atomic.
size_t
ruby_debug_counter_get(const char **names_ptr, size_t *counters_ptr)
{
    int i;
    if (names_ptr != NULL) {
        for (i=0; i<RB_DEBUG_COUNTER_MAX; i++) {
            names_ptr[i] = debug_counter_names[i];
        }
    }
    if (counters_ptr != NULL) {
        for (i=0; i<RB_DEBUG_COUNTER_MAX; i++) {
            counters_ptr[i] = rb_debug_counter[i];
        }
    }

    return RB_DEBUG_COUNTER_MAX;
}

void
ruby_debug_counter_show_at_exit(int enable)
{
    debug_counter_disable_show_at_exit = !enable;
}

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
rb_debug_counter_show(RB_UNUSED_VAR(VALUE klass))
{
    rb_debug_counter_show_results("method call");
    return Qnil;
}

VALUE
rb_debug_counter_reset(RB_UNUSED_VAR(VALUE klass))
{
    ruby_debug_counter_reset();
    return Qnil;
}

__attribute__((destructor))
static void
debug_counter_show_results_at_exit(void)
{
    if (debug_counter_disable_show_at_exit == 0) {
        rb_debug_counter_show_results("normal exit.");
    }
}
#else
void
rb_debug_counter_show_results(const char *msg)
{
}

size_t
ruby_debug_counter_get(const char **names_ptr, size_t *counters_ptr)
{
    return 0;
}
void
ruby_debug_counter_reset(void)
{
}

void
ruby_debug_counter_show_at_exit(int enable)
{
}

#endif /* USE_DEBUG_COUNTER */
