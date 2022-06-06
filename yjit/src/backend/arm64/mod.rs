#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use crate::asm::{CodeBlock};
use crate::asm::arm64::*;
use crate::codegen::{JITState};
use crate::cruby::*;
use crate::backend::ir::*;

// Use the arm64 register type for this platform
pub type Reg = A64Reg;

// Callee-saved registers
pub const _CFP: Opnd = Opnd::Reg(X9);
pub const _EC: Opnd = Opnd::Reg(X10);
pub const _SP: Opnd = Opnd::Reg(X11);

// C return value register on this platform
pub const RET_REG: Reg = X0;

/// Map Opnd to A64Opnd
impl From<Opnd> for A64Opnd {
    fn from(opnd: Opnd) -> Self {
        match opnd {
            Opnd::UImm(val) => uimm_opnd(val),
            Opnd::Imm(val) => imm_opnd(val),
            Opnd::Reg(reg) => A64Opnd::Reg(reg),
            _ => panic!("unsupported arm64 operand type")
        }
    }
}

impl Assembler
{
    // Get the list of registers from which we can allocate on this platform
    pub fn get_scratch_regs() -> Vec<Reg>
    {
        vec![X12_REG, X13_REG]
    }

    // Split platform-specific instructions
    fn arm64_split(mut self) -> Assembler
    {
        todo!();
    }

    // Emit platform-specific machine code
    pub fn arm64_emit(&mut self, jit: &mut JITState, cb: &mut CodeBlock)
    {
        todo!();
    }

    // Optimize and compile the stored instructions
    pub fn compile_with_regs(self, jit: &mut JITState, cb: &mut CodeBlock, regs: Vec<Reg>)
    {
        self
            .arm64_split()
            .split_loads()
            .alloc_regs(regs)
            .arm64_emit(jit, cb);
    }
}
