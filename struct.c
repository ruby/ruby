/**********************************************************************

  struct.c -

  $Author$
  created at: Tue Mar 22 18:44:30 JST 1995

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "id.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/struct.h"
#include "internal/symbol.h"
#include "transient_heap.h"
#include "vm_core.h"
#include "builtin.h"

/* only for struct[:field] access */
enum {
    AREF_HASH_UNIT = 5,
    AREF_HASH_THRESHOLD = 10
};

VALUE rb_cStruct;
static ID id_members, id_back_members, id_keyword_init;

static VALUE struct_alloc(VALUE);

static inline VALUE
struct_ivar_get(VALUE c, ID id)
{
    VALUE orig = c;
    VALUE ivar = rb_attr_get(c, id);

    if (!NIL_P(ivar))
	return ivar;

    for (;;) {
	c = RCLASS_SUPER(c);
	if (c == 0 || c == rb_cStruct)
	    return Qnil;
	ivar = rb_attr_get(c, id);
	if (!NIL_P(ivar)) {
	    return rb_ivar_set(orig, id, ivar);
	}
    }
}

VALUE
rb_struct_s_keyword_init(VALUE klass)
{
    return struct_ivar_get(klass, id_keyword_init);
}

VALUE
rb_struct_s_members(VALUE klass)
{
    VALUE members = struct_ivar_get(klass, id_members);

    if (NIL_P(members)) {
	rb_raise(rb_eTypeError, "uninitialized struct");
    }
    if (!RB_TYPE_P(members, T_ARRAY)) {
	rb_raise(rb_eTypeError, "corrupted struct");
    }
    return members;
}

VALUE
rb_struct_members(VALUE s)
{
    VALUE members = rb_struct_s_members(rb_obj_class(s));

    if (RSTRUCT_LEN(s) != RARRAY_LEN(members)) {
	rb_raise(rb_eTypeError, "struct size differs (%ld required %ld given)",
		 RARRAY_LEN(members), RSTRUCT_LEN(s));
    }
    return members;
}

static long
struct_member_pos_ideal(VALUE name, long mask)
{
    /* (id & (mask/2)) * 2 */
    return (SYM2ID(name) >> (ID_SCOPE_SHIFT - 1)) & mask;
}

static long
struct_member_pos_probe(long prev, long mask)
{
    /* (((prev/2) * AREF_HASH_UNIT + 1) & (mask/2)) * 2 */
    return (prev * AREF_HASH_UNIT + 2) & mask;
}

static VALUE
struct_set_members(VALUE klass, VALUE /* frozen hidden array */ members)
{
    VALUE back;
    const long members_length = RARRAY_LEN(members);

    if (members_length <= AREF_HASH_THRESHOLD) {
	back = members;
    }
    else {
	long i, j, mask = 64;
	VALUE name;

	while (mask < members_length * AREF_HASH_UNIT) mask *= 2;

	back = rb_ary_tmp_new(mask + 1);
	rb_ary_store(back, mask, INT2FIX(members_length));
	mask -= 2;			  /* mask = (2**k-1)*2 */

	for (i=0; i < members_length; i++) {
	    name = RARRAY_AREF(members, i);

	    j = struct_member_pos_ideal(name, mask);

	    for (;;) {
		if (!RTEST(RARRAY_AREF(back, j))) {
		    rb_ary_store(back, j, name);
		    rb_ary_store(back, j + 1, INT2FIX(i));
		    break;
		}
		j = struct_member_pos_probe(j, mask);
	    }
	}
	OBJ_FREEZE_RAW(back);
    }
    rb_ivar_set(klass, id_members, members);
    rb_ivar_set(klass, id_back_members, back);

    return members;
}

static inline int
struct_member_pos(VALUE s, VALUE name)
{
    VALUE back = struct_ivar_get(rb_obj_class(s), id_back_members);
    long j, mask;

    if (UNLIKELY(NIL_P(back))) {
	rb_raise(rb_eTypeError, "uninitialized struct");
    }
    if (UNLIKELY(!RB_TYPE_P(back, T_ARRAY))) {
	rb_raise(rb_eTypeError, "corrupted struct");
    }

    mask = RARRAY_LEN(back);

    if (mask <= AREF_HASH_THRESHOLD) {
	if (UNLIKELY(RSTRUCT_LEN(s) != mask)) {
	    rb_raise(rb_eTypeError,
		     "struct size differs (%ld required %ld given)",
		     mask, RSTRUCT_LEN(s));
	}
	for (j = 0; j < mask; j++) {
            if (RARRAY_AREF(back, j) == name)
		return (int)j;
	}
	return -1;
    }

    if (UNLIKELY(RSTRUCT_LEN(s) != FIX2INT(RARRAY_AREF(back, mask-1)))) {
	rb_raise(rb_eTypeError, "struct size differs (%d required %ld given)",
		 FIX2INT(RARRAY_AREF(back, mask-1)), RSTRUCT_LEN(s));
    }

    mask -= 3;
    j = struct_member_pos_ideal(name, mask);

    for (;;) {
        VALUE e = RARRAY_AREF(back, j);
        if (e == name)
            return FIX2INT(RARRAY_AREF(back, j + 1));
        if (!RTEST(e)) {
	    return -1;
	}
	j = struct_member_pos_probe(j, mask);
    }
}

/*
 *  call-seq:
 *    StructClass::members -> array_of_symbols
 *
 *  Returns the member names of the Struct descendant as an array:
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     Customer.members # => [:name, :address, :zip]
 *
 */

static VALUE
rb_struct_s_members_m(VALUE klass)
{
    VALUE members = rb_struct_s_members(klass);

    return rb_ary_dup(members);
}

/*
 *  call-seq:
 *    members -> array_of_symbols
 *
 *  Returns the member names from +self+ as an array:
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     Customer.new.members # => [:name, :address, :zip]
 *
 *  Related: #to_a.
 */

static VALUE
rb_struct_members_m(VALUE obj)
{
    return rb_struct_s_members_m(rb_obj_class(obj));
}

VALUE
rb_struct_getmember(VALUE obj, ID id)
{
    VALUE slot = ID2SYM(id);
    int i = struct_member_pos(obj, slot);
    if (i != -1) {
	return RSTRUCT_GET(obj, i);
    }
    rb_name_err_raise("`%1$s' is not a struct member", obj, ID2SYM(id));

    UNREACHABLE_RETURN(Qnil);
}

static void
rb_struct_modify(VALUE s)
{
    rb_check_frozen(s);
}

static VALUE
anonymous_struct(VALUE klass)
{
    VALUE nstr;

    nstr = rb_class_new(klass);
    rb_make_metaclass(nstr, RBASIC(klass)->klass);
    rb_class_inherited(klass, nstr);
    return nstr;
}

