/**********************************************************************

  vm_insnhelper.c - instruction helper functions.

  $Author$

  Copyright (C) 2007 Koichi Sasada

**********************************************************************/

/* finish iseq array */
#include "insns.inc"
#ifndef MJIT_HEADER
#include "insns_info.inc"
#endif
#include <math.h>
#include "constant.h"
#include "internal.h"
#include "ruby/config.h"
#include "debug_counter.h"

extern rb_method_definition_t *rb_method_definition_create(rb_method_type_t type, ID mid);
extern void rb_method_definition_set(const rb_method_entry_t *me, rb_method_definition_t *def, void *opts);
extern int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);
extern VALUE rb_make_no_method_exception(VALUE exc, VALUE format, VALUE obj,
                                         int argc, const VALUE *argv, int priv);

/* control stack frame */

static rb_control_frame_t *vm_get_ruby_level_caller_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp);

MJIT_STATIC VALUE
ruby_vm_special_exception_copy(VALUE exc)
{
    VALUE e = rb_obj_alloc(rb_class_real(RBASIC_CLASS(exc)));
    rb_obj_copy_ivar(e, exc);
    return e;
}

NORETURN(static void ec_stack_overflow(rb_execution_context_t *ec, int));
static void
ec_stack_overflow(rb_execution_context_t *ec, int setup)
{
    VALUE mesg = rb_ec_vm_ptr(ec)->special_exceptions[ruby_error_sysstack];
    ec->raised_flag = RAISED_STACKOVERFLOW;
    if (setup) {
	VALUE at = rb_ec_backtrace_object(ec);
	mesg = ruby_vm_special_exception_copy(mesg);
	rb_ivar_set(mesg, idBt, at);
	rb_ivar_set(mesg, idBt_locations, at);
    }
    ec->errinfo = mesg;
    EC_JUMP_TAG(ec, TAG_RAISE);
}

NORETURN(static void vm_stackoverflow(void));

static void
vm_stackoverflow(void)
{
    ec_stack_overflow(GET_EC(), TRUE);
}

NORETURN(MJIT_STATIC void rb_ec_stack_overflow(rb_execution_context_t *ec, int crit));
MJIT_STATIC void
rb_ec_stack_overflow(rb_execution_context_t *ec, int crit)
{
    if (crit || rb_during_gc()) {
	ec->raised_flag = RAISED_STACKOVERFLOW;
	ec->errinfo = rb_ec_vm_ptr(ec)->special_exceptions[ruby_error_stackfatal];
	EC_JUMP_TAG(ec, TAG_RAISE);
    }
#ifdef USE_SIGALTSTACK
    ec_stack_overflow(ec, TRUE);
#else
    ec_stack_overflow(ec, FALSE);
#endif
}


#if VM_CHECK_MODE > 0
static int
callable_class_p(VALUE klass)
{
#if VM_CHECK_MODE >= 2
    if (!klass) return FALSE;
    switch (RB_BUILTIN_TYPE(klass)) {
      case T_ICLASS:
	if (!RB_TYPE_P(RCLASS_SUPER(klass), T_MODULE)) break;
      case T_MODULE:
	return TRUE;
    }
    while (klass) {
	if (klass == rb_cBasicObject) {
	    return TRUE;
	}
	klass = RCLASS_SUPER(klass);
    }
    return FALSE;
#else
    return klass != 0;
#endif
}

static int
callable_method_entry_p(const rb_callable_method_entry_t *me)
{
    if (me == NULL || callable_class_p(me->defined_class)) {
	return TRUE;
    }
    else {
	return FALSE;
    }
}

static void
vm_check_frame_detail(VALUE type, int req_block, int req_me, int req_cref, VALUE specval, VALUE cref_or_me, int is_cframe, const rb_iseq_t *iseq)
{
    unsigned int magic = (unsigned int)(type & VM_FRAME_MAGIC_MASK);
    enum imemo_type cref_or_me_type = imemo_env; /* impossible value */

    if (RB_TYPE_P(cref_or_me, T_IMEMO)) {
	cref_or_me_type = imemo_type(cref_or_me);
    }
    if (type & VM_FRAME_FLAG_BMETHOD) {
	req_me = TRUE;
    }

    if (req_block && (type & VM_ENV_FLAG_LOCAL) == 0) {
	rb_bug("vm_push_frame: specval (%p) should be a block_ptr on %x frame", (void *)specval, magic);
    }
    if (!req_block && (type & VM_ENV_FLAG_LOCAL) != 0) {
	rb_bug("vm_push_frame: specval (%p) should not be a block_ptr on %x frame", (void *)specval, magic);
    }

    if (req_me) {
	if (cref_or_me_type != imemo_ment) {
	    rb_bug("vm_push_frame: (%s) should be method entry on %x frame", rb_obj_info(cref_or_me), magic);
	}
    }
    else {
	if (req_cref && cref_or_me_type != imemo_cref) {
	    rb_bug("vm_push_frame: (%s) should be CREF on %x frame", rb_obj_info(cref_or_me), magic);
	}
	else { /* cref or Qfalse */
	    if (cref_or_me != Qfalse && cref_or_me_type != imemo_cref) {
		if (((type & VM_FRAME_FLAG_LAMBDA) || magic == VM_FRAME_MAGIC_IFUNC) && (cref_or_me_type == imemo_ment)) {
		    /* ignore */
		}
		else {
		    rb_bug("vm_push_frame: (%s) should be false or cref on %x frame", rb_obj_info(cref_or_me), magic);
		}
	    }
	}
    }

    if (cref_or_me_type == imemo_ment) {
	const rb_callable_method_entry_t *me = (const rb_callable_method_entry_t *)cref_or_me;

	if (!callable_method_entry_p(me)) {
	    rb_bug("vm_push_frame: ment (%s) should be callable on %x frame.", rb_obj_info(cref_or_me), magic);
	}
    }

    if ((type & VM_FRAME_MAGIC_MASK) == VM_FRAME_MAGIC_DUMMY) {
	VM_ASSERT(iseq == NULL ||
		  RUBY_VM_NORMAL_ISEQ_P(iseq) /* argument error. it shold be fixed */);
    }
    else {
	VM_ASSERT(is_cframe == !RUBY_VM_NORMAL_ISEQ_P(iseq));
    }
}

static void
vm_check_frame(VALUE type,
	       VALUE specval,
	       VALUE cref_or_me,
	       const rb_iseq_t *iseq)
{
    VALUE given_magic = type & VM_FRAME_MAGIC_MASK;
    VM_ASSERT(FIXNUM_P(type));

#define CHECK(magic, req_block, req_me, req_cref, is_cframe) \
    case magic: \
      vm_check_frame_detail(type, req_block, req_me, req_cref, \
			    specval, cref_or_me, is_cframe, iseq); \
      break
    switch (given_magic) {
	/*                           BLK    ME     CREF   CFRAME */
	CHECK(VM_FRAME_MAGIC_METHOD, TRUE,  TRUE,  FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_CLASS,  TRUE,  FALSE, TRUE,  FALSE);
	CHECK(VM_FRAME_MAGIC_TOP,    TRUE,  FALSE, TRUE,  FALSE);
	CHECK(VM_FRAME_MAGIC_CFUNC,  TRUE,  TRUE,  FALSE, TRUE);
	CHECK(VM_FRAME_MAGIC_BLOCK,  FALSE, FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_IFUNC,  FALSE, FALSE, FALSE, TRUE);
	CHECK(VM_FRAME_MAGIC_EVAL,   FALSE, FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_RESCUE, FALSE, FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_DUMMY,  TRUE,  FALSE, FALSE, FALSE);
      default:
	rb_bug("vm_push_frame: unknown type (%x)", (unsigned int)given_magic);
    }
#undef CHECK
}

static VALUE vm_stack_canary; /* Initialized later */
static bool vm_stack_canary_was_born = false;

static void
vm_check_canary(const rb_execution_context_t *ec, VALUE *sp)
{
    const struct rb_control_frame_struct *reg_cfp = ec->cfp;
    const struct rb_iseq_struct *iseq;

    if (! LIKELY(vm_stack_canary_was_born)) {
        return; /* :FIXME: isn't it rather fatal to enter this branch?  */
    }
    else if ((VALUE *)reg_cfp == ec->vm_stack + ec->vm_stack_size) {
        /* This is at the very beginning of a thread. cfp does not exist. */
        return;
    }
    else if (! (iseq = GET_ISEQ())) {
        return;
    }
    else if (LIKELY(sp[0] != vm_stack_canary)) {
        return;
    }
    else {
        /* we are going to call metods below; squash the canary to
         * prevent infinite loop. */
        sp[0] = Qundef;
    }

    const VALUE *orig = rb_iseq_original_iseq(iseq);
    const VALUE *encoded = iseq->body->iseq_encoded;
    const ptrdiff_t pos = GET_PC() - encoded;
    const enum ruby_vminsn_type insn = (enum ruby_vminsn_type)orig[pos];
    const char *name = insn_name(insn);
    const VALUE iseqw = rb_iseqw_new(iseq);
    const VALUE inspection = rb_inspect(iseqw);
    const char *stri = rb_str_to_cstr(inspection);
    const VALUE disasm = rb_iseq_disasm(iseq);
    const char *strd = rb_str_to_cstr(disasm);

    /* rb_bug() is not capable of outputting this large contents.  It
       is designed to run form a SIGSEGV handler, which tends to be
       very restricted. */
    fprintf(stderr,
        "We are killing the stack canary set by %s, "
        "at %s@pc=%"PRIdPTR"\n"
        "watch out the C stack trace.\n"
        "%s",
        name, stri, pos, strd);
    rb_bug("see above.");
}
#else
#define vm_check_canary(ec, sp)
#define vm_check_frame(a, b, c, d)
#endif /* VM_CHECK_MODE > 0 */

static inline rb_control_frame_t *
vm_push_frame(rb_execution_context_t *ec,
	      const rb_iseq_t *iseq,
	      VALUE type,
	      VALUE self,
	      VALUE specval,
	      VALUE cref_or_me,
	      const VALUE *pc,
	      VALUE *sp,
	      int local_size,
	      int stack_max)
{
    rb_control_frame_t *const cfp = ec->cfp - 1;
    int i;

    vm_check_frame(type, specval, cref_or_me, iseq);
    VM_ASSERT(local_size >= 0);

    /* check stack overflow */
    CHECK_VM_STACK_OVERFLOW0(cfp, sp, local_size + stack_max);
    vm_check_canary(ec, sp);

    ec->cfp = cfp;

    /* setup new frame */
    cfp->pc = (VALUE *)pc;
    cfp->iseq = (rb_iseq_t *)iseq;
    cfp->self = self;
    cfp->block_code = NULL;

    /* setup vm value stack */

    /* initialize local variables */
    for (i=0; i < local_size; i++) {
	*sp++ = Qnil;
    }

    /* setup ep with managing data */
    VM_ASSERT(VM_ENV_DATA_INDEX_ME_CREF == -2);
    VM_ASSERT(VM_ENV_DATA_INDEX_SPECVAL == -1);
    VM_ASSERT(VM_ENV_DATA_INDEX_FLAGS   == -0);
    *sp++ = cref_or_me; /* ep[-2] / Qnil or T_IMEMO(cref) or T_IMEMO(ment) */
    *sp++ = specval     /* ep[-1] / block handler or prev env ptr */;
    *sp   = type;       /* ep[-0] / ENV_FLAGS */

    /* Store initial value of ep as bp to skip calculation cost of bp on JIT cancellation. */
    cfp->ep = sp;
    cfp->__bp__ = cfp->sp = sp + 1;

#if VM_DEBUG_BP_CHECK
    cfp->bp_check = sp + 1;
#endif

    if (VMDEBUG == 2) {
	SDR();
    }

#if USE_DEBUG_COUNTER
    RB_DEBUG_COUNTER_INC(frame_push);
    switch (type & VM_FRAME_MAGIC_MASK) {
      case VM_FRAME_MAGIC_METHOD: RB_DEBUG_COUNTER_INC(frame_push_method); break;
      case VM_FRAME_MAGIC_BLOCK:  RB_DEBUG_COUNTER_INC(frame_push_block);  break;
      case VM_FRAME_MAGIC_CLASS:  RB_DEBUG_COUNTER_INC(frame_push_class);  break;
      case VM_FRAME_MAGIC_TOP:    RB_DEBUG_COUNTER_INC(frame_push_top);    break;
      case VM_FRAME_MAGIC_CFUNC:  RB_DEBUG_COUNTER_INC(frame_push_cfunc);  break;
      case VM_FRAME_MAGIC_IFUNC:  RB_DEBUG_COUNTER_INC(frame_push_ifunc);  break;
      case VM_FRAME_MAGIC_EVAL:   RB_DEBUG_COUNTER_INC(frame_push_eval);   break;
      case VM_FRAME_MAGIC_RESCUE: RB_DEBUG_COUNTER_INC(frame_push_rescue); break;
      case VM_FRAME_MAGIC_DUMMY:  RB_DEBUG_COUNTER_INC(frame_push_dummy);  break;
      default: rb_bug("unreachable");
    }
    {
        rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
        if (RUBY_VM_END_CONTROL_FRAME(ec) != prev_cfp) {
            int cur_ruby_frame = VM_FRAME_RUBYFRAME_P(cfp);
            int pre_ruby_frame = VM_FRAME_RUBYFRAME_P(prev_cfp);

            pre_ruby_frame ? (cur_ruby_frame ? RB_DEBUG_COUNTER_INC(frame_R2R) :
                                               RB_DEBUG_COUNTER_INC(frame_R2C)):
                             (cur_ruby_frame ? RB_DEBUG_COUNTER_INC(frame_C2R) :
                                               RB_DEBUG_COUNTER_INC(frame_C2C));
        }
    }
#endif

    return cfp;
}

/* return TRUE if the frame is finished */
static inline int
vm_pop_frame(rb_execution_context_t *ec, rb_control_frame_t *cfp, const VALUE *ep)
{
    VALUE flags = ep[VM_ENV_DATA_INDEX_FLAGS];

    if (VM_CHECK_MODE >= 4) rb_gc_verify_internal_consistency();
    if (VMDEBUG == 2)       SDR();

    ec->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

    return flags & VM_FRAME_FLAG_FINISH;
}

MJIT_STATIC void
rb_vm_pop_frame(rb_execution_context_t *ec)
{
    vm_pop_frame(ec, ec->cfp, ec->cfp->ep);
}

/* method dispatch */
static inline VALUE
rb_arity_error_new(int argc, int min, int max)
{
    VALUE err_mess = 0;
    if (min == max) {
	err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d)", argc, min);
    }
    else if (max == UNLIMITED_ARGUMENTS) {
	err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d+)", argc, min);
    }
    else {
	err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d..%d)", argc, min, max);
    }
    return rb_exc_new3(rb_eArgError, err_mess);
}

MJIT_STATIC void
rb_error_arity(int argc, int min, int max)
{
    rb_exc_raise(rb_arity_error_new(argc, min, max));
}

/* lvar */

NOINLINE(static void vm_env_write_slowpath(const VALUE *ep, int index, VALUE v));

static void
vm_env_write_slowpath(const VALUE *ep, int index, VALUE v)
{
    /* remember env value forcely */
    rb_gc_writebarrier_remember(VM_ENV_ENVVAL(ep));
    VM_FORCE_WRITE(&ep[index], v);
    VM_ENV_FLAGS_UNSET(ep, VM_ENV_FLAG_WB_REQUIRED);
    RB_DEBUG_COUNTER_INC(lvar_set_slowpath);
}

static inline void
vm_env_write(const VALUE *ep, int index, VALUE v)
{
    VALUE flags = ep[VM_ENV_DATA_INDEX_FLAGS];
    if (LIKELY((flags & VM_ENV_FLAG_WB_REQUIRED) == 0)) {
	VM_STACK_ENV_WRITE(ep, index, v);
    }
    else {
	vm_env_write_slowpath(ep, index, v);
    }
}

MJIT_STATIC VALUE
rb_vm_bh_to_procval(const rb_execution_context_t *ec, VALUE block_handler)
{
    if (block_handler == VM_BLOCK_HANDLER_NONE) {
	return Qnil;
    }
    else {
	switch (vm_block_handler_type(block_handler)) {
	  case block_handler_type_iseq:
	  case block_handler_type_ifunc:
	    return rb_vm_make_proc(ec, VM_BH_TO_CAPT_BLOCK(block_handler), rb_cProc);
	  case block_handler_type_symbol:
	    return rb_sym_to_proc(VM_BH_TO_SYMBOL(block_handler));
	  case block_handler_type_proc:
	    return VM_BH_TO_PROC(block_handler);
	  default:
	    VM_UNREACHABLE(rb_vm_bh_to_procval);
	}
    }
}

/* svar */

#if VM_CHECK_MODE > 0
static int
vm_svar_valid_p(VALUE svar)
{
    if (RB_TYPE_P((VALUE)svar, T_IMEMO)) {
	switch (imemo_type(svar)) {
	  case imemo_svar:
	  case imemo_cref:
	  case imemo_ment:
	    return TRUE;
	  default:
	    break;
	}
    }
    rb_bug("vm_svar_valid_p: unknown type: %s", rb_obj_info(svar));
    return FALSE;
}
#endif

static inline struct vm_svar *
lep_svar(const rb_execution_context_t *ec, const VALUE *lep)
{
    VALUE svar;

    if (lep && (ec == NULL || ec->root_lep != lep)) {
	svar = lep[VM_ENV_DATA_INDEX_ME_CREF];
    }
    else {
	svar = ec->root_svar;
    }

    VM_ASSERT(svar == Qfalse || vm_svar_valid_p(svar));

    return (struct vm_svar *)svar;
}

