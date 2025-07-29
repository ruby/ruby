/**********************************************************************

  debug_counter.h -

  created at: Tue Feb 21 16:51:18 2017

  Copyright (C) 2017 Koichi Sasada

**********************************************************************/

#ifndef USE_DEBUG_COUNTER
#define USE_DEBUG_COUNTER 0
#endif

#ifdef RB_DEBUG_COUNTER

// method cache (IMC: inline method cache)
RB_DEBUG_COUNTER(mc_inline_hit)              // IMC hit
RB_DEBUG_COUNTER(mc_inline_miss_klass)       // IMC miss by different class
RB_DEBUG_COUNTER(mc_inline_miss_invalidated) // IMC miss by invalidated ME
RB_DEBUG_COUNTER(mc_inline_miss_empty)       // IMC miss because prev is empty slot
RB_DEBUG_COUNTER(mc_inline_miss_same_cc)     // IMC miss, but same CC
RB_DEBUG_COUNTER(mc_inline_miss_same_cme)    // IMC miss, but same CME
RB_DEBUG_COUNTER(mc_inline_miss_same_def)    // IMC miss, but same definition
RB_DEBUG_COUNTER(mc_inline_miss_diff)        // IMC miss, different methods

RB_DEBUG_COUNTER(cvar_write_inline_hit)      // cvar cache hit on write
RB_DEBUG_COUNTER(cvar_read_inline_hit)       // cvar cache hit on read
RB_DEBUG_COUNTER(cvar_inline_miss)           // miss inline cache
RB_DEBUG_COUNTER(cvar_class_invalidate)      // invalidate cvar cache when define a cvar that's defined on a subclass
RB_DEBUG_COUNTER(cvar_include_invalidate)    // invalidate cvar cache on module include or prepend

RB_DEBUG_COUNTER(mc_cme_complement)          // number of acquiring complement CME
RB_DEBUG_COUNTER(mc_cme_complement_hit)      // number of cache hit for complemented CME

RB_DEBUG_COUNTER(mc_search)                  // count for method lookup in class tree
RB_DEBUG_COUNTER(mc_search_notfound)         //           method lookup, but not found
RB_DEBUG_COUNTER(mc_search_super)            // total traversed classes

// callinfo
RB_DEBUG_COUNTER(ci_packed)  // number of packed CI
RB_DEBUG_COUNTER(ci_kw)      //           non-packed CI w/ keywords
RB_DEBUG_COUNTER(ci_nokw)    //           non-packed CI w/o keywords
RB_DEBUG_COUNTER(ci_runtime) //           creating temporary CI

// callcache
RB_DEBUG_COUNTER(cc_new)        // number of CC
RB_DEBUG_COUNTER(cc_temp)       //           dummy CC (stack-allocated)
RB_DEBUG_COUNTER(cc_found_in_ccs)      // count for CC lookup success in CCS
RB_DEBUG_COUNTER(cc_not_found_in_ccs)  // count for CC lookup success in CCS

RB_DEBUG_COUNTER(cc_ent_invalidate) // count for invalidating cc (cc->klass = 0)
RB_DEBUG_COUNTER(cc_cme_invalidate) // count for invalidating CME

RB_DEBUG_COUNTER(cc_invalidate_leaf)          // count for invalidating klass if klass has no-subclasses
RB_DEBUG_COUNTER(cc_invalidate_leaf_ccs)      //                        corresponding CCS
RB_DEBUG_COUNTER(cc_invalidate_leaf_callable) //                        complimented cache (no-subclasses)
RB_DEBUG_COUNTER(cc_invalidate_tree)          // count for invalidating klass if klass has subclasses
RB_DEBUG_COUNTER(cc_invalidate_tree_cme)      //                        cme if cme is found in this class or superclasses
RB_DEBUG_COUNTER(cc_invalidate_tree_callable) //                        complimented cache (subclasses)
RB_DEBUG_COUNTER(cc_invalidate_negative)      // count for invalidating negative cache

RB_DEBUG_COUNTER(ccs_free)   // count for free'ing ccs
RB_DEBUG_COUNTER(ccs_maxlen) // maximum length of ccs
RB_DEBUG_COUNTER(ccs_found)      // count for finding corresponding ccs on method lookup
RB_DEBUG_COUNTER(ccs_not_found)  // count for not found corresponding ccs on method lookup

// vm_eval.c
RB_DEBUG_COUNTER(call0_public)
RB_DEBUG_COUNTER(call0_other)
RB_DEBUG_COUNTER(gccct_hit)
RB_DEBUG_COUNTER(gccct_miss)
RB_DEBUG_COUNTER(gccct_null)

