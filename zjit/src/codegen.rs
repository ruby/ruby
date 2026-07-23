//! This module is for native code generation.

#![allow(clippy::let_and_return)]

mod gc_fastpath;

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::ffi::{c_int, c_long, c_void};
use std::slice;

use crate::backend::current::ALLOC_REGS;
use crate::invariants::{
    track_bop_assumption, track_cme_assumption, track_no_ep_escape_assumption, track_no_trace_point_assumption,
    track_single_ractor_assumption, track_stable_constant_names_assumption, track_no_singleton_class_assumption,
    track_root_box_assumption
};
use crate::gc::append_gc_offsets;
use crate::payload::{IseqCodePtrs, IseqStatus, IseqVersion, IseqVersionRef, JITFrame, get_or_create_iseq_payload};
use crate::profile::reset_profiles_remaining;
use crate::state::ZJITState;
use crate::stats::{CompileError, exit_counter_for_compile_error, exit_counter_for_unhandled_hir_insn, incr_counter, incr_counter_by, send_fallback_counter, send_fallback_counter_for_method_type, send_fallback_counter_for_super_method_type, send_fallback_counter_ptr_for_opcode, send_fallback_counter_for_optimized_method_type};
use crate::stats::{counter_ptr, with_time_stat, trace_compile_phase, Counter, Counter::{compile_time_ns, exit_compile_error}};
use crate::{asm::CodeBlock, cruby::*, options::debug, virtualmem::CodePtr};
use crate::backend::lir::{self, Assembler, C_ARG_OPNDS, C_RET_OPND, CFP, EC, NATIVE_BASE_PTR, Opnd, SP, SideExit, SideExitRecompile, SideExitTarget, StackMap, StackMapEntry, Target, asm_ccall, asm_comment};
use crate::hir::{iseq_to_hir, BlockId, Invariant, RangeType, SideExitReason::{self, *}, SpecialBackrefSymbol, SpecialObjectType};
use crate::hir::{BlockHandler, CCallVariadicData, CCallWithFrameData, Const, FieldName, FrameState, Function, Insn, InsnId, Recompile, SendDirectData, SendFallbackReason, qualified_method_name};
use crate::hir_type::{types, Type};
use crate::options::{get_option, InlineDepth, PerfMap, DEFAULT_MAX_VERSIONS};
use crate::cast::IntoUsize;

/// Maximum number of compiled versions per ISEQ.
/// Configurable via --zjit-max-versions (default: 2).
pub fn max_iseq_versions() -> usize {
    unsafe { crate::options::OPTIONS.as_ref() }
        .map_or(DEFAULT_MAX_VERSIONS, |opts| opts.max_versions)
}

/// Sentinel program counter stored in C frames when runtime checks are enabled.
const PC_POISON: Option<*const VALUE> = if cfg!(feature = "runtime_checks") {
    Some(usize::MAX as *const VALUE)
} else {
    None
};

/// Ephemeral code generation state
struct JITState {
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

    /// The number of native stack slots reserved for JITFrame, one per
    /// simultaneously live frame (`inlining_depth() + 1`). gen_write_jit_frame()
    /// and the inlined frame push write a JITFrame into the slot selected by the
    /// current frame's depth.
    jit_frame_size: usize,
}

impl JITState {
    /// Create a new JITState instance
    fn new(version: IseqVersionRef, num_insns: usize, num_blocks: usize, jit_frame_size: usize) -> Self {
        JITState {
            version,
            opnds: vec![None; num_insns],
            labels: vec![None; num_blocks],
            jit_entries: Vec::default(),
            iseq_calls: Vec::default(),
            jit_frame_size,
        }
    }

    /// Retrieve the output of a given instruction that has been compiled
    fn get_opnd(&self, insn_id: InsnId) -> lir::Opnd {
        self.opnds[insn_id.0].unwrap_or_else(|| panic!("Failed to get_opnd({insn_id})"))
    }

    /// Get the ISEQ for the version currently being compiled.
    fn iseq(&self) -> IseqPtr {
        unsafe { self.version.as_ref().iseq }
    }

    /// Find or create a label for a given BlockId
    fn get_label(&mut self, asm: &mut Assembler, lir_block_id: lir::BlockId, hir_block_id: BlockId) -> Target {
        // Extend labels vector if the requested index is out of bounds
        if lir_block_id.0 >= self.labels.len() {
            self.labels.resize(lir_block_id.0 + 1, None);
        }

        match &self.labels[lir_block_id.0] {
            Some(label) => label.clone(),
            None => {
                let label = asm.new_label(&format!("{hir_block_id}_{lir_block_id}"));
                self.labels[lir_block_id.0] = Some(label.clone());
                label
            }
        }
    }

}

impl Assembler {
    /// Emit a conditional jump that splits the current block, creating a new
    /// fall-through block for instructions that follow.
    fn split_block_jump(&mut self, jit: &mut JITState, emit: impl FnOnce(&mut Assembler, Target), target: Target) {
        let hir_block_id = self.current_block().hir_block_id;
        let rpo_idx = self.current_block().rpo_index;

        let fall_through_target = self.new_block(hir_block_id, false, rpo_idx);
        let fall_through_edge = lir::BranchEdge {
            target: fall_through_target,
            args: vec![],
        };
        emit(self, target);
        self.jmp(Target::Block(Box::new(fall_through_edge)));

        self.set_current_block(fall_through_target);

        let label = jit.get_label(self, fall_through_target, hir_block_id);
        self.write_label(label);
    }
}

macro_rules! define_split_jumps {
    ($($name:ident => $insn:ident),+ $(,)?) => {
        impl Assembler {
            $(
                fn $name(&mut self, jit: &mut JITState, target: Target) {
                    self.split_block_jump(jit, |asm, target| asm.push_insn(lir::Insn::$insn(target)), target);
                }
            )+
        }
    };
}

define_split_jumps! {
    jbe => Jbe,
    je => Je,
    jge => Jge,
    jl => Jl,
    jne => Jne,
    jnz => Jnz,
    jo => Jo,
    jo_mul => JoMul,
    jz => Jz,
}

/// Record on the ISEQ payload whether `self` is guaranteed to be a heap object,
/// derived from the owning class of the method entry on `cfp`. Called from compile
/// triggers before the HIR is built so the `self`-producing instructions can be
/// typed precisely. Must be called while holding the VM lock (it writes the payload).
fn update_self_is_heap_object(iseq: IseqPtr, cfp: CfpPtr) {
    let cme = unsafe { rb_vm_frame_method_entry(cfp) };
    let self_is_heap_object = !cme.is_null()
        && iseq_self_is_heap_object(iseq, unsafe { (*cme).owner });
    get_or_create_iseq_payload(iseq).self_is_heap_object = self_is_heap_object;
}

