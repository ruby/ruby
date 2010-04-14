/**********************************************************************

  string.c -

  $Author$
  $Date$
  created at: Mon Aug  9 17:12:58 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "re.h"

#define BEG(no) regs->beg[no]
#define END(no) regs->end[no]

#include <math.h>
#include <ctype.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

VALUE rb_cString;

#define STR_TMPLOCK FL_USER1
#define STR_ASSOC   FL_USER3
#define STR_NOCAPA  (ELTS_SHARED|STR_ASSOC)

#define RESIZE_CAPA(str,capacity) do {\
    REALLOC_N(RSTRING(str)->ptr, char, (capacity)+1);\
    if (!FL_TEST(str, STR_NOCAPA))\
        RSTRING(str)->aux.capa = (capacity);\
} while (0)

VALUE rb_fs;

static inline void
str_mod_check(s, p, len)
    VALUE s;
    char *p;
    long len;
{
    if (RSTRING(s)->ptr != p || RSTRING(s)->len != len) {
	rb_raise(rb_eRuntimeError, "string modified");
    }
}

static inline void
str_frozen_check(s)
    VALUE s;
{
    if (OBJ_FROZEN(s)) {
	rb_raise(rb_eRuntimeError, "string frozen");
    }
}

static VALUE str_alloc _((VALUE));
static VALUE
str_alloc(klass)
    VALUE klass;
{
    NEWOBJ(str, struct RString);
    OBJSETUP(str, klass, T_STRING);

    str->ptr = 0;
    str->len = 0;
    str->aux.capa = 0;

    return (VALUE)str;
}

static VALUE
str_new(klass, ptr, len)
    VALUE klass;
    const char *ptr;
    long len;
{
    VALUE str;

    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }

    str = str_alloc(klass);
    RSTRING(str)->len = len;
    RSTRING(str)->aux.capa = len;
    RSTRING(str)->ptr = ALLOC_N(char,len+1);
    if (ptr) {
	memcpy(RSTRING(str)->ptr, ptr, len);
    }
    RSTRING(str)->ptr[len] = '\0';
    return str;
}

VALUE
rb_str_new(ptr, len)
    const char *ptr;
    long len;
{
    return str_new(rb_cString, ptr, len);
}

VALUE
rb_str_new2(ptr)
    const char *ptr;
{
    if (!ptr) {
	rb_raise(rb_eArgError, "NULL pointer given");
    }
    return rb_str_new(ptr, strlen(ptr));
}

VALUE
rb_tainted_str_new(ptr, len)
    const char *ptr;
    long len;
{
    VALUE str = rb_str_new(ptr, len);

    OBJ_TAINT(str);
    return str;
}

VALUE
rb_tainted_str_new2(ptr)
    const char *ptr;
{
    VALUE str = rb_str_new2(ptr);

    OBJ_TAINT(str);
    return str;
}

static VALUE
str_new3(klass, str)
    VALUE klass, str;
{
    VALUE str2 = str_alloc(klass);

    RSTRING(str2)->len = RSTRING(str)->len;
    RSTRING(str2)->ptr = RSTRING(str)->ptr;
    RSTRING(str2)->aux.shared = str;
    FL_SET(str2, ELTS_SHARED);

    return str2;
}

VALUE
rb_str_new3(str)
    VALUE str;
{
    VALUE str2 = str_new3(rb_obj_class(str), str);

    OBJ_INFECT(str2, str);
    return str2;
}

static VALUE
str_new4(klass, str)
    VALUE klass, str;
{
    VALUE str2 = str_alloc(klass);

    RSTRING(str2)->len = RSTRING(str)->len;
    RSTRING(str2)->ptr = RSTRING(str)->ptr;
    if (FL_TEST(str, ELTS_SHARED)) {
	FL_SET(str2, ELTS_SHARED);
	RSTRING(str2)->aux.shared = RSTRING(str)->aux.shared;
    }
    else {
	FL_SET(str, ELTS_SHARED);
	RSTRING(str)->aux.shared = str2;
    }

    return str2;
}

VALUE
rb_str_new4(orig)
    VALUE orig;
{
    VALUE klass, str;

    if (OBJ_FROZEN(orig)) return orig;
    klass = rb_obj_class(orig);
    if (FL_TEST(orig, ELTS_SHARED) && (str = RSTRING(orig)->aux.shared) && klass == RBASIC(str)->klass) {
	long ofs;
	ofs = RSTRING(str)->len - RSTRING(orig)->len;
	if ((ofs > 0) || (!OBJ_TAINTED(str) && OBJ_TAINTED(orig))) {
	    str = str_new3(klass, str);
	    RSTRING(str)->ptr += ofs;
	    RSTRING(str)->len -= ofs;
	}
    }
    else if (FL_TEST(orig, STR_ASSOC)) {
	str = str_new(klass, RSTRING(orig)->ptr, RSTRING(orig)->len);
    }
    else {
	str = str_new4(klass, orig);
    }
    OBJ_INFECT(str, orig);
    OBJ_FREEZE(str);
    return str;
}

VALUE
rb_str_new5(obj, ptr, len)
    VALUE obj;
    const char *ptr;
    long len;
{
    return str_new(rb_obj_class(obj), ptr, len);
}

#define STR_BUF_MIN_SIZE 128

VALUE
rb_str_buf_new(capa)
    long capa;
{
    VALUE str = str_alloc(rb_cString);

    if (capa < STR_BUF_MIN_SIZE) {
	capa = STR_BUF_MIN_SIZE;
    }
    RSTRING(str)->ptr = 0;
    RSTRING(str)->len = 0;
    RSTRING(str)->aux.capa = capa;
    RSTRING(str)->ptr = ALLOC_N(char, capa+1);
    RSTRING(str)->ptr[0] = '\0';

    return str;
}

VALUE
rb_str_buf_new2(ptr)
    const char *ptr;
{
    VALUE str;
    long len = strlen(ptr);

    str = rb_str_buf_new(len);
    rb_str_buf_cat(str, ptr, len);

    return str;
}

VALUE
rb_str_tmp_new(len)
    long len;
{
    return str_new(0, 0, len);
}

VALUE
rb_str_to_str(str)
    VALUE str;
{
    return rb_convert_type(str, T_STRING, "String", "to_str");
}

static inline void str_discard _((VALUE str));

static void
rb_str_shared_replace(str, str2)
    VALUE str, str2;
{
    if (str == str2) return;
    str_discard(str);
    if (NIL_P(str2)) {
	RSTRING(str)->ptr = 0;
	RSTRING(str)->len = 0;
	RSTRING(str)->aux.capa = 0;
	FL_UNSET(str, STR_NOCAPA);
	return;
    }
    RSTRING(str)->ptr = RSTRING(str2)->ptr;
    RSTRING(str)->len = RSTRING(str2)->len;
    FL_UNSET(str, STR_NOCAPA);
    if (FL_TEST(str2, STR_NOCAPA)) {
	FL_SET(str, RBASIC(str2)->flags & STR_NOCAPA);
	RSTRING(str)->aux.shared = RSTRING(str2)->aux.shared;
    }
    else {
	RSTRING(str)->aux.capa = RSTRING(str2)->aux.capa;
    }
    RSTRING(str2)->ptr = 0;	/* abandon str2 */
    RSTRING(str2)->len = 0;
    RSTRING(str2)->aux.capa = 0;
    FL_UNSET(str2, STR_NOCAPA);
    if (OBJ_TAINTED(str2)) OBJ_TAINT(str);
}

static ID id_to_s;

VALUE
rb_obj_as_string(obj)
    VALUE obj;
{
    VALUE str;

    if (TYPE(obj) == T_STRING) {
	return obj;
    }
    str = rb_funcall(obj, id_to_s, 0);
    if (TYPE(str) != T_STRING)
	return rb_any_to_s(obj);
    if (OBJ_TAINTED(obj)) OBJ_TAINT(str);
    return str;
}

static VALUE rb_str_s_alloc _((VALUE));
static VALUE rb_str_replace _((VALUE, VALUE));

VALUE
rb_str_dup(str)
    VALUE str;
{
    VALUE dup = str_alloc(rb_obj_class(str));
    rb_str_replace(dup, str);
    return dup;
}


/*
 *  call-seq:
 *     String.new(str="")   => new_str
 *
 *  Returns a new string object containing a copy of <i>str</i>.
 */

static VALUE
rb_str_init(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE orig;

    if (rb_scan_args(argc, argv, "01", &orig) == 1)
	rb_str_replace(str, orig);
    return str;
}

static VALUE rb_str_length _((VALUE));

/*
 *  call-seq:
 *     str.length   => integer
 *
 *  Returns the length of <i>str</i>.
 */

static VALUE
rb_str_length(str)
    VALUE str;
{
    return LONG2NUM(RSTRING(str)->len);
}

static VALUE rb_str_empty _((VALUE));

/*
 *  call-seq:
 *     str.empty?   => true or false
 *
 *  Returns <code>true</code> if <i>str</i> has a length of zero.
 *
 *     "hello".empty?   #=> false
 *     "".empty?        #=> true
 */

static VALUE
rb_str_empty(str)
    VALUE str;
{
    if (RSTRING(str)->len == 0)
	return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     str + other_str   => new_str
 *
 *  Concatenation---Returns a new <code>String</code> containing
 *  <i>other_str</i> concatenated to <i>str</i>.
 *
 *     "Hello from " + self.to_s   #=> "Hello from main"
 */

VALUE
rb_str_plus(str1, str2)
    VALUE str1, str2;
{
    VALUE str3;

    StringValue(str2);
    str3 = rb_str_new(0, RSTRING(str1)->len+RSTRING(str2)->len);
    memcpy(RSTRING(str3)->ptr, RSTRING(str1)->ptr, RSTRING(str1)->len);
    memcpy(RSTRING(str3)->ptr + RSTRING(str1)->len,
	   RSTRING(str2)->ptr, RSTRING(str2)->len);
    RSTRING(str3)->ptr[RSTRING(str3)->len] = '\0';

    if (OBJ_TAINTED(str1) || OBJ_TAINTED(str2))
	OBJ_TAINT(str3);
    return str3;
}

/*
 *  call-seq:
 *     str * integer   => new_str
 *
 *  Copy---Returns a new <code>String</code> containing <i>integer</i> copies of
 *  the receiver.
 *
 *     "Ho! " * 3   #=> "Ho! Ho! Ho! "
 */

VALUE
rb_str_times(str, times)
    VALUE str;
    VALUE times;
{
    VALUE str2;
    long n, len;
    char *ptr2;

    len = NUM2LONG(times);
    if (len < 0) {
	rb_raise(rb_eArgError, "negative argument");
    }
    if (len && LONG_MAX/len <  RSTRING(str)->len) {
	rb_raise(rb_eArgError, "argument too big");
    }

    str2 = rb_str_new5(str,0, len *= RSTRING(str)->len);
    ptr2 = RSTRING_PTR(str2);
    if (len) {
        n = RSTRING_LEN(str);
        memcpy(ptr2, RSTRING_PTR(str), n);
        while (n <= len/2) {
            memcpy(ptr2 + n, ptr2, n);
            n *= 2;
        }
        memcpy(ptr2 + n, ptr2, len-n);
    }
    ptr2[RSTRING_LEN(str2)] = '\0';
    OBJ_INFECT(str2, str);

    return str2;
}

/*
 *  call-seq:
 *     str % arg   => new_str
 *
 *  Format---Uses <i>str</i> as a format specification, and returns the result
 *  of applying it to <i>arg</i>. If the format specification contains more than
 *  one substitution, then <i>arg</i> must be an <code>Array</code> containing
 *  the values to be substituted. See <code>Kernel::sprintf</code> for details
 *  of the format string.
 *
 *     "%05d" % 123                       #=> "00123"
 *     "%-5s: %08x" % [ "ID", self.id ]   #=> "ID   : 200e14d6"
 */

static VALUE
rb_str_format_m(str, arg)
    VALUE str, arg;
{
    volatile VALUE tmp = rb_check_array_type(arg);

    if (!NIL_P(tmp)) {
	return rb_str_format(RARRAY_LEN(tmp), RARRAY_PTR(tmp), str);
    }
    return rb_str_format(1, &arg, str);
}

static const char null_str[] = "";

static int
str_independent(str)
    VALUE str;
{
    if (FL_TEST(str, STR_TMPLOCK)) {
	rb_raise(rb_eRuntimeError, "can't modify string; temporarily locked");
    }
    if (OBJ_FROZEN(str)) rb_error_frozen("string");
    if (!OBJ_TAINTED(str) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't modify string");
    if (RSTRING(str)->ptr == null_str) return 0;
    if (!FL_TEST(str, ELTS_SHARED)) return 1;
    return 0;
}

static void
str_make_independent(str)
    VALUE str;
{
    char *ptr;

    ptr = ALLOC_N(char, RSTRING(str)->len+1);
    if (RSTRING(str)->ptr) {
	memcpy(ptr, RSTRING(str)->ptr, RSTRING(str)->len);
    }
    ptr[RSTRING(str)->len] = 0;
    RSTRING(str)->ptr = ptr;
    RSTRING(str)->aux.capa = RSTRING(str)->len;
    FL_UNSET(str, STR_NOCAPA);
}

void
rb_str_modify(str)
    VALUE str;
{
    if (!str_independent(str))
	str_make_independent(str);
}

static inline void
str_discard(str)
    VALUE str;
{
    if (str_independent(str)) {
	xfree(RSTRING_PTR(str));
	RSTRING(str)->ptr = 0;
	RSTRING(str)->len = 0;
    }
}

void
rb_str_associate(str, add)
    VALUE str, add;
{
    if (FL_TEST(str, STR_ASSOC)) {
	/* already associated */
	rb_ary_concat(RSTRING(str)->aux.shared, add);
    }
    else {
	if (FL_TEST(str, ELTS_SHARED)) {
	    str_make_independent(str);
	}
	else if (RSTRING(str)->aux.capa != RSTRING(str)->len) {
	    RESIZE_CAPA(str, RSTRING(str)->len);
	}
	RSTRING(str)->aux.shared = add;
	FL_SET(str, STR_ASSOC);
    }
}

VALUE
rb_str_associated(str)
    VALUE str;
{
    if (FL_TEST(str, STR_ASSOC)) {
	return RSTRING(str)->aux.shared;
    }
    return Qfalse;
}

#define make_null_str(s) do { \
	FL_SET(s, ELTS_SHARED); \
	RSTRING(s)->ptr = (char *)null_str; \
	RSTRING(s)->aux.shared = 0; \
    } while (0)

static VALUE
rb_str_s_alloc(klass)
    VALUE klass;
{
    VALUE str = str_alloc(klass);
    make_null_str(str);
    return str;
}

VALUE
rb_string_value(ptr)
    volatile VALUE *ptr;
{
    VALUE s = *ptr;
    if (TYPE(s) != T_STRING) {
	s = rb_str_to_str(s);
	*ptr = s;
    }
    if (!RSTRING(s)->ptr) {
	make_null_str(s);
    }
    return s;
}

char *
rb_string_value_ptr(ptr)
    volatile VALUE *ptr;
{
    return RSTRING(rb_string_value(ptr))->ptr;
}

char *
rb_string_value_cstr(ptr)
    volatile VALUE *ptr;
{
    VALUE str = rb_string_value(ptr);
    char *s = RSTRING(str)->ptr;
    long len = RSTRING(str)->len;

    if (!s || memchr(s, 0, len)) {
	rb_raise(rb_eArgError, "string contains null byte");
    }
    if (s[len]) rb_str_modify(str);
    return s;
}

VALUE
rb_check_string_type(str)
    VALUE str;
{
    str = rb_check_convert_type(str, T_STRING, "String", "to_str");
    if (!NIL_P(str) && !RSTRING(str)->ptr) {
	make_null_str(str);
    }
    return str;
}

/*
 *  call-seq:
 *     String.try_convert(obj) -> string or nil
 *
 *  Try to convert <i>obj</i> into a String, using to_str method.
 *  Returns converted regexp or nil if <i>obj</i> cannot be converted
 *  for any reason.
 *
 *     String.try_convert("str")     # => str
 *     String.try_convert(/re/)      # => nil
 */
static VALUE
rb_str_s_try_convert(dummy, str)
    VALUE dummy, str;
{
    return rb_check_string_type(str);
}

VALUE
rb_str_substr(str, beg, len)
    VALUE str;
    long beg, len;
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
    if (len == 0) {
	str2 = rb_str_new5(str,0,0);
    }
    else if (len > sizeof(struct RString)/2 &&
	beg + len == RSTRING(str)->len && !FL_TEST(str, STR_ASSOC)) {
	str2 = rb_str_new4(str);
	str2 = str_new3(rb_obj_class(str2), str2);
	RSTRING(str2)->ptr += RSTRING(str2)->len - len;
	RSTRING(str2)->len = len;
    }
    else {
	str2 = rb_str_new5(str, RSTRING(str)->ptr+beg, len);
    }
    OBJ_INFECT(str2, str);

    return str2;
}

VALUE
rb_str_freeze(str)
    VALUE str;
{
    return rb_obj_freeze(str);
}

VALUE
rb_str_dup_frozen(str)
    VALUE str;
{
    if (FL_TEST(str, ELTS_SHARED) && RSTRING(str)->aux.shared) {
	VALUE shared = RSTRING(str)->aux.shared;
	if (RSTRING(shared)->len == RSTRING(str)->len) {
	    OBJ_FREEZE(shared);
	    return shared;
	}
    }
    if (OBJ_FROZEN(str)) return str;
    str = rb_str_dup(str);
    OBJ_FREEZE(str);
    return str;
}

