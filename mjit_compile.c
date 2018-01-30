/**********************************************************************

  mjit_compile.c - MRI method JIT compiler

  Copyright (C) 2017 Takashi Kokubun <takashikkbn@gmail.com>.

**********************************************************************/

#include "internal.h"
#include "vm_core.h"
#include "vm_exec.h"
#include "mjit.h"
#include "insns.inc"
#include "insns_info.inc"
#include "vm_insnhelper.h"

/* Storage to keep compiler's status.  This should have information
   which is global during one `mjit_compile` call.  Ones conditional
   in each branch should be stored in `compile_branch`.  */
struct compile_status {
    int success; /* has TRUE if compilation has had no issue */
    int *compiled_for_pos; /* compiled_for_pos[pos] has TRUE if the pos is compiled */
};

/* Storage to keep data which is consistent in each conditional branch.
   This is created and used for one `compile_insns` call and its values
   should be copied for extra `compile_insns` call. */
struct compile_branch {
    unsigned int stack_size; /* this simulates sp (stack pointer) of YARV */
    int finish_p; /* if TRUE, compilation in this branch should stop and let another branch to be compiled */
};

/* Returns iseq from cc if it's available and still not obsoleted. */
static const rb_iseq_t *
get_iseq_if_available(CALL_CACHE cc)
{
    if (GET_GLOBAL_METHOD_STATE() == cc->method_state
        && mjit_valid_class_serial_p(cc->class_serial)
        && cc->me && cc->me->def->type == VM_METHOD_TYPE_ISEQ) {
        return rb_iseq_check(cc->me->def->body.iseq.iseqptr);
    }
    return NULL;
}

/* TODO: move to somewhere shared with vm_args.c */
#define IS_ARGS_SPLAT(ci)   ((ci)->flag & VM_CALL_ARGS_SPLAT)
#define IS_ARGS_KEYWORD(ci) ((ci)->flag & VM_CALL_KWARG)

/* Returns TRUE if iseq is inlinable, otherwise NULL. This becomes TRUE in the same condition
   as CI_SET_FASTPATH (in vm_callee_setup_arg) is called from vm_call_iseq_setup. */
static int
inlinable_iseq_p(CALL_INFO ci, CALL_CACHE cc, const rb_iseq_t *iseq)
{
    extern int simple_iseq_p(const rb_iseq_t *iseq);
    return iseq != NULL
        && simple_iseq_p(iseq) && !(ci->flag & VM_CALL_KW_SPLAT) /* top of vm_callee_setup_arg */
        && (!IS_ARGS_SPLAT(ci) && !IS_ARGS_KEYWORD(ci) && !(METHOD_ENTRY_VISI(cc->me) == METHOD_VISI_PROTECTED)); /* CI_SET_FASTPATH */
}

/* Compiles vm_search_method and CALL_METHOD macro to f. `calling` should be already defined in `f`. */
static void
fprint_call_method(FILE *f, VALUE ci_v, VALUE cc_v, unsigned int result_pos, int inline_p)
{
    const rb_iseq_t *iseq;
    CALL_CACHE cc = (CALL_CACHE)cc_v;

    fprintf(f, "    {\n");
    fprintf(f, "      VALUE v;\n");

    if (inline_p && inlinable_iseq_p((CALL_INFO)ci_v, cc, iseq = get_iseq_if_available(cc))) {
        /* Inline vm_call_iseq_setup_normal for vm_call_iseq_setup_func FASTPATH */
        int param_size = iseq->body->param.size; /* TODO: check calling->argc for argument_arity_error */

        fprintf(f, "      VALUE *argv = reg_cfp->sp - calling.argc;\n");
        fprintf(f, "      reg_cfp->sp = argv - 1;\n"); /* recv */
        fprintf(f, "      vm_push_frame(ec, 0x%"PRIxVALUE", VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL, calling.recv, "
                "calling.block_handler, 0x%"PRIxVALUE", 0x%"PRIxVALUE", argv + %d, %d, %d);\n",
                (VALUE)iseq, (VALUE)cc->me, (VALUE)iseq->body->iseq_encoded, param_size, iseq->body->local_table_size - param_size, iseq->body->stack_max);
        fprintf(f, "      v = Qundef;\n");
    }
    else {
        fprintf(f, "      vm_search_method(0x%"PRIxVALUE", 0x%"PRIxVALUE", calling.recv);\n", ci_v, cc_v);
        fprintf(f, "      v = (*((CALL_CACHE)0x%"PRIxVALUE")->call)(ec, reg_cfp, &calling, 0x%"PRIxVALUE", 0x%"PRIxVALUE");\n", cc_v, ci_v, cc_v);
    }

    fprintf(f, "      if (v == Qundef && (v = mjit_exec(ec)) == Qundef) {\n");
    fprintf(f, "        VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_FINISH);\n"); /* This is vm_call0_body's code after vm_call_iseq_setup */
    fprintf(f, "        stack[%d] = vm_exec(ec);\n", result_pos); /* TODO: don't run mjit_exec inside vm_exec for this case */
    fprintf(f, "      } else {\n");
    fprintf(f, "        stack[%d] = v;\n", result_pos);
    fprintf(f, "      }\n");
    fprintf(f, "    }\n");
}

