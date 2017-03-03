/**********************************************************************

  debug_counter.h -

  created at: Tue Feb 21 16:51:18 2017

  Copyright (C) 2017 Koichi Sasada

**********************************************************************/

#ifndef RUBY_DEBUG_COUNTER_H
#define RUBY_DEBUG_COUNTER_H 1

#ifndef USE_DEBUG_COUNTER
#define USE_DEBUG_COUNTER 0
#endif

#if !defined(__GNUC__) && USE_DEBUG_COUNTER
#error "USE_DEBUG_COUNTER is not supported by other than __GNUC__"
#endif

enum rb_debug_counter_type {
#define COUNTER(name) RB_DEBUG_COUNTER_##name
    COUNTER(mc_inline_hit),
    COUNTER(mc_inline_miss),
    COUNTER(mc_global_hit),
    COUNTER(mc_global_miss),
    COUNTER(mc_global_state_miss),
    COUNTER(mc_class_serial_miss),
    COUNTER(mc_cme_complement),
    COUNTER(mc_cme_complement_hit),
    COUNTER(mc_search_super),
    COUNTER(ivar_get_hit),
    COUNTER(ivar_get_miss),
    COUNTER(ivar_set_hit),
    COUNTER(ivar_set_miss),
    COUNTER(ivar_get),
    COUNTER(ivar_set),
    RB_DEBUG_COUNTER_MAX
#undef COUNTER
};

#if USE_DEBUG_COUNTER
#include "ruby/ruby.h"

extern size_t rb_debug_counter[RB_DEBUG_COUNTER_MAX + 1];

inline static int
rb_debug_counter_add(enum rb_debug_counter_type type, int add, int cond)
{
    if (cond) {
	rb_debug_counter[(int)type] += add;
    }
    return cond;
}

#define RB_DEBUG_COUNTER_INC(type)                rb_debug_counter_add(RB_DEBUG_COUNTER_##type, 1, 1)
#define RB_DEBUG_COUNTER_INC_UNLESS(type, cond) (!rb_debug_counter_add(RB_DEBUG_COUNTER_##type, 1, !(cond)))
#define RB_DEBUG_COUNTER_INC_IF(type, cond)       rb_debug_counter_add(RB_DEBUG_COUNTER_##type, 1, (cond))

#else
#define RB_DEBUG_COUNTER_INC(type)              ((void)0)
#define RB_DEBUG_COUNTER_INC_UNLESS(type, cond) (cond)
#define RB_DEBUG_COUNTER_INC_IF(type, cond)     (cond)
#endif

#endif /* RUBY_DEBUG_COUNTER_H */
