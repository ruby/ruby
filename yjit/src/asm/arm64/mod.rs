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
    let minimum = if num_bits == 64 { i64::MIN } else { -(2_i64.pow((num_bits as u32) - 1)) };
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

            DataImm::add(rd.reg_no, rn.reg_no, uimm12.try_into().unwrap(), rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Imm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");

            if imm12 < 0 {
                DataImm::sub(rd.reg_no, rn.reg_no, (-imm12 as u64).try_into().unwrap(), rd.num_bits).into()
            } else {
                DataImm::add(rd.reg_no, rn.reg_no, (imm12 as u64).try_into().unwrap(), rd.num_bits).into()
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

            DataImm::adds(rd.reg_no, rn.reg_no, imm12.try_into().unwrap(), rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Imm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");

            if imm12 < 0 {
                DataImm::subs(rd.reg_no, rn.reg_no, (-imm12 as u64).try_into().unwrap(), rd.num_bits).into()
            } else {
                DataImm::adds(rd.reg_no, rn.reg_no, (imm12 as u64).try_into().unwrap(), rd.num_bits).into()
            }
        },
        _ => panic!("Invalid operand combination to adds instruction."),
    };

    cb.write_bytes(&bytes);
}

/// ADR - form a PC-relative address and load it into a register
pub fn adr(cb: &mut CodeBlock, rd: A64Opnd, imm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, imm) {
        (A64Opnd::Reg(rd), A64Opnd::Imm(imm)) => {
            assert!(rd.num_bits == 64, "The destination register must be 64 bits.");
            assert!(imm_fits_bits(imm, 21), "The immediate operand must be 21 bits or less.");

            PCRelative::adr(rd.reg_no, imm as i32).into()
        },
        _ => panic!("Invalid operand combination to adr instruction."),
    };

    cb.write_bytes(&bytes);
}

/// ADRP - form a PC-relative address to a 4KB page and load it into a register.
/// This is effectively the same as ADR except that the immediate must be a
/// multiple of 4KB.
pub fn adrp(cb: &mut CodeBlock, rd: A64Opnd, imm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, imm) {
        (A64Opnd::Reg(rd), A64Opnd::Imm(imm)) => {
            assert!(rd.num_bits == 64, "The destination register must be 64 bits.");
            assert!(imm_fits_bits(imm, 32), "The immediate operand must be 32 bits or less.");

            PCRelative::adrp(rd.reg_no, imm as i32).into()
        },
        _ => panic!("Invalid operand combination to adr instruction."),
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
            let bitmask_imm = if rd.num_bits == 32 {
                BitmaskImmediate::new_32b_reg(imm.try_into().unwrap())
            } else {
                imm.try_into()
            }.unwrap();

            LogicalImm::and(rd.reg_no, rn.reg_no, bitmask_imm, rd.num_bits).into()
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
            let bitmask_imm = if rd.num_bits == 32 {
                BitmaskImmediate::new_32b_reg(imm.try_into().unwrap())
            } else {
                imm.try_into()
            }.unwrap();

            LogicalImm::ands(rd.reg_no, rn.reg_no, bitmask_imm, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ands instruction."),
    };

    cb.write_bytes(&bytes);
}

/// ASR - arithmetic shift right rn by shift, put the result in rd, don't update
/// flags
pub fn asr(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, shift: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, shift) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(shift)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(uimm_fits_bits(shift, 6), "The shift operand must be 6 bits or less.");

            SBFM::asr(rd.reg_no, rn.reg_no, shift.try_into().unwrap(), rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to asr instruction."),
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
pub fn b(cb: &mut CodeBlock, offset: InstructionOffset) {
    assert!(b_offset_fits_bits(offset.into()), "The immediate operand must be 26 bits or less.");
    let bytes: [u8; 4] = Call::b(offset).into();

    cb.write_bytes(&bytes);
}

/// Whether or not the offset in number of instructions between two instructions
/// fits into the b.cond instruction. If it doesn't, then we have to load the
/// value into a register first, then use the b.cond instruction to skip past a
/// direct jump.
pub const fn bcond_offset_fits_bits(offset: i64) -> bool {
    imm_fits_bits(offset, 19)
}

/// B.cond - branch to target if condition is true
pub fn bcond(cb: &mut CodeBlock, cond: u8, offset: InstructionOffset) {
    assert!(bcond_offset_fits_bits(offset.into()), "The offset must be 19 bits or less.");
    let bytes: [u8; 4] = BranchCond::bcond(cond, offset).into();

    cb.write_bytes(&bytes);
}

/// BL - branch with link (offset is number of instructions to jump)
pub fn bl(cb: &mut CodeBlock, offset: InstructionOffset) {
    assert!(b_offset_fits_bits(offset.into()), "The offset must be 26 bits or less.");
    let bytes: [u8; 4] = Call::bl(offset).into();

    cb.write_bytes(&bytes);
}

/// BLR - branch with link to a register
pub fn blr(cb: &mut CodeBlock, rn: A64Opnd) {
    let bytes: [u8; 4] = match rn {
        A64Opnd::Reg(rn) => Branch::blr(rn.reg_no).into(),
        _ => panic!("Invalid operand to blr instruction."),
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
            DataImm::cmp(rn.reg_no, imm12.try_into().unwrap(), rn.num_bits).into()
        },
        _ => panic!("Invalid operand combination to cmp instruction."),
    };

    cb.write_bytes(&bytes);
}

