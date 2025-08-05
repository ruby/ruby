use std::cell::Cell;
use std::rc::Rc;
use std::ffi::{c_int, c_void};

use crate::asm::Label;
use crate::backend::current::{Reg, ALLOC_REGS};
use crate::invariants::{track_bop_assumption, track_cme_assumption, track_stable_constant_names_assumption};
use crate::gc::{get_or_create_iseq_payload, append_gc_offsets};
use crate::state::ZJITState;
use crate::stats::{counter_ptr, Counter};
use crate::{asm::CodeBlock, cruby::*, options::debug, virtualmem::CodePtr};
use crate::backend::lir::{self, asm_comment, asm_ccall, Assembler, Opnd, SideExitContext, Target, CFP, C_ARG_OPNDS, C_RET_OPND, EC, NATIVE_STACK_PTR, NATIVE_BASE_PTR, SP};
use crate::hir::{iseq_to_hir, Block, BlockId, BranchEdge, Invariant, RangeType, SideExitReason, SideExitReason::*, SpecialObjectType, SELF_PARAM_IDX};
use crate::hir::{Const, FrameState, Function, Insn, InsnId};
use crate::hir_type::{types, Type};
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

    /// The number of bytes allocated for basic block arguments spilled onto the C stack
    c_stack_slots: usize,
}

