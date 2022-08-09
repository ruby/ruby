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

        self.forward_pass(|asm, index, op, opnds, target, text, pos_marker, original_opnds| {
            // Load all Value operands into registers that aren't already a part
            // of Load instructions.
            let opnds = match op {
                Op::Load => opnds,
                _ => opnds.into_iter().map(|opnd| {
                    if let Opnd::Value(_) = opnd {
                        asm.load(opnd)
                    } else {
                        opnd
                    }
                }).collect()
            };

            match op {
                Op::Add => {
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
                Op::And | Op::Or => {
                    match (opnds[0], opnds[1]) {
                        (Opnd::Reg(_), Opnd::Reg(_)) => {
                            asm.push_insn(op, vec![opnds[0], opnds[1]], target, text, pos_marker);
                        },
                        (reg_opnd @ Opnd::Reg(_), other_opnd) |
                        (other_opnd, reg_opnd @ Opnd::Reg(_)) => {
                            let opnd1 = split_bitmask_immediate(asm, other_opnd);
                            asm.push_insn(op, vec![reg_opnd, opnd1], target, text, pos_marker);
                        },
                        _ => {
                            let opnd0 = split_load_operand(asm, opnds[0]);
                            let opnd1 = split_bitmask_immediate(asm, opnds[1]);
                            asm.push_insn(op, vec![opnd0, opnd1], target, text, pos_marker);
                        }
                    }
                },
                Op::CCall => {
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
                Op::Cmp => {
                    let opnd0 = match opnds[0] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[0],
                        _ => split_load_operand(asm, opnds[0])
                    };

                    let opnd1 = split_shifted_immediate(asm, opnds[1]);
                    asm.cmp(opnd0, opnd1);
                },
                Op::CRet => {
                    if opnds[0] != Opnd::Reg(C_RET_REG) {
                        let value = split_load_operand(asm, opnds[0]);
                        asm.mov(C_RET_OPND, value);
                    }
                    asm.cret(C_RET_OPND);
                },
                Op::CSelZ | Op::CSelNZ | Op::CSelE | Op::CSelNE |
                Op::CSelL | Op::CSelLE | Op::CSelG | Op::CSelGE => {
                    let new_opnds = opnds.into_iter().map(|opnd| {
                        match opnd {
                            Opnd::Reg(_) | Opnd::InsnOut { .. } => opnd,
                            _ => split_load_operand(asm, opnd)
                        }
                    }).collect();

                    asm.push_insn(op, new_opnds, target, text, pos_marker);
                },
                Op::IncrCounter => {
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
                Op::JmpOpnd => {
                    if let Opnd::Mem(_) = opnds[0] {
                        let opnd0 = split_load_operand(asm, opnds[0]);
                        asm.jmp_opnd(opnd0);
                    } else {
                        asm.jmp_opnd(opnds[0]);
                    }
                },
                Op::Load => {
                    split_load_operand(asm, opnds[0]);
                },
                Op::LoadSExt => {
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
                Op::Mov => {
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
                Op::Not => {
                    // The value that is being negated must be in a register, so
                    // if we get anything else we need to load it first.
                    let opnd0 = match opnds[0] {
                        Opnd::Mem(_) => split_load_operand(asm, opnds[0]),
                        _ => opnds[0]
                    };

                    asm.not(opnd0);
                },
                Op::Store => {
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
                Op::Sub => {
                    let opnd0 = match opnds[0] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[0],
                        _ => split_load_operand(asm, opnds[0])
                    };

                    let opnd1 = split_shifted_immediate(asm, opnds[1]);
                    asm.sub(opnd0, opnd1);
                },
                Op::Test => {
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
                    asm.push_insn(op, opnds, target, text, pos_marker);
                }
            };
        })
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
        fn emit_load_value(cb: &mut CodeBlock, rd: A64Opnd, value: u64) {
            let mut current = value;

            if current <= 0xffff {
                // If the value fits into a single movz
                // instruction, then we'll use that.
                movz(cb, rd, A64Opnd::new_uimm(current), 0);
            } else if BitmaskImmediate::try_from(current).is_ok() {
                // Otherwise, if the immediate can be encoded
                // with the special bitmask immediate encoding,
                // we'll use that.
                mov(cb, rd, A64Opnd::new_uimm(current));
            } else {
                // Finally we'll fall back to encoding the value
                // using movz for the first 16 bits and movk for
                // each subsequent set of 16 bits as long we
                // they are necessary.
                movz(cb, rd, A64Opnd::new_uimm(current & 0xffff), 0);

                // (We're sure this is necessary since we
                // checked if it only fit into movz above).
                current >>= 16;
                movk(cb, rd, A64Opnd::new_uimm(current & 0xffff), 16);

                if current > 0xffff {
                    current >>= 16;
                    movk(cb, rd, A64Opnd::new_uimm(current & 0xffff), 32);
                }

                if current > 0xffff {
                    current >>= 16;
                    movk(cb, rd, A64Opnd::new_uimm(current & 0xffff), 48);
                }
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
                    emit_load_value(cb, Assembler::SCRATCH0, dst_addr);
                    br(cb, Assembler::SCRATCH0);

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
        for insn in &self.insns {
            match insn.op {
                Op::Comment => {
                    if cfg!(feature = "asm_comments") {
                        cb.add_comment(&insn.text.as_ref().unwrap());
                    }
                },
                Op::Label => {
                    cb.write_label(insn.target.unwrap().unwrap_label_idx());
                },
                // Report back the current position in the generated code
                Op::PosMarker => {
                    let pos = cb.get_write_ptr();
                    let pos_marker_fn = insn.pos_marker.as_ref().unwrap();
                    pos_marker_fn(pos);
                }
                Op::BakeString => {
                    let str = insn.text.as_ref().unwrap();
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
                Op::Add => {
                    adds(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::FrameSetup => {
                    stp_pre(cb, X29, X30, A64Opnd::new_mem(128, C_SP_REG, -16));

                    // X29 (frame_pointer) = SP
                    mov(cb, X29, C_SP_REG);
                },
                Op::FrameTeardown => {
                    // SP = X29 (frame pointer)
                    mov(cb, C_SP_REG, X29);

                    ldp_post(cb, X29, X30, A64Opnd::new_mem(128, C_SP_REG, 16));
                },
                Op::Sub => {
                    subs(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::And => {
                    and(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::Or => {
                    orr(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::Not => {
                    mvn(cb, insn.out.into(), insn.opnds[0].into());
                },
                Op::RShift => {
                    asr(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::URShift => {
                    lsr(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::LShift => {
                    lsl(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::Store => {
                    // This order may be surprising but it is correct. The way
                    // the Arm64 assembler works, the register that is going to
                    // be stored is first and the address is second. However in
                    // our IR we have the address first and the register second.
                    stur(cb, insn.opnds[1].into(), insn.opnds[0].into());
                },
                Op::Load => {
                    match insn.opnds[0] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => {
                            mov(cb, insn.out.into(), insn.opnds[0].into());
                        },
                        Opnd::UImm(uimm) => {
                            emit_load_value(cb, insn.out.into(), uimm);
                        },
                        Opnd::Imm(imm) => {
                            emit_load_value(cb, insn.out.into(), imm as u64);
                        },
                        Opnd::Mem(_) => {
                            ldur(cb, insn.out.into(), insn.opnds[0].into());
                        },
                        Opnd::Value(value) => {
                            // This assumes only load instructions can contain
                            // references to GC'd Value operands. If the value
                            // being loaded is a heap object, we'll report that
                            // back out to the gc_offsets list.
                            ldr_literal(cb, insn.out.into(), 2);
                            b(cb, A64Opnd::new_imm(1 + (SIZEOF_VALUE as i64) / 4));
                            cb.write_bytes(&value.as_u64().to_le_bytes());

                            if !value.special_const_p() {
                                let ptr_offset: u32 = (cb.get_write_pos() as u32) - (SIZEOF_VALUE as u32);
                                gc_offsets.push(ptr_offset);
                            }
                        },
                        Opnd::None => {
                            unreachable!("Attempted to load from None operand");
                        }
                    };
                },
                Op::LoadSExt => {
                    match insn.opnds[0] {
                        Opnd::Reg(Reg { num_bits: 32, .. }) |
                        Opnd::InsnOut { num_bits: 32, .. } => {
                            sxtw(cb, insn.out.into(), insn.opnds[0].into());
                        },
                        Opnd::Mem(Mem { num_bits: 32, .. }) => {
                            ldursw(cb, insn.out.into(), insn.opnds[0].into());
                        },
                        _ => unreachable!()
                    };
                },
                Op::Mov => {
                    mov(cb, insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::Lea => {
                    let opnd: A64Opnd = insn.opnds[0].into();

                    match opnd {
                        A64Opnd::Mem(mem) => {
                            add(
                                cb,
                                insn.out.into(),
                                A64Opnd::Reg(A64Reg { reg_no: mem.base_reg_no, num_bits: 64 }),
                                A64Opnd::new_imm(mem.disp.into())
                            );
                        },
                        _ => {
                            panic!("Op::Lea only accepts Opnd::Mem operands.");
                        }
                    };
                },
                Op::LeaLabel => {
                    let label_idx = insn.target.unwrap().unwrap_label_idx();

                    cb.label_ref(label_idx, 4, |cb, end_addr, dst_addr| {
                        adr(cb, Self::SCRATCH0, A64Opnd::new_imm(dst_addr - (end_addr - 4)));
                    });

                    mov(cb, insn.out.into(), Self::SCRATCH0);
                },
                Op::CPush => {
                    emit_push(cb, insn.opnds[0].into());
                },
                Op::CPop => {
                    emit_pop(cb, insn.out.into());
                },
                Op::CPopInto => {
                    emit_pop(cb, insn.opnds[0].into());
                },
                Op::CPushAll => {
                    let regs = Assembler::get_caller_save_regs();

                    for reg in regs {
                        emit_push(cb, A64Opnd::Reg(reg));
                    }

                    // Push the flags/state register
                    mrs(cb, Self::SCRATCH0, SystemRegister::NZCV);
                    emit_push(cb, Self::SCRATCH0);
                },
                Op::CPopAll => {
                    let regs = Assembler::get_caller_save_regs();

                    // Pop the state/flags register
                    msr(cb, SystemRegister::NZCV, Self::SCRATCH0);
                    emit_pop(cb, Self::SCRATCH0);

                    for reg in regs.into_iter().rev() {
                        emit_pop(cb, A64Opnd::Reg(reg));
                    }
                },
                Op::CCall => {
                    // The offset to the call target in bytes
                    let src_addr = cb.get_write_ptr().into_i64();
                    let dst_addr = insn.target.unwrap().unwrap_fun_ptr() as i64;
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
                Op::CRet => {
                    ret(cb, A64Opnd::None);
                },
                Op::Cmp => {
                    cmp(cb, insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::Test => {
                    tst(cb, insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::JmpOpnd => {
                    br(cb, insn.opnds[0].into());
                },
                Op::Jmp => {
                    match insn.target.unwrap() {
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
                            if b_offset_fits_bits(offset) {
                                b(cb, A64Opnd::new_imm(offset));
                            } else {
                                emit_load_value(cb, Self::SCRATCH0, dst_addr as u64);
                                br(cb, Self::SCRATCH0);
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
                Op::Je => {
                    emit_conditional_jump::<{Condition::EQ}>(cb, insn.target.unwrap());
                },
                Op::Jne => {
                    emit_conditional_jump::<{Condition::NE}>(cb, insn.target.unwrap());
                },
                Op::Jbe => {
                    emit_conditional_jump::<{Condition::LS}>(cb, insn.target.unwrap());
                },
                Op::Jz => {
                    emit_conditional_jump::<{Condition::EQ}>(cb, insn.target.unwrap());
                },
                Op::Jnz => {
                    emit_conditional_jump::<{Condition::NE}>(cb, insn.target.unwrap());
                },
                Op::Jo => {
                    emit_conditional_jump::<{Condition::VS}>(cb, insn.target.unwrap());
                },
                Op::IncrCounter => {
                    ldaddal(cb, insn.opnds[1].into(), insn.opnds[1].into(), insn.opnds[0].into());
                },
                Op::Breakpoint => {
                    brk(cb, A64Opnd::None);
                },
                Op::CSelZ | Op::CSelE => {
                    csel(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into(), Condition::EQ);
                },
                Op::CSelNZ | Op::CSelNE => {
                    csel(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into(), Condition::NE);
                },
                Op::CSelL => {
                    csel(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into(), Condition::LT);
                },
                Op::CSelLE => {
                    csel(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into(), Condition::LE);
                },
                Op::CSelG => {
                    csel(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into(), Condition::GT);
                },
                Op::CSelGE => {
                    csel(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into(), Condition::GE);
                }
                Op::LiveReg => (), // just a reg alloc signal, no code
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
        cb.link_labels();

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
