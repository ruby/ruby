#![allow(dead_code)] // For instructions and operands we're not currently using.

use crate::asm::CodeBlock;

mod arg;
mod inst;
mod opnd;

use inst::*;

// We're going to make these public to make using these things easier in the
// backend (so they don't have to have knowledge about the submodule).
pub use arg::*;
pub use opnd::*;

/// Checks that a signed value fits within the specified number of bits.
pub const fn imm_fits_bits(imm: i64, num_bits: u8) -> bool {
    let minimum = if num_bits == 64 { i64::MIN } else { -2_i64.pow((num_bits as u32) - 1) };
    let maximum = if num_bits == 64 { i64::MAX } else { 2_i64.pow((num_bits as u32) - 1) - 1 };

    imm >= minimum && imm <= maximum
}

/// Checks that an unsigned value fits within the specified number of bits.
pub const fn uimm_fits_bits(uimm: u64, num_bits: u8) -> bool {
    let maximum = if num_bits == 64 { u64::MAX } else { 2_u64.pow(num_bits as u32) - 1 };

    uimm <= maximum
}

/// ADD - add rn and rm, put the result in rd, don't update flags
pub fn add(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataReg::add(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(uimm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(uimm_fits_bits(uimm12, 12), "The immediate operand must be 12 bits or less.");

            DataImm::add(rd.reg_no, rn.reg_no, uimm12 as u16, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Imm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(imm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            if imm12 < 0 {
                DataImm::sub(rd.reg_no, rn.reg_no, -imm12 as u16, rd.num_bits).into()
            } else {
                DataImm::add(rd.reg_no, rn.reg_no, imm12 as u16, rd.num_bits).into()
            }
        },
        _ => panic!("Invalid operand combination to add instruction."),
    };

    cb.write_bytes(&bytes);
}

/// ADDS - add rn and rm, put the result in rd, update flags
pub fn adds(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataReg::adds(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(uimm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            DataImm::adds(rd.reg_no, rn.reg_no, imm12 as u16, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Imm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(imm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            if imm12 < 0 {
                DataImm::subs(rd.reg_no, rn.reg_no, -imm12 as u16, rd.num_bits).into()
            } else {
                DataImm::adds(rd.reg_no, rn.reg_no, imm12 as u16, rd.num_bits).into()
            }
        },
        _ => panic!("Invalid operand combination to adds instruction."),
    };

    cb.write_bytes(&bytes);
}

/// AND - and rn and rm, put the result in rd, don't update flags
pub fn and(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            LogicalReg::and(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");

            LogicalImm::and(rd.reg_no, rn.reg_no, imm.try_into().unwrap(), rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to and instruction."),
    };

    cb.write_bytes(&bytes);
}

/// ANDS - and rn and rm, put the result in rd, update flags
pub fn ands(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            LogicalReg::ands(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");

            LogicalImm::ands(rd.reg_no, rn.reg_no, imm.try_into().unwrap(), rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ands instruction."),
    };

    cb.write_bytes(&bytes);
}

/// Whether or not the offset between two instructions fits into the branch with
/// or without link instruction. If it doesn't, then we have to load the value
/// into a register first.
pub const fn b_offset_fits_bits(offset: i64) -> bool {
    imm_fits_bits(offset, 26)
}

/// B - branch without link (offset is number of instructions to jump)
pub fn b(cb: &mut CodeBlock, imm26: A64Opnd) {
    let bytes: [u8; 4] = match imm26 {
        A64Opnd::Imm(imm26) => {
            assert!(b_offset_fits_bits(imm26), "The immediate operand must be 26 bits or less.");

            Call::b(imm26 as i32).into()
        },
        _ => panic!("Invalid operand combination to b instruction.")
    };

    cb.write_bytes(&bytes);
}

/// Whether or not the offset between two instructions fits into the b.cond
/// instruction. If it doesn't, then we have to load the value into a register
/// first, then use the b.cond instruction to skip past a direct jump.
pub const fn bcond_offset_fits_bits(offset: i64) -> bool {
    imm_fits_bits(offset, 21) && (offset & 0b11 == 0)
}

/// B.cond - branch to target if condition is true
pub fn bcond(cb: &mut CodeBlock, cond: Condition, byte_offset: A64Opnd) {
    let bytes: [u8; 4] = match byte_offset {
        A64Opnd::Imm(imm) => {
            assert!(bcond_offset_fits_bits(imm), "The immediate operand must be 21 bits or less and be aligned to a 2-bit boundary.");

            BranchCond::bcond(cond, imm as i32).into()
        },
        _ => panic!("Invalid operand combination to bcond instruction."),
    };

    cb.write_bytes(&bytes);
}

/// BL - branch with link (offset is number of instructions to jump)
pub fn bl(cb: &mut CodeBlock, imm26: A64Opnd) {
    let bytes: [u8; 4] = match imm26 {
        A64Opnd::Imm(imm26) => {
            assert!(b_offset_fits_bits(imm26), "The immediate operand must be 26 bits or less.");

            Call::bl(imm26 as i32).into()
        },
        _ => panic!("Invalid operand combination to bl instruction.")
    };

    cb.write_bytes(&bytes);
}

/// BR - branch to a register
pub fn br(cb: &mut CodeBlock, rn: A64Opnd) {
    let bytes: [u8; 4] = match rn {
        A64Opnd::Reg(rn) => Branch::br(rn.reg_no).into(),
        _ => panic!("Invalid operand to br instruction."),
    };

    cb.write_bytes(&bytes);
}

/// BRK - create a breakpoint
pub fn brk(cb: &mut CodeBlock, imm16: A64Opnd) {
    let bytes: [u8; 4] = match imm16 {
        A64Opnd::None => Breakpoint::brk(0).into(),
        A64Opnd::UImm(imm16) => {
            assert!(uimm_fits_bits(imm16, 16), "The immediate operand must be 16 bits or less.");
            Breakpoint::brk(imm16 as u16).into()
        },
        _ => panic!("Invalid operand combination to brk instruction.")
    };

    cb.write_bytes(&bytes);
}

/// CMP - compare rn and rm, update flags
pub fn cmp(cb: &mut CodeBlock, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rn, rm) {
        (A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataReg::cmp(rn.reg_no, rm.reg_no, rn.num_bits).into()
        },
        (A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(uimm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            DataImm::cmp(rn.reg_no, imm12 as u16, rn.num_bits).into()
        },
        _ => panic!("Invalid operand combination to cmp instruction."),
    };

    cb.write_bytes(&bytes);
}

/// LDADDAL - atomic add with acquire and release semantics
pub fn ldaddal(cb: &mut CodeBlock, rs: A64Opnd, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rs, rt, rn) {
        (A64Opnd::Reg(rs), A64Opnd::Reg(rt), A64Opnd::Reg(rn)) => {
            assert!(
                rs.num_bits == rt.num_bits && rt.num_bits == rn.num_bits,
                "All operands must be of the same size."
            );

            Atomic::ldaddal(rs.reg_no, rt.reg_no, rn.reg_no, rs.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldaddal instruction."),
    };

    cb.write_bytes(&bytes);
}

/// LDR - load a PC-relative memory address into a register
pub fn ldr(cb: &mut CodeBlock, rt: A64Opnd, rn: i32) {
    let bytes: [u8; 4] = match rt {
        A64Opnd::Reg(rt) => {
            LoadLiteral::ldr(rt.reg_no, rn, rt.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldr instruction."),
    };

    cb.write_bytes(&bytes);
}

/// LDUR - load a memory address into a register
pub fn ldur(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Reg(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "All operands must be of the same size.");

            Load::ldur(rt.reg_no, rn.reg_no, 0, rt.num_bits).into()
        },
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 9), "Expected displacement to be 9 bits or less");

            Load::ldur(rt.reg_no, rn.base_reg_no, rn.disp as i16, rt.num_bits).into()
        },
        _ => panic!("Invalid operands for LDUR")
    };

    cb.write_bytes(&bytes);
}

/// LSL - logical shift left a register by an immediate
pub fn lsl(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, shift: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, shift) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(uimm)) => {
            assert!(rd.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(uimm_fits_bits(uimm, 6), "Expected shift to be 6 bits or less");

            ShiftImm::lsl(rd.reg_no, rn.reg_no, uimm as u8, rd.num_bits).into()
        },
        _ => panic!("Invalid operands combination to lsl instruction")
    };

    cb.write_bytes(&bytes);
}

/// LSR - logical shift right a register by an immediate
pub fn lsr(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, shift: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, shift) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(uimm)) => {
            assert!(rd.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(uimm_fits_bits(uimm, 6), "Expected shift to be 6 bits or less");

            ShiftImm::lsr(rd.reg_no, rn.reg_no, uimm as u8, rd.num_bits).into()
        },
        _ => panic!("Invalid operands combination to lsr instruction")
    };

    cb.write_bytes(&bytes);
}

