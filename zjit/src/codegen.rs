use crate::{
    asm::CodeBlock,
    backend::lir::*,
    cruby::*,
    debug,
    hir::{Function, Insn::*, InsnId},
    virtualmem::CodePtr
};
#[cfg(feature = "disasm")]
use crate::get_option;

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
        if !matches!(*insn, Snapshot { .. }) {
            asm_comment!(asm, "Insn: {:04} {:?}", insn_idx, insn);
        }
        match *insn {
            Const { val } => gen_const(&mut jit, insn_id, val),
            Return { val } => gen_return(&jit, &mut asm, val)?,
            Snapshot { .. } => {}, // we don't need to do anything for this instruction at the moment
            _ => {
                debug!("ZJIT: gen_function: unexpected insn {:?}", insn);
                return None;
            }
        }
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
