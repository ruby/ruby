/*
 * This file is included by vm.c
 */

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

#define GLOBAL_METHOD_CACHE_KEY(c,m) ((((c)>>3)^(m))&GLOBAL_METHOD_CACHE_MASK)
#define GLOBAL_METHOD_CACHE(c,m) (global_method_cache + GLOBAL_METHOD_CACHE_KEY(c,m))
#include "method.h"

#define NOEX_NOREDEF 0
#ifndef NOEX_NOREDEF
#define NOEX_NOREDEF NOEX_RESPONDS
#endif

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

static struct cache_entry global_method_cache[GLOBAL_METHOD_CACHE_SIZE];
#define ruby_running (GET_VM()->running)
/* int ruby_running = 0; */

static void
rb_class_clear_method_cache(VALUE klass)
{
    RCLASS_SERIAL(klass) = rb_next_class_serial();
    rb_class_foreach_subclass(klass, rb_class_clear_method_cache);
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

	if (RUBY_DTRACE_METHOD_CACHE_CLEAR_ENABLED()) {
	    RUBY_DTRACE_METHOD_CACHE_CLEAR(global ? "global" : rb_class2name(klass), rb_sourcefile(), rb_sourceline());
	}

	if (global) {
	    INC_GLOBAL_METHOD_STATE();
	}
	else {
	    rb_class_clear_method_cache(klass);
	}
    }
}

VALUE
rb_f_notimplement(int argc, VALUE *argv, VALUE obj)
{
    rb_notimplement();

    UNREACHABLE;
}

static void
rb_define_notimplement_method_id(VALUE mod, ID id, rb_method_flag_t noex)
{
    rb_add_method(mod, id, VM_METHOD_TYPE_NOTIMPLEMENTED, 0, noex);
}

void
rb_add_method_cfunc(VALUE klass, ID mid, VALUE (*func)(ANYARGS), int argc, rb_method_flag_t noex)
{
    if (argc < -2 || 15 < argc) rb_raise(rb_eArgError, "arity out of range: %d for -2..15", argc);
    if (func != rb_f_notimplement) {
	rb_method_cfunc_t opt;
	opt.func = func;
	opt.argc = argc;
	rb_add_method(klass, mid, VM_METHOD_TYPE_CFUNC, &opt, noex);
    }
    else {
	rb_define_notimplement_method_id(klass, mid, noex);
    }
}

void
rb_unlink_method_entry(rb_method_entry_t *me)
{
    struct unlinked_method_entry_list_entry *ume = ALLOC(struct unlinked_method_entry_list_entry);
    ume->me = me;
    ume->next = GET_VM()->unlinked_method_entry_list;
    GET_VM()->unlinked_method_entry_list = ume;
}

void
rb_gc_mark_unlinked_live_method_entries(void *pvm)
{
    rb_vm_t *vm = pvm;
    struct unlinked_method_entry_list_entry *ume = vm->unlinked_method_entry_list;

    while (ume) {
	if (ume->me->mark) {
	    rb_mark_method_entry(ume->me);
	}
	ume = ume->next;
    }
}

void
rb_sweep_method_entry(void *pvm)
{
    rb_vm_t *vm = pvm;
    struct unlinked_method_entry_list_entry **prev_ume = &vm->unlinked_method_entry_list, *ume = *prev_ume, *curr_ume;

    while (ume) {
	if (ume->me->mark) {
	    ume->me->mark = 0;
	    prev_ume = &ume->next;
	    ume = *prev_ume;
	}
	else {
	    rb_free_method_entry(ume->me);

	    curr_ume = ume;
	    ume = ume->next;
	    *prev_ume = ume;
	    xfree(curr_ume);
	}
    }
}

static void
release_method_definition(rb_method_definition_t *def)
{
    if (def == 0)
	return;
    if (def->alias_count == 0) {
	if (def->type == VM_METHOD_TYPE_REFINED &&
	    def->body.orig_me) {
	    release_method_definition(def->body.orig_me->def);
	    xfree(def->body.orig_me);
	}
	xfree(def);
    }
    else if (def->alias_count > 0) {
	def->alias_count--;
    }
}

