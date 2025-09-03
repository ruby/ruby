//! This module is for native code generation.

#![allow(clippy::let_and_return)]

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::ffi::{c_int, c_long, c_void};
use std::slice;

use crate::asm::Label;
use crate::backend::current::{Reg, ALLOC_REGS};
use crate::invariants::{track_bop_assumption, track_cme_assumption, track_single_ractor_assumption, track_stable_constant_names_assumption};
use crate::gc::{append_gc_offsets, get_or_create_iseq_payload, get_or_create_iseq_payload_ptr, IseqPayload, IseqStatus};
use crate::state::ZJITState;
use crate::stats::{exit_counter_for_compile_error, incr_counter, incr_counter_by, CompileError};
use crate::stats::{counter_ptr, with_time_stat, Counter, Counter::{compile_time_ns, exit_compile_error}};
use crate::{asm::CodeBlock, cruby::*, options::debug, virtualmem::CodePtr};
use crate::backend::lir::{self, asm_comment, asm_ccall, Assembler, Opnd, Target, CFP, C_ARG_OPNDS, C_RET_OPND, EC, NATIVE_STACK_PTR, NATIVE_BASE_PTR, SCRATCH_OPND, SP};
use crate::hir::{iseq_to_hir, Block, BlockId, BranchEdge, Invariant, RangeType, SideExitReason, SideExitReason::*, SpecialObjectType, SpecialBackrefSymbol, SELF_PARAM_IDX};
use crate::hir::{Const, FrameState, Function, Insn, InsnId, ParseError};
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

    /// ISEQ calls that need to be compiled later
    iseq_calls: Vec<Rc<RefCell<IseqCall>>>,

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
            iseq_calls: Vec::default(),
            c_stack_slots,
        }
    }

    /// Retrieve the output of a given instruction that has been compiled
    fn get_opnd(&self, insn_id: InsnId) -> lir::Opnd {
        self.opnds[insn_id.0].unwrap_or_else(|| panic!("Failed to get_opnd({insn_id})"))
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

/// CRuby API to compile a given ISEQ.
/// If jit_exception is true, compile JIT code for handling exceptions.
/// See jit_compile_exception() for details.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, jit_exception: bool) -> *const u8 {
    // Do not test the JIT code in HIR tests
    if cfg!(test) {
        return std::ptr::null();
    }

    // Take a lock to avoid writing to ISEQ in parallel with Ractors.
    // with_vm_lock() does nothing if the program doesn't use Ractors.
    with_vm_lock(src_loc!(), || {
        let cb = ZJITState::get_code_block();
        let mut code_ptr = with_time_stat(compile_time_ns, || gen_iseq_entry_point(cb, iseq, jit_exception));

        if let Err(err) = &code_ptr {
            // Assert that the ISEQ compiles if RubyVM::ZJIT.assert_compiles is enabled.
            // We assert only `jit_exception: false` cases until we support exception handlers.
            if ZJITState::assert_compiles_enabled() && !jit_exception {
                let iseq_location = iseq_get_location(iseq, 0);
                panic!("Failed to compile: {iseq_location}");
            }

            // For --zjit-stats, generate an entry that just increments exit_compilation_failure and exits
            if get_option!(stats) {
                code_ptr = gen_compile_error_counter(cb, err);
            }
        }

        // Always mark the code region executable if asm.compile() has been used.
        // We need to do this even if code_ptr is None because, whether gen_entry()
        // fails or not, gen_iseq() may have already used asm.compile().
        cb.mark_all_executable();

        code_ptr.map_or(std::ptr::null(), |ptr| ptr.raw_ptr(cb))
    })
}

/// Compile an entry point for a given ISEQ
fn gen_iseq_entry_point(cb: &mut CodeBlock, iseq: IseqPtr, jit_exception: bool) -> Result<CodePtr, CompileError> {
    // We don't support exception handlers yet
    if jit_exception {
        return Err(CompileError::ExceptionHandler);
    }

    // Compile ISEQ into High-level IR
    let function = compile_iseq(iseq).inspect_err(|_| {
        incr_counter!(failed_iseq_count);
    })?;

    // Compile the High-level IR
    let start_ptr = gen_iseq(cb, iseq, Some(&function)).inspect_err(|err| {
        debug!("{err:?}: gen_iseq failed: {}", iseq_get_location(iseq, 0));
    })?;

    // Compile an entry point to the JIT code
    gen_entry(cb, iseq, &function, start_ptr).inspect_err(|err| {
        debug!("{err:?}: gen_entry failed: {}", iseq_get_location(iseq, 0));
    })
}

/// Stub a branch for a JIT-to-JIT call
fn gen_iseq_call(cb: &mut CodeBlock, caller_iseq: IseqPtr, iseq_call: &Rc<RefCell<IseqCall>>) -> Result<(), CompileError> {
    // Compile a function stub
    let stub_ptr = gen_function_stub(cb, iseq_call.clone()).inspect_err(|err| {
        debug!("{err:?}: gen_function_stub failed: {} -> {}",
               iseq_get_location(caller_iseq, 0), iseq_get_location(iseq_call.borrow().iseq, 0));
    })?;

    // Update the JIT-to-JIT call to call the stub
    let stub_addr = stub_ptr.raw_ptr(cb);
    let iseq = iseq_call.borrow().iseq;
    iseq_call.borrow_mut().regenerate(cb, |asm| {
        asm_comment!(asm, "call function stub: {}", iseq_get_location(iseq, 0));
        asm.ccall(stub_addr, vec![]);
    });
    Ok(())
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
fn gen_entry(cb: &mut CodeBlock, iseq: IseqPtr, function: &Function, function_ptr: CodePtr) -> Result<CodePtr, CompileError> {
    // Set up registers for CFP, EC, SP, and basic block arguments
    let mut asm = Assembler::new();
    gen_entry_prologue(&mut asm, iseq);
    gen_entry_params(&mut asm, iseq, function.block(BlockId(0)));

    // Jump to the first block using a call instruction
    asm.ccall(function_ptr.raw_ptr(cb), vec![]);

    // Restore registers for CFP, EC, and SP after use
    asm_comment!(asm, "return to the interpreter");
    asm.frame_teardown(lir::JIT_PRESERVED_REGS);
    asm.cret(C_RET_OPND);

    if get_option!(dump_lir) {
        println!("LIR:\nJIT entry for {}:\n{:?}", iseq_name(iseq), asm);
    }

    let (code_ptr, gc_offsets) = asm.compile(cb)?;
    assert!(gc_offsets.is_empty());
    if get_option!(perf) {
        let start_ptr = code_ptr.raw_ptr(cb) as usize;
        let end_ptr = cb.get_write_ptr().raw_ptr(cb) as usize;
        let code_size = end_ptr - start_ptr;
        let iseq_name = iseq_get_location(iseq, 0);
        register_with_perf(format!("entry for {iseq_name}"), start_ptr, code_size);
    }
    Ok(code_ptr)
}

/// Compile an ISEQ into machine code if not compiled yet
fn gen_iseq(cb: &mut CodeBlock, iseq: IseqPtr, function: Option<&Function>) -> Result<CodePtr, CompileError> {
    // Return an existing pointer if it's already compiled
    let payload = get_or_create_iseq_payload(iseq);
    match &payload.status {
        IseqStatus::Compiled(start_ptr) => return Ok(*start_ptr),
        IseqStatus::CantCompile(err) => return Err(err.clone()),
        IseqStatus::NotCompiled => {},
    }

    // Compile the ISEQ
    let code_ptr = gen_iseq_body(cb, iseq, function, payload);
    match &code_ptr {
        Ok(start_ptr) => {
            payload.status = IseqStatus::Compiled(*start_ptr);
            incr_counter!(compiled_iseq_count);
        }
        Err(err) => {
            payload.status = IseqStatus::CantCompile(err.clone());
            incr_counter!(failed_iseq_count);
        }
    }
    code_ptr
}

/// Compile an ISEQ into machine code
fn gen_iseq_body(cb: &mut CodeBlock, iseq: IseqPtr, function: Option<&Function>, payload: &mut IseqPayload) -> Result<CodePtr, CompileError> {
    // Convert ISEQ into optimized High-level IR if not given
    let function = match function {
        Some(function) => function,
        None => &compile_iseq(iseq)?,
    };

    // Compile the High-level IR
    let (start_ptr, gc_offsets, iseq_calls) = gen_function(cb, iseq, function)?;

    // Stub callee ISEQs for JIT-to-JIT calls
    for iseq_call in iseq_calls.iter() {
        gen_iseq_call(cb, iseq, iseq_call)?;
    }

    // Prepare for GC
    payload.iseq_calls.extend(iseq_calls.clone());
    append_gc_offsets(iseq, &gc_offsets);
    Ok(start_ptr)
}

/// Compile a function
fn gen_function(cb: &mut CodeBlock, iseq: IseqPtr, function: &Function) -> Result<(CodePtr, Vec<CodePtr>, Vec<IseqCallRef>), CompileError> {
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
            if let Err(last_snapshot) = gen_insn(cb, &mut jit, &mut asm, function, insn_id, &insn) {
                debug!("ZJIT: gen_function: Failed to compile insn: {insn_id} {insn}. Generating side-exit.");
                gen_side_exit(&mut jit, &mut asm, &SideExitReason::UnhandledHIRInsn(insn_id), &function.frame_state(last_snapshot));
                // Don't bother generating code after a side-exit. We won't run it.
                // TODO(max): Generate ud2 or equivalent.
                break;
            };
            // It's fine; we generated the instruction
        }
        // Make sure the last patch point has enough space to insert a jump
        asm.pad_patch_point();
    }

    if get_option!(dump_lir) {
        println!("LIR:\nfn {}:\n{:?}", iseq_name(iseq), asm);
    }

    // Generate code if everything can be compiled
    let result = asm.compile(cb);
    if let Ok((start_ptr, _)) = result {
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
    result.map(|(start_ptr, gc_offsets)| (start_ptr, gc_offsets, jit.iseq_calls))
}

