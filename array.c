/************************************************

  array.c -

  $Author: matz $
  $Date: 1996/12/25 10:42:18 $
  created at: Fri Aug  6 09:46:12 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE cArray;

VALUE rb_to_a();

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
    struct RArray* ary;
    int i;

    if (n < 0) {
	IndexError("Negative number of items(%d)", n);
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
ary_s_new(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    VALUE size;
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, class, T_ARRAY);

    rb_scan_args(argc, argv, "01", &size);
    ary->len = 0;
    ary->capa = NIL_P(size)?ARY_DEFAULT_SIZE:NUM2INT(size);
    ary->ptr = ALLOC_N(VALUE, ary->capa);
    memclear(ary->ptr, ary->capa);

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

void
ary_store(ary, idx, val)
    struct RArray *ary;
    int idx;
    VALUE val;
{
    ary_modify(ary);
    if (idx < 0) {
	IndexError("negative index for array");
    }

    if (idx >= ary->capa) {
	ary->capa = idx + ARY_DEFAULT_SIZE;
	REALLOC_N(ary->ptr, VALUE, ary->capa);
    }
    if (idx > ary->len) {
	memclear(ary->ptr+ary->len, idx-ary->len+1);
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
    ary_store(ary, ary->len, item);
    return (VALUE)ary;
}

static VALUE
ary_push_method(argc, argv, ary)
    int argc;
    VALUE *argv;
    struct RArray *ary;
{
    while (argc--) {
	ary_store(ary, ary->len, *argv++);
    }
    return (VALUE)ary;
}

VALUE
ary_pop(ary)
    struct RArray *ary;
{
    if (ary->len == 0) return Qnil;
    if (ary->len * 10 < ary->capa && ary->capa > ARY_DEFAULT_SIZE) {
	ary->capa = ary->len * 2;
	REALLOC_N(ary->ptr, VALUE, ary->capa);
    }
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
    if (ary->len * 10 < ary->capa && ary->capa > ARY_DEFAULT_SIZE) {
	ary->capa = ary->len * 2;
	REALLOC_N(ary->ptr, VALUE, ary->capa);
    }

    return top;
}

VALUE
ary_unshift(ary, item)
    struct RArray *ary;
    int item;
{
    ary_modify(ary);
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
	IndexError("negative length %d", ary->len);
    }
    if (len == 0) {
	return ary_new2(0);
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
	if (end > len) end = len;
	if (beg > end) {
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
	if (beg_len(arg1, &beg, &len, ary->len)) {
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
    struct RArray *ary;
    VALUE val;
{
    int i;

    for (i=0; i<ary->len; i++) {
	if (rb_equal(ary->ptr[i], val))
	    return INT2FIX(i);
    }
    return Qnil;
}

static VALUE
ary_indexes(ary, args)
    struct RArray *ary, *args;
{
    VALUE *p, *pend;
    VALUE new_ary;
    int i = 0;

    if (!args || NIL_P(args)) {
	return ary_new2(0);
    }

    new_ary = ary_new2(args->len);

    p = args->ptr; pend = p + args->len;
    while (p < pend) {
	ary_store(new_ary, i++, ary_entry(ary, NUM2INT(*p)));
	p++;
    }
    return new_ary;
}

static void
ary_replace(ary, beg, len, rpl)
    struct RArray *ary, *rpl;
    int beg, len;
{
    ary_modify(ary);
    if (TYPE(rpl) != T_ARRAY) {
	rpl = (struct RArray*)rb_to_a(rpl);
    }
    if (beg < 0) {
	beg = ary->len + beg;
	if (beg < 0) beg = 0;
    }
    if (beg >= ary->len) {
	len = beg + rpl->len;
	if (len >= ary->capa) {
	    ary->capa=len;
	    REALLOC_N(ary->ptr, VALUE, ary->capa);
	}
	memclear(ary->ptr+ary->len, beg-ary->len);
	MEMCPY(ary->ptr+beg, rpl->ptr, VALUE, rpl->len);
	ary->len = len;
    }
    else {
	int alen;

	if (beg + len > ary->len) {
	    len = ary->len - beg;
	}
	if (len < 0) {
	    IndexError("negative length %d", ary->len);
	}

	alen = ary->len + rpl->len - len;
	if (alen >= ary->capa) {
	    ary->capa=alen;
	    REALLOC_N(ary->ptr, VALUE, ary->capa);
	}

	if (len != RARRAY(rpl)->len) {
	    MEMMOVE(ary->ptr+beg+rpl->len, ary->ptr+beg+len,
		    VALUE, ary->len-(beg+len));
	    ary->len = alen;
	}
	MEMCPY(ary->ptr+beg, rpl->ptr, VALUE, rpl->len);
    }
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
    int beg, len;

    if (rb_scan_args(argc, argv, "21", &arg1, &arg2, &arg3) == 3) {
	beg = NUM2INT(arg1);
	len = NUM2INT(arg2);
	ary_replace(ary, beg, len, arg3);
	return (VALUE)arg3;
    }
    else if (FIXNUM_P(arg1)) {
	offset = FIX2INT(arg1);
	goto fixnum;
    }
    else if (beg_len(arg1, &beg, &len, ary->len)) {
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
	offset = ary->len + offset;
    }
    ary_store(ary, offset, arg2);
    return arg2;
}

VALUE
ary_each(ary)
    struct RArray *ary;
{
    int i;

    for (i=0; i<ary->len; i++) {
	rb_yield(ary->ptr[i]);
    }
    return Qnil;
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
ary_reverse_each(ary)
    struct RArray *ary;
{
    int len = ary->len;

    while (len--) {
	rb_yield(ary->ptr[len]);
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
ary_empty_p(ary)
    struct RArray *ary;
{
    if (ary->len == 0)
	return TRUE;
    return FALSE;
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

    switch (TYPE(ary->ptr[0])) {
      case T_STRING:
	result = str_dup(ary->ptr[0]);
	break;
      case T_ARRAY:
	result = ary_join(ary->ptr[0], sep);
	break;
      default:
	result = obj_as_string(ary->ptr[0]);
	break;
    }

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
	if (!NIL_P(sep)) str_cat(result, sep->ptr, sep->len);
	str_cat(result, RSTRING(tmp)->ptr, RSTRING(tmp)->len);
	if (str_tainted(tmp)) str_taint(result);
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

VALUE
ary_print_on(ary, port)
    struct RArray *ary;
    VALUE port;
{
    int i;

    for (i=0; i<ary->len; i++) {
	if (!NIL_P(OFS) && i>0) {
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

    if (ary->len == 0) return str_new2("[]");
    str = str_new2("[");
    len = 1;

    for (i=0; i<ary->len; i++) {
	s = rb_inspect(ary->ptr[i]);
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
    VALUE *p1, *p2;
    VALUE tmp;

    p1 = ary->ptr;
    p2 = p1 + ary->len - 1;	/* points last item */

    while (p1 < p2) {
	tmp = *p1;
	*p1 = *p2;
	*p2 = tmp;
	p1++; p2--;
    }

    return (VALUE)ary;
}

