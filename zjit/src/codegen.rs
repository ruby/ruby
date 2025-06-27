use std::cell::Cell;
use std::rc::Rc;
use std::num::NonZeroU32;

use crate::backend::current::{Reg, ALLOC_REGS};
use crate::profile::get_or_create_iseq_payload;
use crate::state::ZJITState;
use crate::{asm::CodeBlock, cruby::*, options::debug, virtualmem::CodePtr};
use crate::invariants::{iseq_escapes_ep, track_no_ep_escape_assumption};
use crate::backend::lir::{self, asm_comment, Assembler, Opnd, Target, CFP, C_ARG_OPNDS, C_RET_OPND, EC, SP};
use crate::hir::{iseq_to_hir, Block, BlockId, BranchEdge, CallInfo, RangeType, SELF_PARAM_IDX, SpecialObjectType};
use crate::hir::{Const, FrameState, Function, Insn, InsnId};
use crate::hir_type::{types::Fixnum, Type};
use crate::options::get_option;

/// Ephemeral code generation state
struct JITState {
    /// Instruction sequence for the method being compiled
    iseq: IseqPtr,

    /// Low-level IR Operands indexed by High-level IR's Instruction ID
    opnds: Vec<Option<Opnd>>,

    /// Labels for each basic block indexed by the BlockId
    labels: Vec<Option<Target>>,

    /// Branches to an ISEQ that need to be compiled later
    branch_iseqs: Vec<(Rc<Branch>, IseqPtr)>,
}

impl JITState {
    /// Create a new JITState instance
    fn new(iseq: IseqPtr, num_insns: usize, num_blocks: usize) -> Self {
        JITState {
            iseq,
            opnds: vec![None; num_insns],
            labels: vec![None; num_blocks],
            branch_iseqs: Vec::default(),
        }
    }

    /// Retrieve the output of a given instruction that has been compiled
    fn get_opnd(&self, insn_id: InsnId) -> Option<lir::Opnd> {
        let opnd = self.opnds[insn_id.0];
        if opnd.is_none() {
            debug!("Failed to get_opnd({insn_id})");
        }
        opnd
    }

    /// Find or create a label for a given BlockId
    fn get_label(&mut self, asm: &mut Assembler, block_id: BlockId) -> Target {
        match &self.labels[block_id.0] {
            Some(label) => label.clone(),
            None => {
                let label = asm.new_label(&format!("{block_id}"));
                self.labels[block_id.0] = Some(label.clone());
                label
            }
        }
    }

    /// Assume that this ISEQ doesn't escape EP. Return false if it's known to escape EP.
    fn assume_no_ep_escape(iseq: IseqPtr) -> bool {
        if iseq_escapes_ep(iseq) {
            return false;
        }
        track_no_ep_escape_assumption(iseq);
        true
    }
}

/// CRuby API to compile a given ISEQ
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, _ec: EcPtr) -> *const u8 {
    // Do not test the JIT code in HIR tests
    if cfg!(test) {
        return std::ptr::null();
    }

    // Take a lock to avoid writing to ISEQ in parallel with Ractors.
    // with_vm_lock() does nothing if the program doesn't use Ractors.
    let code_ptr = with_vm_lock(src_loc!(), || {
        gen_iseq_entry_point(iseq)
    });

    // Assert that the ISEQ compiles if RubyVM::ZJIT.assert_compiles is enabled
    if ZJITState::assert_compiles_enabled() && code_ptr.is_null() {
        let iseq_location = iseq_get_location(iseq, 0);
        panic!("Failed to compile: {iseq_location}");
    }

    code_ptr
}

/// Compile an entry point for a given ISEQ
fn gen_iseq_entry_point(iseq: IseqPtr) -> *const u8 {
    // Compile ISEQ into High-level IR
    let function = match compile_iseq(iseq) {
        Some(function) => function,
        None => return std::ptr::null(),
    };

    // Compile the High-level IR
    let cb = ZJITState::get_code_block();
    let (start_ptr, mut branch_iseqs) = match gen_function(cb, iseq, &function) {
        Some((start_ptr, branch_iseqs)) => {
            // Remember the block address to reuse it later
            let payload = get_or_create_iseq_payload(iseq);
            payload.start_ptr = Some(start_ptr);

            // Compile an entry point to the JIT code
            (gen_entry(cb, iseq, &function, start_ptr), branch_iseqs)
        },
        None => (None, vec![]),
    };

    // Recursively compile callee ISEQs
    while let Some((branch, iseq)) = branch_iseqs.pop() {
        // Disable profiling. This will be the last use of the profiling information for the ISEQ.
        unsafe { rb_zjit_profile_disable(iseq); }

        // Compile the ISEQ
        if let Some((callee_ptr, callee_branch_iseqs)) = gen_iseq(cb, iseq) {
            let callee_addr = callee_ptr.raw_ptr(cb);
            branch.regenerate(cb, |asm| {
                asm.ccall(callee_addr, vec![]);
            });
            branch_iseqs.extend(callee_branch_iseqs);
        } else {
            // Failed to compile the callee. Bail out of compiling this graph of ISEQs.
            return std::ptr::null();
        }
    }

    // Always mark the code region executable if asm.compile() has been used
    cb.mark_all_executable();

    // Return a JIT code address or a null pointer
    start_ptr.map(|start_ptr| start_ptr.raw_ptr(cb)).unwrap_or(std::ptr::null())
}

