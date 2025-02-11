// This module contains various A64 instruction arguments and the logic
// necessary to encode them.

mod bitmask_imm;
mod condition;
mod inst_offset;
mod sf;
mod shifted_imm;
mod sys_reg;
mod truncate;

pub use bitmask_imm::BitmaskImmediate;
#[cfg(target_arch = "aarch64")]
pub use condition::Condition;
pub use inst_offset::InstructionOffset;
pub use sf::Sf;
pub use shifted_imm::ShiftedImmediate;
pub use sys_reg::SystemRegister;
pub use truncate::{truncate_imm, truncate_uimm};
