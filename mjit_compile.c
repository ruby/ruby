/**********************************************************************

  mjit_compile.c - MRI method JIT compiler

  Copyright (C) 2017 Takashi Kokubun <takashikkbn@gmail.com>.

**********************************************************************/

/* NOTE: All functions in this file are executed on MJIT worker. So don't
   call Ruby methods (C functions that may call rb_funcall) or trigger
   GC (using ZALLOC, xmalloc, xfree, etc.) in this file. */

#include "internal.h"

#if USE_MJIT

#include "vm_core.h"
#include "vm_exec.h"
#include "mjit.h"
#include "insns.inc"
#include "insns_info.inc"
#include "vm_insnhelper.h"

/* Macros to check if a position is already compiled using compile_status.stack_size_for_pos */
#define NOT_COMPILED_STACK_SIZE -1
#define ALREADY_COMPILED_P(status, pos) (status->stack_size_for_pos[pos] != NOT_COMPILED_STACK_SIZE)

/* Storage to keep compiler's status.  This should have information
   which is global during one `mjit_compile` call.  Ones conditional
   in each branch should be stored in `compile_branch`.  */
struct compile_status {
    bool success; // has true if compilation has had no issue
    int *stack_size_for_pos; // stack_size_for_pos[pos] has stack size for the position (otherwise -1)
    // If true, JIT-ed code will use local variables to store pushed values instead of
    // using VM's stack and moving stack pointer.
    bool local_stack_p;
    // Safely-accessible cache entries copied from main thread.
    union iseq_inline_storage_entry *is_entries;
    struct rb_call_cache *cc_entries;
};

/* Storage to keep data which is consistent in each conditional branch.
   This is created and used for one `compile_insns` call and its values
   should be copied for extra `compile_insns` call. */
struct compile_branch {
    unsigned int stack_size; // this simulates sp (stack pointer) of YARV
    bool finish_p; // if true, compilation in this branch should stop and let another branch to be compiled
};

struct case_dispatch_var {
    FILE *f;
    unsigned int base_pos;
    VALUE last_value;
};

// Returns true if call cache is still not obsoleted and cc->me->def->type is available.
static bool
has_valid_method_type(CALL_CACHE cc)
{
    extern bool mjit_valid_class_serial_p(rb_serial_t class_serial);
    return GET_GLOBAL_METHOD_STATE() == cc->method_state
        && mjit_valid_class_serial_p(cc->class_serial) && cc->me;
}

// Returns true if iseq is inlinable, otherwise NULL. This becomes true in the same condition
// as CC_SET_FASTPATH (in vm_callee_setup_arg) is called from vm_call_iseq_setup.
static bool
inlinable_iseq_p(const CALL_INFO ci, const CALL_CACHE cc, const rb_iseq_t *iseq)
{
    extern bool rb_simple_iseq_p(const rb_iseq_t *iseq);
    return iseq != NULL
        && !(ci->flag & VM_CALL_KW_SPLAT) && rb_simple_iseq_p(iseq) // Top of vm_callee_setup_arg. In this case, opt_pc is 0.
        && ci->orig_argc == iseq->body->param.lead_num // exclude argument_arity_error (assumption: `calling->argc == ci->orig_argc` in send insns)
        && vm_call_iseq_optimizable_p(ci, cc); // CC_SET_FASTPATH condition
}

static int
compile_case_dispatch_each(VALUE key, VALUE value, VALUE arg)
{
    struct case_dispatch_var *var = (struct case_dispatch_var *)arg;
    unsigned int offset;

    if (var->last_value != value) {
        offset = FIX2INT(value);
        var->last_value = value;
        fprintf(var->f, "      case %d:\n", offset);
        fprintf(var->f, "        goto label_%d;\n", var->base_pos + offset);
        fprintf(var->f, "        break;\n");
    }
    return ST_CONTINUE;
}

