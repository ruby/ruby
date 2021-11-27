/*
 * This file is included by vm.c
 */

#include "id_table.h"
#include "yjit.h"

#define METHOD_DEBUG 0

static int vm_redefinition_check_flag(VALUE klass);
static void rb_vm_check_redefinition_opt_method(const rb_method_entry_t *me, VALUE klass);
static inline rb_method_entry_t *lookup_method_table(VALUE klass, ID id);

#define object_id           idObject_id
#define added               idMethod_added
#define singleton_added     idSingleton_method_added
#define removed             idMethod_removed
#define singleton_removed   idSingleton_method_removed
#define undefined           idMethod_undefined
#define singleton_undefined idSingleton_method_undefined
#define attached            id__attached__

#define ruby_running (GET_VM()->running)
/* int ruby_running = 0; */

static enum rb_id_table_iterator_result
vm_ccs_dump_i(ID mid, VALUE val, void *data)
{
    const struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)val;
    fprintf(stderr,     "  | %s (len:%d) ", rb_id2name(mid), ccs->len);
    rp(ccs->cme);

    for (int i=0; i<ccs->len; i++) {
        fprintf(stderr, "  | [%d]\t", i); vm_ci_dump(ccs->entries[i].ci);
        rp_m(           "  |   \t", ccs->entries[i].cc);
    }

    return ID_TABLE_CONTINUE;
}

static void
vm_ccs_dump(VALUE klass, ID target_mid)
{
    struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);
    if (cc_tbl) {
        VALUE ccs;
        if (target_mid) {
            if (rb_id_table_lookup(cc_tbl, target_mid, &ccs)) {
                fprintf(stderr, "  [CCTB] %p\n", (void *)cc_tbl);
                vm_ccs_dump_i(target_mid, ccs, NULL);
            }
        }
        else {
            fprintf(stderr, "  [CCTB] %p\n", (void *)cc_tbl);
            rb_id_table_foreach(cc_tbl, vm_ccs_dump_i, (void *)target_mid);
        }
    }
}

static enum rb_id_table_iterator_result
vm_cme_dump_i(ID mid, VALUE val, void *data)
{
    ID target_mid = (ID)data;
    if (target_mid == 0 || mid == target_mid) {
        rp_m("  > ", val);
    }
    return ID_TABLE_CONTINUE;
}

static VALUE
vm_mtbl_dump(VALUE klass, ID target_mid)
{
    fprintf(stderr, "# vm_mtbl\n");
    while (klass) {
        rp_m("  -> ", klass);
        VALUE me;

        if (RCLASS_M_TBL(klass)) {
            if (target_mid != 0) {
                if (rb_id_table_lookup(RCLASS_M_TBL(klass), target_mid, &me)) {
                    rp_m("  [MTBL] ", me);
                }
            }
            else {
                fprintf(stderr, "  ## RCLASS_M_TBL (%p)\n", (void *)RCLASS_M_TBL(klass));
                rb_id_table_foreach(RCLASS_M_TBL(klass), vm_cme_dump_i, NULL);
            }
        }
        else {
            fprintf(stderr, "    MTBL: NULL\n");
        }
        if (RCLASS_CALLABLE_M_TBL(klass)) {
            if (target_mid != 0) {
                if (rb_id_table_lookup(RCLASS_CALLABLE_M_TBL(klass), target_mid, &me)) {
                    rp_m("  [CM**] ", me);
                }
            }
            else {
                fprintf(stderr, "  ## RCLASS_CALLABLE_M_TBL\n");
                rb_id_table_foreach(RCLASS_CALLABLE_M_TBL(klass), vm_cme_dump_i, NULL);
            }
        }
        if (RCLASS_CC_TBL(klass)) {
            vm_ccs_dump(klass, target_mid);
        }
        klass = RCLASS_SUPER(klass);
    }
    return Qnil;
}

void
rb_vm_mtbl_dump(const char *msg, VALUE klass, ID target_mid)
{
    fprintf(stderr, "[%s] ", msg);
    vm_mtbl_dump(klass, target_mid);
}

static inline void
vm_cme_invalidate(rb_callable_method_entry_t *cme)
{
    VM_ASSERT(IMEMO_TYPE_P(cme, imemo_ment));
    VM_ASSERT(callable_method_entry_p(cme));
    METHOD_ENTRY_INVALIDATED_SET(cme);
    RB_DEBUG_COUNTER_INC(cc_cme_invalidate);

    rb_yjit_cme_invalidate((VALUE)cme);
}

void
rb_clear_constant_cache(void)
{
    rb_yjit_constant_state_changed();
    INC_GLOBAL_CONSTANT_STATE();
}

static void
invalidate_negative_cache(ID mid)
{
    VALUE cme;
    rb_vm_t *vm = GET_VM();

    if (rb_id_table_lookup(vm->negative_cme_table, mid, &cme)) {
        rb_id_table_delete(vm->negative_cme_table, mid);
        vm_cme_invalidate((rb_callable_method_entry_t *)cme);
        RB_DEBUG_COUNTER_INC(cc_invalidate_negative);
    }
}

static rb_method_entry_t *rb_method_entry_alloc(ID called_id, VALUE owner, VALUE defined_class, const rb_method_definition_t *def);
const rb_method_entry_t * rb_method_entry_clone(const rb_method_entry_t *src_me);
static const rb_callable_method_entry_t *complemented_callable_method_entry(VALUE klass, ID id);

static void
clear_method_cache_by_id_in_class(VALUE klass, ID mid)
{
    VM_ASSERT(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_ICLASS));
    if (rb_objspace_garbage_object_p(klass)) return;

    if (LIKELY(RCLASS_SUBCLASSES(klass) == NULL)) {
        // no subclasses
        // check only current class

        struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);
        VALUE ccs_data;

        // invalidate CCs
        if (cc_tbl && rb_id_table_lookup(cc_tbl, mid, &ccs_data)) {
            struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)ccs_data;
            if (NIL_P(ccs->cme->owner)) invalidate_negative_cache(mid);
            rb_vm_ccs_free(ccs);
            rb_id_table_delete(cc_tbl, mid);
            RB_DEBUG_COUNTER_INC(cc_invalidate_leaf_ccs);
        }

        // remove from callable_m_tbl, if exists
        struct rb_id_table *cm_tbl;
        if ((cm_tbl = RCLASS_CALLABLE_M_TBL(klass)) != NULL) {
            rb_id_table_delete(cm_tbl, mid);
            RB_DEBUG_COUNTER_INC(cc_invalidate_leaf_callable);
        }
        RB_DEBUG_COUNTER_INC(cc_invalidate_leaf);
    }
    else {
        const rb_callable_method_entry_t *cme = complemented_callable_method_entry(klass, mid);

        if (cme) {
            // invalidate cme if found to invalidate the inline method cache.
            if (METHOD_ENTRY_CACHED(cme)) {
                if (METHOD_ENTRY_COMPLEMENTED(cme)) {
                    // do nothing
                }
                else {
                    // invalidate cc by invalidating cc->cme
                    VALUE owner = cme->owner;
                    VM_ASSERT(BUILTIN_TYPE(owner) == T_CLASS);
                    VALUE klass_housing_cme;
                    if (cme->def->type == VM_METHOD_TYPE_REFINED && !cme->def->body.refined.orig_me) {
                        klass_housing_cme = owner;
                    }
                    else {
                        klass_housing_cme = RCLASS_ORIGIN(owner);
                    }
                    // replace the cme that will be invalid
                    VM_ASSERT(lookup_method_table(klass_housing_cme, mid) == (const rb_method_entry_t *)cme);
                    const rb_method_entry_t *new_cme = rb_method_entry_clone((const rb_method_entry_t *)cme);
                    rb_method_table_insert(klass_housing_cme, RCLASS_M_TBL(klass_housing_cme), mid, new_cme);
                }

                vm_cme_invalidate((rb_callable_method_entry_t *)cme);
                RB_DEBUG_COUNTER_INC(cc_invalidate_tree_cme);

                if (cme->def->iseq_overload && cme->def->body.iseq.mandatory_only_cme) {
                    vm_cme_invalidate((rb_callable_method_entry_t *)cme->def->body.iseq.mandatory_only_cme);
                }
            }

            // invalidate complement tbl
            if (METHOD_ENTRY_COMPLEMENTED(cme)) {
                VALUE defined_class = cme->defined_class;
                struct rb_id_table *cm_tbl = RCLASS_CALLABLE_M_TBL(defined_class);
                VM_ASSERT(cm_tbl != NULL);
                int r = rb_id_table_delete(cm_tbl, mid);
                VM_ASSERT(r == TRUE); (void)r;
                RB_DEBUG_COUNTER_INC(cc_invalidate_tree_callable);
            }

            RB_DEBUG_COUNTER_INC(cc_invalidate_tree);
        }
        else {
            invalidate_negative_cache(mid);
        }
    }

    rb_yjit_method_lookup_change(klass, mid);
}

static void
clear_iclass_method_cache_by_id(VALUE iclass, VALUE d)
{
    VM_ASSERT(RB_TYPE_P(iclass, T_ICLASS));
    ID mid = (ID)d;
    clear_method_cache_by_id_in_class(iclass, mid);
}

static void
clear_iclass_method_cache_by_id_for_refinements(VALUE klass, VALUE d)
{
    if (RB_TYPE_P(klass, T_ICLASS)) {
        ID mid = (ID)d;
        clear_method_cache_by_id_in_class(klass, mid);
    }
}

void
rb_clear_method_cache(VALUE klass_or_module, ID mid)
{
    if (RB_TYPE_P(klass_or_module, T_MODULE)) {
        VALUE module = klass_or_module; // alias

        if (FL_TEST(module, RMODULE_IS_REFINEMENT)) {
            VALUE refined_class = rb_refinement_module_get_refined_class(module);
            rb_clear_method_cache(refined_class, mid);
            rb_class_foreach_subclass(refined_class, clear_iclass_method_cache_by_id_for_refinements, mid);
        }
        rb_class_foreach_subclass(module, clear_iclass_method_cache_by_id, mid);
    }
    else {
        clear_method_cache_by_id_in_class(klass_or_module, mid);
    }
}

// gc.c
void rb_cc_table_free(VALUE klass);

static int
invalidate_all_cc(void *vstart, void *vend, size_t stride, void *data)
{
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        void *ptr = asan_poisoned_object_p(v);
        asan_unpoison_object(v, false);
        if (RBASIC(v)->flags) { // liveness check
            if (RB_TYPE_P(v, T_CLASS) ||
                RB_TYPE_P(v, T_ICLASS)) {
                if (RCLASS_CC_TBL(v)) {
                    rb_cc_table_free(v);
                }
                RCLASS_CC_TBL(v) = NULL;
            }
        }
        if (ptr) {
            asan_poison_object(v);
        }
    }
    return 0; // continue to iteration
}

void
rb_clear_method_cache_all(void)
{
    rb_objspace_each_objects(invalidate_all_cc, NULL);

    rb_yjit_invalidate_all_method_lookup_assumptions();
}

void
rb_method_table_insert(VALUE klass, struct rb_id_table *table, ID method_id, const rb_method_entry_t *me)
{
    VALUE table_owner = klass;
    if (RB_TYPE_P(klass, T_ICLASS) && !RICLASS_OWNS_M_TBL_P(klass)) {
        table_owner = RBASIC(table_owner)->klass;
    }
    VM_ASSERT(RB_TYPE_P(table_owner, T_CLASS) || RB_TYPE_P(table_owner, T_ICLASS) || RB_TYPE_P(table_owner, T_MODULE));
    VM_ASSERT(table == RCLASS_M_TBL(table_owner));
    rb_id_table_insert(table, method_id, (VALUE)me);
    RB_OBJ_WRITTEN(table_owner, Qundef, (VALUE)me);
}

