/************************************************

  string.c -

  $Author$
  $Date$
  created at: Mon Aug  9 17:12:58 JST 1993

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"

#define BEG(no) regs->beg[no]
#define END(no) regs->end[no]

#include <ctype.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifndef atof
double strtod();
#endif

VALUE rb_cString;

#define STR_FREEZE FL_USER1
#define STR_NO_ORIG FL_USER3

extern VALUE rb_rs;

VALUE
rb_str_new(ptr, len)
    const char *ptr;
    int len;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, rb_cString, T_STRING);

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
rb_str_new2(ptr)
    const char *ptr;
{
    return rb_str_new(ptr, strlen(ptr));
}

VALUE
rb_tainted_str_new(ptr, len)
    const char *ptr;
    int len;
{
    VALUE str = rb_str_new(ptr, len);

    FL_SET(str, FL_TAINT);
    return str;
}

VALUE
rb_tainted_str_new2(ptr)
    const char *ptr;
{
    VALUE str = rb_str_new2(ptr);

    FL_SET(str, FL_TAINT);
    return str;
}

VALUE
rb_str_new3(str)
    VALUE str;
{
    NEWOBJ(str2, struct RString);
    OBJSETUP(str2, rb_cString, T_STRING);

    str2->len = RSTRING(str)->len;
    str2->ptr = RSTRING(str)->ptr;
    str2->orig = str;

    return (VALUE)str2;
}

VALUE
rb_str_new4(orig)
    VALUE orig;
{
    if (FL_TEST(orig, STR_FREEZE)) {
	return orig;
    }
    else if (RSTRING(orig)->orig && !FL_TEST(orig, STR_NO_ORIG)) {
	return rb_str_freeze(RSTRING(orig)->orig);
    }
    else {
	NEWOBJ(str, struct RString);
	OBJSETUP(str, rb_cString, T_STRING);

	str->len = RSTRING(orig)->len;
	str->ptr = RSTRING(orig)->ptr;
	RSTRING(orig)->orig = (VALUE)str;
	str->orig = 0;
	if (FL_TEST(str, FL_TAINT)) {
	    FL_SET(str, FL_TAINT);
	}
	return (VALUE)str;
    }
}

VALUE
rb_str_to_str(str)
    VALUE str;
{
    return rb_convert_type(str, T_STRING, "String", "to_str");
}

static void
rb_str_assign(str, str2)
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
    if (OBJ_TAINTED(str2)) OBJ_TAINT(str);
}

static ID to_str;

VALUE
rb_obj_as_string(obj)
    VALUE obj;
{
    VALUE str;

    if (TYPE(obj) == T_STRING) {
	return obj;
    }
    str = rb_funcall(obj, to_str, 0);
    if (TYPE(str) != T_STRING)
	return rb_any_to_s(obj);
    if (OBJ_TAINTED(obj)) OBJ_TAINT(str);
    return str;
}

static VALUE
rb_str_clone(orig)
    VALUE orig;
{
    VALUE str;

    if (RSTRING(orig)->orig && !FL_TEST(orig, STR_NO_ORIG))
	str = rb_str_new3(RSTRING(orig)->orig);
    else
	str = rb_str_new(RSTRING(orig)->ptr, RSTRING(orig)->len);
    if (RSTRING(orig)->orig && FL_TEST(orig, STR_NO_ORIG))
	RSTRING(str)->orig = RSTRING(orig)->orig;
    CLONESETUP(str, orig);
    return str;
}

VALUE
rb_str_dup(str)
    VALUE str;
{
    VALUE s;

    if (TYPE(str) != T_STRING) str = rb_str_to_str(str);
    s = rb_str_new(RSTRING(str)->ptr, RSTRING(str)->len);
    if (OBJ_TAINTED(str)) OBJ_TAINT(s);

    return s;
}

static VALUE
rb_str_s_new(klass, orig)
    VALUE klass;
    VALUE orig;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, klass, T_STRING);

    str->orig = 0;
    orig = rb_obj_as_string(orig);
    str->len = RSTRING(orig)->len;
    if (RSTRING(orig)->ptr) {
	str->ptr = ALLOC_N(char, RSTRING(orig)->len+1);
	memcpy(str->ptr, RSTRING(orig)->ptr, RSTRING(orig)->len);
	str->ptr[RSTRING(orig)->len] = '\0';
    }

    if (rb_safe_level() >= 3) {
	FL_SET(str, FL_TAINT);
    }
    rb_obj_call_init((VALUE)str, 1, &orig);

    return (VALUE)str;
}

static VALUE
rb_str_length(str)
    VALUE str;
{
    return INT2FIX(RSTRING(str)->len);
}

static VALUE
rb_str_empty(str)
    VALUE str;
{
    if (RSTRING(str)->len == 0)
	return Qtrue;
    return Qfalse;
}

VALUE
rb_str_plus(str1, str2)
    VALUE str1, str2;
{
    VALUE str3;

    if (TYPE(str2) != T_STRING) str2 = rb_str_to_str(str2);
    str3 = rb_str_new(0, RSTRING(str1)->len+RSTRING(str2)->len);
    memcpy(RSTRING(str3)->ptr, RSTRING(str1)->ptr, RSTRING(str1)->len);
    memcpy(RSTRING(str3)->ptr + RSTRING(str1)->len,
	   RSTRING(str2)->ptr, RSTRING(str2)->len);
    RSTRING(str3)->ptr[RSTRING(str3)->len] = '\0';

    if (OBJ_TAINTED(str1) || OBJ_TAINTED(str2))
	OBJ_TAINT(str3);
    return str3;
}

VALUE
rb_str_times(str, times)
    VALUE str;
    VALUE times;
{
    VALUE str2;
    int i, len;

    len = NUM2INT(times);
    if (len < 0) {
	rb_raise(rb_eArgError, "negative argument");
    }

    str2 = rb_str_new(0, RSTRING(str)->len*len);
    for (i=0; i<len; i++) {
	memcpy(RSTRING(str2)->ptr+(i*RSTRING(str)->len),
	       RSTRING(str)->ptr, RSTRING(str)->len);
    }
    RSTRING(str2)->ptr[RSTRING(str2)->len] = '\0';

    if (OBJ_TAINTED(str)) {
	OBJ_TAINT(str2);
    }

    return str2;
}

static VALUE
rb_str_format(str, arg)
    VALUE str, arg;
{
    VALUE *argv;

    if (TYPE(arg) == T_ARRAY) {
	argv = ALLOCA_N(VALUE, RARRAY(arg)->len + 1);
	argv[0] = str;
	MEMCPY(argv+1, RARRAY(arg)->ptr, VALUE, RARRAY(arg)->len);
	return rb_f_sprintf(RARRAY(arg)->len+1, argv);
    }
    
    argv = ALLOCA_N(VALUE, 2);
    argv[0] = str;
    argv[1] = arg;
    return rb_f_sprintf(2, argv);
}

VALUE
rb_str_substr(str, beg, len)
    VALUE str;
    int beg, len;
{
    VALUE str2;

    if (len < 0) return Qnil;
    if (beg > RSTRING(str)->len) return Qnil;
    if (beg < 0) {
	beg += RSTRING(str)->len;
	if (beg < 0) return Qnil;
    }
    if (beg + len > RSTRING(str)->len) {
	len = RSTRING(str)->len - beg;
    }
    if (len < 0) {
	len = 0;
    }
    if (len == 0) return rb_str_new(0,0);

    str2 = rb_str_new(RSTRING(str)->ptr+beg, len);
    if (OBJ_TAINTED(str)) OBJ_TAINT(str2);

    return str2;
}

void
rb_str_modify(str)
    VALUE str;
{
    char *ptr;

    if (FL_TEST(str, STR_FREEZE))
	rb_raise(rb_eTypeError, "can't modify frozen string");
    if (!FL_TEST(str, FL_TAINT) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't modify string");
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
rb_str_freeze(str)
    VALUE str;
{
    FL_SET(str, STR_FREEZE);
    return str;
}

static VALUE
rb_str_frozen_p(str)
    VALUE str;
{
    if (FL_TEST(str, STR_FREEZE))
	return Qtrue;
    return Qfalse;
}

VALUE
rb_str_dup_frozen(str)
    VALUE str;
{
    if (RSTRING(str)->orig && !FL_TEST(str, STR_NO_ORIG)) {
	return rb_str_freeze(RSTRING(str)->orig);
    }
    if (FL_TEST(str, STR_FREEZE))
	return str;
    return rb_str_freeze(rb_str_dup(str));
}

VALUE
rb_str_resize(str, len)
    VALUE str;
    int len;
{
    rb_str_modify(str);

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
rb_str_cat(str, ptr, len)
    VALUE str;
    const char *ptr;
    int len;
{
    if (len > 0) {
	rb_str_modify(str);
	REALLOC_N(RSTRING(str)->ptr, char, RSTRING(str)->len + len + 1);
	if (ptr)
	    memcpy(RSTRING(str)->ptr + RSTRING(str)->len, ptr, len);
	RSTRING(str)->len += len;
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0'; /* sentinel */
    }
    return str;
}

