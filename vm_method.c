/*
 * This file is included by vm.c
 */

#define CACHE_SIZE 0x800
#define CACHE_MASK 0x7ff
#define EXPR1(c,m) ((((c)>>3)^(m))&CACHE_MASK)

/*****************************************************************************/
/* RENAME SECTION: change names initially only for this file */
/* TD: apply renames within method.h and source-code-wide, then remove those
       defines (or keep as a rename-legend) */

#define mdef_t			rb_method_definition_t
#define ment_t			rb_method_entry_t
#define mtyp_t			rb_method_type_t
#define mflg_t			rb_method_flag_t

#define ment_sweep		rb_sweep_method_entry
#define ment_free		rb_free_method_entry
#define ment_eq			rb_method_entry_eq

#define class_ment_make		rb_ment_make
#define class_method_add	rb_add_method
#define class_method_add_cfunc  rb_add_method_cfunc
#define class_ment_set		rb_method_entry_set

#define class_ment		rb_method_entry
#define class_ment_uncached	rb_method_entry_get_without_cache
#define class_ment_search	search_method

#define allocator_define	rb_define_alloc_func
#define allocator_undef		rb_undef_alloc_func
#define allocator_get		rb_get_alloc_func

#define unlinked_ment_entry	unlinked_method_entry_list_entry

/* END RENAME SECTION */
/*****************************************************************************/

static void rb_vm_check_redefinition_opt_method(const ment_t *me);

static ID object_id, respond_to_missing;
static ID removed, singleton_removed, undefined, singleton_undefined;
static ID added, singleton_added, attached;

/*****************************************************************************/
/*  METHOD ENTRY CACHE                                                       */
/*****************************************************************************/

struct cache_entry {		/* method hash table. */
    VALUE filled_version;        /* filled state version */
    ID mid;			/* method's id */
    VALUE klass;		/* receiver's class */
    ment_t *me;
};

static struct cache_entry cache[CACHE_SIZE];
#define ruby_running (GET_VM()->running)
/* int ruby_running = 0; */

static void
vm_clear_global_method_cache(void)
{
    struct cache_entry *ent, *end;

    ent = cache;
    end = ent + CACHE_SIZE;
    while (ent < end) {
	ent->filled_version = 0;
	ent++;
    }
}

void
rb_clear_cache(void)
{
    rb_vm_change_state();
}

static void
rb_clear_cache_for_undef(VALUE klass, ID mid)
{
    rb_vm_change_state();
}

static void
rb_clear_cache_by_id(ID mid)
{
    rb_vm_change_state();
}

void
rb_clear_cache_by_class(VALUE klass)
{
    rb_vm_change_state();
}

/*****************************************************************************/
/*  SPECIAL METHODS                                                          */
/*****************************************************************************/

VALUE
rb_f_notimplement(int argc, VALUE *argv, VALUE obj)
{
    rb_notimplement();
}

static void
rb_define_notimplement_method_id(VALUE mod, ID mid, mflg_t noex)
{
    class_method_add(mod, mid, VM_METHOD_TYPE_NOTIMPLEMENTED, 0, noex);
}

/*****************************************************************************/
/*  DIVERSE FUNCTIONS                                                        */
/*****************************************************************************/

#undef rb_disable_super
#undef rb_enable_super

void
rb_disable_super(VALUE klass, const char *name)
{
    rb_warning("rb_disable_super() is obsolete");
}

void
rb_enable_super(VALUE klass, const char *name)
{
    rb_warning("rb_enable_super() is obsolete");
}

/*****************************************************************************/
/*  ALLOCATOR FUNCTIONS                                                      */
/*****************************************************************************/

void
allocator_define(VALUE klass, VALUE (*func)(VALUE))
{
/*  defines the allocation method for a class */

    Check_Type(klass, T_CLASS);
    class_method_add_cfunc(rb_singleton_class(klass), ID_ALLOCATOR,
			func, 0, NOEX_PRIVATE);
}

void
allocator_undef(VALUE klass)
{
/*  un-defines the allocation method for a class */

    Check_Type(klass, T_CLASS);
    class_method_add(rb_singleton_class(klass), ID_ALLOCATOR, VM_METHOD_TYPE_UNDEF, 0, NOEX_UNDEF);
}

