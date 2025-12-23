//! This module is for native code generation.

#![allow(clippy::let_and_return)]

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::ffi::{c_int, c_long, c_void};
use std::slice;

use crate::backend::current::ALLOC_REGS;
use crate::invariants::{
    track_bop_assumption, track_cme_assumption, track_no_ep_escape_assumption, track_no_trace_point_assumption,
    track_single_ractor_assumption, track_stable_constant_names_assumption, track_no_singleton_class_assumption
};
use crate::gc::append_gc_offsets;
use crate::payload::{get_or_create_iseq_payload, IseqCodePtrs, IseqVersion, IseqVersionRef, IseqStatus};
use crate::state::ZJITState;
use crate::stats::{CompileError, exit_counter_for_compile_error, exit_counter_for_unhandled_hir_insn, incr_counter, incr_counter_by, send_fallback_counter, send_fallback_counter_for_method_type, send_fallback_counter_ptr_for_opcode, send_without_block_fallback_counter_for_method_type, send_without_block_fallback_counter_for_optimized_method_type};
use crate::stats::{counter_ptr, with_time_stat, Counter, Counter::{compile_time_ns, exit_compile_error}};
use crate::{asm::CodeBlock, cruby::*, options::debug, virtualmem::CodePtr};
use crate::backend::lir::{self, Assembler, C_ARG_OPNDS, C_RET_OPND, CFP, EC, NATIVE_BASE_PTR, NATIVE_STACK_PTR, Opnd, SP, SideExit, Target, asm_ccall, asm_comment};
use crate::hir::{iseq_to_hir, BlockId, BranchEdge, Invariant, RangeType, SideExitReason::{self, *}, SpecialBackrefSymbol, SpecialObjectType};
use crate::hir::{Const, FrameState, Function, Insn, InsnId, SendFallbackReason};
use crate::hir_type::{types, Type};
use crate::options::get_option;
use crate::cast::IntoUsize;

/// At the moment, we support recompiling each ISEQ only once.
pub const MAX_ISEQ_VERSIONS: usize = 2;

/// Sentinel program counter stored in C frames when runtime checks are enabled.
const PC_POISON: Option<*const VALUE> = if cfg!(feature = "runtime_checks") {
    Some(usize::MAX as *const VALUE)
} else {
    None
};

/// Ephemeral code generation state
struct JITState {
    /// Instruction sequence for the method being compiled
    iseq: IseqPtr,

    /// ISEQ version that is being compiled, which will be used by PatchPoint
    version: IseqVersionRef,

    /// Low-level IR Operands indexed by High-level IR's Instruction ID
    opnds: Vec<Option<Opnd>>,

    /// Labels for each basic block indexed by the BlockId
    labels: Vec<Option<Target>>,

    /// JIT entry point for the `iseq`
    jit_entries: Vec<Rc<RefCell<JITEntry>>>,

    /// ISEQ calls that need to be compiled later
    iseq_calls: Vec<IseqCallRef>,
}

