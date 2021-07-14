/**********************************************************************

  vm_args.c - process method call arguments.

  $Author$

  Copyright (C) 2014- Yukihiro Matsumoto

**********************************************************************/

NORETURN(static void raise_argument_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const VALUE exc));
NORETURN(static void argument_arity_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const int miss_argc, const int min_argc, const int max_argc));
NORETURN(static void argument_kw_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const char *error, const VALUE keys));
VALUE rb_keyword_error_new(const char *error, VALUE keys); /* class.c */
static VALUE method_missing(rb_execution_context_t *ec, VALUE obj, ID id, int argc, const VALUE *argv,
                            enum method_missing_reason call_status, int kw_splat);
#if !defined(_MSC_VER) || !defined(MJIT_HEADER)
MJIT_FUNC_EXPORTED
#endif
const rb_callable_method_entry_t *rb_resolve_refined_method_callable(VALUE refinements, const rb_callable_method_entry_t *me);

struct args_info {
    /* basic args info */
    VALUE *argv;
    int argc;

    /* additional args info */
    int rest_index;
    int rest_dupped;
    const struct rb_callinfo_kwarg *kw_arg;
    VALUE *kw_argv;
    VALUE rest;
};

enum arg_setup_type {
    arg_setup_method,
    arg_setup_block
};

static inline void
arg_rest_dup(struct args_info *args)
{
    if (!args->rest_dupped) {
        args->rest = rb_ary_dup(args->rest);
        args->rest_dupped = TRUE;
    }
}

static inline int
args_argc(struct args_info *args)
{
    if (args->rest == Qfalse) {
	return args->argc;
    }
    else {
	return args->argc + RARRAY_LENINT(args->rest) - args->rest_index;
    }
}

static inline void
args_extend(struct args_info *args, const int min_argc)
{
    int i;

    if (args->rest) {
        arg_rest_dup(args);
	VM_ASSERT(args->rest_index == 0);
	for (i=args->argc + RARRAY_LENINT(args->rest); i<min_argc; i++) {
	    rb_ary_push(args->rest, Qnil);
	}
    }
    else {
	for (i=args->argc; i<min_argc; i++) {
	    args->argv[args->argc++] = Qnil;
	}
    }
}

static inline void
args_reduce(struct args_info *args, int over_argc)
{
    if (args->rest) {
	const long len = RARRAY_LEN(args->rest);

	if (len > over_argc) {
	    arg_rest_dup(args);
	    rb_ary_resize(args->rest, len - over_argc);
	    return;
	}
	else {
	    args->rest = Qfalse;
	    over_argc -= len;
	}
    }

    VM_ASSERT(args->argc >= over_argc);
    args->argc -= over_argc;
}

static inline int
args_check_block_arg0(struct args_info *args)
{
    VALUE ary = Qnil;

    if (args->rest && RARRAY_LEN(args->rest) == 1) {
	VALUE arg0 = RARRAY_AREF(args->rest, 0);
	ary = rb_check_array_type(arg0);
    }
    else if (args->argc == 1) {
	VALUE arg0 = args->argv[0];
	ary = rb_check_array_type(arg0);
	args->argv[0] = arg0; /* see: https://bugs.ruby-lang.org/issues/8484 */
    }

    if (!NIL_P(ary)) {
	args->rest = ary;
	args->rest_index = 0;
	args->argc = 0;
	return TRUE;
    }

    return FALSE;
}

