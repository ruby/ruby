use super::family::Family;
use super::super::opnd::Arm64Reg;

/// The size of the operands that we are performing the instruction on.
enum Sf {
    Sf32 = 0b0,
    Sf64 = 0b1
}

/// A convenience function so that we can convert the number of bits of an
/// operand register directly into an Sf enum variant.
impl From<u8> for Sf {
    fn from(num_bits: u8) -> Self {
        match num_bits {
            64 => Sf::Sf64,
            32 => Sf::Sf32,
            _ => panic!("Invalid num_bits value: {}", num_bits)
        }
    }
}

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
    LSL = 0b00,
    LSR = 0b01,
    ASR = 0b10,
    Reserved = 0b11
}

/// The struct that represents an A64 data processing -- register instruction
/// that can be encoded.
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
    /// Add (shifted register)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ADD--shifted-register---Add--shifted-register--?lang=en
    pub fn add(rd: &Arm64Reg, rn: &Arm64Reg, rm: &Arm64Reg) -> Self {
        DataProcessingRegister {
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

    /// Sub (shifted register)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SUB--shifted-register---Subtract--shifted-register--?lang=en
    pub fn sub(rd: &Arm64Reg, rn: &Arm64Reg, rm: &Arm64Reg) -> Self {
        DataProcessingRegister {
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
}

impl From<DataProcessingRegister> for u32 {
    /// Convert a data processing instruction into a 32-bit value.
    fn from(inst: DataProcessingRegister) -> Self {
        // Add/subtract (shifted register)
        // +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
        // | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
        // | sf op  S  0    1  0  1  1   shift  0 rm..............   imm6............... rn.............. rd.............. |
        // +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
        0
        | (inst.sf as u32).wrapping_shl(31)
        | (inst.op as u32).wrapping_shl(30)
        | (inst.s as u32).wrapping_shl(29)
        | (Family::DataProcessingRegister as u32).wrapping_shl(25)
        | (0b1 << 24)
        | (inst.shift as u32).wrapping_shl(22)
        | (inst.rm as u32).wrapping_shl(16)
        | (inst.imm6 as u32).wrapping_shl(10)
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
    use super::super::super::opnd::*;

    #[test]
    fn test_add_shifted_register() {
        let inst = DataProcessingRegister::add(&X0_REG, &X1_REG, &X2_REG);
        let result: u32 = inst.into();
        assert_eq!(0x8b020020, result);
    }

    #[test]
    fn test_sub_shifted_register() {
        let inst = DataProcessingRegister::sub(&X0_REG, &X1_REG, &X2_REG);
        let result: u32 = inst.into();
        assert_eq!(0xcb020020, result);
    }
}
