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

const rb_iseq_t *rb_method_for_self_aref(VALUE name, VALUE arg, const struct rb_builtin_function *func);
const rb_iseq_t *rb_method_for_self_aset(VALUE name, VALUE arg, const struct rb_builtin_function *func);

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

static VALUE
rb_struct_s_members_m(VALUE klass)
{
    VALUE members = rb_struct_s_members(klass);

    return rb_ary_dup(members);
}

/*
 *  call-seq:
 *     struct.members    -> array
 *
 *  Returns the struct members as an array of symbols:
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.members   #=> [:name, :address, :zip]
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

static VALUE rb_struct_ref0(VALUE obj) {return RSTRUCT_GET(obj, 0);}
static VALUE rb_struct_ref1(VALUE obj) {return RSTRUCT_GET(obj, 1);}
static VALUE rb_struct_ref2(VALUE obj) {return RSTRUCT_GET(obj, 2);}
static VALUE rb_struct_ref3(VALUE obj) {return RSTRUCT_GET(obj, 3);}
static VALUE rb_struct_ref4(VALUE obj) {return RSTRUCT_GET(obj, 4);}
static VALUE rb_struct_ref5(VALUE obj) {return RSTRUCT_GET(obj, 5);}
static VALUE rb_struct_ref6(VALUE obj) {return RSTRUCT_GET(obj, 6);}
static VALUE rb_struct_ref7(VALUE obj) {return RSTRUCT_GET(obj, 7);}
static VALUE rb_struct_ref8(VALUE obj) {return RSTRUCT_GET(obj, 8);}
static VALUE rb_struct_ref9(VALUE obj) {return RSTRUCT_GET(obj, 9);}

#define N_REF_FUNC numberof(ref_func)

static VALUE (*const ref_func[])(VALUE) = {
    rb_struct_ref0,
    rb_struct_ref1,
    rb_struct_ref2,
    rb_struct_ref3,
    rb_struct_ref4,
    rb_struct_ref5,
    rb_struct_ref6,
    rb_struct_ref7,
    rb_struct_ref8,
    rb_struct_ref9,
};

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
        rb_category_warn("redefine",
                "redefining constant %"PRIsVALUE"::%"PRIsVALUE, super, name);
	rb_mod_remove_const(super, ID2SYM(id));
    }
    return rb_define_class_id_under(super, id, super);
}

NORETURN(static void invalid_struct_pos(VALUE s, VALUE idx));

static inline long
struct_pos_num(VALUE s, VALUE idx)
{
    long i = NUM2INT(idx);
    if (i < 0 || i >= RSTRUCT_LEN(s)) invalid_struct_pos(s, idx);
    return i;
}

static VALUE
opt_struct_aref(rb_execution_context_t *ec, VALUE self, VALUE idx)
{
    long i = struct_pos_num(self, idx);
    return RSTRUCT_GET(self, i);
}

static VALUE
opt_struct_aset(rb_execution_context_t *ec, VALUE self, VALUE val, VALUE idx)
{
    long i = struct_pos_num(self, idx);
    rb_struct_modify(self);
    RSTRUCT_SET(self, i, val);
    return val;
}

static const struct rb_builtin_function struct_aref_builtin =
    RB_BUILTIN_FUNCTION(0, struct_aref, opt_struct_aref, 1, 0);
static const struct rb_builtin_function struct_aset_builtin =
    RB_BUILTIN_FUNCTION(1, struct_aref, opt_struct_aset, 2, 0);

static void
define_aref_method(VALUE nstr, VALUE name, VALUE off)
{
    const rb_iseq_t *iseq = rb_method_for_self_aref(name, off, &struct_aref_builtin);
    iseq->body->builtin_inline_p = true;

    rb_add_method_iseq(nstr, SYM2ID(name), iseq, NULL, METHOD_VISI_PUBLIC);
}

static void
define_aset_method(VALUE nstr, VALUE name, VALUE off)
{
    const rb_iseq_t *iseq = rb_method_for_self_aset(name, off, &struct_aset_builtin);

    rb_add_method_iseq(nstr, SYM2ID(name), iseq, NULL, METHOD_VISI_PUBLIC);
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
    len = RARRAY_LEN(members);
    for (i=0; i< len; i++) {
        VALUE sym = RARRAY_AREF(members, i);
        ID id = SYM2ID(sym);
	VALUE off = LONG2NUM(i);

	if (i < N_REF_FUNC) {
	    rb_define_method_id(nstr, id, ref_func[i], 0);
	}
	else {
            define_aref_method(nstr, sym, off);
	}
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
 *    Struct.new([class_name] [, member_name]+)                        -> StructClass
 *    Struct.new([class_name] [, member_name]+, keyword_init: true)    -> StructClass
 *    Struct.new([class_name] [, member_name]+) {|StructClass| block } -> StructClass
 *    StructClass.new(value, ...)                                      -> object
 *    StructClass[value, ...]                                          -> object
 *
 *  The first two forms are used to create a new Struct subclass +class_name+
 *  that can contain a value for each +member_name+.  This subclass can be
 *  used to create instances of the structure like any other Class.
 *
 *  If the +class_name+ is omitted an anonymous structure class will be
 *  created.  Otherwise, the name of this struct will appear as a constant in
 *  class Struct, so it must be unique for all Structs in the system and
 *  must start with a capital letter.  Assigning a structure class to a
 *  constant also gives the class the name of the constant.
 *
 *     # Create a structure with a name under Struct
 *     Struct.new("Customer", :name, :address)
 *     #=> Struct::Customer
 *     Struct::Customer.new("Dave", "123 Main")
 *     #=> #<struct Struct::Customer name="Dave", address="123 Main">
 *
 *     # Create a structure named by its constant
 *     Customer = Struct.new(:name, :address)
 *     #=> Customer
 *     Customer.new("Dave", "123 Main")
 *     #=> #<struct Customer name="Dave", address="123 Main">
 *
 *  If the optional +keyword_init+ keyword argument is set to +true+,
 *  .new takes keyword arguments instead of normal arguments.
 *
 *     Customer = Struct.new(:name, :address, keyword_init: true)
 *     Customer.new(name: "Dave", address: "123 Main")
 *     #=> #<struct Customer name="Dave", address="123 Main">
 *
 *  If a block is given it will be evaluated in the context of
 *  +StructClass+, passing the created class as a parameter:
 *
 *     Customer = Struct.new(:name, :address) do
 *       def greeting
 *         "Hello #{name}!"
 *       end
 *     end
 *     Customer.new("Dave", "123 Main").greeting  #=> "Hello Dave!"
 *
 *  This is the recommended way to customize a struct.  Subclassing an
 *  anonymous struct creates an extra anonymous class that will never be used.
 *
 *  The last two forms create a new instance of a struct subclass.  The number
 *  of +value+ parameters must be less than or equal to the number of
 *  attributes defined for the structure.  Unset parameters default to +nil+.
 *  Passing more parameters than number of attributes will raise
 *  an ArgumentError.
 *
 *     Customer = Struct.new(:name, :address)
 *     Customer.new("Dave", "123 Main")
 *     #=> #<struct Customer name="Dave", address="123 Main">
 *     Customer["Dave"]
 *     #=> #<struct Customer name="Dave", address=nil>
 */

