#![allow(dead_code)] // For instructions we're not currently using.

use crate::asm::CodeBlock;

mod inst;
mod opnd;

use inst::DataProcessingRegister;
use opnd::*;

/// ADD (shifted register)
/// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADD--shifted-register---Add--shifted-register--?lang=en
pub fn add(cb: &mut CodeBlock, rd_opnd: &Arm64Opnd, rn_opnd: &Arm64Opnd, rm_opnd: &Arm64Opnd) {
    let (rd, rn, rm) = regs((rd_opnd, rn_opnd, rm_opnd));
    let bytes: [u8; 4] = DataProcessingRegister::add(rd, rn, rm).into();
    cb.write_bytes(&bytes);
}

/// SUB (shifted register)
/// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUB--shifted-register---Subtract--shifted-register--?lang=en
pub fn sub(cb: &mut CodeBlock, rd_opnd: &Arm64Opnd, rn_opnd: &Arm64Opnd, rm_opnd: &Arm64Opnd) {
    let (rd, rn, rm) = regs((rd_opnd, rn_opnd, rm_opnd));
    let bytes: [u8; 4] = DataProcessingRegister::sub(rd, rn, rm).into();
    cb.write_bytes(&bytes);
}

/// Extract out three registers from the given operands. Panic if any of the
/// operands are not registers or if they are not the same size.
fn regs<'a>((rd_opnd, rn_opnd, rm_opnd): (&'a Arm64Opnd, &'a Arm64Opnd, &'a Arm64Opnd)) -> (&'a Arm64Reg, &'a Arm64Reg, &'a Arm64Reg) {
    match (rd_opnd, rn_opnd, rm_opnd) {
        (Arm64Opnd::Reg(rd), Arm64Opnd::Reg(rn), Arm64Opnd::Reg(rm)) => {
            assert!(
                rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits,
                "All operands to a data processing register instruction must be of the same size."
            );

            (rd, rn, rm)
        },
        _ => {
            panic!("Expected 3 register operands for a data processing register instruction.");
        }
    }
}
