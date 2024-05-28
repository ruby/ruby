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

use std::cell::Cell;
use std::cmp;
use std::cmp::min;
use std::collections::HashMap;
use std::ffi::CStr;
use std::mem;
use std::os::raw::c_int;
use std::ptr;
use std::rc::Rc;
use std::cell::RefCell;
use std::slice;

pub use crate::virtualmem::CodePtr;

/// Status returned by code generation functions
#[derive(PartialEq, Debug)]
enum CodegenStatus {
    KeepCompiling,
    EndBlock,
}

/// Code generation function signature
type InsnGenFn = fn(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus>;

/// Ephemeral code generation state.
/// Represents a [core::Block] while we build it.
pub struct JITState {
    /// Instruction sequence for the compiling block
    iseq: IseqPtr,

    /// The iseq index of the first instruction in the block
    starting_insn_idx: IseqIdx,

    /// The [Context] entering into the first instruction of the block
    starting_ctx: Context,

    /// The placement for the machine code of the [Block]
    output_ptr: CodePtr,

    /// Index of the current instruction being compiled
    insn_idx: IseqIdx,

    /// Opcode for the instruction being compiled
    opcode: usize,

    /// PC of the instruction being compiled
    pc: *mut VALUE,

    /// stack_size when it started to compile the current instruction.
    stack_size_for_pc: u8,

    /// Execution context when compilation started
    /// This allows us to peek at run-time values
    ec: EcPtr,

    /// The outgoing branches the block will have
    pub pending_outgoing: Vec<PendingBranchRef>,

    // --- Fields for block invalidation and invariants tracking below:
    // Public mostly so into_block defined in the sibling module core
    // can partially move out of Self.

    /// Whether we need to record the code address at
    /// the end of this bytecode instruction for global invalidation
    pub record_boundary_patch_point: bool,

    /// Code for immediately exiting upon entry to the block.
    /// Required for invalidation.
    pub block_entry_exit: Option<CodePtr>,

    /// A list of callable method entries that must be valid for the block to be valid.
    pub method_lookup_assumptions: Vec<CmePtr>,

    /// A list of basic operators that not be redefined for the block to be valid.
    pub bop_assumptions: Vec<(RedefinitionFlag, ruby_basic_operators)>,

    /// A list of constant expression path segments that must have
    /// not been written to for the block to be valid.
    pub stable_constant_names_assumption: Option<*const ID>,

    /// When true, the block is valid only when there is a total of one ractor running
    pub block_assumes_single_ractor: bool,

    /// Address range for Linux perf's [JIT interface](https://github.com/torvalds/linux/blob/master/tools/perf/Documentation/jit-interface.txt)
    perf_map: Rc::<RefCell::<Vec<(CodePtr, Option<CodePtr>, String)>>>,
}

impl JITState {
    pub fn new(blockid: BlockId, starting_ctx: Context, output_ptr: CodePtr, ec: EcPtr) -> Self {
        JITState {
            iseq: blockid.iseq,
            starting_insn_idx: blockid.idx,
            starting_ctx,
            output_ptr,
            insn_idx: 0,
            opcode: 0,
            pc: ptr::null_mut::<VALUE>(),
            stack_size_for_pc: starting_ctx.get_stack_size(),
            pending_outgoing: vec![],
            ec,
            record_boundary_patch_point: false,
            block_entry_exit: None,
            method_lookup_assumptions: vec![],
            bop_assumptions: vec![],
            stable_constant_names_assumption: None,
            block_assumes_single_ractor: false,
            perf_map: Rc::default(),
        }
    }

    pub fn get_insn_idx(&self) -> IseqIdx {
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

    pub fn get_starting_insn_idx(&self) -> IseqIdx {
        self.starting_insn_idx
    }

    pub fn get_block_entry_exit(&self) -> Option<CodePtr> {
        self.block_entry_exit
    }

    pub fn get_starting_ctx(&self) -> Context {
        self.starting_ctx
    }

    pub fn get_arg(&self, arg_idx: isize) -> VALUE {
        // insn_len require non-test config
        #[cfg(not(test))]
        assert!(insn_len(self.get_opcode()) > (arg_idx + 1).try_into().unwrap());
        unsafe { *(self.pc.offset(arg_idx + 1)) }
    }

    // Get the index of the next instruction
    fn next_insn_idx(&self) -> u16 {
        self.insn_idx + insn_len(self.get_opcode()) as u16
    }

    // Check if we are compiling the instruction at the stub PC
    // Meaning we are compiling the instruction that is next to execute
    pub fn at_current_insn(&self) -> bool {
        let ec_pc: *mut VALUE = unsafe { get_cfp_pc(self.get_cfp()) };
        ec_pc == self.pc
    }

    // Peek at the nth topmost value on the Ruby stack.
    // Returns the topmost value when n == 0.
    pub fn peek_at_stack(&self, ctx: &Context, n: isize) -> VALUE {
        assert!(self.at_current_insn());
        assert!(n < ctx.get_stack_size() as isize);

        // Note: this does not account for ctx->sp_offset because
        // this is only available when hitting a stub, and while
        // hitting a stub, cfp->sp needs to be up to date in case
        // codegen functions trigger GC. See :stub-sp-flush:.
        return unsafe {
            let sp: *mut VALUE = get_cfp_sp(self.get_cfp());

            *(sp.offset(-1 - n))
        };
    }

    fn peek_at_self(&self) -> VALUE {
        unsafe { get_cfp_self(self.get_cfp()) }
    }

    fn peek_at_local(&self, n: i32) -> VALUE {
        assert!(self.at_current_insn());

        let local_table_size: isize = unsafe { get_iseq_body_local_table_size(self.iseq) }
            .try_into()
            .unwrap();
        assert!(n < local_table_size.try_into().unwrap());

        unsafe {
            let ep = get_cfp_ep(self.get_cfp());
            let n_isize: isize = n.try_into().unwrap();
            let offs: isize = -(VM_ENV_DATA_SIZE as isize) - local_table_size + n_isize + 1;
            *ep.offset(offs)
        }
    }

    fn peek_at_block_handler(&self, level: u32) -> VALUE {
        assert!(self.at_current_insn());

        unsafe {
            let ep = get_cfp_ep_level(self.get_cfp(), level);
            *ep.offset(VM_ENV_DATA_INDEX_SPECVAL as isize)
        }
    }

    pub fn assume_method_lookup_stable(&mut self, asm: &mut Assembler, ocb: &mut OutlinedCb, cme: CmePtr) -> Option<()> {
        jit_ensure_block_entry_exit(self, asm, ocb)?;
        self.method_lookup_assumptions.push(cme);

        Some(())
    }

    fn get_cfp(&self) -> *mut rb_control_frame_struct {
        unsafe { get_ec_cfp(self.ec) }
    }

    pub fn assume_stable_constant_names(&mut self, asm: &mut Assembler, ocb: &mut OutlinedCb, id: *const ID) -> Option<()> {
        jit_ensure_block_entry_exit(self, asm, ocb)?;
        self.stable_constant_names_assumption = Some(id);

        Some(())
    }

    pub fn queue_outgoing_branch(&mut self, branch: PendingBranchRef) {
        self.pending_outgoing.push(branch)
    }

    /// Mark the start address of a symbol to be reported to perf
    fn perf_symbol_range_start(&self, asm: &mut Assembler, symbol_name: &str) {
        let symbol_name = symbol_name.to_string();
        let syms = self.perf_map.clone();
        asm.pos_marker(move |start, _| syms.borrow_mut().push((start, None, symbol_name.clone())));
    }

    /// Mark the end address of a symbol to be reported to perf
    fn perf_symbol_range_end(&self, asm: &mut Assembler) {
        let syms = self.perf_map.clone();
        asm.pos_marker(move |end, _| {
            if let Some((_, ref mut end_store, _)) = syms.borrow_mut().last_mut() {
                assert_eq!(None, *end_store);
                *end_store = Some(end);
            }
        });
    }

    /// Flush addresses and symbols to /tmp/perf-{pid}.map
    fn flush_perf_symbols(&self, cb: &CodeBlock) {
        let path = format!("/tmp/perf-{}.map", std::process::id());
        let mut f = std::fs::File::options().create(true).append(true).open(path).unwrap();
        for sym in self.perf_map.borrow().iter() {
            if let (start, Some(end), name) = sym {
                // In case the code straddles two pages, part of it belongs to the symbol.
                for (inline_start, inline_end) in cb.writable_addrs(*start, *end) {
                    use std::io::Write;
                    let code_size = inline_end - inline_start;
                    writeln!(f, "{inline_start:x} {code_size:x} {name}").unwrap();
                }
            }
        }
    }
}

use crate::codegen::JCCKinds::*;

#[allow(non_camel_case_types, unused)]
pub enum JCCKinds {
    JCC_JNE,
    JCC_JNZ,
    JCC_JZ,
    JCC_JE,
    JCC_JB,
    JCC_JBE,
    JCC_JNA,
    JCC_JNAE,
    JCC_JO_MUL,
}

#[inline(always)]
fn gen_counter_incr(asm: &mut Assembler, counter: Counter) {
    // Assert that default counters are not incremented by generated code as this would impact performance
    assert!(!DEFAULT_COUNTERS.contains(&counter), "gen_counter_incr incremented {:?}", counter);

    if get_option!(gen_stats) {
        asm_comment!(asm, "increment counter {}", counter.get_name());
        let ptr = get_counter_ptr(&counter.get_name());
        let ptr_reg = asm.load(Opnd::const_ptr(ptr as *const u8));
        let counter_opnd = Opnd::mem(64, ptr_reg, 0);

        // Increment and store the updated value
        asm.incr_counter(counter_opnd, Opnd::UImm(1));
    }
}

// Save the incremented PC on the CFP
// This is necessary when callees can raise or allocate
fn jit_save_pc(jit: &JITState, asm: &mut Assembler) {
    let pc: *mut VALUE = jit.get_pc();
    let ptr: *mut VALUE = unsafe {
        let cur_insn_len = insn_len(jit.get_opcode()) as isize;
        pc.offset(cur_insn_len)
    };

    asm_comment!(asm, "save PC to CFP");
    asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), Opnd::const_ptr(ptr as *const u8));
}

/// Save the current SP on the CFP
/// This realigns the interpreter SP with the JIT SP
/// Note: this will change the current value of REG_SP,
///       which could invalidate memory operands
fn gen_save_sp(asm: &mut Assembler) {
    gen_save_sp_with_offset(asm, 0);
}

/// Save the current SP + offset on the CFP
fn gen_save_sp_with_offset(asm: &mut Assembler, offset: i8) {
    if asm.ctx.get_sp_offset() != -offset {
        asm_comment!(asm, "save SP to CFP");
        let stack_pointer = asm.ctx.sp_opnd((offset as i32 * SIZEOF_VALUE_I32) as isize);
        let sp_addr = asm.lea(stack_pointer);
        asm.mov(SP, sp_addr);
        let cfp_sp_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP);
        asm.mov(cfp_sp_opnd, SP);
        asm.ctx.set_sp_offset(-offset);
    }
}

/// jit_save_pc() + gen_save_sp(). Should be used before calling a routine that
/// could:
///  - Perform GC allocation
///  - Take the VM lock through RB_VM_LOCK_ENTER()
///  - Perform Ruby method call
fn jit_prepare_routine_call(
    jit: &mut JITState,
    asm: &mut Assembler
) {
    jit.record_boundary_patch_point = true;
    jit_save_pc(jit, asm);
    gen_save_sp(asm);

    // In case the routine calls Ruby methods, it can set local variables
    // through Kernel#binding and other means.
    asm.ctx.clear_local_types();
}

/// Record the current codeblock write position for rewriting into a jump into
/// the outlined block later. Used to implement global code invalidation.
fn record_global_inval_patch(asm: &mut Assembler, outline_block_target_pos: CodePtr) {
    // We add a padding before pos_marker so that the previous patch will not overlap this.
    // jump_to_next_insn() puts a patch point at the end of the block in fallthrough cases.
    // In the fallthrough case, the next block should start with the same Context, so the
    // patch is fine, but it should not overlap another patch.
    asm.pad_inval_patch();
    asm.pos_marker(move |code_ptr, cb| {
        CodegenGlobals::push_global_inval_patch(code_ptr, outline_block_target_pos, cb);
    });
}

