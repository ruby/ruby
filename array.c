/************************************************

  array.c -

  $Author$
  $Date$
  created at: Fri Aug  6 09:46:12 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"


VALUE cArray;

#define ARY_DEFAULT_SIZE 16

void
memclear(mem, size)
    register VALUE *mem;
    register int size;
{
    while (size--) {
	*mem++ = Qnil;
    }
}

#define ARY_FREEZE   FL_USER1

static void
ary_modify(ary)
    VALUE ary;
{
    rb_secure(5);
    if (FL_TEST(ary, ARY_FREEZE)) {
	TypeError("can't modify frozen array");
    }
}

VALUE
ary_freeze(ary)
    VALUE ary;
{
    FL_SET(ary, ARY_FREEZE);
    return ary;
}

static VALUE
ary_frozen_p(ary)
    VALUE ary;
{
    if (FL_TEST(ary, ARY_FREEZE))
	return TRUE;
    return FALSE;
}

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
    else {
	ary->ptr = ALLOC_N(VALUE, len);
	memclear(ary->ptr, len);
    }

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
    VALUE ary;
    int i;

    if (n < 0) {
	IndexError("Negative number of items(%d)", n);
    }
    ary = ary_new2(n<ARY_DEFAULT_SIZE?ARY_DEFAULT_SIZE:n);

    va_start(ar);
    for (i=0; i<n; i++) {
	RARRAY(ary)->ptr[i] = va_arg(ar, VALUE);
    }
    va_end(ar);

    RARRAY(ary)->len = n;
    return ary;
}

VALUE
ary_new4(n, elts)
    int n;
    VALUE *elts;
{
    VALUE ary;

    ary = ary_new2(n);
    if (elts) {
	MEMCPY(RARRAY(ary)->ptr, elts, VALUE, n);
    }
    else {
	memclear(RARRAY(ary)->ptr, n);
    }
    RARRAY(ary)->len = n;

    return ary;
}

VALUE
assoc_new(car, cdr)
    VALUE car, cdr;
{
    VALUE ary;

    ary = ary_new2(2);
    RARRAY(ary)->ptr[0] = car;
    RARRAY(ary)->ptr[1] = cdr;
    RARRAY(ary)->len = 2;

    return ary;
}

static VALUE
ary_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE size;
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, klass, T_ARRAY);

    rb_scan_args(argc, argv, "01", &size);
    ary->len = 0;
    ary->capa = NIL_P(size)?ARY_DEFAULT_SIZE:NUM2INT(size);
    ary->ptr = ALLOC_N(VALUE, ary->capa);
    memclear(ary->ptr, ary->capa);
    obj_call_init((VALUE)ary);

    return (VALUE)ary;
}

static VALUE
ary_s_create(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, klass, T_ARRAY);

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

void
ary_store(ary, idx, val)
    VALUE ary;
    int idx;
    VALUE val;
{
    ary_modify(ary);
    if (idx < 0) {
	IndexError("negative index for array");
    }

    if (idx >= RARRAY(ary)->capa) {
	RARRAY(ary)->capa = idx + ARY_DEFAULT_SIZE;
	REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
    }
    if (idx > RARRAY(ary)->len) {
	memclear(RARRAY(ary)->ptr+RARRAY(ary)->len, idx-RARRAY(ary)->len+1);
    }

    if (idx >= RARRAY(ary)->len) {
	RARRAY(ary)->len = idx + 1;
    }
    RARRAY(ary)->ptr[idx] = val;
}

VALUE
ary_push(ary, item)
    VALUE ary;
    VALUE item;
{
    ary_store(ary, RARRAY(ary)->len, item);
    return ary;
}

static VALUE
ary_push_method(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    while (argc--) {
	ary_store(ary, RARRAY(ary)->len, *argv++);
    }
    return ary;
}

VALUE
ary_pop(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0) return Qnil;
    if (RARRAY(ary)->len * 10 < RARRAY(ary)->capa && RARRAY(ary)->capa > ARY_DEFAULT_SIZE) {
	RARRAY(ary)->capa = RARRAY(ary)->len * 2;
	REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
    }
    return RARRAY(ary)->ptr[--RARRAY(ary)->len];
}

VALUE
ary_shift(ary)
    VALUE ary;
{
    VALUE top;

    if (RARRAY(ary)->len == 0) return Qnil;

    top = RARRAY(ary)->ptr[0];
    RARRAY(ary)->len--;

    /* sliding items */
    MEMMOVE(RARRAY(ary)->ptr, RARRAY(ary)->ptr+1, VALUE, RARRAY(ary)->len);
    if (RARRAY(ary)->len * 10 < RARRAY(ary)->capa && RARRAY(ary)->capa > ARY_DEFAULT_SIZE) {
	RARRAY(ary)->capa = RARRAY(ary)->len * 2;
	REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
    }

    return top;
}