VALUE
rb_str_concat(str1, str2)
    VALUE str1, str2;
{
    if (FIXNUM_P(str2)) {
	int i = FIX2INT(str2);
	if (0 <= i && i <= 0xff) { /* byte */
	    char c = i;
	    return rb_str_cat(str1, &c, 1);
	}
    }
    if (TYPE(str2) != T_STRING) str2 = rb_str_to_str(str2);
    return rb_str_cat(str1, RSTRING(str2)->ptr, RSTRING(str2)->len);
}

int
rb_str_hash(str)
    VALUE str;
{
    register int len = RSTRING(str)->len;
    register char *p = RSTRING(str)->ptr;
    register int key = 0;

    if (ruby_ignorecase) {
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
rb_str_hash_method(str)
    VALUE str;
{
    int key = rb_str_hash(str);
    return INT2FIX(key);
}

#define lesser(a,b) (((a)>(b))?(b):(a))

int
rb_str_cmp(str1, str2)
    VALUE str1, str2;
{
    int len, retval;

    if (ruby_ignorecase) {
	return rb_str_cicmp(str1, str2);
    }

    len = lesser(RSTRING(str1)->len, RSTRING(str2)->len);
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
rb_str_equal(str1, str2)
    VALUE str1, str2;
{
    if (TYPE(str2) != T_STRING)
	return Qfalse;

    if (RSTRING(str1)->len == RSTRING(str2)->len
	&& rb_str_cmp(str1, str2) == 0) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
rb_str_cmp_method(str1, str2)
    VALUE str1, str2;
{
    int result;

    if (TYPE(str2) != T_STRING) str2 = rb_str_to_str(str2);
    result = rb_str_cmp(str1, str2);
    return INT2FIX(result);
}

static VALUE
rb_str_match(x, y)
    VALUE x, y;
{
    VALUE reg;
    int start;

    switch (TYPE(y)) {
      case T_REGEXP:
	return rb_reg_match(y, x);

      case T_STRING:
	reg = rb_reg_regcomp(y);
	start = rb_reg_search(reg, x, 0, 0);
	if (start == -1) {
	    return Qfalse;
	}
	return INT2FIX(start);

      default:
	return rb_funcall(y, rb_intern("=~"), 1, x);
    }
}

static VALUE
rb_str_match2(str)
    VALUE str;
{
    return rb_reg_match2(rb_reg_regcomp(str));
}

static int
rb_str_index(str, sub, offset)
    VALUE str, sub;
    int offset;
{
    char *s, *e, *p;
    int len;

    if (offset < 0) {
	offset += RSTRING(str)->len;
	if (offset < 0) return -1;
    }
    if (RSTRING(str)->len - offset < RSTRING(sub)->len) return -1;
    s = RSTRING(str)->ptr+offset;
    p = RSTRING(sub)->ptr;
    len = RSTRING(sub)->len;
    if (len == 0) return offset;
    e = RSTRING(str)->ptr + RSTRING(str)->len - len + 1;
    while (s < e) {
	if (*s == *(RSTRING(sub)->ptr) && memcmp(s, p, len) == 0) {
	    return (s-(RSTRING(str)->ptr));
	}
	s++;
    }
    return -1;
}

static VALUE
rb_str_index_method(argc, argv, str)
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
	pos = rb_reg_search(sub, str, pos, 0);
	break;

      case T_STRING:
	pos = rb_str_index(str, sub, pos);
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
	rb_raise(rb_eTypeError, "type mismatch: %s given",
		 rb_class2name(CLASS_OF(sub)));
    }

    if (pos == -1) return Qnil;
    return INT2FIX(pos);
}

static VALUE
rb_str_rindex(argc, argv, str)
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
	pos = rb_reg_search(sub, str, pos, 1);
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
	rb_raise(rb_eTypeError, "type mismatch: %s given",
		 rb_class2name(CLASS_OF(sub)));
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
rb_str_succ(orig)
    VALUE orig;
{
    VALUE str, str2;
    char *sbeg, *s;
    char c = -1;

    str = rb_str_new(RSTRING(orig)->ptr, RSTRING(orig)->len);

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
	    str2 = rb_str_new(0, RSTRING(str)->len+1);
	    RSTRING(str2)->ptr[0] = c;
	    memcpy(RSTRING(str2)->ptr+1, RSTRING(str)->ptr, RSTRING(str)->len);
	    str = str2;
	}
    }

    if (OBJ_TAINTED(orig)) {
	OBJ_TAINT(str);
    }

    return str;
}