void
rb_free_method_entry(rb_method_entry_t *me)
{
    release_method_definition(me->def);
    xfree(me);
}

static int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);

static inline rb_method_entry_t *
lookup_method_table(VALUE klass, ID id)
{
    st_data_t body;
    st_table *m_tbl = RCLASS_M_TBL(klass);
    if (st_lookup(m_tbl, id, &body)) {
	return (rb_method_entry_t *) body;
    }
    else {
	return 0;
    }
}

static void
make_method_entry_refined(rb_method_entry_t *me)
{
    rb_method_definition_t *new_def;

    if (me->def && me->def->type == VM_METHOD_TYPE_REFINED)
	return;

    new_def = ALLOC(rb_method_definition_t);
    new_def->type = VM_METHOD_TYPE_REFINED;
    new_def->original_id = me->called_id;
    new_def->alias_count = 0;
    new_def->body.orig_me = ALLOC(rb_method_entry_t);
    *new_def->body.orig_me = *me;
    rb_vm_check_redefinition_opt_method(me, me->klass);
    if (me->def) me->def->alias_count++;
    me->flag = NOEX_WITH_SAFE(NOEX_PUBLIC);
    me->def = new_def;
}

void
rb_add_refined_method_entry(VALUE refined_class, ID mid)
{
    rb_method_entry_t *me = lookup_method_table(refined_class, mid);

    if (me) {
	make_method_entry_refined(me);
	rb_clear_method_cache_by_class(refined_class);
    }
    else {
	rb_add_method(refined_class, mid, VM_METHOD_TYPE_REFINED, 0,
		      NOEX_PUBLIC);
    }
}

