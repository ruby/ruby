/// The operation being performed for this instruction.
enum Op {
    Store = 0,
    Load = 1
}

/// The size of the registers being operated on.
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

/// The struct that represents an A64 load or store exclusive instruction that
/// can be encoded.
///
/// LDAXR/STLXR
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  1     0  0    1  0  0  0    0     0                     1  1  1  1    1  1                                   |
/// | size.                          op    rs..............                       rn.............. rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct LoadStoreExclusive {
    /// The number of the register to be loaded.
    rt: u8,

    /// The base register with which to form the address.
    rn: u8,

    /// The register to be used for the status result if it applies to this
    /// operation. Otherwise it's the zero register.
    rs: u8,

    /// The operation being performed for this instruction.
    op: Op,

    /// The size of the registers being operated on.
    size: Size
}

impl LoadStoreExclusive {
    /// LDAXR
    /// <https://developer.arm.com/documentation/ddi0602/2021-12/Base-Instructions/LDAXR--Load-Acquire-Exclusive-Register->
    pub fn ldaxr(rt: u8, rn: u8, num_bits: u8) -> Self {
        Self { rt, rn, rs: 31, op: Op::Load, size: num_bits.into() }
    }

    /// STLXR
    /// <https://developer.arm.com/documentation/ddi0602/2021-12/Base-Instructions/STLXR--Store-Release-Exclusive-Register->
    pub fn stlxr(rs: u8, rt: u8, rn: u8, num_bits: u8) -> Self {
        Self { rt, rn, rs, op: Op::Store, size: num_bits.into() }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en>
const FAMILY: u32 = 0b0100;

impl From<LoadStoreExclusive> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: LoadStoreExclusive) -> Self {
        0
        | ((inst.size as u32) << 30)
        | (FAMILY << 25)
        | ((inst.op as u32) << 22)
        | ((inst.rs as u32) << 16)
        | (0b111111 << 10)
        | ((inst.rn as u32) << 5)
        | (inst.rt as u32)
    }
}

impl From<LoadStoreExclusive> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: LoadStoreExclusive) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ldaxr() {
        let inst = LoadStoreExclusive::ldaxr(16, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xc85ffc10, result);
    }

    #[test]
    fn test_stlxr() {
        let inst = LoadStoreExclusive::stlxr(17, 16, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xc811fc10, result);
    }
}
