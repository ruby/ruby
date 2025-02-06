use crate::{asm::x86_64::{add, mov, ret, RAX_REG, RDI_REG, RSI_REG}, codegen::CodeBlock, cruby::{Qnil, RUBY_OFFSET_EC_CFP, RUBY_SIZEOF_CONTROL_FRAME}};
use crate::asm::x86_64::X86Opnd::Mem;
use crate::asm::x86_64::X86Opnd::Reg;
use crate::asm::x86_64::X86Opnd::UImm;
use crate::asm::x86_64::X86UImm;
use crate::asm::x86_64::X86Mem;

// Emit x86_64 instructions into CodeBlock
// TODO: Create a module like YJIT's Assembler and consider putting this there
pub fn x86_emit(cb: &mut CodeBlock) { // TODO: take our backend IR
    // rdi: EC, rsi: CFP
    let ec = RDI_REG;
    let cfp = RSI_REG;

    // Pop frame: CFP = CFP + RUBY_SIZEOF_CONTROL_FRAME
    add(cb, Reg(cfp), UImm(X86UImm { num_bits: 64, value: RUBY_SIZEOF_CONTROL_FRAME as u64 }));

    // Set ec->cfp: *(EC + RUBY_OFFSET_EC_CFP) = CFP
    let ec_cfp = X86Mem {
        num_bits: 64,
        base_reg_no: ec.reg_no,
        idx_reg_no: None,
        scale_exp: 0,
        disp: RUBY_OFFSET_EC_CFP,
    };
    mov(cb, Mem(ec_cfp), Reg(cfp));

    // Return Qnil
    mov(cb, Reg(RAX_REG), UImm(X86UImm { num_bits: 64, value: Qnil.as_u64() }));
    ret(cb);
}
