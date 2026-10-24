#![allow(dead_code)] // For instructions we don't currently generate

use crate::asm::*;

// Import the assembler tests module
mod tests;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86Imm
{
    // Size in bits
    pub num_bits: u8,

    // The value of the immediate
    pub value: i64
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86UImm
{
    // Size in bits
    pub num_bits: u8,

    // The value of the immediate
    pub value: u64
}

#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum RegType
{
    GP,
    //FP,
    //XMM,
    IP,
}

#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct X86Reg
{
    // Size in bits
    pub num_bits: u8,

    // Register type
    pub reg_type: RegType,

    // Register index number
    pub reg_no: u8,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct X86Mem
{
    // Size in bits
    pub num_bits: u8,

    /// Base register number
    pub base_reg_no: u8,

    /// Index register number
    pub idx_reg_no: Option<u8>,

    /// SIB scale exponent value (power of two, two bits)
    pub scale_exp: u8,

    /// Constant displacement from the base, not scaled
    pub disp: i32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum X86Opnd
{
    // Dummy operand
    None,

    // Immediate value
    Imm(X86Imm),

    // Unsigned immediate
    UImm(X86UImm),

    // General-purpose register
    Reg(X86Reg),

    // Memory location
    Mem(X86Mem),

    // IP-relative memory location
    IPRel(i32)
}

impl X86Reg {
    pub fn with_num_bits(&self, num_bits: u8) -> Self {
        assert!(
            num_bits == 8 ||
            num_bits == 16 ||
            num_bits == 32 ||
            num_bits == 64
        );
        Self {
            num_bits,
            reg_type: self.reg_type,
            reg_no: self.reg_no
        }
    }

    pub fn rex_needed(&self) -> bool {
        self.reg_no > 7 || self.num_bits == 8 && self.reg_no >= 4
    }
}

impl X86Opnd {
    fn rex_needed(&self) -> bool {
        match self {
            X86Opnd::None => false,
            X86Opnd::Imm(_) => false,
            X86Opnd::UImm(_) => false,
            X86Opnd::Reg(reg) => reg.rex_needed(),
            X86Opnd::Mem(mem) => mem.base_reg_no > 7 || (mem.idx_reg_no.unwrap_or(0) > 7),
            X86Opnd::IPRel(_) => false
        }
    }

    // Check if an SIB byte is needed to encode this operand
    fn sib_needed(&self) -> bool {
        match self {
            X86Opnd::Mem(mem) => {
                mem.idx_reg_no.is_some() ||
                mem.base_reg_no == RSP_REG_NO ||
                mem.base_reg_no == R12_REG_NO
            },
            _ => false
        }
    }

    fn disp_size(&self) -> u32 {
        match self {
            X86Opnd::IPRel(_) => 32,
            X86Opnd::Mem(mem) => {
                if mem.disp != 0 {
                    // Compute the required displacement size
                    let num_bits = imm_num_bits(mem.disp.into());
                    if num_bits > 32 {
                        panic!("displacement does not fit in 32 bits");
                    }

                    // x86 can only encode 8-bit and 32-bit displacements
                    if num_bits == 16 { 32 } else { 8 }
                } else if mem.base_reg_no == RBP_REG_NO || mem.base_reg_no == R13_REG_NO {
                    // If EBP or RBP or R13 is used as the base, displacement must be encoded
                    8
                } else {
                    0
                }
            },
            _ => 0
        }
    }

    pub fn num_bits(&self) -> u8 {
        match self {
            X86Opnd::Reg(reg) => reg.num_bits,
            X86Opnd::Imm(imm) => imm.num_bits,
            X86Opnd::UImm(uimm) => uimm.num_bits,
            X86Opnd::Mem(mem) => mem.num_bits,
            _ => unreachable!()
        }
    }

    pub fn is_some(&self) -> bool {
        !matches!(self, X86Opnd::None)
    }

}

// Instruction pointer
pub const RIP: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 64, reg_type: RegType::IP, reg_no: 5 });

// 64-bit GP registers
const RAX_REG_NO: u8 = 0;
const RSP_REG_NO: u8 = 4;
const RBP_REG_NO: u8 = 5;
const R12_REG_NO: u8 = 12;
const R13_REG_NO: u8 = 13;

pub const RAX_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: RAX_REG_NO };
pub const RCX_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 1 };
pub const RDX_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 2 };
pub const RBX_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 3 };
pub const RSP_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: RSP_REG_NO };
pub const RBP_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: RBP_REG_NO };
pub const RSI_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 6 };
pub const RDI_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 7 };
pub const R8_REG:  X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 8 };
pub const R9_REG:  X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 9 };
pub const R10_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 10 };
pub const R11_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 11 };
pub const R12_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: R12_REG_NO };
pub const R13_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: R13_REG_NO };
pub const R14_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 14 };
pub const R15_REG: X86Reg = X86Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 15 };

pub const RAX: X86Opnd  = X86Opnd::Reg(RAX_REG);
pub const RCX: X86Opnd  = X86Opnd::Reg(RCX_REG);
pub const RDX: X86Opnd  = X86Opnd::Reg(RDX_REG);
pub const RBX: X86Opnd  = X86Opnd::Reg(RBX_REG);
pub const RSP: X86Opnd  = X86Opnd::Reg(RSP_REG);
pub const RBP: X86Opnd  = X86Opnd::Reg(RBP_REG);
pub const RSI: X86Opnd  = X86Opnd::Reg(RSI_REG);
pub const RDI: X86Opnd  = X86Opnd::Reg(RDI_REG);
pub const R8:  X86Opnd  = X86Opnd::Reg(R8_REG);
pub const R9:  X86Opnd  = X86Opnd::Reg(R9_REG);
pub const R10: X86Opnd  = X86Opnd::Reg(R10_REG);
pub const R11: X86Opnd  = X86Opnd::Reg(R11_REG);
pub const R12: X86Opnd  = X86Opnd::Reg(R12_REG);
pub const R13: X86Opnd  = X86Opnd::Reg(R13_REG);
pub const R14: X86Opnd  = X86Opnd::Reg(R14_REG);
pub const R15: X86Opnd  = X86Opnd::Reg(R15_REG);

