/**********************************************************************

  struct.c -

  $Author$
  $Date$
  created at: Tue Mar 22 18:44:30 JST 1995

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"

VALUE rb_cStruct;

static VALUE struct_alloc _((int, VALUE*, VALUE));

static VALUE
class_of(obj)
    VALUE obj;
{
    obj = CLASS_OF(obj);
    if (FL_TEST(obj, FL_SINGLETON))
	return RCLASS(obj)->super;
    return obj;
}

static VALUE
iv_get(obj, name)
    VALUE obj;
    char *name;
{
    ID id;

    id = rb_intern(name);
    for (;;) {
	if (rb_ivar_defined(obj, id))
	    return rb_ivar_get(obj, id);
	obj = RCLASS(obj)->super;
	if (obj == 0 || obj == rb_cStruct)
	    return Qnil;
    }
}

static VALUE
rb_struct_s_members(obj)
    VALUE obj;
{
    VALUE member, ary;
    VALUE *p, *pend;

    member = iv_get(obj, "__member__");
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
    return rb_struct_s_members(class_of(obj));
}

VALUE
rb_struct_getmember(obj, id)
    VALUE obj;
    ID id;
{
    VALUE member, slot;
    long i;

    member = iv_get(class_of(obj), "__member__");
    if (NIL_P(member)) {
	rb_bug("uninitialized struct");
    }
    slot = ID2SYM(id);
    for (i=0; i<RARRAY(member)->len; i++) {
	if (RARRAY(member)->ptr[i] == slot) {
	    return RSTRUCT(obj)->ptr[i];
	}
    }
    rb_raise(rb_eNameError, "%s is not struct member", rb_id2name(id));
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

    member = iv_get(class_of(obj), "__member__");
    if (NIL_P(member)) {
	rb_bug("non-initialized struct");
    }
    rb_struct_modify(obj);
    for (i=0; i<RARRAY(member)->len; i++) {
	slot = RARRAY(member)->ptr[i];
	if (rb_id_attrset(SYM2ID(slot)) == rb_frame_last_func()) {
	    return RSTRUCT(obj)->ptr[i] = val;
	}
    }
    rb_raise(rb_eNameError, "not struct member");
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
    }
    else {
	char *cname = STR2CSTR(name);
	id = rb_intern(cname);
	if (!rb_is_const_id(id)) {
	    rb_raise(rb_eNameError, "identifier %s needs to be constant", cname);
	}
	nstr = rb_define_class_under(klass, cname, klass);
    }
    rb_iv_set(nstr, "__size__", INT2NUM(RARRAY(member)->len));
    rb_iv_set(nstr, "__member__", member);

    rb_define_singleton_method(nstr, "new", struct_alloc, -1);
    rb_define_singleton_method(nstr, "[]", struct_alloc, -1);
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
    VALUE klass = CLASS_OF(self);
    VALUE size;
    long n;

    rb_struct_modify(self);
    size = iv_get(klass, "__size__");
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
struct_alloc(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE size;
    long n;

    NEWOBJ(st, struct RStruct);
    OBJSETUP(st, klass, T_STRUCT);

    size = iv_get(klass, "__size__");
    n = FIX2LONG(size);

    st->ptr = ALLOC_N(VALUE, n);
    rb_mem_clear(st->ptr, n);
    st->len = n;
    rb_obj_call_init((VALUE)st, argc, argv);

    return (VALUE)st;
}

VALUE
rb_struct_alloc(klass, values)
    VALUE klass, values;
{
    return struct_alloc(RARRAY(values)->len, RARRAY(values)->ptr, klass);
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

    sz = iv_get(klass, "__size__");
    size = FIX2LONG(sz); 
    mem = ALLOCA_N(VALUE, size);
    va_init_list(args, klass);
    for (i=0; i<size; i++) {
	mem[i] = va_arg(args, VALUE);
    }
    va_end(args);

    return struct_alloc(size, mem, klass);
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
rb_struct_to_s(s)
    VALUE s;
{
    char *cname = rb_class2name(CLASS_OF(s));
    VALUE str = rb_str_new(0, strlen(cname) + 4);

    sprintf(RSTRING(str)->ptr, "#<%s>", cname);
    RSTRING(str)->len = strlen(RSTRING(str)->ptr);
    return str;
}

static VALUE
inspect_struct(s)
    VALUE s;
{
    char *cname = rb_class2name(CLASS_OF(s));
    VALUE str, member;
    long i;

    member = iv_get(CLASS_OF(s), "__member__");
    if (NIL_P(member)) {
	rb_bug("non-initialized struct");
    }

    str = rb_str_new2("#<");
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
	char *cname = rb_class2name(CLASS_OF(s));
	VALUE str = rb_str_new(0, strlen(cname) + 8);

	sprintf(RSTRING(str)->ptr, "#<%s:...>", cname);
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
rb_struct_clone(s)
    VALUE s;
{
    NEWOBJ(clone, struct RStruct);
    CLONESETUP(clone, s);
    clone->ptr = ALLOC_N(VALUE, RSTRUCT(s)->len);
    clone->len = RSTRUCT(s)->len;
    MEMCPY(clone->ptr, RSTRUCT(s)->ptr, VALUE, clone->len);

    return (VALUE)clone;
}

static VALUE
rb_struct_aref_id(s, id)
    VALUE s;
    ID id;
{
    VALUE member;
    long i, len;

    member = iv_get(CLASS_OF(s), "__member__");
    if (NIL_P(member)) {
	rb_bug("non-initialized struct");
    }

    len = RARRAY(member)->len;
    for (i=0; i<len; i++) {
	if (SYM2ID(RARRAY(member)->ptr[i]) == id) {
	    return RSTRUCT(s)->ptr[i];
	}
    }
    rb_raise(rb_eNameError, "no member '%s' in struct", rb_id2name(id));
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
        rb_raise(rb_eIndexError, "offset %d too small for struct(size:%d)",
		 i, RSTRUCT(s)->len);
    if (RSTRUCT(s)->len <= i)
        rb_raise(rb_eIndexError, "offset %d too large for struct(size:%d)",
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

    member = iv_get(CLASS_OF(s), "__member__");
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
    rb_raise(rb_eNameError, "no member '%s' in struct", rb_id2name(id));
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
        rb_raise(rb_eIndexError, "offset %d too small for struct(size:%d)",
		 i, RSTRUCT(s)->len);
    }
    if (RSTRUCT(s)->len <= i) {
        rb_raise(rb_eIndexError, "offset %d too large for struct(size:%d)",
		 i, RSTRUCT(s)->len);
    }
    rb_struct_modify(s);
    return RSTRUCT(s)->ptr[i] = val;
}

static VALUE
rb_struct_equal(s, s2)
    VALUE s, s2;
{
    long i;

    if (TYPE(s2) != T_STRUCT) return Qfalse;
    if (CLASS_OF(s) != CLASS_OF(s2)) return Qfalse;
    if (RSTRUCT(s)->len != RSTRUCT(s2)->len) {
	rb_bug("inconsistent struct"); /* should never happen */
    }

    for (i=0; i<RSTRUCT(s)->len; i++) {
	if (!rb_equal(RSTRUCT(s)->ptr[i], RSTRUCT(s2)->ptr[i])) return Qfalse;
    }
    return Qtrue;
}

