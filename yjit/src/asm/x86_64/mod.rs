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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RegType
{
    GP,
    //FP,
    //XMM,
    IP,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86Reg
{
    // Size in bits
    pub num_bits: u8,

    // Register type
    pub reg_type: RegType,

    // Register index number
    pub reg_no: u8,
}

#[derive(Clone, Copy, Debug)]
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

#[derive(Clone, Copy, Debug)]
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
}

impl X86Opnd {
    fn rex_needed(&self) -> bool {
        match self {
            X86Opnd::None => false,
            X86Opnd::Imm(_) => false,
            X86Opnd::UImm(_) => false,
            X86Opnd::Reg(reg) => reg.reg_no > 7 || reg.num_bits == 8 && reg.reg_no >= 4,
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
        match self {
            X86Opnd::None => false,
            _ => true
        }
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
                num_bits: num_bits,
                base_reg_no: base_reg.reg_no,
                idx_reg_no: None,
                scale_exp: 0,
                disp: disp,
            }
        )
    }
}

/// Memory operand with SIB (Scale Index Base) indexing
pub fn mem_opnd_sib(num_bits: u8, base_opnd: X86Opnd, index_opnd: X86Opnd, scale: i32, disp: i32) -> X86Opnd {
    if let (X86Opnd::Reg(base_reg), X86Opnd::Reg(index_reg)) = (base_opnd, index_opnd) {
        let scale_exp: u8;

        match scale {
            8 => { scale_exp = 3; },
            4 => { scale_exp = 2; },
            2 => { scale_exp = 1; },
            1 => { scale_exp = 0; },
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

/*
// Struct member operand
#define member_opnd(base_reg, struct_type, member_name) mem_opnd( \
    8 * sizeof(((struct_type*)0)->member_name), \
    base_reg,                                   \
    offsetof(struct_type, member_name)          \
)

// Struct member operand with an array index
#define member_opnd_idx(base_reg, struct_type, member_name, idx) mem_opnd( \
    8 * sizeof(((struct_type*)0)->member_name[0]),     \
    base_reg,                                       \
    (offsetof(struct_type, member_name) +           \
     sizeof(((struct_type*)0)->member_name[0]) * idx)  \
)
*/

/*
// TODO: this should be a method, X86Opnd.resize() or X86Opnd.subreg()
static x86opnd_t resize_opnd(x86opnd_t opnd, uint32_t num_bits)
{
    assert (num_bits % 8 == 0);
    x86opnd_t sub = opnd;
    sub.num_bits = num_bits;
    return sub;
}
*/

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
fn write_rex(cb: &mut CodeBlock, w_flag: bool, reg_no: u8, idx_reg_no: u8, rm_reg_no: u8) {
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
    cb.write_byte(0x40 + (w << 3) + (r << 2) + (x << 1) + (b));
}

/// Write an opcode byte with an embedded register operand
fn write_opcode(cb: &mut CodeBlock, opcode: u8, reg: X86Reg) {
    let op_byte: u8 = opcode | (reg.reg_no & 7);
    cb.write_byte(op_byte);
}

/// Encode an RM instruction
fn write_rm(cb: &mut CodeBlock, sz_pref: bool, rex_w: bool, r_opnd: X86Opnd, rm_opnd: X86Opnd, op_ext: Option<u8>, bytes: &[u8]) {
    let op_len = bytes.len();
    assert!(op_len > 0 && op_len <= 3);
    assert!(matches!(r_opnd, X86Opnd::Reg(_) | X86Opnd::None), "Can only encode an RM instruction with a register or a none");

    // Flag to indicate the REX prefix is needed
    let need_rex = rex_w || r_opnd.rex_needed() || rm_opnd.rex_needed();

    // Flag to indicate SIB byte is needed
    let need_sib = r_opnd.sib_needed() || rm_opnd.sib_needed();

    // Add the operand-size prefix, if needed
    if sz_pref {
        cb.write_byte(0x66);
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
        cb.write_byte(rex_byte);
    }

    // Write the opcode bytes to the code block
    for byte in bytes {
        cb.write_byte(*byte)
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
    cb.write_byte(rm_byte);

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
                cb.write_byte(sib_byte);
            },
            _ => panic!("Expected mem operand")
        }
    }

    // Add the displacement
    match rm_opnd {
        X86Opnd::Mem(mem) => {
            let disp_size = rm_opnd.disp_size();
            if disp_size > 0 {
                cb.write_int(mem.disp as u64, disp_size);
            }
        },
        X86Opnd::IPRel(rel) => {
            cb.write_int(rel as u64, 32);
        },
        _ => ()
    };
}

// Encode a mul-like single-operand RM instruction
fn write_rm_unary(cb: &mut CodeBlock, op_mem_reg_8: u8, op_mem_reg_pref: u8, op_ext: Option<u8>, opnd: X86Opnd) {
    assert!(matches!(opnd, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

    let opnd_size = opnd.num_bits();
    assert!(opnd_size == 8 || opnd_size == 16 || opnd_size == 32 || opnd_size == 64);

    if opnd_size == 8 {
        write_rm(cb, false, false, X86Opnd::None, opnd, op_ext, &[op_mem_reg_8]);
    } else {
        let sz_pref = opnd_size == 16;
        let rex_w = opnd_size == 64;
        write_rm(cb, sz_pref, rex_w, X86Opnd::None, opnd, op_ext, &[op_mem_reg_pref]);
    }
}

// Encode an add-like RM instruction with multiple possible encodings
fn write_rm_multi(cb: &mut CodeBlock, op_mem_reg8: u8, op_mem_reg_pref: u8, op_reg_mem8: u8, op_reg_mem_pref: u8, op_mem_imm8: u8, op_mem_imm_sml: u8, op_mem_imm_lrg: u8, op_ext_imm: Option<u8>, opnd0: X86Opnd, opnd1: X86Opnd) {
    assert!(matches!(opnd0, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

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
                write_rm(cb, false, false, opnd1, opnd0, None, &[op_mem_reg8]);
            } else {
                write_rm(cb, sz_pref, rex_w, opnd1, opnd0, None, &[op_mem_reg_pref]);
            }
        },
        // Reg + R/M/IPRel
        (X86Opnd::Reg(_), X86Opnd::Mem(_) | X86Opnd::IPRel(_)) => {
            if opnd_size == 8 {
                write_rm(cb, false, false, opnd0, opnd1, None, &[op_reg_mem8]);
            } else {
                write_rm(cb, sz_pref, rex_w, opnd0, opnd1, None, &[op_reg_mem_pref]);
            }
        },
        // R/M + Imm
        (_, X86Opnd::Imm(imm)) => {
            if imm.num_bits <= 8 {
                // 8-bit immediate

                if opnd_size == 8 {
                    write_rm(cb, false, false, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm8]);
                } else {
                    write_rm(cb, sz_pref, rex_w, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm_sml]);
                }

                cb.write_int(imm.value as u64, 8);
            } else if imm.num_bits <= 32 {
                // 32-bit immediate

                assert!(imm.num_bits <= opnd_size);
                write_rm(cb, sz_pref, rex_w, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm_lrg]);
                cb.write_int(imm.value as u64, if opnd_size > 32 { 32 } else { opnd_size.into() });
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
                    write_rm(cb, false, false, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm8]);
                } else {
                    write_rm(cb, sz_pref, rex_w, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm_sml]);
                }

                cb.write_int(uimm.value, 8);
            } else if num_bits <= 32 {
                // 32-bit immediate

                assert!(num_bits <= opnd_size);
                write_rm(cb, sz_pref, rex_w, X86Opnd::None, opnd0, op_ext_imm, &[op_mem_imm_lrg]);
                cb.write_int(uimm.value, if opnd_size > 32 { 32 } else { opnd_size.into() });
            } else {
                panic!("immediate value too large (num_bits={}, num={uimm:?})", num_bits);
            }
        },
        _ => panic!("unknown encoding combo: {opnd0:?} {opnd1:?}")
    };
}