impl JITState {
    /// Create a new JITState instance
    fn new(iseq: IseqPtr, version: IseqVersionRef, num_insns: usize, num_blocks: usize) -> Self {
        JITState {
            iseq,
            version,
            opnds: vec![None; num_insns],
            labels: vec![None; num_blocks],
            jit_entries: Vec::default(),
            iseq_calls: Vec::default(),
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
        // We need to do this even if code_ptr is None because gen_iseq() may have already used asm.compile().
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
    let IseqCodePtrs { start_ptr, .. } = gen_iseq(cb, iseq, Some(&function)).inspect_err(|err| {
        debug!("{err:?}: gen_iseq failed: {}", iseq_get_location(iseq, 0));
    })?;

    Ok(start_ptr)
}

/// Stub a branch for a JIT-to-JIT call
pub fn gen_iseq_call(cb: &mut CodeBlock, iseq_call: &IseqCallRef) -> Result<(), CompileError> {
    // Compile a function stub
    let stub_ptr = gen_function_stub(cb, iseq_call.clone()).inspect_err(|err| {
        debug!("{err:?}: gen_function_stub failed: {}", iseq_get_location(iseq_call.iseq.get(), 0));
    })?;

    // Update the JIT-to-JIT call to call the stub
    let stub_addr = stub_ptr.raw_ptr(cb);
    let iseq = iseq_call.iseq.get();
    iseq_call.regenerate(cb, |asm| {
        asm_comment!(asm, "call function stub: {}", iseq_get_location(iseq, 0));
        asm.ccall(stub_addr, vec![]);
    });
    Ok(())
}

/// Write an entry to the perf map in /tmp
fn register_with_perf(iseq_name: String, start_ptr: usize, code_size: usize) {
    use std::io::Write;
    let perf_map = format!("/tmp/perf-{}.map", std::process::id());
    let Ok(file) = std::fs::OpenOptions::new().create(true).append(true).open(&perf_map) else {
        debug!("Failed to open perf map file: {perf_map}");
        return;
    };
    let mut file = std::io::BufWriter::new(file);
    let Ok(_) = writeln!(file, "{start_ptr:#x} {code_size:#x} zjit::{iseq_name}") else {
        debug!("Failed to write {iseq_name} to perf map file: {perf_map}");
        return;
    };
}

/// Compile a shared JIT entry trampoline
pub fn gen_entry_trampoline(cb: &mut CodeBlock) -> Result<CodePtr, CompileError> {
    // Set up registers for CFP, EC, SP, and basic block arguments
    let mut asm = Assembler::new();
    gen_entry_prologue(&mut asm);

    // Jump to the first block using a call instruction. This trampoline is used
    // as rb_zjit_func_t in jit_exec(), which takes (EC, CFP, rb_jit_func_t).
    // So C_ARG_OPNDS[2] is rb_jit_func_t, which is (EC, CFP) -> VALUE.
    asm.ccall_reg(C_ARG_OPNDS[2], VALUE_BITS);

    // Restore registers for CFP, EC, and SP after use
    asm_comment!(asm, "return to the interpreter");
    asm.frame_teardown(lir::JIT_PRESERVED_REGS);
    asm.cret(C_RET_OPND);

    let (code_ptr, gc_offsets) = asm.compile(cb)?;
    assert!(gc_offsets.is_empty());
    if get_option!(perf) {
        let start_ptr = code_ptr.raw_addr(cb);
        let end_ptr = cb.get_write_ptr().raw_addr(cb);
        let code_size = end_ptr - start_ptr;
        register_with_perf("ZJIT entry trampoline".into(), start_ptr, code_size);
    }
    Ok(code_ptr)
}

/// Compile an ISEQ into machine code if not compiled yet
fn gen_iseq(cb: &mut CodeBlock, iseq: IseqPtr, function: Option<&Function>) -> Result<IseqCodePtrs, CompileError> {
    // Return an existing pointer if it's already compiled
    let payload = get_or_create_iseq_payload(iseq);
    let last_status = payload.versions.last().map(|version| &unsafe { version.as_ref() }.status);
    match last_status {
        Some(IseqStatus::Compiled(code_ptrs)) => return Ok(code_ptrs.clone()),
        Some(IseqStatus::CantCompile(err)) => return Err(err.clone()),
        _ => {},
    }
    // If the ISEQ already hax MAX_ISEQ_VERSIONS, do not compile a new version.
    if payload.versions.len() == MAX_ISEQ_VERSIONS {
        return Err(CompileError::IseqVersionLimitReached);
    }

    // Compile the ISEQ
    let mut version = IseqVersion::new(iseq);
    let code_ptrs = gen_iseq_body(cb, iseq, version, function);
    match &code_ptrs {
        Ok(code_ptrs) => {
            unsafe { version.as_mut() }.status = IseqStatus::Compiled(code_ptrs.clone());
            incr_counter!(compiled_iseq_count);
        }
        Err(err) => {
            unsafe { version.as_mut() }.status = IseqStatus::CantCompile(err.clone());
            incr_counter!(failed_iseq_count);
        }
    }
    payload.versions.push(version);
    code_ptrs
}

/// Compile an ISEQ into machine code
fn gen_iseq_body(cb: &mut CodeBlock, iseq: IseqPtr, mut version: IseqVersionRef, function: Option<&Function>) -> Result<IseqCodePtrs, CompileError> {
    // If we ran out of code region, we shouldn't attempt to generate new code.
    if cb.has_dropped_bytes() {
        return Err(CompileError::OutOfMemory);
    }

    // Convert ISEQ into optimized High-level IR if not given
    let function = match function {
        Some(function) => function,
        None => &compile_iseq(iseq)?,
    };

    // Compile the High-level IR
    let (iseq_code_ptrs, gc_offsets, iseq_calls) = gen_function(cb, iseq, version, function)?;

    // Stub callee ISEQs for JIT-to-JIT calls
    for iseq_call in iseq_calls.iter() {
        gen_iseq_call(cb, iseq_call)?;
    }

    // Prepare for GC
    unsafe { version.as_mut() }.outgoing.extend(iseq_calls);
    append_gc_offsets(iseq, version, &gc_offsets);
    Ok(iseq_code_ptrs)
}

/// Compile a function
fn gen_function(cb: &mut CodeBlock, iseq: IseqPtr, version: IseqVersionRef, function: &Function) -> Result<(IseqCodePtrs, Vec<CodePtr>, Vec<IseqCallRef>), CompileError> {
    let num_spilled_params = max_num_params(function).saturating_sub(ALLOC_REGS.len());
    let mut jit = JITState::new(iseq, version, function.num_insns(), function.num_blocks());
    let mut asm = Assembler::new_with_stack_slots(num_spilled_params);

    // Compile each basic block
    let reverse_post_order = function.rpo();
    for &block_id in reverse_post_order.iter() {
        // Write a label to jump to the basic block
        let label = jit.get_label(&mut asm, block_id);
        asm.write_label(label);

        let block = function.block(block_id);
        asm_comment!(
            asm, "{block_id}({}): {}",
            block.params().map(|param| format!("{param}")).collect::<Vec<_>>().join(", "),
            iseq_get_location(iseq, block.insn_idx),
        );

        // Compile all parameters
        for (idx, &insn_id) in block.params().enumerate() {
            match function.find(insn_id) {
                Insn::Param => {
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
                gen_incr_counter(&mut asm, exit_counter_for_unhandled_hir_insn(&insn));
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

    // Generate code if everything can be compiled
    let result = asm.compile(cb);
    if let Ok((start_ptr, _)) = result {
        if get_option!(perf) {
            let start_usize = start_ptr.raw_addr(cb);
            let end_usize = cb.get_write_ptr().raw_addr(cb);
            let code_size = end_usize - start_usize;
            let iseq_name = iseq_get_location(iseq, 0);
            register_with_perf(iseq_name, start_usize, code_size);
        }
        if ZJITState::should_log_compiled_iseqs() {
            let iseq_name = iseq_get_location(iseq, 0);
            ZJITState::log_compile(iseq_name);
        }
    }
    result.map(|(start_ptr, gc_offsets)| {
        // Make sure jit_entry_ptrs can be used as a parallel vector to jit_entry_insns()
        jit.jit_entries.sort_by_key(|jit_entry| jit_entry.borrow().jit_entry_idx);

        let jit_entry_ptrs = jit.jit_entries.iter().map(|jit_entry|
            jit_entry.borrow().start_addr.get().expect("start_addr should have been set by pos_marker in gen_entry_point")
        ).collect();
        (IseqCodePtrs { start_ptr, jit_entry_ptrs }, gc_offsets, jit.iseq_calls)
    })
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
        &Insn::Const { val: Const::Value(val) } => gen_const_value(val),
        &Insn::Const { val: Const::CPtr(val) } => gen_const_cptr(val),
        &Insn::Const { val: Const::CInt64(val) } => gen_const_long(val),
        &Insn::Const { val: Const::CUInt16(val) } => gen_const_uint16(val),
        &Insn::Const { val: Const::CUInt32(val) } => gen_const_uint32(val),
        &Insn::Const { val: Const::CShape(val) } => {
            assert_eq!(SHAPE_ID_NUM_BITS, 32);
            gen_const_uint32(val.0)
        }
        Insn::Const { .. } => panic!("Unexpected Const in gen_insn: {insn}"),
        Insn::NewArray { elements, state } => gen_new_array(asm, opnds!(elements), &function.frame_state(*state)),
        Insn::NewHash { elements, state } => gen_new_hash(jit, asm, opnds!(elements), &function.frame_state(*state)),
        Insn::NewRange { low, high, flag, state } => gen_new_range(jit, asm, opnd!(low), opnd!(high), *flag, &function.frame_state(*state)),
        Insn::NewRangeFixnum { low, high, flag, state } => gen_new_range_fixnum(asm, opnd!(low), opnd!(high), *flag, &function.frame_state(*state)),
        Insn::ArrayDup { val, state } => gen_array_dup(asm, opnd!(val), &function.frame_state(*state)),
        Insn::ArrayArefFixnum { array, index, .. } => gen_aref_fixnum(asm, opnd!(array), opnd!(index)),
        Insn::ArrayPop { array, state } => gen_array_pop(asm, opnd!(array), &function.frame_state(*state)),
        Insn::ArrayLength { array } => gen_array_length(asm, opnd!(array)),
        Insn::ObjectAlloc { val, state } => gen_object_alloc(jit, asm, opnd!(val), &function.frame_state(*state)),
        &Insn::ObjectAllocClass { class, state } => gen_object_alloc_class(asm, class, &function.frame_state(state)),
        Insn::StringCopy { val, chilled, state } => gen_string_copy(asm, opnd!(val), *chilled, &function.frame_state(*state)),
        // concatstrings shouldn't have 0 strings
        // If it happens we abort the compilation for now
        Insn::StringConcat { strings, state, .. } if strings.is_empty() => return Err(*state),
        Insn::StringConcat { strings, state } => gen_string_concat(jit, asm, opnds!(strings), &function.frame_state(*state)),
        &Insn::StringGetbyte { string, index } => gen_string_getbyte(asm, opnd!(string), opnd!(index)),
        Insn::StringSetbyteFixnum { string, index, value } => gen_string_setbyte_fixnum(asm, opnd!(string), opnd!(index), opnd!(value)),
        Insn::StringAppend { recv, other, state } => gen_string_append(jit, asm, opnd!(recv), opnd!(other), &function.frame_state(*state)),
        Insn::StringAppendCodepoint { recv, other, state } => gen_string_append_codepoint(jit, asm, opnd!(recv), opnd!(other), &function.frame_state(*state)),
        Insn::StringIntern { val, state } => gen_intern(asm, opnd!(val), &function.frame_state(*state)),
        Insn::ToRegexp { opt, values, state } => gen_toregexp(jit, asm, *opt, opnds!(values), &function.frame_state(*state)),
        Insn::Param => unreachable!("block.insns should not have Insn::Param"),
        Insn::Snapshot { .. } => return Ok(()), // we don't need to do anything for this instruction at the moment
        Insn::Jump(branch) => no_output!(gen_jump(jit, asm, branch)),
        Insn::IfTrue { val, target } => no_output!(gen_if_true(jit, asm, opnd!(val), target)),
        Insn::IfFalse { val, target } => no_output!(gen_if_false(jit, asm, opnd!(val), target)),
        &Insn::Send { cd, blockiseq, state, reason, .. } => gen_send(jit, asm, cd, blockiseq, &function.frame_state(state), reason),
        &Insn::SendForward { cd, blockiseq, state, reason, .. } => gen_send_forward(jit, asm, cd, blockiseq, &function.frame_state(state), reason),
        &Insn::SendWithoutBlock { cd, state, reason, .. } => gen_send_without_block(jit, asm, cd, &function.frame_state(state), reason),
        // Give up SendWithoutBlockDirect for 6+ args since asm.ccall() doesn't support it.
        Insn::SendWithoutBlockDirect { cd, state, args, .. } if args.len() + 1 > C_ARG_OPNDS.len() => // +1 for self
            gen_send_without_block(jit, asm, *cd, &function.frame_state(*state), SendFallbackReason::TooManyArgsForLir),
        Insn::SendWithoutBlockDirect { cme, iseq, recv, args, state, .. } => gen_send_without_block_direct(cb, jit, asm, *cme, *iseq, opnd!(recv), opnds!(args), &function.frame_state(*state)),
        &Insn::InvokeSuper { cd, blockiseq, state, reason, .. } => gen_invokesuper(jit, asm, cd, blockiseq, &function.frame_state(state), reason),
        &Insn::InvokeBlock { cd, state, reason, .. } => gen_invokeblock(jit, asm, cd, &function.frame_state(state), reason),
        // Ensure we have enough room fit ec, self, and arguments
        // TODO remove this check when we have stack args (we can use Time.new to test it)
        Insn::InvokeBuiltin { bf, state, .. } if bf.argc + 2 > (C_ARG_OPNDS.len() as i32) => return Err(*state),
        Insn::InvokeBuiltin { bf, leaf, args, state, .. } => gen_invokebuiltin(jit, asm, &function.frame_state(*state), bf, *leaf, opnds!(args)),
        &Insn::EntryPoint { jit_entry_idx } => no_output!(gen_entry_point(jit, asm, jit_entry_idx)),
        Insn::Return { val } => no_output!(gen_return(asm, opnd!(val))),
        Insn::FixnumAdd { left, right, state } => gen_fixnum_add(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumSub { left, right, state } => gen_fixnum_sub(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumMult { left, right, state } => gen_fixnum_mult(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumDiv { left, right, state } => gen_fixnum_div(jit, asm, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumEq { left, right } => gen_fixnum_eq(asm, opnd!(left), opnd!(right)),
        Insn::FixnumNeq { left, right } => gen_fixnum_neq(asm, opnd!(left), opnd!(right)),
        Insn::FixnumLt { left, right } => gen_fixnum_lt(asm, opnd!(left), opnd!(right)),
        Insn::FixnumLe { left, right } => gen_fixnum_le(asm, opnd!(left), opnd!(right)),
        Insn::FixnumGt { left, right } => gen_fixnum_gt(asm, opnd!(left), opnd!(right)),
        Insn::FixnumGe { left, right } => gen_fixnum_ge(asm, opnd!(left), opnd!(right)),
        Insn::FixnumAnd { left, right } => gen_fixnum_and(asm, opnd!(left), opnd!(right)),
        Insn::FixnumOr { left, right } => gen_fixnum_or(asm, opnd!(left), opnd!(right)),
        Insn::FixnumXor { left, right } => gen_fixnum_xor(asm, opnd!(left), opnd!(right)),
        &Insn::FixnumLShift { left, right, state } => {
            // We only create FixnumLShift when we know the shift amount statically and it's in [0,
            // 63].
            let shift_amount = function.type_of(right).fixnum_value().unwrap() as u64;
            gen_fixnum_lshift(jit, asm, opnd!(left), shift_amount, &function.frame_state(state))
        }
        &Insn::FixnumRShift { left, right } => {
            // We only create FixnumRShift when we know the shift amount statically and it's in [0,
            // 63].
            let shift_amount = function.type_of(right).fixnum_value().unwrap() as u64;
            gen_fixnum_rshift(asm, opnd!(left), shift_amount)
        }
        &Insn::FixnumMod { left, right, state } => gen_fixnum_mod(jit, asm, opnd!(left), opnd!(right), &function.frame_state(state)),
        Insn::IsNil { val } => gen_isnil(asm, opnd!(val)),
        &Insn::IsMethodCfunc { val, cd, cfunc, state: _ } => gen_is_method_cfunc(jit, asm, opnd!(val), cd, cfunc),
        &Insn::IsBitEqual { left, right } => gen_is_bit_equal(asm, opnd!(left), opnd!(right)),
        &Insn::IsBitNotEqual { left, right } => gen_is_bit_not_equal(asm, opnd!(left), opnd!(right)),
        &Insn::BoxBool { val } => gen_box_bool(asm, opnd!(val)),
        &Insn::BoxFixnum { val, state } => gen_box_fixnum(jit, asm, opnd!(val), &function.frame_state(state)),
        &Insn::UnboxFixnum { val } => gen_unbox_fixnum(asm, opnd!(val)),
        Insn::Test { val } => gen_test(asm, opnd!(val)),
        Insn::GuardType { val, guard_type, state } => gen_guard_type(jit, asm, opnd!(val), *guard_type, &function.frame_state(*state)),
        Insn::GuardTypeNot { val, guard_type, state } => gen_guard_type_not(jit, asm, opnd!(val), *guard_type, &function.frame_state(*state)),
        Insn::GuardBitEquals { val, expected, state } => gen_guard_bit_equals(jit, asm, opnd!(val), *expected, &function.frame_state(*state)),
        &Insn::GuardBlockParamProxy { level, state } => no_output!(gen_guard_block_param_proxy(jit, asm, level, &function.frame_state(state))),
        Insn::GuardNotFrozen { recv, state } => gen_guard_not_frozen(jit, asm, opnd!(recv), &function.frame_state(*state)),
        &Insn::GuardLess { left, right, state } => gen_guard_less(jit, asm, opnd!(left), opnd!(right), &function.frame_state(state)),
        &Insn::GuardGreaterEq { left, right, state } => gen_guard_greater_eq(jit, asm, opnd!(left), opnd!(right), &function.frame_state(state)),
        Insn::PatchPoint { invariant, state } => no_output!(gen_patch_point(jit, asm, invariant, &function.frame_state(*state))),
        Insn::CCall { cfunc, recv, args, name, return_type: _, elidable: _ } => gen_ccall(asm, *cfunc, *name, opnd!(recv), opnds!(args)),
        // Give up CCallWithFrame for 7+ args since asm.ccall() supports at most 6 args (recv + args).
        // There's no test case for this because no core cfuncs have this many parameters. But C extensions could have such methods.
        Insn::CCallWithFrame { cd, state, args, .. } if args.len() + 1 > C_ARG_OPNDS.len() =>
            gen_send_without_block(jit, asm, *cd, &function.frame_state(*state), SendFallbackReason::CCallWithFrameTooManyArgs),
        Insn::CCallWithFrame { cfunc, recv, name, args, cme, state, blockiseq, .. } =>
            gen_ccall_with_frame(jit, asm, *cfunc, *name, opnd!(recv), opnds!(args), *cme, *blockiseq, &function.frame_state(*state)),
        Insn::CCallVariadic { cfunc, recv, name, args, cme, state, blockiseq, return_type: _, elidable: _ } => {
            gen_ccall_variadic(jit, asm, *cfunc, *name, opnd!(recv), opnds!(args), *cme, *blockiseq, &function.frame_state(*state))
        }
        Insn::GetIvar { self_val, id, ic, state: _ } => gen_getivar(jit, asm, opnd!(self_val), *id, *ic),
        Insn::SetGlobal { id, val, state } => no_output!(gen_setglobal(jit, asm, *id, opnd!(val), &function.frame_state(*state))),
        Insn::GetGlobal { id, state } => gen_getglobal(jit, asm, *id, &function.frame_state(*state)),
        &Insn::GetLocal { ep_offset, level, use_sp, .. } => gen_getlocal(asm, ep_offset, level, use_sp),
        &Insn::SetLocal { val, ep_offset, level } => no_output!(gen_setlocal(asm, opnd!(val), function.type_of(val), ep_offset, level)),
        Insn::GetConstantPath { ic, state } => gen_get_constant_path(jit, asm, *ic, &function.frame_state(*state)),
        Insn::GetClassVar { id, ic, state } => gen_getclassvar(jit, asm, *id, *ic, &function.frame_state(*state)),
        Insn::SetClassVar { id, val, ic, state } => no_output!(gen_setclassvar(jit, asm, *id, opnd!(val), *ic, &function.frame_state(*state))),
        Insn::SetIvar { self_val, id, ic, val, state } => no_output!(gen_setivar(jit, asm, opnd!(self_val), *id, *ic, opnd!(val), &function.frame_state(*state))),
        Insn::FixnumBitCheck { val, index } => gen_fixnum_bit_check(asm, opnd!(val), *index),
        Insn::SideExit { state, reason } => no_output!(gen_side_exit(jit, asm, reason, &function.frame_state(*state))),
        Insn::PutSpecialObject { value_type } => gen_putspecialobject(asm, *value_type),
        Insn::AnyToString { val, str, state } => gen_anytostring(asm, opnd!(val), opnd!(str), &function.frame_state(*state)),
        Insn::Defined { op_type, obj, pushval, v, state } => gen_defined(jit, asm, *op_type, *obj, *pushval, opnd!(v), &function.frame_state(*state)),
        Insn::GetSpecialSymbol { symbol_type, state: _ } => gen_getspecial_symbol(asm, *symbol_type),
        Insn::GetSpecialNumber { nth, state } => gen_getspecial_number(asm, *nth, &function.frame_state(*state)),
        &Insn::IncrCounter(counter) => no_output!(gen_incr_counter(asm, counter)),
        Insn::IncrCounterPtr { counter_ptr } => no_output!(gen_incr_counter_ptr(asm, *counter_ptr)),
        Insn::ObjToString { val, cd, state, .. } => gen_objtostring(jit, asm, opnd!(val), *cd, &function.frame_state(*state)),
        &Insn::CheckInterrupts { state } => no_output!(gen_check_interrupts(jit, asm, &function.frame_state(state))),
        &Insn::HashDup { val, state } => { gen_hash_dup(asm, opnd!(val), &function.frame_state(state)) },
        &Insn::HashAref { hash, key, state } => { gen_hash_aref(jit, asm, opnd!(hash), opnd!(key), &function.frame_state(state)) },
        &Insn::HashAset { hash, key, val, state } => { no_output!(gen_hash_aset(jit, asm, opnd!(hash), opnd!(key), opnd!(val), &function.frame_state(state))) },
        &Insn::ArrayPush { array, val, state } => { no_output!(gen_array_push(asm, opnd!(array), opnd!(val), &function.frame_state(state))) },
        &Insn::ToNewArray { val, state } => { gen_to_new_array(jit, asm, opnd!(val), &function.frame_state(state)) },
        &Insn::ToArray { val, state } => { gen_to_array(jit, asm, opnd!(val), &function.frame_state(state)) },
        &Insn::DefinedIvar { self_val, id, pushval, .. } => { gen_defined_ivar(asm, opnd!(self_val), id, pushval) },
        &Insn::ArrayExtend { left, right, state } => { no_output!(gen_array_extend(jit, asm, opnd!(left), opnd!(right), &function.frame_state(state))) },
        &Insn::GuardShape { val, shape, state } => gen_guard_shape(jit, asm, opnd!(val), shape, &function.frame_state(state)),
        Insn::LoadPC => gen_load_pc(asm),
        Insn::LoadEC => gen_load_ec(),
        Insn::LoadSelf => gen_load_self(),
        &Insn::LoadField { recv, id, offset, return_type: _ } => gen_load_field(asm, opnd!(recv), id, offset),
        &Insn::StoreField { recv, id, offset, val } => no_output!(gen_store_field(asm, opnd!(recv), id, offset, opnd!(val), function.type_of(val))),
        &Insn::WriteBarrier { recv, val } => no_output!(gen_write_barrier(asm, opnd!(recv), opnd!(val), function.type_of(val))),
        &Insn::IsBlockGiven => gen_is_block_given(jit, asm),
        Insn::ArrayInclude { elements, target, state } => gen_array_include(jit, asm, opnds!(elements), opnd!(target), &function.frame_state(*state)),
        Insn::ArrayPackBuffer { elements, fmt, buffer, state } => gen_array_pack_buffer(jit, asm, opnds!(elements), opnd!(fmt), opnd!(buffer), &function.frame_state(*state)),
        &Insn::DupArrayInclude { ary, target, state } => gen_dup_array_include(jit, asm, ary, opnd!(target), &function.frame_state(state)),
        Insn::ArrayHash { elements, state } => gen_opt_newarray_hash(jit, asm, opnds!(elements), &function.frame_state(*state)),
        &Insn::IsA { val, class } => gen_is_a(asm, opnd!(val), opnd!(class)),
        &Insn::ArrayMax { state, .. }
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
    // TODO: Specialize for immediate types
    // Call rb_vm_objtostring(iseq, recv, cd)
    let ret = asm_ccall!(asm, rb_vm_objtostring, VALUE::from(jit.iseq).into(), val, Opnd::const_ptr(cd));

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
            //
            // Similar to gen_is_block_given
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

/// Similar to gen_defined for DEFINED_YIELD
fn gen_is_block_given(jit: &JITState, asm: &mut Assembler) -> Opnd {
    let local_iseq = unsafe { rb_get_iseq_body_local_iseq(jit.iseq) };
    if unsafe { rb_get_iseq_body_type(local_iseq) } == ISEQ_TYPE_METHOD {
        let lep = gen_get_lep(jit, asm);
        let block_handler = asm.load(Opnd::mem(64, lep, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL));
        asm.cmp(block_handler, VM_BLOCK_HANDLER_NONE.into());
        asm.csel_e(Qfalse.into(), Qtrue.into())
    } else {
        Qfalse.into()
    }
}

fn gen_unbox_fixnum(asm: &mut Assembler, val: Opnd) -> Opnd {
    asm.rshift(val, Opnd::UImm(1))
}

/// Get a local variable from a higher scope or the heap. `local_ep_offset` is in number of VALUEs.
/// We generate this instruction with level=0 only when the local variable is on the heap, so we
/// can't optimize the level=0 case using the SP register.
fn gen_getlocal(asm: &mut Assembler, local_ep_offset: u32, level: u32, use_sp: bool) -> lir::Opnd {
    let local_ep_offset = i32::try_from(local_ep_offset).unwrap_or_else(|_| panic!("Could not convert local_ep_offset {local_ep_offset} to i32"));
    if level > 0 {
        gen_incr_counter(asm, Counter::vm_read_from_parent_iseq_local_count);
    }
    let local = if use_sp {
        assert_eq!(level, 0, "use_sp optimization should be used only for level=0 locals");
        let offset = -(SIZEOF_VALUE_I32 * (local_ep_offset + 1));
        Opnd::mem(64, SP, offset)
    } else {
        let ep = gen_get_ep(asm, level);
        let offset = -(SIZEOF_VALUE_I32 * local_ep_offset);
        Opnd::mem(64, ep, offset)
    };
    asm.load(local)
}

/// Set a local variable from a higher scope or the heap. `local_ep_offset` is in number of VALUEs.
/// We generate this instruction with level=0 only when the local variable is on the heap, so we
/// can't optimize the level=0 case using the SP register.
fn gen_setlocal(asm: &mut Assembler, val: Opnd, val_type: Type, local_ep_offset: u32, level: u32) {
    let local_ep_offset = c_int::try_from(local_ep_offset).unwrap_or_else(|_| panic!("Could not convert local_ep_offset {local_ep_offset} to i32"));
    if level > 0 {
        gen_incr_counter(asm, Counter::vm_write_to_parent_iseq_local_count);
    }
    let ep = gen_get_ep(asm, level);

    // When we've proved that we're writing an immediate,
    // we can skip the write barrier.
    if val_type.is_immediate() {
        let offset = -(SIZEOF_VALUE_I32 * local_ep_offset);
        asm.mov(Opnd::mem(64, ep, offset), val);
    } else {
        // We're potentially writing a reference to an IMEMO/env object,
        // so take care of the write barrier with a function.
        let local_index = -local_ep_offset;
        asm_ccall!(asm, rb_vm_env_write, ep, local_index.into(), val);
    }
}

fn gen_guard_block_param_proxy(jit: &JITState, asm: &mut Assembler, level: u32, state: &FrameState) {
    // Bail out if the `&block` local variable has been modified
    let ep = gen_get_ep(asm, level);
    let flags = Opnd::mem(64, ep, SIZEOF_VALUE_I32 * (VM_ENV_DATA_INDEX_FLAGS as i32));
    asm.test(flags, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into());
    asm.jnz(side_exit(jit, state, SideExitReason::BlockParamProxyModified));

    // This handles two cases which are nearly identical
    // Block handler is a tagged pointer. Look at the tag.
    //   VM_BH_ISEQ_BLOCK_P(): block_handler & 0x03 == 0x01
    //   VM_BH_IFUNC_P():      block_handler & 0x03 == 0x03
    // So to check for either of those cases we can use: val & 0x1 == 0x1
    const _: () = assert!(RUBY_SYMBOL_FLAG & 1 == 0, "guard below rejects symbol block handlers");

    // Bail ouf if the block handler is neither ISEQ nor ifunc
    let block_handler = asm.load(Opnd::mem(64, ep, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL));
    asm.test(block_handler, 0x1.into());
    asm.jz(side_exit(jit, state, SideExitReason::BlockParamProxyNotIseqOrIfunc));
}

fn gen_guard_not_frozen(jit: &JITState, asm: &mut Assembler, recv: Opnd, state: &FrameState) -> Opnd {
    let recv = asm.load(recv);
    // It's a heap object, so check the frozen flag
    let flags = asm.load(Opnd::mem(64, recv, RUBY_OFFSET_RBASIC_FLAGS));
    asm.test(flags, (RUBY_FL_FREEZE as u64).into());
    // Side-exit if frozen
    asm.jnz(side_exit(jit, state, GuardNotFrozen));
    recv
}

fn gen_guard_less(jit: &JITState, asm: &mut Assembler, left: Opnd, right: Opnd, state: &FrameState) -> Opnd {
    asm.cmp(left, right);
    asm.jge(side_exit(jit, state, SideExitReason::GuardLess));
    left
}

fn gen_guard_greater_eq(jit: &JITState, asm: &mut Assembler, left: Opnd, right: Opnd, state: &FrameState) -> Opnd {
    asm.cmp(left, right);
    asm.jl(side_exit(jit, state, SideExitReason::GuardGreaterEq));
    left
}

fn gen_get_constant_path(jit: &JITState, asm: &mut Assembler, ic: *const iseq_inline_constant_cache, state: &FrameState) -> Opnd {
    unsafe extern "C" {
        fn rb_vm_opt_getconstant_path(ec: EcPtr, cfp: CfpPtr, ic: *const iseq_inline_constant_cache) -> VALUE;
    }

    // Anything could be called on const_missing
    gen_prepare_non_leaf_call(jit, asm, state);

    asm_ccall!(asm, rb_vm_opt_getconstant_path, EC, CFP, Opnd::const_ptr(ic))
}

fn gen_fixnum_bit_check(asm: &mut Assembler, val: Opnd, index: u8) -> Opnd {
    let bit_test: u64 = 0x01 << (index + 1);
    asm.test(val, bit_test.into());
    asm.csel_z(Qtrue.into(), Qfalse.into())
}

fn gen_invokebuiltin(jit: &JITState, asm: &mut Assembler, state: &FrameState, bf: &rb_builtin_function, leaf: bool, args: Vec<Opnd>) -> lir::Opnd {
    assert!(bf.argc + 2 <= C_ARG_OPNDS.len() as i32,
            "gen_invokebuiltin should not be called for builtin function {} with too many arguments: {}",
            unsafe { std::ffi::CStr::from_ptr(bf.name).to_str().unwrap() },
            bf.argc);
    if leaf {
        gen_prepare_leaf_call_with_gc(asm, state);
    } else {
        // Anything can happen inside builtin functions
        gen_prepare_non_leaf_call(jit, asm, state);
    }

    let mut cargs = vec![EC];
    cargs.extend(args);

    asm.count_call_to(unsafe { std::ffi::CStr::from_ptr(bf.name).to_str().unwrap() });
    asm.ccall(bf.func_ptr as *const u8, cargs)
}

/// Record a patch point that should be invalidated on a given invariant
fn gen_patch_point(jit: &mut JITState, asm: &mut Assembler, invariant: &Invariant, state: &FrameState) {
    let invariant = *invariant;
    let exit = build_side_exit(jit, state);

    // Let compile_exits compile a side exit. Let scratch_split lower it with split_patch_point.
    asm.patch_point(Target::SideExit { exit, reason: PatchPoint(invariant) }, invariant, jit.version);
}

/// This is used by scratch_split to lower PatchPoint into PadPatchPoint and PosMarker.
/// It's called at scratch_split so that we can use the Label after side-exit deduplication in compile_exits.
pub fn split_patch_point(asm: &mut Assembler, target: &Target, invariant: Invariant, version: IseqVersionRef) {
    let Target::Label(exit_label) = *target else {
        unreachable!("PatchPoint's target should have been lowered to Target::Label by compile_exits: {target:?}");
    };

    // Fill nop instructions if the last patch point is too close.
    asm.pad_patch_point();

    // Remember the current address as a patch point
    asm.pos_marker(move |code_ptr, cb| {
        let side_exit_ptr = cb.resolve_label(exit_label);
        match invariant {
            Invariant::BOPRedefined { klass, bop } => {
                track_bop_assumption(klass, bop, code_ptr, side_exit_ptr, version);
            }
            Invariant::MethodRedefined { klass: _, method: _, cme } => {
                track_cme_assumption(cme, code_ptr, side_exit_ptr, version);
            }
            Invariant::StableConstantNames { idlist } => {
                track_stable_constant_names_assumption(idlist, code_ptr, side_exit_ptr, version);
            }
            Invariant::NoTracePoint => {
                track_no_trace_point_assumption(code_ptr, side_exit_ptr, version);
            }
            Invariant::NoEPEscape(iseq) => {
                track_no_ep_escape_assumption(iseq, code_ptr, side_exit_ptr, version);
            }
            Invariant::SingleRactorMode => {
                track_single_ractor_assumption(code_ptr, side_exit_ptr, version);
            }
            Invariant::NoSingletonClass { klass } => {
                track_no_singleton_class_assumption(klass, code_ptr, side_exit_ptr, version);
            }
        }
    });
}

/// Generate code for a C function call that pushes a frame
fn gen_ccall_with_frame(
    jit: &mut JITState,
    asm: &mut Assembler,
    cfunc: *const u8,
    name: ID,
    recv: Opnd,
    args: Vec<Opnd>,
    cme: *const rb_callable_method_entry_t,
    blockiseq: Option<IseqPtr>,
    state: &FrameState,
) -> lir::Opnd {
    gen_incr_counter(asm, Counter::non_variadic_cfunc_optimized_send_count);
    gen_stack_overflow_check(jit, asm, state, state.stack_size());

    let args_with_recv_len = args.len() + 1;
    let caller_stack_size = state.stack().len() - args_with_recv_len;

    // Can't use gen_prepare_non_leaf_call() because we need to adjust the SP
    // to account for the receiver and arguments (and block arguments if any)
    gen_save_pc_for_gc(asm, state);
    gen_save_sp(asm, caller_stack_size);
    gen_spill_stack(jit, asm, state);
    gen_spill_locals(jit, asm, state);

    let block_handler_specval = if let Some(block_iseq) = blockiseq {
        // Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
        // VM_CFP_TO_CAPTURED_BLOCK then turns &cfp->self into a block handler.
        // rb_captured_block->code.iseq aliases with cfp->block_code.
        asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_BLOCK_CODE), VALUE::from(block_iseq).into());
        let cfp_self_addr = asm.lea(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF));
        asm.or(cfp_self_addr, Opnd::Imm(1))
    } else {
        VM_BLOCK_HANDLER_NONE.into()
    };

    gen_push_frame(asm, args_with_recv_len, state, ControlFrame {
        recv,
        iseq: None,
        cme,
        frame_type: VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL,
        pc: PC_POISON,
        specval: block_handler_specval,
    });

    asm_comment!(asm, "switch to new SP register");
    let sp_offset = (caller_stack_size + VM_ENV_DATA_SIZE.to_usize()) * SIZEOF_VALUE;
    let new_sp = asm.add(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP as i32), CFP);

    let mut cfunc_args = vec![recv];
    cfunc_args.extend(args);
    asm.count_call_to(&name.contents_lossy());
    let result = asm.ccall(cfunc, cfunc_args);

    asm_comment!(asm, "pop C frame");
    let new_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP as i32), CFP);

    asm_comment!(asm, "restore SP register for the caller");
    let new_sp = asm.sub(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    result
}

/// Lowering for [`Insn::CCall`]. This is a low-level raw call that doesn't know
/// anything about the callee, so handling for e.g. GC safety is dealt with elsewhere.
fn gen_ccall(asm: &mut Assembler, cfunc: *const u8, name: ID, recv: Opnd, args: Vec<Opnd>) -> lir::Opnd {
    let mut cfunc_args = vec![recv];
    cfunc_args.extend(args);
    asm.count_call_to(&name.contents_lossy());
    asm.ccall(cfunc, cfunc_args)
}

/// Generate code for a variadic C function call
/// func(int argc, VALUE *argv, VALUE recv)
fn gen_ccall_variadic(
    jit: &mut JITState,
    asm: &mut Assembler,
    cfunc: *const u8,
    name: ID,
    recv: Opnd,
    args: Vec<Opnd>,
    cme: *const rb_callable_method_entry_t,
    blockiseq: Option<IseqPtr>,
    state: &FrameState,
) -> lir::Opnd {
    gen_incr_counter(asm, Counter::variadic_cfunc_optimized_send_count);
    gen_stack_overflow_check(jit, asm, state, state.stack_size());

    let args_with_recv_len = args.len() + 1;

    // Compute the caller's stack size after consuming recv and args.
    // state.stack() includes recv + args, so subtract both.
    let caller_stack_size = state.stack_size() - args_with_recv_len;

    // Can't use gen_prepare_non_leaf_call() because we need to adjust the SP
    // to account for the receiver and arguments (like gen_ccall_with_frame does)
    gen_save_pc_for_gc(asm, state);
    gen_save_sp(asm, caller_stack_size);
    gen_spill_stack(jit, asm, state);
    gen_spill_locals(jit, asm, state);

    let block_handler_specval = if let Some(block_iseq) = blockiseq {
        // Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
        // VM_CFP_TO_CAPTURED_BLOCK then turns &cfp->self into a block handler.
        // rb_captured_block->code.iseq aliases with cfp->block_code.
        asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_BLOCK_CODE), VALUE::from(block_iseq).into());
        let cfp_self_addr = asm.lea(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF));
        asm.or(cfp_self_addr, Opnd::Imm(1))
    } else {
        VM_BLOCK_HANDLER_NONE.into()
    };

    gen_push_frame(asm, args_with_recv_len, state, ControlFrame {
        recv,
        iseq: None,
        cme,
        frame_type: VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL,
        specval: block_handler_specval,
        pc: PC_POISON,
    });

    asm_comment!(asm, "switch to new SP register");
    let sp_offset = (caller_stack_size + VM_ENV_DATA_SIZE.to_usize()) * SIZEOF_VALUE;
    let new_sp = asm.add(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP as i32), CFP);

    let argv_ptr = gen_push_opnds(asm, &args);
    asm.count_call_to(&name.contents_lossy());
    let result = asm.ccall(cfunc, vec![args.len().into(), argv_ptr, recv]);
    gen_pop_opnds(asm, &args);

    asm_comment!(asm, "pop C frame");
    let new_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP as i32), CFP);