// iseq
RB_DEBUG_COUNTER(iseq_num)    // number of total created iseq
RB_DEBUG_COUNTER(iseq_cd_num) // number of total created cd (call_data)

/*
 * call cache fastpath usage
 */
RB_DEBUG_COUNTER(ccf_general)
RB_DEBUG_COUNTER(ccf_iseq_setup)
RB_DEBUG_COUNTER(ccf_iseq_setup_0start)
RB_DEBUG_COUNTER(ccf_iseq_setup_tailcall_0start)
RB_DEBUG_COUNTER(ccf_iseq_fix) /* several functions created with tool/mk_call_iseq_optimized.rb */
RB_DEBUG_COUNTER(ccf_iseq_opt) /* has_opt == TRUE (has optional parameters), but other flags are FALSE */
RB_DEBUG_COUNTER(ccf_iseq_kw1) /* vm_call_iseq_setup_kwparm_kwarg() */
RB_DEBUG_COUNTER(ccf_iseq_kw2) /* vm_call_iseq_setup_kwparm_nokwarg() */
RB_DEBUG_COUNTER(ccf_cfunc)
RB_DEBUG_COUNTER(ccf_cfunc_with_frame)
RB_DEBUG_COUNTER(ccf_ivar) /* attr_reader */
RB_DEBUG_COUNTER(ccf_attrset) /* attr_writer */
RB_DEBUG_COUNTER(ccf_method_missing)
RB_DEBUG_COUNTER(ccf_zsuper)
RB_DEBUG_COUNTER(ccf_bmethod)
RB_DEBUG_COUNTER(ccf_opt_send)
RB_DEBUG_COUNTER(ccf_opt_call)
RB_DEBUG_COUNTER(ccf_opt_block_call)
RB_DEBUG_COUNTER(ccf_opt_struct_aref)
RB_DEBUG_COUNTER(ccf_opt_struct_aset)
RB_DEBUG_COUNTER(ccf_super_method)
RB_DEBUG_COUNTER(ccf_cfunc_other)
RB_DEBUG_COUNTER(ccf_cfunc_only_splat)
RB_DEBUG_COUNTER(ccf_cfunc_only_splat_kw)
RB_DEBUG_COUNTER(ccf_iseq_bmethod)
RB_DEBUG_COUNTER(ccf_noniseq_bmethod)
RB_DEBUG_COUNTER(ccf_opt_send_complex)
RB_DEBUG_COUNTER(ccf_opt_send_simple)

/*
 * control frame push counts.
 *
 * * frame_push: frame push counts.
 * * frame_push_*: frame push counts per each type.
 * * frame_R2R: Ruby frame to Ruby frame
 * * frame_R2C: Ruby frame to C frame
 * * frame_C2C: C frame to C frame
 * * frame_C2R: C frame to Ruby frame
 */
RB_DEBUG_COUNTER(frame_push)
RB_DEBUG_COUNTER(frame_push_method)
RB_DEBUG_COUNTER(frame_push_block)
RB_DEBUG_COUNTER(frame_push_class)
RB_DEBUG_COUNTER(frame_push_top)
RB_DEBUG_COUNTER(frame_push_cfunc)
RB_DEBUG_COUNTER(frame_push_ifunc)
RB_DEBUG_COUNTER(frame_push_eval)
RB_DEBUG_COUNTER(frame_push_rescue)
RB_DEBUG_COUNTER(frame_push_dummy)

RB_DEBUG_COUNTER(frame_R2R)
RB_DEBUG_COUNTER(frame_R2C)
RB_DEBUG_COUNTER(frame_C2C)
RB_DEBUG_COUNTER(frame_C2R)

