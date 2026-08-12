//! High-level intermediate representation effects.

#![allow(non_upper_case_globals)]
use crate::hir::{PtrPrintMap};
include!("hir_effect.inc.rs");

// NOTE: Effect very intentionally does not support Eq or PartialEq; we almost never want to check
// bit equality of types in the compiler but instead check subtyping, intersection, union, etc.
/// The AbstractHeap struct is the main work horse of effect inference and specialization. The main interfaces
/// will look like:
///
/// * is AbstractHeap A a subset of AbstractHeap B
/// * union/meet AbstractHeap A and AbstractHeap B
///
/// or
///
/// * is Effect A a subset of Effect B
/// * union/meet Effect A and Effect B
///
/// The AbstractHeap is the work horse because Effect is simply 2 AbstractHeaps; one for read, and one for write.
/// Currently, the abstract heap is implemented as a bitset. As we enrich our effect system, this will be updated
/// to match the name and use a heap implementation, roughly aligned with
/// <https://gist.github.com/pizlonator/cf1e72b8600b1437dda8153ea3fdb963>.
///
/// Most questions can be rewritten in terms of these operations.
///
/// Lattice Top corresponds to the "Any" effect. All bits are set and any effect is possible.
/// Lattice Bottom corresponds to the "None" effect. No bits are set and no effects are possible.
/// Elements between abstract_heaps have effects corresponding to the bits that are set.
/// This enables more complex analyses compared to prior ZJIT implementations such as "has_effect",
/// a function that returns a boolean value. Such functions impose an implicit single bit effect
/// system. This explicit design with a lattice allows us many bits for effects.
#[derive(Clone, Copy, Debug)]
pub struct AbstractHeap {
    bits: effect_types::EffectBits
}

#[derive(Clone, Copy, Debug)]
pub struct Effect {
    /// Unlike ZJIT's type system, effects do not have a notion of subclasses.
    /// Instead of specializations, the Effect struct contains two AbstractHeaps.
    /// We distinguish between read effects and write effects.
    /// Both use the same effects lattice, but splitting into two heaps allows
    /// for finer grained optimization.
    ///
    /// For instance:
    /// We can elide HIR instructions with no write effects, but the read effects are necessary for instruction
    /// reordering optimizations.
    ///
    /// These fields should not be directly read or written except by internal `Effect` APIs.
    read: AbstractHeap,
    write: AbstractHeap
}

/// Print adaptor for [`AbstractHeap`]. See [`PtrPrintMap`].
pub struct AbstractHeapPrinter<'a> {
    inner: AbstractHeap,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for AbstractHeapPrinter<'a> {
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

impl std::fmt::Display for AbstractHeap {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

/// Print adaptor for [`Effect`]. See [`PtrPrintMap`].
pub struct EffectPrinter<'a> {
    inner: Effect,
    ptr_map: &'a PtrPrintMap,
}

impl<'a> std::fmt::Display for EffectPrinter<'a> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}, {}", self.inner.read, self.inner.write)
    }
}

impl std::fmt::Display for Effect {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        self.print(&PtrPrintMap::identity()).fmt(f)
    }
}

impl AbstractHeap {
    const fn from_bits(bits: effect_types::EffectBits) -> Self {
        Self { bits }
    }

    pub const fn union(&self, other: Self) -> Self {
        Self::from_bits(self.bits | other.bits)
    }

    pub const fn intersect(&self, other: Self) -> Self {
        Self::from_bits(self.bits & other.bits)
    }

    pub const fn exclude(&self, other: Self) -> Self {
        Self::from_bits(self.bits - (self.bits & other.bits))
    }

    /// Check bit equality of two `Effect`s. Do not use! You are probably looking for [`Effect::includes`].
    /// This function is intentionally made private.
    const fn bit_equal(&self, other: Self) -> bool {
        self.bits == other.bits
    }

    pub const fn includes(&self, other: Self) -> bool {
        self.bit_equal(
            self.union(other)
        )
    }

    pub const fn overlaps(&self, other: Self) -> bool {
        !abstract_heaps::Empty.includes(
            self.intersect(other)
        )
    }

    pub const fn print(self, ptr_map: &PtrPrintMap) -> AbstractHeapPrinter<'_> {
        AbstractHeapPrinter { inner: self, ptr_map }
    }
}

impl Effect {
    pub const fn read_write(read: AbstractHeap, write: AbstractHeap) -> Effect {
        Effect { read, write }
    }

    /// This function addresses the special case where the read and write heaps are the same
    pub const fn promote(heap: AbstractHeap) -> Effect {
        Effect {read: heap, write: heap }
    }

    /// This function accepts write and heaps read to Any
    pub const fn write(write: AbstractHeap) -> Effect {
        Effect { read: abstract_heaps::Any, write }
    }

