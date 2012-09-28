/**********************************************************************

  vm_insnhelper.c - instruction helper functions.

  $Author$

  Copyright (C) 2007 Koichi Sasada

**********************************************************************/

/* finish iseq array */
#include "insns.inc"
#include <math.h>
#include "constant.h"
#include "internal.h"

/* control stack frame */

#ifndef INLINE
#define INLINE inline
#endif

static rb_control_frame_t *vm_get_ruby_level_caller_cfp(rb_thread_t *th, rb_control_frame_t *cfp);

static inline rb_control_frame_t *
vm_push_frame(rb_thread_t *th,
	      const rb_iseq_t *iseq,
	      VALUE type,
	      VALUE self,
	      VALUE klass,
	      VALUE specval,
	      const VALUE *pc,
	      VALUE *sp,
	      int local_size,
	      const rb_method_entry_t *me)
{
    rb_control_frame_t *const cfp = th->cfp - 1;
    int i;

    /* check stack overflow */
    if ((void *)(sp + local_size) >= (void *)cfp) {
	rb_exc_raise(sysstack_error);
    }
    th->cfp = cfp;

    /* setup vm value stack */

    /* initialize local variables */
    for (i=0; i < local_size; i++) {
	*sp++ = Qnil;
    }

    /* set special val */
    *sp = specval;

    /* setup vm control frame stack */

    cfp->pc = (VALUE *)pc;
    cfp->sp = sp + 1;
#if VM_DEBUG_BP_CHECK
    cfp->bp_check = sp + 1;
#endif
    cfp->ep = sp;
    cfp->iseq = (rb_iseq_t *) iseq;
    cfp->flag = type;
    cfp->self = self;
    cfp->block_iseq = 0;
    cfp->proc = 0;
    cfp->me = me;
    if (klass) {
	cfp->klass = klass;
    }
    else {
	rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, prev_cfp)) {
	    cfp->klass = Qnil;
	}
	else {
	    cfp->klass = prev_cfp->klass;
	}
    }

    if (VMDEBUG == 2) {
	SDR();
    }

    return cfp;
}

static inline void
vm_pop_frame(rb_thread_t *th)
{
    th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);

    if (VMDEBUG == 2) {
	SDR();
    }
}

/* method dispatch */
static inline VALUE
rb_arg_error_new(int argc, int min, int max)
{
    VALUE err_mess = 0;
    if (min == max) {
	err_mess = rb_sprintf("wrong number of arguments (%d for %d)", argc, min);
    }
    else if (max == UNLIMITED_ARGUMENTS) {
	err_mess = rb_sprintf("wrong number of arguments (%d for %d+)", argc, min);
    }
    else {
	err_mess = rb_sprintf("wrong number of arguments (%d for %d..%d)", argc, min, max);
    }
    return rb_exc_new3(rb_eArgError, err_mess);
}

NORETURN(static void argument_error(const rb_iseq_t *iseq, int miss_argc, int min_argc, int max_argc));
static void
argument_error(const rb_iseq_t *iseq, int miss_argc, int min_argc, int max_argc)
{
    VALUE exc = rb_arg_error_new(miss_argc, min_argc, max_argc);
    VALUE bt = rb_make_backtrace();
    VALUE err_line = 0;

    if (iseq) {
	int line_no = rb_iseq_first_lineno(iseq);

	err_line = rb_sprintf("%s:%d:in `%s'",
			      RSTRING_PTR(iseq->location.path),
			      line_no, RSTRING_PTR(iseq->location.label));
	rb_funcall(bt, rb_intern("unshift"), 1, err_line);
    }

    rb_funcall(exc, rb_intern("set_backtrace"), 1, bt);
    rb_exc_raise(exc);
}

NORETURN(static void unknown_keyword_error(const rb_iseq_t *iseq, VALUE hash));
static void
unknown_keyword_error(const rb_iseq_t *iseq, VALUE hash)
{
    VALUE sep = rb_usascii_str_new2(", "), keys;
    const char *msg;
    int i;
    for (i = 0; i < iseq->arg_keywords; i++) {
	rb_hash_delete(hash, ID2SYM(iseq->arg_keyword_table[i]));
    }
    keys = rb_funcall(hash, rb_intern("keys"), 0, 0);
    if (!RB_TYPE_P(keys, T_ARRAY)) rb_raise(rb_eArgError, "unknown keyword");
    msg = RARRAY_LEN(keys) == 1 ? "" : "s";
    keys = rb_funcall(keys, rb_intern("join"), 1, sep);
    rb_raise(rb_eArgError, "unknown keyword%s: %"PRIsVALUE, msg, keys);
}

void
rb_error_arity(int argc, int min, int max)
{
    rb_exc_raise(rb_arg_error_new(argc, min, max));
}

#define VM_CALLEE_SETUP_ARG(ret, th, iseq, orig_argc, orig_argv, block) \
    if (LIKELY((iseq)->arg_simple & 0x01)) { \
	/* simple check */ \
	if ((orig_argc) != (iseq)->argc) { \
	    argument_error((iseq), (orig_argc), (iseq)->argc, (iseq)->argc); \
	} \
	(ret) = 0; \
    } \
    else { \
	(ret) = vm_callee_setup_arg_complex((th), (iseq), (orig_argc), (orig_argv), (block)); \
    }

static inline int
vm_callee_setup_arg_complex(rb_thread_t *th, const rb_iseq_t * iseq,
			    int orig_argc, VALUE * orig_argv,
			    const rb_block_t **block)
{
    const int m = iseq->argc;
    const int opts = iseq->arg_opts - (iseq->arg_opts > 0);
    const int min = m + iseq->arg_post_len;
    const int max = (iseq->arg_rest == -1) ? m + opts + iseq->arg_post_len : UNLIMITED_ARGUMENTS;
    int argc = orig_argc;
    VALUE *argv = orig_argv;
    rb_num_t opt_pc = 0;
    VALUE keyword_hash = Qnil;

    th->mark_stack_len = argc + iseq->arg_size;

    if (iseq->arg_keyword != -1) {
	int i, j;
	if (argc > 0) keyword_hash = rb_check_hash_type(argv[argc-1]);
	if (!NIL_P(keyword_hash)) {
	    argc--;
	    keyword_hash = rb_hash_dup(keyword_hash);
	    if (iseq->arg_keyword_check) {
		for (i = j = 0; i < iseq->arg_keywords; i++) {
		    if (st_lookup(RHASH_TBL(keyword_hash), ID2SYM(iseq->arg_keyword_table[i]), 0)) j++;
		}
		if (RHASH_TBL(keyword_hash)->num_entries > (unsigned int) j) {
		    unknown_keyword_error(iseq, keyword_hash);
		}
	    }
	}
	else {
	    keyword_hash = rb_hash_new();
	}
    }

    /* mandatory */
    if ((argc < min) || (argc > max && max != UNLIMITED_ARGUMENTS)) {
	argument_error(iseq, argc, min, max);
    }

    argv += m;
    argc -= m;

    /* post arguments */
    if (iseq->arg_post_len) {
	if (!(orig_argc < iseq->arg_post_start)) {
	    VALUE *new_argv = ALLOCA_N(VALUE, argc);
	    MEMCPY(new_argv, argv, VALUE, argc);
	    argv = new_argv;
	}

	MEMCPY(&orig_argv[iseq->arg_post_start], &argv[argc -= iseq->arg_post_len],
	       VALUE, iseq->arg_post_len);
    }

    /* opt arguments */
    if (iseq->arg_opts) {
	if (argc > opts) {
	    argc -= opts;
	    argv += opts;
	    opt_pc = iseq->arg_opt_table[opts]; /* no opt */
	}
	else {
	    int i;
	    for (i = argc; i<opts; i++) {
		orig_argv[i + m] = Qnil;
	    }
	    opt_pc = iseq->arg_opt_table[argc];
	    argc = 0;
	}
    }

    /* rest arguments */
    if (iseq->arg_rest != -1) {
	orig_argv[iseq->arg_rest] = rb_ary_new4(argc, argv);
	argc = 0;
    }

    /* keyword argument */
    if (iseq->arg_keyword != -1) {
	orig_argv[iseq->arg_keyword] = keyword_hash;
    }

    /* block arguments */
    if (block && iseq->arg_block != -1) {
	VALUE blockval = Qnil;
	const rb_block_t *blockptr = *block;

	if (blockptr) {
	    /* make Proc object */
	    if (blockptr->proc == 0) {
		rb_proc_t *proc;
		blockval = rb_vm_make_proc(th, blockptr, rb_cProc);
		GetProcPtr(blockval, proc);
		*block = &proc->block;
	    }
	    else {
		blockval = blockptr->proc;
	    }
	}

	orig_argv[iseq->arg_block] = blockval; /* Proc or nil */
    }

    th->mark_stack_len = 0;
    return (int)opt_pc;
}

