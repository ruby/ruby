// This module contains various A64 instructions and the logic necessary to
// encode them into u32s.

mod atomic;
mod branch;
mod branch_cond;
mod breakpoint;
mod call;
mod conditional;
mod data_imm;
mod data_reg;
mod halfword_imm;
mod load_literal;
mod load_register;
mod load_store;
mod logical_imm;
mod logical_reg;
mod mov;
mod nop;
mod pc_rel;
mod reg_pair;
mod sbfm;
mod shift_imm;
mod sys_reg;
mod test_bit;

pub use atomic::Atomic;
pub use branch::Branch;
pub use branch_cond::BranchCond;
pub use breakpoint::Breakpoint;
pub use call::Call;
pub use conditional::Conditional;
pub use data_imm::DataImm;
pub use data_reg::DataReg;
pub use halfword_imm::HalfwordImm;
pub use load_literal::LoadLiteral;
pub use load_register::LoadRegister;
pub use load_store::LoadStore;
pub use logical_imm::LogicalImm;
pub use logical_reg::LogicalReg;
pub use mov::Mov;
pub use nop::Nop;
pub use pc_rel::PCRelative;
pub use reg_pair::RegisterPair;
pub use sbfm::SBFM;
pub use shift_imm::ShiftImm;
pub use sys_reg::SysReg;
pub use test_bit::TestBit;
