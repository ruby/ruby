use super::super::arg::Sf;

/// Which operation is being performed.
enum Op {
    /// A movz operation which zeroes out the other bits.
    MOVZ = 0b10,

    /// A movk operation which keeps the other bits in place.
    MOVK = 0b11
}

/// How much to shift the immediate by.
enum Hw {
    LSL0 = 0b00,
    LSL16 = 0b01,
    LSL32 = 0b10,
    LSL48 = 0b11
}

impl From<u8> for Hw {
    fn from(shift: u8) -> Self {
        match shift {
            0 => Hw::LSL0,
            16 => Hw::LSL16,
            32 => Hw::LSL32,
            48 => Hw::LSL48,
            _ => panic!("Invalid value for shift: {}", shift)
        }
    }
}

/// The struct that represents a MOVK or MOVZ instruction.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |           1    0  0  1  0    1                                                                                |
/// | sf op...                       hw... imm16.................................................. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Mov {
    /// The register number of the destination register.
    rd: u8,

    /// The value to move into the register.
    imm16: u16,

    /// The shift of the value to move.
    hw: Hw,

    /// Which operation is being performed.
    op: Op,

    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf
}

impl Mov {
    /// MOVK
    /// <https://developer.arm.com/documentation/ddi0602/2022-03/Base-Instructions/MOVK--Move-wide-with-keep-?lang=en>
    pub fn movk(rd: u8, imm16: u16, hw: u8, num_bits: u8) -> Self {
        Self { rd, imm16, hw: hw.into(), op: Op::MOVK, sf: num_bits.into() }
    }

    /// MOVZ
    /// <https://developer.arm.com/documentation/ddi0602/2022-03/Base-Instructions/MOVZ--Move-wide-with-zero-?lang=en>
    pub fn movz(rd: u8, imm16: u16, hw: u8, num_bits: u8) -> Self {
        Self { rd, imm16, hw: hw.into(), op: Op::MOVZ, sf: num_bits.into() }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Immediate?lang=en>
const FAMILY: u32 = 0b1000;

impl From<Mov> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Mov) -> Self {
        0
        | ((inst.sf as u32) << 31)
        | ((inst.op as u32) << 29)
        | (FAMILY << 25)
        | (0b101 << 23)
        | ((inst.hw as u32) << 21)
        | ((inst.imm16 as u32) << 5)
        | inst.rd as u32
    }
}

impl From<Mov> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Mov) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_movk_unshifted() {
        let inst = Mov::movk(0, 123, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf2800f60, result);
    }

    #[test]
    fn test_movk_shifted_16() {
        let inst = Mov::movk(0, 123, 16, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf2A00f60, result);
    }

    #[test]
    fn test_movk_shifted_32() {
        let inst = Mov::movk(0, 123, 32, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf2C00f60, result);
    }

    #[test]
    fn test_movk_shifted_48() {
        let inst = Mov::movk(0, 123, 48, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf2e00f60, result);
    }

    #[test]
    fn test_movz_unshifted() {
        let inst = Mov::movz(0, 123, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xd2800f60, result);
    }

    #[test]
    fn test_movz_shifted_16() {
        let inst = Mov::movz(0, 123, 16, 64);
        let result: u32 = inst.into();
        assert_eq!(0xd2a00f60, result);
    }

    #[test]
    fn test_movz_shifted_32() {
        let inst = Mov::movz(0, 123, 32, 64);
        let result: u32 = inst.into();
        assert_eq!(0xd2c00f60, result);
    }

    #[test]
    fn test_movz_shifted_48() {
        let inst = Mov::movz(0, 123, 48, 64);
        let result: u32 = inst.into();
        assert_eq!(0xd2e00f60, result);
    }
}
