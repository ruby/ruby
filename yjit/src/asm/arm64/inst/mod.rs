mod atomic;
mod bitmask_imm;
mod branch;
mod call;
mod data_imm;
mod data_reg;
mod load;
mod logical_imm;
mod logical_reg;
mod mov;
mod sf;
mod store;

use core::num;

use atomic::Atomic;
use branch::Branch;
use call::Call;
use data_imm::DataImm;
use data_reg::DataReg;
use load::Load;
use logical_imm::LogicalImm;
use logical_reg::LogicalReg;
use mov::Mov;
use store::Store;

use crate::asm::CodeBlock;
use super::opnd::*;

/// Checks that a signed value fits within the specified number of bits.
const fn imm_fits_bits(imm: i64, num_bits: u8) -> bool {
    let minimum = if num_bits == 64 { i64::MIN } else { -2_i64.pow((num_bits as u32) - 1) };
    let maximum = if num_bits == 64 { i64::MAX } else { 2_i64.pow((num_bits as u32) - 1) - 1 };

    imm >= minimum && imm <= maximum
}

/// Checks that an unsigned value fits within the specified number of bits.
const fn uimm_fits_bits(uimm: u64, num_bits: u8) -> bool {
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
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(uimm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            DataImm::add(rd.reg_no, rn.reg_no, imm12 as u16, rd.num_bits).into()
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

/// BL - branch with link (offset is number of instructions to jump)
pub fn bl(cb: &mut CodeBlock, imm26: A64Opnd) {
    let bytes: [u8; 4] = match imm26 {
        A64Opnd::Imm(imm26) => {
            assert!(imm_fits_bits(imm26, 26), "The immediate operand must be 26 bits or less.");

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

/// LDUR - load a memory address into a register
pub fn ldur(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(imm_fits_bits(rn.disp.into(), 9), "Expected displacement to be 9 bits or less");

            Load::ldur(rt.reg_no, rn.base_reg_no, rn.disp as i16, rt.num_bits).into()
        },
        _ => panic!("Invalid operands for LDUR")
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
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(uimm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            DataImm::sub(rd.reg_no, rn.reg_no, imm12 as u16, rd.num_bits).into()
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
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(uimm_fits_bits(imm12, 12), "The immediate operand must be 12 bits or less.");

            DataImm::subs(rd.reg_no, rn.reg_no, imm12 as u16, rd.num_bits).into()
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
    fn test_add_register() {
        check_bytes("2000028b", |cb| add(cb, X0, X1, X2));
    }

    #[test]
    fn test_add_immediate() {
        check_bytes("201c0091", |cb| add(cb, X0, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_adds_register() {
        check_bytes("200002ab", |cb| adds(cb, X0, X1, X2));
    }

    #[test]
    fn test_adds_immediate() {
        check_bytes("201c00b1", |cb| adds(cb, X0, X1, A64Opnd::new_uimm(7)));
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
    fn test_bl() {
        check_bytes("00040094", |cb| bl(cb, A64Opnd::new_imm(1024)));
    }

    #[test]
    fn test_br() {
        check_bytes("80021fd6", |cb| br(cb, X20));
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
    fn test_ldur() {
        check_bytes("20b047f8", |cb| ldur(cb, X0, A64Opnd::new_mem(X1, 123)));
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
    fn test_ret_none() {
        check_bytes("c0035fd6", |cb| ret(cb, A64Opnd::None));
    }

    #[test]
    fn test_ret_register() {
        check_bytes("80025fd6", |cb| ret(cb, X20));
    }

    #[test]
    fn test_stur() {
        check_bytes("6a0108f8", |cb| stur(cb, X10, A64Opnd::new_mem(X11, 128)));
    }

    #[test]
    fn test_sub_register() {
        check_bytes("200002cb", |cb| sub(cb, X0, X1, X2));
    }

    #[test]
    fn test_sub_immediate() {
        check_bytes("201c00d1", |cb| sub(cb, X0, X1, A64Opnd::new_uimm(7)));
    }

    #[test]
    fn test_subs_register() {
        check_bytes("200002eb", |cb| subs(cb, X0, X1, X2));
    }

    #[test]
    fn test_subs_immediate() {
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
