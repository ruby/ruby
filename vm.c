/**********************************************************************

  vm.c -

  $Author$
  $Date$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/node.h"
#include "ruby/st.h"
#include "gc.h"
#include "eval_intern.h"

#include "insnhelper.h"
#include "insnhelper.ci"

#define BUFSIZE 0x100
#define PROCDEBUG 0

VALUE rb_cVM;
VALUE rb_cThread;
VALUE rb_cEnv;

VALUE ruby_vm_global_state_version = 1;
rb_thread_t *ruby_current_thread = 0;
rb_vm_t *ruby_current_vm = 0;

void vm_analysis_operand(int insn, int n, VALUE op);
void vm_analysis_register(int reg, int isset);
void vm_analysis_insn(int insn);

static NODE *lfp_set_special_cref(VALUE *lfp, NODE * cref);

#if OPT_STACK_CACHING
static VALUE finish_insn_seq[1] = { BIN(finish_SC_ax_ax) };
#elif OPT_CALL_THREADED_CODE
static VALUE const finish_insn_seq[1] = { 0 };
#else
static VALUE finish_insn_seq[1] = { BIN(finish) };
#endif

void
rb_vm_change_state(void)
{
    INC_VM_STATE_VERSION();
}

/* control stack frame */

static inline VALUE
rb_vm_set_finish_env(rb_thread_t *th)
{
    vm_push_frame(th, 0, FRAME_MAGIC_FINISH,
		  Qnil, th->cfp->lfp[0], 0,
		  th->cfp->sp, 0, 1);
    th->cfp->pc = (VALUE *)&finish_insn_seq[0];
    return Qtrue;
}

void
rb_vm_set_top_stack(rb_thread_t *th, VALUE iseqval)
{
    rb_iseq_t *iseq;
    GetISeqPtr(iseqval, iseq);

    if (iseq->type != ISEQ_TYPE_TOP) {
	rb_raise(rb_eTypeError, "Not a toplevel InstructionSequence");
    }

    /* for return */
    rb_vm_set_finish_env(th);

    vm_push_frame(th, iseq, FRAME_MAGIC_TOP,
		  th->top_self, 0, iseq->iseq_encoded,
		  th->cfp->sp, 0, iseq->local_size);
}

void
rb_vm_set_eval_stack(rb_thread_t *th, VALUE iseqval)
{
    rb_iseq_t *iseq;
    rb_block_t *block = th->base_block;
    GetISeqPtr(iseqval, iseq);

    /* for return */
    rb_vm_set_finish_env(th);
    vm_push_frame(th, iseq, FRAME_MAGIC_EVAL, block->self,
		  GC_GUARDED_PTR(block->dfp), iseq->iseq_encoded,
		  th->cfp->sp, block->lfp, iseq->local_size);
}

/* Env */

static void
env_free(void *ptr)
{
    rb_env_t *env;
    RUBY_FREE_ENTER("env");
    if (ptr) {
	env = ptr;
	RUBY_FREE_UNLESS_NULL(env->env);
	ruby_xfree(ptr);
    }
    RUBY_FREE_LEAVE("env");
}

