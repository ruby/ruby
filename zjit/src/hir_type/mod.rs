#![allow(non_upper_case_globals)]
use crate::cruby::{Qfalse, Qnil, Qtrue, VALUE, RUBY_T_ARRAY, RUBY_T_STRING, RUBY_T_HASH, RUBY_T_CLASS, RUBY_T_MODULE};
use crate::cruby::{rb_cInteger, rb_cFloat, rb_cArray, rb_cHash, rb_cString, rb_cSymbol, rb_cObject, rb_cTrueClass, rb_cFalseClass, rb_cNilClass, rb_cRange, rb_cSet, rb_cRegexp, rb_cClass, rb_cModule};
use crate::cruby::ClassRelationship;
use crate::cruby::get_class_name;
use crate::cruby::ruby_sym_to_rust_string;
use crate::cruby::rb_mRubyVMFrozenCore;
use crate::cruby::rb_obj_class;
use crate::hir::PtrPrintMap;

#[derive(Copy, Clone, Debug, PartialEq)]
/// Specialization of the type. If we know additional information about the object, we put it here.
/// This includes information about its value as a cvalue. For Ruby objects, type specialization
/// is split into three sub-cases:
///
/// * Object, where we know exactly what object (pointer) the Type corresponds to
/// * Type exact, where we know exactly what class the Type represents (which could be because we
///   have an instance of it; includes Object specialization)
/// * Type, where we know that the Type could represent the given class or any of its subclasses
///
/// It is also a lattice but a much shallower one. It is not meant to be used directly, just by
/// Type internals.
pub enum Specialization {
    /// We know nothing about the specialization of this Type.
    Any,
    /// We know that this Type is an instance of the given Ruby class in the VALUE or any of its subclasses.
    Type(VALUE),
    /// We know that this Type is an instance of exactly the Ruby class in the VALUE.
    TypeExact(VALUE),
    /// We know that this Type is exactly the Ruby object in the VALUE.
    Object(VALUE),
    /// We know that this Type is exactly the given cvalue/C integer value (use the type bits to
    /// inform how we should interpret the u64, e.g. as CBool or CInt32).
    Int(u64),
    /// We know that this Type is exactly the given cvalue/C double.
    Double(f64),
    /// We know that the Type is [`types::Empty`] and therefore the instruction that produces this
    /// value never returns.
    Empty,
}

// NOTE: Type very intentionally does not support Eq or PartialEq; we almost never want to check
// bit equality of types in the compiler but instead check subtyping, intersection, union, etc.
#[derive(Copy, Clone, Debug)]
/// The main work horse of intraprocedural type inference and specialization. The main interfaces
/// will look like:
///
/// * is type A a subset of type B
/// * union/meet type A and type B
///
/// Most questions can be rewritten in terms of these operations.
pub struct Type {
    /// A bitset representing type information about the object. Specific bits are assigned for
    /// leaf types (for example, static symbols) and union-ing bitsets together represents
    /// union-ing sets of types. These sets form a lattice (with Any as "could be anything" and
    /// Empty as "can be nothing").
    ///
    /// Capable of also representing cvalue types (bool, i32, etc).
    ///
    /// This field should not be directly read or written except by internal `Type` APIs.
    bits: u64,
    /// Specialization of the type. See [`Specialization`].
    ///
    /// This field should not be directly read or written except by internal `Type` APIs.
    spec: Specialization
}

include!("hir_type.inc.rs");

