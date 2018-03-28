/*
 * This file is included by vm.c
 */

#include "id_table.h"

#define METHOD_DEBUG 0

#if OPT_GLOBAL_METHOD_CACHE
#ifndef GLOBAL_METHOD_CACHE_SIZE
#define GLOBAL_METHOD_CACHE_SIZE 0x800
#endif
#define LSB_ONLY(x) ((x) & ~((x) - 1))
#define POWER_OF_2_P(x) ((x) == LSB_ONLY(x))
#if !POWER_OF_2_P(GLOBAL_METHOD_CACHE_SIZE)
# error GLOBAL_METHOD_CACHE_SIZE must be power of 2
#endif
#ifndef GLOBAL_METHOD_CACHE_MASK
#define GLOBAL_METHOD_CACHE_MASK (GLOBAL_METHOD_CACHE_SIZE-1)
#endif

#define GLOBAL_METHOD_CACHE_KEY(c,m) ((((c)>>3)^(m))&(global_method_cache.mask))
#define GLOBAL_METHOD_CACHE(c,m) (global_method_cache.entries + GLOBAL_METHOD_CACHE_KEY(c,m))
#else
#define GLOBAL_METHOD_CACHE(c,m) (rb_bug("global method cache disabled improperly"), NULL)
#endif

static int vm_redefinition_check_flag(VALUE klass);
static void rb_vm_check_redefinition_opt_method(const rb_method_entry_t *me, VALUE klass);

#define object_id           idObject_id
#define added               idMethod_added
#define singleton_added     idSingleton_method_added
#define removed             idMethod_removed
#define singleton_removed   idSingleton_method_removed
#define undefined           idMethod_undefined
#define singleton_undefined idSingleton_method_undefined
#define attached            id__attached__

struct cache_entry {
    rb_serial_t method_state;
    rb_serial_t class_serial;
    ID mid;
    rb_method_entry_t* me;
    VALUE defined_class;
};

#if OPT_GLOBAL_METHOD_CACHE
static struct {
    unsigned int size;
    unsigned int mask;
    struct cache_entry *entries;
} global_method_cache = {
    GLOBAL_METHOD_CACHE_SIZE,
    GLOBAL_METHOD_CACHE_MASK,
};
#endif

#define ruby_running (GET_VM()->running)
/* int ruby_running = 0; */

static void
rb_class_clear_method_cache(VALUE klass, VALUE arg)
{
    RCLASS_SERIAL(klass) = rb_next_class_serial();

    if (RB_TYPE_P(klass, T_ICLASS)) {
	struct rb_id_table *table = RCLASS_CALLABLE_M_TBL(klass);
	if (table) {
	    rb_id_table_clear(table);
	}
    }
    else {
	if (RCLASS_CALLABLE_M_TBL(klass) != 0) {
	    rb_obj_info_dump(klass);
	    rb_bug("RCLASS_CALLABLE_M_TBL(klass) != 0");
	}
    }

    rb_class_foreach_subclass(klass, rb_class_clear_method_cache, arg);
}

void
rb_clear_cache(void)
{
    rb_warning("rb_clear_cache() is deprecated.");
    INC_GLOBAL_METHOD_STATE();
    INC_GLOBAL_CONSTANT_STATE();
}

void
rb_clear_constant_cache(void)
{
    INC_GLOBAL_CONSTANT_STATE();
}

void
rb_clear_method_cache_by_class(VALUE klass)
{
    if (klass && klass != Qundef) {
	int global = klass == rb_cBasicObject || klass == rb_cObject || klass == rb_mKernel;

	RUBY_DTRACE_HOOK(METHOD_CACHE_CLEAR, (global ? "global" : rb_class2name(klass)));

	if (global) {
	    INC_GLOBAL_METHOD_STATE();
	}
	else {
	    rb_class_clear_method_cache(klass, Qnil);
	}
    }

    if (klass == rb_mKernel) {
	rb_subclass_entry_t *entry = RCLASS_EXT(klass)->subclasses;

	for (; entry != NULL; entry = entry->next) {
	    struct rb_id_table *table = RCLASS_CALLABLE_M_TBL(entry->klass);
	    if (table)rb_id_table_clear(table);
	}
    }
}

