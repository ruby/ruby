use crate::{
    asm::CodeBlock,
    backend::*,
    cruby::*,
    debug,
    hir::{self, Function, Insn::*},
    virtualmem::CodePtr
};
#[cfg(feature = "disasm")]
use crate::get_option;

/// Compile SSA IR into machine code
pub fn gen_function(cb: &mut CodeBlock, function: &Function) -> Option<CodePtr> {
    // Set up special registers
    let mut asm = Assembler::new();
    gen_entry_prologue(&mut asm);

    // Compile each instruction in the IR
    for insn in function.insns.iter() {
        match *insn {
            Snapshot { .. } => {}, // we don't need to do anything for this instruction at the moment
            Return { val } => gen_return(&mut asm, val)?,
            _ => {
                debug!("ZJIT: gen_function: unexpected insn {:?}", insn);
                return None;
            }
        }
    }

    // Generate code if everything can be compiled
    let start_ptr = cb.get_write_ptr();
    asm.compile_with_regs(cb, Assembler::get_alloc_regs()); // TODO: resurrect cache busting for arm64
    cb.mark_all_executable();

    #[cfg(feature = "disasm")]
    if get_option!(dump_disasm) {
        let end_ptr = cb.get_write_ptr();
        let disasm = crate::disasm::disasm_addr_range(start_ptr.raw_ptr(cb) as usize, end_ptr.raw_ptr(cb) as usize);
        println!("{}", disasm);
    }

    Some(start_ptr)
}

/// Compile an interpreter entry block to be inserted into an ISEQ
fn gen_entry_prologue(asm: &mut Assembler) {
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

/// Compile code that exits from JIT code with a return value
fn gen_return(asm: &mut Assembler, val: hir::Opnd) -> Option<()> {
    // Pop frame: CFP = CFP + RUBY_SIZEOF_CONTROL_FRAME
    let incr_cfp = asm.add(CFP, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(CFP, incr_cfp);

    // Set ec->cfp: *(EC + RUBY_OFFSET_EC_CFP) = CFP
    asm.mov(Opnd::mem(64, EC, RUBY_OFFSET_EC_CFP), CFP);

    // Tear down the frame
    asm.cpop_into(SP);
    asm.cpop_into(EC);
    asm.cpop_into(CFP);
    asm.frame_teardown();

    // Return a value
    let val = match val {
        hir::Opnd::Const(val) => val,
        _ => return None, // TODO: Support Opnd::Insn
    };
    asm.cret(val.into());

    Some(())
}