/// CSEL - conditionally select between two registers
pub fn csel(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd, cond: u8) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            Conditional::csel(rd.reg_no, rn.reg_no, rm.reg_no, cond, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to csel instruction."),
    };

    cb.write_bytes(&bytes);
}

/// EOR - perform a bitwise XOR of rn and rm, put the result in rd, don't update flags
pub fn eor(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            LogicalReg::eor(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            let bitmask_imm = if rd.num_bits == 32 {
                BitmaskImmediate::new_32b_reg(imm.try_into().unwrap())
            } else {
                imm.try_into()
            }.unwrap();

            LogicalImm::eor(rd.reg_no, rn.reg_no, bitmask_imm, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to eor instruction."),
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

/// LDAXR - atomic load with acquire semantics
pub fn ldaxr(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Reg(rn)) => {
            assert_eq!(rn.num_bits, 64, "rn must be a 64-bit register.");

            LoadStoreExclusive::ldaxr(rt.reg_no, rn.reg_no, rt.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldaxr instruction."),
    };

    cb.write_bytes(&bytes);
}

/// LDP (signed offset) - load a pair of registers from memory
pub fn ldp(cb: &mut CodeBlock, rt1: A64Opnd, rt2: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt1, rt2, rn) {
        (A64Opnd::Reg(rt1), A64Opnd::Reg(rt2), A64Opnd::Mem(rn)) => {
            assert!(rt1.num_bits == rt2.num_bits, "Expected source registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 10), "The displacement must be 10 bits or less.");
            assert_ne!(rt1.reg_no, rt2.reg_no, "Behavior is unpredictable with pairs of the same register");

            RegisterPair::ldp(rt1.reg_no, rt2.reg_no, rn.base_reg_no, rn.disp as i16, rt1.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldp instruction.")
    };

    cb.write_bytes(&bytes);
}

/// LDP (pre-index) - load a pair of registers from memory, update the base pointer before loading it
pub fn ldp_pre(cb: &mut CodeBlock, rt1: A64Opnd, rt2: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt1, rt2, rn) {
        (A64Opnd::Reg(rt1), A64Opnd::Reg(rt2), A64Opnd::Mem(rn)) => {
            assert!(rt1.num_bits == rt2.num_bits, "Expected source registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 10), "The displacement must be 10 bits or less.");
            assert_ne!(rt1.reg_no, rt2.reg_no, "Behavior is unpredictable with pairs of the same register");

            RegisterPair::ldp_pre(rt1.reg_no, rt2.reg_no, rn.base_reg_no, rn.disp as i16, rt1.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldp instruction.")
    };

    cb.write_bytes(&bytes);
}

/// LDP (post-index) - load a pair of registers from memory, update the base pointer after loading it
pub fn ldp_post(cb: &mut CodeBlock, rt1: A64Opnd, rt2: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt1, rt2, rn) {
        (A64Opnd::Reg(rt1), A64Opnd::Reg(rt2), A64Opnd::Mem(rn)) => {
            assert!(rt1.num_bits == rt2.num_bits, "Expected source registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 10), "The displacement must be 10 bits or less.");
            assert_ne!(rt1.reg_no, rt2.reg_no, "Behavior is unpredictable with pairs of the same register");

            RegisterPair::ldp_post(rt1.reg_no, rt2.reg_no, rn.base_reg_no, rn.disp as i16, rt1.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldp instruction.")
    };

    cb.write_bytes(&bytes);
}

/// LDR - load a memory address into a register with a register offset
pub fn ldr(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn, rm) {
        (A64Opnd::Reg(rt), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(rn.num_bits == rm.num_bits, "Expected registers to be the same size");

            LoadRegister::ldr(rt.reg_no, rn.reg_no, rm.reg_no, rt.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldr instruction.")
    };

    cb.write_bytes(&bytes);
}

/// LDR - load a PC-relative memory address into a register
pub fn ldr_literal(cb: &mut CodeBlock, rt: A64Opnd, rn: InstructionOffset) {
    let bytes: [u8; 4] = match rt {
        A64Opnd::Reg(rt) => {
            LoadLiteral::ldr_literal(rt.reg_no, rn, rt.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldr instruction."),
    };

    cb.write_bytes(&bytes);
}

/// LDRH - load a halfword from memory
pub fn ldrh(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert_eq!(rt.num_bits, 32, "Expected to be loading a halfword");
            assert!(imm_fits_bits(rn.disp.into(), 12), "The displacement must be 12 bits or less.");

            HalfwordImm::ldrh(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operand combination to ldrh instruction.")
    };

    cb.write_bytes(&bytes);
}

/// LDRH (pre-index) - load a halfword from memory, update the base pointer before loading it
pub fn ldrh_pre(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert_eq!(rt.num_bits, 32, "Expected to be loading a halfword");
            assert!(imm_fits_bits(rn.disp.into(), 9), "The displacement must be 9 bits or less.");

            HalfwordImm::ldrh_pre(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operand combination to ldrh instruction.")
    };

    cb.write_bytes(&bytes);
}

/// LDRH (post-index) - load a halfword from memory, update the base pointer after loading it
pub fn ldrh_post(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert_eq!(rt.num_bits, 32, "Expected to be loading a halfword");
            assert!(imm_fits_bits(rn.disp.into(), 9), "The displacement must be 9 bits or less.");

            HalfwordImm::ldrh_post(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operand combination to ldrh instruction.")
    };

    cb.write_bytes(&bytes);
}

/// Whether or not a memory address displacement fits into the maximum number of
/// bits such that it can be used without loading it into a register first.
pub fn mem_disp_fits_bits(disp: i32) -> bool {
    imm_fits_bits(disp.into(), 9)
}

/// LDR (post-index) - load a register from memory, update the base pointer after loading it
pub fn ldr_post(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "All operands must be of the same size.");
            assert!(mem_disp_fits_bits(rn.disp), "The displacement must be 9 bits or less.");

            LoadStore::ldr_post(rt.reg_no, rn.base_reg_no, rn.disp as i16, rt.num_bits).into()
        },
        _ => panic!("Invalid operand combination to ldr instruction."),
    };

    cb.write_bytes(&bytes);
}

/// LDR (pre-index) - load a register from memory, update the base pointer before loading it
pub fn ldr_pre(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "All operands must be of the same size.");
            assert!(mem_disp_fits_bits(rn.disp), "The displacement must be 9 bits or less.");

            LoadStore::ldr_pre(rt.reg_no, rn.base_reg_no, rn.disp as i16, rt.num_bits).into()
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

            LoadStore::ldur(rt.reg_no, rn.reg_no, 0, rt.num_bits).into()
        },
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(mem_disp_fits_bits(rn.disp), "Expected displacement to be 9 bits or less");

            LoadStore::ldur(rt.reg_no, rn.base_reg_no, rn.disp as i16, rt.num_bits).into()
        },
        _ => panic!("Invalid operands for LDUR")
    };

    cb.write_bytes(&bytes);
}

/// LDURH - load a byte from memory, zero-extend it, and write it to a register
pub fn ldurh(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(mem_disp_fits_bits(rn.disp), "Expected displacement to be 9 bits or less");

            LoadStore::ldurh(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operands for LDURH")
    };

    cb.write_bytes(&bytes);
}

/// LDURB - load a byte from memory, zero-extend it, and write it to a register
pub fn ldurb(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(rt.num_bits == 8, "Expected registers to have size 8");
            assert!(mem_disp_fits_bits(rn.disp), "Expected displacement to be 9 bits or less");

            LoadStore::ldurb(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operands for LDURB")
    };

    cb.write_bytes(&bytes);
}

/// LDURSW - load a 32-bit memory address into a register and sign-extend it
pub fn ldursw(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(mem_disp_fits_bits(rn.disp), "Expected displacement to be 9 bits or less");

            LoadStore::ldursw(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operand combination to ldursw instruction.")
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
        (A64Opnd::Reg(A64Reg { reg_no: 31, num_bits: 64 }), A64Opnd::Reg(rm)) => {
            assert!(rm.num_bits == 64, "Expected rm to be 64 bits");

            DataImm::add(31, rm.reg_no, 0.try_into().unwrap(), 64).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(A64Reg { reg_no: 31, num_bits: 64 })) => {
            assert!(rd.num_bits == 64, "Expected rd to be 64 bits");

            DataImm::add(rd.reg_no, 31, 0.try_into().unwrap(), 64).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rm)) => {
            assert!(rd.num_bits == rm.num_bits, "Expected registers to be the same size");

            LogicalReg::mov(rd.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::UImm(0)) => {
            LogicalReg::mov(rd.reg_no, XZR_REG.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::UImm(imm)) => {
            let bitmask_imm = if rd.num_bits == 32 {
                BitmaskImmediate::new_32b_reg(imm.try_into().unwrap())
            } else {
                imm.try_into()
            }.unwrap();

            LogicalImm::mov(rd.reg_no, bitmask_imm, rd.num_bits).into()
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

/// MRS - move a system register into a general-purpose register
pub fn mrs(cb: &mut CodeBlock, rt: A64Opnd, systemregister: SystemRegister) {
    let bytes: [u8; 4] = match rt {
        A64Opnd::Reg(rt) => {
            SysReg::mrs(rt.reg_no, systemregister).into()
        },
        _ => panic!("Invalid operand combination to mrs instruction")
    };

    cb.write_bytes(&bytes);
}

/// MSR - move a general-purpose register into a system register
pub fn msr(cb: &mut CodeBlock, systemregister: SystemRegister, rt: A64Opnd) {
    let bytes: [u8; 4] = match rt {
        A64Opnd::Reg(rt) => {
            SysReg::msr(systemregister, rt.reg_no).into()
        },
        _ => panic!("Invalid operand combination to msr instruction")
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
            let bitmask_imm = if rd.num_bits == 32 {
                BitmaskImmediate::new_32b_reg(imm.try_into().unwrap())
            } else {
                imm.try_into()
            }.unwrap();

            LogicalImm::orr(rd.reg_no, rn.reg_no, bitmask_imm, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to orr instruction."),
    };

    cb.write_bytes(&bytes);
}

/// STLXR - store a value to memory, release exclusive access
pub fn stlxr(cb: &mut CodeBlock, rs: A64Opnd, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rs, rt, rn) {
        (A64Opnd::Reg(rs), A64Opnd::Reg(rt), A64Opnd::Reg(rn)) => {
            assert_eq!(rs.num_bits, 32, "rs must be a 32-bit register.");
            assert_eq!(rn.num_bits, 64, "rn must be a 64-bit register.");

            LoadStoreExclusive::stlxr(rs.reg_no, rt.reg_no, rn.reg_no, rn.num_bits).into()
        },
        _ => panic!("Invalid operand combination to stlxr instruction.")
    };

    cb.write_bytes(&bytes);
}

/// STP (signed offset) - store a pair of registers to memory
pub fn stp(cb: &mut CodeBlock, rt1: A64Opnd, rt2: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt1, rt2, rn) {
        (A64Opnd::Reg(rt1), A64Opnd::Reg(rt2), A64Opnd::Mem(rn)) => {
            assert!(rt1.num_bits == rt2.num_bits, "Expected source registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 10), "The displacement must be 10 bits or less.");
            assert_ne!(rt1.reg_no, rt2.reg_no, "Behavior is unpredictable with pairs of the same register");

            RegisterPair::stp(rt1.reg_no, rt2.reg_no, rn.base_reg_no, rn.disp as i16, rt1.num_bits).into()
        },
        _ => panic!("Invalid operand combination to stp instruction.")
    };

    cb.write_bytes(&bytes);
}

/// STP (pre-index) - store a pair of registers to memory, update the base pointer before loading it
pub fn stp_pre(cb: &mut CodeBlock, rt1: A64Opnd, rt2: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt1, rt2, rn) {
        (A64Opnd::Reg(rt1), A64Opnd::Reg(rt2), A64Opnd::Mem(rn)) => {
            assert!(rt1.num_bits == rt2.num_bits, "Expected source registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 10), "The displacement must be 10 bits or less.");
            assert_ne!(rt1.reg_no, rt2.reg_no, "Behavior is unpredictable with pairs of the same register");

            RegisterPair::stp_pre(rt1.reg_no, rt2.reg_no, rn.base_reg_no, rn.disp as i16, rt1.num_bits).into()
        },
        _ => panic!("Invalid operand combination to stp instruction.")
    };

    cb.write_bytes(&bytes);
}

/// STP (post-index) - store a pair of registers to memory, update the base pointer after loading it
pub fn stp_post(cb: &mut CodeBlock, rt1: A64Opnd, rt2: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt1, rt2, rn) {
        (A64Opnd::Reg(rt1), A64Opnd::Reg(rt2), A64Opnd::Mem(rn)) => {
            assert!(rt1.num_bits == rt2.num_bits, "Expected source registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 10), "The displacement must be 10 bits or less.");
            assert_ne!(rt1.reg_no, rt2.reg_no, "Behavior is unpredictable with pairs of the same register");

            RegisterPair::stp_post(rt1.reg_no, rt2.reg_no, rn.base_reg_no, rn.disp as i16, rt1.num_bits).into()
        },
        _ => panic!("Invalid operand combination to stp instruction.")
    };

    cb.write_bytes(&bytes);
}

/// STR (post-index) - store a register to memory, update the base pointer after loading it
pub fn str_post(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "All operands must be of the same size.");
            assert!(mem_disp_fits_bits(rn.disp), "The displacement must be 9 bits or less.");

            LoadStore::str_post(rt.reg_no, rn.base_reg_no, rn.disp as i16, rt.num_bits).into()
        },
        _ => panic!("Invalid operand combination to str instruction."),
    };

    cb.write_bytes(&bytes);
}

/// STR (pre-index) - store a register to memory, update the base pointer before loading it
pub fn str_pre(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "All operands must be of the same size.");
            assert!(mem_disp_fits_bits(rn.disp), "The displacement must be 9 bits or less.");

            LoadStore::str_pre(rt.reg_no, rn.base_reg_no, rn.disp as i16, rt.num_bits).into()
        },
        _ => panic!("Invalid operand combination to str instruction."),
    };

    cb.write_bytes(&bytes);
}

/// STRH - store a halfword into memory
pub fn strh(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert_eq!(rt.num_bits, 32, "Expected to be loading a halfword");
            assert!(imm_fits_bits(rn.disp.into(), 12), "The displacement must be 12 bits or less.");

            HalfwordImm::strh(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operand combination to strh instruction.")
    };

    cb.write_bytes(&bytes);
}

/// STRH (pre-index) - store a halfword into memory, update the base pointer before loading it
pub fn strh_pre(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert_eq!(rt.num_bits, 32, "Expected to be loading a halfword");
            assert!(imm_fits_bits(rn.disp.into(), 9), "The displacement must be 9 bits or less.");

            HalfwordImm::strh_pre(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operand combination to strh instruction.")
    };

    cb.write_bytes(&bytes);
}

/// STRH (post-index) - store a halfword into memory, update the base pointer after loading it
pub fn strh_post(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert_eq!(rt.num_bits, 32, "Expected to be loading a halfword");
            assert!(imm_fits_bits(rn.disp.into(), 9), "The displacement must be 9 bits or less.");

            HalfwordImm::strh_post(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
        },
        _ => panic!("Invalid operand combination to strh instruction.")
    };

    cb.write_bytes(&bytes);
}

/// STUR - store a value in a register at a memory address
pub fn stur(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rn.num_bits == 32 || rn.num_bits == 64);
            assert!(mem_disp_fits_bits(rn.disp), "Expected displacement to be 9 bits or less");

            LoadStore::stur(rt.reg_no, rn.base_reg_no, rn.disp as i16, rn.num_bits).into()
        },
        _ => panic!("Invalid operand combination to stur instruction.")
    };

    cb.write_bytes(&bytes);
}

