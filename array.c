/************************************************

  array.c -

  $Author: matz $
  $Date: 1994/12/06 09:29:47 $
  created at: Fri Aug  6 09:46:12 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE C_Array;

static ID eq;

VALUE rb_to_a();

#define ARY_DEFAULT_SIZE 16

VALUE
ary_new2(len)
{
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, C_Array, T_ARRAY);

    ary->len = 0;
    ary->capa = len;
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
    int len, i;

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
    memcpy(ary->ptr, elts, sizeof(VALUE)*n);
    ary->len = n;

    return (VALUE)ary;
}

VALUE
assoc_new(elm1, elm2)
    VALUE elm1, elm2;
{
    struct RArray *ary;

    ary = (struct RArray*)ary_new2(2);
    ary->ptr[0] = elm1;
    ary->ptr[1] = elm2;
    ary->len = 2;

    return (VALUE)ary;
}

static VALUE
Sary_new(class)
    VALUE class;
{
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, class, T_ARRAY);

    ary->len = 0;
    ary->capa = ARY_DEFAULT_SIZE;
    ary->ptr = ALLOC_N(VALUE, ARY_DEFAULT_SIZE);

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
	ary->capa = idx + ary->capa/5;
	REALLOC_N(ary->ptr, VALUE, ary->capa);
    }
    if (idx >= ary->len) {
	memset(ary->ptr+ary->len, 0, sizeof(VALUE)*(idx-ary->len+1));
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
    return item;
}

static VALUE
Fary_append(ary, item)
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
    memmove(ary->ptr, ary->ptr+1, sizeof(VALUE)*(ary->len));

    return top;
}

VALUE
ary_unshift(ary, item)
    struct RArray *ary;
{
    VALUE top;

    if (ary->len >= ary->capa) {
	ary->capa+=ARY_DEFAULT_SIZE;
	REALLOC_N(ary->ptr, VALUE, ary->capa);
    }

    /* sliding items */
    memmove(ary->ptr+1, ary->ptr, sizeof(VALUE)*(ary->len));

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
    VALUE *ptr;

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
    memmove(ary2->ptr, ary->ptr+beg, sizeof(VALUE)*len);
    ary2->len = len;

    return (VALUE)ary2;
}

extern VALUE C_Range;

static void
range_beg_end(range, begp, lenp, len)
    VALUE range;
    int *begp, *lenp;
    int len;
{
    int beg, end;

    beg = rb_iv_get(range, "start"); beg = NUM2INT(beg);
    end = rb_iv_get(range, "end");   end = NUM2INT(end);
    if (beg < 0) {
	beg = len + beg;
	if (beg < 0) beg = 0;
    }
    if (end < 0) {
	end = len + end;
	if (end < 0) end = 0;
    }
    if (beg > end) {
	int tmp;

	if (verbose) {
	    Warning("start %d is bigger than end %d", beg, end);
	}
	tmp = beg; beg = end; end = tmp;
    }
    *begp = beg; *lenp = end - beg + 1;
}