rb_alloc_func_t
allocator_get(VALUE klass)
{
/*  returns the allocation method for a class */

    ment_t *me;
    Check_Type(klass, T_CLASS);
    me = class_ment(CLASS_OF(klass), ID_ALLOCATOR);

    if (me && me->def && me->def->type == VM_METHOD_TYPE_CFUNC) {
	return (rb_alloc_func_t)me->def->body.cfunc.func;
    }
    else {
	return 0;
    }
}

static inline ID
allocator_deprication(VALUE klass, ID mid, mtyp_t type)
{
/* checks for definition of allocate, returns altered mid after warning */

    if (FL_TEST(klass, FL_SINGLETON) &&
	type == VM_METHOD_TYPE_CFUNC &&
	mid == rb_intern("allocate")) {
	/* issue: use rb_warning to honor -v */
	rb_warn("defining %s.allocate is deprecated; use allocator_define()",
		rb_class2name(rb_ivar_get(klass, attached)));
	mid = ID_ALLOCATOR;
    }

    return mid;
}

/*****************************************************************************/
/*  MDEF - METHOD DEFINITION                                                 */
/*****************************************************************************/

static void
mdef_init_as_attr(mdef_t *def, void *opts)
{
/* processing for mdef_new, method type ATTRSET/IVAR */
  
    rb_thread_t *th;
    rb_control_frame_t *cfp;
    int line;
    
    def->body.attr.id = (ID)opts;
    def->body.attr.location = Qfalse;
    th = GET_THREAD();
    cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);
    if (cfp && (line = rb_vm_get_sourceline(cfp))) {
	VALUE location = rb_ary_new3(2, cfp->iseq->filename, INT2FIX(line));
	def->body.attr.location = rb_ary_freeze(location);
    }
}

mdef_t *
mdef_new(ID mid, mtyp_t type, void *opts)
{
/*  creates a new mdef object (struct)*/

    mdef_t *def = ALLOC(mdef_t);
    def->type = type;
    def->original_id = mid;
    def->alias_count = 0;

    switch (type) {
      case VM_METHOD_TYPE_ISEQ:
	def->body.iseq = (rb_iseq_t *)opts;
	break;
      case VM_METHOD_TYPE_CFUNC:
	def->body.cfunc = *(rb_method_cfunc_t *)opts;
	break;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
        mdef_init_as_attr(def, opts);
	break;
      case VM_METHOD_TYPE_BMETHOD:
	def->body.proc = (VALUE)opts;
	break;
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
	def->body.cfunc.func = rb_f_notimplement;
	def->body.cfunc.argc = -1;
	break;
      case VM_METHOD_TYPE_OPTIMIZED:
	def->body.optimize_type = (enum method_optimized_type)opts;
	break;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_UNDEF:
	break;
      default:
	rb_bug("class_method_add: unsupported method type (%d)\n", type);
    }
    return def;
}

