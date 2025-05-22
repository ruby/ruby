use super::super::arg::{BitmaskImmediate, Sf};

// Which operation to perform.
enum Opc {
    /// The AND operation.
    And = 0b00,

    /// The ORR operation.
    Orr = 0b01,

    /// The EOR operation.
    Eor = 0b10,

    /// The ANDS operation.
    Ands = 0b11
}

/// The struct that represents an A64 bitwise immediate instruction that can be
/// encoded.
///
/// AND/ORR/ANDS (immediate)
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |           1    0  0  1  0    0                                                                                |
/// | sf opc..                       N  immr...............   imms............... rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct LogicalImm {
    /// The register number of the destination register.
    rd: u8,

    /// The register number of the first operand register.
    rn: u8,

    /// The immediate value to test.
    imm: BitmaskImmediate,

    /// The opcode for this instruction.
    opc: Opc,

    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf
}

impl LogicalImm {
    /// AND (bitmask immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/AND--immediate---Bitwise-AND--immediate--?lang=en>
    pub fn and(rd: u8, rn: u8, imm: BitmaskImmediate, num_bits: u8) -> Self {
        Self { rd, rn, imm, opc: Opc::And, sf: num_bits.into() }
    }

    /// ANDS (bitmask immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/ANDS--immediate---Bitwise-AND--immediate---setting-flags-?lang=en>
    pub fn ands(rd: u8, rn: u8, imm: BitmaskImmediate, num_bits: u8) -> Self {
        Self { rd, rn, imm, opc: Opc::Ands, sf: num_bits.into() }
    }

    /// EOR (bitmask immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/EOR--immediate---Bitwise-Exclusive-OR--immediate-->
    pub fn eor(rd: u8, rn: u8, imm: BitmaskImmediate, num_bits: u8) -> Self {
        Self { rd, rn, imm, opc: Opc::Eor, sf: num_bits.into() }
    }

    /// MOV (bitmask immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/MOV--bitmask-immediate---Move--bitmask-immediate---an-alias-of-ORR--immediate--?lang=en>
    pub fn mov(rd: u8, imm: BitmaskImmediate, num_bits: u8) -> Self {
        Self { rd, rn: 0b11111, imm, opc: Opc::Orr, sf: num_bits.into() }
    }

    /// ORR (bitmask immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/ORR--immediate---Bitwise-OR--immediate-->
    pub fn orr(rd: u8, rn: u8, imm: BitmaskImmediate, num_bits: u8) -> Self {
        Self { rd, rn, imm, opc: Opc::Orr, sf: num_bits.into() }
    }

    /// TST (bitmask immediate)
    /// <https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/TST--immediate---Test-bits--immediate---an-alias-of-ANDS--immediate--?lang=en>
    pub fn tst(rn: u8, imm: BitmaskImmediate, num_bits: u8) -> Self {
        Self::ands(31, rn, imm, num_bits)
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Immediate?lang=en#log_imm>
const FAMILY: u32 = 0b1001;

impl From<LogicalImm> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: LogicalImm) -> Self {
        let imm: u32 = inst.imm.encode();

        0
        | ((inst.sf as u32) << 31)
        | ((inst.opc as u32) << 29)
        | (FAMILY << 25)
        | (imm << 10)
        | ((inst.rn as u32) << 5)
        | inst.rd as u32
    }
}

impl From<LogicalImm> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: LogicalImm) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_and() {
        let inst = LogicalImm::and(0, 1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0x92400820, result);
    }

    #[test]
    fn test_ands() {
        let inst = LogicalImm::ands(0, 1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xf2400820, result);
    }

    #[test]
    fn test_eor() {
        let inst = LogicalImm::eor(0, 1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xd2400820, result);
    }

    #[test]
    fn test_mov() {
        let inst = LogicalImm::mov(0, 0x5555555555555555.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xb200f3e0, result);
    }

    #[test]
    fn test_orr() {
        let inst = LogicalImm::orr(0, 1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xb2400820, result);
    }

    #[test]
    fn test_tst() {
        let inst = LogicalImm::tst(1, 7.try_into().unwrap(), 64);
        let result: u32 = inst.into();
        assert_eq!(0xf240083f, result);
    }
}
