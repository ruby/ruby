use super::super::arg::Sf;

/// The units within the register whose bytes get reversed.
enum Opc {
    /// The register as a whole.
    Reg,

    /// Each 16-bit halfword.
    Halfword
}

/// The struct that represents an A64 byte reversal instruction that can be
/// encoded.
///
/// REV
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |     1  0  1    1  0  1  0    1  1  0  0    0  0  0  0                                                         |
/// | sf                                                      opc................ rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Rev {
    /// The register number of the destination register.
    rd: u8,

    /// The register number of the source register.
    rn: u8,

    /// The units whose bytes get reversed.
    opc: Opc,

    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf
}

impl Rev {
    /// REV
    /// <https://developer.arm.com/documentation/ddi0602/2021-12/Base-Instructions/REV--Reverse-Bytes->
    pub fn rev(rd: u8, rn: u8, num_bits: u8) -> Self {
        Rev { rd, rn, opc: Opc::Reg, sf: num_bits.into() }
    }

    /// REV16
    /// <https://developer.arm.com/documentation/ddi0602/2021-12/Base-Instructions/REV16--Reverse-bytes-in-16-bit-halfwords->
    pub fn rev16(rd: u8, rn: u8, num_bits: u8) -> Self {
        Rev { rd, rn, opc: Opc::Halfword, sf: num_bits.into() }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Register#dp_1src>
const FAMILY: u32 = 0b11010110;

impl From<Rev> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Rev) -> Self {
        // Reversing the whole register has its own opc per width, since the
        // 64-bit encoding has to be told apart from REV32.
        let opc = match (&inst.opc, &inst.sf) {
            (Opc::Halfword, _) => 0b000001,
            (Opc::Reg, Sf::Sf32) => 0b000010,
            (Opc::Reg, Sf::Sf64) => 0b000011
        };

        0
        | ((inst.sf as u32) << 31)
        | (1 << 30)
        | (FAMILY << 21)
        | (opc << 10)
        | ((inst.rn as u32) << 5)
        | inst.rd as u32
    }
}

impl From<Rev> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Rev) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rev_32() {
        let inst = Rev::rev(0, 1, 32);
        let result: u32 = inst.into();
        assert_eq!(0x5ac00820, result);
    }

    #[test]
    fn test_rev_64() {
        let inst = Rev::rev(0, 1, 64);
        let result: u32 = inst.into();
        assert_eq!(0xdac00c20, result);
    }

    #[test]
    fn test_rev16_32() {
        let inst = Rev::rev16(0, 1, 32);
        let result: u32 = inst.into();
        assert_eq!(0x5ac00420, result);
    }

    #[test]
    fn test_rev16_64() {
        let inst = Rev::rev16(0, 1, 64);
        let result: u32 = inst.into();
        assert_eq!(0xdac00420, result);
    }
}