/// STURH - store a value in a register at a memory address
pub fn sturh(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rn.num_bits == 16);
            assert!(mem_disp_fits_bits(rn.disp), "Expected displacement to be 9 bits or less");

            LoadStore::sturh(rt.reg_no, rn.base_reg_no, rn.disp as i16).into()
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

            DataImm::sub(rd.reg_no, rn.reg_no, uimm12.try_into().unwrap(), rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Imm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");

            if imm12 < 0 {
                DataImm::add(rd.reg_no, rn.reg_no, (-imm12 as u64).try_into().unwrap(), rd.num_bits).into()
            } else {
                DataImm::sub(rd.reg_no, rn.reg_no, (imm12 as u64).try_into().unwrap(), rd.num_bits).into()
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

            DataImm::subs(rd.reg_no, rn.reg_no, uimm12.try_into().unwrap(), rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Imm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");

            if imm12 < 0 {
                DataImm::adds(rd.reg_no, rn.reg_no, (-imm12 as u64).try_into().unwrap(), rd.num_bits).into()
            } else {
                DataImm::subs(rd.reg_no, rn.reg_no, (imm12 as u64).try_into().unwrap(), rd.num_bits).into()
            }
        },
        _ => panic!("Invalid operand combination to subs instruction."),
    };

    cb.write_bytes(&bytes);
}