static inline int
caller_setup_args(const rb_thread_t *th, rb_control_frame_t *cfp, VALUE flag,
		  int argc, rb_iseq_t *blockiseq, rb_block_t **block)
{
    rb_block_t *blockptr = 0;

    if (block) {
	if (flag & VM_CALL_ARGS_BLOCKARG_BIT) {
	    rb_proc_t *po;
	    VALUE proc;

	    proc = *(--cfp->sp);

	    if (proc != Qnil) {
		if (!rb_obj_is_proc(proc)) {
		    VALUE b = rb_check_convert_type(proc, T_DATA, "Proc", "to_proc");
		    if (NIL_P(b) || !rb_obj_is_proc(b)) {
			rb_raise(rb_eTypeError,
				 "wrong argument type %s (expected Proc)",
				 rb_obj_classname(proc));
		    }
		    proc = b;
		}
		GetProcPtr(proc, po);
		blockptr = &po->block;
		RUBY_VM_GET_BLOCK_PTR_IN_CFP(cfp)->proc = proc;
		*block = blockptr;
	    }
	}
	else if (blockiseq) {
	    blockptr = RUBY_VM_GET_BLOCK_PTR_IN_CFP(cfp);
	    blockptr->iseq = blockiseq;
	    blockptr->proc = 0;
	    *block = blockptr;
	}
    }

    /* expand top of stack? */
    if (flag & VM_CALL_ARGS_SPLAT_BIT) {
	VALUE ary = *(cfp->sp - 1);
	VALUE *ptr;
	int i;
	VALUE tmp = rb_check_convert_type(ary, T_ARRAY, "Array", "to_a");

	if (NIL_P(tmp)) {
	    /* do nothing */
	}
	else {
	    long len = RARRAY_LEN(tmp);
	    ptr = RARRAY_PTR(tmp);
	    cfp->sp -= 1;

	    CHECK_STACK_OVERFLOW(cfp, len);

	    for (i = 0; i < len; i++) {
		*cfp->sp++ = ptr[i];
	    }
	    argc += i-1;
	}
    }

    return argc;
}

static inline VALUE
call_cfunc(VALUE (*func)(), VALUE recv,
	   int len, int argc, const VALUE *argv)
{
    /* printf("len: %d, argc: %d\n", len, argc); */

    if (len >= 0) rb_check_arity(argc, len, len);

    switch (len) {
      case -2:
	return (*func) (recv, rb_ary_new4(argc, argv));
	break;
      case -1:
	return (*func) (argc, argv, recv);
	break;
      case 0:
	return (*func) (recv);
	break;
      case 1:
	return (*func) (recv, argv[0]);
	break;
      case 2:
	return (*func) (recv, argv[0], argv[1]);
	break;
      case 3:
	return (*func) (recv, argv[0], argv[1], argv[2]);
	break;
      case 4:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3]);
	break;
      case 5:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4]);
	break;
      case 6:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5]);
	break;
      case 7:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6]);
	break;
      case 8:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6], argv[7]);
	break;
      case 9:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6], argv[7], argv[8]);
	break;
      case 10:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6], argv[7], argv[8], argv[9]);
	break;
      case 11:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6], argv[7], argv[8], argv[9],
			argv[10]);
	break;
      case 12:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6], argv[7], argv[8], argv[9],
			argv[10], argv[11]);
	break;
      case 13:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6], argv[7], argv[8], argv[9], argv[10],
			argv[11], argv[12]);
	break;
      case 14:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6], argv[7], argv[8], argv[9], argv[10],
			argv[11], argv[12], argv[13]);
	break;
      case 15:
	return (*func) (recv, argv[0], argv[1], argv[2], argv[3], argv[4],
			argv[5], argv[6], argv[7], argv[8], argv[9], argv[10],
			argv[11], argv[12], argv[13], argv[14]);
	break;
      default:
	rb_raise(rb_eArgError, "too many arguments(%d)", len);
	UNREACHABLE;
    }
}

static inline VALUE
vm_call_cfunc(rb_thread_t *th, rb_control_frame_t *reg_cfp,
	      int num, volatile VALUE recv, const rb_block_t *blockptr,
	      const rb_method_entry_t *me, VALUE defined_class)
{
    volatile VALUE val = 0;
    const rb_method_definition_t *def = me->def;

    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, me->called_id, me->klass);

    vm_push_frame(th, 0, VM_FRAME_MAGIC_CFUNC, recv, defined_class,
		  VM_ENVVAL_BLOCK_PTR(blockptr), 0, th->cfp->sp, 1, me);

    reg_cfp->sp -= num + 1;

    val = call_cfunc(def->body.cfunc.func, recv, (int)def->body.cfunc.argc, num, reg_cfp->sp + 1);

    if (reg_cfp != th->cfp + 1) {
	rb_bug("cfp consistency error - send");
    }

    vm_pop_frame(th);

    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, me->called_id, me->klass);

    return val;
}

static inline VALUE
vm_call_bmethod(rb_thread_t *th, VALUE recv, int argc, const VALUE *argv,
		const rb_block_t *blockptr, const rb_method_entry_t *me,
		VALUE defined_class)
{
    rb_proc_t *proc;
    VALUE val;

    EXEC_EVENT_HOOK(th, RUBY_EVENT_CALL, recv, me->called_id, me->klass);

    /* control block frame */
    th->passed_me = me;
    GetProcPtr(me->def->body.proc, proc);
    val = vm_invoke_proc(th, proc, recv, defined_class, argc, argv, blockptr);

    EXEC_EVENT_HOOK(th, RUBY_EVENT_RETURN, recv, me->called_id, me->klass);

    return val;
}

