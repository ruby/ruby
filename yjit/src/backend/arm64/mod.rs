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

/// Also implement going from a reference to an operand for convenience.
impl From<&Opnd> for A64Opnd {
    fn from(opnd: &Opnd) -> Self {
        A64Opnd::from(*opnd)
    }
}

impl Assembler
{
    // A special scratch register for intermediate processing.
    // This register is caller-saved (so we don't have to save it before using it)
    const SCRATCH0: A64Opnd = A64Opnd::Reg(X16_REG);
    const SCRATCH1: A64Opnd = A64Opnd::Reg(X17_REG);    

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
                Opnd::Reg(_) | Opnd::InsnOut { .. } => opnd,
                Opnd::Mem(_) => {
                    let split_opnd = split_memory_address(asm, opnd);
                    let out_opnd = asm.load(split_opnd);
                    // Many Arm insns support only 32-bit or 64-bit operands. asm.load with fewer
                    // bits zero-extends the value, so it's safe to recognize it as a 32-bit value.
                    if out_opnd.rm_num_bits() < 32 {
                        out_opnd.with_num_bits(32).unwrap()
                    } else {
                        out_opnd
                    }
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

        /// Returns the operands that should be used for a boolean logic
        /// instruction.
        fn split_boolean_operands(asm: &mut Assembler, opnd0: Opnd, opnd1: Opnd) -> (Opnd, Opnd) {
            match (opnd0, opnd1) {
                (Opnd::Reg(_), Opnd::Reg(_)) => {
                    (opnd0, opnd1)
                },
                (reg_opnd @ Opnd::Reg(_), other_opnd) |
                (other_opnd, reg_opnd @ Opnd::Reg(_)) => {
                    let opnd1 = split_bitmask_immediate(asm, other_opnd);
                    (reg_opnd, opnd1)
                },
                _ => {
                    let opnd0 = split_load_operand(asm, opnd0);
                    let opnd1 = split_bitmask_immediate(asm, opnd1);
                    (opnd0, opnd1)
                }
            }
        }

        /// Returns the operands that should be used for a csel instruction.
        fn split_csel_operands(asm: &mut Assembler, opnd0: Opnd, opnd1: Opnd) -> (Opnd, Opnd) {
            let opnd0 = match opnd0 {
                Opnd::Reg(_) | Opnd::InsnOut { .. } => opnd0,
                _ => split_load_operand(asm, opnd0)
            };

            let opnd1 = match opnd1 {
                Opnd::Reg(_) | Opnd::InsnOut { .. } => opnd1,
                _ => split_load_operand(asm, opnd1)
            };

            (opnd0, opnd1)
        }

        fn split_less_than_32_cmp(asm: &mut Assembler, opnd0: Opnd) -> Opnd {
            match opnd0 {
                Opnd::Reg(_) | Opnd::InsnOut { .. } => {
                    match opnd0.rm_num_bits() {
                        8 => asm.and(opnd0.with_num_bits(64).unwrap(), Opnd::UImm(0xff)),
                        16 => asm.and(opnd0.with_num_bits(64).unwrap(), Opnd::UImm(0xffff)),
                        32 | 64 => opnd0,
                        bits => unreachable!("Invalid number of bits. {}", bits)
                    }
                }
                _ => opnd0
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
            let is_load = matches!(insn, Insn::Load { .. } | Insn::LoadInto { .. });
            let mut opnd_iter = insn.opnd_iter_mut();

            while let Some(opnd) = opnd_iter.next() {
                match opnd {
                    Opnd::Value(value) => {
                        if value.special_const_p() {
                            *opnd = Opnd::UImm(value.as_u64());
                        } else if !is_load {
                            *opnd = asm.load(*opnd);
                        }
                    },
                    _ => {}
                };
            }

            match insn {
                Insn::Add { left, right, .. } => {
                    match (left, right) {
                        (Opnd::Reg(_) | Opnd::InsnOut { .. }, Opnd::Reg(_) | Opnd::InsnOut { .. }) => {
                            asm.add(left, right);
                        },
                        (reg_opnd @ (Opnd::Reg(_) | Opnd::InsnOut { .. }), other_opnd) |
                        (other_opnd, reg_opnd @ (Opnd::Reg(_) | Opnd::InsnOut { .. })) => {
                            let opnd1 = split_shifted_immediate(asm, other_opnd);
                            asm.add(reg_opnd, opnd1);
                        },
                        _ => {
                            let opnd0 = split_load_operand(asm, left);
                            let opnd1 = split_shifted_immediate(asm, right);
                            asm.add(opnd0, opnd1);
                        }
                    }
                },
                Insn::And { left, right, .. } => {
                    let (opnd0, opnd1) = split_boolean_operands(asm, left, right);
                    asm.and(opnd0, opnd1);
                },
                Insn::Or { left, right, .. } => {
                    let (opnd0, opnd1) = split_boolean_operands(asm, left, right);
                    asm.or(opnd0, opnd1);
                },
                Insn::Xor { left, right, .. } => {
                    let (opnd0, opnd1) = split_boolean_operands(asm, left, right);
                    asm.xor(opnd0, opnd1);
                },
                Insn::CCall { opnds, target, .. } => {
                    assert!(opnds.len() <= C_ARG_OPNDS.len());

                    // Load each operand into the corresponding argument
                    // register.
                    // Note: the iteration order is reversed to avoid corrupting x0,
                    // which is both the return value and first argument register
                    for (idx, opnd) in opnds.into_iter().enumerate().rev() {
                        // If the value that we're sending is 0, then we can use
                        // the zero register, so in this case we'll just send
                        // a UImm of 0 along as the argument to the move.
                        let value = match opnd {
                            Opnd::UImm(0) | Opnd::Imm(0) => Opnd::UImm(0),
                            Opnd::Mem(_) => split_memory_address(asm, opnd),
                            _ => opnd
                        };

                        asm.load_into(C_ARG_OPNDS[idx], value);
                    }

                    // Now we push the CCall without any arguments so that it
                    // just performs the call.
                    asm.ccall(target.unwrap_fun_ptr(), vec![]);
                },
                Insn::Cmp { left, right } => {
                    let opnd0 = split_load_operand(asm, left);
                    let opnd0 = split_less_than_32_cmp(asm, opnd0);
                    let opnd1 = split_shifted_immediate(asm, right);
                    asm.cmp(opnd0, opnd1);
                },
                Insn::CRet(opnd) => {
                    match opnd {
                        // If the value is already in the return register, then
                        // we don't need to do anything.
                        Opnd::Reg(C_RET_REG) => {},

                        // If the value is a memory address, we need to first
                        // make sure the displacement isn't too large and then
                        // load it into the return register.
                        Opnd::Mem(_) => {
                            let split = split_memory_address(asm, opnd);
                            asm.load_into(C_RET_OPND, split);
                        },

                        // Otherwise we just need to load the value into the
                        // return register.
                        _ => {
                            asm.load_into(C_RET_OPND, opnd);
                        }
                    }
                    asm.cret(C_RET_OPND);
                },
                Insn::CSelZ { truthy, falsy, .. } => {
                    let (opnd0, opnd1) = split_csel_operands(asm, truthy, falsy);
                    asm.csel_z(opnd0, opnd1);
                },
                Insn::CSelNZ { truthy, falsy, .. } => {
                    let (opnd0, opnd1) = split_csel_operands(asm, truthy, falsy);
                    asm.csel_nz(opnd0, opnd1);
                },
                Insn::CSelE { truthy, falsy, .. } => {
                    let (opnd0, opnd1) = split_csel_operands(asm, truthy, falsy);
                    asm.csel_e(opnd0, opnd1);
                },
                Insn::CSelNE { truthy, falsy, .. } => {
                    let (opnd0, opnd1) = split_csel_operands(asm, truthy, falsy);
                    asm.csel_ne(opnd0, opnd1);
                },
                Insn::CSelL { truthy, falsy, .. } => {
                    let (opnd0, opnd1) = split_csel_operands(asm, truthy, falsy);
                    asm.csel_l(opnd0, opnd1);
                },
                Insn::CSelLE { truthy, falsy, .. } => {
                    let (opnd0, opnd1) = split_csel_operands(asm, truthy, falsy);
                    asm.csel_le(opnd0, opnd1);
                },
                Insn::CSelG { truthy, falsy, .. } => {
                    let (opnd0, opnd1) = split_csel_operands(asm, truthy, falsy);
                    asm.csel_g(opnd0, opnd1);
                },
                Insn::CSelGE { truthy, falsy, .. } => {
                    let (opnd0, opnd1) = split_csel_operands(asm, truthy, falsy);
                    asm.csel_ge(opnd0, opnd1);
                },
                Insn::IncrCounter { mem, value } => {
                    let counter_addr = match mem {
                        Opnd::Mem(_) => split_lea_operand(asm, mem),
                        _ => mem
                    };

                    asm.incr_counter(counter_addr, value);
                },
                Insn::JmpOpnd(opnd) => {
                    if let Opnd::Mem(_) = opnd {
                        let opnd0 = split_load_operand(asm, opnd);
                        asm.jmp_opnd(opnd0);
                    } else {
                        asm.jmp_opnd(opnd);
                    }
                },
                Insn::Load { opnd, .. } => {
                    let value = match opnd {
                        Opnd::Mem(_) => split_memory_address(asm, opnd),
                        _ => opnd
                    };

                    asm.load(value);
                },
                Insn::LoadInto { dest, opnd } => {
                    let value = match opnd {
                        Opnd::Mem(_) => split_memory_address(asm, opnd),
                        _ => opnd
                    };

                    asm.load_into(dest, value);
                },
                Insn::LoadSExt { opnd, .. } => {
                    match opnd {
                        // We only want to sign extend if the operand is a
                        // register, instruction output, or memory address that
                        // is 32 bits. Otherwise we'll just load the value
                        // directly since there's no need to sign extend.
                        Opnd::Reg(Reg { num_bits: 32, .. }) |
                        Opnd::InsnOut { num_bits: 32, .. } |
                        Opnd::Mem(Mem { num_bits: 32, .. }) => {
                            asm.load_sext(opnd);
                        },
                        _ => {
                            asm.load(opnd);
                        }
                    };
                },
                Insn::Mov { dest, src } => {
                    let value: Opnd = match (dest, src) {
                        // If the first operand is zero, then we can just use
                        // the zero register.
                        (Opnd::Mem(_), Opnd::UImm(0) | Opnd::Imm(0)) => Opnd::Reg(XZR_REG),
                        // If the first operand is a memory operand, we're going
                        // to transform this into a store instruction, so we'll
                        // need to load this anyway.
                        (Opnd::Mem(_), Opnd::UImm(_)) => asm.load(src),
                        // The value that is being moved must be either a
                        // register or an immediate that can be encoded as a
                        // bitmask immediate. Otherwise, we'll need to split the
                        // move into multiple instructions.
                        _ => split_bitmask_immediate(asm, src)
                    };

                    // If we're attempting to load into a memory operand, then
                    // we'll switch over to the store instruction. Otherwise
                    // we'll use the normal mov instruction.
                    match dest {
                        Opnd::Mem(_) => {
                            let opnd0 = split_memory_address(asm, dest);
                            asm.store(opnd0, value);
                        },
                        Opnd::Reg(_) => {
                            asm.mov(dest, value);
                        },
                        _ => unreachable!()
                    };
                },
                Insn::Not { opnd, .. } => {
                    // The value that is being negated must be in a register, so
                    // if we get anything else we need to load it first.
                    let opnd0 = match opnd {
                        Opnd::Mem(_) => split_load_operand(asm, opnd),
                        _ => opnd
                    };

                    asm.not(opnd0);
                },
                Insn::Store { dest, src } => {
                    // The displacement for the STUR instruction can't be more
                    // than 9 bits long. If it's longer, we need to load the
                    // memory address into a register first.
                    let opnd0 = split_memory_address(asm, dest);

                    // The value being stored must be in a register, so if it's
                    // not already one we'll load it first.
                    let opnd1 = match src {
                         // If the first operand is zero, then we can just use
                        // the zero register.
                        Opnd::UImm(0) | Opnd::Imm(0) => Opnd::Reg(XZR_REG),
                        // Otherwise we'll check if we need to load it first.
                        _ => split_load_operand(asm, src)
                    };

                    asm.store(opnd0, opnd1);
                },
                Insn::Sub { left, right, .. } => {
                    let opnd0 = split_load_operand(asm, left);
                    let opnd1 = split_shifted_immediate(asm, right);
                    asm.sub(opnd0, opnd1);
                },
                Insn::Test { left, right } => {
                    // The value being tested must be in a register, so if it's
                    // not already one we'll load it first.
                    let opnd0 = split_load_operand(asm, left);

                    // The second value must be either a register or an
                    // unsigned immediate that can be encoded as a bitmask
                    // immediate. If it's not one of those, we'll need to load
                    // it first.
                    let opnd1 = split_bitmask_immediate(asm, right);
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
                    let dst_addr = dst_ptr.into_i64();
                    let src_addr = cb.get_write_ptr().into_i64();

                    let num_insns = if bcond_offset_fits_bits((dst_addr - src_addr) / 4) {
                        // If the jump offset fits into the conditional jump as
                        // an immediate value and it's properly aligned, then we
                        // can use the b.cond instruction directly. We're safe
                        // to use as i32 here since we already checked that it
                        // fits.
                        let bytes = (dst_addr - src_addr) as i32;
                        bcond(cb, CONDITION, InstructionOffset::from_bytes(bytes));

                        // Here we're going to return 1 because we've only
                        // written out 1 instruction.
                        1
                    } else {
                        // Otherwise, we need to load the address into a
                        // register and use the branch register instruction.
                        let dst_addr = dst_ptr.into_u64();
                        let load_insns: i32 = emit_load_size(dst_addr).into();

                        // We're going to write out the inverse condition so
                        // that if it doesn't match it will skip over the
                        // instructions used for branching.
                        bcond(cb, Condition::inverse(CONDITION), (load_insns + 2).into());
                        emit_load_value(cb, Assembler::SCRATCH0, dst_addr);
                        br(cb, Assembler::SCRATCH0);

                        // Here we'll return the number of instructions that it
                        // took to write out the destination address + 1 for the
                        // b.cond and 1 for the br.
                        load_insns + 2
                    };

                    // We need to make sure we have at least 6 instructions for
                    // every kind of jump for invalidation purposes, so we're
                    // going to write out padding nop instructions here.
                    for _ in num_insns..6 { nop(cb); }
                },
                Target::Label(label_idx) => {
                    // Here we're going to save enough space for ourselves and
                    // then come back and write the instruction once we know the
                    // offset. We're going to assume we can fit into a single
                    // b.cond instruction. It will panic otherwise.
                    cb.label_ref(label_idx, 4, |cb, src_addr, dst_addr| {
                        let bytes: i32 = (dst_addr - (src_addr - 4)).try_into().unwrap();
                        bcond(cb, CONDITION, InstructionOffset::from_bytes(bytes));
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
                Insn::Comment(text) => {
                    if cfg!(feature = "asm_comments") {
                        cb.add_comment(text);
                    }
                },
                Insn::Label(target) => {
                    cb.write_label(target.unwrap_label_idx());
                },
                // Report back the current position in the generated code
                Insn::PosMarker(pos_marker) => {
                    pos_marker(cb.get_write_ptr());
                }
                Insn::BakeString(text) => {
                    for byte in text.as_bytes() {
                        cb.write_byte(*byte);
                    }

                    // Add a null-terminator byte for safety (in case we pass
                    // this to C code)
                    cb.write_byte(0);

                    // Pad out the string to the next 4-byte boundary so that
                    // it's easy to jump past.
                    for _ in 0..(4 - ((text.len() + 1) % 4)) {
                        cb.write_byte(0);
                    }
                },
                Insn::Add { left, right, out } => {
                    adds(cb, out.into(), left.into(), right.into());
                },
                Insn::FrameSetup => {
                    stp_pre(cb, X29, X30, A64Opnd::new_mem(128, C_SP_REG, -16));

                    // X29 (frame_pointer) = SP
                    mov(cb, X29, C_SP_REG);
                },
                Insn::FrameTeardown => {
                    // SP = X29 (frame pointer)
                    mov(cb, C_SP_REG, X29);

                    ldp_post(cb, X29, X30, A64Opnd::new_mem(128, C_SP_REG, 16));
                },
                Insn::Sub { left, right, out } => {
                    subs(cb, out.into(), left.into(), right.into());
                },
                Insn::And { left, right, out } => {
                    and(cb, out.into(), left.into(), right.into());
                },
                Insn::Or { left, right, out } => {
                    orr(cb, out.into(), left.into(), right.into());
                },
                Insn::Xor { left, right, out } => {
                    eor(cb, out.into(), left.into(), right.into());
                },
                Insn::Not { opnd, out } => {
                    mvn(cb, out.into(), opnd.into());
                },
                Insn::RShift { opnd, shift, out } => {
                    asr(cb, out.into(), opnd.into(), shift.into());
                },
                Insn::URShift { opnd, shift, out } => {
                    lsr(cb, out.into(), opnd.into(), shift.into());
                },
                Insn::LShift { opnd, shift, out } => {
                    lsl(cb, out.into(), opnd.into(), shift.into());
                },
                Insn::Store { dest, src } => {
                    // This order may be surprising but it is correct. The way
                    // the Arm64 assembler works, the register that is going to
                    // be stored is first and the address is second. However in
                    // our IR we have the address first and the register second.
                    stur(cb, src.into(), dest.into());
                },
                Insn::Load { opnd, out } |
                Insn::LoadInto { opnd, dest: out } => {
                    match *opnd {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => {
                            mov(cb, out.into(), opnd.into());
                        },
                        Opnd::UImm(uimm) => {
                            emit_load_value(cb, out.into(), uimm);
                        },
                        Opnd::Imm(imm) => {
                            emit_load_value(cb, out.into(), imm as u64);
                        },
                        Opnd::Mem(_) => {
                            match opnd.rm_num_bits() {
                                64 | 32 => ldur(cb, out.into(), opnd.into()),
                                8 => ldurb(cb, out.into(), opnd.into()),
                                num_bits => panic!("unexpected num_bits: {}", num_bits)
                            };
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
                            ldr_literal(cb, out.into(), 2.into());
                            b(cb, InstructionOffset::from_bytes(4 + (SIZEOF_VALUE as i32)));
                            cb.write_bytes(&value.as_u64().to_le_bytes());

                            let ptr_offset: u32 = (cb.get_write_pos() as u32) - (SIZEOF_VALUE as u32);
                            gc_offsets.push(ptr_offset);
                        },
                        Opnd::None => {
                            unreachable!("Attempted to load from None operand");
                        }
                    };
                },
                Insn::LoadSExt { opnd, out } => {
                    match *opnd {
                        Opnd::Reg(Reg { num_bits: 32, .. }) |
                        Opnd::InsnOut { num_bits: 32, .. } => {
                            sxtw(cb, out.into(), opnd.into());
                        },
                        Opnd::Mem(Mem { num_bits: 32, .. }) => {
                            ldursw(cb, out.into(), opnd.into());
                        },
                        _ => unreachable!()
                    };
                },
                Insn::Mov { dest, src } => {
                    mov(cb, dest.into(), src.into());
                },
                Insn::Lea { opnd, out } => {
                    let opnd: A64Opnd = opnd.into();

                    match opnd {
                        A64Opnd::Mem(mem) => {
                            add(
                                cb,
                                out.into(),
                                A64Opnd::Reg(A64Reg { reg_no: mem.base_reg_no, num_bits: 64 }),
                                A64Opnd::new_imm(mem.disp.into())
                            );
                        },
                        _ => {
                            panic!("Op::Lea only accepts Opnd::Mem operands.");
                        }
                    };
                },
                Insn::LeaLabel { out, target, .. } => {
                    let label_idx = target.unwrap_label_idx();

                    cb.label_ref(label_idx, 4, |cb, end_addr, dst_addr| {
                        adr(cb, Self::SCRATCH0, A64Opnd::new_imm(dst_addr - (end_addr - 4)));
                    });

                    mov(cb, out.into(), Self::SCRATCH0);
                },
                Insn::CPush(opnd) => {
                    emit_push(cb, opnd.into());
                },
                Insn::CPop { out } => {
                    emit_pop(cb, out.into());
                },
                Insn::CPopInto(opnd) => {
                    emit_pop(cb, opnd.into());
                },
                Insn::CPushAll => {
                    let regs = Assembler::get_caller_save_regs();

                    for reg in regs {
                        emit_push(cb, A64Opnd::Reg(reg));
                    }

                    // Push the flags/state register
                    mrs(cb, Self::SCRATCH0, SystemRegister::NZCV);
                    emit_push(cb, Self::SCRATCH0);
                },
                Insn::CPopAll => {
                    let regs = Assembler::get_caller_save_regs();

                    // Pop the state/flags register
                    msr(cb, SystemRegister::NZCV, Self::SCRATCH0);
                    emit_pop(cb, Self::SCRATCH0);

                    for reg in regs.into_iter().rev() {
                        emit_pop(cb, A64Opnd::Reg(reg));
                    }
                },
                Insn::CCall { target, .. } => {
                    // The offset to the call target in bytes
                    let src_addr = cb.get_write_ptr().into_i64();
                    let dst_addr = target.unwrap_fun_ptr() as i64;

                    // Use BL if the offset is short enough to encode as an immediate.
                    // Otherwise, use BLR with a register.
                    if b_offset_fits_bits((dst_addr - src_addr) / 4) {
                        bl(cb, InstructionOffset::from_bytes((dst_addr - src_addr) as i32));
                    } else {
                        emit_load_value(cb, Self::SCRATCH0, dst_addr as u64);
                        blr(cb, Self::SCRATCH0);
                    }
                },
                Insn::CRet { .. } => {
                    ret(cb, A64Opnd::None);
                },
                Insn::Cmp { left, right } => {
                    cmp(cb, left.into(), right.into());
                },
                Insn::Test { left, right } => {
                    tst(cb, left.into(), right.into());
                },
                Insn::JmpOpnd(opnd) => {
                    br(cb, opnd.into());
                },
                Insn::Jmp(target) => {
                    match target {
                        Target::CodePtr(dst_ptr) => {
                            let src_addr = cb.get_write_ptr().into_i64();
                            let dst_addr = dst_ptr.into_i64();

                            // If the offset is short enough, then we'll use the
                            // branch instruction. Otherwise, we'll move the
                            // destination into a register and use the branch
                            // register instruction.
                            let num_insns = if b_offset_fits_bits((dst_addr - src_addr) / 4) {
                                b(cb, InstructionOffset::from_bytes((dst_addr - src_addr) as i32));
                                0
                            } else {
                                let num_insns = emit_load_value(cb, Self::SCRATCH0, dst_addr as u64);
                                br(cb, Self::SCRATCH0);
                                num_insns
                            };

                            // Make sure it's always a consistent number of
                            // instructions in case it gets patched and has to
                            // use the other branch.
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
                            cb.label_ref(*label_idx, 4, |cb, src_addr, dst_addr| {
                                let bytes: i32 = (dst_addr - (src_addr - 4)).try_into().unwrap();
                                b(cb, InstructionOffset::from_bytes(bytes));
                            });
                        },
                        _ => unreachable!()
                    };
                },
                Insn::Je(target) | Insn::Jz(target) => {
                    emit_conditional_jump::<{Condition::EQ}>(cb, *target);
                },
                Insn::Jne(target) | Insn::Jnz(target) => {
                    emit_conditional_jump::<{Condition::NE}>(cb, *target);
                },
                Insn::Jl(target) => {
                    emit_conditional_jump::<{Condition::LT}>(cb, *target);
                },
                Insn::Jbe(target) => {
                    emit_conditional_jump::<{Condition::LS}>(cb, *target);
                },
                Insn::Jo(target) => {
                    emit_conditional_jump::<{Condition::VS}>(cb, *target);
                },
                Insn::IncrCounter { mem, value } => {
                    let label = cb.new_label("incr_counter_loop".to_string());
                    cb.write_label(label);

                    ldaxr(cb, Self::SCRATCH0, mem.into());
                    add(cb, Self::SCRATCH0, Self::SCRATCH0, value.into());

                    // The status register that gets used to track whether or
                    // not the store was successful must be 32 bytes. Since we
                    // store the SCRATCH registers as their 64-bit versions, we
                    // need to rewrap it here.
                    let status = A64Opnd::Reg(Self::SCRATCH1.unwrap_reg().with_num_bits(32));
                    stlxr(cb, status, Self::SCRATCH0, mem.into());

                    cmp(cb, Self::SCRATCH1, A64Opnd::new_uimm(0));
                    emit_conditional_jump::<{Condition::NE}>(cb, Target::Label(label));
                },
                Insn::Breakpoint => {
                    brk(cb, A64Opnd::None);
                },
                Insn::CSelZ { truthy, falsy, out } |
                Insn::CSelE { truthy, falsy, out } => {
                    csel(cb, out.into(), truthy.into(), falsy.into(), Condition::EQ);
                },
                Insn::CSelNZ { truthy, falsy, out } |
                Insn::CSelNE { truthy, falsy, out } => {
                    csel(cb, out.into(), truthy.into(), falsy.into(), Condition::NE);
                },
                Insn::CSelL { truthy, falsy, out } => {
                    csel(cb, out.into(), truthy.into(), falsy.into(), Condition::LT);
                },
                Insn::CSelLE { truthy, falsy, out } => {
                    csel(cb, out.into(), truthy.into(), falsy.into(), Condition::LE);
                },
                Insn::CSelG { truthy, falsy, out } => {
                    csel(cb, out.into(), truthy.into(), falsy.into(), Condition::GT);
                },
                Insn::CSelGE { truthy, falsy, out } => {
                    csel(cb, out.into(), truthy.into(), falsy.into(), Condition::GE);
                }
                Insn::LiveReg { .. } => (), // just a reg alloc signal, no code
                Insn::PadEntryExit => {
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

        let start_write_pos = cb.get_write_pos();
        let gc_offsets = asm.arm64_emit(cb);

        if !cb.has_dropped_bytes() {
            cb.link_labels();
        }

        // Invalidate icache for newly written out region so we don't run stale code.
        #[cfg(not(test))]
        {
            let start = cb.get_ptr(start_write_pos).raw_ptr();
            let write_ptr = cb.get_write_ptr().raw_ptr();
            let codeblock_end = cb.get_ptr(cb.get_mem_size()).raw_ptr();
            let end = std::cmp::min(write_ptr, codeblock_end);
            unsafe { rb_yjit_icache_invalidate(start as _, end as _) };
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
    fn test_emit_je_fits_into_bcond() {
        let (mut asm, mut cb) = setup_asm();

        let offset = 80;
        let target: CodePtr = ((cb.get_write_ptr().into_u64() + offset) as *mut u8).into();

        asm.je(Target::CodePtr(target));
        asm.compile_with_num_regs(&mut cb, 0);
    }

    #[test]
    fn test_emit_je_does_not_fit_into_bcond() {
        let (mut asm, mut cb) = setup_asm();

        let offset = 1 << 21;
        let target: CodePtr = ((cb.get_write_ptr().into_u64() + offset) as *mut u8).into();

        asm.je(Target::CodePtr(target));
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
