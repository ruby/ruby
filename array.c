/************************************************

  array.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:18 $
  created at: Fri Aug  6 09:46:12 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE cArray;

VALUE rb_to_a();

#define ARY_DEFAULT_SIZE 16

VALUE
ary_new2(len)
    int len;
{
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, cArray, T_ARRAY);

    ary->len = 0;
    ary->capa = len;
    if (len == 0)
	ary->ptr = 0;
    else
	ary->ptr = ALLOC_N(VALUE, len);

    return (VALUE)ary;
}

VALUE
ary_new()
{
    return ary_new2(ARY_DEFAULT_SIZE);
}

#include <varargs.h>

VALUE
ary_new3(n, va_alist)
    int n;
    va_dcl
{
    va_list ar;
    struct RArray* ary;
    int i;

    if (n < 0) {
	Fail("Negative number of items(%d)", n);
    }
    ary = (struct RArray*)ary_new2(n<ARY_DEFAULT_SIZE?ARY_DEFAULT_SIZE:n);

    va_start(ar);
    for (i=0; i<n; i++) {
	ary->ptr[i] = va_arg(ar, VALUE);
    }
    va_end(ar);

    ary->len = n;
    return (VALUE)ary;
}

VALUE
ary_new4(n, elts)
    int n;
    VALUE *elts;
{
    struct RArray* ary;

    ary = (struct RArray*)ary_new2(n);
    MEMCPY(ary->ptr, elts, VALUE, n);
    ary->len = n;

    return (VALUE)ary;
}

VALUE
assoc_new(car, cdr)
    VALUE car, cdr;
{
    struct RArray* ary;

    ary = (struct RArray*)ary_new2(2);
    ary->ptr[0] = car;
    ary->ptr[1] = cdr;
    ary->len = 2;

    return (VALUE)ary;
}

static VALUE
ary_s_new(class)
    VALUE class;
{
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, class, T_ARRAY);

    ary->len = 0;
    ary->capa = ARY_DEFAULT_SIZE;
    ary->ptr = ALLOC_N(VALUE, ARY_DEFAULT_SIZE);

    return (VALUE)ary;
}

static VALUE
ary_s_create(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, class, T_ARRAY);

    ary->len = argc;
    ary->capa = argc;
    if (argc == 0) {
	ary->ptr = 0;
    }
    else {
	ary->ptr = ALLOC_N(VALUE, argc);
	MEMCPY(ary->ptr, argv, VALUE, argc);
    }

    return (VALUE)ary;
}

static void
astore(ary, idx, val)
    struct RArray *ary;
    int idx;
    VALUE val;
{
    if (idx < 0) {
	Fail("negative index for array");
    }

    if (idx >= ary->capa) {
	ary->capa = idx + ARY_DEFAULT_SIZE;
	REALLOC_N(ary->ptr, VALUE, ary->capa);
    }
    if (idx > ary->len) {
	MEMZERO(ary->ptr+ary->len, VALUE, idx-ary->len+1);
    }

    if (idx >= ary->len) {
	ary->len = idx + 1;
    }
    ary->ptr[idx] = val;
}

VALUE
ary_push(ary, item)
    struct RArray *ary;
    VALUE item;
{
    astore(ary, ary->len, item);
    return (VALUE)ary;
}

static VALUE
ary_append(ary, item)
    struct RArray *ary;
    VALUE item;
{
    astore(ary, ary->len, item);
    return (VALUE)ary;
}

VALUE
ary_pop(ary)
    struct RArray *ary;
{
    if (ary->len == 0) return Qnil;
    return ary->ptr[--ary->len];
}

VALUE
ary_shift(ary)
    struct RArray *ary;
{
    VALUE top;

    if (ary->len == 0) return Qnil;

    top = ary->ptr[0];
    ary->len--;

    /* sliding items */
    MEMMOVE(ary->ptr, ary->ptr+1, VALUE, ary->len);

    return top;
}

VALUE
ary_unshift(ary, item)
    struct RArray *ary;
    int item;
{
    if (ary->len >= ary->capa) {
	ary->capa+=ARY_DEFAULT_SIZE;
	REALLOC_N(ary->ptr, VALUE, ary->capa);
    }

    /* sliding items */
    MEMMOVE(ary->ptr+1, ary->ptr, VALUE, ary->len);

    ary->len++;
    return ary->ptr[0] = item;
}

