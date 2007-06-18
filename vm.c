/**********************************************************************

  vm.c -

  $Author$
  $Date$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/node.h"
#include "ruby/st.h"
// #define MARK_FREE_DEBUG 1
#include "gc.h"

#include "yarvcore.h"
#include "vm.h"
#include "insnhelper.h"
#include "vm_macro.inc"
#include "insns.inc"
#include "eval_intern.h"

VALUE rb_cEnv;

#define PROCDEBUG 0
#define VM_DEBUG  0

#define BUFSIZE 0x100

#define EVALBODY_HELPER_FUNCTION static inline

typedef unsigned long rb_num_t;
typedef unsigned long lindex_t;
typedef unsigned long dindex_t;

typedef rb_num_t GENTRY;

void vm_analysis_operand(int insn, int n, VALUE op);
void vm_analysis_register(int reg, int isset);
void vm_analysis_insn(int insn);

static inline VALUE
th_yield_cfunc(rb_thread_t *th, rb_block_t *block,
	       VALUE self, int argc, VALUE *argv);

VALUE th_invoke_proc(rb_thread_t *th, rb_proc_t *proc,
		     VALUE self, int argc, VALUE *argv);

VALUE th_eval_body(rb_thread_t *th);
static NODE *lfp_get_special_cref(VALUE *lfp);
static NODE *lfp_set_special_cref(VALUE *lfp, NODE * cref);

static inline int block_proc_is_lambda(VALUE procval);

#if OPT_STACK_CACHING
static VALUE yarv_finish_insn_seq[1] = { BIN(finish_SC_ax_ax) };
#elif OPT_CALL_THREADED_CODE
static VALUE const yarv_finish_insn_seq[1] = { 0 };
#else
static VALUE yarv_finish_insn_seq[1] = { BIN(finish) };
#endif

#include "call_cfunc.ci"

static VALUE vm_global_state_version = 1;

void
rb_vm_change_state(void)
{
    INC_VM_STATE_VERSION();
}

/*
 * prepare stack frame
 */
static inline rb_control_frame_t *
push_frame(rb_thread_t *th, rb_iseq_t *iseq, VALUE magic,
	   VALUE self, VALUE specval, VALUE *pc,
	   VALUE *sp, VALUE *lfp, int local_size)
{
    VALUE *dfp;
    rb_control_frame_t *cfp;
    int i;

    /* nil initialize */
    for (i=0; i < local_size; i++) {
	*sp = Qnil;
	sp++;
    }

    /* set special val */
    *sp = GC_GUARDED_PTR(specval);
    dfp = sp;

    if (lfp == 0) {
	lfp = sp;
    }

    cfp = th->cfp = th->cfp - 1;
    cfp->pc = pc;
    cfp->sp = sp + 1;
    cfp->bp = sp + 1;
    cfp->iseq = iseq;
    cfp->magic = magic;
    cfp->self = self;
    cfp->lfp = lfp;
    cfp->dfp = dfp;
    cfp->proc = 0;

#define COLLECT_PROFILE 0
#if COLLECT_PROFILE
    cfp->prof_time_self = clock();
    cfp->prof_time_chld = 0;
#endif

    return cfp;
}

static inline void
pop_frame(rb_thread_t *th)
{
#if COLLECT_PROFILE
    rb_control_frame_t *cfp = th->cfp;

    if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	VALUE current_time = clock();
	rb_control_frame_t *cfp = th->cfp;
	cfp->prof_time_self = current_time - cfp->prof_time_self;
	(cfp+1)->prof_time_chld += cfp->prof_time_self;

	cfp->iseq->profile.count++;
	cfp->iseq->profile.time_cumu = cfp->prof_time_self;
	cfp->iseq->profile.time_self = cfp->prof_time_self - cfp->prof_time_chld;
    }
    else if (0 /* c method? */) {

    }
#endif
    th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
}

VALUE
th_set_finish_env(rb_thread_t *th)
{
    push_frame(th, 0, FRAME_MAGIC_FINISH,
	       Qnil, th->cfp->lfp[0], 0,
	       th->cfp->sp, 0, 1);
    th->cfp->pc = &yarv_finish_insn_seq[0];
    return Qtrue;
}

void
th_set_top_stack(rb_thread_t *th, VALUE iseqval)
{
    rb_iseq_t *iseq;
    GetISeqPtr(iseqval, iseq);

    if (iseq->type != ISEQ_TYPE_TOP) {
	rb_raise(rb_eTypeError, "Not a toplevel InstructionSequence");
    }

    /* for return */
    th_set_finish_env(th);

    push_frame(th, iseq, FRAME_MAGIC_TOP,
	       th->top_self, 0, iseq->iseq_encoded,
	       th->cfp->sp, 0, iseq->local_size);
}

VALUE
th_set_eval_stack(rb_thread_t *th, VALUE iseqval)
{
    rb_iseq_t *iseq;
    rb_block_t *block = th->base_block;
    GetISeqPtr(iseqval, iseq);

    /* for return */
    th_set_finish_env(th);
    push_frame(th, iseq, FRAME_MAGIC_EVAL, block->self,
	       GC_GUARDED_PTR(block->dfp), iseq->iseq_encoded,
	       th->cfp->sp, block->lfp, iseq->local_size);
    return 0;
}


/* Env */

static void
env_free(void *ptr)
{
    rb_env_t *env;
    FREE_REPORT_ENTER("env");
    if (ptr) {
	env = ptr;
	FREE_UNLESS_NULL(env->env);
	ruby_xfree(ptr);
    }
    FREE_REPORT_LEAVE("env");
}

static void
env_mark(void *ptr)
{
    rb_env_t *env;
    MARK_REPORT_ENTER("env");
    if (ptr) {
	env = ptr;
	if (env->env) {
	    /* TODO: should mark more restricted range */
	    GC_INFO("env->env\n");
	    rb_gc_mark_locations(env->env, env->env + env->env_size);
	}

	GC_INFO("env->prev_envval\n");
	MARK_UNLESS_NULL(env->prev_envval);
	MARK_UNLESS_NULL(env->block.proc);

	if (env->block.iseq) {
	    if (BUILTIN_TYPE(env->block.iseq) == T_NODE) {
		MARK_UNLESS_NULL((VALUE)env->block.iseq);
	    }
	    else {
		MARK_UNLESS_NULL(env->block.iseq->self);
	    }
	}
    }
    MARK_REPORT_LEAVE("env");
}

static VALUE
env_alloc(void)
{
    VALUE obj;
    rb_env_t *env;
    obj = Data_Make_Struct(rb_cEnv, rb_env_t, env_mark, env_free, env);
    env->env = 0;
    env->prev_envval = 0;
    env->block.iseq = 0;
    return obj;
}

static int check_env(rb_env_t *env);