/// Compile an instruction
fn gen_insn(cb: &mut CodeBlock, jit: &mut JITState, asm: &mut Assembler, function: &Function, insn_id: InsnId, insn: &Insn) -> Result<(), InsnId> {
    // Convert InsnId to lir::Opnd
    macro_rules! opnd {
        ($insn_id:ident) => {
            jit.get_opnd($insn_id.clone())
        };
    }

    macro_rules! opnds {
        ($insn_ids:ident) => {
            {
                $insn_ids.iter().map(|insn_id| jit.get_opnd(*insn_id)).collect::<Vec<_>>()
            }
        };
    }

    macro_rules! no_output {
        ($call:expr) => {
            { let () = $call; return Ok(()); }
        };
    }

    if !matches!(*insn, Insn::Snapshot { .. }) {
        asm_comment!(asm, "Insn: {insn_id} {insn}");
    }

    let out_opnd = match insn {
        Insn::Const { val: Const::Value(val) } => gen_const(*val),
        Insn::Const { .. } => panic!("Unexpected Const in gen_insn: {insn}"),
        Insn::NewArray { elements, state } => gen_new_array(asm, opnds!(elements), &function.frame_state(*state)),
        Insn::NewHash { elements, state } => gen_new_hash(jit, asm, elements, &function.frame_state(*state)),
        Insn::NewRange { low, high, flag, state } => gen_new_range(jit, asm, opnd!(low), opnd!(high), *flag, &function.frame_state(*state)),
        Insn::NewRangeFixnum { low, high, flag, state } => gen_new_range_fixnum(asm, opnd!(low), opnd!(high), *flag, &function.frame_state(*state)),
        Insn::ArrayDup { val, state } => gen_array_dup(asm, opnd!(val), &function.frame_state(*state)),
        Insn::StringCopy { val, chilled, state } => gen_string_copy(asm, opnd!(val), *chilled, &function.frame_state(*state)),
        // concatstrings shouldn't have 0 strings
        // If it happens we abort the compilation for now
        Insn::StringConcat { strings, state, .. } if strings.is_empty() => return Err(*state),
        Insn::StringConcat { strings, state } => gen_string_concat(jit, asm, opnds!(strings), &function.frame_state(*state)),
        Insn::StringIntern { val, state } => gen_intern(asm, opnd!(val), &function.frame_state(*state)),
        Insn::ToRegexp { opt, values, state } => gen_toregexp(jit, asm, *opt, opnds!(values), &function.frame_state(*state)),
        Insn::Param { idx } => unreachable!("block.insns should not have Insn::Param({idx})"),
        Insn::Snapshot { .. } => return Ok(()), // we don't need to do anything for this instruction at the moment
        Insn::Jump(branch) => no_output!(gen_jump(jit, asm, branch)),
        Insn::IfTrue { val, target } => no_output!(gen_if_true(jit, asm, opnd!(val), target)),
        Insn::IfFalse { val, target } => no_output!(gen_if_false(jit, asm, opnd!(val), target)),
        &Insn::Send { cd, blockiseq, state, .. } => gen_send(jit, asm, cd, blockiseq, &function.frame_state(state)),
        Insn::SendWithoutBlock { cd, state, .. } => gen_send_without_block(jit, asm, *cd, &function.frame_state(*state)),
        // Give up SendWithoutBlockDirect for 6+ args since asm.ccall() doesn't support it.
        Insn::SendWithoutBlockDirect { cd, state, args, .. } if args.len() + 1 > C_ARG_OPNDS.len() => // +1 for self
            gen_send_without_block(jit, asm, *cd, &function.frame_state(*state)),
        Insn::SendWithoutBlockDirect { cme, iseq, self_val, args, state, .. } => gen_send_without_block_direct(cb, jit, asm, *cme, *iseq, opnd!(self_val), opnds!(args), &function.frame_state(*state)),
        // Ensure we have enough room fit ec, self, and arguments
        // TODO remove this check when we have stack args (we can use Time.new to test it)
        Insn::InvokeBuiltin { bf, state, .. } if bf.argc + 2 > (C_ARG_OPNDS.len() as i32) => return Err(*state),
        Insn::InvokeBuiltin { bf, args, state, .. } => gen_invokebuiltin(jit, asm, &function.frame_state(*state), bf, opnds!(args)),
        Insn::Return { val } => no_output!(gen_return(asm, opnd!(val))),
        Insn::FixnumAdd { left, right, state } => gen_fixnum_add(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumSub { left, right, state } => gen_fixnum_sub(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumMult { left, right, state } => gen_fixnum_mult(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumEq { left, right } => gen_fixnum_eq(asm, opnd!(left), opnd!(right)),
        Insn::FixnumNeq { left, right } => gen_fixnum_neq(asm, opnd!(left), opnd!(right)),
        Insn::FixnumLt { left, right } => gen_fixnum_lt(asm, opnd!(left), opnd!(right)),
        Insn::FixnumLe { left, right } => gen_fixnum_le(asm, opnd!(left), opnd!(right)),
        Insn::FixnumGt { left, right } => gen_fixnum_gt(asm, opnd!(left), opnd!(right)),
        Insn::FixnumGe { left, right } => gen_fixnum_ge(asm, opnd!(left), opnd!(right)),
        Insn::FixnumAnd { left, right } => gen_fixnum_and(asm, opnd!(left), opnd!(right)),
        Insn::FixnumOr { left, right } => gen_fixnum_or(asm, opnd!(left), opnd!(right)),
        Insn::IsNil { val } => gen_isnil(asm, opnd!(val)),
        Insn::Test { val } => gen_test(asm, opnd!(val)),
        Insn::GuardType { val, guard_type, state } => gen_guard_type(jit, asm, opnd!(val), *guard_type, &function.frame_state(*state)),
        Insn::GuardBitEquals { val, expected, state } => gen_guard_bit_equals(jit, asm, opnd!(val), *expected, &function.frame_state(*state)),
        Insn::PatchPoint { invariant, state } => no_output!(gen_patch_point(jit, asm, invariant, &function.frame_state(*state))),
        Insn::CCall { cfun, args, name: _, return_type: _, elidable: _ } => gen_ccall(asm, *cfun, opnds!(args)),
        Insn::GetIvar { self_val, id, state: _ } => gen_getivar(asm, opnd!(self_val), *id),
        Insn::SetGlobal { id, val, state } => no_output!(gen_setglobal(jit, asm, *id, opnd!(val), &function.frame_state(*state))),
        Insn::GetGlobal { id, state } => gen_getglobal(jit, asm, *id, &function.frame_state(*state)),
        &Insn::GetLocal { ep_offset, level } => gen_getlocal_with_ep(asm, ep_offset, level),
        &Insn::SetLocal { val, ep_offset, level } => no_output!(gen_setlocal_with_ep(asm, opnd!(val), function.type_of(val), ep_offset, level)),
        Insn::GetConstantPath { ic, state } => gen_get_constant_path(jit, asm, *ic, &function.frame_state(*state)),
        Insn::SetIvar { self_val, id, val, state: _ } => no_output!(gen_setivar(asm, opnd!(self_val), *id, opnd!(val))),
        Insn::SideExit { state, reason } => no_output!(gen_side_exit(jit, asm, reason, &function.frame_state(*state))),
        Insn::PutSpecialObject { value_type } => gen_putspecialobject(asm, *value_type),
        Insn::AnyToString { val, str, state } => gen_anytostring(asm, opnd!(val), opnd!(str), &function.frame_state(*state)),
        Insn::Defined { op_type, obj, pushval, v, state } => gen_defined(jit, asm, *op_type, *obj, *pushval, opnd!(v), &function.frame_state(*state)),
        Insn::GetSpecialSymbol { symbol_type, state: _ } => gen_getspecial_symbol(asm, *symbol_type),
        Insn::GetSpecialNumber { nth, state } => gen_getspecial_number(asm, *nth, &function.frame_state(*state)),
        &Insn::IncrCounter(counter) => no_output!(gen_incr_counter(asm, counter)),
        Insn::ObjToString { val, cd, state, .. } => gen_objtostring(jit, asm, opnd!(val), *cd, &function.frame_state(*state)),
        &Insn::CheckInterrupts { state } => no_output!(gen_check_interrupts(jit, asm, &function.frame_state(state))),
        &Insn::HashDup { val, state } => { gen_hash_dup(asm, opnd!(val), &function.frame_state(state)) },
        &Insn::ArrayPush { array, val, state } => { no_output!(gen_array_push(asm, opnd!(array), opnd!(val), &function.frame_state(state))) },
        &Insn::ToNewArray { val, state } => { gen_to_new_array(jit, asm, opnd!(val), &function.frame_state(state)) },
        &Insn::ToArray { val, state } => { gen_to_array(jit, asm, opnd!(val), &function.frame_state(state)) },
        &Insn::DefinedIvar { self_val, id, pushval, .. } => { gen_defined_ivar(asm, opnd!(self_val), id, pushval) },
        &Insn::ArrayExtend { left, right, state } => { no_output!(gen_array_extend(jit, asm, opnd!(left), opnd!(right), &function.frame_state(state))) },
        &Insn::GuardShape { val, shape, state } => gen_guard_shape(jit, asm, opnd!(val), shape, &function.frame_state(state)),
        &Insn::LoadIvarEmbedded { self_val, id, index } => gen_load_ivar_embedded(asm, opnd!(self_val), id, index),
        &Insn::LoadIvarExtended { self_val, id, index } => gen_load_ivar_extended(asm, opnd!(self_val), id, index),
        &Insn::ArrayMax { state, .. }
        | &Insn::FixnumDiv { state, .. }
        | &Insn::FixnumMod { state, .. }
        | &Insn::Throw { state, .. }
        => return Err(state),
    };

    assert!(insn.has_output(), "Cannot write LIR output of HIR instruction with no output: {insn}");

    // If the instruction has an output, remember it in jit.opnds
    jit.opnds[insn_id.0] = Some(out_opnd);

    Ok(())
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

fn gen_objtostring(jit: &mut JITState, asm: &mut Assembler, val: Opnd, cd: *const rb_call_data, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let iseq_opnd = Opnd::Value(jit.iseq.into());

    // TODO: Specialize for immediate types
    // Call rb_vm_objtostring(iseq, recv, cd)
    let ret = asm_ccall!(asm, rb_vm_objtostring, iseq_opnd, val, (cd as usize).into());

    // TODO: Call `to_s` on the receiver if rb_vm_objtostring returns Qundef
    // Need to replicate what CALL_SIMPLE_METHOD does
    asm_comment!(asm, "side-exit if rb_vm_objtostring returns Qundef");
    asm.cmp(ret, Qundef.into());
    asm.je(side_exit(jit, state, ObjToStringFallback));

    ret
}

fn gen_defined(jit: &JITState, asm: &mut Assembler, op_type: usize, obj: VALUE, pushval: VALUE, tested_value: Opnd, state: &FrameState) -> Opnd {
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
                asm.csel_e(Qnil.into(), pushval)
            } else {
                Qnil.into()
            }
        }
        _ => {
            // Save the PC and SP because the callee may allocate or call #respond_to?
            gen_prepare_non_leaf_call(jit, asm, state);

            // TODO: Inline the cases for each op_type
            // Call vm_defined(ec, reg_cfp, op_type, obj, v)
            let def_result = asm_ccall!(asm, rb_vm_defined, EC, CFP, op_type.into(), obj.into(), tested_value);

            asm.cmp(def_result.with_num_bits(8), 0.into());
            asm.csel_ne(pushval.into(), Qnil.into())
        }
    }
}

/// Get a local variable from a higher scope or the heap. `local_ep_offset` is in number of VALUEs.
/// We generate this instruction with level=0 only when the local variable is on the heap, so we
/// can't optimize the level=0 case using the SP register.
fn gen_getlocal_with_ep(asm: &mut Assembler, local_ep_offset: u32, level: u32) -> lir::Opnd {
    let ep = gen_get_ep(asm, level);
    let offset = -(SIZEOF_VALUE_I32 * i32::try_from(local_ep_offset).unwrap_or_else(|_| panic!("Could not convert local_ep_offset {local_ep_offset} to i32")));
    asm.load(Opnd::mem(64, ep, offset))
}

/// Set a local variable from a higher scope or the heap. `local_ep_offset` is in number of VALUEs.
/// We generate this instruction with level=0 only when the local variable is on the heap, so we
/// can't optimize the level=0 case using the SP register.
fn gen_setlocal_with_ep(asm: &mut Assembler, val: Opnd, val_type: Type, local_ep_offset: u32, level: u32) {
    let ep = gen_get_ep(asm, level);

    // When we've proved that we're writing an immediate,
    // we can skip the write barrier.
    if val_type.is_immediate() {
        let offset = -(SIZEOF_VALUE_I32 * i32::try_from(local_ep_offset).unwrap_or_else(|_| panic!("Could not convert local_ep_offset {local_ep_offset} to i32")));
        asm.mov(Opnd::mem(64, ep, offset), val);
    } else {
        // We're potentially writing a reference to an IMEMO/env object,
        // so take care of the write barrier with a function.
        let local_index = c_int::try_from(local_ep_offset).ok().and_then(|idx| idx.checked_mul(-1)).unwrap_or_else(|| panic!("Could not turn {local_ep_offset} into a negative c_int"));
        asm_ccall!(asm, rb_vm_env_write, ep, local_index.into(), val);
    }
}

fn gen_get_constant_path(jit: &JITState, asm: &mut Assembler, ic: *const iseq_inline_constant_cache, state: &FrameState) -> Opnd {
    unsafe extern "C" {
        fn rb_vm_opt_getconstant_path(ec: EcPtr, cfp: CfpPtr, ic: *const iseq_inline_constant_cache) -> VALUE;
    }

    // Anything could be called on const_missing
    gen_prepare_non_leaf_call(jit, asm, state);

    asm_ccall!(asm, rb_vm_opt_getconstant_path, EC, CFP, Opnd::const_ptr(ic))
}

fn gen_invokebuiltin(jit: &JITState, asm: &mut Assembler, state: &FrameState, bf: &rb_builtin_function, args: Vec<Opnd>) -> lir::Opnd {
    assert!(bf.argc + 2 <= C_ARG_OPNDS.len() as i32,
            "gen_invokebuiltin should not be called for builtin function {} with too many arguments: {}",
            unsafe { std::ffi::CStr::from_ptr(bf.name).to_str().unwrap() },
            bf.argc);
    // Anything can happen inside builtin functions
    gen_prepare_non_leaf_call(jit, asm, state);

    let mut cargs = vec![EC];
    cargs.extend(args);

    asm.ccall(bf.func_ptr as *const u8, cargs)
}

/// Record a patch point that should be invalidated on a given invariant
fn gen_patch_point(jit: &mut JITState, asm: &mut Assembler, invariant: &Invariant, state: &FrameState) {
    let payload_ptr = get_or_create_iseq_payload_ptr(jit.iseq);
    let label = asm.new_label("patch_point").unwrap_label();
    let invariant = *invariant;

    // Compile a side exit. Fill nop instructions if the last patch point is too close.
    asm.patch_point(build_side_exit(jit, state, PatchPoint(invariant), Some(label)));

    // Remember the current address as a patch point
    asm.pos_marker(move |code_ptr, cb| {
        match invariant {
            Invariant::BOPRedefined { klass, bop } => {
                let side_exit_ptr = cb.resolve_label(label);
                track_bop_assumption(klass, bop, code_ptr, side_exit_ptr, payload_ptr);
            }
            Invariant::MethodRedefined { klass: _, method: _, cme } => {
                let side_exit_ptr = cb.resolve_label(label);
                track_cme_assumption(cme, code_ptr, side_exit_ptr, payload_ptr);
            }
            Invariant::StableConstantNames { idlist } => {
                let side_exit_ptr = cb.resolve_label(label);
                track_stable_constant_names_assumption(idlist, code_ptr, side_exit_ptr, payload_ptr);
            }
            Invariant::SingleRactorMode => {
                let side_exit_ptr = cb.resolve_label(label);
                track_single_ractor_assumption(code_ptr, side_exit_ptr, payload_ptr);
            }
        }
    });
}

/// Lowering for [`Insn::CCall`]. This is a low-level raw call that doesn't know
/// anything about the callee, so handling for e.g. GC safety is dealt with elsewhere.
fn gen_ccall(asm: &mut Assembler, cfun: *const u8, args: Vec<Opnd>) -> lir::Opnd {
    asm.ccall(cfun, args)
}

/// Emit an uncached instance variable lookup
fn gen_getivar(asm: &mut Assembler, recv: Opnd, id: ID) -> Opnd {
    asm_ccall!(asm, rb_ivar_get, recv, id.0.into())
}

/// Emit an uncached instance variable store
fn gen_setivar(asm: &mut Assembler, recv: Opnd, id: ID, val: Opnd) {
    asm_ccall!(asm, rb_ivar_set, recv, id.0.into(), val);
}

/// Look up global variables
fn gen_getglobal(jit: &mut JITState, asm: &mut Assembler, id: ID, state: &FrameState) -> Opnd {
    // `Warning` module's method `warn` can be called when reading certain global variables
    gen_prepare_non_leaf_call(jit, asm, state);

    asm_ccall!(asm, rb_gvar_get, id.0.into())
}

/// Intern a string
fn gen_intern(asm: &mut Assembler, val: Opnd, state: &FrameState) -> Opnd {
    gen_prepare_call_with_gc(asm, state);

    asm_ccall!(asm, rb_str_intern, val)
}

/// Set global variables
fn gen_setglobal(jit: &mut JITState, asm: &mut Assembler, id: ID, val: Opnd, state: &FrameState) {
    // When trace_var is used, setting a global variable can cause exceptions
    gen_prepare_non_leaf_call(jit, asm, state);

    asm_ccall!(asm, rb_gvar_set, id.0.into(), val);
}

/// Side-exit into the interpreter
fn gen_side_exit(jit: &mut JITState, asm: &mut Assembler, reason: &SideExitReason, state: &FrameState) {
    asm.jmp(side_exit(jit, state, *reason));
}

/// Emit a special object lookup
fn gen_putspecialobject(asm: &mut Assembler, value_type: SpecialObjectType) -> Opnd {
    // Get the EP of the current CFP and load it into a register
    let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
    let ep_reg = asm.load(ep_opnd);

    asm_ccall!(asm, rb_vm_get_special_object, ep_reg, Opnd::UImm(u64::from(value_type)))
}

fn gen_getspecial_symbol(asm: &mut Assembler, symbol_type: SpecialBackrefSymbol) -> Opnd {
    // Fetch a "special" backref based on the symbol type

    let backref = asm_ccall!(asm, rb_backref_get,);

    match symbol_type {
        SpecialBackrefSymbol::LastMatch => {
            asm_ccall!(asm, rb_reg_last_match, backref)
        }
        SpecialBackrefSymbol::PreMatch => {
            asm_ccall!(asm, rb_reg_match_pre, backref)
        }
        SpecialBackrefSymbol::PostMatch => {
            asm_ccall!(asm, rb_reg_match_post, backref)
        }
        SpecialBackrefSymbol::LastGroup => {
            asm_ccall!(asm, rb_reg_match_last, backref)
        }
    }
}

fn gen_getspecial_number(asm: &mut Assembler, nth: u64, state: &FrameState) -> Opnd {
    // Fetch the N-th match from the last backref based on type shifted by 1

    let backref = asm_ccall!(asm, rb_backref_get,);

    gen_prepare_call_with_gc(asm, state);

    asm_ccall!(asm, rb_reg_nth_match, Opnd::Imm((nth >> 1).try_into().unwrap()), backref)
}

fn gen_check_interrupts(jit: &mut JITState, asm: &mut Assembler, state: &FrameState) {
    // Check for interrupts
    // see RUBY_VM_CHECK_INTS(ec) macro
    asm_comment!(asm, "RUBY_VM_CHECK_INTS(ec)");
    // Not checking interrupt_mask since it's zero outside finalize_deferred_heap_pages,
    // signal_exec, or rb_postponed_job_flush.
    let interrupt_flag = asm.load(Opnd::mem(32, EC, RUBY_OFFSET_EC_INTERRUPT_FLAG));
    asm.test(interrupt_flag, interrupt_flag);
    asm.jnz(side_exit(jit, state, SideExitReason::Interrupt));
}

fn gen_hash_dup(asm: &mut Assembler, val: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_call_with_gc(asm, state);
    asm_ccall!(asm, rb_hash_resurrect, val)
}

fn gen_array_push(asm: &mut Assembler, array: Opnd, val: Opnd, state: &FrameState) {
    gen_prepare_call_with_gc(asm, state);
    asm_ccall!(asm, rb_ary_push, array, val);
}

fn gen_to_new_array(jit: &mut JITState, asm: &mut Assembler, val: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_vm_splat_array, Opnd::Value(Qtrue), val)
}