    asm_comment!(asm, "restore SP register for the caller");
    let new_sp = asm.sub(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    result
}

/// Emit an uncached instance variable lookup
fn gen_getivar(jit: &mut JITState, asm: &mut Assembler, recv: Opnd, id: ID, ic: *const iseq_inline_iv_cache_entry) -> Opnd {
    if ic.is_null() {
        asm_ccall!(asm, rb_ivar_get, recv, id.0.into())
    } else {
        let iseq = Opnd::Value(jit.iseq.into());
        asm_ccall!(asm, rb_vm_getinstancevariable, iseq, recv, id.0.into(), Opnd::const_ptr(ic))
    }
}

/// Emit an uncached instance variable store
fn gen_setivar(jit: &mut JITState, asm: &mut Assembler, recv: Opnd, id: ID, ic: *const iseq_inline_iv_cache_entry, val: Opnd, state: &FrameState) {
    // Setting an ivar can raise FrozenError, so we need proper frame state for exception handling.
    gen_prepare_non_leaf_call(jit, asm, state);
    if ic.is_null() {
        asm_ccall!(asm, rb_ivar_set, recv, id.0.into(), val);
    } else {
        let iseq = Opnd::Value(jit.iseq.into());
        asm_ccall!(asm, rb_vm_setinstancevariable, iseq, recv, id.0.into(), val, Opnd::const_ptr(ic));
    }
}

fn gen_getclassvar(jit: &mut JITState, asm: &mut Assembler, id: ID, ic: *const iseq_inline_cvar_cache_entry, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_vm_getclassvariable, VALUE::from(jit.iseq).into(), CFP, id.0.into(), Opnd::const_ptr(ic))
}