VALUE
ary_unshift(ary, item)
    VALUE ary, item;
{
    ary_modify(ary);
    if (RARRAY(ary)->len >= RARRAY(ary)->capa) {
	RARRAY(ary)->capa+=ARY_DEFAULT_SIZE;
	REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
    }

    /* sliding items */
    MEMMOVE(RARRAY(ary)->ptr+1, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);

    RARRAY(ary)->len++;
    return RARRAY(ary)->ptr[0] = item;
}

VALUE
ary_entry(ary, offset)
    VALUE ary;
    int offset;
{
    if (RARRAY(ary)->len == 0) return Qnil;

    if (offset < 0) {
	offset = RARRAY(ary)->len + offset;
    }
    if (offset < 0 || RARRAY(ary)->len <= offset) {
	return Qnil;
    }

    return RARRAY(ary)->ptr[offset];
}

static VALUE
ary_subseq(ary, beg, len)
    VALUE ary;
    int beg, len;
{
    VALUE ary2;

    if (beg < 0) {
	beg = RARRAY(ary)->len + beg;
	if (beg < 0) beg = 0;
    }
    if (len < 0) {
	IndexError("negative length %d", RARRAY(ary)->len);
    }
    if (len == 0) {
	return ary_new2(0);
    }
    if (beg + len > RARRAY(ary)->len) {
	len = RARRAY(ary)->len - beg;
    }
    if (len < 0) {
	len = 0;
    }

    ary2 = ary_new2(len);
    MEMCPY(RARRAY(ary2)->ptr, RARRAY(ary)->ptr+beg, VALUE, len);
    RARRAY(ary2)->len = len;

    return ary2;
}

static VALUE
beg_len(range, begp, lenp, len)
    VALUE range;
    int *begp, *lenp;
    int len;
{
    int beg, end;

    if (!range_beg_end(range, &beg, &end)) return FALSE;

    if ((beg > 0 && end > 0 || beg < 0 && end < 0) && beg > end) {
	IndexError("end smaller than beg [%d..%d]", beg, end);
    }

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
	    if (end < 0) end = -1;
	}
	if (beg > end) {
	    *lenp = 0;
	}
	else {
	    *lenp = end - beg +1;
	}
    }
    return TRUE;
}

VALUE
ary_aref(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE arg1, arg2;
    int beg, len;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2) {
	beg = NUM2INT(arg1);
	len = NUM2INT(arg2);
	if (len <= 0) {
	    return ary_new();
	}
	return ary_subseq(ary, beg, len);
    }

    /* special case - speeding up */
    if (FIXNUM_P(arg1)) {
	return ary_entry(ary, FIX2INT(arg1));
    }
    else {
	/* check if idx is Range */
	if (beg_len(arg1, &beg, &len, RARRAY(ary)->len)) {
	    return ary_subseq(ary, beg, len);
	}
    }
    if (TYPE(arg1) == T_BIGNUM) {
	IndexError("index too big");
    }
    return ary_entry(ary, NUM2INT(arg1));
}

static VALUE
ary_index(ary, val)
    VALUE ary;
    VALUE val;
{
    int i;

    for (i=0; i<RARRAY(ary)->len; i++) {
	if (rb_equal(RARRAY(ary)->ptr[i], val))
	    return INT2FIX(i);
    }
    return Qnil;
}

static VALUE
ary_rindex(ary, val)
    VALUE ary;
    VALUE val;
{
    int i = i<RARRAY(ary)->len;

    while (i--) {
	if (rb_equal(RARRAY(ary)->ptr[i], val))
	    return INT2FIX(i);
    }
    return Qnil;
}

