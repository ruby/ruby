/* -*-c-*- */
/**********************************************************************

  vm_exec.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include <math.h>

#if VM_COLLECT_USAGE_DETAILS
static void vm_analysis_insn(int insn);
#endif

#if USE_INSNS_COUNTER
static size_t rb_insns_counter[VM_INSTRUCTION_SIZE];

static void
vm_insns_counter_count_insn(int insn)
{
    rb_insns_counter[insn]++;
}

__attribute__((destructor))
static void
vm_insns_counter_show_results_at_exit(void)
{
    int insn_end = (ruby_vm_event_enabled_global_flags & ISEQ_TRACE_EVENTS)
        ? VM_INSTRUCTION_SIZE : VM_INSTRUCTION_SIZE / 2;

    size_t total = 0;
    for (int insn = 0; insn < insn_end; insn++)
        total += rb_insns_counter[insn];

    for (int insn = 0; insn < insn_end; insn++) {
        fprintf(stderr, "[RUBY_INSNS_COUNTER]\t%-32s%'12"PRIuSIZE" (%4.1f%%)\n",
                insn_name(insn), rb_insns_counter[insn],
                100.0 * rb_insns_counter[insn] / total);
    }
}
#else
static void vm_insns_counter_count_insn(int insn) {}
#endif

#if VMDEBUG > 0
#define DECL_SC_REG(type, r, reg) register type reg_##r

#elif defined(__GNUC__) && defined(__x86_64__)
#define DECL_SC_REG(type, r, reg) register type reg_##r __asm__("r" reg)

#elif defined(__GNUC__) && defined(__i386__)
#define DECL_SC_REG(type, r, reg) register type reg_##r __asm__("e" reg)

#elif defined(__GNUC__) && defined(__powerpc64__)
#define DECL_SC_REG(type, r, reg) register type reg_##r __asm__("r" reg)

#else
#define DECL_SC_REG(type, r, reg) register type reg_##r
#endif
/* #define DECL_SC_REG(r, reg) VALUE reg_##r */

#if !OPT_CALL_THREADED_CODE
static VALUE
vm_exec_core(rb_execution_context_t *ec, VALUE initial)
{

#if OPT_STACK_CACHING
#if 0
#elif __GNUC__ && __x86_64__
    DECL_SC_REG(VALUE, a, "12");
    DECL_SC_REG(VALUE, b, "13");
#else
    register VALUE reg_a;
    register VALUE reg_b;
#endif
#endif

#if defined(__GNUC__) && defined(__i386__)
    DECL_SC_REG(const VALUE *, pc, "di");
    DECL_SC_REG(rb_control_frame_t *, cfp, "si");
#define USE_MACHINE_REGS 1

#elif defined(__GNUC__) && defined(__x86_64__)
    DECL_SC_REG(const VALUE *, pc, "14");
    DECL_SC_REG(rb_control_frame_t *, cfp, "15");
#define USE_MACHINE_REGS 1

#elif defined(__GNUC__) && defined(__powerpc64__)
    DECL_SC_REG(const VALUE *, pc, "14");
    DECL_SC_REG(rb_control_frame_t *, cfp, "15");
#define USE_MACHINE_REGS 1

#else
    register rb_control_frame_t *reg_cfp;
    const VALUE *reg_pc;
#endif

#if USE_MACHINE_REGS

#undef  RESTORE_REGS
#define RESTORE_REGS() \
{ \
  VM_REG_CFP = ec->cfp; \
  reg_pc  = reg_cfp->pc; \
}

#undef  VM_REG_PC
#define VM_REG_PC reg_pc
#undef  GET_PC
#define GET_PC() (reg_pc)
#undef  SET_PC
#define SET_PC(x) (reg_cfp->pc = VM_REG_PC = (x))
#endif

#if OPT_TOKEN_THREADED_CODE || OPT_DIRECT_THREADED_CODE
#include "vmtc.inc"
    if (UNLIKELY(ec == 0)) {
	return (VALUE)insns_address_table;
    }
#endif
    reg_cfp = ec->cfp;
    reg_pc = reg_cfp->pc;

#if OPT_STACK_CACHING
    reg_a = initial;
    reg_b = 0;
#endif

  first:
    INSN_DISPATCH();
/*****************/
 #include "vm.inc"
/*****************/
    END_INSNS_DISPATCH();

    /* unreachable */
    rb_bug("vm_eval: unreachable");
    goto first;
}

const void **
rb_vm_get_insns_address_table(void)
{
    return (const void **)vm_exec_core(0, 0);
}

#else /* OPT_CALL_THREADED_CODE */

#include "vm.inc"
#include "vmtc.inc"

const void **
rb_vm_get_insns_address_table(void)
{
    return (const void **)insns_address_table;
}

static VALUE
vm_exec_core(rb_execution_context_t *ec, VALUE initial)
{
    register rb_control_frame_t *reg_cfp = ec->cfp;
    rb_thread_t *th;

    while (1) {
	reg_cfp = ((rb_insn_func_t) (*GET_PC()))(ec, reg_cfp);

	if (UNLIKELY(reg_cfp == 0)) {
	    break;
	}
    }

    if ((th = rb_ec_thread_ptr(ec))->retval != Qundef) {
	VALUE ret = th->retval;
	th->retval = Qundef;
	return ret;
    }
    else {
	VALUE err = ec->errinfo;
	ec->errinfo = Qnil;
	return err;
    }
}
#endif
