/// Immediates used by the logical immediate instructions are not actually the
/// immediate value, but instead are encoded into a 13-bit wide mask of 3
/// elements. This allows many more values to be represented than 13 bits would
/// normally allow, at the expense of not being able to represent every possible
/// value.
///
/// In order for a number to be encodeable in this form, the binary
/// representation must consist of a single set of contiguous 1s. That pattern
/// must then be replicatable across all of the bits either 1, 2, 4, 8, 16, or
/// 32 times (rotated or not).
///
/// For example, 1 (0b1), 2 (0b10), 3 (0b11), and 4 (0b100) are all valid.
/// However, 5 (0b101) is invalid, because it contains 2 sets of 1s and cannot
/// be replicated across 64 bits.
///
/// Some more examples to illustrate the idea of replication:
/// * 0x5555555555555555 is a valid value (0b0101...) because it consists of a
///   single set of 1s which can be replicated across all of the bits 32 times.
/// * 0xf0f0f0f0f0f0f0f0 is a valid value (0b1111000011110000...) because it
///   consists of a single set of 1s which can be replicated across all of the
///   bits 8 times (rotated by 4 bits).
/// * 0x0ff00ff00ff00ff0 is a valid value (0000111111110000...) because it
///   consists of a single set of 1s which can be replicated across all of the
///   bits 4 times (rotated by 12 bits).
///
/// To encode the values, there are 3 elements:
/// * n = 1 if the pattern is 64-bits wide, 0 otherwise
/// * imms = the size of the pattern, a 0, and then one less than the number of
///   sequential 1s
/// * immr = the number of right rotations to apply to the pattern to get the
///   target value
///
pub struct BitmaskImmediate {
    n: u8,
    imms: u8,
    immr: u8
}

impl TryFrom<u64> for BitmaskImmediate {
    type Error = ();

    /// Attempt to convert a u64 into a BitmaskImmediate.
    ///
    /// The implementation here is largely based on this blog post:
    /// <https://dougallj.wordpress.com/2021/10/30/bit-twiddling-optimising-aarch64-logical-immediate-encoding-and-decoding/>
    fn try_from(value: u64) -> Result<Self, Self::Error> {
        if value == 0 || value == u64::MAX {
            return Err(());
        }

        fn rotate_right(value: u64, rotations: u32) -> u64 {
            (value >> (rotations & 0x3F)) |
            (value << (rotations.wrapping_neg() & 0x3F))
        }

        let rotations = (value & (value + 1)).trailing_zeros();
        let normalized = rotate_right(value, rotations & 0x3F);

        let zeroes = normalized.leading_zeros();
        let ones = (!normalized).trailing_zeros();
        let size = zeroes + ones;

        if rotate_right(value, size & 0x3F) != value {
            return Err(());
        }

        Ok(BitmaskImmediate {
            n: ((size >> 6) & 1) as u8,
            imms: (((size << 1).wrapping_neg() | (ones - 1)) & 0x3F) as u8,
            immr: ((rotations.wrapping_neg() & (size - 1)) & 0x3F) as u8
        })
    }
}

impl BitmaskImmediate {
    /// Attempt to make a BitmaskImmediate for a 32 bit register.
    /// The result has N==0, which is required for some 32-bit instructions.
    /// Note that the exact same BitmaskImmediate produces different values
    /// depending on the size of the target register.
    pub fn new_32b_reg(value: u32) -> Result<Self, ()> {
        // The same bit pattern replicated to u64
        let value = value as u64;
        let replicated: u64 = (value << 32) | value;
        let converted = Self::try_from(replicated);
        if let Ok(ref imm) = converted {
            assert_eq!(0, imm.n);
        }

        converted
    }
}

