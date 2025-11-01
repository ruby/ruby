//! Optimized bitset implementation.

type Entry = u128;

const ENTRY_NUM_BITS: usize = Entry::BITS as usize;

#[derive(Clone)]
pub enum BitSet<T: Into<usize> + Copy> {
    Small {
        bits: Entry,
        num_bits: u8,
        phantom: std::marker::PhantomData<T>,
    },
    Large {
        entries: Vec<Entry>,
        num_bits: usize,
        phantom: std::marker::PhantomData<T>,
    },
}

impl<T: Into<usize> + Copy> BitSet<T> {
    pub fn with_capacity(num_bits: usize) -> Self {
        if num_bits <= ENTRY_NUM_BITS {
            BitSet::Small {
                bits: 0,
                num_bits: num_bits as u8,
                phantom: Default::default(),
            }
        } else {
            let num_entries = num_bits.div_ceil(ENTRY_NUM_BITS);
            BitSet::Large {
                entries: vec![0; num_entries],
                num_bits,
                phantom: Default::default(),
            }
        }
    }

    /// Returns whether the value was newly inserted: true if the set did not originally contain
    /// the bit, and false otherwise.
    pub fn insert(&mut self, idx: T) -> bool {
        match self {
            BitSet::Small { bits, num_bits, .. } => {
                debug_assert!(idx.into() < *num_bits as usize);
                let bit_idx = idx.into();
                let newly_inserted = (*bits & (1 << bit_idx)) == 0;
                *bits |= 1 << bit_idx;
                newly_inserted
            }
            BitSet::Large {
                entries, num_bits, ..
            } => {
                debug_assert!(idx.into() < *num_bits);
                let entry_idx = idx.into() / ENTRY_NUM_BITS;
                let bit_idx = idx.into() % ENTRY_NUM_BITS;
                let newly_inserted = (entries[entry_idx] & (1 << bit_idx)) == 0;
                entries[entry_idx] |= 1 << bit_idx;
                newly_inserted
            }
        }
    }

    /// Set all bits to 1.
    pub fn insert_all(&mut self) {
        match self {
            BitSet::Small { bits, .. } => {
                *bits = !0;
            }
            BitSet::Large { entries, .. } => {
                for i in 0..entries.len() {
                    entries[i] = !0;
                }
            }
        }
    }

    pub fn get(&self, idx: T) -> bool {
        match self {
            BitSet::Small { bits, num_bits, .. } => {
                debug_assert!(idx.into() < *num_bits as usize);
                let bit_idx = idx.into();
                bits & (1 << bit_idx) != 0
            }
            BitSet::Large {
                entries, num_bits, ..
            } => {
                debug_assert!(idx.into() < *num_bits);
                let entry_idx = idx.into() / ENTRY_NUM_BITS;
                let bit_idx = idx.into() % ENTRY_NUM_BITS;
                (entries[entry_idx] & (1 << bit_idx)) != 0
            }
        }
    }