static inline VALUE
vm_method_missing(rb_thread_t *th, rb_control_frame_t *const reg_cfp,
		  ID id, VALUE recv,
		  int num, const rb_block_t *blockptr, int opt)
{
    VALUE ret, *argv = STACK_ADDR_FROM_TOP(num + 1);

    th->method_missing_reason = opt;
    th->passed_block = blockptr;
    argv[0] = ID2SYM(id);
    ret = rb_funcall2(recv, idMethodMissing, num + 1, argv);
    POPN(num + 1);
    return ret;
}

static inline void
vm_setup_method(rb_thread_t *th, rb_control_frame_t *cfp,
		VALUE recv, int argc, const rb_block_t *blockptr, VALUE flag,
		const rb_method_entry_t *me, VALUE defined_class)
{
    int opt_pc, i;
    VALUE *sp, *argv = cfp->sp - argc;
    rb_iseq_t *iseq = me->def->body.iseq;

    VM_CALLEE_SETUP_ARG(opt_pc, th, iseq, argc, argv, &blockptr);

    /* stack overflow check */
    CHECK_STACK_OVERFLOW(cfp, iseq->stack_max);
    sp = argv + iseq->arg_size;

    if (LIKELY(!(flag & VM_CALL_TAILCALL_BIT))) {

	/* clear local variables */
	for (i = 0; i < iseq->local_size - iseq->arg_size; i++) {
	    *sp++ = Qnil;
	}

	vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD, recv, defined_class,
		      VM_ENVVAL_BLOCK_PTR(blockptr),
		      iseq->iseq_encoded + opt_pc, sp, 0, me);

	cfp->sp = argv - 1 /* recv */;
    }
    else {
	VALUE *src_argv = argv;
	VALUE *sp_orig;
	const int src_argc = iseq->arg_size;
	VALUE finish_flag = VM_FRAME_TYPE_FINISH_P(cfp) ? VM_FRAME_FLAG_FINISH : 0;
	cfp = th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp); /* pop cf */

	sp = sp_orig = cfp->sp;

	/* push self */
	sp[0] = recv;
	sp++;

	/* copy arguments */
	for (i=0; i < src_argc; i++) {
	    *sp++ = src_argv[i];
	}

	/* clear local variables */
	for (i = 0; i < iseq->local_size - iseq->arg_size; i++) {
	    *sp++ = Qnil;
	}

	vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD | finish_flag,
		      recv, defined_class, VM_ENVVAL_BLOCK_PTR(blockptr),
		      iseq->iseq_encoded + opt_pc, sp, 0, me);

	cfp->sp = sp_orig;
    }
}

static inline VALUE
vm_call_method(rb_thread_t *th, rb_control_frame_t *cfp,
	       int num, const rb_block_t *blockptr, VALUE flag,
	       ID id, const rb_method_entry_t *me,
	       VALUE recv, VALUE defined_class)
{
    VALUE val;

  start_method_dispatch:

    if (me != 0) {
	if ((me->flag == 0)) {
	  normal_method_dispatch:
	    switch (me->def->type) {
	      case VM_METHOD_TYPE_ISEQ:{
		vm_setup_method(th, cfp, recv, num, blockptr, flag, me,
				defined_class);
		return Qundef;
	      }
	      case VM_METHOD_TYPE_NOTIMPLEMENTED:
	      case VM_METHOD_TYPE_CFUNC:{
		val = vm_call_cfunc(th, cfp, num, recv, blockptr, me,
				    defined_class);
		break;
	      }
	      case VM_METHOD_TYPE_ATTRSET:{
		rb_check_arity(num, 1, 1);
		val = rb_ivar_set(recv, me->def->body.attr.id, *(cfp->sp - 1));
		cfp->sp -= 2;
		break;
	      }
	      case VM_METHOD_TYPE_IVAR:{
		rb_check_arity(num, 0, 0);
		val = rb_attr_get(recv, me->def->body.attr.id);
		cfp->sp -= 1;
		break;
	      }
	      case VM_METHOD_TYPE_MISSING:{
		VALUE *argv = ALLOCA_N(VALUE, num+1);
		argv[0] = ID2SYM(me->def->original_id);
		MEMCPY(argv+1, cfp->sp - num, VALUE, num);
		cfp->sp += - num - 1;
		th->passed_block = blockptr;
		val = rb_funcall2(recv, rb_intern("method_missing"), num+1, argv);
		break;
	      }
	      case VM_METHOD_TYPE_BMETHOD:{
		VALUE *argv = ALLOCA_N(VALUE, num);
		MEMCPY(argv, cfp->sp - num, VALUE, num);
		cfp->sp += - num - 1;
		val = vm_call_bmethod(th, recv, num, argv, blockptr, me,
				      defined_class);
		break;
	      }
	      case VM_METHOD_TYPE_ZSUPER:{
		VALUE klass = RCLASS_SUPER(me->klass);
		me = rb_method_entry(klass, id, &defined_class);

		if (me != 0) {
		    goto normal_method_dispatch;
		}
		else {
		    goto start_method_dispatch;
		}
	      }
	      case VM_METHOD_TYPE_OPTIMIZED:{
		switch (me->def->body.optimize_type) {
		  case OPTIMIZED_METHOD_TYPE_SEND: {
		    rb_control_frame_t *reg_cfp = cfp;
		    rb_num_t i = num - 1;
		    VALUE sym;

		    if (num == 0) {
			rb_raise(rb_eArgError, "no method name given");
		    }

		    sym = TOPN(i);
		    if (SYMBOL_P(sym)) {
			id = SYM2ID(sym);
		    }
		    else if (!(id = rb_check_id(&sym))) {
			if (rb_method_basic_definition_p(CLASS_OF(recv), idMethodMissing)) {
			    VALUE exc = make_no_method_exception(rb_eNoMethodError, NULL, recv,
								 rb_long2int(num), &TOPN(i));
			    rb_exc_raise(exc);
			}
			id = rb_to_id(sym);
		    }
		    /* shift arguments */
		    if (i > 0) {
			MEMMOVE(&TOPN(i), &TOPN(i-1), VALUE, i);
		    }
		    me = rb_method_entry(CLASS_OF(recv), id, &defined_class);
		    num -= 1;
		    DEC_SP(1);
		    flag |= VM_CALL_FCALL_BIT | VM_CALL_OPT_SEND_BIT;

		    goto start_method_dispatch;
		  }
		  case OPTIMIZED_METHOD_TYPE_CALL: {
		    rb_proc_t *proc;
		    int argc = num;
		    VALUE *argv = ALLOCA_N(VALUE, num);
		    GetProcPtr(recv, proc);
		    MEMCPY(argv, cfp->sp - num, VALUE, num);
		    cfp->sp -= num + 1;

		    val = rb_vm_invoke_proc(th, proc, argc, argv, blockptr);
		    break;
		  }
		  default:
		    rb_bug("eval_invoke_method: unsupported optimized method type (%d)",
			   me->def->body.optimize_type);
		}
		break;
	      }
	      default:{
		rb_bug("eval_invoke_method: unsupported method type (%d)", me->def->type);
		break;
	      }
	    }
	}
	else {
	    int noex_safe;

	    if (!(flag & VM_CALL_FCALL_BIT) &&
		(me->flag & NOEX_MASK) & NOEX_PRIVATE) {
		int stat = NOEX_PRIVATE;

		if (flag & VM_CALL_VCALL_BIT) {
		    stat |= NOEX_VCALL;
		}
		val = vm_method_missing(th, cfp, id, recv, num, blockptr, stat);
	    }
	    else if (!(flag & VM_CALL_OPT_SEND_BIT) && (me->flag & NOEX_MASK) & NOEX_PROTECTED) {
		if (!rb_obj_is_kind_of(cfp->self, defined_class)) {
		    val = vm_method_missing(th, cfp, id, recv, num, blockptr, NOEX_PROTECTED);
		}
		else {
		    goto normal_method_dispatch;
		}
	    }
	    else if ((noex_safe = NOEX_SAFE(me->flag)) > th->safe_level &&
		     (noex_safe > 2)) {
		rb_raise(rb_eSecurityError, "calling insecure method: %s", rb_id2name(id));
	    }
	    else {
		goto normal_method_dispatch;
	    }
	}
    }
    else {
	/* method missing */
	int stat = 0;
	if (flag & VM_CALL_VCALL_BIT) {
	    stat |= NOEX_VCALL;
	}
	if (flag & VM_CALL_SUPER_BIT) {
	    stat |= NOEX_SUPER;
	}
	if (id == idMethodMissing) {
	    rb_control_frame_t *reg_cfp = cfp;
	    VALUE *argv = STACK_ADDR_FROM_TOP(num);
	    rb_raise_method_missing(th, num, argv, recv, stat);
	}
	else {
	    val = vm_method_missing(th, cfp, id, recv, num, blockptr, stat);
	}
    }

    RUBY_VM_CHECK_INTS(th);
    return val;
}