static void
fprint_opt_call_variables(FILE *f, int insn, unsigned int stack_size, unsigned int argc)
{
    fprintf(f, "    VALUE recv = stack[%d];\n", stack_size - argc);
    if (argc >= 2) {
        fprintf(f, "    VALUE obj = stack[%d];\n", stack_size - (argc - 1));
    }
    if (argc >= 3) {
        fprintf(f, "    VALUE obj2 = stack[%d];\n", stack_size - (argc - 2));
    }
}

static void
fprint_opt_call_fallback(FILE *f, int insn, VALUE ci, VALUE cc, unsigned int result_pos, unsigned int argc, VALUE key)
{
    fprintf(f, "    if (result == Qundef) {\n");
    fprintf(f, "      struct rb_calling_info calling;\n");
    if (key) {
        if (argc == 3) { /* for opt_aset_with, move the position of `val` and put the key */
            fprintf(f, "      *(reg_cfp->sp) = *(reg_cfp->sp - 1);\n");
            fprintf(f, "      *(reg_cfp->sp - 1) = rb_str_resurrect(0x%"PRIxVALUE");\n", key);
            fprintf(f, "      reg_cfp->sp++;\n");
        }
        else { /* for opt_aref_with, just put the key */
            fprintf(f, "      *(reg_cfp->sp++) = rb_str_resurrect(0x%"PRIxVALUE");\n", key);
        }
    }
    /* CALL_SIMPLE_METHOD */
    fprintf(f, "      calling.block_handler = VM_BLOCK_HANDLER_NONE;\n");
    fprintf(f, "      calling.argc = %d;\n", argc - 1); /* -1 is recv */
    fprintf(f, "      calling.recv = recv;\n");
    fprint_call_method(f, ci, cc, result_pos, FALSE);
    fprintf(f, "    } else {\n");
    fprintf(f, "      stack[%d] = result;\n", result_pos);
    fprintf(f, "    }\n");
}

/* Print optimized call with redefinition fallback and return stack size change.
   `format` should call function with `recv`, `obj` and `obj2` depending on `argc`. */
PRINTF_ARGS(static int, 7, 8)
fprint_opt_call(FILE *f, int insn, VALUE ci, VALUE cc, unsigned int stack_size, unsigned int argc, const char *format, ...)
{
    va_list va;

    fprintf(f, "  {\n");
    fprint_opt_call_variables(f, insn, stack_size, argc);

    fprintf(f, "    VALUE result = ");
    va_start(va, format);
    vfprintf(f, format, va);
    va_end(va);
    fprintf(f, ";\n");

    fprint_opt_call_fallback(f, insn, ci, cc, stack_size - argc, argc, (VALUE)0);
    fprintf(f, "  }\n");

    return 1 - argc;
}

/* Same as `fprint_opt_call`, but `key` will be `rb_str_resurrect`ed and pushed. */
PRINTF_ARGS(static int, 8, 9)
fprint_opt_call_with_key(FILE *f, int insn, VALUE ci, VALUE cc, VALUE key, unsigned int stack_size, unsigned int argc, const char *format, ...)
{
    va_list va;

    fprintf(f, "  {\n");
    fprint_opt_call_variables(f, insn, stack_size, argc - 1); /* `-1` for key */

    fprintf(f, "    VALUE result = ");
    va_start(va, format);
    vfprintf(f, format, va);
    va_end(va);
    fprintf(f, ";\n");

    fprint_opt_call_fallback(f, insn, ci, cc, stack_size - argc + 1, argc, key); /* `+ 1` for key */
    fprintf(f, "  }\n");

    return 2 - argc; /* recv + key = 2 */
}