static VALUE
th_make_env_each(rb_thread_t *th, rb_control_frame_t *cfp,
		 VALUE *envptr, VALUE *endptr)
{
    VALUE envval, penvval = 0;
    rb_env_t *env;
    VALUE *nenvptr;
    int i, local_size;

    if (ENV_IN_HEAP_P(envptr)) {
	return ENV_VAL(envptr);
    }

    if (envptr != endptr) {
	VALUE *penvptr = GC_GUARDED_PTR_REF(*envptr);
	rb_control_frame_t *pcfp = cfp;

	if (ENV_IN_HEAP_P(penvptr)) {
	    penvval = ENV_VAL(penvptr);
	}
	else {
	    while (pcfp->dfp != penvptr) {
		pcfp++;
		if (pcfp->dfp == 0) {
		    SDR();
		    printf("[BUG] orz\n");
		    exit(0);
		}
	    }
	    penvval = th_make_env_each(th, pcfp, penvptr, endptr);
	    cfp->lfp = pcfp->lfp;
	    *envptr = GC_GUARDED_PTR(pcfp->dfp);
	}
    }

    /* allocate env */
    envval = env_alloc();
    GetEnvPtr(envval, env);

    if (!RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	local_size = 2;
    }
    else {
	local_size = cfp->iseq->local_size;
    }

    env->env_size = local_size + 1 + 4;
    env->local_size = local_size;
    env->env = ALLOC_N(VALUE, env->env_size);
    env->prev_envval = penvval;

    for (i = 0; i <= local_size; i++) {
	env->env[i] = envptr[-local_size + i];
	// dp(env->env[i]);
	if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	    /* clear value stack for GC */
	    // envptr[-local_size + i] = 0;
	}
    }

    *envptr = envval;		/* GC mark */
    nenvptr = &env->env[i - 1];
    nenvptr[1] = Qfalse;	/* frame is not orphan */
    nenvptr[2] = Qundef;	/* frame is in heap    */
    nenvptr[3] = envval;	/* frame self */
    nenvptr[4] = penvval;	/* frame prev env object */

    /* reset lfp/dfp in cfp */
    cfp->dfp = nenvptr;
    if (envptr == endptr) {
	cfp->lfp = nenvptr;
    }

    /* as Binding */
    env->block.self = cfp->self;
    env->block.lfp = cfp->lfp;
    env->block.dfp = cfp->dfp;
    env->block.iseq = cfp->iseq;

    if (VM_DEBUG &&
	(!(cfp->lfp[-1] == Qnil ||
	  BUILTIN_TYPE(cfp->lfp[-1]) == T_VALUES))) {
	rb_bug("illegal svar");
    }

    if (!RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	/* TODO */
	env->block.iseq = 0;
    }
    return envval;
}

static VALUE check_env_value(VALUE envval);

static int
check_env(rb_env_t *env)
{
    printf("---\n");
    printf("envptr: %p\n", &env->block.dfp[0]);
    printf("orphan: %p\n", (void *)env->block.dfp[1]);
    printf("inheap: %p\n", (void *)env->block.dfp[2]);
    printf("envval: %10p ", (void *)env->block.dfp[3]);
    dp(env->block.dfp[3]);
    printf("penvv : %10p ", (void *)env->block.dfp[4]);
    dp(env->block.dfp[4]);
    printf("lfp:    %10p\n", env->block.lfp);
    printf("dfp:    %10p\n", env->block.dfp);
    if (env->block.dfp[4]) {
	printf(">>\n");
	check_env_value(env->block.dfp[4]);
	printf("<<\n");
    }
    return 1;
}

static VALUE
check_env_value(VALUE envval)
{
    rb_env_t *env;
    GetEnvPtr(envval, env);

    if (check_env(env)) {
	return envval;
    }
    rb_bug("invalid env\n");
    return Qnil;		/* unreachable */
}

static int
collect_local_variables_in_env(rb_env_t *env, VALUE ary)
{
    int i;
    if (env->block.lfp == env->block.dfp) {
	return 0;
    }
    for (i = 0; i < env->block.iseq->local_table_size; i++) {
	ID lid = env->block.iseq->local_table[i];
	if (lid) {
	    rb_ary_push(ary, rb_str_new2(rb_id2name(lid)));
	}
    }
    if (env->prev_envval) {
	GetEnvPtr(env->prev_envval, env);
	collect_local_variables_in_env(env, ary);
    }
    return 0;
}

int
th_collect_local_variables_in_heap(rb_thread_t *th, VALUE *dfp, VALUE ary)
{
    if (ENV_IN_HEAP_P(dfp)) {
	rb_env_t *env;
	GetEnvPtr(ENV_VAL(dfp), env);
	collect_local_variables_in_env(env, ary);
	return 1;
    }
    else {
	return 0;
    }
}

VALUE
th_make_env_object(rb_thread_t *th, rb_control_frame_t *cfp)
{
    VALUE envval;
    // SDR2(cfp);
    envval = th_make_env_each(th, cfp, cfp->dfp, cfp->lfp);
    if (PROCDEBUG) {
	check_env_value(envval);
    }
    return envval;
}