static rb_method_entry_t *
rb_method_entry_make(VALUE klass, ID mid, rb_method_type_t type,
		     rb_method_definition_t *def, rb_method_flag_t noex,
		     VALUE defined_class)
{
    rb_method_entry_t *me;
#if NOEX_NOREDEF
    VALUE rklass;
#endif
    st_table *mtbl;
    st_data_t data;
    int make_refined = 0;

    if (NIL_P(klass)) {
	klass = rb_cObject;
    }
    if (!FL_TEST(klass, FL_SINGLETON) &&
	type != VM_METHOD_TYPE_NOTIMPLEMENTED &&
	type != VM_METHOD_TYPE_ZSUPER &&
	(mid == idInitialize || mid == idInitialize_copy ||
	 mid == idInitialize_clone || mid == idInitialize_dup ||
	 mid == idRespond_to_missing)) {
	noex = NOEX_PRIVATE | noex;
    }

    rb_check_frozen(klass);
#if NOEX_NOREDEF
    rklass = klass;
#endif
    if (FL_TEST(klass, RMODULE_IS_REFINEMENT)) {
	VALUE refined_class =
	    rb_refinement_module_get_refined_class(klass);

	rb_add_refined_method_entry(refined_class, mid);
    }
    if (type == VM_METHOD_TYPE_REFINED) {
	rb_method_entry_t *old_me =
	    lookup_method_table(RCLASS_ORIGIN(klass), mid);
	if (old_me) rb_vm_check_redefinition_opt_method(old_me, klass);
    }
    else {
	klass = RCLASS_ORIGIN(klass);
    }
    mtbl = RCLASS_M_TBL(klass);

    /* check re-definition */
    if (st_lookup(mtbl, mid, &data)) {
	rb_method_entry_t *old_me = (rb_method_entry_t *)data;
	rb_method_definition_t *old_def = old_me->def;

	if (rb_method_definition_eq(old_def, def)) return old_me;
#if NOEX_NOREDEF
	if (old_me->flag & NOEX_NOREDEF) {
	    rb_raise(rb_eTypeError, "cannot redefine %"PRIsVALUE"#%"PRIsVALUE,
		     rb_class_name(rklass), rb_id2str(mid));
	}
#endif
	rb_vm_check_redefinition_opt_method(old_me, klass);
	if (old_def->type == VM_METHOD_TYPE_REFINED)
	    make_refined = 1;

	if (RTEST(ruby_verbose) &&
	    type != VM_METHOD_TYPE_UNDEF &&
	    old_def->alias_count == 0 &&
	    old_def->type != VM_METHOD_TYPE_UNDEF &&
	    old_def->type != VM_METHOD_TYPE_ZSUPER) {
	    rb_iseq_t *iseq = 0;

	    rb_warning("method redefined; discarding old %s", rb_id2name(mid));
	    switch (old_def->type) {
	      case VM_METHOD_TYPE_ISEQ:
		iseq = old_def->body.iseq;
		break;
	      case VM_METHOD_TYPE_BMETHOD:
		iseq = rb_proc_get_iseq(old_def->body.proc, 0);
		break;
	      default:
		break;
	    }
	    if (iseq && !NIL_P(iseq->location.path)) {
		int line = iseq->line_info_table ? FIX2INT(rb_iseq_first_lineno(iseq->self)) : 0;
		rb_compile_warning(RSTRING_PTR(iseq->location.path), line,
				   "previous definition of %s was here",
				   rb_id2name(old_def->original_id));
	    }
	}

	rb_unlink_method_entry(old_me);
    }

    me = ALLOC(rb_method_entry_t);

    rb_clear_method_cache_by_class(klass);

    me->flag = NOEX_WITH_SAFE(noex);
    me->mark = 0;
    me->called_id = mid;
    RB_OBJ_WRITE(klass, &me->klass, defined_class);
    me->def = def;

    if (def) {
	def->alias_count++;

	switch(def->type) {
	  case VM_METHOD_TYPE_ISEQ:
	    RB_OBJ_WRITTEN(klass, Qundef, def->body.iseq->self);
	    break;
	  case VM_METHOD_TYPE_IVAR:
	    RB_OBJ_WRITTEN(klass, Qundef, def->body.attr.location);
	    break;
	  case VM_METHOD_TYPE_BMETHOD:
	    RB_OBJ_WRITTEN(klass, Qundef, def->body.proc);
	    break;
	  default:;
	    /* ignore */
	}
    }

    /* check mid */
    if (klass == rb_cObject && mid == idInitialize) {
	rb_warn("redefining Object#initialize may cause infinite loop");
    }
    /* check mid */
    if (mid == object_id || mid == id__send__) {
	if (type == VM_METHOD_TYPE_ISEQ) {
	    rb_warn("redefining `%s' may cause serious problems", rb_id2name(mid));
	}
    }

    if (make_refined) {
	make_method_entry_refined(me);
    }

    st_insert(mtbl, mid, (st_data_t) me);

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

rb_method_entry_t *
rb_add_method(VALUE klass, ID mid, rb_method_type_t type, void *opts, rb_method_flag_t noex)
{
    rb_thread_t *th;
    rb_control_frame_t *cfp;
    int line;
    rb_method_entry_t *me = rb_method_entry_make(klass, mid, type, 0, noex, klass);
    rb_method_definition_t *def = ALLOC(rb_method_definition_t);
    if (me->def && me->def->type == VM_METHOD_TYPE_REFINED) {
	me->def->body.orig_me->def = def;
    }
    else {
	me->def = def;
    }
    def->type = type;
    def->original_id = mid;
    def->alias_count = 0;
    switch (type) {
      case VM_METHOD_TYPE_ISEQ: {
	  rb_iseq_t *iseq = (rb_iseq_t *)opts;
	  *(rb_iseq_t **)&def->body.iseq = iseq;
	  RB_OBJ_WRITTEN(klass, Qundef, iseq->self);
	  break;
      }
      case VM_METHOD_TYPE_CFUNC:
	{
	    rb_method_cfunc_t *cfunc = (rb_method_cfunc_t *)opts;
	    setup_method_cfunc_struct(&def->body.cfunc, cfunc->func, cfunc->argc);
	}
	break;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	def->body.attr.id = (ID)opts;
	RB_OBJ_WRITE(klass, &def->body.attr.location, Qfalse);
	th = GET_THREAD();
	cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);
	if (cfp && (line = rb_vm_get_sourceline(cfp))) {
	    VALUE location = rb_ary_new3(2, cfp->iseq->location.path, INT2FIX(line));
	    RB_OBJ_WRITE(klass, &def->body.attr.location, rb_ary_freeze(location));
	}
	break;
      case VM_METHOD_TYPE_BMETHOD:
	RB_OBJ_WRITE(klass, &def->body.proc, (VALUE)opts);
	break;
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
	setup_method_cfunc_struct(&def->body.cfunc, rb_f_notimplement, -1);
	break;
      case VM_METHOD_TYPE_OPTIMIZED:
	def->body.optimize_type = (enum method_optimized_type)opts;
	break;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_UNDEF:
	break;
      case VM_METHOD_TYPE_REFINED:
	def->body.orig_me = (rb_method_entry_t *) opts;
	break;
      default:
	rb_bug("rb_add_method: unsupported method type (%d)\n", type);
    }
    if (type != VM_METHOD_TYPE_UNDEF && type != VM_METHOD_TYPE_REFINED) {
	method_added(klass, mid);
    }
    return me;
}