static VALUE
new_struct(VALUE name, VALUE super)
{
    /* old style: should we warn? */
    ID id;
    name = rb_str_to_str(name);
    if (!rb_is_const_name(name)) {
	rb_name_err_raise("identifier %1$s needs to be constant",
			  super, name);
    }
    id = rb_to_id(name);
    if (rb_const_defined_at(super, id)) {
	rb_warn("redefining constant %"PRIsVALUE"::%"PRIsVALUE, super, name);
	rb_mod_remove_const(super, ID2SYM(id));
    }
    return rb_define_class_id_under(super, id, super);
}

NORETURN(static void invalid_struct_pos(VALUE s, VALUE idx));

static void
define_aref_method(VALUE nstr, VALUE name, VALUE off)
{
    rb_add_method_optimized(nstr, SYM2ID(name), OPTIMIZED_METHOD_TYPE_STRUCT_AREF, FIX2UINT(off), METHOD_VISI_PUBLIC);
}

static void
define_aset_method(VALUE nstr, VALUE name, VALUE off)
{
    rb_add_method_optimized(nstr, SYM2ID(name), OPTIMIZED_METHOD_TYPE_STRUCT_ASET, FIX2UINT(off), METHOD_VISI_PUBLIC);
}

static VALUE
rb_struct_s_inspect(VALUE klass)
{
    VALUE inspect = rb_class_name(klass);
    if (RTEST(rb_struct_s_keyword_init(klass))) {
	rb_str_cat_cstr(inspect, "(keyword_init: true)");
    }
    return inspect;
}

#if 0 /* for RDoc */

/*
 * call-seq:
 *   StructClass::keyword_init? -> true or falsy value
 *
 * Returns +true+ if the class was initialized with <tt>keyword_init: true</tt>.
 * Otherwise returns +nil+ or +false+.
 *
 * Examples:
 *   Foo = Struct.new(:a)
 *   Foo.keyword_init? # => nil
 *   Bar = Struct.new(:a, keyword_init: true)
 *   Bar.keyword_init? # => true
 *   Baz = Struct.new(:a, keyword_init: false)
 *   Baz.keyword_init? # => false
 */
static VALUE
rb_struct_s_keyword_init_p(VALUE obj)
{
}
#endif

#define rb_struct_s_keyword_init_p rb_struct_s_keyword_init

static VALUE
setup_struct(VALUE nstr, VALUE members)
{
    long i, len;

    members = struct_set_members(nstr, members);

    rb_define_alloc_func(nstr, struct_alloc);
    rb_define_singleton_method(nstr, "new", rb_class_new_instance_pass_kw, -1);
    rb_define_singleton_method(nstr, "[]", rb_class_new_instance_pass_kw, -1);
    rb_define_singleton_method(nstr, "members", rb_struct_s_members_m, 0);
    rb_define_singleton_method(nstr, "inspect", rb_struct_s_inspect, 0);
    rb_define_singleton_method(nstr, "keyword_init?", rb_struct_s_keyword_init_p, 0);

    len = RARRAY_LEN(members);
    for (i=0; i< len; i++) {
        VALUE sym = RARRAY_AREF(members, i);
        ID id = SYM2ID(sym);
	VALUE off = LONG2NUM(i);

        define_aref_method(nstr, sym, off);
        define_aset_method(nstr, ID2SYM(rb_id_attrset(id)), off);
    }

    return nstr;
}

VALUE
rb_struct_alloc_noinit(VALUE klass)
{
    return struct_alloc(klass);
}

static VALUE
struct_make_members_list(va_list ar)
{
    char *mem;
    VALUE ary, list = rb_ident_hash_new();
    st_table *tbl = RHASH_TBL_RAW(list);

    RBASIC_CLEAR_CLASS(list);
    OBJ_WB_UNPROTECT(list);
    while ((mem = va_arg(ar, char*)) != 0) {
	VALUE sym = rb_sym_intern_ascii_cstr(mem);
	if (st_insert(tbl, sym, Qtrue)) {
	    rb_raise(rb_eArgError, "duplicate member: %s", mem);
	}
    }
    ary = rb_hash_keys(list);
    st_clear(tbl);
    RBASIC_CLEAR_CLASS(ary);
    OBJ_FREEZE_RAW(ary);
    return ary;
}

static VALUE
struct_define_without_accessor(VALUE outer, const char *class_name, VALUE super, rb_alloc_func_t alloc, VALUE members)
{
    VALUE klass;

    if (class_name) {
	if (outer) {
	    klass = rb_define_class_under(outer, class_name, super);
	}
	else {
	    klass = rb_define_class(class_name, super);
	}
    }
    else {
	klass = anonymous_struct(super);
    }

    struct_set_members(klass, members);

    if (alloc) {
	rb_define_alloc_func(klass, alloc);
    }
    else {
	rb_define_alloc_func(klass, struct_alloc);
    }

    return klass;
}

VALUE
rb_struct_define_without_accessor_under(VALUE outer, const char *class_name, VALUE super, rb_alloc_func_t alloc, ...)
{
    va_list ar;
    VALUE members;

    va_start(ar, alloc);
    members = struct_make_members_list(ar);
    va_end(ar);

    return struct_define_without_accessor(outer, class_name, super, alloc, members);
}

VALUE
rb_struct_define_without_accessor(const char *class_name, VALUE super, rb_alloc_func_t alloc, ...)
{
    va_list ar;
    VALUE members;

    va_start(ar, alloc);
    members = struct_make_members_list(ar);
    va_end(ar);

    return struct_define_without_accessor(0, class_name, super, alloc, members);
}

VALUE
rb_struct_define(const char *name, ...)
{
    va_list ar;
    VALUE st, ary;

    va_start(ar, name);
    ary = struct_make_members_list(ar);
    va_end(ar);

    if (!name) st = anonymous_struct(rb_cStruct);
    else st = new_struct(rb_str_new2(name), rb_cStruct);
    return setup_struct(st, ary);
}

VALUE
rb_struct_define_under(VALUE outer, const char *name, ...)
{
    va_list ar;
    VALUE ary;

    va_start(ar, name);
    ary = struct_make_members_list(ar);
    va_end(ar);

    return setup_struct(rb_define_class_under(outer, name, rb_cStruct), ary);
}

