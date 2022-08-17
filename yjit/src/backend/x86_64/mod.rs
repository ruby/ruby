#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use std::mem::take;

use crate::asm::*;
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

            Opnd::InsnOut{..} => panic!("InsnOut operand made it past register allocation"),

            Opnd::UImm(val) => uimm_opnd(val),
            Opnd::Imm(val) => imm_opnd(val),
            Opnd::Value(VALUE(uimm)) => uimm_opnd(uimm as u64),

            // General-purpose register
            Opnd::Reg(reg) => X86Opnd::Reg(reg),

            // Memory operand with displacement
            Opnd::Mem(Mem{ base: MemBase::Reg(reg_no), num_bits, disp }) => {
                let reg = X86Reg {
                    reg_no,
                    num_bits: 64,
                    reg_type: RegType::GP
                };

                mem_opnd(num_bits, X86Opnd::Reg(reg), disp)
            }

            Opnd::None => panic!(
                "Attempted to lower an Opnd::None. This often happens when an out operand was not allocated for an instruction because the output of the instruction was not used. Please ensure you are using the output."
            ),

            _ => panic!("unsupported x86 operand type")
        }
    }
}

impl Assembler
{
    // A special scratch register for intermediate processing.
    // Note: right now this is only used by LeaLabel because label_ref accepts
    // a closure and we don't want it to have to capture anything.
    const SCRATCH0: X86Opnd = X86Opnd::Reg(R11_REG);

    /// Get the list of registers from which we can allocate on this platform
    pub fn get_alloc_regs() -> Vec<Reg>
    {
        vec![
            RAX_REG,
            RCX_REG,
        ]
    }

    /// Get a list of all of the caller-save registers
    pub fn get_caller_save_regs() -> Vec<Reg> {
        vec![RAX_REG, RCX_REG, RDX_REG, RSI_REG, RDI_REG, R8_REG, R9_REG, R10_REG, R11_REG]
    }

    // These are the callee-saved registers in the x86-64 SysV ABI
    // RBX, RSP, RBP, and R12–R15

