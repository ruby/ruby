/// The size of the operands being operated on.
enum Size {
    Size32 = 0b10,
    Size64 = 0b11,
}

/// The operation to perform for this instruction.
enum Opc {
    LDUR = 0b01,
    LDURSW = 0b10
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

/// The struct that represents an A64 data processing -- immediate instruction
/// that can be encoded.
///
/// LDUR
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |        1  1    1  0  0  0          0                                   0  0                                   |
/// | size.                       opc..       imm9..........................         rn.............. rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Load {
    /// The number of the register to load the value into.
    rt: u8,

    /// The base register with which to form the address.
    rn: u8,

    /// The optional signed immediate byte offset from the base register.
    imm9: i16,

    /// The operation to perform for this instruction.
    opc: Opc,

    /// The size of the operands being operated on.
    size: Size
}

impl Load {
    /// LDUR (load register, unscaled)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDUR--Load-Register--unscaled--?lang=en
    pub fn ldur(rt: u8, rn: u8, imm9: i16, num_bits: u8) -> Self {
        Self { rt, rn, imm9, opc: Opc::LDUR, size: num_bits.into() }
    }

    /// LDURSW (load register, unscaled, signed)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDURSW--Load-Register-Signed-Word--unscaled--?lang=en
    pub fn ldursw(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, imm9, opc: Opc::LDURSW, size: Size::Size32 }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en
const FAMILY: u32 = 0b0100;

impl From<Load> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Load) -> Self {
        let imm9 = (inst.imm9 as u32) & ((1 << 9) - 1);

        0
        | ((inst.size as u32) << 30)
        | (0b11 << 28)
        | (FAMILY << 25)
        | ((inst.opc as u32) << 22)
        | (imm9 << 12)
        | ((inst.rn as u32) << 5)
        | (inst.rt as u32)
    }
}

impl From<Load> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Load) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ldur() {
        let inst = Load::ldur(0, 1, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf8400020, result);
    }

    #[test]
    fn test_ldur_with_imm() {
        let inst = Load::ldur(0, 1, 123, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf847b020, result);
    }

    #[test]
    fn test_ldursw() {
        let inst = Load::ldursw(0, 1, 0);
        let result: u32 = inst.into();
        assert_eq!(0xb8800020, result);
    }

    #[test]
    fn test_ldursw_with_imm() {
        let inst = Load::ldursw(0, 1, 123);
        let result: u32 = inst.into();
        assert_eq!(0xb887b020, result);
    }
}
