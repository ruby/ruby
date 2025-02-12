use crate::{asm::CodeBlock, backend::ir::*, cruby::*};

/// Compile code that pops a frame and returns Qnil
pub fn gen_leave(cb: &mut CodeBlock) {
    let mut asm = Assembler::new();

    // rdi: EC, rsi: CFP
    let ec = C_ARG_OPNDS[0];
    let cfp = C_ARG_OPNDS[1];

    // Pop frame: CFP = CFP + RUBY_SIZEOF_CONTROL_FRAME
    let incr_cfp = asm.add(cfp, RUBY_SIZEOF_CONTROL_FRAME.into());
    asm.mov(cfp, incr_cfp);

    // Set ec->cfp: *(EC + RUBY_OFFSET_EC_CFP) = CFP
    asm.mov(Opnd::mem(64, ec, RUBY_OFFSET_EC_CFP), cfp);

    // Return Qnil
    asm.cret(Qnil.into());

    asm.compile_with_regs(cb, Assembler::get_alloc_regs());
    cb.mark_all_executable();
}
