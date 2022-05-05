use crate::asm::*;

// Import the assembler tests module
mod tests;

#[derive(Clone, Copy, Debug)]
pub struct Aarch64Imm
{
    // Size in bits
    num_bits: u8,

    // The value of the immediate
    value: i64
}

#[derive(Clone, Copy, Debug)]
pub struct Aarch64ImmShift
{
    // Size in bits
    num_bits: u8,

    // The value of the immediate
    value: u32,

    shift_type: ShiftType,

    shift_num: u8
}

#[derive(Clone, Copy, Debug)]
pub struct Aarch64UImm
{
    // Size in bits
    num_bits: u8,

    // The value of the immediate
    value: u64
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RegType
{
    GP,
    STACK,
    //ZERO,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AddrType
{
    PostIdx = 1,
    Offset = 2,
    PreIdx = 3,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ShiftType
{
    LSL,
}

#[derive(Clone, Copy, Debug)]
pub struct Aarc64Reg
{
    // Size in bits
    num_bits: u8,

    // Register type
    reg_type: RegType,

    // Register index number
    reg_no: u8,
}

#[derive(Clone, Copy, Debug)]
pub struct Aarc64Mem
{
    // Size in bits
    num_bits: u8,

    // Base register number
    base_reg_no: u8,

    // Addressing type
    addressing: AddrType,

    // Constant displacement from the base, not scaled
    disp: i32,
}

#[derive(Clone, Copy, Debug)]
pub enum YJitOpnd
{
    // Immediate value
    Imm(Aarch64Imm),

    // Immediate value with shift
    ImmShift(Aarch64ImmShift),

    // General-purpose register
    Reg(Aarc64Reg),

    // Memory location
    Mem(Aarc64Mem),
}

impl YJitOpnd {
}

pub const X0: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 0 });
pub const X1: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 1 });
// pub const X2: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 2 });
// pub const X3: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 3 });
// pub const X4: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 4 });
// pub const X5: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 5 });
// pub const X6: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 6 });
// pub const X7: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 7 });
// pub const X8: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 8 });
// pub const X9: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 9 });
// pub const X10: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 10 });
// pub const X11: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 11 });
// pub const X12: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 12 });
// pub const X13: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 13 });
// pub const X14: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 14 });
// pub const X15: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 15 });
// pub const X16: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 16 });
// pub const X17: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 17 });
// pub const X18: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 18 });
pub const X19: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 19 });
pub const X20: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 20 });
pub const X21: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 21 });
// pub const X22: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 22 });
// pub const X23: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 23 });
// pub const X24: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 24 });
// pub const X25: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 25 });
// pub const X26: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 26 });
// pub const X27: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 27 });
// pub const X28: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 28 });
pub const X29: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 29 });
pub const X30: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::GP, reg_no: 30 });

pub const SP: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::STACK, reg_no: 31 });
// pub const XZR: YJitOpnd  = YJitOpnd::Reg(Aarc64Reg { num_bits: 64, reg_type: RegType::ZERO, reg_no: 31 });

//===========================================================================

/// Compute the number of bits needed to encode a signed value
pub fn sig_imm_size(imm: i64) -> u8
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

/// Compute the number of bits needed to encode an unsigned value
pub fn unsig_imm_size(imm: u64) -> u8
{
    // Compute the smallest size this immediate fits in
    if imm <= u8::MAX.into() {
        return 8;
    }
    else if imm <= u16::MAX.into() {
        return 16;
    }
    else if imm <= u32::MAX.into() {
        return 32;
    }

    return 64;
}

/// Shorthand for memory operand with base register and displacement
pub fn mem_opnd(num_bits: u8, base_reg: YJitOpnd, disp: i32) -> YJitOpnd
{
    let base_reg = match base_reg {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!()
    };

    YJitOpnd::Mem(
        Aarc64Mem {
            num_bits,
            base_reg_no: base_reg.reg_no,
            addressing: AddrType::Offset,
            disp,
        }
    )
}

pub fn mem_pre_opnd(num_bits: u8, base_reg: YJitOpnd, disp: i32) -> YJitOpnd {
    let base_reg = match base_reg {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!()
    };

    YJitOpnd::Mem(
        Aarc64Mem {
            num_bits,
            base_reg_no: base_reg.reg_no,
            addressing: AddrType::PreIdx,
            disp,
        }
    )
}

