use super::super::arg::Sf;

/// The type of shift to perform on the second operand register.
enum Shift {
    LSL = 0b00, // logical shift left (unsigned)
    LSR = 0b01, // logical shift right (unsigned)
    ASR = 0b10, // arithmetic shift right (signed)
    ROR = 0b11  // rotate right (unsigned)
}

// Which operation to perform.
enum Opc {
    /// The AND operation.
    And = 0b00,

    /// The ANDS operation.
    Ands = 0b11
}

/// The struct that represents an A64 logical register instruction that can be
/// encoded.
///
/// AND/ANDS (shifted register)
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |           0    1  0  1  0          0                                                                          |
/// | sf opc..                    shift    rm..............   imm6............... rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct LogicalReg {
    /// The register number of the destination register.
    rd: u8,

    /// The register number of the first operand register.
    rn: u8,

    /// The amount to shift the second operand register.
    imm6: u8,

    /// The register number of the second operand register.
    rm: u8,

    /// The type of shift to perform on the second operand register.
    shift: Shift,

    /// The opcode for this instruction.
    opc: Opc,

    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf
}

impl LogicalReg {
    /// AND (shifted register)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/AND--shifted-register---Bitwise-AND--shifted-register--?lang=en
    pub fn and(rd: u8, rn: u8, rm: u8, num_bits: u8) -> Self {
        Self { rd, rn, imm6: 0, rm, shift: Shift::LSL, opc: Opc::And, sf: num_bits.into() }
    }

    /// ANDS (shifted register)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ANDS--shifted-register---Bitwise-AND--shifted-register---setting-flags-?lang=en
    pub fn ands(rd: u8, rn: u8, rm: u8, num_bits: u8) -> Self {
        Self { rd, rn, imm6: 0, rm, shift: Shift::LSL, opc: Opc::Ands, sf: num_bits.into() }
    }

    /// TST (shifted register)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/TST--shifted-register---Test--shifted-register---an-alias-of-ANDS--shifted-register--?lang=en
    pub fn tst(rn: u8, rm: u8, num_bits: u8) -> Self {
        Self { rd: 31, rn, imm6: 0, rm, shift: Shift::LSL, opc: Opc::Ands, sf: num_bits.into() }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Register?lang=en
const FAMILY: u32 = 0b0101;

impl From<LogicalReg> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: LogicalReg) -> Self {
        let imm6 = (inst.imm6 as u32) & ((1 << 6) - 1);

        0
        | ((inst.sf as u32) << 31)
        | ((inst.opc as u32) << 29)
        | (FAMILY << 25)
        | ((inst.shift as u32) << 22)
        | ((inst.rm as u32) << 16)
        | (imm6 << 10)
        | ((inst.rn as u32) << 5)
        | inst.rd as u32
    }
}

impl From<LogicalReg> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: LogicalReg) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_and() {
        let inst = LogicalReg::and(0, 1, 2, 64);
        let result: u32 = inst.into();
        assert_eq!(0x8a020020, result);
    }

    #[test]
    fn test_ands() {
        let inst = LogicalReg::ands(0, 1, 2, 64);
        let result: u32 = inst.into();
        assert_eq!(0xea020020, result);
    }

    #[test]
    fn test_tst() {
        let inst = LogicalReg::tst(0, 1, 64);
        let result: u32 = inst.into();
        assert_eq!(0xea01001f, result);
    }
}