static VALUE
Fary_aref(ary, args)
    struct RArray *ary;
    VALUE args;
{
    VALUE arg1, arg2;

    if (rb_scan_args(args, "11", &arg1, &arg2) == 2) {
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
    if (obj_is_kind_of(arg1, C_Range)) {
	int beg, len;

	range_beg_end(arg1, &beg, &len, ary->len);
	return ary_subseq(ary, beg, len);
    }

    return ary_entry(ary, NUM2INT(arg1));
}

static VALUE
Fary_index(ary, val)
    struct RArray *ary;
    VALUE val;
{
    int i;

    for (i=0; i<ary->len; i++) {
	if (rb_funcall(ary->ptr[i], eq, 1, val))
	    return INT2FIX(i);
    }
    return Qnil;
}

static VALUE
Fary_indexes(ary, args)
    struct RArray *ary, *args;
{
    VALUE *p, *pend;
    VALUE new;
    int i = 0;

    if (!args || args->len == 1) {
	args = (struct RArray*)rb_to_a(args->ptr[0]);
    }

    new = ary_new2(args->len);

    p = args->ptr; pend = p + args->len;
    while (p < pend) {
	astore(new, i++, ary_entry(ary, NUM2INT(*p)));
	p++;
    }
    return new;
}

static VALUE
Fary_aset(ary, args)
    struct RArray *ary;
    VALUE args;
{
    VALUE arg1, arg2;
    struct RArray *arg3;
    int offset;

    if (rb_scan_args(args, "21", &arg1, &arg2, &arg3) == 3) {
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
	    memset(ary->ptr+ary->len, 0, sizeof(VALUE)*(beg-ary->len));
	    memcpy(ary->ptr+beg, arg3->ptr, sizeof(VALUE)*arg3->len);
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

	    memmove(ary->ptr+beg+arg3->len, ary->ptr+beg+len,
		    sizeof(VALUE)*(ary->len-(beg+len)));
	    memmove(ary->ptr+beg, arg3->ptr, sizeof(VALUE)*arg3->len);
	    ary->len = alen;
	}
	return (VALUE)arg3;
    }

    /* check if idx is Range */
    if (obj_is_kind_of(arg1, C_Range)) {
	int beg, len;

	Check_Type(arg2, T_ARRAY);
	range_beg_end(arg1, &beg, &len, ary->len);
	if (ary->len < beg) {
	    len = beg + RARRAY(arg2)->len;
	    if (len >= ary->capa) {
		ary->capa=len;
		REALLOC_N(ary->ptr, VALUE, ary->capa);
	    }
	    memset(ary->ptr+ary->len, 0, sizeof(VALUE)*(beg-ary->len));
	    memcpy(ary->ptr+beg, RARRAY(arg2)->ptr,
		   sizeof(VALUE)*RARRAY(arg2)->len);
	    ary->len = len;
	}
	else {
	    int alen;

	    alen = ary->len + RARRAY(arg2)->len - len;
	    if (alen >= ary->capa) {
		ary->capa=alen;
		REALLOC_N(ary->ptr, VALUE, ary->capa);
	    }

	    memmove(ary->ptr+beg+RARRAY(arg2)->len, ary->ptr+beg+len,
		    sizeof(VALUE)*(ary->len-(beg+len)));
	    memmove(ary->ptr+beg, RARRAY(arg2)->ptr,
		    sizeof(VALUE)*RARRAY(arg2)->len);
	    ary->len = alen;
	}
	return arg2;
    }

    offset = NUM2INT(arg1);
    if (offset < 0) {
	offset = ary->len + offset;
    }
    astore(ary, offset, arg2);
    return arg2;
}

static VALUE
Fary_each(ary)
    struct RArray *ary;
{
    int i;

    if (iterator_p()) {
	for (i=0; i<ary->len; i++) {
	    rb_yield(ary->ptr[i]);
	}
    }
    else {
	return (VALUE)ary;
    }
}

static VALUE
Fary_each_index(ary)
    struct RArray *ary;
{
    int i;

    for (i=0; i<ary->len; i++) {
	rb_yield(INT2FIX(i));
    }
}

static VALUE
Fary_length(ary)
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
    memcpy(RARRAY(ary2)->ptr, ary->ptr, sizeof(VALUE)*ary->len);
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
	result = str_clone(ary->ptr[0]);
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
Fary_join(ary, args)
    struct RArray *ary;
    VALUE args;
{
    VALUE sep;

    rb_scan_args(args, "01", &sep);
    if (sep == Qnil) sep = OFS;

    if (sep != Qnil)
	Check_Type(sep, T_STRING);

    return ary_join(ary, sep);
}

VALUE
Fary_to_s(ary)
    VALUE ary;
{
    VALUE str = ary_join(ary, OFS);
    if (str == Qnil) return str_new(0, 0);
    return str;
}

VALUE
Fary_print_on(ary, port)
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

#define INSPECT_MAX 10

static VALUE
Fary_inspect(ary)
    struct RArray *ary;
{
    int i, len;
    VALUE str;
    char *p;

    ary = (struct RArray*)ary_clone(ary);

    len = ary->len;
    for (i=0; i<len; i++) {
	if (i > INSPECT_MAX) break;
	ary->ptr[i] = rb_funcall(ary->ptr[i], rb_intern("_inspect"), 0, Qnil);
    }

    str = str_new2(", ");
    str = ary_join(ary, str);
    if (str == Qnil) return str_new2("[]");
    len = RSTRING(str)->len;
    if (ary->len > INSPECT_MAX)
	str_grow(str, len+5);
    else
	str_grow(str, len+2);

    p = RSTRING(str)->ptr;
    memmove(p+1, p, len);
    p[0] = '[';
    if (ary->len > INSPECT_MAX)
	strcpy(p+len, "...]");
    else
	p[len+1] = ']';