static VALUE
ary_reverse_method(ary)
    struct RArray *ary;
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
    struct RArray *ary;
{
    ary_modify(ary);
    qsort(ary->ptr, ary->len, sizeof(VALUE), iterator_p()?sort_1:sort_2);
    return (VALUE)ary;
}

VALUE
ary_sort(ary)
    VALUE ary;
{
    return ary_sort_bang(ary_clone(ary));
}

VALUE
ary_delete(ary, item)
    struct RArray *ary;
    VALUE item;
{
    int i1, i2;

    ary_modify(ary);
    for (i1 = i2 = 0; i1 < ary->len; i1++) {
	if (rb_equal(ary->ptr[i1], item)) continue;
	if (i1 != i2) {
	    ary->ptr[i2] = ary->ptr[i1];
	}
	i2++;
    }
    if (ary->len == i2) {
	if (iterator_p()) rb_yield(item);
	return Qnil;
    }
    else {
	ary->len = i2;
    }

    return item;
}

VALUE
ary_delete_at(ary, at)
    struct RArray *ary;
    VALUE at;
{
    int i1, i2, pos;
    VALUE del = Qnil;

    ary_modify(ary);
    pos = NUM2INT(at);
    for (i1 = i2 = 0; i1 < ary->len; i1++) {
	if (i1 == pos) {
	    del = ary->ptr[i1];
	    continue;
	}
	if (i1 != i2) {
	    ary->ptr[i2] = ary->ptr[i1];
	}
	i2++;
    }
    ary->len = i2;

    return del;
}

static VALUE
ary_delete_if(ary)
    struct RArray *ary;
{
    int i1, i2;

    ary_modify(ary);
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

#if 0
static VALUE
ary_replace(ary)
    struct RArray *ary;
{
    int i;

    for (i = 0; i < ary->len; i++) {
	ary->ptr[i] = rb_yield(ary->ptr[i]);
    }

    return (VALUE)ary;
}
#endif

static VALUE
ary_clear(ary)
    struct RArray *ary;
{
    ary->len = 0;
    if (ARY_DEFAULT_SIZE*3 < ary->capa) {
	ary->capa = ARY_DEFAULT_SIZE * 2;
	REALLOC_N(ary->ptr, VALUE, ary->capa);
    }
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
    if (NIL_P(arg2) && beg_len(arg1, &beg, &len, ary->len)) {
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
	    memclear(ary->ptr+ary->len, end-ary->len);
	}
	ary->len = end;
    }
    p = ary->ptr + beg; pend = p + len;

    while (p < pend) {
	*p++ = item;
    }
    return (VALUE)ary;
}

