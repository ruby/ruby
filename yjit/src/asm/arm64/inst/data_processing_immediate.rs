use super::{family::Family, sf::Sf};

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

/// How much to shift the immediate by.
enum Shift {
    LSL0 = 0b0, // no shift
    LSL12 = 0b1 // logical shift left by 12 bits
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
pub struct DataProcessingImmediate {
    /// The register number of the destination register.
    rd: u8,

    /// The register number of the first operand register.
    rn: u8,

    /// The value of the immediate.
    imm12: u16,

    /// How much to shift the immediate by.
    shift: Shift,

    /// Whether or not to update the flags when this instruction is performed.
    s: S,

    /// The opcode for this instruction.
    op: Op,

    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf
}

impl DataProcessingImmediate {
    /// ADD (immediate)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADD--immediate---Add--immediate--?lang=en
    pub fn add(rd: u8, rn: u8, imm12: u16, num_bits: u8) -> Self {
        Self {
            rd,
            rn,
            imm12,
            shift: Shift::LSL0,
            s: S::LeaveFlags,
            op: Op::Add,
            sf: num_bits.into()
        }
    }

    /// ADDS (immediate, set flags)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADDS--immediate---Add--immediate---setting-flags-?lang=en
    pub fn adds(rd: u8, rn: u8, imm12: u16, num_bits: u8) -> Self {
        Self {
            rd,
            rn,
            imm12,
            shift: Shift::LSL0,
            s: S::UpdateFlags,
            op: Op::Add,
            sf: num_bits.into()
        }
    }

    /// SUB (immediate)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUB--immediate---Subtract--immediate--?lang=en
    pub fn sub(rd: u8, rn: u8, imm12: u16, num_bits: u8) -> Self {
        Self {
            rd,
            rn,
            imm12,
            shift: Shift::LSL0,
            s: S::LeaveFlags,
            op: Op::Sub,
            sf: num_bits.into()
        }
    }

    /// SUBS (immediate, set flags)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUBS--immediate---Subtract--immediate---setting-flags-?lang=en
    pub fn subs(rd: u8, rn: u8, imm12: u16, num_bits: u8) -> Self {
        Self {
            rd,
            rn,
            imm12,
            shift: Shift::LSL0,
            s: S::UpdateFlags,
            op: Op::Sub,
            sf: num_bits.into()
        }
    }
}

impl From<DataProcessingImmediate> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: DataProcessingImmediate) -> Self {
        let imm12 = (inst.imm12 as u32) & ((0b1 << 12) - 1);

        0
        | (inst.sf as u32).wrapping_shl(31)
        | (inst.op as u32).wrapping_shl(30)
        | (inst.s as u32).wrapping_shl(29)
        | (Family::DataProcessingImmediate as u32).wrapping_shl(25)
        | (0b1 << 24)
        | (inst.shift as u32).wrapping_shl(22)
        | imm12.wrapping_shl(10)
        | (inst.rn as u32).wrapping_shl(5)
        | inst.rd as u32
    }
}

impl From<DataProcessingImmediate> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: DataProcessingImmediate) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add() {
        let inst = DataProcessingImmediate::add(0, 1, 7, 64);
        let result: u32 = inst.into();
        assert_eq!(0x91001c20, result);
    }

    #[test]
    fn test_adds() {
        let inst = DataProcessingImmediate::adds(0, 1, 7, 64);
        let result: u32 = inst.into();
        assert_eq!(0xb1001c20, result);
    }

    #[test]
    fn test_sub() {
        let inst = DataProcessingImmediate::sub(0, 1, 7, 64);
        let result: u32 = inst.into();
        assert_eq!(0xd1001c20, result);
    }

    #[test]
    fn test_subs() {
        let inst = DataProcessingImmediate::subs(0, 1, 7, 64);
        let result: u32 = inst.into();
        assert_eq!(0xf1001c20, result);
    }
}
