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
struct_s_members(obj)
    VALUE obj;
{
    struct RArray *member;
    VALUE ary, *p, *pend;

    member = RARRAY(rb_iv_get(obj, "__member__"));
    if (NIL_P(member)) {
	Fatal("non-initialized struct");
    }
    ary = ary_new2(member->len);
    p = member->ptr; pend = p + member->len;
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
    return struct_s_members(CLASS_OF(obj));
}

VALUE
struct_getmember(obj, id)
    struct RStruct *obj;
    ID id;
{
    VALUE nstr, member, slot;
    int i;

    nstr = CLASS_OF(obj);
    member = rb_iv_get(nstr, "__member__");
    if (NIL_P(member)) {
	Bug("non-initialized struct");
    }
    slot = INT2FIX(id);
    for (i=0; i<RARRAY(member)->len; i++) {
	if (RARRAY(member)->ptr[i] == slot) {
	    return obj->ptr[i];
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

static VALUE struct_ref0(obj) struct RStruct *obj; {return obj->ptr[0];}
static VALUE struct_ref1(obj) struct RStruct *obj; {return obj->ptr[1];}
static VALUE struct_ref2(obj) struct RStruct *obj; {return obj->ptr[2];}
static VALUE struct_ref3(obj) struct RStruct *obj; {return obj->ptr[3];}
static VALUE struct_ref4(obj) struct RStruct *obj; {return obj->ptr[4];}
static VALUE struct_ref5(obj) struct RStruct *obj; {return obj->ptr[5];}
static VALUE struct_ref6(obj) struct RStruct *obj; {return obj->ptr[6];}
static VALUE struct_ref7(obj) struct RStruct *obj; {return obj->ptr[7];}
static VALUE struct_ref8(obj) struct RStruct *obj; {return obj->ptr[8];}
static VALUE struct_ref9(obj) struct RStruct *obj; {return obj->ptr[9];}

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
    struct RStruct *obj;
    VALUE val;
{
    VALUE nstr, member, slot;
    int i;

    nstr = CLASS_OF(obj);
    member = rb_iv_get(nstr, "__member__");
    if (NIL_P(member)) {
	Fatal("non-initialized struct");
    }
    for (i=0; i<RARRAY(member)->len; i++) {
	slot = RARRAY(member)->ptr[i];
	if (id_attrset(FIX2INT(slot)) == rb_frame_last_func()) {
	    return obj->ptr[i] = val;
	}
    }
    NameError("not struct member");
    /* not reached */
}

VALUE struct_alloc();

static VALUE
make_struct(name, member)
    struct RString *name;
    struct RArray *member;
{
    VALUE nstr;
    ID id;
    int i;

    id = rb_intern(name->ptr);
    if (!rb_is_const_id(id)) {
	NameError("identifier %s needs to be constant", name->ptr);
    }
    nstr = rb_define_class_under(cStruct, name->ptr, cStruct);
    rb_iv_set(nstr, "__size__", INT2FIX(member->len));
    rb_iv_set(nstr, "__member__", member);

    rb_define_singleton_method(nstr, "new", struct_alloc, -2);
    rb_define_singleton_method(nstr, "[]", struct_alloc, -2);
    rb_define_singleton_method(nstr, "members", struct_s_members, 0);
    for (i=0; i< member->len; i++) {
	ID id = FIX2INT(member->ptr[i]);
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

    return make_struct(nm, ary);
}

static VALUE
struct_s_def(argc, argv)
    int argc;
    VALUE *argv;
{
    struct RString *name;
    struct RArray *rest;
    int i;

    rb_scan_args(argc, argv, "1*", &name, &rest);
    Check_Type(name, T_STRING);
    for (i=0; i<rest->len; i++) {
	ID id = rb_to_id(rest->ptr[i]);
	rest->ptr[i] = INT2FIX(id);
    }
    return make_struct(name, rest);
}

VALUE
struct_alloc(class, values)
    VALUE class;
    struct RArray *values;
{
    VALUE size;
    int n;

    size = rb_iv_get(class, "__size__");
    n = FIX2INT(size);
    if (n < values->len) {
	ArgError("struct size differs");
    }
    else {
	NEWOBJ(st, struct RStruct);
	OBJSETUP(st, class, T_STRUCT);
	st->len = n;
	st->ptr = 0;		/* avoid GC crashing  */
	st->ptr = ALLOC_N(VALUE, n);
	MEMCPY(st->ptr, values->ptr, VALUE, values->len);
	memclear(st->ptr+values->len, n - values->len);

	return (VALUE)st;
    }
    /* not reached */
}

VALUE
struct_new(class, va_alist)
    VALUE class;
    va_dcl
{
    VALUE val, mem;
    int size;
    va_list args;

    val = rb_iv_get(class, "__size__");
    size = FIX2INT(val); 
    mem = ary_new();
    va_start(args);
    while (size--) {
	val = va_arg(args, VALUE);
	ary_push(mem, val);
    }
    va_end(args);

    return struct_alloc(class, mem);
}

static VALUE
struct_each(s)
    struct RStruct *s;
{
    int i;

    for (i=0; i<s->len; i++) {
	rb_yield(s->ptr[i]);
    }
    return Qnil;
}

char *rb_class2name();

static VALUE
struct_to_s(s)
    struct RStruct *s;
{
    char *name, *buf;

    name = rb_class2name(CLASS_OF(s));
    buf = ALLOCA_N(char, strlen(name)+1);
    sprintf(buf, "%s", name);
    return str_new2(buf);
}

static VALUE
struct_inspect(s)
    struct RStruct *s;
{
    char *name = rb_class2name(CLASS_OF(s));
    VALUE str, member;
    char buf[256];
    int i;

    member = rb_iv_get(CLASS_OF(s), "__member__");
    if (NIL_P(member)) {
	Fatal("non-initialized struct");
    }

    sprintf(buf, "#<%s ", name);
    str = str_new2(buf);
    for (i=0; i<s->len; i++) {
	VALUE str2, slot;
	char *p;

	if (i > 0) {
	    str_cat(str, ", ", 2);
	}
	slot = RARRAY(member)->ptr[i];
	p = rb_id2name(FIX2INT(slot));
	str_cat(str, p, strlen(p));
	str_cat(str, "=", 1);
	str2 = rb_inspect(s->ptr[i]);
	str2 = obj_as_string(str2);
	str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    }
    str_cat(str, ">", 1);

    return str;
}

static VALUE
struct_to_a(s)
    struct RStruct *s;
{
    return ary_new4(s->len, s->ptr);
}

static VALUE
struct_clone(s)
    struct RStruct *s;
{
    NEWOBJ(st, struct RStruct);
    CLONESETUP(st, s);
    st->len = s->len;
    st->ptr = 0;		/* avoid GC crashing  */
    st->ptr = ALLOC_N(VALUE, s->len);
    MEMCPY(st->ptr, s->ptr, VALUE, st->len);

    return (VALUE)st;
}

VALUE
struct_aref(s, idx)
    struct RStruct *s;
    VALUE idx;
{
    int i;

    i = NUM2INT(idx);
    if (i < 0) i = s->len - i;
    if (i < 0)
        IndexError("offset %d too small for struct(size:%d)", i, s->len);
    if (s->len <= i)
        IndexError("offset %d too large for struct(size:%d)", i, s->len);
    return s->ptr[i];
}

VALUE
struct_aset(s, idx, val)
    struct RStruct *s;
    VALUE idx, val;
{
    int i;

    i = NUM2INT(idx);
    if (i < 0) i = s->len - i;
    if (i < 0)
        IndexError("offset %d too small for struct(size:%d)", i, s->len);
    if (s->len <= i)
        IndexError("offset %d too large for struct(size:%d)", i, s->len);
    return s->ptr[i] = val;
}

static VALUE
struct_equal(s, s2)
    struct RStruct *s, *s2;
{
    int i;

    if (TYPE(s2) != T_STRUCT) return FALSE;
    if (CLASS_OF(s) != CLASS_OF(s2)) return FALSE;
    if (s->len != s2->len) {
	Bug("inconsistent struct"); /* should never happen */
    }

    for (i=0; i<s->len; i++) {
	if (!rb_equal(s->ptr[i], s2->ptr[i])) return FALSE;
    }
    return TRUE;
}

static VALUE
struct_eql(s, s2)
    struct RStruct *s, *s2;
{
    int i;

    if (TYPE(s2) != T_STRUCT) return FALSE;
    if (CLASS_OF(s) != CLASS_OF(s2)) return FALSE;
    if (s->len != s2->len) {
	Bug("inconsistent struct"); /* should never happen */
    }

    for (i=0; i<s->len; i++) {
	if (!rb_eql(s->ptr[i], s2->ptr[i])) return FALSE;
    }
    return TRUE;
}

static VALUE
struct_hash(s)
    struct RStruct *s;
{
    int i, h;

    h = CLASS_OF(s);
    for (i=0; i<s->len; i++) {
	h ^= rb_hash(s->ptr[i]);
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
