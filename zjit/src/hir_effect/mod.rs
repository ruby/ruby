//! High-level intermediate representation effects.

#![allow(non_upper_case_globals)]
use crate::hir::{PtrPrintMap};

// NOTE: Effect very intentionally does not support Eq or PartialEq; we almost never want to check
// bit equality of types in the compiler but instead check subtyping, intersection, union, etc.
#[derive(Copy, Clone, Debug)]
/// The main work horse of effect inference and specialization. The main interfaces
/// will look like:
///
/// * is effect A a subset of effect B
/// * union/meet effect A and effect B
///
/// Most questions can be rewritten in terms of these operations.

// TODO(Jacob): Fix up comments for Effect and EffectPair
// Make it clear why we need both of these. Effect handles all lattice operations
// EffectPair is our typical use case because we care about having both read and write effects
pub struct Effect {
    bits: u64
}

pub struct EffectPair {
    /// Unlike ZJIT's type system, effects do not have a notion of subclasses.
    /// Instead of specializations, the Effects struct contains two Effect bitsets.
    /// We have read and write bitsets, both representing the same lattice.
    ///
    /// TODO(Jacob): Provide an example about why we split based on read / write
    /// TODO(Jacob): Provide an example about what some set of bits means.
    /// TODO(Jacob): Provide a graphic or description about the lattice structure
    /// This should include top, bottom, and how you move up or down in between
    ///
    /// These fields should not be directly read or written except by internal `Effect` APIs.
    read_bits: Effect,
    write_bits: Effect
}

include!("hir_effect.inc.rs");


/// Print adaptor for [`BitSet`]. See [`PtrPrintMap`].
pub struct EffectPrinter<'a> {
    inner: Effect,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for EffectPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let effect = self.inner;
        // TODO(Jacob): Is it better to have 2*n in terms of list traversals, or allocate 1 bitset?
        // We could just remove this first loop through and make the function simpler. This seems better to me?
        //
        // If there's an exact match, write and return
        for (name, pattern) in bits::AllBitPatterns {
            if effect.bits == pattern {
                // TODO(Jacob): Figure out if this is horrible rust
                write!(f, "{name}")?;
                return Ok(());
            }
        }
        // Otherwise, find the most descriptive sub-effect write it, and mask out the handled bits.
        // Most descriptive means "highest number of bits set while remaining fully contained within `effect`"
        debug_assert!(bits::AllBitPatterns.is_sorted_by(|(_, left), (_, right)| left > right));
        let mut bits = effect.bits;
        let mut sep = "";
        for (name, pattern) in bits::AllBitPatterns {
            if bits == 0 { break; }
            if (bits & pattern) == pattern {
                write!(f, "{sep}{name}")?;
                sep = "|";
                bits &= !pattern;
            }
        }
        debug_assert_eq!(bits, 0, "Should have eliminated all bits by iterating over all patterns");
        Ok(())
    }
}

// TODO(Jacob): Add EffectPairPrinter that just calls out to EffectPrinter twice
// TODO(Jacob): Add functions for effect pair. print differing effects in the pair

impl std::fmt::Display for Effect {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

impl Effect {
    // TODO(Jacob): Double check this comment below that was pulled from types
    /// Private. Only for creating effect globals.
    const fn from_bits(bits: u64) -> Effect {
        Effect {
            bits
        }
    }

    pub fn union(&self, other: Effect) -> Effect {
        Effect::from_bits(self.bits | other.bits)
    }

    pub fn intersect(&self, other: Effect) -> Effect {
        Effect::from_bits(self.bits & other.bits)
    }

    pub fn exclude(&self, other: Effect) -> Effect {
        Effect::from_bits(self.bits - (self.bits & other.bits))
    }

    // TODO(Jacob): Rewrite comment and see if this is intended to be used or not. We don't have subtypes...
    /// Check bit equality of two `Type`s. Do not use! You are probably looking for [`Effect::includes`].
    pub fn bit_equal(&self, other: Effect) -> bool {
        self.bits == other.bits
    }

