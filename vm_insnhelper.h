/**********************************************************************

  insnhelper.h - helper macros to implement each instructions

  $Author$
  created at: 04/01/01 15:50:34 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifndef RUBY_INSNHELPER_H
#define RUBY_INSNHELPER_H

extern VALUE ruby_vm_const_missing_count;

#if VM_COLLECT_USAGE_DETAILS
#define COLLECT_USAGE_INSN(insn)           vm_collect_usage_insn(insn)
#define COLLECT_USAGE_OPERAND(insn, n, op) vm_collect_usage_operand((insn), (n), ((VALUE)(op)))

#define COLLECT_USAGE_REGISTER(reg, s)     vm_collect_usage_register((reg), (s))
#else
#define COLLECT_USAGE_INSN(insn)		/* none */
#define COLLECT_USAGE_OPERAND(insn, n, op)	/* none */
#define COLLECT_USAGE_REGISTER(reg, s)		/* none */
#endif

/**********************************************************/
/* deal with stack                                        */
/**********************************************************/

#define PUSH(x) (SET_SV(x), INC_SP(1))
#define TOPN(n) (*(GET_SP()-(n)-1))
#define POPN(n) (DEC_SP(n))
#define POP()   (DEC_SP(1))
#define STACK_ADDR_FROM_TOP(n) (GET_SP()-(n))

#define GET_TOS()  (tos)	/* dummy */

/**********************************************************/
/* deal with registers                                    */
/**********************************************************/

#define REG_CFP (reg_cfp)
#define REG_PC  (REG_CFP->pc)
#define REG_SP  (REG_CFP->sp)
#define REG_EP  (REG_CFP->ep)

#define RESTORE_REGS() do { \
  REG_CFP = th->cfp; \
} while (0)

#define REG_A   reg_a
#define REG_B   reg_b

enum vm_regan_regtype {
    VM_REGAN_PC = 0,
    VM_REGAN_SP = 1,
    VM_REGAN_EP = 2,
    VM_REGAN_CFP = 3,
    VM_REGAN_SELF = 4,
    VM_REGAN_ISEQ = 5,
};
enum vm_regan_acttype {
    VM_REGAN_ACT_GET = 0,
    VM_REGAN_ACT_SET = 1,
};

#if VM_COLLECT_USAGE_DETAILS
#define COLLECT_USAGE_REGISTER_HELPER(a, b, v) \
  (COLLECT_USAGE_REGISTER((VM_REGAN_##a), (VM_REGAN_ACT_##b)), (v))
#else
#define COLLECT_USAGE_REGISTER_HELPER(a, b, v) (v)
#endif

/* PC */
#define GET_PC()           (COLLECT_USAGE_REGISTER_HELPER(PC, GET, REG_PC))
#define SET_PC(x)          (REG_PC = (COLLECT_USAGE_REGISTER_HELPER(PC, SET, (x))))
#define GET_CURRENT_INSN() (*GET_PC())
#define GET_OPERAND(n)     (GET_PC()[(n)])
#define ADD_PC(n)          (SET_PC(REG_PC + (n)))
#define JUMP(dst)          (REG_PC += (dst))

/* frame pointer, environment pointer */
#define GET_CFP()  (COLLECT_USAGE_REGISTER_HELPER(CFP, GET, REG_CFP))
#define GET_EP()   (COLLECT_USAGE_REGISTER_HELPER(EP, GET, REG_EP))
#define SET_EP(x)  (REG_EP = (COLLECT_USAGE_REGISTER_HELPER(EP, SET, (x))))
#define GET_LEP()  (VM_EP_LEP(GET_EP()))

/* SP */
#define GET_SP()   (COLLECT_USAGE_REGISTER_HELPER(SP, GET, REG_SP))
#define SET_SP(x)  (REG_SP  = (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define INC_SP(x)  (REG_SP += (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define DEC_SP(x)  (REG_SP -= (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define SET_SV(x)  (*GET_SP() = (x))
  /* set current stack value as x */

#define GET_SP_COUNT() (REG_SP - th->stack)

/* instruction sequence C struct */
#define GET_ISEQ() (GET_CFP()->iseq)

/**********************************************************/
/* deal with variables                                    */
/**********************************************************/

#define GET_PREV_EP(ep)                ((VALUE *)((ep)[0] & ~0x03))

#define GET_GLOBAL(entry)       rb_gvar_get((struct rb_global_entry*)(entry))
#define SET_GLOBAL(entry, val)  rb_gvar_set((struct rb_global_entry*)(entry), (val))

#define GET_CONST_INLINE_CACHE(dst) ((IC) * (GET_PC() + (dst) + 2))

/**********************************************************/
/* deal with values                                       */
/**********************************************************/

#define GET_SELF() (COLLECT_USAGE_REGISTER_HELPER(SELF, GET, GET_CFP()->self))

/**********************************************************/
/* deal with control flow 2: method/iterator              */
/**********************************************************/

#define CALL_METHOD(calling, ci, cc) do { \
    VALUE v = (*(cc)->call)(th, GET_CFP(), (calling), (ci), (cc)); \
    iseq_deoptimize_if_needed(GET_ISEQ(), ruby_vm_global_timestamp); \
    if (v == Qundef) { \
	RESTORE_REGS(); \
	NEXT_INSN(); \
    } \
    else { \
	val = v; \
    } \
} while (0)

/* set fastpath when cached method is *NOT* protected
 * because inline method cache does not care about receiver.
 */

#ifndef OPT_CALL_FASTPATH
#define OPT_CALL_FASTPATH 1
#endif

#if OPT_CALL_FASTPATH
#define CI_SET_FASTPATH(cc, func, enabled) do { \
    if (LIKELY(enabled)) ((cc)->call = (func)); \
} while (0)
#else
#define CI_SET_FASTPATH(ci, func, enabled) /* do nothing */
#endif

#define GET_BLOCK_PTR() ((rb_block_t *)(GC_GUARDED_PTR_REF(GET_LEP()[0])))

/**********************************************************/
/* deal with control flow 3: exception                    */
/**********************************************************/


/**********************************************************/
/* others                                                 */
/**********************************************************/

/* optimize insn */
#define FIXNUM_2_P(a, b) ((a) & (b) & 1)
#if USE_FLONUM
#define FLONUM_2_P(a, b) (((((a)^2) | ((b)^2)) & 3) == 0) /* (FLONUM_P(a) && FLONUM_P(b)) */
#else
#define FLONUM_2_P(a, b) 0
#endif

#ifndef USE_IC_FOR_SPECIALIZED_METHOD
#define USE_IC_FOR_SPECIALIZED_METHOD 1
#endif

#define CALL_SIMPLE_METHOD(recv_) do { \
    struct rb_calling_info calling; \
    calling.blockptr = NULL; \
    calling.argc = ci->orig_argc; \
    vm_search_method(ci, cc, calling.recv = (recv_)); \
    CALL_METHOD(&calling, ci, cc); \
} while (0)

