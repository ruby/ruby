use super::condition::Condition;

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
    cond: Condition,

    /// The offset from the branch of this instruction to branch to.
    imm19: i32
}

impl BranchCond {
    /// B.cond
    /// https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/B-cond--Branch-conditionally-
    pub fn bcond(cond: Condition, offset: i32) -> Self {
        Self { cond, imm19: offset >> 2 }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en
const FAMILY: u32 = 0b101;

impl From<BranchCond> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: BranchCond) -> Self {
        let imm19 = (inst.imm19 as u32) & ((1 << 19) - 1);

        0
        | (1 << 30)
        | (FAMILY << 26)
        | (imm19 << 5)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_b_eq() {
        let result: u32 = BranchCond::bcond(Condition::EQ, 128).into();
        assert_eq!(0x54000400, result);
    }

    #[test]
    fn test_b_vs() {
        let result: u32 = BranchCond::bcond(Condition::VS, 128).into();
        assert_eq!(0x54000406, result);
    }

    #[test]
    fn test_b_ne_neg() {
        let result: u32 = BranchCond::bcond(Condition::NE, -128).into();
        assert_eq!(0x54fffc01, result);
    }
}