    /// Split IR instructions for the x86 platform
    fn x86_split(mut self) -> Assembler
    {
        let live_ranges: Vec<usize> = take(&mut self.live_ranges);
        let mut asm = Assembler::new_with_label_names(take(&mut self.label_names));
        let mut iterator = self.into_draining_iter();

        while let Some((index, insn)) = iterator.next_unmapped() {
            // When we're iterating through the instructions with x86_split, we
            // need to know the previous live ranges in order to tell if a
            // register lasts beyond the current instruction. So instead of
            // using next_mapped, we call next_unmapped. When you're using the
            // next_unmapped API, you need to make sure that you map each
            // operand that could reference an old index, which means both
            // Opnd::InsnOut operands and Opnd::Mem operands with a base of
            // MemBase::InsnOut.
            //
            // You need to ensure that you only map it _once_, because otherwise
            // you'll end up mapping an incorrect index which could end up being
            // out of bounds of the old set of indices.
            //
            // We handle all of that mapping here to ensure that it's only
            // mapped once. We also handle loading Opnd::Value operands into
            // registers here so that all mapping happens in one place. We load
            // Opnd::Value operands into registers here because:
            //
            //   - Most instructions can't be encoded with 64-bit immediates.
            //   - We look for Op::Load specifically when emiting to keep GC'ed
            //     VALUEs alive. This is a sort of canonicalization.
            let mapped_opnds: Vec<Opnd> = insn.opnds.iter().map(|opnd| {
                if insn.op == Op::Load {
                    iterator.map_opnd(*opnd)
                } else if let Opnd::Value(value) = opnd {
                    // Since mov(mem64, imm32) sign extends, as_i64() makes sure
                    // we split when the extended value is different.
                    if !value.special_const_p() || imm_num_bits(value.as_i64()) > 32 {
                        asm.load(iterator.map_opnd(*opnd))
                    } else {
                        iterator.map_opnd(*opnd)
                    }
                } else {
                    iterator.map_opnd(*opnd)
                }
            }).collect();

            match insn {
                Insn { op: Op::Add | Op::Sub | Op::And | Op::Cmp | Op::Or | Op::Test | Op::Xor, opnds, target, text, pos_marker, .. } => {
                    let (opnd0, opnd1) = match (opnds[0], opnds[1]) {
                        (Opnd::Mem(_), Opnd::Mem(_)) => {
                            (asm.load(mapped_opnds[0]), asm.load(mapped_opnds[1]))
                        },
                        (Opnd::Mem(_), Opnd::UImm(value)) => {
                            // 32-bit values will be sign-extended
                            if imm_num_bits(value as i64) > 32 {
                                (asm.load(mapped_opnds[0]), asm.load(mapped_opnds[1]))
                            } else {
                                (asm.load(mapped_opnds[0]), mapped_opnds[1])
                            }
                        },
                        (Opnd::Mem(_), Opnd::Imm(value)) => {
                            if imm_num_bits(value) > 32 {
                                (asm.load(mapped_opnds[0]), asm.load(mapped_opnds[1]))
                            } else {
                                (asm.load(mapped_opnds[0]), mapped_opnds[1])
                            }
                        },
                        // Instruction output whose live range spans beyond this instruction
                        (Opnd::InsnOut { idx, .. }, _) => {
                            if live_ranges[idx] > index {
                                (asm.load(mapped_opnds[0]), mapped_opnds[1])
                            } else {
                                (mapped_opnds[0], mapped_opnds[1])
                            }
                        },
                        // We have to load memory operands to avoid corrupting them
                        (Opnd::Mem(_) | Opnd::Reg(_), _) => {
                            (asm.load(mapped_opnds[0]), mapped_opnds[1])
                        },
                        _ => (mapped_opnds[0], mapped_opnds[1])
                    };

                    asm.push_insn_parts(insn.op, vec![opnd0, opnd1], target, text, pos_marker);
                },
                // These instructions modify their input operand in-place, so we
                // may need to load the input value to preserve it
                Insn { op: Op::LShift | Op::RShift | Op::URShift, opnds, target, text, pos_marker, .. } => {
                    let (opnd0, opnd1) = match (opnds[0], opnds[1]) {
                        // Instruction output whose live range spans beyond this instruction
                        (Opnd::InsnOut { idx, .. }, _) => {
                            if live_ranges[idx] > index {
                                (asm.load(mapped_opnds[0]), mapped_opnds[1])
                            } else {
                                (mapped_opnds[0], mapped_opnds[1])
                            }
                        },
                        // We have to load memory operands to avoid corrupting them
                        (Opnd::Mem(_) | Opnd::Reg(_), _) => {
                            (asm.load(mapped_opnds[0]), mapped_opnds[1])
                        },
                        _ => (mapped_opnds[0], mapped_opnds[1])
                    };

                    asm.push_insn_parts(insn.op, vec![opnd0, opnd1], target, text, pos_marker);
                },
                Insn { op: Op::CSelZ | Op::CSelNZ | Op::CSelE | Op::CSelNE | Op::CSelL | Op::CSelLE | Op::CSelG | Op::CSelGE, target, text, pos_marker, .. } => {
                    let new_opnds = mapped_opnds.into_iter().map(|opnd| {
                        match opnd {
                            Opnd::Reg(_) | Opnd::InsnOut { .. } => opnd,
                            _ => asm.load(opnd)
                        }
                    }).collect();

                    asm.push_insn_parts(insn.op, new_opnds, target, text, pos_marker);
                },
                Insn { op: Op::Mov, .. } => {
                    match (mapped_opnds[0], mapped_opnds[1]) {
                        (Opnd::Mem(_), Opnd::Mem(_)) => {
                            // We load opnd1 because for mov, opnd0 is the output
                            let opnd1 = asm.load(mapped_opnds[1]);
                            asm.mov(mapped_opnds[0], opnd1);
                        },
                        (Opnd::Mem(_), Opnd::UImm(value)) => {
                            // 32-bit values will be sign-extended
                            if imm_num_bits(value as i64) > 32 {
                                let opnd1 = asm.load(mapped_opnds[1]);
                                asm.mov(mapped_opnds[0], opnd1);
                            } else {
                                asm.mov(mapped_opnds[0], mapped_opnds[1]);
                            }
                        },
                        (Opnd::Mem(_), Opnd::Imm(value)) => {
                            if imm_num_bits(value) > 32 {
                                let opnd1 = asm.load(mapped_opnds[1]);
                                asm.mov(mapped_opnds[0], opnd1);
                            } else {
                                asm.mov(mapped_opnds[0], mapped_opnds[1]);
                            }
                        },
                        _ => {
                            asm.mov(mapped_opnds[0], mapped_opnds[1]);
                        }
                    }
                },
                Insn { op: Op::Not, opnds, .. } => {
                    let opnd0 = match opnds[0] {
                        // If we have an instruction output whose live range
                        // spans beyond this instruction, we have to load it.
                        Opnd::InsnOut { idx, .. } => {
                            if live_ranges[idx] > index {
                                asm.load(mapped_opnds[0])
                            } else {
                                mapped_opnds[0]
                            }
                        },
                        // We have to load memory and register operands to avoid
                        // corrupting them.
                        Opnd::Mem(_) | Opnd::Reg(_) => {
                            asm.load(mapped_opnds[0])
                        },
                        // Otherwise we can just reuse the existing operand.
                        _ => mapped_opnds[0]
                    };

                    asm.not(opnd0);
                },
                _ => {
                    asm.push_insn_parts(insn.op, mapped_opnds, insn.target, insn.text, insn.pos_marker);
                }
            };

            iterator.map_insn_index(&mut asm);
        }

        asm
    }

