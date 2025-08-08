use super::super::arg::truncate_imm;

/// The upper bit of the bit number to test.
#[derive(Debug)]
enum B5 {
    /// When the bit number is below 32.
    B532 = 0,

    /// When the bit number is equal to or above 32.
    B564 = 1
}

/// A convenience function so that we can convert the bit number directly into a
/// B5 variant.
impl From<u8> for B5 {
    fn from(bit_num: u8) -> Self {
        match bit_num {
            0..=31 => B5::B532,
            32..=63 => B5::B564,
            _ => panic!("Invalid bit number: {}", bit_num)
        }
    }
}

/// The operation to perform for this instruction.
enum Op {
    /// The test bit zero operation.
    TBZ = 0,

    /// The test bit not zero operation.
    TBNZ = 1
}

/// The struct that represents an A64 test bit instruction that can be encoded.
///
/// TBNZ/TBZ
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |     0  1  1    0  1  1                                                                                        |
/// | b5                     op   b40............. imm14.......................................... rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct TestBit {
    /// The number of the register to test.
    rt: u8,

    /// The PC-relative offset to the target instruction in term of number of
    /// instructions.
    imm14: i16,

    /// The lower 5 bits of the bit number to be tested.
    b40: u8,

    /// The operation to perform for this instruction.
    op: Op,

    /// The upper bit of the bit number to test.
    b5: B5
}

impl TestBit {
    /// TBNZ
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/TBNZ--Test-bit-and-Branch-if-Nonzero-?lang=en>
    pub fn tbnz(rt: u8, bit_num: u8, offset: i16) -> Self {
        Self { rt, imm14: offset, b40: bit_num & 0b11111, op: Op::TBNZ, b5: bit_num.into() }
    }

    /// TBZ
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/TBZ--Test-bit-and-Branch-if-Zero-?lang=en>
    pub fn tbz(rt: u8, bit_num: u8, offset: i16) -> Self {
        Self { rt, imm14: offset, b40: bit_num & 0b11111, op: Op::TBZ, b5: bit_num.into() }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en>
const FAMILY: u32 = 0b11011;

impl From<TestBit> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: TestBit) -> Self {
        let b40 = (inst.b40 & 0b11111) as u32;
        let imm14 = truncate_imm::<_, 14>(inst.imm14);

        ((inst.b5 as u32) << 31)
        | (FAMILY << 25)
        | ((inst.op as u32) << 24)
        | (b40 << 19)
        | (imm14 << 5)
        | inst.rt as u32
    }
}

impl From<TestBit> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: TestBit) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tbnz() {
        let inst = TestBit::tbnz(0, 0, 0);
        let result: u32 = inst.into();
        assert_eq!(0x37000000, result);
    }

    #[test]
    fn test_tbnz_negative() {
        let inst = TestBit::tbnz(0, 0, -1);
        let result: u32 = inst.into();
        assert_eq!(0x3707ffe0, result);
    }

    #[test]
    fn test_tbz() {
        let inst = TestBit::tbz(0, 0, 0);
        let result: u32 = inst.into();
        assert_eq!(0x36000000, result);
    }

    #[test]
    fn test_tbz_negative() {
        let inst = TestBit::tbz(0, 0, -1);
        let result: u32 = inst.into();
        assert_eq!(0x3607ffe0, result);
    }
}
