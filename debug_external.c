/**********************************************************************

  debug_external.c -

  $Author: kjtsanaktsidis $
  created at: Wed Nov 09 06:24:48 2022

  Copyright (C) 1993-2012 Konstantinos Tsanaktsidis

**********************************************************************/

#include "gc.h"
#include "probes.h"
#include "ruby.h"
#include "ruby/atomic.h"
#include "ruby/debug_external.h"
#include "ruby/st.h"
#include "vm_debug.h"
#include "vm_sync.h"

__attribute__(( section("rb_debug_ext") ))
rb_debug_ext_section_t rb_debug_ext_section = {
    .sizeof_section       = sizeof(rb_debug_ext_section_t),
    .sizeof_ec            = sizeof(rb_debug_ext_ec_t),
    .sizeof_frame         = sizeof(rb_debug_ext_frame_t),
    .strideof_frame       = -sizeof(rb_control_frame_t),
    .ecs                  = NULL,
    .ecs_size             = 0
};

static st_table *ecs_free_indexes;
static st_table *ecs_occupied_indexes;
#define INIT_EC_ARRAY_SIZE 2
static inline size_t EC_ARRAY_GROWTH_SIZE(size_t val) { return val * 2 + 1; }

void
Init_debug_external(void)
{
    /* We need to make sure that the malloc routines used by st_table don't trigger a GC,
     * since the ecs_* tables get accessed very early and very late */
    VALUE gc_already_disabled = rb_gc_disable_no_rest();

    ecs_free_indexes = st_init_numtable();
    rb_debug_ext_ec_t **ec_array = calloc(INIT_EC_ARRAY_SIZE, sizeof(rb_debug_ext_ec_t *));
    for (int i = 0; i < INIT_EC_ARRAY_SIZE; i++) {
        st_insert(ecs_free_indexes, (st_data_t)i, (st_data_t)0);
    }

    ecs_occupied_indexes = st_init_numtable();
    
    /* n.b. - these elements of rb_debug_ext_section are stored with atomic intrinsics. This is NOT
     * to prevent races wihin threads inside the same program; the use of RB_VM_LOCK_ENTER() already
     * prevents this. Rather, this is to ensure that if the process is stopped (e.g. via ptrace), an
     * external process (i.e. a debugger or profiler) can get a consistent view of the contents of the
     * rb_debug_ext_section structure. */
    RUBY_ATOMIC_PTR_SET(rb_debug_ext_section.ecs, ec_array);
    RUBY_ATOMIC_SIZE_SET(rb_debug_ext_section.ecs_size, INIT_EC_ARRAY_SIZE);

    if (gc_already_disabled == Qfalse) {
        rb_gc_enable();
    }
}

void
rb_debug_ext_ec_insert(rb_debug_ext_ec_t *ec_ext)
{
    RB_VM_LOCK_ENTER();
    VALUE gc_already_disabled = rb_gc_disable_no_rest();

    size_t insert_index;
    st_data_t keys[1];
    int keys_returned = st_keys(ecs_free_indexes, keys, 1);
    if (UNLIKELY(keys_returned == 0)) {
        /* Need to grow the array. */
        size_t current_size = RUBY_ATOMIC_SIZE_LOAD(rb_debug_ext_section.ecs_size);
        rb_debug_ext_ec_t **current_array = RUBY_ATOMIC_PTR_LOAD(rb_debug_ext_section.ecs);
        size_t new_size = EC_ARRAY_GROWTH_SIZE(current_size);
        rb_debug_ext_ec_t **new_array = calloc(new_size, sizeof(rb_debug_ext_ec_t *));
        memcpy(new_array, current_array, current_size);
        /* probably need to put a thread fence in here, since memcpy won't be using atomics */
        RUBY_ATOMIC_BARRIER();
        
        /* Use the first new slot for the new entry */
        VM_ASSERT(new_size > current_size);
        insert_index = new_size - current_size;
        for (size_t i = insert_index; i < new_size; i++) {
            st_insert(ecs_free_indexes, (st_data_t)i, (st_data_t)0);
        }
        
        RUBY_ATOMIC_PTR_SET(rb_debug_ext_section.ecs, new_array);
        RUBY_ATOMIC_SIZE_SET(rb_debug_ext_section.ecs_size, new_size);
        free(current_array);
    } else {
        insert_index = keys[0];
    }

    st_delete(ecs_free_indexes, (st_data_t *)&insert_index, NULL);
    st_insert(ecs_occupied_indexes, (st_data_t)ec_ext, (st_data_t)insert_index);
    RUBY_ATOMIC_PTR_SET(rb_debug_ext_section.ecs[insert_index], ec_ext);

    if (gc_already_disabled == Qfalse) {
        rb_gc_enable();
    }
    RB_VM_LOCK_LEAVE();

    RUBY_DTRACE_EXTERNAL_DEBUG_EC_ADDED(ec_ext);
}

static void
rb_debug_ext_ec_remove_impl(rb_debug_ext_ec_t *ec_ext)
{
    VALUE gc_already_disabled = rb_gc_disable_no_rest();

    size_t index;
    int RB_UNUSED_VAR(deleted);
    deleted = st_delete(ecs_occupied_indexes, (st_data_t *)&ec_ext, (st_data_t *)&index);
    VM_ASSERT(deleted);
    st_insert(ecs_occupied_indexes, (st_data_t)index, (st_data_t)0);
    RUBY_ATOMIC_PTR_SET(rb_debug_ext_section.ecs[index], NULL);

    if (gc_already_disabled == Qfalse) {
        rb_gc_enable();
    }
}

void
rb_debug_ext_ec_remove(rb_debug_ext_ec_t *ec_ext)
{
    RUBY_DTRACE_EXTERNAL_DEBUG_EC_REMOVED(ec_ext);

    /* This gets called during VM cleanup, where there is no longer any EC
     * and so RB_VM_LOCK_ENTER won't work. */
    if (rb_current_execution_context(false)) {
        RB_VM_LOCK_ENTER();
        rb_debug_ext_ec_remove_impl(ec_ext);
        RB_VM_LOCK_LEAVE();
    } else {
        rb_debug_ext_ec_remove_impl(ec_ext);
    }
}

