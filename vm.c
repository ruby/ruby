/**********************************************************************

  vm.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/vm.h"
#include "ruby/st.h"
#include "ruby/encoding.h"
#include "internal.h"

#include "gc.h"
#include "vm_core.h"
#include "iseq.h"
#include "eval_intern.h"
#include "probes.h"
#include "probes_helper.h"

static inline VALUE *
VM_EP_LEP(VALUE *ep)
{
    while (!VM_EP_LEP_P(ep)) {
	ep = VM_EP_PREV_EP(ep);
    }
    return ep;
}

VALUE *
rb_vm_ep_local_ep(VALUE *ep)
{
    return VM_EP_LEP(ep);
}

static inline VALUE *
VM_CF_LEP(rb_control_frame_t *cfp)
{
    return VM_EP_LEP(cfp->ep);
}

static inline VALUE *
VM_CF_PREV_EP(rb_control_frame_t * cfp)
{
    return VM_EP_PREV_EP((cfp)->ep);
}

static inline rb_block_t *
VM_CF_BLOCK_PTR(rb_control_frame_t *cfp)
{
    VALUE *ep = VM_CF_LEP(cfp);
    return VM_EP_BLOCK_PTR(ep);
}

rb_block_t *
rb_vm_control_frame_block_ptr(rb_control_frame_t *cfp)
{
    return VM_CF_BLOCK_PTR(cfp);
}

#if VM_COLLECT_USAGE_DETAILS
static void vm_collect_usage_operand(int insn, int n, VALUE op);
static void vm_collect_usage_insn(int insn);
static void vm_collect_usage_register(int reg, int isset);
#endif

static VALUE
vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc, VALUE self, VALUE defined_class,
	       int argc, const VALUE *argv, const rb_block_t *blockptr);

static rb_serial_t ruby_vm_global_method_state = 1;
static rb_serial_t ruby_vm_global_constant_state = 1;
static rb_serial_t ruby_vm_class_serial = 1;

#include "vm_insnhelper.h"
#include "vm_insnhelper.c"
#include "vm_exec.h"
#include "vm_exec.c"

#include "vm_method.c"
#include "vm_eval.c"

#include <assert.h>

#define BUFSIZE 0x100
#define PROCDEBUG 0

rb_serial_t
rb_next_class_serial(void)
{
    return NEXT_CLASS_SERIAL();
}

VALUE rb_cRubyVM;
VALUE rb_cThread;
VALUE rb_cEnv;
VALUE rb_mRubyVMFrozenCore;

VALUE ruby_vm_const_missing_count = 0;
short ruby_vm_redefined_flag[BOP_LAST_];
rb_thread_t *ruby_current_thread = 0;
rb_vm_t *ruby_current_vm = 0;
rb_event_flag_t ruby_vm_event_flags;

static void thread_free(void *ptr);

void
rb_vm_inc_const_missing_count(void)
{
    ruby_vm_const_missing_count +=1;
}

/*
 *  call-seq:
 *    RubyVM.stat -> Hash
 *    RubyVM.stat(hsh) -> hsh
 *    RubyVM.stat(Symbol) -> Numeric
 *
 *  Returns a Hash containing implementation-dependent counters inside the VM.
 *
 *  This hash includes information about method/constant cache serials:
 *
 *    {
 *      :global_method_state=>251,
 *      :global_constant_state=>481,
 *      :class_serial=>9029
 *    }
 *
 *  The contents of the hash are implementation specific and may be changed in
 *  the future.
 *
 *  This method is only expected to work on C Ruby.
 */