static inline void
args_copy(struct args_info *args)
{
    if (args->rest != Qfalse) {
	int argc = args->argc;
	args->argc = 0;
        arg_rest_dup(args);

	/*
	 * argv: [m0, m1, m2, m3]
	 * rest: [a0, a1, a2, a3, a4, a5]
	 *                ^
	 *                rest_index
	 *
	 * #=> first loop
	 *
	 * argv: [m0, m1]
	 * rest: [m2, m3, a2, a3, a4, a5]
	 *        ^
	 *        rest_index
	 *
	 * #=> 2nd loop
	 *
	 * argv: [] (argc == 0)
	 * rest: [m0, m1, m2, m3, a2, a3, a4, a5]
	 *        ^
	 *        rest_index
	 */
	while (args->rest_index > 0 && argc > 0) {
	    RARRAY_ASET(args->rest, --args->rest_index, args->argv[--argc]);
	}
	while (argc > 0) {
	    rb_ary_unshift(args->rest, args->argv[--argc]);
	}
    }
    else if (args->argc > 0) {
	args->rest = rb_ary_new_from_values(args->argc, args->argv);
	args->rest_index = 0;
        args->rest_dupped = TRUE;
	args->argc = 0;
    }
}

static inline const VALUE *
args_rest_argv(struct args_info *args)
{
    return RARRAY_CONST_PTR_TRANSIENT(args->rest) + args->rest_index;
}

static inline VALUE
args_rest_array(struct args_info *args)
{
    VALUE ary;

    if (args->rest) {
        ary = rb_ary_behead(args->rest, args->rest_index);
        args->rest_index = 0;
	args->rest = 0;
    }
    else {
	ary = rb_ary_new();
    }
    return ary;
}

static int
args_kw_argv_to_hash(struct args_info *args)
{
    const struct rb_callinfo_kwarg *kw_arg = args->kw_arg;
    const VALUE *const passed_keywords = kw_arg->keywords;
    const int kw_len = kw_arg->keyword_len;
    VALUE h = rb_hash_new_with_size(kw_len);
    const int kw_start = args->argc - kw_len;
    const VALUE * const kw_argv = args->argv + kw_start;
    int i;

    args->argc = kw_start + 1;
    for (i=0; i<kw_len; i++) {
	rb_hash_aset(h, passed_keywords[i], kw_argv[i]);
    }

    args->argv[args->argc - 1] = h;

    return args->argc;
}

static inline void
args_setup_lead_parameters(struct args_info *args, int argc, VALUE *locals)
{
    if (args->argc >= argc) {
	/* do noting */
	args->argc -= argc;
	args->argv += argc;
    }
    else {
	int i, j;
	const VALUE *argv = args_rest_argv(args);

	for (i=args->argc, j=0; i<argc; i++, j++) {
	    locals[i] = argv[j];
	}
	args->rest_index += argc - args->argc;
	args->argc = 0;
    }
}

static inline void
args_setup_post_parameters(struct args_info *args, int argc, VALUE *locals)
{
    long len;
    len = RARRAY_LEN(args->rest);
    MEMCPY(locals, RARRAY_CONST_PTR_TRANSIENT(args->rest) + len - argc, VALUE, argc);
    rb_ary_resize(args->rest, len - argc);
}

static inline int
args_setup_opt_parameters(struct args_info *args, int opt_max, VALUE *locals)
{
    int i;

    if (args->argc >= opt_max) {
	args->argc -= opt_max;
	args->argv += opt_max;
	i = opt_max;
    }
    else {
	int j;
	i = args->argc;
	args->argc = 0;

	if (args->rest) {
            int len = RARRAY_LENINT(args->rest);
            const VALUE *argv = RARRAY_CONST_PTR_TRANSIENT(args->rest);

            for (; i<opt_max && args->rest_index < len; i++, args->rest_index++) {
                locals[i] = argv[args->rest_index];
            }
        }

	/* initialize by nil */
	for (j=i; j<opt_max; j++) {
	    locals[j] = Qnil;
	}
    }

    return i;
}

static inline void
args_setup_rest_parameter(struct args_info *args, VALUE *locals)
{
    *locals = args_rest_array(args);
}

static VALUE
make_unknown_kw_hash(const VALUE *passed_keywords, int passed_keyword_len, const VALUE *kw_argv)
{
    int i;
    VALUE obj = rb_ary_tmp_new(1);

    for (i=0; i<passed_keyword_len; i++) {
	if (kw_argv[i] != Qundef) {
	    rb_ary_push(obj, passed_keywords[i]);
	}
    }
    return obj;
}

