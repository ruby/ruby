/************************************************

  string.c -

  $Author: matz $
  $Date: 1996/12/25 10:43:01 $
  created at: Mon Aug  9 17:12:58 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"

#define BEG(no) regs->beg[no]
#define END(no) regs->end[no]

#include <stdio.h>
#include <ctype.h>

VALUE cString;

#define STRLEN(s) RSTRING(s)->len

#define STR_FREEZE FL_USER1
#define STR_TAINT  FL_USER2
VALUE str_taint();
VALUE str_tainted();

VALUE
str_new(ptr, len)
    UCHAR *ptr;
    UINT len;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, cString, T_STRING);

    if (rb_safe_level() >= 3) {
	FL_SET(str, STR_TAINT);
    }
    str->len = len;
    str->orig = 0;
    str->ptr = ALLOC_N(char,len+1);
    if (ptr) {
	memcpy(str->ptr, ptr, len);
    }
    str->ptr[len] = '\0';
    return (VALUE)str;
}

VALUE
str_new2(ptr)
    UCHAR *ptr;
{
    return str_new(ptr, strlen(ptr));
}

VALUE
str_new3(str)
    struct RString *str;
{
    NEWOBJ(str2, struct RString);
    OBJSETUP(str2, cString, T_STRING);

    str2->len = str->len;
    str2->ptr = str->ptr;
    str2->orig = str;

    if (rb_safe_level() >= 3) {
	FL_SET(str2, STR_TAINT);
    }

    return (VALUE)str2;
}

VALUE
str_new4(orig)
    struct RString *orig;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, cString, T_STRING);

    str->len = orig->len;
    str->ptr = orig->ptr;
    if (orig->orig) {
	str->orig = orig->orig;
    }
    else {
	orig->orig = str;
	str->orig = 0;
    }
    if (rb_safe_level() >= 3) {
	FL_SET(str, STR_TAINT);
    }

    return (VALUE)str;
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
	return any_to_s(obj);
    return str;
}

static VALUE
str_clone(orig)
    struct RString *orig;
{
    VALUE str;

    if (orig->orig)
	str = str_new3(orig->orig);
    else
	str = str_new(orig->ptr, orig->len);
    CLONESETUP(str, orig);
    return str;
}

VALUE
str_dup(str)
    struct RString *str;
{
    VALUE s = str_new(str->ptr, str->len);
    if (str_tainted(str)) s = str_taint(s);
    return s;
}

static VALUE
str_s_new(class, orig)
    VALUE class;
    struct RString *orig;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, class, T_STRING);

    orig = as_str(orig);
    str->len = orig->len;
    str->ptr = ALLOC_N(char, orig->len+1);
    if (str->ptr) {
	memcpy(str->ptr, orig->ptr, orig->len);
    }
    str->ptr[orig->len] = '\0';
    str->orig = 0;

    if (rb_safe_level() >= 3) {
	FL_SET(str, STR_TAINT);
    }

    return (VALUE)str;
}

static VALUE
str_length(str)
    struct RString *str;
{
    return INT2FIX(str->len);
}

VALUE
str_plus(str1, str2)
    struct RString *str1, *str2;
{
    struct RString *str3;

    str2 = as_str(str2);
    str3 = (struct RString*)str_new(0, str1->len+str2->len);
    memcpy(str3->ptr, str1->ptr, str1->len);
    memcpy(str3->ptr+str1->len, str2->ptr, str2->len);
    str3->ptr[str3->len] = '\0';

    if (str_tainted(str1) || str_tainted(str2))
	return str_taint(str3);
    return (VALUE)str3;
}

VALUE
str_times(str, times)
    struct RString *str;
    VALUE times;
{
    struct RString *str2;
    int i, len;

    len = NUM2INT(times);
    if (len < 0) {
	ArgError("negative argument");
    }

    str2 = (struct RString*)str_new(0, str->len*len);
    for (i=0; i<len; i++) {
	memcpy(str2->ptr+(i*str->len), str->ptr, str->len);
    }
    str2->ptr[str2->len] = '\0';

    if (str_tainted(str))
	return str_taint(str2);

    return (VALUE)str2;
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
    if (str->len <= start || len < 0) {
	return str_new(0,0);
    }
    if (str->len < start + len) {
	len = str->len - start;
    }

    str2 = (struct RString*)str_new(str->ptr+start, len);

    return (VALUE)str2;
}

static VALUE
str_subseq(str, beg, end)
    struct RString *str;
    int beg, end;
{
    int len;

    if ((beg > 0 && end > 0 || beg < 0 && end < 0) && beg > end) {
	IndexError("end smaller than beg [%d..%d]", beg, end);
    }

    if (beg < 0) {
	beg = str->len + beg;
	if (beg < 0) beg = 0;
    }
    if (end < 0) {
	end = str->len + end;
	if (end < 0) end = -1;
	else if (str->len < end) {
	    end = str->len;
	}
    }

    if (beg >= str->len) {
	return str_new(0, 0);
    }

    len = end - beg + 1;
    if (len < 0) {
	len = 0;
    }

    return str_substr(str, beg, len);
}

extern VALUE ignorecase;

void
str_modify(str)
    struct RString *str;
{
    UCHAR *ptr;

    if (rb_safe_level() >= 5) {
	extern VALUE eSecurityError;
	Raise(eSecurityError, "cannot change string status");
    }
    if (FL_TEST(str, STR_FREEZE))
	TypeError("can't modify frozen string");
    if (!str->orig) return;
    ptr = str->ptr;
    str->ptr = ALLOC_N(char, str->len+1);
    if (str->ptr) {
	memcpy(str->ptr, ptr, str->len);
	str->ptr[str->len] = 0;
    }
    str->orig = 0;
}

VALUE
str_freeze(str)
    VALUE str;
{
    FL_SET(str, STR_FREEZE);
    return str;
}

static VALUE
str_frozen_p(str)
    VALUE str;
{
    if (FL_TEST(str, STR_FREEZE))
	return TRUE;
    return FALSE;
}

VALUE
str_dup_freezed(str)
    VALUE str;
{
    str = str_dup(str);
    str_freeze(str);
    return str;
}

VALUE
str_taint(str)
    VALUE str;
{
    if (TYPE(str) == T_STRING) {
	FL_SET(str, STR_TAINT);
    }
    return str;
}

VALUE
str_tainted(str)
    VALUE str;
{
    if (FL_TEST(str, STR_TAINT))
	return TRUE;
    return FALSE;
}

VALUE
str_resize(str, len)
    struct RString *str;
    int len;
{
    str_modify(str);

    if (len >= 0) {
	if (str->len < len || str->len - len > 1024) {
	    REALLOC_N(str->ptr, char, len + 1);
	}
	str->len = len;
	str->ptr[len] = '\0';	/* sentinel */
    }
    return (VALUE)str;
}

