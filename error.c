/**********************************************************************

  error.c -

  $Author$
  created at: Mon Aug  9 16:11:34 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/st.h"
#include "ruby/encoding.h"
#include "vm_core.h"

#include <stdio.h>
#include <stdarg.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <errno.h>

#ifndef EXIT_SUCCESS
#define EXIT_SUCCESS 0
#endif

#ifndef WIFEXITED
#define WIFEXITED(status) 1
#endif

#ifndef WEXITSTATUS
#define WEXITSTATUS(status) (status)
#endif

extern const char ruby_description[];

static const char *
rb_strerrno(int err)
{
#define defined_error(name, num) if (err == (num)) return (name);
#define undefined_error(name)
#include "known_errors.inc"
#undef defined_error
#undef undefined_error
    return NULL;
}

static int
err_position_0(char *buf, long len, const char *file, int line)
{
    if (!file) {
	return 0;
    }
    else if (line == 0) {
	return snprintf(buf, len, "%s: ", file);
    }
    else {
	return snprintf(buf, len, "%s:%d: ", file, line);
    }
}

static int
err_position(char *buf, long len)
{
    return err_position_0(buf, len, rb_sourcefile(), rb_sourceline());
}

static void
err_snprintf(char *buf, long len, const char *fmt, va_list args)
{
    long n;

    n = err_position(buf, len);
    if (len > n) {
	vsnprintf((char*)buf+n, len-n, fmt, args);
    }
}

static void
compile_snprintf(char *buf, long len, const char *file, int line, const char *fmt, va_list args)
{
    long n;

    n = err_position_0(buf, len, file, line);
    if (len > n) {
	vsnprintf((char*)buf+n, len-n, fmt, args);
    }
}

static void err_append(const char*);

void
rb_compile_error(const char *file, int line, const char *fmt, ...)
{
    va_list args;
    char buf[BUFSIZ];

    va_start(args, fmt);
    compile_snprintf(buf, BUFSIZ, file, line, fmt, args);
    va_end(args);
    err_append(buf);
}

void
rb_compile_error_append(const char *fmt, ...)
{
    va_list args;
    char buf[BUFSIZ];

    va_start(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);
    err_append(buf);
}

static void
compile_warn_print(const char *file, int line, const char *fmt, va_list args)
{
    char buf[BUFSIZ];
    int len;

    compile_snprintf(buf, BUFSIZ, file, line, fmt, args);
    len = (int)strlen(buf);
    buf[len++] = '\n';
    rb_write_error2(buf, len);
}

void
rb_compile_warn(const char *file, int line, const char *fmt, ...)
{
    char buf[BUFSIZ];
    va_list args;

    if (NIL_P(ruby_verbose)) return;

    snprintf(buf, BUFSIZ, "warning: %s", fmt);

    va_start(args, fmt);
    compile_warn_print(file, line, buf, args);
    va_end(args);
}

/* rb_compile_warning() reports only in verbose mode */
void
rb_compile_warning(const char *file, int line, const char *fmt, ...)
{
    char buf[BUFSIZ];
    va_list args;

    if (!RTEST(ruby_verbose)) return;

    snprintf(buf, BUFSIZ, "warning: %s", fmt);

    va_start(args, fmt);
    compile_warn_print(file, line, buf, args);
    va_end(args);
}

static void
warn_print(const char *fmt, va_list args)
{
    char buf[BUFSIZ];
    int len;

    err_snprintf(buf, BUFSIZ, fmt, args);
    len = (int)strlen(buf);
    buf[len++] = '\n';
    rb_write_error2(buf, len);
}

void
rb_warn(const char *fmt, ...)
{
    char buf[BUFSIZ];
    va_list args;

    if (NIL_P(ruby_verbose)) return;

    snprintf(buf, BUFSIZ, "warning: %s", fmt);

    va_start(args, fmt);
    warn_print(buf, args);
    va_end(args);
}

/* rb_warning() reports only in verbose mode */
void
rb_warning(const char *fmt, ...)
{
    char buf[BUFSIZ];
    va_list args;

    if (!RTEST(ruby_verbose)) return;

    snprintf(buf, BUFSIZ, "warning: %s", fmt);

    va_start(args, fmt);
    warn_print(buf, args);
    va_end(args);
}

/*
 * call-seq:
 *    warn(msg)   -> nil
 *
 * Display the given message (followed by a newline) on STDERR unless
 * warnings are disabled (for example with the <code>-W0</code> flag).
 */

static VALUE
rb_warn_m(VALUE self, VALUE mesg)
{
    if (!NIL_P(ruby_verbose)) {
	rb_io_write(rb_stderr, mesg);
	rb_io_write(rb_stderr, rb_default_rs);
    }
    return Qnil;
}

void rb_vm_bugreport(void);

static void
report_bug(const char *file, int line, const char *fmt, va_list args)
{
    char buf[BUFSIZ];
    FILE *out = stderr;
    int len = err_position_0(buf, BUFSIZ, file, line);

    if ((ssize_t)fwrite(buf, 1, len, out) == (ssize_t)len ||
	(ssize_t)fwrite(buf, 1, len, (out = stdout)) == (ssize_t)len) {

	fputs("[BUG] ", out);
	vfprintf(out, fmt, args);
	fprintf(out, "\n%s\n\n", ruby_description);

	rb_vm_bugreport();

	fprintf(out,
		"[NOTE]\n"
		"You may have encountered a bug in the Ruby interpreter"
		" or extension libraries.\n"
		"Bug reports are welcome.\n"
		"For details: http://www.ruby-lang.org/bugreport.html\n\n");
    }
}

void
rb_bug(const char *fmt, ...)
{
    va_list args;

    va_start(args, fmt);
    report_bug(rb_sourcefile(), rb_sourceline(), fmt, args);
    va_end(args);

#if defined(_WIN32) && defined(RT_VER) && RT_VER >= 80
    _set_abort_behavior( 0, _CALL_REPORTFAULT);
#endif

    abort();
}

