/* -*-c-*- */
/*
 * included by eval.c
 */

#ifdef HAVE_BUILTIN___BUILTIN_CONSTANT_P
#define write_warn(str, x) RB_GNUC_EXTENSION_BLOCK( \
        NIL_P(str) ? \
            warn_print(x) : (void)( \
            (__builtin_constant_p(x)) ? 		\
                rb_str_concat((str), rb_str_new((x), (long)strlen(x))) : \
                rb_str_concat((str), rb_str_new2(x)) \
            ) \
        )
#define warn_print(x) RB_GNUC_EXTENSION_BLOCK(	\
    (__builtin_constant_p(x)) ? 		\
	rb_write_error2((x), (long)strlen(x)) : \
	rb_write_error(x)			\
)
#else
#define write_warn(str, x) NIL_P(str) ? rb_write_error((x)) : (void)rb_str_concat((str), rb_str_new2(x))
#define warn_print(x) rb_write_error(x)
#endif

#define write_warn2(str,x,l) NIL_P(str) ? warn_print2(x,l) : (void)rb_str_concat((str), rb_str_new((x),(l)))
#define warn_print2(x,l) rb_write_error2((x),(l))

#define write_warn_str(str,x) NIL_P(str) ? rb_write_error_str(x) : (void)rb_str_concat((str), (x))
#define warn_print_str(x) rb_write_error_str(x)

static VALUE error_pos_str(void);

static void
error_pos(const VALUE str)
{
    VALUE pos = error_pos_str();
    if (!NIL_P(pos)) {
	write_warn_str(str, pos);
    }
}

static VALUE
error_pos_str(void)
{
    int sourceline;
    VALUE sourcefile = rb_source_location(&sourceline);

    if (!NIL_P(sourcefile)) {
	ID caller_name;
	if (sourceline == 0) {
	    return rb_sprintf("%"PRIsVALUE": ", sourcefile);
	}
	else if ((caller_name = rb_frame_callee()) != 0) {
	    return rb_sprintf("%"PRIsVALUE":%d:in `%"PRIsVALUE"': ",
			      sourcefile, sourceline,
			      rb_id2str(caller_name));
	}
	else {
	    return rb_sprintf("%"PRIsVALUE":%d: ", sourcefile, sourceline);
	}
    }
    return Qnil;
}

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
error_print(rb_execution_context_t *ec)
{
    rb_ec_error_print(ec, ec->errinfo);
}

#define CSI_BEGIN "\033["
#define CSI_SGR "m"

static const char underline[] = CSI_BEGIN"1;4"CSI_SGR;
static const char bold[] = CSI_BEGIN"1"CSI_SGR;
static const char reset[] = CSI_BEGIN""CSI_SGR;

static void
print_errinfo(const VALUE eclass, const VALUE errat, const VALUE emesg, const VALUE str, int colored)
{
    const char *einfo = "";
    long elen = 0;
    VALUE mesg;

    if (emesg != Qundef) {
	if (NIL_P(errat) || RARRAY_LEN(errat) == 0 ||
	    NIL_P(mesg = RARRAY_AREF(errat, 0))) {
	    error_pos(str);
	}
	else {
	    write_warn_str(str, mesg);
	    write_warn(str, ": ");
	}

        if (colored) write_warn(str, bold);

	if (!NIL_P(emesg)) {
	    einfo = RSTRING_PTR(emesg);
            elen = RSTRING_LEN(emesg);
	}
    }

    if (eclass == rb_eRuntimeError && elen == 0) {
        if (colored) write_warn(str, underline);
	write_warn(str, "unhandled exception\n");
    }
    else {
	VALUE epath;

	epath = rb_class_name(eclass);
	if (elen == 0) {
            if (colored) write_warn(str, underline);
	    write_warn_str(str, epath);
	    write_warn(str, "\n");
	}
	else {
	    const char *tail = 0;
	    long len = elen;

	    if (RSTRING_PTR(epath)[0] == '#')
		epath = 0;
	    if ((tail = memchr(einfo, '\n', elen)) != 0) {
		len = tail - einfo;
		tail++;		/* skip newline */
	    }
	    write_warn_str(str, tail ? rb_str_subseq(emesg, 0, len) : emesg);
	    if (epath) {
		write_warn(str, " (");
                if (colored) write_warn(str, underline);
                write_warn_str(str, epath);
                if (colored) write_warn(str, reset);
                if (colored) write_warn(str, bold);
		write_warn(str, ")\n");
	    }
	    if (tail) {
		write_warn_str(str, rb_str_subseq(emesg, tail - einfo, elen - len - 1));
	    }
	    if (tail ? einfo[elen-1] != '\n' : !epath) write_warn2(str, "\n", 1);
	}
    }
    if (colored) write_warn(str, reset);
}

