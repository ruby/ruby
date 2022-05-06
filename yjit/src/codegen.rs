// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::asm::x86_64::*;
use crate::asm::*;
use crate::core::*;
use crate::cruby::*;
use crate::invariants::*;
use crate::options::*;
use crate::stats::*;
use crate::utils::*;
use CodegenStatus::*;
use InsnOpnd::*;

use std::cell::RefMut;
use std::cmp;
use std::collections::HashMap;
use std::ffi::CStr;
use std::mem::{self, size_of};
use std::os::raw::c_uint;
use std::ptr;
use std::slice;

pub use crate::virtualmem::CodePtr;

// Callee-saved registers
pub const REG_CFP: X86Opnd = R13;
pub const REG_EC: X86Opnd = R12;
pub const REG_SP: X86Opnd = RBX;

// Scratch registers used by YJIT
pub const REG0: X86Opnd = RAX;
pub const REG0_32: X86Opnd = EAX;
pub const REG0_8: X86Opnd = AL;
pub const REG1: X86Opnd = RCX;
// pub const REG1_32: X86Opnd = ECX;

// A block that can be invalidated needs space to write a jump.
// We'll reserve a minimum size for any block that could
// be invalidated. In this case the JMP takes 5 bytes, but
// gen_send_general will always MOV the receiving object
// into place, so 2 bytes are always written automatically.
pub const JUMP_SIZE_IN_BYTES:usize = 3;

/// Status returned by code generation functions
#[derive(PartialEq, Debug)]
enum CodegenStatus {
    EndBlock,
    KeepCompiling,
    CantCompile,
}

/// Code generation function signature
type InsnGenFn = fn(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus;

/// Code generation state
/// This struct only lives while code is being generated
pub struct JITState {
    // Block version being compiled
    block: BlockRef,

    // Instruction sequence this is associated with
    iseq: IseqPtr,

    // Index of the current instruction being compiled
    insn_idx: u32,

    // Opcode for the instruction being compiled
    opcode: usize,

    // PC of the instruction being compiled
    pc: *mut VALUE,

    // Side exit to the instruction being compiled. See :side-exit:.
    side_exit_for_pc: Option<CodePtr>,

    // Execution context when compilation started
    // This allows us to peek at run-time values
    ec: Option<EcPtr>,

    // Whether we need to record the code address at
    // the end of this bytecode instruction for global invalidation
    record_boundary_patch_point: bool,
}

impl JITState {
    pub fn new(blockref: &BlockRef) -> Self {
        JITState {
            block: blockref.clone(),
            iseq: ptr::null(), // TODO: initialize this from the blockid
            insn_idx: 0,
            opcode: 0,
            pc: ptr::null_mut::<VALUE>(),
            side_exit_for_pc: None,
            ec: None,
            record_boundary_patch_point: false,
        }
    }

    pub fn get_block(&self) -> BlockRef {
        self.block.clone()
    }

    pub fn get_insn_idx(&self) -> u32 {
        self.insn_idx
    }

    pub fn get_iseq(self: &JITState) -> IseqPtr {
        self.iseq
    }

    pub fn get_opcode(self: &JITState) -> usize {
        self.opcode
    }

    pub fn add_gc_object_offset(self: &mut JITState, ptr_offset: u32) {
        let mut gc_obj_vec: RefMut<_> = self.block.borrow_mut();
        gc_obj_vec.add_gc_object_offset(ptr_offset);
    }

    pub fn get_pc(self: &JITState) -> *mut VALUE {
        self.pc
    }
}

use crate::codegen::JCCKinds::*;

#[allow(non_camel_case_types, unused)]
pub enum JCCKinds {
    JCC_JNE,
    JCC_JNZ,
    JCC_JZ,
    JCC_JE,
    JCC_JBE,
    JCC_JNA,
}

pub fn jit_get_arg(jit: &JITState, arg_idx: isize) -> VALUE {
    // insn_len require non-test config
    #[cfg(not(test))]
    assert!(insn_len(jit.get_opcode()) > (arg_idx + 1).try_into().unwrap());
    unsafe { *(jit.pc.offset(arg_idx + 1)) }
}

// Load a VALUE into a register and keep track of the reference if it is on the GC heap.
pub fn jit_mov_gc_ptr(jit: &mut JITState, cb: &mut CodeBlock, reg: X86Opnd, ptr: VALUE) {
    assert!(matches!(reg, X86Opnd::Reg(_)));
    assert!(reg.num_bits() == 64);

    // Load the pointer constant into the specified register
    mov(cb, reg, const_ptr_opnd(ptr.as_ptr()));

    // The pointer immediate is encoded as the last part of the mov written out
    let ptr_offset: u32 = (cb.get_write_pos() as u32) - (SIZEOF_VALUE as u32);

    if !ptr.special_const_p() {
        jit.add_gc_object_offset(ptr_offset);
    }
}

// Get the index of the next instruction
fn jit_next_insn_idx(jit: &JITState) -> u32 {
    jit.insn_idx + insn_len(jit.get_opcode())
}

// Check if we are compiling the instruction at the stub PC
// Meaning we are compiling the instruction that is next to execute
fn jit_at_current_insn(jit: &JITState) -> bool {
    let ec_pc: *mut VALUE = unsafe { get_cfp_pc(get_ec_cfp(jit.ec.unwrap())) };
    ec_pc == jit.pc
}

// Peek at the nth topmost value on the Ruby stack.
// Returns the topmost value when n == 0.
fn jit_peek_at_stack(jit: &JITState, ctx: &Context, n: isize) -> VALUE {
    assert!(jit_at_current_insn(jit));
    assert!(n < ctx.get_stack_size() as isize);

    // Note: this does not account for ctx->sp_offset because
    // this is only available when hitting a stub, and while
    // hitting a stub, cfp->sp needs to be up to date in case
    // codegen functions trigger GC. See :stub-sp-flush:.
    return unsafe {
        let sp: *mut VALUE = get_cfp_sp(get_ec_cfp(jit.ec.unwrap()));

        *(sp.offset(-1 - n))
    };
}

fn jit_peek_at_self(jit: &JITState) -> VALUE {
    unsafe { get_cfp_self(get_ec_cfp(jit.ec.unwrap())) }
}

fn jit_peek_at_local(jit: &JITState, n: i32) -> VALUE {
    assert!(jit_at_current_insn(jit));

    let local_table_size: isize = unsafe { get_iseq_body_local_table_size(jit.iseq) }
        .try_into()
        .unwrap();
    assert!(n < local_table_size.try_into().unwrap());

    unsafe {
        let ep = get_cfp_ep(get_ec_cfp(jit.ec.unwrap()));
        let n_isize: isize = n.try_into().unwrap();
        let offs: isize = -(VM_ENV_DATA_SIZE as isize) - local_table_size + n_isize + 1;
        *ep.offset(offs)
    }
}

// Add a comment at the current position in the code block
fn add_comment(cb: &mut CodeBlock, comment_str: &str) {
    if cfg!(feature = "asm_comments") {
        cb.add_comment(comment_str);
    }
}

/// Increment a profiling counter with counter_name
#[cfg(not(feature = "stats"))]
macro_rules! gen_counter_incr {
    ($cb:tt, $counter_name:ident) => {};
}
#[cfg(feature = "stats")]
macro_rules! gen_counter_incr {
    ($cb:tt, $counter_name:ident) => {
        if (get_option!(gen_stats)) {
            // Get a pointer to the counter variable
            let ptr = ptr_to_counter!($counter_name);

            // Use REG1 because there might be return value in REG0
            mov($cb, REG1, const_ptr_opnd(ptr as *const u8));
            write_lock_prefix($cb); // for ractors.
            add($cb, mem_opnd(64, REG1, 0), imm_opnd(1));
        }
    };
}

/// Increment a counter then take an existing side exit
#[cfg(not(feature = "stats"))]
macro_rules! counted_exit {
    ($ocb:tt, $existing_side_exit:tt, $counter_name:ident) => {{
        let _ = $ocb;
        $existing_side_exit
    }};
}
#[cfg(feature = "stats")]
macro_rules! counted_exit {
    ($ocb:tt, $existing_side_exit:tt, $counter_name:ident) => {
        // The counter is only incremented when stats are enabled
        if (!get_option!(gen_stats)) {
            $existing_side_exit
        } else {
            let ocb = $ocb.unwrap();
            let code_ptr = ocb.get_write_ptr();

            // Increment the counter
            gen_counter_incr!(ocb, $counter_name);

            // Jump to the existing side exit
            jmp_ptr(ocb, $existing_side_exit);

            // Pointer to the side-exit code
            code_ptr
        }
    };
}

// Save the incremented PC on the CFP
// This is necessary when callees can raise or allocate
fn jit_save_pc(jit: &JITState, cb: &mut CodeBlock, scratch_reg: X86Opnd) {
    let pc: *mut VALUE = jit.get_pc();
    let ptr: *mut VALUE = unsafe {
        let cur_insn_len = insn_len(jit.get_opcode()) as isize;
        pc.offset(cur_insn_len)
    };
    mov(cb, scratch_reg, const_ptr_opnd(ptr as *const u8));
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_PC), scratch_reg);
}

/// Save the current SP on the CFP
/// This realigns the interpreter SP with the JIT SP
/// Note: this will change the current value of REG_SP,
///       which could invalidate memory operands
fn gen_save_sp(cb: &mut CodeBlock, ctx: &mut Context) {
    if ctx.get_sp_offset() != 0 {
        let stack_pointer = ctx.sp_opnd(0);
        lea(cb, REG_SP, stack_pointer);
        let cfp_sp_opnd = mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SP);
        mov(cb, cfp_sp_opnd, REG_SP);
        ctx.set_sp_offset(0);
    }
}

/// jit_save_pc() + gen_save_sp(). Should be used before calling a routine that
/// could:
///  - Perform GC allocation
///  - Take the VM lock through RB_VM_LOCK_ENTER()
///  - Perform Ruby method call
fn jit_prepare_routine_call(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    scratch_reg: X86Opnd,
) {
    jit.record_boundary_patch_point = true;
    jit_save_pc(jit, cb, scratch_reg);
    gen_save_sp(cb, ctx);

    // In case the routine calls Ruby methods, it can set local variables
    // through Kernel#binding and other means.
    ctx.clear_local_types();
}

/// Record the current codeblock write position for rewriting into a jump into
/// the outlined block later. Used to implement global code invalidation.
fn record_global_inval_patch(cb: &mut CodeBlock, outline_block_target_pos: CodePtr) {
    CodegenGlobals::push_global_inval_patch(cb.get_write_ptr(), outline_block_target_pos);
}

/// Verify the ctx's types and mappings against the compile-time stack, self,
/// and locals.
fn verify_ctx(jit: &JITState, ctx: &Context) {
    fn obj_info_str<'a>(val: VALUE) -> &'a str {
        unsafe { CStr::from_ptr(rb_obj_info(val)).to_str().unwrap() }
    }

    // Only able to check types when at current insn
    assert!(jit_at_current_insn(jit));

    let self_val = jit_peek_at_self(jit);
    let self_val_type = Type::from(self_val);

    // Verify self operand type
    if self_val_type.diff(ctx.get_opnd_type(SelfOpnd)) == usize::MAX {
        panic!(
            "verify_ctx: ctx self type ({:?}) incompatible with actual value of self {}",
            ctx.get_opnd_type(SelfOpnd),
            obj_info_str(self_val)
        );
    }

    // Verify stack operand types
    let top_idx = cmp::min(ctx.get_stack_size(), MAX_TEMP_TYPES as u16);
    for i in 0..top_idx {
        let (learned_mapping, learned_type) = ctx.get_opnd_mapping(StackOpnd(i));
        let stack_val = jit_peek_at_stack(jit, ctx, i as isize);
        let val_type = Type::from(stack_val);

        match learned_mapping {
            TempMapping::MapToSelf => {
                if self_val != stack_val {
                    panic!(
                        "verify_ctx: stack value was mapped to self, but values did not match!\n  stack: {}\n  self: {}",
                        obj_info_str(stack_val),
                        obj_info_str(self_val)
                    );
                }
            }
            TempMapping::MapToLocal(local_idx) => {
                let local_val = jit_peek_at_local(jit, local_idx.into());
                if local_val != stack_val {
                    panic!(
                        "verify_ctx: stack value was mapped to local, but values did not match\n  stack: {}\n  local {}: {}",
                        obj_info_str(stack_val),
                        local_idx,
                        obj_info_str(local_val)
                    );
                }
            }
            TempMapping::MapToStack => {}
        }

        // If the actual type differs from the learned type
        if val_type.diff(learned_type) == usize::MAX {
            panic!(
                "verify_ctx: ctx type ({:?}) incompatible with actual value on stack: {}",
                learned_type,
                obj_info_str(stack_val)
            );
        }
    }

    // Verify local variable types
    let local_table_size = unsafe { get_iseq_body_local_table_size(jit.iseq) };
    let top_idx: usize = cmp::min(local_table_size as usize, MAX_TEMP_TYPES);
    for i in 0..top_idx {
        let learned_type = ctx.get_local_type(i);
        let local_val = jit_peek_at_local(jit, i as i32);
        let local_type = Type::from(local_val);

        if local_type.diff(learned_type) == usize::MAX {
            panic!(
                "verify_ctx: ctx type ({:?}) incompatible with actual value of local: {} (type {:?})",
                learned_type,
                obj_info_str(local_val),
                local_type
            );
        }
    }
}

/// Generate an exit to return to the interpreter
fn gen_exit(exit_pc: *mut VALUE, ctx: &Context, cb: &mut CodeBlock) -> CodePtr {
    let code_ptr = cb.get_write_ptr();

    add_comment(cb, "exit to interpreter");

    // Generate the code to exit to the interpreters
    // Write the adjusted SP back into the CFP
    if ctx.get_sp_offset() != 0 {
        let stack_pointer = ctx.sp_opnd(0);
        lea(cb, REG_SP, stack_pointer);
        mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SP), REG_SP);
    }

    // Update CFP->PC
    mov(cb, RAX, const_ptr_opnd(exit_pc as *const u8));
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_PC), RAX);

    // Accumulate stats about interpreter exits
    #[cfg(feature = "stats")]
    if get_option!(gen_stats) {
        mov(cb, RDI, const_ptr_opnd(exit_pc as *const u8));
        call_ptr(cb, RSI, rb_yjit_count_side_exit_op as *const u8);

        // If --yjit-trace-exits option is enabled, record the exit stack
        // while recording the side exits.
        if get_option!(gen_trace_exits) {
            mov(cb, C_ARG_REGS[0], const_ptr_opnd(exit_pc as *const u8));
            call_ptr(cb, REG0, rb_yjit_record_exit_stack as *const u8);
        }
    }

    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    mov(cb, RAX, uimm_opnd(Qundef.into()));
    ret(cb);

    return code_ptr;
}

// Fill code_for_exit_from_stub. This is used by branch_stub_hit() to exit
// to the interpreter when it cannot service a stub by generating new code.
// Before coming here, branch_stub_hit() takes care of fully reconstructing
// interpreter state.
fn gen_code_for_exit_from_stub(ocb: &mut OutlinedCb) -> CodePtr {
    let ocb = ocb.unwrap();
    let code_ptr = ocb.get_write_ptr();

    gen_counter_incr!(ocb, exit_from_branch_stub);

    pop(ocb, REG_SP);
    pop(ocb, REG_EC);
    pop(ocb, REG_CFP);

    mov(ocb, RAX, uimm_opnd(Qundef.into()));
    ret(ocb);

    return code_ptr;
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
fn get_side_exit(jit: &mut JITState, ocb: &mut OutlinedCb, ctx: &Context) -> CodePtr {
    match jit.side_exit_for_pc {
        None => {
            let exit_code = gen_exit(jit.pc, ctx, ocb.unwrap());
            jit.side_exit_for_pc = Some(exit_code);
            exit_code
        }
        Some(code_ptr) => code_ptr,
    }
}

// Ensure that there is an exit for the start of the block being compiled.
// Block invalidation uses this exit.
pub fn jit_ensure_block_entry_exit(jit: &mut JITState, ocb: &mut OutlinedCb) {
    let blockref = jit.block.clone();
    let mut block = blockref.borrow_mut();
    let block_ctx = block.get_ctx();
    let blockid = block.get_blockid();

    if block.entry_exit.is_some() {
        return;
    }

    if jit.insn_idx == blockid.idx {
        // We are compiling the first instruction in the block.
        // Generate the exit with the cache in jitstate.
        block.entry_exit = Some(get_side_exit(jit, ocb, &block_ctx));
    } else {
        let pc = unsafe { rb_iseq_pc_at_idx(blockid.iseq, blockid.idx) };
        block.entry_exit = Some(gen_exit(pc, &block_ctx, ocb.unwrap()));
    }
}

// Generate a runtime guard that ensures the PC is at the expected
// instruction index in the iseq, otherwise takes a side-exit.
// This is to handle the situation of optional parameters.
// When a function with optional parameters is called, the entry
// PC for the method isn't necessarily 0.
fn gen_pc_guard(cb: &mut CodeBlock, iseq: IseqPtr, insn_idx: u32) {
    //RUBY_ASSERT(cb != NULL);

    let pc_opnd = mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_PC);
    let expected_pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
    let expected_pc_opnd = const_ptr_opnd(expected_pc as *const u8);
    mov(cb, REG0, pc_opnd);
    mov(cb, REG1, expected_pc_opnd);
    cmp(cb, REG0, REG1);

    let pc_match = cb.new_label("pc_match".to_string());
    je_label(cb, pc_match);

    // We're not starting at the first PC, so we need to exit.
    gen_counter_incr!(cb, leave_start_pc_non_zero);

    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    mov(cb, RAX, imm_opnd(Qundef.into()));
    ret(cb);

    // PC should match the expected insn_idx
    cb.write_label(pc_match);
    cb.link_labels();
}

// Landing code for when c_return tracing is enabled. See full_cfunc_return().
fn gen_full_cfunc_return(ocb: &mut OutlinedCb) -> CodePtr {
    let cb = ocb.unwrap();
    let code_ptr = cb.get_write_ptr();

    // This chunk of code expect REG_EC to be filled properly and
    // RAX to contain the return value of the C method.

    // Call full_cfunc_return()
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(cb, C_ARG_REGS[1], RAX);
    call_ptr(cb, REG0, rb_full_cfunc_return as *const u8);

    // Count the exit
    gen_counter_incr!(cb, traced_cfunc_return);

    // Return to the interpreter
    pop(cb, REG_SP);
    pop(cb, REG_EC);
    pop(cb, REG_CFP);

    mov(cb, RAX, uimm_opnd(Qundef.into()));
    ret(cb);

    return code_ptr;
}

/// Generate a continuation for leave that exits to the interpreter at REG_CFP->pc.
/// This is used by gen_leave() and gen_entry_prologue()
fn gen_leave_exit(ocb: &mut OutlinedCb) -> CodePtr {
    let ocb = ocb.unwrap();
    let code_ptr = ocb.get_write_ptr();

    // Note, gen_leave() fully reconstructs interpreter state and leaves the
    // return value in RAX before coming here.

    // Every exit to the interpreter should be counted
    gen_counter_incr!(ocb, leave_interp_return);

    pop(ocb, REG_SP);
    pop(ocb, REG_EC);
    pop(ocb, REG_CFP);

    ret(ocb);

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

    push(cb, REG_CFP);
    push(cb, REG_EC);
    push(cb, REG_SP);

    // We are passed EC and CFP
    mov(cb, REG_EC, C_ARG_REGS[0]);
    mov(cb, REG_CFP, C_ARG_REGS[1]);

    // Load the current SP from the CFP into REG_SP
    mov(cb, REG_SP, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SP));

    // Setup cfp->jit_return
    mov(
        cb,
        REG0,
        code_ptr_opnd(CodegenGlobals::get_leave_exit_code()),
    );
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_JIT_RETURN), REG0);

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

// Generate code to check for interrupts and take a side-exit.
// Warning: this function clobbers REG0
fn gen_check_ints(cb: &mut CodeBlock, side_exit: CodePtr) {
    // Check for interrupts
    // see RUBY_VM_CHECK_INTS(ec) macro
    add_comment(cb, "RUBY_VM_CHECK_INTS(ec)");
    mov(
        cb,
        REG0_32,
        mem_opnd(32, REG_EC, RUBY_OFFSET_EC_INTERRUPT_MASK),
    );
    not(cb, REG0_32);
    test(
        cb,
        mem_opnd(32, REG_EC, RUBY_OFFSET_EC_INTERRUPT_FLAG),
        REG0_32,
    );
    jnz_ptr(cb, side_exit);
}

// Generate a stubbed unconditional jump to the next bytecode instruction.
// Blocks that are part of a guard chain can use this to share the same successor.
fn jump_to_next_insn(
    jit: &mut JITState,
    current_context: &Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) {
    // Reset the depth since in current usages we only ever jump to to
    // chain_depth > 0 from the same instruction.
    let mut reset_depth = *current_context;
    reset_depth.reset_chain_depth();

    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jit_next_insn_idx(jit),
    };

    // We are at the end of the current instruction. Record the boundary.
    if jit.record_boundary_patch_point {
        let next_insn = unsafe { jit.pc.offset(insn_len(jit.opcode).try_into().unwrap()) };
        let exit_pos = gen_exit(next_insn, &reset_depth, ocb.unwrap());
        record_global_inval_patch(cb, exit_pos);
        jit.record_boundary_patch_point = false;
    }

    // Generate the jump instruction
    gen_direct_jump(jit, &reset_depth, jump_block, cb);
}