static VALUE
make_rest_kw_hash(const VALUE *passed_keywords, int passed_keyword_len, const VALUE *kw_argv)
{
    int i;
    VALUE obj = rb_hash_new_with_size(passed_keyword_len);

    for (i=0; i<passed_keyword_len; i++) {
	if (kw_argv[i] != Qundef) {
	    rb_hash_aset(obj, passed_keywords[i], kw_argv[i]);
	}
    }
    return obj;
}

static inline int
args_setup_kw_parameters_lookup(const ID key, VALUE *ptr, const VALUE *const passed_keywords, VALUE *passed_values, const int passed_keyword_len)
{
    int i;
    const VALUE keyname = ID2SYM(key);

    for (i=0; i<passed_keyword_len; i++) {
	if (keyname == passed_keywords[i]) {
	    *ptr = passed_values[i];
	    passed_values[i] = Qundef;
	    return TRUE;
	}
    }

    return FALSE;
}

#define KW_SPECIFIED_BITS_MAX (32-1) /* TODO: 32 -> Fixnum's max bits */

static void
args_setup_kw_parameters(rb_execution_context_t *const ec, const rb_iseq_t *const iseq,
			 VALUE *const passed_values, const int passed_keyword_len, const VALUE *const passed_keywords,
			 VALUE *const locals)
{
    const ID *acceptable_keywords = iseq->body->param.keyword->table;
    const int req_key_num = iseq->body->param.keyword->required_num;
    const int key_num = iseq->body->param.keyword->num;
    const VALUE * const default_values = iseq->body->param.keyword->default_values;
    VALUE missing = 0;
    int i, di, found = 0;
    int unspecified_bits = 0;
    VALUE unspecified_bits_value = Qnil;

    for (i=0; i<req_key_num; i++) {
	ID key = acceptable_keywords[i];
	if (args_setup_kw_parameters_lookup(key, &locals[i], passed_keywords, passed_values, passed_keyword_len)) {
	    found++;
	}
	else {
	    if (!missing) missing = rb_ary_tmp_new(1);
	    rb_ary_push(missing, ID2SYM(key));
	}
    }

    if (missing) argument_kw_error(ec, iseq, "missing", missing);

    for (di=0; i<key_num; i++, di++) {
	if (args_setup_kw_parameters_lookup(acceptable_keywords[i], &locals[i], passed_keywords, passed_values, passed_keyword_len)) {
	    found++;
	}
	else {
	    if (default_values[di] == Qundef) {
		locals[i] = Qnil;

		if (LIKELY(i < KW_SPECIFIED_BITS_MAX)) {
		    unspecified_bits |= 0x01 << di;
		}
		else {
		    if (NIL_P(unspecified_bits_value)) {
			/* fixnum -> hash */
			int j;
			unspecified_bits_value = rb_hash_new();

			for (j=0; j<KW_SPECIFIED_BITS_MAX; j++) {
			    if (unspecified_bits & (0x01 << j)) {
				rb_hash_aset(unspecified_bits_value, INT2FIX(j), Qtrue);
			    }
			}
		    }
		    rb_hash_aset(unspecified_bits_value, INT2FIX(di), Qtrue);
		}
	    }
	    else {
		locals[i] = default_values[di];
	    }
	}
    }

    if (iseq->body->param.flags.has_kwrest) {
	const int rest_hash_index = key_num + 1;
	locals[rest_hash_index] = make_rest_kw_hash(passed_keywords, passed_keyword_len, passed_values);
    }
    else {
	if (found != passed_keyword_len) {
	    VALUE keys = make_unknown_kw_hash(passed_keywords, passed_keyword_len, passed_values);
	    argument_kw_error(ec, iseq, "unknown", keys);
	}
    }

    if (NIL_P(unspecified_bits_value)) {
	unspecified_bits_value = INT2FIX(unspecified_bits);
    }
    locals[key_num] = unspecified_bits_value;
}

