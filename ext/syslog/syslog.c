/* 
 * UNIX Syslog extension for Ruby
 * Amos Gouaux, University of Texas at Dallas
 * <amos+ruby@utdallas.edu>
 *
 * $RoughId: syslog.c,v 1.17 2001/11/24 12:42:39 knu Exp $
 * $Id$
 */

#include "ruby.h"
#include <syslog.h>

/* Syslog class */
static VALUE cSyslog, mSyslogConstants;
static VALUE syslog_instance = Qnil, syslog_ident, syslog_options,
  syslog_facility, syslog_mask;
static int syslog_opened = 0;

/* Package helper routines */
static void syslog_write(int pri, int argc, VALUE *argv)
{
    VALUE str;

    if (argc < 1) {
        rb_raise(rb_eArgError, "no log message supplied");
    }

    if (!syslog_opened) {
        rb_raise(rb_eRuntimeError, "must open syslog before write");
    }

    str = rb_f_sprintf(argc, argv);

    syslog(pri, "%s", RSTRING(str)->ptr);
}

/* Syslog instance methods */
static VALUE cSyslog_close(VALUE self)
{
    closelog();
    syslog_opened = 0;

    return Qnil;
}

static VALUE cSyslog_open(int argc, VALUE *argv, VALUE self)
{
    VALUE ident, opt, fac;
    int mask;

    if (syslog_opened) {
        rb_raise(rb_eRuntimeError, "syslog already open");
    }
    rb_scan_args(argc, argv, "03", &ident, &opt, &fac);
    if (NIL_P(ident)) {
        ident = rb_gv_get("$0"); 
    }
    if (NIL_P(opt)) {
        opt = INT2NUM(LOG_PID | LOG_CONS);
    }
    if (NIL_P(fac)) {
        fac = INT2NUM(LOG_USER);
    }

    Check_SafeStr(ident);
    syslog_ident = ident;
    syslog_options = opt;
    syslog_facility = fac;
    openlog(RSTRING(ident)->ptr, NUM2INT(opt), NUM2INT(fac));
    syslog_opened = 1;

    setlogmask(mask = setlogmask(0));
    syslog_mask = INT2NUM(mask);

    /* be like File.new.open {...} */
    if (rb_block_given_p()) {
        rb_ensure(rb_yield, self, cSyslog_close, self);
    }

    return self;
}

static VALUE cSyslog_init(VALUE self)
{
    syslog_instance = self;
    syslog_opened = 0;
    syslog_ident = Qnil;
    syslog_options = syslog_facility = syslog_mask = INT2FIX(-1);

    return self;
}

static VALUE cSyslog_reopen(int argc, VALUE *argv, VALUE self)
{
    cSyslog_close(self);

    return cSyslog_open(argc, argv, self);
}

static VALUE cSyslog_isopen(VALUE self)
{
    return syslog_opened ? Qtrue : Qfalse;
}

static VALUE cSyslog_ident(VALUE self)
{
    return syslog_ident;
}

static VALUE cSyslog_options(VALUE self)
{
    return syslog_options;
}

static VALUE cSyslog_facility(VALUE self)
{
    return syslog_facility;
}

static VALUE cSyslog_get_mask(VALUE self)
{
    return syslog_mask;
}

static VALUE cSyslog_set_mask(VALUE self, VALUE mask)
{
    if (!syslog_opened) {
        rb_raise(rb_eRuntimeError, "must open syslog before setting log mask");
    }

    setlogmask(NUM2INT(mask));
    syslog_mask = mask;

    return mask;
}

static VALUE cSyslog_log(int argc, VALUE *argv, VALUE self)
{
    VALUE pri;

    if (argc < 2) {
        rb_raise(rb_eArgError, "wrong # of arguments(%d for 2+)", argc);
    }

    argc--;
    pri = *argv++;

    if (!FIXNUM_P(pri)) {
      rb_raise(rb_eTypeError, "type mismatch: %s given", rb_class2name(CLASS_OF(pri)));
    }

    syslog_write(FIX2INT(pri), argc, argv);

    return self;
}

