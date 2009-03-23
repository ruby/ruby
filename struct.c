/**********************************************************************

  struct.c -

  $Author$
  $Date$
  created at: Tue Mar 22 18:44:30 JST 1995

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "env.h"

VALUE rb_cStruct;

static VALUE struct_alloc _((VALUE));

VALUE
rb_struct_iv_get(c, name)
    VALUE c;
    const char *name;
{
    ID id;

    id = rb_intern(name);
    for (;;) {
	if (rb_ivar_defined(c, id))
	    return rb_ivar_get(c, id);
	c = RCLASS(c)->super;
	if (c == 0 || c == rb_cStruct)
	    return Qnil;
    }
}

VALUE
rb_struct_s_members(klass)
    VALUE klass;
{
    VALUE members = rb_struct_iv_get(klass, "__members__");

    if (NIL_P(members)) {
	rb_raise(rb_eTypeError, "uninitialized struct");
    }
    if (TYPE(members) != T_ARRAY) {
	rb_raise(rb_eTypeError, "corrupted struct");
    }
    return members;
}

VALUE
rb_struct_members(s)
    VALUE s;
{
    VALUE members = rb_struct_s_members(rb_obj_class(s));

    if (RSTRUCT(s)->len != RARRAY(members)->len) {
	rb_raise(rb_eTypeError, "struct size differs (%d required %d given)",
		 RARRAY(members)->len, RSTRUCT(s)->len);
    }
    return members;
}

static VALUE
rb_struct_s_members_m(klass)
    VALUE klass;
{
    VALUE members, ary;
    VALUE *p, *pend;

    members = rb_struct_s_members(klass);
    ary = rb_ary_new2(RARRAY(members)->len);
    p = RARRAY(members)->ptr; pend = p + RARRAY(members)->len;
    while (p < pend) {
	rb_ary_push(ary, rb_str_new2(rb_id2name(SYM2ID(*p))));
	p++;
    }

    return ary;
}

/*
 *  call-seq:
 *     struct.members    => array
 *  
 *  Returns an array of strings representing the names of the instance
 *  variables.
 *     
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.members   #=> ["name", "address", "zip"]
 */

static VALUE
rb_struct_members_m(obj)
    VALUE obj;
{
    return rb_struct_s_members_m(rb_obj_class(obj));
}

VALUE
rb_struct_getmember(obj, id)
    VALUE obj;
    ID id;
{
    VALUE members, slot;
    long i;

    members = rb_struct_members(obj);
    slot = ID2SYM(id);
    for (i=0; i<RARRAY(members)->len; i++) {
	if (RARRAY(members)->ptr[i] == slot) {
	    return RSTRUCT(obj)->ptr[i];
	}
    }
    rb_name_error(id, "%s is not struct member", rb_id2name(id));
    return Qnil;		/* not reached */
}

static VALUE
rb_struct_ref(obj)
    VALUE obj;
{
    return rb_struct_getmember(obj, ruby_frame->orig_func);
}

static VALUE rb_struct_ref0(obj) VALUE obj; {return RSTRUCT(obj)->ptr[0];}
static VALUE rb_struct_ref1(obj) VALUE obj; {return RSTRUCT(obj)->ptr[1];}
static VALUE rb_struct_ref2(obj) VALUE obj; {return RSTRUCT(obj)->ptr[2];}
static VALUE rb_struct_ref3(obj) VALUE obj; {return RSTRUCT(obj)->ptr[3];}
static VALUE rb_struct_ref4(obj) VALUE obj; {return RSTRUCT(obj)->ptr[4];}
static VALUE rb_struct_ref5(obj) VALUE obj; {return RSTRUCT(obj)->ptr[5];}
static VALUE rb_struct_ref6(obj) VALUE obj; {return RSTRUCT(obj)->ptr[6];}
static VALUE rb_struct_ref7(obj) VALUE obj; {return RSTRUCT(obj)->ptr[7];}
static VALUE rb_struct_ref8(obj) VALUE obj; {return RSTRUCT(obj)->ptr[8];}
static VALUE rb_struct_ref9(obj) VALUE obj; {return RSTRUCT(obj)->ptr[9];}