VALUE
ary_plus(x, y)
    struct RArray *x, *y;
{
    struct RArray *z;

    if (TYPE(y) != T_ARRAY) {
	return ary_plus(x, rb_to_a(y));
    }

    z = (struct RArray*)ary_new2(x->len + y->len);
    MEMCPY(z->ptr, x->ptr, VALUE, x->len);
    MEMCPY(z->ptr+x->len, y->ptr, VALUE, y->len);
    z->len = x->len + RARRAY(y)->len;
    return (VALUE)z;
}

VALUE
ary_concat(x, y)
    struct RArray *x, *y;
{
    VALUE *p, *pend;

    if (TYPE(y) != T_ARRAY) {
	return ary_concat(x, rb_to_a(y));
    }

    p = y->ptr;
    pend = p + y->len;
    while (p < pend) {
	ary_store(x, x->len, *p);
	p++;
    }
    return (VALUE)x;
}

static VALUE
ary_times(ary, times)
    struct RArray *ary;
    VALUE times;
{
    struct RArray *ary2;
    int i, len;

    if (TYPE(times) == T_STRING) {
	return ary_join(ary, times);
    }

    len = NUM2INT(times) * ary->len;
    ary2 = (struct RArray*)ary_new2(len);
    ary2->len = len;

    if (len < 0) {
	ArgError("negative argument");
    }

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
	p++;
    }
    return Qnil;
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
	    && RARRAY(*p)->len > 1
	    && rb_equal(RARRAY(*p)->ptr[1], value))
	    return *p;
	p++;
    }
    return Qnil;
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
ary_eql(ary1, ary2)
    struct RArray *ary1, *ary2;
{
    int i;

    if (TYPE(ary2) != T_ARRAY) return FALSE;
    if (ary1->len != ary2->len) return FALSE;
    for (i=0; i<ary1->len; i++) {
	if (!rb_eql(ary1->ptr[i], ary2->ptr[i]))
	    return FALSE;
    }
    return TRUE;
}

static VALUE
ary_hash(ary)
    struct RArray *ary;
{
    int h, i;

    h = ary->len;
    for (i=0; i<ary->len; i++) {
	h ^= rb_hash(ary->ptr[i]);
    }
    return INT2FIX(h);
}

VALUE
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

static VALUE
ary_compact_bang(ary)
    struct RArray *ary;
{
    VALUE *p, *t, *end;

    ary_modify(ary);
    p = t = ary->ptr;
    end = p + ary->len;
    while (t < end) {
	if (NIL_P(*t)) t++;
	else *p++ = *t++;
    }
    ary->len = ary->capa = (p - ary->ptr);
    REALLOC_N(ary->ptr, VALUE, ary->len);

    return (VALUE)ary;
}

static VALUE
ary_compact(ary)
    struct RArray *ary;
{
    return ary_compact_bang(ary_clone(ary));
}

static VALUE
ary_nitems(ary)
    struct RArray *ary;
{
    int n = 0;
    VALUE *p, *pend;

    p = ary->ptr;
    pend = p + ary->len;
    while (p < pend) {
	if (!NIL_P(*p)) n++;
	p++;
    }
    return INT2FIX(n);
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
    rb_define_method(cArray, "indexes", ary_indexes, -2);
    rb_define_method(cArray, "clone", ary_clone, 0);
    rb_define_method(cArray, "join", ary_join_method, -1);
    rb_define_method(cArray, "reverse", ary_reverse_method, 0);
    rb_define_method(cArray, "reverse!", ary_reverse, 0);
    rb_define_method(cArray, "sort", ary_sort, 0);
    rb_define_method(cArray, "sort!", ary_sort_bang, 0);
    rb_define_method(cArray, "delete", ary_delete, 1);
    rb_define_method(cArray, "delete_at", ary_delete_at, 1);
    rb_define_method(cArray, "delete_if", ary_delete_if, 0);
#if 0
    rb_define_method(cArray, "replace", ary_replace, 0);
#endif
    rb_define_method(cArray, "clear", ary_clear, 0);
    rb_define_method(cArray, "fill", ary_fill, -1);
    rb_define_method(cArray, "include?", ary_includes, 1);

    rb_define_method(cArray, "assoc", ary_assoc, 1);
    rb_define_method(cArray, "rassoc", ary_rassoc, 1);

    rb_define_method(cArray, "+", ary_plus, 1);
    rb_define_method(cArray, "*", ary_times, 1);

    rb_define_method(cArray, "-", ary_diff, 1);
    rb_define_method(cArray, "&", ary_and, 1);
    rb_define_method(cArray, "|", ary_or, 1);

    rb_define_method(cArray, "compact", ary_compact, 0);
    rb_define_method(cArray, "compact!", ary_compact_bang, 0);
    rb_define_method(cArray, "nitems", ary_nitems, 0);

    cmp = rb_intern("<=>");
}