/// Verify the ctx's types and mappings against the compile-time stack, self,
/// and locals.
fn verify_ctx(jit: &JITState, ctx: &Context) {
    fn obj_info_str<'a>(val: VALUE) -> &'a str {
        unsafe { CStr::from_ptr(rb_obj_info(val)).to_str().unwrap() }
    }

    // Only able to check types when at current insn
    assert!(jit.at_current_insn());

    let self_val = jit.peek_at_self();
    let self_val_type = Type::from(self_val);

    // Verify self operand type
    if self_val_type.diff(ctx.get_opnd_type(SelfOpnd)) == TypeDiff::Incompatible {
        panic!(
            "verify_ctx: ctx self type ({:?}) incompatible with actual value of self {}",
            ctx.get_opnd_type(SelfOpnd),
            obj_info_str(self_val)
        );
    }

    // Verify stack operand types
    let top_idx = cmp::min(ctx.get_stack_size(), MAX_TEMP_TYPES as u8);
    for i in 0..top_idx {
        let learned_mapping = ctx.get_opnd_mapping(StackOpnd(i));
        let learned_type = ctx.get_opnd_type(StackOpnd(i));

        let stack_val = jit.peek_at_stack(ctx, i as isize);
        let val_type = Type::from(stack_val);

        match learned_mapping.get_kind() {
            TempMappingKind::MapToSelf => {
                if self_val != stack_val {
                    panic!(
                        "verify_ctx: stack value was mapped to self, but values did not match!\n  stack: {}\n  self: {}",
                        obj_info_str(stack_val),
                        obj_info_str(self_val)
                    );
                }
            }
            TempMappingKind::MapToLocal => {
                let local_idx: u8 = learned_mapping.get_local_idx();
                let local_val = jit.peek_at_local(local_idx.into());
                if local_val != stack_val {
                    panic!(
                        "verify_ctx: stack value was mapped to local, but values did not match\n  stack: {}\n  local {}: {}",
                        obj_info_str(stack_val),
                        local_idx,
                        obj_info_str(local_val)
                    );
                }
            }
            TempMappingKind::MapToStack => {}
        }

        // If the actual type differs from the learned type
        if val_type.diff(learned_type) == TypeDiff::Incompatible {
            panic!(
                "verify_ctx: ctx type ({:?}) incompatible with actual value on stack: {} ({:?})",
                learned_type,
                obj_info_str(stack_val),
                val_type,
            );
        }
    }

    // Verify local variable types
    let local_table_size = unsafe { get_iseq_body_local_table_size(jit.iseq) };
    let top_idx: usize = cmp::min(local_table_size as usize, MAX_TEMP_TYPES);
    for i in 0..top_idx {
        let learned_type = ctx.get_local_type(i);
        let local_val = jit.peek_at_local(i as i32);
        let local_type = Type::from(local_val);

        if local_type.diff(learned_type) == TypeDiff::Incompatible {
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
fn gen_stub_exit(ocb: &mut OutlinedCb) -> Option<CodePtr> {
    let ocb = ocb.unwrap();
    let mut asm = Assembler::new();

    gen_counter_incr(&mut asm, Counter::exit_from_branch_stub);

    asm_comment!(asm, "exit from branch stub");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(Qundef.into());

    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

/// Generate an exit to return to the interpreter
fn gen_exit(exit_pc: *mut VALUE, asm: &mut Assembler) {
    #[cfg(all(feature = "disasm", not(test)))]
    {
        let opcode = unsafe { rb_vm_insn_addr2opcode((*exit_pc).as_ptr()) };
        asm_comment!(asm, "exit to interpreter on {}", insn_name(opcode as usize));
    }

    if asm.ctx.is_return_landing() {
        asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));
        let top = asm.stack_push(Type::Unknown);
        asm.mov(top, C_RET_OPND);
    }

    // Spill stack temps before returning to the interpreter
    asm.spill_temps();

    // Generate the code to exit to the interpreters
    // Write the adjusted SP back into the CFP
    if asm.ctx.get_sp_offset() != 0 {
        let sp_opnd = asm.lea(asm.ctx.sp_opnd(0));
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

/// :side-exit:
/// Get an exit for the current instruction in the outlined block. The code
/// for each instruction often begins with several guards before proceeding
/// to do work. When guards fail, an option we have is to exit to the
/// interpreter at an instruction boundary. The piece of code that takes
/// care of reconstructing interpreter state and exiting out of generated
/// code is called the side exit.
///
/// No guards change the logic for reconstructing interpreter state at the
/// moment, so there is one unique side exit for each context. Note that
/// it's incorrect to jump to the side exit after any ctx stack push operations
/// since they change the logic required for reconstructing interpreter state.
pub fn gen_outlined_exit(exit_pc: *mut VALUE, ctx: &Context, ocb: &mut OutlinedCb) -> Option<CodePtr> {
    let mut cb = ocb.unwrap();
    let mut asm = Assembler::new();
    asm.ctx = *ctx;
    asm.set_reg_temps(ctx.get_reg_temps());

    gen_exit(exit_pc, &mut asm);

    asm.compile(&mut cb, None).map(|(code_ptr, _)| code_ptr)
}

/// Get a side exit. Increment a counter in it if --yjit-stats is enabled.
pub fn gen_counted_exit(side_exit: CodePtr, ocb: &mut OutlinedCb, counter: Option<Counter>) -> Option<CodePtr> {
    // The counter is only incremented when stats are enabled
    if !get_option!(gen_stats) {
        return Some(side_exit);
    }
    let counter = match counter {
        Some(counter) => counter,
        None => return Some(side_exit),
    };

    let mut asm = Assembler::new();

    // Load the pointer into a register
    asm_comment!(asm, "increment counter {}", counter.get_name());
    let ptr_reg = asm.load(Opnd::const_ptr(get_counter_ptr(&counter.get_name()) as *const u8));
    let counter_opnd = Opnd::mem(64, ptr_reg, 0);

    // Increment and store the updated value
    asm.incr_counter(counter_opnd, Opnd::UImm(1));

    // Jump to the existing side exit
    asm.jmp(Target::CodePtr(side_exit));

    let ocb = ocb.unwrap();
    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

// Ensure that there is an exit for the start of the block being compiled.
// Block invalidation uses this exit.
#[must_use]
pub fn jit_ensure_block_entry_exit(jit: &mut JITState, asm: &mut Assembler, ocb: &mut OutlinedCb) -> Option<()> {
    if jit.block_entry_exit.is_some() {
        return Some(());
    }

    let block_starting_context = &jit.get_starting_ctx();

    // If we're compiling the first instruction in the block.
    if jit.insn_idx == jit.starting_insn_idx {
        // Generate the exit with the cache in Assembler.
        let side_exit_context = SideExitContext::new(jit.pc, *block_starting_context);
        let entry_exit = asm.get_side_exit(&side_exit_context, None, ocb);
        jit.block_entry_exit = Some(entry_exit?);
    } else {
        let block_entry_pc = unsafe { rb_iseq_pc_at_idx(jit.iseq, jit.starting_insn_idx.into()) };
        jit.block_entry_exit = Some(gen_outlined_exit(block_entry_pc, block_starting_context, ocb)?);
    }

    Some(())
}

// Landing code for when c_return tracing is enabled. See full_cfunc_return().
fn gen_full_cfunc_return(ocb: &mut OutlinedCb) -> Option<CodePtr> {
    let ocb = ocb.unwrap();
    let mut asm = Assembler::new();

    // This chunk of code expects REG_EC to be filled properly and
    // RAX to contain the return value of the C method.

    asm_comment!(asm, "full cfunc return");
    asm.ccall(
        rb_full_cfunc_return as *const u8,
        vec![EC, C_RET_OPND]
    );

    // Count the exit
    gen_counter_incr(&mut asm, Counter::traced_cfunc_return);

    // Return to the interpreter
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(Qundef.into());

    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

/// Generate a continuation for leave that exits to the interpreter at REG_CFP->pc.
/// This is used by gen_leave() and gen_entry_prologue()
fn gen_leave_exit(ocb: &mut OutlinedCb) -> Option<CodePtr> {
    let ocb = ocb.unwrap();
    let mut asm = Assembler::new();

    // gen_leave() fully reconstructs interpreter state and leaves the
    // return value in C_RET_OPND before coming here.
    let ret_opnd = asm.live_reg_opnd(C_RET_OPND);

    // Every exit to the interpreter should be counted
    gen_counter_incr(&mut asm, Counter::leave_interp_return);

    asm_comment!(asm, "exit from leave");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(ret_opnd);

    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

// Increment SP and transfer the execution to the interpreter after jit_exec_exception().
// On jit_exec_exception(), you need to return Qundef to keep executing caller non-FINISH
// frames on the interpreter. You also need to increment SP to push the return value to
// the caller's stack, which is different from gen_stub_exit().
fn gen_leave_exception(ocb: &mut OutlinedCb) -> Option<CodePtr> {
    let ocb = ocb.unwrap();
    let mut asm = Assembler::new();

    // gen_leave() leaves the return value in C_RET_OPND before coming here.
    let ruby_ret_val = asm.live_reg_opnd(C_RET_OPND);

    // Every exit to the interpreter should be counted
    gen_counter_incr(&mut asm, Counter::leave_interp_return);

    asm_comment!(asm, "push return value through cfp->sp");
    let cfp_sp = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP);
    let sp = asm.load(cfp_sp);
    asm.mov(Opnd::mem(64, sp, 0), ruby_ret_val);
    let new_sp = asm.add(sp, SIZEOF_VALUE.into());
    asm.mov(cfp_sp, new_sp);

    asm_comment!(asm, "exit from exception");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    // Execute vm_exec_core
    asm.cret(Qundef.into());

    asm.compile(ocb, None).map(|(code_ptr, _)| code_ptr)
}

// Generate a runtime guard that ensures the PC is at the expected
// instruction index in the iseq, otherwise takes an entry stub
// that generates another check and entry.
// This is to handle the situation of optional parameters.
// When a function with optional parameters is called, the entry
// PC for the method isn't necessarily 0.
pub fn gen_entry_chain_guard(
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    iseq: IseqPtr,
    insn_idx: u16,
) -> Option<PendingEntryRef> {
    let entry = new_pending_entry();
    let stub_addr = gen_entry_stub(entry.uninit_entry.as_ptr() as usize, ocb)?;

    let pc_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC);
    let expected_pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };
    let expected_pc_opnd = Opnd::const_ptr(expected_pc as *const u8);

    asm_comment!(asm, "guard expected PC");
    asm.cmp(pc_opnd, expected_pc_opnd);

    asm.mark_entry_start(&entry);
    asm.jne(stub_addr.into());
    asm.mark_entry_end(&entry);
    return Some(entry);
}

/// Compile an interpreter entry block to be inserted into an iseq
/// Returns None if compilation fails.
/// If jit_exception is true, compile JIT code for handling exceptions.
/// See [jit_compile_exception] for details.
pub fn gen_entry_prologue(
    cb: &mut CodeBlock,
    ocb: &mut OutlinedCb,
    iseq: IseqPtr,
    insn_idx: u16,
    jit_exception: bool,
) -> Option<CodePtr> {
    let code_ptr = cb.get_write_ptr();

    let mut asm = Assembler::new();
    if get_option_ref!(dump_disasm).is_some() {
        asm_comment!(asm, "YJIT entry point: {}", iseq_get_location(iseq, 0));
    } else {
        asm_comment!(asm, "YJIT entry");
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
    // If this is an exception handler entry point
    if jit_exception {
        // On jit_exec_exception(), it's NOT safe to return a non-Qundef value
        // from a non-FINISH frame. This function fixes that problem.
        // See [jit_compile_exception] for details.
        asm.ccall(
            rb_yjit_set_exception_return as *mut u8,
            vec![
                CFP,
                Opnd::const_ptr(CodegenGlobals::get_leave_exit_code().raw_ptr(cb)),
                Opnd::const_ptr(CodegenGlobals::get_leave_exception_code().raw_ptr(cb)),
            ],
        );
    } else {
        // On jit_exec() or JIT_EXEC(), it's safe to return a non-Qundef value
        // on the entry frame. See [jit_compile] for details.
        asm.mov(
            Opnd::mem(64, CFP, RUBY_OFFSET_CFP_JIT_RETURN),
            Opnd::const_ptr(CodegenGlobals::get_leave_exit_code().raw_ptr(cb)),
        );
    }

    // We're compiling iseqs that we *expect* to start at `insn_idx`.
    // But in the case of optional parameters or when handling exceptions,
    // the interpreter can set the pc to a different location. For
    // such scenarios, we'll add a runtime check that the PC we've
    // compiled for is the same PC that the interpreter wants us to run with.
    // If they don't match, then we'll jump to an entry stub and generate
    // another PC check and entry there.
    let pending_entry = if unsafe { get_iseq_flags_has_opt(iseq) } || jit_exception {
        Some(gen_entry_chain_guard(&mut asm, ocb, iseq, insn_idx)?)
    } else {
        None
    };

    asm.compile(cb, Some(ocb))?;

    if cb.has_dropped_bytes() {
        None
    } else {
        // Mark code pages for code GC
        let iseq_payload = get_or_create_iseq_payload(iseq);
        for page in cb.addrs_to_pages(code_ptr, cb.get_write_ptr()) {
            iseq_payload.pages.insert(page);
        }
        // Write an entry to the heap and push it to the ISEQ
        if let Some(pending_entry) = pending_entry {
            let pending_entry = Rc::try_unwrap(pending_entry)
                .ok().expect("PendingEntry should be unique");
            iseq_payload.entries.push(pending_entry.into_entry());
        }
        Some(code_ptr)
    }
}

// Generate code to check for interrupts and take a side-exit.
// Warning: this function clobbers REG0
fn gen_check_ints(
    asm: &mut Assembler,
    counter: Counter,
) {
    // Check for interrupts
    // see RUBY_VM_CHECK_INTS(ec) macro
    asm_comment!(asm, "RUBY_VM_CHECK_INTS(ec)");

    // Not checking interrupt_mask since it's zero outside finalize_deferred_heap_pages,
    // signal_exec, or rb_postponed_job_flush.
    let interrupt_flag = asm.load(Opnd::mem(32, EC, RUBY_OFFSET_EC_INTERRUPT_FLAG));
    asm.test(interrupt_flag, interrupt_flag);

    asm.jnz(Target::side_exit(counter));
}

// Generate a stubbed unconditional jump to the next bytecode instruction.
// Blocks that are part of a guard chain can use this to share the same successor.
fn jump_to_next_insn(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<()> {
    // Reset the depth since in current usages we only ever jump to to
    // chain_depth > 0 from the same instruction.
    let mut reset_depth = asm.ctx;
    reset_depth.reset_chain_depth();

    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jit.next_insn_idx(),
    };

    // We are at the end of the current instruction. Record the boundary.
    if jit.record_boundary_patch_point {
        jit.record_boundary_patch_point = false;
        let exit_pc = unsafe { jit.pc.offset(insn_len(jit.opcode).try_into().unwrap()) };
        let exit_pos = gen_outlined_exit(exit_pc, &reset_depth, ocb);
        record_global_inval_patch(asm, exit_pos?);
    }

    // Generate the jump instruction
    gen_direct_jump(jit, &reset_depth, jump_block, asm);
    Some(())
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
    let ctx = limit_block_versions(blockid, start_ctx);

    verify_blockid(blockid);
    assert!(!(blockid.idx == 0 && ctx.get_stack_size() > 0));

    // Save machine code placement of the block. `cb` might page switch when we
    // generate code in `ocb`.
    let block_start_addr = cb.get_write_ptr();

    // Instruction sequence to compile
    let iseq = blockid.iseq;
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    let iseq_size: IseqIdx = if let Ok(size) = iseq_size.try_into() {
        size
    } else {
        // ISeq too large to compile
        return Err(());
    };
    let mut insn_idx: IseqIdx = blockid.idx;

    // Initialize a JIT state object
    let mut jit = JITState::new(blockid, ctx, cb.get_write_ptr(), ec);
    jit.iseq = blockid.iseq;

    // Create a backend assembler instance
    let mut asm = Assembler::new();
    asm.ctx = ctx;

    #[cfg(feature = "disasm")]
    if get_option_ref!(dump_disasm).is_some() {
        let blockid_idx = blockid.idx;
        let chain_depth = if asm.ctx.get_chain_depth() > 0 { format!("(chain_depth: {})", asm.ctx.get_chain_depth()) } else { "".to_string() };
        asm_comment!(asm, "Block: {} {}", iseq_get_location(blockid.iseq, blockid_idx), chain_depth);
        asm_comment!(asm, "reg_temps: {:08b}", asm.ctx.get_reg_temps().as_u8());
    }

    // Mark the start of a method name symbol for --yjit-perf
    if get_option!(perf_map) {
        let comptime_recv_class = jit.peek_at_self().class_of();
        let class_name = unsafe { cstr_to_rust_string(rb_class2name(comptime_recv_class)) };
        match (class_name, unsafe { rb_iseq_label(iseq) }) {
            (Some(class_name), iseq_label) if iseq_label != Qnil => {
                let iseq_label = ruby_str_to_rust(iseq_label);
                jit.perf_symbol_range_start(&mut asm, &format!("[JIT] {}#{}", class_name, iseq_label));
            }
            _ => {},
        }
    }

    if asm.ctx.is_return_landing() {
        // Continuation of the end of gen_leave().
        // Reload REG_SP for the current frame and transfer the return value
        // to the stack top.
        asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));

        let top = asm.stack_push(Type::Unknown);
        asm.mov(top, C_RET_OPND);

        asm.ctx.clear_return_landing();
    }

    // For each instruction to compile
    // NOTE: could rewrite this loop with a std::iter::Iterator
    while insn_idx < iseq_size {
        // Get the current pc and opcode
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx.into()) };
        // try_into() call below is unfortunate. Maybe pick i32 instead of usize for opcodes.
        let opcode: usize = unsafe { rb_iseq_opcode_at_pc(iseq, pc) }
            .try_into()
            .unwrap();

        // We need opt_getconstant_path to be in a block all on its own. Cut the block short
        // if we run into it. This is necessary because we want to invalidate based on the
        // instruction's index.
        if opcode == YARVINSN_opt_getconstant_path.as_usize() && insn_idx > jit.starting_insn_idx {
            jump_to_next_insn(&mut jit, &mut asm, ocb);
            break;
        }

        // Set the current instruction
        jit.insn_idx = insn_idx;
        jit.opcode = opcode;
        jit.pc = pc;
        jit.stack_size_for_pc = asm.ctx.get_stack_size();
        asm.set_side_exit_context(pc, asm.ctx.get_stack_size());

        // stack_pop doesn't immediately deallocate a register for stack temps,
        // but it's safe to do so at this instruction boundary.
        for stack_idx in asm.ctx.get_stack_size()..MAX_REG_TEMPS {
            asm.ctx.dealloc_temp_reg(stack_idx);
        }

        // If previous instruction requested to record the boundary
        if jit.record_boundary_patch_point {
            // Generate an exit to this instruction and record it
            let exit_pos = gen_outlined_exit(jit.pc, &asm.ctx, ocb).ok_or(())?;
            record_global_inval_patch(&mut asm, exit_pos);
            jit.record_boundary_patch_point = false;
        }

        // In debug mode, verify our existing assumption
        if cfg!(debug_assertions) && get_option!(verify_ctx) && jit.at_current_insn() {
            verify_ctx(&jit, &asm.ctx);
        }

        // :count-placement:
        // Count bytecode instructions that execute in generated code.
        // Note that the increment happens even when the output takes side exit.
        gen_counter_incr(&mut asm, Counter::yjit_insns_count);

        // Lookup the codegen function for this instruction
        let mut status = None;
        if let Some(gen_fn) = get_gen_fn(VALUE(opcode)) {
            // Add a comment for the name of the YARV instruction
            asm_comment!(asm, "Insn: {:04} {} (stack_size: {})", insn_idx, insn_name(opcode), asm.ctx.get_stack_size());

            // If requested, dump instructions for debugging
            if get_option!(dump_insns) {
                println!("compiling {}", insn_name(opcode));
                print_str(&mut asm, &format!("executing {}", insn_name(opcode)));
            }

            // Call the code generation function
            status = gen_fn(&mut jit, &mut asm, ocb);
        }

        // If we can't compile this instruction
        // exit to the interpreter and stop compiling
        if status == None {
            if get_option!(dump_insns) {
                println!("can't compile {}", insn_name(opcode));
            }

            // Rewind stack_size using ctx.with_stack_size to allow stack_size changes
            // before you return None.
            asm.ctx = asm.ctx.with_stack_size(jit.stack_size_for_pc);
            gen_exit(jit.pc, &mut asm);

            // If this is the first instruction in the block, then
            // the entry address is the address for block_entry_exit
            if insn_idx == jit.starting_insn_idx {
                jit.block_entry_exit = Some(jit.output_ptr);
            }

            break;
        }

        // For now, reset the chain depth after each instruction as only the
        // first instruction in the block can concern itself with the depth.
        asm.ctx.reset_chain_depth();

        // Move to the next instruction to compile
        insn_idx += insn_len(opcode) as u16;

        // If the instruction terminates this block
        if status == Some(EndBlock) {
            break;
        }
    }
    let end_insn_idx = insn_idx;

    // We currently can't handle cases where the request is for a block that
    // doesn't go to the next instruction in the same iseq.
    assert!(!jit.record_boundary_patch_point);

    // Pad the block if it has the potential to be invalidated
    if jit.block_entry_exit.is_some() {
        asm.pad_inval_patch();
    }

    // Mark the end of a method name symbol for --yjit-perf
    if get_option!(perf_map) {
        jit.perf_symbol_range_end(&mut asm);
    }

    // Compile code into the code block
    let (_, gc_offsets) = asm.compile(cb, Some(ocb)).ok_or(())?;
    let end_addr = cb.get_write_ptr();

    // Flush perf symbols after asm.compile() writes addresses
    if get_option!(perf_map) {
        jit.flush_perf_symbols(cb);
    }

    // If code for the block doesn't fit, fail
    if cb.has_dropped_bytes() || ocb.unwrap().has_dropped_bytes() {
        return Err(());
    }

    // Block compiled successfully
    Ok(jit.into_block(end_insn_idx, block_start_addr, end_addr, gc_offsets))
}

fn gen_nop(
    _jit: &mut JITState,
    _asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Do nothing
    Some(KeepCompiling)
}

fn gen_pop(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Decrement SP
    asm.stack_pop(1);
    Some(KeepCompiling)
}

fn gen_dup(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let dup_val = asm.stack_opnd(0);
    let mapping = asm.ctx.get_opnd_mapping(dup_val.into());

    let loc0 = asm.stack_push_mapping(mapping);
    asm.mov(loc0, dup_val);

    Some(KeepCompiling)
}

// duplicate stack top n elements
fn gen_dupn(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let n = jit.get_arg(0).as_usize();

    // In practice, seems to be only used for n==2
    if n != 2 {
        return None;
    }

    let opnd1: Opnd = asm.stack_opnd(1);
    let opnd0: Opnd = asm.stack_opnd(0);

    let mapping1 = asm.ctx.get_opnd_mapping(opnd1.into());
    let mapping0 = asm.ctx.get_opnd_mapping(opnd0.into());

    let dst1: Opnd = asm.stack_push_mapping(mapping1);
    asm.mov(dst1, opnd1);

    let dst0: Opnd = asm.stack_push_mapping(mapping0);
    asm.mov(dst0, opnd0);

    Some(KeepCompiling)
}

// Swap top 2 stack entries
fn gen_swap(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    stack_swap(asm, 0, 1);
    Some(KeepCompiling)
}

fn stack_swap(
    asm: &mut Assembler,
    offset0: u16,
    offset1: u16,
) {
    let stack0_mem = asm.stack_opnd(offset0 as i32);
    let stack1_mem = asm.stack_opnd(offset1 as i32);

    let mapping0 = asm.ctx.get_opnd_mapping(stack0_mem.into());
    let mapping1 = asm.ctx.get_opnd_mapping(stack1_mem.into());

    let stack0_reg = asm.load(stack0_mem);
    let stack1_reg = asm.load(stack1_mem);
    asm.mov(stack0_mem, stack1_reg);
    asm.mov(stack1_mem, stack0_reg);

    asm.ctx.set_opnd_mapping(stack0_mem.into(), mapping1);
    asm.ctx.set_opnd_mapping(stack1_mem.into(), mapping0);
}

fn gen_putnil(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    jit_putobject(asm, Qnil);
    Some(KeepCompiling)
}

fn jit_putobject(asm: &mut Assembler, arg: VALUE) {
    let val_type: Type = Type::from(arg);
    let stack_top = asm.stack_push(val_type);
    asm.mov(stack_top, arg.into());
}

fn gen_putobject_int2fix(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let opcode = jit.opcode;
    let cst_val: usize = if opcode == YARVINSN_putobject_INT2FIX_0_.as_usize() {
        0
    } else {
        1
    };

    jit_putobject(asm, VALUE::fixnum_from_usize(cst_val));
    Some(KeepCompiling)
}

fn gen_putobject(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let arg: VALUE = jit.get_arg(0);

    jit_putobject(asm, arg);
    Some(KeepCompiling)
}

fn gen_putself(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {

    // Write it on the stack
    let stack_top = asm.stack_push_self();
    asm.mov(
        stack_top,
        Opnd::mem(VALUE_BITS, CFP, RUBY_OFFSET_CFP_SELF)
    );

    Some(KeepCompiling)
}

fn gen_putspecialobject(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let object_type = jit.get_arg(0).as_usize();

    if object_type == VM_SPECIAL_OBJECT_VMCORE.as_usize() {
        let stack_top = asm.stack_push(Type::UnknownHeap);
        let frozen_core = unsafe { rb_mRubyVMFrozenCore };
        asm.mov(stack_top, frozen_core.into());
        Some(KeepCompiling)
    } else {
        // TODO: implement for VM_SPECIAL_OBJECT_CBASE and
        // VM_SPECIAL_OBJECT_CONST_BASE
        None
    }
}

// set Nth stack entry to stack top
fn gen_setn(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let n = jit.get_arg(0).as_usize();

    let top_val = asm.stack_opnd(0);
    let dst_opnd = asm.stack_opnd(n.try_into().unwrap());
    asm.mov(
        dst_opnd,
        top_val
    );

    let mapping = asm.ctx.get_opnd_mapping(top_val.into());
    asm.ctx.set_opnd_mapping(dst_opnd.into(), mapping);

    Some(KeepCompiling)
}

// get nth stack value, then push it
fn gen_topn(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let n = jit.get_arg(0).as_usize();

    let top_n_val = asm.stack_opnd(n.try_into().unwrap());
    let mapping = asm.ctx.get_opnd_mapping(top_n_val.into());
    let loc0 = asm.stack_push_mapping(mapping);
    asm.mov(loc0, top_n_val);

    Some(KeepCompiling)
}

// Pop n values off the stack
fn gen_adjuststack(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let n = jit.get_arg(0).as_usize();
    asm.stack_pop(n);
    Some(KeepCompiling)
}

fn gen_opt_plus(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let two_fixnums = match asm.ctx.two_fixnums_on_stack(jit) {
        Some(two_fixnums) => two_fixnums,
        None => {
            defer_compilation(jit, asm, ocb);
            return Some(EndBlock);
        }
    };

    if two_fixnums {
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_PLUS) {
            return None;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(jit, asm, ocb);

        // Get the operands from the stack
        let arg1 = asm.stack_pop(1);
        let arg0 = asm.stack_pop(1);

        // Add arg0 + arg1 and test for overflow
        let arg0_untag = asm.sub(arg0, Opnd::Imm(1));
        let out_val = asm.add(arg0_untag, arg1);
        asm.jo(Target::side_exit(Counter::opt_plus_overflow));

        // Push the output on the stack
        let dst = asm.stack_push(Type::Fixnum);
        asm.mov(dst, out_val);

        Some(KeepCompiling)
    } else {
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

// new array initialized from top N values
fn gen_newarray(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let n = jit.get_arg(0).as_u32();

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, asm);

    // If n is 0, then elts is never going to be read, so we can just pass null
    let values_ptr = if n == 0 {
        Opnd::UImm(0)
    } else {
        asm_comment!(asm, "load pointer to array elements");
        let offset_magnitude = (SIZEOF_VALUE as u32) * n;
        let values_opnd = asm.ctx.sp_opnd(-(offset_magnitude as isize));
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

    asm.stack_pop(n.as_usize());
    let stack_ret = asm.stack_push(Type::TArray);
    asm.mov(stack_ret, new_ary);

    Some(KeepCompiling)
}

// dup array
fn gen_duparray(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let ary = jit.get_arg(0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, asm);

    // call rb_ary_resurrect(VALUE ary);
    let new_ary = asm.ccall(
        rb_ary_resurrect as *const u8,
        vec![ary.into()],
    );

    let stack_ret = asm.stack_push(Type::TArray);
    asm.mov(stack_ret, new_ary);

    Some(KeepCompiling)
}

// dup hash
fn gen_duphash(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let hash = jit.get_arg(0);

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, asm);

    // call rb_hash_resurrect(VALUE hash);
    let hash = asm.ccall(rb_hash_resurrect as *const u8, vec![hash.into()]);

    let stack_ret = asm.stack_push(Type::Hash);
    asm.mov(stack_ret, hash);

    Some(KeepCompiling)
}

// call to_a on the array on the stack
fn gen_splatarray(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let flag = jit.get_arg(0).as_usize();

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, asm);

    // Get the operands from the stack
    let ary_opnd = asm.stack_opnd(0);

    // Call rb_vm_splat_array(flag, ary)
    let ary = asm.ccall(rb_vm_splat_array as *const u8, vec![flag.into(), ary_opnd]);
    asm.stack_pop(1); // Keep it on stack during ccall for GC

    let stack_ret = asm.stack_push(Type::TArray);
    asm.mov(stack_ret, ary);

    Some(KeepCompiling)
}

// call to_hash on hash to keyword splat before converting block
// e.g. foo(**object, &block)
fn gen_splatkw(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Save the PC and SP because the callee may allocate
    jit_prepare_routine_call(jit, asm);

    // Get the operands from the stack
    let block_opnd = asm.stack_opnd(0);
    let block_type = asm.ctx.get_opnd_type(block_opnd.into());
    let hash_opnd = asm.stack_opnd(1);

    let hash = asm.ccall(rb_to_hash_type as *const u8, vec![hash_opnd]);
    asm.stack_pop(2); // Keep it on stack during ccall for GC

    let stack_ret = asm.stack_push(Type::Hash);
    asm.mov(stack_ret, hash);
    asm.stack_push(block_type);
    // Leave block_opnd spilled by ccall as is
    asm.ctx.dealloc_temp_reg(asm.ctx.get_stack_size() - 1);

    Some(KeepCompiling)
}

// concat two arrays
fn gen_concatarray(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, asm);

    // Get the operands from the stack
    let ary2st_opnd = asm.stack_opnd(0);
    let ary1_opnd = asm.stack_opnd(1);

    // Call rb_vm_concat_array(ary1, ary2st)
    let ary = asm.ccall(rb_vm_concat_array as *const u8, vec![ary1_opnd, ary2st_opnd]);
    asm.stack_pop(2); // Keep them on stack during ccall for GC

    let stack_ret = asm.stack_push(Type::TArray);
    asm.mov(stack_ret, ary);

    Some(KeepCompiling)
}

// new range initialized from top 2 values
fn gen_newrange(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let flag = jit.get_arg(0).as_usize();

    // rb_range_new() allocates and can raise
    jit_prepare_routine_call(jit, asm);

    // val = rb_range_new(low, high, (int)flag);
    let range_opnd = asm.ccall(
        rb_range_new as *const u8,
        vec![
            asm.stack_opnd(1),
            asm.stack_opnd(0),
            flag.into()
        ]
    );

    asm.stack_pop(2);
    let stack_ret = asm.stack_push(Type::UnknownHeap);
    asm.mov(stack_ret, range_opnd);

    Some(KeepCompiling)
}

fn guard_object_is_heap(
    asm: &mut Assembler,
    object: Opnd,
    object_opnd: YARVOpnd,
    counter: Counter,
) {
    let object_type = asm.ctx.get_opnd_type(object_opnd);
    if object_type.is_heap() {
        return;
    }

    asm_comment!(asm, "guard object is heap");

    // Test that the object is not an immediate
    asm.test(object, (RUBY_IMMEDIATE_MASK as u64).into());
    asm.jnz(Target::side_exit(counter));

    // Test that the object is not false
    asm.cmp(object, Qfalse.into());
    asm.je(Target::side_exit(counter));

    if Type::UnknownHeap.diff(object_type) != TypeDiff::Incompatible {
        asm.ctx.upgrade_opnd_type(object_opnd, Type::UnknownHeap);
    }
}

fn guard_object_is_array(
    asm: &mut Assembler,
    object: Opnd,
    object_opnd: YARVOpnd,
    counter: Counter,
) {
    let object_type = asm.ctx.get_opnd_type(object_opnd);
    if object_type.is_array() {
        return;
    }

    let object_reg = match object {
        Opnd::InsnOut { .. } => object,
        _ => asm.load(object),
    };
    guard_object_is_heap(asm, object_reg, object_opnd, counter);

    asm_comment!(asm, "guard object is array");

    // Pull out the type mask
    let flags_opnd = Opnd::mem(VALUE_BITS, object_reg, RUBY_OFFSET_RBASIC_FLAGS);
    let flags_opnd = asm.and(flags_opnd, (RUBY_T_MASK as u64).into());

    // Compare the result with T_ARRAY
    asm.cmp(flags_opnd, (RUBY_T_ARRAY as u64).into());
    asm.jne(Target::side_exit(counter));

    if Type::UnknownHeap.diff(object_type) != TypeDiff::Incompatible {
        asm.ctx.upgrade_opnd_type(object_opnd, Type::TArray);
    }
}

fn guard_object_is_string(
    asm: &mut Assembler,
    object: Opnd,
    object_opnd: YARVOpnd,
    counter: Counter,
) {
    let object_type = asm.ctx.get_opnd_type(object_opnd);
    if object_type.is_string() {
        return;
    }

    let object_reg = match object {
        Opnd::InsnOut { .. } => object,
        _ => asm.load(object),
    };
    guard_object_is_heap(asm, object_reg, object_opnd, counter);

    asm_comment!(asm, "guard object is string");

    // Pull out the type mask
    let flags_reg = asm.load(Opnd::mem(VALUE_BITS, object_reg, RUBY_OFFSET_RBASIC_FLAGS));
    let flags_reg = asm.and(flags_reg, Opnd::UImm(RUBY_T_MASK as u64));

    // Compare the result with T_STRING
    asm.cmp(flags_reg, Opnd::UImm(RUBY_T_STRING as u64));
    asm.jne(Target::side_exit(counter));

    if Type::UnknownHeap.diff(object_type) != TypeDiff::Incompatible {
        asm.ctx.upgrade_opnd_type(object_opnd, Type::TString);
    }
}

/// This guards that a special flag is not set on a hash.
/// By passing a hash with this flag set as the last argument
/// in a splat call, you can change the way keywords are handled
/// to behave like ruby 2. We don't currently support this.
fn guard_object_is_not_ruby2_keyword_hash(
    asm: &mut Assembler,
    object_opnd: Opnd,
    counter: Counter,
) {
    asm_comment!(asm, "guard object is not ruby2 keyword hash");

    let not_ruby2_keyword = asm.new_label("not_ruby2_keyword");
    asm.test(object_opnd, (RUBY_IMMEDIATE_MASK as u64).into());
    asm.jnz(not_ruby2_keyword);

    asm.cmp(object_opnd, Qfalse.into());
    asm.je(not_ruby2_keyword);

    let flags_opnd = asm.load(Opnd::mem(
        VALUE_BITS,
        object_opnd,
        RUBY_OFFSET_RBASIC_FLAGS,
    ));
    let type_opnd = asm.and(flags_opnd, (RUBY_T_MASK as u64).into());

    asm.cmp(type_opnd, (RUBY_T_HASH as u64).into());
    asm.jne(not_ruby2_keyword);

    asm.test(flags_opnd, (RHASH_PASS_AS_KEYWORDS as u64).into());
    asm.jnz(Target::side_exit(counter));

    asm.write_label(not_ruby2_keyword);
}

/// This instruction pops a single value off the stack, converts it to an
/// arrayif it isn’t already one using the #to_ary method, and then pushes
/// the values from the array back onto the stack.
fn gen_expandarray(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Both arguments are rb_num_t which is unsigned
    let num = jit.get_arg(0).as_u32();
    let flag = jit.get_arg(1).as_usize();

    // If this instruction has the splat flag, then bail out.
    if flag & 0x01 != 0 {
        gen_counter_incr(asm, Counter::expandarray_splat);
        return None;
    }

    // If this instruction has the postarg flag, then bail out.
    if flag & 0x02 != 0 {
        gen_counter_incr(asm, Counter::expandarray_postarg);
        return None;
    }

    let array_opnd = asm.stack_opnd(0);

    // If the array operand is nil, just push on nils
    if asm.ctx.get_opnd_type(array_opnd.into()) == Type::Nil {
        asm.stack_pop(1); // pop after using the type info
        // special case for a, b = nil pattern
        // push N nils onto the stack
        for _ in 0..num {
            let push_opnd = asm.stack_push(Type::Nil);
            asm.mov(push_opnd, Qnil.into());
        }
        return Some(KeepCompiling);
    }

    // Defer compilation so we can specialize on a runtime `self`
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    let comptime_recv = jit.peek_at_stack(&asm.ctx, 0);

    // If the comptime receiver is not an array, bail
    if comptime_recv.class_of() != unsafe { rb_cArray } {
        gen_counter_incr(asm, Counter::expandarray_comptime_not_array);
        return None;
    }

    // Get the compile-time array length
    let comptime_len = unsafe { rb_yjit_array_len(comptime_recv) as u32 };

    // Move the array from the stack and check that it's an array.
    guard_object_is_array(
        asm,
        array_opnd,
        array_opnd.into(),
        Counter::expandarray_not_array,
    );

    // If we don't actually want any values, then just return.
    if num == 0 {
        asm.stack_pop(1); // pop the array
        return Some(KeepCompiling);
    }

    let array_opnd = asm.stack_opnd(0);
    let array_reg = asm.load(array_opnd);
    let array_len_opnd = get_array_len(asm, array_reg);

    // Guard on the comptime/expected array length
    if comptime_len >= num {
        asm_comment!(asm, "guard array length >= {}", num);
        asm.cmp(array_len_opnd, num.into());
        jit_chain_guard(
            JCC_JB,
            jit,
            asm,
            ocb,
            EXPANDARRAY_MAX_CHAIN_DEPTH,
            Counter::expandarray_chain_max_depth,
        );

    } else {
        asm_comment!(asm, "guard array length == {}", comptime_len);
        asm.cmp(array_len_opnd, comptime_len.into());
        jit_chain_guard(
            JCC_JNE,
            jit,
            asm,
            ocb,
            EXPANDARRAY_MAX_CHAIN_DEPTH,
            Counter::expandarray_chain_max_depth,
        );
    }

    let array_opnd = asm.stack_pop(1); // pop after using the type info

    // Load the pointer to the embedded or heap array
    let ary_opnd = if comptime_len > 0 {
        let array_reg = asm.load(array_opnd);
        Some(get_array_ptr(asm, array_reg))
    } else {
        None
    };

    // Loop backward through the array and push each element onto the stack.
    for i in (0..num).rev() {
        let top = asm.stack_push(if i < comptime_len { Type::Unknown } else { Type::Nil });
        let offset = i32::try_from(i * (SIZEOF_VALUE as u32)).unwrap();

        // Missing elements are Qnil
        asm_comment!(asm, "load array[{}]", i);
        let elem_opnd = if i < comptime_len { Opnd::mem(64, ary_opnd.unwrap(), offset) } else { Qnil.into() };
        asm.mov(top, elem_opnd);
    }

    Some(KeepCompiling)
}

// Compute the index of a local variable from its slot index
fn ep_offset_to_local_idx(iseq: IseqPtr, ep_offset: u32) -> u32 {
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
    //                   +------------------ep_offset---------------+
    //
    // See usages of local_var_name() from iseq.c for similar calculation.

    // Equivalent of iseq->body->local_table_size
    let local_table_size: i32 = unsafe { get_iseq_body_local_table_size(iseq) }
        .try_into()
        .unwrap();
    let op = (ep_offset - VM_ENV_DATA_SIZE) as i32;
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
        let offs = SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL;
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
    jit: &mut JITState,
    asm: &mut Assembler,
    ep_offset: u32,
    level: u32,
) -> Option<CodegenStatus> {
    // Load environment pointer EP (level 0) from CFP
    let ep_opnd = gen_get_ep(asm, level);

    // Load the local from the block
    // val = *(vm_get_ep(GET_EP(), level) - idx);
    let offs = -(SIZEOF_VALUE_I32 * ep_offset as i32);
    let local_opnd = Opnd::mem(64, ep_opnd, offs);

    // Write the local at SP
    let stack_top = if level == 0 {
        let local_idx = ep_offset_to_local_idx(jit.get_iseq(), ep_offset);
        asm.stack_push_local(local_idx.as_usize())
    } else {
        asm.stack_push(Type::Unknown)
    };

    asm.mov(stack_top, local_opnd);

    Some(KeepCompiling)
}

fn gen_getlocal(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let idx = jit.get_arg(0).as_u32();
    let level = jit.get_arg(1).as_u32();
    gen_getlocal_generic(jit, asm, idx, level)
}

fn gen_getlocal_wc0(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let idx = jit.get_arg(0).as_u32();
    gen_getlocal_generic(jit, asm, idx, 0)
}

fn gen_getlocal_wc1(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let idx = jit.get_arg(0).as_u32();
    gen_getlocal_generic(jit, asm, idx, 1)
}

fn gen_setlocal_generic(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ep_offset: u32,
    level: u32,
) -> Option<CodegenStatus> {
    let value_type = asm.ctx.get_opnd_type(StackOpnd(0));

    // Load environment pointer EP at level
    let ep_opnd = gen_get_ep(asm, level);

    // Fallback because of write barrier
    if asm.ctx.get_chain_depth() > 0
    {
        // Save the PC and SP because it runs GC
        jit_prepare_routine_call(jit, asm);

        // Pop the value to write from the stack
        let value_opnd = asm.stack_opnd(0);

        // void rb_vm_env_write(const VALUE *ep, int index, VALUE v)
        let index = -(ep_offset as i64);
        asm.ccall(
            rb_vm_env_write as *const u8,
            vec![
                ep_opnd,
                index.into(),
                value_opnd,
            ]
        );
        asm.stack_pop(1); // Keep it on stack during ccall for GC

        return Some(KeepCompiling);
    }

    // Write barriers may be required when VM_ENV_FLAG_WB_REQUIRED is set, however write barriers
    // only affect heap objects being written. If we know an immediate value is being written we
    // can skip this check.
    if !value_type.is_imm() {
        // flags & VM_ENV_FLAG_WB_REQUIRED
        let flags_opnd = Opnd::mem(
            64,
            ep_opnd,
            SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_FLAGS as i32,
        );
        asm.test(flags_opnd, VM_ENV_FLAG_WB_REQUIRED.into());

        // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
        assert!(asm.ctx.get_chain_depth() == 0);
        jit_chain_guard(
            JCC_JNZ,
            jit,
            asm,
            ocb,
            1,
            Counter::setlocal_wb_required,
        );
    }

    if level == 0 {
        let local_idx = ep_offset_to_local_idx(jit.get_iseq(), ep_offset).as_usize();
        asm.ctx.set_local_type(local_idx, value_type);
    }

    // Pop the value to write from the stack
    let stack_top = asm.stack_pop(1);

    // Write the value at the environment pointer
    let offs = -(SIZEOF_VALUE_I32 * ep_offset as i32);
    asm.mov(Opnd::mem(64, ep_opnd, offs), stack_top);

    Some(KeepCompiling)
}

fn gen_setlocal(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let idx = jit.get_arg(0).as_u32();
    let level = jit.get_arg(1).as_u32();
    gen_setlocal_generic(jit, asm, ocb, idx, level)
}

fn gen_setlocal_wc0(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let idx = jit.get_arg(0).as_u32();
    gen_setlocal_generic(jit, asm, ocb, idx, 0)
}

fn gen_setlocal_wc1(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let idx = jit.get_arg(0).as_u32();
    gen_setlocal_generic(jit, asm, ocb, idx, 1)
}

// new hash initialized from top N values
fn gen_newhash(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let num: u64 = jit.get_arg(0).as_u64();

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, asm);

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
        let stack_addr_from_top = asm.lea(asm.stack_opnd((num - 1) as i32));

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

        asm.stack_pop(num.try_into().unwrap());
        let stack_ret = asm.stack_push(Type::Hash);
        asm.mov(stack_ret, new_hash);
    } else {
        // val = rb_hash_new();
        let new_hash = asm.ccall(rb_hash_new as *const u8, vec![]);
        let stack_ret = asm.stack_push(Type::Hash);
        asm.mov(stack_ret, new_hash);
    }

    Some(KeepCompiling)
}

fn gen_putstring(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let put_val = jit.get_arg(0);

    // Save the PC and SP because the callee will allocate
    jit_prepare_routine_call(jit, asm);

    let str_opnd = asm.ccall(
        rb_ec_str_resurrect as *const u8,
        vec![EC, put_val.into()]
    );

    let stack_top = asm.stack_push(Type::TString);
    asm.mov(stack_top, str_opnd);

    Some(KeepCompiling)
}

fn gen_checkmatch(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let flag = jit.get_arg(0).as_u32();

    // rb_vm_check_match is not leaf unless flag is VM_CHECKMATCH_TYPE_WHEN.
    // See also: leafness_of_checkmatch() and check_match()
    if flag != VM_CHECKMATCH_TYPE_WHEN {
        jit_prepare_routine_call(jit, asm);
    }

    let pattern = asm.stack_opnd(0);
    let target = asm.stack_opnd(1);

    extern "C" {
        fn rb_vm_check_match(ec: EcPtr, target: VALUE, pattern: VALUE, num: u32) -> VALUE;
    }
    let result = asm.ccall(rb_vm_check_match as *const u8, vec![EC, target, pattern, flag.into()]);
    asm.stack_pop(2); // Keep them on stack during ccall for GC

    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, result);

    Some(KeepCompiling)
}

// Push Qtrue or Qfalse depending on whether the given keyword was supplied by
// the caller
fn gen_checkkeyword(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // When a keyword is unspecified past index 32, a hash will be used
    // instead. This can only happen in iseqs taking more than 32 keywords.
    if unsafe { (*get_iseq_body_param_keyword(jit.iseq)).num >= 32 } {
        return None;
    }

    // The EP offset to the undefined bits local
    let bits_offset = jit.get_arg(0).as_i32();

    // The index of the keyword we want to check
    let index: i64 = jit.get_arg(1).as_i64();

    // Load environment pointer EP
    let ep_opnd = gen_get_ep(asm, 0);

    // VALUE kw_bits = *(ep - bits);
    let bits_opnd = Opnd::mem(64, ep_opnd, SIZEOF_VALUE_I32 * -bits_offset);

    // unsigned int b = (unsigned int)FIX2ULONG(kw_bits);
    // if ((b & (0x01 << idx))) {
    //
    // We can skip the FIX2ULONG conversion by shifting the bit we test
    let bit_test: i64 = 0x01 << (index + 1);
    asm.test(bits_opnd, Opnd::Imm(bit_test));
    let ret_opnd = asm.csel_z(Qtrue.into(), Qfalse.into());

    let stack_ret = asm.stack_push(Type::UnknownImm);
    asm.mov(stack_ret, ret_opnd);

    Some(KeepCompiling)
}

// Generate a jump to a stub that recompiles the current YARV instruction on failure.
// When depth_limit is exceeded, generate a jump to a side exit.
fn jit_chain_guard(
    jcc: JCCKinds,
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    depth_limit: i32,
    counter: Counter,
) {
    let target0_gen_fn = match jcc {
        JCC_JNE | JCC_JNZ => BranchGenFn::JNZToTarget0,
        JCC_JZ | JCC_JE => BranchGenFn::JZToTarget0,
        JCC_JBE | JCC_JNA => BranchGenFn::JBEToTarget0,
        JCC_JB | JCC_JNAE => BranchGenFn::JBToTarget0,
        JCC_JO_MUL => BranchGenFn::JOMulToTarget0,
    };

    if (asm.ctx.get_chain_depth() as i32) < depth_limit {
        // Rewind Context to use the stack_size at the beginning of this instruction.
        let mut deeper = asm.ctx.with_stack_size(jit.stack_size_for_pc);
        deeper.increment_chain_depth();
        let bid = BlockId {
            iseq: jit.iseq,
            idx: jit.insn_idx,
        };

        gen_branch(jit, asm, ocb, bid, &deeper, None, None, target0_gen_fn);
    } else {
        target0_gen_fn.call(asm, Target::side_exit(counter), None);
    }
}

// up to 8 different shapes for each
pub const GET_IVAR_MAX_DEPTH: i32 = 8;

// up to 8 different shapes for each
pub const SET_IVAR_MAX_DEPTH: i32 = 8;

// hashes and arrays
pub const OPT_AREF_MAX_CHAIN_DEPTH: i32 = 2;

// expandarray
pub const EXPANDARRAY_MAX_CHAIN_DEPTH: i32 = 4;

// up to 5 different methods for send
pub const SEND_MAX_DEPTH: i32 = 5;

// up to 20 different offsets for case-when
pub const CASE_WHEN_MAX_DEPTH: i32 = 20;

pub const MAX_SPLAT_LENGTH: i32 = 127;

// Codegen for setting an instance variable.
// Preconditions:
//   - receiver is in REG0
//   - receiver has the same class as CLASS_OF(comptime_receiver)
//   - no stack push or pops to ctx since the entry to the codegen of the instruction being compiled
fn gen_set_ivar(
    jit: &mut JITState,
    asm: &mut Assembler,
    ivar_name: ID,
    flags: u32,
    argc: i32,
) -> Option<CodegenStatus> {

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc);
    }

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, asm);

    // Get the operands from the stack
    let val_opnd = asm.stack_opnd(0);
    let recv_opnd = asm.stack_opnd(1);

    // Call rb_vm_set_ivar_id with the receiver, the ivar name, and the value
    let val = asm.ccall(
        rb_vm_set_ivar_id as *const u8,
        vec![
            recv_opnd,
            Opnd::UImm(ivar_name),
            val_opnd,
        ],
    );
    asm.stack_pop(2); // Keep them on stack during ccall for GC

    let out_opnd = asm.stack_push(Type::Unknown);
    asm.mov(out_opnd, val);

    Some(KeepCompiling)
}

// Codegen for getting an instance variable.
// Preconditions:
//   - receiver has the same class as CLASS_OF(comptime_receiver)
//   - no stack push or pops to ctx since the entry to the codegen of the instruction being compiled
fn gen_get_ivar(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    max_chain_depth: i32,
    comptime_receiver: VALUE,
    ivar_name: ID,
    recv: Opnd,
    recv_opnd: YARVOpnd,
) -> Option<CodegenStatus> {
    let comptime_val_klass = comptime_receiver.class_of();

    // If recv isn't already a register, load it.
    let recv = match recv {
        Opnd::InsnOut { .. } => recv,
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
    // Use a general C call at the last chain to avoid exits on megamorphic shapes
    let megamorphic = asm.ctx.get_chain_depth() as i32 >= max_chain_depth;
    if megamorphic {
        gen_counter_incr(asm, Counter::num_getivar_megamorphic);
    }

    // If the class uses the default allocator, instances should all be T_OBJECT
    // NOTE: This assumes nobody changes the allocator of the class after allocation.
    //       Eventually, we can encode whether an object is T_OBJECT or not
    //       inside object shapes.
    // too-complex shapes can't use index access, so we use rb_ivar_get for them too.
    if !receiver_t_object || uses_custom_allocator || comptime_receiver.shape_too_complex() || megamorphic {
        // General case. Call rb_ivar_get().
        // VALUE rb_ivar_get(VALUE obj, ID id)
        asm_comment!(asm, "call rb_ivar_get()");

        // The function could raise exceptions.
        jit_prepare_routine_call(jit, asm);

        let ivar_val = asm.ccall(rb_ivar_get as *const u8, vec![recv, Opnd::UImm(ivar_name)]);

        if recv_opnd != SelfOpnd {
            asm.stack_pop(1);
        }

        // Push the ivar on the stack
        let out_opnd = asm.stack_push(Type::Unknown);
        asm.mov(out_opnd, ivar_val);

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, asm, ocb);
        return Some(EndBlock);
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

    // Guard heap object (recv_opnd must be used before stack_pop)
    guard_object_is_heap(asm, recv, recv_opnd, Counter::getivar_not_heap);

    // Compile time self is embedded and the ivar index lands within the object
    let embed_test_result = unsafe { FL_TEST_RAW(comptime_receiver, VALUE(ROBJECT_EMBED.as_usize())) != VALUE(0) };

    let expected_shape = unsafe { rb_shape_get_shape_id(comptime_receiver) };
    let shape_id_offset = unsafe { rb_shape_id_offset() };
    let shape_opnd = Opnd::mem(SHAPE_ID_NUM_BITS as u8, recv, shape_id_offset);

    asm_comment!(asm, "guard shape");
    asm.cmp(shape_opnd, Opnd::UImm(expected_shape as u64));
    jit_chain_guard(
        JCC_JNE,
        jit,
        asm,
        ocb,
        max_chain_depth,
        Counter::getivar_megamorphic,
    );

    // Pop receiver if it's on the temp stack
    if recv_opnd != SelfOpnd {
        asm.stack_pop(1);
    }

    match ivar_index {
        // If there is no IVAR index, then the ivar was undefined
        // when we entered the compiler.  That means we can just return
        // nil for this shape + iv name
        None => {
            let out_opnd = asm.stack_push(Type::Nil);
            asm.mov(out_opnd, Qnil.into());
        }
        Some(ivar_index) => {
            if embed_test_result {
                // See ROBJECT_IVPTR() from include/ruby/internal/core/robject.h

                // Load the variable
                let offs = ROBJECT_OFFSET_AS_ARY as i32 + (ivar_index * SIZEOF_VALUE) as i32;
                let ivar_opnd = Opnd::mem(64, recv, offs);

                // Push the ivar on the stack
                let out_opnd = asm.stack_push(Type::Unknown);
                asm.mov(out_opnd, ivar_opnd);
            } else {
                // Compile time value is *not* embedded.

                // Get a pointer to the extended table
                let tbl_opnd = asm.load(Opnd::mem(64, recv, ROBJECT_OFFSET_AS_HEAP_IVPTR as i32));

                // Read the ivar from the extended table
                let ivar_opnd = Opnd::mem(64, tbl_opnd, (SIZEOF_VALUE * ivar_index) as i32);

                let out_opnd = asm.stack_push(Type::Unknown);
                asm.mov(out_opnd, ivar_opnd);
            }
        }
    }

    // Jump to next instruction. This allows guard chains to share the same successor.
    jump_to_next_insn(jit, asm, ocb);
    Some(EndBlock)
}

fn gen_getinstancevariable(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    let ivar_name = jit.get_arg(0).as_u64();

    let comptime_val = jit.peek_at_self();

    // Guard that the receiver has the same class as the one from compile time.
    let self_asm_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF);

    gen_get_ivar(
        jit,
        asm,
        ocb,
        GET_IVAR_MAX_DEPTH,
        comptime_val,
        ivar_name,
        self_asm_opnd,
        SelfOpnd,
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
        let offs = ROBJECT_OFFSET_AS_ARY as i32 + (ivar_index * SIZEOF_VALUE) as i32;
        let ivar_opnd = Opnd::mem(64, recv, offs);

        // Write the IV
        asm_comment!(asm, "write IV");
        asm.mov(ivar_opnd, set_value);
    } else {
        // Compile time value is *not* embedded.

        // Get a pointer to the extended table
        let tbl_opnd = asm.load(Opnd::mem(64, recv, ROBJECT_OFFSET_AS_HEAP_IVPTR as i32));

        // Write the ivar in to the extended table
        let ivar_opnd = Opnd::mem(64, tbl_opnd, (SIZEOF_VALUE * ivar_index) as i32);

        asm_comment!(asm, "write IV");
        asm.mov(ivar_opnd, set_value);
    }
}

