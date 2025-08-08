use super::super::arg::{InstructionOffset, truncate_imm};

/// The size of the operands being operated on.
enum Opc {
    Size32 = 0b00,
    Size64 = 0b01,
}

/// A convenience function so that we can convert the number of bits of an
/// register operand directly into an Sf enum variant.
impl From<u8> for Opc {
    fn from(num_bits: u8) -> Self {
        match num_bits {
            64 => Opc::Size64,
            32 => Opc::Size32,
            _ => panic!("Invalid number of bits: {}", num_bits)
        }
    }
}

/// The struct that represents an A64 load literal instruction that can be encoded.
///
/// LDR
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |        0  1    1  0  0  0                                                                                     |
/// | opc..                       imm19........................................................... rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct LoadLiteral {
    /// The number of the register to load the value into.
    rt: u8,

    /// The PC-relative number of instructions to load the value from.
    offset: InstructionOffset,

    /// The size of the operands being operated on.
    opc: Opc
}

impl LoadLiteral {
    /// LDR (load literal)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDR--literal---Load-Register--literal--?lang=en>
    pub fn ldr_literal(rt: u8, offset: InstructionOffset, num_bits: u8) -> Self {
        Self { rt, offset, opc: num_bits.into() }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en>
const FAMILY: u32 = 0b0100;

impl From<LoadLiteral> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: LoadLiteral) -> Self {
        ((inst.opc as u32) << 30)
        | (1 << 28)
        | (FAMILY << 25)
        | (truncate_imm::<_, 19>(inst.offset) << 5)
        | (inst.rt as u32)
    }
}

impl From<LoadLiteral> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: LoadLiteral) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ldr_positive() {
        let inst = LoadLiteral::ldr_literal(0, 5.into(), 64);
        let result: u32 = inst.into();
        assert_eq!(0x580000a0, result);
    }

    #[test]
    fn test_ldr_negative() {
        let inst = LoadLiteral::ldr_literal(0, (-5).into(), 64);
        let result: u32 = inst.into();
        assert_eq!(0x58ffff60, result);
    }
}
