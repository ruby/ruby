/// The struct that represents an A64 signed multiply high instruction
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  1  0  0  1    1  0  1  1    0  1  0                     0                                                    |
/// |                                      rm..............      ra.............. rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct SMulH {
    /// The number of the general-purpose destination register.
    rd: u8,

    /// The number of the first general-purpose source register.
    rn: u8,

    /// The number of the third general-purpose source register.
    ra: u8,

    /// The number of the second general-purpose source register.
    rm: u8,
}

impl SMulH {
    /// SMULH
    /// <https://developer.arm.com/documentation/ddi0602/2023-06/Base-Instructions/SMULH--Signed-Multiply-High->
    pub fn smulh(rd: u8, rn: u8, rm: u8) -> Self {
        Self { rd, rn, ra: 0b11111, rm }
    }
}

impl From<SMulH> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: SMulH) -> Self {
        (0b10011011010 << 21)
        | ((inst.rm as u32) << 16)
        | ((inst.ra as u32) << 10)
        | ((inst.rn as u32) << 5)
        | (inst.rd as u32)
    }
}

impl From<SMulH> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: SMulH) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_smulh() {
        let result: u32 = SMulH::smulh(0, 1, 2).into();
        assert_eq!(0x9b427c20, result);
    }
}