fn gen_to_array(jit: &mut JITState, asm: &mut Assembler, val: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_vm_splat_array, Opnd::Value(Qfalse), val)
}

fn gen_defined_ivar(asm: &mut Assembler, self_val: Opnd, id: ID, pushval: VALUE) -> lir::Opnd {
    asm_ccall!(asm, rb_zjit_defined_ivar, self_val, id.0.into(), Opnd::Value(pushval))
}

fn gen_array_extend(jit: &mut JITState, asm: &mut Assembler, left: Opnd, right: Opnd, state: &FrameState) {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_ary_concat, left, right);
}

fn gen_guard_shape(jit: &mut JITState, asm: &mut Assembler, val: Opnd, shape: ShapeId, state: &FrameState) -> Opnd {
    let shape_id_offset = unsafe { rb_shape_id_offset() };
    let val = asm.load(val);
    let shape_opnd = Opnd::mem(SHAPE_ID_NUM_BITS as u8, val, shape_id_offset);
    asm.cmp(shape_opnd, Opnd::UImm(shape.0 as u64));
    asm.jne(side_exit(jit, state, SideExitReason::GuardShape(shape)));
    val
}

fn gen_load_ivar_embedded(asm: &mut Assembler, self_val: Opnd, id: ID, index: u16) -> Opnd {
    // See ROBJECT_FIELDS() from include/ruby/internal/core/robject.h

    asm_comment!(asm, "Load embedded ivar id={} index={}", id.contents_lossy(), index);
    let offs = ROBJECT_OFFSET_AS_ARY as i32 + (SIZEOF_VALUE * index as usize) as i32;
    let self_val = asm.load(self_val);
    let ivar_opnd = Opnd::mem(64, self_val, offs);
    asm.load(ivar_opnd)
}

