//! Compile-time constants that HIR can embed in instructions and, eventually, bake into machine
//! code.
//!
//! The representation of [`Const`] is private to this module with helpers exposed to help prevent
//! accidentally picking the wrong variant and baking a GC reference into generated code without
//! marking. See [`BakablePtr`].

use crate::cruby::{attr_index_t, ShapeId, VALUE};
use crate::bakable_ptr::BakablePtr;
use crate::hir::PtrPrintMap;

/// The shape of a [`Const`], for read-only matching.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ConstRepr {
    Value(VALUE),
    CBool(bool),
    CInt8(i8),
    CInt16(i16),
    CInt32(i32),
    CInt64(i64),
    CUInt8(u8),
    CUInt16(u16),
    CUInt32(u32),
    CAttrIndex(attr_index_t),
    CShape(ShapeId),
    CUInt64(u64),
    CPtr(*const u8),
    CDouble(f64),
}

/// A constant value in HIR. Construct with `value.into()` or helper associate functions.
#[derive(Clone, Copy, PartialEq)]
pub struct Const(/* not pub, crucially */ConstRepr);

macro_rules! impl_from {
    ($($ty:ty => $variant:ident),* $(,)?) => {
        $(
            impl From<$ty> for Const {
                fn from(val: $ty) -> Self {
                    Const(ConstRepr::$variant(val))
                }
            }
        )*
    };
}

impl_from! {
    VALUE => Value,
    bool => CBool,
    i8 => CInt8,
    i16 => CInt16,
    i32 => CInt32,
    i64 => CInt64,
    u8 => CUInt8,
    u16 => CUInt16,
    u32 => CUInt32,
    u64 => CUInt64,
    f64 => CDouble,
    ShapeId => CShape,
}

impl Const {
    /// The underlying representation, for matching.
    pub fn inner(self) -> ConstRepr {
        self.0
    }

    /// An instance variable index. `attr_index_t` is an alias for `u8`, so it needs a named
    /// constructor to get the `CAttrIndex` type instead of `CUInt8`.
    pub fn attr_index(index: attr_index_t) -> Self {
        Const(ConstRepr::CAttrIndex(index))
    }

    /// Bake a raw pointer. Only types on the [`BakablePtr`] allowlist are accepted; see the
    /// trait for what qualifies.
    pub fn cptr(ptr: impl BakablePtr) -> Self {
        Const(ConstRepr::CPtr(ptr.addr() as *const u8))
    }

    pub fn print<'a>(&'a self, ptr_map: &'a PtrPrintMap) -> ConstPrinter<'a> {
        ConstPrinter { inner: self, ptr_map }
    }
}

impl std::fmt::Debug for Const {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

impl std::fmt::Display for Const {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

/// Print adaptor for [`Const`]. See [`PtrPrintMap`].
pub struct ConstPrinter<'a> {
    inner: &'a Const,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for ConstPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self.inner.0 {
            ConstRepr::Value(val) => write!(f, "Value({})", val.print(self.ptr_map)),
            ConstRepr::CPtr(val) => write!(f, "CPtr({:p})", self.ptr_map.map_ptr(val)),
            ConstRepr::CShape(shape_id) => write!(f, "CShape({:p})", self.ptr_map.map_shape(shape_id)),
            ConstRepr::CUInt64(int) => {
                // Print in hex if signed bit is set
                if 0 != int & (1 << (u64::BITS - 1)) {
                    write!(f, "CUInt64(0x{int:x})")
                } else {
                    write!(f, "CUInt64({int})")
                }
            }
            repr => write!(f, "{repr:?}"),
        }
    }
}