/* instance variable counts */
RB_DEBUG_COUNTER(ivar_get_obj_hit)  // Only T_OBJECT hits
RB_DEBUG_COUNTER(ivar_get_obj_miss) // Only T_OBJECT misses
RB_DEBUG_COUNTER(ivar_get_ic_hit)   // All hits
RB_DEBUG_COUNTER(ivar_get_ic_miss)  // All misses
RB_DEBUG_COUNTER(ivar_set_ic_hit)   // All hits
RB_DEBUG_COUNTER(ivar_set_obj_hit)  // Only T_OBJECT hits
RB_DEBUG_COUNTER(ivar_set_obj_miss) // Only T_OBJECT misses
RB_DEBUG_COUNTER(ivar_set_ic_miss)  // All misses
RB_DEBUG_COUNTER(ivar_set_ic_miss_noobject)  // Miss because non T_OBJECT
RB_DEBUG_COUNTER(ivar_get_base) // Calls to `rb_ivar_get` (very slow path)
RB_DEBUG_COUNTER(ivar_set_base) // Calls to `ivar_set` (very slow path)
RB_DEBUG_COUNTER(ivar_get_ic_miss_set)   // Misses on IV reads where the cache was wrong
RB_DEBUG_COUNTER(ivar_get_cc_miss_set)   // Misses on attr_reader where the cache was wrong
RB_DEBUG_COUNTER(ivar_get_ic_miss_unset) // Misses on IV read where the cache wasn't set
RB_DEBUG_COUNTER(ivar_get_cc_miss_unset) // Misses on attr_reader where the cache wasn't set

/* local variable counts
 *
 * * lvar_get: total lvar get counts (VM insn)
 * * lvar_get_dynamic: lvar get counts if accessing upper env (VM insn)
 * * lvar_set*: same as "get"
 * * lvar_set_slowpath: counts using vm_env_write_slowpath()
 */
RB_DEBUG_COUNTER(lvar_get)
RB_DEBUG_COUNTER(lvar_get_dynamic)
RB_DEBUG_COUNTER(lvar_set)
RB_DEBUG_COUNTER(lvar_set_dynamic)
RB_DEBUG_COUNTER(lvar_set_slowpath)

/* GC counts:
 *
 * * count: simple count
 * * _minor: minor gc
 * * _major: major gc
 * * other suffix is corresponding to last_gc_info or
 *   gc_profile_record_flag in gc.c.
 */
RB_DEBUG_COUNTER(gc_count)
RB_DEBUG_COUNTER(gc_minor_newobj)
RB_DEBUG_COUNTER(gc_minor_malloc)
RB_DEBUG_COUNTER(gc_minor_method)
RB_DEBUG_COUNTER(gc_minor_capi)
RB_DEBUG_COUNTER(gc_minor_stress)
RB_DEBUG_COUNTER(gc_major_nofree)
RB_DEBUG_COUNTER(gc_major_oldgen)
RB_DEBUG_COUNTER(gc_major_shady)
RB_DEBUG_COUNTER(gc_major_force)
RB_DEBUG_COUNTER(gc_major_oldmalloc)

RB_DEBUG_COUNTER(gc_enter_start)
RB_DEBUG_COUNTER(gc_enter_continue)
RB_DEBUG_COUNTER(gc_enter_rest)
RB_DEBUG_COUNTER(gc_enter_finalizer)

RB_DEBUG_COUNTER(gc_isptr_trial)
RB_DEBUG_COUNTER(gc_isptr_range)
RB_DEBUG_COUNTER(gc_isptr_align)
RB_DEBUG_COUNTER(gc_isptr_maybe)

/* object allocation counts:
 *
 * * obj_newobj: newobj counts
 * * obj_newobj_slowpath: newobj with slowpath counts
 * * obj_newobj_wb_unprotected: newobj for wb_unprotected.
 * * obj_free: obj_free() counts
 * * obj_promote: promoted counts (oldgen)
 * * obj_wb_unprotect: wb unprotect counts
 *
 * * obj_[type]_[attr]: *free'ed counts* for each type.
 *                      Note that it is not a allocated counts.
 * * [type]
 *   * _obj: T_OBJECT
 *   * _str: T_STRING
 *   * _ary: T_ARRAY
 *   * _xxx: T_XXX (hash, struct, ...)
 *
 * * [attr]
 *   * _ptr: R?? is not embed.
 *   * _embed: R?? is embed.
 * * type specific attr.
 *   * str_shared: str is shared.
 *   * str_nofree:        nofree
 *   * str_fstr:          fstr
 *   * hash_empty: hash is empty
 *   * hash_1_4:       has 1 to 4 entries
 *   * hash_5_8:       has 5 to 8 entries
 *   * hash_g8:        has n entries (n>8)
 *   * match_under4:    has under 4 oniguruma regions allocated
 *   * match_ge4:       has n regions allocated (4<=n<8)
 *   * match_ge8:       has n regions allocated (8<=n)
 *   * data_empty: T_DATA but no memory free.
 *   * data_xfree:        free'ed by xfree().
 *   * data_imm_free:     free'ed immediately.
 *   * data_zombie:       free'ed with zombie.
 *   * imemo_*: T_IMEMO with each type.
 */