pub fn mem_post_opnd(num_bits: u8, base_reg: YJitOpnd, disp: i32) -> YJitOpnd {
    let base_reg = match base_reg {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!()
    };

    YJitOpnd::Mem(
        Aarc64Mem {
            num_bits,
            base_reg_no: base_reg.reg_no,
            addressing: AddrType::PostIdx,
            disp,
        }
    )
}

pub fn imm_opnd(value: i64) -> YJitOpnd
{
    YJitOpnd::Imm(Aarch64Imm { num_bits: sig_imm_size(value), value })
}

pub fn imm_shift_opnd(value: u32, shift_type: ShiftType, shift_num: u8) -> YJitOpnd
{
    YJitOpnd::ImmShift(Aarch64ImmShift { num_bits: unsig_imm_size(value as u64), value, shift_type, shift_num })
}

// call - Call a pointer, encode with a 32-bit offset if possible
#[allow(unused)]
pub fn call_ptr(_cb: &mut CodeBlock, _scratch_opnd: YJitOpnd, _dst_ptr: *const u8) {
    unreachable!();
}

pub fn gen_jump_ptr (_cb: &mut CodeBlock, _ptr: CodePtr) {
    unreachable!();
}

// ldr - Data load operation
pub fn ldr(cb: &mut CodeBlock, dst: YJitOpnd, src: YJitOpnd) {
    let src = match src {
        YJitOpnd::Mem(mem) => mem,
        _ => unreachable!(),
    };
    let dst = match dst {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!(),
    };
    assert!(dst.num_bits == 64);

    if src.disp % 8 != 0 {
        unreachable!("unimplemented: ldr with not 8 scaled offset");
    }
    if src.disp < 0 {
        unreachable!("unimplemented: ldr with negative offset");
    }
    if src.addressing != AddrType::Offset {
        unreachable!("unimplemented: ldr with not-offset addressing");
    }

    let disp = src.disp as u16;
    let uimm12:u16 = disp >> 3;
    // 31-24:  1 1 1 1 1 0 0 1
    // 23-16:  0 1 u_i_m_m_m_m
    // 15-08: _m_m_m_m_1_2 R_n
    // 07-00: _n_n_n R_t_t_t_t
    cb.write_bytes(&[
      dst.reg_no | (src.base_reg_no & 0x7) << 5,
      src.base_reg_no >> 3 | (uimm12 as u8 & 0x3f) << 2,
      (uimm12 >> 6) as u8 | 0x40,
      0xf9,
    ]);
}

// str - Data store operation
pub fn str(cb: &mut CodeBlock, src: YJitOpnd, dst: YJitOpnd) {
    let src = match src {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!(),
    };
    let dst = match dst {
        YJitOpnd::Mem(mem) => mem,
        _ => unreachable!(),
    };
    assert!(src.num_bits == 64);

    if dst.disp % 8 != 0 {
        unreachable!("unimplemented: str with not 8 scaled offset");
    }
    if dst.disp < 0 {
        unreachable!("unimplemented: str with negative offset");
    }
    if dst.addressing != AddrType::Offset {
        unreachable!("unimplemented: ldr with not-offset addressing");
    }

    let uimm12:u16 = (dst.disp >> 3) as u16;
    // 31-24:  1 1 1 1 1 0 0 1
    // 23-16:  0 0 u_i_m_m_m_m
    // 15-08: _m_m_m_m_1_2 R_n
    // 07-00: _n_n_n R_t_t_t_t
    cb.write_bytes(&[
      src.reg_no | (dst.base_reg_no & 0x7) << 5,
      dst.base_reg_no >> 3 | ((uimm12 & 0x3f) as u8) << 2,
      (uimm12 >> 6) as u8,
      0xf9
    ]);
}