fn gen_setclassvar(jit: &mut JITState, asm: &mut Assembler, id: ID, val: Opnd, ic: *const iseq_inline_cvar_cache_entry, state: &FrameState) {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_vm_setclassvariable, VALUE::from(jit.iseq).into(), CFP, id.0.into(), val, Opnd::const_ptr(ic));
}

/// Look up global variables
fn gen_getglobal(jit: &mut JITState, asm: &mut Assembler, id: ID, state: &FrameState) -> Opnd {
    // `Warning` module's method `warn` can be called when reading certain global variables
    gen_prepare_non_leaf_call(jit, asm, state);

    asm_ccall!(asm, rb_gvar_get, id.0.into())
}

/// Intern a string
fn gen_intern(asm: &mut Assembler, val: Opnd, state: &FrameState) -> Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

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

    gen_prepare_leaf_call_with_gc(asm, state);

    asm_ccall!(asm, rb_reg_nth_match, Opnd::Imm((nth >> 1).try_into().unwrap()), backref)
}

fn gen_check_interrupts(jit: &mut JITState, asm: &mut Assembler, state: &FrameState) {
    // Check for interrupts
    // see RUBY_VM_CHECK_INTS(ec) macro
    asm_comment!(asm, "RUBY_VM_CHECK_INTS(ec)");
    // Not checking interrupt_mask since it's zero outside finalize_deferred_heap_pages,
    // signal_exec, or rb_postponed_job_flush.
    let interrupt_flag = asm.load(Opnd::mem(32, EC, RUBY_OFFSET_EC_INTERRUPT_FLAG as i32));
    asm.test(interrupt_flag, interrupt_flag);
    asm.jnz(side_exit(jit, state, SideExitReason::Interrupt));
}

fn gen_hash_dup(asm: &mut Assembler, val: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_hash_resurrect, val)
}

fn gen_hash_aref(jit: &mut JITState, asm: &mut Assembler, hash: Opnd, key: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_hash_aref, hash, key)
}

fn gen_hash_aset(jit: &mut JITState, asm: &mut Assembler, hash: Opnd, key: Opnd, val: Opnd, state: &FrameState) {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_hash_aset, hash, key, val);
}

fn gen_array_push(asm: &mut Assembler, array: Opnd, val: Opnd, state: &FrameState) {
    gen_prepare_leaf_call_with_gc(asm, state);
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
    gen_incr_counter(asm, Counter::guard_shape_count);
    let shape_id_offset = unsafe { rb_shape_id_offset() };
    let val = asm.load(val);
    let shape_opnd = Opnd::mem(SHAPE_ID_NUM_BITS as u8, val, shape_id_offset);
    asm.cmp(shape_opnd, Opnd::UImm(shape.0 as u64));
    asm.jne(side_exit(jit, state, SideExitReason::GuardShape(shape)));
    val
}

fn gen_load_pc(asm: &mut Assembler) -> Opnd {
    asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC))
}

fn gen_load_ec() -> Opnd {
    EC
}

fn gen_load_self() -> Opnd {
    Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF)
}

fn gen_load_field(asm: &mut Assembler, recv: Opnd, id: ID, offset: i32) -> Opnd {
    asm_comment!(asm, "Load field id={} offset={}", id.contents_lossy(), offset);
    let recv = asm.load(recv);
    asm.load(Opnd::mem(64, recv, offset))
}

fn gen_store_field(asm: &mut Assembler, recv: Opnd, id: ID, offset: i32, val: Opnd, val_type: Type) {
    asm_comment!(asm, "Store field id={} offset={}", id.contents_lossy(), offset);
    let recv = asm.load(recv);
    asm.store(Opnd::mem(val_type.num_bits(), recv, offset), val);
}

fn gen_write_barrier(asm: &mut Assembler, recv: Opnd, val: Opnd, val_type: Type) {
    // See RB_OBJ_WRITE/rb_obj_write: it's just assignment and rb_obj_written().
    // rb_obj_written() does: if (!RB_SPECIAL_CONST_P(val)) { rb_gc_writebarrier(recv, val); }
    if !val_type.is_immediate() {
        asm_comment!(asm, "Write barrier");
        let recv = asm.load(recv);
        asm_ccall!(asm, rb_zjit_writebarrier_check_immediate, recv, val);
    }
}

/// Compile an interpreter entry block to be inserted into an ISEQ
fn gen_entry_prologue(asm: &mut Assembler) {
    asm_comment!(asm, "ZJIT entry trampoline");
    // Save the registers we'll use for CFP, EP, SP
    asm.frame_setup(lir::JIT_PRESERVED_REGS);

    // EC and CFP are passed as arguments
    asm.mov(EC, C_ARG_OPNDS[0]);
    asm.mov(CFP, C_ARG_OPNDS[1]);

    // Load the current SP from the CFP into REG_SP
    asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));
}

/// Set branch params to basic block arguments
fn gen_branch_params(jit: &mut JITState, asm: &mut Assembler, branch: &BranchEdge) {
    if branch.args.is_empty() {
        return;
    }

    asm_comment!(asm, "set branch params: {}", branch.args.len());
    asm.parallel_mov(branch.args.iter().enumerate().map(|(idx, &arg)|
        (param_opnd(idx), jit.get_opnd(arg))
    ).collect());
}