// Compile a sequence of bytecode instructions for a given basic block version.
// Part of gen_block_version().
// Note: this function will mutate its context while generating code,
//       but the input start_ctx argument should remain immutable.
pub fn gen_single_block(
    blockid: BlockId,
    start_ctx: &Context,
    ec: EcPtr,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> Result<BlockRef, ()> {
    // Limit the number of specialized versions for this block
    let mut ctx = limit_block_versions(blockid, start_ctx);

    verify_blockid(blockid);
    assert!(!(blockid.idx == 0 && ctx.get_stack_size() > 0));

    // Instruction sequence to compile
    let iseq = blockid.iseq;
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let mut insn_idx: c_uint = blockid.idx;
    let starting_insn_idx = insn_idx;

    // Allocate the new block
    let blockref = Block::new(blockid, &ctx);

    // Initialize a JIT state object
    let mut jit = JITState::new(&blockref);
    jit.iseq = blockid.iseq;
    jit.ec = Some(ec);

    // Mark the start position of the block
    blockref.borrow_mut().set_start_addr(cb.get_write_ptr());

    // For each instruction to compile
    // NOTE: could rewrite this loop with a std::iter::Iterator
    while insn_idx < iseq_size {
        // Get the current pc and opcode
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
        // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
        let opcode: usize = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
            .try_into()
            .unwrap();

        // opt_getinlinecache wants to be in a block all on its own. Cut the block short
        // if we run into it. See gen_opt_getinlinecache() for details.
        if opcode == YARVINSN_opt_getinlinecache.as_usize() && insn_idx > starting_insn_idx {
            jump_to_next_insn(&mut jit, &ctx, cb, ocb);
            break;
        }

        // Set the current instruction
        jit.insn_idx = insn_idx;
        jit.opcode = opcode;
        jit.pc = pc;
        jit.side_exit_for_pc = None;

        // If previous instruction requested to record the boundary
        if jit.record_boundary_patch_point {
            // Generate an exit to this instruction and record it
            let exit_pos = gen_exit(jit.pc, &ctx, ocb.unwrap());
            record_global_inval_patch(cb, exit_pos);
            jit.record_boundary_patch_point = false;
        }

        // In debug mode, verify our existing assumption
        if cfg!(debug_assertions) && get_option!(verify_ctx) && jit_at_current_insn(&jit) {
            verify_ctx(&jit, &ctx);
        }

        // Lookup the codegen function for this instruction
        let mut status = CantCompile;
        if let Some(gen_fn) = get_gen_fn(VALUE(opcode)) {
            // :count-placement:
            // Count bytecode instructions that execute in generated code.
            // Note that the increment happens even when the output takes side exit.
            gen_counter_incr!(cb, exec_instruction);

            // Add a comment for the name of the YARV instruction
            add_comment(cb, &insn_name(opcode));

            // If requested, dump instructions for debugging
            if get_option!(dump_insns) {
                println!("compiling {}", insn_name(opcode));
                print_str(cb, &format!("executing {}", insn_name(opcode)));
            }

            // Call the code generation function
            status = gen_fn(&mut jit, &mut ctx, cb, ocb);
        }

        // If we can't compile this instruction
        // exit to the interpreter and stop compiling
        if status == CantCompile {
            let mut block = jit.block.borrow_mut();

            // TODO: if the codegen function makes changes to ctx and then return YJIT_CANT_COMPILE,
            // the exit this generates would be wrong. We could save a copy of the entry context
            // and assert that ctx is the same here.
            let exit = gen_exit(jit.pc, &ctx, cb);

            // If this is the first instruction in the block, then we can use
            // the exit for block->entry_exit.
            if insn_idx == block.get_blockid().idx {
                block.entry_exit = Some(exit);
            }

            break;
        }

        // For now, reset the chain depth after each instruction as only the
        // first instruction in the block can concern itself with the depth.
        ctx.reset_chain_depth();

        // Move to the next instruction to compile
        insn_idx += insn_len(opcode);

        // If the instruction terminates this block
        if status == EndBlock {
            break;
        }
    }

    // Finish filling out the block
    {
        let mut block = jit.block.borrow_mut();

        // Mark the end position of the block
        block.set_end_addr(cb.get_write_ptr());

        // Store the index of the last instruction in the block
        block.set_end_idx(insn_idx);
    }

    // We currently can't handle cases where the request is for a block that
    // doesn't go to the next instruction.
    //assert!(!jit.record_boundary_patch_point);

    // If code for the block doesn't fit, fail
    if cb.has_dropped_bytes() || ocb.unwrap().has_dropped_bytes() {
        return Err(());
    }

    // TODO: we may want a feature for this called dump_insns? Can leave commented for now
    /*
    if (YJIT_DUMP_MODE >= 2) {
        // Dump list of compiled instrutions
        fprintf(stderr, "Compiled the following for iseq=%p:\n", (void *)iseq);
        for (uint32_t idx = block->blockid.idx; idx < insn_idx; ) {
            int opcode = yjit_opcode_at_pc(iseq, yjit_iseq_pc_at_idx(iseq, idx));
            fprintf(stderr, "  %04d %s\n", idx, insn_name(opcode));
            idx += insn_len(opcode);
        }
    }
    */

    // Block compiled successfully
    Ok(blockref)
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

fn gen_pop(
    _jit: &mut JITState,
    ctx: &mut Context,
    _cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Decrement SP
    ctx.stack_pop(1);
    KeepCompiling
}

fn gen_dup(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let dup_val = ctx.stack_pop(0);
    let (mapping, tmp_type) = ctx.get_opnd_mapping(StackOpnd(0));

    let loc0 = ctx.stack_push_mapping((mapping, tmp_type));
    mov(cb, REG0, dup_val);
    mov(cb, loc0, REG0);

    KeepCompiling
}

// duplicate stack top n elements
fn gen_dupn(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let nval: VALUE = jit_get_arg(jit, 0);
    let VALUE(n) = nval;

    // In practice, seems to be only used for n==2
    if n != 2 {
        return CantCompile;
    }

    let opnd1: X86Opnd = ctx.stack_opnd(1);
    let opnd0: X86Opnd = ctx.stack_opnd(0);

    let mapping1 = ctx.get_opnd_mapping(StackOpnd(1));
    let mapping0 = ctx.get_opnd_mapping(StackOpnd(0));

    let dst1: X86Opnd = ctx.stack_push_mapping(mapping1);
    mov(cb, REG0, opnd1);
    mov(cb, dst1, REG0);

    let dst0: X86Opnd = ctx.stack_push_mapping(mapping0);
    mov(cb, REG0, opnd0);
    mov(cb, dst0, REG0);

    KeepCompiling
}

// Swap top 2 stack entries
fn gen_swap(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    stack_swap(ctx, cb, 0, 1, REG0, REG1);
    KeepCompiling
}

fn stack_swap(
    ctx: &mut Context,
    cb: &mut CodeBlock,
    offset0: u16,
    offset1: u16,
    _reg0: X86Opnd,
    _reg1: X86Opnd,
) {
    let opnd0 = ctx.stack_opnd(offset0 as i32);
    let opnd1 = ctx.stack_opnd(offset1 as i32);

    let mapping0 = ctx.get_opnd_mapping(StackOpnd(offset0));
    let mapping1 = ctx.get_opnd_mapping(StackOpnd(offset1));

    mov(cb, REG0, opnd0);
    mov(cb, REG1, opnd1);
    mov(cb, opnd0, REG1);
    mov(cb, opnd1, REG0);

    ctx.set_opnd_mapping(StackOpnd(offset0), mapping1);
    ctx.set_opnd_mapping(StackOpnd(offset1), mapping0);
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

fn jit_putobject(jit: &mut JITState, ctx: &mut Context, cb: &mut CodeBlock, arg: VALUE) {
    let val_type: Type = Type::from(arg);
    let stack_top = ctx.stack_push(val_type);

    if arg.special_const_p() {
        // Immediates will not move and do not need to be tracked for GC
        // Thanks to this we can mov directly to memory when possible.
        let imm = imm_opnd(arg.as_i64());

        // 64-bit immediates can't be directly written to memory
        if imm.num_bits() <= 32 {
            mov(cb, stack_top, imm);
        } else {
            mov(cb, REG0, imm);
            mov(cb, stack_top, REG0);
        }
    } else {
        // Load the value to push into REG0
        // Note that this value may get moved by the GC
        jit_mov_gc_ptr(jit, cb, REG0, arg);

        // Write argument at SP
        mov(cb, stack_top, REG0);
    }
}

fn gen_putobject_int2fix(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let opcode = jit.opcode;
    let cst_val: usize = if opcode == YARVINSN_putobject_INT2FIX_0_.as_usize() {
        0
    } else {
        1
    };

    jit_putobject(jit, ctx, cb, VALUE::fixnum_from_usize(cst_val));
    KeepCompiling
}

fn gen_putobject(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let arg: VALUE = jit_get_arg(jit, 0);

    jit_putobject(jit, ctx, cb, arg);
    KeepCompiling
}

fn gen_putself(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Load self from CFP
    let cf_opnd = mem_opnd((8 * SIZEOF_VALUE) as u8, REG_CFP, RUBY_OFFSET_CFP_SELF);
    mov(cb, REG0, cf_opnd);

    // Write it on the stack
    let stack_top: X86Opnd = ctx.stack_push_self();
    mov(cb, stack_top, REG0);

    KeepCompiling
}

fn gen_putspecialobject(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let object_type = jit_get_arg(jit, 0);

    if object_type == VALUE(VM_SPECIAL_OBJECT_VMCORE.as_usize()) {
        let stack_top: X86Opnd = ctx.stack_push(Type::UnknownHeap);
        jit_mov_gc_ptr(jit, cb, REG0, unsafe { rb_mRubyVMFrozenCore });
        mov(cb, stack_top, REG0);
        KeepCompiling
    } else {
        // TODO: implement for VM_SPECIAL_OBJECT_CBASE and
        // VM_SPECIAL_OBJECT_CONST_BASE
        CantCompile
    }
}

// set Nth stack entry to stack top
fn gen_setn(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let nval: VALUE = jit_get_arg(jit, 0);
    let VALUE(n) = nval;

    let top_val: X86Opnd = ctx.stack_pop(0);
    let dst_opnd: X86Opnd = ctx.stack_opnd(n.try_into().unwrap());
    mov(cb, REG0, top_val);
    mov(cb, dst_opnd, REG0);

    let mapping = ctx.get_opnd_mapping(StackOpnd(0));
    ctx.set_opnd_mapping(StackOpnd(n.try_into().unwrap()), mapping);

    KeepCompiling
}

// get nth stack value, then push it
fn gen_topn(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let nval: VALUE = jit_get_arg(jit, 0);
    let VALUE(n) = nval;

    let top_n_val = ctx.stack_opnd(n.try_into().unwrap());
    let mapping = ctx.get_opnd_mapping(StackOpnd(n.try_into().unwrap()));

    let loc0 = ctx.stack_push_mapping(mapping);
    mov(cb, REG0, top_n_val);
    mov(cb, loc0, REG0);

    KeepCompiling
}

// Pop n values off the stack
fn gen_adjuststack(
    jit: &mut JITState,
    ctx: &mut Context,
    _cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let nval: VALUE = jit_get_arg(jit, 0);
    let VALUE(n) = nval;

    ctx.stack_pop(n);
    KeepCompiling
}

fn gen_opt_plus(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let comptime_a = jit_peek_at_stack(jit, ctx, 1);
    let comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if comptime_a.fixnum_p() && comptime_b.fixnum_p() {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        let side_exit = get_side_exit(jit, ocb, ctx);

        if !assume_bop_not_redefined(jit, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_PLUS) {
            return CantCompile;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, cb, side_exit);

        // Get the operands and destination from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Add arg0 + arg1 and test for overflow
        mov(cb, REG0, arg0);
        sub(cb, REG0, imm_opnd(1));
        add(cb, REG0, arg1);
        jo_ptr(cb, side_exit);

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Fixnum);
        mov(cb, dst, REG0);

        KeepCompiling
    } else {
        gen_opt_send_without_block(jit, ctx, cb, ocb)
    }
}

// new array initialized from top N values
fn gen_newarray(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let n = jit_get_arg(jit, 0).as_u32();

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    let offset_magnitude = SIZEOF_VALUE as u32 * n;
    let values_ptr = ctx.sp_opnd(-(offset_magnitude as isize));

    // call rb_ec_ary_new_from_values(struct rb_execution_context_struct *ec, long n, const VALUE *elts);
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(cb, C_ARG_REGS[1], imm_opnd(n.into()));
    lea(cb, C_ARG_REGS[2], values_ptr);
    call_ptr(cb, REG0, rb_ec_ary_new_from_values as *const u8);

    ctx.stack_pop(n.as_usize());
    let stack_ret = ctx.stack_push(Type::Array);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

// dup array
fn gen_duparray(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let ary = jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // call rb_ary_resurrect(VALUE ary);
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], ary);
    call_ptr(cb, REG0, rb_ary_resurrect as *const u8);

    let stack_ret = ctx.stack_push(Type::Array);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

// dup hash
fn gen_duphash(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let hash = jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // call rb_hash_resurrect(VALUE hash);
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], hash);
    call_ptr(cb, REG0, rb_hash_resurrect as *const u8);

    let stack_ret = ctx.stack_push(Type::Hash);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

// call to_a on the array on the stack
fn gen_splatarray(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let flag = jit_get_arg(jit, 0);

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // Get the operands from the stack
    let ary_opnd = ctx.stack_pop(1);

    // Call rb_vm_splat_array(flag, ary)
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], flag);
    mov(cb, C_ARG_REGS[1], ary_opnd);
    call_ptr(cb, REG1, rb_vm_splat_array as *const u8);

    let stack_ret = ctx.stack_push(Type::Array);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

// new range initialized from top 2 values
fn gen_newrange(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let flag = jit_get_arg(jit, 0);

    // rb_range_new() allocates and can raise
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // val = rb_range_new(low, high, (int)flag);
    mov(cb, C_ARG_REGS[0], ctx.stack_opnd(1));
    mov(cb, C_ARG_REGS[1], ctx.stack_opnd(0));
    mov(cb, C_ARG_REGS[2], uimm_opnd(flag.into()));
    call_ptr(cb, REG0, rb_range_new as *const u8);

    ctx.stack_pop(2);
    let stack_ret = ctx.stack_push(Type::UnknownHeap);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

fn guard_object_is_heap(
    cb: &mut CodeBlock,
    object_opnd: X86Opnd,
    _ctx: &mut Context,
    side_exit: CodePtr,
) {
    add_comment(cb, "guard object is heap");

    // Test that the object is not an immediate
    test(cb, object_opnd, uimm_opnd(RUBY_IMMEDIATE_MASK as u64));
    jnz_ptr(cb, side_exit);

    // Test that the object is not false or nil
    cmp(cb, object_opnd, uimm_opnd(Qnil.into()));
    jbe_ptr(cb, side_exit);
}

fn guard_object_is_array(
    cb: &mut CodeBlock,
    object_opnd: X86Opnd,
    flags_opnd: X86Opnd,
    _ctx: &mut Context,
    side_exit: CodePtr,
) {
    add_comment(cb, "guard object is array");

    // Pull out the type mask
    mov(
        cb,
        flags_opnd,
        mem_opnd(
            8 * SIZEOF_VALUE as u8,
            object_opnd,
            RUBY_OFFSET_RBASIC_FLAGS,
        ),
    );
    and(cb, flags_opnd, uimm_opnd(RUBY_T_MASK as u64));

    // Compare the result with T_ARRAY
    cmp(cb, flags_opnd, uimm_opnd(RUBY_T_ARRAY as u64));
    jne_ptr(cb, side_exit);
}

// push enough nils onto the stack to fill out an array
fn gen_expandarray(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let flag = jit_get_arg(jit, 1);
    let VALUE(flag_value) = flag;

    // If this instruction has the splat flag, then bail out.
    if flag_value & 0x01 != 0 {
        incr_counter!(expandarray_splat);
        return CantCompile;
    }

    // If this instruction has the postarg flag, then bail out.
    if flag_value & 0x02 != 0 {
        incr_counter!(expandarray_postarg);
        return CantCompile;
    }

    let side_exit = get_side_exit(jit, ocb, ctx);

    // num is the number of requested values. If there aren't enough in the
    // array then we're going to push on nils.
    let num = jit_get_arg(jit, 0);
    let array_type = ctx.get_opnd_type(StackOpnd(0));
    let array_opnd = ctx.stack_pop(1);

    if matches!(array_type, Type::Nil) {
        // special case for a, b = nil pattern
        // push N nils onto the stack
        for _i in 0..(num.into()) {
            let push_opnd = ctx.stack_push(Type::Nil);
            mov(cb, push_opnd, uimm_opnd(Qnil.into()));
        }
        return KeepCompiling;
    }

    // Move the array from the stack into REG0 and check that it's an array.
    mov(cb, REG0, array_opnd);
    guard_object_is_heap(
        cb,
        REG0,
        ctx,
        counted_exit!(ocb, side_exit, expandarray_not_array),
    );
    guard_object_is_array(
        cb,
        REG0,
        REG1,
        ctx,
        counted_exit!(ocb, side_exit, expandarray_not_array),
    );

    // If we don't actually want any values, then just return.
    if num == VALUE(0) {
        return KeepCompiling;
    }

    // Pull out the embed flag to check if it's an embedded array.
    let flags_opnd = mem_opnd((8 * SIZEOF_VALUE) as u8, REG0, RUBY_OFFSET_RBASIC_FLAGS);
    mov(cb, REG1, flags_opnd);

    // Move the length of the embedded array into REG1.
    and(cb, REG1, uimm_opnd(RARRAY_EMBED_LEN_MASK as u64));
    shr(cb, REG1, uimm_opnd(RARRAY_EMBED_LEN_SHIFT as u64));

    // Conditionally move the length of the heap array into REG1.
    test(cb, flags_opnd, uimm_opnd(RARRAY_EMBED_FLAG as u64));
    let array_len_opnd = mem_opnd(
        (8 * size_of::<std::os::raw::c_long>()) as u8,
        REG0,
        RUBY_OFFSET_RARRAY_AS_HEAP_LEN,
    );
    cmovz(cb, REG1, array_len_opnd);

    // Only handle the case where the number of values in the array is greater
    // than or equal to the number of values requested.
    cmp(cb, REG1, uimm_opnd(num.into()));
    jl_ptr(cb, counted_exit!(ocb, side_exit, expandarray_rhs_too_small));

    // Load the address of the embedded array into REG1.
    // (struct RArray *)(obj)->as.ary
    let ary_opnd = mem_opnd((8 * SIZEOF_VALUE) as u8, REG0, RUBY_OFFSET_RARRAY_AS_ARY);
    lea(cb, REG1, ary_opnd);

    // Conditionally load the address of the heap array into REG1.
    // (struct RArray *)(obj)->as.heap.ptr
    test(cb, flags_opnd, uimm_opnd(RARRAY_EMBED_FLAG as u64));
    let heap_ptr_opnd = mem_opnd(
        (8 * size_of::<usize>()) as u8,
        REG0,
        RUBY_OFFSET_RARRAY_AS_HEAP_PTR,
    );
    cmovz(cb, REG1, heap_ptr_opnd);

    // Loop backward through the array and push each element onto the stack.
    for i in (0..(num.as_i32())).rev() {
        let top = ctx.stack_push(Type::Unknown);
        mov(cb, REG0, mem_opnd(64, REG1, i * (SIZEOF_VALUE as i32)));
        mov(cb, top, REG0);
    }

    KeepCompiling
}

fn gen_getlocal_wc0(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Compute the offset from BP to the local
    let slot_idx = jit_get_arg(jit, 0).as_i32();
    let offs: i32 = -(SIZEOF_VALUE as i32) * slot_idx;
    let local_idx = slot_to_local_idx(jit.get_iseq(), slot_idx);

    // Load environment pointer EP (level 0) from CFP
    gen_get_ep(cb, REG0, 0);

    // Load the local from the EP
    mov(cb, REG0, mem_opnd(64, REG0, offs));

    // Write the local at SP
    let stack_top = ctx.stack_push_local(local_idx.as_usize());
    mov(cb, stack_top, REG0);

    KeepCompiling
}

// Compute the index of a local variable from its slot index
fn slot_to_local_idx(iseq: IseqPtr, slot_idx: i32) -> u32 {
    // Layout illustration
    // This is an array of VALUE
    //                                           | VM_ENV_DATA_SIZE |
    //                                           v                  v
    // low addr <+-------+-------+-------+-------+------------------+
    //           |local 0|local 1|  ...  |local n|       ....       |
    //           +-------+-------+-------+-------+------------------+
    //           ^       ^                       ^                  ^
    //           +-------+---local_table_size----+         cfp->ep--+
    //                   |                                          |
    //                   +------------------slot_idx----------------+
    //
    // See usages of local_var_name() from iseq.c for similar calculation.

    // Equivalent of iseq->body->local_table_size
    let local_table_size: i32 = unsafe { get_iseq_body_local_table_size(iseq) }
        .try_into()
        .unwrap();
    let op = slot_idx - (VM_ENV_DATA_SIZE as i32);
    let local_idx = local_table_size - op - 1;
    assert!(local_idx >= 0 && local_idx < local_table_size);
    local_idx.try_into().unwrap()
}

// Get EP at level from CFP
fn gen_get_ep(cb: &mut CodeBlock, reg: X86Opnd, level: u32) {
    // Load environment pointer EP from CFP
    let ep_opnd = mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_EP);
    mov(cb, reg, ep_opnd);

    for _ in (0..level).rev() {
        // Get the previous EP from the current EP
        // See GET_PREV_EP(ep) macro
        // VALUE *prev_ep = ((VALUE *)((ep)[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03))
        let offs = (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32);
        mov(cb, reg, mem_opnd(64, reg, offs));
        and(cb, reg, imm_opnd(!0x03));
    }
}

fn gen_getlocal_generic(
    ctx: &mut Context,
    cb: &mut CodeBlock,
    local_idx: u32,
    level: u32,
) -> CodegenStatus {
    gen_get_ep(cb, REG0, level);

    // Load the local from the block
    // val = *(vm_get_ep(GET_EP(), level) - idx);
    let offs = -(SIZEOF_VALUE as i32 * local_idx as i32);
    mov(cb, REG0, mem_opnd(64, REG0, offs));

    // Write the local at SP
    let stack_top = ctx.stack_push(Type::Unknown);
    mov(cb, stack_top, REG0);

    KeepCompiling
}

fn gen_getlocal(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let idx = jit_get_arg(jit, 0);
    let level = jit_get_arg(jit, 1);
    gen_getlocal_generic(ctx, cb, idx.as_u32(), level.as_u32())
}

fn gen_getlocal_wc1(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let idx = jit_get_arg(jit, 0);
    gen_getlocal_generic(ctx, cb, idx.as_u32(), 1)
}

fn gen_setlocal_wc0(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
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

    let slot_idx = jit_get_arg(jit, 0).as_i32();
    let local_idx = slot_to_local_idx(jit.get_iseq(), slot_idx).as_usize();

    // Load environment pointer EP (level 0) from CFP
    gen_get_ep(cb, REG0, 0);

    // flags & VM_ENV_FLAG_WB_REQUIRED
    let flags_opnd = mem_opnd(
        64,
        REG0,
        SIZEOF_VALUE as i32 * VM_ENV_DATA_INDEX_FLAGS as i32,
    );
    test(cb, flags_opnd, imm_opnd(VM_ENV_FLAG_WB_REQUIRED as i64));

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    jnz_ptr(cb, side_exit);

    // Set the type of the local variable in the context
    let temp_type = ctx.get_opnd_type(StackOpnd(0));
    ctx.set_local_type(local_idx, temp_type);

    // Pop the value to write from the stack
    let stack_top = ctx.stack_pop(1);
    mov(cb, REG1, stack_top);

    // Write the value at the environment pointer
    let offs: i32 = -8 * slot_idx;
    mov(cb, mem_opnd(64, REG0, offs), REG1);

    KeepCompiling
}

fn gen_setlocal_generic(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    local_idx: i32,
    level: u32,
) -> CodegenStatus {
    // Load environment pointer EP at level
    gen_get_ep(cb, REG0, level);

    // flags & VM_ENV_FLAG_WB_REQUIRED
    let flags_opnd = mem_opnd(
        64,
        REG0,
        SIZEOF_VALUE as i32 * VM_ENV_DATA_INDEX_FLAGS as i32,
    );
    test(cb, flags_opnd, uimm_opnd(VM_ENV_FLAG_WB_REQUIRED.into()));

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    jnz_ptr(cb, side_exit);

    // Pop the value to write from the stack
    let stack_top = ctx.stack_pop(1);
    mov(cb, REG1, stack_top);

    // Write the value at the environment pointer
    let offs = -(SIZEOF_VALUE as i32 * local_idx);
    mov(cb, mem_opnd(64, REG0, offs), REG1);

    KeepCompiling
}

fn gen_setlocal(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let idx = jit_get_arg(jit, 0).as_i32();
    let level = jit_get_arg(jit, 1).as_u32();
    gen_setlocal_generic(jit, ctx, cb, ocb, idx, level)
}

fn gen_setlocal_wc1(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let idx = jit_get_arg(jit, 0).as_i32();
    gen_setlocal_generic(jit, ctx, cb, ocb, idx, 1)
}

// new hash initialized from top N values
fn gen_newhash(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let num: i64 = jit_get_arg(jit, 0).as_i64();

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    if num != 0 {
        // val = rb_hash_new_with_size(num / 2);
        mov(cb, C_ARG_REGS[0], imm_opnd(num / 2));
        call_ptr(cb, REG0, rb_hash_new_with_size as *const u8);

        // save the allocated hash as we want to push it after insertion
        push(cb, RAX);
        push(cb, RAX); // alignment

        // rb_hash_bulk_insert(num, STACK_ADDR_FROM_TOP(num), val);
        mov(cb, C_ARG_REGS[0], imm_opnd(num));
        lea(
            cb,
            C_ARG_REGS[1],
            ctx.stack_opnd((num - 1).try_into().unwrap()),
        );
        mov(cb, C_ARG_REGS[2], RAX);
        call_ptr(cb, REG0, rb_hash_bulk_insert as *const u8);

        pop(cb, RAX); // alignment
        pop(cb, RAX);

        ctx.stack_pop(num.try_into().unwrap());
        let stack_ret = ctx.stack_push(Type::Hash);
        mov(cb, stack_ret, RAX);
    } else {
        // val = rb_hash_new();
        call_ptr(cb, REG0, rb_hash_new as *const u8);

        let stack_ret = ctx.stack_push(Type::Hash);
        mov(cb, stack_ret, RAX);
    }

    KeepCompiling
}

