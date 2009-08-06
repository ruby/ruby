/*
 * This file is included by vm.h
 */

#define CACHE_SIZE 0x800
#define CACHE_MASK 0x7ff
#define EXPR1(c,m) ((((c)>>3)^(m))&CACHE_MASK)

static void rb_vm_check_redefinition_opt_method(const rb_method_entry_t *me);

static ID object_id;
static ID removed, singleton_removed, undefined, singleton_undefined;
static ID added, singleton_added;

struct cache_entry {		/* method hash table. */
    ID mid;			/* method's id */
    VALUE klass;		/* receiver's class */
    rb_method_entry_t *me;
};

static struct cache_entry cache[CACHE_SIZE];
#define ruby_running (GET_VM()->running)
/* int ruby_running = 0; */

void
rb_clear_cache(void)
{
    struct cache_entry *ent, *end;

    rb_vm_change_state();

    if (!ruby_running)
	return;
    ent = cache;
    end = ent + CACHE_SIZE;
    while (ent < end) {
	ent->me = 0;
	ent->mid = 0;
	ent++;
    }
}

static void
rb_clear_cache_for_undef(VALUE klass, ID id)
{
    struct cache_entry *ent, *end;

    rb_vm_change_state();

    if (!ruby_running)
	return;
    ent = cache;
    end = ent + CACHE_SIZE;
    while (ent < end) {
	if ((ent->me && ent->me->klass == klass) && ent->mid == id) {
	    ent->me = 0;
	    ent->mid = 0;
	}
	ent++;
    }
}

static void
rb_clear_cache_by_id(ID id)
{
    struct cache_entry *ent, *end;

    rb_vm_change_state();

    if (!ruby_running)
	return;
    ent = cache;
    end = ent + CACHE_SIZE;
    while (ent < end) {
	if (ent->mid == id) {
	    ent->me = 0;
	    ent->mid = 0;
	}
	ent++;
    }
}

void
rb_clear_cache_by_class(VALUE klass)
{
    struct cache_entry *ent, *end;

    rb_vm_change_state();

    if (!ruby_running)
	return;
    ent = cache;
    end = ent + CACHE_SIZE;
    while (ent < end) {
	if (ent->klass == klass || (ent->me && ent->me->klass == klass)) {
	    ent->me = 0;
	    ent->mid = 0;
	}
	ent++;
    }
}

VALUE rb_f_notimplement(int argc, VALUE *argv, VALUE obj)
{
    rb_notimplement();
}

static void rb_define_notimplement_method_id(VALUE mod, ID id, rb_method_flag_t noex)
{
    rb_add_method(mod, id, VM_METHOD_TYPE_NOTIMPLEMENTED, 0, noex);
}

void
rb_add_method_cfunc(VALUE klass, ID mid, VALUE (*func)(ANYARGS), int argc, rb_method_flag_t noex)
{
    if (func != rb_f_notimplement) {
	rb_method_cfunc_t opt = {
	    func, argc,
	};
	rb_add_method(klass, mid, VM_METHOD_TYPE_CFUNC, &opt, noex);
    }
    else {
	rb_define_notimplement_method_id(klass, mid, noex);
    }
}

