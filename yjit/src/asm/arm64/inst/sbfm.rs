use super::super::arg::{Sf, truncate_uimm};

/// The struct that represents an A64 signed bitfield move instruction that can
/// be encoded.
///
/// SBFM
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |     0  0  1    0  0  1  1    0                                                                                |
/// | sf                             N  immr...............   imms............... rn.............. rd.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct SBFM {
    /// The number for the general-purpose register to load the value into.
    rd: u8,

    /// The number for the general-purpose register to copy from.
    rn: u8,

    /// The leftmost bit number to be moved from the source.
    imms: u8,

    // The right rotate amount.
    immr: u8,

    /// Whether or not this is a 64-bit operation.
    n: bool,

    /// The size of this operation.
    sf: Sf
}

impl SBFM {
    /// ASR
    /// https://developer.arm.com/documentation/ddi0596/2020-12/Base-Instructions/ASR--immediate---Arithmetic-Shift-Right--immediate---an-alias-of-SBFM-?lang=en
    pub fn asr(rd: u8, rn: u8, shift: u8, num_bits: u8) -> Self {
        let (imms, n) = if num_bits == 64 {
            (0b111111, true)
        } else {
            (0b011111, false)
        };

        Self { rd, rn, immr: shift, imms, n, sf: num_bits.into() }
    }

    /// SXTW
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/SXTW--Sign-Extend-Word--an-alias-of-SBFM-?lang=en
    pub fn sxtw(rd: u8, rn: u8) -> Self {
        Self { rd, rn, immr: 0, imms: 31, n: true, sf: Sf::Sf64 }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Data-Processing----Immediate?lang=en#bitfield
const FAMILY: u32 = 0b1001;

impl From<SBFM> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: SBFM) -> Self {
        0
        | ((inst.sf as u32) << 31)
        | (FAMILY << 25)
        | (1 << 24)
        | ((inst.n as u32) << 22)
        | (truncate_uimm::<_, 6>(inst.immr) << 16)
        | (truncate_uimm::<_, 6>(inst.imms) << 10)
        | ((inst.rn as u32) << 5)
        | inst.rd as u32
    }
}

impl From<SBFM> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: SBFM) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_asr_32_bits() {
        let inst = SBFM::asr(0, 1, 2, 32);
        let result: u32 = inst.into();
        assert_eq!(0x13027c20, result);
    }

    #[test]
    fn test_asr_64_bits() {
        let inst = SBFM::asr(10, 11, 5, 64);
        let result: u32 = inst.into();
        assert_eq!(0x9345fd6a, result);
    }

    #[test]
    fn test_sxtw() {
        let inst = SBFM::sxtw(0, 1);
        let result: u32 = inst.into();
        assert_eq!(0x93407c20, result);
    }
}
