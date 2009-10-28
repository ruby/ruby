/*
 * This file is included by vm.h
 */

#define CACHE_SIZE 0x800
#define CACHE_MASK 0x7ff
#define EXPR1(c,m) ((((c)>>3)^(m))&CACHE_MASK)

static void rb_vm_check_redefinition_opt_method(const NODE *node);

static ID object_id;
static ID removed, singleton_removed, undefined, singleton_undefined;
static ID added, singleton_added;

struct cache_entry {		/* method hash table. */
    ID mid;			/* method's id */
    ID mid0;			/* method's original id */
    VALUE klass;		/* receiver's class */
    VALUE oklass;		/* original's class */
    NODE *method;
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
	if (ent->oklass == klass && ent->mid == id) {
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
	if (ent->klass == klass || ent->oklass == klass) {
	    ent->mid = 0;
	}
	ent++;
    }
}

void
rb_add_method(VALUE klass, ID mid, NODE * node, int noex)
{
    NODE *body;

    if (NIL_P(klass)) {
	klass = rb_cObject;
    }
    if (rb_safe_level() >= 4 &&
       	(klass == rb_cObject || !OBJ_UNTRUSTED(klass))) {
	rb_raise(rb_eSecurityError, "Insecure: can't define method");
    }
    if (!FL_TEST(klass, FL_SINGLETON) &&
	node && nd_type(node) != NODE_ZSUPER &&
	(mid == rb_intern("initialize") || mid == rb_intern("initialize_copy"))) {
	noex = NOEX_PRIVATE | noex;
    }
    else if (FL_TEST(klass, FL_SINGLETON) && node
	     && nd_type(node) == NODE_CFUNC && mid == rb_intern("allocate")) {
	rb_warn
	    ("defining %s.allocate is deprecated; use rb_define_alloc_func()",
	     rb_class2name(rb_iv_get(klass, "__attached__")));
	mid = ID_ALLOCATOR;
    }
    if (OBJ_FROZEN(klass)) {
	rb_error_frozen("class/module");
    }
    rb_clear_cache_by_id(mid);

    /*
     * NODE_METHOD (NEW_METHOD(body, klass, vis)):
     *   nd_file : original id   // RBASIC()->klass (TODO: dirty hack)
     *   nd_body : method body   // (2) // mark
     *   nd_clss : klass         // (1) // mark
     *   nd_noex : visibility    // (3)
     *
     * NODE_FBODY (NEW_FBODY(method, alias)):
     *   nd_body : method (NODE_METHOD)  // (2) // mark
     *   nd_oid  : original id           // (1)
     *   nd_cnt  : alias count           // (3)
     */
    if (node) {
	NODE *method = NEW_METHOD(node, klass, NOEX_WITH_SAFE(noex));
	method->nd_file = (void *)mid;
	body = NEW_FBODY(method, mid);
    }
    else {
	body = 0;
    }

    {
	/* check re-definition */
	st_data_t data;
	NODE *old_node;

	if (st_lookup(RCLASS_M_TBL(klass), mid, &data)) {
	    old_node = (NODE *)data;
	    if (old_node) {
		if (nd_type(old_node->nd_body->nd_body) == NODE_CFUNC) {
		    rb_vm_check_redefinition_opt_method(old_node);
		}
		if (RTEST(ruby_verbose) && node && old_node->nd_cnt == 0 && old_node->nd_body) {
		    rb_warning("method redefined; discarding old %s", rb_id2name(mid));
		}
	    }
	}
	if (klass == rb_cObject && node && mid == idInitialize) {
	    rb_warn("redefining Object#initialize may cause infinite loop");
	}

	if (mid == object_id || mid == id__send__) {
	    if (node && nd_type(node) == RUBY_VM_METHOD_NODE) {
		rb_warn("redefining `%s' may cause serious problem",
			rb_id2name(mid));
	    }
	}
    }

    st_insert(RCLASS_M_TBL(klass), mid, (st_data_t) body);

    if (node && mid != ID_ALLOCATOR && ruby_running) {
	if (FL_TEST(klass, FL_SINGLETON)) {
	    rb_funcall(rb_iv_get(klass, "__attached__"), singleton_added, 1,
		       ID2SYM(mid));
	}
	else {
	    rb_funcall(klass, added, 1, ID2SYM(mid));
	}
    }
}

void
rb_define_alloc_func(VALUE klass, VALUE (*func)(VALUE))
{
    Check_Type(klass, T_CLASS);
    rb_add_method(rb_singleton_class(klass), ID_ALLOCATOR, NEW_CFUNC(func, 0),
		  NOEX_PRIVATE);
}