static int
mdef_eq(const mdef_t *d1, const mdef_t *d2)
{
/*  determines if two mdef are equal */

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

/*****************************************************************************/
/*  MENT - METHOD ENTRY                                                      */
/*****************************************************************************/

static ment_t *
ment_new(ID mid, mdef_t *def, mflg_t noex)
{
/*  creates a new ment object (struct) */

    ment_t *me = ALLOC(ment_t);

    me->flag = NOEX_WITH_SAFE(noex);
    me->mark = 0;
    me->called_id = mid;
    me->klass = 0; /* not yet assigned to a class */
    me->def = def;
    if (def) def->alias_count++;

    return me;
}

static void
ment_unlink(ment_t *me)
{
/*  places an unused ment into the unlinked-list */
/*  TD: verify, possibly rename to "unused_ment_list" */

    struct unlinked_ment_entry *ume;
    ume = ALLOC(struct unlinked_ment_entry);
    ume->me = me;
    ume->next = GET_VM()->unlinked_method_entry_list;
    GET_VM()->unlinked_method_entry_list = ume;
}

void
ment_sweep(void *pvm)
{
/*  frees (deletes permanently) all unused(unlinked) ment */

    rb_vm_t *vm = pvm;
    struct unlinked_ment_entry *ume = vm->unlinked_method_entry_list, *prev_ume = 0, *curr_ume;

    /* TD: document, possibly refactor */
    while (ume) {
	if (ume->me->mark) {
	    ume->me->mark = 0;
	    prev_ume = ume;
	    ume = ume->next;
	}
	else {
	    ment_free(ume->me);

	    if (prev_ume == 0) {
		vm->unlinked_method_entry_list = ume->next;
	    }
	    else {
		prev_ume->next = ume->next;
	    }

	    curr_ume = ume;
	    ume = ume->next;
	    xfree(curr_ume);
	}
    }
}

void
ment_free(ment_t *me)
{
/*  frees the memory of a method entry, deleting it permanently */

    mdef_t *def = me->def;

    if (def) {
	if (def->alias_count == 0) {
	    xfree(def);
	}
	else if (def->alias_count > 0) {
	    def->alias_count--;
	}
	me->def = 0;
    }
    xfree(me);
}

int
ment_eq(const ment_t *m1, const ment_t *m2)
{
/*  determine if two ment are equal */

    return mdef_eq(m1->def, m2->def);
}

static int
ment_has_mdef(ment_t *me, mdef_t *def)
{
/*  tests if ment has the given mdef */

    if (!me) return FALSE;
    
    return mdef_eq(me->def, def) ? TRUE : FALSE;
}

/*****************************************************************************/
/*  METHOD DEFINITION AND ENTRY CREATION                                     */
/*****************************************************************************/

/* TD: refactor to code, leave only "hook_id = singleton_##hook;" as a macro */
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

static ment_t *
class_ment_get(VALUE klass, ID mid)
{
/*  gets the ment by mid. Does *not* do a lookup in the class hierarchy */

    ment_t *me = 0;
    st_lookup(RCLASS_M_TBL(klass), mid, (st_data_t*)me);
    return me;
}

static ment_t *
class_ment_add(VALUE klass, ment_t *me)
{
/*  adds a ment to a class, without check if it's already exists */

    mtyp_t type = me->def->type;
    ID mid = me->called_id;

    /* set initialize or initialize_copy to private */
    if (!FL_TEST(klass, FL_SINGLETON) &&
	type != VM_METHOD_TYPE_NOTIMPLEMENTED &&
	type != VM_METHOD_TYPE_ZSUPER &&
	(mid == rb_intern("initialize") || mid == rb_intern("initialize_copy"))) {
	me->flag = NOEX_PRIVATE | me->flag;
    }

    rb_clear_cache_by_id(mid);

    me->klass = klass;
    st_insert(RCLASS_M_TBL(klass), mid, (st_data_t) me);

    if (type != VM_METHOD_TYPE_UNDEF && mid != ID_ALLOCATOR && ruby_running) {
	CALL_METHOD_HOOK(klass, added, mid);
    }
    return me;
}

static ment_t *
class_mdef_add(VALUE klass, ID mid, mdef_t *def, mflg_t noex )
{
/*  adds a mdef to a class, without check if it's already exists */
    
    return class_ment_add(klass, ment_new(mid, def, noex));
}

static ment_t *
class_ment_redefine(VALUE klass, ID mid, mtyp_t type, mdef_t *def, mflg_t noex)
{
/*  processing subjecting method redefinition */

    ment_t *old_me = class_ment_get(klass, mid, &old_me);
    mdef_t *old_def = old_me->def;

    rb_vm_check_redefinition_opt_method(old_me);

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
	if (iseq && !NIL_P(iseq->filename)) {
	    int line = iseq->insn_info_table ? rb_iseq_first_lineno(iseq) : 0;
	    rb_compile_warning(RSTRING_PTR(iseq->filename), line,
			       "previous definition of %s was here",
			       rb_id2name(old_def->original_id));
	}
    }

    if (klass == rb_cObject && mid == idInitialize) {
	/* issue: use rb_warning to honor -v */
	rb_warn("redefining Object#initialize may cause infinite loop");
    }

    if (mid == object_id || mid == id__send__) {
	if (type == VM_METHOD_TYPE_ISEQ) {
	    /* issue: use rb_warning to honor -v */
	    rb_warn("redefining `%s' may cause serious problems", rb_id2name(mid));
	}
    }

    ment_unlink(old_me);
    
    return class_mdef_add(klass, mid, def, noex);

}