VALUE
rb_f_notimplement(int argc, const VALUE *argv, VALUE obj)
{
    rb_notimplement();

    UNREACHABLE;
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

static void
rb_method_definition_release(rb_method_definition_t *def, int complemented)
{
    if (def != NULL) {
	const int alias_count = def->alias_count;
	const int complemented_count = def->complemented_count;
	VM_ASSERT(alias_count >= 0);
	VM_ASSERT(complemented_count >= 0);

	if (alias_count + complemented_count == 0) {
	    if (METHOD_DEBUG) fprintf(stderr, "-%p-%s:%d,%d (remove)\n", def, rb_id2name(def->original_id), alias_count, complemented_count);
	    xfree(def);
	}
	else {
	    if (complemented) def->complemented_count--;
	    else if (def->alias_count > 0) def->alias_count--;

	    if (METHOD_DEBUG) fprintf(stderr, "-%p-%s:%d->%d,%d->%d (dec)\n", def, rb_id2name(def->original_id),
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
static int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);

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

static VALUE
(*call_cfunc_invoker_func(int argc))(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *)
{
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
	rb_bug("call_cfunc_func: unsupported length: %d", argc);
    }
}

static void
setup_method_cfunc_struct(rb_method_cfunc_t *cfunc, VALUE (*func)(), int argc)
{
    cfunc->func = func;
    cfunc->argc = argc;
    cfunc->invoker = call_cfunc_invoker_func(argc);
}

static void
method_definition_set(const rb_method_entry_t *me, rb_method_definition_t *def, void *opts)
{
    *(rb_method_definition_t **)&me->def = def;

    if (opts != NULL) {
	switch (def->type) {
	  case VM_METHOD_TYPE_ISEQ:
	    {
		rb_method_iseq_t *iseq_body = (rb_method_iseq_t *)opts;
		rb_cref_t *method_cref, *cref = iseq_body->cref;

		/* setup iseq first (before invoking GC) */
		RB_OBJ_WRITE(me, &def->body.iseq.iseqptr, iseq_body->iseqptr);

		if (0) vm_cref_dump("rb_method_definition_create", cref);

		if (cref) {
		    method_cref = cref;
		}
		else {
		    method_cref = vm_cref_new_toplevel(GET_THREAD()); /* TODO: can we reuse? */
		}

		RB_OBJ_WRITE(me, &def->body.iseq.cref, method_cref);
		return;
	    }
	  case VM_METHOD_TYPE_CFUNC:
	    {
		rb_method_cfunc_t *cfunc = (rb_method_cfunc_t *)opts;
		setup_method_cfunc_struct(&def->body.cfunc, cfunc->func, cfunc->argc);
		return;
	    }
	  case VM_METHOD_TYPE_ATTRSET:
	  case VM_METHOD_TYPE_IVAR:
	    {
		rb_thread_t *th = GET_THREAD();
		rb_control_frame_t *cfp;
		int line;

		def->body.attr.id = (ID)(VALUE)opts;

		cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

		if (cfp && (line = rb_vm_get_sourceline(cfp))) {
		    VALUE location = rb_ary_new3(2, cfp->iseq->body->location.path, INT2FIX(line));
		    RB_OBJ_WRITE(me, &def->body.attr.location, rb_ary_freeze(location));
		}
		else {
		    VM_ASSERT(def->body.attr.location == 0);
		}
		return;
	    }
	  case VM_METHOD_TYPE_BMETHOD:
	    RB_OBJ_WRITE(me, &def->body.proc, (VALUE)opts);
	    return;
	  case VM_METHOD_TYPE_NOTIMPLEMENTED:
	    setup_method_cfunc_struct(&def->body.cfunc, rb_f_notimplement, -1);
	    return;
	  case VM_METHOD_TYPE_OPTIMIZED:
	    def->body.optimize_type = (enum method_optimized_type)opts;
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

    switch(def->type) {
      case VM_METHOD_TYPE_ISEQ:
	RB_OBJ_WRITTEN(me, Qundef, def->body.iseq.iseqptr);
	RB_OBJ_WRITTEN(me, Qundef, def->body.iseq.cref);
	break;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	RB_OBJ_WRITTEN(me, Qundef, def->body.attr.location);
	break;
      case VM_METHOD_TYPE_BMETHOD:
	RB_OBJ_WRITTEN(me, Qundef, def->body.proc);
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

static rb_method_definition_t *
method_definition_create(rb_method_type_t type, ID mid)
{
    rb_method_definition_t *def;
    def = ZALLOC(rb_method_definition_t);
    def->type = type;
    def->original_id = mid;
    return def;
}

static rb_method_definition_t *
method_definition_addref(rb_method_definition_t *def)
{
    def->alias_count++;
    if (METHOD_DEBUG) fprintf(stderr, "+%p-%s:%d\n", def, rb_id2name(def->original_id), def->alias_count);
    return def;
}

static rb_method_definition_t *
method_definition_addref_complement(rb_method_definition_t *def)
{
    def->complemented_count++;
    if (METHOD_DEBUG) fprintf(stderr, "+%p-%s:%d\n", def, rb_id2name(def->original_id), def->alias_count);
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
    METHOD_ENTRY_FLAGS_COPY(me, src_me);
    return me;
}

const rb_callable_method_entry_t *
rb_method_entry_complement_defined_class(const rb_method_entry_t *src_me, ID called_id, VALUE defined_class)
{
    rb_method_entry_t *me = rb_method_entry_alloc(called_id, src_me->owner, defined_class,
						  method_definition_addref_complement(src_me->def));
    METHOD_ENTRY_FLAGS_COPY(me, src_me);
    METHOD_ENTRY_COMPLEMENTED_SET(me);

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
	    const struct rb_method_entry_struct *orig_me;
	    VALUE owner;
	} refined;

	rb_vm_check_redefinition_opt_method(me, me->owner);

	refined.orig_me = rb_method_entry_clone(me);
	refined.owner = owner;

	method_definition_set(me, method_definition_create(VM_METHOD_TYPE_REFINED, me->called_id), (void *)&refined);
	METHOD_ENTRY_VISI_SET(me, METHOD_VISI_PUBLIC);
    }
}

void
rb_add_refined_method_entry(VALUE refined_class, ID mid)
{
    rb_method_entry_t *me = lookup_method_table(refined_class, mid);

    if (me) {
	make_method_entry_refined(refined_class, me);
	rb_clear_method_cache_by_class(refined_class);
    }
    else {
	rb_add_method(refined_class, mid, VM_METHOD_TYPE_REFINED, 0, METHOD_VISI_PUBLIC);
    }
}

static void
check_override_opt_method(VALUE klass, VALUE arg)
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
    rb_class_foreach_subclass(klass, check_override_opt_method, (VALUE)mid);
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

    if (NIL_P(klass)) {
	klass = rb_cObject;
    }
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

    rb_frozen_class_p(klass);

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
		iseq = rb_proc_get_iseq(old_def->body.proc, 0);
		break;
	      default:
		break;
	    }
	    if (iseq && !NIL_P(iseq->body->location.path)) {
		int line = iseq->body->line_info_table ? FIX2INT(rb_iseq_first_lineno(iseq)) : 0;
		rb_compile_warning(RSTRING_PTR(iseq->body->location.path), line,
				   "previous definition of %"PRIsVALUE" was here",
				   rb_id2str(old_def->original_id));
	    }
	}
    }

    /* create method entry */
    me = rb_method_entry_create(mid, defined_class, visi, NULL);
    if (def == NULL) def = method_definition_create(type, original_id);
    method_definition_set(me, def, opts);

    rb_clear_method_cache_by_class(klass);

    /* check mid */
    if (klass == rb_cObject && mid == idInitialize) {
	rb_warn("redefining Object#initialize may cause infinite loop");
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

    rb_id_table_insert(mtbl, mid, (VALUE)me);
    RB_OBJ_WRITTEN(klass, Qundef, (VALUE)me);

    VM_ASSERT(me->def != NULL);

    /* check optimized method override by a prepended module */
    if (RB_TYPE_P(klass, T_MODULE)) {
	check_override_opt_method(klass, (VALUE)mid);
    }

    return me;
}

#define CALL_METHOD_HOOK(klass, hook, mid) do {		\
	const VALUE arg = ID2SYM(mid);			\
	VALUE recv_class = (klass);			\
	ID hook_id = (hook);				\
	if (FL_TEST((klass), FL_SINGLETON)) {		\
	    recv_class = rb_ivar_get((klass), attached);	\
	    hook_id = singleton_##hook;			\
	}						\
	rb_funcall2(recv_class, hook_id, 1, &arg);	\
    } while (0)

static void
method_added(VALUE klass, ID mid)
{
    if (ruby_running) {
	CALL_METHOD_HOOK(klass, added, mid);
    }
}

rb_method_entry_t *
rb_add_method(VALUE klass, ID mid, rb_method_type_t type, void *opts, rb_method_visibility_t visi)
{
    rb_method_entry_t *me = rb_method_entry_make(klass, mid, klass, visi, type, NULL, mid, opts);

    if (type != VM_METHOD_TYPE_UNDEF && type != VM_METHOD_TYPE_REFINED) {
	method_added(klass, mid);
    }

    return me;
}

void
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
    RCLASS_EXT(klass)->allocator = func;
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
	rb_alloc_func_t allocator = RCLASS_EXT(klass)->allocator;
	if (allocator == UNDEF_ALLOC_FUNC) break;
	if (allocator) return allocator;
    }
    return 0;
}