void
rb_undef_alloc_func(VALUE klass)
{
    Check_Type(klass, T_CLASS);
    rb_add_method(rb_singleton_class(klass), ID_ALLOCATOR, 0, NOEX_UNDEF);
}

rb_alloc_func_t
rb_get_alloc_func(VALUE klass)
{
    NODE *n;
    Check_Type(klass, T_CLASS);
    n = rb_method_node(CLASS_OF(klass), ID_ALLOCATOR);
    if (!n) return 0;
    if (nd_type(n) != NODE_METHOD) return 0;
    n = n->nd_body;
    if (nd_type(n) != NODE_CFUNC) return 0;
    return (rb_alloc_func_t)n->nd_cfnc;
}

static NODE *
search_method(VALUE klass, ID id, VALUE *klassp)
{
    st_data_t body;

    if (!klass) {
	return 0;
    }

    while (!st_lookup(RCLASS_M_TBL(klass), id, &body)) {
	klass = RCLASS_SUPER(klass);
	if (!klass)
	    return 0;
    }

    if (klassp) {
	*klassp = klass;
    }

    return (NODE *)body;
}

/*
 * search method body (NODE_METHOD)
 *   with    : klass and id
 *   without : method cache
 *
 * if you need method node with method cache, use
 * rb_method_node()
 */
NODE *
rb_get_method_body(VALUE klass, ID id, ID *idp)
{
    NODE *volatile fbody, *body;
    NODE *method;

    if ((fbody = search_method(klass, id, 0)) == 0 || !fbody->nd_body) {
	/* store empty info in cache */
	struct cache_entry *ent;
	ent = cache + EXPR1(klass, id);
	ent->klass = klass;
	ent->mid = ent->mid0 = id;
	ent->method = 0;
	ent->oklass = 0;
	return 0;
    }

    method = fbody->nd_body;

    if (ruby_running) {
	/* store in cache */
	struct cache_entry *ent;
	ent = cache + EXPR1(klass, id);
	ent->klass = klass;
	ent->mid = id;
	ent->mid0 = fbody->nd_oid;
	ent->method = body = method;
	ent->oklass = method->nd_clss;
    }
    else {
	body = method;
    }

    if (idp) {
	*idp = fbody->nd_oid;
    }

    return body;
}

NODE *
rb_method_node(VALUE klass, ID id)
{
    struct cache_entry *ent;

    ent = cache + EXPR1(klass, id);
    if (ent->mid == id && ent->klass == klass) {
	if (ent->method) return ent->method;
	return 0;
    }

    return rb_get_method_body(klass, id, 0);
}

void
rb_remove_method_id(VALUE klass, ID mid)
{
    st_data_t data;
    NODE *body = 0;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't remove method");
    }
    if (OBJ_FROZEN(klass))
	rb_error_frozen("class/module");
    if (mid == object_id || mid == id__send__ || mid == idInitialize) {
	rb_warn("removing `%s' may cause serious problem", rb_id2name(mid));
    }
    if (st_lookup(RCLASS_M_TBL(klass), mid, &data)) {
	body = (NODE *)data;
	if (!body || !body->nd_body) body = 0;
	else {
	    st_delete(RCLASS_M_TBL(klass), &mid, &data);
	}
    }
    if (!body) {
	rb_name_error(mid, "method `%s' not defined in %s",
		      rb_id2name(mid), rb_class2name(klass));
    }

    if (nd_type(body->nd_body->nd_body) == NODE_CFUNC) {
	rb_vm_check_redefinition_opt_method(body);
    }

    rb_clear_cache_for_undef(klass, mid);
    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_funcall(rb_iv_get(klass, "__attached__"), singleton_removed, 1,
		   ID2SYM(mid));
    }
    else {
	rb_funcall(klass, removed, 1, ID2SYM(mid));
    }
}

#define remove_method(klass, mid) rb_remove_method_id(klass, mid)

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
    NODE *fbody;
    VALUE origin;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    fbody = search_method(klass, name, &origin);
    if (!fbody && TYPE(klass) == T_MODULE) {
	fbody = search_method(rb_cObject, name, &origin);
    }
    if (!fbody || !fbody->nd_body) {
	rb_print_undef(klass, name, 0);
    }
    if (fbody->nd_body->nd_noex != noex) {
	if (nd_type(fbody->nd_body->nd_body) == NODE_CFUNC) {
	    rb_vm_check_redefinition_opt_method(fbody);
	}
	if (klass == origin) {
	    fbody->nd_body->nd_noex = noex;
	}
	else {
	    rb_add_method(klass, name, NEW_ZSUPER(), noex);
	}
    }
}

