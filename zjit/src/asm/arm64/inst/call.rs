use super::super::arg::{InstructionOffset, truncate_imm};

/// The operation to perform for this instruction.
enum Op {
    /// Branch directly, with a hint that this is not a subroutine call or
    /// return.
    Branch = 0,

    /// Branch directly, with a hint that this is a subroutine call or return.
    BranchWithLink = 1
}

/// The struct that represents an A64 branch with our without link instruction
/// that can be encoded.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |     0  0  1    0  1                                                                                           |
/// | op                  imm26.................................................................................... |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Call {
    /// The PC-relative offset to jump to in terms of number of instructions.
    offset: InstructionOffset,

    /// The operation to perform for this instruction.
    op: Op
}

impl Call {
    /// B
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/B--Branch->
    pub fn b(offset: InstructionOffset) -> Self {
        Self { offset, op: Op::Branch }
    }

    /// BL
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/BL--Branch-with-Link-?lang=en>
    pub fn bl(offset: InstructionOffset) -> Self {
        Self { offset, op: Op::BranchWithLink }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en>
const FAMILY: u32 = 0b101;

impl From<Call> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Call) -> Self {
        ((inst.op as u32) << 31)
        | (FAMILY << 26)
        | truncate_imm::<_, 26>(inst.offset)
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
        let result: u32 = Call::bl(0.into()).into();
        assert_eq!(0x94000000, result);
    }

    #[test]
    fn test_bl_positive() {
        let result: u32 = Call::bl(256.into()).into();
        assert_eq!(0x94000100, result);
    }

    #[test]
    fn test_bl_negative() {
        let result: u32 = Call::bl((-256).into()).into();
        assert_eq!(0x97ffff00, result);
    }

    #[test]
    fn test_b() {
        let result: u32 = Call::b(0.into()).into();
        assert_eq!(0x14000000, result);
    }

    #[test]
    fn test_b_positive() {
        let result: u32 = Call::b(((1 << 25) - 1).into()).into();
        assert_eq!(0x15ffffff, result);
    }

    #[test]
    fn test_b_negative() {
        let result: u32 = Call::b((-(1 << 25)).into()).into();
        assert_eq!(0x16000000, result);
    }
}
