/// Which operation to perform for the PC-relative instruction.
enum Op {
    /// Form a PC-relative address.
    ADR = 0,

    /// Form a PC-relative address to a 4KB page.
    ADRP = 1
}

/// The struct that represents an A64 PC-relative address instruction that can
/// be encoded.
///
/// ADR
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |           1    0  0  0  0                                                                                     |
/// | op immlo                    immhi........................................................... rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct PCRelative {
    /// The number for the general-purpose register to load the address into.
    rd: u8,

    /// The number of bytes to add to the PC to form the address.
    imm: i32,

    /// Which operation to perform for this instruction.
    op: Op
}

impl PCRelative {
    /// ADR
    /// <https://developer.arm.com/documentation/ddi0602/2022-03/Base-Instructions/ADR--Form-PC-relative-address->
    pub fn adr(rd: u8, imm: i32) -> Self {
        Self { rd, imm, op: Op::ADR }
    }

    /// ADRP
    /// <https://developer.arm.com/documentation/ddi0602/2022-03/Base-Instructions/ADRP--Form-PC-relative-address-to-4KB-page->
    pub fn adrp(rd: u8, imm: i32) -> Self {
        Self { rd, imm: imm >> 12, op: Op::ADRP }
    }
}

/// <https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Immediate?lang=en>
const FAMILY: u32 = 0b1000;

impl From<PCRelative> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: PCRelative) -> Self {
        let immlo = (inst.imm & 0b11) as u32;
        let mut immhi = ((inst.imm >> 2) & ((1 << 18) - 1)) as u32;

        // Toggle the sign bit if necessary.
        if inst.imm < 0 {
            immhi |= 1 << 18;
        }

        0
        | ((inst.op as u32) << 31)
        | (immlo << 29)
        | (FAMILY << 25)
        | (immhi << 5)
        | inst.rd as u32
    }
}

impl From<PCRelative> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: PCRelative) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_adr_positive() {
        let inst = PCRelative::adr(0, 5);
        let result: u32 = inst.into();
        assert_eq!(0x30000020, result);
    }

    #[test]
    fn test_adr_negative() {
        let inst = PCRelative::adr(0, -5);
        let result: u32 = inst.into();
        assert_eq!(0x70ffffc0, result);
    }

    #[test]
    fn test_adrp_positive() {
        let inst = PCRelative::adrp(0, 0x4000);
        let result: u32 = inst.into();
        assert_eq!(0x90000020, result);
    }

    #[test]
    fn test_adrp_negative() {
        let inst = PCRelative::adrp(0, -0x4000);
        let result: u32 = inst.into();
        assert_eq!(0x90ffffe0, result);
    }
}
