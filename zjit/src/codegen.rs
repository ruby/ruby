use crate::state::ZJITState;
use crate::{asm::CodeBlock, cruby::*, options::debug, virtualmem::CodePtr};
use crate::invariants::{iseq_escapes_ep, track_no_ep_escape_assumption};
use crate::backend::lir::{self, asm_comment, Assembler, Opnd, Target, CFP, C_ARG_OPNDS, C_RET_OPND, EC, SP};
use crate::hir;
use crate::hir::{Const, FrameState, Function, Insn, InsnId};
use crate::hir_type::{types::Fixnum, Type};

/// Ephemeral code generation state
struct JITState {
    /// Instruction sequence for the method being compiled
    iseq: IseqPtr,

    /// Low-level IR Operands indexed by High-level IR's Instruction ID
    opnds: Vec<Option<Opnd>>,
}

impl JITState {
    /// Create a new JITState instance
    fn new(iseq: IseqPtr, insn_len: usize) -> Self {
        JITState {
            iseq,
            opnds: vec![None; insn_len],
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

    /// Assume that this ISEQ doesn't escape EP. Return false if it's known to escape EP.
    fn assume_no_ep_escape(&mut self) -> bool {
        if iseq_escapes_ep(self.iseq) {
            return false;
        }
        track_no_ep_escape_assumption(self.iseq);
        true
    }
}

/// Generate JIT code for a given ISEQ, which takes EC and CFP as its arguments.
#[unsafe(no_mangle)]
pub extern "C" fn rb_zjit_iseq_gen_entry_point(iseq: IseqPtr, _ec: EcPtr) -> *const u8 {
    let code_ptr = iseq_gen_entry_point(iseq);
    if ZJITState::assert_compiles_enabled() && code_ptr == std::ptr::null() {
        let iseq_location = iseq_get_location(iseq, 0);
        panic!("Failed to compile: {iseq_location}");
    }
    code_ptr
}

fn iseq_gen_entry_point(iseq: IseqPtr) -> *const u8 {
    // Do not test the JIT code in HIR tests
    if cfg!(test) {
        return std::ptr::null();
    }

    // Take a lock to avoid writing to ISEQ in parallel with Ractors.
    // with_vm_lock() does nothing if the program doesn't use Ractors.
    with_vm_lock(src_loc!(), || {
        // Compile ISEQ into High-level IR
        let ssa = match hir::iseq_to_hir(iseq) {
            Ok(ssa) => ssa,
            Err(err) => {
                debug!("ZJIT: iseq_to_hir: {:?}", err);
                return std::ptr::null();
            }
        };

        // Compile High-level IR into machine code
        let cb = ZJITState::get_code_block();
        match gen_function(cb, &ssa, iseq) {
            Some(start_ptr) => start_ptr.raw_ptr(cb),

            // Compilation failed, continue executing in the interpreter only
            None => std::ptr::null(),
        }
    })
}

/// Compile High-level IR into machine code
fn gen_function(cb: &mut CodeBlock, function: &Function, iseq: IseqPtr) -> Option<CodePtr> {
    // Set up special registers
    let mut jit = JITState::new(iseq, function.insns.len());
    let mut asm = Assembler::new();
    gen_entry_prologue(&jit, &mut asm);

    // Compile each instruction in the IR
    for (insn_idx, insn) in function.insns.iter().enumerate() {
        if gen_insn(&mut jit, &mut asm, function, InsnId(insn_idx), insn).is_none() {
            debug!("Failed to compile insn: {:04} {:?}", insn_idx, insn);
            return None;
        }
    }

    // Generate code if everything can be compiled
    let start_ptr = asm.compile(cb).map(|(start_ptr, _)| start_ptr);
    cb.mark_all_executable();

    start_ptr
}

/// Compile an instruction
fn gen_insn(jit: &mut JITState, asm: &mut Assembler, function: &Function, insn_id: InsnId, insn: &Insn) -> Option<()> {
    if !matches!(*insn, Insn::Snapshot { .. }) {
        asm_comment!(asm, "Insn: {:04} {:?}", insn_id.0, insn);
    }
    let out_opnd = match insn {
        Insn::Const { val: Const::Value(val) } => gen_const(*val),
        Insn::Param { idx } => gen_param(jit, asm, *idx)?,
        Insn::Snapshot { .. } => return Some(()), // we don't need to do anything for this instruction at the moment
        Insn::Return { val } => return Some(gen_return(&jit, asm, *val)?),
        Insn::FixnumAdd { left, right, state } => gen_fixnum_add(jit, asm, *left, *right, function.frame_state(*state))?,
        Insn::FixnumSub { left, right, state } => gen_fixnum_sub(jit, asm, *left, *right, function.frame_state(*state))?,
        // TODO(max): Remove FrameState from FixnumLt
        Insn::FixnumLt { left, right, .. } => gen_fixnum_lt(jit, asm, *left, *right)?,
        Insn::GuardType { val, guard_type, state } => gen_guard_type(jit, asm, *val, *guard_type, function.frame_state(*state))?,
        Insn::PatchPoint(_) => return Some(()), // For now, rb_zjit_bop_redefined() panics. TODO: leave a patch point and fix rb_zjit_bop_redefined()
        _ => {
            debug!("ZJIT: gen_function: unexpected insn {:?}", insn);
            return None;
        }
    };

    // If the instruction has an output, remember it in jit.opnds
    jit.opnds[insn_id.0] = Some(out_opnd);

    Some(())
}

/// Compile an interpreter entry block to be inserted into an ISEQ
fn gen_entry_prologue(jit: &JITState, asm: &mut Assembler) {
    asm_comment!(asm, "YJIT entry point: {}", iseq_get_location(jit.iseq, 0));
    asm.frame_setup();

    // Save the registers we'll use for CFP, EP, SP
    asm.cpush(CFP);
    asm.cpush(EC);
    asm.cpush(SP);

    // EC and CFP are pased as arguments
    asm.mov(EC, C_ARG_OPNDS[0]);
    asm.mov(CFP, C_ARG_OPNDS[1]);

    // Load the current SP from the CFP into REG_SP
    asm.mov(SP, Opnd::mem(64, CFP, RUBY_OFFSET_CFP_SP));

    // TODO: Support entry chain guard when ISEQ has_opt
}

/// Compile a constant
fn gen_const(val: VALUE) -> Opnd {
    // Just propagate the constant value and generate nothing
    Opnd::Value(val)
}

/// Compile a method/block paramter read. For now, it only supports method parameters.
fn gen_param(jit: &mut JITState, asm: &mut Assembler, local_idx: usize) -> Option<lir::Opnd> {
    let ep_offset = local_idx_to_ep_offset(jit.iseq, local_idx);

    let local_opnd = if jit.assume_no_ep_escape() {
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
    };

    Some(local_opnd)
}

/// Compile code that exits from JIT code with a return value
fn gen_return(jit: &JITState, asm: &mut Assembler, val: InsnId) -> Option<()> {
    // Pop the current frame (ec->cfp++)
    // Note: the return PC is already in the previous CFP
    asm_comment!(asm, "pop stack frame");
    let incr_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, incr_cfp);
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // Set a return value to the register. We do this before popping SP, EC,
    // and CFP registers because ret_val may depend on them.
    let ret_val = jit.opnds[val.0]?;
    asm.mov(C_RET_OPND, ret_val);

    asm_comment!(asm, "exit from leave");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);
    asm.frame_teardown();
    asm.cret(C_RET_OPND);