    pub fn includes(&self, other: Effect) -> bool {
        self.bit_equal(Effect::union(self, other))
    }

    pub fn overlaps(&self, other: Effect) -> bool {
        !self.intersect(other).bit_equal(effects::None)
    }

    pub fn print(self, ptr_map: &PtrPrintMap) -> EffectPrinter<'_> {
        EffectPrinter { inner: self, ptr_map }
    }
}

// TODO(Jacob): Review and remake all tests for effects
#[cfg(test)]
mod tests {
    use super::*;
    use crate::cruby::rust_str_to_ruby;
    use crate::cruby::rust_str_to_sym;
    use crate::cruby::rb_ary_new_capa;
    use crate::cruby::rb_hash_new;
    use crate::cruby::rb_float_new;
    use crate::cruby::define_class;
    use crate::cruby::rb_cObject;
    use crate::cruby::rb_cSet;
    use crate::cruby::rb_cTrueClass;
    use crate::cruby::rb_cFalseClass;
    use crate::cruby::rb_cNilClass;

    #[track_caller]
    fn assert_bit_equal(left: Type, right: Type) {
        assert_eq!(left.bits, right.bits, "{left} bits are not equal to {right} bits");
        assert_eq!(left.spec, right.spec, "{left} spec is not equal to {right} spec");
    }

    #[track_caller]
    fn assert_subtype(left: Type, right: Type) {
        assert!(left.is_subtype(right), "{left} is not a subtype of {right}");
    }

    #[track_caller]
    fn assert_not_subtype(left: Type, right: Type) {
        assert!(!left.is_subtype(right), "{left} is a subtype of {right}");
    }

    #[test]
    fn empty_is_subtype_of_everything() {
        // Spot check a few cases
        assert_subtype(types::Empty, types::NilClass);
        assert_subtype(types::Empty, types::Array);
        assert_subtype(types::Empty, types::Object);
        assert_subtype(types::Empty, types::CUInt16);
        assert_subtype(types::Empty, Type::from_cint(types::CInt32, 10));
        assert_subtype(types::Empty, types::Any);
        assert_subtype(types::Empty, types::Empty);
    }

    #[test]
    fn everything_is_a_subtype_of_any() {
        // Spot check a few cases
        assert_subtype(types::NilClass, types::Any);
        assert_subtype(types::Array, types::Any);
        assert_subtype(types::Object, types::Any);
        assert_subtype(types::CUInt16, types::Any);
        assert_subtype(Type::from_cint(types::CInt32, 10), types::Any);
        assert_subtype(types::Empty, types::Any);
        assert_subtype(types::Any, types::Any);
    }

    #[test]
    fn integer() {
        assert_subtype(Type::fixnum(123), types::Fixnum);
        assert_subtype(Type::fixnum(123), Type::fixnum(123));
        assert_not_subtype(Type::fixnum(123), Type::fixnum(200));
        assert_subtype(Type::from_value(VALUE::fixnum_from_usize(123)), types::Fixnum);
        assert_subtype(types::Fixnum, types::Integer);
        assert_subtype(types::Bignum, types::Integer);
    }

    #[test]
    fn float() {
        assert_subtype(types::Flonum, types::Float);
        assert_subtype(types::HeapFloat, types::Float);
    }

    #[test]
    fn numeric() {
        assert_subtype(types::Integer, types::Numeric);
        assert_subtype(types::Float, types::Numeric);
        assert_subtype(types::Float.union(types::Integer), types::Numeric);
        assert_bit_equal(types::Float
            .union(types::Integer)
            .union(types::NumericExact)
            .union(types::NumericSubclass), types::Numeric);
    }

    #[test]
    fn symbol() {
        assert_subtype(types::StaticSymbol, types::Symbol);
        assert_subtype(types::DynamicSymbol, types::Symbol);
    }