/* yield */

static inline int
block_proc_is_lambda(const VALUE procval)
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

static inline VALUE
vm_yield_with_cfunc(rb_thread_t *th, const rb_block_t *block,
		    VALUE self, int argc, const VALUE *argv,
		    const rb_block_t *blockargptr)
{
    NODE *ifunc = (NODE *) block->iseq;
    VALUE val, arg, blockarg;
    int lambda = block_proc_is_lambda(block->proc);
    rb_control_frame_t *cfp;

    if (lambda) {
	arg = rb_ary_new4(argc, argv);
    }
    else if (argc == 0) {
	arg = Qnil;
    }
    else {
	arg = argv[0];
    }

    if (blockargptr) {
	if (blockargptr->proc) {
	    blockarg = blockargptr->proc;
	}
	else {
	    blockarg = rb_vm_make_proc(th, blockargptr, rb_cProc);
	}
    }
    else {
	blockarg = Qnil;
    }

    cfp = vm_push_frame(th, (rb_iseq_t *)ifunc, VM_FRAME_MAGIC_IFUNC, self,
			0, VM_ENVVAL_PREV_EP_PTR(block->ep), 0,
			th->cfp->sp, 1, 0);

    if (blockargptr) {
	VM_CF_LEP(cfp)[0] = VM_ENVVAL_BLOCK_PTR(blockargptr);
    }
    val = (*ifunc->nd_cfnc) (arg, ifunc->nd_tval, argc, argv, blockarg);

    th->cfp++;
    return val;
}


/*--
 * @brief on supplied all of optional, rest and post parameters.
 * @pre iseq is block style (not lambda style)
 */
static inline int
vm_yield_setup_block_args_complex(rb_thread_t *th, const rb_iseq_t *iseq,
				  int argc, VALUE *argv)
{
    rb_num_t opt_pc = 0;
    int i;
    const int m = iseq->argc;
    const int r = iseq->arg_rest;
    int len = iseq->arg_post_len;
    int start = iseq->arg_post_start;
    int rsize = argc > m ? argc - m : 0;    /* # of arguments which did not consumed yet */
    int psize = rsize > len ? len : rsize;  /* # of post arguments */
    int osize = 0;  /* # of opt arguments */
    VALUE ary;

    /* reserves arguments for post parameters */
    rsize -= psize;

    if (iseq->arg_opts) {
	const int opts = iseq->arg_opts - 1;
	if (rsize > opts) {
            osize = opts;
	    opt_pc = iseq->arg_opt_table[opts];
	}
	else {
            osize = rsize;
	    opt_pc = iseq->arg_opt_table[rsize];
	}
    }
    rsize -= osize;

    if (0) {
	printf(" argc: %d\n", argc);
	printf("  len: %d\n", len);
	printf("start: %d\n", start);
	printf("rsize: %d\n", rsize);
    }

    if (r == -1) {
        /* copy post argument */
        MEMMOVE(&argv[start], &argv[m+osize], VALUE, psize);
    }
    else {
        ary = rb_ary_new4(rsize, &argv[r]);

        /* copy post argument */
        MEMMOVE(&argv[start], &argv[m+rsize+osize], VALUE, psize);
        argv[r] = ary;
    }

    for (i=psize; i<len; i++) {
	argv[start + i] = Qnil;
    }

    return (int)opt_pc;
}

static inline int
vm_yield_setup_block_args(rb_thread_t *th, const rb_iseq_t * iseq,
			  int orig_argc, VALUE *argv,
			  const rb_block_t *blockptr)
{
    int i;
    int argc = orig_argc;
    const int m = iseq->argc;
    VALUE ary, arg0;
    int opt_pc = 0;

    th->mark_stack_len = argc;

    /*
     * yield [1, 2]
     *  => {|a|} => a = [1, 2]
     *  => {|a, b|} => a, b = [1, 2]
     */
    arg0 = argv[0];
    if (!(iseq->arg_simple & 0x02) &&          /* exclude {|a|} */
            (m + iseq->arg_opts + iseq->arg_post_len) > 0 &&    /* this process is meaningful */
            argc == 1 && !NIL_P(ary = rb_check_array_type(arg0))) { /* rhs is only an array */
        th->mark_stack_len = argc = RARRAY_LENINT(ary);

        CHECK_STACK_OVERFLOW(th->cfp, argc);

        MEMCPY(argv, RARRAY_PTR(ary), VALUE, argc);
    }
    else {
        argv[0] = arg0;
    }

    for (i=argc; i<m; i++) {
        argv[i] = Qnil;
    }

    if (iseq->arg_rest == -1 && iseq->arg_opts == 0) {
        const int arg_size = iseq->arg_size;
        if (arg_size < argc) {
            /*
             * yield 1, 2
             * => {|a|} # truncate
             */
            th->mark_stack_len = argc = arg_size;
        }
    }
    else {
        int r = iseq->arg_rest;

        if (iseq->arg_post_len ||
                iseq->arg_opts) { /* TODO: implement simple version for (iseq->arg_post_len==0 && iseq->arg_opts > 0) */
	    opt_pc = vm_yield_setup_block_args_complex(th, iseq, argc, argv);
        }
        else {
            if (argc < r) {
                /* yield 1
                 * => {|a, b, *r|}
                 */
                for (i=argc; i<r; i++) {
                    argv[i] = Qnil;
                }
                argv[r] = rb_ary_new();
            }
            else {
                argv[r] = rb_ary_new4(argc-r, &argv[r]);
            }
        }

        th->mark_stack_len = iseq->arg_size;
    }

    /* {|&b|} */
    if (iseq->arg_block != -1) {
        VALUE procval = Qnil;

        if (blockptr) {
	    if (blockptr->proc == 0) {
		procval = rb_vm_make_proc(th, blockptr, rb_cProc);
	    }
	    else {
		procval = blockptr->proc;
	    }
        }

        argv[iseq->arg_block] = procval;
    }

    th->mark_stack_len = 0;
    return opt_pc;
}