struct case_dispatch_var {
    FILE *f;
    unsigned int base_pos;
    VALUE last_value;
};

static int
compile_case_dispatch_each(VALUE key, VALUE value, VALUE arg)
{
    struct case_dispatch_var *var = (struct case_dispatch_var *)arg;
    unsigned int offset;

    if (var->last_value != value) {
        offset = FIX2INT(value);
        var->last_value = value;
        fprintf(var->f, "    case %d:\n", offset);
        fprintf(var->f, "      goto label_%d;\n", var->base_pos + offset);
        fprintf(var->f, "      break;\n");
    }
    return ST_CONTINUE;
}

static void compile_insns(FILE *f, const struct rb_iseq_constant_body *body, unsigned int stack_size,
                          unsigned int pos, struct compile_status *status);

/* Main function of JIT compilation, vm_exec_core counterpart for JIT. Compile one insn to `f`, may modify
   b->stack_size and return next position.

   When you add a new instruction to insns.def, it would be nice to have JIT compilation support here but
   it's optional. This JIT compiler just ignores ISeq which includes unknown instruction, and ISeq which
   does not have it can be compiled as usual. */
static unsigned int
compile_insn(FILE *f, const struct rb_iseq_constant_body *body, const int insn, const VALUE *operands,
             const unsigned int pos, struct compile_status *status, struct compile_branch *b)
{
    unsigned int next_pos = pos + insn_len(insn);

/*****************/
 #include "mjit_compile.inc"
/*****************/

    return next_pos;
}

/* Compile one conditional branch.  If it has branchXXX insn, this should be
   called multiple times for each branch.  */
static void
compile_insns(FILE *f, const struct rb_iseq_constant_body *body, unsigned int stack_size,
              unsigned int pos, struct compile_status *status)
{
    int insn;
    struct compile_branch branch;

    branch.stack_size = stack_size;
    branch.finish_p = FALSE;

    while (pos < body->iseq_size && !status->compiled_for_pos[pos] && !branch.finish_p) {
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
        insn = rb_vm_insn_addr2insn((void *)body->iseq_encoded[pos]);
#else
        insn = (int)body->iseq_encoded[pos];
#endif
        status->compiled_for_pos[pos] = TRUE;

        fprintf(f, "\nlabel_%d: /* %s */\n", pos, insn_name(insn));
        pos = compile_insn(f, body, insn, body->iseq_encoded + (pos+1), pos, status, &branch);
        if (status->success && branch.stack_size > body->stack_max) {
            if (mjit_opts.warnings || mjit_opts.verbose)
                fprintf(stderr, "MJIT warning: JIT stack exceeded its max\n");
            status->success = FALSE;
        }
        if (!status->success)
            break;
    }
}

/* Compile ISeq to C code in F.  It returns 1 if it succeeds to compile. */
int
mjit_compile(FILE *f, const struct rb_iseq_constant_body *body, const char *funcname)
{
    struct compile_status status;
    status.success = TRUE;
    status.compiled_for_pos = ZALLOC_N(int, body->iseq_size);

    fprintf(f, "VALUE %s(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp) {\n", funcname);
    fprintf(f, "  VALUE *stack = reg_cfp->sp;\n");

    /* Simulate `opt_pc` in setup_parameters_complex */
    if (body->param.flags.has_opt) {
        int i;
        fprintf(f, "\n");
        fprintf(f, "  switch (reg_cfp->pc - reg_cfp->iseq->body->iseq_encoded) {\n");
        for (i = 0; i <= body->param.opt_num; i++) {
            VALUE pc_offset = body->param.opt_table[i];
            fprintf(f, "    case %"PRIdVALUE":\n", pc_offset);
            fprintf(f, "      goto label_%"PRIdVALUE";\n", pc_offset);
        }
        fprintf(f, "  }\n");
    }

    /* ISeq might be used for catch table too. For that usage, this code cancels JIT execution. */
    fprintf(f, "  if (reg_cfp->pc != 0x%"PRIxVALUE") {\n", (VALUE)body->iseq_encoded);
    fprintf(f, "    return Qundef;\n");
    fprintf(f, "  }\n");

    compile_insns(f, body, 0, 0, &status);
    fprintf(f, "}\n");

    xfree(status.compiled_for_pos);
    return status.success;
}