static inline void
args_setup_kw_rest_parameter(VALUE keyword_hash, VALUE *locals, int kw_flag)
{
    if (NIL_P(keyword_hash)) {
        keyword_hash = rb_hash_new();
    }
    else if (!(kw_flag & VM_CALL_KW_SPLAT_MUT)) {
        keyword_hash = rb_hash_dup(keyword_hash);
    }
    locals[0] = keyword_hash;
}

static inline void
args_setup_block_parameter(const rb_execution_context_t *ec, struct rb_calling_info *calling, VALUE *locals)
{
    VALUE block_handler = calling->block_handler;
    *locals = rb_vm_bh_to_procval(ec, block_handler);
}

struct fill_values_arg {
    VALUE *keys;
    VALUE *vals;
    int argc;
};

static int
fill_keys_values(st_data_t key, st_data_t val, st_data_t ptr)
{
    struct fill_values_arg *arg = (struct fill_values_arg *)ptr;
    int i = arg->argc++;
    arg->keys[i] = (VALUE)key;
    arg->vals[i] = (VALUE)val;
    return ST_CONTINUE;
}

static inline int
ignore_keyword_hash_p(VALUE keyword_hash, const rb_iseq_t * const iseq, unsigned int * kw_flag, VALUE * converted_keyword_hash)
{
    if (!RB_TYPE_P(keyword_hash, T_HASH)) {
        keyword_hash = rb_to_hash_type(keyword_hash);
    }
    if (!(*kw_flag & VM_CALL_KW_SPLAT_MUT) &&
            (iseq->body->param.flags.has_kwrest ||
             iseq->body->param.flags.ruby2_keywords)) {
        *kw_flag |= VM_CALL_KW_SPLAT_MUT;
        keyword_hash = rb_hash_dup(keyword_hash);
    }
    *converted_keyword_hash = keyword_hash;
    return !(iseq->body->param.flags.has_kw) &&
           !(iseq->body->param.flags.has_kwrest) &&
           RHASH_EMPTY_P(keyword_hash);
}

