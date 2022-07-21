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

    /// Attempt to convert a u64 into a BitmaskImm.
    fn try_from(value: u64) -> Result<Self, Self::Error> {
        // 0 is not encodable as a bitmask immediate. Immediately return here so
        // that we don't have any issues with underflow.
        if value == 0 {
            return Err(());
        }

        /// Is this number's binary representation all 1s?
        fn is_mask(imm: u64) -> bool {
            if imm == u64::MAX { true } else { ((imm + 1) & imm) == 0 }
        }

        /// Is this number's binary representation one or more 1s followed by
        /// one or more 0s?
        fn is_shifted_mask(imm: u64) -> bool {
            is_mask((imm - 1) | imm)
        }

        let mut imm = value;
        let mut size = 64;

        // First, determine the element size.
        loop {
            size >>= 1;
            let mask = (1 << size) - 1;

            if (imm & mask) != ((imm >> size) & mask) {
              size <<= 1;
              break;
            }

            if size <= 2 {
                break;
            }
        }

        // Second, determine the rotation to make the pattern be aligned such
        // that all of the least significant bits are 1.
        let trailing_ones: u32;
        let left_rotations: u32;

        let mask = u64::MAX >> (64 - size);
        imm &= mask;

        if is_shifted_mask(imm) {
            left_rotations = imm.trailing_zeros();
            assert!(left_rotations < 64);
            trailing_ones = (imm >> left_rotations).trailing_ones();
        } else {
            imm |= !mask;
            if !is_shifted_mask(!imm) {
                return Err(());
            }

            let leading_ones = imm.leading_ones();
            left_rotations = 64 - leading_ones;
            trailing_ones = leading_ones + imm.trailing_ones() - (64 - size);
        }

        // immr is the number of right rotations it takes to get from the
        // matching unrotated pattern to the target value.
        let immr = (size - left_rotations) & (size - 1);
        assert!(size > left_rotations);

        // imms is encoded as the size of the pattern, a 0, and then one less
        // than the number of sequential 1s. The table below shows how this is
        // encoded. (Note that the way it works out, it's impossible for every x
        // in a row to be 1 at the same time).
        // +-------------+--------------+--------------+
        // | imms        | element size | number of 1s |
        // +-------------+--------------+--------------+
        // | 1 1 1 1 0 x | 2 bits       | 1            |
        // | 1 1 1 0 x x | 4 bits       | 1-3          |
        // | 1 1 0 x x x | 8 bits       | 1-7          |
        // | 1 0 x x x x | 16 bits      | 1-15         |
        // | 0 x x x x x | 32 bits      | 1-31         |
        // | x x x x x x | 64 bits      | 1-63         |
        // +-------------+--------------+--------------+
        let imms = (!(size - 1) << 1) | (trailing_ones - 1);

        // n is 1 if the element size is 64-bits, and 0 otherwise.
        let n = ((imms >> 6) & 1) ^ 1;

        Ok(BitmaskImmediate {
            n: n as u8,
            imms: (imms & 0x3f) as u8,
            immr: (immr & 0x3f) as u8
        })
    }
}

impl From<BitmaskImmediate> for u32 {
    /// Encode a bitmask immediate into a 32-bit value.
    fn from(bitmask: BitmaskImmediate) -> Self {
        0
        | (((bitmask.n as u32) & 1) << 12)
        | ((bitmask.immr as u32) << 6)
        | bitmask.imms as u32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_failures() {
        vec![5, 9, 10, 11, 13, 17, 18, 19].iter().for_each(|&imm| {
            assert!(BitmaskImmediate::try_from(imm).is_err());
        });
    }

    #[test]
    fn test_negative() {
        let bitmask: BitmaskImmediate = (-9_i64 as u64).try_into().unwrap();
        let encoded: u32 = bitmask.into();
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
}
