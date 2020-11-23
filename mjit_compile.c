/**********************************************************************

  mjit_compile.c - MRI method JIT compiler

  Copyright (C) 2017 Takashi Kokubun <takashikkbn@gmail.com>.

**********************************************************************/

// NOTE: All functions in this file are executed on MJIT worker. So don't
// call Ruby methods (C functions that may call rb_funcall) or trigger
// GC (using ZALLOC, xmalloc, xfree, etc.) in this file.

#include "ruby/internal/config.h" // defines USE_MJIT

#if USE_MJIT

#include "internal.h"
#include "internal/compile.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/variable.h"
#include "mjit.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "vm_exec.h"
#include "vm_insnhelper.h"

#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"

// Macros to check if a position is already compiled using compile_status.stack_size_for_pos
#define NOT_COMPILED_STACK_SIZE -1
#define ALREADY_COMPILED_P(status, pos) (status->stack_size_for_pos[pos] != NOT_COMPILED_STACK_SIZE)

// Storage to keep compiler's status.  This should have information
// which is global during one `mjit_compile` call.  Ones conditional
// in each branch should be stored in `compile_branch`.
struct compile_status {
    bool success; // has true if compilation has had no issue
    int *stack_size_for_pos; // stack_size_for_pos[pos] has stack size for the position (otherwise -1)
    // If true, JIT-ed code will use local variables to store pushed values instead of
    // using VM's stack and moving stack pointer.
    bool local_stack_p;
    // Safely-accessible ivar cache entries copied from main thread.
    union iseq_inline_storage_entry *is_entries;
    // Index of call cache entries captured to compiled_iseq to be marked on GC
    int cc_entries_index;
    // Mutated optimization levels
    struct rb_mjit_compile_info *compile_info;
    bool merge_ivar_guards_p; // If true, merge guards of ivar accesses
    rb_serial_t ivar_serial; // ic_serial of IVC in is_entries (used only when merge_ivar_guards_p)
    size_t max_ivar_index; // Max IVC index in is_entries (used only when merge_ivar_guards_p)
};

// Storage to keep data which is consistent in each conditional branch.
// This is created and used for one `compile_insns` call and its values
// should be copied for extra `compile_insns` call.
struct compile_branch {
    unsigned int stack_size; // this simulates sp (stack pointer) of YARV
    bool finish_p; // if true, compilation in this branch should stop and let another branch to be compiled
};

struct case_dispatch_var {
    FILE *f;
    unsigned int base_pos;
    VALUE last_value;
};

static size_t
call_data_index(CALL_DATA cd, const struct rb_iseq_constant_body *body)
{
    return cd - body->call_data;
}

const struct rb_callcache ** mjit_iseq_cc_entries(const struct rb_iseq_constant_body *const body);

// Using this function to refer to cc_entries allocated by `mjit_capture_cc_entries`
// instead of storing cc_entries in status directly so that we always refer to a new address
// returned by `realloc` inside it.
static const struct rb_callcache **
captured_cc_entries(const struct rb_iseq_constant_body *const body, const struct compile_status *status)
{
    VM_ASSERT(status->cc_entries_index != -1);
    return mjit_iseq_cc_entries(body) + status->cc_entries_index;
}

// Returns true if call cache is still not obsoleted and vm_cc_cme(cc)->def->type is available.
static bool
has_valid_method_type(CALL_CACHE cc)
{
    return vm_cc_cme(cc) != NULL;
}

// Returns true if MJIT thinks this cc's opt_* insn may fallback to opt_send_without_block.
static bool
has_cache_for_send(CALL_CACHE cc, int insn)
{
    extern bool rb_vm_opt_cfunc_p(CALL_CACHE cc, int insn);
    return has_valid_method_type(cc) &&
        !(vm_cc_cme(cc)->def->type == VM_METHOD_TYPE_CFUNC && rb_vm_opt_cfunc_p(cc, insn));
}

// Returns true if iseq can use fastpath for setup, otherwise NULL. This becomes true in the same condition
// as CC_SET_FASTPATH (in vm_callee_setup_arg) is called from vm_call_iseq_setup.
static bool
fastpath_applied_iseq_p(const CALL_INFO ci, const CALL_CACHE cc, const rb_iseq_t *iseq)
{
    extern bool rb_simple_iseq_p(const rb_iseq_t *iseq);
    return iseq != NULL
        && !(vm_ci_flag(ci) & VM_CALL_KW_SPLAT) && rb_simple_iseq_p(iseq) // Top of vm_callee_setup_arg. In this case, opt_pc is 0.
        && vm_ci_argc(ci) == (unsigned int)iseq->body->param.lead_num // exclude argument_arity_error (assumption: `calling->argc == ci->orig_argc` in send insns)
        && vm_call_iseq_optimizable_p(ci, cc); // CC_SET_FASTPATH condition
}