rb_method_entry_t *
rb_add_method(VALUE klass, ID mid, rb_method_type_t type, void *opts, rb_method_flag_t noex)
{
    rb_method_entry_t *me;
    st_table *mtbl;
    st_data_t data;

    if (NIL_P(klass)) {
	klass = rb_cObject;
    }
    if (rb_safe_level() >= 4 &&
       	(klass == rb_cObject || !OBJ_UNTRUSTED(klass))) {
	rb_raise(rb_eSecurityError, "Insecure: can't define method");
    }
    if (!FL_TEST(klass, FL_SINGLETON) &&
	type != VM_METHOD_TYPE_NOTIMPLEMENTED &&
	type != VM_METHOD_TYPE_ZSUPER &&
	(mid == rb_intern("initialize") || mid == rb_intern("initialize_copy"))) {
	noex = NOEX_PRIVATE | noex;
    }
    else if (FL_TEST(klass, FL_SINGLETON) &&
	     type == VM_METHOD_TYPE_CFUNC &&
	     mid == rb_intern("allocate")) {
	rb_warn("defining %s.allocate is deprecated; use rb_define_alloc_func()",
		rb_class2name(rb_iv_get(klass, "__attached__")));
	mid = ID_ALLOCATOR;
    }
    if (OBJ_FROZEN(klass)) {
	rb_error_frozen("class/module");
    }
    rb_clear_cache_by_id(mid);

    me = ALLOC(rb_method_entry_t);
    me->type = type;
    me->original_id = me->called_id = mid;
    me->klass = klass;
    me->flag = NOEX_WITH_SAFE(noex);
    me->alias_count = 0;

    switch (type) {
      case VM_METHOD_TYPE_ISEQ:
	me->body.iseq = (rb_iseq_t *)opts;
	break;
      case VM_METHOD_TYPE_CFUNC:
	me->body.cfunc = *(rb_method_cfunc_t *)opts;
	break;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	me->body.attr_id = (ID)opts;
	break;
      case VM_METHOD_TYPE_BMETHOD:
	me->body.proc = (VALUE)opts;
	break;
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
	me->body.cfunc.func = rb_f_notimplement;
	me->body.cfunc.argc = -1;
	break;
      case VM_METHOD_TYPE_OPTIMIZED:
	me->body.optimize_type = (enum method_optimized_type)opts;
	break;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_UNDEF:
	break;
      default:
	rb_bug("rb_add_method: unsupported method type (%d)\n", type);
    }

    mtbl = RCLASS_M_TBL(klass);

    /* check re-definition */
    if (st_lookup(mtbl, mid, &data)) {
	rb_method_entry_t *old_me = (rb_method_entry_t *)data;
	rb_vm_check_redefinition_opt_method(old_me);

	if (RTEST(ruby_verbose) &&
	    old_me->alias_count == 0 &&
	    old_me->type != VM_METHOD_TYPE_UNDEF) {
	    rb_warning("method redefined; discarding old %s", rb_id2name(mid));
	}
#if defined(__cplusplus) || (__STDC_VERSION__ >= 199901L)
	// TODO: free old_me
#endif
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

    st_insert(mtbl, mid, (st_data_t) me);

    if (mid != ID_ALLOCATOR && ruby_running) {
	if (FL_TEST(klass, FL_SINGLETON)) {
	    rb_funcall(rb_iv_get(klass, "__attached__"), singleton_added, 1, ID2SYM(mid));
	}
	else {
	    rb_funcall(klass, added, 1, ID2SYM(mid));
	}
    }

    return me;
}

void
rb_define_alloc_func(VALUE klass, VALUE (*func)(VALUE))
{
    Check_Type(klass, T_CLASS);
    rb_add_method_cfunc(rb_singleton_class(klass), ID_ALLOCATOR,
			func, 0, NOEX_PRIVATE);
}

void
rb_undef_alloc_func(VALUE klass)
{
    Check_Type(klass, T_CLASS);
    rb_add_method(rb_singleton_class(klass), ID_ALLOCATOR, VM_METHOD_TYPE_UNDEF, 0, NOEX_UNDEF);
}

rb_alloc_func_t
rb_get_alloc_func(VALUE klass)
{
    rb_method_entry_t *me;
    Check_Type(klass, T_CLASS);
    me = rb_method_entry(CLASS_OF(klass), ID_ALLOCATOR);

    if (me && me->type == VM_METHOD_TYPE_CFUNC) {
	return (rb_alloc_func_t)me->body.cfunc.func;
    }
    else {
	return 0;
    }
}

static rb_method_entry_t*
search_method(VALUE klass, ID id)
{
    st_data_t body;
    if (!klass) {
	return 0;
    }

    while (!st_lookup(RCLASS_M_TBL(klass), id, &body)) {
	klass = RCLASS_SUPER(klass);
	if (!klass) {
	    return 0;
	}
    }

    return (rb_method_entry_t *)body;
}

/*
 * search method entry without method cache.
 *
 * if you need method entry with method cache, use
 * rb_method_entry()
 */
rb_method_entry_t *
rb_get_method_entry(VALUE klass, ID id)
{
    rb_method_entry_t *me = search_method(klass, id);

    if (ruby_running) {
	struct cache_entry *ent;
	ent = cache + EXPR1(klass, id);
	ent->klass = klass;

	if (!me || me->type == VM_METHOD_TYPE_UNDEF) {
	    ent->mid = id;
	    ent->me = 0;
	    me = 0;
	}
	else {
	    ent->mid = id;
	    ent->me = me;
	}
    }

    return me;
}

rb_method_entry_t *
rb_method_entry(VALUE klass, ID id)
{
    struct cache_entry *ent;

    ent = cache + EXPR1(klass, id);
    if (ent->mid == id && ent->klass == klass) {
	return ent->me;
    }

    return rb_get_method_entry(klass, id);
}

static void
remove_method(VALUE klass, ID mid)
{
    st_data_t data;
    rb_method_entry_t *me = 0;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't remove method");
    }
    if (OBJ_FROZEN(klass))
	rb_error_frozen("class/module");
    if (mid == object_id || mid == id__send__ || mid == idInitialize) {
	rb_warn("removing `%s' may cause serious problems", rb_id2name(mid));
    }

    if (st_lookup(RCLASS_M_TBL(klass), mid, &data)) {
	me = (rb_method_entry_t *)data;
	if (!me || me->type == VM_METHOD_TYPE_UNDEF) {
	    me = 0;
	}
	else {
	    st_delete(RCLASS_M_TBL(klass), &mid, &data);
	}
    }
    if (!me) {
	rb_name_error(mid, "method `%s' not defined in %s",
		      rb_id2name(mid), rb_class2name(klass));
    }

    rb_vm_check_redefinition_opt_method(me);
    rb_clear_cache_for_undef(klass, mid);

    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_funcall(rb_iv_get(klass, "__attached__"), singleton_removed, 1, ID2SYM(mid));
    }
    else {
	rb_funcall(klass, removed, 1, ID2SYM(mid));
    }
}