    #[test]
    fn immediate() {
        assert_subtype(Type::fixnum(123), types::Immediate);
        assert_subtype(types::Fixnum, types::Immediate);
        assert_not_subtype(types::Bignum, types::Immediate);
        assert_not_subtype(types::Integer, types::Immediate);
        assert_subtype(types::NilClass, types::Immediate);
        assert_subtype(types::TrueClass, types::Immediate);
        assert_subtype(types::FalseClass, types::Immediate);
        assert_subtype(types::StaticSymbol, types::Immediate);
        assert_not_subtype(types::DynamicSymbol, types::Immediate);
        assert_subtype(types::Flonum, types::Immediate);
        assert_not_subtype(types::HeapFloat, types::Immediate);
    }

    #[test]
    fn heap_basic_object() {
        assert_not_subtype(Type::fixnum(123), types::HeapBasicObject);
        assert_not_subtype(types::Fixnum, types::HeapBasicObject);
        assert_subtype(types::Bignum, types::HeapBasicObject);
        assert_not_subtype(types::Integer, types::HeapBasicObject);
        assert_not_subtype(types::NilClass, types::HeapBasicObject);
        assert_not_subtype(types::TrueClass, types::HeapBasicObject);
        assert_not_subtype(types::FalseClass, types::HeapBasicObject);
        assert_not_subtype(types::StaticSymbol, types::HeapBasicObject);
        assert_subtype(types::DynamicSymbol, types::HeapBasicObject);
        assert_not_subtype(types::Flonum, types::HeapBasicObject);
        assert_subtype(types::HeapFloat, types::HeapBasicObject);
        assert_not_subtype(types::BasicObject, types::HeapBasicObject);
        assert_not_subtype(types::Object, types::HeapBasicObject);
        assert_not_subtype(types::Immediate, types::HeapBasicObject);
        assert_not_subtype(types::HeapBasicObject, types::Immediate);
        crate::cruby::with_rubyvm(|| {
            let left = Type::from_value(rust_str_to_ruby("hello"));
            let right = Type::from_value(rust_str_to_ruby("world"));
            assert_subtype(left, types::HeapBasicObject);
            assert_subtype(right, types::HeapBasicObject);
            assert_subtype(left.union(right), types::HeapBasicObject);
        });
    }

    #[test]
    fn heap_object() {
        assert_not_subtype(Type::fixnum(123), types::HeapObject);
        assert_not_subtype(types::Fixnum, types::HeapObject);
        assert_subtype(types::Bignum, types::HeapObject);
        assert_not_subtype(types::Integer, types::HeapObject);
        assert_not_subtype(types::NilClass, types::HeapObject);
        assert_not_subtype(types::TrueClass, types::HeapObject);
        assert_not_subtype(types::FalseClass, types::HeapObject);
        assert_not_subtype(types::StaticSymbol, types::HeapObject);
        assert_subtype(types::DynamicSymbol, types::HeapObject);
        assert_not_subtype(types::Flonum, types::HeapObject);
        assert_subtype(types::HeapFloat, types::HeapObject);
        assert_not_subtype(types::BasicObject, types::HeapObject);
        assert_not_subtype(types::Object, types::HeapObject);
        assert_not_subtype(types::Immediate, types::HeapObject);
        assert_not_subtype(types::HeapObject, types::Immediate);
        crate::cruby::with_rubyvm(|| {
            let left = Type::from_value(rust_str_to_ruby("hello"));
            let right = Type::from_value(rust_str_to_ruby("world"));
            assert_subtype(left, types::HeapObject);
            assert_subtype(right, types::HeapObject);
            assert_subtype(left.union(right), types::HeapObject);
        });
    }

    #[test]
    fn fixnum_has_ruby_object() {
        assert_eq!(Type::fixnum(3).ruby_object(), Some(VALUE::fixnum_from_usize(3)));
        assert_eq!(types::Fixnum.ruby_object(), None);
        assert_eq!(types::Integer.ruby_object(), None);
    }

    #[test]
    fn singletons_do_not_have_ruby_object() {
        assert_eq!(Type::from_value(Qnil).ruby_object(), None);
        assert_eq!(types::NilClass.ruby_object(), None);
        assert_eq!(Type::from_value(Qtrue).ruby_object(), None);
        assert_eq!(types::TrueClass.ruby_object(), None);
        assert_eq!(Type::from_value(Qfalse).ruby_object(), None);
        assert_eq!(types::FalseClass.ruby_object(), None);
    }