fn gen_putstring(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let put_val = jit_get_arg(jit, 0);

    // Save the PC and SP because the callee will allocate
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    mov(cb, C_ARG_REGS[0], REG_EC);
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[1], put_val);
    call_ptr(cb, REG0, rb_ec_str_resurrect as *const u8);

    let stack_top = ctx.stack_push(Type::String);
    mov(cb, stack_top, RAX);

    KeepCompiling
}

// Push Qtrue or Qfalse depending on whether the given keyword was supplied by
// the caller
fn gen_checkkeyword(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // When a keyword is unspecified past index 32, a hash will be used
    // instead. This can only happen in iseqs taking more than 32 keywords.
    if unsafe { (*get_iseq_body_param_keyword(jit.iseq)).num >= 32 } {
        return CantCompile;
    }

    // The EP offset to the undefined bits local
    let bits_offset = jit_get_arg(jit, 0).as_i32();

    // The index of the keyword we want to check
    let index: i64 = jit_get_arg(jit, 1).as_i64();

    // Load environment pointer EP
    gen_get_ep(cb, REG0, 0);

    // VALUE kw_bits = *(ep - bits);
    let bits_opnd = mem_opnd(64, REG0, (SIZEOF_VALUE as i32) * -bits_offset);

    // unsigned int b = (unsigned int)FIX2ULONG(kw_bits);
    // if ((b & (0x01 << idx))) {
    //
    // We can skip the FIX2ULONG conversion by shifting the bit we test
    let bit_test: i64 = 0x01 << (index + 1);
    test(cb, bits_opnd, imm_opnd(bit_test));
    mov(cb, REG0, uimm_opnd(Qfalse.into()));
    mov(cb, REG1, uimm_opnd(Qtrue.into()));
    cmovz(cb, REG0, REG1);

    let stack_ret = ctx.stack_push(Type::UnknownImm);
    mov(cb, stack_ret, REG0);

    KeepCompiling
}

fn gen_jnz_to_target0(
    cb: &mut CodeBlock,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 | BranchShape::Next1 => unreachable!(),
        BranchShape::Default => jnz_ptr(cb, target0),
    }
}

fn gen_jz_to_target0(
    cb: &mut CodeBlock,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 | BranchShape::Next1 => unreachable!(),
        BranchShape::Default => jz_ptr(cb, target0),
    }
}

fn gen_jbe_to_target0(
    cb: &mut CodeBlock,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 | BranchShape::Next1 => unreachable!(),
        BranchShape::Default => jbe_ptr(cb, target0),
    }
}

// Generate a jump to a stub that recompiles the current YARV instruction on failure.
// When depth_limitk is exceeded, generate a jump to a side exit.
fn jit_chain_guard(
    jcc: JCCKinds,
    jit: &JITState,
    ctx: &Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    depth_limit: i32,
    side_exit: CodePtr,
) {
    let target0_gen_fn = match jcc {
        JCC_JNE | JCC_JNZ => gen_jnz_to_target0,
        JCC_JZ | JCC_JE => gen_jz_to_target0,
        JCC_JBE | JCC_JNA => gen_jbe_to_target0,
    };

    if (ctx.get_chain_depth() as i32) < depth_limit {
        let mut deeper = *ctx;
        deeper.increment_chain_depth();
        let bid = BlockId {
            iseq: jit.iseq,
            idx: jit.insn_idx,
        };

        gen_branch(jit, ctx, cb, ocb, bid, &deeper, None, None, target0_gen_fn);
    } else {
        target0_gen_fn(cb, side_exit, None, BranchShape::Default);
    }
}

// up to 5 different classes, and embedded or not for each
pub const GET_IVAR_MAX_DEPTH: i32 = 10;

// hashes and arrays
pub const OPT_AREF_MAX_CHAIN_DEPTH: i32 = 2;

// up to 5 different classes
pub const SEND_MAX_DEPTH: i32 = 5;

// Codegen for setting an instance variable.
// Preconditions:
//   - receiver is in REG0
//   - receiver has the same class as CLASS_OF(comptime_receiver)
//   - no stack push or pops to ctx since the entry to the codegen of the instruction being compiled
fn gen_set_ivar(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    recv: VALUE,
    ivar_name: ID,
) -> CodegenStatus {
    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // Get the operands from the stack
    let val_opnd = ctx.stack_pop(1);
    let recv_opnd = ctx.stack_pop(1);

    let ivar_index: u32 = unsafe { rb_obj_ensure_iv_index_mapping(recv, ivar_name) };

    // Call rb_vm_set_ivar_idx with the receiver, the index of the ivar, and the value
    mov(cb, C_ARG_REGS[0], recv_opnd);
    mov(cb, C_ARG_REGS[1], imm_opnd(ivar_index.into()));
    mov(cb, C_ARG_REGS[2], val_opnd);
    call_ptr(cb, REG0, rb_vm_set_ivar_idx as *const u8);

    let out_opnd = ctx.stack_push(Type::Unknown);
    mov(cb, out_opnd, RAX);

    KeepCompiling
}

// Codegen for getting an instance variable.
// Preconditions:
//   - receiver is in REG0
//   - receiver has the same class as CLASS_OF(comptime_receiver)
//   - no stack push or pops to ctx since the entry to the codegen of the instruction being compiled
fn gen_get_ivar(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    max_chain_depth: i32,
    comptime_receiver: VALUE,
    ivar_name: ID,
    reg0_opnd: InsnOpnd,
    side_exit: CodePtr,
) -> CodegenStatus {
    let comptime_val_klass = comptime_receiver.class_of();
    let starting_context = *ctx; // make a copy for use with jit_chain_guard

    // Check if the comptime class uses a custom allocator
    let custom_allocator = unsafe { rb_get_alloc_func(comptime_val_klass) };
    let uses_custom_allocator = match custom_allocator {
        Some(alloc_fun) => {
            let allocate_instance = rb_class_allocate_instance as *const u8;
            alloc_fun as *const u8 != allocate_instance
        }
        None => false,
    };

    // Check if the comptime receiver is a T_OBJECT
    let receiver_t_object = unsafe { RB_TYPE_P(comptime_receiver, RUBY_T_OBJECT) };

    // If the class uses the default allocator, instances should all be T_OBJECT
    // NOTE: This assumes nobody changes the allocator of the class after allocation.
    //       Eventually, we can encode whether an object is T_OBJECT or not
    //       inside object shapes.
    if !receiver_t_object || uses_custom_allocator {
        // General case. Call rb_ivar_get().
        // VALUE rb_ivar_get(VALUE obj, ID id)
        add_comment(cb, "call rb_ivar_get()");

        // The function could raise exceptions.
        jit_prepare_routine_call(jit, ctx, cb, REG1);

        mov(cb, C_ARG_REGS[0], REG0);
        mov(cb, C_ARG_REGS[1], uimm_opnd(ivar_name));
        call_ptr(cb, REG1, rb_ivar_get as *const u8);

        if reg0_opnd != SelfOpnd {
            ctx.stack_pop(1);
        }
        // Push the ivar on the stack
        let out_opnd = ctx.stack_push(Type::Unknown);
        mov(cb, out_opnd, RAX);

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, ctx, cb, ocb);
        return EndBlock;
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
    add_comment(cb, "guard receiver is T_OBJECT");
    mov(cb, REG1, member_opnd(REG0, struct RBasic, flags));
    and(cb, REG1, imm_opnd(RUBY_T_MASK));
    cmp(cb, REG1, imm_opnd(T_OBJECT));
    jit_chain_guard(JCC_JNE, jit, &starting_context, cb, ocb, max_chain_depth, side_exit);
    */

    // FIXME: Mapping the index could fail when there is too many ivar names. If we're
    // compiling for a branch stub that can cause the exception to be thrown from the
    // wrong PC.
    let ivar_index =
        unsafe { rb_obj_ensure_iv_index_mapping(comptime_receiver, ivar_name) }.as_usize();

    // Pop receiver if it's on the temp stack
    if reg0_opnd != SelfOpnd {
        ctx.stack_pop(1);
    }

    // Compile time self is embedded and the ivar index lands within the object
    let test_result = unsafe { FL_TEST_RAW(comptime_receiver, VALUE(ROBJECT_EMBED.as_usize())) != VALUE(0) };
    if test_result && ivar_index < (ROBJECT_EMBED_LEN_MAX.as_usize()) {
        // See ROBJECT_IVPTR() from include/ruby/internal/core/robject.h

        // Guard that self is embedded
        // TODO: BT and JC is shorter
        add_comment(cb, "guard embedded getivar");
        let flags_opnd = mem_opnd(64, REG0, RUBY_OFFSET_RBASIC_FLAGS);
        test(cb, flags_opnd, uimm_opnd(ROBJECT_EMBED as u64));
        let side_exit = counted_exit!(ocb, side_exit, getivar_megamorphic);
        jit_chain_guard(
            JCC_JZ,
            jit,
            &starting_context,
            cb,
            ocb,
            max_chain_depth,
            side_exit,
        );

        // Load the variable
        let offs = RUBY_OFFSET_ROBJECT_AS_ARY + (ivar_index * SIZEOF_VALUE) as i32;
        let ivar_opnd = mem_opnd(64, REG0, offs);
        mov(cb, REG1, ivar_opnd);

        // Guard that the variable is not Qundef
        cmp(cb, REG1, uimm_opnd(Qundef.into()));
        mov(cb, REG0, uimm_opnd(Qnil.into()));
        cmove(cb, REG1, REG0);

        // Push the ivar on the stack
        let out_opnd = ctx.stack_push(Type::Unknown);
        mov(cb, out_opnd, REG1);
    } else {
        // Compile time value is *not* embedded.

        // Guard that value is *not* embedded
        // See ROBJECT_IVPTR() from include/ruby/internal/core/robject.h
        add_comment(cb, "guard extended getivar");
        let flags_opnd = mem_opnd(64, REG0, RUBY_OFFSET_RBASIC_FLAGS);
        test(cb, flags_opnd, uimm_opnd(ROBJECT_EMBED as u64));
        let side_exit = counted_exit!(ocb, side_exit, getivar_megamorphic);
        jit_chain_guard(
            JCC_JNZ,
            jit,
            &starting_context,
            cb,
            ocb,
            max_chain_depth,
            side_exit,
        );

        // Check that the extended table is big enough
        if ivar_index > (ROBJECT_EMBED_LEN_MAX.as_usize()) {
            // Check that the slot is inside the extended table (num_slots > index)
            let num_slots = mem_opnd(32, REG0, RUBY_OFFSET_ROBJECT_AS_HEAP_NUMIV);

            cmp(cb, num_slots, uimm_opnd(ivar_index as u64));
            jle_ptr(cb, counted_exit!(ocb, side_exit, getivar_idx_out_of_range));
        }

        // Get a pointer to the extended table
        let tbl_opnd = mem_opnd(64, REG0, RUBY_OFFSET_ROBJECT_AS_HEAP_IVPTR);
        mov(cb, REG0, tbl_opnd);

        // Read the ivar from the extended table
        let ivar_opnd = mem_opnd(64, REG0, (SIZEOF_VALUE * ivar_index) as i32);
        mov(cb, REG0, ivar_opnd);

        // Check that the ivar is not Qundef
        cmp(cb, REG0, uimm_opnd(Qundef.into()));
        mov(cb, REG1, uimm_opnd(Qnil.into()));
        cmove(cb, REG0, REG1);

        // Push the ivar on the stack
        let out_opnd = ctx.stack_push(Type::Unknown);
        mov(cb, out_opnd, REG0);
    }

    // Jump to next instruction. This allows guard chains to share the same successor.
    jump_to_next_insn(jit, ctx, cb, ocb);
    EndBlock
}

fn gen_getinstancevariable(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let ivar_name = jit_get_arg(jit, 0).as_u64();

    let comptime_val = jit_peek_at_self(jit);
    let comptime_val_klass = comptime_val.class_of();

    // Generate a side exit
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Guard that the receiver has the same class as the one from compile time.
    mov(cb, REG0, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SELF));

    jit_guard_known_klass(
        jit,
        ctx,
        cb,
        ocb,
        comptime_val_klass,
        SelfOpnd,
        comptime_val,
        GET_IVAR_MAX_DEPTH,
        side_exit,
    );

    gen_get_ivar(
        jit,
        ctx,
        cb,
        ocb,
        GET_IVAR_MAX_DEPTH,
        comptime_val,
        ivar_name,
        SelfOpnd,
        side_exit,
    )
}

fn gen_setinstancevariable(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let id = jit_get_arg(jit, 0);
    let ic = jit_get_arg(jit, 1).as_u64(); // type IVC

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // Get the operands from the stack
    let val_opnd = ctx.stack_pop(1);

    // Call rb_vm_setinstancevariable(iseq, obj, id, val, ic);
    mov(
        cb,
        C_ARG_REGS[1],
        mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SELF),
    );
    mov(cb, C_ARG_REGS[3], val_opnd);
    mov(cb, C_ARG_REGS[2], uimm_opnd(id.into()));
    mov(cb, C_ARG_REGS[4], const_ptr_opnd(ic as *const u8));
    let iseq = VALUE(jit.iseq as usize);
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], iseq);
    call_ptr(cb, REG0, rb_vm_setinstancevariable as *const u8);

    KeepCompiling
}

fn gen_defined(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let op_type = jit_get_arg(jit, 0);
    let obj = jit_get_arg(jit, 1);
    let pushval = jit_get_arg(jit, 2);

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // Get the operands from the stack
    let v_opnd = ctx.stack_pop(1);

    // Call vm_defined(ec, reg_cfp, op_type, obj, v)
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(cb, C_ARG_REGS[1], REG_CFP);
    mov(cb, C_ARG_REGS[2], uimm_opnd(op_type.into()));
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[3], obj);
    mov(cb, C_ARG_REGS[4], v_opnd);
    call_ptr(cb, REG0, rb_vm_defined as *const u8);

    // if (vm_defined(ec, GET_CFP(), op_type, obj, v)) {
    //  val = pushval;
    // }
    jit_mov_gc_ptr(jit, cb, REG1, pushval);
    cmp(cb, AL, imm_opnd(0));
    mov(cb, RAX, uimm_opnd(Qnil.into()));
    cmovnz(cb, RAX, REG1);

    // Push the return value onto the stack
    let out_type = if pushval.special_const_p() {
        Type::UnknownImm
    } else {
        Type::Unknown
    };
    let stack_ret = ctx.stack_push(out_type);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

fn gen_checktype(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let type_val = jit_get_arg(jit, 0).as_u32();

    // Only three types are emitted by compile.c at the moment
    if let RUBY_T_STRING | RUBY_T_ARRAY | RUBY_T_HASH = type_val {
        let val_type = ctx.get_opnd_type(StackOpnd(0));
        let val = ctx.stack_pop(1);

        // Check if we know from type information
        match (type_val, val_type) {
            (RUBY_T_STRING, Type::String)
            | (RUBY_T_ARRAY, Type::Array)
            | (RUBY_T_HASH, Type::Hash) => {
                // guaranteed type match
                let stack_ret = ctx.stack_push(Type::True);
                mov(cb, stack_ret, uimm_opnd(Qtrue.as_u64()));
                return KeepCompiling;
            }
            _ if val_type.is_imm() || val_type.is_specific() => {
                // guaranteed not to match T_STRING/T_ARRAY/T_HASH
                let stack_ret = ctx.stack_push(Type::False);
                mov(cb, stack_ret, uimm_opnd(Qfalse.as_u64()));
                return KeepCompiling;
            }
            _ => (),
        }

        mov(cb, REG0, val);
        mov(cb, REG1, uimm_opnd(Qfalse.as_u64()));

        let ret = cb.new_label("ret".to_string());

        if !val_type.is_heap() {
            // if (SPECIAL_CONST_P(val)) {
            // Return Qfalse via REG1 if not on heap
            test(cb, REG0, uimm_opnd(RUBY_IMMEDIATE_MASK as u64));
            jnz_label(cb, ret);
            cmp(cb, REG0, uimm_opnd(Qnil.as_u64()));
            jbe_label(cb, ret);
        }

        // Check type on object
        mov(cb, REG0, mem_opnd(64, REG0, RUBY_OFFSET_RBASIC_FLAGS));
        and(cb, REG0, uimm_opnd(RUBY_T_MASK as u64));
        cmp(cb, REG0, uimm_opnd(type_val as u64));
        mov(cb, REG0, uimm_opnd(Qtrue.as_u64()));
        // REG1 contains Qfalse from above
        cmove(cb, REG1, REG0);

        cb.write_label(ret);
        let stack_ret = ctx.stack_push(Type::UnknownImm);
        mov(cb, stack_ret, REG1);
        cb.link_labels();

        KeepCompiling
    } else {
        CantCompile
    }
}

fn gen_concatstrings(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let n = jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    let values_ptr = ctx.sp_opnd(-((SIZEOF_VALUE as isize) * n.as_isize()));

    // call rb_str_concat_literals(long n, const VALUE *strings);
    mov(cb, C_ARG_REGS[0], imm_opnd(n.into()));
    lea(cb, C_ARG_REGS[1], values_ptr);
    call_ptr(cb, REG0, rb_str_concat_literals as *const u8);

    ctx.stack_pop(n.as_usize());
    let stack_ret = ctx.stack_push(Type::String);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

fn guard_two_fixnums(ctx: &mut Context, cb: &mut CodeBlock, side_exit: CodePtr) {
    // Get the stack operand types
    let arg1_type = ctx.get_opnd_type(StackOpnd(0));
    let arg0_type = ctx.get_opnd_type(StackOpnd(1));

    if arg0_type.is_heap() || arg1_type.is_heap() {
        add_comment(cb, "arg is heap object");
        jmp_ptr(cb, side_exit);
        return;
    }

    if arg0_type != Type::Fixnum && arg0_type.is_specific() {
        add_comment(cb, "arg0 not fixnum");
        jmp_ptr(cb, side_exit);
        return;
    }

    if arg1_type != Type::Fixnum && arg1_type.is_specific() {
        add_comment(cb, "arg1 not fixnum");
        jmp_ptr(cb, side_exit);
        return;
    }

    assert!(!arg0_type.is_heap());
    assert!(!arg1_type.is_heap());
    assert!(arg0_type == Type::Fixnum || arg0_type.is_unknown());
    assert!(arg1_type == Type::Fixnum || arg1_type.is_unknown());

    // Get stack operands without popping them
    let arg1 = ctx.stack_opnd(0);
    let arg0 = ctx.stack_opnd(1);

    // If not fixnums, fall back
    if arg0_type != Type::Fixnum {
        add_comment(cb, "guard arg0 fixnum");
        test(cb, arg0, uimm_opnd(RUBY_FIXNUM_FLAG as u64));
        jz_ptr(cb, side_exit);
    }
    if arg1_type != Type::Fixnum {
        add_comment(cb, "guard arg1 fixnum");
        test(cb, arg1, uimm_opnd(RUBY_FIXNUM_FLAG as u64));
        jz_ptr(cb, side_exit);
    }

    // Set stack types in context
    ctx.upgrade_opnd_type(StackOpnd(0), Type::Fixnum);
    ctx.upgrade_opnd_type(StackOpnd(1), Type::Fixnum);
}

// Conditional move operation used by comparison operators
type CmovFn = fn(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) -> ();

fn gen_fixnum_cmp(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    cmov_op: CmovFn,
) -> CodegenStatus {
    // Defer compilation so we can specialize base on a runtime receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let comptime_a = jit_peek_at_stack(jit, ctx, 1);
    let comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if comptime_a.fixnum_p() && comptime_b.fixnum_p() {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        let side_exit = get_side_exit(jit, ocb, ctx);

        if !assume_bop_not_redefined(jit, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_LT) {
            return CantCompile;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, cb, side_exit);

        // Get the operands from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Compare the arguments
        xor(cb, REG0_32, REG0_32); // REG0 = Qfalse
        mov(cb, REG1, arg0);
        cmp(cb, REG1, arg1);
        mov(cb, REG1, uimm_opnd(Qtrue.into()));
        cmov_op(cb, REG0, REG1);

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Unknown);
        mov(cb, dst, REG0);

        KeepCompiling
    } else {
        gen_opt_send_without_block(jit, ctx, cb, ocb)
    }
}

fn gen_opt_lt(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    gen_fixnum_cmp(jit, ctx, cb, ocb, cmovl)
}

fn gen_opt_le(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    gen_fixnum_cmp(jit, ctx, cb, ocb, cmovle)
}

fn gen_opt_ge(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    gen_fixnum_cmp(jit, ctx, cb, ocb, cmovge)
}

fn gen_opt_gt(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    gen_fixnum_cmp(jit, ctx, cb, ocb, cmovg)
}

// Implements specialized equality for either two fixnum or two strings
// Returns true if code was generated, otherwise false
fn gen_equality_specialized(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    side_exit: CodePtr,
) -> bool {
    let comptime_a = jit_peek_at_stack(jit, ctx, 1);
    let comptime_b = jit_peek_at_stack(jit, ctx, 0);

    let a_opnd = ctx.stack_opnd(1);
    let b_opnd = ctx.stack_opnd(0);

    if comptime_a.fixnum_p() && comptime_b.fixnum_p() {
        if !assume_bop_not_redefined(jit, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_EQ) {
            // if overridden, emit the generic version
            return false;
        }

        guard_two_fixnums(ctx, cb, side_exit);

        mov(cb, REG0, a_opnd);
        cmp(cb, REG0, b_opnd);

        mov(cb, REG0, imm_opnd(Qfalse.into()));
        mov(cb, REG1, imm_opnd(Qtrue.into()));
        cmove(cb, REG0, REG1);

        // Push the output on the stack
        ctx.stack_pop(2);
        let dst = ctx.stack_push(Type::UnknownImm);
        mov(cb, dst, REG0);

        true
    } else if unsafe { comptime_a.class_of() == rb_cString && comptime_b.class_of() == rb_cString }
    {
        if !assume_bop_not_redefined(jit, ocb, STRING_REDEFINED_OP_FLAG, BOP_EQ) {
            // if overridden, emit the generic version
            return false;
        }

        // Load a and b in preparation for call later
        mov(cb, C_ARG_REGS[0], a_opnd);
        mov(cb, C_ARG_REGS[1], b_opnd);

        // Guard that a is a String
        mov(cb, REG0, C_ARG_REGS[0]);
        jit_guard_known_klass(
            jit,
            ctx,
            cb,
            ocb,
            unsafe { rb_cString },
            StackOpnd(1),
            comptime_a,
            SEND_MAX_DEPTH,
            side_exit,
        );

        let ret = cb.new_label("ret".to_string());

        // If they are equal by identity, return true
        cmp(cb, C_ARG_REGS[0], C_ARG_REGS[1]);
        mov(cb, RAX, imm_opnd(Qtrue.into()));
        je_label(cb, ret);

        // Otherwise guard that b is a T_STRING (from type info) or String (from runtime guard)
        if ctx.get_opnd_type(StackOpnd(0)) != Type::String {
            mov(cb, REG0, C_ARG_REGS[1]);
            // Note: any T_STRING is valid here, but we check for a ::String for simplicity
            // To pass a mutable static variable (rb_cString) requires an unsafe block
            jit_guard_known_klass(
                jit,
                ctx,
                cb,
                ocb,
                unsafe { rb_cString },
                StackOpnd(0),
                comptime_b,
                SEND_MAX_DEPTH,
                side_exit,
            );
        }

        // Call rb_str_eql_internal(a, b)
        call_ptr(cb, REG0, rb_str_eql_internal as *const u8);

        // Push the output on the stack
        cb.write_label(ret);
        ctx.stack_pop(2);
        let dst = ctx.stack_push(Type::UnknownImm);
        mov(cb, dst, RAX);
        cb.link_labels();

        true
    } else {
        false
    }
}

fn gen_opt_eq(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize base on a runtime receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    if gen_equality_specialized(jit, ctx, cb, ocb, side_exit) {
        jump_to_next_insn(jit, ctx, cb, ocb);
        EndBlock
    } else {
        gen_opt_send_without_block(jit, ctx, cb, ocb)
    }
}