void
th_stack_to_heap(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    while ((cfp = th_get_ruby_level_cfp(th, cfp)) != 0) {
	th_make_env_object(th, cfp);
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
}

static VALUE
th_make_proc_from_block(rb_thread_t *th, rb_control_frame_t *cfp,
			rb_block_t *block)
{
    VALUE procval;
    rb_control_frame_t *bcfp;
    VALUE *bdfp;		/* to gc mark */

    if (block->proc) {
	return block->proc;
    }

    bcfp = RUBY_VM_GET_CFP_FROM_BLOCK_PTR(block);
    bdfp = bcfp->dfp;
    block->proc = procval = th_make_proc(th, bcfp, block);
    return procval;
}

VALUE
th_make_proc(rb_thread_t *th,
	     rb_control_frame_t *cfp, rb_block_t *block)
{
    VALUE procval, envval, blockprocval = 0;
    rb_proc_t *proc;

    if (GC_GUARDED_PTR_REF(cfp->lfp[0])) {
	if (!RUBY_VM_CLASS_SPECIAL_P(cfp->lfp[0])) {
	    rb_proc_t *p;

	    blockprocval = th_make_proc_from_block(
		th, cfp, (rb_block_t *)GC_GUARDED_PTR_REF(*cfp->lfp));

	    GetProcPtr(blockprocval, p);
	    *cfp->lfp = GC_GUARDED_PTR(&p->block);
	}
    }
    envval = th_make_env_object(th, cfp);

    if (PROCDEBUG) {
	check_env_value(envval);
    }
    procval = rb_proc_alloc();
    GetProcPtr(procval, proc);
    proc->blockprocval = blockprocval;
    proc->block.self = block->self;
    proc->block.lfp = block->lfp;
    proc->block.dfp = block->dfp;
    proc->block.iseq = block->iseq;
    proc->block.proc = procval;
    proc->envval = envval;
    proc->safe_level = th->safe_level;
    proc->special_cref_stack = lfp_get_special_cref(block->lfp);

    if (VM_DEBUG) {
	if (th->stack < block->dfp && block->dfp < th->stack + th->stack_size) {
	    rb_bug("invalid ptr: block->dfp");
	}
	if (th->stack < block->lfp && block->lfp < th->stack + th->stack_size) {
	    rb_bug("invalid ptr: block->lfp");
	}
    }

    return procval;
}

static inline VALUE
th_invoke_bmethod(rb_thread_t *th, ID id, VALUE procval, VALUE recv,
		  VALUE klass, int argc, VALUE *argv)
{
    rb_control_frame_t *cfp = th->cfp;
    rb_proc_t *proc;
    VALUE val;

    /* control block frame */
    (cfp-2)->method_id = id;
    (cfp-2)->method_klass = klass;

    GetProcPtr(procval, proc);
    val = th_invoke_proc(th, proc, recv, argc, argv);
    return val;
}

VALUE
th_call0(rb_thread_t *th, VALUE klass, VALUE recv,
	 VALUE id, ID oid, int argc, const VALUE *argv,
	 NODE * body, int nosuper)
{
    VALUE val;
    rb_block_t *blockptr = 0;

    if (0) printf("id: %s, nd: %s, argc: %d, passed: %p\n",
		  rb_id2name(id), ruby_node_name(nd_type(body)),
		  argc, th->passed_block);
    //SDR2(th->cfp);

    if (th->passed_block) {
	blockptr = th->passed_block;
	th->passed_block = 0;
    }
    switch (nd_type(body)) {
      case RUBY_VM_METHOD_NODE:{
	rb_control_frame_t *reg_cfp;
	int i;
	const int flag = 0;

	th_set_finish_env(th);
	reg_cfp = th->cfp;
	for (i = 0; i < argc; i++) {
	    *reg_cfp->sp++ = argv[i];
	}
	macro_eval_invoke_func(body->nd_body, recv, klass, blockptr,
			       argc);
	val = th_eval_body(th);
	break;
      }
      case NODE_CFUNC: {
	EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, id, klass);
	{
	    rb_control_frame_t *reg_cfp = th->cfp;
	    rb_control_frame_t *cfp =
		push_frame(th, 0, FRAME_MAGIC_CFUNC,
			   recv, (VALUE)blockptr, 0, reg_cfp->sp, 0, 1);

	    cfp->method_id = id;
	    cfp->method_klass = klass;

	    val = call_cfunc(body->nd_cfnc, recv, body->nd_argc, argc, argv);

	    if (reg_cfp != th->cfp + 1) {
		SDR2(reg_cfp);
		SDR2(th->cfp-5);
		rb_bug("cfp consistency error - call0");
		th->cfp = reg_cfp;
	    }
	    pop_frame(th);
	}
	EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, id, klass);
	break;
      }
      case NODE_ATTRSET:{
	if (argc != 1) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)",
		     argc);
	}
	val = rb_ivar_set(recv, body->nd_vid, argv[0]);
	break;
      }
      case NODE_IVAR: {
	if (argc != 0) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)",
		     argc);
	}
	val = rb_attr_get(recv, body->nd_vid);
	break;
      }
      case NODE_BMETHOD:{
	val = th_invoke_bmethod(th, id, body->nd_cval,
				recv, klass, argc, (VALUE *)argv);
	break;
      }
      default:
	rb_bug("unsupported: th_call0");
    }
    RUBY_VM_CHECK_INTS();
    return val;
}

static VALUE
search_super_klass(VALUE klass, VALUE recv)
{
    if (BUILTIN_TYPE(klass) == T_CLASS) {
	klass = RCLASS(klass)->super;
    }
    else if (BUILTIN_TYPE(klass) == T_MODULE) {
	VALUE k = CLASS_OF(recv);
	while (k) {
	    if (BUILTIN_TYPE(k) == T_ICLASS && RBASIC(k)->klass == klass) {
		klass = RCLASS(k)->super;
		break;
	    }
	    k = RCLASS(k)->super;
	}
    }
    return klass;
}

static VALUE
th_call_super(rb_thread_t *th, int argc, const VALUE *argv)
{
    VALUE recv = th->cfp->self;
    VALUE klass;
    ID id;
    NODE *body;
    int nosuper = 0;
    rb_control_frame_t *cfp = th->cfp;

    if (!th->cfp->iseq) {
	klass = cfp->method_klass;
	klass = RCLASS(klass)->super;

	if (klass == 0) {
	    klass = search_super_klass(cfp->method_klass, recv);
	}

	id = cfp->method_id;
    }
    else {
	rb_bug("th_call_super: should not be reached");
    }

    body = rb_method_node(klass, id);	/* this returns NODE_METHOD */

    if (body) {
	body = body->nd_body;
    }
    else {
	dp(recv);
	dp(klass);
	dpi(id);
	rb_bug("th_call_super: not found");
    }

    return th_call0(th, klass, recv, id, id, argc, argv, body, nosuper);
}

VALUE
rb_call_super(int argc, const VALUE *argv)
{
    return th_call_super(GET_THREAD(), argc, argv);
}

static inline VALUE
th_yield_with_cfunc(rb_thread_t *th, rb_block_t *block,
		    VALUE self, int argc, VALUE *argv)
{
    NODE *ifunc = (NODE *) block->iseq;
    VALUE val;
    VALUE arg;

    if (argc == 1) {
	arg = *argv;
    }
    else if (argc > 1) {
	arg = rb_ary_new4(argc, argv);
    }
    else {
	arg = rb_ary_new();
    }

    push_frame(th, 0, FRAME_MAGIC_IFUNC,
	       self, (VALUE)block->dfp,
	       0, th->cfp->sp, block->lfp, 1);

    val = (*ifunc->nd_cfnc) (arg, ifunc->nd_tval, Qnil);

    th->cfp++;
    return val;
}

