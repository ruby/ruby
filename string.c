/************************************************

  string.c -

  $Author: matz $
  $Date: 1995/01/10 10:43:01 $
  created at: Mon Aug  9 17:12:58 JST 1993

  Copyright (C) 1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"

#include <stdio.h>
#include <ctype.h>

VALUE C_String;

#define STRLEN(s) RSTRING(s)->len

VALUE
str_new(ptr, len)
    char *ptr;
    UINT len;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, C_String, T_STRING);

    str->len = len;
    str->orig = Qnil;
    str->ptr = ALLOC_N(char,len+1);
    if (ptr) {
	memcpy(str->ptr, ptr, len);
    }
    str->ptr[len] = '\0';
    return (VALUE)str;
}

VALUE
str_new2(ptr)
    char *ptr;
{
    return str_new(ptr, strlen(ptr));
}

VALUE
str_new3(str)
    struct RString *str;
{
    NEWOBJ(str2, struct RString);
    OBJSETUP(str2, C_String, T_STRING);

    str2->len = str->len;
    str2->ptr = str->ptr;
    str2->orig = str;

    return (VALUE)str2;
}

#define as_str(str) (struct RString*)obj_as_string(str)

static ID pr_str;

VALUE
obj_as_string(obj)
    VALUE obj;
{
    VALUE str;

    if (TYPE(obj) == T_STRING) {
	return obj;
    }
    str = rb_funcall(obj, pr_str, 0);
    if (TYPE(str) != T_STRING)
	return Fkrn_to_s(obj);
    return str;
}

VALUE
str_clone(str)
    struct RString *str;
{
    VALUE obj;

    if (str->orig)
	obj = str_new3(str->orig);
    else
	obj = str_new(str->ptr, str->len);
    CLONESETUP(obj, str);
    return obj;
}

static VALUE
Sstr_new(class, str)
    VALUE class;
    struct RString *str;
{
    Check_Type(str, T_STRING);
    {
	NEWOBJ(str2, struct RString);
	OBJSETUP(str2, class, T_STRING);

	str2->len = str->len;
	str2->ptr = ALLOC_N(char, str->len+1);
	if (str2->ptr) {
	    memcpy(str2->ptr, str->ptr, str->len);
	}
	str2->ptr[str->len] = '\0';
	str2->orig = Qnil;
	return (VALUE)str2;
    }
}

static VALUE
Fstr_length(str)
    struct RString *str;
{
    return INT2FIX(str->len);
}

VALUE
Fstr_plus(str1, str2)
    struct RString *str1, *str2;
{
    struct RString *str3;

    str2 = as_str(str2);
    str3 = (struct RString*)str_new(0, str1->len+str2->len);
    memcpy(str3->ptr, str1->ptr, str1->len);
    memcpy(str3->ptr+str1->len, str2->ptr, str2->len);
    str3->ptr[str3->len] = '\0';

    return (VALUE)str3;
}

VALUE
Fstr_times(str, times)
    struct RString *str;
    VALUE times;
{
    struct RString *str2;
    int i;

    times = NUM2INT(times);

    str2 = (struct RString*)str_new(0, str->len*times);
    for (i=0; i<times; i++) {
	memcpy(str2->ptr+(i*str->len), str->ptr, str->len);
    }
    str2->ptr[str2->len] = '\0';

    return (VALUE)str2;
}

extern VALUE C_Range;

static VALUE
Fstr_dot2(left, right)
    VALUE left, right;
{
    extern VALUE C_Range;
    VALUE str;

    Check_Type(right, T_STRING);
    str = range_new(left, right);
    return str;
}

VALUE
str_substr(str, start, len)
    struct RString *str;
    int start, len;
{
    struct RString *str2;

    if (start < 0) {
	start = str->len + start;
    }
    if (str->len <= start) {
	Fail("index %d out of range [0..%d]", start, str->len-1);
    }
    if (len < 0) {
	Fail("Negative length %d", len);
    }

    str2 = (struct RString*)str_new(str->ptr+start, len);

    return (VALUE)str2;
}

VALUE
str_subseq(str, beg, end)
    struct RString *str;
    int beg, end;
{
    int len;

    if (beg < 0) {
	beg = str->len + beg;
	if (beg < 0) beg = 0;
    }
    if (end < 0) {
	end = str->len + end;
	if (end < 0) end = 0;
    }

    if (beg > end) {
	int tmp;

	Warning("start %d is bigger than end %d", beg, end);
	tmp = beg; beg = end; end = tmp;
    }

    if (beg >= str->len) {
	return str_new(0, 0);
    }
    if (str->len < end) {
	end = str->len;
    }

    len = end - beg + 1;
    if (len < 0) {
	Fail("end %d too small(size %d)", end, str->len);
    }

    return str_substr(str, beg, len);
}

extern VALUE ignorecase;

void
str_modify(str)
    struct RString *str;
{
    if (str->orig == Qnil) return;
    str->ptr = ALLOC_N(char, str->len+1);
    if (str->ptr) {
	memcpy(str->ptr, str->orig->ptr, str->len+1);
    }
    str->orig = Qnil;
}

VALUE
str_grow(str, len)
    struct RString *str;
    UINT len;
{
    str_modify(str);
    if (len > 0) {
	REALLOC_N(str->ptr, char, len + 1);
	str->len = len;
	str->ptr[len] = '\0';	/* sentinel */
    }
    return (VALUE)str;
}

