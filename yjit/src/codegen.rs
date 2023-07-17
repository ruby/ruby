// We use the YARV bytecode constants which have a CRuby-style name
#![allow(non_upper_case_globals)]

use crate::asm::*;
use crate::backend::ir::*;
use crate::core::*;
use crate::cruby::*;
use crate::invariants::*;
use crate::options::*;
use crate::stats::*;
use crate::utils::*;
use CodegenStatus::*;
use YARVOpnd::*;

use std::cmp;
use std::collections::HashMap;
use std::ffi::CStr;
use std::mem::{self, size_of};
use std::os::raw::{c_int, c_uint};
use std::ptr;
use std::slice;

pub use crate::virtualmem::CodePtr;

/// Status returned by code generation functions
#[derive(PartialEq, Debug)]
enum CodegenStatus {
    KeepCompiling,
    CantCompile,
    EndBlock,
}

/// Code generation function signature
type InsnGenFn = fn(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
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

fn jit_peek_at_block_handler(jit: &JITState, level: u32) -> VALUE {
    assert!(jit_at_current_insn(jit));

    unsafe {
        let ep = get_cfp_ep_level(get_ec_cfp(jit.ec.unwrap()), level);
        *ep.offset(VM_ENV_DATA_INDEX_SPECVAL as isize)
    }
}

macro_rules! gen_counter_incr {
    ($asm:tt, $counter_name:ident) => {
        if (get_option!(gen_stats)) {
            // Get a pointer to the counter variable
            let ptr = ptr_to_counter!($counter_name);

            // Load the pointer into a register
            $asm.comment(&format!("increment counter {}", stringify!($counter_name)));
            let ptr_reg = $asm.load(Opnd::const_ptr(ptr as *const u8));
            let counter_opnd = Opnd::mem(64, ptr_reg, 0);

            // Increment and store the updated value
            $asm.incr_counter(counter_opnd, Opnd::UImm(1));
        }
    };
}

macro_rules! counted_exit {
    ($ocb:tt, $existing_side_exit:tt, $counter_name:ident) => {
        // The counter is only incremented when stats are enabled
        if (!get_option!(gen_stats)) {
            $existing_side_exit
        } else {
            let ocb = $ocb.unwrap();
            let code_ptr = ocb.get_write_ptr();

            let mut ocb_asm = Assembler::new();

            // Increment the counter
            gen_counter_incr!(ocb_asm, $counter_name);

            // Jump to the existing side exit
            ocb_asm.jmp($existing_side_exit.as_side_exit());
            ocb_asm.compile(ocb);

            // Pointer to the side-exit code
            code_ptr
        }
    };
}

// Save the incremented PC on the CFP
// This is necessary when callees can raise or allocate
fn jit_save_pc(jit: &JITState, asm: &mut Assembler) {
    let pc: *mut VALUE = jit.get_pc();
    let ptr: *mut VALUE = unsafe {
        let cur_insn_len = insn_len(jit.get_opcode()) as isize;
        pc.offset(cur_insn_len)
    };

    asm.comment("save PC to CFP");
    asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), Opnd::const_ptr(ptr as *const u8));
}

/// Save the current SP on the CFP
/// This realigns the interpreter SP with the JIT SP
/// Note: this will change the current value of REG_SP,
///       which could invalidate memory operands
fn gen_save_sp(_jit: &JITState, asm: &mut Assembler, ctx: &mut Context) {
    if ctx.get_sp_offset() != 0 {
        asm.comment("save SP to CFP");
        let stack_pointer = ctx.sp_opnd(0);
        let sp_addr = asm.lea(stack_pointer);
        asm.mov(SP, sp_addr);
        let cfp_sp_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP);
        asm.mov(cfp_sp_opnd, SP);
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
    asm: &mut Assembler
) {
    jit.record_boundary_patch_point = true;
    jit_save_pc(jit, asm);
    gen_save_sp(jit, asm, ctx);

    // In case the routine calls Ruby methods, it can set local variables
    // through Kernel#binding and other means.
    ctx.clear_local_types();
}

/// Record the current codeblock write position for rewriting into a jump into
/// the outlined block later. Used to implement global code invalidation.
fn record_global_inval_patch(asm: &mut Assembler, outline_block_target_pos: CodePtr) {
    asm.pad_inval_patch();
    asm.pos_marker(move |code_ptr| {
        CodegenGlobals::push_global_inval_patch(code_ptr, outline_block_target_pos);
    });
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

// Fill code_for_exit_from_stub. This is used by branch_stub_hit() to exit
// to the interpreter when it cannot service a stub by generating new code.
// Before coming here, branch_stub_hit() takes care of fully reconstructing
// interpreter state.
fn gen_code_for_exit_from_stub(ocb: &mut OutlinedCb) -> CodePtr {
    let ocb = ocb.unwrap();
    let code_ptr = ocb.get_write_ptr();
    let mut asm = Assembler::new();

    gen_counter_incr!(asm, exit_from_branch_stub);

    asm.comment("exit from branch stub");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(Qundef.into());

    asm.compile(ocb);

    code_ptr
}

/// Generate an exit to return to the interpreter
fn gen_exit(exit_pc: *mut VALUE, ctx: &Context, asm: &mut Assembler) {
    asm.comment("exit to interpreter");

    // Generate the code to exit to the interpreters
    // Write the adjusted SP back into the CFP
    if ctx.get_sp_offset() != 0 {
        let sp_opnd = asm.lea(ctx.sp_opnd(0));
        asm.mov(
            Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP),
            sp_opnd
        );
    }

    // Update CFP->PC
    asm.mov(
        Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC),
        Opnd::const_ptr(exit_pc as *const u8)
    );

    // Accumulate stats about interpreter exits
    if get_option!(gen_stats) {
        asm.ccall(
            rb_yjit_count_side_exit_op as *const u8,
            vec![Opnd::const_ptr(exit_pc as *const u8)]
        );

        // If --yjit-trace-exits option is enabled, record the exit stack
        // while recording the side exits.
        if get_option!(gen_trace_exits) {
            asm.ccall(
                rb_yjit_record_exit_stack as *const u8,
                vec![Opnd::const_ptr(exit_pc as *const u8)]
            );
        }
    }

    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(Qundef.into());
}

/// Generate an exit to the interpreter in the outlined code block
fn gen_outlined_exit(exit_pc: *mut VALUE, ctx: &Context, ocb: &mut OutlinedCb) -> CodePtr {
    let mut cb = ocb.unwrap();
    let exit_code = cb.get_write_ptr();
    let mut asm = Assembler::new();

    gen_exit(exit_pc, ctx, &mut asm);

    asm.compile(&mut cb);

    exit_code
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
// it's incorrect to jump to the side exit after any ctx stack push operations
// since they change the logic required for reconstructing interpreter state.
fn get_side_exit(jit: &mut JITState, ocb: &mut OutlinedCb, ctx: &Context) -> CodePtr {
    match jit.side_exit_for_pc {
        None => {
            let exit_code = gen_outlined_exit(jit.pc, ctx, ocb);
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

    // If we're compiling the first instruction in the block.
    if jit.insn_idx == blockid.idx {
        // Generate the exit with the cache in jitstate.
        block.entry_exit = Some(get_side_exit(jit, ocb, &block_ctx));
    } else {
        let block_entry_pc = unsafe { rb_iseq_pc_at_idx(blockid.iseq, blockid.idx) };
        block.entry_exit = Some(gen_outlined_exit(block_entry_pc, &block_ctx, ocb));
    }
}

// Landing code for when c_return tracing is enabled. See full_cfunc_return().
fn gen_full_cfunc_return(ocb: &mut OutlinedCb) -> CodePtr {
    let ocb = ocb.unwrap();
    let code_ptr = ocb.get_write_ptr();
    let mut asm = Assembler::new();

    // This chunk of code expects REG_EC to be filled properly and
    // RAX to contain the return value of the C method.

    asm.comment("full cfunc return");
    asm.ccall(
        rb_full_cfunc_return as *const u8,
        vec![EC, C_RET_OPND]
    );

    // Count the exit
    gen_counter_incr!(asm, traced_cfunc_return);

    // Return to the interpreter
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(Qundef.into());

    asm.compile(ocb);

    return code_ptr;
}

/// Generate a continuation for leave that exits to the interpreter at REG_CFP->pc.
/// This is used by gen_leave() and gen_entry_prologue()
fn gen_leave_exit(ocb: &mut OutlinedCb) -> CodePtr {
    let ocb = ocb.unwrap();
    let code_ptr = ocb.get_write_ptr();
    let mut asm = Assembler::new();

    // gen_leave() fully reconstructs interpreter state and leaves the
    // return value in C_RET_OPND before coming here.
    let ret_opnd = asm.live_reg_opnd(C_RET_OPND);

    // Every exit to the interpreter should be counted
    gen_counter_incr!(asm, leave_interp_return);

    asm.comment("exit from leave");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(ret_opnd);

    asm.compile(ocb);

    return code_ptr;
}

// Generate a runtime guard that ensures the PC is at the expected
// instruction index in the iseq, otherwise takes a side-exit.
// This is to handle the situation of optional parameters.
// When a function with optional parameters is called, the entry
// PC for the method isn't necessarily 0.
fn gen_pc_guard(asm: &mut Assembler, iseq: IseqPtr, insn_idx: u32) {
    let pc_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC);
    let expected_pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
    let expected_pc_opnd = Opnd::const_ptr(expected_pc as *const u8);

    asm.cmp(pc_opnd, expected_pc_opnd);

    let pc_match = asm.new_label("pc_match");
    asm.je(pc_match);

    // We're not starting at the first PC, so we need to exit.
    gen_counter_incr!(asm, leave_start_pc_non_zero);

    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(Qundef.into());

    // PC should match the expected insn_idx
    asm.write_label(pc_match);
}

/// Compile an interpreter entry block to be inserted into an iseq
/// Returns None if compilation fails.
pub fn gen_entry_prologue(cb: &mut CodeBlock, iseq: IseqPtr, insn_idx: u32) -> Option<CodePtr> {
    let code_ptr = cb.get_write_ptr();

    let mut asm = Assembler::new();
    if get_option_ref!(dump_disasm).is_some() {
        asm.comment(&format!("YJIT entry: {}", iseq_get_location(iseq)));
    } else {
        asm.comment("YJIT entry");
    }

    asm.frame_setup();

    // Save the CFP, EC, SP registers to the C stack
    asm.cpush(CFP);
    asm.cpush(EC);
    asm.cpush(SP);

    // We are passed EC and CFP as arguments
    asm.mov(EC, C_ARG_OPNDS[0]);
    asm.mov(CFP, C_ARG_OPNDS[1]);

    // Load the current SP from the CFP into REG_SP
    asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));

    // Setup cfp->jit_return
    asm.mov(
        Opnd::mem(64, CFP, RUBY_OFFSET_CFP_JIT_RETURN),
        Opnd::const_ptr(CodegenGlobals::get_leave_exit_code().raw_ptr()),
    );

    // We're compiling iseqs that we *expect* to start at `insn_idx`. But in
    // the case of optional parameters, the interpreter can set the pc to a
    // different location depending on the optional parameters.  If an iseq
    // has optional parameters, we'll add a runtime check that the PC we've
    // compiled for is the same PC that the interpreter wants us to run with.
    // If they don't match, then we'll take a side exit.
    if unsafe { get_iseq_flags_has_opt(iseq) } {
        gen_pc_guard(&mut asm, iseq, insn_idx);
    }

    asm.compile(cb);

    if cb.has_dropped_bytes() {
        None
    } else {
        // Mark code pages for code GC
        let iseq_payload = get_or_create_iseq_payload(iseq);
        for page in cb.addrs_to_pages(code_ptr, cb.get_write_ptr()) {
            iseq_payload.pages.insert(page);
        }
        Some(code_ptr)
    }
}

// Generate code to check for interrupts and take a side-exit.
// Warning: this function clobbers REG0
fn gen_check_ints(asm: &mut Assembler, side_exit: CodePtr) {
    // Check for interrupts
    // see RUBY_VM_CHECK_INTS(ec) macro
    asm.comment("RUBY_VM_CHECK_INTS(ec)");

    // Not checking interrupt_mask since it's zero outside finalize_deferred_heap_pages,
    // signal_exec, or rb_postponed_job_flush.
    let interrupt_flag = asm.load(Opnd::mem(32, EC, RUBY_OFFSET_EC_INTERRUPT_FLAG));
    asm.test(interrupt_flag, interrupt_flag);

    asm.jnz(Target::SideExitPtr(side_exit));
}

// Generate a stubbed unconditional jump to the next bytecode instruction.
// Blocks that are part of a guard chain can use this to share the same successor.
fn jump_to_next_insn(
    jit: &mut JITState,
    current_context: &Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) {
    // Reset the depth since in current usages we only ever jump to to
    // chain_depth > 0 from the same instruction.
    let mut reset_depth = current_context.clone();
    reset_depth.reset_chain_depth();

    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jit_next_insn_idx(jit),
    };

    // We are at the end of the current instruction. Record the boundary.
    if jit.record_boundary_patch_point {
        let exit_pc = unsafe { jit.pc.offset(insn_len(jit.opcode).try_into().unwrap()) };
        let exit_pos = gen_outlined_exit(exit_pc, &reset_depth, ocb);
        record_global_inval_patch(asm, exit_pos);
        jit.record_boundary_patch_point = false;
    }

    // Generate the jump instruction
    gen_direct_jump(jit, &reset_depth, jump_block, asm);
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

    // Create a backend assembler instance
    let mut asm = Assembler::new();

    #[cfg(feature = "disasm")]
    if get_option_ref!(dump_disasm).is_some() {
        let blockid_idx = blockid.idx;
        asm.comment(&format!("Block: {} (ISEQ offset: {})", iseq_get_location(blockid.iseq), blockid_idx));
    }

    // For each instruction to compile
    // NOTE: could rewrite this loop with a std::iter::Iterator
    while insn_idx < iseq_size {
        // Get the current pc and opcode
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
        // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
        let opcode: usize = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
            .try_into()
            .unwrap();

        // We need opt_getconstant_path to be in a block all on its own. Cut the block short
        // if we run into it. This is necessary because we want to invalidate based on the
        // instruction's index.
        if opcode == YARVINSN_opt_getconstant_path.as_usize() && insn_idx > starting_insn_idx {
            jump_to_next_insn(&mut jit, &ctx, &mut asm, ocb);
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
            let exit_pos = gen_outlined_exit(jit.pc, &ctx, ocb);
            record_global_inval_patch(&mut asm, exit_pos);
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
            gen_counter_incr!(asm, exec_instruction);

            // Add a comment for the name of the YARV instruction
            asm.comment(&insn_name(opcode));

            // If requested, dump instructions for debugging
            if get_option!(dump_insns) {
                println!("compiling {}", insn_name(opcode));
                print_str(&mut asm, &format!("executing {}", insn_name(opcode)));
            }

            // Call the code generation function
            status = gen_fn(&mut jit, &mut ctx, &mut asm, ocb);
        }

        // If we can't compile this instruction
        // exit to the interpreter and stop compiling
        if status == CantCompile {
            if get_option!(dump_insns) {
                println!("can't compile {}", insn_name(opcode));
            }

            let mut block = jit.block.borrow_mut();

            // TODO: if the codegen function makes changes to ctx and then return YJIT_CANT_COMPILE,
            // the exit this generates would be wrong. We could save a copy of the entry context
            // and assert that ctx is the same here.
            gen_exit(jit.pc, &ctx, &mut asm);

            // If this is the first instruction in the block, then we can use
            // the exit for block->entry_exit.
            if insn_idx == block.get_blockid().idx {
                block.entry_exit = block.get_start_addr();
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
        if block.entry_exit.is_some() {
            asm.pad_inval_patch();
        }

        // Compile code into the code block
        let gc_offsets = asm.compile(cb);

        // Add the GC offsets to the block
        block.add_gc_obj_offsets(gc_offsets);

        // Mark the end position of the block
        block.set_end_addr(cb.get_write_ptr());

        // Store the index of the last instruction in the block
        block.set_end_idx(insn_idx);
    }

    // We currently can't handle cases where the request is for a block that
    // doesn't go to the next instruction.
    assert!(!jit.record_boundary_patch_point);

    // If code for the block doesn't fit, fail
    if cb.has_dropped_bytes() || ocb.unwrap().has_dropped_bytes() {
        free_block(&blockref);
        return Err(());
    }

    // Block compiled successfully
    Ok(blockref)
}

fn gen_nop(
    _jit: &mut JITState,
    _ctx: &mut Context,
    _asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Do nothing
    KeepCompiling
}

fn gen_pop(
    _jit: &mut JITState,
    ctx: &mut Context,
    _asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Decrement SP
    ctx.stack_pop(1);
    KeepCompiling
}

fn gen_dup(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {

    let dup_val = ctx.stack_pop(0);
    let (mapping, tmp_type) = ctx.get_opnd_mapping(StackOpnd(0));

    let loc0 = ctx.stack_push_mapping((mapping, tmp_type));
    asm.mov(loc0, dup_val);

    KeepCompiling
}

// duplicate stack top n elements
fn gen_dupn(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let n = jit_get_arg(jit, 0).as_usize();

    // In practice, seems to be only used for n==2
    if n != 2 {
        return CantCompile;
    }

    let opnd1: Opnd = ctx.stack_opnd(1);
    let opnd0: Opnd = ctx.stack_opnd(0);

    let mapping1 = ctx.get_opnd_mapping(StackOpnd(1));
    let mapping0 = ctx.get_opnd_mapping(StackOpnd(0));

    let dst1: Opnd = ctx.stack_push_mapping(mapping1);
    asm.mov(dst1, opnd1);

    let dst0: Opnd = ctx.stack_push_mapping(mapping0);
    asm.mov(dst0, opnd0);

    KeepCompiling
}

// Swap top 2 stack entries
fn gen_swap(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    stack_swap(jit, ctx, asm, 0, 1);
    KeepCompiling
}

fn stack_swap(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    offset0: u16,
    offset1: u16,
) {
    let stack0_mem = ctx.stack_opnd(offset0 as i32);
    let stack1_mem = ctx.stack_opnd(offset1 as i32);

    let mapping0 = ctx.get_opnd_mapping(StackOpnd(offset0));
    let mapping1 = ctx.get_opnd_mapping(StackOpnd(offset1));

    let stack0_reg = asm.load(stack0_mem);
    let stack1_reg = asm.load(stack1_mem);
    asm.mov(stack0_mem, stack1_reg);
    asm.mov(stack1_mem, stack0_reg);

    ctx.set_opnd_mapping(StackOpnd(offset0), mapping1);
    ctx.set_opnd_mapping(StackOpnd(offset1), mapping0);
}

fn gen_putnil(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    jit_putobject(jit, ctx, asm, Qnil);
    KeepCompiling
}

fn jit_putobject(_jit: &mut JITState, ctx: &mut Context, asm: &mut Assembler, arg: VALUE) {
    let val_type: Type = Type::from(arg);
    let stack_top = ctx.stack_push(val_type);
    asm.mov(stack_top, arg.into());
}

fn gen_putobject_int2fix(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let opcode = jit.opcode;
    let cst_val: usize = if opcode == YARVINSN_putobject_INT2FIX_0_.as_usize() {
        0
    } else {
        1
    };

    jit_putobject(jit, ctx, asm, VALUE::fixnum_from_usize(cst_val));
    KeepCompiling
}

fn gen_putobject(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let arg: VALUE = jit_get_arg(jit, 0);

    jit_putobject(jit, ctx, asm, arg);
    KeepCompiling
}

fn gen_putself(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {

    // Write it on the stack
    let stack_top = ctx.stack_push_self();
    asm.mov(
        stack_top,
        Opnd::mem((8 * SIZEOF_VALUE) as u8, CFP, RUBY_OFFSET_CFP_SELF)
    );

    KeepCompiling
}

fn gen_putspecialobject(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let object_type = jit_get_arg(jit, 0).as_usize();

    if object_type == VM_SPECIAL_OBJECT_VMCORE.as_usize() {
        let stack_top = ctx.stack_push(Type::UnknownHeap);
        let frozen_core = unsafe { rb_mRubyVMFrozenCore };
        asm.mov(stack_top, frozen_core.into());
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
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let n = jit_get_arg(jit, 0).as_usize();

    let top_val = ctx.stack_pop(0);
    let dst_opnd = ctx.stack_opnd(n.try_into().unwrap());
    asm.mov(
        dst_opnd,
        top_val
    );

    let mapping = ctx.get_opnd_mapping(StackOpnd(0));
    ctx.set_opnd_mapping(StackOpnd(n.try_into().unwrap()), mapping);

    KeepCompiling
}

// get nth stack value, then push it
fn gen_topn(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let n = jit_get_arg(jit, 0).as_usize();

    let top_n_val = ctx.stack_opnd(n.try_into().unwrap());
    let mapping = ctx.get_opnd_mapping(StackOpnd(n.try_into().unwrap()));
    let loc0 = ctx.stack_push_mapping(mapping);
    asm.mov(loc0, top_n_val);

    KeepCompiling
}

// Pop n values off the stack
fn gen_adjuststack(
    jit: &mut JITState,
    ctx: &mut Context,
    _cb: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let n = jit_get_arg(jit, 0).as_usize();
    ctx.stack_pop(n);
    KeepCompiling
}

fn gen_opt_plus(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
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
        guard_two_fixnums(jit, ctx, asm, ocb, side_exit);

        // Get the operands from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Add arg0 + arg1 and test for overflow
        let arg0_untag = asm.sub(arg0, Opnd::Imm(1));
        let out_val = asm.add(arg0_untag, arg1);
        asm.jo(side_exit.as_side_exit());

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Fixnum);
        asm.mov(dst, out_val);

        KeepCompiling
    } else {
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

// new array initialized from top N values
fn gen_newarray(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let n = jit_get_arg(jit, 0).as_u32();

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, asm);

    // If n is 0, then elts is never going to be read, so we can just pass null
    let values_ptr = if n == 0 {
        Opnd::UImm(0)
    } else {
        asm.comment("load pointer to array elts");
        let offset_magnitude = (SIZEOF_VALUE as u32) * n;
        let values_opnd = ctx.sp_opnd(-(offset_magnitude as isize));
        asm.lea(values_opnd)
    };

    // call rb_ec_ary_new_from_values(struct rb_execution_context_struct *ec, long n, const VALUE *elts);
    let new_ary = asm.ccall(
        rb_ec_ary_new_from_values as *const u8,
        vec![
            EC,
            Opnd::UImm(n.into()),
            values_ptr
        ]
    );

    ctx.stack_pop(n.as_usize());
    let stack_ret = ctx.stack_push(Type::Array);
    asm.mov(stack_ret, new_ary);

    KeepCompiling
}

// dup array
fn gen_duparray(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let ary = jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, asm);

    // call rb_ary_resurrect(VALUE ary);
    let new_ary = asm.ccall(
        rb_ary_resurrect as *const u8,
        vec![ary.into()],
    );

    let stack_ret = ctx.stack_push(Type::Array);
    asm.mov(stack_ret, new_ary);

    KeepCompiling
}

// dup hash
fn gen_duphash(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let hash = jit_get_arg(jit, 0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, asm);

    // call rb_hash_resurrect(VALUE hash);
    let hash = asm.ccall(rb_hash_resurrect as *const u8, vec![hash.into()]);

    let stack_ret = ctx.stack_push(Type::Hash);
    asm.mov(stack_ret, hash);

    KeepCompiling
}

// call to_a on the array on the stack
fn gen_splatarray(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let flag = jit_get_arg(jit, 0).as_usize();

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, asm);

    // Get the operands from the stack
    let ary_opnd = ctx.stack_pop(1);

    // Call rb_vm_splat_array(flag, ary)
    let ary = asm.ccall(rb_vm_splat_array as *const u8, vec![flag.into(), ary_opnd]);

    let stack_ret = ctx.stack_push(Type::Array);
    asm.mov(stack_ret, ary);

    KeepCompiling
}

// concat two arrays
fn gen_concatarray(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, asm);

    // Get the operands from the stack
    let ary2st_opnd = ctx.stack_pop(1);
    let ary1_opnd = ctx.stack_pop(1);

    // Call rb_vm_concat_array(ary1, ary2st)
    let ary = asm.ccall(rb_vm_concat_array as *const u8, vec![ary1_opnd, ary2st_opnd]);

    let stack_ret = ctx.stack_push(Type::Array);
    asm.mov(stack_ret, ary);

    KeepCompiling
}