    /// Emit platform-specific machine code
    pub fn x86_emit(&mut self, cb: &mut CodeBlock) -> Vec<u32>
    {
        //dbg!(&self.insns);

        // List of GC offsets
        let mut gc_offsets: Vec<u32> = Vec::new();

        // For each instruction
        let start_write_pos = cb.get_write_pos();
        for insn in &self.insns {
            match insn {
                Insn { op: Op::Comment, text, .. } => {
                    if cfg!(feature = "asm_comments") {
                        cb.add_comment(text.as_ref().unwrap());
                    }
                },

                // Write the label at the current position
                Insn { op: Op::Label, target, .. } => {
                    cb.write_label(target.unwrap().unwrap_label_idx());
                },

                // Report back the current position in the generated code
                Insn { op: Op::PosMarker, pos_marker, .. } => {
                    let pos = cb.get_write_ptr();
                    let pos_marker_fn = pos_marker.as_ref().unwrap();
                    pos_marker_fn(pos);
                },

                Insn { op: Op::BakeString, text, .. } => {
                    for byte in text.as_ref().unwrap().as_bytes() {
                        cb.write_byte(*byte);
                    }

                    // Add a null-terminator byte for safety (in case we pass
                    // this to C code)
                    cb.write_byte(0);
                },

                Insn { op: Op::Add, opnds, .. } => {
                    add(cb, opnds[0].into(), opnds[1].into())
                },

                Insn { op: Op::FrameSetup, .. } => {},
                Insn { op: Op::FrameTeardown, .. } => {},

                Insn { op: Op::Sub, opnds, .. } => {
                    sub(cb, opnds[0].into(), opnds[1].into())
                },

                Insn { op: Op::And, opnds, .. } => {
                    and(cb, opnds[0].into(), opnds[1].into())
                },

                Insn { op: Op::Or, opnds, .. } => {
                    or(cb, opnds[0].into(), opnds[1].into());
                },

                Insn { op: Op::Xor, opnds, .. } => {
                    xor(cb, opnds[0].into(), opnds[1].into());
                },

                Insn { op: Op::Not, opnds, .. } => {
                    not(cb, opnds[0].into());
                },

                Insn { op: Op::LShift, opnds, .. } => {
                    shl(cb, opnds[0].into(), opnds[1].into())
                },

                Insn { op: Op::RShift, opnds, .. } => {
                    sar(cb, opnds[0].into(), opnds[1].into())
                },

                Insn { op: Op::URShift, opnds, .. } => {
                    shr(cb, opnds[0].into(), opnds[1].into())
                },

                Insn { op: Op::Store, opnds, .. } => {
                    mov(cb, opnds[0].into(), opnds[1].into());
                },

                // This assumes only load instructions can contain references to GC'd Value operands
                Insn { op: Op::Load, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());

                    // If the value being loaded is a heap object
                    if let Opnd::Value(val) = opnds[0] {
                        if !val.special_const_p() {
                            // The pointer immediate is encoded as the last part of the mov written out
                            let ptr_offset: u32 = (cb.get_write_pos() as u32) - (SIZEOF_VALUE as u32);
                            gc_offsets.push(ptr_offset);
                        }
                    }
                },

                Insn { op: Op::LoadSExt, opnds, out, .. } => {
                    movsx(cb, (*out).into(), opnds[0].into());
                },

                Insn { op: Op::Mov, opnds, .. } => {
                    mov(cb, opnds[0].into(), opnds[1].into());
                },

                // Load effective address
                Insn { op: Op::Lea, opnds, out, .. } => {
                    lea(cb, (*out).into(), opnds[0].into());
                },

                // Load relative address
                Insn { op: Op::LeaLabel, out, target, .. } => {
                    let label_idx = target.unwrap().unwrap_label_idx();

                    cb.label_ref(label_idx, 7, |cb, src_addr, dst_addr| {
                        let disp = dst_addr - src_addr;
                        lea(cb, Self::SCRATCH0, mem_opnd(8, RIP, disp.try_into().unwrap()));
                    });

                    mov(cb, (*out).into(), Self::SCRATCH0);
                },

                // Push and pop to/from the C stack
                Insn { op: Op::CPush, opnds, .. } => {
                    push(cb, opnds[0].into());
                },
                Insn { op: Op::CPop, out, .. } => {
                    pop(cb, (*out).into());
                },
                Insn { op: Op::CPopInto, opnds, .. } => {
                    pop(cb, opnds[0].into());
                },

                // Push and pop to the C stack all caller-save registers and the
                // flags
                Insn { op: Op::CPushAll, .. } => {
                    let regs = Assembler::get_caller_save_regs();

                    for reg in regs {
                        push(cb, X86Opnd::Reg(reg));
                    }
                    pushfq(cb);
                },
                Insn { op: Op::CPopAll, .. } => {
                    let regs = Assembler::get_caller_save_regs();

                    popfq(cb);
                    for reg in regs.into_iter().rev() {
                        pop(cb, X86Opnd::Reg(reg));
                    }
                },

                // C function call
                Insn { op: Op::CCall, opnds, target, .. } => {
                    // Temporary
                    assert!(opnds.len() <= _C_ARG_OPNDS.len());

                    // For each operand
                    for (idx, opnd) in opnds.iter().enumerate() {
                        mov(cb, X86Opnd::Reg(_C_ARG_OPNDS[idx].unwrap_reg()), opnds[idx].into());
                    }

                    let ptr = target.unwrap().unwrap_fun_ptr();
                    call_ptr(cb, RAX, ptr);
                },

                Insn { op: Op::CRet, opnds, .. } => {
                    // TODO: bias allocation towards return register
                    if opnds[0] != Opnd::Reg(C_RET_REG) {
                        mov(cb, RAX, opnds[0].into());
                    }

                    ret(cb);
                },

                // Compare
                Insn { op: Op::Cmp, opnds, .. } => {
                    cmp(cb, opnds[0].into(), opnds[1].into());
                }

                // Test and set flags
                Insn { op: Op::Test, opnds, .. } => {
                    test(cb, opnds[0].into(), opnds[1].into());
                }

                Insn { op: Op::JmpOpnd, opnds, .. } => {
                    jmp_rm(cb, opnds[0].into());
                }

                // Conditional jump to a label
                Insn { op: Op::Jmp, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(code_ptr) => jmp_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jmp_label(cb, label_idx),
                        _ => unreachable!()
                    }
                }

                Insn { op: Op::Je, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(code_ptr) => je_ptr(cb, code_ptr),
                        Target::Label(label_idx) => je_label(cb, label_idx),
                        _ => unreachable!()
                    }
                }