fn gen_load_ivar_extended(asm: &mut Assembler, self_val: Opnd, id: ID, index: u16) -> Opnd {
    asm_comment!(asm, "Load extended ivar id={} index={}", id.contents_lossy(), index);
    // Compile time value is *not* embedded.

    // Get a pointer to the extended table
    let self_val = asm.load(self_val);
    let tbl_opnd = asm.load(Opnd::mem(64, self_val, ROBJECT_OFFSET_AS_HEAP_FIELDS as i32));

    // Read the ivar from the extended table
    let ivar_opnd = Opnd::mem(64, tbl_opnd, (SIZEOF_VALUE * index as usize) as i32);
    asm.load(ivar_opnd)
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
fn gen_branch_params(jit: &mut JITState, asm: &mut Assembler, branch: &BranchEdge) {
    if branch.args.is_empty() {
        return;
    }

    asm_comment!(asm, "set branch params: {}", branch.args.len());
    let mut moves: Vec<(Reg, Opnd)> = vec![];
    for (idx, &arg) in branch.args.iter().enumerate() {
        match param_opnd(idx) {
            Opnd::Reg(reg) => {
                // If a parameter is a register, we need to parallel-move it
                moves.push((reg, jit.get_opnd(arg)));
            },
            param => {
                // If a parameter is memory, we set it beforehand
                asm.mov(param, jit.get_opnd(arg));
            }
        }
    }
    asm.parallel_mov(moves);
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
fn gen_jump(jit: &mut JITState, asm: &mut Assembler, branch: &BranchEdge) {
    // Set basic block arguments
    gen_branch_params(jit, asm, branch);

    // Jump to the basic block
    let target = jit.get_label(asm, branch.target);
    asm.jmp(target);
}

/// Compile a conditional branch to a basic block
fn gen_if_true(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, branch: &BranchEdge) {
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
}

/// Compile a conditional branch to a basic block
fn gen_if_false(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, branch: &BranchEdge) {
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
}

/// Compile a dynamic dispatch with block
fn gen_send(
    jit: &mut JITState,
    asm: &mut Assembler,
    cd: *const rb_call_data,
    blockiseq: IseqPtr,
    state: &FrameState,
) -> lir::Opnd {
    gen_incr_counter(asm, Counter::dynamic_send_count);

    // Save PC and SP
    gen_prepare_call_with_gc(asm, state);
    gen_save_sp(asm, state.stack().len());

    // Spill locals and stack
    gen_spill_locals(jit, asm, state);
    gen_spill_stack(jit, asm, state);

    asm_comment!(asm, "call #{} with dynamic dispatch", ruby_call_method_name(cd));
    unsafe extern "C" {
        fn rb_vm_send(ec: EcPtr, cfp: CfpPtr, cd: VALUE, blockiseq: IseqPtr) -> VALUE;
    }
    let ret = asm.ccall(
        rb_vm_send as *const u8,
        vec![EC, CFP, (cd as usize).into(), VALUE(blockiseq as usize).into()],
    );
    // TODO: Add a PatchPoint here that can side-exit the function if the callee messed with
    // the frame's locals

    ret
}

/// Compile a dynamic dispatch without block
fn gen_send_without_block(
    jit: &mut JITState,
    asm: &mut Assembler,
    cd: *const rb_call_data,
    state: &FrameState,
) -> lir::Opnd {
    gen_incr_counter(asm, Counter::dynamic_send_count);

    // Note that it's incorrect to use this frame state to side exit because
    // the state might not be on the boundary of an interpreter instruction.
    // For example, `opt_str_uminus` pushes to the stack and then sends.
    asm_comment!(asm, "spill frame state");

    // Save PC and SP
    gen_prepare_call_with_gc(asm, state);
    gen_save_sp(asm, state.stack().len());

    // Spill locals and stack
    gen_spill_locals(jit, asm, state);
    gen_spill_stack(jit, asm, state);

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

    ret
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
) -> lir::Opnd {
    // Save cfp->pc and cfp->sp for the caller frame
    gen_prepare_call_with_gc(asm, state);
    gen_save_sp(asm, state.stack().len() - args.len() - 1); // -1 for receiver

    gen_spill_locals(jit, asm, state);
    gen_spill_stack(jit, asm, state);

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
    let iseq_call = IseqCall::new(iseq);
    let dummy_ptr = cb.get_write_ptr().raw_ptr(cb);
    jit.iseq_calls.push(iseq_call.clone());
    // TODO(max): Add a PatchPoint here that can side-exit the function if the callee messed with
    // the frame's locals
    let ret = asm.ccall_with_iseq_call(dummy_ptr, c_args, &iseq_call);

    // If a callee side-exits, i.e. returns Qundef, propagate the return value to the caller.
    // The caller will side-exit the callee into the interpreter.
    // TODO: Let side exit code pop all JIT frames to optimize away this cmp + je.
    asm_comment!(asm, "side-exit if callee side-exits");
    asm.cmp(ret, Qundef.into());
    // Restore the C stack pointer on exit
    asm.je(ZJITState::get_exit_trampoline().into());

    asm_comment!(asm, "restore SP register for the caller");
    let new_sp = asm.sub(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    ret
}

/// Compile a string resurrection
fn gen_string_copy(asm: &mut Assembler, recv: Opnd, chilled: bool, state: &FrameState) -> Opnd {
    // TODO: split rb_ec_str_resurrect into separate functions
    gen_prepare_call_with_gc(asm, state);
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

    let length: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

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
    elements: &[(InsnId, InsnId)],
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let cap: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");
    let new_hash = asm_ccall!(asm, rb_hash_new_with_size, lir::Opnd::Imm(cap));

    if !elements.is_empty() {
        let mut pairs = Vec::new();
        for (key_id, val_id) in elements.iter() {
            let key = jit.get_opnd(*key_id);
            let val = jit.get_opnd(*val_id);
            pairs.push(key);
            pairs.push(val);
        }

        let argv = gen_push_opnds(jit, asm, &pairs);
        let argc = (elements.len() * 2) as ::std::os::raw::c_long;
        asm_ccall!(asm, rb_hash_bulk_insert, lir::Opnd::Imm(argc), argv, new_hash);

        gen_pop_opnds(asm, &pairs);
    }

    new_hash
}

/// Compile a new range instruction
fn gen_new_range(
    jit: &JITState,
    asm: &mut Assembler,
    low: lir::Opnd,
    high: lir::Opnd,
    flag: RangeType,
    state: &FrameState,
) -> lir::Opnd {
    // Sometimes calls `low.<=>(high)`
    gen_prepare_non_leaf_call(jit, asm, state);

    // Call rb_range_new(low, high, flag)
    asm_ccall!(asm, rb_range_new, low, high, (flag as i64).into())
}

fn gen_new_range_fixnum(
    asm: &mut Assembler,
    low: lir::Opnd,
    high: lir::Opnd,
    flag: RangeType,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_call_with_gc(asm, state);
    asm_ccall!(asm, rb_range_new, low, high, (flag as i64).into())
}

/// Compile code that exits from JIT code with a return value
fn gen_return(asm: &mut Assembler, val: lir::Opnd) {
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
}

/// Compile Fixnum + Fixnum
fn gen_fixnum_add(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Add left + right and test for overflow
    let left_untag = asm.sub(left, Opnd::Imm(1));
    let out_val = asm.add(left_untag, right);
    asm.jo(side_exit(jit, state, FixnumAddOverflow));

    out_val
}

/// Compile Fixnum - Fixnum
fn gen_fixnum_sub(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Subtract left - right and test for overflow
    let val_untag = asm.sub(left, right);
    asm.jo(side_exit(jit, state, FixnumSubOverflow));
    asm.add(val_untag, Opnd::Imm(1))
}

/// Compile Fixnum * Fixnum
fn gen_fixnum_mult(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Do some bitwise gymnastics to handle tag bits
    // x * y is translated to (x >> 1) * (y - 1) + 1
    let left_untag = asm.rshift(left, Opnd::UImm(1));
    let right_untag = asm.sub(right, Opnd::UImm(1));
    let out_val = asm.mul(left_untag, right_untag);

    // Test for overflow
    asm.jo_mul(side_exit(jit, state, FixnumMultOverflow));
    asm.add(out_val, Opnd::UImm(1))
}

/// Compile Fixnum == Fixnum
fn gen_fixnum_eq(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.cmp(left, right);
    asm.csel_e(Qtrue.into(), Qfalse.into())
}

/// Compile Fixnum != Fixnum
fn gen_fixnum_neq(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.cmp(left, right);
    asm.csel_ne(Qtrue.into(), Qfalse.into())
}

/// Compile Fixnum < Fixnum
fn gen_fixnum_lt(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.cmp(left, right);
    asm.csel_l(Qtrue.into(), Qfalse.into())
}

/// Compile Fixnum <= Fixnum
fn gen_fixnum_le(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.cmp(left, right);
    asm.csel_le(Qtrue.into(), Qfalse.into())
}

/// Compile Fixnum > Fixnum
fn gen_fixnum_gt(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.cmp(left, right);
    asm.csel_g(Qtrue.into(), Qfalse.into())
}

/// Compile Fixnum >= Fixnum
fn gen_fixnum_ge(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.cmp(left, right);
    asm.csel_ge(Qtrue.into(), Qfalse.into())
}

/// Compile Fixnum & Fixnum
fn gen_fixnum_and(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.and(left, right)
}

/// Compile Fixnum | Fixnum
fn gen_fixnum_or(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.or(left, right)
}

// Compile val == nil
fn gen_isnil(asm: &mut Assembler, val: lir::Opnd) -> lir::Opnd {
    asm.cmp(val, Qnil.into());
    // TODO: Implement and use setcc
    asm.csel_e(Opnd::Imm(1), Opnd::Imm(0))
}

fn gen_anytostring(asm: &mut Assembler, val: lir::Opnd, str: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_call_with_gc(asm, state);

    asm_ccall!(asm, rb_obj_as_string_result, str, val)
}

/// Evaluate if a value is truthy
/// Produces a CBool type (0 or 1)
/// In Ruby, only nil and false are falsy
/// Everything else evaluates to true
fn gen_test(asm: &mut Assembler, val: lir::Opnd) -> lir::Opnd {
    // Test if any bit (outside of the Qnil bit) is on
    // See RB_TEST(), include/ruby/internal/special_consts.h
    asm.test(val, Opnd::Imm(!Qnil.as_i64()));
    asm.csel_e(0.into(), 1.into())
}

/// Compile a type check with a side exit
fn gen_guard_type(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, guard_type: Type, state: &FrameState) -> lir::Opnd {
    if guard_type.is_subtype(types::Fixnum) {
        asm.test(val, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));
        asm.jz(side_exit(jit, state, GuardType(guard_type)));
    } else if guard_type.is_subtype(types::Flonum) {
        // Flonum: (val & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG
        let masked = asm.and(val, Opnd::UImm(RUBY_FLONUM_MASK as u64));
        asm.cmp(masked, Opnd::UImm(RUBY_FLONUM_FLAG as u64));
        asm.jne(side_exit(jit, state, GuardType(guard_type)));
    } else if guard_type.is_subtype(types::StaticSymbol) {
        // Static symbols have (val & 0xff) == RUBY_SYMBOL_FLAG
        // Use 8-bit comparison like YJIT does. GuardType should not be used
        // for a known VALUE, which with_num_bits() does not support.
        asm.cmp(val.with_num_bits(8), Opnd::UImm(RUBY_SYMBOL_FLAG as u64));
        asm.jne(side_exit(jit, state, GuardType(guard_type)));
    } else if guard_type.is_subtype(types::NilClass) {
        asm.cmp(val, Qnil.into());
        asm.jne(side_exit(jit, state, GuardType(guard_type)));
    } else if guard_type.is_subtype(types::TrueClass) {
        asm.cmp(val, Qtrue.into());
        asm.jne(side_exit(jit, state, GuardType(guard_type)));
    } else if guard_type.is_subtype(types::FalseClass) {
        asm.cmp(val, Qfalse.into());
        asm.jne(side_exit(jit, state, GuardType(guard_type)));
    } else if guard_type.is_immediate() {
        // All immediate types' guard should have been handled above
        panic!("unexpected immediate guard type: {guard_type}");
    } else if let Some(expected_class) = guard_type.runtime_exact_ruby_class() {
        asm_comment!(asm, "guard exact class for non-immediate types");

        // If val isn't in a register, load it to use it as the base of Opnd::mem later.
        // TODO: Max thinks codegen should not care about the shapes of the operands except to create them. (Shopify/ruby#685)
        let val = match val {
            Opnd::Reg(_) | Opnd::VReg { .. } => val,
            _ => asm.load(val),
        };

        // Check if it's a special constant
        let side_exit = side_exit(jit, state, GuardType(guard_type));
        asm.test(val, (RUBY_IMMEDIATE_MASK as u64).into());
        asm.jnz(side_exit.clone());

        // Check if it's false
        asm.cmp(val, Qfalse.into());
        asm.je(side_exit.clone());

        // Load the class from the object's klass field
        let klass = asm.load(Opnd::mem(64, val, RUBY_OFFSET_RBASIC_KLASS));

        asm.cmp(klass, Opnd::Value(expected_class));
        asm.jne(side_exit);
    } else if guard_type.bit_equal(types::HeapObject) {
        let side_exit = side_exit(jit, state, GuardType(guard_type));
        asm.cmp(val, Opnd::Value(Qfalse));
        asm.je(side_exit.clone());
        asm.test(val, (RUBY_IMMEDIATE_MASK as u64).into());
        asm.jnz(side_exit);
    } else {
        unimplemented!("unsupported type: {guard_type}");
    }
    val
}

/// Compile an identity check with a side exit
fn gen_guard_bit_equals(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, expected: VALUE, state: &FrameState) -> lir::Opnd {
    asm.cmp(val, Opnd::Value(expected));
    asm.jnz(side_exit(jit, state, GuardBitEquals(expected)));
    val
}

/// Generate code that increments a counter if --zjit-stats
fn gen_incr_counter(asm: &mut Assembler, counter: Counter) {
    if get_option!(stats) {
        let ptr = counter_ptr(counter);
        let ptr_reg = asm.load(Opnd::const_ptr(ptr as *const u8));
        let counter_opnd = Opnd::mem(64, ptr_reg, 0);

        // Increment and store the updated value
        asm.incr_counter(counter_opnd, Opnd::UImm(1));
    }
}

/// Save the current PC on the CFP as a preparation for calling a C function
/// that may allocate objects and trigger GC. Use gen_prepare_non_leaf_call()
/// if it may raise exceptions or call arbitrary methods.
///
/// Unlike YJIT, we don't need to save the stack slots to protect them from GC
/// because the backend spills all live registers onto the C stack on CCall.
fn gen_prepare_call_with_gc(asm: &mut Assembler, state: &FrameState) {
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
fn gen_spill_locals(jit: &JITState, asm: &mut Assembler, state: &FrameState) {
    // TODO: Avoid spilling locals that have been spilled before and not changed.
    asm_comment!(asm, "spill locals");
    for (idx, &insn_id) in state.locals().enumerate() {
        asm.mov(Opnd::mem(64, SP, (-local_idx_to_ep_offset(jit.iseq, idx) - 1) * SIZEOF_VALUE_I32), jit.get_opnd(insn_id));
    }
}

/// Spill the virtual stack onto the stack.
fn gen_spill_stack(jit: &JITState, asm: &mut Assembler, state: &FrameState) {
    // This function does not call gen_save_sp() at the moment because
    // gen_send_without_block_direct() spills stack slots above SP for arguments.
    asm_comment!(asm, "spill stack");
    for (idx, &insn_id) in state.stack().enumerate() {
        asm.mov(Opnd::mem(64, SP, idx as i32 * SIZEOF_VALUE_I32), jit.get_opnd(insn_id));
    }
}

/// Prepare for calling a C function that may call an arbitrary method.
/// Use gen_prepare_call_with_gc() if the method is leaf but allocates objects.
fn gen_prepare_non_leaf_call(jit: &JITState, asm: &mut Assembler, state: &FrameState) {
    // TODO: Lazily materialize caller frames when needed
    // Save PC for backtraces and allocation tracing
    gen_prepare_call_with_gc(asm, state);

    // Save SP and spill the virtual stack in case it raises an exception
    // and the interpreter uses the stack for handling the exception
    gen_save_sp(asm, state.stack().len());
    gen_spill_stack(jit, asm, state);

    // Spill locals in case the method looks at caller Bindings
    gen_spill_locals(jit, asm, state);
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
pub fn local_idx_to_ep_offset(iseq: IseqPtr, local_idx: usize) -> i32 {
    let local_size = unsafe { get_iseq_body_local_table_size(iseq) };
    local_size_and_idx_to_ep_offset(local_size as usize, local_idx)
}

/// Convert the number of locals and a local index to an offset from the EP
pub fn local_size_and_idx_to_ep_offset(local_size: usize, local_idx: usize) -> i32 {
    local_size as i32 - local_idx as i32 - 1 + VM_ENV_DATA_SIZE as i32
}

/// Convert the number of locals and a local index to an offset from the BP.
/// We don't move the SP register after entry, so we often use SP as BP.
pub fn local_size_and_idx_to_bp_offset(local_size: usize, local_idx: usize) -> i32 {
    local_size_and_idx_to_ep_offset(local_size, local_idx) + 1
}

/// Convert ISEQ into High-level IR
fn compile_iseq(iseq: IseqPtr) -> Result<Function, CompileError> {
    // Convert ZJIT instructions back to bare instructions
    unsafe { crate::cruby::rb_zjit_profile_disable(iseq) };

    // Reject ISEQs with very large temp stacks.
    // We cannot encode too large offsets to access locals in arm64.
    let stack_max = unsafe { rb_get_iseq_body_stack_max(iseq) };
    if stack_max >= i8::MAX as u32 {
        debug!("ISEQ stack too large: {stack_max}");
        return Err(CompileError::IseqStackTooLarge);
    }

    let mut function = match iseq_to_hir(iseq) {
        Ok(function) => function,
        Err(err) => {
            let name = crate::cruby::iseq_get_location(iseq, 0);
            debug!("ZJIT: iseq_to_hir: {err:?}: {name}");
            return Err(CompileError::ParseError(err));
        }
    };
    if !get_option!(disable_hir_opt) {
        function.optimize();
    }
    function.dump_hir();
    #[cfg(debug_assertions)]
    if let Err(err) = function.validate() {
        debug!("ZJIT: compile_iseq: {err:?}");
        return Err(CompileError::ParseError(ParseError::Validation(err)));
    }
    Ok(function)
}

/// Build a Target::SideExit for non-PatchPoint instructions
fn side_exit(jit: &mut JITState, state: &FrameState, reason: SideExitReason) -> Target {
    build_side_exit(jit, state, reason, None)
}

/// Build a Target::SideExit out of a FrameState
fn build_side_exit(jit: &mut JITState, state: &FrameState, reason: SideExitReason, label: Option<Label>) -> Target {
    let mut stack = Vec::new();
    for &insn_id in state.stack() {
        stack.push(jit.get_opnd(insn_id));
    }

    let mut locals = Vec::new();
    for &insn_id in state.locals() {
        locals.push(jit.get_opnd(insn_id));
    }

    Target::SideExit {
        pc: state.pc,
        stack,
        locals,
        reason,
        label,
    }
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
    /// Generated code calls this function with the SysV calling convention. See [gen_function_stub].
    /// This function is expected to be called repeatedly when ZJIT fails to compile the stub.
    /// We should be able to compile most (if not all) function stubs by side-exiting at unsupported
    /// instructions, so this should be used primarily for cb.has_dropped_bytes() situations.
    fn function_stub_hit(iseq_call_ptr: *const c_void, cfp: CfpPtr, sp: *mut VALUE) -> *const u8 {
        with_vm_lock(src_loc!(), || {
            // gen_push_frame() doesn't set PC, so we need to set them before exit.
            // function_stub_hit_body() may allocate and call gc_validate_pc(), so we always set PC.
            let iseq_call = unsafe { Rc::from_raw(iseq_call_ptr as *const RefCell<IseqCall>) };
            let iseq = iseq_call.borrow().iseq;
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, 0) }; // TODO: handle opt_pc once supported
            unsafe { rb_set_cfp_pc(cfp, pc) };

            // JIT-to-JIT calls don't set SP or fill nils to uninitialized (non-argument) locals.
            // We need to set them if we side-exit from function_stub_hit.
            fn prepare_for_exit(iseq: IseqPtr, cfp: CfpPtr, sp: *mut VALUE, compile_error: &CompileError) {
                unsafe {
                    // Set SP which gen_push_frame() doesn't set
                    rb_set_cfp_sp(cfp, sp);

                    // Fill nils to uninitialized (non-argument) locals
                    let local_size = get_iseq_body_local_table_size(iseq) as usize;
                    let num_params = get_iseq_body_param_size(iseq) as usize;
                    let base = sp.offset(-local_size_and_idx_to_bp_offset(local_size, num_params) as isize);
                    slice::from_raw_parts_mut(base, local_size - num_params).fill(Qnil);
                }

                // Increment a compile error counter for --zjit-stats
                if get_option!(stats) {
                    incr_counter_by(exit_counter_for_compile_error(compile_error), 1);
                }
            }

            // If we already know we can't compile the ISEQ, fail early without cb.mark_all_executable().
            // TODO: Alan thinks the payload status part of this check can happen without the VM lock, since the whole
            // code path can be made read-only. But you still need the check as is while holding the VM lock in any case.
            let cb = ZJITState::get_code_block();
            let payload = get_or_create_iseq_payload(iseq);
            let compile_error = match &payload.status {
                IseqStatus::CantCompile(err) => Some(err),
                _ if cb.has_dropped_bytes() => Some(&CompileError::OutOfMemory),
                _ => None,
            };
            if let Some(compile_error) = compile_error {
                // We'll use this Rc again, so increment the ref count decremented by from_raw.
                unsafe { Rc::increment_strong_count(iseq_call_ptr as *const RefCell<IseqCall>); }

                prepare_for_exit(iseq, cfp, sp, compile_error);
                return ZJITState::get_exit_trampoline_with_counter().raw_ptr(cb);
            }

            // Otherwise, attempt to compile the ISEQ. We have to mark_all_executable() beyond this point.
            let code_ptr = with_time_stat(compile_time_ns, || function_stub_hit_body(cb, &iseq_call));
            let code_ptr = code_ptr.unwrap_or_else(|compile_error| {
                prepare_for_exit(iseq, cfp, sp, &compile_error);
                ZJITState::get_exit_trampoline_with_counter()
            });
            cb.mark_all_executable();
            code_ptr.raw_ptr(cb)
        })
    }
}

/// Compile an ISEQ for a function stub
fn function_stub_hit_body(cb: &mut CodeBlock, iseq_call: &Rc<RefCell<IseqCall>>) -> Result<CodePtr, CompileError> {
    // Compile the stubbed ISEQ
    let code_ptr = gen_iseq(cb, iseq_call.borrow().iseq, None).inspect_err(|err| {
        debug!("{err:?}: gen_iseq failed: {}", iseq_get_location(iseq_call.borrow().iseq, 0));
    })?;

    // Update the stub to call the code pointer
    let code_addr = code_ptr.raw_ptr(cb);
    let iseq = iseq_call.borrow().iseq;
    iseq_call.borrow_mut().regenerate(cb, |asm| {
        asm_comment!(asm, "call compiled function: {}", iseq_get_location(iseq, 0));
        asm.ccall(code_addr, vec![]);
    });

    Ok(code_ptr)
}

/// Compile a stub for an ISEQ called by SendWithoutBlockDirect
fn gen_function_stub(cb: &mut CodeBlock, iseq_call: Rc<RefCell<IseqCall>>) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();
    asm_comment!(asm, "Stub: {}", iseq_get_location(iseq_call.borrow().iseq, 0));

    // Call function_stub_hit using the shared trampoline. See `gen_function_stub_hit_trampoline`.
    // Use load_into instead of mov, which is split on arm64, to avoid clobbering ALLOC_REGS.
    asm.load_into(SCRATCH_OPND, Opnd::const_ptr(Rc::into_raw(iseq_call)));
    asm.jmp(ZJITState::get_function_stub_hit_trampoline().into());

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        code_ptr
    })
}