void
rb_bug_errno(const char *mesg, int errno_arg)
{
    if (errno_arg == 0)
        rb_bug("%s: errno == 0 (NOERROR)", mesg);
    else {
        const char *errno_str = rb_strerrno(errno_arg);
        if (errno_str)
            rb_bug("%s: %s (%s)", mesg, strerror(errno_arg), errno_str);
        else
            rb_bug("%s: %s (%d)", mesg, strerror(errno_arg), errno_arg);
    }
}

void
rb_compile_bug(const char *file, int line, const char *fmt, ...)
{
    va_list args;

    va_start(args, fmt);
    report_bug(file, line, fmt, args);
    va_end(args);

    abort();
}

static const struct types {
    int type;
    const char *name;
} builtin_types[] = {
    {T_NIL,	"nil"},
    {T_OBJECT,	"Object"},
    {T_CLASS,	"Class"},
    {T_ICLASS,	"iClass"},	/* internal use: mixed-in module holder */
    {T_MODULE,	"Module"},
    {T_FLOAT,	"Float"},
    {T_STRING,	"String"},
    {T_REGEXP,	"Regexp"},
    {T_ARRAY,	"Array"},
    {T_FIXNUM,	"Fixnum"},
    {T_HASH,	"Hash"},
    {T_STRUCT,	"Struct"},
    {T_BIGNUM,	"Bignum"},
    {T_FILE,	"File"},
    {T_RATIONAL,"Rational"},
    {T_COMPLEX, "Complex"},
    {T_TRUE,	"true"},
    {T_FALSE,	"false"},
    {T_SYMBOL,	"Symbol"},	/* :symbol */
    {T_DATA,	"Data"},	/* internal use: wrapped C pointers */
    {T_MATCH,	"MatchData"},	/* data of $~ */
    {T_NODE,	"Node"},	/* internal use: syntax tree node */
    {T_UNDEF,	"undef"},	/* internal use: #undef; should not happen */
};

void
rb_check_type(VALUE x, int t)
{
    const struct types *type = builtin_types;
    const struct types *const typeend = builtin_types +
	sizeof(builtin_types) / sizeof(builtin_types[0]);
    int xt;

    if (x == Qundef) {
	rb_bug("undef leaked to the Ruby space");
    }

    xt = TYPE(x);
    if (xt != t || (xt == T_DATA && RTYPEDDATA_P(x))) {
	while (type < typeend) {
	    if (type->type == t) {
		const char *etype;

		if (NIL_P(x)) {
		    etype = "nil";
		}
		else if (FIXNUM_P(x)) {
		    etype = "Fixnum";
		}
		else if (SYMBOL_P(x)) {
		    etype = "Symbol";
		}
		else if (rb_special_const_p(x)) {
		    etype = RSTRING_PTR(rb_obj_as_string(x));
		}
		else {
		    etype = rb_obj_classname(x);
		}
		rb_raise(rb_eTypeError, "wrong argument type %s (expected %s)",
			 etype, type->name);
	    }
	    type++;
	}
	rb_bug("unknown type 0x%x (0x%x given)", t, TYPE(x));
    }
}

int
rb_typeddata_inherited_p(const rb_data_type_t *child, const rb_data_type_t *parent)
{
    while (child) {
	if (child == parent) return 1;
	child = child->parent;
    }
    return 0;
}

int
rb_typeddata_is_kind_of(VALUE obj, const rb_data_type_t *data_type)
{
    if (SPECIAL_CONST_P(obj) || BUILTIN_TYPE(obj) != T_DATA ||
	!RTYPEDDATA_P(obj) || !rb_typeddata_inherited_p(RTYPEDDATA_TYPE(obj), data_type)) {
	return 0;
    }
    return 1;
}

void *
rb_check_typeddata(VALUE obj, const rb_data_type_t *data_type)
{
    const char *etype;
    static const char mesg[] = "wrong argument type %s (expected %s)";

    if (SPECIAL_CONST_P(obj) || BUILTIN_TYPE(obj) != T_DATA) {
	Check_Type(obj, T_DATA);
    }
    if (!RTYPEDDATA_P(obj)) {
	etype = rb_obj_classname(obj);
	rb_raise(rb_eTypeError, mesg, etype, data_type->wrap_struct_name);
    }
    else if (!rb_typeddata_inherited_p(RTYPEDDATA_TYPE(obj), data_type)) {
	etype = RTYPEDDATA_TYPE(obj)->wrap_struct_name;
	rb_raise(rb_eTypeError, mesg, etype, data_type->wrap_struct_name);
    }
    return DATA_PTR(obj);
}

/* exception classes */
VALUE rb_eException;
VALUE rb_eSystemExit;
VALUE rb_eInterrupt;
VALUE rb_eSignal;
VALUE rb_eFatal;
VALUE rb_eStandardError;
VALUE rb_eRuntimeError;
VALUE rb_eTypeError;
VALUE rb_eArgError;
VALUE rb_eIndexError;
VALUE rb_eKeyError;
VALUE rb_eRangeError;
VALUE rb_eNameError;
VALUE rb_eEncodingError;
VALUE rb_eEncCompatError;
VALUE rb_eNoMethodError;
VALUE rb_eSecurityError;
VALUE rb_eNotImpError;
VALUE rb_eNoMemError;
VALUE rb_cNameErrorMesg;

VALUE rb_eScriptError;
VALUE rb_eSyntaxError;
VALUE rb_eLoadError;

VALUE rb_eSystemCallError;
VALUE rb_mErrno;
static VALUE rb_eNOERROR;

#undef rb_exc_new2

VALUE
rb_exc_new(VALUE etype, const char *ptr, long len)
{
    return rb_funcall(etype, rb_intern("new"), 1, rb_str_new(ptr, len));
}

