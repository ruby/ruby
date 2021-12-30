// This file is a fragment of the yjit.o compilation unit. See yjit.c.
#include "internal.h"
#include "gc.h"
#include "internal/compile.h"
#include "internal/class.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/sanitizers.h"
#include "internal/string.h"
#include "internal/struct.h"
#include "internal/variable.h"
#include "internal/re.h"
#include "probes.h"
#include "probes_helper.h"
#include "yjit.h"
#include "yjit_iface.h"
#include "yjit_core.h"
#include "yjit_codegen.h"
#include "yjit_asm.h"

// Map from YARV opcodes to code generation functions
static codegen_fn gen_fns[VM_INSTRUCTION_SIZE] = { NULL };

// Map from method entries to code generation functions
static st_table *yjit_method_codegen_table = NULL;

// Code for exiting back to the interpreter from the leave instruction
static void *leave_exit_code;

// Code for full logic of returning from C method and exiting to the interpreter
static uint32_t outline_full_cfunc_return_pos;

// For implementing global code invalidation
struct codepage_patch {
    uint32_t inline_patch_pos;
    uint32_t outlined_target_pos;
};

typedef rb_darray(struct codepage_patch) patch_array_t;

static patch_array_t global_inval_patches = NULL;

// Print the current source location for debugging purposes
RBIMPL_ATTR_MAYBE_UNUSED()
static void
jit_print_loc(jitstate_t *jit, const char *msg)
{
    char *ptr;
    long len;
    VALUE path = rb_iseq_path(jit->iseq);
    RSTRING_GETMEM(path, ptr, len);
    fprintf(stderr, "%s %.*s:%u\n", msg, (int)len, ptr, rb_iseq_line_no(jit->iseq, jit->insn_idx));
}

// dump an object for debugging purposes
RBIMPL_ATTR_MAYBE_UNUSED()
static void
jit_obj_info_dump(codeblock_t *cb, x86opnd_t opnd) {
    push_regs(cb);
    mov(cb, C_ARG_REGS[0], opnd);
    call_ptr(cb, REG0, (void *)rb_obj_info_dump);
    pop_regs(cb);
}

// Get the current instruction's opcode
static int
jit_get_opcode(jitstate_t *jit)
{
    return jit->opcode;
}

// Get the index of the next instruction
static uint32_t
jit_next_insn_idx(jitstate_t *jit)
{
    return jit->insn_idx + insn_len(jit_get_opcode(jit));
}

// Get an instruction argument by index
static VALUE
jit_get_arg(jitstate_t *jit, size_t arg_idx)
{
    RUBY_ASSERT(arg_idx + 1 < (size_t)insn_len(jit_get_opcode(jit)));
    return *(jit->pc + arg_idx + 1);
}

// Load a VALUE into a register and keep track of the reference if it is on the GC heap.
static void
jit_mov_gc_ptr(jitstate_t *jit, codeblock_t *cb, x86opnd_t reg, VALUE ptr)
{
    RUBY_ASSERT(reg.type == OPND_REG && reg.num_bits == 64);

    // Load the pointer constant into the specified register
    mov(cb, reg, const_ptr_opnd((void*)ptr));

    // The pointer immediate is encoded as the last part of the mov written out
    uint32_t ptr_offset = cb->write_pos - sizeof(VALUE);

    if (!SPECIAL_CONST_P(ptr)) {
        if (!rb_darray_append(&jit->block->gc_object_offsets, ptr_offset)) {
            rb_bug("allocation failed");
        }
    }
}

// Check if we are compiling the instruction at the stub PC
// Meaning we are compiling the instruction that is next to execute
static bool
jit_at_current_insn(jitstate_t *jit)
{
    const VALUE *ec_pc = jit->ec->cfp->pc;
    return (ec_pc == jit->pc);
}

// Peek at the nth topmost value on the Ruby stack.
// Returns the topmost value when n == 0.
static VALUE
jit_peek_at_stack(jitstate_t *jit, ctx_t *ctx, int n)
{
    RUBY_ASSERT(jit_at_current_insn(jit));

    // Note: this does not account for ctx->sp_offset because
    // this is only available when hitting a stub, and while
    // hitting a stub, cfp->sp needs to be up to date in case
    // codegen functions trigger GC. See :stub-sp-flush:.
    VALUE *sp = jit->ec->cfp->sp;

    return *(sp - 1 - n);
}

static VALUE
jit_peek_at_self(jitstate_t *jit, ctx_t *ctx)
{
    return jit->ec->cfp->self;
}

RBIMPL_ATTR_MAYBE_UNUSED()
static VALUE
jit_peek_at_local(jitstate_t *jit, ctx_t *ctx, int n)
{
    RUBY_ASSERT(jit_at_current_insn(jit));

    int32_t local_table_size = jit->iseq->body->local_table_size;
    RUBY_ASSERT(n < (int)jit->iseq->body->local_table_size);

    const VALUE *ep = jit->ec->cfp->ep;
    return ep[-VM_ENV_DATA_SIZE - local_table_size + n + 1];
}

// Save the incremented PC on the CFP
// This is necessary when calleees can raise or allocate
static void
jit_save_pc(jitstate_t *jit, x86opnd_t scratch_reg)
{
    codeblock_t *cb = jit->cb;
    mov(cb, scratch_reg, const_ptr_opnd(jit->pc + insn_len(jit->opcode)));
    mov(cb, mem_opnd(64, REG_CFP, offsetof(rb_control_frame_t, pc)), scratch_reg);
}

// Save the current SP on the CFP
// This realigns the interpreter SP with the JIT SP
// Note: this will change the current value of REG_SP,
//       which could invalidate memory operands
static void
jit_save_sp(jitstate_t *jit, ctx_t *ctx)
{
    if (ctx->sp_offset != 0) {
        x86opnd_t stack_pointer = ctx_sp_opnd(ctx, 0);
        codeblock_t *cb = jit->cb;
        lea(cb, REG_SP, stack_pointer);
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG_SP);
        ctx->sp_offset = 0;
    }
}

// jit_save_pc() + jit_save_sp(). Should be used before calling a routine that
// could:
//  - Perform GC allocation
//  - Take the VM lock through RB_VM_LOCK_ENTER()
//  - Perform Ruby method call
static void
jit_prepare_routine_call(jitstate_t *jit, ctx_t *ctx, x86opnd_t scratch_reg)
{
    jit->record_boundary_patch_point = true;
    jit_save_pc(jit, scratch_reg);
    jit_save_sp(jit, ctx);
}

// Record the current codeblock write position for rewriting into a jump into
// the outlined block later. Used to implement global code invalidation.
static void
record_global_inval_patch(const codeblock_t *cb, uint32_t outline_block_target_pos)
{
    struct codepage_patch patch_point = { cb->write_pos, outline_block_target_pos };
    if (!rb_darray_append(&global_inval_patches, patch_point)) rb_bug("allocation failed");
}

static bool jit_guard_known_klass(jitstate_t *jit, ctx_t *ctx, VALUE known_klass, insn_opnd_t insn_opnd, VALUE sample_instance, const int max_chain_depth, uint8_t *side_exit);

#if YJIT_STATS

// Add a comment at the current position in the code block
static void
_add_comment(codeblock_t *cb, const char *comment_str)
{
    // We can't add comments to the outlined code block
    if (cb == ocb)
        return;

    // Avoid adding duplicate comment strings (can happen due to deferred codegen)
    size_t num_comments = rb_darray_size(yjit_code_comments);
    if (num_comments > 0) {
        struct yjit_comment last_comment = rb_darray_get(yjit_code_comments, num_comments - 1);
        if (last_comment.offset == cb->write_pos && strcmp(last_comment.comment, comment_str) == 0) {
            return;
        }
    }

    struct yjit_comment new_comment = (struct yjit_comment){ cb->write_pos, comment_str };
    rb_darray_append(&yjit_code_comments, new_comment);
}

// Comments for generated machine code
#define ADD_COMMENT(cb, comment) _add_comment((cb), (comment))

// Verify the ctx's types and mappings against the compile-time stack, self,
// and locals.
static void
verify_ctx(jitstate_t *jit, ctx_t *ctx)
{
    // Only able to check types when at current insn
    RUBY_ASSERT(jit_at_current_insn(jit));

    VALUE self_val = jit_peek_at_self(jit, ctx);
    if (type_diff(yjit_type_of_value(self_val), ctx->self_type) == INT_MAX) {
        rb_bug("verify_ctx: ctx type (%s) incompatible with actual value of self: %s", yjit_type_name(ctx->self_type), rb_obj_info(self_val));
    }

    for (int i = 0; i < ctx->stack_size && i < MAX_TEMP_TYPES; i++) {
        temp_type_mapping_t learned = ctx_get_opnd_mapping(ctx, OPND_STACK(i));
        VALUE val = jit_peek_at_stack(jit, ctx, i);
        val_type_t detected = yjit_type_of_value(val);

        if (learned.mapping.kind == TEMP_SELF) {
            if (self_val != val) {
                rb_bug("verify_ctx: stack value was mapped to self, but values did not match\n"
                        "  stack: %s\n"
                        "  self: %s",
                        rb_obj_info(val),
                        rb_obj_info(self_val));
            }
        }

        if (learned.mapping.kind == TEMP_LOCAL) {
            int local_idx = learned.mapping.idx;
            VALUE local_val = jit_peek_at_local(jit, ctx, local_idx);
            if (local_val != val) {
                rb_bug("verify_ctx: stack value was mapped to local, but values did not match\n"
                        "  stack: %s\n"
                        "  local %i: %s",
                        rb_obj_info(val),
                        local_idx,
                        rb_obj_info(local_val));
            }
        }

        if (type_diff(detected, learned.type) == INT_MAX) {
            rb_bug("verify_ctx: ctx type (%s) incompatible with actual value on stack: %s", yjit_type_name(learned.type), rb_obj_info(val));
        }
    }

    int32_t local_table_size = jit->iseq->body->local_table_size;
    for (int i = 0; i < local_table_size && i < MAX_TEMP_TYPES; i++) {
        val_type_t learned = ctx->local_types[i];
        VALUE val = jit_peek_at_local(jit, ctx, i);
        val_type_t detected = yjit_type_of_value(val);

        if (type_diff(detected, learned) == INT_MAX) {
            rb_bug("verify_ctx: ctx type (%s) incompatible with actual value of local: %s", yjit_type_name(learned), rb_obj_info(val));
        }
    }
}

#else

#define ADD_COMMENT(cb, comment) ((void)0)
#define verify_ctx(jit, ctx) ((void)0)

#endif // if YJIT_STATS

#if YJIT_STATS

// Increment a profiling counter with counter_name
#define GEN_COUNTER_INC(cb, counter_name) _gen_counter_inc(cb, &(yjit_runtime_counters . counter_name))
static void
_gen_counter_inc(codeblock_t *cb, int64_t *counter)
{
    if (!rb_yjit_opts.gen_stats) return;

    // Use REG1 because there might be return value in REG0
    mov(cb, REG1, const_ptr_opnd(counter));
    cb_write_lock_prefix(cb); // for ractors.
    add(cb, mem_opnd(64, REG1, 0), imm_opnd(1));
}

// Increment a counter then take an existing side exit.
#define COUNTED_EXIT(jit, side_exit, counter_name) _counted_side_exit(jit, side_exit, &(yjit_runtime_counters . counter_name))
static uint8_t *
_counted_side_exit(jitstate_t* jit, uint8_t *existing_side_exit, int64_t *counter)
{
    if (!rb_yjit_opts.gen_stats) return existing_side_exit;

    uint8_t *start = cb_get_ptr(jit->ocb, jit->ocb->write_pos);
    _gen_counter_inc(jit->ocb, counter);
    jmp_ptr(jit->ocb, existing_side_exit);
    return start;
}

#else

#define GEN_COUNTER_INC(cb, counter_name) ((void)0)
#define COUNTED_EXIT(jit, side_exit, counter_name) side_exit

#endif // if YJIT_STATS

// Generate an exit to return to the interpreter
static uint32_t
yjit_gen_exit(VALUE *exit_pc, ctx_t *ctx, codeblock_t *cb)
{
    const uint32_t code_pos = cb->write_pos;

    ADD_COMMENT(cb, "exit to interpreter");

    // Generate the code to exit to the interpreters
    // Write the adjusted SP back into the CFP
    if (ctx->sp_offset != 0) {
        x86opnd_t stack_pointer = ctx_sp_opnd(ctx, 0);
        lea(cb, REG_SP, stack_pointer);
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG_SP);
    }

    // Update CFP->PC
    mov(cb, RAX, const_ptr_opnd(exit_pc));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), RAX);

    // Accumulate stats about interpreter exits
#if YJIT_STATS
    if (rb_yjit_opts.gen_stats) {
        mov(cb, RDI, const_ptr_opnd(exit_pc));
        call_ptr(cb, RSI, (void *)&yjit_count_side_exit_op);
    }
#endif

    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    mov(cb, RAX, imm_opnd(Qundef));
    ret(cb);

    return code_pos;
}

// Generate a continuation for gen_leave() that exits to the interpreter at REG_CFP->pc.
static uint8_t *
yjit_gen_leave_exit(codeblock_t *cb)
{
    uint8_t *code_ptr = cb_get_ptr(cb, cb->write_pos);

    // Note, gen_leave() fully reconstructs interpreter state and leaves the
    // return value in RAX before coming here.

    // Every exit to the interpreter should be counted
    GEN_COUNTER_INC(cb, leave_interp_return);

    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    ret(cb);

    return code_ptr;
}

// Fill code_for_exit_from_stub. This is used by branch_stub_hit() to exit
// to the interpreter when it cannot service a stub by generating new code.
// Before coming here, branch_stub_hit() takes care of fully reconstructing
// interpreter state.
static void
gen_code_for_exit_from_stub(void)
{
    codeblock_t *cb = ocb;
    code_for_exit_from_stub = cb_get_ptr(cb, cb->write_pos);

    GEN_COUNTER_INC(cb, exit_from_branch_stub);

    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    mov(cb, RAX, imm_opnd(Qundef));
    ret(cb);
}

// :side-exit:
// Get an exit for the current instruction in the outlined block. The code
// for each instruction often begins with several guards before proceeding
// to do work. When guards fail, an option we have is to exit to the
// interpreter at an instruction boundary. The piece of code that takes
// care of reconstructing interpreter state and exiting out of generated
// code is called the side exit.
//
// No guards change the logic for reconstructing interpreter state at the
// moment, so there is one unique side exit for each context. Note that
// it's incorrect to jump to the side exit after any ctx stack push/pop operations
// since they change the logic required for reconstructing interpreter state.
static uint8_t *
yjit_side_exit(jitstate_t *jit, ctx_t *ctx)
{
    if (!jit->side_exit_for_pc) {
        codeblock_t *ocb = jit->ocb;
        uint32_t pos = yjit_gen_exit(jit->pc, ctx, ocb);
        jit->side_exit_for_pc = cb_get_ptr(ocb, pos);
    }

    return jit->side_exit_for_pc;
}

// Ensure that there is an exit for the start of the block being compiled.
// Block invalidation uses this exit.
static void
jit_ensure_block_entry_exit(jitstate_t *jit)
{
    block_t *block = jit->block;
    if (block->entry_exit) return;

    if (jit->insn_idx == block->blockid.idx) {
        // We are compiling the first instruction in the block.
        // Generate the exit with the cache in jitstate.
        block->entry_exit = yjit_side_exit(jit, &block->ctx);
    }
    else {
        VALUE *pc = yjit_iseq_pc_at_idx(block->blockid.iseq, block->blockid.idx);
        uint32_t pos = yjit_gen_exit(pc, &block->ctx, ocb);
        block->entry_exit = cb_get_ptr(ocb, pos);
    }
}

// Generate a runtime guard that ensures the PC is at the start of the iseq,
// otherwise take a side exit.  This is to handle the situation of optional
// parameters.  When a function with optional parameters is called, the entry
// PC for the method isn't necessarily 0, but we always generated code that
// assumes the entry point is 0.
static void
yjit_pc_guard(codeblock_t *cb, const rb_iseq_t *iseq)
{
    RUBY_ASSERT(cb != NULL);

    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, pc));
    mov(cb, REG1, const_ptr_opnd(iseq->body->iseq_encoded));
    xor(cb, REG0, REG1);

    // xor should impact ZF, so we can jz here
    uint32_t pc_is_zero = cb_new_label(cb, "pc_is_zero");
    jz_label(cb, pc_is_zero);

    // We're not starting at the first PC, so we need to exit.
    GEN_COUNTER_INC(cb, leave_start_pc_non_zero);

    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    mov(cb, RAX, imm_opnd(Qundef));
    ret(cb);

    // PC should be at the beginning
    cb_write_label(cb, pc_is_zero);
    cb_link_labels(cb);
}

// The code we generate in gen_send_cfunc() doesn't fire the c_return TracePoint event
// like the interpreter. When tracing for c_return is enabled, we patch the code after
// the C method return to call into this to fire the event.
static void
full_cfunc_return(rb_execution_context_t *ec, VALUE return_value)
{
    rb_control_frame_t *cfp = ec->cfp;
    RUBY_ASSERT_ALWAYS(cfp == GET_EC()->cfp);
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    RUBY_ASSERT_ALWAYS(RUBYVM_CFUNC_FRAME_P(cfp));
    RUBY_ASSERT_ALWAYS(me->def->type == VM_METHOD_TYPE_CFUNC);

    // CHECK_CFP_CONSISTENCY("full_cfunc_return"); TODO revive this

    // Pop the C func's frame and fire the c_return TracePoint event
    // Note that this is the same order as vm_call_cfunc_with_frame().
    rb_vm_pop_frame(ec);
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, cfp->self, me->def->original_id, me->called_id, me->owner, return_value);
    // Note, this deviates from the interpreter in that users need to enable
    // a c_return TracePoint for this DTrace hook to work. A reasonable change
    // since the Ruby return event works this way as well.
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, me->owner, me->def->original_id);

    // Push return value into the caller's stack. We know that it's a frame that
    // uses cfp->sp because we are patching a call done with gen_send_cfunc().
    ec->cfp->sp[0] = return_value;
    ec->cfp->sp++;
}

// Landing code for when c_return tracing is enabled. See full_cfunc_return().
static void
gen_full_cfunc_return(void)
{
    codeblock_t *cb = ocb;
    outline_full_cfunc_return_pos = ocb->write_pos;

    // This chunk of code expect REG_EC to be filled properly and
    // RAX to contain the return value of the C method.

    // Call full_cfunc_return()
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(cb, C_ARG_REGS[1], RAX);
    call_ptr(cb, REG0, (void *)full_cfunc_return);

    // Count the exit
    GEN_COUNTER_INC(cb, traced_cfunc_return);

    // Return to the interpreter
    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    mov(cb, RAX, imm_opnd(Qundef));
    ret(cb);
}

/*
Compile an interpreter entry block to be inserted into an iseq
Returns `NULL` if compilation fails.
*/
static uint8_t *
yjit_entry_prologue(codeblock_t *cb, const rb_iseq_t *iseq)
{
    RUBY_ASSERT(cb != NULL);

    enum { MAX_PROLOGUE_SIZE = 1024 };

    // Check if we have enough executable memory
    if (cb->write_pos + MAX_PROLOGUE_SIZE >= cb->mem_size) {
        return NULL;
    }

    const uint32_t old_write_pos = cb->write_pos;

    // Align the current write position to cache line boundaries
    cb_align_pos(cb, 64);

    uint8_t *code_ptr = cb_get_ptr(cb, cb->write_pos);
    ADD_COMMENT(cb, "yjit entry");

    push(cb, REG_CFP);
    push(cb, REG_EC);
    push(cb, REG_SP);

    // We are passed EC and CFP
    mov(cb, REG_EC, C_ARG_REGS[0]);
    mov(cb, REG_CFP, C_ARG_REGS[1]);

    // Load the current SP from the CFP into REG_SP
    mov(cb, REG_SP, member_opnd(REG_CFP, rb_control_frame_t, sp));

    // Setup cfp->jit_return
    // TODO: this could use an IP relative LEA instead of an 8 byte immediate
    mov(cb, REG0, const_ptr_opnd(leave_exit_code));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, jit_return), REG0);

    // We're compiling iseqs that we *expect* to start at `insn_idx`. But in
    // the case of optional parameters, the interpreter can set the pc to a
    // different location depending on the optional parameters.  If an iseq
    // has optional parameters, we'll add a runtime check that the PC we've
    // compiled for is the same PC that the interpreter wants us to run with.
    // If they don't match, then we'll take a side exit.
    if (iseq->body->param.flags.has_opt) {
        yjit_pc_guard(cb, iseq);
    }

    // Verify MAX_PROLOGUE_SIZE
    RUBY_ASSERT_ALWAYS(cb->write_pos - old_write_pos <= MAX_PROLOGUE_SIZE);

    return code_ptr;
}

// Generate code to check for interrupts and take a side-exit.
// Warning: this function clobbers REG0
static void
yjit_check_ints(codeblock_t *cb, uint8_t *side_exit)
{
    // Check for interrupts
    // see RUBY_VM_CHECK_INTS(ec) macro
    ADD_COMMENT(cb, "RUBY_VM_CHECK_INTS(ec)");
    mov(cb, REG0_32, member_opnd(REG_EC, rb_execution_context_t, interrupt_mask));
    not(cb, REG0_32);
    test(cb, member_opnd(REG_EC, rb_execution_context_t, interrupt_flag), REG0_32);
    jnz_ptr(cb, side_exit);
}

// Generate a stubbed unconditional jump to the next bytecode instruction.
// Blocks that are part of a guard chain can use this to share the same successor.
static void
jit_jump_to_next_insn(jitstate_t *jit, const ctx_t *current_context)
{
    // Reset the depth since in current usages we only ever jump to to
    // chain_depth > 0 from the same instruction.
    ctx_t reset_depth = *current_context;
    reset_depth.chain_depth = 0;

    blockid_t jump_block = { jit->iseq, jit_next_insn_idx(jit) };

    // We are at the end of the current instruction. Record the boundary.
    if (jit->record_boundary_patch_point) {
        uint32_t exit_pos = yjit_gen_exit(jit->pc + insn_len(jit->opcode), &reset_depth, jit->ocb);
        record_global_inval_patch(jit->cb, exit_pos);
        jit->record_boundary_patch_point = false;
    }

    // Generate the jump instruction
    gen_direct_jump(
        jit,
        &reset_depth,
        jump_block
    );
}