void
rb_remove_method(VALUE klass, const char *name)
{
    remove_method(klass, rb_intern(name));
}

/*
 *  call-seq:
 *     remove_method(symbol)   => self
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
rb_export_method(VALUE klass, ID name, ID noex)
{
    rb_method_entry_t *me;

    if (klass == rb_cObject) {
	rb_secure(4);
    }

    me = search_method(klass, name);
    if (!me && TYPE(klass) == T_MODULE) {
	me = search_method(rb_cObject, name);
    }

    if (!me || me->type == VM_METHOD_TYPE_UNDEF) {
	rb_print_undef(klass, name, 0);
    }

    if (me->flag != noex) {
	rb_vm_check_redefinition_opt_method(me);

	if (klass == me->klass) {
	    me->flag = noex;
	}
	else {
	    rb_add_method(klass, name, VM_METHOD_TYPE_ZSUPER, 0, noex);
	}
    }
}

int
rb_method_boundp(VALUE klass, ID id, int ex)
{
    rb_method_entry_t *me = rb_method_entry(klass, id);

    if (me != 0) {
	if (ex && (me->flag & NOEX_PRIVATE)) {
	    return Qfalse;
	}
	if (me->type == VM_METHOD_TYPE_NOTIMPLEMENTED) {
	    return Qfalse;
	}
	return Qtrue;
    }
    return Qfalse;
}

void
rb_attr(VALUE klass, ID id, int read, int write, int ex)
{
    const char *name;
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

    if (!rb_is_local_id(id) && !rb_is_const_id(id)) {
	rb_name_error(id, "invalid attribute name `%s'", rb_id2name(id));
    }
    name = rb_id2name(id);
    if (!name) {
	rb_raise(rb_eArgError, "argument needs to be symbol or string");
    }
    aname = rb_sprintf("@%s", name);
    rb_enc_copy(aname, rb_id2str(id));
    attriv = rb_intern_str(aname);
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

    if (rb_vm_cbase() == rb_cObject && klass == rb_cObject) {
	rb_secure(4);
    }
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't undef `%s'", rb_id2name(id));
    }
    rb_frozen_class_p(klass);
    if (id == object_id || id == id__send__ || id == idInitialize) {
	rb_warn("undefining `%s' may cause serious problems", rb_id2name(id));
    }

    me = search_method(klass, id);

    if (!me || me->type == VM_METHOD_TYPE_UNDEF) {
	const char *s0 = " class";
	VALUE c = klass;

	if (FL_TEST(c, FL_SINGLETON)) {
	    VALUE obj = rb_iv_get(klass, "__attached__");

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
	rb_name_error(id, "undefined method `%s' for%s `%s'",
		      rb_id2name(id), s0, rb_class2name(c));
    }

    rb_add_method(klass, id, VM_METHOD_TYPE_UNDEF, 0, NOEX_PUBLIC);

    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_funcall(rb_iv_get(klass, "__attached__"), singleton_undefined, 1, ID2SYM(id));
    }
    else {
	rb_funcall(klass, undefined, 1, ID2SYM(id));
    }
}

/*
 *  call-seq:
 *     undef_method(symbol)    => self
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

/*
 *  call-seq:
 *     mod.method_defined?(symbol)    => true or false
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
    return rb_method_boundp(mod, rb_to_id(mid), 1);
}

#define VISI_CHECK(x,f) (((x)&NOEX_MASK) == (f))

static VALUE
check_definition(VALUE mod, VALUE mid, rb_method_flag_t noex)
{
    const rb_method_entry_t *me;
    me = rb_method_entry(mod, mid);
    if (me) {
	if (VISI_CHECK(me->flag, noex))
	    return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     mod.public_method_defined?(symbol)   => true or false
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
    return check_definition(mod, rb_to_id(mid), NOEX_PUBLIC);
}

/*
 *  call-seq:
 *     mod.private_method_defined?(symbol)    => true or false
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
    return check_definition(mod, rb_to_id(mid), NOEX_PRIVATE);
}

/*
 *  call-seq:
 *     mod.protected_method_defined?(symbol)   => true or false
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
    return check_definition(mod, rb_to_id(mid), NOEX_PROTECTED);
}

static void *
me_opts(const rb_method_entry_t *me)
{
    switch (me->type) {
      case VM_METHOD_TYPE_ISEQ:
	return me->body.iseq;
      case VM_METHOD_TYPE_CFUNC:
	return (void *)&me->body.cfunc;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	return (void *)me->body.attr_id;
      case VM_METHOD_TYPE_BMETHOD:
	return (void *)me->body.proc;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_UNDEF:
	return 0;
      case VM_METHOD_TYPE_OPTIMIZED:
	return (void *)me->body.optimize_type;
      default:
	rb_bug("rb_add_method: unsupported method type (%d)\n", me->type);
	return 0;
    }
}

void
rb_add_method_me(VALUE klass, ID mid, const rb_method_entry_t *me, rb_method_flag_t noex)
{
    rb_add_method(klass, mid, me->type, me_opts(me), noex);
}

int
rb_method_entry_eq(const rb_method_entry_t *m1, const rb_method_entry_t *m2)
{
    if (m1->type != m2->type) {
	return 0;
    }
    switch (m1->type) {
      case VM_METHOD_TYPE_ISEQ:
	return m1->body.iseq == m2->body.iseq;
      case VM_METHOD_TYPE_CFUNC:
	return
	  m1->body.cfunc.func == m2->body.cfunc.func &&
	  m1->body.cfunc.argc == m2->body.cfunc.argc;
      case VM_METHOD_TYPE_ATTRSET:
      case VM_METHOD_TYPE_IVAR:
	return m1->body.attr_id == m2->body.attr_id;
      case VM_METHOD_TYPE_BMETHOD:
	return m1->body.proc == m2->body.proc;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_UNDEF:
	return 1;
      case VM_METHOD_TYPE_OPTIMIZED:
	return m1->body.optimize_type == m2->body.optimize_type;
      default:
	rb_bug("rb_add_method: unsupported method type (%d)\n", m1->type);
	return 0;
    }
}

void
rb_alias(VALUE klass, ID name, ID def)
{
    rb_method_entry_t *orig_me, *me;
    VALUE singleton = 0;

    rb_frozen_class_p(klass);
    if (klass == rb_cObject) {
	rb_secure(4);
    }

    orig_me = search_method(klass, def);

    if (!orig_me || orig_me->type == VM_METHOD_TYPE_UNDEF) {
	if (TYPE(klass) == T_MODULE) {
	    orig_me = search_method(rb_cObject, def);
	}
	if (!orig_me || !orig_me->type == VM_METHOD_TYPE_UNDEF) {
	    rb_print_undef(klass, def, 0);
	}
    }
    if (FL_TEST(klass, FL_SINGLETON)) {
	singleton = rb_iv_get(klass, "__attached__");
    }

    orig_me->alias_count++;
    me = rb_add_method(klass, name, orig_me->type, me_opts(orig_me), orig_me->flag);
    me->original_id = def;

    if (!ruby_running) return;

    rb_clear_cache_by_id(name);

    if (singleton) {
	rb_funcall(singleton, singleton_added, 1, ID2SYM(name));
    }
    else {
	rb_funcall(klass, added, 1, ID2SYM(name));
    }
}

/*
 *  call-seq:
 *     alias_method(new_name, old_name)   => self
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

static void
secure_visibility(VALUE self)
{
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(self)) {
	rb_raise(rb_eSecurityError,
		 "Insecure: can't change method visibility");
    }
}

static void
set_method_visibility(VALUE self, int argc, VALUE *argv, ID ex)
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
 *     public                 => self
 *     public(symbol, ...)    => self
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
 *     protected                => self
 *     protected(symbol, ...)   => self
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
 *     private                 => self
 *     private(symbol, ...)    => self
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
 *     mod.public_class_method(symbol, ...)    => mod
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
 *     mod.private_class_method(symbol, ...)   => mod
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
 *     module_function(symbol, ...)    => self
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
 *       def callOne
 *         one
 *       end
 *     end
 *     Mod.one     #=> "This is one"
 *     c = Cls.new
 *     c.callOne   #=> "This is one"
 *     module Mod
 *       def one
 *         "This is the new one"
 *       end
 *     end
 *     Mod.one     #=> "This is one"
 *     c.callOne   #=> "This is the new one"
 */

