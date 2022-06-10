mod branch;
mod data_imm;
mod data_reg;
mod load;
mod mov;
mod sf;

use branch::Branch;
use data_imm::DataImm;
use data_reg::DataReg;
use load::Load;
use mov::Mov;

use crate::asm::{CodeBlock, imm_num_bits};
use super::opnd::*;

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
            assert!(imm12.num_bits <= 12, "The immediate operand must be 12 bits or less.");

            DataImm::add(rd.reg_no, rn.reg_no, imm12.value as u16, rd.num_bits).into()
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
            assert!(imm12.num_bits <= 12, "The immediate operand must be 12 bits or less.");

            DataImm::adds(rd.reg_no, rn.reg_no, imm12.value as u16, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to adds instruction."),
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

/// LDUR - load a memory address into a register
pub fn ldur(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(imm_num_bits(rn.disp.into()) <= 9, "Expected displacement to be 9 bits or less");

            Load::ldur(rt.reg_no, rn.base_reg_no, rn.disp.try_into().unwrap(), rt.num_bits).into()
        },
        _ => panic!("Invalid operands for LDUR")
    };

    cb.write_bytes(&bytes);
}

/// MOVK - move a 16 bit immediate into a register, keep the other bits in place
pub fn movk(cb: &mut CodeBlock, rd: A64Opnd, imm16: A64Opnd, shift: u8) {
    let bytes: [u8; 4] = match (rd, imm16) {
        (A64Opnd::Reg(rd), A64Opnd::UImm(imm16)) => {
            assert!(imm16.num_bits <= 16, "The immediate operand must be 16 bits or less.");

            Mov::movk(rd.reg_no, imm16.value as u16, shift, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to movk instruction.")
    };

    cb.write_bytes(&bytes);
}

/// MOVZ - move a 16 bit immediate into a register, zero the other bits
pub fn movz(cb: &mut CodeBlock, rd: A64Opnd, imm16: A64Opnd, shift: u8) {
    let bytes: [u8; 4] = match (rd, imm16) {
        (A64Opnd::Reg(rd), A64Opnd::UImm(imm16)) => {
            assert!(imm16.num_bits <= 16, "The immediate operand must be 16 bits or less.");

            Mov::movz(rd.reg_no, imm16.value as u16, shift, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to movz instruction.")
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
            assert!(imm12.num_bits <= 12, "The immediate operand must be 12 bits or less.");

            DataImm::sub(rd.reg_no, rn.reg_no, imm12.value as u16, rd.num_bits).into()
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
            assert!(imm12.num_bits <= 12, "The immediate operand must be 12 bits or less.");

            DataImm::subs(rd.reg_no, rn.reg_no, imm12.value as u16, rd.num_bits).into()
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
    fn test_br() {
        check_bytes("80021fd6", |cb| br(cb, X20));
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
}
