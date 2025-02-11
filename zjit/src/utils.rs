/// The `Into<u64>` Rust does not provide.
/// Convert to u64 with assurance that the value is preserved.
/// Currently, `usize::BITS == 64` holds for all platforms we support.
pub(crate) trait IntoU64 {
    fn as_u64(self) -> u64;
}

#[cfg(target_pointer_width = "64")]
impl IntoU64 for usize {
    fn as_u64(self) -> u64 {
        self as u64
    }
}
