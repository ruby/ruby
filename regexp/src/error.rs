//! Error codes and messages, ported from regerror.c. The numeric values are
//! Onigmo's, so that C callers can keep using the `ONIGERR_*` constants.

use crate::enc::{CTYPE_CNTRL, CTYPE_PRINT, CTYPE_SPACE, Enc};

pub const ONIG_NORMAL: i32 = 0;
pub const ONIG_MISMATCH: i32 = -1;
pub const ONIG_NO_SUPPORT_CONFIG: i32 = -2;

pub const ONIGERR_MEMORY: i32 = -5;
pub const ONIGERR_TYPE_BUG: i32 = -6;
pub const ONIGERR_PARSER_BUG: i32 = -11;
pub const ONIGERR_STACK_BUG: i32 = -12;
pub const ONIGERR_UNDEFINED_BYTECODE: i32 = -13;
pub const ONIGERR_UNEXPECTED_BYTECODE: i32 = -14;
pub const ONIGERR_MATCH_STACK_LIMIT_OVER: i32 = -15;
pub const ONIGERR_PARSE_DEPTH_LIMIT_OVER: i32 = -16;
pub const ONIGERR_DEFAULT_ENCODING_IS_NOT_SET: i32 = -21;
pub const ONIGERR_SPECIFIED_ENCODING_CANT_CONVERT_TO_WIDE_CHAR: i32 = -22;
pub const ONIGERR_TIMEOUT: i32 = -23;
/// Not an Onigmo code: a Ruby interrupt is pending (see re_engine.c).
pub const RB_REGEXP_INTERRUPTED: i32 = -24;
/// Not an Onigmo code: the engine panicked.
pub const RB_REGEXP_PANICKED: i32 = -25;
/// The recursion of the parser or the compiler would leave the machine
/// stack; C raises SystemStackError.
pub const RB_REGEXP_STACK_OVERFLOW: i32 = -26;
pub const ONIGERR_INVALID_ARGUMENT: i32 = -30;
pub const ONIGERR_END_PATTERN_AT_LEFT_BRACE: i32 = -100;
pub const ONIGERR_END_PATTERN_AT_LEFT_BRACKET: i32 = -101;
pub const ONIGERR_EMPTY_CHAR_CLASS: i32 = -102;
pub const ONIGERR_PREMATURE_END_OF_CHAR_CLASS: i32 = -103;
pub const ONIGERR_END_PATTERN_AT_ESCAPE: i32 = -104;
pub const ONIGERR_END_PATTERN_AT_META: i32 = -105;
pub const ONIGERR_END_PATTERN_AT_CONTROL: i32 = -106;
pub const ONIGERR_META_CODE_SYNTAX: i32 = -108;
pub const ONIGERR_CONTROL_CODE_SYNTAX: i32 = -109;
pub const ONIGERR_CHAR_CLASS_VALUE_AT_END_OF_RANGE: i32 = -110;
pub const ONIGERR_CHAR_CLASS_VALUE_AT_START_OF_RANGE: i32 = -111;
pub const ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS: i32 = -112;
pub const ONIGERR_TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED: i32 = -113;
pub const ONIGERR_TARGET_OF_REPEAT_OPERATOR_INVALID: i32 = -114;
pub const ONIGERR_NESTED_REPEAT_OPERATOR: i32 = -115;
pub const ONIGERR_UNMATCHED_CLOSE_PARENTHESIS: i32 = -116;
pub const ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS: i32 = -117;
pub const ONIGERR_END_PATTERN_IN_GROUP: i32 = -118;
pub const ONIGERR_UNDEFINED_GROUP_OPTION: i32 = -119;
pub const ONIGERR_INVALID_POSIX_BRACKET_TYPE: i32 = -121;
pub const ONIGERR_INVALID_LOOK_BEHIND_PATTERN: i32 = -122;
pub const ONIGERR_INVALID_REPEAT_RANGE_PATTERN: i32 = -123;
pub const ONIGERR_INVALID_CONDITION_PATTERN: i32 = -124;
pub const ONIGERR_TOO_BIG_NUMBER: i32 = -200;
pub const ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE: i32 = -201;
pub const ONIGERR_UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE: i32 = -202;
pub const ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS: i32 = -203;
pub const ONIGERR_MISMATCH_CODE_LENGTH_IN_CLASS_RANGE: i32 = -204;
pub const ONIGERR_TOO_MANY_MULTI_BYTE_RANGES: i32 = -205;
pub const ONIGERR_TOO_SHORT_MULTI_BYTE_STRING: i32 = -206;
pub const ONIGERR_TOO_BIG_BACKREF_NUMBER: i32 = -207;
pub const ONIGERR_INVALID_BACKREF: i32 = -208;
pub const ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED: i32 = -209;
pub const ONIGERR_TOO_MANY_CAPTURE_GROUPS: i32 = -210;
pub const ONIGERR_TOO_SHORT_DIGITS: i32 = -211;
pub const ONIGERR_TOO_LONG_WIDE_CHAR_VALUE: i32 = -212;
pub const ONIGERR_EMPTY_GROUP_NAME: i32 = -214;
pub const ONIGERR_INVALID_GROUP_NAME: i32 = -215;
pub const ONIGERR_INVALID_CHAR_IN_GROUP_NAME: i32 = -216;
pub const ONIGERR_UNDEFINED_NAME_REFERENCE: i32 = -217;
pub const ONIGERR_UNDEFINED_GROUP_REFERENCE: i32 = -218;
pub const ONIGERR_MULTIPLEX_DEFINED_NAME: i32 = -219;
pub const ONIGERR_MULTIPLEX_DEFINITION_NAME_CALL: i32 = -220;
pub const ONIGERR_NEVER_ENDING_RECURSION: i32 = -221;
pub const ONIGERR_GROUP_NUMBER_OVER_FOR_CAPTURE_HISTORY: i32 = -222;
pub const ONIGERR_INVALID_CHAR_PROPERTY_NAME: i32 = -223;
pub const ONIGERR_TOO_MANY_RANGE_REPEAT: i32 = -224;
pub const ONIGERR_TOO_MANY_NULL_CHECK: i32 = -225;
pub const ONIGERR_TOO_BIG_COMPILED_PROGRAM: i32 = -226;
pub const ONIGERR_INVALID_CODE_POINT_VALUE: i32 = -400;
pub const ONIGERR_TOO_BIG_WIDE_CHAR_VALUE: i32 = -401;
pub const ONIGERR_NOT_SUPPORTED_ENCODING_COMBINATION: i32 = -402;
pub const ONIGERR_INVALID_COMBINATION_OF_OPTIONS: i32 = -403;

