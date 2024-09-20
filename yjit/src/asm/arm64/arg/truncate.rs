// There are many instances in AArch64 instruction encoding where you represent
// an integer value with a particular bit width that isn't a power of 2. These
// functions represent truncating those integer values down to the appropriate
// number of bits.

/// Truncate a signed immediate to fit into a compile-time known width. It is
/// assumed before calling this function that the value fits into the correct
/// size. If it doesn't, then this function will panic.
///
/// When the value is positive, this should effectively be a no-op since we're
/// just dropping leading zeroes. When the value is negative we should only be
/// dropping leading ones.
pub fn truncate_imm<T: Into<i32>, const WIDTH: usize>(imm: T) -> u32 {
    let value: i32 = imm.into();
    let masked = (value as u32) & ((1 << WIDTH) - 1);

    // Assert that we didn't drop any bits by truncating.
    if value >= 0 {
        assert_eq!(value as u32, masked);
    } else {
        assert_eq!(value as u32, masked | (u32::MAX << WIDTH));
    }

    masked
}

/// Truncate an unsigned immediate to fit into a compile-time known width. It is
/// assumed before calling this function that the value fits into the correct
/// size. If it doesn't, then this function will panic.
///
/// This should effectively be a no-op since we're just dropping leading zeroes.
pub fn truncate_uimm<T: Into<u32>, const WIDTH: usize>(uimm: T) -> u32 {
    let value: u32 = uimm.into();
    let masked = value & ((1 << WIDTH) - 1);

    // Assert that we didn't drop any bits by truncating.
    assert_eq!(value, masked);

    masked
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_truncate_imm_positive() {
        let inst = truncate_imm::<i32, 4>(5);
        let result: u32 = inst;
        assert_eq!(0b0101, result);
    }

    #[test]
    fn test_truncate_imm_negative() {
        let inst = truncate_imm::<i32, 4>(-5);
        let result: u32 = inst;
        assert_eq!(0b1011, result);
    }

    #[test]
    fn test_truncate_uimm() {
        let inst = truncate_uimm::<u32, 4>(5);
        let result: u32 = inst;
        assert_eq!(0b0101, result);
    }
}
