/* -*-c-*- */
/*
 * included by eval.c
 */

static void
warn_printf(const char *fmt, ...)
{
    VALUE str;
    va_list args;

    va_init_list(args, fmt);
    str = rb_vsprintf(fmt, args);
    va_end(args);
    rb_write_error_str(str);
}

#define warn_print(x) rb_write_error(x)
#define warn_print2(x,l) rb_write_error2((x),(l))
#define warn_print_str(x) rb_write_error_str(x)

static void
error_pos(void)
{
    VALUE sourcefile = rb_sourcefilename();
    int sourceline = rb_sourceline();

    if (sourcefile) {
	ID caller_name;
	if (sourceline == 0) {
	    warn_printf("%"PRIsVALUE, sourcefile);
	}
	else if ((caller_name = rb_frame_callee()) != 0) {
	    warn_printf("%"PRIsVALUE":%d:in `%"PRIsVALUE"'", sourcefile, sourceline,
			rb_id2str(caller_name));
	}
	else {
	    warn_printf("%"PRIsVALUE":%d", sourcefile, sourceline);
	}
    }
}

VALUE rb_exc_set_backtrace(VALUE exc, VALUE bt);

static void
set_backtrace(VALUE info, VALUE bt)
{
    ID set_backtrace = rb_intern("set_backtrace");

    if (rb_backtrace_p(bt)) {
	if (rb_method_basic_definition_p(CLASS_OF(info), set_backtrace)) {
	    rb_exc_set_backtrace(info, bt);
	    return;
	}
	else {
	    bt = rb_backtrace_to_str_ary(bt);
	}
    }
    rb_check_funcall(info, set_backtrace, 1, &bt);
}

static void
error_print(void)
{
    volatile VALUE errat = Qundef;
    rb_thread_t *th = GET_THREAD();
    VALUE errinfo = th->errinfo;
    volatile int raised_flag = th->raised_flag;
    volatile VALUE eclass = Qundef, e = Qundef;
    const char *volatile einfo;
    volatile long elen;

    if (NIL_P(errinfo))
	return;
    rb_thread_raised_clear(th);

    TH_PUSH_TAG(th);
    if (TH_EXEC_TAG() == 0) {
	errat = rb_get_backtrace(errinfo);
    }
    else if (errat == Qundef) {
	errat = Qnil;
    }
    else if (eclass == Qundef || e != Qundef) {
	goto error;
    }
    else {
	goto no_message;
    }
    if (NIL_P(errat)) {
	const char *file = rb_sourcefile();
	int line = rb_sourceline();
	if (!file)
	    warn_printf("%d", line);
	else if (!line)
	    warn_printf("%s", file);
	else
	    warn_printf("%s:%d", file, line);
    }
    else if (RARRAY_LEN(errat) == 0) {
	error_pos();
    }
    else {
	VALUE mesg = RARRAY_AREF(errat, 0);

	if (NIL_P(mesg))
	    error_pos();
	else {
	    warn_print_str(mesg);
	}
    }

    eclass = CLASS_OF(errinfo);
    if (eclass != Qundef &&
	(e = rb_check_funcall(errinfo, rb_intern("message"), 0, 0)) != Qundef &&
	(RB_TYPE_P(e, T_STRING) || !NIL_P(e = rb_check_string_type(e)))) {
	einfo = RSTRING_PTR(e);
	elen = RSTRING_LEN(e);
    }
    else {
      no_message:
	einfo = "";
	elen = 0;
    }
    if (eclass == rb_eRuntimeError && elen == 0) {
	warn_print(": unhandled exception\n");
    }
    else {
	VALUE epath;

	epath = rb_class_name(eclass);
	if (elen == 0) {
	    warn_print(": ");
	    warn_print_str(epath);
	    warn_print("\n");
	}
	else {
	    char *tail = 0;
	    long len = elen;

	    if (RSTRING_PTR(epath)[0] == '#')
		epath = 0;
	    if ((tail = memchr(einfo, '\n', elen)) != 0) {
		len = tail - einfo;
		tail++;		/* skip newline */
	    }
	    warn_print(": ");
	    warn_print_str(tail ? rb_str_subseq(e, 0, len) : e);
	    if (epath) {
		warn_print(" (");
		warn_print_str(epath);
		warn_print(")\n");
	    }
	    if (tail) {
		warn_print_str(rb_str_subseq(e, tail - einfo, elen - len - 1));
	    }
	    if (tail ? einfo[elen-1] != '\n' : !epath) warn_print2("\n", 1);
	}
    }

    if (!NIL_P(errat)) {
	long i;
	long len = RARRAY_LEN(errat);
        int skip = eclass == rb_eSysStackError;

#define TRACE_MAX (TRACE_HEAD+TRACE_TAIL+5)
#define TRACE_HEAD 8
#define TRACE_TAIL 5

	for (i = 1; i < len; i++) {
	    VALUE line = RARRAY_AREF(errat, i);
	    if (RB_TYPE_P(line, T_STRING)) {
		warn_printf("\tfrom %"PRIsVALUE"\n", line);
	    }
	    if (skip && i == TRACE_HEAD && len > TRACE_MAX) {
		warn_printf("\t ... %ld levels...\n",
			    len - TRACE_HEAD - TRACE_TAIL);
		i = len - TRACE_TAIL;
	    }
	}
    }
  error:
    TH_POP_TAG();
    th->errinfo = errinfo;
    rb_thread_raised_set(th, raised_flag);
}

