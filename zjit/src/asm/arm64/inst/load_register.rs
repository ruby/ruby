/// Whether or not to shift the register.
enum S {
    Shift = 1,
    NoShift = 0
}

/// The option for this instruction.
enum Option {
    UXTW = 0b010,
    LSL = 0b011,
    SXTW = 0b110,
    SXTX = 0b111
}

/// The size of the operands of this instruction.
enum Size {
    Size32 = 0b10,
    Size64 = 0b11
}

/// A convenience function so that we can convert the number of bits of an
/// register operand directly into a Size enum variant.
impl From<u8> for Size {
    fn from(num_bits: u8) -> Self {
        match num_bits {
            64 => Size::Size64,
            32 => Size::Size32,
            _ => panic!("Invalid number of bits: {}", num_bits)
        }
    }
}

/// The struct that represents an A64 load instruction that can be encoded.
///
/// LDR
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |        1  1    1  0  0  0    0  1  1                                   1  0                                   |
/// | size.                                rm..............   option.. S          rn.............. rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct LoadRegister {
    /// The number of the register to load the value into.
    rt: u8,

    /// The base register with which to form the address.
    rn: u8,

    /// Whether or not to shift the value of the register.
    s: S,

    /// The option associated with this instruction that controls the shift.
    option: Option,

    /// The number of the offset register.
    rm: u8,

    /// The size of the operands.
    size: Size
}

impl LoadRegister {
    /// LDR
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDR--register---Load-Register--register--?lang=en>
    pub fn ldr(rt: u8, rn: u8, rm: u8, num_bits: u8) -> Self {
        Self { rt, rn, s: S::NoShift, option: Option::LSL, rm, size: num_bits.into() }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en>
const FAMILY: u32 = 0b0100;

impl From<LoadRegister> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: LoadRegister) -> Self {
        0
        | ((inst.size as u32) << 30)
        | (0b11 << 28)
        | (FAMILY << 25)
        | (0b11 << 21)
        | ((inst.rm as u32) << 16)
        | ((inst.option as u32) << 13)
        | ((inst.s as u32) << 12)
        | (0b10 << 10)
        | ((inst.rn as u32) << 5)
        | (inst.rt as u32)
    }
}

impl From<LoadRegister> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: LoadRegister) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ldr() {
        let inst = LoadRegister::ldr(0, 1, 2, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf8626820, result);
    }
}
