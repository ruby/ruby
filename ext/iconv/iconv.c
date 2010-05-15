/* -*- mode:c; c-file-style:"ruby" -*- */
/**********************************************************************

  iconv.c -

  $Author$
  $Date$
  created at: Wed Dec  1 20:28:09 JST 1999

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

  Documentation by Yukihiro Matsumoto and Gavin Sinclair.

**********************************************************************/

#include "ruby.h"
#include <errno.h>
#include <iconv.h>
#include <assert.h>
#include "st.h"
#include "intern.h"

/*
 * Document-class: Iconv
 *
 * == Summary
 *
 * Ruby extension for charset conversion.
 * 
 * == Abstract
 *
 * Iconv is a wrapper class for the UNIX 95 <tt>iconv()</tt> function family,
 * which translates string between various encoding systems.
 * 
 * See Open Group's on-line documents for more details.
 * * <tt>iconv.h</tt>:       http://www.opengroup.org/onlinepubs/007908799/xsh/iconv.h.html
 * * <tt>iconv_open()</tt>:  http://www.opengroup.org/onlinepubs/007908799/xsh/iconv_open.html
 * * <tt>iconv()</tt>:       http://www.opengroup.org/onlinepubs/007908799/xsh/iconv.html
 * * <tt>iconv_close()</tt>: http://www.opengroup.org/onlinepubs/007908799/xsh/iconv_close.html
 * 
 * Which coding systems are available is platform-dependent.
 * 
 * == Examples
 *
 * 1. Simple conversion between two charsets.
 *
 *      converted_text = Iconv.conv('iso-8859-15', 'utf-8', text)
 *
 * 2. Instantiate a new Iconv and use method Iconv#iconv.
 *
 *      cd = Iconv.new(to, from)
 *      begin
 *        input.each { |s| output << cd.iconv(s) }
 *        output << cd.iconv(nil)                   # Don't forget this!
 *      ensure
 *        cd.close
 *      end
 *
 * 3. Invoke Iconv.open with a block.
 *
 *      Iconv.open(to, from) do |cd|
 *        input.each { |s| output << cd.iconv(s) }
 *        output << cd.iconv(nil)
 *      end
 *
 * 4. Shorthand for (3).
 *
 *      Iconv.iconv(to, from, *input.to_a)
 */

/* Invalid value for iconv_t is -1 but 0 for VALUE, I hope VALUE is
   big enough to keep iconv_t */
#define VALUE2ICONV(v) ((iconv_t)((VALUE)(v) ^ -1))
#define ICONV2VALUE(c) ((VALUE)(c) ^ -1)

struct iconv_env_t
{
    iconv_t cd;
    int argc;
    VALUE *argv;
    VALUE ret;
    VALUE (*append)_((VALUE, VALUE));
};

static VALUE rb_eIconvInvalidEncoding;
static VALUE rb_eIconvFailure;
static VALUE rb_eIconvIllegalSeq;
static VALUE rb_eIconvInvalidChar;
static VALUE rb_eIconvOutOfRange;
static VALUE rb_eIconvBrokenLibrary;

static ID rb_success, rb_failed;
static VALUE iconv_fail _((VALUE error, VALUE success, VALUE failed, struct iconv_env_t* env, const char *mesg));
static VALUE iconv_fail_retry _((VALUE error, VALUE success, VALUE failed, struct iconv_env_t* env, const char *mesg));
static VALUE iconv_failure_initialize _((VALUE error, VALUE mesg, VALUE success, VALUE failed));
static VALUE iconv_failure_success _((VALUE self));
static VALUE iconv_failure_failed _((VALUE self));

