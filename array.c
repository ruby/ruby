/************************************************

  array.c -

  $Author$
  $Date$
  created at: Fri Aug  6 09:46:12 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

VALUE rb_cArray;

#define ARY_DEFAULT_SIZE 16

void
rb_mem_clear(mem, size)
    register VALUE *mem;
    register int size;
{
    while (size--) {
	*mem++ = Qnil;
    }
}

static void
memfill(mem, size, val)
    register VALUE *mem;
    register int size;
    register VALUE val;
{
    while (size--) {
	*mem++ = val;
    }
}

#define ARY_FREEZE   FL_USER1
#define ARY_TMPLOCK  FL_USER2

static void
rb_ary_modify(ary)
    VALUE ary;
{
    rb_secure(5);
    if (FL_TEST(ary, ARY_FREEZE|ARY_TMPLOCK)) {
	rb_raise(rb_eTypeError, "can't modify frozen array");
    }
}

VALUE
rb_ary_freeze(ary)
    VALUE ary;
{
    FL_SET(ary, ARY_FREEZE);
    return ary;
}

static VALUE
rb_ary_frozen_p(ary)
    VALUE ary;
{
    if (FL_TEST(ary, ARY_FREEZE|ARY_TMPLOCK))
	return Qtrue;
    return Qfalse;
}

VALUE
rb_ary_new2(len)
    int len;
{
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, rb_cArray, T_ARRAY);

    if (len < 0) {
	rb_raise(rb_eArgError, "negative array size (or size too big)");
    }
    if (len > 0 && len*sizeof(VALUE) <= 0) {
	rb_raise(rb_eArgError, "array size too big");
    }
    ary->len = 0;
    ary->capa = len;
    ary->ptr = 0;
    ary->ptr = ALLOC_N(VALUE, len);

    return (VALUE)ary;
}

VALUE
rb_ary_new()
{
    return rb_ary_new2(ARY_DEFAULT_SIZE);
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
rb_ary_new3(int n, ...)
#else
rb_ary_new3(n, va_alist)
    int n;
    va_dcl
#endif
{
    va_list ar;
    VALUE ary;
    int i;

    if (n < 0) {
	rb_raise(rb_eIndexError, "Negative number of items(%d)", n);
    }
    ary = rb_ary_new2(n<ARY_DEFAULT_SIZE?ARY_DEFAULT_SIZE:n);

    va_init_list(ar, n);
    for (i=0; i<n; i++) {
	RARRAY(ary)->ptr[i] = va_arg(ar, VALUE);
    }
    va_end(ar);

    RARRAY(ary)->len = n;
    return ary;
}

VALUE
rb_ary_new4(n, elts)
    int n;
    VALUE *elts;
{
    VALUE ary;

    ary = rb_ary_new2(n);
    if (elts) {
	MEMCPY(RARRAY(ary)->ptr, elts, VALUE, n);
    }
    RARRAY(ary)->len = n;

    return ary;
}

VALUE
rb_assoc_new(car, cdr)
    VALUE car, cdr;
{
    VALUE ary;

    ary = rb_ary_new2(2);
    RARRAY(ary)->ptr[0] = car;
    RARRAY(ary)->ptr[1] = cdr;
    RARRAY(ary)->len = 2;

    return ary;
}

static VALUE
rb_ary_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    int len = 0;
    VALUE size, val;
    NEWOBJ(ary, struct RArray);
    OBJSETUP(ary, klass, T_ARRAY);

    ary->len = 0;
    ary->ptr = 0;
    if (rb_scan_args(argc, argv, "02", &size, &val) == 0) {
	ary->capa = ARY_DEFAULT_SIZE;
    }
    else {
	int capa = NUM2INT(size);

	if (capa < 0) {
	    rb_raise(rb_eArgError, "negative array size");
	}
	if (capa > 0 && capa*sizeof(VALUE) <= 0) {
	    rb_raise(rb_eArgError, "array size too big");
	}
	ary->capa = capa;
	len = capa;
    }
    ary->ptr = ALLOC_N(VALUE, ary->capa);
    memfill(ary->ptr, len, val);
    ary->len = len;
    rb_obj_call_init((VALUE)ary);

    return (VALUE)ary;
}

static VALUE
rb_ary_s_create(argc, argv, klass)
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
rb_ary_store(ary, idx, val)
    VALUE ary;
    int idx;
    VALUE val;
{
    rb_ary_modify(ary);
    if (idx < 0) {
	rb_raise(rb_eIndexError, "negative index for array");
    }

    if (idx >= RARRAY(ary)->capa) {
	RARRAY(ary)->capa = idx + ARY_DEFAULT_SIZE;
	REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
    }
    if (idx > RARRAY(ary)->len) {
	rb_mem_clear(RARRAY(ary)->ptr+RARRAY(ary)->len,
		     idx-RARRAY(ary)->len+1);
    }

    if (idx >= RARRAY(ary)->len) {
	RARRAY(ary)->len = idx + 1;
    }
    RARRAY(ary)->ptr[idx] = val;
}

VALUE
rb_ary_push(ary, item)
    VALUE ary;
    VALUE item;
{
    rb_ary_store(ary, RARRAY(ary)->len, item);
    return ary;
}

static VALUE
rb_ary_push_method(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    while (argc--) {
	rb_ary_store(ary, RARRAY(ary)->len, *argv++);
    }
    return ary;
}

VALUE
rb_ary_pop(ary)
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
rb_ary_shift(ary)
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
rb_ary_unshift(ary, item)
    VALUE ary, item;
{
    rb_ary_modify(ary);
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
rb_ary_entry(ary, offset)
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
rb_ary_subseq(ary, beg, len)
    VALUE ary;
    int beg, len;
{
    VALUE ary2;

    if (beg < 0) {
	beg = RARRAY(ary)->len + beg;
	if (beg < 0) beg = 0;
    }
    if (len < 0) {
	rb_raise(rb_eIndexError, "negative length %d", RARRAY(ary)->len);
    }
    if (len == 0) {
	return rb_ary_new2(0);
    }
    if (beg + len > RARRAY(ary)->len) {
	len = RARRAY(ary)->len - beg;
    }
    if (len < 0) {
	len = 0;
    }

    ary2 = rb_ary_new2(len);
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

    if (!rb_range_beg_end(range, &beg, &end)) return Qfalse;

    if ((beg > 0 && end > 0 || beg < 0 && end < 0) && beg > end) {
	rb_raise(rb_eIndexError, "end smaller than beg [%d..%d]", beg, end);
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
    return Qtrue;
}

VALUE
rb_ary_aref(argc, argv, ary)
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
	    return rb_ary_new();
	}
	return rb_ary_subseq(ary, beg, len);
    }

    /* special case - speeding up */
    if (FIXNUM_P(arg1)) {
	return rb_ary_entry(ary, FIX2INT(arg1));
    }
    else if (TYPE(arg1) == T_BIGNUM) {
	rb_raise(rb_eIndexError, "index too big");
    }
    else if (beg_len(arg1, &beg, &len, RARRAY(ary)->len)) {
	/* check if idx is Range */
	return rb_ary_subseq(ary, beg, len);
    }
    return rb_ary_entry(ary, NUM2INT(arg1));
}