// 32-bit GP registers
pub const EAX: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 0 });
pub const ECX: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 1 });
pub const EDX: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 2 });
pub const EBX: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 3 });
pub const ESP: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 4 });
pub const EBP: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 5 });
pub const ESI: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 6 });
pub const EDI: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 7 });
pub const R8D: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 8 });
pub const R9D: X86Opnd  = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 9 });
pub const R10D: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 10 });
pub const R11D: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 11 });
pub const R12D: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 12 });
pub const R13D: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 13 });
pub const R14D: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 14 });
pub const R15D: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 32, reg_type: RegType::GP, reg_no: 15 });

// 16-bit GP registers
pub const AX:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 0 });
pub const CX:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 1 });
pub const DX:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 2 });
pub const BX:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 3 });
//pub const SP:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 4 });
pub const BP:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 5 });
pub const SI:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 6 });
pub const DI:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 7 });
pub const R8W:  X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 8 });
pub const R9W:  X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 9 });
pub const R10W: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 10 });
pub const R11W: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 11 });
pub const R12W: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 12 });
pub const R13W: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 13 });
pub const R14W: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 14 });
pub const R15W: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 16, reg_type: RegType::GP, reg_no: 15 });

// 8-bit GP registers
pub const AL:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 0 });
pub const CL:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 1 });
pub const DL:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 2 });
pub const BL:   X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 3 });
pub const SPL:  X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 4 });
pub const BPL:  X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 5 });
pub const SIL:  X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 6 });
pub const DIL:  X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 7 });
pub const R8B:  X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 8 });
pub const R9B:  X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 9 });
pub const R10B: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 10 });
pub const R11B: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 11 });
pub const R12B: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 12 });
pub const R13B: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 13 });
pub const R14B: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 14 });
pub const R15B: X86Opnd = X86Opnd::Reg(X86Reg { num_bits: 8, reg_type: RegType::GP, reg_no: 15 });

//===========================================================================

/// Shorthand for memory operand with base register and displacement
pub fn mem_opnd(num_bits: u8, base_reg: X86Opnd, disp: i32) -> X86Opnd
{
    let base_reg = match base_reg {
        X86Opnd::Reg(reg) => reg,
        _ => unreachable!()
    };

    if base_reg.reg_type == RegType::IP {
        X86Opnd::IPRel(disp)
    } else {
        X86Opnd::Mem(
            X86Mem {
                num_bits,
                base_reg_no: base_reg.reg_no,
                idx_reg_no: None,
                scale_exp: 0,
                disp,
            }
        )
    }
}

/// Memory operand with SIB (Scale Index Base) indexing
pub fn mem_opnd_sib(num_bits: u8, base_opnd: X86Opnd, index_opnd: X86Opnd, scale: i32, disp: i32) -> X86Opnd {
    if let (X86Opnd::Reg(base_reg), X86Opnd::Reg(index_reg)) = (base_opnd, index_opnd) {
        let scale_exp: u8 = match scale {
            8 => 3,
            4 => 2,
            2 => 1,
            1 => 0,
            _ => unreachable!()
        };

        X86Opnd::Mem(X86Mem {
            num_bits,
            base_reg_no: base_reg.reg_no,
            idx_reg_no: Some(index_reg.reg_no),
            scale_exp,
            disp
        })
    } else {
        unreachable!()
    }
}

pub fn imm_opnd(value: i64) -> X86Opnd
{
    X86Opnd::Imm(X86Imm { num_bits: imm_num_bits(value), value })
}

pub fn uimm_opnd(value: u64) -> X86Opnd
{
    X86Opnd::UImm(X86UImm { num_bits: uimm_num_bits(value), value })
}

pub fn const_ptr_opnd(ptr: *const u8) -> X86Opnd
{
    uimm_opnd(ptr as u64)
}

/// Write the REX byte
fn write_rex(writer: &mut CodeWriter<'_>, w_flag: bool, reg_no: u8, idx_reg_no: u8, rm_reg_no: u8) {
    // 0 1 0 0 w r x b
    // w - 64-bit operand size flag
    // r - MODRM.reg extension
    // x - SIB.index extension
    // b - MODRM.rm or SIB.base extension
    let w: u8 = if w_flag { 1 } else { 0 };
    let r: u8 = if (reg_no & 8) > 0 { 1 } else { 0 };
    let x: u8 = if (idx_reg_no & 8) > 0 { 1 } else { 0 };
    let b: u8 = if (rm_reg_no & 8) > 0 { 1 } else { 0 };

    // Encode and write the REX byte
    writer.write_byte(0x40 + (w << 3) + (r << 2) + (x << 1) + (b));
}

/// Write an opcode byte with an embedded register operand
fn write_opcode(writer: &mut CodeWriter<'_>, opcode: u8, reg: X86Reg) {
    let op_byte: u8 = opcode | (reg.reg_no & 7);
    writer.write_byte(op_byte);
}

