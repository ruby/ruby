#![cfg(test)]

use crate::asm::aarch64::*;
use std::fmt;

/// Produce hex string output from the bytes in a code block
impl<'a> fmt::LowerHex for super::CodeBlock {
    fn fmt(&self, fmtr: &mut fmt::Formatter) -> fmt::Result {
        for pos in 0..self.write_pos {
            let byte = unsafe { self.mem_block.add(pos).read() };
            fmtr.write_fmt(format_args!("{:02x}", byte))?;
        }
        Ok(())
    }
}

/// Check that the bytes for an instruction sequence match a hex string
fn check_bytes<R>(bytes: &str, run: R) where R: FnOnce(&mut super::CodeBlock) {
    let mut cb = super::CodeBlock::new_dummy(4096);
    run(&mut cb);
    assert_eq!(format!("{:x}", cb), bytes);
}

#[test]
fn test_add() {
    check_bytes("73220091", |cb| add(cb, X19, X19, imm_opnd(8)));
}

#[test]
fn test_ldp() {
    check_bytes("fd7b41a9", |cb| ldp(cb, X29, X30, mem_opnd(     64, SP,  16)));
    check_bytes("fd7bc1a9", |cb| ldp(cb, X29, X30, mem_pre_opnd( 64, SP,  16)));
    check_bytes("fd7bc1a8", |cb| ldp(cb, X29, X30, mem_post_opnd(64, SP,  16)));
    check_bytes("fd7b7fa9", |cb| ldp(cb, X29, X30, mem_opnd(     64, SP, -16)));
}

#[test]
fn test_ldr() {
    check_bytes("200440f9", |cb| ldr(cb, X0, mem_opnd(64, X1, 8)));
}

#[test]
fn test_mov() {
    check_bytes("e00301aa", |cb| mov(cb, X0, X1));
}

#[test]
fn test_mov_u64() {
    check_bytes("e0bd99d26035b1f2e0acc8f26024e0f2", |cb| mov_u64(cb, X0, 0x123456789abcdef));
}

#[test]
fn test_movk() {
    check_bytes("6035b1f2", |cb| movk(cb, X0, imm_shift_opnd(0x89ab, ShiftType::LSL, 16)));
}

#[test]
fn test_movz() {
    check_bytes("e0bd99d2", |cb| movz(cb, X0, imm_opnd(0xcdef)));
}


#[test]
fn test_ret() {
    check_bytes("c0035fd6", |cb| ret(cb, X30));
}

#[test]
fn test_stp() {
    check_bytes("fd7b3fa9", |cb| stp(cb, X29, X30, mem_opnd(     64, SP, -16)));
    check_bytes("fd7bbfa9", |cb| stp(cb, X29, X30, mem_pre_opnd( 64, SP, -16)));
    check_bytes("fd7bbfa8", |cb| stp(cb, X29, X30, mem_post_opnd(64, SP, -16)));
    check_bytes("fd7b01a9", |cb| stp(cb, X29, X30, mem_opnd(     64, SP,  16)));
}

#[test]
fn test_str() {
    check_bytes("200400f9", |cb| str(cb, X0, mem_opnd(64, X1, 8)));
}
