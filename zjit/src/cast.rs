/// Trait for casting to [usize] that allows you to say `.as_usize()`.
/// Implementation conditional on the cast preserving the numeric value on
/// all inputs and being inexpensive.
///
/// [usize] is only guaranteed to be more than 16-bit wide, so we can't use
/// `.into()` to cast an `u32` or an `u64` to a `usize` even though in all
/// the platforms we support these casts are pretty much no-ops.
/// We could say `as usize` or `.try_convert().unwrap()` everywhere for these
/// casts but both options have undesirable consequences if and when we decide to
/// support 32-bit platforms. Unfortunately we can't implement [::core::convert::From]
/// for [usize] since both the trait and the type are external. Also, naming
/// the method `into()` also causes a name conflict.
pub(crate) trait IntoUsize {
    /// Convert to usize. Implementation conditional on width of [usize].
    fn as_usize(self) -> usize;
}

#[cfg(target_pointer_width = "64")]
impl IntoUsize for u64 {
    fn as_usize(self) -> usize {
        self as usize
    }
}

#[cfg(target_pointer_width = "64")]
impl IntoUsize for u32 {
    fn as_usize(self) -> usize {
        self as usize
    }
}

impl IntoUsize for u16 {
    /// Alias for `.into()`. For convenience so you could use the trait for
    /// all unsgined types.
    fn as_usize(self) -> usize {
        self.into()
    }
}

impl IntoUsize for u8 {
    /// Alias for `.into()`. For convenience so you could use the trait for
    /// all unsgined types.
    fn as_usize(self) -> usize {
        self.into()
    }
}

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