// Compile a sequence of bytecode instructions for a given basic block version.
// Part of gen_block_version().
static block_t *
gen_single_block(blockid_t blockid, const ctx_t *start_ctx, rb_execution_context_t *ec)
{
    RUBY_ASSERT(cb != NULL);
    verify_blockid(blockid);

    // Allocate the new block
    block_t *block = calloc(1, sizeof(block_t));
    if (!block) {
        return NULL;
    }

    // Copy the starting context to avoid mutating it
    ctx_t ctx_copy = *start_ctx;
    ctx_t *ctx = &ctx_copy;

    // Limit the number of specialized versions for this block
    *ctx = limit_block_versions(blockid, ctx);

    // Save the starting context on the block.
    block->blockid = blockid;
    block->ctx = *ctx;

    RUBY_ASSERT(!(blockid.idx == 0 && start_ctx->stack_size > 0));

    const rb_iseq_t *iseq = block->blockid.iseq;
    const unsigned int iseq_size = iseq->body->iseq_size;
    uint32_t insn_idx = block->blockid.idx;
    const uint32_t starting_insn_idx = insn_idx;

    // Initialize a JIT state object
    jitstate_t jit = {
        .cb = cb,
        .ocb = ocb,
        .block = block,
        .iseq = iseq,
        .ec = ec
    };

    // Mark the start position of the block
    block->start_addr = cb_get_write_ptr(cb);

    // For each instruction to compile
    while (insn_idx < iseq_size) {
        // Get the current pc and opcode
        VALUE *pc = yjit_iseq_pc_at_idx(iseq, insn_idx);
        int opcode = yjit_opcode_at_pc(iseq, pc);
        RUBY_ASSERT(opcode >= 0 && opcode < VM_INSTRUCTION_SIZE);

        // opt_getinlinecache wants to be in a block all on its own. Cut the block short
        // if we run into it. See gen_opt_getinlinecache() for details.
        if (opcode == BIN(opt_getinlinecache) && insn_idx > starting_insn_idx) {
            jit_jump_to_next_insn(&jit, ctx);
            break;
        }

        // Set the current instruction
        jit.insn_idx = insn_idx;
        jit.opcode = opcode;
        jit.pc = pc;
        jit.side_exit_for_pc = NULL;

        // If previous instruction requested to record the boundary
        if (jit.record_boundary_patch_point) {
            // Generate an exit to this instruction and record it
            uint32_t exit_pos = yjit_gen_exit(jit.pc, ctx, ocb);
            record_global_inval_patch(cb, exit_pos);
            jit.record_boundary_patch_point = false;
        }

        // Verify our existing assumption (DEBUG)
        if (jit_at_current_insn(&jit)) {
            verify_ctx(&jit, ctx);
        }

        // Lookup the codegen function for this instruction
        codegen_fn gen_fn = gen_fns[opcode];
        codegen_status_t status = YJIT_CANT_COMPILE;
        if (gen_fn) {
            if (0) {
                fprintf(stderr, "compiling %d: %s\n", insn_idx, insn_name(opcode));
                print_str(cb, insn_name(opcode));
            }

            // :count-placement:
            // Count bytecode instructions that execute in generated code.
            // Note that the increment happens even when the output takes side exit.
            GEN_COUNTER_INC(cb, exec_instruction);

            // Add a comment for the name of the YARV instruction
            ADD_COMMENT(cb, insn_name(opcode));

            // Call the code generation function
            status = gen_fn(&jit, ctx, cb);
        }

        // If we can't compile this instruction
        // exit to the interpreter and stop compiling
        if (status == YJIT_CANT_COMPILE) {
            // TODO: if the codegen function makes changes to ctx and then return YJIT_CANT_COMPILE,
            // the exit this generates would be wrong. We could save a copy of the entry context
            // and assert that ctx is the same here.
            uint32_t exit_off = yjit_gen_exit(jit.pc, ctx, cb);

            // If this is the first instruction in the block, then we can use
            // the exit for block->entry_exit.
            if (insn_idx == block->blockid.idx) {
                block->entry_exit = cb_get_ptr(cb, exit_off);
            }
            break;
        }

        // For now, reset the chain depth after each instruction as only the
        // first instruction in the block can concern itself with the depth.
        ctx->chain_depth = 0;

        // Move to the next instruction to compile
        insn_idx += insn_len(opcode);

        // If the instruction terminates this block
        if (status == YJIT_END_BLOCK) {
            break;
        }
    }

    // Mark the end position of the block
    block->end_addr = cb_get_write_ptr(cb);

    // Store the index of the last instruction in the block
    block->end_idx = insn_idx;

    // We currently can't handle cases where the request is for a block that
    // doesn't go to the next instruction.
    RUBY_ASSERT(!jit.record_boundary_patch_point);

    // If code for the block doesn't fit, free the block and fail.
    if (cb->dropped_bytes || ocb->dropped_bytes) {
        yjit_free_block(block);
        return NULL;
    }

    if (YJIT_DUMP_MODE >= 2) {
        // Dump list of compiled instrutions
        fprintf(stderr, "Compiled the following for iseq=%p:\n", (void *)iseq);
        for (uint32_t idx = block->blockid.idx; idx < insn_idx; ) {
            int opcode = yjit_opcode_at_pc(iseq, yjit_iseq_pc_at_idx(iseq, idx));
            fprintf(stderr, "  %04d %s\n", idx, insn_name(opcode));
            idx += insn_len(opcode);
        }
    }

    return block;
}

static codegen_status_t gen_opt_send_without_block(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb);

static codegen_status_t
gen_nop(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Do nothing
    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_dup(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Get the top value and its type
    x86opnd_t dup_val = ctx_stack_pop(ctx, 0);
    temp_type_mapping_t mapping = ctx_get_opnd_mapping(ctx, OPND_STACK(0));

    // Push the same value on top
    x86opnd_t loc0 = ctx_stack_push_mapping(ctx, mapping);
    mov(cb, REG0, dup_val);
    mov(cb, loc0, REG0);

    return YJIT_KEEP_COMPILING;
}

// duplicate stack top n elements
static codegen_status_t
gen_dupn(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    rb_num_t n = (rb_num_t)jit_get_arg(jit, 0);

    // In practice, seems to be only used for n==2
    if (n != 2) {
        return YJIT_CANT_COMPILE;
    }

    x86opnd_t opnd1 = ctx_stack_opnd(ctx, 1);
    x86opnd_t opnd0 = ctx_stack_opnd(ctx, 0);
    temp_type_mapping_t mapping1 = ctx_get_opnd_mapping(ctx, OPND_STACK(1));
    temp_type_mapping_t mapping0 = ctx_get_opnd_mapping(ctx, OPND_STACK(0));

    x86opnd_t dst1 = ctx_stack_push_mapping(ctx, mapping1);
    mov(cb, REG0, opnd1);
    mov(cb, dst1, REG0);

    x86opnd_t dst0 = ctx_stack_push_mapping(ctx, mapping0);
    mov(cb, REG0, opnd0);
    mov(cb, dst0, REG0);

    return YJIT_KEEP_COMPILING;
}

static void
stack_swap(ctx_t *ctx, codeblock_t *cb, int offset0, int offset1, x86opnd_t reg0, x86opnd_t reg1)
{
    x86opnd_t opnd0 = ctx_stack_opnd(ctx, offset0);
    x86opnd_t opnd1 = ctx_stack_opnd(ctx, offset1);

    temp_type_mapping_t mapping0 = ctx_get_opnd_mapping(ctx, OPND_STACK(offset0));
    temp_type_mapping_t mapping1 = ctx_get_opnd_mapping(ctx, OPND_STACK(offset1));

    mov(cb, reg0, opnd0);
    mov(cb, reg1, opnd1);
    mov(cb, opnd0, reg1);
    mov(cb, opnd1, reg0);

    ctx_set_opnd_mapping(ctx, OPND_STACK(offset0), mapping1);
    ctx_set_opnd_mapping(ctx, OPND_STACK(offset1), mapping0);
}

// Swap top 2 stack entries
static codegen_status_t
gen_swap(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    stack_swap(ctx , cb, 0, 1, REG0, REG1);
    return YJIT_KEEP_COMPILING;
}

// set Nth stack entry to stack top
static codegen_status_t
gen_setn(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    rb_num_t n = (rb_num_t)jit_get_arg(jit, 0);

    // Set the destination
    x86opnd_t top_val = ctx_stack_pop(ctx, 0);
    x86opnd_t dst_opnd = ctx_stack_opnd(ctx, (int32_t)n);
    mov(cb, REG0, top_val);
    mov(cb, dst_opnd, REG0);

    temp_type_mapping_t mapping = ctx_get_opnd_mapping(ctx, OPND_STACK(0));
    ctx_set_opnd_mapping(ctx, OPND_STACK(n), mapping);

    return YJIT_KEEP_COMPILING;
}

// get nth stack value, then push it
static codegen_status_t
gen_topn(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t n = (int32_t)jit_get_arg(jit, 0);

    // Get top n type / operand
    x86opnd_t top_n_val = ctx_stack_opnd(ctx, n);
    temp_type_mapping_t mapping = ctx_get_opnd_mapping(ctx, OPND_STACK(n));

    x86opnd_t loc0 = ctx_stack_push_mapping(ctx, mapping);
    mov(cb, REG0, top_n_val);
    mov(cb, loc0, REG0);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_pop(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Decrement SP
    ctx_stack_pop(ctx, 1);
    return YJIT_KEEP_COMPILING;
}

// Pop n values off the stack
static codegen_status_t
gen_adjuststack(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    rb_num_t n = (rb_num_t)jit_get_arg(jit, 0);
    ctx_stack_pop(ctx, n);
    return YJIT_KEEP_COMPILING;
}

// new array initialized from top N values
static codegen_status_t
gen_newarray(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    rb_num_t n = (rb_num_t)jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, REG0);

    x86opnd_t values_ptr = ctx_sp_opnd(ctx, -(sizeof(VALUE) * (uint32_t)n));

    // call rb_ec_ary_new_from_values(struct rb_execution_context_struct *ec, long n, const VALUE *elts);
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(cb, C_ARG_REGS[1], imm_opnd(n));
    lea(cb, C_ARG_REGS[2], values_ptr);
    call_ptr(cb, REG0, (void *)rb_ec_ary_new_from_values);

    ctx_stack_pop(ctx, n);
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_ARRAY);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

// dup array
static codegen_status_t
gen_duparray(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    VALUE ary = jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, REG0);

    // call rb_ary_resurrect(VALUE ary);
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], ary);
    call_ptr(cb, REG0, (void *)rb_ary_resurrect);

    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_ARRAY);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

// dup hash
static codegen_status_t
gen_duphash(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    VALUE hash = jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, REG0);

    // call rb_hash_resurrect(VALUE hash);
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], hash);
    call_ptr(cb, REG0, (void *)rb_hash_resurrect);

    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_HASH);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

VALUE rb_vm_splat_array(VALUE flag, VALUE ary);

// call to_a on the array on the stack
static codegen_status_t
gen_splatarray(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    VALUE flag = (VALUE) jit_get_arg(jit, 0);

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, REG0);

    // Get the operands from the stack
    x86opnd_t ary_opnd = ctx_stack_pop(ctx, 1);

    // Call rb_vm_splat_array(flag, ary)
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], flag);
    mov(cb, C_ARG_REGS[1], ary_opnd);
    call_ptr(cb, REG1, (void *) rb_vm_splat_array);

    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_ARRAY);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

// new range initialized from top 2 values
static codegen_status_t
gen_newrange(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    rb_num_t flag = (rb_num_t)jit_get_arg(jit, 0);

    // rb_range_new() allocates and can raise
    jit_prepare_routine_call(jit, ctx, REG0);

    // val = rb_range_new(low, high, (int)flag);
    mov(cb, C_ARG_REGS[0], ctx_stack_opnd(ctx, 1));
    mov(cb, C_ARG_REGS[1], ctx_stack_opnd(ctx, 0));
    mov(cb, C_ARG_REGS[2], imm_opnd(flag));
    call_ptr(cb, REG0, (void *)rb_range_new);

    ctx_stack_pop(ctx, 2);
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_HEAP);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

static void
guard_object_is_heap(codeblock_t *cb, x86opnd_t object_opnd, ctx_t *ctx, uint8_t *side_exit)
{
    ADD_COMMENT(cb, "guard object is heap");

    // Test that the object is not an immediate
    test(cb, object_opnd, imm_opnd(RUBY_IMMEDIATE_MASK));
    jnz_ptr(cb, side_exit);

    // Test that the object is not false or nil
    cmp(cb, object_opnd, imm_opnd(Qnil));
    RUBY_ASSERT(Qfalse < Qnil);
    jbe_ptr(cb, side_exit);
}

static inline void
guard_object_is_array(codeblock_t *cb, x86opnd_t object_opnd, x86opnd_t flags_opnd, ctx_t *ctx, uint8_t *side_exit)
{
    ADD_COMMENT(cb, "guard object is array");

    // Pull out the type mask
    mov(cb, flags_opnd, member_opnd(object_opnd, struct RBasic, flags));
    and(cb, flags_opnd, imm_opnd(RUBY_T_MASK));

    // Compare the result with T_ARRAY
    cmp(cb, flags_opnd, imm_opnd(T_ARRAY));
    jne_ptr(cb, side_exit);
}

// push enough nils onto the stack to fill out an array
static codegen_status_t
gen_expandarray(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int flag = (int) jit_get_arg(jit, 1);

    // If this instruction has the splat flag, then bail out.
    if (flag & 0x01) {
        GEN_COUNTER_INC(cb, expandarray_splat);
        return YJIT_CANT_COMPILE;
    }

    // If this instruction has the postarg flag, then bail out.
    if (flag & 0x02) {
        GEN_COUNTER_INC(cb, expandarray_postarg);
        return YJIT_CANT_COMPILE;
    }

    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // num is the number of requested values. If there aren't enough in the
    // array then we're going to push on nils.
    int num = (int)jit_get_arg(jit, 0);
    val_type_t array_type = ctx_get_opnd_type(ctx, OPND_STACK(0));
    x86opnd_t array_opnd = ctx_stack_pop(ctx, 1);

    if (array_type.type == ETYPE_NIL) {
        // special case for a, b = nil pattern
        // push N nils onto the stack
        for (int i = 0; i < num; i++) {
            x86opnd_t push = ctx_stack_push(ctx, TYPE_NIL);
            mov(cb, push, imm_opnd(Qnil));
        }
        return YJIT_KEEP_COMPILING;
    }

    // Move the array from the stack into REG0 and check that it's an array.
    mov(cb, REG0, array_opnd);
    guard_object_is_heap(cb, REG0, ctx, COUNTED_EXIT(jit, side_exit, expandarray_not_array));
    guard_object_is_array(cb, REG0, REG1, ctx, COUNTED_EXIT(jit, side_exit, expandarray_not_array));

    // If we don't actually want any values, then just return.
    if (num == 0) {
        return YJIT_KEEP_COMPILING;
    }

    // Pull out the embed flag to check if it's an embedded array.
    x86opnd_t flags_opnd = member_opnd(REG0, struct RBasic, flags);
    mov(cb, REG1, flags_opnd);

    // Move the length of the embedded array into REG1.
    and(cb, REG1, imm_opnd(RARRAY_EMBED_LEN_MASK));
    shr(cb, REG1, imm_opnd(RARRAY_EMBED_LEN_SHIFT));

    // Conditionally move the length of the heap array into REG1.
    test(cb, flags_opnd, imm_opnd(RARRAY_EMBED_FLAG));
    cmovz(cb, REG1, member_opnd(REG0, struct RArray, as.heap.len));

    // Only handle the case where the number of values in the array is greater
    // than or equal to the number of values requested.
    cmp(cb, REG1, imm_opnd(num));
    jl_ptr(cb, COUNTED_EXIT(jit, side_exit, expandarray_rhs_too_small));

    // Load the address of the embedded array into REG1.
    // (struct RArray *)(obj)->as.ary
    lea(cb, REG1, member_opnd(REG0, struct RArray, as.ary));

    // Conditionally load the address of the heap array into REG1.
    // (struct RArray *)(obj)->as.heap.ptr
    test(cb, flags_opnd, imm_opnd(RARRAY_EMBED_FLAG));
    cmovz(cb, REG1, member_opnd(REG0, struct RArray, as.heap.ptr));

    // Loop backward through the array and push each element onto the stack.
    for (int32_t i = (int32_t) num - 1; i >= 0; i--) {
        x86opnd_t top = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, REG0, mem_opnd(64, REG1, i * SIZEOF_VALUE));
        mov(cb, top, REG0);
    }

    return YJIT_KEEP_COMPILING;
}

// new hash initialized from top N values
static codegen_status_t
gen_newhash(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t num = (int32_t)jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, REG0);

    if (num) {
        // val = rb_hash_new_with_size(num / 2);
        mov(cb, C_ARG_REGS[0], imm_opnd(num / 2));
        call_ptr(cb, REG0, (void *)rb_hash_new_with_size);

        // save the allocated hash as we want to push it after insertion
        push(cb, RAX);
        push(cb, RAX); // alignment

        // rb_hash_bulk_insert(num, STACK_ADDR_FROM_TOP(num), val);
        mov(cb, C_ARG_REGS[0], imm_opnd(num));
        lea(cb, C_ARG_REGS[1], ctx_stack_opnd(ctx, num - 1));
        mov(cb, C_ARG_REGS[2], RAX);
        call_ptr(cb, REG0, (void *)rb_hash_bulk_insert);

        pop(cb, RAX); // alignment
        pop(cb, RAX);

        ctx_stack_pop(ctx, num);
        x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_HASH);
        mov(cb, stack_ret, RAX);
    }
    else {
        // val = rb_hash_new();
        call_ptr(cb, REG0, (void *)rb_hash_new);

        x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_HASH);
        mov(cb, stack_ret, RAX);
    }

    return YJIT_KEEP_COMPILING;
}

// Push a constant value to the stack, including type information.
// The constant may be a heap object or a special constant.
static void
jit_putobject(jitstate_t *jit, ctx_t *ctx, VALUE arg)
{
    val_type_t val_type = yjit_type_of_value(arg);
    x86opnd_t stack_top = ctx_stack_push(ctx, val_type);

    if (SPECIAL_CONST_P(arg)) {
        // Immediates will not move and do not need to be tracked for GC
        // Thanks to this we can mov directly to memory when possible.

        // NOTE: VALUE -> int64_t cast below is implementation defined.
        // Hopefully it preserves the the bit pattern or raise a signal.
        // See N1256 section 6.3.1.3.
        x86opnd_t imm = imm_opnd((int64_t)arg);

        // 64-bit immediates can't be directly written to memory
        if (imm.num_bits <= 32) {
            mov(cb, stack_top, imm);
        }
        else {
            mov(cb, REG0, imm);
            mov(cb, stack_top, REG0);
        }
    }
    else {
        // Load the value to push into REG0
        // Note that this value may get moved by the GC
        jit_mov_gc_ptr(jit, cb, REG0, arg);

        // Write argument at SP
        mov(cb, stack_top, REG0);
    }
}