static VALUE
vm_stat(int argc, VALUE *argv, VALUE self)
{
    static VALUE sym_global_method_state, sym_global_constant_state, sym_class_serial;
    VALUE arg = Qnil;
    VALUE hash = Qnil, key = Qnil;

    if (rb_scan_args(argc, argv, "01", &arg) == 1) {
	if (SYMBOL_P(arg))
	    key = arg;
	else if (RB_TYPE_P(arg, T_HASH))
	    hash = arg;
	else
	    rb_raise(rb_eTypeError, "non-hash or symbol given");
    } else if (arg == Qnil) {
	hash = rb_hash_new();
    }

    if (sym_global_method_state == 0) {
#define S(s) sym_##s = ID2SYM(rb_intern_const(#s))
	S(global_method_state);
	S(global_constant_state);
	S(class_serial);
#undef S
    }

#define SET(name, attr) \
    if (key == sym_##name) \
	return SERIALT2NUM(attr); \
    else if (hash != Qnil) \
	rb_hash_aset(hash, sym_##name, SERIALT2NUM(attr));

    SET(global_method_state, ruby_vm_global_method_state);
    SET(global_constant_state, ruby_vm_global_constant_state);
    SET(class_serial, ruby_vm_class_serial);
#undef SET

    if (key != Qnil) /* matched key should return above */
	rb_raise(rb_eArgError, "unknown key: %s", RSTRING_PTR(rb_id2str(SYM2ID(key))));

    return hash;
}

/* control stack frame */

static void
vm_set_top_stack(rb_thread_t * th, VALUE iseqval)
{
    rb_iseq_t *iseq;
    GetISeqPtr(iseqval, iseq);

    if (iseq->type != ISEQ_TYPE_TOP) {
	rb_raise(rb_eTypeError, "Not a toplevel InstructionSequence");
    }

    /* for return */
    vm_push_frame(th, iseq, VM_FRAME_MAGIC_TOP | VM_FRAME_FLAG_FINISH,
		  th->top_self, rb_cObject, VM_ENVVAL_BLOCK_PTR(0),
		  iseq->iseq_encoded, th->cfp->sp, iseq->local_size, 0, iseq->stack_max);
}

static void
vm_set_eval_stack(rb_thread_t * th, VALUE iseqval, const NODE *cref, rb_block_t *base_block)
{
    rb_iseq_t *iseq;
    GetISeqPtr(iseqval, iseq);

    vm_push_frame(th, iseq, VM_FRAME_MAGIC_EVAL | VM_FRAME_FLAG_FINISH,
		  base_block->self, base_block->klass,
		  VM_ENVVAL_PREV_EP_PTR(base_block->ep), iseq->iseq_encoded,
		  th->cfp->sp, iseq->local_size, 0, iseq->stack_max);

    if (cref) {
	th->cfp->ep[-1] = (VALUE)cref;
    }
}

static void
vm_set_main_stack(rb_thread_t *th, VALUE iseqval)
{
    VALUE toplevel_binding = rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING"));
    rb_binding_t *bind;
    rb_iseq_t *iseq;
    rb_env_t *env;

    GetBindingPtr(toplevel_binding, bind);
    GetEnvPtr(bind->env, env);
    vm_set_eval_stack(th, iseqval, 0, &env->block);

    /* save binding */
    GetISeqPtr(iseqval, iseq);
    if (bind && iseq->local_size > 0) {
	bind->env = rb_vm_make_env_object(th, th->cfp);
    }
}

rb_control_frame_t *
rb_vm_get_binding_creatable_next_cfp(rb_thread_t *th, const rb_control_frame_t *cfp)
{
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	if (cfp->iseq) {
	    return (rb_control_frame_t *)cfp;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

rb_control_frame_t *
rb_vm_get_ruby_level_next_cfp(rb_thread_t *th, const rb_control_frame_t *cfp)
{
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	    return (rb_control_frame_t *)cfp;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

static rb_control_frame_t *
vm_get_ruby_level_caller_cfp(rb_thread_t *th, rb_control_frame_t *cfp)
{
    if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	return cfp;
    }

    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	    return cfp;
	}

	if ((cfp->flag & VM_FRAME_FLAG_PASSED) == 0) {
	    break;
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

/* at exit */

void
ruby_vm_at_exit(void (*func)(rb_vm_t *))
{
    rb_ary_push((VALUE)&GET_VM()->at_exit, (VALUE)func);
}

static void
ruby_vm_run_at_exit_hooks(rb_vm_t *vm)
{
    VALUE hook = (VALUE)&vm->at_exit;

    while (RARRAY_LEN(hook) > 0) {
	typedef void rb_vm_at_exit_func(rb_vm_t*);
	rb_vm_at_exit_func *func = (rb_vm_at_exit_func*)rb_ary_pop(hook);
	(*func)(vm);
    }
    rb_ary_free(hook);
}

/* Env */

/*
  env{
    env[0] // special (block or prev env)
    env[1] // env object
  };
 */

#define ENV_IN_HEAP_P(th, env)  \
  (!((th)->stack <= (env) && (env) < ((th)->stack + (th)->stack_size)))
#define ENV_VAL(env)        ((env)[1])

static void
env_mark(void * const ptr)
{
    RUBY_MARK_ENTER("env");
    if (ptr) {
	const rb_env_t * const env = ptr;

	if (env->env) {
	    /* TODO: should mark more restricted range */
	    RUBY_GC_INFO("env->env\n");
	    rb_gc_mark_locations(env->env, env->env + env->env_size);
	}

	RUBY_GC_INFO("env->prev_envval\n");
	RUBY_MARK_UNLESS_NULL(env->prev_envval);
	RUBY_MARK_UNLESS_NULL(env->block.self);
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

static void
env_free(void * const ptr)
{
    RUBY_FREE_ENTER("env");
    if (ptr) {
	rb_env_t *const env = ptr;
	RUBY_FREE_UNLESS_NULL(env->env);
	ruby_xfree(ptr);
    }
    RUBY_FREE_LEAVE("env");
}

static size_t
env_memsize(const void *ptr)
{
    if (ptr) {
	const rb_env_t * const env = ptr;
	size_t size = sizeof(rb_env_t);
	if (env->env) {
	    size += env->env_size * sizeof(VALUE);
	}
	return size;
    }
    return 0;
}

static const rb_data_type_t env_data_type = {
    "VM/env",
    {env_mark, env_free, env_memsize,},
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
env_alloc(void)
{
    VALUE obj;
    rb_env_t *env;
    obj = TypedData_Make_Struct(rb_cEnv, rb_env_t, &env_data_type, env);
    env->env = 0;
    env->prev_envval = 0;
    env->block.iseq = 0;
    return obj;
}

static VALUE check_env_value(VALUE envval);

static int
check_env(rb_env_t * const env)
{
    fprintf(stderr, "---\n");
    fprintf(stderr, "envptr: %p\n", (void *)&env->block.ep[0]);
    fprintf(stderr, "envval: %10p ", (void *)env->block.ep[1]);
    dp(env->block.ep[1]);
    fprintf(stderr, "ep:    %10p\n", (void *)env->block.ep);
    if (env->prev_envval) {
	fprintf(stderr, ">>\n");
	check_env_value(env->prev_envval);
	fprintf(stderr, "<<\n");
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
    rb_bug("invalid env");
    return Qnil;		/* unreachable */
}

static VALUE
vm_make_env_each(rb_thread_t * const th, rb_control_frame_t * const cfp,
		 VALUE *envptr, VALUE * const endptr)
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
	    while (pcfp->ep != penvptr) {
		pcfp++;
		if (pcfp->ep == 0) {
		    SDR();
		    rb_bug("invalid ep");
		}
	    }
	    penvval = vm_make_env_each(th, pcfp, penvptr, endptr);
	    *envptr = VM_ENVVAL_PREV_EP_PTR(pcfp->ep);
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

    env->env_size = local_size + 1 + 1;
    env->local_size = local_size;
    env->env = ALLOC_N(VALUE, env->env_size);
    env->prev_envval = penvval;

    for (i = 0; i <= local_size; i++) {
	env->env[i] = envptr[-local_size + i];
#if 0
	fprintf(stderr, "%2d ", &envptr[-local_size + i] - th->stack); dp(env->env[i]);
	if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	    /* clear value stack for GC */
	    envptr[-local_size + i] = 0;
	}
#endif
    }

    *envptr = envval;		/* GC mark */
    nenvptr = &env->env[i - 1];
    nenvptr[1] = envval;	/* frame self */

    /* reset ep in cfp */
    cfp->ep = nenvptr;

    /* as Binding */
    env->block.self = cfp->self;
    env->block.ep = cfp->ep;
    env->block.iseq = cfp->iseq;

    if (!RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	/* TODO */
	env->block.iseq = 0;
    }
    return envval;
}

static int
collect_local_variables_in_iseq(rb_iseq_t *iseq, const VALUE ary)
{
    int i;
    if (!iseq) return 0;
    for (i = 0; i < iseq->local_table_size; i++) {
	ID lid = iseq->local_table[i];
	if (rb_is_local_id(lid)) {
	    rb_ary_push(ary, ID2SYM(lid));
	}
    }
    return 1;
}

static int
collect_local_variables_in_env(rb_env_t * env, const VALUE ary)
{

    while (collect_local_variables_in_iseq(env->block.iseq, ary),
	   env->prev_envval) {
	GetEnvPtr(env->prev_envval, env);
    }
    return 0;
}

static int
vm_collect_local_variables_in_heap(rb_thread_t *th, VALUE *ep, VALUE ary)
{
    if (ENV_IN_HEAP_P(th, ep)) {
	rb_env_t *env;
	GetEnvPtr(ENV_VAL(ep), env);
	collect_local_variables_in_env(env, ary);
	return 1;
    }
    else {
	return 0;
    }
}

static void vm_rewrite_ep_in_errinfo(rb_thread_t *th);
static VALUE vm_make_proc_from_block(rb_thread_t *th, rb_block_t *block);
static VALUE vm_make_env_object(rb_thread_t * th, rb_control_frame_t *cfp, VALUE *blockprocptr);

VALUE
rb_vm_make_env_object(rb_thread_t * th, rb_control_frame_t *cfp)
{
    VALUE blockprocval;
    return vm_make_env_object(th, cfp, &blockprocval);
}

static VALUE
vm_make_env_object(rb_thread_t *th, rb_control_frame_t *cfp, VALUE *blockprocptr)
{
    VALUE envval;
    VALUE *lep = VM_CF_LEP(cfp);
    rb_block_t *blockptr = VM_EP_BLOCK_PTR(lep);

    if (blockptr) {
	VALUE blockprocval = vm_make_proc_from_block(th, blockptr);
	rb_proc_t *p;
	GetProcPtr(blockprocval, p);
	lep[0] = VM_ENVVAL_BLOCK_PTR(&p->block);
	*blockprocptr = blockprocval;
    }

    envval = vm_make_env_each(th, cfp, cfp->ep, lep);
    vm_rewrite_ep_in_errinfo(th);

    if (PROCDEBUG) {
	check_env_value(envval);
    }

    return envval;
}

static void
vm_rewrite_ep_in_errinfo(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    while (!RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	/* rewrite ep in errinfo to point to heap */
	if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq) &&
	    (cfp->iseq->type == ISEQ_TYPE_RESCUE ||
	     cfp->iseq->type == ISEQ_TYPE_ENSURE)) {
	    VALUE errinfo = cfp->ep[-2]; /* #$! */
	    if (RB_TYPE_P(errinfo, T_NODE)) {
		VALUE *escape_ep = GET_THROWOBJ_CATCH_POINT(errinfo);
		if (! ENV_IN_HEAP_P(th, escape_ep)) {
		    VALUE epval = *escape_ep;
		    if (!SPECIAL_CONST_P(epval) && RBASIC(epval)->klass == rb_cEnv) {
			rb_env_t *epenv;
			GetEnvPtr(epval, epenv);
			SET_THROWOBJ_CATCH_POINT(errinfo, (VALUE)(epenv->env + epenv->local_size));
		    }
		}
	    }
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
}

void
rb_vm_stack_to_heap(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    while ((cfp = rb_vm_get_binding_creatable_next_cfp(th, cfp)) != 0) {
	rb_vm_make_env_object(th, cfp);
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
}

/* Proc */

static VALUE
vm_make_proc_from_block(rb_thread_t *th, rb_block_t *block)
{
    if (!block->proc) {
	block->proc = rb_vm_make_proc(th, block, rb_cProc);
    }
    return block->proc;
}

VALUE
rb_vm_make_proc(rb_thread_t *th, const rb_block_t *block, VALUE klass)
{
    VALUE procval, envval, blockprocval = 0;
    rb_proc_t *proc;
    rb_control_frame_t *cfp = RUBY_VM_GET_CFP_FROM_BLOCK_PTR(block);

    if (block->proc) {
	rb_bug("rb_vm_make_proc: Proc value is already created.");
    }

    envval = vm_make_env_object(th, cfp, &blockprocval);

    if (PROCDEBUG) {
	check_env_value(envval);
    }
    procval = rb_proc_alloc(klass);
    GetProcPtr(procval, proc);
    proc->blockprocval = blockprocval;
    proc->block.self = block->self;
    proc->block.klass = block->klass;
    proc->block.ep = block->ep;
    proc->block.iseq = block->iseq;
    proc->block.proc = procval;
    proc->envval = envval;
    proc->safe_level = th->safe_level;

    if (VMDEBUG) {
	if (th->stack < block->ep && block->ep < th->stack + th->stack_size) {
	    rb_bug("invalid ptr: block->ep");
	}
    }

    return procval;
}

VALUE *
rb_binding_add_dynavars(rb_binding_t *bind, int dyncount, const ID *dynvars)
{
    VALUE envval = bind->env, path = bind->path, iseqval;
    rb_env_t *env;
    rb_block_t *base_block;
    rb_thread_t *th = GET_THREAD();
    rb_iseq_t *base_iseq;
    NODE *node = 0;
    ID minibuf[4], *dyns = minibuf;
    VALUE idtmp = 0;

    if (dyncount < 0) return 0;

    GetEnvPtr(envval, env);

    base_block = &env->block;
    base_iseq = base_block->iseq;

    if (dyncount >= numberof(minibuf)) dyns = ALLOCV_N(ID, idtmp, dyncount + 1);

    dyns[0] = dyncount;
    MEMCPY(dyns + 1, dynvars, ID, dyncount);
    node = NEW_NODE(NODE_SCOPE, dyns, 0, 0);

    iseqval = rb_iseq_new(node, base_iseq->location.label, path, path,
			  base_iseq->self, ISEQ_TYPE_EVAL);
    node->u1.tbl = 0; /* reset table */
    ALLOCV_END(idtmp);

    vm_set_eval_stack(th, iseqval, 0, base_block);
    bind->env = rb_vm_make_env_object(th, th->cfp);
    vm_pop_frame(th);
    GetEnvPtr(bind->env, env);

    return env->env;
}

/* C -> Ruby: block */

static inline VALUE
invoke_block_from_c(rb_thread_t *th, const rb_block_t *block,
		    VALUE self, int argc, const VALUE *argv,
		    const rb_block_t *blockptr, const NODE *cref,
		    VALUE defined_class)
{
    if (SPECIAL_CONST_P(block->iseq))
	return Qnil;
    else if (BUILTIN_TYPE(block->iseq) != T_NODE) {
	const rb_iseq_t *iseq = block->iseq;
	const rb_control_frame_t *cfp;
	int i, opt_pc, arg_size = iseq->arg_size;
	int type = block_proc_is_lambda(block->proc) ?
	  VM_FRAME_MAGIC_LAMBDA : VM_FRAME_MAGIC_BLOCK;

	cfp = th->cfp;

	for (i=0; i<argc; i++) {
	    cfp->sp[i] = argv[i];
	}

	opt_pc = vm_yield_setup_args(th, iseq, argc, cfp->sp, blockptr,
				     type == VM_FRAME_MAGIC_LAMBDA);

	if (th->passed_bmethod_me != 0) {
	    /* bmethod */
	    vm_push_frame(th, iseq, type | VM_FRAME_FLAG_FINISH | VM_FRAME_FLAG_BMETHOD,
			  self, defined_class,
			  VM_ENVVAL_PREV_EP_PTR(block->ep),
			  iseq->iseq_encoded + opt_pc,
			  cfp->sp + arg_size, iseq->local_size - arg_size,
			  th->passed_bmethod_me, iseq->stack_max);
	    th->passed_bmethod_me = 0;
	}
	else {
	    vm_push_frame(th, iseq, type | VM_FRAME_FLAG_FINISH,
			  self, defined_class,
			  VM_ENVVAL_PREV_EP_PTR(block->ep),
			  iseq->iseq_encoded + opt_pc,
			  cfp->sp + arg_size, iseq->local_size - arg_size,
			  0, iseq->stack_max);
	}

	if (cref) {
	    th->cfp->ep[-1] = (VALUE)cref;
	}

	return vm_exec(th);
    }
    else {
	return vm_yield_with_cfunc(th, block, self, argc, argv, blockptr);
    }
}

static inline const rb_block_t *
check_block(rb_thread_t *th)
{
    const rb_block_t *blockptr = VM_CF_BLOCK_PTR(th->cfp);

    if (blockptr == 0) {
	rb_vm_localjump_error("no block given", Qnil, 0);
    }

    return blockptr;
}

static inline VALUE
vm_yield_with_cref(rb_thread_t *th, int argc, const VALUE *argv, const NODE *cref)
{
    const rb_block_t *blockptr = check_block(th);
    return invoke_block_from_c(th, blockptr, blockptr->self, argc, argv, 0, cref,
			       blockptr->klass);
}

static inline VALUE
vm_yield(rb_thread_t *th, int argc, const VALUE *argv)
{
    const rb_block_t *blockptr = check_block(th);
    return invoke_block_from_c(th, blockptr, blockptr->self, argc, argv, 0, 0,
			       blockptr->klass);
}

static inline VALUE
vm_yield_with_block(rb_thread_t *th, int argc, const VALUE *argv, const rb_block_t *blockargptr)
{
    const rb_block_t *blockptr = check_block(th);
    return invoke_block_from_c(th, blockptr, blockptr->self, argc, argv, blockargptr, 0,
			       blockptr->klass);
}

static VALUE
vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc, VALUE self, VALUE defined_class,
	       int argc, const VALUE *argv, const rb_block_t *blockptr)
{
    VALUE val = Qundef;
    int state;
    volatile int stored_safe = th->safe_level;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	if (!proc->is_from_method) {
	    th->safe_level = proc->safe_level;
	}
	val = invoke_block_from_c(th, &proc->block, self, argc, argv, blockptr, 0,
				  defined_class);
    }
    TH_POP_TAG();

    if (!proc->is_from_method) {
	th->safe_level = stored_safe;
    }

    if (state) {
	JUMP_TAG(state);
    }
    return val;
}

VALUE
rb_vm_invoke_proc(rb_thread_t *th, rb_proc_t *proc,
		  int argc, const VALUE *argv, const rb_block_t *blockptr)
{
    return vm_invoke_proc(th, proc, proc->block.self, proc->block.klass,
			  argc, argv, blockptr);
}

/* special variable */

static rb_control_frame_t *
vm_normal_frame(rb_thread_t *th, rb_control_frame_t *cfp)
{
    while (cfp->pc == 0) {
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
	    return 0;
	}
    }
    return cfp;
}

static VALUE
vm_cfp_svar_get(rb_thread_t *th, rb_control_frame_t *cfp, VALUE key)
{
    cfp = vm_normal_frame(th, cfp);
    return lep_svar_get(th, cfp ? VM_CF_LEP(cfp) : 0, key);
}

static void
vm_cfp_svar_set(rb_thread_t *th, rb_control_frame_t *cfp, VALUE key, const VALUE val)
{
    cfp = vm_normal_frame(th, cfp);
    lep_svar_set(th, cfp ? VM_CF_LEP(cfp) : 0, key, val);
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

/* misc */

VALUE
rb_sourcefilename(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp) {
	return cfp->iseq->location.path;
    }
    else {
	return Qnil;
    }
}

const char *
rb_sourcefile(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp) {
	return RSTRING_PTR(cfp->iseq->location.path);
    }
    else {
	return 0;
    }
}

int
rb_sourceline(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp) {
	return rb_vm_get_sourceline(cfp);
    }
    else {
	return 0;
    }
}

NODE *
rb_vm_cref(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp == 0) {
	return NULL;
    }
    return rb_vm_get_cref(cfp->iseq, cfp->ep);
}

NODE *
rb_vm_cref_in_context(VALUE self)
{
    rb_thread_t *th = GET_THREAD();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);
    if (cfp->self != self) return NULL;
    return rb_vm_get_cref(cfp->iseq, cfp->ep);
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

VALUE
rb_vm_cbase(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp == 0) {
	rb_raise(rb_eRuntimeError, "Can't call on top of Fiber or Thread");
    }
    return vm_get_cbase(cfp->iseq, cfp->ep);
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
	CONST_ID(id, "break");
	break;
      case TAG_REDO:
	CONST_ID(id, "redo");
	break;
      case TAG_RETRY:
	CONST_ID(id, "retry");
	break;
      case TAG_NEXT:
	CONST_ID(id, "next");
	break;
      case TAG_RETURN:
	CONST_ID(id, "return");
	break;
      default:
	CONST_ID(id, "noreason");
	break;
    }
    rb_iv_set(exc, "@exit_value", value);
    rb_iv_set(exc, "@reason", ID2SYM(id));
    return exc;
}