static VALUE
rb_struct_size(s)
    VALUE s;
{
    return INT2FIX(RSTRUCT(s)->len);
}

void
Init_Struct()
{
    rb_cStruct = rb_define_class("Struct", rb_cObject);
    rb_include_module(rb_cStruct, rb_mEnumerable);

    rb_define_singleton_method(rb_cStruct, "new", rb_struct_s_def, -1);

    rb_define_method(rb_cStruct, "initialize", rb_struct_initialize, -2);
    rb_define_method(rb_cStruct, "clone", rb_struct_clone, 0);

    rb_define_method(rb_cStruct, "==", rb_struct_equal, 1);

    rb_define_method(rb_cStruct, "to_s", rb_struct_to_s, 0);
    rb_define_method(rb_cStruct, "inspect", rb_struct_inspect, 0);
    rb_define_method(rb_cStruct, "to_a", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "values", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "size", rb_struct_size, 0);
    rb_define_method(rb_cStruct, "length", rb_struct_size, 0);

    rb_define_method(rb_cStruct, "each", rb_struct_each, 0);
    rb_define_method(rb_cStruct, "[]", rb_struct_aref, 1);
    rb_define_method(rb_cStruct, "[]=", rb_struct_aset, 2);

    rb_define_method(rb_cStruct, "members", rb_struct_members, 0);
}