VALUE
str_cat(str, ptr, len)
    struct RString *str;
    char *ptr;
    UINT len;
{
    str_modify(str);

    if (len > 0) {
	REALLOC_N(str->ptr, char, str->len + len + 1);
	if (ptr)
	    memcpy(str->ptr + str->len, ptr, len);
	str->len += len;
	str->ptr[str->len] = '\0'; /* sentinel */
    }
    return (VALUE)str;
}

static VALUE
Fstr_concat(str1, str2)
    struct RString *str1, *str2;
{
    str2 = as_str(str2);
    str_cat(str1, str2->ptr, str2->len);
    return (VALUE)str1;
}

static
str_hash(str)
    struct RString *str;
{
    int len = str->len;
    unsigned char *p = (unsigned char*)str->ptr;
    int key = 0;

    if (ignorecase) {
	while (len--) {
	    key = key*65599 + *p;
	}
    }
    else {
	while (len--) {
	    key = key*65599 + toupper(*p);
	}
    }
    return key;
}

static VALUE
Fstr_hash(str)
    VALUE str;
{
    int key = str_hash(str);
    return INT2FIX(key);
}

#define min(a,b) (((a)>(b))?(b):(a))

int
str_cmp(str1, str2)
    struct RString *str1, *str2;
{
    UINT len;
    int retval;

    if (ignorecase != Qnil) {
	return str_cicmp(str1, str2);
    }

    len = min(str1->len, str2->len);
    retval = memcmp(str1->ptr, str2->ptr, len);
    if (retval == 0) {
	return str1->ptr[len] - str2->ptr[len];
    }
    return retval;
}

static VALUE
Fstr_equal(str1, str2)
    struct RString *str1, *str2;
{
    if (TYPE(str2) != T_STRING)
	return FALSE;

    if (str1->len == str2->len
	&& str_cmp(str1, str2) == 0) {
	return TRUE;
    }
    return FALSE;
}

static VALUE
Fstr_cmp(str1, str2)
    VALUE str1, str2;
{
    int result;

    Check_Type(str2, T_STRING);
    result = str_cmp(str1, str2);
    return INT2FIX(result);
}

VALUE Freg_match();

static VALUE
Fstr_match(x, y)
    struct RString *x, *y;
{
    VALUE reg;
    int start;

    switch (TYPE(y)) {
      case T_REGEXP:
	return Freg_match(y, x);

      case T_STRING:
	reg = re_regcomp(y);
	start = research(reg, x, 0);
	if (start == -1) {
	    return FALSE;
	}
	return INT2FIX(start);

      default:
	Fail("type mismatch");
	break;
    }
}

static VALUE
Fstr_match2(str)
    struct RString *str;
{
    extern VALUE rb_lastline;
    VALUE reg;
    int start;

    if (TYPE(rb_lastline) != T_STRING)
	Fail("$_ is not a string");

    reg = re_regcomp(str);
    start = research(reg, rb_lastline, 0);
    if (start == -1) {
	return Qnil;
    }
    return INT2FIX(start);
}

static int
str_index(str, sub, offset)
    struct RString *str, *sub;
    int offset;
{
    char *s, *e, *p;
    int len;

    if (str->len - offset < sub->len) return -1;
    s = str->ptr+offset;
    p = sub->ptr;
    len = sub->len;
    e = s + str->len - len + 1;
    while (s < e) {
	if (*s == *(sub->ptr) && memcmp(s, p, len) == 0) {
	    return (s-(str->ptr));
	}
	s++;
    }
    return -1;
}

static VALUE
Fstr_index(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    struct RString *sub;
    VALUE initpos;
    int pos;

    if (rb_scan_args(argc, argv, "11", &sub, &initpos) == 2) {
	pos = NUM2INT(initpos);
    }
    else {
	pos = 0;
    }

    switch (TYPE(sub)) {
      case T_REGEXP:
	pos = research(sub, str, pos);
	break;

      case T_STRING:
	pos = str_index(str, sub, pos);
	break;

      default:
	Fail("Type mismatch: %s given", rb_class2name(CLASS_OF(sub)));
    }

    if (pos == -1) return Qnil;
    return INT2FIX(pos);
}

static VALUE
Fstr_rindex(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    struct RString *sub;
    VALUE initpos;
    int pos, len;
    char *s, *sbeg, *t;

    if (rb_scan_args(argc, argv, "11", &sub, &initpos) == 2) {
	pos = NUM2INT(initpos);
	if (pos >= str->len) pos = str->len;
    }
    else {
	pos = str->len;
    }

    Check_Type(sub, T_STRING);
    if (pos > str->len) return Qnil; /* substring longer than string */
    sbeg = str->ptr; s = sbeg + pos - sub->len;
    t = sub->ptr;
    len = sub->len;
    while (sbeg <= s) {
	if (*s == *t && memcmp(s, t, len) == 0) {
	    return INT2FIX(s - sbeg);
	}
	s--;
    }
    return Qnil;
}