static VALUE
ary_indexes(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE new_ary;
    int i;

    new_ary = ary_new2(argc);
    for (i=0; i<argc; i++) {
	ary_store(new_ary, i, ary_entry(ary, NUM2INT(argv[i])));
    }

    return new_ary;
}

static void
ary_replace(ary, beg, len, rpl)
    VALUE ary, rpl;
    int beg, len;
{
    ary_modify(ary);
    if (TYPE(rpl) != T_ARRAY) {
	rpl = rb_Array(rpl);
    }
    if (beg < 0) {
	beg = RARRAY(ary)->len + beg;
	if (beg < 0) beg = 0;
    }
    if (beg >= RARRAY(ary)->len) {
	len = beg + RARRAY(rpl)->len;
	if (len >= RARRAY(ary)->capa) {
	    RARRAY(ary)->capa=len;
	    REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
	}
	memclear(RARRAY(ary)->ptr+RARRAY(ary)->len, beg-RARRAY(ary)->len);
	MEMCPY(RARRAY(ary)->ptr+beg, RARRAY(rpl)->ptr, VALUE, RARRAY(rpl)->len);
	RARRAY(ary)->len = len;
    }
    else {
	int alen;

	if (beg + len > RARRAY(ary)->len) {
	    len = RARRAY(ary)->len - beg;
	}
	if (len < 0) {
	    IndexError("negative length %d", RARRAY(ary)->len);
	}

	alen = RARRAY(ary)->len + RARRAY(rpl)->len - len;
	if (alen >= RARRAY(ary)->capa) {
	    RARRAY(ary)->capa=alen;
	    REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
	}

	if (len != RARRAY(rpl)->len) {
	    MEMMOVE(RARRAY(ary)->ptr+beg+RARRAY(rpl)->len, RARRAY(ary)->ptr+beg+len,
		    VALUE, RARRAY(ary)->len-(beg+len));
	    RARRAY(ary)->len = alen;
	}
	MEMCPY(RARRAY(ary)->ptr+beg, RARRAY(rpl)->ptr, VALUE, RARRAY(rpl)->len);
    }
}

static VALUE
ary_aset(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE arg1, arg2, arg3;
    int offset;
    int beg, len;

    if (rb_scan_args(argc, argv, "21", &arg1, &arg2, &arg3) == 3) {
	beg = NUM2INT(arg1);
	len = NUM2INT(arg2);
	ary_replace(ary, beg, len, arg3);
	return arg3;
    }
    else if (FIXNUM_P(arg1)) {
	offset = FIX2INT(arg1);
	goto fixnum;
    }
    else if (beg_len(arg1, &beg, &len, RARRAY(ary)->len)) {
	/* check if idx is Range */
	ary_replace(ary, beg, len, arg2);
	return arg2;
    }
    if (TYPE(arg1) == T_BIGNUM) {
	IndexError("index too big");
    }

    offset = NUM2INT(arg1);
  fixnum:
    if (offset < 0) {
	offset = RARRAY(ary)->len + offset;
    }
    ary_store(ary, offset, arg2);
    return arg2;
}

VALUE
ary_each(ary)
    VALUE ary;
{
    int i;

    for (i=0; i<RARRAY(ary)->len; i++) {
	rb_yield(RARRAY(ary)->ptr[i]);
    }
    return Qnil;
}

static VALUE
ary_each_index(ary)
    VALUE ary;
{
    int i;

    for (i=0; i<RARRAY(ary)->len; i++) {
	rb_yield(INT2FIX(i));
    }
    return Qnil;
}

static VALUE
ary_reverse_each(ary)
    VALUE ary;
{
    int len = RARRAY(ary)->len;

    while (len--) {
	rb_yield(RARRAY(ary)->ptr[len]);
    }
    return Qnil;
}

static VALUE
ary_length(ary)
    VALUE ary;
{
    return INT2FIX(RARRAY(ary)->len);
}

static VALUE
ary_empty_p(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0)
	return TRUE;
    return FALSE;
}

