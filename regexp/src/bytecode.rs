//! Opcodes and operand layout of the compiled program, identical to Onigmo
//! (`enum OpCode` and the `SIZE_*` macros of regint.h). The program is a
//! byte vector; operands are stored unaligned in native byte order, which is
//! what `PLATFORM_UNALIGNED_WORD_ACCESS` builds of Onigmo produce. Keeping
//! the layout lets the two engines' programs be compared byte for byte.

pub const OP_FINISH: u8 = 0;
pub const OP_END: u8 = 1;
pub const OP_EXACT1: u8 = 2;
pub const OP_EXACT2: u8 = 3;
pub const OP_EXACT3: u8 = 4;
pub const OP_EXACT4: u8 = 5;
pub const OP_EXACT5: u8 = 6;
pub const OP_EXACTN: u8 = 7;
pub const OP_EXACTMB2N1: u8 = 8;
pub const OP_EXACTMB2N2: u8 = 9;
pub const OP_EXACTMB2N3: u8 = 10;
pub const OP_EXACTMB2N: u8 = 11;
pub const OP_EXACTMB3N: u8 = 12;
pub const OP_EXACTMBN: u8 = 13;
pub const OP_EXACT1_IC: u8 = 14;
pub const OP_EXACTN_IC: u8 = 15;
pub const OP_CCLASS: u8 = 16;
pub const OP_CCLASS_MB: u8 = 17;
pub const OP_CCLASS_MIX: u8 = 18;
pub const OP_CCLASS_NOT: u8 = 19;
pub const OP_CCLASS_MB_NOT: u8 = 20;
pub const OP_CCLASS_MIX_NOT: u8 = 21;
pub const OP_ANYCHAR: u8 = 22;
pub const OP_ANYCHAR_ML: u8 = 23;
pub const OP_ANYCHAR_STAR: u8 = 24;
pub const OP_ANYCHAR_ML_STAR: u8 = 25;
pub const OP_ANYCHAR_STAR_PEEK_NEXT: u8 = 26;
pub const OP_ANYCHAR_ML_STAR_PEEK_NEXT: u8 = 27;
pub const OP_WORD: u8 = 28;
pub const OP_NOT_WORD: u8 = 29;
pub const OP_WORD_BOUND: u8 = 30;
pub const OP_NOT_WORD_BOUND: u8 = 31;
pub const OP_WORD_BEGIN: u8 = 32;
pub const OP_WORD_END: u8 = 33;
pub const OP_ASCII_WORD: u8 = 34;
pub const OP_NOT_ASCII_WORD: u8 = 35;
pub const OP_ASCII_WORD_BOUND: u8 = 36;
pub const OP_NOT_ASCII_WORD_BOUND: u8 = 37;
pub const OP_ASCII_WORD_BEGIN: u8 = 38;
pub const OP_ASCII_WORD_END: u8 = 39;
pub const OP_BEGIN_BUF: u8 = 40;
pub const OP_END_BUF: u8 = 41;
pub const OP_BEGIN_LINE: u8 = 42;
pub const OP_END_LINE: u8 = 43;
pub const OP_SEMI_END_BUF: u8 = 44;
pub const OP_BEGIN_POSITION: u8 = 45;
pub const OP_BACKREF1: u8 = 46;
pub const OP_BACKREF2: u8 = 47;
pub const OP_BACKREFN: u8 = 48;
pub const OP_BACKREFN_IC: u8 = 49;
pub const OP_BACKREF_MULTI: u8 = 50;
pub const OP_BACKREF_MULTI_IC: u8 = 51;
pub const OP_BACKREF_WITH_LEVEL: u8 = 52;
pub const OP_MEMORY_START: u8 = 53;
pub const OP_MEMORY_START_PUSH: u8 = 54;
pub const OP_MEMORY_END_PUSH: u8 = 55;
pub const OP_MEMORY_END_PUSH_REC: u8 = 56;
pub const OP_MEMORY_END: u8 = 57;
pub const OP_MEMORY_END_REC: u8 = 58;
pub const OP_KEEP: u8 = 59;
pub const OP_FAIL: u8 = 60;
pub const OP_JUMP: u8 = 61;
pub const OP_PUSH: u8 = 62;
pub const OP_POP: u8 = 63;
pub const OP_PUSH_OR_JUMP_EXACT1: u8 = 64;
pub const OP_PUSH_IF_PEEK_NEXT: u8 = 65;
pub const OP_REPEAT: u8 = 66;
pub const OP_REPEAT_NG: u8 = 67;
pub const OP_REPEAT_INC: u8 = 68;
pub const OP_REPEAT_INC_NG: u8 = 69;
pub const OP_REPEAT_INC_SG: u8 = 70;
pub const OP_REPEAT_INC_NG_SG: u8 = 71;
pub const OP_NULL_CHECK_START: u8 = 72;
pub const OP_NULL_CHECK_END: u8 = 73;
pub const OP_NULL_CHECK_END_MEMST: u8 = 74;
pub const OP_NULL_CHECK_END_MEMST_PUSH: u8 = 75;
pub const OP_PUSH_POS: u8 = 76;
pub const OP_POP_POS: u8 = 77;
pub const OP_PUSH_POS_NOT: u8 = 78;
pub const OP_FAIL_POS: u8 = 79;
pub const OP_PUSH_STOP_BT: u8 = 80;
pub const OP_POP_STOP_BT: u8 = 81;
pub const OP_LOOK_BEHIND: u8 = 82;
pub const OP_PUSH_LOOK_BEHIND_NOT: u8 = 83;
pub const OP_FAIL_LOOK_BEHIND_NOT: u8 = 84;
pub const OP_PUSH_ABSENT_POS: u8 = 85;
pub const OP_ABSENT: u8 = 86;
pub const OP_ABSENT_END: u8 = 87;
pub const OP_CALL: u8 = 88;
pub const OP_RETURN: u8 = 89;
pub const OP_CONDITION: u8 = 90;
pub const OP_STATE_CHECK_PUSH: u8 = 91;
pub const OP_STATE_CHECK_PUSH_OR_JUMP: u8 = 92;
pub const OP_STATE_CHECK: u8 = 93;
pub const OP_STATE_CHECK_ANYCHAR_STAR: u8 = 94;
pub const OP_STATE_CHECK_ANYCHAR_ML_STAR: u8 = 95;
pub const OP_SET_OPTION_PUSH: u8 = 96;
pub const OP_SET_OPTION: u8 = 97;