// Return true if an object of the klass may be a special const. See: rb_class_of
static bool
maybe_special_const_class_p(const VALUE klass)
{
    return klass == rb_cFalseClass
        || klass == rb_cNilClass
        || klass == rb_cTrueClass
        || klass == rb_cInteger
        || klass == rb_cSymbol
        || klass == rb_cFloat;
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

// Calling rb_id2str in MJIT worker causes random SEGV. So this is disabled by default.
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

// Main function of JIT compilation, vm_exec_core counterpart for JIT. Compile one insn to `f`, may modify
// b->stack_size and return next position.
//
// When you add a new instruction to insns.def, it would be nice to have JIT compilation support here but
// it's optional. This JIT compiler just ignores ISeq which includes unknown instruction, and ISeq which
// does not have it can be compiled as usual.
static unsigned int
compile_insn(FILE *f, const struct rb_iseq_constant_body *body, const int insn, const VALUE *operands,
             const unsigned int pos, struct compile_status *status, struct compile_branch *b)
{
    unsigned int next_pos = pos + insn_len(insn);

/*****************/
 #include "mjit_compile.inc"
/*****************/

    // If next_pos is already compiled and this branch is not finished yet,
    // next instruction won't be compiled in C code next and will need `goto`.
    if (!b->finish_p && next_pos < body->iseq_size && ALREADY_COMPILED_P(status, next_pos)) {
        fprintf(f, "goto label_%d;\n", next_pos);

        // Verify stack size assumption is the same among multiple branches
        if ((unsigned int)status->stack_size_for_pos[next_pos] != b->stack_size) {
            if (mjit_opts.warnings || mjit_opts.verbose)
                fprintf(stderr, "MJIT warning: JIT stack assumption is not the same between branches (%d != %u)\n",
                        status->stack_size_for_pos[next_pos], b->stack_size);
            status->success = false;
        }
    }

    return next_pos;
}

// Compile one conditional branch.  If it has branchXXX insn, this should be
// called multiple times for each branch.
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

// Print the block to cancel JIT execution.
static void
compile_cancel_handler(FILE *f, const struct rb_iseq_constant_body *body, struct compile_status *status)
{
    fprintf(f, "\nsend_cancel:\n");
    fprintf(f, "    RB_DEBUG_COUNTER_INC(mjit_cancel_send_inline);\n");
    fprintf(f, "    rb_mjit_recompile_send(original_iseq);\n");
    fprintf(f, "    goto cancel;\n");

    fprintf(f, "\nivar_cancel:\n");
    fprintf(f, "    RB_DEBUG_COUNTER_INC(mjit_cancel_ivar_inline);\n");
    fprintf(f, "    rb_mjit_recompile_ivar(original_iseq);\n");
    fprintf(f, "    goto cancel;\n");

    fprintf(f, "\nexivar_cancel:\n");
    fprintf(f, "    RB_DEBUG_COUNTER_INC(mjit_cancel_exivar_inline);\n");
    fprintf(f, "    rb_mjit_recompile_exivar(original_iseq);\n");
    fprintf(f, "    goto cancel;\n");

    fprintf(f, "\ncancel:\n");
    fprintf(f, "    RB_DEBUG_COUNTER_INC(mjit_cancel);\n");
    if (status->local_stack_p) {
        for (unsigned int i = 0; i < body->stack_max; i++) {
            fprintf(f, "    *(vm_base_ptr(reg_cfp) + %d) = stack[%d];\n", i, i);
        }
    }
    fprintf(f, "    return Qundef;\n");
}

extern int mjit_capture_cc_entries(const struct rb_iseq_constant_body *captured_iseq);

// Copy current is_entries and use it throughout the current compilation consistently.
// While ic->entry has been immutable since https://github.com/ruby/ruby/pull/3662,
// we still need this to avoid a race condition between entries and ivar_serial/max_ivar_index.
static void
mjit_capture_is_entries(const struct rb_iseq_constant_body *body, union iseq_inline_storage_entry *is_entries)
{
    if (is_entries == NULL)
        return;
    memcpy(is_entries, body->is_entries, sizeof(union iseq_inline_storage_entry) * body->is_size);
}

static bool
mjit_compile_body(FILE *f, const rb_iseq_t *iseq, struct compile_status *status)
{
    const struct rb_iseq_constant_body *body = iseq->body;
    status->success = true;
    status->local_stack_p = !body->catch_except_p;

    if (status->local_stack_p) {
        fprintf(f, "    VALUE stack[%d];\n", body->stack_max);
    }
    else {
        fprintf(f, "    VALUE *stack = reg_cfp->sp;\n");
    }
    fprintf(f, "    static const rb_iseq_t *original_iseq = (const rb_iseq_t *)0x%"PRIxVALUE";\n", (VALUE)iseq);
    fprintf(f, "    static const VALUE *const original_body_iseq = (VALUE *)0x%"PRIxVALUE";\n",
            (VALUE)body->iseq_encoded);

    // Generate merged ivar guards first if needed
    if (!status->compile_info->disable_ivar_cache && status->merge_ivar_guards_p) {
        fprintf(f, "    if (UNLIKELY(!(RB_TYPE_P(GET_SELF(), T_OBJECT) && (rb_serial_t)%"PRI_SERIALT_PREFIX"u == RCLASS_SERIAL(RBASIC(GET_SELF())->klass) &&", status->ivar_serial);
        if (status->max_ivar_index >= ROBJECT_EMBED_LEN_MAX) {
            fprintf(f, "%"PRIuSIZE" < ROBJECT_NUMIV(GET_SELF())", status->max_ivar_index); // index < ROBJECT_NUMIV(obj) && !RB_FL_ANY_RAW(obj, ROBJECT_EMBED)
        }
        else {
            fprintf(f, "ROBJECT_EMBED_LEN_MAX == ROBJECT_NUMIV(GET_SELF())"); // index < ROBJECT_NUMIV(obj) && RB_FL_ANY_RAW(obj, ROBJECT_EMBED)
        }
        fprintf(f, "))) {\n");
        fprintf(f, "        goto ivar_cancel;\n");
        fprintf(f, "    }\n");
    }

    // Simulate `opt_pc` in setup_parameters_complex. Other PCs which may be passed by catch tables
    // are not considered since vm_exec doesn't call mjit_exec for catch tables.
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

    compile_insns(f, body, 0, 0, status);
    compile_cancel_handler(f, body, status);
    return status->success;
}

static void
init_ivar_compile_status(const struct rb_iseq_constant_body *body, struct compile_status *status)
{
    mjit_capture_is_entries(body, status->is_entries);

    int num_ivars = 0;
    unsigned int pos = 0;
    status->max_ivar_index = 0;
    status->ivar_serial = 0;

    while (pos < body->iseq_size) {
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
        int insn = rb_vm_insn_addr2insn((void *)body->iseq_encoded[pos]);
#else
        int insn = (int)body->iseq_encoded[pos];
#endif
        if (insn == BIN(getinstancevariable) || insn == BIN(setinstancevariable)) {
            IVC ic = (IVC)body->iseq_encoded[pos+2];
            IVC ic_copy = &(status->is_entries + ((union iseq_inline_storage_entry *)ic - body->is_entries))->iv_cache;
            if (ic_copy->entry) { // Only initialized (ic_serial > 0) IVCs are optimized
                num_ivars++;

                if (status->max_ivar_index < ic_copy->entry->index) {
                    status->max_ivar_index = ic_copy->entry->index;
                }

                if (status->ivar_serial == 0) {
                    status->ivar_serial = ic_copy->entry->class_serial;
                }
                else if (status->ivar_serial != ic_copy->entry->class_serial) {
                    // Multiple classes have used this ISeq. Give up assuming one serial.
                    status->merge_ivar_guards_p = false;
                    return;
                }
            }
        }
        pos += insn_len(insn);
    }
    status->merge_ivar_guards_p = status->ivar_serial > 0 && num_ivars >= 2;
}

// This needs to be macro instead of a function because it's using `alloca`.
#define INIT_COMPILE_STATUS(status, body) do { \
    status = (struct compile_status){ \
        .stack_size_for_pos = (int *)alloca(sizeof(int) * body->iseq_size), \
        .is_entries = (body->is_size > 0) ? \
            alloca(sizeof(union iseq_inline_storage_entry) * body->is_size) : NULL, \
        .cc_entries_index = (body->ci_size > 0) ? \
            mjit_capture_cc_entries(body) : -1, \
        .compile_info = rb_mjit_iseq_compile_info(body) \
    }; \
    memset(status.stack_size_for_pos, NOT_COMPILED_STACK_SIZE, sizeof(int) * body->iseq_size); \
} while (0)

// Compile ISeq to C code in `f`. It returns true if it succeeds to compile.
bool
mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id)
{
    struct compile_status status;
    INIT_COMPILE_STATUS(status, iseq->body);
    if (iseq->body->ci_size > 0 && status.cc_entries_index == -1)
        return false;
    init_ivar_compile_status(iseq->body, &status);

#ifdef _WIN32
    fprintf(f, "__declspec(dllexport)\n");
#endif
    fprintf(f, "VALUE\n%s(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)\n{\n", funcname);
    bool success = mjit_compile_body(f, iseq, &status);
    fprintf(f, "\n} // end of %s\n", funcname);
    return success;
}

#endif // USE_MJIT