// new range initialized from top 2 values
fn gen_newrange(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let flag = jit_get_arg(jit, 0).as_usize();

    // rb_range_new() allocates and can raise
    jit_prepare_routine_call(jit, ctx, asm);

    // val = rb_range_new(low, high, (int)flag);
    let range_opnd = asm.ccall(
        rb_range_new as *const u8,
        vec![
            ctx.stack_opnd(1),
            ctx.stack_opnd(0),
            flag.into()
        ]
    );

    ctx.stack_pop(2);
    let stack_ret = ctx.stack_push(Type::UnknownHeap);
    asm.mov(stack_ret, range_opnd);

    KeepCompiling
}

fn guard_object_is_heap(
    asm: &mut Assembler,
    object_opnd: Opnd,
    side_exit: CodePtr,
) {
    asm.comment("guard object is heap");

    // Test that the object is not an immediate
    asm.test(object_opnd, (RUBY_IMMEDIATE_MASK as u64).into());
    asm.jnz(side_exit.as_side_exit());

    // Test that the object is not false
    asm.cmp(object_opnd, Qfalse.into());
    asm.je(side_exit.as_side_exit());
}

fn guard_object_is_array(
    asm: &mut Assembler,
    object_opnd: Opnd,
    side_exit: CodePtr,
) {
    asm.comment("guard object is array");

    // Pull out the type mask
    let flags_opnd = Opnd::mem(
        8 * SIZEOF_VALUE as u8,
        object_opnd,
        RUBY_OFFSET_RBASIC_FLAGS,
    );
    let flags_opnd = asm.and(flags_opnd, (RUBY_T_MASK as u64).into());

    // Compare the result with T_ARRAY
    asm.cmp(flags_opnd, (RUBY_T_ARRAY as u64).into());
    asm.jne(side_exit.as_side_exit());
}

fn guard_object_is_string(
    asm: &mut Assembler,
    object_reg: Opnd,
    side_exit: CodePtr,
) {
    asm.comment("guard object is string");

    // Pull out the type mask
    let flags_reg = asm.load(
        Opnd::mem(
            8 * SIZEOF_VALUE as u8,
            object_reg,
            RUBY_OFFSET_RBASIC_FLAGS,
        ),
    );
    let flags_reg = asm.and(flags_reg, Opnd::UImm(RUBY_T_MASK as u64));

    // Compare the result with T_STRING
    asm.cmp(flags_reg, Opnd::UImm(RUBY_T_STRING as u64));
    asm.jne(side_exit.as_side_exit());
}

// push enough nils onto the stack to fill out an array
fn gen_expandarray(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Both arguments are rb_num_t which is unsigned
    let num = jit_get_arg(jit, 0).as_usize();
    let flag = jit_get_arg(jit, 1).as_usize();

    // If this instruction has the splat flag, then bail out.
    if flag & 0x01 != 0 {
        gen_counter_incr!(asm, expandarray_splat);
        return CantCompile;
    }

    // If this instruction has the postarg flag, then bail out.
    if flag & 0x02 != 0 {
        gen_counter_incr!(asm, expandarray_postarg);
        return CantCompile;
    }

    let side_exit = get_side_exit(jit, ocb, ctx);

    let array_type = ctx.get_opnd_type(StackOpnd(0));
    let array_opnd = ctx.stack_pop(1);

    // num is the number of requested values. If there aren't enough in the
    // array then we're going to push on nils.
    if matches!(array_type, Type::Nil) {
        // special case for a, b = nil pattern
        // push N nils onto the stack
        for _ in 0..num {
            let push_opnd = ctx.stack_push(Type::Nil);
            asm.mov(push_opnd, Qnil.into());
        }
        return KeepCompiling;
    }

    // Move the array from the stack and check that it's an array.
    let array_reg = asm.load(array_opnd);
    guard_object_is_heap(
        asm,
        array_reg,
        counted_exit!(ocb, side_exit, expandarray_not_array),
    );
    guard_object_is_array(
        asm,
        array_reg,
        counted_exit!(ocb, side_exit, expandarray_not_array),
    );

    // If we don't actually want any values, then just return.
    if num == 0 {
        return KeepCompiling;
    }

    // Pull out the embed flag to check if it's an embedded array.
    let flags_opnd = Opnd::mem((8 * SIZEOF_VALUE) as u8, array_reg, RUBY_OFFSET_RBASIC_FLAGS);

    // Move the length of the embedded array into REG1.
    let emb_len_opnd = asm.and(flags_opnd, (RARRAY_EMBED_LEN_MASK as u64).into());
    let emb_len_opnd = asm.rshift(emb_len_opnd, (RARRAY_EMBED_LEN_SHIFT as u64).into());

    // Conditionally move the length of the heap array into REG1.
    let flags_opnd = Opnd::mem((8 * SIZEOF_VALUE) as u8, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags_opnd, (RARRAY_EMBED_FLAG as u64).into());
    let array_len_opnd = Opnd::mem(
        (8 * size_of::<std::os::raw::c_long>()) as u8,
        asm.load(array_opnd),
        RUBY_OFFSET_RARRAY_AS_HEAP_LEN,
    );
    let array_len_opnd = asm.csel_nz(emb_len_opnd, array_len_opnd);

    // Only handle the case where the number of values in the array is greater
    // than or equal to the number of values requested.
    asm.cmp(array_len_opnd, num.into());
    asm.jl(counted_exit!(ocb, side_exit, expandarray_rhs_too_small).into());

    // Load the address of the embedded array into REG1.
    // (struct RArray *)(obj)->as.ary
    let array_reg = asm.load(array_opnd);
    let ary_opnd = asm.lea(Opnd::mem((8 * SIZEOF_VALUE) as u8, array_reg, RUBY_OFFSET_RARRAY_AS_ARY));

    // Conditionally load the address of the heap array into REG1.
    // (struct RArray *)(obj)->as.heap.ptr
    let flags_opnd = Opnd::mem((8 * SIZEOF_VALUE) as u8, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags_opnd, Opnd::UImm(RARRAY_EMBED_FLAG as u64));
    let heap_ptr_opnd = Opnd::mem(
        (8 * size_of::<usize>()) as u8,
        asm.load(array_opnd),
        RUBY_OFFSET_RARRAY_AS_HEAP_PTR,
    );
    let ary_opnd = asm.csel_nz(ary_opnd, heap_ptr_opnd);

    // Loop backward through the array and push each element onto the stack.
    for i in (0..num).rev() {
        let top = ctx.stack_push(Type::Unknown);
        let offset = i32::try_from(i * SIZEOF_VALUE).unwrap();
        asm.mov(top, Opnd::mem(64, ary_opnd, offset));
    }

    KeepCompiling
}

fn gen_getlocal_wc0(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Compute the offset from BP to the local
    let slot_idx = jit_get_arg(jit, 0).as_i32();
    let offs: i32 = -(SIZEOF_VALUE as i32) * slot_idx;
    let local_idx = slot_to_local_idx(jit.get_iseq(), slot_idx);

    // Load environment pointer EP (level 0) from CFP
    let ep_opnd = gen_get_ep(asm, 0);

    // Load the local from the EP
    let local_opnd = Opnd::mem(64, ep_opnd, offs);

    // Write the local at SP
    let stack_top = ctx.stack_push_local(local_idx.as_usize());
    asm.mov(stack_top, local_opnd);

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
fn gen_get_ep(asm: &mut Assembler, level: u32) -> Opnd {
    // Load environment pointer EP from CFP into a register
    let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
    let mut ep_opnd = asm.load(ep_opnd);

    for _ in (0..level).rev() {
        // Get the previous EP from the current EP
        // See GET_PREV_EP(ep) macro
        // VALUE *prev_ep = ((VALUE *)((ep)[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03))
        let offs = (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32);
        ep_opnd = asm.load(Opnd::mem(64, ep_opnd, offs));
        ep_opnd = asm.and(ep_opnd, Opnd::Imm(!0x03));
    }

    ep_opnd
}

// Gets the EP of the ISeq of the containing method, or "local level".
// Equivalent of GET_LEP() macro.
fn gen_get_lep(jit: &mut JITState, asm: &mut Assembler) -> Opnd {
    // Equivalent of get_lvar_level() in compile.c
    fn get_lvar_level(iseq: IseqPtr) -> u32 {
        if iseq == unsafe { rb_get_iseq_body_local_iseq(iseq) } {
            0
        } else {
            1 + get_lvar_level(unsafe { rb_get_iseq_body_parent_iseq(iseq) })
        }
    }

    let level = get_lvar_level(jit.get_iseq());
    gen_get_ep(asm, level)
}

fn gen_getlocal_generic(
    ctx: &mut Context,
    asm: &mut Assembler,
    local_idx: u32,
    level: u32,
) -> CodegenStatus {
    // Load environment pointer EP (level 0) from CFP
    let ep_opnd = gen_get_ep(asm, level);

    // Load the local from the block
    // val = *(vm_get_ep(GET_EP(), level) - idx);
    let offs = -(SIZEOF_VALUE as i32 * local_idx as i32);
    let local_opnd = Opnd::mem(64, ep_opnd, offs);

    // Write the local at SP
    let stack_top = ctx.stack_push(Type::Unknown);

    asm.mov(stack_top, local_opnd);

    KeepCompiling
}

fn gen_getlocal(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let idx = jit_get_arg(jit, 0);
    let level = jit_get_arg(jit, 1);
    gen_getlocal_generic(ctx, asm, idx.as_u32(), level.as_u32())
}

fn gen_getlocal_wc1(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let idx = jit_get_arg(jit, 0);
    gen_getlocal_generic(ctx, asm, idx.as_u32(), 1)
}

fn gen_setlocal_wc0(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
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
    let value_type = ctx.get_opnd_type(StackOpnd(0));

    // Load environment pointer EP (level 0) from CFP
    let ep_opnd = gen_get_ep(asm, 0);

    // Write barriers may be required when VM_ENV_FLAG_WB_REQUIRED is set, however write barriers
    // only affect heap objects being written. If we know an immediate value is being written we
    // can skip this check.
    if !value_type.is_imm() {
        // flags & VM_ENV_FLAG_WB_REQUIRED
        let flags_opnd = Opnd::mem(
            64,
            ep_opnd,
            SIZEOF_VALUE as i32 * VM_ENV_DATA_INDEX_FLAGS as i32,
        );
        asm.test(flags_opnd, VM_ENV_FLAG_WB_REQUIRED.into());

        // Create a side-exit to fall back to the interpreter
        let side_exit = get_side_exit(jit, ocb, ctx);

        // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
        asm.jnz(side_exit.as_side_exit());
    }

    // Set the type of the local variable in the context
    ctx.set_local_type(local_idx, value_type);

    // Pop the value to write from the stack
    let stack_top = ctx.stack_pop(1);

    // Write the value at the environment pointer
    let offs: i32 = -8 * slot_idx;
    asm.mov(Opnd::mem(64, ep_opnd, offs), stack_top);

    KeepCompiling
}

fn gen_setlocal_generic(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    local_idx: i32,
    level: u32,
) -> CodegenStatus {
    let value_type = ctx.get_opnd_type(StackOpnd(0));

    // Load environment pointer EP at level
    let ep_opnd = gen_get_ep(asm, level);

    // Write barriers may be required when VM_ENV_FLAG_WB_REQUIRED is set, however write barriers
    // only affect heap objects being written. If we know an immediate value is being written we
    // can skip this check.
    if !value_type.is_imm() {
        // flags & VM_ENV_FLAG_WB_REQUIRED
        let flags_opnd = Opnd::mem(
            64,
            ep_opnd,
            SIZEOF_VALUE as i32 * VM_ENV_DATA_INDEX_FLAGS as i32,
        );
        asm.test(flags_opnd, VM_ENV_FLAG_WB_REQUIRED.into());

        // Create a side-exit to fall back to the interpreter
        let side_exit = get_side_exit(jit, ocb, ctx);

        // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
        asm.jnz(side_exit.as_side_exit());
    }

    // Pop the value to write from the stack
    let stack_top = ctx.stack_pop(1);

    // Write the value at the environment pointer
    let offs = -(SIZEOF_VALUE as i32 * local_idx);
    asm.mov(Opnd::mem(64, ep_opnd, offs), stack_top);

    KeepCompiling
}

fn gen_setlocal(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let idx = jit_get_arg(jit, 0).as_i32();
    let level = jit_get_arg(jit, 1).as_u32();
    gen_setlocal_generic(jit, ctx, asm, ocb, idx, level)
}

fn gen_setlocal_wc1(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let idx = jit_get_arg(jit, 0).as_i32();
    gen_setlocal_generic(jit, ctx, asm, ocb, idx, 1)
}

// new hash initialized from top N values
fn gen_newhash(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let num: u64 = jit_get_arg(jit, 0).as_u64();

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, asm);

    if num != 0 {
        // val = rb_hash_new_with_size(num / 2);
        let new_hash = asm.ccall(
            rb_hash_new_with_size as *const u8,
            vec![Opnd::UImm(num / 2)]
        );

        // Save the allocated hash as we want to push it after insertion
        asm.cpush(new_hash);
        asm.cpush(new_hash); // x86 alignment

        // Get a pointer to the values to insert into the hash
        let stack_addr_from_top = asm.lea(ctx.stack_opnd((num - 1) as i32));

        // rb_hash_bulk_insert(num, STACK_ADDR_FROM_TOP(num), val);
        asm.ccall(
            rb_hash_bulk_insert as *const u8,
            vec![
                Opnd::UImm(num),
                stack_addr_from_top,
                new_hash
            ]
        );

        let new_hash = asm.cpop();
        asm.cpop_into(new_hash); // x86 alignment

        ctx.stack_pop(num.try_into().unwrap());
        let stack_ret = ctx.stack_push(Type::Hash);
        asm.mov(stack_ret, new_hash);
    } else {
        // val = rb_hash_new();
        let new_hash = asm.ccall(rb_hash_new as *const u8, vec![]);
        let stack_ret = ctx.stack_push(Type::Hash);
        asm.mov(stack_ret, new_hash);
    }

    KeepCompiling
}

fn gen_putstring(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let put_val = jit_get_arg(jit, 0);

    // Save the PC and SP because the callee will allocate
    jit_prepare_routine_call(jit, ctx, asm);

    let str_opnd = asm.ccall(
        rb_ec_str_resurrect as *const u8,
        vec![EC, put_val.into()]
    );

    let stack_top = ctx.stack_push(Type::CString);
    asm.mov(stack_top, str_opnd);

    KeepCompiling
}

// Push Qtrue or Qfalse depending on whether the given keyword was supplied by
// the caller
fn gen_checkkeyword(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
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
    let ep_opnd = gen_get_ep(asm, 0);

    // VALUE kw_bits = *(ep - bits);
    let bits_opnd = Opnd::mem(64, ep_opnd, (SIZEOF_VALUE as i32) * -bits_offset);

    // unsigned int b = (unsigned int)FIX2ULONG(kw_bits);
    // if ((b & (0x01 << idx))) {
    //
    // We can skip the FIX2ULONG conversion by shifting the bit we test
    let bit_test: i64 = 0x01 << (index + 1);
    asm.test(bits_opnd, Opnd::Imm(bit_test));
    let ret_opnd = asm.csel_z(Qtrue.into(), Qfalse.into());

    let stack_ret = ctx.stack_push(Type::UnknownImm);
    asm.mov(stack_ret, ret_opnd);

    KeepCompiling
}

fn gen_jnz_to_target0(
    asm: &mut Assembler,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 | BranchShape::Next1 => unreachable!(),
        BranchShape::Default => asm.jnz(target0.into()),
    }
}

fn gen_jz_to_target0(
    asm: &mut Assembler,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 | BranchShape::Next1 => unreachable!(),
        BranchShape::Default => asm.jz(Target::CodePtr(target0)),
    }
}

fn gen_jbe_to_target0(
    asm: &mut Assembler,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 | BranchShape::Next1 => unreachable!(),
        BranchShape::Default => asm.jbe(Target::CodePtr(target0)),
    }
}

// Generate a jump to a stub that recompiles the current YARV instruction on failure.
// When depth_limit is exceeded, generate a jump to a side exit.
fn jit_chain_guard(
    jcc: JCCKinds,
    jit: &JITState,
    ctx: &Context,
    asm: &mut Assembler,
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
        let mut deeper = ctx.clone();
        deeper.increment_chain_depth();
        let bid = BlockId {
            iseq: jit.iseq,
            idx: jit.insn_idx,
        };

        gen_branch(jit, asm, ocb, bid, &deeper, None, None, target0_gen_fn);
    } else {
        target0_gen_fn(asm, side_exit, None, BranchShape::Default);
    }
}

// up to 5 different classes, and embedded or not for each
pub const GET_IVAR_MAX_DEPTH: i32 = 10;

// up to 5 different classes, and embedded or not for each
pub const SET_IVAR_MAX_DEPTH: i32 = 10;

// hashes and arrays
pub const OPT_AREF_MAX_CHAIN_DEPTH: i32 = 2;

// up to 5 different classes
pub const SEND_MAX_DEPTH: i32 = 5;

// up to 20 different methods for send
pub const SEND_MAX_CHAIN_DEPTH: i32 = 20;

// up to 20 different offsets for case-when
pub const CASE_WHEN_MAX_DEPTH: i32 = 20;

// Codegen for setting an instance variable.
// Preconditions:
//   - receiver is in REG0
//   - receiver has the same class as CLASS_OF(comptime_receiver)
//   - no stack push or pops to ctx since the entry to the codegen of the instruction being compiled
fn gen_set_ivar(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _recv: VALUE,
    ivar_name: ID,
    flags: u32,
    argc: i32,
) -> CodegenStatus {

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc as i32, ctx);
    }

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, asm);

    // Get the operands from the stack
    let val_opnd = ctx.stack_pop(1);
    let recv_opnd = ctx.stack_pop(1);

    // Call rb_vm_set_ivar_id with the receiver, the ivar name, and the value
    let val = asm.ccall(
        rb_vm_set_ivar_id as *const u8,
        vec![
            recv_opnd,
            Opnd::UImm(ivar_name),
            val_opnd,
        ],
    );

    let out_opnd = ctx.stack_push(Type::Unknown);
    asm.mov(out_opnd, val);

    KeepCompiling
}



// Codegen for getting an instance variable.
// Preconditions:
//   - receiver has the same class as CLASS_OF(comptime_receiver)
//   - no stack push or pops to ctx since the entry to the codegen of the instruction being compiled
fn gen_get_ivar(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    max_chain_depth: i32,
    comptime_receiver: VALUE,
    ivar_name: ID,
    recv: Opnd,
    recv_opnd: YARVOpnd,
    side_exit: CodePtr,
) -> CodegenStatus {
    // If the object has a too complex shape, we exit
    if comptime_receiver.shape_too_complex() {
        return CantCompile;
    }

    let comptime_val_klass = comptime_receiver.class_of();
    let starting_context = ctx.clone(); // make a copy for use with jit_chain_guard

    // If recv isn't already a register, load it.
    let recv = match recv {
        Opnd::Reg(_) => recv,
        _ => asm.load(recv),
    };

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
        asm.comment("call rb_ivar_get()");

        // The function could raise exceptions.
        jit_prepare_routine_call(jit, ctx, asm);

        let ivar_val = asm.ccall(rb_ivar_get as *const u8, vec![recv, Opnd::UImm(ivar_name)]);

        if recv_opnd != SelfOpnd {
            ctx.stack_pop(1);
        }

        // Push the ivar on the stack
        let out_opnd = ctx.stack_push(Type::Unknown);
        asm.mov(out_opnd, ivar_val);

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, ctx, asm, ocb);
        return EndBlock;
    }

    let ivar_index = unsafe {
        let shape_id = comptime_receiver.shape_id_of();
        let shape = rb_shape_get_shape_by_id(shape_id);
        let mut ivar_index: u32 = 0;
        if rb_shape_get_iv_index(shape, ivar_name, &mut ivar_index) {
            Some(ivar_index as usize)
        } else {
            None
        }
    };

    // must be before stack_pop
    let recv_type = ctx.get_opnd_type(recv_opnd);

    // Upgrade type
    if !recv_type.is_heap() {
        ctx.upgrade_opnd_type(recv_opnd, Type::UnknownHeap);
    }

    // Pop receiver if it's on the temp stack
    if recv_opnd != SelfOpnd {
        ctx.stack_pop(1);
    }

    // Guard heap object
    if !recv_type.is_heap() {
        guard_object_is_heap(asm, recv, side_exit);
    }

    // Compile time self is embedded and the ivar index lands within the object
    let embed_test_result = unsafe { FL_TEST_RAW(comptime_receiver, VALUE(ROBJECT_EMBED.as_usize())) != VALUE(0) };

    let expected_shape = unsafe { rb_shape_get_shape_id(comptime_receiver) };
    let shape_id_offset = unsafe { rb_shape_id_offset() };
    let shape_opnd = Opnd::mem(SHAPE_ID_NUM_BITS as u8, recv, shape_id_offset);

    asm.comment("guard shape");
    asm.cmp(shape_opnd, Opnd::UImm(expected_shape as u64));
    let megamorphic_side_exit = counted_exit!(ocb, side_exit, getivar_megamorphic).into();
    jit_chain_guard(
        JCC_JNE,
        jit,
        &starting_context,
        asm,
        ocb,
        max_chain_depth,
        megamorphic_side_exit,
    );

    match ivar_index {
        // If there is no IVAR index, then the ivar was undefined
        // when we entered the compiler.  That means we can just return
        // nil for this shape + iv name
        None => {
            let out_opnd = ctx.stack_push(Type::Nil);
            asm.mov(out_opnd, Qnil.into());
        }
        Some(ivar_index) => {
            if embed_test_result {
                // See ROBJECT_IVPTR() from include/ruby/internal/core/robject.h

                // Load the variable
                let offs = ROBJECT_OFFSET_AS_ARY + (ivar_index * SIZEOF_VALUE) as i32;
                let ivar_opnd = Opnd::mem(64, recv, offs);

                // Push the ivar on the stack
                let out_opnd = ctx.stack_push(Type::Unknown);
                asm.mov(out_opnd, ivar_opnd);
            } else {
                // Compile time value is *not* embedded.

                // Get a pointer to the extended table
                let tbl_opnd = asm.load(Opnd::mem(64, recv, ROBJECT_OFFSET_AS_HEAP_IVPTR));

                // Read the ivar from the extended table
                let ivar_opnd = Opnd::mem(64, tbl_opnd, (SIZEOF_VALUE * ivar_index) as i32);

                let out_opnd = ctx.stack_push(Type::Unknown);
                asm.mov(out_opnd, ivar_opnd);
            }
        }
    }

    // Jump to next instruction. This allows guard chains to share the same successor.
    jump_to_next_insn(jit, ctx, asm, ocb);
    EndBlock
}