    Some(())
}

/// Compile Fixnum + Fixnum
fn gen_fixnum_add(jit: &mut JITState, asm: &mut Assembler, left: InsnId, right: InsnId, state: &FrameState) -> Option<lir::Opnd> {
    let left_opnd = jit.get_opnd(left)?;
    let right_opnd = jit.get_opnd(right)?;

    // Add left + right and test for overflow
    let left_untag = asm.sub(left_opnd, Opnd::Imm(1));
    let out_val = asm.add(left_untag, right_opnd);
    asm.jo(Target::SideExit(state.clone()));

    Some(out_val)
}

/// Compile Fixnum < Fixnum
fn gen_fixnum_lt(jit: &mut JITState, asm: &mut Assembler, left: InsnId, right: InsnId) -> Option<lir::Opnd> {
    let left_opnd = jit.get_opnd(left)?;
    let right_opnd = jit.get_opnd(right)?;
    asm.cmp(left_opnd, right_opnd);
    let out_val = asm.csel_l(Qtrue.into(), Qfalse.into());
    Some(out_val)
}

/// Compile Fixnum - Fixnum
fn gen_fixnum_sub(jit: &mut JITState, asm: &mut Assembler, left: InsnId, right: InsnId, state: &FrameState) -> Option<lir::Opnd> {
    let left_opnd = jit.get_opnd(left)?;
    let right_opnd = jit.get_opnd(right)?;

    // Subtract left - right and test for overflow
    let val_untag = asm.sub(left_opnd, right_opnd);
    asm.jo(Target::SideExit(state.clone()));
    let out_val = asm.add(val_untag, Opnd::Imm(1));

    Some(out_val)
}

/// Compile a type check with a side exit
fn gen_guard_type(jit: &mut JITState, asm: &mut Assembler, val: InsnId, guard_type: Type, state: &FrameState) -> Option<lir::Opnd> {
    let opnd = jit.get_opnd(val)?;
    if guard_type.is_subtype(Fixnum) {
        // Check if opnd is Fixnum
        asm.test(opnd, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));
        asm.jz(Target::SideExit(state.clone()));
    } else {
        unimplemented!("unsupported type: {guard_type}");
    }
    Some(opnd)
}

/// Inverse of ep_offset_to_local_idx(). See ep_offset_to_local_idx() for details.
fn local_idx_to_ep_offset(iseq: IseqPtr, local_idx: usize) -> i32 {
    let local_table_size: i32 = unsafe { get_iseq_body_local_table_size(iseq) }
        .try_into()
        .unwrap();
    local_table_size - local_idx as i32 - 1 + VM_ENV_DATA_SIZE as i32
}