VALUE
ary_entry(ary, offset)
    struct RArray *ary;
    int offset;
{
    if (ary->len == 0) return Qnil;

    if (offset < 0) {
	offset = ary->len + offset;
    }
    if (offset < 0 || ary->len <= offset) {
	return Qnil;
    }

    return ary->ptr[offset];
}

static VALUE
ary_subseq(ary, beg, len)
    struct RArray *ary;
    int beg, len;
{
    struct RArray *ary2;

    if (beg < 0) {
	beg = ary->len + beg;
	if (beg < 0) beg = 0;
    }
    if (len < 0) {
	Fail("negative length for sub-array(size: %d)", ary->len);
    }
    if (len == 0) {
	return ary_new();
    }
    if (beg + len > ary->len) {
	len = ary->len - beg;
    }

    ary2 = (struct RArray*)ary_new2(len);
    MEMCPY(ary2->ptr, ary->ptr+beg, VALUE, len);
    ary2->len = len;

    return (VALUE)ary2;
}

static VALUE
beg_len(range, begp, lenp, len)
    VALUE range;
    int *begp, *lenp;
    int len;
{
    int beg, end;

    if (!range_beg_end(range, &beg, &end)) return FALSE;

    if (beg < 0) {
	beg = len + beg;
	if (beg < 0) beg = 0;
    }
    *begp = beg;
    if (beg > len) {
	*lenp = 0;
    }
    else {
	if (end < 0) {
	    end = len + end;
	    if (end < 0) end = 0;
	}
	if (len < end) end = len;
	if (beg < end) {
	    *lenp = 0;
	}
	else {
	    *lenp = end - beg +1;
	}
    }
    return TRUE;
}

static VALUE
ary_aref(argc, argv, ary)
    int argc;
    VALUE *argv;
    struct RArray *ary;
{
    VALUE arg1, arg2;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2) {
	int beg, len;

	beg = NUM2INT(arg1);
	len = NUM2INT(arg2);
	if (len <= 0) {
	    return ary_new();
	}
	return ary_subseq(ary, beg, len);
    }

    /* special case - speeding up */
    if (FIXNUM_P(arg1)) {
	return ary_entry(ary, NUM2INT(arg1));
    }

    /* check if idx is Range */
    {
	int beg, len;

	if (beg_len(arg1, &beg, &len, ary->len)) {
	    return ary_subseq(ary, beg, len);
	}
    }
    return ary_entry(ary, NUM2INT(arg1));
}

static VALUE
ary_index(ary, val)
    struct RArray *ary;
    VALUE val;
{
    int i;

    for (i=0; i<ary->len; i++) {
	if (rb_equal(ary->ptr[i], val))
	    return INT2FIX(i);
    }
    return Qnil;		/* should be FALSE? */
}

static VALUE
ary_indexes(ary, args)
    struct RArray *ary, *args;
{
    VALUE *p, *pend;
    VALUE new_ary;
    int i = 0;

    if (!args || args->len == 1) {
	args = (struct RArray*)rb_to_a(args->ptr[0]);
    }

    new_ary = ary_new2(args->len);

    p = args->ptr; pend = p + args->len;
    while (p < pend) {
	astore(new_ary, i++, ary_entry(ary, NUM2INT(*p)));
	p++;
    }
    return new_ary;
}

static VALUE
ary_aset(argc, argv, ary)
    int argc;
    VALUE *argv;
    struct RArray *ary;
{
    VALUE arg1, arg2;
    struct RArray *arg3;
    int offset;