static iconv_t iconv_create _((VALUE to, VALUE from));
static void iconv_dfree _((void *cd));
static VALUE iconv_free _((VALUE cd));
static VALUE iconv_try _((iconv_t cd, const char **inptr, size_t *inlen, char **outptr, size_t *outlen));
static VALUE rb_str_derive _((VALUE str, const char* ptr, int len));
static VALUE iconv_convert _((iconv_t cd, VALUE str, long start, long length, struct iconv_env_t* env));
static VALUE iconv_s_allocate _((VALUE klass));
static VALUE iconv_initialize _((VALUE self, VALUE to, VALUE from));
static VALUE iconv_s_open _((VALUE self, VALUE to, VALUE from));
static VALUE iconv_s_convert _((struct iconv_env_t* env));
static VALUE iconv_s_iconv _((int argc, VALUE *argv, VALUE self));
static VALUE iconv_init_state _((VALUE cd));
static VALUE iconv_finish _((VALUE self));
static VALUE iconv_iconv _((int argc, VALUE *argv, VALUE self));

static VALUE charset_map;

/*
 * Document-method: charset_map
 * call-seq: Iconv.charset_map
 *
 * Returns the map from canonical name to system dependent name.
 */
static VALUE charset_map_get _((void))
{
    return charset_map;
}

static char *
map_charset
#ifdef HAVE_PROTOTYPES
    (VALUE *code)
#else /* HAVE_PROTOTYPES */
    (code)
    VALUE *code;
#endif /* HAVE_PROTOTYPES */
{
    VALUE val = *code;

    if (RHASH(charset_map)->tbl && RHASH(charset_map)->tbl->num_entries) {
	VALUE key = rb_funcall2(val, rb_intern("downcase"), 0, 0);
	StringValuePtr(key);
	if (st_lookup(RHASH(charset_map)->tbl, key, &val)) {
	    *code = val;
	}
    }
    return StringValuePtr(*code);
}

NORETURN(static void rb_iconv_sys_fail(const char *s));
static void
rb_iconv_sys_fail(const char *s)
{
    if (errno == 0) {
	rb_raise(rb_eIconvBrokenLibrary, "%s", s);
    }
    rb_sys_fail(s);
}

#define rb_sys_fail(s) rb_iconv_sys_fail(s)

static iconv_t
iconv_create
#ifdef HAVE_PROTOTYPES
    (VALUE to, VALUE from)
#else /* HAVE_PROTOTYPES */
    (to, from)
    VALUE to;
    VALUE from;
#endif /* HAVE_PROTOTYPES */
{
    const char* tocode = map_charset(&to);
    const char* fromcode = map_charset(&from);

    iconv_t cd = iconv_open(tocode, fromcode);

    if (cd == (iconv_t)-1) {
	switch (errno) {
	  case EMFILE:
	  case ENFILE:
	  case ENOMEM:
	    rb_gc();
	    cd = iconv_open(tocode, fromcode);
	}
	if (cd == (iconv_t)-1) {
	    int inval = errno == EINVAL;
	    const char *s = inval ? "invalid encoding " : "iconv";
	    volatile VALUE msg = rb_str_new(0, strlen(s) + RSTRING(to)->len +
					    RSTRING(from)->len + 8);

	    sprintf(RSTRING(msg)->ptr, "%s(\"%s\", \"%s\")",
		    s, RSTRING(to)->ptr, RSTRING(from)->ptr);
	    s = RSTRING(msg)->ptr;
	    RSTRING(msg)->len = strlen(s);
	    if (!inval) rb_sys_fail(s);
	    rb_exc_raise(iconv_fail(rb_eIconvInvalidEncoding, Qnil,
				    rb_ary_new3(2, to, from), NULL, s));
	}
    }

    return cd;
}

static void
iconv_dfree
#ifdef HAVE_PROTOTYPES
    (void *cd)
#else /* HAVE_PROTOTYPES */
    (cd)
    void *cd;
#endif /* HAVE_PROTOTYPES */
{
    iconv_close(VALUE2ICONV(cd));
}

#define ICONV_FREE iconv_dfree

static VALUE
iconv_free
#ifdef HAVE_PROTOTYPES
    (VALUE cd)