static inline rb_method_entry_t*
search_method(VALUE klass, ID id, VALUE *defined_class_ptr)
{
    rb_method_entry_t *me;

    for (me = 0; klass; klass = RCLASS_SUPER(klass)) {
	if ((me = lookup_method_table(klass, id)) != 0) break;
    }

    if (defined_class_ptr)
	*defined_class_ptr = klass;
    return me;
}

const rb_method_entry_t *
rb_method_entry_at(VALUE klass, ID id)
{
    return lookup_method_table(klass, id);
}

/*
 * search method entry without the method cache.
 *
 * if you need method entry with method cache (normal case), use
 * rb_method_entry() simply.
 */
static rb_method_entry_t *
method_entry_get_without_cache(VALUE klass, ID id,
			       VALUE *defined_class_ptr)
{
    VALUE defined_class;
    rb_method_entry_t *me = search_method(klass, id, &defined_class);

    if (ruby_running) {
	if (OPT_GLOBAL_METHOD_CACHE) {
	    struct cache_entry *ent;
	    ent = GLOBAL_METHOD_CACHE(klass, id);
	    ent->class_serial = RCLASS_SERIAL(klass);
	    ent->method_state = GET_GLOBAL_METHOD_STATE();
	    ent->defined_class = defined_class;
	    ent->mid = id;

	    if (UNDEFINED_METHOD_ENTRY_P(me)) {
		ent->me = 0;
		me = 0;
	    }
	    else {
		ent->me = me;
	    }
	}
	else if (UNDEFINED_METHOD_ENTRY_P(me)) {
	    me = 0;
	}
    }

    if (defined_class_ptr)
	*defined_class_ptr = defined_class;
    return me;
}

