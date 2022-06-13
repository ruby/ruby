/// The struct that represents an A64 branch with link instruction that can be
/// encoded.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  1  0  0  1    0  1                                                                                           |
/// |                     imm26.................................................................................... |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Call {
    /// The PC-relative offset to jump to (which will be multiplied by 4).
    imm26: i32
}

impl Call {
    /// BL
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/BL--Branch-with-Link-?lang=en
    pub fn bl(imm26: i32) -> Self {
        Self { imm26 }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en
const FAMILY: u32 = 0b101;

impl From<Call> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Call) -> Self {
        let imm26 = (inst.imm26 as u32) & ((1 << 26) - 1);

        0
        | (1 << 31)
        | (FAMILY << 26)
        | imm26
    }
}

impl From<Call> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Call) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bl() {
        let result: u32 = Call::bl(0).into();
        assert_eq!(0x94000000, result);
    }

    #[test]
    fn test_bl_positive() {
        let result: u32 = Call::bl(256).into();
        assert_eq!(0x94000100, result);
    }

    #[test]
    fn test_bl_negative() {
        let result: u32 = Call::bl(-256).into();
        assert_eq!(0x97ffff00, result);
    }
}
