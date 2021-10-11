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

// For propagating information needed for lazily pushing a frame.
struct inlined_call_context {
    int orig_argc; // ci->orig_argc
    VALUE me; // vm_cc_cme(cc)
    int param_size; // def_iseq_ptr(vm_cc_cme(cc)->def)->body->param.size
    int local_size; // def_iseq_ptr(vm_cc_cme(cc)->def)->body->local_table_size
};

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
    // A pointer to root (i.e. not inlined) iseq being compiled.
    const struct rb_iseq_constant_body *compiled_iseq;
    int compiled_id; // Just a copy of compiled_iseq->jit_unit->id
    // Mutated optimization levels
    struct rb_mjit_compile_info *compile_info;
    bool merge_ivar_guards_p; // If true, merge guards of ivar accesses
    rb_serial_t ivar_serial; // ic_serial of IVC in is_entries (used only when merge_ivar_guards_p)
    size_t max_ivar_index; // Max IVC index in is_entries (used only when merge_ivar_guards_p)
    // If `inlined_iseqs[pos]` is not NULL, `mjit_compile_body` tries to inline ISeq there.
    const struct rb_iseq_constant_body **inlined_iseqs;
    struct inlined_call_context inline_context;
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
captured_cc_entries(const struct compile_status *status)
{
    VM_ASSERT(status->cc_entries_index != -1);
    return mjit_iseq_cc_entries(status->compiled_iseq) + status->cc_entries_index;
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
    struct compile_branch branch;

    branch.stack_size = stack_size;
    branch.finish_p = false;

    while (pos < body->iseq_size && !ALREADY_COMPILED_P(status, pos) && !branch.finish_p) {
        int insn = rb_vm_insn_decode(body->iseq_encoded[pos]);
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

// Print the block to cancel inlined method call. It's supporting only `opt_send_without_block` for now.
static void
compile_inlined_cancel_handler(FILE *f, const struct rb_iseq_constant_body *body, struct inlined_call_context *inline_context)
{
    fprintf(f, "\ncancel:\n");
    fprintf(f, "    RB_DEBUG_COUNTER_INC(mjit_cancel);\n");
    fprintf(f, "    rb_mjit_recompile_inlining(original_iseq);\n");

    // Swap pc/sp set on cancel with original pc/sp.
    fprintf(f, "    const VALUE *current_pc = reg_cfp->pc;\n");
    fprintf(f, "    VALUE *current_sp = reg_cfp->sp;\n");
    fprintf(f, "    reg_cfp->pc = orig_pc;\n");
    fprintf(f, "    reg_cfp->sp = orig_sp;\n\n");

    // Lazily push the current call frame.
    fprintf(f, "    struct rb_calling_info calling;\n");
    fprintf(f, "    calling.block_handler = VM_BLOCK_HANDLER_NONE;\n"); // assumes `opt_send_without_block`
    fprintf(f, "    calling.argc = %d;\n", inline_context->orig_argc);
    fprintf(f, "    calling.recv = reg_cfp->self;\n");
    fprintf(f, "    reg_cfp->self = orig_self;\n");
    fprintf(f, "    vm_call_iseq_setup_normal(ec, reg_cfp, &calling, (const rb_callable_method_entry_t *)0x%"PRIxVALUE", 0, %d, %d);\n\n",
            inline_context->me, inline_context->param_size, inline_context->local_size); // fastpath_applied_iseq_p checks rb_simple_iseq_p, which ensures has_opt == FALSE

    // Start usual cancel from here.
    fprintf(f, "    reg_cfp = ec->cfp;\n"); // work on the new frame
    fprintf(f, "    reg_cfp->pc = current_pc;\n");
    fprintf(f, "    reg_cfp->sp = current_sp;\n");
    for (unsigned int i = 0; i < body->stack_max; i++) { // should be always `status->local_stack_p`
        fprintf(f, "    *(vm_base_ptr(reg_cfp) + %d) = stack[%d];\n", i, i);
    }
    // We're not just returning Qundef here so that caller's normal cancel handler can
    // push back `stack` to `cfp->sp`.
    fprintf(f, "    return vm_exec(ec, false);\n");
}

// Print the block to cancel JIT execution.
static void
compile_cancel_handler(FILE *f, const struct rb_iseq_constant_body *body, struct compile_status *status)
{
    if (status->inlined_iseqs == NULL) { // the current ISeq is being inlined
        compile_inlined_cancel_handler(f, body, &status->inline_context);
        return;
    }

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

    fprintf(f, "\nconst_cancel:\n");
    fprintf(f, "    rb_mjit_recompile_const(original_iseq);\n");
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

extern int
mjit_capture_cc_entries(const struct rb_iseq_constant_body *compiled_iseq, const struct rb_iseq_constant_body *captured_iseq);

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
    if (status->inlined_iseqs != NULL) // i.e. compile root
        fprintf(f, "    static const rb_iseq_t *original_iseq = (const rb_iseq_t *)0x%"PRIxVALUE";\n", (VALUE)iseq);
    fprintf(f, "    static const VALUE *const original_body_iseq = (VALUE *)0x%"PRIxVALUE";\n",
            (VALUE)body->iseq_encoded);
    fprintf(f, "    VALUE cfp_self = reg_cfp->self;\n"); // cache self across the method
    fprintf(f, "#undef GET_SELF\n");
    fprintf(f, "#define GET_SELF() cfp_self\n");

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
    fprintf(f, "#undef GET_SELF");
    return status->success;
}

// Return true if the ISeq can be inlined without pushing a new control frame.
static bool
inlinable_iseq_p(const struct rb_iseq_constant_body *body)
{
    // 1) If catch_except_p, caller frame should be preserved when callee catches an exception.
    // Then we need to wrap `vm_exec()` but then we can't inline the call inside it.
    //
    // 2) If `body->catch_except_p` is false and `handles_sp?` of an insn is false,
    // sp is not moved as we assume `status->local_stack_p = !body->catch_except_p`.
    //
    // 3) If `body->catch_except_p` is false and `always_leaf?` of an insn is true,
    // pc is not moved.
    if (body->catch_except_p)
        return false;

    unsigned int pos = 0;
    while (pos < body->iseq_size) {
        int insn = rb_vm_insn_decode(body->iseq_encoded[pos]);
        // All insns in the ISeq except `leave` (to be overridden in the inlined code)
        // should meet following strong assumptions:
        //   * Do not require `cfp->sp` motion
        //   * Do not move `cfp->pc`
        //   * Do not read any `cfp->pc`
        if (insn == BIN(invokebuiltin) || insn == BIN(opt_invokebuiltin_delegate) || insn == BIN(opt_invokebuiltin_delegate_leave)) {
            // builtin insn's inlinability is handled by `Primitive.attr! 'inline'` per iseq
            if (!body->builtin_inline_p)
                return false;
        }
        else if (insn != BIN(leave) && insn_may_depend_on_sp_or_pc(insn, body->iseq_encoded + (pos + 1)))
            return false;
        // At this moment, `cfp->ep` in an inlined method is not working.
        switch (insn) {
          case BIN(getlocal):
          case BIN(getlocal_WC_0):
          case BIN(getlocal_WC_1):
          case BIN(setlocal):
          case BIN(setlocal_WC_0):
          case BIN(setlocal_WC_1):
          case BIN(getblockparam):
          case BIN(getblockparamproxy):
          case BIN(setblockparam):
            return false;
        }
        pos += insn_len(insn);
    }
    return true;
}

// Return an iseq pointer if cc has inlinable iseq.
const rb_iseq_t *
rb_mjit_inlinable_iseq(const struct rb_callinfo *ci, const struct rb_callcache *cc)
{
    const rb_iseq_t *iseq;
    if (has_valid_method_type(cc) &&
        !(vm_ci_flag(ci) & VM_CALL_TAILCALL) && // inlining only non-tailcall path
        vm_cc_cme(cc)->def->type == VM_METHOD_TYPE_ISEQ &&
        fastpath_applied_iseq_p(ci, cc, iseq = def_iseq_ptr(vm_cc_cme(cc)->def)) &&
        // CC_SET_FASTPATH in vm_callee_setup_arg
        inlinable_iseq_p(iseq->body)) {
        return iseq;
    }
    return NULL;
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
        int insn = rb_vm_insn_decode(body->iseq_encoded[pos]);
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
#define INIT_COMPILE_STATUS(status, body, compile_root_p) do { \
    status = (struct compile_status){ \
        .stack_size_for_pos = (int *)alloca(sizeof(int) * body->iseq_size), \
        .inlined_iseqs = compile_root_p ? \
            alloca(sizeof(const struct rb_iseq_constant_body *) * body->iseq_size) : NULL, \
        .is_entries = (body->is_size > 0) ? \
            alloca(sizeof(union iseq_inline_storage_entry) * body->is_size) : NULL, \
        .cc_entries_index = (body->ci_size > 0) ? \
            mjit_capture_cc_entries(status.compiled_iseq, body) : -1, \
        .compiled_id = status.compiled_id, \
        .compiled_iseq = status.compiled_iseq, \
        .compile_info = compile_root_p ? \
            rb_mjit_iseq_compile_info(body) : alloca(sizeof(struct rb_mjit_compile_info)) \
    }; \
    memset(status.stack_size_for_pos, NOT_COMPILED_STACK_SIZE, sizeof(int) * body->iseq_size); \
    if (compile_root_p) \
        memset((void *)status.inlined_iseqs, 0, sizeof(const struct rb_iseq_constant_body *) * body->iseq_size); \
    else \
        memset(status.compile_info, 0, sizeof(struct rb_mjit_compile_info)); \
} while (0)

static bool
precompile_inlinable_child_iseq(FILE *f, const rb_iseq_t *child_iseq, struct compile_status *status,
                                const struct rb_callinfo *ci, const struct rb_callcache *cc, unsigned int pos)
{
    struct compile_status child_status = { .compiled_iseq = status->compiled_iseq, .compiled_id = status->compiled_id };
    INIT_COMPILE_STATUS(child_status, child_iseq->body, false);
    child_status.inline_context = (struct inlined_call_context){
        .orig_argc = vm_ci_argc(ci),
        .me = (VALUE)vm_cc_cme(cc),
        .param_size = child_iseq->body->param.size,
        .local_size = child_iseq->body->local_table_size
    };
    if (child_iseq->body->ci_size > 0 && child_status.cc_entries_index == -1) {
        return false;
    }
    init_ivar_compile_status(child_iseq->body, &child_status);

    fprintf(f, "ALWAYS_INLINE(static VALUE _mjit%d_inlined_%d(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE orig_self, const rb_iseq_t *original_iseq));\n", status->compiled_id, pos);
    fprintf(f, "static inline VALUE\n_mjit%d_inlined_%d(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE orig_self, const rb_iseq_t *original_iseq)\n{\n", status->compiled_id, pos);
    fprintf(f, "    const VALUE *orig_pc = reg_cfp->pc;\n");
    fprintf(f, "    VALUE *orig_sp = reg_cfp->sp;\n");
    bool success = mjit_compile_body(f, child_iseq, &child_status);
    fprintf(f, "\n} /* end of _mjit%d_inlined_%d */\n\n", status->compiled_id, pos);

    return success;
}

// Compile inlinable ISeqs to C code in `f`.  It returns true if it succeeds to compile them.
static bool
precompile_inlinable_iseqs(FILE *f, const rb_iseq_t *iseq, struct compile_status *status)
{
    const struct rb_iseq_constant_body *body = iseq->body;
    unsigned int pos = 0;
    while (pos < body->iseq_size) {
        int insn = rb_vm_insn_decode(body->iseq_encoded[pos]);
        if (insn == BIN(opt_send_without_block) || insn == BIN(opt_size)) { // `compile_inlined_cancel_handler` supports only `opt_send_without_block`
            CALL_DATA cd = (CALL_DATA)body->iseq_encoded[pos + 1];
            const struct rb_callinfo *ci = cd->ci;
            const struct rb_callcache *cc = captured_cc_entries(status)[call_data_index(cd, body)]; // use copy to avoid race condition

            extern bool rb_mjit_compiling_iseq_p(const rb_iseq_t *iseq);
            const rb_iseq_t *child_iseq;
            if ((child_iseq = rb_mjit_inlinable_iseq(ci, cc)) != NULL && rb_mjit_compiling_iseq_p(child_iseq)) {
                status->inlined_iseqs[pos] = child_iseq->body;

                if (mjit_opts.verbose >= 1) // print beforehand because ISeq may be GCed during copy job.
                    fprintf(stderr, "JIT inline: %s@%s:%d => %s@%s:%d\n",
                            RSTRING_PTR(child_iseq->body->location.label),
                            RSTRING_PTR(rb_iseq_path(child_iseq)), FIX2INT(child_iseq->body->location.first_lineno),
                            RSTRING_PTR(iseq->body->location.label),
                            RSTRING_PTR(rb_iseq_path(iseq)), FIX2INT(iseq->body->location.first_lineno));
                if (!precompile_inlinable_child_iseq(f, child_iseq, status, ci, cc, pos))
                    return false;
            }
        }
        pos += insn_len(insn);
    }
    return true;
}

// Compile ISeq to C code in `f`. It returns true if it succeeds to compile.
bool
mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id)
{
    struct compile_status status = { .compiled_iseq = iseq->body, .compiled_id = id };
    INIT_COMPILE_STATUS(status, iseq->body, true);
    if (iseq->body->ci_size > 0 && status.cc_entries_index == -1) {
        return false;
    }
    init_ivar_compile_status(iseq->body, &status);

    if (!status.compile_info->disable_send_cache && !status.compile_info->disable_inlining) {
        if (!precompile_inlinable_iseqs(f, iseq, &status))
            return false;
    }

#ifdef _WIN32
    fprintf(f, "__declspec(dllexport)\n");
#endif
    fprintf(f, "VALUE\n%s(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)\n{\n", funcname);
    bool success = mjit_compile_body(f, iseq, &status);
    fprintf(f, "\n} // end of %s\n", funcname);
    return success;
}

#endif // USE_MJIT
