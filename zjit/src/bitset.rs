//! Optimized bitset implementation.

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

    /// Clear a bit. Returns whether the bit was previously set.
    pub fn remove(&mut self, idx: T) -> bool {
        debug_assert!(idx.into() < self.num_bits);
        let entry_idx = idx.into() / ENTRY_NUM_BITS;
        let bit_idx = idx.into() % ENTRY_NUM_BITS;
        let was_set = (self.entries[entry_idx] & (1 << bit_idx)) != 0;
        self.entries[entry_idx] &= !(1 << bit_idx);
        was_set
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

    /// Modify `self` to have bits set if they are set in either `self` or `other`. Returns true if `self`
    /// was modified, and false otherwise.
    /// `self` and `other` must have the same number of bits.
    pub fn union_with(&mut self, other: &Self) -> bool {
        assert_eq!(self.num_bits, other.num_bits);
        let mut changed = false;
        for i in 0..self.entries.len() {
            let before = self.entries[i];
            self.entries[i] |= other.entries[i];
            changed |= self.entries[i] != before;
        }
        changed
    }

    /// Modify `self` to remove bits that are set in `other`. Returns true if `self`
    /// was modified, and false otherwise.
    /// `self` and `other` must have the same number of bits.
    pub fn difference_with(&mut self, other: &Self) -> bool {
        assert_eq!(self.num_bits, other.num_bits);
        let mut changed = false;
        for i in 0..self.entries.len() {
            let before = self.entries[i];
            self.entries[i] &= !other.entries[i];
            changed |= self.entries[i] != before;
        }
        changed
    }

    /// Check if two BitSets are equal.
    /// `self` and `other` must have the same number of bits.
    pub fn equals(&self, other: &Self) -> bool {
        assert_eq!(self.num_bits, other.num_bits);
        self.entries == other.entries
    }

    /// Returns an iterator over the indices of set bits.
    /// Only iterates over bits that are set, not all possible indices.
    pub fn iter_set_bits(&self) -> impl Iterator<Item = usize> + '_ {
        self.entries.iter().enumerate().flat_map(move |(entry_idx, &entry)| {
            let mut bits = entry;
            std::iter::from_fn(move || {
                if bits == 0 {
                    return None;
                }
                let bit_pos = bits.trailing_zeros() as usize;
                bits &= bits - 1; // Clear the lowest set bit
                Some(entry_idx * ENTRY_NUM_BITS + bit_pos)
            })
        }).filter(move |&idx| idx < self.num_bits)
    }
}

#[cfg(test)]
mod tests {
    use super::BitSet;

    fn set_with_capacity(num_bits: usize) -> BitSet<usize> {
        BitSet::with_capacity(num_bits)
    }

    #[test]
    #[should_panic]
    fn get_over_capacity_panics() {
        let set = set_with_capacity(0);
        assert!(!set.get(0));
    }

    #[test]
    fn with_capacity_defaults_to_zero() {
        let set = set_with_capacity(4);
        assert!(!set.get(0));
        assert!(!set.get(1));
        assert!(!set.get(2));
        assert!(!set.get(3));
    }

    #[test]
    fn insert_sets_bit() {
        let mut set = set_with_capacity(4);
        assert!(set.insert(1));
        assert!(set.get(1));
    }

    #[test]
    fn insert_with_set_bit_returns_false() {
        let mut set = set_with_capacity(4);
        assert!(set.insert(1));
        assert!(!set.insert(1));
    }

    #[test]
    fn insert_all_sets_all_bits() {
        let mut set = set_with_capacity(4);
        set.insert_all();
        assert!(set.get(0));
        assert!(set.get(1));
        assert!(set.get(2));
        assert!(set.get(3));
    }

    #[test]
    fn remove_clears_bit() {
        let mut set = set_with_capacity(4);
        set.insert(1);

        assert!(set.remove(1));
        assert!(!set.get(1));
        assert!(!set.remove(1));
    }

    #[test]
    #[should_panic]
    fn intersect_with_panics_with_different_num_bits() {
        let mut left = set_with_capacity(3);
        let right = set_with_capacity(4);
        left.intersect_with(&right);
    }
    #[test]
    fn intersect_with_keeps_only_common_bits() {
        let mut left = set_with_capacity(3);
        let mut right = set_with_capacity(3);
        left.insert(0);
        left.insert(1);
        right.insert(1);
        right.insert(2);
        left.intersect_with(&right);
        assert!(!left.get(0));
        assert!(left.get(1));
        assert!(!left.get(2));
    }

    #[test]
    fn union_with_sets_bits_from_both_inputs() {
        let mut left = set_with_capacity(4);
        let mut right = set_with_capacity(4);
        left.insert(0);
        right.insert(2);

        assert!(left.union_with(&right));
        assert!(left.get(0));
        assert!(left.get(2));
        assert!(!left.union_with(&right));
    }

    #[test]
    fn difference_with_removes_overlapping_bits() {
        let mut left = set_with_capacity(4);
        let mut right = set_with_capacity(4);
        left.insert(0);
        left.insert(1);
        right.insert(1);

        assert!(left.difference_with(&right));
        assert!(left.get(0));
        assert!(!left.get(1));
        assert!(!left.difference_with(&right));
    }

    #[test]
    fn equals_compares_entries() {
        let mut left = set_with_capacity(4);
        let mut right = set_with_capacity(4);
        left.insert(1);
        right.insert(1);
        assert!(left.equals(&right));

        right.insert(2);
        assert!(!left.equals(&right));
    }

    #[test]
    fn test_iter_set_bits() {
        let mut set = set_with_capacity(10);
        set.insert(1);
        set.insert(5);
        set.insert(9);

        let set_bits: Vec<usize> = set.iter_set_bits().collect();
        assert_eq!(set_bits, vec![1, 5, 9]);
    }

    #[test]
    fn test_iter_set_bits_empty() {
        let set = set_with_capacity(10);
        let set_bits: Vec<usize> = set.iter_set_bits().collect();
        assert_eq!(set_bits, vec![]);
    }

    #[test]
    fn test_iter_set_bits_all() {
        let mut set = set_with_capacity(5);
        set.insert_all();
        let set_bits: Vec<usize> = set.iter_set_bits().collect();
        assert_eq!(set_bits, vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn test_iter_set_bits_large() {
        let mut set = set_with_capacity(200);
        set.insert(0);
        set.insert(127);
        set.insert(128);
        set.insert(199);

        let set_bits: Vec<usize> = set.iter_set_bits().collect();
        assert_eq!(set_bits, vec![0, 127, 128, 199]);
    }
}