static inline int
th_yield_setup_args(rb_thread_t *th, rb_iseq_t *iseq,
		    int argc, VALUE *argv, int lambda)
{
    int i, arg_n = iseq->argc + (iseq->arg_rest == -1 ? 0 : 1);
    th->mark_stack_len = argc;

    if (0) { /* for debug */
	int i;
	GET_THREAD()->cfp->sp += argc;
	for(i=0; i<argc; i++){
	    dp(argv[i]);
	}

	printf("     argc: %d\n", argc);
	printf("iseq argc: %d\n", iseq->argc);
	printf("iseq rest: %d\n", iseq->arg_rest);
	printf("iseq blck: %d\n", iseq->arg_block);
	printf("   lambda: %s\n", lambda ? "true" : "false");
	GET_THREAD()->cfp->sp -= argc;
    }

    if (lambda == 0 && argc == 1 && TYPE(argv[0]) == T_ARRAY && arg_n != 1) {
	VALUE ary = argv[0];
	th->mark_stack_len = argc = RARRAY_LEN(ary);

	/* TODO: check overflow */

	for (i=0; i<argc; i++) {
	    argv[i] = RARRAY_PTR(ary)[i];
	}
    }

    if (iseq->arg_rest == -1) {

	if (iseq->argc < argc) {
	    if (lambda) {
		rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
			 argc, iseq->argc);
	    }
	    else {
		/* simple truncate */
		th->mark_stack_len = argc = iseq->argc;
	    }
	}
	else if (iseq->argc > argc) {
	    if (lambda) {
		rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
			 argc, iseq->argc);
	    }
	}
    }
    else {
	int r = iseq->arg_rest;

	if (argc < r) {
	    if (lambda) {
		rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
			 argc, iseq->argc);
	    }
	    else {
		/* TODO: check overflow */
		for (i=argc; i<r; i++) {
		    argv[i] = Qnil;
		}
		argv[r] = rb_ary_new();
	    }
	}
	else {
	    argv[r] = rb_ary_new4(argc-r, &argv[r]);
	}
	th->mark_stack_len = argc = iseq->arg_rest + 1;
    }

    if (iseq->arg_block != -1) {
	VALUE proc = Qnil;

	if (rb_block_given_p()) {
	    proc = rb_block_proc();
	}

	argv[iseq->arg_block] = proc;
	th->mark_stack_len = argc = iseq->arg_block + 1;
    }

    th->mark_stack_len = 0;
    return argc;
}

static VALUE
invoke_block(rb_thread_t *th, rb_block_t *block, VALUE self, int argc, VALUE *argv)
{
    VALUE val;
    if (BUILTIN_TYPE(block->iseq) != T_NODE) {
	rb_iseq_t *iseq = block->iseq;
	int i;
	int magic = block_proc_is_lambda(block->proc) ?
	  FRAME_MAGIC_LAMBDA : FRAME_MAGIC_BLOCK;

	th_set_finish_env(th);

	/* TODO: check overflow */

	for (i=0; i<argc; i++) {
	    th->cfp->sp[i] = argv[i];
	}

	argc = th_yield_setup_args(th, iseq, argc, th->cfp->sp, magic == FRAME_MAGIC_LAMBDA);
	th->cfp->sp += argc;

	push_frame(th, iseq, magic,
		   self, GC_GUARDED_PTR(block->dfp),
		   iseq->iseq_encoded, th->cfp->sp, block->lfp,
		   iseq->local_size - argc);
	val = th_eval_body(th);
    }
    else {
	if (((NODE*)block->iseq)->u3.state == 1) {
	    VALUE args = rb_ary_new4(argc, argv);
	    argc = 1;
	    argv = &args;
	}
	val = th_yield_with_cfunc(th, block, block->self, argc, argv);
    }
    return val;
}

VALUE
th_yield(rb_thread_t *th, int argc, VALUE *argv)
{
    rb_block_t *block = GC_GUARDED_PTR_REF(th->cfp->lfp[0]);

    if (block == 0) {
	th_localjump_error("no block given", Qnil, 0);
    }

    return invoke_block(th, block, block->self, argc, argv);
}

VALUE
th_invoke_proc(rb_thread_t *th, rb_proc_t *proc,
	       VALUE self, int argc, VALUE *argv)
{
    VALUE val = Qundef;
    int state;
    volatile int stored_safe = th->safe_level;
    volatile NODE *stored_special_cref_stack =
      lfp_set_special_cref(proc->block.lfp, proc->special_cref_stack);
    rb_control_frame_t * volatile cfp = th->cfp;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	th->safe_level = proc->safe_level;

	val = invoke_block(th, &proc->block, self, argc, argv);
    }
    else {
	if (state == TAG_BREAK ||
	    (state == TAG_RETURN && proc->is_lambda)) {
	    VALUE err = th->errinfo;
	    VALUE *escape_dfp = GET_THROWOBJ_CATCH_POINT(err);
	    VALUE *cdfp = proc->block.dfp;

	    if (escape_dfp == cdfp) {
		state = 0;
		th->errinfo = Qnil;
		th->cfp = cfp;
		val = GET_THROWOBJ_VAL(err);
	    }
	}
    }
    TH_POP_TAG();

    th->safe_level = stored_safe;
    lfp_set_special_cref(proc->block.lfp, (NODE*)stored_special_cref_stack);

    if (state) {
	JUMP_TAG(state);
    }
    return val;
}

static struct RValues *
new_value(void)
{
    struct RValues *val = RVALUES(rb_newobj());
    OBJSETUP(val, 0, T_VALUES);
    val->v1 = val->v2 = val->v3 = Qnil;
    return val;
}

static VALUE *
lfp_svar(VALUE *lfp, int cnt)
{
    struct RValues *val;
    rb_thread_t *th = GET_THREAD();

    if (th->local_lfp != lfp) {
	val = (struct RValues *)lfp[-1];
	if ((VALUE)val == Qnil) {
	    val = new_value();
	    lfp[-1] = (VALUE)val;
	}
    }
    else {
	val = (struct RValues *)th->local_svar;
	if ((VALUE)val == Qnil) {
	    val = new_value();
	    th->local_svar = (VALUE)val;
	}
    }
    switch (cnt) {
      case -1:
	return &val->basic.klass;
      case 0:
	return &val->v1;
      case 1:
	return &val->v2;
      default:{
	VALUE ary;
	if ((ary = val->v3) == Qnil) {
	    ary = val->v3 = rb_ary_new();
	}
	if (RARRAY_LEN(ary) <= cnt) {
	    rb_ary_store(ary, cnt, Qnil);
	}
	return &RARRAY_PTR(ary)[cnt];
      }
    }
}


VALUE *
th_cfp_svar(rb_control_frame_t *cfp, int cnt)
{
    while (cfp->pc == 0) {
	cfp++;
    }
    return lfp_svar(cfp->lfp, cnt);
}

static VALUE *
th_svar(rb_thread_t *th, int cnt)
{
    rb_control_frame_t *cfp = th->cfp;
    return th_cfp_svar(cfp, cnt);
}

VALUE *
rb_svar(int cnt)
{
    return th_svar(GET_THREAD(), cnt);
}

VALUE
rb_backref_get(void)
{
    VALUE *var = rb_svar(1);
    if (var) {
	return *var;
    }
    return Qnil;
}

void
rb_backref_set(VALUE val)
{
    VALUE *var = rb_svar(1);
    *var = val;
}

VALUE
rb_lastline_get(void)
{
    VALUE *var = rb_svar(0);
    if (var) {
	return *var;
    }
    return Qnil;
}

void
rb_lastline_set(VALUE val)
{
    VALUE *var = rb_svar(0);
    *var = val;
}