/// CRuby API to compile a given ISEQ.
/// If jit_exception is true, compile JIT code for handling exceptions.
/// See jit_compile_exception() for details.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, ec: EcPtr, jit_exception: bool) -> *const u8 {
    // Don't compile when there is insufficient native stack space
    if unsafe { rb_ec_stack_check(ec as _) } != 0 {
        incr_counter!(skipped_native_stack_full);
        return std::ptr::null();
    }

    // Take a lock to avoid writing to ISEQ in parallel with Ractors.
    // with_vm_lock() does nothing if the program doesn't use Ractors.
    with_vm_lock(src_loc!(), || {
        // The current frame is this ISEQ's method frame, so its method entry tells
        // us the owning class and thus whether `self` is always a heap object.
        update_self_is_heap_object(iseq, unsafe { get_ec_cfp(ec) });

        let cb = ZJITState::get_code_block();
        let mut code_ptr = with_time_stat(compile_time_ns, || gen_iseq_entry_point(cb, iseq, jit_exception));

        if let Err(err) = &code_ptr {
            // Assert that the ISEQ compiles if RubyVM::ZJIT.assert_compiles is enabled.
            // We assert only `jit_exception: false` cases until we support exception handlers.
            if ZJITState::assert_compiles_enabled() && !jit_exception {
                let iseq_location = iseq_get_location(iseq, 0);
                panic!("Failed to compile: {iseq_location}: {err:?}");
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

    let iseq_name = iseq_get_location(iseq, 0);
    trace_compile_phase(&iseq_name, || {
        // Compile ISEQ into High-level IR
        let function = crate::stats::with_time_stat(Counter::compile_hir_time_ns, || compile_iseq(iseq).inspect_err(|_| {
            incr_counter!(failed_iseq_count);
        }))?;

        // Compile the High-level IR
        let IseqCodePtrs { start_ptr, .. } = gen_iseq(cb, iseq, Some(&function)).inspect_err(|err| {
            debug!("{err:?}: gen_iseq failed: {}", iseq_get_location(iseq, 0));
        })?;

        Ok(start_ptr)
    })
}

/// Invalidate an ISEQ version and allow it to be recompiled on the next call.
/// Both PatchPoint invalidation and exit-profiling recompilation go through this
/// function, serving as the central point for all invalidation/recompile decisions.
///
/// TODO: evolve this into a general `handle_event(iseq, event)` state machine that
/// handles all compile lifecycle events (interpreter profiles, JIT profiles, invalidation,
/// GC) so that all compile/recompile tuning decisions live in one place.
pub fn invalidate_iseq_version(cb: &mut CodeBlock, iseq: IseqPtr, version: &mut IseqVersionRef) {
    let payload = get_or_create_iseq_payload(iseq);
    if !unsafe { version.as_ref() }.is_invalidated()
        && payload.versions.len() < max_iseq_versions()
    {
        unsafe { version.as_mut() }.status = IseqStatus::Invalidated;
        unsafe { rb_iseq_reset_jit_func(iseq) };

        // Recompile JIT-to-JIT calls into the invalidated ISEQ
        for incoming in unsafe { version.as_ref() }.incoming.iter() {
            if let Err(err) = gen_iseq_call(cb, incoming) {
                debug!("{err:?}: gen_iseq_call failed during invalidation: {}", iseq_get_location(incoming.iseq.get(), 0));
            }
        }
    }
}

/// Stub a branch for a JIT-to-JIT call
pub fn gen_iseq_call(cb: &mut CodeBlock, iseq_call: &IseqCallRef) -> Result<(), CompileError> {
    trace_compile_phase("compile_stub", || {
        // Compile a function stub
        let stub_ptr = gen_function_stub(cb, iseq_call.clone()).inspect_err(|err| {
            debug!("{err:?}: gen_function_stub failed: {}", iseq_get_location(iseq_call.iseq.get(), 0));
        })?;

        // Update the JIT-to-JIT call to call the stub
        let stub_addr = stub_ptr.raw_ptr(cb);
        let iseq = iseq_call.iseq.get();
        iseq_call.regenerate(cb, |asm| {
            asm_comment!(asm, "call function stub: {}", iseq_get_location(iseq, 0));
            asm.ccall_into(C_RET_OPND, stub_addr, vec![]);
        });
        Ok(())
    })
}

/// Write an entry to the perf map in /tmp
pub(crate) fn register_with_perf(symbol_name: String, start_ptr: usize, code_size: usize) {
    use std::io::Write;
    let perf_map = format!("/tmp/perf-{}.map", std::process::id());
    let Ok(file) = std::fs::OpenOptions::new().create(true).append(true).open(&perf_map) else {
        debug!("Failed to open perf map file: {perf_map}");
        return;
    };
    let mut file = std::io::BufWriter::new(file);
    let Ok(_) = writeln!(file, "{start_ptr:#x} {code_size:#x} ZJIT: {symbol_name}") else {
        debug!("Failed to write {symbol_name} to perf map file: {perf_map}");
        return;
    };
}

/// Register the code emitted from `start` through the current write pointer
/// under `symbol_name` in the perf map, if perf output is enabled.
fn register_current_code_range_with_perf(cb: &CodeBlock, symbol_name: &str, start: CodePtr) {
    if get_option!(perf).is_some() {
        let start_ptr = start.raw_addr(cb);
        let end_ptr = cb.get_write_ptr().raw_addr(cb);
        register_with_perf(symbol_name.to_string(), start_ptr, end_ptr - start_ptr);
    }
}

/// Compile a shared JIT entry trampoline
pub fn gen_entry_trampoline(cb: &mut CodeBlock) -> Result<CodePtr, CompileError> {
    // Set up registers for CFP, EC, SP, and basic block arguments
    let mut asm = Assembler::new();
    asm.new_block_without_id("gen_entry_trampoline");
    gen_entry_prologue(&mut asm);

    // Jump to the first block using a call instruction. This trampoline is used
    // as rb_zjit_func_t in jit_exec(), which takes (EC, CFP, rb_jit_func_t).
    // So C_ARG_OPNDS[2] is rb_jit_func_t, which is (EC, CFP) -> VALUE.
    let out = asm.ccall_reg(C_ARG_OPNDS[2], VALUE_BITS);

    // Restore registers for CFP, EC, and SP after use
    asm_comment!(asm, "return to the interpreter");
    asm.frame_teardown(lir::JIT_PRESERVED_REGS);
    asm.cret(out);

    let (code_ptr, gc_offsets) = asm.compile(cb)?;
    assert!(gc_offsets.is_empty());
    register_current_code_range_with_perf(cb, "entry trampoline", code_ptr);
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
    // If the ISEQ already has max versions, do not compile a new version.
    if payload.versions.len() >= max_iseq_versions() {
        return Err(CompileError::IseqVersionLimitReached);
    }

    // Compile the ISEQ. When function is None, this is a lazy compile
    // from a stub hit -- wrap in a trace event covering the full compile.
    let mut version = IseqVersion::new(iseq);
    let code_ptrs = if function.is_none() {
        trace_compile_phase(&iseq_get_location(iseq, 0), || gen_iseq_body(cb, iseq, version, function))
    } else {
        gen_iseq_body(cb, iseq, version, function)
    };
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
        None => &crate::stats::with_time_stat(Counter::compile_hir_time_ns, || compile_iseq(iseq))?,
    };

    // Compile the High-level IR
    let (iseq_code_ptrs, gc_offsets, iseq_calls) =
        trace_compile_phase("codegen", || {
            let (iseq_code_ptrs, gc_offsets, iseq_calls) =
                crate::stats::with_time_stat(Counter::compile_lir_time_ns, || gen_function(cb, iseq, version, function))?;

            // Stub callee ISEQs for JIT-to-JIT calls
            trace_compile_phase("generate_jit_jit_stubs", || {
                for iseq_call in iseq_calls.iter() {
                    gen_iseq_call(cb, iseq_call)?;
                }
                Ok::<(), CompileError>(())
            })?;

            Ok((iseq_code_ptrs, gc_offsets, iseq_calls))
        })?;

    // Prepare for GC
    unsafe { version.as_mut() }.outgoing.extend(iseq_calls);
    append_gc_offsets(iseq, version, &gc_offsets);
    Ok(iseq_code_ptrs)
}

/// Compile a function
fn gen_function(cb: &mut CodeBlock, iseq: IseqPtr, version: IseqVersionRef, function: &Function) -> Result<(IseqCodePtrs, Vec<CodePtr>, Vec<IseqCallRef>), CompileError> {
    let (mut jit, asm) = trace_compile_phase("codegen", || {
        // Reserve one JITFrame slot per simultaneously live frame. The top-level
        // frame is depth 0, and each level of inlining adds another frame that
        // can be on the CFP chain at the same time, so we need
        // `inlining_depth() + 1` slots. gen_write_jit_frame() and the inlined
        // frame push select among these slots by the frame's depth, keeping each
        // frame's `cfp->jit_return` pointed at its own slot rather than a shared
        // one.
        let jit_frame_size = function.inlining_depth() + 1;
        let mut jit = JITState::new(version, function.num_insns(), function.num_blocks(), jit_frame_size);
        let mut asm = Assembler::new_with_stack_slots(jit_frame_size);

        // Mapping from HIR block IDs to LIR block IDs.
        // This is is a one-to-one mapping from HIR to LIR blocks used for finding
        // jump targets in LIR (LIR should always jump to the head of an HIR block)
        let mut hir_to_lir: Vec<Option<lir::BlockId>> = vec![None; function.num_blocks()];

        let reverse_post_order = function.reverse_post_order();

        // Create all LIR basic blocks corresponding to HIR basic blocks
        for (rpo_idx, &block_id) in reverse_post_order.iter().enumerate() {
            // Skip the entries superblock -- it's an internal CFG artifact
            if block_id == function.entries_block { continue; }
            let lir_block_id = asm.new_block(block_id, function.is_entry_block(block_id), rpo_idx);
            hir_to_lir[block_id.0] = Some(lir_block_id);
        }

        // Compile each basic block
        for &block_id in reverse_post_order.iter() {
            // Skip the entries superblock -- it's an internal CFG artifact
            if block_id == function.entries_block { continue; }
            // Set the current block to the LIR block that corresponds to this
            // HIR block.
            let lir_block_id = hir_to_lir[block_id.0].unwrap();
            asm.set_current_block(lir_block_id);

            // Write a label to jump to the basic block
            let label = jit.get_label(&mut asm, lir_block_id, block_id);
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

            // In JIT entry blocks, compile LoadArg instructions before other instructions
            // so that calling convention registers are reserved early, like Param.
            if function.is_entry_block(block_id) {
                for &insn_id in block.insns() {
                    if let Insn::LoadArg { idx, .. } = function.find(insn_id) {
                        jit.opnds[insn_id.0] = Some(gen_param(&mut asm, idx as usize));
                    }
                }
            }

            // Compile all instructions
            for (insn_idx, &insn_id) in block.insns().enumerate() {
                let insn = function.find(insn_id);
                let perf_symbol = hir_perf_symbol_range_start(&mut asm, &insn);

                let result = match &insn {
                    Insn::CondBranch { val, if_true, if_false } => {
                        let val_opnd = jit.get_opnd(*val);
                        let true_target = hir_to_lir[if_true.target.0].unwrap();
                        let false_target = hir_to_lir[if_false.target.0].unwrap();

                        let true_branch = lir::BranchEdge {
                            target: true_target,
                            args: if_true.args.iter().map(|insn_id| jit.get_opnd(*insn_id)).collect()
                        };

                        let false_branch = lir::BranchEdge {
                            target: false_target,
                            args: if_false.args.iter().map(|insn_id| jit.get_opnd(*insn_id)).collect()
                        };

                        asm.test(val_opnd, val_opnd);
                        asm.push_insn(lir::Insn::Jnz(Target::Block(Box::new(true_branch))));
                        asm.jmp(Target::Block(Box::new(false_branch)));

                        assert!(asm.current_block().insns.last().unwrap().is_terminator());
                        Ok(())
                    }
                    Insn::Jump(target) => {
                        let lir_target = hir_to_lir[target.target.0].unwrap();
                        let branch_edge = lir::BranchEdge {
                            target: lir_target,
                            args: target.args.iter().map(|insn_id| jit.get_opnd(*insn_id)).collect()
                        };
                        asm.jmp(Target::Block(Box::new(branch_edge)));
                        assert!(asm.current_block().insns.last().unwrap().is_terminator());

                        // Jump should always be the last instruction in an HIR block
                        assert!(insn_idx == block.insns().len() - 1, "Jump must be the last instruction in HIR block");
                        Ok(())
                    },
                    _ => {
                        gen_insn(cb, &mut jit, &mut asm, function, insn_id, &insn)
                    }
                };

                // Close the current perf range for the HIR instruction.
                if let Some(perf_symbol) = &perf_symbol {
                    if result.is_ok() && insn.is_terminator() {
                        assert!(asm.current_block().insns.last().is_some_and(|insn| insn.is_terminator()));
                        perf_symbol_range_end_at_block_end(&mut asm, perf_symbol);
                    } else {
                        perf_symbol_range_end(&mut asm, perf_symbol);
                    }
                }

                if let Err(last_snapshot) = result {
                    debug!("ZJIT: gen_function: Failed to compile insn: {insn_id} {insn}. Generating side-exit.");
                    gen_incr_counter(&mut asm, exit_counter_for_unhandled_hir_insn(&insn));
                    let reason = match insn {
                        Insn::Throw { .. }         => SideExitReason::UnhandledHIRThrow,
                        Insn::InvokeBuiltin { .. } => SideExitReason::UnhandledHIRInvokeBuiltin,
                        _                          => SideExitReason::UnhandledHIRUnknown(insn_id),
                    };
                    gen_side_exit(&mut jit, &mut asm, function, &reason, None, &function.frame_state(last_snapshot));
                    // Don't bother generating code after a side-exit. We won't run it.
                    // TODO(max): Generate ud2 or equivalent.
                    break;
                };
                // It's fine; we generated the instruction
            }
            // Blocks should always end with control flow
            assert!(asm.current_block().insns.last().unwrap().is_terminator());
        }

        assert!(!asm.reverse_post_order().is_empty());

        // Validate CFG invariants after HIR to LIR lowering
        asm.validate_jump_positions();

        (jit, asm)
    });

    // Generate code if everything can be compiled
    let result = asm.compile(cb);
    if let Ok((start_ptr, _)) = result {
        if get_option!(perf) == Some(PerfMap::ISEQ) {
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
        Insn::Comment { .. } => return Ok(()), // comment instruction, no code generation
        &Insn::Const { val: Const::Value(val) } => gen_const_value(val),
        &Insn::Const { val: Const::CPtr(val) } => gen_const_cptr(val),
        &Insn::Const { val: Const::CInt64(val) } => gen_const_long(val),
        &Insn::Const { val: Const::CUInt16(val) } => gen_const_uint16(val),
        &Insn::Const { val: Const::CUInt32(val) } => gen_const_uint32(val),
        &Insn::Const { val: Const::CUInt64(val) } => Opnd::UImm(val),
        &Insn::Const { val: Const::CAttrIndex(val) } => gen_const_attr_index_t(val),
        &Insn::Const { val: Const::CShape(val) } => {
            assert_eq!(SHAPE_ID_NUM_BITS, 32);
            gen_const_uint32(val.0)
        }
        Insn::Const { .. } => panic!("Unexpected Const in gen_insn: {insn}"),
        Insn::NewArray { elements, state } => gen_new_array(jit, asm, opnds!(elements), &function.frame_state(*state)),
        Insn::NewHash { elements, state } => {
            let sym_keys = elements.iter().step_by(2).all(|&key| function.type_of(key).is_subtype(types::Symbol));
            gen_new_hash(jit, asm, function, opnds!(elements), sym_keys, &function.frame_state(*state))
        }
        Insn::NewRange { low, high, flag, state } => gen_new_range(jit, asm, function, opnd!(low), opnd!(high), *flag, &function.frame_state(*state)),
        Insn::NewRangeFixnum { low, high, flag, state } => gen_new_range_fixnum(jit, asm, opnd!(low), opnd!(high), *flag, &function.frame_state(*state)),
        Insn::ArrayDup { val, state } => gen_array_dup(jit, asm, function, *val, opnd!(val), &function.frame_state(*state)),
        Insn::AdjustBounds { index, length } => gen_adjust_bounds(asm, opnd!(index), opnd!(length)),
        Insn::ArrayAref { array, index, .. } => gen_array_aref(asm, opnd!(array), opnd!(index)),
        Insn::ArrayAset { array, index, val } => {
            no_output!(gen_array_aset(asm, opnd!(array), opnd!(index), opnd!(val)))
        }
        Insn::ArrayPop { array, state } => gen_array_pop(asm, opnd!(array), &function.frame_state(*state)),
        Insn::ArrayLength { array } => gen_array_length(asm, opnd!(array)),
        Insn::ObjectAlloc { val, state } => gen_object_alloc(jit, asm, function, opnd!(val), &function.frame_state(*state)),
        &Insn::ObjectAllocClass { class, state } => gen_object_alloc_class(jit, asm, class, &function.frame_state(state)),
        Insn::StringCopy { val, chilled, state } => gen_string_copy(jit, asm, function, *val, opnd!(val), *chilled, &function.frame_state(*state)),
        Insn::StringConcat { strings, state } => gen_string_concat(jit, asm, function, opnds!(strings), &function.frame_state(*state)),
        &Insn::StringGetbyte { string, index } => gen_string_getbyte(asm, opnd!(string), opnd!(index)),
        Insn::StringSetbyteFixnum { string, index, value } => gen_string_setbyte_fixnum(asm, opnd!(string), opnd!(index), opnd!(value)),
        Insn::StringAppend { recv, other, state } => gen_string_append(jit, asm, function, opnd!(recv), opnd!(other), &function.frame_state(*state)),
        Insn::StringAppendCodepoint { recv, other, state } => gen_string_append_codepoint(jit, asm, function, opnd!(recv), opnd!(other), &function.frame_state(*state)),
        Insn::StringEqual { left, right } => gen_string_equal(asm, opnd!(left), opnd!(right)),
        Insn::StringIntern { val, state } => gen_intern(asm, opnd!(val), &function.frame_state(*state)),
        Insn::ToRegexp { opt, values, state } => gen_toregexp(jit, asm, function, *opt, opnds!(values), &function.frame_state(*state)),
        Insn::Param => unreachable!("block.insns should not have Insn::Param"),
        Insn::LoadArg { .. } => return Ok(()), // compiled in the LoadArg pre-pass above
        Insn::Snapshot { .. } => return Ok(()), // we don't need to do anything for this instruction at the moment
        &Insn::Send { cd, block: None, state, reason, .. } => gen_send_without_block(jit, asm, function, cd, &function.frame_state(state), reason),
        &Insn::Send { cd, block: Some(BlockHandler::BlockIseq(blockiseq)), state, reason, .. } => gen_send(jit, asm, function, cd, blockiseq, &function.frame_state(state), reason),
        &Insn::Send { cd, block: Some(BlockHandler::BlockArg), state, reason, .. } => gen_send(jit, asm, function, cd, std::ptr::null(), &function.frame_state(state), reason),
        &Insn::SendForward { cd, blockiseq, state, reason, .. } => gen_send_forward(jit, asm, function, cd, blockiseq, &function.frame_state(state), reason),
        Insn::SendDirect(insn) => {
            let SendDirectData { cme, iseq, recv, args, kw_bits, jit_entry_idx, block, state, .. } = &**insn;
            gen_send_iseq_direct(
                cb, jit, asm,
                function, *cme, *iseq, opnd!(recv), opnds!(args),
                *kw_bits, *jit_entry_idx, &function.frame_state(*state), *block,
            )
        }
        Insn::PushInlineFrame { cme, iseq, recv, args, blockiseq, state, .. } => {
            no_output!(gen_push_inline_frame(jit, asm, function, *cme, *iseq, opnd!(recv), opnds!(args), &function.frame_state(*state), *blockiseq))
        },
        Insn::PopInlineFrame { iseq, argc, state } => {
            no_output!(gen_pop_inline_frame(asm, *iseq, *argc, &function.frame_state(*state)))
        },
        &Insn::InvokeSuper { cd, blockiseq, state, reason, .. } => gen_invokesuper(jit, asm, function, cd, blockiseq, &function.frame_state(state), reason),
        &Insn::InvokeSuperForward { cd, blockiseq, state, reason, .. } => gen_invokesuperforward(jit, asm, function, cd, blockiseq, &function.frame_state(state), reason),
        &Insn::InvokeBlock { cd, state, reason, .. } => gen_invokeblock(jit, asm, function, cd, &function.frame_state(state), reason),
        Insn::InvokeBlockIfunc { cd, block_handler, args, state, .. } => gen_invokeblock_ifunc(jit, asm, function, *cd, opnd!(block_handler), opnds!(args), &function.frame_state(*state)),
        Insn::InvokeProc { recv, args, state, kw_splat } => gen_invokeproc(jit, asm, function, opnd!(recv), opnds!(args), *kw_splat, &function.frame_state(*state)),
        Insn::InvokeBuiltin { bf, leaf, args, state, .. } => gen_invokebuiltin(jit, asm, function, &function.frame_state(*state), unsafe { &**bf }, *leaf, opnds!(args)),
        Insn::InvokeBlockIseqDirect { iseq, captured, args, state } => gen_invoke_block_iseq_direct(cb, jit, asm, function, *iseq, opnd!(captured), opnds!(args), &function.frame_state(*state)),
        &Insn::EntryPoint { jit_entry_idx } => no_output!(gen_entry_point(jit, asm, jit_entry_idx)),
        Insn::Return { val } => no_output!(gen_return(asm, opnd!(val))),
        Insn::FixnumAdd { left, right, state } => gen_fixnum_add(jit, asm, function, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumSub { left, right, state } => gen_fixnum_sub(jit, asm, function, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumMult { left, right, state } => gen_fixnum_mult(jit, asm, function, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FixnumDiv { left, right, state } => gen_fixnum_div(jit, asm, function, opnd!(left), opnd!(right), &function.frame_state(*state)),
        Insn::FloatAdd { recv, other, state } => gen_float_add(asm, opnd!(recv), opnd!(other), &function.frame_state(*state)),
        Insn::FloatSub { recv, other, state } => gen_float_sub(asm, opnd!(recv), opnd!(other), &function.frame_state(*state)),
        Insn::FloatMul { recv, other, state } => gen_float_mul(asm, opnd!(recv), opnd!(other), &function.frame_state(*state)),
        Insn::FloatDiv { recv, other, state } => gen_float_div(asm, opnd!(recv), opnd!(other), &function.frame_state(*state)),
        Insn::FloatToInt { recv, state } => gen_float_to_int(asm, opnd!(recv), &function.frame_state(*state)),
        Insn::FixnumEq { left, right } => gen_fixnum_eq(asm, opnd!(left), opnd!(right)),
        Insn::FixnumNeq { left, right } => gen_fixnum_neq(asm, opnd!(left), opnd!(right)),
        Insn::FixnumLt { left, right } => gen_fixnum_lt(asm, opnd!(left), opnd!(right)),
        Insn::FixnumLe { left, right } => gen_fixnum_le(asm, opnd!(left), opnd!(right)),
        Insn::FixnumGt { left, right } => gen_fixnum_gt(asm, opnd!(left), opnd!(right)),
        Insn::FixnumGe { left, right } => gen_fixnum_ge(asm, opnd!(left), opnd!(right)),
        Insn::FixnumAnd { left, right } => gen_fixnum_and(asm, opnd!(left), opnd!(right)),
        Insn::FixnumOr { left, right } => gen_fixnum_or(asm, opnd!(left), opnd!(right)),
        Insn::FixnumXor { left, right } => gen_fixnum_xor(asm, opnd!(left), opnd!(right)),
        Insn::IntAnd { left, right } => asm.and(opnd!(left), opnd!(right)),
        Insn::IntOr { left, right } => gen_int_or(asm, opnd!(left), opnd!(right)),
        &Insn::FixnumLShift { left, right, state } => {
            // We only create FixnumLShift when we know the shift amount statically and it's in [0,
            // 63].
            let shift_amount = function.type_of(right).fixnum_value().unwrap() as u64;
            gen_fixnum_lshift(jit, asm, function, opnd!(left), shift_amount, &function.frame_state(state))
        }
        &Insn::FixnumRShift { left, right } => {
            // We only create FixnumRShift when we know the shift amount statically and it's in [0,
            // 63].
            let shift_amount = function.type_of(right).fixnum_value().unwrap() as u64;
            gen_fixnum_rshift(asm, opnd!(left), shift_amount)
        }
        &Insn::FixnumMod { left, right, state } => gen_fixnum_mod(jit, asm, function, opnd!(left), opnd!(right), &function.frame_state(state)),
        &Insn::FixnumAref { recv, index } => gen_fixnum_aref(asm, opnd!(recv), opnd!(index)),
        &Insn::IsMethodCfunc { val, cd, cfunc, state } => gen_is_method_cfunc(asm, opnd!(val), cd, cfunc, &function.frame_state(state)),
        &Insn::IsBitEqual { left, right } => gen_is_bit_equal(asm, opnd!(left), opnd!(right)),
        &Insn::IsBitNotEqual { left, right } => gen_is_bit_not_equal(asm, opnd!(left), opnd!(right)),
        &Insn::BoxBool { val } => gen_box_bool(asm, opnd!(val)),
        &Insn::BoxFixnum { val, state } => gen_box_fixnum(jit, asm, function, opnd!(val), &function.frame_state(state)),
        &Insn::UnboxFixnum { val } => gen_unbox_fixnum(asm, opnd!(val)),
        Insn::Test { val } => gen_test(asm, opnd!(val), function.type_of(*val)),
        Insn::RefineType { val, .. } => opnd!(val),
        Insn::HasType { val, expected } => {
            let val_type = function.type_of(*val);
            gen_has_type(jit, asm, opnd!(val), val_type, *expected)
        }
        &Insn::GuardType { val, guard_type, state, recompile } => {
            let val_type = function.type_of(val);
            gen_guard_type(jit, asm, function, opnd!(val), val_type, guard_type, recompile, &function.frame_state(state))
        }
        &Insn::GuardBitEquals { val, expected, ref reason, state, recompile } => gen_guard_bit_equals(jit, asm, function, opnd!(val), expected, **reason, recompile, &function.frame_state(state)),
        &Insn::GuardAnyBitSet { val, mask, ref reason, state, recompile, .. } => gen_guard_any_bit_set(jit, asm, function, opnd!(val), mask, **reason, recompile, &function.frame_state(state)),
        &Insn::GuardNoBitsSet { val, mask, ref reason, state, .. } => gen_guard_no_bits_set(jit, asm, function, opnd!(val), mask, **reason, &function.frame_state(state)),
        &Insn::GuardLess { left, right, ref reason, state } => gen_guard_less(jit, asm, function, opnd!(left), opnd!(right), **reason, &function.frame_state(state)),
        &Insn::GuardGreaterEq { left, right, state, .. } => gen_guard_greater_eq(jit, asm, function, opnd!(left), opnd!(right), &function.frame_state(state)),
        Insn::PatchPoint { invariant, state } => no_output!(gen_patch_point(jit, asm, function, invariant, &function.frame_state(*state))),
        Insn::CCall { cfunc, recv, args, name, owner, return_type: _, elidable: _ } => gen_ccall(asm, *cfunc, *name, *owner, opnd!(recv), opnds!(args)),
        Insn::CCallWithFrame(insn) => {
            let CCallWithFrameData { cfunc, recv, name, args, cme, state, block, .. } = &**insn;
            gen_ccall_with_frame(jit, asm, function, *cfunc, *name, opnd!(recv), opnds!(args), *cme, *block, &function.frame_state(*state))
        }
        Insn::CCallVariadic(insn) => {
            let CCallVariadicData { cfunc, recv, name, args, cme, state, block, .. } = &**insn;
            gen_ccall_variadic(jit, asm, function, *cfunc, *name, opnd!(recv), opnds!(args), *cme, *block, &function.frame_state(*state))
        }
        Insn::GetIvar { self_val, id, ic, state } => gen_getivar(asm, opnd!(self_val), *id, *ic, &function.frame_state(*state)),
        Insn::SetGlobal { id, val, state } => no_output!(gen_setglobal(jit, asm, function, *id, opnd!(val), &function.frame_state(*state))),
        Insn::GetGlobal { id, state } => gen_getglobal(jit, asm, function, *id, &function.frame_state(*state)),
        &Insn::IsBlockParamModified { flags } => gen_is_block_param_modified(asm, opnd!(flags)),
        &Insn::GetBlockParam { ep_offset, level, state } => gen_getblockparam(jit, asm, function, ep_offset, level, &function.frame_state(state)),
        &Insn::SetLocal { val, ep_offset, level, .. } => no_output!(gen_setlocal(asm, opnd!(val), function.type_of(val), ep_offset, level)),
        Insn::GetConstant { klass, id, allow_nil, state } => gen_getconstant(jit, asm, function, opnd!(klass), *id, opnd!(allow_nil), &function.frame_state(*state)),
        Insn::GetConstantPath { ic, state } => gen_get_constant_path(jit, asm, function, *ic, &function.frame_state(*state)),
        Insn::GetClassVar { id, ic, state } => gen_getclassvar(jit, asm, function, *id, *ic, &function.frame_state(*state)),
        Insn::SetClassVar { id, val, ic, state } => no_output!(gen_setclassvar(jit, asm, function, *id, opnd!(val), *ic, &function.frame_state(*state))),
        Insn::SetIvar { self_val, id, ic, val, state } => no_output!(gen_setivar(jit, asm, function, opnd!(self_val), *id, *ic, opnd!(val), &function.frame_state(*state))),
        Insn::FixnumBitCheck { val, index } => gen_fixnum_bit_check(asm, opnd!(val), *index),
        Insn::SideExit { state, reason, recompile } => no_output!(gen_side_exit(jit, asm, function, reason, *recompile, &function.frame_state(*state))),
        Insn::PutSpecialObject { value_type, state } => gen_putspecialobject(jit, asm, function, *value_type, &function.frame_state(*state)),
        Insn::AnyToString { val, state } => gen_anytostring(asm, opnd!(val), &function.frame_state(*state)),
        Insn::Defined { op_type, obj, pushval, v, lep_level, state } => gen_defined(jit, asm, function, *op_type, *obj, *pushval, opnd!(v), *lep_level, &function.frame_state(*state)),
        Insn::CheckMatch { target, pattern, flag, state } => gen_checkmatch(jit, asm, function, opnd!(target), opnd!(pattern), *flag, &function.frame_state(*state)),
        Insn::GetSpecialSymbol { symbol_type, state } => gen_getspecial_symbol(asm, *symbol_type, &function.frame_state(*state)),
        Insn::GetSpecialNumber { nth, state } => gen_getspecial_number(asm, *nth, &function.frame_state(*state)),
        &Insn::IncrCounter(counter) => no_output!(gen_incr_counter(asm, counter)),
        Insn::IncrCounterPtr { counter_ptr } => no_output!(gen_incr_counter_ptr(asm, *counter_ptr)),
        &Insn::CheckInterrupts { state } => no_output!(gen_check_interrupts(jit, asm, function, &function.frame_state(state))),
        Insn::BreakPoint => no_output!(asm.breakpoint()),
        Insn::Unreachable => no_output!(asm.abort()),
        &Insn::HashDup { val, state } => { gen_hash_dup(asm, opnd!(val), &function.frame_state(state)) },
        &Insn::HashAref { hash, key, state } => { gen_hash_aref(jit, asm, function, opnd!(hash), opnd!(key), &function.frame_state(state)) },
        &Insn::HashAset { hash, key, val, state } => { no_output!(gen_hash_aset(jit, asm, function, opnd!(hash), opnd!(key), opnd!(val), &function.frame_state(state))) },
        &Insn::ArrayPush { array, val, state } => { no_output!(gen_array_push(asm, opnd!(array), opnd!(val), &function.frame_state(state))) },
        &Insn::ToNewArray { val, state } => { gen_to_new_array(jit, asm, function, opnd!(val), &function.frame_state(state)) },
        &Insn::ToArray { val, state } => { gen_to_array(jit, asm, function, opnd!(val), &function.frame_state(state)) },
        &Insn::DefinedIvar { self_val, id, pushval, .. } => { gen_defined_ivar(asm, opnd!(self_val), id, pushval) },
        &Insn::ArrayExtend { left, right, state } => { no_output!(gen_array_extend(jit, asm, function, opnd!(left), opnd!(right), &function.frame_state(state))) },
        Insn::LoadPC => gen_load_pc(asm),
        Insn::LoadEC => gen_load_ec(),
        Insn::LoadSP => gen_load_sp(),
        &Insn::GetEP { level } => gen_get_ep(asm, level),
        Insn::LoadSelf => gen_load_self(asm),
        &Insn::LoadField { recv, id, offset, return_type: _, num_bits } => gen_load_field(asm, opnd!(recv), id, offset, num_bits),
        &Insn::StoreField { recv, id, offset, val, num_bits } => no_output!(gen_store_field(asm, opnd!(recv), id, offset, opnd!(val), num_bits)),
        &Insn::WriteBarrier { recv, val } => no_output!(gen_write_barrier(jit, asm, opnd!(recv), opnd!(val), function.type_of(val))),
        &Insn::IsBlockGiven { block_handler } => gen_is_block_given(asm, opnd!(block_handler)),
        Insn::ArrayInclude { elements, target, state } => gen_array_include(jit, asm, function, opnds!(elements), opnd!(target), &function.frame_state(*state)),
        Insn::ArrayPackBuffer { elements, fmt, buffer, state } => gen_array_pack_buffer(jit, asm, function, opnds!(elements), opnd!(fmt), (*buffer).map(|buffer| opnd!(buffer)), &function.frame_state(*state)),
        &Insn::DupArrayInclude { ary, target, state } => gen_dup_array_include(jit, asm, function, ary, opnd!(target), &function.frame_state(state)),
        Insn::ArrayHash { elements, state } => gen_opt_newarray_hash(jit, asm, function, opnds!(elements), &function.frame_state(*state)),
        &Insn::IsA { val, class } => gen_is_a(jit, asm, opnd!(val), opnd!(class)),
        &Insn::ArrayMax { ref elements, state } => gen_array_max(jit, asm, function, opnds!(elements), &function.frame_state(state)),
        &Insn::ArrayMin { ref elements, state } => gen_array_min(jit, asm, function, opnds!(elements), &function.frame_state(state)),
        &Insn::Throw { state, .. } => return Err(state),
        &Insn::CondBranch { .. }
        | &Insn::Jump { .. } | Insn::Entries { .. } => unreachable!(),
    };

    assert!(insn.has_output(), "Cannot write LIR output of HIR instruction with no output: {insn}");

    // If the instruction has an output, remember it in jit.opnds
    jit.opnds[insn_id.0] = Some(out_opnd);

    Ok(())
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

fn gen_defined(jit: &JITState, asm: &mut Assembler, function: &Function, op_type: usize, obj: VALUE, pushval: VALUE, tested_value: Opnd, lep_level: u32, state: &FrameState) -> Opnd {
    match op_type as defined_type {
        DEFINED_YIELD => {
            // `lep_level` was precomputed at HIR construction so we can materialize the local EP
            // inline without walking the parent iseq chain here.
            let lep = gen_get_ep(asm, lep_level);
            let block_handler = asm.load(Opnd::mem(64, lep, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL));
            let pushval = asm.load(pushval.into());
            asm.cmp(block_handler, VM_BLOCK_HANDLER_NONE.into());
            asm.csel_e(Qnil.into(), pushval)
        }
        _ => {
            // Save the PC and SP because the callee may allocate or call #respond_to?
            gen_prepare_non_leaf_call(jit, asm, function, state);

            // TODO: Inline the cases for each op_type
            // Call vm_defined(ec, reg_cfp, op_type, obj, v)
            let def_result = asm_ccall!(asm, rb_vm_defined, EC, CFP, op_type.into(), obj.into(), tested_value);

            asm.cmp(def_result.with_num_bits(8), 0.into());
            asm.csel_ne(pushval.into(), Qnil.into())
        }
    }
}

/// Similar to gen_defined for DEFINED_YIELD
fn gen_is_block_given(asm: &mut Assembler, block_handler: Opnd) -> Opnd {
    asm.cmp(block_handler, VM_BLOCK_HANDLER_NONE.into());
    asm.csel_e(Qfalse.into(), Qtrue.into())
}

fn gen_unbox_fixnum(asm: &mut Assembler, val: Opnd) -> Opnd {
    asm.rshift(val, Opnd::UImm(1))
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

/// Returns 1 (as CBool) when VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM is set; returns 0 otherwise.
fn gen_is_block_param_modified(asm: &mut Assembler, flags: Opnd) -> Opnd {
    asm.test(flags, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into());
    asm.csel_nz(Opnd::Imm(1), Opnd::Imm(0))
}

/// Get the block parameter as a Proc, write it to the environment,
/// and mark the flag as modified.
fn gen_getblockparam(jit: &mut JITState, asm: &mut Assembler, function: &Function, ep_offset: u32, level: u32, state: &FrameState) -> Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    // Bail out if write barrier is required.
    let ep = gen_get_ep(asm, level);
    let flags = Opnd::mem(VALUE_BITS, ep, SIZEOF_VALUE_I32 * (VM_ENV_DATA_INDEX_FLAGS as i32));
    asm.test(flags, VM_ENV_FLAG_WB_REQUIRED.into());
    asm.jnz(jit, side_exit(jit, function, state, SideExitReason::BlockParamWbRequired));

    // Convert block handler to Proc.
    let block_handler = asm.load(Opnd::mem(VALUE_BITS, ep, SIZEOF_VALUE_I32 * VM_ENV_DATA_INDEX_SPECVAL));
    let proc = asm_ccall!(asm, rb_vm_bh_to_procval, EC, block_handler);

    let local_ep_offset = c_int::try_from(ep_offset).unwrap_or_else(|_| {
        panic!("Could not convert local_ep_offset {ep_offset} to i32")
    });
    let offset = -(SIZEOF_VALUE_I32 * local_ep_offset);
    asm.mov(Opnd::mem(VALUE_BITS, ep, offset), proc);

    let flags = Opnd::mem(VALUE_BITS, ep, SIZEOF_VALUE_I32 * (VM_ENV_DATA_INDEX_FLAGS as i32));
    let flags_val = asm.load(flags);
    let modified = asm.or(flags_val, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM.into());
    asm.store(flags, modified);

    asm.load(Opnd::mem(VALUE_BITS, ep, offset))
}

fn gen_guard_less(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: Opnd, right: Opnd, reason: SideExitReason, state: &FrameState) -> Opnd {
    asm.cmp(left, right);
    asm.jge(jit, side_exit(jit, function, state, reason));
    left
}

fn gen_guard_greater_eq(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: Opnd, right: Opnd, state: &FrameState) -> Opnd {
    asm.cmp(left, right);
    asm.jl(jit, side_exit(jit, function, state, SideExitReason::GuardGreaterEq));
    left
}

fn gen_get_constant_path(jit: &JITState, asm: &mut Assembler, function: &Function, ic: *const iseq_inline_constant_cache, state: &FrameState) -> Opnd {
    unsafe extern "C" {
        fn rb_vm_opt_getconstant_path(ec: EcPtr, cfp: CfpPtr, ic: *const iseq_inline_constant_cache) -> VALUE;
    }

    // Anything could be called on const_missing
    gen_prepare_non_leaf_call(jit, asm, function, state);

    asm_ccall!(asm, rb_vm_opt_getconstant_path, EC, CFP, Opnd::const_ptr(ic))
}

fn gen_getconstant(jit: &mut JITState, asm: &mut Assembler, function: &Function, klass: Opnd, id: ID, allow_nil: Opnd, state: &FrameState) -> Opnd {
    unsafe extern "C" {
        fn rb_vm_get_ev_const(ec: EcPtr, klass: VALUE, id: ID, allow_nil: VALUE) -> VALUE;
    }

    // Constant lookup can raise and run arbitrary Ruby code via const_missing.
    gen_prepare_non_leaf_call(jit, asm, function, state);

    asm_ccall!(asm, rb_vm_get_ev_const, EC, klass, id.0.into(), allow_nil)
}

fn gen_fixnum_bit_check(asm: &mut Assembler, val: Opnd, index: u8) -> Opnd {
    let bit_test: u64 = 0x01 << (index + 1);
    asm.test(val, bit_test.into());
    asm.csel_z(Qtrue.into(), Qfalse.into())
}

fn gen_invokebuiltin(jit: &JITState, asm: &mut Assembler, function: &Function, state: &FrameState, bf: &rb_builtin_function, leaf: bool, args: Vec<Opnd>) -> lir::Opnd {
    // +2 for ec, self
    assert!(bf.argc + 2 <= C_ARG_OPNDS.len() as i32,
            "gen_invokebuiltin should not be called for builtin function {} with too many arguments: {}",
            unsafe { std::ffi::CStr::from_ptr(bf.name).to_str().unwrap() },
            bf.argc);
    if leaf {
        gen_prepare_leaf_call_with_gc(asm, state);
    } else {
        // Anything can happen inside builtin functions
        gen_prepare_non_leaf_call(jit, asm, function, state);
    }

    let mut cargs = vec![EC];
    cargs.extend(args);

    asm.count_call_to(unsafe { std::ffi::CStr::from_ptr(bf.name).to_str().unwrap() });
    asm.ccall(bf.func_ptr as *const u8, cargs)
}

/// Record a patch point that should be invalidated on a given invariant
fn gen_patch_point(jit: &mut JITState, asm: &mut Assembler, function: &Function, invariant: &Invariant, state: &FrameState) {
    let invariant = *invariant;
    let exit = build_side_exit(jit, function, state);

    // Let compile_exits compile a side exit. Let scratch_split lower it with split_patch_point.
    asm.patch_point(Target::SideExit(Box::new(SideExitTarget { exit, reason: PatchPoint(invariant) })), invariant, jit.version);
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
            Invariant::RootBoxOnly => {
                track_root_box_assumption(code_ptr, side_exit_ptr, version);
            }
        }
    });
}

/// Generate code for a C function call that pushes a frame
fn gen_ccall_with_frame(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cfunc: *const u8,
    name: ID,
    recv: Opnd,
    args: Vec<Opnd>,
    cme: *const rb_callable_method_entry_t,
    block: Option<BlockHandler>,
    state: &FrameState,
) -> lir::Opnd {
    gen_incr_counter(asm, Counter::non_variadic_cfunc_optimized_send_count);
    gen_stack_overflow_check(jit, asm, function, state, state.stack_size());

    let args_with_recv_len = args.len() + 1;
    if args_with_recv_len > C_ARG_OPNDS.len() {
        unimplemented!("Passing C call arguments on the stack");
    }
    let caller_stack_size = state.stack().len() - args_with_recv_len;

    // Can't use gen_prepare_non_leaf_call() because we need to adjust the SP
    // to account for the receiver and arguments (and block arguments if any)
    gen_write_jit_frame(asm, state, 0);
    gen_save_sp(asm, caller_stack_size);
    gen_spill_stack(jit, asm, function, state);
    gen_spill_locals(jit, asm, state);

    let block_handler_specval = if let Some(BlockHandler::BlockIseq(block_iseq)) = block {
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
        write_block_code: false,
    });

    asm_comment!(asm, "switch to new SP register");
    let sp_offset = (caller_stack_size + VM_ENV_DATA_SIZE.to_usize()) * SIZEOF_VALUE;
    let new_sp = asm.add(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    let mut cfunc_args = vec![recv];
    cfunc_args.extend(args);
    asm.count_call_to_with(|| qualified_method_name(unsafe { (*cme).owner }, name));
    let result = asm.ccall(cfunc, cfunc_args);

    asm_comment!(asm, "pop C frame");
    let new_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    asm_comment!(asm, "restore SP register for the caller");
    let new_sp = asm.sub(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    result
}

/// Lowering for [`Insn::CCall`]. This is a low-level raw call that doesn't know
/// anything about the callee, so handling for e.g. GC safety is dealt with elsewhere.
fn gen_ccall(asm: &mut Assembler, cfunc: *const u8, name: ID, owner: VALUE, recv: Opnd, args: Vec<Opnd>) -> lir::Opnd {
    let mut cfunc_args = vec![recv];
    cfunc_args.extend(args);
    asm.count_call_to_with(|| if owner == Qnil { name.contents_lossy().to_string() } else { qualified_method_name(owner, name) });
    asm.ccall(cfunc, cfunc_args)
}

// Change cfp->block_code in the current frame. See vm_caller_setup_arg_block().
// VM_CFP_TO_CAPTURED_BLOCK then turns &cfp->self into a block handler.
// rb_captured_block->code.iseq aliases with cfp->block_code.
fn gen_block_handler_specval(asm: &mut Assembler, blockiseq: IseqPtr) -> lir::Opnd {
    asm.store(Opnd::mem(VALUE_BITS, CFP, RUBY_OFFSET_CFP_BLOCK_CODE), VALUE::from(blockiseq).into());
    let cfp_self_addr = asm.lea(Opnd::mem(VALUE_BITS, CFP, RUBY_OFFSET_CFP_SELF));
    asm.or(cfp_self_addr, Opnd::Imm(1))
}

/// Generate code for a variadic C function call
/// func(int argc, VALUE *argv, VALUE recv)
fn gen_ccall_variadic(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cfunc: *const u8,
    name: ID,
    recv: Opnd,
    args: Vec<Opnd>,
    cme: *const rb_callable_method_entry_t,
    block: Option<BlockHandler>,
    state: &FrameState,
) -> lir::Opnd {
    gen_incr_counter(asm, Counter::variadic_cfunc_optimized_send_count);
    gen_stack_overflow_check(jit, asm, function, state, state.stack_size());

    let args_with_recv_len = args.len() + 1;

    // Compute the caller's stack size after consuming recv and args.
    // state.stack() includes recv + args, so subtract both.
    let caller_stack_size = state.stack_size() - args_with_recv_len;

    // Can't use gen_prepare_non_leaf_call() because we need to adjust the SP
    // to account for the receiver and arguments (like gen_ccall_with_frame does)
    gen_write_jit_frame(asm, state, 0);
    gen_save_sp(asm, caller_stack_size);
    gen_spill_stack(jit, asm, function, state);
    gen_spill_locals(jit, asm, state);

    let block_handler_specval = if let Some(BlockHandler::BlockIseq(blockiseq)) = block {
        gen_block_handler_specval(asm, blockiseq)
    } else {
        VM_BLOCK_HANDLER_NONE.into()
    };

    gen_push_frame(asm, args_with_recv_len, state, ControlFrame {
        recv,
        iseq: None,
        cme,
        frame_type: VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL,
        specval: block_handler_specval,
        write_block_code: false,
    });

    asm_comment!(asm, "switch to new SP register");
    let sp_offset = (caller_stack_size + VM_ENV_DATA_SIZE.to_usize()) * SIZEOF_VALUE;
    let new_sp = asm.add(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    let argv_ptr = gen_push_opnds(jit, asm, &args);
    asm.count_call_to_with(|| qualified_method_name(unsafe { (*cme).owner }, name));
    let result = asm.ccall(cfunc, vec![args.len().into(), argv_ptr, recv]);

    asm_comment!(asm, "pop C frame");
    let new_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    asm_comment!(asm, "restore SP register for the caller");
    let new_sp = asm.sub(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    result
}

/// Emit an uncached instance variable lookup
fn gen_getivar(asm: &mut Assembler, recv: Opnd, id: ID, ic: *const iseq_inline_iv_cache_entry, state: &FrameState) -> Opnd {
    gen_trace_fallback(asm, "getivar");
    if ic.is_null() {
        asm_ccall!(asm, rb_ivar_get, recv, id.0.into())
    } else {
        let iseq = Opnd::Value(state.iseq.into());
        asm_ccall!(asm, rb_vm_getinstancevariable, iseq, recv, id.0.into(), Opnd::const_ptr(ic))
    }
}

/// Emit an uncached instance variable store
fn gen_setivar(jit: &mut JITState, asm: &mut Assembler, function: &Function, recv: Opnd, id: ID, ic: *const iseq_inline_iv_cache_entry, val: Opnd, state: &FrameState) {
    gen_trace_fallback(asm, "setivar");
    // Setting an ivar can raise FrozenError, so we need proper frame state for exception handling.
    gen_prepare_non_leaf_call(jit, asm, function, state);
    if ic.is_null() {
        asm_ccall!(asm, rb_ivar_set, recv, id.0.into(), val);
    } else {
        let iseq = Opnd::Value(state.iseq.into());
        asm_ccall!(asm, rb_vm_setinstancevariable, iseq, recv, id.0.into(), val, Opnd::const_ptr(ic));
    }
}

fn gen_getclassvar(jit: &mut JITState, asm: &mut Assembler, function: &Function, id: ID, ic: *const iseq_inline_cvar_cache_entry, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_vm_getclassvariable, VALUE::from(state.iseq).into(), CFP, id.0.into(), Opnd::const_ptr(ic))
}

fn gen_setclassvar(jit: &mut JITState, asm: &mut Assembler, function: &Function, id: ID, val: Opnd, ic: *const iseq_inline_cvar_cache_entry, state: &FrameState) {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_vm_setclassvariable, VALUE::from(state.iseq).into(), CFP, id.0.into(), val, Opnd::const_ptr(ic));
}

/// Look up global variables
fn gen_getglobal(jit: &mut JITState, asm: &mut Assembler, function: &Function, id: ID, state: &FrameState) -> Opnd {
    // `Warning` module's method `warn` can be called when reading certain global variables
    gen_prepare_non_leaf_call(jit, asm, function, state);

    asm_ccall!(asm, rb_gvar_get, id.0.into())
}

/// Intern a string
fn gen_intern(asm: &mut Assembler, val: Opnd, state: &FrameState) -> Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

    asm_ccall!(asm, rb_str_intern, val)
}

/// Set global variables
fn gen_setglobal(jit: &mut JITState, asm: &mut Assembler, function: &Function, id: ID, val: Opnd, state: &FrameState) {
    // When trace_var is used, setting a global variable can cause exceptions
    gen_prepare_non_leaf_call(jit, asm, function, state);

    asm_ccall!(asm, rb_gvar_set, id.0.into(), val);
}

/// Side-exit into the interpreter
fn gen_side_exit(jit: &mut JITState, asm: &mut Assembler, function: &Function, reason: &SideExitReason, recompile: Option<Recompile>, state: &FrameState) {
    asm.jmp(side_exit_with_recompile(jit, function, state, *reason, recompile));
}

/// Emit a special object lookup
fn gen_putspecialobject(jit: &JITState, asm: &mut Assembler, function: &Function, value_type: SpecialObjectType, state: &FrameState) -> Opnd {
    // rb_vm_get_special_object for CBASE/CONST_BASE can call rb_singleton_class,
    // which allocates (may trigger GC) and can raise TypeError on non-class
    // receivers (e.g. `123.instance_eval { Const = 1 }`). Treat as non-leaf so
    // the PC is saved for GC and stack/locals are spilled for rescue.
    gen_prepare_non_leaf_call(jit, asm, function, state);

    // Get the EP of the current CFP and load it into a register
    let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
    let ep_reg = asm.load(ep_opnd);

    asm_ccall!(asm, rb_vm_get_special_object, ep_reg, Opnd::UImm(u64::from(value_type)))
}

fn gen_getspecial_symbol(asm: &mut Assembler, symbol_type: SpecialBackrefSymbol, state: &FrameState) -> Opnd {
    // rb_backref_get reaches rb_vm_svar_lep, which calls CFP_PC/CFP_ISEQ on the
    // current frame, so the PC must be saved before the call.
    gen_prepare_leaf_call_with_gc(asm, state);

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
    // rb_backref_get reaches rb_vm_svar_lep, which calls CFP_PC/CFP_ISEQ on the
    // current frame, so the PC must be saved before the call.
    gen_prepare_leaf_call_with_gc(asm, state);

    // Fetch the N-th match from the last backref based on type shifted by 1
    let backref = asm_ccall!(asm, rb_backref_get,);

    asm_ccall!(asm, rb_reg_nth_match, Opnd::Imm((nth >> 1).try_into().unwrap()), backref)
}

fn gen_check_interrupts(jit: &mut JITState, asm: &mut Assembler, function: &Function, state: &FrameState) {
    // Check for interrupts
    // see RUBY_VM_CHECK_INTS(ec) macro
    asm_comment!(asm, "RUBY_VM_CHECK_INTS(ec)");
    // Not checking interrupt_mask since it's zero outside finalize_deferred_heap_pages,
    // signal_exec, or rb_postponed_job_flush.
    let interrupt_flag = asm.load(Opnd::mem(32, EC, RUBY_OFFSET_EC_INTERRUPT_FLAG));
    asm.test(interrupt_flag, interrupt_flag);
    asm.jnz(jit, side_exit(jit, function, state, SideExitReason::Interrupt));
}

fn gen_hash_dup(asm: &mut Assembler, val: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_hash_resurrect, val)
}

fn gen_hash_aref(jit: &mut JITState, asm: &mut Assembler, function: &Function, hash: Opnd, key: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_hash_aref, hash, key)
}

fn gen_hash_aset(jit: &mut JITState, asm: &mut Assembler, function: &Function, hash: Opnd, key: Opnd, val: Opnd, state: &FrameState) {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_hash_aset, hash, key, val);
}

fn gen_array_push(asm: &mut Assembler, array: Opnd, val: Opnd, state: &FrameState) {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_ary_push, array, val);
}