#else /* HAVE_PROTOTYPES */
    (cd)
    VALUE cd;
#endif /* HAVE_PROTOTYPES */
{
    if (cd && iconv_close(VALUE2ICONV(cd)) == -1)
	rb_sys_fail("iconv_close");
    return Qnil;
}

static VALUE
check_iconv
#ifdef HAVE_PROTOTYPES
    (VALUE obj)
#else /* HAVE_PROTOTYPES */
    (obj)
    VALUE obj;
#endif /* HAVE_PROTOTYPES */
{
    Check_Type(obj, T_DATA);
    if (RDATA(obj)->dfree != ICONV_FREE) {
	rb_raise(rb_eArgError, "Iconv expected (%s)", rb_class2name(CLASS_OF(obj)));
    }
    return (VALUE)DATA_PTR(obj);
}

static VALUE
iconv_try
#ifdef HAVE_PROTOTYPES
    (iconv_t cd, const char **inptr, size_t *inlen, char **outptr, size_t *outlen)
#else /* HAVE_PROTOTYPES */
    (cd, inptr, inlen, outptr, outlen)
    iconv_t cd;
    const char **inptr;
    size_t *inlen;
    char **outptr;
    size_t *outlen;
#endif /* HAVE_PROTOTYPES */
{
#ifdef ICONV_INPTR_CONST
#define ICONV_INPTR_CAST
#else
#define ICONV_INPTR_CAST (char **)
#endif
    size_t ret;

    errno = 0;
    ret = iconv(cd, ICONV_INPTR_CAST inptr, inlen, outptr, outlen);
    if (ret == (size_t)-1) {
	if (!*inlen)
	    return Qfalse;
	switch (errno) {
	  case E2BIG:
	    /* try the left in next loop */
	    break;
	  case EILSEQ:
	    return rb_eIconvIllegalSeq;
	  case EINVAL:
	    return rb_eIconvInvalidChar;
	  case 0:
	    return rb_eIconvBrokenLibrary;
	  default:
	    rb_sys_fail("iconv");
	}
    }
    else if (*inlen > 0) {
	/* something goes wrong */
	return rb_eIconvIllegalSeq;
    }
    else if (ret) {
	return Qnil;		/* conversion */
    }
    return Qfalse;
}

#define FAILED_MAXLEN 16

static VALUE iconv_failure_initialize
#ifdef HAVE_PROTOTYPES
    (VALUE error, VALUE mesg, VALUE success, VALUE failed)
#else /* HAVE_PROTOTYPES */
    (error, mesg, success, failed)
    VALUE error, mesg, success, failed;
#endif /* HAVE_PROTOTYPES */
{
    rb_call_super(1, &mesg);
    rb_ivar_set(error, rb_success, success);
    rb_ivar_set(error, rb_failed, failed);
    return error;
}

static VALUE
iconv_fail
#ifdef HAVE_PROTOTYPES
    (VALUE error, VALUE success, VALUE failed, struct iconv_env_t* env, const char *mesg)
#else /* HAVE_PROTOTYPES */
    (error, success, failed, env, mesg)
    VALUE error, success, failed;
    struct iconv_env_t *env;
    const char *mesg;
#endif /* HAVE_PROTOTYPES */
{
    VALUE args[3];

    if (mesg && *mesg) {
	args[0] = rb_str_new2(mesg);
    }
    else if (TYPE(failed) != T_STRING || RSTRING(failed)->len < FAILED_MAXLEN) {
	args[0] = rb_inspect(failed);
    }
    else {
	args[0] = rb_inspect(rb_str_substr(failed, 0, FAILED_MAXLEN));
	rb_str_cat2(args[0], "...");
    }
    args[1] = success;
    args[2] = failed;
    if (env) {
	args[1] = env->append(rb_obj_dup(env->ret), success);
	if (env->argc > 0) {
	    *(env->argv) = failed;
	    args[2] = rb_ary_new4(env->argc, env->argv);
	}
    }
    return rb_class_new_instance(3, args, error);
}

