//! The allowlist of raw pointer types that may be baked into generated code.

use std::ffi::c_void;

use crate::codegen::IseqCall;
use crate::cruby::{
    iseq_inline_constant_cache, iseq_inline_cvar_cache_entry, iseq_inline_iv_cache_entry,
    rb_call_data, zjit_jit_frame, VALUE,
};

/// A trait for functions that take a raw pointer of any pointee type, to disable coercion of
/// `&*const T` into `*const *const T`. This is implemented for `*const/mut T`, but rules for
/// coercing into `impl Trait` don't consider the underlying type, so we avoid the undesirable
/// coercion. (It would be weird for the treatment of a trait to change based on the set of types
/// that implements it since Rust has a nominal type system.)
pub trait OneLevelPtr: Copy {
    /// Get the address component of the pointer.
    fn addr(self) -> usize;
    /// The layout of the pointed-to type.
    fn pointee_layout(self) -> std::alloc::Layout;
}

impl<T> OneLevelPtr for *const T {
    fn addr(self) -> usize {
        <*const T>::addr(self)
    }

    fn pointee_layout(self) -> std::alloc::Layout {
        std::alloc::Layout::new::<T>()
    }
}

impl<T> OneLevelPtr for *mut T {
    fn addr(self) -> usize {
        <*mut T>::addr(self)
    }

    fn pointee_layout(self) -> std::alloc::Layout {
        std::alloc::Layout::new::<T>()
    }
}

/// Marker trait that forms an allowlist of raw pointer types which may be baked into generated code.
/// Types on the list enjoy nice looking helper functions, making subtle baking mistakes
/// syntactically loud and easy to spot in comparison. (Watch out for `as` casts!)
///
/// A baked pointer is emitted as a plain immediate the GC neither sees. Baking what ought to
/// be GC traceable as a plain pointer is a class of bugs. Implement this for non-GC stable heap
/// memory.
pub trait BakablePtr: OneLevelPtr {
    /// Bake the pointer as an LIR operand.
    fn bake_ptr(self) -> crate::backend::lir::Opnd {
        crate::backend::lir::Opnd::UImm(self.addr() as u64)
    }
}

/// Untyped memory: C function pointers, `CString`s, and the like.
impl BakablePtr for *const u8 {}
/// Opaque C structs such as the GC's objspace.
impl BakablePtr for *const c_void {}
/// A program counter, pointing into an iseq's `malloc`ed `iseq_encoded` array.
impl BakablePtr for *const VALUE {}
/// Same as `*const VALUE`; `rb_iseq_pc_at_idx` returns a `*mut VALUE`.
impl BakablePtr for *mut VALUE {}
/// Stats counters we manage.
impl BakablePtr for *mut u64 {}
/// Call data in the iseq's `malloc`ed `call_data` array.
impl BakablePtr for *const rb_call_data {}
/// Inline caches in the iseq's `malloc`ed `is_entries` array.
impl BakablePtr for *const iseq_inline_constant_cache {}
/// Inline caches in the iseq's `malloc`ed `is_entries` array.
impl BakablePtr for *const iseq_inline_iv_cache_entry {}
/// Inline caches in the iseq's `malloc`ed `is_entries` array.
impl BakablePtr for *const iseq_inline_cvar_cache_entry {}
/// JIT frame metadata we manage.
impl BakablePtr for *const zjit_jit_frame {}
/// JIT-to-JIT call metadata we manage
impl BakablePtr for *const IseqCall {}

// Now for things that are *not* allowed...
// Just comments since we don't have feature(negative_impls).
//
// Every imemo type from `enum imemo_type` in internal/imemo.h is really a `VALUE` that needs
// marking, so none of their pointer types may be baked.
//
// imemo_ment
// impl !BakablePtr for *const rb_method_entry_t {}
// impl !BakablePtr for *const rb_callable_method_entry_t {}
//
// imemo_iseq
// impl !BakablePtr for *const rb_iseq_t {}
//
// imemo_callinfo
// impl !BakablePtr for *const rb_callinfo {}
//
// imemo_callcache
// impl !BakablePtr for *const rb_callcache {}
//
// imemo_constcache
// `iseq_inline_constant_cache`, which is the inline cache slot pointing to one of these.
// impl !BakablePtr for *const iseq_inline_constant_cache_entry {}
//
// imemo_cdhash
// impl !BakablePtr for *const rb_imemo_cdhash {}
//
// imemo_env
// impl !BakablePtr for *const rb_env_t {}
// imemo_cref
// impl !BakablePtr for *const rb_cref_t {}
// imemo_svar
// impl !BakablePtr for *const vm_svar {}
// imemo_throw_data
// impl !BakablePtr for *const vm_throw_data {}
// imemo_ifunc
// impl !BakablePtr for *const vm_ifunc {}
// imemo_memo
// impl !BakablePtr for *const MEMO {}
// imemo_tmpbuf
// impl !BakablePtr for *const rb_imemo_tmpbuf_t {}
// imemo_cvar_entry
// impl !BakablePtr for *const rb_cvar_class_tbl_entry {}
// imemo_fields
// impl !BakablePtr for *const rb_fields {}
// imemo_subclasses
// impl !BakablePtr for *const rb_subclasses {}