/// Compile a JIT entry
fn gen_entry(cb: &mut CodeBlock, iseq: IseqPtr, function: &Function, function_ptr: CodePtr) -> Option<CodePtr> {
    // Set up registers for CFP, EC, SP, and basic block arguments
    let mut asm = Assembler::new();
    gen_entry_prologue(&mut asm, iseq);
    gen_method_params(&mut asm, iseq, function.block(BlockId(0)));

    // Jump to the first block using a call instruction
    asm.ccall(function_ptr.raw_ptr(cb) as *const u8, vec![]);

    // Restore registers for CFP, EC, and SP after use
    asm_comment!(asm, "exit to the interpreter");
    // On x86_64, maintain 16-byte stack alignment
    if cfg!(target_arch = "x86_64") {
        asm.cpop_into(SP);
    }
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);
    asm.frame_teardown();
    asm.cret(C_RET_OPND);

    asm.compile(cb).map(|(start_ptr, _)| start_ptr)
}

/// Compile an ISEQ into machine code
fn gen_iseq(cb: &mut CodeBlock, iseq: IseqPtr) -> Option<(CodePtr, Vec<(Rc<Branch>, IseqPtr)>)> {
    // Return an existing pointer if it's already compiled
    let payload = get_or_create_iseq_payload(iseq);
    if let Some(start_ptr) = payload.start_ptr {
        return Some((start_ptr, vec![]));
    }

    // Convert ISEQ into High-level IR and optimize HIR
    let function = match compile_iseq(iseq) {
        Some(function) => function,
        None => return None,
    };

    // Compile the High-level IR
    let result = gen_function(cb, iseq, &function);
    if let Some((start_ptr, _)) = result {
        payload.start_ptr = Some(start_ptr);
    }
    result
}

/// Compile a function
fn gen_function(cb: &mut CodeBlock, iseq: IseqPtr, function: &Function) -> Option<(CodePtr, Vec<(Rc<Branch>, IseqPtr)>)> {
    let mut jit = JITState::new(iseq, function.num_insns(), function.num_blocks());
    let mut asm = Assembler::new();

    // Compile each basic block
    let reverse_post_order = function.rpo();
    for &block_id in reverse_post_order.iter() {
        let block = function.block(block_id);
        asm_comment!(asm, "Block: {block_id}({})", block.params().map(|param| format!("{param}")).collect::<Vec<_>>().join(", "));

        // Write a label to jump to the basic block
        let label = jit.get_label(&mut asm, block_id);
        asm.write_label(label);

        // Set up the frame at the first block
        if block_id == BlockId(0) {
            asm.frame_setup();
        }

        // Compile all parameters
        for &insn_id in block.params() {
            match function.find(insn_id) {
                Insn::Param { idx } => {
                    jit.opnds[insn_id.0] = Some(gen_param(&mut asm, idx));
                },
                insn => unreachable!("Non-param insn found in block.params: {insn:?}"),
            }
        }

        // Compile all instructions
        for &insn_id in block.insns() {
            let insn = function.find(insn_id);
            if gen_insn(cb, &mut jit, &mut asm, function, insn_id, &insn).is_none() {
                debug!("Failed to compile insn: {insn_id} {insn}");
                return None;
            }
        }
    }

    if get_option!(dump_lir) {
        println!("LIR:\nfn {}:\n{:?}", iseq_name(iseq), asm);
    }

    // Generate code if everything can be compiled
    asm.compile(cb).map(|(start_ptr, _)| (start_ptr, jit.branch_iseqs))
}