static rb_method_entry_t *
method_entry_set(VALUE klass, ID mid, const rb_method_entry_t *me,
		 rb_method_flag_t noex, VALUE defined_class)
{
    rb_method_type_t type = me->def ? me->def->type : VM_METHOD_TYPE_UNDEF;
    rb_method_entry_t *newme = rb_method_entry_make(klass, mid, type, me->def, noex,
						    defined_class);
    method_added(klass, mid);
    return newme;
}

rb_method_entry_t *
rb_method_entry_set(VALUE klass, ID mid, const rb_method_entry_t *me, rb_method_flag_t noex)
{
    return method_entry_set(klass, mid, me, noex, klass);
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

rb_method_entry_t *
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
rb_method_entry_t *
rb_method_entry_get_without_cache(VALUE klass, ID id,
				  VALUE *defined_class_ptr)
{
    VALUE defined_class;
    rb_method_entry_t *me = search_method(klass, id, &defined_class);

    if (me && RB_TYPE_P(me->klass, T_ICLASS))
	defined_class = me->klass;

    if (ruby_running) {
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
	rb_method_entry_get_without_cache(klass, id, &actual_defined_class);

    if (me != actual_me || defined_class != actual_defined_class) {
	rb_bug("method cache verification failed");
    }
}
#endif

rb_method_entry_t *
rb_method_entry(VALUE klass, ID id, VALUE *defined_class_ptr)
{
#if OPT_GLOBAL_METHOD_CACHE
    struct cache_entry *ent;
    ent = GLOBAL_METHOD_CACHE(klass, id);
    if (ent->method_state == GET_GLOBAL_METHOD_STATE() &&
	ent->class_serial == RCLASS_SERIAL(klass) &&
	ent->mid == id) {
	if (defined_class_ptr)
	    *defined_class_ptr = ent->defined_class;
#if VM_DEBUG_VERIFY_METHOD_CACHE
	verify_method_cache(klass, id, ent->defined_class, ent->me);
#endif
	return ent->me;
    }
#endif

    return rb_method_entry_get_without_cache(klass, id, defined_class_ptr);
}

static rb_method_entry_t *
get_original_method_entry(VALUE refinements,
			  const rb_method_entry_t *me,
			  VALUE *defined_class_ptr)
{
    if (me->def->body.orig_me) {
	return me->def->body.orig_me;
    }
    else {
	rb_method_entry_t *tmp_me;
	tmp_me = rb_method_entry(RCLASS_SUPER(me->klass), me->called_id,
				 defined_class_ptr);
	return rb_resolve_refined_method(refinements, tmp_me,
					 defined_class_ptr);
    }
}

rb_method_entry_t *
rb_resolve_refined_method(VALUE refinements, const rb_method_entry_t *me,
			  VALUE *defined_class_ptr)
{
    if (me && me->def->type == VM_METHOD_TYPE_REFINED) {
	VALUE refinement;
	rb_method_entry_t *tmp_me;

	refinement = find_refinement(refinements, me->klass);
	if (NIL_P(refinement)) {
	    return get_original_method_entry(refinements, me,
					     defined_class_ptr);
	}
	tmp_me = rb_method_entry(refinement, me->called_id,
				 defined_class_ptr);
	if (tmp_me && tmp_me->def->type != VM_METHOD_TYPE_REFINED) {
	    return tmp_me;
	}
	else {
	    return get_original_method_entry(refinements, me,
					     defined_class_ptr);
	}
    }
    else {
	return (rb_method_entry_t *)me;
    }
}

rb_method_entry_t *
rb_method_entry_with_refinements(VALUE klass, ID id,
				 VALUE *defined_class_ptr)
{
    VALUE defined_class;
    rb_method_entry_t *me = rb_method_entry(klass, id, &defined_class);

    if (me && me->def->type == VM_METHOD_TYPE_REFINED) {
	NODE *cref = rb_vm_cref();
	VALUE refinements = cref ? cref->nd_refinements : Qnil;

	me = rb_resolve_refined_method(refinements, me, &defined_class);
    }
    if (defined_class_ptr)
	*defined_class_ptr = defined_class;
    return me;
}

rb_method_entry_t *
rb_method_entry_without_refinements(VALUE klass, ID id,
				    VALUE *defined_class_ptr)
{
    VALUE defined_class;
    rb_method_entry_t *me = rb_method_entry(klass, id, &defined_class);

    if (me && me->def->type == VM_METHOD_TYPE_REFINED) {
	me = rb_resolve_refined_method(Qnil, me, &defined_class);
    }
    if (defined_class_ptr)
	*defined_class_ptr = defined_class;
    if (UNDEFINED_METHOD_ENTRY_P(me)) {
	return 0;
    }
    else {
	return me;
    }
}

static void
remove_method(VALUE klass, ID mid)
{
    st_data_t key, data;
    rb_method_entry_t *me = 0;
    VALUE self = klass;

    klass = RCLASS_ORIGIN(klass);
    rb_check_frozen(klass);
    if (mid == object_id || mid == id__send__ || mid == idInitialize) {
	rb_warn("removing `%s' may cause serious problems", rb_id2name(mid));
    }

    if (!st_lookup(RCLASS_M_TBL(klass), mid, &data) ||
	!(me = (rb_method_entry_t *)data) ||
	(!me->def || me->def->type == VM_METHOD_TYPE_UNDEF)) {
	rb_name_error(mid, "method `%s' not defined in %s",
		      rb_id2name(mid), rb_class2name(klass));
    }
    key = (st_data_t)mid;
    st_delete(RCLASS_M_TBL(klass), &key, &data);

    rb_vm_check_redefinition_opt_method(me, klass);
    rb_clear_method_cache_by_class(klass);
    rb_unlink_method_entry(me);

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
	    rb_name_error_str(v, "method `%s' not defined in %s",
			      RSTRING_PTR(v), rb_class2name(mod));
	}
	remove_method(mod, id);
    }
    return mod;
}