                Insn { op: Op::Jne, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(code_ptr) => jne_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jne_label(cb, label_idx),
                        _ => unreachable!()
                    }
                }

                Insn { op: Op::Jl, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(code_ptr) => jl_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jl_label(cb, label_idx),
                        _ => unreachable!()
                    }
                },

                Insn { op: Op::Jbe, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(code_ptr) => jbe_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jbe_label(cb, label_idx),
                        _ => unreachable!()
                    }
                },

                Insn { op: Op::Jz, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(code_ptr) => jz_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jz_label(cb, label_idx),
                        _ => unreachable!()
                    }
                }

                Insn { op: Op::Jnz, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(code_ptr) => jnz_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jnz_label(cb, label_idx),
                        _ => unreachable!()
                    }
                }

                Insn { op: Op::Jo, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(code_ptr) => jo_ptr(cb, code_ptr),
                        Target::Label(label_idx) => jo_label(cb, label_idx),
                        _ => unreachable!()
                    }
                }

                // Atomically increment a counter at a given memory location
                Insn { op: Op::IncrCounter, opnds, .. } => {
                    assert!(matches!(opnds[0], Opnd::Mem(_)));
                    assert!(matches!(opnds[1], Opnd::UImm(_) | Opnd::Imm(_) ) );
                    write_lock_prefix(cb);
                    add(cb, opnds[0].into(), opnds[1].into());
                },

                Insn { op: Op::Breakpoint, .. } => int3(cb),

                Insn { op: Op::CSelZ, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());
                    cmovnz(cb, (*out).into(), opnds[1].into());
                },
                Insn { op: Op::CSelNZ, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());
                    cmovz(cb, (*out).into(), opnds[1].into());
                },
                Insn { op: Op::CSelE, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());
                    cmovne(cb, (*out).into(), opnds[1].into());
                },
                Insn { op: Op::CSelNE, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());
                    cmove(cb, (*out).into(), opnds[1].into());
                },
                Insn { op: Op::CSelL, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());
                    cmovge(cb, (*out).into(), opnds[1].into());
                },
                Insn { op: Op::CSelLE, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());
                    cmovg(cb, (*out).into(), opnds[1].into());
                },
                Insn { op: Op::CSelG, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());
                    cmovle(cb, (*out).into(), opnds[1].into());
                },
                Insn { op: Op::CSelGE, opnds, out, .. } => {
                    mov(cb, (*out).into(), opnds[0].into());
                    cmovl(cb, (*out).into(), opnds[1].into());
                }
                Insn { op: Op::LiveReg, .. } => (), // just a reg alloc signal, no code
                Insn { op: Op::PadEntryExit, .. } => {
                    // We assume that our Op::Jmp usage that gets invalidated is <= 5
                    let code_size: u32 = (cb.get_write_pos() - start_write_pos).try_into().unwrap();
                    if code_size < 5 {
                        nop(cb, 5 - code_size);
                    }
                }

                // We want to keep the panic here because some instructions that
                // we feed to the backend could get lowered into other
                // instructions. So it's possible that some of our backend
                // instructions can never make it to the emit stage.
                _ => panic!("unsupported instruction passed to x86 backend: {:?}", insn.op)
            };
        }

        gc_offsets
    }

    /// Optimize and compile the stored instructions
    pub fn compile_with_regs(self, cb: &mut CodeBlock, regs: Vec<Reg>) -> Vec<u32>
    {
        let mut asm = self.x86_split().alloc_regs(regs);

        // Create label instances in the code block
        for (idx, name) in asm.label_names.iter().enumerate() {
            let label_idx = cb.new_label(name.to_string());
            assert!(label_idx == idx);
        }

        let gc_offsets = asm.x86_emit(cb);

        if !cb.has_dropped_bytes() {
            cb.link_labels();
        }

        gc_offsets
    }
}