    if (rb_scan_args(argc, argv, "21", &arg1, &arg2, &arg3) == 3) {
	int beg, len;

	beg = NUM2INT(arg1);
	if (TYPE(arg3) != T_ARRAY) {
	    arg3 = (struct RArray*)rb_to_a(arg3);
	}
	if (beg < 0) {
	    beg = ary->len + beg;
	    if (beg < 0) {
		Fail("negative index for array(size: %d)", ary->len);
	    }
	}
	if (beg >= ary->len) {
	    len = beg + arg3->len;
	    if (len >= ary->capa) {
		ary->capa=len;
		REALLOC_N(ary->ptr, VALUE, ary->capa);
	    }
	    MEMZERO(ary->ptr+ary->len, VALUE, beg-ary->len);
	    MEMCPY(ary->ptr+beg, arg3->ptr, VALUE, arg3->len);
	    ary->len = len;
	}
	else {
	    int alen;

	    len = NUM2INT(arg2);
	    if (beg + len > ary->len) {
		len = ary->len - beg;
	    }
	    if (len < 0) {
		Fail("negative length for sub-array(size: %d)", ary->len);
	    }

	    alen = ary->len + arg3->len - len;
	    if (alen >= ary->capa) {
		ary->capa=alen;
		REALLOC_N(ary->ptr, VALUE, ary->capa);
	    }

	    MEMMOVE(ary->ptr+beg+arg3->len, ary->ptr+beg+len,
		    VALUE, ary->len-(beg+len));
	    MEMCPY(ary->ptr+beg, arg3->ptr, VALUE, arg3->len);
	    ary->len = alen;
	}
	return (VALUE)arg3;
    }

    /* check if idx is Range */
    {
	int beg, len;

	if (beg_len(arg1, &beg, &len, ary->len)) {
	    Check_Type(arg2, T_ARRAY);
	    if (ary->len < beg) {
		len = beg + RARRAY(arg2)->len;
		if (len >= ary->capa) {
		    ary->capa=len;
		    REALLOC_N(ary->ptr, VALUE, ary->capa);
		}
		MEMZERO(ary->ptr+ary->len, VALUE, beg-ary->len);
		MEMCPY(ary->ptr+beg, RARRAY(arg2)->ptr, VALUE, RARRAY(arg2)->len);
		ary->len = len;
	    }
	    else {
		int alen;

		alen = ary->len + RARRAY(arg2)->len - len;
		if (alen >= ary->capa) {
		    ary->capa=alen;
		    REALLOC_N(ary->ptr, VALUE, ary->capa);
		}

		MEMMOVE(ary->ptr+beg+RARRAY(arg2)->len, ary->ptr+beg+len,
			VALUE, ary->len-(beg+len));
		MEMCPY(ary->ptr+beg, RARRAY(arg2)->ptr, VALUE, RARRAY(arg2)->len);
		ary->len = alen;
	    }
	    return arg2;
	}
    }

    offset = NUM2INT(arg1);
    if (offset < 0) {
	offset = ary->len + offset;
    }
    astore(ary, offset, arg2);
    return arg2;
}

static VALUE
ary_each(ary)
    struct RArray *ary;
{
    int i;

    if (iterator_p()) {
	for (i=0; i<ary->len; i++) {
	    rb_yield(ary->ptr[i]);
	}
	return Qnil;
    }
    else {
	return (VALUE)ary;
    }
}

static VALUE
ary_each_index(ary)
    struct RArray *ary;
{
    int i;

    for (i=0; i<ary->len; i++) {
	rb_yield(INT2FIX(i));
    }
    return Qnil;
}

static VALUE
ary_length(ary)
    struct RArray *ary;
{
    return INT2FIX(ary->len);
}

static VALUE
ary_clone(ary)
    struct RArray *ary;
{
    VALUE ary2 = ary_new2(ary->len);

    CLONESETUP(ary2, ary);
    MEMCPY(RARRAY(ary2)->ptr, ary->ptr, VALUE, ary->len);
    RARRAY(ary2)->len = ary->len;
    return ary2;
}

extern VALUE OFS;

VALUE
ary_join(ary, sep)
    struct RArray *ary;
    struct RString *sep;
{
    int i;
    VALUE result, tmp;
    if (ary->len == 0) return str_new(0, 0);

    if (TYPE(ary->ptr[0]) == T_STRING)
	result = str_dup(ary->ptr[0]);
    else
	result = obj_as_string(ary->ptr[0]);