void
rb_vm_localjump_error(const char *mesg, VALUE value, int reason)
{
    VALUE exc = make_localjump_error(mesg, value, reason);
    rb_exc_raise(exc);
}

VALUE
rb_vm_make_jump_tag_but_local_jump(int state, VALUE val)
{
    VALUE result = Qnil;

    if (val == Qundef) {
	val = GET_THREAD()->tag->retval;
    }
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
rb_vm_jump_tag_but_local_jump(int state)
{
    VALUE exc = rb_vm_make_jump_tag_but_local_jump(state, Qundef);
    if (!NIL_P(exc)) rb_exc_raise(exc);
    JUMP_TAG(state);
}

NORETURN(static void vm_iter_break(rb_thread_t *th, VALUE val));

static void
vm_iter_break(rb_thread_t *th, VALUE val)
{
    rb_control_frame_t *cfp = th->cfp;
    VALUE *ep = VM_CF_PREV_EP(cfp);

    th->state = TAG_BREAK;
    th->errinfo = (VALUE)NEW_THROW_OBJECT(val, (VALUE)ep, TAG_BREAK);
    TH_JUMP_TAG(th, TAG_BREAK);
}

void
rb_iter_break(void)
{
    vm_iter_break(GET_THREAD(), Qnil);
}

void
rb_iter_break_value(VALUE val)
{
    vm_iter_break(GET_THREAD(), val);
}

/* optimization: redefine management */

static st_table *vm_opt_method_table = 0;

static int
vm_redefinition_check_flag(VALUE klass)
{
    if (klass == rb_cFixnum) return FIXNUM_REDEFINED_OP_FLAG;
    if (klass == rb_cFloat)  return FLOAT_REDEFINED_OP_FLAG;
    if (klass == rb_cString) return STRING_REDEFINED_OP_FLAG;
    if (klass == rb_cArray)  return ARRAY_REDEFINED_OP_FLAG;
    if (klass == rb_cHash)   return HASH_REDEFINED_OP_FLAG;
    if (klass == rb_cBignum) return BIGNUM_REDEFINED_OP_FLAG;
    if (klass == rb_cSymbol) return SYMBOL_REDEFINED_OP_FLAG;
    if (klass == rb_cTime)   return TIME_REDEFINED_OP_FLAG;
    if (klass == rb_cRegexp) return REGEXP_REDEFINED_OP_FLAG;
    return 0;
}

static void
rb_vm_check_redefinition_opt_method(const rb_method_entry_t *me, VALUE klass)
{
    st_data_t bop;
    if (!me->def || me->def->type == VM_METHOD_TYPE_CFUNC) {
	if (st_lookup(vm_opt_method_table, (st_data_t)me, &bop)) {
	    int flag = vm_redefinition_check_flag(klass);

	    ruby_vm_redefined_flag[bop] |= flag;
	}
    }
}

static int
check_redefined_method(st_data_t key, st_data_t value, st_data_t data)
{
    ID mid = (ID)key;
    rb_method_entry_t *me = (rb_method_entry_t *)value;
    VALUE klass = (VALUE)data;
    rb_method_entry_t *newme = rb_method_entry(klass, mid, NULL);

    if (newme != me)
	rb_vm_check_redefinition_opt_method(me, me->klass);
    return ST_CONTINUE;
}

void
rb_vm_check_redefinition_by_prepend(VALUE klass)
{
    if (!vm_redefinition_check_flag(klass)) return;
    st_foreach(RCLASS_M_TBL(RCLASS_ORIGIN(klass)), check_redefined_method,
	       (st_data_t)klass);
}

static void
add_opt_method(VALUE klass, ID mid, VALUE bop)
{
    rb_method_entry_t *me;
    if (st_lookup(RCLASS_M_TBL(klass), mid, (void *)&me) && me->def &&
	me->def->type == VM_METHOD_TYPE_CFUNC) {
	st_insert(vm_opt_method_table, (st_data_t)me, (st_data_t)bop);
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

#define OP(mid_, bop_) (mid = id##mid_, bop = BOP_##bop_, ruby_vm_redefined_flag[bop] = 0)
#define C(k) add_opt_method(rb_c##k, mid, bop)
    OP(PLUS, PLUS), (C(Fixnum), C(Float), C(String), C(Array));
    OP(MINUS, MINUS), (C(Fixnum), C(Float));
    OP(MULT, MULT), (C(Fixnum), C(Float));
    OP(DIV, DIV), (C(Fixnum), C(Float));
    OP(MOD, MOD), (C(Fixnum), C(Float));
    OP(Eq, EQ), (C(Fixnum), C(Float), C(String));
    OP(Eqq, EQQ), (C(Fixnum), C(Bignum), C(Float), C(Symbol), C(String));
    OP(LT, LT), (C(Fixnum), C(Float));
    OP(LE, LE), (C(Fixnum), C(Float));
    OP(GT, GT), (C(Fixnum), C(Float));
    OP(GE, GE), (C(Fixnum), C(Float));
    OP(LTLT, LTLT), (C(String), C(Array));
    OP(AREF, AREF), (C(Array), C(Hash));
    OP(ASET, ASET), (C(Array), C(Hash));
    OP(Length, LENGTH), (C(Array), C(String), C(Hash));
    OP(Size, SIZE), (C(Array), C(String), C(Hash));
    OP(EmptyP, EMPTY_P), (C(Array), C(String), C(Hash));
    OP(Succ, SUCC), (C(Fixnum), C(String), C(Time));
    OP(EqTilde, MATCH), (C(Regexp), C(String));
    OP(Freeze, FREEZE), (C(String));
#undef C
#undef OP
}

/* for vm development */

#if VMDEBUG
static const char *
vm_frametype_name(const rb_control_frame_t *cfp)
{
    switch (VM_FRAME_TYPE(cfp)) {
      case VM_FRAME_MAGIC_METHOD: return "method";
      case VM_FRAME_MAGIC_BLOCK:  return "block";
      case VM_FRAME_MAGIC_CLASS:  return "class";
      case VM_FRAME_MAGIC_TOP:    return "top";
      case VM_FRAME_MAGIC_CFUNC:  return "cfunc";
      case VM_FRAME_MAGIC_PROC:   return "proc";
      case VM_FRAME_MAGIC_IFUNC:  return "ifunc";
      case VM_FRAME_MAGIC_EVAL:   return "eval";
      case VM_FRAME_MAGIC_LAMBDA: return "lambda";
      default:
	rb_bug("unknown frame");
    }
}
#endif

/* evaluator body */

/*                  finish
  VMe (h1)          finish
    VM              finish F1 F2
      cfunc         finish F1 F2 C1
        rb_funcall  finish F1 F2 C1
          VMe       finish F1 F2 C1
            VM      finish F1 F2 C1 F3

  F1 - F3 : pushed by VM
  C1      : pushed by send insn (CFUNC)

  struct CONTROL_FRAME {
    VALUE *pc;                  // cfp[0], program counter
    VALUE *sp;                  // cfp[1], stack pointer
    VALUE *bp;                  // cfp[2], base pointer
    rb_iseq_t *iseq;            // cfp[3], iseq
    VALUE flag;                 // cfp[4], magic
    VALUE self;                 // cfp[5], self
    VALUE *ep;                  // cfp[6], env pointer
    rb_iseq_t * block_iseq;     // cfp[7], block iseq
    VALUE proc;                 // cfp[8], always 0
  };

  struct BLOCK {
    VALUE self;
    VALUE *ep;
    rb_iseq_t *block_iseq;
    VALUE proc;
  };

  struct METHOD_CONTROL_FRAME {
    rb_control_frame_t frame;
  };

  struct METHOD_FRAME {
    VALUE arg0;
    ...
    VALUE argM;
    VALUE param0;
    ...
    VALUE paramN;
    VALUE cref;
    VALUE special;                         // lep [1]
    struct block_object *block_ptr | 0x01; // lep [0]
  };

  struct BLOCK_CONTROL_FRAME {
    rb_control_frame_t frame;
  };

  struct BLOCK_FRAME {
    VALUE arg0;
    ...
    VALUE argM;
    VALUE param0;
    ...
    VALUE paramN;
    VALUE cref;
    VALUE *(prev_ptr | 0x01); // ep[0]
  };

  struct CLASS_CONTROL_FRAME {
    rb_control_frame_t frame;
  };

  struct CLASS_FRAME {
    VALUE param0;
    ...
    VALUE paramN;
    VALUE cref;
    VALUE prev_ep; // for frame jump
  };

  struct C_METHOD_CONTROL_FRAME {
    VALUE *pc;                       // 0
    VALUE *sp;                       // stack pointer
    VALUE *bp;                       // base pointer (used in exception)
    rb_iseq_t *iseq;                 // cmi
    VALUE magic;                     // C_METHOD_FRAME
    VALUE self;                      // ?
    VALUE *ep;                       // ep == lep
    rb_iseq_t * block_iseq;          //
    VALUE proc;                      // always 0
  };

  struct C_BLOCK_CONTROL_FRAME {
    VALUE *pc;                       // point only "finish" insn
    VALUE *sp;                       // sp
    rb_iseq_t *iseq;                 // ?
    VALUE magic;                     // C_METHOD_FRAME
    VALUE self;                      // needed?
    VALUE *ep;                       // ep
    rb_iseq_t * block_iseq; // 0
  };
 */


static VALUE
vm_exec(rb_thread_t *th)
{
    int state;
    VALUE result, err;
    VALUE initial = 0;

    TH_PUSH_TAG(th);
    _tag.retval = Qnil;
    if ((state = EXEC_TAG()) == 0) {
      vm_loop_start:
	result = vm_exec_core(th, initial);
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
	VALUE type;
	VALUE *escape_ep;

	err = th->errinfo;

      exception_handler:
	cont_pc = cont_sp = catch_iseqval = 0;

	while (th->cfp->pc == 0 || th->cfp->iseq == 0) {
	    if (UNLIKELY(VM_FRAME_TYPE(th->cfp) == VM_FRAME_MAGIC_CFUNC)) {
		const rb_method_entry_t *me = th->cfp->me;
		EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, th->cfp->self, me->called_id, me->klass, Qnil);
		RUBY_DTRACE_METHOD_RETURN_HOOK(th, me->klass, me->called_id);
	    }
	    th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
	}

	cfp = th->cfp;
	epc = cfp->pc - cfp->iseq->iseq_encoded;

	escape_ep = NULL;
	if (state == TAG_BREAK || state == TAG_RETURN) {
	    escape_ep = GET_THROWOBJ_CATCH_POINT(err);

	    if (cfp->ep == escape_ep) {
		if (state == TAG_RETURN) {
		    if (!VM_FRAME_TYPE_FINISH_P(cfp)) {
			SET_THROWOBJ_CATCH_POINT(err, (VALUE)(cfp + 1)->ep);
			SET_THROWOBJ_STATE(err, state = TAG_BREAK);
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
			if (!catch_iseqval) {
			    result = GET_THROWOBJ_VAL(err);
			    th->errinfo = Qnil;

			    switch (VM_FRAME_TYPE(cfp)) {
			      case VM_FRAME_MAGIC_LAMBDA:
				EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_B_RETURN, th->cfp->self, 0, 0, Qnil);
				break;
			    }

			    vm_pop_frame(th);
			    goto finish_vme;
			}
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
			VALUE *escape_ep;
			escape_ep = GET_THROWOBJ_CATCH_POINT(err);
			if (cfp->ep == escape_ep) {
			    cfp->pc = cfp->iseq->iseq_encoded + entry->cont;
			    th->errinfo = Qnil;
			    goto vm_loop_start;
			}
		    }
		}
	    }
	}
	else if (state == TAG_BREAK && ((VALUE)escape_ep & ~0x03) == 0) {
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
			cfp->sp = vm_base_ptr(cfp) + entry->sp;

			if (state != TAG_REDO) {
#if OPT_STACK_CACHING
			    initial = (GET_THROWOBJ_VAL(err));
#else
			    *th->cfp->sp++ = (GET_THROWOBJ_VAL(err));
#endif
			}
			th->errinfo = Qnil;
			th->state = 0;
			goto vm_loop_start;
		    }
		}
	    }
	}
	else if (state == TAG_REDO) {
	    type = CATCH_TYPE_REDO;
	    goto search_restart_point;
	}
	else if (state == TAG_NEXT) {
	    type = CATCH_TYPE_NEXT;
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
	    cfp->sp = vm_base_ptr(cfp) + cont_sp;
	    cfp->pc = cfp->iseq->iseq_encoded + cont_pc;

	    /* push block frame */
	    cfp->sp[0] = err;
	    vm_push_frame(th, catch_iseq, VM_FRAME_MAGIC_BLOCK,
			  cfp->self, cfp->klass,
			  VM_ENVVAL_PREV_EP_PTR(cfp->ep),
			  catch_iseq->iseq_encoded,
			  cfp->sp + 1 /* push value */,
			  catch_iseq->local_size - 1,
			  cfp->me, catch_iseq->stack_max);

	    state = 0;
	    th->state = 0;
	    th->errinfo = Qnil;
	    goto vm_loop_start;
	}
	else {
	    /* skip frame */

	    switch (VM_FRAME_TYPE(th->cfp)) {
	      case VM_FRAME_MAGIC_METHOD:
		RUBY_DTRACE_METHOD_RETURN_HOOK(th, 0, 0);
		EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_RETURN, th->cfp->self, 0, 0, Qnil);
		break;
	      case VM_FRAME_MAGIC_BLOCK:
	      case VM_FRAME_MAGIC_LAMBDA:
		if (VM_FRAME_TYPE_BMETHOD_P(th->cfp)) {
		    EXEC_EVENT_HOOK(th, RUBY_EVENT_B_RETURN, th->cfp->self, 0, 0, Qnil);
		    EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_RETURN, th->cfp->self, th->cfp->me->called_id, th->cfp->me->klass, Qnil);
		}
		else {
		    EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_B_RETURN, th->cfp->self, 0, 0, Qnil);
		}
		break;
	      case VM_FRAME_MAGIC_CLASS:
		EXEC_EVENT_HOOK_AND_POP_FRAME(th, RUBY_EVENT_END, th->cfp->self, 0, 0, Qnil);
		break;
	    }

	    if (VM_FRAME_TYPE_FINISH_P(th->cfp)) {
		vm_pop_frame(th);
		th->errinfo = err;
		TH_POP_TAG2();
		JUMP_TAG(state);
	    }
	    else {
		th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
		goto exception_handler;
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

    vm_set_top_stack(th, iseqval);

    val = vm_exec(th);
    RB_GC_GUARD(iseqval); /* prohibit tail call optimization */
    return val;
}