static VALUE (*ref_func[10])() = {
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
rb_struct_modify(s)
    VALUE s;
{
    if (OBJ_FROZEN(s)) rb_error_frozen("Struct");
    if (!OBJ_TAINTED(s) && rb_safe_level() >= 4)
       rb_raise(rb_eSecurityError, "Insecure: can't modify Struct");
}

static VALUE
rb_struct_set(obj, val)
    VALUE obj, val;
{
    VALUE members, slot;
    ID id;
    long i;

    members = rb_struct_members(obj);
    rb_struct_modify(obj);
    id = ruby_frame->orig_func;
    for (i=0; i<RARRAY(members)->len; i++) {
	slot = RARRAY(members)->ptr[i];
	if (rb_id_attrset(SYM2ID(slot)) == id) {
	    return RSTRUCT(obj)->ptr[i] = val;
	}
    }
    rb_name_error(ruby_frame->last_func, "`%s' is not a struct member",
		  rb_id2name(id));
    return Qnil;		/* not reached */
}

static VALUE
make_struct(name, members, klass)
    VALUE name, members, klass;
{
    VALUE nstr;
    ID id;
    long i;

    OBJ_FREEZE(members);
    if (NIL_P(name)) {
	nstr = rb_class_new(klass);
	rb_make_metaclass(nstr, RBASIC(klass)->klass);
	rb_class_inherited(klass, nstr);
    }
    else {
	char *cname = StringValuePtr(name);
	id = rb_intern(cname);
	if (!rb_is_const_id(id)) {
	    rb_name_error(id, "identifier %s needs to be constant", cname);
	}
	if (rb_const_defined_at(klass, id)) {
	    rb_warn("redefining constant Struct::%s", cname);
	    rb_mod_remove_const(klass, ID2SYM(id));
	}
	nstr = rb_define_class_under(klass, rb_id2name(id), klass);
    }
    rb_iv_set(nstr, "__members__", members);

    rb_define_alloc_func(nstr, struct_alloc);
    rb_define_singleton_method(nstr, "new", rb_class_new_instance, -1);
    rb_define_singleton_method(nstr, "[]", rb_class_new_instance, -1);
    rb_define_singleton_method(nstr, "members", rb_struct_s_members_m, 0);
    for (i=0; i< RARRAY(members)->len; i++) {
	ID id = SYM2ID(RARRAY(members)->ptr[i]);
	if (rb_is_local_id(id) || rb_is_const_id(id)) {
	    if (i<10) {
		rb_define_method_id(nstr, id, ref_func[i], 0);
	    }
	    else {
		rb_define_method_id(nstr, id, rb_struct_ref, 0);
	    }
	    rb_define_method_id(nstr, rb_id_attrset(id), rb_struct_set, 1);
	}
    }

    return nstr;
}

#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif

VALUE
#ifdef HAVE_STDARG_PROTOTYPES
rb_struct_define(const char *name, ...)
#else
rb_struct_define(name, va_alist)
    const char *name;
    va_dcl
#endif
{
    va_list ar;
    VALUE nm, ary;
    char *mem;

    if (!name) nm = Qnil;
    else nm = rb_str_new2(name);
    ary = rb_ary_new();

    va_init_list(ar, name);
    while ((mem = va_arg(ar, char*)) != 0) {
	ID slot = rb_intern(mem);
	rb_ary_push(ary, ID2SYM(slot));
    }
    va_end(ar);

    return make_struct(nm, ary, rb_cStruct);
}

/*
 *  call-seq:
 *     Struct.new( [aString] [, aSym]+> )    => StructClass
 *     StructClass.new(arg, ...)             => obj
 *     StructClass[arg, ...]                 => obj
 *
 *  Creates a new class, named by <i>aString</i>, containing accessor
 *  methods for the given symbols. If the name <i>aString</i> is
 *  omitted, an anonymous structure class will be created. Otherwise,
 *  the name of this struct will appear as a constant in class
 *  <code>Struct</code>, so it must be unique for all
 *  <code>Struct</code>s in the system and should start with a capital
 *  letter. Assigning a structure class to a constant effectively gives
 *  the class the name of the constant.
 *     
 *  <code>Struct::new</code> returns a new <code>Class</code> object,
 *  which can then be used to create specific instances of the new
 *  structure. The number of actual parameters must be
 *  less than or equal to the number of attributes defined for this
 *  class; unset parameters default to \nil{}.  Passing too many
 *  parameters will raise an \E{ArgumentError}.
 *
 *  The remaining methods listed in this section (class and instance)
 *  are defined for this generated class. 
 *     
 *     # Create a structure with a name in Struct
 *     Struct.new("Customer", :name, :address)    #=> Struct::Customer
 *     Struct::Customer.new("Dave", "123 Main")   #=> #<Struct::Customer name="Dave", address="123 Main">
 *     
 *     # Create a structure named by its constant
 *     Customer = Struct.new(:name, :address)     #=> Customer
 *     Customer.new("Dave", "123 Main")           #=> #<Customer name="Dave", address="123 Main">
 */

static VALUE
rb_struct_s_def(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE name, rest;
    long i;
    VALUE st;
    ID id;

    rb_scan_args(argc, argv, "1*", &name, &rest);
    if (!NIL_P(name) && SYMBOL_P(name)) {
	rb_ary_unshift(rest, name);
	name = Qnil;
    }
    for (i=0; i<RARRAY(rest)->len; i++) {
	id = rb_to_id(RARRAY(rest)->ptr[i]);
	RARRAY(rest)->ptr[i] = ID2SYM(id);
    }
    st = make_struct(name, rest, klass);
    if (rb_block_given_p()) {
	rb_mod_module_eval(0, 0, st);
    }

    return st;
}

static size_t num_members _((VALUE));

static size_t
num_members(klass)
    VALUE klass;
{
    VALUE members;
    members = rb_struct_iv_get(klass, "__members__");
    if (TYPE(members) != T_ARRAY) {
       rb_raise(rb_eTypeError, "broken members");
    }
    return RARRAY_LEN(members);
}

/*
 */

static VALUE
rb_struct_initialize(self, values)
    VALUE self, values;
{
    VALUE klass = rb_obj_class(self);
    long n;

    rb_struct_modify(self);
    n = num_members(klass);
    if (n < RARRAY(values)->len) {
	rb_raise(rb_eArgError, "struct size differs");
    }
    MEMCPY(RSTRUCT(self)->ptr, RARRAY(values)->ptr, VALUE, RARRAY(values)->len);
    if (n > RARRAY(values)->len) {
	rb_mem_clear(RSTRUCT(self)->ptr+RARRAY(values)->len,
		     n-RARRAY(values)->len);
    }
    return Qnil;
}

static VALUE
struct_alloc(klass)
    VALUE klass;
{
    long n;
    NEWOBJ(st, struct RStruct);
    OBJSETUP(st, klass, T_STRUCT);

    n = num_members(klass);

    st->ptr = ALLOC_N(VALUE, n);
    rb_mem_clear(st->ptr, n);
    st->len = n;

    return (VALUE)st;
}

VALUE
rb_struct_alloc(klass, values)
    VALUE klass, values;
{
    return rb_class_new_instance(RARRAY(values)->len, RARRAY(values)->ptr, klass);
}

VALUE
#ifdef HAVE_STDARG_PROTOTYPES
rb_struct_new(VALUE klass, ...)
#else
rb_struct_new(klass, va_alist)
    VALUE klass;
    va_dcl
#endif
{
    VALUE *mem;
    long size, i;
    va_list args;

    size = num_members(klass);
    mem = ALLOCA_N(VALUE, size);
    va_init_list(args, klass);
    for (i=0; i<size; i++) {
	mem[i] = va_arg(args, VALUE);
    }
    va_end(args);

    return rb_class_new_instance(size, mem, klass);
}

/*
 *  call-seq:
 *     struct.each {|obj| block }  => struct
 *  
 *  Calls <i>block</i> once for each instance variable, passing the
 *  value as a parameter.
 *     
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.each {|x| puts(x) }
 *     
 *  <em>produces:</em>
 *     
 *     Joe Smith
 *     123 Maple, Anytown NC
 *     12345
 */

static VALUE
rb_struct_each(s)
    VALUE s;
{
    long i;

    RETURN_ENUMERATOR(s, 0, 0);
    for (i=0; i<RSTRUCT(s)->len; i++) {
	rb_yield(RSTRUCT(s)->ptr[i]);
    }
    return s;
}

/*
 *  call-seq:
 *     struct.each_pair {|sym, obj| block }     => struct
 *  
 *  Calls <i>block</i> once for each instance variable, passing the name
 *  (as a symbol) and the value as parameters.
 *     
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.each_pair {|name, value| puts("#{name} => #{value}") }
 *     
 *  <em>produces:</em>
 *     
 *     name => Joe Smith
 *     address => 123 Maple, Anytown NC
 *     zip => 12345
 */

static VALUE
rb_struct_each_pair(s)
    VALUE s;
{
    VALUE members;
    long i;

    RETURN_ENUMERATOR(s, 0, 0);
    members = rb_struct_members(s);
    for (i=0; i<RSTRUCT(s)->len; i++) {
	rb_yield_values(2, rb_ary_entry(members, i), RSTRUCT(s)->ptr[i]);
    }
    return s;
}

static VALUE
inspect_struct(s)
    VALUE s;
{
    const char *cname = rb_class2name(rb_obj_class(s));
    VALUE str, members;
    long i;

    members = rb_struct_members(s);
    str = rb_str_buf_new2("#<struct ");
    rb_str_cat2(str, cname);
    rb_str_cat2(str, " ");
    for (i=0; i<RSTRUCT(s)->len; i++) {
	VALUE slot;
	ID id;
	const char *p;

	if (i > 0) {
	    rb_str_cat2(str, ", ");
	}
	slot = RARRAY(members)->ptr[i];
	id = SYM2ID(slot);
	if (rb_is_local_id(id) || rb_is_const_id(id)) {
	    p = rb_id2name(id);
	    rb_str_cat2(str, p);
	}
	else {
	    rb_str_append(str, rb_inspect(slot));
	}
	rb_str_cat2(str, "=");
	rb_str_append(str, rb_inspect(RSTRUCT(s)->ptr[i]));
    }
    rb_str_cat2(str, ">");
    OBJ_INFECT(str, s);

    return str;
}

/*
 * call-seq:
 *   struct.to_s      => string
 *   struct.inspect   => string
 *
 * Describe the contents of this struct in a string.
 */

static VALUE
rb_struct_inspect(s)
    VALUE s;
{
    if (rb_inspecting_p(s)) {
	const char *cname = rb_class2name(rb_obj_class(s));
	size_t len = strlen(cname) + 14;
	VALUE str = rb_str_new(0, len);

	snprintf(RSTRING(str)->ptr, len+1, "#<struct %s:...>", cname);
	RSTRING(str)->len = strlen(RSTRING(str)->ptr);
	return str;
    }
    return rb_protect_inspect(inspect_struct, s, 0);
}

/*
 *  call-seq:
 *     struct.to_a     => array
 *     struct.values   => array
 *  
 *  Returns the values for this instance as an array.
 *     
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.to_a[1]   #=> "123 Maple, Anytown NC"
 */

static VALUE
rb_struct_to_a(s)
    VALUE s;
{
    return rb_ary_new4(RSTRUCT(s)->len, RSTRUCT(s)->ptr);
}

/* :nodoc: */
static VALUE
rb_struct_init_copy(copy, s)
    VALUE copy, s;
{
    if (copy == s) return copy;
    rb_check_frozen(copy);
    if (!rb_obj_is_instance_of(s, rb_obj_class(copy))) {
	rb_raise(rb_eTypeError, "wrong argument class");
    }
    if (RSTRUCT(copy)->len != RSTRUCT(s)->len) {
	rb_raise(rb_eTypeError, "struct size mismatch");
    }
    MEMCPY(RSTRUCT(copy)->ptr, RSTRUCT(s)->ptr, VALUE, RSTRUCT(copy)->len);

    return copy;
}

static VALUE
rb_struct_aref_id(s, id)
    VALUE s;
    ID id;
{
    VALUE members;
    long i, len;

    members = rb_struct_members(s);
    len = RARRAY(members)->len;
    for (i=0; i<len; i++) {
	if (SYM2ID(RARRAY(members)->ptr[i]) == id) {
	    return RSTRUCT(s)->ptr[i];
	}
    }
    rb_name_error(id, "no member '%s' in struct", rb_id2name(id));
    return Qnil;		/* not reached */
}

/*
 *  call-seq:
 *     struct[symbol]    => anObject
 *     struct[fixnum]    => anObject 
 *  
 *  Attribute Reference---Returns the value of the instance variable
 *  named by <i>symbol</i>, or indexed (0..length-1) by
 *  <i>fixnum</i>. Will raise <code>NameError</code> if the named
 *  variable does not exist, or <code>IndexError</code> if the index is
 *  out of range.
 *     
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     
 *     joe["name"]   #=> "Joe Smith"
 *     joe[:name]    #=> "Joe Smith"
 *     joe[0]        #=> "Joe Smith"
 */

VALUE
rb_struct_aref(s, idx)
    VALUE s, idx;
{
    long i;

    if (TYPE(idx) == T_STRING || TYPE(idx) == T_SYMBOL) {
	return rb_struct_aref_id(s, rb_to_id(idx));
    }

    i = NUM2LONG(idx);
    if (i < 0) i = RSTRUCT(s)->len + i;
    if (i < 0)
        rb_raise(rb_eIndexError, "offset %ld too small for struct(size:%ld)",
		 i, RSTRUCT(s)->len);
    if (RSTRUCT(s)->len <= i)
        rb_raise(rb_eIndexError, "offset %ld too large for struct(size:%ld)",
		 i, RSTRUCT(s)->len);
    return RSTRUCT(s)->ptr[i];
}

static VALUE
rb_struct_aset_id(s, id, val)
    VALUE s, val;
    ID id;
{
    VALUE members;
    long i, len;

    members = rb_struct_members(s);
    rb_struct_modify(s);
    len = RARRAY(members)->len;
    if (RSTRUCT(s)->len != RARRAY(members)->len) {
	rb_raise(rb_eTypeError, "struct size differs (%d required %d given)",
		 RARRAY(members)->len, RSTRUCT(s)->len);
    }
    for (i=0; i<len; i++) {
	if (SYM2ID(RARRAY(members)->ptr[i]) == id) {
	    RSTRUCT(s)->ptr[i] = val;
	    return val;
	}
    }
    rb_name_error(id, "no member '%s' in struct", rb_id2name(id));
}

/*
 *  call-seq:
 *     struct[symbol] = obj    => obj
 *     struct[fixnum] = obj    => obj
 *  
 *  Attribute Assignment---Assigns to the instance variable named by
 *  <i>symbol</i> or <i>fixnum</i> the value <i>obj</i> and
 *  returns it. Will raise a <code>NameError</code> if the named
 *  variable does not exist, or an <code>IndexError</code> if the index
 *  is out of range.
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
rb_struct_aset(s, idx, val)
    VALUE s, idx, val;
{
    long i;

    if (TYPE(idx) == T_STRING || TYPE(idx) == T_SYMBOL) {
	return rb_struct_aset_id(s, rb_to_id(idx), val);
    }

    i = NUM2LONG(idx);
    if (i < 0) i = RSTRUCT(s)->len + i;
    if (i < 0) {
        rb_raise(rb_eIndexError, "offset %ld too small for struct(size:%ld)",
		 i, RSTRUCT(s)->len);
    }
    if (RSTRUCT(s)->len <= i) {
        rb_raise(rb_eIndexError, "offset %ld too large for struct(size:%ld)",
		 i, RSTRUCT(s)->len);
    }
    rb_struct_modify(s);
    return RSTRUCT(s)->ptr[i] = val;
}

static VALUE struct_entry _((VALUE, long));
static VALUE
struct_entry(s, n)
    VALUE s;
    long n;
{
    return rb_struct_aref(s, LONG2NUM(n));
}

/* 
 * call-seq:
 *   struct.values_at(selector,... )  => an_array
 *
 *   Returns an array containing the elements in
 *   _self_ corresponding to the given selector(s). The selectors
 *   may be either integer indices or ranges. 
 *   See also </code>.select<code>.
 * 
 *      a = %w{ a b c d e f }
 *      a.values_at(1, 3, 5)
 *      a.values_at(1, 3, 5, 7)
 *      a.values_at(-1, -3, -5, -7)
 *      a.values_at(1..3, 2...5)
 */

static VALUE
rb_struct_values_at(argc, argv, s)
    int argc;
    VALUE *argv;
    VALUE s;
{
    return rb_values_at(s, RSTRUCT(s)->len, argc, argv, struct_entry);
}

/*
 *  call-seq:
 *     struct.select {|i| block }    => array
 *  
 *  Invokes the block passing in successive elements from
 *  <i>struct</i>, returning an array containing those elements
 *  for which the block returns a true value (equivalent to
 *  <code>Enumerable#select</code>).
 *     
 *     Lots = Struct.new(:a, :b, :c, :d, :e, :f)
 *     l = Lots.new(11, 22, 33, 44, 55, 66)
 *     l.select {|v| (v % 2).zero? }   #=> [22, 44, 66]
 */

static VALUE
rb_struct_select(argc, argv, s)
    int argc;
    VALUE *argv;
    VALUE s;
{
    VALUE result;
    long i;

    if (argc > 0) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)", argc);
    }
    result = rb_ary_new();
    for (i = 0; i < RSTRUCT(s)->len; i++) {
	if (RTEST(rb_yield(RSTRUCT(s)->ptr[i]))) {
	    rb_ary_push(result, RSTRUCT(s)->ptr[i]);
	}
    }

    return result;
}

