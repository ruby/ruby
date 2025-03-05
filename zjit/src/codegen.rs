use crate::{
    asm::CodeBlock, backend::lir::{asm_comment, Assembler, Opnd, Target, CFP, C_ARG_OPNDS, EC, SP}, cruby::*, debug, hir::{Const, FrameState, Function, Insn, InsnId}, hir_type::{types::Fixnum, Type}, virtualmem::CodePtr
};

/// Ephemeral code generation state
struct JITState {
    /// Instruction sequence for the compiling method
    iseq: IseqPtr,

    /// Low-level IR Operands indexed by High-level IR's Instruction ID
    opnds: Vec<Option<Opnd>>,
}

impl JITState {
    fn new(iseq: IseqPtr, insn_len: usize) -> Self {
        JITState {
            iseq,
            opnds: vec![None; insn_len],
        }
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
        let insn_id = InsnId(insn_idx);
        if !matches!(*insn, Insn::Snapshot { .. }) {
            asm_comment!(asm, "Insn: {:04} {:?}", insn_idx, insn);
        }
        match insn {
            Insn::Const { val: Const::Value(val) } => gen_const(&mut jit, insn_id, *val),
            Insn::Snapshot { .. } => {}, // we don't need to do anything for this instruction at the moment
            Insn::Return { val } => gen_return(&jit, &mut asm, *val)?,
            Insn::FixnumAdd { left, right, state } => gen_fixnum_add(&mut jit, &mut asm, insn_id, *left, *right, state)?,
            Insn::GuardType { val, guard_type, state } => gen_guard_type(&mut jit, &mut asm, insn_id, *val, *guard_type, state)?,
            Insn::PatchPoint(_) => {}, // For now, rb_zjit_bop_redefined() panics. TODO: leave a patch point and fix rb_zjit_bop_redefined()
            _ => {
                debug!("ZJIT: gen_function: unexpected insn {:?}", insn);
                return None;
            }
        }
        debug!("Compiled insn: {:04} {:?}", insn_idx, insn);
    }

    // Generate code if everything can be compiled
    let start_ptr = asm.compile(cb).map(|(start_ptr, _)| start_ptr);
    cb.mark_all_executable();

    start_ptr
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
fn gen_const(jit: &mut JITState, insn_id: InsnId, val: VALUE) {
    // Just remember the constant value and generate nothing
    jit.opnds[insn_id.0] = Some(Opnd::Value(val));
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
fn gen_fixnum_add(jit: &mut JITState, asm: &mut Assembler, insn_id: InsnId, left: InsnId, right: InsnId, state: &FrameState) -> Option<()> {
    let left_opnd = jit.opnds[left.0]?;
    let right_opnd = jit.opnds[right.0]?;

    // Load left into a register if left is a constant. The backend doesn't support sub(imm, imm).
    let left_reg = match left_opnd {
        Opnd::Value(_) => asm.load(left_opnd),
        _ => left_opnd,
    };

    // Add arg0 + arg1 and test for overflow
    let left_untag = asm.sub(left_reg, Opnd::Imm(1));
    let out_val = asm.add(left_untag, right_opnd);
    asm.jo(Target::SideExit(state.clone()));

    jit.opnds[insn_id.0] = Some(out_val);
    Some(())
}

/// Compile a type check with a side exit
fn gen_guard_type(jit: &mut JITState, asm: &mut Assembler, insn_id: InsnId, val: InsnId, guard_type: Type, state: &FrameState) -> Option<()> {
    let opnd = jit.opnds[val.0]?;
    if guard_type.is_subtype(Fixnum) {
        // Load opnd into a register if opnd is a constant. The backend doesn't support test(imm, imm) yet.
        let opnd_reg = match opnd {
            Opnd::Value(_) => asm.load(opnd),
            _ => opnd,
        };

        // Check if opnd is Fixnum
        asm.test(opnd_reg, Opnd::UImm(RUBY_FIXNUM_FLAG as u64));
        asm.jz(Target::SideExit(state.clone()));
    } else {
        unimplemented!("unsupported type: {guard_type}");
    }

    jit.opnds[insn_id.0] = Some(opnd);
    Some(())
}
