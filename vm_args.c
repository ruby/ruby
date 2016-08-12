/**********************************************************************

  vm_args.c - process method call arguments.

  $Author$

  Copyright (C) 2014- Yukihiro Matsumoto

**********************************************************************/

NORETURN(static void raise_argument_error(rb_thread_t *th, const rb_iseq_t *iseq, const VALUE exc));
NORETURN(static void argument_arity_error(rb_thread_t *th, const rb_iseq_t *iseq, const int miss_argc, const int min_argc, const int max_argc));
NORETURN(static void argument_kw_error(rb_thread_t *th, const rb_iseq_t *iseq, const char *error, const VALUE keys));
VALUE rb_keyword_error_new(const char *error, VALUE keys); /* class.c */

struct args_info {
    /* basic args info */
    rb_call_info_t *ci;
    VALUE *argv;
    int argc;

    /* additional args info */
    int rest_index;
    VALUE *kw_argv;
    VALUE rest;
};

enum arg_setup_type {
    arg_setup_method,
    arg_setup_block,
    arg_setup_lambda
};

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
	args->rest = rb_ary_dup(args->rest);
	assert(args->rest_index == 0);
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
	    args->rest = rb_ary_dup(args->rest);
	    rb_ary_resize(args->rest, len - over_argc);
	    return;
	}
	else {
	    args->rest = Qfalse;
	    over_argc -= len;
	}
    }

    assert(args->argc >= over_argc);
    args->argc -= over_argc;
}

static inline int
args_check_block_arg0(struct args_info *args, rb_thread_t *th)
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
	args->rest = rb_ary_dup(args->rest); /* make dup */

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
	args->argc = 0;
    }
}

static inline const VALUE *
args_rest_argv(struct args_info *args)
{
    return RARRAY_CONST_PTR(args->rest) + args->rest_index;
}

static inline VALUE
args_rest_array(struct args_info *args)
{
    VALUE ary;

    if (args->rest) {
	ary = rb_ary_subseq(args->rest, args->rest_index, RARRAY_LEN(args->rest) - args->rest_index);
	args->rest = 0;
    }
    else {
	ary = rb_ary_new();
    }
    return ary;
}

static int
keyword_hash_p(VALUE *kw_hash_ptr, VALUE *rest_hash_ptr, rb_thread_t *th)
{
    *rest_hash_ptr = rb_check_hash_type(*kw_hash_ptr);

    if (!NIL_P(*rest_hash_ptr)) {
	VALUE hash = rb_extract_keywords(rest_hash_ptr);
	if (!hash) hash = Qnil;
	*kw_hash_ptr = hash;
	return TRUE;
    }
    else {
	*kw_hash_ptr = Qnil;
	return FALSE;
    }
}

static VALUE
args_pop_keyword_hash(struct args_info *args, VALUE *kw_hash_ptr, rb_thread_t *th)
{
    VALUE rest_hash;

    if (args->rest == Qfalse) {
      from_argv:
	assert(args->argc > 0);
	*kw_hash_ptr = args->argv[args->argc-1];

	if (keyword_hash_p(kw_hash_ptr, &rest_hash, th)) {
	    if (rest_hash) {
		args->argv[args->argc-1] = rest_hash;
	    }
	    else {
		args->argc--;
		return TRUE;
	    }
	}
    }
    else {
	long len = RARRAY_LEN(args->rest);

	if (len > 0) {
	    *kw_hash_ptr = RARRAY_AREF(args->rest, len - 1);

	    if (keyword_hash_p(kw_hash_ptr, &rest_hash, th)) {
		if (rest_hash) {
		    RARRAY_ASET(args->rest, len - 1, rest_hash);
		}
		else {
		    args->rest = rb_ary_dup(args->rest);
		    rb_ary_pop(args->rest);
		    return TRUE;
		}
	    }
	}
	else {
	    goto from_argv;
	}
    }

    return FALSE;
}