#if VM_DEBUG_VERIFY_METHOD_CACHE
static void
verify_method_cache(VALUE klass, ID id, VALUE defined_class, rb_method_entry_t *me)
{
    VALUE actual_defined_class;
    rb_method_entry_t *actual_me =
      method_entry_get_without_cache(klass, id, &actual_defined_class);

    if (me != actual_me || defined_class != actual_defined_class) {
	rb_bug("method cache verification failed");
    }
}
#endif

static rb_method_entry_t *
method_entry_get(VALUE klass, ID id, VALUE *defined_class_ptr)
{
#if OPT_GLOBAL_METHOD_CACHE
    struct cache_entry *ent;
    ent = GLOBAL_METHOD_CACHE(klass, id);
    if (ent->method_state == GET_GLOBAL_METHOD_STATE() &&
	ent->class_serial == RCLASS_SERIAL(klass) &&
	ent->mid == id) {
#if VM_DEBUG_VERIFY_METHOD_CACHE
	verify_method_cache(klass, id, ent->defined_class, ent->me);
#endif
	if (defined_class_ptr) *defined_class_ptr = ent->defined_class;
	return ent->me;
    }
#endif

    return method_entry_get_without_cache(klass, id, defined_class_ptr);
}

const rb_method_entry_t *
rb_method_entry(VALUE klass, ID id)
{
    return method_entry_get(klass, id, NULL);
}

static const rb_callable_method_entry_t *
prepare_callable_method_entry(VALUE defined_class, ID id, const rb_method_entry_t *me)
{
    struct rb_id_table *mtbl;
    const rb_callable_method_entry_t *cme;

    if (me && me->defined_class == 0) {
	VM_ASSERT(RB_TYPE_P(defined_class, T_ICLASS));
	VM_ASSERT(me->defined_class == 0);

	if ((mtbl = RCLASS_CALLABLE_M_TBL(defined_class)) == NULL) {
	    mtbl = RCLASS_EXT(defined_class)->callable_m_tbl = rb_id_table_create(0);
	}

	if (rb_id_table_lookup(mtbl, id, (VALUE *)&me)) {
	    cme = (rb_callable_method_entry_t *)me;
	    VM_ASSERT(callable_method_entry_p(cme));
	}
	else {
	    cme = rb_method_entry_complement_defined_class(me, me->called_id, defined_class);
	    rb_id_table_insert(mtbl, id, (VALUE)cme);
	    VM_ASSERT(callable_method_entry_p(cme));
	}
    }
    else {
	cme = (const rb_callable_method_entry_t *)me;
    }

    VM_ASSERT(callable_method_entry_p(cme));
    return cme;
}

const rb_callable_method_entry_t *
rb_callable_method_entry(VALUE klass, ID id)
{
    VALUE defined_class;
    rb_method_entry_t *me = method_entry_get(klass, id, &defined_class);
    return prepare_callable_method_entry(defined_class, id, me);
}

static const rb_method_entry_t *resolve_refined_method(VALUE refinements, const rb_method_entry_t *me, VALUE *defined_class_ptr);