VALUE
rb_f_notimplement(int argc, const VALUE *argv, VALUE obj, VALUE marker)
{
    rb_notimplement();

    UNREACHABLE_RETURN(Qnil);
}

static void
rb_define_notimplement_method_id(VALUE mod, ID id, rb_method_visibility_t visi)
{
    rb_add_method(mod, id, VM_METHOD_TYPE_NOTIMPLEMENTED, (void *)1, visi);
}

void
rb_add_method_cfunc(VALUE klass, ID mid, VALUE (*func)(ANYARGS), int argc, rb_method_visibility_t visi)
{
    if (argc < -2 || 15 < argc) rb_raise(rb_eArgError, "arity out of range: %d for -2..15", argc);
    if (func != rb_f_notimplement) {
	rb_method_cfunc_t opt;
	opt.func = func;
	opt.argc = argc;
        rb_add_method(klass, mid, VM_METHOD_TYPE_CFUNC, &opt, visi);
    }
    else {
	rb_define_notimplement_method_id(klass, mid, visi);
    }
}

void
rb_add_method_optimized(VALUE klass, ID mid, enum method_optimized_type opt_type, unsigned int index, rb_method_visibility_t visi)
{
    rb_method_optimized_t opt = {
        .type = opt_type,
        .index = index,
    };
    rb_add_method(klass, mid, VM_METHOD_TYPE_OPTIMIZED, &opt, visi);
}

static void
rb_method_definition_release(rb_method_definition_t *def, int complemented)
{
    if (def != NULL) {
	const int alias_count = def->alias_count;
	const int complemented_count = def->complemented_count;
	VM_ASSERT(alias_count >= 0);
	VM_ASSERT(complemented_count >= 0);

	if (alias_count + complemented_count == 0) {
            if (METHOD_DEBUG) fprintf(stderr, "-%p-%s:%d,%d (remove)\n", (void *)def,
                                      rb_id2name(def->original_id), alias_count, complemented_count);
            if (def->type == VM_METHOD_TYPE_BMETHOD && def->body.bmethod.hooks) {
                xfree(def->body.bmethod.hooks);
            }
	    xfree(def);
	}
	else {
            if (complemented) {
                VM_ASSERT(def->complemented_count > 0);
                def->complemented_count--;
            }
            else if (def->alias_count > 0) {
                def->alias_count--;
            }

	    if (METHOD_DEBUG) fprintf(stderr, "-%p-%s:%d->%d,%d->%d (dec)\n", (void *)def, rb_id2name(def->original_id),
				      alias_count, def->alias_count, complemented_count, def->complemented_count);
	}
    }
}

void
rb_free_method_entry(const rb_method_entry_t *me)
{
    rb_method_definition_release(me->def, METHOD_ENTRY_COMPLEMENTED(me));
}

static inline rb_method_entry_t *search_method(VALUE klass, ID id, VALUE *defined_class_ptr);
extern int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);

static VALUE
(*call_cfunc_invoker_func(int argc))(VALUE recv, int argc, const VALUE *, VALUE (*func)(ANYARGS))
{
    if (!GET_THREAD()->ext_config.ractor_safe) {
        switch (argc) {
          case -2: return &call_cfunc_m2;
          case -1: return &call_cfunc_m1;
          case 0: return &call_cfunc_0;
          case 1: return &call_cfunc_1;
          case 2: return &call_cfunc_2;
          case 3: return &call_cfunc_3;
          case 4: return &call_cfunc_4;
          case 5: return &call_cfunc_5;
          case 6: return &call_cfunc_6;
          case 7: return &call_cfunc_7;
          case 8: return &call_cfunc_8;
          case 9: return &call_cfunc_9;
          case 10: return &call_cfunc_10;
          case 11: return &call_cfunc_11;
          case 12: return &call_cfunc_12;
          case 13: return &call_cfunc_13;
          case 14: return &call_cfunc_14;
          case 15: return &call_cfunc_15;
          default:
            rb_bug("unsupported length: %d", argc);
        }
    }
    else {
        switch (argc) {
          case -2: return &ractor_safe_call_cfunc_m2;
          case -1: return &ractor_safe_call_cfunc_m1;
          case 0: return  &ractor_safe_call_cfunc_0;
          case 1: return  &ractor_safe_call_cfunc_1;
          case 2: return  &ractor_safe_call_cfunc_2;
          case 3: return  &ractor_safe_call_cfunc_3;
          case 4: return  &ractor_safe_call_cfunc_4;
          case 5: return  &ractor_safe_call_cfunc_5;
          case 6: return  &ractor_safe_call_cfunc_6;
          case 7: return  &ractor_safe_call_cfunc_7;
          case 8: return  &ractor_safe_call_cfunc_8;
          case 9: return  &ractor_safe_call_cfunc_9;
          case 10: return &ractor_safe_call_cfunc_10;
          case 11: return &ractor_safe_call_cfunc_11;
          case 12: return &ractor_safe_call_cfunc_12;
          case 13: return &ractor_safe_call_cfunc_13;
          case 14: return &ractor_safe_call_cfunc_14;
          case 15: return &ractor_safe_call_cfunc_15;
          default:
            rb_bug("unsupported length: %d", argc);
        }
    }
}

static void
setup_method_cfunc_struct(rb_method_cfunc_t *cfunc, VALUE (*func)(ANYARGS), int argc)
{
    cfunc->func = func;
    cfunc->argc = argc;
    cfunc->invoker = call_cfunc_invoker_func(argc);
}

MJIT_FUNC_EXPORTED void
rb_method_definition_set(const rb_method_entry_t *me, rb_method_definition_t *def, void *opts)
{
    *(rb_method_definition_t **)&me->def = def;

    if (opts != NULL) {
	switch (def->type) {
	  case VM_METHOD_TYPE_ISEQ:
	    {
		rb_method_iseq_t *iseq_body = (rb_method_iseq_t *)opts;
                const rb_iseq_t *iseq = iseq_body->iseqptr;
		rb_cref_t *method_cref, *cref = iseq_body->cref;

		/* setup iseq first (before invoking GC) */
		RB_OBJ_WRITE(me, &def->body.iseq.iseqptr, iseq);

                if (iseq->body->mandatory_only_iseq) def->iseq_overload = 1;

		if (0) vm_cref_dump("rb_method_definition_create", cref);

		if (cref) {
		    method_cref = cref;
		}
		else {
		    method_cref = vm_cref_new_toplevel(GET_EC()); /* TODO: can we reuse? */
		}

		RB_OBJ_WRITE(me, &def->body.iseq.cref, method_cref);
		return;
	    }
	  case VM_METHOD_TYPE_CFUNC:
	    {
		rb_method_cfunc_t *cfunc = (rb_method_cfunc_t *)opts;
		setup_method_cfunc_struct(UNALIGNED_MEMBER_PTR(def, body.cfunc), cfunc->func, cfunc->argc);
		return;
	    }
	  case VM_METHOD_TYPE_ATTRSET:
	  case VM_METHOD_TYPE_IVAR:
	    {
		const rb_execution_context_t *ec = GET_EC();
		rb_control_frame_t *cfp;
		int line;

		def->body.attr.id = (ID)(VALUE)opts;

		cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

		if (cfp && (line = rb_vm_get_sourceline(cfp))) {
		    VALUE location = rb_ary_new3(2, rb_iseq_path(cfp->iseq), INT2FIX(line));
		    RB_OBJ_WRITE(me, &def->body.attr.location, rb_ary_freeze(location));
		}
		else {
		    VM_ASSERT(def->body.attr.location == 0);
		}
		return;
	    }
	  case VM_METHOD_TYPE_BMETHOD:
            RB_OBJ_WRITE(me, &def->body.bmethod.proc, (VALUE)opts);
            RB_OBJ_WRITE(me, &def->body.bmethod.defined_ractor, rb_ractor_self(GET_RACTOR()));
	    return;
	  case VM_METHOD_TYPE_NOTIMPLEMENTED:
	    setup_method_cfunc_struct(UNALIGNED_MEMBER_PTR(def, body.cfunc), rb_f_notimplement, -1);
	    return;
	  case VM_METHOD_TYPE_OPTIMIZED:
            def->body.optimized = *(rb_method_optimized_t *)opts;
	    return;
	  case VM_METHOD_TYPE_REFINED:
	    {
		const rb_method_refined_t *refined = (rb_method_refined_t *)opts;
		RB_OBJ_WRITE(me, &def->body.refined.orig_me, refined->orig_me);
		RB_OBJ_WRITE(me, &def->body.refined.owner, refined->owner);
		return;
	    }
	  case VM_METHOD_TYPE_ALIAS:
	    RB_OBJ_WRITE(me, &def->body.alias.original_me, (rb_method_entry_t *)opts);
	    return;
	  case VM_METHOD_TYPE_ZSUPER:
	  case VM_METHOD_TYPE_UNDEF:
	  case VM_METHOD_TYPE_MISSING:
	    return;
	}
    }
}

static void
method_definition_reset(const rb_method_entry_t *me)
{
    rb_method_definition_t *def = me->def;

    switch (def->type) {
      case VM_METHOD_TYPE_ISEQ:
	RB_OBJ_WRITTEN(me, Qundef, def->body.iseq.iseqptr);
	RB_OBJ_WRITTEN(me, Qundef, def->body.iseq.cref);
        RB_OBJ_WRITTEN(me, Qundef, def->body.iseq.mandatory_only_cme);
        break;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	RB_OBJ_WRITTEN(me, Qundef, def->body.attr.location);
	break;
      case VM_METHOD_TYPE_BMETHOD:
        RB_OBJ_WRITTEN(me, Qundef, def->body.bmethod.proc);
        RB_OBJ_WRITTEN(me, Qundef, def->body.bmethod.defined_ractor);
        /* give up to check all in a list */
        if (def->body.bmethod.hooks) rb_gc_writebarrier_remember((VALUE)me);
	break;
      case VM_METHOD_TYPE_REFINED:
	RB_OBJ_WRITTEN(me, Qundef, def->body.refined.orig_me);
	RB_OBJ_WRITTEN(me, Qundef, def->body.refined.owner);
	break;
      case VM_METHOD_TYPE_ALIAS:
	RB_OBJ_WRITTEN(me, Qundef, def->body.alias.original_me);
	break;
      case VM_METHOD_TYPE_CFUNC:
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_MISSING:
      case VM_METHOD_TYPE_OPTIMIZED:
      case VM_METHOD_TYPE_UNDEF:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
	break;
    }
}

MJIT_FUNC_EXPORTED rb_method_definition_t *
rb_method_definition_create(rb_method_type_t type, ID mid)
{
    rb_method_definition_t *def;
    def = ZALLOC(rb_method_definition_t);
    def->type = type;
    def->original_id = mid;
    static uintptr_t method_serial = 1;
    def->method_serial = method_serial++;
    return def;
}

static rb_method_definition_t *
method_definition_addref(rb_method_definition_t *def)
{
    def->alias_count++;
    if (METHOD_DEBUG) fprintf(stderr, "+%p-%s:%d\n", (void *)def, rb_id2name(def->original_id), def->alias_count);
    return def;
}

static rb_method_definition_t *
method_definition_addref_complement(rb_method_definition_t *def)
{
    def->complemented_count++;
    if (METHOD_DEBUG) fprintf(stderr, "+%p-%s:%d\n", (void *)def, rb_id2name(def->original_id), def->complemented_count);
    return def;
}

static rb_method_entry_t *
rb_method_entry_alloc(ID called_id, VALUE owner, VALUE defined_class, const rb_method_definition_t *def)
{
    rb_method_entry_t *me = (rb_method_entry_t *)rb_imemo_new(imemo_ment, (VALUE)def, (VALUE)called_id, owner, defined_class);
    return me;
}