static VALUE
rb_ary_index(ary, val)
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
rb_ary_rindex(ary, val)
    VALUE ary;
    VALUE val;
{
    int i = RARRAY(ary)->len;

    while (i--) {
	if (rb_equal(RARRAY(ary)->ptr[i], val))
	    return INT2FIX(i);
    }
    return Qnil;
}

static VALUE
rb_ary_indexes(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE new_ary;
    int i;

    new_ary = rb_ary_new2(argc);
    for (i=0; i<argc; i++) {
	rb_ary_store(new_ary, i, rb_ary_entry(ary, NUM2INT(argv[i])));
    }

    return new_ary;
}

static void
rb_ary_replace(ary, beg, len, rpl)
    VALUE ary, rpl;
    int beg, len;
{
    rb_ary_modify(ary);
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
	rb_mem_clear(RARRAY(ary)->ptr+RARRAY(ary)->len, beg-RARRAY(ary)->len);
	MEMCPY(RARRAY(ary)->ptr+beg, RARRAY(rpl)->ptr, VALUE, RARRAY(rpl)->len);
	RARRAY(ary)->len = len;
    }
    else {
	int alen;

	if (beg + len > RARRAY(ary)->len) {
	    len = RARRAY(ary)->len - beg;
	}
	if (len < 0) {
	    rb_raise(rb_eIndexError, "negative length %d", RARRAY(ary)->len);
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
rb_ary_aset(argc, argv, ary)
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
	rb_ary_replace(ary, beg, len, arg3);
	return arg3;
    }
    else if (FIXNUM_P(arg1)) {
	offset = FIX2INT(arg1);
	goto fixnum;
    }
    else if (beg_len(arg1, &beg, &len, RARRAY(ary)->len)) {
	/* check if idx is Range */
	rb_ary_replace(ary, beg, len, arg2);
	return arg2;
    }
    if (TYPE(arg1) == T_BIGNUM) {
	rb_raise(rb_eIndexError, "index too big");
    }

    offset = NUM2INT(arg1);
  fixnum:
    if (offset < 0) {
	offset = RARRAY(ary)->len + offset;
    }
    rb_ary_store(ary, offset, arg2);
    return arg2;
}