VALUE
str_cat(str, ptr, len)
    struct RString *str;
    UCHAR *ptr;
    UINT len;
{
    if (len > 0) {
	str_modify(str);
	REALLOC_N(str->ptr, char, str->len + len + 1);
	if (ptr)
	    memcpy(str->ptr + str->len, ptr, len);
	str->len += len;
	str->ptr[str->len] = '\0'; /* sentinel */
    }
    return (VALUE)str;
}

static VALUE
str_concat(str1, str2)
    struct RString *str1, *str2;
{
    str2 = as_str(str2);
    str_cat(str1, str2->ptr, str2->len);
    return (VALUE)str1;
}

int
str_hash(str)
    struct RString *str;
{
    int len = str->len;
    UCHAR *p = str->ptr;
    int key = 0;

    if (ignorecase) {
	while (len--) {
	    key = key*65599 + toupper(*p);
	    p++;
	}
    }
    else {
	while (len--) {
	    key = key*65599 + *p;
	    p++;
	}
    }
    return key;
}

static VALUE
str_hash_method(str)
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

    if (ignorecase != FALSE) {
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
str_equal(str1, str2)
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
str_cmp_method(str1, str2)
    VALUE str1, str2;
{
    int result;

    str2 = obj_as_string(str2);
    result = str_cmp(str1, str2);
    return INT2FIX(result);
}

VALUE Freg_match();

static VALUE
str_match(x, y)
    struct RString *x, *y;
{
    VALUE reg;
    int start;

    switch (TYPE(y)) {
      case T_REGEXP:
	return reg_match(y, x);

      case T_STRING:
	reg = reg_regcomp(y);
	start = reg_search(reg, x, 0, 0);
	if (start == -1) {
	    return FALSE;
	}
	return INT2FIX(start);

      default:
	TypeError("type mismatch");
	break;
    }
}

static VALUE
str_match2(str)
    struct RString *str;
{
    return reg_match2(reg_regcomp(str));
}

static int
str_index(str, sub, offset)
    struct RString *str, *sub;
    int offset;
{
    UCHAR *s, *e, *p;
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
str_index_method(argc, argv, str)
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
	pos = reg_search(sub, str, pos, (struct re_registers *)-1);
	break;

      case T_STRING:
	pos = str_index(str, sub, pos);
	break;

      default:
	TypeError("Type mismatch: %s given", rb_class2name(CLASS_OF(sub)));
    }

    if (pos == -1) return Qnil;
    return INT2FIX(pos);
}