VALUE
rb_exc_new2(VALUE etype, const char *s)
{
    return rb_exc_new(etype, s, strlen(s));
}

VALUE
rb_exc_new3(VALUE etype, VALUE str)
{
    StringValue(str);
    return rb_funcall(etype, rb_intern("new"), 1, str);
}

/*
 * call-seq:
 *    Exception.new(msg = nil)   ->  exception
 *
 *  Construct a new Exception object, optionally passing in
 *  a message.
 */

static VALUE
exc_initialize(int argc, VALUE *argv, VALUE exc)
{
    VALUE arg;

    rb_scan_args(argc, argv, "01", &arg);
    rb_iv_set(exc, "mesg", arg);
    rb_iv_set(exc, "bt", Qnil);

    return exc;
}

/*
 *  Document-method: exception
 *
 *  call-seq:
 *     exc.exception(string)  ->  an_exception or exc
 *
 *  With no argument, or if the argument is the same as the receiver,
 *  return the receiver. Otherwise, create a new
 *  exception object of the same class as the receiver, but with a
 *  message equal to <code>string.to_str</code>.
 *
 */

static VALUE
exc_exception(int argc, VALUE *argv, VALUE self)
{
    VALUE exc;

    if (argc == 0) return self;
    if (argc == 1 && self == argv[0]) return self;
    exc = rb_obj_clone(self);
    exc_initialize(argc, argv, exc);

    return exc;
}

/*
 * call-seq:
 *   exception.to_s   ->  string
 *
 * Returns exception's message (or the name of the exception if
 * no message is set).
 */

static VALUE
exc_to_s(VALUE exc)
{
    VALUE mesg = rb_attr_get(exc, rb_intern("mesg"));

    if (NIL_P(mesg)) return rb_class_name(CLASS_OF(exc));
    OBJ_INFECT(mesg, exc);
    return mesg;
}

/*
 * call-seq:
 *   exception.message   ->  string
 *
 * Returns the result of invoking <code>exception.to_s</code>.
 * Normally this returns the exception's message or name. By
 * supplying a to_str method, exceptions are agreeing to
 * be used where Strings are expected.
 */

static VALUE
exc_message(VALUE exc)
{
    return rb_funcall(exc, rb_intern("to_s"), 0, 0);
}

/*
 * call-seq:
 *   exception.inspect   -> string
 *
 * Return this exception's class name an message
 */

static VALUE
exc_inspect(VALUE exc)
{
    VALUE str, klass;

    klass = CLASS_OF(exc);
    exc = rb_obj_as_string(exc);
    if (RSTRING_LEN(exc) == 0) {
	return rb_str_dup(rb_class_name(klass));
    }

    str = rb_str_buf_new2("#<");
    klass = rb_class_name(klass);
    rb_str_buf_append(str, klass);
    rb_str_buf_cat(str, ": ", 2);
    rb_str_buf_append(str, exc);
    rb_str_buf_cat(str, ">", 1);

    return str;
}

/*
 *  call-seq:
 *     exception.backtrace    -> array
 *
 *  Returns any backtrace associated with the exception. The backtrace
 *  is an array of strings, each containing either ``filename:lineNo: in
 *  `method''' or ``filename:lineNo.''
 *
 *     def a
 *       raise "boom"
 *     end
 *
 *     def b
 *       a()
 *     end
 *
 *     begin
 *       b()
 *     rescue => detail
 *       print detail.backtrace.join("\n")
 *     end
 *
 *  <em>produces:</em>
 *
 *     prog.rb:2:in `a'
 *     prog.rb:6:in `b'
 *     prog.rb:10
*/

static VALUE
exc_backtrace(VALUE exc)
{
    ID bt;

    CONST_ID(bt, "bt");
    return rb_attr_get(exc, bt);
}

VALUE
rb_check_backtrace(VALUE bt)
{
    long i;
    static const char err[] = "backtrace must be Array of String";

    if (!NIL_P(bt)) {
	int t = TYPE(bt);

	if (t == T_STRING) return rb_ary_new3(1, bt);
	if (t != T_ARRAY) {
	    rb_raise(rb_eTypeError, err);
	}
	for (i=0;i<RARRAY_LEN(bt);i++) {
	    if (TYPE(RARRAY_PTR(bt)[i]) != T_STRING) {
		rb_raise(rb_eTypeError, err);
	    }
	}
    }
    return bt;
}

/*
 *  call-seq:
 *     exc.set_backtrace(array)   ->  array
 *
 *  Sets the backtrace information associated with <i>exc</i>. The
 *  argument must be an array of <code>String</code> objects in the
 *  format described in <code>Exception#backtrace</code>.
 *
 */

static VALUE
exc_set_backtrace(VALUE exc, VALUE bt)
{
    return rb_iv_set(exc, "bt", rb_check_backtrace(bt));
}

/*
 *  call-seq:
 *     exc == obj   -> true or false
 *
 *  Equality---If <i>obj</i> is not an <code>Exception</code>, returns
 *  <code>false</code>. Otherwise, returns <code>true</code> if <i>exc</i> and
 *  <i>obj</i> share same class, messages, and backtrace.
 */