// LOCK - lock prefix for atomic shared memory operations
pub fn write_lock_prefix(cb: &mut CodeBlock) {
    cb.write_byte(0xf0);
}

/// add - Integer addition
pub fn add(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        cb,
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
pub fn and(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        cb,
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
pub fn call_rel32(cb: &mut CodeBlock, rel32: i32) {
    // Write the opcode
    cb.write_byte(0xe8);

    // Write the relative 32-bit jump offset
    cb.write_bytes(&rel32.to_le_bytes());
}

/// call - Call a pointer, encode with a 32-bit offset if possible
pub fn call_ptr(cb: &mut CodeBlock, scratch_opnd: X86Opnd, dst_ptr: *const u8) {
    if let X86Opnd::Reg(_scratch_reg) = scratch_opnd {
        use crate::stats::{incr_counter};

        // Pointer to the end of this call instruction
        let end_ptr = cb.get_ptr(cb.write_pos + 5);

        // Compute the jump offset
        let rel64: i64 = dst_ptr as i64 - end_ptr.raw_ptr(cb) as i64;

        // If the offset fits in 32-bit
        if rel64 >= i32::MIN.into() && rel64 <= i32::MAX.into() {
            incr_counter!(num_send_x86_rel32);
            call_rel32(cb, rel64.try_into().unwrap());
            return;
        }

        // Move the pointer into the scratch register and call
        incr_counter!(num_send_x86_reg);
        mov(cb, scratch_opnd, const_ptr_opnd(dst_ptr));
        call(cb, scratch_opnd);
    } else {
        unreachable!();
    }
}

/// call - Call to label with 32-bit offset
pub fn call_label(cb: &mut CodeBlock, label_idx: usize) {
    cb.label_ref(label_idx, 5, |cb, src_addr, dst_addr| {
        cb.write_byte(0xE8);
        cb.write_int((dst_addr - src_addr) as u64, 32);
    });
}

/// call - Indirect call with an R/M operand
pub fn call(cb: &mut CodeBlock, opnd: X86Opnd) {
    write_rm(cb, false, false, X86Opnd::None, opnd, Some(2), &[0xff]);
}

/// Encode a conditional move instruction
fn write_cmov(cb: &mut CodeBlock, opcode1: u8, dst: X86Opnd, src: X86Opnd) {
    if let X86Opnd::Reg(reg) = dst {
        match src {
            X86Opnd::Reg(_) => (),
            X86Opnd::Mem(_) => (),
            _ => unreachable!()
        };

        assert!(reg.num_bits >= 16);
        let sz_pref = reg.num_bits == 16;
        let rex_w = reg.num_bits == 64;

        write_rm(cb, sz_pref, rex_w, dst, src, None, &[0x0f, opcode1]);
    } else {
        unreachable!()
    }
}

// cmovcc - Conditional move
pub fn cmova(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x47, dst, src); }
pub fn cmovae(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x43, dst, src); }
pub fn cmovb(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x42, dst, src); }
pub fn cmovbe(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x46, dst, src); }
pub fn cmovc(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x42, dst, src); }
pub fn cmove(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x44, dst, src); }
pub fn cmovg(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4f, dst, src); }
pub fn cmovge(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4d, dst, src); }
pub fn cmovl(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4c, dst, src); }
pub fn cmovle(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4e, dst, src); }
pub fn cmovna(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x46, dst, src); }
pub fn cmovnae(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x42, dst, src); }
pub fn cmovnb(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x43, dst, src); }
pub fn cmovnbe(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x47, dst, src); }
pub fn cmovnc(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x43, dst, src); }
pub fn cmovne(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x45, dst, src); }
pub fn cmovng(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4e, dst, src); }
pub fn cmovnge(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4c, dst, src); }
pub fn cmovnl(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb,  0x4d, dst, src); }
pub fn cmovnle(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4f, dst, src); }
pub fn cmovno(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x41, dst, src); }
pub fn cmovnp(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4b, dst, src); }
pub fn cmovns(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x49, dst, src); }
pub fn cmovnz(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x45, dst, src); }
pub fn cmovo(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x40, dst, src); }
pub fn cmovp(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4a, dst, src); }
pub fn cmovpe(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4a, dst, src); }
pub fn cmovpo(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x4b, dst, src); }
pub fn cmovs(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x48, dst, src); }
pub fn cmovz(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) { write_cmov(cb, 0x44, dst, src); }

