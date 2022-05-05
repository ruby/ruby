use crate::asm::*;
use crate::core::*;
use crate::cruby::*;
use crate::options::*;
use crate::utils::*;
use CodegenStatus::*;
use InsnOpnd::*;
#[cfg(feature = "stats")]
use crate::stats::*;

use std::cell::RefMut;
use std::cmp;
use std::collections::HashMap;
use std::ffi::CStr;
use std::mem;
use std::os::raw::c_uint;
use std::ptr;

#[cfg(target_arch = "x86_64")]
pub mod x86_64;
#[cfg(target_arch = "x86_64")]
pub use x86_64::*;
#[cfg(target_arch = "aarch64")]
pub mod aarch64;
#[cfg(target_arch = "aarch64")]
pub use aarch64::*;

/// Status returned by code generation functions
#[derive(PartialEq, Debug)]
pub enum CodegenStatus {
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

            gen_counter_increment($cb, ptr as *const u8);
        }
    };
}
pub(crate) use gen_counter_incr;


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
            gen_jump_ptr(ocb, $existing_side_exit);

            // Pointer to the side-exit code
            code_ptr
        }
    };
}

pub(crate) use counted_exit;

/// jit_save_pc() + gen_save_sp(). Should be used before calling a routine that
/// could:
///  - Perform GC allocation
///  - Take the VM lock through RB_VM_LOCK_ENTER()
///  - Perform Ruby method call
fn jit_prepare_routine_call(
    jit: &mut JITState,
    ctx: &mut Context,
    cb: &mut CodeBlock,
    scratch_reg: YJitOpnd,
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
pub fn get_side_exit(jit: &mut JITState, ocb: &mut OutlinedCb, ctx: &Context) -> CodePtr {
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
        if opcode == OP_OPT_GETINLINECACHE && insn_idx > starting_insn_idx {
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
            let page_size = unsafe { rb_yjit_get_page_size() }.as_usize();
            let mem_block: *mut u8 = unsafe { alloc_exec_mem(mem_size.try_into().unwrap()) };
            let cb = CodeBlock::new(mem_block, mem_size / 2, page_size);
            let ocb = OutlinedCb::wrap(CodeBlock::new(
                unsafe { mem_block.add(mem_size / 2) },
                mem_size / 2,
                page_size,
            ));
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
    fn test_get_side_exit() {
        let (mut jit, ctx, _, mut ocb) = setup_codegen();
        get_side_exit(&mut jit, &mut ocb, &ctx);
        assert!(ocb.unwrap().get_write_pos() > 0);
    }
}