static VALUE
ary_clone(ary)
    VALUE ary;
{
    VALUE ary2 = ary_new2(RARRAY(ary)->len);

    CLONESETUP(ary2, ary);
    MEMCPY(RARRAY(ary2)->ptr, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);
    RARRAY(ary2)->len = RARRAY(ary)->len;
    return ary2;
}

static VALUE
ary_dup(ary)
    VALUE ary;
{
    return ary_new4(RARRAY(ary)->len, RARRAY(ary)->ptr);
}

extern VALUE OFS;

VALUE
ary_join(ary, sep)
    VALUE ary;
    VALUE sep;
{
    int i;
    VALUE result, tmp;
    if (RARRAY(ary)->len == 0) return str_new(0, 0);

    switch (TYPE(RARRAY(ary)->ptr[0])) {
      case T_STRING:
	result = str_dup(RARRAY(ary)->ptr[0]);
	break;
      case T_ARRAY:
	result = ary_join(RARRAY(ary)->ptr[0], sep);
	break;
      default:
	result = obj_as_string(RARRAY(ary)->ptr[0]);
	break;
    }

    for (i=1; i<RARRAY(ary)->len; i++) {
	tmp = RARRAY(ary)->ptr[i];
	switch (TYPE(tmp)) {
	  case T_STRING:
	    break;
	  case T_ARRAY:
	    tmp = ary_join(tmp, sep);
	    break;
	  default:
	    tmp = obj_as_string(tmp);
	}
	if (!NIL_P(sep)) str_cat(result, RSTRING(sep)->ptr, RSTRING(sep)->len);
	str_cat(result, RSTRING(tmp)->ptr, RSTRING(tmp)->len);
	if (str_tainted(tmp)) str_taint(result);
    }

    return result;
}

static VALUE
ary_join_method(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE sep;

    rb_scan_args(argc, argv, "01", &sep);
    if (NIL_P(sep)) sep = OFS;
    if (!NIL_P(sep)) Check_Type(sep, T_STRING);

    return ary_join(ary, sep);
}

VALUE
ary_to_s(ary)
    VALUE ary;
{
    VALUE str = ary_join(ary, OFS);
    if (NIL_P(str)) return str_new(0, 0);
    return str;
}

static VALUE
ary_inspect(ary)
    VALUE ary;
{
    int i, len;
    VALUE s, str;

    if (RARRAY(ary)->len == 0) return str_new2("[]");
    str = str_new2("[");
    len = 1;

    for (i=0; i<RARRAY(ary)->len; i++) {
	s = rb_inspect(RARRAY(ary)->ptr[i]);
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
ary_reverse(ary)
    VALUE ary;
{
    VALUE *p1, *p2;
    VALUE tmp;

    if (RARRAY(ary)->len == 0) return ary;

    p1 = RARRAY(ary)->ptr;
    p2 = p1 + RARRAY(ary)->len - 1;	/* points last item */

    while (p1 < p2) {
	tmp = *p1;
	*p1 = *p2;
	*p2 = tmp;
	p1++; p2--;
    }

    return ary;
}

static VALUE
ary_reverse_method(ary)
    VALUE ary;
{
    return ary_reverse(ary_clone(ary));
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

    if (FIXNUM_P(*a)) {
	if (FIXNUM_P(*b)) return *a - *b;
    }
    else if (TYPE(*a) == T_STRING) {
	if (TYPE(*b) == T_STRING) return str_cmp(*a, *b);
    }

    retval = rb_funcall(*a, cmp, 1, *b);
    return NUM2INT(retval);
}

VALUE
ary_sort_bang(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0) return ary;

    ary_modify(ary);
    qsort(RARRAY(ary)->ptr, RARRAY(ary)->len, sizeof(VALUE),
	  iterator_p()?sort_1:sort_2);
    return ary;
}

VALUE
ary_sort(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0) return ary;
    return ary_sort_bang(ary_clone(ary));
}

VALUE
ary_delete(ary, item)
    VALUE ary;
    VALUE item;
{
    int i1, i2;

    ary_modify(ary);
    for (i1 = i2 = 0; i1 < RARRAY(ary)->len; i1++) {
	if (rb_equal(RARRAY(ary)->ptr[i1], item)) continue;
	if (i1 != i2) {
	    RARRAY(ary)->ptr[i2] = RARRAY(ary)->ptr[i1];
	}
	i2++;
    }
    if (RARRAY(ary)->len == i2) {
	if (iterator_p()) rb_yield(item);
	return Qnil;
    }
    else {
	RARRAY(ary)->len = i2;
    }

    return item;
}

