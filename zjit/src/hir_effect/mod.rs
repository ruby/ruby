//! High-level intermediate representation effects.

#![allow(non_upper_case_globals)]
use crate::hir::{PtrPrintMap};

// We use a type alias for the width of our Effect bitset.
// This width should reflect hir_effect.inc.rs.
type EffectBits = u8;

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
///
/// Lattice Top corresponds to the "Any" effect. All bits are set and any effect is possible.
/// Lattice Bottom corresponds to the "None" effect. No bits are set and no effects are possible.
/// Elements between Bottom and Top have effects corresponding to the bits that are set.
/// This enables more complex analyses compared to prior ZJIT implementations such as "has_effect",
/// a function that returns a boolean value. Such functions impose an implicit single bit effect
/// system. This explicit design with a lattice allows us many bits for effects.
pub struct EffectSet {
    bits: EffectBits
}

// TODO(Jacob): Add tests for Effect
// TODO(Jacob): Modify ruby generation of effects to include nice labels for Effects instead of just EffectSets
pub struct Effect {
    /// Unlike ZJIT's type system, effects do not have a notion of subclasses.
    /// Instead of specializations, the EffectPair struct contains two Effect bitsets.
    /// We distinguish between read effects and write effects.
    /// Both use the same effects lattice, but splitting into two bitsets allows
    /// for finer grained optimization.
    ///
    /// For example, an HIR instruction that writes nothing could be elided, regardless
    /// of its read effects.
    ///
    /// These fields should not be directly read or written except by internal `Effect` APIs.
    read: EffectSet,
    write: EffectSet
}

include!("hir_effect.inc.rs");


/// Print adaptor for [`Effect`]. See [`PtrPrintMap`].
pub struct EffectSetPrinter<'a> {
    inner: EffectSet,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for EffectSetPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let effect = self.inner;
        let mut bits = effect.bits;
        let mut sep = "";
        // First, make sure patterns are sorted from higher order bits to lower order.
        // For each match where `bits` contains the pattern, we mask off the matched bits
        // and continue searching for matches until bits == 0.
        // Our first match could be exact and may not require a separator, but all subsequent
        // matches do.
        debug_assert!(bits::AllBitPatterns.is_sorted_by(|(_, left), (_, right)| left > right));
        for (name, pattern) in bits::AllBitPatterns {
            if (bits & pattern) == pattern {
                write!(f, "{sep}{name}")?;
                sep = "|";
                bits &= !pattern;
            }
            // The `sep != ""` check allows us to handle the effects::None case gracefully.
            if (bits == 0) & (sep != "") { break; }
        }
        debug_assert_eq!(bits, 0, "Should have eliminated all bits by iterating over all patterns");
        Ok(())
    }
}

impl std::fmt::Display for EffectSet {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

// TODO(Jacob): Modify union and effect to work on an arbitrary number of args
// TODO(Jacob): These `from_bits` functions used to be `const fn` not `pub fn`. Have I done something bad by making them public?
impl EffectSet {
    pub fn from_bits(bits: EffectBits) -> EffectSet {
        EffectSet { bits }
    }

    pub fn union(&self, other: EffectSet) -> EffectSet {
        EffectSet::from_bits(self.bits | other.bits)
    }

    pub fn intersect(&self, other: EffectSet) -> EffectSet {
        EffectSet::from_bits(self.bits & other.bits)
    }

    pub fn exclude(&self, other: EffectSet) -> EffectSet {
        EffectSet::from_bits(self.bits - (self.bits & other.bits))
    }

    /// Check bit equality of two `Effect`s. Do not use! You are probably looking for [`Effect::includes`].
    pub fn bit_equal(&self, other: EffectSet) -> bool {
        self.bits == other.bits
    }

    pub fn includes(&self, other: EffectSet) -> bool {
        self.bit_equal(EffectSet::union(self, other))
    }

    pub fn overlaps(&self, other: EffectSet) -> bool {
        !self.intersect(other).bit_equal(effects::Empty)
    }

    pub fn print(self, ptr_map: &PtrPrintMap) -> EffectSetPrinter<'_> {
        EffectSetPrinter { inner: self, ptr_map }
    }
}

impl Effect {
    pub fn from_bits(read: EffectSet, write: EffectSet) -> Effect {
        Effect { read, write }
    }

    pub fn union(&self, other: Effect) -> Effect {
        Effect::from_bits(self.read.union(other.read), self.write.union(other.write))
    }

    pub fn intersect(&self, other: Effect) -> Effect {
        Effect::from_bits(self.read.intersect(other.read), self.write.intersect(other.write))
    }

    pub fn exclude(&self, other: Effect) -> Effect {
        Effect::from_bits(
            self.read.exclude(other.read),
            self.write.exclude(other.write)
        )
    }