/// Compile an instruction
fn gen_insn(cb: &mut CodeBlock, jit: &mut JITState, asm: &mut Assembler, function: &Function, insn_id: InsnId, insn: &Insn) -> Option<()> {
    // Convert InsnId to lir::Opnd
    macro_rules! opnd {
        ($insn_id:ident) => {
            jit.get_opnd(*$insn_id)?
        };
    }

    if !matches!(*insn, Insn::Snapshot { .. }) {
        asm_comment!(asm, "Insn: {insn_id} {insn}");
    }

    let out_opnd = match insn {
        Insn::Const { val: Const::Value(val) } => gen_const(*val),
        Insn::NewArray { elements, state } => gen_new_array(jit, asm, elements, &function.frame_state(*state)),
        Insn::NewRange { low, high, flag, state } => gen_new_range(asm, opnd!(low), opnd!(high), *flag, &function.frame_state(*state)),
        Insn::ArrayDup { val, state } => gen_array_dup(asm, opnd!(val), &function.frame_state(*state)),
        Insn::StringCopy { val, chilled } => gen_string_copy(asm, opnd!(val), *chilled),
        Insn::Param { idx } => unreachable!("block.insns should not have Insn::Param({idx})"),
        Insn::Snapshot { .. } => return Some(()), // we don't need to do anything for this instruction at the moment
        Insn::Jump(branch) => return gen_jump(jit, asm, branch),
        Insn::IfTrue { val, target } => return gen_if_true(jit, asm, opnd!(val), target),
        Insn::IfFalse { val, target } => return gen_if_false(jit, asm, opnd!(val), target),
        Insn::SendWithoutBlock { call_info, cd, state, self_val, args, .. } => gen_send_without_block(jit, asm, call_info, *cd, &function.frame_state(*state), self_val, args)?,
        Insn::SendWithoutBlockDirect { cme, iseq, self_val, args, state, .. } => gen_send_without_block_direct(cb, jit, asm, *cme, *iseq, opnd!(self_val), args, &function.frame_state(*state))?,
        Insn::InvokeBuiltin { bf, args, state } => gen_invokebuiltin(jit, asm, &function.frame_state(*state), bf, args)?,
        Insn::Return { val } => return Some(gen_return(asm, opnd!(val))?),
        Insn::FixnumAdd { left, right, state } => gen_fixnum_add(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state))?,
        Insn::FixnumSub { left, right, state } => gen_fixnum_sub(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state))?,
        Insn::FixnumMult { left, right, state } => gen_fixnum_mult(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state))?,
        Insn::FixnumEq { left, right } => gen_fixnum_eq(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumNeq { left, right } => gen_fixnum_neq(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumLt { left, right } => gen_fixnum_lt(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumLe { left, right } => gen_fixnum_le(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumGt { left, right } => gen_fixnum_gt(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumGe { left, right } => gen_fixnum_ge(asm, opnd!(left), opnd!(right))?,
        Insn::Test { val } => gen_test(asm, opnd!(val))?,
        Insn::GuardType { val, guard_type, state } => gen_guard_type(jit, asm, opnd!(val), *guard_type, &function.frame_state(*state))?,
        Insn::GuardBitEquals { val, expected, state } => gen_guard_bit_equals(jit, asm, opnd!(val), *expected, &function.frame_state(*state))?,
        Insn::PatchPoint(_) => return Some(()), // For now, rb_zjit_bop_redefined() panics. TODO: leave a patch point and fix rb_zjit_bop_redefined()
        Insn::CCall { cfun, args, name: _, return_type: _, elidable: _ } => gen_ccall(jit, asm, *cfun, args)?,
        Insn::GetIvar { self_val, id, state: _ } => gen_getivar(asm, opnd!(self_val), *id),
        Insn::SetGlobal { id, val, state: _ } => gen_setglobal(asm, *id, opnd!(val)),
        Insn::GetGlobal { id, state: _ } => gen_getglobal(asm, *id),
        &Insn::GetLocal { ep_offset, level } => gen_nested_getlocal(asm, ep_offset, level)?,
        Insn::SetLocal { val, ep_offset, level } => return gen_nested_setlocal(asm, opnd!(val), *ep_offset, *level),
        Insn::GetConstantPath { ic, state } => gen_get_constant_path(asm, *ic, &function.frame_state(*state)),
        Insn::SetIvar { self_val, id, val, state: _ } => return gen_setivar(asm, opnd!(self_val), *id, opnd!(val)),
        Insn::SideExit { state } => return gen_side_exit(jit, asm, &function.frame_state(*state)),
        Insn::PutSpecialObject { value_type } => gen_putspecialobject(asm, *value_type),
        Insn::AnyToString { val, str, state } => gen_anytostring(asm, opnd!(val), opnd!(str), &function.frame_state(*state))?,
        Insn::Defined { op_type, obj, pushval, v } => gen_defined(jit, asm, *op_type, *obj, *pushval, opnd!(v))?,
        _ => {
            debug!("ZJIT: gen_function: unexpected insn {insn}");
            return None;
        }
    };

    assert!(insn.has_output(), "Cannot write LIR output of HIR instruction with no output");

    // If the instruction has an output, remember it in jit.opnds
    jit.opnds[insn_id.0] = Some(out_opnd);

    Some(())
}

/// Gets the EP of the ISeq of the containing method, or "local level".
/// Equivalent of GET_LEP() macro.
fn gen_get_lep(jit: &JITState, asm: &mut Assembler) -> Opnd {
    // Equivalent of get_lvar_level() in compile.c
    fn get_lvar_level(mut iseq: IseqPtr) -> u32 {
        let local_iseq = unsafe { rb_get_iseq_body_local_iseq(iseq) };
        let mut level = 0;
        while iseq != local_iseq {
            iseq = unsafe { rb_get_iseq_body_parent_iseq(iseq) };
            level += 1;
        }

        level
    }

    let level = get_lvar_level(jit.iseq);
    gen_get_ep(asm, level)
}

// Get EP at `level` from CFP
fn gen_get_ep(asm: &mut Assembler, level: u32) -> Opnd {
    // Load environment pointer EP from CFP into a register
    let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
    let mut ep_opnd = asm.load(ep_opnd);

    for _ in 0..level {
        // Get the previous EP from the current EP
        // See GET_PREV_EP(ep) macro
        // VALUE *prev_ep = ((VALUE *)((ep)[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03))
        const UNTAGGING_MASK: Opnd = Opnd::Imm(!0x03);
        let offset = SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL;
        ep_opnd = asm.load(Opnd::mem(64, ep_opnd, offset));
        ep_opnd = asm.and(ep_opnd, UNTAGGING_MASK);
    }

    ep_opnd
}

fn gen_defined(jit: &JITState, asm: &mut Assembler, op_type: usize, _obj: VALUE, pushval: VALUE, _tested_value: Opnd) -> Option<Opnd> {
    match op_type as defined_type {
        DEFINED_YIELD => {
            // `yield` goes to the block handler stowed in the "local" iseq which is
            // the current iseq or a parent. Only the "method" iseq type can be passed a
            // block handler. (e.g. `yield` in the top level script is a syntax error.)
            let local_iseq = unsafe { rb_get_iseq_body_local_iseq(jit.iseq) };
            if unsafe { rb_get_iseq_body_type(local_iseq) } == ISEQ_TYPE_METHOD {
                let lep = gen_get_lep(jit, asm);
                let block_handler = asm.load(Opnd::mem(64, lep, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL));
                let pushval = asm.load(pushval.into());
                asm.cmp(block_handler, VM_BLOCK_HANDLER_NONE.into());
                Some(asm.csel_e(Qnil.into(), pushval.into()))
            } else {
                Some(Qnil.into())
            }
        }
        _ => None
    }
}

/// Get a local variable from a higher scope. `local_ep_offset` is in number of VALUEs.
fn gen_nested_getlocal(asm: &mut Assembler, local_ep_offset: u32, level: NonZeroU32) -> Option<lir::Opnd> {
    let ep = gen_get_ep(asm, level.get());
    let offset = -(SIZEOF_VALUE_I32 * i32::try_from(local_ep_offset).ok()?);
    Some(asm.load(Opnd::mem(64, ep, offset)))
}

/// Set a local variable from a higher scope. `local_ep_offset` is in number of VALUEs.
fn gen_nested_setlocal(asm: &mut Assembler, val: Opnd, local_ep_offset: u32, level: NonZeroU32) -> Option<()> {
    let ep = gen_get_ep(asm, level.get());
    let offset = -(SIZEOF_VALUE_I32 * i32::try_from(local_ep_offset).ok()?);
    asm.mov(Opnd::mem(64, ep, offset), val);
    Some(())
}

fn gen_get_constant_path(asm: &mut Assembler, ic: *const iseq_inline_constant_cache, state: &FrameState) -> Opnd {
    unsafe extern "C" {
        fn rb_vm_opt_getconstant_path(ec: EcPtr, cfp: CfpPtr, ic: *const iseq_inline_constant_cache) -> VALUE;
    }

    // Save PC since the call can allocate an IC
    gen_save_pc(asm, state);

    let val = asm.ccall(
        rb_vm_opt_getconstant_path as *const u8,
        vec![EC, CFP, Opnd::const_ptr(ic as *const u8)],
    );
    val
}

fn gen_invokebuiltin(jit: &mut JITState, asm: &mut Assembler, state: &FrameState, bf: &rb_builtin_function, args: &Vec<InsnId>) -> Option<lir::Opnd> {
    // Ensure we have enough room fit ec, self, and arguments
    // TODO remove this check when we have stack args (we can use Time.new to test it)
    if bf.argc + 2 > (C_ARG_OPNDS.len() as i32) {
        return None;
    }

    gen_save_pc(asm, state);

    let mut cargs = vec![EC];
    for &arg in args.iter() {
        let opnd = jit.get_opnd(arg)?;
        cargs.push(opnd);
    }

    let val = asm.ccall(bf.func_ptr as *const u8, cargs);

    Some(val)
}

/// Lowering for [`Insn::CCall`]. This is a low-level raw call that doesn't know
/// anything about the callee, so handling for e.g. GC safety is dealt with elsewhere.
fn gen_ccall(jit: &mut JITState, asm: &mut Assembler, cfun: *const u8, args: &[InsnId]) -> Option<lir::Opnd> {
    let mut lir_args = Vec::with_capacity(args.len());
    for &arg in args {
        lir_args.push(jit.get_opnd(arg)?);
    }

    Some(asm.ccall(cfun, lir_args))
}

/// Emit an uncached instance variable lookup
fn gen_getivar(asm: &mut Assembler, recv: Opnd, id: ID) -> Opnd {
    asm_comment!(asm, "call rb_ivar_get");
    asm.ccall(
        rb_ivar_get as *const u8,
        vec![recv, Opnd::UImm(id.0)],
    )
}

/// Emit an uncached instance variable store
fn gen_setivar(asm: &mut Assembler, recv: Opnd, id: ID, val: Opnd) -> Option<()> {
    asm_comment!(asm, "call rb_ivar_set");
    asm.ccall(
        rb_ivar_set as *const u8,
        vec![recv, Opnd::UImm(id.0), val],
    );
    Some(())
}

/// Look up global variables
fn gen_getglobal(asm: &mut Assembler, id: ID) -> Opnd {
    asm_comment!(asm, "call rb_gvar_get");
    asm.ccall(
        rb_gvar_get as *const u8,
        vec![Opnd::UImm(id.0)],
    )
}

/// Set global variables
fn gen_setglobal(asm: &mut Assembler, id: ID, val: Opnd) -> Opnd {
    asm_comment!(asm, "call rb_gvar_set");
    asm.ccall(
        rb_gvar_set as *const u8,
        vec![Opnd::UImm(id.0), val],
    )
}

/// Side-exit into the interpreter
fn gen_side_exit(jit: &mut JITState, asm: &mut Assembler, state: &FrameState) -> Option<()> {
    asm.jmp(side_exit(jit, state)?);
    Some(())
}

/// Emit a special object lookup
fn gen_putspecialobject(asm: &mut Assembler, value_type: SpecialObjectType) -> Opnd {
    // Get the EP of the current CFP and load it into a register
    let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
    let ep_reg = asm.load(ep_opnd);

    asm_comment!(asm, "call rb_vm_get_special_object");
    asm.ccall(
        rb_vm_get_special_object as *const u8,
        vec![ep_reg, Opnd::UImm(u64::from(value_type))],
    )
}

/// Compile an interpreter entry block to be inserted into an ISEQ
fn gen_entry_prologue(asm: &mut Assembler, iseq: IseqPtr) {
    asm_comment!(asm, "ZJIT entry point: {}", iseq_get_location(iseq, 0));
    asm.frame_setup();

    // Save the registers we'll use for CFP, EP, SP
    asm.cpush(CFP);
    asm.cpush(EC);
    asm.cpush(SP);
    // On x86_64, maintain 16-byte stack alignment
    if cfg!(target_arch = "x86_64") {
        asm.cpush(SP);
    }

    // EC and CFP are passed as arguments
    asm.mov(EC, C_ARG_OPNDS[0]);
    asm.mov(CFP, C_ARG_OPNDS[1]);

    // Load the current SP from the CFP into REG_SP
    asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));

    // TODO: Support entry chain guard when ISEQ has_opt
}

/// Assign method arguments to basic block arguments at JIT entry
fn gen_method_params(asm: &mut Assembler, iseq: IseqPtr, entry_block: &Block) {
    let self_param = gen_param(asm, SELF_PARAM_IDX);
    asm.mov(self_param, Opnd::mem(VALUE_BITS, CFP, RUBY_OFFSET_CFP_SELF));

    let num_params = entry_block.params().len() - 1; // -1 to exclude self
    if num_params > 0 {
        asm_comment!(asm, "set method params: {num_params}");

        // Allocate registers for basic block arguments
        let params: Vec<Opnd> = (0..num_params).map(|idx|
            gen_param(asm, idx + 1) // +1 for self
        ).collect();

        // Assign local variables to the basic block arguments
        for (idx, &param) in params.iter().enumerate() {
            let local = gen_getlocal(asm, iseq, idx);
            asm.load_into(param, local);
        }
    }
}

/// Set branch params to basic block arguments
fn gen_branch_params(jit: &mut JITState, asm: &mut Assembler, branch: &BranchEdge) -> Option<()> {
    if !branch.args.is_empty() {
        asm_comment!(asm, "set branch params: {}", branch.args.len());
        let mut moves: Vec<(Reg, Opnd)> = vec![];
        for (idx, &arg) in branch.args.iter().enumerate() {
            moves.push((param_reg(idx), jit.get_opnd(arg)?));
        }
        asm.parallel_mov(moves);
    }
    Some(())
}

/// Get the local variable at the given index
fn gen_getlocal(asm: &mut Assembler, iseq: IseqPtr, local_idx: usize) -> lir::Opnd {
    let ep_offset = local_idx_to_ep_offset(iseq, local_idx);

    if JITState::assume_no_ep_escape(iseq) {
        // Create a reference to the local variable using the SP register. We assume EP == BP.
        // TODO: Implement the invalidation in rb_zjit_invalidate_ep_is_bp()
        let offs = -(SIZEOF_VALUE_I32 * (ep_offset + 1));
        Opnd::mem(64, SP, offs)
    } else {
        // Get the EP of the current CFP
        let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
        let ep_reg = asm.load(ep_opnd);

        // Create a reference to the local variable using cfp->ep
        let offs = -(SIZEOF_VALUE_I32 * ep_offset);
        Opnd::mem(64, ep_reg, offs)
    }
}

/// Compile a constant
fn gen_const(val: VALUE) -> lir::Opnd {
    // Just propagate the constant value and generate nothing
    Opnd::Value(val)
}

/// Compile a basic block argument
fn gen_param(asm: &mut Assembler, idx: usize) -> lir::Opnd {
    asm.live_reg_opnd(Opnd::Reg(param_reg(idx)))
}

/// Compile a jump to a basic block
fn gen_jump(jit: &mut JITState, asm: &mut Assembler, branch: &BranchEdge) -> Option<()> {
    // Set basic block arguments
    gen_branch_params(jit, asm, branch);

    // Jump to the basic block
    let target = jit.get_label(asm, branch.target);
    asm.jmp(target);
    Some(())
}

/// Compile a conditional branch to a basic block
fn gen_if_true(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, branch: &BranchEdge) -> Option<()> {
    // If val is zero, move on to the next instruction.
    let if_false = asm.new_label("if_false");
    asm.test(val, val);
    asm.jz(if_false.clone());

    // If val is not zero, set basic block arguments and jump to the branch target.
    // TODO: Consider generating the loads out-of-line
    let if_true = jit.get_label(asm, branch.target);
    gen_branch_params(jit, asm, branch);
    asm.jmp(if_true);

    asm.write_label(if_false);

    Some(())
}

/// Compile a conditional branch to a basic block
fn gen_if_false(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, branch: &BranchEdge) -> Option<()> {
    // If val is not zero, move on to the next instruction.
    let if_true = asm.new_label("if_true");
    asm.test(val, val);
    asm.jnz(if_true.clone());

    // If val is zero, set basic block arguments and jump to the branch target.
    // TODO: Consider generating the loads out-of-line
    let if_false = jit.get_label(asm, branch.target);
    gen_branch_params(jit, asm, branch);
    asm.jmp(if_false);

    asm.write_label(if_true);

    Some(())
}

/// Compile a dynamic dispatch without block
fn gen_send_without_block(
    jit: &mut JITState,
    asm: &mut Assembler,
    call_info: &CallInfo,
    cd: *const rb_call_data,
    state: &FrameState,
    self_val: &InsnId,
    args: &Vec<InsnId>,
) -> Option<lir::Opnd> {
    // Spill locals onto the stack.
    // TODO: Don't spill locals eagerly; lazily reify frames
    asm_comment!(asm, "spill locals");
    for (idx, &insn_id) in state.locals().enumerate() {
        asm.mov(Opnd::mem(64, SP, (-local_idx_to_ep_offset(jit.iseq, idx) - 1) * SIZEOF_VALUE_I32), jit.get_opnd(insn_id)?);
    }
    // Spill the receiver and the arguments onto the stack.
    // They need to be on the interpreter stack to let the interpreter access them.
    // TODO: Avoid spilling operands that have been spilled before.
    asm_comment!(asm, "spill receiver and arguments");
    for (idx, &insn_id) in [*self_val].iter().chain(args.iter()).enumerate() {
        // Currently, we don't move the SP register. So it's equal to the base pointer.
        let stack_opnd = Opnd::mem(64, SP, idx as i32  * SIZEOF_VALUE_I32);
        asm.mov(stack_opnd, jit.get_opnd(insn_id)?);
    }

    // Save PC and SP
    gen_save_pc(asm, state);
    gen_save_sp(asm, 1 + args.len()); // +1 for receiver

    asm_comment!(asm, "call #{} with dynamic dispatch", call_info.method_name);
    unsafe extern "C" {
        fn rb_vm_opt_send_without_block(ec: EcPtr, cfp: CfpPtr, cd: VALUE) -> VALUE;
    }
    let ret = asm.ccall(
        rb_vm_opt_send_without_block as *const u8,
        vec![EC, CFP, (cd as usize).into()],
    );
    // TODO(max): Add a PatchPoint here that can side-exit the function if the callee messed with
    // the frame's locals

    Some(ret)
}

/// Compile a direct jump to an ISEQ call without block
fn gen_send_without_block_direct(
    cb: &mut CodeBlock,
    jit: &mut JITState,
    asm: &mut Assembler,
    cme: *const rb_callable_method_entry_t,
    iseq: IseqPtr,
    recv: Opnd,
    args: &Vec<InsnId>,
    state: &FrameState,
) -> Option<lir::Opnd> {
    // Save cfp->pc and cfp->sp for the caller frame
    gen_save_pc(asm, state);
    gen_save_sp(asm, state.stack().len() - args.len() - 1); // -1 for receiver

    // Spill the virtual stack and the locals of the caller onto the stack
    // TODO: Lazily materialize caller frames on side exits or when needed
    asm_comment!(asm, "spill locals and stack");
    for (idx, &insn_id) in state.locals().enumerate() {
        asm.mov(Opnd::mem(64, SP, (-local_idx_to_ep_offset(jit.iseq, idx) - 1) * SIZEOF_VALUE_I32), jit.get_opnd(insn_id)?);
    }
    for (idx, &insn_id) in state.stack().enumerate() {
        asm.mov(Opnd::mem(64, SP, idx as i32 * SIZEOF_VALUE_I32), jit.get_opnd(insn_id)?);
    }

    // Set up the new frame
    // TODO: Lazily materialize caller frames on side exits or when needed
    gen_push_frame(asm, args.len(), state, ControlFrame {
        recv,
        iseq,
        cme,
        frame_type: VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL,
    });

    asm_comment!(asm, "switch to new SP register");
    let local_size = unsafe { get_iseq_body_local_table_size(iseq) } as usize;
    let new_sp = asm.add(SP, ((state.stack().len() + local_size - args.len() + VM_ENV_DATA_SIZE as usize) * SIZEOF_VALUE).into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // Set up arguments
    let mut c_args: Vec<Opnd> = vec![];
    c_args.push(recv);
    for &arg in args.iter() {
        c_args.push(jit.get_opnd(arg)?);
    }

    // Make a method call. The target address will be rewritten once compiled.
    let branch = Branch::new();
    let dummy_ptr = cb.get_write_ptr().raw_ptr(cb);
    jit.branch_iseqs.push((branch.clone(), iseq));
    // TODO(max): Add a PatchPoint here that can side-exit the function if the callee messed with
    // the frame's locals
    let ret = asm.ccall_with_branch(dummy_ptr, c_args, &branch);

    // If a callee side-exits, i.e. returns Qundef, propagate the return value to the caller.
    // The caller will side-exit the callee into the interpreter.
    // TODO: Let side exit code pop all JIT frames to optimize away this cmp + je.
    asm.cmp(ret, Qundef.into());
    asm.je(ZJITState::get_exit_trampoline().into());

    Some(ret)
}

/// Compile a string resurrection
fn gen_string_copy(asm: &mut Assembler, recv: Opnd, chilled: bool) -> Opnd {
    asm_comment!(asm, "call rb_ec_str_resurrect");
    // TODO: split rb_ec_str_resurrect into separate functions
    let chilled = if chilled { Opnd::Imm(1) } else { Opnd::Imm(0) };
    asm.ccall(
        rb_ec_str_resurrect as *const u8,
        vec![EC, recv, chilled],
    )
}

/// Compile an array duplication instruction
fn gen_array_dup(
    asm: &mut Assembler,
    val: lir::Opnd,
    state: &FrameState,
) -> lir::Opnd {
    // Save PC
    gen_save_pc(asm, state);

    asm_comment!(asm, "call rb_ary_resurrect");
    asm.ccall(
        rb_ary_resurrect as *const u8,
        vec![val],
    )
}

/// Compile a new array instruction
fn gen_new_array(
    jit: &mut JITState,
    asm: &mut Assembler,
    elements: &Vec<InsnId>,
    state: &FrameState,
) -> lir::Opnd {
    // Save PC
    gen_save_pc(asm, state);

    let length: ::std::os::raw::c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

    asm_comment!(asm, "call rb_ary_new");
    let new_array = asm.ccall(
        rb_ary_new_capa as *const u8,
        vec![lir::Opnd::Imm(length)],
    );

    for i in 0..elements.len() {
        let insn_id = elements.get(i as usize).expect("Element should exist at index");
        let val = jit.get_opnd(*insn_id).unwrap();
        asm_comment!(asm, "call rb_ary_push");
        asm.ccall(
            rb_ary_push as *const u8,
            vec![new_array, val]
        );
    }

    new_array
}

/// Compile a new range instruction
fn gen_new_range(
    asm: &mut Assembler,
    low: lir::Opnd,
    high: lir::Opnd,
    flag: RangeType,
    state: &FrameState,
) -> lir::Opnd {
    // Save PC
    gen_save_pc(asm, state);

    asm_comment!(asm, "call rb_range_new");
    // Call rb_range_new(low, high, flag)
    let new_range = asm.ccall(
        rb_range_new as *const u8,
        vec![low, high, lir::Opnd::Imm(flag as i64)],
    );

    new_range
}

/// Compile code that exits from JIT code with a return value
fn gen_return(asm: &mut Assembler, val: lir::Opnd) -> Option<()> {
    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    asm_comment!(asm, "pop stack frame");
    let incr_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, incr_cfp);
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    asm.frame_teardown();

    // Return from the function
    asm.cret(val);
    Some(())
}

/// Compile Fixnum + Fixnum
fn gen_fixnum_add(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Add left + right and test for overflow
    let left_untag = asm.sub(left, Opnd::Imm(1));
    let out_val = asm.add(left_untag, right);
    asm.jo(side_exit(jit, state)?);

    Some(out_val)
}

/// Compile Fixnum - Fixnum
fn gen_fixnum_sub(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Subtract left - right and test for overflow
    let val_untag = asm.sub(left, right);
    asm.jo(side_exit(jit, state)?);
    let out_val = asm.add(val_untag, Opnd::Imm(1));

    Some(out_val)
}

/// Compile Fixnum * Fixnum
fn gen_fixnum_mult(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Do some bitwise gymnastics to handle tag bits
    // x * y is translated to (x >> 1) * (y - 1) + 1
    let left_untag = asm.rshift(left, Opnd::UImm(1));
    let right_untag = asm.sub(right, Opnd::UImm(1));
    let out_val = asm.mul(left_untag, right_untag);

    // Test for overflow
    asm.jo_mul(side_exit(jit, state)?);
    let out_val = asm.add(out_val, Opnd::UImm(1));

    Some(out_val)
}

/// Compile Fixnum == Fixnum
fn gen_fixnum_eq(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_e(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum != Fixnum
fn gen_fixnum_neq(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_ne(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum < Fixnum
fn gen_fixnum_lt(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_l(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum <= Fixnum
fn gen_fixnum_le(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_le(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum > Fixnum
fn gen_fixnum_gt(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_g(Qtrue.into(), Qfalse.into()))
}

/// Compile Fixnum >= Fixnum
fn gen_fixnum_ge(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(left, right);
    Some(asm.csel_ge(Qtrue.into(), Qfalse.into()))
}

fn gen_anytostring(asm: &mut Assembler, val: lir::Opnd, str: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Save PC
    gen_save_pc(asm, state);

    asm_comment!(asm, "call rb_obj_as_string_result");
    Some(asm.ccall(
        rb_obj_as_string_result as *const u8,
        vec![str, val],
    ))
}

/// Evaluate if a value is truthy
/// Produces a CBool type (0 or 1)
/// In Ruby, only nil and false are falsy
/// Everything else evaluates to true
fn gen_test(asm: &mut Assembler, val: lir::Opnd) -> Option<lir::Opnd> {
    // Test if any bit (outside of the Qnil bit) is on
    // See RB_TEST(), include/ruby/internal/special_consts.h
    asm.test(val, Opnd::Imm(!Qnil.as_i64()));
    Some(asm.csel_e(0.into(), 1.into()))
}

/// Compile a type check with a side exit
fn gen_guard_type(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, guard_type: Type, state: &FrameState) -> Option<lir::Opnd> {
    if guard_type.is_subtype(Fixnum) {
        // Check if opnd is Fixnum
        asm.test(val, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));
        asm.jz(side_exit(jit, state)?);
    } else {
        unimplemented!("unsupported type: {guard_type}");
    }
    Some(val)
}

/// Compile an identity check with a side exit
fn gen_guard_bit_equals(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, expected: VALUE, state: &FrameState) -> Option<lir::Opnd> {
    asm.cmp(val, Opnd::UImm(expected.into()));
    asm.jnz(side_exit(jit, state)?);
    Some(val)
}

/// Save the incremented PC on the CFP.
/// This is necessary when callees can raise or allocate.
fn gen_save_pc(asm: &mut Assembler, state: &FrameState) {
    let opcode: usize = state.get_opcode().try_into().unwrap();
    let next_pc: *const VALUE = unsafe { state.pc.offset(insn_len(opcode) as isize) };

    asm_comment!(asm, "save PC to CFP");
    asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), Opnd::const_ptr(next_pc as *const u8));
}

/// Save the current SP on the CFP
fn gen_save_sp(asm: &mut Assembler, stack_size: usize) {
    // Update cfp->sp which will be read by the interpreter. We also have the SP register in JIT
    // code, and ZJIT's codegen currently assumes the SP register doesn't move, e.g. gen_param().
    // So we don't update the SP register here. We could update the SP register to avoid using
    // an extra register for asm.lea(), but you'll need to manage the SP offset like YJIT does.
    asm_comment!(asm, "save SP to CFP: {}", stack_size);
    let sp_addr = asm.lea(Opnd::mem(64, SP, stack_size as i32 * SIZEOF_VALUE_I32));
    let cfp_sp = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP);
    asm.mov(cfp_sp, sp_addr);
}

/// Frame metadata written by gen_push_frame()
struct ControlFrame {
    recv: Opnd,
    iseq: IseqPtr,
    cme: *const rb_callable_method_entry_t,
    frame_type: u32,
}

/// Compile an interpreter frame
fn gen_push_frame(asm: &mut Assembler, argc: usize, state: &FrameState, frame: ControlFrame) {
    // Locals are written by the callee frame on side-exits or non-leaf calls

    // See vm_push_frame() for details
    asm_comment!(asm, "push cme, specval, frame type");
    // ep[-2]: cref of cme
    let local_size = unsafe { get_iseq_body_local_table_size(frame.iseq) } as i32;
    let ep_offset = state.stack().len() as i32 + local_size - argc as i32 + VM_ENV_DATA_SIZE as i32 - 1;
    asm.store(Opnd::mem(64, SP, (ep_offset - 2) * SIZEOF_VALUE_I32), VALUE::from(frame.cme).into());
    // ep[-1]: block_handler or prev EP
    // block_handler is not supported for now
    asm.store(Opnd::mem(64, SP, (ep_offset - 1) * SIZEOF_VALUE_I32), VM_BLOCK_HANDLER_NONE.into());
    // ep[0]: ENV_FLAGS
    asm.store(Opnd::mem(64, SP, ep_offset * SIZEOF_VALUE_I32), frame.frame_type.into());

    // Write to the callee CFP
    fn cfp_opnd(offset: i32) -> Opnd {
        Opnd::mem(64, CFP, offset - (RUBY_SIZEOF_CONTROL_FRAME as i32))
    }

    asm_comment!(asm, "push callee control frame");
    // cfp_opnd(RUBY_OFFSET_CFP_PC): written by the callee frame on side-exits or non-leaf calls
    // cfp_opnd(RUBY_OFFSET_CFP_SP): written by the callee frame on side-exits or non-leaf calls
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_ISEQ), VALUE::from(frame.iseq).into());
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SELF), frame.recv);
    let ep = asm.lea(Opnd::mem(64, SP, ep_offset * SIZEOF_VALUE_I32));
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_EP), ep);
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_BLOCK_CODE), 0.into());
}