/*
 *  call-seq:
 *    Struct.new(*member_names, keyword_init: false){|Struct_subclass| ... } -> Struct_subclass
 *    Struct.new(class_name, *member_names, keyword_init: false){|Struct_subclass| ... } -> Struct_subclass
 *    Struct_subclass.new(*member_names) -> Struct_subclass_instance
 *    Struct_subclass.new(**member_names) -> Struct_subclass_instance
 *
 *  <tt>Struct.new</tt> returns a new subclass of +Struct+.  The new subclass:
 *
 *  - May be anonymous, or may have the name given by +class_name+.
 *  - May have members as given by +member_names+.
 *  - May have initialization via ordinary arguments (the default)
 *    or via keyword arguments (if <tt>keyword_init: true</tt> is given).
 *
 *  The new subclass has its own method <tt>::new</tt>; thus:
 *
 *    Foo = Struct.new('Foo', :foo, :bar) # => Struct::Foo
 *    f = Foo.new(0, 1)                   # => #<struct Struct::Foo foo=0, bar=1>
 *
 *  <b>\Class Name</b>
 *
 *  With string argument +class_name+,
 *  returns a new subclass of +Struct+ named <tt>Struct::<em>class_name</em></tt>:
 *
 *    Foo = Struct.new('Foo', :foo, :bar) # => Struct::Foo
 *    Foo.name                            # => "Struct::Foo"
 *    Foo.superclass                      # => Struct
 *
 *  Without string argument +class_name+,
 *  returns a new anonymous subclass of +Struct+:
 *
 *    Struct.new(:foo, :bar).name # => nil
 *
 *  <b>Block</b>
 *
 *  With a block given, the created subclass is yielded to the block:
 *
 *    Customer = Struct.new('Customer', :name, :address) do |new_class|
 *      p "The new subclass is #{new_class}"
 *      def greeting
 *        "Hello #{name} at #{address}"
 *      end
 *    end           # => Struct::Customer
 *    dave = Customer.new('Dave', '123 Main')
 *    dave # =>     #<struct Struct::Customer name="Dave", address="123 Main">
 *    dave.greeting # => "Hello Dave at 123 Main"
 *
 *  Output, from <tt>Struct.new</tt>:
 *
 *    "The new subclass is Struct::Customer"
 *
 *  <b>Member Names</b>
 *
 *  \Symbol arguments +member_names+
 *  determines the members of the new subclass:
 *
 *    Struct.new(:foo, :bar).members        # => [:foo, :bar]
 *    Struct.new('Foo', :foo, :bar).members # => [:foo, :bar]
 *
 *  The new subclass has instance methods corresponding to +member_names+:
 *
 *    Foo = Struct.new('Foo', :foo, :bar)
 *    Foo.instance_methods(false) # => [:foo, :bar, :foo=, :bar=]
 *    f = Foo.new                 # => #<struct Struct::Foo foo=nil, bar=nil>
 *    f.foo                       # => nil
 *    f.foo = 0                   # => 0
 *    f.bar                       # => nil
 *    f.bar = 1                   # => 1
 *    f                           # => #<struct Struct::Foo foo=0, bar=1>
 *
 *  <b>Singleton Methods</b>
 *
 *  A subclass returned by Struct.new has these singleton methods:
 *
 *  - \Method <tt>::new </tt> creates an instance of the subclass:
 *
 *      Foo.new          # => #<struct Struct::Foo foo=nil, bar=nil>
 *      Foo.new(0)       # => #<struct Struct::Foo foo=0, bar=nil>
 *      Foo.new(0, 1)    # => #<struct Struct::Foo foo=0, bar=1>
 *      Foo.new(0, 1, 2) # Raises ArgumentError: struct size differs
 *
 *    \Method <tt>::[]</tt> is an alias for method <tt>::new</tt>.
 *
 *  - \Method <tt>:inspect</tt> returns a string representation of the subclass:
 *
 *      Foo.inspect
 *      # => "Struct::Foo"
 *
 *  - \Method <tt>::members</tt> returns an array of the member names:
 *
 *      Foo.members # => [:foo, :bar]
 *
 *  <b>Keyword Argument</b>
 *
 *  By default, the arguments for initializing an instance of the new subclass
 *  are ordinary arguments (not keyword arguments).
 *  With optional keyword argument <tt>keyword_init: true</tt>,
 *  the new subclass is initialized with keyword arguments:
 *
 *    # Without keyword_init: true.
 *    Foo = Struct.new('Foo', :foo, :bar)
 *    Foo                     # => Struct::Foo
 *    Foo.new(0, 1)           # => #<struct Struct::Foo foo=0, bar=1>
 *    # With keyword_init: true.
 *    Bar = Struct.new(:foo, :bar, keyword_init: true)
 *    Bar # =>                # => Bar(keyword_init: true)
 *    Bar.new(bar: 1, foo: 0) # => #<struct Bar foo=0, bar=1>
 *
 */

static VALUE
rb_struct_s_def(int argc, VALUE *argv, VALUE klass)
{
    VALUE name, rest, keyword_init = Qnil;
    long i;
    VALUE st;
    st_table *tbl;

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    name = argv[0];
    if (SYMBOL_P(name)) {
	name = Qnil;
    }
    else {
	--argc;
	++argv;
    }

    if (RB_TYPE_P(argv[argc-1], T_HASH)) {
	static ID keyword_ids[1];

	if (!keyword_ids[0]) {
	    keyword_ids[0] = rb_intern("keyword_init");
	}
        rb_get_kwargs(argv[argc-1], keyword_ids, 0, 1, &keyword_init);
        if (keyword_init == Qundef) {
            keyword_init = Qnil;
        }
        else if (RTEST(keyword_init)) {
            keyword_init = Qtrue;
        }
	--argc;
    }

    rest = rb_ident_hash_new();
    RBASIC_CLEAR_CLASS(rest);
    OBJ_WB_UNPROTECT(rest);
    tbl = RHASH_TBL_RAW(rest);
    for (i=0; i<argc; i++) {
	VALUE mem = rb_to_symbol(argv[i]);
        if (rb_is_attrset_sym(mem)) {
            rb_raise(rb_eArgError, "invalid struct member: %"PRIsVALUE, mem);
        }
	if (st_insert(tbl, mem, Qtrue)) {
	    rb_raise(rb_eArgError, "duplicate member: %"PRIsVALUE, mem);
	}
    }
    rest = rb_hash_keys(rest);
    st_clear(tbl);
    RBASIC_CLEAR_CLASS(rest);
    OBJ_FREEZE_RAW(rest);
    if (NIL_P(name)) {
	st = anonymous_struct(klass);
    }
    else {
	st = new_struct(name, klass);
    }
    setup_struct(st, rest);
    rb_ivar_set(st, id_keyword_init, keyword_init);
    if (rb_block_given_p()) {
        rb_mod_module_eval(0, 0, st);
    }

    return st;
}

