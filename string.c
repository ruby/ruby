/************************************************

  string.c -

  $Author$
  $Date$
  created at: Mon Aug  9 17:12:58 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"

#define BEG(no) regs->beg[no]
#define END(no) regs->end[no]

#include <ctype.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

VALUE cString;

#define STRLEN(s) RSTRING(s)->len

#define STR_FREEZE FL_USER1
#define STR_TAINT  FL_USER2
#define STR_NO_ORIG FL_USER3

extern VALUE RS;

VALUE
str_new(ptr, len)
    char *ptr;
    unsigned len;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, cString, T_STRING);

    if (rb_safe_level() >= 3) {
	FL_SET(str, STR_TAINT);
    }
    str->ptr = 0;
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
    char *ptr;
{
    return str_new(ptr, strlen(ptr));
}

VALUE
str_new3(str)
    VALUE str;
{
    NEWOBJ(str2, struct RString);
    OBJSETUP(str2, cString, T_STRING);

    str2->len = RSTRING(str)->len;
    str2->ptr = RSTRING(str)->ptr;
    str2->orig = str;

    if (rb_safe_level() >= 3) {
	FL_SET(str2, STR_TAINT);
    }

    return (VALUE)str2;
}

VALUE
str_new4(orig)
    VALUE orig;
{
    if (FL_TEST(orig, STR_FREEZE)) {
	return orig;
    }
    else if (RSTRING(orig)->orig && !FL_TEST(orig, STR_NO_ORIG)) {
	return str_freeze(RSTRING(orig)->orig);
    }
    else {
	NEWOBJ(str, struct RString);
	OBJSETUP(str, cString, T_STRING);

	str->len = RSTRING(orig)->len;
	str->ptr = RSTRING(orig)->ptr;
	RSTRING(orig)->orig = (VALUE)str;
	str->orig = 0;
	if (rb_safe_level() >= 3) {
	    FL_SET(str, STR_TAINT);
	}
	return (VALUE)str;
    }
}

VALUE
str_to_str(str)
    VALUE str;
{
    return rb_convert_type(str, T_STRING, "String", "to_str");
}

static void
str_assign(str, str2)
    VALUE str, str2;
{
    if (str == str2) return;
    if (NIL_P(str2)) {
	RSTRING(str)->ptr = 0;
	RSTRING(str)->len = 0;
	RSTRING(str)->orig = 0;
	return;
    }
    if ((!RSTRING(str)->orig||FL_TEST(str, STR_NO_ORIG))&&RSTRING(str)->ptr)
	free(RSTRING(str)->ptr);
    RSTRING(str)->ptr = RSTRING(str2)->ptr;
    RSTRING(str)->len = RSTRING(str2)->len;
    RSTRING(str)->orig = RSTRING(str2)->orig;
    RSTRING(str2)->ptr = 0;	/* abandon str2 */
    RSTRING(str2)->len = 0;
    if (str_tainted(str2)) str_taint(str);
}

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
    VALUE orig;
{
    VALUE str;

    if (RSTRING(orig)->orig && !FL_TEST(orig, STR_NO_ORIG))
	str = str_new3(RSTRING(orig)->orig);
    else
	str = str_new(RSTRING(orig)->ptr, RSTRING(orig)->len);
    if (RSTRING(orig)->orig && FL_TEST(orig, STR_NO_ORIG))
	RSTRING(str)->orig = RSTRING(orig)->orig;
    CLONESETUP(str, orig);
    return str;
}

VALUE
str_dup(str)
    VALUE str;
{
    VALUE s;

    str = str_to_str(str);
    s = str_new(RSTRING(str)->ptr, RSTRING(str)->len);
    if (str_tainted(str)) s = str_taint(s);
    if (RSTRING(str)->orig && FL_TEST(str, STR_NO_ORIG))
	RSTRING(s)->orig = RSTRING(str)->orig;
    return s;
}

static VALUE
str_s_new(klass, orig)
    VALUE klass;
    VALUE orig;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, klass, T_STRING);

    orig = obj_as_string(orig);
    str->len = RSTRING(orig)->len;
    str->ptr = ALLOC_N(char, RSTRING(orig)->len+1);
    if (str->ptr) {
	memcpy(str->ptr, RSTRING(orig)->ptr, RSTRING(orig)->len);
    }
    str->ptr[RSTRING(orig)->len] = '\0';
    str->orig = 0;

    if (rb_safe_level() >= 3) {
	FL_SET(str, STR_TAINT);
    }
    obj_call_init((VALUE)str);

    return (VALUE)str;
}

static VALUE
str_length(str)
    VALUE str;
{
    return INT2FIX(RSTRING(str)->len);
}

static VALUE
str_empty(str)
    VALUE str;
{
    if (RSTRING(str)->len == 0)
	return TRUE;
    return FALSE;
}

VALUE
str_plus(str1, str2)
    VALUE str1, str2;
{
    VALUE str3;

    str2 = str_to_str(str2);
    str3 = str_new(0, RSTRING(str1)->len+RSTRING(str2)->len);
    memcpy(RSTRING(str3)->ptr, RSTRING(str1)->ptr, RSTRING(str1)->len);
    memcpy(RSTRING(str3)->ptr+RSTRING(str1)->len, RSTRING(str2)->ptr, RSTRING(str2)->len);
    RSTRING(str3)->ptr[RSTRING(str3)->len] = '\0';

    if (str_tainted(str1) || str_tainted(str2))
	return str_taint(str3);
    return str3;
}

VALUE
str_times(str, times)
    VALUE str;
    VALUE times;
{
    VALUE str2;
    int i, len;

    len = NUM2INT(times);
    if (len < 0) {
	ArgError("negative argument");
    }

    str2 = str_new(0, RSTRING(str)->len*len);
    for (i=0; i<len; i++) {
	memcpy(RSTRING(str2)->ptr+(i*RSTRING(str)->len), RSTRING(str)->ptr, RSTRING(str)->len);
    }
    RSTRING(str2)->ptr[RSTRING(str2)->len] = '\0';

    if (str_tainted(str)) {
	return str_taint(str2);
    }

    return str2;
}