/// Generate a trampoline that is used when a
pub fn gen_function_stub_hit_trampoline(cb: &mut CodeBlock) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();
    asm_comment!(asm, "function_stub_hit trampoline");

    // Maintain alignment for x86_64, and set up a frame for arm64 properly
    asm.frame_setup(&[], 0);

    asm_comment!(asm, "preserve argument registers");
    for &reg in ALLOC_REGS.iter() {
        asm.cpush(Opnd::Reg(reg));
    }
    const { assert!(ALLOC_REGS.len() % 2 == 0, "x86_64 would need to push one more if we push an odd number of regs"); }

    // Compile the stubbed ISEQ
    let jump_addr = asm_ccall!(asm, function_stub_hit, SCRATCH_OPND, CFP, SP);
    asm.mov(SCRATCH_OPND, jump_addr);

    asm_comment!(asm, "restore argument registers");
    for &reg in ALLOC_REGS.iter().rev() {
        asm.cpop_into(Opnd::Reg(reg));
    }

    // Discard the current frame since the JIT function will set it up again
    asm.frame_teardown(&[]);

    // Jump to SCRATCH_OPND so that cpop_into() doesn't clobber it
    asm.jmp_opnd(SCRATCH_OPND);

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        code_ptr
    })
}

/// Generate a trampoline that is used when a function exits without restoring PC and the stack
pub fn gen_exit_trampoline(cb: &mut CodeBlock) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();

    asm_comment!(asm, "side-exit trampoline");
    asm.frame_teardown(&[]); // matching the setup in :bb0-prologue:
    asm.cret(Qundef.into());

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        code_ptr
    })
}

