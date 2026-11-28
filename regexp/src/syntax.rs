//! Options and the Ruby syntax (`OnigSyntaxRuby` in regparse.c). Only the
//! Ruby syntax exists here, but the flags are kept so that the parser reads
//! like regparse.c.

pub const ONIG_OPTION_NONE: u32 = 0;
pub const ONIG_OPTION_IGNORECASE: u32 = 1;
pub const ONIG_OPTION_EXTEND: u32 = ONIG_OPTION_IGNORECASE << 1;
pub const ONIG_OPTION_MULTILINE: u32 = ONIG_OPTION_EXTEND << 1;
pub const ONIG_OPTION_SINGLELINE: u32 = ONIG_OPTION_MULTILINE << 1;
pub const ONIG_OPTION_FIND_LONGEST: u32 = ONIG_OPTION_SINGLELINE << 1;
pub const ONIG_OPTION_FIND_NOT_EMPTY: u32 = ONIG_OPTION_FIND_LONGEST << 1;
pub const ONIG_OPTION_NEGATE_SINGLELINE: u32 = ONIG_OPTION_FIND_NOT_EMPTY << 1;
pub const ONIG_OPTION_DONT_CAPTURE_GROUP: u32 = ONIG_OPTION_NEGATE_SINGLELINE << 1;
pub const ONIG_OPTION_CAPTURE_GROUP: u32 = ONIG_OPTION_DONT_CAPTURE_GROUP << 1;
pub const ONIG_OPTION_NOTBOL: u32 = ONIG_OPTION_CAPTURE_GROUP << 1;
pub const ONIG_OPTION_NOTEOL: u32 = ONIG_OPTION_NOTBOL << 1;
pub const ONIG_OPTION_NOTBOS: u32 = ONIG_OPTION_NOTEOL << 1;
pub const ONIG_OPTION_NOTEOS: u32 = ONIG_OPTION_NOTBOS << 1;
pub const ONIG_OPTION_ASCII_RANGE: u32 = ONIG_OPTION_NOTEOS << 1;
pub const ONIG_OPTION_POSIX_BRACKET_ALL_RANGE: u32 = ONIG_OPTION_ASCII_RANGE << 1;
pub const ONIG_OPTION_WORD_BOUND_ALL_RANGE: u32 = ONIG_OPTION_POSIX_BRACKET_ALL_RANGE << 1;
pub const ONIG_OPTION_NEWLINE_CRLF: u32 = ONIG_OPTION_WORD_BOUND_ALL_RANGE << 1;

#[inline]
pub fn is_singleline(o: u32) -> bool {
    o & ONIG_OPTION_SINGLELINE != 0
}
#[inline]
pub fn is_multiline(o: u32) -> bool {
    o & ONIG_OPTION_MULTILINE != 0
}
#[inline]
pub fn is_ignorecase(o: u32) -> bool {
    o & ONIG_OPTION_IGNORECASE != 0
}
#[inline]
pub fn is_extend(o: u32) -> bool {
    o & ONIG_OPTION_EXTEND != 0
}
#[inline]
pub fn is_find_longest(o: u32) -> bool {
    o & ONIG_OPTION_FIND_LONGEST != 0
}
#[inline]
pub fn is_find_not_empty(o: u32) -> bool {
    o & ONIG_OPTION_FIND_NOT_EMPTY != 0
}
#[inline]
pub fn is_find_condition(o: u32) -> bool {
    o & (ONIG_OPTION_FIND_LONGEST | ONIG_OPTION_FIND_NOT_EMPTY) != 0
}
#[inline]
pub fn is_notbol(o: u32) -> bool {
    o & ONIG_OPTION_NOTBOL != 0
}
#[inline]
pub fn is_noteol(o: u32) -> bool {
    o & ONIG_OPTION_NOTEOL != 0
}
#[inline]
pub fn is_notbos(o: u32) -> bool {
    o & ONIG_OPTION_NOTBOS != 0
}
#[inline]
pub fn is_noteos(o: u32) -> bool {
    o & ONIG_OPTION_NOTEOS != 0
}
#[inline]
pub fn is_ascii_range(o: u32) -> bool {
    o & ONIG_OPTION_ASCII_RANGE != 0
}
#[inline]
pub fn is_posix_bracket_all_range(o: u32) -> bool {
    o & ONIG_OPTION_POSIX_BRACKET_ALL_RANGE != 0
}
#[inline]
pub fn is_word_bound_all_range(o: u32) -> bool {
    o & ONIG_OPTION_WORD_BOUND_ALL_RANGE != 0
}
#[inline]
pub fn is_newline_crlf(o: u32) -> bool {
    o & ONIG_OPTION_NEWLINE_CRLF != 0
}