static char
str_next(s)
    char *s;
{
    char c = *s;

    /* numerics */
    if ('0' <= c && c < '9') (*s)++;
    else if (c == '9') {
	*s = '0';
	return '1';
    }
    /* small alphabets */
    else if ('a' <= c && c < 'z') (*s)++;
    else if (c == 'z') {
	return *s = 'a';
    }
    /* capital alphabets */
    else if ('A' <= c && c < 'Z') (*s)++;
    else if (c == 'Z') {
	return *s = 'A';
    }
    return 0;
}

static VALUE
Fstr_next(orig)
    struct RString *orig;
{
    struct RString *str, *str2;
    char *sbeg, *s;
    char c = -1;

    str = (struct RString*)str_new(orig->ptr, orig->len);

    sbeg = str->ptr; s = sbeg + str->len - 1;

    while (sbeg <= s) {
	if (isalnum(*s) && (c = str_next(s)) == Qnil) break;
	s--;
    }
    if (s < sbeg && c != -1) {
	str2 = (struct RString*)str_new(0, str->len+1);
	str2->ptr[0] = c;
	memcpy(str2->ptr+1, str->ptr, str->len);
	str = str2;
    }

    return (VALUE)str;
}

VALUE
Fstr_upto(beg, end)
    VALUE beg, end;
{
    VALUE current;

    current = beg;
    for (;;) {
	rb_yield(current);
	if (Fstr_equal(current, end)) break;
	current = Fstr_next(current);
    }

    return Qnil;
}

static VALUE
Fstr_aref_internal(str, indx)
    struct RString *str;
    VALUE indx;
{
    int idx;

    switch (TYPE(indx)) {
      case T_FIXNUM:
	idx = FIX2UINT(indx);

	if (idx < 0) {
	    idx = str->len + idx;
	}
	if (idx < 0 || str->len <= idx) {
	    Fail("index %d out of range [0..%d]", idx, str->len-1);
	}
	return (VALUE)INT2FIX(str->ptr[idx] & 0xff);

      case T_REGEXP:
	if (Fstr_index(str, indx))
	    return re_last_match(0);
	return Qnil;

      case T_STRING:
	if (str_index(str, indx, 0)) return indx;
	return Qnil;

      default:
	/* check if indx is Range */
	if (obj_is_kind_of(indx, C_Range)) {
	    int beg, end;

	    beg = rb_iv_get(indx, "start"); beg = NUM2INT(beg);
	    end = rb_iv_get(indx, "end");   end = NUM2INT(end);
	    if (beg > end) {
		int tmp;

		Warning("start %d is bigger than end %d", beg, end);
		tmp = beg; beg = end; end = tmp;
	    }

	    return str_subseq(str, beg, end);
	}
	Fail("Invalid index for string");
    }
}

static VALUE
Fstr_aref(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    VALUE arg1, arg2;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2) {
	return str_substr(str, NUM2INT(arg1), NUM2INT(arg2));
    }
    return Fstr_aref_internal(str, arg1);
}

static void
str_replace(str, beg, len, val)
    struct RString *str, *val;
    int beg, len;
{
    if (len < val->len) {
	/* expand string */
	REALLOC_N(str->ptr, char, str->len+val->len-len+1);
    }

    if (len != val->len) {
	memmove(str->ptr+beg+val->len, str->ptr+beg+len, str->len-(beg+len));
    }
    memcpy(str->ptr+beg, val->ptr, val->len);
    str->len += val->len - len;
    str->ptr[str->len] = '\0';
}

static void
str_replace2(str, beg, end, val)
    struct RString *str, *val;
    int beg, end;
{
    int len;

    if (beg < 0) {
	beg = str->len + beg;
    }
    if (str->len <= beg) {
	Fail("start %d too big", beg);
    }
    if (end < 0) {
	end = str->len + end;
    }
    if (end < 0 || str->len <= end) {
	Fail("end %d too big", end);
    }
    len = end - beg + 1;	/* length of substring */
    if (len < 0) {
	Fail("end %d too small", end);
    }

    str_replace(str, beg, len, val);
}

static VALUE
str_sub(str, pat, val, once)
    struct RString *str;
    struct RRegexp *pat;
    VALUE val;
    int once;
{
    int beg, end, offset, n;

    for (offset=0, n=0;
	 (beg=research(pat, str, offset)) >= 0;
	 offset=BEG(0)+STRLEN(val)) {
	end = END(0)-1;
	val = re_regsub(val);
	str_replace2(str, beg, END(0)-1, val);
	n++;
	if (once) break;
    }
    if (n == 0) return Qnil;
    return (VALUE)str;
}