static VALUE
rb_mod_modfunc(int argc, VALUE *argv, VALUE module)
{
    int i;
    ID id;
    const rb_method_entry_t *me;

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

	id = rb_to_id(argv[i]);
	for (;;) {
	    me = search_method(m, id);
	    if (me == 0) {
		me = search_method(rb_cObject, id);
	    }
	    if (me == 0 || me->type == VM_METHOD_TYPE_UNDEF) {
		rb_print_undef(module, id, 0);
	    }
	    if (me->type != VM_METHOD_TYPE_ZSUPER) {
		break; /* normal case: need not to follow 'super' link */
	    }
	    m = RCLASS_SUPER(m);
	    if (!m)
		break;
	}
	rb_add_method_me(rb_singleton_class(module), id, me, NOEX_PUBLIC);
    }
    return module;
}

int
rb_method_basic_definition_p(VALUE klass, ID id)
{
    const rb_method_entry_t *me = rb_method_entry(klass, id);
    if (me && (me->flag & NOEX_BASIC))
	return 1;
    return 0;
}

int
rb_obj_respond_to(VALUE obj, ID id, int priv)
{
    VALUE klass = CLASS_OF(obj);

    if (rb_method_basic_definition_p(klass, idRespond_to)) {
	return rb_method_boundp(klass, id, !priv);
    }
    else {
	VALUE args[2];
	int n = 0;
	args[n++] = ID2SYM(id);
	if (priv)
	    args[n++] = Qtrue;
	return RTEST(rb_funcall2(obj, idRespond_to, n, args));
    }
}

int
rb_respond_to(VALUE obj, ID id)
{
    return rb_obj_respond_to(obj, id, Qfalse);
}

/*
 *  call-seq:
 *     obj.respond_to?(symbol, include_private=false) => true or false
 *
 *  Returns +true+ if _obj_ responds to the given
 *  method. Private methods are included in the search only if the
 *  optional second parameter evaluates to +true+.
 *
 *  If the method is not implemented,
 *  as Process.fork on Windows, File.lchmod on GNU/Linux, etc.,
 *  false is returned.
 */

static VALUE
obj_respond_to(int argc, VALUE *argv, VALUE obj)
{
    VALUE mid, priv;
    ID id;

    rb_scan_args(argc, argv, "11", &mid, &priv);
    id = rb_to_id(mid);
    if (rb_method_boundp(CLASS_OF(obj), id, !RTEST(priv))) {
	return Qtrue;
    }
    return Qfalse;
}

void
Init_eval_method(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    rb_define_method(rb_mKernel, "respond_to?", obj_respond_to, -1);

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
}