static VALUE
filter_defined_class(VALUE klass)
{
    switch (BUILTIN_TYPE(klass)) {
      case T_CLASS:
	return klass;
      case T_MODULE:
	return 0;
      case T_ICLASS:
	break;
      default:
        break;
    }
    rb_bug("filter_defined_class: %s", rb_obj_info(klass));
}

rb_method_entry_t *
rb_method_entry_create(ID called_id, VALUE klass, rb_method_visibility_t visi, const rb_method_definition_t *def)
{
    rb_method_entry_t *me = rb_method_entry_alloc(called_id, klass, filter_defined_class(klass), def);
    METHOD_ENTRY_FLAGS_SET(me, visi, ruby_running ? FALSE : TRUE);
    if (def != NULL) method_definition_reset(me);
    return me;
}

const rb_method_entry_t *
rb_method_entry_clone(const rb_method_entry_t *src_me)
{
    rb_method_entry_t *me = rb_method_entry_alloc(src_me->called_id, src_me->owner, src_me->defined_class,
                                                  method_definition_addref(src_me->def));
    if (METHOD_ENTRY_COMPLEMENTED(src_me)) {
        method_definition_addref_complement(src_me->def);
    }

    METHOD_ENTRY_FLAGS_COPY(me, src_me);
    return me;
}

MJIT_FUNC_EXPORTED const rb_callable_method_entry_t *
rb_method_entry_complement_defined_class(const rb_method_entry_t *src_me, ID called_id, VALUE defined_class)
{
    rb_method_definition_t *def = src_me->def;
    rb_method_entry_t *me;
    struct {
	const struct rb_method_entry_struct *orig_me;
	VALUE owner;
    } refined = {0};

    if (!src_me->defined_class &&
	def->type == VM_METHOD_TYPE_REFINED &&
	def->body.refined.orig_me) {
	const rb_method_entry_t *orig_me =
	    rb_method_entry_clone(def->body.refined.orig_me);
	RB_OBJ_WRITE((VALUE)orig_me, &orig_me->defined_class, defined_class);
	refined.orig_me = orig_me;
	refined.owner = orig_me->owner;
	def = NULL;
    }
    else {
	def = method_definition_addref_complement(def);
    }
    me = rb_method_entry_alloc(called_id, src_me->owner, defined_class, def);
    METHOD_ENTRY_FLAGS_COPY(me, src_me);
    METHOD_ENTRY_COMPLEMENTED_SET(me);
    if (!def) {
	def = rb_method_definition_create(VM_METHOD_TYPE_REFINED, called_id);
	rb_method_definition_set(me, def, &refined);
    }

    VM_ASSERT(RB_TYPE_P(me->owner, T_MODULE));

    return (rb_callable_method_entry_t *)me;
}

void
rb_method_entry_copy(rb_method_entry_t *dst, const rb_method_entry_t *src)
{
    *(rb_method_definition_t **)&dst->def = method_definition_addref(src->def);
    method_definition_reset(dst);
    dst->called_id = src->called_id;
    RB_OBJ_WRITE((VALUE)dst, &dst->owner, src->owner);
    RB_OBJ_WRITE((VALUE)dst, &dst->defined_class, src->defined_class);
    METHOD_ENTRY_FLAGS_COPY(dst, src);
}

static void
make_method_entry_refined(VALUE owner, rb_method_entry_t *me)
{
    if (me->def->type == VM_METHOD_TYPE_REFINED) {
	return;
    }
    else {
	struct {
	    struct rb_method_entry_struct *orig_me;
	    VALUE owner;
	} refined;
	rb_method_definition_t *def;

	rb_vm_check_redefinition_opt_method(me, me->owner);

	refined.orig_me =
	    rb_method_entry_alloc(me->called_id, me->owner,
				  me->defined_class ?
				  me->defined_class : owner,
				  method_definition_addref(me->def));
	METHOD_ENTRY_FLAGS_COPY(refined.orig_me, me);
	refined.owner = owner;

	def = rb_method_definition_create(VM_METHOD_TYPE_REFINED, me->called_id);
	rb_method_definition_set(me, def, (void *)&refined);
	METHOD_ENTRY_VISI_SET(me, METHOD_VISI_PUBLIC);
    }
}

static inline rb_method_entry_t *
lookup_method_table(VALUE klass, ID id)
{
    st_data_t body;
    struct rb_id_table *m_tbl = RCLASS_M_TBL(klass);

    if (rb_id_table_lookup(m_tbl, id, &body)) {
	return (rb_method_entry_t *) body;
    }
    else {
	return 0;
    }
}

void
rb_add_refined_method_entry(VALUE refined_class, ID mid)
{
    rb_method_entry_t *me = lookup_method_table(refined_class, mid);

    if (me) {
	make_method_entry_refined(refined_class, me);
	rb_clear_method_cache(refined_class, mid);
    }
    else {
	rb_add_method(refined_class, mid, VM_METHOD_TYPE_REFINED, 0, METHOD_VISI_PUBLIC);
    }
}

static void
check_override_opt_method_i(VALUE klass, VALUE arg)
{
    ID mid = (ID)arg;
    const rb_method_entry_t *me, *newme;

    if (vm_redefinition_check_flag(klass)) {
	me = lookup_method_table(RCLASS_ORIGIN(klass), mid);
	if (me) {
	    newme = rb_method_entry(klass, mid);
	    if (newme != me) rb_vm_check_redefinition_opt_method(me, me->owner);
	}
    }
    rb_class_foreach_subclass(klass, check_override_opt_method_i, (VALUE)mid);
}

static void
check_override_opt_method(VALUE klass, VALUE mid)
{
    if (rb_vm_check_optimizable_mid(mid)) {
        check_override_opt_method_i(klass, mid);
    }
}

/*
 * klass->method_table[mid] = method_entry(defined_class, visi, def)
 *
 * If def is given (!= NULL), then just use it and ignore original_id and otps.
 * If not given, then make a new def with original_id and opts.
 */
static rb_method_entry_t *
rb_method_entry_make(VALUE klass, ID mid, VALUE defined_class, rb_method_visibility_t visi,
		     rb_method_type_t type, rb_method_definition_t *def, ID original_id, void *opts)
{
    rb_method_entry_t *me;
    struct rb_id_table *mtbl;
    st_data_t data;
    int make_refined = 0;
    VALUE orig_klass;

    if (NIL_P(klass)) {
	klass = rb_cObject;
    }
    orig_klass = klass;

    if (!FL_TEST(klass, FL_SINGLETON) &&
	type != VM_METHOD_TYPE_NOTIMPLEMENTED &&
	type != VM_METHOD_TYPE_ZSUPER) {
	switch (mid) {
	  case idInitialize:
	  case idInitialize_copy:
	  case idInitialize_clone:
	  case idInitialize_dup:
	  case idRespond_to_missing:
	    visi = METHOD_VISI_PRIVATE;
	}
    }

    if (type != VM_METHOD_TYPE_REFINED) {
       rb_class_modify_check(klass);
    }

    if (FL_TEST(klass, RMODULE_IS_REFINEMENT)) {
	VALUE refined_class = rb_refinement_module_get_refined_class(klass);
	rb_add_refined_method_entry(refined_class, mid);
    }
    if (type == VM_METHOD_TYPE_REFINED) {
	rb_method_entry_t *old_me = lookup_method_table(RCLASS_ORIGIN(klass), mid);
	if (old_me) rb_vm_check_redefinition_opt_method(old_me, klass);
    }
    else {
	klass = RCLASS_ORIGIN(klass);
        if (klass != orig_klass) {
            rb_clear_method_cache(orig_klass, mid);
        }
    }
    mtbl = RCLASS_M_TBL(klass);

    /* check re-definition */
    if (rb_id_table_lookup(mtbl, mid, &data)) {
	rb_method_entry_t *old_me = (rb_method_entry_t *)data;
	rb_method_definition_t *old_def = old_me->def;

	if (rb_method_definition_eq(old_def, def)) return old_me;
	rb_vm_check_redefinition_opt_method(old_me, klass);

	if (old_def->type == VM_METHOD_TYPE_REFINED) make_refined = 1;

	if (RTEST(ruby_verbose) &&
	    type != VM_METHOD_TYPE_UNDEF &&
	    (old_def->alias_count == 0) &&
	    !make_refined &&
	    old_def->type != VM_METHOD_TYPE_UNDEF &&
	    old_def->type != VM_METHOD_TYPE_ZSUPER &&
	    old_def->type != VM_METHOD_TYPE_ALIAS) {
	    const rb_iseq_t *iseq = 0;

	    rb_warning("method redefined; discarding old %"PRIsVALUE, rb_id2str(mid));
	    switch (old_def->type) {
	      case VM_METHOD_TYPE_ISEQ:
		iseq = def_iseq_ptr(old_def);
		break;
	      case VM_METHOD_TYPE_BMETHOD:
                iseq = rb_proc_get_iseq(old_def->body.bmethod.proc, 0);
		break;
	      default:
		break;
	    }
	    if (iseq) {
		rb_compile_warning(RSTRING_PTR(rb_iseq_path(iseq)),
				   FIX2INT(iseq->body->location.first_lineno),
				   "previous definition of %"PRIsVALUE" was here",
				   rb_id2str(old_def->original_id));
	    }
	}
    }

    /* create method entry */
    me = rb_method_entry_create(mid, defined_class, visi, NULL);
    if (def == NULL) def = rb_method_definition_create(type, original_id);
    rb_method_definition_set(me, def, opts);

    rb_clear_method_cache(klass, mid);

    /* check mid */
    if (klass == rb_cObject) {
        switch (mid) {
          case idInitialize:
          case idRespond_to_missing:
          case idMethodMissing:
          case idRespond_to:
            rb_warn("redefining Object#%s may cause infinite loop", rb_id2name(mid));
        }
    }
    /* check mid */
    if (mid == object_id || mid == id__send__) {
	if (type == VM_METHOD_TYPE_ISEQ && search_method(klass, mid, 0)) {
	    rb_warn("redefining `%s' may cause serious problems", rb_id2name(mid));
	}
    }

    if (make_refined) {
	make_method_entry_refined(klass, me);
    }

    rb_method_table_insert(klass, mtbl, mid, me);

    VM_ASSERT(me->def != NULL);

    /* check optimized method override by a prepended module */
    if (RB_TYPE_P(orig_klass, T_MODULE)) {
	check_override_opt_method(klass, (VALUE)mid);
    }

    return me;
}

static const rb_callable_method_entry_t *
overloaded_cme(const rb_callable_method_entry_t *cme)
{
    VM_ASSERT(cme->def->iseq_overload);
    VM_ASSERT(cme->def->type == VM_METHOD_TYPE_ISEQ);
    VM_ASSERT(cme->def->body.iseq.iseqptr != NULL);

    const rb_callable_method_entry_t *monly_cme = cme->def->body.iseq.mandatory_only_cme;

    if (monly_cme && !METHOD_ENTRY_INVALIDATED(monly_cme)) {
        // ok
    }
    else {
        rb_method_definition_t *def = rb_method_definition_create(VM_METHOD_TYPE_ISEQ, cme->def->original_id);
        def->body.iseq.cref = cme->def->body.iseq.cref;
        def->body.iseq.iseqptr = cme->def->body.iseq.iseqptr->body->mandatory_only_iseq;

        rb_method_entry_t *me = rb_method_entry_alloc(cme->called_id,
                                                      cme->owner,
                                                      cme->defined_class,
                                                      def);
        METHOD_ENTRY_VISI_SET(me, METHOD_ENTRY_VISI(cme));
        RB_OBJ_WRITE(cme, &cme->def->body.iseq.mandatory_only_cme, me);
        monly_cme = (rb_callable_method_entry_t *)me;
    }

    return monly_cme;
}

#define CALL_METHOD_HOOK(klass, hook, mid) do {		\
	const VALUE arg = ID2SYM(mid);			\
	VALUE recv_class = (klass);			\
	ID hook_id = (hook);				\
	if (FL_TEST((klass), FL_SINGLETON)) {		\
	    recv_class = rb_ivar_get((klass), attached);	\
	    hook_id = singleton_##hook;			\
	}						\
	rb_funcallv(recv_class, hook_id, 1, &arg);	\
    } while (0)

