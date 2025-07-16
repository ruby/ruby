#ifndef GC_GC_H
#define GC_GC_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Private header for the default GC and other GC implementations
 *             first introduced for [Feature #20470].
 */
#include "ruby/ruby.h"

#if USE_MODULAR_GC
#include "ruby/thread_native.h"

struct rb_gc_vm_context {
    rb_nativethread_lock_t lock;

    struct rb_execution_context_struct *ec;
};
#endif

typedef int (*vm_table_foreach_callback_func)(VALUE value, void *data);
typedef int (*vm_table_update_callback_func)(VALUE *value, void *data);

enum rb_gc_vm_weak_tables {
    RB_GC_VM_CI_TABLE,
    RB_GC_VM_OVERLOADED_CME_TABLE,
    RB_GC_VM_GLOBAL_SYMBOLS_TABLE,
    RB_GC_VM_ID2REF_TABLE,
    RB_GC_VM_GENERIC_FIELDS_TABLE,
    RB_GC_VM_FROZEN_STRINGS_TABLE,
    RB_GC_VM_CC_REFINEMENT_TABLE,
    RB_GC_VM_WEAK_TABLE_COUNT
};

#define RB_GC_VM_LOCK() rb_gc_vm_lock(__FILE__, __LINE__)
#define RB_GC_VM_UNLOCK(lev) rb_gc_vm_unlock(lev, __FILE__, __LINE__)
#define RB_GC_CR_LOCK() rb_gc_cr_lock(__FILE__, __LINE__)
#define RB_GC_CR_UNLOCK(lev) rb_gc_cr_unlock(lev, __FILE__, __LINE__)
#define RB_GC_VM_LOCK_NO_BARRIER() rb_gc_vm_lock_no_barrier(__FILE__, __LINE__)
#define RB_GC_VM_UNLOCK_NO_BARRIER(lev) rb_gc_vm_unlock_no_barrier(lev, __FILE__, __LINE__)

#if USE_MODULAR_GC
# define MODULAR_GC_FN
#else
// This takes advantage of internal linkage winning when appearing first.
// See C99 6.2.2p4.
# define MODULAR_GC_FN static
#endif

#if USE_MODULAR_GC
RUBY_SYMBOL_EXPORT_BEGIN
#endif

// These functions cannot be defined as static because they are used by other
// files in Ruby.
size_t rb_size_mul_or_raise(size_t x, size_t y, VALUE exc);
void rb_objspace_reachable_objects_from(VALUE obj, void (func)(VALUE, void *), void *data);
void rb_obj_info_dump(VALUE obj);
const char *rb_obj_info(VALUE obj);
size_t rb_obj_memsize_of(VALUE obj);
bool ruby_free_at_exit_p(void);
void rb_objspace_reachable_objects_from_root(void (func)(const char *category, VALUE, void *), void *passing_data);

MODULAR_GC_FN unsigned int rb_gc_vm_lock(const char *file, int line);
MODULAR_GC_FN void rb_gc_vm_unlock(unsigned int lev, const char *file, int line);
MODULAR_GC_FN unsigned int rb_gc_cr_lock(const char *file, int line);
MODULAR_GC_FN void rb_gc_cr_unlock(unsigned int lev, const char *file, int line);
MODULAR_GC_FN unsigned int rb_gc_vm_lock_no_barrier(const char *file, int line);
MODULAR_GC_FN void rb_gc_vm_unlock_no_barrier(unsigned int lev, const char *file, int line);
MODULAR_GC_FN void rb_gc_vm_barrier(void);
MODULAR_GC_FN size_t rb_gc_obj_optimal_size(VALUE obj);
MODULAR_GC_FN void rb_gc_mark_children(void *objspace, VALUE obj);
MODULAR_GC_FN void rb_gc_vm_weak_table_foreach(vm_table_foreach_callback_func callback, vm_table_update_callback_func update_callback, void *data, bool weak_only, enum rb_gc_vm_weak_tables table);
MODULAR_GC_FN void rb_gc_update_object_references(void *objspace, VALUE obj);
MODULAR_GC_FN void rb_gc_update_moved_object(void *objspace, VALUE dest, VALUE src);
MODULAR_GC_FN void rb_gc_update_vm_references(void *objspace);
MODULAR_GC_FN void rb_gc_event_hook(VALUE obj, rb_event_flag_t event);
MODULAR_GC_FN void *rb_gc_get_objspace(void);
MODULAR_GC_FN void rb_gc_run_obj_finalizer(VALUE objid, long count, VALUE (*callback)(long i, void *data), void *data);
MODULAR_GC_FN void rb_gc_set_pending_interrupt(void);
MODULAR_GC_FN void rb_gc_unset_pending_interrupt(void);
MODULAR_GC_FN void rb_gc_obj_free_vm_weak_references(VALUE obj);
MODULAR_GC_FN bool rb_gc_obj_free(void *objspace, VALUE obj);
MODULAR_GC_FN void rb_gc_save_machine_context(void);
MODULAR_GC_FN void rb_gc_mark_roots(void *objspace, const char **categoryp);
MODULAR_GC_FN void rb_gc_ractor_newobj_cache_foreach(void (*func)(void *cache, void *data), void *data);
MODULAR_GC_FN bool rb_gc_multi_ractor_p(void);
MODULAR_GC_FN bool rb_gc_shutdown_call_finalizer_p(VALUE obj);
MODULAR_GC_FN uint32_t rb_gc_get_shape(VALUE obj);
MODULAR_GC_FN void rb_gc_set_shape(VALUE obj, uint32_t shape_id);
MODULAR_GC_FN uint32_t rb_gc_rebuild_shape(VALUE obj, size_t heap_id);
MODULAR_GC_FN void rb_gc_prepare_heap_process_object(VALUE obj);
MODULAR_GC_FN bool rb_memerror_reentered(void);
MODULAR_GC_FN bool rb_obj_id_p(VALUE);
MODULAR_GC_FN void rb_gc_before_updating_jit_code(void);
MODULAR_GC_FN void rb_gc_after_updating_jit_code(void);

#if USE_MODULAR_GC
MODULAR_GC_FN bool rb_gc_event_hook_required_p(rb_event_flag_t event);
MODULAR_GC_FN void *rb_gc_get_ractor_newobj_cache(void);
MODULAR_GC_FN void rb_gc_initialize_vm_context(struct rb_gc_vm_context *context);
MODULAR_GC_FN void rb_gc_worker_thread_set_vm_context(struct rb_gc_vm_context *context);
MODULAR_GC_FN void rb_gc_worker_thread_unset_vm_context(struct rb_gc_vm_context *context);
#endif

#if USE_MODULAR_GC
RUBY_SYMBOL_EXPORT_END
#endif

void rb_ractor_finish_marking(void);

// -------------------Private section begin------------------------
// Functions in this section are private to the default GC and gc.c

#ifdef BUILDING_MODULAR_GC
RBIMPL_WARNING_PUSH()
RBIMPL_WARNING_IGNORED(-Wunused-function)
#endif

/* RGENGC_CHECK_MODE
 * 0: disable all assertions
 * 1: enable assertions (to debug RGenGC)
 * 2: enable internal consistency check at each GC (for debugging)
 * 3: enable internal consistency check at each GC steps (for debugging)
 * 4: enable liveness check
 * 5: show all references
 */
#ifndef RGENGC_CHECK_MODE
# define RGENGC_CHECK_MODE  0
#endif

#ifndef GC_ASSERT
# define GC_ASSERT(expr, ...) RUBY_ASSERT_MESG_WHEN(RGENGC_CHECK_MODE > 0, expr, #expr RBIMPL_VA_OPT_ARGS(__VA_ARGS__))
#endif

static int
hash_foreach_replace_value(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    if (rb_gc_location((VALUE)value) != (VALUE)value) {
        return ST_REPLACE;
    }
    return ST_CONTINUE;
}

static int
hash_replace_ref_value(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    *value = rb_gc_location((VALUE)*value);

    return ST_CONTINUE;
}

static void
gc_ref_update_table_values_only(st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;

    if (st_foreach_with_replace(tbl, hash_foreach_replace_value, hash_replace_ref_value, 0)) {
        rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

static int
gc_mark_tbl_no_pin_i(st_data_t key, st_data_t value, st_data_t data)
{
    rb_gc_mark_movable((VALUE)value);

    return ST_CONTINUE;
}

static int
hash_foreach_replace(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    if (rb_gc_location((VALUE)key) != (VALUE)key) {
        return ST_REPLACE;
    }

    if (rb_gc_location((VALUE)value) != (VALUE)value) {
        return ST_REPLACE;
    }

    return ST_CONTINUE;
}

static int
hash_replace_ref(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    if (rb_gc_location((VALUE)*key) != (VALUE)*key) {
        *key = rb_gc_location((VALUE)*key);
    }

    if (rb_gc_location((VALUE)*value) != (VALUE)*value) {
        *value = rb_gc_location((VALUE)*value);
    }

    return ST_CONTINUE;
}

static void
gc_update_table_refs(st_table *tbl)
{
    if (!tbl || tbl->num_entries == 0) return;

    if (st_foreach_with_replace(tbl, hash_foreach_replace, hash_replace_ref, 0)) {
        rb_raise(rb_eRuntimeError, "hash modified during iteration");
    }
}

static inline size_t
xmalloc2_size(const size_t count, const size_t elsize)
{
    return rb_size_mul_or_raise(count, elsize, rb_eArgError);
}

static VALUE
type_sym(size_t type)
{
    switch (type) {
#define COUNT_TYPE(t) case (t): return ID2SYM(rb_intern(#t)); break;
        COUNT_TYPE(T_NONE);
        COUNT_TYPE(T_OBJECT);
        COUNT_TYPE(T_CLASS);
        COUNT_TYPE(T_MODULE);
        COUNT_TYPE(T_FLOAT);
        COUNT_TYPE(T_STRING);
        COUNT_TYPE(T_REGEXP);
        COUNT_TYPE(T_ARRAY);
        COUNT_TYPE(T_HASH);
        COUNT_TYPE(T_STRUCT);
        COUNT_TYPE(T_BIGNUM);
        COUNT_TYPE(T_FILE);
        COUNT_TYPE(T_DATA);
        COUNT_TYPE(T_MATCH);
        COUNT_TYPE(T_COMPLEX);
        COUNT_TYPE(T_RATIONAL);
        COUNT_TYPE(T_NIL);
        COUNT_TYPE(T_TRUE);
        COUNT_TYPE(T_FALSE);
        COUNT_TYPE(T_SYMBOL);
        COUNT_TYPE(T_FIXNUM);
        COUNT_TYPE(T_IMEMO);
        COUNT_TYPE(T_UNDEF);
        COUNT_TYPE(T_NODE);
        COUNT_TYPE(T_ICLASS);
        COUNT_TYPE(T_ZOMBIE);
        COUNT_TYPE(T_MOVED);
#undef COUNT_TYPE
        default:              return SIZET2NUM(type); break;
    }
}

#ifdef BUILDING_MODULAR_GC
RBIMPL_WARNING_POP()
#endif
// -------------------Private section end------------------------

#endif
