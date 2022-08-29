#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_imports)]

use crate::asm::{CodeBlock};
use crate::asm::arm64::*;
use crate::codegen::{JITState};
use crate::cruby::*;
use crate::backend::ir::*;
use crate::virtualmem::CodePtr;

// Use the arm64 register type for this platform
pub type Reg = A64Reg;

// Callee-saved registers
pub const _CFP: Opnd = Opnd::Reg(X19_REG);
pub const _EC: Opnd = Opnd::Reg(X20_REG);
pub const _SP: Opnd = Opnd::Reg(X21_REG);

// C argument registers on this platform
pub const _C_ARG_OPNDS: [Opnd; 6] = [
    Opnd::Reg(X0_REG),
    Opnd::Reg(X1_REG),
    Opnd::Reg(X2_REG),
    Opnd::Reg(X3_REG),
    Opnd::Reg(X4_REG),
    Opnd::Reg(X5_REG)
];

// C return value register on this platform
pub const C_RET_REG: Reg = X0_REG;
pub const _C_RET_OPND: Opnd = Opnd::Reg(X0_REG);

// These constants define the way we work with Arm64's stack pointer. The stack
// pointer always needs to be aligned to a 16-byte boundary.
pub const C_SP_REG: A64Opnd = X31;
pub const C_SP_STEP: i32 = 16;

/// Map Opnd to A64Opnd
impl From<Opnd> for A64Opnd {
    fn from(opnd: Opnd) -> Self {
        match opnd {
            Opnd::UImm(value) => A64Opnd::new_uimm(value),
            Opnd::Imm(value) => A64Opnd::new_imm(value),
            Opnd::Reg(reg) => A64Opnd::Reg(reg),
            Opnd::Mem(Mem { base: MemBase::Reg(reg_no), num_bits, disp }) => {
                A64Opnd::new_mem(num_bits, A64Opnd::Reg(A64Reg { num_bits, reg_no }), disp)
            },
            Opnd::Mem(Mem { base: MemBase::InsnOut(_), .. }) => {
                panic!("attempted to lower an Opnd::Mem with a MemBase::InsnOut base")
            },
            Opnd::InsnOut { .. } => panic!("attempted to lower an Opnd::InsnOut"),
            Opnd::Value(_) => panic!("attempted to lower an Opnd::Value"),
            Opnd::None => panic!(
                "Attempted to lower an Opnd::None. This often happens when an out operand was not allocated for an instruction because the output of the instruction was not used. Please ensure you are using the output."
            ),

        }
    }
}

impl Assembler
{
    // A special scratch register for intermediate processing.
    const SCRATCH0: A64Opnd = A64Opnd::Reg(X22_REG);

    /// Get the list of registers from which we will allocate on this platform
    /// These are caller-saved registers
    /// Note: we intentionally exclude C_RET_REG (X0) from this list
    /// because of the way it's used in gen_leave() and gen_leave_exit()
    pub fn get_alloc_regs() -> Vec<Reg> {
        vec![X11_REG, X12_REG, X13_REG]
    }

    /// Get a list of all of the caller-saved registers
    pub fn get_caller_save_regs() -> Vec<Reg> {
        vec![X9_REG, X10_REG, X11_REG, X12_REG, X13_REG, X14_REG, X15_REG]
    }