fn gen_to_new_array(jit: &mut JITState, asm: &mut Assembler, function: &Function, val: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_vm_splat_array, Opnd::Value(Qtrue), val)
}

fn gen_to_array(jit: &mut JITState, asm: &mut Assembler, function: &Function, val: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_vm_splat_array, Opnd::Value(Qfalse), val)
}

fn gen_defined_ivar(asm: &mut Assembler, self_val: Opnd, id: ID, pushval: VALUE) -> lir::Opnd {
    asm_ccall!(asm, rb_zjit_defined_ivar, self_val, id.0.into(), Opnd::Value(pushval))
}

fn gen_checkmatch(jit: &JITState, asm: &mut Assembler, function: &Function, target: Opnd, pattern: Opnd, flag: u32, state: &FrameState) -> lir::Opnd {
    // rb_vm_check_match is not leaf unless flag is VM_CHECKMATCH_TYPE_WHEN.
    // See also: leafness_of_checkmatch() and check_match()
    if flag != VM_CHECKMATCH_TYPE_WHEN {
        gen_prepare_non_leaf_call(jit, asm, function, state);
    }

    unsafe extern "C" {
        fn rb_vm_check_match(ec: EcPtr, target: VALUE, pattern: VALUE, flag: u32) -> VALUE;
    }

    asm_ccall!(asm, rb_vm_check_match, EC, target, pattern, flag.into())
}

fn gen_array_extend(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: Opnd, right: Opnd, state: &FrameState) {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_ary_concat, left, right);
}

fn gen_load_pc(asm: &mut Assembler) -> Opnd {
    asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC))
}

fn gen_load_ec() -> Opnd {
    EC
}

fn gen_load_sp() -> Opnd {
    SP
}

fn gen_load_self(asm: &mut Assembler) -> Opnd {
    asm.load(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SELF))
}