static int
args_kw_argv_to_hash(struct args_info *args)
{
    const VALUE *const passed_keywords = args->ci->kw_arg->keywords;
    const int kw_len = args->ci->kw_arg->keyword_len;
    VALUE h = rb_hash_new();
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

static void
args_stored_kw_argv_to_hash(struct args_info *args)
{
    VALUE h = rb_hash_new();
    int i;
    const VALUE *const passed_keywords = args->ci->kw_arg->keywords;
    const int passed_keyword_len = args->ci->kw_arg->keyword_len;

    for (i=0; i<passed_keyword_len; i++) {
	rb_hash_aset(h, passed_keywords[i], args->kw_argv[i]);
    }
    args->kw_argv = NULL;

    if (args->rest) {
	args->rest = rb_ary_dup(args->rest);
	rb_ary_push(args->rest, h);
    }
    else {
	args->argv[args->argc++] = h;
    }
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
    args_copy(args);
    len = RARRAY_LEN(args->rest);
    MEMCPY(locals, RARRAY_CONST_PTR(args->rest) + len - argc, VALUE, argc);
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
	    const VALUE *argv = RARRAY_CONST_PTR(args->rest);

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
    args_copy(args);
    *locals = args_rest_array(args);
}

static VALUE
make_unused_kw_hash(const VALUE *passed_keywords, int passed_keyword_len, const VALUE *kw_argv, const int key_only)
{
    int i;
    VALUE obj = key_only ? rb_ary_tmp_new(1) : rb_hash_new();

    for (i=0; i<passed_keyword_len; i++) {
	if (kw_argv[i] != Qundef) {
	    if (key_only) {
		rb_ary_push(obj, passed_keywords[i]);
	    }
	    else {
		rb_hash_aset(obj, passed_keywords[i], kw_argv[i]);
	    }
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

static void
args_setup_kw_parameters(VALUE* const passed_values, const int passed_keyword_len, const VALUE *const passed_keywords,
			 const rb_iseq_t * const iseq, VALUE * const locals)
{
    const ID *acceptable_keywords = iseq->param.keyword->table;
    const int req_key_num = iseq->param.keyword->required_num;
    const int key_num = iseq->param.keyword->num;
    const VALUE * const default_values = iseq->param.keyword->default_values;
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

    if (missing) argument_kw_error(GET_THREAD(), iseq, "missing", missing);

    for (di=0; i<key_num; i++, di++) {
	if (args_setup_kw_parameters_lookup(acceptable_keywords[i], &locals[i], passed_keywords, passed_values, passed_keyword_len)) {
	    found++;
	}
	else {
	    if (default_values[di] == Qundef) {
		locals[i] = Qnil;

		if (LIKELY(i < 32)) { /* TODO: 32 -> Fixnum's max bits */
		    unspecified_bits |= 0x01 << di;
		}
		else {
		    if (NIL_P(unspecified_bits_value)) {
			/* fixnum -> hash */
			int j;
			unspecified_bits_value = rb_hash_new();

			for (j=0; j<32; j++) {
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

    if (iseq->param.flags.has_kwrest) {
	const int rest_hash_index = key_num + 1;
	locals[rest_hash_index] = make_unused_kw_hash(passed_keywords, passed_keyword_len, passed_values, FALSE);
    }
    else {
	if (found != passed_keyword_len) {
	    VALUE keys = make_unused_kw_hash(passed_keywords, passed_keyword_len, passed_values, TRUE);
	    argument_kw_error(GET_THREAD(), iseq, "unknown", keys);
	}
    }

    if (NIL_P(unspecified_bits_value)) {
	unspecified_bits_value = INT2FIX(unspecified_bits);
    }
    locals[key_num] = unspecified_bits_value;
}

static inline void
args_setup_kw_rest_parameter(VALUE keyword_hash, VALUE *locals)
{
    locals[0] = NIL_P(keyword_hash) ? rb_hash_new() : rb_hash_dup(keyword_hash);
}

static inline void
args_setup_block_parameter(rb_thread_t *th, rb_call_info_t *ci, VALUE *locals)
{
    VALUE blockval = Qnil;
    const rb_block_t *blockptr = ci->blockptr;

    if (blockptr) {
	/* make Proc object */
	if (blockptr->proc == 0) {
	    rb_proc_t *proc;
	    blockval = rb_vm_make_proc(th, blockptr, rb_cProc);
	    GetProcPtr(blockval, proc);
	    ci->blockptr = &proc->block;
	}
	else {
	    blockval = blockptr->proc;
	}
    }
    *locals = blockval;
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

static int
setup_parameters_complex(rb_thread_t * const th, const rb_iseq_t * const iseq, rb_call_info_t * const ci,
			 VALUE * const locals, const enum arg_setup_type arg_setup_type)
{
    const int min_argc = iseq->param.lead_num + iseq->param.post_num;
    const int max_argc = (iseq->param.flags.has_rest == FALSE) ? min_argc + iseq->param.opt_num : UNLIMITED_ARGUMENTS;
    int opt_pc = 0;
    int given_argc;
    struct args_info args_body, *args;
    VALUE keyword_hash = Qnil;
    VALUE * const orig_sp = th->cfp->sp;
    int i;

    /*
     * Extend SP for GC.
     *
     * [pushed values] [uninitialized values]
     * <- ci->argc -->
     * <- iseq->param.size------------------>
     * ^ locals        ^ sp
     *
     * =>
     * [pushed values] [initialized values  ]
     * <- ci->argc -->
     * <- iseq->param.size------------------>
     * ^ locals                             ^ sp
     */
    for (i=ci->argc; i<iseq->param.size; i++) {
	locals[i] = Qnil;
    }
    th->cfp->sp = &locals[i];

    /* setup args */
    args = &args_body;
    args->ci = ci;
    given_argc = args->argc = ci->argc;
    args->argv = locals;

    if (ci->kw_arg) {
	if (iseq->param.flags.has_kw) {
	    int kw_len = ci->kw_arg->keyword_len;
	    /* copy kw_argv */
	    args->kw_argv = ALLOCA_N(VALUE, kw_len);
	    args->argc -= kw_len;
	    given_argc -= kw_len;
	    MEMCPY(args->kw_argv, locals + args->argc, VALUE, kw_len);
	}
	else {
	    args->kw_argv = NULL;
	    given_argc = args_kw_argv_to_hash(args);
	}
    }
    else {
	args->kw_argv = NULL;
    }

    if (ci->flag & VM_CALL_ARGS_SPLAT) {
	args->rest = locals[--args->argc];
	args->rest_index = 0;
	given_argc += RARRAY_LENINT(args->rest) - 1;
    }
    else {
	args->rest = Qfalse;
    }

    switch (arg_setup_type) {
      case arg_setup_method:
	break; /* do nothing special */
      case arg_setup_block:
	if (given_argc == 1 &&
	    (min_argc > 0 || iseq->param.opt_num > 1 ||
	     iseq->param.flags.has_kw || iseq->param.flags.has_kwrest) &&
	    !iseq->param.flags.ambiguous_param0 &&
	    args_check_block_arg0(args, th)) {
	    given_argc = RARRAY_LENINT(args->rest);
	}
	break;
      case arg_setup_lambda:
	if (given_argc == 1 &&
	    given_argc != iseq->param.lead_num &&
	    !iseq->param.flags.has_opt &&
	    !iseq->param.flags.has_rest &&
	    args_check_block_arg0(args, th)) {
	    given_argc = RARRAY_LENINT(args->rest);
	}
    }

    /* argc check */
    if (given_argc < min_argc) {
	if (given_argc == min_argc - 1 && args->kw_argv) {
	    args_stored_kw_argv_to_hash(args);
	    given_argc = args_argc(args);
	}
	else {
	    if (arg_setup_type == arg_setup_block) {
		CHECK_VM_STACK_OVERFLOW(th->cfp, min_argc);
		given_argc = min_argc;
		args_extend(args, min_argc);
	    }
	    else {
		argument_arity_error(th, iseq, given_argc, min_argc, max_argc);
	    }
	}
    }

    if (given_argc > min_argc &&
	(iseq->param.flags.has_kw || iseq->param.flags.has_kwrest) &&
	args->kw_argv == NULL) {
	if (args_pop_keyword_hash(args, &keyword_hash, th)) {
	    given_argc--;
	}
    }

    if (given_argc > max_argc && max_argc != UNLIMITED_ARGUMENTS) {
	if (arg_setup_type == arg_setup_block) {
	    /* truncate */
	    args_reduce(args, given_argc - max_argc);
	    given_argc = max_argc;
	}
	else {
	    argument_arity_error(th, iseq, given_argc, min_argc, max_argc);
	}
    }

    if (iseq->param.flags.has_lead) {
	args_setup_lead_parameters(args, iseq->param.lead_num, locals + 0);
    }

    if (iseq->param.flags.has_post) {
	args_setup_post_parameters(args, iseq->param.post_num, locals + iseq->param.post_start);
    }

    if (iseq->param.flags.has_opt) {
	int opt = args_setup_opt_parameters(args, iseq->param.opt_num, locals + iseq->param.lead_num);
	opt_pc = (int)iseq->param.opt_table[opt];
    }

    if (iseq->param.flags.has_rest) {
	args_setup_rest_parameter(args, locals + iseq->param.rest_start);
    }

    if (iseq->param.flags.has_kw) {
	VALUE * const klocals = locals + iseq->param.keyword->bits_start - iseq->param.keyword->num;

	if (args->kw_argv != NULL) {
	    args_setup_kw_parameters(args->kw_argv, args->ci->kw_arg->keyword_len, args->ci->kw_arg->keywords, iseq, klocals);
	}
	else if (!NIL_P(keyword_hash)) {
	    int kw_len = rb_long2int(RHASH_SIZE(keyword_hash));
	    struct fill_values_arg arg;
	    /* copy kw_argv */
	    arg.keys = args->kw_argv = ALLOCA_N(VALUE, kw_len * 2);
	    arg.vals = arg.keys + kw_len;
	    arg.argc = 0;
	    rb_hash_foreach(keyword_hash, fill_keys_values, (VALUE)&arg);
	    assert(arg.argc == kw_len);
	    args_setup_kw_parameters(arg.vals, kw_len, arg.keys, iseq, klocals);
	}
	else {
	    assert(args_argc(args) == 0);
	    args_setup_kw_parameters(NULL, 0, NULL, iseq, klocals);
	}
    }
    else if (iseq->param.flags.has_kwrest) {
	args_setup_kw_rest_parameter(keyword_hash, locals + iseq->param.keyword->rest_start);
    }

    if (iseq->param.flags.has_block) {
	args_setup_block_parameter(th, ci, locals + iseq->param.block_start);
    }

#if 0
    {
	int i;
	for (i=0; i<iseq->param.size; i++) {
	    fprintf(stderr, "local[%d] = %p\n", i, (void *)locals[i]);
	}
    }
#endif

    th->cfp->sp = orig_sp;
    return opt_pc;
}

static void
raise_argument_error(rb_thread_t *th, const rb_iseq_t *iseq, const VALUE exc)
{
    VALUE at;

    if (iseq) {
	vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD, Qnil /* self */, Qnil /* klass */, Qnil /* specval*/,
		      iseq->iseq_encoded, th->cfp->sp, 0 /* local_size */, 0 /* me */, 0 /* stack_max */);
	at = rb_vm_backtrace_object();
	vm_pop_frame(th);
    }
    else {
	at = rb_vm_backtrace_object();
    }

    rb_iv_set(exc, "bt_locations", at);
    rb_funcall(exc, rb_intern("set_backtrace"), 1, at);
    rb_exc_raise(exc);
}

static void
argument_arity_error(rb_thread_t *th, const rb_iseq_t *iseq, const int miss_argc, const int min_argc, const int max_argc)
{
    raise_argument_error(th, iseq, rb_arity_error_new(miss_argc, min_argc, max_argc));
}

static void
argument_kw_error(rb_thread_t *th, const rb_iseq_t *iseq, const char *error, const VALUE keys)
{
    raise_argument_error(th, iseq, rb_keyword_error_new(error, keys));
}

static inline void
vm_caller_setup_arg_splat(rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    VALUE *argv = cfp->sp - ci->argc;
    VALUE ary = argv[ci->argc-1];

    cfp->sp--;

    if (!NIL_P(ary)) {
	const VALUE *ptr = RARRAY_CONST_PTR(ary);
	long len = RARRAY_LEN(ary), i;

	CHECK_VM_STACK_OVERFLOW(cfp, len);

	for (i = 0; i < len; i++) {
	    *cfp->sp++ = ptr[i];
	}
	ci->argc += i - 1;
    }
}

static inline void
vm_caller_setup_arg_kw(rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    const VALUE *const passed_keywords = ci->kw_arg->keywords;
    const int kw_len = ci->kw_arg->keyword_len;
    const VALUE h = rb_hash_new();
    VALUE *sp = cfp->sp;
    int i;

    for (i=0; i<kw_len; i++) {
	rb_hash_aset(h, passed_keywords[i], (sp - kw_len)[i]);
    }
    (sp-kw_len)[0] = h;

    cfp->sp -= kw_len - 1;
    ci->argc -= kw_len - 1;
}

#define SAVE_RESTORE_CI(expr, ci) do { \
    int saved_argc = (ci)->argc; rb_block_t *saved_blockptr = (ci)->blockptr; /* save */ \
    expr; \
    (ci)->argc = saved_argc; (ci)->blockptr = saved_blockptr; /* restore */ \
} while (0)

static void
vm_caller_setup_arg_block(const rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci, const int is_super)
{
    if (ci->flag & VM_CALL_ARGS_BLOCKARG) {
	rb_proc_t *po;
	VALUE proc;

	proc = *(--reg_cfp->sp);

	if (proc != Qnil) {
	    if (!rb_obj_is_proc(proc)) {
		VALUE b;

		SAVE_RESTORE_CI(b = rb_check_convert_type(proc, T_DATA, "Proc", "to_proc"), ci);

		if (NIL_P(b) || !rb_obj_is_proc(b)) {
		    rb_raise(rb_eTypeError,
			     "wrong argument type %s (expected Proc)",
			     rb_obj_classname(proc));
		}
		proc = b;
	    }
	    GetProcPtr(proc, po);
	    ci->blockptr = &po->block;
	    RUBY_VM_GET_BLOCK_PTR_IN_CFP(reg_cfp)->proc = proc;
	}
	else {
	    ci->blockptr = NULL;
	}
    }
    else if (ci->blockiseq != 0) { /* likely */
	ci->blockptr = RUBY_VM_GET_BLOCK_PTR_IN_CFP(reg_cfp);
	ci->blockptr->iseq = ci->blockiseq;
	ci->blockptr->proc = 0;
    }
    else {
	if (is_super) {
	    ci->blockptr = GET_BLOCK_PTR();
	}
	else {
	    ci->blockptr = NULL;
	}
    }
}

#define IS_ARGS_SPLAT(ci) ((ci)->flag & VM_CALL_ARGS_SPLAT)
#define IS_ARGS_KEYWORD(ci) ((ci)->kw_arg != NULL)

#define CALLER_SETUP_ARG(cfp, ci) do { \
    if (UNLIKELY(IS_ARGS_SPLAT(ci))) vm_caller_setup_arg_splat((cfp), (ci)); \
    if (UNLIKELY(IS_ARGS_KEYWORD(ci))) vm_caller_setup_arg_kw((cfp), (ci)); \
} while (0)
