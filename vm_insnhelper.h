/**********************************************************************

  insnhelper.h - helper macros to implement each instructions

  $Author$
  created at: 04/01/01 15:50:34 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifndef RUBY_INSNHELPER_H
#define RUBY_INSNHELPER_H

RUBY_SYMBOL_EXPORT_BEGIN

extern VALUE ruby_vm_const_missing_count;
extern rb_serial_t ruby_vm_global_method_state;
extern rb_serial_t ruby_vm_global_constant_state;
extern rb_serial_t ruby_vm_class_serial;

RUBY_SYMBOL_EXPORT_END

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

static inline int
rb_obj_hidden_p(VALUE obj)
{
    if (SPECIAL_CONST_P(obj)) {
        return FALSE;
    }
    else {
        return RBASIC_CLASS(obj) ? FALSE : TRUE;
    }
}

#define PUSH(x) (VM_ASSERT(!rb_obj_hidden_p(x)), SET_SV(x), INC_SP(1))
#define TOPN(n) (*(GET_SP()-(n)-1))
#define POPN(n) (DEC_SP(n))
#define POP()   (DEC_SP(1))
#define STACK_ADDR_FROM_TOP(n) (GET_SP()-(n))

#define GET_TOS()  (tos)	/* dummy */

/**********************************************************/
/* deal with registers                                    */
/**********************************************************/

#define VM_REG_CFP (reg_cfp)
#define VM_REG_PC  (VM_REG_CFP->pc)
#define VM_REG_SP  (VM_REG_CFP->sp)
#define VM_REG_EP  (VM_REG_CFP->ep)

#define RESTORE_REGS() do { \
    VM_REG_CFP = ec->cfp; \
} while (0)

#define REG_A   reg_a
#define REG_B   reg_b

enum vm_regan_regtype {
    VM_REGAN_PC = 0,
    VM_REGAN_SP = 1,
    VM_REGAN_EP = 2,
    VM_REGAN_CFP = 3,
    VM_REGAN_SELF = 4,
    VM_REGAN_ISEQ = 5
};
enum vm_regan_acttype {
    VM_REGAN_ACT_GET = 0,
    VM_REGAN_ACT_SET = 1
};

#if VM_COLLECT_USAGE_DETAILS
#define COLLECT_USAGE_REGISTER_HELPER(a, b, v) \
  (COLLECT_USAGE_REGISTER((VM_REGAN_##a), (VM_REGAN_ACT_##b)), (v))
#else
#define COLLECT_USAGE_REGISTER_HELPER(a, b, v) (v)
#endif

/* PC */
#define GET_PC()           (COLLECT_USAGE_REGISTER_HELPER(PC, GET, VM_REG_PC))
#define SET_PC(x)          (VM_REG_PC = (COLLECT_USAGE_REGISTER_HELPER(PC, SET, (x))))
#define GET_CURRENT_INSN() (*GET_PC())
#define GET_OPERAND(n)     (GET_PC()[(n)])
#define ADD_PC(n)          (SET_PC(VM_REG_PC + (n)))
#define JUMP(dst)          (SET_PC(VM_REG_PC + (dst)))

/* frame pointer, environment pointer */
#define GET_CFP()  (COLLECT_USAGE_REGISTER_HELPER(CFP, GET, VM_REG_CFP))
#define GET_EP()   (COLLECT_USAGE_REGISTER_HELPER(EP, GET, VM_REG_EP))
#define SET_EP(x)  (VM_REG_EP = (COLLECT_USAGE_REGISTER_HELPER(EP, SET, (x))))
#define GET_LEP()  (VM_EP_LEP(GET_EP()))

/* SP */
#define GET_SP()   (COLLECT_USAGE_REGISTER_HELPER(SP, GET, VM_REG_SP))
#define SET_SP(x)  (VM_REG_SP  = (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define INC_SP(x)  (VM_REG_SP += (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define DEC_SP(x)  (VM_REG_SP -= (COLLECT_USAGE_REGISTER_HELPER(SP, SET, (x))))
#define SET_SV(x)  (*GET_SP() = (x))
  /* set current stack value as x */
#define ADJ_SP(x)  INC_SP(x)

/* instruction sequence C struct */
#define GET_ISEQ() (GET_CFP()->iseq)

/**********************************************************/
/* deal with variables                                    */
/**********************************************************/

#define GET_PREV_EP(ep)                ((VALUE *)((ep)[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03))

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

#ifdef MJIT_HEADER
/* When calling ISeq which may catch an exception from JIT-ed code, we should not call
   mjit_exec directly to prevent the caller frame from being canceled. That's because
   the caller frame may have stack values in the local variables and the cancelling
   the caller frame will purge them. But directly calling mjit_exec is faster... */
#define EXEC_EC_CFP(val) do { \
    if (ec->cfp->iseq->body->catch_except_p) { \
        VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_FINISH); \
        val = vm_exec(ec, TRUE); \
    } \
    else if ((val = mjit_exec(ec)) == Qundef) { \
        VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_FINISH); \
        val = vm_exec(ec, FALSE); \
    } \
} while (0)
#else
/* When calling from VM, longjmp in the callee won't purge any JIT-ed caller frames.
   So it's safe to directly call mjit_exec. */