/// Encode an RM instruction
fn write_rm(writer: &mut CodeWriter<'_>, sz_pref: bool, rex_w: bool, r_opnd: X86Opnd, rm_opnd: X86Opnd, op_ext: Option<u8>, bytes: &[u8]) {
    let op_len = bytes.len();
    assert!(op_len > 0 && op_len <= 3);
    assert!(matches!(r_opnd, X86Opnd::Reg(_) | X86Opnd::None), "Can only encode an RM instruction with a register or a none");

    // Flag to indicate the REX prefix is needed
    let need_rex = rex_w || r_opnd.rex_needed() || rm_opnd.rex_needed();

    // Flag to indicate SIB byte is needed
    let need_sib = r_opnd.sib_needed() || rm_opnd.sib_needed();

    // Add the operand-size prefix, if needed
    if sz_pref {
        writer.write_byte(0x66);
    }

    // Add the REX prefix, if needed
    if need_rex {
        // 0 1 0 0 w r x b
        // w - 64-bit operand size flag
        // r - MODRM.reg extension
        // x - SIB.index extension
        // b - MODRM.rm or SIB.base extension

        let w = if rex_w { 1 } else { 0 };
        let r = match r_opnd {
            X86Opnd::None => 0,
            X86Opnd::Reg(reg) => if (reg.reg_no & 8) > 0 { 1 } else { 0 },
            _ => unreachable!()
        };

        let x = match (need_sib, rm_opnd) {
            (true, X86Opnd::Mem(mem)) => if (mem.idx_reg_no.unwrap_or(0) & 8) > 0 { 1 } else { 0 },
            _ => 0
        };

        let b = match rm_opnd {
            X86Opnd::Reg(reg) => if (reg.reg_no & 8) > 0 { 1 } else { 0 },
            X86Opnd::Mem(mem) => if (mem.base_reg_no & 8) > 0 { 1 } else { 0 },
            _ => 0
        };

        // Encode and write the REX byte
        let rex_byte: u8 = 0x40 + (w << 3) + (r << 2) + (x << 1) + (b);
        writer.write_byte(rex_byte);
    }

    // Write the opcode bytes to the code block
    for byte in bytes {
        writer.write_byte(*byte)
    }

    // MODRM.mod (2 bits)
    // MODRM.reg (3 bits)
    // MODRM.rm  (3 bits)

    assert!(
        !(op_ext.is_some() && r_opnd.is_some()),
        "opcode extension and register operand present"
    );

    // Encode the mod field
    let rm_mod = match rm_opnd {
        X86Opnd::Reg(_) => 3,
        X86Opnd::IPRel(_) => 0,
        X86Opnd::Mem(_mem) => {
            match rm_opnd.disp_size() {
                0 => 0,
                8 => 1,
                32 => 2,
                _ => unreachable!()
            }
        },
        _ => unreachable!()
    };

    // Encode the reg field
    let reg: u8;
    if let Some(val) = op_ext {
        reg = val;
    } else {
        reg = match r_opnd {
            X86Opnd::Reg(reg) => reg.reg_no & 7,
            _ => 0
        };
    }

    // Encode the rm field
    let rm = match rm_opnd {
        X86Opnd::Reg(reg) => reg.reg_no & 7,
        X86Opnd::Mem(mem) => if need_sib { 4 } else { mem.base_reg_no & 7 },
        X86Opnd::IPRel(_) => 0b101,
        _ => unreachable!()
    };

    // Encode and write the ModR/M byte
    let rm_byte: u8 = (rm_mod << 6) + (reg << 3) + (rm);
    writer.write_byte(rm_byte);

    // Add the SIB byte, if needed
    if need_sib {
        // SIB.scale (2 bits)
        // SIB.index (3 bits)
        // SIB.base  (3 bits)

        match rm_opnd {
            X86Opnd::Mem(mem) => {
                // Encode the scale value
                let scale = mem.scale_exp;

                // Encode the index value
                let index = mem.idx_reg_no.map(|no| no & 7).unwrap_or(4);

                // Encode the base register
                let base = mem.base_reg_no & 7;

                // Encode and write the SIB byte
                let sib_byte: u8 = (scale << 6) + (index << 3) + (base);
                writer.write_byte(sib_byte);
            },
            _ => panic!("Expected mem operand")
        }
    }

    // Add the displacement
    match rm_opnd {
        X86Opnd::Mem(mem) => {
            let disp_size = rm_opnd.disp_size();
            if disp_size > 0 {
                writer.write_int(mem.disp as u64, disp_size);
            }
        },
        X86Opnd::IPRel(rel) => {
            writer.write_int(rel as u64, 32);
        },
        _ => ()
    };
}

// Encode a mul-like single-operand RM instruction
fn write_rm_unary(writer: &mut CodeWriter<'_>, op_mem_reg_8: u8, op_mem_reg_pref: u8, op_ext: Option<u8>, opnd: X86Opnd) {
    assert!(matches!(opnd, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

    let opnd_size = opnd.num_bits();
    assert!(opnd_size == 8 || opnd_size == 16 || opnd_size == 32 || opnd_size == 64);

    if opnd_size == 8 {
        write_rm(writer, false, false, X86Opnd::None, opnd, op_ext, &[op_mem_reg_8]);
    } else {
        let sz_pref = opnd_size == 16;
        let rex_w = opnd_size == 64;
        write_rm(writer, sz_pref, rex_w, X86Opnd::None, opnd, op_ext, &[op_mem_reg_pref]);
    }
}

// Encode an add-like RM instruction with multiple possible encodings
fn write_rm_multi(writer: &mut CodeWriter<'_>, op_mem_reg8: u8, op_mem_reg_pref: u8, op_reg_mem8: u8, op_reg_mem_pref: u8, op_mem_imm8: u8, op_mem_imm_sml: u8, op_mem_imm_lrg: u8, op_ext_imm: Option<u8>, opnd0: X86Opnd, opnd1: X86Opnd) {
    assert!(matches!(opnd0, X86Opnd::Reg(_) | X86Opnd::Mem(_)), "unexpected opnd0: {opnd0:?}, {opnd1:?}");

    // Check the size of opnd0
    let opnd_size = opnd0.num_bits();
    assert!(opnd_size == 8 || opnd_size == 16 || opnd_size == 32 || opnd_size == 64);

    // Check the size of opnd1
    match opnd1 {
        X86Opnd::Reg(reg) => assert_eq!(reg.num_bits, opnd_size),
        X86Opnd::Mem(mem) => assert_eq!(mem.num_bits, opnd_size),
        X86Opnd::Imm(imm) => assert!(imm.num_bits <= opnd_size),
        X86Opnd::UImm(uimm) => assert!(uimm.num_bits <= opnd_size),
        _ => ()
    };

    let sz_pref = opnd_size == 16;
    let rex_w = opnd_size == 64;

    match (opnd0, opnd1) {
        // R/M + Reg
        (X86Opnd::Mem(_), X86Opnd::Reg(_)) | (X86Opnd::Reg(_), X86Opnd::Reg(_)) => {
            if opnd_size == 8 {
                write_rm(writer, false, false, opnd1, opnd0, None, &[op_mem_reg8]);
            } else {
                write_rm(writer, sz_pref, rex_w, opnd1, opnd0, None, &[op_mem_reg_pref]);
            }
        },
        // Reg + R/M/IPRel
        (X86Opnd::Reg(_), X86Opnd::Mem(_) | X86Opnd::IPRel(_)) => {
            if opnd_size == 8 {
                write_rm(writer, false, false, opnd0, opnd1, None, &[op_reg_mem8]);
            } else {
                write_rm(writer, sz_pref, rex_w, opnd0, opnd1, None, &[op_reg_mem_pref]);
            }
        },
        // R/M + Imm
        (_, X86Opnd::Imm(imm)) => {
            if imm.num_bits <= 8 {
                // 8-bit immediate

                if opnd_size == 8 {
                    write_rm(writer, false, false, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm8]);
                } else {
                    write_rm(writer, sz_pref, rex_w, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm_sml]);
                }

                writer.write_int(imm.value as u64, 8);
            } else if imm.num_bits <= 32 {
                // 32-bit immediate

                assert!(imm.num_bits <= opnd_size);
                write_rm(writer, sz_pref, rex_w, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm_lrg]);
                writer.write_int(imm.value as u64, if opnd_size > 32 { 32 } else { opnd_size.into() });
            } else {
                panic!("immediate value too large");
            }
        },
        // R/M + UImm
        (_, X86Opnd::UImm(uimm)) => {
            // If the size of left hand operand equals the number of bits
            // required to represent the right hand immediate, then we
            // don't care about sign extension when calculating the immediate
            let num_bits = if opnd0.num_bits() == uimm_num_bits(uimm.value) {
                uimm_num_bits(uimm.value)
            } else {
                imm_num_bits(uimm.value.try_into().unwrap())
            };

            if num_bits <= 8 {
                // 8-bit immediate

                if opnd_size == 8 {
                    write_rm(writer, false, false, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm8]);
                } else {
                    write_rm(writer, sz_pref, rex_w, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm_sml]);
                }

                writer.write_int(uimm.value, 8);
            } else if num_bits <= 32 {
                // 32-bit immediate

                assert!(num_bits <= opnd_size);
                write_rm(writer, sz_pref, rex_w, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm_lrg]);
                writer.write_int(uimm.value, if opnd_size > 32 { 32 } else { opnd_size.into() });
            } else {
                panic!("immediate value too large (num_bits={}, num={uimm:?})", num_bits);
            }
        },
        _ => panic!("unknown encoding combo: {opnd0:?} {opnd1:?}")
    };
}

