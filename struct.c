/************************************************

  struct.c -

  $Author$
  $Date$
  created at: Tue Mar 22 18:44:30 JST 1995

************************************************/

#include "ruby.h"

ID rb_frame_last_func();
VALUE cStruct;
extern VALUE mEnumerable;

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
struct_s_members(obj)
    VALUE obj;
{
    VALUE member, ary;
    VALUE *p, *pend;

    member = rb_iv_get(obj, "__member__");
    if (NIL_P(member)) {
	Bug("non-initialized struct");
    }
    ary = ary_new2(RARRAY(member)->len);
    p = RARRAY(member)->ptr; pend = p + RARRAY(member)->len;
    while (p < pend) {
	ary_push(ary, str_new2(rb_id2name(FIX2INT(*p))));
	p++;
    }

    return ary;
}

static VALUE
struct_members(obj)
    VALUE obj;
{
    return struct_s_members(class_of(obj));
}

VALUE
struct_getmember(obj, id)
    VALUE obj;
    ID id;
{
    VALUE member, slot;
    int i;

    member = rb_iv_get(class_of(obj), "__member__");
    if (NIL_P(member)) {
	Bug("non-initialized struct");
    }
    slot = INT2FIX(id);
    for (i=0; i<RARRAY(member)->len; i++) {
	if (RARRAY(member)->ptr[i] == slot) {
	    return RSTRUCT(obj)->ptr[i];
	}
    }
    NameError("%s is not struct member", rb_id2name(id));
    /* not reached */
}

static VALUE
struct_ref(obj)
    VALUE obj;
{
    return struct_getmember(obj, rb_frame_last_func());
}

static VALUE struct_ref0(obj) VALUE obj; {return RSTRUCT(obj)->ptr[0];}
static VALUE struct_ref1(obj) VALUE obj; {return RSTRUCT(obj)->ptr[1];}
static VALUE struct_ref2(obj) VALUE obj; {return RSTRUCT(obj)->ptr[2];}
static VALUE struct_ref3(obj) VALUE obj; {return RSTRUCT(obj)->ptr[3];}
static VALUE struct_ref4(obj) VALUE obj; {return RSTRUCT(obj)->ptr[4];}
static VALUE struct_ref5(obj) VALUE obj; {return RSTRUCT(obj)->ptr[5];}
static VALUE struct_ref6(obj) VALUE obj; {return RSTRUCT(obj)->ptr[6];}
static VALUE struct_ref7(obj) VALUE obj; {return RSTRUCT(obj)->ptr[7];}
static VALUE struct_ref8(obj) VALUE obj; {return RSTRUCT(obj)->ptr[8];}
static VALUE struct_ref9(obj) VALUE obj; {return RSTRUCT(obj)->ptr[9];}

VALUE (*ref_func[10])() = {
    struct_ref0,
    struct_ref1,
    struct_ref2,
    struct_ref3,
    struct_ref4,
    struct_ref5,
    struct_ref6,
    struct_ref7,
    struct_ref8,
    struct_ref9,
};

static VALUE
struct_set(obj, val)
    VALUE obj, val;
{
    VALUE member, slot;
    int i;

    member = rb_iv_get(class_of(obj), "__member__");
    if (NIL_P(member)) {
	Fatal("non-initialized struct");
    }
    for (i=0; i<RARRAY(member)->len; i++) {
	slot = RARRAY(member)->ptr[i];
	if (id_attrset(FIX2INT(slot)) == rb_frame_last_func()) {
	    return RSTRUCT(obj)->ptr[i] = val;
	}
    }
    NameError("not struct member");
    /* not reached */
}

VALUE struct_alloc();

static VALUE
make_struct(name, member, klass)
    VALUE name, member, klass;
{
    VALUE nstr;
    ID id;
    int i;

    id = rb_intern(RSTRING(name)->ptr);
    if (!rb_is_const_id(id)) {
	NameError("identifier %s needs to be constant", RSTRING(name)->ptr);
    }
    nstr = rb_define_class_under(klass, RSTRING(name)->ptr, klass);
    rb_iv_set(nstr, "__size__", INT2FIX(RARRAY(member)->len));
    rb_iv_set(nstr, "__member__", member);

    rb_define_singleton_method(nstr, "new", struct_alloc, -2);
    rb_define_singleton_method(nstr, "[]", struct_alloc, -2);
    rb_define_singleton_method(nstr, "members", struct_s_members, 0);
    for (i=0; i< RARRAY(member)->len; i++) {
	ID id = FIX2INT(RARRAY(member)->ptr[i]);
	if (i<10) {
	    rb_define_method_id(nstr, id, ref_func[i], 0);
	}
	else {
	    rb_define_method_id(nstr, id, struct_ref, 0);
	}
	rb_define_method_id(nstr, id_attrset(id), struct_set, 1);
    }

    return nstr;
}