static inline void
lep_svar_write(const rb_execution_context_t *ec, const VALUE *lep, const struct vm_svar *svar)
{
    VM_ASSERT(vm_svar_valid_p((VALUE)svar));

    if (lep && (ec == NULL || ec->root_lep != lep)) {
	vm_env_write(lep, VM_ENV_DATA_INDEX_ME_CREF, (VALUE)svar);
    }
    else {
	RB_OBJ_WRITE(rb_ec_thread_ptr(ec)->self, &ec->root_svar, svar);
    }
}

static VALUE
lep_svar_get(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key)
{
    const struct vm_svar *svar = lep_svar(ec, lep);

    if ((VALUE)svar == Qfalse || imemo_type((VALUE)svar) != imemo_svar) return Qnil;

    switch (key) {
      case VM_SVAR_LASTLINE:
	return svar->lastline;
      case VM_SVAR_BACKREF:
	return svar->backref;
      default: {
	const VALUE ary = svar->others;

	if (NIL_P(ary)) {
	    return Qnil;
	}
	else {
	    return rb_ary_entry(ary, key - VM_SVAR_EXTRA_START);
	}
      }
    }
}

static struct vm_svar *
svar_new(VALUE obj)
{
    return (struct vm_svar *)rb_imemo_new(imemo_svar, Qnil, Qnil, Qnil, obj);
}

static void
lep_svar_set(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key, VALUE val)
{
    struct vm_svar *svar = lep_svar(ec, lep);

    if ((VALUE)svar == Qfalse || imemo_type((VALUE)svar) != imemo_svar) {
	lep_svar_write(ec, lep, svar = svar_new((VALUE)svar));
    }

    switch (key) {
      case VM_SVAR_LASTLINE:
	RB_OBJ_WRITE(svar, &svar->lastline, val);
	return;
      case VM_SVAR_BACKREF:
	RB_OBJ_WRITE(svar, &svar->backref, val);
	return;
      default: {
	VALUE ary = svar->others;

	if (NIL_P(ary)) {
	    RB_OBJ_WRITE(svar, &svar->others, ary = rb_ary_new());
	}
	rb_ary_store(ary, key - VM_SVAR_EXTRA_START, val);
      }
    }
}

static inline VALUE
vm_getspecial(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key, rb_num_t type)
{
    VALUE val;

    if (type == 0) {
	val = lep_svar_get(ec, lep, key);
    }
    else {
	VALUE backref = lep_svar_get(ec, lep, VM_SVAR_BACKREF);

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

PUREFUNC(static rb_callable_method_entry_t *check_method_entry(VALUE obj, int can_be_svar));
static rb_callable_method_entry_t *
check_method_entry(VALUE obj, int can_be_svar)
{
    if (obj == Qfalse) return NULL;

#if VM_CHECK_MODE > 0
    if (!RB_TYPE_P(obj, T_IMEMO)) rb_bug("check_method_entry: unknown type: %s", rb_obj_info(obj));
#endif

    switch (imemo_type(obj)) {
      case imemo_ment:
	return (rb_callable_method_entry_t *)obj;
      case imemo_cref:
	return NULL;
      case imemo_svar:
	if (can_be_svar) {
	    return check_method_entry(((struct vm_svar *)obj)->cref_or_me, FALSE);
	}
      default:
#if VM_CHECK_MODE > 0
	rb_bug("check_method_entry: svar should not be there:");
#endif
	return NULL;
    }
}

MJIT_STATIC const rb_callable_method_entry_t *
rb_vm_frame_method_entry(const rb_control_frame_t *cfp)
{
    const VALUE *ep = cfp->ep;
    rb_callable_method_entry_t *me;

    while (!VM_ENV_LOCAL_P(ep)) {
	if ((me = check_method_entry(ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE)) != NULL) return me;
	ep = VM_ENV_PREV_EP(ep);
    }

    return check_method_entry(ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE);
}

static rb_cref_t *
method_entry_cref(rb_callable_method_entry_t *me)
{
    switch (me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
	return me->def->body.iseq.cref;
      default:
	return NULL;
    }
}

#if VM_CHECK_MODE == 0
PUREFUNC(static rb_cref_t *check_cref(VALUE, int));
#endif
static rb_cref_t *
check_cref(VALUE obj, int can_be_svar)
{
    if (obj == Qfalse) return NULL;

#if VM_CHECK_MODE > 0
    if (!RB_TYPE_P(obj, T_IMEMO)) rb_bug("check_cref: unknown type: %s", rb_obj_info(obj));
#endif

    switch (imemo_type(obj)) {
      case imemo_ment:
	return method_entry_cref((rb_callable_method_entry_t *)obj);
      case imemo_cref:
	return (rb_cref_t *)obj;
      case imemo_svar:
	if (can_be_svar) {
	    return check_cref(((struct vm_svar *)obj)->cref_or_me, FALSE);
	}
      default:
#if VM_CHECK_MODE > 0
	rb_bug("check_method_entry: svar should not be there:");
#endif
	return NULL;
    }
}

static inline rb_cref_t *
vm_env_cref(const VALUE *ep)
{
    rb_cref_t *cref;

    while (!VM_ENV_LOCAL_P(ep)) {
	if ((cref = check_cref(ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE)) != NULL) return cref;
	ep = VM_ENV_PREV_EP(ep);
    }

    return check_cref(ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE);
}

static int
is_cref(const VALUE v, int can_be_svar)
{
    if (RB_TYPE_P(v, T_IMEMO)) {
	switch (imemo_type(v)) {
	  case imemo_cref:
	    return TRUE;
	  case imemo_svar:
	    if (can_be_svar) return is_cref(((struct vm_svar *)v)->cref_or_me, FALSE);
	  default:
	    break;
	}
    }
    return FALSE;
}

static int
vm_env_cref_by_cref(const VALUE *ep)
{
    while (!VM_ENV_LOCAL_P(ep)) {
	if (is_cref(ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE)) return TRUE;
	ep = VM_ENV_PREV_EP(ep);
    }
    return is_cref(ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE);
}

static rb_cref_t *
cref_replace_with_duplicated_cref_each_frame(const VALUE *vptr, int can_be_svar, VALUE parent)
{
    const VALUE v = *vptr;
    rb_cref_t *cref, *new_cref;

    if (RB_TYPE_P(v, T_IMEMO)) {
	switch (imemo_type(v)) {
	  case imemo_cref:
	    cref = (rb_cref_t *)v;
	    new_cref = vm_cref_dup(cref);
	    if (parent) {
		RB_OBJ_WRITE(parent, vptr, new_cref);
	    }
	    else {
		VM_FORCE_WRITE(vptr, (VALUE)new_cref);
	    }
	    return (rb_cref_t *)new_cref;
	  case imemo_svar:
	    if (can_be_svar) {
		return cref_replace_with_duplicated_cref_each_frame((const VALUE *)&((struct vm_svar *)v)->cref_or_me, FALSE, v);
	    }
            /* fall through */
	  case imemo_ment:
	    rb_bug("cref_replace_with_duplicated_cref_each_frame: unreachable");
	  default:
	    break;
	}
    }
    return FALSE;
}

static rb_cref_t *
vm_cref_replace_with_duplicated_cref(const VALUE *ep)
{
    if (vm_env_cref_by_cref(ep)) {
	rb_cref_t *cref;
	VALUE envval;

	while (!VM_ENV_LOCAL_P(ep)) {
	    envval = VM_ENV_ESCAPED_P(ep) ? VM_ENV_ENVVAL(ep) : Qfalse;
	    if ((cref = cref_replace_with_duplicated_cref_each_frame(&ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE, envval)) != NULL) {
		return cref;
	    }
	    ep = VM_ENV_PREV_EP(ep);
	}
	envval = VM_ENV_ESCAPED_P(ep) ? VM_ENV_ENVVAL(ep) : Qfalse;
	return cref_replace_with_duplicated_cref_each_frame(&ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE, envval);
    }
    else {
	rb_bug("vm_cref_dup: unreachable");
    }
}

static rb_cref_t *
vm_get_cref(const VALUE *ep)
{
    rb_cref_t *cref = vm_env_cref(ep);

    if (cref != NULL) {
	return cref;
    }
    else {
        rb_bug("vm_get_cref: unreachable");
    }
}

static rb_cref_t *
vm_ec_cref(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (cfp == NULL) {
        return NULL;
    }
    return vm_get_cref(cfp->ep);
}

static const rb_cref_t *
vm_get_const_key_cref(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);
    const rb_cref_t *key_cref = cref;

    while (cref) {
        if (FL_TEST(CREF_CLASS(cref), FL_SINGLETON) ||
            FL_TEST(CREF_CLASS(cref), RCLASS_CLONED)) {
            return key_cref;
	}
	cref = CREF_NEXT(cref);
    }

    /* does not include singleton class */
    return NULL;
}

void
rb_vm_rewrite_cref(rb_cref_t *cref, VALUE old_klass, VALUE new_klass, rb_cref_t **new_cref_ptr)
{
    rb_cref_t *new_cref;

    while (cref) {
	if (CREF_CLASS(cref) == old_klass) {
	    new_cref = vm_cref_new_use_prev(new_klass, METHOD_VISI_UNDEF, FALSE, cref, FALSE);
	    *new_cref_ptr = new_cref;
	    return;
	}
	new_cref = vm_cref_new_use_prev(CREF_CLASS(cref), METHOD_VISI_UNDEF, FALSE, cref, FALSE);
	cref = CREF_NEXT(cref);
	*new_cref_ptr = new_cref;
	new_cref_ptr = (rb_cref_t **)&new_cref->next;
    }
    *new_cref_ptr = NULL;
}

static rb_cref_t *
vm_cref_push(const rb_execution_context_t *ec, VALUE klass, const VALUE *ep, int pushed_by_eval)
{
    rb_cref_t *prev_cref = NULL;

    if (ep) {
	prev_cref = vm_env_cref(ep);
    }
    else {
	rb_control_frame_t *cfp = vm_get_ruby_level_caller_cfp(ec, ec->cfp);

	if (cfp) {
	    prev_cref = vm_env_cref(cfp->ep);
	}
    }

    return vm_cref_new(klass, METHOD_VISI_PUBLIC, FALSE, prev_cref, pushed_by_eval);
}

static inline VALUE
vm_get_cbase(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);
    VALUE klass = Qundef;

    while (cref) {
	if ((klass = CREF_CLASS(cref)) != 0) {
	    break;
	}
	cref = CREF_NEXT(cref);
    }

    return klass;
}

static inline VALUE
vm_get_const_base(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);
    VALUE klass = Qundef;

    while (cref) {
	if (!CREF_PUSHED_BY_EVAL(cref) &&
	    (klass = CREF_CLASS(cref)) != 0) {
	    break;
	}
	cref = CREF_NEXT(cref);
    }

    return klass;
}

static inline void
vm_check_if_namespace(VALUE klass)
{
    if (!RB_TYPE_P(klass, T_CLASS) && !RB_TYPE_P(klass, T_MODULE)) {
	rb_raise(rb_eTypeError, "%+"PRIsVALUE" is not a class/module", klass);
    }
}

static inline void
vm_ensure_not_refinement_module(VALUE self)
{
    if (RB_TYPE_P(self, T_MODULE) && FL_TEST(self, RMODULE_IS_REFINEMENT)) {
	rb_warn("not defined at the refinement, but at the outer class/module");
    }
}

static inline VALUE
vm_get_iclass(rb_control_frame_t *cfp, VALUE klass)
{
    return klass;
}

