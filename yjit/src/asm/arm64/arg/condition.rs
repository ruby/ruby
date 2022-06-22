/// Various instructions in A64 can have condition codes attached. This enum
/// includes all of the various kinds of conditions along with their respective
/// encodings.
pub enum Condition {
    EQ = 0b0000, // equal to
    NE = 0b0001, // not equal to
    CS = 0b0010, // carry set (alias for HS)
    CC = 0b0011, // carry clear (alias for LO)
    MI = 0b0100, // minus, negative
    PL = 0b0101, // positive or zero
    VS = 0b0110, // signed overflow
    VC = 0b0111, // no signed overflow
    HI = 0b1000, // greater than (unsigned)
    LS = 0b1001, // less than or equal to (unsigned)
    GE = 0b1010, // greater than or equal to (signed)
    LT = 0b1011, // less than (signed)
    GT = 0b1100, // greater than (signed)
    LE = 0b1101, // less than or equal to (signed)
    AL = 0b1110, // always
}
