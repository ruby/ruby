/**********************************************************************

  vm.h -

  $Author$
  created at: 04/01/01 16:56:59 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#ifndef RUBY_VM_H
#define RUBY_VM_H

typedef long OFFSET;
typedef unsigned long lindex_t;
typedef unsigned long dindex_t;
typedef rb_num_t GENTRY;
typedef rb_iseq_t *ISEQ;

extern VALUE rb_cEnv;
extern VALUE ruby_vm_global_state_version;
extern VALUE ruby_vm_redefined_flag;


/**
 * VM Debug Level
 *
 * debug level:
 *  0: no debug output
 *  1: show instruction name
 *  2: show stack frame when control stack frame is changed
 *  3: show stack status
 *  4: show register
 *  5:
 * 10: gc check
 */


#ifndef VMDEBUG
#define VMDEBUG 0
#endif

#if 0
#undef  VMDEBUG
#define VMDEBUG 3
#endif

#ifdef  COLLECT_USAGE_ANALYSIS
#define USAGE_ANALYSIS_INSN(insn)           vm_analysis_insn(insn)
#define USAGE_ANALYSIS_OPERAND(insn, n, op) vm_analysis_operand(insn, n, (VALUE)op)
#define USAGE_ANALYSIS_REGISTER(reg, s)     vm_analysis_register(reg, s)
#else
#define USAGE_ANALYSIS_INSN(insn)		/* none */
#define USAGE_ANALYSIS_OPERAND(insn, n, op)	/* none */
#define USAGE_ANALYSIS_REGISTER(reg, s)		/* none */
#endif

#ifdef __GCC__
/* TODO: machine dependent prefetch instruction */
#define PREFETCH(pc)
#else
#define PREFETCH(pc)
#endif

#if VMDEBUG > 0
#define debugs printf
#define DEBUG_ENTER_INSN(insn) \
  debug_print_pre(th, GET_CFP());

#if OPT_STACK_CACHING
#define SC_REGS() , reg_a, reg_b
#else
#define SC_REGS()
#endif

#define DEBUG_END_INSN() \
  debug_print_post(th, GET_CFP() SC_REGS());

#else

#define debugs
#define DEBUG_ENTER_INSN(insn)
#define DEBUG_END_INSN()
#endif

#define throwdebug if(0)printf
/* #define throwdebug printf */

#define SDR2(cfp) vm_stack_dump_raw(GET_THREAD(), (cfp))


/************************************************/
#if   DISPATCH_XXX
error !
/************************************************/
#elif OPT_CALL_THREADED_CODE

#define LABEL(x)  insn_func_##x
#define ELABEL(x)
#define LABEL_PTR(x) &LABEL(x)

#define INSN_ENTRY(insn) \
  static rb_control_frame_t * \
    FUNC_FASTCALL(LABEL(insn))(rb_thread_t *th, rb_control_frame_t *reg_cfp) {

#define END_INSN(insn) return reg_cfp;}

#define NEXT_INSN() return reg_cfp;

/************************************************/
#elif OPT_TOKEN_THREADED_CODE || OPT_DIRECT_THREADED_CODE
/* threaded code with gcc */

#define LABEL(x)  INSN_LABEL_##x
#define ELABEL(x) INSN_ELABEL_##x
#define LABEL_PTR(x) &&LABEL(x)

#define INSN_ENTRY_SIG(insn)


#define INSN_DISPATCH_SIG(insn)

#define INSN_ENTRY(insn) \
  LABEL(insn): \
  INSN_ENTRY_SIG(insn); \

/* dispather */
#if __GNUC__ && (__i386__ || __x86_64__) && __GNUC__ == 3
#define DISPATCH_ARCH_DEPEND_WAY(addr) \
  asm volatile("jmp *%0;\t# -- inseted by vm.h\t[length = 2]" : : "r" (addr))

#else
#define DISPATCH_ARCH_DEPEND_WAY(addr) \
				/* do nothing */

#endif


/**********************************/
#if OPT_DIRECT_THREADED_CODE

/* for GCC 3.4.x */
#define TC_DISPATCH(insn) \
  INSN_DISPATCH_SIG(insn); \
  goto *GET_CURRENT_INSN(); \
  ;

#else
/* token threade code */

#define TC_DISPATCH(insn)  \
  DISPATCH_ARCH_DEPEND_WAY(insns_address_table[GET_CURRENT_INSN()]); \
  INSN_DISPATCH_SIG(insn); \
  goto *insns_address_table[GET_CURRENT_INSN()]; \
  rb_bug("tc error");


#endif /* DISPATCH_DIRECT_THREADED_CODE */

#define END_INSN(insn)      \
  DEBUG_END_INSN();         \
  TC_DISPATCH(insn);        \

#define INSN_DISPATCH()     \
  TC_DISPATCH(__START__)    \
  {

#define END_INSNS_DISPATCH()    \
      rb_bug("unknown insn: %ld", GET_CURRENT_INSN());   \
  }   /* end of while loop */   \

#define NEXT_INSN() TC_DISPATCH(__NEXT_INSN__)

/************************************************/
#else /* no threaded code */
/* most common method */

#define INSN_ENTRY(insn) \
case BIN(insn):

#define END_INSN(insn)                        \
  DEBUG_END_INSN();                           \
  break;


#define INSN_DISPATCH()         \
  while(1){                     \
    switch(GET_CURRENT_INSN()){

#define END_INSNS_DISPATCH()    \
default:                        \
  SDR(); \
      rb_bug("unknown insn: %ld", GET_CURRENT_INSN());   \
    } /* end of switch */       \
  }   /* end of while loop */   \

#define NEXT_INSN() goto first

#endif


/************************************************/
/************************************************/

#define VM_CFP_CNT(th, cfp) \
  ((rb_control_frame_t *)(th->stack + th->stack_size) - (rb_control_frame_t *)(cfp))
#define VM_SP_CNT(th, sp) ((sp) - (th)->stack)

/*
  env{
    env[0] // special (block or prev env)
    env[1] // env object
    env[2] // prev env val
  };
 */

#define ENV_IN_HEAP_P(th, env)  \
  (!((th)->stack < (env) && (env) < ((th)->stack + (th)->stack_size)))
#define ENV_VAL(env)        ((env)[1])

#if OPT_CALL_THREADED_CODE
#define THROW_EXCEPTION(exc) do { \
    th->errinfo = (VALUE)(exc); \
    return 0; \
} while (0)
#else
#define THROW_EXCEPTION(exc) return (VALUE)(exc)
#endif

#define SCREG(r) (reg_##r)

/* VM state version */

#define GET_VM_STATE_VERSION() (ruby_vm_global_state_version)
#define INC_VM_STATE_VERSION() \
  (ruby_vm_global_state_version = (ruby_vm_global_state_version+1) & 0x8fffffff)

#define BOP_PLUS     0x01
#define BOP_MINUS    0x02
#define BOP_MULT     0x04
#define BOP_DIV      0x08
#define BOP_MOD      0x10
#define BOP_EQ       0x20
#define BOP_LT       0x40
#define BOP_LE       0x80
#define BOP_LTLT    0x100
#define BOP_AREF    0x200
#define BOP_ASET    0x400
#define BOP_LENGTH  0x800
#define BOP_SUCC   0x1000
#define BOP_GT     0x2000
#define BOP_GE     0x4000
#define BOP_NOT    0x8000
#define BOP_NEQ   0x10000

#endif /* RUBY_VM_H */