VALUE
rb_str_locktmp(str)
    VALUE str;
{
    if (FL_TEST(str, STR_TMPLOCK)) {
	rb_raise(rb_eRuntimeError, "temporal locking already locked string");
    }
    FL_SET(str, STR_TMPLOCK);
    return str;
}

VALUE
rb_str_unlocktmp(str)
    VALUE str;
{
    if (!FL_TEST(str, STR_TMPLOCK)) {
	rb_raise(rb_eRuntimeError, "temporal unlocking already unlocked string");
    }
    FL_UNSET(str, STR_TMPLOCK);
    return str;
}

void
rb_str_set_len(str, len)
    VALUE str;
    long len;
{
    RSTRING(str)->len = len;
    RSTRING(str)->ptr[len] = '\0';
}

VALUE
rb_str_resize(str, len)
    VALUE str;
    long len;
{
    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }

    rb_str_modify(str);
    if (len != RSTRING(str)->len) {
	if (RSTRING(str)->len < len || RSTRING(str)->len - len > 1024) {
	    REALLOC_N(RSTRING(str)->ptr, char, len+1);
	    if (!FL_TEST(str, STR_NOCAPA)) {
		RSTRING(str)->aux.capa = len;
	    }
	}
	RSTRING(str)->len = len;
	RSTRING(str)->ptr[len] = '\0';	/* sentinel */
    }
    return str;
}

static VALUE
str_buf_cat(str, ptr, len)
    VALUE str;
    const char *ptr;
    long len;
{
    long capa, total, off = -1;;

    rb_str_modify(str);
    if (ptr >= RSTRING(str)->ptr && ptr <= RSTRING(str)->ptr + RSTRING(str)->len) {
        off = ptr - RSTRING(str)->ptr;
    }
    if (len == 0) return 0;
    if (FL_TEST(str, STR_ASSOC)) {
	FL_UNSET(str, STR_ASSOC);
	capa = RSTRING(str)->aux.capa = RSTRING(str)->len;
    }
    else {
	capa = RSTRING(str)->aux.capa;
    }
    if (RSTRING(str)->len >= LONG_MAX - len) {
	rb_raise(rb_eArgError, "string sizes too big");
    }
    total = RSTRING(str)->len+len;
    if (capa <= total) {
	while (total > capa) {
	    if (capa + 1 >= LONG_MAX / 2) {
		capa = total;
		break;
	    }
	    capa = (capa + 1) * 2;
	}
	RESIZE_CAPA(str, capa);
    }
    if (off != -1) {
        ptr = RSTRING(str)->ptr + off;
    }
    memcpy(RSTRING(str)->ptr + RSTRING(str)->len, ptr, len);
    RSTRING(str)->len = total;
    RSTRING(str)->ptr[total] = '\0'; /* sentinel */

    return str;
}

VALUE
rb_str_buf_cat(str, ptr, len)
    VALUE str;
    const char *ptr;
    long len;
{
    if (len == 0) return str;
    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }
    return str_buf_cat(str, ptr, len);
}

VALUE
rb_str_buf_cat2(str, ptr)
    VALUE str;
    const char *ptr;
{
    return rb_str_buf_cat(str, ptr, strlen(ptr));
}

VALUE
rb_str_cat(str, ptr, len)
    VALUE str;
    const char *ptr;
    long len;
{
    if (len < 0) {
	rb_raise(rb_eArgError, "negative string size (or size too big)");
    }
    if (FL_TEST(str, STR_ASSOC)) {
	rb_str_modify(str);
	REALLOC_N(RSTRING(str)->ptr, char, RSTRING(str)->len+len+1);
	memcpy(RSTRING(str)->ptr + RSTRING(str)->len, ptr, len);
	RSTRING(str)->len += len;
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0'; /* sentinel */
	return str;
    }

    return rb_str_buf_cat(str, ptr, len);
}

VALUE
rb_str_cat2(str, ptr)
    VALUE str;
    const char *ptr;
{
    return rb_str_cat(str, ptr, strlen(ptr));
}

VALUE
rb_str_buf_append(str, str2)
    VALUE str, str2;
{
    str_buf_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
    OBJ_INFECT(str, str2);
    return str;
}

VALUE
rb_str_append(str, str2)
    VALUE str, str2;
{
    StringValue(str2);
    rb_str_modify(str);
    if (RSTRING(str2)->len > 0) {
	if (FL_TEST(str, STR_ASSOC)) {
	    long len = RSTRING(str)->len+RSTRING(str2)->len;
	    REALLOC_N(RSTRING(str)->ptr, char, len+1);
	    memcpy(RSTRING(str)->ptr + RSTRING(str)->len,
		   RSTRING(str2)->ptr, RSTRING(str2)->len);
	    RSTRING(str)->ptr[len] = '\0'; /* sentinel */
	    RSTRING(str)->len = len;
	}
	else {
	    return rb_str_buf_append(str, str2);
	}
    }
    OBJ_INFECT(str, str2);
    return str;
}


/*
 *  call-seq:
 *     str << fixnum        => str
 *     str.concat(fixnum)   => str
 *     str << obj           => str
 *     str.concat(obj)      => str
 *
 *  Append---Concatenates the given object to <i>str</i>. If the object is a
 *  <code>Fixnum</code> between 0 and 255, it is converted to a character before
 *  concatenation.
 *
 *     a = "hello "
 *     a << "world"   #=> "hello world"
 *     a.concat(33)   #=> "hello world!"
 */

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
    str1 = rb_str_append(str1, str2);

    return str1;
}

int
rb_str_hash(str)
    VALUE str;
{
    register long len = RSTRING(str)->len;
    register char *p = RSTRING(str)->ptr;
    register int key = 0;

#if defined(HASH_ELFHASH)
    register unsigned int g;

    while (len--) {
	key = (key << 4) + *p++;
	if (g = key & 0xF0000000)
	    key ^= g >> 24;
	key &= ~g;
    }
#elif defined(HASH_PERL)
    while (len--) {
	key += *p++;
	key += (key << 10);
	key ^= (key >> 6);
    }
    key += (key << 3);
    key ^= (key >> 11);
    key += (key << 15);
#else
    while (len--) {
	key = key*65599 + *p;
	p++;
    }
    key = key + (key>>5);
#endif
    return key;
}

/*
 * call-seq:
 *    str.hash   => fixnum
 *
 * Return a hash based on the string's length and content.
 */

static VALUE
rb_str_hash_m(str)
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
    long len;
    int retval;

    len = lesser(RSTRING(str1)->len, RSTRING(str2)->len);
    retval = rb_memcmp(RSTRING(str1)->ptr, RSTRING(str2)->ptr, len);
    if (retval == 0) {
	if (RSTRING(str1)->len == RSTRING(str2)->len) return 0;
	if (RSTRING(str1)->len > RSTRING(str2)->len) return 1;
	return -1;
    }
    if (retval > 0) return 1;
    return -1;
}


/*
 *  call-seq:
 *     str == obj   => true or false
 *
 *  Equality---If <i>obj</i> is not a <code>String</code>, returns
 *  <code>false</code>. Otherwise, returns <code>true</code> if <i>str</i>
 *  <code><=></code> <i>obj</i> returns zero.
 */

static VALUE
rb_str_equal(str1, str2)
    VALUE str1, str2;
{
    if (str1 == str2) return Qtrue;
    if (TYPE(str2) != T_STRING) {
	if (!rb_respond_to(str2, rb_intern("to_str"))) {
	    return Qfalse;
	}
	return rb_equal(str2, str1);
    }
    if (RSTRING(str1)->len == RSTRING(str2)->len &&
	rb_str_cmp(str1, str2) == 0) {
	return Qtrue;
    }
    return Qfalse;
}

#define IS_EVSTR(p,e) ((p) < (e) && (*(p) == '$' || *(p) == '@' || *(p) == '{'))

/*
 * call-seq:
 *   str.eql?(other)   => true or false
 *
 * Two strings are equal if the have the same length and content.
 */

static VALUE
rb_str_eql(str1, str2)
    VALUE str1, str2;
{
    if (TYPE(str2) != T_STRING || RSTRING(str1)->len != RSTRING(str2)->len)
	return Qfalse;

    if (memcmp(RSTRING(str1)->ptr, RSTRING(str2)->ptr,
	       lesser(RSTRING(str1)->len, RSTRING(str2)->len)) == 0)
	return Qtrue;

    return Qfalse;
}

static VALUE rb_str_cmp_m _((VALUE, VALUE));

/*
 *  call-seq:
 *     str <=> other_str   => -1, 0, +1 or nil
 *
 *  Comparison---Returns -1 if <i>other_str</i> is greater than, 0 if
 *  <i>other_str</i> is equal to, and +1 if <i>other_str</i> is less than
 *  <i>str</i>. If the strings are of different lengths, and the strings are
 *  equal when compared up to the shortest length, then the longer string is
 *  considered greater than the shorter one. If the variable <code>$=</code> is
 *  <code>false</code>, the comparison is based on comparing the binary values
 *  of each character in the string. In older versions of Ruby, setting
 *  <code>$=</code> allowed case-insensitive comparisons; this is now deprecated
 *  in favor of using <code>String#casecmp</code>.
 *
 *  <code><=></code> is the basis for the methods <code><</code>,
 *  <code><=</code>, <code>></code>, <code>>=</code>, and <code>between?</code>,
 *  included from module <code>Comparable</code>.  The method
 *  <code>String#==</code> does not use <code>Comparable#==</code>.
 *
 *     "abcdef" <=> "abcde"     #=> 1
 *     "abcdef" <=> "abcdef"    #=> 0
 *     "abcdef" <=> "abcdefg"   #=> -1
 *     "abcdef" <=> "ABCDEF"    #=> 1
 */

static VALUE
rb_str_cmp_m(str1, str2)
    VALUE str1, str2;
{
    long result;

    if (TYPE(str2) != T_STRING) {
	if (!rb_respond_to(str2, rb_intern("to_str"))) {
	    return Qnil;
	}
	else if (!rb_respond_to(str2, rb_intern("<=>"))) {
	    return Qnil;
	}
	else {
	    VALUE tmp = rb_funcall(str2, rb_intern("<=>"), 1, str1);

	    if (NIL_P(tmp)) return Qnil;
	    if (!FIXNUM_P(tmp)) {
		return rb_funcall(LONG2FIX(0), '-', 1, tmp);
	    }
	    result = -FIX2LONG(tmp);
	}
    }
    else {
	result = rb_str_cmp(str1, str2);
    }
    return LONG2NUM(result);
}

static VALUE rb_str_casecmp _((VALUE, VALUE));

/*
 *  call-seq:
 *     str.casecmp(other_str)   => -1, 0, +1 or nil
 *
 *  Case-insensitive version of <code>String#<=></code>.
 *
 *     "abcdef".casecmp("abcde")     #=> 1
 *     "aBcDeF".casecmp("abcdef")    #=> 0
 *     "abcdef".casecmp("abcdefg")   #=> -1
 *     "abcdef".casecmp("ABCDEF")    #=> 0
 */

static VALUE
rb_str_casecmp(str1, str2)
    VALUE str1, str2;
{
    long len;
    int retval;

    StringValue(str2);
    len = lesser(RSTRING(str1)->len, RSTRING(str2)->len);
    retval = rb_memcicmp(RSTRING(str1)->ptr, RSTRING(str2)->ptr, len);
    if (retval == 0) {
	if (RSTRING(str1)->len == RSTRING(str2)->len) return INT2FIX(0);
	if (RSTRING(str1)->len > RSTRING(str2)->len) return INT2FIX(1);
	return INT2FIX(-1);
    }
    if (retval == 0) return INT2FIX(0);
    if (retval > 0) return INT2FIX(1);
    return INT2FIX(-1);
}

static long
rb_str_index(str, sub, offset)
    VALUE str, sub;
    long offset;
{
    long pos;

    if (offset < 0) {
	offset += RSTRING(str)->len;
	if (offset < 0) return -1;
    }
    if (RSTRING(str)->len - offset < RSTRING(sub)->len) return -1;
    if (RSTRING(sub)->len == 0) return offset;
    pos = rb_memsearch(RSTRING(sub)->ptr, RSTRING(sub)->len,
		       RSTRING(str)->ptr+offset, RSTRING(str)->len-offset);
    if (pos < 0) return pos;
    return pos + offset;
}


/*
 *  call-seq:
 *     str.index(substring [, offset])   => fixnum or nil
 *     str.index(fixnum [, offset])      => fixnum or nil
 *     str.index(regexp [, offset])      => fixnum or nil
 *
 *  Returns the index of the first occurrence of the given <i>substring</i>,
 *  character (<i>fixnum</i>), or pattern (<i>regexp</i>) in <i>str</i>. Returns
 *  <code>nil</code> if not found. If the second parameter is present, it
 *  specifies the position in the string to begin the search.
 *
 *     "hello".index('e')             #=> 1
 *     "hello".index('lo')            #=> 3
 *     "hello".index('a')             #=> nil
 *     "hello".index(101)             #=> 1
 *     "hello".index(/[aeiou]/, -3)   #=> 4
 */

static VALUE
rb_str_index_m(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE sub;
    VALUE initpos;
    long pos;

    if (rb_scan_args(argc, argv, "11", &sub, &initpos) == 2) {
	pos = NUM2LONG(initpos);
    }
    else {
	pos = 0;
    }
    if (pos < 0) {
	pos += RSTRING(str)->len;
	if (pos < 0) {
	    if (TYPE(sub) == T_REGEXP) {
		rb_backref_set(Qnil);
	    }
	    return Qnil;
	}
    }

    switch (TYPE(sub)) {
      case T_REGEXP:
	pos = rb_reg_adjust_startpos(sub, str, pos, 0);
	pos = rb_reg_search(sub, str, pos, 0);
	break;

      case T_FIXNUM: {
	int c = FIX2INT(sub);
	long len = RSTRING(str)->len;
	unsigned char *p = (unsigned char*)RSTRING(str)->ptr;

	for (;pos<len;pos++) {
	    if (p[pos] == c) return LONG2NUM(pos);
	}
	return Qnil;
      }

      default: {
	VALUE tmp;

	tmp = rb_check_string_type(sub);
	if (NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "type mismatch: %s given",
		     rb_obj_classname(sub));
	}
	sub = tmp;
      }
	/* fall through */
      case T_STRING:
	pos = rb_str_index(str, sub, pos);
	break;
    }

    if (pos == -1) return Qnil;
    return LONG2NUM(pos);
}

static long
rb_str_rindex(str, sub, pos)
    VALUE str, sub;
    long pos;
{
    long len = RSTRING(sub)->len;
    char *s, *sbeg, *t;

    /* substring longer than string */
    if (RSTRING(str)->len < len) return -1;
    if (RSTRING(str)->len - pos < len) {
	pos = RSTRING(str)->len - len;
    }
    sbeg = RSTRING(str)->ptr;
    s = RSTRING(str)->ptr + pos;
    t = RSTRING(sub)->ptr;
    if (len) {
	while (sbeg <= s) {
	    if (rb_memcmp(s, t, len) == 0) {
		return s - RSTRING(str)->ptr;
	    }
	    s--;
	}
	return -1;
    }
    else {
	return pos;
    }
}


/*
 *  call-seq:
 *     str.rindex(substring [, fixnum])   => fixnum or nil
 *     str.rindex(fixnum [, fixnum])   => fixnum or nil
 *     str.rindex(regexp [, fixnum])   => fixnum or nil
 *
 *  Returns the index of the last occurrence of the given <i>substring</i>,
 *  character (<i>fixnum</i>), or pattern (<i>regexp</i>) in <i>str</i>. Returns
 *  <code>nil</code> if not found. If the second parameter is present, it
 *  specifies the position in the string to end the search---characters beyond
 *  this point will not be considered.
 *
 *     "hello".rindex('e')             #=> 1
 *     "hello".rindex('l')             #=> 3
 *     "hello".rindex('a')             #=> nil
 *     "hello".rindex(101)             #=> 1
 *     "hello".rindex(/[aeiou]/, -2)   #=> 1
 */

static VALUE
rb_str_rindex_m(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE sub;
    VALUE position;
    long pos;

    if (rb_scan_args(argc, argv, "11", &sub, &position) == 2) {
	pos = NUM2LONG(position);
	if (pos < 0) {
	    pos += RSTRING(str)->len;
	    if (pos < 0) {
		if (TYPE(sub) == T_REGEXP) {
		    rb_backref_set(Qnil);
		}
		return Qnil;
	    }
	}
	if (pos > RSTRING(str)->len) pos = RSTRING(str)->len;
    }
    else {
	pos = RSTRING(str)->len;
    }

    switch (TYPE(sub)) {
      case T_REGEXP:
	if (RREGEXP(sub)->len) {
	    pos = rb_reg_adjust_startpos(sub, str, pos, 1);
	    pos = rb_reg_search(sub, str, pos, 1);
	}
	if (pos >= 0) return LONG2NUM(pos);
	break;

      default: {
	VALUE tmp;

	tmp = rb_check_string_type(sub);
	if (NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "type mismatch: %s given",
		     rb_obj_classname(sub));
	}
	sub = tmp;
      }
	/* fall through */
      case T_STRING:
	pos = rb_str_rindex(str, sub, pos);
	if (pos >= 0) return LONG2NUM(pos);
	break;

      case T_FIXNUM: {
	int c = FIX2INT(sub);
	unsigned char *p = (unsigned char*)RSTRING(str)->ptr + pos;
	unsigned char *pbeg = (unsigned char*)RSTRING(str)->ptr;

	if (pos == RSTRING(str)->len) {
	    if (pos == 0) return Qnil;
	    --p;
	}
	while (pbeg <= p) {
	    if (*p == c) return LONG2NUM((char*)p - RSTRING(str)->ptr);
	    p--;
	}
	return Qnil;
      }
    }
    return Qnil;
}