/// cmp - Compare and set flags
pub fn cmp(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        cb,
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
pub fn cdq(cb: &mut CodeBlock) {
    cb.write_byte(0x99);
}

/// cqo - Convert quadword to octaword
pub fn cqo(cb: &mut CodeBlock) {
    cb.write_bytes(&[0x48, 0x99]);
}

/// imul - signed integer multiply
pub fn imul(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    assert!(opnd0.num_bits() == 64);
    assert!(opnd1.num_bits() == 64);
    assert!(matches!(opnd0, X86Opnd::Reg(_) | X86Opnd::Mem(_)));
    assert!(matches!(opnd1, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

    match (opnd0, opnd1) {
        (X86Opnd::Reg(_), X86Opnd::Reg(_) | X86Opnd::Mem(_)) => {
            //REX.W + 0F AF /rIMUL r64, r/m64
            // Quadword register := Quadword register * r/m64.
            write_rm(cb, false, true, opnd0, opnd1, None, &[0x0F, 0xAF]);
        }

        // Flip the operands to handle this case. This instruction has weird encoding restrictions.
        (X86Opnd::Mem(_), X86Opnd::Reg(_)) => {
            //REX.W + 0F AF /rIMUL r64, r/m64
            // Quadword register := Quadword register * r/m64.
            write_rm(cb, false, true, opnd1, opnd0, None, &[0x0F, 0xAF]);
        }

        _ => unreachable!()
    }
}

/// Interrupt 3 - trap to debugger
pub fn int3(cb: &mut CodeBlock) {
    cb.write_byte(0xcc);
}

// Encode a conditional relative jump to a label
// Note: this always encodes a 32-bit offset
fn write_jcc<const OP: u8>(cb: &mut CodeBlock, label_idx: usize) {
    cb.label_ref(label_idx, 6, |cb, src_addr, dst_addr| {
        cb.write_byte(0x0F);
        cb.write_byte(OP);
        cb.write_int((dst_addr - src_addr) as u64, 32);
    });
}

/// jcc - relative jumps to a label
pub fn ja_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x87>(cb, label_idx); }
pub fn jae_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x83>(cb, label_idx); }
pub fn jb_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x82>(cb, label_idx); }
pub fn jbe_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x86>(cb, label_idx); }
pub fn jc_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x82>(cb, label_idx); }
pub fn je_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x84>(cb, label_idx); }
pub fn jg_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8F>(cb, label_idx); }
pub fn jge_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8D>(cb, label_idx); }
pub fn jl_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8C>(cb, label_idx); }
pub fn jle_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8E>(cb, label_idx); }
pub fn jna_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x86>(cb, label_idx); }
pub fn jnae_label(cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x82>(cb, label_idx); }
pub fn jnb_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x83>(cb, label_idx); }
pub fn jnbe_label(cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x87>(cb, label_idx); }
pub fn jnc_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x83>(cb, label_idx); }
pub fn jne_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x85>(cb, label_idx); }
pub fn jng_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8E>(cb, label_idx); }
pub fn jnge_label(cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8C>(cb, label_idx); }
pub fn jnl_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8D>(cb, label_idx); }
pub fn jnle_label(cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8F>(cb, label_idx); }
pub fn jno_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x81>(cb, label_idx); }
pub fn jnp_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8b>(cb, label_idx); }
pub fn jns_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x89>(cb, label_idx); }
pub fn jnz_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x85>(cb, label_idx); }
pub fn jo_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x80>(cb, label_idx); }
pub fn jp_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8A>(cb, label_idx); }
pub fn jpe_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8A>(cb, label_idx); }
pub fn jpo_label (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x8B>(cb, label_idx); }
pub fn js_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x88>(cb, label_idx); }
pub fn jz_label  (cb: &mut CodeBlock, label_idx: usize) { write_jcc::<0x84>(cb, label_idx); }