impl BitmaskImmediate {
    /// Encode a bitmask immediate into a 32-bit value.
    pub fn encode(self) -> u32 {
        0
        | ((self.n as u32) << 12)
        | ((self.immr as u32) << 6)
        | (self.imms as u32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_failures() {
        [5, 9, 10, 11, 13, 17, 18, 19].iter().for_each(|&imm| {
            assert!(BitmaskImmediate::try_from(imm).is_err());
        });
    }

    #[test]
    fn test_negative() {
        let bitmask: BitmaskImmediate = (-9_i64 as u64).try_into().unwrap();
        let encoded: u32 = bitmask.encode();
        assert_eq!(7998, encoded);
    }

    #[test]
    fn test_size_2_minimum() {
        let bitmask = BitmaskImmediate::try_from(0x5555555555555555);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000000, imms: 0b111100 })));
    }

    #[test]
    fn test_size_2_maximum() {
        let bitmask = BitmaskImmediate::try_from(0xaaaaaaaaaaaaaaaa);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000001, imms: 0b111100 })));
    }

    #[test]
    fn test_size_4_minimum() {
        let bitmask = BitmaskImmediate::try_from(0x1111111111111111);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000000, imms: 0b111000 })));
    }

    #[test]
    fn test_size_4_rotated() {
        let bitmask = BitmaskImmediate::try_from(0x6666666666666666);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000011, imms: 0b111001 })));
    }

    #[test]
    fn test_size_4_maximum() {
        let bitmask = BitmaskImmediate::try_from(0xeeeeeeeeeeeeeeee);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000011, imms: 0b111010 })));
    }

    #[test]
    fn test_size_8_minimum() {
        let bitmask = BitmaskImmediate::try_from(0x0101010101010101);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000000, imms: 0b110000 })));
    }

    #[test]
    fn test_size_8_rotated() {
        let bitmask = BitmaskImmediate::try_from(0x1818181818181818);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000101, imms: 0b110001 })));
    }

    #[test]
    fn test_size_8_maximum() {
        let bitmask = BitmaskImmediate::try_from(0xfefefefefefefefe);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000111, imms: 0b110110 })));
    }

    #[test]
    fn test_size_16_minimum() {
        let bitmask = BitmaskImmediate::try_from(0x0001000100010001);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000000, imms: 0b100000 })));
    }

    #[test]
    fn test_size_16_rotated() {
        let bitmask = BitmaskImmediate::try_from(0xff8fff8fff8fff8f);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b001001, imms: 0b101100 })));
    }

    #[test]
    fn test_size_16_maximum() {
        let bitmask = BitmaskImmediate::try_from(0xfffefffefffefffe);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b001111, imms: 0b101110 })));
    }

    #[test]
    fn test_size_32_minimum() {
        let bitmask = BitmaskImmediate::try_from(0x0000000100000001);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b000000, imms: 0b000000 })));
    }

    #[test]
    fn test_size_32_rotated() {
        let bitmask = BitmaskImmediate::try_from(0x3fffff003fffff00);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b011000, imms: 0b010101 })));
    }

    #[test]
    fn test_size_32_maximum() {
        let bitmask = BitmaskImmediate::try_from(0xfffffffefffffffe);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 0, immr: 0b011111, imms: 0b011110 })));
    }

    #[test]
    fn test_size_64_minimum() {
        let bitmask = BitmaskImmediate::try_from(0x0000000000000001);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 1, immr: 0b000000, imms: 0b000000 })));
    }

    #[test]
    fn test_size_64_rotated() {
        let bitmask = BitmaskImmediate::try_from(0x0000001fffff0000);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 1, immr: 0b110000, imms: 0b010100 })));
    }

    #[test]
    fn test_size_64_maximum() {
        let bitmask = BitmaskImmediate::try_from(0xfffffffffffffffe);
        assert!(matches!(bitmask, Ok(BitmaskImmediate { n: 1, immr: 0b111111, imms: 0b111110 })));
    }

    #[test]
    fn test_size_64_invalid() {
        let bitmask = BitmaskImmediate::try_from(u64::MAX);
        assert!(matches!(bitmask, Err(())));
    }

    #[test]
    fn test_all_valid_32b_pattern() {
        let mut patterns = vec![];
        for pattern_size in [2, 4, 8, 16, 32_u64] {
            for ones_count in 1..pattern_size {
                for rotation in 0..pattern_size {
                    let ones = (1_u64 << ones_count) - 1;
                    let rotated = (ones >> rotation) |
                        ((ones & ((1 << rotation) - 1)) << (pattern_size - rotation));
                    let mut replicated = rotated;
                    let mut shift = pattern_size;
                    while shift < 32 {
                        replicated |= replicated << shift;
                        shift *= 2;
                    }
                    let replicated: u32 = replicated.try_into().unwrap();
                    assert!(BitmaskImmediate::new_32b_reg(replicated).is_ok());
                    patterns.push(replicated);
                }
            }
        }
        patterns.sort();
        patterns.dedup();
        // Up to {size}-1 ones, and a total of {size} possible rotations.
        assert_eq!(1*2 + 3*4 + 7*8 + 15*16 + 31*32, patterns.len());
    }
}