static codegen_status_t
gen_putnil(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    jit_putobject(jit, ctx, Qnil);
    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putobject(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    VALUE arg = jit_get_arg(jit, 0);

    jit_putobject(jit, ctx, arg);
    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putstring(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    VALUE put_val = jit_get_arg(jit, 0);

    // Save the PC and SP because the callee will allocate
    jit_prepare_routine_call(jit, ctx, REG0);

    mov(cb, C_ARG_REGS[0], REG_EC);
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[1], put_val);
    call_ptr(cb, REG0, (void *)rb_ec_str_resurrect);

    x86opnd_t stack_top = ctx_stack_push(ctx, TYPE_STRING);
    mov(cb, stack_top, RAX);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putobject_int2fix(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int opcode = jit_get_opcode(jit);
    int cst_val = (opcode == BIN(putobject_INT2FIX_0_))? 0:1;

    jit_putobject(jit, ctx, INT2FIX(cst_val));
    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putself(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Load self from CFP
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, self));

    // Write it on the stack
    x86opnd_t stack_top = ctx_stack_push_self(ctx);
    mov(cb, stack_top, REG0);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_putspecialobject(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    enum vm_special_object_type type = (enum vm_special_object_type)jit_get_arg(jit, 0);

    if (type == VM_SPECIAL_OBJECT_VMCORE) {
        x86opnd_t stack_top = ctx_stack_push(ctx, TYPE_HEAP);
        jit_mov_gc_ptr(jit, cb, REG0, rb_mRubyVMFrozenCore);
        mov(cb, stack_top, REG0);
        return YJIT_KEEP_COMPILING;
    }
    else {
        // TODO: implement for VM_SPECIAL_OBJECT_CBASE and
        // VM_SPECIAL_OBJECT_CONST_BASE
        return YJIT_CANT_COMPILE;
    }
}

// Get EP at level from CFP
static void
gen_get_ep(codeblock_t *cb, x86opnd_t reg, uint32_t level)
{
    // Load environment pointer EP from CFP
    mov(cb, reg, member_opnd(REG_CFP, rb_control_frame_t, ep));

    while (level--) {
        // Get the previous EP from the current EP
        // See GET_PREV_EP(ep) macro
        // VALUE *prev_ep = ((VALUE *)((ep)[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03))
        mov(cb, reg, mem_opnd(64, REG0, SIZEOF_VALUE * VM_ENV_DATA_INDEX_SPECVAL));
        and(cb, reg, imm_opnd(~0x03));
    }
}

// Compute the index of a local variable from its slot index
static uint32_t
slot_to_local_idx(const rb_iseq_t *iseq, int32_t slot_idx)
{
    // Convoluted rules from local_var_name() in iseq.c
    int32_t local_table_size = iseq->body->local_table_size;
    int32_t op = slot_idx - VM_ENV_DATA_SIZE;
    int32_t local_idx = local_idx = local_table_size - op - 1;
    RUBY_ASSERT(local_idx >= 0 && local_idx < local_table_size);
    return (uint32_t)local_idx;
}

static codegen_status_t
gen_getlocal_wc0(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Compute the offset from BP to the local
    int32_t slot_idx = (int32_t)jit_get_arg(jit, 0);
    const int32_t offs = -(SIZEOF_VALUE * slot_idx);
    uint32_t local_idx = slot_to_local_idx(jit->iseq, slot_idx);

    // Load environment pointer EP (level 0) from CFP
    gen_get_ep(cb, REG0, 0);

    // Load the local from the EP
    mov(cb, REG0, mem_opnd(64, REG0, offs));

    // Write the local at SP
    x86opnd_t stack_top = ctx_stack_push_local(ctx, local_idx);
    mov(cb, stack_top, REG0);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_getlocal_generic(ctx_t *ctx, uint32_t local_idx, uint32_t level)
{
    gen_get_ep(cb, REG0, level);

    // Load the local from the block
    // val = *(vm_get_ep(GET_EP(), level) - idx);
    const int32_t offs = -(SIZEOF_VALUE * local_idx);
    mov(cb, REG0, mem_opnd(64, REG0, offs));

    // Write the local at SP
    x86opnd_t stack_top = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, stack_top, REG0);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_getlocal(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t idx = (int32_t)jit_get_arg(jit, 0);
    int32_t level = (int32_t)jit_get_arg(jit, 1);
    return gen_getlocal_generic(ctx, idx, level);
}

static codegen_status_t
gen_getlocal_wc1(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t idx = (int32_t)jit_get_arg(jit, 0);
    return gen_getlocal_generic(ctx, idx, 1);
}

static codegen_status_t
gen_setlocal_wc0(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    /*
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
    */

    int32_t slot_idx = (int32_t)jit_get_arg(jit, 0);
    uint32_t local_idx = slot_to_local_idx(jit->iseq, slot_idx);

    // Load environment pointer EP (level 0) from CFP
    gen_get_ep(cb, REG0, 0);

    // flags & VM_ENV_FLAG_WB_REQUIRED
    x86opnd_t flags_opnd = mem_opnd(64, REG0, sizeof(VALUE) * VM_ENV_DATA_INDEX_FLAGS);
    test(cb, flags_opnd, imm_opnd(VM_ENV_FLAG_WB_REQUIRED));

    // Create a side-exit to fall back to the interpreter
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    jnz_ptr(cb, side_exit);

    // Set the type of the local variable in the context
    val_type_t temp_type = ctx_get_opnd_type(ctx, OPND_STACK(0));
    ctx_set_local_type(ctx, local_idx, temp_type);

    // Pop the value to write from the stack
    x86opnd_t stack_top = ctx_stack_pop(ctx, 1);
    mov(cb, REG1, stack_top);

    // Write the value at the environment pointer
    const int32_t offs = -8 * slot_idx;
    mov(cb, mem_opnd(64, REG0, offs), REG1);

    return YJIT_KEEP_COMPILING;
}

// Push Qtrue or Qfalse depending on whether the given keyword was supplied by
// the caller
static codegen_status_t
gen_checkkeyword(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // When a keyword is unspecified past index 32, a hash will be used
    // instead. This can only happen in iseqs taking more than 32 keywords.
    if (jit->iseq->body->param.keyword->num >= 32) {
        return YJIT_CANT_COMPILE;
    }

    // The EP offset to the undefined bits local
    int32_t bits_offset = (int32_t)jit_get_arg(jit, 0);

    // The index of the keyword we want to check
    int32_t index = (int32_t)jit_get_arg(jit, 1);

    // Load environment pointer EP
    gen_get_ep(cb, REG0, 0);

    // VALUE kw_bits = *(ep - bits);
    x86opnd_t bits_opnd = mem_opnd(64, REG0, sizeof(VALUE) * -bits_offset);

    // unsigned int b = (unsigned int)FIX2ULONG(kw_bits);
    // if ((b & (0x01 << idx))) {
    //
    // We can skip the FIX2ULONG conversion by shifting the bit we test
    int64_t bit_test = 0x01 << (index + 1);
    test(cb, bits_opnd, imm_opnd(bit_test));
    mov(cb, REG0, imm_opnd(Qfalse));
    mov(cb, REG1, imm_opnd(Qtrue));
    cmovz(cb, REG0, REG1);

    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_IMM);
    mov(cb, stack_ret, REG0);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_setlocal_generic(jitstate_t *jit, ctx_t *ctx, uint32_t local_idx, uint32_t level)
{
    // Load environment pointer EP at level
    gen_get_ep(cb, REG0, level);

    // flags & VM_ENV_FLAG_WB_REQUIRED
    x86opnd_t flags_opnd = mem_opnd(64, REG0, sizeof(VALUE) * VM_ENV_DATA_INDEX_FLAGS);
    test(cb, flags_opnd, imm_opnd(VM_ENV_FLAG_WB_REQUIRED));

    // Create a side-exit to fall back to the interpreter
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    jnz_ptr(cb, side_exit);

    // Pop the value to write from the stack
    x86opnd_t stack_top = ctx_stack_pop(ctx, 1);
    mov(cb, REG1, stack_top);

    // Write the value at the environment pointer
    const int32_t offs = -(SIZEOF_VALUE * local_idx);
    mov(cb, mem_opnd(64, REG0, offs), REG1);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_setlocal(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t idx = (int32_t)jit_get_arg(jit, 0);
    int32_t level = (int32_t)jit_get_arg(jit, 1);
    return gen_setlocal_generic(jit, ctx, idx, level);
}

static codegen_status_t
gen_setlocal_wc1(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t idx = (int32_t)jit_get_arg(jit, 0);
    return gen_setlocal_generic(jit, ctx, idx, 1);
}

static void
gen_jnz_to_target0(codeblock_t *cb, uint8_t *target0, uint8_t *target1, uint8_t shape)
{
    switch (shape) {
      case SHAPE_NEXT0:
      case SHAPE_NEXT1:
        RUBY_ASSERT(false);
        break;

      case SHAPE_DEFAULT:
        jnz_ptr(cb, target0);
        break;
    }
}

static void
gen_jz_to_target0(codeblock_t *cb, uint8_t *target0, uint8_t *target1, uint8_t shape)
{
    switch (shape) {
      case SHAPE_NEXT0:
      case SHAPE_NEXT1:
        RUBY_ASSERT(false);
        break;

      case SHAPE_DEFAULT:
        jz_ptr(cb, target0);
        break;
    }
}

static void
gen_jbe_to_target0(codeblock_t *cb, uint8_t *target0, uint8_t *target1, uint8_t shape)
{
    switch (shape) {
      case SHAPE_NEXT0:
      case SHAPE_NEXT1:
        RUBY_ASSERT(false);
        break;

      case SHAPE_DEFAULT:
        jbe_ptr(cb, target0);
        break;
    }
}

enum jcc_kinds {
    JCC_JNE,
    JCC_JNZ,
    JCC_JZ,
    JCC_JE,
    JCC_JBE,
    JCC_JNA,
};

// Generate a jump to a stub that recompiles the current YARV instruction on failure.
// When depth_limitk is exceeded, generate a jump to a side exit.
static void
jit_chain_guard(enum jcc_kinds jcc, jitstate_t *jit, const ctx_t *ctx, uint8_t depth_limit, uint8_t *side_exit)
{
    branchgen_fn target0_gen_fn;

    switch (jcc) {
      case JCC_JNE:
      case JCC_JNZ:
        target0_gen_fn = gen_jnz_to_target0;
        break;
      case JCC_JZ:
      case JCC_JE:
        target0_gen_fn = gen_jz_to_target0;
        break;
      case JCC_JBE:
      case JCC_JNA:
        target0_gen_fn = gen_jbe_to_target0;
        break;
      default:
        rb_bug("yjit: unimplemented jump kind");
        break;
    };

    if (ctx->chain_depth < depth_limit) {
        ctx_t deeper = *ctx;
        deeper.chain_depth++;

        gen_branch(
            jit,
            ctx,
            (blockid_t) { jit->iseq, jit->insn_idx },
            &deeper,
            BLOCKID_NULL,
            NULL,
            target0_gen_fn
        );
    }
    else {
        target0_gen_fn(cb, side_exit, NULL, SHAPE_DEFAULT);
    }
}

enum {
    GETIVAR_MAX_DEPTH = 10,       // up to 5 different classes, and embedded or not for each
    OPT_AREF_MAX_CHAIN_DEPTH = 2, // hashes and arrays
    SEND_MAX_DEPTH = 5,           // up to 5 different classes
};

VALUE rb_vm_set_ivar_idx(VALUE obj, uint32_t idx, VALUE val);

// Codegen for setting an instance variable.
// Preconditions:
//   - receiver is in REG0
//   - receiver has the same class as CLASS_OF(comptime_receiver)
//   - no stack push or pops to ctx since the entry to the codegen of the instruction being compiled
static codegen_status_t
gen_set_ivar(jitstate_t *jit, ctx_t *ctx, VALUE recv, VALUE klass, ID ivar_name)
{
    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, REG0);

    // Get the operands from the stack
    x86opnd_t val_opnd = ctx_stack_pop(ctx, 1);
    x86opnd_t recv_opnd = ctx_stack_pop(ctx, 1);

    uint32_t ivar_index = rb_obj_ensure_iv_index_mapping(recv, ivar_name);

    // Call rb_vm_set_ivar_idx with the receiver, the index of the ivar, and the value
    mov(cb, C_ARG_REGS[0], recv_opnd);
    mov(cb, C_ARG_REGS[1], imm_opnd(ivar_index));
    mov(cb, C_ARG_REGS[2], val_opnd);
    call_ptr(cb, REG0, (void *)rb_vm_set_ivar_idx);

    x86opnd_t out_opnd = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, out_opnd, RAX);

    return YJIT_KEEP_COMPILING;
}

// Codegen for getting an instance variable.
// Preconditions:
//   - receiver is in REG0
//   - receiver has the same class as CLASS_OF(comptime_receiver)
//   - no stack push or pops to ctx since the entry to the codegen of the instruction being compiled
static codegen_status_t
gen_get_ivar(jitstate_t *jit, ctx_t *ctx, const int max_chain_depth, VALUE comptime_receiver, ID ivar_name, insn_opnd_t reg0_opnd, uint8_t *side_exit)
{
    VALUE comptime_val_klass = CLASS_OF(comptime_receiver);
    const ctx_t starting_context = *ctx; // make a copy for use with jit_chain_guard

    // If the class uses the default allocator, instances should all be T_OBJECT
    // NOTE: This assumes nobody changes the allocator of the class after allocation.
    //       Eventually, we can encode whether an object is T_OBJECT or not
    //       inside object shapes.
    if (!RB_TYPE_P(comptime_receiver, T_OBJECT) ||
            rb_get_alloc_func(comptime_val_klass) != rb_class_allocate_instance) {
        // General case. Call rb_ivar_get().
        // VALUE rb_ivar_get(VALUE obj, ID id)
        ADD_COMMENT(cb, "call rb_ivar_get()");

        // The function could raise exceptions.
        jit_prepare_routine_call(jit, ctx, REG1);

        mov(cb, C_ARG_REGS[0], REG0);
        mov(cb, C_ARG_REGS[1], imm_opnd((int64_t)ivar_name));
        call_ptr(cb, REG1, (void *)rb_ivar_get);

        if (!reg0_opnd.is_self) {
            (void)ctx_stack_pop(ctx, 1);
        }
        // Push the ivar on the stack
        x86opnd_t out_opnd = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, out_opnd, RAX);

        // Jump to next instruction. This allows guard chains to share the same successor.
        jit_jump_to_next_insn(jit, ctx);
        return YJIT_END_BLOCK;
    }

    /*
    // FIXME:
    // This check was added because of a failure in a test involving the
    // Nokogiri Document class where we see a T_DATA that still has the default
    // allocator.
    // Aaron Patterson argues that this is a bug in the C extension, because
    // people could call .allocate() on the class and still get a T_OBJECT
    // For now I added an extra dynamic check that the receiver is T_OBJECT
    // so we can safely pass all the tests in Shopify Core.
    //
    // Guard that the receiver is T_OBJECT
    // #define RB_BUILTIN_TYPE(x) (int)(((struct RBasic*)(x))->flags & RUBY_T_MASK)
    ADD_COMMENT(cb, "guard receiver is T_OBJECT");
    mov(cb, REG1, member_opnd(REG0, struct RBasic, flags));
    and(cb, REG1, imm_opnd(RUBY_T_MASK));
    cmp(cb, REG1, imm_opnd(T_OBJECT));
    jit_chain_guard(JCC_JNE, jit, &starting_context, max_chain_depth, side_exit);
    */

    // FIXME: Mapping the index could fail when there is too many ivar names. If we're
    // compiling for a branch stub that can cause the exception to be thrown from the
    // wrong PC.
    uint32_t ivar_index = rb_obj_ensure_iv_index_mapping(comptime_receiver, ivar_name);

    // Pop receiver if it's on the temp stack
    if (!reg0_opnd.is_self) {
        (void)ctx_stack_pop(ctx, 1);
    }

    // Compile time self is embedded and the ivar index lands within the object
    if (RB_FL_TEST_RAW(comptime_receiver, ROBJECT_EMBED) && ivar_index < ROBJECT_EMBED_LEN_MAX) {
        // See ROBJECT_IVPTR() from include/ruby/internal/core/robject.h

        // Guard that self is embedded
        // TODO: BT and JC is shorter
        ADD_COMMENT(cb, "guard embedded getivar");
        x86opnd_t flags_opnd = member_opnd(REG0, struct RBasic, flags);
        test(cb, flags_opnd, imm_opnd(ROBJECT_EMBED));
        jit_chain_guard(JCC_JZ, jit, &starting_context, max_chain_depth, COUNTED_EXIT(jit, side_exit, getivar_megamorphic));

        // Load the variable
        x86opnd_t ivar_opnd = mem_opnd(64, REG0, offsetof(struct RObject, as.ary) + ivar_index * SIZEOF_VALUE);
        mov(cb, REG1, ivar_opnd);

        // Guard that the variable is not Qundef
        cmp(cb, REG1, imm_opnd(Qundef));
        mov(cb, REG0, imm_opnd(Qnil));
        cmove(cb, REG1, REG0);

        // Push the ivar on the stack
        x86opnd_t out_opnd = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, out_opnd, REG1);
    }
    else {
        // Compile time value is *not* embedded.

        // Guard that value is *not* embedded
        // See ROBJECT_IVPTR() from include/ruby/internal/core/robject.h
        ADD_COMMENT(cb, "guard extended getivar");
        x86opnd_t flags_opnd = member_opnd(REG0, struct RBasic, flags);
        test(cb, flags_opnd, imm_opnd(ROBJECT_EMBED));
        jit_chain_guard(JCC_JNZ, jit, &starting_context, max_chain_depth, COUNTED_EXIT(jit, side_exit, getivar_megamorphic));

        // check that the extended table is big enough
        if (ivar_index >= ROBJECT_EMBED_LEN_MAX + 1) {
            // Check that the slot is inside the extended table (num_slots > index)
            x86opnd_t num_slots = mem_opnd(32, REG0, offsetof(struct RObject, as.heap.numiv));
            cmp(cb, num_slots, imm_opnd(ivar_index));
            jle_ptr(cb, COUNTED_EXIT(jit, side_exit, getivar_idx_out_of_range));
        }

        // Get a pointer to the extended table
        x86opnd_t tbl_opnd = mem_opnd(64, REG0, offsetof(struct RObject, as.heap.ivptr));
        mov(cb, REG0, tbl_opnd);

        // Read the ivar from the extended table
        x86opnd_t ivar_opnd = mem_opnd(64, REG0, sizeof(VALUE) * ivar_index);
        mov(cb, REG0, ivar_opnd);

        // Check that the ivar is not Qundef
        cmp(cb, REG0, imm_opnd(Qundef));
        mov(cb, REG1, imm_opnd(Qnil));
        cmove(cb, REG0, REG1);

        // Push the ivar on the stack
        x86opnd_t out_opnd = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, out_opnd, REG0);
    }

    // Jump to next instruction. This allows guard chains to share the same successor.
    jit_jump_to_next_insn(jit, ctx);
    return YJIT_END_BLOCK;
}

static codegen_status_t
gen_getinstancevariable(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Defer compilation so we can specialize on a runtime `self`
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    ID ivar_name = (ID)jit_get_arg(jit, 0);

    VALUE comptime_val = jit_peek_at_self(jit, ctx);
    VALUE comptime_val_klass = CLASS_OF(comptime_val);

    // Generate a side exit
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // Guard that the receiver has the same class as the one from compile time.
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, self));

    jit_guard_known_klass(jit, ctx, comptime_val_klass, OPND_SELF, comptime_val, GETIVAR_MAX_DEPTH, side_exit);

    return gen_get_ivar(jit, ctx, GETIVAR_MAX_DEPTH, comptime_val, ivar_name, OPND_SELF, side_exit);
}

void rb_vm_setinstancevariable(const rb_iseq_t *iseq, VALUE obj, ID id, VALUE val, IVC ic);

static codegen_status_t
gen_setinstancevariable(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    ID id = (ID)jit_get_arg(jit, 0);
    IVC ic = (IVC)jit_get_arg(jit, 1);

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, REG0);

    // Get the operands from the stack
    x86opnd_t val_opnd = ctx_stack_pop(ctx, 1);

    // Call rb_vm_setinstancevariable(iseq, obj, id, val, ic);
    mov(cb, C_ARG_REGS[1], member_opnd(REG_CFP, rb_control_frame_t, self));
    mov(cb, C_ARG_REGS[3], val_opnd);
    mov(cb, C_ARG_REGS[2], imm_opnd(id));
    mov(cb, C_ARG_REGS[4], const_ptr_opnd(ic));
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], (VALUE)jit->iseq);
    call_ptr(cb, REG0, (void *)rb_vm_setinstancevariable);

    return YJIT_KEEP_COMPILING;
}

bool rb_vm_defined(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t op_type, VALUE obj, VALUE v);

static codegen_status_t
gen_defined(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    rb_num_t op_type = (rb_num_t)jit_get_arg(jit, 0);
    VALUE obj = (VALUE)jit_get_arg(jit, 1);
    VALUE pushval = (VALUE)jit_get_arg(jit, 2);

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, REG0);

    // Get the operands from the stack
    x86opnd_t v_opnd = ctx_stack_pop(ctx, 1);

    // Call vm_defined(ec, reg_cfp, op_type, obj, v)
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(cb, C_ARG_REGS[1], REG_CFP);
    mov(cb, C_ARG_REGS[2], imm_opnd(op_type));
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[3], (VALUE)obj);
    mov(cb, C_ARG_REGS[4], v_opnd);
    call_ptr(cb, REG0, (void *)rb_vm_defined);

    // if (vm_defined(ec, GET_CFP(), op_type, obj, v)) {
    //  val = pushval;
    // }
    jit_mov_gc_ptr(jit, cb, REG1, (VALUE)pushval);
    cmp(cb, AL, imm_opnd(0));
    mov(cb, RAX, imm_opnd(Qnil));
    cmovnz(cb, RAX, REG1);

    // Push the return value onto the stack
    val_type_t out_type = SPECIAL_CONST_P(pushval)? TYPE_IMM:TYPE_UNKNOWN;
    x86opnd_t stack_ret = ctx_stack_push(ctx, out_type);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_checktype(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    enum ruby_value_type type_val = (enum ruby_value_type)jit_get_arg(jit, 0);
    // Only three types are emitted by compile.c
    if (type_val == T_STRING || type_val == T_ARRAY || type_val == T_HASH) {
        val_type_t val_type = ctx_get_opnd_type(ctx, OPND_STACK(0));
        x86opnd_t val = ctx_stack_pop(ctx, 1);

        x86opnd_t stack_ret;

        // Check if we know from type information
        if ((type_val == T_STRING && val_type.type == ETYPE_STRING) ||
                (type_val == T_ARRAY && val_type.type == ETYPE_ARRAY) ||
                (type_val == T_HASH && val_type.type == ETYPE_HASH)) {
            // guaranteed type match
            stack_ret = ctx_stack_push(ctx, TYPE_TRUE);
            mov(cb, stack_ret, imm_opnd(Qtrue));
            return YJIT_KEEP_COMPILING;
        }
        else if (val_type.is_imm || val_type.type != ETYPE_UNKNOWN) {
            // guaranteed not to match T_STRING/T_ARRAY/T_HASH
            stack_ret = ctx_stack_push(ctx, TYPE_FALSE);
            mov(cb, stack_ret, imm_opnd(Qfalse));
            return YJIT_KEEP_COMPILING;
        }

        mov(cb, REG0, val);
        mov(cb, REG1, imm_opnd(Qfalse));

        uint32_t ret = cb_new_label(cb, "ret");

        if (!val_type.is_heap) {
            // if (SPECIAL_CONST_P(val)) {
            // Return Qfalse via REG1 if not on heap
            test(cb, REG0, imm_opnd(RUBY_IMMEDIATE_MASK));
            jnz_label(cb, ret);
            cmp(cb, REG0, imm_opnd(Qnil));
            jbe_label(cb, ret);
        }

        // Check type on object
        mov(cb, REG0, mem_opnd(64, REG0, offsetof(struct RBasic, flags)));
        and(cb, REG0, imm_opnd(RUBY_T_MASK));
        cmp(cb, REG0, imm_opnd(type_val));
        mov(cb, REG0, imm_opnd(Qtrue));
        // REG1 contains Qfalse from above
        cmove(cb, REG1, REG0);

        cb_write_label(cb, ret);
        stack_ret = ctx_stack_push(ctx, TYPE_IMM);
        mov(cb, stack_ret, REG1);
        cb_link_labels(cb);

        return YJIT_KEEP_COMPILING;
    }
    else {
        return YJIT_CANT_COMPILE;
    }
}

static codegen_status_t
gen_concatstrings(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    rb_num_t n = (rb_num_t)jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, REG0);

    x86opnd_t values_ptr = ctx_sp_opnd(ctx, -(sizeof(VALUE) * (uint32_t)n));

    // call rb_str_concat_literals(long n, const VALUE *strings);
    mov(cb, C_ARG_REGS[0], imm_opnd(n));
    lea(cb, C_ARG_REGS[1], values_ptr);
    call_ptr(cb, REG0, (void *)rb_str_concat_literals);

    ctx_stack_pop(ctx, n);
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_STRING);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

static void
guard_two_fixnums(ctx_t *ctx, uint8_t *side_exit)
{
    // Get the stack operand types
    val_type_t arg1_type = ctx_get_opnd_type(ctx, OPND_STACK(0));
    val_type_t arg0_type = ctx_get_opnd_type(ctx, OPND_STACK(1));

    if (arg0_type.is_heap || arg1_type.is_heap) {
        jmp_ptr(cb, side_exit);
        return;
    }

    if (arg0_type.type != ETYPE_FIXNUM && arg0_type.type != ETYPE_UNKNOWN) {
        jmp_ptr(cb, side_exit);
        return;
    }

    if (arg1_type.type != ETYPE_FIXNUM && arg1_type.type != ETYPE_UNKNOWN) {
        jmp_ptr(cb, side_exit);
        return;
    }

    RUBY_ASSERT(!arg0_type.is_heap);
    RUBY_ASSERT(!arg1_type.is_heap);
    RUBY_ASSERT(arg0_type.type == ETYPE_FIXNUM || arg0_type.type == ETYPE_UNKNOWN);
    RUBY_ASSERT(arg1_type.type == ETYPE_FIXNUM || arg1_type.type == ETYPE_UNKNOWN);

    // Get stack operands without popping them
    x86opnd_t arg1 = ctx_stack_opnd(ctx, 0);
    x86opnd_t arg0 = ctx_stack_opnd(ctx, 1);

    // If not fixnums, fall back
    if (arg0_type.type != ETYPE_FIXNUM) {
        ADD_COMMENT(cb, "guard arg0 fixnum");
        test(cb, arg0, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, side_exit);
    }
    if (arg1_type.type != ETYPE_FIXNUM) {
        ADD_COMMENT(cb, "guard arg1 fixnum");
        test(cb, arg1, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, side_exit);
    }

    // Set stack types in context
    ctx_upgrade_opnd_type(ctx, OPND_STACK(0), TYPE_FIXNUM);
    ctx_upgrade_opnd_type(ctx, OPND_STACK(1), TYPE_FIXNUM);
}

// Conditional move operation used by comparison operators
typedef void (*cmov_fn)(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);

