use super::super::arg::Sf;

/// The struct that represents an A64 multiply-add instruction that can be
/// encoded.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |     0  0  1    1  0  1  1    0  0  0                     0                                                    |
/// | sf                                   rm..............      ra.............. rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct MAdd {
    /// The number of the general-purpose destination register.
    rd: u8,

    /// The number of the first general-purpose source register.
    rn: u8,

    /// The number of the third general-purpose source register.
    ra: u8,

    /// The number of the second general-purpose source register.
    rm: u8,

    /// The size of the registers of this instruction.
    sf: Sf
}

impl MAdd {
    /// MUL
    /// <https://developer.arm.com/documentation/ddi0602/2023-06/Base-Instructions/MUL--Multiply--an-alias-of-MADD->
    pub fn mul(rd: u8, rn: u8, rm: u8, num_bits: u8) -> Self {
        Self { rd, rn, ra: 0b11111, rm, sf: num_bits.into() }
    }
}

impl From<MAdd> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: MAdd) -> Self {
        0
        | ((inst.sf as u32) << 31)
        | (0b11011 << 24)
        | ((inst.rm as u32) << 16)
        | ((inst.ra as u32) << 10)
        | ((inst.rn as u32) << 5)
        | (inst.rd as u32)
    }
}

impl From<MAdd> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: MAdd) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mul_32() {
        let result: u32 = MAdd::mul(0, 1, 2, 32).into();
        assert_eq!(0x1B027C20, result);
    }

    #[test]
    fn test_mul_64() {
        let result: u32 = MAdd::mul(0, 1, 2, 64).into();
        assert_eq!(0x9B027C20, result);
    }
}