fn gen_getinstancevariable(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    let ivar_name = jit_get_arg(jit, 0).as_u64();

    let comptime_val = jit_peek_at_self(jit);

    // Generate a side exit
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Guard that the receiver has the same class as the one from compile time.
    let self_asm_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF);

    gen_get_ivar(
        jit,
        ctx,
        asm,
        ocb,
        GET_IVAR_MAX_DEPTH,
        comptime_val,
        ivar_name,
        self_asm_opnd,
        SelfOpnd,
        side_exit,
    )
}

// Generate an IV write.
// This function doesn't deal with writing the shape, or expanding an object
// to use an IV buffer if necessary.  That is the callers responsibility
fn gen_write_iv(
    asm: &mut Assembler,
    comptime_receiver: VALUE,
    recv: Opnd,
    ivar_index: usize,
    set_value: Opnd,
    extension_needed: bool)
{
    // Compile time self is embedded and the ivar index lands within the object
    let embed_test_result = comptime_receiver.embedded_p() && !extension_needed;

    if embed_test_result {
        // Find the IV offset
        let offs = ROBJECT_OFFSET_AS_ARY + (ivar_index * SIZEOF_VALUE) as i32;
        let ivar_opnd = Opnd::mem(64, recv, offs);

        // Write the IV
        asm.comment("write IV");
        asm.mov(ivar_opnd, set_value);
    } else {
        // Compile time value is *not* embedded.

        // Get a pointer to the extended table
        let tbl_opnd = asm.load(Opnd::mem(64, recv, ROBJECT_OFFSET_AS_HEAP_IVPTR));

        // Write the ivar in to the extended table
        let ivar_opnd = Opnd::mem(64, tbl_opnd, (SIZEOF_VALUE * ivar_index) as i32);

        asm.comment("write IV");
        asm.mov(ivar_opnd, set_value);
    }
}

fn gen_setinstancevariable(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let starting_context = ctx.clone(); // make a copy for use with jit_chain_guard

    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    let ivar_name = jit_get_arg(jit, 0).as_u64();
    let comptime_receiver = jit_peek_at_self(jit);
    let comptime_val_klass = comptime_receiver.class_of();

    // If the comptime receiver is frozen, writing an IV will raise an exception
    // and we don't want to JIT code to deal with that situation.
    // If the object has a too complex shape, we will also exit
    if comptime_receiver.is_frozen() || comptime_receiver.shape_too_complex() {
        return CantCompile;
    }

    let (_, stack_type) = ctx.get_opnd_mapping(StackOpnd(0));

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

    // If the receiver isn't a T_OBJECT, or uses a custom allocator,
    // then just write out the IV write as a function call
    if !receiver_t_object || uses_custom_allocator {
        asm.comment("call rb_vm_setinstancevariable()");

        let ic = jit_get_arg(jit, 1).as_u64(); // type IVC

        // The function could raise exceptions.
        // Note that this modifies REG_SP, which is why we do it first
        jit_prepare_routine_call(jit, ctx, asm);

        // Get the operands from the stack
        let val_opnd = ctx.stack_pop(1);

        // Call rb_vm_setinstancevariable(iseq, obj, id, val, ic);
        asm.ccall(
            rb_vm_setinstancevariable as *const u8,
            vec![
                Opnd::const_ptr(jit.iseq as *const u8),
                Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF),
                ivar_name.into(),
                val_opnd,
                Opnd::const_ptr(ic as *const u8),
            ]
        );
    } else {
        // Get the iv index
        let ivar_index = unsafe {
            let shape_id = comptime_receiver.shape_id_of();
            let shape = rb_shape_get_shape_by_id(shape_id);
            let mut ivar_index: u32 = 0;
            if rb_shape_get_iv_index(shape, ivar_name, &mut ivar_index) {
                Some(ivar_index as usize)
            } else {
                None
            }
        };

        // Get the receiver
        let mut recv = asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF));

        let recv_opnd = SelfOpnd;
        let recv_type = ctx.get_opnd_type(recv_opnd);

        // Generate a side exit
        let side_exit = get_side_exit(jit, ocb, ctx);

        // Upgrade type
        if !recv_type.is_heap() { // Must be a heap type
            ctx.upgrade_opnd_type(recv_opnd, Type::UnknownHeap);
            guard_object_is_heap(asm, recv, side_exit);
        }

        let expected_shape = unsafe { rb_shape_get_shape_id(comptime_receiver) };
        let shape_id_offset = unsafe { rb_shape_id_offset() };
        let shape_opnd = Opnd::mem(SHAPE_ID_NUM_BITS as u8, recv, shape_id_offset);

        asm.comment("guard shape");
        asm.cmp(shape_opnd, Opnd::UImm(expected_shape as u64));
        let megamorphic_side_exit = counted_exit!(ocb, side_exit, getivar_megamorphic).into();
        jit_chain_guard(
            JCC_JNE,
            jit,
            &starting_context,
            asm,
            ocb,
            SET_IVAR_MAX_DEPTH,
            megamorphic_side_exit,
        );

        let write_val;

        match ivar_index {
            // If we don't have an instance variable index, then we need to
            // transition out of the current shape.
            None => {
                let shape = comptime_receiver.shape_of();

                let current_capacity = unsafe { (*shape).capacity };
                let new_capacity = current_capacity * 2;

                // If the object doesn't have the capacity to store the IV,
                // then we'll need to allocate it.
                let needs_extension = unsafe { (*shape).next_iv_index >= current_capacity };

                // We can write to the object, but we need to transition the shape
                let ivar_index = unsafe { (*shape).next_iv_index } as usize;

                let capa_shape = if needs_extension {
                    // We need to add an extended table to the object
                    // First, create an outgoing transition that increases the
                    // capacity
                    Some(unsafe { rb_shape_transition_shape_capa(shape, new_capacity) })
                } else {
                    None
                };

                let dest_shape = if capa_shape.is_none() {
                    unsafe { rb_shape_get_next(shape, comptime_receiver, ivar_name) }
                } else {
                    unsafe { rb_shape_get_next(capa_shape.unwrap(), comptime_receiver, ivar_name) }
                };

                let new_shape_id = unsafe { rb_shape_id(dest_shape) };

                if new_shape_id == OBJ_TOO_COMPLEX_SHAPE_ID {
                    return CantCompile;
                }

                if needs_extension {
                    // Generate the C call so that runtime code will increase
                    // the capacity and set the buffer.
                    asm.comment("call rb_ensure_iv_list_size");

                    // It allocates so can trigger GC, which takes the VM lock
                    // so could yield to a different ractor.
                    jit_prepare_routine_call(jit, ctx, asm);
                    asm.ccall(rb_ensure_iv_list_size as *const u8,
                              vec![
                                  recv,
                                  Opnd::UImm(current_capacity.into()),
                                  Opnd::UImm(new_capacity.into())
                              ]
                    );

                    // Load the receiver again after the function call
                    recv = asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF))
                }

                write_val = ctx.stack_pop(1);
                gen_write_iv(asm, comptime_receiver, recv, ivar_index, write_val, needs_extension);

                asm.comment("write shape");

                let shape_id_offset = unsafe { rb_shape_id_offset() };
                let shape_opnd = Opnd::mem(SHAPE_ID_NUM_BITS as u8, recv, shape_id_offset);

                // Store the new shape
                asm.store(shape_opnd, Opnd::UImm(new_shape_id as u64));
            },

            Some(ivar_index) => {
                // If the iv index already exists, then we don't need to
                // transition to a new shape.  The reason is because we find
                // the iv index by searching up the shape tree.  If we've
                // made the transition already, then there's no reason to
                // update the shape on the object.  Just set the IV.
                write_val = ctx.stack_pop(1);
                gen_write_iv(asm, comptime_receiver, recv, ivar_index, write_val, false);
            },
        }

        // If we know the stack value is an immediate, there's no need to
        // generate WB code.
        if !stack_type.is_imm() {
            let skip_wb = asm.new_label("skip_wb");
            // If the value we're writing is an immediate, we don't need to WB
            asm.test(write_val, (RUBY_IMMEDIATE_MASK as u64).into());
            asm.jnz(skip_wb);

            // If the value we're writing is nil or false, we don't need to WB
            asm.cmp(write_val, Qnil.into());
            asm.jbe(skip_wb);

            asm.comment("write barrier");
            asm.ccall(
                rb_gc_writebarrier as *const u8,
                vec![
                    recv,
                    write_val,
                ]
            );

            asm.write_label(skip_wb);
        }
    }

    KeepCompiling
}

fn gen_defined(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let op_type = jit_get_arg(jit, 0).as_u64();
    let obj = jit_get_arg(jit, 1);
    let pushval = jit_get_arg(jit, 2);

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, ctx, asm);

    // Get the operands from the stack
    let v_opnd = ctx.stack_pop(1);

    // Call vm_defined(ec, reg_cfp, op_type, obj, v)
    let def_result = asm.ccall(rb_vm_defined as *const u8, vec![EC, CFP, op_type.into(), obj.into(), v_opnd]);

    // if (vm_defined(ec, GET_CFP(), op_type, obj, v)) {
    //  val = pushval;
    // }
    asm.test(def_result, Opnd::UImm(255));
    let out_value = asm.csel_nz(pushval.into(), Qnil.into());

    // Push the return value onto the stack
    let out_type = if pushval.special_const_p() {
        Type::UnknownImm
    } else {
        Type::Unknown
    };
    let stack_ret = ctx.stack_push(out_type);
    asm.mov(stack_ret, out_value);

    KeepCompiling
}

fn gen_checktype(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let type_val = jit_get_arg(jit, 0).as_u32();

    // Only three types are emitted by compile.c at the moment
    if let RUBY_T_STRING | RUBY_T_ARRAY | RUBY_T_HASH = type_val {
        let val_type = ctx.get_opnd_type(StackOpnd(0));
        let val = asm.load(ctx.stack_pop(1));

        // Check if we know from type information
        match val_type.known_value_type() {
            Some(value_type) => {
                if value_type == type_val {
                    jit_putobject(jit, ctx, asm, Qtrue);
                    return KeepCompiling;
                } else {
                    jit_putobject(jit, ctx, asm, Qfalse);
                    return KeepCompiling;
                }
            },
            _ => (),
        }

        let ret = asm.new_label("ret");

        if !val_type.is_heap() {
            // if (SPECIAL_CONST_P(val)) {
            // Return Qfalse via REG1 if not on heap
            asm.test(val, (RUBY_IMMEDIATE_MASK as u64).into());
            asm.jnz(ret);
            asm.cmp(val, Qfalse.into());
            asm.je(ret);
        }

        // Check type on object
        let object_type = asm.and(
            Opnd::mem(64, val, RUBY_OFFSET_RBASIC_FLAGS),
            Opnd::UImm(RUBY_T_MASK.into()));
        asm.cmp(object_type, Opnd::UImm(type_val.into()));
        let ret_opnd = asm.csel_e(Qtrue.into(), Qfalse.into());

        asm.write_label(ret);
        let stack_ret = ctx.stack_push(Type::UnknownImm);
        asm.mov(stack_ret, ret_opnd);

        KeepCompiling
    } else {
        CantCompile
    }
}

fn gen_concatstrings(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let n = jit_get_arg(jit, 0).as_usize();

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, ctx, asm);

    let values_ptr = asm.lea(ctx.sp_opnd(-((SIZEOF_VALUE as isize) * n as isize)));

    // call rb_str_concat_literals(size_t n, const VALUE *strings);
    let return_value = asm.ccall(
        rb_str_concat_literals as *const u8,
        vec![n.into(), values_ptr]
    );

    ctx.stack_pop(n);
    let stack_ret = ctx.stack_push(Type::CString);
    asm.mov(stack_ret, return_value);

    KeepCompiling
}

fn guard_two_fixnums(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    side_exit: CodePtr
) {
    // Get the stack operand types
    let arg1_type = ctx.get_opnd_type(StackOpnd(0));
    let arg0_type = ctx.get_opnd_type(StackOpnd(1));

    if arg0_type.is_heap() || arg1_type.is_heap() {
        asm.comment("arg is heap object");
        asm.jmp(side_exit.as_side_exit());
        return;
    }

    if arg0_type != Type::Fixnum && arg0_type.is_specific() {
        asm.comment("arg0 not fixnum");
        asm.jmp(side_exit.as_side_exit());
        return;
    }

    if arg1_type != Type::Fixnum && arg1_type.is_specific() {
        asm.comment("arg1 not fixnum");
        asm.jmp(side_exit.as_side_exit());
        return;
    }

    assert!(!arg0_type.is_heap());
    assert!(!arg1_type.is_heap());
    assert!(arg0_type == Type::Fixnum || arg0_type.is_unknown());
    assert!(arg1_type == Type::Fixnum || arg1_type.is_unknown());

    // Get stack operands without popping them
    let arg1 = ctx.stack_opnd(0);
    let arg0 = ctx.stack_opnd(1);

    // If not fixnums at run-time, fall back
    if arg0_type != Type::Fixnum {
        asm.comment("guard arg0 fixnum");
        asm.test(arg0, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));

        jit_chain_guard(
            JCC_JZ,
            jit,
            &ctx,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            side_exit,
        );
    }
    if arg1_type != Type::Fixnum {
        asm.comment("guard arg1 fixnum");
        asm.test(arg1, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));

        jit_chain_guard(
            JCC_JZ,
            jit,
            &ctx,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            side_exit,
        );
    }

    // Set stack types in context
    ctx.upgrade_opnd_type(StackOpnd(0), Type::Fixnum);
    ctx.upgrade_opnd_type(StackOpnd(1), Type::Fixnum);
}

// Conditional move operation used by comparison operators
type CmovFn = fn(cb: &mut Assembler, opnd0: Opnd, opnd1: Opnd) -> Opnd;

fn gen_fixnum_cmp(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    cmov_op: CmovFn,
) -> CodegenStatus {
    // Defer compilation so we can specialize base on a runtime receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
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
        guard_two_fixnums(jit, ctx, asm, ocb, side_exit);

        // Get the operands from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Compare the arguments
        asm.cmp(arg0, arg1);
        let bool_opnd = cmov_op(asm, Qtrue.into(), Qfalse.into());

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Unknown);
        asm.mov(dst, bool_opnd);

        KeepCompiling
    } else {
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

fn gen_opt_lt(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    gen_fixnum_cmp(jit, ctx, asm, ocb, Assembler::csel_l)
}

fn gen_opt_le(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    gen_fixnum_cmp(jit, ctx, asm, ocb, Assembler::csel_le)
}

fn gen_opt_ge(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    gen_fixnum_cmp(jit, ctx, asm, ocb, Assembler::csel_ge)
}

fn gen_opt_gt(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    gen_fixnum_cmp(jit, ctx, asm, ocb, Assembler::csel_g)
}

// Implements specialized equality for either two fixnum or two strings
// Returns true if code was generated, otherwise false
fn gen_equality_specialized(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
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

        guard_two_fixnums(jit, ctx, asm, ocb, side_exit);

        asm.cmp(a_opnd, b_opnd);

        let val = asm.csel_ne(Qfalse.into(), Qtrue.into());

        // Push the output on the stack
        ctx.stack_pop(2);
        let dst = ctx.stack_push(Type::UnknownImm);
        asm.mov(dst, val);

        true
    }
    else if unsafe { comptime_a.class_of() == rb_cString && comptime_b.class_of() == rb_cString }
    {
        if !assume_bop_not_redefined(jit, ocb, STRING_REDEFINED_OP_FLAG, BOP_EQ) {
            // if overridden, emit the generic version
            return false;
        }

        // Guard that a is a String
        jit_guard_known_klass(
            jit,
            ctx,
            asm,
            ocb,
            unsafe { rb_cString },
            a_opnd,
            StackOpnd(1),
            comptime_a,
            SEND_MAX_DEPTH,
            side_exit,
        );

        let equal = asm.new_label("equal");
        let ret = asm.new_label("ret");

        // If they are equal by identity, return true
        asm.cmp(a_opnd, b_opnd);
        asm.je(equal);

        // Otherwise guard that b is a T_STRING (from type info) or String (from runtime guard)
        let btype = ctx.get_opnd_type(StackOpnd(0));
        if btype.known_value_type() != Some(RUBY_T_STRING) {
            // Note: any T_STRING is valid here, but we check for a ::String for simplicity
            // To pass a mutable static variable (rb_cString) requires an unsafe block
            jit_guard_known_klass(
                jit,
                ctx,
                asm,
                ocb,
                unsafe { rb_cString },
                b_opnd,
                StackOpnd(0),
                comptime_b,
                SEND_MAX_DEPTH,
                side_exit,
            );
        }

        // Call rb_str_eql_internal(a, b)
        let val = asm.ccall(rb_str_eql_internal as *const u8, vec![a_opnd, b_opnd]);

        // Push the output on the stack
        ctx.stack_pop(2);
        let dst = ctx.stack_push(Type::UnknownImm);
        asm.mov(dst, val);
        asm.jmp(ret);

        asm.write_label(equal);
        asm.mov(dst, Qtrue.into());

        asm.write_label(ret);

        true
    } else {
        false
    }
}

fn gen_opt_eq(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize base on a runtime receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    if gen_equality_specialized(jit, ctx, asm, ocb, side_exit) {
        jump_to_next_insn(jit, ctx, asm, ocb);
        EndBlock
    } else {
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

fn gen_opt_neq(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // opt_neq is passed two rb_call_data as arguments:
    // first for ==, second for !=
    let cd = jit_get_arg(jit, 1).as_ptr();
    return gen_send_general(jit, ctx, asm, ocb, cd, None);
}

fn gen_opt_aref(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let cd: *const rb_call_data = jit_get_arg(jit, 0).as_ptr();
    let argc = unsafe { vm_ci_argc((*cd).ci) };

    // Only JIT one arg calls like `ary[6]`
    if argc != 1 {
        gen_counter_incr!(asm, oaref_argc_not_one);
        return CantCompile;
    }

    // Defer compilation so we can specialize base on a runtime receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    // Specialize base on compile time values
    let comptime_idx = jit_peek_at_stack(jit, ctx, 0);
    let comptime_recv = jit_peek_at_stack(jit, ctx, 1);

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    if comptime_recv.class_of() == unsafe { rb_cArray } && comptime_idx.fixnum_p() {
        if !assume_bop_not_redefined(jit, ocb, ARRAY_REDEFINED_OP_FLAG, BOP_AREF) {
            return CantCompile;
        }

        // Get the stack operands
        let idx_opnd = ctx.stack_opnd(0);
        let recv_opnd = ctx.stack_opnd(1);

        // Guard that the receiver is an ::Array
        // BOP_AREF check above is only good for ::Array.
        jit_guard_known_klass(
            jit,
            ctx,
            asm,
            ocb,
            unsafe { rb_cArray },
            recv_opnd,
            StackOpnd(1),
            comptime_recv,
            OPT_AREF_MAX_CHAIN_DEPTH,
            side_exit,
        );

        // Bail if idx is not a FIXNUM
        let idx_reg = asm.load(idx_opnd);
        asm.test(idx_reg, (RUBY_FIXNUM_FLAG as u64).into());
        asm.jz(counted_exit!(ocb, side_exit, oaref_arg_not_fixnum).into());

        // Call VALUE rb_ary_entry_internal(VALUE ary, long offset).
        // It never raises or allocates, so we don't need to write to cfp->pc.
        {
            let idx_reg = asm.rshift(idx_reg, Opnd::UImm(1)); // Convert fixnum to int
            let val = asm.ccall(rb_ary_entry_internal as *const u8, vec![recv_opnd, idx_reg]);

            // Pop the argument and the receiver
            ctx.stack_pop(2);

            // Push the return value onto the stack
            let stack_ret = ctx.stack_push(Type::Unknown);
            asm.mov(stack_ret, val);
        }

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, ctx, asm, ocb);
        return EndBlock;
    } else if comptime_recv.class_of() == unsafe { rb_cHash } {
        if !assume_bop_not_redefined(jit, ocb, HASH_REDEFINED_OP_FLAG, BOP_AREF) {
            return CantCompile;
        }

        let recv_opnd = ctx.stack_opnd(1);

        // Guard that the receiver is a hash
        jit_guard_known_klass(
            jit,
            ctx,
            asm,
            ocb,
            unsafe { rb_cHash },
            recv_opnd,
            StackOpnd(1),
            comptime_recv,
            OPT_AREF_MAX_CHAIN_DEPTH,
            side_exit,
        );

        // Prepare to call rb_hash_aref(). It might call #hash on the key.
        jit_prepare_routine_call(jit, ctx, asm);

        // Call rb_hash_aref
        let key_opnd = ctx.stack_opnd(0);
        let recv_opnd = ctx.stack_opnd(1);
        let val = asm.ccall(rb_hash_aref as *const u8, vec![recv_opnd, key_opnd]);

        // Pop the key and the receiver
        ctx.stack_pop(2);

        // Push the return value onto the stack
        let stack_ret = ctx.stack_push(Type::Unknown);
        asm.mov(stack_ret, val);

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, ctx, asm, ocb);
        EndBlock
    } else {
        // General case. Call the [] method.
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

fn gen_opt_aset(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    let comptime_recv = jit_peek_at_stack(jit, ctx, 2);
    let comptime_key = jit_peek_at_stack(jit, ctx, 1);

    // Get the operands from the stack
    let recv = ctx.stack_opnd(2);
    let key = ctx.stack_opnd(1);
    let _val = ctx.stack_opnd(0);

    if comptime_recv.class_of() == unsafe { rb_cArray } && comptime_key.fixnum_p() {
        let side_exit = get_side_exit(jit, ocb, ctx);

        // Guard receiver is an Array
        jit_guard_known_klass(
            jit,
            ctx,
            asm,
            ocb,
            unsafe { rb_cArray },
            recv,
            StackOpnd(2),
            comptime_recv,
            SEND_MAX_DEPTH,
            side_exit,
        );

        // Guard key is a fixnum
        jit_guard_known_klass(
            jit,
            ctx,
            asm,
            ocb,
            unsafe { rb_cInteger },
            key,
            StackOpnd(1),
            comptime_key,
            SEND_MAX_DEPTH,
            side_exit,
        );

        // We might allocate or raise
        jit_prepare_routine_call(jit, ctx, asm);

        // Call rb_ary_store
        let recv = ctx.stack_opnd(2);
        let key = asm.load(ctx.stack_opnd(1));
        let key = asm.rshift(key, Opnd::UImm(1)); // FIX2LONG(key)
        let val = ctx.stack_opnd(0);
        asm.ccall(rb_ary_store as *const u8, vec![recv, key, val]);

        // rb_ary_store returns void
        // stored value should still be on stack
        let val = asm.load(ctx.stack_opnd(0));

        // Push the return value onto the stack
        ctx.stack_pop(3);
        let stack_ret = ctx.stack_push(Type::Unknown);
        asm.mov(stack_ret, val);

        jump_to_next_insn(jit, ctx, asm, ocb);
        return EndBlock;
    } else if comptime_recv.class_of() == unsafe { rb_cHash } {
        let side_exit = get_side_exit(jit, ocb, ctx);

        // Guard receiver is a Hash
        jit_guard_known_klass(
            jit,
            ctx,
            asm,
            ocb,
            unsafe { rb_cHash },
            recv,
            StackOpnd(2),
            comptime_recv,
            SEND_MAX_DEPTH,
            side_exit,
        );

        // We might allocate or raise
        jit_prepare_routine_call(jit, ctx, asm);

        // Call rb_hash_aset
        let recv = ctx.stack_opnd(2);
        let key = ctx.stack_opnd(1);
        let val = ctx.stack_opnd(0);
        let ret = asm.ccall(rb_hash_aset as *const u8, vec![recv, key, val]);

        // Push the return value onto the stack
        ctx.stack_pop(3);
        let stack_ret = ctx.stack_push(Type::Unknown);
        asm.mov(stack_ret, ret);

        jump_to_next_insn(jit, ctx, asm, ocb);
        EndBlock
    } else {
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

fn gen_opt_and(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
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
        guard_two_fixnums(jit, ctx, asm, ocb, side_exit);

        // Get the operands and destination from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Do the bitwise and arg0 & arg1
        let val = asm.and(arg0, arg1);

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Fixnum);
        asm.store(dst, val);

        KeepCompiling
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

fn gen_opt_or(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
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
        guard_two_fixnums(jit, ctx, asm, ocb, side_exit);

        // Get the operands and destination from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Do the bitwise or arg0 | arg1
        let val = asm.or(arg0, arg1);

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Fixnum);
        asm.store(dst, val);

        KeepCompiling
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

fn gen_opt_minus(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
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
        guard_two_fixnums(jit, ctx, asm, ocb, side_exit);

        // Get the operands and destination from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Subtract arg0 - arg1 and test for overflow
        let val_untag = asm.sub(arg0, arg1);
        asm.jo(side_exit.as_side_exit());
        let val = asm.add(val_untag, Opnd::Imm(1));

        // Push the output on the stack
        let dst = ctx.stack_push(Type::Fixnum);
        asm.store(dst, val);

        KeepCompiling
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

fn gen_opt_mult(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, asm, ocb)
}

fn gen_opt_div(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, asm, ocb)
}

fn gen_opt_mod(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    let comptime_a = jit_peek_at_stack(jit, ctx, 1);
    let comptime_b = jit_peek_at_stack(jit, ctx, 0);

    if comptime_a.fixnum_p() && comptime_b.fixnum_p() {
        // Create a side-exit to fall back to the interpreter
        // Note: we generate the side-exit before popping operands from the stack
        let side_exit = get_side_exit(jit, ocb, ctx);

        if !assume_bop_not_redefined(jit, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_MOD) {
            return CantCompile;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm, ocb, side_exit);

        // Get the operands and destination from the stack
        let arg1 = ctx.stack_pop(1);
        let arg0 = ctx.stack_pop(1);

        // Check for arg0 % 0
        asm.cmp(arg1, Opnd::Imm(VALUE::fixnum_from_usize(0).as_i64()));
        asm.je(side_exit.as_side_exit());

        // Call rb_fix_mod_fix(VALUE recv, VALUE obj)
        let ret = asm.ccall(rb_fix_mod_fix as *const u8, vec![arg0, arg1]);

        // Push the return value onto the stack
        let stack_ret = ctx.stack_push(Type::Unknown);
        asm.mov(stack_ret, ret);

        KeepCompiling
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, ctx, asm, ocb)
    }
}

fn gen_opt_ltlt(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, asm, ocb)
}

fn gen_opt_nil_p(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, asm, ocb)
}