#include <varargs.h>

VALUE
struct_define(name, va_alist)
    char *name;
    va_dcl
{
    va_list ar;
    VALUE nm, ary;
    char *mem;

    nm = str_new2(name);
    ary = ary_new();

    va_start(ar);
    while (mem = va_arg(ar, char*)) {
	ID slot = rb_intern(mem);
	ary_push(ary, INT2FIX(slot));
    }
    va_end(ar);

    return make_struct(nm, ary, cStruct);
}

static VALUE
struct_s_def(argc, argv, klass)
    int argc;
    VALUE *argv;
{
    struct RString *name;
    struct RArray *rest;
    int i;
    VALUE st;

    rb_scan_args(argc, argv, "1*", &name, &rest);
    Check_Type(name, T_STRING);
    for (i=0; i<rest->len; i++) {
	ID id = rb_to_id(rest->ptr[i]);
	rest->ptr[i] = INT2FIX(id);
    }
    st = make_struct(name, rest, klass);
    obj_call_init(st);

    return st;
}

VALUE
struct_alloc(klass, values)
    VALUE klass, values;
{
    VALUE size;
    int n;

    size = rb_iv_get(klass, "__size__");
    n = FIX2INT(size);
    if (n < RARRAY(values)->len) {
	ArgError("struct size differs");
    }
    else {
	NEWOBJ(st, struct RStruct);
	OBJSETUP(st, klass, T_STRUCT);
	st->len = 0;		/* avoid GC crashing  */
	st->ptr = ALLOC_N(VALUE, n);
	st->len = n;
	MEMCPY(st->ptr, RARRAY(values)->ptr, VALUE, RARRAY(values)->len);
	memclear(st->ptr+RARRAY(values)->len, n-RARRAY(values)->len);
	obj_call_init((VALUE)st);

	return (VALUE)st;
    }
    /* not reached */
}

VALUE
struct_new(klass, va_alist)
    VALUE klass;
    va_dcl
{
    VALUE val, mem;
    int size;
    va_list args;

    val = rb_iv_get(klass, "__size__");
    size = FIX2INT(val); 
    mem = ary_new();
    va_start(args);
    while (size--) {
	val = va_arg(args, VALUE);
	ary_push(mem, val);
    }
    va_end(args);

    return struct_alloc(klass, mem);
}

static VALUE
struct_each(s)
    VALUE s;
{
    int i;

    for (i=0; i<RSTRUCT(s)->len; i++) {
	rb_yield(RSTRUCT(s)->ptr[i]);
    }
    return Qnil;
}

char *rb_class2name();

static VALUE
struct_to_s(s)
    VALUE s;
{
    char *name, *buf;

    name = rb_class2name(CLASS_OF(s));
    buf = ALLOCA_N(char, strlen(name)+1);
    sprintf(buf, "%s", name);
    return str_new2(buf);
}

static VALUE
struct_inspect(s)
    VALUE s;
{
    char *name = rb_class2name(CLASS_OF(s));
    VALUE str, member;
    int i;

    member = rb_iv_get(CLASS_OF(s), "__member__");
    if (NIL_P(member)) {
	Fatal("non-initialized struct");
    }

    str = str_new2("#<");
    str_cat(str, name, strlen(name));
    str_cat(str, " ", 1);
    for (i=0; i<RSTRUCT(s)->len; i++) {
	VALUE str2, slot;
	char *p;

	if (i > 0) {
	    str_cat(str, ", ", 2);
	}
	slot = RARRAY(member)->ptr[i];
	p = rb_id2name(FIX2INT(slot));
	str_cat(str, p, strlen(p));
	str_cat(str, "=", 1);
	str2 = rb_inspect(RSTRUCT(s)->ptr[i]);
	str2 = obj_as_string(str2);
	str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    }
    str_cat(str, ">", 1);

    return str;
}

static VALUE
struct_to_a(s)
    VALUE s;
{
    return ary_new4(RSTRUCT(s)->len, RSTRUCT(s)->ptr);
}

static VALUE
struct_clone(s)
    VALUE s;
{
    NEWOBJ(st, struct RStruct);
    CLONESETUP(st, s);
    st->len = 0;		/* avoid GC crashing  */
    st->ptr = ALLOC_N(VALUE, RSTRUCT(s)->len);
    st->len = RSTRUCT(s)->len;
    MEMCPY(st->ptr, RSTRUCT(s)->ptr, VALUE, st->len);

    return (VALUE)st;
}