static void
method_added(VALUE klass, ID mid)
{
    if (ruby_running) {
	CALL_METHOD_HOOK(klass, added, mid);
    }
}

void
rb_add_method(VALUE klass, ID mid, rb_method_type_t type, void *opts, rb_method_visibility_t visi)
{
    rb_method_entry_make(klass, mid, klass, visi, type, NULL, mid, opts);

    if (type != VM_METHOD_TYPE_UNDEF && type != VM_METHOD_TYPE_REFINED) {
	method_added(klass, mid);
    }
}

MJIT_FUNC_EXPORTED void
rb_add_method_iseq(VALUE klass, ID mid, const rb_iseq_t *iseq, rb_cref_t *cref, rb_method_visibility_t visi)
{
    struct { /* should be same fields with rb_method_iseq_struct */
        const rb_iseq_t *iseqptr;
        rb_cref_t *cref;
    } iseq_body;

    iseq_body.iseqptr = iseq;
    iseq_body.cref = cref;

    rb_add_method(klass, mid, VM_METHOD_TYPE_ISEQ, &iseq_body, visi);
}

static rb_method_entry_t *
method_entry_set(VALUE klass, ID mid, const rb_method_entry_t *me,
		 rb_method_visibility_t visi, VALUE defined_class)
{
    rb_method_entry_t *newme = rb_method_entry_make(klass, mid, defined_class, visi,
						    me->def->type, method_definition_addref(me->def), 0, NULL);
    method_added(klass, mid);
    return newme;
}

rb_method_entry_t *
rb_method_entry_set(VALUE klass, ID mid, const rb_method_entry_t *me, rb_method_visibility_t visi)
{
    return method_entry_set(klass, mid, me, visi, klass);
}

#define UNDEF_ALLOC_FUNC ((rb_alloc_func_t)-1)

void
rb_define_alloc_func(VALUE klass, VALUE (*func)(VALUE))
{
    Check_Type(klass, T_CLASS);
    RCLASS_ALLOCATOR(klass) = func;
}

void
rb_undef_alloc_func(VALUE klass)
{
    rb_define_alloc_func(klass, UNDEF_ALLOC_FUNC);
}

rb_alloc_func_t
rb_get_alloc_func(VALUE klass)
{
    Check_Type(klass, T_CLASS);

    for (; klass; klass = RCLASS_SUPER(klass)) {
	rb_alloc_func_t allocator = RCLASS_ALLOCATOR(klass);
	if (allocator == UNDEF_ALLOC_FUNC) break;
	if (allocator) return allocator;
    }
    return 0;
}

const rb_method_entry_t *
rb_method_entry_at(VALUE klass, ID id)
{
    return lookup_method_table(klass, id);
}

static inline rb_method_entry_t*
search_method0(VALUE klass, ID id, VALUE *defined_class_ptr, bool skip_refined)
{
    rb_method_entry_t *me = NULL;

    RB_DEBUG_COUNTER_INC(mc_search);

    for (; klass; klass = RCLASS_SUPER(klass)) {
	RB_DEBUG_COUNTER_INC(mc_search_super);
        if ((me = lookup_method_table(klass, id)) != 0) {
            if (!skip_refined || me->def->type != VM_METHOD_TYPE_REFINED ||
                    me->def->body.refined.orig_me) {
                break;
            }
        }
    }

    if (defined_class_ptr) *defined_class_ptr = klass;

    if (me == NULL) RB_DEBUG_COUNTER_INC(mc_search_notfound);

    VM_ASSERT(me == NULL || !METHOD_ENTRY_INVALIDATED(me));
    return me;
}

static inline rb_method_entry_t*
search_method(VALUE klass, ID id, VALUE *defined_class_ptr)
{
    return search_method0(klass, id, defined_class_ptr, false);
}

static rb_method_entry_t *
search_method_protect(VALUE klass, ID id, VALUE *defined_class_ptr)
{
    rb_method_entry_t *me = search_method(klass, id, defined_class_ptr);

    if (!UNDEFINED_METHOD_ENTRY_P(me)) {
        return me;
    }
    else {
        return NULL;
    }
}

MJIT_FUNC_EXPORTED const rb_method_entry_t *
rb_method_entry(VALUE klass, ID id)
{
    return search_method_protect(klass, id, NULL);
}

static inline const rb_callable_method_entry_t *
prepare_callable_method_entry(VALUE defined_class, ID id, const rb_method_entry_t * const me, int create)
{
    struct rb_id_table *mtbl;
    const rb_callable_method_entry_t *cme;
    VALUE cme_data;

    if (me) {
        if (me->defined_class == 0) {
            RB_DEBUG_COUNTER_INC(mc_cme_complement);
            VM_ASSERT(RB_TYPE_P(defined_class, T_ICLASS) || RB_TYPE_P(defined_class, T_MODULE));
            VM_ASSERT(me->defined_class == 0);

            mtbl = RCLASS_CALLABLE_M_TBL(defined_class);

            if (mtbl && rb_id_table_lookup(mtbl, id, &cme_data)) {
                cme = (rb_callable_method_entry_t *)cme_data;
                RB_DEBUG_COUNTER_INC(mc_cme_complement_hit);
                VM_ASSERT(callable_method_entry_p(cme));
                VM_ASSERT(!METHOD_ENTRY_INVALIDATED(cme));
            }
            else if (create) {
                if (!mtbl) {
                    mtbl = RCLASS_EXT(defined_class)->callable_m_tbl = rb_id_table_create(0);
                }
                cme = rb_method_entry_complement_defined_class(me, me->called_id, defined_class);
                rb_id_table_insert(mtbl, id, (VALUE)cme);
                RB_OBJ_WRITTEN(defined_class, Qundef, (VALUE)cme);
                VM_ASSERT(callable_method_entry_p(cme));
            }
            else {
                return NULL;
            }
        }
        else {
            cme = (const rb_callable_method_entry_t *)me;
            VM_ASSERT(callable_method_entry_p(cme));
            VM_ASSERT(!METHOD_ENTRY_INVALIDATED(cme));
        }
        return cme;
    }
    else {
        return NULL;
    }
}

static const rb_callable_method_entry_t *
complemented_callable_method_entry(VALUE klass, ID id)
{
    VALUE defined_class;
    rb_method_entry_t *me = search_method(klass, id, &defined_class);
    return prepare_callable_method_entry(defined_class, id, me, FALSE);
}

static const rb_callable_method_entry_t *
cached_callable_method_entry(VALUE klass, ID mid)
{
    ASSERT_vm_locking();

    struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);
    VALUE ccs_data;

    if (cc_tbl && rb_id_table_lookup(cc_tbl, mid, &ccs_data)) {
        struct rb_class_cc_entries *ccs = (struct rb_class_cc_entries *)ccs_data;
        VM_ASSERT(vm_ccs_p(ccs));

        if (LIKELY(!METHOD_ENTRY_INVALIDATED(ccs->cme))) {
            VM_ASSERT(ccs->cme->called_id == mid);
            RB_DEBUG_COUNTER_INC(ccs_found);
            return ccs->cme;
        }
        else {
            rb_vm_ccs_free(ccs);
            rb_id_table_delete(cc_tbl, mid);
        }
    }

    RB_DEBUG_COUNTER_INC(ccs_not_found);
    return NULL;
}

static void
cache_callable_method_entry(VALUE klass, ID mid, const rb_callable_method_entry_t *cme)
{
    ASSERT_vm_locking();
    VM_ASSERT(cme != NULL);

    struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);
    struct rb_class_cc_entries *ccs;
    VALUE ccs_data;

    if (!cc_tbl) {
        cc_tbl = RCLASS_CC_TBL(klass) = rb_id_table_create(2);
    }

    if (rb_id_table_lookup(cc_tbl, mid, &ccs_data)) {
        ccs = (struct rb_class_cc_entries *)ccs_data;
        VM_ASSERT(ccs->cme == cme);
    }
    else {
        ccs = vm_ccs_create(klass, cme);
        rb_id_table_insert(cc_tbl, mid, (VALUE)ccs);
    }
}

static const rb_callable_method_entry_t *
negative_cme(ID mid)
{
    rb_vm_t *vm = GET_VM();
    const rb_callable_method_entry_t *cme;
    VALUE cme_data;

    if (rb_id_table_lookup(vm->negative_cme_table, mid, &cme_data)) {
        cme = (rb_callable_method_entry_t *)cme_data;
    }
    else {
        cme = (rb_callable_method_entry_t *)rb_method_entry_alloc(mid, Qnil, Qnil, NULL);
        rb_id_table_insert(vm->negative_cme_table, mid, (VALUE)cme);
    }

    VM_ASSERT(cme != NULL);
    return cme;
}

static const rb_callable_method_entry_t *
callable_method_entry(VALUE klass, ID mid, VALUE *defined_class_ptr)
{
    const rb_callable_method_entry_t *cme;

    VM_ASSERT(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_ICLASS));
    RB_VM_LOCK_ENTER();
    {
        cme = cached_callable_method_entry(klass, mid);

        if (cme) {
            if (defined_class_ptr != NULL) *defined_class_ptr = cme->defined_class;
        }
        else {
            VALUE defined_class;
            rb_method_entry_t *me = search_method(klass, mid, &defined_class);
            if (defined_class_ptr) *defined_class_ptr = defined_class;

            if (me != NULL) {
                cme = prepare_callable_method_entry(defined_class, mid, me, TRUE);
            }
            else {
                cme = negative_cme(mid);
            }

            cache_callable_method_entry(klass, mid, cme);
        }
    }
    RB_VM_LOCK_LEAVE();

    return !UNDEFINED_METHOD_ENTRY_P(cme) ? cme : NULL;
}

MJIT_FUNC_EXPORTED const rb_callable_method_entry_t *
rb_callable_method_entry(VALUE klass, ID mid)
{
    return callable_method_entry(klass, mid, NULL);
}

static const rb_method_entry_t *resolve_refined_method(VALUE refinements, const rb_method_entry_t *me, VALUE *defined_class_ptr);

static const rb_method_entry_t *
method_entry_resolve_refinement(VALUE klass, ID id, int with_refinement, VALUE *defined_class_ptr)
{
    const rb_method_entry_t *me = search_method_protect(klass, id, defined_class_ptr);

    if (me) {
	if (me->def->type == VM_METHOD_TYPE_REFINED) {
	    if (with_refinement) {
		const rb_cref_t *cref = rb_vm_cref();
		VALUE refinements = cref ? CREF_REFINEMENTS(cref) : Qnil;
		me = resolve_refined_method(refinements, me, defined_class_ptr);
	    }
	    else {
		me = resolve_refined_method(Qnil, me, defined_class_ptr);
	    }

	    if (UNDEFINED_METHOD_ENTRY_P(me)) me = NULL;
	}
    }

    return me;
}

MJIT_FUNC_EXPORTED const rb_method_entry_t *
rb_method_entry_with_refinements(VALUE klass, ID id, VALUE *defined_class_ptr)
{
    return method_entry_resolve_refinement(klass, id, TRUE, defined_class_ptr);
}

static const rb_callable_method_entry_t *
callable_method_entry_refeinements0(VALUE klass, ID id, VALUE *defined_class_ptr, bool with_refinements,
                                    const rb_callable_method_entry_t *cme)
{
    if (cme == NULL || LIKELY(cme->def->type != VM_METHOD_TYPE_REFINED)) {
        return cme;
    }
    else {
        VALUE defined_class, *dcp = defined_class_ptr ? defined_class_ptr : &defined_class;
        const rb_method_entry_t *me = method_entry_resolve_refinement(klass, id, with_refinements, dcp);
        return prepare_callable_method_entry(*dcp, id, me, TRUE);
    }
}