static long
num_members(VALUE klass)
{
    VALUE members;
    members = struct_ivar_get(klass, id_members);
    if (!RB_TYPE_P(members, T_ARRAY)) {
	rb_raise(rb_eTypeError, "broken members");
    }
    return RARRAY_LEN(members);
}

/*
 */

struct struct_hash_set_arg {
    VALUE self;
    VALUE unknown_keywords;
};

static int rb_struct_pos(VALUE s, VALUE *name);

static int
struct_hash_set_i(VALUE key, VALUE val, VALUE arg)
{
    struct struct_hash_set_arg *args = (struct struct_hash_set_arg *)arg;
    int i = rb_struct_pos(args->self, &key);
    if (i < 0) {
	if (NIL_P(args->unknown_keywords)) {
	    args->unknown_keywords = rb_ary_new();
	}
	rb_ary_push(args->unknown_keywords, key);
    }
    else {
	rb_struct_modify(args->self);
	RSTRUCT_SET(args->self, i, val);
    }
    return ST_CONTINUE;
}

static VALUE
rb_struct_initialize_m(int argc, const VALUE *argv, VALUE self)
{
    VALUE klass = rb_obj_class(self);
    rb_struct_modify(self);
    long n = num_members(klass);
    if (argc == 0) {
        rb_mem_clear((VALUE *)RSTRUCT_CONST_PTR(self), n);
        return Qnil;
    }

    VALUE keyword_init = rb_struct_s_keyword_init(klass);
    if (RTEST(keyword_init)) {
	struct struct_hash_set_arg arg;
	if (argc > 1 || !RB_TYPE_P(argv[0], T_HASH)) {
	    rb_raise(rb_eArgError, "wrong number of arguments (given %d, expected 0)", argc);
	}
	rb_mem_clear((VALUE *)RSTRUCT_CONST_PTR(self), n);
	arg.self = self;
	arg.unknown_keywords = Qnil;
	rb_hash_foreach(argv[0], struct_hash_set_i, (VALUE)&arg);
	if (arg.unknown_keywords != Qnil) {
	    rb_raise(rb_eArgError, "unknown keywords: %s",
		     RSTRING_PTR(rb_ary_join(arg.unknown_keywords, rb_str_new2(", "))));
	}
    }
    else {
	if (n < argc) {
	    rb_raise(rb_eArgError, "struct size differs");
	}
        if (NIL_P(keyword_init) && argc == 1 && RB_TYPE_P(argv[0], T_HASH) && rb_keyword_given_p()) {
            rb_warn("Passing only keyword arguments to Struct#initialize will behave differently from Ruby 3.2. "\
                    "Please use a Hash literal like .new({k: v}) instead of .new(k: v).");
        }
        for (long i=0; i<argc; i++) {
	    RSTRUCT_SET(self, i, argv[i]);
	}
	if (n > argc) {
	    rb_mem_clear((VALUE *)RSTRUCT_CONST_PTR(self)+argc, n-argc);
	}
    }
    return Qnil;
}

VALUE
rb_struct_initialize(VALUE self, VALUE values)
{
    rb_struct_initialize_m(RARRAY_LENINT(values), RARRAY_CONST_PTR(values), self);
    RB_GC_GUARD(values);
    return Qnil;
}

static VALUE *
struct_heap_alloc(VALUE st, size_t len)
{
    VALUE *ptr = rb_transient_heap_alloc((VALUE)st, sizeof(VALUE) * len);

    if (ptr) {
        RSTRUCT_TRANSIENT_SET(st);
        return ptr;
    }
    else {
        RSTRUCT_TRANSIENT_UNSET(st);
        return ALLOC_N(VALUE, len);
    }
}

#if USE_TRANSIENT_HEAP
void
rb_struct_transient_heap_evacuate(VALUE obj, int promote)
{
    if (RSTRUCT_TRANSIENT_P(obj)) {
        const VALUE *old_ptr = rb_struct_const_heap_ptr(obj);
        VALUE *new_ptr;
        long len = RSTRUCT_LEN(obj);

        if (promote) {
            new_ptr = ALLOC_N(VALUE, len);
            FL_UNSET_RAW(obj, RSTRUCT_TRANSIENT_FLAG);
        }
        else {
            new_ptr = struct_heap_alloc(obj, len);
        }
        MEMCPY(new_ptr, old_ptr, VALUE, len);
        RSTRUCT(obj)->as.heap.ptr = new_ptr;
    }
}
#endif

static VALUE
struct_alloc(VALUE klass)
{
    long n;
    NEWOBJ_OF(st, struct RStruct, klass, T_STRUCT | (RGENGC_WB_PROTECTED_STRUCT ? FL_WB_PROTECTED : 0));

    n = num_members(klass);

    if (0 < n && n <= RSTRUCT_EMBED_LEN_MAX) {
        RBASIC(st)->flags &= ~RSTRUCT_EMBED_LEN_MASK;
        RBASIC(st)->flags |= n << RSTRUCT_EMBED_LEN_SHIFT;
	rb_mem_clear((VALUE *)st->as.ary, n);
    }
    else {
        st->as.heap.ptr = struct_heap_alloc((VALUE)st, n);
        rb_mem_clear((VALUE *)st->as.heap.ptr, n);
        st->as.heap.len = n;
    }

    return (VALUE)st;
}

VALUE
rb_struct_alloc(VALUE klass, VALUE values)
{
    return rb_class_new_instance(RARRAY_LENINT(values), RARRAY_CONST_PTR(values), klass);
}

VALUE
rb_struct_new(VALUE klass, ...)
{
    VALUE tmpargs[16], *mem = tmpargs;
    int size, i;
    va_list args;

    size = rb_long2int(num_members(klass));
    if (size > numberof(tmpargs)) {
	tmpargs[0] = rb_ary_tmp_new(size);
	mem = RARRAY_PTR(tmpargs[0]);
    }
    va_start(args, klass);
    for (i=0; i<size; i++) {
	mem[i] = va_arg(args, VALUE);
    }
    va_end(args);

    return rb_class_new_instance(size, mem, klass);
}

static VALUE
struct_enum_size(VALUE s, VALUE args, VALUE eobj)
{
    return rb_struct_size(s);
}

/*
 *  call-seq:
 *    each {|value| ... } -> self
 *    each -> enumerator
 *
 *  Calls the given block with the value of each member; returns +self+:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.each {|value| p value }
 *
 *  Output:
 *
 *    "Joe Smith"
 *    "123 Maple, Anytown NC"
 *    12345
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: #each_pair.
 */

