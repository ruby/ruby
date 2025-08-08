use super::super::arg::{Sf, ShiftedImmediate};

/// The operation being performed by this instruction.
enum Op {
    Add = 0b0,
    Sub = 0b1
}

// Whether or not to update the flags when this instruction is performed.
enum S {
    LeaveFlags = 0b0,
    UpdateFlags = 0b1
}

/// The struct that represents an A64 data processing -- immediate instruction
/// that can be encoded.
///
/// Add/subtract (immediate)
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |           1    0  0  0  1    0                                                                                |
/// | sf op  S                       sh imm12.................................... rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct DataImm {
    /// The register number of the destination register.
    rd: u8,

    /// The register number of the first operand register.
    rn: u8,

    /// How much to shift the immediate by.
    imm: ShiftedImmediate,

    /// Whether or not to update the flags when this instruction is performed.
    s: S,

    /// The opcode for this instruction.
    op: Op,

    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf
}

impl DataImm {
    /// ADD (immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADD--immediate---Add--immediate--?lang=en>
    pub fn add(rd: u8, rn: u8, imm: ShiftedImmediate, num_bits: u8) -> Self {
        Self { rd, rn, imm, s: S::LeaveFlags, op: Op::Add, sf: num_bits.into() }
    }

    /// ADDS (immediate, set flags)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADDS--immediate---Add--immediate---setting-flags-?lang=en>
    pub fn adds(rd: u8, rn: u8, imm: ShiftedImmediate, num_bits: u8) -> Self {
        Self { rd, rn, imm, s: S::UpdateFlags, op: Op::Add, sf: num_bits.into() }
    }

    /// CMP (immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/CMP--immediate---Compare--immediate---an-alias-of-SUBS--immediate--?lang=en>
    pub fn cmp(rn: u8, imm: ShiftedImmediate, num_bits: u8) -> Self {
        Self::subs(31, rn, imm, num_bits)
    }

    /// SUB (immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUB--immediate---Subtract--immediate--?lang=en>
    pub fn sub(rd: u8, rn: u8, imm: ShiftedImmediate, num_bits: u8) -> Self {
        Self { rd, rn, imm, s: S::LeaveFlags, op: Op::Sub, sf: num_bits.into() }
    }

    /// SUBS (immediate, set flags)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUBS--immediate---Subtract--immediate---setting-flags-?lang=en>
    pub fn subs(rd: u8, rn: u8, imm: ShiftedImmediate, num_bits: u8) -> Self {
        Self { rd, rn, imm, s: S::UpdateFlags, op: Op::Sub, sf: num_bits.into() }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Immediate?lang=en>
const FAMILY: u32 = 0b1000;

impl From<DataImm> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: DataImm) -> Self {
        let imm: u32 = inst.imm.into();

        ((inst.sf as u32) << 31)
        | ((inst.op as u32) << 30)
        | ((inst.s as u32) << 29)
        | (FAMILY << 25)
        | (1 << 24)
        | (imm << 10)
        | ((inst.rn as u32) << 5)
        | inst.rd as u32
    }
}

impl From<DataImm> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: DataImm) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add() {
        let inst = DataImm::add(0, 1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0x91001c20, result);
    }

    #[test]
    fn test_adds() {
        let inst = DataImm::adds(0, 1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xb1001c20, result);
    }

    #[test]
    fn test_cmp() {
        let inst = DataImm::cmp(0, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xf1001c1f, result);
    }

    #[test]
    fn test_sub() {
        let inst = DataImm::sub(0, 1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xd1001c20, result);
    }

    #[test]
    fn test_subs() {
        let inst = DataImm::subs(0, 1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xf1001c20, result);
    }
}