static ment_t *
class_ment_make(VALUE klass, ID mid, mtyp_t type, mdef_t *def, mflg_t noex)
{
/*  retrieves the ment for the given mdef from the klass
    creates new ment if not available */

    ment_t *me, *old_me;

    if (NIL_P(klass)) {
	klass = rb_cObject;
    }

    mid = allocator_deprication(klass, mid, type);

    /* issue: possibly after "return old_me", as frozen has no relevance if
              existent ment is returned */
    rb_check_frozen(klass);

    old_me = class_ment_get(klass, mid, &old_me); 
    if (old_me && ment_has_mdef(old_me, def))
	return old_me;

    /* definition or redefinition */

    if (rb_safe_level() >= 4 &&
	(klass == rb_cObject || !OBJ_UNTRUSTED(klass))) {
	rb_raise(rb_eSecurityError, "Insecure: can't define method");
    }

    if (old_me)
        return class_ment_redefine(klass, mid, type, def, noex);	    

    return class_mdef_add(klass, mid, def, noex);
}

ment_t *
class_method_add(VALUE klass, ID mid, mtyp_t type, void *opts, mflg_t noex)
{
/*  adds a newly created mdef via a newly created me to a class */

    mdef_t *def = mdef_new(mid, type, opts);
    ment_t *me = class_ment_make(klass, mid, type, def, noex);
    return me;
}

ment_t *
class_ment_set(VALUE klass, ID mid, const ment_t *me, mflg_t noex)
{
/*  adds the me->def via newly created newme to a class */

/*  TD: possibly rename to "class_ment_copy" */
/*  TD: possibly move setting of "VM_METHOD_TYPE_UNDEF" int _metn_make */

    mtyp_t type = me->def ? me->def->type : VM_METHOD_TYPE_UNDEF;
    ment_t *newme = class_ment_make(klass, mid, type, me->def, noex);    
    return newme;
}

void
class_method_add_cfunc(VALUE klass, ID mid, VALUE (*func)(ANYARGS), int argc, mflg_t noex)
{
/*  specialized version of class_method_add - for C functions */

/*  issue: should possibly return me */

/*  TD: notimplemented logic belongs possibly in class_method_add or mdef_new,
    new function "ment_init_notimplemented" */

    if (func != rb_f_notimplement) {
	rb_method_cfunc_t opt;
	opt.func = func;
	opt.argc = argc;
	class_method_add(klass, mid, VM_METHOD_TYPE_CFUNC, &opt, noex);
    }
    else {
	rb_define_notimplement_method_id(klass, mid, noex);
    }
}

static ment_t*
class_ment_search(VALUE klass, ID mid)
{
/* searches for a ment in the class's inheritance chain */
/* issue: st_lookup does *not* a lookup, possibly rename to "get") */

    st_data_t body;
    if (!klass) {
	return 0;
    }
    /* TD: refactor to while(klass), remove above if */
    while (!st_lookup(RCLASS_M_TBL(klass), mid, &body)) {
	klass = RCLASS_SUPER(klass);
	if (!klass) {
	    return 0;
	}
    }

    return (ment_t *)body;
}

/*
 * search method entry without the method cache.
 *
 * if you need method entry with method cache (normal case), use
 * class_ment() simply.
 */
ment_t *
class_ment_uncached(VALUE klass, ID mid)
{
    ment_t *me = class_ment_search(klass, mid);

/*  TD: document this code */
    if (ruby_running) {
	struct cache_entry *ent;
	ent = cache + EXPR1(klass, mid);
	ent->filled_version = GET_VM_STATE_VERSION();
	ent->klass = klass;

	if (UNDEFINED_METHOD_ENTRY_P(me)) {
	    ent->mid = mid;
	    ent->me = 0;
	    me = 0;
	}
	else {
	    ent->mid = mid;
	    ent->me = me;
	}
    }

    return me;
}