/// Compile a constant
fn gen_const_value(val: VALUE) -> lir::Opnd {
    // Just propagate the constant value and generate nothing
    Opnd::Value(val)
}

/// Compile Const::CPtr
fn gen_const_cptr(val: *const u8) -> lir::Opnd {
    Opnd::const_ptr(val)
}

fn gen_const_long(val: i64) -> lir::Opnd {
    Opnd::Imm(val)
}

fn gen_const_uint16(val: u16) -> lir::Opnd {
    Opnd::UImm(val as u64)
}

fn gen_const_uint32(val: u32) -> lir::Opnd {
    Opnd::UImm(val as u64)
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
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);

    gen_prepare_non_leaf_call(jit, asm, state);
    asm_comment!(asm, "call #{} with dynamic dispatch", ruby_call_method_name(cd));
    unsafe extern "C" {
        fn rb_vm_send(ec: EcPtr, cfp: CfpPtr, cd: VALUE, blockiseq: IseqPtr) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_send,
        EC, CFP, Opnd::const_ptr(cd), VALUE::from(blockiseq).into()
    )
}

/// Compile a dynamic dispatch with `...`
fn gen_send_forward(
    jit: &mut JITState,
    asm: &mut Assembler,
    cd: *const rb_call_data,
    blockiseq: IseqPtr,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);

    gen_prepare_non_leaf_call(jit, asm, state);

    asm_comment!(asm, "call #{} with dynamic dispatch", ruby_call_method_name(cd));
    unsafe extern "C" {
        fn rb_vm_sendforward(ec: EcPtr, cfp: CfpPtr, cd: VALUE, blockiseq: IseqPtr) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_sendforward,
        EC, CFP, Opnd::const_ptr(cd), VALUE::from(blockiseq).into()
    )
}

/// Compile a dynamic dispatch without block
fn gen_send_without_block(
    jit: &mut JITState,
    asm: &mut Assembler,
    cd: *const rb_call_data,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);

    gen_prepare_non_leaf_call(jit, asm, state);
    asm_comment!(asm, "call #{} with dynamic dispatch", ruby_call_method_name(cd));
    unsafe extern "C" {
        fn rb_vm_opt_send_without_block(ec: EcPtr, cfp: CfpPtr, cd: VALUE) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_opt_send_without_block,
        EC, CFP, Opnd::const_ptr(cd)
    )
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
    gen_incr_counter(asm, Counter::iseq_optimized_send_count);

    let local_size = unsafe { get_iseq_body_local_table_size(iseq) }.to_usize();
    let stack_growth = state.stack_size() + local_size + unsafe { get_iseq_body_stack_max(iseq) }.to_usize();
    gen_stack_overflow_check(jit, asm, state, stack_growth);

    // Save cfp->pc and cfp->sp for the caller frame
    // Can't use gen_prepare_non_leaf_call because we need special SP math.
    gen_save_pc_for_gc(asm, state);
    gen_save_sp(asm, state.stack().len() - args.len() - 1); // -1 for receiver

    gen_spill_locals(jit, asm, state);
    gen_spill_stack(jit, asm, state);

    let (frame_type, specval) = if VM_METHOD_TYPE_BMETHOD == unsafe { get_cme_def_type(cme) } {
        // Extract EP from the Proc instance
        let procv = unsafe { rb_get_def_bmethod_proc((*cme).def) };
        let proc = unsafe { rb_jit_get_proc_ptr(procv) };
        let proc_block = unsafe { &(*proc).block };
        let capture = unsafe { proc_block.as_.captured.as_ref() };
        let bmethod_frame_type = VM_FRAME_MAGIC_BLOCK | VM_FRAME_FLAG_BMETHOD | VM_FRAME_FLAG_LAMBDA;
        // Tag the captured EP like VM_GUARDED_PREV_EP() in vm_call_iseq_bmethod()
        let bmethod_specval = (capture.ep.addr() | 1).into();
        (bmethod_frame_type, bmethod_specval)
    } else {
        (VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL, VM_BLOCK_HANDLER_NONE.into())
    };

    // Set up the new frame
    // TODO: Lazily materialize caller frames on side exits or when needed
    gen_push_frame(asm, args.len(), state, ControlFrame {
        recv,
        iseq: Some(iseq),
        cme,
        frame_type,
        pc: None,
        specval,
    });

    // Write "keyword_bits" to the callee's frame if the callee accepts keywords.
    // This is a synthetic local/parameter that the callee reads via checkkeyword to determine
    // which optional keyword arguments need their defaults evaluated.
    if unsafe { rb_get_iseq_flags_has_kw(iseq) } {
        let keyword = unsafe { rb_get_iseq_body_param_keyword(iseq) };
        let bits_start = unsafe { (*keyword).bits_start } as usize;
        // Currently we only support required keywords, so all bits are 0 (all keywords specified).
        // TODO: When supporting optional keywords, calculate actual unspecified_bits here.
        let unspecified_bits = VALUE::fixnum_from_usize(0);
        let bits_offset = (state.stack().len() - args.len() + bits_start) * SIZEOF_VALUE;
        asm_comment!(asm, "write keyword bits to callee frame");
        asm.store(Opnd::mem(64, SP, bits_offset as i32), unspecified_bits.into());
    }

    asm_comment!(asm, "switch to new SP register");
    let sp_offset = (state.stack().len() + local_size - args.len() + VM_ENV_DATA_SIZE.to_usize()) * SIZEOF_VALUE;
    let new_sp = asm.add(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP as i32), CFP);

    // Set up arguments
    let mut c_args = vec![recv];
    c_args.extend(&args);

    let params = unsafe { iseq.params() };
    let num_optionals_passed = if params.flags.has_opt() != 0 {
        // See vm_call_iseq_setup_normal_opt_start in vm_inshelper.c
        let lead_num = params.lead_num as u32;
        let opt_num = params.opt_num as u32;
        let keyword = params.keyword;
        let kw_req_num = if keyword.is_null() { 0 } else { unsafe { (*keyword).required_num } } as u32;
        let req_num = lead_num + kw_req_num;
        assert!(args.len() as u32 <= req_num + opt_num);
        let num_optionals_passed = args.len() as u32 - req_num;
        num_optionals_passed
    } else {
        0
    };

    // Fill non-parameter locals with nil (they may be read by eval before being written)
    let num_params = params.size.to_usize();
    if local_size > num_params {
        asm_comment!(asm, "initialize non-parameter locals to nil");
        for local_idx in num_params..local_size {
            let offset = local_size_and_idx_to_bp_offset(local_size, local_idx);
            asm.store(Opnd::mem(64, SP, -offset * SIZEOF_VALUE_I32), Qnil.into());
        }
    }

    // Make a method call. The target address will be rewritten once compiled.
    let iseq_call = IseqCall::new(iseq, num_optionals_passed);
    let dummy_ptr = cb.get_write_ptr().raw_ptr(cb);
    jit.iseq_calls.push(iseq_call.clone());
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

/// Compile for invokeblock
fn gen_invokeblock(
    jit: &mut JITState,
    asm: &mut Assembler,
    cd: *const rb_call_data,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);

    gen_prepare_non_leaf_call(jit, asm, state);

    asm_comment!(asm, "call invokeblock");
    unsafe extern "C" {
        fn rb_vm_invokeblock(ec: EcPtr, cfp: CfpPtr, cd: VALUE) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_invokeblock,
        EC, CFP, Opnd::const_ptr(cd)
    )
}

/// Compile a dynamic dispatch for `super`
fn gen_invokesuper(
    jit: &mut JITState,
    asm: &mut Assembler,
    cd: *const rb_call_data,
    blockiseq: IseqPtr,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);

    gen_prepare_non_leaf_call(jit, asm, state);
    asm_comment!(asm, "call super with dynamic dispatch");
    unsafe extern "C" {
        fn rb_vm_invokesuper(ec: EcPtr, cfp: CfpPtr, cd: VALUE, blockiseq: IseqPtr) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_invokesuper,
        EC, CFP, Opnd::const_ptr(cd), VALUE::from(blockiseq).into()
    )
}

/// Compile a string resurrection
fn gen_string_copy(asm: &mut Assembler, recv: Opnd, chilled: bool, state: &FrameState) -> Opnd {
    // TODO: split rb_ec_str_resurrect into separate functions
    gen_prepare_leaf_call_with_gc(asm, state);
    let chilled = if chilled { Opnd::Imm(1) } else { Opnd::Imm(0) };
    asm_ccall!(asm, rb_ec_str_resurrect, EC, recv, chilled)
}

/// Compile an array duplication instruction
fn gen_array_dup(
    asm: &mut Assembler,
    val: lir::Opnd,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

    asm_ccall!(asm, rb_ary_resurrect, val)
}

/// Compile a new array instruction
fn gen_new_array(
    asm: &mut Assembler,
    elements: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

    let num: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

    if elements.is_empty() {
        asm_ccall!(asm, rb_ec_ary_new_from_values, EC, 0i64.into(), Opnd::UImm(0))
    } else {
        let argv = gen_push_opnds(asm, &elements);
        let new_array = asm_ccall!(asm, rb_ec_ary_new_from_values, EC, num.into(), argv);
        gen_pop_opnds(asm, &elements);
        new_array
    }
}

/// Compile array access (`array[index]`)
fn gen_aref_fixnum(
    asm: &mut Assembler,
    array: Opnd,
    index: Opnd,
) -> lir::Opnd {
    let unboxed_idx = asm.rshift(index, Opnd::UImm(1));
    asm_ccall!(asm, rb_ary_entry, array, unboxed_idx)
}

fn gen_array_pop(asm: &mut Assembler, array: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_ary_pop, array)
}

fn gen_array_length(asm: &mut Assembler, array: Opnd) -> lir::Opnd {
    let array = asm.load(array);
    let flags = Opnd::mem(VALUE_BITS, array, RUBY_OFFSET_RBASIC_FLAGS);
    let embedded_len = asm.and(flags, (RARRAY_EMBED_LEN_MASK as u64).into());
    let embedded_len = asm.rshift(embedded_len, (RARRAY_EMBED_LEN_SHIFT as u64).into());
    // cmov between the embedded length and heap length depending on the embed flag
    asm.test(flags, (RARRAY_EMBED_FLAG as u64).into());
    let heap_len = Opnd::mem(c_long::BITS as u8, array, RUBY_OFFSET_RARRAY_AS_HEAP_LEN);
    asm.csel_nz(embedded_len, heap_len)
}

/// Compile opt_newarray_hash - create a hash from array elements
fn gen_opt_newarray_hash(
    jit: &JITState,
    asm: &mut Assembler,
    elements: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    // `Array#hash` will hash the elements of the array.
    gen_prepare_non_leaf_call(jit, asm, state);

    let array_len: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

    // After gen_prepare_non_leaf_call, the elements are spilled to the Ruby stack.
    // Get a pointer to the first element on the Ruby stack.
    let stack_bottom = state.stack().len() - elements.len();
    let elements_ptr = asm.lea(Opnd::mem(64, SP, stack_bottom as i32 * SIZEOF_VALUE_I32));

    unsafe extern "C" {
        fn rb_vm_opt_newarray_hash(ec: EcPtr, array_len: u32, elts: *const VALUE) -> VALUE;
    }

    asm.ccall(
        rb_vm_opt_newarray_hash as *const u8,
        vec![EC, (array_len as u32).into(), elements_ptr],
    )
}

fn gen_array_include(
    jit: &JITState,
    asm: &mut Assembler,
    elements: Vec<Opnd>,
    target: Opnd,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let array_len: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

    // After gen_prepare_non_leaf_call, the elements are spilled to the Ruby stack.
    // The elements are at the bottom of the virtual stack, followed by the target.
    // Get a pointer to the first element on the Ruby stack.
    let stack_bottom = state.stack().len() - elements.len() - 1;
    let elements_ptr = asm.lea(Opnd::mem(64, SP, stack_bottom as i32 * SIZEOF_VALUE_I32));

    unsafe extern "C" {
        fn rb_vm_opt_newarray_include_p(ec: EcPtr, num: c_long, elts: *const VALUE, target: VALUE) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_opt_newarray_include_p,
        EC, array_len.into(), elements_ptr, target
    )
}

