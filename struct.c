/**********************************************************************

  struct.c -

  $Author$
  $Date$
  created at: Tue Mar 22 18:44:30 JST 1995

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"

VALUE rb_cStruct;

static VALUE struct_alloc _((VALUE));

VALUE
rb_struct_iv_get(c, name)
    VALUE c;
    char *name;
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

static VALUE
rb_struct_s_members(obj)
    VALUE obj;
{
    VALUE member, ary;
    VALUE *p, *pend;

    member = rb_struct_iv_get(obj, "__member__");
    if (NIL_P(member)) {
	rb_bug("uninitialized struct");
    }
    ary = rb_ary_new2(RARRAY(member)->len);
    p = RARRAY(member)->ptr; pend = p + RARRAY(member)->len;
    while (p < pend) {
	rb_ary_push(ary, rb_str_new2(rb_id2name(SYM2ID(*p))));
	p++;
    }

    return ary;
}

static VALUE
rb_struct_members(obj)
    VALUE obj;
{
    return rb_struct_s_members(rb_obj_class(obj));
}

VALUE
rb_struct_getmember(obj, id)
    VALUE obj;
    ID id;
{
    VALUE member, slot;
    long i;

    member = rb_struct_iv_get(rb_obj_class(obj), "__member__");
    if (NIL_P(member)) {
	rb_bug("uninitialized struct");
    }
    slot = ID2SYM(id);
    for (i=0; i<RARRAY(member)->len; i++) {
	if (RARRAY(member)->ptr[i] == slot) {
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
    return rb_struct_getmember(obj, rb_frame_last_func());
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
    VALUE member, slot;
    long i;

    member = rb_struct_iv_get(rb_obj_class(obj), "__member__");
    if (NIL_P(member)) {
	rb_bug("uninitialized struct");
    }
    rb_struct_modify(obj);
    for (i=0; i<RARRAY(member)->len; i++) {
	slot = RARRAY(member)->ptr[i];
	if (rb_id_attrset(SYM2ID(slot)) == rb_frame_last_func()) {
	    return RSTRUCT(obj)->ptr[i] = val;
	}
    }
    rb_name_error(rb_frame_last_func(), "`%s' is not a struct member",
		  rb_id2name(rb_frame_last_func()));
    return Qnil;		/* not reached */
}

static VALUE
make_struct(name, member, klass)
    VALUE name, member, klass;
{
    VALUE nstr;
    ID id;
    long i;

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
	nstr = rb_define_class_under(klass, cname, klass);
    }
    rb_iv_set(nstr, "__size__", LONG2NUM(RARRAY(member)->len));
    rb_iv_set(nstr, "__member__", member);

    rb_define_alloc_func(nstr, struct_alloc);
    rb_define_singleton_method(nstr, "new", rb_class_new_instance, -1);
    rb_define_singleton_method(nstr, "[]", rb_class_new_instance, -1);
    rb_define_singleton_method(nstr, "members", rb_struct_s_members, 0);
    for (i=0; i< RARRAY(member)->len; i++) {
	ID id = SYM2ID(RARRAY(member)->ptr[i]);
	if (i<10) {
	    rb_define_method_id(nstr, id, ref_func[i], 0);
	}
	else {
	    rb_define_method_id(nstr, id, rb_struct_ref, 0);
	}
	rb_define_method_id(nstr, rb_id_attrset(id), rb_struct_set, 1);
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
    while (mem = va_arg(ar, char*)) {
	ID slot = rb_intern(mem);
	rb_ary_push(ary, ID2SYM(slot));
    }
    va_end(ar);

    return make_struct(nm, ary, rb_cStruct);
}

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
    for (i=0; i<RARRAY(rest)->len; i++) {
	id = rb_to_id(RARRAY(rest)->ptr[i]);
	RARRAY(rest)->ptr[i] = ID2SYM(id);
    }
    if (!NIL_P(name) && TYPE(name) != T_STRING) {
	id = rb_to_id(name);
	rb_ary_unshift(rest, ID2SYM(id));
	name = Qnil;
    }
    st = make_struct(name, rest, klass);

    return st;
}

static VALUE
rb_struct_initialize(self, values)
    VALUE self, values;
{
    VALUE klass = rb_obj_class(self);
    VALUE size;
    long n;

    rb_struct_modify(self);
    size = rb_struct_iv_get(klass, "__size__");
    n = FIX2LONG(size);
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
    VALUE size;
    long n;
    NEWOBJ(st, struct RStruct);
    OBJSETUP(st, klass, T_STRUCT);

    size = rb_struct_iv_get(klass, "__size__");
    n = FIX2LONG(size);

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
    VALUE sz, *mem;
    long size, i;
    va_list args;

    sz = rb_struct_iv_get(klass, "__size__");
    size = FIX2LONG(sz); 
    mem = ALLOCA_N(VALUE, size);
    va_init_list(args, klass);
    for (i=0; i<size; i++) {
	mem[i] = va_arg(args, VALUE);
    }
    va_end(args);

    return rb_class_new_instance(size, mem, klass);
}

static VALUE
rb_struct_each(s)
    VALUE s;
{
    long i;

    for (i=0; i<RSTRUCT(s)->len; i++) {
	rb_yield(RSTRUCT(s)->ptr[i]);
    }
    return s;
}