VALUE
ary_delete_at(ary, at)
    VALUE ary;
    VALUE at;
{
    int i1, i2, pos;
    VALUE del = Qnil;

    ary_modify(ary);
    pos = NUM2INT(at);
    for (i1 = i2 = 0; i1 < RARRAY(ary)->len; i1++) {
	if (i1 == pos) {
	    del = RARRAY(ary)->ptr[i1];
	    continue;
	}
	if (i1 != i2) {
	    RARRAY(ary)->ptr[i2] = RARRAY(ary)->ptr[i1];
	}
	i2++;
    }
    RARRAY(ary)->len = i2;

    return del;
}

static VALUE
ary_delete_if(ary)
    VALUE ary;
{
    int i1, i2;

    ary_modify(ary);
    for (i1 = i2 = 0; i1 < RARRAY(ary)->len; i1++) {
	if (rb_yield(RARRAY(ary)->ptr[i1])) continue;
	if (i1 != i2) {
	    RARRAY(ary)->ptr[i2] = RARRAY(ary)->ptr[i1];
	}
	i2++;
    }
    RARRAY(ary)->len = i2;

    return ary;
}

static VALUE
ary_filter(ary)
    VALUE ary;
{
    int i;

    ary_modify(ary);
    for (i = 0; i < RARRAY(ary)->len; i++) {
	RARRAY(ary)->ptr[i] = rb_yield(RARRAY(ary)->ptr[i]);
    }
    return ary;
}

static VALUE
ary_replace_method(ary, ary2)
    VALUE ary, ary2;
{
    Check_Type(ary2, T_ARRAY);
    ary_replace(ary, 0, RARRAY(ary2)->len, ary2);
    return ary;
}

static VALUE
ary_clear(ary)
    VALUE ary;
{
    RARRAY(ary)->len = 0;
    if (ARY_DEFAULT_SIZE*3 < RARRAY(ary)->capa) {
	RARRAY(ary)->capa = ARY_DEFAULT_SIZE * 2;
	REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
    }
    return ary;
}

static VALUE
ary_fill(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE item, arg1, arg2;
    int beg, len, end;
    VALUE *p, *pend;

    rb_scan_args(argc, argv, "12", &item, &arg1, &arg2);
    if (NIL_P(arg2) && beg_len(arg1, &beg, &len, RARRAY(ary)->len)) {
	/* beg and len set already */
    }
    else {
	beg = NUM2INT(arg1);
	if (beg < 0) {
	    beg = RARRAY(ary)->len + beg;
	    if (beg < 0) beg = 0;
	}
	if (!NIL_P(arg2)) {
	    len = NUM2INT(arg2);
	}
	else {
	    len = RARRAY(ary)->len - beg;
	}
    }
    end = beg + len;
    if (end > RARRAY(ary)->len) {
	if (end >= RARRAY(ary)->capa) {
	    RARRAY(ary)->capa=end;
	    REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
	}
	if (beg > RARRAY(ary)->len) {
	    memclear(RARRAY(ary)->ptr+RARRAY(ary)->len, end-RARRAY(ary)->len);
	}
	RARRAY(ary)->len = end;
    }
    p = RARRAY(ary)->ptr + beg; pend = p + len;

    while (p < pend) {
	*p++ = item;
    }
    return ary;
}

VALUE
ary_plus(x, y)
    VALUE x, y;
{
    VALUE z;

    if (TYPE(y) != T_ARRAY) {
	return ary_plus(x, rb_Array(y));
    }

    z = ary_new2(RARRAY(x)->len + RARRAY(y)->len);
    MEMCPY(RARRAY(z)->ptr, RARRAY(x)->ptr, VALUE, RARRAY(x)->len);
    MEMCPY(RARRAY(z)->ptr+RARRAY(x)->len, RARRAY(y)->ptr, VALUE, RARRAY(y)->len);
    RARRAY(z)->len = RARRAY(x)->len + RARRAY(y)->len;
    return z;
}