VALUE
rb_ary_each(ary)
    VALUE ary;
{
    int i;

    for (i=0; i<RARRAY(ary)->len; i++) {
	rb_yield(RARRAY(ary)->ptr[i]);
    }
    return Qnil;
}

static VALUE
rb_ary_each_index(ary)
    VALUE ary;
{
    int i;

    for (i=0; i<RARRAY(ary)->len; i++) {
	rb_yield(INT2FIX(i));
    }
    return Qnil;
}

static VALUE
rb_ary_reverse_each(ary)
    VALUE ary;
{
    int len = RARRAY(ary)->len;

    while (len--) {
	rb_yield(RARRAY(ary)->ptr[len]);
    }
    return Qnil;
}

static VALUE
rb_ary_length(ary)
    VALUE ary;
{
    return INT2FIX(RARRAY(ary)->len);
}

static VALUE
rb_ary_empty_p(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0)
	return Qtrue;
    return Qfalse;
}

static VALUE
rb_ary_clone(ary)
    VALUE ary;
{
    VALUE ary2 = rb_ary_new2(RARRAY(ary)->len);

    CLONESETUP(ary2, ary);
    MEMCPY(RARRAY(ary2)->ptr, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);
    RARRAY(ary2)->len = RARRAY(ary)->len;
    return ary2;
}

static VALUE
rb_ary_dup(ary)
    VALUE ary;
{
    return rb_ary_new4(RARRAY(ary)->len, RARRAY(ary)->ptr);
}

static VALUE
to_ary(ary)
    VALUE ary;
{
    return rb_convert_type(ary, T_ARRAY, "Array", "to_ary");
}

extern VALUE rb_output_fs;

VALUE
rb_ary_join(ary, sep)
    VALUE ary;
    VALUE sep;
{
    int i;
    VALUE result, tmp;
    if (RARRAY(ary)->len == 0) return rb_str_new(0, 0);

    switch (TYPE(RARRAY(ary)->ptr[0])) {
      case T_STRING:
	result = rb_str_dup(RARRAY(ary)->ptr[0]);
	break;
      case T_ARRAY:
	result = rb_ary_join(RARRAY(ary)->ptr[0], sep);
	break;
      default:
	result = rb_obj_as_string(RARRAY(ary)->ptr[0]);
	break;
    }

    for (i=1; i<RARRAY(ary)->len; i++) {
	tmp = RARRAY(ary)->ptr[i];
	switch (TYPE(tmp)) {
	  case T_STRING:
	    break;
	  case T_ARRAY:
	    tmp = rb_ary_join(tmp, sep);
	    break;
	  default:
	    tmp = rb_obj_as_string(tmp);
	}
	if (!NIL_P(sep)) rb_str_concat(result, sep);
	rb_str_cat(result, RSTRING(tmp)->ptr, RSTRING(tmp)->len);
	if (rb_str_tainted(tmp)) rb_str_taint(result);
    }

    return result;
}

static VALUE
rb_ary_join_method(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE sep;

    rb_scan_args(argc, argv, "01", &sep);
    if (NIL_P(sep)) sep = rb_output_fs;

    return rb_ary_join(ary, sep);
}

VALUE
rb_ary_to_s(ary)
    VALUE ary;
{
    VALUE str = rb_ary_join(ary, rb_output_fs);
    if (NIL_P(str)) return rb_str_new(0, 0);
    return str;
}