static VALUE
exc_equal(VALUE exc, VALUE obj)
{
    VALUE mesg, backtrace;
    ID id_mesg;

    if (exc == obj) return Qtrue;
    CONST_ID(id_mesg, "mesg");

    if (rb_obj_class(exc) != rb_obj_class(obj)) {
	ID id_message, id_backtrace;
	CONST_ID(id_message, "message");
	CONST_ID(id_backtrace, "backtrace");

	mesg = rb_check_funcall(obj, id_message, 0, 0);
	if (mesg == Qundef) return Qfalse;
	backtrace = rb_check_funcall(obj, id_backtrace, 0, 0);
	if (backtrace == Qundef) return Qfalse;
    }
    else {
	mesg = rb_attr_get(obj, id_mesg);
	backtrace = exc_backtrace(obj);
    }

    if (!rb_equal(rb_attr_get(exc, id_mesg), mesg))
	return Qfalse;
    if (!rb_equal(exc_backtrace(exc), backtrace))
	return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *   SystemExit.new(status=0)   -> system_exit
 *
 * Create a new +SystemExit+ exception with the given status.
 */

static VALUE
exit_initialize(int argc, VALUE *argv, VALUE exc)
{
    VALUE status = INT2FIX(EXIT_SUCCESS);
    if (argc > 0 && FIXNUM_P(argv[0])) {
	status = *argv++;
	--argc;
    }
    rb_call_super(argc, argv);
    rb_iv_set(exc, "status", status);
    return exc;
}


/*
 * call-seq:
 *   system_exit.status   -> fixnum
 *
 * Return the status value associated with this system exit.
 */

static VALUE
exit_status(VALUE exc)
{
    return rb_attr_get(exc, rb_intern("status"));
}


/*
 * call-seq:
 *   system_exit.success?  -> true or false
 *
 * Returns +true+ if exiting successful, +false+ if not.
 */

static VALUE
exit_success_p(VALUE exc)
{
    VALUE status_val = rb_attr_get(exc, rb_intern("status"));
    int status;

    if (NIL_P(status_val))
	return Qtrue;
    status = NUM2INT(status_val);
    if (WIFEXITED(status) && WEXITSTATUS(status) == EXIT_SUCCESS)
	return Qtrue;

    return Qfalse;
}

void
rb_name_error(ID id, const char *fmt, ...)
{
    VALUE exc, argv[2];
    va_list args;

    va_start(args, fmt);
    argv[0] = rb_vsprintf(fmt, args);
    va_end(args);

    argv[1] = ID2SYM(id);
    exc = rb_class_new_instance(2, argv, rb_eNameError);
    rb_exc_raise(exc);
}

/*
 * call-seq:
 *   NameError.new(msg [, name])  -> name_error
 *
 * Construct a new NameError exception. If given the <i>name</i>
 * parameter may subsequently be examined using the <code>NameError.name</code>
 * method.
 */

static VALUE
name_err_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE name;

    name = (argc > 1) ? argv[--argc] : Qnil;
    rb_call_super(argc, argv);
    rb_iv_set(self, "name", name);
    return self;
}

/*
 *  call-seq:
 *    name_error.name    ->  string or nil
 *
 *  Return the name associated with this NameError exception.
 */

static VALUE
name_err_name(VALUE self)
{
    return rb_attr_get(self, rb_intern("name"));
}

/*
 * call-seq:
 *  name_error.to_s   -> string
 *
 * Produce a nicely-formatted string representing the +NameError+.
 */

static VALUE
name_err_to_s(VALUE exc)
{
    VALUE mesg = rb_attr_get(exc, rb_intern("mesg"));
    VALUE str = mesg;

    if (NIL_P(mesg)) return rb_class_name(CLASS_OF(exc));
    StringValue(str);
    if (str != mesg) {
	rb_iv_set(exc, "mesg", mesg = str);
    }
    OBJ_INFECT(mesg, exc);
    return mesg;
}

/*
 * call-seq:
 *   NoMethodError.new(msg, name [, args])  -> no_method_error
 *
 * Construct a NoMethodError exception for a method of the given name
 * called with the given arguments. The name may be accessed using
 * the <code>#name</code> method on the resulting object, and the
 * arguments using the <code>#args</code> method.
 */

static VALUE
nometh_err_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE args = (argc > 2) ? argv[--argc] : Qnil;
    name_err_initialize(argc, argv, self);
    rb_iv_set(self, "args", args);
    return self;
}

/* :nodoc: */
#define NAME_ERR_MESG_COUNT 3

static void
name_err_mesg_mark(void *p)
{
    VALUE *ptr = p;
    rb_gc_mark_locations(ptr, ptr+NAME_ERR_MESG_COUNT);
}

#define name_err_mesg_free RUBY_TYPED_DEFAULT_FREE

static size_t
name_err_mesg_memsize(const void *p)
{
    return p ? (NAME_ERR_MESG_COUNT * sizeof(VALUE)) : 0;
}

static const rb_data_type_t name_err_mesg_data_type = {
    "name_err_mesg",
    {
	name_err_mesg_mark,
	name_err_mesg_free,
	name_err_mesg_memsize,
    },
};

/* :nodoc: */
VALUE
rb_name_err_mesg_new(VALUE obj, VALUE mesg, VALUE recv, VALUE method)
{
    VALUE *ptr = ALLOC_N(VALUE, NAME_ERR_MESG_COUNT);
    VALUE result;

    ptr[0] = mesg;
    ptr[1] = recv;
    ptr[2] = method;
    result = TypedData_Wrap_Struct(rb_cNameErrorMesg, &name_err_mesg_data_type, ptr);
    RB_GC_GUARD(mesg);
    RB_GC_GUARD(recv);
    RB_GC_GUARD(method);
    return result;
}

/* :nodoc: */
static VALUE
name_err_mesg_equal(VALUE obj1, VALUE obj2)
{
    VALUE *ptr1, *ptr2;
    int i;

    if (obj1 == obj2) return Qtrue;
    if (rb_obj_class(obj2) != rb_cNameErrorMesg)
	return Qfalse;

    TypedData_Get_Struct(obj1, VALUE, &name_err_mesg_data_type, ptr1);
    TypedData_Get_Struct(obj2, VALUE, &name_err_mesg_data_type, ptr2);
    for (i=0; i<NAME_ERR_MESG_COUNT; i++) {
	if (!rb_equal(ptr1[i], ptr2[i]))
	    return Qfalse;
    }
    return Qtrue;
}