fn gen_load_field(asm: &mut Assembler, recv: Opnd, id: FieldName, offset: i32, num_bits: u8) -> Opnd {
    gen_incr_counter(asm, Counter::load_field_count);
    asm_comment!(asm, "Load field id={id} offset={offset}");
    let recv = asm.load_mem(recv);
    asm.load(Opnd::mem(num_bits, recv, offset))
}

fn gen_store_field(asm: &mut Assembler, recv: Opnd, id: FieldName, offset: i32, val: Opnd, num_bits: u8) {
    gen_incr_counter(asm, Counter::store_field_count);
    asm_comment!(asm, "Store field id={id} offset={offset}");
    let recv = asm.load_mem(recv);
    asm.store(Opnd::mem(num_bits, recv, offset), val);
}

fn gen_write_barrier(jit: &mut JITState, asm: &mut Assembler, recv: Opnd, val: Opnd, val_type: Type) {
    // See RB_OBJ_WRITE/rb_obj_write: it's just assignment and rb_obj_written().
    // rb_obj_written() does: if (!RB_SPECIAL_CONST_P(val)) { rb_gc_writebarrier(recv, val); }
    if !val_type.is_immediate() {
        asm_comment!(asm, "Write barrier");
        let recv = asm.load_mem(recv);

        // Create a result block that all paths converge to
        let hir_block_id = asm.current_block().hir_block_id;
        let rpo_idx = asm.current_block().rpo_index;
        let result_block = asm.new_block(hir_block_id, false, rpo_idx);
        let result_edge = Target::Block(Box::new(lir::BranchEdge { target: result_block, args: vec![] }));

        // If non-false immediate, don't fire write barrier
        asm.test(val, Opnd::UImm(RUBY_IMMEDIATE_MASK as u64));
        asm.jnz(jit, result_edge.clone());

        // If false, don't fire write barrier
        asm.cmp(val, Qfalse.into());
        asm.je(jit, result_edge.clone());

        // Heap object; fire the write barrier
        asm_ccall!(asm, rb_gc_writebarrier, recv, val);
        asm.jmp(result_edge);

        // Join block
        asm.set_current_block(result_block);
        let label = jit.get_label(asm, result_block, hir_block_id);
        asm.write_label(label);
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

fn gen_const_attr_index_t(val: attr_index_t) -> lir::Opnd {
    Opnd::UImm(val as u64)
}

/// Compile a basic block argument
fn gen_param(asm: &mut Assembler, _idx: usize) -> lir::Opnd {
    let vreg = asm.new_block_param(VALUE_BITS);
    asm.current_block().add_parameter(vreg);
    vreg
}

fn gen_trace_fallback(asm: &mut Assembler, reason: &str) {
    if !get_option!(trace_fallbacks) {
        return;
    }
    let reason_cstr = std::ffi::CString::new(reason.to_string())
        .unwrap_or_else(|_| std::ffi::CString::new("unknown").unwrap());
    let reason_ptr = reason_cstr.into_raw() as *const u8;
    use crate::state::rb_zjit_record_fallback_stack;
    asm_ccall!(asm, rb_zjit_record_fallback_stack, Opnd::const_ptr(reason_ptr));
}

fn gen_trace_send_fallback(asm: &mut Assembler, reason: &SendFallbackReason) {
    if !get_option!(trace_fallbacks) {
        return;
    }
    gen_trace_fallback(asm, &format!("{reason}"));
}

/// Compile a dynamic dispatch with block
fn gen_send(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cd: *const rb_call_data,
    blockiseq: IseqPtr,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);
    gen_trace_send_fallback(asm, &reason);

    gen_prepare_fallback_call(jit, asm, function, state);
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
    function: &Function,
    cd: *const rb_call_data,
    blockiseq: IseqPtr,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);
    gen_trace_send_fallback(asm, &reason);

    gen_prepare_fallback_call(jit, asm, function, state);

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
    function: &Function,
    cd: *const rb_call_data,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);
    gen_trace_send_fallback(asm, &reason);

    gen_prepare_fallback_call(jit, asm, function, state);
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

/// Push an interpreter frame for an inlined callee. This is the same as the frame push
/// portion of gen_send_iseq_direct, but without the native call to the callee. Control
/// falls through to the next instruction (the inlined callee body).
fn gen_push_inline_frame(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cme: *const rb_callable_method_entry_t,
    iseq: IseqPtr,
    recv: Opnd,
    args: Vec<Opnd>,
    state: &FrameState,
    blockiseq: Option<IseqPtr>,
) {
    let local_size = unsafe { get_iseq_body_local_table_size(iseq) }.to_usize();
    let stack_growth = state.stack_size() + local_size + unsafe { get_iseq_body_stack_max(iseq) }.to_usize();
    gen_stack_overflow_check(jit, asm, function, state, stack_growth);

    // Save cfp->pc and cfp->sp for the caller frame.
    // Cannot use gen_prepare_non_leaf_call because we need special SP math.
    let stack_size = state.stack().len() - args.len() - 1; // -1 for receiver
    gen_write_jit_frame(asm, state, 0);
    gen_save_sp(asm, stack_size);

    gen_spill_locals(jit, asm, state);

    // This mirrors vm_caller_setup_arg_block() for the `blockiseq != NULL` case.
    // The HIR specialization guards ensure we will only reach here for literal blocks,
    // not &block forwarding, &:foo, etc. These are rejected in `type_specialize` by
    // `unspecializable_call_type`.
    let block_handler = blockiseq.map(|b| gen_block_handler_specval(asm, b));

    let callee_is_bmethod = VM_METHOD_TYPE_BMETHOD == unsafe { get_cme_def_type(cme) };

    let (frame_type, specval) = if callee_is_bmethod {
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
        let specval = block_handler.unwrap_or_else(|| VM_BLOCK_HANDLER_NONE.into());
        (VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL, specval)
    };

    gen_push_frame(asm, args.len(), state, ControlFrame {
        recv,
        iseq: Some(iseq),
        cme,
        frame_type,
        specval,
        write_block_code: iseq_may_write_block_code(iseq),
    });

    // Publish the inlined callee's entry JITFrame before the inlined body runs.
    // Frame walking functions such as rb_profile_frames can inspect the new
    // CFP between this frame push and the first inlined gen_write_jit_frame, so
    // cfp->jit_return must already reference a valid JITFrame slot. Leaving it
    // stale or uninitialized is unsafe because CFP_ZJIT_FRAME has no independent
    // way to tell whether it points at a valid JITFrame slot.
    //
    // We install a pre-baked JITFrame for the callee's entry by writing its address into
    // the callee's own JITFrame slot and pointing the callee's cfp->jit_return at that
    // slot, matching the protocol established by gen_entry_point + gen_write_jit_frame.
    // The callee runs one level deeper than the caller, so it uses the slot for
    // `state.depth + 1` (state is the caller's FrameState). Giving each inlining depth a
    // distinct slot keeps the caller's and callee's cfp->jit_return from aliasing the same
    // native stack location, which would otherwise make rb_zjit_materialize_frames copy
    // one frame's PC/ISEQ into every aliased CFP on the chain. CFP_ZJIT_FRAME in zjit.h
    // reads the JITFrame via ((VALUE *)cfp->jit_return)[-1], so the field must be the
    // slot's address, not the JITFrame pointer itself. Once the inlined body runs its
    // first gen_write_jit_frame, that call overwrites the same slot with a JITFrame
    // carrying the current PC, just as the non-inlined path does.
    //
    // cfp->sp is left stale at frame push, matching the non-inlined gen_push_frame, which
    // also skips the cfp->sp write for ISEQ frames. The first gen_save_sp call inside the
    // inlined body (reached via gen_prepare_call_with_gc or gen_prepare_leaf_call_with_gc
    // before any GC-triggering operation) installs the correct value. Side-exits write
    // cfp->sp themselves via compile_exit_save_state in lir.rs before returning Qundef.
    fn cfp_opnd(offset: i32) -> Opnd {
        Opnd::mem(64, CFP, offset - (RUBY_SIZEOF_CONTROL_FRAME as i32))
    }
    let callee_depth = state.depth + 1;
    let callee_entry_pc = unsafe { rb_iseq_pc_at_idx(iseq, 0) };
    let callee_entry_frame = JITFrame::new_iseq(callee_entry_pc, iseq, 0);
    asm_comment!(asm, "install entry JITFrame for inlined callee");
    asm.mov(Opnd::mem(64, NATIVE_BASE_PTR, jit_frame_slot_offset(callee_depth)), Opnd::const_ptr(callee_entry_frame));
    let callee_jit_return = cfp_jit_return_for_depth(asm, callee_depth);
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_JIT_RETURN), callee_jit_return);

    // The callee's hidden `kw_bits` local does not need a runtime store here:
    // the inliner aliases the local to a `Const::Value` carrying the
    // compile-time bitmask, so `checkkeyword` lowers to a constant
    // `FixnumBitCheck` rather than a memory load. On a side exit out of the
    // inlined body, FrameState materialization writes the local back to the
    // callee frame from that constant, and on the no-side-exit path nothing
    // reads the slot before `gen_pop_lightweight_frame` tears down the frame.
    // (The non-inlined `gen_send_iseq_direct` path still emits its own store
    // because the callee's separate JIT entry reads it from memory.)

    let sp_offset = (state.stack().len() + local_size - args.len() + VM_ENV_DATA_SIZE.to_usize()) * SIZEOF_VALUE;
    asm_comment!(asm, "switch to inlined callee SP");
    let new_sp = asm.add(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to inlined callee CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP as i32), CFP);
}

/// Pop the interpreter frame for an inlined callee, restoring the caller's SP and CFP.
fn gen_pop_inline_frame(
    asm: &mut Assembler,
    iseq: IseqPtr,
    argc: usize,
    state: &FrameState,
) {
    let local_size = unsafe { get_iseq_body_local_table_size(iseq) }.to_usize();
    let sp_offset = (state.stack().len() + local_size - argc + VM_ENV_DATA_SIZE.to_usize()) * SIZEOF_VALUE;

    asm_comment!(asm, "restore caller SP after inline");
    asm.sub_into(SP, sp_offset.into());

    asm_comment!(asm, "restore caller CFP after inline");
    asm.add_into(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP as i32), CFP);
}