static VALUE rb_str_match _((VALUE, VALUE));

/*
 *  call-seq:
 *     str =~ obj   => fixnum or nil
 *
 *  Match---If <i>obj</i> is a <code>Regexp</code>, use it as a pattern to match
 *  against <i>str</i>,and returns the position the match starts, or
 *  <code>nil</code> if there is no match. Otherwise, invokes
 *  <i>obj.=~</i>, passing <i>str</i> as an argument. The default
 *  <code>=~</code> in <code>Object</code> returns <code>false</code>.
 *
 *     "cat o' 9 tails" =~ /\d/   #=> 7
 *     "cat o' 9 tails" =~ 9      #=> false
 */

static VALUE
rb_str_match(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_STRING:
	rb_raise(rb_eTypeError, "type mismatch: String given");

      case T_REGEXP:
	return rb_reg_match(y, x);

      default:
	return rb_funcall(y, rb_intern("=~"), 1, x);
    }
}


static VALUE get_pat _((VALUE, int));


/*
 *  call-seq:
 *     str.match(pattern)   => matchdata or nil
 *
 *  Converts <i>pattern</i> to a <code>Regexp</code> (if it isn't already one),
 *  then invokes its <code>match</code> method on <i>str</i>.
 *
 *     'hello'.match('(.)\1')      #=> #<MatchData:0x401b3d30>
 *     'hello'.match('(.)\1')[0]   #=> "ll"
 *     'hello'.match(/(.)\1/)[0]   #=> "ll"
 *     'hello'.match('xx')         #=> nil
 */

static VALUE
rb_str_match_m(str, re)
    VALUE str, re;
{
    return rb_funcall(get_pat(re, 0), rb_intern("match"), 1, str);
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


/*
 *  call-seq:
 *     str.succ   => new_str
 *     str.next   => new_str
 *
 *  Returns the successor to <i>str</i>. The successor is calculated by
 *  incrementing characters starting from the rightmost alphanumeric (or
 *  the rightmost character if there are no alphanumerics) in the
 *  string. Incrementing a digit always results in another digit, and
 *  incrementing a letter results in another letter of the same case.
 *  Incrementing nonalphanumerics uses the underlying character set's
 *  collating sequence.
 *
 *  If the increment generates a ``carry,'' the character to the left of
 *  it is incremented. This process repeats until there is no carry,
 *  adding an additional character if necessary.
 *
 *     "abcd".succ        #=> "abce"
 *     "THX1138".succ     #=> "THX1139"
 *     "<<koala>>".succ   #=> "<<koalb>>"
 *     "1999zzz".succ     #=> "2000aaa"
 *     "ZZZ9999".succ     #=> "AAAA0000"
 *     "***".succ         #=> "**+"
 */

static VALUE
rb_str_succ(orig)
    VALUE orig;
{
    VALUE str;
    char *sbeg, *s;
    int c = -1;
    long n = 0;

    str = rb_str_new5(orig, RSTRING(orig)->ptr, RSTRING(orig)->len);
    OBJ_INFECT(str, orig);
    if (RSTRING(str)->len == 0) return str;

    sbeg = RSTRING(str)->ptr; s = sbeg + RSTRING(str)->len - 1;

    while (sbeg <= s) {
	if (ISALNUM(*s)) {
	    if ((c = succ_char(s)) == 0) break;
	    n = s - sbeg;
	}
	s--;
    }
    if (c == -1) {		/* str contains no alnum */
	sbeg = RSTRING(str)->ptr; s = sbeg + RSTRING(str)->len - 1;
	c = '\001';
	while (sbeg <= s) {
	    if ((*s += 1) != 0) break;
	    s--;
	}
    }
    if (s < sbeg) {
	RESIZE_CAPA(str, RSTRING(str)->len + 1);
	s = RSTRING(str)->ptr + n;
	memmove(s+1, s, RSTRING(str)->len - n);
	*s = c;
	RSTRING(str)->len += 1;
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
    }

    return str;
}


static VALUE rb_str_succ_bang _((VALUE));

/*
 *  call-seq:
 *     str.succ!   => str
 *     str.next!   => str
 *
 *  Equivalent to <code>String#succ</code>, but modifies the receiver in
 *  place.
 */

static VALUE
rb_str_succ_bang(str)
    VALUE str;
{
    rb_str_shared_replace(str, rb_str_succ(str));

    return str;
}

VALUE
rb_str_upto(beg, end, excl)
    VALUE beg, end;
    int excl;
{
    VALUE current, after_end;
    ID succ = rb_intern("succ");
    int n;

    StringValue(end);
    n = rb_str_cmp(beg, end);
    if (n > 0 || (excl && n == 0)) return beg;
    after_end = rb_funcall(end, succ, 0, 0);
    current = beg;
    while (!rb_str_equal(current, after_end)) {
	rb_yield(current);
	if (!excl && rb_str_equal(current, end)) break;
	current = rb_funcall(current, succ, 0, 0);
	StringValue(current);
	if (excl && rb_str_equal(current, end)) break;
	StringValue(current);
	if (RSTRING(current)->len > RSTRING(end)->len || RSTRING(current)->len == 0)
	    break;
    }

    return beg;
}


/*
 *  call-seq:
 *     str.upto(other_str, exclusive=false) {|s| block }   => str
 *
 *  Iterates through successive values, starting at <i>str</i> and
 *  ending at <i>other_str</i> inclusive, passing each value in turn to
 *  the block. The <code>String#succ</code> method is used to generate
 *  each value.  If optional second argument exclusive is omitted or is <code>false</code>,
 *  the last value will be included; otherwise it will be excluded.
 *
 *     "a8".upto("b6") {|s| print s, ' ' }
 *     for s in "a8".."b6"
 *       print s, ' '
 *     end
 *
 *  <em>produces:</em>
 *
 *     a8 a9 b0 b1 b2 b3 b4 b5 b6
 *     a8 a9 b0 b1 b2 b3 b4 b5 b6
 */

static VALUE
rb_str_upto_m(argc, argv, beg)
    int argc;
    VALUE *argv;
    VALUE beg;
{
    VALUE end, exclusive;

    rb_scan_args(argc, argv, "11", &end, &exclusive);

    return rb_str_upto(beg, end, RTEST(exclusive));
}

static VALUE
rb_str_subpat(str, re, nth)
    VALUE str, re;
    int nth;
{
    if (rb_reg_search(re, str, 0, 0) >= 0) {
	return rb_reg_nth_match(nth, rb_backref_get());
    }
    return Qnil;
}

static VALUE
rb_str_aref(str, indx)
    VALUE str;
    VALUE indx;
{
    long idx;

    switch (TYPE(indx)) {
      case T_FIXNUM:
	idx = FIX2LONG(indx);

      num_index:
	if (idx < 0) {
	    idx = RSTRING(str)->len + idx;
	}
	if (idx < 0 || RSTRING(str)->len <= idx) {
	    return Qnil;
	}
	return INT2FIX(RSTRING(str)->ptr[idx] & 0xff);

      case T_REGEXP:
	return rb_str_subpat(str, indx, 0);

      case T_STRING:
	if (rb_str_index(str, indx, 0) != -1)
	    return rb_str_dup(indx);
	return Qnil;

      default:
	/* check if indx is Range */
	{
	    long beg, len;
	    VALUE tmp;

	    switch (rb_range_beg_len(indx, &beg, &len, RSTRING(str)->len, 0)) {
	      case Qfalse:
		break;
	      case Qnil:
		return Qnil;
	      default:
		tmp = rb_str_substr(str, beg, len);
		OBJ_INFECT(tmp, indx);
		return tmp;
	    }
	}
	idx = NUM2LONG(indx);
	goto num_index;
    }
    return Qnil;		/* not reached */
}


static VALUE rb_str_aref_m _((int, VALUE *, VALUE));

/*
 *  call-seq:
 *     str[fixnum]                 => fixnum or nil
 *     str[fixnum, fixnum]         => new_str or nil
 *     str[range]                  => new_str or nil
 *     str[regexp]                 => new_str or nil
 *     str[regexp, fixnum]         => new_str or nil
 *     str[other_str]              => new_str or nil
 *     str.slice(fixnum)           => fixnum or nil
 *     str.slice(fixnum, fixnum)   => new_str or nil
 *     str.slice(range)            => new_str or nil
 *     str.slice(regexp)           => new_str or nil
 *     str.slice(regexp, fixnum)   => new_str or nil
 *     str.slice(other_str)        => new_str or nil
 *
 *  Element Reference---If passed a single <code>Fixnum</code>, returns the code
 *  of the character at that position. If passed two <code>Fixnum</code>
 *  objects, returns a substring starting at the offset given by the first, and
 *  a length given by the second. If given a range, a substring containing
 *  characters at offsets given by the range is returned. In all three cases, if
 *  an offset is negative, it is counted from the end of <i>str</i>. Returns
 *  <code>nil</code> if the initial offset falls outside the string, the length
 *  is negative, or the beginning of the range is greater than the end.
 *
 *  If a <code>Regexp</code> is supplied, the matching portion of <i>str</i> is
 *  returned. If a numeric parameter follows the regular expression, that
 *  component of the <code>MatchData</code> is returned instead. If a
 *  <code>String</code> is given, that string is returned if it occurs in
 *  <i>str</i>. In both cases, <code>nil</code> is returned if there is no
 *  match.
 *
 *     a = "hello there"
 *     a[1]                   #=> 101
 *     a[1,3]                 #=> "ell"
 *     a[1..3]                #=> "ell"
 *     a[-3,2]                #=> "er"
 *     a[-4..-2]              #=> "her"
 *     a[12..-1]              #=> nil
 *     a[-2..-4]              #=> ""
 *     a[/[aeiou](.)\1/]      #=> "ell"
 *     a[/[aeiou](.)\1/, 0]   #=> "ell"
 *     a[/[aeiou](.)\1/, 1]   #=> "l"
 *     a[/[aeiou](.)\1/, 2]   #=> nil
 *     a["lo"]                #=> "lo"
 *     a["bye"]               #=> nil
 */

static VALUE
rb_str_aref_m(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    if (argc == 2) {
	if (TYPE(argv[0]) == T_REGEXP) {
	    return rb_str_subpat(str, argv[0], NUM2INT(argv[1]));
	}
	return rb_str_substr(str, NUM2LONG(argv[0]), NUM2LONG(argv[1]));
    }
    if (argc != 1) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", argc);
    }
    return rb_str_aref(str, argv[0]);
}

static void
rb_str_splice(str, beg, len, val)
    VALUE str;
    long beg, len;
    VALUE val;
{
    if (len < 0) rb_raise(rb_eIndexError, "negative length %ld", len);

    StringValue(val);
    rb_str_modify(str);

    if (RSTRING(str)->len < beg) {
      out_of_range:
	rb_raise(rb_eIndexError, "index %ld out of string", beg);
    }
    if (beg < 0) {
	if (-beg > RSTRING(str)->len) {
	    goto out_of_range;
	}
	beg += RSTRING(str)->len;
    }
    if (RSTRING(str)->len < len || RSTRING(str)->len < beg + len) {
	len = RSTRING(str)->len - beg;
    }

    if (len < RSTRING(val)->len) {
	/* expand string */
	RESIZE_CAPA(str, RSTRING(str)->len + RSTRING(val)->len - len + 1);
    }

    if (RSTRING(val)->len != len) {
	memmove(RSTRING(str)->ptr + beg + RSTRING(val)->len,
		RSTRING(str)->ptr + beg + len,
		RSTRING(str)->len - (beg + len));
    }
    if (RSTRING(str)->len < beg && len < 0) {
	MEMZERO(RSTRING(str)->ptr + RSTRING(str)->len, char, -len);
    }
    if (RSTRING(val)->len > 0) {
	memmove(RSTRING(str)->ptr+beg, RSTRING(val)->ptr, RSTRING(val)->len);
    }
    RSTRING(str)->len += RSTRING(val)->len - len;
    if (RSTRING(str)->ptr) {
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
    }
    OBJ_INFECT(str, val);
}

void
rb_str_update(str, beg, len, val)
    VALUE str;
    long beg, len;
    VALUE val;
{
    rb_str_splice(str, beg, len, val);
}

static void
rb_str_subpat_set(str, re, nth, val)
    VALUE str, re;
    int nth;
    VALUE val;
{
    VALUE match;
    long start, end, len;

    if (rb_reg_search(re, str, 0, 0) < 0) {
	rb_raise(rb_eIndexError, "regexp not matched");
    }
    match = rb_backref_get();
    if (nth >= RMATCH(match)->regs->num_regs) {
      out_of_range:
	rb_raise(rb_eIndexError, "index %d out of regexp", nth);
    }
    if (nth < 0) {
	if (-nth >= RMATCH(match)->regs->num_regs) {
	    goto out_of_range;
	}
	nth += RMATCH(match)->regs->num_regs;
    }

    start = RMATCH(match)->BEG(nth);
    if (start == -1) {
	rb_raise(rb_eIndexError, "regexp group %d not matched", nth);
    }
    end = RMATCH(match)->END(nth);
    len = end - start;
    rb_str_splice(str, start, len, val);
}

static VALUE
rb_str_aset(str, indx, val)
    VALUE str;
    VALUE indx, val;
{
    long idx, beg;

    switch (TYPE(indx)) {
      case T_FIXNUM:
	idx = FIX2LONG(indx);
      num_index:
	if (RSTRING(str)->len <= idx) {
	  out_of_range:
	    rb_raise(rb_eIndexError, "index %ld out of string", idx);
	}
	if (idx < 0) {
	    if (-idx > RSTRING(str)->len)
		goto out_of_range;
	    idx += RSTRING(str)->len;
	}
	if (FIXNUM_P(val)) {
	    rb_str_modify(str);
	    if (RSTRING(str)->len == idx) {
		RSTRING(str)->len += 1;
		RESIZE_CAPA(str, RSTRING(str)->len);
	    }
	    RSTRING(str)->ptr[idx] = FIX2INT(val) & 0xff;
	}
	else {
	    rb_str_splice(str, idx, 1, val);
	}
	return val;

      case T_REGEXP:
	rb_str_subpat_set(str, indx, 0, val);
	return val;

      case T_STRING:
	beg = rb_str_index(str, indx, 0);
	if (beg < 0) {
	    rb_raise(rb_eIndexError, "string not matched");
	}
	rb_str_splice(str, beg, RSTRING(indx)->len, val);
	return val;

      default:
	/* check if indx is Range */
	{
	    long beg, len;
	    if (rb_range_beg_len(indx, &beg, &len, RSTRING(str)->len, 2)) {
		rb_str_splice(str, beg, len, val);
		return val;
	    }
	}
	idx = NUM2LONG(indx);
	goto num_index;
    }
}

/*
 *  call-seq:
 *     str[fixnum] = fixnum
 *     str[fixnum] = new_str
 *     str[fixnum, fixnum] = new_str
 *     str[range] = aString
 *     str[regexp] = new_str
 *     str[regexp, fixnum] = new_str
 *     str[other_str] = new_str
 *
 *  Element Assignment---Replaces some or all of the content of <i>str</i>. The
 *  portion of the string affected is determined using the same criteria as
 *  <code>String#[]</code>. If the replacement string is not the same length as
 *  the text it is replacing, the string will be adjusted accordingly. If the
 *  regular expression or string is used as the index doesn't match a position
 *  in the string, <code>IndexError</code> is raised. If the regular expression
 *  form is used, the optional second <code>Fixnum</code> allows you to specify
 *  which portion of the match to replace (effectively using the
 *  <code>MatchData</code> indexing rules. The forms that take a
 *  <code>Fixnum</code> will raise an <code>IndexError</code> if the value is
 *  out of range; the <code>Range</code> form will raise a
 *  <code>RangeError</code>, and the <code>Regexp</code> and <code>String</code>
 *  forms will silently ignore the assignment.
 */

static VALUE
rb_str_aset_m(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    if (argc == 3) {
	if (TYPE(argv[0]) == T_REGEXP) {
	    rb_str_subpat_set(str, argv[0], NUM2INT(argv[1]), argv[2]);
	}
	else {
	    rb_str_splice(str, NUM2LONG(argv[0]), NUM2LONG(argv[1]), argv[2]);
	}
	return argv[2];
    }
    if (argc != 2) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 2)", argc);
    }
    return rb_str_aset(str, argv[0], argv[1]);
}

/*
 *  call-seq:
 *     str.insert(index, other_str)   => str
 *
 *  Inserts <i>other_str</i> before the character at the given
 *  <i>index</i>, modifying <i>str</i>. Negative indices count from the
 *  end of the string, and insert <em>after</em> the given character.
 *  The intent is insert <i>aString</i> so that it starts at the given
 *  <i>index</i>.
 *
 *     "abcd".insert(0, 'X')    #=> "Xabcd"
 *     "abcd".insert(3, 'X')    #=> "abcXd"
 *     "abcd".insert(4, 'X')    #=> "abcdX"
 *     "abcd".insert(-3, 'X')   #=> "abXcd"
 *     "abcd".insert(-1, 'X')   #=> "abcdX"
 */

static VALUE
rb_str_insert(str, idx, str2)
    VALUE str, idx, str2;
{
    long pos = NUM2LONG(idx);

    if (pos == -1) {
	pos = RSTRING(str)->len;
    }
    else if (pos < 0) {
	pos++;
    }
    rb_str_splice(str, pos, 0, str2);
    return str;
}