fn gen_opt_empty_p(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, asm, ocb)
}

fn gen_opt_succ(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, ctx, asm, ocb)
}


fn gen_opt_str_freeze(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !assume_bop_not_redefined(jit, ocb, STRING_REDEFINED_OP_FLAG, BOP_FREEZE) {
        return CantCompile;
    }

    let str = jit_get_arg(jit, 0);

    // Push the return value onto the stack
    let stack_ret = ctx.stack_push(Type::CString);
    asm.mov(stack_ret, str.into());

    KeepCompiling
}

fn gen_opt_str_uminus(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !assume_bop_not_redefined(jit, ocb, STRING_REDEFINED_OP_FLAG, BOP_UMINUS) {
        return CantCompile;
    }

    let str = jit_get_arg(jit, 0);

    // Push the return value onto the stack
    let stack_ret = ctx.stack_push(Type::CString);
    asm.mov(stack_ret, str.into());

    KeepCompiling
}

fn gen_opt_newarray_max(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let num = jit_get_arg(jit, 0).as_u32();

    // Save the PC and SP because we may allocate
    jit_prepare_routine_call(jit, ctx, asm);

    extern "C" {
        fn rb_vm_opt_newarray_max(ec: EcPtr, num: u32, elts: *const VALUE) -> VALUE;
    }

    let offset_magnitude = (SIZEOF_VALUE as u32) * num;
    let values_opnd = ctx.sp_opnd(-(offset_magnitude as isize));
    let values_ptr = asm.lea(values_opnd);

    let val_opnd = asm.ccall(
        rb_vm_opt_newarray_max as *const u8,
        vec![
            EC,
            num.into(),
            values_ptr
        ],
    );

    ctx.stack_pop(num.as_usize());
    let stack_ret = ctx.stack_push(Type::Unknown);
    asm.mov(stack_ret, val_opnd);

    KeepCompiling
}

fn gen_opt_newarray_min(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {

    let num = jit_get_arg(jit, 0).as_u32();

    // Save the PC and SP because we may allocate
    jit_prepare_routine_call(jit, ctx, asm);

    extern "C" {
        fn rb_vm_opt_newarray_min(ec: EcPtr, num: u32, elts: *const VALUE) -> VALUE;
    }

    let offset_magnitude = (SIZEOF_VALUE as u32) * num;
    let values_opnd = ctx.sp_opnd(-(offset_magnitude as isize));
    let values_ptr = asm.lea(values_opnd);

    let val_opnd = asm.ccall(
        rb_vm_opt_newarray_min as *const u8,
        vec![
            EC,
            num.into(),
            values_ptr
        ],
    );

    ctx.stack_pop(num.as_usize());
    let stack_ret = ctx.stack_push(Type::Unknown);
    asm.mov(stack_ret, val_opnd);

    KeepCompiling
}

fn gen_opt_not(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    return gen_opt_send_without_block(jit, ctx, asm, ocb);
}

fn gen_opt_size(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    return gen_opt_send_without_block(jit, ctx, asm, ocb);
}

fn gen_opt_length(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    return gen_opt_send_without_block(jit, ctx, asm, ocb);
}

fn gen_opt_regexpmatch2(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    return gen_opt_send_without_block(jit, ctx, asm, ocb);
}

fn gen_opt_case_dispatch(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Normally this instruction would lookup the key in a hash and jump to an
    // offset based on that.
    // Instead we can take the fallback case and continue with the next
    // instruction.
    // We'd hope that our jitted code will be sufficiently fast without the
    // hash lookup, at least for small hashes, but it's worth revisiting this
    // assumption in the future.
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }
    let starting_context = ctx.clone();

    let case_hash = jit_get_arg(jit, 0);
    let else_offset = jit_get_arg(jit, 1).as_u32();

    // Try to reorder case/else branches so that ones that are actually used come first.
    // Supporting only Fixnum for now so that the implementation can be an equality check.
    let key_opnd = ctx.stack_pop(1);
    let comptime_key = jit_peek_at_stack(jit, ctx, 0);

    // Check that all cases are fixnums to avoid having to register BOP assumptions on
    // all the types that case hashes support. This spends compile time to save memory.
    fn case_hash_all_fixnum_p(hash: VALUE) -> bool {
        let mut all_fixnum = true;
        unsafe {
            unsafe extern "C" fn per_case(key: st_data_t, _value: st_data_t, data: st_data_t) -> c_int {
                (if VALUE(key as usize).fixnum_p() {
                    ST_CONTINUE
                } else {
                    (data as *mut bool).write(false);
                    ST_STOP
                }) as c_int
            }
            rb_hash_stlike_foreach(hash, Some(per_case), (&mut all_fixnum) as *mut _ as st_data_t);
        }

        all_fixnum
    }

    if comptime_key.fixnum_p() && comptime_key.0 <= u32::MAX.as_usize() && case_hash_all_fixnum_p(case_hash) {
        if !assume_bop_not_redefined(jit, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_EQQ) {
            return CantCompile;
        }

        // Check if the key is the same value
        asm.cmp(key_opnd, comptime_key.into());
        let side_exit = get_side_exit(jit, ocb, &starting_context);
        jit_chain_guard(
            JCC_JNE,
            jit,
            &starting_context,
            asm,
            ocb,
            CASE_WHEN_MAX_DEPTH as i32,
            side_exit,
        );

        // Get the offset for the compile-time key
        let mut offset = 0;
        unsafe { rb_hash_stlike_lookup(case_hash, comptime_key.0 as _, &mut offset) };
        let jump_offset = if offset == 0 {
            // NOTE: If we hit the else branch with various values, it could negatively impact the performance.
            else_offset
        } else {
            (offset as u32) >> 1 // FIX2LONG
        };

        // Jump to the offset of case or else
        let jump_block = BlockId { iseq: jit.iseq, idx: jit_next_insn_idx(jit) + jump_offset };
        gen_direct_jump(jit, &ctx, jump_block, asm);
        EndBlock
    } else {
        KeepCompiling // continue with === branches
    }
}

fn gen_branchif_branch(
    asm: &mut Assembler,
    target0: CodePtr,
    target1: Option<CodePtr>,
    shape: BranchShape,
) {
    assert!(target1 != None);
    match shape {
        BranchShape::Next0 => {
            asm.jz(target1.unwrap().into());
        }
        BranchShape::Next1 => {
            asm.jnz(target0.into());
        }
        BranchShape::Default => {
            asm.jnz(target0.into());
            asm.jmp(target1.unwrap().into());
        }
    }
}

fn gen_branchif(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        let side_exit = get_side_exit(jit, ocb, ctx);
        gen_check_ints(asm, side_exit);
    }

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

    // Test if any bit (outside of the Qnil bit) is on
    // See RB_TEST()
    let val_type = ctx.get_opnd_type(StackOpnd(0));
    let val_opnd = ctx.stack_pop(1);

    if let Some(result) = val_type.known_truthy() {
        let target = if result { jump_block } else { next_block };
        gen_direct_jump(jit, ctx, target, asm);
    } else {
        asm.test(val_opnd, Opnd::Imm(!Qnil.as_i64()));

        // Generate the branch instructions
        gen_branch(
            jit,
            asm,
            ocb,
            jump_block,
            ctx,
            Some(next_block),
            Some(ctx),
            gen_branchif_branch,
        );
    }

    EndBlock
}

fn gen_branchunless_branch(
    asm: &mut Assembler,
    target0: CodePtr,
    target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 => asm.jnz(target1.unwrap().into()),
        BranchShape::Next1 => asm.jz(target0.into()),
        BranchShape::Default => {
            asm.jz(target0.into());
            asm.jmp(target1.unwrap().into());
        }
    }
}

fn gen_branchunless(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        let side_exit = get_side_exit(jit, ocb, ctx);
        gen_check_ints(asm, side_exit);
    }

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

    let val_type = ctx.get_opnd_type(StackOpnd(0));
    let val_opnd = ctx.stack_pop(1);

    if let Some(result) = val_type.known_truthy() {
        let target = if result { next_block } else { jump_block };
        gen_direct_jump(jit, ctx, target, asm);
    } else {
        // Test if any bit (outside of the Qnil bit) is on
        // See RB_TEST()
        let not_qnil = !Qnil.as_i64();
        asm.test(val_opnd, not_qnil.into());

        // Generate the branch instructions
        gen_branch(
            jit,
            asm,
            ocb,
            jump_block,
            ctx,
            Some(next_block),
            Some(ctx),
            gen_branchunless_branch,
        );
    }

    EndBlock
}

fn gen_branchnil_branch(
    asm: &mut Assembler,
    target0: CodePtr,
    target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 => asm.jne(target1.unwrap().into()),
        BranchShape::Next1 => asm.je(target0.into()),
        BranchShape::Default => {
            asm.je(target0.into());
            asm.jmp(target1.unwrap().into());
        }
    }
}

fn gen_branchnil(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        let side_exit = get_side_exit(jit, ocb, ctx);
        gen_check_ints(asm, side_exit);
    }

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

    let val_type = ctx.get_opnd_type(StackOpnd(0));
    let val_opnd = ctx.stack_pop(1);

    if let Some(result) = val_type.known_nil() {
        let target = if result { jump_block } else { next_block };
        gen_direct_jump(jit, ctx, target, asm);
    } else {
        // Test if the value is Qnil
        asm.cmp(val_opnd, Opnd::UImm(Qnil.into()));
        // Generate the branch instructions
        gen_branch(
            jit,
            asm,
            ocb,
            jump_block,
            ctx,
            Some(next_block),
            Some(ctx),
            gen_branchnil_branch,
        );
    }

    EndBlock
}

fn gen_jump(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let jump_offset = jit_get_arg(jit, 0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        let side_exit = get_side_exit(jit, ocb, ctx);
        gen_check_ints(asm, side_exit);
    }

    // Get the branch target instruction offsets
    let jump_idx = (jit_next_insn_idx(jit) as i32) + jump_offset;
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx as u32,
    };

    // Generate the jump instruction
    gen_direct_jump(jit, ctx, jump_block, asm);

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
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    known_klass: VALUE,
    obj_opnd: Opnd,
    insn_opnd: YARVOpnd,
    sample_instance: VALUE,
    max_chain_depth: i32,
    side_exit: CodePtr,
) {
    let val_type = ctx.get_opnd_type(insn_opnd);

    if val_type.known_class() == Some(known_klass) {
        // We already know from type information that this is a match
        return;
    }

    if unsafe { known_klass == rb_cNilClass } {
        assert!(!val_type.is_heap());
        assert!(val_type.is_unknown());

        asm.comment("guard object is nil");
        asm.cmp(obj_opnd, Qnil.into());
        jit_chain_guard(JCC_JNE, jit, ctx, asm, ocb, max_chain_depth, side_exit);

        ctx.upgrade_opnd_type(insn_opnd, Type::Nil);
    } else if unsafe { known_klass == rb_cTrueClass } {
        assert!(!val_type.is_heap());
        assert!(val_type.is_unknown());

        asm.comment("guard object is true");
        asm.cmp(obj_opnd, Qtrue.into());
        jit_chain_guard(JCC_JNE, jit, ctx, asm, ocb, max_chain_depth, side_exit);

        ctx.upgrade_opnd_type(insn_opnd, Type::True);
    } else if unsafe { known_klass == rb_cFalseClass } {
        assert!(!val_type.is_heap());
        assert!(val_type.is_unknown());

        asm.comment("guard object is false");
        assert!(Qfalse.as_i32() == 0);
        asm.test(obj_opnd, obj_opnd);
        jit_chain_guard(JCC_JNZ, jit, ctx, asm, ocb, max_chain_depth, side_exit);

        ctx.upgrade_opnd_type(insn_opnd, Type::False);
    } else if unsafe { known_klass == rb_cInteger } && sample_instance.fixnum_p() {
        // We will guard fixnum and bignum as though they were separate classes
        // BIGNUM can be handled by the general else case below
        assert!(val_type.is_unknown());

        asm.comment("guard object is fixnum");
        asm.test(obj_opnd, Opnd::Imm(RUBY_FIXNUM_FLAG as i64));
        jit_chain_guard(JCC_JZ, jit, ctx, asm, ocb, max_chain_depth, side_exit);
        ctx.upgrade_opnd_type(insn_opnd, Type::Fixnum);
    } else if unsafe { known_klass == rb_cSymbol } && sample_instance.static_sym_p() {
        assert!(!val_type.is_heap());
        // We will guard STATIC vs DYNAMIC as though they were separate classes
        // DYNAMIC symbols can be handled by the general else case below
        if val_type != Type::ImmSymbol || !val_type.is_imm() {
            assert!(val_type.is_unknown());

            asm.comment("guard object is static symbol");
            assert!(RUBY_SPECIAL_SHIFT == 8);
            asm.cmp(obj_opnd.with_num_bits(8).unwrap(), Opnd::UImm(RUBY_SYMBOL_FLAG as u64));
            jit_chain_guard(JCC_JNE, jit, ctx, asm, ocb, max_chain_depth, side_exit);
            ctx.upgrade_opnd_type(insn_opnd, Type::ImmSymbol);
        }
    } else if unsafe { known_klass == rb_cFloat } && sample_instance.flonum_p() {
        assert!(!val_type.is_heap());
        if val_type != Type::Flonum || !val_type.is_imm() {
            assert!(val_type.is_unknown());

            // We will guard flonum vs heap float as though they were separate classes
            asm.comment("guard object is flonum");
            let flag_bits = asm.and(obj_opnd, Opnd::UImm(RUBY_FLONUM_MASK as u64));
            asm.cmp(flag_bits, Opnd::UImm(RUBY_FLONUM_FLAG as u64));
            jit_chain_guard(JCC_JNE, jit, ctx, asm, ocb, max_chain_depth, side_exit);
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
        asm.comment("guard known object with singleton class");
        asm.cmp(obj_opnd, sample_instance.into());
        jit_chain_guard(JCC_JNE, jit, ctx, asm, ocb, max_chain_depth, side_exit);
    } else if val_type == Type::CString && unsafe { known_klass == rb_cString } {
        // guard elided because the context says we've already checked
        unsafe {
            assert_eq!(sample_instance.class_of(), rb_cString, "context says class is exactly ::String")
        };
    } else {
        assert!(!val_type.is_imm());

        // Check that the receiver is a heap object
        // Note: if we get here, the class doesn't have immediate instances.
        if !val_type.is_heap() {
            asm.comment("guard not immediate");
            asm.test(obj_opnd, (RUBY_IMMEDIATE_MASK as u64).into());
            jit_chain_guard(JCC_JNZ, jit, ctx, asm, ocb, max_chain_depth, side_exit);
            asm.cmp(obj_opnd, Qfalse.into());
            jit_chain_guard(JCC_JE, jit, ctx, asm, ocb, max_chain_depth, side_exit);

            ctx.upgrade_opnd_type(insn_opnd, Type::UnknownHeap);
        }

        // If obj_opnd isn't already a register, load it.
        let obj_opnd = match obj_opnd {
            Opnd::Reg(_) => obj_opnd,
            _ => asm.load(obj_opnd),
        };
        let klass_opnd = Opnd::mem(64, obj_opnd, RUBY_OFFSET_RBASIC_KLASS);

        // Bail if receiver class is different from known_klass
        // TODO: jit_mov_gc_ptr keeps a strong reference, which leaks the class.
        asm.comment("guard known class");
        asm.cmp(klass_opnd, known_klass.into());
        jit_chain_guard(JCC_JNE, jit, ctx, asm, ocb, max_chain_depth, side_exit);

        if known_klass == unsafe { rb_cString } {
            ctx.upgrade_opnd_type(insn_opnd, Type::CString);
        }
    }
}

// Generate ancestry guard for protected callee.
// Calls to protected callees only go through when self.is_a?(klass_that_defines_the_callee).
fn jit_protected_callee_ancestry_guard(
    _jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    cme: *const rb_callable_method_entry_t,
    side_exit: CodePtr,
) {
    // See vm_call_method().
    let def_class = unsafe { (*cme).defined_class };
    // Note: PC isn't written to current control frame as rb_is_kind_of() shouldn't raise.
    // VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);

    let val = asm.ccall(
        rb_obj_is_kind_of as *mut u8,
        vec![
            Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF),
            def_class.into(),
        ],
    );
    asm.test(val, val);
    asm.jz(counted_exit!(ocb, side_exit, send_se_protected_check_failed).into())
}

// Codegen for rb_obj_not().
// Note, caller is responsible for generating all the right guards, including
// arity guards.
fn jit_rb_obj_not(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    let recv_opnd = ctx.get_opnd_type(StackOpnd(0));

    match recv_opnd.known_truthy() {
        Some(false) => {
            asm.comment("rb_obj_not(nil_or_false)");
            ctx.stack_pop(1);
            let out_opnd = ctx.stack_push(Type::True);
            asm.mov(out_opnd, Qtrue.into());
        },
        Some(true) => {
            // Note: recv_opnd != Type::Nil && recv_opnd != Type::False.
            asm.comment("rb_obj_not(truthy)");
            ctx.stack_pop(1);
            let out_opnd = ctx.stack_push(Type::False);
            asm.mov(out_opnd, Qfalse.into());
        },
        _ => {
            return false;
        },
    }

    true
}

// Codegen for rb_true()
fn jit_rb_true(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm.comment("nil? == true");
    ctx.stack_pop(1);
    let stack_ret = ctx.stack_push(Type::True);
    asm.mov(stack_ret, Qtrue.into());
    true
}

// Codegen for rb_false()
fn jit_rb_false(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm.comment("nil? == false");
    ctx.stack_pop(1);
    let stack_ret = ctx.stack_push(Type::False);
    asm.mov(stack_ret, Qfalse.into());
    true
}

// Codegen for rb_obj_equal()
// object identity comparison
fn jit_rb_obj_equal(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm.comment("equal?");
    let obj1 = ctx.stack_pop(1);
    let obj2 = ctx.stack_pop(1);

    asm.cmp(obj1, obj2);
    let ret_opnd = asm.csel_e(Qtrue.into(), Qfalse.into());

    let stack_ret = ctx.stack_push(Type::UnknownImm);
    asm.mov(stack_ret, ret_opnd);
    true
}

// Codegen for rb_int_equal()
fn jit_rb_int_equal(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Check that both operands are fixnums
    guard_two_fixnums(jit, ctx, asm, ocb, side_exit);

    // Compare the arguments
    asm.comment("rb_int_equal");
    let arg1 = ctx.stack_pop(1);
    let arg0 = ctx.stack_pop(1);
    asm.cmp(arg0, arg1);
    let ret_opnd = asm.csel_e(Qtrue.into(), Qfalse.into());

    let stack_ret = ctx.stack_push(Type::UnknownImm);
    asm.mov(stack_ret, ret_opnd);
    true
}