fn gen_opt_neq(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // opt_neq is passed two rb_call_data as arguments:
    // first for ==, second for !=
    let cd = jit_get_arg(jit, 1).as_ptr();
    return gen_send_general(jit, ctx, cb, ocb, cd, None);
}

fn gen_opt_aref(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let cd: *const rb_call_data = jit_get_arg(jit, 0).as_ptr();
    let argc = unsafe { vm_ci_argc((*cd).ci) };

    // Only JIT one arg calls like `ary[6]`
    if argc != 1 {
        gen_counter_incr!(cb, oaref_argc_not_one);
        return CantCompile;
    }

    // Defer compilation so we can specialize base on a runtime receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    // Remember the context on entry for adding guard chains
    let starting_context = *ctx;

    // Specialize base on compile time values
    let comptime_idx = jit_peek_at_stack(jit, ctx, 0);
    let comptime_recv = jit_peek_at_stack(jit, ctx, 1);

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    if comptime_recv.class_of() == unsafe { rb_cArray } && comptime_idx.fixnum_p() {
        if !assume_bop_not_redefined(jit, ocb, ARRAY_REDEFINED_OP_FLAG, BOP_AREF) {
            return CantCompile;
        }

        // Pop the stack operands
        let idx_opnd = ctx.stack_pop(1);
        let recv_opnd = ctx.stack_pop(1);
        mov(cb, REG0, recv_opnd);

        // if (SPECIAL_CONST_P(recv)) {
        // Bail if receiver is not a heap object
        test(cb, REG0, uimm_opnd(RUBY_IMMEDIATE_MASK as u64));
        jnz_ptr(cb, side_exit);
        cmp(cb, REG0, uimm_opnd(Qfalse.into()));
        je_ptr(cb, side_exit);
        cmp(cb, REG0, uimm_opnd(Qnil.into()));
        je_ptr(cb, side_exit);

        // Bail if recv has a class other than ::Array.
        // BOP_AREF check above is only good for ::Array.
        mov(cb, REG1, mem_opnd(64, REG0, RUBY_OFFSET_RBASIC_KLASS));
        mov(cb, REG0, uimm_opnd(unsafe { rb_cArray }.into()));
        cmp(cb, REG0, REG1);
        jit_chain_guard(
            JCC_JNE,
            jit,
            &starting_context,
            cb,
            ocb,
            OPT_AREF_MAX_CHAIN_DEPTH,
            side_exit,
        );

        // Bail if idx is not a FIXNUM
        mov(cb, REG1, idx_opnd);
        test(cb, REG1, uimm_opnd(RUBY_FIXNUM_FLAG as u64));
        jz_ptr(cb, counted_exit!(ocb, side_exit, oaref_arg_not_fixnum));

        // Call VALUE rb_ary_entry_internal(VALUE ary, long offset).
        // It never raises or allocates, so we don't need to write to cfp->pc.
        {
            mov(cb, RDI, recv_opnd);
            sar(cb, REG1, uimm_opnd(1)); // Convert fixnum to int
            mov(cb, RSI, REG1);
            call_ptr(cb, REG0, rb_ary_entry_internal as *const u8);

            // Push the return value onto the stack
            let stack_ret = ctx.stack_push(Type::Unknown);
            mov(cb, stack_ret, RAX);
        }

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, ctx, cb, ocb);
        return EndBlock;
    } else if comptime_recv.class_of() == unsafe { rb_cHash } {
        if !assume_bop_not_redefined(jit, ocb, HASH_REDEFINED_OP_FLAG, BOP_AREF) {
            return CantCompile;
        }

        let key_opnd = ctx.stack_opnd(0);
        let recv_opnd = ctx.stack_opnd(1);

        // Guard that the receiver is a hash
        mov(cb, REG0, recv_opnd);
        jit_guard_known_klass(
            jit,
            ctx,
            cb,
            ocb,
            unsafe { rb_cHash },
            StackOpnd(1),
            comptime_recv,
            OPT_AREF_MAX_CHAIN_DEPTH,
            side_exit,
        );

        // Setup arguments for rb_hash_aref().
        mov(cb, C_ARG_REGS[0], REG0);
        mov(cb, C_ARG_REGS[1], key_opnd);

        // Prepare to call rb_hash_aref(). It might call #hash on the key.
        jit_prepare_routine_call(jit, ctx, cb, REG0);

        call_ptr(cb, REG0, rb_hash_aref as *const u8);

        // Pop the key and the receiver
        ctx.stack_pop(2);

        // Push the return value onto the stack
        let stack_ret = ctx.stack_push(Type::Unknown);
        mov(cb, stack_ret, RAX);

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, ctx, cb, ocb);
        EndBlock
    } else {
        // General case. Call the [] method.
        gen_opt_send_without_block(jit, ctx, cb, ocb)
    }
}

fn gen_opt_aset(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let comptime_recv = jit_peek_at_stack(jit, ctx, 2);
    let comptime_key = jit_peek_at_stack(jit, ctx, 1);

    // Get the operands from the stack
    let recv = ctx.stack_opnd(2);
    let key = ctx.stack_opnd(1);
    let val = ctx.stack_opnd(0);

    if comptime_recv.class_of() == unsafe { rb_cArray } && comptime_key.fixnum_p() {
        let side_exit = get_side_exit(jit, ocb, ctx);

        // Guard receiver is an Array
        mov(cb, REG0, recv);
        jit_guard_known_klass(
            jit,
            ctx,
            cb,
            ocb,
            unsafe { rb_cArray },
            StackOpnd(2),
            comptime_recv,
            SEND_MAX_DEPTH,
            side_exit,
        );

        // Guard key is a fixnum
        mov(cb, REG0, key);
        jit_guard_known_klass(
            jit,
            ctx,
            cb,
            ocb,
            unsafe { rb_cInteger },
            StackOpnd(1),
            comptime_key,
            SEND_MAX_DEPTH,
            side_exit,
        );

        // Call rb_ary_store
        mov(cb, C_ARG_REGS[0], recv);
        mov(cb, C_ARG_REGS[1], key);
        sar(cb, C_ARG_REGS[1], uimm_opnd(1)); // FIX2LONG(key)
        mov(cb, C_ARG_REGS[2], val);

        // We might allocate or raise
        jit_prepare_routine_call(jit, ctx, cb, REG0);

        call_ptr(cb, REG0, rb_ary_store as *const u8);

        // rb_ary_store returns void
        // stored value should still be on stack
        mov(cb, REG0, ctx.stack_opnd(0));

        // Push the return value onto the stack
        ctx.stack_pop(3);
        let stack_ret = ctx.stack_push(Type::Unknown);
        mov(cb, stack_ret, REG0);

        jump_to_next_insn(jit, ctx, cb, ocb);
        return EndBlock;
    } else if comptime_recv.class_of() == unsafe { rb_cHash } {
        let side_exit = get_side_exit(jit, ocb, ctx);

        // Guard receiver is a Hash
        mov(cb, REG0, recv);
        jit_guard_known_klass(
            jit,
            ctx,
            cb,
            ocb,
            unsafe { rb_cHash },
            StackOpnd(2),
            comptime_recv,
            SEND_MAX_DEPTH,
            side_exit,
        );

        // Call rb_hash_aset
        mov(cb, C_ARG_REGS[0], recv);
        mov(cb, C_ARG_REGS[1], key);
        mov(cb, C_ARG_REGS[2], val);

        // We might allocate or raise
        jit_prepare_routine_call(jit, ctx, cb, REG0);

        call_ptr(cb, REG0, rb_hash_aset as *const u8);

        // Push the return value onto the stack
        ctx.stack_pop(3);
        let stack_ret = ctx.stack_push(Type::Unknown);
        mov(cb, stack_ret, RAX);

        jump_to_next_insn(jit, ctx, cb, ocb);
        EndBlock
    } else {
        gen_opt_send_without_block(jit, ctx, cb, ocb)
    }
}

fn gen_opt_and(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let comptime_a = jit_peek_at_stack(jit, ctx, 1);
    let comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if comptime_a.fixnum_p() && comptime_b.fixnum_p() {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        let side_exit = get_side_exit(jit, ocb, ctx);

        if !assume_bop_not_redefined(jit, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_AND) {
            return CantCompile;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, cb, side_exit);

        // Get the operands and destination from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Do the bitwise and arg0 & arg1
        mov(cb, REG0, arg0);
        and(cb, REG0, arg1);

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Fixnum);
        mov(cb, dst, REG0);

        KeepCompiling
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, ctx, cb, ocb)
    }
}

fn gen_opt_or(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let comptime_a = jit_peek_at_stack(jit, ctx, 1);
    let comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if comptime_a.fixnum_p() && comptime_b.fixnum_p() {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        let side_exit = get_side_exit(jit, ocb, ctx);

        if !assume_bop_not_redefined(jit, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_OR) {
            return CantCompile;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, cb, side_exit);

        // Get the operands and destination from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Do the bitwise or arg0 | arg1
        mov(cb, REG0, arg0);
        or(cb, REG0, arg1);

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Fixnum);
        mov(cb, dst, REG0);

        KeepCompiling
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, ctx, cb, ocb)
    }
}

fn gen_opt_minus(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let comptime_a = jit_peek_at_stack(jit, ctx, 1);
    let comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if comptime_a.fixnum_p() && comptime_b.fixnum_p() {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        let side_exit = get_side_exit(jit, ocb, ctx);

        if !assume_bop_not_redefined(jit, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_MINUS) {
            return CantCompile;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(ctx, cb, side_exit);

        // Get the operands and destination from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Subtract arg0 - arg1 and test for overflow
        mov(cb, REG0, arg0);
        sub(cb, REG0, arg1);
        jo_ptr(cb, side_exit);
        add(cb, REG0, imm_opnd(1));

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Fixnum);
        mov(cb, dst, REG0);

        KeepCompiling
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, ctx, cb, ocb)
    }
}

fn gen_opt_mult(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, cb, ocb)
}

fn gen_opt_div(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, cb, ocb)
}

fn gen_opt_mod(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Save the PC and SP because the callee may allocate bignums
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    let side_exit = get_side_exit(jit, ocb, ctx);

    // Get the operands from the stack
    let arg1 = ctx.stack_pop(1);
    let arg0 = ctx.stack_pop(1);

    // Call rb_vm_opt_mod(VALUE recv, VALUE obj)
    mov(cb, C_ARG_REGS[0], arg0);
    mov(cb, C_ARG_REGS[1], arg1);
    call_ptr(cb, REG0, rb_vm_opt_mod as *const u8);

    // If val == Qundef, bail to do a method call
    cmp(cb, RAX, imm_opnd(Qundef.as_i64()));
    je_ptr(cb, side_exit);

    // Push the return value onto the stack
    let stack_ret = ctx.stack_push(Type::Unknown);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

fn gen_opt_ltlt(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, cb, ocb)
}

fn gen_opt_nil_p(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, cb, ocb)
}

fn gen_opt_empty_p(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, cb, ocb)
}

fn gen_opt_succ(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, cb, ocb)
}

fn gen_opt_str_freeze(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !assume_bop_not_redefined(jit, ocb, STRING_REDEFINED_OP_FLAG, BOP_FREEZE) {
        return CantCompile;
    }

    let str = jit_get_arg(jit, 0);
    jit_mov_gc_ptr(jit, cb, REG0, str);

    // Push the return value onto the stack
    let stack_ret = ctx.stack_push(Type::String);
    mov(cb, stack_ret, REG0);

    KeepCompiling
}

fn gen_opt_str_uminus(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !assume_bop_not_redefined(jit, ocb, STRING_REDEFINED_OP_FLAG, BOP_UMINUS) {
        return CantCompile;
    }

    let str = jit_get_arg(jit, 0);
    jit_mov_gc_ptr(jit, cb, REG0, str);

    // Push the return value onto the stack
    let stack_ret = ctx.stack_push(Type::String);
    mov(cb, stack_ret, REG0);

    KeepCompiling
}

fn gen_opt_not(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    return gen_opt_send_without_block(jit, ctx, cb, ocb);
}

fn gen_opt_size(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    return gen_opt_send_without_block(jit, ctx, cb, ocb);
}

fn gen_opt_length(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    return gen_opt_send_without_block(jit, ctx, cb, ocb);
}

fn gen_opt_regexpmatch2(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    return gen_opt_send_without_block(jit, ctx, cb, ocb);
}

fn gen_opt_case_dispatch(
    _jit: &mut JITState,
    ctx: &mut Context,
    _cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Normally this instruction would lookup the key in a hash and jump to an
    // offset based on that.
    // Instead we can take the fallback case and continue with the next
    // instruction.
    // We'd hope that our jitted code will be sufficiently fast without the
    // hash lookup, at least for small hashes, but it's worth revisiting this
    // assumption in the future.

    ctx.stack_pop(1);

    KeepCompiling // continue with the next instruction
}

fn gen_branchif_branch(
    cb: &mut CodeBlock,
    target0: CodePtr,
    target1: Option<CodePtr>,
    shape: BranchShape,
) {
    assert!(target1 != None);
    match shape {
        BranchShape::Next0 => {
            jz_ptr(cb, target1.unwrap());
        }
        BranchShape::Next1 => {
            jnz_ptr(cb, target0);
        }
        BranchShape::Default => {
            jnz_ptr(cb, target0);
            jmp_ptr(cb, target1.unwrap());
        }
    }
}

fn gen_branchif(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        let side_exit = get_side_exit(jit, ocb, ctx);
        gen_check_ints(cb, side_exit);
    }

    // Test if any bit (outside of the Qnil bit) is on
    // RUBY_Qfalse  /* ...0000 0000 */
    // RUBY_Qnil    /* ...0000 1000 */
    let val_opnd = ctx.stack_pop(1);
    test(cb, val_opnd, imm_opnd(!Qnil.as_i64()));

    // Get the branch target instruction offsets
    let next_idx = jit_next_insn_idx(jit);
    let jump_idx = (next_idx as i32) + jump_offset;
    let next_block = BlockId {
        iseq: jit.iseq,
        idx: next_idx,
    };
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx as u32,
    };

    // Generate the branch instructions
    gen_branch(
        jit,
        ctx,
        cb,
        ocb,
        jump_block,
        ctx,
        Some(next_block),
        Some(ctx),
        gen_branchif_branch,
    );

    EndBlock
}

fn gen_branchunless_branch(
    cb: &mut CodeBlock,
    target0: CodePtr,
    target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 => jnz_ptr(cb, target1.unwrap()),
        BranchShape::Next1 => jz_ptr(cb, target0),
        BranchShape::Default => {
            jz_ptr(cb, target0);
            jmp_ptr(cb, target1.unwrap());
        }
    }
}

fn gen_branchunless(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        let side_exit = get_side_exit(jit, ocb, ctx);
        gen_check_ints(cb, side_exit);
    }

    // Test if any bit (outside of the Qnil bit) is on
    // RUBY_Qfalse  /* ...0000 0000 */
    // RUBY_Qnil    /* ...0000 1000 */
    let val_opnd = ctx.stack_pop(1);
    test(cb, val_opnd, imm_opnd(!Qnil.as_i64()));

    // Get the branch target instruction offsets
    let next_idx = jit_next_insn_idx(jit) as i32;
    let jump_idx = next_idx + jump_offset;
    let next_block = BlockId {
        iseq: jit.iseq,
        idx: next_idx.try_into().unwrap(),
    };
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx.try_into().unwrap(),
    };

    // Generate the branch instructions
    gen_branch(
        jit,
        ctx,
        cb,
        ocb,
        jump_block,
        ctx,
        Some(next_block),
        Some(ctx),
        gen_branchunless_branch,
    );

    EndBlock
}

fn gen_branchnil_branch(
    cb: &mut CodeBlock,
    target0: CodePtr,
    target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 => jne_ptr(cb, target1.unwrap()),
        BranchShape::Next1 => je_ptr(cb, target0),
        BranchShape::Default => {
            je_ptr(cb, target0);
            jmp_ptr(cb, target1.unwrap());
        }
    }
}

fn gen_branchnil(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        let side_exit = get_side_exit(jit, ocb, ctx);
        gen_check_ints(cb, side_exit);
    }

    // Test if the value is Qnil
    // RUBY_Qnil    /* ...0000 1000 */
    let val_opnd = ctx.stack_pop(1);
    cmp(cb, val_opnd, uimm_opnd(Qnil.into()));

    // Get the branch target instruction offsets
    let next_idx = jit_next_insn_idx(jit) as i32;
    let jump_idx = next_idx + jump_offset;
    let next_block = BlockId {
        iseq: jit.iseq,
        idx: next_idx.try_into().unwrap(),
    };
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx.try_into().unwrap(),
    };

    // Generate the branch instructions
    gen_branch(
        jit,
        ctx,
        cb,
        ocb,
        jump_block,
        ctx,
        Some(next_block),
        Some(ctx),
        gen_branchnil_branch,
    );

    EndBlock
}

fn gen_jump(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        let side_exit = get_side_exit(jit, ocb, ctx);
        gen_check_ints(cb, side_exit);
    }

    // Get the branch target instruction offsets
    let jump_idx = (jit_next_insn_idx(jit) as i32) + jump_offset;
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx as u32,
    };

    // Generate the jump instruction
    gen_direct_jump(jit, ctx, jump_block, cb);

    EndBlock
}

/// Guard that self or a stack operand has the same class as `known_klass`, using
/// `sample_instance` to speculate about the shape of the runtime value.
/// FIXNUM and on-heap integers are treated as if they have distinct classes, and
/// the guard generated for one will fail for the other.
///
/// Recompile as contingency if possible, or take side exit a last resort.

fn jit_guard_known_klass(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    known_klass: VALUE,
    insn_opnd: InsnOpnd,
    sample_instance: VALUE,
    max_chain_depth: i32,
    side_exit: CodePtr,
) {
    let val_type = ctx.get_opnd_type(insn_opnd);

    if unsafe { known_klass == rb_cNilClass } {
        assert!(!val_type.is_heap());
        if val_type != Type::Nil {
            assert!(val_type.is_unknown());

            add_comment(cb, "guard object is nil");
            cmp(cb, REG0, imm_opnd(Qnil.into()));
            jit_chain_guard(JCC_JNE, jit, ctx, cb, ocb, max_chain_depth, side_exit);

            ctx.upgrade_opnd_type(insn_opnd, Type::Nil);
        }
    } else if unsafe { known_klass == rb_cTrueClass } {
        assert!(!val_type.is_heap());
        if val_type != Type::True {
            assert!(val_type.is_unknown());

            add_comment(cb, "guard object is true");
            cmp(cb, REG0, imm_opnd(Qtrue.into()));
            jit_chain_guard(JCC_JNE, jit, ctx, cb, ocb, max_chain_depth, side_exit);

            ctx.upgrade_opnd_type(insn_opnd, Type::True);
        }
    } else if unsafe { known_klass == rb_cFalseClass } {
        assert!(!val_type.is_heap());
        if val_type != Type::False {
            assert!(val_type.is_unknown());

            add_comment(cb, "guard object is false");
            assert!(Qfalse.as_i32() == 0);
            test(cb, REG0, REG0);
            jit_chain_guard(JCC_JNZ, jit, ctx, cb, ocb, max_chain_depth, side_exit);

            ctx.upgrade_opnd_type(insn_opnd, Type::False);
        }
    } else if unsafe { known_klass == rb_cInteger } && sample_instance.fixnum_p() {
        assert!(!val_type.is_heap());
        // We will guard fixnum and bignum as though they were separate classes
        // BIGNUM can be handled by the general else case below
        if val_type != Type::Fixnum || !val_type.is_imm() {
            assert!(val_type.is_unknown());

            add_comment(cb, "guard object is fixnum");
            test(cb, REG0, imm_opnd(RUBY_FIXNUM_FLAG as i64));
            jit_chain_guard(JCC_JZ, jit, ctx, cb, ocb, max_chain_depth, side_exit);
            ctx.upgrade_opnd_type(insn_opnd, Type::Fixnum);
        }
    } else if unsafe { known_klass == rb_cSymbol } && sample_instance.static_sym_p() {
        assert!(!val_type.is_heap());
        // We will guard STATIC vs DYNAMIC as though they were separate classes
        // DYNAMIC symbols can be handled by the general else case below
        if val_type != Type::ImmSymbol || !val_type.is_imm() {
            assert!(val_type.is_unknown());

            add_comment(cb, "guard object is static symbol");
            assert!(RUBY_SPECIAL_SHIFT == 8);
            cmp(cb, REG0_8, uimm_opnd(RUBY_SYMBOL_FLAG as u64));
            jit_chain_guard(JCC_JNE, jit, ctx, cb, ocb, max_chain_depth, side_exit);
            ctx.upgrade_opnd_type(insn_opnd, Type::ImmSymbol);
        }
    } else if unsafe { known_klass == rb_cFloat } && sample_instance.flonum_p() {
        assert!(!val_type.is_heap());
        if val_type != Type::Flonum || !val_type.is_imm() {
            assert!(val_type.is_unknown());

            // We will guard flonum vs heap float as though they were separate classes
            add_comment(cb, "guard object is flonum");
            mov(cb, REG1, REG0);
            and(cb, REG1, uimm_opnd(RUBY_FLONUM_MASK as u64));
            cmp(cb, REG1, uimm_opnd(RUBY_FLONUM_FLAG as u64));
            jit_chain_guard(JCC_JNE, jit, ctx, cb, ocb, max_chain_depth, side_exit);
            ctx.upgrade_opnd_type(insn_opnd, Type::Flonum);
        }
    } else if unsafe {
        FL_TEST(known_klass, VALUE(RUBY_FL_SINGLETON as usize)) != VALUE(0)
            && sample_instance == rb_attr_get(known_klass, id__attached__ as ID)
    } {
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
        add_comment(cb, "guard known object with singleton class");
        // TODO: jit_mov_gc_ptr keeps a strong reference, which leaks the object.
        jit_mov_gc_ptr(jit, cb, REG1, sample_instance);
        cmp(cb, REG0, REG1);
        jit_chain_guard(JCC_JNE, jit, ctx, cb, ocb, max_chain_depth, side_exit);
    } else {
        assert!(!val_type.is_imm());

        // Check that the receiver is a heap object
        // Note: if we get here, the class doesn't have immediate instances.
        if !val_type.is_heap() {
            add_comment(cb, "guard not immediate");
            assert!(Qfalse.as_i32() < Qnil.as_i32());
            test(cb, REG0, imm_opnd(RUBY_IMMEDIATE_MASK as i64));
            jit_chain_guard(JCC_JNZ, jit, ctx, cb, ocb, max_chain_depth, side_exit);
            cmp(cb, REG0, imm_opnd(Qnil.into()));
            jit_chain_guard(JCC_JBE, jit, ctx, cb, ocb, max_chain_depth, side_exit);

            ctx.upgrade_opnd_type(insn_opnd, Type::UnknownHeap);
        }

        let klass_opnd = mem_opnd(64, REG0, RUBY_OFFSET_RBASIC_KLASS);

        // Bail if receiver class is different from known_klass
        // TODO: jit_mov_gc_ptr keeps a strong reference, which leaks the class.
        add_comment(cb, "guard known class");
        jit_mov_gc_ptr(jit, cb, REG1, known_klass);
        cmp(cb, klass_opnd, REG1);
        jit_chain_guard(JCC_JNE, jit, ctx, cb, ocb, max_chain_depth, side_exit);
    }
}

// Generate ancestry guard for protected callee.
// Calls to protected callees only go through when self.is_a?(klass_that_defines_the_callee).
fn jit_protected_callee_ancestry_guard(
    jit: &mut JITState,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    cme: *const rb_callable_method_entry_t,
    side_exit: CodePtr,
) {
    // See vm_call_method().
    mov(
        cb,
        C_ARG_REGS[0],
        mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SELF),
    );
    let def_class = unsafe { (*cme).defined_class };
    jit_mov_gc_ptr(jit, cb, C_ARG_REGS[1], def_class);
    // Note: PC isn't written to current control frame as rb_is_kind_of() shouldn't raise.
    // VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);

    call_ptr(cb, REG0, rb_obj_is_kind_of as *mut u8);
    test(cb, RAX, RAX);
    jz_ptr(
        cb,
        counted_exit!(ocb, side_exit, send_se_protected_check_failed),
    );
}