static const rb_callable_method_entry_t *
callable_method_entry_refinements(VALUE klass, ID id, VALUE *defined_class_ptr, bool with_refinements)
{
    const rb_callable_method_entry_t *cme = callable_method_entry(klass, id, defined_class_ptr);
    return callable_method_entry_refeinements0(klass, id, defined_class_ptr, with_refinements, cme);
}

MJIT_FUNC_EXPORTED const rb_callable_method_entry_t *
rb_callable_method_entry_with_refinements(VALUE klass, ID id, VALUE *defined_class_ptr)
{
    return callable_method_entry_refinements(klass, id, defined_class_ptr, true);
}

static const rb_callable_method_entry_t *
callable_method_entry_without_refinements(VALUE klass, ID id, VALUE *defined_class_ptr)
{
    return callable_method_entry_refinements(klass, id, defined_class_ptr, false);
}

const rb_method_entry_t *
rb_method_entry_without_refinements(VALUE klass, ID id, VALUE *defined_class_ptr)
{
    return method_entry_resolve_refinement(klass, id, FALSE, defined_class_ptr);
}

MJIT_FUNC_EXPORTED const rb_callable_method_entry_t *
rb_callable_method_entry_without_refinements(VALUE klass, ID id, VALUE *defined_class_ptr)
{
    VALUE defined_class, *dcp = defined_class_ptr ? defined_class_ptr : &defined_class;
    const rb_method_entry_t *me = method_entry_resolve_refinement(klass, id, FALSE, dcp);
    return prepare_callable_method_entry(*dcp, id, me, TRUE);
}

static const rb_method_entry_t *
resolve_refined_method(VALUE refinements, const rb_method_entry_t *me, VALUE *defined_class_ptr)
{
    while (me && me->def->type == VM_METHOD_TYPE_REFINED) {
	VALUE refinement;
        const rb_method_entry_t *tmp_me;
        VALUE super;

	refinement = find_refinement(refinements, me->owner);
        if (!NIL_P(refinement)) {
	    tmp_me = search_method_protect(refinement, me->called_id, defined_class_ptr);

	    if (tmp_me && tmp_me->def->type != VM_METHOD_TYPE_REFINED) {
		return tmp_me;
	    }
	}

        tmp_me = me->def->body.refined.orig_me;
        if (tmp_me) {
            if (defined_class_ptr) *defined_class_ptr = tmp_me->defined_class;
            return tmp_me;
        }

        super = RCLASS_SUPER(me->owner);
        if (!super) {
            return 0;
        }

        me = search_method_protect(super, me->called_id, defined_class_ptr);
    }
    return me;
}

const rb_method_entry_t *
rb_resolve_refined_method(VALUE refinements, const rb_method_entry_t *me)
{
    return resolve_refined_method(refinements, me, NULL);
}

MJIT_FUNC_EXPORTED
const rb_callable_method_entry_t *
rb_resolve_refined_method_callable(VALUE refinements, const rb_callable_method_entry_t *me)
{
    VALUE defined_class = me->defined_class;
    const rb_method_entry_t *resolved_me = resolve_refined_method(refinements, (const rb_method_entry_t *)me, &defined_class);

    if (resolved_me && resolved_me->defined_class == 0) {
	return rb_method_entry_complement_defined_class(resolved_me, me->called_id, defined_class);
    }
    else {
	return (const rb_callable_method_entry_t *)resolved_me;
    }
}

static void
remove_method(VALUE klass, ID mid)
{
    VALUE data;
    rb_method_entry_t *me = 0;
    VALUE self = klass;

    klass = RCLASS_ORIGIN(klass);
    rb_class_modify_check(klass);
    if (mid == object_id || mid == id__send__ || mid == idInitialize) {
	rb_warn("removing `%s' may cause serious problems", rb_id2name(mid));
    }

    if (!rb_id_table_lookup(RCLASS_M_TBL(klass), mid, &data) ||
	!(me = (rb_method_entry_t *)data) ||
	(!me->def || me->def->type == VM_METHOD_TYPE_UNDEF) ||
        UNDEFINED_REFINED_METHOD_P(me->def)) {
	rb_name_err_raise("method `%1$s' not defined in %2$s",
			  klass, ID2SYM(mid));
    }

    if (klass != self) {
        rb_clear_method_cache(self, mid);
    }
    rb_clear_method_cache(klass, mid);
    rb_id_table_delete(RCLASS_M_TBL(klass), mid);

    rb_vm_check_redefinition_opt_method(me, klass);

    if (me->def->type == VM_METHOD_TYPE_REFINED) {
	rb_add_refined_method_entry(klass, mid);
    }

    CALL_METHOD_HOOK(self, removed, mid);
}

void
rb_remove_method_id(VALUE klass, ID mid)
{
    remove_method(klass, mid);
}

void
rb_remove_method(VALUE klass, const char *name)
{
    remove_method(klass, rb_intern(name));
}

/*
 *  call-seq:
 *     remove_method(symbol)   -> self
 *     remove_method(string)   -> self
 *
 *  Removes the method identified by _symbol_ from the current
 *  class. For an example, see Module#undef_method.
 *  String arguments are converted to symbols.
 */

static VALUE
rb_mod_remove_method(int argc, VALUE *argv, VALUE mod)
{
    int i;

    for (i = 0; i < argc; i++) {
	VALUE v = argv[i];
	ID id = rb_check_id(&v);
	if (!id) {
	    rb_name_err_raise("method `%1$s' not defined in %2$s",
			      mod, v);
	}
	remove_method(mod, id);
    }
    return mod;
}

static void
rb_export_method(VALUE klass, ID name, rb_method_visibility_t visi)
{
    rb_method_entry_t *me;
    VALUE defined_class;
    VALUE origin_class = RCLASS_ORIGIN(klass);

    me = search_method0(origin_class, name, &defined_class, true);

    if (!me && RB_TYPE_P(klass, T_MODULE)) {
	me = search_method(rb_cObject, name, &defined_class);
    }

    if (UNDEFINED_METHOD_ENTRY_P(me) ||
	UNDEFINED_REFINED_METHOD_P(me->def)) {
	rb_print_undef(klass, name, METHOD_VISI_UNDEF);
    }

    if (METHOD_ENTRY_VISI(me) != visi) {
	rb_vm_check_redefinition_opt_method(me, klass);

	if (klass == defined_class || origin_class == defined_class) {
            if (me->def->type == VM_METHOD_TYPE_REFINED) {
                // Refinement method entries should always be public because the refinement
                // search is always performed.
                if (me->def->body.refined.orig_me) {
                    METHOD_ENTRY_VISI_SET((rb_method_entry_t *)me->def->body.refined.orig_me, visi);
                }
            }
            else {
                METHOD_ENTRY_VISI_SET(me, visi);
            }
            rb_clear_method_cache(klass, name);
	}
	else {
	    rb_add_method(klass, name, VM_METHOD_TYPE_ZSUPER, 0, visi);
	}
    }
}

#define BOUND_PRIVATE  0x01
#define BOUND_RESPONDS 0x02

static int
method_boundp(VALUE klass, ID id, int ex)
{
    const rb_callable_method_entry_t *cme;

    VM_ASSERT(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_ICLASS));

    if (ex & BOUND_RESPONDS) {
        cme = rb_callable_method_entry_with_refinements(klass, id, NULL);
    }
    else {
        cme = callable_method_entry_without_refinements(klass, id, NULL);
    }

    if (cme != NULL) {
        if (ex & ~BOUND_RESPONDS) {
            switch (METHOD_ENTRY_VISI(cme)) {
              case METHOD_VISI_PRIVATE:
                return 0;
              case METHOD_VISI_PROTECTED:
                if (ex & BOUND_RESPONDS) return 0;
              default:
                break;
            }
	}

	if (cme->def->type == VM_METHOD_TYPE_NOTIMPLEMENTED) {
	    if (ex & BOUND_RESPONDS) return 2;
	    return 0;
	}
	return 1;
    }
    return 0;
}

// deprecated
int
rb_method_boundp(VALUE klass, ID id, int ex)
{
    return method_boundp(klass, id, ex);
}

static void
vm_cref_set_visibility(rb_method_visibility_t method_visi, int module_func)
{
    rb_scope_visibility_t *scope_visi = (rb_scope_visibility_t *)&rb_vm_cref()->scope_visi;
    scope_visi->method_visi = method_visi;
    scope_visi->module_func = module_func;
}

void
rb_scope_visibility_set(rb_method_visibility_t visi)
{
    vm_cref_set_visibility(visi, FALSE);
}

static void
scope_visibility_check(void)
{
    /* Check for public/protected/private/module_function called inside a method */
    rb_control_frame_t *cfp = GET_EC()->cfp+1;
    if (cfp && cfp->iseq && cfp->iseq->body->type == ISEQ_TYPE_METHOD) {
        rb_warn("calling %s without arguments inside a method may not have the intended effect",
            rb_id2name(rb_frame_this_func()));
    }
}

static void
rb_scope_module_func_set(void)
{
    scope_visibility_check();
    vm_cref_set_visibility(METHOD_VISI_PRIVATE, TRUE);
}

const rb_cref_t *rb_vm_cref_in_context(VALUE self, VALUE cbase);
void
rb_attr(VALUE klass, ID id, int read, int write, int ex)
{
    ID attriv;
    rb_method_visibility_t visi;
    const rb_execution_context_t *ec = GET_EC();
    const rb_cref_t *cref = rb_vm_cref_in_context(klass, klass);

    if (!ex || !cref) {
	visi = METHOD_VISI_PUBLIC;
    }
    else {
        switch (vm_scope_visibility_get(ec)) {
	  case METHOD_VISI_PRIVATE:
            if (vm_scope_module_func_check(ec)) {
		rb_warning("attribute accessor as module_function");
	    }
	    visi = METHOD_VISI_PRIVATE;
	    break;
	  case METHOD_VISI_PROTECTED:
	    visi = METHOD_VISI_PROTECTED;
	    break;
	  default:
	    visi = METHOD_VISI_PUBLIC;
	    break;
	}
    }

    attriv = rb_intern_str(rb_sprintf("@%"PRIsVALUE, rb_id2str(id)));
    if (read) {
	rb_add_method(klass, id, VM_METHOD_TYPE_IVAR, (void *)attriv, visi);
    }
    if (write) {
	rb_add_method(klass, rb_id_attrset(id), VM_METHOD_TYPE_ATTRSET, (void *)attriv, visi);
    }
}

void
rb_undef(VALUE klass, ID id)
{
    const rb_method_entry_t *me;

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class to undef method");
    }
    rb_class_modify_check(klass);
    if (id == object_id || id == id__send__ || id == idInitialize) {
	rb_warn("undefining `%s' may cause serious problems", rb_id2name(id));
    }

    me = search_method(klass, id, 0);
    if (me && me->def->type == VM_METHOD_TYPE_REFINED) {
	me = rb_resolve_refined_method(Qnil, me);
    }

    if (UNDEFINED_METHOD_ENTRY_P(me) ||
	UNDEFINED_REFINED_METHOD_P(me->def)) {
	rb_method_name_error(klass, rb_id2str(id));
    }

    rb_add_method(klass, id, VM_METHOD_TYPE_UNDEF, 0, METHOD_VISI_PUBLIC);

    CALL_METHOD_HOOK(klass, undefined, id);
}