/// If string is frozen, duplicate it to get a non-frozen string. Otherwise, return it.
fn jit_rb_str_uplus(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    argc: i32,
    _known_recv_class: *const VALUE,
) -> bool
{
    if argc != 0 {
        return false;
    }

    // We allocate when we dup the string
    jit_prepare_routine_call(jit, ctx, asm);

    asm.comment("Unary plus on string");
    let recv_opnd = asm.load(ctx.stack_pop(1));
    let flags_opnd = asm.load(Opnd::mem(64, recv_opnd, RUBY_OFFSET_RBASIC_FLAGS));
    asm.test(flags_opnd, Opnd::Imm(RUBY_FL_FREEZE as i64));

    let ret_label = asm.new_label("stack_ret");

    // String#+@ can only exist on T_STRING
    let stack_ret = ctx.stack_push(Type::TString);

    // If the string isn't frozen, we just return it.
    asm.mov(stack_ret, recv_opnd);
    asm.jz(ret_label);

    // Str is frozen - duplicate it
    let ret_opnd = asm.ccall(rb_str_dup as *const u8, vec![recv_opnd]);
    asm.mov(stack_ret, ret_opnd);

    asm.write_label(ret_label);

    true
}

fn jit_rb_str_bytesize(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm.comment("String#bytesize");

    let recv = ctx.stack_pop(1);
    let ret_opnd = asm.ccall(rb_str_bytesize as *const u8, vec![recv]);

    let out_opnd = ctx.stack_push(Type::Fixnum);
    asm.mov(out_opnd, ret_opnd);

    true
}

// Codegen for rb_str_to_s()
// When String#to_s is called on a String instance, the method returns self and
// most of the overhead comes from setting up the method call. We observed that
// this situation happens a lot in some workloads.
fn jit_rb_str_to_s(
    _jit: &mut JITState,
    _ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    known_recv_class: *const VALUE,
) -> bool {
    if !known_recv_class.is_null() && unsafe { *known_recv_class == rb_cString } {
        asm.comment("to_s on plain string");
        // The method returns the receiver, which is already on the stack.
        // No stack movement.
        return true;
    }
    false
}

// Codegen for rb_str_concat() -- *not* String#concat
// Frequently strings are concatenated using "out_str << next_str".
// This is common in Erb and similar templating languages.
fn jit_rb_str_concat(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    // The << operator can accept integer codepoints for characters
    // as the argument. We only specially optimise string arguments.
    // If the peeked-at compile time argument is something other than
    // a string, assume it won't be a string later either.
    let comptime_arg = jit_peek_at_stack(jit, ctx, 0);
    if ! unsafe { RB_TYPE_P(comptime_arg, RUBY_T_STRING) } {
        return false;
    }

    // Generate a side exit
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Guard that the argument is of class String at runtime.
    let arg_type = ctx.get_opnd_type(StackOpnd(0));

    // Guard buffers from GC since rb_str_buf_append may allocate. During the VM lock on GC,
    // other Ractors may trigger global invalidation, so we need ctx.clear_local_types().
    // PC is used on errors like Encoding::CompatibilityError raised by rb_str_buf_append.
    jit_prepare_routine_call(jit, ctx, asm);

    let concat_arg = ctx.stack_pop(1);
    let recv = ctx.stack_pop(1);

    // If we're not compile-time certain that this will always be a string, guard at runtime
    if arg_type != Type::CString && arg_type != Type::TString {
        let arg_opnd = asm.load(concat_arg);
        if !arg_type.is_heap() {
            asm.comment("guard arg not immediate");
            asm.test(arg_opnd, (RUBY_IMMEDIATE_MASK as u64).into());
            asm.jnz(side_exit.as_side_exit());
            asm.cmp(arg_opnd, Qfalse.into());
            asm.je(side_exit.as_side_exit());
        }
        guard_object_is_string(asm, arg_opnd, side_exit);
    }

    // Test if string encodings differ. If different, use rb_str_append. If the same,
    // use rb_yjit_str_simple_append, which calls rb_str_cat.
    asm.comment("<< on strings");

    // Take receiver's object flags XOR arg's flags. If any
    // string-encoding flags are different between the two,
    // the encodings don't match.
    let recv_reg = asm.load(recv);
    let concat_arg_reg = asm.load(concat_arg);
    let flags_xor = asm.xor(
        Opnd::mem(64, recv_reg, RUBY_OFFSET_RBASIC_FLAGS),
        Opnd::mem(64, concat_arg_reg, RUBY_OFFSET_RBASIC_FLAGS)
    );
    asm.test(flags_xor, Opnd::UImm(RUBY_ENCODING_MASK as u64));

    // Push once, use the resulting operand in both branches below.
    let stack_ret = ctx.stack_push(Type::CString);

    let enc_mismatch = asm.new_label("enc_mismatch");
    asm.jnz(enc_mismatch);

    // If encodings match, call the simple append function and jump to return
    let ret_opnd = asm.ccall(rb_yjit_str_simple_append as *const u8, vec![recv, concat_arg]);
    let ret_label = asm.new_label("func_return");
    asm.mov(stack_ret, ret_opnd);
    asm.jmp(ret_label);

    // If encodings are different, use a slower encoding-aware concatenate
    asm.write_label(enc_mismatch);
    let ret_opnd = asm.ccall(rb_str_buf_append as *const u8, vec![recv, concat_arg]);
    asm.mov(stack_ret, ret_opnd);
    // Drop through to return

    asm.write_label(ret_label);

    true
}

fn jit_obj_respond_to(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    argc: i32,
    known_recv_class: *const VALUE,
) -> bool {
    // respond_to(:sym) or respond_to(:sym, true)
    if argc != 1 && argc != 2 {
        return false;
    }

    if known_recv_class.is_null() {
        return false;
    }

    let recv_class = unsafe { *known_recv_class };

    // Get the method_id from compile time. We will later add a guard against it.
    let mid_sym = jit_peek_at_stack(jit, ctx, (argc - 1) as isize);
    if !mid_sym.static_sym_p() {
        return false
    }
    let mid = unsafe { rb_sym2id(mid_sym) };

    // Option<bool> representing the value of the "include_all" argument and whether it's known
    let allow_priv = if argc == 1 {
        // Default is false
        Some(false)
    } else {
        // Get value from type information (may or may not be known)
        ctx.get_opnd_type(StackOpnd(0)).known_truthy()
    };

    let target_cme = unsafe { rb_callable_method_entry_or_negative(recv_class, mid) };

    // Should never be null, as in that case we will be returned a "negative CME"
    assert!(!target_cme.is_null());

    let cme_def_type = unsafe { get_cme_def_type(target_cme) };

    if cme_def_type == VM_METHOD_TYPE_REFINED {
        return false;
    }

    let visibility = if cme_def_type == VM_METHOD_TYPE_UNDEF {
        METHOD_VISI_UNDEF
    } else {
        unsafe { METHOD_ENTRY_VISI(target_cme) }
    };

    let result = match (visibility, allow_priv) {
        (METHOD_VISI_UNDEF, _) => Qfalse, // No method => false
        (METHOD_VISI_PUBLIC, _) => Qtrue, // Public method => true regardless of include_all
        (_, Some(true)) => Qtrue, // include_all => always true
        (_, _) => return false // not public and include_all not known, can't compile
    };

    if result != Qtrue {
        // Only if respond_to_missing? hasn't been overridden
        // In the future, we might want to jit the call to respond_to_missing?
        if !assume_method_basic_definition(jit, ocb, recv_class, idRespond_to_missing.into()) {
            return false;
        }
    }

    // Invalidate this block if method lookup changes for the method being queried. This works
    // both for the case where a method does or does not exist, as for the latter we asked for a
    // "negative CME" earlier.
    assume_method_lookup_stable(jit, ocb, target_cme);

    // Generate a side exit
    let side_exit = get_side_exit(jit, ocb, ctx);

    if argc == 2 {
        // pop include_all argument (we only use its type info)
        ctx.stack_pop(1);
    }

    let sym_opnd = ctx.stack_pop(1);
    let _recv_opnd = ctx.stack_pop(1);

    // This is necessary because we have no guarantee that sym_opnd is a constant
    asm.comment("guard known mid");
    asm.cmp(sym_opnd, mid_sym.into());
    asm.jne(side_exit.as_side_exit());

    jit_putobject(jit, ctx, asm, result);

    true
}

fn jit_thread_s_current(
    _jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<IseqPtr>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm.comment("Thread.current");
    ctx.stack_pop(1);

    // ec->thread_ptr
    let ec_thread_opnd = asm.load(Opnd::mem(64, EC, RUBY_OFFSET_EC_THREAD_PTR));

    // thread->self
    let thread_self = Opnd::mem(64, ec_thread_opnd, RUBY_OFFSET_THREAD_SELF);

    let stack_ret = ctx.stack_push(Type::UnknownHeap);
    asm.mov(stack_ret, thread_self);
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

// SpecVal is a single value in an iseq invocation's environment on the stack,
// at sp[-2]. Depending on the frame type, it can serve different purposes,
// which are covered here by enum variants.
enum SpecVal {
    None,
    BlockISeq(IseqPtr),
    BlockParamProxy,
    PrevEP(*const VALUE),
    PrevEPOpnd(Opnd),
}

struct ControlFrame {
    recv: Opnd,
    sp: Opnd,
    iseq: Option<IseqPtr>,
    pc: Option<u64>,
    frame_type: u32,
    specval: SpecVal,
    cme: *const rb_callable_method_entry_t,
    local_size: i32
}

// Codegen performing a similar (but not identical) function to vm_push_frame
//
// This will generate the code to:
//   * initialize locals to Qnil
//   * push the environment (cme, block handler, frame type)
//   * push a new CFP
//   * save the new CFP to ec->cfp
//
// Notes:
//   * Provided sp should point to the new frame's sp, immediately following locals and the environment
//   * At entry, CFP points to the caller (not callee) frame
//   * At exit, ec->cfp is updated to the pushed CFP
//   * CFP and SP registers are updated only if set_sp_cfp is set
//   * Stack overflow is not checked (should be done by the caller)
//   * Interrupts are not checked (should be done by the caller)
fn gen_push_frame(
    jit: &mut JITState,
    _ctx: &mut Context,
    asm: &mut Assembler,
    set_sp_cfp: bool, // if true CFP and SP will be switched to the callee
    frame: ControlFrame,
) {
    assert!(frame.local_size >= 0);

    let sp = frame.sp;

    asm.comment("push cme, specval, frame type");

    // Write method entry at sp[-3]
    // sp[-3] = me;
    // Use compile time cme. It's assumed to be valid because we are notified when
    // any cme we depend on become outdated. See yjit_method_lookup_change().
    asm.store(Opnd::mem(64, sp, SIZEOF_VALUE_I32 * -3), VALUE::from(frame.cme).into());

    // Write special value at sp[-2]. It's either a block handler or a pointer to
    // the outer environment depending on the frame type.
    // sp[-2] = specval;
    let specval: Opnd = match frame.specval {
        SpecVal::None => {
            VM_BLOCK_HANDLER_NONE.into()
        }
        SpecVal::BlockISeq(block_iseq) => {
            // Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
            // VM_CFP_TO_CAPTURED_BLOCK does &cfp->self, rb_captured_block->code.iseq aliases
            // with cfp->block_code.
            asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_BLOCK_CODE), VALUE::from(block_iseq).into());

            let cfp_self = asm.lea(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF));
            asm.or(cfp_self, Opnd::Imm(1))
        }
        SpecVal::BlockParamProxy => {
            let ep_opnd = gen_get_lep(jit, asm);
            let block_handler = asm.load(
                Opnd::mem(64, ep_opnd, (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32))
            );

            asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_BLOCK_CODE), block_handler);

            block_handler
        }
        SpecVal::PrevEP(prev_ep) => {
            let tagged_prev_ep = (prev_ep as usize) | 1;
            VALUE(tagged_prev_ep).into()
        }
        SpecVal::PrevEPOpnd(ep_opnd) => {
            asm.or(ep_opnd, 1.into())
        },
    };
    asm.store(Opnd::mem(64, sp, SIZEOF_VALUE_I32 * -2), specval);

    // Write env flags at sp[-1]
    // sp[-1] = frame_type;
    asm.store(Opnd::mem(64, sp, SIZEOF_VALUE_I32 * -1), frame.frame_type.into());

    // Allocate a new CFP (ec->cfp--)
    fn cfp_opnd(offset: i32) -> Opnd {
        Opnd::mem(64, CFP, offset - (RUBY_SIZEOF_CONTROL_FRAME as i32))
    }

    // Setup the new frame
    // *cfp = (const struct rb_control_frame_struct) {
    //    .pc         = <unset for iseq, 0 for cfunc>,
    //    .sp         = sp,
    //    .iseq       = <iseq for iseq, 0 for cfunc>,
    //    .self       = recv,
    //    .ep         = <sp - 1>,
    //    .block_code = 0,
    //    .__bp__     = sp,
    // };
    asm.comment("push callee control frame");

    // For an iseq call PC may be None, in which case we will not set PC and will allow jitted code
    // to set it as necessary.
    let _pc = if let Some(pc) = frame.pc {
        asm.mov(cfp_opnd(RUBY_OFFSET_CFP_PC), pc.into());
    };
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_BP), sp);
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SP), sp);
    let iseq: Opnd = if let Some(iseq) = frame.iseq {
        VALUE::from(iseq).into()
    } else {
        0.into()
    };
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_ISEQ), iseq);
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SELF), frame.recv);
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_BLOCK_CODE), 0.into());

    // This Qnil fill snippet potentially requires 2 more registers on Arm, one for Qnil and
    // another for calculating the address in case there are a lot of local variables. So doing
    // this after releasing the register for specval and the receiver to avoid register spill.
    let num_locals = frame.local_size;
    if num_locals > 0 {
        asm.comment("initialize locals");

        // Initialize local variables to Qnil
        for i in 0..num_locals {
            let offs = (SIZEOF_VALUE as i32) * (i - num_locals - 3);
            asm.store(Opnd::mem(64, sp, offs), Qnil.into());
        }
    }

    if set_sp_cfp {
        // Saving SP before calculating ep avoids a dependency on a register
        // However this must be done after referencing frame.recv, which may be SP-relative
        asm.mov(SP, sp);
    }
    let ep = asm.sub(sp, SIZEOF_VALUE.into());
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_EP), ep);

    asm.comment("switch to new CFP");
    let new_cfp = asm.lea(cfp_opnd(0));
    if set_sp_cfp {
        asm.mov(CFP, new_cfp);
        asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);
    } else {
        asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), new_cfp);
    }
}

fn gen_send_cfunc(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    block: Option<IseqPtr>,
    recv_known_klass: *const VALUE,
    flags: u32,
    argc: i32,
) -> CodegenStatus {
    let cfunc = unsafe { get_cme_def_body_cfunc(cme) };
    let cfunc_argc = unsafe { get_mct_argc(cfunc) };
    let argc = argc;

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    // If the function expects a Ruby array of arguments
    if cfunc_argc < 0 && cfunc_argc != -1 {
        gen_counter_incr!(asm, send_cfunc_ruby_array_varg);
        return CantCompile;
    }

    if flags & VM_CALL_ARGS_SPLAT != 0  {
        gen_counter_incr!(asm, send_args_splat_cfunc);
        return CantCompile;
    }

    let kw_arg = unsafe { vm_ci_kwarg(ci) };
    let kw_arg_num = if kw_arg.is_null() {
        0
    } else {
        unsafe { get_cikw_keyword_len(kw_arg) }
    };

    if c_method_tracing_currently_enabled(jit) {
        // Don't JIT if tracing c_call or c_return
        gen_counter_incr!(asm, send_cfunc_tracing);
        return CantCompile;
    }

    // Delegate to codegen for C methods if we have it.
    if kw_arg.is_null() && flags & VM_CALL_OPT_SEND == 0 && flags & VM_CALL_ARGS_SPLAT == 0 && (cfunc_argc == -1 || argc == cfunc_argc) {
        let codegen_p = lookup_cfunc_codegen(unsafe { (*cme).def });
        let expected_stack_after = ctx.get_stack_size() as i32 - argc;
        if let Some(known_cfunc_codegen) = codegen_p {
            if known_cfunc_codegen(jit, ctx, asm, ocb, ci, cme, block, argc, recv_known_klass) {
                assert_eq!(expected_stack_after, ctx.get_stack_size() as i32);
                // cfunc codegen generated code. Terminate the block so
                // there isn't multiple calls in the same block.
                jump_to_next_insn(jit, ctx, asm, ocb);
                return EndBlock;
            }
        }
    }

    // Check for interrupts
    gen_check_ints(asm, side_exit);

    // Stack overflow check
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    // REG_CFP <= REG_SP + 4 * SIZEOF_VALUE + sizeof(rb_control_frame_t)
    asm.comment("stack overflow check");
    let stack_limit = asm.lea(ctx.sp_opnd((SIZEOF_VALUE * 4 + 2 * RUBY_SIZEOF_CONTROL_FRAME) as isize));
    asm.cmp(CFP, stack_limit);
    asm.jbe(counted_exit!(ocb, side_exit, send_se_cf_overflow).as_side_exit());

    // Number of args which will be passed through to the callee
    // This is adjusted by the kwargs being combined into a hash.
    let passed_argc = if kw_arg.is_null() {
        argc
    } else {
        argc - kw_arg_num + 1
    };

    // If the argument count doesn't match
    if cfunc_argc >= 0 && cfunc_argc != passed_argc {
        gen_counter_incr!(asm, send_cfunc_argc_mismatch);
        return CantCompile;
    }

    // Don't JIT functions that need C stack arguments for now
    if cfunc_argc >= 0 && passed_argc + 1 > (C_ARG_OPNDS.len() as i32) {
        gen_counter_incr!(asm, send_cfunc_toomany_args);
        return CantCompile;
    }

    let block_arg = flags & VM_CALL_ARGS_BLOCKARG != 0;
    let block_arg_type = if block_arg {
        Some(ctx.get_opnd_type(StackOpnd(0)))
    } else {
        None
    };

    match block_arg_type {
        Some(Type::Nil | Type::BlockParamProxy) => {
            // We'll handle this later
        }
        None => {
            // Nothing to do
        }
        _ => {
            gen_counter_incr!(asm, send_block_arg);
            return CantCompile;
        }
    }

    match block_arg_type {
        Some(Type::Nil) => {
            // We have a nil block arg, so let's pop it off the args
            ctx.stack_pop(1);
        }
        Some(Type::BlockParamProxy) => {
            // We don't need the actual stack value
            ctx.stack_pop(1);
        }
        None => {
            // Nothing to do
        }
        _ => {
            assert!(false);
        }
    }

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc as i32, ctx);
    }

    // Points to the receiver operand on the stack
    let recv = ctx.stack_opnd(argc);

    // Store incremented PC into current control frame in case callee raises.
    jit_save_pc(jit, asm);

    // Increment the stack pointer by 3 (in the callee)
    // sp += 3
    let sp = asm.lea(ctx.sp_opnd((SIZEOF_VALUE as isize) * 3));

    let specval = if block_arg_type == Some(Type::BlockParamProxy) {
        SpecVal::BlockParamProxy
    } else if let Some(block_iseq) = block {
        SpecVal::BlockISeq(block_iseq)
    } else {
        SpecVal::None
    };

    let mut frame_type = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;
    if !kw_arg.is_null() {
        frame_type |= VM_FRAME_FLAG_CFRAME_KW
    }

    gen_push_frame(jit, ctx, asm, false, ControlFrame {
        frame_type,
        specval,
        cme,
        recv,
        sp,
        pc: Some(0),
        iseq: None,
        local_size: 0,
    });

    if !kw_arg.is_null() {
        // Build a hash from all kwargs passed
        asm.comment("build_kwhash");
        let imemo_ci = VALUE(ci as usize);
        assert_ne!(0, unsafe { rb_IMEMO_TYPE_P(imemo_ci, imemo_callinfo) },
            "we assume all callinfos with kwargs are on the GC heap");
        let sp = asm.lea(ctx.sp_opnd(0));
        let kwargs = asm.ccall(build_kwhash as *const u8, vec![imemo_ci.into(), sp]);

        // Replace the stack location at the start of kwargs with the new hash
        let stack_opnd = ctx.stack_opnd(argc - passed_argc);
        asm.mov(stack_opnd, kwargs);
    }

    // Copy SP because REG_SP will get overwritten
    let sp = asm.lea(ctx.sp_opnd(0));

    // Pop the C function arguments from the stack (in the caller)
    ctx.stack_pop((argc + 1).try_into().unwrap());

    // Write interpreter SP into CFP.
    // Needed in case the callee yields to the block.
    gen_save_sp(jit, asm, ctx);

    // Non-variadic method
    let args = if cfunc_argc >= 0 {
        // Copy the arguments from the stack to the C argument registers
        // self is the 0th argument and is at index argc from the stack top
        (0..=passed_argc).map(|i|
            Opnd::mem(64, sp, -(argc + 1 - (i as i32)) * SIZEOF_VALUE_I32)
        ).collect()
    }
    // Variadic method
    else if cfunc_argc == -1 {
        // The method gets a pointer to the first argument
        // rb_f_puts(int argc, VALUE *argv, VALUE recv)
        vec![
            Opnd::Imm(passed_argc.into()),
            asm.lea(Opnd::mem(64, sp, -(argc) * SIZEOF_VALUE_I32)),
            Opnd::mem(64, sp, -(argc + 1) * SIZEOF_VALUE_I32),
        ]
    }
    else {
        panic!("unexpected cfunc_args: {}", cfunc_argc)
    };

    // Call the C function
    // VALUE ret = (cfunc->func)(recv, argv[0], argv[1]);
    // cfunc comes from compile-time cme->def, which we assume to be stable.
    // Invalidation logic is in yjit_method_lookup_change()
    asm.comment("call C function");
    let ret = asm.ccall(unsafe { get_mct_func(cfunc) }.cast(), args);

    // Record code position for TracePoint patching. See full_cfunc_return().
    record_global_inval_patch(asm, CodegenGlobals::get_outline_full_cfunc_return_pos());

    // Push the return value on the Ruby stack
    let stack_ret = ctx.stack_push(Type::Unknown);
    asm.mov(stack_ret, ret);

    // Pop the stack frame (ec->cfp++)
    // Instead of recalculating, we can reuse the previous CFP, which is stored in a callee-saved
    // register
    let ec_cfp_opnd = Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP);
    asm.store(ec_cfp_opnd, CFP);

    // cfunc calls may corrupt types
    ctx.clear_local_types();

    // Note: the return block of gen_send_iseq() has ctx->sp_offset == 1
    // which allows for sharing the same successor.

    // Jump (fall through) to the call continuation block
    // We do this to end the current block after the call
    jump_to_next_insn(jit, ctx, asm, ocb);
    EndBlock
}

fn gen_return_branch(
    asm: &mut Assembler,
    target0: CodePtr,
    _target1: Option<CodePtr>,
    shape: BranchShape,
) {
    match shape {
        BranchShape::Next0 | BranchShape::Next1 => unreachable!(),
        BranchShape::Default => {
            asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_JIT_RETURN), Opnd::const_ptr(target0.raw_ptr()));
        }
    }
}