static const rb_method_entry_t *
method_entry_resolve_refinement(VALUE klass, ID id, int with_refinement, VALUE *defined_class_ptr)
{
    const rb_method_entry_t *me = method_entry_get(klass, id, defined_class_ptr);

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

const rb_method_entry_t *
rb_method_entry_with_refinements(VALUE klass, ID id)
{
    return method_entry_resolve_refinement(klass, id, TRUE, NULL);
}

const rb_callable_method_entry_t *
rb_callable_method_entry_with_refinements(VALUE klass, ID id)
{
    VALUE defined_class;
    const rb_method_entry_t *me = method_entry_resolve_refinement(klass, id, TRUE, &defined_class);
    return prepare_callable_method_entry(defined_class, id, me);
}

const rb_method_entry_t *
rb_method_entry_without_refinements(VALUE klass, ID id)
{
    return method_entry_resolve_refinement(klass, id, FALSE, NULL);
}

const rb_callable_method_entry_t *
rb_callable_method_entry_without_refinements(VALUE klass, ID id)
{
    VALUE defined_class;
    const rb_method_entry_t *me = method_entry_resolve_refinement(klass, id, FALSE, &defined_class);
    return prepare_callable_method_entry(defined_class, id, me);
}

static const rb_method_entry_t *
refined_method_original_method_entry(VALUE refinements, const rb_method_entry_t *me, VALUE *defined_class_ptr)
{
    VALUE super;

    if (me->def->body.refined.orig_me) {
	if (defined_class_ptr) *defined_class_ptr = me->def->body.refined.orig_me->defined_class;
	return me->def->body.refined.orig_me;
    }
    else if (!(super = RCLASS_SUPER(me->owner))) {
	return 0;
    }
    else {
	rb_method_entry_t *tmp_me;
	tmp_me = method_entry_get(super, me->called_id, defined_class_ptr);
	return resolve_refined_method(refinements, tmp_me, defined_class_ptr);
    }
}

static const rb_method_entry_t *
resolve_refined_method(VALUE refinements, const rb_method_entry_t *me, VALUE *defined_class_ptr)
{
    if (me && me->def->type == VM_METHOD_TYPE_REFINED) {
	VALUE refinement;
	rb_method_entry_t *tmp_me;

	refinement = find_refinement(refinements, me->owner);
	if (NIL_P(refinement)) {
	    return refined_method_original_method_entry(refinements, me, defined_class_ptr);
	}
	else {
	    tmp_me = method_entry_get(refinement, me->called_id, defined_class_ptr);

	    if (tmp_me && tmp_me->def->type != VM_METHOD_TYPE_REFINED) {
		return tmp_me;
	    }
	    else {
		return refined_method_original_method_entry(refinements, me, defined_class_ptr);
	    }
	}
    }
    else {
	return me;
    }
}

const rb_method_entry_t *
rb_resolve_refined_method(VALUE refinements, const rb_method_entry_t *me)
{
    return resolve_refined_method(refinements, me, NULL);
}

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
    rb_frozen_class_p(klass);
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

    rb_id_table_delete(RCLASS_M_TBL(klass), mid);

    rb_vm_check_redefinition_opt_method(me, klass);
    rb_clear_method_cache_by_class(klass);

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
 *  class. For an example, see <code>Module.undef_method</code>.
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

    me = search_method(origin_class, name, &defined_class);
    if (!me && RB_TYPE_P(klass, T_MODULE)) {
	me = search_method(rb_cObject, name, &defined_class);
    }

    if (UNDEFINED_METHOD_ENTRY_P(me) ||
	UNDEFINED_REFINED_METHOD_P(me->def)) {
	rb_print_undef(klass, name, 0);
    }

    if (METHOD_ENTRY_VISI(me) != visi) {
	rb_vm_check_redefinition_opt_method(me, klass);

	if (klass == defined_class || origin_class == defined_class) {
	    METHOD_ENTRY_VISI_SET(me, visi);

	    if (me->def->type == VM_METHOD_TYPE_REFINED && me->def->body.refined.orig_me) {
		METHOD_ENTRY_VISI_SET((rb_method_entry_t *)me->def->body.refined.orig_me, visi);
	    }
	    rb_clear_method_cache_by_class(klass);
	}
	else {
	    rb_add_method(klass, name, VM_METHOD_TYPE_ZSUPER, 0, visi);
	}
    }
}

#define BOUND_PRIVATE  0x01
#define BOUND_RESPONDS 0x02

int
rb_method_boundp(VALUE klass, ID id, int ex)
{
    const rb_method_entry_t *me = rb_method_entry_without_refinements(klass, id);

    if (me != 0) {
	if ((ex & ~BOUND_RESPONDS) &&
	    ((METHOD_ENTRY_VISI(me) == METHOD_VISI_PRIVATE) ||
	     ((ex & BOUND_RESPONDS) && (METHOD_ENTRY_VISI(me) == METHOD_VISI_PROTECTED)))) {
	    return 0;
	}

	if (me->def->type == VM_METHOD_TYPE_NOTIMPLEMENTED) {
	    if (ex & BOUND_RESPONDS) return 2;
	    return 0;
	}
	return 1;
    }
    return 0;
}

static rb_method_visibility_t
rb_scope_visibility_get(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (!vm_env_cref_by_cref(cfp->ep)) {
	return METHOD_VISI_PUBLIC;
    }
    else {
	return CREF_SCOPE_VISI(rb_vm_cref())->method_visi;
    }
}