fn gen_setinstancevariable(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    let ivar_name = jit.get_arg(0).as_u64();
    let comptime_receiver = jit.peek_at_self();
    let comptime_val_klass = comptime_receiver.class_of();

    // If the comptime receiver is frozen, writing an IV will raise an exception
    // and we don't want to JIT code to deal with that situation.
    if comptime_receiver.is_frozen() {
        gen_counter_incr(asm, Counter::setivar_frozen);
        return None;
    }

    let stack_type = asm.ctx.get_opnd_type(StackOpnd(0));

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
    // Use a general C call at the last chain to avoid exits on megamorphic shapes
    let megamorphic = asm.ctx.get_chain_depth() as i32 >= SET_IVAR_MAX_DEPTH;
    if megamorphic {
        gen_counter_incr(asm, Counter::num_setivar_megamorphic);
    }

    // Get the iv index
    let shape_too_complex = comptime_receiver.shape_too_complex();
    let ivar_index = if !shape_too_complex {
        let shape_id = comptime_receiver.shape_id_of();
        let shape = unsafe { rb_shape_get_shape_by_id(shape_id) };
        let mut ivar_index: u32 = 0;
        if unsafe { rb_shape_get_iv_index(shape, ivar_name, &mut ivar_index) } {
            Some(ivar_index as usize)
        } else {
            None
        }
    } else {
        None
    };

    // The current shape doesn't contain this iv, we need to transition to another shape.
    let new_shape = if !shape_too_complex && receiver_t_object && ivar_index.is_none() {
        let current_shape = comptime_receiver.shape_of();
        let next_shape = unsafe { rb_shape_get_next(current_shape, comptime_receiver, ivar_name) };
        let next_shape_id = unsafe { rb_shape_id(next_shape) };

        // If the VM ran out of shapes, or this class generated too many leaf,
        // it may be de-optimized into OBJ_TOO_COMPLEX_SHAPE (hash-table).
        if next_shape_id == OBJ_TOO_COMPLEX_SHAPE_ID {
            Some((next_shape_id, None, 0_usize))
        } else {
            let current_capacity = unsafe { (*current_shape).capacity };

            // If the new shape has a different capacity, or is TOO_COMPLEX, we'll have to
            // reallocate it.
            let needs_extension = unsafe { (*current_shape).capacity != (*next_shape).capacity };

            // We can write to the object, but we need to transition the shape
            let ivar_index = unsafe { (*current_shape).next_iv_index } as usize;

            let needs_extension = if needs_extension {
                Some((current_capacity, unsafe { (*next_shape).capacity }))
            } else {
                None
            };
            Some((next_shape_id, needs_extension, ivar_index))
        }
    } else {
        None
    };
    let new_shape_too_complex = matches!(new_shape, Some((OBJ_TOO_COMPLEX_SHAPE_ID, _, _)));

    // If the receiver isn't a T_OBJECT, or uses a custom allocator,
    // then just write out the IV write as a function call.
    // too-complex shapes can't use index access, so we use rb_ivar_get for them too.
    if !receiver_t_object || uses_custom_allocator || shape_too_complex || new_shape_too_complex || megamorphic {
        asm_comment!(asm, "call rb_vm_setinstancevariable()");

        let ic = jit.get_arg(1).as_u64(); // type IVC

        // The function could raise exceptions.
        // Note that this modifies REG_SP, which is why we do it first
        jit_prepare_routine_call(jit, asm);

        // Get the operands from the stack
        let val_opnd = asm.stack_opnd(0);

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
        asm.stack_pop(1); // Keep it on stack during ccall for GC
    } else {
        // Get the receiver
        let mut recv = asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF));

        let recv_opnd = SelfOpnd;

        // Upgrade type
        guard_object_is_heap(asm, recv, recv_opnd, Counter::setivar_not_heap);

        let expected_shape = unsafe { rb_shape_get_shape_id(comptime_receiver) };
        let shape_id_offset = unsafe { rb_shape_id_offset() };
        let shape_opnd = Opnd::mem(SHAPE_ID_NUM_BITS as u8, recv, shape_id_offset);

        asm_comment!(asm, "guard shape");
        asm.cmp(shape_opnd, Opnd::UImm(expected_shape as u64));
        jit_chain_guard(
            JCC_JNE,
            jit,
            asm,
            ocb,
            SET_IVAR_MAX_DEPTH,
            Counter::setivar_megamorphic,
        );

        asm.spill_temps(); // for ccall (must be done before write_val is popped)
        let write_val;

        match ivar_index {
            // If we don't have an instance variable index, then we need to
            // transition out of the current shape.
            None => {
                let (new_shape_id, needs_extension, ivar_index) = new_shape.unwrap();
                if let Some((current_capacity, new_capacity)) = needs_extension {
                    // Generate the C call so that runtime code will increase
                    // the capacity and set the buffer.
                    asm_comment!(asm, "call rb_ensure_iv_list_size");

                    // It allocates so can trigger GC, which takes the VM lock
                    // so could yield to a different ractor.
                    jit_prepare_routine_call(jit, asm);
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

                write_val = asm.stack_pop(1);
                gen_write_iv(asm, comptime_receiver, recv, ivar_index, write_val, needs_extension.is_some());

                asm_comment!(asm, "write shape");

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
                write_val = asm.stack_pop(1);
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

            asm_comment!(asm, "write barrier");
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

    Some(KeepCompiling)
}

fn gen_defined(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let op_type = jit.get_arg(0).as_u64();
    let obj = jit.get_arg(1);
    let pushval = jit.get_arg(2);

    // Save the PC and SP because the callee may allocate
    // Note that this modifies REG_SP, which is why we do it first
    jit_prepare_routine_call(jit, asm);

    // Get the operands from the stack
    let v_opnd = asm.stack_opnd(0);

    // Call vm_defined(ec, reg_cfp, op_type, obj, v)
    let def_result = asm.ccall(rb_vm_defined as *const u8, vec![EC, CFP, op_type.into(), obj.into(), v_opnd]);
    asm.stack_pop(1); // Keep it on stack during ccall for GC

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
    let stack_ret = asm.stack_push(out_type);
    asm.mov(stack_ret, out_value);

    Some(KeepCompiling)
}

fn gen_definedivar(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Defer compilation so we can specialize base on a runtime receiver
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    let ivar_name = jit.get_arg(0).as_u64();
    // Value that will be pushed on the stack if the ivar is defined. In practice this is always the
    // string "instance-variable". If the ivar is not defined, nil will be pushed instead.
    let pushval = jit.get_arg(2);

    // Get the receiver
    let recv = asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF));

    // Specialize base on compile time values
    let comptime_receiver = jit.peek_at_self();

    if comptime_receiver.shape_too_complex() || asm.ctx.get_chain_depth() as i32 >= GET_IVAR_MAX_DEPTH {
        // Fall back to calling rb_ivar_defined

        // Save the PC and SP because the callee may allocate
        // Note that this modifies REG_SP, which is why we do it first
        jit_prepare_routine_call(jit, asm);

        // Call rb_ivar_defined(recv, ivar_name)
        let def_result = asm.ccall(rb_ivar_defined as *const u8, vec![recv, ivar_name.into()]);

        // if (rb_ivar_defined(recv, ivar_name)) {
        //  val = pushval;
        // }
        asm.test(def_result, Opnd::UImm(255));
        let out_value = asm.csel_nz(pushval.into(), Qnil.into());

        // Push the return value onto the stack
        let out_type = if pushval.special_const_p() { Type::UnknownImm } else { Type::Unknown };
        let stack_ret = asm.stack_push(out_type);
        asm.mov(stack_ret, out_value);

        return Some(KeepCompiling)
    }

    let shape_id = comptime_receiver.shape_id_of();
    let ivar_exists = unsafe {
        let shape = rb_shape_get_shape_by_id(shape_id);
        let mut ivar_index: u32 = 0;
        rb_shape_get_iv_index(shape, ivar_name, &mut ivar_index)
    };

    // Guard heap object (recv_opnd must be used before stack_pop)
    guard_object_is_heap(asm, recv, SelfOpnd, Counter::definedivar_not_heap);

    let shape_id_offset = unsafe { rb_shape_id_offset() };
    let shape_opnd = Opnd::mem(SHAPE_ID_NUM_BITS as u8, recv, shape_id_offset);

    asm_comment!(asm, "guard shape");
    asm.cmp(shape_opnd, Opnd::UImm(shape_id as u64));
    jit_chain_guard(
        JCC_JNE,
        jit,
        asm,
        ocb,
        GET_IVAR_MAX_DEPTH,
        Counter::definedivar_megamorphic,
    );

    let result = if ivar_exists { pushval } else { Qnil };
    jit_putobject(asm, result);

    // Jump to next instruction. This allows guard chains to share the same successor.
    jump_to_next_insn(jit, asm, ocb);

    return Some(EndBlock);
}

fn gen_checktype(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let type_val = jit.get_arg(0).as_u32();

    // Only three types are emitted by compile.c at the moment
    if let RUBY_T_STRING | RUBY_T_ARRAY | RUBY_T_HASH = type_val {
        let val_type = asm.ctx.get_opnd_type(StackOpnd(0));
        let val = asm.stack_pop(1);

        // Check if we know from type information
        match val_type.known_value_type() {
            Some(value_type) => {
                if value_type == type_val {
                    jit_putobject(asm, Qtrue);
                    return Some(KeepCompiling);
                } else {
                    jit_putobject(asm, Qfalse);
                    return Some(KeepCompiling);
                }
            },
            _ => (),
        }

        let ret = asm.new_label("ret");

        let val = asm.load(val);
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
        let stack_ret = asm.stack_push(Type::UnknownImm);
        asm.mov(stack_ret, ret_opnd);

        Some(KeepCompiling)
    } else {
        None
    }
}

fn gen_concatstrings(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let n = jit.get_arg(0).as_usize();

    // Save the PC and SP because we are allocating
    jit_prepare_routine_call(jit, asm);

    let values_ptr = asm.lea(asm.ctx.sp_opnd(-((SIZEOF_VALUE as isize) * n as isize)));

    // call rb_str_concat_literals(size_t n, const VALUE *strings);
    let return_value = asm.ccall(
        rb_str_concat_literals as *const u8,
        vec![n.into(), values_ptr]
    );

    asm.stack_pop(n);
    let stack_ret = asm.stack_push(Type::TString);
    asm.mov(stack_ret, return_value);

    Some(KeepCompiling)
}

fn guard_two_fixnums(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) {
    let counter = Counter::guard_send_not_fixnums;

    // Get stack operands without popping them
    let arg1 = asm.stack_opnd(0);
    let arg0 = asm.stack_opnd(1);

    // Get the stack operand types
    let arg1_type = asm.ctx.get_opnd_type(arg1.into());
    let arg0_type = asm.ctx.get_opnd_type(arg0.into());

    if arg0_type.is_heap() || arg1_type.is_heap() {
        asm_comment!(asm, "arg is heap object");
        asm.jmp(Target::side_exit(counter));
        return;
    }

    if arg0_type != Type::Fixnum && arg0_type.is_specific() {
        asm_comment!(asm, "arg0 not fixnum");
        asm.jmp(Target::side_exit(counter));
        return;
    }

    if arg1_type != Type::Fixnum && arg1_type.is_specific() {
        asm_comment!(asm, "arg1 not fixnum");
        asm.jmp(Target::side_exit(counter));
        return;
    }

    assert!(!arg0_type.is_heap());
    assert!(!arg1_type.is_heap());
    assert!(arg0_type == Type::Fixnum || arg0_type.is_unknown());
    assert!(arg1_type == Type::Fixnum || arg1_type.is_unknown());

    // If not fixnums at run-time, fall back
    if arg0_type != Type::Fixnum {
        asm_comment!(asm, "guard arg0 fixnum");
        asm.test(arg0, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));

        jit_chain_guard(
            JCC_JZ,
            jit,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            counter,
        );
    }
    if arg1_type != Type::Fixnum {
        asm_comment!(asm, "guard arg1 fixnum");
        asm.test(arg1, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));

        jit_chain_guard(
            JCC_JZ,
            jit,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            counter,
        );
    }

    // Set stack types in context
    asm.ctx.upgrade_opnd_type(arg1.into(), Type::Fixnum);
    asm.ctx.upgrade_opnd_type(arg0.into(), Type::Fixnum);
}

// Conditional move operation used by comparison operators
type CmovFn = fn(cb: &mut Assembler, opnd0: Opnd, opnd1: Opnd) -> Opnd;