/*
 *  call-seq:
 *     undef_method(symbol)    -> self
 *     undef_method(string)    -> self
 *
 *  Prevents the current class from responding to calls to the named
 *  method. Contrast this with <code>remove_method</code>, which deletes
 *  the method from the particular class; Ruby will still search
 *  superclasses and mixed-in modules for a possible receiver.
 *  String arguments are converted to symbols.
 *
 *     class Parent
 *       def hello
 *         puts "In parent"
 *       end
 *     end
 *     class Child < Parent
 *       def hello
 *         puts "In child"
 *       end
 *     end
 *
 *
 *     c = Child.new
 *     c.hello
 *
 *
 *     class Child
 *       remove_method :hello  # remove from child, still in parent
 *     end
 *     c.hello
 *
 *
 *     class Child
 *       undef_method :hello   # prevent any calls to 'hello'
 *     end
 *     c.hello
 *
 *  <em>produces:</em>
 *
 *     In child
 *     In parent
 *     prog.rb:23: undefined method `hello' for #<Child:0x401b3bb4> (NoMethodError)
 */

static VALUE
rb_mod_undef_method(int argc, VALUE *argv, VALUE mod)
{
    int i;
    for (i = 0; i < argc; i++) {
	VALUE v = argv[i];
	ID id = rb_check_id(&v);
	if (!id) {
	    rb_method_name_error(mod, v);
	}
	rb_undef(mod, id);
    }
    return mod;
}

static rb_method_visibility_t
check_definition_visibility(VALUE mod, int argc, VALUE *argv)
{
    const rb_method_entry_t *me;
    VALUE mid, include_super, lookup_mod = mod;
    int inc_super;
    ID id;

    rb_scan_args(argc, argv, "11", &mid, &include_super);
    id = rb_check_id(&mid);
    if (!id) return METHOD_VISI_UNDEF;

    if (argc == 1) {
	inc_super = 1;
    }
    else {
	inc_super = RTEST(include_super);
	if (!inc_super) {
	    lookup_mod = RCLASS_ORIGIN(mod);
	}
    }

    me = rb_method_entry_without_refinements(lookup_mod, id, NULL);
    if (me) {
	if (me->def->type == VM_METHOD_TYPE_NOTIMPLEMENTED) return METHOD_VISI_UNDEF;
	if (!inc_super && me->owner != mod) return METHOD_VISI_UNDEF;
	return METHOD_ENTRY_VISI(me);
    }
    return METHOD_VISI_UNDEF;
}

/*
 *  call-seq:
 *     mod.method_defined?(symbol, inherit=true)    -> true or false
 *     mod.method_defined?(string, inherit=true)    -> true or false
 *
 *  Returns +true+ if the named method is defined by
 *  _mod_.  If _inherit_ is set, the lookup will also search _mod_'s
 *  ancestors. Public and protected methods are matched.
 *  String arguments are converted to symbols.
 *
 *     module A
 *       def method1()  end
 *       def protected_method1()  end
 *       protected :protected_method1
 *     end
 *     class B
 *       def method2()  end
 *       def private_method2()  end
 *       private :private_method2
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1              #=> true
 *     C.method_defined? "method1"             #=> true
 *     C.method_defined? "method2"             #=> true
 *     C.method_defined? "method2", true       #=> true
 *     C.method_defined? "method2", false      #=> false
 *     C.method_defined? "method3"             #=> true
 *     C.method_defined? "protected_method1"   #=> true
 *     C.method_defined? "method4"             #=> false
 *     C.method_defined? "private_method2"     #=> false
 */

static VALUE
rb_mod_method_defined(int argc, VALUE *argv, VALUE mod)
{
    rb_method_visibility_t visi = check_definition_visibility(mod, argc, argv);
    return RBOOL(visi == METHOD_VISI_PUBLIC || visi == METHOD_VISI_PROTECTED);
}

static VALUE
check_definition(VALUE mod, int argc, VALUE *argv, rb_method_visibility_t visi)
{
    return RBOOL(check_definition_visibility(mod, argc, argv) == visi);
}

/*
 *  call-seq:
 *     mod.public_method_defined?(symbol, inherit=true)   -> true or false
 *     mod.public_method_defined?(string, inherit=true)   -> true or false
 *
 *  Returns +true+ if the named public method is defined by
 *  _mod_.  If _inherit_ is set, the lookup will also search _mod_'s
 *  ancestors.
 *  String arguments are converted to symbols.
 *
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       protected
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1                 #=> true
 *     C.public_method_defined? "method1"         #=> true
 *     C.public_method_defined? "method1", true   #=> true
 *     C.public_method_defined? "method1", false  #=> true
 *     C.public_method_defined? "method2"         #=> false
 *     C.method_defined? "method2"                #=> true
 */

static VALUE
rb_mod_public_method_defined(int argc, VALUE *argv, VALUE mod)
{
    return check_definition(mod, argc, argv, METHOD_VISI_PUBLIC);
}

/*
 *  call-seq:
 *     mod.private_method_defined?(symbol, inherit=true)    -> true or false
 *     mod.private_method_defined?(string, inherit=true)    -> true or false
 *
 *  Returns +true+ if the named private method is defined by
 *  _mod_.  If _inherit_ is set, the lookup will also search _mod_'s
 *  ancestors.
 *  String arguments are converted to symbols.
 *
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       private
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1                   #=> true
 *     C.private_method_defined? "method1"          #=> false
 *     C.private_method_defined? "method2"          #=> true
 *     C.private_method_defined? "method2", true    #=> true
 *     C.private_method_defined? "method2", false   #=> false
 *     C.method_defined? "method2"                  #=> false
 */

static VALUE
rb_mod_private_method_defined(int argc, VALUE *argv, VALUE mod)
{
    return check_definition(mod, argc, argv, METHOD_VISI_PRIVATE);
}

/*
 *  call-seq:
 *     mod.protected_method_defined?(symbol, inherit=true)   -> true or false
 *     mod.protected_method_defined?(string, inherit=true)   -> true or false
 *
 *  Returns +true+ if the named protected method is defined
 *  _mod_.  If _inherit_ is set, the lookup will also search _mod_'s
 *  ancestors.
 *  String arguments are converted to symbols.
 *
 *     module A
 *       def method1()  end
 *     end
 *     class B
 *       protected
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1                    #=> true
 *     C.protected_method_defined? "method1"         #=> false
 *     C.protected_method_defined? "method2"         #=> true
 *     C.protected_method_defined? "method2", true   #=> true
 *     C.protected_method_defined? "method2", false  #=> false
 *     C.method_defined? "method2"                   #=> true
 */

static VALUE
rb_mod_protected_method_defined(int argc, VALUE *argv, VALUE mod)
{
    return check_definition(mod, argc, argv, METHOD_VISI_PROTECTED);
}

int
rb_method_entry_eq(const rb_method_entry_t *m1, const rb_method_entry_t *m2)
{
    return rb_method_definition_eq(m1->def, m2->def);
}

static const rb_method_definition_t *
original_method_definition(const rb_method_definition_t *def)
{
  again:
    if (def) {
	switch (def->type) {
	  case VM_METHOD_TYPE_REFINED:
	    if (def->body.refined.orig_me) {
		def = def->body.refined.orig_me->def;
		goto again;
	    }
	    break;
	  case VM_METHOD_TYPE_ALIAS:
	    def = def->body.alias.original_me->def;
	    goto again;
	  default:
	    break;
	}
    }
    return def;
}

MJIT_FUNC_EXPORTED int
rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2)
{
    d1 = original_method_definition(d1);
    d2 = original_method_definition(d2);

    if (d1 == d2) return 1;
    if (!d1 || !d2) return 0;
    if (d1->type != d2->type) return 0;

    switch (d1->type) {
      case VM_METHOD_TYPE_ISEQ:
        return d1->body.iseq.iseqptr == d2->body.iseq.iseqptr;
      case VM_METHOD_TYPE_CFUNC:
	return
	  d1->body.cfunc.func == d2->body.cfunc.func &&
	  d1->body.cfunc.argc == d2->body.cfunc.argc;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	return d1->body.attr.id == d2->body.attr.id;
      case VM_METHOD_TYPE_BMETHOD:
        return RTEST(rb_equal(d1->body.bmethod.proc, d2->body.bmethod.proc));
      case VM_METHOD_TYPE_MISSING:
	return d1->original_id == d2->original_id;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_UNDEF:
	return 1;
      case VM_METHOD_TYPE_OPTIMIZED:
	return (d1->body.optimized.type == d2->body.optimized.type) &&
               (d1->body.optimized.index == d2->body.optimized.index);
      case VM_METHOD_TYPE_REFINED:
      case VM_METHOD_TYPE_ALIAS:
	break;
    }
    rb_bug("rb_method_definition_eq: unsupported type: %d\n", d1->type);
}

static st_index_t
rb_hash_method_definition(st_index_t hash, const rb_method_definition_t *def)
{
    hash = rb_hash_uint(hash, def->type);
    def = original_method_definition(def);

    if (!def) return hash;

    switch (def->type) {
      case VM_METHOD_TYPE_ISEQ:
	return rb_hash_uint(hash, (st_index_t)def->body.iseq.iseqptr);
      case VM_METHOD_TYPE_CFUNC:
	hash = rb_hash_uint(hash, (st_index_t)def->body.cfunc.func);
	return rb_hash_uint(hash, def->body.cfunc.argc);
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	return rb_hash_uint(hash, def->body.attr.id);
      case VM_METHOD_TYPE_BMETHOD:
        return rb_hash_proc(hash, def->body.bmethod.proc);
      case VM_METHOD_TYPE_MISSING:
	return rb_hash_uint(hash, def->original_id);
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_UNDEF:
	return hash;
      case VM_METHOD_TYPE_OPTIMIZED:
        hash = rb_hash_uint(hash, def->body.optimized.index);
	return rb_hash_uint(hash, def->body.optimized.type);
      case VM_METHOD_TYPE_REFINED:
      case VM_METHOD_TYPE_ALIAS:
	break; /* unreachable */
    }
    rb_bug("rb_hash_method_definition: unsupported method type (%d)\n", def->type);
}

st_index_t
rb_hash_method_entry(st_index_t hash, const rb_method_entry_t *me)
{
    return rb_hash_method_definition(hash, me->def);
}

void
rb_alias(VALUE klass, ID alias_name, ID original_name)
{
    const VALUE target_klass = klass;
    VALUE defined_class;
    const rb_method_entry_t *orig_me;
    rb_method_visibility_t visi = METHOD_VISI_UNDEF;

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class to make alias");
    }

    rb_class_modify_check(klass);

  again:
    orig_me = search_method(klass, original_name, &defined_class);

    if (orig_me && orig_me->def->type == VM_METHOD_TYPE_REFINED) {
	orig_me = rb_resolve_refined_method(Qnil, orig_me);
    }

    if (UNDEFINED_METHOD_ENTRY_P(orig_me) ||
	UNDEFINED_REFINED_METHOD_P(orig_me->def)) {
	if ((!RB_TYPE_P(klass, T_MODULE)) ||
	    (orig_me = search_method(rb_cObject, original_name, &defined_class),
	     UNDEFINED_METHOD_ENTRY_P(orig_me))) {
	    rb_print_undef(klass, original_name, METHOD_VISI_UNDEF);
	}
    }

    switch (orig_me->def->type) {
      case VM_METHOD_TYPE_ZSUPER:
	klass = RCLASS_SUPER(klass);
	original_name = orig_me->def->original_id;
	visi = METHOD_ENTRY_VISI(orig_me);
	goto again;
      case VM_METHOD_TYPE_ALIAS:
        orig_me = orig_me->def->body.alias.original_me;
        VM_ASSERT(orig_me->def->type != VM_METHOD_TYPE_ALIAS);
        break;
      default: break;
    }

    if (visi == METHOD_VISI_UNDEF) visi = METHOD_ENTRY_VISI(orig_me);

    if (orig_me->defined_class == 0) {
	rb_method_entry_make(target_klass, alias_name, target_klass, visi,
			     VM_METHOD_TYPE_ALIAS, NULL, orig_me->called_id,
			     (void *)rb_method_entry_clone(orig_me));
	method_added(target_klass, alias_name);
    }
    else {
	rb_method_entry_t *alias_me;

	alias_me = method_entry_set(target_klass, alias_name, orig_me, visi, orig_me->owner);
	RB_OBJ_WRITE(alias_me, &alias_me->owner, target_klass);
        RB_OBJ_WRITE(alias_me, &alias_me->defined_class, orig_me->defined_class);
    }
}