static VALUE
Fstr_aset_internal(str, indx, val)
    struct RString *str;
    VALUE indx, val;
{
    int idx, beg, end, offset;

    switch (TYPE(indx)) {
      case T_FIXNUM:
	idx = NUM2INT(indx);
	if (idx < 0) {
	    idx = str->len + idx;
	}
	if (idx < 0 || str->len <= idx) {
	    Fail("index %d out of range [0..%d]", idx, str->len-1);
	}
	str->ptr[idx] = FIX2UINT(val) & 0xff;
	return val;

      case T_REGEXP:
	str_sub(str, indx, val, 0);
	return val;

      case T_STRING:
	for (offset=0;
	     (beg=str_index(str, indx, offset)) >= 0;
	     offset=beg+STRLEN(val)) {
	    end = beg + STRLEN(indx) - 1;
	    str_replace2(str, beg, end, val);
	}
	if (offset == 0) Fail("Not a substring");
	return val;

      default:
	/* check if indx is Range */
	if (obj_is_kind_of(indx, C_Range)) {
	    Check_Type(val, T_STRING);

	    beg = rb_iv_get(indx, "start"); beg = NUM2INT(beg);
	    end =  rb_iv_get(indx, "end");  end = NUM2INT(end);
	    if (beg > end) {
		int tmp;

		Warning("start %d is bigger than end %d", beg, end);
		tmp = beg; beg = end; end = tmp;
	    }

	    str_replace2(str, beg, end, val);
	    return val;
	}
	Fail("Invalid index for string");
    }
}

static VALUE
Fstr_aset(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    VALUE arg1, arg2, arg3;

    str_modify(str);

    if (rb_scan_args(argc, argv, "21", &arg1, &arg2, &arg3) == 3) {
	int beg, len;

	Check_Type(arg3, T_STRING);

	beg = NUM2INT(arg1);
	if (beg < 0) {
	    beg = str->len + beg;
	    if (beg < 0) Fail("start %d too small", beg);
	}
	len = NUM2INT(arg2);
	if (len < 0) Fail("length %d too small", len);
	if (beg + len > str->len) {
	    len = str->len - beg;
	}
	str_replace(str, beg, len, arg3);
	return arg3;
    }
    return Fstr_aset_internal(str, arg1, arg2);
}

static VALUE
Fstr_sub_internal(str, pat, val, once)
    VALUE str, pat, val;
    int once;
{
    Check_Type(val, T_STRING);
    str_modify(str);

    switch (TYPE(pat)) {
      case T_REGEXP:
	return str_sub(str, pat, val, once);

      case T_STRING:
	return str_sub(str, re_regcomp(pat), val, once);

      default:
	/* type failed */
	Check_Type(pat, T_REGEXP);
    }
    return Qnil;		/*  not reached */
}

static VALUE
Fstr_sub(str, pat, val)
    VALUE str, pat, val;
{
    return Fstr_sub_internal(str, pat, val, 1);
}

static VALUE
Fstr_gsub(str, pat, val)
    VALUE str, pat, val;
{
    return Fstr_sub_internal(str, pat, val, 0);
}

static VALUE
Fstr_esub(str, pat)
    VALUE str, pat;
{
    VALUE val;
    int beg, end, offset, n;

    str_modify(str);
    switch (TYPE(pat)) {
      case T_REGEXP:
	break;

      case T_STRING:
	pat = re_regcomp(pat);
	break;

      default:
	/* type failed */
	Check_Type(pat, T_REGEXP);
    }

    offset=0;
    while ((beg=research(pat, str, offset)) >= 0) {
	val = rb_yield(re_nth_match(0));
	val = obj_as_string(val);
	str_replace2(str, beg, END(0)-1, val);
	offset=BEG(0)+STRLEN(val);
    }
    return (VALUE)str;
}

extern VALUE rb_lastline;

static VALUE
Fsub(obj, pat, val)
    VALUE obj, pat, val;
{
    Check_Type(rb_lastline, T_STRING);
    return Fstr_sub_internal(rb_lastline, pat, val, 1);
}

static VALUE
Fgsub(obj, pat, val)
    VALUE obj, pat, val;
{
    Check_Type(rb_lastline, T_STRING);
    return Fstr_sub_internal(rb_lastline, pat, val, 0);
}

static VALUE
Fesub(obj, pat)
    VALUE obj, pat;
{
    Check_Type(rb_lastline, T_STRING);
    return Fstr_esub(rb_lastline, pat);
}

static VALUE
Fstr_reverse(str)
    struct RString *str;
{
    VALUE obj = str_new(0, str->len);
    char *s, *e, *p;

    s = str->ptr; e = s + str->len - 1;
    p = RSTRING(obj)->ptr;

    while (e >= s) {
	*p++ = *e--;
    }

    return obj;
}

static VALUE
Fstr_to_i(str)
    struct RString *str;
{
    return str2inum(str->ptr, 10);
}

static VALUE
Fstr_to_f(str)
    struct RString *str;
{
    double atof();
    double f = atof(str->ptr);

    return float_new(f);
}

static VALUE
Fstr_to_s(str)
    VALUE str;
{
    return str;
}

static VALUE
Fstr_inspect(str)
    struct RString *str;
{
    char buf[160];
    char *p, *pend;
    char *b, *bend;

#define CHECK(n) if (b+n > bend) break;