    for (i=1; i<ary->len; i++) {
	tmp = ary->ptr[i];
	switch (TYPE(tmp)) {
	  case T_STRING:
	    break;
	  case T_ARRAY:
	    tmp = ary_join(tmp, sep);
	    break;
	  default:
	    tmp = obj_as_string(tmp);
	}
	if (sep) str_cat(result, sep->ptr, sep->len);
	str_cat(result, RSTRING(tmp)->ptr, RSTRING(tmp)->len);
    }

    return result;
}

static VALUE
ary_join_method(argc, argv, ary)
    int argc;
    VALUE *argv;
    struct RArray *ary;
{
    VALUE sep;

    rb_scan_args(argc, argv, "01", &sep);
    if (sep == Qnil) sep = OFS;

    if (sep != Qnil)
	Check_Type(sep, T_STRING);

    return ary_join(ary, sep);
}

VALUE
ary_to_s(ary)
    VALUE ary;
{
    VALUE str = ary_join(ary, OFS);
    if (str == Qnil) return str_new(0, 0);
    return str;
}

VALUE
ary_print_on(ary, port)
    struct RArray *ary;
    VALUE port;
{
    int i;

    for (i=0; i<ary->len; i++) {
	if (OFS && i>1) {
	    io_write(port, OFS);
	}
	io_write(port, ary->ptr[i]);
    }
    return port;
}

static VALUE
ary_inspect(ary)
    struct RArray *ary;
{
    int i, len;
    VALUE s, str;
    char *p;

    if (ary->len == 0) return str_new2("[]");
    str = str_new2("[");
    len = 1;

    for (i=0; i<ary->len; i++) {
	s = rb_funcall(ary->ptr[i], rb_intern("inspect"), 0, 0);
	if (i > 0) str_cat(str, ", ", 2);
	str_cat(str, RSTRING(s)->ptr, RSTRING(s)->len);
	len += RSTRING(s)->len + 2;
    }
    str_cat(str, "]", 1);

    return str;
}

static VALUE
ary_to_a(ary)
    VALUE ary;
{
    return ary;
}

VALUE
rb_to_a(obj)
    VALUE obj;
{
    if (TYPE(obj) == T_ARRAY) return obj;
    obj = rb_funcall(obj, rb_intern("to_a"), 0);
    if (TYPE(obj) != T_ARRAY) {
	Bug("`to_a' did not return Array");
    }
    return obj;
}

VALUE
ary_reverse(ary)
    struct RArray *ary;
{
    VALUE ary2 = ary_new2(ary->len);
    int i, j;

    for (i=ary->len-1, j=0; i >=0; i--, j++) {
	RARRAY(ary2)->ptr[j] = ary->ptr[i];
    }
    RARRAY(ary2)->len = ary->len;

    return ary2;
}

static ID cmp;

static int
sort_1(a, b)
    VALUE *a, *b;
{
    VALUE retval = rb_yield(assoc_new(*a, *b));
    return NUM2INT(retval);
}

static int
sort_2(a, b)
    VALUE *a, *b;
{
    VALUE retval;

    if (!cmp) cmp = rb_intern("<=>");
    retval = rb_funcall(*a, cmp, 1, *b);
    return NUM2INT(retval);
}

VALUE
ary_sort(ary)
    struct RArray *ary;
{
    qsort(ary->ptr, ary->len, sizeof(VALUE), iterator_p()?sort_1:sort_2);
    return (VALUE)ary;
}

static VALUE
ary_delete(ary, item)
    struct RArray *ary;
    VALUE item;
{
    int i1, i2;

    for (i1 = i2 = 0; i1 < ary->len; i1++) {
	if (rb_equal(ary->ptr[i1], item)) continue;
	if (i1 != i2) {
	    ary->ptr[i2] = ary->ptr[i1];
	}
	i2++;
    }
    ary->len = i2;

    return (VALUE)ary;
}

static VALUE
ary_delete_if(ary)
    struct RArray *ary;
{
    int i1, i2;

    for (i1 = i2 = 0; i1 < ary->len; i1++) {
	if (rb_yield(ary->ptr[i1])) continue;
	if (i1 != i2) {
	    ary->ptr[i2] = ary->ptr[i1];
	}
	i2++;
    }
    ary->len = i2;

    return (VALUE)ary;
}

static VALUE
ary_clear(ary)
    struct RArray *ary;
{
    ary->len = 0;
    return (VALUE)ary;
}