/*
 *  call-seq:
 *     str.slice!(fixnum)           => fixnum or nil
 *     str.slice!(fixnum, fixnum)   => new_str or nil
 *     str.slice!(range)            => new_str or nil
 *     str.slice!(regexp)           => new_str or nil
 *     str.slice!(other_str)        => new_str or nil
 *
 *  Deletes the specified portion from <i>str</i>, and returns the portion
 *  deleted. The forms that take a <code>Fixnum</code> will raise an
 *  <code>IndexError</code> if the value is out of range; the <code>Range</code>
 *  form will raise a <code>RangeError</code>, and the <code>Regexp</code> and
 *  <code>String</code> forms will silently ignore the assignment.
 *
 *     string = "this is a string"
 *     string.slice!(2)        #=> 105
 *     string.slice!(3..6)     #=> " is "
 *     string.slice!(/s.*t/)   #=> "sa st"
 *     string.slice!("r")      #=> "r"
 *     string                  #=> "thing"
 */

static VALUE
rb_str_slice_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE result;
    VALUE buf[3];
    int i;

    if (argc < 1 || 2 < argc) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", argc);
    }
    for (i=0; i<argc; i++) {
	buf[i] = argv[i];
    }
    buf[i] = rb_str_new(0,0);
    result = rb_str_aref_m(argc, buf, str);
    if (!NIL_P(result)) {
	rb_str_aset_m(argc+1, buf, str);
    }
    return result;
}

static VALUE
get_pat(pat, quote)
    VALUE pat;
    int quote;
{
    VALUE val;

    switch (TYPE(pat)) {
      case T_REGEXP:
	return pat;

      case T_STRING:
	break;

      default:
	val = rb_check_string_type(pat);
	if (NIL_P(val)) {
	    Check_Type(pat, T_REGEXP);
	}
	pat = val;
    }

    if (quote) {
	pat = rb_reg_quote(pat);
    }

    return rb_reg_regcomp(pat);
}

static VALUE
get_pat_quoted(pat)
     VALUE pat;
{
    return get_pat(pat, 1);
}

static VALUE
regcomp_failed(str)
    VALUE str;
{
    rb_raise(rb_eArgError, "invalid byte sequence");
    /*NOTREACHED*/
    return Qundef;
}

static VALUE
get_arg_pat(pat)
     VALUE pat;
{
    return rb_rescue2(get_pat_quoted, pat,
                      regcomp_failed, pat,
                      rb_eRegexpError, (VALUE)0);
}

/*
 *  call-seq:
 *     str.sub!(pattern, replacement)          => str or nil
 *     str.sub!(pattern) {|match| block }      => str or nil
 *
 *  Performs the substitutions of <code>String#sub</code> in place,
 *  returning <i>str</i>, or <code>nil</code> if no substitutions were
 *  performed.
 */

static VALUE
rb_str_sub_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE pat, repl, match;
    struct re_registers *regs;
    int iter = 0;
    int tainted = 0;
    long plen;

    if (argc == 1 && rb_block_given_p()) {
	iter = 1;
    }
    else if (argc == 2) {
	repl = argv[1];
	StringValue(repl);
	if (OBJ_TAINTED(repl)) tainted = 1;
    }
    else {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 2)", argc);
    }

    pat = get_pat(argv[0], 1);
    if (rb_reg_search(pat, str, 0, 0) >= 0) {
	match = rb_backref_get();
	regs = RMATCH(match)->regs;

	if (iter) {
	    char *p = RSTRING(str)->ptr; long len = RSTRING(str)->len;

	    rb_match_busy(match);
	    repl = rb_obj_as_string(rb_yield(rb_reg_nth_match(0, match)));
	    str_mod_check(str, p, len);
	    str_frozen_check(str);
	    rb_backref_set(match);
	}
	else {
	    repl = rb_reg_regsub(repl, str, regs);
	}
	rb_str_modify(str);
	if (OBJ_TAINTED(repl)) tainted = 1;
	plen = END(0) - BEG(0);
	if (RSTRING(repl)->len > plen) {
	    RESIZE_CAPA(str, RSTRING(str)->len + RSTRING(repl)->len - plen);
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
	if (tainted) OBJ_TAINT(str);

	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.sub(pattern, replacement)         => new_str
 *     str.sub(pattern) {|match| block }     => new_str
 *
 *  Returns a copy of <i>str</i> with the <em>first</em> occurrence of
 *  <i>pattern</i> replaced with either <i>replacement</i> or the value of the
 *  block. The <i>pattern</i> will typically be a <code>Regexp</code>; if it is
 *  a <code>String</code> then no regular expression metacharacters will be
 *  interpreted (that is <code>/\d/</code> will match a digit, but
 *  <code>'\d'</code> will match a backslash followed by a 'd').
 *
 *  If the method call specifies <i>replacement</i>, special variables such as
 *  <code>$&</code> will not be useful, as substitution into the string occurs
 *  before the pattern match starts. However, the sequences <code>\1</code>,
 *  <code>\2</code>, etc., may be used.
 *
 *  In the block form, the current match string is passed in as a parameter, and
 *  variables such as <code>$1</code>, <code>$2</code>, <code>$`</code>,
 *  <code>$&</code>, and <code>$'</code> will be set appropriately. The value
 *  returned by the block will be substituted for the match on each call.
 *
 *  The result inherits any tainting in the original string or any supplied
 *  replacement string.
 *
 *     "hello".sub(/[aeiou]/, '*')               #=> "h*llo"
 *     "hello".sub(/([aeiou])/, '<\1>')          #=> "h<e>llo"
 *     "hello".sub(/./) {|s| s[0].to_s + ' ' }   #=> "104 ello"
 */

static VALUE
rb_str_sub(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_sub_bang(argc, argv, str);
    return str;
}

static VALUE
str_gsub(argc, argv, str, bang)
    int argc;
    VALUE *argv;
    VALUE str;
    int bang;
{
    VALUE pat, val, repl, match, dest;
    struct re_registers *regs;
    long beg, n;
    long offset, blen, slen, len;
    int iter = 0;
    char *buf, *bp, *sp, *cp;
    int tainted = 0;

    if (argc == 1) {
        RETURN_ENUMERATOR(str, argc, argv);
	iter = 1;
    }
    else if (argc == 2) {
	repl = argv[1];
	StringValue(repl);
	if (OBJ_TAINTED(repl)) tainted = 1;
    }
    else {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 2)", argc);
    }

    pat = get_pat(argv[0], 1);
    offset=0; n=0;
    beg = rb_reg_search(pat, str, 0, 0);
    if (beg < 0) {
	if (bang) return Qnil;	/* no match, no substitution */
	return rb_str_dup(str);
    }

    blen = RSTRING(str)->len + 30; /* len + margin */
    dest = str_new(0, 0, blen);
    buf = RSTRING(dest)->ptr;
    bp = buf;
    sp = cp = RSTRING(str)->ptr;
    slen = RSTRING(str)->len;

    rb_str_locktmp(dest);
    do {
	n++;
	match = rb_backref_get();
	regs = RMATCH(match)->regs;
	if (iter) {
	    rb_match_busy(match);
	    val = rb_obj_as_string(rb_yield(rb_reg_nth_match(0, match)));
	    str_mod_check(str, sp, slen);
	    if (bang) str_frozen_check(str);
	    if (val == dest) {  /* paranoid chack [ruby-dev:24827] */
		rb_raise(rb_eRuntimeError, "block should not cheat");
	    }
	    rb_backref_set(match);
	}
	else {
	    val = rb_reg_regsub(repl, str, regs);
	}
	if (OBJ_TAINTED(val)) tainted = 1;
	len = (bp - buf) + (beg - offset) + RSTRING(val)->len + 3;
	if (blen < len) {
	    while (blen < len) blen *= 2;
	    len = bp - buf;
	    RESIZE_CAPA(dest, blen);
	    RSTRING(dest)->len = blen;
	    buf = RSTRING(dest)->ptr;
	    bp = buf + len;
	}
	len = beg - offset;	/* copy pre-match substr */
	memcpy(bp, cp, len);
	bp += len;
	memcpy(bp, RSTRING(val)->ptr, RSTRING(val)->len);
	bp += RSTRING(val)->len;
	offset = END(0);
	if (BEG(0) == END(0)) {
	    /*
	     * Always consume at least one character of the input string
	     * in order to prevent infinite loops.
	     */
	    if (RSTRING(str)->len <= END(0)) break;
	    len = mbclen2(RSTRING(str)->ptr[END(0)], pat);
	    memcpy(bp, RSTRING(str)->ptr+END(0), len);
	    bp += len;
	    offset = END(0) + len;
	}
	cp = RSTRING(str)->ptr + offset;
	if (offset > RSTRING(str)->len) break;
	beg = rb_reg_search(pat, str, offset, 0);
    } while (beg >= 0);
    if (RSTRING(str)->len > offset) {
	len = bp - buf;
	if (blen - len < RSTRING(str)->len - offset) {
	    blen = len + RSTRING(str)->len - offset;
	    RESIZE_CAPA(dest, blen);
	    buf = RSTRING(dest)->ptr;
	    bp = buf + len;
	}
	memcpy(bp, cp, RSTRING(str)->len - offset);
	bp += RSTRING(str)->len - offset;
    }
    rb_backref_set(match);
    *bp = '\0';
    rb_str_unlocktmp(dest);
    if (bang) {
	str_discard(str);
	FL_UNSET(str, STR_NOCAPA);
	RSTRING(str)->ptr = buf;
	RSTRING(str)->aux.capa = blen;
	RSTRING(dest)->ptr = 0;
	RSTRING(dest)->len = 0;
    }
    else {
	RBASIC(dest)->klass = rb_obj_class(str);
	OBJ_INFECT(dest, str);
	str = dest;
    }
    RSTRING(str)->len = bp - buf;

    if (tainted) OBJ_TAINT(str);
    return str;
}


/*
 *  call-seq:
 *     str.gsub!(pattern, replacement)        => str or nil
 *     str.gsub!(pattern) {|match| block }    => str or nil
 *
 *  Performs the substitutions of <code>String#gsub</code> in place, returning
 *  <i>str</i>, or <code>nil</code> if no substitutions were performed.
 */

static VALUE
rb_str_gsub_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    return str_gsub(argc, argv, str, 1);
}


/*
 *  call-seq:
 *     str.gsub(pattern, replacement)       => new_str
 *     str.gsub(pattern) {|match| block }   => new_str
 *
 *  Returns a copy of <i>str</i> with <em>all</em> occurrences of <i>pattern</i>
 *  replaced with either <i>replacement</i> or the value of the block. The
 *  <i>pattern</i> will typically be a <code>Regexp</code>; if it is a
 *  <code>String</code> then no regular expression metacharacters will be
 *  interpreted (that is <code>/\d/</code> will match a digit, but
 *  <code>'\d'</code> will match a backslash followed by a 'd').
 *
 *  If a string is used as the replacement, special variables from the match
 *  (such as <code>$&</code> and <code>$1</code>) cannot be substituted into it,
 *  as substitution into the string occurs before the pattern match
 *  starts. However, the sequences <code>\1</code>, <code>\2</code>, and so on
 *  may be used to interpolate successive groups in the match.
 *
 *  In the block form, the current match string is passed in as a parameter, and
 *  variables such as <code>$1</code>, <code>$2</code>, <code>$`</code>,
 *  <code>$&</code>, and <code>$'</code> will be set appropriately. The value
 *  returned by the block will be substituted for the match on each call.
 *
 *  The result inherits any tainting in the original string or any supplied
 *  replacement string.
 *
 *     "hello".gsub(/[aeiou]/, '*')              #=> "h*ll*"
 *     "hello".gsub(/([aeiou])/, '<\1>')         #=> "h<e>ll<o>"
 *     "hello".gsub(/./) {|s| s[0].to_s + ' '}   #=> "104 101 108 108 111 "
 */

static VALUE
rb_str_gsub(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    return str_gsub(argc, argv, str, 0);
}


/*
 *  call-seq:
 *     str.replace(other_str)   => str
 *
 *  Replaces the contents and taintedness of <i>str</i> with the corresponding
 *  values in <i>other_str</i>.
 *
 *     s = "hello"         #=> "hello"
 *     s.replace "world"   #=> "world"
 */

static VALUE
rb_str_replace(str, str2)
    VALUE str, str2;
{
    if (str == str2) return str;

    StringValue(str2);
    if (FL_TEST(str2, ELTS_SHARED)) {
	str_discard(str);
	RSTRING(str)->len = RSTRING(str2)->len;
	RSTRING(str)->ptr = RSTRING(str2)->ptr;
	FL_SET(str, ELTS_SHARED);
	FL_UNSET(str, STR_ASSOC);
	RSTRING(str)->aux.shared = RSTRING(str2)->aux.shared;
    }
    else {
	if (str_independent(str)) {
	    rb_str_resize(str, RSTRING(str2)->len);
	    memcpy(RSTRING(str)->ptr, RSTRING(str2)->ptr, RSTRING(str2)->len);
	    if (!RSTRING(str)->ptr) {
		make_null_str(str);
	    }
	}
	else {
	    RSTRING(str)->ptr = RSTRING(str2)->ptr;
	    RSTRING(str)->len = RSTRING(str2)->len;
	    str_make_independent(str);
	}
	if (FL_TEST(str2, STR_ASSOC)) {
	    FL_SET(str, STR_ASSOC);
	    RSTRING(str)->aux.shared = RSTRING(str2)->aux.shared;
	}
    }

    OBJ_INFECT(str, str2);
    return str;
}

static VALUE
uscore_get()
{
    VALUE line;

    line = rb_lastline_get();
    if (TYPE(line) != T_STRING) {
	rb_raise(rb_eTypeError, "$_ value need to be String (%s given)",
		 NIL_P(line) ? "nil" : rb_obj_classname(line));
    }
    return line;
}

/*
 *  call-seq:
 *     sub!(pattern, replacement)    => $_ or nil
 *     sub!(pattern) {|...| block }  => $_ or nil
 *
 *  Equivalent to <code>$_.sub!(<i>args</i>)</code>.
 */

static VALUE
rb_f_sub_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_sub_bang(argc, argv, uscore_get());
}

/*
 *  call-seq:
 *     sub(pattern, replacement)   => $_
 *     sub(pattern) { block }      => $_
 *
 *  Equivalent to <code>$_.sub(<i>args</i>)</code>, except that
 *  <code>$_</code> will be updated if substitution occurs.
 */

static VALUE
rb_f_sub(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str = rb_str_dup(uscore_get());

    if (NIL_P(rb_str_sub_bang(argc, argv, str)))
	return str;
    rb_lastline_set(str);
    return str;
}

/*
 *  call-seq:
 *     gsub!(pattern, replacement)    => string or nil
 *     gsub!(pattern) {|...| block }  => string or nil
 *
 *  Equivalent to <code>Kernel::gsub</code>, except <code>nil</code> is
 *  returned if <code>$_</code> is not modified.
 *
 *     $_ = "quick brown fox"
 *     gsub! /cat/, '*'   #=> nil
 *     $_                 #=> "quick brown fox"
 */

static VALUE
rb_f_gsub_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_gsub_bang(argc, argv, uscore_get());
}

/*
 *  call-seq:
 *     gsub(pattern, replacement)    => string
 *     gsub(pattern) {|...| block }  => string
 *
 *  Equivalent to <code>$_.gsub...</code>, except that <code>$_</code>
 *  receives the modified result.
 *
 *     $_ = "quick brown fox"
 *     gsub /[aeiou]/, '*'   #=> "q**ck br*wn f*x"
 *     $_                    #=> "q**ck br*wn f*x"
 */

static VALUE
rb_f_gsub(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str = rb_str_dup(uscore_get());

    if (NIL_P(rb_str_gsub_bang(argc, argv, str)))
	return str;
    rb_lastline_set(str);
    return str;
}


/*
 *  call-seq:
 *     str.reverse!   => str
 *
 *  Reverses <i>str</i> in place.
 */

static VALUE
rb_str_reverse_bang(str)
    VALUE str;
{
    char *s, *e;
    char c;

    if (RSTRING(str)->len > 1) {
	rb_str_modify(str);
	s = RSTRING(str)->ptr;
	e = s + RSTRING(str)->len - 1;
	while (s < e) {
	    c = *s;
	    *s++ = *e;
	    *e-- = c;
	}
    }
    return str;
}


/*
 *  call-seq:
 *     str.getbyte(index)          => 0 .. 255
 *
 *  returns the <i>index</i>th byte as an integer.
 */
static VALUE
rb_str_getbyte(str, index)
    VALUE str, index;
{
    long pos = NUM2LONG(index);
    long len = RSTRING(str)->len;

    if (pos < -len || len <= pos)
	return Qnil;
    if (pos < 0)
	pos += len;

    return INT2FIX((unsigned char)RSTRING(str)->ptr[pos]);
}


/*
 *  call-seq:
 *     str.setbyte(index, int) => int
 *
 *  modifies the <i>index</i>th byte as <i>int</i>.
 */
static VALUE
rb_str_setbyte(str, index, value)
    VALUE str, index, value;
{
    long pos = NUM2LONG(index);
    long len = RSTRING(str)->len;
    int byte = NUM2INT(value);

    rb_str_modify(str);

    if (pos < -len || len <= pos)
	rb_raise(rb_eIndexError, "index %ld out of string", pos);
    if (pos < 0)
	pos += len;

    RSTRING(str)->ptr[pos] = byte;

    return value;
}


/*
 *  call-seq:
 *     str.reverse   => new_str
 *
 *  Returns a new string with the characters from <i>str</i> in reverse order.
 *
 *     "stressed".reverse   #=> "desserts"
 */

static VALUE
rb_str_reverse(str)
    VALUE str;
{
    VALUE obj;
    char *s, *e, *p;

    if (RSTRING(str)->len <= 1) return rb_str_dup(str);

    obj = rb_str_new5(str, 0, RSTRING(str)->len);
    s = RSTRING(str)->ptr; e = s + RSTRING(str)->len - 1;
    p = RSTRING(obj)->ptr;

    while (e >= s) {
	*p++ = *e--;
    }
    OBJ_INFECT(obj, str);

    return obj;
}