int
th_get_sourceline(rb_control_frame_t *cfp)
{
    int line_no = 0;
    rb_iseq_t *iseq = cfp->iseq;

    if (RUBY_VM_NORMAL_ISEQ_P(iseq)) {
	int i;
	int pos = cfp->pc - cfp->iseq->iseq_encoded;

	for (i = 0; i < iseq->insn_info_size; i++) {
	    if (iseq->insn_info_tbl[i].position == pos) {
		line_no = iseq->insn_info_tbl[i - 1].line_no;
		goto found;
	    }
	}
	line_no = iseq->insn_info_tbl[i - 1].line_no;
    }
  found:
    return line_no;
}

static VALUE
th_backtrace_each(rb_thread_t *th,
		  rb_control_frame_t *limit_cfp,
		  rb_control_frame_t *cfp,
		  char *file, int line_no, VALUE ary)
{
    VALUE str;

    while (cfp > limit_cfp) {
	str = 0;
	if (cfp->iseq != 0) {
	    if (cfp->pc != 0) {
		rb_iseq_t *iseq = cfp->iseq;

		line_no = th_get_sourceline(cfp);
		file = RSTRING_PTR(iseq->filename);
		str = rb_sprintf("%s:%d:in `%s'",
				 file, line_no, RSTRING_PTR(iseq->name));
		rb_ary_push(ary, str);
	    }
	}
	else if (RUBYVM_CFUNC_FRAME_P(cfp)) {
	    str = rb_sprintf("%s:%d:in `%s'",
			     file, line_no,
			     rb_id2name(cfp->method_id));
	    rb_ary_push(ary, str);
	}
	cfp = RUBY_VM_NEXT_CONTROL_FRAME(cfp);
    }
    return rb_ary_reverse(ary);
}

VALUE
th_backtrace(rb_thread_t *th, int lev)
{
    VALUE ary;
    rb_control_frame_t *cfp = th->cfp;
    rb_control_frame_t *top_of_cfp = (void *)(th->stack + th->stack_size);
    top_of_cfp -= 2;

    if (lev < 0) {
	/* TODO ?? */
	ary = rb_ary_new();
    }
    else {
	while (lev-- >= 0) {
	    cfp++;
	    if (cfp >= top_of_cfp) {
		return Qnil;
	    }
	}
	ary = rb_ary_new();
    }

    ary = th_backtrace_each(th, RUBY_VM_NEXT_CONTROL_FRAME(cfp),
			    top_of_cfp, "", 0, ary);
    return ary;
}

VALUE
thread_backtrace(VALUE self, int level)
{
    rb_thread_t *th;
    GetThreadPtr(self, th);
    return th_backtrace(th, level);
}

/*
 * vm main loop helper functions
 */


static NODE *
lfp_get_special_cref(VALUE *lfp)
{
    struct RValues *values;
    if (((VALUE)(values = (void *)lfp[-1])) != Qnil && values->basic.klass) {
	return (NODE *)values->basic.klass;
    }
    else {
	return 0;
    }
}

static void
check_svar(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp;
    while ((void *)(cfp + 1) < (void *)(th->stack + th->stack_size)) {
	/* printf("cfp: %p\n", cfp->magic); */
	if (cfp->lfp && cfp->lfp[-1] != Qnil &&
	    TYPE(cfp->lfp[-1]) != T_VALUES) {
	    /* dp(cfp->lfp[-1]); */
	    rb_bug("!!!illegal svar!!!");
	}
	cfp++;
    }
}

static NODE *
lfp_set_special_cref(VALUE *lfp, NODE * cref)
{
    struct RValues *values = (void *) lfp[-1];
    VALUE *pv;
    NODE *old_cref;

    if (VM_DEBUG) {
	check_svar();
    }

    if (cref == 0 && ((VALUE)values == Qnil || values->basic.klass == 0)) {
	old_cref = 0;
    }
    else {
	pv = lfp_svar(lfp, -1);
	old_cref = (NODE *) * pv;
	*pv = (VALUE)cref;
    }
    return old_cref;
}

NODE *
th_set_special_cref(rb_thread_t *th, VALUE *lfp, NODE * cref_stack)
{
    return lfp_set_special_cref(lfp, cref_stack);
}

void
debug_cref(NODE *cref)
{
    while (cref) {
	dp(cref->nd_clss);
	printf("%ld\n", cref->nd_visi);
	cref = cref->nd_next;
    }
}

static NODE *
get_cref(rb_iseq_t *iseq, VALUE *lfp)
{
    NODE *cref;
    if ((cref = lfp_get_special_cref(lfp)) != 0) {
	/* */
    }
    else if ((cref = iseq->cref_stack) != 0) {
	/* */
    }
    else {
	rb_bug("get_cref: unreachable");
    }
    return cref;
}

NODE *
th_get_cref(rb_thread_t *th, rb_iseq_t *iseq, rb_control_frame_t *cfp)
{
    return get_cref(iseq, cfp->lfp);
}

NODE *
th_cref_push(rb_thread_t *th, VALUE klass, int noex)
{
    NODE *cref = NEW_BLOCK(klass);
    rb_control_frame_t *cfp = th_get_ruby_level_cfp(th, th->cfp);

    cref->nd_file = 0;
    cref->nd_next = get_cref(cfp->iseq, cfp->lfp);
    cref->nd_visi = noex;
    return cref;
}

VALUE
th_get_cbase(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th_get_ruby_level_cfp(th, th->cfp);
    NODE *cref = get_cref(cfp->iseq, cfp->lfp);
    VALUE klass = Qundef;

    while (cref) {
	if ((klass = cref->nd_clss) != 0) {
	    break;
	}
	cref = cref->nd_next;
    }
    return klass;
}

EVALBODY_HELPER_FUNCTION VALUE
eval_get_ev_const(rb_thread_t *th, rb_iseq_t *iseq,
		  VALUE klass, ID id, int is_defined)
{
    VALUE val;

    if (klass == Qnil) {
	/* in current lexical scope */
	NODE *root_cref = get_cref(iseq, th->cfp->lfp);
	NODE *cref = root_cref;

	while (cref && cref->nd_next) {
	    klass = cref->nd_clss;
	    cref = cref->nd_next;

	    if (klass == 0) {
		continue;
	    }
	    if (NIL_P(klass)) {
		if (is_defined) {
		    /* TODO: check */
		    return 1;
		}
		else {
		    klass = CLASS_OF(th->cfp->self);
		    return rb_const_get(klass, id);
		}
	    }
	  search_continue:
	    if (RCLASS(klass)->iv_tbl &&
		st_lookup(RCLASS(klass)->iv_tbl, id, &val)) {
		if (val == Qundef) {
		    rb_autoload_load(klass, id);
		    goto search_continue;
		}
		else {
		    if (is_defined) {
			return 1;
		    }
		    else {
			return val;
		    }
		}
	    }
	}
	klass = root_cref->nd_clss;
	if (is_defined) {
	    return rb_const_defined(klass, id);
	}
	else {
	    return rb_const_get(klass, id);
	}
    }
    else {
	switch (TYPE(klass)) {
	  case T_CLASS:
	  case T_MODULE:
	    break;
	  default:
	    rb_raise(rb_eTypeError, "%s is not a class/module",
		     RSTRING_PTR(rb_obj_as_string(klass)));
	}
	if (is_defined) {
	    return rb_const_defined(klass, id);
	}
	else {
	    return rb_const_get(klass, id);
	}
    }
}

