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
pub struct DataProcessingRegister {
    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf,

    /// The opcode for this instruction.
    op: Op,

    /// Whether or not to update the flags when this instruction is performed.
    s: S,

    /// The type of shift to perform on the second operand register.
    shift: Shift,

    /// The register number of the second operand register.
    rm: u8,

    /// The amount to shift the second operand register by.
    imm6: u8,

    /// The register number of the first operand register.
    rn: u8,

    /// The register number of the destination register.
    rd: u8
}

impl DataProcessingRegister {
    /// ADD (shifted register)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADD--shifted-register---Add--shifted-register--?lang=en
    pub fn add(rd: &A64Opnd, rn: &A64Opnd, rm: &A64Opnd) -> Self {
        let (rd, rn, rm) = Self::unwrap(rd, rn, rm);

        Self {
            sf: rd.num_bits.into(),
            op: Op::Add,
            s: S::LeaveFlags,
            shift: Shift::LSL,
            rm: rm.reg_no,
            imm6: 0,
            rn: rn.reg_no,
            rd: rd.reg_no
        }
    }

    /// ADDS (shifted register, set flags)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADDS--shifted-register---Add--shifted-register---setting-flags-?lang=en
    pub fn adds(rd: &A64Opnd, rn: &A64Opnd, rm: &A64Opnd) -> Self {
        let (rd, rn, rm) = Self::unwrap(rd, rn, rm);

        Self {
            sf: rd.num_bits.into(),
            op: Op::Add,
            s: S::UpdateFlags,
            shift: Shift::LSL,
            rm: rm.reg_no,
            imm6: 0,
            rn: rn.reg_no,
            rd: rd.reg_no
        }
    }

    /// SUB (shifted register)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUB--shifted-register---Subtract--shifted-register--?lang=en
    pub fn sub(rd: &A64Opnd, rn: &A64Opnd, rm: &A64Opnd) -> Self {
        let (rd, rn, rm) = Self::unwrap(rd, rn, rm);

        Self {
            sf: rd.num_bits.into(),
            op: Op::Sub,
            s: S::LeaveFlags,
            shift: Shift::LSL,
            rm: rm.reg_no,
            imm6: 0,
            rn: rn.reg_no,
            rd: rd.reg_no
        }
    }

    /// SUBS (shifted register, set flags)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUBS--shifted-register---Subtract--shifted-register---setting-flags-?lang=en
    pub fn subs(rd: &A64Opnd, rn: &A64Opnd, rm: &A64Opnd) -> Self {
        let (rd, rn, rm) = Self::unwrap(rd, rn, rm);

        Self {
            sf: rd.num_bits.into(),
            op: Op::Sub,
            s: S::UpdateFlags,
            shift: Shift::LSL,
            rm: rm.reg_no,
            imm6: 0,
            rn: rn.reg_no,
            rd: rd.reg_no
        }
    }

    /// Extract out three registers from the given operands. Panic if any of the
    /// operands are not registers or if they are not the same size.
    fn unwrap<'a>(rd: &'a A64Opnd, rn: &'a A64Opnd, rm: &'a A64Opnd) -> (&'a A64Reg, &'a A64Reg, &'a A64Reg) {
        match (rd, rn, rm) {
            (A64Opnd::Reg(rd), A64Opnd::Reg(rn), A64Opnd::Reg(rm)) => {
                assert!(rd.num_bits == rn.num_bits && rn.num_bits == rm.num_bits, "All operands to a data processing register instruction must be of the same size.");
                (rd, rn, rm)
            },
            _ => {
                panic!("Expected 3 register operands for a data processing register instruction.");
            }
        }
    }
}

impl From<DataProcessingRegister> for u32 {
    /// Convert a data processing instruction into a 32-bit value.
    fn from(inst: DataProcessingRegister) -> Self {
        let imm6 = (inst.imm6 as u32) & (2_u32.pow(6) - 1);

        0
        | (inst.sf as u32).wrapping_shl(31)
        | (inst.op as u32).wrapping_shl(30)
        | (inst.s as u32).wrapping_shl(29)
        | (Family::DataProcessingRegister as u32).wrapping_shl(25)
        | (0b1 << 24)
        | (inst.shift as u32).wrapping_shl(22)
        | (inst.rm as u32).wrapping_shl(16)
        | imm6.wrapping_shl(10)
        | (inst.rn as u32).wrapping_shl(5)
        | inst.rd as u32
    }
}

impl From<DataProcessingRegister> for [u8; 4] {
    /// Convert a data processing instruction into a 4 byte array.
    fn from(inst: DataProcessingRegister) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add() {
        let inst = DataProcessingRegister::add(&X0, &X1, &X2);
        let result: u32 = inst.into();
        assert_eq!(0x8b020020, result);
    }

    #[test]
    fn test_adds() {
        let inst = DataProcessingRegister::adds(&X0, &X1, &X2);
        let result: u32 = inst.into();
        assert_eq!(0xab020020, result);
    }

    #[test]
    fn test_sub() {
        let inst = DataProcessingRegister::sub(&X0, &X1, &X2);
        let result: u32 = inst.into();
        assert_eq!(0xcb020020, result);
    }

    #[test]
    fn test_subs() {
        let inst = DataProcessingRegister::subs(&X0, &X1, &X2);
        let result: u32 = inst.into();
        assert_eq!(0xeb020020, result);
    }
}