static codegen_status_t
gen_fixnum_cmp(jitstate_t *jit, ctx_t *ctx, cmov_fn cmov_op)
{
    // Defer compilation so we can specialize base on a runtime receiver
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    VALUE comptime_a = jit_peek_at_stack(jit, ctx, 1);
    VALUE comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if (FIXNUM_P(comptime_a) && FIXNUM_P(comptime_b)) {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        if (!assume_bop_not_redefined(jit, INTEGER_REDEFINED_OP_FLAG, BOP_LT)) {
            return YJIT_CANT_COMPILE;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, side_exit);

        // Get the operands from the stack
        x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
        x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

        // Compare the arguments
        xor(cb, REG0_32, REG0_32); // REG0 = Qfalse
        mov(cb, REG1, arg0);
        cmp(cb, REG1, arg1);
        mov(cb, REG1, imm_opnd(Qtrue));
        cmov_op(cb, REG0, REG1);

        // Push the output on the stack
        x86opnd_t dst = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, dst, REG0);

        return YJIT_KEEP_COMPILING;
    }
    else {
        return gen_opt_send_without_block(jit, ctx, cb);
    }
}

static codegen_status_t
gen_opt_lt(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    return gen_fixnum_cmp(jit, ctx, cmovl);
}

static codegen_status_t
gen_opt_le(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    return gen_fixnum_cmp(jit, ctx, cmovle);
}

static codegen_status_t
gen_opt_ge(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    return gen_fixnum_cmp(jit, ctx, cmovge);
}

static codegen_status_t
gen_opt_gt(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    return gen_fixnum_cmp(jit, ctx, cmovg);
}

// Implements specialized equality for either two fixnum or two strings
// Returns true if code was generated, otherwise false
static bool
gen_equality_specialized(jitstate_t *jit, ctx_t *ctx, uint8_t *side_exit)
{
    VALUE comptime_a = jit_peek_at_stack(jit, ctx, 1);
    VALUE comptime_b = jit_peek_at_stack(jit, ctx, 0);

    x86opnd_t a_opnd = ctx_stack_opnd(ctx, 1);
    x86opnd_t b_opnd = ctx_stack_opnd(ctx, 0);

    if (FIXNUM_P(comptime_a) && FIXNUM_P(comptime_b)) {
        if (!assume_bop_not_redefined(jit, INTEGER_REDEFINED_OP_FLAG, BOP_EQ)) {
            // if overridden, emit the generic version
            return false;
        }

        guard_two_fixnums(ctx, side_exit);

        mov(cb, REG0, a_opnd);
        cmp(cb, REG0, b_opnd);

        mov(cb, REG0, imm_opnd(Qfalse));
        mov(cb, REG1, imm_opnd(Qtrue));
        cmove(cb, REG0, REG1);

        // Push the output on the stack
        ctx_stack_pop(ctx, 2);
        x86opnd_t dst = ctx_stack_push(ctx, TYPE_IMM);
        mov(cb, dst, REG0);

        return true;
    }
    else if (CLASS_OF(comptime_a) == rb_cString &&
            CLASS_OF(comptime_b) == rb_cString) {
        if (!assume_bop_not_redefined(jit, STRING_REDEFINED_OP_FLAG, BOP_EQ)) {
            // if overridden, emit the generic version
            return false;
        }

        // Load a and b in preparation for call later
        mov(cb, C_ARG_REGS[0], a_opnd);
        mov(cb, C_ARG_REGS[1], b_opnd);

        // Guard that a is a String
        mov(cb, REG0, C_ARG_REGS[0]);
        jit_guard_known_klass(jit, ctx, rb_cString, OPND_STACK(1), comptime_a, SEND_MAX_DEPTH, side_exit);

        uint32_t ret = cb_new_label(cb, "ret");

        // If they are equal by identity, return true
        cmp(cb, C_ARG_REGS[0], C_ARG_REGS[1]);
        mov(cb, RAX, imm_opnd(Qtrue));
        je_label(cb, ret);

        // Otherwise guard that b is a T_STRING (from type info) or String (from runtime guard)
        if (ctx_get_opnd_type(ctx, OPND_STACK(0)).type != ETYPE_STRING) {
            mov(cb, REG0, C_ARG_REGS[1]);
            // Note: any T_STRING is valid here, but we check for a ::String for simplicity
            jit_guard_known_klass(jit, ctx, rb_cString, OPND_STACK(0), comptime_b, SEND_MAX_DEPTH, side_exit);
        }

        // Call rb_str_eql_internal(a, b)
        call_ptr(cb, REG0, (void *)rb_str_eql_internal);

        // Push the output on the stack
        cb_write_label(cb, ret);
        ctx_stack_pop(ctx, 2);
        x86opnd_t dst = ctx_stack_push(ctx, TYPE_IMM);
        mov(cb, dst, RAX);
        cb_link_labels(cb);

        return true;
    }
    else {
        return false;
    }
}

static codegen_status_t
gen_opt_eq(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Defer compilation so we can specialize base on a runtime receiver
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    // Create a side-exit to fall back to the interpreter
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    if (gen_equality_specialized(jit, ctx, side_exit)) {
        jit_jump_to_next_insn(jit, ctx);
        return YJIT_END_BLOCK;
    }
    else {
        return gen_opt_send_without_block(jit, ctx, cb);
    }
}

static codegen_status_t gen_send_general(jitstate_t *jit, ctx_t *ctx, struct rb_call_data *cd, rb_iseq_t *block);

static codegen_status_t
gen_opt_neq(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // opt_neq is passed two rb_call_data as arguments:
    // first for ==, second for !=
    struct rb_call_data *cd = (struct rb_call_data *)jit_get_arg(jit, 1);
    return gen_send_general(jit, ctx, cd, NULL);
}

static codegen_status_t
gen_opt_aref(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    struct rb_call_data * cd = (struct rb_call_data *)jit_get_arg(jit, 0);
    int32_t argc = (int32_t)vm_ci_argc(cd->ci);

    // Only JIT one arg calls like `ary[6]`
    if (argc != 1) {
        GEN_COUNTER_INC(cb, oaref_argc_not_one);
        return YJIT_CANT_COMPILE;
    }

    // Defer compilation so we can specialize base on a runtime receiver
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    // Remember the context on entry for adding guard chains
    const ctx_t starting_context = *ctx;

    // Specialize base on compile time values
    VALUE comptime_idx = jit_peek_at_stack(jit, ctx, 0);
    VALUE comptime_recv = jit_peek_at_stack(jit, ctx, 1);

    // Create a side-exit to fall back to the interpreter
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    if (CLASS_OF(comptime_recv) == rb_cArray && RB_FIXNUM_P(comptime_idx)) {
        if (!assume_bop_not_redefined(jit, ARRAY_REDEFINED_OP_FLAG, BOP_AREF)) {
            return YJIT_CANT_COMPILE;
        }

        // Pop the stack operands
        x86opnd_t idx_opnd = ctx_stack_pop(ctx, 1);
        x86opnd_t recv_opnd = ctx_stack_pop(ctx, 1);
        mov(cb, REG0, recv_opnd);

        // if (SPECIAL_CONST_P(recv)) {
        // Bail if receiver is not a heap object
        test(cb, REG0, imm_opnd(RUBY_IMMEDIATE_MASK));
        jnz_ptr(cb, side_exit);
        cmp(cb, REG0, imm_opnd(Qfalse));
        je_ptr(cb, side_exit);
        cmp(cb, REG0, imm_opnd(Qnil));
        je_ptr(cb, side_exit);

        // Bail if recv has a class other than ::Array.
        // BOP_AREF check above is only good for ::Array.
        mov(cb, REG1, mem_opnd(64, REG0, offsetof(struct RBasic, klass)));
        mov(cb, REG0, const_ptr_opnd((void *)rb_cArray));
        cmp(cb, REG0, REG1);
        jit_chain_guard(JCC_JNE, jit, &starting_context, OPT_AREF_MAX_CHAIN_DEPTH, side_exit);

        // Bail if idx is not a FIXNUM
        mov(cb, REG1, idx_opnd);
        test(cb, REG1, imm_opnd(RUBY_FIXNUM_FLAG));
        jz_ptr(cb, COUNTED_EXIT(jit, side_exit, oaref_arg_not_fixnum));

        // Call VALUE rb_ary_entry_internal(VALUE ary, long offset).
        // It never raises or allocates, so we don't need to write to cfp->pc.
        {
            mov(cb, RDI, recv_opnd);
            sar(cb, REG1, imm_opnd(1)); // Convert fixnum to int
            mov(cb, RSI, REG1);
            call_ptr(cb, REG0, (void *)rb_ary_entry_internal);

            // Push the return value onto the stack
            x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
            mov(cb, stack_ret, RAX);
        }

        // Jump to next instruction. This allows guard chains to share the same successor.
        jit_jump_to_next_insn(jit, ctx);
        return YJIT_END_BLOCK;
    }
    else if (CLASS_OF(comptime_recv) == rb_cHash) {
        if (!assume_bop_not_redefined(jit, HASH_REDEFINED_OP_FLAG, BOP_AREF)) {
            return YJIT_CANT_COMPILE;
        }

        x86opnd_t key_opnd = ctx_stack_opnd(ctx, 0);
        x86opnd_t recv_opnd = ctx_stack_opnd(ctx, 1);

        // Guard that the receiver is a hash
        mov(cb, REG0, recv_opnd);
        jit_guard_known_klass(jit, ctx, rb_cHash, OPND_STACK(1), comptime_recv, OPT_AREF_MAX_CHAIN_DEPTH, side_exit);

        // Setup arguments for rb_hash_aref().
        mov(cb, C_ARG_REGS[0], REG0);
        mov(cb, C_ARG_REGS[1], key_opnd);

        // Prepare to call rb_hash_aref(). It might call #hash on the key.
        jit_prepare_routine_call(jit, ctx, REG0);

        call_ptr(cb, REG0, (void *)rb_hash_aref);

        // Pop the key and the receiver
        (void)ctx_stack_pop(ctx, 2);

        // Push the return value onto the stack
        x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, stack_ret, RAX);

        // Jump to next instruction. This allows guard chains to share the same successor.
        jit_jump_to_next_insn(jit, ctx);
        return YJIT_END_BLOCK;
    }
    else {
        // General case. Call the [] method.
        return gen_opt_send_without_block(jit, ctx, cb);
    }
}

static codegen_status_t
gen_opt_aset(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Defer compilation so we can specialize on a runtime `self`
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    VALUE comptime_recv = jit_peek_at_stack(jit, ctx, 2);
    VALUE comptime_key  = jit_peek_at_stack(jit, ctx, 1);

    // Get the operands from the stack
    x86opnd_t recv = ctx_stack_opnd(ctx, 2);
    x86opnd_t key = ctx_stack_opnd(ctx, 1);
    x86opnd_t val = ctx_stack_opnd(ctx, 0);

    if (CLASS_OF(comptime_recv) == rb_cArray && FIXNUM_P(comptime_key)) {
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        // Guard receiver is an Array
        mov(cb, REG0, recv);
        jit_guard_known_klass(jit, ctx, rb_cArray, OPND_STACK(2), comptime_recv, SEND_MAX_DEPTH, side_exit);

        // Guard key is a fixnum
        mov(cb, REG0, key);
        jit_guard_known_klass(jit, ctx, rb_cInteger, OPND_STACK(1), comptime_key, SEND_MAX_DEPTH, side_exit);

        // Call rb_ary_store
        mov(cb, C_ARG_REGS[0], recv);
        mov(cb, C_ARG_REGS[1], key);
        sar(cb, C_ARG_REGS[1], imm_opnd(1)); // FIX2LONG(key)
        mov(cb, C_ARG_REGS[2], val);

        // We might allocate or raise
        jit_prepare_routine_call(jit, ctx, REG0);

        call_ptr(cb, REG0, (void *)rb_ary_store);

        // rb_ary_store returns void
        // stored value should still be on stack
        mov(cb, REG0, ctx_stack_opnd(ctx, 0));

        // Push the return value onto the stack
        ctx_stack_pop(ctx, 3);
        x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, stack_ret, REG0);

        jit_jump_to_next_insn(jit, ctx);
        return YJIT_END_BLOCK;
    }
    else if (CLASS_OF(comptime_recv) == rb_cHash) {
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        // Guard receiver is a Hash
        mov(cb, REG0, recv);
        jit_guard_known_klass(jit, ctx, rb_cHash, OPND_STACK(2), comptime_recv, SEND_MAX_DEPTH, side_exit);

        // Call rb_hash_aset
        mov(cb, C_ARG_REGS[0], recv);
        mov(cb, C_ARG_REGS[1], key);
        mov(cb, C_ARG_REGS[2], val);

        // We might allocate or raise
        jit_prepare_routine_call(jit, ctx, REG0);

        call_ptr(cb, REG0, (void *)rb_hash_aset);

        // Push the return value onto the stack
        ctx_stack_pop(ctx, 3);
        x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, stack_ret, RAX);

        jit_jump_to_next_insn(jit, ctx);
        return YJIT_END_BLOCK;
    }
    else {
        return gen_opt_send_without_block(jit, ctx, cb);
    }
}

static codegen_status_t
gen_opt_and(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Defer compilation so we can specialize on a runtime `self`
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    VALUE comptime_a = jit_peek_at_stack(jit, ctx, 1);
    VALUE comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if (FIXNUM_P(comptime_a) && FIXNUM_P(comptime_b)) {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        if (!assume_bop_not_redefined(jit, INTEGER_REDEFINED_OP_FLAG, BOP_AND)) {
            return YJIT_CANT_COMPILE;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, side_exit);

        // Get the operands and destination from the stack
        x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
        x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

        // Do the bitwise and arg0 & arg1
        mov(cb, REG0, arg0);
        and(cb, REG0, arg1);

        // Push the output on the stack
        x86opnd_t dst = ctx_stack_push(ctx, TYPE_FIXNUM);
        mov(cb, dst, REG0);

        return YJIT_KEEP_COMPILING;
    }
    else {
        // Delegate to send, call the method on the recv
        return gen_opt_send_without_block(jit, ctx, cb);
    }
}

static codegen_status_t
gen_opt_or(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Defer compilation so we can specialize on a runtime `self`
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    VALUE comptime_a = jit_peek_at_stack(jit, ctx, 1);
    VALUE comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if (FIXNUM_P(comptime_a) && FIXNUM_P(comptime_b)) {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        if (!assume_bop_not_redefined(jit, INTEGER_REDEFINED_OP_FLAG, BOP_OR)) {
            return YJIT_CANT_COMPILE;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, side_exit);

        // Get the operands and destination from the stack
        x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
        x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

        // Do the bitwise or arg0 | arg1
        mov(cb, REG0, arg0);
        or(cb, REG0, arg1);

        // Push the output on the stack
        x86opnd_t dst = ctx_stack_push(ctx, TYPE_FIXNUM);
        mov(cb, dst, REG0);

        return YJIT_KEEP_COMPILING;
    }
    else {
        // Delegate to send, call the method on the recv
        return gen_opt_send_without_block(jit, ctx, cb);
    }
}

static codegen_status_t
gen_opt_minus(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Defer compilation so we can specialize on a runtime `self`
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    VALUE comptime_a = jit_peek_at_stack(jit, ctx, 1);
    VALUE comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if (FIXNUM_P(comptime_a) && FIXNUM_P(comptime_b)) {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        if (!assume_bop_not_redefined(jit, INTEGER_REDEFINED_OP_FLAG, BOP_MINUS)) {
            return YJIT_CANT_COMPILE;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, side_exit);

        // Get the operands and destination from the stack
        x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
        x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

        // Subtract arg0 - arg1 and test for overflow
        mov(cb, REG0, arg0);
        sub(cb, REG0, arg1);
        jo_ptr(cb, side_exit);
        add(cb, REG0, imm_opnd(1));

        // Push the output on the stack
        x86opnd_t dst = ctx_stack_push(ctx, TYPE_FIXNUM);
        mov(cb, dst, REG0);

        return YJIT_KEEP_COMPILING;
    }
    else {
        // Delegate to send, call the method on the recv
        return gen_opt_send_without_block(jit, ctx, cb);
    }
}

static codegen_status_t
gen_opt_plus(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Defer compilation so we can specialize on a runtime `self`
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    VALUE comptime_a = jit_peek_at_stack(jit, ctx, 1);
    VALUE comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if (FIXNUM_P(comptime_a) && FIXNUM_P(comptime_b)) {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        if (!assume_bop_not_redefined(jit, INTEGER_REDEFINED_OP_FLAG, BOP_PLUS)) {
            return YJIT_CANT_COMPILE;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, side_exit);

        // Get the operands and destination from the stack
        x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
        x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

        // Add arg0 + arg1 and test for overflow
        mov(cb, REG0, arg0);
        sub(cb, REG0, imm_opnd(1));
        add(cb, REG0, arg1);
        jo_ptr(cb, side_exit);

        // Push the output on the stack
        x86opnd_t dst = ctx_stack_push(ctx, TYPE_FIXNUM);
        mov(cb, dst, REG0);

        return YJIT_KEEP_COMPILING;
    }
    else {
        // Delegate to send, call the method on the recv
        return gen_opt_send_without_block(jit, ctx, cb);
    }
}

static codegen_status_t
gen_opt_mult(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Delegate to send, call the method on the recv
    return gen_opt_send_without_block(jit, ctx, cb);
}

static codegen_status_t
gen_opt_div(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Delegate to send, call the method on the recv
    return gen_opt_send_without_block(jit, ctx, cb);
}

VALUE rb_vm_opt_mod(VALUE recv, VALUE obj);

static codegen_status_t
gen_opt_mod(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Save the PC and SP because the callee may allocate bignums
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, REG0);

    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // Get the operands from the stack
    x86opnd_t arg1 = ctx_stack_pop(ctx, 1);
    x86opnd_t arg0 = ctx_stack_pop(ctx, 1);

    // Call rb_vm_opt_mod(VALUE recv, VALUE obj)
    mov(cb, C_ARG_REGS[0], arg0);
    mov(cb, C_ARG_REGS[1], arg1);
    call_ptr(cb, REG0, (void *)rb_vm_opt_mod);

    // If val == Qundef, bail to do a method call
    cmp(cb, RAX, imm_opnd(Qundef));
    je_ptr(cb, side_exit);

    // Push the return value onto the stack
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_opt_ltlt(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Delegate to send, call the method on the recv
    return gen_opt_send_without_block(jit, ctx, cb);
}

static codegen_status_t
gen_opt_nil_p(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Delegate to send, call the method on the recv
    return gen_opt_send_without_block(jit, ctx, cb);
}

static codegen_status_t
gen_opt_empty_p(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Delegate to send, call the method on the recv
    return gen_opt_send_without_block(jit, ctx, cb);
}

static codegen_status_t
gen_opt_str_freeze(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    if (!assume_bop_not_redefined(jit, STRING_REDEFINED_OP_FLAG, BOP_FREEZE)) {
        return YJIT_CANT_COMPILE;
    }

    VALUE str = jit_get_arg(jit, 0);
    jit_mov_gc_ptr(jit, cb, REG0, str);

    // Push the return value onto the stack
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_STRING);
    mov(cb, stack_ret, REG0);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_opt_str_uminus(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    if (!assume_bop_not_redefined(jit, STRING_REDEFINED_OP_FLAG, BOP_UMINUS)) {
        return YJIT_CANT_COMPILE;
    }

    VALUE str = jit_get_arg(jit, 0);
    jit_mov_gc_ptr(jit, cb, REG0, str);

    // Push the return value onto the stack
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_STRING);
    mov(cb, stack_ret, REG0);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_opt_not(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    return gen_opt_send_without_block(jit, ctx, cb);
}

static codegen_status_t
gen_opt_size(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    return gen_opt_send_without_block(jit, ctx, cb);
}

static codegen_status_t
gen_opt_length(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    return gen_opt_send_without_block(jit, ctx, cb);
}

static codegen_status_t
gen_opt_regexpmatch2(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    return gen_opt_send_without_block(jit, ctx, cb);
}

static codegen_status_t
gen_opt_case_dispatch(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Normally this instruction would lookup the key in a hash and jump to an
    // offset based on that.
    // Instead we can take the fallback case and continue with the next
    // instruction.
    // We'd hope that our jitted code will be sufficiently fast without the
    // hash lookup, at least for small hashes, but it's worth revisiting this
    // assumption in the future.

    ctx_stack_pop(ctx, 1);

    return YJIT_KEEP_COMPILING; // continue with the next instruction
}

static void
gen_branchif_branch(codeblock_t *cb, uint8_t *target0, uint8_t *target1, uint8_t shape)
{
    switch (shape) {
      case SHAPE_NEXT0:
        jz_ptr(cb, target1);
        break;

      case SHAPE_NEXT1:
        jnz_ptr(cb, target0);
        break;

      case SHAPE_DEFAULT:
        jnz_ptr(cb, target0);
        jmp_ptr(cb, target1);
        break;
    }
}

static codegen_status_t
gen_branchif(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t jump_offset = (int32_t)jit_get_arg(jit, 0);

    // Check for interrupts, but only on backward branches that may create loops
    if (jump_offset < 0) {
        uint8_t *side_exit = yjit_side_exit(jit, ctx);
        yjit_check_ints(cb, side_exit);
    }

    // Test if any bit (outside of the Qnil bit) is on
    // RUBY_Qfalse  /* ...0000 0000 */
    // RUBY_Qnil    /* ...0000 1000 */
    x86opnd_t val_opnd = ctx_stack_pop(ctx, 1);
    test(cb, val_opnd, imm_opnd(~Qnil));

    // Get the branch target instruction offsets
    uint32_t next_idx = jit_next_insn_idx(jit);
    uint32_t jump_idx = next_idx + jump_offset;
    blockid_t next_block = { jit->iseq, next_idx };
    blockid_t jump_block = { jit->iseq, jump_idx };

    // Generate the branch instructions
    gen_branch(
        jit,
        ctx,
        jump_block,
        ctx,
        next_block,
        ctx,
        gen_branchif_branch
    );

    return YJIT_END_BLOCK;
}

static void
gen_branchunless_branch(codeblock_t *cb, uint8_t *target0, uint8_t *target1, uint8_t shape)
{
    switch (shape) {
      case SHAPE_NEXT0:
        jnz_ptr(cb, target1);
        break;

      case SHAPE_NEXT1:
        jz_ptr(cb, target0);
        break;

      case SHAPE_DEFAULT:
        jz_ptr(cb, target0);
        jmp_ptr(cb, target1);
        break;
    }
}

static codegen_status_t
gen_branchunless(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t jump_offset = (int32_t)jit_get_arg(jit, 0);

    // Check for interrupts, but only on backward branches that may create loops
    if (jump_offset < 0) {
        uint8_t *side_exit = yjit_side_exit(jit, ctx);
        yjit_check_ints(cb, side_exit);
    }

    // Test if any bit (outside of the Qnil bit) is on
    // RUBY_Qfalse  /* ...0000 0000 */
    // RUBY_Qnil    /* ...0000 1000 */
    x86opnd_t val_opnd = ctx_stack_pop(ctx, 1);
    test(cb, val_opnd, imm_opnd(~Qnil));

    // Get the branch target instruction offsets
    uint32_t next_idx = jit_next_insn_idx(jit);
    uint32_t jump_idx = next_idx + jump_offset;
    blockid_t next_block = { jit->iseq, next_idx };
    blockid_t jump_block = { jit->iseq, jump_idx };

    // Generate the branch instructions
    gen_branch(
        jit,
        ctx,
        jump_block,
        ctx,
        next_block,
        ctx,
        gen_branchunless_branch
    );

    return YJIT_END_BLOCK;
}