static void
print_backtrace(const VALUE eclass, const VALUE errat, const VALUE str, int reverse)
{
    if (!NIL_P(errat)) {
	long i;
	long len = RARRAY_LEN(errat);
        int skip = eclass == rb_eSysStackError;
	const int threshold = 1000000000;
	int width = ((int)log10((double)(len > threshold ?
					 ((len - 1) / threshold) :
					 len - 1)) +
		     (len < threshold ? 0 : 9) + 1);

#define TRACE_MAX (TRACE_HEAD+TRACE_TAIL+5)
#define TRACE_HEAD 8
#define TRACE_TAIL 5

	for (i = 1; i < len; i++) {
	    VALUE line = RARRAY_AREF(errat, reverse ? len - i : i);
	    if (RB_TYPE_P(line, T_STRING)) {
		VALUE bt = rb_str_new_cstr("\t");
		if (reverse) rb_str_catf(bt, "%*ld: ", width, len - i);
		write_warn_str(str, rb_str_catf(bt, "from %"PRIsVALUE"\n", line));
	    }
	    if (skip && i == TRACE_HEAD && len > TRACE_MAX) {
		write_warn_str(str, rb_sprintf("\t ... %ld levels...\n",
					  len - TRACE_HEAD - TRACE_TAIL));
		i = len - TRACE_TAIL;
	    }
	}
    }
}

void
rb_error_write(VALUE errinfo, VALUE emesg, VALUE errat, VALUE str, VALUE highlight, VALUE reverse)
{
    volatile VALUE eclass;

    if (NIL_P(errinfo))
	return;

    if (errat == Qundef) {
	errat = Qnil;
    }
    eclass = CLASS_OF(errinfo);
    if (NIL_P(reverse) || NIL_P(highlight)) {
	VALUE tty = (VALUE)rb_stderr_tty_p();
	if (NIL_P(reverse)) reverse = tty;
	if (NIL_P(highlight)) highlight = tty;
    }
    if (reverse) {
	static const char traceback[] = "Traceback "
	    "(most recent call last):\n";
	const int bold_part = rb_strlen_lit("Traceback");
	char buff[sizeof(traceback)+sizeof(bold)+sizeof(reset)-2], *p = buff;
	const char *msg = traceback;
	long len = sizeof(traceback) - 1;
	if (highlight) {
#define APPEND(s, l) (memcpy(p, s, l), p += (l))
	    APPEND(bold, sizeof(bold)-1);
	    APPEND(traceback, bold_part);
	    APPEND(reset, sizeof(reset)-1);
	    APPEND(traceback + bold_part, sizeof(traceback)-bold_part-1);
#undef APPEND
	    len = p - (msg = buff);
	}
	write_warn2(str, msg, len);
	print_backtrace(eclass, errat, str, TRUE);
	print_errinfo(eclass, errat, emesg, str, highlight!=0);
    }
    else {
	print_errinfo(eclass, errat, emesg, str, highlight!=0);
	print_backtrace(eclass, errat, str, FALSE);
    }
}

VALUE rb_get_message(VALUE exc);

void
rb_ec_error_print(rb_execution_context_t * volatile ec, volatile VALUE errinfo)
{
    volatile int raised_flag = ec->raised_flag;
    volatile VALUE errat = Qundef;
    volatile VALUE emesg = Qundef;

    if (NIL_P(errinfo))
	return;
    rb_ec_raised_clear(ec);

    EC_PUSH_TAG(ec);
    if (EC_EXEC_TAG() == TAG_NONE) {
	errat = rb_get_backtrace(errinfo);
    }
    if (emesg == Qundef) {
	emesg = Qnil;
	emesg = rb_get_message(errinfo);
    }

    rb_error_write(errinfo, emesg, errat, Qnil, Qnil, Qnil);

    EC_POP_TAG();
    ec->errinfo = errinfo;
    rb_ec_raised_set(ec, raised_flag);
}

