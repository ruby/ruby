/// Which operation to perform.
enum Op {
    /// Perform a BR instruction.
    BR = 0b00,

    /// Perform a BLR instruction.
    BLR = 0b01,

    /// Perform a RET instruction.
    RET = 0b10
}

/// The struct that represents an A64 branch instruction that can be encoded.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  1  1  0  1    0  1  1  0    0        1    1  1  1  1    0  0  0  0    0  0                   0    0  0  0  0 |
/// |                                op...                                        rn.............. rm.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Branch {
    /// The register holding the address to be branched to.
    rn: u8,

    /// The operation to perform.
    op: Op
}

impl Branch {
    /// BR
    /// <https://developer.arm.com/documentation/ddi0602/2022-03/Base-Instructions/BR--Branch-to-Register-?lang=en>
    pub fn br(rn: u8) -> Self {
        Self { rn, op: Op::BR }
    }

    /// BLR
    /// <https://developer.arm.com/documentation/ddi0602/2022-03/Base-Instructions/BLR--Branch-with-Link-to-Register-?lang=en>
    pub fn blr(rn: u8) -> Self {
        Self { rn, op: Op::BLR }
    }

    /// RET
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/RET--Return-from-subroutine-?lang=en>
    pub fn ret(rn: u8) -> Self {
        Self { rn, op: Op::RET }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en>
const FAMILY: u32 = 0b101;

impl From<Branch> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Branch) -> Self {
        0
        | (0b11 << 30)
        | (FAMILY << 26)
        | (1 << 25)
        | ((inst.op as u32) << 21)
        | (0b11111 << 16)
        | ((inst.rn as u32) << 5)
    }
}

impl From<Branch> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Branch) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_br() {
        let result: u32 = Branch::br(0).into();
        assert_eq!(0xd61f0000, result);
    }

    #[test]
    fn test_blr() {
        let result: u32 = Branch::blr(0).into();
        assert_eq!(0xd63f0000, result);
    }

    #[test]
    fn test_ret() {
        let result: u32 = Branch::ret(30).into();
        assert_eq!(0xd65f03C0, result);
    }

    #[test]
    fn test_ret_rn() {
        let result: u32 = Branch::ret(20).into();
        assert_eq!(0xd65f0280, result);
    }
}