static int
setup_parameters_complex(rb_execution_context_t * const ec, const rb_iseq_t * const iseq,
			 struct rb_calling_info *const calling,
                         const struct rb_callinfo *ci,
                         VALUE * const locals, const enum arg_setup_type arg_setup_type)
{
    const int min_argc = iseq->body->param.lead_num + iseq->body->param.post_num;
    const int max_argc = (iseq->body->param.flags.has_rest == FALSE) ? min_argc + iseq->body->param.opt_num : UNLIMITED_ARGUMENTS;
    int given_argc;
    unsigned int kw_flag = vm_ci_flag(ci) & (VM_CALL_KWARG | VM_CALL_KW_SPLAT | VM_CALL_KW_SPLAT_MUT);
    int opt_pc = 0, allow_autosplat = !kw_flag;
    struct args_info args_body, *args;
    VALUE keyword_hash = Qnil;
    VALUE * const orig_sp = ec->cfp->sp;
    unsigned int i;
    VALUE flag_keyword_hash = 0;
    VALUE converted_keyword_hash = 0;

    vm_check_canary(ec, orig_sp);
    /*
     * Extend SP for GC.
     *
     * [pushed values] [uninitialized values]
     * <- ci->argc -->
     * <- iseq->body->param.size------------>
     * ^ locals        ^ sp
     *
     * =>
     * [pushed values] [initialized values  ]
     * <- ci->argc -->
     * <- iseq->body->param.size------------>
     * ^ locals                             ^ sp
     */
    for (i=calling->argc; i<iseq->body->param.size; i++) {
	locals[i] = Qnil;
    }
    ec->cfp->sp = &locals[i];

    /* setup args */
    args = &args_body;
    given_argc = args->argc = calling->argc;
    args->argv = locals;
    args->rest_dupped = FALSE;

    if (kw_flag & VM_CALL_KWARG) {
	args->kw_arg = vm_ci_kwarg(ci);

	if (iseq->body->param.flags.has_kw) {
	    int kw_len = args->kw_arg->keyword_len;
	    /* copy kw_argv */
	    args->kw_argv = ALLOCA_N(VALUE, kw_len);
	    args->argc -= kw_len;
	    given_argc -= kw_len;
	    MEMCPY(args->kw_argv, locals + args->argc, VALUE, kw_len);
	}
	else {
	    args->kw_argv = NULL;
	    given_argc = args_kw_argv_to_hash(args);
            kw_flag |= VM_CALL_KW_SPLAT | VM_CALL_KW_SPLAT_MUT;
	}
    }
    else {
	args->kw_arg = NULL;
	args->kw_argv = NULL;
    }

    if (vm_ci_flag(ci) & VM_CALL_ARGS_SPLAT) {
        VALUE rest_last = 0;
        int len;
	args->rest = locals[--args->argc];
	args->rest_index = 0;
        len = RARRAY_LENINT(args->rest);
        given_argc += len - 1;
        rest_last = RARRAY_AREF(args->rest, len - 1);

        if (!kw_flag && len > 0) {
            if (RB_TYPE_P(rest_last, T_HASH) &&
                (((struct RHash *)rest_last)->basic.flags & RHASH_PASS_AS_KEYWORDS)) {
                rest_last = rb_hash_dup(rest_last);
                kw_flag |= VM_CALL_KW_SPLAT | VM_CALL_KW_SPLAT_MUT;
            }
            else {
                rest_last = 0;
            }
        }

        if (kw_flag & VM_CALL_KW_SPLAT) {
            if (ignore_keyword_hash_p(rest_last, iseq, &kw_flag, &converted_keyword_hash)) {
                arg_rest_dup(args);
                rb_ary_pop(args->rest);
                given_argc--;
                kw_flag &= ~(VM_CALL_KW_SPLAT | VM_CALL_KW_SPLAT_MUT);
	    }
            else {
                if (rest_last != converted_keyword_hash) {
                    rest_last = converted_keyword_hash;
                    arg_rest_dup(args);
                    RARRAY_ASET(args->rest, len - 1, rest_last);
                }

                if (iseq->body->param.flags.ruby2_keywords && rest_last) {
                    flag_keyword_hash = rest_last;
                }
                else if (iseq->body->param.flags.has_kw || iseq->body->param.flags.has_kwrest) {
                    arg_rest_dup(args);
                    rb_ary_pop(args->rest);
                    given_argc--;
                    keyword_hash = rest_last;
                }
            }
        }
    }
    else {
        if (kw_flag & VM_CALL_KW_SPLAT) {
            VALUE last_arg = args->argv[args->argc-1];
            if (ignore_keyword_hash_p(last_arg, iseq, &kw_flag, &converted_keyword_hash)) {
                args->argc--;
                given_argc--;
                kw_flag &= ~(VM_CALL_KW_SPLAT | VM_CALL_KW_SPLAT_MUT);
	    }
            else {
                if (last_arg != converted_keyword_hash) {
                    last_arg = converted_keyword_hash;
                    args->argv[args->argc-1] = last_arg;
                }

                if (iseq->body->param.flags.ruby2_keywords) {
                    flag_keyword_hash = last_arg;
                }
                else if (iseq->body->param.flags.has_kw || iseq->body->param.flags.has_kwrest) {
                    args->argc--;
                    given_argc--;
                    keyword_hash = last_arg;
                }
            }
        }
	args->rest = Qfalse;
    }

    if (flag_keyword_hash && RB_TYPE_P(flag_keyword_hash, T_HASH)) {
        ((struct RHash *)flag_keyword_hash)->basic.flags |= RHASH_PASS_AS_KEYWORDS;
    }

    if (kw_flag && iseq->body->param.flags.accepts_no_kwarg) {
	rb_raise(rb_eArgError, "no keywords accepted");
    }


    switch (arg_setup_type) {
      case arg_setup_method:
	break; /* do nothing special */
      case arg_setup_block:
        if (given_argc == (keyword_hash == Qnil ? 1 : 2) &&
            allow_autosplat &&
            (min_argc > 0 || iseq->body->param.opt_num > 1) &&
	    !iseq->body->param.flags.ambiguous_param0 &&
	    args_check_block_arg0(args)) {
	    given_argc = RARRAY_LENINT(args->rest);
	}
	break;
    }

    /* argc check */
    if (given_argc < min_argc) {
        if (arg_setup_type == arg_setup_block) {
            CHECK_VM_STACK_OVERFLOW(ec->cfp, min_argc);
            given_argc = min_argc;
            args_extend(args, min_argc);
        }
        else {
            argument_arity_error(ec, iseq, given_argc, min_argc, max_argc);
        }
    }

    if (given_argc > max_argc && max_argc != UNLIMITED_ARGUMENTS) {
	if (arg_setup_type == arg_setup_block) {
	    /* truncate */
	    args_reduce(args, given_argc - max_argc);
	    given_argc = max_argc;
	}
	else {
	    argument_arity_error(ec, iseq, given_argc, min_argc, max_argc);
	}
    }

    if (iseq->body->param.flags.has_lead) {
	args_setup_lead_parameters(args, iseq->body->param.lead_num, locals + 0);
    }

    if (iseq->body->param.flags.has_rest || iseq->body->param.flags.has_post){
        args_copy(args);
    }

    if (iseq->body->param.flags.has_post) {
	args_setup_post_parameters(args, iseq->body->param.post_num, locals + iseq->body->param.post_start);
    }

    if (iseq->body->param.flags.has_opt) {
	int opt = args_setup_opt_parameters(args, iseq->body->param.opt_num, locals + iseq->body->param.lead_num);
	opt_pc = (int)iseq->body->param.opt_table[opt];
    }

    if (iseq->body->param.flags.has_rest) {
	args_setup_rest_parameter(args, locals + iseq->body->param.rest_start);
    }

    if (iseq->body->param.flags.has_kw) {
	VALUE * const klocals = locals + iseq->body->param.keyword->bits_start - iseq->body->param.keyword->num;

	if (args->kw_argv != NULL) {
	    const struct rb_callinfo_kwarg *kw_arg = args->kw_arg;
	    args_setup_kw_parameters(ec, iseq, args->kw_argv, kw_arg->keyword_len, kw_arg->keywords, klocals);
	}
	else if (!NIL_P(keyword_hash)) {
	    int kw_len = rb_long2int(RHASH_SIZE(keyword_hash));
	    struct fill_values_arg arg;
	    /* copy kw_argv */
	    arg.keys = args->kw_argv = ALLOCA_N(VALUE, kw_len * 2);
	    arg.vals = arg.keys + kw_len;
	    arg.argc = 0;
	    rb_hash_foreach(keyword_hash, fill_keys_values, (VALUE)&arg);
	    VM_ASSERT(arg.argc == kw_len);
	    args_setup_kw_parameters(ec, iseq, arg.vals, kw_len, arg.keys, klocals);
	}
	else {
	    VM_ASSERT(args_argc(args) == 0);
	    args_setup_kw_parameters(ec, iseq, NULL, 0, NULL, klocals);
	}
    }
    else if (iseq->body->param.flags.has_kwrest) {
        args_setup_kw_rest_parameter(keyword_hash, locals + iseq->body->param.keyword->rest_start, kw_flag);
    }
    else if (!NIL_P(keyword_hash) && RHASH_SIZE(keyword_hash) > 0 && arg_setup_type == arg_setup_method) {
	argument_kw_error(ec, iseq, "unknown", rb_hash_keys(keyword_hash));
    }

    if (iseq->body->param.flags.has_block) {
	if (iseq->body->local_iseq == iseq) {
	    /* Do nothing */
	}
	else {
	    args_setup_block_parameter(ec, calling, locals + iseq->body->param.block_start);
	}
    }

#if 0
    {
	int i;
	for (i=0; i<iseq->body->param.size; i++) {
	    fprintf(stderr, "local[%d] = %p\n", i, (void *)locals[i]);
	}
    }
#endif

    ec->cfp->sp = orig_sp;
    return opt_pc;
}

