/* -*- mode:c; c-file-style:"ruby" -*- */
/**********************************************************************

  iconv.c -

  $Author$
  $Date$
  created at: Wed Dec  1 20:28:09 JST 1999

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

/*
=begin
= Summary
Ruby extension for codeset conversion.

= Abstract
Iconv is a wrapper class for UNIX 95 (({iconv()})) function family, which
translates string between various coding systems.

See ((<Open Group|URL:http://www.opengroup.org/>))'s on-line documents for more details.
* ((<iconv.h|URL:http://www.opengroup.org/onlinepubs/007908799/xsh/iconv.h.html>))
* ((<iconv_open()|URL:http://www.opengroup.org/onlinepubs/007908799/xsh/iconv_open.html>))
* ((<iconv()|URL:http://www.opengroup.org/onlinepubs/007908799/xsh/iconv.html>))
* ((<iconv_close()|URL:http://www.opengroup.org/onlinepubs/007908799/xsh/iconv_close.html>))

Which coding systems are available, it depends on the platform.

=end
*/

#include <errno.h>
#include <iconv.h>
#include <assert.h>
#include "ruby.h"
#include "intern.h"

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
};

static VALUE rb_eIconvFailure;
static VALUE rb_eIconvIllegalSeq;
static VALUE rb_eIconvInvalidChar;
static VALUE rb_eIconvOutOfRange;
static ID rb_inserter;

static ID rb_success, rb_failed, rb_mesg;
static VALUE iconv_failure_initialize _((VALUE error, VALUE success, VALUE failed, struct iconv_env_t* env));
static VALUE iconv_failure_success _((VALUE self));
static VALUE iconv_failure_failed _((VALUE self));

static iconv_t iconv_create _((VALUE to, VALUE from));
static VALUE iconv_free _((VALUE cd));
static VALUE iconv_try _((iconv_t cd, const char **inptr, size_t *inlen, char **outptr, size_t *outlen));
static VALUE rb_str_derive _((VALUE str, const char* ptr, int len));
static VALUE iconv_convert _((iconv_t cd, VALUE str, int start, int length, struct iconv_env_t* env));
static VALUE iconv_s_allocate _((VALUE klass));
static VALUE iconv_initialize _((VALUE self, VALUE to, VALUE from));
static VALUE iconv_s_open _((VALUE self, VALUE to, VALUE from));
static VALUE iconv_s_convert _((struct iconv_env_t* env));
static VALUE iconv_s_iconv _((int argc, VALUE *argv, VALUE self));
static VALUE iconv_init_state _((VALUE cd));
static VALUE iconv_finish _((VALUE self));
static VALUE iconv_iconv _((int argc, VALUE *argv, VALUE self));


/*
=begin
= Classes & Modules
=end
*/

/*
=begin
== Iconv
=end
*/
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
    const char* tocode = StringValuePtr(to);
    const char* fromcode = StringValuePtr(from);

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
	    volatile VALUE msg = rb_str_new2("iconv(\"");
	    rb_str_buf_cat2(rb_str_buf_append(msg, to), "\", \"");
	    rb_str_buf_cat2(rb_str_buf_append(msg, from), "\")");
	    rb_sys_fail(StringValuePtr(msg));
	}
    }

    return cd;
}

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

#define ICONV_FREE (RUBY_DATA_FUNC)iconv_free

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
    if (iconv(cd, (char **)inptr, inlen, outptr, outlen) == (size_t)-1) {
	if (!*inlen)
	    return Qfalse;
	switch (errno) {
	  case E2BIG:
	    /* try the left in next loop */
	    break;
	  case EILSEQ:
	    return rb_obj_alloc(rb_eIconvIllegalSeq);
	  case EINVAL:
	    return rb_obj_alloc(rb_eIconvInvalidChar);
	  default:
	    rb_sys_fail("iconv");
	}
    }
    else if (*inlen > 0) {
	/* something goes wrong */
	return rb_obj_alloc(rb_eIconvIllegalSeq);
    }
    return Qfalse;
}