static inline int
vm_yield_setup_args(rb_thread_t * const th, const rb_iseq_t *iseq,
		    int argc, VALUE *argv,
		    const rb_block_t *blockptr, int lambda)
{
    if (0) { /* for debug */
	printf("     argc: %d\n", argc);
	printf("iseq argc: %d\n", iseq->argc);
	printf("iseq opts: %d\n", iseq->arg_opts);
	printf("iseq rest: %d\n", iseq->arg_rest);
	printf("iseq post: %d\n", iseq->arg_post_len);
	printf("iseq blck: %d\n", iseq->arg_block);
	printf("iseq smpl: %d\n", iseq->arg_simple);
	printf("   lambda: %s\n", lambda ? "true" : "false");
    }

    if (lambda) {
	/* call as method */
	int opt_pc;
	VM_CALLEE_SETUP_ARG(opt_pc, th, iseq, argc, argv, &blockptr);
	return opt_pc;
    }
    else {
	return vm_yield_setup_block_args(th, iseq, argc, argv, blockptr);
    }
}

static VALUE
vm_invoke_block(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_num_t num, rb_num_t flag)
{
    const rb_block_t *block = VM_CF_BLOCK_PTR(reg_cfp);
    rb_iseq_t *iseq;
    int argc = (int)num;
    VALUE type = GET_ISEQ()->local_iseq->type;

    if ((type != ISEQ_TYPE_METHOD && type != ISEQ_TYPE_CLASS) || block == 0) {
	rb_vm_localjump_error("no block given (yield)", Qnil, 0);
    }
    iseq = block->iseq;

    argc = caller_setup_args(th, GET_CFP(), flag, argc, 0, 0);

    if (BUILTIN_TYPE(iseq) != T_NODE) {
	int opt_pc;
	const int arg_size = iseq->arg_size;
	VALUE * const rsp = GET_SP() - argc;
	SET_SP(rsp);

	CHECK_STACK_OVERFLOW(GET_CFP(), iseq->stack_max);
	opt_pc = vm_yield_setup_args(th, iseq, argc, rsp, 0,
				     block_proc_is_lambda(block->proc));

	vm_push_frame(th, iseq, VM_FRAME_MAGIC_BLOCK, block->self,
		      block->klass,
		      VM_ENVVAL_PREV_EP_PTR(block->ep),
		      iseq->iseq_encoded + opt_pc,
		      rsp + arg_size,
		      iseq->local_size - arg_size, 0);

	return Qundef;
    }
    else {
	VALUE val = vm_yield_with_cfunc(th, block, block->self, argc, STACK_ADDR_FROM_TOP(argc), 0);
	POPN(argc); /* TODO: should put before C/yield? */
	return val;
    }
}

/* svar */

static inline NODE *
lep_svar_place(rb_thread_t *th, VALUE *lep)
{
    VALUE *svar;

    if (lep && th->root_lep != lep) {
	svar = &lep[-1];
    }
    else {
	svar = &th->root_svar;
    }
    if (NIL_P(*svar)) {
	*svar = (VALUE)NEW_IF(Qnil, Qnil, Qnil);
    }
    return (NODE *)*svar;
}

static VALUE
lep_svar_get(rb_thread_t *th, VALUE *lep, VALUE key)
{
    NODE *svar = lep_svar_place(th, lep);

    switch (key) {
      case 0:
	return svar->u1.value;
      case 1:
	return svar->u2.value;
      default: {
	const VALUE hash = svar->u3.value;

	if (hash == Qnil) {
	    return Qnil;
	}
	else {
	    return rb_hash_lookup(hash, key);
	}
      }
    }
}

static void
lep_svar_set(rb_thread_t *th, VALUE *lep, VALUE key, VALUE val)
{
    NODE *svar = lep_svar_place(th, lep);

    switch (key) {
      case 0:
	svar->u1.value = val;
	return;
      case 1:
	svar->u2.value = val;
	return;
      default: {
	VALUE hash = svar->u3.value;

	if (hash == Qnil) {
	    svar->u3.value = hash = rb_hash_new();
	}
	rb_hash_aset(hash, key, val);
      }
    }
}

static inline VALUE
vm_getspecial(rb_thread_t *th, VALUE *lep, VALUE key, rb_num_t type)
{
    VALUE val;

    if (type == 0) {
	VALUE k = key;
	if (FIXNUM_P(key)) {
	    k = FIX2INT(key);
	}
	val = lep_svar_get(th, lep, k);
    }
    else {
	VALUE backref = lep_svar_get(th, lep, 1);

	if (type & 0x01) {
	    switch (type >> 1) {
	      case '&':
		val = rb_reg_last_match(backref);
		break;
	      case '`':
		val = rb_reg_match_pre(backref);
		break;
	      case '\'':
		val = rb_reg_match_post(backref);
		break;
	      case '+':
		val = rb_reg_match_last(backref);
		break;
	      default:
		rb_bug("unexpected back-ref");
	    }
	}
	else {
	    val = rb_reg_nth_match((int)(type >> 1), backref);
	}
    }
    return val;
}

static NODE *
vm_get_cref0(const rb_iseq_t *iseq, const VALUE *ep)
{
    while (1) {
	if (VM_EP_LEP_P(ep)) {
	    if (!RUBY_VM_NORMAL_ISEQ_P(iseq)) return NULL;
	    return iseq->cref_stack;
	}
	else if (ep[-1] != Qnil) {
	    return (NODE *)ep[-1];
	}
	ep = VM_EP_PREV_EP(ep);
    }
}

NODE *
rb_vm_get_cref(const rb_iseq_t *iseq, const VALUE *ep)
{
    NODE *cref = vm_get_cref0(iseq, ep);

    if (cref == 0) {
	rb_bug("rb_vm_get_cref: unreachable");
    }
    return cref;
}

static NODE *
vm_cref_push(rb_thread_t *th, VALUE klass, int noex, rb_block_t *blockptr)
{
    rb_control_frame_t *cfp = vm_get_ruby_level_caller_cfp(th, th->cfp);
    NODE *cref = NEW_CREF(klass);
    cref->nd_omod = Qnil;
    cref->nd_visi = noex;

    if (blockptr) {
	cref->nd_next = vm_get_cref0(blockptr->iseq, blockptr->ep);
    }
    else if (cfp) {
	cref->nd_next = vm_get_cref0(cfp->iseq, cfp->ep);
    }
    /* TODO: why cref->nd_next is 1? */
    if (cref->nd_next && cref->nd_next != (void *) 1 &&
	!NIL_P(cref->nd_next->nd_omod)) {
	COPY_CREF_OMOD(cref, cref->nd_next);
    }

    return cref;
}

