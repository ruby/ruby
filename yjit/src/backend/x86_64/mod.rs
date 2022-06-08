#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use crate::asm::{CodeBlock};
use crate::asm::x86_64::*;
use crate::codegen::{JITState};
use crate::cruby::*;
use crate::backend::ir::*;

// Use the x86 register type for this platform
pub type Reg = X86Reg;

// Callee-saved registers
pub const _CFP: Opnd = Opnd::Reg(R13_REG);
pub const _EC: Opnd = Opnd::Reg(R12_REG);
pub const _SP: Opnd = Opnd::Reg(RBX_REG);

// C return value register on this platform
pub const RET_REG: Reg = RAX_REG;

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
    /// Get the list of registers from which we can allocate on this platform
    pub fn get_scratch_regs() -> Vec<Reg>
    {
        vec![
            RAX_REG,
            RCX_REG,
        ]
    }

    /// Emit platform-specific machine code
    fn x86_split(mut self) -> Assembler
    {
        let live_ranges: Vec<usize> = std::mem::take(&mut self.live_ranges);

        self.transform_insns(|asm, index, op, opnds, target| {
            match op {
                Op::Add | Op::Sub | Op::And => {
                    match opnds.as_slice() {
                        // Instruction output whose live range spans beyond this instruction
                        [Opnd::InsnOut(out_idx), _] => {
                            if live_ranges[*out_idx] > index {
                                let opnd0 = asm.load(opnds[0]);
                                asm.push_insn(op, vec![opnd0, opnds[1]], None);
                                return;
                            }
                        },

                        [Opnd::Mem(_), _] => {
                            let opnd0 = asm.load(opnds[0]);
                            asm.push_insn(op, vec![opnd0, opnds[1]], None);
                            return;
                        },

                        _ => {}
                    }
                },
                _ => {}
            };

            asm.push_insn(op, opnds, target);
        })
    }

    /// Emit platform-specific machine code
    pub fn x86_emit(&mut self, cb: &mut CodeBlock) -> Vec<u32>
    {
        // List of GC offsets
        let mut gc_offsets: Vec<u32> = Vec::new();

        // For each instruction
        for insn in &self.insns {
            match insn.op {
                Op::Comment => {
                    if cfg!(feature = "asm_comments") {
                        cb.add_comment(&insn.text.as_ref().unwrap());
                    }
                },

                Op::Label => {},

                Op::Add => {
                    // FIXME: this fails because insn.out is none sometimes
                    //assert_eq!(insn.out, insn.opnds[0]);
                    add(cb, insn.opnds[0].into(), insn.opnds[1].into())
                },

                Op::Store => mov(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                // This assumes only load instructions can contain references to GC'd Value operands
                Op::Load => {
                    mov(cb, insn.out.into(), insn.opnds[0].into());

                    // If the value being loaded is a heap object
                    if let Opnd::Value(val) = insn.opnds[0] {
                        if !val.special_const_p() {
                            // The pointer immediate is encoded as the last part of the mov written out
                            let ptr_offset: u32 = (cb.get_write_pos() as u32) - (SIZEOF_VALUE as u32);
                            gc_offsets.push(ptr_offset);
                        }
                    }
                },

                Op::Mov => mov(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                // Load effective address
                Op::Lea => lea(cb, insn.out.into(), insn.opnds[0].into()),

                // Test and set flags
                Op::Test => test(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                /*
                Cmp,
                Jnz,
                Jbe,
                */

                // C function call
                Op::CCall => {
                    // Temporary
                    assert!(insn.opnds.len() < C_ARG_REGS.len());

                    // For each operand
                    for (idx, opnd) in insn.opnds.iter().enumerate() {
                        mov(cb, C_ARG_REGS[idx], insn.opnds[idx].into());
                    }
                },

                Op::CRet => {
                    // TODO: bias allocation towards return register
                    if insn.opnds[0] != Opnd::Reg(RET_REG) {
                        mov(cb, RAX, insn.opnds[0].into());
                    }

                    ret(cb);
                }

                _ => panic!("unsupported instruction passed to x86 backend: {:?}", insn.op)
            };
        }

        gc_offsets
    }

    /// Optimize and compile the stored instructions
    pub fn compile_with_regs(self, cb: &mut CodeBlock, regs: Vec<Reg>) -> Vec<u32>
    {
        self
        .x86_split()
        .split_loads()
        .alloc_regs(regs)
        .x86_emit(cb)
    }
}