static VALUE
rb_str_succ_bang(str)
    VALUE str;
{
    rb_str_modify(str);
    rb_str_assign(str, rb_str_succ(str));

    return str;
}

VALUE
rb_str_upto(beg, end, excl)
    VALUE beg, end;
    int excl;
{
    VALUE current;

    if (TYPE(end) != T_STRING) end = rb_str_to_str(end);

    current = beg;
    for (;;) {
	rb_yield(current);
	if (!excl && rb_str_equal(current, end)) break;
	current = rb_str_succ(current);
	if (excl && rb_str_equal(current, end)) break;
	if (RSTRING(current)->len > RSTRING(end)->len)
	    break;
    }

    return Qnil;
}

static VALUE
rb_str_upto_method(beg, end)
    VALUE beg, end;
{
    return rb_str_upto(beg, end, 0);
}

static VALUE
rb_str_aref(str, indx)
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
	if (rb_reg_search(indx, str, 0, 0) >= 0)
	    return rb_reg_last_match(rb_backref_get());
	return Qnil;

      case T_STRING:
	if (rb_str_index(str, indx, 0) != -1) return indx;
	return Qnil;

      default:
	/* check if indx is Range */
	{
	    int beg, len;
	    switch (rb_range_beg_len(indx, &beg, &len, RSTRING(str)->len, 0)) {
	      case Qfalse:
		break;
	      case Qnil:
		return Qnil;
	      default:
		return rb_str_substr(str, beg, len);
	    }
	}
	rb_raise(rb_eIndexError, "invalid index for string");
    }
    return Qnil;		/* not reached */
}

static VALUE
rb_str_aref_method(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE arg1, arg2;

    if (rb_scan_args(argc, argv, "11", &arg1, &arg2) == 2) {
	return rb_str_substr(str, NUM2INT(arg1), NUM2INT(arg2));
    }
    return rb_str_aref(str, arg1);
}

static void
rb_str_replace(str, beg, len, val)
    VALUE str, val;
    int beg;
    int len;
{
    if (len < RSTRING(val)->len) {
	/* expand string */
	REALLOC_N(RSTRING(str)->ptr, char, RSTRING(str)->len+RSTRING(val)->len-len+1);
    }

    if (len != RSTRING(val)->len) {
	memmove(RSTRING(str)->ptr + beg + RSTRING(val)->len,
		RSTRING(str)->ptr + beg + len,
		RSTRING(str)->len - (beg + len));
    }
    if (RSTRING(str)->len < beg && len < 0) {
	MEMZERO(RSTRING(str)->ptr + RSTRING(str)->len, char, -len);
    }
    memcpy(RSTRING(str)->ptr+beg, RSTRING(val)->ptr, RSTRING(val)->len);
    RSTRING(str)->len += RSTRING(val)->len - len;
    RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
}

static VALUE rb_str_sub_bang _((int, VALUE*, VALUE));

static VALUE
rb_str_aset(str, indx, val)
    VALUE str;
    VALUE indx, val;
{
    int idx;
    int beg, end;

    switch (TYPE(indx)) {
      case T_FIXNUM:
	beg = idx = NUM2INT(indx);
	if (idx < 0) {
	    idx += RSTRING(str)->len;
	}
	if (idx < 0 || RSTRING(str)->len < idx) {
	    rb_raise(rb_eIndexError, "index %d out of string", NUM2INT(beg));
	}
	if (FIXNUM_P(val)) {
	    if (RSTRING(str)->len == idx) {
		RSTRING(str)->len += 1;
		REALLOC_N(RSTRING(str)->ptr, char, RSTRING(str)->len);
	    }
	    RSTRING(str)->ptr[idx] = NUM2INT(val) & 0xff;
	}
	else {
	    if (TYPE(val) != T_STRING) val = rb_str_to_str(val);
	    rb_str_replace(str, idx, 1, val);
	}
	return val;

      case T_REGEXP:
        {
	    VALUE args[2];
	    args[0] = indx;
	    args[1] = val;
	    rb_str_sub_bang(2, args, str);
	}
	return val;

      case T_STRING:
	beg = rb_str_index(str, indx, 0);
	if (beg != -1) {
	    if (TYPE(val) != T_STRING) val = rb_str_to_str(val);
	    rb_str_replace(str, beg, RSTRING(indx)->len, val);
	}
	return val;

      default:
	/* check if indx is Range */
	{
	    int beg, len;
	    if (rb_range_beg_len(indx, &beg, &len, RSTRING(str)->len, 2)) {
		if (TYPE(val) != T_STRING) val = rb_str_to_str(val);
		rb_str_replace(str, beg, len, val);
		return val;
	    }
	}
	rb_raise(rb_eIndexError, "invalid index for string");
    }
}

