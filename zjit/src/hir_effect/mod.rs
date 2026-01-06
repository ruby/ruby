//! High-level intermediate representation effects.

#![allow(non_upper_case_globals)]
use crate::hir::{PtrPrintMap};

// We use a type alias for the width of our Effect bitset.
// This width should reflect hir_effect.inc.rs.
type EffectBits = u8;

// NOTE: Effect very intentionally does not support Eq or PartialEq; we almost never want to check
// bit equality of types in the compiler but instead check subtyping, intersection, union, etc.
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
#[derive(Clone, Copy, Debug)]
pub struct EffectSet {
    bits: EffectBits
}

// TODO(Jacob): Add tests for Effect
// TODO(Jacob): Modify ruby generation of effects to include nice labels for Effects instead of just EffectSets
// TODO(Jacob): Modify these labels to be callected effect_sets in the inc.rs, and create others called effects
pub struct Effect {
    /// Unlike ZJIT's type system, effects do not have a notion of subclasses.
    /// Instead of specializations, the Effect struct contains two EffectSet bitsets.
    /// We distinguish between read effects and write effects.
    /// Both use the same effects lattice, but splitting into two bitsets allows
    /// for finer grained optimization.
    ///
    /// For instance:
    /// We can elide HIR instructions with no write effects, but the read effects are necessary for instruction
    /// reordering optimizations.
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

impl EffectSet {
    const fn from_bits(bits: EffectBits) -> Self {
        Self { bits }
    }

    pub fn union(&self, other: Self) -> Self {
        Self::from_bits(self.bits | other.bits)
    }

    pub fn intersect(&self, other: Self) -> Self {
        Self::from_bits(self.bits & other.bits)
    }

    pub fn exclude(&self, other: Self) -> Self {
        Self::from_bits(self.bits - (self.bits & other.bits))
    }

    /// Check bit equality of two `Effect`s. Do not use! You are probably looking for [`Effect::includes`].
    /// This function is intentionally made private.
    fn bit_equal(&self, other: Self) -> bool {
        self.bits == other.bits
    }

    pub fn includes(&self, other: Self) -> bool {
        self.bit_equal(
            self.union(other)
        )
    }

    pub fn overlaps(&self, other: Self) -> bool {
        !effect_sets::Empty.includes(
            self.intersect(other)
        )
    }

    pub fn print(self, ptr_map: &PtrPrintMap) -> EffectSetPrinter<'_> {
        EffectSetPrinter { inner: self, ptr_map }
    }
}

impl Effect {
    pub fn from_sets(read: EffectSet, write: EffectSet) -> Effect {
        Effect { read, write }
    }

    // This function addresses the special case where the read and write sets are the same
    pub fn from_set(set: EffectSet) -> Effect {
        Effect {read: set, write: set }
    }

    // This function accepts write and sets read to Any
    pub fn from_write(write: EffectSet) -> Effect {
        Effect { read: effect_sets::Any, write }
    }

    // This function accepts read and sets read to Any
    pub fn from_read(read: EffectSet) -> Effect {
        Effect { read, write: effect_sets::Any }
    }

    pub fn union(&self, other: Effect) -> Effect {
        Effect::from_sets(
            self.read.union(other.read),
            self.write.union(other.write)
        )
    }

    pub fn intersect(&self, other: Effect) -> Effect {
        Effect::from_sets(
            self.read.intersect(other.read),
            self.write.intersect(other.write)
        )
    }

    pub fn exclude(&self, other: Effect) -> Effect {
        Effect::from_sets(
            self.read.exclude(other.read),
            self.write.exclude(other.write)
        )
    }

    /// Check bit equality of two `Effect`s. Do not use! You are probably looking for [`Effect::includes`].
    /// This function is intentionally made private.
    fn bit_equal(&self, other: Effect) -> bool {
        self.read.bit_equal(other.read) & self.write.bit_equal(other.write)
    }

    pub fn includes(&self, other: Effect) -> bool {
        self.bit_equal(Effect::union(self, other))
    }