// syntax (operators)
pub const ONIG_SYN_OP_VARIABLE_META_CHARACTERS: u32 = 1 << 0;
pub const ONIG_SYN_OP_DOT_ANYCHAR: u32 = 1 << 1;
pub const ONIG_SYN_OP_ASTERISK_ZERO_INF: u32 = 1 << 2;
pub const ONIG_SYN_OP_ESC_ASTERISK_ZERO_INF: u32 = 1 << 3;
pub const ONIG_SYN_OP_PLUS_ONE_INF: u32 = 1 << 4;
pub const ONIG_SYN_OP_ESC_PLUS_ONE_INF: u32 = 1 << 5;
pub const ONIG_SYN_OP_QMARK_ZERO_ONE: u32 = 1 << 6;
pub const ONIG_SYN_OP_ESC_QMARK_ZERO_ONE: u32 = 1 << 7;
pub const ONIG_SYN_OP_BRACE_INTERVAL: u32 = 1 << 8;
pub const ONIG_SYN_OP_ESC_BRACE_INTERVAL: u32 = 1 << 9;
pub const ONIG_SYN_OP_VBAR_ALT: u32 = 1 << 10;
pub const ONIG_SYN_OP_ESC_VBAR_ALT: u32 = 1 << 11;
pub const ONIG_SYN_OP_LPAREN_SUBEXP: u32 = 1 << 12;
pub const ONIG_SYN_OP_ESC_LPAREN_SUBEXP: u32 = 1 << 13;
pub const ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR: u32 = 1 << 14;
pub const ONIG_SYN_OP_ESC_CAPITAL_G_BEGIN_ANCHOR: u32 = 1 << 15;
pub const ONIG_SYN_OP_DECIMAL_BACKREF: u32 = 1 << 16;
pub const ONIG_SYN_OP_BRACKET_CC: u32 = 1 << 17;
pub const ONIG_SYN_OP_ESC_W_WORD: u32 = 1 << 18;
pub const ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END: u32 = 1 << 19;
pub const ONIG_SYN_OP_ESC_B_WORD_BOUND: u32 = 1 << 20;
pub const ONIG_SYN_OP_ESC_S_WHITE_SPACE: u32 = 1 << 21;
pub const ONIG_SYN_OP_ESC_D_DIGIT: u32 = 1 << 22;
pub const ONIG_SYN_OP_LINE_ANCHOR: u32 = 1 << 23;
pub const ONIG_SYN_OP_POSIX_BRACKET: u32 = 1 << 24;
pub const ONIG_SYN_OP_QMARK_NON_GREEDY: u32 = 1 << 25;
pub const ONIG_SYN_OP_ESC_CONTROL_CHARS: u32 = 1 << 26;
pub const ONIG_SYN_OP_ESC_C_CONTROL: u32 = 1 << 27;
pub const ONIG_SYN_OP_ESC_OCTAL3: u32 = 1 << 28;
pub const ONIG_SYN_OP_ESC_X_HEX2: u32 = 1 << 29;
pub const ONIG_SYN_OP_ESC_X_BRACE_HEX8: u32 = 1 << 30;
pub const ONIG_SYN_OP_ESC_O_BRACE_OCTAL: u32 = 1 << 31;