VALUE
ary_concat(x, y)
    VALUE x, y;
{
    VALUE *p, *pend;

    if (TYPE(y) != T_ARRAY) {
	return ary_concat(x, rb_Array(y));
    }

    p = RARRAY(y)->ptr;
    pend = p + RARRAY(y)->len;
    while (p < pend) {
	ary_store(x, RARRAY(x)->len, *p);
	p++;
    }
    return x;
}

static VALUE
ary_times(ary, times)
    VALUE ary;
    VALUE times;
{
    VALUE ary2;
    int i, len;

    if (TYPE(times) == T_STRING) {
	return ary_join(ary, times);
    }

    len = NUM2INT(times) * RARRAY(ary)->len;
    ary2 = ary_new2(len);
    RARRAY(ary2)->len = len;

    if (len < 0) {
	ArgError("negative argument");
    }

    for (i=0; i<len; i+=RARRAY(ary)->len) {
	MEMCPY(RARRAY(ary2)->ptr+i, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);
    }

    return ary2;
}

VALUE
ary_assoc(ary, key)
    VALUE ary;
    VALUE key;
{
    VALUE *p, *pend;

    p = RARRAY(ary)->ptr; pend = p + RARRAY(ary)->len;
    while (p < pend) {
	if (TYPE(*p) == T_ARRAY
	    && RARRAY(*p)->len > 1
	    && rb_equal(RARRAY(*p)->ptr[0], key))
	    return *p;
	p++;
    }
    return Qnil;
}

VALUE
ary_rassoc(ary, value)
    VALUE ary;
    VALUE value;
{
    VALUE *p, *pend;

    p = RARRAY(ary)->ptr; pend = p + RARRAY(ary)->len;
    while (p < pend) {
	if (TYPE(*p) == T_ARRAY
	    && RARRAY(*p)->len > 1
	    && rb_equal(RARRAY(*p)->ptr[1], value))
	    return *p;
	p++;
    }
    return Qnil;
}

static VALUE
ary_equal(ary1, ary2)
    VALUE ary1, ary2;
{
    int i;

    if (TYPE(ary2) != T_ARRAY) return FALSE;
    if (RARRAY(ary1)->len != RARRAY(ary2)->len) return FALSE;
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (!rb_equal(RARRAY(ary1)->ptr[i], RARRAY(ary2)->ptr[i]))
	    return FALSE;
    }
    return TRUE;
}

static VALUE
ary_eql(ary1, ary2)
    VALUE ary1, ary2;
{
    int i;

    if (TYPE(ary2) != T_ARRAY) return FALSE;
    if (RARRAY(ary1)->len != RARRAY(ary2)->len)
	return FALSE;
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (!rb_eql(RARRAY(ary1)->ptr[i], RARRAY(ary2)->ptr[i]))
	    return FALSE;
    }
    return TRUE;
}

static VALUE
ary_hash(ary)
    VALUE ary;
{
    int h, i;

    h = RARRAY(ary)->len;
    for (i=0; i<RARRAY(ary)->len; i++) {
	h ^= rb_hash(RARRAY(ary)->ptr[i]);
    }
    return INT2FIX(h);
}

VALUE
ary_includes(ary, item)
    VALUE ary;
    VALUE item;
{
    int i;
    for (i=0; i<RARRAY(ary)->len; i++) {
	if (rb_equal(RARRAY(ary)->ptr[i], item)) {
	    return TRUE;
	}
    }
    return FALSE;
}

VALUE
ary_cmp(ary, ary2)
    VALUE ary;
    VALUE ary2;
{
    int i, len;

    Check_Type(ary2, T_ARRAY);
    len = RARRAY(ary)->len;
    if (len > RARRAY(ary2)->len) {
	len = RARRAY(ary2)->len;
    }
    for (i=0; i<len; i++) {
	VALUE v = rb_funcall(RARRAY(ary)->ptr[i],cmp,1,RARRAY(ary2)->ptr[i]);
	if (v != INT2FIX(0)) {
	    return v;
	}
    }
    len = RARRAY(ary)->len - RARRAY(ary2)->len;
    if (len == 0) return INT2FIX(0);
    if (len > 0) return INT2FIX(1);
    return INT2FIX(-1);
}