static VALUE
iconv_fail_retry(VALUE error, VALUE success, VALUE failed, struct iconv_env_t* env, const char *mesg)
{
    error = iconv_fail(error, success, failed, env, mesg);
    if (!rb_block_given_p()) rb_exc_raise(error);
    ruby_errinfo = error;
    return rb_yield(failed);
}

static VALUE
rb_str_derive
#ifdef HAVE_PROTOTYPES
    (VALUE str, const char* ptr, int len)
#else /* HAVE_PROTOTYPES */
    (str, ptr, len)
    VALUE str;
    const char *ptr;
    int len;
#endif /* HAVE_PROTOTYPES */
{
    VALUE ret;

    if (NIL_P(str))
	return rb_str_new(ptr, len);
    if (RSTRING(str)->ptr == ptr && RSTRING(str)->len == len)
	return str;
    if (RSTRING(str)->ptr + RSTRING(str)->len == ptr + len)
	ret = rb_str_substr(str, ptr - RSTRING(str)->ptr, len);
    else
	ret = rb_str_new(ptr, len);
    OBJ_INFECT(ret, str);
    return ret;
}

static VALUE
iconv_convert
#ifdef HAVE_PROTOTYPES
    (iconv_t cd, VALUE str, long start, long length, struct iconv_env_t* env)
#else /* HAVE_PROTOTYPES */
    (cd, str, start, length, env)
    iconv_t cd;
    VALUE str;
    long start;
    long length;
    struct iconv_env_t *env;
#endif /* HAVE_PROTOTYPES */
{
    VALUE ret = Qfalse;
    VALUE error = Qfalse;
    VALUE rescue;
    const char *inptr, *instart;
    size_t inlen;
    /* I believe ONE CHARACTER never exceed this. */
    char buffer[BUFSIZ];
    char *outptr;
    size_t outlen;

    if (cd == (iconv_t)-1)
	rb_raise(rb_eArgError, "closed iconv");

    if (NIL_P(str)) {
	/* Reset output pointer or something. */
	inptr = "";
	inlen = 0;
	outptr = buffer;
	outlen = sizeof(buffer);
	error = iconv_try(cd, &inptr, &inlen, &outptr, &outlen);
	if (RTEST(error)) {
	    unsigned int i;
	    rescue = iconv_fail_retry(error, Qnil, Qnil, env, 0);
	    if (TYPE(rescue) == T_ARRAY) {
		str = RARRAY(rescue)->len > 0 ? RARRAY(rescue)->ptr[0] : Qnil;
	    }
	    if (FIXNUM_P(str) && (i = FIX2INT(str)) <= 0xff) {
		char c = i;
		str = rb_str_new(&c, 1);
	    }
	    else if (!NIL_P(str)) {
		StringValue(str);
	    }
	}

	inptr = NULL;
	length = 0;
    }
    else {
	int slen;

	StringValue(str);
	slen = RSTRING(str)->len;
	inptr = RSTRING(str)->ptr;

	inptr += start;
	if (length < 0 || length > start + slen)
	    length = slen - start;
    }
    instart = inptr;
    inlen = length;

    do {
	char errmsg[50];
	const char *tmpstart = inptr;
	outptr = buffer;
	outlen = sizeof(buffer);

	errmsg[0] = 0;
	error = iconv_try(cd, &inptr, &inlen, &outptr, &outlen);

	if (0 <= outlen && outlen <= sizeof(buffer)) {
	    outlen = sizeof(buffer) - outlen;
	    if (NIL_P(error) ||	/* something converted */
		outlen > inptr - tmpstart || /* input can't contain output */
		(outlen < inptr - tmpstart && inlen > 0) || /* something skipped */
		memcmp(buffer, tmpstart, outlen)) /* something differs */
	    {
		if (NIL_P(str)) {
		    ret = rb_str_new(buffer, outlen);
		}
		else {
		    if (ret) {
			ret = rb_str_buf_cat(ret, instart, tmpstart - instart);
		    }
		    else {
			ret = rb_str_new(instart, tmpstart - instart);
			OBJ_INFECT(ret, str);
		    }
		    ret = rb_str_buf_cat(ret, buffer, outlen);
		    instart = inptr;
		}
	    }
	    else if (!inlen) {
		inptr = tmpstart + outlen;
	    }
	}
	else {
	    /* Some iconv() have a bug, return *outlen out of range */
	    sprintf(errmsg, "bug?(output length = %ld)", (long)(sizeof(buffer) - outlen));
	    error = rb_eIconvOutOfRange;
	}

	if (RTEST(error)) {
	    long len = 0;

	    if (!ret)
		ret = rb_str_derive(str, instart, inptr - instart);
	    else if (inptr > instart)
		rb_str_cat(ret, instart, inptr - instart);
	    str = rb_str_derive(str, inptr, inlen);
	    rescue = iconv_fail_retry(error, ret, str, env, errmsg);
	    if (TYPE(rescue) == T_ARRAY) {
		if ((len = RARRAY(rescue)->len) > 0)
		    rb_str_concat(ret, RARRAY(rescue)->ptr[0]);
		if (len > 1 && !NIL_P(str = RARRAY(rescue)->ptr[1])) {
		    StringValue(str);
		    inlen = length = RSTRING(str)->len;
		    instart = inptr = RSTRING(str)->ptr;
		    continue;
		}
	    }
	    else if (!NIL_P(rescue)) {
		rb_str_concat(ret, rescue);
	    }
	    break;
	}
    } while (inlen > 0);

    if (!ret)
	ret = rb_str_derive(str, instart, inptr - instart);
    else if (inptr > instart)
	rb_str_cat(ret, instart, inptr - instart);
    return ret;
}