/// Pushes arguments from an array to the stack that are passed with a splat (i.e. *args)
/// It optimistically compiles to a static size that is the exact number of arguments
/// needed for the function.
fn push_splat_args(required_args: i32, ctx: &mut Context, asm: &mut Assembler, ocb: &mut OutlinedCb, side_exit: CodePtr) {

    asm.comment("push_splat_args");

    let array_opnd = ctx.stack_opnd(0);

    let array_reg = asm.load(array_opnd);
    guard_object_is_heap(
        asm,
        array_reg,
        counted_exit!(ocb, side_exit, send_splat_not_array),
    );
    guard_object_is_array(
        asm,
        array_reg,
        counted_exit!(ocb, side_exit, send_splat_not_array),
    );

    // Pull out the embed flag to check if it's an embedded array.
    let flags_opnd = Opnd::mem((8 * SIZEOF_VALUE) as u8, array_reg, RUBY_OFFSET_RBASIC_FLAGS);

    // Get the length of the array
    let emb_len_opnd = asm.and(flags_opnd, (RARRAY_EMBED_LEN_MASK as u64).into());
    let emb_len_opnd = asm.rshift(emb_len_opnd, (RARRAY_EMBED_LEN_SHIFT as u64).into());

    // Conditionally move the length of the heap array
    let flags_opnd = Opnd::mem((8 * SIZEOF_VALUE) as u8, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags_opnd, (RARRAY_EMBED_FLAG as u64).into());
    let array_len_opnd = Opnd::mem(
        (8 * size_of::<std::os::raw::c_long>()) as u8,
        asm.load(array_opnd),
        RUBY_OFFSET_RARRAY_AS_HEAP_LEN,
    );
    let array_len_opnd = asm.csel_nz(emb_len_opnd, array_len_opnd);

    // Only handle the case where the number of values in the array is equal to the number requested
    asm.cmp(array_len_opnd, required_args.into());
    asm.jne(counted_exit!(ocb, side_exit, send_splatarray_length_not_equal).into());

    let array_opnd = ctx.stack_pop(1);

    if required_args > 0 {

        // Load the address of the embedded array
        // (struct RArray *)(obj)->as.ary
        let array_reg = asm.load(array_opnd);
        let ary_opnd = asm.lea(Opnd::mem((8 * SIZEOF_VALUE) as u8, array_reg, RUBY_OFFSET_RARRAY_AS_ARY));

        // Conditionally load the address of the heap array
        // (struct RArray *)(obj)->as.heap.ptr
        let flags_opnd = Opnd::mem((8 * SIZEOF_VALUE) as u8, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
        asm.test(flags_opnd, Opnd::UImm(RARRAY_EMBED_FLAG as u64));
        let heap_ptr_opnd = Opnd::mem(
            (8 * size_of::<usize>()) as u8,
            asm.load(array_opnd),
            RUBY_OFFSET_RARRAY_AS_HEAP_PTR,
        );

        let ary_opnd = asm.csel_nz(ary_opnd, heap_ptr_opnd);

        for i in 0..required_args as i32 {
            let top = ctx.stack_push(Type::Unknown);
            asm.mov(top, Opnd::mem(64, ary_opnd, i * (SIZEOF_VALUE as i32)));
        }
    }
}

fn gen_send_bmethod(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    block: Option<IseqPtr>,
    flags: u32,
    argc: i32,
) -> CodegenStatus {
    let procv = unsafe { rb_get_def_bmethod_proc((*cme).def) };

    let proc = unsafe { rb_yjit_get_proc_ptr(procv) };
    let proc_block = unsafe { &(*proc).block };

    if proc_block.type_ != block_type_iseq {
        return CantCompile;
    }

    let capture = unsafe { proc_block.as_.captured.as_ref() };
    let iseq = unsafe { *capture.code.iseq.as_ref() };

    // Optimize for single ractor mode and avoid runtime check for
    // "defined with an un-shareable Proc in a different Ractor"
    if !assume_single_ractor_mode(jit, ocb) {
        gen_counter_incr!(asm, send_bmethod_ractor);
        return CantCompile;
    }

    // Passing a block to a block needs logic different from passing
    // a block to a method and sometimes requires allocation. Bail for now.
    if block.is_some() {
        gen_counter_incr!(asm, send_bmethod_block_arg);
        return CantCompile;
    }

    let frame_type = VM_FRAME_MAGIC_BLOCK | VM_FRAME_FLAG_BMETHOD | VM_FRAME_FLAG_LAMBDA;
    gen_send_iseq(jit, ctx, asm, ocb, iseq, ci, frame_type, Some(capture.ep), cme, block, flags, argc, None)
}

fn gen_send_iseq(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    iseq: *const rb_iseq_t,
    ci: *const rb_callinfo,
    frame_type: u32,
    prev_ep: Option<*const VALUE>,
    cme: *const rb_callable_method_entry_t,
    block: Option<IseqPtr>,
    flags: u32,
    argc: i32,
    captured_opnd: Option<Opnd>,
) -> CodegenStatus {
    let mut argc = argc;

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);

    // When you have keyword arguments, there is an extra object that gets
    // placed on the stack the represents a bitmap of the keywords that were not
    // specified at the call site. We need to keep track of the fact that this
    // value is present on the stack in order to properly set up the callee's
    // stack pointer.
    let doing_kw_call = unsafe { get_iseq_flags_has_kw(iseq) };
    let supplying_kws = unsafe { vm_ci_flag(ci) & VM_CALL_KWARG } != 0;

    if unsafe { vm_ci_flag(ci) } & VM_CALL_TAILCALL != 0 {
        // We can't handle tailcalls
        gen_counter_incr!(asm, send_iseq_tailcall);
        return CantCompile;
    }

    // No support for callees with these parameters yet as they require allocation
    // or complex handling.
    if unsafe { get_iseq_flags_has_rest(iseq) } {
        gen_counter_incr!(asm, send_iseq_has_rest);
        return CantCompile;
    }
    if unsafe { get_iseq_flags_has_post(iseq) } {
        gen_counter_incr!(asm, send_iseq_has_post);
        return CantCompile;
    }
    if unsafe { get_iseq_flags_has_kwrest(iseq) } {
        gen_counter_incr!(asm, send_iseq_has_kwrest);
        return CantCompile;
    }

    // In order to handle backwards compatibility between ruby 3 and 2
    // ruby2_keywords was introduced. It is called only on methods
    // with splat and changes they way they handle them.
    // We are just going to not compile these.
    // https://www.rubydoc.info/stdlib/core/Proc:ruby2_keywords
    if unsafe {
        get_iseq_flags_ruby2_keywords(jit.iseq) && flags & VM_CALL_ARGS_SPLAT != 0
    } {
        gen_counter_incr!(asm, send_iseq_ruby2_keywords);
        return CantCompile;
    }

    // If we have keyword arguments being passed to a callee that only takes
    // positionals, then we need to allocate a hash. For now we're going to
    // call that too complex and bail.
    if supplying_kws && !unsafe { get_iseq_flags_has_kw(iseq) } {
        gen_counter_incr!(asm, send_iseq_has_no_kw);
        return CantCompile;
    }

    // If we have a method accepting no kwargs (**nil), exit if we have passed
    // it any kwargs.
    if supplying_kws && unsafe { get_iseq_flags_accepts_no_kwarg(iseq) } {
        gen_counter_incr!(asm, send_iseq_accepts_no_kwarg);
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
            gen_counter_incr!(asm, send_iseq_materialized_block);
            return CantCompile;
        }
    }


    if flags & VM_CALL_ARGS_SPLAT != 0 && flags & VM_CALL_ZSUPER != 0 {
        // zsuper methods are super calls without any arguments.
        // They are also marked as splat, but don't actually have an array
        // they pull arguments from, instead we need to change to call
        // a different method with the current stack.
        gen_counter_incr!(asm, send_iseq_zsuper);
        return CantCompile;
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


    if opt_num > 0 && flags & VM_CALL_ARGS_SPLAT != 0 {
        gen_counter_incr!(asm, send_iseq_splat_with_opt);
        return CantCompile;
    }

    if doing_kw_call && flags & VM_CALL_ARGS_SPLAT != 0 {
        gen_counter_incr!(asm, send_iseq_splat_with_kw);
        return CantCompile;
    }

    if opts_filled < 0 && flags & VM_CALL_ARGS_SPLAT == 0  {
        // Too few arguments and no splat to make up for it
        gen_counter_incr!(asm, send_iseq_arity_error);
        return CantCompile;
    }

    if opts_filled > opt_num {
        // Too many arguments
        gen_counter_incr!(asm, send_iseq_arity_error);
        return CantCompile;
    }

    let block_arg = flags & VM_CALL_ARGS_BLOCKARG != 0;
    let block_arg_type = if block_arg {
        Some(ctx.get_opnd_type(StackOpnd(0)))
    } else {
        None
    };

    match block_arg_type {
        Some(Type::Nil | Type::BlockParamProxy) => {
            // We'll handle this later
        }
        None => {
            // Nothing to do
        }
        _ => {
            gen_counter_incr!(asm, send_block_arg);
            return CantCompile;
        }
    }

    // If we have unfilled optional arguments and keyword arguments then we
    // would need to adjust the arguments location to account for that.
    // For now we aren't handling this case.
    if doing_kw_call && opts_missing > 0 {
        gen_counter_incr!(asm, send_iseq_missing_optional_kw);
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
            gen_counter_incr!(asm, send_iseq_too_many_kwargs);
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
                        gen_counter_incr!(asm, send_iseq_kwargs_mismatch);
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
            gen_counter_incr!(asm, send_iseq_kwargs_mismatch);
            return CantCompile;
        }
    }

    // Number of locals that are not parameters
    let num_locals = unsafe { get_iseq_body_local_table_size(iseq) as i32 } - (num_params as i32);

    // Check for interrupts
    gen_check_ints(asm, side_exit);

    match block_arg_type {
        Some(Type::Nil) => {
            // We have a nil block arg, so let's pop it off the args
            ctx.stack_pop(1);
        }
        Some(Type::BlockParamProxy) => {
            // We don't need the actual stack value
            ctx.stack_pop(1);
        }
        None => {
            // Nothing to do
        }
        _ => {
            assert!(false);
        }
    }

    let leaf_builtin_raw = unsafe { rb_leaf_builtin_function(iseq) };
    let leaf_builtin: Option<*const rb_builtin_function> = if leaf_builtin_raw.is_null() {
        None
    } else {
        Some(leaf_builtin_raw)
    };
    if let (None, Some(builtin_info)) = (block, leaf_builtin) {

        // this is a .send call not currently supported for builtins
        if flags & VM_CALL_OPT_SEND != 0 {
            gen_counter_incr!(asm, send_send_builtin);
            return CantCompile;
        }

        let builtin_argc = unsafe { (*builtin_info).argc };
        if builtin_argc + 1 < (C_ARG_OPNDS.len() as i32) {
            asm.comment("inlined leaf builtin");

            // Save the PC and SP because the callee may allocate
            // e.g. Integer#abs on a bignum
            jit_prepare_routine_call(jit, ctx, asm);

            // Call the builtin func (ec, recv, arg1, arg2, ...)
            let mut args = vec![EC];

            // Copy self and arguments
            for i in 0..=builtin_argc {
                let stack_opnd = ctx.stack_opnd(builtin_argc - i);
                args.push(stack_opnd);
            }
            ctx.stack_pop((builtin_argc + 1).try_into().unwrap());
            let val = asm.ccall(unsafe { (*builtin_info).func_ptr as *const u8 }, args);

            // Push the return value
            let stack_ret = ctx.stack_push(Type::Unknown);
            asm.mov(stack_ret, val);

            // Note: assuming that the leaf builtin doesn't change local variables here.
            // Seems like a safe assumption.

            return KeepCompiling;
        }
    }

    // Stack overflow check
    // Note that vm_push_frame checks it against a decremented cfp, hence the multiply by 2.
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    asm.comment("stack overflow check");
    let stack_max: i32 = unsafe { get_iseq_body_stack_max(iseq) }.try_into().unwrap();
    let locals_offs =
        (SIZEOF_VALUE as i32) * (num_locals + stack_max) + 2 * (RUBY_SIZEOF_CONTROL_FRAME as i32);
    let stack_limit = asm.lea(ctx.sp_opnd(locals_offs as isize));
    asm.cmp(CFP, stack_limit);
    asm.jbe(counted_exit!(ocb, side_exit, send_se_cf_overflow).as_side_exit());

    // push_splat_args does stack manipulation so we can no longer side exit
    if flags & VM_CALL_ARGS_SPLAT != 0 {
        let required_args = num_params as i32 - (argc - 1);
        // We are going to assume that the splat fills
        // all the remaining arguments. In the generated code
        // we test if this is true and if not side exit.
        argc = num_params as i32;
        push_splat_args(required_args, ctx, asm, ocb, side_exit)
    }

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc as i32, ctx);
    }

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

        asm.comment("keyword args");

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

                asm.mov(default_arg, default_value.into());

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
                    stack_swap(jit, ctx, asm, offset0, offset1);

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
        let unspec_opnd = VALUE::fixnum_from_usize(unspecified_bits).as_u64();
        asm.mov(ctx.stack_opnd(-1), unspec_opnd.into());
    }

    // Points to the receiver operand on the stack unless a captured environment is used
    let recv = match captured_opnd {
        Some(captured_opnd) => asm.load(Opnd::mem(64, captured_opnd, 0)), // captured->self
        _ => ctx.stack_opnd(argc),
    };
    let captured_self = captured_opnd.is_some();
    let sp_offset = (argc as isize) + if captured_self { 0 } else { 1 };

    // Store the updated SP on the current frame (pop arguments and receiver)
    asm.comment("store caller sp");
    let caller_sp = asm.lea(ctx.sp_opnd((SIZEOF_VALUE as isize) * -sp_offset));
    asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP), caller_sp);

    // Store the next PC in the current frame
    jit_save_pc(jit, asm);

    // Adjust the callee's stack pointer
    let offs =
        (SIZEOF_VALUE as isize) * (3 + (num_locals as isize) + if doing_kw_call { 1 } else { 0 });
    let callee_sp = asm.lea(ctx.sp_opnd(offs));

    let specval = if let Some(prev_ep) = prev_ep {
        // We've already side-exited if the callee expects a block, so we
        // ignore any supplied block here
        SpecVal::PrevEP(prev_ep)
    } else if let Some(captured_opnd) = captured_opnd {
        let ep_opnd = asm.load(Opnd::mem(64, captured_opnd, SIZEOF_VALUE_I32)); // captured->ep
        SpecVal::PrevEPOpnd(ep_opnd)
    } else if block_arg_type == Some(Type::BlockParamProxy) {
        SpecVal::BlockParamProxy
    } else if let Some(block_val) = block {
        SpecVal::BlockISeq(block_val)
    } else {
        SpecVal::None
    };

    // Setup the new frame
    gen_push_frame(jit, ctx, asm, true, ControlFrame {
        frame_type,
        specval,
        cme,
        recv,
        sp: callee_sp,
        iseq: Some(iseq),
        pc: None, // We are calling into jitted code, which will set the PC as necessary
        local_size: num_locals
    });

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
    let mut callee_ctx = Context::default();

    // Set the argument types in the callee's context
    for arg_idx in 0..argc {
        let stack_offs: u16 = (argc - arg_idx - 1).try_into().unwrap();
        let arg_type = ctx.get_opnd_type(StackOpnd(stack_offs));
        callee_ctx.set_local_type(arg_idx.try_into().unwrap(), arg_type);
    }

    let recv_type = if captured_self {
        Type::Unknown // we don't track the type information of captured->self for now
    } else {
        ctx.get_opnd_type(StackOpnd(argc.try_into().unwrap()))
    };
    callee_ctx.upgrade_opnd_type(SelfOpnd, recv_type);

    // The callee might change locals through Kernel#binding and other means.
    ctx.clear_local_types();

    // Pop arguments and receiver in return context, push the return value
    // After the return, sp_offset will be 1. The codegen for leave writes
    // the return value in case of JIT-to-JIT return.
    let mut return_ctx = ctx.clone();
    return_ctx.stack_pop(sp_offset.try_into().unwrap());
    return_ctx.stack_push(Type::Unknown);
    return_ctx.set_sp_offset(1);
    return_ctx.reset_chain_depth();

    // Write the JIT return address on the callee frame
    gen_branch(
        jit,
        asm,
        ocb,
        return_block,
        &return_ctx,
        None,
        None,
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
        asm,
    );

    EndBlock
}

fn gen_struct_aref(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    comptime_recv: VALUE,
    _comptime_recv_klass: VALUE,
    flags: u32,
    argc: i32,
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

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc as i32, ctx);
    }

    // All structs from the same Struct class should have the same
    // length. So if our comptime_recv is embedded all runtime
    // structs of the same class should be as well, and the same is
    // true of the converse.
    let embedded = unsafe { FL_TEST_RAW(comptime_recv, VALUE(RSTRUCT_EMBED_LEN_MASK)) };

    asm.comment("struct aref");

    let recv = asm.load(ctx.stack_pop(1));

    let val = if embedded != VALUE(0) {
        Opnd::mem(64, recv, RUBY_OFFSET_RSTRUCT_AS_ARY + ((SIZEOF_VALUE as i32) * off))
    } else {
        let rstruct_ptr = asm.load(Opnd::mem(64, recv, RUBY_OFFSET_RSTRUCT_AS_HEAP_PTR));
        Opnd::mem(64, rstruct_ptr, (SIZEOF_VALUE as i32) * off)
    };

    let ret = ctx.stack_push(Type::Unknown);
    asm.mov(ret, val);

    jump_to_next_insn(jit, ctx, asm, ocb);
    EndBlock
}

fn gen_struct_aset(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    comptime_recv: VALUE,
    _comptime_recv_klass: VALUE,
    flags: u32,
    argc: i32,
) -> CodegenStatus {
    if unsafe { vm_ci_argc(ci) } != 1 {
        return CantCompile;
    }

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc, ctx);
    }

    let off: i32 = unsafe { get_cme_def_body_optimized_index(cme) }
        .try_into()
        .unwrap();

    // Confidence checks
    assert!(unsafe { RB_TYPE_P(comptime_recv, RUBY_T_STRUCT) });
    assert!((off as i64) < unsafe { RSTRUCT_LEN(comptime_recv) });

    asm.comment("struct aset");

    let val = ctx.stack_pop(1);
    let recv = ctx.stack_pop(1);

    let val = asm.ccall(RSTRUCT_SET as *const u8, vec![recv, (off as i64).into(), val]);

    let ret = ctx.stack_push(Type::Unknown);
    asm.mov(ret, val);

    jump_to_next_insn(jit, ctx, asm, ocb);
    EndBlock
}