    /// Check bit equality of two `Effect`s. Do not use! You are probably looking for [`Effect::includes`].
    pub fn bit_equal(&self, other: Effect) -> bool {
        self.read.bit_equal(other.read) & self.write.bit_equal(other.write)
    }

    pub fn includes(&self, other: Effect) -> bool {
        self.bit_equal(Effect::union(self, other))
    }

    pub fn overlaps(&self, other: Effect) -> bool {
        let empty = Effect::from_bits(effects::Empty, effects::Empty);
        !self.intersect(other).bit_equal(empty)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[track_caller]
    fn assert_bit_equal(left: EffectSet, right: EffectSet) {
        assert_eq!(left.bits, right.bits, "{left} bits are not equal to {right} bits");
    }

    #[track_caller]
    fn assert_subeffect(left: EffectSet, right: EffectSet) {
        assert!(right.includes(left), "{left} is not a subeffect of {right}");
    }

    #[track_caller]
    fn assert_not_subeffect(left: EffectSet, right: EffectSet) {
        assert!(!right.includes(left), "{left} is a subeffect of {right}");
    }

    #[test]
    fn none_is_subeffect_of_everything() {
        assert_subeffect(effects::Empty, effects::Empty);
        assert_subeffect(effects::Empty, effects::Any);
        assert_subeffect(effects::Empty, effects::Control);
        assert_subeffect(effects::Empty, effects::Frame);
        assert_subeffect(effects::Empty, effects::Stack);
        assert_subeffect(effects::Empty, effects::Locals);
        assert_subeffect(effects::Empty, effects::Allocator);
    }

    #[test]
    fn everything_is_subeffect_of_any() {
        assert_subeffect(effects::Empty, effects::Any);
        assert_subeffect(effects::Any, effects::Any);
        assert_subeffect(effects::Control, effects::Any);
        assert_subeffect(effects::Frame, effects::Any);
        assert_subeffect(effects::Memory, effects::Any);
        assert_subeffect(effects::Locals, effects::Any);
        assert_subeffect(effects::PC, effects::Any);
    }

    #[test]
    fn union_never_shrinks() {
        // iterate over all effect entries from bottom to top
        for i in [0, 1, 4, 6, 10, 15] {
            let e = EffectSet::from_bits(i);
            // Testing on bottom, top, and some arbitrary element in the middle
            assert_subeffect(effects::Empty, effects::Empty.union(e));
            assert_subeffect(effects::Any, effects::Any.union(e));
            assert_subeffect(effects::Frame, effects::Frame.union(e));
        }
    }

    #[test]
    fn intersect_never_grows() {
        // Randomly selected values from bottom to top
        for i in [0, 3, 6, 8, 15] {
            let e = EffectSet::from_bits(i);
            // Testing on bottom, top, and some arbitrary element in the middle
            assert_subeffect(effects::Empty.intersect(e), effects::Empty);
            assert_subeffect(effects::Any.intersect(e), effects::Any);
            assert_subeffect(effects::Frame.intersect(e), effects::Frame);
        }
    }

    #[test]
    fn self_is_included() {
        assert!(effects::Stack.includes(effects::Stack));
        assert!(effects::Any.includes(effects::Any));
        assert!(effects::Empty.includes(effects::Empty));
    }

    #[test]
    fn frame_includes_stack_locals_and_pc() {
        assert_subeffect(effects::Stack, effects::Frame);
        assert_subeffect(effects::Locals, effects::Frame);
        assert_subeffect(effects::PC, effects::Frame);
    }

    #[test]
    fn frame_is_stack_locals_and_pc() {
        let union = effects::Stack.union(effects::Locals.union(effects::PC));
        assert_bit_equal(effects::Frame, union);
    }

    #[test]
    fn any_includes_some_subeffects() {
        assert_subeffect(effects::Allocator, effects::Any);
        assert_subeffect(effects::Frame, effects::Any);
        assert_subeffect(effects::Memory, effects::Any);
    }

    #[test]
    fn display_exact_bits_match() {
        assert_eq!(format!("{}", effects::Empty), "Empty");
        assert_eq!(format!("{}", effects::PC), "PC");
        assert_eq!(format!("{}", effects::Any), "Any");
        assert_eq!(format!("{}", effects::Frame), "Frame");
        assert_eq!(format!("{}", effects::Stack.union(effects::Locals.union(effects::PC))), "Frame");
    }

    #[test]
    fn display_multiple_bits() {
        let union = effects::Stack.union(effects::Locals);
        assert_eq!(format!("{}", effects::Stack.union(effects::Locals.union(effects::PC))), "Frame");
        println!("{}", union);
        println!("{}", effects::Stack.union(effects::Locals.union(effects::PC)));
        assert_eq!(format!("{}", effects::Stack.union(effects::Locals)), "Stack|Locals");
        assert_eq!(format!("{}", effects::PC.union(effects::Allocator)), "PC|Allocator");
    }
}