#undef rb_disable_super
#undef rb_enable_super

void
rb_disable_super(VALUE klass, const char *name)
{
    /* obsolete - no use */
}

void
rb_enable_super(VALUE klass, const char *name)
{
    rb_warning("rb_enable_super() is obsolete");
}

static void
rb_export_method(VALUE klass, ID name, rb_method_flag_t noex)
{
    rb_method_entry_t *me;
    VALUE defined_class;

    me = search_method(klass, name, &defined_class);
    if (!me && RB_TYPE_P(klass, T_MODULE)) {
	me = search_method(rb_cObject, name, &defined_class);
    }

    if (UNDEFINED_METHOD_ENTRY_P(me)) {
	rb_print_undef(klass, name, 0);
    }

    if (me->flag != noex) {
	rb_vm_check_redefinition_opt_method(me, klass);

	if (klass == defined_class ||
	    RCLASS_ORIGIN(klass) == defined_class) {
	    me->flag = noex;
	    if (me->def->type == VM_METHOD_TYPE_REFINED) {
		me->def->body.orig_me->flag = noex;
	    }
	    rb_clear_method_cache_by_class(klass);
	}
	else {
	    rb_add_method(klass, name, VM_METHOD_TYPE_ZSUPER, 0, noex);
	}
    }
}