static VALUE
iconv_s_allocate
#ifdef HAVE_PROTOTYPES
    (VALUE klass)
#else /* HAVE_PROTOTYPES */
    (klass)
    VALUE klass;
#endif /* HAVE_PROTOTYPES */
{
    return Data_Wrap_Struct(klass, 0, ICONV_FREE, 0);
}

/*
 * Document-method: new
 * call-seq: Iconv.new(to, from)
 *
 * Creates new code converter from a coding-system designated with +from+
 * to another one designated with +to+.
 * 
 * === Parameters
 *
 * +to+::   encoding name for destination
 * +from+:: encoding name for source
 *
 * === Exceptions
 *
 * TypeError::       if +to+ or +from+ aren't String
 * InvalidEncoding:: if designated converter couldn't find out
 * SystemCallError:: if <tt>iconv_open(3)</tt> fails
 */
static VALUE
iconv_initialize
#ifdef HAVE_PROTOTYPES
    (VALUE self, VALUE to, VALUE from)
#else /* HAVE_PROTOTYPES */
    (self, to, from)
    VALUE self;
    VALUE to;
    VALUE from;
#endif /* HAVE_PROTOTYPES */
{
    iconv_free(check_iconv(self));
    DATA_PTR(self) = NULL;
    DATA_PTR(self) = (void *)ICONV2VALUE(iconv_create(to, from));
    return self;
}

/*
 * Document-method: open
 * call-seq: Iconv.open(to, from) { |iconv| ... }
 *
 * Equivalent to Iconv.new except that when it is called with a block, it
 * yields with the new instance and closes it, and returns the result which
 * returned from the block.
 */
static VALUE
iconv_s_open
#ifdef HAVE_PROTOTYPES
    (VALUE self, VALUE to, VALUE from)
#else /* HAVE_PROTOTYPES */
    (self, to, from)
    VALUE self;
    VALUE to;
    VALUE from;
