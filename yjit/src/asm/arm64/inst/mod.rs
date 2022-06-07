mod branches_and_system;
mod data_processing_immediate;
mod data_processing_register;
mod family;
mod loads_and_stores;
mod sf;

use data_processing_immediate::DataProcessingImmediate;
use data_processing_register::DataProcessingRegister;

use crate::asm::CodeBlock;
use super::opnd::*;

/// ADD
pub fn add(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match rm {
        A64Opnd::UImm(_) => DataProcessingImmediate::add(rd, rn, rm).into(),
        A64Opnd::Reg(_) => DataProcessingRegister::add(rd, rn, rm).into(),
        _ => panic!("Invalid operand combination to add.")
    };

    cb.write_bytes(&bytes);
}

/// SUB
pub fn sub(cb: &mut CodeBlock, rd: A64Opnd, rn: A64Opnd, rm: A64Opnd) {
    let bytes: [u8; 4] = match rm {
        A64Opnd::UImm(_) => DataProcessingImmediate::sub(rd, rn, rm).into(),
        A64Opnd::Reg(_) => DataProcessingRegister::sub(rd, rn, rm).into(),
        _ => panic!("Invalid operand combination to add.")
    };

    cb.write_bytes(&bytes);
}