static VALUE
rb_struct_each(VALUE s)
{
    long i;

    RETURN_SIZED_ENUMERATOR(s, 0, 0, struct_enum_size);
    for (i=0; i<RSTRUCT_LEN(s); i++) {
	rb_yield(RSTRUCT_GET(s, i));
    }
    return s;
}

/*
 *  call-seq:
 *    each_pair {|(name, value)| ... } -> self
 *    each_pair -> enumerator
 *
 *  Calls the given block with each member name/value pair; returns +self+:
 *
 *    Customer = Struct.new(:name, :address, :zip) # => Customer
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.each_pair {|(name, value)| p "#{name} => #{value}" }
 *
 *  Output:
 *
 *    "name => Joe Smith"
 *    "address => 123 Maple, Anytown NC"
 *    "zip => 12345"
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: #each.
 *
 */

static VALUE
rb_struct_each_pair(VALUE s)
{
    VALUE members;
    long i;

    RETURN_SIZED_ENUMERATOR(s, 0, 0, struct_enum_size);
    members = rb_struct_members(s);
    if (rb_block_pair_yield_optimizable()) {
	for (i=0; i<RSTRUCT_LEN(s); i++) {
	    VALUE key = rb_ary_entry(members, i);
	    VALUE value = RSTRUCT_GET(s, i);
	    rb_yield_values(2, key, value);
	}
    }
    else {
	for (i=0; i<RSTRUCT_LEN(s); i++) {
	    VALUE key = rb_ary_entry(members, i);
	    VALUE value = RSTRUCT_GET(s, i);
	    rb_yield(rb_assoc_new(key, value));
	}
    }
    return s;
}

static VALUE
inspect_struct(VALUE s, VALUE dummy, int recur)
{
    VALUE cname = rb_class_path(rb_obj_class(s));
    VALUE members, str = rb_str_new2("#<struct ");
    long i, len;
    char first = RSTRING_PTR(cname)[0];

    if (recur || first != '#') {
	rb_str_append(str, cname);
    }
    if (recur) {
	return rb_str_cat2(str, ":...>");
    }

    members = rb_struct_members(s);
    len = RSTRUCT_LEN(s);

    for (i=0; i<len; i++) {
	VALUE slot;
	ID id;

	if (i > 0) {
	    rb_str_cat2(str, ", ");
	}
	else if (first != '#') {
	    rb_str_cat2(str, " ");
	}
	slot = RARRAY_AREF(members, i);
	id = SYM2ID(slot);
	if (rb_is_local_id(id) || rb_is_const_id(id)) {
	    rb_str_append(str, rb_id2str(id));
	}
	else {
	    rb_str_append(str, rb_inspect(slot));
	}
	rb_str_cat2(str, "=");
	rb_str_append(str, rb_inspect(RSTRUCT_GET(s, i)));
    }
    rb_str_cat2(str, ">");

    return str;
}

/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a string representation of +self+:
 *
 *    Customer = Struct.new(:name, :address, :zip) # => Customer
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.inspect # => "#<struct Customer name=\"Joe Smith\", address=\"123 Maple, Anytown NC\", zip=12345>"
 *
 *  Struct#to_s is an alias for Struct#inspect.
 *
 */

static VALUE
rb_struct_inspect(VALUE s)
{
    return rb_exec_recursive(inspect_struct, s, 0);
}

/*
 *  call-seq:
 *    to_a     -> array
 *
 *  Returns the values in +self+ as an array:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.to_a # => ["Joe Smith", "123 Maple, Anytown NC", 12345]
 *
 *  Struct#values and Struct#deconstruct are aliases for Struct#to_a.
 *
 *  Related: #members.
 */

static VALUE
rb_struct_to_a(VALUE s)
{
    return rb_ary_new4(RSTRUCT_LEN(s), RSTRUCT_CONST_PTR(s));
}

/*
 *  call-seq:
 *    to_h -> hash
 *    to_h {|name, value| ... } -> hash
 *
 *  Returns a hash containing the name and value for each member:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    h = joe.to_h
 *    h # => {:name=>"Joe Smith", :address=>"123 Maple, Anytown NC", :zip=>12345}
 *
 *  If a block is given, it is called with each name/value pair;
 *  the block should return a 2-element array whose elements will become
 *  a key/value pair in the returned hash:
 *
 *    h = joe.to_h{|name, value| [name.upcase, value.to_s.upcase]}
 *    h # => {:NAME=>"JOE SMITH", :ADDRESS=>"123 MAPLE, ANYTOWN NC", :ZIP=>"12345"}
 *
 *  Raises ArgumentError if the block returns an inappropriate value.
 *
 */

static VALUE
rb_struct_to_h(VALUE s)
{
    VALUE h = rb_hash_new_with_size(RSTRUCT_LEN(s));
    VALUE members = rb_struct_members(s);
    long i;
    int block_given = rb_block_given_p();

    for (i=0; i<RSTRUCT_LEN(s); i++) {
        VALUE k = rb_ary_entry(members, i), v = RSTRUCT_GET(s, i);
        if (block_given)
            rb_hash_set_pair(h, rb_yield_values(2, k, v));
        else
            rb_hash_aset(h, k, v);
    }
    return h;
}

/*
 *  call-seq:
 *    deconstruct_keys(array_of_names) -> hash
 *
 *  Returns a hash of the name/value pairs for the given member names.
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    h = joe.deconstruct_keys([:zip, :address])
 *    h # => {:zip=>12345, :address=>"123 Maple, Anytown NC"}
 *
 *  Returns all names and values if +array_of_names+ is +nil+:
 *
 *    h = joe.deconstruct_keys(nil)
 *    h # => {:name=>"Joseph Smith, Jr.", :address=>"123 Maple, Anytown NC", :zip=>12345}
 *
 */
static VALUE
rb_struct_deconstruct_keys(VALUE s, VALUE keys)
{
    VALUE h;
    long i;

    if (NIL_P(keys)) {
        return rb_struct_to_h(s);
    }
    if (UNLIKELY(!RB_TYPE_P(keys, T_ARRAY))) {
	rb_raise(rb_eTypeError,
                 "wrong argument type %"PRIsVALUE" (expected Array or nil)",
                 rb_obj_class(keys));

    }
    if (RSTRUCT_LEN(s) < RARRAY_LEN(keys)) {
        return rb_hash_new_with_size(0);
    }
    h = rb_hash_new_with_size(RARRAY_LEN(keys));
    for (i=0; i<RARRAY_LEN(keys); i++) {
        VALUE key = RARRAY_AREF(keys, i);
        int i = rb_struct_pos(s, &key);
        if (i < 0) {
            return h;
        }
        rb_hash_aset(h, key, RSTRUCT_GET(s, i));
    }
    return h;
}

