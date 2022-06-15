#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use crate::asm::{CodeBlock};
use crate::asm::x86_64::*;
use crate::codegen::{JITState};
use crate::cruby::*;
use crate::backend::ir::{Assembler, Opnd, Target, Op, Mem};

// Use the x86 register type for this platform
pub type Reg = X86Reg;

// Callee-saved registers
pub const _CFP: Opnd = Opnd::Reg(R13_REG);
pub const _EC: Opnd = Opnd::Reg(R12_REG);
pub const _SP: Opnd = Opnd::Reg(RBX_REG);

// C argument registers on this platform
pub const _C_ARG_OPNDS: [Opnd; 6] = [
    Opnd::Reg(RDI_REG),
    Opnd::Reg(RSI_REG),
    Opnd::Reg(RDX_REG),
    Opnd::Reg(RCX_REG),
    Opnd::Reg(R8_REG),
    Opnd::Reg(R9_REG)
];

// C return value register on this platform
pub const C_RET_REG: Reg = RAX_REG;
pub const _C_RET_OPND: Opnd = Opnd::Reg(RAX_REG);

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

    /// Split IR instructions for the x86 platform
    fn x86_split(mut self) -> Assembler
    {
        let live_ranges: Vec<usize> = std::mem::take(&mut self.live_ranges);

        self.forward_pass(|asm, index, op, opnds, target| {
            match op {
                Op::Add | Op::Sub | Op::And | Op::Not => {
                    match opnds[0] {
                        // Instruction output whose live range spans beyond this instruction
                        Opnd::InsnOut(out_idx) => {
                            if live_ranges[out_idx] > index {
                                let opnd0 = asm.load(opnds[0]);
                                asm.push_insn(op, vec![opnd0, opnds[1]], None);
                                return;
                            }
                        },

                        // We have to load memory and register operands to avoid corrupting them
                        Opnd::Mem(_) | Opnd::Reg(_) => {
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

                // Write the label at the current position
                Op::Label => {
                    cb.write_label(insn.target.unwrap().unwrap_label_idx());
                },

                Op::Add => {
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

                // Push and pop to the C stack
                Op::CPush => push(cb, insn.opnds[0].into()),
                Op::CPop => pop(cb, insn.opnds[0].into()),

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
                    if insn.opnds[0] != Opnd::Reg(C_RET_REG) {
                        mov(cb, RAX, insn.opnds[0].into());
                    }

                    ret(cb);
                }

                // Compare
                Op::Cmp => test(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                // Test and set flags
                Op::Test => test(cb, insn.opnds[0].into(), insn.opnds[1].into()),

                Op::JmpOpnd => jmp_rm(cb, insn.opnds[0].into()),

                Op::Je => je_label(cb, insn.target.unwrap().unwrap_label_idx()),

                // Atomically increment a counter at a given memory location
                Op::IncrCounter => {
                    assert!(matches!(insn.opnds[0], Opnd::Mem(_)));
                    assert!(matches!(insn.opnds[0], Opnd::UImm(_)));
                    write_lock_prefix(cb);
                    add(cb, insn.opnds[0].into(), insn.opnds[1].into());
                },

                Op::Breakpoint => int3(cb),

                _ => panic!("unsupported instruction passed to x86 backend: {:?}", insn.op)
            };
        }

        gc_offsets
    }

    /// Optimize and compile the stored instructions
    pub fn compile_with_regs(self, cb: &mut CodeBlock, regs: Vec<Reg>) -> Vec<u32>
    {
        let mut asm = self.x86_split();
        let mut asm = asm.split_loads();
        let mut asm = asm.alloc_regs(regs);

        // Create label instances in the code block
        for (idx, name) in asm.label_names.iter().enumerate() {
            dbg!("creating label, idx={}", idx);
            let label_idx = cb.new_label(name.to_string());
            assert!(label_idx == idx);
        }

        let gc_offsets = asm.x86_emit(cb);

        cb.link_labels();

        gc_offsets
    }
}