RB_DEBUG_COUNTER(obj_newobj)
RB_DEBUG_COUNTER(obj_newobj_slowpath)
RB_DEBUG_COUNTER(obj_newobj_wb_unprotected)
RB_DEBUG_COUNTER(obj_free)
RB_DEBUG_COUNTER(obj_promote)
RB_DEBUG_COUNTER(obj_wb_unprotect)

RB_DEBUG_COUNTER(obj_obj_embed)
RB_DEBUG_COUNTER(obj_obj_ptr)
RB_DEBUG_COUNTER(obj_obj_too_complex)

RB_DEBUG_COUNTER(obj_str_ptr)
RB_DEBUG_COUNTER(obj_str_embed)
RB_DEBUG_COUNTER(obj_str_shared)
RB_DEBUG_COUNTER(obj_str_nofree)
RB_DEBUG_COUNTER(obj_str_fstr)

RB_DEBUG_COUNTER(obj_ary_embed)
RB_DEBUG_COUNTER(obj_ary_ptr)
RB_DEBUG_COUNTER(obj_ary_extracapa)
/*
  ary_shared_create: shared ary by Array#dup and so on.
  ary_shared: finished in shard.
  ary_shared_root_occupied: shared_root but has only 1 refcnt.
    The number (ary_shared - ary_shared_root_occupied) is meaningful.
 */
RB_DEBUG_COUNTER(obj_ary_shared_create)
RB_DEBUG_COUNTER(obj_ary_shared)
RB_DEBUG_COUNTER(obj_ary_shared_root_occupied)

RB_DEBUG_COUNTER(obj_hash_empty)
RB_DEBUG_COUNTER(obj_hash_1)
RB_DEBUG_COUNTER(obj_hash_2)
RB_DEBUG_COUNTER(obj_hash_3)
RB_DEBUG_COUNTER(obj_hash_4)
RB_DEBUG_COUNTER(obj_hash_5_8)
RB_DEBUG_COUNTER(obj_hash_g8)

RB_DEBUG_COUNTER(obj_hash_null)
RB_DEBUG_COUNTER(obj_hash_ar)
RB_DEBUG_COUNTER(obj_hash_st)
RB_DEBUG_COUNTER(obj_hash_force_convert)

RB_DEBUG_COUNTER(obj_struct_embed)
RB_DEBUG_COUNTER(obj_struct_ptr)

RB_DEBUG_COUNTER(obj_data_empty)
RB_DEBUG_COUNTER(obj_data_xfree)
RB_DEBUG_COUNTER(obj_data_imm_free)
RB_DEBUG_COUNTER(obj_data_zombie)

RB_DEBUG_COUNTER(obj_match_under4)
RB_DEBUG_COUNTER(obj_match_ge4)
RB_DEBUG_COUNTER(obj_match_ge8)
RB_DEBUG_COUNTER(obj_match_ptr)

RB_DEBUG_COUNTER(obj_iclass_ptr)
RB_DEBUG_COUNTER(obj_class_ptr)
RB_DEBUG_COUNTER(obj_module_ptr)

RB_DEBUG_COUNTER(obj_bignum_ptr)
RB_DEBUG_COUNTER(obj_bignum_embed)
RB_DEBUG_COUNTER(obj_float)
RB_DEBUG_COUNTER(obj_complex)
RB_DEBUG_COUNTER(obj_rational)

RB_DEBUG_COUNTER(obj_regexp_ptr)
RB_DEBUG_COUNTER(obj_file_ptr)
RB_DEBUG_COUNTER(obj_symbol)

RB_DEBUG_COUNTER(obj_imemo_ment)
RB_DEBUG_COUNTER(obj_imemo_iseq)
RB_DEBUG_COUNTER(obj_imemo_env)
RB_DEBUG_COUNTER(obj_imemo_tmpbuf)
RB_DEBUG_COUNTER(obj_imemo_cref)
RB_DEBUG_COUNTER(obj_imemo_svar)
RB_DEBUG_COUNTER(obj_imemo_throw_data)
RB_DEBUG_COUNTER(obj_imemo_ifunc)
RB_DEBUG_COUNTER(obj_imemo_memo)
RB_DEBUG_COUNTER(obj_imemo_callinfo)
RB_DEBUG_COUNTER(obj_imemo_callcache)
RB_DEBUG_COUNTER(obj_imemo_constcache)
RB_DEBUG_COUNTER(obj_imemo_fields)

