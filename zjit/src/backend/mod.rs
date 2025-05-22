#[cfg(target_arch = "x86_64")]
pub mod x86_64;

#[cfg(target_arch = "aarch64")]
pub mod arm64;

#[cfg(target_arch = "x86_64")]
pub use x86_64 as current;

#[cfg(target_arch = "aarch64")]
pub use arm64 as current;

pub mod lir;