// ldp - Data pair load operation
pub fn ldp(cb: &mut CodeBlock, dst1: YJitOpnd, dst2: YJitOpnd, src: YJitOpnd)
{
    let dst1 = match dst1 {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!()
    };
    let dst2 = match dst2 {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!()
    };
    let src = match src {
        YJitOpnd::Mem(mem) => mem,
        _ => unreachable!()
    };

    let z:bool = dst1.num_bits == 64;
    let imm7:u8 = (src.disp / (if z { 8 } else { 4 })) as u8 & 0x7f;

    // bit     7 6 5 4 3 2 1 0
    // 31-24:  z 0 1 0 1 0 A_d
    // 23-16: _r 1 i_m_m_7_7_7
    // 15-08: _7 R_t_2_2_2 R_n
    // 07-00: _n_n_n R_t_1_1_1
    cb.write_bytes(&[
      dst1.reg_no | (src.base_reg_no & 0x7) << 5,
      src.base_reg_no >> 3 | dst2.reg_no << 2 | (imm7 & 0x1) << 7,
      imm7 >> 1 | 0x40 | (src.addressing as u8 & 0x1) << 7,
      src.addressing as u8 >> 1 | (if z { 0xa8 } else { 0x28 })
    ]);
}

// stp - Data pair store operation
pub fn stp(cb: &mut CodeBlock, src1: YJitOpnd, src2: YJitOpnd, dst: YJitOpnd) {
    let src1 = match src1 {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!(),
    };
    let src2 = match src2 {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!(),
    };
    let dst = match dst {
        YJitOpnd::Mem(mem) => mem,
        _ => unreachable!(),
    };
    assert!(src1.num_bits == src2.num_bits);
    let z:bool = src1.num_bits == 64;
    let imm7:u8 = (dst.disp / (if z { 8 } else { 4 })) as u8 & 0x7f;

    // bit     7 6 5 4 3 2 1 0
    // 31-24:  z 0 1 0 1 0 A_d
    // 23-16: _r 0 i_m_m_7_7_7
    // 15-08: _7 R_t_2_2_2 R_n
    // 07-00: _n_n_n R_t_1_1_1
    cb.write_bytes(&[
        src1.reg_no | (dst.base_reg_no & 0x7) << 5,
        dst.base_reg_no >> 3 | src2.reg_no << 2 | (imm7 & 0x1) << 7,
        imm7 >> 1 | (dst.addressing as u8 & 0x1) << 7,
        dst.addressing as u8 >> 1 | (if z { 0xa8 } else { 0x28 }),
    ]);
}

// mov - Data move operation
pub fn mov(cb: &mut CodeBlock, dst: YJitOpnd, src: YJitOpnd) {
    let dst = match dst {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!(),
    };
    let src = match src {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!(),
    };

    let z: bool = dst.num_bits == 64;

    //         7 6 5 4 3 2 1 0
    // 31-24:  z 0 1 0 1 0 1 0
    // 23-16:  0 0 0 R_m_m_m_m
    // 15-08:  0 0_0 0 0 0 1 1
    // 07-00:  1 1 1 R_d_d_d_d
    cb.write_bytes(&[
      dst.reg_no | 0xe0,
      3,
      src.reg_no,
      if z { 0xaa } else { 0x2a }
    ]);
}

pub fn movz(cb: &mut CodeBlock, dst: YJitOpnd, src: YJitOpnd) {
    let dst = match dst {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!()
    };

    let z: bool = dst.num_bits == 64;
    let imm16:u16;
    let lsl:u8;

    match src {
      YJitOpnd::Imm(imm) => {
        lsl = 0;
        imm16 = imm.value as u16;
      },
      YJitOpnd::ImmShift(imm_shift) => {
        assert!(imm_shift.shift_type == ShiftType::LSL);
        lsl = imm_shift.shift_num;
        assert!(lsl == 0 || lsl == 16 || lsl == 32 || lsl == 48);
        imm16 = imm_shift.value as u16;
      },
      _ => unreachable!(),
    };

    //         7 6 5 4 3 2 1 0
    // 31-24:  z 1 0 1 0 0 1 0
    // 23-16:  1 h_w i_m_m_m_m
    // 15-08: _m_m_m_m_m_m_m_m
    // 07-00: _m_1_6 R_d_d_d_d
    cb.write_bytes(&[
      dst.reg_no | (imm16 as u8 & 0x0007) << 5,
      ((imm16 & 0x07f8) >> 3) as u8,
      (imm16 >> 11) as u8 | lsl << 1 | 0x80,
      if z { 0xd2 } else { 0x52 }
    ]);
}