RB_DEBUG_COUNTER(opt_new_hit)
RB_DEBUG_COUNTER(opt_new_miss)

/* ar_table */
RB_DEBUG_COUNTER(artable_hint_hit)
RB_DEBUG_COUNTER(artable_hint_miss)
RB_DEBUG_COUNTER(artable_hint_notfound)

/* heap function counts
 *
 * * heap_xmalloc/realloc/xfree: call counts
 */
RB_DEBUG_COUNTER(heap_xmalloc)
RB_DEBUG_COUNTER(heap_xrealloc)
RB_DEBUG_COUNTER(heap_xfree)

// VM sync
RB_DEBUG_COUNTER(vm_sync_lock)
RB_DEBUG_COUNTER(vm_sync_lock_enter)
RB_DEBUG_COUNTER(vm_sync_lock_enter_nb)
RB_DEBUG_COUNTER(vm_sync_lock_enter_cr)
RB_DEBUG_COUNTER(vm_sync_barrier)

/* load (not implemented yet) */
/*
RB_DEBUG_COUNTER(load_files)
RB_DEBUG_COUNTER(load_path_is_not_realpath)
*/
#endif

#ifndef RUBY_DEBUG_COUNTER_H
#define RUBY_DEBUG_COUNTER_H 1

#include "ruby/internal/config.h"
#include <stddef.h>             /* for size_t */
#include "ruby/ruby.h"          /* for VALUE */

#if !defined(__GNUC__) && USE_DEBUG_COUNTER
#error "USE_DEBUG_COUNTER is not supported by other than __GNUC__"
#endif

enum rb_debug_counter_type {
#define RB_DEBUG_COUNTER(name) RB_DEBUG_COUNTER_##name,
#include "debug_counter.h"
    RB_DEBUG_COUNTER_MAX
#undef RB_DEBUG_COUNTER
};

#if USE_DEBUG_COUNTER
extern size_t rb_debug_counter[];
RUBY_EXTERN struct rb_ractor_struct *ruby_single_main_ractor;
RUBY_EXTERN void rb_debug_counter_add_atomic(enum rb_debug_counter_type type, int add);

inline static int
rb_debug_counter_add(enum rb_debug_counter_type type, int add, int cond)
{
    if (cond) {
        if (ruby_single_main_ractor != NULL) {
            rb_debug_counter[(int)type] += add;
        }
        else {
            rb_debug_counter_add_atomic(type, add);
        }
    }
    return cond;
}

inline static int
rb_debug_counter_max(enum rb_debug_counter_type type, unsigned int num)
{
    // TODO: sync
    if (rb_debug_counter[(int)type] < num) {
        rb_debug_counter[(int)type] = num;
        return 1;
    }
    else {
        return 0;
    }
}

VALUE rb_debug_counter_reset(VALUE klass);
VALUE rb_debug_counter_show(VALUE klass);

#define RB_DEBUG_COUNTER_INC(type)                rb_debug_counter_add(RB_DEBUG_COUNTER_##type, 1, 1)
#define RB_DEBUG_COUNTER_INC_UNLESS(type, cond) (!rb_debug_counter_add(RB_DEBUG_COUNTER_##type, 1, !(cond)))
#define RB_DEBUG_COUNTER_INC_IF(type, cond)       rb_debug_counter_add(RB_DEBUG_COUNTER_##type, 1, !!(cond))
#define RB_DEBUG_COUNTER_ADD(type, num)           rb_debug_counter_add(RB_DEBUG_COUNTER_##type, (num), 1)
#define RB_DEBUG_COUNTER_SETMAX(type, num)        rb_debug_counter_max(RB_DEBUG_COUNTER_##type, (unsigned int)(num))

#else
#define RB_DEBUG_COUNTER_INC(type)              ((void)0)
#define RB_DEBUG_COUNTER_INC_UNLESS(type, cond) (!!(cond))
#define RB_DEBUG_COUNTER_INC_IF(type, cond)     (!!(cond))
#define RB_DEBUG_COUNTER_ADD(type, num)         ((void)0)
#define RB_DEBUG_COUNTER_SETMAX(type, num)      0
#endif

void rb_debug_counter_show_results(const char *msg);

RUBY_SYMBOL_EXPORT_BEGIN

size_t ruby_debug_counter_get(const char **names_ptr, size_t *counters_ptr);
void ruby_debug_counter_reset(void);
void ruby_debug_counter_show_at_exit(int enable);

RUBY_SYMBOL_EXPORT_END

#endif /* RUBY_DEBUG_COUNTER_H */