static VALUE
str_rindex(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    struct RString *sub;
    VALUE initpos;
    int pos, len;
    UCHAR *s, *sbeg, *t;

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

static UCHAR
succ_char(s)
    UCHAR *s;
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
str_succ(orig)
    struct RString *orig;
{
    struct RString *str, *str2;
    UCHAR *sbeg, *s;
    char c = -1;

    str = (struct RString*)str_new(orig->ptr, orig->len);

    sbeg = str->ptr; s = sbeg + str->len - 1;

    while (sbeg <= s) {
	if (isalnum(*s) && (c = succ_char(s)) == 0) break;
	s--;
    }
    if (s < sbeg) {
	if (c == -1 && str->len > 0) {
	    str->ptr[str->len-1] += 1;
	}
	else {
	    str2 = (struct RString*)str_new(0, str->len+1);
	    str2->ptr[0] = c;
	    memcpy(str2->ptr+1, str->ptr, str->len);
	    str = str2;
	}
    }

    if (str_tainted(orig))
	return str_taint(str);

    return (VALUE)str;
}

VALUE
str_upto(beg, end)
    VALUE beg, end;
{
    VALUE current;

    Check_Type(end, T_STRING);
    if (RTEST(rb_funcall(beg, '>', 1, end))) 
	return Qnil;

    current = beg;
    for (;;) {
	rb_yield(current);
	if (str_equal(current, end)) break;
	current = str_succ(current);
	if (RSTRING(current)->len > RSTRING(end)->len)
	    break;
    }

    return Qnil;
}

static VALUE
str_aref(str, indx)
    struct RString *str;
    VALUE indx;
{
    int idx;

    switch (TYPE(indx)) {
      case T_FIXNUM:
	idx = FIX2INT(indx);

	if (idx < 0) {
	    idx = str->len + idx;
	}
	if (idx < 0 || str->len <= idx) {
	    return Qnil;
	}
	return (VALUE)INT2FIX(str->ptr[idx] & 0xff);

      case T_REGEXP:
	if (str_match(str, indx))
	    return reg_last_match(0);
	return Qnil;

      case T_STRING:
	if (str_index(str, indx, 0) != -1) return indx;
	return Qnil;

      default:
	/* check if indx is Range */
	{
	    int beg, end;
	    if (range_beg_end(indx, &beg, &end)) {
		return str_subseq(str, beg, end);
	    }
	}
	IndexError("Invalid index for string");
    }
}

static VALUE
str_aref_method(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    VALUE arg1, arg2;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2) {
	return str_substr(str, NUM2INT(arg1), NUM2INT(arg2));
    }
    return str_aref(str, arg1);
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

/* str_replace2() understands negatice offset */
static void
str_replace2(str, beg, end, val)
    struct RString *str, *val;
    int beg, end;
{
    int len;

    if ((beg > 0 && end > 0 || beg < 0 && end < 0) && beg > end) {
	IndexError("end smaller than beg [%d..%d]", beg, end);
    }

    if (beg < 0) {
	beg = str->len + beg;
	if (beg < 0) {
	    beg = 0;
	}
    }
    if (str->len <= beg) {
	beg = str->len;
    }
    if (end < 0) {
	end = str->len + end;
	if (end < 0) {
	    end = 0;
	}
    }
    if (str->len <= end) {
	end = str->len - 1;
    }
    len = end - beg + 1;	/* length of substring */
    if (len < 0) {
	len = 0;
    }

    str_replace(str, beg, len, val);
}

static VALUE
str_sub_s(str, pat, val, once)
    struct RString *str;
    struct RRegexp *pat;
    VALUE val;
    int once;
{
    VALUE result, repl;
    int beg, offset, n;
    struct re_registers *regs;

    switch (TYPE(pat)) {
      case T_REGEXP:
	break;

      case T_STRING:
	pat = (struct RRegexp*)reg_regcomp(pat);
	break;

      default:
	/* type failed */
	Check_Type(pat, T_REGEXP);
    }

    val = obj_as_string(val);
    result = str_new(0,0);
    offset=0; n=0; 
    while ((beg=reg_search(pat, str, offset, 0)) >= 0) {
	n++;

	regs = RMATCH(backref_get())->regs;
	str_cat(result, str->ptr+offset, beg-offset);

	repl = reg_regsub(val, str, regs);
	str_cat(result, RSTRING(repl)->ptr, RSTRING(repl)->len);
	if (END(0) == offset) {
	    /*
	     * Always consume at least one character of the input string
	     * in order to prevent infinite loops.
	     */
	    if (str->len) str_cat(result, str->ptr+END(0), 1);
	    offset = END(0)+1;
	}
	else {
	    offset = END(0);
	}

	if (once) break;
	if (offset >= STRLEN(str)) break;
    }
    if (n == 0) return Qnil;
    if (str->len > offset) {
	str_cat(result, str->ptr+offset, str->len-offset);
    }

    if (str_tainted(val)) str_taint(result);
    return result;
}

static VALUE
str_sub_f(str, pat, val, once)
    struct RString *str;
    VALUE pat;
    VALUE val;
    int once;
{
    VALUE result;

    str_modify(str);
    result = str_sub_s(str, pat, val, once);

    if (NIL_P(result)) return Qnil;
    str_resize(str, RSTRING(result)->len);
    memcpy(str->ptr, RSTRING(result)->ptr, RSTRING(result)->len);
    if (str_tainted(result)) str_taint(str);

    return (VALUE)str;
}

static VALUE
str_sub_iter_s(str, pat, once)
    struct RString *str;
    VALUE pat;
    int once;
{
    VALUE val, result;
    int beg, offset, n, null;
    struct re_registers *regs;

    if (!iterator_p()) {
	ArgError("Wrong # of arguments(1 for 2)");
    }

    switch (TYPE(pat)) {
      case T_REGEXP:
	break;

      case T_STRING:
	pat = reg_regcomp(pat);
	break;

      default:
	/* type failed */
	Check_Type(pat, T_REGEXP);
    }

    result = str_new(0,0);
    n = 0; offset = 0;
    while ((beg=reg_search(pat, str, offset, 0)) >= 0) {
	n++;

	null = 0;
	regs = RMATCH(backref_get())->regs;
	str_cat(result, str->ptr+offset, beg-offset);

	if (END(0) == offset) {
	    null = 1;
	    offset = END(0)+1;
	}
	else {
	    offset = END(0);
	}

	val = rb_yield(reg_nth_match(0, backref_get()));
	val = obj_as_string(val);
	str_cat(result, RSTRING(val)->ptr, RSTRING(val)->len);
	if (null && str->len) {
	    str_cat(result, str->ptr+offset-1, 1);
	}

	if (once) break;
	if (offset >= STRLEN(str)) break;
    }
    if (n == 0) return Qnil;
    if (str->len > offset) {
	str_cat(result, str->ptr+offset, str->len-offset);
    }

    return result;
}

static VALUE
str_sub_iter_f(str, pat, once)
    struct RString *str;
    VALUE pat;
    int once;
{
    VALUE result;

    str_modify(str);
    result = str_sub_iter_s(str, pat, once);

    if (NIL_P(result)) return Qnil;
    str_resize(str, RSTRING(result)->len);
    memcpy(str->ptr, RSTRING(result)->ptr, RSTRING(result)->len);

    return (VALUE)str;
}

static VALUE
str_aset(str, indx, val)
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
	    IndexError("index %d out of range [0..%d]", idx, str->len-1);
	}
	str->ptr[idx] = FIX2INT(val) & 0xff;
	return val;

      case T_REGEXP:
	str_sub_f(str, indx, val, 0);
	return val;

      case T_STRING:
	for (offset=0;
	     (beg=str_index(str, indx, offset)) >= 0;
	     offset=beg+STRLEN(val)) {
	    end = beg + STRLEN(indx) - 1;
	    str_replace2(str, beg, end, val);
	}
	if (offset == 0) return Qnil;
	return val;

      default:
	/* check if indx is Range */
	{
	    int beg, end;
	    if (range_beg_end(indx, &beg, &end)) {
		str_replace2(str, beg, end, val);
		return val;
	    }
	}
	IndexError("Invalid index for string");
    }
}