fn gen_fixnum_cmp(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    cmov_op: CmovFn,
    bop: ruby_basic_operators,
) -> Option<CodegenStatus> {
    let two_fixnums = match asm.ctx.two_fixnums_on_stack(jit) {
        Some(two_fixnums) => two_fixnums,
        None => {
            // Defer compilation so we can specialize based on a runtime receiver
            defer_compilation(jit, asm, ocb);
            return Some(EndBlock);
        }
    };

    if two_fixnums {
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, bop) {
            return None;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(jit, asm, ocb);

        // Get the operands from the stack
        let arg1 = asm.stack_pop(1);
        let arg0 = asm.stack_pop(1);

        // Compare the arguments
        asm.cmp(arg0, arg1);
        let bool_opnd = cmov_op(asm, Qtrue.into(), Qfalse.into());

        // Push the output on the stack
        let dst = asm.stack_push(Type::UnknownImm);
        asm.mov(dst, bool_opnd);

        Some(KeepCompiling)
    } else {
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_lt(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    gen_fixnum_cmp(jit, asm, ocb, Assembler::csel_l, BOP_LT)
}

fn gen_opt_le(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    gen_fixnum_cmp(jit, asm, ocb, Assembler::csel_le, BOP_LE)
}

fn gen_opt_ge(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    gen_fixnum_cmp(jit, asm, ocb, Assembler::csel_ge, BOP_GE)
}

fn gen_opt_gt(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    gen_fixnum_cmp(jit, asm, ocb, Assembler::csel_g, BOP_GT)
}

// Implements specialized equality for either two fixnum or two strings
// Returns None if enough type information isn't available, Some(true)
// if code was generated, otherwise Some(false).
fn gen_equality_specialized(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    gen_eq: bool,
) -> Option<bool> {
    let a_opnd = asm.stack_opnd(1);
    let b_opnd = asm.stack_opnd(0);

    let two_fixnums = match asm.ctx.two_fixnums_on_stack(jit) {
        Some(two_fixnums) => two_fixnums,
        None => return None,
    };

    if two_fixnums {
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_EQ) {
            // if overridden, emit the generic version
            return Some(false);
        }

        guard_two_fixnums(jit, asm, ocb);

        asm.cmp(a_opnd, b_opnd);
        let val = if gen_eq {
            asm.csel_e(Qtrue.into(), Qfalse.into())
        } else {
            asm.csel_ne(Qtrue.into(), Qfalse.into())
        };

        // Push the output on the stack
        asm.stack_pop(2);
        let dst = asm.stack_push(Type::UnknownImm);
        asm.mov(dst, val);

        return Some(true);
    }

    if !jit.at_current_insn() {
        return None;
    }
    let comptime_a = jit.peek_at_stack(&asm.ctx, 1);
    let comptime_b = jit.peek_at_stack(&asm.ctx, 0);

    if unsafe { comptime_a.class_of() == rb_cString && comptime_b.class_of() == rb_cString } {
        if !assume_bop_not_redefined(jit, asm, ocb, STRING_REDEFINED_OP_FLAG, BOP_EQ) {
            // if overridden, emit the generic version
            return Some(false);
        }

        // Guard that a is a String
        jit_guard_known_klass(
            jit,
            asm,
            ocb,
            unsafe { rb_cString },
            a_opnd,
            a_opnd.into(),
            comptime_a,
            SEND_MAX_DEPTH,
            Counter::guard_send_not_string,
        );

        let equal = asm.new_label("equal");
        let ret = asm.new_label("ret");

        // Spill for ccall. For safety, unconditionally spill temps before branching.
        asm.spill_temps();

        // If they are equal by identity, return true
        asm.cmp(a_opnd, b_opnd);
        asm.je(equal);

        // Otherwise guard that b is a T_STRING (from type info) or String (from runtime guard)
        let btype = asm.ctx.get_opnd_type(b_opnd.into());
        if btype.known_value_type() != Some(RUBY_T_STRING) {
            // Note: any T_STRING is valid here, but we check for a ::String for simplicity
            // To pass a mutable static variable (rb_cString) requires an unsafe block
            jit_guard_known_klass(
                jit,
                asm,
                ocb,
                unsafe { rb_cString },
                b_opnd,
                b_opnd.into(),
                comptime_b,
                SEND_MAX_DEPTH,
                Counter::guard_send_not_string,
            );
        }

        // Call rb_str_eql_internal(a, b)
        let val = asm.ccall(
            if gen_eq { rb_str_eql_internal } else { rb_str_neq_internal } as *const u8,
            vec![a_opnd, b_opnd],
        );

        // Push the output on the stack
        asm.stack_pop(2);
        let dst = asm.stack_push(Type::UnknownImm);
        asm.mov(dst, val);
        asm.jmp(ret);

        asm.write_label(equal);
        asm.mov(dst, if gen_eq { Qtrue } else { Qfalse }.into());

        asm.write_label(ret);

        Some(true)
    } else {
        Some(false)
    }
}

fn gen_opt_eq(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let specialized = match gen_equality_specialized(jit, asm, ocb, true) {
        Some(specialized) => specialized,
        None => {
            // Defer compilation so we can specialize base on a runtime receiver
            defer_compilation(jit, asm, ocb);
            return Some(EndBlock);
        }
    };

    if specialized {
        jump_to_next_insn(jit, asm, ocb);
        Some(EndBlock)
    } else {
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_neq(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // opt_neq is passed two rb_call_data as arguments:
    // first for ==, second for !=
    let cd = jit.get_arg(1).as_ptr();
    return gen_send_general(jit, asm, ocb, cd, None);
}

fn gen_opt_aref(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let cd: *const rb_call_data = jit.get_arg(0).as_ptr();
    let argc = unsafe { vm_ci_argc((*cd).ci) };

    // Only JIT one arg calls like `ary[6]`
    if argc != 1 {
        gen_counter_incr(asm, Counter::opt_aref_argc_not_one);
        return None;
    }

    // Defer compilation so we can specialize base on a runtime receiver
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    // Specialize base on compile time values
    let comptime_idx = jit.peek_at_stack(&asm.ctx, 0);
    let comptime_recv = jit.peek_at_stack(&asm.ctx, 1);

    if comptime_recv.class_of() == unsafe { rb_cArray } && comptime_idx.fixnum_p() {
        if !assume_bop_not_redefined(jit, asm, ocb, ARRAY_REDEFINED_OP_FLAG, BOP_AREF) {
            return None;
        }

        // Get the stack operands
        let idx_opnd = asm.stack_opnd(0);
        let recv_opnd = asm.stack_opnd(1);

        // Guard that the receiver is an ::Array
        // BOP_AREF check above is only good for ::Array.
        jit_guard_known_klass(
            jit,
            asm,
            ocb,
            unsafe { rb_cArray },
            recv_opnd,
            recv_opnd.into(),
            comptime_recv,
            OPT_AREF_MAX_CHAIN_DEPTH,
            Counter::opt_aref_not_array,
        );

        // Bail if idx is not a FIXNUM
        let idx_reg = asm.load(idx_opnd);
        asm.test(idx_reg, (RUBY_FIXNUM_FLAG as u64).into());
        asm.jz(Target::side_exit(Counter::opt_aref_arg_not_fixnum));

        // Call VALUE rb_ary_entry_internal(VALUE ary, long offset).
        // It never raises or allocates, so we don't need to write to cfp->pc.
        {
            // Pop the argument and the receiver
            asm.stack_pop(2);

            let idx_reg = asm.rshift(idx_reg, Opnd::UImm(1)); // Convert fixnum to int
            let val = asm.ccall(rb_ary_entry_internal as *const u8, vec![recv_opnd, idx_reg]);

            // Push the return value onto the stack
            let stack_ret = asm.stack_push(Type::Unknown);
            asm.mov(stack_ret, val);
        }

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, asm, ocb);
        return Some(EndBlock);
    } else if comptime_recv.class_of() == unsafe { rb_cHash } {
        if !assume_bop_not_redefined(jit, asm, ocb, HASH_REDEFINED_OP_FLAG, BOP_AREF) {
            return None;
        }

        let recv_opnd = asm.stack_opnd(1);

        // Guard that the receiver is a hash
        jit_guard_known_klass(
            jit,
            asm,
            ocb,
            unsafe { rb_cHash },
            recv_opnd,
            recv_opnd.into(),
            comptime_recv,
            OPT_AREF_MAX_CHAIN_DEPTH,
            Counter::opt_aref_not_hash,
        );

        // Prepare to call rb_hash_aref(). It might call #hash on the key.
        jit_prepare_routine_call(jit, asm);

        // Call rb_hash_aref
        let key_opnd = asm.stack_opnd(0);
        let recv_opnd = asm.stack_opnd(1);
        let val = asm.ccall(rb_hash_aref as *const u8, vec![recv_opnd, key_opnd]);

        // Pop the key and the receiver
        asm.stack_pop(2);

        // Push the return value onto the stack
        let stack_ret = asm.stack_push(Type::Unknown);
        asm.mov(stack_ret, val);

        // Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, asm, ocb);
        Some(EndBlock)
    } else {
        // General case. Call the [] method.
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_aset(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Defer compilation so we can specialize on a runtime `self`
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    let comptime_recv = jit.peek_at_stack(&asm.ctx, 2);
    let comptime_key = jit.peek_at_stack(&asm.ctx, 1);

    // Get the operands from the stack
    let recv = asm.stack_opnd(2);
    let key = asm.stack_opnd(1);
    let _val = asm.stack_opnd(0);

    if comptime_recv.class_of() == unsafe { rb_cArray } && comptime_key.fixnum_p() {
        // Guard receiver is an Array
        jit_guard_known_klass(
            jit,
            asm,
            ocb,
            unsafe { rb_cArray },
            recv,
            recv.into(),
            comptime_recv,
            SEND_MAX_DEPTH,
            Counter::opt_aset_not_array,
        );

        // Guard key is a fixnum
        jit_guard_known_klass(
            jit,
            asm,
            ocb,
            unsafe { rb_cInteger },
            key,
            key.into(),
            comptime_key,
            SEND_MAX_DEPTH,
            Counter::opt_aset_not_fixnum,
        );

        // We might allocate or raise
        jit_prepare_routine_call(jit, asm);

        // Call rb_ary_store
        let recv = asm.stack_opnd(2);
        let key = asm.load(asm.stack_opnd(1));
        let key = asm.rshift(key, Opnd::UImm(1)); // FIX2LONG(key)
        let val = asm.stack_opnd(0);
        asm.ccall(rb_ary_store as *const u8, vec![recv, key, val]);

        // rb_ary_store returns void
        // stored value should still be on stack
        let val = asm.load(asm.stack_opnd(0));

        // Push the return value onto the stack
        asm.stack_pop(3);
        let stack_ret = asm.stack_push(Type::Unknown);
        asm.mov(stack_ret, val);

        jump_to_next_insn(jit, asm, ocb);
        return Some(EndBlock);
    } else if comptime_recv.class_of() == unsafe { rb_cHash } {
        // Guard receiver is a Hash
        jit_guard_known_klass(
            jit,
            asm,
            ocb,
            unsafe { rb_cHash },
            recv,
            recv.into(),
            comptime_recv,
            SEND_MAX_DEPTH,
            Counter::opt_aset_not_hash,
        );

        // We might allocate or raise
        jit_prepare_routine_call(jit, asm);

        // Call rb_hash_aset
        let recv = asm.stack_opnd(2);
        let key = asm.stack_opnd(1);
        let val = asm.stack_opnd(0);
        let ret = asm.ccall(rb_hash_aset as *const u8, vec![recv, key, val]);

        // Push the return value onto the stack
        asm.stack_pop(3);
        let stack_ret = asm.stack_push(Type::Unknown);
        asm.mov(stack_ret, ret);

        jump_to_next_insn(jit, asm, ocb);
        Some(EndBlock)
    } else {
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_aref_with(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus>{
    jit_prepare_routine_call(jit, asm);

    let key_opnd = Opnd::Value(jit.get_arg(0));
    let recv_opnd = asm.stack_opnd(0);

    extern "C" {
        fn rb_vm_opt_aref_with(recv: VALUE, key: VALUE) -> VALUE;
    }

    let val_opnd = asm.ccall(
        rb_vm_opt_aref_with as *const u8,
        vec![
            recv_opnd,
            key_opnd
        ],
    );
    asm.stack_pop(1); // Keep it on stack during GC

    asm.cmp(val_opnd, Qundef.into());
    asm.je(Target::side_exit(Counter::opt_aref_with_qundef));

    let top = asm.stack_push(Type::Unknown);
    asm.mov(top, val_opnd);

    return Some(KeepCompiling);
}

fn gen_opt_and(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let two_fixnums = match asm.ctx.two_fixnums_on_stack(jit) {
        Some(two_fixnums) => two_fixnums,
        None => {
            // Defer compilation so we can specialize on a runtime `self`
            defer_compilation(jit, asm, ocb);
            return Some(EndBlock);
        }
    };

    if two_fixnums {
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_AND) {
            return None;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(jit, asm, ocb);

        // Get the operands and destination from the stack
        let arg1 = asm.stack_pop(1);
        let arg0 = asm.stack_pop(1);

        // Do the bitwise and arg0 & arg1
        let val = asm.and(arg0, arg1);

        // Push the output on the stack
        let dst = asm.stack_push(Type::Fixnum);
        asm.store(dst, val);

        Some(KeepCompiling)
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_or(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let two_fixnums = match asm.ctx.two_fixnums_on_stack(jit) {
        Some(two_fixnums) => two_fixnums,
        None => {
            // Defer compilation so we can specialize on a runtime `self`
            defer_compilation(jit, asm, ocb);
            return Some(EndBlock);
        }
    };

    if two_fixnums {
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_OR) {
            return None;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(jit, asm, ocb);

        // Get the operands and destination from the stack
        let arg1 = asm.stack_pop(1);
        let arg0 = asm.stack_pop(1);

        // Do the bitwise or arg0 | arg1
        let val = asm.or(arg0, arg1);

        // Push the output on the stack
        let dst = asm.stack_push(Type::Fixnum);
        asm.store(dst, val);

        Some(KeepCompiling)
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_minus(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let two_fixnums = match asm.ctx.two_fixnums_on_stack(jit) {
        Some(two_fixnums) => two_fixnums,
        None => {
            // Defer compilation so we can specialize on a runtime `self`
            defer_compilation(jit, asm, ocb);
            return Some(EndBlock);
        }
    };

    if two_fixnums {
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_MINUS) {
            return None;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(jit, asm, ocb);

        // Get the operands and destination from the stack
        let arg1 = asm.stack_pop(1);
        let arg0 = asm.stack_pop(1);

        // Subtract arg0 - arg1 and test for overflow
        let val_untag = asm.sub(arg0, arg1);
        asm.jo(Target::side_exit(Counter::opt_minus_overflow));
        let val = asm.add(val_untag, Opnd::Imm(1));

        // Push the output on the stack
        let dst = asm.stack_push(Type::Fixnum);
        asm.store(dst, val);

        Some(KeepCompiling)
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_mult(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let two_fixnums = match asm.ctx.two_fixnums_on_stack(jit) {
        Some(two_fixnums) => two_fixnums,
        None => {
            defer_compilation(jit, asm, ocb);
            return Some(EndBlock);
        }
    };

    // Fallback to a method call if it overflows
    if two_fixnums && asm.ctx.get_chain_depth() == 0 {
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_MULT) {
            return None;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(jit, asm, ocb);

        // Get the operands from the stack
        let arg1 = asm.stack_pop(1);
        let arg0 = asm.stack_pop(1);

        // Do some bitwise gymnastics to handle tag bits
        // x * y is translated to (x >> 1) * (y - 1) + 1
        let arg0_untag = asm.rshift(arg0, Opnd::UImm(1));
        let arg1_untag = asm.sub(arg1, Opnd::UImm(1));
        let out_val = asm.mul(arg0_untag, arg1_untag);
        jit_chain_guard(JCC_JO_MUL, jit, asm, ocb, 1, Counter::opt_mult_overflow);
        let out_val = asm.add(out_val, Opnd::UImm(1));

        // Push the output on the stack
        let dst = asm.stack_push(Type::Fixnum);
        asm.mov(dst, out_val);

        Some(KeepCompiling)
    } else {
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_div(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, asm, ocb)
}

fn gen_opt_mod(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let two_fixnums = match asm.ctx.two_fixnums_on_stack(jit) {
        Some(two_fixnums) => two_fixnums,
        None => {
            // Defer compilation so we can specialize on a runtime `self`
            defer_compilation(jit, asm, ocb);
            return Some(EndBlock);
        }
    };

    if two_fixnums {
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_MOD) {
            return None;
        }

        // Check that both operands are fixnums
        guard_two_fixnums(jit, asm, ocb);

        // Get the operands and destination from the stack
        let arg1 = asm.stack_pop(1);
        let arg0 = asm.stack_pop(1);

        // Check for arg0 % 0
        asm.cmp(arg1, Opnd::Imm(VALUE::fixnum_from_usize(0).as_i64()));
        asm.je(Target::side_exit(Counter::opt_mod_zero));

        // Call rb_fix_mod_fix(VALUE recv, VALUE obj)
        let ret = asm.ccall(rb_fix_mod_fix as *const u8, vec![arg0, arg1]);

        // Push the return value onto the stack
        // When the two arguments are fixnums, the modulo output is always a fixnum
        let stack_ret = asm.stack_push(Type::Fixnum);
        asm.mov(stack_ret, ret);

        Some(KeepCompiling)
    } else {
        // Delegate to send, call the method on the recv
        gen_opt_send_without_block(jit, asm, ocb)
    }
}

fn gen_opt_ltlt(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, asm, ocb)
}

fn gen_opt_nil_p(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, asm, ocb)
}

fn gen_opt_empty_p(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, asm, ocb)
}

fn gen_opt_succ(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Delegate to send, call the method on the recv
    gen_opt_send_without_block(jit, asm, ocb)
}

fn gen_opt_str_freeze(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    if !assume_bop_not_redefined(jit, asm, ocb, STRING_REDEFINED_OP_FLAG, BOP_FREEZE) {
        return None;
    }

    let str = jit.get_arg(0);

    // Push the return value onto the stack
    let stack_ret = asm.stack_push(Type::CString);
    asm.mov(stack_ret, str.into());

    Some(KeepCompiling)
}

fn gen_opt_str_uminus(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    if !assume_bop_not_redefined(jit, asm, ocb, STRING_REDEFINED_OP_FLAG, BOP_UMINUS) {
        return None;
    }

    let str = jit.get_arg(0);

    // Push the return value onto the stack
    let stack_ret = asm.stack_push(Type::CString);
    asm.mov(stack_ret, str.into());

    Some(KeepCompiling)
}

fn gen_opt_newarray_max(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let num = jit.get_arg(0).as_u32();

    // Save the PC and SP because we may allocate
    jit_prepare_routine_call(jit, asm);

    extern "C" {
        fn rb_vm_opt_newarray_max(ec: EcPtr, num: u32, elts: *const VALUE) -> VALUE;
    }

    let offset_magnitude = (SIZEOF_VALUE as u32) * num;
    let values_opnd = asm.ctx.sp_opnd(-(offset_magnitude as isize));
    let values_ptr = asm.lea(values_opnd);

    let val_opnd = asm.ccall(
        rb_vm_opt_newarray_max as *const u8,
        vec![
            EC,
            num.into(),
            values_ptr
        ],
    );

    asm.stack_pop(num.as_usize());
    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, val_opnd);

    Some(KeepCompiling)
}

fn gen_opt_newarray_send(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let method = jit.get_arg(1).as_u64();

    if method == ID!(min) {
        gen_opt_newarray_min(jit, asm, _ocb)
    } else if method == ID!(max) {
        gen_opt_newarray_max(jit, asm, _ocb)
    } else if method == ID!(hash) {
        gen_opt_newarray_hash(jit, asm, _ocb)
    } else {
        None
    }
}

fn gen_opt_newarray_hash(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {

    let num = jit.get_arg(0).as_u32();

    // Save the PC and SP because we may allocate
    jit_prepare_routine_call(jit, asm);

    extern "C" {
        fn rb_vm_opt_newarray_hash(ec: EcPtr, num: u32, elts: *const VALUE) -> VALUE;
    }

    let offset_magnitude = (SIZEOF_VALUE as u32) * num;
    let values_opnd = asm.ctx.sp_opnd(-(offset_magnitude as isize));
    let values_ptr = asm.lea(values_opnd);

    let val_opnd = asm.ccall(
        rb_vm_opt_newarray_hash as *const u8,
        vec![
            EC,
            num.into(),
            values_ptr
        ],
    );

    asm.stack_pop(num.as_usize());
    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, val_opnd);

    Some(KeepCompiling)
}

fn gen_opt_newarray_min(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {

    let num = jit.get_arg(0).as_u32();

    // Save the PC and SP because we may allocate
    jit_prepare_routine_call(jit, asm);

    extern "C" {
        fn rb_vm_opt_newarray_min(ec: EcPtr, num: u32, elts: *const VALUE) -> VALUE;
    }

    let offset_magnitude = (SIZEOF_VALUE as u32) * num;
    let values_opnd = asm.ctx.sp_opnd(-(offset_magnitude as isize));
    let values_ptr = asm.lea(values_opnd);

    let val_opnd = asm.ccall(
        rb_vm_opt_newarray_min as *const u8,
        vec![
            EC,
            num.into(),
            values_ptr
        ],
    );

    asm.stack_pop(num.as_usize());
    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, val_opnd);

    Some(KeepCompiling)
}

fn gen_opt_not(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    return gen_opt_send_without_block(jit, asm, ocb);
}

fn gen_opt_size(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    return gen_opt_send_without_block(jit, asm, ocb);
}

fn gen_opt_length(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    return gen_opt_send_without_block(jit, asm, ocb);
}

fn gen_opt_regexpmatch2(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    return gen_opt_send_without_block(jit, asm, ocb);
}

fn gen_opt_case_dispatch(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Normally this instruction would lookup the key in a hash and jump to an
    // offset based on that.
    // Instead we can take the fallback case and continue with the next
    // instruction.
    // We'd hope that our jitted code will be sufficiently fast without the
    // hash lookup, at least for small hashes, but it's worth revisiting this
    // assumption in the future.
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    let case_hash = jit.get_arg(0);
    let else_offset = jit.get_arg(1).as_u32();

    // Try to reorder case/else branches so that ones that are actually used come first.
    // Supporting only Fixnum for now so that the implementation can be an equality check.
    let key_opnd = asm.stack_opnd(0);
    let comptime_key = jit.peek_at_stack(&asm.ctx, 0);

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
        if !assume_bop_not_redefined(jit, asm, ocb, INTEGER_REDEFINED_OP_FLAG, BOP_EQQ) {
            return None;
        }

        // Check if the key is the same value
        asm.cmp(key_opnd, comptime_key.into());
        jit_chain_guard(
            JCC_JNE,
            jit,
            asm,
            ocb,
            CASE_WHEN_MAX_DEPTH,
            Counter::opt_case_dispatch_megamorphic,
        );
        asm.stack_pop(1); // Pop key_opnd

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
        let jump_idx = jit.next_insn_idx() as u32 + jump_offset;
        let jump_block = BlockId { iseq: jit.iseq, idx: jump_idx.try_into().unwrap() };
        gen_direct_jump(jit, &asm.ctx.clone(), jump_block, asm);
        Some(EndBlock)
    } else {
        asm.stack_pop(1); // Pop key_opnd
        Some(KeepCompiling) // continue with === branches
    }
}

fn gen_branchif(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let jump_offset = jit.get_arg(0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        gen_check_ints(asm, Counter::branchif_interrupted);
    }

    // Get the branch target instruction offsets
    let next_idx = jit.next_insn_idx();
    let jump_idx = (next_idx as i32) + jump_offset;
    let next_block = BlockId {
        iseq: jit.iseq,
        idx: next_idx,
    };
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx.try_into().unwrap(),
    };

    // Test if any bit (outside of the Qnil bit) is on
    // See RB_TEST()
    let val_type = asm.ctx.get_opnd_type(StackOpnd(0));
    let val_opnd = asm.stack_pop(1);

    incr_counter!(branch_insn_count);

    if let Some(result) = val_type.known_truthy() {
        let target = if result { jump_block } else { next_block };
        gen_direct_jump(jit, &asm.ctx.clone(), target, asm);
        incr_counter!(branch_known_count);
    } else {
        asm.test(val_opnd, Opnd::Imm(!Qnil.as_i64()));

        // Generate the branch instructions
        let ctx = asm.ctx;
        gen_branch(
            jit,
            asm,
            ocb,
            jump_block,
            &ctx,
            Some(next_block),
            Some(&ctx),
            BranchGenFn::BranchIf(Cell::new(BranchShape::Default)),
        );
    }

    Some(EndBlock)
}

fn gen_branchunless(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let jump_offset = jit.get_arg(0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        gen_check_ints(asm, Counter::branchunless_interrupted);
    }

    // Get the branch target instruction offsets
    let next_idx = jit.next_insn_idx() as i32;
    let jump_idx = next_idx + jump_offset;
    let next_block = BlockId {
        iseq: jit.iseq,
        idx: next_idx.try_into().unwrap(),
    };
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx.try_into().unwrap(),
    };

    let val_type = asm.ctx.get_opnd_type(StackOpnd(0));
    let val_opnd = asm.stack_pop(1);

    incr_counter!(branch_insn_count);

    if let Some(result) = val_type.known_truthy() {
        let target = if result { next_block } else { jump_block };
        gen_direct_jump(jit, &asm.ctx.clone(), target, asm);
        incr_counter!(branch_known_count);
    } else {
        // Test if any bit (outside of the Qnil bit) is on
        // See RB_TEST()
        let not_qnil = !Qnil.as_i64();
        asm.test(val_opnd, not_qnil.into());

        // Generate the branch instructions
        let ctx = asm.ctx;
        gen_branch(
            jit,
            asm,
            ocb,
            jump_block,
            &ctx,
            Some(next_block),
            Some(&ctx),
            BranchGenFn::BranchUnless(Cell::new(BranchShape::Default)),
        );
    }

    Some(EndBlock)
}

fn gen_branchnil(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let jump_offset = jit.get_arg(0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        gen_check_ints(asm, Counter::branchnil_interrupted);
    }

    // Get the branch target instruction offsets
    let next_idx = jit.next_insn_idx() as i32;
    let jump_idx = next_idx + jump_offset;
    let next_block = BlockId {
        iseq: jit.iseq,
        idx: next_idx.try_into().unwrap(),
    };
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx.try_into().unwrap(),
    };

    let val_type = asm.ctx.get_opnd_type(StackOpnd(0));
    let val_opnd = asm.stack_pop(1);

    incr_counter!(branch_insn_count);

    if let Some(result) = val_type.known_nil() {
        let target = if result { jump_block } else { next_block };
        gen_direct_jump(jit, &asm.ctx.clone(), target, asm);
        incr_counter!(branch_known_count);
    } else {
        // Test if the value is Qnil
        asm.cmp(val_opnd, Opnd::UImm(Qnil.into()));
        // Generate the branch instructions
        let ctx = asm.ctx;
        gen_branch(
            jit,
            asm,
            ocb,
            jump_block,
            &ctx,
            Some(next_block),
            Some(&ctx),
            BranchGenFn::BranchNil(Cell::new(BranchShape::Default)),
        );
    }

    Some(EndBlock)
}

fn gen_throw(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let throw_state = jit.get_arg(0).as_u64();
    let throwobj = asm.stack_pop(1);
    let throwobj = asm.load(throwobj);

    // Gather some statistics about throw
    gen_counter_incr(asm, Counter::num_throw);
    match (throw_state & VM_THROW_STATE_MASK as u64) as u32 {
        RUBY_TAG_BREAK => gen_counter_incr(asm, Counter::num_throw_break),
        RUBY_TAG_RETRY => gen_counter_incr(asm, Counter::num_throw_retry),
        RUBY_TAG_RETURN => gen_counter_incr(asm, Counter::num_throw_return),
        _ => {},
    }

    // THROW_DATA_NEW allocates. Save SP for GC and PC for allocation tracing as
    // well as handling the catch table. However, not using jit_prepare_routine_call
    // since we don't need a patch point for this implementation.
    jit_save_pc(jit, asm);
    gen_save_sp(asm);

    // rb_vm_throw verifies it's a valid throw, sets ec->tag->state, and returns throw
    // data, which is throwobj or a vm_throw_data wrapping it. When ec->tag->state is
    // set, JIT code callers will handle the throw with vm_exec_handle_exception.
    extern "C" {
        fn rb_vm_throw(ec: EcPtr, reg_cfp: CfpPtr, throw_state: u32, throwobj: VALUE) -> VALUE;
    }
    let val = asm.ccall(rb_vm_throw as *mut u8, vec![EC, CFP, throw_state.into(), throwobj]);

    asm_comment!(asm, "exit from throw");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);

    asm.frame_teardown();

    asm.cret(val);
    Some(EndBlock)
}

fn gen_jump(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let jump_offset = jit.get_arg(0).as_i32();

    // Check for interrupts, but only on backward branches that may create loops
    if jump_offset < 0 {
        gen_check_ints(asm, Counter::jump_interrupted);
    }

    // Get the branch target instruction offsets
    let jump_idx = jit.next_insn_idx() as i32 + jump_offset;
    let jump_block = BlockId {
        iseq: jit.iseq,
        idx: jump_idx.try_into().unwrap(),
    };

    // Generate the jump instruction
    gen_direct_jump(jit, &asm.ctx.clone(), jump_block, asm);

    Some(EndBlock)
}

/// Guard that self or a stack operand has the same class as `known_klass`, using
/// `sample_instance` to speculate about the shape of the runtime value.
/// FIXNUM and on-heap integers are treated as if they have distinct classes, and
/// the guard generated for one will fail for the other.
///
/// Recompile as contingency if possible, or take side exit a last resort.
fn jit_guard_known_klass(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    known_klass: VALUE,
    obj_opnd: Opnd,
    insn_opnd: YARVOpnd,
    sample_instance: VALUE,
    max_chain_depth: i32,
    counter: Counter,
) {
    let val_type = asm.ctx.get_opnd_type(insn_opnd);

    if val_type.known_class() == Some(known_klass) {
        // We already know from type information that this is a match
        return;
    }

    if unsafe { known_klass == rb_cNilClass } {
        assert!(!val_type.is_heap());
        assert!(val_type.is_unknown());

        asm_comment!(asm, "guard object is nil");
        asm.cmp(obj_opnd, Qnil.into());
        jit_chain_guard(JCC_JNE, jit, asm, ocb, max_chain_depth, counter);

        asm.ctx.upgrade_opnd_type(insn_opnd, Type::Nil);
    } else if unsafe { known_klass == rb_cTrueClass } {
        assert!(!val_type.is_heap());
        assert!(val_type.is_unknown());

        asm_comment!(asm, "guard object is true");
        asm.cmp(obj_opnd, Qtrue.into());
        jit_chain_guard(JCC_JNE, jit, asm, ocb, max_chain_depth, counter);

        asm.ctx.upgrade_opnd_type(insn_opnd, Type::True);
    } else if unsafe { known_klass == rb_cFalseClass } {
        assert!(!val_type.is_heap());
        assert!(val_type.is_unknown());

        asm_comment!(asm, "guard object is false");
        assert!(Qfalse.as_i32() == 0);
        asm.test(obj_opnd, obj_opnd);
        jit_chain_guard(JCC_JNZ, jit, asm, ocb, max_chain_depth, counter);

        asm.ctx.upgrade_opnd_type(insn_opnd, Type::False);
    } else if unsafe { known_klass == rb_cInteger } && sample_instance.fixnum_p() {
        // We will guard fixnum and bignum as though they were separate classes
        // BIGNUM can be handled by the general else case below
        assert!(val_type.is_unknown());

        asm_comment!(asm, "guard object is fixnum");
        asm.test(obj_opnd, Opnd::Imm(RUBY_FIXNUM_FLAG as i64));
        jit_chain_guard(JCC_JZ, jit, asm, ocb, max_chain_depth, counter);
        asm.ctx.upgrade_opnd_type(insn_opnd, Type::Fixnum);
    } else if unsafe { known_klass == rb_cSymbol } && sample_instance.static_sym_p() {
        assert!(!val_type.is_heap());
        // We will guard STATIC vs DYNAMIC as though they were separate classes
        // DYNAMIC symbols can be handled by the general else case below
        if val_type != Type::ImmSymbol || !val_type.is_imm() {
            assert!(val_type.is_unknown());

            asm_comment!(asm, "guard object is static symbol");
            assert!(RUBY_SPECIAL_SHIFT == 8);
            asm.cmp(obj_opnd.with_num_bits(8).unwrap(), Opnd::UImm(RUBY_SYMBOL_FLAG as u64));
            jit_chain_guard(JCC_JNE, jit, asm, ocb, max_chain_depth, counter);
            asm.ctx.upgrade_opnd_type(insn_opnd, Type::ImmSymbol);
        }
    } else if unsafe { known_klass == rb_cFloat } && sample_instance.flonum_p() {
        assert!(!val_type.is_heap());
        if val_type != Type::Flonum || !val_type.is_imm() {
            assert!(val_type.is_unknown());

            // We will guard flonum vs heap float as though they were separate classes
            asm_comment!(asm, "guard object is flonum");
            let flag_bits = asm.and(obj_opnd, Opnd::UImm(RUBY_FLONUM_MASK as u64));
            asm.cmp(flag_bits, Opnd::UImm(RUBY_FLONUM_FLAG as u64));
            jit_chain_guard(JCC_JNE, jit, asm, ocb, max_chain_depth, counter);
            asm.ctx.upgrade_opnd_type(insn_opnd, Type::Flonum);
        }
    } else if unsafe {
        FL_TEST(known_klass, VALUE(RUBY_FL_SINGLETON as usize)) != VALUE(0)
            && sample_instance == rb_class_attached_object(known_klass)
            && !rb_obj_is_kind_of(sample_instance, rb_cIO).test()
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
        // Also, guarding by identity is incorrect for IO objects because
        // IO#reopen can be used to change the class and singleton class of IO objects!
        asm_comment!(asm, "guard known object with singleton class");
        asm.cmp(obj_opnd, sample_instance.into());
        jit_chain_guard(JCC_JNE, jit, asm, ocb, max_chain_depth, counter);
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
            asm_comment!(asm, "guard not immediate");
            asm.test(obj_opnd, (RUBY_IMMEDIATE_MASK as u64).into());
            jit_chain_guard(JCC_JNZ, jit, asm, ocb, max_chain_depth, counter);
            asm.cmp(obj_opnd, Qfalse.into());
            jit_chain_guard(JCC_JE, jit, asm, ocb, max_chain_depth, counter);

            asm.ctx.upgrade_opnd_type(insn_opnd, Type::UnknownHeap);
        }

        // If obj_opnd isn't already a register, load it.
        let obj_opnd = match obj_opnd {
            Opnd::InsnOut { .. } => obj_opnd,
            _ => asm.load(obj_opnd),
        };
        let klass_opnd = Opnd::mem(64, obj_opnd, RUBY_OFFSET_RBASIC_KLASS);

        // Bail if receiver class is different from known_klass
        // TODO: jit_mov_gc_ptr keeps a strong reference, which leaks the class.
        asm_comment!(asm, "guard known class");
        asm.cmp(klass_opnd, known_klass.into());
        jit_chain_guard(JCC_JNE, jit, asm, ocb, max_chain_depth, counter);

        if known_klass == unsafe { rb_cString } {
            // Upgrading to Type::CString here is incorrect.
            // The guard we put only checks RBASIC_CLASS(obj),
            // which adding a singleton class can change. We
            // additionally need to know the string is frozen
            // to claim Type::CString.
            asm.ctx.upgrade_opnd_type(insn_opnd, Type::TString);
        } else if known_klass == unsafe { rb_cArray } {
            asm.ctx.upgrade_opnd_type(insn_opnd, Type::TArray);
        }
    }
}

// Generate ancestry guard for protected callee.
// Calls to protected callees only go through when self.is_a?(klass_that_defines_the_callee).
fn jit_protected_callee_ancestry_guard(
    asm: &mut Assembler,
    cme: *const rb_callable_method_entry_t,
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
    asm.jz(Target::side_exit(Counter::guard_send_se_protected_check_failed))
}

// Codegen for rb_obj_not().
// Note, caller is responsible for generating all the right guards, including
// arity guards.
fn jit_rb_obj_not(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    let recv_opnd = asm.ctx.get_opnd_type(StackOpnd(0));

    match recv_opnd.known_truthy() {
        Some(false) => {
            asm_comment!(asm, "rb_obj_not(nil_or_false)");
            asm.stack_pop(1);
            let out_opnd = asm.stack_push(Type::True);
            asm.mov(out_opnd, Qtrue.into());
        },
        Some(true) => {
            // Note: recv_opnd != Type::Nil && recv_opnd != Type::False.
            asm_comment!(asm, "rb_obj_not(truthy)");
            asm.stack_pop(1);
            let out_opnd = asm.stack_push(Type::False);
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
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm_comment!(asm, "nil? == true");
    asm.stack_pop(1);
    let stack_ret = asm.stack_push(Type::True);
    asm.mov(stack_ret, Qtrue.into());
    true
}

// Codegen for rb_false()
fn jit_rb_false(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm_comment!(asm, "nil? == false");
    asm.stack_pop(1);
    let stack_ret = asm.stack_push(Type::False);
    asm.mov(stack_ret, Qfalse.into());
    true
}

/// Codegen for Kernel#is_a?
fn jit_rb_kernel_is_a(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    argc: i32,
    known_recv_class: *const VALUE,
) -> bool {
    if argc != 1 {
        return false;
    }

    // If this is a super call we might not know the class
    if known_recv_class.is_null() {
        return false;
    }

    // Important note: The output code will simply `return true/false`.
    // Correctness follows from:
    //  - `known_recv_class` implies there is a guard scheduled before here
    //    for a particular `CLASS_OF(lhs)`.
    //  - We guard that rhs is identical to the compile-time sample
    //  - In general, for any two Class instances A, B, `A < B` does not change at runtime.
    //    Class#superclass is stable.

    let sample_rhs = jit.peek_at_stack(&asm.ctx, 0);
    let sample_lhs = jit.peek_at_stack(&asm.ctx, 1);

    // We are not allowing module here because the module hierarchy can change at runtime.
    if !unsafe { RB_TYPE_P(sample_rhs, RUBY_T_CLASS) } {
        return false;
    }
    let sample_is_a = unsafe { rb_obj_is_kind_of(sample_lhs, sample_rhs) == Qtrue };

    asm_comment!(asm, "Kernel#is_a?");
    asm.cmp(asm.stack_opnd(0), sample_rhs.into());
    asm.jne(Target::side_exit(Counter::guard_send_is_a_class_mismatch));

    asm.stack_pop(2);

    if sample_is_a {
        let stack_ret = asm.stack_push(Type::True);
        asm.mov(stack_ret, Qtrue.into());
    } else {
        let stack_ret = asm.stack_push(Type::False);
        asm.mov(stack_ret, Qfalse.into());
    }
    return true;
}

/// Codegen for Kernel#instance_of?
fn jit_rb_kernel_instance_of(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    argc: i32,
    known_recv_class: *const VALUE,
) -> bool {
    if argc != 1 {
        return false;
    }

    // If this is a super call we might not know the class
    if known_recv_class.is_null() {
        return false;
    }

    // Important note: The output code will simply `return true/false`.
    // Correctness follows from:
    //  - `known_recv_class` implies there is a guard scheduled before here
    //    for a particular `CLASS_OF(lhs)`.
    //  - We guard that rhs is identical to the compile-time sample
    //  - For a particular `CLASS_OF(lhs)`, `rb_obj_class(lhs)` does not change.
    //    (because for any singleton class `s`, `s.superclass.equal?(s.attached_object.class)`)

    let sample_rhs = jit.peek_at_stack(&asm.ctx, 0);
    let sample_lhs = jit.peek_at_stack(&asm.ctx, 1);

    // Filters out cases where the C implementation raises
    if unsafe { !(RB_TYPE_P(sample_rhs, RUBY_T_CLASS) || RB_TYPE_P(sample_rhs, RUBY_T_MODULE)) } {
        return false;
    }

    // We need to grab the class here to deal with singleton classes.
    // Instance of grabs the "real class" of the object rather than the
    // singleton class.
    let sample_lhs_real_class = unsafe { rb_obj_class(sample_lhs) };

    let sample_instance_of = sample_lhs_real_class == sample_rhs;

    asm_comment!(asm, "Kernel#instance_of?");
    asm.cmp(asm.stack_opnd(0), sample_rhs.into());
    jit_chain_guard(
        JCC_JNE,
        jit,
        asm,
        ocb,
        SEND_MAX_DEPTH,
        Counter::guard_send_instance_of_class_mismatch,
    );

    asm.stack_pop(2);

    if sample_instance_of {
        let stack_ret = asm.stack_push(Type::True);
        asm.mov(stack_ret, Qtrue.into());
    } else {
        let stack_ret = asm.stack_push(Type::False);
        asm.mov(stack_ret, Qfalse.into());
    }
    return true;
}

fn jit_rb_mod_eqq(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    if argc != 1 {
        return false;
    }

    asm_comment!(asm, "Module#===");
    // By being here, we know that the receiver is a T_MODULE or a T_CLASS, because Module#=== can
    // only live on these objects. With that, we can call rb_obj_is_kind_of() without
    // jit_prepare_routine_call() or a control frame push because it can't raise, allocate, or call
    // Ruby methods with these inputs.
    // Note the difference in approach from Kernel#is_a? because we don't get a free guard for the
    // right hand side.
    let rhs = asm.stack_pop(1);
    let lhs = asm.stack_pop(1); // the module
    let ret = asm.ccall(rb_obj_is_kind_of as *const u8, vec![rhs, lhs]);

    // Return the result
    let stack_ret = asm.stack_push(Type::UnknownImm);
    asm.mov(stack_ret, ret);

    return true;
}

// Codegen for rb_obj_equal()
// object identity comparison
fn jit_rb_obj_equal(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm_comment!(asm, "equal?");
    let obj1 = asm.stack_pop(1);
    let obj2 = asm.stack_pop(1);

    asm.cmp(obj1, obj2);
    let ret_opnd = asm.csel_e(Qtrue.into(), Qfalse.into());

    let stack_ret = asm.stack_push(Type::UnknownImm);
    asm.mov(stack_ret, ret_opnd);
    true
}

// Codegen for rb_obj_not_equal()
// object identity comparison
fn jit_rb_obj_not_equal(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    gen_equality_specialized(jit, asm, ocb, false) == Some(true)
}

// Codegen for rb_int_equal()
fn jit_rb_int_equal(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    // Check that both operands are fixnums
    guard_two_fixnums(jit, asm, ocb);

    // Compare the arguments
    asm_comment!(asm, "rb_int_equal");
    let arg1 = asm.stack_pop(1);
    let arg0 = asm.stack_pop(1);
    asm.cmp(arg0, arg1);
    let ret_opnd = asm.csel_e(Qtrue.into(), Qfalse.into());

    let stack_ret = asm.stack_push(Type::UnknownImm);
    asm.mov(stack_ret, ret_opnd);
    true
}

fn jit_rb_int_div(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    if asm.ctx.two_fixnums_on_stack(jit) != Some(true) {
        return false;
    }
    guard_two_fixnums(jit, asm, ocb);

    // rb_fix_div_fix may GC-allocate for Bignum
    jit_prepare_routine_call(jit, asm);

    asm_comment!(asm, "Integer#/");
    let obj = asm.stack_opnd(0);
    let recv = asm.stack_opnd(1);

    // Check for arg0 % 0
    asm.cmp(obj, VALUE::fixnum_from_usize(0).as_i64().into());
    asm.je(Target::side_exit(Counter::opt_div_zero));

    let ret = asm.ccall(rb_fix_div_fix as *const u8, vec![recv, obj]);
    asm.stack_pop(2); // Keep them during ccall for GC

    let ret_opnd = asm.stack_push(Type::Unknown);
    asm.mov(ret_opnd, ret);
    true
}

fn jit_rb_int_lshift(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    if asm.ctx.two_fixnums_on_stack(jit) != Some(true) {
        return false;
    }
    guard_two_fixnums(jit, asm, ocb);

    let comptime_shift = jit.peek_at_stack(&asm.ctx, 0);

    if !comptime_shift.fixnum_p() {
        return false;
    }

    // Untag the fixnum shift amount
    let shift_amt = comptime_shift.as_isize() >> 1;

    if shift_amt > 63 || shift_amt < 0 {
        return false;
    }

    let rhs = asm.stack_pop(1);
    let lhs = asm.stack_pop(1);

    // Guard on the shift value we speculated on
    asm.cmp(rhs, comptime_shift.into());
    asm.jne(Target::side_exit(Counter::lshift_amt_changed));

    let in_val = asm.sub(lhs, 1.into());
    let shift_opnd = Opnd::UImm(shift_amt as u64);
    let out_val = asm.lshift(in_val, shift_opnd);
    let unshifted = asm.rshift(out_val, shift_opnd);

    // Guard that we did not overflow
    asm.cmp(unshifted, in_val);
    asm.jne(Target::side_exit(Counter::lshift_overflow));

    // Re-tag the output value
    let out_val = asm.add(out_val, 1.into());

    let ret_opnd = asm.stack_push(Type::Fixnum);
    asm.mov(ret_opnd, out_val);
    true
}

fn jit_rb_int_aref(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    if argc != 1 {
        return false;
    }
    if asm.ctx.two_fixnums_on_stack(jit) != Some(true) {
        return false;
    }
    guard_two_fixnums(jit, asm, ocb);

    asm_comment!(asm, "Integer#[]");
    let obj = asm.stack_pop(1);
    let recv = asm.stack_pop(1);

    let ret = asm.ccall(rb_fix_aref as *const u8, vec![recv, obj]);

    let ret_opnd = asm.stack_push(Type::Fixnum);
    asm.mov(ret_opnd, ret);
    true
}

/// If string is frozen, duplicate it to get a non-frozen string. Otherwise, return it.
fn jit_rb_str_uplus(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    argc: i32,
    _known_recv_class: *const VALUE,
) -> bool
{
    if argc != 0 {
        return false;
    }

    // We allocate when we dup the string
    jit_prepare_routine_call(jit, asm);
    asm.spill_temps(); // For ccall. Unconditionally spill them for RegTemps consistency.

    asm_comment!(asm, "Unary plus on string");
    let recv_opnd = asm.stack_pop(1);
    let recv_opnd = asm.load(recv_opnd);
    let flags_opnd = asm.load(Opnd::mem(64, recv_opnd, RUBY_OFFSET_RBASIC_FLAGS));
    asm.test(flags_opnd, Opnd::Imm(RUBY_FL_FREEZE as i64));

    let ret_label = asm.new_label("stack_ret");

    // String#+@ can only exist on T_STRING
    let stack_ret = asm.stack_push(Type::TString);

    // If the string isn't frozen, we just return it.
    asm.mov(stack_ret, recv_opnd);
    asm.jz(ret_label);

    // Str is frozen - duplicate it
    asm.spill_temps(); // for ccall
    let ret_opnd = asm.ccall(rb_str_dup as *const u8, vec![recv_opnd]);
    asm.mov(stack_ret, ret_opnd);

    asm.write_label(ret_label);

    true
}

fn jit_rb_str_bytesize(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm_comment!(asm, "String#bytesize");

    let recv = asm.stack_pop(1);

    asm_comment!(asm, "get string length");
    let str_len_opnd = Opnd::mem(
        std::os::raw::c_long::BITS as u8,
        asm.load(recv),
        RUBY_OFFSET_RSTRING_LEN as i32,
    );

    let len = asm.load(str_len_opnd);
    let shifted_val = asm.lshift(len, Opnd::UImm(1));
    let out_val = asm.or(shifted_val, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));

    let out_opnd = asm.stack_push(Type::Fixnum);

    asm.mov(out_opnd, out_val);

    true
}

fn jit_rb_str_getbyte(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm_comment!(asm, "String#getbyte");
    extern "C" {
        fn rb_str_getbyte(str: VALUE, index: VALUE) -> VALUE;
    }
    // Raises when non-integers are passed in
    jit_prepare_routine_call(jit, asm);

    let index = asm.stack_opnd(0);
    let recv = asm.stack_opnd(1);
    let ret_opnd = asm.ccall(rb_str_getbyte as *const u8, vec![recv, index]);
    asm.stack_pop(2); // Keep them on stack during ccall for GC

    // Can either return a FIXNUM or nil
    let out_opnd = asm.stack_push(Type::UnknownImm);
    asm.mov(out_opnd, ret_opnd);

    true
}

// Codegen for rb_str_to_s()
// When String#to_s is called on a String instance, the method returns self and
// most of the overhead comes from setting up the method call. We observed that
// this situation happens a lot in some workloads.
fn jit_rb_str_to_s(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    known_recv_class: *const VALUE,
) -> bool {
    if !known_recv_class.is_null() && unsafe { *known_recv_class == rb_cString } {
        asm_comment!(asm, "to_s on plain string");
        // The method returns the receiver, which is already on the stack.
        // No stack movement.
        return true;
    }
    false
}

// Codegen for rb_str_empty_p()
fn jit_rb_str_empty_p(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    let recv_opnd = asm.stack_pop(1);

    asm_comment!(asm, "get string length");
    let str_len_opnd = Opnd::mem(
        std::os::raw::c_long::BITS as u8,
        asm.load(recv_opnd),
        RUBY_OFFSET_RSTRING_LEN as i32,
    );

    asm.cmp(str_len_opnd, Opnd::UImm(0));
    let string_empty = asm.csel_e(Qtrue.into(), Qfalse.into());
    let out_opnd = asm.stack_push(Type::UnknownImm);
    asm.mov(out_opnd, string_empty);

    return true;
}

// Codegen for rb_str_concat() -- *not* String#concat
// Frequently strings are concatenated using "out_str << next_str".
// This is common in Erb and similar templating languages.
fn jit_rb_str_concat(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    // The << operator can accept integer codepoints for characters
    // as the argument. We only specially optimise string arguments.
    // If the peeked-at compile time argument is something other than
    // a string, assume it won't be a string later either.
    let comptime_arg = jit.peek_at_stack(&asm.ctx, 0);
    if ! unsafe { RB_TYPE_P(comptime_arg, RUBY_T_STRING) } {
        return false;
    }

    // Guard that the concat argument is a string
    guard_object_is_string(asm, asm.stack_opnd(0), StackOpnd(0), Counter::guard_send_not_string);

    // Guard buffers from GC since rb_str_buf_append may allocate. During the VM lock on GC,
    // other Ractors may trigger global invalidation, so we need ctx.clear_local_types().
    // PC is used on errors like Encoding::CompatibilityError raised by rb_str_buf_append.
    jit_prepare_routine_call(jit, asm);
    asm.spill_temps(); // For ccall. Unconditionally spill them for RegTemps consistency.

    let concat_arg = asm.stack_pop(1);
    let recv = asm.stack_pop(1);

    // Test if string encodings differ. If different, use rb_str_append. If the same,
    // use rb_yjit_str_simple_append, which calls rb_str_cat.
    asm_comment!(asm, "<< on strings");

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

    let enc_mismatch = asm.new_label("enc_mismatch");
    asm.jnz(enc_mismatch);

    // If encodings match, call the simple append function and jump to return
    let ret_opnd = asm.ccall(rb_yjit_str_simple_append as *const u8, vec![recv, concat_arg]);
    let ret_label = asm.new_label("func_return");
    let stack_ret = asm.stack_push(Type::TString);
    asm.mov(stack_ret, ret_opnd);
    asm.stack_pop(1); // forget stack_ret to re-push after ccall
    asm.jmp(ret_label);

    // If encodings are different, use a slower encoding-aware concatenate
    asm.write_label(enc_mismatch);
    asm.spill_temps(); // Ignore the register for the other local branch
    let ret_opnd = asm.ccall(rb_str_buf_append as *const u8, vec![recv, concat_arg]);
    let stack_ret = asm.stack_push(Type::TString);
    asm.mov(stack_ret, ret_opnd);
    // Drop through to return

    asm.write_label(ret_label);

    true
}

// Codegen for rb_ary_empty_p()
fn jit_rb_ary_empty_p(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    let array_opnd = asm.stack_pop(1);
    let array_reg = asm.load(array_opnd);
    let len_opnd = get_array_len(asm, array_reg);

    asm.test(len_opnd, len_opnd);
    let bool_val = asm.csel_z(Qtrue.into(), Qfalse.into());

    let out_opnd = asm.stack_push(Type::UnknownImm);
    asm.store(out_opnd, bool_val);

    return true;
}

// Codegen for rb_ary_length()
fn jit_rb_ary_length(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    let array_opnd = asm.stack_pop(1);
    let array_reg = asm.load(array_opnd);
    let len_opnd = get_array_len(asm, array_reg);

    // Convert the length to a fixnum
    let shifted_val = asm.lshift(len_opnd, Opnd::UImm(1));
    let out_val = asm.or(shifted_val, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));

    let out_opnd = asm.stack_push(Type::Fixnum);
    asm.store(out_opnd, out_val);

    return true;
}

fn jit_rb_ary_push(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm_comment!(asm, "Array#<<");

    // rb_ary_push allocates memory for buffer extension
    jit_prepare_routine_call(jit, asm);

    let item_opnd = asm.stack_opnd(0);
    let ary_opnd = asm.stack_opnd(1);
    let ret = asm.ccall(rb_ary_push as *const u8, vec![ary_opnd, item_opnd]);
    asm.stack_pop(2); // Keep them on stack during ccall for GC

    let ret_opnd = asm.stack_push(Type::TArray);
    asm.mov(ret_opnd, ret);
    true
}

fn jit_obj_respond_to(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
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
    let mid_sym = jit.peek_at_stack(&asm.ctx, (argc - 1) as isize);
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
        asm.ctx.get_opnd_type(StackOpnd(0)).known_truthy()
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
        (METHOD_VISI_UNDEF, _) => {
            // No method, we can return false given respond_to_missing? hasn't been overridden.
            // In the future, we might want to jit the call to respond_to_missing?
            if !assume_method_basic_definition(jit, asm, ocb, recv_class, ID!(respond_to_missing)) {
                return false;
            }
            Qfalse
        }
        (METHOD_VISI_PUBLIC, _) | // Public method => fine regardless of include_all
        (_, Some(true)) => { // include_all => all visibility are acceptable
            // Method exists and has acceptable visibility
            if cme_def_type == VM_METHOD_TYPE_NOTIMPLEMENTED {
                // C method with rb_f_notimplement(). `respond_to?` returns false
                // without consulting `respond_to_missing?`. See also: rb_add_method_cfunc()
                Qfalse
            } else {
                Qtrue
            }
        }
        (_, _) => return false // not public and include_all not known, can't compile
    };

    // Invalidate this block if method lookup changes for the method being queried. This works
    // both for the case where a method does or does not exist, as for the latter we asked for a
    // "negative CME" earlier.
    jit.assume_method_lookup_stable(asm, ocb, target_cme);

    if argc == 2 {
        // pop include_all argument (we only use its type info)
        asm.stack_pop(1);
    }

    let sym_opnd = asm.stack_pop(1);
    let _recv_opnd = asm.stack_pop(1);

    // This is necessary because we have no guarantee that sym_opnd is a constant
    asm_comment!(asm, "guard known mid");
    asm.cmp(sym_opnd, mid_sym.into());
    jit_chain_guard(
        JCC_JNE,
        jit,
        asm,
        ocb,
        SEND_MAX_DEPTH,
        Counter::guard_send_respond_to_mid_mismatch,
    );

    jit_putobject(asm, result);

    true
}

fn jit_rb_f_block_given_p(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm_comment!(asm, "block_given?");

    // Same as rb_vm_frame_block_handler
    let ep_opnd = gen_get_lep(jit, asm);
    let block_handler = asm.load(
        Opnd::mem(64, ep_opnd, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL)
    );

    asm.stack_pop(1);
    let out_opnd = asm.stack_push(Type::UnknownImm);

    // Return `block_handler != VM_BLOCK_HANDLER_NONE`
    asm.cmp(block_handler, VM_BLOCK_HANDLER_NONE.into());
    let block_given = asm.csel_ne(Qtrue.into(), Qfalse.into());
    asm.mov(out_opnd, block_given);

    true
}

fn jit_thread_s_current(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
    _ci: *const rb_callinfo,
    _cme: *const rb_callable_method_entry_t,
    _block: Option<BlockHandler>,
    _argc: i32,
    _known_recv_class: *const VALUE,
) -> bool {
    asm_comment!(asm, "Thread.current");
    asm.stack_pop(1);

    // ec->thread_ptr
    let ec_thread_opnd = asm.load(Opnd::mem(64, EC, RUBY_OFFSET_EC_THREAD_PTR));

    // thread->self
    let thread_self = Opnd::mem(64, ec_thread_opnd, RUBY_OFFSET_THREAD_SELF);

    let stack_ret = asm.stack_push(Type::UnknownHeap);
    asm.mov(stack_ret, thread_self);
    true
}

// Check if we know how to codegen for a particular cfunc method
fn lookup_cfunc_codegen(def: *const rb_method_definition_t) -> Option<MethodGenFn> {
    let method_serial = unsafe { get_def_method_serial(def) };
    let table = unsafe { METHOD_CODEGEN_TABLE.as_ref().unwrap() };

    let option_ref = table.get(&method_serial);
    match option_ref {
        None => None,
        Some(&mgf) => Some(mgf), // Deref
    }
}

// Is anyone listening for :c_call and :c_return event currently?
fn c_method_tracing_currently_enabled(jit: &JITState) -> bool {
    // Defer to C implementation in yjit.c
    unsafe {
        rb_c_method_tracing_currently_enabled(jit.ec)
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
    BlockHandler(Option<BlockHandler>),
    PrevEP(*const VALUE),
    PrevEPOpnd(Opnd),
}

// Each variant represents a branch in vm_caller_setup_arg_block.
#[derive(Clone, Copy)]
pub enum BlockHandler {
    // send, invokesuper: blockiseq operand
    BlockISeq(IseqPtr),
    // invokesuper: GET_BLOCK_HANDLER() (GET_LEP()[VM_ENV_DATA_INDEX_SPECVAL])
    LEPSpecVal,
    // part of the allocate-free block forwarding scheme
    BlockParamProxy,
    // To avoid holding the block arg (e.g. proc and symbol) across C calls,
    // we might need to set the block handler early in the call sequence
    AlreadySet,
}

struct ControlFrame {
    recv: Opnd,
    sp: Opnd,
    iseq: Option<IseqPtr>,
    pc: Option<u64>,
    frame_type: u32,
    specval: SpecVal,
    cme: *const rb_callable_method_entry_t,
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
//   * SP register is updated only if frame.iseq is set
//   * Stack overflow is not checked (should be done by the caller)
//   * Interrupts are not checked (should be done by the caller)
fn gen_push_frame(
    jit: &mut JITState,
    asm: &mut Assembler,
    frame: ControlFrame,
) {
    let sp = frame.sp;

    asm_comment!(asm, "push cme, specval, frame type");

    // Write method entry at sp[-3]
    // sp[-3] = me;
    // Use compile time cme. It's assumed to be valid because we are notified when
    // any cme we depend on become outdated. See yjit_method_lookup_change().
    asm.store(Opnd::mem(64, sp, SIZEOF_VALUE_I32 * -3), VALUE::from(frame.cme).into());

    // Write special value at sp[-2]. It's either a block handler or a pointer to
    // the outer environment depending on the frame type.
    // sp[-2] = specval;
    let specval: Opnd = match frame.specval {
        SpecVal::BlockHandler(None) => VM_BLOCK_HANDLER_NONE.into(),
        SpecVal::BlockHandler(Some(block_handler)) => {
            match block_handler {
                BlockHandler::BlockISeq(block_iseq) => {
                    // Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
                    // VM_CFP_TO_CAPTURED_BLOCK does &cfp->self, rb_captured_block->code.iseq aliases
                    // with cfp->block_code.
                    asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_BLOCK_CODE), VALUE::from(block_iseq).into());

                    let cfp_self = asm.lea(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF));
                    asm.or(cfp_self, Opnd::Imm(1))
                }
                BlockHandler::LEPSpecVal => {
                    let lep_opnd = gen_get_lep(jit, asm);
                    asm.load(Opnd::mem(64, lep_opnd, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL))
                }
                BlockHandler::BlockParamProxy => {
                    let ep_opnd = gen_get_lep(jit, asm);
                    let block_handler = asm.load(
                        Opnd::mem(64, ep_opnd, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL)
                    );
                    block_handler
                }
                BlockHandler::AlreadySet => 0.into(), // unused
            }
        }
        SpecVal::PrevEP(prev_ep) => {
            let tagged_prev_ep = (prev_ep as usize) | 1;
            VALUE(tagged_prev_ep).into()
        }
        SpecVal::PrevEPOpnd(ep_opnd) => {
            asm.or(ep_opnd, 1.into())
        }
    };
    if let SpecVal::BlockHandler(Some(BlockHandler::AlreadySet)) = frame.specval {
        asm_comment!(asm, "specval should have been set");
    } else {
        asm.store(Opnd::mem(64, sp, SIZEOF_VALUE_I32 * -2), specval);
    }

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
    // };
    asm_comment!(asm, "push callee control frame");

    // For an iseq call PC may be None, in which case we will not set PC and will allow jitted code
    // to set it as necessary.
    if let Some(pc) = frame.pc {
        asm.mov(cfp_opnd(RUBY_OFFSET_CFP_PC), pc.into());
    };
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SP), sp);
    let iseq: Opnd = if let Some(iseq) = frame.iseq {
        VALUE::from(iseq).into()
    } else {
        0.into()
    };
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_ISEQ), iseq);
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SELF), frame.recv);
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_BLOCK_CODE), 0.into());

    if frame.iseq.is_some() {
        // Spill stack temps to let the callee use them (must be done before changing the SP register)
        asm.spill_temps();

        // Saving SP before calculating ep avoids a dependency on a register
        // However this must be done after referencing frame.recv, which may be SP-relative
        asm.mov(SP, sp);
    }
    let ep = asm.sub(sp, SIZEOF_VALUE.into());
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_EP), ep);
}