static inline VALUE
vm_get_ev_const(rb_execution_context_t *ec, VALUE orig_klass, ID id, int allow_nil, int is_defined)
{
    void rb_const_warn_if_deprecated(const rb_const_entry_t *ce, VALUE klass, ID id);
    VALUE val;

    if (orig_klass == Qnil && allow_nil) {
	/* in current lexical scope */
        const rb_cref_t *root_cref = vm_get_cref(ec->cfp->ep);
	const rb_cref_t *cref;
	VALUE klass = Qnil;

	while (root_cref && CREF_PUSHED_BY_EVAL(root_cref)) {
	    root_cref = CREF_NEXT(root_cref);
	}
	cref = root_cref;
	while (cref && CREF_NEXT(cref)) {
	    if (CREF_PUSHED_BY_EVAL(cref)) {
		klass = Qnil;
	    }
	    else {
		klass = CREF_CLASS(cref);
	    }
	    cref = CREF_NEXT(cref);

	    if (!NIL_P(klass)) {
		VALUE av, am = 0;
		rb_const_entry_t *ce;
	      search_continue:
		if ((ce = rb_const_lookup(klass, id))) {
		    rb_const_warn_if_deprecated(ce, klass, id);
		    val = ce->value;
		    if (val == Qundef) {
			if (am == klass) break;
			am = klass;
			if (is_defined) return 1;
			if (rb_autoloading_value(klass, id, &av, NULL)) return av;
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
	if (root_cref && !NIL_P(CREF_CLASS(root_cref))) {
	    klass = vm_get_iclass(ec->cfp, CREF_CLASS(root_cref));
	}
	else {
	    klass = CLASS_OF(ec->cfp->self);
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
vm_get_cvar_base(const rb_cref_t *cref, rb_control_frame_t *cfp)
{
    VALUE klass;

    if (!cref) {
	rb_bug("vm_get_cvar_base: no cref");
    }

    while (CREF_NEXT(cref) &&
	   (NIL_P(CREF_CLASS(cref)) || FL_TEST(CREF_CLASS(cref), FL_SINGLETON) ||
	    CREF_PUSHED_BY_EVAL(cref))) {
	cref = CREF_NEXT(cref);
    }
    if (!CREF_NEXT(cref)) {
	rb_warn("class variable access from toplevel");
    }

    klass = vm_get_iclass(cfp, CREF_CLASS(cref));

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

ALWAYS_INLINE(static VALUE vm_getivar(VALUE, ID, IC, struct rb_call_cache *, int));
static inline VALUE
vm_getivar(VALUE obj, ID id, IC ic, struct rb_call_cache *cc, int is_attr)
{
#if OPT_IC_FOR_IVAR
    if (LIKELY(RB_TYPE_P(obj, T_OBJECT))) {
	VALUE val = Qundef;
        if (LIKELY(is_attr ?
		   RB_DEBUG_COUNTER_INC_UNLESS(ivar_get_ic_miss_unset, cc->aux.index > 0) :
		   RB_DEBUG_COUNTER_INC_UNLESS(ivar_get_ic_miss_serial,
					       ic->ic_serial == RCLASS_SERIAL(RBASIC(obj)->klass)))) {
            st_index_t index = !is_attr ? ic->ic_value.index : (cc->aux.index - 1);
	    if (LIKELY(index < ROBJECT_NUMIV(obj))) {
		val = ROBJECT_IVPTR(obj)[index];
	    }
	}
	else {
            st_data_t index;
	    struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);

	    if (iv_index_tbl) {
		if (st_lookup(iv_index_tbl, id, &index)) {
		    if (index < ROBJECT_NUMIV(obj)) {
			val = ROBJECT_IVPTR(obj)[index];
		    }
                    if (!is_attr) {
                        ic->ic_value.index = index;
                        ic->ic_serial = RCLASS_SERIAL(RBASIC(obj)->klass);
                    }
                    else { /* call_info */
                        cc->aux.index = (int)index + 1;
                    }
		}
	    }
	}
	if (UNLIKELY(val == Qundef)) {
	    if (!is_attr && RTEST(ruby_verbose))
		rb_warning("instance variable %"PRIsVALUE" not initialized", QUOTE_ID(id));
	    val = Qnil;
	}
	RB_DEBUG_COUNTER_INC(ivar_get_ic_hit);
	return val;
    }
    else {
	RB_DEBUG_COUNTER_INC(ivar_get_ic_miss_noobject);
    }
#endif /* OPT_IC_FOR_IVAR */
    RB_DEBUG_COUNTER_INC(ivar_get_ic_miss);

    if (is_attr)
	return rb_attr_get(obj, id);
    return rb_ivar_get(obj, id);
}

static inline VALUE
vm_setivar(VALUE obj, ID id, VALUE val, IC ic, struct rb_call_cache *cc, int is_attr)
{
#if OPT_IC_FOR_IVAR
    rb_check_frozen_internal(obj);

    if (LIKELY(RB_TYPE_P(obj, T_OBJECT))) {
	VALUE klass = RBASIC(obj)->klass;
	st_data_t index;

	if (LIKELY(
	    (!is_attr && RB_DEBUG_COUNTER_INC_UNLESS(ivar_set_ic_miss_serial, ic->ic_serial == RCLASS_SERIAL(klass))) ||
	    ( is_attr && RB_DEBUG_COUNTER_INC_UNLESS(ivar_set_ic_miss_unset, cc->aux.index > 0)))) {
	    VALUE *ptr = ROBJECT_IVPTR(obj);
	    index = !is_attr ? ic->ic_value.index : cc->aux.index-1;

	    if (RB_DEBUG_COUNTER_INC_UNLESS(ivar_set_ic_miss_oorange, index < ROBJECT_NUMIV(obj))) {
		RB_OBJ_WRITE(obj, &ptr[index], val);
		RB_DEBUG_COUNTER_INC(ivar_set_ic_hit);
		return val; /* inline cache hit */
	    }
	}
	else {
	    struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);

	    if (iv_index_tbl && st_lookup(iv_index_tbl, (st_data_t)id, &index)) {
                if (!is_attr) {
                    ic->ic_value.index = index;
                    ic->ic_serial = RCLASS_SERIAL(klass);
                }
		else if (index >= INT_MAX) {
		    rb_raise(rb_eArgError, "too many instance variables");
		}
		else {
		    cc->aux.index = (int)(index + 1);
		}
	    }
	    /* fall through */
	}
    }
    else {
	RB_DEBUG_COUNTER_INC(ivar_set_ic_miss_noobject);
    }
#endif /* OPT_IC_FOR_IVAR */
    RB_DEBUG_COUNTER_INC(ivar_set_ic_miss);
    return rb_ivar_set(obj, id, val);
}

static inline VALUE
vm_getinstancevariable(VALUE obj, ID id, IC ic)
{
    return vm_getivar(obj, id, ic, NULL, FALSE);
}

static inline void
vm_setinstancevariable(VALUE obj, ID id, VALUE val, IC ic)
{
    vm_setivar(obj, id, val, ic, 0, 0);
}

static VALUE
vm_throw_continue(const rb_execution_context_t *ec, VALUE err)
{
    /* continue throw */

    if (FIXNUM_P(err)) {
	ec->tag->state = FIX2INT(err);
    }
    else if (SYMBOL_P(err)) {
	ec->tag->state = TAG_THROW;
    }
    else if (THROW_DATA_P(err)) {
	ec->tag->state = THROW_DATA_STATE((struct vm_throw_data *)err);
    }
    else {
	ec->tag->state = TAG_RAISE;
    }
    return err;
}

static VALUE
vm_throw_start(const rb_execution_context_t *ec, rb_control_frame_t *const reg_cfp, enum ruby_tag_type state,
               const int flag, const VALUE throwobj)
{
    const rb_control_frame_t *escape_cfp = NULL;
    const rb_control_frame_t * const eocfp = RUBY_VM_END_CONTROL_FRAME(ec); /* end of control frame pointer */

    if (flag != 0) {
	/* do nothing */
    }
    else if (state == TAG_BREAK) {
	int is_orphan = 1;
	const VALUE *ep = GET_EP();
	const rb_iseq_t *base_iseq = GET_ISEQ();
	escape_cfp = reg_cfp;

	while (base_iseq->body->type != ISEQ_TYPE_BLOCK) {
	    if (escape_cfp->iseq->body->type == ISEQ_TYPE_CLASS) {
		escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
		ep = escape_cfp->ep;
		base_iseq = escape_cfp->iseq;
	    }
	    else {
		ep = VM_ENV_PREV_EP(ep);
		base_iseq = base_iseq->body->parent_iseq;
		escape_cfp = rb_vm_search_cf_from_ep(ec, escape_cfp, ep);
		VM_ASSERT(escape_cfp->iseq == base_iseq);
	    }
	}

	if (VM_FRAME_LAMBDA_P(escape_cfp)) {
	    /* lambda{... break ...} */
	    is_orphan = 0;
	    state = TAG_RETURN;
	}
	else {
	    ep = VM_ENV_PREV_EP(ep);

	    while (escape_cfp < eocfp) {
		if (escape_cfp->ep == ep) {
		    const rb_iseq_t *const iseq = escape_cfp->iseq;
		    const VALUE epc = escape_cfp->pc - iseq->body->iseq_encoded;
		    const struct iseq_catch_table *const ct = iseq->body->catch_table;
		    unsigned int i;

		    if (!ct) break;
		    for (i=0; i < ct->size; i++) {
			const struct iseq_catch_table_entry *const entry =
			    UNALIGNED_MEMBER_PTR(ct, entries[i]);

			if (entry->type == CATCH_TYPE_BREAK &&
			    entry->iseq == base_iseq &&
			    entry->start < epc && entry->end >= epc) {
			    if (entry->cont == epc) { /* found! */
				is_orphan = 0;
			    }
			    break;
			}
		    }
		    break;
		}

		escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
	    }
	}

	if (is_orphan) {
	    rb_vm_localjump_error("break from proc-closure", throwobj, TAG_BREAK);
	}
    }
    else if (state == TAG_RETRY) {
	const VALUE *ep = VM_ENV_PREV_EP(GET_EP());

	escape_cfp = rb_vm_search_cf_from_ep(ec, reg_cfp, ep);
    }
    else if (state == TAG_RETURN) {
	const VALUE *current_ep = GET_EP();
	const VALUE *target_lep = VM_EP_LEP(current_ep);
	int in_class_frame = 0;
	int toplevel = 1;
	escape_cfp = reg_cfp;

	while (escape_cfp < eocfp) {
	    const VALUE *lep = VM_CF_LEP(escape_cfp);

	    if (!target_lep) {
		target_lep = lep;
	    }

	    if (lep == target_lep &&
		VM_FRAME_RUBYFRAME_P(escape_cfp) &&
		escape_cfp->iseq->body->type == ISEQ_TYPE_CLASS) {
		in_class_frame = 1;
		target_lep = 0;
	    }

	    if (lep == target_lep) {
		if (VM_FRAME_LAMBDA_P(escape_cfp)) {
		    toplevel = 0;
		    if (in_class_frame) {
			/* lambda {class A; ... return ...; end} */
			goto valid_return;
		    }
		    else {
			const VALUE *tep = current_ep;

			while (target_lep != tep) {
			    if (escape_cfp->ep == tep) {
				/* in lambda */
				goto valid_return;
			    }
			    tep = VM_ENV_PREV_EP(tep);
			}
		    }
		}
		else if (VM_FRAME_RUBYFRAME_P(escape_cfp)) {
		    switch (escape_cfp->iseq->body->type) {
		      case ISEQ_TYPE_TOP:
		      case ISEQ_TYPE_MAIN:
			if (toplevel) goto valid_return;
			break;
		      case ISEQ_TYPE_EVAL:
		      case ISEQ_TYPE_CLASS:
			toplevel = 0;
			break;
		      default:
			break;
		    }
		}
	    }

	    if (escape_cfp->ep == target_lep && escape_cfp->iseq->body->type == ISEQ_TYPE_METHOD) {
		goto valid_return;
	    }

	    escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
	}
	rb_vm_localjump_error("unexpected return", throwobj, TAG_RETURN);

      valid_return:;
	/* do nothing */
    }
    else {
	rb_bug("isns(throw): unsupport throw type");
    }

    ec->tag->state = state;
    return (VALUE)THROW_DATA_NEW(throwobj, escape_cfp, state);
}

static VALUE
vm_throw(const rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
	 rb_num_t throw_state, VALUE throwobj)
{
    const int state = (int)(throw_state & VM_THROW_STATE_MASK);
    const int flag = (int)(throw_state & VM_THROW_NO_ESCAPE_FLAG);

    if (state != 0) {
        return vm_throw_start(ec, reg_cfp, state, flag, throwobj);
    }
    else {
	return vm_throw_continue(ec, throwobj);
    }
}

static inline void
vm_expandarray(VALUE *sp, VALUE ary, rb_num_t num, int flag)
{
    int is_splat = flag & 0x01;
    rb_num_t space_size = num + is_splat;
    VALUE *base = sp - 1;
    const VALUE *ptr;
    rb_num_t len;
    const VALUE obj = ary;

    if (!RB_TYPE_P(ary, T_ARRAY) && NIL_P(ary = rb_check_array_type(ary))) {
	ary = obj;
	ptr = &ary;
	len = 1;
    }
    else {
        ptr = RARRAY_CONST_PTR_TRANSIENT(ary);
	len = (rb_num_t)RARRAY_LEN(ary);
    }

    if (space_size == 0) {
        /* no space left on stack */
    }
    else if (flag & 0x02) {
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

static VALUE vm_call_general(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);

MJIT_FUNC_EXPORTED void
rb_vm_search_method_slowpath(const struct rb_call_info *ci, struct rb_call_cache *cc, VALUE klass)
{
    cc->me = rb_callable_method_entry(klass, ci->mid);
    VM_ASSERT(callable_method_entry_p(cc->me));
    cc->call = vm_call_general;
#if OPT_INLINE_METHOD_CACHE
    cc->method_state = GET_GLOBAL_METHOD_STATE();
    cc->class_serial = RCLASS_SERIAL(klass);
#endif
}

static void
vm_search_method(const struct rb_call_info *ci, struct rb_call_cache *cc, VALUE recv)
{
    VALUE klass = CLASS_OF(recv);

    VM_ASSERT(klass != Qfalse);
    VM_ASSERT(RBASIC_CLASS(klass) == 0 || rb_obj_is_kind_of(klass, rb_cClass));

#if OPT_INLINE_METHOD_CACHE
    if (LIKELY(RB_DEBUG_COUNTER_INC_UNLESS(mc_global_state_miss,
					   GET_GLOBAL_METHOD_STATE() == cc->method_state) &&
	       RB_DEBUG_COUNTER_INC_UNLESS(mc_class_serial_miss,
					   RCLASS_SERIAL(klass) == cc->class_serial))) {
	/* cache hit! */
	VM_ASSERT(cc->call != NULL);
	RB_DEBUG_COUNTER_INC(mc_inline_hit);
	return;
    }
    RB_DEBUG_COUNTER_INC(mc_inline_miss);
#endif
    rb_vm_search_method_slowpath(ci, cc, klass);
}

static inline int
check_cfunc(const rb_callable_method_entry_t *me, VALUE (*func)())
{
    if (me && me->def->type == VM_METHOD_TYPE_CFUNC &&
	me->def->body.cfunc.func == func) {
	return 1;
    }
    else {
	return 0;
    }
}

static inline int
vm_method_cfunc_is(CALL_INFO ci, CALL_CACHE cc,
		   VALUE recv, VALUE (*func)())
{
    vm_search_method(ci, cc, recv);
    return check_cfunc(cc->me, func);
}

static VALUE
opt_equal_fallback(VALUE recv, VALUE obj, CALL_INFO ci, CALL_CACHE cc)
{
    if (vm_method_cfunc_is(ci, cc, recv, rb_obj_equal)) {
	return recv == obj ? Qtrue : Qfalse;
    }

    return Qundef;
}

#define BUILTIN_CLASS_P(x, k) (!SPECIAL_CONST_P(x) && RBASIC_CLASS(x) == k)
#define EQ_UNREDEFINED_P(t) BASIC_OP_UNREDEFINED_P(BOP_EQ, t##_REDEFINED_OP_FLAG)

static inline bool
FIXNUM_2_P(VALUE a, VALUE b)
{
    /* FIXNUM_P(a) && FIXNUM_P(b)
     * == ((a & 1) && (b & 1))
     * == a & b & 1 */
    SIGNED_VALUE x = a;
    SIGNED_VALUE y = b;
    SIGNED_VALUE z = x & y & 1;
    return z == 1;
}

static inline bool
FLONUM_2_P(VALUE a, VALUE b)
{
#if USE_FLONUM
    /* FLONUM_P(a) && FLONUM_P(b)
     * == ((a & 3) == 2) && ((b & 3) == 2)
     * == ! ((a ^ 2) | (b ^ 2) & 3)
     */
    SIGNED_VALUE x = a;
    SIGNED_VALUE y = b;
    SIGNED_VALUE z = ((x ^ 2) | (y ^ 2)) & 3;
    return !z;
#else
    return false;
#endif
}

/* 1: compare by identity, 0: not applicable, -1: redefined */
static inline int
comparable_by_identity(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj)) {
	return (EQ_UNREDEFINED_P(INTEGER) != 0) * 2 - 1;
    }
    if (FLONUM_2_P(recv, obj)) {
	return (EQ_UNREDEFINED_P(FLOAT) != 0) * 2 - 1;
    }
    if (SYMBOL_P(recv) && SYMBOL_P(obj)) {
	return (EQ_UNREDEFINED_P(SYMBOL) != 0) * 2 - 1;
    }
    return 0;
}

static
#ifndef NO_BIG_INLINE
inline
#endif
VALUE
opt_eq_func(VALUE recv, VALUE obj, CALL_INFO ci, CALL_CACHE cc)
{
    switch (comparable_by_identity(recv, obj)) {
      case 1:
	return (recv == obj) ? Qtrue : Qfalse;
      case -1:
	goto fallback;
    }
    if (0) {
    }
    else if (BUILTIN_CLASS_P(recv, rb_cFloat)) {
	if (EQ_UNREDEFINED_P(FLOAT)) {
	    return rb_float_equal(recv, obj);
	}
    }
    else if (BUILTIN_CLASS_P(recv, rb_cString) && EQ_UNREDEFINED_P(STRING)) {
        if (recv == obj) return Qtrue;
        if (RB_TYPE_P(obj, T_STRING)) {
            return rb_str_eql_internal(recv, obj);
        }
    }

  fallback:
    return opt_equal_fallback(recv, obj, ci, cc);
}

static
#ifndef NO_BIG_INLINE
inline
#endif
VALUE
opt_eql_func(VALUE recv, VALUE obj, CALL_INFO ci, CALL_CACHE cc)
{
    switch (comparable_by_identity(recv, obj)) {
      case 1:
	return (recv == obj) ? Qtrue : Qfalse;
      case -1:
	goto fallback;
    }
    if (0) {
    }
    else if (BUILTIN_CLASS_P(recv, rb_cFloat)) {
	if (EQ_UNREDEFINED_P(FLOAT)) {
	    return rb_float_eql(recv, obj);
	}
    }
    else if (BUILTIN_CLASS_P(recv, rb_cString)) {
	if (EQ_UNREDEFINED_P(STRING)) {
	    return rb_str_eql(recv, obj);
	}
    }

  fallback:
    return opt_equal_fallback(recv, obj, ci, cc);
}
#undef BUILTIN_CLASS_P
#undef EQ_UNREDEFINED_P

VALUE
rb_equal_opt(VALUE obj1, VALUE obj2)
{
    struct rb_call_info ci;
    struct rb_call_cache cc;

    ci.mid = idEq;
    cc.method_state = 0;
    cc.class_serial = 0;
    cc.me = NULL;
    return opt_eq_func(obj1, obj2, &ci, &cc);
}

VALUE
rb_eql_opt(VALUE obj1, VALUE obj2)
{
    struct rb_call_info ci;
    struct rb_call_cache cc;

    ci.mid = idEqlP;
    cc.method_state = 0;
    cc.class_serial = 0;
    cc.me = NULL;
    return opt_eql_func(obj1, obj2, &ci, &cc);
}

extern VALUE rb_vm_call0(rb_execution_context_t *ec, VALUE, ID, int, const VALUE*, const rb_callable_method_entry_t *);

static VALUE
check_match(rb_execution_context_t *ec, VALUE pattern, VALUE target, enum vm_check_match_type type)
{
    switch (type) {
      case VM_CHECKMATCH_TYPE_WHEN:
	return pattern;
      case VM_CHECKMATCH_TYPE_RESCUE:
	if (!rb_obj_is_kind_of(pattern, rb_cModule)) {
	    rb_raise(rb_eTypeError, "class or module required for rescue clause");
	}
	/* fall through */
      case VM_CHECKMATCH_TYPE_CASE: {
	const rb_callable_method_entry_t *me =
	    rb_callable_method_entry_with_refinements(CLASS_OF(pattern), idEqq, NULL);
	if (me) {
            return rb_vm_call0(ec, pattern, idEqq, 1, &target, me);
	}
	else {
	    /* fallback to funcall (e.g. method_missing) */
	    return rb_funcallv(pattern, idEqq, 1, &target);
	}
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

static inline VALUE *
vm_base_ptr(const rb_control_frame_t *cfp)
{
#if 0 // we may optimize and use this once we confirm it does not spoil performance on JIT.
    const rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

    if (cfp->iseq && VM_FRAME_RUBYFRAME_P(cfp)) {
	VALUE *bp = prev_cfp->sp + cfp->iseq->body->local_table_size + VM_ENV_DATA_SIZE;
	if (cfp->iseq->body->type == ISEQ_TYPE_METHOD) {
	    /* adjust `self' */
	    bp += 1;
	}
#if VM_DEBUG_BP_CHECK
	if (bp != cfp->bp_check) {
	    fprintf(stderr, "bp_check: %ld, bp: %ld\n",
		    (long)(cfp->bp_check - GET_EC()->vm_stack),
		    (long)(bp - GET_EC()->vm_stack));
	    rb_bug("vm_base_ptr: unreachable");
	}
#endif
	return bp;
    }
    else {
	return NULL;
    }
#else
    return cfp->__bp__;
#endif
}

/* method call processes with call_info */

#include "vm_args.c"

static inline VALUE vm_call_iseq_setup_2(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, int opt_pc, int param_size, int local_size);
ALWAYS_INLINE(static VALUE vm_call_iseq_setup_normal(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const rb_callable_method_entry_t *me, int opt_pc, int param_size, int local_size));
static inline VALUE vm_call_iseq_setup_tailcall(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, int opt_pc);
static VALUE vm_call_super_method(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);
static VALUE vm_call_method_nome(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);
static VALUE vm_call_method_each_type(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);
static inline VALUE vm_call_method(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);

static vm_call_handler vm_call_iseq_setup_func(const struct rb_call_info *ci, const int param_size, const int local_size);

static VALUE
vm_call_iseq_setup_tailcall_0start(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_setup_tailcall_0start);

    return vm_call_iseq_setup_tailcall(ec, cfp, calling, ci, cc, 0);
}

static VALUE
vm_call_iseq_setup_normal_0start(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_setup_0start);

    const rb_iseq_t *iseq = def_iseq_ptr(cc->me->def);
    int param = iseq->body->param.size;
    int local = iseq->body->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, cc->me, 0, param, local);
}

MJIT_STATIC bool
rb_simple_iseq_p(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_opt == FALSE &&
           iseq->body->param.flags.has_rest == FALSE &&
	   iseq->body->param.flags.has_post == FALSE &&
	   iseq->body->param.flags.has_kw == FALSE &&
	   iseq->body->param.flags.has_kwrest == FALSE &&
	   iseq->body->param.flags.has_block == FALSE;
}

static bool
rb_iseq_only_optparam_p(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_opt == TRUE &&
           iseq->body->param.flags.has_rest == FALSE &&
           iseq->body->param.flags.has_post == FALSE &&
           iseq->body->param.flags.has_kw == FALSE &&
           iseq->body->param.flags.has_kwrest == FALSE &&
           iseq->body->param.flags.has_block == FALSE;
}

static bool
rb_iseq_only_kwparam_p(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_opt == FALSE &&
           iseq->body->param.flags.has_rest == FALSE &&
           iseq->body->param.flags.has_post == FALSE &&
           iseq->body->param.flags.has_kw == TRUE &&
           iseq->body->param.flags.has_kwrest == FALSE &&
           iseq->body->param.flags.has_block == FALSE;
}


static inline void
CALLER_SETUP_ARG(struct rb_control_frame_struct *restrict cfp,
                 struct rb_calling_info *restrict calling,
                 const struct rb_call_info *restrict ci)
{
    if (UNLIKELY(IS_ARGS_SPLAT(ci))) {
        vm_caller_setup_arg_splat(cfp, calling);
    }
    if (UNLIKELY(IS_ARGS_KEYWORD(ci))) {
        vm_caller_setup_arg_kw(cfp, calling, ci);
    }
}

#define USE_OPT_HIST 0

#if USE_OPT_HIST
#define OPT_HIST_MAX 64
static int opt_hist[OPT_HIST_MAX+1];

__attribute__((destructor))
static void
opt_hist_show_results_at_exit(void)
{
    for (int i=0; i<OPT_HIST_MAX; i++) {
        fprintf(stderr, "opt_hist\t%d\t%d\n", i, opt_hist[i]);
    }
}
#endif

static VALUE
vm_call_iseq_setup_normal_opt_start(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                    struct rb_calling_info *calling,
                                    const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    const rb_iseq_t *iseq = def_iseq_ptr(cc->me->def);
    const int lead_num = iseq->body->param.lead_num;
    const int opt = calling->argc - lead_num;
    const int opt_num = iseq->body->param.opt_num;
    const int opt_pc = (int)iseq->body->param.opt_table[opt];
    const int param = iseq->body->param.size;
    const int local = iseq->body->local_table_size;
    const int delta = opt_num - opt;

    RB_DEBUG_COUNTER_INC(ccf_iseq_opt);

#if USE_OPT_HIST
    if (opt_pc < OPT_HIST_MAX) {
        opt_hist[opt]++;
    }
    else {
        opt_hist[OPT_HIST_MAX]++;
    }
#endif

    return vm_call_iseq_setup_normal(ec, cfp, calling, cc->me, opt_pc, param - delta, local);
}

static void
args_setup_kw_parameters(rb_execution_context_t *const ec, const rb_iseq_t *const iseq,
                         VALUE *const passed_values, const int passed_keyword_len, const VALUE *const passed_keywords,
                         VALUE *const locals);

static VALUE
vm_call_iseq_setup_kwparm_kwarg(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                struct rb_calling_info *calling,
                                const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VM_ASSERT(ci->flag & VM_CALL_KWARG);
    RB_DEBUG_COUNTER_INC(ccf_iseq_kw1);

    const rb_iseq_t *iseq = def_iseq_ptr(cc->me->def);
    const struct rb_iseq_param_keyword *kw_param = iseq->body->param.keyword;
    const struct rb_call_info_kw_arg *kw_arg = ((struct rb_call_info_with_kwarg *)ci)->kw_arg;
    const int ci_kw_len = kw_arg->keyword_len;
    const VALUE * const ci_keywords = kw_arg->keywords;
    VALUE *argv = cfp->sp - calling->argc;
    VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
    const int lead_num = iseq->body->param.lead_num;
    VALUE * const ci_kws = ALLOCA_N(VALUE, ci_kw_len);
    MEMCPY(ci_kws, argv + lead_num, VALUE, ci_kw_len);
    args_setup_kw_parameters(ec, iseq, ci_kws, ci_kw_len, ci_keywords, klocals);

    int param = iseq->body->param.size;
    int local = iseq->body->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, cc->me, 0, param, local);
}

static VALUE
vm_call_iseq_setup_kwparm_nokwarg(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                  struct rb_calling_info *calling,
                                  const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VM_ASSERT((ci->flag & VM_CALL_KWARG) == 0);
    RB_DEBUG_COUNTER_INC(ccf_iseq_kw2);

    const rb_iseq_t *iseq = def_iseq_ptr(cc->me->def);
    const struct rb_iseq_param_keyword *kw_param = iseq->body->param.keyword;
    VALUE * const argv = cfp->sp - calling->argc;
    VALUE * const klocals = argv + kw_param->bits_start - kw_param->num;

    for (int i=0; i<kw_param->num; i++) {
        klocals[i] = kw_param->default_values[i];
    }
    /* NOTE: don't need to setup (clear) unspecified bits
             because no code check it.
             klocals[kw_param->num] = INT2FIX(0); */

    int param = iseq->body->param.size;
    int local = iseq->body->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, cc->me, 0, param, local);
}

static inline int
vm_callee_setup_arg(rb_execution_context_t *ec, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc,
		    const rb_iseq_t *iseq, VALUE *argv, int param_size, int local_size)
{
    if (LIKELY(!(ci->flag & VM_CALL_KW_SPLAT))) {
        if (LIKELY(rb_simple_iseq_p(iseq))) {
            rb_control_frame_t *cfp = ec->cfp;
            CALLER_SETUP_ARG(cfp, calling, ci); /* splat arg */

            if (calling->argc != iseq->body->param.lead_num) {
                argument_arity_error(ec, iseq, calling->argc, iseq->body->param.lead_num, iseq->body->param.lead_num);
            }

            CC_SET_FASTPATH(cc, vm_call_iseq_setup_func(ci, param_size, local_size), vm_call_iseq_optimizable_p(ci, cc));
            return 0;
        }
        else if (rb_iseq_only_optparam_p(iseq)) {
            rb_control_frame_t *cfp = ec->cfp;
            CALLER_SETUP_ARG(cfp, calling, ci); /* splat arg */

            const int lead_num = iseq->body->param.lead_num;
            const int opt_num = iseq->body->param.opt_num;
            const int argc = calling->argc;
            const int opt = argc - lead_num;

            if (opt < 0 || opt > opt_num) {
                argument_arity_error(ec, iseq, argc, lead_num, lead_num + opt_num);
            }

            CC_SET_FASTPATH(cc, vm_call_iseq_setup_normal_opt_start,
                            !IS_ARGS_SPLAT(ci) && !IS_ARGS_KEYWORD(ci) &&
                            !(METHOD_ENTRY_VISI(cc->me) == METHOD_VISI_PROTECTED));

            /* initialize opt vars for self-references */
            VM_ASSERT((int)iseq->body->param.size == lead_num + opt_num);
            for (int i=argc; i<lead_num + opt_num; i++) {
                argv[i] = Qnil;
            }
            return (int)iseq->body->param.opt_table[opt];
        }
        else if (rb_iseq_only_kwparam_p(iseq) && !IS_ARGS_SPLAT(ci)) {
            const int lead_num = iseq->body->param.lead_num;
            const int argc = calling->argc;
            const struct rb_iseq_param_keyword *kw_param = iseq->body->param.keyword;

            if (ci->flag & VM_CALL_KWARG) {
                const struct rb_call_info_kw_arg *kw_arg = ((struct rb_call_info_with_kwarg *)ci)->kw_arg;

                if (argc - kw_arg->keyword_len == lead_num) {
                    const int ci_kw_len = kw_arg->keyword_len;
                    const VALUE * const ci_keywords = kw_arg->keywords;
                    VALUE * const ci_kws = ALLOCA_N(VALUE, ci_kw_len);
                    MEMCPY(ci_kws, argv + lead_num, VALUE, ci_kw_len);

                    VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
                    args_setup_kw_parameters(ec, iseq, ci_kws, ci_kw_len, ci_keywords, klocals);

                    CC_SET_FASTPATH(cc, vm_call_iseq_setup_kwparm_kwarg,
                                    !(METHOD_ENTRY_VISI(cc->me) == METHOD_VISI_PROTECTED));

                    return 0;
                }
            }
            else if (argc == lead_num) {
                /* no kwarg */
                VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
                args_setup_kw_parameters(ec, iseq, NULL, 0, NULL, klocals);

                if (klocals[kw_param->num] == INT2FIX(0)) {
                    /* copy from default_values */
                    CC_SET_FASTPATH(cc, vm_call_iseq_setup_kwparm_nokwarg,
                                    !(METHOD_ENTRY_VISI(cc->me) == METHOD_VISI_PROTECTED));
                }

                return 0;
            }
        }
    }

    return setup_parameters_complex(ec, iseq, calling, ci, argv, arg_setup_method);
}

static VALUE
vm_call_iseq_setup(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_setup);

    const rb_iseq_t *iseq = def_iseq_ptr(cc->me->def);
    const int param_size = iseq->body->param.size;
    const int local_size = iseq->body->local_table_size;
    const int opt_pc = vm_callee_setup_arg(ec, calling, ci, cc, def_iseq_ptr(cc->me->def), cfp->sp - calling->argc, param_size, local_size);
    return vm_call_iseq_setup_2(ec, cfp, calling, ci, cc, opt_pc, param_size, local_size);
}

static inline VALUE
vm_call_iseq_setup_2(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc,
		     int opt_pc, int param_size, int local_size)
{
    if (LIKELY(!(ci->flag & VM_CALL_TAILCALL))) {
        return vm_call_iseq_setup_normal(ec, cfp, calling, cc->me, opt_pc, param_size, local_size);
    }
    else {
	return vm_call_iseq_setup_tailcall(ec, cfp, calling, ci, cc, opt_pc);
    }
}

static inline VALUE
vm_call_iseq_setup_normal(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const rb_callable_method_entry_t *me,
                          int opt_pc, int param_size, int local_size)
{
    const rb_iseq_t *iseq = def_iseq_ptr(me->def);
    VALUE *argv = cfp->sp - calling->argc;
    VALUE *sp = argv + param_size;
    cfp->sp = argv - 1 /* recv */;

    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL, calling->recv,
                  calling->block_handler, (VALUE)me,
                  iseq->body->iseq_encoded + opt_pc, sp,
                  local_size - param_size,
                  iseq->body->stack_max);
    return Qundef;
}

static inline VALUE
vm_call_iseq_setup_tailcall(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc,
			    int opt_pc)
{
    unsigned int i;
    VALUE *argv = cfp->sp - calling->argc;
    const rb_callable_method_entry_t *me = cc->me;
    const rb_iseq_t *iseq = def_iseq_ptr(me->def);
    VALUE *src_argv = argv;
    VALUE *sp_orig, *sp;
    VALUE finish_flag = VM_FRAME_FINISHED_P(cfp) ? VM_FRAME_FLAG_FINISH : 0;

    if (VM_BH_FROM_CFP_P(calling->block_handler, cfp)) {
	struct rb_captured_block *dst_captured = VM_CFP_TO_CAPTURED_BLOCK(RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));
	const struct rb_captured_block *src_captured = VM_BH_TO_CAPT_BLOCK(calling->block_handler);
	dst_captured->code.val = src_captured->code.val;
	if (VM_BH_ISEQ_BLOCK_P(calling->block_handler)) {
	    calling->block_handler = VM_BH_FROM_ISEQ_BLOCK(dst_captured);
	}
	else {
	    calling->block_handler = VM_BH_FROM_IFUNC_BLOCK(dst_captured);
	}
    }

    vm_pop_frame(ec, cfp, cfp->ep);
    cfp = ec->cfp;

    sp_orig = sp = cfp->sp;

    /* push self */
    sp[0] = calling->recv;
    sp++;

    /* copy arguments */
    for (i=0; i < iseq->body->param.size; i++) {
	*sp++ = src_argv[i];
    }

    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL | finish_flag,
		  calling->recv, calling->block_handler, (VALUE)me,
		  iseq->body->iseq_encoded + opt_pc, sp,
		  iseq->body->local_table_size - iseq->body->param.size,
		  iseq->body->stack_max);

    cfp->sp = sp_orig;
    RUBY_VM_CHECK_INTS(ec);

    return Qundef;
}