pub const ONIG_MAX_ERROR_MESSAGE_LEN: usize = 90;
/// < ONIG_MAX_ERROR_MESSAGE_LEN - max length of messages with %n
const MAX_ERROR_PAR_LEN: usize = 50;
const WARN_BUFSIZE: usize = 256;

/// `onig_error_code_to_format`.
pub fn error_code_to_format(code: i32) -> Option<&'static str> {
    if code >= 0 {
        return None;
    }
    Some(match code {
        ONIG_MISMATCH => "mismatch",
        ONIG_NO_SUPPORT_CONFIG => "no support in this configuration",
        ONIGERR_MEMORY => "failed to allocate memory",
        ONIGERR_TYPE_BUG => "undefined type (bug)",
        ONIGERR_PARSER_BUG => "internal parser error (bug)",
        ONIGERR_STACK_BUG => "stack error (bug)",
        ONIGERR_UNDEFINED_BYTECODE => "undefined bytecode (bug)",
        ONIGERR_UNEXPECTED_BYTECODE => "unexpected bytecode (bug)",
        ONIGERR_MATCH_STACK_LIMIT_OVER => "match-stack limit over",
        ONIGERR_PARSE_DEPTH_LIMIT_OVER => "parse depth limit over",
        ONIGERR_DEFAULT_ENCODING_IS_NOT_SET => "default multibyte-encoding is not set",
        ONIGERR_INVALID_ARGUMENT => "invalid argument",
        ONIGERR_END_PATTERN_AT_LEFT_BRACE => "end pattern at left brace",
        ONIGERR_EMPTY_CHAR_CLASS => "empty char-class",
        ONIGERR_PREMATURE_END_OF_CHAR_CLASS => "premature end of char-class",
        ONIGERR_END_PATTERN_AT_ESCAPE => "end pattern at escape",
        ONIGERR_END_PATTERN_AT_META => "end pattern at meta",
        ONIGERR_END_PATTERN_AT_CONTROL => "end pattern at control",
        ONIGERR_META_CODE_SYNTAX => "invalid meta-code syntax",
        ONIGERR_CONTROL_CODE_SYNTAX => "invalid control-code syntax",
        ONIGERR_CHAR_CLASS_VALUE_AT_END_OF_RANGE => "char-class value at end of range",
        ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS => "unmatched range specifier in char-class",
        ONIGERR_TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED => "target of repeat operator is not specified",
        ONIGERR_TARGET_OF_REPEAT_OPERATOR_INVALID => "target of repeat operator is invalid",
        ONIGERR_UNMATCHED_CLOSE_PARENTHESIS => "unmatched close parenthesis",
        ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS => "end pattern with unmatched parenthesis",
        ONIGERR_END_PATTERN_IN_GROUP => "end pattern in group",
        ONIGERR_UNDEFINED_GROUP_OPTION => "undefined group option",
        ONIGERR_INVALID_POSIX_BRACKET_TYPE => "invalid POSIX bracket type",
        ONIGERR_INVALID_LOOK_BEHIND_PATTERN => "invalid pattern in look-behind",
        ONIGERR_INVALID_REPEAT_RANGE_PATTERN => "invalid repeat range {lower,upper}",
        ONIGERR_INVALID_CONDITION_PATTERN => "invalid conditional pattern",
        ONIGERR_TOO_BIG_NUMBER => "too big number",
        ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE => "too big number for repeat range",
        ONIGERR_UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE => "upper is smaller than lower in repeat range",
        ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS => "empty range in char class",
        ONIGERR_TOO_MANY_MULTI_BYTE_RANGES => "too many multibyte code ranges are specified",
        ONIGERR_TOO_SHORT_MULTI_BYTE_STRING => "too short multibyte code string",
        ONIGERR_INVALID_BACKREF => "invalid backref number/name",
        ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED => "numbered backref/call is not allowed. (use name)",
        ONIGERR_TOO_SHORT_DIGITS => "too short digits",
        ONIGERR_TOO_LONG_WIDE_CHAR_VALUE => "too long wide-char value",
        ONIGERR_EMPTY_GROUP_NAME => "group name is empty",
        ONIGERR_INVALID_GROUP_NAME => "invalid group name <%n>",
        ONIGERR_INVALID_CHAR_IN_GROUP_NAME => "invalid char in group name <%n>",
        ONIGERR_UNDEFINED_NAME_REFERENCE => "undefined name <%n> reference",
        ONIGERR_UNDEFINED_GROUP_REFERENCE => "undefined group <%n> reference",
        ONIGERR_MULTIPLEX_DEFINED_NAME => "multiplex defined name <%n>",
        ONIGERR_MULTIPLEX_DEFINITION_NAME_CALL => "multiplex definition name <%n> call",
        ONIGERR_NEVER_ENDING_RECURSION => "never ending recursion",
        ONIGERR_INVALID_CHAR_PROPERTY_NAME => "invalid character property name {%n}",
        ONIGERR_TOO_MANY_RANGE_REPEAT => "too many range repeat",
        ONIGERR_TOO_MANY_NULL_CHECK => "too many null check",
        ONIGERR_TOO_BIG_COMPILED_PROGRAM => "too big compiled program",
        ONIGERR_TOO_MANY_CAPTURE_GROUPS => "too many capture groups are specified",
        ONIGERR_INVALID_CODE_POINT_VALUE => "invalid code point value",
        ONIGERR_TOO_BIG_WIDE_CHAR_VALUE => "too big wide-char value",
        ONIGERR_NOT_SUPPORTED_ENCODING_COMBINATION => "not supported encoding combination",
        ONIGERR_INVALID_COMBINATION_OF_OPTIONS => "invalid combination of options",
        _ => "undefined error code",
    })
}

