mod branches_and_system;
mod data_processing_immediate;
mod data_processing_register;
mod family;
mod loads_and_stores;
mod sf;

use branches_and_system::BranchesAndSystem;
use data_processing_immediate::DataProcessingImmediate;
use data_processing_register::DataProcessingRegister;
use loads_and_stores::LoadsAndStores;

use crate::asm::{CodeBlock, imm_num_bits};
use super::opnd::*;

/// ADD
pub fn add(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataProcessingRegister::add(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(imm12.num_bits <= 12, "The immediate operand must be 12 bits or less.");

            DataProcessingImmediate::add(rd.reg_no, rn.reg_no, imm12.value as u16, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to add instruction."),
    };

    cb.write_bytes(&bytes);
}

/// ADDS
pub fn adds(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataProcessingRegister::adds(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(imm12.num_bits <= 12, "The immediate operand must be 12 bits or less.");

            DataProcessingImmediate::adds(rd.reg_no, rn.reg_no, imm12.value as u16, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to adds instruction."),
    };

    cb.write_bytes(&bytes);
}

/// LDUR
pub fn ldur(cb: &mut CodeBlock, rt: A64Opnd, rn: A64Opnd) {
    let bytes: [u8; 4] = match (rt, rn) {
        (A64Opnd::Reg(rt), A64Opnd::Mem(rn)) => {
            assert!(rt.num_bits == rn.num_bits, "Expected registers to be the same size");
            assert!(imm_num_bits(rn.disp.into()) <= 9, "Expected displacement to be 9 bits or less");

            LoadsAndStores::ldur(rt.reg_no, rn.base_reg_no, rn.disp.try_into().unwrap(), rt.num_bits).into()
        },
        _ => panic!("Invalid operands for LDUR")
    };

    cb.write_bytes(&bytes);
}

/// SUB
pub fn sub(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataProcessingRegister::sub(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(imm12.num_bits <= 12, "The immediate operand must be 12 bits or less.");

            DataProcessingImmediate::sub(rd.reg_no, rn.reg_no, imm12.value as u16, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to sub instruction."),
    };

    cb.write_bytes(&bytes);
}

/// SUBS
pub fn subs(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match (rd, rn, rm) {
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands must be of the same size."
            );

            DataProcessingRegister::subs(rd.reg_no, rn.reg_no, rm.reg_no, rd.num_bits).into()
        },
        (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
            assert!(rd.num_bits == rn.num_bits, "rd and rn must be of the same size.");
            assert!(imm12.num_bits <= 12, "The immediate operand must be 12 bits or less.");

            DataProcessingImmediate::subs(rd.reg_no, rn.reg_no, imm12.value as u16, rd.num_bits).into()
        },
        _ => panic!("Invalid operand combination to subs instruction."),
    };

    cb.write_bytes(&bytes);
}

/// RET
pub fn ret(cb: &mut CodeBlock, rn: A64Opnd) {
    let bytes: [u8; 4] = match rn {
        A64Opnd::None => BranchesAndSystem::ret(30).into(),
        A64Opnd::Reg(reg) => BranchesAndSystem::ret(reg.reg_no).into(),
        _ => panic!("Invalid operand for RET")
    };

    cb.write_bytes(&bytes);
}