/* :nodoc: */
static VALUE
name_err_mesg_to_str(VALUE obj)
{
    VALUE *ptr, mesg;
    TypedData_Get_Struct(obj, VALUE, &name_err_mesg_data_type, ptr);

    mesg = ptr[0];
    if (NIL_P(mesg)) return Qnil;
    else {
	const char *desc = 0;
	VALUE d = 0, args[NAME_ERR_MESG_COUNT];

	obj = ptr[1];
	switch (TYPE(obj)) {
	  case T_NIL:
	    desc = "nil";
	    break;
	  case T_TRUE:
	    desc = "true";
	    break;
	  case T_FALSE:
	    desc = "false";
	    break;
	  default:
	    d = rb_protect(rb_inspect, obj, 0);
	    if (NIL_P(d) || RSTRING_LEN(d) > 65) {
		d = rb_any_to_s(obj);
	    }
	    desc = RSTRING_PTR(d);
	    break;
	}
	if (desc && desc[0] != '#') {
	    d = d ? rb_str_dup(d) : rb_str_new2(desc);
	    rb_str_cat2(d, ":");
	    rb_str_cat2(d, rb_obj_classname(obj));
	}
	args[0] = mesg;
	args[1] = ptr[2];
	args[2] = d;
	mesg = rb_f_sprintf(NAME_ERR_MESG_COUNT, args);
    }
    OBJ_INFECT(mesg, obj);
    return mesg;
}

/* :nodoc: */
static VALUE
name_err_mesg_load(VALUE klass, VALUE str)
{
    return str;
}

/*
 * call-seq:
 *   no_method_error.args  -> obj
 *
 * Return the arguments passed in as the third parameter to
 * the constructor.
 */

static VALUE
nometh_err_args(VALUE self)
{
    return rb_attr_get(self, rb_intern("args"));
}

void
rb_invalid_str(const char *str, const char *type)
{
    VALUE s = rb_str_inspect(rb_str_new2(str));

    rb_raise(rb_eArgError, "invalid value for %s: %s", type, RSTRING_PTR(s));
}

/*
 *  Document-module: Errno
 *
 *  Ruby exception objects are subclasses of <code>Exception</code>.
 *  However, operating systems typically report errors using plain
 *  integers. Module <code>Errno</code> is created dynamically to map
 *  these operating system errors to Ruby classes, with each error
 *  number generating its own subclass of <code>SystemCallError</code>.
 *  As the subclass is created in module <code>Errno</code>, its name
 *  will start <code>Errno::</code>.
 *
 *  The names of the <code>Errno::</code> classes depend on
 *  the environment in which Ruby runs. On a typical Unix or Windows
 *  platform, there are <code>Errno</code> classes such as
 *  <code>Errno::EACCES</code>, <code>Errno::EAGAIN</code>,
 *  <code>Errno::EINTR</code>, and so on.
 *
 *  The integer operating system error number corresponding to a
 *  particular error is available as the class constant
 *  <code>Errno::</code><em>error</em><code>::Errno</code>.
 *
 *     Errno::EACCES::Errno   #=> 13
 *     Errno::EAGAIN::Errno   #=> 11
 *     Errno::EINTR::Errno    #=> 4
 *
 *  The full list of operating system errors on your particular platform
 *  are available as the constants of <code>Errno</code>.
 *
 *     Errno.constants   #=> :E2BIG, :EACCES, :EADDRINUSE, :EADDRNOTAVAIL, ...
 */

static st_table *syserr_tbl;

static VALUE
set_syserr(int n, const char *name)
{
    st_data_t error;

    if (!st_lookup(syserr_tbl, n, &error)) {
	error = rb_define_class_under(rb_mErrno, name, rb_eSystemCallError);
	rb_define_const(error, "Errno", INT2NUM(n));
	st_add_direct(syserr_tbl, n, error);
    }
    else {
	rb_define_const(rb_mErrno, name, error);
    }
    return error;
}

static VALUE
get_syserr(int n)
{
    st_data_t error;

    if (!st_lookup(syserr_tbl, n, &error)) {
	char name[8];	/* some Windows' errno have 5 digits. */

	snprintf(name, sizeof(name), "E%03d", n);
	error = set_syserr(n, name);
    }
    return error;
}

/*
 * call-seq:
 *   SystemCallError.new(msg, errno)  -> system_call_error_subclass
 *
 * If _errno_ corresponds to a known system error code, constructs
 * the appropriate <code>Errno</code> class for that error, otherwise
 * constructs a generic <code>SystemCallError</code> object. The
 * error number is subsequently available via the <code>errno</code>
 * method.
 */

static VALUE
syserr_initialize(int argc, VALUE *argv, VALUE self)
{
#if !defined(_WIN32)
    char *strerror();
#endif
    const char *err;
    VALUE mesg, error;
    VALUE klass = rb_obj_class(self);

    if (klass == rb_eSystemCallError) {
	st_data_t data = (st_data_t)klass;
	rb_scan_args(argc, argv, "11", &mesg, &error);
	if (argc == 1 && FIXNUM_P(mesg)) {
	    error = mesg; mesg = Qnil;
	}
	if (!NIL_P(error) && st_lookup(syserr_tbl, NUM2LONG(error), &data)) {
	    klass = (VALUE)data;
	    /* change class */
	    if (TYPE(self) != T_OBJECT) { /* insurance to avoid type crash */
		rb_raise(rb_eTypeError, "invalid instance type");
	    }
	    RBASIC(self)->klass = klass;
	}
    }
    else {
	rb_scan_args(argc, argv, "01", &mesg);
	error = rb_const_get(klass, rb_intern("Errno"));
    }
    if (!NIL_P(error)) err = strerror(NUM2INT(error));
    else err = "unknown error";
    if (!NIL_P(mesg)) {
	rb_encoding *le = rb_locale_encoding();
	VALUE str = mesg;

	StringValue(str);
	mesg = rb_sprintf("%s - %.*s", err,
			  (int)RSTRING_LEN(str), RSTRING_PTR(str));
	if (le == rb_usascii_encoding()) {
	    rb_encoding *me = rb_enc_get(mesg);
	    if (le != me && rb_enc_asciicompat(me))
		le = me;
	}/* else assume err is non ASCII string. */
	OBJ_INFECT(mesg, str);
	rb_enc_associate(mesg, le);
    }
    else {
	mesg = rb_str_new2(err);
	rb_enc_associate(mesg, rb_locale_encoding());
    }
    rb_call_super(1, &mesg);
    rb_iv_set(self, "errno", error);
    return self;
}