/// Return a register we use for the basic block argument at a given index
fn param_reg(idx: usize) -> Reg {
    // To simplify the implementation, allocate a fixed register for each basic block argument for now.
    // TODO: Allow allocating arbitrary registers for basic block arguments
    if idx >= ALLOC_REGS.len() {
        unimplemented!(
            "register spilling not yet implemented, too many basic block arguments ({}/{})",
            idx + 1, ALLOC_REGS.len()
        );
    }
    ALLOC_REGS[idx]
}

/// Inverse of ep_offset_to_local_idx(). See ep_offset_to_local_idx() for details.
fn local_idx_to_ep_offset(iseq: IseqPtr, local_idx: usize) -> i32 {
    let local_size = unsafe { get_iseq_body_local_table_size(iseq) };
    local_size_and_idx_to_ep_offset(local_size as usize, local_idx)
}

/// Convert the number of locals and a local index to an offset in the EP
pub fn local_size_and_idx_to_ep_offset(local_size: usize, local_idx: usize) -> i32 {
    local_size as i32 - local_idx as i32 - 1 + VM_ENV_DATA_SIZE as i32
}

/// Convert ISEQ into High-level IR
fn compile_iseq(iseq: IseqPtr) -> Option<Function> {
    let mut function = match iseq_to_hir(iseq) {
        Ok(function) => function,
        Err(err) => {
            debug!("ZJIT: iseq_to_hir: {err:?}");
            return None;
        }
    };
    function.optimize();
    Some(function)
}