fn gen_send_cfunc(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    block: Option<BlockHandler>,
    recv_known_klass: *const VALUE,
    flags: u32,
    argc: i32,
) -> Option<CodegenStatus> {
    let cfunc = unsafe { get_cme_def_body_cfunc(cme) };
    let cfunc_argc = unsafe { get_mct_argc(cfunc) };
    let mut argc = argc;

    // If the function expects a Ruby array of arguments
    if cfunc_argc < 0 && cfunc_argc != -1 {
        gen_counter_incr(asm, Counter::send_cfunc_ruby_array_varg);
        return None;
    }

    // We aren't handling a vararg cfuncs with splat currently.
    if flags & VM_CALL_ARGS_SPLAT != 0 && cfunc_argc == -1 {
        gen_counter_incr(asm, Counter::send_args_splat_cfunc_var_args);
        return None;
    }

    if flags & VM_CALL_ARGS_SPLAT != 0 && flags & VM_CALL_ZSUPER != 0 {
        // zsuper methods are super calls without any arguments.
        // They are also marked as splat, but don't actually have an array
        // they pull arguments from, instead we need to change to call
        // a different method with the current stack.
        gen_counter_incr(asm, Counter::send_args_splat_cfunc_zuper);
        return None;
    }

    // In order to handle backwards compatibility between ruby 3 and 2
    // ruby2_keywords was introduced. It is called only on methods
    // with splat and changes they way they handle them.
    // We are just going to not compile these.
    // https://docs.ruby-lang.org/en/3.2/Module.html#method-i-ruby2_keywords
    if unsafe {
        get_iseq_flags_ruby2_keywords(jit.iseq) && flags & VM_CALL_ARGS_SPLAT != 0
    } {
        gen_counter_incr(asm, Counter::send_args_splat_cfunc_ruby2_keywords);
        return None;
    }

    let kw_arg = unsafe { vm_ci_kwarg(ci) };
    let kw_arg_num = if kw_arg.is_null() {
        0
    } else {
        unsafe { get_cikw_keyword_len(kw_arg) }
    };

    if kw_arg_num != 0 && flags & VM_CALL_ARGS_SPLAT != 0 {
        gen_counter_incr(asm, Counter::send_cfunc_splat_with_kw);
        return None;
    }

    if c_method_tracing_currently_enabled(jit) {
        // Don't JIT if tracing c_call or c_return
        gen_counter_incr(asm, Counter::send_cfunc_tracing);
        return None;
    }

    // Increment total cfunc send count
    gen_counter_incr(asm, Counter::num_send_cfunc);

    // Delegate to codegen for C methods if we have it.
    if kw_arg.is_null() && flags & VM_CALL_OPT_SEND == 0 && flags & VM_CALL_ARGS_SPLAT == 0 && (cfunc_argc == -1 || argc == cfunc_argc) {
        let codegen_p = lookup_cfunc_codegen(unsafe { (*cme).def });
        let expected_stack_after = asm.ctx.get_stack_size() as i32 - argc;
        if let Some(known_cfunc_codegen) = codegen_p {
            if known_cfunc_codegen(jit, asm, ocb, ci, cme, block, argc, recv_known_klass) {
                assert_eq!(expected_stack_after, asm.ctx.get_stack_size() as i32);
                gen_counter_incr(asm, Counter::num_send_cfunc_inline);
                // cfunc codegen generated code. Terminate the block so
                // there isn't multiple calls in the same block.
                jump_to_next_insn(jit, asm, ocb);
                return Some(EndBlock);
            }
        }
    }

    // Log the name of the method we're calling to,
    // note that we intentionally don't do this for inlined cfuncs
    if get_option!(gen_stats) {
        // TODO: extract code to get method name string into its own function

        // Assemble the method name string
        let mid = unsafe { vm_ci_mid(ci) };
        let class_name = if recv_known_klass != ptr::null() {
            unsafe { cstr_to_rust_string(rb_class2name(*recv_known_klass)) }.unwrap()
        } else {
            "Unknown".to_string()
        };
        let method_name = if mid != 0 {
            unsafe { cstr_to_rust_string(rb_id2name(mid)) }.unwrap()
        } else {
            "Unknown".to_string()
        };
        let name_str = format!("{}#{}", class_name, method_name);

        // Get an index for this cfunc name
        let cfunc_idx = get_cfunc_idx(&name_str);

        // Increment the counter for this cfunc
        asm.ccall(incr_cfunc_counter as *const u8, vec![cfunc_idx.into()]);
    }

    // Check for interrupts
    gen_check_ints(asm, Counter::guard_send_interrupted);

    // Stack overflow check
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    // REG_CFP <= REG_SP + 4 * SIZEOF_VALUE + sizeof(rb_control_frame_t)
    asm_comment!(asm, "stack overflow check");
    let stack_limit = asm.lea(asm.ctx.sp_opnd((SIZEOF_VALUE * 4 + 2 * RUBY_SIZEOF_CONTROL_FRAME) as isize));
    asm.cmp(CFP, stack_limit);
    asm.jbe(Target::side_exit(Counter::guard_send_se_cf_overflow));

    // Number of args which will be passed through to the callee
    // This is adjusted by the kwargs being combined into a hash.
    let mut passed_argc = if kw_arg.is_null() {
        argc
    } else {
        argc - kw_arg_num + 1
    };

    // If the argument count doesn't match
    if cfunc_argc >= 0 && cfunc_argc != passed_argc && flags & VM_CALL_ARGS_SPLAT == 0 {
        gen_counter_incr(asm, Counter::send_cfunc_argc_mismatch);
        return None;
    }

    // Don't JIT functions that need C stack arguments for now
    if cfunc_argc >= 0 && passed_argc + 1 > (C_ARG_OPNDS.len() as i32) {
        gen_counter_incr(asm, Counter::send_cfunc_toomany_args);
        return None;
    }

    let block_arg = flags & VM_CALL_ARGS_BLOCKARG != 0;
    let block_arg_type = if block_arg {
        Some(asm.ctx.get_opnd_type(StackOpnd(0)))
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
            gen_counter_incr(asm, Counter::send_block_arg);
            return None;
        }
    }

    match block_arg_type {
        Some(Type::Nil) => {
            // We have a nil block arg, so let's pop it off the args
            asm.stack_pop(1);
        }
        Some(Type::BlockParamProxy) => {
            // We don't need the actual stack value
            asm.stack_pop(1);
        }
        None => {
            // Nothing to do
        }
        _ => {
            assert!(false);
        }
    }

    // push_splat_args does stack manipulation so we can no longer side exit
    if flags & VM_CALL_ARGS_SPLAT != 0 {
        assert!(cfunc_argc >= 0);
        let required_args : u32 = (cfunc_argc as u32).saturating_sub(argc as u32 - 1);
        // + 1 because we pass self
        if required_args + 1 >= C_ARG_OPNDS.len() as u32 {
            gen_counter_incr(asm, Counter::send_cfunc_toomany_args);
            return None;
        }

        // We are going to assume that the splat fills
        // all the remaining arguments. So the number of args
        // should just equal the number of args the cfunc takes.
        // In the generated code we test if this is true
        // and if not side exit.
        argc = cfunc_argc;
        passed_argc = argc;
        push_splat_args(required_args, asm)
    }

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc);
    }

    // Points to the receiver operand on the stack
    let recv = asm.stack_opnd(argc);

    // Store incremented PC into current control frame in case callee raises.
    jit_save_pc(jit, asm);

    // Increment the stack pointer by 3 (in the callee)
    // sp += 3
    let sp = asm.lea(asm.ctx.sp_opnd((SIZEOF_VALUE as isize) * 3));

    let specval = if block_arg_type == Some(Type::BlockParamProxy) {
        SpecVal::BlockHandler(Some(BlockHandler::BlockParamProxy))
    } else {
        SpecVal::BlockHandler(block)
    };

    let mut frame_type = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;
    if !kw_arg.is_null() {
        frame_type |= VM_FRAME_FLAG_CFRAME_KW
    }

    gen_push_frame(jit, asm, ControlFrame {
        frame_type,
        specval,
        cme,
        recv,
        sp,
        pc: if cfg!(debug_assertions) {
            Some(!0) // Poison value. Helps to fail fast.
        } else {
            None     // Leave PC uninitialized as cfuncs shouldn't read it
        },
        iseq: None,
    });

    asm_comment!(asm, "set ec->cfp");
    let new_cfp = asm.lea(Opnd::mem(64, CFP, -(RUBY_SIZEOF_CONTROL_FRAME as i32)));
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), new_cfp);

    if !kw_arg.is_null() {
        // Build a hash from all kwargs passed
        asm_comment!(asm, "build_kwhash");
        let imemo_ci = VALUE(ci as usize);
        assert_ne!(0, unsafe { rb_IMEMO_TYPE_P(imemo_ci, imemo_callinfo) },
            "we assume all callinfos with kwargs are on the GC heap");
        let sp = asm.lea(asm.ctx.sp_opnd(0));
        let kwargs = asm.ccall(build_kwhash as *const u8, vec![imemo_ci.into(), sp]);

        // Replace the stack location at the start of kwargs with the new hash
        let stack_opnd = asm.stack_opnd(argc - passed_argc);
        asm.mov(stack_opnd, kwargs);
    }

    // Write interpreter SP into CFP.
    // We don't pop arguments yet to use registers for passing them, but we
    // have to set cfp->sp below them for full_cfunc_return() invalidation.
    gen_save_sp_with_offset(asm, -(argc + 1) as i8);

    // Non-variadic method
    let args = if cfunc_argc >= 0 {
        // Copy the arguments from the stack to the C argument registers
        // self is the 0th argument and is at index argc from the stack top
        (0..=passed_argc).map(|i|
            asm.stack_opnd(argc - i)
        ).collect()
    }
    // Variadic method
    else if cfunc_argc == -1 {
        // The method gets a pointer to the first argument
        // rb_f_puts(int argc, VALUE *argv, VALUE recv)
        vec![
            Opnd::Imm(passed_argc.into()),
            asm.lea(asm.ctx.sp_opnd((-argc * SIZEOF_VALUE_I32) as isize)),
            asm.stack_opnd(argc),
        ]
    }
    else {
        panic!("unexpected cfunc_args: {}", cfunc_argc)
    };

    // Call the C function
    // VALUE ret = (cfunc->func)(recv, argv[0], argv[1]);
    // cfunc comes from compile-time cme->def, which we assume to be stable.
    // Invalidation logic is in yjit_method_lookup_change()
    asm_comment!(asm, "call C function");
    let ret = asm.ccall(unsafe { get_mct_func(cfunc) }.cast(), args);
    asm.stack_pop((argc + 1).try_into().unwrap()); // Pop arguments after ccall to use registers for passing them.

    // Record code position for TracePoint patching. See full_cfunc_return().
    record_global_inval_patch(asm, CodegenGlobals::get_outline_full_cfunc_return_pos());

    // Push the return value on the Ruby stack
    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, ret);

    // Pop the stack frame (ec->cfp++)
    // Instead of recalculating, we can reuse the previous CFP, which is stored in a callee-saved
    // register
    let ec_cfp_opnd = Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP);
    asm.store(ec_cfp_opnd, CFP);

    // cfunc calls may corrupt types
    asm.ctx.clear_local_types();

    // Note: the return block of gen_send_iseq() has ctx->sp_offset == 1
    // which allows for sharing the same successor.

    // Jump (fall through) to the call continuation block
    // We do this to end the current block after the call
    jump_to_next_insn(jit, asm, ocb);
    Some(EndBlock)
}

// Generate RARRAY_LEN. For array_opnd, use Opnd::Reg to reduce memory access,
// and use Opnd::Mem to save registers.
fn get_array_len(asm: &mut Assembler, array_opnd: Opnd) -> Opnd {
    asm_comment!(asm, "get array length for embedded or heap");

    // Pull out the embed flag to check if it's an embedded array.
    let array_reg = match array_opnd {
        Opnd::InsnOut { .. } => array_opnd,
        _ => asm.load(array_opnd),
    };
    let flags_opnd = Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RBASIC_FLAGS);

    // Get the length of the array
    let emb_len_opnd = asm.and(flags_opnd, (RARRAY_EMBED_LEN_MASK as u64).into());
    let emb_len_opnd = asm.rshift(emb_len_opnd, (RARRAY_EMBED_LEN_SHIFT as u64).into());

    // Conditionally move the length of the heap array
    let flags_opnd = Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags_opnd, (RARRAY_EMBED_FLAG as u64).into());

    let array_reg = match array_opnd {
        Opnd::InsnOut { .. } => array_opnd,
        _ => asm.load(array_opnd),
    };
    let array_len_opnd = Opnd::mem(
        std::os::raw::c_long::BITS as u8,
        array_reg,
        RUBY_OFFSET_RARRAY_AS_HEAP_LEN,
    );

    // Select the array length value
    asm.csel_nz(emb_len_opnd, array_len_opnd)
}

// Generate RARRAY_CONST_PTR (part of RARRAY_AREF)
fn get_array_ptr(asm: &mut Assembler, array_reg: Opnd) -> Opnd {
    asm_comment!(asm, "get array pointer for embedded or heap");

    let flags_opnd = Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags_opnd, (RARRAY_EMBED_FLAG as u64).into());
    let heap_ptr_opnd = Opnd::mem(
        usize::BITS as u8,
        array_reg,
        RUBY_OFFSET_RARRAY_AS_HEAP_PTR,
    );

    // Load the address of the embedded array
    // (struct RArray *)(obj)->as.ary
    let ary_opnd = asm.lea(Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RARRAY_AS_ARY));
    asm.csel_nz(ary_opnd, heap_ptr_opnd)
}

/// Pushes arguments from an array to the stack. Differs from push splat because
/// the array can have items left over. Array is assumed to be T_ARRAY without guards.
fn copy_splat_args_for_rest_callee(array: Opnd, num_args: u32, asm: &mut Assembler) {
    asm_comment!(asm, "copy_splat_args_for_rest_callee");

    // Unused operands cause the backend to panic
    if num_args == 0 {
        return;
    }

    asm_comment!(asm, "Push arguments from array");

    // Load the address of the embedded array
    // (struct RArray *)(obj)->as.ary
    let array_reg = asm.load(array);

    // Conditionally load the address of the heap array
    // (struct RArray *)(obj)->as.heap.ptr
    let flags_opnd = Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags_opnd, Opnd::UImm(RARRAY_EMBED_FLAG as u64));
    let heap_ptr_opnd = Opnd::mem(
        usize::BITS as u8,
        array_reg,
        RUBY_OFFSET_RARRAY_AS_HEAP_PTR,
    );
    // Load the address of the embedded array
    // (struct RArray *)(obj)->as.ary
    let ary_opnd = asm.lea(Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RARRAY_AS_ARY));
    let ary_opnd = asm.csel_nz(ary_opnd, heap_ptr_opnd);

    for i in 0..num_args {
        let top = asm.stack_push(Type::Unknown);
        asm.mov(top, Opnd::mem(64, ary_opnd, i as i32 * SIZEOF_VALUE_I32));
    }
}

/// Pushes arguments from an array to the stack that are passed with a splat (i.e. *args)
/// It optimistically compiles to a static size that is the exact number of arguments
/// needed for the function.
fn push_splat_args(required_args: u32, asm: &mut Assembler) {
    asm_comment!(asm, "push_splat_args");

    let array_opnd = asm.stack_opnd(0);
    let array_reg = asm.load(array_opnd);

    guard_object_is_array(
        asm,
        array_reg,
        array_opnd.into(),
        Counter::guard_send_splat_not_array,
    );

    asm_comment!(asm, "Get array length for embedded or heap");

    // Pull out the embed flag to check if it's an embedded array.
    let flags_opnd = Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RBASIC_FLAGS);

    // Get the length of the array
    let emb_len_opnd = asm.and(flags_opnd, (RARRAY_EMBED_LEN_MASK as u64).into());
    let emb_len_opnd = asm.rshift(emb_len_opnd, (RARRAY_EMBED_LEN_SHIFT as u64).into());

    // Conditionally move the length of the heap array
    let flags_opnd = Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags_opnd, (RARRAY_EMBED_FLAG as u64).into());

    // Need to repeat this here to deal with register allocation
    let array_opnd = asm.stack_opnd(0);
    let array_reg = asm.load(array_opnd);

    let array_len_opnd = Opnd::mem(
        std::os::raw::c_long::BITS as u8,
        array_reg,
        RUBY_OFFSET_RARRAY_AS_HEAP_LEN,
    );
    let array_len_opnd = asm.csel_nz(emb_len_opnd, array_len_opnd);

    asm_comment!(asm, "Guard for expected splat length");
    asm.cmp(array_len_opnd, required_args.into());
    asm.jne(Target::side_exit(Counter::guard_send_splatarray_length_not_equal));

    asm_comment!(asm, "Check last argument is not ruby2keyword hash");

    // Need to repeat this here to deal with register allocation
    let array_reg = asm.load(asm.stack_opnd(0));

    let ary_opnd = get_array_ptr(asm, array_reg);

    let last_array_value = asm.load(Opnd::mem(64, ary_opnd, (required_args as i32 - 1) * (SIZEOF_VALUE as i32)));

    guard_object_is_not_ruby2_keyword_hash(
        asm,
        last_array_value,
        Counter::guard_send_splatarray_last_ruby_2_keywords,
    );

    asm_comment!(asm, "Push arguments from array");
    let array_opnd = asm.stack_pop(1);

    if required_args > 0 {
        // Load the address of the embedded array
        // (struct RArray *)(obj)->as.ary
        let array_reg = asm.load(array_opnd);

        // Conditionally load the address of the heap array
        // (struct RArray *)(obj)->as.heap.ptr
        let flags_opnd = Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RBASIC_FLAGS);
        asm.test(flags_opnd, Opnd::UImm(RARRAY_EMBED_FLAG as u64));
        let heap_ptr_opnd = Opnd::mem(
            usize::BITS as u8,
            array_reg,
            RUBY_OFFSET_RARRAY_AS_HEAP_PTR,
        );
        // Load the address of the embedded array
        // (struct RArray *)(obj)->as.ary
        let ary_opnd = asm.lea(Opnd::mem(VALUE_BITS, array_reg, RUBY_OFFSET_RARRAY_AS_ARY));
        let ary_opnd = asm.csel_nz(ary_opnd, heap_ptr_opnd);

        for i in 0..required_args {
            let top = asm.stack_push(Type::Unknown);
            asm.mov(top, Opnd::mem(64, ary_opnd, i as i32 * SIZEOF_VALUE_I32));
        }

        asm_comment!(asm, "end push_each");
    }
}

fn gen_send_bmethod(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    block: Option<BlockHandler>,
    flags: u32,
    argc: i32,
) -> Option<CodegenStatus> {
    let procv = unsafe { rb_get_def_bmethod_proc((*cme).def) };

    let proc = unsafe { rb_yjit_get_proc_ptr(procv) };
    let proc_block = unsafe { &(*proc).block };

    if proc_block.type_ != block_type_iseq {
        return None;
    }

    let capture = unsafe { proc_block.as_.captured.as_ref() };
    let iseq = unsafe { *capture.code.iseq.as_ref() };

    // Optimize for single ractor mode and avoid runtime check for
    // "defined with an un-shareable Proc in a different Ractor"
    if !assume_single_ractor_mode(jit, asm, ocb) {
        gen_counter_incr(asm, Counter::send_bmethod_ractor);
        return None;
    }

    // Passing a block to a block needs logic different from passing
    // a block to a method and sometimes requires allocation. Bail for now.
    if block.is_some() {
        gen_counter_incr(asm, Counter::send_bmethod_block_arg);
        return None;
    }

    let frame_type = VM_FRAME_MAGIC_BLOCK | VM_FRAME_FLAG_BMETHOD | VM_FRAME_FLAG_LAMBDA;
    gen_send_iseq(jit, asm, ocb, iseq, ci, frame_type, Some(capture.ep), cme, block, flags, argc, None)
}

/// Return the ISEQ's return value if it consists of only putnil/putobject and leave.
fn iseq_get_return_value(iseq: IseqPtr) -> Option<VALUE> {
    // Expect only two instructions and one possible operand
    let iseq_size = unsafe { get_iseq_encoded_size(iseq) };
    if !(2..=3).contains(&iseq_size) {
        return None;
    }

    // Get the first two instructions
    let first_insn = iseq_opcode_at_idx(iseq, 0);
    let second_insn = iseq_opcode_at_idx(iseq, insn_len(first_insn as usize));

    // Extract the return value if known
    if second_insn != YARVINSN_leave {
        return None;
    }
    match first_insn {
        YARVINSN_putnil => Some(Qnil),
        YARVINSN_putobject => unsafe { Some(*rb_iseq_pc_at_idx(iseq, 1)) },
        YARVINSN_putobject_INT2FIX_0_ => Some(VALUE::fixnum_from_usize(0)),
        YARVINSN_putobject_INT2FIX_1_ => Some(VALUE::fixnum_from_usize(1)),
        _ => None,
    }
}