fn push_hex(out: &mut Vec<u8>, v: u32, with_x: bool) {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    if with_x {
        out.extend_from_slice(b"\\x");
    }
    out.push(HEX[((v >> 4) & 0xf) as usize]);
    out.push(HEX[(v & 0xf) as usize]);
}

/// `to_ascii`: renders the `%n` parameter, as many whole characters as fit
/// in `buf_size` bytes. Returns (bytes, is_over).
fn to_ascii(enc: Enc, s: &[u8], buf_size: usize) -> (Vec<u8>, bool) {
    let end = s.len();
    let mut buf = Vec::new();
    let mut p = 0;
    while p < end && buf.len() < buf_size {
        let len = enc.enclen(s, p, end).max(1);
        if enc.min_len() > 1 {
            let code = enc.mbc_to_code(s, p, end);
            if code < 0x80 {
                buf.push(code as u8);
            } else if code > 0xffff {
                if buf.len() + 10 > buf_size {
                    break;
                }
                push_hex(&mut buf, code >> 24, true);
                push_hex(&mut buf, code >> 16, false);
                push_hex(&mut buf, code >> 8, false);
                push_hex(&mut buf, code, false);
            } else {
                if buf.len() + 6 > buf_size {
                    break;
                }
                push_hex(&mut buf, code >> 8, true);
                push_hex(&mut buf, code, false);
            }
        } else {
            if buf.len() + len > buf_size {
                break;
            }
            buf.extend_from_slice(&s[p..p + len]);
        }
        p += len;
    }
    (buf, p < end)
}