static void
raise_argument_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const VALUE exc)
{
    VALUE at;

    if (iseq) {
	vm_push_frame(ec, iseq, VM_FRAME_MAGIC_DUMMY | VM_ENV_FLAG_LOCAL, Qnil /* self */,
		      VM_BLOCK_HANDLER_NONE /* specval*/, Qfalse /* me or cref */,
		      iseq->body->iseq_encoded,
		      ec->cfp->sp, 0, 0 /* stack_max */);
	at = rb_ec_backtrace_object(ec);
	rb_backtrace_use_iseq_first_lineno_for_last_location(at);
	rb_vm_pop_frame(ec);
    }
    else {
	at = rb_ec_backtrace_object(ec);
    }

    rb_ivar_set(exc, idBt_locations, at);
    rb_exc_set_backtrace(exc, at);
    rb_exc_raise(exc);
}

static void
argument_arity_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const int miss_argc, const int min_argc, const int max_argc)
{
    VALUE exc = rb_arity_error_new(miss_argc, min_argc, max_argc);
    if (iseq->body->param.flags.has_kw) {
	const struct rb_iseq_param_keyword *const kw = iseq->body->param.keyword;
	const ID *keywords = kw->table;
	int req_key_num = kw->required_num;
	if (req_key_num > 0) {
	    static const char required[] = "; required keywords";
	    VALUE mesg = rb_attr_get(exc, idMesg);
	    rb_str_resize(mesg, RSTRING_LEN(mesg)-1);
	    rb_str_cat(mesg, required, sizeof(required) - 1 - (req_key_num == 1));
	    rb_str_cat_cstr(mesg, ":");
	    do {
		rb_str_cat_cstr(mesg, " ");
		rb_str_append(mesg, rb_id2str(*keywords++));
		rb_str_cat_cstr(mesg, ",");
	    } while (--req_key_num);
	    RSTRING_PTR(mesg)[RSTRING_LEN(mesg)-1] = ')';
	}
    }
    raise_argument_error(ec, iseq, exc);
}