static void
gen_branchnil_branch(codeblock_t *cb, uint8_t *target0, uint8_t *target1, uint8_t shape)
{
    switch (shape) {
      case SHAPE_NEXT0:
        jne_ptr(cb, target1);
        break;

      case SHAPE_NEXT1:
        je_ptr(cb, target0);
        break;

      case SHAPE_DEFAULT:
        je_ptr(cb, target0);
        jmp_ptr(cb, target1);
        break;
    }
}

static codegen_status_t
gen_branchnil(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t jump_offset = (int32_t)jit_get_arg(jit, 0);

    // Check for interrupts, but only on backward branches that may create loops
    if (jump_offset < 0) {
        uint8_t *side_exit = yjit_side_exit(jit, ctx);
        yjit_check_ints(cb, side_exit);
    }

    // Test if the value is Qnil
    // RUBY_Qnil    /* ...0000 1000 */
    x86opnd_t val_opnd = ctx_stack_pop(ctx, 1);
    cmp(cb, val_opnd, imm_opnd(Qnil));

    // Get the branch target instruction offsets
    uint32_t next_idx = jit_next_insn_idx(jit);
    uint32_t jump_idx = next_idx + jump_offset;
    blockid_t next_block = { jit->iseq, next_idx };
    blockid_t jump_block = { jit->iseq, jump_idx };

    // Generate the branch instructions
    gen_branch(
        jit,
        ctx,
        jump_block,
        ctx,
        next_block,
        ctx,
        gen_branchnil_branch
    );

    return YJIT_END_BLOCK;
}

static codegen_status_t
gen_jump(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    int32_t jump_offset = (int32_t)jit_get_arg(jit, 0);

    // Check for interrupts, but only on backward branches that may create loops
    if (jump_offset < 0) {
        uint8_t *side_exit = yjit_side_exit(jit, ctx);
        yjit_check_ints(cb, side_exit);
    }

    // Get the branch target instruction offsets
    uint32_t jump_idx = jit_next_insn_idx(jit) + jump_offset;
    blockid_t jump_block = { jit->iseq, jump_idx };

    // Generate the jump instruction
    gen_direct_jump(
        jit,
        ctx,
        jump_block
    );

    return YJIT_END_BLOCK;
}

/*
Guard that self or a stack operand has the same class as `known_klass`, using
`sample_instance` to speculate about the shape of the runtime value.
FIXNUM and on-heap integers are treated as if they have distinct classes, and
the guard generated for one will fail for the other.

Recompile as contingency if possible, or take side exit a last resort.
*/
static bool
jit_guard_known_klass(jitstate_t *jit, ctx_t *ctx, VALUE known_klass, insn_opnd_t insn_opnd, VALUE sample_instance, const int max_chain_depth, uint8_t *side_exit)
{
    val_type_t val_type = ctx_get_opnd_type(ctx, insn_opnd);

    if (known_klass == rb_cNilClass) {
        RUBY_ASSERT(!val_type.is_heap);
        if (val_type.type != ETYPE_NIL) {
            RUBY_ASSERT(val_type.type == ETYPE_UNKNOWN);

            ADD_COMMENT(cb, "guard object is nil");
            cmp(cb, REG0, imm_opnd(Qnil));
            jit_chain_guard(JCC_JNE, jit, ctx, max_chain_depth, side_exit);

            ctx_upgrade_opnd_type(ctx, insn_opnd, TYPE_NIL);
        }
    }
    else if (known_klass == rb_cTrueClass) {
        RUBY_ASSERT(!val_type.is_heap);
        if (val_type.type != ETYPE_TRUE) {
            RUBY_ASSERT(val_type.type == ETYPE_UNKNOWN);

            ADD_COMMENT(cb, "guard object is true");
            cmp(cb, REG0, imm_opnd(Qtrue));
            jit_chain_guard(JCC_JNE, jit, ctx, max_chain_depth, side_exit);

            ctx_upgrade_opnd_type(ctx, insn_opnd, TYPE_TRUE);
        }
    }
    else if (known_klass == rb_cFalseClass) {
        RUBY_ASSERT(!val_type.is_heap);
        if (val_type.type != ETYPE_FALSE) {
            RUBY_ASSERT(val_type.type == ETYPE_UNKNOWN);

            ADD_COMMENT(cb, "guard object is false");
            STATIC_ASSERT(qfalse_is_zero, Qfalse == 0);
            test(cb, REG0, REG0);
            jit_chain_guard(JCC_JNZ, jit, ctx, max_chain_depth, side_exit);

            ctx_upgrade_opnd_type(ctx, insn_opnd, TYPE_FALSE);
        }
    }
    else if (known_klass == rb_cInteger && FIXNUM_P(sample_instance)) {
        RUBY_ASSERT(!val_type.is_heap);
        // We will guard fixnum and bignum as though they were separate classes
        // BIGNUM can be handled by the general else case below
        if (val_type.type != ETYPE_FIXNUM || !val_type.is_imm) {
            RUBY_ASSERT(val_type.type == ETYPE_UNKNOWN);

            ADD_COMMENT(cb, "guard object is fixnum");
            test(cb, REG0, imm_opnd(RUBY_FIXNUM_FLAG));
            jit_chain_guard(JCC_JZ, jit, ctx, max_chain_depth, side_exit);
            ctx_upgrade_opnd_type(ctx, insn_opnd, TYPE_FIXNUM);
        }
    }
    else if (known_klass == rb_cSymbol && STATIC_SYM_P(sample_instance)) {
        RUBY_ASSERT(!val_type.is_heap);
        // We will guard STATIC vs DYNAMIC as though they were separate classes
        // DYNAMIC symbols can be handled by the general else case below
        if (val_type.type != ETYPE_SYMBOL || !val_type.is_imm) {
            RUBY_ASSERT(val_type.type == ETYPE_UNKNOWN);

            ADD_COMMENT(cb, "guard object is static symbol");
            STATIC_ASSERT(special_shift_is_8, RUBY_SPECIAL_SHIFT == 8);
            cmp(cb, REG0_8, imm_opnd(RUBY_SYMBOL_FLAG));
            jit_chain_guard(JCC_JNE, jit, ctx, max_chain_depth, side_exit);
            ctx_upgrade_opnd_type(ctx, insn_opnd, TYPE_STATIC_SYMBOL);
        }
    }
    else if (known_klass == rb_cFloat && FLONUM_P(sample_instance)) {
        RUBY_ASSERT(!val_type.is_heap);
        if (val_type.type != ETYPE_FLONUM || !val_type.is_imm) {
            RUBY_ASSERT(val_type.type == ETYPE_UNKNOWN);

            // We will guard flonum vs heap float as though they were separate classes
            ADD_COMMENT(cb, "guard object is flonum");
            mov(cb, REG1, REG0);
            and(cb, REG1, imm_opnd(RUBY_FLONUM_MASK));
            cmp(cb, REG1, imm_opnd(RUBY_FLONUM_FLAG));
            jit_chain_guard(JCC_JNE, jit, ctx, max_chain_depth, side_exit);
            ctx_upgrade_opnd_type(ctx, insn_opnd, TYPE_FLONUM);
        }
    }
    else if (FL_TEST(known_klass, FL_SINGLETON) && sample_instance == rb_attr_get(known_klass, id__attached__)) {
        // Singleton classes are attached to one specific object, so we can
        // avoid one memory access (and potentially the is_heap check) by
        // looking for the expected object directly.
        // Note that in case the sample instance has a singleton class that
        // doesn't attach to the sample instance, it means the sample instance
        // has an empty singleton class that hasn't been materialized yet. In
        // this case, comparing against the sample instance doesn't guarantee
        // that its singleton class is empty, so we can't avoid the memory
        // access. As an example, `Object.new.singleton_class` is an object in
        // this situation.
        ADD_COMMENT(cb, "guard known object with singleton class");
        // TODO: jit_mov_gc_ptr keeps a strong reference, which leaks the object.
        jit_mov_gc_ptr(jit, cb, REG1, sample_instance);
        cmp(cb, REG0, REG1);
        jit_chain_guard(JCC_JNE, jit, ctx, max_chain_depth, side_exit);
    }
    else {
        RUBY_ASSERT(!val_type.is_imm);

        // Check that the receiver is a heap object
        // Note: if we get here, the class doesn't have immediate instances.
        if (!val_type.is_heap) {
            ADD_COMMENT(cb, "guard not immediate");
            RUBY_ASSERT(Qfalse < Qnil);
            test(cb, REG0, imm_opnd(RUBY_IMMEDIATE_MASK));
            jit_chain_guard(JCC_JNZ, jit, ctx, max_chain_depth, side_exit);
            cmp(cb, REG0, imm_opnd(Qnil));
            jit_chain_guard(JCC_JBE, jit, ctx, max_chain_depth, side_exit);

            ctx_upgrade_opnd_type(ctx, insn_opnd, TYPE_HEAP);
        }

        x86opnd_t klass_opnd = mem_opnd(64, REG0, offsetof(struct RBasic, klass));

        // Bail if receiver class is different from known_klass
        // TODO: jit_mov_gc_ptr keeps a strong reference, which leaks the class.
        ADD_COMMENT(cb, "guard known class");
        jit_mov_gc_ptr(jit, cb, REG1, known_klass);
        cmp(cb, klass_opnd, REG1);
        jit_chain_guard(JCC_JNE, jit, ctx, max_chain_depth, side_exit);
    }

    return true;
}

// Generate ancestry guard for protected callee.
// Calls to protected callees only go through when self.is_a?(klass_that_defines_the_callee).
static void
jit_protected_callee_ancestry_guard(jitstate_t *jit, codeblock_t *cb, const rb_callable_method_entry_t *cme, uint8_t *side_exit)
{
    // See vm_call_method().
    mov(cb, C_ARG_REGS[0], member_opnd(REG_CFP, rb_control_frame_t, self));
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[1], cme->defined_class);
    // Note: PC isn't written to current control frame as rb_is_kind_of() shouldn't raise.
    // VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);
    call_ptr(cb, REG0, (void *)&rb_obj_is_kind_of);
    test(cb, RAX, RAX);
    jz_ptr(cb, COUNTED_EXIT(jit, side_exit, send_se_protected_check_failed));
}

// Return true when the codegen function generates code.
// known_recv_klass is non-NULL when the caller has used jit_guard_known_klass().
// See yjit_reg_method().
typedef bool (*method_codegen_t)(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *known_recv_klass);

// Register a specialized codegen function for a particular method. Note that
// the if the function returns true, the code it generates runs without a
// control frame and without interrupt checks. To avoid creating observable
// behavior changes, the codegen function should only target simple code paths
// that do not allocate and do not make method calls.
static void
yjit_reg_method(VALUE klass, const char *mid_str, method_codegen_t gen_fn)
{
    ID mid = rb_intern(mid_str);
    const rb_method_entry_t *me = rb_method_entry_at(klass, mid);

    if (!me) {
        rb_bug("undefined optimized method: %s", rb_id2name(mid));
    }

    // For now, only cfuncs are supported
    RUBY_ASSERT(me && me->def);
    RUBY_ASSERT(me->def->type == VM_METHOD_TYPE_CFUNC);

    st_insert(yjit_method_codegen_table, (st_data_t)me->def->method_serial, (st_data_t)gen_fn);
}

// Codegen for rb_obj_not().
// Note, caller is responsible for generating all the right guards, including
// arity guards.
static bool
jit_rb_obj_not(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *known_recv_klass)
{
    const val_type_t recv_opnd = ctx_get_opnd_type(ctx, OPND_STACK(0));

    if (recv_opnd.type == ETYPE_NIL || recv_opnd.type == ETYPE_FALSE) {
        ADD_COMMENT(cb, "rb_obj_not(nil_or_false)");
        ctx_stack_pop(ctx, 1);
        x86opnd_t out_opnd = ctx_stack_push(ctx, TYPE_TRUE);
        mov(cb, out_opnd, imm_opnd(Qtrue));
    }
    else if (recv_opnd.is_heap || recv_opnd.type != ETYPE_UNKNOWN) {
        // Note: recv_opnd.type != ETYPE_NIL && recv_opnd.type != ETYPE_FALSE.
        ADD_COMMENT(cb, "rb_obj_not(truthy)");
        ctx_stack_pop(ctx, 1);
        x86opnd_t out_opnd = ctx_stack_push(ctx, TYPE_FALSE);
        mov(cb, out_opnd, imm_opnd(Qfalse));
    }
    else {
        // jit_guard_known_klass() already ran on the receiver which should
        // have deduced deduced the type of the receiver. This case should be
        // rare if not unreachable.
        return false;
    }
    return true;
}

// Codegen for rb_true()
static bool
jit_rb_true(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *known_recv_klass)
{
    ADD_COMMENT(cb, "nil? == true");
    ctx_stack_pop(ctx, 1);
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_TRUE);
    mov(cb, stack_ret, imm_opnd(Qtrue));
    return true;
}

// Codegen for rb_false()
static bool
jit_rb_false(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *known_recv_klass)
{
    ADD_COMMENT(cb, "nil? == false");
    ctx_stack_pop(ctx, 1);
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_FALSE);
    mov(cb, stack_ret, imm_opnd(Qfalse));
    return true;
}

// Codegen for rb_obj_equal()
// object identity comparison
static bool
jit_rb_obj_equal(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *known_recv_klass)
{
    ADD_COMMENT(cb, "equal?");
    x86opnd_t obj1 = ctx_stack_pop(ctx, 1);
    x86opnd_t obj2 = ctx_stack_pop(ctx, 1);

    mov(cb, REG0, obj1);
    cmp(cb, REG0, obj2);
    mov(cb, REG0, imm_opnd(Qtrue));
    mov(cb, REG1, imm_opnd(Qfalse));
    cmovne(cb, REG0, REG1);

    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_IMM);
    mov(cb, stack_ret, REG0);
    return true;
}

static VALUE
yjit_str_bytesize(VALUE str)
{
    return LONG2NUM(RSTRING_LEN(str));
}

static bool
jit_rb_str_bytesize(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *known_recv_klass)
{
    ADD_COMMENT(cb, "String#bytesize");

    x86opnd_t recv = ctx_stack_pop(ctx, 1);
    mov(cb, C_ARG_REGS[0], recv);
    call_ptr(cb, REG0, (void *)&yjit_str_bytesize);

    x86opnd_t out_opnd = ctx_stack_push(ctx, TYPE_FIXNUM);
    mov(cb, out_opnd, RAX);

    return true;
}

// Codegen for rb_str_to_s()
// When String#to_s is called on a String instance, the method returns self and
// most of the overhead comes from setting up the method call. We observed that
// this situation happens a lot in some workloads.
static bool
jit_rb_str_to_s(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *recv_known_klass)
{
    if (recv_known_klass && *recv_known_klass == rb_cString) {
        ADD_COMMENT(cb, "to_s on plain string");
        // The method returns the receiver, which is already on the stack.
        // No stack movement.
        return true;
    }
    return false;
}

static bool
jit_thread_s_current(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *recv_known_klass)
{
    ADD_COMMENT(cb, "Thread.current");
    ctx_stack_pop(ctx, 1);

    // ec->thread_ptr
    mov(cb, REG0, member_opnd(REG_EC, rb_execution_context_t, thread_ptr));

    // thread->self
    mov(cb, REG0, member_opnd(REG0, rb_thread_t, self));

    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_HEAP);
    mov(cb, stack_ret, REG0);
    return true;
}

// Check if we know how to codegen for a particular cfunc method
static method_codegen_t
lookup_cfunc_codegen(const rb_method_definition_t *def)
{
    method_codegen_t gen_fn;
    if (st_lookup(yjit_method_codegen_table, def->method_serial, (st_data_t *)&gen_fn)) {
        return gen_fn;
    }
    return NULL;
}

// Is anyone listening for :c_call and :c_return event currently?
static bool
c_method_tracing_currently_enabled(const jitstate_t *jit)
{
    rb_event_flag_t tracing_events;
    if (rb_multi_ractor_p()) {
        tracing_events = ruby_vm_event_enabled_global_flags;
    }
    else {
        // At the time of writing, events are never removed from
        // ruby_vm_event_enabled_global_flags so always checking using it would
        // mean we don't compile even after tracing is disabled.
        tracing_events = rb_ec_ractor_hooks(jit->ec)->events;
    }

    return tracing_events & (RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN);
}

static codegen_status_t
gen_send_cfunc(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, const int32_t argc, VALUE *recv_known_klass)
{
    const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(cme->def, body.cfunc);

    // If the function expects a Ruby array of arguments
    if (cfunc->argc < 0 && cfunc->argc != -1) {
        GEN_COUNTER_INC(cb, send_cfunc_ruby_array_varg);
        return YJIT_CANT_COMPILE;
    }

    // If the argument count doesn't match
    if (cfunc->argc >= 0 && cfunc->argc != argc) {
        GEN_COUNTER_INC(cb, send_cfunc_argc_mismatch);
        return YJIT_CANT_COMPILE;
    }

    // Don't JIT functions that need C stack arguments for now
    if (cfunc->argc >= 0 && argc + 1 > NUM_C_ARG_REGS) {
        GEN_COUNTER_INC(cb, send_cfunc_toomany_args);
        return YJIT_CANT_COMPILE;
    }

    if (c_method_tracing_currently_enabled(jit)) {
        // Don't JIT if tracing c_call or c_return
        GEN_COUNTER_INC(cb, send_cfunc_tracing);
        return YJIT_CANT_COMPILE;
    }

    // Delegate to codegen for C methods if we have it.
    {
        method_codegen_t known_cfunc_codegen;
        if ((known_cfunc_codegen = lookup_cfunc_codegen(cme->def))) {
            if (known_cfunc_codegen(jit, ctx, ci, cme, block, argc, recv_known_klass)) {
                // cfunc codegen generated code. Terminate the block so
                // there isn't multiple calls in the same block.
                jit_jump_to_next_insn(jit, ctx);
                return YJIT_END_BLOCK;
            }
        }
    }

    // Callee method ID
    //ID mid = vm_ci_mid(ci);
    //printf("JITting call to C function \"%s\", argc: %lu\n", rb_id2name(mid), argc);
    //print_str(cb, "");
    //print_str(cb, "calling CFUNC:");
    //print_str(cb, rb_id2name(mid));
    //print_str(cb, "recv");
    //print_ptr(cb, recv);

    // Create a side-exit to fall back to the interpreter
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // Check for interrupts
    yjit_check_ints(cb, side_exit);

    // Stack overflow check
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    // REG_CFP <= REG_SP + 4 * sizeof(VALUE) + sizeof(rb_control_frame_t)
    lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * 4 + 2 * sizeof(rb_control_frame_t)));
    cmp(cb, REG_CFP, REG0);
    jle_ptr(cb, COUNTED_EXIT(jit, side_exit, send_se_cf_overflow));

    // Points to the receiver operand on the stack
    x86opnd_t recv = ctx_stack_opnd(ctx, argc);

    // Store incremented PC into current control frame in case callee raises.
    jit_save_pc(jit, REG0);

    if (block) {
        // Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
        // VM_CFP_TO_CAPTURED_BLCOK does &cfp->self, rb_captured_block->code.iseq aliases
        // with cfp->block_code.
        jit_mov_gc_ptr(jit, cb, REG0, (VALUE)block);
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, block_code), REG0);
    }

    // Increment the stack pointer by 3 (in the callee)
    // sp += 3
    lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * 3));

    // Write method entry at sp[-3]
    // sp[-3] = me;
    // Put compile time cme into REG1. It's assumed to be valid because we are notified when
    // any cme we depend on become outdated. See rb_yjit_method_lookup_change().
    jit_mov_gc_ptr(jit, cb, REG1, (VALUE)cme);
    mov(cb, mem_opnd(64, REG0, 8 * -3), REG1);

    // Write block handler at sp[-2]
    // sp[-2] = block_handler;
    if (block) {
        // reg1 = VM_BH_FROM_ISEQ_BLOCK(VM_CFP_TO_CAPTURED_BLOCK(reg_cfp));
        lea(cb, REG1, member_opnd(REG_CFP, rb_control_frame_t, self));
        or(cb, REG1, imm_opnd(1));
        mov(cb, mem_opnd(64, REG0, 8 * -2), REG1);
    }
    else {
        mov(cb, mem_opnd(64, REG0, 8 * -2), imm_opnd(VM_BLOCK_HANDLER_NONE));
    }

    // Write env flags at sp[-1]
    // sp[-1] = frame_type;
    uint64_t frame_type = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;
    mov(cb, mem_opnd(64, REG0, 8 * -1), imm_opnd(frame_type));

    // Allocate a new CFP (ec->cfp--)
    sub(
        cb,
        member_opnd(REG_EC, rb_execution_context_t, cfp),
        imm_opnd(sizeof(rb_control_frame_t))
    );

    // Setup the new frame
    // *cfp = (const struct rb_control_frame_struct) {
    //    .pc         = 0,
    //    .sp         = sp,
    //    .iseq       = 0,
    //    .self       = recv,
    //    .ep         = sp - 1,
    //    .block_code = 0,
    //    .__bp__     = sp,
    // };
    mov(cb, REG1, member_opnd(REG_EC, rb_execution_context_t, cfp));
    mov(cb, member_opnd(REG1, rb_control_frame_t, pc), imm_opnd(0));
    mov(cb, member_opnd(REG1, rb_control_frame_t, sp), REG0);
    mov(cb, member_opnd(REG1, rb_control_frame_t, iseq), imm_opnd(0));
    mov(cb, member_opnd(REG1, rb_control_frame_t, block_code), imm_opnd(0));
    mov(cb, member_opnd(REG1, rb_control_frame_t, __bp__), REG0);
    sub(cb, REG0, imm_opnd(sizeof(VALUE)));
    mov(cb, member_opnd(REG1, rb_control_frame_t, ep), REG0);
    mov(cb, REG0, recv);
    mov(cb, member_opnd(REG1, rb_control_frame_t, self), REG0);

    // Verify that we are calling the right function
    if (YJIT_CHECK_MODE > 0) {
        // Call check_cfunc_dispatch
        mov(cb, C_ARG_REGS[0], recv);
        jit_mov_gc_ptr(jit, cb, C_ARG_REGS[1], (VALUE)ci);
        mov(cb, C_ARG_REGS[2], const_ptr_opnd((void *)cfunc->func));
        jit_mov_gc_ptr(jit, cb, C_ARG_REGS[3], (VALUE)cme);
        call_ptr(cb, REG0, (void *)&check_cfunc_dispatch);
    }

    // Copy SP into RAX because REG_SP will get overwritten
    lea(cb, RAX, ctx_sp_opnd(ctx, 0));

    // Pop the C function arguments from the stack (in the caller)
    ctx_stack_pop(ctx, argc + 1);

    // Write interpreter SP into CFP.
    // Needed in case the callee yields to the block.
    jit_save_sp(jit, ctx);

    // Non-variadic method
    if (cfunc->argc >= 0) {
        // Copy the arguments from the stack to the C argument registers
        // self is the 0th argument and is at index argc from the stack top
        for (int32_t i = 0; i < argc + 1; ++i)
        {
            x86opnd_t stack_opnd = mem_opnd(64, RAX, -(argc + 1 - i) * SIZEOF_VALUE);
            x86opnd_t c_arg_reg = C_ARG_REGS[i];
            mov(cb, c_arg_reg, stack_opnd);
        }
    }
    // Variadic method
    if (cfunc->argc == -1) {
        // The method gets a pointer to the first argument
        // rb_f_puts(int argc, VALUE *argv, VALUE recv)
        mov(cb, C_ARG_REGS[0], imm_opnd(argc));
        lea(cb, C_ARG_REGS[1], mem_opnd(64, RAX, -(argc) * SIZEOF_VALUE));
        mov(cb, C_ARG_REGS[2], mem_opnd(64, RAX, -(argc + 1) * SIZEOF_VALUE));
    }

    // Call the C function
    // VALUE ret = (cfunc->func)(recv, argv[0], argv[1]);
    // cfunc comes from compile-time cme->def, which we assume to be stable.
    // Invalidation logic is in rb_yjit_method_lookup_change()
    call_ptr(cb, REG0, (void*)cfunc->func);

    // Record code position for TracePoint patching. See full_cfunc_return().
    record_global_inval_patch(cb, outline_full_cfunc_return_pos);

    // Push the return value on the Ruby stack
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, stack_ret, RAX);

    // Pop the stack frame (ec->cfp++)
    add(
        cb,
        member_opnd(REG_EC, rb_execution_context_t, cfp),
        imm_opnd(sizeof(rb_control_frame_t))
    );

    // cfunc calls may corrupt types
    ctx_clear_local_types(ctx);

    // Note: the return block of gen_send_iseq() has ctx->sp_offset == 1
    // which allows for sharing the same successor.

    // Jump (fall through) to the call continuation block
    // We do this to end the current block after the call
    jit_jump_to_next_insn(jit, ctx);
    return YJIT_END_BLOCK;
}