/// MOV - move a value in a register to another register
pub fn mov(cb: &mut CodeBlock, rd: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rm)) => {
            assert!(rd.num_bits == rm.num_bits, "Expected registers to be the same size");

            LogicalReg::mov(rd.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::UImm(imm)) => {
            LogicalImm::mov(rd.reg_no, imm.try_into().unwrap(), rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to mov instruction")
    };

    cb.write_bytes(&bytes);
}

/// MOVK - move a 16 bit immediate into a register, keep the other bits in place
pub fn movk(cb: &mut CodeBlock, rd: A64Opnd, imm16: A64Opnd, shift: u8) {
    let bytes: [u8; 4] = match (rd, imm16) {
        (A64Opnd::Reg(rd), A64Opnd::UImm(imm16)) => {
            assert!(uimm_fits_bits(imm16, 16), "The immediate operand must be 16 bits or less.");

            Mov::movk(rd.reg_no, imm16 as u16, shift, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to movk instruction.")
    };

    cb.write_bytes(&bytes);
}

/// MOVZ - move a 16 bit immediate into a register, zero the other bits
pub fn movz(cb: &mut CodeBlock, rd: A64Opnd, imm16: A64Opnd, shift: u8) {
    let bytes: [u8; 4] = match (rd, imm16) {
        (A64Opnd::Reg(rd), A64Opnd::UImm(imm16)) => {
            assert!(uimm_fits_bits(imm16, 16), "The immediate operand must be 16 bits or less.");

            Mov::movz(rd.reg_no, imm16 as u16, shift, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to movz instruction.")
    };

    cb.write_bytes(&bytes);
}

/// MVN - move a value in a register to another register, negating it
pub fn mvn(cb: &mut CodeBlock, rd: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rm)) => {
            assert!(rd.num_bits == rm.num_bits, "Expected registers to be the same size");

            LogicalReg::mvn(rd.reg_no, rm.reg_no, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to mvn instruction")
    };

    cb.write_bytes(&bytes);
}

/// NOP - no-operation, used for alignment purposes
pub fn nop(cb: &mut CodeBlock) {
    let bytes: [u8; 4] = Nop::nop().into();

    cb.write_bytes(&bytes);
}

/// ORN - perform a bitwise OR of rn and NOT rm, put the result in rd, don't update flags
pub fn orn(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits, "Expected registers to be the same size");

            LogicalReg::orn(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to orn instruction.")
    };

    cb.write_bytes(&bytes);
}

/// ORR - perform a bitwise OR of rn and rm, put the result in rd, don't update flags
pub fn orr(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            LogicalReg::orr(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");

            LogicalImm::orr(rd.reg_no, rn.reg_no, imm.try_into().unwrap(), rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to orr instruction."),
    };

    cb.write_bytes(&bytes);
}

/// STUR - store a value in a register at a memory address
pub fn stur(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 9), "Expected displacement to be 9 bits or less");

            Store::stur(rt.reg_no, rn.base_reg_no, rn.disp as i16, rt.num_bits).into()
        },
        _ => panic!("Invalid operand combination to stur instruction.")
    };

    cb.write_bytes(&bytes);
}

