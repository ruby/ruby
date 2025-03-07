use crate::{
    asm::CodeBlock, backend::lir, backend::lir::{asm_comment, Assembler, Opnd, Target, CFP, C_ARG_OPNDS, EC, SP}, cruby::*, debug, hir::{Const, FrameState, Function, Insn, InsnId}, hir_type::{types::Fixnum, Type}, virtualmem::CodePtr
};

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
}

/// Compile High-level IR into machine code
pub fn gen_function(cb: &mut CodeBlock, function: &Function, iseq: IseqPtr) -> Option<CodePtr> {
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
fn gen_param(jit: &JITState, asm: &mut Assembler, local_idx: usize) -> Option<lir::Opnd> {
    // Get the EP of the current CFP
    // TODO: Use the SP register and invalidate on EP escape
    let ep_opnd = Opnd::mem(64, CFP, RUBY_OFFSET_CFP_EP);
    let ep_reg = asm.load(ep_opnd);

    // Load the local variable
    // val = *(vm_get_ep(GET_EP(), level) - idx);
    let ep_offset = local_idx_to_ep_offset(jit.iseq, local_idx);
    let offs = -(SIZEOF_VALUE_I32 * ep_offset);
    let local_opnd = Opnd::mem(64, ep_reg, offs);

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

    asm_comment!(asm, "exit from leave");
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);
    asm.frame_teardown();

    // Return a value
    let ret_val = jit.opnds[val.0]?;
    asm.cret(ret_val);

    Some(())
}

/// Compile Fixnum + Fixnum
fn gen_fixnum_add(jit: &mut JITState, asm: &mut Assembler, left: InsnId, right: InsnId, state: &FrameState) -> Option<lir::Opnd> {
    let left_opnd = jit.get_opnd(left)?;
    let right_opnd = jit.get_opnd(right)?;

    // Add arg0 + arg1 and test for overflow
    let left_untag = asm.sub(left_opnd, Opnd::Imm(1));
    let out_val = asm.add(left_untag, right_opnd);
    asm.jo(Target::SideExit(state.clone()));

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