#define undef_mesg_for(v, k) rb_fstring_cstr("undefined"v" method `%1$s' for "k" `%2$s'")
#define undef_mesg(v) ( \
	is_mod ? \
	undef_mesg_for(v, "module") : \
	undef_mesg_for(v, "class"))

void
rb_print_undef(VALUE klass, ID id, rb_method_visibility_t visi)
{
    const int is_mod = RB_TYPE_P(klass, T_MODULE);
    VALUE mesg;
    switch (visi & METHOD_VISI_MASK) {
      case METHOD_VISI_UNDEF:
      case METHOD_VISI_PUBLIC:    mesg = undef_mesg(""); break;
      case METHOD_VISI_PRIVATE:   mesg = undef_mesg(" private"); break;
      case METHOD_VISI_PROTECTED: mesg = undef_mesg(" protected"); break;
      default: UNREACHABLE;
    }
    rb_name_err_raise_str(mesg, klass, ID2SYM(id));
}

void
rb_print_undef_str(VALUE klass, VALUE name)
{
    const int is_mod = RB_TYPE_P(klass, T_MODULE);
    rb_name_err_raise_str(undef_mesg(""), klass, name);
}

#define inaccessible_mesg_for(v, k) rb_fstring_cstr("method `%1$s' for "k" `%2$s' is "v)
#define inaccessible_mesg(v) ( \
	is_mod ? \
	inaccessible_mesg_for(v, "module") : \
	inaccessible_mesg_for(v, "class"))

void
rb_print_inaccessible(VALUE klass, ID id, rb_method_visibility_t visi)
{
    const int is_mod = RB_TYPE_P(klass, T_MODULE);
    VALUE mesg;
    switch (visi & METHOD_VISI_MASK) {
      case METHOD_VISI_UNDEF:
      case METHOD_VISI_PUBLIC:    mesg = inaccessible_mesg(""); break;
      case METHOD_VISI_PRIVATE:   mesg = inaccessible_mesg(" private"); break;
      case METHOD_VISI_PROTECTED: mesg = inaccessible_mesg(" protected"); break;
      default: UNREACHABLE;
    }
    rb_name_err_raise_str(mesg, klass, ID2SYM(id));
}

static int
sysexit_status(VALUE err)
{
    VALUE st = rb_ivar_get(err, id_status);
    return NUM2INT(st);
}

#define unknown_longjmp_status(status) \
    rb_bug("Unknown longjmp status %d", status)

static int
error_handle(int ex)
{
    int status = EXIT_FAILURE;
    rb_execution_context_t *ec = GET_EC();

    if (rb_ec_set_raised(ec))
	return EXIT_FAILURE;
    switch (ex & TAG_MASK) {
      case 0:
	status = EXIT_SUCCESS;
	break;

      case TAG_RETURN:
	error_pos(Qnil);
	warn_print("unexpected return\n");
	break;
      case TAG_NEXT:
	error_pos(Qnil);
	warn_print("unexpected next\n");
	break;
      case TAG_BREAK:
	error_pos(Qnil);
	warn_print("unexpected break\n");
	break;
      case TAG_REDO:
	error_pos(Qnil);
	warn_print("unexpected redo\n");
	break;
      case TAG_RETRY:
	error_pos(Qnil);
	warn_print("retry outside of rescue clause\n");
	break;
      case TAG_THROW:
	/* TODO: fix me */
	error_pos(Qnil);
	warn_print("unexpected throw\n");
	break;
      case TAG_RAISE: {
	VALUE errinfo = ec->errinfo;
	if (rb_obj_is_kind_of(errinfo, rb_eSystemExit)) {
	    status = sysexit_status(errinfo);
	}
	else if (rb_obj_is_instance_of(errinfo, rb_eSignal) &&
		 rb_ivar_get(errinfo, id_signo) != INT2FIX(SIGSEGV)) {
	    /* no message when exiting by signal */
	}
	else {
	    rb_ec_error_print(ec, errinfo);
	}
	break;
      }
      case TAG_FATAL:
	error_print(ec);
	break;
      default:
	unknown_longjmp_status(ex);
	break;
    }
    rb_ec_reset_raised(ec);
    return status;
}