/*
 * call-seq:
 *   system_call_error.errno   -> fixnum
 *
 * Return this SystemCallError's error number.
 */

static VALUE
syserr_errno(VALUE self)
{
    return rb_attr_get(self, rb_intern("errno"));
}

/*
 * call-seq:
 *   system_call_error === other  -> true or false
 *
 * Return +true+ if the receiver is a generic +SystemCallError+, or
 * if the error numbers +self+ and _other_ are the same.
 */

static VALUE
syserr_eqq(VALUE self, VALUE exc)
{
    VALUE num, e;
    ID en;

    CONST_ID(en, "errno");

    if (!rb_obj_is_kind_of(exc, rb_eSystemCallError)) {
	if (!rb_respond_to(exc, en)) return Qfalse;
    }
    else if (self == rb_eSystemCallError) return Qtrue;

    num = rb_attr_get(exc, rb_intern("errno"));
    if (NIL_P(num)) {
	num = rb_funcall(exc, en, 0, 0);
    }
    e = rb_const_get(self, rb_intern("Errno"));
    if (FIXNUM_P(num) ? num == e : rb_equal(num, e))
	return Qtrue;
    return Qfalse;
}


/*
 *  Document-class: StandardError
 *
 *  The most standard error types are subclasses of StandardError. A
 *  rescue clause without an explicit Exception class will rescue all
 *  StandardErrors (and only those).
 *
 *     def foo
 *       raise "Oups"
 *     end
 *     foo rescue "Hello"   #=> "Hello"
 *
 *  On the other hand:
 *
 *     require 'does/not/exist' rescue "Hi"
 *
 *  <em>raises the exception:</em>
 *
 *     LoadError: no such file to load -- does/not/exist
 *
 */

/*
 *  Document-class: SystemExit
 *
 *  Raised by +exit+ to initiate the termination of the script.
 */

/*
 *  Document-class: SignalException
 *
 *  Raised when a signal is received.
 *
 *     begin
 *       Process.kill('HUP',Process.pid)
 *     rescue SignalException => e
 *       puts "received Exception #{e}"
 *     end
 *
 *  <em>produces:</em>
 *
 *     received Exception SIGHUP
 */

/*
 *  Document-class: Interrupt
 *
 *  Raised with the interrupt signal is received, typically because the
 *  user pressed on Control-C (on most posix platforms). As such, it is a
 *  subclass of +SignalException+.
 *
 *     begin
 *       puts "Press ctrl-C when you get bored"
 *       loop {}
 *     rescue Interrupt => e
 *       puts "Note: You will typically use Signal.trap instead."
 *     end
 *
 *  <em>produces:</em>
 *
 *     Press ctrl-C when you get bored
 *
 *  <em>then waits until it is interrupted with Control-C and then prints:</em>
 *
 *     Note: You will typically use Signal.trap instead.
 */

/*
 *  Document-class: TypeError
 *
 *  Raised when encountering an object that is not of the expected type.
 *
 *     [1, 2, 3].first("two")
 *
 *  <em>raises the exception:</em>
 *
 *     TypeError: can't convert String into Integer
 *
 */

/*
 *  Document-class: ArgumentError
 *
 *  Raised when the arguments are wrong and there isn't a more specific
 *  Exception class.
 *
 *  Ex: passing the wrong number of arguments
 *
 *     [1, 2, 3].first(4, 5)
 *
 *  <em>raises the exception:</em>
 *
 *     ArgumentError: wrong number of arguments (2 for 1)
 *
 *  Ex: passing an argument that is not acceptable:
 *
 *     [1, 2, 3].first(-4)
 *
 *  <em>raises the exception:</em>
 *
 *     ArgumentError: negative array size
 */

/*
 *  Document-class: IndexError
 *
 *  Raised when the given index is invalid.
 *
 *     a = [:foo, :bar]
 *     a.fetch(0)   #=> :foo
 *     a[4]         #=> nil
 *     a.fetch(4)   #=> IndexError: index 4 outside of array bounds: -2...2
 *
 */

/*
 *  Document-class: KeyError
 *
 *  Raised when the specified key is not found. It is a subclass of
 *  IndexError.
 *
 *     h = {"foo" => :bar}
 *     h.fetch("foo") #=> :bar
 *     h.fetch("baz") #=> KeyError: key not found: "baz"
 *
 */

/*
 *  Document-class: RangeError
 *
 *  Raised when a given numerical value is out of range.
 *
 *     [1, 2, 3].drop(1 << 100)
 *
 *  <em>raises the exception:</em>
 *
 *     RangeError: bignum too big to convert into `long'
 */

/*
 *  Document-class: ScriptError
 *
 *  ScriptError is the superclass for errors raised when a script
 *  can not be executed because of a +LoadError+,
 *  +NotImplementedError+ or a +SyntaxError+. Note these type of
 *  +ScriptErrors+ are not +StandardError+ and will not be
 *  rescued unless it is specified explicitly (or its ancestor
 *  +Exception+).
 */

/*
 *  Document-class: SyntaxError
 *
 *  Raised when encountering Ruby code with an invalid syntax.
 *
 *     eval("1+1=2")
 *
 *  <em>raises the exception:</em>
 *
 *     SyntaxError: (eval):1: syntax error, unexpected '=', expecting $end
 */