    /// Split platform-specific instructions
    /// The transformations done here are meant to make our lives simpler in later
    /// stages of the compilation pipeline.
    /// Here we may want to make sure that all instructions (except load and store)
    /// have no memory operands.
    fn arm64_split(mut self) -> Assembler
    {
        /// When we're attempting to load a memory address into a register, the
        /// displacement must fit into the maximum number of bits for an Op::Add
        /// immediate. If it doesn't, we have to load the displacement into a
        /// register first.
        fn split_lea_operand(asm: &mut Assembler, opnd: Opnd) -> Opnd {
            match opnd {
                Opnd::Mem(Mem { base, disp, num_bits }) => {
                    if disp >= 0 && ShiftedImmediate::try_from(disp as u64).is_ok() {
                        asm.lea(opnd)
                    } else {
                        let disp = asm.load(Opnd::Imm(disp.into()));
                        let reg = match base {
                            MemBase::Reg(reg_no) => Opnd::Reg(Reg { reg_no, num_bits }),
                            MemBase::InsnOut(idx) => Opnd::InsnOut { idx, num_bits }
                        };

                        asm.add(reg, disp)
                    }
                },
                _ => unreachable!("Op::Lea only accepts Opnd::Mem operands.")
            }
        }

        /// When you're storing a register into a memory location or loading a
        /// memory location into a register, the displacement from the base
        /// register of the memory location must fit into 9 bits. If it doesn't,
        /// then we need to load that memory address into a register first.
        fn split_memory_address(asm: &mut Assembler, opnd: Opnd) -> Opnd {
            match opnd {
                Opnd::Mem(mem) => {
                    if mem_disp_fits_bits(mem.disp) {
                        opnd
                    } else {
                        let base = split_lea_operand(asm, opnd);
                        Opnd::mem(64, base, 0)
                    }
                },
                _ => unreachable!("Can only split memory addresses.")
            }
        }

        /// Any memory operands you're sending into an Op::Load instruction need
        /// to be split in case their displacement doesn't fit into 9 bits.
        fn split_load_operand(asm: &mut Assembler, opnd: Opnd) -> Opnd {
            match opnd {
                Opnd::Mem(_) => {
                    let split_opnd = split_memory_address(asm, opnd);
                    asm.load(split_opnd)
                },
                _ => asm.load(opnd)
            }
        }

        /// Operands that take the place of bitmask immediates must follow a
        /// certain encoding. In this function we ensure that those operands
        /// do follow that encoding, and if they don't then we load them first.
        fn split_bitmask_immediate(asm: &mut Assembler, opnd: Opnd) -> Opnd {
            match opnd {
                Opnd::Reg(_) | Opnd::InsnOut { .. } => opnd,
                Opnd::Mem(_) => split_load_operand(asm, opnd),
                Opnd::Imm(imm) => {
                    if imm <= 0 {
                        asm.load(opnd)
                    } else if BitmaskImmediate::try_from(imm as u64).is_ok() {
                        Opnd::UImm(imm as u64)
                    } else {
                        asm.load(opnd)
                    }
                },
                Opnd::UImm(uimm) => {
                    if BitmaskImmediate::try_from(uimm).is_ok() {
                        opnd
                    } else {
                        asm.load(opnd)
                    }
                },
                Opnd::None | Opnd::Value(_) => unreachable!()
            }
        }

        /// Operands that take the place of a shifted immediate must fit within
        /// a certain size. If they don't then we need to load them first.
        fn split_shifted_immediate(asm: &mut Assembler, opnd: Opnd) -> Opnd {
            match opnd {
                Opnd::Reg(_) | Opnd::InsnOut { .. } => opnd,
                Opnd::Mem(_) => split_load_operand(asm, opnd),
                Opnd::Imm(_) => asm.load(opnd),
                Opnd::UImm(uimm) => {
                    if ShiftedImmediate::try_from(uimm).is_ok() {
                        opnd
                    } else {
                        asm.load(opnd)
                    }
                },
                Opnd::None | Opnd::Value(_) => unreachable!()
            }
        }

        let mut asm_local = Assembler::new_with_label_names(std::mem::take(&mut self.label_names));
        let asm = &mut asm_local;
        let mut iterator = self.into_draining_iter();

        while let Some((index, mut insn)) = iterator.next_mapped() {
            // Here we're going to map the operands of the instruction to load
            // any Opnd::Value operands into registers if they are heap objects
            // such that only the Op::Load instruction needs to handle that
            // case. If the values aren't heap objects then we'll treat them as
            // if they were just unsigned integer.
            let skip_load = matches!(insn, Insn { op: Op::Load, .. });
            let mut opnd_iter = insn.opnd_iter_mut();

            while let Some(opnd) = opnd_iter.next() {
                match opnd {
                    Opnd::Value(value) => {
                        if value.special_const_p() {
                            *opnd = Opnd::UImm(value.as_u64());
                        } else if !skip_load {
                            *opnd = asm.load(*opnd);
                        }
                    },
                    _ => {}
                };
            }

            match insn {
                Insn { op: Op::Add, opnds, .. } => {
                    match (opnds[0], opnds[1]) {
                        (Opnd::Reg(_) | Opnd::InsnOut { .. }, Opnd::Reg(_) | Opnd::InsnOut { .. }) => {
                            asm.add(opnds[0], opnds[1]);
                        },
                        (reg_opnd @ (Opnd::Reg(_) | Opnd::InsnOut { .. }), other_opnd) |
                        (other_opnd, reg_opnd @ (Opnd::Reg(_) | Opnd::InsnOut { .. })) => {
                            let opnd1 = split_shifted_immediate(asm, other_opnd);
                            asm.add(reg_opnd, opnd1);
                        },
                        _ => {
                            let opnd0 = split_load_operand(asm, opnds[0]);
                            let opnd1 = split_shifted_immediate(asm, opnds[1]);
                            asm.add(opnd0, opnd1);
                        }
                    }
                },
                Insn { op: Op::And | Op::Or | Op::Xor, opnds, target, text, pos_marker, .. } => {
                    match (opnds[0], opnds[1]) {
                        (Opnd::Reg(_), Opnd::Reg(_)) => {
                            asm.push_insn_parts(insn.op, vec![opnds[0], opnds[1]], target, text, pos_marker);
                        },
                        (reg_opnd @ Opnd::Reg(_), other_opnd) |
                        (other_opnd, reg_opnd @ Opnd::Reg(_)) => {
                            let opnd1 = split_bitmask_immediate(asm, other_opnd);
                            asm.push_insn_parts(insn.op, vec![reg_opnd, opnd1], target, text, pos_marker);
                        },
                        _ => {
                            let opnd0 = split_load_operand(asm, opnds[0]);
                            let opnd1 = split_bitmask_immediate(asm, opnds[1]);
                            asm.push_insn_parts(insn.op, vec![opnd0, opnd1], target, text, pos_marker);
                        }
                    }
                },
                Insn { op: Op::CCall, opnds, target, .. } => {
                    assert!(opnds.len() <= C_ARG_OPNDS.len());

                    // For each of the operands we're going to first load them
                    // into a register and then move them into the correct
                    // argument register.
                    // Note: the iteration order is reversed to avoid corrupting x0,
                    // which is both the return value and first argument register
                    for (idx, opnd) in opnds.into_iter().enumerate().rev() {
                        let value = split_load_operand(asm, opnd);
                        asm.mov(C_ARG_OPNDS[idx], value);
                    }

                    // Now we push the CCall without any arguments so that it
                    // just performs the call.
                    asm.ccall(target.unwrap().unwrap_fun_ptr(), vec![]);
                },
                Insn { op: Op::Cmp, opnds, .. } => {
                    let opnd0 = match opnds[0] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[0],
                        _ => split_load_operand(asm, opnds[0])
                    };

                    let opnd1 = split_shifted_immediate(asm, opnds[1]);
                    asm.cmp(opnd0, opnd1);
                },
                Insn { op: Op::CRet, opnds, .. } => {
                    if opnds[0] != Opnd::Reg(C_RET_REG) {
                        let value = split_load_operand(asm, opnds[0]);
                        asm.mov(C_RET_OPND, value);
                    }
                    asm.cret(C_RET_OPND);
                },
                Insn { op: Op::CSelZ | Op::CSelNZ | Op::CSelE | Op::CSelNE | Op::CSelL | Op::CSelLE | Op::CSelG | Op::CSelGE, opnds, target, text, pos_marker, .. } => {
                    let new_opnds = opnds.into_iter().map(|opnd| {
                        match opnd {
                            Opnd::Reg(_) | Opnd::InsnOut { .. } => opnd,
                            _ => split_load_operand(asm, opnd)
                        }
                    }).collect();

                    asm.push_insn_parts(insn.op, new_opnds, target, text, pos_marker);
                },
                Insn { op: Op::IncrCounter, opnds, .. } => {
                    // We'll use LDADD later which only works with registers
                    // ... Load pointer into register
                    let counter_addr = split_lea_operand(asm, opnds[0]);

                    // Load immediates into a register
                    let addend = match opnds[1] {
                        opnd @ Opnd::Imm(_) | opnd @ Opnd::UImm(_) => asm.load(opnd),
                        opnd => opnd,
                    };

                    asm.incr_counter(counter_addr, addend);
                },
                Insn { op: Op::JmpOpnd, opnds, .. } => {
                    if let Opnd::Mem(_) = opnds[0] {
                        let opnd0 = split_load_operand(asm, opnds[0]);
                        asm.jmp_opnd(opnd0);
                    } else {
                        asm.jmp_opnd(opnds[0]);
                    }
                },
                Insn { op: Op::Load, opnds, .. } => {
                    split_load_operand(asm, opnds[0]);
                },
                Insn { op: Op::LoadSExt, opnds, .. } => {
                    match opnds[0] {
                        // We only want to sign extend if the operand is a
                        // register, instruction output, or memory address that
                        // is 32 bits. Otherwise we'll just load the value
                        // directly since there's no need to sign extend.
                        Opnd::Reg(Reg { num_bits: 32, .. }) |
                        Opnd::InsnOut { num_bits: 32, .. } |
                        Opnd::Mem(Mem { num_bits: 32, .. }) => {
                            asm.load_sext(opnds[0]);
                        },
                        _ => {
                            asm.load(opnds[0]);
                        }
                    };
                },
                Insn { op: Op::Mov, opnds, .. } => {
                    let value = match (opnds[0], opnds[1]) {
                        // If the first operand is a memory operand, we're going
                        // to transform this into a store instruction, so we'll
                        // need to load this anyway.
                        (Opnd::Mem(_), Opnd::UImm(_)) => asm.load(opnds[1]),
                        // The value that is being moved must be either a
                        // register or an immediate that can be encoded as a
                        // bitmask immediate. Otherwise, we'll need to split the
                        // move into multiple instructions.
                        _ => split_bitmask_immediate(asm, opnds[1])
                    };

                    // If we're attempting to load into a memory operand, then
                    // we'll switch over to the store instruction. Otherwise
                    // we'll use the normal mov instruction.
                    match opnds[0] {
                        Opnd::Mem(_) => {
                            let opnd0 = split_memory_address(asm, opnds[0]);
                            asm.store(opnd0, value);
                        },
                        Opnd::Reg(_) => {
                            asm.mov(opnds[0], value);
                        },
                        _ => unreachable!()
                    };
                },
                Insn { op: Op::Not, opnds, .. } => {
                    // The value that is being negated must be in a register, so
                    // if we get anything else we need to load it first.
                    let opnd0 = match opnds[0] {
                        Opnd::Mem(_) => split_load_operand(asm, opnds[0]),
                        _ => opnds[0]
                    };

                    asm.not(opnd0);
                },
                Insn { op: Op::Store, opnds, .. } => {
                    // The displacement for the STUR instruction can't be more
                    // than 9 bits long. If it's longer, we need to load the
                    // memory address into a register first.
                    let opnd0 = split_memory_address(asm, opnds[0]);

                    // The value being stored must be in a register, so if it's
                    // not already one we'll load it first.
                    let opnd1 = match opnds[1] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[1],
                        _ => split_load_operand(asm, opnds[1])
                    };

                    asm.store(opnd0, opnd1);
                },
                Insn { op: Op::Sub, opnds, .. } => {
                    let opnd0 = match opnds[0] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[0],
                        _ => split_load_operand(asm, opnds[0])
                    };

                    let opnd1 = split_shifted_immediate(asm, opnds[1]);
                    asm.sub(opnd0, opnd1);
                },
                Insn { op: Op::Test, opnds, .. } => {
                    // The value being tested must be in a register, so if it's
                    // not already one we'll load it first.
                    let opnd0 = match opnds[0] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[0],
                        _ => split_load_operand(asm, opnds[0])
                    };