    #[test]
    fn integer_has_exact_ruby_class() {
        assert_eq!(Type::fixnum(3).exact_ruby_class(), Some(unsafe { rb_cInteger }));
        assert_eq!(types::Fixnum.exact_ruby_class(), None);
        assert_eq!(types::Integer.exact_ruby_class(), None);
    }

    #[test]
    fn singletons_do_not_have_exact_ruby_class() {
        assert_eq!(Type::from_value(Qnil).exact_ruby_class(), None);
        assert_eq!(types::NilClass.exact_ruby_class(), None);
        assert_eq!(Type::from_value(Qtrue).exact_ruby_class(), None);
        assert_eq!(types::TrueClass.exact_ruby_class(), None);
        assert_eq!(Type::from_value(Qfalse).exact_ruby_class(), None);
        assert_eq!(types::FalseClass.exact_ruby_class(), None);
    }

    #[test]
    fn singletons_do_not_have_ruby_class() {
        assert_eq!(Type::from_value(Qnil).inexact_ruby_class(), None);
        assert_eq!(types::NilClass.inexact_ruby_class(), None);
        assert_eq!(Type::from_value(Qtrue).inexact_ruby_class(), None);
        assert_eq!(types::TrueClass.inexact_ruby_class(), None);
        assert_eq!(Type::from_value(Qfalse).inexact_ruby_class(), None);
        assert_eq!(types::FalseClass.inexact_ruby_class(), None);
    }

    #[test]
    fn from_class() {
        crate::cruby::with_rubyvm(|| {
            assert_bit_equal(Type::from_class(unsafe { rb_cInteger }), types::Integer);
            assert_bit_equal(Type::from_class(unsafe { rb_cString }), types::StringExact);
            assert_bit_equal(Type::from_class(unsafe { rb_cArray }), types::ArrayExact);
            assert_bit_equal(Type::from_class(unsafe { rb_cHash }), types::HashExact);
            assert_bit_equal(Type::from_class(unsafe { rb_cNilClass }), types::NilClass);
            assert_bit_equal(Type::from_class(unsafe { rb_cTrueClass }), types::TrueClass);
            assert_bit_equal(Type::from_class(unsafe { rb_cFalseClass }), types::FalseClass);
            let c_class = define_class("C", unsafe { rb_cObject });
            assert_bit_equal(Type::from_class(c_class), Type { bits: bits::HeapObject, spec: Specialization::TypeExact(c_class) });
        });
    }

    #[test]
    fn integer_has_ruby_class() {
        crate::cruby::with_rubyvm(|| {
            assert_eq!(Type::fixnum(3).inexact_ruby_class(), Some(unsafe { rb_cInteger }));
            assert_eq!(types::Fixnum.inexact_ruby_class(), None);
            assert_eq!(types::Integer.inexact_ruby_class(), None);
        });
    }

    #[test]
    fn set() {
        assert_subtype(types::SetExact, types::Set);
        assert_subtype(types::SetSubclass, types::Set);
    }

    #[test]
    fn set_has_ruby_class() {
        crate::cruby::with_rubyvm(|| {
            assert_eq!(types::SetExact.runtime_exact_ruby_class(), Some(unsafe { rb_cSet }));
            assert_eq!(types::Set.runtime_exact_ruby_class(), None);
            assert_eq!(types::SetSubclass.runtime_exact_ruby_class(), None);
        });
    }

