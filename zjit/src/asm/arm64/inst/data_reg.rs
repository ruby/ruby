use super::super::arg::{Sf, truncate_uimm};

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

/// The type of shift to perform on the second operand register.
enum Shift {
    LSL = 0b00, // logical shift left (unsigned)
    LSR = 0b01, // logical shift right (unsigned)
    ASR = 0b10  // arithmetic shift right (signed)
}

/// The struct that represents an A64 data processing -- register instruction
/// that can be encoded.
///
/// Add/subtract (shifted register)
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |           0    1  0  1  1          0                                                                          |
/// | sf op  S                    shift    rm..............   imm6............... rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct DataReg {
    /// The register number of the destination register.
    rd: u8,

    /// The register number of the first operand register.
    rn: u8,

    /// The amount to shift the second operand register by.
    imm6: u8,

    /// The register number of the second operand register.
    rm: u8,

    /// The type of shift to perform on the second operand register.
    shift: Shift,

    /// Whether or not to update the flags when this instruction is performed.
    s: S,

    /// The opcode for this instruction.
    op: Op,

    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf
}

impl DataReg {
    /// ADD (shifted register)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADD--shifted-register---Add--shifted-register--?lang=en>
    pub fn add(rd: u8, rn: u8, rm: u8, num_bits: u8) -> Self {
        Self {
            rd,
            rn,
            imm6: 0,
            rm,
            shift: Shift::LSL,
            s: S::LeaveFlags,
            op: Op::Add,
            sf: num_bits.into()
        }
    }

    /// ADDS (shifted register, set flags)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADDS--shifted-register---Add--shifted-register---setting-flags-?lang=en>
    pub fn adds(rd: u8, rn: u8, rm: u8, num_bits: u8) -> Self {
        Self {
            rd,
            rn,
            imm6: 0,
            rm,
            shift: Shift::LSL,
            s: S::UpdateFlags,
            op: Op::Add,
            sf: num_bits.into()
        }
    }

    /// CMP (shifted register)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/CMP--shifted-register---Compare--shifted-register---an-alias-of-SUBS--shifted-register--?lang=en>
    pub fn cmp(rn: u8, rm: u8, num_bits: u8) -> Self {
        Self::subs(31, rn, rm, num_bits)
    }

    /// SUB (shifted register)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUB--shifted-register---Subtract--shifted-register--?lang=en>
    pub fn sub(rd: u8, rn: u8, rm: u8, num_bits: u8) -> Self {
        Self {
            rd,
            rn,
            imm6: 0,
            rm,
            shift: Shift::LSL,
            s: S::LeaveFlags,
            op: Op::Sub,
            sf: num_bits.into()
        }
    }

    /// SUBS (shifted register, set flags)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUBS--shifted-register---Subtract--shifted-register---setting-flags-?lang=en>
    pub fn subs(rd: u8, rn: u8, rm: u8, num_bits: u8) -> Self {
        Self {
            rd,
            rn,
            imm6: 0,
            rm,
            shift: Shift::LSL,
            s: S::UpdateFlags,
            op: Op::Sub,
            sf: num_bits.into()
        }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Register?lang=en>
const FAMILY: u32 = 0b0101;

impl From<DataReg> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: DataReg) -> Self {
        ((inst.sf as u32) << 31)
        | ((inst.op as u32) << 30)
        | ((inst.s as u32) << 29)
        | (FAMILY << 25)
        | (1 << 24)
        | ((inst.shift as u32) << 22)
        | ((inst.rm as u32) << 16)
        | (truncate_uimm::<_, 6>(inst.imm6) << 10)
        | ((inst.rn as u32) << 5)
        | inst.rd as u32
    }
}

impl From<DataReg> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: DataReg) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add() {
        let inst = DataReg::add(0, 1, 2, 64);
        let result: u32 = inst.into();
        assert_eq!(0x8b020020, result);
    }

    #[test]
    fn test_adds() {
        let inst = DataReg::adds(0, 1, 2, 64);
        let result: u32 = inst.into();
        assert_eq!(0xab020020, result);
    }

    #[test]
    fn test_cmp() {
        let inst = DataReg::cmp(0, 1, 64);
        let result: u32 = inst.into();
        assert_eq!(0xeb01001f, result);
    }

    #[test]
    fn test_sub() {
        let inst = DataReg::sub(0, 1, 2, 64);
        let result: u32 = inst.into();
        assert_eq!(0xcb020020, result);
    }

    #[test]
    fn test_subs() {
        let inst = DataReg::subs(0, 1, 2, 64);
        let result: u32 = inst.into();
        assert_eq!(0xeb020020, result);
    }
}
