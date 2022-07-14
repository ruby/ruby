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
pub const C_SP_STEP: A64Opnd = A64Opnd::UImm(16);

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
            Opnd::None => panic!("attempted to lower an Opnd::None"),
            Opnd::Value(_) => panic!("attempted to lower an Opnd::Value"),
        }
    }
}

impl Assembler
{
    /// Get the list of registers from which we will allocate on this platform
    /// These are caller-saved registers
    /// Note: we intentionally exclude C_RET_REG (X0) from this list
    /// because of the way it's used in gen_leave() and gen_leave_exit()
    pub fn get_alloc_regs() -> Vec<Reg> {
        vec![X11_REG, X12_REG]
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
        self.forward_pass(|asm, index, op, opnds, target| {
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
                Op::Add | Op::And | Op::Sub => {
                    // Check if one of the operands is a register. If it is,
                    // then we'll make that the first operand.
                    match (opnds[0], opnds[1]) {
                        (Opnd::Mem(_), Opnd::Mem(_)) => {
                            let opnd0 = asm.load(opnds[0]);
                            let opnd1 = asm.load(opnds[1]);
                            asm.push_insn(op, vec![opnd0, opnd1], target);
                        },
                        (mem_opnd @ Opnd::Mem(_), other_opnd) |
                        (other_opnd, mem_opnd @ Opnd::Mem(_)) => {
                            let opnd0 = asm.load(mem_opnd);
                            asm.push_insn(op, vec![opnd0, other_opnd], target);
                        },
                        _ => {
                            asm.push_insn(op, opnds, target);
                        }
                    }
                },
                Op::CCall => {
                    assert!(opnds.len() < C_ARG_REGS.len());

                    // For each of the operands we're going to first load them
                    // into a register and then move them into the correct
                    // argument register.
                    for (idx, opnd) in opnds.into_iter().enumerate() {
                        let value = asm.load(opnd);
                        asm.mov(Opnd::Reg(C_ARG_REGREGS[idx]), value);
                    }

                    // Now we push the CCall without any arguments so that it
                    // just performs the call.
                    asm.ccall(target.unwrap().unwrap_fun_ptr(), vec![]);
                },
                Op::CRet => {
                    if opnds[0] != Opnd::Reg(C_RET_REG) {
                        let value = asm.load(opnds[0]);
                        asm.mov(C_RET_OPND, value);
                    }
                    asm.cret(C_RET_OPND);
                },
                Op::IncrCounter => {
                    // Every operand to the IncrCounter instruction need to be a
                    // register once it gets there. So here we're going to load
                    // anything that isn't a register first.
                    let new_opnds: Vec<Opnd> = opnds.into_iter().map(|opnd| {
                        match opnd {
                            Opnd::Mem(_) | Opnd::Imm(_) | Opnd::UImm(_) => asm.load(opnd),
                            _ => opnd,
                        }
                    }).collect();

                    asm.incr_counter(new_opnds[0], new_opnds[1]);
                },
                Op::JmpOpnd => {
                    if let Opnd::Mem(_) = opnds[0] {
                        let opnd0 = asm.load(opnds[0]);
                        asm.jmp_opnd(opnd0);
                    } else {
                        asm.jmp_opnd(opnds[0]);
                    }
                },
                Op::Mov => {
                    // The value that is being moved must be either a register
                    // or an immediate that can be encoded as a bitmask
                    // immediate. Otherwise, we'll need to split the move into
                    // multiple instructions.
                    let value = match opnds[1] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[1],
                        Opnd::Mem(_) | Opnd::Imm(_) => asm.load(opnds[1]),
                        Opnd::UImm(uimm) => {
                            if let Ok(encoded) = BitmaskImmediate::try_from(uimm) {
                                if let Opnd::Mem(_) = opnds[0] {
                                    // If the first operand is a memory operand,
                                    // we're going to transform this into a
                                    // store instruction, so we'll need to load
                                    // this anyway.
                                    asm.load(opnds[1])
                                } else {
                                    opnds[1]
                                }
                            } else {
                                asm.load(opnds[1])
                            }
                        },
                        _ => unreachable!()
                    };

                    // If we're attempting to load into a memory operand, then
                    // we'll switch over to the store instruction. Otherwise
                    // we'll use the normal mov instruction.
                    match opnds[0] {
                        Opnd::Mem(_) => asm.store(opnds[0], value),
                        _ => asm.mov(opnds[0], value)
                    };
                },
                Op::Not => {
                    // The value that is being negated must be in a register, so
                    // if we get anything else we need to load it first.
                    let opnd0 = match opnds[0] {
                        Opnd::Mem(_) => asm.load(opnds[0]),
                        _ => opnds[0]
                    };

                    asm.not(opnd0);
                },
                Op::Store => {
                    // The value being stored must be in a register, so if it's
                    // not already one we'll load it first.
                    let opnd1 = match opnds[1] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[1],
                        _ => asm.load(opnds[1])
                    };

                    asm.store(opnds[0], opnd1);
                },
                Op::Test => {
                    // The value being tested must be in a register, so if it's
                    // not already one we'll load it first.
                    let opnd0 = match opnds[0] {
                        Opnd::Reg(_) | Opnd::InsnOut { .. } => opnds[0],
                        _ => asm.load(opnds[0])
                    };

                    asm.test(opnd0, opnds[1]);
                },
                _ => {
                    asm.push_insn(op, opnds, target);
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
                    let src_addr = cb.get_write_ptr().into_i64() + 4;
                    let dst_addr = dst_ptr.into_i64();
                    let offset = dst_addr - src_addr;

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
                        bcond(cb, CONDITION, A64Opnd::new_imm(4));

                        // If the offset fits into a direct jump, then we'll use
                        // that and the number of instructions will be shorter.
                        // Otherwise we'll use the branch register instruction.
                        if b_offset_fits_bits(offset) {
                            // If we get to this instruction, then the condition
                            // wasn't met, in which case we'll jump past the
                            // next instruction that performs the direct jump.
                            b(cb, A64Opnd::new_imm(1));

                            // Here we'll perform the direct jump to the target.
                            b(cb, A64Opnd::new_imm(offset / 4));
                        } else {
                            // If we get to this instruction, then the condition
                            // wasn't met, in which case we'll jump past the
                            // next instruction that perform the direct jump.
                            let value = dst_addr as u64;

                            b(cb, A64Opnd::new_imm(emit_load_size(value).into()));
                            emit_load_value(cb, X29, value);
                            br(cb, X29);
                        }
                    }
                },
                Target::Label(label_idx) => {
                    // Here we're going to save enough space for ourselves and
                    // then come back and write the instruction once we know the
                    // offset. We're going to assume we can fit into a single
                    // b.cond instruction. It will panic otherwise.
                    cb.label_ref(label_idx, 4, |cb, src_addr, dst_addr| {
                        bcond(cb, CONDITION, A64Opnd::new_imm(dst_addr - src_addr));
                    });
                },
                Target::FunPtr(_) => unreachable!()
            };
        }

        /// Emit a push instruction for the given operand by adding to the stack
        /// pointer and then storing the given value.
        fn emit_push(cb: &mut CodeBlock, opnd: A64Opnd) {
            add(cb, C_SP_REG, C_SP_REG, C_SP_STEP);
            stur(cb, opnd, A64Opnd::new_mem(64, C_SP_REG, 0));
        }

        /// Emit a pop instruction into the given operand by loading the value
        /// and then subtracting from the stack pointer.
        fn emit_pop(cb: &mut CodeBlock, opnd: A64Opnd) {
            ldur(cb, opnd, A64Opnd::new_mem(64, C_SP_REG, 0));
            sub(cb, C_SP_REG, C_SP_REG, C_SP_STEP);
        }

        // dbg!(&self.insns);

        // List of GC offsets
        let mut gc_offsets: Vec<u32> = Vec::new();

        // A special scratch register for loading/storing system registers.
        let mut sys_scratch = A64Opnd::Reg(X22_REG);

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
                Op::Add => {
                    add(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::Sub => {
                    sub(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::And => {
                    and(cb, insn.out.into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::Not => {
                    mvn(cb, insn.out.into(), insn.opnds[0].into());
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
                            ldr(cb, insn.out.into(), 1);
                            b(cb, A64Opnd::new_imm((SIZEOF_VALUE as i64) / 4));
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
                Op::CPush => {
                    emit_push(cb, insn.opnds[0].into());
                },
                Op::CPushAll => {
                    let regs = Assembler::get_caller_save_regs();

                    for reg in regs {
                        emit_push(cb, A64Opnd::Reg(reg));
                    }

                    mrs(cb, sys_scratch, SystemRegister::NZCV);
                    emit_push(cb, sys_scratch);
                },
                Op::CPop => {
                    emit_pop(cb, insn.out.into());
                },
                Op::CPopInto => {
                    emit_pop(cb, insn.opnds[0].into());
                },
                Op::CPopAll => {
                    let regs = Assembler::get_caller_save_regs();

                    msr(cb, SystemRegister::NZCV, sys_scratch);
                    emit_pop(cb, sys_scratch);

                    for reg in regs.into_iter().rev() {
                        emit_pop(cb, A64Opnd::Reg(reg));
                    }
                },
                Op::CCall => {
                    let src_addr = cb.get_write_ptr().into_i64() + 4;
                    let dst_addr = insn.target.unwrap().unwrap_fun_ptr() as i64;

                    // The offset between the two instructions in bytes. Note
                    // that when we encode this into a bl instruction, we'll
                    // divide by 4 because it accepts the number of instructions
                    // to jump over.
                    let offset = dst_addr - src_addr;

                    // If the offset is short enough, then we'll use the branch
                    // link instruction. Otherwise, we'll move the destination
                    // and return address into appropriate registers and use the
                    // branch register instruction.
                    if b_offset_fits_bits(offset) {
                        bl(cb, A64Opnd::new_imm(offset / 4));
                    } else {
                        emit_load_value(cb, X30, src_addr as u64);
                        emit_load_value(cb, X29, dst_addr as u64);
                        br(cb, X29);
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
                            let src_addr = cb.get_write_ptr().into_i64() + 4;
                            let dst_addr = dst_ptr.into_i64();

                            // The offset between the two instructions in bytes.
                            // Note that when we encode this into a b
                            // instruction, we'll divide by 4 because it accepts
                            // the number of instructions to jump over.
                            let offset = dst_addr - src_addr;

                            // If the offset is short enough, then we'll use the
                            // branch instruction. Otherwise, we'll move the
                            // destination into a register and use the branch
                            // register instruction.
                            if b_offset_fits_bits(offset) {
                                b(cb, A64Opnd::new_imm(offset / 4));
                            } else {
                                emit_load_value(cb, X29, dst_addr as u64);
                                br(cb, X29);
                            }
                        },
                        Target::Label(label_idx) => {
                            // Here we're going to save enough space for
                            // ourselves and then come back and write the
                            // instruction once we know the offset. We're going
                            // to assume we can fit into a single b instruction.
                            // It will panic otherwise.
                            cb.label_ref(label_idx, 4, |cb, src_addr, dst_addr| {
                                b(cb, A64Opnd::new_imm((dst_addr - src_addr) / 4));
                            });
                        },
                        _ => unreachable!()
                    };
                },
                Op::Je => {
                    emit_conditional_jump::<{Condition::EQ}>(cb, insn.target.unwrap());
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
                    ldaddal(cb, insn.opnds[0].into(), insn.opnds[0].into(), insn.opnds[1].into());
                },
                Op::Breakpoint => {
                    brk(cb, A64Opnd::None);
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

        let insns = cb.get_ptr(0).raw_ptr() as *const u32;
        assert_eq!(0x8b010003, unsafe { *insns });
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
}
