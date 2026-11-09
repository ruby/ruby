/// The size of the register operands to this instruction.
enum Size {
    /// Using 32-bit registers.
    Size32 = 0b10,

    /// Using 64-bit registers.
    Size64 = 0b11
}

/// A convenience function so that we can convert the number of bits of an
/// register operand directly into a Size enum variant.
impl From<u8> for Size {
    fn from(num_bits: u8) -> Self {
        match num_bits {
            64 => Size::Size64,
            32 => Size::Size32,
            _ => panic!("Invalid number of bits: {num_bits}"),
        }
    }
}

/// The struct that represents an A64 atomic instruction that can be encoded.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |        1  1    1  0  0  0          1                     0  0  0  0    0  0                                   |
/// | size                         A  R    rs..............                       rn.............. rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Atomic {
    /// The register holding the value to be loaded.
    rt: u8,

    /// The base register.
    rn: u8,

    /// The register holding the data value to be operated on.
    rs: u8,

    /// The size of the registers used in this instruction.
    size: Size,

    /// Whether the load has acquire semantics (the A bit).
    acquire: bool,

    /// Whether the store has release semantics (the R bit).
    release: bool,
}

impl Atomic {
    /// LDADD, with no ordering constraints (relaxed)
    /// <https://support.arm.com/documentation/ddi0602/2026-09/Base-Instructions/LDADD--LDADDA--LDADDAL--LDADDL--Atomic-add-on-word-or-doubleword-?lang=en>
    pub fn ldadd(rs: u8, rt: u8, rn: u8, num_bits: u8) -> Self {
        Self { rt, rn, rs, size: num_bits.into(), acquire: false, release: false }
    }

    /// LDADDAL, with acquire and release semantics
    /// <https://support.arm.com/documentation/ddi0602/2026-09/Base-Instructions/LDADD--LDADDA--LDADDAL--LDADDL--Atomic-add-on-word-or-doubleword-?lang=en>
    pub fn ldaddal(rs: u8, rt: u8, rn: u8, num_bits: u8) -> Self {
        Self { rt, rn, rs, size: num_bits.into(), acquire: true, release: true }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en>
const FAMILY: u32 = 0b0100;

impl From<Atomic> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Atomic) -> Self {
        0
        | ((inst.size as u32) << 30)
        | (0b11 << 28)
        | (FAMILY << 25)
        | ((inst.acquire as u32) << 23)
        | ((inst.release as u32) << 22)
        | (1 << 21)
        | ((inst.rs as u32) << 16)
        | ((inst.rn as u32) << 5)
        | (inst.rt as u32)
    }
}

impl From<Atomic> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Atomic) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ldadd() {
        let result: u32 = Atomic::ldadd(20, 21, 22, 64).into();
        assert_eq!(0xf83402d5, result);
    }

    #[test]
    fn test_ldaddal() {
        let result: u32 = Atomic::ldaddal(20, 21, 22, 64).into();
        assert_eq!(0xf8f402d5, result);
    }
}