static VALUE
rb_struct_s_def(int argc, VALUE *argv, VALUE klass)
{
    VALUE name, rest, keyword_init = Qfalse;
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
            keyword_init = Qfalse;
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
	if (args->unknown_keywords == Qnil) {
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
    long i, n;

    rb_struct_modify(self);
    n = num_members(klass);
    if (argc > 0 && RTEST(rb_struct_s_keyword_init(klass))) {
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
	for (i=0; i<argc; i++) {
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
    VALUE tmpargs[N_REF_FUNC], *mem = tmpargs;
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
 *     struct.each {|obj| block }  -> struct
 *     struct.each                 -> enumerator
 *
 *  Yields the value of each struct member in order.  If no block is given an
 *  enumerator is returned.
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.each {|x| puts(x) }
 *
 *  Produces:
 *
 *     Joe Smith
 *     123 Maple, Anytown NC
 *     12345
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
 *     struct.each_pair {|sym, obj| block }     -> struct
 *     struct.each_pair                         -> enumerator
 *
 *  Yields the name and value of each struct member in order.  If no block is
 *  given an enumerator is returned.
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.each_pair {|name, value| puts("#{name} => #{value}") }
 *
 *  Produces:
 *
 *     name => Joe Smith
 *     address => 123 Maple, Anytown NC
 *     zip => 12345
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
 * call-seq:
 *   struct.to_s      -> string
 *   struct.inspect   -> string
 *
 * Returns a description of this struct as a string.
 */

static VALUE
rb_struct_inspect(VALUE s)
{
    return rb_exec_recursive(inspect_struct, s, 0);
}

/*
 *  call-seq:
 *     struct.to_a     -> array
 *     struct.values   -> array
 *
 *  Returns the values for this struct as an Array.
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.to_a[1]   #=> "123 Maple, Anytown NC"
 */

static VALUE
rb_struct_to_a(VALUE s)
{
    return rb_ary_new4(RSTRUCT_LEN(s), RSTRUCT_CONST_PTR(s));
}

/*
 *  call-seq:
 *     struct.to_h                        -> hash
 *     struct.to_h {|name, value| block } -> hash
 *
 *  Returns a Hash containing the names and values for the struct's members.
 *
 *  If a block is given, the results of the block on each pair of the receiver
 *  will be used as pairs.
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.to_h[:address]   #=> "123 Maple, Anytown NC"
 *     joe.to_h{|name, value| [name.upcase, value.to_s.upcase]}[:ADDRESS]
 *                          #=> "123 MAPLE, ANYTOWN NC"
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

    if (RB_TYPE_P(idx, T_SYMBOL)) {
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
 *     struct[member]   -> object
 *     struct[index]    -> object
 *
 *  Attribute Reference---Returns the value of the given struct +member+ or
 *  the member at the given +index+.   Raises NameError if the +member+ does
 *  not exist and IndexError if the +index+ is out of range.
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *
 *     joe["name"]   #=> "Joe Smith"
 *     joe[:name]    #=> "Joe Smith"
 *     joe[0]        #=> "Joe Smith"
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
 *     struct[member] = obj    -> obj
 *     struct[index]  = obj    -> obj
 *
 *  Attribute Assignment---Sets the value of the given struct +member+ or
 *  the member at the given +index+.  Raises NameError if the +member+ does not
 *  exist and IndexError if the +index+ is out of range.
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *
 *     joe["name"] = "Luke"
 *     joe[:zip]   = "90210"
 *
 *     joe.name   #=> "Luke"
 *     joe.zip    #=> "90210"
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
 *     struct.values_at(selector, ...)  -> array
 *
 *  Returns the struct member values for each +selector+ as an Array.  A
 *  +selector+ may be either an Integer offset or a Range of offsets (as in
 *  Array#values_at).
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.values_at(0, 2)   #=> ["Joe Smith", 12345]
 *
 */

static VALUE
rb_struct_values_at(int argc, VALUE *argv, VALUE s)
{
    return rb_get_values_at(s, RSTRUCT_LEN(s), argc, argv, struct_entry);
}

/*
 *  call-seq:
 *     struct.select {|obj| block }  -> array
 *     struct.select                 -> enumerator
 *     struct.filter {|obj| block }  -> array
 *     struct.filter                 -> enumerator
 *
 *  Yields each member value from the struct to the block and returns an Array
 *  containing the member values from the +struct+ for which the given block
 *  returns a true value (equivalent to Enumerable#select).
 *
 *     Lots = Struct.new(:a, :b, :c, :d, :e, :f)
 *     l = Lots.new(11, 22, 33, 44, 55, 66)
 *     l.select {|v| v.even? }   #=> [22, 44, 66]
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
 *     struct == other     -> true or false
 *
 *  Equality---Returns +true+ if +other+ has the same struct subclass and has
 *  equal member values (according to Object#==).
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe   = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joejr = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     jane  = Customer.new("Jane Doe", "456 Elm, Anytown NC", 12345)
 *     joe == joejr   #=> true
 *     joe == jane    #=> false
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
 * call-seq:
 *   struct.hash   -> integer
 *
 * Returns a hash value based on this struct's contents.
 *
 * See also Object#hash.
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
 *   struct.eql?(other)   -> true or false
 *
 * Hash equality---+other+ and +struct+ refer to the same hash key if they
 * have the same struct subclass and have equal member values (according to
 * Object#eql?).
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
 *     struct.length    -> integer
 *     struct.size      -> integer
 *
 *  Returns the number of struct members.
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.length   #=> 3
 */

VALUE
rb_struct_size(VALUE s)
{
    return LONG2FIX(RSTRUCT_LEN(s));
}

/*
 * call-seq:
 *   struct.dig(key, *identifiers) -> object
 *
 * Finds and returns the object in nested objects
 * that is specified by +key+ and +identifiers+.
 * The nested objects may be instances of various classes.
 * See {Dig Methods}[rdoc-ref:doc/dig_methods.rdoc].
 *
 * Examples:
 *   Foo = Struct.new(:a)
 *   f = Foo.new(Foo.new({b: [1, 2, 3]}))
 *   f.dig(:a) # => #<struct Foo a={:b=>[1, 2, 3]}>
 *   f.dig(:a, :a) # => {:b=>[1, 2, 3]}
 *   f.dig(:a, :a, :b) # => [1, 2, 3]
 *   f.dig(:a, :a, :b, 0) # => 1
 *   f.dig(:b, 0) # => nil
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
 *  A Struct is a convenient way to bundle a number of attributes together,
 *  using accessor methods, without having to write an explicit class.
 *
 *  The Struct class generates new subclasses that hold a set of members and
 *  their values.  For each member a reader and writer method is created
 *  similar to Module#attr_accessor.
 *
 *     Customer = Struct.new(:name, :address) do
 *       def greeting
 *         "Hello #{name}!"
 *       end
 *     end
 *
 *     dave = Customer.new("Dave", "123 Main")
 *     dave.name     #=> "Dave"
 *     dave.greeting #=> "Hello Dave!"
 *
 *  See Struct::new for further examples of creating struct subclasses and
 *  instances.
 *
 *  In the method descriptions that follow, a "member" parameter refers to a
 *  struct member which is either a quoted string (<code>"name"</code>) or a
 *  Symbol (<code>:name</code>).
 */
void
InitVM_Struct(void)
{
    rb_cStruct = rb_define_class("Struct", rb_cObject);
    rb_include_module(rb_cStruct, rb_mEnumerable);

    rb_undef_alloc_func(rb_cStruct);
    rb_define_singleton_method(rb_cStruct, "new", rb_struct_s_def, -1);

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
