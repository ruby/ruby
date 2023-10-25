/// This is commonly the top-most bit in the encoding of the instruction, and
/// represents whether register operands should be treated as 64-bit registers
/// or 32-bit registers.
pub enum Sf {
    Sf32 = 0b0,
    Sf64 = 0b1
}

/// A convenience function so that we can convert the number of bits of an
/// register operand directly into an Sf enum variant.
impl From<u8> for Sf {
    fn from(num_bits: u8) -> Self {
        match num_bits {
            64 => Sf::Sf64,
            32 => Sf::Sf32,
            _ => panic!("Invalid number of bits: {}", num_bits)
        }
    }
}