pub fn jmp_label(cb: &mut CodeBlock, label_idx: usize) {
    cb.label_ref(label_idx, 5, |cb, src_addr, dst_addr| {
        cb.write_byte(0xE9);
        cb.write_int((dst_addr - src_addr) as u64, 32);
    });
}

/// Encode a relative jump to a pointer at a 32-bit offset (direct or conditional)
fn write_jcc_ptr(cb: &mut CodeBlock, op0: u8, op1: u8, dst_ptr: CodePtr) {
    // Write the opcode
    if op0 != 0xFF {
        cb.write_byte(op0);
    }

    cb.write_byte(op1);

    // Pointer to the end of this jump instruction
    let end_ptr = cb.get_ptr(cb.write_pos + 4);

    // Compute the jump offset
    let rel64 = dst_ptr.as_offset() - end_ptr.as_offset();

    if rel64 >= i32::MIN.into() && rel64 <= i32::MAX.into() {
        // Write the relative 32-bit jump offset
        cb.write_int(rel64 as u64, 32);
    }
    else {
        // Offset doesn't fit in 4 bytes. Report error.
        cb.dropped_bytes = true;
    }
}

/// jcc - relative jumps to a pointer (32-bit offset)
pub fn ja_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x87, ptr); }
pub fn jae_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x83, ptr); }
pub fn jb_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x82, ptr); }
pub fn jbe_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x86, ptr); }
pub fn jc_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x82, ptr); }
pub fn je_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x84, ptr); }
pub fn jg_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8F, ptr); }
pub fn jge_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8D, ptr); }
pub fn jl_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8C, ptr); }
pub fn jle_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8E, ptr); }
pub fn jna_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x86, ptr); }
pub fn jnae_ptr(cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x82, ptr); }
pub fn jnb_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x83, ptr); }
pub fn jnbe_ptr(cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x87, ptr); }
pub fn jnc_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x83, ptr); }
pub fn jne_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x85, ptr); }
pub fn jng_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8E, ptr); }
pub fn jnge_ptr(cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8C, ptr); }
pub fn jnl_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8D, ptr); }
pub fn jnle_ptr(cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8F, ptr); }
pub fn jno_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x81, ptr); }
pub fn jnp_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8b, ptr); }
pub fn jns_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x89, ptr); }
pub fn jnz_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x85, ptr); }
pub fn jo_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x80, ptr); }
pub fn jp_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8A, ptr); }
pub fn jpe_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8A, ptr); }
pub fn jpo_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x8B, ptr); }
pub fn js_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x88, ptr); }
pub fn jz_ptr  (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0x0F, 0x84, ptr); }
pub fn jmp_ptr (cb: &mut CodeBlock, ptr: CodePtr) { write_jcc_ptr(cb, 0xFF, 0xE9, ptr); }