static void
gen_return_branch(codeblock_t *cb, uint8_t *target0, uint8_t *target1, uint8_t shape)
{
    switch (shape) {
      case SHAPE_NEXT0:
      case SHAPE_NEXT1:
        RUBY_ASSERT(false);
        break;

      case SHAPE_DEFAULT:
        mov(cb, REG0, const_ptr_opnd(target0));
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, jit_return), REG0);
        break;
    }
}

// If true, the iseq is leaf and it can be replaced by a single C call.
static bool
rb_leaf_invokebuiltin_iseq_p(const rb_iseq_t *iseq)
{
    unsigned int invokebuiltin_len = insn_len(BIN(opt_invokebuiltin_delegate_leave));
    unsigned int leave_len = insn_len(BIN(leave));

    return (iseq->body->iseq_size == (invokebuiltin_len + leave_len) &&
        rb_vm_insn_addr2opcode((void *)iseq->body->iseq_encoded[0]) == BIN(opt_invokebuiltin_delegate_leave) &&
        rb_vm_insn_addr2opcode((void *)iseq->body->iseq_encoded[invokebuiltin_len]) == BIN(leave) &&
        iseq->body->builtin_inline_p
    );
 }

// Return an rb_builtin_function if the iseq contains only that leaf builtin function.
static const struct rb_builtin_function*
rb_leaf_builtin_function(const rb_iseq_t *iseq)
{
    if (!rb_leaf_invokebuiltin_iseq_p(iseq))
        return NULL;
    return (const struct rb_builtin_function *)iseq->body->iseq_encoded[1];
}

static codegen_status_t
gen_send_iseq(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, rb_iseq_t *block, int32_t argc)
{
    const rb_iseq_t *iseq = def_iseq_ptr(cme->def);

    // When you have keyword arguments, there is an extra object that gets
    // placed on the stack the represents a bitmap of the keywords that were not
    // specified at the call site. We need to keep track of the fact that this
    // value is present on the stack in order to properly set up the callee's
    // stack pointer.
    const bool doing_kw_call = iseq->body->param.flags.has_kw;
    const bool supplying_kws = vm_ci_flag(ci) & VM_CALL_KWARG;

    if (vm_ci_flag(ci) & VM_CALL_TAILCALL) {
        // We can't handle tailcalls
        GEN_COUNTER_INC(cb, send_iseq_tailcall);
        return YJIT_CANT_COMPILE;
    }

    // No support for callees with these parameters yet as they require allocation
    // or complex handling.
    if (iseq->body->param.flags.has_rest ||
        iseq->body->param.flags.has_post ||
        iseq->body->param.flags.has_kwrest) {
        GEN_COUNTER_INC(cb, send_iseq_complex_callee);
        return YJIT_CANT_COMPILE;
    }

    // If we have keyword arguments being passed to a callee that only takes
    // positionals, then we need to allocate a hash. For now we're going to
    // call that too complex and bail.
    if (supplying_kws && !iseq->body->param.flags.has_kw) {
        GEN_COUNTER_INC(cb, send_iseq_complex_callee);
        return YJIT_CANT_COMPILE;
    }

    // If we have a method accepting no kwargs (**nil), exit if we have passed
    // it any kwargs.
    if (supplying_kws && iseq->body->param.flags.accepts_no_kwarg) {
        GEN_COUNTER_INC(cb, send_iseq_complex_callee);
        return YJIT_CANT_COMPILE;
    }

    // For computing number of locals to setup for the callee
    int num_params = iseq->body->param.size;

    // Block parameter handling. This mirrors setup_parameters_complex().
    if (iseq->body->param.flags.has_block) {
        if (iseq->body->local_iseq == iseq) {
            // Block argument is passed through EP and not setup as a local in
            // the callee.
            num_params--;
        }
        else {
            // In this case (param.flags.has_block && local_iseq != iseq),
            // the block argument is setup as a local variable and requires
            // materialization (allocation). Bail.
            GEN_COUNTER_INC(cb, send_iseq_complex_callee);
            return YJIT_CANT_COMPILE;
        }
    }

    uint32_t start_pc_offset = 0;

    const int required_num = iseq->body->param.lead_num;

    // This struct represents the metadata about the caller-specified
    // keyword arguments.
    const struct rb_callinfo_kwarg *kw_arg = vm_ci_kwarg(ci);
    const int kw_arg_num = kw_arg ? kw_arg->keyword_len : 0;

    // Arity handling and optional parameter setup
    const int opts_filled = argc - required_num - kw_arg_num;
    const int opt_num = iseq->body->param.opt_num;
    const int opts_missing = opt_num - opts_filled;

    if (opts_filled < 0 || opts_filled > opt_num) {
        GEN_COUNTER_INC(cb, send_iseq_arity_error);
        return YJIT_CANT_COMPILE;
    }

    // If we have unfilled optional arguments and keyword arguments then we
    // would need to move adjust the arguments location to account for that.
    // For now we aren't handling this case.
    if (doing_kw_call && opts_missing > 0) {
        GEN_COUNTER_INC(cb, send_iseq_complex_callee);
        return YJIT_CANT_COMPILE;
    }

    if (opt_num > 0) {
        num_params -= opt_num - opts_filled;
        start_pc_offset = (uint32_t)iseq->body->param.opt_table[opts_filled];
    }

    if (doing_kw_call) {
        // Here we're calling a method with keyword arguments and specifying
        // keyword arguments at this call site.

        // This struct represents the metadata about the callee-specified
        // keyword parameters.
        const struct rb_iseq_param_keyword *keyword = iseq->body->param.keyword;

        int required_kwargs_filled = 0;

        if (keyword->num > 30) {
            // We have so many keywords that (1 << num) encoded as a FIXNUM
            // (which shifts it left one more) no longer fits inside a 32-bit
            // immediate.
            GEN_COUNTER_INC(cb, send_iseq_complex_callee);
            return YJIT_CANT_COMPILE;
        }

        // Check that the kwargs being passed are valid
        if (supplying_kws) {
            // This is the list of keyword arguments that the callee specified
            // in its initial declaration.
            const ID *callee_kwargs = keyword->table;

            // Here we're going to build up a list of the IDs that correspond to
            // the caller-specified keyword arguments. If they're not in the
            // same order as the order specified in the callee declaration, then
            // we're going to need to generate some code to swap values around
            // on the stack.
            ID *caller_kwargs = ALLOCA_N(VALUE, kw_arg->keyword_len);
            for (int kwarg_idx = 0; kwarg_idx < kw_arg->keyword_len; kwarg_idx++)
                caller_kwargs[kwarg_idx] = SYM2ID(kw_arg->keywords[kwarg_idx]);

            // First, we're going to be sure that the names of every
            // caller-specified keyword argument correspond to a name in the
            // list of callee-specified keyword parameters.
            for (int caller_idx = 0; caller_idx < kw_arg->keyword_len; caller_idx++) {
                int callee_idx;

                for (callee_idx = 0; callee_idx < keyword->num; callee_idx++) {
                    if (caller_kwargs[caller_idx] == callee_kwargs[callee_idx]) {
                        break;
                    }
                }

                // If the keyword was never found, then we know we have a
                // mismatch in the names of the keyword arguments, so we need to
                // bail.
                if (callee_idx == keyword->num) {
                    GEN_COUNTER_INC(cb, send_iseq_kwargs_mismatch);
                    return YJIT_CANT_COMPILE;
                }

                // Keep a count to ensure all required kwargs are specified
                if (callee_idx < keyword->required_num) {
                    required_kwargs_filled++;
                }
            }
        }

        RUBY_ASSERT(required_kwargs_filled <= keyword->required_num);
        if (required_kwargs_filled != keyword->required_num) {
            GEN_COUNTER_INC(cb, send_iseq_kwargs_mismatch);
            return YJIT_CANT_COMPILE;
        }
    }

    // Number of locals that are not parameters
    const int num_locals = iseq->body->local_table_size - num_params;

    // Create a side-exit to fall back to the interpreter
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // Check for interrupts
    yjit_check_ints(cb, side_exit);

    const struct rb_builtin_function *leaf_builtin = rb_leaf_builtin_function(iseq);

    if (leaf_builtin && !block && leaf_builtin->argc + 1 <= NUM_C_ARG_REGS) {
        ADD_COMMENT(cb, "inlined leaf builtin");

        // Call the builtin func (ec, recv, arg1, arg2, ...)
        mov(cb, C_ARG_REGS[0], REG_EC);

        // Copy self and arguments
        for (int32_t i = 0; i < leaf_builtin->argc + 1; i++) {
            x86opnd_t stack_opnd = ctx_stack_opnd(ctx, leaf_builtin->argc - i);
            x86opnd_t c_arg_reg = C_ARG_REGS[i + 1];
            mov(cb, c_arg_reg, stack_opnd);
        }
        ctx_stack_pop(ctx, leaf_builtin->argc + 1);
        call_ptr(cb, REG0, (void *)leaf_builtin->func_ptr);

        // Push the return value
        x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, stack_ret, RAX);

        // Note: assuming that the leaf builtin doesn't change local variables here.
        // Seems like a safe assumption.

        return YJIT_KEEP_COMPILING;
    }

    // Stack overflow check
    // Note that vm_push_frame checks it against a decremented cfp, hence the multiply by 2.
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    ADD_COMMENT(cb, "stack overflow check");
    lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * (num_locals + iseq->body->stack_max) + 2 * sizeof(rb_control_frame_t)));
    cmp(cb, REG_CFP, REG0);
    jle_ptr(cb, COUNTED_EXIT(jit, side_exit, send_se_cf_overflow));

    if (doing_kw_call) {
        // Here we're calling a method with keyword arguments and specifying
        // keyword arguments at this call site.

        // Number of positional arguments the callee expects before the first
        // keyword argument
        const int args_before_kw = required_num + opt_num;

        // This struct represents the metadata about the caller-specified
        // keyword arguments.
        int caller_keyword_len = 0;
        const VALUE *caller_keywords = NULL;
        if (vm_ci_kwarg(ci)) {
            caller_keyword_len = vm_ci_kwarg(ci)->keyword_len;
            caller_keywords = &vm_ci_kwarg(ci)->keywords[0];
        }

        // This struct represents the metadata about the callee-specified
        // keyword parameters.
        const struct rb_iseq_param_keyword *const keyword = iseq->body->param.keyword;

        ADD_COMMENT(cb, "keyword args");

        // This is the list of keyword arguments that the callee specified
        // in its initial declaration.
        const ID *callee_kwargs = keyword->table;

        int total_kwargs = keyword->num;

        // Here we're going to build up a list of the IDs that correspond to
        // the caller-specified keyword arguments. If they're not in the
        // same order as the order specified in the callee declaration, then
        // we're going to need to generate some code to swap values around
        // on the stack.
        ID *caller_kwargs = ALLOCA_N(VALUE, total_kwargs);
        int kwarg_idx;
        for (kwarg_idx = 0; kwarg_idx < caller_keyword_len; kwarg_idx++) {
            caller_kwargs[kwarg_idx] = SYM2ID(caller_keywords[kwarg_idx]);
        }

        int unspecified_bits = 0;

        for (int callee_idx = keyword->required_num; callee_idx < total_kwargs; callee_idx++) {
            bool already_passed = false;
            ID callee_kwarg = callee_kwargs[callee_idx];

            for (int caller_idx = 0; caller_idx < caller_keyword_len; caller_idx++) {
                if (caller_kwargs[caller_idx] == callee_kwarg) {
                    already_passed = true;
                    break;
                }
            }

            if (!already_passed) {
                // Reserve space on the stack for each default value we'll be
                // filling in (which is done in the next loop). Also increments
                // argc so that the callee's SP is recorded correctly.
                argc++;
                x86opnd_t default_arg = ctx_stack_push(ctx, TYPE_UNKNOWN);
                VALUE default_value = keyword->default_values[callee_idx - keyword->required_num];

                if (default_value == Qundef) {
                    // Qundef means that this value is not constant and must be
                    // recalculated at runtime, so we record it in unspecified_bits
                    // (Qnil is then used as a placeholder instead of Qundef).
                    unspecified_bits |= 0x01 << (callee_idx - keyword->required_num);
                    default_value = Qnil;
                }

                // GC might move default_value.
                jit_mov_gc_ptr(jit, cb, REG0, default_value);
                mov(cb, default_arg, REG0);

                caller_kwargs[kwarg_idx++] = callee_kwarg;
            }
        }
        RUBY_ASSERT(kwarg_idx == total_kwargs);

        // Next, we're going to loop through every keyword that was
        // specified by the caller and make sure that it's in the correct
        // place. If it's not we're going to swap it around with another one.
        for (kwarg_idx = 0; kwarg_idx < total_kwargs; kwarg_idx++) {
            ID callee_kwarg = callee_kwargs[kwarg_idx];

            // If the argument is already in the right order, then we don't
            // need to generate any code since the expected value is already
            // in the right place on the stack.
            if (callee_kwarg == caller_kwargs[kwarg_idx]) continue;

            // In this case the argument is not in the right place, so we
            // need to find its position where it _should_ be and swap with
            // that location.
            for (int swap_idx = kwarg_idx + 1; swap_idx < total_kwargs; swap_idx++) {
                if (callee_kwarg == caller_kwargs[swap_idx]) {
                    // First we're going to generate the code that is going
                    // to perform the actual swapping at runtime.
                    stack_swap(ctx, cb, argc - 1 - swap_idx - args_before_kw, argc - 1 - kwarg_idx - args_before_kw, REG1, REG0);

                    // Next we're going to do some bookkeeping on our end so
                    // that we know the order that the arguments are
                    // actually in now.
                    ID tmp = caller_kwargs[kwarg_idx];
                    caller_kwargs[kwarg_idx] = caller_kwargs[swap_idx];
                    caller_kwargs[swap_idx] = tmp;

                    break;
                }
            }
        }

        // Keyword arguments cause a special extra local variable to be
        // pushed onto the stack that represents the parameters that weren't
        // explicitly given a value and have a non-constant default.
        mov(cb, ctx_stack_opnd(ctx, -1), imm_opnd(INT2FIX(unspecified_bits)));
    }
    // Points to the receiver operand on the stack
    x86opnd_t recv = ctx_stack_opnd(ctx, argc);

    // Store the updated SP on the current frame (pop arguments and receiver)
    ADD_COMMENT(cb, "store caller sp");
    lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * -(argc + 1)));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG0);

    // Store the next PC in the current frame
    jit_save_pc(jit, REG0);

    if (block) {
        // Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
        // VM_CFP_TO_CAPTURED_BLCOK does &cfp->self, rb_captured_block->code.iseq aliases
        // with cfp->block_code.
        jit_mov_gc_ptr(jit, cb, REG0, (VALUE)block);
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, block_code), REG0);
    }

    // Adjust the callee's stack pointer
    lea(cb, REG0, ctx_sp_opnd(ctx, sizeof(VALUE) * (3 + num_locals + doing_kw_call)));

    // Initialize local variables to Qnil
    for (int i = 0; i < num_locals; i++) {
        mov(cb, mem_opnd(64, REG0, sizeof(VALUE) * (i - num_locals - 3)), imm_opnd(Qnil));
    }

    ADD_COMMENT(cb, "push env");
    // Put compile time cme into REG1. It's assumed to be valid because we are notified when
    // any cme we depend on become outdated. See rb_yjit_method_lookup_change().
    jit_mov_gc_ptr(jit, cb, REG1, (VALUE)cme);
    // Write method entry at sp[-3]
    // sp[-3] = me;
    mov(cb, mem_opnd(64, REG0, 8 * -3), REG1);

    // Write block handler at sp[-2]
    // sp[-2] = block_handler;
    if (block) {
        // reg1 = VM_BH_FROM_ISEQ_BLOCK(VM_CFP_TO_CAPTURED_BLOCK(reg_cfp));
        lea(cb, REG1, member_opnd(REG_CFP, rb_control_frame_t, self));
        or(cb, REG1, imm_opnd(1));
        mov(cb, mem_opnd(64, REG0, 8 * -2), REG1);
    }
    else {
        mov(cb, mem_opnd(64, REG0, 8 * -2), imm_opnd(VM_BLOCK_HANDLER_NONE));
    }

    // Write env flags at sp[-1]
    // sp[-1] = frame_type;
    uint64_t frame_type = VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL;
    mov(cb, mem_opnd(64, REG0, 8 * -1), imm_opnd(frame_type));

    ADD_COMMENT(cb, "push callee CFP");
    // Allocate a new CFP (ec->cfp--)
    sub(cb, REG_CFP, imm_opnd(sizeof(rb_control_frame_t)));
    mov(cb, member_opnd(REG_EC, rb_execution_context_t, cfp), REG_CFP);

    // Setup the new frame
    // *cfp = (const struct rb_control_frame_struct) {
    //    .pc         = pc,
    //    .sp         = sp,
    //    .iseq       = iseq,
    //    .self       = recv,
    //    .ep         = sp - 1,
    //    .block_code = 0,
    //    .__bp__     = sp,
    // };
    mov(cb, REG1, recv);
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, self), REG1);
    mov(cb, REG_SP, REG0); // Switch to the callee's REG_SP
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG0);
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, __bp__), REG0);
    sub(cb, REG0, imm_opnd(sizeof(VALUE)));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, ep), REG0);
    jit_mov_gc_ptr(jit, cb, REG0, (VALUE)iseq);
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, iseq), REG0);
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, block_code), imm_opnd(0));

    // No need to set cfp->pc since the callee sets it whenever calling into routines
    // that could look at it through jit_save_pc().
    // mov(cb, REG0, const_ptr_opnd(start_pc));
    // mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), REG0);

    // Stub so we can return to JITted code
    blockid_t return_block = { jit->iseq, jit_next_insn_idx(jit) };

    // Create a context for the callee
    ctx_t callee_ctx = DEFAULT_CTX;

    // Set the argument types in the callee's context
    for (int32_t arg_idx = 0; arg_idx < argc; ++arg_idx) {
        val_type_t arg_type = ctx_get_opnd_type(ctx, OPND_STACK(argc - arg_idx - 1));
        ctx_set_local_type(&callee_ctx, arg_idx, arg_type);
    }
    val_type_t recv_type = ctx_get_opnd_type(ctx, OPND_STACK(argc));
    ctx_upgrade_opnd_type(&callee_ctx, OPND_SELF, recv_type);

    // The callee might change locals through Kernel#binding and other means.
    ctx_clear_local_types(ctx);

    // Pop arguments and receiver in return context, push the return value
    // After the return, sp_offset will be 1. The codegen for leave writes
    // the return value in case of JIT-to-JIT return.
    ctx_t return_ctx = *ctx;
    ctx_stack_pop(&return_ctx, argc + 1);
    ctx_stack_push(&return_ctx, TYPE_UNKNOWN);
    return_ctx.sp_offset = 1;
    return_ctx.chain_depth = 0;

    // Write the JIT return address on the callee frame
    gen_branch(
        jit,
        ctx,
        return_block,
        &return_ctx,
        return_block,
        &return_ctx,
        gen_return_branch
    );

    //print_str(cb, "calling Ruby func:");
    //print_str(cb, rb_id2name(vm_ci_mid(ci)));

    // Directly jump to the entry point of the callee
    gen_direct_jump(
        jit,
        &callee_ctx,
        (blockid_t){ iseq, start_pc_offset }
    );

    return YJIT_END_BLOCK;
}

static codegen_status_t
gen_struct_aref(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, VALUE comptime_recv, VALUE comptime_recv_klass) {
    if (vm_ci_argc(ci) != 0) {
        return YJIT_CANT_COMPILE;
    }

    const unsigned int off = cme->def->body.optimized.index;

    // Confidence checks
    RUBY_ASSERT_ALWAYS(RB_TYPE_P(comptime_recv, T_STRUCT));
    RUBY_ASSERT_ALWAYS((long)off < RSTRUCT_LEN(comptime_recv));

    // We are going to use an encoding that takes a 4-byte immediate which
    // limits the offset to INT32_MAX.
    {
        uint64_t native_off = (uint64_t)off * (uint64_t)SIZEOF_VALUE;
        if (native_off > (uint64_t)INT32_MAX) {
            return YJIT_CANT_COMPILE;
        }
    }

    // All structs from the same Struct class should have the same
    // length. So if our comptime_recv is embedded all runtime
    // structs of the same class should be as well, and the same is
    // true of the converse.
    bool embedded = FL_TEST_RAW(comptime_recv, RSTRUCT_EMBED_LEN_MASK);

    ADD_COMMENT(cb, "struct aref");

    x86opnd_t recv = ctx_stack_pop(ctx, 1);

    mov(cb, REG0, recv);

    if (embedded) {
        mov(cb, REG0, member_opnd_idx(REG0, struct RStruct, as.ary, off));
    }
    else {
        mov(cb, REG0, member_opnd(REG0, struct RStruct, as.heap.ptr));
        mov(cb, REG0, mem_opnd(64, REG0, SIZEOF_VALUE * off));
    }

    x86opnd_t ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, ret, REG0);

    jit_jump_to_next_insn(jit, ctx);
    return YJIT_END_BLOCK;
}

