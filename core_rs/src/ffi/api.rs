//! Public C API of CRuby used by Wave B ports, categorized into
//! [`non_raising`] and [`raising`] submodules.
//!
//! Non-raising functions and static exception handles are re-exported at `api::*`
//! for backwards compatibility. Raising functions are kept strictly inside
//! `api::raising::*` to enforce explicit opt-in and compile-time boundaries.

pub mod non_raising;
pub mod raising;

pub use self::non_raising::*;
pub use self::raising::UnprotectedTag;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_non_raising_exports_accessible() {
        // Test that non-raising items are accessible via api::* re-export.
        let _ = rb_errinfo as unsafe extern "C" fn() -> crate::ffi::value::VALUE;
        let _ = rb_set_errinfo as unsafe extern "C" fn(crate::ffi::value::VALUE);
        let _ = rb_obj_class as unsafe extern "C" fn(crate::ffi::value::VALUE) -> crate::ffi::value::VALUE;
        let _ = rb_int2inum as unsafe extern "C" fn(isize) -> crate::ffi::value::VALUE;
        let _ = rb_uint2inum as unsafe extern "C" fn(usize) -> crate::ffi::value::VALUE;
    }

    #[test]
    fn test_unprotected_tag_creation() {
        let tag = unsafe { UnprotectedTag::unsafe_new() };
        let tag_copy = tag;
        assert_eq!(tag, tag_copy);
    }

    #[test]
    fn test_raising_functions_accessible_under_raising_submodule() {
        use super::raising::*;
        let _ = rb_raise as unsafe extern "C" fn(crate::ffi::value::VALUE, *const core::ffi::c_char, ...) -> !;
        let _ = rb_num2long as unsafe extern "C" fn(crate::ffi::value::VALUE) -> core::ffi::c_long;
        let _ = rb_num2ulong as unsafe extern "C" fn(crate::ffi::value::VALUE) -> core::ffi::c_ulong;
        let _ = rb_num2dbl as unsafe extern "C" fn(crate::ffi::value::VALUE) -> core::ffi::c_double;
        let _ = rb_funcallv as unsafe extern "C" fn(
            crate::ffi::value::VALUE,
            crate::ffi::value::ID,
            core::ffi::c_int,
            *const crate::ffi::value::VALUE,
        ) -> crate::ffi::value::VALUE;
        let _ = rb_ary_push as unsafe extern "C" fn(
            crate::ffi::value::VALUE,
            crate::ffi::value::VALUE,
        ) -> crate::ffi::value::VALUE;
    }
}