static VALUE
rb_str_aset_method(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE arg1, arg2, arg3;

    rb_str_modify(str);

    if (rb_scan_args(argc, argv, "21", &arg1, &arg2, &arg3) == 3) {
	int beg, len;

	if (TYPE(arg3) != T_STRING) arg3 = rb_str_to_str(arg3);
	beg = NUM2INT(arg1);
	len = NUM2INT(arg2);
	if (len < 0) rb_raise(rb_eIndexError, "negative length %d", len);
	if (beg < 0) {
	    beg += RSTRING(str)->len;
	}
	if (beg < 0 || RSTRING(str)->len < beg) {
	    if (beg < 0) {
		beg -= RSTRING(str)->len;
	    }
	    rb_raise(rb_eIndexError, "index %d out of string", beg);
	}
	if (beg + len > RSTRING(str)->len) {
	    len = RSTRING(str)->len - beg;
	}
	rb_str_replace(str, beg, len, arg3);
	return arg3;
    }
    return rb_str_aset(str, arg1, arg2);
}

static VALUE
get_pat(pat)
    VALUE pat;
{
    switch (TYPE(pat)) {
      case T_REGEXP:
	break;

      case T_STRING:
	pat = rb_reg_regcomp(pat);
	break;

      default:
	/* type failed */
	Check_Type(pat, T_REGEXP);
    }
    return pat;
}

static VALUE
rb_str_sub_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE pat, repl, match;
    struct re_registers *regs;
    int iter = 0;
    int plen;

    if (argc == 1 && rb_iterator_p()) {
	iter = 1;
    }
    else if (argc == 2) {
	repl = rb_obj_as_string(argv[1]);;
    }
    else {
	rb_raise(rb_eArgError, "wrong # of arguments(%d for 2)", argc);
    }

    pat = get_pat(argv[0]);
    if (rb_reg_search(pat, str, 0, 0) >= 0) {
	rb_str_modify(str);
	match = rb_backref_get();
	regs = RMATCH(match)->regs;

	if (iter) {
	    rb_match_busy(match, Qtrue);
	    repl = rb_obj_as_string(rb_yield(rb_reg_nth_match(0, match)));
	    rb_match_busy(match, Qfalse);
	    rb_backref_set(match);
	}
	else {
	    repl = rb_reg_regsub(repl, str, regs);
	}
	plen = END(0) - BEG(0);
	if (RSTRING(repl)->len > plen) {
	    REALLOC_N(RSTRING(str)->ptr, char,
		      RSTRING(str)->len + RSTRING(repl)->len - plen + 1);
	}
	if (RSTRING(repl)->len != plen) {
	    memmove(RSTRING(str)->ptr + BEG(0) + RSTRING(repl)->len,
		    RSTRING(str)->ptr + BEG(0) + plen,
		    RSTRING(str)->len - BEG(0) - plen);
	}
	memcpy(RSTRING(str)->ptr + BEG(0),
	       RSTRING(repl)->ptr, RSTRING(repl)->len);
	RSTRING(str)->len += RSTRING(repl)->len - plen;
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
	return str;
    }
    return Qnil;
}

static VALUE
rb_str_sub(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE val = rb_str_sub_bang(argc, argv, str = rb_str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_str_gsub_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE pat, val, repl, match;
    struct re_registers *regs;
    int beg, n;
    int iter = 0;
    char *buf, *bp, *cp;
    int offset, blen, len;

    if (argc == 1 && rb_iterator_p()) {
	iter = 1;
    }
    else if (argc == 2) {
	repl = rb_obj_as_string(argv[1]);;
    }
    else {
	rb_raise(rb_eArgError, "wrong # of arguments(%d for 2)", argc);
    }

    pat = get_pat(argv[0]);
    offset=0; n=0; 
    beg = rb_reg_search(pat, str, 0, 0);
    if (beg < 0) return Qnil;	/* no match, no substitution */

    blen = RSTRING(str)->len + 30; /* len + margin */
    buf = ALLOC_N(char, blen);
    bp = buf;
    cp = RSTRING(str)->ptr;

    while (beg >= 0) {
	n++;
	match = rb_backref_get();
	regs = RMATCH(match)->regs;
	if (iter) {
	    rb_match_busy(match, Qtrue);
	    val = rb_obj_as_string(rb_yield(rb_reg_nth_match(0, match)));
	    rb_match_busy(match, Qfalse);
	    rb_backref_set(match);
	}
	else {
	    val = rb_reg_regsub(repl, str, regs);
	}
	len = (bp - buf) + (beg - offset) + RSTRING(val)->len + 3;
	if (blen < len) {
	    while (blen < len) blen *= 2;
	    len = bp - buf;
	    REALLOC_N(buf, char, blen);
	    bp = buf + len;
	}
	len = beg - offset;	/* copy pre-match substr */
	memcpy(bp, cp, len);
	bp += len;
	memcpy(bp, RSTRING(val)->ptr, RSTRING(val)->len);
	bp += RSTRING(val)->len;
	if (BEG(0) == END(0)) {
	    /*
	     * Always consume at least one character of the input string
	     * in order to prevent infinite loops.
	     */
	    len = mbclen(RSTRING(str)->ptr[END(0)]);
	    if (RSTRING(str)->len > END(0)) {
		memcpy(bp, RSTRING(str)->ptr+END(0), len);
		bp += len;
	    }
	    offset = END(0) + len;
	}
	else {
	    offset = END(0);
	}
	cp = RSTRING(str)->ptr + offset;
	if (offset > RSTRING(str)->len) break;
	beg = rb_reg_search(pat, str, offset, 0);
    }
    if (RSTRING(str)->len > offset) {
	len = bp - buf;
	if (blen - len < RSTRING(str)->len - offset + 1) {
	    REALLOC_N(buf, char, len + RSTRING(str)->len - offset + 1);
	    bp = buf + len;
	}
	memcpy(bp, cp, RSTRING(str)->len - offset);
	bp += RSTRING(str)->len - offset;
    }
    rb_str_modify(str);
    free(RSTRING(str)->ptr);
    RSTRING(str)->ptr = buf;
    RSTRING(str)->len = len = bp - buf;
    RSTRING(str)->ptr[len] = '\0';

    return str;
}

static VALUE
rb_str_gsub(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE val = rb_str_gsub_bang(argc, argv, str = rb_str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_str_replace_method(str, str2)
    VALUE str, str2;
{
    if (TYPE(str2) != T_STRING) str2 = rb_str_to_str(str2);
    rb_str_modify(str);
    rb_str_resize(str, RSTRING(str2)->len);
    memcpy(RSTRING(str)->ptr, RSTRING(str2)->ptr, RSTRING(str2)->len);
    if (OBJ_TAINTED(str2)) OBJ_TAINT(str);

    return str;
}

static VALUE
uscore_get()
{
    VALUE line;

    line = rb_lastline_get();
    if (TYPE(line) != T_STRING) {
	rb_raise(rb_eTypeError, "$_ value need to be String (%s given)",
		 NIL_P(line)?"nil":rb_class2name(CLASS_OF(line)));
    }
    return line;
}

static VALUE
rb_f_sub_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_sub_bang(argc, argv, uscore_get());
}

static VALUE
rb_f_sub(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line, v;

    line = rb_str_dup(uscore_get());
    v = rb_str_sub_bang(argc, argv, line);
    if (NIL_P(v)) return line;
    rb_lastline_set(v);
    return v;
}

static VALUE
rb_f_gsub_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_gsub_bang(argc, argv, uscore_get());
}

static VALUE
rb_f_gsub(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line, v;

    line = rb_str_dup(uscore_get());
    v = rb_str_gsub_bang(argc, argv, line);
    if (NIL_P(v)) return line;
    rb_lastline_set(v);
    return v;
}

static VALUE
rb_str_reverse_bang(str)
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
rb_str_reverse(str)
    VALUE str;
{
    VALUE obj;
    char *s, *e, *p;

    if (RSTRING(str)->len <= 1) return str;

    obj = rb_str_new(0, RSTRING(str)->len);
    s = RSTRING(str)->ptr; e = s + RSTRING(str)->len - 1;
    p = RSTRING(obj)->ptr;

    while (e >= s) {
	*p++ = *e--;
    }

    return obj;
}

static VALUE
rb_str_include(str, arg)
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
	return Qfalse;
    }

    if (TYPE(arg) != T_STRING) arg = rb_str_to_str(arg);
    i = rb_str_index(str, arg, 0);

    if (i == -1) return Qfalse;
    return INT2FIX(i);
}

