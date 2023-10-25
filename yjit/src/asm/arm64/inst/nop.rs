/// The struct that represents an A64 nop instruction that can be encoded.
///
/// NOP
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  1  1  0  1    0  1  0  1    0  0  0  0    0  0  1  1    0  0  1  0    0  0  0  0    0  0  0  1    1  1  1  1 |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct Nop;

impl Nop {
    /// NOP
    /// https://developer.arm.com/documentation/ddi0602/2022-03/Base-Instructions/NOP--No-Operation-
    pub fn nop() -> Self {
        Self {}
    }
}

impl From<Nop> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(_inst: Nop) -> Self {
        0b11010101000000110010000000011111
    }
}

impl From<Nop> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: Nop) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_nop() {
        let inst = Nop::nop();
        let result: u32 = inst.into();
        assert_eq!(0xd503201f, result);
    }
}