#define EXEC_EC_CFP(val) do { \
    if ((val = mjit_exec(ec)) == Qundef) { \
        RESTORE_REGS(); \
        NEXT_INSN(); \
    } \
} while (0)
#endif

#define CALL_METHOD(calling, ci, cc) do { \
    VALUE v = (*(cc)->call)(ec, GET_CFP(), (calling), (ci), (cc)); \
    if (v == Qundef) { \
        EXEC_EC_CFP(val); \
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

#define GET_BLOCK_HANDLER() (GET_LEP()[VM_ENV_DATA_INDEX_SPECVAL])

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
#define FLOAT_HEAP_P(x) (!SPECIAL_CONST_P(x) && RBASIC_CLASS(x) == rb_cFloat)
#define FLOAT_INSTANCE_P(x) (FLONUM_P(x) || FLOAT_HEAP_P(x))

#ifndef USE_IC_FOR_SPECIALIZED_METHOD
#define USE_IC_FOR_SPECIALIZED_METHOD 1
#endif

#define NEXT_CLASS_SERIAL() (++ruby_vm_class_serial)
#define GET_GLOBAL_METHOD_STATE() (ruby_vm_global_method_state)
#define INC_GLOBAL_METHOD_STATE() (++ruby_vm_global_method_state)
#define GET_GLOBAL_CONSTANT_STATE() (ruby_vm_global_constant_state)
#define INC_GLOBAL_CONSTANT_STATE() (++ruby_vm_global_constant_state)

extern rb_method_definition_t *rb_method_definition_create(rb_method_type_t type, ID mid);
extern void rb_method_definition_set(const rb_method_entry_t *me, rb_method_definition_t *def, void *opts);
extern int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);

extern VALUE rb_make_no_method_exception(VALUE exc, VALUE format, VALUE obj,
					 int argc, const VALUE *argv, int priv);

static inline struct vm_throw_data *
THROW_DATA_NEW(VALUE val, const rb_control_frame_t *cf, VALUE st)
{
    return (struct vm_throw_data *)rb_imemo_new(imemo_throw_data, val, (VALUE)cf, st, 0);
}

static inline VALUE
THROW_DATA_VAL(const struct vm_throw_data *obj)
{
    VM_ASSERT(THROW_DATA_P(obj));
    return obj->throw_obj;
}

static inline const rb_control_frame_t *
THROW_DATA_CATCH_FRAME(const struct vm_throw_data *obj)
{
    VM_ASSERT(THROW_DATA_P(obj));
    return obj->catch_frame;
}

static inline int
THROW_DATA_STATE(const struct vm_throw_data *obj)
{
    VM_ASSERT(THROW_DATA_P(obj));
    return (int)obj->throw_state;
}

static inline int
THROW_DATA_CONSUMED_P(const struct vm_throw_data *obj)
{
    VM_ASSERT(THROW_DATA_P(obj));
    return obj->flags & THROW_DATA_CONSUMED;
}

static inline void
THROW_DATA_CATCH_FRAME_SET(struct vm_throw_data *obj, const rb_control_frame_t *cfp)
{
    VM_ASSERT(THROW_DATA_P(obj));
    obj->catch_frame = cfp;
}

static inline void
THROW_DATA_STATE_SET(struct vm_throw_data *obj, int st)
{
    VM_ASSERT(THROW_DATA_P(obj));
    obj->throw_state = (VALUE)st;
}

static inline void
THROW_DATA_CONSUMED_SET(struct vm_throw_data *obj)
{
    if (THROW_DATA_P(obj) &&
	THROW_DATA_STATE(obj) == TAG_BREAK) {
	obj->flags |= THROW_DATA_CONSUMED;
    }
}

#define IS_ARGS_SPLAT(ci)   ((ci)->flag & VM_CALL_ARGS_SPLAT)
#define IS_ARGS_KEYWORD(ci) ((ci)->flag & VM_CALL_KWARG)

#define CALLER_SETUP_ARG(cfp, calling, ci) do { \
    if (UNLIKELY(IS_ARGS_SPLAT(ci))) vm_caller_setup_arg_splat((cfp), (calling)); \
    if (UNLIKELY(IS_ARGS_KEYWORD(ci))) vm_caller_setup_arg_kw((cfp), (calling), (ci)); \
} while (0)

#endif /* RUBY_INSNHELPER_H */