// movk - Data move with keep operation
pub fn movk(cb: &mut CodeBlock, dst: YJitOpnd, src: YJitOpnd) {
    let dst = match dst {
        YJitOpnd::Reg(reg) => reg,
        _ => unreachable!()
    };

    let z: bool = dst.num_bits == 64;
    let imm16:u16;
    let lsl:u8;

    match src {
      YJitOpnd::Imm(imm) => {
        lsl = 0;
        imm16 = imm.value as u16;
      },
      YJitOpnd::ImmShift(imm_shift) => {
        assert!(imm_shift.shift_type == ShiftType::LSL);
        lsl = imm_shift.shift_num;
        assert!(lsl == 0 || lsl == 16 || lsl == 32 || lsl == 48);
        imm16 = imm_shift.value as u16;
      },
      _ => unreachable!(),
    };

    //         7 6 5 4 3 2 1 0
    // 31-24:  z 1 1 1 0 0 1 0
    // 23-16:  1 h_w i_m_m_m_m
    // 15-08: _m_m_m_m_m_m_m_m
    // 07-00: _m_1_6 R_d_d_d_d
    cb.write_bytes(&[
        dst.reg_no | (imm16 as u8 & 0x0007) << 5,
      ((imm16 & 0x07f8) >> 3) as u8,
      (imm16 >> 11) as u8 | lsl << 1 | 0x80,
      if z { 0xf2 } else { 0x72 }
    ]);
}

pub fn mov_u64(cb: &mut CodeBlock, dst: YJitOpnd, src: u64) {
    let mut imm = src;
    movz(cb, dst, imm_opnd((imm & 0xffff) as i64));
    imm = imm >> 16;
    if imm == 0 { return; }
    movk(cb, dst, imm_shift_opnd((imm & 0xffff) as u32, ShiftType::LSL, 16));
    imm = imm >> 16;
    if imm == 0 { return; }
    movk(cb, dst, imm_shift_opnd((imm & 0xffff) as u32, ShiftType::LSL, 32));
    imm = imm >> 16;
    if imm == 0 { return; }
    movk(cb, dst, imm_shift_opnd((imm & 0xffff) as u32, ShiftType::LSL, 48))
}

// ret - Return from call, popping only the return address
pub fn ret(cb: &mut CodeBlock, reg: YJitOpnd) {
    let reg = match reg {
        YJitOpnd::Reg(r) => r,
        _ => unreachable!()
    };
    cb.write_bytes(&[
        (reg.reg_no & 0x7) << 5,
        (reg.reg_no & 0x18) >> 3,
        0x5f,
        0xd6,
    ]);
}

// add - Add operation
pub fn add(cb: &mut CodeBlock, dst: YJitOpnd, src1: YJitOpnd, src2: YJitOpnd) {
    let (dst, src1) = match (dst, src1) {
        (YJitOpnd::Reg(reg1), YJitOpnd::Reg(reg2)) => (reg1, reg2),
        (_, _) => unreachable!()
    };

    let z: bool = dst.num_bits == 64;
    let imm12:u16;
    let sh:u8;

    match src2 {
      YJitOpnd::Imm(imm) => {
        sh = 0;
        imm12 = imm.value as u16 & 0xfff;
      },
      YJitOpnd::ImmShift(imm_shift) => {
        sh = imm_shift.shift_num / 12;
        assert!(imm_shift.shift_type == ShiftType::LSL);
        assert!(imm_shift.shift_num == 0 || imm_shift.shift_num == 12);
        imm12 = imm_shift.value as u16;
      },
      _ => unreachable!(),
    };

    //         7 6 5 4 3 2 1 0
    // 31-24:  z 0 0 1 0 0 0 1
    // 23-16:  s_h i_m_m_m_m_m
    // 15-08: _m_m_m_m_1_2 R_n
    // 07-00: _n_n_n R_d_d_d_d
    cb.write_bytes(&[
      dst.reg_no | (src1.reg_no & 0x7) << 5,
      src1.reg_no >> 3 | (imm12 as u8 & 0x3f) << 2,
      (imm12 >> 6) as u8 | sh,
      if z { 0x91 } else { 0x11 }
    ]);
}
