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

/// Map Opnd to X86Opnd
impl From<Opnd> for X86Opnd {
    fn from(opnd: Opnd) -> Self {
        match opnd {
            // NOTE: these operand types need to be lowered first
            //Value(VALUE),       // Immediate Ruby value, may be GC'd, movable
            //InsnOut(usize),     // Output of a preceding instruction in this block

            Opnd::InsnOut(idx) => panic!("InsnOut operand made it past register allocation"),

            Opnd::None => X86Opnd::None,

            Opnd::UImm(val) => uimm_opnd(val),
            Opnd::Imm(val) => imm_opnd(val),

            // General-purpose register
            Opnd::Reg(reg) => X86Opnd::Reg(reg),

            // Memory operand with displacement
            Opnd::Mem(Mem{ num_bits, base_reg, disp }) => {
                mem_opnd(num_bits, X86Opnd::Reg(base_reg), disp)
            }

            _ => panic!("unsupported x86 operand type")
        }
    }
}

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
        // For each instruction
        for insn in &self.insns {
            match insn.op {
                Op::Comment => {},
                Op::Label => {},

                Op::Add => add(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                /*
                Load
                Store,
                */

                Op::Mov => add(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                // Test and set flags
                Op::Test => add(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                /*
                Test,
                Cmp,
                Jnz,
                Jbe,
                */

                _ => panic!("unsupported instruction passed to x86 backend")
            };
        }
    }
}