#define iconv_fail(error, success, failed, env) \
	rb_exc_raise(iconv_failure_initialize(error, success, failed, env))

static VALUE
iconv_failure_initialize
#ifdef HAVE_PROTOTYPES
(VALUE error, VALUE success, VALUE failed, struct iconv_env_t* env)
#else /* HAVE_PROTOTYPES */
    (error, success, failed, env)
    VALUE error;
    VALUE success;
    VALUE failed;
    struct iconv_env_t *env;
#endif /* HAVE_PROTOTYPES */
{
    if (NIL_P(rb_ivar_get(error, rb_mesg)))
	rb_ivar_set(error, rb_mesg, rb_inspect(failed));
    if (env) {
	success = rb_funcall3(env->ret, rb_inserter, 1, &success);
	if (env->argc > 0) {
	    *(env->argv) = failed;
	    failed = rb_ary_new4(env->argc, env->argv);
	}
    }
    rb_ivar_set(error, rb_success, success);
    rb_ivar_set(error, rb_failed, failed);
    return error;
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
    ret = rb_str_new(ptr, len);
    OBJ_INFECT(ret, str);
    return ret;
}

static VALUE
iconv_convert
#ifdef HAVE_PROTOTYPES
(iconv_t cd, VALUE str, int start, int length, struct iconv_env_t* env)
#else /* HAVE_PROTOTYPES */
    (cd, str, start, length, env)
    iconv_t cd;
    VALUE str;
    int start;
    int length;
    struct iconv_env_t *env;
#endif /* HAVE_PROTOTYPES */
{
    VALUE ret = Qfalse;
    VALUE error = Qfalse;
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
	if (error)
	    iconv_fail(error, Qnil, Qnil, env);

	inptr = NULL;
	length = 0;
    }
    else {
	int slen;

	Check_Type(str, T_STRING);
	slen = RSTRING(str)->len;
	inptr = RSTRING(str)->ptr;

	if (start < 0 ? (start += slen) < 0 : start >= slen)
	    length = 0;
	else if (length < 0 && (length += slen + 1) < 0)
	    length = 0;
	else if ((length -= start) < 0)
	    length = 0;
	else
	    inptr += start;
    }
    instart = inptr;
    inlen = length;

    do {
	const char *tmpstart = inptr;
	outptr = buffer;
	outlen = sizeof(buffer);

	error = iconv_try(cd, &inptr, &inlen, &outptr, &outlen);

	if (0 <= outlen && outlen <= sizeof(buffer)) {
	    outlen = sizeof(buffer) - outlen;
	    if (outlen > inptr - tmpstart || /* input can't contain output */
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
	    char errmsg[50];
	    sprintf(errmsg, "bug?(output length = %d)", sizeof(buffer) - outlen);
	    error = rb_exc_new2(rb_eIconvOutOfRange, errmsg);
	}

	if (error) {
	    if (!ret)
		ret = rb_str_derive(str, instart, inptr - instart);
	    str = rb_str_derive(str, inptr, inlen);
	    iconv_fail(error, ret, str, env);
	}
    } while (inlen > 0);

    if (!ret)
	ret = rb_str_derive(str, instart, inptr - instart);
    return ret;
}


/*
=begin
=== Class methods
=end
*/
/*
=begin
--- Iconv.new(to, from)
    Creates new code converter from a coding-system designated with ((|from|))
    to another one designated with ((|to|)).
    :Parameters
      :((|to|))
        coding-system name for destination.
      :((|from|))
        coding-system name for source.
    :Exceptions
      :(({TypeError}))
        if ((|to|)) or ((|from|)) aren't String
      :(({ArgumentError}))
        if designated converter couldn't find out.
      :(({SystemCallError}))
        when (({iconv_open(3)})) failed.

--- Iconv.open(to, from)
    Equivalents to ((<Iconv.new>)) except with in the case of called
    with a block, yields with the new instance and closes it, and
    returns the result which returned from the block.
=end
*/
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
    iconv_free((VALUE)(DATA_PTR(self)));
    DATA_PTR(self) = NULL;
    DATA_PTR(self) = (void *)ICONV2VALUE(iconv_create(to, from));
    return self;
}

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

    if (rb_block_given_p()) {
	self = Data_Wrap_Struct(self, NULL, NULL, (void *)cd);
	return rb_ensure(rb_yield, self, (VALUE(*)())iconv_finish, self);
    }
    else {
	return Data_Wrap_Struct(self, NULL, ICONV_FREE, (void *)cd);
    }
}

