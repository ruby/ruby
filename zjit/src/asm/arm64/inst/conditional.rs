use super::super::arg::Sf;

/// The struct that represents an A64 conditional instruction that can be
/// encoded.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |     0  0  1    1  0  1  0    1  0  0                                   0  0                                   |
/// | sf                                   rm..............   cond.......         rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Conditional {
    /// The number of the general-purpose destination register.
    rd: u8,

    /// The number of the first general-purpose source register.
    rn: u8,

    /// The condition to use for the conditional instruction.
    cond: u8,

    /// The number of the second general-purpose source register.
    rm: u8,

    /// The size of the registers of this instruction.
    sf: Sf
}

impl Conditional {
    /// CSEL
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/CSEL--Conditional-Select-?lang=en>
    pub fn csel(rd: u8, rn: u8, rm: u8, cond: u8, num_bits: u8) -> Self {
        Self { rd, rn, cond, rm, sf: num_bits.into() }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Register?lang=en#condsel>
const FAMILY: u32 = 0b101;

impl From<Conditional> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Conditional) -> Self {
        ((inst.sf as u32) << 31)
        | (1 << 28)
        | (FAMILY << 25)
        | (1 << 23)
        | ((inst.rm as u32) << 16)
        | ((inst.cond as u32) << 12)
        | ((inst.rn as u32) << 5)
        | (inst.rd as u32)
    }
}

impl From<Conditional> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Conditional) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

/*
#[cfg(test)]
mod tests {
    use super::*;
    use super::super::super::arg::Condition;

    #[test]
    fn test_csel() {
        let result: u32 = Conditional::csel(0, 1, 2, Condition::NE, 64).into();
        assert_eq!(0x9a821020, result);
    }
}
*/