ment_t *
class_ment(VALUE klass, ID mid)
{
/*  retrieves the ment from a given class. looks in mcache first */

    struct cache_entry *ent;

    ent = cache + EXPR1(klass, mid);
    if (ent->filled_version == GET_VM_STATE_VERSION() &&
	ent->mid == mid && ent->klass == klass) {
	return ent->me;
    }

    return class_ment_uncached(klass, mid);
}

#define VISI_CHECK(x,f) (((x)&NOEX_MASK) == (f))
/* TD: verify, macro seems redundant. code directly. */

static VALUE
class_ment_flagtest(VALUE klass, ID mid, mflg_t noex)
{
/*  ??? tests the flag of a modules ment */

    const ment_t *me = class_ment(klass, mid);
    if (me && VISI_CHECK(me->flag, noex)) {
	return Qtrue;
    }
    return Qfalse;
}

/*****************************************************************************/
/*  RUBY LEVEL METHODS                                                       */
/*****************************************************************************/

void
rb_attr(VALUE klass, ID mid, int read, int write, int ex)
{
    const char *name;
    ID attriv;
    VALUE aname;
    mflg_t noex;

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

    if (!rb_is_local_id(mid) && !rb_is_const_id(mid)) {
	rb_name_error(mid, "invalid attribute name `%s'", rb_id2name(mid));
    }
    name = rb_id2name(mid);
    if (!name) {
	rb_raise(rb_eArgError, "argument needs to be symbol or string");
    }
    aname = rb_sprintf("@%s", name);
    rb_enc_copy(aname, rb_id2str(mid));
    attriv = rb_intern_str(aname);
    if (read) {
	class_method_add(klass, mid, VM_METHOD_TYPE_IVAR, (void *)attriv, noex);
    }
    if (write) {
	class_method_add(klass, rb_id_attrset(mid), VM_METHOD_TYPE_ATTRSET, (void *)attriv, noex);
    }
}

/* rb_attr called from class.c */

/*----------*/

static void
remove_method(VALUE klass, ID mid)
{
    st_data_t key, data;
    rb_method_entry_t *me = 0;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't remove method");
    }
    rb_check_frozen(klass);
    if (mid == object_id || mid == id__send__ || mid == idInitialize) {
	/* issue: use rb_warning to honor -v */
	rb_warn("removing `%s' may cause serious problems", rb_id2name(mid));
    }

    if (!st_lookup(RCLASS_M_TBL(klass), mid, &data) ||
	!(me = (ment_t *)data) ||
	(!me->def || me->def->type == VM_METHOD_TYPE_UNDEF)) {
	rb_name_error(mid, "method `%s' not defined in %s",
		      rb_id2name(mid), rb_class2name(klass));
    }
    key = (st_data_t)mid;
    st_delete(RCLASS_M_TBL(klass), &key, &data);

    rb_vm_check_redefinition_opt_method(me);
    rb_clear_cache_for_undef(klass, mid);
    ment_unlink(me);

    CALL_METHOD_HOOK(klass, removed, mid);
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
 *
 *  Removes the method identified by _symbol_ from the current
 *  class. For an example, see <code>Module.undef_method</code>.
 */

static VALUE
rb_mod_remove_method(int argc, VALUE *argv, VALUE mod)
{
    int i;

    for (i = 0; i < argc; i++) {
	remove_method(mod, rb_to_id(argv[i]));
    }
    return mod;
}

/*----------*/

void
rb_undef(VALUE klass, ID mid)
{
    ment_t *me;

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class to undef method");
    }
    if (rb_vm_cbase() == rb_cObject && klass == rb_cObject) {
	rb_secure(4);
    }
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't undef `%s'", rb_id2name(mid));
    }
    rb_frozen_class_p(klass);
    if (mid == object_id || mid == id__send__ || mid == idInitialize) {
	rb_warn("undefining `%s' may cause serious problems", rb_id2name(mid));
    }

    me = class_ment_search(klass, mid);

    if (UNDEFINED_METHOD_ENTRY_P(me)) {
	const char *s0 = " class";
	VALUE c = klass;

	if (FL_TEST(c, FL_SINGLETON)) {
	    VALUE obj = rb_ivar_get(klass, attached);

	    switch (TYPE(obj)) {
	      case T_MODULE:
	      case T_CLASS:
		c = obj;
		s0 = "";
	    }
	}
	else if (TYPE(c) == T_MODULE) {
	    s0 = " module";
	}
	rb_name_error(mid, "undefined method `%s' for%s `%s'",
		      rb_id2name(mid), s0, rb_class2name(c));
    }

    class_method_add(klass, mid, VM_METHOD_TYPE_UNDEF, 0, NOEX_PUBLIC);

    CALL_METHOD_HOOK(klass, undefined, mid);
}