fn gen_send_general(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
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
    let mut argc: i32 = unsafe { vm_ci_argc(ci) }.try_into().unwrap();
    let mut mid = unsafe { vm_ci_mid(ci) };
    let mut flags = unsafe { vm_ci_flag(ci) };

    // Don't JIT calls with keyword splat
    if flags & VM_CALL_KW_SPLAT != 0 {
        gen_counter_incr!(asm, send_kw_splat);
        return CantCompile;
    }

    // Defer compilation so we can specialize on class of receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    let recv_idx = argc + if flags & VM_CALL_ARGS_BLOCKARG != 0 { 1 } else { 0 };

    let comptime_recv = jit_peek_at_stack(jit, ctx, recv_idx as isize);
    let comptime_recv_klass = comptime_recv.class_of();

    // Guard that the receiver has the same class as the one from compile time
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Points to the receiver operand on the stack
    let recv = ctx.stack_opnd(recv_idx);
    let recv_opnd = StackOpnd(recv_idx.try_into().unwrap());
    jit_guard_known_klass(
        jit,
        ctx,
        asm,
        ocb,
        comptime_recv_klass,
        recv,
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
            // If the method call is an FCALL, it is always valid
            if flags & VM_CALL_FCALL == 0 {
                // otherwise we need an ancestry check to ensure the receiver is vaild to be called
                // as protected
                jit_protected_callee_ancestry_guard(jit, asm, ocb, cme, side_exit);
            }
        }
        _ => {
            panic!("cmes should always have a visibility!");
        }
    }

    // Register block for invalidation
    //assert!(cme->called_id == mid);
    assume_method_lookup_stable(jit, ocb, cme);

    // To handle the aliased method case (VM_METHOD_TYPE_ALIAS)
    loop {
        let def_type = unsafe { get_cme_def_type(cme) };

        if flags & VM_CALL_ARGS_SPLAT != 0 && def_type != VM_METHOD_TYPE_ISEQ  {
            gen_counter_incr!(asm, send_args_splat_non_iseq);
            return CantCompile;
        }

        match def_type {
            VM_METHOD_TYPE_ISEQ => {
                let iseq = unsafe { get_def_iseq_ptr((*cme).def) };
                let frame_type = VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL;
                return gen_send_iseq(jit, ctx, asm, ocb, iseq, ci, frame_type, None, cme, block, flags, argc, None);
            }
            VM_METHOD_TYPE_CFUNC => {
                return gen_send_cfunc(
                    jit,
                    ctx,
                    asm,
                    ocb,
                    ci,
                    cme,
                    block,
                    &comptime_recv_klass,
                    flags,
                    argc,
                );
            }
            VM_METHOD_TYPE_IVAR => {
                if argc != 0 {
                    // Argument count mismatch. Getters take no arguments.
                    gen_counter_incr!(asm, send_getter_arity);
                    return CantCompile;
                }

                // This is a .send call not supported right now for getters
                if flags & VM_CALL_OPT_SEND != 0 {
                    gen_counter_incr!(asm, send_send_getter);
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
                    gen_counter_incr!(asm, send_cfunc_tracing);
                    return CantCompile;
                }

                let ivar_name = unsafe { get_cme_def_body_attr_id(cme) };

                if flags & VM_CALL_ARGS_BLOCKARG != 0 {
                    gen_counter_incr!(asm, send_block_arg);
                    return CantCompile;
                }

                return gen_get_ivar(
                    jit,
                    ctx,
                    asm,
                    ocb,
                    SEND_MAX_DEPTH,
                    comptime_recv,
                    ivar_name,
                    recv,
                    recv_opnd,
                    side_exit,
                );
            }
            VM_METHOD_TYPE_ATTRSET => {
                if flags & VM_CALL_KWARG != 0 {
                    gen_counter_incr!(asm, send_attrset_kwargs);
                    return CantCompile;
                } else if argc != 1 || unsafe { !RB_TYPE_P(comptime_recv, RUBY_T_OBJECT) } {
                    gen_counter_incr!(asm, send_ivar_set_method);
                    return CantCompile;
                } else if c_method_tracing_currently_enabled(jit) {
                    // Can't generate code for firing c_call and c_return events
                    // See :attr-tracing:
                    gen_counter_incr!(asm, send_cfunc_tracing);
                    return CantCompile;
                } else if flags & VM_CALL_ARGS_BLOCKARG != 0 {
                    gen_counter_incr!(asm, send_block_arg);
                    return CantCompile;
                } else {
                    let ivar_name = unsafe { get_cme_def_body_attr_id(cme) };
                    return gen_set_ivar(jit, ctx, asm, comptime_recv, ivar_name, flags, argc);
                }
            }
            // Block method, e.g. define_method(:foo) { :my_block }
            VM_METHOD_TYPE_BMETHOD => {
                return gen_send_bmethod(jit, ctx, asm, ocb, ci, cme, block, flags, argc);
            }
            VM_METHOD_TYPE_ZSUPER => {
                gen_counter_incr!(asm, send_zsuper_method);
                return CantCompile;
            }
            VM_METHOD_TYPE_ALIAS => {
                // Retrieve the aliased method and re-enter the switch
                cme = unsafe { rb_aliased_callable_method_entry(cme) };
                continue;
            }
            VM_METHOD_TYPE_UNDEF => {
                gen_counter_incr!(asm, send_undef_method);
                return CantCompile;
            }
            VM_METHOD_TYPE_NOTIMPLEMENTED => {
                gen_counter_incr!(asm, send_not_implemented_method);
                return CantCompile;
            }
            // Send family of methods, e.g. call/apply
            VM_METHOD_TYPE_OPTIMIZED => {
                if flags & VM_CALL_ARGS_BLOCKARG != 0 {
                    gen_counter_incr!(asm, send_block_arg);
                    return CantCompile;
                }

                let opt_type = unsafe { get_cme_def_body_optimized_type(cme) };
                match opt_type {
                    OPTIMIZED_METHOD_TYPE_SEND => {
                        // This is for method calls like `foo.send(:bar)`
                        // The `send` method does not get its own stack frame.
                        // instead we look up the method and call it,
                        // doing some stack shifting based on the VM_CALL_OPT_SEND flag

                        let starting_context = ctx.clone();

                        // Reject nested cases such as `send(:send, :alias_for_send, :foo))`.
                        // We would need to do some stack manipulation here or keep track of how
                        // many levels deep we need to stack manipulate. Because of how exits
                        // currently work, we can't do stack manipulation until we will no longer
                        // side exit.
                        if flags & VM_CALL_OPT_SEND != 0 {
                            gen_counter_incr!(asm, send_send_nested);
                            return CantCompile;
                        }

                        if argc == 0 {
                            gen_counter_incr!(asm, send_send_wrong_args);
                            return CantCompile;
                        }

                        argc -= 1;

                        let compile_time_name = jit_peek_at_stack(jit, ctx, argc as isize);

                        if !compile_time_name.string_p() && !compile_time_name.static_sym_p()  {
                            gen_counter_incr!(asm, send_send_chain_not_string_or_sym);
                            return CantCompile;
                        }

                        mid = unsafe { rb_get_symbol_id(compile_time_name) };
                        if mid == 0 {
                            gen_counter_incr!(asm, send_send_null_mid);
                            return CantCompile;
                        }

                        cme = unsafe { rb_callable_method_entry(comptime_recv_klass, mid) };
                        if cme.is_null() {
                            gen_counter_incr!(asm, send_send_null_cme);
                            return CantCompile;
                        }

                        flags |= VM_CALL_FCALL | VM_CALL_OPT_SEND;

                        assume_method_lookup_stable(jit, ocb, cme);

                        let (known_class, type_mismatch_exit) = {
                            if compile_time_name.string_p() {
                                (
                                    unsafe { rb_cString },
                                    counted_exit!(ocb, side_exit, send_send_chain_not_string),

                                )
                            } else {
                                (
                                    unsafe { rb_cSymbol },
                                    counted_exit!(ocb, side_exit, send_send_chain_not_sym),
                                )
                            }
                        };

                        jit_guard_known_klass(
                            jit,
                            ctx,
                            asm,
                            ocb,
                            known_class,
                            ctx.stack_opnd(argc),
                            StackOpnd(argc as u16),
                            compile_time_name,
                            2, // We have string or symbol, so max depth is 2
                            type_mismatch_exit
                        );

                        // Need to do this here so we don't have too many live
                        // values for the register allocator.
                        let name_opnd = asm.load(ctx.stack_opnd(argc));

                        let symbol_id_opnd = asm.ccall(rb_get_symbol_id as *const u8, vec![name_opnd]);

                        asm.comment("chain_guard_send");
                        let chain_exit = counted_exit!(ocb, side_exit, send_send_chain);
                        asm.cmp(symbol_id_opnd, 0.into());
                        asm.jbe(chain_exit.into());

                        asm.cmp(symbol_id_opnd, mid.into());
                        jit_chain_guard(
                            JCC_JNE,
                            jit,
                            &starting_context,
                            asm,
                            ocb,
                            SEND_MAX_CHAIN_DEPTH as i32,
                            chain_exit,
                        );

                        // We have changed the argc, flags, mid, and cme, so we need to re-enter the match
                        // and compile whatever method we found from send.
                        continue;

                    }
                    OPTIMIZED_METHOD_TYPE_CALL => {

                        if block.is_some() {
                            gen_counter_incr!(asm, send_call_block);
                            return CantCompile;
                        }

                        if flags & VM_CALL_KWARG != 0 {
                            gen_counter_incr!(asm, send_call_kwarg);
                            return CantCompile;
                        }

                        // Optimize for single ractor mode and avoid runtime check for
                        // "defined with an un-shareable Proc in a different Ractor"
                        if !assume_single_ractor_mode(jit, ocb) {
                            gen_counter_incr!(asm, send_call_multi_ractor);
                            return CantCompile;
                        }

                        // If this is a .send call we need to adjust the stack
                        if flags & VM_CALL_OPT_SEND != 0 {
                            handle_opt_send_shift_stack(asm, argc as i32, ctx);
                        }

                        // About to reset the SP, need to load this here
                        let recv_load = asm.load(recv);

                        let sp = asm.lea(ctx.sp_opnd(0));

                        // Save the PC and SP because the callee can make Ruby calls
                        jit_prepare_routine_call(jit, ctx, asm);

                        let kw_splat = flags & VM_CALL_KW_SPLAT;
                        let stack_argument_pointer = asm.lea(Opnd::mem(64, sp, -(argc) * SIZEOF_VALUE_I32));

                        let ret = asm.ccall(rb_optimized_call as *const u8, vec![
                            recv_load,
                            EC,
                            argc.into(),
                            stack_argument_pointer,
                            kw_splat.into(),
                            VM_BLOCK_HANDLER_NONE.into(),
                        ]);

                        ctx.stack_pop(argc as usize + 1);

                        let stack_ret = ctx.stack_push(Type::Unknown);
                        asm.mov(stack_ret, ret);
                        return KeepCompiling;

                    }
                    OPTIMIZED_METHOD_TYPE_BLOCK_CALL => {
                        gen_counter_incr!(asm, send_optimized_method_block_call);
                        return CantCompile;
                    }
                    OPTIMIZED_METHOD_TYPE_STRUCT_AREF => {
                        return gen_struct_aref(
                            jit,
                            ctx,
                            asm,
                            ocb,
                            ci,
                            cme,
                            comptime_recv,
                            comptime_recv_klass,
                            flags,
                            argc,
                        );
                    }
                    OPTIMIZED_METHOD_TYPE_STRUCT_ASET => {
                        return gen_struct_aset(
                            jit,
                            ctx,
                            asm,
                            ocb,
                            ci,
                            cme,
                            comptime_recv,
                            comptime_recv_klass,
                            flags,
                            argc,
                        );
                    }
                    _ => {
                        panic!("unknown optimized method type!")
                    }
                }
            }
            VM_METHOD_TYPE_MISSING => {
                gen_counter_incr!(asm, send_missing_method);
                return CantCompile;
            }
            VM_METHOD_TYPE_REFINED => {
                gen_counter_incr!(asm, send_refined_method);
                return CantCompile;
            }
            _ => {
                unreachable!();
            }
        }
    }
}


/// Shifts the stack for send in order to remove the name of the method
/// Comment below borrow from vm_call_opt_send in vm_insnhelper.c
/// E.g. when argc == 2
///  |      |        |      |  TOPN
///  +------+        |      |
///  | arg1 | ---+   |      |    0
///  +------+    |   +------+
///  | arg0 | -+ +-> | arg1 |    1
///  +------+  |     +------+
///  | sym  |  +---> | arg0 |    2
///  +------+        +------+
///  | recv |        | recv |    3
///--+------+--------+------+------
///
/// We do this for our compiletime context and the actual stack
fn handle_opt_send_shift_stack(asm: &mut Assembler, argc: i32, ctx: &mut Context) {
    asm.comment("shift_stack");
    for j in (0..argc).rev() {
        let opnd = ctx.stack_opnd(j);
        let opnd2 = ctx.stack_opnd(j + 1);
        asm.mov(opnd2, opnd);
    }
    ctx.shift_stack(argc as usize);
}

fn gen_opt_send_without_block(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let cd = jit_get_arg(jit, 0).as_ptr();

    gen_send_general(jit, ctx, asm, ocb, cd, None)
}

fn gen_send(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let cd = jit_get_arg(jit, 0).as_ptr();
    let block = jit_get_arg(jit, 1).as_optional_ptr();
    return gen_send_general(jit, ctx, asm, ocb, cd, block);
}

fn gen_invokeblock(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    // Get call info
    let cd = jit_get_arg(jit, 0).as_ptr();
    let ci = unsafe { get_call_data_ci(cd) };
    let argc: i32 = unsafe { vm_ci_argc(ci) }.try_into().unwrap();
    let flags = unsafe { vm_ci_flag(ci) };

    // Get block_handler
    let cfp = unsafe { get_ec_cfp(jit.ec.unwrap()) };
    let lep = unsafe { rb_vm_ep_local_ep(get_cfp_ep(cfp)) };
    let comptime_handler = unsafe { *lep.offset(VM_ENV_DATA_INDEX_SPECVAL.try_into().unwrap()) };

    // Handle each block_handler type
    if comptime_handler.0 == VM_BLOCK_HANDLER_NONE as usize { // no block given
        gen_counter_incr!(asm, invokeblock_none);
        CantCompile
    } else if comptime_handler.0 & 0x3 == 0x1 { // VM_BH_ISEQ_BLOCK_P
        asm.comment("get local EP");
        let ep_opnd = gen_get_lep(jit, asm);
        let block_handler_opnd = asm.load(
            Opnd::mem(64, ep_opnd, (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32))
        );

        asm.comment("guard block_handler type");
        let side_exit = get_side_exit(jit, ocb, ctx);
        let tag_opnd = asm.and(block_handler_opnd, 0x3.into()); // block_handler is a tagged pointer
        asm.cmp(tag_opnd, 0x1.into()); // VM_BH_ISEQ_BLOCK_P
        asm.jne(counted_exit!(ocb, side_exit, invokeblock_iseq_tag_changed).into());

        // Not supporting vm_callee_setup_block_arg_arg0_splat for now
        let comptime_captured = unsafe { ((comptime_handler.0 & !0x3) as *const rb_captured_block).as_ref().unwrap() };
        let comptime_iseq = unsafe { *comptime_captured.code.iseq.as_ref() };
        if argc == 1 && unsafe {
                (get_iseq_flags_has_lead(comptime_iseq) || get_iseq_body_param_opt_num(comptime_iseq) > 1) &&
                !get_iseq_flags_ambiguous_param0(comptime_iseq) } {
            gen_counter_incr!(asm, invokeblock_iseq_arg0_splat);
            return CantCompile;
        }

        asm.comment("guard known ISEQ");
        let captured_opnd = asm.and(block_handler_opnd, Opnd::Imm(!0x3));
        let iseq_opnd = asm.load(Opnd::mem(64, captured_opnd, SIZEOF_VALUE_I32 * 2));
        asm.cmp(iseq_opnd, (comptime_iseq as usize).into());
        let block_changed_exit = counted_exit!(ocb, side_exit, invokeblock_iseq_block_changed);
        jit_chain_guard(
            JCC_JNE,
            jit,
            ctx,
            asm,
            ocb,
            SEND_MAX_CHAIN_DEPTH,
            block_changed_exit,
        );

        gen_send_iseq(
            jit,
            ctx,
            asm,
            ocb,
            comptime_iseq,
            ci,
            VM_FRAME_MAGIC_BLOCK,
            None,
            0 as _,
            None,
            flags,
            argc,
            Some(captured_opnd),
        )
    } else if comptime_handler.0 & 0x3 == 0x3 { // VM_BH_IFUNC_P
        gen_counter_incr!(asm, invokeblock_ifunc);
        CantCompile
    } else if comptime_handler.symbol_p() {
        gen_counter_incr!(asm, invokeblock_symbol);
        CantCompile
    } else { // Proc
        gen_counter_incr!(asm, invokeblock_proc);
        CantCompile
    }
}

fn gen_invokesuper(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let cd: *const rb_call_data = jit_get_arg(jit, 0).as_ptr();
    let block: Option<IseqPtr> = jit_get_arg(jit, 1).as_optional_ptr();

    // Defer compilation so we can specialize on class of receiver
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
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
    let argc: i32 = unsafe { vm_ci_argc(ci) }.try_into().unwrap();

    let ci_flags = unsafe { vm_ci_flag(ci) };

    // Don't JIT calls that aren't simple
    // Note, not using VM_CALL_ARGS_SIMPLE because sometimes we pass a block.

    if ci_flags & VM_CALL_KWARG != 0 {
        gen_counter_incr!(asm, send_keywords);
        return CantCompile;
    }
    if ci_flags & VM_CALL_KW_SPLAT != 0 {
        gen_counter_incr!(asm, send_kw_splat);
        return CantCompile;
    }
    if ci_flags & VM_CALL_ARGS_BLOCKARG != 0 {
        gen_counter_incr!(asm, send_block_arg);
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

    asm.comment("guard known me");
    let ep_opnd = asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP));
    let ep_me_opnd = Opnd::mem(
        64,
        ep_opnd,
        (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_ME_CREF as i32),
    );
    asm.cmp(ep_me_opnd, me_as_value.into());
    asm.jne(counted_exit!(ocb, side_exit, invokesuper_me_changed).into());

    if block.is_none() {
        // Guard no block passed
        // rb_vm_frame_block_handler(GET_EC()->cfp) == VM_BLOCK_HANDLER_NONE
        // note, we assume VM_ASSERT(VM_ENV_LOCAL_P(ep))
        //
        // TODO: this could properly forward the current block handler, but
        // would require changes to gen_send_*
        asm.comment("guard no block given");
        // EP is in REG0 from above
        let ep_opnd = asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP));
        let ep_specval_opnd = Opnd::mem(
            64,
            ep_opnd,
            (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32),
        );
        asm.cmp(ep_specval_opnd, VM_BLOCK_HANDLER_NONE.into());
        asm.jne(counted_exit!(ocb, side_exit, invokesuper_block).into());
    }

    // We need to assume that both our current method entry and the super
    // method entry we invoke remain stable
    assume_method_lookup_stable(jit, ocb, me);
    assume_method_lookup_stable(jit, ocb, cme);

    // Method calls may corrupt types
    ctx.clear_local_types();

    match cme_def_type {
        VM_METHOD_TYPE_ISEQ => {
            let iseq = unsafe { get_def_iseq_ptr((*cme).def) };
            let frame_type = VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL;
            gen_send_iseq(jit, ctx, asm, ocb, iseq, ci, frame_type, None, cme, block, ci_flags, argc, None)
        }
        VM_METHOD_TYPE_CFUNC => {
            gen_send_cfunc(jit, ctx, asm, ocb, ci, cme, block, ptr::null(), ci_flags, argc)
        }
        _ => unreachable!(),
    }
}

fn gen_leave(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Only the return value should be on the stack
    assert_eq!(1, ctx.get_stack_size());

    // Create a side-exit to fall back to the interpreter
    let side_exit = get_side_exit(jit, ocb, ctx);
    let ocb_asm = Assembler::new();

    // Check for interrupts
    gen_check_ints(asm, counted_exit!(ocb, side_exit, leave_se_interrupt));
    ocb_asm.compile(ocb.unwrap());

    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    asm.comment("pop stack frame");
    let incr_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, incr_cfp);
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // Load the return value
    let retval_opnd = ctx.stack_pop(1);

    // Move the return value into the C return register for gen_leave_exit()
    asm.mov(C_RET_OPND, retval_opnd);

    // Reload REG_SP for the caller and write the return value.
    // Top of the stack is REG_SP[0] since the caller has sp_offset=1.
    asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));
    asm.mov(Opnd::mem(64, SP, 0), C_RET_OPND);

    // Jump to the JIT return address on the frame that was just popped
    let offset_to_jit_return =
        -(RUBY_SIZEOF_CONTROL_FRAME as i32) + (RUBY_OFFSET_CFP_JIT_RETURN as i32);
    asm.jmp_opnd(Opnd::mem(64, CFP, offset_to_jit_return));

    EndBlock
}

fn gen_getglobal(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let gid = jit_get_arg(jit, 0).as_usize();

    // Save the PC and SP because we might make a Ruby call for warning
    jit_prepare_routine_call(jit, ctx, asm);

    let val_opnd = asm.ccall(
        rb_gvar_get as *const u8,
        vec![ gid.into() ]
    );

    let top = ctx.stack_push(Type::Unknown);
    asm.mov(top, val_opnd);

    KeepCompiling
}

fn gen_setglobal(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let gid = jit_get_arg(jit, 0).as_usize();

    // Save the PC and SP because we might make a Ruby call for
    // Kernel#set_trace_var
    jit_prepare_routine_call(jit, ctx, asm);

    asm.ccall(
        rb_gvar_set as *const u8,
        vec![
            gid.into(),
            ctx.stack_pop(1),
        ],
    );

    KeepCompiling
}

fn gen_anytostring(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Save the PC and SP since we might call #to_s
    jit_prepare_routine_call(jit, ctx, asm);

    let str = ctx.stack_pop(1);
    let val = ctx.stack_pop(1);

    let val = asm.ccall(rb_obj_as_string_result as *const u8, vec![str, val]);

    // Push the return value
    let stack_ret = ctx.stack_push(Type::TString);
    asm.mov(stack_ret, val);

    KeepCompiling
}

fn gen_objtostring(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    let recv = ctx.stack_opnd(0);
    let comptime_recv = jit_peek_at_stack(jit, ctx, 0);

    if unsafe { RB_TYPE_P(comptime_recv, RUBY_T_STRING) } {
        let side_exit = get_side_exit(jit, ocb, ctx);

        jit_guard_known_klass(
            jit,
            ctx,
            asm,
            ocb,
            comptime_recv.class_of(),
            recv,
            StackOpnd(0),
            comptime_recv,
            SEND_MAX_DEPTH,
            side_exit,
        );
        // No work needed. The string value is already on the top of the stack.
        KeepCompiling
    } else {
        let cd = jit_get_arg(jit, 0).as_ptr();
        gen_send_general(jit, ctx, asm, ocb, cd, None)
    }
}

fn gen_intern(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // Save the PC and SP because we might allocate
    jit_prepare_routine_call(jit, ctx, asm);

    let str = ctx.stack_pop(1);
    let sym = asm.ccall(rb_str_intern as *const u8, vec![str]);

    // Push the return value
    let stack_ret = ctx.stack_push(Type::Unknown);
    asm.mov(stack_ret, sym);

    KeepCompiling
}

fn gen_toregexp(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let opt = jit_get_arg(jit, 0).as_i64();
    let cnt = jit_get_arg(jit, 1).as_usize();

    // Save the PC and SP because this allocates an object and could
    // raise an exception.
    jit_prepare_routine_call(jit, ctx, asm);

    let values_ptr = asm.lea(ctx.sp_opnd(-((SIZEOF_VALUE as isize) * (cnt as isize))));
    ctx.stack_pop(cnt);

    let ary = asm.ccall(
        rb_ary_tmp_new_from_values as *const u8,
        vec![
            Opnd::Imm(0),
            cnt.into(),
            values_ptr,
        ]
    );

    // Save the array so we can clear it later
    asm.cpush(ary);
    asm.cpush(ary); // Alignment

    let val = asm.ccall(
        rb_reg_new_ary as *const u8,
        vec![
            ary,
            Opnd::Imm(opt),
        ]
    );

    // The actual regex is in RAX now.  Pop the temp array from
    // rb_ary_tmp_new_from_values into C arg regs so we can clear it
    let ary = asm.cpop(); // Alignment
    asm.cpop_into(ary);

    // The value we want to push on the stack is in RAX right now
    let stack_ret = ctx.stack_push(Type::Unknown);
    asm.mov(stack_ret, val);

    // Clear the temp array.
    asm.ccall(rb_ary_clear as *const u8, vec![ary]);

    KeepCompiling
}

fn gen_getspecial(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
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
        jit_prepare_routine_call(jit, ctx, asm);

        // call rb_backref_get()
        asm.comment("rb_backref_get");
        let backref = asm.ccall(rb_backref_get as *const u8, vec![]);

        let rt_u8: u8 = (rtype >> 1).try_into().unwrap();
        let val = match rt_u8.into() {
            '&' => {
                asm.comment("rb_reg_last_match");
                asm.ccall(rb_reg_last_match as *const u8, vec![backref])
            }
            '`' => {
                asm.comment("rb_reg_match_pre");
                asm.ccall(rb_reg_match_pre as *const u8, vec![backref])
            }
            '\'' => {
                asm.comment("rb_reg_match_post");
                asm.ccall(rb_reg_match_post as *const u8, vec![backref])
            }
            '+' => {
                asm.comment("rb_reg_match_last");
                asm.ccall(rb_reg_match_last as *const u8, vec![backref])
            }
            _ => panic!("invalid back-ref"),
        };

        let stack_ret = ctx.stack_push(Type::Unknown);
        asm.mov(stack_ret, val);

        KeepCompiling
    } else {
        // Fetch the N-th match from the last backref based on type shifted by 1

        // Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, asm);

        // call rb_backref_get()
        asm.comment("rb_backref_get");
        let backref = asm.ccall(rb_backref_get as *const u8, vec![]);

        // rb_reg_nth_match((int)(type >> 1), backref);
        asm.comment("rb_reg_nth_match");
        let val = asm.ccall(
            rb_reg_nth_match as *const u8,
            vec![
                Opnd::Imm((rtype >> 1).try_into().unwrap()),
                backref,
            ]
        );

        let stack_ret = ctx.stack_push(Type::Unknown);
        asm.mov(stack_ret, val);

        KeepCompiling
    }
}

fn gen_getclassvariable(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // rb_vm_getclassvariable can raise exceptions.
    jit_prepare_routine_call(jit, ctx, asm);

    let val_opnd = asm.ccall(
        rb_vm_getclassvariable as *const u8,
        vec![
            Opnd::mem(64, CFP, RUBY_OFFSET_CFP_ISEQ),
            CFP,
            Opnd::UImm(jit_get_arg(jit, 0).as_u64()),
            Opnd::UImm(jit_get_arg(jit, 1).as_u64()),
        ],
    );

    let top = ctx.stack_push(Type::Unknown);
    asm.mov(top, val_opnd);

    KeepCompiling
}

