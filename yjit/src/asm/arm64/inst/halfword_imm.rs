use super::super::arg::truncate_imm;

/// Whether this is a load or a store.
enum Op {
    Load = 1,
    Store = 0
}

/// The type of indexing to perform for this instruction.
enum Index {
    /// No indexing.
    None = 0b00,

    /// Mutate the register after the read.
    PostIndex = 0b01,

    /// Mutate the register before the read.
    PreIndex = 0b11
}

/// The struct that represents an A64 halfword instruction that can be encoded.
///
/// LDRH/STRH
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  0  1  1  1    1  0  0  1    0                                                                                |
/// |                                op imm12.................................... rn.............. rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
/// LDRH (pre-index/post-index)
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  0  1  1  1    1  0  0  0    0     0                                                                          |
/// |                                op    imm9..........................   index rn.............. rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct HalfwordImm {
    /// The number of the 32-bit register to be loaded.
    rt: u8,

    /// The number of the 64-bit base register to calculate the memory address.
    rn: u8,

    /// The type of indexing to perform for this instruction.
    index: Index,

    /// The immediate offset from the base register.
    imm: i16,

    /// The operation to perform.
    op: Op
}

impl HalfwordImm {
    /// LDRH
    /// https://developer.arm.com/documentation/ddi0602/2022-06/Base-Instructions/LDRH--immediate---Load-Register-Halfword--immediate--
    pub fn ldrh(rt: u8, rn: u8, imm12: i16) -> Self {
        Self { rt, rn, index: Index::None, imm: imm12, op: Op::Load }
    }

    /// LDRH (pre-index)
    /// https://developer.arm.com/documentation/ddi0602/2022-06/Base-Instructions/LDRH--immediate---Load-Register-Halfword--immediate--
    pub fn ldrh_pre(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, index: Index::PreIndex, imm: imm9, op: Op::Load }
    }

    /// LDRH (post-index)
    /// https://developer.arm.com/documentation/ddi0602/2022-06/Base-Instructions/LDRH--immediate---Load-Register-Halfword--immediate--
    pub fn ldrh_post(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, index: Index::PostIndex, imm: imm9, op: Op::Load }
    }

    /// STRH
    /// https://developer.arm.com/documentation/ddi0602/2022-06/Base-Instructions/STRH--immediate---Store-Register-Halfword--immediate--
    pub fn strh(rt: u8, rn: u8, imm12: i16) -> Self {
        Self { rt, rn, index: Index::None, imm: imm12, op: Op::Store }
    }

    /// STRH (pre-index)
    /// https://developer.arm.com/documentation/ddi0602/2022-06/Base-Instructions/STRH--immediate---Store-Register-Halfword--immediate--
    pub fn strh_pre(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, index: Index::PreIndex, imm: imm9, op: Op::Store }
    }

    /// STRH (post-index)
    /// https://developer.arm.com/documentation/ddi0602/2022-06/Base-Instructions/STRH--immediate---Store-Register-Halfword--immediate--
    pub fn strh_post(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, index: Index::PostIndex, imm: imm9, op: Op::Store }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en
const FAMILY: u32 = 0b111100;

impl From<HalfwordImm> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: HalfwordImm) -> Self {
        let (opc, imm) = match inst.index {
            Index::None => {
                assert_eq!(inst.imm & 1, 0, "immediate offset must be even");
                let imm12 = truncate_imm::<_, 12>(inst.imm / 2);
                (0b100, imm12)
            },
            Index::PreIndex | Index::PostIndex => {
                let imm9 = truncate_imm::<_, 9>(inst.imm);
                (0b000, (imm9 << 2) | (inst.index as u32))
            }
        };

        0
        | (FAMILY << 25)
        | ((opc | (inst.op as u32)) << 22)
        | (imm << 10)
        | ((inst.rn as u32) << 5)
        | (inst.rt as u32)
    }
}

impl From<HalfwordImm> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: HalfwordImm) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ldrh() {
        let inst = HalfwordImm::ldrh(0, 1, 8);
        let result: u32 = inst.into();
        assert_eq!(0x79401020, result);
    }

    #[test]
    fn test_ldrh_pre() {
        let inst = HalfwordImm::ldrh_pre(0, 1, 16);
        let result: u32 = inst.into();
        assert_eq!(0x78410c20, result);
    }

    #[test]
    fn test_ldrh_post() {
        let inst = HalfwordImm::ldrh_post(0, 1, 24);
        let result: u32 = inst.into();
        assert_eq!(0x78418420, result);
    }

    #[test]
    fn test_ldrh_post_negative() {
        let inst = HalfwordImm::ldrh_post(0, 1, -24);
        let result: u32 = inst.into();
        assert_eq!(0x785e8420, result);
    }

    #[test]
    fn test_strh() {
        let inst = HalfwordImm::strh(0, 1, 0);
        let result: u32 = inst.into();
        assert_eq!(0x79000020, result);
    }

    #[test]
    fn test_strh_pre() {
        let inst = HalfwordImm::strh_pre(0, 1, 0);
        let result: u32 = inst.into();
        assert_eq!(0x78000c20, result);
    }

    #[test]
    fn test_strh_post() {
        let inst = HalfwordImm::strh_post(0, 1, 0);
        let result: u32 = inst.into();
        assert_eq!(0x78000420, result);
    }
}
