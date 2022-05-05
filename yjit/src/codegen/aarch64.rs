use crate::asm::aarch64::*;
use crate::asm::*;
use crate::cruby::*;
use crate::codegen::*;

// Callee-saved registers
pub const REG_CFP: YJitOpnd = X21;
pub const REG_EC: YJitOpnd = X20;
pub const REG_SP: YJitOpnd = X19;

// Scratch registers used by YJIT
pub const REG0: YJitOpnd = X0;
// pub const REG1: YJitOpnd = X1;

// Save the incremented PC on the CFP
// This is necessary when callees can raise or allocate
#[allow(unused)]
pub fn jit_save_pc(jit: &JITState, cb: &mut CodeBlock, scratch_reg: YJitOpnd) {
    unreachable!("unimplemented yet: jit_save_pc");
}

/// Save the current SP on the CFP
/// This realigns the interpreter SP with the JIT SP
/// Note: this will change the current value of REG_SP,
///       which could invalidate memory operands
#[allow(unused)]
pub fn gen_save_sp(cb: &mut CodeBlock, ctx: &mut Context) {
    unreachable!("unimplemented yet: gen_save_sp");
}

/// Generate an exit to return to the interpreter
pub fn gen_exit(exit_pc: *mut VALUE, ctx: &Context, cb: &mut CodeBlock) -> CodePtr {
    let code_ptr = cb.get_write_ptr();

    add_comment(cb, "exit to interpreter");

    // Generate the code to exit to the interpreters
    // Write the adjusted SP back into the CFP
    if ctx.get_sp_offset() != 0 {
        add(cb, REG_SP, REG_SP, ctx.sp_imm_opnd(0));
        str(cb, REG_SP, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SP));
    }

    // Update CFP->PC
    mov_u64(cb, X0, exit_pc as u64);
    str(cb, X0, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_PC));

    // Accumulate stats about interpreter exits
    #[cfg(feature = "stats")]
    if get_option!(gen_stats) {
        mov(cb, RDI, const_ptr_opnd(exit_pc as *const u8));
        call_ptr(cb, RSI, rb_yjit_count_side_exit_op as *const u8);
    }

    ldp(cb, REG_EC, REG_SP, mem_post_opnd(64, SP, 16));
    ldp(cb, X30, REG_CFP, mem_post_opnd(64, SP, 16));

    mov_u64(cb, X0, Qundef.into());
    ret(cb, X30);

    return code_ptr;
}
// Fill code_for_exit_from_stub. This is used by branch_stub_hit() to exit
// to the interpreter when it cannot service a stub by generating new code.
// Before coming here, branch_stub_hit() takes care of fully reconstructing
// interpreter state.
pub fn gen_code_for_exit_from_stub(ocb: &mut OutlinedCb) -> CodePtr {
    let ocb = ocb.unwrap();
    let code_ptr = ocb.get_write_ptr();

    gen_counter_incr!(ocb, exit_from_branch_stub);

    ldp(ocb, REG_EC, REG_SP, mem_post_opnd(64, SP, 16));
    ldp(ocb, X30, REG_CFP, mem_post_opnd(64, SP, 16));

    mov_u64(ocb, X0, Qundef.into());
    ret(ocb, X30);

    return code_ptr;
}

// Generate a runtime guard that ensures the PC is at the expected
// instruction index in the iseq, otherwise takes a side-exit.
// This is to handle the situation of optional parameters.
// When a function with optional parameters is called, the entry
// PC for the method isn't necessarily 0.
fn gen_pc_guard(_cb: &mut CodeBlock, _iseq: IseqPtr, _insn_idx: u32) {
    unreachable!("unimplemented yet: gen_pc_guard")
}

// Landing code for when c_return tracing is enabled. See full_cfunc_return().
pub fn gen_full_cfunc_return(ocb: &mut OutlinedCb) -> CodePtr {
    let cb = ocb.unwrap();
    let code_ptr = cb.get_write_ptr();

    // This chunk of code expect REG_EC to be filled properly and
    // RAX to contain the return value of the C method.

    // Call full_cfunc_return()
    // TODO

    // Count the exit
    gen_counter_incr!(cb, traced_cfunc_return);

    // Return to the interpreter
    // TODO

    return code_ptr;
}

/// Generate a continuation for leave that exits to the interpreter at REG_CFP->pc.
/// This is used by gen_leave() and gen_entry_prologue()
pub fn gen_leave_exit(ocb: &mut OutlinedCb) -> CodePtr {
    let ocb = ocb.unwrap();
    let code_ptr = ocb.get_write_ptr();

    // Note, gen_leave() fully reconstructs interpreter state and leaves the
    // return value in RAX before coming here.

    // Every exit to the interpreter should be counted
    gen_counter_incr!(ocb, leave_interp_return);

    ldp(ocb, REG_EC, REG_SP, mem_post_opnd(64, SP, 16));
    ldp(ocb, X30, REG_CFP, mem_post_opnd(64, SP, 16));

    ret(ocb, X30);

    return code_ptr;
}