/// jmp - Indirect jump near to an R/M operand.
pub fn jmp_rm(cb: &mut CodeBlock, opnd: X86Opnd) {
    write_rm(cb, false, false, X86Opnd::None, opnd, Some(4), &[0xff]);
}

// jmp - Jump with relative 32-bit offset
pub fn jmp32(cb: &mut CodeBlock, offset: i32) {
    cb.write_byte(0xE9);
    cb.write_int(offset as u64, 32);
}

/// lea - Load Effective Address
pub fn lea(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) {
    if let X86Opnd::Reg(reg) = dst {
        assert!(reg.num_bits == 64);
        assert!(matches!(src, X86Opnd::Mem(_) | X86Opnd::IPRel(_)));
        write_rm(cb, false, true, dst, src, None, &[0x8d]);
    } else {
        unreachable!();
    }
}

/// mov - Data move operation
pub fn mov(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) {
    match (dst, src) {
        // R + Imm
        (X86Opnd::Reg(reg), X86Opnd::Imm(imm)) => {
            assert!(imm.num_bits <= reg.num_bits);

            // In case the source immediate could be zero extended to be 64
            // bit, we can use the 32-bit operands version of the instruction.
            // For example, we can turn mov(rax, 0x34) into the equivalent
            // mov(eax, 0x34).
            if (reg.num_bits == 64) && (imm.value > 0) && (imm.num_bits <= 32) {
                if dst.rex_needed() {
                    write_rex(cb, false, 0, 0, reg.reg_no);
                }
                write_opcode(cb, 0xB8, reg);
                cb.write_int(imm.value as u64, 32);
            } else {
                if reg.num_bits == 16 {
                    cb.write_byte(0x66);
                }

                if dst.rex_needed() || reg.num_bits == 64 {
                    write_rex(cb, reg.num_bits == 64, 0, 0, reg.reg_no);
                }

                write_opcode(cb, if reg.num_bits == 8 { 0xb0 } else { 0xb8 }, reg);
                cb.write_int(imm.value as u64, reg.num_bits.into());
            }
        },
        // R + UImm
        (X86Opnd::Reg(reg), X86Opnd::UImm(uimm)) => {
            assert!(uimm.num_bits <= reg.num_bits);

            // In case the source immediate could be zero extended to be 64
            // bit, we can use the 32-bit operands version of the instruction.
            // For example, we can turn mov(rax, 0x34) into the equivalent
            // mov(eax, 0x34).
            if (reg.num_bits == 64) && (uimm.value <= u32::MAX.into()) {
                if dst.rex_needed() {
                    write_rex(cb, false, 0, 0, reg.reg_no);
                }
                write_opcode(cb, 0xB8, reg);
                cb.write_int(uimm.value, 32);
            } else {
                if reg.num_bits == 16 {
                    cb.write_byte(0x66);
                }

                if dst.rex_needed() || reg.num_bits == 64 {
                    write_rex(cb, reg.num_bits == 64, 0, 0, reg.reg_no);
                }

                write_opcode(cb, if reg.num_bits == 8 { 0xb0 } else { 0xb8 }, reg);
                cb.write_int(uimm.value, reg.num_bits.into());
            }
        },
        // M + Imm
        (X86Opnd::Mem(mem), X86Opnd::Imm(imm)) => {
            assert!(imm.num_bits <= mem.num_bits);

            if mem.num_bits == 8 {
                write_rm(cb, false, false, X86Opnd::None, dst, None, &[0xc6]);
            } else {
                write_rm(cb, mem.num_bits == 16, mem.num_bits == 64, X86Opnd::None, dst, Some(0), &[0xc7]);
            }

            let output_num_bits:u32 = if mem.num_bits > 32 { 32 } else { mem.num_bits.into() };
            assert!(
                mem.num_bits < 64 || imm_num_bits(imm.value) <= (output_num_bits as u8),
                "immediate value should be small enough to survive sign extension"
            );
            cb.write_int(imm.value as u64, output_num_bits);
        },
        // M + UImm
        (X86Opnd::Mem(mem), X86Opnd::UImm(uimm)) => {
            assert!(uimm.num_bits <= mem.num_bits);

            if mem.num_bits == 8 {
                write_rm(cb, false, false, X86Opnd::None, dst, None, &[0xc6]);
            }
            else {
                write_rm(cb, mem.num_bits == 16, mem.num_bits == 64, X86Opnd::None, dst, Some(0), &[0xc7]);
            }

            let output_num_bits = if mem.num_bits > 32 { 32 } else { mem.num_bits.into() };
            assert!(
                mem.num_bits < 64 || imm_num_bits(uimm.value as i64) <= (output_num_bits as u8),
                "immediate value should be small enough to survive sign extension"
            );
            cb.write_int(uimm.value, output_num_bits);
        },
        // * + Imm/UImm
        (_, X86Opnd::Imm(_) | X86Opnd::UImm(_)) => unreachable!(),
        // * + *
        (_, _) => {
            write_rm_multi(
                cb,
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
pub fn movabs(cb: &mut CodeBlock, dst: X86Opnd, value: u64) {
    match dst {
        X86Opnd::Reg(reg) => {
            assert_eq!(reg.num_bits, 64);
            write_rex(cb, true, 0, 0, reg.reg_no);

            write_opcode(cb, 0xb8, reg);
            cb.write_int(value, 64);
        },
        _ => unreachable!()
    }
}

/// movsx - Move with sign extension (signed integers)
pub fn movsx(cb: &mut CodeBlock, dst: X86Opnd, src: X86Opnd) {
    if let X86Opnd::Reg(_dst_reg) = dst {
        assert!(matches!(src, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

        let src_num_bits = src.num_bits();
        let dst_num_bits = dst.num_bits();
        assert!(src_num_bits < dst_num_bits);

        match src_num_bits {
            8 => write_rm(cb, dst_num_bits == 16, dst_num_bits == 64, dst, src, None, &[0x0f, 0xbe]),
            16 => write_rm(cb, dst_num_bits == 16, dst_num_bits == 64, dst, src, None, &[0x0f, 0xbf]),
            32 => write_rm(cb, false, true, dst, src, None, &[0x63]),
            _ => unreachable!()
        };
    } else {
        unreachable!();
    }
}

/*
/// movzx - Move with zero extension (unsigned values)
void movzx(codeblock_t *cb, x86opnd_t dst, x86opnd_t src)
{
    cb.writeASM("movzx", dst, src);

    uint32_t dstSize;
    if (dst.isReg)
        dstSize = dst.reg.size;
    else
        assert (false, "movzx dst must be a register");

    uint32_t srcSize;
    if (src.isReg)
        srcSize = src.reg.size;
    else if (src.isMem)
        srcSize = src.mem.size;
    else
        assert (false);

    assert (
        srcSize < dstSize,
        "movzx: srcSize >= dstSize"
    );

    if (srcSize is 8)
    {
        cb.writeRMInstr!('r', 0xFF, 0x0F, 0xB6)(dstSize is 16, dstSize is 64, dst, src);
    }
    else if (srcSize is 16)
    {
        cb.writeRMInstr!('r', 0xFF, 0x0F, 0xB7)(dstSize is 16, dstSize is 64, dst, src);
    }
    else
    {
        assert (false, "invalid src operand size for movxz");
    }
}
*/

/// nop - Noop, one or multiple bytes long
pub fn nop(cb: &mut CodeBlock, length: u32) {
    match length {
        0 => {},
        1 => cb.write_byte(0x90),
        2 => cb.write_bytes(&[0x66, 0x90]),
        3 => cb.write_bytes(&[0x0f, 0x1f, 0x00]),
        4 => cb.write_bytes(&[0x0f, 0x1f, 0x40, 0x00]),
        5 => cb.write_bytes(&[0x0f, 0x1f, 0x44, 0x00, 0x00]),
        6 => cb.write_bytes(&[0x66, 0x0f, 0x1f, 0x44, 0x00, 0x00]),
        7 => cb.write_bytes(&[0x0f, 0x1f, 0x80, 0x00, 0x00, 0x00, 0x00]),
        8 => cb.write_bytes(&[0x0f, 0x1f, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00]),
        9 => cb.write_bytes(&[0x66, 0x0f, 0x1f, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00]),
        _ => {
            let mut written: u32 = 0;
            while written + 9 <= length {
                nop(cb, 9);
                written += 9;
            }
            nop(cb, length - written);
        }
    };
}

/// not - Bitwise NOT
pub fn not(cb: &mut CodeBlock, opnd: X86Opnd) {
    write_rm_unary(
        cb,
        0xf6, // opMemReg8
        0xf7, // opMemRegPref
        Some(0x02), // opExt
        opnd
    );
}

/// or - Bitwise OR
pub fn or(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        cb,
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
pub fn pop(cb: &mut CodeBlock, opnd: X86Opnd) {
    match opnd {
        X86Opnd::Reg(reg) => {
            assert!(reg.num_bits == 64);

            if opnd.rex_needed() {
                write_rex(cb, false, 0, 0, reg.reg_no);
            }
            write_opcode(cb, 0x58, reg);
        },
        X86Opnd::Mem(mem) => {
            assert!(mem.num_bits == 64);

            write_rm(cb, false, false, X86Opnd::None, opnd, Some(0), &[0x8f]);
        },
        _ => unreachable!()
    };
}

/// popfq - Pop the flags register (64-bit)
pub fn popfq(cb: &mut CodeBlock) {
    // REX.W + 0x9D
    cb.write_bytes(&[0x48, 0x9d]);
}

/// push - Push an operand on the stack
pub fn push(cb: &mut CodeBlock, opnd: X86Opnd) {
    match opnd {
        X86Opnd::Reg(reg) => {
            if opnd.rex_needed() {
                write_rex(cb, false, 0, 0, reg.reg_no);
            }
            write_opcode(cb, 0x50, reg);
        },
        X86Opnd::Mem(_mem) => {
            write_rm(cb, false, false, X86Opnd::None, opnd, Some(6), &[0xff]);
        },
        _ => unreachable!()
    }
}

/// pushfq - Push the flags register (64-bit)
pub fn pushfq(cb: &mut CodeBlock) {
    cb.write_byte(0x9C);
}

/// ret - Return from call, popping only the return address
pub fn ret(cb: &mut CodeBlock) {
    cb.write_byte(0xC3);
}

// Encode a bitwise shift instruction
fn write_shift(cb: &mut CodeBlock, op_mem_one_pref: u8, op_mem_cl_pref: u8, op_mem_imm_pref: u8, op_ext: u8, opnd0: X86Opnd, opnd1: X86Opnd) {
    assert!(matches!(opnd0, X86Opnd::Reg(_) | X86Opnd::Mem(_)));

    // Check the size of opnd0
    let opnd_size = opnd0.num_bits();
    assert!(opnd_size == 16 || opnd_size == 32 || opnd_size == 64);

    let sz_pref = opnd_size == 16;
    let rex_w = opnd_size == 64;

    match opnd1 {
        X86Opnd::UImm(imm) => {
            if imm.value == 1 {
                write_rm(cb, sz_pref, rex_w, X86Opnd::None, opnd0, Some(op_ext), &[op_mem_one_pref]);
            } else {
                assert!(imm.num_bits <= 8);
                write_rm(cb, sz_pref, rex_w, X86Opnd::None, opnd0, Some(op_ext), &[op_mem_imm_pref]);
                cb.write_byte(imm.value as u8);
            }
        }

        X86Opnd::Reg(reg) => {
            // We can only use CL/RCX as the shift amount
            assert!(reg.reg_no == RCX_REG.reg_no);
            write_rm(cb, sz_pref, rex_w, X86Opnd::None, opnd0, Some(op_ext), &[op_mem_cl_pref]);
        }

        _ => {
            unreachable!("unsupported operands: {:?}, {:?}", opnd0, opnd1);
        }
    }
}

// sal - Shift arithmetic left
pub fn sal(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_shift(
        cb,
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x04,
        opnd0,
        opnd1
    );
}

/// sar - Shift arithmetic right (signed)
pub fn sar(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_shift(
        cb,
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x07,
        opnd0,
        opnd1
    );
}

// shl - Shift logical left
pub fn shl(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_shift(
        cb,
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x04,
        opnd0,
        opnd1
    );
}

/// shr - Shift logical right (unsigned)
pub fn shr(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_shift(
        cb,
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x05,
        opnd0,
        opnd1
    );
}

/// sub - Integer subtraction
pub fn sub(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        cb,
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
pub fn test(cb: &mut CodeBlock, rm_opnd: X86Opnd, test_opnd: X86Opnd) {
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
                write_rm(cb, false, false, X86Opnd::None, rm_resized, Some(0x00), &[0xf6]);
                cb.write_int(uimm.value, uimm.num_bits.into());
            } else {
                write_rm(cb, uimm.num_bits == 16, false, X86Opnd::None, rm_resized, Some(0x00), &[0xf7]);
                cb.write_int(uimm.value, uimm.num_bits.into());
            }
        },
        X86Opnd::Imm(imm) => {
            // This mode only applies to 64-bit R/M operands with 32-bit signed immediates
            assert!(imm.num_bits <= 32);
            assert!(rm_num_bits == 64);

            write_rm(cb, false, true, X86Opnd::None, rm_opnd, Some(0x00), &[0xf7]);
            cb.write_int(imm.value as u64, 32);
        },
        X86Opnd::Reg(reg) => {
            assert!(reg.num_bits == rm_num_bits);

            if rm_num_bits == 8 {
                write_rm(cb, false, false, test_opnd, rm_opnd, None, &[0x84]);
            } else {
                write_rm(cb, rm_num_bits == 16, rm_num_bits == 64, test_opnd, rm_opnd, None, &[0x85]);
            }
        },
        _ => unreachable!()
    };
}

/// Undefined opcode
pub fn ud2(cb: &mut CodeBlock) {
    cb.write_bytes(&[0x0f, 0x0b]);
}

/// xchg - Exchange Register/Memory with Register
pub fn xchg(cb: &mut CodeBlock, rm_opnd: X86Opnd, r_opnd: X86Opnd) {
    if let (X86Opnd::Reg(rm_reg), X86Opnd::Reg(r_reg)) = (rm_opnd, r_opnd) {
        assert!(rm_reg.num_bits == 64);
        assert!(r_reg.num_bits == 64);

        // If we're exchanging with RAX
        if rm_reg.reg_no == RAX_REG_NO {
            // Write the REX byte
            write_rex(cb, true, 0, 0, r_reg.reg_no);

            // Write the opcode and register number
            cb.write_byte(0x90 + (r_reg.reg_no & 7));
        } else {
            write_rm(cb, false, true, r_opnd, rm_opnd, None, &[0x87]);
        }
    } else {
        unreachable!();
    }
}

/// xor - Exclusive bitwise OR
pub fn xor(cb: &mut CodeBlock, opnd0: X86Opnd, opnd1: X86Opnd) {
    write_rm_multi(
        cb,
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
