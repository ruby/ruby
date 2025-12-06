mod bits {
  pub const Any: u8 = World;
  pub const Frame: u8 = Locals | PC | Stack;
  pub const Locals: u8 = 1u8 << 0;
  pub const None: u8 = 0u8;
  pub const Other: u8 = 1u8 << 1;
  pub const PC: u8 = 1u8 << 2;
  pub const Stack: u8 = 1u8 << 3;
  pub const World: u8 = Frame | Other;
  pub const AllBitPatterns: [(&str, u8); 8] = [
    ("World", World),
    ("Any", Any),
    ("Frame", Frame),
    ("Stack", Stack),
    ("PC", PC),
    ("Other", Other),
    ("Locals", Locals),
    ("None", None),
  ];
  pub const NumEffectBits: u8 = 4;
}
pub mod effects {
  use super::*;
  pub const Any: Effect = Effect::from_bits(bits::Any);
  pub const Frame: Effect = Effect::from_bits(bits::Frame);
  pub const Locals: Effect = Effect::from_bits(bits::Locals);
  pub const None: Effect = Effect::from_bits(bits::None);
  pub const Other: Effect = Effect::from_bits(bits::Other);
  pub const PC: Effect = Effect::from_bits(bits::PC);
  pub const Stack: Effect = Effect::from_bits(bits::Stack);
  pub const World: Effect = Effect::from_bits(bits::World);
}