VALUE
rb_iseq_eval_main(VALUE iseqval)
{
    rb_thread_t *th = GET_THREAD();
    VALUE val;

    vm_set_main_stack(th, iseqval);

    val = vm_exec(th);
    RB_GC_GUARD(iseqval); /* prohibit tail call optimization */
    return val;
}

int
rb_vm_control_frame_id_and_class(const rb_control_frame_t *cfp, ID *idp, VALUE *klassp)
{
    rb_iseq_t *iseq = cfp->iseq;
    if (!iseq && cfp->me) {
	if (idp) *idp = cfp->me->def->original_id;
	if (klassp) *klassp = cfp->me->klass;
	return 1;
    }
    while (iseq) {
	if (RUBY_VM_IFUNC_P(iseq)) {
	    if (idp) *idp = idIFUNC;
	    if (klassp) *klassp = 0;
	    return 1;
	}
	if (iseq->defined_method_id) {
	    if (idp) *idp = iseq->defined_method_id;
	    if (klassp) *klassp = iseq->klass;
	    return 1;
	}
	if (iseq->local_iseq == iseq) {
	    break;
	}
	iseq = iseq->parent_iseq;
    }
    return 0;
}

int
rb_thread_method_id_and_class(rb_thread_t *th, ID *idp, VALUE *klassp)
{
    return rb_vm_control_frame_id_and_class(th->cfp, idp, klassp);
}

int
rb_frame_method_id_and_class(ID *idp, VALUE *klassp)
{
    return rb_thread_method_id_and_class(GET_THREAD(), idp, klassp);
}

VALUE
rb_thread_current_status(const rb_thread_t *th)
{
    const rb_control_frame_t *cfp = th->cfp;
    VALUE str = Qnil;

    if (cfp->iseq != 0) {
	if (cfp->pc != 0) {
	    rb_iseq_t *iseq = cfp->iseq;
	    int line_no = rb_vm_get_sourceline(cfp);
	    char *file = RSTRING_PTR(iseq->location.path);
	    str = rb_sprintf("%s:%d:in `%s'",
			     file, line_no, RSTRING_PTR(iseq->location.label));
	}
    }
    else if (cfp->me->def->original_id) {
	str = rb_sprintf("`%s#%s' (cfunc)",
			 rb_class2name(cfp->me->klass),
			 rb_id2name(cfp->me->def->original_id));
    }

    return str;
}