/*
 *  Document-class: LoadError
 *
 *  Raised when a file required (a Ruby script, extension library, ...)
 *  fails to load.
 *
 *     require 'this/file/does/not/exist'
 *
 *  <em>raises the exception:</em>
 *
 *     LoadError: no such file to load -- this/file/does/not/exist
 */

/*
 *  Document-class: NotImplementedError
 *
 *  Raised when a feature is not implemented on the current platform. For
 *  example, methods depending on the +fsync+ or +fork+ system calls may
 *  raise this exception if the underlying operating system or Ruby
 *  runtime does not support them.
 *
 *  Note that if +fork+ raises a +NotImplementedError+, then
 *  <code>respond_to?(:fork)</code> returns +false+.
 */

/*
 *  Document-class: NameError
 *
 *  Raised when a given name is invalid or undefined.
 *
 *     puts foo
 *
 *  <em>raises the exception:</em>
 *
 *     NameError: undefined local variable or method `foo' for main:Object
 *
 *  Since constant names must start with a capital:
 *
 *     Fixnum.const_set :answer, 42
 *
 *  <em>raises the exception:</em>
 *
 *     NameError: wrong constant name answer
 */

/*
 *  Document-class: NoMethodError
 *
 *  Raised when a method is called on a receiver which doesn't have it
 *  defined and also fails to respond with +method_missing+.
 *
 *     "hello".to_ary
 *
 *  <em>raises the exception:</em>
 *
 *     NoMethodError: undefined method `to_ary' for "hello":String
 */

/*
 *  Document-class: RuntimeError
 *
 *  A generic error class raised when an invalid operation is attempted.
 *
 *     [1, 2, 3].freeze << 4
 *
 *  <em>raises the exception:</em>
 *
 *     RuntimeError: can't modify frozen array
 *
 *  Kernel.raise will raise a RuntimeError if no Exception class is
 *  specified.
 *
 *     raise "ouch"
 *
 *  <em>raises the exception:</em>
 *
 *     RuntimeError: ouch
 */

/*
 *  Document-class: SecurityError
 *
 *  Raised when attempting a potential unsafe operation, typically when
 *  the $SAFE level is raised above 0.
 *
 *     foo = "bar"
 *     proc = Proc.new do
 *       $SAFE = 4
 *       foo.gsub! "a", "*"
 *     end
 *     proc.call
 *
 *  <em>raises the exception:</em>
 *
 *     SecurityError: Insecure: can't modify string
 */

/*
 *  Document-class: NoMemoryError
 *
 *  Raised when memory allocation fails.
 */

/*
 *  Document-class: SystemCallError
 *
 *  SystemCallError is the base class for all low-level
 *  platform-dependent errors.
 *
 *  The errors available on the current platform are subclasses of
 *  SystemCallError and are defined in the Errno module.
 *
 *     File.open("does/not/exist")
 *
 *  <em>raises the exception:</em>
 *
 *     Errno::ENOENT: No such file or directory - does/not/exist
 */

/*
 *  Document-class: Encoding::CompatibilityError
 *
 *  Raised by Encoding and String methods when the source encoding is
 *  incompatible with the target encoding.
 */

/*
 *  Descendants of class <code>Exception</code> are used to communicate
 *  between <code>raise</code> methods and <code>rescue</code>
 *  statements in <code>begin/end</code> blocks. <code>Exception</code>
 *  objects carry information about the exception---its type (the
 *  exception's class name), an optional descriptive string, and
 *  optional traceback information. Programs may subclass
 *  <code>Exception</code>, or more typically <code>StandardError</code>
 *  to provide custom classes and add additional information.
 */

void
Init_Exception(void)
{
    rb_eException   = rb_define_class("Exception", rb_cObject);
    rb_define_singleton_method(rb_eException, "exception", rb_class_new_instance, -1);
    rb_define_method(rb_eException, "exception", exc_exception, -1);
    rb_define_method(rb_eException, "initialize", exc_initialize, -1);
    rb_define_method(rb_eException, "==", exc_equal, 1);
    rb_define_method(rb_eException, "to_s", exc_to_s, 0);
    rb_define_method(rb_eException, "message", exc_message, 0);
    rb_define_method(rb_eException, "inspect", exc_inspect, 0);
    rb_define_method(rb_eException, "backtrace", exc_backtrace, 0);
    rb_define_method(rb_eException, "set_backtrace", exc_set_backtrace, 1);

    rb_eSystemExit  = rb_define_class("SystemExit", rb_eException);
    rb_define_method(rb_eSystemExit, "initialize", exit_initialize, -1);
    rb_define_method(rb_eSystemExit, "status", exit_status, 0);
    rb_define_method(rb_eSystemExit, "success?", exit_success_p, 0);

    rb_eFatal  	    = rb_define_class("fatal", rb_eException);
    rb_eSignal      = rb_define_class("SignalException", rb_eException);
    rb_eInterrupt   = rb_define_class("Interrupt", rb_eSignal);

    rb_eStandardError = rb_define_class("StandardError", rb_eException);
    rb_eTypeError     = rb_define_class("TypeError", rb_eStandardError);
    rb_eArgError      = rb_define_class("ArgumentError", rb_eStandardError);
    rb_eIndexError    = rb_define_class("IndexError", rb_eStandardError);
    rb_eKeyError      = rb_define_class("KeyError", rb_eIndexError);
    rb_eRangeError    = rb_define_class("RangeError", rb_eStandardError);

    rb_eScriptError = rb_define_class("ScriptError", rb_eException);
    rb_eSyntaxError = rb_define_class("SyntaxError", rb_eScriptError);
    rb_eLoadError   = rb_define_class("LoadError", rb_eScriptError);
    rb_eNotImpError = rb_define_class("NotImplementedError", rb_eScriptError);

    rb_eNameError     = rb_define_class("NameError", rb_eStandardError);
    rb_define_method(rb_eNameError, "initialize", name_err_initialize, -1);
    rb_define_method(rb_eNameError, "name", name_err_name, 0);
    rb_define_method(rb_eNameError, "to_s", name_err_to_s, 0);
    rb_cNameErrorMesg = rb_define_class_under(rb_eNameError, "message", rb_cData);
    rb_define_singleton_method(rb_cNameErrorMesg, "!", rb_name_err_mesg_new, NAME_ERR_MESG_COUNT);
    rb_define_method(rb_cNameErrorMesg, "==", name_err_mesg_equal, 1);
    rb_define_method(rb_cNameErrorMesg, "to_str", name_err_mesg_to_str, 0);
    rb_define_method(rb_cNameErrorMesg, "_dump", name_err_mesg_to_str, 1);
    rb_define_singleton_method(rb_cNameErrorMesg, "_load", name_err_mesg_load, 1);
    rb_eNoMethodError = rb_define_class("NoMethodError", rb_eNameError);
    rb_define_method(rb_eNoMethodError, "initialize", nometh_err_initialize, -1);
    rb_define_method(rb_eNoMethodError, "args", nometh_err_args, 0);

    rb_eRuntimeError = rb_define_class("RuntimeError", rb_eStandardError);
    rb_eSecurityError = rb_define_class("SecurityError", rb_eException);
    rb_eNoMemError = rb_define_class("NoMemoryError", rb_eException);
    rb_eEncodingError = rb_define_class("EncodingError", rb_eStandardError);
    rb_eEncCompatError = rb_define_class_under(rb_cEncoding, "CompatibilityError", rb_eEncodingError);

    syserr_tbl = st_init_numtable();
    rb_eSystemCallError = rb_define_class("SystemCallError", rb_eStandardError);
    rb_define_method(rb_eSystemCallError, "initialize", syserr_initialize, -1);
    rb_define_method(rb_eSystemCallError, "errno", syserr_errno, 0);
    rb_define_singleton_method(rb_eSystemCallError, "===", syserr_eqq, 1);

    rb_mErrno = rb_define_module("Errno");

    rb_define_global_function("warn", rb_warn_m, 1);
}