static inline VALUE
vm_get_cbase(const rb_iseq_t *iseq, const VALUE *ep)
{
    NODE *cref = rb_vm_get_cref(iseq, ep);
    VALUE klass = Qundef;

    while (cref) {
	if ((klass = cref->nd_clss) != 0) {
	    break;
	}
	cref = cref->nd_next;
    }

    return klass;
}

static inline VALUE
vm_get_const_base(const rb_iseq_t *iseq, const VALUE *ep)
{
    NODE *cref = rb_vm_get_cref(iseq, ep);
    VALUE klass = Qundef;

    while (cref) {
	if (!(cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) &&
	    (klass = cref->nd_clss) != 0) {
	    break;
	}
	cref = cref->nd_next;
    }

    return klass;
}

static inline void
vm_check_if_namespace(VALUE klass)
{
    VALUE str;
    if (!RB_TYPE_P(klass, T_CLASS) && !RB_TYPE_P(klass, T_MODULE)) {
	str = rb_inspect(klass);
	rb_raise(rb_eTypeError, "%s is not a class/module",
		 StringValuePtr(str));
    }
}

static inline VALUE
vm_get_iclass(rb_control_frame_t *cfp, VALUE klass)
{
    if (TYPE(klass) == T_MODULE &&
	FL_TEST(klass, RMODULE_IS_OVERLAID) &&
	TYPE(cfp->klass) == T_ICLASS &&
	RBASIC(cfp->klass)->klass == klass) {
	return cfp->klass;
    }
    else {
	return klass;
    }
}

static inline VALUE
vm_get_ev_const(rb_thread_t *th, const rb_iseq_t *iseq,
		VALUE orig_klass, ID id, int is_defined)
{
    VALUE val;

    if (orig_klass == Qnil) {
	/* in current lexical scope */
	const NODE *root_cref = rb_vm_get_cref(iseq, th->cfp->ep);
	const NODE *cref;
	VALUE klass = orig_klass;

	while (root_cref && root_cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) {
	    root_cref = root_cref->nd_next;
	}
	cref = root_cref;
	while (cref && cref->nd_next) {
	    if (cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) {
		klass = Qnil;
	    }
	    else {
		klass = cref->nd_clss;
	    }
	    cref = cref->nd_next;

	    if (!NIL_P(klass)) {
		VALUE av, am = 0;
		st_data_t data;
	      search_continue:
		if (RCLASS_CONST_TBL(klass) &&
		    st_lookup(RCLASS_CONST_TBL(klass), id, &data)) {
		    val = ((rb_const_entry_t*)data)->value;
		    if (val == Qundef) {
			if (am == klass) break;
			am = klass;
			if (is_defined) return 1;
			if (rb_autoloading_value(klass, id, &av)) return av;
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
	}

	/* search self */
	if (root_cref && !NIL_P(root_cref->nd_clss)) {
	    klass = vm_get_iclass(th->cfp, root_cref->nd_clss);
	}
	else {
	    klass = CLASS_OF(th->cfp->self);
	}

	if (is_defined) {
	    return rb_const_defined(klass, id);
	}
	else {
	    return rb_const_get(klass, id);
	}
    }
    else {
	vm_check_if_namespace(orig_klass);
	if (is_defined) {
	    return rb_public_const_defined_from(orig_klass, id);
	}
	else {
	    return rb_public_const_get_from(orig_klass, id);
	}
    }
}

static inline VALUE
vm_get_cvar_base(NODE *cref, rb_control_frame_t *cfp)
{
    VALUE klass;

    if (!cref) {
	rb_bug("vm_get_cvar_base: no cref");
    }

    while (cref->nd_next &&
	   (NIL_P(cref->nd_clss) || FL_TEST(cref->nd_clss, FL_SINGLETON) ||
	    (cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL))) {
	cref = cref->nd_next;
    }
    if (!cref->nd_next) {
	rb_warn("class variable access from toplevel");
    }

    klass = vm_get_iclass(cfp, cref->nd_clss);

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class variables available");
    }
    return klass;
}

static VALUE
vm_search_const_defined_class(const VALUE cbase, ID id)
{
    if (rb_const_defined_at(cbase, id)) return cbase;
    if (cbase == rb_cObject) {
	VALUE tmp = RCLASS_SUPER(cbase);
	while (tmp) {
	    if (rb_const_defined_at(tmp, id)) return tmp;
	    tmp = RCLASS_SUPER(tmp);
	}
    }
    return 0;
}

#ifndef USE_IC_FOR_IVAR
#define USE_IC_FOR_IVAR 1
#endif

static VALUE
vm_getivar(VALUE obj, ID id, IC ic)
{
#if USE_IC_FOR_IVAR
    if (RB_TYPE_P(obj, T_OBJECT)) {
	VALUE val = Qundef;
	VALUE klass = RBASIC(obj)->klass;

	if (LIKELY(ic->ic_class == klass &&
		   ic->ic_vmstat == GET_VM_STATE_VERSION())) {
	    long index = ic->ic_value.index;
	    long len = ROBJECT_NUMIV(obj);
	    VALUE *ptr = ROBJECT_IVPTR(obj);

	    if (index < len) {
		val = ptr[index];
	    }
	}
	else {
	    st_data_t index;
	    long len = ROBJECT_NUMIV(obj);
	    VALUE *ptr = ROBJECT_IVPTR(obj);
	    struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);

	    if (iv_index_tbl) {
		if (st_lookup(iv_index_tbl, id, &index)) {
		    if ((long)index < len) {
			val = ptr[index];
		    }
		    ic->ic_class = klass;
		    ic->ic_value.index = index;
		    ic->ic_vmstat = GET_VM_STATE_VERSION();
		}
	    }
	}
	if (UNLIKELY(val == Qundef)) {
	    rb_warning("instance variable %s not initialized", rb_id2name(id));
	    val = Qnil;
	}
	return val;
    }
    else {
	return rb_ivar_get(obj, id);
    }
#else
    return rb_ivar_get(obj, id);
#endif
}

static void
vm_setivar(VALUE obj, ID id, VALUE val, IC ic)
{
#if USE_IC_FOR_IVAR
    if (!OBJ_UNTRUSTED(obj) && rb_safe_level() >= 4) {
	rb_raise(rb_eSecurityError, "Insecure: can't modify instance variable");
    }

    rb_check_frozen(obj);

    if (RB_TYPE_P(obj, T_OBJECT)) {
	VALUE klass = RBASIC(obj)->klass;
	st_data_t index;

	if (LIKELY(ic->ic_class == klass &&
		   ic->ic_vmstat == GET_VM_STATE_VERSION())) {
	    long index = ic->ic_value.index;
	    long len = ROBJECT_NUMIV(obj);
	    VALUE *ptr = ROBJECT_IVPTR(obj);

	    if (index < len) {
		ptr[index] = val;
		return; /* inline cache hit */
	    }
	}
	else {
	    struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);

	    if (iv_index_tbl && st_lookup(iv_index_tbl, (st_data_t)id, &index)) {
		ic->ic_class = klass;
		ic->ic_value.index = index;
		ic->ic_vmstat = GET_VM_STATE_VERSION();
	    }
	    /* fall through */
	}
    }
    rb_ivar_set(obj, id, val);
#else
    rb_ivar_set(obj, id, val);
#endif
}