/*
 *  call-seq:
 *     undef_method(symbol)    -> self
 *
 *  Prevents the current class from responding to calls to the named
 *  method. Contrast this with <code>remove_method</code>, which deletes
 *  the method from the particular class; Ruby will still search
 *  superclasses and mixed-in modules for a possible receiver.
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
	rb_undef(mod, rb_to_id(argv[i]));
    }
    return mod;
}

/*----------*/

int
rb_method_boundp(VALUE klass, ID mid, int ex)
{
    ment_t *me = class_ment(klass, mid);

    if (me != 0) {
	if ((ex & ~NOEX_RESPONDS) && (me->flag & NOEX_PRIVATE)) {
	    return FALSE;
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

/*
 *  call-seq:
 *     mod.method_defined?(symbol)    -> true or false
 *
 *  Returns +true+ if the named method is defined by
 *  _mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors). Public and protected methods are matched.
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
    ID id = rb_check_id(mid);
    if (!id || !rb_method_boundp(mod, id, 1)) {
	return Qfalse;
    }
    return Qtrue;

}

/*
 *  call-seq:
 *     mod.public_method_defined?(symbol)   -> true or false
 *
 *  Returns +true+ if the named public method is defined by
 *  _mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors).
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
    ID id = rb_check_id(mid);
    if (!id) return Qfalse;
    return class_ment_flagtest(mod, id, NOEX_PUBLIC);
}

/*
 *  call-seq:
 *     mod.private_method_defined?(symbol)    -> true or false
 *
 *  Returns +true+ if the named private method is defined by
 *  _ mod_ (or its included modules and, if _mod_ is a class,
 *  its ancestors).
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
    ID id = rb_check_id(mid);
    if (!id) return Qfalse;
    return class_ment_flagtest(mod, id, NOEX_PRIVATE);
}

/*
 *  call-seq:
 *     mod.protected_method_defined?(symbol)   -> true or false
 *
 *  Returns +true+ if the named protected method is defined
 *  by _mod_ (or its included modules and, if _mod_ is a
 *  class, its ancestors).
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
    ID id = rb_check_id(mid);
    if (!id) return Qfalse;
    return class_ment_flagtest(mod, id, NOEX_PROTECTED);
}

/*----------*/

void
rb_alias(VALUE klass, ID mid_alias, ID mid)
{
    VALUE target_klass = klass;
    ment_t *orig_me;
    mflg_t flag = NOEX_UNDEF;

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class to make alias");
    }

    rb_frozen_class_p(klass);
    if (klass == rb_cObject) {
	rb_secure(4);
    }

  again:
    orig_me = search_method(klass, mid);

    if (UNDEFINED_METHOD_ENTRY_P(orig_me)) {
	if ((TYPE(klass) != T_MODULE) ||
	    (orig_me = class_ment_search(rb_cObject, mid), UNDEFINED_METHOD_ENTRY_P(orig_me))) {
	    rb_print_undef(klass, mid, 0);
	}
    }
    if (orig_me->def->type == VM_METHOD_TYPE_ZSUPER) {
	klass = RCLASS_SUPER(klass);
	mid = orig_me->def->original_id;
	flag = orig_me->flag;
	goto again;
    }

    if (flag == NOEX_UNDEF) flag = orig_me->flag;
    class_ment_set(target_klass, mid_alias, orig_me, flag);
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
    rb_alias(mod, rb_to_id(newname), rb_to_id(oldname));
    return mod;
}

/*----------*/

static void
secure_visibility(VALUE self)
{
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(self)) {
	rb_raise(rb_eSecurityError,
		 "Insecure: can't change method visibility");
    }
}

static void
rb_export_method(VALUE klass, ID mid, mflg_t noex)
{
    ment_t *me;

    if (klass == rb_cObject) {
	rb_secure(4);
    }

    me = class_ment_search(klass, mid);
    if (!me && TYPE(klass) == T_MODULE) {
	me = class_ment_search(rb_cObject, mid);
    }

    if (UNDEFINED_METHOD_ENTRY_P(me)) {
	rb_print_undef(klass, mid, 0);
    }

    if (me->flag != noex) {
	rb_vm_check_redefinition_opt_method(me);

	if (klass == me->klass) {
	    me->flag = noex;
	}
	else {
	    class_method_add(klass, mid, VM_METHOD_TYPE_ZSUPER, 0, noex);
	}
    }
}

static void
set_method_visibility(VALUE self, int argc, VALUE *argv, mflg_t ex)
{
    int i;
    secure_visibility(self);
    for (i = 0; i < argc; i++) {
	rb_export_method(self, rb_to_id(argv[i]), ex);
    }
    rb_clear_cache_by_class(self);
}

/*
 *  call-seq:
 *     public                 -> self
 *     public(symbol, ...)    -> self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 */

static VALUE
rb_mod_public(int argc, VALUE *argv, VALUE module)
{
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(NOEX_PUBLIC);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PUBLIC);
    }
    return module;
}