#endif /* HAVE_PROTOTYPES */
{
    VALUE cd = ICONV2VALUE(iconv_create(to, from));

    self = Data_Wrap_Struct(self, NULL, ICONV_FREE, (void *)cd);
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, self, (VALUE(*)())iconv_finish, self);
    }
    else {
	return self;
    }
}

static VALUE
iconv_s_convert
#ifdef HAVE_PROTOTYPES
    (struct iconv_env_t* env)
#else /* HAVE_PROTOTYPES */
    (env)
    struct iconv_env_t *env;
#endif /* HAVE_PROTOTYPES */
{
    VALUE last = 0;

    for (; env->argc > 0; --env->argc, ++env->argv) {
	VALUE s = iconv_convert(env->cd, last = *(env->argv), 0, -1, env);
	env->append(env->ret, s);
    }

    if (!NIL_P(last)) {
	VALUE s = iconv_convert(env->cd, Qnil, 0, 0, env);
	if (RSTRING(s)->len)
	    env->append(env->ret, s);
    }

    return env->ret;
}

/*
 * Document-method: Iconv::iconv
 * call-seq: Iconv.iconv(to, from, *strs)
 *
 * Shorthand for
 *   Iconv.open(to, from) { |cd|
 *     (strs + [nil]).collect { |s| cd.iconv(s) }
 *   }
 *
 * === Parameters
 *
 * <tt>to, from</tt>:: see Iconv.new
 * <tt>strs</tt>:: strings to be converted
 *
 * === Exceptions
 *
 * Exceptions thrown by Iconv.new, Iconv.open and Iconv#iconv.
 */
static VALUE
iconv_s_iconv
#ifdef HAVE_PROTOTYPES
    (int argc, VALUE *argv, VALUE self)
#else /* HAVE_PROTOTYPES */
    (argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
#endif /* HAVE_PROTOTYPES */
{
    struct iconv_env_t arg;

    if (argc < 2)		/* needs `to' and `from' arguments at least */
	rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)", argc, 2);

    arg.argc = argc -= 2;
    arg.argv = argv + 2;
    arg.append = rb_ary_push;
    arg.ret = rb_ary_new2(argc);
    arg.cd = iconv_create(argv[0], argv[1]);
    return rb_ensure(iconv_s_convert, (VALUE)&arg, iconv_free, ICONV2VALUE(arg.cd));
}

/*
 * Document-method: Iconv::conv
 * call-seq: Iconv.conv(to, from, str)
 *
 * Shorthand for
 *   Iconv.iconv(to, from, str).join
 * See Iconv.iconv.
 */
static VALUE
iconv_s_conv
#ifdef HAVE_PROTOTYPES
    (VALUE self, VALUE to, VALUE from, VALUE str)
#else /* HAVE_PROTOTYPES */
    (self, to, from, str)
    VALUE self, to, from, str;
#endif /* HAVE_PROTOTYPES */
{
    struct iconv_env_t arg;

    arg.argc = 1;
    arg.argv = &str;
    arg.append = rb_str_append;
    arg.ret = rb_str_new(0, 0);
    arg.cd = iconv_create(to, from);
    return rb_ensure(iconv_s_convert, (VALUE)&arg, iconv_free, ICONV2VALUE(arg.cd));
}

/*
 * Document-method: close
 *
 * Finishes conversion.
 *
 * After calling this, calling Iconv#iconv will cause an exception, but
 * multiple calls of #close are guaranteed to end successfully.
 *
 * Returns a string containing the byte sequence to change the output buffer to
 * its initial shift state.
 */
static VALUE
iconv_init_state
#ifdef HAVE_PROTOTYPES
    (VALUE cd)
#else /* HAVE_PROTOTYPES */
    (cd)
    VALUE cd;
#endif /* HAVE_PROTOTYPES */
{
    return iconv_convert(VALUE2ICONV(cd), Qnil, 0, 0, NULL);
}

