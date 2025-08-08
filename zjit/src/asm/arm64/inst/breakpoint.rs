/// The struct that represents an A64 breakpoint instruction that can be encoded.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  1  1  0  1    0  1  0  0    0  0  1                                                          0    0  0  0  0 |
/// |                                      imm16..................................................                  |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Breakpoint {
    /// The value to be captured by ESR_ELx.ISS
    imm16: u16
}

impl Breakpoint {
    /// BRK
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/BRK--Breakpoint-instruction->
    pub fn brk(imm16: u16) -> Self {
        Self { imm16 }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en#control>
const FAMILY: u32 = 0b101;

impl From<Breakpoint> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Breakpoint) -> Self {
        let imm16 = inst.imm16 as u32;

        (0b11 << 30)
        | (FAMILY << 26)
        | (1 << 21)
        | (imm16 << 5)
    }
}

impl From<Breakpoint> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Breakpoint) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_brk() {
        let result: u32 = Breakpoint::brk(7).into();
        assert_eq!(0xd42000e0, result);
    }
}