    #[test]
    fn display_exact_bits_match() {
        assert_eq!(format!("{}", Type::fixnum(4)), "Fixnum[4]");
        assert_eq!(format!("{}", Type::from_cint(types::CInt8, -1)), "CInt8[-1]");
        assert_eq!(format!("{}", Type::from_cint(types::CUInt8, -1)), "CUInt8[255]");
        assert_eq!(format!("{}", Type::from_cint(types::CInt16, -1)), "CInt16[-1]");
        assert_eq!(format!("{}", Type::from_cint(types::CUInt16, -1)), "CUInt16[65535]");
        assert_eq!(format!("{}", Type::from_cint(types::CInt32, -1)), "CInt32[-1]");
        assert_eq!(format!("{}", Type::from_cint(types::CUInt32, -1)), "CUInt32[4294967295]");
        assert_eq!(format!("{}", Type::from_cint(types::CInt64, -1)), "CInt64[-1]");
        assert_eq!(format!("{}", Type::from_cint(types::CUInt64, -1)), "CUInt64[18446744073709551615]");
        assert_eq!(format!("{}", Type::from_cbool(true)), "CBool[true]");
        assert_eq!(format!("{}", Type::from_cbool(false)), "CBool[false]");
        assert_eq!(format!("{}", types::Fixnum), "Fixnum");
        assert_eq!(format!("{}", types::Integer), "Integer");
    }

    #[test]
    fn display_multiple_bits() {
        assert_eq!(format!("{}", types::CSigned), "CSigned");
        assert_eq!(format!("{}", types::CUInt8.union(types::CInt32)), "CUInt8|CInt32");
        assert_eq!(format!("{}", types::HashExact.union(types::HashSubclass)), "Hash");
    }

    #[test]
    fn union_equal() {
        assert_bit_equal(types::Fixnum.union(types::Fixnum), types::Fixnum);
        assert_bit_equal(Type::fixnum(3).union(Type::fixnum(3)), Type::fixnum(3));
    }

    #[test]
    fn union_bits_subtype() {
        assert_bit_equal(types::Fixnum.union(types::Integer), types::Integer);
        assert_bit_equal(types::Fixnum.union(types::Object), types::Object);
        assert_bit_equal(Type::fixnum(3).union(types::Fixnum), types::Fixnum);

        assert_bit_equal(types::Integer.union(types::Fixnum), types::Integer);
        assert_bit_equal(types::Object.union(types::Fixnum), types::Object);
        assert_bit_equal(types::Fixnum.union(Type::fixnum(3)), types::Fixnum);
    }

    #[test]
    fn union_bits_unions_bits() {
        assert_bit_equal(types::Fixnum.union(types::StaticSymbol), Type { bits: bits::Fixnum | bits::StaticSymbol, spec: Specialization::Any });
    }

    #[test]
    fn union_int_specialized() {
        assert_bit_equal(Type::from_cbool(true).union(Type::from_cbool(true)), Type::from_cbool(true));
        assert_bit_equal(Type::from_cbool(true).union(Type::from_cbool(false)), types::CBool);
        assert_bit_equal(Type::from_cbool(true).union(types::CBool), types::CBool);

        assert_bit_equal(Type::from_cbool(false).union(Type::from_cbool(true)), types::CBool);
        assert_bit_equal(types::CBool.union(Type::from_cbool(true)), types::CBool);
    }

    #[test]
    fn union_one_type_specialized_returns_unspecialized() {
        crate::cruby::with_rubyvm(|| {
            let specialized = Type::from_value(unsafe { rb_ary_new_capa(0) });
            let unspecialized = types::StringExact;
            assert_bit_equal(specialized.union(unspecialized), Type { bits: bits::ArrayExact | bits::StringExact, spec: Specialization::Any });
            assert_bit_equal(unspecialized.union(specialized), Type { bits: bits::ArrayExact | bits::StringExact, spec: Specialization::Any });
        });
    }