fn write_spec(f: &mut std::fmt::Formatter, printer: &TypePrinter) -> std::fmt::Result {
    let ty = printer.inner;
    match ty.spec {
        Specialization::Any | Specialization::Empty => { Ok(()) },
        Specialization::Object(val) if val == unsafe { rb_mRubyVMFrozenCore } => write!(f, "[VMFrozenCore]"),
        Specialization::Object(val) if ty.is_subtype(types::SymbolExact) => write!(f, "[:{}]", ruby_sym_to_rust_string(val)),
        Specialization::Object(val) => write!(f, "[{}]", val.print(printer.ptr_map)),
        Specialization::Type(val) => write!(f, "[class:{}]", get_class_name(val)),
        Specialization::TypeExact(val) => write!(f, "[class_exact:{}]", get_class_name(val)),
        Specialization::Int(val) if ty.is_subtype(types::CBool) => write!(f, "[{}]", val != 0),
        Specialization::Int(val) if ty.is_subtype(types::CInt8) => write!(f, "[{}]", (val as i64) >> 56),
        Specialization::Int(val) if ty.is_subtype(types::CInt16) => write!(f, "[{}]", (val as i64) >> 48),
        Specialization::Int(val) if ty.is_subtype(types::CInt32) => write!(f, "[{}]", (val as i64) >> 32),
        Specialization::Int(val) if ty.is_subtype(types::CInt64) => write!(f, "[{}]", val as i64),
        Specialization::Int(val) if ty.is_subtype(types::CUInt8) => write!(f, "[{}]", val >> 56),
        Specialization::Int(val) if ty.is_subtype(types::CUInt16) => write!(f, "[{}]", val >> 48),
        Specialization::Int(val) if ty.is_subtype(types::CUInt32) => write!(f, "[{}]", val >> 32),
        Specialization::Int(val) if ty.is_subtype(types::CUInt64) => write!(f, "[{}]", val),
        Specialization::Int(val) => write!(f, "[{val}]"),
        Specialization::Double(val) => write!(f, "[{val}]"),
    }
}

/// Print adaptor for [`Type`]. See [`PtrPrintMap`].
pub struct TypePrinter<'a> {
    inner: Type,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for TypePrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let ty = self.inner;
        for (name, pattern) in bits::AllBitPatterns {
            if ty.bits == pattern {
                write!(f, "{name}")?;
                return write_spec(f, self);
            }
        }
        assert!(bits::AllBitPatterns.is_sorted_by(|(_, left), (_, right)| left > right));
        let mut bits = ty.bits;
        let mut sep = "";
        for (name, pattern) in bits::AllBitPatterns {
            if bits == 0 { break; }
            if (bits & pattern) == pattern {
                write!(f, "{sep}{name}")?;
                sep = "|";
                bits &= !pattern;
            }
        }
        assert_eq!(bits, 0, "Should have eliminated all bits by iterating over all patterns");
        write_spec(f, self)
    }
}

impl std::fmt::Display for Type {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

fn is_array_exact(val: VALUE) -> bool {
    // Prism hides array values in the constant pool from the GC, so class_of will return 0
    val.class_of() == unsafe { rb_cArray } || (val.class_of() == VALUE(0) && val.builtin_type() == RUBY_T_ARRAY)
}

fn is_string_exact(val: VALUE) -> bool {
    // Prism hides string values in the constant pool from the GC, so class_of will return 0
    val.class_of() == unsafe { rb_cString } || (val.class_of() == VALUE(0) && val.builtin_type() == RUBY_T_STRING)
}

fn is_hash_exact(val: VALUE) -> bool {
    // Prism hides hash values in the constant pool from the GC, so class_of will return 0
    val.class_of() == unsafe { rb_cHash } || (val.class_of() == VALUE(0) && val.builtin_type() == RUBY_T_HASH)
}

fn is_range_exact(val: VALUE) -> bool {
    val.class_of() == unsafe { rb_cRange }
}

fn is_module_exact(val: VALUE) -> bool {
    if val.builtin_type() != RUBY_T_MODULE {
        return false;
    }

    // For Class and Module instances, `class_of` will return the singleton class of the object.
    // Using `rb_obj_class` will give us the actual class of the module so we can check if the
    // object is an instance of Module, or an instance of Module subclass.
    let klass = unsafe { rb_obj_class(val) };
    klass == unsafe { rb_cModule }
}

impl Type {
    /// Create a `Type` from the given integer.
    pub const fn fixnum(val: i64) -> Type {
        Type {
            bits: bits::Fixnum,
            spec: Specialization::Object(VALUE::fixnum_from_usize(val as usize)),
        }
    }