/*
 *  call-seq:
 *     struct == other_struct     => true or false
 *  
 *  Equality---Returns <code>true</code> if <i>other_struct</i> is
 *  equal to this one: they must be of the same class as generated by
 *  <code>Struct::new</code>, and the values of all instance variables
 *  must be equal (according to <code>Object#==</code>).
 *     
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe   = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joejr = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     jane  = Customer.new("Jane Doe", "456 Elm, Anytown NC", 12345)
 *     joe == joejr   #=> true
 *     joe == jane    #=> false
 */

static VALUE
rb_struct_equal(s, s2)
    VALUE s, s2;
{
    long i;

    if (s == s2) return Qtrue;
    if (TYPE(s2) != T_STRUCT) return Qfalse;
    if (rb_obj_class(s) != rb_obj_class(s2)) return Qfalse;
    if (RSTRUCT(s)->len != RSTRUCT(s2)->len) {
	rb_bug("inconsistent struct"); /* should never happen */
    }

    for (i=0; i<RSTRUCT(s)->len; i++) {
	if (!rb_equal(RSTRUCT(s)->ptr[i], RSTRUCT(s2)->ptr[i])) return Qfalse;
    }
    return Qtrue;
}

/*
 * call-seq:
 *   struct.hash   => fixnum
 *
 * Return a hash value based on this struct's contents.
 */