    #[test]
    fn union_specialized_builtin_subtype_returns_unspecialized() {
        crate::cruby::with_rubyvm(|| {
            let hello = Type::from_value(rust_str_to_ruby("hello"));
            let world = Type::from_value(rust_str_to_ruby("world"));
            assert_bit_equal(hello.union(world), types::StringExact);
        });
        crate::cruby::with_rubyvm(|| {
            let hello = Type::from_value(rust_str_to_sym("hello"));
            let world = Type::from_value(rust_str_to_sym("world"));
            assert_bit_equal(hello.union(world), types::StaticSymbol);
        });
        crate::cruby::with_rubyvm(|| {
            let left = Type::from_value(rust_str_to_ruby("hello"));
            let right = Type::from_value(rust_str_to_ruby("hello"));
            assert_bit_equal(left.union(right), types::StringExact);
        });
        crate::cruby::with_rubyvm(|| {
            let left = Type::from_value(rust_str_to_sym("hello"));
            let right = Type::from_value(rust_str_to_sym("hello"));
            assert_bit_equal(left.union(right), left);
        });
        crate::cruby::with_rubyvm(|| {
            let left = Type::from_value(unsafe { rb_ary_new_capa(0) });
            let right = Type::from_value(unsafe { rb_ary_new_capa(0) });
            assert_bit_equal(left.union(right), types::ArrayExact);
        });
        crate::cruby::with_rubyvm(|| {
            let left = Type::from_value(unsafe { rb_hash_new() });
            let right = Type::from_value(unsafe { rb_hash_new() });
            assert_bit_equal(left.union(right), types::HashExact);
        });
        crate::cruby::with_rubyvm(|| {
            let left = Type::from_value(unsafe { rb_float_new(1.0) });
            let right = Type::from_value(unsafe { rb_float_new(2.0) });
            assert_bit_equal(left.union(right), types::Flonum);
        });
        crate::cruby::with_rubyvm(|| {
            let left = Type::from_value(unsafe { rb_float_new(1.7976931348623157e+308) });
            let right = Type::from_value(unsafe { rb_float_new(1.7976931348623157e+308) });
            assert_bit_equal(left.union(right), types::HeapFloat);
        });
    }

    #[test]
    fn cme() {
        use crate::cruby::{rb_callable_method_entry, ID};
        crate::cruby::with_rubyvm(|| {
            let cme = unsafe { rb_callable_method_entry(rb_cInteger, ID!(to_s)) };
            assert!(!cme.is_null());
            let cme_value: VALUE = cme.into();
            let ty = Type::from_value(cme_value);
            assert_subtype(ty, types::CallableMethodEntry);
            assert!(ty.ruby_object_known());
        });
    }

    #[test]
    fn string_subclass_is_string_subtype() {
        crate::cruby::with_rubyvm(|| {
            assert_subtype(types::StringExact, types::String);
            assert_subtype(Type::from_class(unsafe { rb_cString }), types::String);
            assert_subtype(Type::from_class(unsafe { rb_cString }), types::StringExact);
            let c_class = define_class("C", unsafe { rb_cString });
            assert_subtype(Type::from_class(c_class), types::String);
        });
    }

    #[test]
    fn union_specialized_with_no_relation_returns_unspecialized() {
        crate::cruby::with_rubyvm(|| {
            let string = Type::from_value(rust_str_to_ruby("hello"));
            let array = Type::from_value(unsafe { rb_ary_new_capa(0) });
            assert_bit_equal(string.union(array), Type { bits: bits::ArrayExact | bits::StringExact, spec: Specialization::Any });
        });
    }

    #[test]
    fn union_specialized_with_subclass_relationship_returns_superclass() {
        crate::cruby::with_rubyvm(|| {
            let c_class = define_class("C", unsafe { rb_cObject });
            let d_class = define_class("D", c_class);
            let c_instance = Type { bits: bits::ObjectSubclass, spec: Specialization::TypeExact(c_class) };
            let d_instance = Type { bits: bits::ObjectSubclass, spec: Specialization::TypeExact(d_class) };
            assert_bit_equal(c_instance.union(c_instance), Type { bits: bits::ObjectSubclass, spec: Specialization::TypeExact(c_class)});
            assert_bit_equal(c_instance.union(d_instance), Type { bits: bits::ObjectSubclass, spec: Specialization::Type(c_class)});
            assert_bit_equal(d_instance.union(c_instance), Type { bits: bits::ObjectSubclass, spec: Specialization::Type(c_class)});
        });
    }
}