static VALUE
str_aset_method(argc, argv, str)
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
	    if (beg < 0) beg = 0;
	}
	len = NUM2INT(arg2);
	if (len < 0) IndexError("negative length %d", len);
	if (beg + len > str->len) {
	    len = str->len - beg;
	}
	str_replace(str, beg, len, arg3);
	return arg3;
    }
    return str_aset(str, arg1, arg2);
}

static VALUE
str_sub_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE pat, val;

    if (rb_scan_args(argc, argv, "11", &pat, &val) == 1) {
	return str_sub_iter_f(str, pat, 1);
    }
    return str_sub_f(str, pat, val, 1);
}

static VALUE
str_sub(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE pat, val, v;

    if (rb_scan_args(argc, argv, "11", &pat, &val) == 1) {
	v = str_sub_iter_s(str, pat, 1);
    }
    else {
	v = str_sub_s(str, pat, val, 1);
    }
    if (NIL_P(v)) return str;
    return v;
}

static VALUE
str_gsub_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE pat, val;

    if (rb_scan_args(argc, argv, "11", &pat, &val) == 1) {
	return str_sub_iter_f(str, pat, 0);
    }
    return str_sub_f(str, pat, val, 0);
}

static VALUE
str_gsub(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE pat, val, v;

    if (rb_scan_args(argc, argv, "11", &pat, &val) == 1) {
	v =  str_sub_iter_s(str, pat, 0);
    }
    else {
	v = str_sub_s(str, pat, val, 0);
    }
    if (NIL_P(v)) return str;
    return v;    
}

static VALUE
uscore_get()
{
    VALUE line;

    line = lastline_get();
    if (TYPE(line) != T_STRING) {
	TypeError("$_ value need to be String");
    }
    return line;
}

static VALUE
f_sub_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE pat, val, line;

    line = uscore_get();
    if (rb_scan_args(argc, argv, "11", &pat, &val) == 1) {
	return str_sub_iter_f(line, pat, 1);
    }
    return str_sub_f(line, pat, val, 1);
}

static VALUE
f_sub(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE pat, val, line, v;

    line = uscore_get();
    if (rb_scan_args(argc, argv, "11", &pat, &val) == 1) {
	v = str_sub_iter_s(line, pat, 1);
    }
    else {
	v = str_sub_s(line, pat, val, 1);
    }
    if (!NIL_P(v)) {
	lastline_set(v);
	return v;
    }
    return line;
}

static VALUE
f_gsub_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE pat, val, line;

    line = uscore_get();
    if (rb_scan_args(argc, argv, "11", &pat, &val) == 1) {
	return str_sub_iter_f(line, pat, 0);
    }
    return str_sub_f(line, pat, val, 0);
}

static VALUE
f_gsub(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE pat, val, line, v;

    line = uscore_get();
    if (rb_scan_args(argc, argv, "11", &pat, &val) == 1) {
	v = str_sub_iter_s(line, pat, 0);
    }
    else {
	v = str_sub_s(line, pat, val, 0);
    }
    if (!NIL_P(v)) {
	lastline_set(v);
	return v;
    }
    return line;
}

static VALUE
str_reverse_bang(str)
    struct RString *str;
{
    UCHAR *s, *e, *p;

    s = str->ptr;
    e = s + str->len - 1;
    p = ALLOCA_N(char, str->len);

    while (e >= s) {
	*p++ = *e--;
    }
    MEMCPY(str->ptr, p, char, str->len);

    return (VALUE)str;
}

static VALUE
str_reverse(str)
    struct RString *str;
{
    VALUE obj = str_new(0, str->len);
    UCHAR *s, *e, *p;

    s = str->ptr; e = s + str->len - 1;
    p = RSTRING(obj)->ptr;

    while (e >= s) {
	*p++ = *e--;
    }

    return obj;
}

static VALUE
str_to_i(str)
    struct RString *str;
{
    return str2inum(str->ptr, 10);
}

#ifndef atof
double atof();
#endif

static VALUE
str_to_f(str)
    struct RString *str;
{
    double f = atof(str->ptr);

    return float_new(f);
}

static VALUE
str_to_s(str)
    VALUE str;
{
    return str;
}

VALUE
str_inspect(str)
    struct RString *str;
{
#define STRMAX 80
    UCHAR buf[STRMAX];
    UCHAR *p, *pend;
    UCHAR *b;