/*
 *  call-seq:
 *     protected                -> self
 *     protected(symbol, ...)   -> self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to protected. With arguments, sets the named methods
 *  to have protected visibility.
 */

static VALUE
rb_mod_protected(int argc, VALUE *argv, VALUE module)
{
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(NOEX_PROTECTED);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PROTECTED);
    }
    return module;
}

/*
 *  call-seq:
 *     private                 -> self
 *     private(symbol, ...)    -> self
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to private. With arguments, sets the named methods
 *  to have private visibility.
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
    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(NOEX_PRIVATE);
    }
    else {
	set_method_visibility(module, argc, argv, NOEX_PRIVATE);
    }
    return module;
}

/*
 *  call-seq:
 *     mod.public_class_method(symbol, ...)    -> mod
 *
 *  Makes a list of existing class methods public.
 */

static VALUE
rb_mod_public_method(int argc, VALUE *argv, VALUE obj)
{
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PUBLIC);
    return obj;
}

/*
 *  call-seq:
 *     mod.private_class_method(symbol, ...)   -> mod
 *
 *  Makes existing class methods private. Often used to hide the default
 *  constructor <code>new</code>.
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
    set_method_visibility(CLASS_OF(obj), argc, argv, NOEX_PRIVATE);
    return obj;
}

/*
 *  call-seq:
 *     public
 *     public(symbol, ...)
 *
 *  With no arguments, sets the default visibility for subsequently
 *  defined methods to public. With arguments, sets the named methods to
 *  have public visibility.
 */

static VALUE
top_public(int argc, VALUE *argv)
{
    return rb_mod_public(argc, argv, rb_cObject);
}