EVALBODY_HELPER_FUNCTION VALUE
eval_get_cvar_base(rb_thread_t *th, rb_iseq_t *iseq)
{
    NODE *cref = get_cref(iseq, th->cfp->lfp);
    VALUE klass = Qnil;

    if (cref) {
	klass = cref->nd_clss;
	if (!cref->nd_next) {
	    rb_warn("class variable access from toplevel");
	}
    }
    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class variables available");
    }
    return klass;
}

EVALBODY_HELPER_FUNCTION void
eval_define_method(rb_thread_t *th, VALUE obj,
		   ID id, rb_iseq_t *miseq, rb_num_t is_singleton, NODE *cref)
{
    NODE *newbody;
    int noex = cref->nd_visi;
    VALUE klass = cref->nd_clss;

    if (is_singleton) {
	if (FIXNUM_P(obj) || SYMBOL_P(obj)) {
	    rb_raise(rb_eTypeError,
		     "can't define singleton method \"%s\" for %s",
		     rb_id2name(id), rb_obj_classname(obj));
	}

	if (OBJ_FROZEN(obj)) {
	    rb_error_frozen("object");
	}

	klass = rb_singleton_class(obj);
	noex = NOEX_PUBLIC;
    }

    /* dup */
    COPY_CREF(miseq->cref_stack, cref);
    miseq->klass = klass;
    miseq->defined_method_id = id;
    newbody = NEW_NODE(RUBY_VM_METHOD_NODE, 0, miseq->self, 0);
    rb_add_method(klass, id, newbody, noex);

    if (!is_singleton && noex == NOEX_MODFUNC) {
	rb_add_method(rb_singleton_class(klass), id, newbody, NOEX_PUBLIC);
    }
    INC_VM_STATE_VERSION();
}

EVALBODY_HELPER_FUNCTION VALUE
eval_method_missing(rb_thread_t *th, ID id, VALUE recv, int num,
		    rb_block_t *blockptr, int opt)
{
    rb_control_frame_t *reg_cfp = th->cfp;
    VALUE *argv = STACK_ADDR_FROM_TOP(num + 1);
    VALUE val;
    argv[0] = ID2SYM(id);
    th->method_missing_reason = opt;
    th->passed_block = blockptr;
    val = rb_funcall2(recv, idMethodMissing, num + 1, argv);
    POPN(num + 1);
    return val;
}

EVALBODY_HELPER_FUNCTION NODE *
eval_method_search(VALUE id, VALUE klass, IC ic)
{
    NODE *mn;

#if OPT_INLINE_METHOD_CACHE
    {
	if (LIKELY(klass == ic->ic_klass) &&
	    LIKELY(GET_VM_STATE_VERSION() == ic->ic_vmstat)) {
	    mn = ic->ic_method;
	}
	else {
	    mn = rb_method_node(klass, id);
	    ic->ic_klass = klass;
	    ic->ic_method = mn;
	    ic->ic_vmstat = GET_VM_STATE_VERSION();
	}
    }
#else
    mn = rb_method_node(klass, id);
#endif
    return mn;
}

static void
call_yarv_end_proc(VALUE data)
{
    rb_proc_call(data, rb_ary_new2(0));
}

static inline int
block_proc_is_lambda(VALUE procval)
{
    rb_proc_t *proc;

    if (procval) {
	GetProcPtr(procval, proc);
	return proc->is_lambda;
    }
    else {
	return 0;
    }
}


/*********************************************************/
/*********************************************************/

static VALUE
make_localjump_error(const char *mesg, VALUE value, int reason)
{
    VALUE exc =
	rb_exc_new2(rb_const_get(rb_cObject, rb_intern("LocalJumpError")),
		    mesg);
    ID id;

    switch (reason) {
      case TAG_BREAK:
	id = rb_intern("break");
	break;
      case TAG_REDO:
	id = rb_intern("redo");
	break;
      case TAG_RETRY:
	id = rb_intern("retry");
	break;
      case TAG_NEXT:
	id = rb_intern("next");
	break;
      case TAG_RETURN:
	id = rb_intern("return");
	break;
      default:
	id = rb_intern("noreason");
	break;
    }
    rb_iv_set(exc, "@exit_value", value);
    rb_iv_set(exc, "@reason", ID2SYM(id));
    return exc;
}

void
th_localjump_error(const char *mesg, VALUE value, int reason)
{
    VALUE exc = make_localjump_error(mesg, value, reason);
    rb_exc_raise(exc);
}

VALUE
th_make_jump_tag_but_local_jump(int state, VALUE val)
{
    VALUE result = Qnil;

    if (val == Qundef)
	val = GET_THREAD()->tag->retval;
    switch (state) {
      case 0:
	break;
      case TAG_RETURN:
	result = make_localjump_error("unexpected return", val, state);
	break;
      case TAG_BREAK:
	result = make_localjump_error("unexpected break", val, state);
	break;
      case TAG_NEXT:
	result = make_localjump_error("unexpected next", val, state);
	break;
      case TAG_REDO:
	result = make_localjump_error("unexpected redo", Qnil, state);
	break;
      case TAG_RETRY:
	result = make_localjump_error("retry outside of rescue clause", Qnil, state);
	break;
      default:
	break;
    }
    return result;
}

void
th_jump_tag_but_local_jump(int state, VALUE val)
{
    VALUE exc = th_make_jump_tag_but_local_jump(state, val);
    if (val != Qnil) {
	rb_exc_raise(exc);
    }
    JUMP_TAG(state);
}

void
th_iter_break(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    VALUE *dfp = GC_GUARDED_PTR_REF(*cfp->dfp);

    th->state = TAG_BREAK;
    th->errinfo = (VALUE)NEW_THROW_OBJECT(Qnil, (VALUE)dfp, TAG_BREAK);
    TH_JUMP_TAG(th, TAG_BREAK);
}

static VALUE yarv_redefined_flag = 0;
static st_table *vm_opt_method_table = 0;

void
rb_vm_check_redefinition_opt_method(NODE *node)
{
    VALUE bop;

    if (st_lookup(vm_opt_method_table, (st_data_t)node, &bop)) {
	yarv_redefined_flag |= bop;
    }
}

static void
add_opt_method(VALUE klass, ID mid, VALUE bop)
{
    NODE *node;
    if (st_lookup(RCLASS(klass)->m_tbl, mid, (void *)&node) &&
	nd_type(node->nd_body->nd_body) == NODE_CFUNC) {
	st_insert(vm_opt_method_table, (st_data_t)node, (st_data_t)bop);
    }
    else {
	rb_bug("undefined optimized method: %s", rb_id2name(mid));
    }
}