fn gen_send_iseq(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    iseq: *const rb_iseq_t,
    ci: *const rb_callinfo,
    frame_type: u32,
    prev_ep: Option<*const VALUE>,
    cme: *const rb_callable_method_entry_t,
    block: Option<BlockHandler>,
    flags: u32,
    argc: i32,
    captured_opnd: Option<Opnd>,
) -> Option<CodegenStatus> {
    // Argument count. We will change this as we gather values from
    // sources to satisfy the callee's parameters. To help make sense
    // of changes, note that:
    //   - Parameters syntactically on the left have lower addresses.
    //     For example, all the lead (required) and optional parameters
    //     have lower addresses than the rest parameter array.
    //   - The larger the index one passes to Assembler::stack_opnd(),
    //     the *lower* the address.
    let mut argc = argc;

    // Iseqs with keyword parameters have a hidden, unnamed parameter local
    // that the callee could use to know which keywords are unspecified
    // (see the `checkkeyword` instruction and check `ruby --dump=insn -e 'def foo(k:itself)=k'`).
    // We always need to set up this local if the call goes through.
    let doing_kw_call = unsafe { get_iseq_flags_has_kw(iseq) };
    let supplying_kws = unsafe { vm_ci_flag(ci) & VM_CALL_KWARG } != 0;
    let iseq_has_rest = unsafe { get_iseq_flags_has_rest(iseq) };
    let iseq_has_block_param = unsafe { get_iseq_flags_has_block(iseq) };

    // For computing offsets to callee locals
    let num_params = unsafe { get_iseq_body_param_size(iseq) };
    let num_locals = unsafe { get_iseq_body_local_table_size(iseq) as i32 };

    let mut start_pc_offset: u16 = 0;
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
    let mut opts_filled = argc - required_num - kw_arg_num;
    let opt_num = unsafe { get_iseq_body_param_opt_num(iseq) };
    // We have a rest parameter so there could be more args
    // than are required + optional. Those will go in rest.
    // So we cap ops_filled at opt_num.
    if iseq_has_rest {
        opts_filled = min(opts_filled, opt_num);
    }
    let mut opts_missing: i32 = opt_num - opts_filled;

    let block_arg = flags & VM_CALL_ARGS_BLOCKARG != 0;

    exit_if_stack_too_large(iseq)?;
    exit_if_tail_call(asm, ci)?;
    exit_if_has_post(asm, iseq)?;
    exit_if_has_kwrest(asm, iseq)?;
    exit_if_kw_splat(asm, flags)?;
    exit_if_splat_and_ruby2_keywords(asm, jit, flags)?;
    exit_if_has_rest_and_captured(asm, iseq_has_rest, captured_opnd)?;
    exit_if_has_rest_and_supplying_kws(asm, iseq_has_rest, iseq, supplying_kws)?;
    exit_if_supplying_kw_and_has_no_kw(asm, supplying_kws, iseq)?;
    exit_if_supplying_kws_and_accept_no_kwargs(asm, supplying_kws, iseq)?;
    exit_if_splat_and_zsuper(asm, flags)?;
    exit_if_doing_kw_and_splat(asm, doing_kw_call, flags)?;
    exit_if_wrong_number_arguments(asm, opts_filled, flags, opt_num, iseq_has_rest)?;
    exit_if_doing_kw_and_opts_missing(asm, doing_kw_call, opts_missing)?;
    exit_if_has_rest_and_optional_and_block(asm, iseq_has_rest, opt_num, iseq, block_arg)?;
    let block_arg_type = exit_if_unsupported_block_arg_type(jit, asm, block_arg)?;

    // Block parameter handling. This mirrors setup_parameters_complex().
    if iseq_has_block_param {
        if unsafe { get_iseq_body_local_iseq(iseq) == iseq } {
            // Do nothing
        } else {
            // In this case (param.flags.has_block && local_iseq != iseq),
            // the block argument is setup as a local variable and requires
            // materialization (allocation). Bail.
            gen_counter_incr(asm, Counter::send_iseq_materialized_block);
            return None;
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
            gen_counter_incr(asm, Counter::send_iseq_too_many_kwargs);
            return None;
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
                        gen_counter_incr(asm, Counter::send_iseq_kwargs_mismatch);
                        return None;
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
            gen_counter_incr(asm, Counter::send_iseq_kwargs_mismatch);
            return None;
        }
    }

    // Check if we need the arg0 splat handling of vm_callee_setup_block_arg()
    // Also known as "autosplat" inside setup_parameters_complex()
    let arg_setup_block = captured_opnd.is_some(); // arg_setup_type: arg_setup_block (invokeblock)
    let block_arg0_splat = arg_setup_block && argc == 1 && unsafe {
         (get_iseq_flags_has_lead(iseq) || opt_num > 1)
             && !get_iseq_flags_ambiguous_param0(iseq)
    };
    if block_arg0_splat {
        // If block_arg0_splat, we still need side exits after splat, but
        // doing push_splat_args here disallows it. So bail out.
        if flags & VM_CALL_ARGS_SPLAT != 0 && !iseq_has_rest {
            gen_counter_incr(asm, Counter::invokeblock_iseq_arg0_args_splat);
            return None;
        }
        // The block_arg0_splat implementation is for the rb_simple_iseq_p case,
        // but doing_kw_call means it's not a simple ISEQ.
        if doing_kw_call {
            gen_counter_incr(asm, Counter::invokeblock_iseq_arg0_has_kw);
            return None;
        }
        // The block_arg0_splat implementation cannot deal with optional parameters.
        // This is a setup_parameters_complex() situation and interacts with the
        // starting position of the callee.
        if opt_num > 1 {
            gen_counter_incr(asm, Counter::invokeblock_iseq_arg0_optional);
            return None;
        }
    }

    let splat_array_length = if flags & VM_CALL_ARGS_SPLAT != 0 {
        let array = jit.peek_at_stack(&asm.ctx, if block_arg { 1 } else { 0 }) ;
        let array_length = if array == Qnil {
            0
        } else if unsafe { !RB_TYPE_P(array, RUBY_T_ARRAY) } {
            gen_counter_incr(asm, Counter::send_iseq_splat_not_array);
            return None;
        } else {
            unsafe { rb_yjit_array_len(array) as u32}
        };

        // Arity check accounting for size of the splat. When callee has rest parameters, we insert
        // runtime guards later in copy_splat_args_for_rest_callee()
        if !iseq_has_rest {
            let supplying = argc - 1 + array_length as i32;
            if (required_num..=required_num + opt_num).contains(&supplying) == false {
                gen_counter_incr(asm, Counter::send_iseq_splat_arity_error);
                return None;
            }
        }

        if iseq_has_rest && opt_num > 0 {
            // If we have a rest and option arguments
            // we are going to set the pc_offset for where
            // to jump in the called method.
            // If the number of args change, that would need to
            // change and we don't change that dynmically so we side exit.
            // On a normal splat without rest and option args this is handled
            // elsewhere depending on the case
            asm_comment!(asm, "Side exit if length doesn't not equal compile time length");
            let array_len_opnd = get_array_len(asm, asm.stack_opnd(if block_arg { 1 } else { 0 }));
            asm.cmp(array_len_opnd, array_length.into());
            asm.jne(Target::side_exit(Counter::guard_send_splatarray_length_not_equal));
        }

        Some(array_length)
    } else {
        None
    };

    // Adjust `opts_filled` and `opts_missing` taking
    // into account the size of the splat expansion.
    if let Some(len) = splat_array_length {
        assert_eq!(kw_arg_num, 0); // Due to exit_if_doing_kw_and_splat().
                                   // Simplifies calculation below.
        let num_args = (argc - 1) + len as i32;

        opts_filled = if num_args >= required_num {
            min(num_args - required_num, opt_num)
        } else {
            0
        };
        opts_missing = opt_num - opts_filled;
    }

    assert_eq!(opts_missing + opts_filled, opt_num);
    assert!(opts_filled >= 0);

    // ISeq with optional parameters start at different
    // locations depending on the number of optionals given.
    if opt_num > 0 {
        assert!(opts_filled >= 0);
        unsafe {
            let opt_table = get_iseq_body_param_opt_table(iseq);
            start_pc_offset = opt_table.offset(opts_filled as isize).read().try_into().unwrap();
        }
    }

    // Shortcut for special `Primitive.attr! :leaf` builtins
    let builtin_attrs = unsafe { rb_yjit_iseq_builtin_attrs(iseq) };
    let builtin_func_raw = unsafe { rb_yjit_builtin_function(iseq) };
    let builtin_func = if builtin_func_raw.is_null() { None } else { Some(builtin_func_raw) };
    let opt_send_call = flags & VM_CALL_OPT_SEND != 0; // .send call is not currently supported for builtins
    if let (None, Some(builtin_info), true, false) = (block, builtin_func, builtin_attrs & BUILTIN_ATTR_LEAF != 0, opt_send_call) {
        let builtin_argc = unsafe { (*builtin_info).argc };
        if builtin_argc + 1 < (C_ARG_OPNDS.len() as i32) {
            // We pop the block arg without using it because:
            //  - the builtin is leaf, so it promises to not `yield`.
            //  - no leaf builtins have block param at the time of writing, and
            //    adding one requires interpreter changes to support.
            if block_arg_type.is_some() {
                if iseq_has_block_param {
                    gen_counter_incr(asm, Counter::send_iseq_leaf_builtin_block_arg_block_param);
                    return None;
                }
                asm.stack_pop(1);
            }

            asm_comment!(asm, "inlined leaf builtin");
            gen_counter_incr(asm, Counter::num_send_leaf_builtin);

            // Skip this if it doesn't trigger GC
            if builtin_attrs & BUILTIN_ATTR_NO_GC == 0 {
                // The callee may allocate, e.g. Integer#abs on a Bignum.
                // Save SP for GC, save PC for allocation tracing, and prepare
                // for global invalidation after GC's VM lock contention.
                jit_prepare_routine_call(jit, asm);
            }

            // Call the builtin func (ec, recv, arg1, arg2, ...)
            let mut args = vec![EC];

            // Copy self and arguments
            for i in 0..=builtin_argc {
                let stack_opnd = asm.stack_opnd(builtin_argc - i);
                args.push(stack_opnd);
            }
            let val = asm.ccall(unsafe { (*builtin_info).func_ptr as *const u8 }, args);
            asm.stack_pop((builtin_argc + 1).try_into().unwrap()); // Keep them on stack during ccall for GC

            // Push the return value
            let stack_ret = asm.stack_push(Type::Unknown);
            asm.mov(stack_ret, val);

            // Note: assuming that the leaf builtin doesn't change local variables here.
            // Seems like a safe assumption.

            // Let guard chains share the same successor
            jump_to_next_insn(jit, asm, ocb);
            return Some(EndBlock);
        }
    }

    // Inline simple ISEQs whose return value is known at compile time
    if let (Some(value), None, false) = (iseq_get_return_value(iseq), block_arg_type, opt_send_call) {
        asm_comment!(asm, "inlined simple ISEQ");
        gen_counter_incr(asm, Counter::num_send_inline);

        // Pop receiver and arguments
        asm.stack_pop(argc as usize + if captured_opnd.is_some() { 0 } else { 1 });

        // Push the return value
        let stack_ret = asm.stack_push(Type::from(value));
        asm.mov(stack_ret, value.into());

        // Let guard chains share the same successor
        jump_to_next_insn(jit, asm, ocb);
        return Some(EndBlock);
    }

    // Stack overflow check
    // Note that vm_push_frame checks it against a decremented cfp, hence the multiply by 2.
    // #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
    asm_comment!(asm, "stack overflow check");
    let stack_max: i32 = unsafe { get_iseq_body_stack_max(iseq) }.try_into().unwrap();
    let locals_offs =
        SIZEOF_VALUE_I32 * (num_locals + stack_max) + 2 * (RUBY_SIZEOF_CONTROL_FRAME as i32);
    let stack_limit = asm.lea(asm.ctx.sp_opnd(locals_offs as isize));
    asm.cmp(CFP, stack_limit);
    asm.jbe(Target::side_exit(Counter::guard_send_se_cf_overflow));

    if iseq_has_rest && flags & VM_CALL_ARGS_SPLAT != 0 {
        // Insert length guard for a call to copy_splat_args_for_rest_callee()
        // that will come later. We will have made changes to
        // the stack by spilling or handling __send__ shifting
        // by the time we get to that code, so we need the
        // guard here where we can still side exit.
        let non_rest_arg_count = argc - 1;
        if non_rest_arg_count < required_num + opt_num {
            let take_count: u32 = (required_num - non_rest_arg_count + opts_filled)
                .try_into().unwrap();

            if take_count > 0 {
                asm_comment!(asm, "guard splat_array_length >= {take_count}");

                let splat_array = asm.stack_opnd(i32::from(block_arg) + kw_arg_num);
                let array_len_opnd = get_array_len(asm, splat_array);
                asm.cmp(array_len_opnd, take_count.into());
                asm.jl(Target::side_exit(Counter::guard_send_iseq_has_rest_and_splat_too_few));
            }
        }
    }

    match block_arg_type {
        Some(Type::Nil) => {
            // We have a nil block arg, so let's pop it off the args
            asm.stack_pop(1);
        }
        Some(Type::BlockParamProxy) => {
            // We don't need the actual stack value
            asm.stack_pop(1);
        }
        Some(Type::TProc) => {
            // Place the proc as the block handler. We do this early because
            // the block arg being at the top of the stack gets in the way of
            // rest param handling later. Also, since there are C calls that
            // come later, we can't hold this value in a register and place it
            // near the end when we push a new control frame.
            asm_comment!(asm, "guard block arg is a proc");
            // Simple predicate, no need for jit_prepare_routine_call().
            let is_proc = asm.ccall(rb_obj_is_proc as _, vec![asm.stack_opnd(0)]);
            asm.cmp(is_proc, Qfalse.into());
            jit_chain_guard(
                JCC_JE,
                jit,
                asm,
                ocb,
                SEND_MAX_DEPTH,
                Counter::guard_send_block_arg_type,
            );

            let callee_ep = -argc + num_locals + VM_ENV_DATA_SIZE as i32 - 1;
            let callee_specval = callee_ep + VM_ENV_DATA_INDEX_SPECVAL;
            if callee_specval < 0 {
                // Can't write to sp[-n] since that's where the arguments are
                gen_counter_incr(asm, Counter::send_iseq_clobbering_block_arg);
                return None;
            }
            let proc = asm.stack_pop(1); // Pop first, as argc doesn't account for the block arg
            let callee_specval = asm.ctx.sp_opnd(callee_specval as isize * SIZEOF_VALUE as isize);
            asm.store(callee_specval, proc);
        }
        None => {
            // Nothing to do
        }
        _ => unreachable!(),
    }

    // push_splat_args does stack manipulation so we can no longer side exit
    if let Some(array_length) = splat_array_length {
        if !iseq_has_rest {
            // Speculate that future splats will be done with
            // an array that has the same length. We will insert guards.
            argc = argc - 1 + array_length as i32;
            if argc + asm.ctx.get_stack_size() as i32 > MAX_SPLAT_LENGTH {
                gen_counter_incr(asm, Counter::send_splat_too_long);
                return None;
            }
            push_splat_args(array_length, asm);
        }
    }

    // This is a .send call and we need to adjust the stack
    // TODO: This can be more efficient if we do it before
    //       extracting from the splat array above.
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc);
    }

    if iseq_has_rest {
        // We are going to allocate so setting pc and sp.
        jit_save_pc(jit, asm);
        gen_save_sp(asm);

        let rest_param_array = if flags & VM_CALL_ARGS_SPLAT != 0 {
            let non_rest_arg_count = argc - 1;
            // We start by dupping the array because someone else might have
            // a reference to it. This also normalizes to an ::Array instance.
            let array = asm.stack_opnd(0);
            let array = asm.ccall(
                rb_ary_dup as *const u8,
                vec![array],
            );
            asm.stack_pop(1); // Pop array after ccall to use a register for passing it.

            // This is the end stack state of all `non_rest_arg_count` situations below
            argc = required_num + opts_filled;

            if non_rest_arg_count > required_num + opt_num {
                // If we have more arguments than required, we need to prepend
                // the items from the stack onto the array.
                let diff: u32 = (non_rest_arg_count - (required_num + opt_num))
                    .try_into().unwrap();

                // diff is >0 so no need to worry about null pointer
                asm_comment!(asm, "load pointer to array elements");
                let offset_magnitude = SIZEOF_VALUE as u32 * diff;
                let values_opnd = asm.ctx.sp_opnd(-(offset_magnitude as isize));
                let values_ptr = asm.lea(values_opnd);

                asm_comment!(asm, "prepend stack values to rest array");
                let array = asm.ccall(
                    rb_ary_unshift_m as *const u8,
                    vec![Opnd::UImm(diff as u64), values_ptr, array],
                );
                asm.stack_pop(diff as usize);

                array
            } else if non_rest_arg_count < required_num + opt_num {
                // If we have fewer arguments than required, we need to take some
                // from the array and move them to the stack.
                asm_comment!(asm, "take items from splat array");

                let take_count: u32 = (required_num - non_rest_arg_count + opts_filled)
                    .try_into().unwrap();

                // Copy required arguments to the stack without modifying the array
                copy_splat_args_for_rest_callee(array, take_count, asm);

                // We will now slice the array to give us a new array of the correct size
                let sliced = asm.ccall(rb_yjit_rb_ary_subseq_length as *const u8, vec![array, Opnd::UImm(take_count.into())]);

                sliced
            } else {
                // The arguments are equal so we can just push to the stack
                asm_comment!(asm, "same length for splat array and rest param");
                assert!(non_rest_arg_count == required_num + opt_num);

                array
            }
        } else {
            asm_comment!(asm, "rest parameter without splat");

            assert!(argc >= required_num);
            let n = (argc - required_num - opts_filled) as u32;
            argc = required_num + opts_filled;
            // If n is 0, then elts is never going to be read, so we can just pass null
            let values_ptr = if n == 0 {
                Opnd::UImm(0)
            } else {
                asm_comment!(asm, "load pointer to array elements");
                let offset_magnitude = SIZEOF_VALUE as u32 * n;
                let values_opnd = asm.ctx.sp_opnd(-(offset_magnitude as isize));
                asm.lea(values_opnd)
            };

            let new_ary = asm.ccall(
                rb_ec_ary_new_from_values as *const u8,
                vec![
                    EC,
                    Opnd::UImm(n.into()),
                    values_ptr
                ]
            );
            asm.stack_pop(n.as_usize());

            new_ary
        };

        // Find where to put the rest parameter array
        let rest_param = if opts_missing == 0 {
            // All optionals are filled, the rest param goes at the top of the stack
            argc += 1;
            asm.stack_push(Type::TArray)
        } else {
            // The top of the stack will be a missing optional, but the rest
            // parameter needs to be placed after all the missing optionals.
            // Place it using a stack operand with a negative stack index.
            // (Higher magnitude negative stack index have higher address.)
            assert!(opts_missing > 0);
            // The argument deepest in the stack will be the 0th local in the callee.
            let callee_locals_base = argc - 1;
            let rest_param_stack_idx = callee_locals_base - required_num - opt_num;
            assert!(rest_param_stack_idx < 0);
            asm.stack_opnd(rest_param_stack_idx)
        };
        // Store rest param to memory to avoid register shuffle as
        // we won't be reading it for the remainder of the block.
        asm.ctx.dealloc_temp_reg(rest_param.stack_idx());
        asm.store(rest_param, rest_param_array);
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

        asm_comment!(asm, "keyword args");

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
                let default_arg = asm.stack_push(Type::Unknown);

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
                    stack_swap(asm, offset0, offset1);

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
        asm.ctx.dealloc_temp_reg(asm.stack_opnd(-1).stack_idx()); // avoid using a register for unspecified_bits
        asm.mov(asm.stack_opnd(-1), unspec_opnd.into());
    }

    // Same as vm_callee_setup_block_arg_arg0_check and vm_callee_setup_block_arg_arg0_splat
    // on vm_callee_setup_block_arg for arg_setup_block. This is done after CALLER_SETUP_ARG
    // and CALLER_REMOVE_EMPTY_KW_SPLAT, so this implementation is put here. This may need
    // side exits, so you still need to allow side exits here if block_arg0_splat is true.
    // Note that you can't have side exits after this arg0 splat.
    if block_arg0_splat {
        let arg0_opnd = asm.stack_opnd(0);

        // Only handle the case that you don't need to_ary conversion
        let not_array_counter = Counter::invokeblock_iseq_arg0_not_array;
        guard_object_is_array(asm, arg0_opnd, arg0_opnd.into(), not_array_counter);

        // Only handle the same that the array length == ISEQ's lead_num (most common)
        let arg0_len_opnd = get_array_len(asm, arg0_opnd);
        let lead_num = unsafe { rb_get_iseq_body_param_lead_num(iseq) };
        asm.cmp(arg0_len_opnd, lead_num.into());
        asm.jne(Target::side_exit(Counter::invokeblock_iseq_arg0_wrong_len));

        let arg0_reg = asm.load(arg0_opnd);
        let array_opnd = get_array_ptr(asm, arg0_reg);
        asm_comment!(asm, "push splat arg0 onto the stack");
        asm.stack_pop(argc.try_into().unwrap());
        for i in 0..lead_num {
            let stack_opnd = asm.stack_push(Type::Unknown);
            asm.mov(stack_opnd, Opnd::mem(64, array_opnd, SIZEOF_VALUE_I32 * i));
        }
        argc = lead_num;
    }

    fn nil_fill(comment: &'static str, fill_range: std::ops::Range<isize>, asm: &mut Assembler) {
        if fill_range.is_empty() {
            return;
        }

        asm_comment!(asm, "{}", comment);
        for i in fill_range {
            let value_slot = asm.ctx.sp_opnd(i * SIZEOF_VALUE as isize);
            asm.store(value_slot, Qnil.into());
        }
    }

    // Nil-initialize missing optional parameters
    nil_fill(
        "nil-initialize missing optionals",
        {
            let begin = -(argc as isize) + required_num as isize + opts_filled as isize;
            let end   = -(argc as isize) + required_num as isize + opt_num as isize;

            begin..end
        },
        asm
    );
    // Nil-initialize the block parameter. It's the last parameter local
    if iseq_has_block_param {
        let block_param = asm.ctx.sp_opnd(
            SIZEOF_VALUE as isize * (-(argc as isize) + num_params as isize - 1)
        );
        asm.store(block_param, Qnil.into());
    }
    // Nil-initialize non-parameter locals
    nil_fill(
        "nil-initialize locals",
        {
            let begin = -(argc as isize) + num_params as isize;
            let end   = -(argc as isize) + num_locals as isize;

            begin..end
        },
        asm
    );

    // Points to the receiver operand on the stack unless a captured environment is used
    let recv = match captured_opnd {
        Some(captured_opnd) => asm.load(Opnd::mem(64, captured_opnd, 0)), // captured->self
        _ => asm.stack_opnd(argc),
    };
    let captured_self = captured_opnd.is_some();
    let sp_offset = (argc as isize) + if captured_self { 0 } else { 1 };

    // Store the updated SP on the current frame (pop arguments and receiver)
    asm_comment!(asm, "store caller sp");
    let caller_sp = asm.lea(asm.ctx.sp_opnd((SIZEOF_VALUE as isize) * -sp_offset));
    asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP), caller_sp);

    // Store the next PC in the current frame
    jit_save_pc(jit, asm);

    // Adjust the callee's stack pointer
    let offs = (SIZEOF_VALUE as isize) * (
        -(argc as isize) + num_locals as isize + VM_ENV_DATA_SIZE as isize
    );
    let callee_sp = asm.lea(asm.ctx.sp_opnd(offs));

    let specval = if let Some(prev_ep) = prev_ep {
        // We've already side-exited if the callee expects a block, so we
        // ignore any supplied block here
        SpecVal::PrevEP(prev_ep)
    } else if let Some(captured_opnd) = captured_opnd {
        let ep_opnd = asm.load(Opnd::mem(64, captured_opnd, SIZEOF_VALUE_I32)); // captured->ep
        SpecVal::PrevEPOpnd(ep_opnd)
    } else if let Some(Type::TProc) = block_arg_type {
        SpecVal::BlockHandler(Some(BlockHandler::AlreadySet))
    } else if let Some(Type::BlockParamProxy) = block_arg_type {
        SpecVal::BlockHandler(Some(BlockHandler::BlockParamProxy))
    } else {
        SpecVal::BlockHandler(block)
    };

    // Setup the new frame
    gen_push_frame(jit, asm, ControlFrame {
        frame_type,
        specval,
        cme,
        recv,
        sp: callee_sp,
        iseq: Some(iseq),
        pc: None, // We are calling into jitted code, which will set the PC as necessary
    });

    // No need to set cfp->pc since the callee sets it whenever calling into routines
    // that could look at it through jit_save_pc().
    // mov(cb, REG0, const_ptr_opnd(start_pc));
    // mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), REG0);

    // Stub so we can return to JITted code
    let return_block = BlockId {
        iseq: jit.iseq,
        idx: jit.next_insn_idx(),
    };

    // Create a context for the callee
    let mut callee_ctx = Context::default();

    // Set the argument types in the callee's context
    for arg_idx in 0..argc {
        let stack_offs: u8 = (argc - arg_idx - 1).try_into().unwrap();
        let arg_type = asm.ctx.get_opnd_type(StackOpnd(stack_offs));
        callee_ctx.set_local_type(arg_idx.try_into().unwrap(), arg_type);
    }

    let recv_type = if captured_self {
        Type::Unknown // we don't track the type information of captured->self for now
    } else {
        asm.ctx.get_opnd_type(StackOpnd(argc.try_into().unwrap()))
    };
    callee_ctx.upgrade_opnd_type(SelfOpnd, recv_type);

    // The callee might change locals through Kernel#binding and other means.
    asm.ctx.clear_local_types();

    // Pop arguments and receiver in return context and
    // mark it as a continuation of gen_leave()
    let mut return_asm = Assembler::new();
    return_asm.ctx = asm.ctx;
    return_asm.stack_pop(sp_offset.try_into().unwrap());
    return_asm.ctx.set_sp_offset(0); // We set SP on the caller's frame above
    return_asm.ctx.reset_chain_depth();
    return_asm.ctx.set_as_return_landing();

    // Write the JIT return address on the callee frame
    gen_branch(
        jit,
        asm,
        ocb,
        return_block,
        &return_asm.ctx,
        None,
        None,
        BranchGenFn::JITReturn,
    );

    // ec->cfp is updated after cfp->jit_return for rb_profile_frames() safety
    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

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

    Some(EndBlock)
}

/// This is a helper function to allow us to exit early
/// during code generation if a predicate is true.
/// We return Option<()> here because we will be able to
/// short-circuit using the ? operator if we return None.
/// It would be great if rust let you implement ? for your
/// own types, but as of right now they don't.
fn exit_if(asm: &mut Assembler, pred: bool, counter: Counter) -> Option<()> {
    if pred {
        gen_counter_incr(asm, counter);
        return None
    }
    Some(())
}

#[must_use]
fn exit_if_tail_call(asm: &mut Assembler, ci: *const rb_callinfo) -> Option<()> {
    exit_if(asm, unsafe { vm_ci_flag(ci) } & VM_CALL_TAILCALL != 0, Counter::send_iseq_tailcall)
}

#[must_use]
fn exit_if_has_post(asm: &mut Assembler, iseq: *const rb_iseq_t) -> Option<()> {
    exit_if(asm, unsafe { get_iseq_flags_has_post(iseq) }, Counter::send_iseq_has_post)
}

#[must_use]
fn exit_if_has_kwrest(asm: &mut Assembler, iseq: *const rb_iseq_t) -> Option<()> {
    exit_if(asm, unsafe { get_iseq_flags_has_kwrest(iseq) }, Counter::send_iseq_has_kwrest)
}

#[must_use]
fn exit_if_kw_splat(asm: &mut Assembler, flags: u32) -> Option<()> {
    exit_if(asm, flags & VM_CALL_KW_SPLAT != 0, Counter::send_iseq_kw_splat)
}

#[must_use]
fn exit_if_splat_and_ruby2_keywords(asm: &mut Assembler, jit: &mut JITState, flags: u32) -> Option<()> {
    // In order to handle backwards compatibility between ruby 3 and 2
    // ruby2_keywords was introduced. It is called only on methods
    // with splat and changes they way they handle them.
    // We are just going to not compile these.
    // https://www.rubydoc.info/stdlib/core/Proc:ruby2_keywords
    exit_if(
        asm,
        unsafe { get_iseq_flags_ruby2_keywords(jit.iseq) } && flags & VM_CALL_ARGS_SPLAT != 0,
        Counter::send_iseq_ruby2_keywords,
    )
}

#[must_use]
fn exit_if_has_rest_and_captured(asm: &mut Assembler, iseq_has_rest: bool, captured_opnd: Option<Opnd>) -> Option<()> {
    exit_if(asm, iseq_has_rest && captured_opnd.is_some(), Counter::send_iseq_has_rest_and_captured)
}

#[must_use]
fn exit_if_has_rest_and_supplying_kws(asm: &mut Assembler, iseq_has_rest: bool, iseq: *const rb_iseq_t, supplying_kws: bool) -> Option<()> {
    exit_if(
        asm,
        iseq_has_rest && unsafe { get_iseq_flags_has_kw(iseq) } && supplying_kws,
        Counter::send_iseq_has_rest_and_kw_supplied,
    )
}

#[must_use]
fn exit_if_supplying_kw_and_has_no_kw(asm: &mut Assembler, supplying_kws: bool, iseq: *const rb_iseq_t) -> Option<()> {
    // If we have keyword arguments being passed to a callee that only takes
    // positionals, then we need to allocate a hash. For now we're going to
    // call that too complex and bail.
    exit_if(
        asm,
        supplying_kws && !unsafe { get_iseq_flags_has_kw(iseq) },
        Counter::send_iseq_has_no_kw,
    )
}

#[must_use]
fn exit_if_supplying_kws_and_accept_no_kwargs(asm: &mut Assembler, supplying_kws: bool, iseq: *const rb_iseq_t) -> Option<()> {
    // If we have a method accepting no kwargs (**nil), exit if we have passed
    // it any kwargs.
    exit_if(
        asm,
        supplying_kws && unsafe { get_iseq_flags_accepts_no_kwarg(iseq) },
        Counter::send_iseq_accepts_no_kwarg
    )
}

#[must_use]
fn exit_if_splat_and_zsuper(asm: &mut Assembler, flags: u32) -> Option<()> {
    // zsuper methods are super calls without any arguments.
    // They are also marked as splat, but don't actually have an array
    // they pull arguments from, instead we need to change to call
    // a different method with the current stack.
    exit_if(asm, flags & VM_CALL_ARGS_SPLAT != 0 && flags & VM_CALL_ZSUPER != 0, Counter::send_iseq_zsuper)
}

#[must_use]
fn exit_if_doing_kw_and_splat(asm: &mut Assembler, doing_kw_call: bool, flags: u32) -> Option<()> {
    exit_if(asm, doing_kw_call && flags & VM_CALL_ARGS_SPLAT != 0, Counter::send_iseq_splat_with_kw)
}

#[must_use]
fn exit_if_wrong_number_arguments(asm: &mut Assembler, opts_filled: i32, flags: u32, opt_num: i32, iseq_has_rest: bool) -> Option<()> {
    // Too few arguments and no splat to make up for it
    let too_few = opts_filled < 0 && flags & VM_CALL_ARGS_SPLAT == 0;
    // Too many arguments and no place to put them (i.e. rest arg)
    let too_many = opts_filled > opt_num && !iseq_has_rest;

    exit_if(asm, too_few || too_many, Counter::send_iseq_arity_error)
}

#[must_use]
fn exit_if_doing_kw_and_opts_missing(asm: &mut Assembler, doing_kw_call: bool, opts_missing: i32) -> Option<()> {
    // If we have unfilled optional arguments and keyword arguments then we
    // would need to adjust the arguments location to account for that.
    // For now we aren't handling this case.
    exit_if(asm, doing_kw_call && opts_missing > 0, Counter::send_iseq_missing_optional_kw)
}

#[must_use]
fn exit_if_has_rest_and_optional_and_block(asm: &mut Assembler, iseq_has_rest: bool, opt_num: i32, iseq: *const rb_iseq_t, block_arg: bool) -> Option<()> {
    exit_if(
        asm,
        iseq_has_rest && opt_num != 0 && (unsafe { get_iseq_flags_has_block(iseq) } || block_arg),
        Counter::send_iseq_has_rest_opt_and_block
    )
}

#[must_use]
fn exit_if_unsupported_block_arg_type(
    jit: &mut JITState,
    asm: &mut Assembler,
    supplying_block_arg: bool
) -> Option<Option<Type>> {
    let block_arg_type = if supplying_block_arg {
        asm.ctx.get_opnd_type(StackOpnd(0))
    } else {
        // Passing no block argument
        return Some(None);
    };

    match block_arg_type {
        Type::Nil | Type::BlockParamProxy => {
            // We'll handle this later
            Some(Some(block_arg_type))
        }
        _ if {
            let sample_block_arg = jit.peek_at_stack(&asm.ctx, 0);
            unsafe { rb_obj_is_proc(sample_block_arg) }.test()
        } => {
            // Speculate that we'll have a proc as the block arg
            Some(Some(Type::TProc))
        }
        _ => {
            gen_counter_incr(asm, Counter::send_block_arg);
            None
        }
    }
}

#[must_use]
fn exit_if_stack_too_large(iseq: *const rb_iseq_t) -> Option<()> {
    let stack_max = unsafe { rb_get_iseq_body_stack_max(iseq) };
    // Reject ISEQs with very large temp stacks,
    // this will allow us to use u8/i8 values to track stack_size and sp_offset
    if stack_max >= i8::MAX as u32 {
        incr_counter!(iseq_stack_too_large);
        return None;
    }
    Some(())
}

fn gen_struct_aref(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    comptime_recv: VALUE,
    flags: u32,
    argc: i32,
) -> Option<CodegenStatus> {

    if unsafe { vm_ci_argc(ci) } != 0 {
        return None;
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
            return None;
        }
    }

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc);
    }

    // All structs from the same Struct class should have the same
    // length. So if our comptime_recv is embedded all runtime
    // structs of the same class should be as well, and the same is
    // true of the converse.
    let embedded = unsafe { FL_TEST_RAW(comptime_recv, VALUE(RSTRUCT_EMBED_LEN_MASK)) };

    asm_comment!(asm, "struct aref");

    let recv = asm.stack_pop(1);
    let recv = asm.load(recv);

    let val = if embedded != VALUE(0) {
        Opnd::mem(64, recv, RUBY_OFFSET_RSTRUCT_AS_ARY + (SIZEOF_VALUE_I32 * off))
    } else {
        let rstruct_ptr = asm.load(Opnd::mem(64, recv, RUBY_OFFSET_RSTRUCT_AS_HEAP_PTR));
        Opnd::mem(64, rstruct_ptr, SIZEOF_VALUE_I32 * off)
    };

    let ret = asm.stack_push(Type::Unknown);
    asm.mov(ret, val);

    jump_to_next_insn(jit, asm, ocb);
    Some(EndBlock)
}