VALUE
str_format(str, arg)
    VALUE str, arg;
{
    VALUE *argv;

    if (TYPE(arg) == T_ARRAY) {
	argv = ALLOCA_N(VALUE, RARRAY(arg)->len + 1);
	argv[0] = str;
	MEMCPY(argv+1, RARRAY(arg)->ptr, VALUE, RARRAY(arg)->len);
	return f_sprintf(RARRAY(arg)->len+1, argv);
    }
    
    argv = ALLOCA_N(VALUE, 2);
    argv[0] = str;
    argv[1] = arg;
    return f_sprintf(2, argv);
}

VALUE
str_substr(str, start, len)
    VALUE str;
    int start, len;
{
    VALUE str2;

    if (start < 0) {
	start = RSTRING(str)->len + start;
    }
    if (RSTRING(str)->len <= start || len < 0) {
	return str_new(0,0);
    }
    if (RSTRING(str)->len < start + len) {
	len = RSTRING(str)->len - start;
    }

    str2 = str_new(RSTRING(str)->ptr+start, len);
    if (str_tainted(str)) str_taint(str2);

    return str2;
}

static VALUE
str_subseq(str, beg, end)
    VALUE str;
    int beg, end;
{
    int len;

    if ((beg > 0 && end > 0 || beg < 0 && end < 0) && beg > end) {
	IndexError("end smaller than beg [%d..%d]", beg, end);
    }

    if (beg < 0) {
	beg = RSTRING(str)->len + beg;
	if (beg < 0) beg = 0;
    }
    if (end < 0) {
	end = RSTRING(str)->len + end;
	if (end < 0) end = -1;
	else if (RSTRING(str)->len < end) {
	    end = RSTRING(str)->len;
	}
    }

    if (beg >= RSTRING(str)->len) {
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
    VALUE str;
{
    char *ptr;

    if (rb_safe_level() >= 5) {
	Raise(eSecurityError, "cannot change string status");
    }
    if (FL_TEST(str, STR_FREEZE))
	TypeError("can't modify frozen string");
    if (!RSTRING(str)->orig || FL_TEST(str, STR_NO_ORIG)) return;
    ptr = RSTRING(str)->ptr;
    RSTRING(str)->ptr = ALLOC_N(char, RSTRING(str)->len+1);
    if (RSTRING(str)->ptr) {
	memcpy(RSTRING(str)->ptr, ptr, RSTRING(str)->len);
	RSTRING(str)->ptr[RSTRING(str)->len] = 0;
    }
    RSTRING(str)->orig = 0;
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
str_dup_frozen(str)
    VALUE str;
{
    if (RSTRING(str)->orig && !FL_TEST(str, STR_NO_ORIG)) {
	return str_freeze(RSTRING(str)->orig);
    }
    if (FL_TEST(str, STR_FREEZE))
	return str;
    return str_freeze(str_dup(str));
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
    VALUE str;
    int len;
{
    str_modify(str);

    if (len >= 0) {
	if (RSTRING(str)->len < len || RSTRING(str)->len - len > 1024) {
	    REALLOC_N(RSTRING(str)->ptr, char, len + 1);
	}
	RSTRING(str)->len = len;
	RSTRING(str)->ptr[len] = '\0';	/* sentinel */
    }
    return str;
}

VALUE
str_cat(str, ptr, len)
    VALUE str;
    char *ptr;
    unsigned len;
{
    if (len > 0) {
	str_modify(str);
	REALLOC_N(RSTRING(str)->ptr, char, RSTRING(str)->len + len + 1);
	if (ptr)
	    memcpy(RSTRING(str)->ptr + RSTRING(str)->len, ptr, len);
	RSTRING(str)->len += len;
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0'; /* sentinel */
    }
    return str;
}

VALUE
str_concat(str1, str2)
    VALUE str1, str2;
{
    str2 = str_to_str(str2);
    str_cat(str1, RSTRING(str2)->ptr, RSTRING(str2)->len);
    return str1;
}

int
str_hash(str)
    VALUE str;
{
    register int len = RSTRING(str)->len;
    register char *p = RSTRING(str)->ptr;
    register int key = 0;

    if (RTEST(ignorecase)) {
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
    VALUE str1, str2;
{
    unsigned int len;
    int retval;

    if (RTEST(ignorecase)) {
	return str_cicmp(str1, str2);
    }

    len = min(RSTRING(str1)->len, RSTRING(str2)->len);
    retval = memcmp(RSTRING(str1)->ptr, RSTRING(str2)->ptr, len);
    if (retval == 0) {
	if (RSTRING(str1)->len == RSTRING(str2)->len) return 0;
	if (RSTRING(str1)->len > RSTRING(str2)->len) return 1;
	return -1;
    }
    if (retval == 0) return 0;
    if (retval > 0) return 1;
    return -1;
}

static VALUE
str_equal(str1, str2)
    VALUE str1, str2;
{
    if (TYPE(str2) != T_STRING)
	return FALSE;

    if (RSTRING(str1)->len == RSTRING(str2)->len
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

    str2 = str_to_str(str2);
    result = str_cmp(str1, str2);
    return INT2FIX(result);
}

static VALUE
str_match(x, y)
    VALUE x, y;
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
	return rb_funcall(y, rb_intern("=~"), 1, x);
    }
}

static VALUE
str_match2(str)
    VALUE str;
{
    return reg_match2(reg_regcomp(str));
}

static int
str_index(str, sub, offset)
    VALUE str, sub;
    int offset;
{
    char *s, *e, *p;
    int len;

    if (RSTRING(str)->len - offset < RSTRING(sub)->len) return -1;
    s = RSTRING(str)->ptr+offset;
    p = RSTRING(sub)->ptr;
    len = RSTRING(sub)->len;
    e = s + RSTRING(str)->len - len + 1;
    while (s < e) {
	if (*s == *(RSTRING(sub)->ptr) && memcmp(s, p, len) == 0) {
	    return (s-(RSTRING(str)->ptr));
	}
	s++;
    }
    return -1;
}

static VALUE
str_index_method(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE sub;
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
	pos = reg_search(sub, str, pos, 0);
	break;

      case T_STRING:
	pos = str_index(str, sub, pos);
	break;

      case T_FIXNUM:
      {
	  int c = FIX2INT(sub);
	  int len = RSTRING(str)->len;
	  char *p = RSTRING(str)->ptr;

	  for (;pos<len;pos++) {
	      if (p[pos] == c) return INT2FIX(pos);
	  }
	  return Qnil;
      }

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
    VALUE str;
{
    VALUE sub;
    VALUE initpos;
    int pos, len;
    char *s, *sbeg, *t;

    if (rb_scan_args(argc, argv, "11", &sub, &initpos) == 2) {
	pos = NUM2INT(initpos);
	if (pos >= RSTRING(str)->len) pos = RSTRING(str)->len;
    }
    else {
	pos = RSTRING(str)->len;
    }

    switch (TYPE(sub)) {
      case T_REGEXP:
	pos = reg_search(sub, str, pos, 1);
	if (pos >= 0) return INT2FIX(pos); 
	break;

      case T_STRING:
	/* substring longer than string */
	if (pos > RSTRING(str)->len) return Qnil;
	sbeg = RSTRING(str)->ptr; s = sbeg + pos - RSTRING(sub)->len;
	t = RSTRING(sub)->ptr;
	len = RSTRING(sub)->len;
	while (sbeg <= s) {
	    if (*s == *t && memcmp(s, t, len) == 0) {
		return INT2FIX(s - sbeg);
	    }
	    s--;
	}
	break;

      case T_FIXNUM:
      {
	  int c = FIX2INT(sub);
	  char *p = RSTRING(str)->ptr;

	  for (;pos>=0;pos--) {
	      if (p[pos] == c) return INT2FIX(pos);
	  }
	  return Qnil;
      }

      default:
	TypeError("Type mismatch: %s given", rb_class2name(CLASS_OF(sub)));
    }
    return Qnil;
}

static char
succ_char(s)
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
str_succ(orig)
    VALUE orig;
{
    VALUE str, str2;
    char *sbeg, *s;
    char c = -1;

    str = str_new(RSTRING(orig)->ptr, RSTRING(orig)->len);

    sbeg = RSTRING(str)->ptr; s = sbeg + RSTRING(str)->len - 1;

    while (sbeg <= s) {
	if (ISALNUM(*s) && (c = succ_char(s)) == 0) break;
	s--;
    }
    if (s < sbeg) {
	if (c == -1 && RSTRING(str)->len > 0) {
	    RSTRING(str)->ptr[RSTRING(str)->len-1] += 1;
	}
	else {
	    str2 = str_new(0, RSTRING(str)->len+1);
	    RSTRING(str2)->ptr[0] = c;
	    memcpy(RSTRING(str2)->ptr+1, RSTRING(str)->ptr, RSTRING(str)->len);
	    str = str2;
	}
    }

    if (str_tainted(orig)) {
	return str_taint(str);
    }

    return str;
}

static VALUE
str_succ_bang(str)
    VALUE str;
{
    str_modify(str);
    str_assign(str, str_succ(str));

    return str;
}

VALUE
str_upto(beg, end)
    VALUE beg, end;
{
    VALUE current;

    end = str_to_str(end);
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
    VALUE str;
    VALUE indx;
{
    int idx;

    switch (TYPE(indx)) {
      case T_FIXNUM:
	idx = FIX2INT(indx);

	if (idx < 0) {
	    idx = RSTRING(str)->len + idx;
	}
	if (idx < 0 || RSTRING(str)->len <= idx) {
	    return Qnil;
	}
	return INT2FIX(RSTRING(str)->ptr[idx] & 0xff);

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
    VALUE str;
{
    VALUE arg1, arg2;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2) {
	return str_substr(str, NUM2INT(arg1), NUM2INT(arg2));
    }
    return str_aref(str, arg1);
}

static void
str_replace(str, beg, len, val)
    VALUE str, val;
    int beg, len;
{
    if (len < RSTRING(val)->len) {
	/* expand string */
	REALLOC_N(RSTRING(str)->ptr, char, RSTRING(str)->len+RSTRING(val)->len-len+1);
    }

    if (len != RSTRING(val)->len) {
	memmove(RSTRING(str)->ptr+beg+RSTRING(val)->len,
		RSTRING(str)->ptr+beg+len,
		RSTRING(str)->len-(beg+len));
    }
    if (RSTRING(str)->len < beg && len < 0) {
	MEMZERO(RSTRING(str)->ptr+RSTRING(str)->len, char, -len);
    }
    memcpy(RSTRING(str)->ptr+beg, RSTRING(val)->ptr, RSTRING(val)->len);
    RSTRING(str)->len += RSTRING(val)->len - len;
    RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
}

/* str_replace2() understands negatice offset */
static void
str_replace2(str, beg, end, val)
    VALUE str, val;
    int beg, end;
{
    int len;

    if ((beg > 0 && end > 0 || beg < 0 && end < 0) && beg > end) {
	IndexError("end smaller than beg [%d..%d]", beg, end);
    }

    if (beg < 0) {
	beg = RSTRING(str)->len + beg;
	if (beg < 0) {
	    beg = 0;
	}
    }
    if (RSTRING(str)->len <= beg) {
	beg = RSTRING(str)->len;
    }
    if (end < 0) {
	end = RSTRING(str)->len + end;
	if (end < 0) {
	    end = 0;
	}
    }
    if (RSTRING(str)->len <= end) {
	end = RSTRING(str)->len - 1;
    }
    len = end - beg + 1;	/* length of substring */
    if (len < 0) {
	len = 0;
    }

    str_replace(str, beg, len, val);
}

static VALUE
str_sub_s(str, pat, val, once)
    VALUE str, pat, val;
    int once;
{
    VALUE result, repl;
    int beg, offset, n;
    struct re_registers *regs;

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

    val = obj_as_string(val);
    result = str_new(0,0);
    offset=0; n=0; 
    while ((beg=reg_search(pat, str, offset, 0)) >= 0) {
	n++;

	regs = RMATCH(backref_get())->regs;
	str_cat(result, RSTRING(str)->ptr+offset, beg-offset);

	repl = reg_regsub(val, str, regs);
	str_cat(result, RSTRING(repl)->ptr, RSTRING(repl)->len);
	if (BEG(0) == END(0)) {
	    int len = ismbchar(RSTRING(str)->ptr[END(0)])?2:1;
	    /*
	     * Always consume at least one character of the input string
	     * in order to prevent infinite loops.
	     */
	    if (RSTRING(str)->len > END(0)) {
		str_cat(result, RSTRING(str)->ptr+END(0), len);
	    }
	    offset = END(0)+len;
	}
	else {
	    offset = END(0);
	}

	if (once) break;
	if (offset > STRLEN(str)) break;
    }
    if (n == 0) return Qnil;
    if (RSTRING(str)->len > offset) {
	str_cat(result, RSTRING(str)->ptr+offset, RSTRING(str)->len-offset);
    }

    if (str_tainted(val)) str_taint(result);
    return result;
}

static VALUE
str_sub_f(str, pat, val, once)
    VALUE str;
    VALUE pat;
    VALUE val;
    int once;
{
    VALUE result;

    str_modify(str);
    result = str_sub_s(str, pat, val, once);
    if (NIL_P(result)) return Qnil;
    str_assign(str, result);

    return str;
}

static VALUE
str_sub_iter_s(str, pat, once)
    VALUE str;
    VALUE pat;
    int once;
{
    VALUE val, match, result;
    int beg, offset, n;
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
	match = backref_get();
	regs = RMATCH(match)->regs;
	str_cat(result, RSTRING(str)->ptr+offset, beg-offset);

	val = obj_as_string(rb_yield(reg_nth_match(0, match)));
	str_cat(result, RSTRING(val)->ptr, RSTRING(val)->len);

	if (BEG(0) == END(0)) {
	    int len = ismbchar(RSTRING(str)->ptr[END(0)])?2:1;

	    /*
	     * Always consume at least one character of the input string
	     * in order to prevent infinite loops.
	     */
	    if (RSTRING(str)->len > END(0)) {
		str_cat(result, RSTRING(str)->ptr+END(0), len);
	    }
	    offset = END(0)+len;
	}
	else {
	    offset = END(0);
	}

	if (once) break;
	if (offset > STRLEN(str)) break;
    }
    if (n == 0) return Qnil;
    if (RSTRING(str)->len > offset) {
	str_cat(result, RSTRING(str)->ptr+offset, RSTRING(str)->len-offset);
    }

    return result;
}

static VALUE
str_sub_iter_f(str, pat, once)
    VALUE str;
    VALUE pat;
    int once;
{
    VALUE result;

    str_modify(str);
    result = str_sub_iter_s(str, pat, once);
    if (NIL_P(result)) return Qnil;
    str_assign(str, result);

    return str;
}

static VALUE
str_aset(str, indx, val)
    VALUE str;
    VALUE indx, val;
{
    int idx, beg, end, offset;

    switch (TYPE(indx)) {
      case T_FIXNUM:
	idx = NUM2INT(indx);
	if (idx < 0) {
	    idx = RSTRING(str)->len + idx;
	}
	if (idx < 0 || RSTRING(str)->len <= idx) {
	    IndexError("index %d out of range [0..%d]", idx, RSTRING(str)->len-1);
	}
	if (TYPE(val) == T_STRING) {
	    str_replace(str, idx, 1, val);
	}
	else {
	    RSTRING(str)->ptr[idx] = NUM2INT(val) & 0xff;
	}
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
		str_replace2(str, beg, end, str_to_str(val));
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
    VALUE str;
{
    VALUE arg1, arg2, arg3;

    str_modify(str);

    if (rb_scan_args(argc, argv, "21", &arg1, &arg2, &arg3) == 3) {
	int beg, len;

	arg3 = str_to_str(arg3);
	beg = NUM2INT(arg1);
	if (beg < 0) {
	    beg = RSTRING(str)->len + beg;
	    if (beg < 0) beg = 0;
	}
	len = NUM2INT(arg2);
	if (len < 0) IndexError("negative length %d", len);
	if (beg + len > RSTRING(str)->len) {
	    len = RSTRING(str)->len - beg;
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
    if (NIL_P(v)) return str_dup(str);
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
    if (NIL_P(v)) return str_dup(str);
    return v;    
}

static VALUE
str_replace_method(str, str2)
    VALUE str, str2;
{
    str2 = str_to_str(str2);
    str_modify(str);
    str_resize(str, RSTRING(str2)->len);
    memcpy(RSTRING(str)->ptr, RSTRING(str2)->ptr, RSTRING(str2)->len);
    if (str_tainted(str2)) str_taint(str);

    return str;
}

static VALUE
uscore_get()
{
    VALUE line;

    line = lastline_get();
    if (TYPE(line) != T_STRING) {
	TypeError("$_ value need to be String (%s given)",
		  rb_class2name(CLASS_OF(line)));
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
    if (NIL_P(v)) v = str_dup(line);
    lastline_set(v);

    return v;
}

static VALUE
str_reverse_bang(str)
    VALUE str;
{
    char *s, *e, *p, *q;

    s = RSTRING(str)->ptr;
    e = s + RSTRING(str)->len - 1;
    p = q = ALLOCA_N(char, RSTRING(str)->len);

    while (e >= s) {
	*p++ = *e--;
    }
    MEMCPY(RSTRING(str)->ptr, q, char, RSTRING(str)->len);

    return str;
}

static VALUE
str_reverse(str)
    VALUE str;
{
    VALUE obj;
    char *s, *e, *p;

    if (RSTRING(str)->len <= 1) return str;

    obj = str_new(0, RSTRING(str)->len);
    s = RSTRING(str)->ptr; e = s + RSTRING(str)->len - 1;
    p = RSTRING(obj)->ptr;

    while (e >= s) {
	*p++ = *e--;
    }

    return obj;
}

static VALUE
str_include(str, arg)
    VALUE str, arg;
{
    int i;

    if (FIXNUM_P(arg)) {
	int c = FIX2INT(arg);
	int len = RSTRING(str)->len;
	char *p = RSTRING(str)->ptr;

	for (i=0; i<len; i++) {
	    if (p[i] == c) {
		return INT2FIX(i);
	    }
	}
	return FALSE;
    }

    i = str_index(str, str_to_str(arg), 0);

    if (i == -1) return FALSE;
    return INT2FIX(i);
}

static VALUE
str_to_i(str)
    VALUE str;
{
    return str2inum(RSTRING(str)->ptr, 10);
}

static VALUE
str_to_f(str)
    VALUE str;
{
    double f = atof(RSTRING(str)->ptr);

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
    VALUE str;
{
#define STRMAX 80
    char buf[STRMAX];
    char *p, *pend;
    char *b;

    p = RSTRING(str)->ptr; pend = p + RSTRING(str)->len;
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
	char c = *p++;
	if (ismbchar(c) && p < pend) {
	    CHECK(2);
	    *b++ = c;
	    *b++ = *p++;
	}
	else if ((c & 0x80) && current_mbctype != MBCTYPE_EUC) {
	    CHECK(1);
	    *b++ = c;
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
	else if (ISPRINT(c)) {
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
	else if (c == '\013') {
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
	    sprintf(b, "%03o", c & 0377);
	    b += 3;
	}
    }
    *b++ = '"';
    return str_new(buf, b - buf);
}

VALUE
str_dump(str)
    VALUE str;
{
    int len;
    char *p, *pend;
    char *q, *qend;
    VALUE result;

    len = 2;			/* "" */
    p = RSTRING(str)->ptr; pend = p + RSTRING(str)->len;
    while (p < pend) {
	char c = *p++;
	switch (c) {
	  case '"':  case '\'':
	  case '\n': case '\r':
	  case '\t': case '\f':
	  case '\013': case '\007': case '\033': 
	    len += 2;
	    break;

	  default:
	    if (ISPRINT(c)) {
		len++;
	    }
	    else {
		len += 4;		/* \nnn */
	    }
	    break;
	}
    }

    result = str_new(0, len);
    p = RSTRING(str)->ptr; pend = p + RSTRING(str)->len;
    q = RSTRING(result)->ptr; qend = q + len;

    *q++ = '"';
    while (p < pend) {
	char c = *p++;

	if (c == '"' || c == '\\') {
	    *q++ = '\\';
	    *q++ = c;
	}
	else if (ISPRINT(c)) {
	    *q++ = c;
	}
	else if (c == '\n') {
	    *q++ = '\\';
	    *q++ = 'n';
	}
	else if (c == '\r') {
	    *q++ = '\\';
	    *q++ = 'r';
	}
	else if (c == '\t') {
	    *q++ = '\\';
	    *q++ = 't';
	}
	else if (c == '\f') {
	    *q++ = '\\';
	    *q++ = 'f';
	}
	else if (c == '\13') {
	    *q++ = '\\';
	    *q++ = 'v';
	}
	else if (c == '\007') {
	    *q++ = '\\';
	    *q++ = 'a';
	}
	else if (c == 033) {
	    *q++ = '\\';
	    *q++ = 'e';
	}
	else {
	    *q++ = '\\';
	    sprintf(q, "%03o", c);
	    q += 3;
	}
    }
    *q++ = '"';

    return result;
}

static VALUE
str_upcase_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    while (s < send) {
	if (ismbchar(*s)) {
	    s++;
	}
	else if (islower(*s)) {
	    *s = toupper(*s);
	    modify = 1;
	}
	s++;
    }

    if (modify) return str;
    return Qnil;
}

static VALUE
str_upcase(str)
    VALUE str;
{
    VALUE val = str_upcase_bang(str = str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
str_downcase_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    while (s < send) {
	if (ismbchar(*s)) {
	    s++;
	}
	else if (ISUPPER(*s)) {
	    *s = tolower(*s);
	    modify = 1;
	}
	s++;
    }

    if (modify) return str;
    return Qnil;
}

static VALUE
str_downcase(str)
    VALUE str;
{
    VALUE val = str_downcase_bang(str = str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
str_capitalize_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    if (ISLOWER(*s)) {
	*s = toupper(*s);
	modify = 1;
    }
    while (++s < send) {
	if (ismbchar(*s)) {
	    s++;
	}
	else if (ISUPPER(*s)) {
	    *s = tolower(*s);
	    modify = 1;
	}
    }
    if (modify) return str;
    return Qnil;
}

static VALUE
str_capitalize(str)
    VALUE str;
{
    VALUE val = str_capitalize_bang(str = str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
str_swapcase_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    while (s < send) {
	if (ismbchar(*s)) {
	    s++;
	}
	else if (ISUPPER(*s)) {
	    *s = tolower(*s);
	    modify = 1;
	}
	else if (ISLOWER(*s)) {
	    *s = toupper(*s);
	    modify = 1;
	}
	s++;
    }

    if (modify) return str;
    return Qnil;
}

static VALUE
str_swapcase(str)
    VALUE str;
{
    VALUE val = str_swapcase_bang(str = str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

typedef unsigned char *USTR;

struct tr {
    int gen, now, max;
    char *p, *pend;
};

static int
trnext(t)
    struct tr *t;
{
    for (;;) {
	if (!t->gen) {
	    if (t->p == t->pend) return -1;
	    t->now = *(USTR)t->p++;
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

static VALUE str_delete_bang _((VALUE,VALUE));

static VALUE
tr_trans(str, src, repl, sflag)
    VALUE str, src, repl;
    int sflag;
{
    struct tr trsrc, trrepl;
    int cflag = 0;
    char trans[256];
    int i, c, c0, modify = 0;
    char *s, *send;

    str_modify(str);
    src = str_to_str(src);
    trsrc.p = RSTRING(src)->ptr; trsrc.pend = trsrc.p + RSTRING(src)->len;
    if (RSTRING(src)->len > 2 && RSTRING(src)->ptr[0] == '^') {
	cflag++;
	trsrc.p++;
    }
    repl = str_to_str(repl);
    if (RSTRING(repl)->len == 0) return str_delete_bang(str, src);
    trrepl.p = RSTRING(repl)->ptr;
    trrepl.pend = trrepl.p + RSTRING(repl)->len;
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

    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    c0 = -1;
    if (sflag) {
	char *t = s;

	while (s < send) {
	    c = trans[*s++ & 0xff] & 0xff;
	    if (s[-1] == c || c != c0) {
		c0 = (s[-1] == c)?-1:c;
		if (*t != c) {
		    *t = c;
		    modify = 1;
		}
		*t++ = c;
	    }
	}
	if (RSTRING(str)->len > (t - RSTRING(str)->ptr)) {
	    RSTRING(str)->len = (t - RSTRING(str)->ptr);
	    modify = 1;
	    *t = '\0';
	}
    }
    else {
	while (s < send) {
	    c = trans[*s & 0xff] & 0xff;
	    if (*s != c) {
		*s = c;
		modify = 1;
	    }
	    s++;
	}
    }

    if (modify) return str;
    return Qnil;
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
    VALUE val = tr_trans(str = str_dup(str), src, repl, 0);

    if (NIL_P(val)) return str;
    return val;
}

static void
tr_setup_table(str, table)
    VALUE str;
    char table[256];
{
    struct tr tr;
    int i, cflag = 0;
    int c;

    tr.p = RSTRING(str)->ptr; tr.pend = tr.p + RSTRING(str)->len;
    tr.gen = tr.now = tr.max = 0;
    if (RSTRING(str)->len > 1 && RSTRING(str)->ptr[0] == '^') {
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
    VALUE str1, str2;
{
    char *s, *send, *t;
    char squeez[256];
    int modify = 0;

    str2 = str_to_str(str2);
    tr_setup_table(str2, squeez);

    str_modify(str1);

    s = t = RSTRING(str1)->ptr;
    send = s + RSTRING(str1)->len;
    while (s < send) {
	if (squeez[*s & 0xff])
	    modify = 1;
	else
	    *t++ = *s;
	s++;
    }
    *t = '\0';
    RSTRING(str1)->len = t - RSTRING(str1)->ptr;

    if (modify) return str1;
    return Qnil;
}

static VALUE
str_delete(str1, str2)
    VALUE str1, str2;
{
    VALUE val = str_delete_bang(str1 = str_dup(str1), str2);

    if (NIL_P(val)) return str1;
    return val;
}

static VALUE
tr_squeeze(str1, str2)
    VALUE str1, str2;
{
    char squeez[256];
    char *s, *send, *t;
    char c, save, modify = 0;

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

    s = t = RSTRING(str1)->ptr;
    send = s + RSTRING(str1)->len;
    save = -1;
    while (s < send) {
	c = *s++ & 0xff;
	if (c != save || !squeez[c & 0xff]) {
	    *t++ = save = c;
	    modify = 1;
	}
    }
    *t = '\0';
    RSTRING(str1)->len = t - RSTRING(str1)->ptr;

    if (modify) return str1;
    return Qnil;
}

static VALUE
str_squeeze_bang(argc, argv, str1)
    int argc;
    VALUE *argv;
    VALUE str1;
{
    VALUE str2;

    if (rb_scan_args(argc, argv, "01", &str2) == 1) {
	str2 = str_to_str(str2);
    }
    return tr_squeeze(str1, str2);
}

static VALUE
str_squeeze(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE val = str_squeeze_bang(argc, argv, str = str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
str_tr_s_bang(str, src, repl)
    VALUE str, src, repl;
{
    return tr_trans(str, src, repl, 1);
}

static VALUE
str_tr_s(str, src, repl)
    VALUE str, src, repl;
{
    VALUE val = tr_trans(str = str_dup(str), src, repl, 1);

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
str_split_method(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    extern VALUE FS;
    VALUE spat;
    VALUE limit;
    int char_sep = -1;
    int beg, end, lim, i;
    VALUE result, tmp;

    if (rb_scan_args(argc, argv, "02", &spat, &limit) == 2) {
	lim = NUM2INT(limit);
	if (lim == 0) limit = Qnil;
	else if (lim == 1) return ary_new3(1, str);
	i = 1;
    }

    if (argc == 0) {
	if (!NIL_P(FS)) {
	    spat = FS;
	    goto fs_set;
	}
	char_sep = ' ';
    }
    else {
	switch (TYPE(spat)) {
	  case T_STRING:
	  fs_set:
	    if (STRLEN(spat) == 1) {
		char_sep = (unsigned char)RSTRING(spat)->ptr[0];
	    }
	    else {
		spat = reg_regcomp(spat);
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
    if (char_sep >= 0) {
	char *ptr = RSTRING(str)->ptr;
	int len = RSTRING(str)->len;
	char *eptr = ptr + len;

	if (char_sep == ' ') {	/* AWK emulation */
	    int skip = 1;

	    for (end = beg = 0; ptr<eptr; ptr++) {
		if (skip) {
		    if (ISSPACE(*ptr)) {
			beg++;
		    }
		    else {
			end = beg+1;
			skip = 0;
		    }
		}
		else {
		    if (ISSPACE(*ptr)) {
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
		if (*ptr == (char)char_sep) {
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
		    if (ismbchar(RSTRING(str)->ptr[beg]))
			ary_push(result, str_substr(str, beg, 2));
		    else
			ary_push(result, str_substr(str, beg, 1));
		    beg = start;
		}
		else {
		    start += ismbchar(RSTRING(str)->ptr[start])?2:1;
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
    if (RSTRING(str)->len > beg) {
	ary_push(result, str_subseq(str, beg, -1));
    }

    return result;
}

VALUE
str_split(str, sep0)
    VALUE str;
    char *sep0;
{
    VALUE sep;

    str = str_to_str(str);
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
    VALUE str;
{
    VALUE rs;
    int newline;
    int rslen;
    char *p = RSTRING(str)->ptr, *pend = p + RSTRING(str)->len, *s;
    char *ptr = p;
    int len = RSTRING(str)->len;
    VALUE line;

    if (rb_scan_args(argc, argv, "01", &rs) == 0) {
	rs = RS;
    }

    if (NIL_P(rs)) {
	rb_yield(str);
	return Qnil;
    }
    rs = str_to_str(rs);

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
	}
	if (p[-1] == newline &&
	    (rslen <= 1 ||
	     memcmp(RSTRING(rs)->ptr, p-rslen, rslen) == 0)) {
	    line = str_new(s, p - s);
	    lastline_set(line);
	    rb_yield(line);
	    if (RSTRING(str)->ptr != ptr || RSTRING(str)->len != len)
		Fail("string modified");
	    s = p;
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

    for (i=0; i<RSTRING(str)->len; i++) {
	rb_yield(INT2FIX(RSTRING(str)->ptr[i] & 0xff));
    }
    return Qnil;
}

static VALUE
str_chop_bang(str)
    VALUE str;
{
    if (RSTRING(str)->len > 0) {
	str_modify(str);
	RSTRING(str)->len--;
	if (RSTRING(str)->ptr[RSTRING(str)->len] == '\n') {
	    if (RSTRING(str)->len > 0 &&
		RSTRING(str)->ptr[RSTRING(str)->len-1] == '\r') {
		RSTRING(str)->len--;
	    }
	}
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
	return str;
    }
    return Qnil;
}

static VALUE
str_chop(str)
    VALUE str;
{
    VALUE val = str_chop_bang(str = str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
f_chop_bang(str)
    VALUE str;
{
    return str_chop_bang(uscore_get());
}

static VALUE
f_chop()
{
    VALUE str = str_dup(uscore_get());
    VALUE val;

    val = str_chop_bang(str);
    if (NIL_P(val)) return str;
    lastline_set(val);
    return val;
}

static VALUE
str_chomp_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE rs;
    int newline;
    int rslen;
    char *p = RSTRING(str)->ptr;
    int len = RSTRING(str)->len;

    if (rb_scan_args(argc, argv, "01", &rs) == 0) {
	rs = RS;
    }
    if (NIL_P(rs)) return Qnil;

    rs = str_to_str(rs);
    rslen = RSTRING(rs)->len;
    if (rslen == 0) {
	while (len>0 && p[len-1] == '\n') {
	    len--;
	}
	if (len < RSTRING(str)->len) {
	    RSTRING(str)->len = len;
	    RSTRING(str)->ptr[len] = '\0';
	    return str;
	}
	return Qnil;
    }
    if (rslen > len) return Qnil;
    newline = RSTRING(rs)->ptr[rslen-1];

    if (p[len-1] == newline &&
	(rslen <= 1 ||
	 memcmp(RSTRING(rs)->ptr, p+len-rslen, rslen) == 0)) {
	RSTRING(str)->len -= rslen;
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
	return str;
    }
    return Qnil;
}

static VALUE
str_chomp(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE val = str_chomp_bang(argc, argv, str = str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
f_chomp_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    return str_chomp_bang(argc, argv, uscore_get());
}

static VALUE
f_chomp(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str = str_dup(uscore_get());
    VALUE val = str_chomp_bang(argc, argv, str);

    if (NIL_P(val)) return str;
    lastline_set(val);
    return val;
}

static VALUE
str_strip_bang(str)
    VALUE str;
{
    char *s, *t, *e;

    str_modify(str);
    s = RSTRING(str)->ptr;
    e = t = s + RSTRING(str)->len;
    /* remove spaces at head */
    while (s < t && ISSPACE(*s)) s++;

    /* remove trailing spaces */
    t--;
    while (s <= t && ISSPACE(*t)) t--;
    t++;

    RSTRING(str)->len = t-s;
    if (s > RSTRING(str)->ptr) { 
	char *p = RSTRING(str)->ptr;

	RSTRING(str)->ptr = ALLOC_N(char, RSTRING(str)->len+1);
	memcpy(RSTRING(str)->ptr, s, RSTRING(str)->len);
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
	free(p);
    }
    else if (t < e) {
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
    }
    else {
	return Qnil;
    }

    return str;
}

static VALUE
str_strip(str)
    VALUE str;
{
    VALUE val = str_strip_bang(str = str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
scan_once(str, pat, start)
    VALUE str, pat;
    int *start;
{
    VALUE result, match;
    struct re_registers *regs;
    int i;

    if (reg_search(pat, str, *start, 0) >= 0) {
	match = backref_get();
	regs = RMATCH(match)->regs;
	if (END(0) == *start) {
	    *start = END(0)+1;
	}
	else {
	    *start = END(0);
	}
	if (regs->num_regs == 1) {
	    return reg_nth_match(0, match);
	}
	result = ary_new2(regs->num_regs);
	for (i=1; i < regs->num_regs; i++) {
	    ary_push(result, reg_nth_match(i, match));
	}

	return result;
    }
    return Qnil;
}

static VALUE
str_scan(str, pat)
    VALUE str, pat;
{
    VALUE result;
    int start = 0;

    switch (TYPE(pat)) {
      case T_STRING:
	pat = reg_regcomp(pat);
	break;
      case T_REGEXP:
	break;
      default:
	Check_Type(pat, T_REGEXP);
    }

    if (!iterator_p()) {
	VALUE ary = ary_new();

	while (!NIL_P(result = scan_once(str, pat, &start))) {
	    ary_push(ary, result);
	}
	return ary;
    }

    while (!NIL_P(result = scan_once(str, pat, &start))) {
	rb_yield(result);
    }
    return Qnil;
}

static VALUE
str_hex(str)
    VALUE str;
{
    return str2inum(RSTRING(str)->ptr, 16);
}

static VALUE
str_oct(str)
    VALUE str;
{
    int base = 8;

    if (RSTRING(str)->len > 2 && RSTRING(str)->ptr[0] == '0' &&
	(RSTRING(str)->ptr[1] == 'x' || RSTRING(str)->ptr[1] == 'X')) {
	base = 16;
    }
    return str2inum(RSTRING(str)->ptr, base);
}

static VALUE
str_crypt(str, salt)
    VALUE str, salt;
{
    extern char *crypt();

    salt = str_to_str(salt);
    if (RSTRING(salt)->len < 2)
	ArgError("salt too short(need >2 bytes)");
    return str_new2(crypt(RSTRING(str)->ptr, RSTRING(salt)->ptr));
}

static VALUE
str_intern(str)
    VALUE str;
{
    ID id;

    if (strlen(RSTRING(str)->ptr) != RSTRING(str)->len)
	ArgError("string contains `\\0'");
    id = rb_intern(RSTRING(str)->ptr);
    return INT2FIX(id);
}

static VALUE
str_sum(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE vbits;
    int   bits;
    char *p, *pend;

    if (rb_scan_args(argc, argv, "01", &vbits) == 0) {
	bits = 16;
    }
    else bits = NUM2INT(vbits);

    p = RSTRING(str)->ptr; pend = p + RSTRING(str)->len;
    if (bits > sizeof(long)*CHAR_BIT) {
	VALUE res = INT2FIX(0);
	VALUE mod;

	mod = rb_funcall(INT2FIX(1), rb_intern("<<"), 1, INT2FIX(bits));
	mod = rb_funcall(mod, '-', 1, INT2FIX(1));

	while (p < pend) {
	    res = rb_funcall(res, '+', 1, INT2FIX((unsigned int)*p));
	    p++;
	}
	res = rb_funcall(res, '&', 1, mod);
	return res;
    }
    else {
	unsigned int res = 0;
	unsigned int mod = (1<<bits)-1;

	if (mod == 0) {
	    mod = -1;
	}
	while (p < pend) {
	    res += (unsigned int)*p;
	    p++;
	}
	res &= mod;
	return int2inum(res);
    }
}

static VALUE
str_ljust(str, w)
    VALUE str;
    VALUE w;
{
    int width = NUM2INT(w);
    VALUE res;
    char *p, *pend;

    if (width < 0 || RSTRING(str)->len >= width) return str;
    res = str_new(0, width);
    memcpy(RSTRING(res)->ptr, RSTRING(str)->ptr, RSTRING(str)->len);
    p = RSTRING(res)->ptr + RSTRING(str)->len; pend = RSTRING(res)->ptr + width;
    while (p < pend) {
	*p++ = ' ';
    }
    return res;
}

static VALUE
str_rjust(str, w)
    VALUE str;
    VALUE w;
{
    int width = NUM2INT(w);
    VALUE res;
    char *p, *pend;

    if (width < 0 || RSTRING(str)->len >= width) return str;
    res = str_new(0, width);
    p = RSTRING(res)->ptr; pend = p + width - RSTRING(str)->len;
    while (p < pend) {
	*p++ = ' ';
    }
    memcpy(pend, RSTRING(str)->ptr, RSTRING(str)->len);
    return res;
}

static VALUE
str_center(str, w)
    VALUE str;
    VALUE w;
{
    int width = NUM2INT(w);
    VALUE res;
    char *p, *pend;
    int n;

    if (width < 0 || RSTRING(str)->len >= width) return str;
    res = str_new(0, width);
    n = (width - RSTRING(str)->len)/2;
    p = RSTRING(res)->ptr; pend = p + n;
    while (p < pend) {
	*p++ = ' ';
    }
    memcpy(pend, RSTRING(str)->ptr, RSTRING(str)->len);
    p = pend + RSTRING(str)->len; pend = RSTRING(res)->ptr + width;
    while (p < pend) {
	*p++ = ' ';
    }
    return res;
}

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
    rb_define_method(cString, "%", str_format, 1);
    rb_define_method(cString, "[]", str_aref_method, -1);
    rb_define_method(cString, "[]=", str_aset_method, -1);
    rb_define_method(cString, "length", str_length, 0);
    rb_define_alias(cString,  "size", "length");
    rb_define_method(cString, "empty?", str_empty, 0);
    rb_define_method(cString, "=~", str_match, 1);
    rb_define_method(cString, "~", str_match2, 0);
    rb_define_method(cString, "succ", str_succ, 0);
    rb_define_method(cString, "succ!", str_succ_bang, 0);
    rb_define_method(cString, "next", str_succ, 0);
    rb_define_method(cString, "next!", str_succ_bang, 0);
    rb_define_method(cString, "upto", str_upto, 1);
    rb_define_method(cString, "index", str_index_method, -1);
    rb_define_method(cString, "rindex", str_rindex, -1);
    rb_define_method(cString, "replace", str_replace_method, 1);

    rb_define_method(cString, "freeze", str_freeze, 0);
    rb_define_method(cString, "frozen?", str_frozen_p, 0);

    rb_define_method(cString, "taint", str_taint, 0);
    rb_define_method(cString, "tainted?", str_tainted, 0);

    rb_define_method(cString, "to_i", str_to_i, 0);
    rb_define_method(cString, "to_f", str_to_f, 0);
    rb_define_method(cString, "to_s", str_to_s, 0);
    rb_define_method(cString, "to_str", str_to_s, 0);
    rb_define_method(cString, "inspect", str_inspect, 0);
    rb_define_method(cString, "dump", str_dump, 0);

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

    rb_define_method(cString, "include?", str_include, 1);

    rb_define_method(cString, "scan", str_scan, 1);

    rb_define_method(cString, "ljust", str_ljust, 1);
    rb_define_method(cString, "rjust", str_rjust, 1);
    rb_define_method(cString, "center", str_center, 1);

    rb_define_method(cString, "sub", str_sub, -1);
    rb_define_method(cString, "gsub", str_gsub, -1);
    rb_define_method(cString, "chop", str_chop, 0);
    rb_define_method(cString, "chomp", str_chomp, -1);
    rb_define_method(cString, "strip", str_strip, 0);

    rb_define_method(cString, "sub!", str_sub_bang, -1);
    rb_define_method(cString, "gsub!", str_gsub_bang, -1);
    rb_define_method(cString, "strip!", str_strip_bang, 0);
    rb_define_method(cString, "chop!", str_chop_bang, 0);
    rb_define_method(cString, "chomp!", str_chomp_bang, -1);

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

    rb_define_global_function("chomp", f_chomp, -1);
    rb_define_global_function("chomp!", f_chomp_bang, -1);

    rb_define_global_function("split", f_split, -1);

    pr_str = rb_intern("to_s");
}