    /// Modify `self` to only have bits set if they are also set in `other`. Returns true if `self`
    /// was modified, and false otherwise.
    /// `self` and `other` must have the same number of bits.
    pub fn intersect_with(&mut self, other: &Self) -> bool {
        match (self, other) {
            (
                BitSet::Small {
                    bits: self_bits,
                    num_bits: self_num_bits,
                    ..
                },
                BitSet::Small {
                    bits: other_bits,
                    num_bits: other_num_bits,
                    ..
                },
            ) => {
                assert_eq!(*self_num_bits, *other_num_bits);
                let before = *self_bits;
                *self_bits &= *other_bits;
                *self_bits != before
            }
            (
                BitSet::Large {
                    entries: self_entries,
                    num_bits: self_num_bits,
                    ..
                },
                BitSet::Large {
                    entries: other_entries,
                    num_bits: other_num_bits,
                    ..
                },
            ) => {
                assert_eq!(*self_num_bits, *other_num_bits);
                let mut changed = false;
                for i in 0..self_entries.len() {
                    let before = self_entries[i];
                    self_entries[i] &= other_entries[i];
                    changed |= self_entries[i] != before;
                }
                changed
            }
            _ => panic!("BitSets must have same variant for intersection"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::BitSet;

    mod small {
        use super::*;

        #[test]
        #[should_panic]
        fn get_over_capacity_panics() {
            let set: BitSet<usize> = BitSet::with_capacity(0);
            assert!(!set.get(0usize));
        }

        #[test]
        fn with_capacity_defaults_to_zero() {
            let set = BitSet::with_capacity(4);
            assert!(!set.get(0usize));
            assert!(!set.get(1usize));
            assert!(!set.get(2usize));
            assert!(!set.get(3usize));
        }

        #[test]
        fn insert_sets_bit() {
            let mut set = BitSet::with_capacity(4);
            assert!(set.insert(1usize));
            assert!(set.get(1usize));
        }

        #[test]
        fn insert_with_set_bit_returns_false() {
            let mut set = BitSet::with_capacity(4);
            assert!(set.insert(1usize));
            assert!(!set.insert(1usize));
        }

        #[test]
        fn insert_all_sets_all_bits() {
            let mut set = BitSet::with_capacity(4);
            set.insert_all();
            assert!(set.get(0usize));
            assert!(set.get(1usize));
            assert!(set.get(2usize));
            assert!(set.get(3usize));
        }

        #[test]
        #[should_panic]
        fn intersect_with_panics_with_different_num_bits() {
            let mut left: BitSet<usize> = BitSet::with_capacity(3);
            let right = BitSet::with_capacity(4);
            left.intersect_with(&right);
        }

        #[test]
        fn intersect_with_keeps_only_common_bits() {
            let mut left = BitSet::with_capacity(3);
            let mut right = BitSet::with_capacity(3);
            left.insert(0usize);
            left.insert(1usize);
            right.insert(1usize);
            right.insert(2usize);
            left.intersect_with(&right);
            assert!(!left.get(0usize));
            assert!(left.get(1usize));
            assert!(!left.get(2usize));
        }
    }

    mod large {
        use super::*;

        #[test]
        #[should_panic]
        fn get_over_capacity_panics() {
            let set: BitSet<usize> = BitSet::with_capacity(200);
            assert!(!set.get(201usize));
        }

        #[test]
        fn with_capacity_defaults_to_zero() {
            let set = BitSet::with_capacity(200);
            assert!(!set.get(0usize));
            assert!(!set.get(1usize));
            assert!(!set.get(2usize));
            assert!(!set.get(3usize));
        }

        #[test]
        fn insert_sets_bit() {
            let mut set = BitSet::with_capacity(200);
            assert!(set.insert(1usize));
            assert!(set.get(1usize));
        }

        #[test]
        fn insert_with_set_bit_returns_false() {
            let mut set = BitSet::with_capacity(200);
            assert!(set.insert(1usize));
            assert!(!set.insert(1usize));
        }

        #[test]
        fn insert_all_sets_all_bits() {
            let mut set = BitSet::with_capacity(200);
            set.insert_all();
            assert!(set.get(0usize));
            assert!(set.get(1usize));
            assert!(set.get(2usize));
            assert!(set.get(3usize));
        }

        #[test]
        #[should_panic]
        fn intersect_with_panics_with_different_num_bits() {
            let mut left: BitSet<usize> = BitSet::with_capacity(200);
            let right = BitSet::with_capacity(300);
            left.intersect_with(&right);
        }

        #[test]
        fn intersect_with_keeps_only_common_bits() {
            let mut left = BitSet::with_capacity(200);
            let mut right = BitSet::with_capacity(200);
            left.insert(0usize);
            left.insert(1usize);
            right.insert(1usize);
            right.insert(2usize);
            left.intersect_with(&right);
            assert!(!left.get(0usize));
            assert!(left.get(1usize));
            assert!(!left.get(2usize));
        }
    }
}