fn gen_struct_aset(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    comptime_recv: VALUE,
    flags: u32,
    argc: i32,
) -> Option<CodegenStatus> {
    if unsafe { vm_ci_argc(ci) } != 1 {
        return None;
    }

    // This is a .send call and we need to adjust the stack
    if flags & VM_CALL_OPT_SEND != 0 {
        handle_opt_send_shift_stack(asm, argc);
    }

    let off: i32 = unsafe { get_cme_def_body_optimized_index(cme) }
        .try_into()
        .unwrap();

    // Confidence checks
    assert!(unsafe { RB_TYPE_P(comptime_recv, RUBY_T_STRUCT) });
    assert!((off as i64) < unsafe { RSTRUCT_LEN(comptime_recv) });

    asm_comment!(asm, "struct aset");

    let val = asm.stack_pop(1);
    let recv = asm.stack_pop(1);

    let val = asm.ccall(RSTRUCT_SET as *const u8, vec![recv, (off as i64).into(), val]);

    let ret = asm.stack_push(Type::Unknown);
    asm.mov(ret, val);

    jump_to_next_insn(jit, asm, ocb);
    Some(EndBlock)
}

// Generate code that calls a method with dynamic dispatch
fn gen_send_dynamic<F: Fn(&mut Assembler) -> Opnd>(
    jit: &mut JITState,
    asm: &mut Assembler,
    cd: *const rb_call_data,
    sp_pops: usize,
    vm_sendish: F,
) -> Option<CodegenStatus> {
    // Our frame handling is not compatible with tailcall
    if unsafe { vm_ci_flag((*cd).ci) } & VM_CALL_TAILCALL != 0 {
        return None;
    }

    // Save PC and SP to prepare for dynamic dispatch
    jit_prepare_routine_call(jit, asm);

    // Dispatch a method
    let ret = vm_sendish(asm);

    // Pop arguments and a receiver
    asm.stack_pop(sp_pops);

    // Push the return value
    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, ret);

    // Fix the interpreter SP deviated by vm_sendish
    asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP), SP);

    gen_counter_incr(asm, Counter::num_send_dynamic);
    Some(KeepCompiling)
}

fn gen_send_general(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    cd: *const rb_call_data,
    block: Option<BlockHandler>,
) -> Option<CodegenStatus> {
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
        gen_counter_incr(asm, Counter::send_kw_splat);
        return None;
    }

    // Defer compilation so we can specialize on class of receiver
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    let recv_idx = argc + if flags & VM_CALL_ARGS_BLOCKARG != 0 { 1 } else { 0 };
    let comptime_recv = jit.peek_at_stack(&asm.ctx, recv_idx as isize);
    let comptime_recv_klass = comptime_recv.class_of();
    assert_eq!(RUBY_T_CLASS, comptime_recv_klass.builtin_type(),
        "objects visible to ruby code should have a T_CLASS in their klass field");

    // Don't compile calls through singleton classes to avoid retaining the receiver.
    // Make an exception for class methods since classes tend to be retained anyways.
    // Also compile calls on top_self to help tests.
    if VALUE(0) != unsafe { FL_TEST(comptime_recv_klass, VALUE(RUBY_FL_SINGLETON as usize)) }
        && comptime_recv != unsafe { rb_vm_top_self() }
        && !unsafe { RB_TYPE_P(comptime_recv, RUBY_T_CLASS) }
        && !unsafe { RB_TYPE_P(comptime_recv, RUBY_T_MODULE) } {
        gen_counter_incr(asm, Counter::send_singleton_class);
        return None;
    }

    // Points to the receiver operand on the stack
    let recv = asm.stack_opnd(recv_idx);
    let recv_opnd: YARVOpnd = recv.into();

    // Log the name of the method we're calling to
    #[cfg(feature = "disasm")]
    {
        let class_name = unsafe { cstr_to_rust_string(rb_class2name(comptime_recv_klass)) };
        let method_name = unsafe { cstr_to_rust_string(rb_id2name(mid)) };
        match (class_name, method_name) {
            (Some(class_name), Some(method_name)) => {
                asm_comment!(asm, "call to {}#{}", class_name, method_name);
            }
            _ => {}
        }
    }

    // Gather some statistics about sends
    gen_counter_incr(asm, Counter::num_send);
    if let Some(_known_klass) = asm.ctx.get_opnd_type(recv_opnd).known_class()  {
        gen_counter_incr(asm, Counter::num_send_known_class);
    }
    if asm.ctx.get_chain_depth() > 1 {
        gen_counter_incr(asm, Counter::num_send_polymorphic);
    }
    // If megamorphic, let the caller fallback to dynamic dispatch
    if asm.ctx.get_chain_depth() as i32 >= SEND_MAX_DEPTH {
        gen_counter_incr(asm, Counter::send_megamorphic);
        return None;
    }

    jit_guard_known_klass(
        jit,
        asm,
        ocb,
        comptime_recv_klass,
        recv,
        recv_opnd,
        comptime_recv,
        SEND_MAX_DEPTH,
        Counter::guard_send_klass_megamorphic,
    );

    // Do method lookup
    let mut cme = unsafe { rb_callable_method_entry(comptime_recv_klass, mid) };
    if cme.is_null() {
        gen_counter_incr(asm, Counter::send_cme_not_found);
        return None;
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
                gen_counter_incr(asm, Counter::send_private_not_fcall);
                return None;
            }
        }
        METHOD_VISI_PROTECTED => {
            // If the method call is an FCALL, it is always valid
            if flags & VM_CALL_FCALL == 0 {
                // otherwise we need an ancestry check to ensure the receiver is valid to be called
                // as protected
                jit_protected_callee_ancestry_guard(asm, cme);
            }
        }
        _ => {
            panic!("cmes should always have a visibility!");
        }
    }

    // Register block for invalidation
    //assert!(cme->called_id == mid);
    jit.assume_method_lookup_stable(asm, ocb, cme);

    // To handle the aliased method case (VM_METHOD_TYPE_ALIAS)
    loop {
        let def_type = unsafe { get_cme_def_type(cme) };

        match def_type {
            VM_METHOD_TYPE_ISEQ => {
                let iseq = unsafe { get_def_iseq_ptr((*cme).def) };
                let frame_type = VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL;
                return gen_send_iseq(jit, asm, ocb, iseq, ci, frame_type, None, cme, block, flags, argc, None);
            }
            VM_METHOD_TYPE_CFUNC => {
                return gen_send_cfunc(
                    jit,
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
                if flags & VM_CALL_ARGS_SPLAT != 0 {
                    gen_counter_incr(asm, Counter::send_args_splat_ivar);
                    return None;
                }

                if argc != 0 {
                    // Argument count mismatch. Getters take no arguments.
                    gen_counter_incr(asm, Counter::send_getter_arity);
                    return None;
                }

                // This is a .send call not supported right now for getters
                if flags & VM_CALL_OPT_SEND != 0 {
                    gen_counter_incr(asm, Counter::send_send_getter);
                    return None;
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
                    gen_counter_incr(asm, Counter::send_cfunc_tracing);
                    return None;
                }

                let ivar_name = unsafe { get_cme_def_body_attr_id(cme) };

                if flags & VM_CALL_ARGS_BLOCKARG != 0 {
                    gen_counter_incr(asm, Counter::send_block_arg);
                    return None;
                }

                return gen_get_ivar(
                    jit,
                    asm,
                    ocb,
                    SEND_MAX_DEPTH,
                    comptime_recv,
                    ivar_name,
                    recv,
                    recv_opnd,
                );
            }
            VM_METHOD_TYPE_ATTRSET => {
                if flags & VM_CALL_ARGS_SPLAT != 0 {
                    gen_counter_incr(asm, Counter::send_args_splat_attrset);
                    return None;
                }
                if flags & VM_CALL_KWARG != 0 {
                    gen_counter_incr(asm, Counter::send_attrset_kwargs);
                    return None;
                } else if argc != 1 || unsafe { !RB_TYPE_P(comptime_recv, RUBY_T_OBJECT) } {
                    gen_counter_incr(asm, Counter::send_ivar_set_method);
                    return None;
                } else if c_method_tracing_currently_enabled(jit) {
                    // Can't generate code for firing c_call and c_return events
                    // See :attr-tracing:
                    gen_counter_incr(asm, Counter::send_cfunc_tracing);
                    return None;
                } else if flags & VM_CALL_ARGS_BLOCKARG != 0 {
                    gen_counter_incr(asm, Counter::send_block_arg);
                    return None;
                } else {
                    let ivar_name = unsafe { get_cme_def_body_attr_id(cme) };
                    return gen_set_ivar(jit, asm, ivar_name, flags, argc);
                }
            }
            // Block method, e.g. define_method(:foo) { :my_block }
            VM_METHOD_TYPE_BMETHOD => {
                if flags & VM_CALL_ARGS_SPLAT != 0 {
                    gen_counter_incr(asm, Counter::send_args_splat_bmethod);
                    return None;
                }
                return gen_send_bmethod(jit, asm, ocb, ci, cme, block, flags, argc);
            }
            VM_METHOD_TYPE_ALIAS => {
                // Retrieve the aliased method and re-enter the switch
                cme = unsafe { rb_aliased_callable_method_entry(cme) };
                continue;
            }
            // Send family of methods, e.g. call/apply
            VM_METHOD_TYPE_OPTIMIZED => {
                if flags & VM_CALL_ARGS_BLOCKARG != 0 {
                    gen_counter_incr(asm, Counter::send_block_arg);
                    return None;
                }

                let opt_type = unsafe { get_cme_def_body_optimized_type(cme) };
                match opt_type {
                    OPTIMIZED_METHOD_TYPE_SEND => {
                        // This is for method calls like `foo.send(:bar)`
                        // The `send` method does not get its own stack frame.
                        // instead we look up the method and call it,
                        // doing some stack shifting based on the VM_CALL_OPT_SEND flag

                        // Reject nested cases such as `send(:send, :alias_for_send, :foo))`.
                        // We would need to do some stack manipulation here or keep track of how
                        // many levels deep we need to stack manipulate. Because of how exits
                        // currently work, we can't do stack manipulation until we will no longer
                        // side exit.
                        if flags & VM_CALL_OPT_SEND != 0 {
                            gen_counter_incr(asm, Counter::send_send_nested);
                            return None;
                        }

                        if argc == 0 {
                            gen_counter_incr(asm, Counter::send_send_wrong_args);
                            return None;
                        }

                        argc -= 1;

                        let compile_time_name = jit.peek_at_stack(&asm.ctx, argc as isize);

                        if !compile_time_name.string_p() && !compile_time_name.static_sym_p()  {
                            gen_counter_incr(asm, Counter::send_send_chain_not_string_or_sym);
                            return None;
                        }

                        mid = unsafe { rb_get_symbol_id(compile_time_name) };
                        if mid == 0 {
                            gen_counter_incr(asm, Counter::send_send_null_mid);
                            return None;
                        }

                        cme = unsafe { rb_callable_method_entry(comptime_recv_klass, mid) };
                        if cme.is_null() {
                            gen_counter_incr(asm, Counter::send_send_null_cme);
                            return None;
                        }

                        flags |= VM_CALL_FCALL | VM_CALL_OPT_SEND;

                        jit.assume_method_lookup_stable(asm, ocb, cme);

                        let (known_class, type_mismatch_counter) = {
                            if compile_time_name.string_p() {
                                (
                                    unsafe { rb_cString },
                                    Counter::guard_send_send_chain_not_string,
                                )
                            } else {
                                (
                                    unsafe { rb_cSymbol },
                                    Counter::guard_send_send_chain_not_sym,
                                )
                            }
                        };

                        let name_opnd = asm.stack_opnd(argc);
                        jit_guard_known_klass(
                            jit,
                            asm,
                            ocb,
                            known_class,
                            name_opnd,
                            name_opnd.into(),
                            compile_time_name,
                            2, // We have string or symbol, so max depth is 2
                            type_mismatch_counter
                        );

                        // Need to do this here so we don't have too many live
                        // values for the register allocator.
                        let name_opnd = asm.load(name_opnd);

                        let symbol_id_opnd = asm.ccall(rb_get_symbol_id as *const u8, vec![name_opnd]);

                        asm_comment!(asm, "chain_guard_send");
                        asm.cmp(symbol_id_opnd, mid.into());
                        jit_chain_guard(
                            JCC_JNE,
                            jit,
                            asm,
                            ocb,
                            SEND_MAX_DEPTH,
                            Counter::guard_send_send_chain,
                        );

                        // We have changed the argc, flags, mid, and cme, so we need to re-enter the match
                        // and compile whatever method we found from send.
                        continue;

                    }
                    OPTIMIZED_METHOD_TYPE_CALL => {

                        if block.is_some() {
                            gen_counter_incr(asm, Counter::send_call_block);
                            return None;
                        }

                        if flags & VM_CALL_KWARG != 0 {
                            gen_counter_incr(asm, Counter::send_call_kwarg);
                            return None;
                        }

                        if flags & VM_CALL_ARGS_SPLAT != 0 {
                            gen_counter_incr(asm, Counter::send_args_splat_opt_call);
                            return None;
                        }

                        // Optimize for single ractor mode and avoid runtime check for
                        // "defined with an un-shareable Proc in a different Ractor"
                        if !assume_single_ractor_mode(jit, asm, ocb) {
                            gen_counter_incr(asm, Counter::send_call_multi_ractor);
                            return None;
                        }

                        // If this is a .send call we need to adjust the stack
                        if flags & VM_CALL_OPT_SEND != 0 {
                            handle_opt_send_shift_stack(asm, argc);
                        }

                        // About to reset the SP, need to load this here
                        let recv_load = asm.load(recv);

                        let sp = asm.lea(asm.ctx.sp_opnd(0));

                        // Save the PC and SP because the callee can make Ruby calls
                        jit_prepare_routine_call(jit, asm);

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

                        asm.stack_pop(argc as usize + 1);

                        let stack_ret = asm.stack_push(Type::Unknown);
                        asm.mov(stack_ret, ret);
                        return Some(KeepCompiling);

                    }
                    OPTIMIZED_METHOD_TYPE_BLOCK_CALL => {
                        gen_counter_incr(asm, Counter::send_optimized_method_block_call);
                        return None;
                    }
                    OPTIMIZED_METHOD_TYPE_STRUCT_AREF => {
                        if flags & VM_CALL_ARGS_SPLAT != 0 {
                            gen_counter_incr(asm, Counter::send_args_splat_aref);
                            return None;
                        }
                        return gen_struct_aref(
                            jit,
                            asm,
                            ocb,
                            ci,
                            cme,
                            comptime_recv,
                            flags,
                            argc,
                        );
                    }
                    OPTIMIZED_METHOD_TYPE_STRUCT_ASET => {
                        if flags & VM_CALL_ARGS_SPLAT != 0 {
                            gen_counter_incr(asm, Counter::send_args_splat_aset);
                            return None;
                        }
                        return gen_struct_aset(
                            jit,
                            asm,
                            ocb,
                            ci,
                            cme,
                            comptime_recv,
                            flags,
                            argc,
                        );
                    }
                    _ => {
                        panic!("unknown optimized method type!")
                    }
                }
            }
            VM_METHOD_TYPE_ZSUPER => {
                gen_counter_incr(asm, Counter::send_zsuper_method);
                return None;
            }
            VM_METHOD_TYPE_UNDEF => {
                gen_counter_incr(asm, Counter::send_undef_method);
                return None;
            }
            VM_METHOD_TYPE_NOTIMPLEMENTED => {
                gen_counter_incr(asm, Counter::send_not_implemented_method);
                return None;
            }
            VM_METHOD_TYPE_MISSING => {
                gen_counter_incr(asm, Counter::send_missing_method);
                return None;
            }
            VM_METHOD_TYPE_REFINED => {
                gen_counter_incr(asm, Counter::send_refined_method);
                return None;
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
fn handle_opt_send_shift_stack(asm: &mut Assembler, argc: i32) {
    asm_comment!(asm, "shift_stack");
    for j in (0..argc).rev() {
        let opnd = asm.stack_opnd(j);
        let opnd2 = asm.stack_opnd(j + 1);
        asm.mov(opnd2, opnd);
    }
    asm.shift_stack(argc as usize);
}

fn gen_opt_send_without_block(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Generate specialized code if possible
    let cd = jit.get_arg(0).as_ptr();
    if let Some(status) = gen_send_general(jit, asm, ocb, cd, None) {
        return Some(status);
    }

    // Otherwise, fallback to dynamic dispatch using the interpreter's implementation of send
    gen_send_dynamic(jit, asm, cd, unsafe { rb_yjit_sendish_sp_pops((*cd).ci) }, |asm| {
        extern "C" {
            fn rb_vm_opt_send_without_block(ec: EcPtr, cfp: CfpPtr, cd: VALUE) -> VALUE;
        }
        asm.ccall(
            rb_vm_opt_send_without_block as *const u8,
            vec![EC, CFP, (cd as usize).into()],
        )
    })
}

fn gen_send(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Generate specialized code if possible
    let cd = jit.get_arg(0).as_ptr();
    let block = jit.get_arg(1).as_optional_ptr().map(|iseq| BlockHandler::BlockISeq(iseq));
    if let Some(status) = gen_send_general(jit, asm, ocb, cd, block) {
        return Some(status);
    }

    // Otherwise, fallback to dynamic dispatch using the interpreter's implementation of send
    let blockiseq = jit.get_arg(1).as_iseq();
    gen_send_dynamic(jit, asm, cd, unsafe { rb_yjit_sendish_sp_pops((*cd).ci) }, |asm| {
        extern "C" {
            fn rb_vm_send(ec: EcPtr, cfp: CfpPtr, cd: VALUE, blockiseq: IseqPtr) -> VALUE;
        }
        asm.ccall(
            rb_vm_send as *const u8,
            vec![EC, CFP, (cd as usize).into(), VALUE(blockiseq as usize).into()],
        )
    })
}

fn gen_invokeblock(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Generate specialized code if possible
    let cd = jit.get_arg(0).as_ptr();
    if let Some(status) = gen_invokeblock_specialized(jit, asm, ocb, cd) {
        return Some(status);
    }

    // Otherwise, fallback to dynamic dispatch using the interpreter's implementation of send
    gen_send_dynamic(jit, asm, cd, unsafe { rb_yjit_invokeblock_sp_pops((*cd).ci) }, |asm| {
        extern "C" {
            fn rb_vm_invokeblock(ec: EcPtr, cfp: CfpPtr, cd: VALUE) -> VALUE;
        }
        asm.ccall(
            rb_vm_invokeblock as *const u8,
            vec![EC, CFP, (cd as usize).into()],
        )
    })
}

fn gen_invokeblock_specialized(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    cd: *const rb_call_data,
) -> Option<CodegenStatus> {
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    // Fallback to dynamic dispatch if this callsite is megamorphic
    if asm.ctx.get_chain_depth() as i32 >= SEND_MAX_DEPTH {
        gen_counter_incr(asm, Counter::invokeblock_megamorphic);
        return None;
    }

    // Get call info
    let ci = unsafe { get_call_data_ci(cd) };
    let argc: i32 = unsafe { vm_ci_argc(ci) }.try_into().unwrap();
    let flags = unsafe { vm_ci_flag(ci) };

    // Get block_handler
    let cfp = jit.get_cfp();
    let lep = unsafe { rb_vm_ep_local_ep(get_cfp_ep(cfp)) };
    let comptime_handler = unsafe { *lep.offset(VM_ENV_DATA_INDEX_SPECVAL.try_into().unwrap()) };

    // Handle each block_handler type
    if comptime_handler.0 == VM_BLOCK_HANDLER_NONE as usize { // no block given
        gen_counter_incr(asm, Counter::invokeblock_none);
        None
    } else if comptime_handler.0 & 0x3 == 0x1 { // VM_BH_ISEQ_BLOCK_P
        asm_comment!(asm, "get local EP");
        let ep_opnd = gen_get_lep(jit, asm);
        let block_handler_opnd = asm.load(
            Opnd::mem(64, ep_opnd, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL)
        );

        asm_comment!(asm, "guard block_handler type");
        let tag_opnd = asm.and(block_handler_opnd, 0x3.into()); // block_handler is a tagged pointer
        asm.cmp(tag_opnd, 0x1.into()); // VM_BH_ISEQ_BLOCK_P
        jit_chain_guard(
            JCC_JNE,
            jit,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            Counter::guard_invokeblock_tag_changed,
        );

        let comptime_captured = unsafe { ((comptime_handler.0 & !0x3) as *const rb_captured_block).as_ref().unwrap() };
        let comptime_iseq = unsafe { *comptime_captured.code.iseq.as_ref() };

        asm_comment!(asm, "guard known ISEQ");
        let captured_opnd = asm.and(block_handler_opnd, Opnd::Imm(!0x3));
        let iseq_opnd = asm.load(Opnd::mem(64, captured_opnd, SIZEOF_VALUE_I32 * 2));
        asm.cmp(iseq_opnd, VALUE::from(comptime_iseq).into());
        jit_chain_guard(
            JCC_JNE,
            jit,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            Counter::guard_invokeblock_iseq_block_changed,
        );

        gen_send_iseq(
            jit,
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
        // We aren't handling CALLER_SETUP_ARG and CALLER_REMOVE_EMPTY_KW_SPLAT yet.
        if flags & VM_CALL_ARGS_SPLAT != 0 {
            gen_counter_incr(asm, Counter::invokeblock_ifunc_args_splat);
            return None;
        }
        if flags & VM_CALL_KW_SPLAT != 0 {
            gen_counter_incr(asm, Counter::invokeblock_ifunc_kw_splat);
            return None;
        }

        asm_comment!(asm, "get local EP");
        let ep_opnd = gen_get_lep(jit, asm);
        let block_handler_opnd = asm.load(
            Opnd::mem(64, ep_opnd, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL)
        );

        asm_comment!(asm, "guard block_handler type");
        let tag_opnd = asm.and(block_handler_opnd, 0x3.into()); // block_handler is a tagged pointer
        asm.cmp(tag_opnd, 0x3.into()); // VM_BH_IFUNC_P
        jit_chain_guard(
            JCC_JNE,
            jit,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            Counter::guard_invokeblock_tag_changed,
        );

        // The cfunc may not be leaf
        jit_prepare_routine_call(jit, asm);

        extern "C" {
            fn rb_vm_yield_with_cfunc(ec: EcPtr, captured: *const rb_captured_block, argc: c_int, argv: *const VALUE) -> VALUE;
        }
        asm_comment!(asm, "call ifunc");
        let captured_opnd = asm.and(block_handler_opnd, Opnd::Imm(!0x3));
        let argv = asm.lea(asm.ctx.sp_opnd((-argc * SIZEOF_VALUE_I32) as isize));
        let ret = asm.ccall(
            rb_vm_yield_with_cfunc as *const u8,
            vec![EC, captured_opnd, argc.into(), argv],
        );

        asm.stack_pop(argc.try_into().unwrap());
        let stack_ret = asm.stack_push(Type::Unknown);
        asm.mov(stack_ret, ret);

        // cfunc calls may corrupt types
        asm.ctx.clear_local_types();

        // Share the successor with other chains
        jump_to_next_insn(jit, asm, ocb);
        Some(EndBlock)
    } else if comptime_handler.symbol_p() {
        gen_counter_incr(asm, Counter::invokeblock_symbol);
        None
    } else { // Proc
        gen_counter_incr(asm, Counter::invokeblock_proc);
        None
    }
}

fn gen_invokesuper(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Generate specialized code if possible
    let cd = jit.get_arg(0).as_ptr();
    if let Some(status) = gen_invokesuper_specialized(jit, asm, ocb, cd) {
        return Some(status);
    }

    // Otherwise, fallback to dynamic dispatch using the interpreter's implementation of send
    let blockiseq = jit.get_arg(1).as_iseq();
    gen_send_dynamic(jit, asm, cd, unsafe { rb_yjit_sendish_sp_pops((*cd).ci) }, |asm| {
        extern "C" {
            fn rb_vm_invokesuper(ec: EcPtr, cfp: CfpPtr, cd: VALUE, blockiseq: IseqPtr) -> VALUE;
        }
        asm.ccall(
            rb_vm_invokesuper as *const u8,
            vec![EC, CFP, (cd as usize).into(), VALUE(blockiseq as usize).into()],
        )
    })
}

fn gen_invokesuper_specialized(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    cd: *const rb_call_data,
) -> Option<CodegenStatus> {
    // Defer compilation so we can specialize on class of receiver
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    // Handle the last two branches of vm_caller_setup_arg_block
    let block = if let Some(iseq) = jit.get_arg(1).as_optional_ptr() {
        BlockHandler::BlockISeq(iseq)
    } else {
        BlockHandler::LEPSpecVal
    };

    // Fallback to dynamic dispatch if this callsite is megamorphic
    if asm.ctx.get_chain_depth() as i32 >= SEND_MAX_DEPTH {
        gen_counter_incr(asm, Counter::invokesuper_megamorphic);
        return None;
    }

    let me = unsafe { rb_vm_frame_method_entry(jit.get_cfp()) };
    if me.is_null() {
        gen_counter_incr(asm, Counter::invokesuper_no_me);
        return None;
    }

    // FIXME: We should track and invalidate this block when this cme is invalidated
    let current_defined_class = unsafe { (*me).defined_class };
    let mid = unsafe { get_def_original_id((*me).def) };

    // vm_search_normal_superclass
    let rbasic_ptr: *const RBasic = current_defined_class.as_ptr();
    if current_defined_class.builtin_type() == RUBY_T_ICLASS
        && unsafe { RB_TYPE_P((*rbasic_ptr).klass, RUBY_T_MODULE) && FL_TEST_RAW((*rbasic_ptr).klass, VALUE(RMODULE_IS_REFINEMENT.as_usize())) != VALUE(0) }
    {
        gen_counter_incr(asm, Counter::invokesuper_refinement);
        return None;
    }
    let comptime_superclass =
        unsafe { rb_class_get_superclass(RCLASS_ORIGIN(current_defined_class)) };

    let ci = unsafe { get_call_data_ci(cd) };
    let argc: i32 = unsafe { vm_ci_argc(ci) }.try_into().unwrap();

    let ci_flags = unsafe { vm_ci_flag(ci) };

    // Don't JIT calls that aren't simple
    // Note, not using VM_CALL_ARGS_SIMPLE because sometimes we pass a block.

    if ci_flags & VM_CALL_KWARG != 0 {
        gen_counter_incr(asm, Counter::invokesuper_kwarg);
        return None;
    }
    if ci_flags & VM_CALL_KW_SPLAT != 0 {
        gen_counter_incr(asm, Counter::invokesuper_kw_splat);
        return None;
    }

    // Ensure we haven't rebound this method onto an incompatible class.
    // In the interpreter we try to avoid making this check by performing some
    // cheaper calculations first, but since we specialize on the method entry
    // and so only have to do this once at compile time this is fine to always
    // check and side exit.
    let comptime_recv = jit.peek_at_stack(&asm.ctx, argc as isize);
    if unsafe { rb_obj_is_kind_of(comptime_recv, current_defined_class) } == VALUE(0) {
        gen_counter_incr(asm, Counter::invokesuper_defined_class_mismatch);
        return None;
    }

    // Don't compile `super` on objects with singleton class to avoid retaining the receiver.
    if VALUE(0) != unsafe { FL_TEST(comptime_recv.class_of(), VALUE(RUBY_FL_SINGLETON as usize)) } {
        gen_counter_incr(asm, Counter::invokesuper_singleton_class);
        return None;
    }

    // Do method lookup
    let cme = unsafe { rb_callable_method_entry(comptime_superclass, mid) };
    if cme.is_null() {
        gen_counter_incr(asm, Counter::invokesuper_no_cme);
        return None;
    }

    // Check that we'll be able to write this method dispatch before generating checks
    let cme_def_type = unsafe { get_cme_def_type(cme) };
    if cme_def_type != VM_METHOD_TYPE_ISEQ && cme_def_type != VM_METHOD_TYPE_CFUNC {
        // others unimplemented
        gen_counter_incr(asm, Counter::invokesuper_not_iseq_or_cfunc);
        return None;
    }

    asm_comment!(asm, "guard known me");
    let lep_opnd = gen_get_lep(jit, asm);
    let ep_me_opnd = Opnd::mem(
        64,
        lep_opnd,
        SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_ME_CREF,
    );

    let me_as_value = VALUE(me as usize);
    asm.cmp(ep_me_opnd, me_as_value.into());
    jit_chain_guard(
        JCC_JNE,
        jit,
        asm,
        ocb,
        SEND_MAX_DEPTH,
        Counter::guard_invokesuper_me_changed,
    );

    // We need to assume that both our current method entry and the super
    // method entry we invoke remain stable
    jit.assume_method_lookup_stable(asm, ocb, me);
    jit.assume_method_lookup_stable(asm, ocb, cme);

    // Method calls may corrupt types
    asm.ctx.clear_local_types();

    match cme_def_type {
        VM_METHOD_TYPE_ISEQ => {
            let iseq = unsafe { get_def_iseq_ptr((*cme).def) };
            let frame_type = VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL;
            gen_send_iseq(jit, asm, ocb, iseq, ci, frame_type, None, cme, Some(block), ci_flags, argc, None)
        }
        VM_METHOD_TYPE_CFUNC => {
            gen_send_cfunc(jit, asm, ocb, ci, cme, Some(block), ptr::null(), ci_flags, argc)
        }
        _ => unreachable!(),
    }
}

fn gen_leave(
    _jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Only the return value should be on the stack
    assert_eq!(1, asm.ctx.get_stack_size(), "leave instruction expects stack size 1, but was: {}", asm.ctx.get_stack_size());

    // Check for interrupts
    gen_check_ints(asm, Counter::leave_se_interrupt);

    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    asm_comment!(asm, "pop stack frame");
    let incr_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, incr_cfp);
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // Load the return value
    let retval_opnd = asm.stack_pop(1);

    // Move the return value into the C return register
    asm.mov(C_RET_OPND, retval_opnd);

    // Jump to the JIT return address on the frame that was just popped.
    // There are a few possible jump targets:
    //   - gen_leave_exit() and gen_leave_exception(), for C callers
    //   - Return context set up by gen_send_iseq()
    // We don't write the return value to stack memory like the interpreter here.
    // Each jump target do it as necessary.
    let offset_to_jit_return =
        -(RUBY_SIZEOF_CONTROL_FRAME as i32) + RUBY_OFFSET_CFP_JIT_RETURN;
    asm.jmp_opnd(Opnd::mem(64, CFP, offset_to_jit_return));

    Some(EndBlock)
}

fn gen_getglobal(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let gid = jit.get_arg(0).as_usize();

    // Save the PC and SP because we might make a Ruby call for warning
    jit_prepare_routine_call(jit, asm);

    let val_opnd = asm.ccall(
        rb_gvar_get as *const u8,
        vec![ gid.into() ]
    );

    let top = asm.stack_push(Type::Unknown);
    asm.mov(top, val_opnd);

    Some(KeepCompiling)
}

fn gen_setglobal(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let gid = jit.get_arg(0).as_usize();

    // Save the PC and SP because we might make a Ruby call for
    // Kernel#set_trace_var
    jit_prepare_routine_call(jit, asm);

    let val = asm.stack_opnd(0);
    asm.ccall(
        rb_gvar_set as *const u8,
        vec![
            gid.into(),
            val,
        ],
    );
    asm.stack_pop(1); // Keep it during ccall for GC

    Some(KeepCompiling)
}

fn gen_anytostring(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Save the PC and SP since we might call #to_s
    jit_prepare_routine_call(jit, asm);

    let str = asm.stack_opnd(0);
    let val = asm.stack_opnd(1);

    let val = asm.ccall(rb_obj_as_string_result as *const u8, vec![str, val]);
    asm.stack_pop(2); // Keep them during ccall for GC

    // Push the return value
    let stack_ret = asm.stack_push(Type::TString);
    asm.mov(stack_ret, val);

    Some(KeepCompiling)
}

fn gen_objtostring(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    let recv = asm.stack_opnd(0);
    let comptime_recv = jit.peek_at_stack(&asm.ctx, 0);

    if unsafe { RB_TYPE_P(comptime_recv, RUBY_T_STRING) } {
        jit_guard_known_klass(
            jit,
            asm,
            ocb,
            comptime_recv.class_of(),
            recv,
            recv.into(),
            comptime_recv,
            SEND_MAX_DEPTH,
            Counter::objtostring_not_string,
        );

        // No work needed. The string value is already on the top of the stack.
        Some(KeepCompiling)
    } else {
        let cd = jit.get_arg(0).as_ptr();
        gen_send_general(jit, asm, ocb, cd, None)
    }
}

fn gen_intern(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // Save the PC and SP because we might allocate
    jit_prepare_routine_call(jit, asm);

    let str = asm.stack_opnd(0);
    let sym = asm.ccall(rb_str_intern as *const u8, vec![str]);
    asm.stack_pop(1); // Keep it during ccall for GC

    // Push the return value
    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, sym);

    Some(KeepCompiling)
}

fn gen_toregexp(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let opt = jit.get_arg(0).as_i64();
    let cnt = jit.get_arg(1).as_usize();

    // Save the PC and SP because this allocates an object and could
    // raise an exception.
    jit_prepare_routine_call(jit, asm);

    let values_ptr = asm.lea(asm.ctx.sp_opnd(-((SIZEOF_VALUE as isize) * (cnt as isize))));

    let ary = asm.ccall(
        rb_ary_tmp_new_from_values as *const u8,
        vec![
            Opnd::Imm(0),
            cnt.into(),
            values_ptr,
        ]
    );
    asm.stack_pop(cnt); // Let ccall spill them

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
    let stack_ret = asm.stack_push(Type::UnknownHeap);
    asm.mov(stack_ret, val);

    // Clear the temp array.
    asm.ccall(rb_ary_clear as *const u8, vec![ary]);

    Some(KeepCompiling)
}

fn gen_getspecial(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // This takes two arguments, key and type
    // key is only used when type == 0
    // A non-zero type determines which type of backref to fetch
    //rb_num_t key = jit.jit_get_arg(0);
    let rtype = jit.get_arg(1).as_u64();

    if rtype == 0 {
        // not yet implemented
        return None;
    } else if rtype & 0x01 != 0 {
        // Fetch a "special" backref based on a char encoded by shifting by 1

        // Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, asm);

        // call rb_backref_get()
        asm_comment!(asm, "rb_backref_get");
        let backref = asm.ccall(rb_backref_get as *const u8, vec![]);

        let rt_u8: u8 = (rtype >> 1).try_into().unwrap();
        let val = match rt_u8.into() {
            '&' => {
                asm_comment!(asm, "rb_reg_last_match");
                asm.ccall(rb_reg_last_match as *const u8, vec![backref])
            }
            '`' => {
                asm_comment!(asm, "rb_reg_match_pre");
                asm.ccall(rb_reg_match_pre as *const u8, vec![backref])
            }
            '\'' => {
                asm_comment!(asm, "rb_reg_match_post");
                asm.ccall(rb_reg_match_post as *const u8, vec![backref])
            }
            '+' => {
                asm_comment!(asm, "rb_reg_match_last");
                asm.ccall(rb_reg_match_last as *const u8, vec![backref])
            }
            _ => panic!("invalid back-ref"),
        };

        let stack_ret = asm.stack_push(Type::Unknown);
        asm.mov(stack_ret, val);

        Some(KeepCompiling)
    } else {
        // Fetch the N-th match from the last backref based on type shifted by 1

        // Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, asm);

        // call rb_backref_get()
        asm_comment!(asm, "rb_backref_get");
        let backref = asm.ccall(rb_backref_get as *const u8, vec![]);

        // rb_reg_nth_match((int)(type >> 1), backref);
        asm_comment!(asm, "rb_reg_nth_match");
        let val = asm.ccall(
            rb_reg_nth_match as *const u8,
            vec![
                Opnd::Imm((rtype >> 1).try_into().unwrap()),
                backref,
            ]
        );

        let stack_ret = asm.stack_push(Type::Unknown);
        asm.mov(stack_ret, val);

        Some(KeepCompiling)
    }
}

fn gen_getclassvariable(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // rb_vm_getclassvariable can raise exceptions.
    jit_prepare_routine_call(jit, asm);

    let val_opnd = asm.ccall(
        rb_vm_getclassvariable as *const u8,
        vec![
            Opnd::mem(64, CFP, RUBY_OFFSET_CFP_ISEQ),
            CFP,
            Opnd::UImm(jit.get_arg(0).as_u64()),
            Opnd::UImm(jit.get_arg(1).as_u64()),
        ],
    );

    let top = asm.stack_push(Type::Unknown);
    asm.mov(top, val_opnd);

    Some(KeepCompiling)
}

fn gen_setclassvariable(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // rb_vm_setclassvariable can raise exceptions.
    jit_prepare_routine_call(jit, asm);

    let val = asm.stack_opnd(0);
    asm.ccall(
        rb_vm_setclassvariable as *const u8,
        vec![
            Opnd::mem(64, CFP, RUBY_OFFSET_CFP_ISEQ),
            CFP,
            Opnd::UImm(jit.get_arg(0).as_u64()),
            val,
            Opnd::UImm(jit.get_arg(1).as_u64()),
        ],
    );
    asm.stack_pop(1); // Keep it during ccall for GC

    Some(KeepCompiling)
}

fn gen_getconstant(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {

    let id = jit.get_arg(0).as_usize();

    // vm_get_ev_const can raise exceptions.
    jit_prepare_routine_call(jit, asm);

    let allow_nil_opnd = asm.stack_opnd(0);
    let klass_opnd = asm.stack_opnd(1);

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
    asm.stack_pop(2); // Keep them during ccall for GC

    let top = asm.stack_push(Type::Unknown);
    asm.mov(top, val_opnd);

    Some(KeepCompiling)
}

fn gen_opt_getconstant_path(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let const_cache_as_value = jit.get_arg(0);
    let ic: *const iseq_inline_constant_cache = const_cache_as_value.as_ptr();
    let idlist: *const ID = unsafe { (*ic).segments };

    // Make sure there is an exit for this block as the interpreter might want
    // to invalidate this block from yjit_constant_ic_update().
    jit_ensure_block_entry_exit(jit, asm, ocb)?;

    // See vm_ic_hit_p(). The same conditions are checked in yjit_constant_ic_update().
    // If a cache is not filled, fallback to the general C call.
    let ice = unsafe { (*ic).entry };
    if ice.is_null() {
        // Prepare for const_missing
        jit_prepare_routine_call(jit, asm);

        // If this does not trigger const_missing, vm_ic_update will invalidate this block.
        extern "C" {
            fn rb_vm_opt_getconstant_path(ec: EcPtr, cfp: CfpPtr, ic: *const u8) -> VALUE;
        }
        let val = asm.ccall(
            rb_vm_opt_getconstant_path as *const u8,
            vec![EC, CFP, Opnd::const_ptr(ic as *const u8)],
        );

        let stack_top = asm.stack_push(Type::Unknown);
        asm.store(stack_top, val);

        jump_to_next_insn(jit, asm, ocb);
        return Some(EndBlock);
    }

    if !unsafe { (*ice).ic_cref }.is_null() {
        // Cache is keyed on a certain lexical scope. Use the interpreter's cache.
        let inline_cache = asm.load(Opnd::const_ptr(ic as *const u8));

        // Call function to verify the cache. It doesn't allocate or call methods.
        let ret_val = asm.ccall(
            rb_vm_ic_hit_p as *const u8,
            vec![inline_cache, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP)]
        );

        // Check the result. SysV only specifies one byte for _Bool return values,
        // so it's important we only check one bit to ignore the higher bits in the register.
        asm.test(ret_val, 1.into());
        asm.jz(Target::side_exit(Counter::opt_getconstant_path_ic_miss));

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
        let stack_top = asm.stack_push(Type::Unknown);
        asm.store(stack_top, ic_entry_val);
    } else {
        // Optimize for single ractor mode.
        if !assume_single_ractor_mode(jit, asm, ocb) {
            gen_counter_incr(asm, Counter::opt_getconstant_path_multi_ractor);
            return None;
        }

        // Invalidate output code on any constant writes associated with
        // constants referenced within the current block.
        jit.assume_stable_constant_names(asm, ocb, idlist);

        jit_putobject(asm, unsafe { (*ice).value });
    }

    jump_to_next_insn(jit, asm, ocb);
    Some(EndBlock)
}

// Push the explicit block parameter onto the temporary stack. Part of the
// interpreter's scheme for avoiding Proc allocations when delegating
// explicit block parameters.
fn gen_getblockparamproxy(
    jit: &mut JITState,
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    if !jit.at_current_insn() {
        defer_compilation(jit, asm, ocb);
        return Some(EndBlock);
    }

    // EP level
    let level = jit.get_arg(1).as_u32();

    // Peek at the block handler so we can check whether it's nil
    let comptime_handler = jit.peek_at_block_handler(level);

    // Filter for the 4 cases we currently handle
    if !(comptime_handler.as_u64() == 0 ||              // no block given
            comptime_handler.as_u64() & 0x3 == 0x1 ||   // iseq block (no associated GC managed object)
            comptime_handler.as_u64() & 0x3 == 0x3 ||   // ifunc block (no associated GC managed object)
            unsafe { rb_obj_is_proc(comptime_handler) }.test() // block is a Proc
        ) {
        // Missing the symbol case, where we basically need to call Symbol#to_proc at runtime
        gen_counter_incr(asm, Counter::gbpp_unsupported_type);
        return None;
    }

    // Load environment pointer EP from CFP
    let ep_opnd = gen_get_ep(asm, level);

    // Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
    let flag_check = Opnd::mem(
        64,
        ep_opnd,
        SIZEOF_VALUE_I32 * (VM_ENV_DATA_INDEX_FLAGS as i32),
    );
    asm.test(flag_check, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into());
    asm.jnz(Target::side_exit(Counter::gbpp_block_param_modified));

    // Load the block handler for the current frame
    // note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
    let block_handler = asm.load(
        Opnd::mem(64, ep_opnd, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL)
    );

    // Use block handler sample to guide specialization...
    // NOTE: we use jit_chain_guard() in this decision tree, and since
    // there are only a few cases, it should never reach the depth limit use
    // the exit counter we pass to it.
    //
    // No block given
    if comptime_handler.as_u64() == 0 {
        // Bail if there is a block handler
        asm.cmp(block_handler, Opnd::UImm(0));

        jit_chain_guard(
            JCC_JNZ,
            jit,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            Counter::gbpp_block_handler_not_none,
        );

        jit_putobject(asm, Qnil);
    } else if comptime_handler.as_u64() & 0x1 == 0x1 {
        // This handles two cases which are nearly identical
        // Block handler is a tagged pointer. Look at the tag.
        //   VM_BH_ISEQ_BLOCK_P(): block_handler & 0x03 == 0x01
        //   VM_BH_IFUNC_P():      block_handler & 0x03 == 0x03
        // So to check for either of those cases we can use: val & 0x1 == 0x1
        const _: () = assert!(RUBY_SYMBOL_FLAG & 1 == 0, "guard below rejects symbol block handlers");
        // Procs are aligned heap pointers so testing the bit rejects them too.

        asm.test(block_handler, 0x1.into());
        jit_chain_guard(
            JCC_JZ,
            jit,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            Counter::gbpp_block_handler_not_iseq,
        );

        // Push rb_block_param_proxy. It's a root, so no need to use jit_mov_gc_ptr.
        assert!(!unsafe { rb_block_param_proxy }.special_const_p());

        let top = asm.stack_push(Type::BlockParamProxy);
        asm.mov(top, Opnd::const_ptr(unsafe { rb_block_param_proxy }.as_ptr()));
    } else if unsafe { rb_obj_is_proc(comptime_handler) }.test() {
        // The block parameter is a Proc
        c_callable! {
            // We can't hold values across C calls due to a backend limitation,
            // so we'll use this thin wrapper around rb_obj_is_proc().
            fn is_proc(object: VALUE) -> VALUE {
                if unsafe { rb_obj_is_proc(object) }.test() {
                    // VM_BH_TO_PROC() is the identify function.
                    object
                } else {
                    Qfalse
                }
            }
        }

        // Simple predicate, no need to jit_prepare_routine_call()
        let proc_or_false = asm.ccall(is_proc as _, vec![block_handler]);

        // Guard for proc
        asm.cmp(proc_or_false, Qfalse.into());
        jit_chain_guard(
            JCC_JE,
            jit,
            asm,
            ocb,
            SEND_MAX_DEPTH,
            Counter::gbpp_block_handler_not_proc,
        );

        let top = asm.stack_push(Type::Unknown);
        asm.mov(top, proc_or_false);
    } else {
        unreachable!("absurd given initial filtering");
    }

    jump_to_next_insn(jit, asm, ocb);

    Some(EndBlock)
}

fn gen_getblockparam(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    // EP level
    let level = jit.get_arg(1).as_u32();

    // Save the PC and SP because we might allocate
    jit_prepare_routine_call(jit, asm);
    asm.spill_temps(); // For ccall. Unconditionally spill them for RegTemps consistency.

    // A mirror of the interpreter code. Checking for the case
    // where it's pushing rb_block_param_proxy.

    // Load environment pointer EP from CFP
    let ep_opnd = gen_get_ep(asm, level);

    // Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
    let flag_check = Opnd::mem(64, ep_opnd, SIZEOF_VALUE_I32 * (VM_ENV_DATA_INDEX_FLAGS as i32));
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
        SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_FLAGS as i32,
    );
    asm.test(flags_opnd, VM_ENV_FLAG_WB_REQUIRED.into());

    // if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
    asm.jnz(Target::side_exit(Counter::gbp_wb_required));

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
                SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL,
            ),
        ]
    );

    // Load environment pointer EP from CFP (again)
    let ep_opnd = gen_get_ep(asm, level);

    // Write the value at the environment pointer
    let idx = jit.get_arg(0).as_i32();
    let offs = -(SIZEOF_VALUE_I32 * idx);
    asm.mov(Opnd::mem(64, ep_opnd, offs), proc);

    // Set the frame modified flag
    let flag_check = Opnd::mem(64, ep_opnd, SIZEOF_VALUE_I32 * (VM_ENV_DATA_INDEX_FLAGS as i32));
    let modified_flag = asm.or(flag_check, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into());
    asm.store(flag_check, modified_flag);

    asm.write_label(frame_flag_modified);

    // Push the proc on the stack
    let stack_ret = asm.stack_push(Type::Unknown);
    let ep_opnd = gen_get_ep(asm, level);
    asm.mov(stack_ret, Opnd::mem(64, ep_opnd, offs));

    Some(KeepCompiling)
}