/// SUB - subtract rm from rn, put the result in rd, don't update flags
pub fn sub(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataReg::sub(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(uimm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(uimm_fits_bits(uimm12, 12), "The immediate operand must be 12 bits or less.");

            DataImm::sub(rd.reg_no, rn.reg_no, uimm12 as u16, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Imm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(imm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            if imm12 < 0 {
                DataImm::add(rd.reg_no, rn.reg_no, -imm12 as u16, rd.num_bits).into()
            } else {
                DataImm::sub(rd.reg_no, rn.reg_no, imm12 as u16, rd.num_bits).into()
            }
        },
        _ => panic!("Invalid operand combination to sub instruction."),
    };

    cb.write_bytes(&bytes);
}

/// SUBS - subtract rm from rn, put the result in rd, update flags
pub fn subs(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataReg::subs(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(uimm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(uimm_fits_bits(uimm12, 12), "The immediate operand must be 12 bits or less.");

            DataImm::subs(rd.reg_no, rn.reg_no, uimm12 as u16, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Imm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(imm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            if imm12 < 0 {
                DataImm::adds(rd.reg_no, rn.reg_no, -imm12 as u16, rd.num_bits).into()
            } else {
                DataImm::subs(rd.reg_no, rn.reg_no, imm12 as u16, rd.num_bits).into()
            }
        },
        _ => panic!("Invalid operand combination to subs instruction."),
    };

    cb.write_bytes(&bytes);
}

/// RET - unconditionally return to a location in a register, defaults to X30
pub fn ret(cb: &mut CodeBlock, rn: A64Opnd) {
    let bytes: [u8; 4] = match rn {
        A64Opnd::None => Branch::ret(30).into(),
        A64Opnd::Reg(reg) => Branch::ret(reg.reg_no).into(),
        _ => panic!("Invalid operand to ret instruction.")
    };

    cb.write_bytes(&bytes);
}

/// TST - test the bits of a register against a mask, then update flags
pub fn tst(cb: &mut CodeBlock, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rn, rm) {
        (A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(rn.num_bits == rm.num_bits, "All operands must be of the same size.");

            LogicalReg::tst(rn.reg_no, rm.reg_no, rn.num_bits).into()
        },
        (A64Opnd::Reg(rn), A64Opnd::UImm(imm)) => {
            LogicalImm::tst(rn.reg_no, imm.try_into().unwrap(), rn.num_bits).into()
        },
        _ => panic!("Invalid operand combination to tst instruction."),
    };

    cb.write_bytes(&bytes);
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Check that the bytes for an instruction sequence match a hex string
    fn check_bytes<R>(bytes: &str, run: R) where R: FnOnce(&mut super::CodeBlock) {
        let mut cb = super::CodeBlock::new_dummy(128);
        run(&mut cb);
        assert_eq!(format!("{:x}", cb), bytes);
    }

    #[test]
    fn test_imm_fits_bits() {
        assert!(imm_fits_bits(i8::MAX.into(), 8));
        assert!(imm_fits_bits(i8::MIN.into(), 8));

        assert!(imm_fits_bits(i16::MAX.into(), 16));
        assert!(imm_fits_bits(i16::MIN.into(), 16));

        assert!(imm_fits_bits(i32::MAX.into(), 32));
        assert!(imm_fits_bits(i32::MIN.into(), 32));

        assert!(imm_fits_bits(i64::MAX.into(), 64));
        assert!(imm_fits_bits(i64::MIN.into(), 64));
    }

    #[test]
    fn test_uimm_fits_bits() {
        assert!(uimm_fits_bits(u8::MAX.into(), 8));
        assert!(uimm_fits_bits(u16::MAX.into(), 16));
        assert!(uimm_fits_bits(u32::MAX.into(), 32));
        assert!(uimm_fits_bits(u64::MAX.into(), 64));
    }

    #[test]
    fn test_add_reg() {
        check_bytes("2000028b", |cb| add(cb, X0, X1, X2));
    }

    #[test]
    fn test_add_uimm() {
        check_bytes("201c0091", |cb| add(cb, X0, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_add_imm_positive() {
        check_bytes("201c0091", |cb| add(cb, X0, X1, A64Opnd::new_imm(7)));
    }

    #[test]
    fn test_add_imm_negative() {
        check_bytes("201c00d1", |cb| add(cb, X0, X1, A64Opnd::new_imm(-7)));
    }

    #[test]
    fn test_adds_reg() {
        check_bytes("200002ab", |cb| adds(cb, X0, X1, X2));
    }

    #[test]
    fn test_adds_uimm() {
        check_bytes("201c00b1", |cb| adds(cb, X0, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_adds_imm_positive() {
        check_bytes("201c00b1", |cb| adds(cb, X0, X1, A64Opnd::new_imm(7)));
    }

    #[test]
    fn test_adds_imm_negatve() {
        check_bytes("201c00f1", |cb| adds(cb, X0, X1, A64Opnd::new_imm(-7)));
    }

    #[test]
    fn test_and_register() {
        check_bytes("2000028a", |cb| and(cb, X0, X1, X2));
    }

    #[test]
    fn test_and_immediate() {
        check_bytes("20084092", |cb| and(cb, X0, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_ands_register() {
        check_bytes("200002ea", |cb| ands(cb, X0, X1, X2));
    }

    #[test]
    fn test_ands_immediate() {
        check_bytes("200840f2", |cb| ands(cb, X0, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_bcond() {
        check_bytes("01200054", |cb| bcond(cb, Condition::NE, A64Opnd::new_imm(0x400)));
    }

    #[test]
    fn test_b() {
        check_bytes("00040014", |cb| b(cb, A64Opnd::new_imm(1024)));
    }

    #[test]
    fn test_bl() {
        check_bytes("00040094", |cb| bl(cb, A64Opnd::new_imm(1024)));
    }

    #[test]
    fn test_br() {
        check_bytes("80021fd6", |cb| br(cb, X20));
    }

    #[test]
    fn test_brk_none() {
        check_bytes("000020d4", |cb| brk(cb, A64Opnd::None));
    }

    #[test]
    fn test_brk_uimm() {
        check_bytes("c00120d4", |cb| brk(cb, A64Opnd::new_uimm(14)));
    }

    #[test]
    fn test_cmp_register() {
        check_bytes("5f010beb", |cb| cmp(cb, X10, X11));
    }

    #[test]
    fn test_cmp_immediate() {
        check_bytes("5f3900f1", |cb| cmp(cb, X10, A64Opnd::new_uimm(14)));
    }

    #[test]
    fn test_ldaddal() {
        check_bytes("8b01eaf8", |cb| ldaddal(cb, X10, X11, X12));
    }

    #[test]
    fn test_ldr() {
        check_bytes("40010058", |cb| ldr(cb, X0, 10));
    }

    #[test]
    fn test_ldur_memory() {
        check_bytes("20b047f8", |cb| ldur(cb, X0, A64Opnd::new_mem(64, X1, 123)));
    }

    #[test]
    fn test_ldur_register() {
        check_bytes("200040f8", |cb| ldur(cb, X0, X1));
    }

    #[test]
    fn test_lsl() {
        check_bytes("6ac572d3", |cb| lsl(cb, X10, X11, A64Opnd::new_uimm(14)));
    }

    #[test]
    fn test_lsr() {
        check_bytes("6afd4ed3", |cb| lsr(cb, X10, X11, A64Opnd::new_uimm(14)));
    }

    #[test]
    fn test_mov_registers() {
        check_bytes("ea030baa", |cb| mov(cb, X10, X11));
    }

    #[test]
    fn test_mov_immediate() {
        check_bytes("eaf300b2", |cb| mov(cb, X10, A64Opnd::new_uimm(0x5555555555555555)));
    }

    #[test]
    fn test_movk() {
        check_bytes("600fa0f2", |cb| movk(cb, X0, A64Opnd::new_uimm(123), 16));
    }

    #[test]
    fn test_movz() {
        check_bytes("600fa0d2", |cb| movz(cb, X0, A64Opnd::new_uimm(123), 16));
    }

    #[test]
    fn test_mvn() {
        check_bytes("ea032baa", |cb| mvn(cb, X10, X11));
    }

    #[test]
    fn test_nop() {
        check_bytes("1f2003d5", |cb| nop(cb));
    }

    #[test]
    fn test_orn() {
        check_bytes("6a012caa", |cb| orn(cb, X10, X11, X12));
    }

    #[test]
    fn test_orr_register() {
        check_bytes("6a010caa", |cb| orr(cb, X10, X11, X12));
    }

    #[test]
    fn test_orr_immediate() {
        check_bytes("6a0940b2", |cb| orr(cb, X10, X11, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_ret_none() {
        check_bytes("c0035fd6", |cb| ret(cb, A64Opnd::None));
    }

    #[test]
    fn test_ret_register() {
        check_bytes("80025fd6", |cb| ret(cb, X20));
    }

    #[test]
    fn test_stur() {
        check_bytes("6a0108f8", |cb| stur(cb, X10, A64Opnd::new_mem(64, X11, 128)));
    }

    #[test]
    fn test_sub_reg() {
        check_bytes("200002cb", |cb| sub(cb, X0, X1, X2));
    }

    #[test]
    fn test_sub_uimm() {
        check_bytes("201c00d1", |cb| sub(cb, X0, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_sub_imm_positive() {
        check_bytes("201c00d1", |cb| sub(cb, X0, X1, A64Opnd::new_imm(7)));
    }

    #[test]
    fn test_sub_imm_negative() {
        check_bytes("201c0091", |cb| sub(cb, X0, X1, A64Opnd::new_imm(-7)));
    }

    #[test]
    fn test_subs_reg() {
        check_bytes("200002eb", |cb| subs(cb, X0, X1, X2));
    }

    #[test]
    fn test_subs_imm_positive() {
        check_bytes("201c00f1", |cb| subs(cb, X0, X1, A64Opnd::new_imm(7)));
    }

    #[test]
    fn test_subs_imm_negative() {
        check_bytes("201c00b1", |cb| subs(cb, X0, X1, A64Opnd::new_imm(-7)));
    }

    #[test]
    fn test_subs_uimm() {
        check_bytes("201c00f1", |cb| subs(cb, X0, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_tst_register() {
        check_bytes("1f0001ea", |cb| tst(cb, X0, X1));
    }

    #[test]
    fn test_tst_immediate() {
        check_bytes("3f0840f2", |cb| tst(cb, X1, A64Opnd::new_uimm(7)));
    }
}