/*
 *  call-seq:
 *     str.include? other_str   => true or false
 *     str.include? fixnum      => true or false
 *
 *  Returns <code>true</code> if <i>str</i> contains the given string or
 *  character.
 *
 *     "hello".include? "lo"   #=> true
 *     "hello".include? "ol"   #=> false
 *     "hello".include? ?h     #=> true
 */

static VALUE
rb_str_include(str, arg)
    VALUE str, arg;
{
    long i;

    if (FIXNUM_P(arg)) {
	if (memchr(RSTRING(str)->ptr, FIX2INT(arg), RSTRING(str)->len))
	    return Qtrue;
	return Qfalse;
    }

    StringValue(arg);
    i = rb_str_index(str, arg, 0);

    if (i == -1) return Qfalse;
    return Qtrue;
}


/*
 *  call-seq:
 *     str.to_i(base=10)   => integer
 *
 *  Returns the result of interpreting leading characters in <i>str</i> as an
 *  integer base <i>base</i> (between 2 and 36). Extraneous characters past the
 *  end of a valid number are ignored. If there is not a valid number at the
 *  start of <i>str</i>, <code>0</code> is returned. This method never raises an
 *  exception.
 *
 *     "12345".to_i             #=> 12345
 *     "99 red balloons".to_i   #=> 99
 *     "0a".to_i                #=> 0
 *     "0a".to_i(16)            #=> 10
 *     "hello".to_i             #=> 0
 *     "1100101".to_i(2)        #=> 101
 *     "1100101".to_i(8)        #=> 294977
 *     "1100101".to_i(10)       #=> 1100101
 *     "1100101".to_i(16)       #=> 17826049
 */

static VALUE
rb_str_to_i(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE b;
    int base;

    rb_scan_args(argc, argv, "01", &b);
    if (argc == 0) base = 10;
    else base = NUM2INT(b);

    if (base < 0) {
	rb_raise(rb_eArgError, "illegal radix %d", base);
    }
    return rb_str_to_inum(str, base, Qfalse);
}


/*
 *  call-seq:
 *     str.to_f   => float
 *
 *  Returns the result of interpreting leading characters in <i>str</i> as a
 *  floating point number. Extraneous characters past the end of a valid number
 *  are ignored. If there is not a valid number at the start of <i>str</i>,
 *  <code>0.0</code> is returned. This method never raises an exception.
 *
 *     "123.45e1".to_f        #=> 1234.5
 *     "45.67 degrees".to_f   #=> 45.67
 *     "thx1138".to_f         #=> 0.0
 */

static VALUE
rb_str_to_f(str)
    VALUE str;
{
    return rb_float_new(rb_str_to_dbl(str, Qfalse));
}


/*
 *  call-seq:
 *     str.to_s     => str
 *     str.to_str   => str
 *
 *  Returns the receiver.
 */

static VALUE
rb_str_to_s(str)
    VALUE str;
{
    if (rb_obj_class(str) != rb_cString) {
	VALUE dup = str_alloc(rb_cString);
	rb_str_replace(dup, str);
	return dup;
    }
    return str;
}

/*
 * call-seq:
 *   str.inspect   => string
 *
 * Returns a printable version of _str_, with special characters
 * escaped.
 *
 *    str = "hello"
 *    str[3] = 8
 *    str.inspect       #=> "hel\010o"
 */

VALUE
rb_str_inspect(str)
    VALUE str;
{
    char *p, *pend;
    VALUE result = rb_str_buf_new2("\"");
    char s[5];

    p = RSTRING(str)->ptr; pend = p + RSTRING(str)->len;
    while (p < pend) {
	char c = *p++;
	int len;
	if (ismbchar(c) && p - 1 + (len = mbclen(c)) <= pend) {
	    rb_str_buf_cat(result, p - 1, len);
	    p += len - 1;
	}
	else if (c == '"'|| c == '\\' || (c == '#' && IS_EVSTR(p, pend))) {
	    s[0] = '\\'; s[1] = c;
	    rb_str_buf_cat(result, s, 2);
	}
	else if (ISPRINT(c)) {
	    s[0] = c;
	    rb_str_buf_cat(result, s, 1);
	}
	else if (c == '\n') {
	    s[0] = '\\'; s[1] = 'n';
	    rb_str_buf_cat(result, s, 2);
	}
	else if (c == '\r') {
	    s[0] = '\\'; s[1] = 'r';
	    rb_str_buf_cat(result, s, 2);
	}
	else if (c == '\t') {
	    s[0] = '\\'; s[1] = 't';
	    rb_str_buf_cat(result, s, 2);
	}
	else if (c == '\f') {
	    s[0] = '\\'; s[1] = 'f';
	    rb_str_buf_cat(result, s, 2);
	}
	else if (c == '\013') {
	    s[0] = '\\'; s[1] = 'v';
	    rb_str_buf_cat(result, s, 2);
	}
	else if (c == '\010') {
	    s[0] = '\\'; s[1] = 'b';
	    rb_str_buf_cat(result, s, 2);
	}
	else if (c == '\007') {
	    s[0] = '\\'; s[1] = 'a';
	    rb_str_buf_cat(result, s, 2);
	}
	else if (c == 033) {
	    s[0] = '\\'; s[1] = 'e';
	    rb_str_buf_cat(result, s, 2);
	}
	else {
	    sprintf(s, "\\%03o", c & 0377);
	    rb_str_buf_cat2(result, s);
	}
    }
    rb_str_buf_cat2(result, "\"");

    OBJ_INFECT(result, str);
    return result;
}


/*
 *  call-seq:
 *     str.dump   => new_str
 *
 *  Produces a version of <i>str</i> with all nonprinting characters replaced by
 *  <code>\nnn</code> notation and all special characters escaped.
 */

VALUE
rb_str_dump(str)
    VALUE str;
{
    long len;
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
	  case '\t': case '\f':
	  case '\013': case '\010': case '\007': case '\033':
	    len += 2;
	    break;

	  case '#':
	    len += IS_EVSTR(p, pend) ? 2 : 1;
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

    result = rb_str_new5(str, 0, len);
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
	    if (IS_EVSTR(p, pend)) *q++ = '\\';
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
	else if (c == '\010') {
	    *q++ = '\\';
	    *q++ = 'b';
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

    OBJ_INFECT(result, str);
    return result;
}


static VALUE rb_str_upcase_bang _((VALUE));

/*
 *  call-seq:
 *     str.upcase!   => str or nil
 *
 *  Upcases the contents of <i>str</i>, returning <code>nil</code> if no changes
 *  were made.
 */

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
	else if (ISLOWER(*s)) {
	    *s = toupper(*s);
	    modify = 1;
	}
	s++;
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.upcase   => new_str
 *
 *  Returns a copy of <i>str</i> with all lowercase letters replaced with their
 *  uppercase counterparts. The operation is locale insensitive---only
 *  characters ``a'' to ``z'' are affected.
 *
 *     "hEllO".upcase   #=> "HELLO"
 */

static VALUE
rb_str_upcase(str)
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_upcase_bang(str);
    return str;
}


static VALUE rb_str_downcase_bang _((VALUE));

/*
 *  call-seq:
 *     str.downcase!   => str or nil
 *
 *  Downcases the contents of <i>str</i>, returning <code>nil</code> if no
 *  changes were made.
 */

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


/*
 *  call-seq:
 *     str.downcase   => new_str
 *
 *  Returns a copy of <i>str</i> with all uppercase letters replaced with their
 *  lowercase counterparts. The operation is locale insensitive---only
 *  characters ``A'' to ``Z'' are affected.
 *
 *     "hEllO".downcase   #=> "hello"
 */

static VALUE
rb_str_downcase(str)
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_downcase_bang(str);
    return str;
}


static VALUE rb_str_capitalize_bang _((VALUE));

/*
 *  call-seq:
 *     str.capitalize!   => str or nil
 *
 *  Modifies <i>str</i> by converting the first character to uppercase and the
 *  remainder to lowercase. Returns <code>nil</code> if no changes are made.
 *
 *     a = "hello"
 *     a.capitalize!   #=> "Hello"
 *     a               #=> "Hello"
 *     a.capitalize!   #=> nil
 */

static VALUE
rb_str_capitalize_bang(str)
    VALUE str;
{
    char *s, *send;
    int modify = 0;

    rb_str_modify(str);
    if (RSTRING(str)->len == 0 || !RSTRING(str)->ptr) return Qnil;
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


/*
 *  call-seq:
 *     str.capitalize   => new_str
 *
 *  Returns a copy of <i>str</i> with the first character converted to uppercase
 *  and the remainder to lowercase.
 *
 *     "hello".capitalize    #=> "Hello"
 *     "HELLO".capitalize    #=> "Hello"
 *     "123ABC".capitalize   #=> "123abc"
 */

static VALUE
rb_str_capitalize(str)
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_capitalize_bang(str);
    return str;
}


static VALUE rb_str_swapcase_bang _((VALUE));

/*
 *  call-seq:
 *     str.swapcase!   => str or nil
 *
 *  Equivalent to <code>String#swapcase</code>, but modifies the receiver in
 *  place, returning <i>str</i>, or <code>nil</code> if no changes were made.
 */

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


/*
 *  call-seq:
 *     str.swapcase   => new_str
 *
 *  Returns a copy of <i>str</i> with uppercase alphabetic characters converted
 *  to lowercase and lowercase characters converted to uppercase.
 *
 *     "Hello".swapcase          #=> "hELLO"
 *     "cYbEr_PuNk11".swapcase   #=> "CyBeR_pUnK11"
 */