fn gen_array_pack_buffer(
    jit: &JITState,
    asm: &mut Assembler,
    elements: Vec<Opnd>,
    fmt: Opnd,
    buffer: Opnd,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let array_len: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

    // After gen_prepare_non_leaf_call, the elements are spilled to the Ruby stack.
    // The elements are at the bottom of the virtual stack, followed by the fmt, followed by the buffer.
    // Get a pointer to the first element on the Ruby stack.
    let stack_bottom = state.stack().len() - elements.len() - 2;
    let elements_ptr = asm.lea(Opnd::mem(64, SP, stack_bottom as i32 * SIZEOF_VALUE_I32));

    unsafe extern "C" {
        fn rb_vm_opt_newarray_pack_buffer(ec: EcPtr, num: c_long, elts: *const VALUE, fmt: VALUE, buffer: VALUE) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_opt_newarray_pack_buffer,
        EC, array_len.into(), elements_ptr, fmt, buffer
    )
}

fn gen_dup_array_include(
    jit: &JITState,
    asm: &mut Assembler,
    ary: VALUE,
    target: Opnd,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    unsafe extern "C" {
        fn rb_vm_opt_duparray_include_p(ec: EcPtr, ary: VALUE, target: VALUE) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_opt_duparray_include_p,
        EC, ary.into(), target
    )
}

fn gen_is_a(asm: &mut Assembler, obj: Opnd, class: Opnd) -> lir::Opnd {
    asm_ccall!(asm, rb_obj_is_kind_of, obj, class)
}

/// Compile a new hash instruction
fn gen_new_hash(
    jit: &mut JITState,
    asm: &mut Assembler,
    elements: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let cap: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");
    let new_hash = asm_ccall!(asm, rb_hash_new_with_size, lir::Opnd::Imm(cap));

    if !elements.is_empty() {
        let argv = gen_push_opnds(asm, &elements);
        asm_ccall!(asm, rb_hash_bulk_insert, elements.len().into(), argv, new_hash);

        gen_pop_opnds(asm, &elements);
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
    asm_ccall!(asm, rb_range_new, low, high, (flag as i32).into())
}

fn gen_new_range_fixnum(
    asm: &mut Assembler,
    low: lir::Opnd,
    high: lir::Opnd,
    flag: RangeType,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_range_new, low, high, (flag as i64).into())
}

fn gen_object_alloc(jit: &JITState, asm: &mut Assembler, val: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Allocating an object from an unknown class is non-leaf; see doc for `ObjectAlloc`.
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_obj_alloc, val)
}

fn gen_object_alloc_class(asm: &mut Assembler, class: VALUE, state: &FrameState) -> lir::Opnd {
    // Allocating an object for a known class with default allocator is leaf; see doc for
    // `ObjectAllocClass`.
    gen_prepare_leaf_call_with_gc(asm, state);
    if unsafe { rb_zjit_class_has_default_allocator(class) } {
        // TODO(max): inline code to allocate an instance
        asm_ccall!(asm, rb_class_allocate_instance, class.into())
    } else {
        assert!(class_has_leaf_allocator(class), "class passed to ObjectAllocClass must have a leaf allocator");
        let alloc_func = unsafe { rb_zjit_class_get_alloc_func(class) };
        assert!(alloc_func.is_some(), "class {} passed to ObjectAllocClass must have an allocator", get_class_name(class));
        asm_comment!(asm, "call allocator for class {}", get_class_name(class));
        asm.count_call_to(&format!("{}::allocator", get_class_name(class)));
        asm.ccall(alloc_func.unwrap() as *const u8, vec![class.into()])
    }
}

/// Compile a frame setup. If jit_entry_idx is Some, remember the address of it as a JIT entry.
fn gen_entry_point(jit: &mut JITState, asm: &mut Assembler, jit_entry_idx: Option<usize>) {
    if let Some(jit_entry_idx) = jit_entry_idx {
        let jit_entry = JITEntry::new(jit_entry_idx);
        jit.jit_entries.push(jit_entry.clone());
        asm.pos_marker(move |code_ptr, _| {
            jit_entry.borrow_mut().start_addr.set(Some(code_ptr));
        });
    }
    asm.frame_setup(&[]);
}

/// Compile code that exits from JIT code with a return value
fn gen_return(asm: &mut Assembler, val: lir::Opnd) {
    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    asm_comment!(asm, "pop stack frame");
    let incr_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, incr_cfp);
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP as i32), CFP);

    // Order here is important. Because we're about to tear down the frame,
    // we need to load the return value, which might be part of the frame.
    asm.load_into(C_RET_OPND, val);

    // Return from the function
    asm.frame_teardown(&[]); // matching the setup in gen_entry_point()
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

/// Compile Fixnum / Fixnum
fn gen_fixnum_div(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

    // Side exit if rhs is 0
    asm.cmp(right, Opnd::from(VALUE::fixnum_from_usize(0)));
    asm.je(side_exit(jit, state, FixnumDivByZero));
    asm_ccall!(asm, rb_jit_fix_div_fix, left, right)
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

/// Compile Fixnum ^ Fixnum
fn gen_fixnum_xor(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    // XOR and then re-tag the resulting fixnum
    let out_val = asm.xor(left, right);
    asm.add(out_val, Opnd::UImm(1))
}

/// Compile Fixnum << Fixnum
fn gen_fixnum_lshift(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, shift_amount: u64, state: &FrameState) -> lir::Opnd {
    // Shift amount is known statically to be in the range [0, 63]
    assert!(shift_amount < 64);
    let in_val = asm.sub(left, Opnd::UImm(1));  // Drop tag bit
    let out_val = asm.lshift(in_val, shift_amount.into());
    let unshifted = asm.rshift(out_val, shift_amount.into());
    asm.cmp(in_val, unshifted);
    asm.jne(side_exit(jit, state, FixnumLShiftOverflow));
    // Re-tag the output value
    let out_val = asm.add(out_val, 1.into());
    out_val
}

/// Compile Fixnum >> Fixnum
fn gen_fixnum_rshift(asm: &mut Assembler, left: lir::Opnd, shift_amount: u64) -> lir::Opnd {
    // Shift amount is known statically to be in the range [0, 63]
    assert!(shift_amount < 64);
    let result = asm.rshift(left, shift_amount.into());
    // Re-tag the output value
    asm.or(result, 1.into())
}

fn gen_fixnum_mod(jit: &mut JITState, asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Check for left % 0, which raises ZeroDivisionError
    asm.cmp(right, Opnd::from(VALUE::fixnum_from_usize(0)));
    asm.je(side_exit(jit, state, FixnumModByZero));
    asm_ccall!(asm, rb_fix_mod_fix, left, right)
}

// Compile val == nil
fn gen_isnil(asm: &mut Assembler, val: lir::Opnd) -> lir::Opnd {
    asm.cmp(val, Qnil.into());
    // TODO: Implement and use setcc
    asm.csel_e(Opnd::Imm(1), Opnd::Imm(0))
}

fn gen_is_method_cfunc(jit: &JITState, asm: &mut Assembler, val: lir::Opnd, cd: *const rb_call_data, cfunc: *const u8) -> lir::Opnd {
    unsafe extern "C" {
        fn rb_vm_method_cfunc_is(iseq: IseqPtr, cd: *const rb_call_data, recv: VALUE, cfunc: *const u8) -> VALUE;
    }
    asm_ccall!(asm, rb_vm_method_cfunc_is, VALUE::from(jit.iseq).into(), Opnd::const_ptr(cd), val, Opnd::const_ptr(cfunc))
}

fn gen_is_bit_equal(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.cmp(left, right);
    asm.csel_e(Opnd::Imm(1), Opnd::Imm(0))
}

fn gen_is_bit_not_equal(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.cmp(left, right);
    asm.csel_ne(Opnd::Imm(1), Opnd::Imm(0))
}

fn gen_box_bool(asm: &mut Assembler, val: lir::Opnd) -> lir::Opnd {
    asm.test(val, val);
    asm.csel_nz(Opnd::Value(Qtrue), Opnd::Value(Qfalse))
}

fn gen_box_fixnum(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Load the value, then test for overflow and tag it
    let val = asm.load(val);
    let shifted = asm.lshift(val, Opnd::UImm(1));
    asm.jo(side_exit(jit, state, BoxFixnumOverflow));
    asm.or(shifted, Opnd::UImm(RUBY_FIXNUM_FLAG as u64))
}

fn gen_anytostring(asm: &mut Assembler, val: lir::Opnd, str: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

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
    gen_incr_counter(asm, Counter::guard_type_count);
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
    } else if guard_type.is_subtype(types::String) {
        let side = side_exit(jit, state, GuardType(guard_type));

        // Check special constant
        asm.test(val, Opnd::UImm(RUBY_IMMEDIATE_MASK as u64));
        asm.jnz(side.clone());

        // Check false
        asm.cmp(val, Qfalse.into());
        asm.je(side.clone());

        let val = match val {
            Opnd::Reg(_) | Opnd::VReg { .. } => val,
            _ => asm.load(val),
        };

        let flags = asm.load(Opnd::mem(VALUE_BITS, val, RUBY_OFFSET_RBASIC_FLAGS));
        let tag   = asm.and(flags, Opnd::UImm(RUBY_T_MASK as u64));
        asm.cmp(tag, Opnd::UImm(RUBY_T_STRING as u64));
        asm.jne(side);
    } else if guard_type.bit_equal(types::HeapBasicObject) {
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

fn gen_guard_type_not(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, guard_type: Type, state: &FrameState) -> lir::Opnd {
    if guard_type.is_subtype(types::String) {
        // We only exit if val *is* a String. Otherwise we fall through.
        let cont = asm.new_label("guard_type_not_string_cont");
        let side = side_exit(jit, state, GuardTypeNot(guard_type));

        // Continue if special constant (not string)
        asm.test(val, Opnd::UImm(RUBY_IMMEDIATE_MASK as u64));
        asm.jnz(cont.clone());

        // Continue if false (not string)
        asm.cmp(val, Qfalse.into());
        asm.je(cont.clone());

        let val = match val {
            Opnd::Reg(_) | Opnd::VReg { .. } => val,
            _ => asm.load(val),
        };

        let flags = asm.load(Opnd::mem(VALUE_BITS, val, RUBY_OFFSET_RBASIC_FLAGS));
        let tag   = asm.and(flags, Opnd::UImm(RUBY_T_MASK as u64));
        asm.cmp(tag, Opnd::UImm(RUBY_T_STRING as u64));
        asm.je(side);

        // Otherwise (non-string heap object), continue.
        asm.write_label(cont);
    } else {
        unimplemented!("unsupported type: {guard_type}");
    }
    val
}

/// Compile an identity check with a side exit
fn gen_guard_bit_equals(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, expected: crate::hir::Const, state: &FrameState) -> lir::Opnd {
    let expected_opnd: Opnd = match expected {
        crate::hir::Const::Value(v) => { Opnd::Value(v) }
        crate::hir::Const::CInt64(v) => { v.into() }
        _ => panic!("gen_guard_bit_equals: unexpected hir::Const {expected:?}"),
    };
    asm.cmp(val, expected_opnd);
    asm.jnz(side_exit(jit, state, GuardBitEquals(expected)));
    val
}

/// Generate code that records unoptimized C functions if --zjit-stats is enabled
fn gen_incr_counter_ptr(asm: &mut Assembler, counter_ptr: *mut u64) {
    if get_option!(stats) {
        asm.incr_counter(Opnd::const_ptr(counter_ptr as *const u8), Opnd::UImm(1));
    }
}

/// Generate code that increments a counter if --zjit-stats
fn gen_incr_counter(asm: &mut Assembler, counter: Counter) {
    if get_option!(stats) {
        let ptr = counter_ptr(counter);
        gen_incr_counter_ptr(asm, ptr);
    }
}

/// Increment a counter for each DynamicSendReason. If the variant has
/// a counter prefix to break down the details, increment that as well.
fn gen_incr_send_fallback_counter(asm: &mut Assembler, reason: SendFallbackReason) {
    gen_incr_counter(asm, send_fallback_counter(reason));

    use SendFallbackReason::*;
    match reason {
        Uncategorized(opcode) => {
            gen_incr_counter_ptr(asm, send_fallback_counter_ptr_for_opcode(opcode));
        }
        SendWithoutBlockNotOptimizedMethodType(method_type) => {
            gen_incr_counter(asm, send_without_block_fallback_counter_for_method_type(method_type));
        }
        SendWithoutBlockNotOptimizedMethodTypeOptimized(method_type) => {
            gen_incr_counter(asm, send_without_block_fallback_counter_for_optimized_method_type(method_type));
        }
        SendNotOptimizedMethodType(method_type) => {
            gen_incr_counter(asm, send_fallback_counter_for_method_type(method_type));
        }
        _ => {}
    }
}

/// Save only the PC to CFP. Use this when you need to call gen_save_sp()
/// immediately after with a custom stack size (e.g., gen_ccall_with_frame
/// adjusts SP to exclude receiver and arguments).
fn gen_save_pc_for_gc(asm: &mut Assembler, state: &FrameState) {
    let opcode: usize = state.get_opcode().try_into().unwrap();
    let next_pc: *const VALUE = unsafe { state.pc.offset(insn_len(opcode) as isize) };

    gen_incr_counter(asm, Counter::vm_write_pc_count);
    asm_comment!(asm, "save PC to CFP");
    asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), Opnd::const_ptr(next_pc));
}