/// Compile a direct call to an ISEQ method.
/// If `block_handler` is provided, it's used as the specval for the new frame (for forwarding blocks).
/// Otherwise, `VM_BLOCK_HANDLER_NONE` is used.
fn gen_send_iseq_direct(
    cb: &mut CodeBlock,
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cme: *const rb_callable_method_entry_t,
    iseq: IseqPtr,
    recv: Opnd,
    args: Vec<Opnd>,
    kw_bits: u32,
    jit_entry_idx: u16,
    state: &FrameState,
    block: Option<BlockHandler>,
) -> lir::Opnd {
    gen_incr_counter(asm, Counter::iseq_optimized_send_count);

    let local_size = unsafe { get_iseq_body_local_table_size(iseq) }.to_usize();
    let stack_growth = state.stack_size() + local_size + unsafe { get_iseq_body_stack_max(iseq) }.to_usize();
    gen_stack_overflow_check(jit, asm, function, state, stack_growth);

    // Save cfp->pc and cfp->sp for the caller frame
    // Can't use gen_prepare_non_leaf_call because we need special SP math.
    let stack_size = state.stack().len() - args.len() - 1; // -1 for receiver
    let stack_map = build_stack_map(jit, function, &state.with_stack_size(stack_size));
    let jit_frame = gen_write_jit_frame(asm, state, stack_map.len());
    gen_save_sp(asm, stack_size);

    gen_spill_locals(jit, asm, state);
    asm.stack_map(stack_map, jit_frame, state.depth);

    // This mirrors vm_caller_setup_arg_block() in for the `blockiseq != NULL` case.
    // The HIR specialization guards ensure we will only reach here for literal blocks,
    // not &block forwarding, &:foo, etc. Thise are rejected in `type_specialize` by
    // `unspecializable_call_type`.
    let block_handler = block.map(|bh| match bh { BlockHandler::BlockIseq(b) => gen_block_handler_specval(asm, b), BlockHandler::BlockArg => unreachable!("BlockArg in gen_send_iseq_direct") });

    let callee_is_bmethod = VM_METHOD_TYPE_BMETHOD == unsafe { get_cme_def_type(cme) };

    let (frame_type, specval) = if callee_is_bmethod {
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
        let specval = block_handler.unwrap_or_else(|| VM_BLOCK_HANDLER_NONE.into());
        (VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL, specval)
    };

    // Set up the new frame
    // TODO: Lazily materialize caller frames on side exits or when needed
    gen_push_frame(asm, args.len(), state, ControlFrame {
        recv,
        iseq: Some(iseq),
        cme,
        frame_type,
        specval,
        write_block_code: iseq_may_write_block_code(iseq),
    });

    // Write "keyword_bits" to the callee's frame if the callee accepts keywords.
    // This is a synthetic local/parameter that the callee reads via checkkeyword to determine
    // which optional keyword arguments need their defaults evaluated.
    // We write this to the local table slot at bits_start so that:
    // 1. The interpreter can read it via checkkeyword if we side-exit
    // 2. The JIT entry can read it from the callee frame slot
    if unsafe { rb_get_iseq_flags_has_kw(iseq) } {
        let keyword = unsafe { rb_get_iseq_body_param_keyword(iseq) };
        let bits_start = unsafe { (*keyword).bits_start } as usize;
        let unspecified_bits = VALUE::fixnum_from_usize(kw_bits as usize);
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
    asm.mov(CFP, new_cfp); // will be published at `ec->cfp` after callee's entrypoint

    let params = unsafe { iseq.params() };

    // For &block, the JIT entrypoint expects the block_handler as an argument
    // This HIR param is not actually used, things read from specval from the VM frame today.
    // TODO: Remove unused param from HIR, or pass specval through c_args.
    // See https://github.com/ruby/ruby/pull/15911#discussion_r2710544982
    let needs_block = params.flags.has_block() != 0;

    // Set up arguments
    let mut c_args = Vec::with_capacity({
        // This is a heuristic to avoid re-allocation, not necessary for correctness
        1 /* recv */ + args.len() + if needs_block { 1 } else { 0 }
    });
    c_args.push(recv);
    c_args.extend(&args);
    if needs_block {
        if callee_is_bmethod {
            // For bmethods, specval is the captured EP, not the block handler.
            // The block param needs nil (no block) or a Proc value.
            assert!(block_handler.is_none(), "at the moment, HIR builder never emits a direct send for a to-bmethod send-with-literal-block");
            c_args.push(Qnil.into());
        } else {
            c_args.push(specval);
        }
    }

    // Make a method call. The target address will be rewritten once compiled.
    let iseq_call = IseqCall::new(iseq, jit_entry_idx, args.len().try_into().expect("checked in HIR"));
    let dummy_ptr = cb.get_write_ptr().raw_ptr(cb);
    jit.iseq_calls.push(iseq_call.clone());
    let ret = asm.ccall_with_iseq_call(dummy_ptr, c_args, &iseq_call);

    // If a callee side-exits, i.e. returns Qundef, propagate the return value to the caller.
    // The caller will side-exit the callee into the interpreter.
    // TODO: Let side exit code pop all JIT frames to optimize away this cmp + je.
    asm_comment!(asm, "side-exit if callee side-exits");
    asm.cmp(ret, Qundef.into());
    // Restore the C stack pointer on exit
    asm.je(jit, ZJITState::get_exit_trampoline().into());

    asm_comment!(asm, "restore SP register for the caller");
    let new_sp = asm.sub(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    ret
}

/// Compile for invokeblock
fn gen_invokeblock(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cd: *const rb_call_data,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);
    gen_trace_send_fallback(asm, &reason);

    gen_prepare_fallback_call(jit, asm, function, state);

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

/// Compile invokeblock for IFUNC block handlers.
/// Calls rb_vm_yield_with_cfunc directly.
fn gen_invokeblock_ifunc(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cd: *const rb_call_data,
    block_handler: Opnd,
    args: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    let _ = cd; // cd is not needed for the direct call

    gen_prepare_fallback_call(jit, asm, function, state);

    // Push args to memory so we can pass argv pointer
    let argv_ptr = gen_push_opnds(jit, asm, &args);

    // Untag the block handler to get the captured block pointer
    // captured = block_handler & ~0x3
    asm_comment!(asm, "untag block handler to get captured block");
    let captured = asm.and(block_handler, Opnd::Imm(!0x3i64));

    asm_comment!(asm, "call rb_vm_yield_with_cfunc");
    unsafe extern "C" {
        fn rb_vm_yield_with_cfunc(
            ec: EcPtr,
            captured: VALUE,
            argc: i32,
            argv: *const VALUE,
        ) -> VALUE;
    }
    asm_ccall!(asm, rb_vm_yield_with_cfunc, EC, captured, (args.len() as i64).into(), argv_ptr)
}

fn gen_invokeproc(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    recv: Opnd,
    args: Vec<Opnd>,
    kw_splat: bool,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_fallback_call(jit, asm, function, state);

    asm_comment!(asm, "call invokeproc");

    let argv_ptr = gen_push_opnds(jit, asm, &args);
    let kw_splat_opnd = Opnd::Imm(i64::from(kw_splat));
    asm_ccall!(
        asm,
        rb_optimized_call,
        recv,
        EC,
        args.len().into(),
        argv_ptr,
        kw_splat_opnd,
        VM_BLOCK_HANDLER_NONE.into()
    )
}

/// Compile `yield`. Inlines the block ISEQ frame like `invokeblock` instead of calling vm_yield.
/// The block handler is read from the enclosing frame's LEP (`level` hops up), guarded to be the
/// comptime-known ISEQ block, and its frame is pushed here before jumping to the block's JIT entry.
/// On a guard miss, side-exit and recompile. The HIR gate ensures the block is simple + lead-only
/// + non-throwing.
fn gen_invoke_block_iseq_direct(
    cb: &mut CodeBlock,
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    block_iseq: IseqPtr,
    captured: Opnd,
    args: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    gen_incr_counter(asm, Counter::block_iseq_direct_optimized_send_count);

    let local_size = unsafe { get_iseq_body_local_table_size(block_iseq) }.to_usize();
    let stack_growth = state.stack_size() + local_size + unsafe { get_iseq_body_stack_max(block_iseq) }.to_usize();
    gen_stack_overflow_check(jit, asm, function, state, stack_growth);

    // `captured` is the guarded `struct rb_captured_block *` (block handler with the ISEQ tag
    // masked off). The HIR builder loaded it from the LEP and guarded the tag + iseq identity.
    // TODO: During inlining, captured->self can be known. It should be put into HIR.
    let captured_self = asm.load(Opnd::mem(64, captured, 0)); // captured->self
    // TODO: During inlining, captured->ep can sometimes also be known.
    let captured_ep = asm.load(Opnd::mem(64, captured, SIZEOF_VALUE_I32)); // captured->ep
    // specval = VM_GUARDED_PREV_EP(captured->ep) = captured->ep | 0x01
    let specval = asm.or(captured_ep, Opnd::Imm(0x1));

    let stack_size = state.stack().len() - args.len();
    let stack_map = build_stack_map(jit, function, &state.with_stack_size(stack_size));
    let jit_frame = gen_write_jit_frame(asm, state, stack_map.len());
    gen_save_sp(asm, stack_size);

    gen_spill_locals(jit, asm, state);
    asm.stack_map(stack_map, jit_frame, state.depth);

    gen_push_frame(asm, args.len(), state, ControlFrame {
        recv: captured_self,
        iseq: Some(block_iseq),
        cme: std::ptr::null(),
        frame_type: VM_FRAME_MAGIC_BLOCK,
        specval,
        write_block_code: iseq_may_write_block_code(block_iseq),
    });

    asm_comment!(asm, "switch to new SP register");
    let sp_offset = (stack_size + local_size + VM_ENV_DATA_SIZE.to_usize()) * SIZEOF_VALUE;
    let new_sp = asm.add(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    asm_comment!(asm, "switch to new CFP");
    let new_cfp = asm.sub(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, new_cfp);
    asm.store(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // JIT-to-JIT convention: self as c_args[0], then positional args. The block is
    // gated to simple + lead-only + exact arity, so there are no optionals/kw/block.
    let mut c_args = Vec::with_capacity(1 + args.len());
    c_args.push(captured_self);
    c_args.extend(&args);

    let iseq_call = IseqCall::new(block_iseq, 0, args.len().try_into().expect("checked in HIR"));
    let dummy_ptr = cb.get_write_ptr().raw_ptr(cb);
    jit.iseq_calls.push(iseq_call.clone());
    let ret = asm.ccall_with_iseq_call(dummy_ptr, c_args, &iseq_call);

    // If the callee side-exits (returns Qundef), propagate to the caller.
    asm_comment!(asm, "side-exit if callee side-exits");
    asm.cmp(ret, Qundef.into());
    asm.je(jit, ZJITState::get_exit_trampoline().into());

    asm_comment!(asm, "restore SP register for the caller");
    let new_sp = asm.sub(SP, sp_offset.into());
    asm.mov(SP, new_sp);

    ret
}

/// Compile a dynamic dispatch for `super`
fn gen_invokesuper(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cd: *const rb_call_data,
    blockiseq: IseqPtr,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);
    gen_trace_send_fallback(asm, &reason);

    gen_prepare_fallback_call(jit, asm, function, state);
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

/// Compile a dynamic dispatch for `super` with `...`
fn gen_invokesuperforward(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    cd: *const rb_call_data,
    blockiseq: IseqPtr,
    state: &FrameState,
    reason: SendFallbackReason,
) -> lir::Opnd {
    gen_incr_send_fallback_counter(asm, reason);
    gen_trace_send_fallback(asm, &reason);

    gen_prepare_fallback_call(jit, asm, function, state);
    asm_comment!(asm, "call super with dynamic dispatch (forwarding)");
    unsafe extern "C" {
        fn rb_vm_invokesuperforward(ec: EcPtr, cfp: CfpPtr, cd: VALUE, blockiseq: IseqPtr) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_invokesuperforward,
        EC, CFP, Opnd::const_ptr(cd), VALUE::from(blockiseq).into()
    )
}

const STR_INLINE_STORE_MAX_BYTES: usize = 128;

/// Compile a string resurrection
fn gen_string_copy(jit: &mut JITState, asm: &mut Assembler, function: &Function, val_id: InsnId, recv: Opnd, chilled: bool, state: &FrameState) -> Opnd {
    // TODO: split rb_ec_str_resurrect into separate functions
    gen_prepare_leaf_call_with_gc(asm, state);

    let Some(src) = function.type_of(val_id).ruby_object() else {
        return asm_ccall!(asm, rb_ec_str_resurrect, EC, recv, (chilled as i64).into());
    };

    let slow_path = |asm: &mut Assembler| asm_ccall!(asm, rb_ec_str_resurrect, EC, Opnd::Value(src), (chilled as i64).into());

    let mut alloc_size: usize = 0;
    let mut flags: VALUE = VALUE(0);
    let mut len: c_long = 0;
    let mut byte_size: usize = 0;
    let has_fastpath = unsafe {
        rb_zjit_str_resurrect_fastpath(src, chilled, &mut alloc_size, &mut flags, &mut len, &mut byte_size)
    };
    if !has_fastpath {
        return slow_path(asm);
    }

    let full_flags = flags.as_u64();
    let klass = unsafe { rb_cString };

    // Because inline stores are 8 bytes, storing large embedded strings would
    // generate a large number of stores (!125 for a string in the 1024b size
    // pool). Here we choose an arbitrary threshold (128 bytes, or 16 stores),
    // above which we'll emit a C call to memcpy instead of multiple stores.
    if byte_size > STR_INLINE_STORE_MAX_BYTES {
        return gc_fastpath::gc_fastpath_new_obj(jit, asm, alloc_size, full_flags, klass,
            &|asm, obj| {
                asm.store(Opnd::mem(VALUE_BITS, obj, RUBY_OFFSET_RSTRING_LEN), Opnd::Imm(len));
                let src_obj = asm.load(Opnd::Value(src));
                let src_ptr = asm.lea(Opnd::mem(64, src_obj, RUBY_OFFSET_RSTRING_AS_ARY));
                let dst_ptr = asm.lea(Opnd::mem(64, obj, RUBY_OFFSET_RSTRING_AS_ARY));
                asm.ccall(memcpy as *const u8, vec![dst_ptr, src_ptr, Opnd::UImm(byte_size as u64)]);
            },
            slow_path);
    }

    // Pre-process string data into 8 byte chunks and take care of padding
    // outside the loop, so we can keep the complexity out of the fast path
    // loop.
    let padded_size = byte_size.next_multiple_of(8);
    let Some(src_bytes) = (unsafe { src.as_rstring_byte_slice() }) else {
        return slow_path(asm);
    };
    debug_assert_eq!(src_bytes.len(), len as usize);
    let mut string_bytes = vec![0u8; padded_size];
    string_bytes[..src_bytes.len()].copy_from_slice(src_bytes);

    gc_fastpath::gc_fastpath_new_obj(jit, asm, alloc_size, full_flags, klass,
        &|asm, obj| {
            asm.store(Opnd::mem(VALUE_BITS, obj, RUBY_OFFSET_RSTRING_LEN), Opnd::Imm(len));
            for (i, chunk) in string_bytes.chunks_exact(8).enumerate() {
                let word = u64::from_le_bytes(chunk.try_into().unwrap());
                let offset = RUBY_OFFSET_RSTRING_AS_ARY + (i as i32) * 8;
                asm.store(Opnd::mem(64, obj, offset), Opnd::UImm(word));
            }
        },
        slow_path)
}

unsafe extern "C" {
    fn memcpy(dst: *mut c_void, src: *const c_void, n: usize) -> *mut c_void;
}

fn gen_string_equal(asm: &mut Assembler, left: Opnd, right: Opnd) -> lir::Opnd {
    asm_ccall!(asm, rb_yarv_str_eql_internal, left, right)
}

/// Compile an array duplication instruction
fn gen_array_dup(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    val_id: InsnId,
    val: lir::Opnd,
    state: &FrameState,
) -> lir::Opnd {
    // duparray resurrects a frozen literal array baked into the ISEQ, so its elements are known
    // here. When the resurrected copy would be embedded, bump-allocate it inline and store the
    // elements directly; the fresh object is young and white, so those writes need no write
    // barrier (elements may be heap objects).
    if let Some(src) = function.type_of(val_id).ruby_object() {
        let mut alloc_size: usize = 0;
        let mut flags = VALUE(0);
        let mut len: std::os::raw::c_long = 0;
        if unsafe { rb_zjit_array_dup_can_fastpath(src, &mut alloc_size, &mut flags, &mut len) } {
            let klass = unsafe { rb_cArray };
            return gc_fastpath::gc_fastpath_new_obj(jit, asm, alloc_size, flags.as_u64(), klass, &|asm, obj| {
                for i in 0..len {
                    let elem = unsafe { rb_ary_entry(src, i) };
                    let offset = RUBY_OFFSET_RARRAY_AS_ARY + (i as i32) * SIZEOF_VALUE_I32;
                    asm.store(Opnd::mem(VALUE_BITS, obj, offset), Opnd::Value(elem));
                }
            },
            |asm| {
                gen_prepare_leaf_call_with_gc(asm, state);
                asm_ccall!(asm, rb_ary_resurrect, val)
            });
        }
    }

    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_ary_resurrect, val)
}

/// Compile a new array instruction
fn gen_new_array(
    jit: &mut JITState,
    asm: &mut Assembler,
    elements: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

    let num: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

    if !elements.is_empty() {
        let argv = gen_push_opnds(jit, asm, &elements);
        return asm_ccall!(asm, rb_ec_ary_new_from_values, EC, num.into(), argv);
    }

    let alloc_size = std::mem::size_of::<RArray>();

    let flags = (RUBY_T_ARRAY as u64) | (RARRAY_EMBED_FLAG as u64);
    let klass = unsafe { rb_cArray };

    gc_fastpath::gc_fastpath_new_obj(jit, asm, alloc_size, flags, klass, &|_asm, _obj| {}, |asm| {
        asm_ccall!(asm, rb_ec_ary_new_from_values, EC, 0i64.into(), Opnd::UImm(0))
    })
}

/// Adjust potentially-negative index by the given length, returning the adjusted index. If still negative,
/// return a negative number, which indicates the index is still out-of-bounds.
fn gen_adjust_bounds(asm: &mut Assembler, index: Opnd, length: Opnd) -> lir::Opnd {
    let adjusted = asm.add(index, length);
    asm.test(index, index);
    asm.csel_l(adjusted, index)
}

/// Compile array access (`array[index]`)
fn gen_array_aref(
    asm: &mut Assembler,
    array: Opnd,
    index: Opnd,
) -> lir::Opnd {
    let unboxed_idx = asm.load_mem(index);
    let array = asm.load_mem(array);
    let array_ptr = gen_array_ptr(asm, array);
    let elem_offset = asm.lshift(unboxed_idx, Opnd::UImm(SIZEOF_VALUE.trailing_zeros() as u64));
    let elem_ptr = asm.add(array_ptr, elem_offset);
    asm.load(Opnd::mem(VALUE_BITS, elem_ptr, 0))
}

fn gen_array_aset(
    asm: &mut Assembler,
    array: Opnd,
    index: Opnd,
    val: Opnd,
) {
    let unboxed_idx = asm.load_mem(index);
    let array = asm.load_mem(array);
    let array_ptr = gen_array_ptr(asm, array);
    let elem_offset = asm.lshift(unboxed_idx, Opnd::UImm(SIZEOF_VALUE.trailing_zeros() as u64));
    let elem_ptr = asm.add(array_ptr, elem_offset);
    asm.store(Opnd::mem(VALUE_BITS, elem_ptr, 0), val);
}

fn gen_array_pop(asm: &mut Assembler, array: Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_ary_pop, array)
}

fn gen_array_length(asm: &mut Assembler, array: Opnd) -> lir::Opnd {
    let array = asm.load_mem(array);
    let flags = Opnd::mem(VALUE_BITS, array, RUBY_OFFSET_RBASIC_FLAGS);
    let embedded_len = asm.and(flags, (RARRAY_EMBED_LEN_MASK as u64).into());
    let embedded_len = asm.rshift(embedded_len, (RARRAY_EMBED_LEN_SHIFT as u64).into());
    // cmov between the embedded length and heap length depending on the embed flag
    asm.test(flags, (RARRAY_EMBED_FLAG as u64).into());
    let heap_len = Opnd::mem(c_long::BITS as u8, array, RUBY_OFFSET_RARRAY_AS_HEAP_LEN);
    asm.csel_nz(embedded_len, heap_len)
}

fn gen_array_ptr(asm: &mut Assembler, array: Opnd) -> lir::Opnd {
    let flags = Opnd::mem(VALUE_BITS, array, RUBY_OFFSET_RBASIC_FLAGS);
    asm.test(flags, (RARRAY_EMBED_FLAG as u64).into());
    let heap_ptr = Opnd::mem(usize::BITS as u8, array, RUBY_OFFSET_RARRAY_AS_HEAP_PTR);
    let embedded_ptr = asm.lea(Opnd::mem(VALUE_BITS, array, RUBY_OFFSET_RARRAY_AS_ARY));
    asm.csel_nz(embedded_ptr, heap_ptr)
}

/// Compile opt_newarray_hash - create a hash from array elements
fn gen_opt_newarray_hash(
    jit: &JITState,
    asm: &mut Assembler,
    function: &Function,
    elements: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    // `Array#hash` will hash the elements of the array.
    gen_prepare_fallback_call(jit, asm, function, state);

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

/// Compile ArrayMax - find the maximum element among array elements
fn gen_array_max(
    jit: &JITState,
    asm: &mut Assembler,
    function: &Function,
    elements: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_fallback_call(jit, asm, function, state);

    let array_len: u32 = elements.len().try_into().expect("Unable to fit length of elements into u32");

    // After gen_prepare_non_leaf_call, the elements are spilled to the Ruby stack.
    // Get a pointer to the first element on the Ruby stack.
    let stack_bottom = state.stack().len() - elements.len();
    let elements_ptr = asm.lea(Opnd::mem(VALUE_BITS, SP, stack_bottom as i32 * SIZEOF_VALUE_I32));

    unsafe extern "C" {
        fn rb_vm_opt_newarray_max(ec: EcPtr, num: u32, elts: *const VALUE) -> VALUE;
    }

    asm.ccall(
        rb_vm_opt_newarray_max as *const u8,
        vec![EC, array_len.into(), elements_ptr],
    )
}

/// Find the minimum element among array elements
fn gen_array_min(
    jit: &JITState,
    asm: &mut Assembler,
    function: &Function,
    elements: Vec<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_fallback_call(jit, asm, function, state);

    let array_len: u32 = elements.len().try_into().expect("Unable to fit length of elements into u32");

    // After gen_prepare_non_leaf_call, the elements are spilled to the Ruby stack.
    // Get a pointer to the first element on the Ruby stack.
    let stack_bottom = state.stack().len() - elements.len();
    let elements_ptr = asm.lea(Opnd::mem(VALUE_BITS, SP, stack_bottom as i32 * SIZEOF_VALUE_I32));

    unsafe extern "C" {
        fn rb_vm_opt_newarray_min(ec: EcPtr, num: u32, elts: *const VALUE) -> VALUE;
    }

    asm.ccall(
        rb_vm_opt_newarray_min as *const u8,
        vec![EC, array_len.into(), elements_ptr],
    )
}

fn gen_array_include(
    jit: &JITState,
    asm: &mut Assembler,
    function: &Function,
    elements: Vec<Opnd>,
    target: Opnd,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_fallback_call(jit, asm, function, state);

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
    function: &Function,
    elements: Vec<Opnd>,
    fmt: Opnd,
    buffer: Option<Opnd>,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_fallback_call(jit, asm, function, state);

    let array_len: c_long = elements.len().try_into().expect("Unable to fit length of elements into c_long");

    // After gen_prepare_non_leaf_call, the elements are spilled to the Ruby stack.
    // The elements are at the bottom of the virtual stack, followed by the fmt, and optionally the buffer.
    // Get a pointer to the first element on the Ruby stack.
    let stack_bottom = if buffer.is_some() {
        state.stack().len() - elements.len() - 2
    } else {
        state.stack().len() - elements.len() - 1
    };
    let elements_ptr = asm.lea(Opnd::mem(64, SP, stack_bottom as i32 * SIZEOF_VALUE_I32));

    unsafe extern "C" {
        fn rb_vm_opt_newarray_pack_buffer(ec: EcPtr, num: c_long, elts: *const VALUE, fmt: VALUE, buffer: VALUE) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_opt_newarray_pack_buffer,
        EC, array_len.into(), elements_ptr, fmt, buffer.unwrap_or_else(|| Qundef.into())
    )
}

fn gen_dup_array_include(
    jit: &JITState,
    asm: &mut Assembler,
    function: &Function,
    ary: VALUE,
    target: Opnd,
    state: &FrameState,
) -> lir::Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);

    unsafe extern "C" {
        fn rb_vm_opt_duparray_include_p(ec: EcPtr, ary: VALUE, target: VALUE) -> VALUE;
    }
    asm_ccall!(
        asm,
        rb_vm_opt_duparray_include_p,
        EC, ary.into(), target
    )
}

fn gen_is_a(jit: &mut JITState, asm: &mut Assembler, obj: Opnd, class: Opnd) -> lir::Opnd {
    let builtin_type = match class {
        Opnd::Value(value) if value == unsafe { rb_cString } => Some(RUBY_T_STRING),
        Opnd::Value(value) if value == unsafe { rb_cArray } => Some(RUBY_T_ARRAY),
        Opnd::Value(value) if value == unsafe { rb_cHash } => Some(RUBY_T_HASH),
        _ => None
    };

    if let Some(builtin_type) = builtin_type {
        asm_comment!(asm, "IsA by matching builtin type");
        let hir_block_id = asm.current_block().hir_block_id;
        let rpo_idx = asm.current_block().rpo_index;

        // Create a result block that all paths converge to
        let result_block = asm.new_block(hir_block_id, false, rpo_idx);
        let result_edge = |v| Target::Block(Box::new(lir::BranchEdge {
            target: result_block,
            args: vec![v],
        }));

        let val = asm.load_mem(obj);

        // Immediate -> definitely not String/Array/Hash
        asm.test(val, Opnd::UImm(RUBY_IMMEDIATE_MASK as u64));
        asm.jnz(jit, result_edge(Qfalse.into()));

        // Qfalse -> definitely not String/Array/Hash
        asm.cmp(val, Qfalse.into());
        asm.je(jit, result_edge(Qfalse.into()));

        // Heap object -> check builtin type
        let flags = asm.load(Opnd::mem(VALUE_BITS, val, RUBY_OFFSET_RBASIC_FLAGS));
        let obj_builtin_type = asm.and(flags, Opnd::UImm(RUBY_T_MASK as u64));
        asm.cmp(obj_builtin_type, Opnd::UImm(builtin_type as u64));
        let result = asm.csel_e(Qtrue.into(), Qfalse.into());
        asm.jmp(result_edge(result));

        // Result block -- receives the value via block parameter (phi node)
        asm.set_current_block(result_block);
        let label = jit.get_label(asm, result_block, hir_block_id);
        asm.write_label(label);
        let param = asm.new_block_param(VALUE_BITS);
        asm.current_block().add_parameter(param);
        param
    } else {
        asm_ccall!(asm, rb_obj_is_kind_of, obj, class)
    }
}

/// Compile a new hash instruction
fn gen_new_hash(
    jit: &mut JITState,
    asm: &mut Assembler,
    function: &Function,
    elements: Vec<Opnd>,
    sym_keys: bool,
    state: &FrameState,
) -> lir::Opnd {
    if elements.is_empty() {
        gen_prepare_leaf_call_with_gc(asm, state);

        let alloc_size = unsafe { rb_zjit_hash_new_size() };
        let flags = RUBY_T_HASH as u64;
        let klass = unsafe { rb_cHash };

        gc_fastpath::gc_fastpath_new_obj(jit, asm, alloc_size, flags, klass,
            &|asm, hash| {
                asm.store(Opnd::mem(VALUE_BITS, hash, RUBY_OFFSET_RHASH_IFNONE), Qnil.into());
            },
            |asm| {
                asm_ccall!(asm, rb_hash_new,)
            })
    // TODO: we should use effects_of for this (we would need to add it).
    } else if sym_keys {
        // Symbols hash and compare without running Ruby and those operations never raise so
        // the bulk insert is leaf.
        gen_prepare_leaf_call_with_gc(asm, state);

        let num_pairs = elements.len() / 2;
        let hash = if num_pairs <= RUBY_RHASH_AR_TABLE_MAX_SIZE as usize {
            let alloc_size = unsafe { rb_zjit_hash_new_size() };
            let flags = RUBY_T_HASH as u64;
            let klass = unsafe { rb_cHash };

            gc_fastpath::gc_fastpath_new_obj(jit, asm, alloc_size, flags, klass,
                &|asm, hash| {
                    asm.store(Opnd::mem(VALUE_BITS, hash, RUBY_OFFSET_RHASH_IFNONE), Qnil.into());
                },
                |asm| {
                    asm_ccall!(asm, rb_hash_new_with_size, num_pairs.into())
                })
        } else {
            asm_ccall!(asm, rb_hash_new_with_size, num_pairs.into())
        };

        let argv = gen_push_opnds(jit, asm, &elements);
        asm_ccall!(asm, rb_hash_bulk_insert, elements.len().into(), argv, hash);
        hash
    } else {
        gen_prepare_non_leaf_call(jit, asm, function, state);

        let argv = gen_push_opnds(jit, asm, &elements);
        asm_ccall!(asm, rb_hash_new_with_bulk_insert, elements.len().into(), argv)
    }
}

/// Compile a new range instruction
fn gen_new_range(
    jit: &JITState,
    asm: &mut Assembler,
    function: &Function,
    low: lir::Opnd,
    high: lir::Opnd,
    flag: RangeType,
    state: &FrameState,
) -> lir::Opnd {
    // Sometimes calls `low.<=>(high)`
    gen_prepare_non_leaf_call(jit, asm, function, state);

    // Call rb_range_new(low, high, flag)
    asm_ccall!(asm, rb_range_new, low, high, (flag as i32).into())
}

fn gen_new_range_fixnum(
    jit: &mut JITState,
    asm: &mut Assembler,
    low: lir::Opnd,
    high: lir::Opnd,
    flag: RangeType,
    state: &FrameState,
) -> lir::Opnd {
    let mut alloc_size = 0;
    let mut flags = VALUE(0);
    let exclude_end = matches!(flag, RangeType::Exclusive);
    unsafe {
        rb_zjit_range_new_fastpath(exclude_end, &mut alloc_size, &mut flags)
    };

    let klass = unsafe { rb_cRange };
    gc_fastpath::gc_fastpath_new_obj(jit, asm, alloc_size, flags.as_u64(), klass,
        &|asm, range| {
            asm.store(Opnd::mem(VALUE_BITS, range, RUBY_OFFSET_RSTRUCT_FIELDS_OBJ), Opnd::UImm(0));
            asm.store(Opnd::mem(VALUE_BITS, range, RUBY_OFFSET_RSTRUCT_AS_ARY), low);
            asm.store(Opnd::mem(VALUE_BITS, range, RUBY_OFFSET_RSTRUCT_AS_ARY + SIZEOF_VALUE_I32), high);
        },
        |asm| {
            gen_prepare_leaf_call_with_gc(asm, state);

            asm_ccall!(asm, rb_range_new, low, high, (flag as i64).into())
        })
}

fn gen_object_alloc(jit: &JITState, asm: &mut Assembler, function: &Function, val: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Allocating an object from an unknown class is non-leaf; see doc for `ObjectAlloc`.
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_obj_alloc, val)
}