/// `onig_error_code_to_str`. `par` is the `%n` parameter for the codes
/// that take one.
pub fn error_code_to_str(code: i32, par: Option<(Enc, &[u8])>) -> Vec<u8> {
    match code {
        ONIGERR_UNDEFINED_NAME_REFERENCE
        | ONIGERR_UNDEFINED_GROUP_REFERENCE
        | ONIGERR_MULTIPLEX_DEFINED_NAME
        | ONIGERR_MULTIPLEX_DEFINITION_NAME_CALL
        | ONIGERR_INVALID_GROUP_NAME
        | ONIGERR_INVALID_CHAR_IN_GROUP_NAME
        | ONIGERR_INVALID_CHAR_PROPERTY_NAME => {
            let (parbuf, is_over) = match par {
                Some((enc, s)) => to_ascii(enc, s, MAX_ERROR_PAR_LEN - 3),
                None => (Vec::new(), false),
            };
            let fmt = error_code_to_format(code).unwrap_or("").as_bytes();
            let mut out = Vec::with_capacity(ONIG_MAX_ERROR_MESSAGE_LEN);
            let mut i = 0;
            while i < fmt.len() {
                if fmt[i] == b'%' && fmt.get(i + 1) == Some(&b'n') {
                    out.extend_from_slice(&parbuf);
                    if is_over {
                        out.extend_from_slice(b"...");
                    }
                    i += 2;
                } else {
                    out.push(fmt[i]);
                    i += 1;
                }
            }
            out
        }
        _ => error_code_to_format(code).map(|s| s.as_bytes().to_vec()).unwrap_or_default(),
    }
}

/// `onig_vsnprintf_with_pattern`: the warning text `msg`, followed by
/// `: /pattern/` when it fits in the buffer Onigmo uses.
pub fn message_with_pattern(enc: Enc, pat: &[u8], msg: &[u8]) -> Vec<u8> {
    let mut out = msg.to_vec();
    let need = pat.len() * 4 + 4;
    if msg.len() + need < WARN_BUFSIZE {
        out.extend_from_slice(b": /");
        let end = pat.len();
        let mut p = 0;
        while p < end {
            if enc.is_mbc_head(pat, p, end) {
                let len = enc.enclen(pat, p, end);
                if enc.min_len() == 1 {
                    out.extend_from_slice(&pat[p..p + len]);
                } else {
                    for &b in &pat[p..p + len] {
                        push_hex(&mut out, b as u32, true);
                    }
                }
                p += len.max(1);
            } else if pat[p] == b'\\' {
                out.push(pat[p]);
                p += 1;
                let len = enc.enclen(pat, p, end);
                out.extend_from_slice(&pat[p..p + len]);
                p += len;
            } else if pat[p] == b'/' {
                out.push(b'\\');
                out.push(pat[p]);
                p += 1;
            } else {
                let c = pat[p] as u32;
                if !enc.is_code_ctype(c, CTYPE_PRINT)
                    && (!enc.is_code_ctype(c, CTYPE_SPACE) || enc.is_code_ctype(c, CTYPE_CNTRL))
                {
                    push_hex(&mut out, c, true);
                } else {
                    out.push(pat[p]);
                }
                p += 1;
            }
        }
        out.push(b'/');
    }
    out
}