static VALUE
rb_ary_inspect(ary)
    VALUE ary;
{
    int i, len;
    VALUE s, str;

    if (RARRAY(ary)->len == 0) return rb_str_new2("[]");
    str = rb_str_new2("[");
    len = 1;

    for (i=0; i<RARRAY(ary)->len; i++) {
	s = rb_inspect(RARRAY(ary)->ptr[i]);
	if (i > 0) rb_str_cat(str, ", ", 2);
	rb_str_cat(str, RSTRING(s)->ptr, RSTRING(s)->len);
	len += RSTRING(s)->len + 2;
    }
    rb_str_cat(str, "]", 1);

    return str;
}

static VALUE
rb_ary_to_a(ary)
    VALUE ary;
{
    return ary;
}

VALUE
rb_ary_reverse(ary)
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
rb_ary_reverse_method(ary)
    VALUE ary;
{
    return rb_ary_reverse(rb_ary_dup(ary));
}

static ID cmp;

static int
sort_1(a, b)
    VALUE *a, *b;
{
    VALUE retval = rb_yield(rb_assoc_new(*a, *b));
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
    else if (TYPE(*a) == T_STRING && TYPE(*b) == T_STRING) {
	return rb_str_cmp(*a, *b);
    }

    retval = rb_funcall(*a, cmp, 1, *b);
    return NUM2INT(retval);
}

static VALUE
sort_internal(ary)
    VALUE ary;
{
    qsort(RARRAY(ary)->ptr, RARRAY(ary)->len, sizeof(VALUE),
	  rb_iterator_p()?sort_1:sort_2);
    return ary;
}

static VALUE
sort_unlock(ary)
    VALUE ary;
{
    FL_UNSET(ary, ARY_TMPLOCK);
    return ary;
}

VALUE
rb_ary_sort_bang(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0) return ary;

    rb_ary_modify(ary);
    FL_SET(ary, ARY_TMPLOCK);	/* prohibit modification during sort */
    rb_ensure(sort_internal, ary, sort_unlock, ary);
    return ary;
}

VALUE
rb_ary_sort(ary)
    VALUE ary;
{
    if (RARRAY(ary)->len == 0) return ary;
    return rb_ary_sort_bang(rb_ary_dup(ary));
}

VALUE
rb_ary_delete(ary, item)
    VALUE ary;
    VALUE item;
{
    int i1, i2;

    rb_ary_modify(ary);
    for (i1 = i2 = 0; i1 < RARRAY(ary)->len; i1++) {
	if (rb_equal(RARRAY(ary)->ptr[i1], item)) continue;
	if (i1 != i2) {
	    RARRAY(ary)->ptr[i2] = RARRAY(ary)->ptr[i1];
	}
	i2++;
    }
    if (RARRAY(ary)->len == i2) {
	if (rb_iterator_p()) {
	    return rb_yield(item);
	}
	return Qnil;
    }
    else {
	RARRAY(ary)->len = i2;
    }

    return item;
}