static VALUE
iconv_finish
#ifdef HAVE_PROTOTYPES
    (VALUE self)
#else /* HAVE_PROTOTYPES */
    (self)
    VALUE self;
#endif /* HAVE_PROTOTYPES */
{
    VALUE cd = check_iconv(self);

    if (!cd) return Qnil;
    DATA_PTR(self) = NULL;

    return rb_ensure(iconv_init_state, cd, iconv_free, cd);
}

/*
 * Document-method: Iconv#iconv
 * call-seq: iconv(str, start=0, length=-1)
 *
 * Converts string and returns the result.
 * * If +str+ is a String, converts <tt>str[start, length]</tt> and returns the converted string.
 * * If +str+ is +nil+, places converter itself into initial shift state and
 *   just returns a string containing the byte sequence to change the output
 *   buffer to its initial shift state.
 * * Otherwise, raises an exception.
 *
 * === Parameters
 *
 * str::    string to be converted, or nil
 * start::  starting offset
 * length:: conversion length; nil or -1 means whole the string from start
 *
 * === Exceptions
 *
 * * IconvIllegalSequence
 * * IconvInvalidCharacter
 * * IconvOutOfRange
 *
 * === Examples
 *
 * See the Iconv documentation.
 */
static VALUE
iconv_iconv
#ifdef HAVE_PROTOTYPES
    (int argc, VALUE *argv, VALUE self)