static VALUE cSyslog_inspect(VALUE self)
{
#define N 7
    int argc = N;
    VALUE argv[N];
    const char fmt[] =
      "<#%s: opened=%s, ident=\"%s\", options=%d, facility=%d, mask=%d>";

    argv[0] = rb_str_new(fmt, sizeof(fmt) - 1);
    argv[1] = cSyslog;
    argv[2] = syslog_opened ? Qtrue : Qfalse;
    argv[3] = syslog_ident;
    argv[4] = syslog_options;
    argv[5] = syslog_facility;
    argv[6] = syslog_mask;

    return rb_f_sprintf(argc, argv);
#undef N
}

#define define_syslog_shortcut_method(pri, name) \
static VALUE cSyslog_##name(int argc, VALUE *argv, VALUE self) \
{ \
    syslog_write(pri, argc, argv); \
\
    return self; \
}

#ifdef LOG_EMERG
define_syslog_shortcut_method(LOG_EMERG, emerg)
#endif
#ifdef LOG_ALERT
define_syslog_shortcut_method(LOG_ALERT, alert)
#endif
#ifdef LOG_CRIT
define_syslog_shortcut_method(LOG_CRIT, crit)
#endif
#ifdef LOG_ERR
define_syslog_shortcut_method(LOG_ERR, err)
#endif
#ifdef LOG_WARNING
define_syslog_shortcut_method(LOG_WARNING, warning)
#endif
#ifdef LOG_NOTICE
define_syslog_shortcut_method(LOG_NOTICE, notice)
#endif
#ifdef LOG_INFO
define_syslog_shortcut_method(LOG_INFO, info)
#endif
#ifdef LOG_DEBUG
define_syslog_shortcut_method(LOG_DEBUG, debug)
#endif

/* Syslog class methods */
static VALUE cSyslog_s_instance(VALUE klass)
{
    VALUE obj;

    obj = syslog_instance;

    if (NIL_P(obj)) {
	obj = rb_obj_alloc(klass);
	rb_obj_call_init(obj, 0, NULL);
    }

    return obj;
}

static VALUE cSyslog_s_open(int argc, VALUE *argv, VALUE klass)
{
    VALUE obj;

    obj = cSyslog_s_instance(klass);

    cSyslog_open(argc, argv, obj);

    return obj;
}

static VALUE cSyslog_s_LOG_MASK(VALUE klass, VALUE pri)
{
    return INT2FIX(LOG_MASK(FIX2INT(pri)));
}

static VALUE cSyslog_s_LOG_UPTO(VALUE klass, VALUE pri)
{
    return INT2FIX(LOG_UPTO(FIX2INT(pri)));
}

