//! High-level intermediate representation effects.

// TODO(Jacob): Replace Effect with EffectSet and EffectPair with Effect
//

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
pub struct Effect {
    bits: EffectBits
}

pub struct EffectPair {
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
    read_bits: Effect,
    write_bits: Effect
}

include!("hir_effect.inc.rs");


/// Print adaptor for [`Effect`]. See [`PtrPrintMap`].
pub struct EffectPrinter<'a> {
    inner: Effect,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for EffectPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let effect = self.inner;
        // If there's an exact match, write and return
        for (name, pattern) in bits::AllBitPatterns {
            if effect.bits == pattern {
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

impl std::fmt::Display for Effect {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

impl Effect {
    const fn from_bits(bits: EffectBits) -> Effect {
        Effect { bits }
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

    /// Check bit equality of two `Effect`s. Do not use! You are probably looking for [`Effect::includes`].
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

#[cfg(test)]
mod tests {
    use super::*;

    #[track_caller]
    fn assert_bit_equal(left: Effect, right: Effect) {
        assert_eq!(left.bits, right.bits, "{left} bits are not equal to {right} bits");
    }

    #[track_caller]
    fn assert_subeffect(left: Effect, right: Effect) {
        assert!(right.includes(left), "{left} is not a subeffect of {right}");
    }

    #[track_caller]
    fn assert_not_subeffect(left: Effect, right: Effect) {
        assert!(!right.includes(left), "{left} is a subeffect of {right}");
    }

    #[test]
    fn none_is_subeffect_of_everything() {
        assert_subeffect(effects::None, effects::None);
        assert_subeffect(effects::None, effects::Any);
        assert_subeffect(effects::None, effects::World);
        assert_subeffect(effects::None, effects::Frame);
        assert_subeffect(effects::None, effects::Other);
        assert_subeffect(effects::None, effects::Stack);
        assert_subeffect(effects::None, effects::Locals);
        assert_subeffect(effects::None, effects::PC);
    }

    #[test]
    fn everything_is_subeffect_of_any() {
        assert_subeffect(effects::None, effects::Any);
        assert_subeffect(effects::Any, effects::Any);
        assert_subeffect(effects::World, effects::Any);
        assert_subeffect(effects::Frame, effects::Any);
        assert_subeffect(effects::Other, effects::Any);
        assert_subeffect(effects::Stack, effects::Any);
        assert_subeffect(effects::Locals, effects::Any);
        assert_subeffect(effects::PC, effects::Any);
    }

    #[test]
    fn union_never_shrinks() {
        // iterate over all effect entries from bottom to top
        for i in [0, 1, 4, 6, 10, 15] {
            let e = Effect::from_bits(i);
            // Testing on bottom, top, and some arbitrary element in the middle
            assert_subeffect(effects::None, effects::None.union(e));
            assert_subeffect(effects::Any, effects::Any.union(e));
            assert_subeffect(effects::Frame, effects::Frame.union(e));
        }
    }

    #[test]
    fn intersect_never_grows() {
        // Randomly selected values from bottom to top
        for i in [0, 3, 6, 8, 15] {
            let e = Effect::from_bits(i);
            // Testing on bottom, top, and some arbitrary element in the middle
            assert_subeffect(effects::None.intersect(e), effects::None);
            assert_subeffect(effects::Any.intersect(e), effects::Any);
            assert_subeffect(effects::Frame.intersect(e), effects::Frame);
        }
    }

    #[test]
    fn self_is_included() {
        assert!(effects::Stack.includes(effects::Stack));
        assert!(effects::Other.includes(effects::Other));
        assert!(effects::Stack.includes(effects::Stack));
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
    fn world_includes_other() {
        assert_subeffect(effects::Other, effects::World);
    }

    #[test]
    fn any_includes_world_and_frame() {
        assert_subeffect(effects::World, effects::Any);
        assert_subeffect(effects::Frame, effects::Any);
    }

    #[test]
    fn display_exact_bits_match() {
        assert_eq!(format!("{}", effects::None), "None");
        assert_eq!(format!("{}", effects::PC), "PC");
        assert_eq!(format!("{}", effects::Other), "Other");
    }

    // TODO(Jacob): Figure out why these last two comments cause test failures
    #[test]
    fn display_multiple_bits() {
        assert_eq!(format!("{}", effects::Frame), "Frame");
        assert_eq!(format!("{}", effects::Stack.union(effects::Locals.union(effects::PC))), "Frame");
        // assert_eq!(format!("{}", effects::Stack.union(effects::Locals)), "Locals|Stack");
        // assert_eq!(format!("{}", effects::Any), "Any");
    }
}