    return str;
}

static VALUE
Fary_to_a(ary)
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

static VALUE
Fary_reverse(ary)
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
    VALUE retval = rb_funcall(*a, cmp, 1, *b);
    return NUM2INT(retval);
}

VALUE
Fary_sort(ary)
    struct RArray *ary;
{
    qsort(ary->ptr, ary->len, sizeof(VALUE), iterator_p()?sort_1:sort_2);
    return (VALUE)ary;
}

static VALUE
Fary_delete(ary, item)
    struct RArray *ary;
    VALUE item;
{
    int i1, i2;

    for (i1 = i2 = 0; i1 < ary->len; i1++) {
	if (rb_funcall(ary->ptr[i1], eq, 1, item)) continue;
	if (i1 != i2) {
	    ary->ptr[i2] = ary->ptr[i1];
	}
	i2++;
    }
    ary->len = i2;

    return (VALUE)ary;
}

static VALUE
Fary_delete_if(ary)
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
Fary_clear(ary)
    struct RArray *ary;
{
    ary->len = 0;
    return (VALUE)ary;
}

static VALUE
Fary_fill(ary, args)
    struct RArray *ary;
    VALUE args;
{
    VALUE item, arg1, arg2;
    int beg, len, end;
    VALUE *p, *pend;

    rb_scan_args(args, "12", &item, &arg1, &arg2);
    if (arg2 == Qnil && obj_is_kind_of(arg1, C_Range)) {
	range_beg_end(arg1, &beg, &len, ary->len);
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
	    memset(ary->ptr+ary->len, 0, sizeof(VALUE)*(end-ary->len));
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
Fary_plus(x, y)
    struct RArray *x, *y;
{
    struct RArray *z;

    switch (TYPE(y)) {
      case T_ARRAY:
	z = (struct RArray*)ary_new2(x->len + y->len);
	memcpy(z->ptr, x->ptr, x->len*sizeof(VALUE));
	memcpy(z->ptr+x->len, y->ptr, y->len*sizeof(VALUE));
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
Fary_times(ary, times)
    struct RArray *ary;
    VALUE times;
{
    struct RArray *ary2;
    int i, len;

    len = NUM2INT(times) * ary->len;
    ary2 = (struct RArray*)ary_new2(len);
    ary2->len = len;

    for (i=0; i<len; i+=ary->len) {
	memcpy(ary2->ptr+i, ary->ptr, ary->len*sizeof(VALUE));
    }

    return (VALUE)ary2;
}

VALUE
Fary_assoc(ary, key)
    struct RArray *ary;
    VALUE key;
{
    VALUE *p, *pend;

    p = ary->ptr; pend = p + ary->len;
    while (p < pend) {
	if (TYPE(*p) == T_ARRAY
	    && RARRAY(*p)->len == 2
	    && rb_funcall(RARRAY(*p)->ptr[0], eq, 1, key))
	    return *p;
    }
    return Qnil;
}

VALUE
Fary_rassoc(ary, value)
    struct RArray *ary;
    VALUE value;
{
    VALUE *p, *pend;

    p = ary->ptr; pend = p + ary->len;
    while (p < pend) {
	if (TYPE(*p) == T_ARRAY
	    && RARRAY(*p)->len == 2
	    && rb_funcall(RARRAY(*p)->ptr[1], eq, 1, value))
	    return *p;
    }
    return Qnil;
}

static VALUE
Fary_equal(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    int i;

    if (TYPE(ary2) != T_ARRAY) return FALSE;
    if (ary1->len != ary2->len) return FALSE;
    for (i=0; i<ary1->len; i++) {
	if (!rb_funcall(ary1->ptr[i], eq, 1, ary2->ptr[i]))
	    return FALSE;
    }
    return TRUE;
}

static VALUE
Fary_hash(ary)
    struct RArray *ary;
{
    int i, h;
    ID hash = rb_intern("hash");

    h = 0;
    for (i=0; i<ary->len; i++) {
	h += rb_funcall(ary->ptr[i], hash, 0);
    }
    h += ary->len;
    return INT2FIX(h);
}

static VALUE
Fary_includes(ary, item)
    struct RArray *ary;
    VALUE item;
{
    int i;
    for (i=0; i<ary->len; i++) {
	if (rb_funcall(ary->ptr[i], eq, 1, item)) {
	    return TRUE;
	}
    }
    return FALSE;
}

static VALUE
Fary_diff(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    VALUE ary3;
    int i, j;

    Check_Type(ary2, T_ARRAY);
    ary3 = ary_new();
    for (i=0; i<ary1->len; i++) {
	if (Fary_includes(ary2, ary1->ptr[i])) continue;
	if (Fary_includes(ary3, ary1->ptr[i])) continue;
	ary_push(ary3, ary1->ptr[i]);
    }
    return ary3;
}

static VALUE
Fary_and(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    VALUE ary3;
    int i, j;

    Check_Type(ary2, T_ARRAY);
    ary3 = ary_new();
    for (i=0; i<ary1->len; i++) {
	if (Fary_includes(ary2, ary1->ptr[i])
	    && !Fary_includes(ary3, ary1->ptr[i])) {
	    ary_push(ary3, ary1->ptr[i]);
	}
    }
    return ary3;
}

static VALUE
Fary_or(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    VALUE ary3;
    int i;

    if (TYPE(ary2) != T_ARRAY) {
	if (Fary_includes(ary1, ary2)) return (VALUE)ary1;
	else return Fary_plus(ary1, ary2);
    }

    ary3 = ary_new();
    for (i=0; i<ary1->len; i++) {
	if (!Fary_includes(ary3, ary1->ptr[i]))
		ary_push(ary3, ary1->ptr[i]);
    }
    for (i=0; i<ary2->len; i++) {
	if (!Fary_includes(ary3, ary2->ptr[i]))
		ary_push(ary3, ary2->ptr[i]);
    }
    return ary3;
}

extern VALUE C_Kernel;
extern VALUE M_Enumerable;

Init_Array()
{
    C_Array  = rb_define_class("Array", C_Object);
    rb_include_module(C_Array, M_Enumerable);

    rb_define_single_method(C_Array, "new", Sary_new, 0);
    rb_define_method(C_Array, "to_s", Fary_to_s, 0);
    rb_define_method(C_Array, "_inspect", Fary_inspect, 0);
    rb_define_method(C_Array, "to_a", Fary_to_a, 0);

    rb_define_method(C_Array, "print_on", Fary_print_on, 1);

    rb_define_method(C_Array, "==", Fary_equal, 1);
    rb_define_method(C_Array, "hash", Fary_hash, 0);
    rb_define_method(C_Array, "[]", Fary_aref, -2);
    rb_define_method(C_Array, "[]=", Fary_aset, -2);
    rb_define_method(C_Array, "<<", Fary_append, 1);
    rb_define_method(C_Array, "push", ary_push, 1);
    rb_define_method(C_Array, "pop", ary_pop, 0);
    rb_define_method(C_Array, "shift", ary_shift, 0);
    rb_define_method(C_Array, "unshift", ary_unshift, 1);
    rb_define_method(C_Array, "each", Fary_each, 0);
    rb_define_method(C_Array, "each_index", Fary_each_index, 0);
    rb_define_method(C_Array, "length", Fary_length, 0);
    rb_define_alias(C_Array,  "size", "length");
    rb_define_method(C_Array, "index", Fary_index, 1);
    rb_define_method(C_Array, "indexes", Fary_indexes, -2);
    rb_define_method(C_Array, "clone", ary_clone, 0);
    rb_define_method(C_Array, "join", Fary_join, -2);
    rb_define_method(C_Array, "reverse", Fary_reverse, 0);
    rb_define_method(C_Array, "sort", Fary_sort, 0);
    rb_define_method(C_Array, "delete", Fary_delete, 1);
    rb_define_method(C_Array, "delete_if", Fary_delete_if, 0);
    rb_define_method(C_Array, "clear", Fary_clear, 0);
    rb_define_method(C_Array, "fill", Fary_fill, -2);
    rb_define_method(C_Array, "includes", Fary_includes, 1);

    rb_define_method(C_Array, "assoc", Fary_assoc, 1);
    rb_define_method(C_Array, "rassoc", Fary_rassoc, 1);

    rb_define_method(C_Array, "+", Fary_plus, 1);
    rb_define_method(C_Array, "*", Fary_times, 1);

    rb_define_method(C_Array, "-", Fary_diff, 1);
    rb_define_method(C_Array, "&", Fary_and, 1);
    rb_define_method(C_Array, "|", Fary_or, 1);

    cmp = rb_intern("<=>");
    eq = rb_intern("==");

    rb_define_method(C_Kernel, "::", assoc_new, 1);
}