/// Build a Target::SideExit out of a FrameState
fn side_exit(jit: &mut JITState, state: &FrameState) -> Option<Target> {
    let mut stack = Vec::new();
    for &insn_id in state.stack() {
        stack.push(jit.get_opnd(insn_id)?);
    }

    let mut locals = Vec::new();
    for &insn_id in state.locals() {
        locals.push(jit.get_opnd(insn_id)?);
    }

    let target = Target::SideExit {
        pc: state.pc,
        stack,
        locals,
    };
    Some(target)
}

impl Assembler {
    /// Make a C call while marking the start and end positions of it
    fn ccall_with_branch(&mut self, fptr: *const u8, opnds: Vec<Opnd>, branch: &Rc<Branch>) -> Opnd {
        // We need to create our own branch rc objects so that we can move the closure below
        let start_branch = branch.clone();
        let end_branch = branch.clone();

        self.ccall_with_pos_markers(
            fptr,
            opnds,
            move |code_ptr, _| {
                start_branch.start_addr.set(Some(code_ptr));
            },
            move |code_ptr, _| {
                end_branch.end_addr.set(Some(code_ptr));
            },
        )
    }
}

/// Store info about an outgoing branch in a code segment
#[derive(Debug)]
struct Branch {
    /// Position where the generated code starts
    start_addr: Cell<Option<CodePtr>>,

    /// Position where the generated code ends (exclusive)
    end_addr: Cell<Option<CodePtr>>,
}

impl Branch {
    /// Allocate a new branch
    fn new() -> Rc<Self> {
        Rc::new(Branch {
            start_addr: Cell::new(None),
            end_addr: Cell::new(None),
        })
    }

    /// Regenerate a branch with a given callback
    fn regenerate(&self, cb: &mut CodeBlock, callback: impl Fn(&mut Assembler)) {
        cb.with_write_ptr(self.start_addr.get().unwrap(), |cb| {
            let mut asm = Assembler::new();
            callback(&mut asm);
            asm.compile(cb).unwrap();
            assert_eq!(self.end_addr.get().unwrap(), cb.get_write_ptr());
        });
    }
}