static codegen_status_t
gen_struct_aset(jitstate_t *jit, ctx_t *ctx, const struct rb_callinfo *ci, const rb_callable_method_entry_t *cme, VALUE comptime_recv, VALUE comptime_recv_klass) {
    if (vm_ci_argc(ci) != 1) {
        return YJIT_CANT_COMPILE;
    }

    const unsigned int off = cme->def->body.optimized.index;

    // Confidence checks
    RUBY_ASSERT_ALWAYS(RB_TYPE_P(comptime_recv, T_STRUCT));
    RUBY_ASSERT_ALWAYS((long)off < RSTRUCT_LEN(comptime_recv));

    ADD_COMMENT(cb, "struct aset");

    x86opnd_t val = ctx_stack_pop(ctx, 1);
    x86opnd_t recv = ctx_stack_pop(ctx, 1);

    mov(cb, C_ARG_REGS[0], recv);
    mov(cb, C_ARG_REGS[1], imm_opnd(off));
    mov(cb, C_ARG_REGS[2], val);
    call_ptr(cb, REG0, (void *)RSTRUCT_SET);

    x86opnd_t ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, ret, RAX);

    jit_jump_to_next_insn(jit, ctx);
    return YJIT_END_BLOCK;
}

const rb_callable_method_entry_t *
rb_aliased_callable_method_entry(const rb_callable_method_entry_t *me);

static codegen_status_t
gen_send_general(jitstate_t *jit, ctx_t *ctx, struct rb_call_data *cd, rb_iseq_t *block)
{
    // Relevant definitions:
    // rb_execution_context_t       : vm_core.h
    // invoker, cfunc logic         : method.h, vm_method.c
    // rb_callinfo                  : vm_callinfo.h
    // rb_callable_method_entry_t   : method.h
    // vm_call_cfunc_with_frame     : vm_insnhelper.c
    //
    // For a general overview for how the interpreter calls methods,
    // see vm_call_method().

    const struct rb_callinfo *ci = cd->ci; // info about the call site

    int32_t argc = (int32_t)vm_ci_argc(ci);
    ID mid = vm_ci_mid(ci);

    // Don't JIT calls with keyword splat
    if (vm_ci_flag(ci) & VM_CALL_KW_SPLAT) {
        GEN_COUNTER_INC(cb, send_kw_splat);
        return YJIT_CANT_COMPILE;
    }

    // Don't JIT calls that aren't simple
    // Note, not using VM_CALL_ARGS_SIMPLE because sometimes we pass a block.
    if ((vm_ci_flag(ci) & VM_CALL_ARGS_SPLAT) != 0) {
        GEN_COUNTER_INC(cb, send_args_splat);
        return YJIT_CANT_COMPILE;
    }
    if ((vm_ci_flag(ci) & VM_CALL_ARGS_BLOCKARG) != 0) {
        GEN_COUNTER_INC(cb, send_block_arg);
        return YJIT_CANT_COMPILE;
    }

    // Defer compilation so we can specialize on class of receiver
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    VALUE comptime_recv = jit_peek_at_stack(jit, ctx, argc);
    VALUE comptime_recv_klass = CLASS_OF(comptime_recv);

    // Guard that the receiver has the same class as the one from compile time
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // Points to the receiver operand on the stack
    x86opnd_t recv = ctx_stack_opnd(ctx, argc);
    insn_opnd_t recv_opnd = OPND_STACK(argc);
    mov(cb, REG0, recv);
    if (!jit_guard_known_klass(jit, ctx, comptime_recv_klass, recv_opnd, comptime_recv, SEND_MAX_DEPTH, side_exit)) {
        return YJIT_CANT_COMPILE;
    }

    // Do method lookup
    const rb_callable_method_entry_t *cme = rb_callable_method_entry(comptime_recv_klass, mid);
    if (!cme) {
        // TODO: counter
        return YJIT_CANT_COMPILE;
    }

    switch (METHOD_ENTRY_VISI(cme)) {
      case METHOD_VISI_PUBLIC:
        // Can always call public methods
        break;
      case METHOD_VISI_PRIVATE:
        if (!(vm_ci_flag(ci) & VM_CALL_FCALL)) {
            // Can only call private methods with FCALL callsites.
            // (at the moment they are callsites without a receiver or an explicit `self` receiver)
            return YJIT_CANT_COMPILE;
        }
        break;
      case METHOD_VISI_PROTECTED:
        jit_protected_callee_ancestry_guard(jit, cb, cme, side_exit);
        break;
      case METHOD_VISI_UNDEF:
        RUBY_ASSERT(false && "cmes should always have a visibility");
        break;
    }

    // Register block for invalidation
    RUBY_ASSERT(cme->called_id == mid);
    assume_method_lookup_stable(comptime_recv_klass, cme, jit);

    // To handle the aliased method case (VM_METHOD_TYPE_ALIAS)
    while (true) {
        // switch on the method type
        switch (cme->def->type) {
          case VM_METHOD_TYPE_ISEQ:
            return gen_send_iseq(jit, ctx, ci, cme, block, argc);
          case VM_METHOD_TYPE_CFUNC:
            if ((vm_ci_flag(ci) & VM_CALL_KWARG) != 0) {
                GEN_COUNTER_INC(cb, send_cfunc_kwargs);
                return YJIT_CANT_COMPILE;
            }
            return gen_send_cfunc(jit, ctx, ci, cme, block, argc, &comptime_recv_klass);
          case VM_METHOD_TYPE_IVAR:
            if (argc != 0) {
                // Argument count mismatch. Getters take no arguments.
                GEN_COUNTER_INC(cb, send_getter_arity);
                return YJIT_CANT_COMPILE;
            }
            if (c_method_tracing_currently_enabled(jit)) {
                // Can't generate code for firing c_call and c_return events
                // :attr-tracing:
                // Handling the C method tracing events for attr_accessor
                // methods is easier than regular C methods as we know the
                // "method" we are calling into never enables those tracing
                // events. Once global invalidation runs, the code for the
                // attr_accessor is invalidated and we exit at the closest
                // instruction boundary which is always outside of the body of
                // the attr_accessor code.
                GEN_COUNTER_INC(cb, send_cfunc_tracing);
                return YJIT_CANT_COMPILE;
            }

            mov(cb, REG0, recv);

            ID ivar_name = cme->def->body.attr.id;
            return gen_get_ivar(jit, ctx, SEND_MAX_DEPTH, comptime_recv, ivar_name, recv_opnd, side_exit);
          case VM_METHOD_TYPE_ATTRSET:
            if ((vm_ci_flag(ci) & VM_CALL_KWARG) != 0) {
                GEN_COUNTER_INC(cb, send_attrset_kwargs);
                return YJIT_CANT_COMPILE;
            }
            else if (argc != 1 || !RB_TYPE_P(comptime_recv, T_OBJECT)) {
                GEN_COUNTER_INC(cb, send_ivar_set_method);
                return YJIT_CANT_COMPILE;
            }
            else if (c_method_tracing_currently_enabled(jit)) {
                // Can't generate code for firing c_call and c_return events
                // See :attr-tracing:
                GEN_COUNTER_INC(cb, send_cfunc_tracing);
                return YJIT_CANT_COMPILE;
            }
            else {
                ID ivar_name = cme->def->body.attr.id;
                return gen_set_ivar(jit, ctx, comptime_recv, comptime_recv_klass, ivar_name);
            }
          // Block method, e.g. define_method(:foo) { :my_block }
          case VM_METHOD_TYPE_BMETHOD:
            GEN_COUNTER_INC(cb, send_bmethod);
            return YJIT_CANT_COMPILE;
          case VM_METHOD_TYPE_ZSUPER:
            GEN_COUNTER_INC(cb, send_zsuper_method);
            return YJIT_CANT_COMPILE;
          case VM_METHOD_TYPE_ALIAS: {
            // Retrieve the alised method and re-enter the switch
            cme = rb_aliased_callable_method_entry(cme);
            continue;
          }
          case VM_METHOD_TYPE_UNDEF:
            GEN_COUNTER_INC(cb, send_undef_method);
            return YJIT_CANT_COMPILE;
          case VM_METHOD_TYPE_NOTIMPLEMENTED:
            GEN_COUNTER_INC(cb, send_not_implemented_method);
            return YJIT_CANT_COMPILE;
          // Send family of methods, e.g. call/apply
          case VM_METHOD_TYPE_OPTIMIZED:
            switch (cme->def->body.optimized.type) {
              case OPTIMIZED_METHOD_TYPE_SEND:
                GEN_COUNTER_INC(cb, send_optimized_method_send);
                return YJIT_CANT_COMPILE;
              case OPTIMIZED_METHOD_TYPE_CALL:
                GEN_COUNTER_INC(cb, send_optimized_method_call);
                return YJIT_CANT_COMPILE;
              case OPTIMIZED_METHOD_TYPE_BLOCK_CALL:
                GEN_COUNTER_INC(cb, send_optimized_method_block_call);
                return YJIT_CANT_COMPILE;
              case OPTIMIZED_METHOD_TYPE_STRUCT_AREF:
                return gen_struct_aref(jit, ctx, ci, cme, comptime_recv, comptime_recv_klass);
              case OPTIMIZED_METHOD_TYPE_STRUCT_ASET:
                return gen_struct_aset(jit, ctx, ci, cme, comptime_recv, comptime_recv_klass);
              default:
                rb_bug("unknown optimized method type (%d)", cme->def->body.optimized.type);
                UNREACHABLE_RETURN(YJIT_CANT_COMPILE);
            }
          case VM_METHOD_TYPE_MISSING:
            GEN_COUNTER_INC(cb, send_missing_method);
            return YJIT_CANT_COMPILE;
          case VM_METHOD_TYPE_REFINED:
            GEN_COUNTER_INC(cb, send_refined_method);
            return YJIT_CANT_COMPILE;
            // no default case so compiler issues a warning if this is not exhaustive
        }

        // Unreachable
        RUBY_ASSERT(false);
    }
}

static codegen_status_t
gen_opt_send_without_block(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    struct rb_call_data *cd = (struct rb_call_data *)jit_get_arg(jit, 0);
    return gen_send_general(jit, ctx, cd, NULL);
}

static codegen_status_t
gen_send(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    struct rb_call_data *cd = (struct rb_call_data *)jit_get_arg(jit, 0);
    rb_iseq_t *block = (rb_iseq_t *)jit_get_arg(jit, 1);
    return gen_send_general(jit, ctx, cd, block);
}

static codegen_status_t
gen_invokesuper(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    struct rb_call_data *cd = (struct rb_call_data *)jit_get_arg(jit, 0);
    rb_iseq_t *block = (rb_iseq_t *)jit_get_arg(jit, 1);

    // Defer compilation so we can specialize on class of receiver
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(jit->ec->cfp);
    if (!me) {
        return YJIT_CANT_COMPILE;
    }

    // FIXME: We should track and invalidate this block when this cme is invalidated
    VALUE current_defined_class = me->defined_class;
    ID mid = me->def->original_id;

    if (me != rb_callable_method_entry(current_defined_class, me->called_id)) {
        // Though we likely could generate this call, as we are only concerned
        // with the method entry remaining valid, assume_method_lookup_stable
        // below requires that the method lookup matches as well
        return YJIT_CANT_COMPILE;
    }

    // vm_search_normal_superclass
    if (BUILTIN_TYPE(current_defined_class) == T_ICLASS && FL_TEST_RAW(RBASIC(current_defined_class)->klass, RMODULE_IS_REFINEMENT)) {
        return YJIT_CANT_COMPILE;
    }
    VALUE comptime_superclass = RCLASS_SUPER(RCLASS_ORIGIN(current_defined_class));

    const struct rb_callinfo *ci = cd->ci;
    int32_t argc = (int32_t)vm_ci_argc(ci);

    // Don't JIT calls that aren't simple
    // Note, not using VM_CALL_ARGS_SIMPLE because sometimes we pass a block.
    if ((vm_ci_flag(ci) & VM_CALL_ARGS_SPLAT) != 0) {
        GEN_COUNTER_INC(cb, send_args_splat);
        return YJIT_CANT_COMPILE;
    }
    if ((vm_ci_flag(ci) & VM_CALL_KWARG) != 0) {
        GEN_COUNTER_INC(cb, send_keywords);
        return YJIT_CANT_COMPILE;
    }
    if ((vm_ci_flag(ci) & VM_CALL_KW_SPLAT) != 0) {
        GEN_COUNTER_INC(cb, send_kw_splat);
        return YJIT_CANT_COMPILE;
    }
    if ((vm_ci_flag(ci) & VM_CALL_ARGS_BLOCKARG) != 0) {
        GEN_COUNTER_INC(cb, send_block_arg);
        return YJIT_CANT_COMPILE;
    }

    // Ensure we haven't rebound this method onto an incompatible class.
    // In the interpreter we try to avoid making this check by performing some
    // cheaper calculations first, but since we specialize on the method entry
    // and so only have to do this once at compile time this is fine to always
    // check and side exit.
    VALUE comptime_recv = jit_peek_at_stack(jit, ctx, argc);
    if (!rb_obj_is_kind_of(comptime_recv, current_defined_class)) {
        return YJIT_CANT_COMPILE;
    }

    // Do method lookup
    const rb_callable_method_entry_t *cme = rb_callable_method_entry(comptime_superclass, mid);

    if (!cme) {
        return YJIT_CANT_COMPILE;
    }

    // Check that we'll be able to write this method dispatch before generating checks
    switch (cme->def->type) {
      case VM_METHOD_TYPE_ISEQ:
      case VM_METHOD_TYPE_CFUNC:
        break;
      default:
        // others unimplemented
        return YJIT_CANT_COMPILE;
    }

    // Guard that the receiver has the same class as the one from compile time
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    if (jit->ec->cfp->ep[VM_ENV_DATA_INDEX_ME_CREF] != (VALUE)me) {
        // This will be the case for super within a block
        return YJIT_CANT_COMPILE;
    }

    ADD_COMMENT(cb, "guard known me");
    mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, ep));
    x86opnd_t ep_me_opnd = mem_opnd(64, REG0, SIZEOF_VALUE * VM_ENV_DATA_INDEX_ME_CREF);
    jit_mov_gc_ptr(jit, cb, REG1, (VALUE)me);
    cmp(cb, ep_me_opnd, REG1);
    jne_ptr(cb, COUNTED_EXIT(jit, side_exit, invokesuper_me_changed));

    if (!block) {
        // Guard no block passed
        // rb_vm_frame_block_handler(GET_EC()->cfp) == VM_BLOCK_HANDLER_NONE
        // note, we assume VM_ASSERT(VM_ENV_LOCAL_P(ep))
        //
        // TODO: this could properly forward the current block handler, but
        // would require changes to gen_send_*
        ADD_COMMENT(cb, "guard no block given");
        // EP is in REG0 from above
        x86opnd_t ep_specval_opnd = mem_opnd(64, REG0, SIZEOF_VALUE * VM_ENV_DATA_INDEX_SPECVAL);
        cmp(cb, ep_specval_opnd, imm_opnd(VM_BLOCK_HANDLER_NONE));
        jne_ptr(cb, COUNTED_EXIT(jit, side_exit, invokesuper_block));
    }

    // Points to the receiver operand on the stack
    x86opnd_t recv = ctx_stack_opnd(ctx, argc);
    mov(cb, REG0, recv);

    // We need to assume that both our current method entry and the super
    // method entry we invoke remain stable
    assume_method_lookup_stable(current_defined_class, me, jit);
    assume_method_lookup_stable(comptime_superclass, cme, jit);

    // Method calls may corrupt types
    ctx_clear_local_types(ctx);

    switch (cme->def->type) {
      case VM_METHOD_TYPE_ISEQ:
        return gen_send_iseq(jit, ctx, ci, cme, block, argc);
      case VM_METHOD_TYPE_CFUNC:
        return gen_send_cfunc(jit, ctx, ci, cme, block, argc, NULL);
      default:
        break;
    }

    RUBY_ASSERT_ALWAYS(false);
}

static codegen_status_t
gen_leave(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Only the return value should be on the stack
    RUBY_ASSERT(ctx->stack_size == 1);

    // Create a side-exit to fall back to the interpreter
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // Load environment pointer EP from CFP
    mov(cb, REG1, member_opnd(REG_CFP, rb_control_frame_t, ep));

    // Check for interrupts
    ADD_COMMENT(cb, "check for interrupts");
    yjit_check_ints(cb, COUNTED_EXIT(jit, side_exit, leave_se_interrupt));

    // Load the return value
    mov(cb, REG0, ctx_stack_pop(ctx, 1));

    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    add(cb, REG_CFP, imm_opnd(sizeof(rb_control_frame_t)));
    mov(cb, member_opnd(REG_EC, rb_execution_context_t, cfp), REG_CFP);

    // Reload REG_SP for the caller and write the return value.
    // Top of the stack is REG_SP[0] since the caller has sp_offset=1.
    mov(cb, REG_SP, member_opnd(REG_CFP, rb_control_frame_t, sp));
    mov(cb, mem_opnd(64, REG_SP, 0), REG0);

    // Jump to the JIT return address on the frame that was just popped
    const int32_t offset_to_jit_return = -((int32_t)sizeof(rb_control_frame_t)) + (int32_t)offsetof(rb_control_frame_t, jit_return);
    jmp_rm(cb, mem_opnd(64, REG_CFP, offset_to_jit_return));

    return YJIT_END_BLOCK;
}

RUBY_EXTERN rb_serial_t ruby_vm_global_constant_state;

static codegen_status_t
gen_getglobal(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    ID gid = jit_get_arg(jit, 0);

    // Save the PC and SP because we might make a Ruby call for warning
    jit_prepare_routine_call(jit, ctx, REG0);

    mov(cb, C_ARG_REGS[0], imm_opnd(gid));

    call_ptr(cb, REG0, (void *)&rb_gvar_get);

    x86opnd_t top = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, top, RAX);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_setglobal(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    ID gid = jit_get_arg(jit, 0);

    // Save the PC and SP because we might make a Ruby call for
    // Kernel#set_trace_var
    jit_prepare_routine_call(jit, ctx, REG0);

    mov(cb, C_ARG_REGS[0], imm_opnd(gid));

    x86opnd_t val = ctx_stack_pop(ctx, 1);

    mov(cb, C_ARG_REGS[1], val);

    call_ptr(cb, REG0, (void *)&rb_gvar_set);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_anytostring(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Save the PC and SP because we might make a Ruby call for
    // Kernel#set_trace_var
    jit_prepare_routine_call(jit, ctx, REG0);

    x86opnd_t str = ctx_stack_pop(ctx, 1);
    x86opnd_t val = ctx_stack_pop(ctx, 1);

    mov(cb, C_ARG_REGS[0], str);
    mov(cb, C_ARG_REGS[1], val);

    call_ptr(cb, REG0, (void *)&rb_obj_as_string_result);

    // Push the return value
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_STRING);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_objtostring(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    if (!jit_at_current_insn(jit)) {
        defer_compilation(jit, ctx);
        return YJIT_END_BLOCK;
    }

    x86opnd_t recv = ctx_stack_opnd(ctx, 0);
    VALUE comptime_recv = jit_peek_at_stack(jit, ctx, 0);

    if (RB_TYPE_P(comptime_recv, T_STRING)) {
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        mov(cb, REG0, recv);
        jit_guard_known_klass(jit, ctx, CLASS_OF(comptime_recv), OPND_STACK(0), comptime_recv, SEND_MAX_DEPTH, side_exit);
        // No work needed. The string value is already on the top of the stack.
        return YJIT_KEEP_COMPILING;
    }
    else {
        struct rb_call_data *cd = (struct rb_call_data *)jit_get_arg(jit, 0);
        return gen_send_general(jit, ctx, cd, NULL);
    }
}

static codegen_status_t
gen_toregexp(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    rb_num_t opt = jit_get_arg(jit, 0);
    rb_num_t cnt = jit_get_arg(jit, 1);

    // Save the PC and SP because this allocates an object and could
    // raise an exception.
    jit_prepare_routine_call(jit, ctx, REG0);

    x86opnd_t values_ptr = ctx_sp_opnd(ctx, -(sizeof(VALUE) * (uint32_t)cnt));
    ctx_stack_pop(ctx, cnt);

    mov(cb, C_ARG_REGS[0], imm_opnd(0));
    mov(cb, C_ARG_REGS[1], imm_opnd(cnt));
    lea(cb, C_ARG_REGS[2], values_ptr);
    call_ptr(cb, REG0, (void *)&rb_ary_tmp_new_from_values);

    // Save the array so we can clear it later
    push(cb, RAX);
    push(cb, RAX); // Alignment
    mov(cb, C_ARG_REGS[0], RAX);
    mov(cb, C_ARG_REGS[1], imm_opnd(opt));
    call_ptr(cb, REG0, (void *)&rb_reg_new_ary);

    // The actual regex is in RAX now.  Pop the temp array from
    // rb_ary_tmp_new_from_values into C arg regs so we can clear it
    pop(cb, REG1); // Alignment
    pop(cb, C_ARG_REGS[0]);

    // The value we want to push on the stack is in RAX right now
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, stack_ret, RAX);

    // Clear the temp array.
    call_ptr(cb, REG0, (void *)&rb_ary_clear);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_intern(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // Save the PC and SP because we might allocate
    jit_prepare_routine_call(jit, ctx, REG0);

    x86opnd_t str = ctx_stack_pop(ctx, 1);

    mov(cb, C_ARG_REGS[0], str);

    call_ptr(cb, REG0, (void *)&rb_str_intern);

    // Push the return value
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_getspecial(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // This takes two arguments, key and type
    // key is only used when type == 0
    // A non-zero type determines which type of backref to fetch
    //rb_num_t key = jit_get_arg(jit, 0);
    rb_num_t type = jit_get_arg(jit, 1);

    if (type == 0) {
        // not yet implemented
        return YJIT_CANT_COMPILE;
    }
    else if (type & 0x01) {
        // Fetch a "special" backref based on a char encoded by shifting by 1

        // Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, REG0);

        // call rb_backref_get()
        ADD_COMMENT(cb, "rb_backref_get");
        call_ptr(cb, REG0, (void *)rb_backref_get);
        mov(cb, C_ARG_REGS[0], RAX);

        switch (type >> 1) {
          case '&':
            ADD_COMMENT(cb, "rb_reg_last_match");
            call_ptr(cb, REG0, (void *)rb_reg_last_match);
            break;
          case '`':
            ADD_COMMENT(cb, "rb_reg_match_pre");
            call_ptr(cb, REG0, (void *)rb_reg_match_pre);
            break;
          case '\'':
            ADD_COMMENT(cb, "rb_reg_match_post");
            call_ptr(cb, REG0, (void *)rb_reg_match_post);
            break;
          case '+':
            ADD_COMMENT(cb, "rb_reg_match_last");
            call_ptr(cb, REG0, (void *)rb_reg_match_last);
            break;
          default:
            rb_bug("invalid back-ref");
        }

        x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, stack_ret, RAX);

        return YJIT_KEEP_COMPILING;
    }
    else {
        // Fetch the N-th match from the last backref based on type shifted by 1

        // Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, REG0);

        // call rb_backref_get()
        ADD_COMMENT(cb, "rb_backref_get");
        call_ptr(cb, REG0, (void *)rb_backref_get);

        // rb_reg_nth_match((int)(type >> 1), backref);
        ADD_COMMENT(cb, "rb_reg_nth_match");
        mov(cb, C_ARG_REGS[0], imm_opnd(type >> 1));
        mov(cb, C_ARG_REGS[1], RAX);
        call_ptr(cb, REG0, (void *)rb_reg_nth_match);

        x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, stack_ret, RAX);

        return YJIT_KEEP_COMPILING;
    }
}