/* :nodoc: */
VALUE
rb_struct_init_copy(VALUE copy, VALUE s)
{
    long i, len;

    if (!OBJ_INIT_COPY(copy, s)) return copy;
    if (RSTRUCT_LEN(copy) != RSTRUCT_LEN(s)) {
	rb_raise(rb_eTypeError, "struct size mismatch");
    }

    for (i=0, len=RSTRUCT_LEN(copy); i<len; i++) {
	RSTRUCT_SET(copy, i, RSTRUCT_GET(s, i));
    }

    return copy;
}

static int
rb_struct_pos(VALUE s, VALUE *name)
{
    long i;
    VALUE idx = *name;

    if (SYMBOL_P(idx)) {
	return struct_member_pos(s, idx);
    }
    else if (RB_TYPE_P(idx, T_STRING)) {
	idx = rb_check_symbol(name);
	if (NIL_P(idx)) return -1;
	return struct_member_pos(s, idx);
    }
    else {
	long len;
	i = NUM2LONG(idx);
	len = RSTRUCT_LEN(s);
	if (i < 0) {
	    if (i + len < 0) {
		*name = LONG2FIX(i);
		return -1;
	    }
	    i += len;
	}
	else if (len <= i) {
	    *name = LONG2FIX(i);
	    return -1;
	}
	return (int)i;
    }
}

static void
invalid_struct_pos(VALUE s, VALUE idx)
{
    if (FIXNUM_P(idx)) {
	long i = FIX2INT(idx), len = RSTRUCT_LEN(s);
	if (i < 0) {
	    rb_raise(rb_eIndexError, "offset %ld too small for struct(size:%ld)",
		     i, len);
	}
	else {
	    rb_raise(rb_eIndexError, "offset %ld too large for struct(size:%ld)",
		     i, len);
	}
    }
    else {
	rb_name_err_raise("no member '%1$s' in struct", s, idx);
    }
}

/*
 *  call-seq:
 *    struct[name] -> object
 *    struct[n] -> object
 *
 *  Returns a value from +self+.
 *
 *  With symbol or string argument +name+ given, returns the value for the named member:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe[:zip] # => 12345
 *
 *  Raises NameError if +name+ is not the name of a member.
 *
 *  With integer argument +n+ given, returns <tt>self.values[n]</tt>
 *  if +n+ is in range;
 *  see {Array Indexes}[Array.html#class-Array-label-Array+Indexes]:
 *
 *    joe[2]  # => 12345
 *    joe[-2] # => "123 Maple, Anytown NC"
 *
 *  Raises IndexError if +n+ is out of range.
 *
 */

VALUE
rb_struct_aref(VALUE s, VALUE idx)
{
    int i = rb_struct_pos(s, &idx);
    if (i < 0) invalid_struct_pos(s, idx);
    return RSTRUCT_GET(s, i);
}

/*
 *  call-seq:
 *    struct[name] = value -> value
 *    struct[n] = value -> value
 *
 *  Assigns a value to a member.
 *
 *  With symbol or string argument +name+ given, assigns the given +value+
 *  to the named member; returns +value+:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe[:zip] = 54321 # => 54321
 *    joe # => #<struct Customer name="Joe Smith", address="123 Maple, Anytown NC", zip=54321>
 *
 *  Raises NameError if +name+ is not the name of a member.
 *
 *  With integer argument +n+ given, assigns the given +value+
 *  to the +n+-th member if +n+ is in range;
 *  see {Array Indexes}[Array.html#class-Array-label-Array+Indexes]:
 *
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe[2] = 54321           # => 54321
 *    joe[-3] = 'Joseph Smith' # => "Joseph Smith"
 *    joe # => #<struct Customer name="Joseph Smith", address="123 Maple, Anytown NC", zip=54321>
 *
 *  Raises IndexError if +n+ is out of range.
 *
 */

VALUE
rb_struct_aset(VALUE s, VALUE idx, VALUE val)
{
    int i = rb_struct_pos(s, &idx);
    if (i < 0) invalid_struct_pos(s, idx);
    rb_struct_modify(s);
    RSTRUCT_SET(s, i, val);
    return val;
}

FUNC_MINIMIZED(VALUE rb_struct_lookup(VALUE s, VALUE idx));
NOINLINE(static VALUE rb_struct_lookup_default(VALUE s, VALUE idx, VALUE notfound));

VALUE
rb_struct_lookup(VALUE s, VALUE idx)
{
    return rb_struct_lookup_default(s, idx, Qnil);
}

static VALUE
rb_struct_lookup_default(VALUE s, VALUE idx, VALUE notfound)
{
    int i = rb_struct_pos(s, &idx);
    if (i < 0) return notfound;
    return RSTRUCT_GET(s, i);
}

static VALUE
struct_entry(VALUE s, long n)
{
    return rb_struct_aref(s, LONG2NUM(n));
}

/*
 *  call-seq:
 *    values_at(*integers) -> array
 *    values_at(integer_range) -> array
 *
 *  Returns an array of values from +self+.
 *
 *  With integer arguments +integers+ given,
 *  returns an array containing each value given by one of +integers+:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.values_at(0, 2)    # => ["Joe Smith", 12345]
 *    joe.values_at(2, 0)    # => [12345, "Joe Smith"]
 *    joe.values_at(2, 1, 0) # => [12345, "123 Maple, Anytown NC", "Joe Smith"]
 *    joe.values_at(0, -3)   # => ["Joe Smith", "Joe Smith"]
 *
 *  Raises IndexError if any of +integers+ is out of range;
 *  see {Array Indexes}[Array.html#class-Array-label-Array+Indexes].
 *
 *  With integer range argument +integer_range+ given,
 *  returns an array containing each value given by the elements of the range;
 *  fills with +nil+ values for range elements larger than the structure:
 *
 *    joe.values_at(0..2)
 *    # => ["Joe Smith", "123 Maple, Anytown NC", 12345]
 *    joe.values_at(-3..-1)
 *    # => ["Joe Smith", "123 Maple, Anytown NC", 12345]
 *    joe.values_at(1..4) # => ["123 Maple, Anytown NC", 12345, nil, nil]
 *
 *  Raises RangeError if any element of the range is negative and out of range;
 *  see {Array Indexes}[Array.html#class-Array-label-Array+Indexes].
 *
 */

static VALUE
rb_struct_values_at(int argc, VALUE *argv, VALUE s)
{
    return rb_get_values_at(s, RSTRUCT_LEN(s), argc, argv, struct_entry);
}