    /// Create a `Type` from a Ruby `VALUE`. The type is not guaranteed to have object
    /// specialization in its `specialization` field (for example, `Qnil` will just be
    /// `types::NilClassExact`), but will be available via `ruby_object()`.
    pub fn from_value(val: VALUE) -> Type {
        if val.fixnum_p() {
            Type { bits: bits::Fixnum, spec: Specialization::Object(val) }
        }
        else if val.flonum_p() {
            Type { bits: bits::Flonum, spec: Specialization::Object(val) }
        }
        else if val.static_sym_p() {
            Type { bits: bits::StaticSymbol, spec: Specialization::Object(val) }
        }
        // Singleton objects; don't specialize
        else if val == Qnil { types::NilClassExact }
        else if val == Qtrue { types::TrueClassExact }
        else if val == Qfalse { types::FalseClassExact }
        else if val.cme_p() {
            // NB: Checking for CME has to happen before looking at class_of because that's not
            // valid on imemo.
            Type { bits: bits::CallableMethodEntry, spec: Specialization::Object(val) }
        }
        else if val.class_of() == unsafe { rb_cInteger } {
            Type { bits: bits::Bignum, spec: Specialization::Object(val) }
        }
        else if val.class_of() == unsafe { rb_cFloat } {
            Type { bits: bits::HeapFloat, spec: Specialization::Object(val) }
        }
        else if val.class_of() == unsafe { rb_cSymbol } {
            Type { bits: bits::DynamicSymbol, spec: Specialization::Object(val) }
        }
        else if is_array_exact(val) {
            Type { bits: bits::ArrayExact, spec: Specialization::Object(val) }
        }
        else if is_hash_exact(val) {
            Type { bits: bits::HashExact, spec: Specialization::Object(val) }
        }
        else if is_range_exact(val) {
            Type { bits: bits::RangeExact, spec: Specialization::Object(val) }
        }
        else if is_string_exact(val) {
            Type { bits: bits::StringExact, spec: Specialization::Object(val) }
        }
        else if is_module_exact(val) {
            Type { bits: bits::ModuleExact, spec: Specialization::Object(val) }
        }
        else if val.builtin_type() == RUBY_T_CLASS {
            Type { bits: bits::Class, spec: Specialization::Object(val) }
        }
        else if val.class_of() == unsafe { rb_cRegexp } {
            Type { bits: bits::RegexpExact, spec: Specialization::Object(val) }
        }
        else if val.class_of() == unsafe { rb_cSet } {
            Type { bits: bits::SetExact, spec: Specialization::Object(val) }
        }
        else if val.class_of() == unsafe { rb_cObject } {
            Type { bits: bits::ObjectExact, spec: Specialization::Object(val) }
        }
        else {
            // TODO(max): Add more cases for inferring type bits from built-in types
            Type { bits: bits::BasicObject, spec: Specialization::Object(val) }
        }
    }

    /// Private. Only for creating type globals.
    const fn from_bits(bits: u64) -> Type {
        Type {
            bits,
            spec: if bits == bits::Empty {
                Specialization::Empty
            } else {
                Specialization::Any
            },
        }
    }

    /// Create a `Type` from a cvalue integer. Use the `ty` given to specify what size the
    /// `specialization` represents. For example, `Type::from_cint(types::CBool, 1)` or
    /// `Type::from_cint(types::CUInt16, 12)`.
    pub fn from_cint(ty: Type, val: i64) -> Type {
        assert_eq!(ty.spec, Specialization::Any);
        assert!((ty.is_subtype(types::CUnsigned) || ty.is_subtype(types::CSigned)) &&
                ty.bits != types::CUnsigned.bits && ty.bits != types::CSigned.bits,
                "ty must be a specific int size");
        Type { bits: ty.bits, spec: Specialization::Int(val as u64) }
    }