#define NEXT_CLASS_SERIAL() (++ruby_vm_class_serial)
#define GET_GLOBAL_METHOD_STATE() (ruby_vm_global_method_state)
#define INC_GLOBAL_METHOD_STATE() (++ruby_vm_global_method_state)
#define GET_GLOBAL_CONSTANT_STATE() (ruby_vm_global_constant_state)
#define INC_GLOBAL_CONSTANT_STATE() (++ruby_vm_global_constant_state)

#if RUBY_ATOMIC_GENERIC_MACRO
# define INC_GLOBAL_TIMESTAMP() ATOMIC_INC(ruby_vm_global_timestamp)
#elif defined(HAVE_LONG_LONG) && (SIZEOF_SIZE_T == SIZEOF_LONG_LONG)
# define INC_GLOBAL_TIMESTAMP() ATOMIC_SIZE_INC(ruby_vm_global_timestamp)
#else
# define INC_GLOBAL_TIMESTAMP() (++ruby_vm_global_timestamp)
#endif

static VALUE make_no_method_exception(VALUE exc, VALUE format, VALUE obj,
				      int argc, const VALUE *argv, int priv);

static inline struct vm_throw_data *
THROW_DATA_NEW(VALUE val, rb_control_frame_t *cf, VALUE st)
{
    return (struct vm_throw_data *)rb_imemo_new(imemo_throw_data, val, (VALUE)cf, st, 0);
}

static inline void
THROW_DATA_CATCH_FRAME_SET(struct vm_throw_data *obj, const rb_control_frame_t *cfp)
{
    obj->catch_frame = cfp;
}

static inline void
THROW_DATA_STATE_SET(struct vm_throw_data *obj, int st)
{
    obj->throw_state = (VALUE)st;
}

static inline VALUE
THROW_DATA_VAL(const struct vm_throw_data *obj)
{
    return obj->throw_obj;
}

static inline const rb_control_frame_t *
THROW_DATA_CATCH_FRAME(const struct vm_throw_data *obj)
{
    return obj->catch_frame;
}

static int
THROW_DATA_STATE(const struct vm_throw_data *obj)
{
    return (int)obj->throw_state;
}

#define inc_temperature(var) SATURATION_ADD(var, 1)

/* This must be a macro because REG_CFP is a function-static
 * variable.  It is also vital that this macro contains no branches
 * so that your compiler can reorder at will. */
#define PREPARE_FOR_ELIMINATION do { \
    const rb_iseq_t *i	    = GET_ISEQ(); \
    const VALUE *pc	    = GET_PC(); \
    const VALUE *head	    = i->body->iseq_encoded; \
    const int len	    = 1 + OPN_OF_CURRENT_INSN; \
    const int increase	    = STACK_INCREASE_OF_CURRENT_INSN; \
    rb_control_frame_t *cfp = GET_CFP(); \
    cfp->last_insn	    = (typeof(cfp->last_insn)) { \
	.pc		    = (pc - len) - head, \
	.len		    = len, \
	.argc		    = -increase, \
    }; \
} while (0)

#define PREPARE_ELIMINATE_SENDISH(cc) do { \
    if(GET_CURRENT_INSN() != (VALUE)LABEL_PTR(adjuststack)) { \
	/* unable to eliminate */ \
    } \
    else if (! (cc)->me) {  \
	/* method missing */ \
    } \
    else if (cc->temperature < 0) { \
	/* not optimizable */ \
    } \
    else if (inc_temperature(cc->temperature) < 32) { \
	/* temperature too few */ \
    } \
    else if (vm_is_hot(cc)) { \
	PREPARE_FOR_ELIMINATION; \
    } \
} while (0)

#define MOVE_NOP \
    if (GET_OPERAND(-OPN_OF_CURRENT_INSN - 2) == (VALUE)LABEL_PTR(nop)) { \
	iseq_move_nop(GET_ISEQ(), GET_PC(), OPN_OF_CURRENT_INSN + 1);   \
    }

#define TRY_CONSTFOLD(val) \
    if (GET_CFP()->count >= POPN_OF_CURRENT_INSN) { \
        PUSH(val); \
        PUSH(INT2FIX(POPN_OF_CURRENT_INSN)); \
        PUSH(INT2FIX(OPN_OF_CURRENT_INSN)); \
        goto LABEL(opt_constfold); \
    } \
    else { \
        MOVE_NOP; \
    }

#endif /* RUBY_INSNHELPER_H */