VALUE
rb_vm_call_cfunc(VALUE recv, VALUE (*func)(VALUE), VALUE arg,
		 const rb_block_t *blockptr, VALUE filename)
{
    rb_thread_t *th = GET_THREAD();
    const rb_control_frame_t *reg_cfp = th->cfp;
    volatile VALUE iseqval = rb_iseq_new(0, filename, filename, Qnil, 0, ISEQ_TYPE_TOP);
    VALUE val;

    vm_push_frame(th, DATA_PTR(iseqval), VM_FRAME_MAGIC_TOP | VM_FRAME_FLAG_FINISH,
		  recv, CLASS_OF(recv), VM_ENVVAL_BLOCK_PTR(blockptr), 0, reg_cfp->sp, 1, 0, 0);

    val = (*func)(arg);

    vm_pop_frame(th);
    return val;
}

/* vm */

static int
vm_mark_each_thread_func(st_data_t key, st_data_t value, st_data_t dummy)
{
    VALUE thval = (VALUE)key;
    rb_gc_mark(thval);
    return ST_CONTINUE;
}

void rb_vm_trace_mark_event_hooks(rb_hook_list_t *hooks);

void
rb_vm_mark(void *ptr)
{
    int i;

    RUBY_MARK_ENTER("vm");
    RUBY_GC_INFO("-------------------------------------------------\n");
    if (ptr) {
	rb_vm_t *vm = ptr;
	if (vm->living_threads) {
	    st_foreach(vm->living_threads, vm_mark_each_thread_func, 0);
	}
	RUBY_MARK_UNLESS_NULL(vm->thgroup_default);
	RUBY_MARK_UNLESS_NULL(vm->mark_object_ary);
	RUBY_MARK_UNLESS_NULL(vm->load_path);
	RUBY_MARK_UNLESS_NULL(vm->load_path_snapshot);
	RUBY_MARK_UNLESS_NULL(vm->load_path_check_cache);
	RUBY_MARK_UNLESS_NULL(vm->expanded_load_path);
	RUBY_MARK_UNLESS_NULL(vm->loaded_features);
	RUBY_MARK_UNLESS_NULL(vm->loaded_features_snapshot);
	RUBY_MARK_UNLESS_NULL(vm->top_self);
	RUBY_MARK_UNLESS_NULL(vm->coverages);
	RUBY_MARK_UNLESS_NULL(vm->defined_module_hash);
	rb_gc_mark_locations(vm->special_exceptions, vm->special_exceptions + ruby_special_error_count);

	if (vm->loading_table) {
	    rb_mark_tbl(vm->loading_table);
	}

	rb_vm_trace_mark_event_hooks(&vm->event_hooks);

	for (i = 0; i < RUBY_NSIG; i++) {
	    if (vm->trap_list[i].cmd)
		rb_gc_mark(vm->trap_list[i].cmd);
	}
	if (vm->defined_strings) {
	    rb_gc_mark_locations(vm->defined_strings, vm->defined_strings + DEFINED_EXPR);
	}
    }

    RUBY_MARK_LEAVE("vm");
}


int
rb_vm_add_root_module(ID id, VALUE module)
{
    rb_vm_t *vm = GET_VM();
    if (vm->defined_module_hash) {
	rb_hash_aset(vm->defined_module_hash, ID2SYM(id), module);
    }
    return TRUE;
}

#define vm_free 0

int
ruby_vm_destruct(rb_vm_t *vm)
{
    RUBY_FREE_ENTER("vm");
    if (vm) {
	rb_thread_t *th = vm->main_thread;
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
	struct rb_objspace *objspace = vm->objspace;
#endif
	rb_gc_force_recycle(vm->self);
	vm->main_thread = 0;
	if (th) {
	    rb_fiber_reset_root_local_storage(th->self);
	    thread_free(th);
	}
	if (vm->living_threads) {
	    st_free_table(vm->living_threads);
	    vm->living_threads = 0;
	}
	ruby_vm_run_at_exit_hooks(vm);
	rb_vm_gvl_destroy(vm);
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
	if (objspace) {
	    rb_objspace_free(objspace);
	}
#endif
	/* after freeing objspace, you *can't* use ruby_xfree() */
	ruby_mimfree(vm);
	ruby_current_vm = 0;
    }
    RUBY_FREE_LEAVE("vm");
    return 0;
}

static size_t
vm_memsize(const void *ptr)
{
    if (ptr) {
	const rb_vm_t *vmobj = ptr;
	size_t size = sizeof(rb_vm_t);
	if (vmobj->living_threads) {
	    size += st_memsize(vmobj->living_threads);
	}
	if (vmobj->defined_strings) {
	    size += DEFINED_EXPR * sizeof(VALUE);
	}
	return size;
    }
    else {
	return 0;
    }
}

static const rb_data_type_t vm_data_type = {
    "VM",
    {rb_vm_mark, vm_free, vm_memsize,},
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
};


static VALUE
vm_default_params(void)
{
    rb_vm_t *vm = GET_VM();
    VALUE result = rb_hash_new();
#define SET(name) rb_hash_aset(result, ID2SYM(rb_intern(#name)), SIZET2NUM(vm->default_params.name));
    SET(thread_vm_stack_size);
    SET(thread_machine_stack_size);
    SET(fiber_vm_stack_size);
    SET(fiber_machine_stack_size);
#undef SET
    rb_obj_freeze(result);
    return result;
}

static size_t
get_param(const char *name, size_t default_value, size_t min_value)
{
    const char *envval;
    size_t result = default_value;
    if ((envval = getenv(name)) != 0) {
	long val = atol(envval);
	if (val < (long)min_value) {
	    val = (long)min_value;
	}
	result = (size_t)(((val -1 + RUBY_VM_SIZE_ALIGN) / RUBY_VM_SIZE_ALIGN) * RUBY_VM_SIZE_ALIGN);
    }
    if (0) fprintf(stderr, "%s: %"PRIdSIZE"\n", name, result); /* debug print */

    return result;
}

static void
check_machine_stack_size(size_t *sizep)
{
#ifdef PTHREAD_STACK_MIN
    size_t size = *sizep;
#endif

#ifdef __SYMBIAN32__
    *sizep = 64 * 1024; /* 64KB: Let's be slightly more frugal on mobile platform */
#endif

#ifdef PTHREAD_STACK_MIN
    if (size < PTHREAD_STACK_MIN) {
	*sizep = PTHREAD_STACK_MIN * 2;
    }
#endif
}

static void
vm_default_params_setup(rb_vm_t *vm)
{
    vm->default_params.thread_vm_stack_size =
      get_param("RUBY_THREAD_VM_STACK_SIZE",
		RUBY_VM_THREAD_VM_STACK_SIZE,
		RUBY_VM_THREAD_VM_STACK_SIZE_MIN);

    vm->default_params.thread_machine_stack_size =
      get_param("RUBY_THREAD_MACHINE_STACK_SIZE",
		RUBY_VM_THREAD_MACHINE_STACK_SIZE,
		RUBY_VM_THREAD_MACHINE_STACK_SIZE_MIN);

    vm->default_params.fiber_vm_stack_size =
      get_param("RUBY_FIBER_VM_STACK_SIZE",
		RUBY_VM_FIBER_VM_STACK_SIZE,
		RUBY_VM_FIBER_VM_STACK_SIZE_MIN);

    vm->default_params.fiber_machine_stack_size =
      get_param("RUBY_FIBER_MACHINE_STACK_SIZE",
		RUBY_VM_FIBER_MACHINE_STACK_SIZE,
		RUBY_VM_FIBER_MACHINE_STACK_SIZE_MIN);

    /* environment dependent check */
    check_machine_stack_size(&vm->default_params.thread_machine_stack_size);
    check_machine_stack_size(&vm->default_params.fiber_machine_stack_size);
}

static void
vm_init2(rb_vm_t *vm)
{
    MEMZERO(vm, rb_vm_t, 1);
    vm->src_encoding_index = -1;
    vm->at_exit.basic.flags = (T_ARRAY | RARRAY_EMBED_FLAG) & ~RARRAY_EMBED_LEN_MASK; /* len set 0 */
    rb_obj_hide((VALUE)&vm->at_exit);

    vm_default_params_setup(vm);
}

/* Thread */

#define USE_THREAD_DATA_RECYCLE 1

#if USE_THREAD_DATA_RECYCLE
#define RECYCLE_MAX 64
static VALUE *thread_recycle_stack_slot[RECYCLE_MAX];
static int thread_recycle_stack_count = 0;

static VALUE *
thread_recycle_stack(size_t size)
{
    if (thread_recycle_stack_count) {
	/* TODO: check stack size if stack sizes are variable */
	return thread_recycle_stack_slot[--thread_recycle_stack_count];
    }
    else {
	return ALLOC_N(VALUE, size);
    }
}

#else
#define thread_recycle_stack(size) ALLOC_N(VALUE, (size))
#endif

void
rb_thread_recycle_stack_release(VALUE *stack)
{
#if USE_THREAD_DATA_RECYCLE
    if (thread_recycle_stack_count < RECYCLE_MAX) {
	thread_recycle_stack_slot[thread_recycle_stack_count++] = stack;
	return;
    }
#endif
    ruby_xfree(stack);
}

#ifdef USE_THREAD_RECYCLE
static rb_thread_t *
thread_recycle_struct(void)
{
    void *p = ALLOC_N(rb_thread_t, 1);
    memset(p, 0, sizeof(rb_thread_t));
    return p;
}
#endif

