use super::{
    super::opnd::*,
    family::Family,
    sf::Sf
};

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
    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf,

    /// The opcode for this instruction.
    op: Op,

    /// Whether or not to update the flags when this instruction is performed.
    s: S,

    /// How much to shift the immediate by.
    shift: Shift,

    /// The value of the immediate.
    imm12: u16,

    /// The register number of the first operand register.
    rn: u8,

    /// The register number of the destination register.
    rd: u8
}

impl DataProcessingImmediate {
    /// ADD (immediate)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADD--immediate---Add--immediate--?lang=en
    pub fn add(rd: &A64Opnd, rn: &A64Opnd, imm12: &A64Opnd) -> Self {
        let (rd, rn, imm12) = Self::unwrap(rd, rn, imm12);

        Self {
            sf: rd.num_bits.into(),
            op: Op::Add,
            s: S::LeaveFlags,
            shift: Shift::LSL0,
            imm12: imm12.value as u16,
            rn: rn.reg_no,
            rd: rd.reg_no
        }
    }

    /// ADDS (immediate, set flags)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADDS--immediate---Add--immediate---setting-flags-?lang=en
    pub fn adds(rd: &A64Opnd, rn: &A64Opnd, imm12: &A64Opnd) -> Self {
        let (rd, rn, imm12) = Self::unwrap(rd, rn, imm12);

        Self {
            sf: rd.num_bits.into(),
            op: Op::Add,
            s: S::UpdateFlags,
            shift: Shift::LSL0,
            imm12: imm12.value as u16,
            rn: rn.reg_no,
            rd: rd.reg_no
        }
    }

    /// SUB (immediate)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUB--immediate---Subtract--immediate--?lang=en
    pub fn sub(rd: &A64Opnd, rn: &A64Opnd, imm12: &A64Opnd) -> Self {
        let (rd, rn, imm12) = Self::unwrap(rd, rn, imm12);

        Self {
            sf: rd.num_bits.into(),
            op: Op::Sub,
            s: S::LeaveFlags,
            shift: Shift::LSL0,
            imm12: imm12.value as u16,
            rn: rn.reg_no,
            rd: rd.reg_no
        }
    }

    /// SUBS (immediate, set flags)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUBS--immediate---Subtract--immediate---setting-flags-?lang=en
    pub fn subs(rd: &A64Opnd, rn: &A64Opnd, imm12: &A64Opnd) -> Self {
        let (rd, rn, imm12) = Self::unwrap(rd, rn, imm12);

        Self {
            sf: rd.num_bits.into(),
            op: Op::Sub,
            s: S::UpdateFlags,
            shift: Shift::LSL0,
            imm12: imm12.value as u16,
            rn: rn.reg_no,
            rd: rd.reg_no
        }
    }

    /// Extract out two registers and an immediate from the given operands.
    /// Panic if any of the operands do not match the expected type or size.
    fn unwrap<'a>(rd: &'a A64Opnd, rn: &'a A64Opnd, imm12: &'a A64Opnd) -> (&'a A64Reg, &'a A64Reg, &'a A64UImm) {
        match (rd, rn, imm12) {
            (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::UImm(imm12)) => {
                assert!(rd.num_bits == rn.num_bits, "Both rd and rn operands to a data processing immediate instruction must be of the same size.");
                assert!(imm12.num_bits <= 12, "The immediate operand to a data processing immediate instruction must be 12 bits or less.");
                (rd, rn, imm12)
            },
            _ => {
                panic!("Expected 2 register operands and an immediate operand for a data processing immediate instruction.");
            }
        }
    }
}

impl From<DataProcessingImmediate> for u32 {
    /// Convert a data processing instruction into a 32-bit value.
    fn from(inst: DataProcessingImmediate) -> Self {
        let imm12 = (inst.imm12 as u32) & (2_u32.pow(12) - 1);

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
    /// Convert a data processing instruction into a 4 byte array.
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
        let uimm12 = A64Opnd::new_uimm(7);
        let inst = DataProcessingImmediate::add(&X0, &X1, &uimm12);
        let result: u32 = inst.into();
        assert_eq!(0x91001c20, result);
    }

    #[test]
    fn test_adds() {
        let uimm12 = A64Opnd::new_uimm(7);
        let inst = DataProcessingImmediate::adds(&X0, &X1, &uimm12);
        let result: u32 = inst.into();
        assert_eq!(0xb1001c20, result);
    }

    #[test]
    fn test_sub() {
        let uimm12 = A64Opnd::new_uimm(7);
        let inst = DataProcessingImmediate::sub(&X0, &X1, &uimm12);
        let result: u32 = inst.into();
        assert_eq!(0xd1001c20, result);
    }

    #[test]
    fn test_subs() {
        let uimm12 = A64Opnd::new_uimm(7);
        let inst = DataProcessingImmediate::subs(&X0, &X1, &uimm12);
        let result: u32 = inst.into();
        assert_eq!(0xf1001c20, result);
    }
}