/*
 *  call-seq:
 *    select {|value| ... } -> array
 *    select -> enumerator
 *
 *  With a block given, returns an array of values from +self+
 *  for which the block returns a truthy value:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    a = joe.select {|value| value.is_a?(String) }
 *    a # => ["Joe Smith", "123 Maple, Anytown NC"]
 *    a = joe.select {|value| value.is_a?(Integer) }
 *    a # => [12345]
 *
 *  With no block given, returns an Enumerator.
 *
 *  Struct#filter is an alias for Struct#select.
 */

static VALUE
rb_struct_select(int argc, VALUE *argv, VALUE s)
{
    VALUE result;
    long i;

    rb_check_arity(argc, 0, 0);
    RETURN_SIZED_ENUMERATOR(s, 0, 0, struct_enum_size);
    result = rb_ary_new();
    for (i = 0; i < RSTRUCT_LEN(s); i++) {
	if (RTEST(rb_yield(RSTRUCT_GET(s, i)))) {
	    rb_ary_push(result, RSTRUCT_GET(s, i));
	}
    }

    return result;
}

static VALUE
recursive_equal(VALUE s, VALUE s2, int recur)
{
    long i, len;

    if (recur) return Qtrue; /* Subtle! */
    len = RSTRUCT_LEN(s);
    for (i=0; i<len; i++) {
        if (!rb_equal(RSTRUCT_GET(s, i), RSTRUCT_GET(s2, i))) return Qfalse;
    }
    return Qtrue;
}


/*
 *  call-seq:
 *    self == other -> true or false
 *
 *  Returns  +true+ if and only if the following are true; otherwise returns +false+:
 *
 *  - <tt>other.class == self.class</tt>.
 *  - For each member name +name+, <tt>other.name == self.name</tt>.
 *
 *  Examples:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe    = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe_jr = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe_jr == joe # => true
 *    joe_jr[:name] = 'Joe Smith, Jr.'
 *    # => "Joe Smith, Jr."
 *    joe_jr == joe # => false
 */

static VALUE
rb_struct_equal(VALUE s, VALUE s2)
{
    if (s == s2) return Qtrue;
    if (!RB_TYPE_P(s2, T_STRUCT)) return Qfalse;
    if (rb_obj_class(s) != rb_obj_class(s2)) return Qfalse;
    if (RSTRUCT_LEN(s) != RSTRUCT_LEN(s2)) {
	rb_bug("inconsistent struct"); /* should never happen */
    }

    return rb_exec_recursive_paired(recursive_equal, s, s2, s2);
}

/*
 *  call-seq:
 *    hash -> integer
 *
 *  Returns the integer hash value for +self+.
 *
 *  Two structs of the same class and with the same content
 *  will have the same hash code (and will compare using Struct#eql?):
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe    = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe_jr = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.hash == joe_jr.hash # => true
 *    joe_jr[:name] = 'Joe Smith, Jr.'
 *    joe.hash == joe_jr.hash # => false
 *
 *  Related: Object#hash.
 */

static VALUE
rb_struct_hash(VALUE s)
{
    long i, len;
    st_index_t h;
    VALUE n;

    h = rb_hash_start(rb_hash(rb_obj_class(s)));
    len = RSTRUCT_LEN(s);
    for (i = 0; i < len; i++) {
        n = rb_hash(RSTRUCT_GET(s, i));
	h = rb_hash_uint(h, NUM2LONG(n));
    }
    h = rb_hash_end(h);
    return ST2FIX(h);
}

static VALUE
recursive_eql(VALUE s, VALUE s2, int recur)
{
    long i, len;

    if (recur) return Qtrue; /* Subtle! */
    len = RSTRUCT_LEN(s);
    for (i=0; i<len; i++) {
        if (!rb_eql(RSTRUCT_GET(s, i), RSTRUCT_GET(s2, i))) return Qfalse;
    }
    return Qtrue;
}

/*
 * call-seq:
 *   eql?(other) -> true or false
 *
 *  Returns +true+ if and only if the following are true; otherwise returns +false+:
 *
 *  - <tt>other.class == self.class</tt>.
 *  - For each member name +name+, <tt>other.name.eql?(self.name)</tt>.
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe    = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe_jr = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe_jr.eql?(joe) # => true
 *    joe_jr[:name] = 'Joe Smith, Jr.'
 *    joe_jr.eql?(joe) # => false
 *
 *  Related: Object#==.
 */

static VALUE
rb_struct_eql(VALUE s, VALUE s2)
{
    if (s == s2) return Qtrue;
    if (!RB_TYPE_P(s2, T_STRUCT)) return Qfalse;
    if (rb_obj_class(s) != rb_obj_class(s2)) return Qfalse;
    if (RSTRUCT_LEN(s) != RSTRUCT_LEN(s2)) {
	rb_bug("inconsistent struct"); /* should never happen */
    }

    return rb_exec_recursive_paired(recursive_eql, s, s2, s2);
}

/*
 *  call-seq:
 *    size -> integer
 *
 *  Returns the number of members.
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.size #=> 3
 *
 *  Struct#length is an alias for Struct#size.
 */

VALUE
rb_struct_size(VALUE s)
{
    return LONG2FIX(RSTRUCT_LEN(s));
}

/*
 * call-seq:
 *   dig(name, *identifiers) -> object
 *   dig(n, *identifiers) -> object
 *
 *  Finds and returns an object among nested objects.
 *  The nested objects may be instances of various classes.
 *  See {Dig Methods}[rdoc-ref:dig_methods.rdoc].
 *
 *
 *  Given symbol or string argument +name+,
 *  returns the object that is specified by +name+ and +identifiers+:
 *
 *   Foo = Struct.new(:a)
 *   f = Foo.new(Foo.new({b: [1, 2, 3]}))
 *   f.dig(:a) # => #<struct Foo a={:b=>[1, 2, 3]}>
 *   f.dig(:a, :a) # => {:b=>[1, 2, 3]}
 *   f.dig(:a, :a, :b) # => [1, 2, 3]
 *   f.dig(:a, :a, :b, 0) # => 1
 *   f.dig(:b, 0) # => nil
 *
 *  Given integer argument +n+,
 *  returns the object that is specified by +n+ and +identifiers+:
 *
 *   f.dig(0) # => #<struct Foo a={:b=>[1, 2, 3]}>
 *   f.dig(0, 0) # => {:b=>[1, 2, 3]}
 *   f.dig(0, 0, :b) # => [1, 2, 3]
 *   f.dig(0, 0, :b, 0) # => 1
 *   f.dig(:b, 0) # => nil
 *
 */

static VALUE
rb_struct_dig(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    self = rb_struct_lookup(self, *argv);
    if (!--argc) return self;
    ++argv;
    return rb_obj_dig(argc, argv, self, Qnil);
}