/*
 *  call-seq:
 *     alias_method(new_name, old_name)   -> symbol
 *
 *  Makes <i>new_name</i> a new copy of the method <i>old_name</i>. This can
 *  be used to retain access to methods that are overridden.
 *
 *     module Mod
 *       alias_method :orig_exit, :exit #=> :orig_exit
 *       def exit(code=0)
 *         puts "Exiting with code #{code}"
 *         orig_exit(code)
 *       end
 *     end
 *     include Mod
 *     exit(99)
 *
 *  <em>produces:</em>
 *
 *     Exiting with code 99
 */

static VALUE
rb_mod_alias_method(VALUE mod, VALUE newname, VALUE oldname)
{
    ID oldid = rb_check_id(&oldname);
    if (!oldid) {
	rb_print_undef_str(mod, oldname);
    }
    VALUE id = rb_to_id(newname);
    rb_alias(mod, id, oldid);
    return ID2SYM(id);
}

static void
check_and_export_method(VALUE self, VALUE name, rb_method_visibility_t visi)
{
    ID id = rb_check_id(&name);
    if (!id) {
	rb_print_undef_str(self, name);
    }
    rb_export_method(self, id, visi);
}

static void
set_method_visibility(VALUE self, int argc, const VALUE *argv, rb_method_visibility_t visi)
{
    int i;

    rb_check_frozen(self);
    if (argc == 0) {
	rb_warning("%"PRIsVALUE" with no argument is just ignored",
		   QUOTE_ID(rb_frame_callee()));
	return;
    }


    VALUE v;

    if (argc == 1 && (v = rb_check_array_type(argv[0])) != Qnil) {
        long j;

	for (j = 0; j < RARRAY_LEN(v); j++) {
	    check_and_export_method(self, RARRAY_AREF(v, j), visi);
	}
    }
    else {
        for (i = 0; i < argc; i++) {
            check_and_export_method(self, argv[i], visi);
        }
    }
}

static VALUE
set_visibility(int argc, const VALUE *argv, VALUE module, rb_method_visibility_t visi)
{
    if (argc == 0) {
        scope_visibility_check();
        rb_scope_visibility_set(visi);
        return Qnil;
    }

    set_method_visibility(module, argc, argv, visi);
    if (argc == 1) {
        return argv[0];
    }
    return rb_ary_new_from_values(argc, argv);
}

/*
 *  call-seq:
 *     public                                -> nil
 *     public(method_name)                   -> method_name
 *     public(method_name, method_name, ...) -> array
 *     public(array)                         -> array
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 *  String arguments are converted to symbols.
 *  An Array of Symbols and/or Strings is also accepted.
 *  If a single argument is passed, it is returned.
 *  If no argument is passed, nil is returned.
 *  If multiple arguments are passed, the arguments are returned as an array.
 */

static VALUE
rb_mod_public(int argc, VALUE *argv, VALUE module)
{
    return set_visibility(argc, argv, module, METHOD_VISI_PUBLIC);
}

/*
 *  call-seq:
 *     protected                                -> nil
 *     protected(method_name)                   -> method_name
 *     protected(method_name, method_name, ...) -> array
 *     protected(array)                         -> array
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to protected. With arguments, sets the named methods
 *  to have protected visibility.
 *  String arguments are converted to symbols.
 *  An Array of Symbols and/or Strings is also accepted.
 *  If a single argument is passed, it is returned.
 *  If no argument is passed, nil is returned.
 *  If multiple arguments are passed, the arguments are returned as an array.
 *
 *  If a method has protected visibility, it is callable only where
 *  <code>self</code> of the context is the same as the method.
 *  (method definition or instance_eval). This behavior is different from
 *  Java's protected method. Usually <code>private</code> should be used.
 *
 *  Note that a protected method is slow because it can't use inline cache.
 *
 *  To show a private method on RDoc, use <code>:doc:</code> instead of this.
 */

static VALUE
rb_mod_protected(int argc, VALUE *argv, VALUE module)
{
    return set_visibility(argc, argv, module, METHOD_VISI_PROTECTED);
}

/*
 *  call-seq:
 *     private                                -> nil
 *     private(method_name)                   -> method_name
 *     private(method_name, method_name, ...) -> array
 *     private(array)                         -> array
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to private. With arguments, sets the named methods
 *  to have private visibility.
 *  String arguments are converted to symbols.
 *  An Array of Symbols and/or Strings is also accepted.
 *  If a single argument is passed, it is returned.
 *  If no argument is passed, nil is returned.
 *  If multiple arguments are passed, the arguments are returned as an array.
 *
 *     module Mod
 *       def a()  end
 *       def b()  end
 *       private
 *       def c()  end
 *       private :a
 *     end
 *     Mod.private_instance_methods   #=> [:a, :c]
 *
 *  Note that to show a private method on RDoc, use <code>:doc:</code>.
 */

static VALUE
rb_mod_private(int argc, VALUE *argv, VALUE module)
{
    return set_visibility(argc, argv, module, METHOD_VISI_PRIVATE);
}

/*
 *  call-seq:
 *     ruby2_keywords(method_name, ...)    -> nil
 *
 *  For the given method names, marks the method as passing keywords through
 *  a normal argument splat.  This should only be called on methods that
 *  accept an argument splat (<tt>*args</tt>) but not explicit keywords or
 *  a keyword splat.  It marks the method such that if the method is called
 *  with keyword arguments, the final hash argument is marked with a special
 *  flag such that if it is the final element of a normal argument splat to
 *  another method call, and that method call does not include explicit
 *  keywords or a keyword splat, the final element is interpreted as keywords.
 *  In other words, keywords will be passed through the method to other
 *  methods.
 *
 *  This should only be used for methods that delegate keywords to another
 *  method, and only for backwards compatibility with Ruby versions before 3.0.
 *  See https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/
 *  for details on why +ruby2_keywords+ exists and when and how to use it.
 *
 *  This method will probably be removed at some point, as it exists only
 *  for backwards compatibility. As it does not exist in Ruby versions before
 *  2.7, check that the module responds to this method before calling it:
 *
 *    module Mod
 *      def foo(meth, *args, &block)
 *        send(:"do_#{meth}", *args, &block)
 *      end
 *      ruby2_keywords(:foo) if respond_to?(:ruby2_keywords, true)
 *    end
 *
 *  However, be aware that if the +ruby2_keywords+ method is removed, the
 *  behavior of the +foo+ method using the above approach will change so that
 *  the method does not pass through keywords.
 */

static VALUE
rb_mod_ruby2_keywords(int argc, VALUE *argv, VALUE module)
{
    int i;
    VALUE origin_class = RCLASS_ORIGIN(module);

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    rb_check_frozen(module);

    for (i = 0; i < argc; i++) {
        VALUE v = argv[i];
        ID name = rb_check_id(&v);
        rb_method_entry_t *me;
        VALUE defined_class;

        if (!name) {
            rb_print_undef_str(module, v);
        }

        me = search_method(origin_class, name, &defined_class);
        if (!me && RB_TYPE_P(module, T_MODULE)) {
            me = search_method(rb_cObject, name, &defined_class);
        }

        if (UNDEFINED_METHOD_ENTRY_P(me) ||
            UNDEFINED_REFINED_METHOD_P(me->def)) {
            rb_print_undef(module, name, METHOD_VISI_UNDEF);
        }

        if (module == defined_class || origin_class == defined_class) {
            switch (me->def->type) {
              case VM_METHOD_TYPE_ISEQ:
                if (me->def->body.iseq.iseqptr->body->param.flags.has_rest &&
                        !me->def->body.iseq.iseqptr->body->param.flags.has_kw &&
                        !me->def->body.iseq.iseqptr->body->param.flags.has_kwrest) {
                    me->def->body.iseq.iseqptr->body->param.flags.ruby2_keywords = 1;
                    rb_clear_method_cache(module, name);
                }
                else {
                    rb_warn("Skipping set of ruby2_keywords flag for %s (method accepts keywords or method does not accept argument splat)", rb_id2name(name));
                }
                break;
              case VM_METHOD_TYPE_BMETHOD: {
                VALUE procval = me->def->body.bmethod.proc;
                if (vm_block_handler_type(procval) == block_handler_type_proc) {
                    procval = vm_proc_to_block_handler(VM_BH_TO_PROC(procval));
                }

                if (vm_block_handler_type(procval) == block_handler_type_iseq) {
                    const struct rb_captured_block *captured = VM_BH_TO_ISEQ_BLOCK(procval);
                    const rb_iseq_t *iseq = rb_iseq_check(captured->code.iseq);
                    if (iseq->body->param.flags.has_rest &&
                            !iseq->body->param.flags.has_kw &&
                            !iseq->body->param.flags.has_kwrest) {
                        iseq->body->param.flags.ruby2_keywords = 1;
                        rb_clear_method_cache(module, name);
                    }
                    else {
                        rb_warn("Skipping set of ruby2_keywords flag for %s (method accepts keywords or method does not accept argument splat)", rb_id2name(name));
                    }
                    break;
                }
              }
              /* fallthrough */
              default:
                rb_warn("Skipping set of ruby2_keywords flag for %s (method not defined in Ruby)", rb_id2name(name));
                break;
            }
        }
        else {
            rb_warn("Skipping set of ruby2_keywords flag for %s (can only set in method defining module)", rb_id2name(name));
        }
    }
    return Qnil;
}

/*
 *  call-seq:
 *     mod.public_class_method(symbol, ...)    -> mod
 *     mod.public_class_method(string, ...)    -> mod
 *     mod.public_class_method(array)          -> mod
 *
 *  Makes a list of existing class methods public.
 *
 *  String arguments are converted to symbols.
 *  An Array of Symbols and/or Strings is also accepted.
 */

static VALUE
rb_mod_public_method(int argc, VALUE *argv, VALUE obj)
{
    set_method_visibility(rb_singleton_class(obj), argc, argv, METHOD_VISI_PUBLIC);
    return obj;
}

/*
 *  call-seq:
 *     mod.private_class_method(symbol, ...)   -> mod
 *     mod.private_class_method(string, ...)   -> mod
 *     mod.private_class_method(array)         -> mod
 *
 *  Makes existing class methods private. Often used to hide the default
 *  constructor <code>new</code>.
 *
 *  String arguments are converted to symbols.
 *  An Array of Symbols and/or Strings is also accepted.
 *
 *     class SimpleSingleton  # Not thread safe
 *       private_class_method :new
 *       def SimpleSingleton.create(*args, &block)
 *         @me = new(*args, &block) if ! @me
 *         @me
 *       end
 *     end
 */

static VALUE
rb_mod_private_method(int argc, VALUE *argv, VALUE obj)
{
    set_method_visibility(rb_singleton_class(obj), argc, argv, METHOD_VISI_PRIVATE);
    return obj;
}

/*
 *  call-seq:
 *     public
 *     public(symbol, ...)
 *     public(string, ...)
 *     public(array)
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 *
 *  String arguments are converted to symbols.
 *  An Array of Symbols and/or Strings is also accepted.
 */