VALUE
rb_ary_delete_at(ary, at)
    VALUE ary;
    VALUE at;
{
    int i1, i2, pos;
    VALUE del = Qnil;

    rb_ary_modify(ary);
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
rb_ary_delete_if(ary)
    VALUE ary;
{
    int i1, i2;

    rb_ary_modify(ary);
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
rb_ary_filter(ary)
    VALUE ary;
{
    int i;

    rb_ary_modify(ary);
    for (i = 0; i < RARRAY(ary)->len; i++) {
	RARRAY(ary)->ptr[i] = rb_yield(RARRAY(ary)->ptr[i]);
    }
    return ary;
}

static VALUE
rb_ary_replace_method(ary, ary2)
    VALUE ary, ary2;
{
    ary2 = to_ary(ary2);
    rb_ary_replace(ary, 0, RARRAY(ary2)->len, ary2);
    return ary;
}

static VALUE
rb_ary_clear(ary)
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
rb_ary_fill(argc, argv, ary)
    int argc;
    VALUE *argv;
    VALUE ary;
{
    VALUE item, arg1, arg2;
    int beg, len, end;
    VALUE *p, *pend;

    if (rb_scan_args(argc, argv, "12", &item, &arg1, &arg2) == 2 &&
	beg_len(arg1, &beg, &len, RARRAY(ary)->len)) {
	/* beg and len set already */
    }
    else {
	beg = NIL_P(arg1)?0:NUM2INT(arg1);
	if (beg < 0) {
	    beg = RARRAY(ary)->len + beg;
	    if (beg < 0) beg = 0;
	}
	len = NIL_P(arg2)?RARRAY(ary)->len - beg:NUM2INT(arg2);
    }
    rb_ary_modify(ary);
    end = beg + len;
    if (end > RARRAY(ary)->len) {
	if (end >= RARRAY(ary)->capa) {
	    RARRAY(ary)->capa=end;
	    REALLOC_N(RARRAY(ary)->ptr, VALUE, RARRAY(ary)->capa);
	}
	if (beg > RARRAY(ary)->len) {
	    rb_mem_clear(RARRAY(ary)->ptr+RARRAY(ary)->len,end-RARRAY(ary)->len);
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
rb_ary_plus(x, y)
    VALUE x, y;
{
    VALUE z;

    if (TYPE(y) != T_ARRAY) {
	return rb_ary_plus(x, rb_Array(y));
    }

    z = rb_ary_new2(RARRAY(x)->len + RARRAY(y)->len);
    MEMCPY(RARRAY(z)->ptr, RARRAY(x)->ptr, VALUE, RARRAY(x)->len);
    MEMCPY(RARRAY(z)->ptr+RARRAY(x)->len, RARRAY(y)->ptr, VALUE, RARRAY(y)->len);
    RARRAY(z)->len = RARRAY(x)->len + RARRAY(y)->len;
    return z;
}

VALUE
rb_ary_concat(x, y)
    VALUE x, y;
{
    VALUE *p, *pend;

    if (TYPE(y) != T_ARRAY) {
	return rb_ary_concat(x, rb_Array(y));
    }

    p = RARRAY(y)->ptr;
    pend = p + RARRAY(y)->len;
    while (p < pend) {
	rb_ary_store(x, RARRAY(x)->len, *p);
	p++;
    }
    return x;
}

static VALUE
rb_ary_times(ary, times)
    VALUE ary;
    VALUE times;
{
    VALUE ary2;
    int i, len;

    if (TYPE(times) == T_STRING) {
	return rb_ary_join(ary, times);
    }

    len = NUM2INT(times);
    if (len < 0) {
	rb_raise(rb_eArgError, "negative argument");
    }
    len *= RARRAY(ary)->len;

    ary2 = rb_ary_new2(len);
    RARRAY(ary2)->len = len;

    for (i=0; i<len; i+=RARRAY(ary)->len) {
	MEMCPY(RARRAY(ary2)->ptr+i, RARRAY(ary)->ptr, VALUE, RARRAY(ary)->len);
    }

    return ary2;
}

VALUE
rb_ary_assoc(ary, key)
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
rb_ary_rassoc(ary, value)
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
rb_ary_equal(ary1, ary2)
    VALUE ary1, ary2;
{
    int i;

    if (TYPE(ary2) != T_ARRAY) return Qfalse;
    if (RARRAY(ary1)->len != RARRAY(ary2)->len) return Qfalse;
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (!rb_equal(RARRAY(ary1)->ptr[i], RARRAY(ary2)->ptr[i]))
	    return Qfalse;
    }
    return Qtrue;
}

static VALUE
rb_ary_eql(ary1, ary2)
    VALUE ary1, ary2;
{
    int i;

    if (TYPE(ary2) != T_ARRAY) return Qfalse;
    if (RARRAY(ary1)->len != RARRAY(ary2)->len)
	return Qfalse;
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (!rb_eql(RARRAY(ary1)->ptr[i], RARRAY(ary2)->ptr[i]))
	    return Qfalse;
    }
    return Qtrue;
}

static VALUE
rb_ary_hash(ary)
    VALUE ary;
{
    int h, i;

    h = RARRAY(ary)->len;
    for (i=0; i<RARRAY(ary)->len; i++) {
	int n = rb_hash(RARRAY(ary)->ptr[i]);
	h ^= NUM2LONG(n);
    }
    return INT2FIX(h);
}

VALUE
rb_ary_includes(ary, item)
    VALUE ary;
    VALUE item;
{
    int i;
    for (i=0; i<RARRAY(ary)->len; i++) {
	if (rb_equal(RARRAY(ary)->ptr[i], item)) {
	    return Qtrue;
	}
    }
    return Qfalse;
}

static VALUE
rb_ary_cmp(ary, ary2)
    VALUE ary;
    VALUE ary2;
{
    int i, len;

    ary2 = to_ary(ary2);
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
rb_ary_diff(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE ary3;
    int i;

    ary2 = to_ary(ary2);
    ary3 = rb_ary_new();
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (rb_ary_includes(ary2, RARRAY(ary1)->ptr[i])) continue;
	if (rb_ary_includes(ary3, RARRAY(ary1)->ptr[i])) continue;
	rb_ary_push(ary3, RARRAY(ary1)->ptr[i]);
    }
    return ary3;
}

static VALUE
rb_ary_and(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE ary3;
    int i;

    ary2 = to_ary(ary2);
    ary3 = rb_ary_new();
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (rb_ary_includes(ary2, RARRAY(ary1)->ptr[i])
	    && !rb_ary_includes(ary3, RARRAY(ary1)->ptr[i])) {
	    rb_ary_push(ary3, RARRAY(ary1)->ptr[i]);
	}
    }
    return ary3;
}

static VALUE
rb_ary_or(ary1, ary2)
    VALUE ary1, ary2;
{
    VALUE ary3;
    int i;

    if (TYPE(ary2) != T_ARRAY) {
	if (rb_ary_includes(ary1, ary2)) return ary1;
	else return rb_ary_plus(ary1, ary2);
    }

    ary3 = rb_ary_new();
    for (i=0; i<RARRAY(ary1)->len; i++) {
	if (!rb_ary_includes(ary3, RARRAY(ary1)->ptr[i]))
		rb_ary_push(ary3, RARRAY(ary1)->ptr[i]);
    }
    for (i=0; i<RARRAY(ary2)->len; i++) {
	if (!rb_ary_includes(ary3, RARRAY(ary2)->ptr[i]))
		rb_ary_push(ary3, RARRAY(ary2)->ptr[i]);
    }
    return ary3;
}

static VALUE
rb_ary_uniq_bang(ary)
    VALUE ary;
{
    VALUE *p, *q, *t, *end;
    VALUE v;

    rb_ary_modify(ary);
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
rb_ary_uniq(ary)
    VALUE ary;
{
    VALUE v = rb_ary_uniq_bang(rb_ary_dup(ary));

    if (NIL_P(v)) return ary;
    return v;
}

static VALUE
rb_ary_compact_bang(ary)
    VALUE ary;
{
    VALUE *p, *t, *end;

    rb_ary_modify(ary);
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
rb_ary_compact(ary)
    VALUE ary;
{
    VALUE v = rb_ary_compact_bang(rb_ary_dup(ary));

    if (NIL_P(v)) return ary;
    return v;
}

static VALUE
rb_ary_nitems(ary)
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
rb_ary_flatten_bang(ary)
    VALUE ary;
{
    int i;
    int mod = 0;

    rb_ary_modify(ary);
    for (i=0; i<RARRAY(ary)->len; i++) {
	VALUE ary2 = RARRAY(ary)->ptr[i];
	if (TYPE(ary2) == T_ARRAY) {
	    rb_ary_replace(ary, i--, 1, ary2);
	    mod = 1;
	}
    }
    if (mod == 0) return Qnil;
    return ary;
}

static VALUE
rb_ary_flatten(ary)
    VALUE ary;
{
    VALUE v = rb_ary_flatten_bang(rb_ary_dup(ary));

    if (NIL_P(v)) return ary;
    return v;
}

void
Init_Array()
{
    rb_cArray  = rb_define_class("Array", rb_cObject);
    rb_include_module(rb_cArray, rb_mEnumerable);

    rb_define_singleton_method(rb_cArray, "new", rb_ary_s_new, -1);
    rb_define_singleton_method(rb_cArray, "[]", rb_ary_s_create, -1);
    rb_define_method(rb_cArray, "to_s", rb_ary_to_s, 0);
    rb_define_method(rb_cArray, "inspect", rb_ary_inspect, 0);
    rb_define_method(rb_cArray, "to_a", rb_ary_to_a, 0);
    rb_define_method(rb_cArray, "to_ary", rb_ary_to_a, 0);

    rb_define_method(rb_cArray, "freeze",  rb_ary_freeze, 0);
    rb_define_method(rb_cArray, "frozen?",  rb_ary_frozen_p, 0);

    rb_define_method(rb_cArray, "==", rb_ary_equal, 1);
    rb_define_method(rb_cArray, "eql?", rb_ary_eql, 1);
    rb_define_method(rb_cArray, "hash", rb_ary_hash, 0);

    rb_define_method(rb_cArray, "[]", rb_ary_aref, -1);
    rb_define_method(rb_cArray, "[]=", rb_ary_aset, -1);
    rb_define_method(rb_cArray, "concat", rb_ary_concat, 1);
    rb_define_method(rb_cArray, "<<", rb_ary_push, 1);
    rb_define_method(rb_cArray, "push", rb_ary_push_method, -1);
    rb_define_method(rb_cArray, "pop", rb_ary_pop, 0);
    rb_define_method(rb_cArray, "shift", rb_ary_shift, 0);
    rb_define_method(rb_cArray, "unshift", rb_ary_unshift, 1);
    rb_define_method(rb_cArray, "each", rb_ary_each, 0);
    rb_define_method(rb_cArray, "each_index", rb_ary_each_index, 0);
    rb_define_method(rb_cArray, "reverse_each", rb_ary_reverse_each, 0);
    rb_define_method(rb_cArray, "length", rb_ary_length, 0);
    rb_define_alias(rb_cArray,  "size", "length");
    rb_define_method(rb_cArray, "empty?", rb_ary_empty_p, 0);
    rb_define_method(rb_cArray, "index", rb_ary_index, 1);
    rb_define_method(rb_cArray, "rindex", rb_ary_rindex, 1);
    rb_define_method(rb_cArray, "indexes", rb_ary_indexes, -1);
    rb_define_method(rb_cArray, "indices", rb_ary_indexes, -1);
    rb_define_method(rb_cArray, "clone", rb_ary_clone, 0);
    rb_define_method(rb_cArray, "dup", rb_ary_dup, 0);
    rb_define_method(rb_cArray, "join", rb_ary_join_method, -1);
    rb_define_method(rb_cArray, "reverse", rb_ary_reverse_method, 0);
    rb_define_method(rb_cArray, "reverse!", rb_ary_reverse, 0);
    rb_define_method(rb_cArray, "sort", rb_ary_sort, 0);
    rb_define_method(rb_cArray, "sort!", rb_ary_sort_bang, 0);
    rb_define_method(rb_cArray, "delete", rb_ary_delete, 1);
    rb_define_method(rb_cArray, "delete_at", rb_ary_delete_at, 1);
    rb_define_method(rb_cArray, "delete_if", rb_ary_delete_if, 0);
    rb_define_method(rb_cArray, "filter", rb_ary_filter, 0);
    rb_define_method(rb_cArray, "replace", rb_ary_replace_method, 1);
    rb_define_method(rb_cArray, "clear", rb_ary_clear, 0);
    rb_define_method(rb_cArray, "fill", rb_ary_fill, -1);
    rb_define_method(rb_cArray, "include?", rb_ary_includes, 1);
    rb_define_method(rb_cArray, "===", rb_ary_includes, 1);
    rb_define_method(rb_cArray, "<=>", rb_ary_cmp, 1);

    rb_define_method(rb_cArray, "assoc", rb_ary_assoc, 1);
    rb_define_method(rb_cArray, "rassoc", rb_ary_rassoc, 1);

    rb_define_method(rb_cArray, "+", rb_ary_plus, 1);
    rb_define_method(rb_cArray, "*", rb_ary_times, 1);

    rb_define_method(rb_cArray, "-", rb_ary_diff, 1);
    rb_define_method(rb_cArray, "&", rb_ary_and, 1);
    rb_define_method(rb_cArray, "|", rb_ary_or, 1);

    rb_define_method(rb_cArray, "uniq", rb_ary_uniq, 0);
    rb_define_method(rb_cArray, "uniq!", rb_ary_uniq_bang, 0);
    rb_define_method(rb_cArray, "compact", rb_ary_compact, 0);
    rb_define_method(rb_cArray, "compact!", rb_ary_compact_bang, 0);
    rb_define_method(rb_cArray, "flatten", rb_ary_flatten, 0);
    rb_define_method(rb_cArray, "flatten!", rb_ary_flatten_bang, 0);
    rb_define_method(rb_cArray, "nitems", rb_ary_nitems, 0);

    cmp = rb_intern("<=>");
}