fn gen_invokebuiltin(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let bf: *const rb_builtin_function = jit.get_arg(0).as_ptr();
    let bf_argc: usize = unsafe { (*bf).argc }.try_into().expect("non negative argc");

    // ec, self, and arguments
    if bf_argc + 2 > C_ARG_OPNDS.len() {
        return None;
    }

    // If the calls don't allocate, do they need up to date PC, SP?
    jit_prepare_routine_call(jit, asm);

    // Call the builtin func (ec, recv, arg1, arg2, ...)
    let mut args = vec![EC, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF)];

    // Copy arguments from locals
    for i in 0..bf_argc {
        let stack_opnd = asm.stack_opnd((bf_argc - i - 1) as i32);
        args.push(stack_opnd);
    }

    let val = asm.ccall(unsafe { (*bf).func_ptr } as *const u8, args);

    // Push the return value
    asm.stack_pop(bf_argc);
    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, val);

    Some(KeepCompiling)
}

// opt_invokebuiltin_delegate calls a builtin function, like
// invokebuiltin does, but instead of taking arguments from the top of the
// stack uses the argument locals (and self) from the current method.
fn gen_opt_invokebuiltin_delegate(
    jit: &mut JITState,
    asm: &mut Assembler,
    _ocb: &mut OutlinedCb,
) -> Option<CodegenStatus> {
    let bf: *const rb_builtin_function = jit.get_arg(0).as_ptr();
    let bf_argc = unsafe { (*bf).argc };
    let start_index = jit.get_arg(1).as_i32();

    // ec, self, and arguments
    if bf_argc + 2 > (C_ARG_OPNDS.len() as i32) {
        return None;
    }

    // If the calls don't allocate, do they need up to date PC, SP?
    jit_prepare_routine_call(jit, asm);

    // Call the builtin func (ec, recv, arg1, arg2, ...)
    let mut args = vec![EC, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF)];

    // Copy arguments from locals
    if bf_argc > 0 {
        // Load environment pointer EP from CFP
        let ep = asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP));

        for i in 0..bf_argc {
            let table_size = unsafe { get_iseq_body_local_table_size(jit.iseq) };
            let offs: i32 = -(table_size as i32) - (VM_ENV_DATA_SIZE as i32) + 1 + start_index + i;
            let local_opnd = Opnd::mem(64, ep, offs * SIZEOF_VALUE_I32);
            args.push(local_opnd);
        }
    }
    let val = asm.ccall(unsafe { (*bf).func_ptr } as *const u8, args);

    // Push the return value
    let stack_ret = asm.stack_push(Type::Unknown);
    asm.mov(stack_ret, val);

    Some(KeepCompiling)
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
        YARVINSN_opt_newarray_send => Some(gen_opt_newarray_send),
        YARVINSN_splatarray => Some(gen_splatarray),
        YARVINSN_splatkw => Some(gen_splatkw),
        YARVINSN_concatarray => Some(gen_concatarray),
        YARVINSN_newrange => Some(gen_newrange),
        YARVINSN_putstring => Some(gen_putstring),
        YARVINSN_expandarray => Some(gen_expandarray),
        YARVINSN_defined => Some(gen_defined),
        YARVINSN_definedivar => Some(gen_definedivar),
        YARVINSN_checkmatch => Some(gen_checkmatch),
        YARVINSN_checkkeyword => Some(gen_checkkeyword),
        YARVINSN_concatstrings => Some(gen_concatstrings),
        YARVINSN_getinstancevariable => Some(gen_getinstancevariable),
        YARVINSN_setinstancevariable => Some(gen_setinstancevariable),

        YARVINSN_opt_eq => Some(gen_opt_eq),
        YARVINSN_opt_neq => Some(gen_opt_neq),
        YARVINSN_opt_aref => Some(gen_opt_aref),
        YARVINSN_opt_aset => Some(gen_opt_aset),
        YARVINSN_opt_aref_with => Some(gen_opt_aref_with),
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
        YARVINSN_throw => Some(gen_throw),
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
    asm: &mut Assembler,
    ocb: &mut OutlinedCb,
    ci: *const rb_callinfo,
    cme: *const rb_callable_method_entry_t,
    block: Option<BlockHandler>,
    argc: i32,
    known_recv_class: *const VALUE,
) -> bool;

/// Methods for generating code for hardcoded (usually C) methods
static mut METHOD_CODEGEN_TABLE: Option<HashMap<usize, MethodGenFn>> = None;

/// Register codegen functions for some Ruby core methods
pub fn yjit_reg_method_codegen_fns() {
    unsafe {
        assert!(METHOD_CODEGEN_TABLE.is_none());
        METHOD_CODEGEN_TABLE = Some(HashMap::default());

        // Specialization for C methods. See yjit_reg_method() for details.
        yjit_reg_method(rb_cBasicObject, "!", jit_rb_obj_not);

        yjit_reg_method(rb_cNilClass, "nil?", jit_rb_true);
        yjit_reg_method(rb_mKernel, "nil?", jit_rb_false);
        yjit_reg_method(rb_mKernel, "is_a?", jit_rb_kernel_is_a);
        yjit_reg_method(rb_mKernel, "kind_of?", jit_rb_kernel_is_a);
        yjit_reg_method(rb_mKernel, "instance_of?", jit_rb_kernel_instance_of);

        yjit_reg_method(rb_cBasicObject, "==", jit_rb_obj_equal);
        yjit_reg_method(rb_cBasicObject, "equal?", jit_rb_obj_equal);
        yjit_reg_method(rb_cBasicObject, "!=", jit_rb_obj_not_equal);
        yjit_reg_method(rb_mKernel, "eql?", jit_rb_obj_equal);
        yjit_reg_method(rb_cModule, "==", jit_rb_obj_equal);
        yjit_reg_method(rb_cModule, "===", jit_rb_mod_eqq);
        yjit_reg_method(rb_cSymbol, "==", jit_rb_obj_equal);
        yjit_reg_method(rb_cSymbol, "===", jit_rb_obj_equal);
        yjit_reg_method(rb_cInteger, "==", jit_rb_int_equal);
        yjit_reg_method(rb_cInteger, "===", jit_rb_int_equal);

        yjit_reg_method(rb_cInteger, "/", jit_rb_int_div);
        yjit_reg_method(rb_cInteger, "<<", jit_rb_int_lshift);
        yjit_reg_method(rb_cInteger, "[]", jit_rb_int_aref);

        yjit_reg_method(rb_cString, "empty?", jit_rb_str_empty_p);
        yjit_reg_method(rb_cString, "to_s", jit_rb_str_to_s);
        yjit_reg_method(rb_cString, "to_str", jit_rb_str_to_s);
        yjit_reg_method(rb_cString, "bytesize", jit_rb_str_bytesize);
        yjit_reg_method(rb_cString, "getbyte", jit_rb_str_getbyte);
        yjit_reg_method(rb_cString, "<<", jit_rb_str_concat);
        yjit_reg_method(rb_cString, "+@", jit_rb_str_uplus);

        yjit_reg_method(rb_cArray, "empty?", jit_rb_ary_empty_p);
        yjit_reg_method(rb_cArray, "length", jit_rb_ary_length);
        yjit_reg_method(rb_cArray, "size", jit_rb_ary_length);
        yjit_reg_method(rb_cArray, "<<", jit_rb_ary_push);

        yjit_reg_method(rb_mKernel, "respond_to?", jit_obj_respond_to);
        yjit_reg_method(rb_mKernel, "block_given?", jit_rb_f_block_given_p);

        yjit_reg_method(rb_singleton_class(rb_cThread), "current", jit_thread_s_current);
    }
}

// Register a specialized codegen function for a particular method. Note that
// the if the function returns true, the code it generates runs without a
// control frame and without interrupt checks. To avoid creating observable
// behavior changes, the codegen function should only target simple code paths
// that do not allocate and do not make method calls.
fn yjit_reg_method(klass: VALUE, mid_str: &str, gen_fn: MethodGenFn) {
    let id_string = std::ffi::CString::new(mid_str).expect("couldn't convert to CString!");
    let mid = unsafe { rb_intern(id_string.as_ptr()) };
    let me = unsafe { rb_method_entry_at(klass, mid) };

    if me.is_null() {
        panic!("undefined optimized method!: {mid_str}");
    }

    // For now, only cfuncs are supported
    //RUBY_ASSERT(me && me->def);
    //RUBY_ASSERT(me->def->type == VM_METHOD_TYPE_CFUNC);

    let method_serial = unsafe {
        let def = (*me).def;
        get_def_method_serial(def)
    };

    unsafe { METHOD_CODEGEN_TABLE.as_mut().unwrap().insert(method_serial, gen_fn); }
}

/// Global state needed for code generation
pub struct CodegenGlobals {
    /// Inline code block (fast path)
    inline_cb: CodeBlock,

    /// Outlined code block (slow path)
    outlined_cb: OutlinedCb,

    /// Code for exiting back to the interpreter from the leave instruction
    leave_exit_code: CodePtr,

    /// Code for exiting back to the interpreter after handling an exception
    leave_exception_code: CodePtr,

    // For exiting from YJIT frame from branch_stub_hit().
    // Filled by gen_stub_exit().
    stub_exit_code: CodePtr,

    // For servicing branch stubs
    branch_stub_hit_trampoline: CodePtr,

    // For servicing entry stubs
    entry_stub_hit_trampoline: CodePtr,

    // Code for full logic of returning from C method and exiting to the interpreter
    outline_full_cfunc_return_pos: CodePtr,

    /// For implementing global code invalidation
    global_inval_patches: Vec<CodepagePatch>,

    /// Page indexes for outlined code that are not associated to any ISEQ.
    ocb_pages: Vec<usize>,
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
        let leave_exit_code = gen_leave_exit(&mut ocb).unwrap();
        let leave_exception_code = gen_leave_exception(&mut ocb).unwrap();

        let stub_exit_code = gen_stub_exit(&mut ocb).unwrap();

        let branch_stub_hit_trampoline = gen_branch_stub_hit_trampoline(&mut ocb).unwrap();
        let entry_stub_hit_trampoline = gen_entry_stub_hit_trampoline(&mut ocb).unwrap();

        // Generate full exit code for C func
        let cfunc_exit_code = gen_full_cfunc_return(&mut ocb).unwrap();

        let ocb_end_addr = ocb.unwrap().get_write_ptr();
        let ocb_pages = ocb.unwrap().addrs_to_pages(ocb_start_addr, ocb_end_addr);

        // Mark all code memory as executable
        cb.mark_all_executable();
        ocb.unwrap().mark_all_executable();

        let codegen_globals = CodegenGlobals {
            inline_cb: cb,
            outlined_cb: ocb,
            leave_exit_code,
            leave_exception_code,
            stub_exit_code,
            outline_full_cfunc_return_pos: cfunc_exit_code,
            branch_stub_hit_trampoline,
            entry_stub_hit_trampoline,
            global_inval_patches: Vec::new(),
            ocb_pages,
        };

        // Initialize the codegen globals instance
        unsafe {
            CODEGEN_GLOBALS = Some(codegen_globals);
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

    pub fn get_leave_exception_code() -> CodePtr {
        CodegenGlobals::get_instance().leave_exception_code
    }

    pub fn get_stub_exit_code() -> CodePtr {
        CodegenGlobals::get_instance().stub_exit_code
    }

    pub fn push_global_inval_patch(inline_pos: CodePtr, outlined_pos: CodePtr, cb: &CodeBlock) {
        if let Some(last_patch) = CodegenGlobals::get_instance().global_inval_patches.last() {
            let patch_offset = inline_pos.as_offset() - last_patch.inline_patch_pos.as_offset();
            assert!(
                patch_offset < 0 || cb.jmp_ptr_bytes() as i64 <= patch_offset,
                "patches should not overlap (patch_offset: {patch_offset})",
            );
        }

        let patch = CodepagePatch {
            inline_patch_pos: inline_pos,
            outlined_target_pos: outlined_pos,
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

    pub fn get_outline_full_cfunc_return_pos() -> CodePtr {
        CodegenGlobals::get_instance().outline_full_cfunc_return_pos
    }

    pub fn get_branch_stub_hit_trampoline() -> CodePtr {
        CodegenGlobals::get_instance().branch_stub_hit_trampoline
    }

    pub fn get_entry_stub_hit_trampoline() -> CodePtr {
        CodegenGlobals::get_instance().entry_stub_hit_trampoline
    }

    pub fn get_ocb_pages() -> &'static Vec<usize> {
        &CodegenGlobals::get_instance().ocb_pages
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_codegen() -> (JITState, Context, Assembler, CodeBlock, OutlinedCb) {
        let cb = CodeBlock::new_dummy(256 * 1024);

        return (
            JITState::new(
                BlockId { iseq: std::ptr::null(), idx: 0 },
                Context::default(),
                cb.get_write_ptr(),
                ptr::null(), // No execution context in tests. No peeking!
            ),
            Context::default(),
            Assembler::new(),
            cb,
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
        let (_, _ctx, mut asm, mut cb, _) = setup_codegen();
        gen_exit(0 as *mut VALUE, &mut asm);
        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_get_side_exit() {
        let (_jit, ctx, mut asm, _, mut ocb) = setup_codegen();
        let side_exit_context = SideExitContext::new(0 as _, ctx);
        asm.get_side_exit(&side_exit_context, None, &mut ocb);
        assert!(ocb.unwrap().get_write_pos() > 0);
    }

    #[test]
    fn test_gen_check_ints() {
        let (_jit, _ctx, mut asm, _cb, _ocb) = setup_codegen();
        asm.set_side_exit_context(0 as _, 0);
        gen_check_ints(&mut asm, Counter::guard_send_interrupted);
    }

    #[test]
    fn test_gen_nop() {
        let (mut jit, context, mut asm, mut cb, mut ocb) = setup_codegen();
        let status = gen_nop(&mut jit, &mut asm, &mut ocb);
        asm.compile(&mut cb, None).unwrap();

        assert_eq!(status, Some(KeepCompiling));
        assert_eq!(context.diff(&Context::default()), TypeDiff::Compatible(0));
        assert_eq!(cb.get_write_pos(), 0);
    }

    #[test]
    fn test_gen_pop() {
        let (mut jit, _, mut asm, _cb, mut ocb) = setup_codegen();
        let context = Context::default();
        asm.stack_push(Type::Fixnum);
        let status = gen_pop(&mut jit, &mut asm, &mut ocb);

        assert_eq!(status, Some(KeepCompiling));
        let mut default = Context::default();
        default.set_reg_temps(context.get_reg_temps());
        assert_eq!(context.diff(&default), TypeDiff::Compatible(0));
    }

    #[test]
    fn test_gen_dup() {
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();
        asm.stack_push(Type::Fixnum);
        let status = gen_dup(&mut jit, &mut asm, &mut ocb);

        assert_eq!(status, Some(KeepCompiling));

        // Did we duplicate the type information for the Fixnum type?
        assert_eq!(Type::Fixnum, asm.ctx.get_opnd_type(StackOpnd(0)));
        assert_eq!(Type::Fixnum, asm.ctx.get_opnd_type(StackOpnd(1)));

        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_dupn() {
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();
        asm.stack_push(Type::Fixnum);
        asm.stack_push(Type::Flonum);

        let mut value_array: [u64; 2] = [0, 2]; // We only compile for n == 2
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_dupn(&mut jit, &mut asm, &mut ocb);

        assert_eq!(status, Some(KeepCompiling));

        assert_eq!(Type::Fixnum, asm.ctx.get_opnd_type(StackOpnd(3)));
        assert_eq!(Type::Flonum, asm.ctx.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::Fixnum, asm.ctx.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::Flonum, asm.ctx.get_opnd_type(StackOpnd(0)));

        // TODO: this is writing zero bytes on x86. Why?
        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_swap() {
        let (mut jit, _context, mut asm, _cb, mut ocb) = setup_codegen();
        asm.stack_push(Type::Fixnum);
        asm.stack_push(Type::Flonum);

        let status = gen_swap(&mut jit, &mut asm, &mut ocb);

        let tmp_type_top = asm.ctx.get_opnd_type(StackOpnd(0));
        let tmp_type_next = asm.ctx.get_opnd_type(StackOpnd(1));

        assert_eq!(status, Some(KeepCompiling));
        assert_eq!(tmp_type_top, Type::Fixnum);
        assert_eq!(tmp_type_next, Type::Flonum);
    }

    #[test]
    fn test_putnil() {
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();
        let status = gen_putnil(&mut jit, &mut asm, &mut ocb);

        let tmp_type_top = asm.ctx.get_opnd_type(StackOpnd(0));

        assert_eq!(status, Some(KeepCompiling));
        assert_eq!(tmp_type_top, Type::Nil);
        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_putobject_qtrue() {
        // Test gen_putobject with Qtrue
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();

        let mut value_array: [u64; 2] = [0, Qtrue.into()];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_putobject(&mut jit, &mut asm, &mut ocb);

        let tmp_type_top = asm.ctx.get_opnd_type(StackOpnd(0));

        assert_eq!(status, Some(KeepCompiling));
        assert_eq!(tmp_type_top, Type::True);
        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_putobject_fixnum() {
        // Test gen_putobject with a Fixnum to test another conditional branch
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();

        // The Fixnum 7 is encoded as 7 * 2 + 1, or 15
        let mut value_array: [u64; 2] = [0, 15];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_putobject(&mut jit, &mut asm, &mut ocb);

        let tmp_type_top = asm.ctx.get_opnd_type(StackOpnd(0));

        assert_eq!(status, Some(KeepCompiling));
        assert_eq!(tmp_type_top, Type::Fixnum);
        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_int2fix() {
        let (mut jit, _context, mut asm, _cb, mut ocb) = setup_codegen();
        jit.opcode = YARVINSN_putobject_INT2FIX_0_.as_usize();
        let status = gen_putobject_int2fix(&mut jit, &mut asm, &mut ocb);

        let tmp_type_top = asm.ctx.get_opnd_type(StackOpnd(0));

        // Right now we're not testing the generated machine code to make sure a literal 1 or 0 was pushed. I've checked locally.
        assert_eq!(status, Some(KeepCompiling));
        assert_eq!(tmp_type_top, Type::Fixnum);
    }

    #[test]
    fn test_putself() {
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();
        let status = gen_putself(&mut jit, &mut asm, &mut ocb);

        assert_eq!(status, Some(KeepCompiling));
        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_gen_setn() {
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();
        asm.stack_push(Type::Fixnum);
        asm.stack_push(Type::Flonum);
        asm.stack_push(Type::CString);

        let mut value_array: [u64; 2] = [0, 2];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_setn(&mut jit, &mut asm, &mut ocb);

        assert_eq!(status, Some(KeepCompiling));

        assert_eq!(Type::CString, asm.ctx.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::Flonum, asm.ctx.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::CString, asm.ctx.get_opnd_type(StackOpnd(0)));

        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0);
    }

    #[test]
    fn test_gen_topn() {
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();
        asm.stack_push(Type::Flonum);
        asm.stack_push(Type::CString);

        let mut value_array: [u64; 2] = [0, 1];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_topn(&mut jit, &mut asm, &mut ocb);

        assert_eq!(status, Some(KeepCompiling));

        assert_eq!(Type::Flonum, asm.ctx.get_opnd_type(StackOpnd(2)));
        assert_eq!(Type::CString, asm.ctx.get_opnd_type(StackOpnd(1)));
        assert_eq!(Type::Flonum, asm.ctx.get_opnd_type(StackOpnd(0)));

        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() > 0); // Write some movs
    }

    #[test]
    fn test_gen_adjuststack() {
        let (mut jit, _context, mut asm, mut cb, mut ocb) = setup_codegen();
        asm.stack_push(Type::Flonum);
        asm.stack_push(Type::CString);
        asm.stack_push(Type::Fixnum);

        let mut value_array: [u64; 3] = [0, 2, 0];
        let pc: *mut VALUE = &mut value_array as *mut u64 as *mut VALUE;
        jit.pc = pc;

        let status = gen_adjuststack(&mut jit, &mut asm, &mut ocb);

        assert_eq!(status, Some(KeepCompiling));

        assert_eq!(Type::Flonum, asm.ctx.get_opnd_type(StackOpnd(0)));

        asm.compile(&mut cb, None).unwrap();
        assert!(cb.get_write_pos() == 0); // No instructions written
    }

    #[test]
    fn test_gen_leave() {
        let (mut jit, _context, mut asm, _cb, mut ocb) = setup_codegen();
        // Push return value
        asm.stack_push(Type::Fixnum);
        asm.set_side_exit_context(0 as _, 0);
        gen_leave(&mut jit, &mut asm, &mut ocb);
    }
}