static VALUE
top_private(int argc, VALUE *argv)
{
    return rb_mod_private(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     module_function(symbol, ...)    -> self
 *
 *  Creates module functions for the named methods. These functions may
 *  be called with the module as a receiver, and also become available
 *  as instance methods to classes that mix in the module. Module
 *  functions are copies of the original, and so may be changed
 *  independently. The instance-method versions are made private. If
 *  used with no arguments, subsequently defined methods become module
 *  functions.
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
    ID mid;
    const ment_t *me;

    if (TYPE(module) != T_MODULE) {
	rb_raise(rb_eTypeError, "module_function must be called for modules");
    }

    secure_visibility(module);
    if (argc == 0) {
	SCOPE_SET(NOEX_MODFUNC);
	return module;
    }

    set_method_visibility(module, argc, argv, NOEX_PRIVATE);

    for (i = 0; i < argc; i++) {
	VALUE m = module;

	mid = rb_to_id(argv[i]);
	for (;;) {
	    me = class_ment_search(m, mid);
	    if (me == 0) {
		me = class_ment_search(rb_cObject, mid);
	    }
	    if (UNDEFINED_METHOD_ENTRY_P(me)) {
		rb_print_undef(module, mid, 0);
	    }
	    if (me->def->type != VM_METHOD_TYPE_ZSUPER) {
		break; /* normal case: need not to follow 'super' link */
	    }
	    m = RCLASS_SUPER(m);
	    if (!m)
		break;
	}
	class_ment_set(rb_singleton_class(module), mid, me, NOEX_PUBLIC);
    }
    return module;
}

/*----------*/

int
rb_method_basic_definition_p(VALUE klass, ID mid)
{
    const ment_t *me = class_ment(klass, mid);
    if (me && (me->flag & NOEX_BASIC))
	return 1;
    return 0;
}

static inline int
basic_obj_respond_to(VALUE obj, ID mid, int pub)
{
    VALUE klass = CLASS_OF(obj);

    switch (rb_method_boundp(klass, mid, pub|NOEX_RESPONDS)) {
      case 2:
	return FALSE;
      case 0:
	return RTEST(rb_funcall(obj, respond_to_missing, 2, ID2SYM(mid), pub ? Qfalse : Qtrue));
      default:
	return TRUE;
    }
}

int
rb_obj_respond_to(VALUE obj, ID mid, int priv)
{
    VALUE klass = CLASS_OF(obj);

    if (rb_method_basic_definition_p(klass, idRespond_to)) {
	return basic_obj_respond_to(obj, mid, !RTEST(priv));
    }
    else {
	return RTEST(rb_funcall(obj, idRespond_to, priv ? 2 : 1, ID2SYM(mid), Qtrue));
    }
}

int
rb_respond_to(VALUE obj, ID mid)
{
    return rb_obj_respond_to(obj, mid, FALSE);
}


/*
 *  call-seq:
 *     obj.respond_to?(symbol, include_private=false) -> true or false
 *
 *  Returns +true+ if _obj_ responds to the given
 *  method. Private methods are included in the search only if the
 *  optional second parameter evaluates to +true+.
 *
 *  If the method is not implemented,
 *  as Process.fork on Windows, File.lchmod on GNU/Linux, etc.,
 *  false is returned.
 *
 *  If the method is not defined, <code>respond_to_missing?</code>
 *  method is called and the result is returned.
 */

static VALUE
obj_respond_to(int argc, VALUE *argv, VALUE obj)
{
    VALUE mid, priv;
    ID id;

    rb_scan_args(argc, argv, "11", &mid, &priv);
    if (!(id = rb_check_id(mid)))
	return Qfalse;
    if (basic_obj_respond_to(obj, id, !RTEST(priv)))
	return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     obj.respond_to_missing?(symbol, include_private) -> true or false
 *
 *  Hook method to return whether the _obj_ can respond to _id_ method
 *  or not.
 *
 *  See #respond_to?.
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

    rb_define_singleton_method(rb_vm_top_self(), "public", top_public, -1);
    rb_define_singleton_method(rb_vm_top_self(), "private", top_private, -1);

    object_id = rb_intern("object_id");
    added = rb_intern("method_added");
    singleton_added = rb_intern("singleton_method_added");
    removed = rb_intern("method_removed");
    singleton_removed = rb_intern("singleton_method_removed");
    undefined = rb_intern("method_undefined");
    singleton_undefined = rb_intern("singleton_method_undefined");
    attached = rb_intern("__attached__");
    respond_to_missing = rb_intern("respond_to_missing?");
}

/* TD: rename plan

method_entry 		| mentry	| ment	| me
method_definition	| mdefinition	| mdef	| md
method_table		| mtable	| mtbl	| mt
method_id		| midentifier	| mid	| mi

The term "method" refers usually to:
 * A mdef entered via a ment into the mtbl of a class
 * class->mtbl[mid]->mdef

Functions are grouped by the type (structure, object) they affect. Whenever
possible, first parameter is a pointer to such type. Examples:

rb_mtbl_ = functions affecting a method table
rb_ment_ = functions affecting a method entry 
rb_mtbl_<function> e.g. rb_mtbl_add(mtbl_t *mtbl, )
rb_mdef_<function> e.g. rb_mdef_new

*/