void
ruby_error_print(void)
{
    error_print();
}

static const char *
method_scope_name(int scope)
{
    const char *v;

    switch (scope) {
      default:
      case NOEX_PUBLIC: v = ""; break;
      case NOEX_PRIVATE: v = " private"; break;
      case NOEX_PROTECTED: v = " protected"; break;
    }
    return v;
}

void
rb_print_undef(VALUE klass, ID id, int scope)
{
    const char *v = method_scope_name(scope);
    rb_name_error(id, "undefined%s method `%"PRIsVALUE"' for %s `% "PRIsVALUE"'", v,
		  QUOTE_ID(id),
		  (RB_TYPE_P(klass, T_MODULE)) ? "module" : "class",
		  rb_class_name(klass));
}

void
rb_print_undef_str(VALUE klass, VALUE name)
{
    rb_name_error_str(name, "undefined method `%"PRIsVALUE"' for %s `% "PRIsVALUE"'",
		      QUOTE(name),
		      (RB_TYPE_P(klass, T_MODULE)) ? "module" : "class",
		      rb_class_name(klass));
}

void
rb_print_inaccessible(VALUE klass, ID id, int scope)
{
    const char *v = method_scope_name(scope);
    rb_name_error(id, "method `%"PRIsVALUE"' for %s `% "PRIsVALUE"' is %s",
		  QUOTE_ID(id),
		  (RB_TYPE_P(klass, T_MODULE)) ? "module" : "class",
		  rb_class_name(klass),
		  v);
}

static int
sysexit_status(VALUE err)
{
    VALUE st = rb_iv_get(err, "status");
    return NUM2INT(st);
}

static int
error_handle(int ex)
{
    int status = EXIT_FAILURE;
    rb_thread_t *th = GET_THREAD();

    if (rb_threadptr_set_raised(th))
	return EXIT_FAILURE;
    switch (ex & TAG_MASK) {
      case 0:
	status = EXIT_SUCCESS;
	break;

      case TAG_RETURN:
	error_pos();
	warn_print(": unexpected return\n");
	break;
      case TAG_NEXT:
	error_pos();
	warn_print(": unexpected next\n");
	break;
      case TAG_BREAK:
	error_pos();
	warn_print(": unexpected break\n");
	break;
      case TAG_REDO:
	error_pos();
	warn_print(": unexpected redo\n");
	break;
      case TAG_RETRY:
	error_pos();
	warn_print(": retry outside of rescue clause\n");
	break;
      case TAG_THROW:
	/* TODO: fix me */
	error_pos();
	warn_printf(": unexpected throw\n");
	break;
      case TAG_RAISE: {
	VALUE errinfo = GET_THREAD()->errinfo;
	if (rb_obj_is_kind_of(errinfo, rb_eSystemExit)) {
	    status = sysexit_status(errinfo);
	}
	else if (rb_obj_is_instance_of(errinfo, rb_eSignal) &&
		 rb_iv_get(errinfo, "signo") != INT2FIX(SIGSEGV)) {
	    /* no message when exiting by signal */
	}
	else {
	    error_print();
	}
	break;
      }
      case TAG_FATAL:
	error_print();
	break;
      default:
	rb_bug("Unknown longjmp status %d", ex);
	break;
    }
    rb_threadptr_reset_raised(th);
    return status;
}