static VALUE
call_cfunc_m2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    return (*func)(recv, rb_ary_new4(argc, argv));
}

static VALUE
call_cfunc_m1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    return (*func)(argc, argv, recv);
}

static VALUE
call_cfunc_0(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE) = (VALUE(*)(VALUE))func;
    return (*f)(recv);
}
static VALUE
call_cfunc_1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE) = (VALUE(*)(VALUE, VALUE))func;
    return (*f)(recv, argv[0]);
}
static VALUE
call_cfunc_2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1]);
}
static VALUE
call_cfunc_3(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2]);
}
static VALUE
call_cfunc_4(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3]);
}
static VALUE
call_cfunc_5(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4]);
}
static VALUE
call_cfunc_6(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}
static VALUE
call_cfunc_7(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}
static VALUE
call_cfunc_8(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
}
static VALUE
call_cfunc_9(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}
static VALUE
call_cfunc_10(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]);
}
static VALUE
call_cfunc_11(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
}
static VALUE
call_cfunc_12(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
}
static VALUE
call_cfunc_13(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]);
}
static VALUE
call_cfunc_14(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13]);
}
static VALUE
call_cfunc_15(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14]);
}

static inline int
vm_cfp_consistent_p(rb_execution_context_t *ec, const rb_control_frame_t *reg_cfp)
{
    const int ov_flags = RAISED_STACKOVERFLOW;
    if (LIKELY(reg_cfp == ec->cfp + 1)) return TRUE;
    if (rb_ec_raised_p(ec, ov_flags)) {
	rb_ec_raised_reset(ec, ov_flags);
	return TRUE;
    }
    return FALSE;
}

#define CHECK_CFP_CONSISTENCY(func) \
    (LIKELY(vm_cfp_consistent_p(ec, reg_cfp)) ? (void)0 : \
     rb_bug(func ": cfp consistency error (%p, %p)", (void *)reg_cfp, (void *)(ec->cfp+1)))

static inline
const rb_method_cfunc_t *
vm_method_cfunc_entry(const rb_callable_method_entry_t *me)
{
#if VM_DEBUG_VERIFY_METHOD_CACHE
    switch (me->def->type) {
      case VM_METHOD_TYPE_CFUNC:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
	break;
# define METHOD_BUG(t) case VM_METHOD_TYPE_##t: rb_bug("wrong method type: " #t)
	METHOD_BUG(ISEQ);
	METHOD_BUG(ATTRSET);
	METHOD_BUG(IVAR);
	METHOD_BUG(BMETHOD);
	METHOD_BUG(ZSUPER);
	METHOD_BUG(UNDEF);
	METHOD_BUG(OPTIMIZED);
	METHOD_BUG(MISSING);
	METHOD_BUG(REFINED);
	METHOD_BUG(ALIAS);
# undef METHOD_BUG
      default:
	rb_bug("wrong method type: %d", me->def->type);
    }
#endif
    return UNALIGNED_MEMBER_PTR(me->def, body.cfunc);
}

static VALUE
vm_call_cfunc_with_frame(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VALUE val;
    const rb_callable_method_entry_t *me = cc->me;
    const rb_method_cfunc_t *cfunc = vm_method_cfunc_entry(me);
    int len = cfunc->argc;

    VALUE recv = calling->recv;
    VALUE block_handler = calling->block_handler;
    int argc = calling->argc;

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(ec, me->owner, me->def->original_id);
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_CALL, recv, me->def->original_id, ci->mid, me->owner, Qundef);

    vm_push_frame(ec, NULL, VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL, recv,
		  block_handler, (VALUE)me,
		  0, ec->cfp->sp, 0, 0);

    if (len >= 0) rb_check_arity(argc, len, len);

    reg_cfp->sp -= argc + 1;
    val = (*cfunc->invoker)(recv, argc, reg_cfp->sp + 1, cfunc->func);

    CHECK_CFP_CONSISTENCY("vm_call_cfunc");

    rb_vm_pop_frame(ec);

    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, recv, me->def->original_id, ci->mid, me->owner, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, me->owner, me->def->original_id);

    return val;
}

static VALUE
vm_call_cfunc(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_cfunc);

    CALLER_SETUP_ARG(reg_cfp, calling, ci);
    return vm_call_cfunc_with_frame(ec, reg_cfp, calling, ci, cc);
}

static VALUE
vm_call_ivar(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_ivar);
    cfp->sp -= 1;
    return vm_getivar(calling->recv, cc->me->def->body.attr.id, NULL, cc, TRUE);
}

static VALUE
vm_call_attrset(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_attrset);
    VALUE val = *(cfp->sp - 1);
    cfp->sp -= 2;
    return vm_setivar(calling->recv, cc->me->def->body.attr.id, val, NULL, cc, 1);
}

static inline VALUE
vm_call_bmethod_body(rb_execution_context_t *ec, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    rb_proc_t *proc;
    VALUE val;

    /* control block frame */
    GetProcPtr(cc->me->def->body.bmethod.proc, proc);
    val = rb_vm_invoke_bmethod(ec, proc, calling->recv, calling->argc, argv, calling->block_handler, cc->me);

    return val;
}