void
rb_thread_mark(void *ptr)
{
    rb_thread_t *th = NULL;
    RUBY_MARK_ENTER("thread");
    if (ptr) {
	th = ptr;
	if (th->stack) {
	    VALUE *p = th->stack;
	    VALUE *sp = th->cfp->sp;
	    rb_control_frame_t *cfp = th->cfp;
	    rb_control_frame_t *limit_cfp = (void *)(th->stack + th->stack_size);

	    while (p < sp) {
		rb_gc_mark(*p++);
	    }
	    rb_gc_mark_locations(p, p + th->mark_stack_len);

	    while (cfp != limit_cfp) {
		rb_iseq_t *iseq = cfp->iseq;
		rb_gc_mark(cfp->proc);
		rb_gc_mark(cfp->self);
		rb_gc_mark(cfp->klass);
		if (iseq) {
		    rb_gc_mark(RUBY_VM_NORMAL_ISEQ_P(iseq) ? iseq->self : (VALUE)iseq);
		}
		if (cfp->me) {
		    /* TODO: marking `me' can be more sophisticated way */
		    ((rb_method_entry_t *)cfp->me)->mark = 1;
		    rb_mark_method_entry(cfp->me);
		}
		cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	    }
	}

	/* mark ruby objects */
	RUBY_MARK_UNLESS_NULL(th->first_proc);
	if (th->first_proc) RUBY_MARK_UNLESS_NULL(th->first_args);

	RUBY_MARK_UNLESS_NULL(th->thgroup);
	RUBY_MARK_UNLESS_NULL(th->value);
	RUBY_MARK_UNLESS_NULL(th->errinfo);
	RUBY_MARK_UNLESS_NULL(th->pending_interrupt_queue);
	RUBY_MARK_UNLESS_NULL(th->pending_interrupt_mask_stack);
	RUBY_MARK_UNLESS_NULL(th->root_svar);
	RUBY_MARK_UNLESS_NULL(th->top_self);
	RUBY_MARK_UNLESS_NULL(th->top_wrapper);
	RUBY_MARK_UNLESS_NULL(th->fiber);
	RUBY_MARK_UNLESS_NULL(th->root_fiber);
	RUBY_MARK_UNLESS_NULL(th->stat_insn_usage);
	RUBY_MARK_UNLESS_NULL(th->last_status);

	RUBY_MARK_UNLESS_NULL(th->locking_mutex);

	rb_mark_tbl(th->local_storage);

	if (GET_THREAD() != th && th->machine.stack_start && th->machine.stack_end) {
	    rb_gc_mark_machine_stack(th);
	    rb_gc_mark_locations((VALUE *)&th->machine.regs,
				 (VALUE *)(&th->machine.regs) +
				 sizeof(th->machine.regs) / sizeof(VALUE));
	}

	rb_vm_trace_mark_event_hooks(&th->event_hooks);
    }

    RUBY_MARK_LEAVE("thread");
}

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

	if (th->locking_mutex != Qfalse) {
	    rb_bug("thread_free: locking_mutex must be NULL (%p:%p)", (void *)th, (void *)th->locking_mutex);
	}
	if (th->keeping_mutexes != NULL) {
	    rb_bug("thread_free: keeping_mutexes must be NULL (%p:%p)", (void *)th, (void *)th->keeping_mutexes);
	}

	if (th->local_storage) {
	    st_free_table(th->local_storage);
	}

	if (th->vm && th->vm->main_thread == th) {
	    RUBY_GC_INFO("main thread\n");
	}
	else {
#ifdef USE_SIGALTSTACK
	    if (th->altstack) {
		free(th->altstack);
	    }
#endif
	    ruby_xfree(ptr);
	}
        if (ruby_current_thread == th)
            ruby_current_thread = NULL;
    }
    RUBY_FREE_LEAVE("thread");
}

static size_t
thread_memsize(const void *ptr)
{
    if (ptr) {
	const rb_thread_t *th = ptr;
	size_t size = sizeof(rb_thread_t);

	if (!th->root_fiber) {
	    size += th->stack_size * sizeof(VALUE);
	}
	if (th->local_storage) {
	    size += st_memsize(th->local_storage);
	}
	return size;
    }
    else {
	return 0;
    }
}

#define thread_data_type ruby_threadptr_data_type
const rb_data_type_t ruby_threadptr_data_type = {
    "VM/thread",
    {
	rb_thread_mark,
	thread_free,
	thread_memsize,
    },
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
};

VALUE
rb_obj_is_thread(VALUE obj)
{
    if (rb_typeddata_is_kind_of(obj, &thread_data_type)) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

static VALUE
thread_alloc(VALUE klass)
{
    VALUE volatile obj;
#ifdef USE_THREAD_RECYCLE
    rb_thread_t *th = thread_recycle_struct();
    obj = TypedData_Wrap_Struct(klass, &thread_data_type, th);
#else
    rb_thread_t *th;
    obj = TypedData_Make_Struct(klass, rb_thread_t, &thread_data_type, th);
#endif
    return obj;
}

static void
th_init(rb_thread_t *th, VALUE self)
{
    th->self = self;

    /* allocate thread stack */
#ifdef USE_SIGALTSTACK
    /* altstack of main thread is reallocated in another place */
    th->altstack = malloc(rb_sigaltstack_size());
#endif
    /* th->stack_size is word number.
     * th->vm->default_params.thread_vm_stack_size is byte size.
     */
    th->stack_size = th->vm->default_params.thread_vm_stack_size / sizeof(VALUE);
    th->stack = thread_recycle_stack(th->stack_size);

    th->cfp = (void *)(th->stack + th->stack_size);

    vm_push_frame(th, 0 /* dummy iseq */, VM_FRAME_MAGIC_TOP | VM_FRAME_FLAG_FINISH,
		  Qnil /* dummy self */, Qnil /* dummy klass */, VM_ENVVAL_BLOCK_PTR(0), 0 /* dummy pc */, th->stack, 1, 0, 0);

    th->status = THREAD_RUNNABLE;
    th->errinfo = Qnil;
    th->last_status = Qnil;
    th->waiting_fd = -1;
    th->root_svar = Qnil;

#if OPT_CALL_THREADED_CODE
    th->retval = Qundef;
#endif
}

static VALUE
ruby_thread_init(VALUE self)
{
    rb_thread_t *th;
    rb_vm_t *vm = GET_THREAD()->vm;
    GetThreadPtr(self, th);

    th->vm = vm;
    th_init(th, self);
    rb_ivar_set(self, rb_intern("locals"), rb_hash_new());

    th->top_wrapper = 0;
    th->top_self = rb_vm_top_self();
    th->root_svar = Qnil;
    return self;
}

VALUE
rb_thread_alloc(VALUE klass)
{
    VALUE self = thread_alloc(klass);
    ruby_thread_init(self);
    return self;
}

static void
vm_define_method(rb_thread_t *th, VALUE obj, ID id, VALUE iseqval,
		 rb_num_t is_singleton, NODE *cref)
{
    VALUE klass = cref->nd_clss;
    int noex = (int)cref->nd_visi;
    rb_iseq_t *miseq;
    GetISeqPtr(iseqval, miseq);

    if (miseq->klass) {
	RB_GC_GUARD(iseqval) = rb_iseq_clone(iseqval, 0);
	GetISeqPtr(iseqval, miseq);
    }

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class/module to add method");
    }

    if (is_singleton) {
	klass = rb_singleton_class(obj); /* class and frozen checked in this API */
	noex = NOEX_PUBLIC;
    }

    /* dup */
    COPY_CREF(miseq->cref_stack, cref);
    miseq->cref_stack->nd_visi = NOEX_PUBLIC;
    RB_OBJ_WRITE(miseq->self, &miseq->klass, klass);
    miseq->defined_method_id = id;
    rb_add_method(klass, id, VM_METHOD_TYPE_ISEQ, miseq, noex);

    if (!is_singleton && noex == NOEX_MODFUNC) {
	klass = rb_singleton_class(klass);
	rb_add_method(klass, id, VM_METHOD_TYPE_ISEQ, miseq, NOEX_PUBLIC);
    }
}

#define REWIND_CFP(expr) do { \
    rb_thread_t *th__ = GET_THREAD(); \
    th__->cfp++; expr; th__->cfp--; \
} while (0)

static VALUE
m_core_define_method(VALUE self, VALUE cbase, VALUE sym, VALUE iseqval)
{
    REWIND_CFP({
	vm_define_method(GET_THREAD(), cbase, SYM2ID(sym), iseqval, 0, rb_vm_cref());
    });
    return sym;
}

static VALUE
m_core_define_singleton_method(VALUE self, VALUE cbase, VALUE sym, VALUE iseqval)
{
    REWIND_CFP({
	vm_define_method(GET_THREAD(), cbase, SYM2ID(sym), iseqval, 1, rb_vm_cref());
    });
    return sym;
}

static VALUE
m_core_set_method_alias(VALUE self, VALUE cbase, VALUE sym1, VALUE sym2)
{
    REWIND_CFP({
	rb_alias(cbase, SYM2ID(sym1), SYM2ID(sym2));
    });
    return Qnil;
}

static VALUE
m_core_set_variable_alias(VALUE self, VALUE sym1, VALUE sym2)
{
    REWIND_CFP({
	rb_alias_variable(SYM2ID(sym1), SYM2ID(sym2));
    });
    return Qnil;
}

static VALUE
m_core_undef_method(VALUE self, VALUE cbase, VALUE sym)
{
    REWIND_CFP({
	rb_undef(cbase, SYM2ID(sym));
	rb_clear_method_cache_by_class(self);
    });
    return Qnil;
}

static VALUE
m_core_set_postexe(VALUE self)
{
    rb_set_end_proc(rb_call_end_proc, rb_block_proc());
    return Qnil;
}

static VALUE
m_core_hash_from_ary(VALUE self, VALUE ary)
{
    VALUE hash = rb_hash_new();
    int i;

    if (RUBY_DTRACE_HASH_CREATE_ENABLED()) {
	RUBY_DTRACE_HASH_CREATE(RARRAY_LEN(ary), rb_sourcefile(), rb_sourceline());
    }

    assert(RARRAY_LEN(ary) % 2 == 0);
    for (i=0; i<RARRAY_LEN(ary); i+=2) {
	rb_hash_aset(hash, RARRAY_AREF(ary, i), RARRAY_AREF(ary, i+1));
    }

    return hash;
}

static VALUE
m_core_hash_merge_ary(VALUE self, VALUE hash, VALUE ary)
{
    int i;

    assert(RARRAY_LEN(ary) % 2 == 0);
    for (i=0; i<RARRAY_LEN(ary); i+=2) {
	rb_hash_aset(hash, RARRAY_AREF(ary, i), RARRAY_AREF(ary, i+1));
    }

    return hash;
}

static VALUE
m_core_hash_merge_ptr(int argc, VALUE *argv, VALUE recv)
{
    int i;
    VALUE hash = argv[0];

    for (i=1; i<argc; i+=2) {
	rb_hash_aset(hash, argv[i], argv[i+1]);
    }

    return hash;
}

static int
kwmerge_ii(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    if (existing) return ST_STOP;
    *value = arg;
    return ST_CONTINUE;
}

static int
kwmerge_i(VALUE key, VALUE value, VALUE hash)
{
    if (!SYMBOL_P(key)) Check_Type(key, T_SYMBOL);
    if (st_update(RHASH_TBL_RAW(hash), key, kwmerge_ii, (st_data_t)value) == 0) { /* !existing */
	RB_OBJ_WRITTEN(hash, Qundef, value);
    }
    return ST_CONTINUE;
}

static int
kwcheck_i(VALUE key, VALUE value, VALUE hash)
{
    if (!SYMBOL_P(key)) Check_Type(key, T_SYMBOL);
    return ST_CONTINUE;
}

static VALUE
m_core_hash_merge_kwd(int argc, VALUE *argv, VALUE recv)
{
    VALUE hash, kw;
    rb_check_arity(argc, 1, 2);
    hash = argv[0];
    kw = argv[argc-1];
    kw = rb_convert_type(kw, T_HASH, "Hash", "to_hash");
    rb_hash_foreach(kw, argc < 2 ? kwcheck_i : kwmerge_i, hash);
    return hash;
}