int
rb_method_boundp(VALUE klass, ID id, int ex)
{
    rb_method_entry_t *me =
	rb_method_entry_without_refinements(klass, id, 0);

    if (me != 0) {
	if ((ex & ~NOEX_RESPONDS) &&
	    ((me->flag & NOEX_PRIVATE) ||
	     ((ex & NOEX_RESPONDS) && (me->flag & NOEX_PROTECTED)))) {
	    return 0;
	}
	if (!me->def) return 0;
	if (me->def->type == VM_METHOD_TYPE_NOTIMPLEMENTED) {
	    if (ex & NOEX_RESPONDS) return 2;
	    return 0;
	}
	return 1;
    }
    return 0;
}

extern ID rb_check_attr_id(ID id);

void
rb_attr(VALUE klass, ID id, int read, int write, int ex)
{
    ID attriv;
    VALUE aname;
    rb_method_flag_t noex;

    if (!ex) {
	noex = NOEX_PUBLIC;
    }
    else {
	if (SCOPE_TEST(NOEX_PRIVATE)) {
	    noex = NOEX_PRIVATE;
	    rb_warning((SCOPE_CHECK(NOEX_MODFUNC)) ?
		       "attribute accessor as module_function" :
		       "private attribute?");
	}
	else if (SCOPE_TEST(NOEX_PROTECTED)) {
	    noex = NOEX_PROTECTED;
	}
	else {
	    noex = NOEX_PUBLIC;
	}
    }

    aname = rb_id2str(rb_check_attr_id(id));
    if (NIL_P(aname)) {
	rb_raise(rb_eArgError, "argument needs to be symbol or string");
    }
    attriv = rb_intern_str(rb_sprintf("@%"PRIsVALUE, aname));
    if (read) {
	rb_add_method(klass, id, VM_METHOD_TYPE_IVAR, (void *)attriv, noex);
    }
    if (write) {
	rb_add_method(klass, rb_id_attrset(id), VM_METHOD_TYPE_ATTRSET, (void *)attriv, noex);
    }
}

void
rb_undef(VALUE klass, ID id)
{
    rb_method_entry_t *me;

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class to undef method");
    }
    rb_frozen_class_p(klass);
    if (id == object_id || id == id__send__ || id == idInitialize) {
	rb_warn("undefining `%s' may cause serious problems", rb_id2name(id));
    }

    me = search_method(klass, id, 0);

    if (UNDEFINED_METHOD_ENTRY_P(me) ||
	(me->def->type == VM_METHOD_TYPE_REFINED &&
	 UNDEFINED_METHOD_ENTRY_P(me->def->body.orig_me))) {
	const char *s0 = " class";
	VALUE c = klass;

	if (FL_TEST(c, FL_SINGLETON)) {
	    VALUE obj = rb_ivar_get(klass, attached);

	    if (RB_TYPE_P(obj, T_MODULE) || RB_TYPE_P(obj, T_CLASS)) {
		c = obj;
		s0 = "";
	    }
	}
	else if (RB_TYPE_P(c, T_MODULE)) {
	    s0 = " module";
	}
	rb_name_error(id, "undefined method `%"PRIsVALUE"' for%s `%"PRIsVALUE"'",
		      QUOTE_ID(id), s0, rb_class_name(c));
    }

    rb_add_method(klass, id, VM_METHOD_TYPE_UNDEF, 0, NOEX_PUBLIC);

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
 *     end
 *     class B
 *       def method2()  end
 *     end
 *     class C < B
 *       include A
 *       def method3()  end
 *     end
 *
 *     A.method_defined? :method1    #=> true
 *     C.method_defined? "method1"   #=> true
 *     C.method_defined? "method2"   #=> true
 *     C.method_defined? "method3"   #=> true
 *     C.method_defined? "method4"   #=> false
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