fn gen_object_alloc_class(jit: &mut JITState, asm: &mut Assembler, class: VALUE, state: &FrameState) -> lir::Opnd {
    // Allocating an object for a known class with default allocator is leaf; see doc for
    // `ObjectAllocClass`.
    gen_prepare_leaf_call_with_gc(asm, state);
    if unsafe { rb_zjit_class_has_default_allocator(class) } {
        let mut alloc_size: usize = 0;
        let mut shape_id: shape_id_t = 0;
        let has_fastpath = unsafe {
            rb_zjit_class_allocate_instance_fastpath(class, &mut alloc_size, &mut shape_id)
        };
        if has_fastpath {
            let flags = (RUBY_T_OBJECT as u64) | ((shape_id as u64) << RB_SHAPE_FLAG_SHIFT as u64);
            gc_fastpath::gc_fastpath_new_obj(jit, asm, alloc_size, flags, class, &|_asm, _obj| {}, |asm| {
                asm_ccall!(asm, rb_class_allocate_instance, class.into())
            })
        } else {
            asm_ccall!(asm, rb_class_allocate_instance, class.into())
        }
    } else {
        assert!(class_has_leaf_allocator(class), "class passed to ObjectAllocClass must have a leaf allocator");
        let alloc_func = unsafe { rb_zjit_class_get_alloc_func(class) };
        assert!(alloc_func.is_some(), "class {} passed to ObjectAllocClass must have an allocator", get_class_name(class));
        asm_comment!(asm, "call allocator for class {}", get_class_name(class));
        asm.count_call_to(&format!("{}::allocator", get_class_name(class)));
        asm.ccall(alloc_func.unwrap() as *const u8, vec![class.into()])
    }
}

/// Map an entry point to the bytecode PC used by its initial JITFrame.
/// JIT call entries use `opt_table[jit_entry_idx]`; the interpreter entry uses
/// `opt_table.last()` for the fall-through path where all optionals are filled.
fn entry_pc(iseq: IseqPtr, jit_entry_idx: Option<usize>) -> *const VALUE {
    let params = unsafe { iseq.params() };
    let opt_table = params.opt_table_slice();
    let entry_idx = jit_entry_idx.unwrap_or_else(|| opt_table.len() - 1);
    let entry_insn_idx = opt_table.get(entry_idx)
        .unwrap_or_else(|| panic!("entry_pc: opt_table out of bounds. {params:#?}, entry_idx={entry_idx}"))
        .as_u32();
    unsafe { rb_iseq_pc_at_idx(iseq, entry_insn_idx) }
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

    // Publish a valid entry JITFrame before setting cfp->jit_return. The entry point is
    // always the top-level frame (depth 0). Inlined frames get their own deeper
    // slots in gen_push_lightweight_frame().
    let jit_frame = JITFrame::new_iseq(entry_pc(jit.iseq(), jit_entry_idx), jit.iseq(), 0);
    asm.mov(Opnd::mem(64, NATIVE_BASE_PTR, -SIZEOF_VALUE_I32), Opnd::const_ptr(jit_frame));
    asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_JIT_RETURN), NATIVE_BASE_PTR);

    // Direct JIT-to-JIT callers switch the CFP register before calling this entry
    // point, but they leave ec->cfp pointing at the caller until cfp->jit_return
    // is valid so signal-based frame walkers never observe a half-published callee.
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);
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
    asm.frame_teardown(&[]); // matching the setup in gen_entry_point()
    asm.cret(C_RET_OPND);
}

/// Compile Fixnum + Fixnum
fn gen_fixnum_add(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Add left + right and test for overflow
    let left_untag = asm.sub(left, Opnd::Imm(1));
    let out_val = asm.add(left_untag, right);
    asm.jo(jit, side_exit(jit, function, state, FixnumAddOverflow));

    out_val
}

/// Compile Fixnum - Fixnum
fn gen_fixnum_sub(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Subtract left - right and test for overflow
    let val_untag = asm.sub(left, right);
    asm.jo(jit, side_exit(jit, function, state, FixnumSubOverflow));
    asm.add(val_untag, Opnd::Imm(1))
}

/// Compile Fixnum * Fixnum
fn gen_fixnum_mult(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Do some bitwise gymnastics to handle tag bits
    // x * y is translated to (x >> 1) * (y - 1) + 1
    let left_untag = asm.rshift(left, Opnd::UImm(1));
    let right_untag = asm.sub(right, Opnd::UImm(1));
    let out_val = asm.mul(left_untag, right_untag);

    // Test for overflow
    asm.jo_mul(jit, side_exit(jit, function, state, FixnumMultOverflow));
    asm.add(out_val, Opnd::UImm(1))
}

/// Compile Fixnum / Fixnum
fn gen_fixnum_div(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

    // Side exit if rhs is 0
    asm.cmp(right, Opnd::from(VALUE::fixnum_from_usize(0)));
    asm.je(jit, side_exit(jit, function, state, FixnumDivByZero));
    asm_ccall!(asm, rb_jit_fix_div_fix, left, right)
}

/// Compile Float + Float
fn gen_float_add(asm: &mut Assembler, recv: lir::Opnd, other: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_float_plus, recv, other)
}

/// Compile Float - Float
fn gen_float_sub(asm: &mut Assembler, recv: lir::Opnd, other: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_float_minus, recv, other)
}

/// Compile Float * Float
fn gen_float_mul(asm: &mut Assembler, recv: lir::Opnd, other: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_float_mul, recv, other)
}

/// Compile Float / Float
fn gen_float_div(asm: &mut Assembler, recv: lir::Opnd, other: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_float_div, recv, other)
}

/// Compile Float#to_i (truncate to integer)
fn gen_float_to_int(asm: &mut Assembler, recv: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);
    asm_ccall!(asm, rb_flo_to_i, recv)
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

/// Compile C integer | C integer.
fn gen_int_or(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    asm.or(left, right)
}

/// Compile Fixnum ^ Fixnum
fn gen_fixnum_xor(asm: &mut Assembler, left: lir::Opnd, right: lir::Opnd) -> lir::Opnd {
    // XOR and then re-tag the resulting fixnum
    let out_val = asm.xor(left, right);
    asm.add(out_val, Opnd::UImm(1))
}

/// Compile Fixnum << Fixnum
fn gen_fixnum_lshift(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: lir::Opnd, shift_amount: u64, state: &FrameState) -> lir::Opnd {
    // Shift amount is known statically to be in the range [0, 63]
    assert!(shift_amount < 64);
    let in_val = asm.sub(left, Opnd::UImm(1));  // Drop tag bit
    let out_val = asm.lshift(in_val, shift_amount.into());
    let unshifted = asm.rshift(out_val, shift_amount.into());
    asm.cmp(in_val, unshifted);
    asm.jne(jit, side_exit(jit, function, state, FixnumLShiftOverflow));
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

fn gen_fixnum_mod(jit: &mut JITState, asm: &mut Assembler, function: &Function, left: lir::Opnd, right: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Check for left % 0, which raises ZeroDivisionError
    asm.cmp(right, Opnd::from(VALUE::fixnum_from_usize(0)));
    asm.je(jit, side_exit(jit, function, state, FixnumModByZero));
    asm_ccall!(asm, rb_fix_mod_fix, left, right)
}

fn gen_fixnum_aref(asm: &mut Assembler, recv: lir::Opnd, index: lir::Opnd) -> lir::Opnd {
    asm_ccall!(asm, rb_fix_aref, recv, index)
}

fn gen_is_method_cfunc(asm: &mut Assembler, val: lir::Opnd, cd: *const rb_call_data, cfunc: *const u8, state: &FrameState) -> lir::Opnd {
    unsafe extern "C" {
        fn rb_vm_method_cfunc_is(iseq: IseqPtr, cd: *const rb_call_data, recv: VALUE, cfunc: *const u8) -> VALUE;
    }
    asm_ccall!(asm, rb_vm_method_cfunc_is, VALUE::from(state.iseq).into(), Opnd::const_ptr(cd), val, Opnd::const_ptr(cfunc))
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
    // Since we know val is either 0 or 1 and we are trying to get Qfalse or Qtrue, respectively,
    // we can just multiply by Qtrue to get the correct boxed value.
    assert_eq!(Qfalse.as_i64(), 0);
    assert_eq!(Qtrue.as_i64(), 0b10100);
    asm.mul(val, Qtrue.as_i64().into())
}

fn gen_box_fixnum(jit: &mut JITState, asm: &mut Assembler, function: &Function, val: lir::Opnd, state: &FrameState) -> lir::Opnd {
    // Load the value, then test for overflow and tag it
    let val = asm.load_mem(val);
    let shifted = asm.lshift(val, Opnd::UImm(1));
    asm.jo(jit, side_exit(jit, function, state, BoxFixnumOverflow));
    asm.or(shifted, Opnd::UImm(RUBY_FIXNUM_FLAG as u64))
}

fn gen_anytostring(asm: &mut Assembler, val: lir::Opnd, state: &FrameState) -> lir::Opnd {
    gen_prepare_leaf_call_with_gc(asm, state);

    asm_ccall!(asm, rb_any_to_s, val)
}

/// Evaluate if a value is truthy
/// Produces a CBool type (0 or 1)
/// In Ruby, only nil and false are falsy
/// Everything else evaluates to true
fn gen_test(asm: &mut Assembler, val: lir::Opnd, val_type: Type) -> lir::Opnd {
    if val_type.is_subtype(types::BoolExact) {
        // If the type is BoolExact, we know it's either Qtrue or Qfalse. We can just right shift
        // to check what's in the fifth bit.
        assert_eq!(Qfalse.as_i64(), 0);
        assert_eq!(Qtrue.as_i64(), 0b10100);
        return asm.rshift(val, Opnd::UImm(4));
    }
    // Test if any bit (outside of the Qnil bit) is on
    // See RB_TEST(), include/ruby/internal/special_consts.h
    asm.test(val, Opnd::Imm(!Qnil.as_i64()));
    asm.csel_e(0.into(), 1.into())
}

fn gen_has_type(jit: &mut JITState, asm: &mut Assembler, val: lir::Opnd, val_type: Type, ty: Type) -> lir::Opnd {
    if ty.is_subtype(types::Fixnum) {
        asm.test(val, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));
        asm.csel_nz(Opnd::Imm(1), Opnd::Imm(0))
    } else if ty.is_subtype(types::Flonum) {
        // Flonum: (val & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG
        let masked = asm.and(val, Opnd::UImm(RUBY_FLONUM_MASK as u64));
        asm.cmp(masked, Opnd::UImm(RUBY_FLONUM_FLAG as u64));
        asm.csel_e(Opnd::Imm(1), Opnd::Imm(0))
    } else if ty.is_subtype(types::StaticSymbol) {
        // Static symbols have (val & 0xff) == RUBY_SYMBOL_FLAG
        // Use 8-bit comparison like YJIT does.
        // If `val` is a constant (rare but possible), put it in a register to allow masking.
        let val = asm.load_imm(val);
        asm.cmp(val.with_num_bits(8), Opnd::UImm(RUBY_SYMBOL_FLAG as u64));
        asm.csel_e(Opnd::Imm(1), Opnd::Imm(0))
    } else if ty.is_subtype(types::NilClass) {
        asm.cmp(val, Qnil.into());
        asm.csel_e(Opnd::Imm(1), Opnd::Imm(0))
    } else if ty.is_subtype(types::TrueClass) {
        asm.cmp(val, Qtrue.into());
        asm.csel_e(Opnd::Imm(1), Opnd::Imm(0))
    } else if ty.is_subtype(types::FalseClass) {
        asm.cmp(val, Qfalse.into());
        asm.csel_e(Opnd::Imm(1), Opnd::Imm(0))
    } else if ty.is_immediate() {
        // All immediate types' guard should have been handled above
        panic!("unexpected immediate guard type: {ty}");
    } else if let Some(expected_class) = ty.runtime_exact_ruby_class() {
        let hir_block_id = asm.current_block().hir_block_id;
        let rpo_idx = asm.current_block().rpo_index;

        // Create a result block that all paths converge to
        let result_block = asm.new_block(hir_block_id, false, rpo_idx);
        let result_edge = |v| Target::Block(Box::new(lir::BranchEdge {
            target: result_block,
            args: vec![v],
        }));

        // If val isn't in a register, load it to use it as the base of Opnd::mem later.
        // TODO: Max thinks codegen should not care about the shapes of the operands except to create them. (Shopify/ruby#685)
        let val = asm.load_mem(val);

        let is_known_heap_basic_object = val_type.is_subtype(types::HeapBasicObject);
        if !is_known_heap_basic_object {
            // Immediate -> definitely not the class
            asm.test(val, (RUBY_IMMEDIATE_MASK as u64).into());
            asm.jnz(jit, result_edge(Opnd::Imm(0)));

            // Qfalse -> definitely not the class
            asm.cmp(val, Qfalse.into());
            asm.je(jit, result_edge(Opnd::Imm(0)));
        }

        // Heap object -> check klass field
        let klass = asm.load(Opnd::mem(64, val, RUBY_OFFSET_RBASIC_KLASS));
        asm.cmp(klass, Opnd::Value(expected_class));
        let result = asm.csel_e(Opnd::UImm(1), Opnd::Imm(0));
        asm.jmp(result_edge(result));

        // Result block -- receives the value via block parameter (phi node)
        asm.set_current_block(result_block);
        let label = jit.get_label(asm, result_block, hir_block_id);
        asm.write_label(label);
        let param = asm.new_block_param(VALUE_BITS);
        asm.current_block().add_parameter(param);
        param
    } else if let Some(builtin_type) = ty.builtin_type_equivalent() {
        let hir_block_id = asm.current_block().hir_block_id;
        let rpo_idx = asm.current_block().rpo_index;

        // Create a result block that all paths converge to
        let result_block = asm.new_block(hir_block_id, false, rpo_idx);
        let result_edge = |v| Target::Block(Box::new(lir::BranchEdge {
            target: result_block,
            args: vec![v],
        }));

        // If val isn't in a register, load it to use it as the base of Opnd::mem later.
        let val = asm.load_mem(val);

        let is_known_heap_basic_object = val_type.is_subtype(types::HeapBasicObject);
        if !is_known_heap_basic_object {
            // Immediate -> definitely not the class
            asm.test(val, (RUBY_IMMEDIATE_MASK as u64).into());
            asm.jnz(jit, result_edge(Opnd::Imm(0)));

            // Qfalse -> definitely not the class
            asm.cmp(val, Qfalse.into());
            asm.je(jit, result_edge(Opnd::Imm(0)));
        }

        // Heap object
        // Mask and check the builtin type
        let flags = asm.load(Opnd::mem(VALUE_BITS, val, RUBY_OFFSET_RBASIC_FLAGS));
        let tag   = asm.and(flags, Opnd::UImm(RUBY_T_MASK as u64));
        asm.cmp(tag, Opnd::UImm(builtin_type as u64));
        let result = asm.csel_e(Opnd::UImm(1), Opnd::Imm(0));
        asm.jmp(result_edge(result));

        // Result block -- receives the value via block parameter (phi node)
        asm.set_current_block(result_block);
        let label = jit.get_label(asm, result_block, hir_block_id);
        asm.write_label(label);
        let param = asm.new_block_param(VALUE_BITS);
        asm.current_block().add_parameter(param);
        param
    } else {
        unimplemented!("unsupported type: {ty}");
    }
}

/// Compile a type check with a side exit
fn gen_guard_type(jit: &mut JITState, asm: &mut Assembler, function: &Function, val: lir::Opnd, val_type: Type, guard_type: Type, recompile: Option<Recompile>, state: &FrameState) -> lir::Opnd {
    let is_known_heap_basic_object = val_type.is_subtype(types::HeapBasicObject);
    gen_incr_counter(asm, Counter::guard_type_count);
    if guard_type.is_subtype(types::Fixnum) {
        asm.test(val, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));
        asm.jz(jit, side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile));
    } else if guard_type.is_subtype(types::Flonum) {
        // Flonum: (val & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG
        let masked = asm.and(val, Opnd::UImm(RUBY_FLONUM_MASK as u64));
        asm.cmp(masked, Opnd::UImm(RUBY_FLONUM_FLAG as u64));
        asm.jne(jit, side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile));
    } else if guard_type.is_subtype(types::StaticSymbol) {
        // Static symbols have (val & 0xff) == RUBY_SYMBOL_FLAG
        // Use 8-bit comparison like YJIT does.
        // If `val` is a constant (rare but possible), put it in a register to allow masking.
        let val = asm.load_imm(val);
        asm.cmp(val.with_num_bits(8), Opnd::UImm(RUBY_SYMBOL_FLAG as u64));
        asm.jne(jit, side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile));
    } else if guard_type.is_subtype(types::NilClass) {
        asm.cmp(val, Qnil.into());
        asm.jne(jit, side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile));
    } else if guard_type.is_subtype(types::TrueClass) {
        asm.cmp(val, Qtrue.into());
        asm.jne(jit, side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile));
    } else if guard_type.is_subtype(types::FalseClass) {
        asm.cmp(val, Qfalse.into());
        asm.jne(jit, side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile));
    } else if guard_type.is_immediate() {
        // All immediate types' guard should have been handled above
        panic!("unexpected immediate guard type: {guard_type}");
    } else if let Some(expected_class) = guard_type.runtime_exact_ruby_class() {
        asm_comment!(asm, "guard exact class for non-immediate types");

        // If val isn't in a register, load it to use it as the base of Opnd::mem later.
        // TODO: Max thinks codegen should not care about the shapes of the operands except to create them. (Shopify/ruby#685)
        let val = asm.load_mem(val);

        let side_exit = side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile);
        if !is_known_heap_basic_object {
            // Check if it's a special constant
            asm.test(val, (RUBY_IMMEDIATE_MASK as u64).into());
            asm.jnz(jit, side_exit.clone());

            // Check if it's false
            asm.cmp(val, Qfalse.into());
            asm.je(jit, side_exit.clone());
        }

        // Load the class from the object's klass field
        let klass = asm.load(Opnd::mem(64, val, RUBY_OFFSET_RBASIC_KLASS));

        asm.cmp(klass, Opnd::Value(expected_class));
        asm.jne(jit, side_exit);
    } else if let Some(builtin_type) = guard_type.builtin_type_equivalent() {
        let side = side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile);

        if !is_known_heap_basic_object {
            // Check special constant
            asm.test(val, Opnd::UImm(RUBY_IMMEDIATE_MASK as u64));
            asm.jnz(jit, side.clone());

            // Check false
            asm.cmp(val, Qfalse.into());
            asm.je(jit, side.clone());
        }

        // Mask and check the builtin type
        let val = asm.load_mem(val);
        let flags = asm.load(Opnd::mem(VALUE_BITS, val, RUBY_OFFSET_RBASIC_FLAGS));
        let tag   = asm.and(flags, Opnd::UImm(RUBY_T_MASK as u64));
        asm.cmp(tag, Opnd::UImm(builtin_type as u64));
        asm.jne(jit, side);
    } else if guard_type.bit_equal(types::HeapBasicObject) {
        let side_exit = side_exit_with_recompile(jit, function, state, GuardType(guard_type), recompile);
        asm.cmp(val, Opnd::Value(Qfalse));
        asm.je(jit, side_exit.clone());
        asm.test(val, (RUBY_IMMEDIATE_MASK as u64).into());
        asm.jnz(jit, side_exit);
    } else {
        unimplemented!("unsupported type: {guard_type}");
    }
    val
}

/// Compile an identity check with a side exit
fn gen_guard_bit_equals(jit: &mut JITState, asm: &mut Assembler, function: &Function, val: lir::Opnd, expected: crate::hir::Const, reason: SideExitReason, recompile: Option<Recompile>, state: &FrameState) -> lir::Opnd {
    if matches!(reason, SideExitReason::GuardShape(_) ) {
        gen_incr_counter(asm, Counter::guard_shape_count);
    }
    let expected_opnd: Opnd = match expected {
        crate::hir::Const::Value(v) => { Opnd::Value(v) }
        crate::hir::Const::CInt64(v) => { v.into() }
        crate::hir::Const::CPtr(v) => { Opnd::const_ptr(v) }
        crate::hir::Const::CShape(v) => { Opnd::UImm(v.0 as u64) }
        _ => panic!("gen_guard_bit_equals: unexpected hir::Const {expected:?}"),
    };
    asm.cmp(val, expected_opnd);
    asm.jnz(jit, side_exit_with_recompile(jit, function, state, reason, recompile));
    val
}

