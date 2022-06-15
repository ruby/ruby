/// This operand represents a signed immediate value.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Arm64Imm
{
    // Size in bits
    pub num_bits: u8,

    // The value of the immediate
    pub value: i64
}

impl Arm64Imm {
    pub fn new(value: i64) -> Self {
        Arm64Imm { num_bits: Self::calculate_size(value), value }
    }

    /// Compute the number of bits needed to encode a signed value
    fn calculate_size(imm: i64) -> u8
    {
        // Compute the smallest size this immediate fits in
        if imm >= i8::MIN.into() && imm <= i8::MAX.into() {
            return 8;
        }
        if imm >= i16::MIN.into() && imm <= i16::MAX.into() {
            return 16;
        }
        if imm >= i32::MIN.into() && imm <= i32::MAX.into() {
            return 32;
        }

        return 64;
    }
}

/// This operand represents an unsigned immediate value.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Arm64UImm
{
    // Size in bits
    pub num_bits: u8,

    // The value of the immediate
    pub value: u64
}

impl Arm64UImm {
    pub fn new(value: u64) -> Self {
        Arm64UImm { num_bits: Self::calculate_size(value), value }
    }

    /// Compute the number of bits needed to encode an unsigned value
    fn calculate_size(imm: u64) -> u8
    {
        // Compute the smallest size this immediate fits in
        if imm <= u8::MAX.into() {
            return 8;
        }
        if imm <= u16::MAX.into() {
            return 16;
        }
        if imm <= u32::MAX.into() {
            return 32;
        }

        return 64;
    }
}

/// This operand represents a register.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Arm64Reg
{
    // Size in bits
    pub num_bits: u8,

    // Register index number
    pub reg_no: u8,
}

#[derive(Clone, Copy, Debug)]
pub enum Arm64Opnd
{
    // Dummy operand
    None,

    // Immediate value
    Imm(Arm64Imm),

    // Unsigned immediate
    UImm(Arm64UImm),

    // Register
    Reg(Arm64Reg),
}

impl Arm64Opnd {
    /// Create a new immediate value operand.
    pub fn new_imm(value: i64) -> Self {
        Arm64Opnd::Imm(Arm64Imm::new(value))
    }

    /// Create a new unsigned immediate value operand.
    pub fn new_uimm(value: u64) -> Self {
        Arm64Opnd::UImm(Arm64UImm::new(value))
    }

    /// Convenience function to check if this operand is a register.
    pub fn is_reg(&self) -> bool {
        match self {
            Arm64Opnd::Reg(_) => true,
            _ => false
        }
    }
}

pub const X0_REG: Arm64Reg = Arm64Reg { num_bits: 64, reg_no: 0 };
pub const X1_REG: Arm64Reg = Arm64Reg { num_bits: 64, reg_no: 1 };
pub const X2_REG: Arm64Reg = Arm64Reg { num_bits: 64, reg_no: 2 };
pub const X3_REG: Arm64Reg = Arm64Reg { num_bits: 64, reg_no: 3 };

pub const X12_REG: Arm64Reg = Arm64Reg { num_bits: 64, reg_no: 12 };
pub const X13_REG: Arm64Reg = Arm64Reg { num_bits: 64, reg_no: 13 };

// 64-bit registers
pub const X0: Arm64Opnd = Arm64Opnd::Reg(X0_REG);
pub const X1: Arm64Opnd = Arm64Opnd::Reg(X1_REG);
pub const X2: Arm64Opnd = Arm64Opnd::Reg(X2_REG);
pub const X3: Arm64Opnd = Arm64Opnd::Reg(X3_REG);
pub const X4: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 4 });
pub const X5: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 5 });
pub const X6: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 6 });
pub const X7: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 7 });
pub const X8: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 8 });
pub const X9: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 9 });
pub const X10: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 10 });
pub const X11: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 11 });
pub const X12: Arm64Opnd = Arm64Opnd::Reg(X12_REG);
pub const X13: Arm64Opnd = Arm64Opnd::Reg(X13_REG);
pub const X14: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 14 });
pub const X15: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 15 });
pub const X16: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 16 });
pub const X17: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 17 });
pub const X18: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 18 });
pub const X19: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 19 });
pub const X20: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 20 });
pub const X21: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 21 });
pub const X22: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 22 });
pub const X23: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 23 });
pub const X24: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 24 });
pub const X25: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 25 });
pub const X26: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 26 });
pub const X27: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 27 });
pub const X28: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 28 });
pub const X29: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 29 });
pub const X30: Arm64Opnd = Arm64Opnd::Reg(Arm64Reg { num_bits: 64, reg_no: 30 });

// 32-bit registers
pub const W0: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 0 };
pub const W1: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 1 };
pub const W2: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 2 };
pub const W3: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 3 };
pub const W4: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 4 };
pub const W5: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 5 };
pub const W6: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 6 };
pub const W7: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 7 };
pub const W8: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 8 };
pub const W9: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 9 };
pub const W10: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 10 };
pub const W11: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 11 };
pub const W12: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 12 };
pub const W13: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 13 };
pub const W14: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 14 };
pub const W15: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 15 };
pub const W16: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 16 };
pub const W17: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 17 };
pub const W18: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 18 };
pub const W19: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 19 };
pub const W20: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 20 };
pub const W21: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 21 };
pub const W22: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 22 };
pub const W23: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 23 };
pub const W24: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 24 };
pub const W25: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 25 };
pub const W26: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 26 };
pub const W27: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 27 };
pub const W28: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 28 };
pub const W29: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 29 };
pub const W30: Arm64Reg = Arm64Reg { num_bits: 32, reg_no: 30 };

// C argument registers
pub const C_ARG_REGS: [Arm64Opnd; 4] = [X0, X1, X2, X3];