// Codegen for rb_obj_not().
// Note, caller is responsible for generating all the right guards, including
// arity guards.
fn jit_rb_obj_not(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    let recv_opnd = ctx.get_opnd_type(StackOpnd(0));

    if recv_opnd == Type::Nil || recv_opnd == Type::False {
        add_comment(cb, "rb_obj_not(nil_or_false)");
        ctx.stack_pop(1);
        let out_opnd = ctx.stack_push(Type::True);
        mov(cb, out_opnd, uimm_opnd(Qtrue.into()));
    } else if recv_opnd.is_heap() || recv_opnd.is_specific() {
        // Note: recv_opnd != Type::Nil && recv_opnd != Type::False.
        add_comment(cb, "rb_obj_not(truthy)");
        ctx.stack_pop(1);
        let out_opnd = ctx.stack_push(Type::False);
        mov(cb, out_opnd, uimm_opnd(Qfalse.into()));
    } else {
        // jit_guard_known_klass() already ran on the receiver which should
        // have deduced deduced the type of the receiver. This case should be
        // rare if not unreachable.
        return false;
    }
    true
}

// Codegen for rb_true()
fn jit_rb_true(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    add_comment(cb, "nil? == true");
    ctx.stack_pop(1);
    let stack_ret = ctx.stack_push(Type::True);
    mov(cb, stack_ret, uimm_opnd(Qtrue.into()));
    true
}

// Codegen for rb_false()
fn jit_rb_false(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    add_comment(cb, "nil? == false");
    ctx.stack_pop(1);
    let stack_ret = ctx.stack_push(Type::False);
    mov(cb, stack_ret, uimm_opnd(Qfalse.into()));
    true
}

// Codegen for rb_obj_equal()
// object identity comparison
fn jit_rb_obj_equal(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    add_comment(cb, "equal?");
    let obj1 = ctx.stack_pop(1);
    let obj2 = ctx.stack_pop(1);

    mov(cb, REG0, obj1);
    cmp(cb, REG0, obj2);
    mov(cb, REG0, uimm_opnd(Qtrue.into()));
    mov(cb, REG1, uimm_opnd(Qfalse.into()));
    cmovne(cb, REG0, REG1);

    let stack_ret = ctx.stack_push(Type::UnknownImm);
    mov(cb, stack_ret, REG0);
    true
}

/// If string is frozen, duplicate it to get a non-frozen string. Otherwise, return it.
fn jit_rb_str_uplus(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool
{
    let recv = ctx.stack_pop(1);

    add_comment(cb, "Unary plus on string");
    mov(cb, REG0, recv);
    mov(cb, REG1, mem_opnd(64, REG0, RUBY_OFFSET_RBASIC_FLAGS));
    test(cb, REG1, imm_opnd(RUBY_FL_FREEZE as i64));

    let ret_label = cb.new_label("stack_ret".to_string());
    // If the string isn't frozen, we just return it. It's already in REG0.
    jz_label(cb, ret_label);

    // Str is frozen - duplicate
    mov(cb, C_ARG_REGS[0], REG0);
    call_ptr(cb, REG0, rb_str_dup as *const u8);
    // Return value is in REG0, drop through and return it.

    cb.write_label(ret_label);
    let stack_ret = ctx.stack_push(Type::String);
    mov(cb, stack_ret, REG0);

    cb.link_labels();
    true
}

fn jit_rb_str_bytesize(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    add_comment(cb, "String#bytesize");

    let recv = ctx.stack_pop(1);
    mov(cb, C_ARG_REGS[0], recv);
    call_ptr(cb, REG0, rb_str_bytesize as *const u8);

    let out_opnd = ctx.stack_push(Type::Fixnum);
    mov(cb, out_opnd, RAX);

    true
}

// Codegen for rb_str_to_s()
// When String#to_s is called on a String instance, the method returns self and
// most of the overhead comes from setting up the method call. We observed that
// this situation happens a lot in some workloads.
fn jit_rb_str_to_s(
    _jit: &mut JITState,
    _ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    known_recv_class: *const VALUE,
) -> bool {
    if !known_recv_class.is_null() && unsafe { *known_recv_class == rb_cString } {
        add_comment(cb, "to_s on plain string");
        // The method returns the receiver, which is already on the stack.
        // No stack movement.
        return true;
    }
    false
}

// Codegen for rb_str_concat()
// Frequently strings are concatenated using "out_str << next_str".
// This is common in Erb and similar templating languages.
fn jit_rb_str_concat(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    let comptime_arg = jit_peek_at_stack(jit, ctx, 0);
    let comptime_arg_type = ctx.get_opnd_type(StackOpnd(0));

    // String#<< can take an integer codepoint as an argument, but we don't optimise that.
    // Also, a non-string argument would have to call .to_str on itself before being treated
    // as a string, and that would require saving pc/sp, which we don't do here.
    if comptime_arg_type != Type::String {
        return false;
    }

    // Generate a side exit
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Guard that the argument is of class String at runtime.
    let arg_opnd = ctx.stack_opnd(0);
    mov(cb, REG0, arg_opnd);
    jit_guard_known_klass(
        jit,
        ctx,
        cb,
        ocb,
        unsafe { rb_cString },
        StackOpnd(0),
        comptime_arg,
        SEND_MAX_DEPTH,
        side_exit,
    );

    let concat_arg = ctx.stack_pop(1);
    let recv = ctx.stack_pop(1);

    // Test if string encodings differ. If different, use rb_str_append. If the same,
    // use rb_yjit_str_simple_append, which calls rb_str_cat.
    add_comment(cb, "<< on strings");

    // Both rb_str_append and rb_yjit_str_simple_append take identical args
    mov(cb, C_ARG_REGS[0], recv);
    mov(cb, C_ARG_REGS[1], concat_arg);

    // Take receiver's object flags XOR arg's flags. If any
    // string-encoding flags are different between the two,
    // the encodings don't match.
    mov(cb, REG0, recv);
    mov(cb, REG1, concat_arg);
    mov(cb, REG0, mem_opnd(64, REG0, RUBY_OFFSET_RBASIC_FLAGS));
    xor(cb, REG0, mem_opnd(64, REG1, RUBY_OFFSET_RBASIC_FLAGS));
    test(cb, REG0, uimm_opnd(RUBY_ENCODING_MASK as u64));

    let enc_mismatch = cb.new_label("enc_mismatch".to_string());
    jne_label(cb, enc_mismatch);

    // If encodings match, call the simple append function and jump to return
    call_ptr(cb, REG0, rb_yjit_str_simple_append as *const u8);
    let ret_label: usize = cb.new_label("stack_return".to_string());
    jmp_label(cb, ret_label);

    // If encodings are different, use a slower encoding-aware concatenate
    cb.write_label(enc_mismatch);
    call_ptr(cb, REG0, rb_str_append as *const u8);
    // Drop through to return

    cb.write_label(ret_label);
    let stack_ret = ctx.stack_push(Type::String);
    mov(cb, stack_ret, RAX);

    cb.link_labels();
    true
}

fn jit_thread_s_current(
    _jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    add_comment(cb, "Thread.current");
    ctx.stack_pop(1);

    // ec->thread_ptr
    let ec_thread_ptr = mem_opnd(64, REG_EC, RUBY_OFFSET_EC_THREAD_PTR);
    mov(cb, REG0, ec_thread_ptr);

    // thread->self
    let thread_self = mem_opnd(64, REG0, RUBY_OFFSET_THREAD_SELF);
    mov(cb, REG0, thread_self);

    let stack_ret = ctx.stack_push(Type::UnknownHeap);
    mov(cb, stack_ret, REG0);
    true
}

// Check if we know how to codegen for a particular cfunc method
fn lookup_cfunc_codegen(def: *const rb_method_definition_t) -> Option<MethodGenFn> {
    let method_serial = unsafe { get_def_method_serial(def) };

    CodegenGlobals::look_up_codegen_method(method_serial)
}

// Is anyone listening for :c_call and :c_return event currently?
fn c_method_tracing_currently_enabled(jit: &JITState) -> bool {
    // Defer to C implementation in yjit.c
    unsafe {
        rb_c_method_tracing_currently_enabled(jit.ec.unwrap() as *mut rb_execution_context_struct)
    }
}

// Similar to args_kw_argv_to_hash. It is called at runtime from within the
// generated assembly to build a Ruby hash of the passed keyword arguments. The
// keys are the Symbol objects associated with the keywords and the values are
// the actual values. In the representation, both keys and values are VALUEs.
unsafe extern "C" fn build_kwhash(ci: *const rb_callinfo, sp: *const VALUE) -> VALUE {
    let kw_arg = vm_ci_kwarg(ci);
    let kw_len: usize = get_cikw_keyword_len(kw_arg).try_into().unwrap();
    let hash = rb_hash_new_with_size(kw_len as u64);

    for kwarg_idx in 0..kw_len {
        let key = get_cikw_keywords_idx(kw_arg, kwarg_idx.try_into().unwrap());
        let val = sp.sub(kw_len).add(kwarg_idx).read();
        rb_hash_aset(hash, key, val);
    }
    hash
}

fn gen_send_cfunc(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    block: Option<IseqPtr>,
    argc: i32,
    recv_known_klass: *const VALUE,
) -> CodegenStatus {
    let cfunc = unsafe { get_cme_def_body_cfunc(cme) };
    let cfunc_argc = unsafe { get_mct_argc(cfunc) };

    // If the function expects a Ruby array of arguments
    if cfunc_argc < 0 && cfunc_argc != -1 {
        gen_counter_incr!(cb, send_cfunc_ruby_array_varg);
        return CantCompile;
    }

    let kw_arg = unsafe { vm_ci_kwarg(ci) };
    let kw_arg_num = if kw_arg.is_null() {
        0
    } else {
        unsafe { get_cikw_keyword_len(kw_arg) }
    };

    // Number of args which will be passed through to the callee
    // This is adjusted by the kwargs being combined into a hash.
    let passed_argc = if kw_arg.is_null() {
        argc
    } else {
        argc - kw_arg_num + 1
    };

    // If the argument count doesn't match
    if cfunc_argc >= 0 && cfunc_argc != passed_argc {
        gen_counter_incr!(cb, send_cfunc_argc_mismatch);
        return CantCompile;
    }

    // Don't JIT functions that need C stack arguments for now
    if cfunc_argc >= 0 && passed_argc + 1 > (C_ARG_REGS.len() as i32) {
        gen_counter_incr!(cb, send_cfunc_toomany_args);
        return CantCompile;
    }

    if c_method_tracing_currently_enabled(jit) {
        // Don't JIT if tracing c_call or c_return
        gen_counter_incr!(cb, send_cfunc_tracing);
        return CantCompile;
    }

    // Delegate to codegen for C methods if we have it.
    if kw_arg.is_null() {
        let codegen_p = lookup_cfunc_codegen(unsafe { (*cme).def });
        if let Some(known_cfunc_codegen) = codegen_p {
            let start_pos = cb.get_write_ptr().raw_ptr() as usize;
            if known_cfunc_codegen(jit, ctx, cb, ocb, ci, cme, block, argc, recv_known_klass) {
                let written_bytes = cb.get_write_ptr().raw_ptr() as usize - start_pos;
                if written_bytes < JUMP_SIZE_IN_BYTES {
                    add_comment(cb, "Writing NOPs to leave room for later invalidation code");
                    nop(cb, (JUMP_SIZE_IN_BYTES - written_bytes) as u32);
                }
                // cfunc codegen generated code. Terminate the block so
                // there isn't multiple calls in the same block.
                jump_to_next_insn(jit, ctx, cb, ocb);
                return EndBlock;
            }
        }
    }

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Check for interrupts
    gen_check_ints(cb, side_exit);

    // Stack overflow check
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    // REG_CFP <= REG_SP + 4 * SIZEOF_VALUE + sizeof(rb_control_frame_t)
    add_comment(cb, "stack overflow check");
    lea(
        cb,
        REG0,
        ctx.sp_opnd((SIZEOF_VALUE * 4 + 2 * RUBY_SIZEOF_CONTROL_FRAME) as isize),
    );
    cmp(cb, REG_CFP, REG0);
    jle_ptr(cb, counted_exit!(ocb, side_exit, send_se_cf_overflow));

    // Points to the receiver operand on the stack
    let recv = ctx.stack_opnd(argc);

    // Store incremented PC into current control frame in case callee raises.
    jit_save_pc(jit, cb, REG0);

    if let Some(block_iseq) = block {
        // Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
        // VM_CFP_TO_CAPTURED_BLOCK does &cfp->self, rb_captured_block->code.iseq aliases
        // with cfp->block_code.
        jit_mov_gc_ptr(jit, cb, REG0, VALUE(block_iseq as usize));
        let block_code_opnd = mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_BLOCK_CODE);
        mov(cb, block_code_opnd, REG0);
    }

    // Increment the stack pointer by 3 (in the callee)
    // sp += 3
    lea(cb, REG0, ctx.sp_opnd((SIZEOF_VALUE as isize) * 3));

    // Write method entry at sp[-3]
    // sp[-3] = me;
    // Put compile time cme into REG1. It's assumed to be valid because we are notified when
    // any cme we depend on become outdated. See yjit_method_lookup_change().
    jit_mov_gc_ptr(jit, cb, REG1, VALUE(cme as usize));
    mov(cb, mem_opnd(64, REG0, 8 * -3), REG1);

    // Write block handler at sp[-2]
    // sp[-2] = block_handler;
    if let Some(_block_iseq) = block {
        // reg1 = VM_BH_FROM_ISEQ_BLOCK(VM_CFP_TO_CAPTURED_BLOCK(reg_cfp));
        let cfp_self = mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SELF);
        lea(cb, REG1, cfp_self);
        or(cb, REG1, imm_opnd(1));
        mov(cb, mem_opnd(64, REG0, 8 * -2), REG1);
    } else {
        let dst_opnd = mem_opnd(64, REG0, 8 * -2);
        mov(cb, dst_opnd, uimm_opnd(VM_BLOCK_HANDLER_NONE.into()));
    }

    // Write env flags at sp[-1]
    // sp[-1] = frame_type;
    let mut frame_type = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;
    if !kw_arg.is_null() {
        frame_type |= VM_FRAME_FLAG_CFRAME_KW
    }
    mov(cb, mem_opnd(64, REG0, 8 * -1), uimm_opnd(frame_type.into()));

    // Allocate a new CFP (ec->cfp--)
    let ec_cfp_opnd = mem_opnd(64, REG_EC, RUBY_OFFSET_EC_CFP);
    sub(cb, ec_cfp_opnd, uimm_opnd(RUBY_SIZEOF_CONTROL_FRAME as u64));

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

    // Can we re-use ec_cfp_opnd from above?
    let ec_cfp_opnd = mem_opnd(64, REG_EC, RUBY_OFFSET_EC_CFP);
    mov(cb, REG1, ec_cfp_opnd);
    mov(cb, mem_opnd(64, REG1, RUBY_OFFSET_CFP_PC), imm_opnd(0));

    mov(cb, mem_opnd(64, REG1, RUBY_OFFSET_CFP_SP), REG0);
    mov(cb, mem_opnd(64, REG1, RUBY_OFFSET_CFP_ISEQ), imm_opnd(0));
    mov(
        cb,
        mem_opnd(64, REG1, RUBY_OFFSET_CFP_BLOCK_CODE),
        imm_opnd(0),
    );
    mov(cb, mem_opnd(64, REG1, RUBY_OFFSET_CFP_BP), REG0);
    sub(cb, REG0, uimm_opnd(SIZEOF_VALUE as u64));
    mov(cb, mem_opnd(64, REG1, RUBY_OFFSET_CFP_EP), REG0);
    mov(cb, REG0, recv);
    mov(cb, mem_opnd(64, REG1, RUBY_OFFSET_CFP_SELF), REG0);

    /*
    // Verify that we are calling the right function
    if (YJIT_CHECK_MODE > 0) {  // TODO: will we have a YJIT_CHECK_MODE?
        // Call check_cfunc_dispatch
        mov(cb, C_ARG_REGS[0], recv);
        jit_mov_gc_ptr(jit, cb, C_ARG_REGS[1], (VALUE)ci);
        mov(cb, C_ARG_REGS[2], const_ptr_opnd((void *)cfunc->func));
        jit_mov_gc_ptr(jit, cb, C_ARG_REGS[3], (VALUE)cme);
        call_ptr(cb, REG0, (void *)&check_cfunc_dispatch);
    }
    */

    if !kw_arg.is_null() {
        // Build a hash from all kwargs passed
        jit_mov_gc_ptr(jit, cb, C_ARG_REGS[0], VALUE(ci as usize));
        lea(cb, C_ARG_REGS[1], ctx.sp_opnd(0));
        call_ptr(cb, REG0, build_kwhash as *const u8);

        // Replace the stack location at the start of kwargs with the new hash
        let stack_opnd = ctx.stack_opnd(argc - passed_argc);
        mov(cb, stack_opnd, RAX);
    }

    // Copy SP into RAX because REG_SP will get overwritten
    lea(cb, RAX, ctx.sp_opnd(0));

    // Pop the C function arguments from the stack (in the caller)
    ctx.stack_pop((argc + 1).try_into().unwrap());

    // Write interpreter SP into CFP.
    // Needed in case the callee yields to the block.
    gen_save_sp(cb, ctx);

    // Non-variadic method
    if cfunc_argc >= 0 {
        // Copy the arguments from the stack to the C argument registers
        // self is the 0th argument and is at index argc from the stack top
        for i in 0..=passed_argc as usize {
            let stack_opnd = mem_opnd(64, RAX, -(argc + 1 - (i as i32)) * SIZEOF_VALUE_I32);
            let c_arg_reg = C_ARG_REGS[i];
            mov(cb, c_arg_reg, stack_opnd);
        }
    }

    // Variadic method
    if cfunc_argc == -1 {
        // The method gets a pointer to the first argument
        // rb_f_puts(int argc, VALUE *argv, VALUE recv)
        mov(cb, C_ARG_REGS[0], imm_opnd(passed_argc.into()));
        lea(
            cb,
            C_ARG_REGS[1],
            mem_opnd(64, RAX, -(argc) * SIZEOF_VALUE_I32),
        );
        mov(
            cb,
            C_ARG_REGS[2],
            mem_opnd(64, RAX, -(argc + 1) * SIZEOF_VALUE_I32),
        );
    }

    // Call the C function
    // VALUE ret = (cfunc->func)(recv, argv[0], argv[1]);
    // cfunc comes from compile-time cme->def, which we assume to be stable.
    // Invalidation logic is in yjit_method_lookup_change()
    add_comment(cb, "call C function");
    call_ptr(cb, REG0, unsafe { get_mct_func(cfunc) });

    // Record code position for TracePoint patching. See full_cfunc_return().
    record_global_inval_patch(cb, CodegenGlobals::get_outline_full_cfunc_return_pos());

    // Push the return value on the Ruby stack
    let stack_ret = ctx.stack_push(Type::Unknown);
    mov(cb, stack_ret, RAX);

    // Pop the stack frame (ec->cfp++)
    // Can we reuse ec_cfp_opnd from above?
    let ec_cfp_opnd = mem_opnd(64, REG_EC, RUBY_OFFSET_EC_CFP);
    add(cb, ec_cfp_opnd, uimm_opnd(RUBY_SIZEOF_CONTROL_FRAME as u64));

    // cfunc calls may corrupt types
    ctx.clear_local_types();

    // Note: the return block of gen_send_iseq() has ctx->sp_offset == 1
    // which allows for sharing the same successor.

    // Jump (fall through) to the call continuation block
    // We do this to end the current block after the call
    jump_to_next_insn(jit, ctx, cb, ocb);
    EndBlock
}

fn gen_return_branch(
    cb: &mut CodeBlock,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 | BranchShape::Next1 => unreachable!(),
        BranchShape::Default => {
            mov(cb, REG0, code_ptr_opnd(target0));
            mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_JIT_RETURN), REG0);
        }
    }
}

