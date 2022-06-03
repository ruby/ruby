mod data_processing_immediate;
mod data_processing_register;
mod family;
mod sf;

use data_processing_immediate::DataProcessingImmediate;
use data_processing_register::DataProcessingRegister;

use crate::asm::CodeBlock;
use super::opnd::*;

/// ADD
pub fn add(cb: &mut CodeBlock, rd: &Arm64Opnd, rn: &Arm64Opnd, rm: &Arm64Opnd) {
    let bytes: [u8; 4] = match rm {
        Arm64Opnd::UImm(_) => DataProcessingImmediate::add(rd, rn, rm).into(),
        Arm64Opnd::Reg(_) => DataProcessingRegister::add(rd, rn, rm).into(),
        _ => panic!("Invalid operand combination to add.")
    };

    cb.write_bytes(&bytes);
}

/// SUB
pub fn sub(cb: &mut CodeBlock, rd: &Arm64Opnd, rn: &Arm64Opnd, rm: &Arm64Opnd) {
    let bytes: [u8; 4] = match rm {
        Arm64Opnd::UImm(_) => DataProcessingImmediate::sub(rd, rn, rm).into(),
        Arm64Opnd::Reg(_) => DataProcessingRegister::sub(rd, rn, rm).into(),
        _ => panic!("Invalid operand combination to add.")
    };

    cb.write_bytes(&bytes);
}