fn mask_to_opnd(mask: crate::hir::Const) -> Option<Opnd> {
    match mask {
        crate::hir::Const::CUInt8(v) => Some(Opnd::UImm(v as u64)),
        crate::hir::Const::CUInt16(v) => Some(Opnd::UImm(v as u64)),
        crate::hir::Const::CUInt32(v) => Some(Opnd::UImm(v as u64)),
        crate::hir::Const::CUInt64(v) => Some(Opnd::UImm(v)),
        _ => None
    }
}

/// Compile a bitmask check with a side exit if none of the masked bits are not set
fn gen_guard_any_bit_set(jit: &mut JITState, asm: &mut Assembler, function: &Function, val: lir::Opnd, mask: crate::hir::Const, reason: SideExitReason, recompile: Option<Recompile>, state: &FrameState) -> lir::Opnd {
    let mask_opnd = mask_to_opnd(mask).unwrap_or_else(|| panic!("gen_guard_any_bit_set: unexpected hir::Const {mask:?}"));
    asm.test(val, mask_opnd);
    asm.jz(jit, side_exit_with_recompile(jit, function, state, reason, recompile));
    val
}

/// Compile a bitmask check with a side exit if any of the masked bits are set
fn gen_guard_no_bits_set(jit: &mut JITState, asm: &mut Assembler, function: &Function, val: lir::Opnd, mask: crate::hir::Const, reason: SideExitReason, state: &FrameState) -> lir::Opnd {
    let mask_opnd = mask_to_opnd(mask).unwrap_or_else(|| panic!("gen_guard_no_bits_set: unexpected hir::Const {mask:?}"));
    asm.test(val, mask_opnd);
    asm.jnz(jit, side_exit(jit, function, state, reason));
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
        SendNotOptimizedMethodTypeOptimized(method_type) => {
            gen_incr_counter(asm, send_fallback_counter_for_optimized_method_type(method_type));
        }
        SendNotOptimizedMethodType(method_type) => {
            gen_incr_counter(asm, send_fallback_counter_for_method_type(method_type));
        }
        SuperNotOptimizedMethodType(method_type) => {
            gen_incr_counter(asm, send_fallback_counter_for_super_method_type(method_type));
        }
        _ => {}
    }
}

/// Check if an ISEQ contains instructions that may write to block_code
/// (send, sendforward, invokesuper, invokesuperforward, invokeblock).
/// These instructions call vm_caller_setup_arg_block which writes to cfp->block_code.
#[allow(non_upper_case_globals)]
pub(crate) fn iseq_may_write_block_code(iseq: IseqPtr) -> bool {
    let encoded_size = unsafe { rb_iseq_encoded_size(iseq) };
    let mut insn_idx: u32 = 0;

    while insn_idx < encoded_size {
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
        let opcode = unsafe { rb_iseq_bare_opcode_at_pc(iseq, pc) } as u32;

        match opcode {
            YARVINSN_send | YARVINSN_sendforward |
            YARVINSN_invokesuper | YARVINSN_invokesuperforward |
            YARVINSN_invokeblock => {
                return true;
            }
            _ => {}
        }

        insn_idx = insn_idx.saturating_add(unsafe { rb_insn_len(VALUE(opcode as usize)) }.try_into().unwrap());
    }

    false
}

/// True if the block ISEQ contains a `throw` opcode (break, non-local return). ZJIT can't
/// compile `throw`, so inlining such a block's frame would side-exit + deopt on every call.
/// These blocks fall back to `vm_yield`, which handles the non-local exit in C.
/// (`next`/`redo` lower to `leave`/`jump`, not `throw`, so they stay inlinable.)
pub(crate) fn block_iseq_may_throw(iseq: IseqPtr) -> bool {
    let encoded_size = unsafe { rb_iseq_encoded_size(iseq) };
    let mut insn_idx: u32 = 0;

    while insn_idx < encoded_size {
        let pc = unsafe { rb_iseq_pc_at_idx(iseq, insn_idx) };
        let opcode = unsafe { rb_iseq_bare_opcode_at_pc(iseq, pc) } as u32;

        if opcode == YARVINSN_throw {
            return true;
        }

        insn_idx = insn_idx.saturating_add(unsafe { rb_insn_len(VALUE(opcode as usize)) }.try_into().unwrap());
    }

    false
}

/// Byte offset from NATIVE_BASE_PTR of the JITFrame storage slot for a frame at
/// the given inlining depth. Depth 0 (the top-level frame) lives at
/// `[NATIVE_BASE_PTR - 8]`; each deeper inlined frame gets the next slot below.
/// gen_function() reserves `inlining_depth() + 1` slots, so every live frame's
/// depth maps to a distinct slot inside that reserved region.
fn jit_frame_slot_offset(depth: InlineDepth) -> i32 {
    -(SIZEOF_VALUE_I32 * (depth as i32 + 1))
}

/// Compute the value to store in a frame's `cfp->jit_return` for the given
/// inlining depth. CFP_ZJIT_FRAME(cfp) reads the JITFrame pointer from
/// `((VALUE *)cfp->jit_return)[-1]`, so jit_return must point one VALUE above
/// the frame's storage slot (see jit_frame_slot_offset()). Depth 0 lands exactly
/// on NATIVE_BASE_PTR, matching the non-inlined protocol; deeper frames need an
/// address computed relative to it.
fn cfp_jit_return_for_depth(asm: &mut Assembler, depth: InlineDepth) -> Opnd {
    if depth == 0 {
        NATIVE_BASE_PTR
    } else {
        asm.lea(Opnd::mem(64, NATIVE_BASE_PTR, -(SIZEOF_VALUE_I32 * depth as i32)))
    }
}

fn jit_frame_next_pc(state: &FrameState) -> *const VALUE {
    let opcode: usize = state.get_opcode().try_into().unwrap();
    unsafe { state.pc.offset(insn_len(opcode) as isize) }
}

fn jit_frame_for_state(state: &FrameState, stack_map_size: usize) -> *const zjit_jit_frame {
    JITFrame::new_iseq(jit_frame_next_pc(state), state.iseq, stack_map_size)
}

/// Save only the PC to CFP. Use this when you need to call gen_save_sp()
/// immediately after with a custom stack size (e.g., gen_ccall_with_frame
/// adjusts SP to exclude receiver and arguments).
fn gen_write_jit_frame(asm: &mut Assembler, state: &FrameState, stack_map_size: usize) -> *const zjit_jit_frame {
    gen_incr_counter(asm, Counter::vm_write_jit_frame_count);
    asm_comment!(asm, "save JITFrame to CFP");
    let jit_frame = jit_frame_for_state(state, stack_map_size);
    asm.mov(Opnd::mem(64, NATIVE_BASE_PTR, jit_frame_slot_offset(state.depth)), Opnd::const_ptr(jit_frame));

    // CFP_PC for a live JIT frame routes through the JITFrame on the native
    // stack (cfp->jit_return points at this frame's slot), so we don't need to
    // touch cfp->pc here. Poisoning cfp->pc with PC_POISON would actively
    // break the case where rb_zjit_materialize_frames() previously copied
    // jit_frame->pc into cfp->pc and cleared cfp->jit_return: the JIT keeps
    // running, lands on this routine again, and the poison would replace
    // the valid materialized pc behind the GC's back.
    jit_frame
}

/// Save the current PC on the CFP as a preparation for calling a C function
/// that may allocate objects and trigger GC. Use gen_prepare_non_leaf_call()
/// if it may raise exceptions or call arbitrary methods.
///
/// Unlike YJIT, we don't need to save the stack slots to protect them from GC
/// because the backend spills all live registers onto the C stack on CCall.
/// However, to avoid marking uninitialized stack slots, this also updates SP,
/// which may have cfp->sp for a past frame or a past non-leaf call.
fn gen_prepare_call_with_gc(asm: &mut Assembler, state: &FrameState, leaf: bool, stack_map_size: usize) -> *const zjit_jit_frame {
    let jit_frame = gen_write_jit_frame(asm, state, stack_map_size);
    gen_save_sp(asm, state.stack_size());
    if leaf {
        asm.expect_leaf_ccall(state.stack_size());
    }
    jit_frame
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
    gen_prepare_call_with_gc(asm, &state.without_stack(), true, 0);
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
        asm.mov(Opnd::mem(64, SP, (-local_idx_to_ep_offset(state.iseq, idx) - 1) * SIZEOF_VALUE_I32), jit.get_opnd(insn_id));
    }
}

/// Spill the virtual stack onto the stack.
fn gen_spill_stack(jit: &JITState, asm: &mut Assembler, function: &Function, state: &FrameState) {
    // This function does not call gen_save_sp() at the moment because
    // gen_send_without_block_direct() spills stack slots above SP for arguments.
    gen_incr_counter(asm, Counter::vm_write_stack_count);
    asm_comment!(asm, "spill stack");

    let mut offset = state.stack_size() as i32;
    for entry in build_stack_map(jit, function, state) {
        match entry {
            StackMapEntry::Opnd(opnd) => {
                offset -= 1;
                asm.mov(Opnd::mem(64, SP, offset * SIZEOF_VALUE_I32), opnd);
            }
            StackMapEntry::Skip(skip) => {
                offset -= skip as i32;
            }
        }
    }
}

/// Prepare for VM fallback helpers that read arguments from the VM stack.
///
/// Direct JIT-to-JIT calls keep cfp->sp lazy, so this must publish SP before
/// writing stack slots. Otherwise spilling the stack can overwrite frame
/// metadata below the real VM-stack base.
fn gen_prepare_fallback_call(jit: &JITState, asm: &mut Assembler, function: &Function, state: &FrameState) {
    gen_write_jit_frame(asm, state, 0);
    gen_save_sp(asm, state.stack_size());
    gen_spill_locals(jit, asm, state);
    gen_spill_stack(jit, asm, function, state);
}

/// Build entries for Ruby stack values that need materialization. The actual
/// JITFrame entries are encoded by the register allocator, where VReg locations
/// on the native stack are known.
fn build_stack_map(jit: &JITState, function: &Function, state: &FrameState) -> Vec<StackMapEntry> {
    let mut stack = Vec::new();
    let mut current_state = state.clone();
    loop {
        stack.extend(current_state.stack().rev().copied().map(|insn_id| {
            let opnd = jit.get_opnd(insn_id);
            assert!(
                matches!(opnd, Opnd::Value(_) | Opnd::VReg { .. }),
                "FrameState should only reference Opnd::Value or Opnd::VReg, but got: {opnd:?}",
            );
            StackMapEntry::Opnd(opnd)
        }));

        let Some(caller) = current_state.caller() else {
            break;
        };
        stack.push(StackMapEntry::Skip(inline_frame_stack_gap(current_state.iseq)));
        current_state = function.frame_state(caller);
    }
    stack
}

fn inline_frame_stack_gap(iseq: IseqPtr) -> usize {
    // The extra slot is for the callee's receiver below its local table.
    // We currently never map out the stack for `invokeblock`, which doesn't
    // put a receiver on cfp->sp stack.
    1 + unsafe { get_iseq_body_local_table_size(iseq) }.to_usize() + VM_ENV_DATA_SIZE.to_usize()
}

/// Prepare for calling a C function that may call an arbitrary method.
/// Use gen_prepare_leaf_call_with_gc() if the method is leaf but allocates objects.
fn gen_prepare_non_leaf_call(jit: &JITState, asm: &mut Assembler, function: &Function, state: &FrameState) {
    // TODO: Lazily materialize caller frames when needed
    // Save PC for backtraces and allocation tracing
    // and SP to avoid marking uninitialized stack slots
    let stack_map = build_stack_map(jit, function, state);
    let jit_frame = gen_prepare_call_with_gc(asm, state, false, stack_map.len());

    // Remember the stack map in case it raises an exception
    // and the interpreter uses the stack for handling the exception
    asm.stack_map(stack_map, jit_frame, state.depth);

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
    /// Whether to write block_code = 0 at frame push time.
    /// True when the callee ISEQ may write to block_code (has send/invokesuper/invokeblock).
    write_block_code: bool,
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

    if frame.iseq.is_some() {
        // PC, SP, and ISEQ are written lazily by the callee on side-exits, non-leaf calls, or GC.
        // cfp->jit_return will be written by gen_entry_point() on the callee after this frame push.
        if frame.write_block_code {
            asm_comment!(asm, "write block_code for iseq that may use it");
            asm.mov(cfp_opnd(RUBY_OFFSET_CFP_BLOCK_CODE), 0.into());
        }
    } else {
        // C frames don't have a PC and ISEQ in normal operation. ISEQ frames set PC on gen_write_jit_frame().
        // When runtime checks are enabled we poison the PC for C frames so accidental reads stand out.
        if let (None, Some(pc)) = (frame.iseq, PC_POISON) {
            asm.mov(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_PC), Opnd::const_ptr(pc));
        }
        let new_sp = asm.lea(Opnd::mem(64, SP, (ep_offset + 1) * SIZEOF_VALUE_I32));
        asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SP), new_sp);
        // block_code must be written explicitly because the interpreter reads
        // captured->code.ifunc directly from cfp->block_code (not through JITFrame).
        // Without this, stale data from a previous frame occupying this CFP slot
        // can be used as an ifunc pointer, causing a segfault.
        asm.mov(cfp_opnd(RUBY_OFFSET_CFP_BLOCK_CODE), 0.into());
        // C frames share a single static JITFrame (rb_zjit_c_frame). Setting
        // cfp->jit_return to the ZJIT_JIT_RETURN_C_FRAME sentinel tells
        // CFP_ZJIT_FRAME() to use that shared frame, so we don't need to
        // allocate a per-call JITFrame for C method pushes.
        asm.mov(cfp_opnd(RUBY_OFFSET_CFP_JIT_RETURN), (ZJIT_JIT_RETURN_C_FRAME as usize).into());
    }

    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_SELF), frame.recv);
    let ep = asm.lea(Opnd::mem(64, SP, ep_offset * SIZEOF_VALUE_I32));
    asm.mov(cfp_opnd(RUBY_OFFSET_CFP_EP), ep);
}

/// Stack overflow check: fails if CFP<=SP at any point in the callee.
fn gen_stack_overflow_check(jit: &mut JITState, asm: &mut Assembler, function: &Function, state: &FrameState, stack_growth: usize) {
    asm_comment!(asm, "stack overflow check");
    // vm_push_frame() checks it against a decremented cfp, and CHECK_VM_STACK_OVERFLOW0
    // adds to the margin another control frame with `&bounds[1]`.
    const { assert!(RUBY_SIZEOF_CONTROL_FRAME % SIZEOF_VALUE == 0, "sizeof(rb_control_frame_t) is a multiple of sizeof(VALUE)"); }
    let cfp_growth = 2 * (RUBY_SIZEOF_CONTROL_FRAME / SIZEOF_VALUE);
    let peak_offset = (cfp_growth + stack_growth) * SIZEOF_VALUE;
    let stack_limit = asm.lea(Opnd::mem(64, SP, peak_offset as i32));
    asm.cmp(CFP, stack_limit);
    asm.jbe(jit, side_exit(jit, function, state, StackOverflow));
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

    let hir = trace_compile_phase("build_hir", ||
        crate::stats::with_time_stat(Counter::compile_hir_build_time_ns, || iseq_to_hir(iseq))
    );
    let mut function = match hir {
        Ok(function) => function,
        Err(err) => {
            debug!("ZJIT: iseq_to_hir: {err:?}: {}", iseq_get_location(iseq, 0));
            return Err(CompileError::ParseError(err));
        }
    };
    if !get_option!(disable_hir_opt) {
        trace_compile_phase("optimize", || function.optimize());
    }
    function.dump_hir();
    let non_final_version = get_or_create_iseq_payload(iseq).versions.len() + 1 < max_iseq_versions();
    if non_final_version {
        reset_profiles_remaining(iseq);
    }
    Ok(function)
}

/// Build a Target::SideExit
fn side_exit(jit: &JITState, function: &Function, state: &FrameState, reason: SideExitReason) -> Target {
    let exit = build_side_exit(jit, function, state);
    Target::SideExit(Box::new(SideExitTarget { exit, reason }))
}

/// Build a Target::SideExit that optionally triggers exit_recompile on the exit path.
fn side_exit_with_recompile(jit: &JITState, function: &Function, state: &FrameState, reason: SideExitReason, recompile: Option<Recompile>) -> Target {
    let mut exit = build_side_exit(jit, function, state);
    exit.recompile = recompile.map(|_| SideExitRecompile {
        compiled_iseq: Opnd::Value(VALUE::from(jit.iseq())),
        insn_idx: state.insn_idx() as u32,
    });
    Target::SideExit(Box::new(SideExitTarget { exit, reason }))
}

/// Build a side-exit context
fn build_side_exit(jit: &JITState, function: &Function, state: &FrameState) -> SideExit {
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
        iseq: state.iseq,
        stack_map: build_caller_stack_map(jit, function, state),
        recompile: None,
    }
}

fn build_caller_stack_map(jit: &JITState, function: &Function, state: &FrameState) -> Option<StackMap> {
    let caller = state.caller()?;
    let caller_state = function.frame_state(caller);
    let stack_map = build_stack_map(jit, function, &caller_state);
    if stack_map.is_empty() {
        return None;
    }

    let jit_frame = jit_frame_for_state(&caller_state, stack_map.len());
    Some(StackMap::new(stack_map, jit_frame, caller_state.depth))
}