static VALUE
vm_call_bmethod(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_bmethod);

    VALUE *argv;
    int argc;

    CALLER_SETUP_ARG(cfp, calling, ci);
    argc = calling->argc;
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, cfp->sp - argc, VALUE, argc);
    cfp->sp += - argc - 1;

    return vm_call_bmethod_body(ec, calling, ci, cc, argv);
}

static enum method_missing_reason
ci_missing_reason(const struct rb_call_info *ci)
{
    enum method_missing_reason stat = MISSING_NOENTRY;
    if (ci->flag & VM_CALL_VCALL) stat |= MISSING_VCALL;
    if (ci->flag & VM_CALL_FCALL) stat |= MISSING_FCALL;
    if (ci->flag & VM_CALL_SUPER) stat |= MISSING_SUPER;
    return stat;
}

static VALUE
vm_call_opt_send(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *orig_ci, struct rb_call_cache *orig_cc)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_send);

    int i;
    VALUE sym;
    struct rb_call_info *ci;
    struct rb_call_info_with_kwarg ci_entry;
    struct rb_call_cache cc_entry, *cc;

    CALLER_SETUP_ARG(reg_cfp, calling, orig_ci);

    i = calling->argc - 1;

    if (calling->argc == 0) {
	rb_raise(rb_eArgError, "no method name given");
    }

    /* setup new ci */
    if (orig_ci->flag & VM_CALL_KWARG) {
	ci = (struct rb_call_info *)&ci_entry;
	ci_entry = *(struct rb_call_info_with_kwarg *)orig_ci;
    }
    else {
	ci = &ci_entry.ci;
	ci_entry.ci = *orig_ci;
    }
    ci->flag = ci->flag & ~VM_CALL_KWARG; /* TODO: delegate kw_arg without making a Hash object */

    /* setup new cc */
    cc_entry = *orig_cc;
    cc = &cc_entry;

    sym = TOPN(i);

    if (!(ci->mid = rb_check_id(&sym))) {
	if (rb_method_basic_definition_p(CLASS_OF(calling->recv), idMethodMissing)) {
	    VALUE exc =
		rb_make_no_method_exception(rb_eNoMethodError, 0, calling->recv,
					    rb_long2int(calling->argc), &TOPN(i),
					    ci->flag & (VM_CALL_FCALL|VM_CALL_VCALL));
	    rb_exc_raise(exc);
	}
	TOPN(i) = rb_str_intern(sym);
	ci->mid = idMethodMissing;
	ec->method_missing_reason = cc->aux.method_missing_reason = ci_missing_reason(ci);
    }
    else {
	/* shift arguments */
	if (i > 0) {
	    MEMMOVE(&TOPN(i), &TOPN(i-1), VALUE, i);
	}
	calling->argc -= 1;
	DEC_SP(1);
    }

    cc->me = rb_callable_method_entry_with_refinements(CLASS_OF(calling->recv), ci->mid, NULL);
    ci->flag = VM_CALL_FCALL | VM_CALL_OPT_SEND;
    return vm_call_method(ec, reg_cfp, calling, ci, cc);
}

static inline VALUE vm_invoke_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, VALUE block_handler);

NOINLINE(static VALUE
	 vm_invoke_block_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
				  struct rb_calling_info *calling, const struct rb_call_info *ci, VALUE block_handler));

static VALUE
vm_invoke_block_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
			 struct rb_calling_info *calling, const struct rb_call_info *ci, VALUE block_handler)
{
    int argc = calling->argc;

    /* remove self */
    if (argc > 0) MEMMOVE(&TOPN(argc), &TOPN(argc-1), VALUE, argc);
    DEC_SP(1);

    return vm_invoke_block(ec, reg_cfp, calling, ci, block_handler);
}

static VALUE
vm_call_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_call);

    VALUE procval = calling->recv;
    return vm_invoke_block_opt_call(ec, reg_cfp, calling, ci, VM_BH_FROM_PROC(procval));
}

static VALUE
vm_call_opt_block_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_block_call);
    VALUE block_handler = VM_ENV_BLOCK_HANDLER(VM_CF_LEP(reg_cfp));

    if (BASIC_OP_UNREDEFINED_P(BOP_CALL, PROC_REDEFINED_OP_FLAG)) {
	return vm_invoke_block_opt_call(ec, reg_cfp, calling, ci, block_handler);
    }
    else {
	calling->recv = rb_vm_bh_to_procval(ec, block_handler);
	vm_search_method(ci, cc, calling->recv);
	return vm_call_general(ec, reg_cfp, calling, ci, cc);
    }
}

static VALUE
vm_call_method_missing(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *orig_ci, struct rb_call_cache *orig_cc)
{
    RB_DEBUG_COUNTER_INC(ccf_method_missing);

    VALUE *argv = STACK_ADDR_FROM_TOP(calling->argc);
    struct rb_call_info ci_entry;
    const struct rb_call_info *ci;
    struct rb_call_cache cc_entry, *cc;
    unsigned int argc;

    CALLER_SETUP_ARG(reg_cfp, calling, orig_ci);
    argc = calling->argc+1;

    ci_entry.flag = VM_CALL_FCALL | VM_CALL_OPT_SEND;
    ci_entry.mid = idMethodMissing;
    ci_entry.orig_argc = argc;
    ci = &ci_entry;

    cc_entry = *orig_cc;
    cc_entry.me =
	rb_callable_method_entry_without_refinements(CLASS_OF(calling->recv),
						     idMethodMissing, NULL);
    cc = &cc_entry;

    calling->argc = argc;

    /* shift arguments: m(a, b, c) #=> method_missing(:m, a, b, c) */
    CHECK_VM_STACK_OVERFLOW(reg_cfp, 1);
    vm_check_canary(ec, reg_cfp->sp);
    if (argc > 1) {
	MEMMOVE(argv+1, argv, VALUE, argc-1);
    }
    argv[0] = ID2SYM(orig_ci->mid);
    INC_SP(1);

    ec->method_missing_reason = orig_cc->aux.method_missing_reason;
    return vm_call_method(ec, reg_cfp, calling, ci, cc);
}

static const rb_callable_method_entry_t *refined_method_callable_without_refinement(const rb_callable_method_entry_t *me);
static VALUE
vm_call_zsuper(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, VALUE klass)
{
    RB_DEBUG_COUNTER_INC(ccf_method_missing);

    klass = RCLASS_SUPER(klass);
    cc->me = klass ? rb_callable_method_entry(klass, ci->mid) : NULL;

    if (!cc->me) {
	return vm_call_method_nome(ec, cfp, calling, ci, cc);
    }
    if (cc->me->def->type == VM_METHOD_TYPE_REFINED &&
	cc->me->def->body.refined.orig_me) {
	cc->me = refined_method_callable_without_refinement(cc->me);
    }
    return vm_call_method_each_type(ec, cfp, calling, ci, cc);
}

static inline VALUE
find_refinement(VALUE refinements, VALUE klass)
{
    if (NIL_P(refinements)) {
	return Qnil;
    }
    return rb_hash_lookup(refinements, klass);
}

PUREFUNC(static rb_control_frame_t * current_method_entry(const rb_execution_context_t *ec, rb_control_frame_t *cfp));
static rb_control_frame_t *
current_method_entry(const rb_execution_context_t *ec, rb_control_frame_t *cfp)
{
    rb_control_frame_t *top_cfp = cfp;

    if (cfp->iseq && cfp->iseq->body->type == ISEQ_TYPE_BLOCK) {
	const rb_iseq_t *local_iseq = cfp->iseq->body->local_iseq;

	do {
	    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	    if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)) {
		/* TODO: orphan block */
		return top_cfp;
	    }
	} while (cfp->iseq != local_iseq);
    }
    return cfp;
}

static VALUE
find_defined_class_by_owner(VALUE current_class, VALUE target_owner)
{
    VALUE klass = current_class;

    /* for prepended Module, then start from cover class */
    if (RB_TYPE_P(klass, T_ICLASS) && FL_TEST(klass, RICLASS_IS_ORIGIN)) klass = RBASIC_CLASS(klass);

    while (RTEST(klass)) {
	VALUE owner = RB_TYPE_P(klass, T_ICLASS) ? RBASIC_CLASS(klass) : klass;
	if (owner == target_owner) {
	    return klass;
	}
	klass = RCLASS_SUPER(klass);
    }

    return current_class; /* maybe module function */
}

static const rb_callable_method_entry_t *
aliased_callable_method_entry(const rb_callable_method_entry_t *me)
{
    const rb_method_entry_t *orig_me = me->def->body.alias.original_me;
    const rb_callable_method_entry_t *cme;

    if (orig_me->defined_class == 0) {
	VALUE defined_class = find_defined_class_by_owner(me->defined_class, orig_me->owner);
	VM_ASSERT(RB_TYPE_P(orig_me->owner, T_MODULE));
	cme = rb_method_entry_complement_defined_class(orig_me, me->called_id, defined_class);

	if (me->def->alias_count + me->def->complemented_count == 0) {
	    RB_OBJ_WRITE(me, &me->def->body.alias.original_me, cme);
	}
	else {
	    rb_method_definition_t *def =
		rb_method_definition_create(VM_METHOD_TYPE_ALIAS, me->def->original_id);
	    rb_method_definition_set((rb_method_entry_t *)me, def, (void *)cme);
	}
    }
    else {
	cme = (const rb_callable_method_entry_t *)orig_me;
    }

    VM_ASSERT(callable_method_entry_p(cme));
    return cme;
}

static const rb_callable_method_entry_t *
refined_method_callable_without_refinement(const rb_callable_method_entry_t *me)
{
    const rb_method_entry_t *orig_me = me->def->body.refined.orig_me;
    const rb_callable_method_entry_t *cme;

    if (orig_me->defined_class == 0) {
	cme = NULL;
	rb_notimplement();
    }
    else {
	cme = (const rb_callable_method_entry_t *)orig_me;
    }

    VM_ASSERT(callable_method_entry_p(cme));

    if (UNDEFINED_METHOD_ENTRY_P(cme)) {
	cme = NULL;
    }

    return cme;
}