fn gen_send_iseq(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    block: Option<IseqPtr>,
    argc: i32,
) -> CodegenStatus {
    let iseq = unsafe { get_def_iseq_ptr((*cme).def) };
    let mut argc = argc;

    // When you have keyword arguments, there is an extra object that gets
    // placed on the stack the represents a bitmap of the keywords that were not
    // specified at the call site. We need to keep track of the fact that this
    // value is present on the stack in order to properly set up the callee's
    // stack pointer.
    let doing_kw_call = unsafe { get_iseq_flags_has_kw(iseq) };
    let supplying_kws = unsafe { vm_ci_flag(ci) & VM_CALL_KWARG } != 0;

    if unsafe { vm_ci_flag(ci) } & VM_CALL_TAILCALL != 0 {
        // We can't handle tailcalls
        gen_counter_incr!(cb, send_iseq_tailcall);
        return CantCompile;
    }

    // No support for callees with these parameters yet as they require allocation
    // or complex handling.
    if unsafe {
        get_iseq_flags_has_rest(iseq)
            || get_iseq_flags_has_post(iseq)
            || get_iseq_flags_has_kwrest(iseq)
    } {
        gen_counter_incr!(cb, send_iseq_complex_callee);
        return CantCompile;
    }

    // If we have keyword arguments being passed to a callee that only takes
    // positionals, then we need to allocate a hash. For now we're going to
    // call that too complex and bail.
    if supplying_kws && !unsafe { get_iseq_flags_has_kw(iseq) } {
        gen_counter_incr!(cb, send_iseq_complex_callee);
        return CantCompile;
    }

    // If we have a method accepting no kwargs (**nil), exit if we have passed
    // it any kwargs.
    if supplying_kws && unsafe { get_iseq_flags_has_accepts_no_kwarg(iseq) } {
        gen_counter_incr!(cb, send_iseq_complex_callee);
        return CantCompile;
    }

    // For computing number of locals to set up for the callee
    let mut num_params = unsafe { get_iseq_body_param_size(iseq) };

    // Block parameter handling. This mirrors setup_parameters_complex().
    if unsafe { get_iseq_flags_has_block(iseq) } {
        if unsafe { get_iseq_body_local_iseq(iseq) == iseq } {
            num_params -= 1;
        } else {
            // In this case (param.flags.has_block && local_iseq != iseq),
            // the block argument is setup as a local variable and requires
            // materialization (allocation). Bail.
            gen_counter_incr!(cb, send_iseq_complex_callee);
            return CantCompile;
        }
    }

    let mut start_pc_offset = 0;
    let required_num = unsafe { get_iseq_body_param_lead_num(iseq) };

    // This struct represents the metadata about the caller-specified
    // keyword arguments.
    let kw_arg = unsafe { vm_ci_kwarg(ci) };
    let kw_arg_num = if kw_arg.is_null() {
        0
    } else {
        unsafe { get_cikw_keyword_len(kw_arg) }
    };

    // Arity handling and optional parameter setup
    let opts_filled = argc - required_num - kw_arg_num;
    let opt_num = unsafe { get_iseq_body_param_opt_num(iseq) };
    let opts_missing: i32 = opt_num - opts_filled;

    if opts_filled < 0 || opts_filled > opt_num {
        gen_counter_incr!(cb, send_iseq_arity_error);
        return CantCompile;
    }

    // If we have unfilled optional arguments and keyword arguments then we
    // would need to move adjust the arguments location to account for that.
    // For now we aren't handling this case.
    if doing_kw_call && opts_missing > 0 {
        gen_counter_incr!(cb, send_iseq_complex_callee);
        return CantCompile;
    }

    if opt_num > 0 {
        num_params -= opts_missing as u32;
        unsafe {
            let opt_table = get_iseq_body_param_opt_table(iseq);
            start_pc_offset = (*opt_table.offset(opts_filled as isize)).as_u32();
        }
    }

    if doing_kw_call {
        // Here we're calling a method with keyword arguments and specifying
        // keyword arguments at this call site.

        // This struct represents the metadata about the callee-specified
        // keyword parameters.
        let keyword = unsafe { get_iseq_body_param_keyword(iseq) };
        let keyword_num: usize = unsafe { (*keyword).num }.try_into().unwrap();
        let keyword_required_num: usize = unsafe { (*keyword).required_num }.try_into().unwrap();

        let mut required_kwargs_filled = 0;

        if keyword_num > 30 {
            // We have so many keywords that (1 << num) encoded as a FIXNUM
            // (which shifts it left one more) no longer fits inside a 32-bit
            // immediate.
            gen_counter_incr!(cb, send_iseq_complex_callee);
            return CantCompile;
        }

        // Check that the kwargs being passed are valid
        if supplying_kws {
            // This is the list of keyword arguments that the callee specified
            // in its initial declaration.
            // SAFETY: see compile.c for sizing of this slice.
            let callee_kwargs = unsafe { slice::from_raw_parts((*keyword).table, keyword_num) };

            // Here we're going to build up a list of the IDs that correspond to
            // the caller-specified keyword arguments. If they're not in the
            // same order as the order specified in the callee declaration, then
            // we're going to need to generate some code to swap values around
            // on the stack.
            let kw_arg_keyword_len: usize =
                unsafe { get_cikw_keyword_len(kw_arg) }.try_into().unwrap();
            let mut caller_kwargs: Vec<ID> = vec![0; kw_arg_keyword_len];
            for kwarg_idx in 0..kw_arg_keyword_len {
                let sym = unsafe { get_cikw_keywords_idx(kw_arg, kwarg_idx.try_into().unwrap()) };
                caller_kwargs[kwarg_idx] = unsafe { rb_sym2id(sym) };
            }

            // First, we're going to be sure that the names of every
            // caller-specified keyword argument correspond to a name in the
            // list of callee-specified keyword parameters.
            for caller_kwarg in caller_kwargs {
                let search_result = callee_kwargs
                    .iter()
                    .enumerate() // inject element index
                    .find(|(_, &kwarg)| kwarg == caller_kwarg);

                match search_result {
                    None => {
                        // If the keyword was never found, then we know we have a
                        // mismatch in the names of the keyword arguments, so we need to
                        // bail.
                        gen_counter_incr!(cb, send_iseq_kwargs_mismatch);
                        return CantCompile;
                    }
                    Some((callee_idx, _)) if callee_idx < keyword_required_num => {
                        // Keep a count to ensure all required kwargs are specified
                        required_kwargs_filled += 1;
                    }
                    _ => (),
                }
            }
        }
        assert!(required_kwargs_filled <= keyword_required_num);
        if required_kwargs_filled != keyword_required_num {
            gen_counter_incr!(cb, send_iseq_kwargs_mismatch);
            return CantCompile;
        }
    }

    // Number of locals that are not parameters
    let num_locals = unsafe { get_iseq_body_local_table_size(iseq) as i32 } - (num_params as i32);

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Check for interrupts
    gen_check_ints(cb, side_exit);

    let leaf_builtin_raw = unsafe { rb_leaf_builtin_function(iseq) };
    let leaf_builtin: Option<*const rb_builtin_function> = if leaf_builtin_raw.is_null() {
        None
    } else {
        Some(leaf_builtin_raw)
    };
    if let (None, Some(builtin_info)) = (block, leaf_builtin) {
        let builtin_argc = unsafe { (*builtin_info).argc };
        if builtin_argc + 1 /* for self */ + 1 /* for ec */ <= (C_ARG_REGS.len() as i32) {
            add_comment(cb, "inlined leaf builtin");

            // Call the builtin func (ec, recv, arg1, arg2, ...)
            mov(cb, C_ARG_REGS[0], REG_EC);

            // Copy self and arguments
            for i in 0..=builtin_argc {
                let stack_opnd = ctx.stack_opnd(builtin_argc - i);
                let idx: usize = (i + 1).try_into().unwrap();
                let c_arg_reg = C_ARG_REGS[idx];
                mov(cb, c_arg_reg, stack_opnd);
            }
            ctx.stack_pop((builtin_argc + 1).try_into().unwrap());
            let builtin_func_ptr = unsafe { (*builtin_info).func_ptr as *const u8 };
            call_ptr(cb, REG0, builtin_func_ptr);

            // Push the return value
            let stack_ret = ctx.stack_push(Type::Unknown);
            mov(cb, stack_ret, RAX);

            // Note: assuming that the leaf builtin doesn't change local variables here.
            // Seems like a safe assumption.

            return KeepCompiling;
        }
    }

    // Stack overflow check
    // Note that vm_push_frame checks it against a decremented cfp, hence the multiply by 2.
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    add_comment(cb, "stack overflow check");
    let stack_max: i32 = unsafe { get_iseq_body_stack_max(iseq) }.try_into().unwrap();
    let locals_offs =
        (SIZEOF_VALUE as i32) * (num_locals + stack_max) + 2 * (RUBY_SIZEOF_CONTROL_FRAME as i32);
    lea(cb, REG0, ctx.sp_opnd(locals_offs as isize));
    cmp(cb, REG_CFP, REG0);
    jle_ptr(cb, counted_exit!(ocb, side_exit, send_se_cf_overflow));

    if doing_kw_call {
        // Here we're calling a method with keyword arguments and specifying
        // keyword arguments at this call site.

        // Number of positional arguments the callee expects before the first
        // keyword argument
        let args_before_kw = required_num + opt_num;

        // This struct represents the metadata about the caller-specified
        // keyword arguments.
        let ci_kwarg = unsafe { vm_ci_kwarg(ci) };
        let caller_keyword_len: usize = if ci_kwarg.is_null() {
            0
        } else {
            unsafe { get_cikw_keyword_len(ci_kwarg) }
                .try_into()
                .unwrap()
        };

        // This struct represents the metadata about the callee-specified
        // keyword parameters.
        let keyword = unsafe { get_iseq_body_param_keyword(iseq) };

        add_comment(cb, "keyword args");

        // This is the list of keyword arguments that the callee specified
        // in its initial declaration.
        let callee_kwargs = unsafe { (*keyword).table };
        let total_kwargs: usize = unsafe { (*keyword).num }.try_into().unwrap();

        // Here we're going to build up a list of the IDs that correspond to
        // the caller-specified keyword arguments. If they're not in the
        // same order as the order specified in the callee declaration, then
        // we're going to need to generate some code to swap values around
        // on the stack.
        let mut caller_kwargs: Vec<ID> = vec![0; total_kwargs];

        for kwarg_idx in 0..caller_keyword_len {
            let sym = unsafe { get_cikw_keywords_idx(ci_kwarg, kwarg_idx.try_into().unwrap()) };
            caller_kwargs[kwarg_idx] = unsafe { rb_sym2id(sym) };
        }
        let mut kwarg_idx = caller_keyword_len;

        let mut unspecified_bits = 0;

        let keyword_required_num: usize = unsafe { (*keyword).required_num }.try_into().unwrap();
        for callee_idx in keyword_required_num..total_kwargs {
            let mut already_passed = false;
            let callee_kwarg = unsafe { *(callee_kwargs.offset(callee_idx.try_into().unwrap())) };

            for caller_idx in 0..caller_keyword_len {
                if caller_kwargs[caller_idx] == callee_kwarg {
                    already_passed = true;
                    break;
                }
            }

            if !already_passed {
                // Reserve space on the stack for each default value we'll be
                // filling in (which is done in the next loop). Also increments
                // argc so that the callee's SP is recorded correctly.
                argc += 1;
                let default_arg = ctx.stack_push(Type::Unknown);

                // callee_idx - keyword->required_num is used in a couple of places below.
                let req_num: isize = unsafe { (*keyword).required_num }.try_into().unwrap();
                let callee_idx_isize: isize = callee_idx.try_into().unwrap();
                let extra_args = callee_idx_isize - req_num;

                //VALUE default_value = keyword->default_values[callee_idx - keyword->required_num];
                let mut default_value = unsafe { *((*keyword).default_values.offset(extra_args)) };

                if default_value == Qundef {
                    // Qundef means that this value is not constant and must be
                    // recalculated at runtime, so we record it in unspecified_bits
                    // (Qnil is then used as a placeholder instead of Qundef).
                    unspecified_bits |= 0x01 << extra_args;
                    default_value = Qnil;
                }

                jit_mov_gc_ptr(jit, cb, REG0, default_value);
                mov(cb, default_arg, REG0);

                caller_kwargs[kwarg_idx] = callee_kwarg;
                kwarg_idx += 1;
            }
        }

        assert!(kwarg_idx == total_kwargs);

        // Next, we're going to loop through every keyword that was
        // specified by the caller and make sure that it's in the correct
        // place. If it's not we're going to swap it around with another one.
        for kwarg_idx in 0..total_kwargs {
            let kwarg_idx_isize: isize = kwarg_idx.try_into().unwrap();
            let callee_kwarg = unsafe { *(callee_kwargs.offset(kwarg_idx_isize)) };

            // If the argument is already in the right order, then we don't
            // need to generate any code since the expected value is already
            // in the right place on the stack.
            if callee_kwarg == caller_kwargs[kwarg_idx] {
                continue;
            }

            // In this case the argument is not in the right place, so we
            // need to find its position where it _should_ be and swap with
            // that location.
            for swap_idx in (kwarg_idx + 1)..total_kwargs {
                if callee_kwarg == caller_kwargs[swap_idx] {
                    // First we're going to generate the code that is going
                    // to perform the actual swapping at runtime.
                    let swap_idx_i32: i32 = swap_idx.try_into().unwrap();
                    let kwarg_idx_i32: i32 = kwarg_idx.try_into().unwrap();
                    let offset0: u16 = (argc - 1 - swap_idx_i32 - args_before_kw)
                        .try_into()
                        .unwrap();
                    let offset1: u16 = (argc - 1 - kwarg_idx_i32 - args_before_kw)
                        .try_into()
                        .unwrap();
                    stack_swap(ctx, cb, offset0, offset1, REG1, REG0);

                    // Next we're going to do some bookkeeping on our end so
                    // that we know the order that the arguments are
                    // actually in now.
                    caller_kwargs.swap(kwarg_idx, swap_idx);

                    break;
                }
            }
        }

        // Keyword arguments cause a special extra local variable to be
        // pushed onto the stack that represents the parameters that weren't
        // explicitly given a value and have a non-constant default.
        let unspec_opnd = uimm_opnd(VALUE::fixnum_from_usize(unspecified_bits).as_u64());
        mov(cb, ctx.stack_opnd(-1), unspec_opnd);
    }

    // Points to the receiver operand on the stack
    let recv = ctx.stack_opnd(argc);

    // Store the updated SP on the current frame (pop arguments and receiver)
    add_comment(cb, "store caller sp");
    lea(
        cb,
        REG0,
        ctx.sp_opnd((SIZEOF_VALUE as isize) * -((argc as isize) + 1)),
    );
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SP), REG0);

    // Store the next PC in the current frame
    jit_save_pc(jit, cb, REG0);

    if let Some(block_val) = block {
        // Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
        // VM_CFP_TO_CAPTURED_BLCOK does &cfp->self, rb_captured_block->code.iseq aliases
        // with cfp->block_code.
        let gc_ptr = VALUE(block_val as usize);
        jit_mov_gc_ptr(jit, cb, REG0, gc_ptr);
        mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_BLOCK_CODE), REG0);
    }

    // Adjust the callee's stack pointer
    let offs =
        (SIZEOF_VALUE as isize) * (3 + (num_locals as isize) + if doing_kw_call { 1 } else { 0 });
    lea(cb, REG0, ctx.sp_opnd(offs));

    // Initialize local variables to Qnil
    for i in 0..num_locals {
        let offs = (SIZEOF_VALUE as i32) * (i - num_locals - 3);
        mov(cb, mem_opnd(64, REG0, offs), uimm_opnd(Qnil.into()));
    }

    add_comment(cb, "push env");
    // Put compile time cme into REG1. It's assumed to be valid because we are notified when
    // any cme we depend on become outdated. See yjit_method_lookup_change().
    jit_mov_gc_ptr(jit, cb, REG1, VALUE(cme as usize));
    // Write method entry at sp[-3]
    // sp[-3] = me;
    mov(cb, mem_opnd(64, REG0, 8 * -3), REG1);

    // Write block handler at sp[-2]
    // sp[-2] = block_handler;
    match block {
        Some(_) => {
            // reg1 = VM_BH_FROM_ISEQ_BLOCK(VM_CFP_TO_CAPTURED_BLOCK(reg_cfp));
            lea(cb, REG1, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SELF));
            or(cb, REG1, imm_opnd(1));
            mov(cb, mem_opnd(64, REG0, 8 * -2), REG1);
        }
        None => {
            mov(
                cb,
                mem_opnd(64, REG0, 8 * -2),
                uimm_opnd(VM_BLOCK_HANDLER_NONE.into()),
            );
        }
    }

    // Write env flags at sp[-1]
    // sp[-1] = frame_type;
    let frame_type = VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL;
    mov(cb, mem_opnd(64, REG0, 8 * -1), uimm_opnd(frame_type.into()));

    add_comment(cb, "push callee CFP");
    // Allocate a new CFP (ec->cfp--)
    sub(cb, REG_CFP, uimm_opnd(RUBY_SIZEOF_CONTROL_FRAME as u64));
    mov(cb, mem_opnd(64, REG_EC, RUBY_OFFSET_EC_CFP), REG_CFP);

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
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SELF), REG1);
    mov(cb, REG_SP, REG0); // Switch to the callee's REG_SP
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SP), REG0);
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_BP), REG0);
    sub(cb, REG0, uimm_opnd(SIZEOF_VALUE as u64));
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_EP), REG0);
    jit_mov_gc_ptr(jit, cb, REG0, VALUE(iseq as usize));
    mov(cb, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_ISEQ), REG0);
    mov(
        cb,
        mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_BLOCK_CODE),
        imm_opnd(0),
    );

    // No need to set cfp->pc since the callee sets it whenever calling into routines
    // that could look at it through jit_save_pc().
    // mov(cb, REG0, const_ptr_opnd(start_pc));
    // mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), REG0);

    // Stub so we can return to JITted code
    let return_block = BlockId {
        iseq: jit.iseq,
        idx: jit_next_insn_idx(jit),
    };

    // Create a context for the callee
    let mut callee_ctx = Context::new(); // Was DEFAULT_CTX

    // Set the argument types in the callee's context
    for arg_idx in 0..argc {
        let stack_offs: u16 = (argc - arg_idx - 1).try_into().unwrap();
        let arg_type = ctx.get_opnd_type(StackOpnd(stack_offs));
        callee_ctx.set_local_type(arg_idx.try_into().unwrap(), arg_type);
    }

    let recv_type = ctx.get_opnd_type(StackOpnd(argc.try_into().unwrap()));
    callee_ctx.upgrade_opnd_type(SelfOpnd, recv_type);

    // The callee might change locals through Kernel#binding and other means.
    ctx.clear_local_types();

    // Pop arguments and receiver in return context, push the return value
    // After the return, sp_offset will be 1. The codegen for leave writes
    // the return value in case of JIT-to-JIT return.
    let mut return_ctx = *ctx;
    return_ctx.stack_pop((argc + 1).try_into().unwrap());
    return_ctx.stack_push(Type::Unknown);
    return_ctx.set_sp_offset(1);
    return_ctx.reset_chain_depth();

    // Write the JIT return address on the callee frame
    gen_branch(
        jit,
        ctx,
        cb,
        ocb,
        return_block,
        &return_ctx,
        Some(return_block),
        Some(&return_ctx),
        gen_return_branch,
    );

    //print_str(cb, "calling Ruby func:");
    //print_str(cb, rb_id2name(vm_ci_mid(ci)));

    // Directly jump to the entry point of the callee
    gen_direct_jump(
        jit,
        &callee_ctx,
        BlockId {
            iseq: iseq,
            idx: start_pc_offset,
        },
        cb,
    );

    EndBlock
}

fn gen_struct_aref(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    comptime_recv: VALUE,
    _comptime_recv_klass: VALUE,
) -> CodegenStatus {
    if unsafe { vm_ci_argc(ci) } != 0 {
        return CantCompile;
    }

    let off: i32 = unsafe { get_cme_def_body_optimized_index(cme) }
        .try_into()
        .unwrap();

    // Confidence checks
    assert!(unsafe { RB_TYPE_P(comptime_recv, RUBY_T_STRUCT) });
    assert!((off as i64) < unsafe { RSTRUCT_LEN(comptime_recv) });

    // We are going to use an encoding that takes a 4-byte immediate which
    // limits the offset to INT32_MAX.
    {
        let native_off = (off as i64) * (SIZEOF_VALUE as i64);
        if native_off > (i32::MAX as i64) {
            return CantCompile;
        }
    }

    // All structs from the same Struct class should have the same
    // length. So if our comptime_recv is embedded all runtime
    // structs of the same class should be as well, and the same is
    // true of the converse.
    let embedded = unsafe { FL_TEST_RAW(comptime_recv, VALUE(RSTRUCT_EMBED_LEN_MASK)) };

    add_comment(cb, "struct aref");

    let recv = ctx.stack_pop(1);

    mov(cb, REG0, recv);

    if embedded != VALUE(0) {
        let ary_elt = mem_opnd(64, REG0, RUBY_OFFSET_RSTRUCT_AS_ARY + (8 * off));
        mov(cb, REG0, ary_elt);
    } else {
        let rstruct_ptr = mem_opnd(64, REG0, RUBY_OFFSET_RSTRUCT_AS_HEAP_PTR);
        mov(cb, REG0, rstruct_ptr);
        mov(cb, REG0, mem_opnd(64, REG0, (SIZEOF_VALUE as i32) * off));
    }

    let ret = ctx.stack_push(Type::Unknown);
    mov(cb, ret, REG0);

    jump_to_next_insn(jit, ctx, cb, ocb);
    EndBlock
}

fn gen_struct_aset(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    comptime_recv: VALUE,
    _comptime_recv_klass: VALUE,
) -> CodegenStatus {
    if unsafe { vm_ci_argc(ci) } != 1 {
        return CantCompile;
    }

    let off: i32 = unsafe { get_cme_def_body_optimized_index(cme) }
        .try_into()
        .unwrap();

    // Confidence checks
    assert!(unsafe { RB_TYPE_P(comptime_recv, RUBY_T_STRUCT) });
    assert!((off as i64) < unsafe { RSTRUCT_LEN(comptime_recv) });

    add_comment(cb, "struct aset");

    let val = ctx.stack_pop(1);
    let recv = ctx.stack_pop(1);

    mov(cb, C_ARG_REGS[0], recv);
    mov(cb, C_ARG_REGS[1], imm_opnd(off as i64));
    mov(cb, C_ARG_REGS[2], val);
    call_ptr(cb, REG0, RSTRUCT_SET as *const u8);

    let ret = ctx.stack_push(Type::Unknown);
    mov(cb, ret, RAX);

    jump_to_next_insn(jit, ctx, cb, ocb);
    EndBlock
}

fn gen_send_general(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    cd: *const rb_call_data,
    block: Option<IseqPtr>,
) -> CodegenStatus {
    // Relevant definitions:
    // rb_execution_context_t       : vm_core.h
    // invoker, cfunc logic         : method.h, vm_method.c
    // rb_callinfo                  : vm_callinfo.h
    // rb_callable_method_entry_t   : method.h
    // vm_call_cfunc_with_frame     : vm_insnhelper.c
    //
    // For a general overview for how the interpreter calls methods,
    // see vm_call_method().

    let ci = unsafe { get_call_data_ci(cd) }; // info about the call site
    let argc = unsafe { vm_ci_argc(ci) };
    let mid = unsafe { vm_ci_mid(ci) };
    let flags = unsafe { vm_ci_flag(ci) };

    // Don't JIT calls with keyword splat
    if flags & VM_CALL_KW_SPLAT != 0 {
        gen_counter_incr!(cb, send_kw_splat);
        return CantCompile;
    }

    // Don't JIT calls that aren't simple
    // Note, not using VM_CALL_ARGS_SIMPLE because sometimes we pass a block.
    if flags & VM_CALL_ARGS_SPLAT != 0 {
        gen_counter_incr!(cb, send_args_splat);
        return CantCompile;
    }
    if flags & VM_CALL_ARGS_BLOCKARG != 0 {
        gen_counter_incr!(cb, send_block_arg);
        return CantCompile;
    }

    // Defer compilation so we can specialize on class of receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let comptime_recv = jit_peek_at_stack(jit, ctx, argc as isize);
    let comptime_recv_klass = comptime_recv.class_of();

    // Guard that the receiver has the same class as the one from compile time
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Points to the receiver operand on the stack
    let recv = ctx.stack_opnd(argc);
    let recv_opnd = StackOpnd(argc.try_into().unwrap());
    mov(cb, REG0, recv);
    jit_guard_known_klass(
        jit,
        ctx,
        cb,
        ocb,
        comptime_recv_klass,
        recv_opnd,
        comptime_recv,
        SEND_MAX_DEPTH,
        side_exit,
    );

    // Do method lookup
    let mut cme = unsafe { rb_callable_method_entry(comptime_recv_klass, mid) };
    if cme.is_null() {
        // TODO: counter
        return CantCompile;
    }

    let visi = unsafe { METHOD_ENTRY_VISI(cme) };
    match visi {
        METHOD_VISI_PUBLIC => {
            // Can always call public methods
        }
        METHOD_VISI_PRIVATE => {
            if flags & VM_CALL_FCALL == 0 {
                // Can only call private methods with FCALL callsites.
                // (at the moment they are callsites without a receiver or an explicit `self` receiver)
                return CantCompile;
            }
        }
        METHOD_VISI_PROTECTED => {
            jit_protected_callee_ancestry_guard(jit, cb, ocb, cme, side_exit);
        }
        _ => {
            panic!("cmes should always have a visibility!");
        }
    }

    // Register block for invalidation
    //assert!(cme->called_id == mid);
    assume_method_lookup_stable(jit, ocb, comptime_recv_klass, cme);

    // To handle the aliased method case (VM_METHOD_TYPE_ALIAS)
    loop {
        let def_type = unsafe { get_cme_def_type(cme) };
        match def_type {
            VM_METHOD_TYPE_ISEQ => {
                return gen_send_iseq(jit, ctx, cb, ocb, ci, cme, block, argc);
            }
            VM_METHOD_TYPE_CFUNC => {
                return gen_send_cfunc(
                    jit,
                    ctx,
                    cb,
                    ocb,
                    ci,
                    cme,
                    block,
                    argc,
                    &comptime_recv_klass,
                );
            }
            VM_METHOD_TYPE_IVAR => {
                if argc != 0 {
                    // Argument count mismatch. Getters take no arguments.
                    gen_counter_incr!(cb, send_getter_arity);
                    return CantCompile;
                }

                if c_method_tracing_currently_enabled(jit) {
                    // Can't generate code for firing c_call and c_return events
                    // :attr-tracing:
                    // Handling the C method tracing events for attr_accessor
                    // methods is easier than regular C methods as we know the
                    // "method" we are calling into never enables those tracing
                    // events. Once global invalidation runs, the code for the
                    // attr_accessor is invalidated and we exit at the closest
                    // instruction boundary which is always outside of the body of
                    // the attr_accessor code.
                    gen_counter_incr!(cb, send_cfunc_tracing);
                    return CantCompile;
                }

                mov(cb, REG0, recv);
                let ivar_name = unsafe { get_cme_def_body_attr_id(cme) };

                return gen_get_ivar(
                    jit,
                    ctx,
                    cb,
                    ocb,
                    SEND_MAX_DEPTH,
                    comptime_recv,
                    ivar_name,
                    recv_opnd,
                    side_exit,
                );
            }
            VM_METHOD_TYPE_ATTRSET => {
                if flags & VM_CALL_KWARG != 0 {
                    gen_counter_incr!(cb, send_attrset_kwargs);
                    return CantCompile;
                } else if argc != 1 || unsafe { !RB_TYPE_P(comptime_recv, RUBY_T_OBJECT) } {
                    gen_counter_incr!(cb, send_ivar_set_method);
                    return CantCompile;
                } else if c_method_tracing_currently_enabled(jit) {
                    // Can't generate code for firing c_call and c_return events
                    // See :attr-tracing:
                    gen_counter_incr!(cb, send_cfunc_tracing);
                    return CantCompile;
                } else {
                    let ivar_name = unsafe { get_cme_def_body_attr_id(cme) };
                    return gen_set_ivar(jit, ctx, cb, comptime_recv, ivar_name);
                }
            }
            // Block method, e.g. define_method(:foo) { :my_block }
            VM_METHOD_TYPE_BMETHOD => {
                gen_counter_incr!(cb, send_bmethod);
                return CantCompile;
            }
            VM_METHOD_TYPE_ZSUPER => {
                gen_counter_incr!(cb, send_zsuper_method);
                return CantCompile;
            }
            VM_METHOD_TYPE_ALIAS => {
                // Retrieve the aliased method and re-enter the switch
                cme = unsafe { rb_aliased_callable_method_entry(cme) };
                continue;
            }
            VM_METHOD_TYPE_UNDEF => {
                gen_counter_incr!(cb, send_undef_method);
                return CantCompile;
            }
            VM_METHOD_TYPE_NOTIMPLEMENTED => {
                gen_counter_incr!(cb, send_not_implemented_method);
                return CantCompile;
            }
            // Send family of methods, e.g. call/apply
            VM_METHOD_TYPE_OPTIMIZED => {
                let opt_type = unsafe { get_cme_def_body_optimized_type(cme) };
                match opt_type {
                    OPTIMIZED_METHOD_TYPE_SEND => {
                        gen_counter_incr!(cb, send_optimized_method_send);
                        return CantCompile;
                    }
                    OPTIMIZED_METHOD_TYPE_CALL => {
                        gen_counter_incr!(cb, send_optimized_method_call);
                        return CantCompile;
                    }
                    OPTIMIZED_METHOD_TYPE_BLOCK_CALL => {
                        gen_counter_incr!(cb, send_optimized_method_block_call);
                        return CantCompile;
                    }
                    OPTIMIZED_METHOD_TYPE_STRUCT_AREF => {
                        return gen_struct_aref(
                            jit,
                            ctx,
                            cb,
                            ocb,
                            ci,
                            cme,
                            comptime_recv,
                            comptime_recv_klass,
                        );
                    }
                    OPTIMIZED_METHOD_TYPE_STRUCT_ASET => {
                        return gen_struct_aset(
                            jit,
                            ctx,
                            cb,
                            ocb,
                            ci,
                            cme,
                            comptime_recv,
                            comptime_recv_klass,
                        );
                    }
                    _ => {
                        panic!("unknown optimized method type!")
                    }
                }
            }
            VM_METHOD_TYPE_MISSING => {
                gen_counter_incr!(cb, send_missing_method);
                return CantCompile;
            }
            VM_METHOD_TYPE_REFINED => {
                gen_counter_incr!(cb, send_refined_method);
                return CantCompile;
            }
            _ => {
                unreachable!();
            }
        }
    }
}