void
rb_raise(VALUE exc, const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_vsprintf(fmt, args);
    va_end(args);
    rb_exc_raise(rb_exc_new3(exc, mesg));
}

void
rb_loaderror(const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_enc_vsprintf(rb_locale_encoding(), fmt, args);
    va_end(args);
    rb_exc_raise(rb_exc_new3(rb_eLoadError, mesg));
}

void
rb_notimplement(void)
{
    rb_raise(rb_eNotImpError,
	     "%s() function is unimplemented on this machine",
	     rb_id2name(rb_frame_this_func()));
}

void
rb_fatal(const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_vsprintf(fmt, args);
    va_end(args);

    rb_exc_fatal(rb_exc_new3(rb_eFatal, mesg));
}

static VALUE
make_errno_exc(const char *mesg)
{
    int n = errno;

    errno = 0;
    if (n == 0) {
	rb_bug("rb_sys_fail(%s) - errno == 0", mesg ? mesg : "");
    }
    return rb_syserr_new(n, mesg);
}

VALUE
rb_syserr_new(int n, const char *mesg)
{
    VALUE arg;
    arg = mesg ? rb_str_new2(mesg) : Qnil;
    return rb_class_new_instance(1, &arg, get_syserr(n));
}

void
rb_syserr_fail(int e, const char *mesg)
{
    rb_exc_raise(rb_syserr_new(e, mesg));
}

void
rb_sys_fail(const char *mesg)
{
    rb_exc_raise(make_errno_exc(mesg));
}

void
rb_mod_sys_fail(VALUE mod, const char *mesg)
{
    VALUE exc = make_errno_exc(mesg);
    rb_extend_object(exc, mod);
    rb_exc_raise(exc);
}

void
rb_mod_syserr_fail(VALUE mod, int e, const char *mesg)
{
    VALUE exc = rb_syserr_new(e, mesg);
    rb_extend_object(exc, mod);
    rb_exc_raise(exc);
}

void
rb_sys_warning(const char *fmt, ...)
{
    char buf[BUFSIZ];
    va_list args;
    int errno_save;

    errno_save = errno;

    if (!RTEST(ruby_verbose)) return;

    snprintf(buf, BUFSIZ, "warning: %s", fmt);
    snprintf(buf+strlen(buf), BUFSIZ-strlen(buf), ": %s", strerror(errno_save));

    va_start(args, fmt);
    warn_print(buf, args);
    va_end(args);
    errno = errno_save;
}

void
rb_load_fail(const char *path)
{
    rb_loaderror("%s -- %s", strerror(errno), path);
}

void
rb_error_frozen(const char *what)
{
    rb_raise(rb_eRuntimeError, "can't modify frozen %s", what);
}

#undef rb_check_frozen
void
rb_check_frozen(VALUE obj)
{
    rb_check_frozen_internal(obj);
}

void
Init_syserr(void)
{
    rb_eNOERROR = set_syserr(0, "NOERROR");
#define defined_error(name, num) set_syserr((num), (name));
#define undefined_error(name) set_syserr(0, (name));
#include "known_errors.inc"
#undef defined_error
#undef undefined_error
}

static void
err_append(const char *s)
{
    rb_thread_t *th = GET_THREAD();
    VALUE err = th->errinfo;

    if (th->mild_compile_error) {
	if (!RTEST(err)) {
	    err = rb_exc_new2(rb_eSyntaxError, s);
	    th->errinfo = err;
	}
	else {
	    VALUE str = rb_obj_as_string(err);

	    rb_str_cat2(str, "\n");
	    rb_str_cat2(str, s);
	    th->errinfo = rb_exc_new3(rb_eSyntaxError, str);
	}
    }
    else {
	if (!RTEST(err)) {
	    err = rb_exc_new2(rb_eSyntaxError, "compile error");
	    th->errinfo = err;
	}
	rb_write_error(s);
	rb_write_error("\n");
    }
}
