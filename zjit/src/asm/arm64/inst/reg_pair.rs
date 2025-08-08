use super::super::arg::truncate_imm;

/// The operation to perform for this instruction.
enum Opc {
    /// When the registers are 32-bits wide.
    Opc32 = 0b00,

    /// When the registers are 64-bits wide.
    Opc64 = 0b10
}

/// The kind of indexing to perform for this instruction.
enum Index {
    StorePostIndex = 0b010,
    LoadPostIndex = 0b011,
    StoreSignedOffset = 0b100,
    LoadSignedOffset = 0b101,
    StorePreIndex = 0b110,
    LoadPreIndex = 0b111
}

/// A convenience function so that we can convert the number of bits of a
/// register operand directly into an Opc variant.
impl From<u8> for Opc {
    fn from(num_bits: u8) -> Self {
        match num_bits {
            64 => Opc::Opc64,
            32 => Opc::Opc32,
            _ => panic!("Invalid number of bits: {}", num_bits)
        }
    }
}

/// The struct that represents an A64 register pair instruction that can be
/// encoded.
///
/// STP/LDP
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |     0  1  0    1  0  0                                                                                        |
/// | opc                    index..... imm7.................... rt2............. rn.............. rt1............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct RegisterPair {
    /// The number of the first register to be transferred.
    rt1: u8,

    /// The number of the base register.
    rn: u8,

    /// The number of the second register to be transferred.
    rt2: u8,

    /// The signed immediate byte offset, a multiple of 8.
    imm7: i16,

    /// The kind of indexing to use for this instruction.
    index: Index,

    /// The operation to be performed (in terms of size).
    opc: Opc
}

impl RegisterPair {
    /// Create a register pair instruction with a given indexing mode.
    fn new(rt1: u8, rt2: u8, rn: u8, disp: i16, index: Index, num_bits: u8) -> Self {
        Self { rt1, rn, rt2, imm7: disp / 8, index, opc: num_bits.into() }
    }

    /// LDP (signed offset)
    /// `LDP <Xt1>, <Xt2>, [<Xn|SP>{, #<imm>}]`
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDP--Load-Pair-of-Registers-?lang=en>
    pub fn ldp(rt1: u8, rt2: u8, rn: u8, disp: i16, num_bits: u8) -> Self {
        Self::new(rt1, rt2, rn, disp, Index::LoadSignedOffset, num_bits)
    }

    /// LDP (pre-index)
    /// `LDP <Xt1>, <Xt2>, [<Xn|SP>, #<imm>]!`
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDP--Load-Pair-of-Registers-?lang=en>
    pub fn ldp_pre(rt1: u8, rt2: u8, rn: u8, disp: i16, num_bits: u8) -> Self {
        Self::new(rt1, rt2, rn, disp, Index::LoadPreIndex, num_bits)
    }

    /// LDP (post-index)
    /// `LDP <Xt1>, <Xt2>, [<Xn|SP>], #<imm>`
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDP--Load-Pair-of-Registers-?lang=en>
    pub fn ldp_post(rt1: u8, rt2: u8, rn: u8, disp: i16, num_bits: u8) -> Self {
        Self::new(rt1, rt2, rn, disp, Index::LoadPostIndex, num_bits)
    }

    /// STP (signed offset)
    /// `STP <Xt1>, <Xt2>, [<Xn|SP>{, #<imm>}]`
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/STP--Store-Pair-of-Registers-?lang=en>
    pub fn stp(rt1: u8, rt2: u8, rn: u8, disp: i16, num_bits: u8) -> Self {
        Self::new(rt1, rt2, rn, disp, Index::StoreSignedOffset, num_bits)
    }

    /// STP (pre-index)
    /// `STP <Xt1>, <Xt2>, [<Xn|SP>, #<imm>]!`
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/STP--Store-Pair-of-Registers-?lang=en>
    pub fn stp_pre(rt1: u8, rt2: u8, rn: u8, disp: i16, num_bits: u8) -> Self {
        Self::new(rt1, rt2, rn, disp, Index::StorePreIndex, num_bits)
    }

    /// STP (post-index)
    /// `STP <Xt1>, <Xt2>, [<Xn|SP>], #<imm>`
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/STP--Store-Pair-of-Registers-?lang=en>
    pub fn stp_post(rt1: u8, rt2: u8, rn: u8, disp: i16, num_bits: u8) -> Self {
        Self::new(rt1, rt2, rn, disp, Index::StorePostIndex, num_bits)
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en>
const FAMILY: u32 = 0b0100;

impl From<RegisterPair> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: RegisterPair) -> Self {
        0
        | ((inst.opc as u32) << 30)
        | (1 << 29)
        | (FAMILY << 25)
        | ((inst.index as u32) << 22)
        | (truncate_imm::<_, 7>(inst.imm7) << 15)
        | ((inst.rt2 as u32) << 10)
        | ((inst.rn as u32) << 5)
        | (inst.rt1 as u32)
    }
}

impl From<RegisterPair> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: RegisterPair) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ldp() {
        let inst = RegisterPair::ldp(0, 1, 2, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa9400440, result);
    }

    #[test]
    fn test_ldp_maximum_displacement() {
        let inst = RegisterPair::ldp(0, 1, 2, 504, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa95f8440, result);
    }

    #[test]
    fn test_ldp_minimum_displacement() {
        let inst = RegisterPair::ldp(0, 1, 2, -512, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa9600440, result);
    }

    #[test]
    fn test_ldp_pre() {
        let inst = RegisterPair::ldp_pre(0, 1, 2, 256, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa9d00440, result);
    }

    #[test]
    fn test_ldp_post() {
        let inst = RegisterPair::ldp_post(0, 1, 2, 256, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa8d00440, result);
    }

    #[test]
    fn test_stp() {
        let inst = RegisterPair::stp(0, 1, 2, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa9000440, result);
    }

    #[test]
    fn test_stp_maximum_displacement() {
        let inst = RegisterPair::stp(0, 1, 2, 504, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa91f8440, result);
    }

    #[test]
    fn test_stp_minimum_displacement() {
        let inst = RegisterPair::stp(0, 1, 2, -512, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa9200440, result);
    }

    #[test]
    fn test_stp_pre() {
        let inst = RegisterPair::stp_pre(0, 1, 2, 256, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa9900440, result);
    }

    #[test]
    fn test_stp_post() {
        let inst = RegisterPair::stp_post(0, 1, 2, 256, 64);
        let result: u32 = inst.into();
        assert_eq!(0xa8900440, result);
    }
}
