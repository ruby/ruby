/// The size of the operands being operated on.
enum Size {
    Size32 = 0b10,
    Size64 = 0b11,
}

/// A convenience function so that we can convert the number of bits of an
/// register operand directly into an Sf enum variant.
impl From<u8> for Size {
    fn from(num_bits: u8) -> Self {
        match num_bits {
            64 => Size::Size64,
            32 => Size::Size32,
            _ => panic!("Invalid number of bits: {}", num_bits)
        }
    }
}

/// The struct that represents an A64 store instruction that can be encoded.
///
/// STUR
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |        1  1    1  0  0  0    0  0  0                                   0  0                                   |
/// | size.                                imm9..........................         rn.............. rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Store {
    /// The number of the register to be transferred.
    rt: u8,

    /// The register holding the memory location.
    rn: u8,

    /// The optional signed immediate byte offset from the base register.
    imm9: i16,

    /// The size of the operands being operated on.
    size: Size
}

impl Store {
    /// STUR (store register, unscaled)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/STUR--Store-Register--unscaled--?lang=en
    pub fn stur(rt: u8, rn: u8, imm9: i16, num_bits: u8) -> Self {
        Self {
            rt,
            rn,
            imm9,
            size: num_bits.into()
        }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en
const FAMILY: u32 = 0b0100;

impl From<Store> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Store) -> Self {
        let imm9 = (inst.imm9 as u32) & ((1 << 9) - 1);

        0
        | ((inst.size as u32) << 30)
        | (0b11 << 28)
        | (FAMILY << 25)
        | (imm9 << 12)
        | ((inst.rn as u32) << 5)
        | (inst.rt as u32)
    }
}

impl From<Store> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Store) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stur() {
        let inst = Store::stur(0, 1, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf8000020, result);
    }

    #[test]
    fn test_stur_negative_offset() {
        let inst = Store::stur(0, 1, -1, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf81ff020, result);
    }

    #[test]
    fn test_stur_positive_offset() {
        let inst = Store::stur(0, 1, 255, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf80ff020, result);
    }
}