pub const ONIG_SYN_OP2_ESC_CAPITAL_Q_QUOTE: u32 = 1 << 0;
pub const ONIG_SYN_OP2_QMARK_GROUP_EFFECT: u32 = 1 << 1;
pub const ONIG_SYN_OP2_OPTION_PERL: u32 = 1 << 2;
pub const ONIG_SYN_OP2_OPTION_RUBY: u32 = 1 << 3;
pub const ONIG_SYN_OP2_PLUS_POSSESSIVE_REPEAT: u32 = 1 << 4;
pub const ONIG_SYN_OP2_PLUS_POSSESSIVE_INTERVAL: u32 = 1 << 5;
pub const ONIG_SYN_OP2_CCLASS_SET_OP: u32 = 1 << 6;
pub const ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP: u32 = 1 << 7;
pub const ONIG_SYN_OP2_ESC_K_NAMED_BACKREF: u32 = 1 << 8;
pub const ONIG_SYN_OP2_ESC_G_SUBEXP_CALL: u32 = 1 << 9;
pub const ONIG_SYN_OP2_ATMARK_CAPTURE_HISTORY: u32 = 1 << 10;
pub const ONIG_SYN_OP2_ESC_CAPITAL_C_BAR_CONTROL: u32 = 1 << 11;
pub const ONIG_SYN_OP2_ESC_CAPITAL_M_BAR_META: u32 = 1 << 12;
pub const ONIG_SYN_OP2_ESC_V_VTAB: u32 = 1 << 13;
pub const ONIG_SYN_OP2_ESC_U_HEX4: u32 = 1 << 14;
pub const ONIG_SYN_OP2_ESC_GNU_BUF_ANCHOR: u32 = 1 << 15;
pub const ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY: u32 = 1 << 16;
pub const ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT: u32 = 1 << 17;
pub const ONIG_SYN_OP2_ESC_H_XDIGIT: u32 = 1 << 19;
pub const ONIG_SYN_OP2_INEFFECTIVE_ESCAPE: u32 = 1 << 20;
pub const ONIG_SYN_OP2_ESC_CAPITAL_R_LINEBREAK: u32 = 1 << 21;
pub const ONIG_SYN_OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER: u32 = 1 << 22;
pub const ONIG_SYN_OP2_ESC_CAPITAL_K_KEEP: u32 = 1 << 25;
pub const ONIG_SYN_OP2_ESC_G_BRACE_BACKREF: u32 = 1 << 26;
pub const ONIG_SYN_OP2_QMARK_SUBEXP_CALL: u32 = 1 << 27;
pub const ONIG_SYN_OP2_QMARK_LPAREN_CONDITION: u32 = 1 << 29;
pub const ONIG_SYN_OP2_QMARK_CAPITAL_P_NAMED_GROUP: u32 = 1 << 30;
pub const ONIG_SYN_OP2_QMARK_TILDE_ABSENT: u32 = 1 << 31;

pub const ONIG_SYN_CONTEXT_INDEP_ANCHORS: u32 = 1 << 31;
pub const ONIG_SYN_CONTEXT_INDEP_REPEAT_OPS: u32 = 1 << 0;
pub const ONIG_SYN_CONTEXT_INVALID_REPEAT_OPS: u32 = 1 << 1;
pub const ONIG_SYN_ALLOW_UNMATCHED_CLOSE_SUBEXP: u32 = 1 << 2;
pub const ONIG_SYN_ALLOW_INVALID_INTERVAL: u32 = 1 << 3;
pub const ONIG_SYN_ALLOW_INTERVAL_LOW_ABBREV: u32 = 1 << 4;
pub const ONIG_SYN_STRICT_CHECK_BACKREF: u32 = 1 << 5;
pub const ONIG_SYN_DIFFERENT_LEN_ALT_LOOK_BEHIND: u32 = 1 << 6;
pub const ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP: u32 = 1 << 7;
pub const ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME: u32 = 1 << 8;
pub const ONIG_SYN_FIXED_INTERVAL_IS_GREEDY_ONLY: u32 = 1 << 9;
pub const ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME_CALL: u32 = 1 << 10;
pub const ONIG_SYN_USE_LEFT_MOST_NAMED_GROUP: u32 = 1 << 11;
pub const ONIG_SYN_NOT_NEWLINE_IN_NEGATIVE_CC: u32 = 1 << 20;
pub const ONIG_SYN_BACKSLASH_ESCAPE_IN_CC: u32 = 1 << 21;
pub const ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC: u32 = 1 << 22;
pub const ONIG_SYN_ALLOW_DOUBLE_RANGE_OP_IN_CC: u32 = 1 << 23;
pub const ONIG_SYN_WARN_CC_OP_NOT_ESCAPED: u32 = 1 << 24;
pub const ONIG_SYN_WARN_REDUNDANT_NESTED_REPEAT: u32 = 1 << 25;
pub const ONIG_SYN_WARN_CC_DUP: u32 = 1 << 26;

