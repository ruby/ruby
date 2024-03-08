#ifndef RUBY_INSNHELPER_H
#define RUBY_INSNHELPER_H
/**********************************************************************

  insnhelper.h - helper macros to implement each instructions

  $Author$
  created at: 04/01/01 15:50:34 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

RUBY_EXTERN VALUE ruby_vm_const_missing_count;
RUBY_EXTERN rb_serial_t ruby_vm_constant_cache_invalidations;
RUBY_EXTERN rb_serial_t ruby_vm_constant_cache_misses;
RUBY_EXTERN rb_serial_t ruby_vm_global_cvar_state;

#if USE_YJIT || USE_RJIT // We want vm_insns_count on any JIT-enabled build.
// Increment vm_insns_count for --yjit-stats. We increment this even when
// --yjit or --yjit-stats is not used because branching to skip it is slower.
// We also don't use ATOMIC_INC for performance, allowing inaccuracy on Ractors.
#define JIT_COLLECT_USAGE_INSN(insn) rb_vm_insns_count++
#else
#define JIT_COLLECT_USAGE_INSN(insn) // none
#endif

#if VM_COLLECT_USAGE_DETAILS
#define COLLECT_USAGE_INSN(insn)           vm_collect_usage_insn(insn)
#define COLLECT_USAGE_OPERAND(insn, n, op) vm_collect_usage_operand((insn), (n), ((VALUE)(op)))
#define COLLECT_USAGE_REGISTER(reg, s)     vm_collect_usage_register((reg), (s))
#else
#define COLLECT_USAGE_INSN(insn)           JIT_COLLECT_USAGE_INSN(insn)
#define COLLECT_USAGE_OPERAND(insn, n, op) // none
#define COLLECT_USAGE_REGISTER(reg, s)     // none
#endif

/**********************************************************/
/* deal with stack                                        */
/**********************************************************/

#define PUSH(x) (SET_SV(x), INC_SP(1))
#define TOPN(n) (*(GET_SP()-(n)-1))
#define POPN(n) (DEC_SP(n))
#define POP()   (DEC_SP(1))
#define STACK_ADDR_FROM_TOP(n) (GET_SP()-(n))

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

#if VM_COLLECT_USAGE_DETAILS
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
#define SET_SV(x)  (*GET_SP() = rb_ractor_confirm_belonging(x))
  /* set current stack value as x */

/* instruction sequence C struct */
#define GET_ISEQ() (GET_CFP()->iseq)

/**********************************************************/
/* deal with variables                                    */
/**********************************************************/

#define GET_PREV_EP(ep)                ((VALUE *)((ep)[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03))

/**********************************************************/
/* deal with values                                       */
/**********************************************************/

#define GET_SELF() (COLLECT_USAGE_REGISTER_HELPER(SELF, GET, GET_CFP()->self))

/**********************************************************/
/* deal with control flow 2: method/iterator              */
/**********************************************************/

/* set fastpath when cached method is *NOT* protected
 * because inline method cache does not care about receiver.
 */

static inline void
CC_SET_FASTPATH(const struct rb_callcache *cc, vm_call_handler func, bool enabled)
{
    if (LIKELY(enabled)) {
        vm_cc_call_set(cc, func);
    }
}

#define GET_BLOCK_HANDLER() (GET_LEP()[VM_ENV_DATA_INDEX_SPECVAL])

/**********************************************************/
/* deal with control flow 3: exception                    */
/**********************************************************/


/**********************************************************/
/* deal with stack canary                                 */
/**********************************************************/

#if VM_CHECK_MODE > 0
#define SETUP_CANARY(cond) \
    VALUE *canary = 0; \
    if (cond) { \
        canary = GET_SP(); \
        SET_SV(vm_stack_canary); \
    } \
    else {\
        SET_SV(Qfalse); /* cleanup */ \
    }
#define CHECK_CANARY(cond, insn) \
    if (cond) { \
        if (*canary == vm_stack_canary) { \
            *canary = Qfalse; /* cleanup */ \
        } \
        else { \
            rb_vm_canary_is_found_dead(insn, *canary); \
        } \
    }
#else
#define SETUP_CANARY(cond)       if (cond) {} else {}
#define CHECK_CANARY(cond, insn) if (cond) {(void)(insn);}
#endif

/**********************************************************/
/* others                                                 */
/**********************************************************/

#define CALL_SIMPLE_METHOD() do { \
    rb_snum_t insn_width = attr_width_opt_send_without_block(0); \
    ADD_PC(-insn_width); \
    DISPATCH_ORIGINAL_INSN(opt_send_without_block); \
} while (0)

#define GET_GLOBAL_CVAR_STATE() (ruby_vm_global_cvar_state)
#define INC_GLOBAL_CVAR_STATE() (++ruby_vm_global_cvar_state)

static inline struct vm_throw_data *
THROW_DATA_NEW(VALUE val, const rb_control_frame_t *cf, int st)
{
    struct vm_throw_data *obj = IMEMO_NEW(struct vm_throw_data, imemo_throw_data, 0);
    *((VALUE *)&obj->throw_obj) = val;
    *((struct rb_control_frame_struct **)&obj->catch_frame) = (struct rb_control_frame_struct *)cf;
    obj->throw_state = st;

    return obj;
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
    return obj->throw_state;
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
    obj->throw_state = st;
}

static inline void
THROW_DATA_CONSUMED_SET(struct vm_throw_data *obj)
{
    if (THROW_DATA_P(obj) &&
        THROW_DATA_STATE(obj) == TAG_BREAK) {
        obj->flags |= THROW_DATA_CONSUMED;
    }
}

#define IS_ARGS_SPLAT(ci)          (vm_ci_flag(ci) & VM_CALL_ARGS_SPLAT)
#define IS_ARGS_KEYWORD(ci)        (vm_ci_flag(ci) & VM_CALL_KWARG)
#define IS_ARGS_KW_SPLAT(ci)       (vm_ci_flag(ci) & VM_CALL_KW_SPLAT)
#define IS_ARGS_KW_OR_KW_SPLAT(ci) (vm_ci_flag(ci) & (VM_CALL_KWARG | VM_CALL_KW_SPLAT))
#define IS_ARGS_KW_SPLAT_MUT(ci)   (vm_ci_flag(ci) & VM_CALL_KW_SPLAT_MUT)

static inline bool
vm_call_cacheable(const struct rb_callinfo *ci, const struct rb_callcache *cc)
{
    return (vm_ci_flag(ci) & VM_CALL_FCALL) ||
        METHOD_ENTRY_VISI(vm_cc_cme(cc)) != METHOD_VISI_PROTECTED;
}
/* If this returns true, an optimized function returned by `vm_call_iseq_setup_func`
   can be used as a fastpath. */
static inline bool
vm_call_iseq_optimizable_p(const struct rb_callinfo *ci, const struct rb_callcache *cc)
{
    return !IS_ARGS_SPLAT(ci) && !IS_ARGS_KEYWORD(ci) && vm_call_cacheable(ci, cc);
}

#endif /* RUBY_INSNHELPER_H */