static VALUE
rb_str_to_i(str)
    VALUE str;
{
    return rb_str2inum(RSTRING(str)->ptr, 10);
}

static VALUE
rb_str_to_f(str)
    VALUE str;
{
    double f = strtod(RSTRING(str)->ptr, 0);

    return rb_float_new(f);
}

static VALUE
rb_str_to_s(str)
    VALUE str;
{
    return str;
}

VALUE
rb_str_inspect(str)
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
	    int len = mbclen(c);

	    CHECK(len);
	    *b++ = c;
	    while (--len) {
		*b++ = *p++;
	    }
	}
	else if ((c & 0x80) && rb_kcode() != MBCTYPE_EUC) {
	    CHECK(1);
	    *b++ = c;
	}
	else if (c == '"'|| c == '\\') {
	    CHECK(2);
	    *b++ = '\\';
	    *b++ = c;
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
    return rb_str_new(buf, b - buf);
}

static VALUE
rb_str_dump(str)
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
	  case '"':  case '\\':
	  case '\n': case '\r':
	  case '\t': case '\f': case '#':
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

    result = rb_str_new(0, len);
    p = RSTRING(str)->ptr; pend = p + RSTRING(str)->len;
    q = RSTRING(result)->ptr; qend = q + len;

    *q++ = '"';
    while (p < pend) {
	char c = *p++;

	if (c == '"' || c == '\\') {
	    *q++ = '\\';
	    *q++ = c;
	}
	else if (c == '#') {
	    *q++ = '\\';
	    *q++ = '#';
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
	else if (c == '\013') {
	    *q++ = '\\';
	    *q++ = 'v';
	}
	else if (c == '\007') {
	    *q++ = '\\';
	    *q++ = 'a';
	}
	else if (c == '\033') {
	    *q++ = '\\';
	    *q++ = 'e';
	}
	else {
	    *q++ = '\\';
	    sprintf(q, "%03o", c&0xff);
	    q += 3;
	}
    }
    *q++ = '"';

    return result;
}

