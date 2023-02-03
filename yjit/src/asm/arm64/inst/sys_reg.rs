use super::super::arg::SystemRegister;

/// Which operation to perform (loading or storing the system register value).
enum L {
    /// Store the value of a general-purpose register in a system register.
    MSR = 0,

    /// Store the value of a system register in a general-purpose register.
    MRS = 1
}

/// The struct that represents an A64 system register instruction that can be
/// encoded.
///
/// MSR/MRS (register)
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
/// | 31 30 29 28 | 27 26 25 24 | 23 22 21 20 | 19 18 17 16 | 15 14 13 12 | 11 10 09 08 | 07 06 05 04 | 03 02 01 00 |
/// |  1  1  0  1    0  1  0  1    0  0     1                                                                       |
/// |                                   L       o0 op1.....   CRn........   CRm........   op2..... rt.............. |
/// +-------------+-------------+-------------+-------------+-------------+-------------+-------------+-------------+
///
pub struct SysReg {
    /// The register to load the system register value into.
    rt: u8,

    /// Which system register to load or store.
    systemreg: SystemRegister,

    /// Which operation to perform (loading or storing the system register value).
    l: L
}

impl SysReg {
    /// MRS (register)
    /// https://developer.arm.com/documentation/ddi0602/2022-03/Base-Instructions/MRS--Move-System-Register-?lang=en
    pub fn mrs(rt: u8, systemreg: SystemRegister) -> Self {
        SysReg { rt, systemreg, l: L::MRS }
    }

    /// MSR (register)
    /// https://developer.arm.com/documentation/ddi0596/2021-12/Base-Instructions/MSR--register---Move-general-purpose-register-to-System-Register-?lang=en
    pub fn msr(systemreg: SystemRegister, rt: u8) -> Self {
        SysReg { rt, systemreg, l: L::MSR }
    }
}

/// https://developer.arm.com/documentation/ddi0602/2022-03/Index-by-Encoding/Branches--Exception-Generating-and-System-instructions?lang=en#systemmove
const FAMILY: u32 = 0b110101010001;

impl From<SysReg> for u32 {
    /// Convert an instruction into a 32-bit value.
    fn from(inst: SysReg) -> Self {
        0
        | (FAMILY << 20)
        | ((inst.l as u32) << 21)
        | ((inst.systemreg as u32) << 5)
        | inst.rt as u32
    }
}

impl From<SysReg> for [u8; 4] {
    /// Convert an instruction into a 4 byte array.
    fn from(inst: SysReg) -> [u8; 4] {
        let result: u32 = inst.into();
        result.to_le_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mrs() {
        let inst = SysReg::mrs(0, SystemRegister::NZCV);
        let result: u32 = inst.into();
        assert_eq!(0xd53b4200, result);
    }

    #[test]
    fn test_msr() {
        let inst = SysReg::msr(SystemRegister::NZCV, 0);
        let result: u32 = inst.into();
        assert_eq!(0xd51b4200, result);
    }
}