int
rb_method_boundp(VALUE klass, ID id, int ex)
{
    NODE *method;

    if ((method = rb_method_node(klass, id)) != 0) {
	if (ex && (method->nd_noex & NOEX_PRIVATE)) {
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
    int noex;

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
	rb_add_method(klass, id, NEW_IVAR(attriv), noex);
    }
    if (write) {
	rb_add_method(klass, rb_id_attrset(id), NEW_ATTRSET(attriv), noex);
    }
}

void
rb_undef(VALUE klass, ID id)
{
    VALUE origin;
    NODE *body;

    if (rb_vm_cbase() == rb_cObject && klass == rb_cObject) {
	rb_secure(4);
    }
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't undef `%s'",
		 rb_id2name(id));
    }
    rb_frozen_class_p(klass);
    if (id == object_id || id == id__send__ || id == idInitialize) {
	rb_warn("undefining `%s' may cause serious problem", rb_id2name(id));
    }
    body = search_method(klass, id, &origin);
    if (!body || !body->nd_body) {
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

    rb_add_method(klass, id, 0, NOEX_PUBLIC);

    if (FL_TEST(klass, FL_SINGLETON)) {
	rb_funcall(rb_iv_get(klass, "__attached__"),
		   singleton_undefined, 1, ID2SYM(id));
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
    ID id = rb_to_id(mid);
    NODE *method;

    method = rb_method_node(mod, id);
    if (method) {
	if (VISI_CHECK(method->nd_noex, NOEX_PUBLIC))
	    return Qtrue;
    }
    return Qfalse;
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
    ID id = rb_to_id(mid);
    NODE *method;

    method = rb_method_node(mod, id);
    if (method) {
	if (VISI_CHECK(method->nd_noex, NOEX_PRIVATE))
	    return Qtrue;
    }
    return Qfalse;
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
    ID id = rb_to_id(mid);
    NODE *method;

    method = rb_method_node(mod, id);
    if (method) {
	if (VISI_CHECK(method->nd_noex, NOEX_PROTECTED))
	    return Qtrue;
    }
    return Qfalse;
}

void
rb_alias(VALUE klass, ID name, ID def)
{
    NODE *orig_fbody, *node, *method;
    VALUE singleton = 0;
    st_data_t data;

    rb_frozen_class_p(klass);
    if (klass == rb_cObject) {
	rb_secure(4);
    }
    orig_fbody = search_method(klass, def, 0);
    if (!orig_fbody || !orig_fbody->nd_body) {
	if (TYPE(klass) == T_MODULE) {
	    orig_fbody = search_method(rb_cObject, def, 0);
	}
    }
    if (!orig_fbody || !orig_fbody->nd_body) {
	rb_print_undef(klass, def, 0);
    }
    if (FL_TEST(klass, FL_SINGLETON)) {
	singleton = rb_iv_get(klass, "__attached__");
    }

    orig_fbody->nd_cnt++;

    if (st_lookup(RCLASS_M_TBL(klass), name, &data)) {
	node = (NODE *)data;
	if (node) {
	    if (RTEST(ruby_verbose) && node->nd_cnt == 0 && node->nd_body) {
		rb_warning("discarding old %s", rb_id2name(name));
	    }
	    if (nd_type(node->nd_body->nd_body) == NODE_CFUNC) {
		rb_vm_check_redefinition_opt_method(node);
	    }
	}
    }

    st_insert(RCLASS_M_TBL(klass), name,
	      (st_data_t) NEW_FBODY(
		  method = NEW_METHOD(orig_fbody->nd_body->nd_body,
			     orig_fbody->nd_body->nd_clss,
			     NOEX_WITH_SAFE(orig_fbody->nd_body->nd_noex)), def));
    method->nd_file = (void *)def;

    rb_clear_cache_by_id(name);

    if (!ruby_running) return;

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
    NODE *fbody;

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
	    fbody = search_method(m, id, &m);
	    if (fbody == 0) {
		fbody = search_method(rb_cObject, id, &m);
	    }
	    if (fbody == 0 || fbody->nd_body == 0) {
		rb_print_undef(module, id, 0);
	    }
	    if (nd_type(fbody->nd_body->nd_body) != NODE_ZSUPER) {
		break;		/* normal case: need not to follow 'super' link */
	    }
	    m = RCLASS_SUPER(m);
	    if (!m)
		break;
	}
	rb_add_method(rb_singleton_class(module), id, fbody->nd_body->nd_body,
		      NOEX_PUBLIC);
    }
    return module;
}

int
rb_method_basic_definition_p(VALUE klass, ID id)
{
    NODE *node = rb_method_node(klass, id);
    if (node && (node->nd_noex & NOEX_BASIC))
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