    /// Create a `Type` (a `CDouble` with double specialization) from a f64.
    pub fn from_double(val: f64) -> Type {
        Type { bits: bits::CDouble, spec: Specialization::Double(val) }
    }

    /// Create a `Type` from a cvalue boolean.
    pub fn from_cbool(val: bool) -> Type {
        Type { bits: bits::CBool, spec: Specialization::Int(val as u64) }
    }

    /// Return true if the value with this type is definitely truthy.
    pub fn is_known_truthy(&self) -> bool {
        !self.could_be(types::NilClassExact) && !self.could_be(types::FalseClassExact)
    }

    /// Return true if the value with this type is definitely falsy.
    pub fn is_known_falsy(&self) -> bool {
        self.is_subtype(types::NilClassExact) || self.is_subtype(types::FalseClassExact)
    }

    /// Top self is the Ruby global object, where top-level method definitions go. Return true if
    /// this Type has a Ruby object specialization that is the top-level self.
    pub fn is_top_self(&self) -> bool {
        self.ruby_object() == Some(unsafe { crate::cruby::rb_vm_top_self() })
    }

    /// Return the object specialization, if any.
    pub fn ruby_object(&self) -> Option<VALUE> {
        match self.spec {
            Specialization::Object(val) => Some(val),
            _ => None,
        }
    }

    pub fn unspecialized(&self) -> Self {
        Type { spec: Specialization::Any, ..*self }
    }

    pub fn fixnum_value(&self) -> Option<i64> {
        if self.is_subtype(types::Fixnum) {
            self.ruby_object().map(|val| val.as_fixnum())
        } else {
            None
        }
    }

    /// Return true if the Type has object specialization and false otherwise.
    pub fn ruby_object_known(&self) -> bool {
        matches!(self.spec, Specialization::Object(_))
    }

    fn is_builtin(class: VALUE) -> bool {
        if class == unsafe { rb_cArray } { return true; }
        if class == unsafe { rb_cClass } { return true; }
        if class == unsafe { rb_cFalseClass } { return true; }
        if class == unsafe { rb_cFloat } { return true; }
        if class == unsafe { rb_cHash } { return true; }
        if class == unsafe { rb_cInteger } { return true; }
        if class == unsafe { rb_cModule } { return true; }
        if class == unsafe { rb_cNilClass } { return true; }
        if class == unsafe { rb_cObject } { return true; }
        if class == unsafe { rb_cRange } { return true; }
        if class == unsafe { rb_cRegexp } { return true; }
        if class == unsafe { rb_cString } { return true; }
        if class == unsafe { rb_cSymbol } { return true; }
        if class == unsafe { rb_cTrueClass } { return true; }
        false
    }

    /// Union both types together, preserving specialization if possible.
    pub fn union(&self, other: Type) -> Type {
        // Easy cases first
        if self.is_subtype(other) { return other; }
        if other.is_subtype(*self) { return *self; }
        let bits = self.bits | other.bits;
        let result = Type::from_bits(bits);
        // If one type isn't type specialized, we can't return a specialized Type
        if !self.type_known() || !other.type_known() { return result; }
        let self_class = self.inexact_ruby_class().unwrap();
        let other_class = other.inexact_ruby_class().unwrap();
        // Pick one of self/other as the least upper bound. This is not the most specific (there
        // could be intermediate classes in the inheritance hierarchy) but it is fast to compute.
        let super_class = match self_class.is_subclass_of(other_class) {
            ClassRelationship::Subclass => other_class,
            ClassRelationship::Superclass => self_class,
            ClassRelationship::NoRelation => return result,
        };
        // Don't specialize built-in types; we can represent them perfectly with type bits.
        if Type::is_builtin(super_class) { return result; }
        // Supertype specialization can be exact only if the exact type specializations are identical
        if let Some(self_class) = self.exact_ruby_class() {
            if let Some(other_class) = other.exact_ruby_class() {
                if self_class == other_class {
                    return Type { bits, spec: Specialization::TypeExact(self_class) };
                }
            }
        }
        Type { bits, spec: Specialization::Type(super_class) }
    }