    /// This function accepts read and heaps read to Any
    pub const fn read(read: AbstractHeap) -> Effect {
        Effect { read, write: abstract_heaps::Any }
    }

    /// Method to access the private read field
    pub const fn read_bits(&self) -> AbstractHeap {
        self.read
    }

    /// Method to access the private write field
    pub const fn write_bits(&self) -> AbstractHeap {
        self.write
    }

    pub const fn union(&self, other: Effect) -> Effect {
        Effect::read_write(
            self.read.union(other.read),
            self.write.union(other.write)
        )
    }

    pub const fn intersect(&self, other: Effect) -> Effect {
        Effect::read_write(
            self.read.intersect(other.read),
            self.write.intersect(other.write)
        )
    }

    pub const fn exclude(&self, other: Effect) -> Effect {
        Effect::read_write(
            self.read.exclude(other.read),
            self.write.exclude(other.write)
        )
    }

    /// Check bit equality of two `Effect`s. Do not use! You are probably looking for [`Effect::includes`].
    /// This function is intentionally made private.
    const fn bit_equal(&self, other: Effect) -> bool {
        self.read.bit_equal(other.read) & self.write.bit_equal(other.write)
    }

    pub const fn includes(&self, other: Effect) -> bool {
        self.bit_equal(Effect::union(self, other))
    }

    pub const fn overlaps(&self, other: Effect) -> bool {
        Effect::promote(abstract_heaps::Empty).includes(
            self.intersect(other)
        )
    }

    pub const fn print(self, ptr_map: &PtrPrintMap) -> EffectPrinter<'_> {
        EffectPrinter { inner: self, ptr_map }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[track_caller]
    fn assert_heap_bit_equal(left: AbstractHeap, right: AbstractHeap) {
        assert!(left.bit_equal(right), "{left} bits are not equal to {right} bits");
    }

    #[track_caller]
    fn assert_subeffect_heap(left: AbstractHeap, right: AbstractHeap) {
        assert!(right.includes(left), "{left} is not a subeffect heap of {right}");
    }

    #[track_caller]
    fn assert_not_subeffect_heap(left: AbstractHeap, right: AbstractHeap) {
        assert!(!right.includes(left), "{left} is a subeffect heap of {right}");
    }

