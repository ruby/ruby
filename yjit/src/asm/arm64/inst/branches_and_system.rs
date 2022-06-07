use super::family::Family;

/// The struct that represents an A64 branches and system instruction that can
/// be encoded.
///
/// RET
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  1  1  0  1    0  1  1  0    0  1  0  1    1  1  1  1    0  0  0  0    0  0                   0    0  0  0  0 |
/// |                                                                             rn.............. rm.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct BranchesAndSystem {
    /// The register holding the address to be branched to.
    rn: u8
}

impl BranchesAndSystem {
    /// RET
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/RET--Return-from-subroutine-?lang=en
    pub fn ret(rn: u8) -> Self {
        Self { rn }
    }
}

impl From<BranchesAndSystem> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: BranchesAndSystem) -> Self {
        0
        | (0b11 << 30)
        | ((Family::BranchesAndSystem as u32) << 25)
        | (0b1001011111 << 16)
        | ((inst.rn as u32) << 5)
    }
}

impl From<BranchesAndSystem> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: BranchesAndSystem) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ret() {
        let inst = BranchesAndSystem::ret(30);
        let result: u32 = inst.into();
        assert_eq!(0xd65f03C0, result);
    }

    #[test]
    fn test_ret_rn() {
        let inst = BranchesAndSystem::ret(20);
        let result: u32 = inst.into();
        assert_eq!(0xd65f0280, result);
    }
}