static VALUE
rb_struct_hash(s)
    VALUE s;
{
    long i, h;
    VALUE n;

    h = rb_hash(rb_obj_class(s));
    for (i = 0; i < RSTRUCT(s)->len; i++) {
	h = (h << 1) | (h<0 ? 1 : 0);
	n = rb_hash(RSTRUCT(s)->ptr[i]);
	h ^= NUM2LONG(n);
    }
    return LONG2FIX(h);
}

/*
 * code-seq:
 *   struct.eql?(other)   => true or false
 *
 * Two structures are equal if they are the same object, or if all their
 * fields are equal (using <code>eql?</code>).
 */

static VALUE
rb_struct_eql(s, s2)
    VALUE s, s2;
{
    long i;

    if (s == s2) return Qtrue;
    if (TYPE(s2) != T_STRUCT) return Qfalse;
    if (rb_obj_class(s) != rb_obj_class(s2)) return Qfalse;
    if (RSTRUCT(s)->len != RSTRUCT(s2)->len) {
	rb_bug("inconsistent struct"); /* should never happen */
    }

    for (i=0; i<RSTRUCT(s)->len; i++) {
	if (!rb_eql(RSTRUCT(s)->ptr[i], RSTRUCT(s2)->ptr[i])) return Qfalse;
    }
    return Qtrue;
}