pub const SIZE_OPCODE: i64 = 1;
pub const SIZE_RELADDR: i64 = 4;
pub const SIZE_ABSADDR: i64 = 4;
pub const SIZE_LENGTH: i64 = 4;
pub const SIZE_MEMNUM: i64 = 2;
pub const SIZE_OPTION: i64 = 4;
pub const SIZE_CODE_POINT: i64 = 4;
pub const SIZE_BITSET: i64 = 32;

pub const SIZE_OP_ANYCHAR_STAR: i64 = SIZE_OPCODE;
pub const SIZE_OP_ANYCHAR_STAR_PEEK_NEXT: i64 = SIZE_OPCODE + 1;
pub const SIZE_OP_JUMP: i64 = SIZE_OPCODE + SIZE_RELADDR;
pub const SIZE_OP_PUSH: i64 = SIZE_OPCODE + SIZE_RELADDR;
pub const SIZE_OP_POP: i64 = SIZE_OPCODE;
pub const SIZE_OP_PUSH_OR_JUMP_EXACT1: i64 = SIZE_OPCODE + SIZE_RELADDR + 1;
pub const SIZE_OP_PUSH_IF_PEEK_NEXT: i64 = SIZE_OPCODE + SIZE_RELADDR + 1;
pub const SIZE_OP_REPEAT_INC: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_REPEAT_INC_NG: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_PUSH_POS: i64 = SIZE_OPCODE;
pub const SIZE_OP_PUSH_POS_NOT: i64 = SIZE_OPCODE + SIZE_RELADDR;
pub const SIZE_OP_POP_POS: i64 = SIZE_OPCODE;
pub const SIZE_OP_FAIL_POS: i64 = SIZE_OPCODE;
pub const SIZE_OP_SET_OPTION: i64 = SIZE_OPCODE + SIZE_OPTION;
pub const SIZE_OP_SET_OPTION_PUSH: i64 = SIZE_OPCODE + SIZE_OPTION;
pub const SIZE_OP_FAIL: i64 = SIZE_OPCODE;
pub const SIZE_OP_MEMORY_START: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_MEMORY_START_PUSH: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_MEMORY_END_PUSH: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_MEMORY_END_PUSH_REC: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_MEMORY_END: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_MEMORY_END_REC: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_PUSH_STOP_BT: i64 = SIZE_OPCODE;
pub const SIZE_OP_POP_STOP_BT: i64 = SIZE_OPCODE;
pub const SIZE_OP_NULL_CHECK_START: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_NULL_CHECK_END: i64 = SIZE_OPCODE + SIZE_MEMNUM;
pub const SIZE_OP_LOOK_BEHIND: i64 = SIZE_OPCODE + SIZE_LENGTH;
pub const SIZE_OP_PUSH_LOOK_BEHIND_NOT: i64 = SIZE_OPCODE + SIZE_RELADDR + SIZE_LENGTH;
pub const SIZE_OP_FAIL_LOOK_BEHIND_NOT: i64 = SIZE_OPCODE;
pub const SIZE_OP_CALL: i64 = SIZE_OPCODE + SIZE_ABSADDR;
pub const SIZE_OP_RETURN: i64 = SIZE_OPCODE;
pub const SIZE_OP_CONDITION: i64 = SIZE_OPCODE + SIZE_MEMNUM + SIZE_RELADDR;
pub const SIZE_OP_PUSH_ABSENT_POS: i64 = SIZE_OPCODE;
pub const SIZE_OP_ABSENT: i64 = SIZE_OPCODE + SIZE_RELADDR;
pub const SIZE_OP_ABSENT_END: i64 = SIZE_OPCODE;

/// `MAX_COMPILED_PROGRAM_SIZE`: offsets must stay well inside `int`.
pub const MAX_COMPILED_PROGRAM_SIZE: usize = (i32::MAX / 4) as usize;

/// Bounds-checked operand reads. A read past the end of the program means
/// the compiler emitted a broken program, which is a bug, so it panics.
#[derive(Clone, Copy)]
pub struct Reader<'a> {
    pub p: &'a [u8],
}

impl<'a> Reader<'a> {
    #[inline]
    pub fn u8(&self, at: usize) -> u8 {
        self.p[at]
    }
    #[inline]
    pub fn i16(&self, at: usize) -> i16 {
        i16::from_ne_bytes(self.p[at..at + 2].try_into().unwrap())
    }
    #[inline]
    pub fn i32(&self, at: usize) -> i32 {
        i32::from_ne_bytes(self.p[at..at + 4].try_into().unwrap())
    }
    #[inline]
    pub fn u32(&self, at: usize) -> u32 {
        u32::from_ne_bytes(self.p[at..at + 4].try_into().unwrap())
    }
    #[inline]
    pub fn bytes(&self, at: usize, len: usize) -> &'a [u8] {
        &self.p[at..at + len]
    }
}
