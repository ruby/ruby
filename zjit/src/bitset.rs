type Entry = u128;

const ENTRY_NUM_BITS: usize = Entry::BITS as usize;

// TODO(max): Make a `SmallBitSet` and `LargeBitSet` and switch between them if `num_bits` fits in
// `Entry`.
#[derive(Clone)]
pub struct BitSet<T: Into<usize> + Copy> {
    entries: Vec<Entry>,
    num_bits: usize,
    phantom: std::marker::PhantomData<T>,
}

impl<T: Into<usize> + Copy> BitSet<T> {
    pub fn with_capacity(num_bits: usize) -> Self {
        let num_entries = num_bits.div_ceil(ENTRY_NUM_BITS);
        Self { entries: vec![0; num_entries], num_bits, phantom: Default::default() }
    }

    /// Returns whether the value was newly inserted: true if the set did not originally contain
    /// the bit, and false otherwise.
    pub fn insert(&mut self, idx: T) -> bool {
        debug_assert!(idx.into() < self.num_bits);
        let entry_idx = idx.into() / ENTRY_NUM_BITS;
        let bit_idx = idx.into() % ENTRY_NUM_BITS;
        let newly_inserted = (self.entries[entry_idx] & (1 << bit_idx)) == 0;
        self.entries[entry_idx] |= 1 << bit_idx;
        newly_inserted
    }

    /// Set all bits to 1.
    pub fn insert_all(&mut self) {
        for i in 0..self.entries.len() {
            self.entries[i] = !0;
        }
    }

    pub fn get(&self, idx: T) -> bool {
        debug_assert!(idx.into() < self.num_bits);
        let entry_idx = idx.into() / ENTRY_NUM_BITS;
        let bit_idx = idx.into() % ENTRY_NUM_BITS;
        (self.entries[entry_idx] & (1 << bit_idx)) != 0
    }

    /// Modify `self` to only have bits set if they are also set in `other`. Returns true if `self`
    /// was modified, and false otherwise.
    /// `self` and `other` must have the same number of bits.
    pub fn intersect_with(&mut self, other: &Self) -> bool {
        assert_eq!(self.num_bits, other.num_bits);
        let mut changed = false;
        for i in 0..self.entries.len() {
            let before = self.entries[i];
            self.entries[i] &= other.entries[i];
            changed |= self.entries[i] != before;
        }
        changed
    }
}

#[cfg(test)]
mod tests {
    use super::BitSet;

    #[test]
    #[should_panic]
    fn get_over_capacity_panics() {
        let set = BitSet::with_capacity(0);
        assert_eq!(set.get(0usize), false);
    }

    #[test]
    fn with_capacity_defaults_to_zero() {
        let set = BitSet::with_capacity(4);
        assert_eq!(set.get(0usize), false);
        assert_eq!(set.get(1usize), false);
        assert_eq!(set.get(2usize), false);
        assert_eq!(set.get(3usize), false);
    }

    #[test]
    fn insert_sets_bit() {
        let mut set = BitSet::with_capacity(4);
        assert_eq!(set.insert(1usize), true);
        assert_eq!(set.get(1usize), true);
    }

    #[test]
    fn insert_with_set_bit_returns_false() {
        let mut set = BitSet::with_capacity(4);
        assert_eq!(set.insert(1usize), true);
        assert_eq!(set.insert(1usize), false);
    }

    #[test]
    fn insert_all_sets_all_bits() {
        let mut set = BitSet::with_capacity(4);
        set.insert_all();
        assert_eq!(set.get(0usize), true);
        assert_eq!(set.get(1usize), true);
        assert_eq!(set.get(2usize), true);
        assert_eq!(set.get(3usize), true);
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
        assert_eq!(left.get(0usize), false);
        assert_eq!(left.get(1usize), true);
        assert_eq!(left.get(2usize), false);
    }
}