#define VISI_CHECK(x,f) (((x)&NOEX_MASK) == (f))

static VALUE
check_definition(VALUE mod, VALUE mid, rb_method_flag_t noex)
{
    const rb_method_entry_t *me;
    ID id = rb_check_id(&mid);
    if (!id) return Qfalse;
    me = rb_method_entry(mod, id, 0);
    if (me) {
	if (VISI_CHECK(me->flag, noex))
	    return Qtrue;
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
    return check_definition(mod, mid, NOEX_PUBLIC);
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
    return check_definition(mod, mid, NOEX_PRIVATE);
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
    return check_definition(mod, mid, NOEX_PROTECTED);
}

int
rb_method_entry_eq(const rb_method_entry_t *m1, const rb_method_entry_t *m2)
{
    return rb_method_definition_eq(m1->def, m2->def);
}

static int
rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2)
{
    if (d1 && d1->type == VM_METHOD_TYPE_REFINED && d1->body.orig_me)
	d1 = d1->body.orig_me->def;
    if (d2 && d2->type == VM_METHOD_TYPE_REFINED && d2->body.orig_me)
	d2 = d2->body.orig_me->def;
    if (d1 == d2) return 1;
    if (!d1 || !d2) return 0;
    if (d1->type != d2->type) {
	return 0;
    }
    switch (d1->type) {
      case VM_METHOD_TYPE_ISEQ:
	return d1->body.iseq == d2->body.iseq;
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
      default:
	rb_bug("rb_method_entry_eq: unsupported method type (%d)\n", d1->type);
	return 0;
    }
}

static st_index_t
rb_hash_method_definition(st_index_t hash, const rb_method_definition_t *def)
{
  again:
    hash = rb_hash_uint(hash, def->type);
    switch (def->type) {
      case VM_METHOD_TYPE_ISEQ:
	return rb_hash_uint(hash, (st_index_t)def->body.iseq);
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
	if (def->body.orig_me) {
	    def = def->body.orig_me->def;
	    goto again;
	}
	else {
	    return hash;
	}
      default:
	rb_bug("rb_hash_method_definition: unsupported method type (%d)\n", def->type);
    }
    return hash;
}

st_index_t
rb_hash_method_entry(st_index_t hash, const rb_method_entry_t *me)
{
    return rb_hash_method_definition(hash, me->def);
}

void
rb_alias(VALUE klass, ID name, ID def)
{
    VALUE target_klass = klass;
    VALUE defined_class;
    rb_method_entry_t *orig_me;
    rb_method_flag_t flag = NOEX_UNDEF;

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class to make alias");
    }

    rb_frozen_class_p(klass);

  again:
    orig_me = search_method(klass, def, &defined_class);

    if (UNDEFINED_METHOD_ENTRY_P(orig_me)) {
	if ((!RB_TYPE_P(klass, T_MODULE)) ||
	    (orig_me = search_method(rb_cObject, def, 0),
	     UNDEFINED_METHOD_ENTRY_P(orig_me))) {
	    rb_print_undef(klass, def, 0);
	}
    }
    if (orig_me->def->type == VM_METHOD_TYPE_ZSUPER) {
	klass = RCLASS_SUPER(klass);
	def = orig_me->def->original_id;
	flag = orig_me->flag;
	goto again;
    }
    if (RB_TYPE_P(defined_class, T_ICLASS)) {
	VALUE real_class = RBASIC_CLASS(defined_class);
	if (real_class && RCLASS_ORIGIN(real_class) == defined_class)
	    defined_class = real_class;
    }

    if (flag == NOEX_UNDEF) flag = orig_me->flag;
    method_entry_set(target_klass, name, orig_me, flag, defined_class);
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
set_method_visibility(VALUE self, int argc, VALUE *argv, rb_method_flag_t ex)
{
    int i;

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
	rb_export_method(self, id, ex);
    }
}