static VALUE
struct_aref_id(s, id)
    VALUE s;
    ID id;
{
    VALUE member;
    int i, len;
    VALUE *p;

    member = rb_iv_get(CLASS_OF(s), "__member__");
    if (NIL_P(member)) {
	Bug("non-initialized struct");
    }

    len = RARRAY(member)->len;
    for (i=0; i<len; i++) {
	if (FIX2INT(RARRAY(member)->ptr[i]) == id) {
	    return RSTRUCT(s)->ptr[i];
	}
    }
    NameError("no member '%s' in struct", rb_id2name(id));
}

VALUE
struct_aref(s, idx)
    VALUE s, idx;
{
    int i;

    if (TYPE(idx) == T_STRING) {
	return struct_aref_id(s, rb_to_id(idx));
    }

    i = NUM2INT(idx);
    if (i < 0) i = RSTRUCT(s)->len + i;
    if (i < 0)
        IndexError("offset %d too small for struct(size:%d)", i, RSTRUCT(s)->len);
    if (RSTRUCT(s)->len <= i)
        IndexError("offset %d too large for struct(size:%d)", i, RSTRUCT(s)->len);
    return RSTRUCT(s)->ptr[i];
}

VALUE
struct_aset_id(s, id, val)
    VALUE s, val;
    ID id;
{
    VALUE member;
    int i, len;
    VALUE *p;

    member = rb_iv_get(CLASS_OF(s), "__member__");
    if (NIL_P(member)) {
	Bug("non-initialized struct");
    }

    len = RARRAY(member)->len;
    for (i=0; i<len; i++) {
	if (FIX2INT(RARRAY(member)->ptr[i]) == id) {
	    RSTRUCT(s)->ptr[i] = val;
	    return val;
	}
    }
    NameError("no member '%s' in struct", rb_id2name(id));
}

VALUE
struct_aset(s, idx, val)
    VALUE s, idx, val;
{
    int i;

    if (TYPE(idx) == T_STRING) {
	return struct_aref_id(s, rb_to_id(idx));
    }

    i = NUM2INT(idx);
    if (i < 0) i = RSTRUCT(s)->len + i;
    if (i < 0)
        IndexError("offset %d too small for struct(size:%d)", i, RSTRUCT(s)->len);
    if (RSTRUCT(s)->len <= i)
        IndexError("offset %d too large for struct(size:%d)", i, RSTRUCT(s)->len);
    return RSTRUCT(s)->ptr[i] = val;
}

static VALUE
struct_equal(s, s2)
    VALUE s, s2;
{
    int i;

    if (TYPE(s2) != T_STRUCT) return FALSE;
    if (CLASS_OF(s) != CLASS_OF(s2)) return FALSE;
    if (RSTRUCT(s)->len != RSTRUCT(s2)->len) {
	Bug("inconsistent struct"); /* should never happen */
    }

    for (i=0; i<RSTRUCT(s)->len; i++) {
	if (!rb_equal(RSTRUCT(s)->ptr[i], RSTRUCT(s2)->ptr[i])) return FALSE;
    }
    return TRUE;
}

static VALUE
struct_eql(s, s2)
    VALUE s, s2;
{
    int i;

    if (TYPE(s2) != T_STRUCT) return FALSE;
    if (CLASS_OF(s) != CLASS_OF(s2)) return FALSE;
    if (RSTRUCT(s)->len != RSTRUCT(s2)->len) {
	Bug("inconsistent struct"); /* should never happen */
    }

    for (i=0; i<RSTRUCT(s)->len; i++) {
	if (!rb_eql(RSTRUCT(s)->ptr[i], RSTRUCT(s2)->ptr[i])) return FALSE;
    }
    return TRUE;
}

static VALUE
struct_hash(s)
    VALUE s;
{
    int i, h;

    h = CLASS_OF(s);
    for (i=0; i<RSTRUCT(s)->len; i++) {
	h ^= rb_hash(RSTRUCT(s)->ptr[i]);
    }
    return INT2FIX(h);
}

void
Init_Struct()
{
    cStruct = rb_define_class("Struct", cObject);
    rb_include_module(cStruct, mEnumerable);

    rb_define_singleton_method(cStruct, "new", struct_s_def, -1);

    rb_define_method(cStruct, "clone", struct_clone, 0);

    rb_define_method(cStruct, "==", struct_equal, 1);
    rb_define_method(cStruct, "eql?", struct_eql, 1);
    rb_define_method(cStruct, "hash", struct_hash, 0);

    rb_define_method(cStruct, "to_s", struct_to_s, 0);
    rb_define_method(cStruct, "inspect", struct_inspect, 0);
    rb_define_method(cStruct, "to_a", struct_to_a, 0);
    rb_define_method(cStruct, "values", struct_to_a, 0);

    rb_define_method(cStruct, "each", struct_each, 0);
    rb_define_method(cStruct, "[]", struct_aref, 1);
    rb_define_method(cStruct, "[]=", struct_aset, 2);

    rb_define_method(cStruct, "members", struct_members, 0);
}