static void
argument_kw_error(rb_execution_context_t *ec, const rb_iseq_t *iseq, const char *error, const VALUE keys)
{
    raise_argument_error(ec, iseq, rb_keyword_error_new(error, keys));
}

static inline void
vm_caller_setup_arg_splat(rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    int argc = calling->argc;
    VALUE *argv = cfp->sp - argc;
    VALUE ary = argv[argc-1];

    vm_check_canary(GET_EC(), cfp->sp);
    cfp->sp--;

    if (!NIL_P(ary)) {
        const VALUE *ptr = RARRAY_CONST_PTR_TRANSIENT(ary);
        long len = RARRAY_LEN(ary), i;

        CHECK_VM_STACK_OVERFLOW(cfp, len);

        for (i = 0; i < len; i++) {
            *cfp->sp++ = ptr[i];
        }
        calling->argc += i - 1;
    }
}

static inline void
vm_caller_setup_arg_kw(rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_callinfo *ci)
{
    const VALUE *const passed_keywords = vm_ci_kwarg(ci)->keywords;
    const int kw_len = vm_ci_kwarg(ci)->keyword_len;
    const VALUE h = rb_hash_new_with_size(kw_len);
    VALUE *sp = cfp->sp;
    int i;

    for (i=0; i<kw_len; i++) {
	rb_hash_aset(h, passed_keywords[i], (sp - kw_len)[i]);
    }
    (sp-kw_len)[0] = h;

    cfp->sp -= kw_len - 1;
    calling->argc -= kw_len - 1;
    calling->kw_splat = 1;
}