    p = str->ptr; pend = p + str->len;
    b = buf; bend = b + sizeof buf - (str->len>150?4:2);
    *b++ = '"';
    while (p < pend) {
	char c = *p++;
	if (isprint(c)) {
	    CHECK(1);
	    *b++ = c;
	}
	else if (ismbchar(c)) {
	    CHECK(2);
	    *b++ = c;
	    *b++ = *p++;
	}
	else if (c == '\n') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 'n';
	}
	else if (c == '\r') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 'r';
	}
	else if (c == '\t') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 't';
	}
	else if (c == '\f') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 'f';
	}
	else if (c == '\13') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 'v';
	}
	else if (c == '\1') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 'a';
	}
	else if (c == 033) {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 'e';
	}
	else if (iscntrl(c)) {
	    CHECK(2);
	    *b++ = '^';
	    *b++ = c;
	}
	else {
	    CHECK(1);
	    *b++ = c;
	}
    }
    *b++ = '"';
    if (p < pend) {
	bend = buf + sizeof buf;
	while (b < bend) {
	    *b++ = '.';
	}
    }
    return str_new(buf, b - buf);
}

static VALUE
Fstr_upcase(str)
    struct RString *str;
{
    char *s, *send;

    str_modify(str);
    s = str->ptr; send = s + str->len;
    while (s < send) {
	if (islower(*s)) {
	    *s = toupper(*s);
	}
	*s++;
    }

    return (VALUE)str;
}

static VALUE
Fstr_downcase(str)
    struct RString *str;
{
    char *s, *send;

    str_modify(str);
    s = str->ptr; send = s + str->len;
    while (s < send) {
	if (isupper(*s)) {
	    *s = tolower(*s);
	}
	*s++;
    }

    return (VALUE)str;
}

static VALUE
Fstr_capitalize(str)
    struct RString *str;
{
    char *s, *send;

    str_modify(str);
    s = str->ptr; send = s + str->len;
    if (islower(*s))
	*s = toupper(*s);
    while (++s < send) {
	if (isupper(*s)) {
	    *s = tolower(*s);
	}
    }
    return (VALUE)str;
}

static VALUE
Fstr_swapcase(str)
    struct RString *str;
{
    char *s, *send;

    str_modify(str);
    s = str->ptr; send = s + str->len;
    while (s < send) {
	if (isupper(*s)) {
	    *s = tolower(*s);
	}
	else if (islower(*s)) {
	    *s = toupper(*s);
	}
	*s++;
    }

    return (VALUE)str;
}

static VALUE
Fstr_toupper(str)
    struct RString *str;
{
    return Fstr_upcase(str_new(str->ptr, str->len));
}

static VALUE
Fstr_tolower(str)
    struct RString *str;
{
    return Fstr_downcase(str_new(str->ptr, str->len));
}

struct tr {
    int last, max;
    char *p, *pend;
} trsrc, trrepl;

static
trnext(t)
    struct tr *t;
{
    while (t->p < t->pend) {
	if (t->max) {
	    if (++t->last < t->max)
		return t->last;
	    t->last = t->max = 0;
	}
	else if (t->last && *t->p == '-') {
	    t->p++;
	    t->max = *t->p;
	    if (t->p == t->pend) {
		t->p--;
		return '-';
	    }
	    else if (t->max < t->last) {
		t->last = t->max - 1;
		return '-';
	    }
	    continue;
	}
	return t->last = *t->p++;
    }
    return -1;
}

static VALUE
Fstr_tr(str, src, repl)
    struct RString *str, *src, *repl;
{
    struct tr trsrc, trrepl;
    char trans[256];
    int cflag = 0;
    int i, c, save;
    char *s, *send, *t;

    Check_Type(src, T_STRING);
    trsrc.p = src->ptr; trsrc.pend = trsrc.p + src->len;
    if (src->len > 2 && src->ptr[0] == '^') {
	cflag++;
	trsrc.p++;
    }
    Check_Type(repl, T_STRING);
    trrepl.p = repl->ptr; trrepl.pend = trrepl.p + repl->len;
    trsrc.last = trrepl.last = trsrc.max = trrepl.max = 0;

    for (i=0; i<256; i++) {
	trans[i] = cflag ? 1 : 0;
    }

    while ((c = trnext(&trsrc)) >= 0) {
	trans[c & 0xff] = cflag ? 0 : 1;
    }

    c = 0;
    for (i=0; i<256; i++) {
	if (trans[i] == 0) {
	    trans[i] = i;
	}
	else {
	    c = trnext(&trrepl);
	    if (c == -1) {
		trans[i] = trrepl.last;
	    }
	    else {
		trans[i] = c;
	    }
	}
    }

    str_modify(str);

    t = s = str->ptr; send = s + str->len;
    while (s < send) {
	c = *s++ & 0xff;
	c = trans[c] & 0xff;
	*t++ = c;
    }
    *t = '\0';
    str->len = t - str->ptr;

    return (VALUE)str;
}