static VALUE
top_public(int argc, VALUE *argv, VALUE _)
{
    return rb_mod_public(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     private
 *     private(symbol, ...)
 *     private(string, ...)
 *     private(array)
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to private. With arguments, sets the named methods to
 *  have private visibility.
 *
 *  String arguments are converted to symbols.
 *  An Array of Symbols and/or Strings is also accepted.
 */
static VALUE
top_private(int argc, VALUE *argv, VALUE _)
{
    return rb_mod_private(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     ruby2_keywords(method_name, ...) -> self
 *
 *  For the given method names, marks the method as passing keywords through
 *  a normal argument splat.  See Module#ruby2_keywords in detail.
 */
static VALUE
top_ruby2_keywords(int argc, VALUE *argv, VALUE module)
{
    return rb_mod_ruby2_keywords(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     module_function                                -> nil
 *     module_function(method_name)                   -> method_name
 *     module_function(method_name, method_name, ...) -> array
 *
 *  Creates module functions for the named methods. These functions may
 *  be called with the module as a receiver, and also become available
 *  as instance methods to classes that mix in the module. Module
 *  functions are copies of the original, and so may be changed
 *  independently. The instance-method versions are made private. If
 *  used with no arguments, subsequently defined methods become module
 *  functions.
 *  String arguments are converted to symbols.
 *  If a single argument is passed, it is returned.
 *  If no argument is passed, nil is returned.
 *  If multiple arguments are passed, the arguments are returned as an array.
 *
 *     module Mod
 *       def one
 *         "This is one"
 *       end
 *       module_function :one
 *     end
 *     class Cls
 *       include Mod
 *       def call_one
 *         one
 *       end
 *     end
 *     Mod.one     #=> "This is one"
 *     c = Cls.new
 *     c.call_one  #=> "This is one"
 *     module Mod
 *       def one
 *         "This is the new one"
 *       end
 *     end
 *     Mod.one     #=> "This is one"
 *     c.call_one  #=> "This is the new one"
 */

static VALUE
rb_mod_modfunc(int argc, VALUE *argv, VALUE module)
{
    int i;
    ID id;
    const rb_method_entry_t *me;

    if (!RB_TYPE_P(module, T_MODULE)) {
	rb_raise(rb_eTypeError, "module_function must be called for modules");
    }

    if (argc == 0) {
	rb_scope_module_func_set();
        return Qnil;
    }

    set_method_visibility(module, argc, argv, METHOD_VISI_PRIVATE);

    for (i = 0; i < argc; i++) {
	VALUE m = module;

	id = rb_to_id(argv[i]);
	for (;;) {
	    me = search_method(m, id, 0);
	    if (me == 0) {
		me = search_method(rb_cObject, id, 0);
	    }
	    if (UNDEFINED_METHOD_ENTRY_P(me)) {
		rb_print_undef(module, id, METHOD_VISI_UNDEF);
	    }
	    if (me->def->type != VM_METHOD_TYPE_ZSUPER) {
		break; /* normal case: need not to follow 'super' link */
	    }
	    m = RCLASS_SUPER(m);
	    if (!m)
		break;
	}
	rb_method_entry_set(rb_singleton_class(module), id, me, METHOD_VISI_PUBLIC);
    }
    if (argc == 1) {
        return argv[0];
    }
    return rb_ary_new_from_values(argc, argv);
}

#ifdef __GNUC__
#pragma push_macro("rb_method_basic_definition_p")
#undef rb_method_basic_definition_p
#endif
int
rb_method_basic_definition_p(VALUE klass, ID id)
{
    const rb_callable_method_entry_t *cme;
    if (!klass) return TRUE; /* hidden object cannot be overridden */
    cme = rb_callable_method_entry(klass, id);
    return (cme && METHOD_ENTRY_BASIC(cme)) ? TRUE : FALSE;
}
#ifdef __GNUC__
#pragma pop_macro("rb_method_basic_definition_p")
#endif

static VALUE
call_method_entry(rb_execution_context_t *ec, VALUE defined_class, VALUE obj, ID id,
                  const rb_callable_method_entry_t *cme, int argc, const VALUE *argv, int kw_splat)
{
    VALUE passed_block_handler = vm_passed_block_handler(ec);
    VALUE result = rb_vm_call_kw(ec, obj, id, argc, argv, cme, kw_splat);
    vm_passed_block_handler_set(ec, passed_block_handler);
    return result;
}

static VALUE
basic_obj_respond_to_missing(rb_execution_context_t *ec, VALUE klass, VALUE obj,
			     VALUE mid, VALUE priv)
{
    VALUE defined_class, args[2];
    const ID rtmid = idRespond_to_missing;
    const rb_callable_method_entry_t *const cme = callable_method_entry(klass, rtmid, &defined_class);

    if (!cme || METHOD_ENTRY_BASIC(cme)) return Qundef;
    args[0] = mid;
    args[1] = priv;
    return call_method_entry(ec, defined_class, obj, rtmid, cme, 2, args, RB_NO_KEYWORDS);
}

static inline int
basic_obj_respond_to(rb_execution_context_t *ec, VALUE obj, ID id, int pub)
{
    VALUE klass = CLASS_OF(obj);
    VALUE ret;

    switch (method_boundp(klass, id, pub|BOUND_RESPONDS)) {
      case 2:
	return FALSE;
      case 0:
	ret = basic_obj_respond_to_missing(ec, klass, obj, ID2SYM(id),
					   pub ? Qfalse : Qtrue);
	return RTEST(ret) && ret != Qundef;
      default:
	return TRUE;
    }
}

static int
vm_respond_to(rb_execution_context_t *ec, VALUE klass, VALUE obj, ID id, int priv)
{
    VALUE defined_class;
    const ID resid = idRespond_to;
    const rb_callable_method_entry_t *const cme = callable_method_entry(klass, resid, &defined_class);

    if (!cme) return -1;
    if (METHOD_ENTRY_BASIC(cme)) {
	return -1;
    }
    else {
	int argc = 1;
	VALUE args[2];
	VALUE result;

	args[0] = ID2SYM(id);
	args[1] = Qtrue;
	if (priv) {
            argc = rb_method_entry_arity((const rb_method_entry_t *)cme);
	    if (argc > 2) {
		rb_raise(rb_eArgError,
			 "respond_to? must accept 1 or 2 arguments (requires %d)",
			 argc);
	    }
	    if (argc != 1) {
		argc = 2;
	    }
	    else if (!NIL_P(ruby_verbose)) {
		VALUE location = rb_method_entry_location((const rb_method_entry_t *)cme);
                rb_category_warn(RB_WARN_CATEGORY_DEPRECATED,
                        "%"PRIsVALUE"%c""respond_to?(:%"PRIsVALUE") uses"
			" the deprecated method signature, which takes one parameter",
			(FL_TEST(klass, FL_SINGLETON) ? obj : klass),
			(FL_TEST(klass, FL_SINGLETON) ? '.' : '#'),
			QUOTE_ID(id));
		if (!NIL_P(location)) {
		    VALUE path = RARRAY_AREF(location, 0);
		    VALUE line = RARRAY_AREF(location, 1);
		    if (!NIL_P(path)) {
			rb_category_compile_warn(RB_WARN_CATEGORY_DEPRECATED,
					RSTRING_PTR(path), NUM2INT(line),
					"respond_to? is defined here");
		    }
		}
	    }
	}
        result = call_method_entry(ec, defined_class, obj, resid, cme, argc, args, RB_NO_KEYWORDS);
	return RTEST(result);
    }
}

int
rb_obj_respond_to(VALUE obj, ID id, int priv)
{
    rb_execution_context_t *ec = GET_EC();
    return rb_ec_obj_respond_to(ec, obj, id, priv);
}

int
rb_ec_obj_respond_to(rb_execution_context_t *ec, VALUE obj, ID id, int priv)
{
    VALUE klass = CLASS_OF(obj);
    int ret = vm_respond_to(ec, klass, obj, id, priv);
    if (ret == -1) ret = basic_obj_respond_to(ec, obj, id, !priv);
    return ret;
}

int
rb_respond_to(VALUE obj, ID id)
{
    return rb_obj_respond_to(obj, id, FALSE);
}


/*
 *  call-seq:
 *     obj.respond_to?(symbol, include_all=false) -> true or false
 *     obj.respond_to?(string, include_all=false) -> true or false
 *
 *  Returns +true+ if _obj_ responds to the given method.  Private and
 *  protected methods are included in the search only if the optional
 *  second parameter evaluates to +true+.
 *
 *  If the method is not implemented,
 *  as Process.fork on Windows, File.lchmod on GNU/Linux, etc.,
 *  false is returned.
 *
 *  If the method is not defined, <code>respond_to_missing?</code>
 *  method is called and the result is returned.
 *
 *  When the method name parameter is given as a string, the string is
 *  converted to a symbol.
 */

static VALUE
obj_respond_to(int argc, VALUE *argv, VALUE obj)
{
    VALUE mid, priv;
    ID id;
    rb_execution_context_t *ec = GET_EC();

    rb_scan_args(argc, argv, "11", &mid, &priv);
    if (!(id = rb_check_id(&mid))) {
	VALUE ret = basic_obj_respond_to_missing(ec, CLASS_OF(obj), obj,
						 rb_to_symbol(mid), priv);
	if (ret == Qundef) ret = Qfalse;
	return ret;
    }
    return  RBOOL(basic_obj_respond_to(ec, obj, id, !RTEST(priv)));
}

/*
 *  call-seq:
 *     obj.respond_to_missing?(symbol, include_all) -> true or false
 *     obj.respond_to_missing?(string, include_all) -> true or false
 *
 *  DO NOT USE THIS DIRECTLY.
 *
 *  Hook method to return whether the _obj_ can respond to _id_ method
 *  or not.
 *
 *  When the method name parameter is given as a string, the string is
 *  converted to a symbol.
 *
 *  See #respond_to?, and the example of BasicObject.
 */
static VALUE
obj_respond_to_missing(VALUE obj, VALUE mid, VALUE priv)
{
    return Qfalse;
}

void
Init_Method(void)
{
    //
}

void
Init_eval_method(void)
{
    rb_define_method(rb_mKernel, "respond_to?", obj_respond_to, -1);
    rb_define_method(rb_mKernel, "respond_to_missing?", obj_respond_to_missing, 2);

    rb_define_method(rb_cModule, "remove_method", rb_mod_remove_method, -1);
    rb_define_method(rb_cModule, "undef_method", rb_mod_undef_method, -1);
    rb_define_method(rb_cModule, "alias_method", rb_mod_alias_method, 2);
    rb_define_private_method(rb_cModule, "public", rb_mod_public, -1);
    rb_define_private_method(rb_cModule, "protected", rb_mod_protected, -1);
    rb_define_private_method(rb_cModule, "private", rb_mod_private, -1);
    rb_define_private_method(rb_cModule, "module_function", rb_mod_modfunc, -1);
    rb_define_private_method(rb_cModule, "ruby2_keywords", rb_mod_ruby2_keywords, -1);

    rb_define_method(rb_cModule, "method_defined?", rb_mod_method_defined, -1);
    rb_define_method(rb_cModule, "public_method_defined?", rb_mod_public_method_defined, -1);
    rb_define_method(rb_cModule, "private_method_defined?", rb_mod_private_method_defined, -1);
    rb_define_method(rb_cModule, "protected_method_defined?", rb_mod_protected_method_defined, -1);
    rb_define_method(rb_cModule, "public_class_method", rb_mod_public_method, -1);
    rb_define_method(rb_cModule, "private_class_method", rb_mod_private_method, -1);

    rb_define_private_method(rb_singleton_class(rb_vm_top_self()),
			     "public", top_public, -1);
    rb_define_private_method(rb_singleton_class(rb_vm_top_self()),
			     "private", top_private, -1);
    rb_define_private_method(rb_singleton_class(rb_vm_top_self()),
			     "ruby2_keywords", top_ruby2_keywords, -1);

    {
#define REPLICATE_METHOD(klass, id) do { \
	    const rb_method_entry_t *me = rb_method_entry((klass), (id)); \
	    rb_method_entry_set((klass), (id), me, METHOD_ENTRY_VISI(me)); \
	} while (0)

	REPLICATE_METHOD(rb_eException, idMethodMissing);
	REPLICATE_METHOD(rb_eException, idRespond_to);
	REPLICATE_METHOD(rb_eException, idRespond_to_missing);
    }
}