const SYN_GNU_REGEX_OP: u32 = ONIG_SYN_OP_DOT_ANYCHAR
    | ONIG_SYN_OP_BRACKET_CC
    | ONIG_SYN_OP_POSIX_BRACKET
    | ONIG_SYN_OP_DECIMAL_BACKREF
    | ONIG_SYN_OP_BRACE_INTERVAL
    | ONIG_SYN_OP_LPAREN_SUBEXP
    | ONIG_SYN_OP_VBAR_ALT
    | ONIG_SYN_OP_ASTERISK_ZERO_INF
    | ONIG_SYN_OP_PLUS_ONE_INF
    | ONIG_SYN_OP_QMARK_ZERO_ONE
    | ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR
    | ONIG_SYN_OP_ESC_CAPITAL_G_BEGIN_ANCHOR
    | ONIG_SYN_OP_ESC_W_WORD
    | ONIG_SYN_OP_ESC_B_WORD_BOUND
    | ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END
    | ONIG_SYN_OP_ESC_S_WHITE_SPACE
    | ONIG_SYN_OP_ESC_D_DIGIT
    | ONIG_SYN_OP_LINE_ANCHOR;

const SYN_GNU_REGEX_BV: u32 = ONIG_SYN_CONTEXT_INDEP_ANCHORS
    | ONIG_SYN_CONTEXT_INDEP_REPEAT_OPS
    | ONIG_SYN_CONTEXT_INVALID_REPEAT_OPS
    | ONIG_SYN_ALLOW_INVALID_INTERVAL
    | ONIG_SYN_BACKSLASH_ESCAPE_IN_CC
    | ONIG_SYN_ALLOW_DOUBLE_RANGE_OP_IN_CC;

pub struct Syntax {
    pub op: u32,
    pub op2: u32,
    pub behavior: u32,
    pub options: u32,
    pub esc: u32,
}

impl Syntax {
    #[inline]
    pub const fn op(&self, f: u32) -> bool {
        self.op & f != 0
    }
    #[inline]
    pub const fn op2(&self, f: u32) -> bool {
        self.op2 & f != 0
    }
    #[inline]
    pub const fn bv(&self, f: u32) -> bool {
        self.behavior & f != 0
    }
}

/// `OnigSyntaxRuby` with RUBY defined (no `\uHHHH`: re.c handles it).
pub static SYNTAX_RUBY: Syntax = Syntax {
    op: (SYN_GNU_REGEX_OP
        | ONIG_SYN_OP_QMARK_NON_GREEDY
        | ONIG_SYN_OP_ESC_OCTAL3
        | ONIG_SYN_OP_ESC_X_HEX2
        | ONIG_SYN_OP_ESC_X_BRACE_HEX8
        | ONIG_SYN_OP_ESC_CONTROL_CHARS
        | ONIG_SYN_OP_ESC_C_CONTROL)
        & !ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END,
    op2: ONIG_SYN_OP2_QMARK_GROUP_EFFECT
        | ONIG_SYN_OP2_OPTION_RUBY
        | ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP
        | ONIG_SYN_OP2_ESC_K_NAMED_BACKREF
        | ONIG_SYN_OP2_ESC_G_SUBEXP_CALL
        | ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY
        | ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT
        | ONIG_SYN_OP2_PLUS_POSSESSIVE_REPEAT
        | ONIG_SYN_OP2_CCLASS_SET_OP
        | ONIG_SYN_OP2_ESC_CAPITAL_C_BAR_CONTROL
        | ONIG_SYN_OP2_ESC_CAPITAL_M_BAR_META
        | ONIG_SYN_OP2_ESC_V_VTAB
        | ONIG_SYN_OP2_ESC_H_XDIGIT
        | ONIG_SYN_OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER
        | ONIG_SYN_OP2_QMARK_LPAREN_CONDITION
        | ONIG_SYN_OP2_ESC_CAPITAL_R_LINEBREAK
        | ONIG_SYN_OP2_ESC_CAPITAL_K_KEEP
        | ONIG_SYN_OP2_QMARK_TILDE_ABSENT,
    behavior: SYN_GNU_REGEX_BV
        | ONIG_SYN_ALLOW_INTERVAL_LOW_ABBREV
        | ONIG_SYN_DIFFERENT_LEN_ALT_LOOK_BEHIND
        | ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP
        | ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME
        | ONIG_SYN_FIXED_INTERVAL_IS_GREEDY_ONLY
        | ONIG_SYN_WARN_CC_OP_NOT_ESCAPED
        | ONIG_SYN_WARN_CC_DUP
        | ONIG_SYN_WARN_REDUNDANT_NESTED_REPEAT,
    options: ONIG_OPTION_ASCII_RANGE | ONIG_OPTION_POSIX_BRACKET_ALL_RANGE | ONIG_OPTION_WORD_BOUND_ALL_RANGE,
    esc: b'\\' as u32,
};