/*
 *  Document-class: Struct
 *
 *  \Class \Struct provides a convenient way to create a simple class
 *  that can store and fetch values.
 *
 *  This example creates a subclass of +Struct+, <tt>Struct::Customer</tt>;
 *  the first argument, a string, is the name of the subclass;
 *  the other arguments, symbols, determine the _members_ of the new subclass.
 *
 *    Customer = Struct.new('Customer', :name, :address, :zip)
 *    Customer.name       # => "Struct::Customer"
 *    Customer.class      # => Class
 *    Customer.superclass # => Struct
 *
 *  Corresponding to each member are two methods, a writer and a reader,
 *  that store and fetch values:
 *
 *    methods = Customer.instance_methods false
 *    methods # => [:zip, :address=, :zip=, :address, :name, :name=]
 *
 *  An instance of the subclass may be created,
 *  and its members assigned values, via method <tt>::new</tt>:
 *
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe # => #<struct Struct::Customer name="Joe Smith", address="123 Maple, Anytown NC", zip=12345>
 *
 *  The member values may be managed thus:
 *
 *    joe.name    # => "Joe Smith"
 *    joe.name = 'Joseph Smith'
 *    joe.name    # => "Joseph Smith"
 *
 *  And thus; note that member name may be expressed as either a string or a symbol:
 *
 *    joe[:name]  # => "Joseph Smith"
 *    joe[:name] = 'Joseph Smith, Jr.'
 *    joe['name'] # => "Joseph Smith, Jr."
 *
 *  See Struct::new.
 *
 *  == What's Here
 *
 *  First, what's elsewhere. \Class \Struct:
 *
 *  - Inherits from {class Object}[Object.html#class-Object-label-What-27s+Here].
 *  - Includes {module Enumerable}[Enumerable.html#module-Enumerable-label-What-27s+Here],
 *    which provides dozens of additional methods.
 *
 *  Here, class \Struct provides methods that are useful for:
 *
 *  - {Creating a Struct Subclass}[#class-Struct-label-Methods+for+Creating+a+Struct+Subclass]
 *  - {Querying}[#class-Struct-label-Methods+for+Querying]
 *  - {Comparing}[#class-Struct-label-Methods+for+Comparing]
 *  - {Fetching}[#class-Struct-label-Methods+for+Fetching]
 *  - {Assigning}[#class-Struct-label-Methods+for+Assigning]
 *  - {Iterating}[#class-Struct-label-Methods+for+Iterating]
 *  - {Converting}[#class-Struct-label-Methods+for+Converting]
 *
 *  === Methods for Creating a Struct Subclass
 *
 *  ::new:: Returns a new subclass of \Struct.
 *
 *  === Methods for Querying
 *
 *  #hash:: Returns the integer hash code.
 *  #length, #size:: Returns the number of members.
 *
 *  === Methods for Comparing
 *
 *  {#==}[#method-i-3D-3D]:: Returns whether a given object is equal to +self+,
 *                           using <tt>==</tt> to compare member values.
 *  #eql?:: Returns whether a given object is equal to +self+,
 *          using <tt>eql?</tt> to compare member values.
 *
 *  === Methods for Fetching
 *
 *  #[]:: Returns the value associated with a given member name.
 *  #to_a, #values, #deconstruct:: Returns the member values in +self+ as an array.
 *  #deconstruct_keys:: Returns a hash of the name/value pairs
 *                      for given member names.
 *  #dig:: Returns the object in nested objects that is specified
 *         by a given member name and additional arguments.
 *  #members:: Returns an array of the member names.
 *  #select, #filter:: Returns an array of member values from +self+,
 *                     as selected by the given block.
 *  #values_at:: Returns an array containing values for given member names.
 *
 *  === Methods for Assigning
 *
 *  #[]=:: Assigns a given value to a given member name.
 *
 *  === Methods for Iterating
 *
 *  #each:: Calls a given block with each member name.
 *  #each_pair:: Calls a given block with each member name/value pair.
 *
 *  === Methods for Converting
 *
 *  #inspect, #to_s:: Returns a string representation of +self+.
 *  #to_h:: Returns a hash of the member name/value pairs in +self+.
 *
 */
void
InitVM_Struct(void)
{
    rb_cStruct = rb_define_class("Struct", rb_cObject);
    rb_include_module(rb_cStruct, rb_mEnumerable);

    rb_undef_alloc_func(rb_cStruct);
    rb_define_singleton_method(rb_cStruct, "new", rb_struct_s_def, -1);
#if 0 /* for RDoc */
    rb_define_singleton_method(rb_cStruct, "keyword_init?", rb_struct_s_keyword_init_p, 0);
    rb_define_singleton_method(rb_cStruct, "members", rb_struct_s_members_m, 0);
#endif

    rb_define_method(rb_cStruct, "initialize", rb_struct_initialize_m, -1);
    rb_define_method(rb_cStruct, "initialize_copy", rb_struct_init_copy, 1);

    rb_define_method(rb_cStruct, "==", rb_struct_equal, 1);
    rb_define_method(rb_cStruct, "eql?", rb_struct_eql, 1);
    rb_define_method(rb_cStruct, "hash", rb_struct_hash, 0);

    rb_define_method(rb_cStruct, "inspect", rb_struct_inspect, 0);
    rb_define_alias(rb_cStruct,  "to_s", "inspect");
    rb_define_method(rb_cStruct, "to_a", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "to_h", rb_struct_to_h, 0);
    rb_define_method(rb_cStruct, "values", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "size", rb_struct_size, 0);
    rb_define_method(rb_cStruct, "length", rb_struct_size, 0);

    rb_define_method(rb_cStruct, "each", rb_struct_each, 0);
    rb_define_method(rb_cStruct, "each_pair", rb_struct_each_pair, 0);
    rb_define_method(rb_cStruct, "[]", rb_struct_aref, 1);
    rb_define_method(rb_cStruct, "[]=", rb_struct_aset, 2);
    rb_define_method(rb_cStruct, "select", rb_struct_select, -1);
    rb_define_method(rb_cStruct, "filter", rb_struct_select, -1);
    rb_define_method(rb_cStruct, "values_at", rb_struct_values_at, -1);

    rb_define_method(rb_cStruct, "members", rb_struct_members_m, 0);
    rb_define_method(rb_cStruct, "dig", rb_struct_dig, -1);

    rb_define_method(rb_cStruct, "deconstruct", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "deconstruct_keys", rb_struct_deconstruct_keys, 1);
}

#undef rb_intern
void
Init_Struct(void)
{
    id_members = rb_intern("__members__");
    id_back_members = rb_intern("__members_back__");
    id_keyword_init = rb_intern("__keyword_init__");

    InitVM(Struct);
}
