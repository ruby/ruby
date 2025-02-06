//use std::fmt;

use crate::codegen::CodeBlock;

/*
use crate::core::IseqPayload;
use crate::core::for_each_off_stack_iseq_payload;
use crate::core::for_each_on_stack_iseq_payload;
use crate::invariants::rb_yjit_tracing_invalidate_all;
use crate::stats::incr_counter;
use crate::virtualmem::WriteError;
use crate::codegen::CodegenGlobals;
use crate::virtualmem::{VirtualMem, CodePtr};
*/




/// Pointer inside the ZJIT code region
#[derive(Eq, PartialEq)]
pub struct CodePtr(u32);









// Lots of manual vertical alignment in there that rustfmt doesn't handle well.
#[rustfmt::skip]
pub mod x86_64;
pub mod arm64;







/// Reference to an ASM label
#[derive(Clone)]
pub struct LabelRef {
    // Position in the code block where the label reference exists
    pos: usize,

    // Label which this refers to
    label_idx: usize,

    /// The number of bytes that this label reference takes up in the memory.
    /// It's necessary to know this ahead of time so that when we come back to
    /// patch it it takes the same amount of space.
    num_bytes: usize,

    /// The object that knows how to encode the branch instruction.
    encode: fn(&mut CodeBlock, i64, i64)
}

/// Compute the number of bits needed to encode a signed value
pub fn imm_num_bits(imm: i64) -> u8
{
    // Compute the smallest size this immediate fits in
    if imm >= i8::MIN.into() && imm <= i8::MAX.into() {
        return 8;
    }
    if imm >= i16::MIN.into() && imm <= i16::MAX.into() {
        return 16;
    }
    if imm >= i32::MIN.into() && imm <= i32::MAX.into() {
        return 32;
    }

    return 64;
}

/// Compute the number of bits needed to encode an unsigned value
pub fn uimm_num_bits(uimm: u64) -> u8
{
    // Compute the smallest size this immediate fits in
    if uimm <= u8::MAX.into() {
        return 8;
    }
    else if uimm <= u16::MAX.into() {
        return 16;
    }
    else if uimm <= u32::MAX.into() {
        return 32;
    }

    return 64;
}




/*
#[cfg(test)]
mod tests
{
    use super::*;

    #[test]
    fn test_imm_num_bits()
    {
        assert_eq!(imm_num_bits(i8::MIN.into()), 8);
        assert_eq!(imm_num_bits(i8::MAX.into()), 8);

        assert_eq!(imm_num_bits(i16::MIN.into()), 16);
        assert_eq!(imm_num_bits(i16::MAX.into()), 16);

        assert_eq!(imm_num_bits(i32::MIN.into()), 32);
        assert_eq!(imm_num_bits(i32::MAX.into()), 32);

        assert_eq!(imm_num_bits(i64::MIN), 64);
        assert_eq!(imm_num_bits(i64::MAX), 64);
    }

    #[test]
    fn test_uimm_num_bits() {
        assert_eq!(uimm_num_bits(u8::MIN.into()), 8);
        assert_eq!(uimm_num_bits(u8::MAX.into()), 8);

        assert_eq!(uimm_num_bits(((u8::MAX as u16) + 1).into()), 16);
        assert_eq!(uimm_num_bits(u16::MAX.into()), 16);

        assert_eq!(uimm_num_bits(((u16::MAX as u32) + 1).into()), 32);
        assert_eq!(uimm_num_bits(u32::MAX.into()), 32);

        assert_eq!(uimm_num_bits((u32::MAX as u64) + 1), 64);
        assert_eq!(uimm_num_bits(u64::MAX), 64);
    }

    #[test]
    fn test_code_size() {
        // Write 4 bytes in the first page
        let mut cb = CodeBlock::new_dummy(CodeBlock::PREFERRED_CODE_PAGE_SIZE * 2);
        cb.write_bytes(&[0, 0, 0, 0]);
        assert_eq!(cb.code_size(), 4);

        // Moving to the next page should not increase code_size
        cb.next_page(cb.get_write_ptr(), |_, _| {});
        assert_eq!(cb.code_size(), 4);

        // Write 4 bytes in the second page
        cb.write_bytes(&[0, 0, 0, 0]);
        assert_eq!(cb.code_size(), 8);

        // Rewrite 4 bytes in the first page
        let old_write_pos = cb.get_write_pos();
        cb.set_pos(0);
        cb.write_bytes(&[1, 1, 1, 1]);

        // Moving from an old page to the next page should not increase code_size
        cb.next_page(cb.get_write_ptr(), |_, _| {});
        cb.set_pos(old_write_pos);
        assert_eq!(cb.code_size(), 8);
    }
}

*/