static void
tr_setup_table(str, table)
    struct RString *str;
    char table[256];
{
    struct tr tr;
    int i, cflag = 0;
    char c;

    tr.p = str->ptr; tr.pend = tr.p + str->len;
    tr.last = tr.max = 0;
    if (str->len > 2 && str->ptr[0] == '^') {
	cflag++;
	tr.p++;
    }

    for  (i=0; i<256; i++) {
	table[i] = cflag ? 1 : 0;
    }
    while ((c = trnext(&tr)) >= 0) {
	table[c & 0xff] = cflag ? 0 : 1;
    }
}

static VALUE
Fstr_delete(str1, str2)
    struct RString *str1, *str2;
{
    char *s, *send, *t;
    char squeez[256];

    Check_Type(str2, T_STRING);
    tr_setup_table(str2, squeez);

    str_modify(str1);

    s = t = str1->ptr;
    send = s + str1->len;
    while (s < send) {
	if (!squeez[*s & 0xff]) {
	    *t++ = *s;
	}
	s++;
    }
    *t = '\0';
    str1->len = t - str1->ptr;

    return (VALUE)str1;
}

static VALUE
tr_squeeze(str1, str2)
    struct RString *str1, *str2;
{
    char squeez[256];
    char *s, *send, *t;
    char c, save;

    if (str2) {
	tr_setup_table(str2, squeez);
    }
    else {
	int i;

	for (i=0; i<256; i++) {
	    squeez[i] = 1;
	}
    }

    str_modify(str1);

    s = t = str1->ptr;
    send = s + str1->len;
    save = -1;
    while (s < send) {
	c = *s++ & 0xff;
	if (c != save || !squeez[c & 0xff]) {
	    *t++ = save = c;
	}
    }
    *t = '\0';
    str1->len = t - str1->ptr;

    return (VALUE)str1;
}

static VALUE
Fstr_squeeze(argc, argv, str1)
    int argc;
    VALUE *argv;
    VALUE str1;
{
    VALUE str2;

    rb_scan_args(argc, argv, "01", &str2);
    if (str2) {
	Check_Type(str2, T_STRING);
    }
    return tr_squeeze(str1, str2);
}

static VALUE
Fstr_tr_s(str, src, repl)
    VALUE str, src, repl;
{
    Check_Type(src, T_STRING);
    Check_Type(repl, T_STRING);
    Fstr_tr(str, src, repl);
    tr_squeeze(str, repl);
    return str;
}

static VALUE
Fstr_split(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    extern VALUE FS;
    struct RRegexp *spat;
    VALUE limit;
    char char_sep = 0;
    int beg, end, lim, i;
    VALUE result, tmp;

    rb_scan_args(argc, argv, "02", &spat, &limit);
    if (limit) {
	lim = NUM2INT(limit);
	i = 1;
    }

    if (spat == Qnil) {
	if (FS) {
	    spat = (struct RRegexp*)FS;
	    goto fs_set;
	}
	char_sep = ' ';
    }
    else {
	switch (TYPE(spat)) {
	  case T_STRING:
	  fs_set:
	    if (STRLEN(spat) == 1) {
		char_sep = RSTRING(spat)->ptr[0];
	    }
	    else {
		spat = (struct RRegexp*)re_regcomp(spat);
	    }
	    break;
	  case T_REGEXP:
	    break;
	  default:
	    Fail("split(): bad separator");
	}
    }

    result = ary_new();
    beg = 0;
    if (char_sep != 0) {
	char *ptr = str->ptr;
	int len = str->len;
	char *eptr = ptr + len;

	if (char_sep == ' ') {	/* AWK emulation */
	    int skip = 1;

	    for (end = beg = 0; ptr<eptr; ptr++) {
		if (skip) {
		    if (isspace(*ptr)) {
			beg++;
		    }
		    else {
			end = beg+1;
			skip = 0;
		    }
		}
		else {
		    if (isspace(*ptr)) {
			ary_push(result, str_substr(str, beg, end-beg));
			if (limit && lim <= ++i) break;
			skip = 1;
			beg = end + 1;
		    }
		    else {
			end++;
		    }
		}
	    }
	}
	else {
	    for (end = beg = 0; ptr<eptr; ptr++) {
		if (*ptr == char_sep) {
		    ary_push(result, str_substr(str, beg, end-beg));
		    if (limit && lim <= ++i) break;
		    beg = end + 1;
		}
		end++;
	    }
	}
    }
    else {
	int start = beg;
	int last_null = 0;
	int idx;

	while ((end = research(spat, str, start)) >= 0) {
	    if (start == end && BEG(0) == END(0)) {
		if (last_null == 1) {
		    if (ismbchar(str->ptr[beg]))
			ary_push(result, str_substr(str, beg, 2));
		    else
			ary_push(result, str_substr(str, beg, 1));
		    beg = start;
		    if (limit && lim <= ++i) break;
		}
		else {
		    start += ismbchar(str->ptr[start])?2:1;
		    last_null = 1;
		    continue;
		}
	    }
	    else {
		ary_push(result, str_substr(str, beg, end-beg));
		beg = start = END(0);
		if (limit && lim <= ++i) break;
	    }
	    last_null = 0;

	    for (idx=1; idx < 10; idx++) {
		if (BEG(idx) == -1) break;
		if (BEG(idx) == END(idx))
		    tmp = str_new(0, 0);
		else
		    tmp = str_subseq(str, BEG(idx), END(idx)-1);
		ary_push(result, tmp);
		if (limit && lim <= ++i) break;
	    }

	}
    }
    if (str->len > beg) {
	ary_push(result, str_subseq(str, beg, -1));
    }

    return result;
}