    pub fn overlaps(&self, other: Effect) -> bool {
        Effect::from_set(effect_sets::Empty).includes(
            self.intersect(other)
        )
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
        assert_subeffect(effect_sets::Empty, effect_sets::Empty);
        assert_subeffect(effect_sets::Empty, effect_sets::Any);
        assert_subeffect(effect_sets::Empty, effect_sets::Control);
        assert_subeffect(effect_sets::Empty, effect_sets::Frame);
        assert_subeffect(effect_sets::Empty, effect_sets::Stack);
        assert_subeffect(effect_sets::Empty, effect_sets::Locals);
        assert_subeffect(effect_sets::Empty, effect_sets::Allocator);
    }

    #[test]
    fn everything_is_subeffect_of_any() {
        assert_subeffect(effect_sets::Empty, effect_sets::Any);
        assert_subeffect(effect_sets::Any, effect_sets::Any);
        assert_subeffect(effect_sets::Control, effect_sets::Any);
        assert_subeffect(effect_sets::Frame, effect_sets::Any);
        assert_subeffect(effect_sets::Memory, effect_sets::Any);
        assert_subeffect(effect_sets::Locals, effect_sets::Any);
        assert_subeffect(effect_sets::PC, effect_sets::Any);
    }

    #[test]
    fn union_never_shrinks() {
        // iterate over all effect entries from bottom to top
        for i in [0, 1, 4, 6, 10, 15] {
            let e = EffectSet::from_bits(i);
            // Testing on bottom, top, and some arbitrary element in the middle
            assert_subeffect(effect_sets::Empty, effect_sets::Empty.union(e));
            assert_subeffect(effect_sets::Any, effect_sets::Any.union(e));
            assert_subeffect(effect_sets::Frame, effect_sets::Frame.union(e));
        }
    }

    #[test]
    fn intersect_never_grows() {
        // Randomly selected values from bottom to top
        for i in [0, 3, 6, 8, 15] {
            let e = EffectSet::from_bits(i);
            // Testing on bottom, top, and some arbitrary element in the middle
            assert_subeffect(effect_sets::Empty.intersect(e), effect_sets::Empty);
            assert_subeffect(effect_sets::Any.intersect(e), effect_sets::Any);
            assert_subeffect(effect_sets::Frame.intersect(e), effect_sets::Frame);
        }
    }

    #[test]
    fn self_is_included() {
        assert!(effect_sets::Stack.includes(effect_sets::Stack));
        assert!(effect_sets::Any.includes(effect_sets::Any));
        assert!(effect_sets::Empty.includes(effect_sets::Empty));
    }

    #[test]
    fn frame_includes_stack_locals_and_pc() {
        assert_subeffect(effect_sets::Stack, effect_sets::Frame);
        assert_subeffect(effect_sets::Locals, effect_sets::Frame);
        assert_subeffect(effect_sets::PC, effect_sets::Frame);
    }

    #[test]
    fn frame_is_stack_locals_and_pc() {
        let union = effect_sets::Stack.union(effect_sets::Locals.union(effect_sets::PC));
        assert_bit_equal(effect_sets::Frame, union);
    }

    #[test]
    fn any_includes_some_subeffects() {
        assert_subeffect(effect_sets::Allocator, effect_sets::Any);
        assert_subeffect(effect_sets::Frame, effect_sets::Any);
        assert_subeffect(effect_sets::Memory, effect_sets::Any);
    }

    #[test]
    fn display_exact_bits_match() {
        assert_eq!(format!("{}", effect_sets::Empty), "Empty");
        assert_eq!(format!("{}", effect_sets::PC), "PC");
        assert_eq!(format!("{}", effect_sets::Any), "Any");
        assert_eq!(format!("{}", effect_sets::Frame), "Frame");
        assert_eq!(format!("{}", effect_sets::Stack.union(effect_sets::Locals.union(effect_sets::PC))), "Frame");
    }

    #[test]
    fn display_multiple_bits() {
        let union = effect_sets::Stack.union(effect_sets::Locals);
        assert_eq!(format!("{}", effect_sets::Stack.union(effect_sets::Locals.union(effect_sets::PC))), "Frame");
        println!("{}", union);
        println!("{}", effect_sets::Stack.union(effect_sets::Locals.union(effect_sets::PC)));
        assert_eq!(format!("{}", effect_sets::Stack.union(effect_sets::Locals)), "Stack|Locals");
        assert_eq!(format!("{}", effect_sets::PC.union(effect_sets::Allocator)), "PC|Allocator");
    }
}