static inline const rb_method_entry_t *
vm_method_search(VALUE id, VALUE klass, IC ic, VALUE *defined_class_ptr)
{
    rb_method_entry_t *me;
#if OPT_INLINE_METHOD_CACHE
    if (LIKELY(klass == ic->ic_class &&
	GET_VM_STATE_VERSION() == ic->ic_vmstat)) {
	me = ic->ic_value.method;
	if (defined_class_ptr)
	    *defined_class_ptr = ic->ic_value2.defined_class;
    }
    else {
	VALUE defined_class;
	me = rb_method_entry(klass, id, &defined_class);
	if (defined_class_ptr)
	    *defined_class_ptr = defined_class;
	ic->ic_class = klass;
	ic->ic_value.method = me;
	ic->ic_value2.defined_class = defined_class;
	ic->ic_vmstat = GET_VM_STATE_VERSION();
    }
#else
    me = rb_method_entry(klass, id, defined_class_ptr);
#endif
    return me;
}

static inline VALUE
vm_search_normal_superclass(VALUE klass)
{
    klass = RCLASS_ORIGIN(klass);
    return RCLASS_SUPER(klass);
}

static void
vm_super_outside(void)
{
    rb_raise(rb_eNoMethodError, "super called outside of method");
}

static void
vm_search_superclass(rb_control_frame_t *reg_cfp, rb_iseq_t *iseq,
		     VALUE sigval,
		     ID *idp, VALUE *klassp)
{
    ID id;
    VALUE klass;

    while (iseq && !iseq->klass) {
	iseq = iseq->parent_iseq;
    }

    if (iseq == 0) {
	vm_super_outside();
    }

    id = iseq->defined_method_id;

    if (iseq != iseq->local_iseq) {
	/* defined by Module#define_method() */
	rb_control_frame_t *lcfp = GET_CFP();

	if (!sigval) {
	    /* zsuper */
	    rb_raise(rb_eRuntimeError, "implicit argument passing of super from method defined by define_method() is not supported. Specify all arguments explicitly.");
	}

	while (lcfp->iseq != iseq) {
	    rb_thread_t *th = GET_THREAD();
	    VALUE *tep = VM_EP_PREV_EP(lcfp->ep);
	    while (1) {
		lcfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(lcfp);
		if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, lcfp)) {
		    vm_super_outside();
		}
		if (lcfp->ep == tep) {
		    break;
		}
	    }
	}

	/* temporary measure for [Bug #2420] [Bug #3136] */
	if (!lcfp->me) {
	    vm_super_outside();
	}

	id = lcfp->me->def->original_id;
	klass = vm_search_normal_superclass(lcfp->klass);
    }
    else {
	klass = vm_search_normal_superclass(reg_cfp->klass);
    }

    *idp = id;
    *klassp = klass;
}

static VALUE
vm_throw(rb_thread_t *th, rb_control_frame_t *reg_cfp,
	 rb_num_t throw_state, VALUE throwobj)
{
    int state = (int)(throw_state & 0xff);
    int flag = (int)(throw_state & 0x8000);
    rb_num_t level = throw_state >> 16;

    if (state != 0) {
	VALUE *pt = 0;
	if (flag != 0) {
	    pt = (void *) 1;
	}
	else {
	    if (state == TAG_BREAK) {
		rb_control_frame_t *cfp = GET_CFP();
		VALUE *ep = GET_EP();
		int is_orphan = 1;
		rb_iseq_t *base_iseq = GET_ISEQ();

	      search_parent:
		if (cfp->iseq->type != ISEQ_TYPE_BLOCK) {
		    if (cfp->iseq->type == ISEQ_TYPE_CLASS) {
			cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
			ep = cfp->ep;
			goto search_parent;
		    }
		    ep = VM_EP_PREV_EP(ep);
		    base_iseq = base_iseq->parent_iseq;

		    while ((VALUE *) cfp < th->stack + th->stack_size) {
			if (cfp->ep == ep) {
			    goto search_parent;
			}
			cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
		    }
		    rb_bug("VM (throw): can't find break base.");
		}

		if (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_LAMBDA) {
		    /* lambda{... break ...} */
		    is_orphan = 0;
		    pt = cfp->ep;
		    state = TAG_RETURN;
		}
		else {
		    ep = VM_EP_PREV_EP(ep);

		    while ((VALUE *)cfp < th->stack + th->stack_size) {
			if (cfp->ep == ep) {
			    VALUE epc = cfp->pc - cfp->iseq->iseq_encoded;
			    rb_iseq_t *iseq = cfp->iseq;
			    int i;

			    for (i=0; i<iseq->catch_table_size; i++) {
				struct iseq_catch_table_entry *entry = &iseq->catch_table[i];

				if (entry->type == CATCH_TYPE_BREAK &&
				    entry->start < epc && entry->end >= epc) {
				    if (entry->cont == epc) {
					goto found;
				    }
				    else {
					break;
				    }
				}
			    }
			    break;

			  found:
			    pt = ep;
			    is_orphan = 0;
			    break;
			}
			cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
		    }
		}

		if (is_orphan) {
		    rb_vm_localjump_error("break from proc-closure", throwobj, TAG_BREAK);
		}
	    }
	    else if (state == TAG_RETRY) {
		rb_num_t i;
		pt = VM_EP_PREV_EP(GET_EP());
		for (i = 0; i < level; i++) {
		    pt = GC_GUARDED_PTR_REF((VALUE *) * pt);
		}
	    }
	    else if (state == TAG_RETURN) {
		rb_control_frame_t *cfp = GET_CFP();
		VALUE *ep = GET_EP();
		VALUE *target_lep = VM_CF_LEP(cfp);
		int in_class_frame = 0;

		/* check orphan and get dfp */
		while ((VALUE *) cfp < th->stack + th->stack_size) {
		    VALUE *lep = VM_CF_LEP(cfp);

		    if (!target_lep) {
			target_lep = lep;
		    }

		    if (lep == target_lep && cfp->iseq->type == ISEQ_TYPE_CLASS) {
			in_class_frame = 1;
			target_lep = 0;
		    }

		    if (lep == target_lep) {
			if (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_LAMBDA) {
			    VALUE *tep = ep;

			    if (in_class_frame) {
				/* lambda {class A; ... return ...; end} */
				ep = cfp->ep;
				goto valid_return;
			    }

			    while (target_lep != tep) {
				if (cfp->ep == tep) {
				    /* in lambda */
				    ep = cfp->ep;
				    goto valid_return;
				}
				tep = VM_EP_PREV_EP(tep);
			    }
			}
		    }

		    if (cfp->ep == target_lep && cfp->iseq->type == ISEQ_TYPE_METHOD) {
			ep = target_lep;
			goto valid_return;
		    }

		    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
		}

		rb_vm_localjump_error("unexpected return", throwobj, TAG_RETURN);

	      valid_return:
		pt = ep;
	    }
	    else {
		rb_bug("isns(throw): unsupport throw type");
	    }
	}
	th->state = state;
	return (VALUE)NEW_THROW_OBJECT(throwobj, (VALUE) pt, state);
    }
    else {
	/* continue throw */
	VALUE err = throwobj;

	if (FIXNUM_P(err)) {
	    th->state = FIX2INT(err);
	}
	else if (SYMBOL_P(err)) {
	    th->state = TAG_THROW;
	}
	else if (BUILTIN_TYPE(err) == T_NODE) {
	    th->state = GET_THROWOBJ_STATE(err);
	}
	else {
	    th->state = TAG_RAISE;
	    /*th->state = FIX2INT(rb_ivar_get(err, idThrowState));*/
	}
	return err;
    }
}

