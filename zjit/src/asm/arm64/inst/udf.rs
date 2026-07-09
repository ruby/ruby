/// The struct that represents an A64 permanently undefined instruction.
///
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  0  0  0  0    0  0  0  0    0  0  0  0    0  0  0  0                                                         |
/// |                                                         imm16..................................................|
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Udf {
    /// The immediate value encoded in the instruction
    imm16: u16
}

impl Udf {
    /// UDF - Permanently Undefined
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/UDF--Permanently-Undefined->
    pub fn udf(imm16: u16) -> Self {
        Self { imm16 }
    }
}

impl From<Udf> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: Udf) -> Self {
        inst.imm16 as u32
    }
}

impl From<Udf> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Udf) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_udf() {
        let result: u32 = Udf::udf(0).into();
        assert_eq!(0x00000000, result);
    }

    #[test]
    fn test_udf_imm() {
        let result: u32 = Udf::udf(1).into();
        assert_eq!(0x00000001, result);
    }
}