static VALUE
rb_str_upcase_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    rb_str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    while (s < send) {
	if (ismbchar(*s)) {
	    s+=mbclen(*s) - 1;
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
rb_str_upcase(str)
    VALUE str;
{
    VALUE val = rb_str_upcase_bang(str = rb_str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_str_downcase_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    rb_str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    while (s < send) {
	if (ismbchar(*s)) {
	    s+=mbclen(*s) - 1;
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
rb_str_downcase(str)
    VALUE str;
{
    VALUE val = rb_str_downcase_bang(str = rb_str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_str_capitalize_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    rb_str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    if (ISLOWER(*s)) {
	*s = toupper(*s);
	modify = 1;
    }
    while (++s < send) {
	if (ismbchar(*s)) {
	    s+=mbclen(*s) - 1;
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
rb_str_capitalize(str)
    VALUE str;
{
    VALUE val = rb_str_capitalize_bang(str = rb_str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_str_swapcase_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    rb_str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    while (s < send) {
	if (ismbchar(*s)) {
	    s+=mbclen(*s) - 1;
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
rb_str_swapcase(str)
    VALUE str;
{
    VALUE val = rb_str_swapcase_bang(str = rb_str_dup(str));

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

static VALUE rb_str_delete_bang _((VALUE,VALUE));

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

    rb_str_modify(str);
    if (TYPE(src) != T_STRING) src = rb_str_to_str(src);
    trsrc.p = RSTRING(src)->ptr; trsrc.pend = trsrc.p + RSTRING(src)->len;
    if (RSTRING(src)->len > 2 && RSTRING(src)->ptr[0] == '^') {
	cflag++;
	trsrc.p++;
    }
    if (TYPE(repl) != T_STRING) repl = rb_str_to_str(repl);
    if (RSTRING(repl)->len == 0) return rb_str_delete_bang(str, src);
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
rb_str_tr_bang(str, src, repl)
    VALUE str, src, repl;
{
    return tr_trans(str, src, repl, 0);
}

static VALUE
rb_str_tr(str, src, repl)
    VALUE str, src, repl;
{
    VALUE val = tr_trans(str = rb_str_dup(str), src, repl, 0);

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
rb_str_delete_bang(str1, str2)
    VALUE str1, str2;
{
    char *s, *send, *t;
    char squeez[256];
    int modify = 0;

    if (TYPE(str2) != T_STRING) str2 = rb_str_to_str(str2);
    tr_setup_table(str2, squeez);

    rb_str_modify(str1);

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
rb_str_delete(str1, str2)
    VALUE str1, str2;
{
    VALUE val = rb_str_delete_bang(str1 = rb_str_dup(str1), str2);

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

    rb_str_modify(str1);

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
rb_str_squeeze_bang(argc, argv, str1)
    int argc;
    VALUE *argv;
    VALUE str1;
{
    VALUE str2;

    if (rb_scan_args(argc, argv, "01", &str2) == 1 && TYPE(str2) != T_STRING) {
	str2 = rb_str_to_str(str2);
    }
    return tr_squeeze(str1, str2);
}

static VALUE
rb_str_squeeze(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE val = rb_str_squeeze_bang(argc, argv, str = rb_str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_str_tr_s_bang(str, src, repl)
    VALUE str, src, repl;
{
    return tr_trans(str, src, repl, 1);
}

static VALUE
rb_str_tr_s(str, src, repl)
    VALUE str, src, repl;
{
    VALUE val = tr_trans(str = rb_str_dup(str), src, repl, 1);

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_str_split_method(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE spat;
    VALUE limit;
    int char_sep = -1;
    int beg, end, i;
    int lim = 0;
    VALUE result, tmp;

    if (rb_scan_args(argc, argv, "02", &spat, &limit) == 2) {
	lim = NUM2INT(limit);
	if (lim <= 0) limit = Qnil;
	else if (lim == 1) return rb_ary_new3(1, str);
	i = 1;
    }

    if (argc == 0) {
	if (!NIL_P(rb_fs)) {
	    spat = rb_fs;
	    goto fs_set;
	}
	char_sep = ' ';
    }
    else {
	switch (TYPE(spat)) {
	  case T_STRING:
	  fs_set:
	    if (RSTRING(spat)->len == 1) {
		char_sep = (unsigned char)RSTRING(spat)->ptr[0];
	    }
	    else {
		spat = rb_reg_regcomp(spat);
	    }
	    break;
	  case T_REGEXP:
	    break;
	  default:
	    rb_raise(rb_eArgError, "bad separator");
	}
    }

    result = rb_ary_new();
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
			rb_ary_push(result, rb_str_substr(str, beg, end-beg));
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
		    rb_ary_push(result, rb_str_substr(str, beg, end-beg));
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

	while ((end = rb_reg_search(spat, str, start, 0)) >= 0) {
	    regs = RMATCH(rb_backref_get())->regs;
	    if (start == end && BEG(0) == END(0)) {
		if (last_null == 1) {
		    rb_ary_push(result, rb_str_substr(str, beg, mbclen(RSTRING(str)->ptr[beg])));
		    beg = start;
		}
		else {
		    start += mbclen(RSTRING(str)->ptr[start]);
		    last_null = 1;
		    continue;
		}
	    }
	    else {
		rb_ary_push(result, rb_str_substr(str, beg, end-beg));
		beg = start = END(0);
	    }
	    last_null = 0;

	    for (idx=1; idx < regs->num_regs; idx++) {
		if (BEG(idx) == -1) continue;
		if (BEG(idx) == END(idx))
		    tmp = rb_str_new(0, 0);
		else
		    tmp = rb_str_substr(str, BEG(idx), END(idx)-BEG(idx));
		rb_ary_push(result, tmp);
	    }
	    if (!NIL_P(limit) && lim <= ++i) break;
	}
    }
    if (!NIL_P(limit) || RSTRING(str)->len > beg || lim < 0) {
	rb_ary_push(result, rb_str_substr(str, beg, RSTRING(str)->len-beg));
    }
    if (NIL_P(limit) && lim == 0) {
	while (RARRAY(result)->len > 0 &&
	       RSTRING(RARRAY(result)->ptr[RARRAY(result)->len-1])->len == 0)
	    rb_ary_pop(result);
    }

    return result;
}

VALUE
rb_str_split(str, sep0)
    VALUE str;
    const char *sep0;
{
    VALUE sep;

    if (TYPE(str) != T_STRING) str = rb_str_to_str(str);
    sep = rb_str_new2(sep0);
    return rb_str_split_method(1, &sep, str);
}

static VALUE
rb_f_split(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_split_method(argc, argv, uscore_get());
}

static VALUE
rb_str_each_line(argc, argv, str)
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
	rs = rb_rs;
    }

    if (NIL_P(rs)) {
	rb_yield(str);
	return Qnil;
    }
    if (TYPE(rs) != T_STRING) rs = rb_str_to_str(rs);

    rslen = RSTRING(rs)->len;
    if (rslen == 0) {
	newline = '\n';
    }
    else {
	newline = RSTRING(rs)->ptr[rslen-1];
    }

    for (s = p, p += rslen; p < pend; p++) {
	if (rslen == 0 && *p == '\n') {
	    if (p[1] != '\n') continue;
	    while (*p == '\n') p++;
	}
	if (p[-1] == newline &&
	    (rslen <= 1 ||
	     memcmp(RSTRING(rs)->ptr, p-rslen, rslen) == 0)) {
	    line = rb_str_new(s, p - s);
	    rb_yield(line);
	    if (RSTRING(str)->ptr != ptr || RSTRING(str)->len != len)
		rb_raise(rb_eArgError, "string modified");
	    s = p;
	}
    }

    if (s != pend) {
	line = rb_str_new(s, p - s);
	rb_yield(line);
    }

    return Qnil;
}

static VALUE
rb_str_each_byte(str)
    struct RString* str;
{
    int i;

    for (i=0; i<RSTRING(str)->len; i++) {
	rb_yield(INT2FIX(RSTRING(str)->ptr[i] & 0xff));
    }
    return Qnil;
}

static VALUE
rb_str_chop_bang(str)
    VALUE str;
{
    if (RSTRING(str)->len > 0) {
	rb_str_modify(str);
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
rb_str_chop(str)
    VALUE str;
{
    VALUE val = rb_str_chop_bang(str = rb_str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_f_chop_bang(str)
    VALUE str;
{
    return rb_str_chop_bang(uscore_get());
}

static VALUE
rb_f_chop()
{
    VALUE str = rb_str_dup(uscore_get());
    VALUE val = rb_str_chop_bang(str);

    if (NIL_P(str)) return str;
    rb_lastline_set(val);
    return val;
}

static VALUE
rb_str_chomp_bang(argc, argv, str)
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
	rs = rb_rs;
    }
    if (NIL_P(rs)) return Qnil;

    if (TYPE(rs) != T_STRING) rs = rb_str_to_str(rs);
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
rb_str_chomp(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE val = rb_str_chomp_bang(argc, argv, str = rb_str_dup(str));

    if (NIL_P(val)) return str;
    return val;
}

static VALUE
rb_f_chomp_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_chomp_bang(argc, argv, uscore_get());
}

static VALUE
rb_f_chomp(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str = rb_str_dup(uscore_get());
    VALUE val = rb_str_chomp_bang(argc, argv, str);
    return val;
}

static VALUE
rb_str_strip_bang(str)
    VALUE str;
{
    char *s, *t, *e;

    rb_str_modify(str);
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
rb_str_strip(str)
    VALUE str;
{
    VALUE val = rb_str_strip_bang(str = rb_str_dup(str));

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

    if (rb_reg_search(pat, str, *start, 0) >= 0) {
	match = rb_backref_get();
	regs = RMATCH(match)->regs;
	if (BEG(0) == END(0)) {
	    /*
	     * Always consume at least one character of the input string
	     */
	    *start = END(0)+mbclen(RSTRING(str)->ptr[END(0)]);
	}
	else {
	    *start = END(0);
	}
	if (regs->num_regs == 1) {
	    return rb_reg_nth_match(0, match);
	}
	result = rb_ary_new2(regs->num_regs);
	for (i=1; i < regs->num_regs; i++) {
	    rb_ary_push(result, rb_reg_nth_match(i, match));
	}

	return result;
    }
    return Qnil;
}

static VALUE
rb_str_scan(str, pat)
    VALUE str, pat;
{
    VALUE result;
    int start = 0;

    pat = get_pat(pat);
    if (!rb_iterator_p()) {
	VALUE ary = rb_ary_new();

	while (!NIL_P(result = scan_once(str, pat, &start))) {
	    rb_ary_push(ary, result);
	}
	return ary;
    }

    while (!NIL_P(result = scan_once(str, pat, &start))) {
	rb_yield(result);
    }
    return Qnil;
}

static VALUE
rb_str_hex(str)
    VALUE str;
{
    return rb_str2inum(RSTRING(str)->ptr, 16);
}

static VALUE
rb_str_oct(str)
    VALUE str;
{
    int base = 8;

    if (RSTRING(str)->len > 2 && RSTRING(str)->ptr[0] == '0' &&
	(RSTRING(str)->ptr[1] == 'x' || RSTRING(str)->ptr[1] == 'X')) {
	base = 16;
    }
    return rb_str2inum(RSTRING(str)->ptr, base);
}

static VALUE
rb_str_crypt(str, salt)
    VALUE str, salt;
{
    extern char *crypt();

    if (TYPE(salt) != T_STRING) salt = rb_str_to_str(salt);
    if (RSTRING(salt)->len < 2)
	rb_raise(rb_eArgError, "salt too short(need >2 bytes)");
    return rb_str_new2(crypt(RSTRING(str)->ptr, RSTRING(salt)->ptr));
}

static VALUE
rb_str_intern(str)
    VALUE str;
{
    ID id;

    if (strlen(RSTRING(str)->ptr) != RSTRING(str)->len)
	rb_raise(rb_eArgError, "string contains `\\0'");
    id = rb_intern(RSTRING(str)->ptr);
    return INT2FIX(id);
}

static VALUE
rb_str_sum(argc, argv, str)
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
	return rb_int2inum(res);
    }
}

static VALUE
rb_str_ljust(str, w)
    VALUE str;
    VALUE w;
{
    int width = NUM2INT(w);
    VALUE res;
    char *p, *pend;

    if (width < 0 || RSTRING(str)->len >= width) return str;
    res = rb_str_new(0, width);
    memcpy(RSTRING(res)->ptr, RSTRING(str)->ptr, RSTRING(str)->len);
    p = RSTRING(res)->ptr + RSTRING(str)->len; pend = RSTRING(res)->ptr + width;
    while (p < pend) {
	*p++ = ' ';
    }
    return res;
}

static VALUE
rb_str_rjust(str, w)
    VALUE str;
    VALUE w;
{
    int width = NUM2INT(w);
    VALUE res;
    char *p, *pend;

    if (width < 0 || RSTRING(str)->len >= width) return str;
    res = rb_str_new(0, width);
    p = RSTRING(res)->ptr; pend = p + width - RSTRING(str)->len;
    while (p < pend) {
	*p++ = ' ';
    }
    memcpy(pend, RSTRING(str)->ptr, RSTRING(str)->len);
    return res;
}

static VALUE
rb_str_center(str, w)
    VALUE str;
    VALUE w;
{
    int width = NUM2INT(w);
    VALUE res;
    char *p, *pend;
    int n;

    if (width < 0 || RSTRING(str)->len >= width) return str;
    res = rb_str_new(0, width);
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
    rb_cString  = rb_define_class("String", rb_cObject);
    rb_include_module(rb_cString, rb_mComparable);
    rb_include_module(rb_cString, rb_mEnumerable);
    rb_define_singleton_method(rb_cString, "new", rb_str_s_new, 1);
    rb_define_method(rb_cString, "clone", rb_str_clone, 0);
    rb_define_method(rb_cString, "dup", rb_str_dup, 0);
    rb_define_method(rb_cString, "<=>", rb_str_cmp_method, 1);
    rb_define_method(rb_cString, "==", rb_str_equal, 1);
    rb_define_method(rb_cString, "===", rb_str_equal, 1);
    rb_define_method(rb_cString, "eql?", rb_str_equal, 1);
    rb_define_method(rb_cString, "hash", rb_str_hash_method, 0);
    rb_define_method(rb_cString, "+", rb_str_plus, 1);
    rb_define_method(rb_cString, "*", rb_str_times, 1);
    rb_define_method(rb_cString, "%", rb_str_format, 1);
    rb_define_method(rb_cString, "[]", rb_str_aref_method, -1);
    rb_define_method(rb_cString, "[]=", rb_str_aset_method, -1);
    rb_define_method(rb_cString, "length", rb_str_length, 0);
    rb_define_alias(rb_cString,  "size", "length");
    rb_define_method(rb_cString, "empty?", rb_str_empty, 0);
    rb_define_method(rb_cString, "=~", rb_str_match, 1);
    rb_define_method(rb_cString, "~", rb_str_match2, 0);
    rb_define_method(rb_cString, "succ", rb_str_succ, 0);
    rb_define_method(rb_cString, "succ!", rb_str_succ_bang, 0);
    rb_define_method(rb_cString, "next", rb_str_succ, 0);
    rb_define_method(rb_cString, "next!", rb_str_succ_bang, 0);
    rb_define_method(rb_cString, "upto", rb_str_upto_method, 1);
    rb_define_method(rb_cString, "index", rb_str_index_method, -1);
    rb_define_method(rb_cString, "rindex", rb_str_rindex, -1);
    rb_define_method(rb_cString, "replace", rb_str_replace_method, 1);

    rb_define_method(rb_cString, "freeze", rb_str_freeze, 0);
    rb_define_method(rb_cString, "frozen?", rb_str_frozen_p, 0);

    rb_define_method(rb_cString, "to_i", rb_str_to_i, 0);
    rb_define_method(rb_cString, "to_f", rb_str_to_f, 0);
    rb_define_method(rb_cString, "to_s", rb_str_to_s, 0);
    rb_define_method(rb_cString, "to_str", rb_str_to_s, 0);
    rb_define_method(rb_cString, "inspect", rb_str_inspect, 0);
    rb_define_method(rb_cString, "dump", rb_str_dump, 0);

    rb_define_method(rb_cString, "upcase", rb_str_upcase, 0);
    rb_define_method(rb_cString, "downcase", rb_str_downcase, 0);
    rb_define_method(rb_cString, "capitalize", rb_str_capitalize, 0);
    rb_define_method(rb_cString, "swapcase", rb_str_swapcase, 0);

    rb_define_method(rb_cString, "upcase!", rb_str_upcase_bang, 0);
    rb_define_method(rb_cString, "downcase!", rb_str_downcase_bang, 0);
    rb_define_method(rb_cString, "capitalize!", rb_str_capitalize_bang, 0);
    rb_define_method(rb_cString, "swapcase!", rb_str_swapcase_bang, 0);

    rb_define_method(rb_cString, "hex", rb_str_hex, 0);
    rb_define_method(rb_cString, "oct", rb_str_oct, 0);
    rb_define_method(rb_cString, "split", rb_str_split_method, -1);
    rb_define_method(rb_cString, "reverse", rb_str_reverse, 0);
    rb_define_method(rb_cString, "reverse!", rb_str_reverse_bang, 0);
    rb_define_method(rb_cString, "concat", rb_str_concat, 1);
    rb_define_method(rb_cString, "<<", rb_str_concat, 1);
    rb_define_method(rb_cString, "crypt", rb_str_crypt, 1);
    rb_define_method(rb_cString, "intern", rb_str_intern, 0);

    rb_define_method(rb_cString, "include?", rb_str_include, 1);

    rb_define_method(rb_cString, "scan", rb_str_scan, 1);

    rb_define_method(rb_cString, "ljust", rb_str_ljust, 1);
    rb_define_method(rb_cString, "rjust", rb_str_rjust, 1);
    rb_define_method(rb_cString, "center", rb_str_center, 1);

    rb_define_method(rb_cString, "sub", rb_str_sub, -1);
    rb_define_method(rb_cString, "gsub", rb_str_gsub, -1);
    rb_define_method(rb_cString, "chop", rb_str_chop, 0);
    rb_define_method(rb_cString, "chomp", rb_str_chomp, -1);
    rb_define_method(rb_cString, "strip", rb_str_strip, 0);

    rb_define_method(rb_cString, "sub!", rb_str_sub_bang, -1);
    rb_define_method(rb_cString, "gsub!", rb_str_gsub_bang, -1);
    rb_define_method(rb_cString, "strip!", rb_str_strip_bang, 0);
    rb_define_method(rb_cString, "chop!", rb_str_chop_bang, 0);
    rb_define_method(rb_cString, "chomp!", rb_str_chomp_bang, -1);

    rb_define_method(rb_cString, "tr", rb_str_tr, 2);
    rb_define_method(rb_cString, "tr_s", rb_str_tr_s, 2);
    rb_define_method(rb_cString, "delete", rb_str_delete, 1);
    rb_define_method(rb_cString, "squeeze", rb_str_squeeze, -1);

    rb_define_method(rb_cString, "tr!", rb_str_tr_bang, 2);
    rb_define_method(rb_cString, "tr_s!", rb_str_tr_s_bang, 2);
    rb_define_method(rb_cString, "delete!", rb_str_delete_bang, 1);
    rb_define_method(rb_cString, "squeeze!", rb_str_squeeze_bang, -1);

    rb_define_method(rb_cString, "each_line", rb_str_each_line, -1);
    rb_define_method(rb_cString, "each", rb_str_each_line, -1);
    rb_define_method(rb_cString, "each_byte", rb_str_each_byte, 0);

    rb_define_method(rb_cString, "sum", rb_str_sum, -1);

    rb_define_global_function("sub", rb_f_sub, -1);
    rb_define_global_function("gsub", rb_f_gsub, -1);

    rb_define_global_function("sub!", rb_f_sub_bang, -1);
    rb_define_global_function("gsub!", rb_f_gsub_bang, -1);

    rb_define_global_function("chop", rb_f_chop, 0);
    rb_define_global_function("chop!", rb_f_chop_bang, 0);

    rb_define_global_function("chomp", rb_f_chomp, -1);
    rb_define_global_function("chomp!", rb_f_chomp_bang, -1);

    rb_define_global_function("split", rb_f_split, -1);

    to_str = rb_intern("to_s");
}