impl JITState {
    /// Create a new JITState instance
    fn new(iseq: IseqPtr, num_insns: usize, num_blocks: usize, c_stack_slots: usize) -> Self {
        JITState {
            iseq,
            opnds: vec![None; num_insns],
            labels: vec![None; num_blocks],
            branch_iseqs: Vec::default(),
            c_stack_slots,
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
}

/// CRuby API to compile a given ISEQ
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, _ec: EcPtr) -> *const u8 {
    // Do not test the JIT code in HIR tests
    if cfg!(test) {
        return std::ptr::null();
    }

    // Reject ISEQs with very large temp stacks.
    // We cannot encode too large offsets to access locals in arm64.
    let stack_max = unsafe { rb_get_iseq_body_stack_max(iseq) };
    if stack_max >= i8::MAX as u32 {
        debug!("ISEQ stack too large: {stack_max}");
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

/// See [gen_iseq_entry_point_body]. This wrapper is to make sure cb.mark_all_executable()
/// is called even if gen_iseq_entry_point_body() partially fails and returns a null pointer.
fn gen_iseq_entry_point(iseq: IseqPtr) -> *const u8 {
    let cb = ZJITState::get_code_block();
    let code_ptr = gen_iseq_entry_point_body(cb, iseq);

    // Always mark the code region executable if asm.compile() has been used.
    // We need to do this even if code_ptr is null because, whether gen_entry() or
    // gen_function_stub() fails or not, gen_function() has already used asm.compile().
    cb.mark_all_executable();

    code_ptr.map_or(std::ptr::null(), |ptr| ptr.raw_ptr(cb))
}

/// Compile an entry point for a given ISEQ
fn gen_iseq_entry_point_body(cb: &mut CodeBlock, iseq: IseqPtr) -> Option<CodePtr> {
    // Compile ISEQ into High-level IR
    let function = compile_iseq(iseq)?;

    // Compile the High-level IR
    let Some((start_ptr, gc_offsets, jit)) = gen_function(cb, iseq, &function) else {
        debug!("Failed to compile iseq: gen_function failed: {}", iseq_get_location(iseq, 0));
        return None;
    };

    // Compile an entry point to the JIT code
    let Some(entry_ptr) = gen_entry(cb, iseq, &function, start_ptr) else {
        debug!("Failed to compile iseq: gen_entry failed: {}", iseq_get_location(iseq, 0));
        return None;
    };

    // Stub callee ISEQs for JIT-to-JIT calls
    for (branch, callee_iseq) in jit.branch_iseqs.into_iter() {
        gen_iseq_branch(cb, callee_iseq, iseq, branch)?;
    }

    // Remember the block address to reuse it later
    let payload = get_or_create_iseq_payload(iseq);
    payload.start_ptr = Some(start_ptr);
    append_gc_offsets(iseq, &gc_offsets);

    // Return a JIT code address
    Some(entry_ptr)
}

/// Stub a branch for a JIT-to-JIT call
fn gen_iseq_branch(cb: &mut CodeBlock, iseq: IseqPtr, caller_iseq: IseqPtr, branch: Rc<Branch>) -> Option<()> {
    // Compile a function stub
    let Some((stub_ptr, gc_offsets)) = gen_function_stub(cb, iseq, branch.clone()) else {
        // Failed to compile the stub. Bail out of compiling the caller ISEQ.
        debug!("Failed to compile iseq: could not compile stub: {} -> {}",
               iseq_get_location(caller_iseq, 0), iseq_get_location(iseq, 0));
        return None;
    };
    append_gc_offsets(iseq, &gc_offsets);

    // Update the JIT-to-JIT call to call the stub
    let stub_addr = stub_ptr.raw_ptr(cb);
    branch.regenerate(cb, |asm| {
        asm_comment!(asm, "call function stub: {}", iseq_get_location(iseq, 0));
        asm.ccall(stub_addr, vec![]);
    });
    Some(())
}

/// Write an entry to the perf map in /tmp
fn register_with_perf(iseq_name: String, start_ptr: usize, code_size: usize) {
    use std::io::Write;
    let perf_map = format!("/tmp/perf-{}.map", std::process::id());
    let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(&perf_map) else {
        debug!("Failed to open perf map file: {perf_map}");
        return;
    };
    let Ok(_) = writeln!(file, "{:#x} {:#x} zjit::{}", start_ptr, code_size, iseq_name) else {
        debug!("Failed to write {iseq_name} to perf map file: {perf_map}");
        return;
    };
}

/// Compile a JIT entry
fn gen_entry(cb: &mut CodeBlock, iseq: IseqPtr, function: &Function, function_ptr: CodePtr) -> Option<CodePtr> {
    // Set up registers for CFP, EC, SP, and basic block arguments
    let mut asm = Assembler::new();
    gen_entry_prologue(&mut asm, iseq);
    gen_entry_params(&mut asm, iseq, function.block(BlockId(0)));

    // Jump to the first block using a call instruction
    asm.ccall(function_ptr.raw_ptr(cb) as *const u8, vec![]);

    // Restore registers for CFP, EC, and SP after use
    asm_comment!(asm, "return to the interpreter");
    asm.frame_teardown(lir::JIT_PRESERVED_REGS);
    asm.cret(C_RET_OPND);

    if get_option!(dump_lir) {
        println!("LIR:\nJIT entry for {}:\n{:?}", iseq_name(iseq), asm);
    }

    let result = asm.compile(cb).map(|(start_ptr, _)| start_ptr);
    if let Some(start_addr) = result {
        if get_option!(perf) {
            let start_ptr = start_addr.raw_ptr(cb) as usize;
            let end_ptr = cb.get_write_ptr().raw_ptr(cb) as usize;
            let code_size = end_ptr - start_ptr;
            let iseq_name = iseq_get_location(iseq, 0);
            register_with_perf(format!("entry for {iseq_name}"), start_ptr, code_size);
        }
    }
    result
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
    if let Some((start_ptr, gc_offsets, jit)) = result {
        payload.start_ptr = Some(start_ptr);
        append_gc_offsets(iseq, &gc_offsets);
        Some((start_ptr, jit.branch_iseqs))
    } else {
        None
    }
}

/// Compile a function
fn gen_function(cb: &mut CodeBlock, iseq: IseqPtr, function: &Function) -> Option<(CodePtr, Vec<CodePtr>, JITState)> {
    let c_stack_slots = max_num_params(function).saturating_sub(ALLOC_REGS.len());
    let mut jit = JITState::new(iseq, function.num_insns(), function.num_blocks(), c_stack_slots);
    let mut asm = Assembler::new();

    // Compile each basic block
    let reverse_post_order = function.rpo();
    for &block_id in reverse_post_order.iter() {
        let block = function.block(block_id);
        asm_comment!(
            asm, "{block_id}({}): {}",
            block.params().map(|param| format!("{param}")).collect::<Vec<_>>().join(", "),
            iseq_get_location(iseq, block.insn_idx),
        );

        // Write a label to jump to the basic block
        let label = jit.get_label(&mut asm, block_id);
        asm.write_label(label);

        // Set up the frame at the first block. :bb0-prologue:
        if block_id == BlockId(0) {
            asm.frame_setup(&[], jit.c_stack_slots);
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
        // Make sure the last patch point has enough space to insert a jump
        asm.pad_patch_point();
    }

    if get_option!(dump_lir) {
        println!("LIR:\nfn {}:\n{:?}", iseq_name(iseq), asm);
    }

    // Generate code if everything can be compiled
    let result = asm.compile(cb).map(|(start_ptr, gc_offsets)| (start_ptr, gc_offsets, jit));
    if let Some((start_ptr, _, _)) = result {
        if get_option!(perf) {
            let start_usize = start_ptr.raw_ptr(cb) as usize;
            let end_usize = cb.get_write_ptr().raw_ptr(cb) as usize;
            let code_size = end_usize - start_usize;
            let iseq_name = iseq_get_location(iseq, 0);
            register_with_perf(iseq_name, start_usize, code_size);
        }
        if ZJITState::should_log_compiled_iseqs() {
            let iseq_name = iseq_get_location(iseq, 0);
            ZJITState::log_compile(iseq_name);
        }
    }
    result
}

/// Compile an instruction
fn gen_insn(cb: &mut CodeBlock, jit: &mut JITState, asm: &mut Assembler, function: &Function, insn_id: InsnId, insn: &Insn) -> Option<()> {
    // Convert InsnId to lir::Opnd
    macro_rules! opnd {
        ($insn_id:ident) => {
            jit.get_opnd(*$insn_id)?
        };
    }

    macro_rules! opnds {
        ($insn_ids:ident) => {
            {
                Option::from_iter($insn_ids.iter().map(|insn_id| jit.get_opnd(*insn_id)))?
            }
        };
    }

    if !matches!(*insn, Insn::Snapshot { .. }) {
        asm_comment!(asm, "Insn: {insn_id} {insn}");
    }

    let out_opnd = match insn {
        Insn::Const { val: Const::Value(val) } => gen_const(*val),
        Insn::NewArray { elements, state } => gen_new_array(asm, opnds!(elements), &function.frame_state(*state)),
        Insn::NewHash { elements, state } => gen_new_hash(jit, asm, elements, &function.frame_state(*state))?,
        Insn::NewRange { low, high, flag, state } => gen_new_range(asm, opnd!(low), opnd!(high), *flag, &function.frame_state(*state)),
        Insn::ArrayDup { val, state } => gen_array_dup(asm, opnd!(val), &function.frame_state(*state)),
        Insn::StringCopy { val, chilled } => gen_string_copy(asm, opnd!(val), *chilled),
        Insn::Param { idx } => unreachable!("block.insns should not have Insn::Param({idx})"),
        Insn::Snapshot { .. } => return Some(()), // we don't need to do anything for this instruction at the moment
        Insn::Jump(branch) => return gen_jump(jit, asm, branch),
        Insn::IfTrue { val, target } => return gen_if_true(jit, asm, opnd!(val), target),
        Insn::IfFalse { val, target } => return gen_if_false(jit, asm, opnd!(val), target),
        Insn::SendWithoutBlock { cd, state, self_val, args, .. } => gen_send_without_block(jit, asm, *cd, &function.frame_state(*state), opnd!(self_val), opnds!(args))?,
        // Give up SendWithoutBlockDirect for 6+ args since asm.ccall() doesn't support it.
        Insn::SendWithoutBlockDirect { cd, state, self_val, args, .. } if args.len() + 1 > C_ARG_OPNDS.len() => // +1 for self
            gen_send_without_block(jit, asm, *cd, &function.frame_state(*state), opnd!(self_val), opnds!(args))?,
        Insn::SendWithoutBlockDirect { cme, iseq, self_val, args, state, .. } => gen_send_without_block_direct(cb, jit, asm, *cme, *iseq, opnd!(self_val), opnds!(args), &function.frame_state(*state))?,
        Insn::InvokeBuiltin { bf, args, state, .. } => gen_invokebuiltin(jit, asm, &function.frame_state(*state), bf, opnds!(args))?,
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
        Insn::FixnumAnd { left, right } => gen_fixnum_and(asm, opnd!(left), opnd!(right))?,
        Insn::FixnumOr { left, right } => gen_fixnum_or(asm, opnd!(left), opnd!(right))?,
        Insn::IsNil { val } => gen_isnil(asm, opnd!(val))?,
        Insn::Test { val } => gen_test(asm, opnd!(val))?,
        Insn::GuardType { val, guard_type, state } => gen_guard_type(jit, asm, opnd!(val), *guard_type, &function.frame_state(*state))?,
        Insn::GuardBitEquals { val, expected, state } => gen_guard_bit_equals(jit, asm, opnd!(val), *expected, &function.frame_state(*state))?,
        Insn::PatchPoint { invariant, state } => return gen_patch_point(jit, asm, invariant, &function.frame_state(*state)),
        Insn::CCall { cfun, args, name: _, return_type: _, elidable: _ } => gen_ccall(asm, *cfun, opnds!(args))?,
        Insn::GetIvar { self_val, id, state: _ } => gen_getivar(asm, opnd!(self_val), *id),
        Insn::SetGlobal { id, val, state: _ } => return Some(gen_setglobal(asm, *id, opnd!(val))),
        Insn::GetGlobal { id, state: _ } => gen_getglobal(asm, *id),
        &Insn::GetLocal { ep_offset, level } => gen_getlocal_with_ep(asm, ep_offset, level)?,
        Insn::SetLocal { val, ep_offset, level } => return gen_setlocal_with_ep(asm, opnd!(val), *ep_offset, *level),
        Insn::GetConstantPath { ic, state } => gen_get_constant_path(jit, asm, *ic, &function.frame_state(*state))?,
        Insn::SetIvar { self_val, id, val, state: _ } => return gen_setivar(asm, opnd!(self_val), *id, opnd!(val)),
        Insn::SideExit { state, reason } => return gen_side_exit(jit, asm, reason, &function.frame_state(*state)),
        Insn::PutSpecialObject { value_type } => gen_putspecialobject(asm, *value_type),
        Insn::AnyToString { val, str, state } => gen_anytostring(asm, opnd!(val), opnd!(str), &function.frame_state(*state))?,
        Insn::Defined { op_type, obj, pushval, v } => gen_defined(jit, asm, *op_type, *obj, *pushval, opnd!(v))?,
        &Insn::IncrCounter(counter) => return Some(gen_incr_counter(asm, counter)),
        Insn::ArrayExtend { .. }
        | Insn::ArrayMax { .. }
        | Insn::ArrayPush { .. }
        | Insn::DefinedIvar { .. }
        | Insn::FixnumDiv { .. }
        | Insn::FixnumMod { .. }
        | Insn::HashDup { .. }
        | Insn::ObjToString { .. }
        | Insn::Send { .. }
        | Insn::StringIntern { .. }
        | Insn::Throw { .. }
        | Insn::ToArray { .. }
        | Insn::ToNewArray { .. }
        | Insn::Const { .. }
        => {
            debug!("ZJIT: gen_function: unexpected insn {insn}");
            return None;
        }
    };

    assert!(insn.has_output(), "Cannot write LIR output of HIR instruction with no output: {insn}");

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

/// Get a local variable from a higher scope or the heap. `local_ep_offset` is in number of VALUEs.
/// We generate this instruction with level=0 only when the local variable is on the heap, so we
/// can't optimize the level=0 case using the SP register.
fn gen_getlocal_with_ep(asm: &mut Assembler, local_ep_offset: u32, level: u32) -> Option<lir::Opnd> {
    let ep = gen_get_ep(asm, level);
    let offset = -(SIZEOF_VALUE_I32 * i32::try_from(local_ep_offset).ok()?);
    Some(asm.load(Opnd::mem(64, ep, offset)))
}

/// Set a local variable from a higher scope or the heap. `local_ep_offset` is in number of VALUEs.
/// We generate this instruction with level=0 only when the local variable is on the heap, so we
/// can't optimize the level=0 case using the SP register.
fn gen_setlocal_with_ep(asm: &mut Assembler, val: Opnd, local_ep_offset: u32, level: u32) -> Option<()> {
    let ep = gen_get_ep(asm, level);
    match val {
        // If we're writing a constant, non-heap VALUE, do a raw memory write without
        // running write barrier.
        lir::Opnd::Value(const_val) if const_val.special_const_p() => {
            let offset = -(SIZEOF_VALUE_I32 * i32::try_from(local_ep_offset).ok()?);
            asm.mov(Opnd::mem(64, ep, offset), val);
        }
        // We're potentially writing a reference to an IMEMO/env object,
        // so take care of the write barrier with a function.
        _ => {
            let local_index = c_int::try_from(local_ep_offset).ok().and_then(|idx| idx.checked_mul(-1))?;
            asm_ccall!(asm, rb_vm_env_write, ep, local_index.into(), val);
        }
    }
    Some(())
}

fn gen_get_constant_path(jit: &JITState, asm: &mut Assembler, ic: *const iseq_inline_constant_cache, state: &FrameState) -> Option<Opnd> {
    unsafe extern "C" {
        fn rb_vm_opt_getconstant_path(ec: EcPtr, cfp: CfpPtr, ic: *const iseq_inline_constant_cache) -> VALUE;
    }

    // Anything could be called on const_missing
    gen_prepare_non_leaf_call(jit, asm, state)?;

    Some(asm_ccall!(asm, rb_vm_opt_getconstant_path, EC, CFP, Opnd::const_ptr(ic)))
}

fn gen_invokebuiltin(jit: &JITState, asm: &mut Assembler, state: &FrameState, bf: &rb_builtin_function, args: Vec<Opnd>) -> Option<lir::Opnd> {
    // Ensure we have enough room fit ec, self, and arguments
    // TODO remove this check when we have stack args (we can use Time.new to test it)
    if bf.argc + 2 > (C_ARG_OPNDS.len() as i32) {
        return None;
    }

    // Anything can happen inside builtin functions
    gen_prepare_non_leaf_call(jit, asm, state)?;

    let mut cargs = vec![EC];
    cargs.extend(args);

    let val = asm.ccall(bf.func_ptr as *const u8, cargs);

    Some(val)
}

/// Record a patch point that should be invalidated on a given invariant
fn gen_patch_point(jit: &mut JITState, asm: &mut Assembler, invariant: &Invariant, state: &FrameState) -> Option<()> {
    let label = asm.new_label("patch_point").unwrap_label();
    let invariant = invariant.clone();

    // Compile a side exit. Fill nop instructions if the last patch point is too close.
    asm.patch_point(build_side_exit(jit, state, PatchPoint(invariant), Some(label))?);

    // Remember the current address as a patch point
    asm.pos_marker(move |code_ptr, cb| {
        match invariant {
            Invariant::BOPRedefined { klass, bop } => {
                let side_exit_ptr = cb.resolve_label(label);
                track_bop_assumption(klass, bop, code_ptr, side_exit_ptr);
            }
            Invariant::MethodRedefined { klass: _, method: _, cme } => {
                let side_exit_ptr = cb.resolve_label(label);
                track_cme_assumption(cme, code_ptr, side_exit_ptr);
            }
            Invariant::StableConstantNames { idlist } => {
                let side_exit_ptr = cb.resolve_label(label);
                track_stable_constant_names_assumption(idlist, code_ptr, side_exit_ptr);
            }
            _ => {
                debug!("ZJIT: gen_patch_point: unimplemented invariant {invariant:?}");
                return;
            }
        }
    });
    Some(())
}

/// Lowering for [`Insn::CCall`]. This is a low-level raw call that doesn't know
/// anything about the callee, so handling for e.g. GC safety is dealt with elsewhere.
fn gen_ccall(asm: &mut Assembler, cfun: *const u8, args: Vec<Opnd>) -> Option<lir::Opnd> {
    Some(asm.ccall(cfun, args))
}

/// Emit an uncached instance variable lookup
fn gen_getivar(asm: &mut Assembler, recv: Opnd, id: ID) -> Opnd {
    asm_ccall!(asm, rb_ivar_get, recv, id.0.into())
}

/// Emit an uncached instance variable store
fn gen_setivar(asm: &mut Assembler, recv: Opnd, id: ID, val: Opnd) -> Option<()> {
    asm_ccall!(asm, rb_ivar_set, recv, id.0.into(), val);
    Some(())
}

/// Look up global variables
fn gen_getglobal(asm: &mut Assembler, id: ID) -> Opnd {
    asm_ccall!(asm, rb_gvar_get, id.0.into())
}

/// Set global variables
fn gen_setglobal(asm: &mut Assembler, id: ID, val: Opnd) {
    asm_ccall!(asm, rb_gvar_set, id.0.into(), val);
}

/// Side-exit into the interpreter
fn gen_side_exit(jit: &mut JITState, asm: &mut Assembler, reason: &SideExitReason, state: &FrameState) -> Option<()> {
    asm.jmp(side_exit(jit, state, *reason)?);
    Some(())
}

/// Emit a special object lookup
fn gen_putspecialobject(asm: &mut Assembler, value_type: SpecialObjectType) -> Opnd {
    // Get the EP of the current CFP and load it into a register
    let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
    let ep_reg = asm.load(ep_opnd);

    asm_ccall!(asm, rb_vm_get_special_object, ep_reg, Opnd::UImm(u64::from(value_type)))
}

/// Compile an interpreter entry block to be inserted into an ISEQ
fn gen_entry_prologue(asm: &mut Assembler, iseq: IseqPtr) {
    asm_comment!(asm, "ZJIT entry point: {}", iseq_get_location(iseq, 0));
    // Save the registers we'll use for CFP, EP, SP
    asm.frame_setup(lir::JIT_PRESERVED_REGS, 0);

    // EC and CFP are passed as arguments
    asm.mov(EC, C_ARG_OPNDS[0]);
    asm.mov(CFP, C_ARG_OPNDS[1]);

    // Load the current SP from the CFP into REG_SP
    asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));

    // TODO: Support entry chain guard when ISEQ has_opt
}

/// Assign method arguments to basic block arguments at JIT entry
fn gen_entry_params(asm: &mut Assembler, iseq: IseqPtr, entry_block: &Block) {
    let num_params = entry_block.params().len() - 1; // -1 to exclude self
    if num_params > 0 {
        asm_comment!(asm, "set method params: {num_params}");

        // Fill basic block parameters.
        // Doing it in reverse is load-bearing. High index params have memory slots that might
        // require using a register to fill. Filling them first avoids clobbering.
        for idx in (0..num_params).rev() {
            let param = param_opnd(idx + 1); // +1 for self
            let local = gen_entry_param(asm, iseq, idx);

            // Funky offset adjustment to write into the native stack frame of the
            // HIR function we'll be calling into. This only makes sense in context
            // of the schedule of instructions in gen_entry() for the JIT entry point.
            //
            // The entry point needs to load VALUEs into native stack slots _before_ the
            // frame containing the slots exists. So, we anticipate the stack frame size
            // of the Function and subtract offsets based on that.
            //
            // native SP at entry point ─────►┌────────────┐   Native SP grows downwards
            //                                │            │ ↓ on all arches we support.
            //                         SP-0x8 ├────────────┤
            //                                │            │
            // where native SP         SP-0x10├────────────┤
            // would be while                 │            │
            // the HIR function ────────────► └────────────┘
            // is running
            match param {
                Opnd::Mem(lir::Mem { base: _, disp, num_bits }) => {
                    let param_slot = Opnd::mem(num_bits, NATIVE_STACK_PTR, disp - Assembler::frame_size());
                    asm.mov(param_slot, local);
                }
                // Prepare for parallel move for locals in registers
                reg @ Opnd::Reg(_) => {
                    asm.load_into(reg, local);
                }
                _ => unreachable!("on entry, params are either in memory or in reg. Got {param:?}")
            }

            // Assign local variables to the basic block arguments
        }
    }
    asm.load_into(param_opnd(SELF_PARAM_IDX), Opnd::mem(VALUE_BITS, CFP, RUBY_OFFSET_CFP_SELF));
}

/// Set branch params to basic block arguments
fn gen_branch_params(jit: &mut JITState, asm: &mut Assembler, branch: &BranchEdge) -> Option<()> {
    if !branch.args.is_empty() {
        asm_comment!(asm, "set branch params: {}", branch.args.len());
        let mut moves: Vec<(Reg, Opnd)> = vec![];
        for (idx, &arg) in branch.args.iter().enumerate() {
            match param_opnd(idx) {
                Opnd::Reg(reg) => {
                    // If a parameter is a register, we need to parallel-move it
                    moves.push((reg, jit.get_opnd(arg)?));
                },
                param => {
                    // If a parameter is memory, we set it beforehand
                    asm.mov(param, jit.get_opnd(arg)?);
                }
            }
        }
        asm.parallel_mov(moves);
    }
    Some(())
}

/// Get a method parameter on JIT entry. As of entry, whether EP is escaped or not solely
/// depends on the ISEQ type.
fn gen_entry_param(asm: &mut Assembler, iseq: IseqPtr, local_idx: usize) -> lir::Opnd {
    let ep_offset = local_idx_to_ep_offset(iseq, local_idx);

    // If the ISEQ does not escape EP, we can optimize the local variable access using the SP register.
    if !iseq_entry_escapes_ep(iseq) {
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
    // Allocate a register or a stack slot
    match param_opnd(idx) {
        // If it's a register, insert LiveReg instruction to reserve the register
        // in the register pool for register allocation.
        param @ Opnd::Reg(_) => asm.live_reg_opnd(param),
        param => param,
    }
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
    cd: *const rb_call_data,
    state: &FrameState,
    self_val: Opnd,
    args: Vec<Opnd>,
) -> Option<lir::Opnd> {
    gen_spill_locals(jit, asm, state)?;
    // Spill the receiver and the arguments onto the stack.
    // They need to be on the interpreter stack to let the interpreter access them.
    // TODO: Avoid spilling operands that have been spilled before.
    // TODO: Despite https://github.com/ruby/ruby/pull/13468, Kokubun thinks this should
    // spill the whole stack in case it raises an exception. The HIR might need to change
    // for opt_aref_with, which pushes to the stack in the middle of the instruction.
    asm_comment!(asm, "spill receiver and arguments");
    for (idx, &val) in [self_val].iter().chain(args.iter()).enumerate() {
        // Currently, we don't move the SP register. So it's equal to the base pointer.
        let stack_opnd = Opnd::mem(64, SP, idx as i32 * SIZEOF_VALUE_I32);
        asm.mov(stack_opnd, val);
    }

    // Save PC and SP
    gen_save_pc(asm, state);
    gen_save_sp(asm, 1 + args.len()); // +1 for receiver

    asm_comment!(asm, "call #{} with dynamic dispatch", ruby_call_method_name(cd));
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
    args: Vec<Opnd>,
    state: &FrameState,
) -> Option<lir::Opnd> {
    // Save cfp->pc and cfp->sp for the caller frame
    gen_save_pc(asm, state);
    gen_save_sp(asm, state.stack().len() - args.len() - 1); // -1 for receiver

    gen_spill_locals(jit, asm, state)?;
    gen_spill_stack(jit, asm, state)?;

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
    let sp_offset = (state.stack().len() + local_size - args.len() + VM_ENV_DATA_SIZE as usize) * SIZEOF_VALUE;
    let new_sp = asm.add(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // Set up arguments
    let mut c_args = vec![recv];
    c_args.extend(args);

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
    asm_comment!(asm, "side-exit if callee side-exits");
    asm.cmp(ret, Qundef.into());
    // Restore the C stack pointer on exit
    asm.je(Target::SideExit { context: None, reason: CalleeSideExit, label: None });

    asm_comment!(asm, "restore SP register for the caller");
    let new_sp = asm.sub(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    Some(ret)
}

/// Compile a string resurrection
fn gen_string_copy(asm: &mut Assembler, recv: Opnd, chilled: bool) -> Opnd {
    // TODO: split rb_ec_str_resurrect into separate functions
    let chilled = if chilled { Opnd::Imm(1) } else { Opnd::Imm(0) };
    asm_ccall!(asm, rb_ec_str_resurrect, EC, recv, chilled)
}

/// Compile an array duplication instruction
fn gen_array_dup(
    asm: &mut Assembler,
    val: lir::Opnd,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_call_with_gc(asm, state);

    asm_ccall!(asm, rb_ary_resurrect, val)
}

/// Compile a new array instruction
fn gen_new_array(
    asm: &mut Assembler,
    elements: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_call_with_gc(asm, state);

    let length: ::std::os::raw::c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

    let new_array = asm_ccall!(asm, rb_ary_new_capa, length.into());

    for val in elements {
        asm_ccall!(asm, rb_ary_push, new_array, val);
    }

    new_array
}

/// Compile a new hash instruction
fn gen_new_hash(
    jit: &mut JITState,
    asm: &mut Assembler,
    elements: &Vec<(InsnId, InsnId)>,
    state: &FrameState,
) -> Option<lir::Opnd> {
    gen_prepare_non_leaf_call(jit, asm, state)?;

    asm_comment!(asm, "call rb_hash_new");
    let cap: ::std::os::raw::c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");
    let new_hash = asm_ccall!(asm, rb_hash_new_with_size, lir::Opnd::Imm(cap));

    for (key_id, val_id) in elements.iter() {
        let key = jit.get_opnd(*key_id)?;
        let val = jit.get_opnd(*val_id)?;
        asm_comment!(asm, "call rb_hash_aset");
        asm_ccall!(asm, rb_hash_aset, new_hash, key, val);
    }

    Some(new_hash)
}

/// Compile a new range instruction
fn gen_new_range(
    asm: &mut Assembler,
    low: lir::Opnd,
    high: lir::Opnd,
    flag: RangeType,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_call_with_gc(asm, state);

    // Call rb_range_new(low, high, flag)
    asm_ccall!(asm, rb_range_new, low, high, (flag as i64).into())
}

/// Compile code that exits from JIT code with a return value
fn gen_return(asm: &mut Assembler, val: lir::Opnd) -> Option<()> {
    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    asm_comment!(asm, "pop stack frame");
    let incr_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, incr_cfp);
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // Order here is important. Because we're about to tear down the frame,
    // we need to load the return value, which might be part of the frame.
    asm.load_into(C_RET_OPND, val);

    // Return from the function
    asm.frame_teardown(&[]); // matching the setup in :bb0-prologue:
    asm.cret(C_RET_OPND);
    Some(())
}

/// Compile Fixnum + Fixnum
fn gen_fixnum_add(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Add left + right and test for overflow
    let left_untag = asm.sub(left, Opnd::Imm(1));
    let out_val = asm.add(left_untag, right);
    asm.jo(side_exit(jit, state, FixnumAddOverflow)?);

    Some(out_val)
}

/// Compile Fixnum - Fixnum
fn gen_fixnum_sub(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    // Subtract left - right and test for overflow
    let val_untag = asm.sub(left, right);
    asm.jo(side_exit(jit, state, FixnumSubOverflow)?);
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
    asm.jo_mul(side_exit(jit, state, FixnumMultOverflow)?);
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

/// Compile Fixnum & Fixnum
fn gen_fixnum_and(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    Some(asm.and(left, right))
}

/// Compile Fixnum | Fixnum
fn gen_fixnum_or(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> Option<lir::Opnd> {
    Some(asm.or(left, right))
}

// Compile val == nil
fn gen_isnil(asm: &mut Assembler, val: lir::Opnd) -> Option<lir::Opnd> {
    asm.cmp(val, Qnil.into());
    // TODO: Implement and use setcc
    Some(asm.csel_e(Opnd::Imm(1), Opnd::Imm(0)))
}

fn gen_anytostring(asm: &mut Assembler, val: lir::Opnd, str: lir::Opnd, state: &FrameState) -> Option<lir::Opnd> {
    gen_prepare_call_with_gc(asm, state);

    Some(asm_ccall!(asm, rb_obj_as_string_result, str, val))
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
    if guard_type.is_subtype(types::Fixnum) {
        asm.test(val, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));
        asm.jz(side_exit(jit, state, GuardType(guard_type))?);
    } else if guard_type.is_subtype(types::Flonum) {
        // Flonum: (val & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG
        let masked = asm.and(val, Opnd::UImm(RUBY_FLONUM_MASK as u64));
        asm.cmp(masked, Opnd::UImm(RUBY_FLONUM_FLAG as u64));
        asm.jne(side_exit(jit, state, GuardType(guard_type))?);
    } else if guard_type.is_subtype(types::StaticSymbol) {
        // Static symbols have (val & 0xff) == RUBY_SYMBOL_FLAG
        // Use 8-bit comparison like YJIT does
        asm.cmp(val.with_num_bits(8).unwrap(), Opnd::UImm(RUBY_SYMBOL_FLAG as u64));
        asm.jne(side_exit(jit, state, GuardType(guard_type))?);
    } else if guard_type.is_subtype(types::NilClass) {
        asm.cmp(val, Qnil.into());
        asm.jne(side_exit(jit, state, GuardType(guard_type))?);
    } else if guard_type.is_subtype(types::TrueClass) {
        asm.cmp(val, Qtrue.into());
        asm.jne(side_exit(jit, state, GuardType(guard_type))?);
    } else if guard_type.is_subtype(types::FalseClass) {
        assert!(Qfalse.as_i64() == 0);
        asm.test(val, val);
        asm.jne(side_exit(jit, state, GuardType(guard_type))?);
    } else if let Some(expected_class) = guard_type.runtime_exact_ruby_class() {
        asm_comment!(asm, "guard exact class");

        // Get the class of the value
        let klass = asm.ccall(rb_yarv_class_of as *const u8, vec![val]);

        asm.cmp(klass, Opnd::Value(expected_class));
        asm.jne(side_exit(jit, state, GuardType(guard_type))?);
    } else {
        unimplemented!("unsupported type: {guard_type}");
    }
    Some(val)
}

/// Compile an identity check with a side exit
fn gen_guard_bit_equals(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, expected: VALUE, state: &FrameState) -> Option<lir::Opnd> {
    asm.cmp(val, Opnd::Value(expected));
    asm.jnz(side_exit(jit, state, GuardBitEquals(expected))?);
    Some(val)
}

/// Generate code that increments a counter in ZJIT stats
fn gen_incr_counter(asm: &mut Assembler, counter: Counter) -> () {
    let ptr = counter_ptr(counter);
    let ptr_reg = asm.load(Opnd::const_ptr(ptr as *const u8));
    let counter_opnd = Opnd::mem(64, ptr_reg, 0);

    // Increment and store the updated value
    asm.incr_counter(counter_opnd, Opnd::UImm(1));
}

/// Save the incremented PC on the CFP.
/// This is necessary when callees can raise or allocate.
fn gen_save_pc(asm: &mut Assembler, state: &FrameState) {
    let opcode: usize = state.get_opcode().try_into().unwrap();
    let next_pc: *const VALUE = unsafe { state.pc.offset(insn_len(opcode) as isize) };

    asm_comment!(asm, "save PC to CFP");
    asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), Opnd::const_ptr(next_pc));
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

/// Spill locals onto the stack.
fn gen_spill_locals(jit: &JITState, asm: &mut Assembler, state: &FrameState) -> Option<()> {
    // TODO: Avoid spilling locals that have been spilled before and not changed.
    asm_comment!(asm, "spill locals");
    for (idx, &insn_id) in state.locals().enumerate() {
        asm.mov(Opnd::mem(64, SP, (-local_idx_to_ep_offset(jit.iseq, idx) - 1) * SIZEOF_VALUE_I32), jit.get_opnd(insn_id)?);
    }
    Some(())
}

/// Spill the virtual stack onto the stack.
fn gen_spill_stack(jit: &JITState, asm: &mut Assembler, state: &FrameState) -> Option<()> {
    // This function does not call gen_save_sp() at the moment because
    // gen_send_without_block_direct() spills stack slots above SP for arguments.
    asm_comment!(asm, "spill stack");
    for (idx, &insn_id) in state.stack().enumerate() {
        asm.mov(Opnd::mem(64, SP, idx as i32 * SIZEOF_VALUE_I32), jit.get_opnd(insn_id)?);
    }
    Some(())
}

/// Prepare for calling a C function that may call an arbitrary method.
/// Use gen_prepare_call_with_gc() if the method is leaf but allocates objects.
#[must_use]
fn gen_prepare_non_leaf_call(jit: &JITState, asm: &mut Assembler, state: &FrameState) -> Option<()> {
    // TODO: Lazily materialize caller frames when needed
    // Save PC for backtraces and allocation tracing
    gen_save_pc(asm, state);

    // Save SP and spill the virtual stack in case it raises an exception
    // and the interpreter uses the stack for handling the exception
    gen_save_sp(asm, state.stack().len());
    gen_spill_stack(jit, asm, state)?;

    // Spill locals in case the method looks at caller Bindings
    gen_spill_locals(jit, asm, state)?;
    Some(())
}

/// Prepare for calling a C function that may allocate objects and trigger GC.
/// Use gen_prepare_non_leaf_call() if it may also call an arbitrary method.
fn gen_prepare_call_with_gc(asm: &mut Assembler, state: &FrameState) {
    // Save PC for allocation tracing
    gen_save_pc(asm, state);
    // Unlike YJIT, we don't need to save the stack to protect them from GC
    // because the backend spills all live registers onto the C stack on asm.ccall().
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

/// Return an operand we use for the basic block argument at a given index
fn param_opnd(idx: usize) -> Opnd {
    // To simplify the implementation, allocate a fixed register or a stack slot for each basic block argument for now.
    // Note that this is implemented here as opposed to automatically inside LIR machineries.
    // TODO: Allow allocating arbitrary registers for basic block arguments
    if idx < ALLOC_REGS.len() {
        Opnd::Reg(ALLOC_REGS[idx])
    } else {
        Opnd::mem(64, NATIVE_BASE_PTR, (idx - ALLOC_REGS.len() + 1) as i32 * -SIZEOF_VALUE_I32)
    }
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
            let name = crate::cruby::iseq_get_location(iseq, 0);
            debug!("ZJIT: iseq_to_hir: {err:?}: {name}");
            return None;
        }
    };
    function.optimize();
    if let Err(err) = function.validate() {
        debug!("ZJIT: compile_iseq: {err:?}");
        return None;
    }
    Some(function)
}

/// Build a Target::SideExit for non-PatchPoint instructions
fn side_exit(jit: &mut JITState, state: &FrameState, reason: SideExitReason) -> Option<Target> {
    build_side_exit(jit, state, reason, None)
}

/// Build a Target::SideExit out of a FrameState
fn build_side_exit(jit: &mut JITState, state: &FrameState, reason: SideExitReason, label: Option<Label>) -> Option<Target> {
    let mut stack = Vec::new();
    for &insn_id in state.stack() {
        stack.push(jit.get_opnd(insn_id)?);
    }

    let mut locals = Vec::new();
    for &insn_id in state.locals() {
        locals.push(jit.get_opnd(insn_id)?);
    }

    let target = Target::SideExit {
        context: Some(SideExitContext {
            pc: state.pc,
            stack,
            locals,
        }),
        reason,
        label,
    };
    Some(target)
}

/// Return true if a given ISEQ is known to escape EP to the heap on entry.
///
/// As of vm_push_frame(), EP is always equal to BP. However, after pushing
/// a frame, some ISEQ setups call vm_bind_update_env(), which redirects EP.
fn iseq_entry_escapes_ep(iseq: IseqPtr) -> bool {
    match unsafe { get_iseq_body_type(iseq) } {
        // <main> frame is always associated to TOPLEVEL_BINDING.
        ISEQ_TYPE_MAIN |
        // Kernel#eval uses a heap EP when a Binding argument is not nil.
        ISEQ_TYPE_EVAL => true,
        _ => false,
    }
}

/// Returne the maximum number of arguments for a block in a given function
fn max_num_params(function: &Function) -> usize {
    let reverse_post_order = function.rpo();
    reverse_post_order.iter().map(|&block_id| {
        let block = function.block(block_id);
        block.params().len()
    }).max().unwrap_or(0)
}

#[cfg(target_arch = "x86_64")]
macro_rules! c_callable {
    ($(#[$outer:meta])*
    fn $f:ident $args:tt $(-> $ret:ty)? $body:block) => {
        $(#[$outer])*
        extern "sysv64" fn $f $args $(-> $ret)? $body
    };
}
#[cfg(target_arch = "aarch64")]
macro_rules! c_callable {
    ($(#[$outer:meta])*
    fn $f:ident $args:tt $(-> $ret:ty)? $body:block) => {
        $(#[$outer])*
        extern "C" fn $f $args $(-> $ret)? $body
    };
}
pub(crate) use c_callable;

c_callable! {
    /// Generated code calls this function with the SysV calling convention.
    /// See [gen_function_stub].
    fn function_stub_hit(iseq: IseqPtr, branch_ptr: *const c_void, ec: EcPtr, sp: *mut VALUE) -> *const u8 {
        with_vm_lock(src_loc!(), || {
            // Get a pointer to compiled code or the side-exit trampoline
            let cb = ZJITState::get_code_block();
            let code_ptr = if let Some(code_ptr) = function_stub_hit_body(cb, iseq, branch_ptr) {
                code_ptr
            } else {
                // gen_push_frame() doesn't set PC and SP, so we need to set them for side-exit
                // TODO: We could generate code that sets PC/SP. Note that we'd still need to handle OOM.
                let cfp = unsafe { get_ec_cfp(ec) };
                let pc = unsafe { rb_iseq_pc_at_idx(iseq, 0) }; // TODO: handle opt_pc once supported
                unsafe { rb_set_cfp_pc(cfp, pc) };
                unsafe { rb_set_cfp_sp(cfp, sp) };

                // Exit to the interpreter
                ZJITState::get_stub_exit()
            };

            cb.mark_all_executable();
            code_ptr.raw_ptr(cb)
        })
    }
}

/// Compile an ISEQ for a function stub
fn function_stub_hit_body(cb: &mut CodeBlock, iseq: IseqPtr, branch_ptr: *const c_void) -> Option<CodePtr> {
    // Compile the stubbed ISEQ
    let Some((code_ptr, branch_iseqs)) = gen_iseq(cb, iseq) else {
        debug!("Failed to compile iseq: gen_iseq failed: {}", iseq_get_location(iseq, 0));
        return None;
    };

    // Stub callee ISEQs for JIT-to-JIT calls
    for (branch, callee_iseq) in branch_iseqs.into_iter() {
        gen_iseq_branch(cb, callee_iseq, iseq, branch)?;
    }

    // Update the stub to call the code pointer
    let branch = unsafe { Rc::from_raw(branch_ptr as *const Branch) };
    let code_addr = code_ptr.raw_ptr(cb);
    branch.regenerate(cb, |asm| {
        asm_comment!(asm, "call compiled function: {}", iseq_get_location(iseq, 0));
        asm.ccall(code_addr, vec![]);
    });

    Some(code_ptr)
}

/// Compile a stub for an ISEQ called by SendWithoutBlockDirect
/// TODO: Consider creating a trampoline to share some of the code among function stubs
fn gen_function_stub(cb: &mut CodeBlock, iseq: IseqPtr, branch: Rc<Branch>) -> Option<(CodePtr, Vec<CodePtr>)> {
    let mut asm = Assembler::new();
    asm_comment!(asm, "Stub: {}", iseq_get_location(iseq, 0));

    // Maintain alignment for x86_64, and set up a frame for arm64 properly
    asm.frame_setup(&[], 0);

    asm_comment!(asm, "preserve argument registers");
    for &reg in ALLOC_REGS.iter() {
        asm.cpush(Opnd::Reg(reg));
    }
    const { assert!(ALLOC_REGS.len() % 2 == 0, "x86_64 would need to push one more if we push an odd number of regs"); }

    // Compile the stubbed ISEQ
    let branch_addr = Rc::into_raw(branch);
    let jump_addr = asm_ccall!(asm, function_stub_hit,
        Opnd::Value(iseq.into()),
        Opnd::const_ptr(branch_addr as *const u8),
        EC,
        SP
    );
    asm.mov(Opnd::Reg(Assembler::SCRATCH_REG), jump_addr);

    asm_comment!(asm, "restore argument registers");
    for &reg in ALLOC_REGS.iter().rev() {
        asm.cpop_into(Opnd::Reg(reg));
    }

    // Discard the current frame since the JIT function will set it up again
    asm.frame_teardown(&[]);

    // Jump to SCRATCH_REG so that cpop_all() doesn't clobber it
    asm.jmp_opnd(Opnd::Reg(Assembler::SCRATCH_REG));
    asm.compile(cb)
}

/// Generate a trampoline that is used when a function stub fails to compile the ISEQ
pub fn gen_stub_exit(cb: &mut CodeBlock) -> Option<CodePtr> {
    let mut asm = Assembler::new();

    asm_comment!(asm, "exit from function stub");
    asm.frame_teardown(lir::JIT_PRESERVED_REGS);
    asm.cret(Qundef.into());

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        code_ptr
    })
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