static VALUE
rb_str_swapcase(str)
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_swapcase_bang(str);
    return str;
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
	    if (t->p < t->pend - 1 && *t->p == '\\') {
		t->p++;
	    }
	    t->now = *(USTR)t->p++;
	    if (t->p < t->pend - 1 && *t->p == '-') {
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

static VALUE rb_str_delete_bang _((int,VALUE*,VALUE));

static VALUE
tr_trans(str, src, repl, sflag)
    VALUE str, src, repl;
    int sflag;
{
    struct tr trsrc, trrepl;
    int cflag = 0;
    int trans[256];
    int i, c, modify = 0;
    char *s, *send;

    StringValue(src);
    StringValue(repl);
    if (RSTRING(str)->len == 0 || !RSTRING(str)->ptr) return Qnil;
    trsrc.p = RSTRING(src)->ptr; trsrc.pend = trsrc.p + RSTRING(src)->len;
    if (RSTRING(src)->len >= 2 && RSTRING(src)->ptr[0] == '^') {
	cflag++;
	trsrc.p++;
    }
    if (RSTRING(repl)->len == 0) {
	return rb_str_delete_bang(1, &src, str);
    }
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
	    trans[c & 0xff] = -1;
	}
	while ((c = trnext(&trrepl)) >= 0)
	    /* retrieve last replacer */;
	for (i=0; i<256; i++) {
	    if (trans[i] >= 0) {
		trans[i] = trrepl.now;
	    }
	}
    }
    else {
	int r;

	for (i=0; i<256; i++) {
	    trans[i] = -1;
	}
	while ((c = trnext(&trsrc)) >= 0) {
	    r = trnext(&trrepl);
	    if (r == -1) r = trrepl.now;
	    trans[c & 0xff] = r;
	}
    }

    rb_str_modify(str);
    s = RSTRING(str)->ptr; send = s + RSTRING(str)->len;
    if (sflag) {
	char *t = s;
	int c0, last = -1;

	while (s < send) {
	    c0 = *s++;
	    if ((c = trans[c0 & 0xff]) >= 0) {
		if (last == c) continue;
		last = c;
		*t++ = c & 0xff;
		modify = 1;
	    }
	    else {
		last = -1;
		*t++ = c0;
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
	    if ((c = trans[*s & 0xff]) >= 0) {
		*s = c & 0xff;
		modify = 1;
	    }
	    s++;
	}
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.tr!(from_str, to_str)   => str or nil
 *
 *  Translates <i>str</i> in place, using the same rules as
 *  <code>String#tr</code>. Returns <i>str</i>, or <code>nil</code> if no
 *  changes were made.
 */

static VALUE
rb_str_tr_bang(str, src, repl)
    VALUE str, src, repl;
{
    return tr_trans(str, src, repl, 0);
}


/*
 *  call-seq:
 *     str.tr(from_str, to_str)   => new_str
 *
 *  Returns a copy of <i>str</i> with the characters in <i>from_str</i> replaced
 *  by the corresponding characters in <i>to_str</i>. If <i>to_str</i> is
 *  shorter than <i>from_str</i>, it is padded with its last character. Both
 *  strings may use the c1--c2 notation to denote ranges of characters, and
 *  <i>from_str</i> may start with a <code>^</code>, which denotes all
 *  characters except those listed.
 *
 *     "hello".tr('aeiou', '*')    #=> "h*ll*"
 *     "hello".tr('^aeiou', '*')   #=> "*e**o"
 *     "hello".tr('el', 'ip')      #=> "hippo"
 *     "hello".tr('a-y', 'b-z')    #=> "ifmmp"
 */

static VALUE
rb_str_tr(str, src, repl)
    VALUE str, src, repl;
{
    str = rb_str_dup(str);
    tr_trans(str, src, repl, 0);
    return str;
}

static void
tr_setup_table(str, table, init)
    VALUE str;
    char table[256];
    int init;
{
    char buf[256];
    struct tr tr;
    int i, c;
    int cflag = 0;

    tr.p = RSTRING(str)->ptr; tr.pend = tr.p + RSTRING(str)->len;
    tr.gen = tr.now = tr.max = 0;
    if (RSTRING(str)->len > 1 && RSTRING(str)->ptr[0] == '^') {
	cflag = 1;
	tr.p++;
    }

    if (init) {
	for (i=0; i<256; i++) {
	    table[i] = 1;
	}
    }
    for (i=0; i<256; i++) {
	buf[i] = cflag;
    }
    while ((c = trnext(&tr)) >= 0) {
	buf[c & 0xff] = !cflag;
    }
    for (i=0; i<256; i++) {
	table[i] = table[i] && buf[i];
    }
}


/*
 *  call-seq:
 *     str.delete!([other_str]+>)   => str or nil
 *
 *  Performs a <code>delete</code> operation in place, returning <i>str</i>, or
 *  <code>nil</code> if <i>str</i> was not modified.
 */

static VALUE
rb_str_delete_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    char *s, *send, *t;
    char squeez[256];
    int modify = 0;
    int init = 1;
    int i;

    if (argc < 1) {
	rb_raise(rb_eArgError, "wrong number of arguments");
    }
    for (i=0; i<argc; i++) {
	VALUE s = argv[i];

	StringValue(s);
	tr_setup_table(s, squeez, init);
	init = 0;
    }

    rb_str_modify(str);
    s = t = RSTRING(str)->ptr;
    if (!s || RSTRING(str)->len == 0) return Qnil;
    send = s + RSTRING(str)->len;
    while (s < send) {
	if (squeez[*s & 0xff])
	    modify = 1;
	else
	    *t++ = *s;
	s++;
    }
    *t = '\0';
    RSTRING(str)->len = t - RSTRING(str)->ptr;

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.delete([other_str]+)   => new_str
 *
 *  Returns a copy of <i>str</i> with all characters in the intersection of its
 *  arguments deleted. Uses the same rules for building the set of characters as
 *  <code>String#count</code>.
 *
 *     "hello".delete "l","lo"        #=> "heo"
 *     "hello".delete "lo"            #=> "he"
 *     "hello".delete "aeiou", "^e"   #=> "hell"
 *     "hello".delete "ej-m"          #=> "ho"
 */

static VALUE
rb_str_delete(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_delete_bang(argc, argv, str);
    return str;
}


/*
 *  call-seq:
 *     str.squeeze!([other_str]*)   => str or nil
 *
 *  Squeezes <i>str</i> in place, returning either <i>str</i>, or
 *  <code>nil</code> if no changes were made.
 */

static VALUE
rb_str_squeeze_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    char squeez[256];
    char *s, *send, *t;
    int c, save, modify = 0;
    int init = 1;
    int i;

    if (argc == 0) {
	for (i=0; i<256; i++) {
	    squeez[i] = 1;
	}
    }
    else {
	for (i=0; i<argc; i++) {
	    VALUE s = argv[i];

	    StringValue(s);
	    tr_setup_table(s, squeez, init);
	    init = 0;
	}
    }

    rb_str_modify(str);
    s = t = RSTRING(str)->ptr;
    if (!s || RSTRING(str)->len == 0) return Qnil;
    send = s + RSTRING(str)->len;
    save = -1;
    while (s < send) {
	c = *s++ & 0xff;
	if (c != save || !squeez[c]) {
	    *t++ = save = c;
	}
    }
    *t = '\0';
    if (t - RSTRING(str)->ptr != RSTRING(str)->len) {
	RSTRING(str)->len = t - RSTRING(str)->ptr;
	modify = 1;
    }

    if (modify) return str;
    return Qnil;
}


/*
 *  call-seq:
 *     str.squeeze([other_str]*)    => new_str
 *
 *  Builds a set of characters from the <i>other_str</i> parameter(s) using the
 *  procedure described for <code>String#count</code>. Returns a new string
 *  where runs of the same character that occur in this set are replaced by a
 *  single character. If no arguments are given, all runs of identical
 *  characters are replaced by a single character.
 *
 *     "yellow moon".squeeze                  #=> "yelow mon"
 *     "  now   is  the".squeeze(" ")         #=> " now is the"
 *     "putters shoot balls".squeeze("m-z")   #=> "puters shot balls"
 */

static VALUE
rb_str_squeeze(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_squeeze_bang(argc, argv, str);
    return str;
}


/*
 *  call-seq:
 *     str.tr_s!(from_str, to_str)   => str or nil
 *
 *  Performs <code>String#tr_s</code> processing on <i>str</i> in place,
 *  returning <i>str</i>, or <code>nil</code> if no changes were made.
 */

static VALUE
rb_str_tr_s_bang(str, src, repl)
    VALUE str, src, repl;
{
    return tr_trans(str, src, repl, 1);
}


/*
 *  call-seq:
 *     str.tr_s(from_str, to_str)   => new_str
 *
 *  Processes a copy of <i>str</i> as described under <code>String#tr</code>,
 *  then removes duplicate characters in regions that were affected by the
 *  translation.
 *
 *     "hello".tr_s('l', 'r')     #=> "hero"
 *     "hello".tr_s('el', '*')    #=> "h*o"
 *     "hello".tr_s('el', 'hx')   #=> "hhxo"
 */

static VALUE
rb_str_tr_s(str, src, repl)
    VALUE str, src, repl;
{
    str = rb_str_dup(str);
    tr_trans(str, src, repl, 1);
    return str;
}


/*
 *  call-seq:
 *     str.count([other_str]+)   => fixnum
 *
 *  Each <i>other_str</i> parameter defines a set of characters to count.  The
 *  intersection of these sets defines the characters to count in
 *  <i>str</i>. Any <i>other_str</i> that starts with a caret (^) is
 *  negated. The sequence c1--c2 means all characters between c1 and c2.
 *
 *     a = "hello world"
 *     a.count "lo"            #=> 5
 *     a.count "lo", "o"       #=> 2
 *     a.count "hello", "^l"   #=> 4
 *     a.count "ej-m"          #=> 4
 */

static VALUE
rb_str_count(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    char table[256];
    char *s, *send;
    int init = 1;
    int i;

    if (argc < 1) {
	rb_raise(rb_eArgError, "wrong number of arguments");
    }
    for (i=0; i<argc; i++) {
	VALUE s = argv[i];

	StringValue(s);
	tr_setup_table(s, table, init);
	init = 0;
    }

    s = RSTRING(str)->ptr;
    if (!s || RSTRING(str)->len == 0) return INT2FIX(0);
    send = s + RSTRING(str)->len;
    i = 0;
    while (s < send) {
	if (table[*s++ & 0xff]) {
	    i++;
	}
    }
    return INT2NUM(i);
}


/*
 *  call-seq:
 *     str.split(pattern=$;, [limit])   => anArray
 *
 *  Divides <i>str</i> into substrings based on a delimiter, returning an array
 *  of these substrings.
 *
 *  If <i>pattern</i> is a <code>String</code>, then its contents are used as
 *  the delimiter when splitting <i>str</i>. If <i>pattern</i> is a single
 *  space, <i>str</i> is split on whitespace, with leading whitespace and runs
 *  of contiguous whitespace characters ignored.
 *
 *  If <i>pattern</i> is a <code>Regexp</code>, <i>str</i> is divided where the
 *  pattern matches. Whenever the pattern matches a zero-length string,
 *  <i>str</i> is split into individual characters. If
 *  <i>pattern</i> includes one or more capturing subpatterns,
 *  these will be returned in the array returned by split.
 *
 *  If <i>pattern</i> is omitted, the value of <code>$;</code> is used.  If
 *  <code>$;</code> is <code>nil</code> (which is the default), <i>str</i> is
 *  split on whitespace as if ` ' were specified.
 *
 *  If the <i>limit</i> parameter is omitted, trailing null fields are
 *  suppressed. If <i>limit</i> is a positive number, at most that number of
 *  fields will be returned (if <i>limit</i> is <code>1</code>, the entire
 *  string is returned as the only entry in an array). If negative, there is no
 *  limit to the number of fields returned, and trailing null fields are not
 *  suppressed.
 *
 *     " now's  the time".split        #=> ["now's", "the", "time"]
 *     " now's  the time".split(' ')   #=> ["now's", "the", "time"]
 *     " now's  the time".split(/ /)   #=> ["", "now's", "", "the", "time"]
 *     "1, 2.34,56, 7".split(%r{,\s*}) #=> ["1", "2.34", "56", "7"]
 *     "1, 2.34,56".split(%r{(,\s*)})  #=> ["1", ", ", "2.34", ",", "56"]
 *     "wd :sp: wd".split(/(:(\w+):)/) #=> ["wd ", ":sp:", "sp", " wd"]
 *     "hello".split(//)               #=> ["h", "e", "l", "l", "o"]
 *     "hello".split(//, 3)            #=> ["h", "e", "llo"]
 *     "hi mom".split(%r{\s*})         #=> ["h", "i", "m", "o", "m"]
 *
 *     "mellow yellow".split("ello")   #=> ["m", "w y", "w"]
 *     "1,2,,3,4,,".split(',')         #=> ["1", "2", "", "3", "4"]
 *     "1,2,,3,4,,".split(',', 4)      #=> ["1", "2", "", "3,4,,"]
 *     "1,2,,3,4,,".split(',', -4)     #=> ["1", "2", "", "3", "4", "", ""]
 */

static VALUE
rb_str_split_m(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE spat;
    VALUE limit;
    int awk_split = Qfalse;
    long beg, end, i = 0;
    int lim = 0;
    VALUE result, tmp;

    if (rb_scan_args(argc, argv, "02", &spat, &limit) == 2) {
	lim = NUM2INT(limit);
	if (lim <= 0) limit = Qnil;
	else if (lim == 1) {
	    if (RSTRING(str)->len == 0)
		return rb_ary_new2(0);
	    return rb_ary_new3(1, str);
	}
	i = 1;
    }

    if (NIL_P(spat)) {
	if (!NIL_P(rb_fs)) {
	    spat = rb_fs;
	    goto fs_set;
	}
	awk_split = Qtrue;
    }
    else {
      fs_set:
	if (TYPE(spat) == T_STRING && RSTRING(spat)->len == 1) {
	    if (RSTRING(spat)->ptr[0] == ' ') {
		awk_split = Qtrue;
	    }
	    else {
		spat = rb_reg_regcomp(rb_reg_quote(spat));
	    }
	}
	else {
	    spat = get_pat(spat, 1);
	}
    }

    result = rb_ary_new();
    beg = 0;
    if (awk_split) {
	char *ptr = RSTRING(str)->ptr;
	long len = RSTRING(str)->len;
	char *eptr = ptr + len;
	int skip = 1;

	for (end = beg = 0; ptr<eptr; ptr++) {
	    if (skip) {
		if (ISSPACE(*ptr)) {
		    beg++;
		}
		else {
		    end = beg+1;
		    skip = 0;
		    if (!NIL_P(limit) && lim <= i) break;
		}
	    }
	    else {
		if (ISSPACE(*ptr)) {
		    rb_ary_push(result, rb_str_substr(str, beg, end-beg));
		    skip = 1;
		    beg = end + 1;
		    if (!NIL_P(limit)) ++i;
		}
		else {
		    end++;
		}
	    }
	}
    }
    else {
	long start = beg;
	long idx;
	int last_null = 0;
	struct re_registers *regs;

	while ((end = rb_reg_search(spat, str, start, 0)) >= 0) {
	    regs = RMATCH(rb_backref_get())->regs;
	    if (start == end && BEG(0) == END(0)) {
		if (!RSTRING(str)->ptr) {
		    rb_ary_push(result, rb_str_new("", 0));
		    break;
		}
		else if (last_null == 1) {
		    rb_ary_push(result, rb_str_substr(str, beg, mbclen2(RSTRING(str)->ptr[beg],spat)));
		    beg = start;
		}
		else {
		    start += mbclen2(RSTRING(str)->ptr[start],spat);
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
		    tmp = rb_str_new5(str, 0, 0);
		else
		    tmp = rb_str_substr(str, BEG(idx), END(idx)-BEG(idx));
		rb_ary_push(result, tmp);
	    }
	    if (!NIL_P(limit) && lim <= ++i) break;
	}
    }
    if (RSTRING(str)->len > 0 && (!NIL_P(limit) || RSTRING(str)->len > beg || lim < 0)) {
	if (RSTRING(str)->len == beg)
	    tmp = rb_str_new5(str, 0, 0);
	else
	    tmp = rb_str_substr(str, beg, RSTRING(str)->len-beg);
	rb_ary_push(result, tmp);
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

    StringValue(str);
    sep = rb_str_new2(sep0);
    return rb_str_split_m(1, &sep, str);
}

/*
 *  call-seq:
 *     split([pattern [, limit]])    => array
 *
 *  Equivalent to <code>$_.split(<i>pattern</i>, <i>limit</i>)</code>.
 *  See <code>String#split</code>.
 */

static VALUE
rb_f_split(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_split_m(argc, argv, uscore_get());
}

/*
 *  Document-method: lines
 *  call-seq:
 *     str.lines(separator=$/)   => anEnumerator
 *     str.lines(separator=$/) {|substr| block }        => str
 *
 *  Returns an enumerator that gives each line in the string.  If a block is
 *  given, it iterates over each line in the string.
 *
 *     "foo\nbar\n".lines.to_a   #=> ["foo\n", "bar\n"]
 *     "foo\nb ar".lines.sort    #=> ["b ar", "foo\n"]
 */

/*
 *  call-seq:
 *     str.each_line(separator=$/) {|substr| block }   => str
 *
 *  Splits <i>str</i> using the supplied parameter as the record separator
 *  (<code>$/</code> by default), passing each substring in turn to the supplied
 *  block. If a zero-length record separator is supplied, the string is split
 *  into paragraphs delimited by multiple successive newlines.
 *
 *     print "Example one\n"
 *     "hello\nworld".each {|s| p s}
 *     print "Example two\n"
 *     "hello\nworld".each('l') {|s| p s}
 *     print "Example three\n"
 *     "hello\n\n\nworld".each('') {|s| p s}
 *
 *  <em>produces:</em>
 *
 *     Example one
 *     "hello\n"
 *     "world"
 *     Example two
 *     "hel"
 *     "l"
 *     "o\nworl"
 *     "d"
 *     Example three
 *     "hello\n\n\n"
 *     "world"
 */

static VALUE
rb_str_each_line(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE rs;
    int newline;
    char *p = RSTRING(str)->ptr, *pend = p + RSTRING(str)->len, *s;
    char *ptr = p;
    long len = RSTRING(str)->len, rslen;
    VALUE line;

    if (rb_scan_args(argc, argv, "01", &rs) == 0) {
	rs = rb_rs;
    }
    RETURN_ENUMERATOR(str, argc, argv);
    if (NIL_P(rs)) {
	rb_yield(str);
	return str;
    }
    StringValue(rs);
    rslen = RSTRING(rs)->len;
    if (rslen == 0) {
	newline = '\n';
    }
    else {
	newline = RSTRING(rs)->ptr[rslen-1];
    }

    for (s = p, p += rslen; p < pend; p++) {
	if (rslen == 0 && *p == '\n') {
	    if (*++p != '\n') continue;
	    while (*p == '\n') p++;
	}
	if (RSTRING(str)->ptr < p && p[-1] == newline &&
	    (rslen <= 1 ||
	     rb_memcmp(RSTRING(rs)->ptr, p-rslen, rslen) == 0)) {
	    line = rb_str_new5(str, s, p - s);
	    OBJ_INFECT(line, str);
	    rb_yield(line);
	    str_mod_check(str, ptr, len);
	    s = p;
	}
    }

    if (s != pend) {
	if (p > pend) p = pend;
	line = rb_str_new5(str, s, p - s);
	OBJ_INFECT(line, str);
	rb_yield(line);
    }

    return str;
}

/*
 *  call-seq:
 *     str.each(separator=$/) {|substr| block }        => str
 *
 *
 */
static VALUE
rb_str_each(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    rb_warning("treating String as Enumerable object is deprecated; use String#each_line/lines");
    return rb_str_each_line(argc, argv, str);
}


/*
 *  Document-method: bytes
 *  call-seq:
 *     str.bytes   => anEnumerator
 *     str.bytes {|fixnum| block }    => str
 *
 *  Returns an enumerator that gives each byte in the string.  If a block is
 *  given, it iterates over each byte in the string.
 *
 *     "hello".bytes.to_a        #=> [104, 101, 108, 108, 111]
 */

/*
 *  call-seq:
 *     str.each_byte {|fixnum| block }    => str
 *
 *  Passes each byte in <i>str</i> to the given block.
 *
 *     "hello".each_byte {|c| print c, ' ' }
 *
 *  <em>produces:</em>
 *
 *     104 101 108 108 111
 */

static VALUE
rb_str_each_byte(str)
    VALUE str;
{
    long i;

    RETURN_ENUMERATOR(str, 0, 0);
    for (i=0; i<RSTRING(str)->len; i++) {
	rb_yield(INT2FIX(RSTRING(str)->ptr[i] & 0xff));
    }
    return str;
}


/*
 *  Document-method: chars
 *  call-seq:
 *     str.chars                   => anEnumerator
 *     str.chars {|substr| block } => str
 *
 *  Returns an enumerator that gives each character in the string.
 *  If a block is given, it iterates over each character in the string.
 *
 *     "foo".chars.to_a   #=> ["f","o","o"]
 */

/*
 *  Document-method: each_char
 *  call-seq:
 *     str.each_char {|cstr| block }    => str
 *
 *  Passes each character in <i>str</i> to the given block.
 *
 *     "hello".each_char {|c| print c, ' ' }
 *
 *  <em>produces:</em>
 *
 *     h e l l o
 */

static VALUE
rb_str_each_char(str)
    VALUE str;
{
    int i, len, n;
    const char *ptr;

    RETURN_ENUMERATOR(str, 0, 0);
    str = rb_str_new4(str);
    ptr = RSTRING(str)->ptr;
    len = RSTRING(str)->len;
    for (i = 0; i < len; i += n) {
        n = mbclen(ptr[i]);
        rb_yield(rb_str_substr(str, i, n));
    }
    return str;
}


/*
 *  call-seq:
 *     str.chop!   => str or nil
 *
 *  Processes <i>str</i> as for <code>String#chop</code>, returning <i>str</i>,
 *  or <code>nil</code> if <i>str</i> is the empty string.  See also
 *  <code>String#chomp!</code>.
 */

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


/*
 *  call-seq:
 *     str.chop   => new_str
 *
 *  Returns a new <code>String</code> with the last character removed.  If the
 *  string ends with <code>\r\n</code>, both characters are removed. Applying
 *  <code>chop</code> to an empty string returns an empty
 *  string. <code>String#chomp</code> is often a safer alternative, as it leaves
 *  the string unchanged if it doesn't end in a record separator.
 *
 *     "string\r\n".chop   #=> "string"
 *     "string\n\r".chop   #=> "string\n"
 *     "string\n".chop     #=> "string"
 *     "string".chop       #=> "strin"
 *     "x".chop.chop       #=> ""
 */

static VALUE
rb_str_chop(str)
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_chop_bang(str);
    return str;
}


/*
 *  call-seq:
 *     chop!    => $_ or nil
 *
 *  Equivalent to <code>$_.chop!</code>.
 *
 *     a  = "now\r\n"
 *     $_ = a
 *     chop!   #=> "now"
 *     chop!   #=> "no"
 *     chop!   #=> "n"
 *     chop!   #=> ""
 *     chop!   #=> nil
 *     $_      #=> ""
 *     a       #=> ""
 */

static VALUE
rb_f_chop_bang(str)
    VALUE str;
{
    return rb_str_chop_bang(uscore_get());
}

/*
 *  call-seq:
 *     chop   => string
 *
 *  Equivalent to <code>($_.dup).chop!</code>, except <code>nil</code>
 *  is never returned. See <code>String#chop!</code>.
 *
 *     a  =  "now\r\n"
 *     $_ = a
 *     chop   #=> "now"
 *     $_     #=> "now"
 *     chop   #=> "no"
 *     chop   #=> "n"
 *     chop   #=> ""
 *     chop   #=> ""
 *     a      #=> "now\r\n"
 */

static VALUE
rb_f_chop()
{
    VALUE str = uscore_get();

    if (RSTRING(str)->len > 0) {
	str = rb_str_dup(str);
	rb_str_chop_bang(str);
	rb_lastline_set(str);
    }
    return str;
}


/*
 *  call-seq:
 *     str.chomp!(separator=$/)   => str or nil
 *
 *  Modifies <i>str</i> in place as described for <code>String#chomp</code>,
 *  returning <i>str</i>, or <code>nil</code> if no modifications were made.
 */

static VALUE
rb_str_chomp_bang(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE rs;
    int newline;
    char *p;
    long len, rslen;

    if (rb_scan_args(argc, argv, "01", &rs) == 0) {
	len = RSTRING(str)->len;
	if (len == 0) return Qnil;
	p = RSTRING(str)->ptr;
	rs = rb_rs;
	if (rs == rb_default_rs) {
	  smart_chomp:
	    rb_str_modify(str);
	    if (RSTRING(str)->ptr[len-1] == '\n') {
		RSTRING(str)->len--;
		if (RSTRING(str)->len > 0 &&
		    RSTRING(str)->ptr[RSTRING(str)->len-1] == '\r') {
		    RSTRING(str)->len--;
		}
	    }
	    else if (RSTRING(str)->ptr[len-1] == '\r') {
		RSTRING(str)->len--;
	    }
	    else {
		return Qnil;
	    }
	    RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
	    return str;
	}
    }
    if (NIL_P(rs)) return Qnil;
    StringValue(rs);
    len = RSTRING(str)->len;
    if (len == 0) return Qnil;
    p = RSTRING(str)->ptr;
    rslen = RSTRING(rs)->len;
    if (rslen == 0) {
	while (len>0 && p[len-1] == '\n') {
	    len--;
	    if (len>0 && p[len-1] == '\r')
		len--;
	}
	if (len < RSTRING(str)->len) {
	    rb_str_modify(str);
	    RSTRING(str)->len = len;
	    RSTRING(str)->ptr[len] = '\0';
	    return str;
	}
	return Qnil;
    }
    if (rslen > len) return Qnil;
    newline = RSTRING(rs)->ptr[rslen-1];
    if (rslen == 1 && newline == '\n')
	goto smart_chomp;

    if (p[len-1] == newline &&
	(rslen <= 1 ||
	 rb_memcmp(RSTRING(rs)->ptr, p+len-rslen, rslen) == 0)) {
	rb_str_modify(str);
	RSTRING(str)->len -= rslen;
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.chomp(separator=$/)   => new_str
 *
 *  Returns a new <code>String</code> with the given record separator removed
 *  from the end of <i>str</i> (if present). If <code>$/</code> has not been
 *  changed from the default Ruby record separator, then <code>chomp</code> also
 *  removes carriage return characters (that is it will remove <code>\n</code>,
 *  <code>\r</code>, and <code>\r\n</code>).
 *
 *     "hello".chomp            #=> "hello"
 *     "hello\n".chomp          #=> "hello"
 *     "hello\r\n".chomp        #=> "hello"
 *     "hello\n\r".chomp        #=> "hello\n"
 *     "hello\r".chomp          #=> "hello"
 *     "hello \n there".chomp   #=> "hello \n there"
 *     "hello".chomp("llo")     #=> "he"
 */

static VALUE
rb_str_chomp(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_chomp_bang(argc, argv, str);
    return str;
}

/*
 *  call-seq:
 *     chomp!             => $_ or nil
 *     chomp!(string)     => $_ or nil
 *
 *  Equivalent to <code>$_.chomp!(<em>string</em>)</code>. See
 *  <code>String#chomp!</code>
 *
 *     $_ = "now\n"
 *     chomp!       #=> "now"
 *     $_           #=> "now"
 *     chomp! "x"   #=> nil
 *     $_           #=> "now"
 */

static VALUE
rb_f_chomp_bang(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_chomp_bang(argc, argv, uscore_get());
}

/*
 *  call-seq:
 *     chomp            => $_
 *     chomp(string)    => $_
 *
 *  Equivalent to <code>$_ = $_.chomp(<em>string</em>)</code>. See
 *  <code>String#chomp</code>.
 *
 *     $_ = "now\n"
 *     chomp         #=> "now"
 *     $_            #=> "now"
 *     chomp "ow"    #=> "n"
 *     $_            #=> "n"
 *     chomp "xxx"   #=> "n"
 *     $_            #=> "n"
 */

static VALUE
rb_f_chomp(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str = uscore_get();
    VALUE dup = rb_str_dup(str);

    if (NIL_P(rb_str_chomp_bang(argc, argv, dup)))
	return str;
    rb_lastline_set(dup);
    return dup;
}


/*
 *  call-seq:
 *     str.lstrip!   => self or nil
 *
 *  Removes leading whitespace from <i>str</i>, returning <code>nil</code> if no
 *  change was made. See also <code>String#rstrip!</code> and
 *  <code>String#strip!</code>.
 *
 *     "  hello  ".lstrip   #=> "hello  "
 *     "hello".lstrip!      #=> nil
 */

static VALUE
rb_str_lstrip_bang(str)
    VALUE str;
{
    char *s, *t, *e;

    s = RSTRING(str)->ptr;
    if (!s || RSTRING(str)->len == 0) return Qnil;
    e = t = s + RSTRING(str)->len;
    /* remove spaces at head */
    while (s < t && ISSPACE(*s)) s++;

    if (s > RSTRING(str)->ptr) {
	rb_str_modify(str);
	RSTRING(str)->len = t-s;
	memmove(RSTRING(str)->ptr, s, RSTRING(str)->len);
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.lstrip   => new_str
 *
 *  Returns a copy of <i>str</i> with leading whitespace removed. See also
 *  <code>String#rstrip</code> and <code>String#strip</code>.
 *
 *     "  hello  ".lstrip   #=> "hello  "
 *     "hello".lstrip       #=> "hello"
 */

static VALUE
rb_str_lstrip(str)
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_lstrip_bang(str);
    return str;
}


/*
 *  call-seq:
 *     str.rstrip!   => self or nil
 *
 *  Removes trailing whitespace from <i>str</i>, returning <code>nil</code> if
 *  no change was made. See also <code>String#lstrip!</code> and
 *  <code>String#strip!</code>.
 *
 *     "  hello  ".rstrip   #=> "  hello"
 *     "hello".rstrip!      #=> nil
 */

static VALUE
rb_str_rstrip_bang(str)
    VALUE str;
{
    char *s, *t, *e;

    s = RSTRING(str)->ptr;
    if (!s || RSTRING(str)->len == 0) return Qnil;
    e = t = s + RSTRING(str)->len;

    /* remove trailing '\0's */
    while (s < t && t[-1] == '\0') t--;

    /* remove trailing spaces */
    while (s < t && ISSPACE(*(t-1))) t--;

    if (t < e) {
	rb_str_modify(str);
	RSTRING(str)->len = t-s;
	RSTRING(str)->ptr[RSTRING(str)->len] = '\0';
	return str;
    }
    return Qnil;
}


/*
 *  call-seq:
 *     str.rstrip   => new_str
 *
 *  Returns a copy of <i>str</i> with trailing whitespace removed. See also
 *  <code>String#lstrip</code> and <code>String#strip</code>.
 *
 *     "  hello  ".rstrip   #=> "  hello"
 *     "hello".rstrip       #=> "hello"
 */

static VALUE
rb_str_rstrip(str)
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_rstrip_bang(str);
    return str;
}


/*
 *  call-seq:
 *     str.strip!   => str or nil
 *
 *  Removes leading and trailing whitespace from <i>str</i>. Returns
 *  <code>nil</code> if <i>str</i> was not altered.
 */

static VALUE
rb_str_strip_bang(str)
    VALUE str;
{
    VALUE l = rb_str_lstrip_bang(str);
    VALUE r = rb_str_rstrip_bang(str);

    if (NIL_P(l) && NIL_P(r)) return Qnil;
    return str;
}


/*
 *  call-seq:
 *     str.strip   => new_str
 *
 *  Returns a copy of <i>str</i> with leading and trailing whitespace removed.
 *
 *     "    hello    ".strip   #=> "hello"
 *     "\tgoodbye\r\n".strip   #=> "goodbye"
 */

static VALUE
rb_str_strip(str)
    VALUE str;
{
    str = rb_str_dup(str);
    rb_str_strip_bang(str);
    return str;
}

static VALUE
scan_once(str, pat, start)
    VALUE str, pat;
    long *start;
{
    VALUE result, match;
    struct re_registers *regs;
    long i;

    if (rb_reg_search(pat, str, *start, 0) >= 0) {
	match = rb_backref_get();
	regs = RMATCH(match)->regs;
	if (BEG(0) == END(0)) {
	    /*
	     * Always consume at least one character of the input string
	     */
	    if (RSTRING(str)->len > END(0))
		*start = END(0)+mbclen2(RSTRING(str)->ptr[END(0)],pat);
	    else
		*start = END(0)+1;
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


/*
 *  call-seq:
 *     str.scan(pattern)                         => array
 *     str.scan(pattern) {|match, ...| block }   => str
 *
 *  Both forms iterate through <i>str</i>, matching the pattern (which may be a
 *  <code>Regexp</code> or a <code>String</code>). For each match, a result is
 *  generated and either added to the result array or passed to the block. If
 *  the pattern contains no groups, each individual result consists of the
 *  matched string, <code>$&</code>.  If the pattern contains groups, each
 *  individual result is itself an array containing one entry per group.
 *
 *     a = "cruel world"
 *     a.scan(/\w+/)        #=> ["cruel", "world"]
 *     a.scan(/.../)        #=> ["cru", "el ", "wor"]
 *     a.scan(/(...)/)      #=> [["cru"], ["el "], ["wor"]]
 *     a.scan(/(..)(..)/)   #=> [["cr", "ue"], ["l ", "wo"]]
 *
 *  And the block form:
 *
 *     a.scan(/\w+/) {|w| print "<<#{w}>> " }
 *     print "\n"
 *     a.scan(/(.)(.)/) {|x,y| print y, x }
 *     print "\n"
 *
 *  <em>produces:</em>
 *
 *     <<cruel>> <<world>>
 *     rceu lowlr
 */

static VALUE
rb_str_scan(str, pat)
    VALUE str, pat;
{
    VALUE result;
    long start = 0;
    VALUE match = Qnil;
    char *p = RSTRING(str)->ptr; long len = RSTRING(str)->len;

    pat = get_pat(pat, 1);
    if (!rb_block_given_p()) {
	VALUE ary = rb_ary_new();

	while (!NIL_P(result = scan_once(str, pat, &start))) {
	    match = rb_backref_get();
	    rb_ary_push(ary, result);
	}
	rb_backref_set(match);
	return ary;
    }

    while (!NIL_P(result = scan_once(str, pat, &start))) {
	match = rb_backref_get();
	rb_match_busy(match);
	rb_yield(result);
	str_mod_check(str, p, len);
	rb_backref_set(match);	/* restore $~ value */
    }
    rb_backref_set(match);
    return str;
}

/*
 *  call-seq:
 *     scan(pattern)                   => array
 *     scan(pattern) {|///| block }    => $_
 *
 *  Equivalent to calling <code>$_.scan</code>. See
 *  <code>String#scan</code>.
 */

static VALUE
rb_f_scan(self, pat)
    VALUE self, pat;
{
    return rb_str_scan(uscore_get(), pat);
}


/*
 *  call-seq:
 *     str.hex   => integer
 *
 *  Treats leading characters from <i>str</i> as a string of hexadecimal digits
 *  (with an optional sign and an optional <code>0x</code>) and returns the
 *  corresponding number. Zero is returned on error.
 *
 *     "0x0a".hex     #=> 10
 *     "-1234".hex    #=> -4660
 *     "0".hex        #=> 0
 *     "wombat".hex   #=> 0
 */

static VALUE
rb_str_hex(str)
    VALUE str;
{
    return rb_str_to_inum(str, 16, Qfalse);
}


/*
 *  call-seq:
 *     str.oct   => integer
 *
 *  Treats leading characters of <i>str</i> as a string of octal digits (with an
 *  optional sign) and returns the corresponding number.  Returns 0 if the
 *  conversion fails.
 *
 *     "123".oct       #=> 83
 *     "-377".oct      #=> -255
 *     "bad".oct       #=> 0
 *     "0377bad".oct   #=> 255
 */

static VALUE
rb_str_oct(str)
    VALUE str;
{
    return rb_str_to_inum(str, -8, Qfalse);
}


/*
 *  call-seq:
 *     str.crypt(other_str)   => new_str
 *
 *  Applies a one-way cryptographic hash to <i>str</i> by invoking the standard
 *  library function <code>crypt</code>. The argument is the salt string, which
 *  should be two characters long, each character drawn from
 *  <code>[a-zA-Z0-9./]</code>.
 */

static VALUE
rb_str_crypt(str, salt)
    VALUE str, salt;
{
    extern char *crypt _((const char *, const char*));
    VALUE result;
    const char *s;

    StringValue(salt);
    if (RSTRING(salt)->len < 2)
	rb_raise(rb_eArgError, "salt too short(need >=2 bytes)");

    if (RSTRING(str)->ptr) s = RSTRING(str)->ptr;
    else s = "";
    result = rb_str_new2(crypt(s, RSTRING(salt)->ptr));
    OBJ_INFECT(result, str);
    OBJ_INFECT(result, salt);
    return result;
}


/*
 *  call-seq:
 *     str.intern   => symbol
 *     str.to_sym   => symbol
 *
 *  Returns the <code>Symbol</code> corresponding to <i>str</i>, creating the
 *  symbol if it did not previously exist. See <code>Symbol#id2name</code>.
 *
 *     "Koala".intern         #=> :Koala
 *     s = 'cat'.to_sym       #=> :cat
 *     s == :cat              #=> true
 *     s = '@cat'.to_sym      #=> :@cat
 *     s == :@cat             #=> true
 *
 *  This can also be used to create symbols that cannot be represented using the
 *  <code>:xxx</code> notation.
 *
 *     'cat and dog'.to_sym   #=> :"cat and dog"
 */

VALUE
rb_str_intern(s)
    VALUE s;
{
    volatile VALUE str = s;
    ID id;

    if (!RSTRING(str)->ptr || RSTRING(str)->len == 0) {
	rb_raise(rb_eArgError, "interning empty string");
    }
    if (strlen(RSTRING(str)->ptr) != RSTRING(str)->len)
	rb_raise(rb_eArgError, "symbol string may not contain `\\0'");
    if (OBJ_TAINTED(str) && rb_safe_level() >= 1 && !rb_sym_interned_p(str)) {
	rb_raise(rb_eSecurityError, "Insecure: can't intern tainted string");
    }
    id = rb_intern(RSTRING(str)->ptr);
    return ID2SYM(id);
}


/*
 *  call-seq:
 *     str.sum(n=16)   => integer
 *
 *  Returns a basic <em>n</em>-bit checksum of the characters in <i>str</i>,
 *  where <em>n</em> is the optional <code>Fixnum</code> parameter, defaulting
 *  to 16. The result is simply the sum of the binary value of each character in
 *  <i>str</i> modulo <code>2n - 1</code>. This is not a particularly good
 *  checksum.
 */

static VALUE
rb_str_sum(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE vbits;
    int bits;
    char *ptr, *p, *pend;
    long len;

    if (rb_scan_args(argc, argv, "01", &vbits) == 0) {
	bits = 16;
    }
    else bits = NUM2INT(vbits);

    ptr = p = RSTRING(str)->ptr;
    len = RSTRING(str)->len;
    pend = p + len;
    if (bits >= sizeof(long)*CHAR_BIT) {
	VALUE sum = INT2FIX(0);

	while (p < pend) {
	    str_mod_check(str, ptr, len);
	    sum = rb_funcall(sum, '+', 1, INT2FIX((unsigned char)*p));
	    p++;
	}
	if (bits != 0) {
	    VALUE mod;

	    mod = rb_funcall(INT2FIX(1), rb_intern("<<"), 1, INT2FIX(bits));
	    mod = rb_funcall(mod, '-', 1, INT2FIX(1));
	    sum = rb_funcall(sum, '&', 1, mod);
	}
	return sum;
    }
    else {
       unsigned long sum = 0;

	while (p < pend) {
	    str_mod_check(str, ptr, len);
	    sum += (unsigned char)*p;
	    p++;
	}
	if (bits != 0) {
           sum &= (((unsigned long)1)<<bits)-1;
	}
	return rb_int2inum(sum);
    }
}

static VALUE
rb_str_justify(argc, argv, str, jflag)
    int argc;
    VALUE *argv;
    VALUE str;
    char jflag;
{
    VALUE w;
    long width, flen = 0;
    VALUE res;
    char *p, *pend;
    const char *f = " ";
    long n;
    VALUE pad;

    rb_scan_args(argc, argv, "11", &w, &pad);
    width = NUM2LONG(w);
    if (argc == 2) {
	StringValue(pad);
	f = RSTRING(pad)->ptr;
	flen = RSTRING(pad)->len;
	if (flen == 0) {
	    rb_raise(rb_eArgError, "zero width padding");
	}
    }
    if (width < 0 || RSTRING(str)->len >= width) return rb_str_dup(str);
    res = rb_str_new5(str, 0, width);
    p = RSTRING(res)->ptr;
    if (jflag != 'l') {
	n = width - RSTRING(str)->len;
	pend = p + ((jflag == 'r') ? n : n/2);
	if (flen <= 1) {
	    while (p < pend) {
		*p++ = *f;
	    }
	}
	else {
	    const char *q = f;
	    while (p + flen <= pend) {
		memcpy(p,f,flen);
		p += flen;
	    }
	    while (p < pend) {
		*p++ = *q++;
	    }
	}
    }
    memcpy(p, RSTRING(str)->ptr, RSTRING(str)->len);
    if (jflag != 'r') {
	p += RSTRING(str)->len; pend = RSTRING(res)->ptr + width;
	if (flen <= 1) {
	    while (p < pend) {
		*p++ = *f;
	    }
	}
	else {
	    while (p + flen <= pend) {
		memcpy(p,f,flen);
		p += flen;
	    }
	    while (p < pend) {
		*p++ = *f++;
	    }
	}
    }
    OBJ_INFECT(res, str);
    if (flen > 0) OBJ_INFECT(res, pad);
    return res;
}


/*
 *  call-seq:
 *     str.ljust(integer, padstr=' ')   => new_str
 *
 *  If <i>integer</i> is greater than the length of <i>str</i>, returns a new
 *  <code>String</code> of length <i>integer</i> with <i>str</i> left justified
 *  and padded with <i>padstr</i>; otherwise, returns <i>str</i>.
 *
 *     "hello".ljust(4)            #=> "hello"
 *     "hello".ljust(20)           #=> "hello               "
 *     "hello".ljust(20, '1234')   #=> "hello123412341234123"
 */

static VALUE
rb_str_ljust(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    return rb_str_justify(argc, argv, str, 'l');
}


/*
 *  call-seq:
 *     str.rjust(integer, padstr=' ')   => new_str
 *
 *  If <i>integer</i> is greater than the length of <i>str</i>, returns a new
 *  <code>String</code> of length <i>integer</i> with <i>str</i> right justified
 *  and padded with <i>padstr</i>; otherwise, returns <i>str</i>.
 *
 *     "hello".rjust(4)            #=> "hello"
 *     "hello".rjust(20)           #=> "               hello"
 *     "hello".rjust(20, '1234')   #=> "123412341234123hello"
 */

static VALUE
rb_str_rjust(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    return rb_str_justify(argc, argv, str, 'r');
}


/*
 *  call-seq:
 *     str.center(integer, padstr)   => new_str
 *
 *  If <i>integer</i> is greater than the length of <i>str</i>, returns a new
 *  <code>String</code> of length <i>integer</i> with <i>str</i> centered and
 *  padded with <i>padstr</i>; otherwise, returns <i>str</i>.
 *
 *     "hello".center(4)         #=> "hello"
 *     "hello".center(20)        #=> "       hello        "
 *     "hello".center(20, '123') #=> "1231231hello12312312"
 */

static VALUE
rb_str_center(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    return rb_str_justify(argc, argv, str, 'c');
}

/*
 *  call-seq:
 *     str.partition(sep)              => [head, sep, tail]
 *
 *  Searches the string for <i>sep</i> and returns the part before it,
 *  the <i>sep</i>, and the part after it.  If <i>sep</i> is not
 *  found, returns <i>str</i> and two empty strings.  If no argument
 *  is given, Enumerable#partition is called.
 *
 *     "hello".partition("l")         #=> ["he", "l", "lo"]
 *     "hello".partition("x")         #=> ["hello", "", ""]
 */

static VALUE
rb_str_partition(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    VALUE sep;
    long pos;

    if (argc == 0) return rb_call_super(argc, argv);
    rb_scan_args(argc, argv, "1", &sep);
    if (TYPE(sep) != T_REGEXP) {
	VALUE tmp;

	tmp = rb_check_string_type(sep);
	if (NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "type mismatch: %s given",
		     rb_obj_classname(sep));
	}
        sep = get_arg_pat(tmp);
    }
    pos = rb_reg_search(sep, str, 0, 0);
    if (pos < 0) {
      failed:
	return rb_ary_new3(3, str, rb_str_new(0,0),rb_str_new(0,0));
    }
    sep = rb_str_subpat(str, sep, 0);
    if (pos == 0 && RSTRING(sep)->len == 0) goto failed;
    return rb_ary_new3(3, rb_str_substr(str, 0, pos),
		          sep,
		          rb_str_substr(str, pos+RSTRING(sep)->len,
					     RSTRING(str)->len-pos-RSTRING(sep)->len));
}

/*
 *  call-seq:
 *     str.rpartition(sep)            => [head, sep, tail]
 *
 *  Searches <i>sep</i> in the string from the end of the string, and
 *  returns the part before it, the <i>sep</i>, and the part after it.
 *  If <i>sep</i> is not found, returns two empty strings and
 *  <i>str</i>.
 *
 *     "hello".rpartition("l")         #=> ["hel", "l", "o"]
 *     "hello".rpartition("x")         #=> ["", "", "hello"]
 */

static VALUE
rb_str_rpartition(str, sep)
    VALUE str;
    VALUE sep;
{
    long pos = RSTRING(str)->len;

    if (TYPE(sep) != T_REGEXP) {
	VALUE tmp;

	tmp = rb_check_string_type(sep);
	if (NIL_P(tmp)) {
	    rb_raise(rb_eTypeError, "type mismatch: %s given",
		     rb_obj_classname(sep));
	}
        sep = get_arg_pat(tmp);
    }
    pos = rb_reg_search(sep, str, pos, 1);
    if (pos < 0) {
	return rb_ary_new3(3, rb_str_new(0,0),rb_str_new(0,0), str);
    }
    sep = rb_reg_nth_match(0, rb_backref_get());
    return rb_ary_new3(3, rb_str_substr(str, 0, pos),
		          sep,
		          rb_str_substr(str, pos+RSTRING(sep)->len,
					     RSTRING(str)->len-pos-RSTRING(sep)->len));
}

/*
 *  call-seq:
 *     str.start_with?([prefix]+)   => true or false
 *
 *  Returns true if <i>str</i> starts with the prefix given.
 */

static VALUE
rb_str_start_with(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    int i;
    VALUE pat;

    for (i=0; i<argc; i++) {
	VALUE prefix = rb_check_string_type(argv[i]);
	if (NIL_P(prefix)) continue;
	if (RSTRING(str)->len < RSTRING(prefix)->len) continue;
        pat = get_arg_pat(prefix);
        if (rb_reg_search(pat, str, 0, 1) >= 0)
	    return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     str.end_with?([suffix]+)   => true or false
 *
 *  Returns true if <i>str</i> ends with the suffix given.
 */

static VALUE
rb_str_end_with(argc, argv, str)
    int argc;
    VALUE *argv;
    VALUE str;
{
    int i;
    long pos;
    VALUE pat;

    for (i=0; i<argc; i++) {
	VALUE suffix = rb_check_string_type(argv[i]);
	if (NIL_P(suffix)) continue;
	if (RSTRING(str)->len < RSTRING(suffix)->len) continue;
        pat = get_arg_pat(suffix);
        pos = rb_reg_adjust_startpos(pat, str, RSTRING(str)->len - RSTRING(suffix)->len, 0);
        if (rb_reg_search(pat, str, pos, 0) >= 0)
            return Qtrue;
    }
    return Qfalse;
}

void
rb_str_setter(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    if (!NIL_P(val) && TYPE(val) != T_STRING) {
	rb_raise(rb_eTypeError, "value of %s must be String", rb_id2name(id));
    }
    *var = val;
}


/*
 * call-seq:
 *
 *   sym.succ
 *
 * Same as <code>sym.to_s.succ.intern</code>.
 */

static VALUE
sym_succ(sym)
    VALUE sym;
{
    VALUE str = rb_sym_to_s(sym);
    rb_str_succ_bang(str);
    return rb_str_intern(str);
}

/*
 * call-seq:
 *
 *   str <=> other       => -1, 0, +1 or nil
 *
 * Compares _sym_ with _other_ in string form.
 */

static VALUE
sym_cmp(sym, other)
    VALUE sym, other;
{
    if (!SYMBOL_P(other)) {
	return Qnil;
    }
    return rb_str_cmp_m(rb_sym_to_s(sym), rb_sym_to_s(other));
}

/*
 * call-seq:
 *
 *   sym.casecmp(other)  => -1, 0, +1 or nil
 *
 * Case-insensitive version of <code>Symbol#<=></code>.
 */

static VALUE
sym_casecmp(sym, other)
    VALUE sym, other;
{
    if (!SYMBOL_P(other)) {
	return Qnil;
    }
    return rb_str_casecmp(rb_sym_to_s(sym), rb_sym_to_s(other));
}

/*
 * call-seq:
 *   sym =~ obj   => fixnum or nil
 *
 * Returns <code>sym.to_s =~ obj</code>.
 */

static VALUE
sym_match(sym, other)
    VALUE sym, other;
{
    return rb_str_match(rb_sym_to_s(sym), other);
}

/*
 * call-seq:
 *   sym[idx]      => char
 *   sym[b, n]     => char
 *
 * Returns <code>sym.to_s[]</code>.
 */

static VALUE
sym_aref(argc, argv, sym)
    int argc;
    VALUE *argv;
    VALUE sym;
{
    return rb_str_aref_m(argc, argv, rb_sym_to_s(sym));
}

/*
 * call-seq:
 *   sym.length    => integer
 *
 * Same as <code>sym.to_s.length</code>.
 */

static VALUE
sym_length(sym)
    VALUE sym;
{
    return rb_str_length(rb_sym_to_s(sym));
}

/*
 * call-seq:
 *   sym.empty?   => true or false
 *
 * Returns that _sym_ is :"" or not.
 */

static VALUE
sym_empty(sym)
    VALUE sym;
{
    return rb_str_empty(rb_sym_to_s(sym));
}

/*
 * call-seq:
 *   sym.upcase    => symbol
 *
 * Same as <code>sym.to_s.upcase.intern</code>.
 */

static VALUE
sym_upcase(sym)
    VALUE sym;
{
    VALUE str = rb_sym_to_s(sym);
    rb_str_upcase_bang(str);
    return rb_str_intern(str);
}

/*
 * call-seq:
 *   sym.downcase  => symbol
 *
 * Same as <code>sym.to_s.downcase.intern</code>.
 */

static VALUE
sym_downcase(sym)
    VALUE sym;
{
    VALUE str = rb_sym_to_s(sym);
    rb_str_downcase_bang(str);
    return rb_str_intern(str);
}

/*
 * call-seq:
 *   sym.capitalize  => symbol
 *
 * Same as <code>sym.to_s.capitalize.intern</code>.
 */

static VALUE
sym_capitalize(sym)
    VALUE sym;
{
    VALUE str = rb_sym_to_s(sym);
    rb_str_capitalize_bang(str);
    return rb_str_intern(str);
}

/*
 * call-seq:
 *   sym.swapcase  => symbol
 *
 * Same as <code>sym.to_s.swapcase.intern</code>.
 */

static VALUE
sym_swapcase(sym)
    VALUE sym;
{
    VALUE str = rb_sym_to_s(sym);
    rb_str_swapcase_bang(str);
    return rb_str_intern(str);
}


/*
 *  A <code>String</code> object holds and manipulates an arbitrary sequence of
 *  bytes, typically representing characters. String objects may be created
 *  using <code>String::new</code> or as literals.
 *
 *  Because of aliasing issues, users of strings should be aware of the methods
 *  that modify the contents of a <code>String</code> object.  Typically,
 *  methods with names ending in ``!'' modify their receiver, while those
 *  without a ``!'' return a new <code>String</code>.  However, there are
 *  exceptions, such as <code>String#[]=</code>.
 *
 */

void
Init_String()
{
    rb_cString  = rb_define_class("String", rb_cObject);
    rb_include_module(rb_cString, rb_mComparable);
    rb_include_module(rb_cString, rb_mEnumerable);
    rb_define_alloc_func(rb_cString, rb_str_s_alloc);
    rb_define_singleton_method(rb_cString, "try_convert", rb_str_s_try_convert, 1);
    rb_define_method(rb_cString, "initialize", rb_str_init, -1);
    rb_define_method(rb_cString, "initialize_copy", rb_str_replace, 1);
    rb_define_method(rb_cString, "<=>", rb_str_cmp_m, 1);
    rb_define_method(rb_cString, "==", rb_str_equal, 1);
    rb_define_method(rb_cString, "eql?", rb_str_eql, 1);
    rb_define_method(rb_cString, "hash", rb_str_hash_m, 0);
    rb_define_method(rb_cString, "casecmp", rb_str_casecmp, 1);
    rb_define_method(rb_cString, "+", rb_str_plus, 1);
    rb_define_method(rb_cString, "*", rb_str_times, 1);
    rb_define_method(rb_cString, "%", rb_str_format_m, 1);
    rb_define_method(rb_cString, "[]", rb_str_aref_m, -1);
    rb_define_method(rb_cString, "[]=", rb_str_aset_m, -1);
    rb_define_method(rb_cString, "insert", rb_str_insert, 2);
    rb_define_method(rb_cString, "length", rb_str_length, 0);
    rb_define_method(rb_cString, "size", rb_str_length, 0);
    rb_define_method(rb_cString, "bytesize", rb_str_length, 0);
    rb_define_method(rb_cString, "empty?", rb_str_empty, 0);
    rb_define_method(rb_cString, "=~", rb_str_match, 1);
    rb_define_method(rb_cString, "match", rb_str_match_m, 1);
    rb_define_method(rb_cString, "succ", rb_str_succ, 0);
    rb_define_method(rb_cString, "succ!", rb_str_succ_bang, 0);
    rb_define_method(rb_cString, "next", rb_str_succ, 0);
    rb_define_method(rb_cString, "next!", rb_str_succ_bang, 0);
    rb_define_method(rb_cString, "upto", rb_str_upto_m, -1);
    rb_define_method(rb_cString, "index", rb_str_index_m, -1);
    rb_define_method(rb_cString, "rindex", rb_str_rindex_m, -1);
    rb_define_method(rb_cString, "replace", rb_str_replace, 1);
    rb_define_method(rb_cString, "getbyte", rb_str_getbyte, 1);
    rb_define_method(rb_cString, "setbyte", rb_str_setbyte, 2);

    rb_define_method(rb_cString, "to_i", rb_str_to_i, -1);
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
    rb_define_method(rb_cString, "split", rb_str_split_m, -1);
    rb_define_method(rb_cString, "reverse", rb_str_reverse, 0);
    rb_define_method(rb_cString, "reverse!", rb_str_reverse_bang, 0);
    rb_define_method(rb_cString, "concat", rb_str_concat, 1);
    rb_define_method(rb_cString, "<<", rb_str_concat, 1);
    rb_define_method(rb_cString, "crypt", rb_str_crypt, 1);
    rb_define_method(rb_cString, "intern", rb_str_intern, 0);
    rb_define_method(rb_cString, "to_sym", rb_str_intern, 0);

    rb_define_method(rb_cString, "include?", rb_str_include, 1);
    rb_define_method(rb_cString, "start_with?", rb_str_start_with, -1);
    rb_define_method(rb_cString, "end_with?", rb_str_end_with, -1);

    rb_define_method(rb_cString, "scan", rb_str_scan, 1);

    rb_define_method(rb_cString, "ljust", rb_str_ljust, -1);
    rb_define_method(rb_cString, "rjust", rb_str_rjust, -1);
    rb_define_method(rb_cString, "center", rb_str_center, -1);

    rb_define_method(rb_cString, "sub", rb_str_sub, -1);
    rb_define_method(rb_cString, "gsub", rb_str_gsub, -1);
    rb_define_method(rb_cString, "chop", rb_str_chop, 0);
    rb_define_method(rb_cString, "chomp", rb_str_chomp, -1);
    rb_define_method(rb_cString, "strip", rb_str_strip, 0);
    rb_define_method(rb_cString, "lstrip", rb_str_lstrip, 0);
    rb_define_method(rb_cString, "rstrip", rb_str_rstrip, 0);

    rb_define_method(rb_cString, "sub!", rb_str_sub_bang, -1);
    rb_define_method(rb_cString, "gsub!", rb_str_gsub_bang, -1);
    rb_define_method(rb_cString, "chop!", rb_str_chop_bang, 0);
    rb_define_method(rb_cString, "chomp!", rb_str_chomp_bang, -1);
    rb_define_method(rb_cString, "strip!", rb_str_strip_bang, 0);
    rb_define_method(rb_cString, "lstrip!", rb_str_lstrip_bang, 0);
    rb_define_method(rb_cString, "rstrip!", rb_str_rstrip_bang, 0);

    rb_define_method(rb_cString, "tr", rb_str_tr, 2);
    rb_define_method(rb_cString, "tr_s", rb_str_tr_s, 2);
    rb_define_method(rb_cString, "delete", rb_str_delete, -1);
    rb_define_method(rb_cString, "squeeze", rb_str_squeeze, -1);
    rb_define_method(rb_cString, "count", rb_str_count, -1);

    rb_define_method(rb_cString, "tr!", rb_str_tr_bang, 2);
    rb_define_method(rb_cString, "tr_s!", rb_str_tr_s_bang, 2);
    rb_define_method(rb_cString, "delete!", rb_str_delete_bang, -1);
    rb_define_method(rb_cString, "squeeze!", rb_str_squeeze_bang, -1);

    rb_define_method(rb_cString, "each_line", rb_str_each_line, -1);
    rb_define_method(rb_cString, "each",      rb_str_each, -1);
    rb_define_method(rb_cString, "each_byte", rb_str_each_byte, 0);
    rb_define_method(rb_cString, "each_char", rb_str_each_char, 0);

    rb_define_method(rb_cString, "lines", rb_str_each_line, -1);
    rb_define_method(rb_cString, "bytes", rb_str_each_byte, 0);
    rb_define_method(rb_cString, "chars", rb_str_each_char, 0);

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
    rb_define_global_function("scan", rb_f_scan, 1);

    rb_define_method(rb_cString, "slice", rb_str_aref_m, -1);
    rb_define_method(rb_cString, "slice!", rb_str_slice_bang, -1);

    rb_define_method(rb_cString, "partition", rb_str_partition, -1);
    rb_define_method(rb_cString, "rpartition", rb_str_rpartition, 1);

    id_to_s = rb_intern("to_s");

    rb_fs = Qnil;
    rb_define_variable("$;", &rb_fs);
    rb_define_variable("$-F", &rb_fs);

    rb_define_method(rb_cSymbol, "succ", sym_succ, 0);
    rb_define_method(rb_cSymbol, "next", sym_succ, 0);

    rb_define_method(rb_cSymbol, "<=>", sym_cmp, 1);
    rb_define_method(rb_cSymbol, "casecmp", sym_casecmp, 1);
    rb_define_method(rb_cSymbol, "=~", sym_match, 1);

    rb_define_method(rb_cSymbol, "[]", sym_aref, -1);
    rb_define_method(rb_cSymbol, "slice", sym_aref, -1);
    rb_define_method(rb_cSymbol, "length", sym_length, 0);
    rb_define_method(rb_cSymbol, "size", sym_length, 0);
    rb_define_method(rb_cSymbol, "empty?", sym_empty, 0);
    rb_define_method(rb_cSymbol, "match", sym_match, 1);

    rb_define_method(rb_cSymbol, "upcase", sym_upcase, 0);
    rb_define_method(rb_cSymbol, "downcase", sym_downcase, 0);
    rb_define_method(rb_cSymbol, "capitalize", sym_capitalize, 0);
    rb_define_method(rb_cSymbol, "swapcase", sym_swapcase, 0);
}