#[cfg(target_arch = "x86_64")]
macro_rules! c_callable {
    ($(#[$outer:meta])*
    $vis:vis fn $f:ident $args:tt $(-> $ret:ty)? $body:block) => {
        $(#[$outer])*
        $vis extern "sysv64" fn $f $args $(-> $ret)? $body
    };
}
#[cfg(target_arch = "aarch64")]
macro_rules! c_callable {
    ($(#[$outer:meta])*
    $vis:vis fn $f:ident $args:tt $(-> $ret:ty)? $body:block) => {
        $(#[$outer])*
        $vis extern "C" fn $f $args $(-> $ret)? $body
    };
}
#[cfg(test)]
pub(crate) use c_callable;

c_callable! {
    /// Called from JIT side-exit code to profile operands and trigger recompilation.
    /// Once enough profiles are gathered, invalidates the compiled unit for recompilation.
    ///
    /// `compiled_iseq_raw` is the ISEQ that was actually compiled. For an exit out
    /// of inlined code, the inliner folds the callee's body into the outer ISEQ, so
    /// the outer ISEQ's version holds the failing guard and must be invalidated to
    /// force a recompile. For non-inlined code, it is the same as the frame ISEQ.
    pub(crate) fn exit_recompile(ec: EcPtr, compiled_iseq_raw: VALUE) {
        // Fast check before taking the VM lock: skip if the compiled unit is already
        // invalidated or at the version limit. This avoids expensive lock acquisition
        // on every shape guard exit after the recompile has already been triggered.
        // The check is on the compiled unit because that is the version we invalidate.
        {
            let compiled_iseq: IseqPtr = compiled_iseq_raw.as_iseq();
            let payload = get_or_create_iseq_payload(compiled_iseq);
            let already_done = payload.versions.last()
                .map_or(false, |v| unsafe { v.as_ref() }.is_invalidated())
                || payload.versions.len() >= max_iseq_versions();
            if already_done {
                return;
            }
        }

        with_vm_lock(src_loc!(), || {
            let compiled_iseq: IseqPtr = compiled_iseq_raw.as_iseq();

            let should_recompile = with_time_stat(Counter::profile_time_ns, || {
                crate::profile::profile_recompile_insn(ec)
            });

            // Once we have enough profiles, invalidate the compiled unit so it
            // recompiles and reads the freshly recorded profile. We invalidate
            // `compiled_iseq` rather than `frame_iseq` because an inlined callee has no
            // compiled code of its own; the outer function it was folded into is what
            // actually got compiled.
            if should_recompile {
                let payload = get_or_create_iseq_payload(compiled_iseq);
                if let Some(version) = payload.versions.last_mut() {
                    let cb = ZJITState::get_code_block();
                    invalidate_iseq_version(cb, compiled_iseq, version);
                    cb.mark_all_executable();
                }
            }
        });
    }
}

c_callable! {
    /// Generated code calls this function with the SysV calling convention. See [gen_function_stub].
    /// This function is expected to be called repeatedly when ZJIT fails to compile the stub.
    /// We should be able to compile most (if not all) function stubs by side-exiting at unsupported
    /// instructions, so this should be used primarily for cb.has_dropped_bytes() situations.
    fn function_stub_hit(iseq_call_ptr: *const c_void, cfp: CfpPtr, sp: *mut VALUE, ec: EcPtr) -> *const u8 {
        // Make sure cfp is ready to be scanned by other Ractors and GC before taking the barrier
        {
            unsafe { Rc::increment_strong_count(iseq_call_ptr as *const IseqCall); }
            let iseq_call = unsafe { Rc::from_raw(iseq_call_ptr as *const IseqCall) };
            let iseq = iseq_call.iseq.get();
            let params = unsafe { iseq.params() };
            let entry_idx = iseq_call.jit_entry_idx.to_usize();
            let entry_insn_idx = params.opt_table_slice().get(entry_idx)
                .unwrap_or_else(|| panic!("function_stub: opt_table out of bounds. {params:#?}, entry_idx={entry_idx}"))
                .as_u32();
            // gen_push_frame() doesn't set PC or ISEQ, so we need to set them before exit.
            // function_stub_hit_body() may allocate and call gc_validate_pc(), so we always set PC and ISEQ.
            // Clear jit_return so the interpreter reads cfp->pc and cfp->iseq directly.
            let pc = unsafe { rb_iseq_pc_at_idx(iseq, entry_insn_idx) };
            unsafe { rb_set_cfp_pc(cfp, pc) };
            unsafe { (*cfp)._iseq = iseq };
            unsafe { (*cfp).jit_return = std::ptr::null_mut() };
            let ec_cfp = unsafe { ec.byte_add(RUBY_OFFSET_EC_CFP as usize) as *mut CfpPtr };
            unsafe { *ec_cfp = cfp };
        }

        with_vm_lock(src_loc!(), || {
            // Re-create the Rc inside the VM lock because IseqCall's interior
            // mutability (Cell<IseqPtr>) requires exclusive access.
            let iseq_call = unsafe { Rc::from_raw(iseq_call_ptr as *const IseqCall) };
            let iseq = iseq_call.iseq.get();
            let argc = iseq_call.argc;
            let num_opts_filled = iseq_call.jit_entry_idx;

            // JIT-to-JIT calls don't eagerly fill nils to non-parameter locals.
            // If we side-exit from function_stub_hit (before JIT code runs), we need to set them here.
            fn prepare_for_exit(iseq: IseqPtr, cfp: CfpPtr, sp: *mut VALUE, argc: u16, num_opts_filled: u16, compile_error: &CompileError) {
                unsafe {
                    // Caller frames are materialized by the materialize_exit trampoline before unwinding native frames.
                    // The current frame's pc and iseq are already set by function_stub_hit before this point.

                    // Set SP which gen_push_frame() doesn't set
                    rb_set_cfp_sp(cfp, sp);

                    let local_size = get_iseq_body_local_table_size(iseq).to_usize();
                    let params = iseq.params();
                    let params_size = params.size.to_usize();
                    let frame_base = sp.offset(-local_size_and_idx_to_bp_offset(local_size, 0) as isize);
                    let locals = slice::from_raw_parts_mut(frame_base, local_size);
                    // Fill nils to uninitialized (non-parameter) locals
                    locals.get_mut(params_size..).unwrap_or_default().fill(Qnil);

                    // SendDirect packs args without gaps for unfilled optionals.
                    // When we exit to the interpreter, we need to shift args right
                    // to create the gap and nil-fill the unfilled optional slots.
                    //
                    // Example: def target(req, a = a, b = b, kw:); target(1, kw: 2)
                    //   lead_num=1, opt_num=2, opts_filled=0, argc=2
                    //
                    //   locals[] as placed by SendDirect (argc=2, no gaps):
                    //     [req, kw_val, ?, ?, ?, ...]
                    //      0    1
                    //      ^----caller's args----^
                    //
                    //   locals[] expected by interpreter (params_size=4):
                    //     [req,  a,   b,  kw_val, ?, ...]
                    //      0     1    2   3
                    //            ^nil ^nil^--moved--^
                    //
                    //   gap_start = lead_num + opts_filled = 1
                    //   gap_end   = lead_num + opt_num     = 3
                    //   We move locals[gap_start..argc] to locals[gap_end..], then
                    //   nil-fill locals[gap_start..gap_end].
                    let opt_num: usize = params.opt_num.try_into().expect("ISEQ opt_num should be non-negative");
                    let opts_filled = num_opts_filled.to_usize();
                    let opts_unfilled = opt_num.saturating_sub(opts_filled);
                    if opts_unfilled > 0 {
                        let argc = argc.to_usize();
                        let lead_num: usize = params.lead_num.try_into().expect("ISEQ lead_num should be non-negative");
                        let param_locals = &mut locals[..params_size];
                        // Gap of unspecified optional parameters
                        let gap_start = lead_num + opts_filled;
                        let gap_end = lead_num + opt_num;
                        // When there are arguments in the gap, shift them past the gap
                        let args_overlapping_gap = gap_start..argc;
                        if !args_overlapping_gap.is_empty() {
                            assert!(
                                gap_end.checked_add(args_overlapping_gap.len())
                                    .is_some_and(|new_end| new_end <= param_locals.len()) ,
                                "shift past gap out-of-bounds. params={params:#?} args_overlapping_gap={args_overlapping_gap:?}"
                            );
                            param_locals.copy_within(args_overlapping_gap, gap_end);
                        }
                        // Nil-fill the now-vacant optional parameter slots
                        param_locals[gap_start..gap_end].fill(Qnil);
                    }
                }

                // Increment a compile error counter for --zjit-stats
                if get_option!(stats) {
                    incr_counter_by(exit_counter_for_compile_error(compile_error), 1);
                }
            }

            // If we already know we can't compile the ISEQ, or there is insufficient native
            // stack space, fail early without cb.mark_all_executable().
            // TODO: Alan thinks the payload status part of this check can happen without the VM lock, since the whole
            // code path can be made read-only. But you still need the check as is while holding the VM lock in any case.
            let cb = ZJITState::get_code_block();
            let native_stack_full = unsafe { rb_ec_stack_check(ec as _) } != 0;
            let payload = get_or_create_iseq_payload(iseq);
            // cfp is the callee's (this ISEQ's) frame here, so its method entry gives
            // the owning class and thus whether `self` is always a heap object.
            let cme = unsafe { rb_vm_frame_method_entry(cfp) };
            payload.self_is_heap_object = !cme.is_null()
                && iseq_self_is_heap_object(iseq, unsafe { (*cme).owner });
            let last_status = payload.versions.last().map(|version| &unsafe { version.as_ref() }.status);
            let compile_error = match last_status {
                Some(IseqStatus::CantCompile(err)) => Some(err),
                _ if cb.has_dropped_bytes() => Some(&CompileError::OutOfMemory),
                _ if native_stack_full => {
                    incr_counter!(skipped_native_stack_full);
                    Some(&CompileError::NativeStackTooLarge)
                },
                _ => None,
            };
            if let Some(compile_error) = compile_error {
                // We'll use this Rc again, so increment the ref count decremented by from_raw.
                unsafe { Rc::increment_strong_count(iseq_call_ptr as *const IseqCall); }

                prepare_for_exit(iseq, cfp, sp, argc, num_opts_filled, compile_error);
                return ZJITState::get_materialize_exit_trampoline_with_counter().raw_ptr(cb);
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

                prepare_for_exit(iseq, cfp, sp, argc, num_opts_filled, &compile_error);
                ZJITState::get_materialize_exit_trampoline_with_counter()
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
    trace_compile_phase("compile_stub", || {
        iseq_call.regenerate(cb, |asm| {
            asm_comment!(asm, "call compiled function: {}", iseq_get_location(iseq, 0));
            asm.ccall_into(C_RET_OPND, code_addr, vec![]);
        });
    });

    Ok(jit_entry_ptr)
}

/// Compile a stub for an ISEQ called by SendDirect
fn gen_function_stub(cb: &mut CodeBlock, iseq_call: IseqCallRef) -> Result<CodePtr, CompileError> {
    let (mut asm, scratch_reg) = Assembler::new_with_scratch_reg();
    asm.new_block_without_id("gen_function_stub");
    asm_comment!(asm, "Stub: {}", iseq_get_location(iseq_call.iseq.get(), 0));

    // If the stubbed ISEQ fails to compile, function_stub_hit exits to the
    // interpreter with this callee frame. Direct JIT-to-JIT calls pass arguments
    // in C argument registers, so spill the packed argument locals first. The
    // fallback path will reshape these around any optional positional gaps.
    let argc = iseq_call.argc.to_usize();
    assert!(argc < C_ARG_OPNDS.len(), "SendDirect must fit receiver plus arguments in C argument registers");
    let local_size = unsafe { get_iseq_body_local_table_size(iseq_call.iseq.get()) }.to_usize();
    for arg_idx in 0..argc {
        asm.store(
            Opnd::mem(64, SP, -local_size_and_idx_to_bp_offset(local_size, arg_idx) * SIZEOF_VALUE_I32),
            C_ARG_OPNDS[arg_idx + 1],
        );
    }

    // Call function_stub_hit using the shared trampoline. See `gen_function_stub_hit_trampoline`.
    // Use load_into instead of mov, which is split on arm64, to avoid clobbering ALLOC_REGS.
    asm.load_into(scratch_reg, Opnd::const_ptr(Rc::into_raw(iseq_call)));
    asm.cpush(scratch_reg);
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
    asm.new_block_without_id("function_stub_hit_trampoline");
    asm_comment!(asm, "function_stub_hit trampoline");

    asm.cpop_into(scratch_reg);

    // Maintain alignment for x86_64, and set up a frame for arm64 properly
    asm.frame_setup(&[]);

    asm_comment!(asm, "preserve argument registers");

    for pair in ALLOC_REGS.chunks(2) {
        match *pair {
            [reg0, reg1] => {
                asm.cpush_pair(Opnd::Reg(reg0), Opnd::Reg(reg1));
            }
            [reg] => {
                asm.cpush(Opnd::Reg(reg));
            }
            _ => unreachable!("chunks(2)")
        }
    }
    if cfg!(target_arch = "x86_64") && ALLOC_REGS.len() % 2 == 1 {
        asm.cpush(Opnd::Reg(ALLOC_REGS[0])); // maintain alignment for x86_64
    }

    // We can't directly pass the scratch register in to the ccall because
    // we're going to have parallel move automatically handle coping registers
    // in to the C calling convention and the parallel move algorithm needs
    // a scratch register to break any cycles.  If we use the scratch register
    // as a C call parameter, then parallel move wouldn't be able to break
    // cycles without clobbering something
    asm.mov(C_ARG_OPNDS[0], scratch_reg);
    // Compile the stubbed ISEQ
    let jump_addr = asm_ccall!(asm, function_stub_hit, C_ARG_OPNDS[0], CFP, SP, EC);
    asm.mov(scratch_reg, jump_addr);

    asm_comment!(asm, "restore argument registers");
    if cfg!(target_arch = "x86_64") && ALLOC_REGS.len() % 2 == 1 {
        asm.cpop_into(Opnd::Reg(ALLOC_REGS[0]));
    }

    for pair in ALLOC_REGS.chunks(2).rev() {
        match *pair {
            [reg] => {
                asm.cpop_into(Opnd::Reg(reg));
            }
            [reg0, reg1] => {
                asm.cpop_pair_into(Opnd::Reg(reg1), Opnd::Reg(reg0));
            }
            _ => unreachable!("chunks(2)")
        }
    }

    // Discard the current frame since the JIT function will set it up again
    asm.frame_teardown(&[]);

    // Jump to scratch_reg so that cpop_into() doesn't clobber it
    asm.jmp_opnd(scratch_reg);

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        register_current_code_range_with_perf(cb, "function_stub_hit trampoline", code_ptr);
        code_ptr
    })
}

/// Generate a trampoline that is used when a function exits without restoring PC and the stack
pub fn gen_exit_trampoline(cb: &mut CodeBlock) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();
    asm.new_block_without_id("exit_trampoline");

    asm_comment!(asm, "side-exit trampoline");
    asm.frame_teardown(&[]); // matching the setup in gen_entry_point()
    asm.cret(Qundef.into());

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        register_current_code_range_with_perf(cb, "exit trampoline", code_ptr);
        code_ptr
    })
}

/// Generate a trampoline that materializes ZJIT frames before unwinding native frames.
pub fn gen_materialize_exit_trampoline(cb: &mut CodeBlock, exit_trampoline: CodePtr) -> Result<CodePtr, CompileError> {
    unsafe extern "C" {
        fn rb_zjit_materialize_frames(ec: EcPtr, cfp: CfpPtr);
    }

    let mut asm = Assembler::new();
    asm.new_block_without_id("materialize_exit_trampoline");

    asm_comment!(asm, "clear JITFrame materialized by exit code");
    asm.store(Opnd::mem(64, CFP, RUBY_OFFSET_CFP_JIT_RETURN), 0.into());

    asm_comment!(asm, "materialize ZJIT frames");
    asm_ccall!(asm, rb_zjit_materialize_frames, EC, CFP);
    asm.jmp(Target::CodePtr(exit_trampoline));

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        register_current_code_range_with_perf(cb, "materialize_exit trampoline", code_ptr);
        code_ptr
    })
}

/// Generate a trampoline that increments exit_compilation_failure and jumps to materialize_exit_trampoline.
pub fn gen_materialize_exit_trampoline_with_counter(cb: &mut CodeBlock, materialize_exit_trampoline: CodePtr) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();
    asm.new_block_without_id("materialize_exit_trampoline_with_counter");

    asm_comment!(asm, "function stub exit trampoline");
    gen_incr_counter(&mut asm, exit_compile_error);
    asm.jmp(Target::CodePtr(materialize_exit_trampoline));

    asm.compile(cb).map(|(code_ptr, gc_offsets)| {
        assert_eq!(gc_offsets.len(), 0);
        register_current_code_range_with_perf(cb, "materialize_exit_with_counter trampoline", code_ptr);
        code_ptr
    })
}

/// Reserve native stack space and write operands into it.
fn gen_push_opnds(jit: &JITState, asm: &mut Assembler, opnds: &[Opnd]) -> lir::Opnd {
    let argv = if opnds.len() > 0 {
        // Make sure the Assembler will reserve a sufficient stack size for given opnds
        asm_comment!(asm, "allocate space on C stack for {} values", opnds.len());
        asm.alloc_stack(jit, opnds.len())
    } else {
        asm_comment!(asm, "no opnds to allocate");
        Opnd::UImm(0)
    };

    // Write operands into stack slots allocated by asm.alloc_stack()
    for (idx, &opnd) in opnds.iter().enumerate() {
        asm.mov(Opnd::mem(VALUE_BITS, argv, idx as i32 * SIZEOF_VALUE_I32), opnd);
    }

    argv
}

fn gen_toregexp(jit: &mut JITState, asm: &mut Assembler, function: &Function, opt: usize, values: Vec<Opnd>, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);

    let first_opnd_ptr = gen_push_opnds(jit, asm, &values);
    asm_ccall!(asm, rb_reg_new_from_values, values.len().into(), first_opnd_ptr, opt.into())
}

fn gen_string_concat(jit: &mut JITState, asm: &mut Assembler, function: &Function, strings: Vec<Opnd>, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);

    let first_string_ptr = gen_push_opnds(jit, asm, &strings);
    asm_ccall!(asm, rb_str_concat_literals, strings.len().into(), first_string_ptr)
}

// Generate RSTRING_PTR
fn get_string_ptr(asm: &mut Assembler, string: Opnd) -> Opnd {
    asm_comment!(asm, "get string pointer for embedded or heap");
    let string = asm.load_mem(string);
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

fn gen_string_append(jit: &mut JITState, asm: &mut Assembler, function: &Function, string: Opnd, val: Opnd, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_str_buf_append, string, val)
}

fn gen_string_append_codepoint(jit: &mut JITState, asm: &mut Assembler, function: &Function, string: Opnd, val: Opnd, state: &FrameState) -> Opnd {
    gen_prepare_non_leaf_call(jit, asm, function, state);
    asm_ccall!(asm, rb_jit_str_concat_codepoint, string, val)
}

/// Generate a JIT entry that just increments exit_compilation_failure and exits
fn gen_compile_error_counter(cb: &mut CodeBlock, compile_error: &CompileError) -> Result<CodePtr, CompileError> {
    let mut asm = Assembler::new();
    asm.new_block_without_id("compile_error_counter");
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
    /// Allocate stack space on top of the stack slots reserved for JITFrame,
    /// and return a pointer to the allocated space.
    fn alloc_stack(&mut self, jit: &JITState, stack_size: usize) -> Opnd {
        let total_stack_size = self.stack_state.reserve_stack_slots(jit.jit_frame_size, stack_size);
        self.sub(NATIVE_BASE_PTR, (SIZEOF_VALUE * total_stack_size).into())
    }

    /// Emits a load for memory based operands and returns a vreg,
    /// otherwise returns recv.
    fn load_mem(&mut self, recv: Opnd) -> Opnd {
        match recv {
            Opnd::VReg { .. } | Opnd::Reg(_) => recv,
            _ => self.load(recv),
        }
    }

    /// Emits a load for constant based operands and returns a vreg,
    /// otherwise returns recv.
    fn load_imm(&mut self, recv: Opnd) -> Opnd {
        match recv {
            Opnd::Value { .. } | Opnd::UImm(_) | Opnd::Imm(_) => self.load(recv),
            _ => recv,
        }
    }

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
    /// Index that corresponds to an entry in [crate::cruby::IseqParameters::opt_table_slice]
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

    /// Index that corresponds to an entry in [crate::cruby::IseqParameters::opt_table_slice]
    jit_entry_idx: u16,

    /// Argument count passing to the HIR function
    argc: u16,

    /// Position where the call instruction starts
    start_addr: Cell<Option<CodePtr>>,

    /// Position where the call instruction ends (exclusive)
    end_addr: Cell<Option<CodePtr>>,
}

pub type IseqCallRef = Rc<IseqCall>;

impl IseqCall {
    /// Allocate a new IseqCall
    fn new(iseq: IseqPtr, jit_entry_idx: u16, argc: u16) -> IseqCallRef {
        let iseq_call = IseqCall {
            iseq: Cell::new(iseq),
            start_addr: Cell::new(None),
            end_addr: Cell::new(None),
            jit_entry_idx,
            argc,
        };
        Rc::new(iseq_call)
    }

    /// Regenerate a IseqCall with a given callback
    fn regenerate(&self, cb: &mut CodeBlock, callback: impl Fn(&mut Assembler)) {
        cb.with_write_ptr(self.start_addr.get().expect("expected a start address"), |cb| {
            let mut asm = Assembler::new();
            asm.new_block_without_id("regenerate");
            callback(&mut asm);
            asm.compile(cb).unwrap();
            assert_eq!(self.end_addr.get().unwrap(), cb.get_write_ptr());
        });
    }
}

type PerfSymbol = Rc<RefCell<Option<(CodePtr, String)>>>;

/// Start a HIR perf symbol range when --zjit-perf=hir is enabled.
fn hir_perf_symbol_range_start(asm: &mut Assembler, insn: &Insn) -> Option<PerfSymbol> {
    if get_option!(perf) == Some(PerfMap::HIR) {
        let insn_name = format!("{insn}").split_whitespace().next().unwrap().to_string();
        Some(perf_symbol_range_start(asm, &insn_name))
    } else {
        None
    }
}

/// Mark the start of a perf symbol range via pos_marker.
/// Returns a handle to pass to perf_symbol_range_end.
pub fn perf_symbol_range_start(asm: &mut Assembler, symbol_name: &str) -> PerfSymbol {
    let symbol_name = symbol_name.to_string();
    let perf_symbol: PerfSymbol = Rc::new(RefCell::new(None));
    let current = perf_symbol.clone();
    asm.pos_marker(move |start, _| {
        let mut current = current.borrow_mut();
        assert!(current.is_none(), "perf symbol range already open");
        *current = Some((start, symbol_name.clone()));
    });
    perf_symbol
}

/// Mark the end of a perf symbol range via pos_marker.
pub fn perf_symbol_range_end(asm: &mut Assembler, perf_symbol: &PerfSymbol) {
    let current = perf_symbol.clone();
    asm.pos_marker(move |end, cb| {
        if let Some((start, name)) = current.borrow_mut().take() {
            let start_addr = start.raw_addr(cb);
            let code_size = end.raw_addr(cb) - start_addr;
            register_with_perf(name, start_addr, code_size);
        }
    });
}

/// Mark the end of a perf symbol range at the end of the current LIR block.
pub fn perf_symbol_range_end_at_block_end(asm: &mut Assembler, perf_symbol: &PerfSymbol) {
    let current = perf_symbol.clone();
    asm.pos_marker_at_block_end(move |end, cb| {
        if let Some((start, name)) = current.borrow_mut().take() {
            let start_addr = start.raw_addr(cb);
            let end_addr = end.raw_addr(cb);
            // A terminator's jump can be removed when it targets the next
            // linear block, leaving no code between the range start and the
            // block-end marker. Skip zero-sized perf map entries.
            if start_addr < end_addr {
                register_with_perf(name, start_addr, end_addr - start_addr);
            }
        }
    });
}

#[cfg(test)]
#[path = "codegen_tests.rs"]
mod tests;