static VALUE
ary_fill(argc, argv, ary)
    int argc;
    VALUE *argv;
    struct RArray *ary;
{
    VALUE item, arg1, arg2;
    int beg, len, end;
    VALUE *p, *pend;

    rb_scan_args(argc, argv, "12", &item, &arg1, &arg2);
    if (arg2 == Qnil && beg_len(arg1, &beg, &len, ary->len)) {
	/* beg and len set already */
    }
    else {
	beg = NUM2INT(arg1);
	if (beg < 0) {
	    beg = ary->len + beg;
	    if (beg < 0) beg = 0;
	}
	if (arg2) {
	    len = NUM2INT(arg2);
	}
	else {
	    len = ary->len - beg;
	}
    }
    end = beg + len;
    if (end > ary->len) {
	if (end >= ary->capa) {
	    ary->capa=end;
	    REALLOC_N(ary->ptr, VALUE, ary->capa);
	}
	if (beg > ary->len) {
	    MEMZERO(ary->ptr+ary->len, VALUE, end-ary->len);
	}
	ary->len = end;
    }
    p = ary->ptr + beg; pend = p + len;

    while (p < pend) {
	*p++ = item;
    }
    return (VALUE)ary;
}

static VALUE
ary_plus(x, y)
    struct RArray *x, *y;
{
    struct RArray *z;

    switch (TYPE(y)) {
      case T_ARRAY:
	z = (struct RArray*)ary_new2(x->len + y->len);
	MEMCPY(z->ptr, x->ptr, VALUE, x->len);
	MEMCPY(z->ptr+x->len, y->ptr, VALUE, y->len);
	z->len = x->len + RARRAY(y)->len;
	break;

      default:
	z = (struct RArray*)ary_clone(x);
	ary_push(z, y);
	break;
    }
    return (VALUE)z;
}

static VALUE
ary_times(ary, times)
    struct RArray *ary;
    VALUE times;
{
    struct RArray *ary2;
    int i, len;

    len = NUM2INT(times) * ary->len;
    ary2 = (struct RArray*)ary_new2(len);
    ary2->len = len;

    for (i=0; i<len; i+=ary->len) {
	MEMCPY(ary2->ptr+i, ary->ptr, VALUE, ary->len);
    }

    return (VALUE)ary2;
}

VALUE
ary_assoc(ary, key)
    struct RArray *ary;
    VALUE key;
{
    VALUE *p, *pend;

    p = ary->ptr; pend = p + ary->len;
    while (p < pend) {
	if (TYPE(*p) == T_ARRAY
	    && RARRAY(*p)->len > 1
	    && rb_equal(RARRAY(*p)->ptr[0], key))
	    return *p;
    }
    return Qnil;		/* should be FALSE? */
}

VALUE
ary_rassoc(ary, value)
    struct RArray *ary;
    VALUE value;
{
    VALUE *p, *pend;

    p = ary->ptr; pend = p + ary->len;
    while (p < pend) {
	if (TYPE(*p) == T_ARRAY
	    && RARRAY(*p)->len > 2
	    && rb_equal(RARRAY(*p)->ptr[1], value))
	    return *p;
    }
    return Qnil;		/* should be FALSE? */
}

static VALUE
ary_equal(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    int i;

    if (TYPE(ary2) != T_ARRAY) return FALSE;
    if (ary1->len != ary2->len) return FALSE;
    for (i=0; i<ary1->len; i++) {
	if (!rb_equal(ary1->ptr[i], ary2->ptr[i]))
	    return FALSE;
    }
    return TRUE;
}

static VALUE
ary_hash(ary)
    struct RArray *ary;
{
    int i, h;
    ID hash = rb_intern("hash");

    h = 0;
    for (i=0; i<ary->len; i++) {
	h ^= rb_funcall(ary->ptr[i], hash, 0);
    }
    h += ary->len;
    return INT2FIX(h);
}

static VALUE
ary_includes(ary, item)
    struct RArray *ary;
    VALUE item;
{
    int i;
    for (i=0; i<ary->len; i++) {
	if (rb_equal(ary->ptr[i], item)) {
	    return TRUE;
	}
    }
    return FALSE;
}