/* Calling rb_id2str in MJIT worker causes random SEGV. So this is disabled by default. */
static void
comment_id(FILE *f, ID id)
{
#ifdef MJIT_COMMENT_ID
    VALUE name = rb_id2str(id);
    const char *p, *e;
    char c, prev = '\0';

    if (!name) return;
    p = RSTRING_PTR(name);
    e = RSTRING_END(name);
    fputs("/* :\"", f);
    for (; p < e; ++p) {
        switch (c = *p) {
          case '*': case '/': if (prev != (c ^ ('/' ^ '*'))) break;
          case '\\': case '"': fputc('\\', f);
        }
        fputc(c, f);
        prev = c;
    }
    fputs("\" */", f);
#endif
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

    /* If next_pos is already compiled and this branch is not finished yet,
       next instruction won't be compiled in C code next and will need `goto`. */
    if (!b->finish_p && next_pos < body->iseq_size && ALREADY_COMPILED_P(status, next_pos)) {
        fprintf(f, "goto label_%d;\n", next_pos);

        /* Verify stack size assumption is the same among multiple branches */
        if ((unsigned int)status->stack_size_for_pos[next_pos] != b->stack_size) {
            if (mjit_opts.warnings || mjit_opts.verbose)
                fprintf(stderr, "MJIT warning: JIT stack assumption is not the same between branches (%d != %u)\n",
                        status->stack_size_for_pos[next_pos], b->stack_size);
            status->success = false;
        }
    }

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
    branch.finish_p = false;

    while (pos < body->iseq_size && !ALREADY_COMPILED_P(status, pos) && !branch.finish_p) {
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
        insn = rb_vm_insn_addr2insn((void *)body->iseq_encoded[pos]);
#else
        insn = (int)body->iseq_encoded[pos];
#endif
        status->stack_size_for_pos[pos] = (int)branch.stack_size;

        fprintf(f, "\nlabel_%d: /* %s */\n", pos, insn_name(insn));
        pos = compile_insn(f, body, insn, body->iseq_encoded + (pos+1), pos, status, &branch);
        if (status->success && branch.stack_size > body->stack_max) {
            if (mjit_opts.warnings || mjit_opts.verbose)
                fprintf(stderr, "MJIT warning: JIT stack size (%d) exceeded its max size (%d)\n", branch.stack_size, body->stack_max);
            status->success = false;
        }
        if (!status->success)
            break;
    }
}

/* Print the block to cancel JIT execution. */
static void
compile_cancel_handler(FILE *f, const struct rb_iseq_constant_body *body, struct compile_status *status)
{
    unsigned int i;
    fprintf(f, "\ncancel:\n");
    if (status->local_stack_p) {
        for (i = 0; i < body->stack_max; i++) {
            fprintf(f, "    *((VALUE *)reg_cfp->bp_ + %d) = stack[%d];\n", i, i);
        }
    }
    fprintf(f, "    return Qundef;\n");
}

extern bool mjit_copy_cache_from_main_thread(const rb_iseq_t *iseq, struct rb_call_cache *cc_entries, union iseq_inline_storage_entry *is_entries);

// Compile ISeq to C code in `f`. It returns true if it succeeds to compile.
bool
mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname)
{
    const struct rb_iseq_constant_body *body = iseq->body;
    struct compile_status status = {
        .success = true,
        .local_stack_p = !body->catch_except_p,
        .stack_size_for_pos = (int *)alloca(sizeof(int) * body->iseq_size),
        .cc_entries = (body->ci_size + body->ci_kw_size) > 0 ?
            alloca(sizeof(struct rb_call_cache) * (body->ci_size + body->ci_kw_size)) : NULL,
        .is_entries = (body->is_size > 0) ?
            alloca(sizeof(union iseq_inline_storage_entry) * body->is_size) : NULL,
    };
    memset(status.stack_size_for_pos, NOT_COMPILED_STACK_SIZE, sizeof(int) * body->iseq_size);
    if ((status.cc_entries != NULL || status.is_entries != NULL)
            && !mjit_copy_cache_from_main_thread(iseq, status.cc_entries, status.is_entries))
        return false;

    /* For performance, we verify stack size only on compilation time (mjit_compile.inc.erb) without --jit-debug */
    if (!mjit_opts.debug) {
        fprintf(f, "#undef OPT_CHECKED_RUN\n");
        fprintf(f, "#define OPT_CHECKED_RUN 0\n\n");
    }

#ifdef _WIN32
    fprintf(f, "__declspec(dllexport)\n");
#endif
    fprintf(f, "VALUE\n%s(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)\n{\n", funcname);
    if (status.local_stack_p) {
        fprintf(f, "    VALUE stack[%d];\n", body->stack_max);
    }
    else {
        fprintf(f, "    VALUE *stack = reg_cfp->sp;\n");
    }
    fprintf(f, "    static const VALUE *const original_body_iseq = (VALUE *)0x%"PRIxVALUE";\n",
            (VALUE)body->iseq_encoded);

    /* Simulate `opt_pc` in setup_parameters_complex. Other PCs which may be passed by catch tables
       are not considered since vm_exec doesn't call mjit_exec for catch tables. */
    if (body->param.flags.has_opt) {
        int i;
        fprintf(f, "\n");
        fprintf(f, "    switch (reg_cfp->pc - reg_cfp->iseq->body->iseq_encoded) {\n");
        for (i = 0; i <= body->param.opt_num; i++) {
            VALUE pc_offset = body->param.opt_table[i];
            fprintf(f, "      case %"PRIdVALUE":\n", pc_offset);
            fprintf(f, "        goto label_%"PRIdVALUE";\n", pc_offset);
        }
        fprintf(f, "    }\n");
    }

    compile_insns(f, body, 0, 0, &status);
    compile_cancel_handler(f, body, &status);
    fprintf(f, "\n} /* end of %s */\n", funcname);
    return status.success;
}

#endif /* USE_MJIT */