static VALUE
set_visibility(int argc, VALUE *argv, VALUE module, rb_method_flag_t ex)
{
    if (argc == 0) {
	SCOPE_SET(ex);
    }
    else {
	set_method_visibility(module, argc, argv, ex);
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
    return set_visibility(argc, argv, module, NOEX_PUBLIC);
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
    return set_visibility(argc, argv, module, NOEX_PROTECTED);
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
    return set_visibility(argc, argv, module, NOEX_PRIVATE);
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
    set_method_visibility(rb_singleton_class(obj), argc, argv, NOEX_PUBLIC);
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
    set_method_visibility(rb_singleton_class(obj), argc, argv, NOEX_PRIVATE);
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
	SCOPE_SET(NOEX_MODFUNC);
	return module;
    }

    set_method_visibility(module, argc, argv, NOEX_PRIVATE);

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
	rb_method_entry_set(rb_singleton_class(module), id, me, NOEX_PUBLIC);
    }
    return module;
}

int
rb_method_basic_definition_p(VALUE klass, ID id)
{
    const rb_method_entry_t *me = rb_method_entry(klass, id, 0);
    if (me && (me->flag & NOEX_BASIC))
	return 1;
    return 0;
}

static inline int
basic_obj_respond_to(VALUE obj, ID id, int pub)
{
    VALUE klass = CLASS_OF(obj);
    VALUE args[2];

    switch (rb_method_boundp(klass, id, pub|NOEX_RESPONDS)) {
      case 2:
	return FALSE;
      case 0:
	args[0] = ID2SYM(id);
	args[1] = pub ? Qfalse : Qtrue;
	return RTEST(rb_funcall2(obj, idRespond_to_missing, 2, args));
      default:
	return TRUE;
    }
}

int
rb_obj_respond_to(VALUE obj, ID id, int priv)
{
    VALUE klass = CLASS_OF(obj);

    if (rb_method_basic_definition_p(klass, idRespond_to)) {
	return basic_obj_respond_to(obj, id, !RTEST(priv));
    }
    else {
	int argc = 1;
	VALUE args[2];
	args[0] = ID2SYM(id);
	args[1] = Qtrue;
	if (priv) {
	    if (rb_obj_method_arity(obj, idRespond_to) != 1) {
		argc = 2;
	    }
	    else if (!NIL_P(ruby_verbose)) {
		VALUE klass = CLASS_OF(obj);
		VALUE location = rb_mod_method_location(klass, idRespond_to);
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
	return RTEST(rb_funcall2(obj, idRespond_to, argc,  args));
    }
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

    rb_scan_args(argc, argv, "11", &mid, &priv);
    if (!(id = rb_check_id(&mid))) {
	if (!rb_method_basic_definition_p(CLASS_OF(obj), idRespond_to_missing)) {
	    VALUE args[2];
	    args[0] = ID2SYM(rb_to_id(mid));
	    args[1] = priv;
	    return rb_funcall2(obj, idRespond_to_missing, 2, args);
	}
	return Qfalse;
    }
    if (basic_obj_respond_to(obj, id, !RTEST(priv)))
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
#define REPLICATE_METHOD(klass, id, noex) \
	rb_method_entry_set((klass), (id), \
			    rb_method_entry((klass), (id), 0), \
			    (rb_method_flag_t)(noex | NOEX_BASIC | NOEX_NOREDEF))
	REPLICATE_METHOD(rb_eException, idMethodMissing, NOEX_PRIVATE);
	REPLICATE_METHOD(rb_eException, idRespond_to, NOEX_PUBLIC);
	REPLICATE_METHOD(rb_eException, idRespond_to_missing, NOEX_PUBLIC);
    }
}