    /// Intersect both types, preserving specialization if possible.
    pub fn intersection(&self, other: Type) -> Type {
        let bits = self.bits & other.bits;
        if bits == bits::Empty { return types::Empty; }
        if self.spec_is_subtype_of(other) { return Type { bits, spec: self.spec }; }
        if other.spec_is_subtype_of(*self) { return Type { bits, spec: other.spec }; }
        types::Empty
    }

    pub fn could_be(&self, other: Type) -> bool {
        !self.intersection(other).bit_equal(types::Empty)
    }

    /// Check if the type field of `self` is a subtype of the type field of `other` and also check
    /// if the specialization of `self` is a subtype of the specialization of `other`.
    pub fn is_subtype(&self, other: Type) -> bool {
        (self.bits & other.bits) == self.bits && self.spec_is_subtype_of(other)
    }

    /// Return the type specialization, if any. Type specialization asks if we know the Ruby type
    /// (including potentially its subclasses) corresponding to a `Type`, including knowing exactly
    /// what object is is.
    pub fn type_known(&self) -> bool {
        matches!(self.spec, Specialization::TypeExact(_) | Specialization::Type(_) | Specialization::Object(_))
    }

    /// Return the exact type specialization, if any. Type specialization asks if we know the
    /// *exact* Ruby type corresponding to a `Type`, including knowing exactly what object is is.
    pub fn exact_class_known(&self) -> bool {
        matches!(self.spec, Specialization::TypeExact(_) | Specialization::Object(_))
    }

    /// Return the exact type specialization, if any. Type specialization asks if we know the exact
    /// Ruby type corresponding to a `Type` (no subclasses), including knowing exactly what object
    /// it is.
    pub fn exact_ruby_class(&self) -> Option<VALUE> {
        match self.spec {
            // If we're looking at a precise object, we can pull out its class.
            Specialization::Object(val) => Some(val.class_of()),
            Specialization::TypeExact(val) => Some(val),
            _ => None,
        }
    }

    /// Return the type specialization, if any. Type specialization asks if we know the inexact
    /// Ruby type corresponding to a `Type`, including knowing exactly what object is is.
    pub fn inexact_ruby_class(&self) -> Option<VALUE> {
        match self.spec {
            // If we're looking at a precise object, we can pull out its class.
            Specialization::Object(val) => Some(val.class_of()),
            Specialization::TypeExact(val) | Specialization::Type(val) => Some(val),
            _ => None,
        }
    }

    /// Return a pointer to the Ruby class that an object of this Type would have at run-time, if
    /// known. This includes classes for HIR types such as ArrayExact or NilClassExact, which have
    /// canonical Type representations that lack an explicit specialization in their `spec` fields.
    pub fn runtime_exact_ruby_class(&self) -> Option<VALUE> {
        if let Some(val) = self.exact_ruby_class() {
            return Some(val);
        }
        if self.is_subtype(types::ArrayExact) { return Some(unsafe { rb_cArray }); }
        if self.is_subtype(types::Class) { return Some(unsafe { rb_cClass }); }
        if self.is_subtype(types::FalseClassExact) { return Some(unsafe { rb_cFalseClass }); }
        if self.is_subtype(types::FloatExact) { return Some(unsafe { rb_cFloat }); }
        if self.is_subtype(types::HashExact) { return Some(unsafe { rb_cHash }); }
        if self.is_subtype(types::IntegerExact) { return Some(unsafe { rb_cInteger }); }
        if self.is_subtype(types::ModuleExact) { return Some(unsafe { rb_cModule }); }
        if self.is_subtype(types::NilClassExact) { return Some(unsafe { rb_cNilClass }); }
        if self.is_subtype(types::ObjectExact) { return Some(unsafe { rb_cObject }); }
        if self.is_subtype(types::RangeExact) { return Some(unsafe { rb_cRange }); }
        if self.is_subtype(types::RegexpExact) { return Some(unsafe { rb_cRegexp }); }
        if self.is_subtype(types::SetExact) { return Some(unsafe { rb_cSet }); }
        if self.is_subtype(types::StringExact) { return Some(unsafe { rb_cString }); }
        if self.is_subtype(types::SymbolExact) { return Some(unsafe { rb_cSymbol }); }
        if self.is_subtype(types::TrueClassExact) { return Some(unsafe { rb_cTrueClass }); }
        None
    }