static VALUE
ary_diff(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE ary3;
    int i;

    Check_Type(ary2, T_ARRAY);
    ary3 = ary_new();
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (ary_includes(ary2, RARRAY(ary1)->ptr[i])) continue;
	if (ary_includes(ary3, RARRAY(ary1)->ptr[i])) continue;
	ary_push(ary3, RARRAY(ary1)->ptr[i]);
    }
    return ary3;
}

static VALUE
ary_and(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE ary3;
    int i;

    Check_Type(ary2, T_ARRAY);
    ary3 = ary_new();
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (ary_includes(ary2, RARRAY(ary1)->ptr[i])
	    && !ary_includes(ary3, RARRAY(ary1)->ptr[i])) {
	    ary_push(ary3, RARRAY(ary1)->ptr[i]);
	}
    }
    return ary3;
}

static VALUE
ary_or(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE ary3;
    int i;

    if (TYPE(ary2) != T_ARRAY) {
	if (ary_includes(ary1, ary2)) return ary1;
	else return ary_plus(ary1, ary2);
    }

    ary3 = ary_new();
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (!ary_includes(ary3, RARRAY(ary1)->ptr[i]))
		ary_push(ary3, RARRAY(ary1)->ptr[i]);
    }
    for (i=0; i<RARRAY(ary2)->len; i++) {
	if (!ary_includes(ary3, RARRAY(ary2)->ptr[i]))
		ary_push(ary3, RARRAY(ary2)->ptr[i]);
    }
    return ary3;
}

static VALUE
ary_uniq_bang(ary)
    VALUE ary;
{
    VALUE *p, *q, *t, *end;
    VALUE v;
    int i;

    ary_modify(ary);
    p = RARRAY(ary)->ptr;
    end = p + RARRAY(ary)->len;

    while (p < end) {
	v = *p++;
	q = t = p;
	while (q < end) {
	    if (rb_equal(*q, v)) q++;
	    else *t++ = *q++;
	}
	end = t;
    }
    if (RARRAY(ary)->len == (end - RARRAY(ary)->ptr)) {
	return Qnil;
    }

    RARRAY(ary)->len = (end - RARRAY(ary)->ptr);

    return ary;
}

static VALUE
ary_uniq(ary)
    VALUE ary;
{
    VALUE v = ary_uniq_bang(ary_clone(ary));

    if (NIL_P(v)) return ary;
    return v;
}

static VALUE
ary_compact_bang(ary)
    VALUE ary;
{
    VALUE *p, *t, *end;

    ary_modify(ary);
    p = t = RARRAY(ary)->ptr;
    end = p + RARRAY(ary)->len;
    while (t < end) {
	if (NIL_P(*t)) t++;
	else *p++ = *t++;
    }
    if (RARRAY(ary)->len == (p - RARRAY(ary)->ptr)) {
	return Qnil;
    }
    RARRAY(ary)->len = RARRAY(ary)->capa = (p - RARRAY(ary)->ptr);
    REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);

    return ary;
}

static VALUE
ary_compact(ary)
    VALUE ary;
{
    VALUE v = ary_compact_bang(ary_clone(ary));

    if (NIL_P(v)) return ary;
    return v;
}

static VALUE
ary_nitems(ary)
    VALUE ary;
{
    int n = 0;
    VALUE *p, *pend;

    p = RARRAY(ary)->ptr;
    pend = p + RARRAY(ary)->len;
    while (p < pend) {
	if (!NIL_P(*p)) n++;
	p++;
    }
    return INT2FIX(n);
}

static VALUE
ary_flatten_bang(ary)
    VALUE ary;
{
    int i;
    int mod = 0;

    ary_modify(ary);
    for (i=0; i<RARRAY(ary)->len; i++) {
	VALUE ary2 = RARRAY(ary)->ptr[i];
	if (TYPE(ary2) == T_ARRAY) {
	    ary_replace(ary, i--, 1, ary2);
	    mod = 1;
	}
    }
    if (mod == 0) return Qnil;
    return ary;
}

static VALUE
ary_flatten(ary)
    VALUE ary;
{
    VALUE v = ary_flatten_bang(ary_clone(ary));

    if (NIL_P(v)) return ary;
    return v;
}

extern VALUE mEnumerable;