static void
env_mark(void *ptr)
{
    rb_env_t *env;
    RUBY_MARK_ENTER("env");
    if (ptr) {
	env = ptr;
	if (env->env) {
	    /* TODO: should mark more restricted range */
	    RUBY_GC_INFO("env->env\n");
	    rb_gc_mark_locations(env->env, env->env + env->env_size);
	}

	RUBY_GC_INFO("env->prev_envval\n");
	RUBY_MARK_UNLESS_NULL(env->prev_envval);
	RUBY_MARK_UNLESS_NULL(env->block.proc);

	if (env->block.iseq) {
	    if (BUILTIN_TYPE(env->block.iseq) == T_NODE) {
		RUBY_MARK_UNLESS_NULL((VALUE)env->block.iseq);
	    }
	    else {
		RUBY_MARK_UNLESS_NULL(env->block.iseq->self);
	    }
	}
    }
    RUBY_MARK_LEAVE("env");
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

static VALUE
vm_make_env_each(rb_thread_t *th, rb_control_frame_t *cfp,
		 VALUE *envptr, VALUE *endptr)
{
    VALUE envval, penvval = 0;
    rb_env_t *env;
    VALUE *nenvptr;
    int i, local_size;

    if (ENV_IN_HEAP_P(th, envptr)) {
	return ENV_VAL(envptr);
    }

    if (envptr != endptr) {
	VALUE *penvptr = GC_GUARDED_PTR_REF(*envptr);
	rb_control_frame_t *pcfp = cfp;

	if (ENV_IN_HEAP_P(th, penvptr)) {
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
	    penvval = vm_make_env_each(th, pcfp, penvptr, endptr);
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

    env->env_size = local_size + 1 + 2;
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
    nenvptr[1] = envval;	/* frame self */
    nenvptr[2] = penvval;	/* frame prev env object */

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

    if (VMDEBUG &&
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
vm_collect_local_variables_in_heap(rb_thread_t *th, VALUE *dfp, VALUE ary)
{
    if (ENV_IN_HEAP_P(th, dfp)) {
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
vm_make_env_object(rb_thread_t *th, rb_control_frame_t *cfp)
{
    VALUE envval;

    envval = vm_make_env_each(th, cfp, cfp->dfp, cfp->lfp);

    if (PROCDEBUG) {
	check_env_value(envval);
    }

    return envval;
}

void
vm_stack_to_heap(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    while ((cfp = vm_get_ruby_level_cfp(th, cfp)) != 0) {
	vm_make_env_object(th, cfp);
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
}

/* Proc */

static VALUE
vm_make_proc_from_block(rb_thread_t *th, rb_control_frame_t *cfp,
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
    block->proc = procval = vm_make_proc(th, bcfp, block);
    return procval;
}

VALUE
vm_make_proc(rb_thread_t *th,
	     rb_control_frame_t *cfp, rb_block_t *block)
{
    VALUE procval, envval, blockprocval = 0;
    rb_proc_t *proc;

    if (GC_GUARDED_PTR_REF(cfp->lfp[0])) {
	if (!RUBY_VM_CLASS_SPECIAL_P(cfp->lfp[0])) {
	    rb_proc_t *p;

	    blockprocval = vm_make_proc_from_block(
		th, cfp, (rb_block_t *)GC_GUARDED_PTR_REF(*cfp->lfp));

	    GetProcPtr(blockprocval, p);
	    *cfp->lfp = GC_GUARDED_PTR(&p->block);
	}
    }
    envval = vm_make_env_object(th, cfp);

    if (PROCDEBUG) {
	check_env_value(envval);
    }
    procval = rb_proc_alloc(rb_cProc);
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

    if (VMDEBUG) {
	if (th->stack < block->dfp && block->dfp < th->stack + th->stack_size) {
	    rb_bug("invalid ptr: block->dfp");
	}
	if (th->stack < block->lfp && block->lfp < th->stack + th->stack_size) {
	    rb_bug("invalid ptr: block->lfp");
	}
    }

    return procval;
}

/* C -> Ruby: method */

VALUE
vm_call0(rb_thread_t *th, VALUE klass, VALUE recv,
	 VALUE id, ID oid, int argc, const VALUE *argv,
	 NODE * body, int nosuper)
{
    VALUE val;
    rb_block_t *blockptr = 0;

    if (0) printf("id: %s, nd: %s, argc: %d, passed: %p\n",
		  rb_id2name(id), ruby_node_name(nd_type(body)),
		  argc, th->passed_block);

    if (th->passed_block) {
	blockptr = th->passed_block;
	th->passed_block = 0;
    }
    switch (nd_type(body)) {
      case RUBY_VM_METHOD_NODE:{
	rb_control_frame_t *reg_cfp;
	VALUE iseqval = (VALUE)body->nd_body;
	int i;

	rb_vm_set_finish_env(th);
	reg_cfp = th->cfp;

	CHECK_STACK_OVERFLOW(reg_cfp, argc + 1);

	*reg_cfp->sp++ = recv;
	for (i = 0; i < argc; i++) {
	    *reg_cfp->sp++ = argv[i];
	}

	vm_setup_method(th, reg_cfp, argc, blockptr, 0, iseqval, recv, klass);
	val = vm_eval_body(th);
	break;
      }
      case NODE_CFUNC: {
	EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, id, klass);
	{
	    rb_control_frame_t *reg_cfp = th->cfp;
	    rb_control_frame_t *cfp =
		vm_push_frame(th, 0, FRAME_MAGIC_CFUNC,
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
	    vm_pop_frame(th);
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
	val = vm_call_bmethod(th, id, body->nd_cval,
			      recv, klass, argc, (VALUE *)argv);
	break;
      }
      default:
	rb_bug("unsupported: vm_call0");
    }
    RUBY_VM_CHECK_INTS();
    return val;
}

static VALUE
vm_call_super(rb_thread_t *th, int argc, const VALUE *argv)
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
	    klass = vm_search_super_klass(cfp->method_klass, recv);
	}

	id = cfp->method_id;
    }
    else {
	rb_bug("vm_call_super: should not be reached");
    }

    body = rb_method_node(klass, id);	/* this returns NODE_METHOD */

    if (body) {
	body = body->nd_body;
    }
    else {
	dp(recv);
	dp(klass);
	dpi(id);
	rb_bug("vm_call_super: not found");
    }

    return vm_call0(th, klass, recv, id, id, argc, argv, body, nosuper);
}

VALUE
rb_call_super(int argc, const VALUE *argv)
{
    return vm_call_super(GET_THREAD(), argc, argv);
}

/* C -> Ruby: block */

static VALUE
invoke_block(rb_thread_t *th, rb_block_t *block, VALUE self, int argc, VALUE *argv)
{
    VALUE val;
    if (BUILTIN_TYPE(block->iseq) != T_NODE) {
	rb_iseq_t *iseq = block->iseq;
	int i, opt_pc;
	int type = block_proc_is_lambda(block->proc) ?
	  FRAME_MAGIC_LAMBDA : FRAME_MAGIC_BLOCK;

	rb_vm_set_finish_env(th);

	CHECK_STACK_OVERFLOW(th->cfp, argc);
	CHECK_STACK_OVERFLOW(th->cfp, iseq->stack_max);

	for (i=0; i<argc; i++) {
	    th->cfp->sp[i] = argv[i];
	}

	if (iseq->arg_block == -1) {
	    opt_pc = vm_yield_setup_args(th, iseq, argc, th->cfp->sp, 0,
					 type == FRAME_MAGIC_LAMBDA);
	}
	else {
	    rb_block_t *blockptr = 0;
	    if (rb_block_given_p()) {
		rb_proc_t *proc;
		VALUE procval;
		procval = rb_block_proc();
		GetProcPtr(procval, proc);
		blockptr = &proc->block;
	    }
	    opt_pc = vm_yield_setup_args(th, iseq, argc, th->cfp->sp,
					 blockptr, type == FRAME_MAGIC_LAMBDA);
	}
	argc = iseq->arg_size;
	th->cfp->sp += argc;

	vm_push_frame(th, iseq, type,
		      self, GC_GUARDED_PTR(block->dfp),
		      iseq->iseq_encoded + opt_pc, th->cfp->sp, block->lfp,
		      iseq->local_size - argc);
	val = vm_eval_body(th);
    }
    else {
	if (((NODE*)block->iseq)->u3.state == 1) {
	    VALUE args = rb_ary_new4(argc, argv);
	    argc = 1;
	    argv = &args;
	}
	val = vm_yield_with_cfunc(th, block, block->self, argc, argv);
    }
    return val;
}

VALUE
vm_yield(rb_thread_t *th, int argc, VALUE *argv)
{
    rb_block_t *block = GC_GUARDED_PTR_REF(th->cfp->lfp[0]);

    if (block == 0) {
	vm_localjump_error("no block given", Qnil, 0);
    }

    return invoke_block(th, block, block->self, argc, argv);
}

VALUE
vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc,
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
    TH_POP_TAG();

    th->safe_level = stored_safe;
    lfp_set_special_cref(proc->block.lfp, (NODE*)stored_special_cref_stack);

    if (state) {
	if (state == TAG_RETURN && proc->is_lambda) {
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

    if (state) {
	JUMP_TAG(state);
    }
    return val;
}

/* special variable */

VALUE
vm_cfp_svar_get(rb_thread_t *th, rb_control_frame_t *cfp, VALUE key)
{
    while (cfp->pc == 0) {
	cfp++;
    }
    return lfp_svar_get(th, cfp->lfp, key);
}

void
vm_cfp_svar_set(rb_thread_t *th, rb_control_frame_t *cfp, VALUE key, VALUE val)
{
    while (cfp->pc == 0) {
	cfp++;
    }
    lfp_svar_set(th, cfp->lfp, key, val);
}

static VALUE
vm_svar_get(VALUE key)
{
    rb_thread_t *th = GET_THREAD();
    return vm_cfp_svar_get(th, th->cfp, key);
}

static void
vm_svar_set(VALUE key, VALUE val)
{
    rb_thread_t *th = GET_THREAD();
    vm_cfp_svar_set(th, th->cfp, key, val);
}

VALUE
rb_backref_get(void)
{
    return vm_svar_get(1);
}

void
rb_backref_set(VALUE val)
{
    vm_svar_set(1, val);
}

VALUE
rb_lastline_get(void)
{
    return vm_svar_get(0);
}

void
rb_lastline_set(VALUE val)
{
    vm_svar_set(0, val);
}

/* backtrace */

int
vm_get_sourceline(rb_control_frame_t *cfp)
{
    int line_no = 0;
    rb_iseq_t *iseq = cfp->iseq;

    if (RUBY_VM_NORMAL_ISEQ_P(iseq)) {
	int i;
	int pos = cfp->pc - cfp->iseq->iseq_encoded;

	for (i = 0; i < iseq->insn_info_size; i++) {
	    if (iseq->insn_info_table[i].position == pos) {
		line_no = iseq->insn_info_table[i - 1].line_no;
		goto found;
	    }
	}
	line_no = iseq->insn_info_table[i - 1].line_no;
    }
  found:
    return line_no;
}

static VALUE
vm_backtrace_each(rb_thread_t *th,
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

		line_no = vm_get_sourceline(cfp);
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
vm_backtrace(rb_thread_t *th, int lev)
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

    ary = vm_backtrace_each(th, RUBY_VM_NEXT_CONTROL_FRAME(cfp),
			    top_of_cfp, "", 0, ary);
    return ary;
}

/* cref */

static void
check_svar(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp;
    while ((void *)(cfp + 1) < (void *)(th->stack + th->stack_size)) {
	/* printf("cfp: %p\n", cfp->type); */
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
    NODE *old_cref;

    if (VMDEBUG) {
	check_svar();
    }

    if (cref == 0 && ((VALUE)values == Qnil || values->basic.klass == 0)) {
	old_cref = 0;
    }
    else {
	old_cref = (NODE *)lfp_svar_get(GET_THREAD(), lfp, 2);
	lfp_svar_set(GET_THREAD(), lfp, 2, (VALUE)cref);
    }
    return old_cref;
}

NODE *
vm_set_special_cref(rb_thread_t *th, VALUE *lfp, NODE * cref_stack)
{
    return lfp_set_special_cref(lfp, cref_stack);
}

#if 0
void
debug_cref(NODE *cref)
{
    while (cref) {
	dp(cref->nd_clss);
	printf("%ld\n", cref->nd_visi);
	cref = cref->nd_next;
    }
}
#endif

NODE *
vm_get_cref(rb_thread_t *th, rb_iseq_t *iseq, rb_control_frame_t *cfp)
{
    return get_cref(iseq, cfp->lfp);
}

NODE *
vm_cref_push(rb_thread_t *th, VALUE klass, int noex)
{
    NODE *cref = NEW_BLOCK(klass);
    rb_control_frame_t *cfp = vm_get_ruby_level_cfp(th, th->cfp);

    cref->nd_file = 0;
    cref->nd_next = get_cref(cfp->iseq, cfp->lfp);
    cref->nd_visi = noex;
    return cref;
}

VALUE
vm_get_cbase(rb_thread_t *th)
{
    rb_control_frame_t *cfp = vm_get_ruby_level_cfp(th, th->cfp);
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

/* jump */

static VALUE
make_localjump_error(const char *mesg, VALUE value, int reason)
{
    extern VALUE rb_eLocalJumpError;
    VALUE exc = rb_exc_new2(rb_eLocalJumpError, mesg);
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
vm_localjump_error(const char *mesg, VALUE value, int reason)
{
    VALUE exc = make_localjump_error(mesg, value, reason);
    rb_exc_raise(exc);
}

VALUE
vm_make_jump_tag_but_local_jump(int state, VALUE val)
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
vm_jump_tag_but_local_jump(int state, VALUE val)
{
    VALUE exc = vm_make_jump_tag_but_local_jump(state, val);
    if (val != Qnil) {
	rb_exc_raise(exc);
    }
    JUMP_TAG(state);
}

NORETURN(static void vm_iter_break(rb_thread_t *th));

static void
vm_iter_break(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    VALUE *dfp = GC_GUARDED_PTR_REF(*cfp->dfp);

    th->state = TAG_BREAK;
    th->errinfo = (VALUE)NEW_THROW_OBJECT(Qnil, (VALUE)dfp, TAG_BREAK);
    TH_JUMP_TAG(th, TAG_BREAK);
}

void
rb_iter_break()
{
    vm_iter_break(GET_THREAD());
}

/* optimization: redefine management */

VALUE ruby_vm_redefined_flag = 0;
static st_table *vm_opt_method_table = 0;

void
rb_vm_check_redefinition_opt_method(NODE *node)
{
    VALUE bop;

    if (st_lookup(vm_opt_method_table, (st_data_t)node, &bop)) {
	ruby_vm_redefined_flag |= bop;
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

static void
vm_init_redefined_flag(void)
{
    ID mid;
    VALUE bop;

    vm_opt_method_table = st_init_numtable();

#define OP(mid_, bop_) (mid = id##mid_, bop = BOP_##bop_)
#define C(k) add_opt_method(rb_c##k, mid, bop)
    OP(PLUS, PLUS), (C(Fixnum), C(Float), C(String), C(Array));
    OP(MINUS, MINUS), (C(Fixnum));
    OP(MULT, MULT), (C(Fixnum), C(Float));
    OP(DIV, DIV), (C(Fixnum), C(Float));
    OP(MOD, MOD), (C(Fixnum), C(Float));
    OP(Eq, EQ), (C(Fixnum), C(Float), C(String));
    OP(LT, LT), (C(Fixnum));
    OP(LE, LE), (C(Fixnum));
    OP(LTLT, LTLT), (C(String), C(Array));
    OP(AREF, AREF), (C(Array), C(Hash));
    OP(ASET, ASET), (C(Array), C(Hash));
    OP(Length, LENGTH), (C(Array), C(String), C(Hash));
    OP(Succ, SUCC), (C(Fixnum), C(String), C(Time));
    OP(GT, GT), (C(Fixnum));
    OP(GE, GE), (C(Fixnum));
#undef C
#undef OP
}

/* evaluator body */

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
    rb_iseq_t *iseq;            // cfp[3]
    VALUE flag;                 // cfp[4]
    VALUE self;                 // cfp[5]
    VALUE *lfp;                 // cfp[6]
    VALUE *dfp;                 // cfp[7]
    rb_iseq_t * block_iseq;     // cfp[8]
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
vm_eval_body(rb_thread_t *th)
{
    int state;
    VALUE result, err;
    VALUE initial = 0;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
      vm_loop_start:
	result = vm_eval(th, initial);
	if ((state = th->state) != 0) {
	    err = result;
	    th->state = 0;
	    goto exception_handler;
	}
    }
    else {
	int i;
	struct iseq_catch_table_entry *entry;
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
		    if ((cfp + 1)->pc != &finish_insn_seq[0]) {
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
	    vm_push_frame(th, catch_iseq, FRAME_MAGIC_BLOCK,
			  cfp->self, (VALUE)cfp->dfp, catch_iseq->iseq_encoded,
			  cfp->sp + 1, cfp->lfp, catch_iseq->local_size - 1);

	    state = 0;
	    th->errinfo = Qnil;
	    goto vm_loop_start;
	}
	else {
	    th->cfp++;
	    if (th->cfp->pc != &finish_insn_seq[0]) {
		goto exception_handler;
	    }
	    else {
		vm_pop_frame(th);
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

/* misc */

VALUE
rb_iseq_eval(VALUE iseqval)
{
    rb_thread_t *th = GET_THREAD();
    VALUE val;
    volatile VALUE tmp;

    rb_vm_set_top_stack(th, iseqval);

    if (!rb_const_defined(rb_cObject, rb_intern("TOPLEVEL_BINDING"))) {
	rb_define_global_const("TOPLEVEL_BINDING", rb_binding_new());
    }
    val = vm_eval_body(th);
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
	    int line_no = vm_get_sourceline(cfp);
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

    vm_push_frame(th, DATA_PTR(iseq), FRAME_MAGIC_TOP,
		  recv, (VALUE)blockptr, 0, reg_cfp->sp, 0, 1);
    val = (*func)(arg);

    vm_pop_frame(th);
    return val;
}

/* vm */

static void
vm_free(void *ptr)
{
    RUBY_FREE_ENTER("vm");
    if (ptr) {
	rb_vm_t *vmobj = ptr;

	st_free_table(vmobj->living_threads);
	vmobj->living_threads = 0;
	/* TODO: MultiVM Instance */
	/* VM object should not be cleaned by GC */
	/* ruby_xfree(ptr); */
	/* ruby_current_vm = 0; */
    }
    RUBY_FREE_LEAVE("vm");
}

static int
vm_mark_each_thread_func(st_data_t key, st_data_t value, st_data_t dummy)
{
    VALUE thval = (VALUE)key;
    rb_gc_mark(thval);
    return ST_CONTINUE;
}

static void
mark_event_hooks(rb_event_hook_t *hook)
{
    while (hook) {
	rb_gc_mark(hook->data);
	hook = hook->next;
    }
}

void
rb_vm_mark(void *ptr)
{
    RUBY_MARK_ENTER("vm");
    RUBY_GC_INFO("-------------------------------------------------\n");
    if (ptr) {
	rb_vm_t *vm = ptr;
	if (vm->living_threads) {
	    st_foreach(vm->living_threads, vm_mark_each_thread_func, 0);
	}
	RUBY_MARK_UNLESS_NULL(vm->thgroup_default);
	RUBY_MARK_UNLESS_NULL(vm->mark_object_ary);
	RUBY_MARK_UNLESS_NULL(vm->last_status);
	RUBY_MARK_UNLESS_NULL(vm->loaded_features);
	RUBY_MARK_UNLESS_NULL(vm->top_self);

	if (vm->loading_table) {
	    rb_mark_tbl(vm->loading_table);
	}

	mark_event_hooks(vm->event_hooks);
    }

    RUBY_MARK_LEAVE("vm");
}

static void
vm_init2(rb_vm_t *vm)
{
    MEMZERO(vm, rb_vm_t, 1);
}

/* Thread */

static void
thread_free(void *ptr)
{
    rb_thread_t *th;
    RUBY_FREE_ENTER("thread");

    if (ptr) {
	th = ptr;

	if (!th->root_fiber) {
	    RUBY_FREE_UNLESS_NULL(th->stack);
	}

	if (th->local_storage) {
	    st_free_table(th->local_storage);
	}

#if USE_VALUE_CACHE
	{
	    VALUE *ptr = th->value_cache_ptr;
	    while (*ptr) {
		VALUE v = *ptr;
		RBASIC(v)->flags = 0;
		RBASIC(v)->klass = 0;
		ptr++;
	    }
	}
#endif

	if (th->vm->main_thread == th) {
	    RUBY_GC_INFO("main thread\n");
	}
	else {
	    ruby_xfree(ptr);
	}
    }
    RUBY_FREE_LEAVE("thread");
}

void rb_gc_mark_machine_stack(rb_thread_t *th);

void
rb_thread_mark(void *ptr)
{
    rb_thread_t *th = NULL;
    RUBY_MARK_ENTER("thread");
    if (ptr) {
	th = ptr;
	if (th->stack) {
	    VALUE *p = th->stack;
	    VALUE *sp = th->cfp->sp + th->mark_stack_len;
	    rb_control_frame_t *cfp = th->cfp;
	    rb_control_frame_t *limit_cfp =
	      (void *)(th->stack + th->stack_size);

	    while (p < sp) {
		rb_gc_mark(*p++);
	    }
	    while (cfp != limit_cfp) {
		rb_gc_mark(cfp->proc);
		cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	    }
	}

	/* mark ruby objects */
	RUBY_MARK_UNLESS_NULL(th->first_proc);
	RUBY_MARK_UNLESS_NULL(th->first_args);

	RUBY_MARK_UNLESS_NULL(th->thgroup);
	RUBY_MARK_UNLESS_NULL(th->value);
	RUBY_MARK_UNLESS_NULL(th->errinfo);
	RUBY_MARK_UNLESS_NULL(th->thrown_errinfo);
	RUBY_MARK_UNLESS_NULL(th->local_svar);
	RUBY_MARK_UNLESS_NULL(th->top_self);
	RUBY_MARK_UNLESS_NULL(th->top_wrapper);
	RUBY_MARK_UNLESS_NULL(th->fiber);
	RUBY_MARK_UNLESS_NULL(th->root_fiber);

	rb_mark_tbl(th->local_storage);

	if (GET_THREAD() != th && th->machine_stack_start && th->machine_stack_end) {
	    rb_gc_mark_machine_stack(th);
	    rb_gc_mark_locations((VALUE *)&th->machine_regs,
				 (VALUE *)(&th->machine_regs) +
				 sizeof(th->machine_regs) / sizeof(VALUE));
	}

	mark_event_hooks(th->event_hooks);
    }

    RUBY_MARK_UNLESS_NULL(th->stat_insn_usage);
    RUBY_MARK_LEAVE("thread");
}

static VALUE
thread_alloc(VALUE klass)
{
    VALUE volatile obj;
    rb_thread_t *th;
    obj = Data_Make_Struct(klass, rb_thread_t,
			   rb_thread_mark, thread_free, th);
    return obj;
}

static void
th_init2(rb_thread_t *th)
{
    MEMZERO(th, rb_thread_t, 1);

    /* allocate thread stack */
    th->stack_size = RUBY_VM_THREAD_STACK_SIZE;
    th->stack = ALLOC_N(VALUE, th->stack_size);

    th->cfp = (void *)(th->stack + th->stack_size);
    th->cfp--;

    th->cfp->pc = 0;
    th->cfp->sp = th->stack + 1;
    th->cfp->bp = 0;
    th->cfp->lfp = th->stack;
    *th->cfp->lfp = 0;
    th->cfp->dfp = th->stack;
    th->cfp->self = Qnil;
    th->cfp->flag = 0;
    th->cfp->iseq = 0;
    th->cfp->proc = 0;
    th->cfp->block_iseq = 0;

    th->status = THREAD_RUNNABLE;
    th->errinfo = Qnil;

#if USE_VALUE_CACHE
    th->value_cache_ptr = &th->value_cache[0];
#endif
}

static void
th_init(rb_thread_t *th)
{
    th_init2(th);
}

static VALUE
ruby_thread_init(VALUE self)
{
    rb_thread_t *th;
    rb_vm_t *vm = GET_THREAD()->vm;
    GetThreadPtr(self, th);

    th_init(th);
    th->self = self;
    th->vm = vm;

    th->top_wrapper = 0;
    th->top_self = rb_vm_top_self();
    return self;
}

VALUE
rb_thread_alloc(VALUE klass)
{
    VALUE self = thread_alloc(klass);
    ruby_thread_init(self);
    return self;
}

VALUE insns_name_array(void);
extern VALUE *rb_gc_stack_start;
#ifdef __ia64
extern VALUE *rb_gc_register_stack_start;
#endif

static VALUE
sdr(void)
{
    rb_vm_bugreport();
    return Qnil;
}

static VALUE
nsdr(void)
{
    VALUE ary = rb_ary_new();
#if HAVE_BACKTRACE
#include <execinfo.h>
#define MAX_NATIVE_TRACE 1024
    static void *trace[MAX_NATIVE_TRACE];
    int n = backtrace(trace, MAX_NATIVE_TRACE);
    char **syms = backtrace_symbols(trace, n);
    int i;

    if (syms == 0) {
	rb_memerror();
    }

    for (i=0; i<n; i++) {
	rb_ary_push(ary, rb_str_new2(syms[i]));
    }
    free(syms);
#endif
    return ary;
}

void
Init_VM(void)
{
    VALUE opts;

    /* ::VM */
    rb_cVM = rb_define_class("VM", rb_cObject);
    rb_undef_alloc_func(rb_cVM);

    /* Env */
    rb_cEnv = rb_define_class_under(rb_cVM, "Env", rb_cObject);
    rb_undef_alloc_func(rb_cEnv);

    /* ::Thread */
    rb_cThread = rb_define_class("Thread", rb_cObject);
    rb_undef_alloc_func(rb_cThread);
    rb_define_method(rb_cThread, "initialize", ruby_thread_init, 0);

    /* ::VM::USAGE_ANALISYS_* */
    rb_define_const(rb_cVM, "USAGE_ANALISYS_INSN", rb_hash_new());
    rb_define_const(rb_cVM, "USAGE_ANALISYS_REGS", rb_hash_new());
    rb_define_const(rb_cVM, "USAGE_ANALISYS_INSN_BIGRAM", rb_hash_new());
    rb_define_const(rb_cVM, "OPTS", opts = rb_ary_new());

#if   OPT_DIRECT_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("direct threaded code"));
#elif OPT_TOKEN_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("token threaded code"));
#elif OPT_CALL_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("call threaded code"));
#endif

#if OPT_BASIC_OPERATIONS
    rb_ary_push(opts, rb_str_new2("optimize basic operation"));
#endif

#if OPT_STACK_CACHING
    rb_ary_push(opts, rb_str_new2("stack caching"));
#endif
#if OPT_OPERANDS_UNIFICATION
    rb_ary_push(opts, rb_str_new2("operands unification]"));
#endif
#if OPT_INSTRUCTIONS_UNIFICATION
    rb_ary_push(opts, rb_str_new2("instructions unification"));
#endif
#if OPT_INLINE_METHOD_CACHE
    rb_ary_push(opts, rb_str_new2("inline method cache"));
#endif
#if OPT_BLOCKINLINING
    rb_ary_push(opts, rb_str_new2("block inlining"));
#endif

    /* ::VM::InsnNameArray */
    rb_define_const(rb_cVM, "INSTRUCTION_NAMES", insns_name_array());

    /* debug functions ::VM::SDR(), ::VM::NSDR() */
    rb_define_singleton_method(rb_cVM, "SDR", sdr, 0);
    rb_define_singleton_method(rb_cVM, "NSDR", nsdr, 0);

    /* VM bootstrap: phase 2 */
    {
	rb_vm_t *vm = ruby_current_vm;
	rb_thread_t *th = GET_THREAD();
        volatile VALUE th_self;

	/* create vm object */
	vm->self = Data_Wrap_Struct(rb_cVM, rb_vm_mark, vm_free, vm);

	/* create main thread */
	th_self = th->self = Data_Wrap_Struct(rb_cThread, rb_thread_mark,
					      thread_free, th);

	vm->main_thread = th;
	vm->running_thread = th;
	th->vm = vm;
	th->top_wrapper = 0;
	th->top_self = rb_vm_top_self();
	rb_thread_set_current(th);

	vm->living_threads = st_init_numtable();
	st_insert(vm->living_threads, th_self, (st_data_t) th->thread_id);
    }
    vm_init_redefined_flag();
}

void
Init_BareVM(void)
{
    /* VM bootstrap: phase 1 */
    rb_vm_t *vm = ALLOC(rb_vm_t);
    rb_thread_t *th = ALLOC(rb_thread_t);

    vm_init2(vm);
    ruby_current_vm = vm;

    th_init2(th);
    th->vm = vm;
    th->machine_stack_start = rb_gc_stack_start;
#ifdef __ia64
    th->machine_register_stack_start = rb_gc_register_stack_start;
#endif
    rb_thread_set_current_raw(th);
}

/* top self */

static VALUE
main_to_s(VALUE obj)
{
    return rb_str_new2("main");
}

VALUE
rb_vm_top_self()
{
    return GET_VM()->top_self;
}

void
Init_top_self()
{
    rb_vm_t *vm = GET_VM();

    vm->top_self = rb_obj_alloc(rb_cObject);
    rb_define_singleton_method(rb_vm_top_self(), "to_s", main_to_s, 0);
}