/// Generate a trampoline that increments exit_compilation_failure and jumps to exit_trampoline.
pub fn gen_exit_trampoline_with_counter(cb: &mut CodeBlock, exit_trampoline: CodePtr) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();

    asm_comment!(asm, "function stub exit trampoline");
    gen_incr_counter(&mut asm, exit_compile_error);
    asm.jmp(Target::CodePtr(exit_trampoline));

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        code_ptr
    })
}

fn gen_push_opnds(jit: &mut JITState, asm: &mut Assembler, opnds: &[Opnd]) -> lir::Opnd {
    let n = opnds.len();

    // Calculate the compile-time NATIVE_STACK_PTR offset from NATIVE_BASE_PTR
    // At this point, frame_setup(&[], jit.c_stack_slots) has been called,
    // which allocated aligned_stack_bytes(jit.c_stack_slots) on the stack
    let frame_size = aligned_stack_bytes(jit.c_stack_slots);
    let allocation_size = aligned_stack_bytes(n);

    asm_comment!(asm, "allocate {} bytes on C stack for {} values", allocation_size, n);
    asm.sub_into(NATIVE_STACK_PTR, allocation_size.into());

    // Calculate the total offset from NATIVE_BASE_PTR to our buffer
    let total_offset_from_base = (frame_size + allocation_size) as i32;

    for (idx, &opnd) in opnds.iter().enumerate() {
        let slot_offset = -total_offset_from_base + (idx as i32 * SIZEOF_VALUE_I32);
        asm.mov(
            Opnd::mem(VALUE_BITS, NATIVE_BASE_PTR, slot_offset),
            opnd
        );
    }

    asm.lea(Opnd::mem(64, NATIVE_BASE_PTR, -total_offset_from_base))
}