    /// Check bit equality of two `Type`s. Do not use! You are probably looking for [`Type::is_subtype`].
    pub fn bit_equal(&self, other: Type) -> bool {
        self.bits == other.bits && self.spec == other.spec
    }

    /// Check *only* if `self`'s specialization is a subtype of `other`'s specialization. Private.
    /// You probably want [`Type::is_subtype`] instead.
    fn spec_is_subtype_of(&self, other: Type) -> bool {
        match (self.spec, other.spec) {
            // Empty is a subtype of everything; Any is a supertype of everything
            (Specialization::Empty, _) | (_, Specialization::Any) => true,
            // Other is not Any from the previous case, so Any is definitely not a subtype
            (Specialization::Any, _) | (_, Specialization::Empty) => false,
            // Int and double specialization requires exact equality
            (Specialization::Int(_), _) | (_, Specialization::Int(_)) |
            (Specialization::Double(_), _) | (_, Specialization::Double(_)) =>
                self.bits == other.bits && self.spec == other.spec,
            // Check other's specialization type in decreasing order of specificity
            (_, Specialization::Object(_)) =>
                self.ruby_object_known() && self.ruby_object() == other.ruby_object(),
            (_, Specialization::TypeExact(_)) =>
                self.exact_class_known() && self.inexact_ruby_class() == other.inexact_ruby_class(),
            (_, Specialization::Type(other_class)) =>
                self.inexact_ruby_class().unwrap().is_subclass_of(other_class) == ClassRelationship::Subclass,
        }
    }

    fn is_immediate(&self) -> bool {
        self.is_subtype(types::Immediate)
    }

    pub fn print(self, ptr_map: &PtrPrintMap) -> TypePrinter {
        TypePrinter { inner: self, ptr_map }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cruby::rust_str_to_ruby;
    use crate::cruby::rust_str_to_sym;
    use crate::cruby::rb_ary_new_capa;
    use crate::cruby::rb_hash_new;
    use crate::cruby::rb_float_new;
    use crate::cruby::define_class;

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
        assert_subtype(types::Empty, types::NilClassExact);
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
        assert_subtype(types::NilClassExact, types::Any);
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
        assert_subtype(types::Fixnum, types::IntegerExact);
        assert_subtype(types::Bignum, types::IntegerExact);
        assert_subtype(types::IntegerExact, types::Integer);
        assert_subtype(types::IntegerSubclass, types::Integer);
    }

    #[test]
    fn float() {
        assert_subtype(types::Flonum, types::FloatExact);
        assert_subtype(types::HeapFloat, types::FloatExact);
        assert_subtype(types::FloatExact, types::Float);
        assert_subtype(types::FloatSubclass, types::Float);
    }

    #[test]
    fn symbol() {
        assert_subtype(types::StaticSymbol, types::SymbolExact);
        assert_subtype(types::DynamicSymbol, types::SymbolExact);
        assert_subtype(types::SymbolExact, types::Symbol);
        assert_subtype(types::SymbolSubclass, types::Symbol);
    }