    p = str->ptr; pend = p + str->len;
    b = buf;
    *b++ = '"';

#define CHECK(n) {\
    if (b - buf + n > STRMAX - 4) {\
	strcpy(b, "...");\
	b += 3;\
        break;\
    }\
}

    while (p < pend) {
	UCHAR c = *p++;
	if (ismbchar(c) && p < pend) {
	    CHECK(2);
	    *b++ = c;
	    *b++ = *p++;
	}
	else if (c == '"') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = '"';
	}
	else if (c == '\\') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = '\\';
	}
	else if (isprint(c)) {
	    CHECK(1);
	    *b++ = c;
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
	else if (c == '\007') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 'a';
	}
	else if (c == 033) {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = 'e';
	}
	else {
	    CHECK(4);
	    *b++ = '\\';
	    sprintf(b, "%03o", c);
	    b += 3;
	}
    }
    *b++ = '"';
    return str_new(buf, b - buf);
}

static VALUE
str_upcase_bang(str)
    struct RString *str;
{
    UCHAR *s, *send;

    str_modify(str);
    s = str->ptr; send = s + str->len;
    while (s < send) {
	if (islower(*s)) {
	    *s = toupper(*s);
	}
	s++;
    }

    return (VALUE)str;
}

static VALUE
str_upcase(str)
    struct RString *str;
{
    return str_upcase_bang(str_dup(str));
}

static VALUE
str_downcase_bang(str)
    struct RString *str;
{
    UCHAR *s, *send;

    str_modify(str);
    s = str->ptr; send = s + str->len;
    while (s < send) {
	if (isupper(*s)) {
	    *s = tolower(*s);
	}
	s++;
    }

    return (VALUE)str;
}

static VALUE
str_downcase(str)
    struct RString *str;
{
    return str_downcase_bang(str_dup(str));
}

static VALUE
str_capitalize_bang(str)
    struct RString *str;
{
    UCHAR *s, *send;

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
str_capitalize(str)
    struct RString *str;
{
    return str_capitalize_bang(str_dup(str));
}

static VALUE
str_swapcase_bang(str)
    struct RString *str;
{
    UCHAR *s, *send;

    str_modify(str);
    s = str->ptr; send = s + str->len;
    while (s < send) {
	if (isupper(*s)) {
	    *s = tolower(*s);
	}
	else if (islower(*s)) {
	    *s = toupper(*s);
	}
	s++;
    }