static VALUE
rb_struct_each_pair(s)
    VALUE s;
{
    VALUE member;
    long i;

    member = rb_struct_iv_get(rb_obj_class(s), "__member__");
    if (NIL_P(member)) {
	rb_bug("non-initialized struct");
    }
    for (i=0; i<RSTRUCT(s)->len; i++) {
	rb_yield_values(2, RARRAY(member)->ptr[i], RSTRUCT(s)->ptr[i]);
    }
    return s;
}

static VALUE
inspect_struct(s)
    VALUE s;
{
    char *cname = rb_class2name(rb_obj_class(s));
    VALUE str, member;
    long i;

    member = rb_struct_iv_get(rb_obj_class(s), "__member__");
    if (NIL_P(member)) {
	rb_bug("non-initialized struct");
    }

    str = rb_str_buf_new2("#<struct ");
    rb_str_cat2(str, cname);
    rb_str_cat2(str, " ");
    for (i=0; i<RSTRUCT(s)->len; i++) {
	VALUE str2, slot;
	char *p;

	if (i > 0) {
	    rb_str_cat2(str, ", ");
	}
	slot = RARRAY(member)->ptr[i];
	p = rb_id2name(SYM2ID(slot));
	rb_str_cat2(str, p);
	rb_str_cat2(str, "=");
	str2 = rb_inspect(RSTRUCT(s)->ptr[i]);
	rb_str_append(str, str2);
    }
    rb_str_cat2(str, ">");
    OBJ_INFECT(str, s);

    return str;
}

static VALUE
rb_struct_inspect(s)
    VALUE s;
{
    if (rb_inspecting_p(s)) {
	char *cname = rb_class2name(rb_obj_class(s));
	VALUE str = rb_str_new(0, strlen(cname) + 15);

	sprintf(RSTRING(str)->ptr, "#<struct %s:...>", cname);
	RSTRING(str)->len = strlen(RSTRING(str)->ptr);
	return str;
    }
    return rb_protect_inspect(inspect_struct, s, 0);
}

static VALUE
rb_struct_to_a(s)
    VALUE s;
{
    return rb_ary_new4(RSTRUCT(s)->len, RSTRUCT(s)->ptr);
}

static VALUE
rb_struct_init_copy(copy, s)
    VALUE copy, s;
{
    if (copy == s) return copy;
    rb_check_frozen(copy);
    if (!rb_obj_is_instance_of(s, rb_obj_class(copy))) {
	rb_raise(rb_eTypeError, "wrong argument class");
    }
    RSTRUCT(copy)->ptr = ALLOC_N(VALUE, RSTRUCT(s)->len);
    RSTRUCT(copy)->len = RSTRUCT(s)->len;
    MEMCPY(RSTRUCT(copy)->ptr, RSTRUCT(s)->ptr, VALUE, RSTRUCT(copy)->len);

    return copy;
}

static VALUE
rb_struct_aref_id(s, id)
    VALUE s;
    ID id;
{
    VALUE member;
    long i, len;

    member = rb_struct_iv_get(rb_obj_class(s), "__member__");
    if (NIL_P(member)) {
	rb_bug("non-initialized struct");
    }

    len = RARRAY(member)->len;
    for (i=0; i<len; i++) {
	if (SYM2ID(RARRAY(member)->ptr[i]) == id) {
	    return RSTRUCT(s)->ptr[i];
	}
    }
    rb_name_error(id, "no member '%s' in struct", rb_id2name(id));
    return Qnil;		/* not reached */
}

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
    VALUE member;
    long i, len;

    member = rb_struct_iv_get(rb_obj_class(s), "__member__");
    if (NIL_P(member)) {
	rb_bug("non-initialized struct");
    }

    rb_struct_modify(s);
    len = RARRAY(member)->len;
    for (i=0; i<len; i++) {
	if (SYM2ID(RARRAY(member)->ptr[i]) == id) {
	    RSTRUCT(s)->ptr[i] = val;
	    return val;
	}
    }
    rb_name_error(id, "no member '%s' in struct", rb_id2name(id));
}

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

static VALUE
rb_struct_values_at(argc, argv, s)
    int argc;
    VALUE *argv;
    VALUE s;
{
    return rb_values_at(s, RSTRUCT(s)->len, argc, argv, struct_entry);
}

static VALUE
rb_struct_select(argc, argv, s)
    int argc;
    VALUE *argv;
    VALUE s;
{
    VALUE result;
    long i;

    if (argc > 0) {
	rb_raise(rb_eArgError, "wrong number arguments(%d for 0)", argc);
    }
    result = rb_ary_new();
    for (i = 0; i < RSTRUCT(s)->len; i++) {
	if (RTEST(rb_yield(RSTRUCT(s)->ptr[i]))) {
	    rb_ary_push(result, RSTRUCT(s)->ptr[i]);
	}
    }

    return result;
}

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

static VALUE
rb_struct_size(s)
    VALUE s;
{
    return LONG2FIX(RSTRUCT(s)->len);
}

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

    rb_define_method(rb_cStruct, "members", rb_struct_members, 0);
}
