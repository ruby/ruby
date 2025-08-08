use super::super::arg::{InstructionOffset, truncate_imm};

/// The struct that represents an A64 conditional branch instruction that can be
/// encoded.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  0  1  0  1    0  1  0  0                                                                     0               |
/// |                             imm19...........................................................      cond....... |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct BranchCond {
    /// The kind of condition to check before branching.
    cond: u8,

    /// The instruction offset from this instruction to branch to.
    offset: InstructionOffset
}

impl BranchCond {
    /// B.cond
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/B-cond--Branch-conditionally->
    pub fn bcond(cond: u8, offset: InstructionOffset) -> Self {
        Self { cond, offset }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en>
const FAMILY: u32 = 0b101;

impl From<BranchCond> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: BranchCond) -> Self {
        (1 << 30)
        | (FAMILY << 26)
        | (truncate_imm::<_, 19>(inst.offset) << 5)
        | (inst.cond as u32)
    }
}

impl From<BranchCond> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: BranchCond) -> [u8; 4] {
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
    fn test_b_eq() {
        let result: u32 = BranchCond::bcond(Condition::EQ, 32.into()).into();
        assert_eq!(0x54000400, result);
    }

    #[test]
    fn test_b_vs() {
        let result: u32 = BranchCond::bcond(Condition::VS, 32.into()).into();
        assert_eq!(0x54000406, result);
    }

    #[test]
    fn test_b_eq_max() {
        let result: u32 = BranchCond::bcond(Condition::EQ, ((1 << 18) - 1).into()).into();
        assert_eq!(0x547fffe0, result);
    }

    #[test]
    fn test_b_eq_min() {
        let result: u32 = BranchCond::bcond(Condition::EQ, (-(1 << 18)).into()).into();
        assert_eq!(0x54800000, result);
    }
}
*/