/// SXTW - sign extend a 32-bit register into a 64-bit register
pub fn sxtw(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn)) => {
            assert_eq!(rd.num_bits, 64, "rd must be 64-bits wide.");
            assert_eq!(rn.num_bits, 32, "rn must be 32-bits wide.");

            SBFM::sxtw(rd.reg_no, rn.reg_no).into()
        },
        _ => panic!("Invalid operand combination to sxtw instruction."),
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

/// TBNZ - test bit and branch if not zero
pub fn tbnz(cb: &mut CodeBlock, rt: A64Opnd, bit_num: A64Opnd, offset: A64Opnd) {
    let bytes: [u8; 4] = match (rt, bit_num, offset) {
        (A64Opnd::Reg(rt), A64Opnd::UImm(bit_num), A64Opnd::Imm(offset)) => {
            TestBit::tbnz(rt.reg_no, bit_num.try_into().unwrap(), offset.try_into().unwrap()).into()
        },
        _ => panic!("Invalid operand combination to tbnz instruction.")
    };

    cb.write_bytes(&bytes);
}

/// TBZ - test bit and branch if zero
pub fn tbz(cb: &mut CodeBlock, rt: A64Opnd, bit_num: A64Opnd, offset: A64Opnd) {
    let bytes: [u8; 4] = match (rt, bit_num, offset) {
        (A64Opnd::Reg(rt), A64Opnd::UImm(bit_num), A64Opnd::Imm(offset)) => {
            TestBit::tbz(rt.reg_no, bit_num.try_into().unwrap(), offset.try_into().unwrap()).into()
        },
        _ => panic!("Invalid operand combination to tbz instruction.")
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
            let bitmask_imm = if rn.num_bits == 32 {
                BitmaskImmediate::new_32b_reg(imm.try_into().unwrap())
            } else {
                imm.try_into()
            }.unwrap();

            LogicalImm::tst(rn.reg_no, bitmask_imm, rn.num_bits).into()
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

        assert!(imm_fits_bits(i64::MAX, 64));
        assert!(imm_fits_bits(i64::MIN, 64));
    }

    #[test]
    fn test_uimm_fits_bits() {
        assert!(uimm_fits_bits(u8::MAX.into(), 8));
        assert!(uimm_fits_bits(u16::MAX.into(), 16));
        assert!(uimm_fits_bits(u32::MAX.into(), 32));
        assert!(uimm_fits_bits(u64::MAX, 64));
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
    fn test_adr() {
        check_bytes("aa000010", |cb| adr(cb, X10, A64Opnd::new_imm(20)));
    }

    #[test]
    fn test_adrp() {
        check_bytes("4a000090", |cb| adrp(cb, X10, A64Opnd::new_imm(0x8000)));
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
    fn test_and_32b_immedaite() {
        check_bytes("404c0012", |cb| and(cb, W0, W2, A64Opnd::new_uimm(0xfffff)));
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
    fn test_asr() {
        check_bytes("b4fe4a93", |cb| asr(cb, X20, X21, A64Opnd::new_uimm(10)));
    }

    #[test]
    fn test_bcond() {
        let offset = InstructionOffset::from_insns(0x100);
        check_bytes("01200054", |cb| bcond(cb, Condition::NE, offset));
    }

    #[test]
    fn test_b() {
        let offset = InstructionOffset::from_insns((1 << 25) - 1);
        check_bytes("ffffff15", |cb| b(cb, offset));
    }

    #[test]
    #[should_panic]
    fn test_b_too_big() {
        // There are 26 bits available
        let offset = InstructionOffset::from_insns(1 << 25);
        check_bytes("", |cb| b(cb, offset));
    }

    #[test]
    #[should_panic]
    fn test_b_too_small() {
        // There are 26 bits available
        let offset = InstructionOffset::from_insns(-(1 << 25) - 1);
        check_bytes("", |cb| b(cb, offset));
    }

    #[test]
    fn test_bl() {
        let offset = InstructionOffset::from_insns(-(1 << 25));
        check_bytes("00000096", |cb| bl(cb, offset));
    }

    #[test]
    #[should_panic]
    fn test_bl_too_big() {
        // There are 26 bits available
        let offset = InstructionOffset::from_insns(1 << 25);
        check_bytes("", |cb| bl(cb, offset));
    }

    #[test]
    #[should_panic]
    fn test_bl_too_small() {
        // There are 26 bits available
        let offset = InstructionOffset::from_insns(-(1 << 25) - 1);
        check_bytes("", |cb| bl(cb, offset));
    }

    #[test]
    fn test_blr() {
        check_bytes("80023fd6", |cb| blr(cb, X20));
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
    fn test_csel() {
        check_bytes("6a018c9a", |cb| csel(cb, X10, X11, X12, Condition::EQ));
    }

    #[test]
    fn test_eor_register() {
        check_bytes("6a010cca", |cb| eor(cb, X10, X11, X12));
    }

    #[test]
    fn test_eor_immediate() {
        check_bytes("6a0940d2", |cb| eor(cb, X10, X11, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_eor_32b_immediate() {
        check_bytes("29040152", |cb| eor(cb, W9, W1, A64Opnd::new_uimm(0x80000001)));
    }

    #[test]
    fn test_ldaddal() {
        check_bytes("8b01eaf8", |cb| ldaddal(cb, X10, X11, X12));
    }

    #[test]
    fn test_ldaxr() {
        check_bytes("6afd5fc8", |cb| ldaxr(cb, X10, X11));
    }

    #[test]
    fn test_ldp() {
        check_bytes("8a2d4da9", |cb| ldp(cb, X10, X11, A64Opnd::new_mem(64, X12, 208)));
    }

    #[test]
    fn test_ldp_pre() {
        check_bytes("8a2dcda9", |cb| ldp_pre(cb, X10, X11, A64Opnd::new_mem(64, X12, 208)));
    }

    #[test]
    fn test_ldp_post() {
        check_bytes("8a2dcda8", |cb| ldp_post(cb, X10, X11, A64Opnd::new_mem(64, X12, 208)));
    }

    #[test]
    fn test_ldr() {
        check_bytes("6a696cf8", |cb| ldr(cb, X10, X11, X12));
    }

    #[test]
    fn test_ldr_literal() {
        check_bytes("40010058", |cb| ldr_literal(cb, X0, 10.into()));
    }

    #[test]
    fn test_ldr_post() {
        check_bytes("6a0541f8", |cb| ldr_post(cb, X10, A64Opnd::new_mem(64, X11, 16)));
    }

    #[test]
    fn test_ldr_pre() {
        check_bytes("6a0d41f8", |cb| ldr_pre(cb, X10, A64Opnd::new_mem(64, X11, 16)));
    }

    #[test]
    fn test_ldrh() {
        check_bytes("6a194079", |cb| ldrh(cb, W10, A64Opnd::new_mem(64, X11, 12)));
    }

    #[test]
    fn test_ldrh_pre() {
        check_bytes("6acd4078", |cb| ldrh_pre(cb, W10, A64Opnd::new_mem(64, X11, 12)));
    }

    #[test]
    fn test_ldrh_post() {
        check_bytes("6ac54078", |cb| ldrh_post(cb, W10, A64Opnd::new_mem(64, X11, 12)));
    }

    #[test]
    fn test_ldurh_memory() {
        check_bytes("2a004078", |cb| ldurh(cb, W10, A64Opnd::new_mem(64, X1, 0)));
        check_bytes("2ab04778", |cb| ldurh(cb, W10, A64Opnd::new_mem(64, X1, 123)));
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
    fn test_ldursw() {
        check_bytes("6ab187b8", |cb| ldursw(cb, X10, A64Opnd::new_mem(64, X11, 123)));
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
    fn test_mov_32b_immediate() {
        check_bytes("ea070132", |cb| mov(cb, W10, A64Opnd::new_uimm(0x80000001)));
    }
    #[test]
    fn test_mov_into_sp() {
        check_bytes("1f000091", |cb| mov(cb, X31, X0));
    }

    #[test]
    fn test_mov_from_sp() {
        check_bytes("e0030091", |cb| mov(cb, X0, X31));
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
    fn test_mrs() {
        check_bytes("0a423bd5", |cb| mrs(cb, X10, SystemRegister::NZCV));
    }

    #[test]
    fn test_msr() {
        check_bytes("0a421bd5", |cb| msr(cb, SystemRegister::NZCV, X10));
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
    fn test_orr_32b_immediate() {
        check_bytes("6a010032", |cb| orr(cb, W10, W11, A64Opnd::new_uimm(1)));
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
    fn test_stlxr() {
        check_bytes("8bfd0ac8", |cb| stlxr(cb, W10, X11, X12));
    }

    #[test]
    fn test_stp() {
        check_bytes("8a2d0da9", |cb| stp(cb, X10, X11, A64Opnd::new_mem(64, X12, 208)));
    }

    #[test]
    fn test_stp_pre() {
        check_bytes("8a2d8da9", |cb| stp_pre(cb, X10, X11, A64Opnd::new_mem(64, X12, 208)));
    }

    #[test]
    fn test_stp_post() {
        check_bytes("8a2d8da8", |cb| stp_post(cb, X10, X11, A64Opnd::new_mem(64, X12, 208)));
    }

    #[test]
    fn test_str_post() {
        check_bytes("6a051ff8", |cb| str_post(cb, X10, A64Opnd::new_mem(64, X11, -16)));
    }

    #[test]
    fn test_str_pre() {
        check_bytes("6a0d1ff8", |cb| str_pre(cb, X10, A64Opnd::new_mem(64, X11, -16)));
    }

    #[test]
    fn test_strh() {
        check_bytes("6a190079", |cb| strh(cb, W10, A64Opnd::new_mem(64, X11, 12)));
    }

    #[test]
    fn test_strh_pre() {
        check_bytes("6acd0078", |cb| strh_pre(cb, W10, A64Opnd::new_mem(64, X11, 12)));
    }

    #[test]
    fn test_strh_post() {
        check_bytes("6ac50078", |cb| strh_post(cb, W10, A64Opnd::new_mem(64, X11, 12)));
    }

    #[test]
    fn test_stur_64_bits() {
        check_bytes("6a0108f8", |cb| stur(cb, X10, A64Opnd::new_mem(64, X11, 128)));
    }

    #[test]
    fn test_stur_32_bits() {
        check_bytes("6a0108b8", |cb| stur(cb, X10, A64Opnd::new_mem(32, X11, 128)));
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
    fn test_sxtw() {
        check_bytes("6a7d4093", |cb| sxtw(cb, X10, W11));
    }

    #[test]
    fn test_tbnz() {
        check_bytes("4a005037", |cb| tbnz(cb, X10, A64Opnd::UImm(10), A64Opnd::Imm(2)));
    }

    #[test]
    fn test_tbz() {
        check_bytes("4a005036", |cb| tbz(cb, X10, A64Opnd::UImm(10), A64Opnd::Imm(2)));
    }

    #[test]
    fn test_tst_register() {
        check_bytes("1f0001ea", |cb| tst(cb, X0, X1));
    }

    #[test]
    fn test_tst_immediate() {
        check_bytes("3f0840f2", |cb| tst(cb, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_tst_32b_immediate() {
        check_bytes("1f3c0072", |cb| tst(cb, W0, A64Opnd::new_uimm(0xffff)));
    }
}
