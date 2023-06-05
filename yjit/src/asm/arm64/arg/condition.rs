/// Various instructions in A64 can have condition codes attached. This enum
/// includes all of the various kinds of conditions along with their respective
/// encodings.
pub struct Condition;

impl Condition {
    pub const EQ: u8 = 0b0000; // equal to
    pub const NE: u8 = 0b0001; // not equal to
    pub const CS: u8 = 0b0010; // carry set (alias for HS)
    pub const CC: u8 = 0b0011; // carry clear (alias for LO)
    pub const MI: u8 = 0b0100; // minus, negative
    pub const PL: u8 = 0b0101; // positive or zero
    pub const VS: u8 = 0b0110; // signed overflow
    pub const VC: u8 = 0b0111; // no signed overflow
    pub const HI: u8 = 0b1000; // greater than (unsigned)
    pub const LS: u8 = 0b1001; // less than or equal to (unsigned)
    pub const GE: u8 = 0b1010; // greater than or equal to (signed)
    pub const LT: u8 = 0b1011; // less than (signed)
    pub const GT: u8 = 0b1100; // greater than (signed)
    pub const LE: u8 = 0b1101; // less than or equal to (signed)
    pub const AL: u8 = 0b1110; // always

    pub const fn inverse(condition: u8) -> u8 {
        match condition {
            Condition::EQ => Condition::NE,
            Condition::NE => Condition::EQ,

            Condition::CS => Condition::CC,
            Condition::CC => Condition::CS,

            Condition::MI => Condition::PL,
            Condition::PL => Condition::MI,

            Condition::VS => Condition::VC,
            Condition::VC => Condition::VS,

            Condition::HI => Condition::LS,
            Condition::LS => Condition::HI,

            Condition::LT => Condition::GE,
            Condition::GE => Condition::LT,

            Condition::GT => Condition::LE,
            Condition::LE => Condition::GT,

            Condition::AL => Condition::AL,

            _ => panic!("Unknown condition")

        }
    }
}