void
Init_Array()
{
    cArray  = rb_define_class("Array", cObject);
    rb_include_module(cArray, mEnumerable);

    rb_define_singleton_method(cArray, "new", ary_s_new, -1);
    rb_define_singleton_method(cArray, "[]", ary_s_create, -1);
    rb_define_method(cArray, "to_s", ary_to_s, 0);
    rb_define_method(cArray, "inspect", ary_inspect, 0);
    rb_define_method(cArray, "to_a", ary_to_a, 0);

    rb_define_method(cArray, "freeze",  ary_freeze, 0);
    rb_define_method(cArray, "frozen?",  ary_frozen_p, 0);

    rb_define_method(cArray, "==", ary_equal, 1);
    rb_define_method(cArray, "eql?", ary_eql, 1);
    rb_define_method(cArray, "hash", ary_hash, 0);

    rb_define_method(cArray, "[]", ary_aref, -1);
    rb_define_method(cArray, "[]=", ary_aset, -1);
    rb_define_method(cArray, "concat", ary_concat, 1);
    rb_define_method(cArray, "<<", ary_push, 1);
    rb_define_method(cArray, "push", ary_push_method, -1);
    rb_define_method(cArray, "pop", ary_pop, 0);
    rb_define_method(cArray, "shift", ary_shift, 0);
    rb_define_method(cArray, "unshift", ary_unshift, 1);
    rb_define_method(cArray, "each", ary_each, 0);
    rb_define_method(cArray, "each_index", ary_each_index, 0);
    rb_define_method(cArray, "reverse_each", ary_reverse_each, 0);
    rb_define_method(cArray, "length", ary_length, 0);
    rb_define_alias(cArray,  "size", "length");
    rb_define_method(cArray, "empty?", ary_empty_p, 0);
    rb_define_method(cArray, "index", ary_index, 1);
    rb_define_method(cArray, "rindex", ary_rindex, 1);
    rb_define_method(cArray, "indexes", ary_indexes, -1);
    rb_define_method(cArray, "indices", ary_indexes, -1);
    rb_define_method(cArray, "clone", ary_clone, 0);
    rb_define_method(cArray, "dup", ary_dup, 0);
    rb_define_method(cArray, "join", ary_join_method, -1);
    rb_define_method(cArray, "reverse", ary_reverse_method, 0);
    rb_define_method(cArray, "reverse!", ary_reverse, 0);
    rb_define_method(cArray, "sort", ary_sort, 0);
    rb_define_method(cArray, "sort!", ary_sort_bang, 0);
    rb_define_method(cArray, "delete", ary_delete, 1);
    rb_define_method(cArray, "delete_at", ary_delete_at, 1);
    rb_define_method(cArray, "delete_if", ary_delete_if, 0);
    rb_define_method(cArray, "filter", ary_filter, 0);
    rb_define_method(cArray, "replace", ary_replace_method, 1);
    rb_define_method(cArray, "clear", ary_clear, 0);
    rb_define_method(cArray, "fill", ary_fill, -1);
    rb_define_method(cArray, "include?", ary_includes, 1);
    rb_define_method(cArray, "===", ary_includes, 1);
    rb_define_method(cArray, "<=>", ary_cmp, 1);

    rb_define_method(cArray, "assoc", ary_assoc, 1);
    rb_define_method(cArray, "rassoc", ary_rassoc, 1);

    rb_define_method(cArray, "+", ary_plus, 1);
    rb_define_method(cArray, "*", ary_times, 1);

    rb_define_method(cArray, "-", ary_diff, 1);
    rb_define_method(cArray, "&", ary_and, 1);
    rb_define_method(cArray, "|", ary_or, 1);

    rb_define_method(cArray, "uniq", ary_uniq, 0);
    rb_define_method(cArray, "uniq!", ary_uniq_bang, 0);
    rb_define_method(cArray, "compact", ary_compact, 0);
    rb_define_method(cArray, "compact!", ary_compact_bang, 0);
    rb_define_method(cArray, "flatten", ary_flatten, 0);
    rb_define_method(cArray, "flatten!", ary_flatten_bang, 0);
    rb_define_method(cArray, "nitems", ary_nitems, 0);

    cmp = rb_intern("<=>");
}