/// Save the current PC on the CFP as a preparation for calling a C function
/// that may allocate objects and trigger GC. Use gen_prepare_non_leaf_call()
/// if it may raise exceptions or call arbitrary methods.
///
/// Unlike YJIT, we don't need to save the stack slots to protect them from GC
/// because the backend spills all live registers onto the C stack on CCall.
/// However, to avoid marking uninitialized stack slots, this also updates SP,
/// which may have cfp->sp for a past frame or a past non-leaf call.
fn gen_prepare_call_with_gc(asm: &mut Assembler, state: &FrameState, leaf: bool) {
    gen_save_pc_for_gc(asm, state);
    gen_save_sp(asm, state.stack_size());
    if leaf {
        asm.expect_leaf_ccall(state.stack_size());
    }
}

fn gen_prepare_leaf_call_with_gc(asm: &mut Assembler, state: &FrameState) {
    // In gen_prepare_call_with_gc(), we update cfp->sp for leaf calls too.
    //
    // Here, cfp->sp may be pointing to either of the following:
    //   1. cfp->sp for a past frame, which gen_push_frame() skips to initialize
    //   2. cfp->sp set by gen_prepare_non_leaf_call() for the current frame
    //
    // When (1), to avoid marking dead objects, we need to set cfp->sp for the current frame.
    // When (2), setting cfp->sp at gen_push_frame() and not updating cfp->sp here could lead to
    // keeping objects longer than it should, so we set cfp->sp at every call of this function.
    //
    // We use state.without_stack() to pass stack_size=0 to gen_save_sp() because we don't write
    // VM stack slots on leaf calls, which leaves those stack slots uninitialized. ZJIT keeps
    // live objects on the C stack, so they are protected from GC properly.
    gen_prepare_call_with_gc(asm, &state.without_stack(), true);
}

/// Save the current SP on the CFP
fn gen_save_sp(asm: &mut Assembler, stack_size: usize) {
    // Update cfp->sp which will be read by the interpreter. We also have the SP register in JIT
    // code, and ZJIT's codegen currently assumes the SP register doesn't move, e.g. gen_param().
    // So we don't update the SP register here. We could update the SP register to avoid using
    // an extra register for asm.lea(), but you'll need to manage the SP offset like YJIT does.
    gen_incr_counter(asm, Counter::vm_write_sp_count);
    asm_comment!(asm, "save SP to CFP: {}", stack_size);
    let sp_addr = asm.lea(Opnd::mem(64, SP, stack_size as i32 * SIZEOF_VALUE_I32));
    let cfp_sp = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP);
    asm.mov(cfp_sp, sp_addr);
}

/// Spill locals onto the stack.
fn gen_spill_locals(jit: &JITState, asm: &mut Assembler, state: &FrameState) {
    // TODO: Avoid spilling locals that have been spilled before and not changed.
    gen_incr_counter(asm, Counter::vm_write_locals_count);
    asm_comment!(asm, "spill locals");
    for (idx, &insn_id) in state.locals().enumerate() {
        asm.mov(Opnd::mem(64, SP, (-local_idx_to_ep_offset(jit.iseq, idx) - 1) * SIZEOF_VALUE_I32), jit.get_opnd(insn_id));
    }
}

/// Spill the virtual stack onto the stack.
fn gen_spill_stack(jit: &JITState, asm: &mut Assembler, state: &FrameState) {
    // This function does not call gen_save_sp() at the moment because
    // gen_send_without_block_direct() spills stack slots above SP for arguments.
    gen_incr_counter(asm, Counter::vm_write_stack_count);
    asm_comment!(asm, "spill stack");
    for (idx, &insn_id) in state.stack().enumerate() {
        asm.mov(Opnd::mem(64, SP, idx as i32 * SIZEOF_VALUE_I32), jit.get_opnd(insn_id));
    }
}

/// Prepare for calling a C function that may call an arbitrary method.
/// Use gen_prepare_leaf_call_with_gc() if the method is leaf but allocates objects.
fn gen_prepare_non_leaf_call(jit: &JITState, asm: &mut Assembler, state: &FrameState) {
    // TODO: Lazily materialize caller frames when needed
    // Save PC for backtraces and allocation tracing
    // and SP to avoid marking uninitialized stack slots
    gen_prepare_call_with_gc(asm, state, false);

    // Spill the virtual stack in case it raises an exception
    // and the interpreter uses the stack for handling the exception
    gen_spill_stack(jit, asm, state);

    // Spill locals in case the method looks at caller Bindings
    gen_spill_locals(jit, asm, state);
}

/// Frame metadata written by gen_push_frame()
struct ControlFrame {
    recv: Opnd,
    iseq: Option<IseqPtr>,
    cme: *const rb_callable_method_entry_t,
    frame_type: u32,
    /// The [`VM_ENV_DATA_INDEX_SPECVAL`] slot of the frame.
    /// For the type of frames we push, block handler or the parent EP.
    specval: lir::Opnd,
    pc: Option<*const VALUE>,
}

/// Compile an interpreter frame
fn gen_push_frame(asm: &mut Assembler, argc: usize, state: &FrameState, frame: ControlFrame) {
    // Locals are written by the callee frame on side-exits or non-leaf calls

    // See vm_push_frame() for details
    asm_comment!(asm, "push cme, specval, frame type");
    // ep[-2]: cref of cme
    let local_size = if let Some(iseq) = frame.iseq {
        (unsafe { get_iseq_body_local_table_size(iseq) }) as i32
    } else {
        0
    };
    let ep_offset = state.stack().len() as i32 + local_size - argc as i32 + VM_ENV_DATA_SIZE as i32 - 1;
    // ep[-2]: CME
    asm.store(Opnd::mem(64, SP, (ep_offset - 2) * SIZEOF_VALUE_I32), VALUE::from(frame.cme).into());
    // ep[-1]: specval
    asm.store(Opnd::mem(64, SP, (ep_offset - 1) * SIZEOF_VALUE_I32), frame.specval);
    // ep[0]: ENV_FLAGS
    asm.store(Opnd::mem(64, SP, ep_offset * SIZEOF_VALUE_I32), frame.frame_type.into());

    // Write to the callee CFP
    fn cfp_opnd(offset: i32) -> Opnd {
        Opnd::mem(64, CFP, offset - (RUBY_SIZEOF_CONTROL_FRAME as i32))
    }

    asm_comment!(asm, "push callee control frame");

    if let Some(iseq) = frame.iseq {
        // cfp_opnd(RUBY_OFFSET_CFP_PC): written by the callee frame on side-exits, non-leaf calls, or calls with GC
        // cfp_opnd(RUBY_OFFSET_CFP_SP): written by the callee frame on side-exits, non-leaf calls, or calls with GC
        asm.mov(cfp_opnd(RUBY_OFFSET_CFP_ISEQ), VALUE::from(iseq).into());
    } else {
        // C frames don't have a PC and ISEQ in normal operation.
        // When runtime checks are enabled we poison the PC so accidental reads stand out.
        if let Some(pc) = frame.pc {
            asm.mov(cfp_opnd(RUBY_OFFSET_CFP_PC), Opnd::const_ptr(pc));
        }
        let new_sp = asm.lea(Opnd::mem(64, SP, (ep_offset + 1) * SIZEOF_VALUE_I32));
        asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SP), new_sp);
        asm.mov(cfp_opnd(RUBY_OFFSET_CFP_ISEQ), 0.into());
    }

    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SELF), frame.recv);
    let ep = asm.lea(Opnd::mem(64, SP, ep_offset * SIZEOF_VALUE_I32));
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_EP), ep);
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_BLOCK_CODE), 0.into());
}

/// Stack overflow check: fails if CFP<=SP at any point in the callee.
fn gen_stack_overflow_check(jit: &mut JITState, asm: &mut Assembler, state: &FrameState, stack_growth: usize) {
    asm_comment!(asm, "stack overflow check");
    // vm_push_frame() checks it against a decremented cfp, and CHECK_VM_STACK_OVERFLOW0
    // adds to the margin another control frame with `&bounds[1]`.
    const { assert!(RUBY_SIZEOF_CONTROL_FRAME % SIZEOF_VALUE == 0, "sizeof(rb_control_frame_t) is a multiple of sizeof(VALUE)"); }
    let cfp_growth = 2 * (RUBY_SIZEOF_CONTROL_FRAME / SIZEOF_VALUE);
    let peak_offset = (cfp_growth + stack_growth) * SIZEOF_VALUE;
    let stack_limit = asm.lea(Opnd::mem(64, SP, peak_offset as i32));
    asm.cmp(CFP, stack_limit);
    asm.jbe(side_exit(jit, state, StackOverflow));
}

/// Return an operand we use for the basic block argument at a given index
fn param_opnd(idx: usize) -> Opnd {
    // To simplify the implementation, allocate a fixed register or a stack slot for each basic block argument for now.
    // Note that this is implemented here as opposed to automatically inside LIR machineries.
    // TODO: Allow allocating arbitrary registers for basic block arguments
    if idx < ALLOC_REGS.len() {
        Opnd::Reg(ALLOC_REGS[idx])
    } else {
        // With FrameSetup, the address that NATIVE_BASE_PTR points to stores an old value in the register.
        // To avoid clobbering it, we need to start from the next slot, hence `+ 1` for the index.
        Opnd::mem(64, NATIVE_BASE_PTR, (idx - ALLOC_REGS.len() + 1) as i32 * -SIZEOF_VALUE_I32)
    }
}

/// Inverse of ep_offset_to_local_idx(). See ep_offset_to_local_idx() for details.
pub fn local_idx_to_ep_offset(iseq: IseqPtr, local_idx: usize) -> i32 {
    let local_size = unsafe { get_iseq_body_local_table_size(iseq) };
    local_size_and_idx_to_ep_offset(local_size.to_usize(), local_idx)
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
            debug!("ZJIT: iseq_to_hir: {err:?}: {}", iseq_get_location(iseq, 0));
            return Err(CompileError::ParseError(err));
        }
    };
    if !get_option!(disable_hir_opt) {
        function.optimize();
    }
    function.dump_hir();
    Ok(function)
}

/// Build a Target::SideExit
fn side_exit(jit: &JITState, state: &FrameState, reason: SideExitReason) -> Target {
    let exit = build_side_exit(jit, state);
    Target::SideExit { exit, reason }
}

/// Build a side-exit context
fn build_side_exit(jit: &JITState, state: &FrameState) -> SideExit {
    let mut stack = Vec::new();
    for &insn_id in state.stack() {
        stack.push(jit.get_opnd(insn_id));
    }

    let mut locals = Vec::new();
    for &insn_id in state.locals() {
        locals.push(jit.get_opnd(insn_id));
    }

    SideExit{
        pc: Opnd::const_ptr(state.pc),
        stack,
        locals,
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
#[cfg(test)]
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
            let iseq_call = unsafe { Rc::from_raw(iseq_call_ptr as *const IseqCall) };
            let iseq = iseq_call.iseq.get();
            let entry_insn_idxs = crate::hir::jit_entry_insns(iseq);
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, entry_insn_idxs[iseq_call.jit_entry_idx.to_usize()]) };
            unsafe { rb_set_cfp_pc(cfp, pc) };

            // Successful JIT-to-JIT calls fill nils to non-parameter locals in generated code.
            // If we side-exit from function_stub_hit (before JIT code runs), we need to set them here.
            fn prepare_for_exit(iseq: IseqPtr, cfp: CfpPtr, sp: *mut VALUE, compile_error: &CompileError) {
                unsafe {
                    // Set SP which gen_push_frame() doesn't set
                    rb_set_cfp_sp(cfp, sp);

                    // Fill nils to uninitialized (non-argument) locals
                    let local_size = get_iseq_body_local_table_size(iseq).to_usize();
                    let num_params = iseq.params().size.to_usize();
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
            let last_status = payload.versions.last().map(|version| &unsafe { version.as_ref() }.status);
            let compile_error = match last_status {
                Some(IseqStatus::CantCompile(err)) => Some(err),
                _ if cb.has_dropped_bytes() => Some(&CompileError::OutOfMemory),
                _ => None,
            };
            if let Some(compile_error) = compile_error {
                // We'll use this Rc again, so increment the ref count decremented by from_raw.
                unsafe { Rc::increment_strong_count(iseq_call_ptr as *const IseqCall); }

                prepare_for_exit(iseq, cfp, sp, compile_error);
                return ZJITState::get_exit_trampoline_with_counter().raw_ptr(cb);
            }

            // Otherwise, attempt to compile the ISEQ. We have to mark_all_executable() beyond this point.
            let code_ptr = with_time_stat(compile_time_ns, || function_stub_hit_body(cb, &iseq_call));
            if code_ptr.is_ok() {
                if let Some(version) = payload.versions.last_mut() {
                    unsafe { version.as_mut() }.incoming.push(iseq_call);
                }
            }
            let code_ptr = code_ptr.unwrap_or_else(|compile_error| {
                // We'll use this Rc again, so increment the ref count decremented by from_raw.
                unsafe { Rc::increment_strong_count(iseq_call_ptr as *const IseqCall); }

                prepare_for_exit(iseq, cfp, sp, &compile_error);
                ZJITState::get_exit_trampoline_with_counter()
            });
            cb.mark_all_executable();
            code_ptr.raw_ptr(cb)
        })
    }
}