static VALUE
ary_diff(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    VALUE ary3;
    int i;

    Check_Type(ary2, T_ARRAY);
    ary3 = ary_new();
    for (i=0; i<ary1->len; i++) {
	if (ary_includes(ary2, ary1->ptr[i])) continue;
	if (ary_includes(ary3, ary1->ptr[i])) continue;
	ary_push(ary3, ary1->ptr[i]);
    }
    return ary3;
}

static VALUE
ary_and(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    VALUE ary3;
    int i;

    Check_Type(ary2, T_ARRAY);
    ary3 = ary_new();
    for (i=0; i<ary1->len; i++) {
	if (ary_includes(ary2, ary1->ptr[i])
	    && !ary_includes(ary3, ary1->ptr[i])) {
	    ary_push(ary3, ary1->ptr[i]);
	}
    }
    return ary3;
}

static VALUE
ary_or(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    VALUE ary3;
    int i;

    if (TYPE(ary2) != T_ARRAY) {
	if (ary_includes(ary1, ary2)) return (VALUE)ary1;
	else return ary_plus(ary1, ary2);
    }

    ary3 = ary_new();
    for (i=0; i<ary1->len; i++) {
	if (!ary_includes(ary3, ary1->ptr[i]))
		ary_push(ary3, ary1->ptr[i]);
    }
    for (i=0; i<ary2->len; i++) {
	if (!ary_includes(ary3, ary2->ptr[i]))
		ary_push(ary3, ary2->ptr[i]);
    }
    return ary3;
}

extern VALUE cKernel;
extern VALUE mEnumerable;

void
Init_Array()
{
    cArray  = rb_define_class("Array", cObject);
    rb_include_module(cArray, mEnumerable);

    rb_define_singleton_method(cArray, "new", ary_s_new, 0);
    rb_define_singleton_method(cArray, "[]", ary_s_create, -1);
    rb_define_method(cArray, "to_s", ary_to_s, 0);
    rb_define_method(cArray, "inspect", ary_inspect, 0);
    rb_define_method(cArray, "to_a", ary_to_a, 0);

    rb_define_method(cArray, "print_on", ary_print_on, 1);

    rb_define_method(cArray, "==", ary_equal, 1);
    rb_define_method(cArray, "hash", ary_hash, 0);
    rb_define_method(cArray, "[]", ary_aref, -1);
    rb_define_method(cArray, "[]=", ary_aset, -1);
    rb_define_method(cArray, "<<", ary_append, 1);
    rb_define_method(cArray, "push", ary_push, 1);
    rb_define_method(cArray, "pop", ary_pop, 0);
    rb_define_method(cArray, "shift", ary_shift, 0);
    rb_define_method(cArray, "unshift", ary_unshift, 1);
    rb_define_method(cArray, "each", ary_each, 0);
    rb_define_method(cArray, "each_index", ary_each_index, 0);
    rb_define_method(cArray, "length", ary_length, 0);
    rb_define_alias(cArray,  "size", "length");
    rb_define_method(cArray, "index", ary_index, 1);
    rb_define_method(cArray, "indexes", ary_indexes, -2);
    rb_define_method(cArray, "clone", ary_clone, 0);
    rb_define_method(cArray, "join", ary_join_method, -1);
    rb_define_method(cArray, "reverse", ary_reverse, 0);
    rb_define_method(cArray, "sort", ary_sort, 0);
    rb_define_method(cArray, "delete", ary_delete, 1);
    rb_define_method(cArray, "delete_if", ary_delete_if, 0);
    rb_define_method(cArray, "clear", ary_clear, 0);
    rb_define_method(cArray, "fill", ary_fill, -1);
    rb_define_method(cArray, "includes", ary_includes, 1);

    rb_define_method(cArray, "assoc", ary_assoc, 1);
    rb_define_method(cArray, "rassoc", ary_rassoc, 1);

    rb_define_method(cArray, "+", ary_plus, 1);
    rb_define_method(cArray, "*", ary_times, 1);

    rb_define_method(cArray, "-", ary_diff, 1);
    rb_define_method(cArray, "&", ary_and, 1);
    rb_define_method(cArray, "|", ary_or, 1);
}
