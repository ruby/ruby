type Entry = u128;

const ENTRY_NUM_BITS: usize = Entry::BITS as usize;

// TODO(max): Make a `SmallBitSet` and `LargeBitSet` and switch between them if `num_bits` fits in
// `Entry`.
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

    pub fn get(&self, idx: T) -> bool {
        debug_assert!(idx.into() < self.num_bits);
        let entry_idx = idx.into() / ENTRY_NUM_BITS;
        let bit_idx = idx.into() % ENTRY_NUM_BITS;
        (self.entries[entry_idx] & (1 << bit_idx)) != 0
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
}