fn gen_pop_opnds(asm: &mut Assembler, opnds: &[Opnd]) {
    asm_comment!(asm, "restore C stack pointer");
    let allocation_size = aligned_stack_bytes(opnds.len());
    asm.add_into(NATIVE_STACK_PTR, allocation_size.into());
}

fn gen_toregexp(jit: &mut JITState, asm: &mut Assembler, opt: usize, values: Vec<Opnd>, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let first_opnd_ptr = gen_push_opnds(jit, asm, &values);

    let tmp_ary = asm_ccall!(asm, rb_ary_tmp_new_from_values, Opnd::Imm(0), values.len().into(), first_opnd_ptr);
    let result = asm_ccall!(asm, rb_reg_new_ary, tmp_ary, opt.into());
    asm_ccall!(asm, rb_ary_clear, tmp_ary);

    gen_pop_opnds(asm, &values);

    result
}

fn gen_string_concat(jit: &mut JITState, asm: &mut Assembler, strings: Vec<Opnd>, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let first_string_ptr = gen_push_opnds(jit, asm, &strings);
    let result = asm_ccall!(asm, rb_str_concat_literals, strings.len().into(), first_string_ptr);
    gen_pop_opnds(asm, &strings);

    result
}

/// Generate a JIT entry that just increments exit_compilation_failure and exits
fn gen_compile_error_counter(cb: &mut CodeBlock, compile_error: &CompileError) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();
    gen_incr_counter(&mut asm, exit_compile_error);
    gen_incr_counter(&mut asm, exit_counter_for_compile_error(compile_error));
    asm.cret(Qundef.into());

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(0, gc_offsets.len());
        code_ptr
    })
}

