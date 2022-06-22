use super::super::arg::Sf;

/// The operation to perform for this instruction.
enum Opc {
    /// Logical left shift
    LSL,

    /// Logical shift right
    LSR
}

/// The struct that represents an A64 unsigned bitfield move instruction that
/// can be encoded.
///
/// LSL (immediate)
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |     1  0  1    0  0  1  1    0                                                                                |
/// | sf                             N  immr...............   imms............... rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct ShiftImm {
    /// The register number of the destination register.
    rd: u8,

    /// The register number of the first operand register.
    rn: u8,

    /// The immediate value to shift by.
    shift: u8,

    /// The opcode for this instruction.
    opc: Opc,

    /// Whether or not this instruction is operating on 64-bit operands.
    sf: Sf
}

impl ShiftImm {
    /// LSL (immediate)
    /// https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/LSL--immediate---Logical-Shift-Left--immediate---an-alias-of-UBFM-?lang=en
    pub fn lsl(rd: u8, rn: u8, shift: u8, num_bits: u8) -> Self {
        ShiftImm { rd, rn, shift, opc: Opc::LSL, sf: num_bits.into() }
    }

    /// LSR (immediate)
    /// https://developer.arm.com/documentation/ddi0602/2021-12/Base-Instructions/LSR--immediate---Logical-Shift-Right--immediate---an-alias-of-UBFM-?lang=en
    pub fn lsr(rd: u8, rn: u8, shift: u8, num_bits: u8) -> Self {
        ShiftImm { rd, rn, shift, opc: Opc::LSR, sf: num_bits.into() }
    }

    /// Returns a triplet of (n, immr, imms) encoded in u32s for this
    /// instruction. This mirrors how they will be encoded in the actual bits.
    fn bitmask(&self) -> (u32, u32, u32) {
        match self.opc {
            // The key insight is a little buried in the docs, but effectively:
            // LSL <Wd>, <Wn>, #<shift> == UBFM <Wd>, <Wn>, #(-<shift> MOD 32), #(31-<shift>)
            // LSL <Xd>, <Xn>, #<shift> == UBFM <Xd>, <Xn>, #(-<shift> MOD 64), #(63-<shift>)
            Opc::LSL => {
                let shift = -(self.shift as i16);

                match self.sf {
                    Sf::Sf32 => (
                        0,
                        (shift.rem_euclid(32) & 0x3f) as u32,
                        ((31 - self.shift) & 0x3f) as u32
                    ),
                    Sf::Sf64 => (
                        1,
                        (shift.rem_euclid(64) & 0x3f) as u32,
                        ((63 - self.shift) & 0x3f) as u32
                    )
                }
            },
            // Similar to LSL:
            // LSR <Wd>, <Wn>, #<shift> == UBFM <Wd>, <Wn>, #<shift>, #31
            // LSR <Xd>, <Xn>, #<shift> == UBFM <Xd>, <Xn>, #<shift>, #63
            Opc::LSR => {
                match self.sf {
                    Sf::Sf32 => (0, (self.shift & 0x3f) as u32, 31),
                    Sf::Sf64 => (1, (self.shift & 0x3f) as u32, 63)
                }
            }
        }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Immediate?lang=en#bitfield
const FAMILY: u32 = 0b10011;

impl From<ShiftImm> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: ShiftImm) -> Self {
        let (n, immr, imms) = inst.bitmask();

        0
        | ((inst.sf as u32) << 31)
        | (1 << 30)
        | (FAMILY << 24)
        | (n << 22)
        | (immr << 16)
        | (imms << 10)
        | ((inst.rn as u32) << 5)
        | inst.rd as u32
    }
}

impl From<ShiftImm> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: ShiftImm) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lsl_32() {
        let inst = ShiftImm::lsl(0, 1, 7, 32);
        let result: u32 = inst.into();
        assert_eq!(0x53196020, result);
    }

    #[test]
    fn test_lsl_64() {
        let inst = ShiftImm::lsl(0, 1, 7, 64);
        let result: u32 = inst.into();
        assert_eq!(0xd379e020, result);
    }

    #[test]
    fn test_lsr_32() {
        let inst = ShiftImm::lsr(0, 1, 7, 32);
        let result: u32 = inst.into();
        assert_eq!(0x53077c20, result);
    }

    #[test]
    fn test_lsr_64() {
        let inst = ShiftImm::lsr(0, 1, 7, 64);
        let result: u32 = inst.into();
        assert_eq!(0xd347fc20, result);
    }
}