// LOCK - lock prefix for atomic shared memory operations
pub fn write_lock_prefix(writer: &mut CodeWriter<'_>) {
    writer.write_byte(0xf0);
}

/// add - Integer addition
pub fn add(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        writer,
        0x00, // opMemReg8
        0x01, // opMemRegPref
        0x02, // opRegMem8
        0x03, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        Some(0x00), // opExtImm
        opnd0,
        opnd1
    );
}

/// and - Bitwise AND
pub fn and(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        writer,
        0x20, // opMemReg8
        0x21, // opMemRegPref
        0x22, // opRegMem8
        0x23, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        Some(0x04), // opExtImm
        opnd0,
        opnd1
    );
}

/// call - Call to a pointer with a 32-bit displacement offset
pub fn call_rel32(writer: &mut CodeWriter<'_>, rel32: i32) {
    // Write the opcode
    writer.write_byte(0xe8);

    // Write the relative 32-bit jump offset
    writer.write_bytes(&rel32.to_le_bytes());
}

/// call - Call a pointer, encode with a 32-bit offset if possible
pub fn call_ptr(writer: &mut CodeWriter<'_>, scratch_opnd: X86Opnd, dst_ptr: *const u8) {
    if let X86Opnd::Reg(_scratch_reg) = scratch_opnd {
        // TODO: implement a counter

        // Pointer to the end of this call instruction
        let end_ptr = writer.get_write_ptr().add_bytes(5);

        // Compute the jump offset
        let rel64: i64 = dst_ptr as i64 - end_ptr.raw_ptr(writer) as i64;

        // If the offset fits in 32-bit
        if rel64 >= i32::MIN.into() && rel64 <= i32::MAX.into() {
            call_rel32(writer, rel64.try_into().unwrap());
            return;
        }

        // Move the pointer into the scratch register and call
        mov(writer, scratch_opnd, const_ptr_opnd(dst_ptr));
        call(writer, scratch_opnd);
    } else {
        unreachable!();
    }
}

/// call - Call to label with 32-bit offset
pub fn call_label(writer: &mut CodeWriter<'_>, label: Label) {
    writer.label_ref(label, 5, |writer, src_addr, dst_addr| {
        writer.write_byte(0xE8);
        writer.write_int((dst_addr - src_addr) as u64, 32);
        Ok(())
    });
}

/// call - Indirect call with an R/M operand
pub fn call(writer: &mut CodeWriter<'_>, opnd: X86Opnd) {
    write_rm(writer, false, false, X86Opnd::None, opnd, Some(2), &[0xff]);
}

/// Encode a conditional move instruction
fn write_cmov(writer: &mut CodeWriter<'_>, opcode1: u8, dst: X86Opnd, src: X86Opnd) {
    if let X86Opnd::Reg(reg) = dst {
        match src {
            X86Opnd::Reg(_) => (),
            X86Opnd::Mem(_) => (),
            _ => unreachable!()
        };

        assert!(reg.num_bits >= 16);
        let sz_pref = reg.num_bits == 16;
        let rex_w = reg.num_bits == 64;

        write_rm(writer, sz_pref, rex_w, dst, src, None, &[0x0f, opcode1]);
    } else {
        unreachable!()
    }
}

// cmovcc - Conditional move
pub fn cmova(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x47, dst, src); }
pub fn cmovae(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x43, dst, src); }
pub fn cmovb(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x42, dst, src); }
pub fn cmovbe(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x46, dst, src); }
pub fn cmovc(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x42, dst, src); }
pub fn cmove(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x44, dst, src); }
pub fn cmovg(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4f, dst, src); }
pub fn cmovge(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4d, dst, src); }
pub fn cmovl(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4c, dst, src); }
pub fn cmovle(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4e, dst, src); }
pub fn cmovna(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x46, dst, src); }
pub fn cmovnae(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x42, dst, src); }
pub fn cmovnb(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x43, dst, src); }
pub fn cmovnbe(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x47, dst, src); }
pub fn cmovnc(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x43, dst, src); }
pub fn cmovne(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x45, dst, src); }
pub fn cmovng(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4e, dst, src); }
pub fn cmovnge(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4c, dst, src); }
pub fn cmovnl(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer,  0x4d, dst, src); }
pub fn cmovnle(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4f, dst, src); }
pub fn cmovno(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x41, dst, src); }
pub fn cmovnp(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4b, dst, src); }
pub fn cmovns(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x49, dst, src); }
pub fn cmovnz(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x45, dst, src); }
pub fn cmovo(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x40, dst, src); }
pub fn cmovp(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4a, dst, src); }
pub fn cmovpe(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4a, dst, src); }
pub fn cmovpo(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x4b, dst, src); }
pub fn cmovs(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x48, dst, src); }
pub fn cmovz(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) { write_cmov(writer, 0x44, dst, src); }