    #[test]
    fn immediate() {
        assert_subtype(Type::fixnum(123), types::Immediate);
        assert_subtype(types::Fixnum, types::Immediate);
        assert_not_subtype(types::Bignum, types::Immediate);
        assert_subtype(types::NilClassExact, types::Immediate);
        assert_subtype(types::TrueClassExact, types::Immediate);
        assert_subtype(types::FalseClassExact, types::Immediate);
        assert_not_subtype(types::NilClassSubclass, types::Immediate);
        assert_not_subtype(types::TrueClassSubclass, types::Immediate);
        assert_not_subtype(types::FalseClassSubclass, types::Immediate);
        assert_subtype(types::StaticSymbol, types::Immediate);
        assert_not_subtype(types::DynamicSymbol, types::Immediate);
        assert_subtype(types::Flonum, types::Immediate);
        assert_not_subtype(types::HeapFloat, types::Immediate);
    }

    #[test]
    fn fixnum_has_ruby_object() {
        assert_eq!(Type::fixnum(3).ruby_object(), Some(VALUE::fixnum_from_usize(3)));
        assert_eq!(types::Fixnum.ruby_object(), None);
        assert_eq!(types::IntegerExact.ruby_object(), None);
        assert_eq!(types::Integer.ruby_object(), None);
    }

    #[test]
    fn singletons_do_not_have_ruby_object() {
        assert_eq!(Type::from_value(Qnil).ruby_object(), None);
        assert_eq!(types::NilClassExact.ruby_object(), None);
        assert_eq!(Type::from_value(Qtrue).ruby_object(), None);
        assert_eq!(types::TrueClassExact.ruby_object(), None);
        assert_eq!(Type::from_value(Qfalse).ruby_object(), None);
        assert_eq!(types::FalseClassExact.ruby_object(), None);
    }

    #[test]
    fn integer_has_exact_ruby_class() {
        assert_eq!(Type::fixnum(3).exact_ruby_class(), Some(unsafe { rb_cInteger }.into()));
        assert_eq!(types::Fixnum.exact_ruby_class(), None);
        assert_eq!(types::IntegerExact.exact_ruby_class(), None);
        assert_eq!(types::Integer.exact_ruby_class(), None);
    }

    #[test]
    fn singletons_do_not_have_exact_ruby_class() {
        assert_eq!(Type::from_value(Qnil).exact_ruby_class(), None);
        assert_eq!(types::NilClassExact.exact_ruby_class(), None);
        assert_eq!(Type::from_value(Qtrue).exact_ruby_class(), None);
        assert_eq!(types::TrueClassExact.exact_ruby_class(), None);
        assert_eq!(Type::from_value(Qfalse).exact_ruby_class(), None);
        assert_eq!(types::FalseClassExact.exact_ruby_class(), None);
    }

    #[test]
    fn singletons_do_not_have_ruby_class() {
        assert_eq!(Type::from_value(Qnil).inexact_ruby_class(), None);
        assert_eq!(types::NilClassExact.inexact_ruby_class(), None);
        assert_eq!(Type::from_value(Qtrue).inexact_ruby_class(), None);
        assert_eq!(types::TrueClassExact.inexact_ruby_class(), None);
        assert_eq!(Type::from_value(Qfalse).inexact_ruby_class(), None);
        assert_eq!(types::FalseClassExact.inexact_ruby_class(), None);
    }

    #[test]
    fn integer_has_ruby_class() {
        assert_eq!(Type::fixnum(3).inexact_ruby_class(), Some(unsafe { rb_cInteger }.into()));
        assert_eq!(types::Fixnum.inexact_ruby_class(), None);
        assert_eq!(types::IntegerExact.inexact_ruby_class(), None);
        assert_eq!(types::Integer.inexact_ruby_class(), None);
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
        assert_eq!(format!("{}", types::IntegerExact), "IntegerExact");
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
        assert_bit_equal(types::Fixnum.union(types::IntegerExact), types::IntegerExact);
        assert_bit_equal(types::Fixnum.union(types::Integer), types::Integer);
        assert_bit_equal(types::Fixnum.union(types::Object), types::Object);
        assert_bit_equal(Type::fixnum(3).union(types::Fixnum), types::Fixnum);

        assert_bit_equal(types::IntegerExact.union(types::Fixnum), types::IntegerExact);
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