/// Compile an ISEQ for a function stub
fn function_stub_hit_body(cb: &mut CodeBlock, iseq_call: &IseqCallRef) -> Result<CodePtr, CompileError> {
    // Compile the stubbed ISEQ
    let IseqCodePtrs { jit_entry_ptrs, .. } = gen_iseq(cb, iseq_call.iseq.get(), None).inspect_err(|err| {
        debug!("{err:?}: gen_iseq failed: {}", iseq_get_location(iseq_call.iseq.get(), 0));
    })?;

    // Update the stub to call the code pointer
    let jit_entry_ptr = jit_entry_ptrs[iseq_call.jit_entry_idx.to_usize()];
    let code_addr = jit_entry_ptr.raw_ptr(cb);
    let iseq = iseq_call.iseq.get();
    iseq_call.regenerate(cb, |asm| {
        asm_comment!(asm, "call compiled function: {}", iseq_get_location(iseq, 0));
        asm.ccall(code_addr, vec![]);
    });

    Ok(jit_entry_ptr)
}

/// Compile a stub for an ISEQ called by SendWithoutBlockDirect
fn gen_function_stub(cb: &mut CodeBlock, iseq_call: IseqCallRef) -> Result<CodePtr, CompileError> {
    let (mut asm, scratch_reg) = Assembler::new_with_scratch_reg();
    asm_comment!(asm, "Stub: {}", iseq_get_location(iseq_call.iseq.get(), 0));

    // Call function_stub_hit using the shared trampoline. See `gen_function_stub_hit_trampoline`.
    // Use load_into instead of mov, which is split on arm64, to avoid clobbering ALLOC_REGS.
    asm.load_into(scratch_reg, Opnd::const_ptr(Rc::into_raw(iseq_call)));
    asm.jmp(ZJITState::get_function_stub_hit_trampoline().into());

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        code_ptr
    })
}

/// Generate a trampoline that is used when a function stub is called.
/// See [gen_function_stub] for how it's used.
pub fn gen_function_stub_hit_trampoline(cb: &mut CodeBlock) -> Result<CodePtr, CompileError> {
    let (mut asm, scratch_reg) = Assembler::new_with_scratch_reg();
    asm_comment!(asm, "function_stub_hit trampoline");

    // Maintain alignment for x86_64, and set up a frame for arm64 properly
    asm.frame_setup(&[]);

    asm_comment!(asm, "preserve argument registers");
    for &reg in ALLOC_REGS.iter() {
        asm.cpush(Opnd::Reg(reg));
    }
    if cfg!(target_arch = "x86_64") && ALLOC_REGS.len() % 2 == 1 {
        asm.cpush(Opnd::Reg(ALLOC_REGS[0])); // maintain alignment for x86_64
    }

    // Compile the stubbed ISEQ
    let jump_addr = asm_ccall!(asm, function_stub_hit, scratch_reg, CFP, SP);
    asm.mov(scratch_reg, jump_addr);

    asm_comment!(asm, "restore argument registers");
    if cfg!(target_arch = "x86_64") && ALLOC_REGS.len() % 2 == 1 {
        asm.cpop_into(Opnd::Reg(ALLOC_REGS[0]));
    }
    for &reg in ALLOC_REGS.iter().rev() {
        asm.cpop_into(Opnd::Reg(reg));
    }

    // Discard the current frame since the JIT function will set it up again
    asm.frame_teardown(&[]);

    // Jump to scratch_reg so that cpop_into() doesn't clobber it
    asm.jmp_opnd(scratch_reg);

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        code_ptr
    })
}

/// Generate a trampoline that is used when a function exits without restoring PC and the stack
pub fn gen_exit_trampoline(cb: &mut CodeBlock) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();

    asm_comment!(asm, "side-exit trampoline");
    asm.frame_teardown(&[]); // matching the setup in gen_entry_point()
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

fn gen_push_opnds(asm: &mut Assembler, opnds: &[Opnd]) -> lir::Opnd {
    let n = opnds.len();
    let allocation_size = aligned_stack_bytes(n);

    // Bump the stack pointer to reserve the space for opnds
    if n != 0 {
        asm_comment!(asm, "allocate {} bytes on C stack for {} values", allocation_size, n);
        asm.sub_into(NATIVE_STACK_PTR, allocation_size.into());
    } else {
        asm_comment!(asm, "no opnds to allocate");
    }

    // Load NATIVE_STACK_PTR to get the address of a returned array
    // to allow the backend to move it for its own use.
    let argv = asm.load(NATIVE_STACK_PTR);
    for (idx, &opnd) in opnds.iter().enumerate() {
        asm.mov(Opnd::mem(VALUE_BITS, argv, idx as i32 * SIZEOF_VALUE_I32), opnd);
    }

    argv
}

fn gen_pop_opnds(asm: &mut Assembler, opnds: &[Opnd]) {
    if opnds.is_empty() {
        asm_comment!(asm, "no opnds to restore");
        return
    }

    asm_comment!(asm, "restore C stack pointer");
    let allocation_size = aligned_stack_bytes(opnds.len());
    asm.add_into(NATIVE_STACK_PTR, allocation_size.into());
}

fn gen_toregexp(jit: &mut JITState, asm: &mut Assembler, opt: usize, values: Vec<Opnd>, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let first_opnd_ptr = gen_push_opnds(asm, &values);

    let tmp_ary = asm_ccall!(asm, rb_ary_tmp_new_from_values, Opnd::Imm(0), values.len().into(), first_opnd_ptr);
    let result = asm_ccall!(asm, rb_reg_new_ary, tmp_ary, opt.into());
    asm_ccall!(asm, rb_ary_clear, tmp_ary);

    gen_pop_opnds(asm, &values);

    result
}

fn gen_string_concat(jit: &mut JITState, asm: &mut Assembler, strings: Vec<Opnd>, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);

    let first_string_ptr = gen_push_opnds(asm, &strings);
    let result = asm_ccall!(asm, rb_str_concat_literals, strings.len().into(), first_string_ptr);
    gen_pop_opnds(asm, &strings);

    result
}

// Generate RSTRING_PTR
fn get_string_ptr(asm: &mut Assembler, string: Opnd) -> Opnd {
    asm_comment!(asm, "get string pointer for embedded or heap");
    let string = asm.load(string);
    let flags = Opnd::mem(VALUE_BITS, string, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags, (RSTRING_NOEMBED as u64).into());
    let heap_ptr = asm.load(Opnd::mem(
        usize::BITS as u8,
        string,
        RUBY_OFFSET_RSTRING_AS_HEAP_PTR,
    ));
    // Load the address of the embedded array
    // (struct RString *)(obj)->as.ary
    let ary = asm.lea(Opnd::mem(VALUE_BITS, string, RUBY_OFFSET_RSTRING_AS_ARY));
    asm.csel_nz(heap_ptr, ary)
}

fn gen_string_getbyte(asm: &mut Assembler, string: Opnd, index: Opnd) -> Opnd {
    let string_ptr = get_string_ptr(asm, string);
    // TODO(max): Use SIB indexing here once the backend supports it
    let string_ptr = asm.add(string_ptr, index);
    let byte = asm.load(Opnd::mem(8, string_ptr, 0));
    // Zero-extend the byte to 64 bits
    let byte = byte.with_num_bits(64);
    let byte = asm.and(byte, 0xFF.into());
    // Tag the byte
    let byte = asm.lshift(byte, Opnd::UImm(1));
    asm.or(byte, Opnd::UImm(1))
}

fn gen_string_setbyte_fixnum(asm: &mut Assembler, string: Opnd, index: Opnd, value: Opnd) -> Opnd {
    // rb_str_setbyte is not leaf, but we guard types and index ranges in HIR
    asm_ccall!(asm, rb_str_setbyte, string, index, value)
}

fn gen_string_append(jit: &mut JITState, asm: &mut Assembler, string: Opnd, val: Opnd, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_str_buf_append, string, val)
}

fn gen_string_append_codepoint(jit: &mut JITState, asm: &mut Assembler, string: Opnd, val: Opnd, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, state);
    asm_ccall!(asm, rb_jit_str_concat_codepoint, string, val)
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
    fn ccall_with_iseq_call(&mut self, fptr: *const u8, opnds: Vec<Opnd>, iseq_call: &IseqCallRef) -> Opnd {
        // We need to create our own branch rc objects so that we can move the closure below
        let start_iseq_call = iseq_call.clone();
        let end_iseq_call = iseq_call.clone();

        self.ccall_with_pos_markers(
            fptr,
            opnds,
            move |code_ptr, _| {
                start_iseq_call.start_addr.set(Some(code_ptr));
            },
            move |code_ptr, _| {
                end_iseq_call.end_addr.set(Some(code_ptr));
            },
        )
    }
}

/// Store info about a JIT entry point
pub struct JITEntry {
    /// Index that corresponds to [crate::hir::jit_entry_insns]
    jit_entry_idx: usize,
    /// Position where the entry point starts
    start_addr: Cell<Option<CodePtr>>,
}

impl JITEntry {
    /// Allocate a new JITEntry
    fn new(jit_entry_idx: usize) -> Rc<RefCell<Self>> {
        let jit_entry = JITEntry {
            jit_entry_idx,
            start_addr: Cell::new(None),
        };
        Rc::new(RefCell::new(jit_entry))
    }
}

/// Store info about a JIT-to-JIT call
#[derive(Debug)]
pub struct IseqCall {
    /// Callee ISEQ that start_addr jumps to
    pub iseq: Cell<IseqPtr>,

    /// Index that corresponds to [crate::hir::jit_entry_insns]
    jit_entry_idx: u32,

    /// Position where the call instruction starts
    start_addr: Cell<Option<CodePtr>>,

    /// Position where the call instruction ends (exclusive)
    end_addr: Cell<Option<CodePtr>>,
}

pub type IseqCallRef = Rc<IseqCall>;

impl IseqCall {
    /// Allocate a new IseqCall
    fn new(iseq: IseqPtr, jit_entry_idx: u32) -> IseqCallRef {
        let iseq_call = IseqCall {
            iseq: Cell::new(iseq),
            start_addr: Cell::new(None),
            end_addr: Cell::new(None),
            jit_entry_idx,
        };
        Rc::new(iseq_call)
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

#[cfg(test)]
mod tests {
    use crate::codegen::MAX_ISEQ_VERSIONS;
    use crate::cruby::test_utils::*;
    use crate::payload::*;

    #[test]
    fn test_max_iseq_versions() {
        eval(&format!("
            TEST = -1
            def test = TEST

            # compile and invalidate MAX+1 times
            i = 0
            while i < {MAX_ISEQ_VERSIONS} + 1
              test; test # compile a version

              Object.send(:remove_const, :TEST)
              TEST = i

              i += 1
            end
        "));

        // It should not exceed MAX_ISEQ_VERSIONS
        let iseq = get_method_iseq("self", "test");
        let payload = get_or_create_iseq_payload(iseq);
        assert_eq!(payload.versions.len(), MAX_ISEQ_VERSIONS);

        // The last call should not discard the JIT code
        assert!(matches!(unsafe { payload.versions.last().unwrap().as_ref() }.status, IseqStatus::Compiled(_)));
    }
}