/// cmp - Compare and set flags
pub fn cmp(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        writer,
        0x38, // opMemReg8
        0x39, // opMemRegPref
        0x3A, // opRegMem8
        0x3B, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        Some(0x07), // opExtImm
        opnd0,
        opnd1
    );
}

/// cdq - Convert doubleword to quadword
pub fn cdq(writer: &mut CodeWriter<'_>) {
    writer.write_byte(0x99);
}

/// cqo - Convert quadword to octaword
pub fn cqo(writer: &mut CodeWriter<'_>) {
    writer.write_bytes(&[0x48, 0x99]);
}

/// imul - signed integer multiply
pub fn imul(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    assert!(opnd0.num_bits() == 64);
    assert!(opnd1.num_bits() == 64);
    assert!(matches!(opnd0, X86Opnd::Reg(_) | X86Opnd::Mem(_)));
    assert!(matches!(opnd1, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

    match (opnd0, opnd1) {
        (X86Opnd::Reg(_), X86Opnd::Reg(_) | X86Opnd::Mem(_)) => {
            //REX.W + 0F AF /rIMUL r64, r/m64
            // Quadword register := Quadword register * r/m64.
            write_rm(writer, false, true, opnd0, opnd1, None, &[0x0F, 0xAF]);
        }

        _ => unreachable!()
    }
}

/// Interrupt 3 - trap to debugger
pub fn int3(writer: &mut CodeWriter<'_>) {
    writer.write_byte(0xcc);
}

// Encode a conditional relative jump to a label
// Note: this always encodes a 32-bit offset
fn write_jcc<const OP: u8>(writer: &mut CodeWriter<'_>, label: Label) {
    writer.label_ref(label, 6, |writer, src_addr, dst_addr| {
        writer.write_byte(0x0F);
        writer.write_byte(OP);
        writer.write_int((dst_addr - src_addr) as u64, 32);
        Ok(())
    });
}

/// jcc - relative jumps to a label
pub fn ja_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x87>(writer, label); }
pub fn jae_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x83>(writer, label); }
pub fn jb_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x82>(writer, label); }
pub fn jbe_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x86>(writer, label); }
pub fn jc_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x82>(writer, label); }
pub fn je_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x84>(writer, label); }
pub fn jg_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8F>(writer, label); }
pub fn jge_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8D>(writer, label); }
pub fn jl_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8C>(writer, label); }
pub fn jle_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8E>(writer, label); }
pub fn jna_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x86>(writer, label); }
pub fn jnae_label(writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x82>(writer, label); }
pub fn jnb_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x83>(writer, label); }
pub fn jnbe_label(writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x87>(writer, label); }
pub fn jnc_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x83>(writer, label); }
pub fn jne_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x85>(writer, label); }
pub fn jng_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8E>(writer, label); }
pub fn jnge_label(writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8C>(writer, label); }
pub fn jnl_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8D>(writer, label); }
pub fn jnle_label(writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8F>(writer, label); }
pub fn jno_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x81>(writer, label); }
pub fn jnp_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8b>(writer, label); }
pub fn jns_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x89>(writer, label); }
pub fn jnz_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x85>(writer, label); }
pub fn jo_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x80>(writer, label); }
pub fn jp_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8A>(writer, label); }
pub fn jpe_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8A>(writer, label); }
pub fn jpo_label (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x8B>(writer, label); }
pub fn js_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x88>(writer, label); }
pub fn jz_label  (writer: &mut CodeWriter<'_>, label: Label) { write_jcc::<0x84>(writer, label); }

pub fn jmp_label(writer: &mut CodeWriter<'_>, label: Label) {
    writer.label_ref(label, 5, |writer, src_addr, dst_addr| {
        writer.write_byte(0xE9);
        writer.write_int((dst_addr - src_addr) as u64, 32);
        Ok(())
    });
}

/// Encode a relative jump to a pointer at a 32-bit offset (direct or conditional)
fn write_jcc_ptr(writer: &mut CodeWriter<'_>, op0: u8, op1: u8, dst_ptr: CodePtr) {
    // Write the opcode
    if op0 != 0xFF {
        writer.write_byte(op0);
    }

    writer.write_byte(op1);

    // Pointer to the end of this jump instruction
    let end_ptr = writer.get_write_ptr().add_bytes(4);

    // Compute the jump offset
    let rel64 = dst_ptr.as_offset() - end_ptr.as_offset();

    if rel64 >= i32::MIN.into() && rel64 <= i32::MAX.into() {
        // Write the relative 32-bit jump offset
        writer.write_int(rel64 as u64, 32);
    }
    else {
        // Offset doesn't fit in 4 bytes. Report error.
        //writer.dropped_bytes = true;
        panic!("we should refactor to avoid dropped_bytes");
    }
}

/// jcc - relative jumps to a pointer (32-bit offset)
pub fn ja_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x87, ptr); }
pub fn jae_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x83, ptr); }
pub fn jb_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x82, ptr); }
pub fn jbe_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x86, ptr); }
pub fn jc_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x82, ptr); }
pub fn je_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x84, ptr); }
pub fn jg_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8F, ptr); }
pub fn jge_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8D, ptr); }
pub fn jl_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8C, ptr); }
pub fn jle_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8E, ptr); }
pub fn jna_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x86, ptr); }
pub fn jnae_ptr(writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x82, ptr); }
pub fn jnb_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x83, ptr); }
pub fn jnbe_ptr(writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x87, ptr); }
pub fn jnc_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x83, ptr); }
pub fn jne_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x85, ptr); }
pub fn jng_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8E, ptr); }
pub fn jnge_ptr(writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8C, ptr); }
pub fn jnl_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8D, ptr); }
pub fn jnle_ptr(writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8F, ptr); }
pub fn jno_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x81, ptr); }
pub fn jnp_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8b, ptr); }
pub fn jns_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x89, ptr); }
pub fn jnz_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x85, ptr); }
pub fn jo_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x80, ptr); }
pub fn jp_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8A, ptr); }
pub fn jpe_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8A, ptr); }
pub fn jpo_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x8B, ptr); }
pub fn js_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x88, ptr); }
pub fn jz_ptr  (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0x0F, 0x84, ptr); }
pub fn jmp_ptr (writer: &mut CodeWriter<'_>, ptr: CodePtr) { write_jcc_ptr(writer, 0xFF, 0xE9, ptr); }

/// jmp - Indirect jump near to an R/M operand.
pub fn jmp_rm(writer: &mut CodeWriter<'_>, opnd: X86Opnd) {
    write_rm(writer, false, false, X86Opnd::None, opnd, Some(4), &[0xff]);
}

// jmp - Jump with relative 32-bit offset
pub fn jmp32(writer: &mut CodeWriter<'_>, offset: i32) {
    writer.write_byte(0xE9);
    writer.write_int(offset as u64, 32);
}

/// lea - Load Effective Address
pub fn lea(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) {
    if let X86Opnd::Reg(reg) = dst {
        assert!(reg.num_bits == 64);
        assert!(matches!(src, X86Opnd::Mem(_) | X86Opnd::IPRel(_)));
        write_rm(writer, false, true, dst, src, None, &[0x8d]);
    } else {
        unreachable!();
    }
}

/// mov - Data move operation
pub fn mov(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) {
    fn emit_reg_imm(writer: &mut CodeWriter<'_>, reg: X86Reg, imm: X86Imm) {
        // In case the source immediate could be zero extended to be 64
        // bit, we can use the 32-bit operands version of the instruction.
        // For example, we can turn mov(rax, 0x34) into the equivalent
        // mov(eax, 0x34).
        if (reg.num_bits == 64) && u32::try_from(imm.value).is_ok() {
            if reg.rex_needed() {
                write_rex(writer, false, 0, 0, reg.reg_no);
            }
            write_opcode(writer, 0xB8, reg);
            writer.write_int(imm.value as u64, 32);
        } else if reg.num_bits == 64 && imm.num_bits <= 32 {
            // Use 32-to-64 bit sign-extension when possible
            write_rm(writer, false, true /* REX.w */, X86Opnd::None, X86Opnd::Reg(reg), Some(0) /* /0 */, &[0xc7]);
            writer.write_int(imm.value as u64, 32);
        } else {
            if reg.num_bits == 16 {
                writer.write_byte(0x66);
            }

            if reg.rex_needed() || reg.num_bits == 64 {
                write_rex(writer, reg.num_bits == 64, 0, 0, reg.reg_no);
            }

            write_opcode(writer, if reg.num_bits == 8 { 0xb0 } else { 0xb8 }, reg);
            writer.write_int(imm.value as u64, reg.num_bits.into());
        }
    }
    match (dst, src) {
        // R + Imm
        (X86Opnd::Reg(reg), X86Opnd::Imm(imm)) => emit_reg_imm(writer, reg, imm),
        // R + UImm
        (X86Opnd::Reg(reg), X86Opnd::UImm(uimm)) => {
            // u64->i64 type cast is a bit pattern no-op
            let value: u64 = uimm.value;
            let value = value as i64;
            emit_reg_imm(writer, reg, X86Imm { num_bits: imm_num_bits(value), value });
        },
        // M + Imm
        (X86Opnd::Mem(mem), X86Opnd::Imm(imm)) => {
            assert!(imm.num_bits <= mem.num_bits);

            if mem.num_bits == 8 {
                write_rm(writer, false, false, X86Opnd::None, dst, None, &[0xc6]);
            } else {
                write_rm(writer, mem.num_bits == 16, mem.num_bits == 64, X86Opnd::None, dst, Some(0), &[0xc7]);
            }

            let output_num_bits:u32 = if mem.num_bits > 32 { 32 } else { mem.num_bits.into() };
            assert!(
                mem.num_bits < 64 || imm_num_bits(imm.value) <= (output_num_bits as u8),
                "immediate value should be small enough to survive sign extension"
            );
            writer.write_int(imm.value as u64, output_num_bits);
        },
        // M + UImm
        (X86Opnd::Mem(mem), X86Opnd::UImm(uimm)) => {
            assert!(uimm.num_bits <= mem.num_bits);

            if mem.num_bits == 8 {
                write_rm(writer, false, false, X86Opnd::None, dst, None, &[0xc6]);
            }
            else {
                write_rm(writer, mem.num_bits == 16, mem.num_bits == 64, X86Opnd::None, dst, Some(0), &[0xc7]);
            }

            let output_num_bits = if mem.num_bits > 32 { 32 } else { mem.num_bits.into() };
            assert!(
                mem.num_bits < 64 || imm_num_bits(uimm.value as i64) <= (output_num_bits as u8),
                "immediate value should be small enough to survive sign extension"
            );
            writer.write_int(uimm.value, output_num_bits);
        },
        // * + Imm/UImm
        (_, X86Opnd::Imm(_) | X86Opnd::UImm(_)) => unreachable!(),
        // * + *
        (_, _) => {
            write_rm_multi(
                writer,
                0x88, // opMemReg8
                0x89, // opMemRegPref
                0x8A, // opRegMem8
                0x8B, // opRegMemPref
                0xC6, // opMemImm8
                0xFF, // opMemImmSml (not available)
                0xFF, // opMemImmLrg
                None, // opExtImm
                dst,
                src
            );
        }
    };
}

/// A variant of mov used for always writing the value in 64 bits for GC offsets.
pub fn movabs(writer: &mut CodeWriter<'_>, dst: X86Opnd, value: u64) {
    match dst {
        X86Opnd::Reg(reg) => {
            assert_eq!(reg.num_bits, 64);
            write_rex(writer, true, 0, 0, reg.reg_no);

            write_opcode(writer, 0xb8, reg);
            writer.write_int(value, 64);
        },
        _ => unreachable!()
    }
}

/// movsx - Move with sign extension (signed integers)
pub fn movsx(writer: &mut CodeWriter<'_>, dst: X86Opnd, src: X86Opnd) {
    if let X86Opnd::Reg(_dst_reg) = dst {
        assert!(matches!(src, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

        let src_num_bits = src.num_bits();
        let dst_num_bits = dst.num_bits();
        assert!(src_num_bits < dst_num_bits);

        match src_num_bits {
            8 => write_rm(writer, dst_num_bits == 16, dst_num_bits == 64, dst, src, None, &[0x0f, 0xbe]),
            16 => write_rm(writer, dst_num_bits == 16, dst_num_bits == 64, dst, src, None, &[0x0f, 0xbf]),
            32 => write_rm(writer, false, true, dst, src, None, &[0x63]),
            _ => unreachable!()
        };
    } else {
        unreachable!();
    }
}

/// nop - Noop, one or multiple bytes long
pub fn nop(writer: &mut CodeWriter<'_>, length: u32) {
    match length {
        0 => {},
        1 => writer.write_byte(0x90),
        2 => writer.write_bytes(&[0x66, 0x90]),
        3 => writer.write_bytes(&[0x0f, 0x1f, 0x00]),
        4 => writer.write_bytes(&[0x0f, 0x1f, 0x40, 0x00]),
        5 => writer.write_bytes(&[0x0f, 0x1f, 0x44, 0x00, 0x00]),
        6 => writer.write_bytes(&[0x66, 0x0f, 0x1f, 0x44, 0x00, 0x00]),
        7 => writer.write_bytes(&[0x0f, 0x1f, 0x80, 0x00, 0x00, 0x00, 0x00]),
        8 => writer.write_bytes(&[0x0f, 0x1f, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00]),
        9 => writer.write_bytes(&[0x66, 0x0f, 0x1f, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00]),
        _ => {
            let mut written: u32 = 0;
            while written + 9 <= length {
                nop(writer, 9);
                written += 9;
            }
            nop(writer, length - written);
        }
    };
}

/// not - Bitwise NOT
pub fn not(writer: &mut CodeWriter<'_>, opnd: X86Opnd) {
    write_rm_unary(
        writer,
        0xf6, // opMemReg8
        0xf7, // opMemRegPref
        Some(0x02), // opExt
        opnd
    );
}

/// or - Bitwise OR
pub fn or(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        writer,
        0x08, // opMemReg8
        0x09, // opMemRegPref
        0x0A, // opRegMem8
        0x0B, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        Some(0x01), // opExtImm
        opnd0,
        opnd1
    );
}

/// pop - Pop a register off the stack
pub fn pop(writer: &mut CodeWriter<'_>, opnd: X86Opnd) {
    match opnd {
        X86Opnd::Reg(reg) => {
            assert!(reg.num_bits == 64);

            if opnd.rex_needed() {
                write_rex(writer, false, 0, 0, reg.reg_no);
            }
            write_opcode(writer, 0x58, reg);
        },
        X86Opnd::Mem(mem) => {
            assert!(mem.num_bits == 64);

            write_rm(writer, false, false, X86Opnd::None, opnd, Some(0), &[0x8f]);
        },
        _ => unreachable!()
    };
}

/// popfq - Pop the flags register (64-bit)
pub fn popfq(writer: &mut CodeWriter<'_>) {
    // REX.W + 0x9D
    writer.write_bytes(&[0x48, 0x9d]);
}

/// push - Push an operand on the stack
pub fn push(writer: &mut CodeWriter<'_>, opnd: X86Opnd) {
    match opnd {
        X86Opnd::Reg(reg) => {
            if opnd.rex_needed() {
                write_rex(writer, false, 0, 0, reg.reg_no);
            }
            write_opcode(writer, 0x50, reg);
        },
        X86Opnd::Mem(_mem) => {
            write_rm(writer, false, false, X86Opnd::None, opnd, Some(6), &[0xff]);
        },
        X86Opnd::Imm(X86Imm { value: 0, .. }) | X86Opnd::UImm(X86UImm { value: 0, .. }) => {
            writer.write_bytes(&[0x6a, 0x00]);
        }
        _ => unreachable!()
    }
}

/// pushfq - Push the flags register (64-bit)
pub fn pushfq(writer: &mut CodeWriter<'_>) {
    writer.write_byte(0x9C);
}

/// ret - Return from call, popping only the return address
pub fn ret(writer: &mut CodeWriter<'_>) {
    writer.write_byte(0xC3);
}

// Encode a bitwise shift instruction
fn write_shift(writer: &mut CodeWriter<'_>, op_mem_one_pref: u8, op_mem_cl_pref: u8, op_mem_imm_pref: u8, op_ext: u8, opnd0: X86Opnd, opnd1: X86Opnd) {
    assert!(matches!(opnd0, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

    // Check the size of opnd0
    let opnd_size = opnd0.num_bits();
    assert!(opnd_size == 16 || opnd_size == 32 || opnd_size == 64);

    let sz_pref = opnd_size == 16;
    let rex_w = opnd_size == 64;

    match opnd1 {
        X86Opnd::UImm(imm) => {
            if imm.value == 1 {
                write_rm(writer, sz_pref, rex_w, X86Opnd::None, opnd0, Some(op_ext), &[op_mem_one_pref]);
            } else {
                assert!(imm.num_bits <= 8);
                write_rm(writer, sz_pref, rex_w, X86Opnd::None, opnd0, Some(op_ext), &[op_mem_imm_pref]);
                writer.write_byte(imm.value as u8);
            }
        }

        X86Opnd::Reg(reg) => {
            // We can only use CL/RCX as the shift amount
            assert!(reg.reg_no == RCX_REG.reg_no);
            write_rm(writer, sz_pref, rex_w, X86Opnd::None, opnd0, Some(op_ext), &[op_mem_cl_pref]);
        }

        _ => {
            unreachable!("unsupported operands: {:?}, {:?}", opnd0, opnd1);
        }
    }
}

// sal - Shift arithmetic left
pub fn sal(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_shift(
        writer,
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x04,
        opnd0,
        opnd1
    );
}

/// sar - Shift arithmetic right (signed)
pub fn sar(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_shift(
        writer,
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x07,
        opnd0,
        opnd1
    );
}

// shl - Shift logical left
pub fn shl(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_shift(
        writer,
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x04,
        opnd0,
        opnd1
    );
}

/// shr - Shift logical right (unsigned)
pub fn shr(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_shift(
        writer,
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x05,
        opnd0,
        opnd1
    );
}

/// sub - Integer subtraction
pub fn sub(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        writer,
        0x28, // opMemReg8
        0x29, // opMemRegPref
        0x2A, // opRegMem8
        0x2B, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        Some(0x05), // opExtImm
        opnd0,
        opnd1
    );
}

fn resize_opnd(opnd: X86Opnd, num_bits: u8) -> X86Opnd {
    match opnd {
        X86Opnd::Reg(reg) => {
            let mut cloned = reg;
            cloned.num_bits = num_bits;
            X86Opnd::Reg(cloned)
        },
        X86Opnd::Mem(mem) => {
            let mut cloned = mem;
            cloned.num_bits = num_bits;
            X86Opnd::Mem(cloned)
        },
        _ => unreachable!()
    }
}

/// test - Logical Compare
pub fn test(writer: &mut CodeWriter<'_>, rm_opnd: X86Opnd, test_opnd: X86Opnd) {
    assert!(matches!(rm_opnd, X86Opnd::Reg(_) | X86Opnd::Mem(_)));
    let rm_num_bits = rm_opnd.num_bits();

    match test_opnd {
        X86Opnd::UImm(uimm) => {
            assert!(uimm.num_bits <= 32);
            assert!(uimm.num_bits <= rm_num_bits);

            // Use the smallest operand size possible
            assert!(rm_num_bits % 8 == 0);
            let rm_resized = resize_opnd(rm_opnd, uimm.num_bits);

            if uimm.num_bits == 8 {
                write_rm(writer, false, false, X86Opnd::None, rm_resized, Some(0x00), &[0xf6]);
                writer.write_int(uimm.value, uimm.num_bits.into());
            } else {
                write_rm(writer, uimm.num_bits == 16, false, X86Opnd::None, rm_resized, Some(0x00), &[0xf7]);
                writer.write_int(uimm.value, uimm.num_bits.into());
            }
        },
        X86Opnd::Imm(imm) => {
            // This mode only applies to 64-bit R/M operands with 32-bit signed immediates
            assert!(imm.num_bits <= 32);
            assert!(rm_num_bits == 64);

            write_rm(writer, false, true, X86Opnd::None, rm_opnd, Some(0x00), &[0xf7]);
            writer.write_int(imm.value as u64, 32);
        },
        X86Opnd::Reg(reg) => {
            assert!(reg.num_bits == rm_num_bits);

            if rm_num_bits == 8 {
                write_rm(writer, false, false, test_opnd, rm_opnd, None, &[0x84]);
            } else {
                write_rm(writer, rm_num_bits == 16, rm_num_bits == 64, test_opnd, rm_opnd, None, &[0x85]);
            }
        },
        _ => unreachable!("unexpected operands for test: {rm_opnd:?}, {test_opnd:?}")
    };
}

/// Undefined opcode
pub fn ud2(writer: &mut CodeWriter<'_>) {
    writer.write_bytes(&[0x0f, 0x0b]);
}

/// xchg - Exchange Register/Memory with Register
pub fn xchg(writer: &mut CodeWriter<'_>, rm_opnd: X86Opnd, r_opnd: X86Opnd) {
    if let (X86Opnd::Reg(rm_reg), X86Opnd::Reg(r_reg)) = (rm_opnd, r_opnd) {
        assert!(rm_reg.num_bits == 64);
        assert!(r_reg.num_bits == 64);

        // If we're exchanging with RAX
        if rm_reg.reg_no == RAX_REG_NO {
            // Write the REX byte
            write_rex(writer, true, 0, 0, r_reg.reg_no);

            // Write the opcode and register number
            writer.write_byte(0x90 + (r_reg.reg_no & 7));
        } else {
            write_rm(writer, false, true, r_opnd, rm_opnd, None, &[0x87]);
        }
    } else {
        unreachable!();
    }
}

/// xor - Exclusive bitwise OR
pub fn xor(writer: &mut CodeWriter<'_>, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        writer,
        0x30, // opMemReg8
        0x31, // opMemRegPref
        0x32, // opRegMem8
        0x33, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        Some(0x06), // opExtImm
        opnd0,
        opnd1
    );
}

impl fmt::Display for X86Reg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match X86Opnd::Reg(*self) {
            RAX  => write!(f, "rax"),
            RCX  => write!(f, "rcx"),
            RDX  => write!(f, "rdx"),
            RBX  => write!(f, "rbx"),
            RSP  => write!(f, "rsp"),
            RBP  => write!(f, "rbp"),
            RSI  => write!(f, "rsi"),
            RDI  => write!(f, "rdi"),
            R8   => write!(f, "r8"),
            R9   => write!(f, "r9"),
            R10  => write!(f, "r10"),
            R11  => write!(f, "r11"),
            R12  => write!(f, "r12"),
            R13  => write!(f, "r13"),
            R14  => write!(f, "r14"),
            R15  => write!(f, "r15"),
            EAX  => write!(f, "eax"),
            ECX  => write!(f, "ecx"),
            EDX  => write!(f, "edx"),
            EBX  => write!(f, "ebx"),
            ESP  => write!(f, "esp"),
            EBP  => write!(f, "ebp"),
            ESI  => write!(f, "esi"),
            EDI  => write!(f, "edi"),
            R8D  => write!(f, "r8d"),
            R9D  => write!(f, "r9d"),
            R10D => write!(f, "r10d"),
            R11D => write!(f, "r11d"),
            R12D => write!(f, "r12d"),
            R13D => write!(f, "r13d"),
            R14D => write!(f, "r14d"),
            R15D => write!(f, "r15d"),
            AX   => write!(f, "ax"),
            CX   => write!(f, "cx"),
            DX   => write!(f, "dx"),
            BX   => write!(f, "bx"),
            BP   => write!(f, "bp"),
            SI   => write!(f, "si"),
            DI   => write!(f, "di"),
            R8W  => write!(f, "r8w"),
            R9W  => write!(f, "r9w"),
            R10W => write!(f, "r10w"),
            R11W => write!(f, "r11w"),
            R12W => write!(f, "r12w"),
            R13W => write!(f, "r13w"),
            R14W => write!(f, "r14w"),
            R15W => write!(f, "r15w"),
            AL   => write!(f, "al"),
            CL   => write!(f, "cl"),
            DL   => write!(f, "dl"),
            BL   => write!(f, "bl"),
            SPL  => write!(f, "spl"),
            BPL  => write!(f, "bpl"),
            SIL  => write!(f, "sil"),
            DIL  => write!(f, "dil"),
            R8B  => write!(f, "r8b"),
            R9B  => write!(f, "r9b"),
            R10B => write!(f, "r10b"),
            R11B => write!(f, "r11b"),
            R12B => write!(f, "r12b"),
            R13B => write!(f, "r13b"),
            R14B => write!(f, "r14b"),
            R15B => write!(f, "r15b"),
            _ => write!(f, "{self:?}"),
        }
    }
}