                    // The second value must be either a register or an
                    // unsigned immediate that can be encoded as a bitmask
                    // immediate. If it's not one of those, we'll need to load
                    // it first.
                    let opnd1 = split_bitmask_immediate(asm, opnds[1]);
                    asm.test(opnd0, opnd1);
                },
                _ => {
                    // If we have an output operand, then we need to replace it
                    // with a new output operand from the new assembler.
                    if insn.out_opnd().is_some() {
                        let out_num_bits = Opnd::match_num_bits_iter(insn.opnd_iter());
                        let out = insn.out_opnd_mut().unwrap();
                        *out = asm.next_opnd_out(out_num_bits);
                    }

                    asm.push_insn(insn);
                }
            };

            iterator.map_insn_index(asm);
        }

        asm_local
    }

    /// Emit platform-specific machine code
    /// Returns a list of GC offsets
    pub fn arm64_emit(&mut self, cb: &mut CodeBlock) -> Vec<u32>
    {
        /// Determine how many instructions it will take to represent moving
        /// this value into a register. Note that the return value of this
        /// function must correspond to how many instructions are used to
        /// represent this load in the emit_load_value function.
        fn emit_load_size(value: u64) -> u8 {
            if BitmaskImmediate::try_from(value).is_ok() {
                return 1;
            }

            if value < (1 << 16) {
                1
            } else if value < (1 << 32) {
                2
            } else if value < (1 << 48) {
                3
            } else {
                4
            }
        }

        /// Emit the required instructions to load the given value into the
        /// given register. Our goal here is to use as few instructions as
        /// possible to get this value into the register.
        fn emit_load_value(cb: &mut CodeBlock, rd: A64Opnd, value: u64) -> i32 {
            let mut current = value;

            if current <= 0xffff {
                // If the value fits into a single movz
                // instruction, then we'll use that.
                movz(cb, rd, A64Opnd::new_uimm(current), 0);
                return 1;
            } else if BitmaskImmediate::try_from(current).is_ok() {
                // Otherwise, if the immediate can be encoded
                // with the special bitmask immediate encoding,
                // we'll use that.
                mov(cb, rd, A64Opnd::new_uimm(current));
                return 1;
            } else {
                // Finally we'll fall back to encoding the value
                // using movz for the first 16 bits and movk for
                // each subsequent set of 16 bits as long we
                // they are necessary.
                movz(cb, rd, A64Opnd::new_uimm(current & 0xffff), 0);
                let mut num_insns = 1;

                // (We're sure this is necessary since we
                // checked if it only fit into movz above).
                current >>= 16;
                movk(cb, rd, A64Opnd::new_uimm(current & 0xffff), 16);
                num_insns += 1;

                if current > 0xffff {
                    current >>= 16;
                    movk(cb, rd, A64Opnd::new_uimm(current & 0xffff), 32);
                    num_insns += 1;
                }

                if current > 0xffff {
                    current >>= 16;
                    movk(cb, rd, A64Opnd::new_uimm(current & 0xffff), 48);
                    num_insns += 1;
                }
                return num_insns;
            }
        }

        /// Emit a conditional jump instruction to a specific target. This is
        /// called when lowering any of the conditional jump instructions.
        fn emit_conditional_jump<const CONDITION: u8>(cb: &mut CodeBlock, target: Target) {
            match target {
                Target::CodePtr(dst_ptr) => {
                    let dst_addr = dst_ptr.into_u64();
                    //let src_addr = cb.get_write_ptr().into_i64() + 4;
                    //let offset = dst_addr - src_addr;

                    // If the condition is met, then we'll skip past the
                    // next instruction, put the address in a register, and
                    // jump to it.
                    bcond(cb, CONDITION, A64Opnd::new_imm(8));

                    // If we get to this instruction, then the condition
                    // wasn't met, in which case we'll jump past the
                    // next instruction that perform the direct jump.

                    b(cb, A64Opnd::new_imm(2i64 + emit_load_size(dst_addr) as i64));
                    let num_insns = emit_load_value(cb, Assembler::SCRATCH0, dst_addr);
                    br(cb, Assembler::SCRATCH0);
                    for _ in num_insns..4 {
                        nop(cb);
                    }

                    /*
                    // If the jump offset fits into the conditional jump as an
                    // immediate value and it's properly aligned, then we can
                    // use the b.cond instruction directly. Otherwise, we need
                    // to load the address into a register and use the branch
                    // register instruction.
                    if bcond_offset_fits_bits(offset) {
                        bcond(cb, CONDITION, A64Opnd::new_imm(dst_addr - src_addr));
                    } else {
                        // If the condition is met, then we'll skip past the
                        // next instruction, put the address in a register, and
                        // jump to it.
                        bcond(cb, CONDITION, A64Opnd::new_imm(8));

                        // If the offset fits into a direct jump, then we'll use
                        // that and the number of instructions will be shorter.
                        // Otherwise we'll use the branch register instruction.
                        if b_offset_fits_bits(offset) {
                            // If we get to this instruction, then the condition
                            // wasn't met, in which case we'll jump past the
                            // next instruction that performs the direct jump.
                            b(cb, A64Opnd::new_imm(1));

                            // Here we'll perform the direct jump to the target.
                            let offset = dst_addr - cb.get_write_ptr().into_i64() + 4;
                            b(cb, A64Opnd::new_imm(offset / 4));
                        } else {
                            // If we get to this instruction, then the condition
                            // wasn't met, in which case we'll jump past the
                            // next instruction that perform the direct jump.
                            let value = dst_addr as u64;

                            b(cb, A64Opnd::new_imm(emit_load_size(value).into()));
                            emit_load_value(cb, Assembler::SCRATCH0, value);
                            br(cb, Assembler::SCRATCH0);
                        }
                    }
                    */
                },
                Target::Label(label_idx) => {
                    // Here we're going to save enough space for ourselves and
                    // then come back and write the instruction once we know the
                    // offset. We're going to assume we can fit into a single
                    // b.cond instruction. It will panic otherwise.
                    cb.label_ref(label_idx, 4, |cb, src_addr, dst_addr| {
                        bcond(cb, CONDITION, A64Opnd::new_imm(dst_addr - (src_addr - 4)));
                    });
                },
                Target::FunPtr(_) => unreachable!()
            };
        }

        /// Emit a push instruction for the given operand by adding to the stack
        /// pointer and then storing the given value.
        fn emit_push(cb: &mut CodeBlock, opnd: A64Opnd) {
            str_pre(cb, opnd, A64Opnd::new_mem(64, C_SP_REG, -C_SP_STEP));
        }

        /// Emit a pop instruction into the given operand by loading the value
        /// and then subtracting from the stack pointer.
        fn emit_pop(cb: &mut CodeBlock, opnd: A64Opnd) {
            ldr_post(cb, opnd, A64Opnd::new_mem(64, C_SP_REG, C_SP_STEP));
        }

        // dbg!(&self.insns);

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
                Insn { op: Op::Label, target, .. } => {
                    cb.write_label(target.unwrap().unwrap_label_idx());
                },
                // Report back the current position in the generated code
                Insn { op: Op::PosMarker, pos_marker, .. } => {
                    let pos = cb.get_write_ptr();
                    let pos_marker_fn = pos_marker.as_ref().unwrap();
                    pos_marker_fn(pos);
                }
                Insn { op: Op::BakeString, text, .. } => {
                    let str = text.as_ref().unwrap();
                    for byte in str.as_bytes() {
                        cb.write_byte(*byte);
                    }

                    // Add a null-terminator byte for safety (in case we pass
                    // this to C code)
                    cb.write_byte(0);

                    // Pad out the string to the next 4-byte boundary so that
                    // it's easy to jump past.
                    for _ in 0..(4 - ((str.len() + 1) % 4)) {
                        cb.write_byte(0);
                    }
                },
                Insn { op: Op::Add, opnds, out, .. } => {
                    adds(cb, (*out).into(), opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::FrameSetup, .. } => {
                    stp_pre(cb, X29, X30, A64Opnd::new_mem(128, C_SP_REG, -16));

                    // X29 (frame_pointer) = SP
                    mov(cb, X29, C_SP_REG);
                },
                Insn { op: Op::FrameTeardown, .. } => {
                    // SP = X29 (frame pointer)
                    mov(cb, C_SP_REG, X29);

                    ldp_post(cb, X29, X30, A64Opnd::new_mem(128, C_SP_REG, 16));
                },
                Insn { op: Op::Sub, opnds, out, .. } => {
                    subs(cb, (*out).into(), opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::And, opnds, out, .. } => {
                    and(cb, (*out).into(), opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::Or, opnds, out, .. } => {
                    orr(cb, (*out).into(), opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::Xor, opnds, out, .. } => {
                    eor(cb, (*out).into(), opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::Not, opnds, out, .. } => {
                    mvn(cb, (*out).into(), opnds[0].into());
                },
                Insn { op: Op::RShift, opnds, out, .. } => {
                    asr(cb, (*out).into(), opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::URShift, opnds, out, .. } => {
                    lsr(cb, (*out).into(), opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::LShift, opnds, out, .. } => {
                    lsl(cb, (*out).into(), opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::Store, opnds, .. } => {
                    // This order may be surprising but it is correct. The way
                    // the Arm64 assembler works, the register that is going to
                    // be stored is first and the address is second. However in
                    // our IR we have the address first and the register second.
                    stur(cb, opnds[1].into(), opnds[0].into());
                },
                Insn { op: Op::Load, opnds, out, .. } => {
                    match opnds[0] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => {
                            mov(cb, (*out).into(), opnds[0].into());
                        },
                        Opnd::UImm(uimm) => {
                            emit_load_value(cb, (*out).into(), uimm);
                        },
                        Opnd::Imm(imm) => {
                            emit_load_value(cb, (*out).into(), imm as u64);
                        },
                        Opnd::Mem(_) => {
                            ldur(cb, (*out).into(), opnds[0].into());
                        },
                        Opnd::Value(value) => {
                            // We dont need to check if it's a special const
                            // here because we only allow these operands to hit
                            // this point if they're not a special const.
                            assert!(!value.special_const_p());

                            // This assumes only load instructions can contain
                            // references to GC'd Value operands. If the value
                            // being loaded is a heap object, we'll report that
                            // back out to the gc_offsets list.
                            ldr_literal(cb, (*out).into(), 2);
                            b(cb, A64Opnd::new_imm(1 + (SIZEOF_VALUE as i64) / 4));
                            cb.write_bytes(&value.as_u64().to_le_bytes());

                            let ptr_offset: u32 = (cb.get_write_pos() as u32) - (SIZEOF_VALUE as u32);
                            gc_offsets.push(ptr_offset);
                        },
                        Opnd::None => {
                            unreachable!("Attempted to load from None operand");
                        }
                    };
                },
                Insn { op: Op::LoadSExt, opnds, out, .. } => {
                    match opnds[0] {
                        Opnd::Reg(Reg { num_bits: 32, .. }) |
                        Opnd::InsnOut { num_bits: 32, .. } => {
                            sxtw(cb, (*out).into(), opnds[0].into());
                        },
                        Opnd::Mem(Mem { num_bits: 32, .. }) => {
                            ldursw(cb, (*out).into(), opnds[0].into());
                        },
                        _ => unreachable!()
                    };
                },
                Insn { op: Op::Mov, opnds, .. } => {
                    mov(cb, opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::Lea, opnds, out, .. } => {
                    let opnd: A64Opnd = opnds[0].into();

                    match opnd {
                        A64Opnd::Mem(mem) => {
                            add(
                                cb,
                                (*out).into(),
                                A64Opnd::Reg(A64Reg { reg_no: mem.base_reg_no, num_bits: 64 }),
                                A64Opnd::new_imm(mem.disp.into())
                            );
                        },
                        _ => {
                            panic!("Op::Lea only accepts Opnd::Mem operands.");
                        }
                    };
                },
                Insn { op: Op::LeaLabel, out, target, .. } => {
                    let label_idx = target.unwrap().unwrap_label_idx();

                    cb.label_ref(label_idx, 4, |cb, end_addr, dst_addr| {
                        adr(cb, Self::SCRATCH0, A64Opnd::new_imm(dst_addr - (end_addr - 4)));
                    });

                    mov(cb, (*out).into(), Self::SCRATCH0);
                },
                Insn { op: Op::CPush, opnds, .. } => {
                    emit_push(cb, opnds[0].into());
                },
                Insn { op: Op::CPop, out, .. } => {
                    emit_pop(cb, (*out).into());
                },
                Insn { op: Op::CPopInto, opnds, .. } => {
                    emit_pop(cb, opnds[0].into());
                },
                Insn { op: Op::CPushAll, .. } => {
                    let regs = Assembler::get_caller_save_regs();

                    for reg in regs {
                        emit_push(cb, A64Opnd::Reg(reg));
                    }

                    // Push the flags/state register
                    mrs(cb, Self::SCRATCH0, SystemRegister::NZCV);
                    emit_push(cb, Self::SCRATCH0);
                },
                Insn { op: Op::CPopAll, .. } => {
                    let regs = Assembler::get_caller_save_regs();

                    // Pop the state/flags register
                    msr(cb, SystemRegister::NZCV, Self::SCRATCH0);
                    emit_pop(cb, Self::SCRATCH0);

                    for reg in regs.into_iter().rev() {
                        emit_pop(cb, A64Opnd::Reg(reg));
                    }
                },
                Insn { op: Op::CCall, target, .. } => {
                    // The offset to the call target in bytes
                    let src_addr = cb.get_write_ptr().into_i64();
                    let dst_addr = target.unwrap().unwrap_fun_ptr() as i64;
                    let offset = dst_addr - src_addr;
                    // The offset in instruction count for BL's immediate
                    let offset = offset / 4;

                    // Use BL if the offset is short enough to encode as an immediate.
                    // Otherwise, use BLR with a register.
                    if b_offset_fits_bits(offset) {
                        bl(cb, A64Opnd::new_imm(offset));
                    } else {
                        emit_load_value(cb, Self::SCRATCH0, dst_addr as u64);
                        blr(cb, Self::SCRATCH0);
                    }
                },
                Insn { op: Op::CRet, .. } => {
                    ret(cb, A64Opnd::None);
                },
                Insn { op: Op::Cmp, opnds, .. } => {
                    cmp(cb, opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::Test, opnds, .. } => {
                    tst(cb, opnds[0].into(), opnds[1].into());
                },
                Insn { op: Op::JmpOpnd, opnds, .. } => {
                    br(cb, opnds[0].into());
                },
                Insn { op: Op::Jmp, target, .. } => {
                    match target.unwrap() {
                        Target::CodePtr(dst_ptr) => {
                            let src_addr = cb.get_write_ptr().into_i64();
                            let dst_addr = dst_ptr.into_i64();

                            // The offset between the two instructions in bytes.
                            // Note that when we encode this into a b
                            // instruction, we'll divide by 4 because it accepts
                            // the number of instructions to jump over.
                            let offset = dst_addr - src_addr;
                            let offset = offset / 4;

                            // If the offset is short enough, then we'll use the
                            // branch instruction. Otherwise, we'll move the
                            // destination into a register and use the branch
                            // register instruction.
                            let num_insns = emit_load_value(cb, Self::SCRATCH0, dst_addr as u64);
                            br(cb, Self::SCRATCH0);
                            for _ in num_insns..4 {
                                nop(cb);
                            }
                        },
                        Target::Label(label_idx) => {
                            // Here we're going to save enough space for
                            // ourselves and then come back and write the
                            // instruction once we know the offset. We're going
                            // to assume we can fit into a single b instruction.
                            // It will panic otherwise.
                            cb.label_ref(label_idx, 4, |cb, src_addr, dst_addr| {
                                b(cb, A64Opnd::new_imm((dst_addr - (src_addr - 4)) / 4));
                            });
                        },
                        _ => unreachable!()
                    };
                },
                Insn { op: Op::Je, target, .. } => {
                    emit_conditional_jump::<{Condition::EQ}>(cb, target.unwrap());
                },
                Insn { op: Op::Jne, target, .. } => {
                    emit_conditional_jump::<{Condition::NE}>(cb, target.unwrap());
                },
                Insn { op: Op::Jl, target, .. } => {
                    emit_conditional_jump::<{Condition::LT}>(cb, target.unwrap());
                },
                Insn { op: Op::Jbe, target, .. } => {
                    emit_conditional_jump::<{Condition::LS}>(cb, target.unwrap());
                },
                Insn { op: Op::Jz, target, .. } => {
                    emit_conditional_jump::<{Condition::EQ}>(cb, target.unwrap());
                },
                Insn { op: Op::Jnz, target, .. } => {
                    emit_conditional_jump::<{Condition::NE}>(cb, target.unwrap());
                },
                Insn { op: Op::Jo, target, .. } => {
                    emit_conditional_jump::<{Condition::VS}>(cb, target.unwrap());
                },
                Insn { op: Op::IncrCounter, opnds, .. } => {
                    ldaddal(cb, opnds[1].into(), opnds[1].into(), opnds[0].into());
                },
                Insn { op: Op::Breakpoint, .. } => {
                    brk(cb, A64Opnd::None);
                },
                Insn { op: Op::CSelZ | Op::CSelE, opnds, out, .. } => {
                    csel(cb, (*out).into(), opnds[0].into(), opnds[1].into(), Condition::EQ);
                },
                Insn { op: Op::CSelNZ | Op::CSelNE, opnds, out, .. } => {
                    csel(cb, (*out).into(), opnds[0].into(), opnds[1].into(), Condition::NE);
                },
                Insn { op: Op::CSelL, opnds, out, .. } => {
                    csel(cb, (*out).into(), opnds[0].into(), opnds[1].into(), Condition::LT);
                },
                Insn { op: Op::CSelLE, opnds, out, .. } => {
                    csel(cb, (*out).into(), opnds[0].into(), opnds[1].into(), Condition::LE);
                },
                Insn { op: Op::CSelG, opnds, out, .. } => {
                    csel(cb, (*out).into(), opnds[0].into(), opnds[1].into(), Condition::GT);
                },
                Insn { op: Op::CSelGE, opnds, out, .. } => {
                    csel(cb, (*out).into(), opnds[0].into(), opnds[1].into(), Condition::GE);
                }
                Insn { op: Op::LiveReg, .. } => (), // just a reg alloc signal, no code
                Insn { op: Op::PadEntryExit, .. } => {
                    let jmp_len = 5 * 4; // Op::Jmp may emit 5 instructions
                    while (cb.get_write_pos() - start_write_pos) < jmp_len {
                        nop(cb);
                    }
                }
            };
        }

        gc_offsets
    }

    /// Optimize and compile the stored instructions
    pub fn compile_with_regs(self, cb: &mut CodeBlock, regs: Vec<Reg>) -> Vec<u32>
    {
        let mut asm = self.arm64_split().alloc_regs(regs);

        // Create label instances in the code block
        for (idx, name) in asm.label_names.iter().enumerate() {
            let label_idx = cb.new_label(name.to_string());
            assert!(label_idx == idx);
        }

        let gc_offsets = asm.arm64_emit(cb);

        if !cb.has_dropped_bytes() {
            cb.link_labels();
        }

        gc_offsets
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_asm() -> (Assembler, CodeBlock) {
        (Assembler::new(), CodeBlock::new_dummy(1024))
    }

    #[test]
    fn test_emit_add() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.add(Opnd::Reg(X0_REG), Opnd::Reg(X1_REG));
        asm.store(Opnd::mem(64, Opnd::Reg(X2_REG), 0), opnd);
        asm.compile_with_regs(&mut cb, vec![X3_REG]);

        // Assert that only 2 instructions were written.
        assert_eq!(8, cb.get_write_pos());
    }

    #[test]
    fn test_emit_bake_string() {
        let (mut asm, mut cb) = setup_asm();

        asm.bake_string("Hello, world!");
        asm.compile_with_num_regs(&mut cb, 0);

        // Testing that we pad the string to the nearest 4-byte boundary to make
        // it easier to jump over.
        assert_eq!(16, cb.get_write_pos());
    }

    #[test]
    fn test_emit_cpush_all() {
        let (mut asm, mut cb) = setup_asm();

        asm.cpush_all();
        asm.compile_with_num_regs(&mut cb, 0);
    }

    #[test]
    fn test_emit_cpop_all() {
        let (mut asm, mut cb) = setup_asm();

        asm.cpop_all();
        asm.compile_with_num_regs(&mut cb, 0);
    }

    #[test]
    fn test_emit_frame() {
        let (mut asm, mut cb) = setup_asm();

        asm.frame_setup();
        asm.frame_teardown();
        asm.compile_with_num_regs(&mut cb, 0);
    }

    #[test]
    fn test_emit_lea_label() {
        let (mut asm, mut cb) = setup_asm();

        let label = asm.new_label("label");
        let opnd = asm.lea_label(label);

        asm.write_label(label);
        asm.bake_string("Hello, world!");
        asm.store(Opnd::mem(64, SP, 0), opnd);

        asm.compile_with_num_regs(&mut cb, 1);
    }

    #[test]
    fn test_emit_load_mem_disp_fits_into_load() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.load(Opnd::mem(64, SP, 0));
        asm.store(Opnd::mem(64, SP, 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);

        // Assert that two instructions were written: LDUR and STUR.
        assert_eq!(8, cb.get_write_pos());
    }

    #[test]
    fn test_emit_load_mem_disp_fits_into_add() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.load(Opnd::mem(64, SP, 1 << 10));
        asm.store(Opnd::mem(64, SP, 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);

        // Assert that three instructions were written: ADD, LDUR, and STUR.
        assert_eq!(12, cb.get_write_pos());
    }

    #[test]
    fn test_emit_load_mem_disp_does_not_fit_into_add() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.load(Opnd::mem(64, SP, 1 << 12 | 1));
        asm.store(Opnd::mem(64, SP, 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);

        // Assert that three instructions were written: MOVZ, ADD, LDUR, and STUR.
        assert_eq!(16, cb.get_write_pos());
    }

    #[test]
    fn test_emit_load_value_immediate() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.load(Opnd::Value(Qnil));
        asm.store(Opnd::mem(64, SP, 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);

        // Assert that only two instructions were written since the value is an
        // immediate.
        assert_eq!(8, cb.get_write_pos());
    }

    #[test]
    fn test_emit_load_value_non_immediate() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.load(Opnd::Value(VALUE(0xCAFECAFECAFE0000)));
        asm.store(Opnd::mem(64, SP, 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);

        // Assert that five instructions were written since the value is not an
        // immediate and needs to be loaded into a register.
        assert_eq!(20, cb.get_write_pos());
    }

    #[test]
    fn test_emit_or() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.or(Opnd::Reg(X0_REG), Opnd::Reg(X1_REG));
        asm.store(Opnd::mem(64, Opnd::Reg(X2_REG), 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);
    }

    #[test]
    fn test_emit_lshift() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.lshift(Opnd::Reg(X0_REG), Opnd::UImm(5));
        asm.store(Opnd::mem(64, Opnd::Reg(X2_REG), 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);
    }

    #[test]
    fn test_emit_rshift() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.rshift(Opnd::Reg(X0_REG), Opnd::UImm(5));
        asm.store(Opnd::mem(64, Opnd::Reg(X2_REG), 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);
    }

    #[test]
    fn test_emit_urshift() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.urshift(Opnd::Reg(X0_REG), Opnd::UImm(5));
        asm.store(Opnd::mem(64, Opnd::Reg(X2_REG), 0), opnd);
        asm.compile_with_num_regs(&mut cb, 1);
    }

    #[test]
    fn test_emit_test() {
        let (mut asm, mut cb) = setup_asm();

        asm.test(Opnd::Reg(X0_REG), Opnd::Reg(X1_REG));
        asm.compile_with_num_regs(&mut cb, 0);

        // Assert that only one instruction was written.
        assert_eq!(4, cb.get_write_pos());
    }

    #[test]
    fn test_emit_test_with_encodable_unsigned_immediate() {
        let (mut asm, mut cb) = setup_asm();

        asm.test(Opnd::Reg(X0_REG), Opnd::UImm(7));
        asm.compile_with_num_regs(&mut cb, 0);

        // Assert that only one instruction was written.
        assert_eq!(4, cb.get_write_pos());
    }

    #[test]
    fn test_emit_test_with_unencodable_unsigned_immediate() {
        let (mut asm, mut cb) = setup_asm();

        asm.test(Opnd::Reg(X0_REG), Opnd::UImm(5));
        asm.compile_with_num_regs(&mut cb, 1);

        // Assert that a load and a test instruction were written.
        assert_eq!(8, cb.get_write_pos());
    }

    #[test]
    fn test_emit_test_with_encodable_signed_immediate() {
        let (mut asm, mut cb) = setup_asm();

        asm.test(Opnd::Reg(X0_REG), Opnd::Imm(7));
        asm.compile_with_num_regs(&mut cb, 0);

        // Assert that only one instruction was written.
        assert_eq!(4, cb.get_write_pos());
    }

    #[test]
    fn test_emit_test_with_unencodable_signed_immediate() {
        let (mut asm, mut cb) = setup_asm();

        asm.test(Opnd::Reg(X0_REG), Opnd::Imm(5));
        asm.compile_with_num_regs(&mut cb, 1);

        // Assert that a load and a test instruction were written.
        assert_eq!(8, cb.get_write_pos());
    }

    #[test]
    fn test_emit_test_with_negative_signed_immediate() {
        let (mut asm, mut cb) = setup_asm();

        asm.test(Opnd::Reg(X0_REG), Opnd::Imm(-7));
        asm.compile_with_num_regs(&mut cb, 1);

        // Assert that a load and a test instruction were written.
        assert_eq!(8, cb.get_write_pos());
    }

    #[test]
    fn test_emit_xor() {
        let (mut asm, mut cb) = setup_asm();

        let opnd = asm.xor(Opnd::Reg(X0_REG), Opnd::Reg(X1_REG));
        asm.store(Opnd::mem(64, Opnd::Reg(X2_REG), 0), opnd);

        asm.compile_with_num_regs(&mut cb, 1);
    }

    #[test]
    #[cfg(feature = "disasm")]
    fn test_simple_disasm() -> std::result::Result<(), capstone::Error> {
        // Test drive Capstone with simple input
        use capstone::prelude::*;

        let cs = Capstone::new()
            .arm64()
            .mode(arch::arm64::ArchMode::Arm)
            .build()?;

        let insns = cs.disasm_all(&[0x60, 0x0f, 0x80, 0xF2], 0x1000)?;

        match insns.as_ref() {
            [insn] => {
                assert_eq!(Some("movk"), insn.mnemonic());
                Ok(())
            }
            _ => Err(capstone::Error::CustomError(
                "expected to disassemble to movk",
            )),
        }
    }
}