fn gen_opt_send_without_block(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let cd = jit_get_arg(jit, 0).as_ptr();

    gen_send_general(jit, ctx, cb, ocb, cd, None)
}

fn gen_send(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let cd = jit_get_arg(jit, 0).as_ptr();
    let block = jit_get_arg(jit, 1).as_optional_ptr();
    return gen_send_general(jit, ctx, cb, ocb, cd, block);
}

fn gen_invokesuper(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let cd: *const rb_call_data = jit_get_arg(jit, 0).as_ptr();
    let block: Option<IseqPtr> = jit_get_arg(jit, 1).as_optional_ptr();

    // Defer compilation so we can specialize on class of receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let me = unsafe { rb_vm_frame_method_entry(get_ec_cfp(jit.ec.unwrap())) };
    if me.is_null() {
        return CantCompile;
    }

    // FIXME: We should track and invalidate this block when this cme is invalidated
    let current_defined_class = unsafe { (*me).defined_class };
    let mid = unsafe { get_def_original_id((*me).def) };

    if me != unsafe { rb_callable_method_entry(current_defined_class, (*me).called_id) } {
        // Though we likely could generate this call, as we are only concerned
        // with the method entry remaining valid, assume_method_lookup_stable
        // below requires that the method lookup matches as well
        return CantCompile;
    }

    // vm_search_normal_superclass
    let rbasic_ptr: *const RBasic = current_defined_class.as_ptr();
    if current_defined_class.builtin_type() == RUBY_T_ICLASS
        && unsafe { RB_TYPE_P((*rbasic_ptr).klass, RUBY_T_MODULE) && FL_TEST_RAW((*rbasic_ptr).klass, VALUE(RMODULE_IS_REFINEMENT.as_usize())) != VALUE(0) }
    {
        return CantCompile;
    }
    let comptime_superclass =
        unsafe { rb_class_get_superclass(RCLASS_ORIGIN(current_defined_class)) };

    let ci = unsafe { get_call_data_ci(cd) };
    let argc = unsafe { vm_ci_argc(ci) };

    let ci_flags = unsafe { vm_ci_flag(ci) };

    // Don't JIT calls that aren't simple
    // Note, not using VM_CALL_ARGS_SIMPLE because sometimes we pass a block.
    if ci_flags & VM_CALL_ARGS_SPLAT != 0 {
        gen_counter_incr!(cb, send_args_splat);
        return CantCompile;
    }
    if ci_flags & VM_CALL_KWARG != 0 {
        gen_counter_incr!(cb, send_keywords);
        return CantCompile;
    }
    if ci_flags & VM_CALL_KW_SPLAT != 0 {
        gen_counter_incr!(cb, send_kw_splat);
        return CantCompile;
    }
    if ci_flags & VM_CALL_ARGS_BLOCKARG != 0 {
        gen_counter_incr!(cb, send_block_arg);
        return CantCompile;
    }

    // Ensure we haven't rebound this method onto an incompatible class.
    // In the interpreter we try to avoid making this check by performing some
    // cheaper calculations first, but since we specialize on the method entry
    // and so only have to do this once at compile time this is fine to always
    // check and side exit.
    let comptime_recv = jit_peek_at_stack(jit, ctx, argc as isize);
    if unsafe { rb_obj_is_kind_of(comptime_recv, current_defined_class) } == VALUE(0) {
        return CantCompile;
    }

    // Do method lookup
    let cme = unsafe { rb_callable_method_entry(comptime_superclass, mid) };

    if cme.is_null() {
        return CantCompile;
    }

    // Check that we'll be able to write this method dispatch before generating checks
    let cme_def_type = unsafe { get_cme_def_type(cme) };
    if cme_def_type != VM_METHOD_TYPE_ISEQ && cme_def_type != VM_METHOD_TYPE_CFUNC {
        // others unimplemented
        return CantCompile;
    }

    // Guard that the receiver has the same class as the one from compile time
    let side_exit = get_side_exit(jit, ocb, ctx);

    let cfp = unsafe { get_ec_cfp(jit.ec.unwrap()) };
    let ep = unsafe { get_cfp_ep(cfp) };
    let cref_me = unsafe { *ep.offset(VM_ENV_DATA_INDEX_ME_CREF.try_into().unwrap()) };
    let me_as_value = VALUE(me as usize);
    if cref_me != me_as_value {
        // This will be the case for super within a block
        return CantCompile;
    }

    add_comment(cb, "guard known me");
    mov(cb, REG0, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_EP));
    let ep_me_opnd = mem_opnd(
        64,
        REG0,
        (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_ME_CREF as i32),
    );
    jit_mov_gc_ptr(jit, cb, REG1, me_as_value);
    cmp(cb, ep_me_opnd, REG1);
    jne_ptr(cb, counted_exit!(ocb, side_exit, invokesuper_me_changed));

    if block.is_none() {
        // Guard no block passed
        // rb_vm_frame_block_handler(GET_EC()->cfp) == VM_BLOCK_HANDLER_NONE
        // note, we assume VM_ASSERT(VM_ENV_LOCAL_P(ep))
        //
        // TODO: this could properly forward the current block handler, but
        // would require changes to gen_send_*
        add_comment(cb, "guard no block given");
        // EP is in REG0 from above
        let ep_specval_opnd = mem_opnd(
            64,
            REG0,
            (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32),
        );
        cmp(cb, ep_specval_opnd, uimm_opnd(VM_BLOCK_HANDLER_NONE.into()));
        jne_ptr(cb, counted_exit!(ocb, side_exit, invokesuper_block));
    }

    // Points to the receiver operand on the stack
    let recv = ctx.stack_opnd(argc);
    mov(cb, REG0, recv);

    // We need to assume that both our current method entry and the super
    // method entry we invoke remain stable
    assume_method_lookup_stable(jit, ocb, current_defined_class, me);
    assume_method_lookup_stable(jit, ocb, comptime_superclass, cme);

    // Method calls may corrupt types
    ctx.clear_local_types();

    match cme_def_type {
        VM_METHOD_TYPE_ISEQ => gen_send_iseq(jit, ctx, cb, ocb, ci, cme, block, argc),
        VM_METHOD_TYPE_CFUNC => {
            gen_send_cfunc(jit, ctx, cb, ocb, ci, cme, block, argc, ptr::null())
        }
        _ => unreachable!(),
    }
}

fn gen_leave(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Only the return value should be on the stack
    assert!(ctx.get_stack_size() == 1);

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Load environment pointer EP from CFP
    mov(cb, REG1, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_EP));

    // Check for interrupts
    add_comment(cb, "check for interrupts");
    gen_check_ints(cb, counted_exit!(ocb, side_exit, leave_se_interrupt));

    // Load the return value
    mov(cb, REG0, ctx.stack_pop(1));

    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    add_comment(cb, "pop stack frame");
    add(cb, REG_CFP, uimm_opnd(RUBY_SIZEOF_CONTROL_FRAME as u64));
    mov(cb, mem_opnd(64, REG_EC, RUBY_OFFSET_EC_CFP), REG_CFP);

    // Reload REG_SP for the caller and write the return value.
    // Top of the stack is REG_SP[0] since the caller has sp_offset=1.
    mov(cb, REG_SP, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SP));
    mov(cb, mem_opnd(64, REG_SP, 0), REG0);

    // Jump to the JIT return address on the frame that was just popped
    let offset_to_jit_return =
        -(RUBY_SIZEOF_CONTROL_FRAME as i32) + (RUBY_OFFSET_CFP_JIT_RETURN as i32);
    jmp_rm(cb, mem_opnd(64, REG_CFP, offset_to_jit_return));

    EndBlock
}

fn gen_getglobal(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let gid = jit_get_arg(jit, 0);

    // Save the PC and SP because we might make a Ruby call for warning
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    mov(cb, C_ARG_REGS[0], imm_opnd(gid.as_i64()));

    call_ptr(cb, REG0, rb_gvar_get as *const u8);

    let top = ctx.stack_push(Type::Unknown);
    mov(cb, top, RAX);

    KeepCompiling
}

fn gen_setglobal(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let gid = jit_get_arg(jit, 0);

    // Save the PC and SP because we might make a Ruby call for
    // Kernel#set_trace_var
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    mov(cb, C_ARG_REGS[0], imm_opnd(gid.as_i64()));

    let val = ctx.stack_pop(1);

    mov(cb, C_ARG_REGS[1], val);

    call_ptr(cb, REG0, rb_gvar_set as *const u8);

    KeepCompiling
}

fn gen_anytostring(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Save the PC and SP because we might make a Ruby call for
    // Kernel#set_trace_var
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    let str = ctx.stack_pop(1);
    let val = ctx.stack_pop(1);

    mov(cb, C_ARG_REGS[0], str);
    mov(cb, C_ARG_REGS[1], val);

    call_ptr(cb, REG0, rb_obj_as_string_result as *const u8);

    // Push the return value
    let stack_ret = ctx.stack_push(Type::String);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

fn gen_objtostring(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, cb, ocb);
        return EndBlock;
    }

    let recv = ctx.stack_opnd(0);
    let comptime_recv = jit_peek_at_stack(jit, ctx, 0);

    if unsafe { RB_TYPE_P(comptime_recv, RUBY_T_STRING) } {
        let side_exit = get_side_exit(jit, ocb, ctx);

        mov(cb, REG0, recv);
        jit_guard_known_klass(
            jit,
            ctx,
            cb,
            ocb,
            comptime_recv.class_of(),
            StackOpnd(0),
            comptime_recv,
            SEND_MAX_DEPTH,
            side_exit,
        );
        // No work needed. The string value is already on the top of the stack.
        KeepCompiling
    } else {
        let cd = jit_get_arg(jit, 0).as_ptr();
        gen_send_general(jit, ctx, cb, ocb, cd, None)
    }
}

fn gen_intern(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Save the PC and SP because we might allocate
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    let str = ctx.stack_pop(1);

    mov(cb, C_ARG_REGS[0], str);

    call_ptr(cb, REG0, rb_str_intern as *const u8);

    // Push the return value
    let stack_ret = ctx.stack_push(Type::Unknown);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

fn gen_toregexp(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let opt = jit_get_arg(jit, 0).as_i64();
    let cnt = jit_get_arg(jit, 1).as_usize();

    // Save the PC and SP because this allocates an object and could
    // raise an exception.
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    let values_ptr = ctx.sp_opnd(-((SIZEOF_VALUE as isize) * (cnt as isize)));
    ctx.stack_pop(cnt);

    mov(cb, C_ARG_REGS[0], imm_opnd(0));
    mov(cb, C_ARG_REGS[1], imm_opnd(cnt.try_into().unwrap()));
    lea(cb, C_ARG_REGS[2], values_ptr);
    call_ptr(cb, REG0, rb_ary_tmp_new_from_values as *const u8);

    // Save the array so we can clear it later
    push(cb, RAX);
    push(cb, RAX); // Alignment
    mov(cb, C_ARG_REGS[0], RAX);
    mov(cb, C_ARG_REGS[1], imm_opnd(opt));
    call_ptr(cb, REG0, rb_reg_new_ary as *const u8);

    // The actual regex is in RAX now.  Pop the temp array from
    // rb_ary_tmp_new_from_values into C arg regs so we can clear it
    pop(cb, REG1); // Alignment
    pop(cb, C_ARG_REGS[0]);

    // The value we want to push on the stack is in RAX right now
    let stack_ret = ctx.stack_push(Type::Unknown);
    mov(cb, stack_ret, RAX);

    // Clear the temp array.
    call_ptr(cb, REG0, rb_ary_clear as *const u8);

    KeepCompiling
}

fn gen_getspecial(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // This takes two arguments, key and type
    // key is only used when type == 0
    // A non-zero type determines which type of backref to fetch
    //rb_num_t key = jit_get_arg(jit, 0);
    let rtype = jit_get_arg(jit, 1).as_u64();

    if rtype == 0 {
        // not yet implemented
        return CantCompile;
    } else if rtype & 0x01 != 0 {
        // Fetch a "special" backref based on a char encoded by shifting by 1

        // Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, cb, REG0);

        // call rb_backref_get()
        add_comment(cb, "rb_backref_get");
        call_ptr(cb, REG0, rb_backref_get as *const u8);
        mov(cb, C_ARG_REGS[0], RAX);

        let rt_u8: u8 = (rtype >> 1).try_into().unwrap();
        match rt_u8.into() {
            '&' => {
                add_comment(cb, "rb_reg_last_match");
                call_ptr(cb, REG0, rb_reg_last_match as *const u8);
            }
            '`' => {
                add_comment(cb, "rb_reg_match_pre");
                call_ptr(cb, REG0, rb_reg_match_pre as *const u8);
            }
            '\'' => {
                add_comment(cb, "rb_reg_match_post");
                call_ptr(cb, REG0, rb_reg_match_post as *const u8);
            }
            '+' => {
                add_comment(cb, "rb_reg_match_last");
                call_ptr(cb, REG0, rb_reg_match_last as *const u8);
            }
            _ => panic!("invalid back-ref"),
        }

        let stack_ret = ctx.stack_push(Type::Unknown);
        mov(cb, stack_ret, RAX);

        KeepCompiling
    } else {
        // Fetch the N-th match from the last backref based on type shifted by 1

        // Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, cb, REG0);

        // call rb_backref_get()
        add_comment(cb, "rb_backref_get");
        call_ptr(cb, REG0, rb_backref_get as *const u8);

        // rb_reg_nth_match((int)(type >> 1), backref);
        add_comment(cb, "rb_reg_nth_match");
        mov(
            cb,
            C_ARG_REGS[0],
            imm_opnd((rtype >> 1).try_into().unwrap()),
        );
        mov(cb, C_ARG_REGS[1], RAX);
        call_ptr(cb, REG0, rb_reg_nth_match as *const u8);

        let stack_ret = ctx.stack_push(Type::Unknown);
        mov(cb, stack_ret, RAX);

        KeepCompiling
    }
}

fn gen_getclassvariable(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // rb_vm_getclassvariable can raise exceptions.
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    let cfp_iseq_opnd = mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_ISEQ);
    mov(cb, C_ARG_REGS[0], cfp_iseq_opnd);
    mov(cb, C_ARG_REGS[1], REG_CFP);
    mov(cb, C_ARG_REGS[2], uimm_opnd(jit_get_arg(jit, 0).as_u64()));
    mov(cb, C_ARG_REGS[3], uimm_opnd(jit_get_arg(jit, 1).as_u64()));

    call_ptr(cb, REG0, rb_vm_getclassvariable as *const u8);

    let stack_top = ctx.stack_push(Type::Unknown);
    mov(cb, stack_top, RAX);

    KeepCompiling
}

fn gen_setclassvariable(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // rb_vm_setclassvariable can raise exceptions.
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    let cfp_iseq_opnd = mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_ISEQ);
    mov(cb, C_ARG_REGS[0], cfp_iseq_opnd);
    mov(cb, C_ARG_REGS[1], REG_CFP);
    mov(cb, C_ARG_REGS[2], uimm_opnd(jit_get_arg(jit, 0).as_u64()));
    mov(cb, C_ARG_REGS[3], ctx.stack_pop(1));
    mov(cb, C_ARG_REGS[4], uimm_opnd(jit_get_arg(jit, 1).as_u64()));

    call_ptr(cb, REG0, rb_vm_setclassvariable as *const u8);

    KeepCompiling
}

fn gen_opt_getinlinecache(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0);
    let const_cache_as_value = jit_get_arg(jit, 1);
    let ic: *const iseq_inline_constant_cache = const_cache_as_value.as_ptr();

    // See vm_ic_hit_p(). The same conditions are checked in yjit_constant_ic_update().
    let ice = unsafe { (*ic).entry };
    if ice.is_null() {
        // In this case, leave a block that unconditionally side exits
        // for the interpreter to invalidate.
        return CantCompile;
    }

    // Make sure there is an exit for this block as the interpreter might want
    // to invalidate this block from yjit_constant_ic_update().
    jit_ensure_block_entry_exit(jit, ocb);

    if !unsafe { (*ice).ic_cref }.is_null() {
        // Cache is keyed on a certain lexical scope. Use the interpreter's cache.
        let side_exit = get_side_exit(jit, ocb, ctx);

        // Call function to verify the cache. It doesn't allocate or call methods.
        mov(cb, C_ARG_REGS[0], const_ptr_opnd(ic as *const u8));
        mov(cb, C_ARG_REGS[1], mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_EP));
        call_ptr(cb, REG0, rb_vm_ic_hit_p as *const u8);

        // Check the result. _Bool is one byte in SysV.
        test(cb, AL, AL);
        jz_ptr(cb, counted_exit!(ocb, side_exit, opt_getinlinecache_miss));

        // Push ic->entry->value
        mov(cb, REG0, const_ptr_opnd(ic as *mut u8));
        mov(cb, REG0, mem_opnd(64, REG0, RUBY_OFFSET_IC_ENTRY));
        let stack_top = ctx.stack_push(Type::Unknown);
        mov(cb, REG0, mem_opnd(64, REG0, RUBY_OFFSET_ICE_VALUE));
        mov(cb, stack_top, REG0);
    } else {
        // Optimize for single ractor mode.
        // FIXME: This leaks when st_insert raises NoMemoryError
        if !assume_single_ractor_mode(jit, ocb) {
            return CantCompile;
        }

        // Invalidate output code on any constant writes associated with
        // constants referenced within the current block.
        assume_stable_constant_names(jit, ocb);

        jit_putobject(jit, ctx, cb, unsafe { (*ice).value });
    }

    // Jump over the code for filling the cache
    let jump_idx = jit_next_insn_idx(jit) + jump_offset.as_u32();
    gen_direct_jump(
        jit,
        ctx,
        BlockId {
            iseq: jit.iseq,
            idx: jump_idx,
        },
        cb,
    );
    EndBlock
}

// Push the explicit block parameter onto the temporary stack. Part of the
// interpreter's scheme for avoiding Proc allocations when delegating
// explicit block parameters.
fn gen_getblockparamproxy(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // A mirror of the interpreter code. Checking for the case
    // where it's pushing rb_block_param_proxy.
    let side_exit = get_side_exit(jit, ocb, ctx);

    // EP level
    let level = jit_get_arg(jit, 1).as_u32();

    // Load environment pointer EP from CFP
    gen_get_ep(cb, REG0, level);

    // Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
    let flag_check = mem_opnd(
        64,
        REG0,
        (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_FLAGS as i32),
    );
    test(
        cb,
        flag_check,
        uimm_opnd(VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into()),
    );
    jnz_ptr(cb, counted_exit!(ocb, side_exit, gbpp_block_param_modified));

    // Load the block handler for the current frame
    // note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
    mov(
        cb,
        REG0,
        mem_opnd(
            64,
            REG0,
            (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32),
        ),
    );

    // Block handler is a tagged pointer. Look at the tag. 0x03 is from VM_BH_ISEQ_BLOCK_P().
    and(cb, REG0_8, imm_opnd(0x3));

    // Bail unless VM_BH_ISEQ_BLOCK_P(bh). This also checks for null.
    cmp(cb, REG0_8, imm_opnd(0x1));
    jnz_ptr(
        cb,
        counted_exit!(ocb, side_exit, gbpp_block_handler_not_iseq),
    );

    // Push rb_block_param_proxy. It's a root, so no need to use jit_mov_gc_ptr.
    mov(
        cb,
        REG0,
        const_ptr_opnd(unsafe { rb_block_param_proxy }.as_ptr()),
    );
    assert!(!unsafe { rb_block_param_proxy }.special_const_p());
    let top = ctx.stack_push(Type::UnknownHeap);
    mov(cb, top, REG0);

    KeepCompiling
}

fn gen_getblockparam(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // EP level
    let level = jit_get_arg(jit, 1).as_u32();

    // Save the PC and SP because we might allocate
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // A mirror of the interpreter code. Checking for the case
    // where it's pushing rb_block_param_proxy.
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Load environment pointer EP from CFP
    gen_get_ep(cb, REG1, level);

    // Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
    let flag_check = mem_opnd(
        64,
        REG1,
        (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_FLAGS as i32),
    );
    // FIXME: This is testing bits in the same place that the WB check is testing.
    // We should combine these at some point
    test(
        cb,
        flag_check,
        uimm_opnd(VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into()),
    );

    // If the frame flag has been modified, then the actual proc value is
    // already in the EP and we should just use the value.
    let frame_flag_modified = cb.new_label("frame_flag_modified".to_string());
    jnz_label(cb, frame_flag_modified);

    // This instruction writes the block handler to the EP.  If we need to
    // fire a write barrier for the write, then exit (we'll let the
    // interpreter handle it so it can fire the write barrier).
    // flags & VM_ENV_FLAG_WB_REQUIRED
    let flags_opnd = mem_opnd(
        64,
        REG1,
        SIZEOF_VALUE as i32 * VM_ENV_DATA_INDEX_FLAGS as i32,
    );
    test(cb, flags_opnd, imm_opnd(VM_ENV_FLAG_WB_REQUIRED.into()));

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    jnz_ptr(cb, side_exit);

    // Load the block handler for the current frame
    // note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
    mov(
        cb,
        C_ARG_REGS[1],
        mem_opnd(
            64,
            REG1,
            (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32),
        ),
    );

    // Convert the block handler in to a proc
    // call rb_vm_bh_to_procval(const rb_execution_context_t *ec, VALUE block_handler)
    mov(cb, C_ARG_REGS[0], REG_EC);
    call_ptr(cb, REG0, rb_vm_bh_to_procval as *const u8);

    // Load environment pointer EP from CFP (again)
    gen_get_ep(cb, REG1, level);

    // Set the frame modified flag
    or(cb, flag_check, uimm_opnd(VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into()));

    // Write the value at the environment pointer
    let idx = jit_get_arg(jit, 0).as_i32();
    let offs = -(SIZEOF_VALUE as i32 * idx);
    mov(cb, mem_opnd(64, REG1, offs), RAX);

    cb.write_label(frame_flag_modified);

    // Push the proc on the stack
    let stack_ret = ctx.stack_push(Type::Unknown);
    mov(cb, RAX, mem_opnd(64, REG1, offs));
    mov(cb, stack_ret, RAX);

    cb.link_labels();

    KeepCompiling
}