fn gen_setclassvariable(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // rb_vm_setclassvariable can raise exceptions.
    jit_prepare_routine_call(jit, ctx, asm);

    asm.ccall(
        rb_vm_setclassvariable as *const u8,
        vec![
            Opnd::mem(64, CFP, RUBY_OFFSET_CFP_ISEQ),
            CFP,
            Opnd::UImm(jit_get_arg(jit, 0).as_u64()),
            ctx.stack_pop(1),
            Opnd::UImm(jit_get_arg(jit, 1).as_u64()),
        ],
    );

    KeepCompiling
}

fn gen_getconstant(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {

    let id = jit_get_arg(jit, 0).as_usize();

    // vm_get_ev_const can raise exceptions.
    jit_prepare_routine_call(jit, ctx, asm);

    let allow_nil_opnd = ctx.stack_pop(1);
    let klass_opnd = ctx.stack_pop(1);

    extern "C" {
        fn rb_vm_get_ev_const(ec: EcPtr, klass: VALUE, id: ID, allow_nil: VALUE) -> VALUE;
    }

    let val_opnd = asm.ccall(
        rb_vm_get_ev_const as *const u8,
        vec![
            EC,
            klass_opnd,
            id.into(),
            allow_nil_opnd
        ],
    );

    let top = ctx.stack_push(Type::Unknown);
    asm.mov(top, val_opnd);

    KeepCompiling
}

fn gen_opt_getconstant_path(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let const_cache_as_value = jit_get_arg(jit, 0);
    let ic: *const iseq_inline_constant_cache = const_cache_as_value.as_ptr();
    let idlist: *const ID = unsafe { (*ic).segments };

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

        let inline_cache = asm.load(Opnd::const_ptr(ic as *const u8));

        // Call function to verify the cache. It doesn't allocate or call methods.
        let ret_val = asm.ccall(
            rb_vm_ic_hit_p as *const u8,
            vec![inline_cache, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP)]
        );

        // Check the result. SysV only specifies one byte for _Bool return values,
        // so it's important we only check one bit to ignore the higher bits in the register.
        asm.test(ret_val, 1.into());
        asm.jz(counted_exit!(ocb, side_exit, opt_getinlinecache_miss).into());

        let inline_cache = asm.load(Opnd::const_ptr(ic as *const u8));

        let ic_entry = asm.load(Opnd::mem(
            64,
            inline_cache,
            RUBY_OFFSET_IC_ENTRY
        ));

        let ic_entry_val = asm.load(Opnd::mem(
            64,
            ic_entry,
            RUBY_OFFSET_ICE_VALUE
        ));

        // Push ic->entry->value
        let stack_top = ctx.stack_push(Type::Unknown);
        asm.store(stack_top, ic_entry_val);
    } else {
        // Optimize for single ractor mode.
        // FIXME: This leaks when st_insert raises NoMemoryError
        if !assume_single_ractor_mode(jit, ocb) {
            return CantCompile;
        }

        // Invalidate output code on any constant writes associated with
        // constants referenced within the current block.
        assume_stable_constant_names(jit, ocb, idlist);

        jit_putobject(jit, ctx, asm, unsafe { (*ice).value });
    }

    jump_to_next_insn(jit, ctx, asm, ocb);
    EndBlock
}

// Push the explicit block parameter onto the temporary stack. Part of the
// interpreter's scheme for avoiding Proc allocations when delegating
// explicit block parameters.
fn gen_getblockparamproxy(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    if !jit_at_current_insn(jit) {
        defer_compilation(jit, ctx, asm, ocb);
        return EndBlock;
    }

    let starting_context = ctx.clone(); // make a copy for use with jit_chain_guard

    // A mirror of the interpreter code. Checking for the case
    // where it's pushing rb_block_param_proxy.
    let side_exit = get_side_exit(jit, ocb, ctx);

    // EP level
    let level = jit_get_arg(jit, 1).as_u32();

    // Peek at the block handler so we can check whether it's nil
    let comptime_handler = jit_peek_at_block_handler(jit, level);

    // When a block handler is present, it should always be a GC-guarded
    // pointer (VM_BH_ISEQ_BLOCK_P)
    if comptime_handler.as_u64() != 0 && comptime_handler.as_u64() & 0x3 != 0x1 {
        return CantCompile;
    }

    // Load environment pointer EP from CFP
    let ep_opnd = gen_get_ep(asm, level);

    // Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
    let flag_check = Opnd::mem(
        64,
        ep_opnd,
        (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_FLAGS as i32),
    );
    asm.test(flag_check, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into());
    asm.jnz(counted_exit!(ocb, side_exit, gbpp_block_param_modified).into());

    // Load the block handler for the current frame
    // note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
    let block_handler = asm.load(
        Opnd::mem(64, ep_opnd, (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32))
    );

    // Specialize compilation for the case where no block handler is present
    if comptime_handler.as_u64() == 0 {
        // Bail if there is a block handler
        asm.cmp(block_handler, Opnd::UImm(0));

        jit_chain_guard(
            JCC_JNZ,
            jit,
            &starting_context,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            side_exit,
        );

        jit_putobject(jit, ctx, asm, Qnil);
    } else {
        // Block handler is a tagged pointer. Look at the tag. 0x03 is from VM_BH_ISEQ_BLOCK_P().
        let block_handler = asm.and(block_handler, 0x3.into());

        // Bail unless VM_BH_ISEQ_BLOCK_P(bh). This also checks for null.
        asm.cmp(block_handler, 0x1.into());

        jit_chain_guard(
            JCC_JNZ,
            jit,
            &starting_context,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            side_exit,
        );

        // Push rb_block_param_proxy. It's a root, so no need to use jit_mov_gc_ptr.
        assert!(!unsafe { rb_block_param_proxy }.special_const_p());

        let top = ctx.stack_push(Type::BlockParamProxy);
        asm.mov(top, Opnd::const_ptr(unsafe { rb_block_param_proxy }.as_ptr()));
    }

    jump_to_next_insn(jit, ctx, asm, ocb);

    EndBlock
}

fn gen_getblockparam(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> CodegenStatus {
    // EP level
    let level = jit_get_arg(jit, 1).as_u32();

    // Save the PC and SP because we might allocate
    jit_prepare_routine_call(jit, ctx, asm);

    // A mirror of the interpreter code. Checking for the case
    // where it's pushing rb_block_param_proxy.
    let side_exit = get_side_exit(jit, ocb, ctx);

    // Load environment pointer EP from CFP
    let ep_opnd = gen_get_ep(asm, level);

    // Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
    let flag_check = Opnd::mem(64, ep_opnd, (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_FLAGS as i32));
    // FIXME: This is testing bits in the same place that the WB check is testing.
    // We should combine these at some point
    asm.test(flag_check, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into());

    // If the frame flag has been modified, then the actual proc value is
    // already in the EP and we should just use the value.
    let frame_flag_modified = asm.new_label("frame_flag_modified");
    asm.jnz(frame_flag_modified);

    // This instruction writes the block handler to the EP.  If we need to
    // fire a write barrier for the write, then exit (we'll let the
    // interpreter handle it so it can fire the write barrier).
    // flags & VM_ENV_FLAG_WB_REQUIRED
    let flags_opnd = Opnd::mem(
        64,
        ep_opnd,
        SIZEOF_VALUE as i32 * VM_ENV_DATA_INDEX_FLAGS as i32,
    );
    asm.test(flags_opnd, VM_ENV_FLAG_WB_REQUIRED.into());

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    asm.jnz(side_exit.as_side_exit());

    // Convert the block handler in to a proc
    // call rb_vm_bh_to_procval(const rb_execution_context_t *ec, VALUE block_handler)
    let proc = asm.ccall(
        rb_vm_bh_to_procval as *const u8,
        vec![
            EC,
            // The block handler for the current frame
            // note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
            Opnd::mem(
                64,
                ep_opnd,
                (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_SPECVAL as i32),
            ),
        ]
    );

    // Load environment pointer EP from CFP (again)
    let ep_opnd = gen_get_ep(asm, level);

    // Write the value at the environment pointer
    let idx = jit_get_arg(jit, 0).as_i32();
    let offs = -(SIZEOF_VALUE as i32 * idx);
    asm.mov(Opnd::mem(64, ep_opnd, offs), proc);

    // Set the frame modified flag
    let flag_check = Opnd::mem(64, ep_opnd, (SIZEOF_VALUE as i32) * (VM_ENV_DATA_INDEX_FLAGS as i32));
    let modified_flag = asm.or(flag_check, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into());
    asm.store(flag_check, modified_flag);

    asm.write_label(frame_flag_modified);

    // Push the proc on the stack
    let stack_ret = ctx.stack_push(Type::Unknown);
    let ep_opnd = gen_get_ep(asm, level);
    asm.mov(stack_ret, Opnd::mem(64, ep_opnd, offs));

    KeepCompiling
}

fn gen_invokebuiltin(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let bf: *const rb_builtin_function = jit_get_arg(jit, 0).as_ptr();
    let bf_argc: usize = unsafe { (*bf).argc }.try_into().expect("non negative argc");

    // ec, self, and arguments
    if bf_argc + 2 > C_ARG_OPNDS.len() {
        return CantCompile;
    }

    // If the calls don't allocate, do they need up to date PC, SP?
    jit_prepare_routine_call(jit, ctx, asm);

    // Call the builtin func (ec, recv, arg1, arg2, ...)
    let mut args = vec![EC, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF)];

    // Copy arguments from locals
    for i in 0..bf_argc {
        let stack_opnd = ctx.stack_opnd((bf_argc - i - 1) as i32);
        args.push(stack_opnd);
    }

    let val = asm.ccall(unsafe { (*bf).func_ptr } as *const u8, args);

    // Push the return value
    ctx.stack_pop(bf_argc);
    let stack_ret = ctx.stack_push(Type::Unknown);
    asm.mov(stack_ret, val);

    KeepCompiling
}

// opt_invokebuiltin_delegate calls a builtin function, like
// invokebuiltin does, but instead of taking arguments from the top of the
// stack uses the argument locals (and self) from the current method.
fn gen_opt_invokebuiltin_delegate(
    jit: &mut JITState,
    ctx: &mut Context,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> CodegenStatus {
    let bf: *const rb_builtin_function = jit_get_arg(jit, 0).as_ptr();
    let bf_argc = unsafe { (*bf).argc };
    let start_index = jit_get_arg(jit, 1).as_i32();

    // ec, self, and arguments
    if bf_argc + 2 > (C_ARG_OPNDS.len() as i32) {
        return CantCompile;
    }

    // If the calls don't allocate, do they need up to date PC, SP?
    jit_prepare_routine_call(jit, ctx, asm);

    // Call the builtin func (ec, recv, arg1, arg2, ...)
    let mut args = vec![EC, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF)];

    // Copy arguments from locals
    if bf_argc > 0 {
        // Load environment pointer EP from CFP
        let ep = asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP));

        for i in 0..bf_argc {
            let table_size = unsafe { get_iseq_body_local_table_size(jit.iseq) };
            let offs: i32 = -(table_size as i32) - (VM_ENV_DATA_SIZE as i32) + 1 + start_index + i;
            let local_opnd = Opnd::mem(64, ep, offs * (SIZEOF_VALUE as i32));
            args.push(local_opnd);
        }
    }
    let val = asm.ccall(unsafe { (*bf).func_ptr } as *const u8, args);

    // Push the return value
    let stack_ret = ctx.stack_push(Type::Unknown);
    asm.mov(stack_ret, val);

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
        YARVINSN_opt_newarray_max => Some(gen_opt_newarray_max),
        YARVINSN_opt_newarray_min => Some(gen_opt_newarray_min),
        YARVINSN_splatarray => Some(gen_splatarray),
        YARVINSN_concatarray => Some(gen_concatarray),
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
        YARVINSN_getconstant => Some(gen_getconstant),
        YARVINSN_opt_getconstant_path => Some(gen_opt_getconstant_path),
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
        YARVINSN_invokeblock => Some(gen_invokeblock),
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
    asm: &mut Assembler,
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

    // For servicing branch stubs
    branch_stub_hit_trampoline: CodePtr,

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
    method_codegen_table: HashMap<usize, MethodGenFn>,

    /// Page indexes for outlined code that are not associated to any ISEQ.
    ocb_pages: Vec<usize>,

    /// How many times code GC has been executed.
    code_gc_count: usize,
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
        // Executable memory and code page size in bytes
        let mem_size = get_option!(exec_mem_size);


        #[cfg(not(test))]
        let (mut cb, mut ocb) = {
            use std::cell::RefCell;
            use std::rc::Rc;

            let virt_block: *mut u8 = unsafe { rb_yjit_reserve_addr_space(mem_size as u32) };

            // Memory protection syscalls need page-aligned addresses, so check it here. Assuming
            // `virt_block` is page-aligned, `second_half` should be page-aligned as long as the
            // page size in bytes is a power of two 2¹⁹ or smaller. This is because the user
            // requested size is half of mem_option × 2²⁰ as it's in MiB.
            //
            // Basically, we don't support x86-64 2MiB and 1GiB pages. ARMv8 can do up to 64KiB
            // (2¹⁶ bytes) pages, which should be fine. 4KiB pages seem to be the most popular though.
            let page_size = unsafe { rb_yjit_get_page_size() };
            assert_eq!(
                virt_block as usize % page_size.as_usize(), 0,
                "Start of virtual address block should be page-aligned",
            );

            use crate::virtualmem::*;
            use std::ptr::NonNull;

            let mem_block = VirtualMem::new(
                SystemAllocator {},
                page_size,
                NonNull::new(virt_block).unwrap(),
                mem_size,
            );
            let mem_block = Rc::new(RefCell::new(mem_block));

            let freed_pages = Rc::new(None);
            let cb = CodeBlock::new(mem_block.clone(), false, freed_pages.clone());
            let ocb = OutlinedCb::wrap(CodeBlock::new(mem_block, true, freed_pages));

            (cb, ocb)
        };

        // In test mode we're not linking with the C code
        // so we don't allocate executable memory
        #[cfg(test)]
        let mut cb = CodeBlock::new_dummy(mem_size / 2);
        #[cfg(test)]
        let mut ocb = OutlinedCb::wrap(CodeBlock::new_dummy(mem_size / 2));

        let ocb_start_addr = ocb.unwrap().get_write_ptr();
        let leave_exit_code = gen_leave_exit(&mut ocb);

        let stub_exit_code = gen_code_for_exit_from_stub(&mut ocb);

        let branch_stub_hit_trampoline = gen_branch_stub_hit_trampoline(&mut ocb);

        // Generate full exit code for C func
        let cfunc_exit_code = gen_full_cfunc_return(&mut ocb);

        let ocb_end_addr = ocb.unwrap().get_write_ptr();
        let ocb_pages = ocb.unwrap().addrs_to_pages(ocb_start_addr, ocb_end_addr);

        // Mark all code memory as executable
        cb.mark_all_executable();
        ocb.unwrap().mark_all_executable();

        let mut codegen_globals = CodegenGlobals {
            inline_cb: cb,
            outlined_cb: ocb,
            leave_exit_code,
            stub_exit_code: stub_exit_code,
            outline_full_cfunc_return_pos: cfunc_exit_code,
            branch_stub_hit_trampoline,
            global_inval_patches: Vec::new(),
            inline_frozen_bytes: 0,
            method_codegen_table: HashMap::new(),
            ocb_pages,
            code_gc_count: 0,
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
            self.yjit_reg_method(rb_cInteger, "==", jit_rb_int_equal);
            self.yjit_reg_method(rb_cInteger, "===", jit_rb_int_equal);

            // rb_str_to_s() methods in string.c
            self.yjit_reg_method(rb_cString, "to_s", jit_rb_str_to_s);
            self.yjit_reg_method(rb_cString, "to_str", jit_rb_str_to_s);
            self.yjit_reg_method(rb_cString, "bytesize", jit_rb_str_bytesize);
            self.yjit_reg_method(rb_cString, "<<", jit_rb_str_concat);
            self.yjit_reg_method(rb_cString, "+@", jit_rb_str_uplus);

            self.yjit_reg_method(rb_mKernel, "respond_to?", jit_obj_respond_to);

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

    pub fn has_instance() -> bool {
        unsafe { CODEGEN_GLOBALS.as_mut().is_some() }
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

    pub fn get_branch_stub_hit_trampoline() -> CodePtr {
        CodegenGlobals::get_instance().branch_stub_hit_trampoline
    }

    pub fn look_up_codegen_method(method_serial: usize) -> Option<MethodGenFn> {
        let table = &CodegenGlobals::get_instance().method_codegen_table;

        let option_ref = table.get(&method_serial);
        match option_ref {
            None => None,
            Some(&mgf) => Some(mgf), // Deref
        }
    }

    pub fn get_ocb_pages() -> &'static Vec<usize> {
        &CodegenGlobals::get_instance().ocb_pages
    }

    pub fn incr_code_gc_count() {
        CodegenGlobals::get_instance().code_gc_count += 1;
    }

    pub fn get_code_gc_count() -> usize {
        CodegenGlobals::get_instance().code_gc_count
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_codegen() -> (JITState, Context, Assembler, CodeBlock, OutlinedCb) {
        let blockid = BlockId {
            iseq: ptr::null(),
            idx: 0,
        };
        let block = Block::new(blockid, &Context::default());

        return (
            JITState::new(&block),
            Context::default(),
            Assembler::new(),
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
        let (_, ctx, mut asm, mut cb, _) = setup_codegen();
        gen_exit(0 as *mut VALUE, &ctx, &mut asm);
        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_get_side_exit() {
        let (mut jit, ctx, _, _, mut ocb) = setup_codegen();
         get_side_exit(&mut jit, &mut ocb, &ctx);
        assert!(ocb.unwrap().get_write_pos() > 0);
    }

    #[test]
    fn test_gen_check_ints() {
        let (_, _ctx, mut asm, _cb, mut ocb) = setup_codegen();
        let side_exit = ocb.unwrap().get_write_ptr();
        gen_check_ints(&mut asm, side_exit);
    }

    #[test]
    fn test_gen_nop() {
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();
        let status = gen_nop(&mut jit, &mut context, &mut asm, &mut ocb);
        asm.compile(&mut cb);

        assert_eq!(status, KeepCompiling);
        assert_eq!(context.diff(&Context::default()), 0);
        assert_eq!(cb.get_write_pos(), 0);
    }

    #[test]
    fn test_gen_pop() {
        let (mut jit, _, mut asm, _cb, mut ocb) = setup_codegen();
        let mut context = Context::default();
        context.stack_push(Type::Fixnum);
        let status = gen_pop(&mut jit, &mut context, &mut asm, &mut ocb);

        assert_eq!(status, KeepCompiling);
        assert_eq!(context.diff(&Context::default()), 0);
    }

    #[test]
    fn test_gen_dup() {
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Fixnum);
        let status = gen_dup(&mut jit, &mut context, &mut asm, &mut ocb);

        assert_eq!(status, KeepCompiling);

        // Did we duplicate the type information for the Fixnum type?
        assert_eq!(Type::Fixnum, context.get_opnd_type(StackOpnd(0)));
        assert_eq!(Type::Fixnum, context.get_opnd_type(StackOpnd(1)));

        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_dupn() {
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Fixnum);
        context.stack_push(Type::Flonum);

        let mut value_array: [u64; 2] = [0, 2]; // We only compile for n == 2
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_dupn(&mut jit, &mut context, &mut asm, &mut ocb);

        assert_eq!(status, KeepCompiling);

        assert_eq!(Type::Fixnum, context.get_opnd_type(StackOpnd(3)));
        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::Fixnum, context.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(0)));

        // TODO: this is writing zero bytes on x86. Why?
        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_swap() {
        let (mut jit, mut context, mut asm, _cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Fixnum);
        context.stack_push(Type::Flonum);

        let status = gen_swap(&mut jit, &mut context, &mut asm, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));
        let (_, tmp_type_next) = context.get_opnd_mapping(StackOpnd(1));

        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::Fixnum);
        assert_eq!(tmp_type_next, Type::Flonum);
    }

    #[test]
    fn test_putnil() {
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();
        let status = gen_putnil(&mut jit, &mut context, &mut asm, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));

        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::Nil);
        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_putobject_qtrue() {
        // Test gen_putobject with Qtrue
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();

        let mut value_array: [u64; 2] = [0, Qtrue.into()];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_putobject(&mut jit, &mut context, &mut asm, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));

        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::True);
        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_putobject_fixnum() {
        // Test gen_putobject with a Fixnum to test another conditional branch
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();

        // The Fixnum 7 is encoded as 7 * 2 + 1, or 15
        let mut value_array: [u64; 2] = [0, 15];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_putobject(&mut jit, &mut context, &mut asm, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));

        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::Fixnum);
        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_int2fix() {
        let (mut jit, mut context, mut asm, _cb, mut ocb) = setup_codegen();
        jit.opcode = YARVINSN_putobject_INT2FIX_0_.as_usize();
        let status = gen_putobject_int2fix(&mut jit, &mut context, &mut asm, &mut ocb);

        let (_, tmp_type_top) = context.get_opnd_mapping(StackOpnd(0));

        // Right now we're not testing the generated machine code to make sure a literal 1 or 0 was pushed. I've checked locally.
        assert_eq!(status, KeepCompiling);
        assert_eq!(tmp_type_top, Type::Fixnum);
    }

    #[test]
    fn test_putself() {
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();
        let status = gen_putself(&mut jit, &mut context, &mut asm, &mut ocb);

        assert_eq!(status, KeepCompiling);
        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_gen_setn() {
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Fixnum);
        context.stack_push(Type::Flonum);
        context.stack_push(Type::CString);

        let mut value_array: [u64; 2] = [0, 2];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_setn(&mut jit, &mut context, &mut asm, &mut ocb);

        assert_eq!(status, KeepCompiling);

        assert_eq!(Type::CString, context.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::CString, context.get_opnd_type(StackOpnd(0)));

        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_gen_topn() {
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Flonum);
        context.stack_push(Type::CString);

        let mut value_array: [u64; 2] = [0, 1];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_topn(&mut jit, &mut context, &mut asm, &mut ocb);

        assert_eq!(status, KeepCompiling);

        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::CString, context.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(0)));

        asm.compile(&mut cb);
        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_adjuststack() {
        let (mut jit, mut context, mut asm, mut cb, mut ocb) = setup_codegen();
        context.stack_push(Type::Flonum);
        context.stack_push(Type::CString);
        context.stack_push(Type::Fixnum);

        let mut value_array: [u64; 3] = [0, 2, 0];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_adjuststack(&mut jit, &mut context, &mut asm, &mut ocb);

        assert_eq!(status, KeepCompiling);

        assert_eq!(Type::Flonum, context.get_opnd_type(StackOpnd(0)));

        asm.compile(&mut cb);
        assert!(cb.get_write_pos() == 0); // No instructions written
    }

    #[test]
    fn test_gen_leave() {
        let (mut jit, mut context, mut asm, _cb, mut ocb) = setup_codegen();
        // Push return value
        context.stack_push(Type::Fixnum);
        gen_leave(&mut jit, &mut context, &mut asm, &mut ocb);
    }
}