/*
=begin
--- Iconv.iconv(to, from, *strs)
    Shorthand for
      Iconv.new(to, from) {|cd| (strs + nil).collect {|s| cd.iconv(s)}}
    :Parameters
      :((|to|)), ((|from|))
        see ((<Iconv.new>)).
      :((|strs|))
        strings to be converted.
    :Exceptions
      exceptions thrown by ((<Iconv.new>)) and ((<Iconv#iconv>)).
=end
*/

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
	rb_funcall3(env->ret, rb_inserter, 1, &s);
    }

    if (!NIL_P(last)) {
	VALUE s = iconv_convert(env->cd, Qnil, 0, 0, env);
	if (RSTRING(s)->len)
	    rb_funcall3(env->ret, rb_inserter, 1, &s);
    }

    return env->ret;
}

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
	rb_raise(rb_eArgError, "wrong # of arguments (%d for %d)", argc, 2);

    arg.argc = argc -= 2;
    arg.argv = argv + 2;
    arg.ret = rb_ary_new2(argc);
    arg.cd = iconv_create(argv[0], argv[1]);
    return rb_ensure(iconv_s_convert, (VALUE)&arg, iconv_free, ICONV2VALUE(arg.cd));
}


/*
=begin
=== Instance methods
=end
*/
/*
=begin
--- Iconv#close
    Finishes conversion.
    * After calling this, invoking method ((<Iconv#iconv>)) will cause
      exception, but multiple calls of (({close})) are guaranteed to
      end successfully.
    * Returns a string contains the byte sequence to change the
      output buffer to its initial shift state.
=end
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
    VALUE cd;

    Check_Type(self, T_DATA);

    cd = (VALUE)DATA_PTR(self);
    if (!cd) return Qnil;
    DATA_PTR(self) = NULL;

    return rb_ensure(iconv_init_state, cd, iconv_free, cd);
}

/*
=begin
--- Iconv#iconv(str, [ start = 0, [ length = -1 ] ])
    Converts string and returns converted one.
    * In the case of ((|str|)) is (({String})), converts (({str[start, length]})).
      Returns converted string.
    * In the case of ((|str|)) is (({nil})), places ((|converter|))
      itself into initial shift state and just returns a string contains
      the byte sequence to change the output buffer to its initial shift
      state.
    * Otherwise, causes exception.
    :Parameters
      :((|str|))
        string to be converted or (({nil})).
      :((|start|))
        starting offset.
      :((|length|))
        conversion length,
        (({nil})) or (({-1})) means whole string from (({start})).
    :Exceptions
      * ((<Iconv::IllegalSequence>))
      * ((<Iconv::InvalidCharacter>))
      * ((<Iconv::OutOfRange>))
=end
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

    Check_Type(self, T_DATA);

    n1 = n2 = Qnil;
    rb_scan_args(argc, argv, "12", &str, &n1, &n2);

    return iconv_convert(VALUE2ICONV(DATA_PTR(self)), str,
			 NIL_P(n1) ? 0 : NUM2INT(n1),
			 NIL_P(n2) ? -1 : NUM2INT(n1),
			 NULL);
}


/*
=begin
= Exceptions
=end
*/
/*
=begin
== Iconv::Failure
Base exceptional attributes from ((<Iconv>)).

=== Instance methods
=end
*/
/*
=begin
--- Iconv::Failure#success
    Returns string(s) translated successfully until the exception occurred.
    * In the case of failure occurred within ((<Iconv.iconv>)), returned
      value is an array of strings translated successfully preceding
      failure and the last element is string on the way.
=end
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
    return rb_ivar_get(self, rb_success);
}

/*
=begin
--- Iconv::Failure#failed
    Returns substring of the original string passed to ((<Iconv>)) that
    starts at the character caused the exception. 
=end
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
    return rb_ivar_get(self, rb_failed);
}

/*
=begin
--- Iconv::Failure#inspect
    Returns inspected string like as: #<(({type})): "(({success}))", "(({failed}))">
=end
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
    char *cname = rb_class2name(CLASS_OF(self));
    VALUE success = iconv_failure_success(self);
    VALUE failed = iconv_failure_failed(self);
    VALUE str = rb_str_buf_cat2(rb_str_new2("#<"), cname);
    str = rb_str_buf_cat(str, ": ", 2);
    str = rb_str_buf_append(str, rb_inspect(success));
    str = rb_str_buf_cat(str, ", ", 2);
    str = rb_str_buf_append(str, rb_inspect(failed));
    return rb_str_buf_cat(str, ">", 1);
}

/*
  Hmmm, I don't like to write RD inside of function :-<.

=begin
== Iconv::IllegalSequence
Exception in the case of any illegal sequence detected.
=== Superclass
(({ArgumentError}))
=== Included Modules
((<Iconv::Failure>))

== Iconv::InvalidCharacter
Exception in the case of output coding system can't express the character.
=== Superclass
(({ArgumentError}))
=== Included Modules
((<Iconv::Failure>))

== Iconv::OutOfRange
Iconv library internal error.  Must not occur.
=== Superclass
(({RuntimeError}))
=== Included Modules
((<Iconv::Failure>))
=end
*/