static VALUE
vm_to_proc(VALUE proc)
{
    if (UNLIKELY(!rb_obj_is_proc(proc))) {
	VALUE b;
	const rb_callable_method_entry_t *me =
	    rb_callable_method_entry_with_refinements(CLASS_OF(proc), idTo_proc, NULL);

	if (me) {
            b = rb_vm_call0(GET_EC(), proc, idTo_proc, 0, NULL, me, RB_NO_KEYWORDS);
	}
	else {
	    /* NOTE: calling method_missing */
	    b = rb_check_convert_type_with_id(proc, T_DATA, "Proc", idTo_proc);
	}

	if (NIL_P(b) || !rb_obj_is_proc(b)) {
	    rb_raise(rb_eTypeError,
		     "wrong argument type %s (expected Proc)",
		     rb_obj_classname(proc));
	}
	return b;
    }
    else {
	return proc;
    }
}

static VALUE
refine_sym_proc_call(RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg))
{
    VALUE obj;
    ID mid;
    const rb_callable_method_entry_t *me = 0; /* for hidden object case */
    rb_execution_context_t *ec;
    const VALUE symbol = RARRAY_AREF(callback_arg, 0);
    const VALUE refinements = RARRAY_AREF(callback_arg, 1);
    int kw_splat = RB_PASS_CALLED_KEYWORDS;
    VALUE klass;

    if (argc-- < 1) {
	rb_raise(rb_eArgError, "no receiver given");
    }
    obj = *argv++;

    mid = SYM2ID(symbol);
    for (klass = CLASS_OF(obj); klass; klass = RCLASS_SUPER(klass)) {
        me = rb_callable_method_entry(klass, mid);
        if (me) {
            me = rb_resolve_refined_method_callable(refinements, me);
            if (me) break;
        }
    }

    ec = GET_EC();
    if (!NIL_P(blockarg)) {
	vm_passed_block_handler_set(ec, blockarg);
    }
    if (!me) {
        return method_missing(ec, obj, mid, argc, argv, MISSING_NOENTRY, kw_splat);
    }
    return rb_vm_call0(ec, obj, mid, argc, argv, me, kw_splat);
}

static VALUE
vm_caller_setup_arg_block(const rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                          const struct rb_callinfo *ci, const rb_iseq_t *blockiseq, const int is_super)
{
    if (vm_ci_flag(ci) & VM_CALL_ARGS_BLOCKARG) {
	VALUE block_code = *(--reg_cfp->sp);

	if (NIL_P(block_code)) {
            return VM_BLOCK_HANDLER_NONE;
        }
	else if (block_code == rb_block_param_proxy) {
            VM_ASSERT(!VM_CFP_IN_HEAP_P(GET_EC(), reg_cfp));
            VALUE handler = VM_CF_BLOCK_HANDLER(reg_cfp);
            reg_cfp->block_code = (const void *) handler;
            return handler;
        }
	else if (SYMBOL_P(block_code) && rb_method_basic_definition_p(rb_cSymbol, idTo_proc)) {
	    const rb_cref_t *cref = vm_env_cref(reg_cfp->ep);
	    if (cref && !NIL_P(cref->refinements)) {
		VALUE ref = cref->refinements;
		VALUE func = rb_hash_lookup(ref, block_code);
		if (NIL_P(func)) {
		    /* TODO: limit cached funcs */
                    VALUE callback_arg = rb_ary_tmp_new(2);
                    rb_ary_push(callback_arg, block_code);
                    rb_ary_push(callback_arg, ref);
                    OBJ_FREEZE_RAW(callback_arg);
                    func = rb_func_lambda_new(refine_sym_proc_call, callback_arg, 1, UNLIMITED_ARGUMENTS);
		    rb_hash_aset(ref, block_code, func);
		}
		block_code = func;
	    }
            return block_code;
        }
        else {
            return vm_to_proc(block_code);
        }
    }
    else if (blockiseq != NULL) { /* likely */
	struct rb_captured_block *captured = VM_CFP_TO_CAPTURED_BLOCK(reg_cfp);
	captured->code.iseq = blockiseq;
        return VM_BH_FROM_ISEQ_BLOCK(captured);
    }
    else {
	if (is_super) {
            return GET_BLOCK_HANDLER();
        }
        else {
            return VM_BLOCK_HANDLER_NONE;
        }
    }
}