static VALUE
vm_call_method_each_type(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    switch (cc->me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
        CC_SET_FASTPATH(cc, vm_call_iseq_setup, TRUE);
	return vm_call_iseq_setup(ec, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_CFUNC:
        CC_SET_FASTPATH(cc, vm_call_cfunc, TRUE);
	return vm_call_cfunc(ec, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_ATTRSET:
	CALLER_SETUP_ARG(cfp, calling, ci);
	rb_check_arity(calling->argc, 1, 1);
	cc->aux.index = 0;
        CC_SET_FASTPATH(cc, vm_call_attrset, !((ci->flag & VM_CALL_ARGS_SPLAT) || (ci->flag & VM_CALL_KWARG)));
	return vm_call_attrset(ec, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_IVAR:
	CALLER_SETUP_ARG(cfp, calling, ci);
	rb_check_arity(calling->argc, 0, 0);
	cc->aux.index = 0;
        CC_SET_FASTPATH(cc, vm_call_ivar, !(ci->flag & VM_CALL_ARGS_SPLAT));
	return vm_call_ivar(ec, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_MISSING:
	cc->aux.method_missing_reason = 0;
        CC_SET_FASTPATH(cc, vm_call_method_missing, TRUE);
	return vm_call_method_missing(ec, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_BMETHOD:
        CC_SET_FASTPATH(cc, vm_call_bmethod, TRUE);
	return vm_call_bmethod(ec, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_ALIAS:
	cc->me = aliased_callable_method_entry(cc->me);
	VM_ASSERT(cc->me != NULL);
	return vm_call_method_each_type(ec, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_OPTIMIZED:
	switch (cc->me->def->body.optimize_type) {
	  case OPTIMIZED_METHOD_TYPE_SEND:
            CC_SET_FASTPATH(cc, vm_call_opt_send, TRUE);
	    return vm_call_opt_send(ec, cfp, calling, ci, cc);
	  case OPTIMIZED_METHOD_TYPE_CALL:
            CC_SET_FASTPATH(cc, vm_call_opt_call, TRUE);
	    return vm_call_opt_call(ec, cfp, calling, ci, cc);
	  case OPTIMIZED_METHOD_TYPE_BLOCK_CALL:
            CC_SET_FASTPATH(cc, vm_call_opt_block_call, TRUE);
	    return vm_call_opt_block_call(ec, cfp, calling, ci, cc);
	  default:
	    rb_bug("vm_call_method: unsupported optimized method type (%d)",
		   cc->me->def->body.optimize_type);
	}

      case VM_METHOD_TYPE_UNDEF:
	break;

      case VM_METHOD_TYPE_ZSUPER:
        return vm_call_zsuper(ec, cfp, calling, ci, cc, RCLASS_ORIGIN(cc->me->defined_class));

      case VM_METHOD_TYPE_REFINED: {
        const rb_cref_t *cref = vm_get_cref(cfp->ep);

        for (; cref; cref = CREF_NEXT(cref)) {
            const rb_callable_method_entry_t *ref_me;
            VALUE refinements = CREF_REFINEMENTS(cref);
            VALUE refinement = find_refinement(refinements, cc->me->owner);
            if (NIL_P(refinement)) continue;

            ref_me = rb_callable_method_entry(refinement, ci->mid);

            if (ref_me) {
                if (cc->call == vm_call_super_method) {
                    const rb_control_frame_t *top_cfp = current_method_entry(ec, cfp);
                    const rb_callable_method_entry_t *top_me = rb_vm_frame_method_entry(top_cfp);
                    if (top_me && rb_method_definition_eq(ref_me->def, top_me->def)) {
                        continue;
                    }
                }
                if (cc->me->def->type != VM_METHOD_TYPE_REFINED ||
                    cc->me->def != ref_me->def) {
                    cc->me = ref_me;
                }
                if (ref_me->def->type != VM_METHOD_TYPE_REFINED) {
                    return vm_call_method(ec, cfp, calling, ci, cc);
                }
            }
            else {
                cc->me = NULL;
                return vm_call_method_nome(ec, cfp, calling, ci, cc);
            }
        }

	if (cc->me->def->body.refined.orig_me) {
	    cc->me = refined_method_callable_without_refinement(cc->me);
	}
	else {
	    VALUE klass = RCLASS_SUPER(cc->me->defined_class);
	    cc->me = klass ? rb_callable_method_entry(klass, ci->mid) : NULL;
	}
	return vm_call_method(ec, cfp, calling, ci, cc);
      }
    }

    rb_bug("vm_call_method: unsupported method type (%d)", cc->me->def->type);
}

NORETURN(static void vm_raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE obj, int call_status));

static VALUE
vm_call_method_nome(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    /* method missing */
    const int stat = ci_missing_reason(ci);

    if (ci->mid == idMethodMissing) {
	rb_control_frame_t *reg_cfp = cfp;
	VALUE *argv = STACK_ADDR_FROM_TOP(calling->argc);
	vm_raise_method_missing(ec, calling->argc, argv, calling->recv, stat);
    }
    else {
	cc->aux.method_missing_reason = stat;
        CC_SET_FASTPATH(cc, vm_call_method_missing, TRUE);
	return vm_call_method_missing(ec, cfp, calling, ci, cc);
    }
}

static inline VALUE
vm_call_method(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VM_ASSERT(callable_method_entry_p(cc->me));

    if (cc->me != NULL) {
	switch (METHOD_ENTRY_VISI(cc->me)) {
	  case METHOD_VISI_PUBLIC: /* likely */
	    return vm_call_method_each_type(ec, cfp, calling, ci, cc);

	  case METHOD_VISI_PRIVATE:
	    if (!(ci->flag & VM_CALL_FCALL)) {
		enum method_missing_reason stat = MISSING_PRIVATE;
		if (ci->flag & VM_CALL_VCALL) stat |= MISSING_VCALL;

		cc->aux.method_missing_reason = stat;
                CC_SET_FASTPATH(cc, vm_call_method_missing, TRUE);
		return vm_call_method_missing(ec, cfp, calling, ci, cc);
	    }
	    return vm_call_method_each_type(ec, cfp, calling, ci, cc);

	  case METHOD_VISI_PROTECTED:
	    if (!(ci->flag & VM_CALL_OPT_SEND)) {
		if (!rb_obj_is_kind_of(cfp->self, cc->me->defined_class)) {
		    cc->aux.method_missing_reason = MISSING_PROTECTED;
		    return vm_call_method_missing(ec, cfp, calling, ci, cc);
		}
		else {
		    /* caching method info to dummy cc */
		    struct rb_call_cache cc_entry;
		    cc_entry = *cc;
		    cc = &cc_entry;

		    VM_ASSERT(cc->me != NULL);
		    return vm_call_method_each_type(ec, cfp, calling, ci, cc);
		}
	    }
	    return vm_call_method_each_type(ec, cfp, calling, ci, cc);

	  default:
	    rb_bug("unreachable");
	}
    }
    else {
	return vm_call_method_nome(ec, cfp, calling, ci, cc);
    }
}

static VALUE
vm_call_general(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_general);
    return vm_call_method(ec, reg_cfp, calling, ci, cc);
}

static VALUE
vm_call_super_method(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    RB_DEBUG_COUNTER_INC(ccf_super_method);

    /* this check is required to distinguish with other functions. */
    if (cc->call != vm_call_super_method) rb_bug("bug");
    return vm_call_method(ec, reg_cfp, calling, ci, cc);
}

/* super */

static inline VALUE
vm_search_normal_superclass(VALUE klass)
{
    if (BUILTIN_TYPE(klass) == T_ICLASS &&
	FL_TEST(RBASIC(klass)->klass, RMODULE_IS_REFINEMENT)) {
	klass = RBASIC(klass)->klass;
    }
    klass = RCLASS_ORIGIN(klass);
    return RCLASS_SUPER(klass);
}

NORETURN(static void vm_super_outside(void));

static void
vm_super_outside(void)
{
    rb_raise(rb_eNoMethodError, "super called outside of method");
}

static void
vm_search_super_method(const rb_control_frame_t *reg_cfp, struct rb_call_info *ci, struct rb_call_cache *cc, VALUE recv)
{
    VALUE current_defined_class, klass;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(reg_cfp);

    if (!me) {
	vm_super_outside();
    }

    current_defined_class = me->defined_class;

    if (!NIL_P(RCLASS_REFINED_CLASS(current_defined_class))) {
	current_defined_class = RCLASS_REFINED_CLASS(current_defined_class);
    }

    if (BUILTIN_TYPE(current_defined_class) != T_MODULE &&
	BUILTIN_TYPE(current_defined_class) != T_ICLASS && /* bound UnboundMethod */
	!FL_TEST(current_defined_class, RMODULE_INCLUDED_INTO_REFINEMENT) &&
        !rb_obj_is_kind_of(recv, current_defined_class)) {
	VALUE m = RB_TYPE_P(current_defined_class, T_ICLASS) ?
	    RBASIC(current_defined_class)->klass : current_defined_class;

	rb_raise(rb_eTypeError,
		 "self has wrong type to call super in this context: "
		 "%"PRIsVALUE" (expected %"PRIsVALUE")",
                 rb_obj_class(recv), m);
    }

    if (me->def->type == VM_METHOD_TYPE_BMETHOD && (ci->flag & VM_CALL_ZSUPER)) {
	rb_raise(rb_eRuntimeError,
		 "implicit argument passing of super from method defined"
		 " by define_method() is not supported."
		 " Specify all arguments explicitly.");
    }

    ci->mid = me->def->original_id;
    klass = vm_search_normal_superclass(me->defined_class);

    if (!klass) {
	/* bound instance method of module */
	cc->aux.method_missing_reason = MISSING_SUPER;
        CC_SET_FASTPATH(cc, vm_call_method_missing, TRUE);
    }
    else {
        /* TODO: use inline cache */
	cc->me = rb_callable_method_entry(klass, ci->mid);
        CC_SET_FASTPATH(cc, vm_call_super_method, TRUE);
    }
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

static VALUE
vm_yield_with_cfunc(rb_execution_context_t *ec,
		    const struct rb_captured_block *captured,
                    VALUE self, int argc, const VALUE *argv, VALUE block_handler,
                    const rb_callable_method_entry_t *me)
{
    int is_lambda = FALSE; /* TODO */
    VALUE val, arg, blockarg;
    const struct vm_ifunc *ifunc = captured->code.ifunc;

    if (is_lambda) {
	arg = rb_ary_new4(argc, argv);
    }
    else if (argc == 0) {
	arg = Qnil;
    }
    else {
	arg = argv[0];
    }

    blockarg = rb_vm_bh_to_procval(ec, block_handler);

    vm_push_frame(ec, (const rb_iseq_t *)captured->code.ifunc,
                  VM_FRAME_MAGIC_IFUNC | VM_FRAME_FLAG_CFRAME |
                  (me ? VM_FRAME_FLAG_BMETHOD : 0),
		  self,
		  VM_GUARDED_PREV_EP(captured->ep),
                  (VALUE)me,
		  0, ec->cfp->sp, 0, 0);
    val = (*ifunc->func)(arg, ifunc->data, argc, argv, blockarg);
    rb_vm_pop_frame(ec);

    return val;
}

static VALUE
vm_yield_with_symbol(rb_execution_context_t *ec,  VALUE symbol, int argc, const VALUE *argv, VALUE block_handler)
{
    return rb_sym_proc_call(SYM2ID(symbol), argc, argv, rb_vm_bh_to_procval(ec, block_handler));
}

static inline int
vm_callee_setup_block_arg_arg0_splat(rb_control_frame_t *cfp, const rb_iseq_t *iseq, VALUE *argv, VALUE ary)
{
    int i;
    long len = RARRAY_LEN(ary);

    CHECK_VM_STACK_OVERFLOW(cfp, iseq->body->param.lead_num);

    for (i=0; i<len && i<iseq->body->param.lead_num; i++) {
	argv[i] = RARRAY_AREF(ary, i);
    }

    return i;
}

static inline VALUE
vm_callee_setup_block_arg_arg0_check(VALUE *argv)
{
    VALUE ary, arg0 = argv[0];
    ary = rb_check_array_type(arg0);
#if 0
    argv[0] = arg0;
#else
    VM_ASSERT(argv[0] == arg0);
#endif
    return ary;
}

static int
vm_callee_setup_block_arg(rb_execution_context_t *ec, struct rb_calling_info *calling, const struct rb_call_info *ci, const rb_iseq_t *iseq, VALUE *argv, const enum arg_setup_type arg_setup_type)
{
    if (rb_simple_iseq_p(iseq)) {
	rb_control_frame_t *cfp = ec->cfp;
	VALUE arg0;

	CALLER_SETUP_ARG(cfp, calling, ci); /* splat arg */

	if (arg_setup_type == arg_setup_block &&
	    calling->argc == 1 &&
	    iseq->body->param.flags.has_lead &&
	    !iseq->body->param.flags.ambiguous_param0 &&
	    !NIL_P(arg0 = vm_callee_setup_block_arg_arg0_check(argv))) {
	    calling->argc = vm_callee_setup_block_arg_arg0_splat(cfp, iseq, argv, arg0);
	}

	if (calling->argc != iseq->body->param.lead_num) {
	    if (arg_setup_type == arg_setup_block) {
		if (calling->argc < iseq->body->param.lead_num) {
		    int i;
		    CHECK_VM_STACK_OVERFLOW(cfp, iseq->body->param.lead_num);
		    for (i=calling->argc; i<iseq->body->param.lead_num; i++) argv[i] = Qnil;
		    calling->argc = iseq->body->param.lead_num; /* fill rest parameters */
		}
		else if (calling->argc > iseq->body->param.lead_num) {
		    calling->argc = iseq->body->param.lead_num; /* simply truncate arguments */
		}
	    }
	    else {
		argument_arity_error(ec, iseq, calling->argc, iseq->body->param.lead_num, iseq->body->param.lead_num);
	    }
	}

	return 0;
    }
    else {
	return setup_parameters_complex(ec, iseq, calling, ci, argv, arg_setup_type);
    }
}

static int
vm_yield_setup_args(rb_execution_context_t *ec, const rb_iseq_t *iseq, const int argc, VALUE *argv, VALUE block_handler, enum arg_setup_type arg_setup_type)
{
    struct rb_calling_info calling_entry, *calling;
    struct rb_call_info ci_entry, *ci;

    calling = &calling_entry;
    calling->argc = argc;
    calling->block_handler = block_handler;

    ci_entry.flag = 0;
    ci = &ci_entry;

    return vm_callee_setup_block_arg(ec, calling, ci, iseq, argv, arg_setup_type);
}

/* ruby iseq -> ruby block */

static VALUE
vm_invoke_iseq_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
		     struct rb_calling_info *calling, const struct rb_call_info *ci,
		     int is_lambda, const struct rb_captured_block *captured)
{
    const rb_iseq_t *iseq = rb_iseq_check(captured->code.iseq);
    const int arg_size = iseq->body->param.size;
    VALUE * const rsp = GET_SP() - calling->argc;
    int opt_pc = vm_callee_setup_block_arg(ec, calling, ci, iseq, rsp, is_lambda ? arg_setup_method : arg_setup_block);

    SET_SP(rsp);

    vm_push_frame(ec, iseq,
		  VM_FRAME_MAGIC_BLOCK | (is_lambda ? VM_FRAME_FLAG_LAMBDA : 0),
		  captured->self,
		  VM_GUARDED_PREV_EP(captured->ep), 0,
		  iseq->body->iseq_encoded + opt_pc,
		  rsp + arg_size,
		  iseq->body->local_table_size - arg_size, iseq->body->stack_max);

    return Qundef;
}

static VALUE
vm_invoke_symbol_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
		       struct rb_calling_info *calling, const struct rb_call_info *ci,
		       VALUE symbol)
{
    VALUE val;
    int argc;
    CALLER_SETUP_ARG(ec->cfp, calling, ci);
    argc = calling->argc;
    val = vm_yield_with_symbol(ec, symbol, argc, STACK_ADDR_FROM_TOP(argc), calling->block_handler);
    POPN(argc);
    return val;
}

static VALUE
vm_invoke_ifunc_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
		      struct rb_calling_info *calling, const struct rb_call_info *ci,
		      const struct rb_captured_block *captured)
{
    VALUE val;
    int argc;
    CALLER_SETUP_ARG(ec->cfp, calling, ci);
    argc = calling->argc;
    val = vm_yield_with_cfunc(ec, captured, captured->self, argc, STACK_ADDR_FROM_TOP(argc), calling->block_handler, NULL);
    POPN(argc); /* TODO: should put before C/yield? */
    return val;
}

static VALUE
vm_proc_to_block_handler(VALUE procval)
{
    const struct rb_block *block = vm_proc_block(procval);

    switch (vm_block_type(block)) {
      case block_type_iseq:
	return VM_BH_FROM_ISEQ_BLOCK(&block->as.captured);
      case block_type_ifunc:
	return VM_BH_FROM_IFUNC_BLOCK(&block->as.captured);
      case block_type_symbol:
	return VM_BH_FROM_SYMBOL(block->as.symbol);
      case block_type_proc:
	return VM_BH_FROM_PROC(block->as.proc);
    }
    VM_UNREACHABLE(vm_yield_with_proc);
    return Qundef;
}

static inline VALUE
vm_invoke_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
		struct rb_calling_info *calling, const struct rb_call_info *ci, VALUE block_handler)
{
    int is_lambda = FALSE;

  again:
    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_iseq:
	{
	    const struct rb_captured_block *captured = VM_BH_TO_ISEQ_BLOCK(block_handler);
	    return vm_invoke_iseq_block(ec, reg_cfp, calling, ci, is_lambda, captured);
	}
      case block_handler_type_ifunc:
	{
	    const struct rb_captured_block *captured = VM_BH_TO_IFUNC_BLOCK(block_handler);
	    return vm_invoke_ifunc_block(ec, reg_cfp, calling, ci, captured);
	}
      case block_handler_type_proc:
	is_lambda = block_proc_is_lambda(VM_BH_TO_PROC(block_handler));
	block_handler = vm_proc_to_block_handler(VM_BH_TO_PROC(block_handler));
	goto again;
      case block_handler_type_symbol:
	return vm_invoke_symbol_block(ec, reg_cfp, calling, ci, VM_BH_TO_SYMBOL(block_handler));
    }
    VM_UNREACHABLE(vm_invoke_block: unreachable);
    return Qnil;
}

static VALUE
vm_make_proc_with_iseq(const rb_iseq_t *blockiseq)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    struct rb_captured_block *captured;

    if (cfp == 0) {
	rb_bug("vm_make_proc_with_iseq: unreachable");
    }

    captured = VM_CFP_TO_CAPTURED_BLOCK(cfp);
    captured->code.iseq = blockiseq;

    return rb_vm_make_proc(ec, captured, rb_cProc);
}

static VALUE
vm_once_exec(VALUE iseq)
{
    VALUE proc = vm_make_proc_with_iseq((rb_iseq_t *)iseq);
    return rb_proc_call_with_block(proc, 0, 0, Qnil);
}

static VALUE
vm_once_clear(VALUE data)
{
    union iseq_inline_storage_entry *is = (union iseq_inline_storage_entry *)data;
    is->once.running_thread = NULL;
    return Qnil;
}

rb_control_frame_t *
FUNC_FASTCALL(rb_vm_opt_struct_aref)(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)
{
    TOPN(0) = rb_struct_aref(GET_SELF(), TOPN(0));
    return reg_cfp;
}

rb_control_frame_t *
FUNC_FASTCALL(rb_vm_opt_struct_aset)(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)
{
    rb_struct_aset(GET_SELF(), TOPN(0), TOPN(1));
    return reg_cfp;
}

/* defined insn */

static enum defined_type
check_respond_to_missing(VALUE obj, VALUE v)
{
    VALUE args[2];
    VALUE r;

    args[0] = obj; args[1] = Qfalse;
    r = rb_check_funcall(v, idRespond_to_missing, 2, args);
    if (r != Qundef && RTEST(r)) {
	return DEFINED_METHOD;
    }
    else {
	return DEFINED_NOT_DEFINED;
    }
}

static VALUE
vm_defined(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t op_type, VALUE obj, VALUE needstr, VALUE v)
{
    VALUE klass;
    enum defined_type expr_type = DEFINED_NOT_DEFINED;
    enum defined_type type = (enum defined_type)op_type;

    switch (type) {
      case DEFINED_IVAR:
	if (rb_ivar_defined(GET_SELF(), SYM2ID(obj))) {
	    expr_type = DEFINED_IVAR;
	}
	break;
      case DEFINED_IVAR2:
	klass = vm_get_cbase(GET_EP());
	break;
      case DEFINED_GVAR:
	if (rb_gvar_defined(rb_global_entry(SYM2ID(obj)))) {
	    expr_type = DEFINED_GVAR;
	}
	break;
      case DEFINED_CVAR: {
        const rb_cref_t *cref = vm_get_cref(GET_EP());
	klass = vm_get_cvar_base(cref, GET_CFP());
	if (rb_cvar_defined(klass, SYM2ID(obj))) {
	    expr_type = DEFINED_CVAR;
	}
	break;
      }
      case DEFINED_CONST:
	klass = v;
        if (vm_get_ev_const(ec, klass, SYM2ID(obj), 1, 1)) {
	    expr_type = DEFINED_CONST;
	}
	break;
      case DEFINED_FUNC:
	klass = CLASS_OF(v);
	if (rb_method_boundp(klass, SYM2ID(obj), 0)) {
	    expr_type = DEFINED_METHOD;
	}
	else {
	    expr_type = check_respond_to_missing(obj, v);
	}
	break;
      case DEFINED_METHOD:{
	VALUE klass = CLASS_OF(v);
	const rb_method_entry_t *me = rb_method_entry(klass, SYM2ID(obj));

	if (me) {
	    switch (METHOD_ENTRY_VISI(me)) {
	      case METHOD_VISI_PRIVATE:
		break;
	      case METHOD_VISI_PROTECTED:
		if (!rb_obj_is_kind_of(GET_SELF(), rb_class_real(klass))) {
		    break;
		}
	      case METHOD_VISI_PUBLIC:
		expr_type = DEFINED_METHOD;
		break;
	      default:
		rb_bug("vm_defined: unreachable: %u", (unsigned int)METHOD_ENTRY_VISI(me));
	    }
	}
	else {
	    expr_type = check_respond_to_missing(obj, v);
	}
	break;
      }
      case DEFINED_YIELD:
	if (GET_BLOCK_HANDLER() != VM_BLOCK_HANDLER_NONE) {
	    expr_type = DEFINED_YIELD;
	}
	break;
      case DEFINED_ZSUPER:
	{
	    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(GET_CFP());

	    if (me) {
		VALUE klass = vm_search_normal_superclass(me->defined_class);
		ID id = me->def->original_id;

		if (rb_method_boundp(klass, id, 0)) {
		    expr_type = DEFINED_ZSUPER;
		}
	    }
	}
	break;
      case DEFINED_REF:{
	if (vm_getspecial(ec, GET_LEP(), Qfalse, FIX2INT(obj)) != Qnil) {
	    expr_type = DEFINED_GVAR;
	}
	break;
      }
      default:
	rb_bug("unimplemented defined? type (VM)");
	break;
    }

    if (expr_type != 0) {
	if (needstr != Qfalse) {
	    return rb_iseq_defined_string(expr_type);
	}
	else {
	    return Qtrue;
	}
    }
    else {
	return Qnil;
    }
}

static const VALUE *
vm_get_ep(const VALUE *const reg_ep, rb_num_t lv)
{
    rb_num_t i;
    const VALUE *ep = reg_ep;
    for (i = 0; i < lv; i++) {
	ep = GET_PREV_EP(ep);
    }
    return ep;
}

static VALUE
vm_get_special_object(const VALUE *const reg_ep,
		      enum vm_special_object_type type)
{
    switch (type) {
      case VM_SPECIAL_OBJECT_VMCORE:
	return rb_mRubyVMFrozenCore;
      case VM_SPECIAL_OBJECT_CBASE:
	return vm_get_cbase(reg_ep);
      case VM_SPECIAL_OBJECT_CONST_BASE:
	return vm_get_const_base(reg_ep);
      default:
	rb_bug("putspecialobject insn: unknown value_type %d", type);
    }
}

static void
vm_freezestring(VALUE str, VALUE debug)
{
    if (!NIL_P(debug)) {
	rb_ivar_set(str, id_debug_created_info, debug);
    }
    rb_str_freeze(str);
}

static VALUE
vm_concat_array(VALUE ary1, VALUE ary2st)
{
    const VALUE ary2 = ary2st;
    VALUE tmp1 = rb_check_to_array(ary1);
    VALUE tmp2 = rb_check_to_array(ary2);

    if (NIL_P(tmp1)) {
	tmp1 = rb_ary_new3(1, ary1);
    }

    if (NIL_P(tmp2)) {
	tmp2 = rb_ary_new3(1, ary2);
    }

    if (tmp1 == ary1) {
	tmp1 = rb_ary_dup(ary1);
    }
    return rb_ary_concat(tmp1, tmp2);
}