fn gen_invokebuiltin(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let bf: *const rb_builtin_function = jit_get_arg(jit, 0).as_ptr();
    let bf_argc: usize = unsafe { (*bf).argc }.try_into().expect("non negative argc");

    // ec, self, and arguments
    if bf_argc + 2 > C_ARG_REGS.len() {
        return CantCompile;
    }

    // If the calls don't allocate, do they need up to date PC, SP?
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    // Call the builtin func (ec, recv, arg1, arg2, ...)
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(
        cb,
        C_ARG_REGS[1],
        mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SELF),
    );

    // Copy arguments from locals
    for i in 0..bf_argc {
        let stack_opnd = ctx.stack_opnd((bf_argc - i - 1) as i32);
        let c_arg_reg = C_ARG_REGS[2 + i];
        mov(cb, c_arg_reg, stack_opnd);
    }

    call_ptr(cb, REG0, unsafe { (*bf).func_ptr } as *const u8);

    // Push the return value
    ctx.stack_pop(bf_argc);
    let stack_ret = ctx.stack_push(Type::Unknown);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

// opt_invokebuiltin_delegate calls a builtin function, like
// invokebuiltin does, but instead of taking arguments from the top of the
// stack uses the argument locals (and self) from the current method.
fn gen_opt_invokebuiltin_delegate(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let bf: *const rb_builtin_function = jit_get_arg(jit, 0).as_ptr();
    let bf_argc = unsafe { (*bf).argc };
    let start_index = jit_get_arg(jit, 1).as_i32();

    // ec, self, and arguments
    if bf_argc + 2 > (C_ARG_REGS.len() as i32) {
        return CantCompile;
    }

    // If the calls don't allocate, do they need up to date PC, SP?
    jit_prepare_routine_call(jit, ctx, cb, REG0);

    if bf_argc > 0 {
        // Load environment pointer EP from CFP
        mov(cb, REG0, mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_EP));
    }

    // Call the builtin func (ec, recv, arg1, arg2, ...)
    mov(cb, C_ARG_REGS[0], REG_EC);
    mov(
        cb,
        C_ARG_REGS[1],
        mem_opnd(64, REG_CFP, RUBY_OFFSET_CFP_SELF),
    );

    // Copy arguments from locals
    for i in 0..bf_argc {
        let table_size = unsafe { get_iseq_body_local_table_size(jit.iseq) };
        let offs: i32 = -(table_size as i32) - (VM_ENV_DATA_SIZE as i32) + 1 + start_index + i;
        let local_opnd = mem_opnd(64, REG0, offs * (SIZEOF_VALUE as i32));
        let offs: usize = (i + 2) as usize;
        let c_arg_reg = C_ARG_REGS[offs];
        mov(cb, c_arg_reg, local_opnd);
    }
    call_ptr(cb, REG0, unsafe { (*bf).func_ptr } as *const u8);

    // Push the return value
    let stack_ret = ctx.stack_push(Type::Unknown);
    mov(cb, stack_ret, RAX);

    KeepCompiling
}

/// Maps a YARV opcode to a code generation function (if supported)
fn get_gen_fn(opcode: VALUE) -> Option<InsnGenFn> {
    let VALUE(opcode) = opcode;
    let opcode = opcode as ruby_vminsn_type;
    assert!(opcode < VM_INSTRUCTION_SIZE);

    match opcode {
        YARVINSN_nop => Some(gen_nop),
        YARVINSN_pop => Some(gen_pop),
        YARVINSN_dup => Some(gen_dup),
        YARVINSN_dupn => Some(gen_dupn),
        YARVINSN_swap => Some(gen_swap),
        YARVINSN_putnil => Some(gen_putnil),
        YARVINSN_putobject => Some(gen_putobject),
        YARVINSN_putobject_INT2FIX_0_ => Some(gen_putobject_int2fix),
        YARVINSN_putobject_INT2FIX_1_ => Some(gen_putobject_int2fix),
        YARVINSN_putself => Some(gen_putself),
        YARVINSN_putspecialobject => Some(gen_putspecialobject),
        YARVINSN_setn => Some(gen_setn),
        YARVINSN_topn => Some(gen_topn),
        YARVINSN_adjuststack => Some(gen_adjuststack),
        YARVINSN_getlocal => Some(gen_getlocal),
        YARVINSN_getlocal_WC_0 => Some(gen_getlocal_wc0),
        YARVINSN_getlocal_WC_1 => Some(gen_getlocal_wc1),
        YARVINSN_setlocal => Some(gen_setlocal),
        YARVINSN_setlocal_WC_0 => Some(gen_setlocal_wc0),
        YARVINSN_setlocal_WC_1 => Some(gen_setlocal_wc1),
        YARVINSN_opt_plus => Some(gen_opt_plus),
        YARVINSN_opt_minus => Some(gen_opt_minus),
        YARVINSN_opt_and => Some(gen_opt_and),
        YARVINSN_opt_or => Some(gen_opt_or),
        YARVINSN_newhash => Some(gen_newhash),
        YARVINSN_duphash => Some(gen_duphash),
        YARVINSN_newarray => Some(gen_newarray),
        YARVINSN_duparray => Some(gen_duparray),
        YARVINSN_checktype => Some(gen_checktype),
        YARVINSN_opt_lt => Some(gen_opt_lt),
        YARVINSN_opt_le => Some(gen_opt_le),
        YARVINSN_opt_gt => Some(gen_opt_gt),
        YARVINSN_opt_ge => Some(gen_opt_ge),
        YARVINSN_opt_mod => Some(gen_opt_mod),
        YARVINSN_opt_str_freeze => Some(gen_opt_str_freeze),
        YARVINSN_opt_str_uminus => Some(gen_opt_str_uminus),
        YARVINSN_splatarray => Some(gen_splatarray),
        YARVINSN_newrange => Some(gen_newrange),
        YARVINSN_putstring => Some(gen_putstring),
        YARVINSN_expandarray => Some(gen_expandarray),
        YARVINSN_defined => Some(gen_defined),
        YARVINSN_checkkeyword => Some(gen_checkkeyword),
        YARVINSN_concatstrings => Some(gen_concatstrings),
        YARVINSN_getinstancevariable => Some(gen_getinstancevariable),
        YARVINSN_setinstancevariable => Some(gen_setinstancevariable),

        YARVINSN_opt_eq => Some(gen_opt_eq),
        YARVINSN_opt_neq => Some(gen_opt_neq),
        YARVINSN_opt_aref => Some(gen_opt_aref),
        YARVINSN_opt_aset => Some(gen_opt_aset),
        YARVINSN_opt_mult => Some(gen_opt_mult),
        YARVINSN_opt_div => Some(gen_opt_div),
        YARVINSN_opt_ltlt => Some(gen_opt_ltlt),
        YARVINSN_opt_nil_p => Some(gen_opt_nil_p),
        YARVINSN_opt_empty_p => Some(gen_opt_empty_p),
        YARVINSN_opt_succ => Some(gen_opt_succ),
        YARVINSN_opt_not => Some(gen_opt_not),
        YARVINSN_opt_size => Some(gen_opt_size),
        YARVINSN_opt_length => Some(gen_opt_length),
        YARVINSN_opt_regexpmatch2 => Some(gen_opt_regexpmatch2),
        YARVINSN_opt_getinlinecache => Some(gen_opt_getinlinecache),
        YARVINSN_invokebuiltin => Some(gen_invokebuiltin),
        YARVINSN_opt_invokebuiltin_delegate => Some(gen_opt_invokebuiltin_delegate),
        YARVINSN_opt_invokebuiltin_delegate_leave => Some(gen_opt_invokebuiltin_delegate),
        YARVINSN_opt_case_dispatch => Some(gen_opt_case_dispatch),
        YARVINSN_branchif => Some(gen_branchif),
        YARVINSN_branchunless => Some(gen_branchunless),
        YARVINSN_branchnil => Some(gen_branchnil),
        YARVINSN_jump => Some(gen_jump),

        YARVINSN_getblockparamproxy => Some(gen_getblockparamproxy),
        YARVINSN_getblockparam => Some(gen_getblockparam),
        YARVINSN_opt_send_without_block => Some(gen_opt_send_without_block),
        YARVINSN_send => Some(gen_send),
        YARVINSN_invokesuper => Some(gen_invokesuper),
        YARVINSN_leave => Some(gen_leave),

        YARVINSN_getglobal => Some(gen_getglobal),
        YARVINSN_setglobal => Some(gen_setglobal),
        YARVINSN_anytostring => Some(gen_anytostring),
        YARVINSN_objtostring => Some(gen_objtostring),
        YARVINSN_intern => Some(gen_intern),
        YARVINSN_toregexp => Some(gen_toregexp),
        YARVINSN_getspecial => Some(gen_getspecial),
        YARVINSN_getclassvariable => Some(gen_getclassvariable),
        YARVINSN_setclassvariable => Some(gen_setclassvariable),

        // Unimplemented opcode, YJIT won't generate code for this yet
        _ => None,
    }
}

// Return true when the codegen function generates code.
// known_recv_klass is non-NULL when the caller has used jit_guard_known_klass().
// See yjit_reg_method().
type MethodGenFn = fn(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    block: Option<IseqPtr>,
    argc: i32,
    known_recv_class: *const VALUE,
) -> bool;

/// Global state needed for code generation
pub struct CodegenGlobals {
    /// Inline code block (fast path)
    inline_cb: CodeBlock,

    /// Outlined code block (slow path)
    outlined_cb: OutlinedCb,

    /// Code for exiting back to the interpreter from the leave instruction
    leave_exit_code: CodePtr,

    // For exiting from YJIT frame from branch_stub_hit().
    // Filled by gen_code_for_exit_from_stub().
    stub_exit_code: CodePtr,

    // Code for full logic of returning from C method and exiting to the interpreter
    outline_full_cfunc_return_pos: CodePtr,

    /// For implementing global code invalidation
    global_inval_patches: Vec<CodepagePatch>,

    /// For implementing global code invalidation. The number of bytes counting from the beginning
    /// of the inline code block that should not be changed. After patching for global invalidation,
    /// no one should make changes to the invalidated code region anymore. This is used to
    /// break out of invalidation race when there are multiple ractors.
    inline_frozen_bytes: usize,

    // Methods for generating code for hardcoded (usually C) methods
    method_codegen_table: HashMap<u64, MethodGenFn>,
}

/// For implementing global code invalidation. A position in the inline
/// codeblock to patch into a JMP rel32 which jumps into some code in
/// the outlined codeblock to exit to the interpreter.
pub struct CodepagePatch {
    pub inline_patch_pos: CodePtr,
    pub outlined_target_pos: CodePtr,
}

/// Private singleton instance of the codegen globals
static mut CODEGEN_GLOBALS: Option<CodegenGlobals> = None;

impl CodegenGlobals {
    /// Initialize the codegen globals
    pub fn init() {
        // Executable memory size in MiB
        let mem_size = get_option!(exec_mem_size) * 1024 * 1024;

        #[cfg(not(test))]
        let (mut cb, mut ocb) = {
            // TODO(alan): we can error more gracefully when the user gives
            //   --yjit-exec-mem=absurdly-large-number
            //
            // 2 GiB. It's likely a bug if we generate this much code.
            const MAX_BUFFER_SIZE: usize = 2 * 1024 * 1024 * 1024;
            assert!(mem_size <= MAX_BUFFER_SIZE);
            let mem_size_u32 = mem_size as u32;
            let half_size = mem_size / 2;

            let page_size = unsafe { rb_yjit_get_page_size() };
            let assert_page_aligned = |ptr| assert_eq!(
                0,
                ptr as usize % page_size.as_usize(),
                "Start of virtual address block should be page-aligned",
            );

            let virt_block: *mut u8 = unsafe { rb_yjit_reserve_addr_space(mem_size_u32) };
            let second_half = virt_block.wrapping_add(half_size);

            // Memory protection syscalls need page-aligned addresses, so check it here. Assuming
            // `virt_block` is page-aligned, `second_half` should be page-aligned as long as the
            // page size in bytes is a power of two 2¹⁹ or smaller. This is because the user
            // requested size is half of mem_option × 2²⁰ as it's in MiB.
            //
            // Basically, we don't support x86-64 2MiB and 1GiB pages. ARMv8 can do up to 64KiB
            // (2¹⁶ bytes) pages, which should be fine. 4KiB pages seem to be the most popular though.
            assert_page_aligned(virt_block);
            assert_page_aligned(second_half);

            use crate::virtualmem::*;

            let first_half = VirtualMem::new(
                SystemAllocator {},
                page_size,
                virt_block,
                half_size
            );
            let second_half = VirtualMem::new(
                SystemAllocator {},
                page_size,
                second_half,
                half_size
            );

            let cb = CodeBlock::new(first_half);
            let ocb = OutlinedCb::wrap(CodeBlock::new(second_half));

            (cb, ocb)
        };

        // In test mode we're not linking with the C code
        // so we don't allocate executable memory
        #[cfg(test)]
        let mut cb = CodeBlock::new_dummy(mem_size / 2);
        #[cfg(test)]
        let mut ocb = OutlinedCb::wrap(CodeBlock::new_dummy(mem_size / 2));

        let leave_exit_code = gen_leave_exit(&mut ocb);

        let stub_exit_code = gen_code_for_exit_from_stub(&mut ocb);

        // Generate full exit code for C func
        let cfunc_exit_code = gen_full_cfunc_return(&mut ocb);

        // Mark all code memory as executable
        cb.mark_all_executable();
        ocb.unwrap().mark_all_executable();

        let mut codegen_globals = CodegenGlobals {
            inline_cb: cb,
            outlined_cb: ocb,
            leave_exit_code: leave_exit_code,
            stub_exit_code: stub_exit_code,
            outline_full_cfunc_return_pos: cfunc_exit_code,
            global_inval_patches: Vec::new(),
            inline_frozen_bytes: 0,
            method_codegen_table: HashMap::new(),
        };

        // Register the method codegen functions
        codegen_globals.reg_method_codegen_fns();

        // Initialize the codegen globals instance
        unsafe {
            CODEGEN_GLOBALS = Some(codegen_globals);
        }
    }

    // Register a specialized codegen function for a particular method. Note that
    // the if the function returns true, the code it generates runs without a
    // control frame and without interrupt checks. To avoid creating observable
    // behavior changes, the codegen function should only target simple code paths
    // that do not allocate and do not make method calls.
    fn yjit_reg_method(&mut self, klass: VALUE, mid_str: &str, gen_fn: MethodGenFn) {
        let id_string = std::ffi::CString::new(mid_str).expect("couldn't convert to CString!");
        let mid = unsafe { rb_intern(id_string.as_ptr()) };
        let me = unsafe { rb_method_entry_at(klass, mid) };

        if me.is_null() {
            panic!("undefined optimized method!");
        }

        // For now, only cfuncs are supported
        //RUBY_ASSERT(me && me->def);
        //RUBY_ASSERT(me->def->type == VM_METHOD_TYPE_CFUNC);

        let method_serial = unsafe {
            let def = (*me).def;
            get_def_method_serial(def)
        };

        self.method_codegen_table.insert(method_serial, gen_fn);
    }

    /// Register codegen functions for some Ruby core methods
    fn reg_method_codegen_fns(&mut self) {
        unsafe {
            // Specialization for C methods. See yjit_reg_method() for details.
            self.yjit_reg_method(rb_cBasicObject, "!", jit_rb_obj_not);

            self.yjit_reg_method(rb_cNilClass, "nil?", jit_rb_true);
            self.yjit_reg_method(rb_mKernel, "nil?", jit_rb_false);

            self.yjit_reg_method(rb_cBasicObject, "==", jit_rb_obj_equal);
            self.yjit_reg_method(rb_cBasicObject, "equal?", jit_rb_obj_equal);
            self.yjit_reg_method(rb_mKernel, "eql?", jit_rb_obj_equal);
            self.yjit_reg_method(rb_cModule, "==", jit_rb_obj_equal);
            self.yjit_reg_method(rb_cSymbol, "==", jit_rb_obj_equal);
            self.yjit_reg_method(rb_cSymbol, "===", jit_rb_obj_equal);

            // rb_str_to_s() methods in string.c
            self.yjit_reg_method(rb_cString, "to_s", jit_rb_str_to_s);
            self.yjit_reg_method(rb_cString, "to_str", jit_rb_str_to_s);
            self.yjit_reg_method(rb_cString, "bytesize", jit_rb_str_bytesize);
            self.yjit_reg_method(rb_cString, "<<", jit_rb_str_concat);
            self.yjit_reg_method(rb_cString, "+@", jit_rb_str_uplus);

            // Thread.current
            self.yjit_reg_method(
                rb_singleton_class(rb_cThread),
                "current",
                jit_thread_s_current,
            );
        }
    }

    /// Get a mutable reference to the codegen globals instance
    pub fn get_instance() -> &'static mut CodegenGlobals {
        unsafe { CODEGEN_GLOBALS.as_mut().unwrap() }
    }

    /// Get a mutable reference to the inline code block
    pub fn get_inline_cb() -> &'static mut CodeBlock {
        &mut CodegenGlobals::get_instance().inline_cb
    }

    /// Get a mutable reference to the outlined code block
    pub fn get_outlined_cb() -> &'static mut OutlinedCb {
        &mut CodegenGlobals::get_instance().outlined_cb
    }

    pub fn get_leave_exit_code() -> CodePtr {
        CodegenGlobals::get_instance().leave_exit_code
    }

    pub fn get_stub_exit_code() -> CodePtr {
        CodegenGlobals::get_instance().stub_exit_code
    }

    pub fn push_global_inval_patch(i_pos: CodePtr, o_pos: CodePtr) {
        let patch = CodepagePatch {
            inline_patch_pos: i_pos,
            outlined_target_pos: o_pos,
        };
        CodegenGlobals::get_instance()
            .global_inval_patches
            .push(patch);
    }

    // Drain the list of patches and return it
    pub fn take_global_inval_patches() -> Vec<CodepagePatch> {
        let globals = CodegenGlobals::get_instance();
        mem::take(&mut globals.global_inval_patches)
    }

    pub fn get_inline_frozen_bytes() -> usize {
        CodegenGlobals::get_instance().inline_frozen_bytes
    }

    pub fn set_inline_frozen_bytes(frozen_bytes: usize) {
        CodegenGlobals::get_instance().inline_frozen_bytes = frozen_bytes;
    }

    pub fn get_outline_full_cfunc_return_pos() -> CodePtr {
        CodegenGlobals::get_instance().outline_full_cfunc_return_pos
    }

    pub fn look_up_codegen_method(method_serial: u64) -> Option<MethodGenFn> {
        let table = &CodegenGlobals::get_instance().method_codegen_table;

        let option_ref = table.get(&method_serial);
        match option_ref {
            None => None,
            Some(&mgf) => Some(mgf), // Deref
        }
    }
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
    fn test_gen_leave_exit() {
        let mut ocb = OutlinedCb::wrap(CodeBlock::new_dummy(256 * 1024));
        gen_leave_exit(&mut ocb);
        assert!(ocb.unwrap().get_write_pos() > 0);
    }

    #[test]
    fn test_gen_exit() {
        let (_, ctx, mut cb, _) = setup_codegen();
        gen_exit(0 as *mut VALUE, &ctx, &mut cb);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_get_side_exit() {
        let (mut jit, ctx, _, mut ocb) = setup_codegen();
        get_side_exit(&mut jit, &mut ocb, &ctx);
        assert!(ocb.unwrap().get_write_pos() > 0);
    }

    #[test]
    fn test_gen_check_ints() {
        let (_, _ctx, mut cb, mut ocb) = setup_codegen();
        let side_exit = ocb.unwrap().get_write_ptr();
        gen_check_ints(&mut cb, side_exit);
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
    fn test_gen_pop() {
        let (mut jit, _, mut cb, mut ocb) = setup_codegen();
        let mut context = Context::new_with_stack_size(1);
        let status = gen_pop(&mut jit, &mut context, &mut cb, &mut ocb);

        assert_eq!(status, KeepCompiling);
        assert_eq!(context.diff(&Context::new()), 0);
    }

    #[test]
    fn test_gen_dup() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Fixnum);
        let status = gen_dup(&mut jit, &mut context, &mut cb, &mut ocb);

        assert_eq!(status, KeepCompiling);

        // Did we duplicate the type information for the Fixnum type?
        assert_eq!(Type::Fixnum, context.get_opnd_type(StackOpnd(0)));
        assert_eq!(Type::Fixnum, context.get_opnd_type(StackOpnd(1)));

        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_dupn() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Fixnum);
        context.stack_push(Type::Flonum);

        let mut value_array: [u64; 2] = [0, 2]; // We only compile for n == 2
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_dupn(&mut jit, &mut context, &mut cb, &mut ocb);

        assert_eq!(status, KeepCompiling);

        assert_eq!(Type::Fixnum, context.get_opnd_type(StackOpnd(3)));
        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::Fixnum, context.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(0)));

        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_swap() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Fixnum);
        context.stack_push(Type::Flonum);

        let status = gen_swap(&mut jit, &mut context, &mut cb, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));
        let (_, tmp_type_next) = context.get_opnd_mapping(StackOpnd(1));

        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::Fixnum);
        assert_eq!(tmp_type_next, Type::Flonum);
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

    #[test]
    fn test_putobject_qtrue() {
        // Test gen_putobject with Qtrue
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();

        let mut value_array: [u64; 2] = [0, Qtrue.into()];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_putobject(&mut jit, &mut context, &mut cb, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));

        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::True);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_putobject_fixnum() {
        // Test gen_putobject with a Fixnum to test another conditional branch
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();

        // The Fixnum 7 is encoded as 7 * 2 + 1, or 15
        let mut value_array: [u64; 2] = [0, 15];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_putobject(&mut jit, &mut context, &mut cb, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));

        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::Fixnum);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_int2fix() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        jit.opcode = YARVINSN_putobject_INT2FIX_0_.as_usize();
        let status = gen_putobject_int2fix(&mut jit, &mut context, &mut cb, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));

        // Right now we're not testing the generated machine code to make sure a literal 1 or 0 was pushed. I've checked locally.
        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::Fixnum);
    }

    #[test]
    fn test_putself() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        let status = gen_putself(&mut jit, &mut context, &mut cb, &mut ocb);

        assert_eq!(status, KeepCompiling);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_gen_setn() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Fixnum);
        context.stack_push(Type::Flonum);
        context.stack_push(Type::String);

        let mut value_array: [u64; 2] = [0, 2];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_setn(&mut jit, &mut context, &mut cb, &mut ocb);

        assert_eq!(status, KeepCompiling);

        assert_eq!(Type::String, context.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::String, context.get_opnd_type(StackOpnd(0)));

        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_gen_topn() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Flonum);
        context.stack_push(Type::String);

        let mut value_array: [u64; 2] = [0, 1];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_topn(&mut jit, &mut context, &mut cb, &mut ocb);

        assert_eq!(status, KeepCompiling);

        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::String, context.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(0)));

        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_adjuststack() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Flonum);
        context.stack_push(Type::String);
        context.stack_push(Type::Fixnum);

        let mut value_array: [u64; 3] = [0, 2, 0];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_adjuststack(&mut jit, &mut context, &mut cb, &mut ocb);

        assert_eq!(status, KeepCompiling);

        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(0)));

        assert!(cb.get_write_pos() == 0); // No instructions written
    }

    #[test]
    fn test_gen_leave() {
        let (mut jit, mut context, mut cb, mut ocb) = setup_codegen();
        // Push return value
        context.stack_push(Type::Fixnum);
        gen_leave(&mut jit, &mut context, &mut cb, &mut ocb);
    }
}