extern VALUE *rb_gc_stack_start;
extern size_t rb_gc_stack_maxsize;
#ifdef __ia64
extern VALUE *rb_gc_register_stack_start;
#endif

/* debug functions */

/* :nodoc: */
static VALUE
sdr(void)
{
    rb_vm_bugreport();
    return Qnil;
}

/* :nodoc: */
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
    free(syms); /* OK */
#endif
    return ary;
}

#if VM_COLLECT_USAGE_DETAILS
static VALUE usage_analysis_insn_stop(VALUE self);
static VALUE usage_analysis_operand_stop(VALUE self);
static VALUE usage_analysis_register_stop(VALUE self);
#endif

void
Init_VM(void)
{
    VALUE opts;
    VALUE klass;
    VALUE fcore;

    /* ::RubyVM */
    rb_cRubyVM = rb_define_class("RubyVM", rb_cObject);
    rb_undef_alloc_func(rb_cRubyVM);
    rb_undef_method(CLASS_OF(rb_cRubyVM), "new");
    rb_define_singleton_method(rb_cRubyVM, "stat", vm_stat, -1);

    /* FrozenCore (hidden) */
    fcore = rb_class_new(rb_cBasicObject);
    RBASIC(fcore)->flags = T_ICLASS;
    klass = rb_singleton_class(fcore);
    rb_define_method_id(klass, id_core_set_method_alias, m_core_set_method_alias, 3);
    rb_define_method_id(klass, id_core_set_variable_alias, m_core_set_variable_alias, 2);
    rb_define_method_id(klass, id_core_undef_method, m_core_undef_method, 2);
    rb_define_method_id(klass, id_core_define_method, m_core_define_method, 3);
    rb_define_method_id(klass, id_core_define_singleton_method, m_core_define_singleton_method, 3);
    rb_define_method_id(klass, id_core_set_postexe, m_core_set_postexe, 0);
    rb_define_method_id(klass, id_core_hash_from_ary, m_core_hash_from_ary, 1);
    rb_define_method_id(klass, id_core_hash_merge_ary, m_core_hash_merge_ary, 2);
    rb_define_method_id(klass, id_core_hash_merge_ptr, m_core_hash_merge_ptr, -1);
    rb_define_method_id(klass, id_core_hash_merge_kwd, m_core_hash_merge_kwd, -1);
    rb_define_method_id(klass, idProc, rb_block_proc, 0);
    rb_define_method_id(klass, idLambda, rb_block_lambda, 0);
    rb_obj_freeze(fcore);
    RBASIC_CLEAR_CLASS(klass);
    RCLASS_SET_SUPER(klass, 0);
    rb_obj_freeze(klass);
    rb_gc_register_mark_object(fcore);
    rb_mRubyVMFrozenCore = fcore;

    /* ::RubyVM::Env */
    rb_cEnv = rb_define_class_under(rb_cRubyVM, "Env", rb_cObject);
    rb_undef_alloc_func(rb_cEnv);
    rb_undef_method(CLASS_OF(rb_cEnv), "new");

    /*
     * Document-class: Thread
     *
     *	Threads are the Ruby implementation for a concurrent programming model.
     *
     *	Programs that require multiple threads of execution are a perfect
     *	candidate for Ruby's Thread class.
     *
     *	For example, we can create a new thread separate from the main thread's
     *	execution using ::new.
     *
     *	    thr = Thread.new { puts "Whats the big deal" }
     *
     *	Then we are able to pause the execution of the main thread and allow
     *	our new thread to finish, using #join:
     *
     *	    thr.join #=> "Whats the big deal"
     *
     *	If we don't call +thr.join+ before the main thread terminates, then all
     *	other threads including +thr+ will be killed.
     *
     *	Alternatively, you can use an array for handling multiple threads at
     *	once, like in the following example:
     *
     *	    threads = []
     *	    threads << Thread.new { puts "Whats the big deal" }
     *	    threads << Thread.new { 3.times { puts "Threads are fun!" } }
     *
     *	After creating a few threads we wait for them all to finish
     *	consecutively.
     *
     *	    threads.each { |thr| thr.join }
     *
     *	=== Thread initialization
     *
     *	In order to create new threads, Ruby provides ::new, ::start, and
     *	::fork. A block must be provided with each of these methods, otherwise
     *	a ThreadError will be raised.
     *
     *	When subclassing the Thread class, the +initialize+ method of your
     *	subclass will be ignored by ::start and ::fork. Otherwise, be sure to
     *	call super in your +initialize+ method.
     *
     * 	=== Thread termination
     *
     * 	For terminating threads, Ruby provides a variety of ways to do this.
     *
     *	The class method ::kill, is meant to exit a given thread:
     *
     *	    thr = Thread.new { ... }
     *	    Thread.kill(thr) # sends exit() to thr
     *
     *	Alternatively, you can use the instance method #exit, or any of its
     *	aliases #kill or #terminate.
     *
     *	    thr.exit
     *
     * 	=== Thread status
     *
     * 	Ruby provides a few instance methods for querying the state of a given
     * 	thread. To get a string with the current thread's state use #status
     *
     *	    thr = Thread.new { sleep }
     *	    thr.status # => "sleep"
     *	    thr.exit
     *	    thr.status # => false
     *
     *	You can also use #alive? to tell if the thread is running or sleeping,
     *	and #stop? if the thread is dead or sleeping.
     *
     * 	=== Thread variables and scope
     *
     * 	Since threads are created with blocks, the same rules apply to other
     * 	Ruby blocks for variable scope. Any local variables created within this
     * 	block are accessible to only this thread.
     *
     * 	==== Fiber-local vs. Thread-local
     *
     *	Each fiber has its own bucket for Thread#[] storage. When you set a
     *	new fiber-local it is only accessible within this Fiber. To illustrate:
     *
     *	    Thread.new {
     *	      Thread.current[:foo] = "bar"
     *	      Fiber.new {
     *	        p Thread.current[:foo] # => nil
     *	      }.resume
     *	    }.join
     *
     * 	This example uses #[] for getting and #[]= for setting fiber-locals,
     * 	you can also use #keys to list the fiber-locals for a given
     * 	thread and #key? to check if a fiber-local exists.
     *
     *	When it comes to thread-locals, they are accessible within the entire
     *	scope of the thread. Given the following example:
     *
     *	    Thread.new{
     *	      Thread.current.thread_variable_set(:foo, 1)
     *	      p Thread.current.thread_variable_get(:foo) # => 1
     *	      Fiber.new{
     *		Thread.current.thread_variable_set(:foo, 2)
     *		p Thread.current.thread_variable_get(:foo) # => 2
     *	      }.resume
     *	      p Thread.current.thread_variable_get(:foo)   # => 2
     *	    }.join
     *
     *  You can see that the thread-local +:foo+ carried over into the fiber
     *  and was changed to +2+ by the end of the thread.
     *
     *  This example makes use of #thread_variable_set to create new
     *  thread-locals, and #thread_variable_get to reference them.
     *
     *  There is also #thread_variables to list all thread-locals, and
     *  #thread_variable? to check if a given thread-local exists.
     *
     * 	=== Exception handling
     *
     *	Any thread can raise an exception using the #raise instance method,
     *	which operates similarly to Kernel#raise.
     *
     *	However, it's important to note that an exception that occurs in any
     *	thread except the main thread depends on #abort_on_exception. This
     *	option is +false+ by default, meaning that any unhandled exception will
     *	cause the thread to terminate silently when waited on by either #join
     *	or #value. You can change this default by either #abort_on_exception=
     *	+true+ or setting $DEBUG to +true+.
     *
     *	With the addition of the class method ::handle_interrupt, you can now
     *	handle exceptions asynchronously with threads.
     *
     * 	=== Scheduling
     *
     * 	Ruby provides a few ways to support scheduling threads in your program.
     *
     * 	The first way is by using the class method ::stop, to put the current
     * 	running thread to sleep and schedule the execution of another thread.
     *
     * 	Once a thread is asleep, you can use the instance method #wakeup to
     * 	mark your thread as eligible for scheduling.
     *
     * 	You can also try ::pass, which attempts to pass execution to another
     * 	thread but is dependent on the OS whether a running thread will switch
     * 	or not. The same goes for #priority, which lets you hint to the thread
     * 	scheduler which threads you want to take precedence when passing
     * 	execution. This method is also dependent on the OS and may be ignored
     * 	on some platforms.
     *
     */
    rb_cThread = rb_define_class("Thread", rb_cObject);
    rb_undef_alloc_func(rb_cThread);

#if VM_COLLECT_USAGE_DETAILS
    /* ::RubyVM::USAGE_ANALYSIS_* */
#define define_usage_analysis_hash(name) /* shut up rdoc -C */ \
    rb_define_const(rb_cRubyVM, "USAGE_ANALYSIS_"#name, rb_hash_new())
    define_usage_analysis_hash("INSN");
    define_usage_analysis_hash("REGS");
    define_usage_analysis_hash("INSN_BIGRAM");

    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_INSN_STOP", usage_analysis_insn_stop, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_OPERAND_STOP", usage_analysis_operand_stop, 0);
    rb_define_singleton_method(rb_cRubyVM, "USAGE_ANALYSIS_REGISTER_STOP", usage_analysis_register_stop, 0);
#endif

    /* ::RubyVM::OPTS, which shows vm build options */
    rb_define_const(rb_cRubyVM, "OPTS", opts = rb_ary_new());

#if   OPT_DIRECT_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("direct threaded code"));
#elif OPT_TOKEN_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("token threaded code"));
#elif OPT_CALL_THREADED_CODE
    rb_ary_push(opts, rb_str_new2("call threaded code"));
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

    /* ::RubyVM::INSTRUCTION_NAMES */
    rb_define_const(rb_cRubyVM, "INSTRUCTION_NAMES", rb_insns_name_array());

    /* ::RubyVM::DEFAULT_PARAMS
     * This constant variable shows VM's default parameters.
     * Note that changing these values does not affect VM execution.
     * Specification is not stable and you should not depend on this value.
     * Of course, this constant is MRI specific.
     */
    rb_define_const(rb_cRubyVM, "DEFAULT_PARAMS", vm_default_params());

    /* debug functions ::RubyVM::SDR(), ::RubyVM::NSDR() */
#if VMDEBUG
    rb_define_singleton_method(rb_cRubyVM, "SDR", sdr, 0);
    rb_define_singleton_method(rb_cRubyVM, "NSDR", nsdr, 0);
#else
    (void)sdr;
    (void)nsdr;
#endif

    /* VM bootstrap: phase 2 */
    {
	rb_vm_t *vm = ruby_current_vm;
	rb_thread_t *th = GET_THREAD();
	VALUE filename = rb_str_new2("<main>");
	volatile VALUE iseqval = rb_iseq_new(0, filename, filename, Qnil, 0, ISEQ_TYPE_TOP);
        volatile VALUE th_self;
	rb_iseq_t *iseq;

	/* create vm object */
	vm->self = TypedData_Wrap_Struct(rb_cRubyVM, &vm_data_type, vm);

	/* create main thread */
	th_self = th->self = TypedData_Wrap_Struct(rb_cThread, &thread_data_type, th);
	rb_iv_set(th_self, "locals", rb_hash_new());
	vm->main_thread = th;
	vm->running_thread = th;
	th->vm = vm;
	th->top_wrapper = 0;
	th->top_self = rb_vm_top_self();
	rb_thread_set_current(th);

	vm->living_threads = st_init_numtable();
	st_insert(vm->living_threads, th_self, (st_data_t) th->thread_id);

	rb_gc_register_mark_object(iseqval);
	GetISeqPtr(iseqval, iseq);
	th->cfp->iseq = iseq;
	th->cfp->pc = iseq->iseq_encoded;
	th->cfp->self = th->top_self;
	th->cfp->klass = Qnil;

	/*
	 * The Binding of the top level scope
	 */
	rb_define_global_const("TOPLEVEL_BINDING", rb_binding_new());
    }
    vm_init_redefined_flag();

    /* vm_backtrace.c */
    Init_vm_backtrace();
    VM_PROFILE_ATEXIT();
}