static VALUE
vm_splat_array(VALUE flag, VALUE ary)
{
    VALUE tmp = rb_check_to_array(ary);
    if (NIL_P(tmp)) {
	return rb_ary_new3(1, ary);
    }
    else if (RTEST(flag)) {
	return rb_ary_dup(tmp);
    }
    else {
	return tmp;
    }
}

static VALUE
vm_check_match(rb_execution_context_t *ec, VALUE target, VALUE pattern, rb_num_t flag)
{
    enum vm_check_match_type type = ((int)flag) & VM_CHECKMATCH_TYPE_MASK;

    if (flag & VM_CHECKMATCH_ARRAY) {
	long i;
	const long n = RARRAY_LEN(pattern);

	for (i = 0; i < n; i++) {
	    VALUE v = RARRAY_AREF(pattern, i);
	    VALUE c = check_match(ec, v, target, type);

	    if (RTEST(c)) {
		return c;
	    }
	}
	return Qfalse;
    }
    else {
	return check_match(ec, pattern, target, type);
    }
}

static VALUE
vm_check_keyword(lindex_t bits, lindex_t idx, const VALUE *ep)
{
    const VALUE kw_bits = *(ep - bits);

    if (FIXNUM_P(kw_bits)) {
	unsigned int b = (unsigned int)FIX2ULONG(kw_bits);
	if ((idx < KW_SPECIFIED_BITS_MAX) && (b & (0x01 << idx)))
	    return Qfalse;
    }
    else {
	VM_ASSERT(RB_TYPE_P(kw_bits, T_HASH));
	if (rb_hash_has_key(kw_bits, INT2FIX(idx))) return Qfalse;
    }
    return Qtrue;
}

static void
vm_dtrace(rb_event_flag_t flag, rb_execution_context_t *ec)
{
    if (RUBY_DTRACE_METHOD_ENTRY_ENABLED() ||
	RUBY_DTRACE_METHOD_RETURN_ENABLED() ||
	RUBY_DTRACE_CMETHOD_ENTRY_ENABLED() ||
	RUBY_DTRACE_CMETHOD_RETURN_ENABLED()) {

	switch (flag) {
	  case RUBY_EVENT_CALL:
	    RUBY_DTRACE_METHOD_ENTRY_HOOK(ec, 0, 0);
	    return;
	  case RUBY_EVENT_C_CALL:
	    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(ec, 0, 0);
	    return;
	  case RUBY_EVENT_RETURN:
	    RUBY_DTRACE_METHOD_RETURN_HOOK(ec, 0, 0);
	    return;
	  case RUBY_EVENT_C_RETURN:
	    RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, 0, 0);
	    return;
	}
    }
}

static VALUE
vm_const_get_under(ID id, rb_num_t flags, VALUE cbase)
{
    VALUE ns;

    if ((ns = vm_search_const_defined_class(cbase, id)) == 0) {
	return ns;
    }
    else if (VM_DEFINECLASS_SCOPED_P(flags)) {
	return rb_public_const_get_at(ns, id);
    }
    else {
	return rb_const_get_at(ns, id);
    }
}

static VALUE
vm_check_if_class(ID id, rb_num_t flags, VALUE super, VALUE klass)
{
    if (!RB_TYPE_P(klass, T_CLASS)) {
	rb_raise(rb_eTypeError, "%"PRIsVALUE" is not a class", rb_id2str(id));
    }
    else if (VM_DEFINECLASS_HAS_SUPERCLASS_P(flags)) {
	VALUE tmp = rb_class_real(RCLASS_SUPER(klass));

	if (tmp != super) {
	    rb_raise(rb_eTypeError,
		     "superclass mismatch for class %"PRIsVALUE"",
		     rb_id2str(id));
	}
	else {
	    return klass;
	}
    }
    else {
	return klass;
    }
}

static VALUE
vm_check_if_module(ID id, VALUE mod)
{
    if (!RB_TYPE_P(mod, T_MODULE)) {
	rb_raise(rb_eTypeError, "%"PRIsVALUE" is not a module", rb_id2str(id));
    }
    else {
	return mod;
    }
}

static VALUE
vm_declare_class(ID id, rb_num_t flags, VALUE cbase, VALUE super)
{
    /* new class declaration */
    VALUE s = VM_DEFINECLASS_HAS_SUPERCLASS_P(flags) ? super : rb_cObject;
    VALUE c = rb_define_class_id(id, s);

    rb_set_class_path_string(c, cbase, rb_id2str(id));
    rb_const_set(cbase, id, c);
    rb_class_inherited(s, c);
    return c;
}

static VALUE
vm_declare_module(ID id, VALUE cbase)
{
    /* new module declaration */
    VALUE mod = rb_define_module_id(id);
    rb_set_class_path_string(mod, cbase, rb_id2str(id));
    rb_const_set(cbase, id, mod);
    return mod;
}

static VALUE
vm_define_class(ID id, rb_num_t flags, VALUE cbase, VALUE super)
{
    VALUE klass;

    if (VM_DEFINECLASS_HAS_SUPERCLASS_P(flags) && !RB_TYPE_P(super, T_CLASS)) {
	rb_raise(rb_eTypeError,
		 "superclass must be a Class (%"PRIsVALUE" given)",
		 rb_obj_class(super));
    }

    vm_check_if_namespace(cbase);

    /* find klass */
    rb_autoload_load(cbase, id);
    if ((klass = vm_const_get_under(id, flags, cbase)) != 0) {
	return vm_check_if_class(id, flags, super, klass);
    }
    else {
	return vm_declare_class(id, flags, cbase, super);
    }
}

static VALUE
vm_define_module(ID id, rb_num_t flags, VALUE cbase)
{
    VALUE mod;

    vm_check_if_namespace(cbase);
    if ((mod = vm_const_get_under(id, flags, cbase)) != 0) {
	return vm_check_if_module(id, mod);
    }
    else {
	return vm_declare_module(id, cbase);
    }
}

static VALUE
vm_find_or_create_class_by_id(ID id,
			      rb_num_t flags,
			      VALUE cbase,
			      VALUE super)
{
    rb_vm_defineclass_type_t type = VM_DEFINECLASS_TYPE(flags);

    switch (type) {
      case VM_DEFINECLASS_TYPE_CLASS:
	/* classdef returns class scope value */
	return vm_define_class(id, flags, cbase, super);

      case VM_DEFINECLASS_TYPE_SINGLETON_CLASS:
	/* classdef returns class scope value */
	return rb_singleton_class(cbase);

      case VM_DEFINECLASS_TYPE_MODULE:
	/* classdef returns class scope value */
	return vm_define_module(id, flags, cbase);

      default:
	rb_bug("unknown defineclass type: %d", (int)type);
    }
}

static rb_method_visibility_t
vm_scope_visibility_get(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (!vm_env_cref_by_cref(cfp->ep)) {
        return METHOD_VISI_PUBLIC;
    }
    else {
        return CREF_SCOPE_VISI(vm_ec_cref(ec))->method_visi;
    }
}

static int
vm_scope_module_func_check(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (!vm_env_cref_by_cref(cfp->ep)) {
        return FALSE;
    }
    else {
        return CREF_SCOPE_VISI(vm_ec_cref(ec))->module_func;
    }
}

static void
vm_define_method(const rb_execution_context_t *ec, VALUE obj, ID id, VALUE iseqval, int is_singleton)
{
    VALUE klass;
    rb_method_visibility_t visi;
    rb_cref_t *cref = vm_ec_cref(ec);

    if (!is_singleton) {
        klass = CREF_CLASS(cref);
        visi = vm_scope_visibility_get(ec);
    }
    else { /* singleton */
        klass = rb_singleton_class(obj); /* class and frozen checked in this API */
        visi = METHOD_VISI_PUBLIC;
    }

    if (NIL_P(klass)) {
        rb_raise(rb_eTypeError, "no class/module to add method");
    }

    rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, visi);

    if (!is_singleton && vm_scope_module_func_check(ec)) {
        klass = rb_singleton_class(klass);
        rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, METHOD_VISI_PUBLIC);
    }
}

static void
vm_search_method_wrap(
    const struct rb_control_frame_struct *reg_cfp,
    struct rb_call_info *ci,
    struct rb_call_cache *cc,
    VALUE recv)
{
    vm_search_method(ci, cc, recv);
}

static void
vm_search_invokeblock(
    const struct rb_control_frame_struct *reg_cfp,
    struct rb_call_info *ci,
    struct rb_call_cache *cc,
    VALUE recv)
{
    /* Does nothing. */
}

static VALUE
vm_invokeblock_i(
    struct rb_execution_context_struct *ec,
    struct rb_control_frame_struct *reg_cfp,
    struct rb_calling_info *calling,
    const struct rb_call_info *ci,
    struct rb_call_cache *cc)
{
    VALUE block_handler = VM_CF_BLOCK_HANDLER(GET_CFP());

    if (block_handler == VM_BLOCK_HANDLER_NONE) {
        rb_vm_localjump_error("no block given (yield)", Qnil, 0);
    }
    else {
        return vm_invoke_block(ec, GET_CFP(), calling, ci, block_handler);
    }
}

static VALUE
vm_sendish(
    struct rb_execution_context_struct *ec,
    struct rb_control_frame_struct *reg_cfp,
    struct rb_call_info *ci,
    struct rb_call_cache *cc,
    VALUE block_handler,
    void (*method_explorer)(
        const struct rb_control_frame_struct *reg_cfp,
        struct rb_call_info *ci,
        struct rb_call_cache *cc,
        VALUE recv))
{
    VALUE val;
    int argc = ci->orig_argc;
    VALUE recv = TOPN(argc);
    struct rb_calling_info calling;

    calling.block_handler = block_handler;
    calling.recv = recv;
    calling.argc = argc;

    method_explorer(GET_CFP(), ci, cc, recv);

    val = cc->call(ec, GET_CFP(), &calling, ci, cc);

    if (val != Qundef) {
        return val;             /* CFUNC normal return */
    }
    else {
        RESTORE_REGS();         /* CFP pushed in cc->call() */
    }

#ifdef MJIT_HEADER
    /* When calling ISeq which may catch an exception from JIT-ed
       code, we should not call mjit_exec directly to prevent the
       caller frame from being canceled. That's because the caller
       frame may have stack values in the local variables and the
       cancelling the caller frame will purge them. But directly
       calling mjit_exec is faster... */
    if (GET_ISEQ()->body->catch_except_p) {
        VM_ENV_FLAGS_SET(GET_EP(), VM_FRAME_FLAG_FINISH);
        return vm_exec(ec, true);
    }
    else if ((val = mjit_exec(ec)) == Qundef) {
        VM_ENV_FLAGS_SET(GET_EP(), VM_FRAME_FLAG_FINISH);
        return vm_exec(ec, false);
    }
    else {
        return val;
    }
#else
    /* When calling from VM, longjmp in the callee won't purge any
       JIT-ed caller frames.  So it's safe to directly call
       mjit_exec. */
    return mjit_exec(ec);
#endif
}

static VALUE
vm_opt_str_freeze(VALUE str, int bop, ID id)
{
    if (BASIC_OP_UNREDEFINED_P(bop, STRING_REDEFINED_OP_FLAG)) {
	return str;
    }
    else {
	return Qundef;
    }
}

/* this macro is mandatory to use OPTIMIZED_CMP. What a design! */
#define id_cmp idCmp

static VALUE
vm_opt_newarray_max(rb_num_t num, const VALUE *ptr)
{
    if (BASIC_OP_UNREDEFINED_P(BOP_MAX, ARRAY_REDEFINED_OP_FLAG)) {
	if (num == 0) {
	    return Qnil;
	}
	else {
	    struct cmp_opt_data cmp_opt = { 0, 0 };
	    VALUE result = *ptr;
            rb_snum_t i = num - 1;
	    while (i-- > 0) {
		const VALUE v = *++ptr;
		if (OPTIMIZED_CMP(v, result, cmp_opt) > 0) {
		    result = v;
		}
	    }
	    return result;
	}
    }
    else {
	VALUE ary = rb_ary_new4(num, ptr);
	return rb_funcall(ary, idMax, 0);
    }
}

static VALUE
vm_opt_newarray_min(rb_num_t num, const VALUE *ptr)
{
    if (BASIC_OP_UNREDEFINED_P(BOP_MIN, ARRAY_REDEFINED_OP_FLAG)) {
	if (num == 0) {
	    return Qnil;
	}
	else {
	    struct cmp_opt_data cmp_opt = { 0, 0 };
	    VALUE result = *ptr;
            rb_snum_t i = num - 1;
	    while (i-- > 0) {
		const VALUE v = *++ptr;
		if (OPTIMIZED_CMP(v, result, cmp_opt) < 0) {
		    result = v;
		}
	    }
	    return result;
	}
    }
    else {
	VALUE ary = rb_ary_new4(num, ptr);
	return rb_funcall(ary, idMin, 0);
    }
}

#undef id_cmp

static int
vm_ic_hit_p(IC ic, const VALUE *reg_ep)
{
    if (ic->ic_serial == GET_GLOBAL_CONSTANT_STATE()) {
        return (ic->ic_cref == NULL || // no need to check CREF
                ic->ic_cref == vm_get_cref(reg_ep));
    }
    return FALSE;
}

static void
vm_ic_update(IC ic, VALUE val, const VALUE *reg_ep)
{
    VM_ASSERT(ic->ic_value.value != Qundef);
    ic->ic_value.value = val;
    ic->ic_serial = GET_GLOBAL_CONSTANT_STATE() - ruby_vm_const_missing_count;
    ic->ic_cref = vm_get_const_key_cref(reg_ep);
    ruby_vm_const_missing_count = 0;
}

static VALUE
vm_once_dispatch(rb_execution_context_t *ec, ISEQ iseq, ISE is)
{
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    rb_thread_t *const RUNNING_THREAD_ONCE_DONE = (rb_thread_t *)(0x1);

  again:
    if (is->once.running_thread == RUNNING_THREAD_ONCE_DONE) {
	return is->once.value;
    }
    else if (is->once.running_thread == NULL) {
	VALUE val;
	is->once.running_thread = th;
	val = rb_ensure(vm_once_exec, (VALUE)iseq, vm_once_clear, (VALUE)is);
	RB_OBJ_WRITE(ec->cfp->iseq, &is->once.value, val);
	/* is->once.running_thread is cleared by vm_once_clear() */
	is->once.running_thread = RUNNING_THREAD_ONCE_DONE; /* success */
	return val;
    }
    else if (is->once.running_thread == th) {
	/* recursive once */
	return vm_once_exec((VALUE)iseq);
    }
    else {
	/* waiting for finish */
	RUBY_VM_CHECK_INTS(ec);
	rb_thread_schedule();
	goto again;
    }
}

static OFFSET
vm_case_dispatch(CDHASH hash, OFFSET else_offset, VALUE key)
{
    switch (OBJ_BUILTIN_TYPE(key)) {
      case -1:
      case T_FLOAT:
      case T_SYMBOL:
      case T_BIGNUM:
      case T_STRING:
	if (BASIC_OP_UNREDEFINED_P(BOP_EQQ,
				   SYMBOL_REDEFINED_OP_FLAG |
				   INTEGER_REDEFINED_OP_FLAG |
				   FLOAT_REDEFINED_OP_FLAG |
				   NIL_REDEFINED_OP_FLAG    |
				   TRUE_REDEFINED_OP_FLAG   |
				   FALSE_REDEFINED_OP_FLAG  |
				   STRING_REDEFINED_OP_FLAG)) {
	    st_data_t val;
	    if (RB_FLOAT_TYPE_P(key)) {
		double kval = RFLOAT_VALUE(key);
		if (!isinf(kval) && modf(kval, &kval) == 0.0) {
		    key = FIXABLE(kval) ? LONG2FIX((long)kval) : rb_dbl2big(kval);
		}
	    }
            if (rb_hash_stlike_lookup(hash, key, &val)) {
		return FIX2LONG((VALUE)val);
	    }
	    else {
		return else_offset;
	    }
	}
    }
    return 0;
}

NORETURN(static void
	 vm_stack_consistency_error(const rb_execution_context_t *ec,
				    const rb_control_frame_t *,
				    const VALUE *));
static void
vm_stack_consistency_error(const rb_execution_context_t *ec,
			   const rb_control_frame_t *cfp,
			   const VALUE *bp)
{
    const ptrdiff_t nsp = VM_SP_CNT(ec, cfp->sp);
    const ptrdiff_t nbp = VM_SP_CNT(ec, bp);
    static const char stack_consistency_error[] =
	"Stack consistency error (sp: %"PRIdPTRDIFF", bp: %"PRIdPTRDIFF")";
#if defined RUBY_DEVEL
    VALUE mesg = rb_sprintf(stack_consistency_error, nsp, nbp);
    rb_str_cat_cstr(mesg, "\n");
    rb_str_append(mesg, rb_iseq_disasm(cfp->iseq));
    rb_exc_fatal(rb_exc_new3(rb_eFatal, mesg));
#else
    rb_bug(stack_consistency_error, nsp, nbp);
#endif
}