/// Compile an interpreter entry block to be inserted into an iseq
/// Returns None if compilation fails.
pub fn gen_entry_prologue(cb: &mut CodeBlock, iseq: IseqPtr, insn_idx: u32) -> Option<CodePtr> {
    const MAX_PROLOGUE_SIZE: usize = 1024;

    // Check if we have enough executable memory
    if !cb.has_capacity(MAX_PROLOGUE_SIZE) {
        return None;
    }

    let old_write_pos = cb.get_write_pos();

    // Align the current write position to cache line boundaries
    cb.align_pos(64);

    let code_ptr = cb.get_write_ptr();
    add_comment(cb, "yjit entry");

    stp(cb, X30, REG_CFP, mem_pre_opnd(64, SP, -16));
    stp(cb, REG_EC, REG_SP, mem_pre_opnd(64, SP, -16));

    // We are passed EC and CFP
    mov(cb, REG_EC, X0);
    mov(cb, REG_CFP, X1);

    // Load the current SP from the CFP into REG_SP
    ldr(cb, REG_SP, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SP));

    // Setup cfp->jit_return
    // TODO: this could use an IP relative LEA instead of an 8 byte immediate
    mov_u64(cb, REG0, CodegenGlobals::get_leave_exit_code().raw_ptr() as u64);
    str(cb, REG0, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_JIT_RETURN));

    // We're compiling iseqs that we *expect* to start at `insn_idx`. But in
    // the case of optional parameters, the interpreter can set the pc to a
    // different location depending on the optional parameters.  If an iseq
    // has optional parameters, we'll add a runtime check that the PC we've
    // compiled for is the same PC that the interpreter wants us to run with.
    // If they don't match, then we'll take a side exit.
    if unsafe { get_iseq_flags_has_opt(iseq) } {
        gen_pc_guard(cb, iseq, insn_idx);
    }

    // Verify MAX_PROLOGUE_SIZE
    assert!(cb.get_write_pos() - old_write_pos <= MAX_PROLOGUE_SIZE);

    return Some(code_ptr);
}

fn gen_nop(
    _jit: &mut JITState,
    _ctx: &mut Context,
    _cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Do nothing
    KeepCompiling
}

fn gen_putnil(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    jit_putobject(jit, ctx, cb, Qnil);
    KeepCompiling
}

fn jit_putobject(_jit: &mut JITState, ctx: &mut Context, cb: &mut CodeBlock, arg: VALUE) {
    let val_type: Type = Type::from(arg);
    let stack_top = ctx.stack_push(val_type);

    if arg.special_const_p() {
        mov_u64(cb, REG0, arg.as_u64());
        str(cb, REG0, stack_top);
    } else {
        // TODO
        unreachable!("unimplemented: jit_putobject for not SPECIAL_CONST");
    }
}

/// Maps a YARV opcode to a code generation function (if supported)
pub fn get_gen_fn(opcode: VALUE) -> Option<InsnGenFn> {
    let VALUE(opcode) = opcode;
    assert!(opcode < VM_INSTRUCTION_SIZE);

    match opcode {
        OP_NOP => Some(gen_nop),
        OP_PUTNIL => Some(gen_putnil),

        // Unimplemented opcode, YJIT won't generate code for this yet
        _ => None,
    }
}

impl CodegenGlobals {
    /// Register codegen functions for some Ruby core methods
    pub fn reg_method_codegen_fns(&mut self) {
    }
}

pub fn gen_call_branch_stub_hit(_ocb: &mut CodeBlock, _target_idx: u32, _branch_ptr: *const u8, _branch_stub_hit_ptr: *mut u8) {
    unreachable!("unimplemented yet: gen_call_branch_stub_hit")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_codegen() -> (JITState, Context, CodeBlock, OutlinedCb) {
        let blockid = BlockId {
            iseq: ptr::null(),
            idx: 0,
        };
        let block = Block::new(blockid, &Context::default());

        return (
            JITState::new(&block),
            Context::new(),
            CodeBlock::new_dummy(256 * 1024),
            OutlinedCb::wrap(CodeBlock::new_dummy(256 * 1024)),
        );
    }

    #[test]
    fn test_gen_exit() {
        let (_, ctx, mut cb, _) = setup_codegen();
        gen_exit(0 as *mut VALUE, &ctx, &mut cb);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_gen_nop() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        let status = gen_nop(&mut jit, &mut context, &mut cb, &mut ocb);

        assert_eq!(status, KeepCompiling);
        assert_eq!(context.diff(&Context::new()), 0);
        assert_eq!(cb.get_write_pos(), 0);
    }

    #[test]
    fn test_putnil() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        let status = gen_putnil(&mut jit, &mut context, &mut cb, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));

        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::Nil);
        assert!(cb.get_write_pos() > 0);
    }
}