void
rb_vm_set_progname(VALUE filename)
{
    rb_thread_t *th = GET_VM()->main_thread;
    rb_control_frame_t *cfp = (void *)(th->stack + th->stack_size);
    --cfp;
    RB_OBJ_WRITE(cfp->iseq->self, &cfp->iseq->location.path, filename);
}

#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
struct rb_objspace *rb_objspace_alloc(void);
#endif

void
Init_BareVM(void)
{
    /* VM bootstrap: phase 1 */
    rb_vm_t * vm = ruby_mimmalloc(sizeof(*vm));
    rb_thread_t * th = ruby_mimmalloc(sizeof(*th));
    if (!vm || !th) {
	fprintf(stderr, "[FATAL] failed to allocate memory\n");
	exit(EXIT_FAILURE);
    }
    MEMZERO(th, rb_thread_t, 1);
    rb_thread_set_current_raw(th);

    vm_init2(vm);
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
    vm->objspace = rb_objspace_alloc();
#endif
    ruby_current_vm = vm;

    Init_native_thread();
    th->vm = vm;
    th_init(th, 0);
    ruby_thread_init_stack(th);
    vm->defined_module_hash = rb_hash_new();
}

/* top self */

static VALUE
main_to_s(VALUE obj)
{
    return rb_str_new2("main");
}

VALUE
rb_vm_top_self(void)
{
    return GET_VM()->top_self;
}

void
Init_top_self(void)
{
    rb_vm_t *vm = GET_VM();

    vm->top_self = rb_obj_alloc(rb_cObject);
    rb_define_singleton_method(rb_vm_top_self(), "to_s", main_to_s, 0);
    rb_define_alias(rb_singleton_class(rb_vm_top_self()), "inspect", "to_s");

    /* initialize mark object array, hash */
    vm->mark_object_ary = rb_ary_tmp_new(1);
}

VALUE *
ruby_vm_verbose_ptr(rb_vm_t *vm)
{
    return &vm->verbose;
}

VALUE *
ruby_vm_debug_ptr(rb_vm_t *vm)
{
    return &vm->debug;
}

VALUE *
rb_ruby_verbose_ptr(void)
{
    return ruby_vm_verbose_ptr(GET_VM());
}

VALUE *
rb_ruby_debug_ptr(void)
{
    return ruby_vm_debug_ptr(GET_VM());
}

/* iseq.c */
VALUE rb_insn_operand_intern(rb_iseq_t *iseq,
			     VALUE insn, int op_no, VALUE op,
			     int len, size_t pos, VALUE *pnop, VALUE child);

#if VM_COLLECT_USAGE_DETAILS

#define HASH_ASET(h, k, v) rb_hash_aset((h), (st_data_t)(k), (st_data_t)(v))

/* uh = {
 *   insn(Fixnum) => ihash(Hash)
 * }
 * ihash = {
 *   -1(Fixnum) => count,      # insn usage
 *    0(Fixnum) => ophash,     # operand usage
 * }
 * ophash = {
 *   val(interned string) => count(Fixnum)
 * }
 */
static void
vm_analysis_insn(int insn)
{
    ID usage_hash;
    ID bigram_hash;
    static int prev_insn = -1;

    VALUE uh;
    VALUE ihash;
    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_INSN");
    CONST_ID(bigram_hash, "USAGE_ANALYSIS_INSN_BIGRAM");
    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((ihash = rb_hash_aref(uh, INT2FIX(insn))) == Qnil) {
	ihash = rb_hash_new();
	HASH_ASET(uh, INT2FIX(insn), ihash);
    }
    if ((cv = rb_hash_aref(ihash, INT2FIX(-1))) == Qnil) {
	cv = INT2FIX(0);
    }
    HASH_ASET(ihash, INT2FIX(-1), INT2FIX(FIX2INT(cv) + 1));

    /* calc bigram */
    if (prev_insn != -1) {
	VALUE bi;
	VALUE ary[2];
	VALUE cv;

	ary[0] = INT2FIX(prev_insn);
	ary[1] = INT2FIX(insn);
	bi = rb_ary_new4(2, &ary[0]);

	uh = rb_const_get(rb_cRubyVM, bigram_hash);
	if ((cv = rb_hash_aref(uh, bi)) == Qnil) {
	    cv = INT2FIX(0);
	}
	HASH_ASET(uh, bi, INT2FIX(FIX2INT(cv) + 1));
    }
    prev_insn = insn;
}

static void
vm_analysis_operand(int insn, int n, VALUE op)
{
    ID usage_hash;

    VALUE uh;
    VALUE ihash;
    VALUE ophash;
    VALUE valstr;
    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_INSN");

    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((ihash = rb_hash_aref(uh, INT2FIX(insn))) == Qnil) {
	ihash = rb_hash_new();
	HASH_ASET(uh, INT2FIX(insn), ihash);
    }
    if ((ophash = rb_hash_aref(ihash, INT2FIX(n))) == Qnil) {
	ophash = rb_hash_new();
	HASH_ASET(ihash, INT2FIX(n), ophash);
    }
    /* intern */
    valstr = rb_insn_operand_intern(GET_THREAD()->cfp->iseq, insn, n, op, 0, 0, 0, 0);

    /* set count */
    if ((cv = rb_hash_aref(ophash, valstr)) == Qnil) {
	cv = INT2FIX(0);
    }
    HASH_ASET(ophash, valstr, INT2FIX(FIX2INT(cv) + 1));
}

static void
vm_analysis_register(int reg, int isset)
{
    ID usage_hash;
    VALUE uh;
    VALUE valstr;
    static const char regstrs[][5] = {
	"pc",			/* 0 */
	"sp",			/* 1 */
	"ep",                   /* 2 */
	"cfp",			/* 3 */
	"self",			/* 4 */
	"iseq",			/* 5 */
    };
    static const char getsetstr[][4] = {
	"get",
	"set",
    };
    static VALUE syms[sizeof(regstrs) / sizeof(regstrs[0])][2];

    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_REGS");
    if (syms[0] == 0) {
	char buff[0x10];
	int i;

	for (i = 0; i < (int)(sizeof(regstrs) / sizeof(regstrs[0])); i++) {
	    int j;
	    for (j = 0; j < 2; j++) {
		snprintf(buff, 0x10, "%d %s %-4s", i, getsetstr[j], regstrs[i]);
		syms[i][j] = ID2SYM(rb_intern(buff));
	    }
	}
    }
    valstr = syms[reg][isset];

    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((cv = rb_hash_aref(uh, valstr)) == Qnil) {
	cv = INT2FIX(0);
    }
    HASH_ASET(uh, valstr, INT2FIX(FIX2INT(cv) + 1));
}

#undef HASH_ASET

void (*ruby_vm_collect_usage_func_insn)(int insn) = vm_analysis_insn;
void (*ruby_vm_collect_usage_func_operand)(int insn, int n, VALUE op) = vm_analysis_operand;
void (*ruby_vm_collect_usage_func_register)(int reg, int isset) = vm_analysis_register;

/* :nodoc: */
static VALUE
usage_analysis_insn_stop(VALUE self)
{
    ruby_vm_collect_usage_func_insn = 0;
    return Qnil;
}

/* :nodoc: */
static VALUE
usage_analysis_operand_stop(VALUE self)
{
    ruby_vm_collect_usage_func_operand = 0;
    return Qnil;
}

/* :nodoc: */
static VALUE
usage_analysis_register_stop(VALUE self)
{
    ruby_vm_collect_usage_func_register = 0;
    return Qnil;
}

#else

void (*ruby_vm_collect_usage_func_insn)(int insn) = NULL;
void (*ruby_vm_collect_usage_func_operand)(int insn, int n, VALUE op) = NULL;
void (*ruby_vm_collect_usage_func_register)(int reg, int isset) = NULL;

#endif

#if VM_COLLECT_USAGE_DETAILS
/* @param insn instruction number */
static void
vm_collect_usage_insn(int insn)
{
    if (RUBY_DTRACE_INSN_ENABLED()) {
	RUBY_DTRACE_INSN(rb_insns_name(insn));
    }
    if (ruby_vm_collect_usage_func_insn)
	(*ruby_vm_collect_usage_func_insn)(insn);
}

/* @param insn instruction number
 * @param n    n-th operand
 * @param op   operand value
 */
static void
vm_collect_usage_operand(int insn, int n, VALUE op)
{
    if (RUBY_DTRACE_INSN_OPERAND_ENABLED()) {
	VALUE valstr;

	valstr = rb_insn_operand_intern(GET_THREAD()->cfp->iseq, insn, n, op, 0, 0, 0, 0);

	RUBY_DTRACE_INSN_OPERAND(RSTRING_PTR(valstr), rb_insns_name(insn));
	RB_GC_GUARD(valstr);
    }
    if (ruby_vm_collect_usage_func_operand)
	(*ruby_vm_collect_usage_func_operand)(insn, n, op);
}

/* @param reg register id. see code of vm_analysis_register() */
/* @param iseset 0: read, 1: write */
static void
vm_collect_usage_register(int reg, int isset)
{
    if (ruby_vm_collect_usage_func_register)
	(*ruby_vm_collect_usage_func_register)(reg, isset);
}
#endif