static int
rb_scope_module_func_check(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (!vm_env_cref_by_cref(cfp->ep)) {
	return FALSE;
    }
    else {
	return CREF_SCOPE_VISI(rb_vm_cref())->module_func;
    }
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
rb_scope_module_func_set(void)
{
    vm_cref_set_visibility(METHOD_VISI_PRIVATE, TRUE);
}

void
rb_attr(VALUE klass, ID id, int read, int write, int ex)
{
    ID attriv;
    rb_method_visibility_t visi;

    if (!ex) {
	visi = METHOD_VISI_PUBLIC;
    }
    else {
	switch (rb_scope_visibility_get()) {
	  case METHOD_VISI_PRIVATE:
	    if (rb_scope_module_func_check()) {
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
    rb_frozen_class_p(klass);
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

/*
 *  call-seq:
 *     mod.method_defined?(symbol)    -> true or false
 *     mod.method_defined?(string)    -> true or false
 *
 *  Returns +true+ if the named method is defined by
 *  _mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors). Public and protected methods are matched.
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
 *     C.method_defined? "method3"             #=> true
 *     C.method_defined? "protected_method1"   #=> true
 *     C.method_defined? "method4"             #=> false
 *     C.method_defined? "private_method2"     #=> false
 */

static VALUE
rb_mod_method_defined(VALUE mod, VALUE mid)
{
    ID id = rb_check_id(&mid);
    if (!id || !rb_method_boundp(mod, id, 1)) {
	return Qfalse;
    }
    return Qtrue;

}

static VALUE
check_definition(VALUE mod, VALUE mid, rb_method_visibility_t visi)
{
    const rb_method_entry_t *me;
    ID id = rb_check_id(&mid);
    if (!id) return Qfalse;
    me = rb_method_entry_without_refinements(mod, id);
    if (me) {
	if (METHOD_ENTRY_VISI(me) == visi) return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.public_method_defined?(symbol)   -> true or false
 *     mod.public_method_defined?(string)   -> true or false
 *
 *  Returns +true+ if the named public method is defined by
 *  _mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors).
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
 *     A.method_defined? :method1           #=> true
 *     C.public_method_defined? "method1"   #=> true
 *     C.public_method_defined? "method2"   #=> false
 *     C.method_defined? "method2"          #=> true
 */

static VALUE
rb_mod_public_method_defined(VALUE mod, VALUE mid)
{
    return check_definition(mod, mid, METHOD_VISI_PUBLIC);
}

/*
 *  call-seq:
 *     mod.private_method_defined?(symbol)    -> true or false
 *     mod.private_method_defined?(string)    -> true or false
 *
 *  Returns +true+ if the named private method is defined by
 *  _ mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors).
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
 *     A.method_defined? :method1            #=> true
 *     C.private_method_defined? "method1"   #=> false
 *     C.private_method_defined? "method2"   #=> true
 *     C.method_defined? "method2"           #=> false
 */

static VALUE
rb_mod_private_method_defined(VALUE mod, VALUE mid)
{
    return check_definition(mod, mid, METHOD_VISI_PRIVATE);
}

/*
 *  call-seq:
 *     mod.protected_method_defined?(symbol)   -> true or false
 *     mod.protected_method_defined?(string)   -> true or false
 *
 *  Returns +true+ if the named protected method is defined
 *  by _mod_ (or its included modules and, if _mod_ is a
 *  class, its ancestors).
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
 *     A.method_defined? :method1              #=> true
 *     C.protected_method_defined? "method1"   #=> false
 *     C.protected_method_defined? "method2"   #=> true
 *     C.method_defined? "method2"             #=> true
 */

static VALUE
rb_mod_protected_method_defined(VALUE mod, VALUE mid)
{
    return check_definition(mod, mid, METHOD_VISI_PROTECTED);
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

static int
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
	return RTEST(rb_equal(d1->body.proc, d2->body.proc));
      case VM_METHOD_TYPE_MISSING:
	return d1->original_id == d2->original_id;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_UNDEF:
	return 1;
      case VM_METHOD_TYPE_OPTIMIZED:
	return d1->body.optimize_type == d2->body.optimize_type;
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
	return rb_hash_proc(hash, def->body.proc);
      case VM_METHOD_TYPE_MISSING:
	return rb_hash_uint(hash, def->original_id);
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_UNDEF:
	return hash;
      case VM_METHOD_TYPE_OPTIMIZED:
	return rb_hash_uint(hash, def->body.optimize_type);
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

    rb_frozen_class_p(klass);

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
	    rb_print_undef(klass, original_name, 0);
	}
    }

    if (orig_me->def->type == VM_METHOD_TYPE_ZSUPER) {
	klass = RCLASS_SUPER(klass);
	original_name = orig_me->def->original_id;
	visi = METHOD_ENTRY_VISI(orig_me);
	goto again;
    }

    if (visi == METHOD_VISI_UNDEF) visi = METHOD_ENTRY_VISI(orig_me);

    if (orig_me->defined_class == 0) {
	rb_method_entry_t *alias_me;

	alias_me = rb_add_method(target_klass, alias_name, VM_METHOD_TYPE_ALIAS, (void *)rb_method_entry_clone(orig_me), visi);
	alias_me->def->original_id = orig_me->called_id;
    }
    else {
	rb_method_entry_t *alias_me;

	alias_me = method_entry_set(target_klass, alias_name, orig_me, visi, orig_me->owner);
	RB_OBJ_WRITE(alias_me, &alias_me->owner, target_klass);
	RB_OBJ_WRITE(alias_me, &alias_me->defined_class, defined_class);
    }
}

/*
 *  call-seq:
 *     alias_method(new_name, old_name)   -> self
 *
 *  Makes <i>new_name</i> a new copy of the method <i>old_name</i>. This can
 *  be used to retain access to methods that are overridden.
 *
 *     module Mod
 *       alias_method :orig_exit, :exit
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
    rb_alias(mod, rb_to_id(newname), oldid);
    return mod;
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

    for (i = 0; i < argc; i++) {
	VALUE v = argv[i];
	ID id = rb_check_id(&v);
	if (!id) {
	    rb_print_undef_str(self, v);
	}
	rb_export_method(self, id, visi);
    }
}

static VALUE
set_visibility(int argc, const VALUE *argv, VALUE module, rb_method_visibility_t visi)
{
    if (argc == 0) {
	rb_scope_visibility_set(visi);
    }
    else {
	set_method_visibility(module, argc, argv, visi);
    }
    return module;
}

/*
 *  call-seq:
 *     public                 -> self
 *     public(symbol, ...)    -> self
 *     public(string, ...)    -> self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 *  String arguments are converted to symbols.
 */

static VALUE
rb_mod_public(int argc, VALUE *argv, VALUE module)
{
    return set_visibility(argc, argv, module, METHOD_VISI_PUBLIC);
}

/*
 *  call-seq:
 *     protected                -> self
 *     protected(symbol, ...)   -> self
 *     protected(string, ...)   -> self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to protected. With arguments, sets the named methods
 *  to have protected visibility.
 *  String arguments are converted to symbols.
 */

static VALUE
rb_mod_protected(int argc, VALUE *argv, VALUE module)
{
    return set_visibility(argc, argv, module, METHOD_VISI_PROTECTED);
}

/*
 *  call-seq:
 *     private                 -> self
 *     private(symbol, ...)    -> self
 *     private(string, ...)    -> self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to private. With arguments, sets the named methods
 *  to have private visibility.
 *  String arguments are converted to symbols.
 *
 *     module Mod
 *       def a()  end
 *       def b()  end
 *       private
 *       def c()  end
 *       private :a
 *     end
 *     Mod.private_instance_methods   #=> [:a, :c]
 */

static VALUE
rb_mod_private(int argc, VALUE *argv, VALUE module)
{
    return set_visibility(argc, argv, module, METHOD_VISI_PRIVATE);
}

/*
 *  call-seq:
 *     mod.public_class_method(symbol, ...)    -> mod
 *     mod.public_class_method(string, ...)    -> mod
 *
 *  Makes a list of existing class methods public.
 *
 *  String arguments are converted to symbols.
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
 *
 *  Makes existing class methods private. Often used to hide the default
 *  constructor <code>new</code>.
 *
 *  String arguments are converted to symbols.
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
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 *
 *  String arguments are converted to symbols.
 */

static VALUE
top_public(int argc, VALUE *argv)
{
    return rb_mod_public(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     private
 *     private(symbol, ...)
 *     private(string, ...)
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to private. With arguments, sets the named methods to
 *  have private visibility.
 *
 *  String arguments are converted to symbols.
 */
static VALUE
top_private(int argc, VALUE *argv)
{
    return rb_mod_private(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     module_function(symbol, ...)    -> self
 *     module_function(string, ...)    -> self
 *
 *  Creates module functions for the named methods. These functions may
 *  be called with the module as a receiver, and also become available
 *  as instance methods to classes that mix in the module. Module
 *  functions are copies of the original, and so may be changed
 *  independently. The instance-method versions are made private. If
 *  used with no arguments, subsequently defined methods become module
 *  functions.
 *  String arguments are converted to symbols.
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
	return module;
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
		rb_print_undef(module, id, 0);
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
    return module;
}

int
rb_method_basic_definition_p(VALUE klass, ID id)
{
    const rb_method_entry_t *me = rb_method_entry(klass, id);
    return (me && METHOD_ENTRY_BASIC(me)) ? TRUE : FALSE;
}

static VALUE
call_method_entry(rb_thread_t *th, VALUE defined_class, VALUE obj, ID id,
		  const rb_method_entry_t *me, int argc, const VALUE *argv)
{
    const rb_callable_method_entry_t *cme =
	prepare_callable_method_entry(defined_class, id, me);
    const rb_block_t *passed_block = th->passed_block;
    VALUE result = vm_call0(th, obj, id, argc, argv, cme);
    th->passed_block = passed_block;
    return result;
}

static VALUE
basic_obj_respond_to_missing(rb_thread_t *th, VALUE klass, VALUE obj,
			     VALUE mid, VALUE priv)
{
    VALUE defined_class, args[2];
    const ID rtmid = idRespond_to_missing;
    const rb_method_entry_t *const me =
	method_entry_get(klass, rtmid, &defined_class);

    if (!me || METHOD_ENTRY_BASIC(me)) return Qundef;
    args[0] = mid;
    args[1] = priv;
    return call_method_entry(th, defined_class, obj, rtmid, me, 2, args);
}

static inline int
basic_obj_respond_to(rb_thread_t *th, VALUE obj, ID id, int pub)
{
    VALUE klass = CLASS_OF(obj);
    VALUE ret;

    switch (rb_method_boundp(klass, id, pub|BOUND_RESPONDS)) {
      case 2:
	return FALSE;
      case 0:
	ret = basic_obj_respond_to_missing(th, klass, obj, ID2SYM(id),
					   pub ? Qfalse : Qtrue);
	return RTEST(ret) && ret != Qundef;
      default:
	return TRUE;
    }
}

static int
vm_respond_to(rb_thread_t *th, VALUE klass, VALUE obj, ID id, int priv)
{
    VALUE defined_class;
    const ID resid = idRespond_to;
    const rb_method_entry_t *const me =
	method_entry_get(klass, resid, &defined_class);

    if (!me) return TRUE;
    if (METHOD_ENTRY_BASIC(me)) {
	return -1;
    }
    else {
	int argc = 1;
	VALUE args[2];
	VALUE result;

	args[0] = ID2SYM(id);
	args[1] = Qtrue;
	if (priv) {
	    argc = rb_method_entry_arity(me);
	    if (argc > 2) {
		rb_raise(rb_eArgError,
			 "respond_to? must accept 1 or 2 arguments (requires %d)",
			 argc);
	    }
	    if (argc != 1) {
		argc = 2;
	    }
	    else if (!NIL_P(ruby_verbose)) {
		VALUE location = rb_method_entry_location(me);
		rb_warn("%"PRIsVALUE"%c""respond_to?(:%"PRIsVALUE") is"
			" old fashion which takes only one parameter",
			(FL_TEST(klass, FL_SINGLETON) ? obj : klass),
			(FL_TEST(klass, FL_SINGLETON) ? '.' : '#'),
			QUOTE_ID(id));
		if (!NIL_P(location)) {
		    VALUE path = RARRAY_AREF(location, 0);
		    VALUE line = RARRAY_AREF(location, 1);
		    if (!NIL_P(path)) {
			rb_compile_warn(RSTRING_PTR(path), NUM2INT(line),
					"respond_to? is defined here");
		    }
		}
	    }
	}
	result = call_method_entry(th, defined_class, obj, resid, me, argc, args);
	return RTEST(result);
    }
}

int
rb_obj_respond_to(VALUE obj, ID id, int priv)
{
    rb_thread_t *th = GET_THREAD();
    VALUE klass = CLASS_OF(obj);
    int ret = vm_respond_to(th, klass, obj, id, priv);
    if (ret == -1) ret = basic_obj_respond_to(th, obj, id, !priv);
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
    rb_thread_t *th = GET_THREAD();

    rb_scan_args(argc, argv, "11", &mid, &priv);
    if (!(id = rb_check_id(&mid))) {
	VALUE ret = basic_obj_respond_to_missing(th, CLASS_OF(obj), obj,
						 rb_to_symbol(mid), priv);
	if (ret == Qundef) ret = Qfalse;
	return ret;
    }
    if (basic_obj_respond_to(th, obj, id, !RTEST(priv)))
	return Qtrue;
    return Qfalse;
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
#if OPT_GLOBAL_METHOD_CACHE
    char *ptr = getenv("RUBY_GLOBAL_METHOD_CACHE_SIZE");
    int val;

    if (ptr != NULL && (val = atoi(ptr)) > 0) {
	if ((val & (val - 1)) == 0) { /* ensure val is a power of 2 */
	    global_method_cache.size = val;
	    global_method_cache.mask = val - 1;
	}
	else {
	   fprintf(stderr, "RUBY_GLOBAL_METHOD_CACHE_SIZE was set to %d but ignored because the value is not a power of 2.\n", val);
	}
    }

    global_method_cache.entries = (struct cache_entry *)calloc(global_method_cache.size, sizeof(struct cache_entry));
    if (global_method_cache.entries == NULL) {
	fprintf(stderr, "[FATAL] failed to allocate memory\n");
	exit(EXIT_FAILURE);
    }
#endif
}

void
Init_eval_method(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    rb_define_method(rb_mKernel, "respond_to?", obj_respond_to, -1);
    rb_define_method(rb_mKernel, "respond_to_missing?", obj_respond_to_missing, 2);

    rb_define_private_method(rb_cModule, "remove_method", rb_mod_remove_method, -1);
    rb_define_private_method(rb_cModule, "undef_method", rb_mod_undef_method, -1);
    rb_define_private_method(rb_cModule, "alias_method", rb_mod_alias_method, 2);
    rb_define_private_method(rb_cModule, "public", rb_mod_public, -1);
    rb_define_private_method(rb_cModule, "protected", rb_mod_protected, -1);
    rb_define_private_method(rb_cModule, "private", rb_mod_private, -1);
    rb_define_private_method(rb_cModule, "module_function", rb_mod_modfunc, -1);

    rb_define_method(rb_cModule, "method_defined?", rb_mod_method_defined, 1);
    rb_define_method(rb_cModule, "public_method_defined?", rb_mod_public_method_defined, 1);
    rb_define_method(rb_cModule, "private_method_defined?", rb_mod_private_method_defined, 1);
    rb_define_method(rb_cModule, "protected_method_defined?", rb_mod_protected_method_defined, 1);
    rb_define_method(rb_cModule, "public_class_method", rb_mod_public_method, -1);
    rb_define_method(rb_cModule, "private_class_method", rb_mod_private_method, -1);

    rb_define_private_method(rb_singleton_class(rb_vm_top_self()),
			     "public", top_public, -1);
    rb_define_private_method(rb_singleton_class(rb_vm_top_self()),
			     "private", top_private, -1);

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