static inline void
vm_expandarray(rb_control_frame_t *cfp, VALUE ary, rb_num_t num, int flag)
{
    int is_splat = flag & 0x01;
    rb_num_t space_size = num + is_splat;
    VALUE *base = cfp->sp, *ptr;
    rb_num_t len;

    if (!RB_TYPE_P(ary, T_ARRAY)) {
	ary = rb_ary_to_ary(ary);
    }

    cfp->sp += space_size;

    ptr = RARRAY_PTR(ary);
    len = (rb_num_t)RARRAY_LEN(ary);

    if (flag & 0x02) {
	/* post: ..., nil ,ary[-1], ..., ary[0..-num] # top */
	rb_num_t i = 0, j;

	if (len < num) {
	    for (i=0; i<num-len; i++) {
		*base++ = Qnil;
	    }
	}
	for (j=0; i<num; i++, j++) {
	    VALUE v = ptr[len - j - 1];
	    *base++ = v;
	}
	if (is_splat) {
	    *base = rb_ary_new4(len - j, ptr);
	}
    }
    else {
	/* normal: ary[num..-1], ary[num-2], ary[num-3], ..., ary[0] # top */
	rb_num_t i;
	VALUE *bptr = &base[space_size - 1];

	for (i=0; i<num; i++) {
	    if (len <= i) {
		for (; i<num; i++) {
		    *bptr-- = Qnil;
		}
		break;
	    }
	    *bptr-- = ptr[i];
	}
	if (is_splat) {
	    if (num > len) {
		*bptr = rb_ary_new();
	    }
	    else {
		*bptr = rb_ary_new4(len - num, ptr + num);
	    }
	}
    }
    RB_GC_GUARD(ary);
}

static inline int
check_cfunc(const rb_method_entry_t *me, VALUE (*func)())
{
    if (me && me->def->type == VM_METHOD_TYPE_CFUNC &&
	me->def->body.cfunc.func == func) {
	return 1;
    }
    else {
	return 0;
    }
}

static
#ifndef NO_BIG_INLINE
inline
#endif
VALUE
opt_eq_func(VALUE recv, VALUE obj, IC ic)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_EQ, FIXNUM_REDEFINED_OP_FLAG)) {
	return (recv == obj) ? Qtrue : Qfalse;
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_EQ, FLOAT_REDEFINED_OP_FLAG)) {
	return (recv == obj) ? Qtrue : Qfalse;
    }
    else if (!SPECIAL_CONST_P(recv) && !SPECIAL_CONST_P(obj)) {
	if (HEAP_CLASS_OF(recv) == rb_cFloat &&
		 HEAP_CLASS_OF(obj) == rb_cFloat &&
	    BASIC_OP_UNREDEFINED_P(BOP_EQ, FLOAT_REDEFINED_OP_FLAG)) {
	    double a = RFLOAT_VALUE(recv);
	    double b = RFLOAT_VALUE(obj);

	    if (isnan(a) || isnan(b)) {
		return Qfalse;
	    }
	    return  (a == b) ? Qtrue : Qfalse;
	}
	else if (HEAP_CLASS_OF(recv) == rb_cString &&
		 HEAP_CLASS_OF(obj) == rb_cString &&
		 BASIC_OP_UNREDEFINED_P(BOP_EQ, STRING_REDEFINED_OP_FLAG)) {
	    return rb_str_equal(recv, obj);
	}
    }

    {
	const rb_method_entry_t *me = vm_method_search(idEq, CLASS_OF(recv), ic, 0);

	if (check_cfunc(me, rb_obj_equal)) {
	    return recv == obj ? Qtrue : Qfalse;
	}
    }

    return Qundef;
}

void rb_using_module(NODE *cref, VALUE module);

static int
vm_using_module_i(VALUE module, VALUE value, VALUE arg)
{
    NODE *cref = (NODE *) arg;

    rb_using_module(cref, module);
    return ST_CONTINUE;
}

static void
rb_vm_using_modules(NODE *cref, VALUE klass)
{
    ID id_using_modules;
    VALUE using_modules;

    CONST_ID(id_using_modules, "__using_modules__");
    using_modules = rb_attr_get(klass, id_using_modules);
    switch (TYPE(klass)) {
    case T_CLASS:
	if (NIL_P(using_modules)) {
	    VALUE super = rb_class_real(RCLASS_SUPER(klass));
	    using_modules = rb_attr_get(super, id_using_modules);
	    if (!NIL_P(using_modules)) {
		using_modules = rb_hash_dup(using_modules);
		rb_ivar_set(klass, id_using_modules, using_modules);
	    }
	}
	break;
    case T_MODULE:
	rb_using_module(cref, klass);
	break;
    }
    if (!NIL_P(using_modules)) {
	rb_hash_foreach(using_modules, vm_using_module_i,
			(VALUE) cref);
    }
}

static VALUE
check_match(VALUE pattern, VALUE target, enum vm_check_match_type type)
{
    switch (type) {
      case VM_CHECKMATCH_TYPE_WHEN:
	return pattern;
      case VM_CHECKMATCH_TYPE_CASE:
	return rb_funcall2(pattern, idEqq, 1, &target);
      case VM_CHECKMATCH_TYPE_RESCUE: {
	if (!rb_obj_is_kind_of(pattern, rb_cModule)) {
	    rb_raise(rb_eTypeError, "class or module required for rescue clause");
	}
	return RTEST(rb_funcall2(pattern, idEqq, 1, &target));
      }
      default:
	rb_bug("check_match: unreachable");
    }
}


#if defined(_MSC_VER) && _MSC_VER < 1300
#define CHECK_CMP_NAN(a, b) if (isnan(a) || isnan(b)) return Qfalse;
#else
#define CHECK_CMP_NAN(a, b) /* do nothing */
#endif

static inline VALUE
double_cmp_lt(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return a < b ? Qtrue : Qfalse;
}

static inline VALUE
double_cmp_le(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return a <= b ? Qtrue : Qfalse;
}

static inline VALUE
double_cmp_gt(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return a > b ? Qtrue : Qfalse;
}

static inline VALUE
double_cmp_ge(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return a >= b ? Qtrue : Qfalse;
}

static VALUE *
vm_base_ptr(rb_control_frame_t *cfp)
{
    rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    VALUE *bp = prev_cfp->sp + cfp->iseq->local_size + 1;

    if (cfp->iseq->type == ISEQ_TYPE_METHOD) {
	/* adjust `self' */
	bp += 1;
    }

#if VM_DEBUG_BP_CHECK
    if (bp != cfp->bp_check) {
	fprintf(stderr, "bp_check: %ld, bp: %ld\n",
		(long)(cfp->bp_check - GET_THREAD()->stack),
		(long)(bp - GET_THREAD()->stack));
	rb_bug("vm_base_ptr: unreachable");
    }
#endif

    return bp;
}