static VALUE
vm_opt_plus(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_PLUS, INTEGER_REDEFINED_OP_FLAG)) {
	return rb_fix_plus_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_PLUS, FLOAT_REDEFINED_OP_FLAG)) {
	return DBL2NUM(RFLOAT_VALUE(recv) + RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_PLUS, FLOAT_REDEFINED_OP_FLAG)) {
	return DBL2NUM(RFLOAT_VALUE(recv) + RFLOAT_VALUE(obj));
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
	     RBASIC_CLASS(obj) == rb_cString &&
	     BASIC_OP_UNREDEFINED_P(BOP_PLUS, STRING_REDEFINED_OP_FLAG)) {
        return rb_str_opt_plus(recv, obj);
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
             RBASIC_CLASS(obj) == rb_cArray &&
	     BASIC_OP_UNREDEFINED_P(BOP_PLUS, ARRAY_REDEFINED_OP_FLAG)) {
	return rb_ary_plus(recv, obj);
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_minus(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_MINUS, INTEGER_REDEFINED_OP_FLAG)) {
	return rb_fix_minus_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_MINUS, FLOAT_REDEFINED_OP_FLAG)) {
	return DBL2NUM(RFLOAT_VALUE(recv) - RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_MINUS, FLOAT_REDEFINED_OP_FLAG)) {
	return DBL2NUM(RFLOAT_VALUE(recv) - RFLOAT_VALUE(obj));
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_mult(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_MULT, INTEGER_REDEFINED_OP_FLAG)) {
	return rb_fix_mul_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_MULT, FLOAT_REDEFINED_OP_FLAG)) {
	return DBL2NUM(RFLOAT_VALUE(recv) * RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_MULT, FLOAT_REDEFINED_OP_FLAG)) {
	return DBL2NUM(RFLOAT_VALUE(recv) * RFLOAT_VALUE(obj));
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_div(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_DIV, INTEGER_REDEFINED_OP_FLAG)) {
	return (FIX2LONG(obj) == 0) ? Qundef : rb_fix_div_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_DIV, FLOAT_REDEFINED_OP_FLAG)) {
        return rb_flo_div_flo(recv, obj);
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_DIV, FLOAT_REDEFINED_OP_FLAG)) {
        return rb_flo_div_flo(recv, obj);
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_mod(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_MOD, INTEGER_REDEFINED_OP_FLAG)) {
	return (FIX2LONG(obj) == 0) ? Qundef : rb_fix_mod_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_MOD, FLOAT_REDEFINED_OP_FLAG)) {
	return DBL2NUM(ruby_float_mod(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj)));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_MOD, FLOAT_REDEFINED_OP_FLAG)) {
	return DBL2NUM(ruby_float_mod(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj)));
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_neq(CALL_INFO ci, CALL_CACHE cc,
	   CALL_INFO ci_eq, CALL_CACHE cc_eq,
	   VALUE recv, VALUE obj)
{
    if (vm_method_cfunc_is(ci, cc, recv, rb_obj_not_equal)) {
	VALUE val = opt_eq_func(recv, obj, ci_eq, cc_eq);

	if (val != Qundef) {
	    return RTEST(val) ? Qfalse : Qtrue;
	}
    }

    return Qundef;
}

static VALUE
vm_opt_lt(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_LT, INTEGER_REDEFINED_OP_FLAG)) {
	return (SIGNED_VALUE)recv < (SIGNED_VALUE)obj ? Qtrue : Qfalse;
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_LT, FLOAT_REDEFINED_OP_FLAG)) {
	return RFLOAT_VALUE(recv) < RFLOAT_VALUE(obj) ? Qtrue : Qfalse;
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_LT, FLOAT_REDEFINED_OP_FLAG)) {
	CHECK_CMP_NAN(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj));
	return RFLOAT_VALUE(recv) < RFLOAT_VALUE(obj) ? Qtrue : Qfalse;
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_le(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_LE, INTEGER_REDEFINED_OP_FLAG)) {
	return (SIGNED_VALUE)recv <= (SIGNED_VALUE)obj ? Qtrue : Qfalse;
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_LE, FLOAT_REDEFINED_OP_FLAG)) {
	return RFLOAT_VALUE(recv) <= RFLOAT_VALUE(obj) ? Qtrue : Qfalse;
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_LE, FLOAT_REDEFINED_OP_FLAG)) {
	CHECK_CMP_NAN(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj));
	return RFLOAT_VALUE(recv) <= RFLOAT_VALUE(obj) ? Qtrue : Qfalse;
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_gt(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_GT, INTEGER_REDEFINED_OP_FLAG)) {
	return (SIGNED_VALUE)recv > (SIGNED_VALUE)obj ? Qtrue : Qfalse;
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_GT, FLOAT_REDEFINED_OP_FLAG)) {
	return RFLOAT_VALUE(recv) > RFLOAT_VALUE(obj) ? Qtrue : Qfalse;
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_GT, FLOAT_REDEFINED_OP_FLAG)) {
	CHECK_CMP_NAN(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj));
	return RFLOAT_VALUE(recv) > RFLOAT_VALUE(obj) ? Qtrue : Qfalse;
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_ge(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_GE, INTEGER_REDEFINED_OP_FLAG)) {
	return (SIGNED_VALUE)recv >= (SIGNED_VALUE)obj ? Qtrue : Qfalse;
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_GE, FLOAT_REDEFINED_OP_FLAG)) {
	return RFLOAT_VALUE(recv) >= RFLOAT_VALUE(obj) ? Qtrue : Qfalse;
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
	     RBASIC_CLASS(obj)  == rb_cFloat &&
	     BASIC_OP_UNREDEFINED_P(BOP_GE, FLOAT_REDEFINED_OP_FLAG)) {
	CHECK_CMP_NAN(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj));
	return RFLOAT_VALUE(recv) >= RFLOAT_VALUE(obj) ? Qtrue : Qfalse;
    }
    else {
	return Qundef;
    }
}


static VALUE
vm_opt_ltlt(VALUE recv, VALUE obj)
{
    if (SPECIAL_CONST_P(recv)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
	     BASIC_OP_UNREDEFINED_P(BOP_LTLT, STRING_REDEFINED_OP_FLAG)) {
	return rb_str_concat(recv, obj);
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
	     BASIC_OP_UNREDEFINED_P(BOP_LTLT, ARRAY_REDEFINED_OP_FLAG)) {
	return rb_ary_push(recv, obj);
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_and(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_AND, INTEGER_REDEFINED_OP_FLAG)) {
        return LONG2NUM(FIX2LONG(recv) & FIX2LONG(obj));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_or(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_OR, INTEGER_REDEFINED_OP_FLAG)) {
        return LONG2NUM(FIX2LONG(recv) | FIX2LONG(obj));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_aref(VALUE recv, VALUE obj)
{
    if (SPECIAL_CONST_P(recv)) {
        if (FIXNUM_P(recv) && FIXNUM_P(obj) &&
                BASIC_OP_UNREDEFINED_P(BOP_AREF, INTEGER_REDEFINED_OP_FLAG)) {
            return rb_fix_aref(recv, obj);
        }
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
	     BASIC_OP_UNREDEFINED_P(BOP_AREF, ARRAY_REDEFINED_OP_FLAG)) {
        if (FIXNUM_P(obj)) {
            return rb_ary_entry_internal(recv, FIX2LONG(obj));
        }
        else {
            return rb_ary_aref1(recv, obj);
        }
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
	     BASIC_OP_UNREDEFINED_P(BOP_AREF, HASH_REDEFINED_OP_FLAG)) {
	return rb_hash_aref(recv, obj);
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_aset(VALUE recv, VALUE obj, VALUE set)
{
    if (SPECIAL_CONST_P(recv)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
	     BASIC_OP_UNREDEFINED_P(BOP_ASET, ARRAY_REDEFINED_OP_FLAG) &&
	     FIXNUM_P(obj)) {
	rb_ary_store(recv, FIX2LONG(obj), set);
	return set;
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
	     BASIC_OP_UNREDEFINED_P(BOP_ASET, HASH_REDEFINED_OP_FLAG)) {
	rb_hash_aset(recv, obj, set);
	return set;
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_aref_with(VALUE recv, VALUE key)
{
    if (!SPECIAL_CONST_P(recv) && RBASIC_CLASS(recv) == rb_cHash &&
	BASIC_OP_UNREDEFINED_P(BOP_AREF, HASH_REDEFINED_OP_FLAG) &&
	rb_hash_compare_by_id_p(recv) == Qfalse) {
	return rb_hash_aref(recv, key);
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_aset_with(VALUE recv, VALUE key, VALUE val)
{
    if (!SPECIAL_CONST_P(recv) && RBASIC_CLASS(recv) == rb_cHash &&
	BASIC_OP_UNREDEFINED_P(BOP_ASET, HASH_REDEFINED_OP_FLAG) &&
	rb_hash_compare_by_id_p(recv) == Qfalse) {
	return rb_hash_aset(recv, key, val);
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_length(VALUE recv, int bop)
{
    if (SPECIAL_CONST_P(recv)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
	     BASIC_OP_UNREDEFINED_P(bop, STRING_REDEFINED_OP_FLAG)) {
	if (bop == BOP_EMPTY_P) {
	    return LONG2NUM(RSTRING_LEN(recv));
	}
	else {
	    return rb_str_length(recv);
	}
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
	     BASIC_OP_UNREDEFINED_P(bop, ARRAY_REDEFINED_OP_FLAG)) {
	return LONG2NUM(RARRAY_LEN(recv));
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
	     BASIC_OP_UNREDEFINED_P(bop, HASH_REDEFINED_OP_FLAG)) {
	return INT2FIX(RHASH_SIZE(recv));
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_empty_p(VALUE recv)
{
    switch (vm_opt_length(recv, BOP_EMPTY_P)) {
      case Qundef: return Qundef;
      case INT2FIX(0): return Qtrue;
      default: return Qfalse;
    }
}

VALUE rb_false(VALUE obj);

static VALUE
vm_opt_nil_p(CALL_INFO ci, CALL_CACHE cc, VALUE recv)
{
    if (recv == Qnil) {
        if (BASIC_OP_UNREDEFINED_P(BOP_NIL_P, NIL_REDEFINED_OP_FLAG)) {
            return Qtrue;
        } else {
            return Qundef;
        }
    } else {
        if (vm_method_cfunc_is(ci, cc, recv, rb_false)) {
            return Qfalse;
        } else {
            return Qundef;
        }
    }
}

static VALUE
fix_succ(VALUE x)
{
    switch (x) {
      case ~0UL:
        /* 0xFFFF_FFFF == INT2FIX(-1)
         * `-1.succ` is of course 0. */
        return INT2FIX(0);
      case RSHIFT(~0UL, 1):
        /* 0x7FFF_FFFF == LONG2FIX(0x3FFF_FFFF)
         * 0x3FFF_FFFF + 1 == 0x4000_0000, which is a Bignum. */
        return rb_uint2big(1UL << (SIZEOF_LONG * CHAR_BIT - 2));
      default:
        /*    LONG2FIX(FIX2LONG(x)+FIX2LONG(y))
         * == ((lx*2+1)/2 + (ly*2+1)/2)*2+1
         * == lx*2 + ly*2 + 1
         * == (lx*2+1) + (ly*2+1) - 1
         * == x + y - 1
         *
         * Here, if we put y := INT2FIX(1):
         *
         * == x + INT2FIX(1) - 1
         * == x + 2 .
         */
        return x + 2;
    }
}

static VALUE
vm_opt_succ(VALUE recv)
{
    if (FIXNUM_P(recv) &&
	BASIC_OP_UNREDEFINED_P(BOP_SUCC, INTEGER_REDEFINED_OP_FLAG)) {
        return fix_succ(recv);
    }
    else if (SPECIAL_CONST_P(recv)) {
	return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
	     BASIC_OP_UNREDEFINED_P(BOP_SUCC, STRING_REDEFINED_OP_FLAG)) {
	return rb_str_succ(recv);
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_not(CALL_INFO ci, CALL_CACHE cc, VALUE recv)
{
    if (vm_method_cfunc_is(ci, cc, recv, rb_obj_not)) {
	return RTEST(recv) ? Qfalse : Qtrue;
    }
    else {
	return Qundef;
    }
}

static VALUE
vm_opt_regexpmatch1(VALUE recv, VALUE obj)
{
    if (BASIC_OP_UNREDEFINED_P(BOP_MATCH, REGEXP_REDEFINED_OP_FLAG)) {
	return rb_reg_match(recv, obj);
    }
    else {
	return rb_funcall(recv, idEqTilde, 1, obj);
    }
}

static VALUE
vm_opt_regexpmatch2(VALUE recv, VALUE obj)
{
    if (CLASS_OF(recv) == rb_cString &&
	BASIC_OP_UNREDEFINED_P(BOP_MATCH, STRING_REDEFINED_OP_FLAG)) {
	return rb_reg_match(obj, recv);
    }
    else {
	return Qundef;
    }
}

rb_event_flag_t rb_iseq_event_flags(const rb_iseq_t *iseq, size_t pos);

NOINLINE(static void vm_trace(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE *pc));

static inline void
vm_trace_hook(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE *pc,
              rb_event_flag_t pc_events, rb_event_flag_t target_event,
              rb_hook_list_t *global_hooks, rb_hook_list_t *local_hooks, VALUE val)
{
    rb_event_flag_t event = pc_events & target_event;
    VALUE self = GET_SELF();

    VM_ASSERT(rb_popcount64((uint64_t)event) == 1);

    if (event & global_hooks->events) {
        /* increment PC because source line is calculated with PC-1 */
        reg_cfp->pc++;
        vm_dtrace(event, ec);
        rb_exec_event_hook_orig(ec, global_hooks, event, self, 0, 0, 0 , val, 0);
        reg_cfp->pc--;
    }

    if (local_hooks != NULL) {
        if (event & local_hooks->events) {
            /* increment PC because source line is calculated with PC-1 */
            reg_cfp->pc++;
            rb_exec_event_hook_orig(ec, local_hooks, event, self, 0, 0, 0 , val, 0);
            reg_cfp->pc--;
        }
    }
}

#define VM_TRACE_HOOK(target_event, val) do { \
    if ((pc_events & (target_event)) & enabled_flags) { \
        vm_trace_hook(ec, reg_cfp, pc, pc_events, (target_event), global_hooks, local_hooks, (val)); \
    } \
} while (0)

static void
vm_trace(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE *pc)
{
    rb_event_flag_t enabled_flags = ruby_vm_event_flags & ISEQ_TRACE_EVENTS;

    if (enabled_flags == 0 && ruby_vm_event_local_num == 0) {
        return;
    }
    else {
	const rb_iseq_t *iseq = reg_cfp->iseq;
	size_t pos = pc - iseq->body->iseq_encoded;
        rb_event_flag_t pc_events = rb_iseq_event_flags(iseq, pos);
        rb_hook_list_t *local_hooks = iseq->aux.exec.local_hooks;
        rb_event_flag_t local_hook_events = local_hooks != NULL ? local_hooks->events : 0;
        enabled_flags |= local_hook_events;

        VM_ASSERT((local_hook_events & ~ISEQ_TRACE_EVENTS) == 0);

        if ((pc_events & enabled_flags) == 0) {
#if 0
	    /* disable trace */
            /* TODO: incomplete */
	    rb_iseq_trace_set(iseq, vm_event_flags & ISEQ_TRACE_EVENTS);
#else
	    /* do not disable trace because of performance problem
	     * (re-enable overhead)
	     */
#endif
	    return;
        }
        else if (ec->trace_arg != NULL) {
            /* already tracing */
            return;
        }
        else {
            rb_hook_list_t *global_hooks = rb_vm_global_hooks(ec);

            if (0) {
                fprintf(stderr, "vm_trace>>%4d (%4x) - %s:%d %s\n",
                        (int)pos,
                        (int)pc_events,
                        RSTRING_PTR(rb_iseq_path(iseq)),
                        (int)rb_iseq_line_no(iseq, pos),
                        RSTRING_PTR(rb_iseq_label(iseq)));
            }
            VM_ASSERT(reg_cfp->pc == pc);
            VM_ASSERT(pc_events != 0);
            VM_ASSERT(enabled_flags & pc_events);

            /* check traces */
            VM_TRACE_HOOK(RUBY_EVENT_CLASS | RUBY_EVENT_CALL | RUBY_EVENT_B_CALL,   Qundef);
            VM_TRACE_HOOK(RUBY_EVENT_LINE,                                          Qundef);
            VM_TRACE_HOOK(RUBY_EVENT_COVERAGE_LINE,                                 Qundef);
            VM_TRACE_HOOK(RUBY_EVENT_COVERAGE_BRANCH,                               Qundef);
            VM_TRACE_HOOK(RUBY_EVENT_END | RUBY_EVENT_RETURN | RUBY_EVENT_B_RETURN, TOPN(0));
        }
    }
}

#if VM_CHECK_MODE > 0
static NORETURN( NOINLINE( COLDFUNC
void vm_canary_is_found_dead(enum ruby_vminsn_type i, VALUE c)));

void
Init_vm_stack_canary(void)
{
    /* This has to be called _after_ our PRNG is properly set up. */
    int n = ruby_fill_random_bytes(&vm_stack_canary, sizeof vm_stack_canary, false);

    vm_stack_canary_was_born = true;
    VM_ASSERT(n == 0);
}

static void
vm_canary_is_found_dead(enum ruby_vminsn_type i, VALUE c)
{
    /* Because a method has already been called, why not call
     * another one. */
    const char *insn = rb_insns_name(i);
    VALUE inspection = rb_inspect(c);
    const char *str  = StringValueCStr(inspection);

    rb_bug("dead canary found at %s: %s", insn, str);
}

#else
void Init_vm_stack_canary(void) { /* nothing to do */ }
#endif
