#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use crate::asm::{CodeBlock};
use crate::asm::x86_64::*;
use crate::backend::ir::*;

// Use the x86 register type for this platform
pub type Reg = X86Reg;

// Callee-saved registers
pub const CFP: Opnd = Opnd::Reg(R13_REG);
pub const EC: Opnd = Opnd::Reg(R12_REG);
pub const SP: Opnd = Opnd::Reg(RBX_REG);

impl Assembler
{
    // Get the list of registers from which we can allocate on this platform
    pub fn get_scrach_regs() -> Vec<Reg>
    {
        vec![
            RAX_REG,
            RCX_REG,
        ]
    }

    // Emit platform-specific machine code
    pub fn target_emit(&self, cb: &mut CodeBlock)
    {



        for insn in &self.insns {


            // For each instruction, either handle it here or allow the map_insn
            // callback to handle it.
            match insn.op {
                Op::Comment => {
                },
                Op::Label => {
                },
                _ => {
                }
            };


        }




    }
}