static VALUE
Fstr_each(str)
    struct RString* str;
{
    extern VALUE RS;
    int newline;
    int rslen;
    char *p = str->ptr, *pend = p + str->len, *s;

    if (RS == Qnil) {
	rb_yield(str);
	return (VALUE)str;
    }

    rslen = RSTRING(RS)->len;
    if (rslen == 0) {
	newline = '\n';
    }
    else {
	newline = RSTRING(RS)->ptr[rslen-1];
    }

    for (s = p, p += rslen; p < pend; p++) {
	if (rslen == 0 && *p == '\n') {
	    if (*(p+1) != '\n') continue;
	    while (*p == '\n') p++;
	    p--;
	}
	if (*p == newline &&
	    (rslen <= 1 ||
	     memcmp(RSTRING(RS)->ptr, p-rslen+1, rslen) == 0)) {
	    rb_lastline = str_new(s, p - s + 1);
	    rb_yield(rb_lastline);
	    s = p + 1;
	}
    }

    if (s != pend) {
	rb_lastline = str_new(s, p - s);
	rb_yield(rb_lastline);
    }

    return (VALUE)str;
}

static VALUE
Fstr_each_byte(str)
    struct RString* str;
{
    int i;

    for (i=0; str->len; i++) {
	rb_yield(str->ptr[i] & 0xff);
    }
    return (VALUE)str;
}

static VALUE
Fstr_chop(str)
    struct RString *str;
{
    str_modify(str);

    str->len--;
    str->ptr[str->len] = '\0';

    return (VALUE)str;
}

static VALUE
Fstr_strip(str)
    struct RString *str;
{
    char *s, *t, *e;

    s = str->ptr;
    e = t = s + str->len;
    /* remove spaces at head */
    while (s < t && isspace(*s)) s++;

    /* remove trailing spaces */
    t--;
    while (s <= t && isspace(*t)) t--;
    t++;

    if (s > str->ptr || t < e) {
	char *p = str->ptr;
	int len = t-s;

	str->ptr = ALLOC_N(char, len+1);
	memcpy(str->ptr, p, len);
	str->ptr[len] = '\0';
	if (str->orig) {
	    str->orig = Qnil;
	}
	else {
	    free(p);
	}
    }
    return (VALUE)str;
}

static VALUE
Fstr_hex(str)
    struct RString *str;
{
    return str2inum(str->ptr, 16);
}

static VALUE
Fstr_oct(str)
    struct RString *str;
{
    return str2inum(str->ptr, 8);
}

static VALUE
Fstr_crypt(str, salt)
    struct RString *str, *salt;
{
    Check_Type(salt, T_STRING);
    if (salt->len < 2)
	Fail("salt too short(need 2 byte)");
    return str_new2(crypt(str->ptr, salt->ptr));
}

static VALUE
Fstr_intern(str)
    struct RString *str;
{
    if (strlen(str->ptr) != str->len)
	Fail("string contains `\0'");

    return rb_intern(str->ptr)|FIXNUM_FLAG;
}

static VALUE
Fstr_sum(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    VALUE vbits;
    int   bits;
    char *p, *pend;

    rb_scan_args(argc, argv, "01", &vbits);
    if (vbits == Qnil) bits = 16;
    else bits = NUM2INT(vbits);

    p = str->ptr; pend = p + str->len;
    if (bits > 32) {
	VALUE res = INT2FIX(0);
	VALUE mod;

	mod = rb_funcall(INT2FIX(1), rb_intern("<<"), 1, INT2FIX(bits));
	mod = rb_funcall(mod, '-', 1, INT2FIX(1));

	while (p < pend) {
	    res = rb_funcall(res, '+', 1, INT2FIX((UINT)*p));
	    res = rb_funcall(res, '%', 1, mod);
	    p++;
	}
	return res;
    }
    else {
	UINT res = 0;
	UINT mod = (1<<bits)-1;

	while (p < pend) {
	    res += (UINT)*p;
	    res %= mod;
	    p++;
	}
	return int2inum(res);
    }
}

Fstr_ljust(str, w)
    struct RString *str;
    VALUE w;
{
    int width = NUM2INT(w);
    struct RString *res;
    char *p, *pend;

    if (str->len >= width) return (VALUE)str;
    res = (struct RString*)str_new(0, width);
    memcpy(res->ptr, str->ptr, str->len);
    p = res->ptr + str->len; pend = res->ptr + width;
    while (p < pend) {
	*p++ = ' ';
    }
    return (VALUE)res;
}