void
Init_iconv _((void))
{
    VALUE rb_cIconv = rb_define_class("Iconv", rb_cData);
    rb_define_singleton_method(rb_cIconv, "allocate", iconv_s_allocate, 0);
    rb_define_singleton_method(rb_cIconv, "open", iconv_s_open, 2);
    rb_define_singleton_method(rb_cIconv, "iconv", iconv_s_iconv, -1);
    rb_define_method(rb_cIconv, "initialize", iconv_initialize, 2);
    rb_define_method(rb_cIconv, "close", iconv_finish, 0);
    rb_define_method(rb_cIconv, "iconv", iconv_iconv, -1);

    rb_eIconvFailure = rb_define_module_under(rb_cIconv, "Failure");
    rb_define_method(rb_eIconvFailure, "success", iconv_failure_success, 0);
    rb_define_method(rb_eIconvFailure, "failed", iconv_failure_failed, 0);
    rb_define_method(rb_eIconvFailure, "inspect", iconv_failure_inspect, 0);

    rb_eIconvIllegalSeq = rb_define_class_under(rb_cIconv, "IllegalSequence", rb_eArgError);
    rb_eIconvInvalidChar = rb_define_class_under(rb_cIconv, "InvalidCharacter", rb_eArgError);
    rb_eIconvOutOfRange = rb_define_class_under(rb_cIconv, "OutOfRange", rb_eRuntimeError);
    rb_include_module(rb_eIconvIllegalSeq, rb_eIconvFailure);
    rb_include_module(rb_eIconvInvalidChar, rb_eIconvFailure);
    rb_include_module(rb_eIconvOutOfRange, rb_eIconvFailure);

    rb_inserter = rb_intern("<<");
    rb_success = rb_intern("success");
    rb_failed = rb_intern("failed");
    rb_mesg = rb_intern("mesg");
}


/*
=begin
== Example
(1) Instantiate a new ((<Iconv>)), use method ((<Iconv#iconv>)).
      cd = Iconv.new(to, from)
      begin
        input.each {|s| output << cd.iconv(s)}
        output << cd.iconv(nil)      # don't forget this
      ensure
        cd.close
      end
(2) Invoke ((<Iconv.new>)) with a block.
      Iconv.new(to, from) do |cd|
        input.each {|s| output << cd.iconv(s)}
        output << cd.iconv(nil)
      end
(3) Shorthand for (2).
      Iconv.iconv(to, from, *input.to_a)
=end
*/