    return (VALUE)str;
}

static VALUE
str_swapcase(str)
    struct RString *str;
{
    return str_swapcase_bang(str_dup(str));
}

typedef UCHAR *USTR;

static struct tr {
    int gen, now, max;
    UCHAR *p, *pend;
} trsrc, trrepl;

static int
trnext(t)
    struct tr *t;
{
    for (;;) {
	if (!t->gen) {
	    if (t->p == t->pend) return -1;
	    t->now = *t->p++;
	    if (t->p < t->pend && *t->p == '-') {
		t->p++;
		if (t->p < t->pend) {
		    if (t->now > *(USTR)t->p) {
			t->p++;
			continue;
		    }
		    t->gen = 1;
		    t->max = *(USTR)t->p++;
		}
	    }
	    return t->now;
	}
	else if (++t->now < t->max) {
	    return t->now;
	}
	else {
	    t->gen = 0;
	    return t->max;
	}
    }
}

static VALUE str_delete_bang();

static VALUE
tr_trans(str, src, repl, sflag)
    struct RString *str, *src, *repl;
    int sflag;
{
    struct tr trsrc, trrepl;
    int cflag = 0;
    UCHAR trans[256];
    int i, c, c0;
    UCHAR *s, *send, *t;

    Check_Type(src, T_STRING);
    trsrc.p = src->ptr; trsrc.pend = trsrc.p + src->len;
    if (src->len > 2 && src->ptr[0] == '^') {
	cflag++;
	trsrc.p++;
    }
    Check_Type(repl, T_STRING);
    if (repl->len == 0) return str_delete_bang(str, src);
    trrepl.p = repl->ptr; trrepl.pend = trrepl.p + repl->len;
    trsrc.gen = trrepl.gen = 0;
    trsrc.now = trrepl.now = 0;
    trsrc.max = trrepl.max = 0;

    if (cflag) {
	for (i=0; i<256; i++) {
	    trans[i] = 1;
	}
	while ((c = trnext(&trsrc)) >= 0) {
	    trans[c & 0xff] = 0;
	}
	for (i=0; i<256; i++) {
	    if (trans[i] == 0) {
		trans[i] = i;
	    }
	    else {
		c = trnext(&trrepl);
		if (c == -1) {
		    trans[i] = trrepl.now;
		}
		else {
		    trans[i] = c;
		}
	    }
	}
    }
    else {
	char r;

	for (i=0; i<256; i++) {
	    trans[i] = i;
	}
	while ((c = trnext(&trsrc)) >= 0) {
	    r = trnext(&trrepl);
	    if (r == -1) r = trrepl.now;
	    trans[c & 0xff] = r;
	}
    }

    str_modify(str);
    t = s = str->ptr; send = s + str->len;
    c0 = -1;
    if (sflag) {
	while (s < send) {
	    c = trans[*s++ & 0xff] & 0xff;
	    if (s[-1] == c || c != c0) {
		c0 = (s[-1] == c)?-1:c;
		*t++ = c;
	    }
	}
    }
    else {
	while (s < send) {
	    c = trans[*s++ & 0xff] & 0xff;
	    *t++ = c;
	}
    }
    *t = '\0';
    if (sflag) str->len = (t - str->ptr);

    return (VALUE)str;
}

static VALUE
str_tr_bang(str, src, repl)
    VALUE str, src, repl;
{
    return tr_trans(str, src, repl, 0);
}

static VALUE
str_tr(str, src, repl)
    VALUE str, src, repl;
{
    return tr_trans(str_dup(str), src, repl, 0);
}

static void
tr_setup_table(str, table)
    struct RString *str;
    UCHAR table[256];
{
    struct tr tr;
    int i, cflag = 0;
    int c;

    tr.p = str->ptr; tr.pend = tr.p + str->len;
    tr.gen = tr.now = tr.max = 0;
    if (str->len > 1 && str->ptr[0] == '^') {
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
str_delete_bang(str1, str2)
    struct RString *str1, *str2;
{
    UCHAR *s, *send, *t;
    UCHAR squeez[256];

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
str_delete(str1, str2)
    struct RString *str1, *str2;
{
    return str_delete_bang(str_dup(str1), str2);
}

static VALUE
tr_squeeze(str1, str2)
    struct RString *str1, *str2;
{
    UCHAR squeez[256];
    UCHAR *s, *send, *t;
    char c, save;

    if (!NIL_P(str2)) {
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
str_squeeze_bang(argc, argv, str1)
    int argc;
    VALUE *argv;
    VALUE str1;
{
    VALUE str2;

    rb_scan_args(argc, argv, "01", &str2);
    if (!NIL_P(str2)) {
	Check_Type(str2, T_STRING);
    }
    return tr_squeeze(str1, str2);
}

static VALUE
str_squeeze(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    return str_squeeze_bang(argc, argv, str_dup(str));
}

static VALUE
str_tr_s_bang(str, src, repl)
    VALUE str, src, repl;
{
    Check_Type(src, T_STRING);
    Check_Type(repl, T_STRING);

    return tr_trans(str, src, repl, 1);
}

static VALUE
str_tr_s(str, src, repl)
    VALUE str, src, repl;
{
    return str_tr_s_bang(str_dup(str), src, repl);
}

static VALUE
str_split_method(argc, argv, str)
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
    if (!NIL_P(limit)) {
	lim = NUM2INT(limit);
	if (lim == 0) limit = Qnil;
	else if (lim == 1) return ary_new3(1, str);
	i = 1;
    }

    if (NIL_P(spat)) {
	if (!NIL_P(FS)) {
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
		spat = (struct RRegexp*)reg_regcomp(spat);
	    }
	    break;
	  case T_REGEXP:
	    break;
	  default:
	    ArgError("split(): bad separator");
	}
    }

    result = ary_new();
    beg = 0;
    if (char_sep != 0) {
	UCHAR *ptr = str->ptr;
	int len = str->len;
	UCHAR *eptr = ptr + len;

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
			skip = 1;
			beg = end + 1;
			if (!NIL_P(limit) && lim <= ++i) break;
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
		    beg = end + 1;
		    if (!NIL_P(limit) && lim <= ++i) break;
		}
		end++;
	    }
	}
    }
    else {
	int start = beg;
	int last_null = 0;
	int idx;
	struct re_registers *regs;

	while ((end = reg_search(spat, str, start, 0)) >= 0) {
	    regs = RMATCH(backref_get())->regs;
	    if (start == end && BEG(0) == END(0)) {
		if (last_null == 1) {
		    if (ismbchar(str->ptr[beg]))
			ary_push(result, str_substr(str, beg, 2));
		    else
			ary_push(result, str_substr(str, beg, 1));
		    beg = start;
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
	    }
	    last_null = 0;

	    for (idx=1; idx < regs->num_regs; idx++) {
		if (BEG(idx) == -1) continue;
		if (BEG(idx) == END(idx))
		    tmp = str_new(0, 0);
		else
		    tmp = str_subseq(str, BEG(idx), END(idx)-1);
		ary_push(result, tmp);
	    }
	    if (!NIL_P(limit) && lim <= ++i) break;
	}
    }
    if (str->len > beg) {
	ary_push(result, str_subseq(str, beg, -1));
    }

    return result;
}

VALUE
str_split(str, sep0)
    struct RString* str;
    char *sep0;
{
    VALUE sep;

    Check_Type(str, T_STRING);
    sep = str_new2(sep0);
    return str_split_method(1, &sep, str);
}

static VALUE
f_split(argc, argv)
    int argc;
    VALUE *argv;
{
    return str_split_method(argc, argv, uscore_get());
}

static VALUE
str_each_line(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString* str;
{
    extern VALUE RS;
    VALUE rs;
    int newline;
    int rslen;
    UCHAR *p = str->ptr, *pend = p + str->len, *s;
    UCHAR *ptr = p;
    int len = str->len;
    VALUE line;

    if (rb_scan_args(argc, argv, "01", &rs) == 1) {
	if (!NIL_P(rs)) Check_Type(rs, T_STRING);
    }
    else {
	rs = RS;
    }

    if (NIL_P(rs)) {
	rb_yield(str);
	return Qnil;
    }

    rslen = RSTRING(rs)->len;
    if (rslen == 0) {
	newline = '\n';
    }
    else {
	newline = RSTRING(rs)->ptr[rslen-1];
    }

    for (s = p, p += rslen; p < pend; p++) {
	if (rslen == 0 && *p == '\n') {
	    if (*(p+1) != '\n') continue;
	    while (*p == '\n') p++;
	    p--;
	}
	if (*p == newline &&
	    (rslen <= 1 ||
	     memcmp(RSTRING(rs)->ptr, p-rslen+1, rslen) == 0)) {
	    line = str_new(s, p - s + 1);
	    lastline_set(line);
	    rb_yield(line);
	    if (str->ptr != ptr || str->len != len)
		Fail("string modified");
	    s = p + 1;
	}
    }

    if (s != pend) {
	line = str_new(s, p - s);
	lastline_set(line);
	rb_yield(line);
    }

    return Qnil;
}

static VALUE
str_each_byte(str)
    struct RString* str;
{
    int i;

    for (i=0; i<str->len; i++) {
	rb_yield(INT2FIX(str->ptr[i] & 0xff));
    }
    return Qnil;
}

static VALUE
str_chop_bang(str)
    struct RString *str;
{
    str_modify(str);

    if (str->len > 0) {
	str->len--;
	if (str->ptr[str->len] == '\n') {
	    if (str->len > 0 && str->ptr[str->len-1] == '\r') {
		str->len--;
	    }
	}
	str->ptr[str->len] = '\0';
    }

    return (VALUE)str;
}

static VALUE
str_chop(str)
    struct RString *str;
{
    return str_chop_bang(str_dup(str));
}

static VALUE
f_chop_bang(str)
    struct RString *str;
{
    return str_chop_bang(uscore_get());
}

static VALUE
f_chop()
{
    return str_chop_bang(str_dup(uscore_get()));
}

static VALUE
str_strip_bang(str)
    struct RString *str;
{
    UCHAR *s, *t, *e;

    str_modify(str);

    s = str->ptr;
    e = t = s + str->len;
    /* remove spaces at head */
    while (s < t && isspace(*s)) s++;

    /* remove trailing spaces */
    t--;
    while (s <= t && isspace(*t)) t--;
    t++;

    str->len = t-s;
    if (s > str->ptr) { 
	UCHAR *p = str->ptr;

	str->ptr = ALLOC_N(char, str->len+1);
	memcpy(str->ptr, s, str->len);
	str->ptr[str->len] = '\0';
	free(p);
    }
    else if (t < e) {
	str->ptr[str->len] = '\0';
    }

    return (VALUE)str;
}

static VALUE
scan_once(str, pat, start)
    struct RString *str;
    struct RRegexp *pat;
    int *start;
{
    VALUE result;
    struct re_registers *regs;
    int idx;

    if (reg_search(pat, str, *start, 0) >= 0) {
	regs = RMATCH(backref_get())->regs;
	result = ary_new2(regs->num_regs);
	for (idx=1; idx < regs->num_regs; idx++) {
	    if (BEG(idx) == -1) {
		ary_push(result, Qnil);
	    }
	    else if (BEG(idx) == END(idx)) {
		ary_push(result, str_new(0, 0));
	    }
	    else {
		ary_push(result, str_subseq(str, BEG(idx), END(idx)-1));
	    }
	}
	if (END(0) == *start) {
	    *start = END(0)+1;
	}
	else {
	    *start = END(0);
	}

	return result;
    }
    return Qnil;
}

static VALUE
str_scan(str, pat)
    struct RString *str;
    struct RRegexp *pat;
{
    VALUE result;
    int start = 0;

    switch (TYPE(pat)) {
      case T_STRING:
	pat = (struct RRegexp*)reg_regcomp(pat);
	break;
      case T_REGEXP:
	break;
      default:
	Check_Type(pat, T_REGEXP);
    }

    if (!iterator_p()) {
	return scan_once(str, pat, &start);
    }

    while (!NIL_P(result = scan_once(str, pat, &start))) {
	rb_yield(result);
    }
    return Qnil;
}

static VALUE
str_strip(str)
    struct RString *str;
{
    return str_strip_bang(str_dup(str));
}

static VALUE
str_hex(str)
    struct RString *str;
{
    return str2inum(str->ptr, 16);
}

static VALUE
str_oct(str)
    struct RString *str;
{
    return str2inum(str->ptr, 8);
}

static VALUE
str_crypt(str, salt)
    struct RString *str, *salt;
{
    salt = as_str(salt);
    if (salt->len < 2)
	ArgError("salt too short(need >2 bytes)");
    return str_new2(crypt(str->ptr, salt->ptr));
}

static VALUE
str_intern(str)
    struct RString *str;
{
    ID id;

    if (strlen(str->ptr) != str->len)
	ArgError("string contains `\0'");
    id = rb_intern(str->ptr);
    return INT2FIX(id);
}

static VALUE
str_sum(argc, argv, str)
    int argc;
    VALUE *argv;
    struct RString *str;
{
    VALUE vbits;
    int   bits;
    UCHAR *p, *pend;

    rb_scan_args(argc, argv, "01", &vbits);
    if (NIL_P(vbits)) bits = 16;
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

static VALUE
str_ljust(str, w)
    struct RString *str;
    VALUE w;
{
    int width = NUM2INT(w);
    struct RString *res;
    UCHAR *p, *pend;

    if (str->len >= width) return (VALUE)str;
    res = (struct RString*)str_new(0, width);
    memcpy(res->ptr, str->ptr, str->len);
    p = res->ptr + str->len; pend = res->ptr + width;
    while (p < pend) {
	*p++ = ' ';
    }
    return (VALUE)res;
}

static VALUE
str_rjust(str, w)
    struct RString *str;
    VALUE w;
{
    int width = NUM2INT(w);
    struct RString *res;
    UCHAR *p, *pend;

    if (str->len >= width) return (VALUE)str;
    res = (struct RString*)str_new(0, width);
    p = res->ptr; pend = p + width - str->len;
    while (p < pend) {
	*p++ = ' ';
    }
    memcpy(pend, str->ptr, str->len);
    return (VALUE)res;
}

static VALUE
str_center(str, w)
    struct RString *str;
    VALUE w;
{
    int width = NUM2INT(w);
    struct RString *res;
    UCHAR *p, *pend;
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

extern VALUE mKernel;
extern VALUE mComparable;
extern VALUE mEnumerable;

void
Init_String()
{
    cString  = rb_define_class("String", cObject);
    rb_include_module(cString, mComparable);
    rb_include_module(cString, mEnumerable);
    rb_define_singleton_method(cString, "new", str_s_new, 1);
    rb_define_method(cString, "clone", str_clone, 0);
    rb_define_method(cString, "dup", str_dup, 0);
    rb_define_method(cString, "<=>", str_cmp_method, 1);
    rb_define_method(cString, "==", str_equal, 1);
    rb_define_method(cString, "===", str_equal, 1);
    rb_define_method(cString, "eql?", str_equal, 1);
    rb_define_method(cString, "hash", str_hash_method, 0);
    rb_define_method(cString, "+", str_plus, 1);
    rb_define_method(cString, "*", str_times, 1);
    rb_define_method(cString, "[]", str_aref_method, -1);
    rb_define_method(cString, "[]=", str_aset_method, -1);
    rb_define_method(cString, "length", str_length, 0);
    rb_define_alias(cString,  "size", "length");
    rb_define_method(cString, "=~", str_match, 1);
    rb_define_method(cString, "~", str_match2, 0);
    rb_define_method(cString, "succ", str_succ, 0);
    rb_define_method(cString, "upto", str_upto, 1);
    rb_define_method(cString, "index", str_index_method, -1);
    rb_define_method(cString, "rindex", str_rindex, -1);

    rb_define_method(cString, "freeze", str_freeze, 0);
    rb_define_method(cString, "frozen?", str_frozen_p, 0);

    rb_define_method(cString, "taint", str_taint, 0);
    rb_define_method(cString, "tainted?", str_tainted, 0);

    rb_define_method(cString, "to_i", str_to_i, 0);
    rb_define_method(cString, "to_f", str_to_f, 0);
    rb_define_method(cString, "to_s", str_to_s, 0);
    rb_define_method(cString, "inspect", str_inspect, 0);

    rb_define_method(cString, "upcase", str_upcase, 0);
    rb_define_method(cString, "downcase", str_downcase, 0);
    rb_define_method(cString, "capitalize", str_capitalize, 0);
    rb_define_method(cString, "swapcase", str_swapcase, 0);

    rb_define_method(cString, "upcase!", str_upcase_bang, 0);
    rb_define_method(cString, "downcase!", str_downcase_bang, 0);
    rb_define_method(cString, "capitalize!", str_capitalize_bang, 0);
    rb_define_method(cString, "swapcase!", str_swapcase_bang, 0);

    rb_define_method(cString, "hex", str_hex, 0);
    rb_define_method(cString, "oct", str_oct, 0);
    rb_define_method(cString, "split", str_split_method, -1);
    rb_define_method(cString, "reverse", str_reverse, 0);
    rb_define_method(cString, "reverse!", str_reverse_bang, 0);
    rb_define_method(cString, "concat", str_concat, 1);
    rb_define_method(cString, "<<", str_concat, 1);
    rb_define_method(cString, "crypt", str_crypt, 1);
    rb_define_method(cString, "intern", str_intern, 0);

    rb_define_method(cString, "scan", str_scan, 1);

    rb_define_method(cString, "ljust", str_ljust, 1);
    rb_define_method(cString, "rjust", str_rjust, 1);
    rb_define_method(cString, "center", str_center, 1);

    rb_define_method(cString, "sub", str_sub, -1);
    rb_define_method(cString, "gsub", str_gsub, -1);
    rb_define_method(cString, "chop", str_chop, 0);
    rb_define_method(cString, "strip", str_strip, 0);

    rb_define_method(cString, "sub!", str_sub_bang, -1);
    rb_define_method(cString, "gsub!", str_gsub_bang, -1);
    rb_define_method(cString, "strip!", str_strip_bang, 0);
    rb_define_method(cString, "chop!", str_chop_bang, 0);

    rb_define_method(cString, "tr", str_tr, 2);
    rb_define_method(cString, "tr_s", str_tr_s, 2);
    rb_define_method(cString, "delete", str_delete, 1);
    rb_define_method(cString, "squeeze", str_squeeze, -1);

    rb_define_method(cString, "tr!", str_tr_bang, 2);
    rb_define_method(cString, "tr_s!", str_tr_s_bang, 2);
    rb_define_method(cString, "delete!", str_delete_bang, 1);
    rb_define_method(cString, "squeeze!", str_squeeze_bang, -1);

    rb_define_method(cString, "each_line", str_each_line, -1);
    rb_define_method(cString, "each", str_each_line, -1);
    rb_define_method(cString, "each_byte", str_each_byte, 0);

    rb_define_method(cString, "sum", str_sum, -1);

    rb_define_global_function("sub", f_sub, -1);
    rb_define_global_function("gsub", f_gsub, -1);

    rb_define_global_function("sub!", f_sub_bang, -1);
    rb_define_global_function("gsub!", f_gsub_bang, -1);

    rb_define_global_function("chop", f_chop, 0);
    rb_define_global_function("chop!", f_chop_bang, 0);

    rb_define_global_function("split", f_split, -1);

    pr_str = rb_intern("to_s");
}