#else /* HAVE_PROTOTYPES */
    (argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
#endif /* HAVE_PROTOTYPES */
{
    VALUE str, n1, n2;
    VALUE cd = check_iconv(self);
    long start = 0, length = 0, slen = 0;

    rb_scan_args(argc, argv, "12", &str, &n1, &n2);
    if (!NIL_P(str)) slen = RSTRING_LEN(StringValue(str));
    if (argc != 2 || !RTEST(rb_range_beg_len(n1, &start, &length, slen, 0))) {
	if (NIL_P(n1) || ((start = NUM2LONG(n1)) < 0 ? (start += slen) >= 0 : start < slen)) {
	    if (NIL_P(n2)) {
		length = -1;
	    }
	    else if ((length = NUM2LONG(n2)) >= slen - start) {
		length = slen - start;
	    }
	}
    }

    return iconv_convert(VALUE2ICONV(cd), str, start, length, NULL);
}

/*
 * Document-class: Iconv::Failure
 *
 * Base attributes for Iconv exceptions.
 */

/*
 * Document-method: success
 * call-seq: success
 *
 * Returns string(s) translated successfully until the exception occurred.
 * * In the case of failure occurred within Iconv.iconv, returned
 *   value is an array of strings translated successfully preceding
 *   failure and the last element is string on the way.
 */
static VALUE
iconv_failure_success
#ifdef HAVE_PROTOTYPES
(VALUE self)
#else /* HAVE_PROTOTYPES */
    (self)
    VALUE self;
#endif /* HAVE_PROTOTYPES */
{
    return rb_attr_get(self, rb_success);
}

/*
 * Document-method: failed
 * call-seq: failed
 *
 * Returns substring of the original string passed to Iconv that starts at the
 * character caused the exception. 
 */
static VALUE
iconv_failure_failed
#ifdef HAVE_PROTOTYPES
(VALUE self)
#else /* HAVE_PROTOTYPES */
    (self)
    VALUE self;
#endif /* HAVE_PROTOTYPES */
{
    return rb_attr_get(self, rb_failed);
}

/*
 * Document-method: inspect
 * call-seq: inspect
 *
 * Returns inspected string like as: #<_class_: _success_, _failed_>
 */
static VALUE
iconv_failure_inspect
#ifdef HAVE_PROTOTYPES
    (VALUE self)
#else /* HAVE_PROTOTYPES */
    (self)
    VALUE self;
#endif /* HAVE_PROTOTYPES */
{
    const char *cname = rb_class2name(CLASS_OF(self));
    VALUE success = rb_attr_get(self, rb_success);
    VALUE failed = rb_attr_get(self, rb_failed);
    VALUE str = rb_str_buf_cat2(rb_str_new2("#<"), cname);
    str = rb_str_buf_cat(str, ": ", 2);
    str = rb_str_buf_append(str, rb_inspect(success));
    str = rb_str_buf_cat(str, ", ", 2);
    str = rb_str_buf_append(str, rb_inspect(failed));
    return rb_str_buf_cat(str, ">", 1);
}

/*
 * Document-class: Iconv::InvalidEncoding
 * 
 * Requested coding-system is not available on this system.
 */

/*
 * Document-class: Iconv::IllegalSequence
 * 
 * Input conversion stopped due to an input byte that does not belong to
 * the input codeset, or the output codeset does not contain the
 * character.
 */

/*
 * Document-class: Iconv::InvalidCharacter
 * 
 * Input conversion stopped due to an incomplete character or shift
 * sequence at the end of the input buffer.
 */

/*
 * Document-class: Iconv::OutOfRange
 * 
 * Iconv library internal error.  Must not occur.
 */

/*
 * Document-class: Iconv::BrokenLibrary
 * 
 * Detected a bug of underlying iconv(3) libray.
 * * returns an error without setting errno properly
 */

void
Init_iconv _((void))
{
    VALUE rb_cIconv = rb_define_class("Iconv", rb_cData);

    rb_define_alloc_func(rb_cIconv, iconv_s_allocate);
    rb_define_singleton_method(rb_cIconv, "open", iconv_s_open, 2);
    rb_define_singleton_method(rb_cIconv, "iconv", iconv_s_iconv, -1);
    rb_define_singleton_method(rb_cIconv, "conv", iconv_s_conv, 3);
    rb_define_method(rb_cIconv, "initialize", iconv_initialize, 2);
    rb_define_method(rb_cIconv, "close", iconv_finish, 0);
    rb_define_method(rb_cIconv, "iconv", iconv_iconv, -1);

    rb_eIconvFailure = rb_define_module_under(rb_cIconv, "Failure");
    rb_define_method(rb_eIconvFailure, "initialize", iconv_failure_initialize, 3);
    rb_define_method(rb_eIconvFailure, "success", iconv_failure_success, 0);
    rb_define_method(rb_eIconvFailure, "failed", iconv_failure_failed, 0);
    rb_define_method(rb_eIconvFailure, "inspect", iconv_failure_inspect, 0);

    rb_eIconvInvalidEncoding = rb_define_class_under(rb_cIconv, "InvalidEncoding", rb_eArgError);
    rb_eIconvIllegalSeq = rb_define_class_under(rb_cIconv, "IllegalSequence", rb_eArgError);
    rb_eIconvInvalidChar = rb_define_class_under(rb_cIconv, "InvalidCharacter", rb_eArgError);
    rb_eIconvOutOfRange = rb_define_class_under(rb_cIconv, "OutOfRange", rb_eRuntimeError);
    rb_eIconvBrokenLibrary = rb_define_class_under(rb_cIconv, "BrokenLibrary", rb_eRuntimeError);
    rb_include_module(rb_eIconvInvalidEncoding, rb_eIconvFailure);
    rb_include_module(rb_eIconvIllegalSeq, rb_eIconvFailure);
    rb_include_module(rb_eIconvInvalidChar, rb_eIconvFailure);
    rb_include_module(rb_eIconvOutOfRange, rb_eIconvFailure);
    rb_include_module(rb_eIconvBrokenLibrary, rb_eIconvFailure);

    rb_success = rb_intern("success");
    rb_failed = rb_intern("failed");

    rb_gc_register_address(&charset_map);
    charset_map = rb_hash_new();
    rb_define_singleton_method(rb_cIconv, "charset_map", charset_map_get, 0);
}