VALUE
rb_vm_getclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *cfp, ID id, ICVARC ic);

static codegen_status_t
gen_getclassvariable(jitstate_t* jit, ctx_t* ctx, codeblock_t* cb)
{
    // rb_vm_getclassvariable can raise exceptions.
    jit_prepare_routine_call(jit, ctx, REG0);

    mov(cb, C_ARG_REGS[0], member_opnd(REG_CFP, rb_control_frame_t, iseq));
    mov(cb, C_ARG_REGS[1], REG_CFP);
    mov(cb, C_ARG_REGS[2], imm_opnd(jit_get_arg(jit, 0)));
    mov(cb, C_ARG_REGS[3], imm_opnd(jit_get_arg(jit, 1)));

    call_ptr(cb, REG0, (void *)rb_vm_getclassvariable);

    x86opnd_t stack_top = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, stack_top, RAX);

    return YJIT_KEEP_COMPILING;
}

VALUE
rb_vm_setclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *cfp, ID id, VALUE val, ICVARC ic);

static codegen_status_t
gen_setclassvariable(jitstate_t* jit, ctx_t* ctx, codeblock_t* cb)
{
    // rb_vm_setclassvariable can raise exceptions.
    jit_prepare_routine_call(jit, ctx, REG0);

    mov(cb, C_ARG_REGS[0], member_opnd(REG_CFP, rb_control_frame_t, iseq));
    mov(cb, C_ARG_REGS[1], REG_CFP);
    mov(cb, C_ARG_REGS[2], imm_opnd(jit_get_arg(jit, 0)));
    mov(cb, C_ARG_REGS[3], ctx_stack_pop(ctx, 1));
    mov(cb, C_ARG_REGS[4], imm_opnd(jit_get_arg(jit, 1)));

    call_ptr(cb, REG0, (void *)rb_vm_setclassvariable);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_opt_getinlinecache(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    VALUE jump_offset = jit_get_arg(jit, 0);
    VALUE const_cache_as_value = jit_get_arg(jit, 1);
    IC ic = (IC)const_cache_as_value;

    // See vm_ic_hit_p(). The same conditions are checked in yjit_constant_ic_update().
    struct iseq_inline_constant_cache_entry *ice = ic->entry;
    if (!ice || // cache not filled
        GET_IC_SERIAL(ice) != ruby_vm_global_constant_state /* cache out of date */) {
        // In these cases, leave a block that unconditionally side exits
        // for the interpreter to invalidate.
        return YJIT_CANT_COMPILE;
    }

    // Make sure there is an exit for this block as the interpreter might want
    // to invalidate this block from yjit_constant_ic_update().
    jit_ensure_block_entry_exit(jit);

    if (ice->ic_cref) {
        // Cache is keyed on a certain lexical scope. Use the interpreter's cache.
        uint8_t *side_exit = yjit_side_exit(jit, ctx);

        // Call function to verify the cache. It doesn't allocate or call methods.
        bool rb_vm_ic_hit_p(IC ic, const VALUE *reg_ep);
        mov(cb, C_ARG_REGS[0], const_ptr_opnd((void *)ic));
        mov(cb, C_ARG_REGS[1], member_opnd(REG_CFP, rb_control_frame_t, ep));
        call_ptr(cb, REG0, (void *)rb_vm_ic_hit_p);

        // Check the result. _Bool is one byte in SysV.
        test(cb, AL, AL);
        jz_ptr(cb, COUNTED_EXIT(jit, side_exit, opt_getinlinecache_miss));

        // Push ic->entry->value
        mov(cb, REG0, const_ptr_opnd((void *)ic));
        mov(cb, REG0, member_opnd(REG0, struct iseq_inline_constant_cache, entry));
        x86opnd_t stack_top = ctx_stack_push(ctx, TYPE_UNKNOWN);
        mov(cb, REG0, member_opnd(REG0, struct iseq_inline_constant_cache_entry, value));
        mov(cb, stack_top, REG0);
    }
    else {
        // Optimize for single ractor mode.
        // FIXME: This leaks when st_insert raises NoMemoryError
        if (!assume_single_ractor_mode(jit)) return YJIT_CANT_COMPILE;

        // Invalidate output code on any and all constant writes
        // FIXME: This leaks when st_insert raises NoMemoryError
        assume_stable_global_constant_state(jit);

        jit_putobject(jit, ctx, ice->value);
    }

    // Jump over the code for filling the cache
    uint32_t jump_idx = jit_next_insn_idx(jit) + (int32_t)jump_offset;
    gen_direct_jump(
        jit,
        ctx,
        (blockid_t){ .iseq = jit->iseq, .idx = jump_idx }
    );

    return YJIT_END_BLOCK;
}

// Push the explicit block parameter onto the temporary stack. Part of the
// interpreter's scheme for avoiding Proc allocations when delegating
// explicit block parameters.
static codegen_status_t
gen_getblockparamproxy(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    // A mirror of the interpreter code. Checking for the case
    // where it's pushing rb_block_param_proxy.
    uint8_t *side_exit = yjit_side_exit(jit, ctx);

    // EP level
    uint32_t level = (uint32_t)jit_get_arg(jit, 1);

    // Load environment pointer EP from CFP
    gen_get_ep(cb, REG0, level);

    // Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
    test(cb, mem_opnd(64, REG0, SIZEOF_VALUE * VM_ENV_DATA_INDEX_FLAGS), imm_opnd(VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM));
    jnz_ptr(cb, COUNTED_EXIT(jit, side_exit, gbpp_block_param_modified));

    // Load the block handler for the current frame
    // note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
    mov(cb, REG0, mem_opnd(64, REG0, SIZEOF_VALUE * VM_ENV_DATA_INDEX_SPECVAL));

    // Block handler is a tagged pointer. Look at the tag. 0x03 is from VM_BH_ISEQ_BLOCK_P().
    and(cb, REG0_8, imm_opnd(0x3));

    // Bail unless VM_BH_ISEQ_BLOCK_P(bh). This also checks for null.
    cmp(cb, REG0_8, imm_opnd(0x1));
    jnz_ptr(cb, COUNTED_EXIT(jit, side_exit, gbpp_block_handler_not_iseq));

    // Push rb_block_param_proxy. It's a root, so no need to use jit_mov_gc_ptr.
    mov(cb, REG0, const_ptr_opnd((void *)rb_block_param_proxy));
    RUBY_ASSERT(!SPECIAL_CONST_P(rb_block_param_proxy));
    x86opnd_t top = ctx_stack_push(ctx, TYPE_HEAP);
    mov(cb, top, REG0);

    return YJIT_KEEP_COMPILING;
}

static codegen_status_t
gen_invokebuiltin(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    const struct rb_builtin_function *bf = (struct rb_builtin_function *)jit_get_arg(jit, 0);

    // ec, self, and arguments
    if (bf->argc + 2 > NUM_C_ARG_REGS) {
        return YJIT_CANT_COMPILE;
    }

    // If the calls don't allocate, do they need up to date PC, SP?
    jit_prepare_routine_call(jit, ctx, REG0);

    // Call the builtin func (ec, recv, arg1, arg2, ...)
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(cb, C_ARG_REGS[1], member_opnd(REG_CFP, rb_control_frame_t, self));

    // Copy arguments from locals
    for (int32_t i = 0; i < bf->argc; i++) {
        x86opnd_t stack_opnd = ctx_stack_opnd(ctx, bf->argc - i - 1);
        x86opnd_t c_arg_reg = C_ARG_REGS[2 + i];
        mov(cb, c_arg_reg, stack_opnd);
    }

    call_ptr(cb, REG0, (void *)bf->func_ptr);

    // Push the return value
    ctx_stack_pop(ctx, bf->argc);
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

// opt_invokebuiltin_delegate calls a builtin function, like
// invokebuiltin does, but instead of taking arguments from the top of the
// stack uses the argument locals (and self) from the current method.
static codegen_status_t
gen_opt_invokebuiltin_delegate(jitstate_t *jit, ctx_t *ctx, codeblock_t *cb)
{
    const struct rb_builtin_function *bf = (struct rb_builtin_function *)jit_get_arg(jit, 0);
    int32_t start_index = (int32_t)jit_get_arg(jit, 1);

    // ec, self, and arguments
    if (bf->argc + 2 > NUM_C_ARG_REGS) {
        return YJIT_CANT_COMPILE;
    }

    // If the calls don't allocate, do they need up to date PC, SP?
    jit_prepare_routine_call(jit, ctx, REG0);

    if (bf->argc > 0) {
        // Load environment pointer EP from CFP
        mov(cb, REG0, member_opnd(REG_CFP, rb_control_frame_t, ep));
    }

    // Call the builtin func (ec, recv, arg1, arg2, ...)
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(cb, C_ARG_REGS[1], member_opnd(REG_CFP, rb_control_frame_t, self));

    // Copy arguments from locals
    for (int32_t i = 0; i < bf->argc; i++) {
        const int32_t offs = -jit->iseq->body->local_table_size - VM_ENV_DATA_SIZE + 1 + start_index + i;
        x86opnd_t local_opnd = mem_opnd(64, REG0, offs * SIZEOF_VALUE);
        x86opnd_t c_arg_reg = C_ARG_REGS[i + 2];
        mov(cb, c_arg_reg, local_opnd);
    }
    call_ptr(cb, REG0, (void *)bf->func_ptr);

    // Push the return value
    x86opnd_t stack_ret = ctx_stack_push(ctx, TYPE_UNKNOWN);
    mov(cb, stack_ret, RAX);

    return YJIT_KEEP_COMPILING;
}

static int tracing_invalidate_all_i(void *vstart, void *vend, size_t stride, void *data);
static void invalidate_all_blocks_for_tracing(const rb_iseq_t *iseq);

// Invalidate all generated code and patch C method return code to contain
// logic for firing the c_return TracePoint event. Once rb_vm_barrier()
// returns, all other ractors are pausing inside RB_VM_LOCK_ENTER(), which
// means they are inside a C routine. If there are any generated code on-stack,
// they are waiting for a return from a C routine. For every routine call, we
// patch in an exit after the body of the containing VM instruction. This makes
// it so all the invalidated code exit as soon as execution logically reaches
// the next VM instruction. The interpreter takes care of firing the tracing
// event if it so happens that the next VM instruction has one attached.
//
// The c_return event needs special handling as our codegen never outputs code
// that contains tracing logic. If we let the normal output code run until the
// start of the next VM instruction by relying on the patching scheme above, we
// would fail to fire the c_return event. The interpreter doesn't fire the
// event at an instruction boundary, so simply exiting to the interpreter isn't
// enough. To handle it, we patch in the full logic at the return address. See
// full_cfunc_return().
//
// In addition to patching, we prevent future entries into invalidated code by
// removing all live blocks from their iseq.
void
rb_yjit_tracing_invalidate_all(void)
{
    if (!rb_yjit_enabled_p()) return;

    // Stop other ractors since we are going to patch machine code.
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    // Make it so all live block versions are no longer valid branch targets
    rb_objspace_each_objects(tracing_invalidate_all_i, NULL);

    // Apply patches
    const uint32_t old_pos = cb->write_pos;
    rb_darray_for(global_inval_patches, patch_idx) {
        struct codepage_patch patch = rb_darray_get(global_inval_patches, patch_idx);
        cb_set_pos(cb, patch.inline_patch_pos);
        uint8_t *jump_target = cb_get_ptr(ocb, patch.outlined_target_pos);
        jmp_ptr(cb, jump_target);
    }
    cb_set_pos(cb, old_pos);

    // Freeze invalidated part of the codepage. We only want to wait for
    // running instances of the code to exit from now on, so we shouldn't
    // change the code. There could be other ractors sleeping in
    // branch_stub_hit(), for example. We could harden this by changing memory
    // protection on the frozen range.
    RUBY_ASSERT_ALWAYS(yjit_codepage_frozen_bytes <= old_pos && "frozen bytes should increase monotonically");
    yjit_codepage_frozen_bytes = old_pos;

    cb_mark_all_executable(ocb);
    cb_mark_all_executable(cb);
    RB_VM_LOCK_LEAVE();
}

static int
tracing_invalidate_all_i(void *vstart, void *vend, size_t stride, void *data)
{
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        void *ptr = asan_poisoned_object_p(v);
        asan_unpoison_object(v, false);

        if (rb_obj_is_iseq(v)) {
            rb_iseq_t *iseq = (rb_iseq_t *)v;
            invalidate_all_blocks_for_tracing(iseq);
        }

        asan_poison_object_if(ptr, v);
    }
    return 0;
}

static void
invalidate_all_blocks_for_tracing(const rb_iseq_t *iseq)
{
    struct rb_iseq_constant_body *body = iseq->body;
    if (!body) return; // iseq yet to be initialized

    ASSERT_vm_locking();

    // Empty all blocks on the iseq so we don't compile new blocks that jump to the
    // invalidted region.
    // TODO Leaking the blocks for now since we might have situations where
    // a different ractor is waiting in branch_stub_hit(). If we free the block
    // that ractor can wake up with a dangling block.
    rb_darray_for(body->yjit_blocks, version_array_idx) {
        rb_yjit_block_array_t version_array = rb_darray_get(body->yjit_blocks, version_array_idx);
        rb_darray_for(version_array, version_idx) {
            // Stop listening for invalidation events like basic operation redefinition.
            block_t *block = rb_darray_get(version_array, version_idx);
            yjit_unlink_method_lookup_dependency(block);
            yjit_block_assumptions_free(block);
        }
        rb_darray_free(version_array);
    }
    rb_darray_free(body->yjit_blocks);
    body->yjit_blocks = NULL;

#if USE_MJIT
    // Reset output code entry point
    body->jit_func = NULL;
#endif
}

static void
yjit_reg_op(int opcode, codegen_fn gen_fn)
{
    RUBY_ASSERT(opcode >= 0 && opcode < VM_INSTRUCTION_SIZE);
    // Check that the op wasn't previously registered
    RUBY_ASSERT(gen_fns[opcode] == NULL);

    gen_fns[opcode] = gen_fn;
}

void
yjit_init_codegen(void)
{
    // Initialize the code blocks
    uint32_t mem_size = rb_yjit_opts.exec_mem_size * 1024 * 1024;
    uint8_t *mem_block = alloc_exec_mem(mem_size);

    cb = &block;
    cb_init(cb, mem_block, mem_size/2);

    ocb = &outline_block;
    cb_init(ocb, mem_block + mem_size/2, mem_size/2);

    // Generate the interpreter exit code for leave
    leave_exit_code = yjit_gen_leave_exit(cb);

    // Generate full exit code for C func
    gen_full_cfunc_return();
    cb_mark_all_executable(cb);

    // Map YARV opcodes to the corresponding codegen functions
    yjit_reg_op(BIN(nop), gen_nop);
    yjit_reg_op(BIN(dup), gen_dup);
    yjit_reg_op(BIN(dupn), gen_dupn);
    yjit_reg_op(BIN(swap), gen_swap);
    yjit_reg_op(BIN(setn), gen_setn);
    yjit_reg_op(BIN(topn), gen_topn);
    yjit_reg_op(BIN(pop), gen_pop);
    yjit_reg_op(BIN(adjuststack), gen_adjuststack);
    yjit_reg_op(BIN(newarray), gen_newarray);
    yjit_reg_op(BIN(duparray), gen_duparray);
    yjit_reg_op(BIN(duphash), gen_duphash);
    yjit_reg_op(BIN(splatarray), gen_splatarray);
    yjit_reg_op(BIN(expandarray), gen_expandarray);
    yjit_reg_op(BIN(newhash), gen_newhash);
    yjit_reg_op(BIN(newrange), gen_newrange);
    yjit_reg_op(BIN(concatstrings), gen_concatstrings);
    yjit_reg_op(BIN(putnil), gen_putnil);
    yjit_reg_op(BIN(putobject), gen_putobject);
    yjit_reg_op(BIN(putstring), gen_putstring);
    yjit_reg_op(BIN(putobject_INT2FIX_0_), gen_putobject_int2fix);
    yjit_reg_op(BIN(putobject_INT2FIX_1_), gen_putobject_int2fix);
    yjit_reg_op(BIN(putself), gen_putself);
    yjit_reg_op(BIN(putspecialobject), gen_putspecialobject);
    yjit_reg_op(BIN(getlocal), gen_getlocal);
    yjit_reg_op(BIN(getlocal_WC_0), gen_getlocal_wc0);
    yjit_reg_op(BIN(getlocal_WC_1), gen_getlocal_wc1);
    yjit_reg_op(BIN(setlocal), gen_setlocal);
    yjit_reg_op(BIN(setlocal_WC_0), gen_setlocal_wc0);
    yjit_reg_op(BIN(setlocal_WC_1), gen_setlocal_wc1);
    yjit_reg_op(BIN(getinstancevariable), gen_getinstancevariable);
    yjit_reg_op(BIN(setinstancevariable), gen_setinstancevariable);
    yjit_reg_op(BIN(defined), gen_defined);
    yjit_reg_op(BIN(checktype), gen_checktype);
    yjit_reg_op(BIN(checkkeyword), gen_checkkeyword);
    yjit_reg_op(BIN(opt_lt), gen_opt_lt);
    yjit_reg_op(BIN(opt_le), gen_opt_le);
    yjit_reg_op(BIN(opt_ge), gen_opt_ge);
    yjit_reg_op(BIN(opt_gt), gen_opt_gt);
    yjit_reg_op(BIN(opt_eq), gen_opt_eq);
    yjit_reg_op(BIN(opt_neq), gen_opt_neq);
    yjit_reg_op(BIN(opt_aref), gen_opt_aref);
    yjit_reg_op(BIN(opt_aset), gen_opt_aset);
    yjit_reg_op(BIN(opt_and), gen_opt_and);
    yjit_reg_op(BIN(opt_or), gen_opt_or);
    yjit_reg_op(BIN(opt_minus), gen_opt_minus);
    yjit_reg_op(BIN(opt_plus), gen_opt_plus);
    yjit_reg_op(BIN(opt_mult), gen_opt_mult);
    yjit_reg_op(BIN(opt_div), gen_opt_div);
    yjit_reg_op(BIN(opt_mod), gen_opt_mod);
    yjit_reg_op(BIN(opt_ltlt), gen_opt_ltlt);
    yjit_reg_op(BIN(opt_nil_p), gen_opt_nil_p);
    yjit_reg_op(BIN(opt_empty_p), gen_opt_empty_p);
    yjit_reg_op(BIN(opt_str_freeze), gen_opt_str_freeze);
    yjit_reg_op(BIN(opt_str_uminus), gen_opt_str_uminus);
    yjit_reg_op(BIN(opt_not), gen_opt_not);
    yjit_reg_op(BIN(opt_size), gen_opt_size);
    yjit_reg_op(BIN(opt_length), gen_opt_length);
    yjit_reg_op(BIN(opt_regexpmatch2), gen_opt_regexpmatch2);
    yjit_reg_op(BIN(opt_getinlinecache), gen_opt_getinlinecache);
    yjit_reg_op(BIN(invokebuiltin), gen_invokebuiltin);
    yjit_reg_op(BIN(opt_invokebuiltin_delegate), gen_opt_invokebuiltin_delegate);
    yjit_reg_op(BIN(opt_invokebuiltin_delegate_leave), gen_opt_invokebuiltin_delegate);
    yjit_reg_op(BIN(opt_case_dispatch), gen_opt_case_dispatch);
    yjit_reg_op(BIN(branchif), gen_branchif);
    yjit_reg_op(BIN(branchunless), gen_branchunless);
    yjit_reg_op(BIN(branchnil), gen_branchnil);
    yjit_reg_op(BIN(jump), gen_jump);
    yjit_reg_op(BIN(getblockparamproxy), gen_getblockparamproxy);
    yjit_reg_op(BIN(opt_send_without_block), gen_opt_send_without_block);
    yjit_reg_op(BIN(send), gen_send);
    yjit_reg_op(BIN(invokesuper), gen_invokesuper);
    yjit_reg_op(BIN(leave), gen_leave);
    yjit_reg_op(BIN(getglobal), gen_getglobal);
    yjit_reg_op(BIN(setglobal), gen_setglobal);
    yjit_reg_op(BIN(anytostring), gen_anytostring);
    yjit_reg_op(BIN(objtostring), gen_objtostring);
    yjit_reg_op(BIN(toregexp), gen_toregexp);
    yjit_reg_op(BIN(intern), gen_intern);
    yjit_reg_op(BIN(getspecial), gen_getspecial);
    yjit_reg_op(BIN(getclassvariable), gen_getclassvariable);
    yjit_reg_op(BIN(setclassvariable), gen_setclassvariable);

    yjit_method_codegen_table = st_init_numtable();

    // Specialization for C methods. See yjit_reg_method() for details.
    yjit_reg_method(rb_cBasicObject, "!", jit_rb_obj_not);

    yjit_reg_method(rb_cNilClass, "nil?", jit_rb_true);
    yjit_reg_method(rb_mKernel, "nil?", jit_rb_false);

    yjit_reg_method(rb_cBasicObject, "==", jit_rb_obj_equal);
    yjit_reg_method(rb_cBasicObject, "equal?", jit_rb_obj_equal);
    yjit_reg_method(rb_mKernel, "eql?", jit_rb_obj_equal);
    yjit_reg_method(rb_cModule, "==", jit_rb_obj_equal);
    yjit_reg_method(rb_cSymbol, "==", jit_rb_obj_equal);
    yjit_reg_method(rb_cSymbol, "===", jit_rb_obj_equal);

    // rb_str_to_s() methods in string.c
    yjit_reg_method(rb_cString, "to_s", jit_rb_str_to_s);
    yjit_reg_method(rb_cString, "to_str", jit_rb_str_to_s);
    yjit_reg_method(rb_cString, "bytesize", jit_rb_str_bytesize);

    // Thread.current
    yjit_reg_method(rb_singleton_class(rb_cThread), "current", jit_thread_s_current);
}
