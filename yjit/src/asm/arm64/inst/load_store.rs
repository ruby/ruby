use super::super::arg::truncate_imm;

/// The size of the operands being operated on.
enum Size {
    Size8 = 0b00,
    Size16 = 0b01,
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

/// The operation to perform for this instruction.
enum Opc {
    STR = 0b00,
    LDR = 0b01,
    LDURSW = 0b10
}

/// What kind of indexing to perform for this instruction.
enum Index {
    None = 0b00,
    PostIndex = 0b01,
    PreIndex = 0b11
}

/// The struct that represents an A64 load or store instruction that can be
/// encoded.
///
/// LDR/LDUR/LDURSW/STR/STUR
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |        1  1    1  0  0  0          0                                                                          |
/// | size.                       opc..    imm9..........................   idx.. rn.............. rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct LoadStore {
    /// The number of the register to load the value into.
    rt: u8,

    /// The base register with which to form the address.
    rn: u8,

    /// What kind of indexing to perform for this instruction.
    idx: Index,

    /// The optional signed immediate byte offset from the base register.
    imm9: i16,

    /// The operation to perform for this instruction.
    opc: Opc,

    /// The size of the operands being operated on.
    size: Size
}

impl LoadStore {
    /// LDR (immediate, post-index)
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/LDR--immediate---Load-Register--immediate-->
    pub fn ldr_post(rt: u8, rn: u8, imm9: i16, num_bits: u8) -> Self {
        Self { rt, rn, idx: Index::PostIndex, imm9, opc: Opc::LDR, size: num_bits.into() }
    }

    /// LDR (immediate, pre-index)
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/LDR--immediate---Load-Register--immediate-->
    pub fn ldr_pre(rt: u8, rn: u8, imm9: i16, num_bits: u8) -> Self {
        Self { rt, rn, idx: Index::PreIndex, imm9, opc: Opc::LDR, size: num_bits.into() }
    }

    /// LDUR (load register, unscaled)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDUR--Load-Register--unscaled--?lang=en>
    pub fn ldur(rt: u8, rn: u8, imm9: i16, num_bits: u8) -> Self {
        Self { rt, rn, idx: Index::None, imm9, opc: Opc::LDR, size: num_bits.into() }
    }

    /// LDURH Load Register Halfword (unscaled)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDURH--Load-Register-Halfword--unscaled--?lang=en>
    pub fn ldurh(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, idx: Index::None, imm9, opc: Opc::LDR, size: Size::Size16 }
    }

    /// LDURB (load register, byte, unscaled)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDURB--Load-Register-Byte--unscaled--?lang=en>
    pub fn ldurb(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, idx: Index::None, imm9, opc: Opc::LDR, size: Size::Size8 }
    }

    /// LDURSW (load register, unscaled, signed)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/LDURSW--Load-Register-Signed-Word--unscaled--?lang=en>
    pub fn ldursw(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, idx: Index::None, imm9, opc: Opc::LDURSW, size: Size::Size32 }
    }

    /// STR (immediate, post-index)
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/STR--immediate---Store-Register--immediate-->
    pub fn str_post(rt: u8, rn: u8, imm9: i16, num_bits: u8) -> Self {
        Self { rt, rn, idx: Index::PostIndex, imm9, opc: Opc::STR, size: num_bits.into() }
    }

    /// STR (immediate, pre-index)
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/STR--immediate---Store-Register--immediate-->
    pub fn str_pre(rt: u8, rn: u8, imm9: i16, num_bits: u8) -> Self {
        Self { rt, rn, idx: Index::PreIndex, imm9, opc: Opc::STR, size: num_bits.into() }
    }

    /// STUR (store register, unscaled)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/STUR--Store-Register--unscaled--?lang=en>
    pub fn stur(rt: u8, rn: u8, imm9: i16, num_bits: u8) -> Self {
        Self { rt, rn, idx: Index::None, imm9, opc: Opc::STR, size: num_bits.into() }
    }

    /// STURH (store register, halfword, unscaled)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/STURH--Store-Register-Halfword--unscaled--?lang=en>
    pub fn sturh(rt: u8, rn: u8, imm9: i16) -> Self {
        Self { rt, rn, idx: Index::None, imm9, opc: Opc::STR, size: Size::Size16 }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Loads-and-Stores?lang=en>
const FAMILY: u32 = 0b0100;

impl From<LoadStore> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: LoadStore) -> Self {
        0
        | ((inst.size as u32) << 30)
        | (0b11 << 28)
        | (FAMILY << 25)
        | ((inst.opc as u32) << 22)
        | (truncate_imm::<_, 9>(inst.imm9) << 12)
        | ((inst.idx as u32) << 10)
        | ((inst.rn as u32) << 5)
        | (inst.rt as u32)
    }
}

impl From<LoadStore> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: LoadStore) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ldr_post() {
        let inst = LoadStore::ldr_post(0, 1, 16, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf8410420, result);
    }

    #[test]
    fn test_ldr_pre() {
        let inst = LoadStore::ldr_pre(0, 1, 16, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf8410c20, result);
    }

    #[test]
    fn test_ldur() {
        let inst = LoadStore::ldur(0, 1, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf8400020, result);
    }

    #[test]
    fn test_ldurb() {
        let inst = LoadStore::ldurb(0, 1, 0);
        let result: u32 = inst.into();
        assert_eq!(0x38400020, result);
    }

    #[test]
    fn test_ldurh() {
        let inst = LoadStore::ldurh(0, 1, 0);
        let result: u32 = inst.into();
        assert_eq!(0x78400020, result);
    }

    #[test]
    fn test_ldur_with_imm() {
        let inst = LoadStore::ldur(0, 1, 123, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf847b020, result);
    }

    #[test]
    fn test_ldursw() {
        let inst = LoadStore::ldursw(0, 1, 0);
        let result: u32 = inst.into();
        assert_eq!(0xb8800020, result);
    }

    #[test]
    fn test_ldursw_with_imm() {
        let inst = LoadStore::ldursw(0, 1, 123);
        let result: u32 = inst.into();
        assert_eq!(0xb887b020, result);
    }

    #[test]
    fn test_str_post() {
        let inst = LoadStore::str_post(0, 1, -16, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf81f0420, result);
    }

    #[test]
    fn test_str_pre() {
        let inst = LoadStore::str_pre(0, 1, -16, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf81f0c20, result);
    }

    #[test]
    fn test_stur() {
        let inst = LoadStore::stur(0, 1, 0, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf8000020, result);
    }

    #[test]
    fn test_stur_negative_offset() {
        let inst = LoadStore::stur(0, 1, -1, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf81ff020, result);
    }

    #[test]
    fn test_stur_positive_offset() {
        let inst = LoadStore::stur(0, 1, 255, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf80ff020, result);
    }
}