/*
 *  call-seq:
 *     struct.length    => fixnum
 *     struct.size      => fixnum
 *  
 *  Returns the number of instance variables.
 *     
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe.length   #=> 3
 */

static VALUE
rb_struct_size(s)
    VALUE s;
{
    return LONG2FIX(RSTRUCT(s)->len);
}

/*
 *  A <code>Struct</code> is a convenient way to bundle a number of
 *  attributes together, using accessor methods, without having to write
 *  an explicit class.
 *     
 *  The <code>Struct</code> class is a generator of specific classes,
 *  each one of which is defined to hold a set of variables and their
 *  accessors. In these examples, we'll call the generated class
 *  ``<i>Customer</i>Class,'' and we'll show an example instance of that
 *  class as ``<i>Customer</i>Inst.''
 *     
 *  In the descriptions that follow, the parameter <i>symbol</i> refers
 *  to a symbol, which is either a quoted string or a
 *  <code>Symbol</code> (such as <code>:name</code>).
 */
void
Init_Struct()
{
    rb_cStruct = rb_define_class("Struct", rb_cObject);
    rb_include_module(rb_cStruct, rb_mEnumerable);

    rb_undef_alloc_func(rb_cStruct);
    rb_define_singleton_method(rb_cStruct, "new", rb_struct_s_def, -1);

    rb_define_method(rb_cStruct, "initialize", rb_struct_initialize, -2);
    rb_define_method(rb_cStruct, "initialize_copy", rb_struct_init_copy, 1);

    rb_define_method(rb_cStruct, "==", rb_struct_equal, 1);
    rb_define_method(rb_cStruct, "eql?", rb_struct_eql, 1);
    rb_define_method(rb_cStruct, "hash", rb_struct_hash, 0);

    rb_define_method(rb_cStruct, "to_s", rb_struct_inspect, 0);
    rb_define_method(rb_cStruct, "inspect", rb_struct_inspect, 0);
    rb_define_method(rb_cStruct, "to_a", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "values", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "size", rb_struct_size, 0);
    rb_define_method(rb_cStruct, "length", rb_struct_size, 0);

    rb_define_method(rb_cStruct, "each", rb_struct_each, 0);
    rb_define_method(rb_cStruct, "each_pair", rb_struct_each_pair, 0);
    rb_define_method(rb_cStruct, "[]", rb_struct_aref, 1);
    rb_define_method(rb_cStruct, "[]=", rb_struct_aset, 2);
    rb_define_method(rb_cStruct, "select", rb_struct_select, -1);
    rb_define_method(rb_cStruct, "values_at", rb_struct_values_at, -1);

    rb_define_method(rb_cStruct, "members", rb_struct_members_m, 0);
}