void
yarv_init_redefined_flag(void)
{
    VALUE register_info[] = {
	idPLUS, BOP_PLUS, rb_cFixnum, rb_cFloat, rb_cString, rb_cArray, 0,
	idMINUS, BOP_MINUS, rb_cFixnum, 0,
	idMULT, BOP_MULT, rb_cFixnum, rb_cFloat, 0,
	idDIV, BOP_DIV, rb_cFixnum, rb_cFloat, 0,
	idMOD, BOP_MOD, rb_cFixnum, rb_cFloat, 0,
	idEq, BOP_EQ, rb_cFixnum, rb_cFloat, rb_cString, 0,
	idLT, BOP_LT, rb_cFixnum, 0,
	idLE, BOP_LE, rb_cFixnum, 0,
	idLTLT, BOP_LTLT, rb_cString, rb_cArray, 0,
	idAREF, BOP_AREF, rb_cArray, rb_cHash, 0,
	idASET, BOP_ASET, rb_cArray, rb_cHash, 0,
	idLength, BOP_LENGTH, rb_cArray, rb_cString, rb_cHash, 0,
	idSucc, BOP_SUCC, rb_cFixnum, rb_cString, rb_cTime, 0,
	idGT, BOP_GT, rb_cFixnum, 0,
	idGE, BOP_GE, rb_cFixnum, 0,
	0,
    };
    VALUE *ptr = register_info;
    vm_opt_method_table = st_init_numtable();

    while (*ptr) {
	ID mid = *ptr++;
	VALUE bop = *ptr++;
	while(*ptr) {
	    VALUE klass = *ptr++;
	    add_opt_method(klass, mid, bop);
	}
	ptr++;
    }
}



#include "vm_evalbody.ci"

/*                  finish
  VMe (h1)          finish
    VM              finish F1 F2
      func          finish F1 F2 C1
        rb_funcall  finish F1 F2 C1
          VMe       finish F1 F2 C1
            VM      finish F1 F2 C1 F3

  F1 - F3 : pushed by VM
  C1      : pushed by send insn (CFUNC)

  struct CONTROL_FRAME {
    VALUE *pc;                  // cfp[0]
    VALUE *sp;                  // cfp[1]
    VALUE *bp;                  // cfp[2]
    rb_iseq_t *iseq;          // cfp[3]
    VALUE magic;                // cfp[4]
    VALUE self;                 // cfp[5]
    VALUE *lfp;                 // cfp[6]
    VALUE *dfp;                 // cfp[7]
    rb_iseq_t * block_iseq;   // cfp[8]
    VALUE proc;                 // cfp[9] always 0
  };

  struct BLOCK {
    VALUE self;
    VALUE *lfp;
    VALUE *dfp;
    rb_iseq_t *block_iseq;
  };

  struct PROC {
    VALUE  proc_sig = 0;
    struct BLOCK;
  };

  struct METHOD_CONTROL_FRAME {
    struct CONTROL_FRAME;
  };

  struct METHOD_FRAME {
    VALUE arg0;
    ...
    VALUE argM;
    VALUE param0;
    ...
    VALUE paramN;
    VALUE special;                         // lfp [1]
    struct block_object *block_ptr | 0x01; // lfp [0]
  };

  struct BLOCK_CONTROL_FRAME {
    struct STACK_FRAME;
  };

  struct BLOCK_FRAME {
    VALUE arg0;
    ...
    VALUE argM;
    VALUE param0;
    ...
    VALUE paramN;
    VALUE *(prev_ptr | 0x01); // DFP[0]
  };

  struct CLASS_CONTROL_FRAME {
    struct STACK_FRAME;
  };

  struct CLASS_FRAME {
    VALUE param0;
    ...
    VALUE paramN;
    VALUE prev_dfp; // for frame jump
  };

  struct C_METHOD_CONTROL_FRAME {
    VALUE *pc;                       // 0
    VALUE *sp;                       // stack pointer
    VALUE *bp;                       // base pointer (used in exception)
    rb_iseq_t *iseq;               // cmi
    VALUE magic;                     // C_METHOD_FRAME
    VALUE self;                      // ?
    VALUE *lfp;                      // lfp
    VALUE *dfp;                      // == lfp
    rb_iseq_t * block_iseq;        //
    VALUE proc;                      // always 0
  };

  struct C_BLOCK_CONTROL_FRAME {
    VALUE *pc;                       // point only "finish" insn
    VALUE *sp;                       // sp
    rb_iseq_t *iseq;               // ?
    VALUE magic;                     // C_METHOD_FRAME
    VALUE self;                      // needed?
    VALUE *lfp;                      // lfp
    VALUE *dfp;                      // lfp
    rb_iseq_t * block_iseq; // 0
  };

  struct C_METHDO_FRAME{
    VALUE block_ptr;
    VALUE special;
  };
 */