/* Init for package syslog */
void Init_syslog()
{
    cSyslog = rb_define_class("Syslog", rb_cObject);
 
    mSyslogConstants = rb_define_module_under(cSyslog, "Constants");

    rb_include_module(cSyslog, mSyslogConstants);

    rb_define_module_function(cSyslog, "open", cSyslog_s_open, -1);
    rb_define_module_function(cSyslog, "instance", cSyslog_s_instance, 0);
    rb_define_module_function(cSyslog, "LOG_MASK", cSyslog_s_LOG_MASK, 1);
    rb_define_module_function(cSyslog, "LOG_UPTO", cSyslog_s_LOG_UPTO, 1);

    rb_undef_method(CLASS_OF(cSyslog), "new");

    rb_define_method(cSyslog, "initialize", cSyslog_init, 0);
    rb_define_method(cSyslog, "open", cSyslog_open, -1);
    rb_define_method(cSyslog, "reopen", cSyslog_reopen, -1);
    rb_define_method(cSyslog, "open!", cSyslog_reopen, -1);
    rb_define_method(cSyslog, "opened?", cSyslog_isopen, 0);

    rb_define_method(cSyslog, "ident", cSyslog_ident, 0);
    rb_define_method(cSyslog, "options", cSyslog_options, 0);
    rb_define_method(cSyslog, "facility", cSyslog_facility, 0);

    rb_define_method(cSyslog, "log", cSyslog_log, -1);
    rb_define_method(cSyslog, "close", cSyslog_close, 0);
    rb_define_method(cSyslog, "mask", cSyslog_get_mask, 0);
    rb_define_method(cSyslog, "mask=", cSyslog_set_mask, 1);

    rb_define_method(cSyslog, "inspect", cSyslog_inspect, 0);

#define rb_define_syslog_const(id) \
    rb_define_const(mSyslogConstants, #id, INT2NUM(id))

    /* Various options when opening log */
#ifdef LOG_PID
    rb_define_syslog_const(LOG_PID);
#endif
#ifdef LOG_CONS
    rb_define_syslog_const(LOG_CONS);
#endif
#ifdef LOG_ODELAY
    rb_define_syslog_const(LOG_ODELAY); /* deprecated */
#endif
#ifdef LOG_NDELAY
    rb_define_syslog_const(LOG_NDELAY);
#endif
#ifdef LOG_NOWAIT
    rb_define_syslog_const(LOG_NOWAIT); /* deprecated */
#endif
#ifdef LOG_PERROR
    rb_define_syslog_const(LOG_PERROR);
#endif

    /* Various syslog facilities */
#ifdef LOG_AUTH
    rb_define_syslog_const(LOG_AUTH);
#endif
#ifdef LOG_AUTHPRIV
    rb_define_syslog_const(LOG_AUTHPRIV);
#endif
#ifdef LOG_CONSOLE
    rb_define_syslog_const(LOG_CONSOLE);
#endif
#ifdef LOG_CRON
    rb_define_syslog_const(LOG_CRON);
#endif
#ifdef LOG_DAEMON
    rb_define_syslog_const(LOG_DAEMON);
#endif
#ifdef LOG_FTP
    rb_define_syslog_const(LOG_FTP);
#endif
#ifdef LOG_KERN
    rb_define_syslog_const(LOG_KERN);
#endif
#ifdef LOG_LPR
    rb_define_syslog_const(LOG_LPR);
#endif
#ifdef LOG_MAIL
    rb_define_syslog_const(LOG_MAIL);
#endif
#ifdef LOG_NEWS
    rb_define_syslog_const(LOG_NEWS);
#endif
#ifdef LOG_NTP
   rb_define_syslog_const(LOG_NTP);
#endif
#ifdef LOG_SECURITY
    rb_define_syslog_const(LOG_SECURITY);
#endif
#ifdef LOG_SYSLOG
    rb_define_syslog_const(LOG_SYSLOG);
#endif
#ifdef LOG_USER
    rb_define_syslog_const(LOG_USER);
#endif
#ifdef LOG_UUCP
    rb_define_syslog_const(LOG_UUCP);
#endif
#ifdef LOG_LOCAL0
    rb_define_syslog_const(LOG_LOCAL0);
#endif
#ifdef LOG_LOCAL1
    rb_define_syslog_const(LOG_LOCAL1);
#endif
#ifdef LOG_LOCAL2
    rb_define_syslog_const(LOG_LOCAL2);
#endif
#ifdef LOG_LOCAL3
    rb_define_syslog_const(LOG_LOCAL3);
#endif
#ifdef LOG_LOCAL4
    rb_define_syslog_const(LOG_LOCAL4);
#endif
#ifdef LOG_LOCAL5
    rb_define_syslog_const(LOG_LOCAL5);
#endif
#ifdef LOG_LOCAL6
    rb_define_syslog_const(LOG_LOCAL6);
#endif
#ifdef LOG_LOCAL7
    rb_define_syslog_const(LOG_LOCAL7);
#endif

#define rb_define_syslog_shortcut(name) \
    rb_define_method(cSyslog, #name, cSyslog_##name, -1)

    /* Various syslog priorities and the shortcut methods */
#ifdef LOG_EMERG
    rb_define_syslog_const(LOG_EMERG);
    rb_define_syslog_shortcut(emerg);
#endif
#ifdef LOG_ALERT
    rb_define_syslog_const(LOG_ALERT);
    rb_define_syslog_shortcut(alert);
#endif
#ifdef LOG_CRIT
    rb_define_syslog_const(LOG_CRIT);
    rb_define_syslog_shortcut(crit);
#endif
#ifdef LOG_ERR
    rb_define_syslog_const(LOG_ERR);
    rb_define_syslog_shortcut(err);
#endif
#ifdef LOG_WARNING
    rb_define_syslog_const(LOG_WARNING);
    rb_define_syslog_shortcut(warning);
#endif
#ifdef LOG_NOTICE
    rb_define_syslog_const(LOG_NOTICE);
    rb_define_syslog_shortcut(notice);
#endif
#ifdef LOG_INFO
    rb_define_syslog_const(LOG_INFO);
    rb_define_syslog_shortcut(info);
#endif
#ifdef LOG_DEBUG
    rb_define_syslog_const(LOG_DEBUG);
    rb_define_syslog_shortcut(debug);
#endif
}