    #[track_caller]
    fn assert_bit_equal(left: Effect, right: Effect) {
        assert!(left.bit_equal(right), "{left} bits are not equal to {right} bits");
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
    fn effect_heap_none_is_subeffect_of_everything() {
        assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Empty);
        assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Control);
        assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Frame);
        assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Stack);
        assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Locals);
        assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Allocator);
    }

    #[test]
    fn effect_heap_everything_is_subeffect_of_any() {
        assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::Any, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::Control, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::Frame, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::Memory, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::Locals, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::PC, abstract_heaps::Any);
    }

    #[test]
    fn effect_heap_union_never_shrinks() {
        // iterate over all effect entries from bottom to top
        for i in [0, 1, 4, 6, 10, 15] {
            let e = AbstractHeap::from_bits(i);
            // Testing on bottom, top, and some arbitrary element in the middle
            assert_subeffect_heap(abstract_heaps::Empty, abstract_heaps::Empty.union(e));
            assert_subeffect_heap(abstract_heaps::Any, abstract_heaps::Any.union(e));
            assert_subeffect_heap(abstract_heaps::Frame, abstract_heaps::Frame.union(e));
        }
    }

    #[test]
    fn effect_heap_intersect_never_grows() {
        // Randomly selected values from bottom to top
        for i in [0, 3, 6, 8, 15] {
            let e = AbstractHeap::from_bits(i);
            // Testing on bottom, top, and some arbitrary element in the middle
            assert_subeffect_heap(abstract_heaps::Empty.intersect(e), abstract_heaps::Empty);
            assert_subeffect_heap(abstract_heaps::Any.intersect(e), abstract_heaps::Any);
            assert_subeffect_heap(abstract_heaps::Frame.intersect(e), abstract_heaps::Frame);
        }
    }

    #[test]
    fn effect_heap_self_is_included() {
        assert!(abstract_heaps::Stack.includes(abstract_heaps::Stack));
        assert!(abstract_heaps::Any.includes(abstract_heaps::Any));
        assert!(abstract_heaps::Empty.includes(abstract_heaps::Empty));
    }

    #[test]
    fn effect_heap_frame_includes_stack_locals_and_pc() {
        assert_subeffect_heap(abstract_heaps::Stack, abstract_heaps::Frame);
        assert_subeffect_heap(abstract_heaps::Locals, abstract_heaps::Frame);
        assert_subeffect_heap(abstract_heaps::PC, abstract_heaps::Frame);
    }

    #[test]
    fn effect_heap_frame_is_stack_locals_and_pc() {
        let union = abstract_heaps::Stack.union(abstract_heaps::Locals.union(abstract_heaps::PC));
        assert_heap_bit_equal(abstract_heaps::Frame, union);
    }

    #[test]
    fn effect_heap_any_includes_some_subeffects() {
        assert_subeffect_heap(abstract_heaps::Allocator, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::Frame, abstract_heaps::Any);
        assert_subeffect_heap(abstract_heaps::Memory, abstract_heaps::Any);
    }

    #[test]
    fn effect_heap_display_exact_bits_match() {
        assert_eq!(format!("{}", abstract_heaps::Empty), "Empty");
        assert_eq!(format!("{}", abstract_heaps::PC), "PC");
        assert_eq!(format!("{}", abstract_heaps::Any), "Any");
        assert_eq!(format!("{}", abstract_heaps::Frame), "Frame");
        assert_eq!(format!("{}", abstract_heaps::Stack.union(abstract_heaps::Locals.union(abstract_heaps::PC))), "Frame");
    }

    #[test]
    fn effect_heap_display_multiple_bits() {
        assert_eq!(format!("{}", abstract_heaps::Stack.union(abstract_heaps::Locals.union(abstract_heaps::PC))), "Frame");
        assert_eq!(format!("{}", abstract_heaps::Stack.union(abstract_heaps::Locals)), "Stack|Locals");
        assert_eq!(format!("{}", abstract_heaps::PC.union(abstract_heaps::Allocator)), "PC|Allocator");
    }

    #[test]
    fn effect_any_includes_everything() {
        assert_subeffect(effects::Allocator, effects::Any);
        assert_subeffect(effects::Frame, effects::Any);
        assert_subeffect(effects::Memory, effects::Any);
        // Let's do a less standard effect too
        assert_subeffect(
            Effect::read_write(abstract_heaps::Control, abstract_heaps::Any),
            effects::Any
        );
    }

    #[test]
    fn effect_union_is_idempotent() {
        assert_bit_equal(
            Effect::read(abstract_heaps::Any)
                .union(Effect::write(abstract_heaps::Any)),
            effects::Any
        );
        assert_bit_equal(
            effects::Empty.union(effects::Empty),
            effects::Empty
        );
    }

    #[test]
    fn effect_union_contains_and_excludes() {
        assert_subeffect(
            effects::Control.union(effects::Frame),
            effects::Any
        );
        assert_not_subeffect(
            effects::Frame.union(effects::Locals),
            effects::PC
        );
    }

    #[test]
    fn effect_intersect_is_empty() {
        assert_subeffect(effects::Memory.intersect(effects::Control), effects::Empty);
        assert_subeffect(
            Effect::read_write(abstract_heaps::Allocator, abstract_heaps::Other)
                .intersect(Effect::read_write(abstract_heaps::Stack, abstract_heaps::PC)),
            effects::Empty
        )
    }

    #[test]
    fn effect_intersect_exact_match() {
        assert_subeffect(effects::Frame.intersect(effects::PC), effects::PC);
        assert_subeffect(effects::Allocator.intersect(effects::Allocator), effects::Allocator);
    }

    #[test]
    fn effect_display_exact_bits_match() {
        assert_eq!(format!("{}", effects::Empty), "Empty, Empty");
        assert_eq!(format!("{}", effects::PC), "PC, PC");
        assert_eq!(format!("{}", effects::Any), "Any, Any");
        assert_eq!(format!("{}", effects::Frame), "Frame, Frame");
        assert_eq!(format!("{}", effects::Stack.union(effects::Locals.union(effects::PC))), "Frame, Frame");
        assert_eq!(format!("{}", Effect::write(abstract_heaps::Control)), "Any, Control");
        assert_eq!(format!("{}", Effect::read_write(abstract_heaps::Allocator, abstract_heaps::Memory)), "Allocator, Memory");
    }

    #[test]
    fn effect_display_multiple_bits() {
        assert_eq!(format!("{}", effects::Stack.union(effects::Locals.union(effects::PC))), "Frame, Frame");
        assert_eq!(format!("{}", effects::Stack.union(effects::Locals)), "Stack|Locals, Stack|Locals");
        assert_eq!(format!("{}", effects::PC.union(effects::Allocator)), "PC|Allocator, PC|Allocator");
        assert_eq!(format!("{}", Effect::read_write(abstract_heaps::Other, abstract_heaps::PC)
            .union(Effect::read_write(abstract_heaps::Memory, abstract_heaps::Stack))),
            "Memory, Stack|PC"
        );
    }

}
