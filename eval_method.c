/* -*-c-*- */
/*
 * This file is included by eval.c
 */

#define CACHE_SIZE 0x800
#define CACHE_MASK 0x7ff
#define EXPR1(c,m) ((((c)>>3)^(m))&CACHE_MASK)

struct cache_entry {		/* method hash table. */
    ID mid;			/* method's id */
    ID mid0;			/* method's original id */
    VALUE klass;		/* receiver's class */
    VALUE oklass;		/* original's class */
    NODE *method;
};

static struct cache_entry cache[CACHE_SIZE];
static int ruby_running = 0;

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
    if (rb_safe_level() >= 4 && (klass == rb_cObject || !OBJ_TAINTED(klass))) {
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
	body = NEW_FBODY(NEW_METHOD(node, klass, NOEX_WITH_SAFE(noex)), 0);
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
	if (klass == rb_cObject && node && mid == init) {
	    rb_warn("redefining Object#initialize may cause infinite loop");
	}

	if (mid == object_id || mid == __send__) {
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
    if (ent->mid == id && ent->klass == klass && ent->method) {
	return ent->method;
    }

    return rb_get_method_body(klass, id, 0);
}

static void
remove_method(VALUE klass, ID mid)
{
    st_data_t data;
    NODE *body = 0;

    if (klass == rb_cObject) {
	rb_secure(4);
    }
    if (rb_safe_level() >= 4 && !OBJ_TAINTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't remove method");
    }
    if (OBJ_FROZEN(klass))
	rb_error_frozen("class/module");
    if (mid == object_id || mid == __send__ || mid == init) {
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
    attriv = rb_intern_str(rb_sprintf("@%s", name));
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
    if (rb_safe_level() >= 4 && !OBJ_TAINTED(klass)) {
	rb_raise(rb_eSecurityError, "Insecure: can't undef `%s'",
		 rb_id2name(id));
    }
    rb_frozen_class_p(klass);
    if (id == object_id || id == __send__ || id == init) {
	rb_warn("undefining `%s' may cause serious problem", rb_id2name(id));
    }
    body = search_method(klass, id, &origin);
    if (!body || !body->nd_body) {
	char *s0 = " class";
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

void
rb_alias(VALUE klass, ID name, ID def)
{
    NODE *orig_fbody, *node;
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
		  NEW_METHOD(orig_fbody->nd_body->nd_body,
			     orig_fbody->nd_body->nd_clss,
			     NOEX_WITH_SAFE(orig_fbody->nd_body->nd_noex)), def));

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
Init_eval_method(void)
{
    rb_define_private_method(rb_cModule, "remove_method", rb_mod_remove_method, -1);
    rb_define_private_method(rb_cModule, "undef_method", rb_mod_undef_method, -1);
    rb_define_private_method(rb_cModule, "alias_method", rb_mod_alias_method, 2);
}