/// Given the number of spill slots needed for a function, return the number of bytes
/// the function needs to allocate on the stack for the stack frame.
fn aligned_stack_bytes(num_slots: usize) -> usize {
    // Both x86_64 and arm64 require the stack to be aligned to 16 bytes.
    // Since SIZEOF_VALUE is 8 bytes, we need to round up the size to the nearest even number.
    let num_slots = num_slots + (num_slots % 2);
    num_slots * SIZEOF_VALUE
}

impl Assembler {
    /// Make a C call while marking the start and end positions for IseqCall
    fn ccall_with_iseq_call(&mut self, fptr: *const u8, opnds: Vec<Opnd>, iseq_call: &Rc<RefCell<IseqCall>>) -> Opnd {
        // We need to create our own branch rc objects so that we can move the closure below
        let start_iseq_call = iseq_call.clone();
        let end_iseq_call = iseq_call.clone();

        self.ccall_with_pos_markers(
            fptr,
            opnds,
            move |code_ptr, _| {
                start_iseq_call.borrow_mut().start_addr.set(Some(code_ptr));
            },
            move |code_ptr, _| {
                end_iseq_call.borrow_mut().end_addr.set(Some(code_ptr));
            },
        )
    }
}

/// Store info about a JIT-to-JIT call
#[derive(Debug)]
pub struct IseqCall {
    /// Callee ISEQ that start_addr jumps to
    pub iseq: IseqPtr,

    /// Position where the call instruction starts
    start_addr: Cell<Option<CodePtr>>,

    /// Position where the call instruction ends (exclusive)
    end_addr: Cell<Option<CodePtr>>,
}

type IseqCallRef = Rc<RefCell<IseqCall>>;

impl IseqCall {
    /// Allocate a new IseqCall
    fn new(iseq: IseqPtr) -> Rc<RefCell<Self>> {
        let iseq_call = IseqCall {
            iseq,
            start_addr: Cell::new(None),
            end_addr: Cell::new(None),
        };
        Rc::new(RefCell::new(iseq_call))
    }

    /// Regenerate a IseqCall with a given callback
    fn regenerate(&self, cb: &mut CodeBlock, callback: impl Fn(&mut Assembler)) {
        cb.with_write_ptr(self.start_addr.get().unwrap(), |cb| {
            let mut asm = Assembler::new();
            callback(&mut asm);
            asm.compile(cb).unwrap();
            assert_eq!(self.end_addr.get().unwrap(), cb.get_write_ptr());
        });
    }
}