VALUE
th_eval_body(rb_thread_t *th)
{
    int state;
    VALUE result, err;
    VALUE initial = 0;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
      vm_loop_start:
	result = th_eval(th, initial);
	if ((state = th->state) != 0) {
	    err = result;
	    th->state = 0;
	    goto exception_handler;
	}
    }
    else {
	int i;
	struct catch_table_entry *entry;
	unsigned long epc, cont_pc, cont_sp;
	VALUE catch_iseqval;
	rb_control_frame_t *cfp;
	VALUE *escape_dfp = NULL;
	VALUE type;

	err = th->errinfo;

	if (state == TAG_RAISE) {
	    rb_ivar_set(err, idThrowState, INT2FIX(state));
	}

      exception_handler:
	cont_pc = cont_sp = catch_iseqval = 0;

	while (th->cfp->pc == 0 || th->cfp->iseq == 0) {
	    th->cfp++;
	}

	cfp = th->cfp;
	epc = cfp->pc - cfp->iseq->iseq_encoded;

	if (state == TAG_BREAK || state == TAG_RETURN) {
	    escape_dfp = GET_THROWOBJ_CATCH_POINT(err);

	    if (cfp->dfp == escape_dfp) {
		if (state == TAG_RETURN) {
		    if ((cfp + 1)->pc != &yarv_finish_insn_seq[0]) {
			SET_THROWOBJ_CATCH_POINT(err, (VALUE)(cfp + 1)->dfp);
			SET_THROWOBJ_STATE(err, state = TAG_BREAK);
		    }
		    else {
			result = GET_THROWOBJ_VAL(err);
			th->errinfo = Qnil;
			th->cfp += 2;
			goto finish_vme;
		    }
		    /* through */
		}
		else {
		    /* TAG_BREAK */
#if OPT_STACK_CACHING
		    initial = (GET_THROWOBJ_VAL(err));
#else
		    *th->cfp->sp++ = (GET_THROWOBJ_VAL(err));
#endif
		    th->errinfo = Qnil;
		    goto vm_loop_start;
		}
	    }
	}

	if (state == TAG_RAISE) {
	    for (i = 0; i < cfp->iseq->catch_table_size; i++) {
		entry = &cfp->iseq->catch_table[i];
		if (entry->start < epc && entry->end >= epc) {

		    if (entry->type == CATCH_TYPE_RESCUE ||
			entry->type == CATCH_TYPE_ENSURE) {
			catch_iseqval = entry->iseq;
			cont_pc = entry->cont;
			cont_sp = entry->sp;
			break;
		    }
		}
	    }
	}
	else if (state == TAG_RETRY) {
	    for (i = 0; i < cfp->iseq->catch_table_size; i++) {
		entry = &cfp->iseq->catch_table[i];
		if (entry->start < epc && entry->end >= epc) {

		    if (entry->type == CATCH_TYPE_ENSURE) {
			catch_iseqval = entry->iseq;
			cont_pc = entry->cont;
			cont_sp = entry->sp;
			break;
		    }
		    else if (entry->type == CATCH_TYPE_RETRY) {
			VALUE *escape_dfp;
			escape_dfp = GET_THROWOBJ_CATCH_POINT(err);
			if (cfp->dfp == escape_dfp) {
			    cfp->pc = cfp->iseq->iseq_encoded + entry->cont;
			    th->errinfo = Qnil;
			    goto vm_loop_start;
			}
		    }
		}
	    }
	}
	else if (state == TAG_BREAK && ((VALUE)escape_dfp & ~0x03) == 0) {
	    type = CATCH_TYPE_BREAK;

	  search_restart_point:
	    for (i = 0; i < cfp->iseq->catch_table_size; i++) {
		entry = &cfp->iseq->catch_table[i];

		if (entry->start < epc && entry->end >= epc) {
		    if (entry->type == CATCH_TYPE_ENSURE) {
			catch_iseqval = entry->iseq;
			cont_pc = entry->cont;
			cont_sp = entry->sp;
			break;
		    }
		    else if (entry->type == type) {
			cfp->pc = cfp->iseq->iseq_encoded + entry->cont;
			cfp->sp = cfp->bp + entry->sp;

			if (!(state == TAG_REDO) &&
			    !(state == TAG_NEXT && !escape_dfp) &&
			    !(state == TAG_BREAK && !escape_dfp)) {
#if OPT_STACK_CACHING
			    initial = (GET_THROWOBJ_VAL(err));
#else
			    *th->cfp->sp++ = (GET_THROWOBJ_VAL(err));
#endif
			}
			th->errinfo = Qnil;
			goto vm_loop_start;
		    }
		}
	    }
	}
	else if (state == TAG_REDO) {
	    type = CATCH_TYPE_REDO;
	    escape_dfp = GET_THROWOBJ_CATCH_POINT(err);
	    goto search_restart_point;
	}
	else if (state == TAG_NEXT) {
	    type = CATCH_TYPE_NEXT;
	    escape_dfp = GET_THROWOBJ_CATCH_POINT(err);
	    goto search_restart_point;
	}
	else {
	    for (i = 0; i < cfp->iseq->catch_table_size; i++) {
		entry = &cfp->iseq->catch_table[i];
		if (entry->start < epc && entry->end >= epc) {

		    if (entry->type == CATCH_TYPE_ENSURE) {
			catch_iseqval = entry->iseq;
			cont_pc = entry->cont;
			cont_sp = entry->sp;
			break;
		    }
		}
	    }
	}

	if (catch_iseqval != 0) {
	    /* found catch table */
	    rb_iseq_t *catch_iseq;

	    /* enter catch scope */
	    GetISeqPtr(catch_iseqval, catch_iseq);
	    cfp->sp = cfp->bp + cont_sp;
	    cfp->pc = cfp->iseq->iseq_encoded + cont_pc;

	    /* push block frame */
	    cfp->sp[0] = err;
	    push_frame(th, catch_iseq, FRAME_MAGIC_BLOCK,
		       cfp->self, (VALUE)cfp->dfp, catch_iseq->iseq_encoded,
		       cfp->sp + 1, cfp->lfp, catch_iseq->local_size - 1);

	    state = 0;
	    th->errinfo = Qnil;
	    goto vm_loop_start;
	}
	else {
	    th->cfp++;
	    if (th->cfp->pc != &yarv_finish_insn_seq[0]) {
		goto exception_handler;
	    }
	    else {
		pop_frame(th);
		th->errinfo = err;
		TH_POP_TAG2();
		JUMP_TAG(state);
	    }
	}
    }
  finish_vme:
    TH_POP_TAG();
    return result;
}

VALUE
rb_thread_eval(rb_thread_t *th, VALUE iseqval)
{
    VALUE val;
    volatile VALUE tmp;

    th_set_top_stack(th, iseqval);

    if (!rb_const_defined(rb_cObject, rb_intern("TOPLEVEL_BINDING"))) {
	rb_define_global_const("TOPLEVEL_BINDING", rb_binding_new());
    }
    val = th_eval_body(th);
    tmp = iseqval; /* prohibit tail call optimization */
    return val;
}

int
rb_thread_method_id_and_klass(rb_thread_t *th, ID *idp, VALUE *klassp)
{
    rb_control_frame_t *cfp = th->cfp;

    if (cfp->iseq) {
	if (cfp->pc != 0) {
	    rb_iseq_t *iseq = cfp->iseq->local_iseq;
	    if (idp) *idp = rb_intern(RSTRING_PTR(iseq->name));
	    if (klassp) *klassp = iseq->klass;
	    return 1;
	}
    }
    else {
	if (idp) *idp = cfp->method_id;
	if (klassp) *klassp = cfp->method_klass;
	return 1;
    }
    *idp = *klassp = 0;
    return 0;
}

VALUE
rb_thread_current_status(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    VALUE str = Qnil;

    if (cfp->iseq != 0) {
	if (cfp->pc != 0) {
	    rb_iseq_t *iseq = cfp->iseq;
	    int line_no = th_get_sourceline(cfp);
	    char *file = RSTRING_PTR(iseq->filename);
	    str = rb_sprintf("%s:%d:in `%s'",
			     file, line_no, RSTRING_PTR(iseq->name));
	}
    }
    else if (cfp->method_id) {
	str = rb_sprintf("`%s#%s' (cfunc)",
			 RSTRING_PTR(rb_class_name(cfp->method_klass)),
			 rb_id2name(cfp->method_id));
    }

    return str;
}

VALUE
rb_vm_call_cfunc(VALUE recv, VALUE (*func)(VALUE), VALUE arg, rb_block_t *blockptr, VALUE filename)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *reg_cfp = th->cfp;
    volatile VALUE iseq = rb_iseq_new(0, filename, filename, 0, ISEQ_TYPE_TOP);
    VALUE val;

    push_frame(th, DATA_PTR(iseq), FRAME_MAGIC_TOP,
	       recv, (VALUE)blockptr, 0, reg_cfp->sp, 0, 1);
    val = (*func)(arg);
    pop_frame(th);
    return val;
}