Fstr_rjust(str, w)
    struct RString *str;
    VALUE w;
{
    int width = NUM2INT(w);
    struct RString *res;
    char *p, *pend;

    if (str->len >= width) return (VALUE)str;
    res = (struct RString*)str_new(0, width);
    p = res->ptr; pend = p + width - str->len;
    while (p < pend) {
	*p++ = ' ';
    }
    memcpy(pend, str->ptr, str->len);
    return (VALUE)res;
}

Fstr_center(str, w)
    struct RString *str;
    VALUE w;
{
    int width = NUM2INT(w);
    struct RString *res;
    char *p, *pend;
    int n;

    if (str->len >= width) return (VALUE)str;
    res = (struct RString*)str_new(0, width);
    n = (width - str->len)/2;
    p = res->ptr; pend = p + n;
    while (p < pend) {
	*p++ = ' ';
    }
    memcpy(pend, str->ptr, str->len);
    p = pend + str->len; pend = res->ptr + width;
    while (p < pend) {
	*p++ = ' ';
    }
    return (VALUE)res;
}

extern VALUE C_Kernel;
extern VALUE M_Comparable;
extern VALUE M_Enumerable;

Init_String()
{
    C_String  = rb_define_class("String", C_Object);
    rb_include_module(C_String, M_Comparable);
    rb_include_module(C_String, M_Enumerable);
    rb_define_single_method(C_String, "new", Sstr_new, 1);
    rb_define_method(C_String, "clone", str_clone, 0);
    rb_define_method(C_String, "<=>", Fstr_cmp, 1);
    rb_define_method(C_String, "==", Fstr_equal, 1);
    rb_define_method(C_String, "hash", Fstr_hash, 0);
    rb_define_method(C_String, "+", Fstr_plus, 1);
    rb_define_method(C_String, "*", Fstr_times, 1);
    rb_define_method(C_String, "..", Fstr_dot2, 1);
    rb_define_method(C_String, "[]", Fstr_aref, -1);
    rb_define_method(C_String, "[]=", Fstr_aset, -1);
    rb_define_method(C_String, "length", Fstr_length, 0);
    rb_define_alias(C_String,  "size", "length");
    rb_define_method(C_String, "=~", Fstr_match, 1);
    rb_define_method(C_String, "~", Fstr_match2, 0);
    rb_define_method(C_String, "next", Fstr_next, 0);
    rb_define_method(C_String, "upto", Fstr_next, 1);
    rb_define_method(C_String, "index", Fstr_index, -1);
    rb_define_method(C_String, "rindex", Fstr_rindex, -1);

    rb_define_method(C_String, "to_i", Fstr_to_i, 0);
    rb_define_method(C_String, "to_f", Fstr_to_f, 0);
    rb_define_method(C_String, "to_s", Fstr_to_s, 0);
    rb_define_method(C_String, "_inspect", Fstr_inspect, 0);

    rb_define_method(C_String, "toupper", Fstr_toupper, 0);
    rb_define_method(C_String, "tolower", Fstr_tolower, 0);

    rb_define_method(C_String, "upcase", Fstr_upcase, 0);
    rb_define_method(C_String, "downcase", Fstr_downcase, 0);
    rb_define_method(C_String, "capitalize", Fstr_capitalize, 0);
    rb_define_method(C_String, "swapcase", Fstr_swapcase, 0);

    rb_define_method(C_String, "hex", Fstr_hex, 0);
    rb_define_method(C_String, "oct", Fstr_oct, 0);
    rb_define_method(C_String, "split", Fstr_split, -1);
    rb_define_method(C_String, "reverse", Fstr_reverse, 0);
    rb_define_method(C_String, "concat", Fstr_concat, 1);
    rb_define_method(C_String, "crypt", Fstr_crypt, 1);
    rb_define_method(C_String, "intern", Fstr_intern, 0);

    rb_define_method(C_String, "ljust", Fstr_ljust, 1);
    rb_define_method(C_String, "rjust", Fstr_rjust, 1);
    rb_define_method(C_String, "center", Fstr_center, 1);

    rb_define_method(C_String, "sub", Fstr_sub, 2);
    rb_define_method(C_String, "gsub", Fstr_gsub, 2);
    rb_define_method(C_String, "esub", Fstr_esub, 1);
    rb_define_method(C_String, "chop", Fstr_chop, 0);
    rb_define_method(C_String, "strip", Fstr_strip, 0);

    rb_define_method(C_String, "tr", Fstr_tr, 2);
    rb_define_method(C_String, "tr_s", Fstr_tr_s, 2);
    rb_define_method(C_String, "delete", Fstr_delete, 1);
    rb_define_method(C_String, "squeeze", Fstr_squeeze, -1);

    rb_define_method(C_String, "each", Fstr_each, 0);
    rb_define_method(C_String, "each_byte", Fstr_each_byte, 0);

    rb_define_method(C_String, "sum", Fstr_sum, -1);

    rb_define_private_method(C_Kernel, "sub", Fsub, 2);
    rb_define_private_method(C_Kernel, "gsub", Fgsub, 2);
    rb_define_private_method(C_Kernel, "esub", Fesub, 1);

    pr_str = rb_intern("to_s");
}
