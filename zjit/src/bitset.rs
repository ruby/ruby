type Entry = u128;

const ENTRY_NUM_BITS: usize = Entry::BITS as usize;

trait BitSetBackend<T: Into<usize> + Copy>{

    // Set bit at index to 1. Returns false if it was already set
    fn insert(&mut self, idx: T) -> bool;

    // Set all bits to 1.
    fn insert_all(&mut self);

    // Get bit value at index
    fn get(&self, idx: T) -> bool;

    // Modify self to
    fn intersect_with(&mut self, other: &Self) -> bool;

    // Number of bits
    fn num_bits(&self) -> usize;
}

#[derive(Clone)]
pub enum BitSet<T: Into<usize> + Copy> {
    Small(SmallBitSet<T>),
    Large(LargeBitSet<T>),
}

impl<T: Into<usize> + Copy> BitSet<T> {
    pub fn with_capacity(num_bits: usize) -> Self {
        if num_bits <= ENTRY_NUM_BITS as usize {
            BitSet::Small(SmallBitSet {
                bits: 0,
                num_bits,
                phantom: std::marker::PhantomData,
            })
        } else {
            BitSet::Large(LargeBitSet {
                entries: vec![0; num_bits.div_ceil(ENTRY_NUM_BITS)],
                num_bits,
                phantom: std::marker::PhantomData,
            })
        }
    }

    pub fn insert(&mut self, idx: T) -> bool {
        match self {
            BitSet::Small(inner) => inner.insert(idx),
            BitSet::Large(inner) => inner.insert(idx),
        }
    }

    pub fn insert_all(&mut self) {
        match self {
            BitSet::Small(inner) => inner.insert_all(),
            BitSet::Large(inner) => inner.insert_all(),
        }
    }

    pub fn get(&self, idx: T) -> bool {
        match self {
            BitSet::Small(inner) => inner.get(idx),
            BitSet::Large(inner) => inner.get(idx),
        }
    }

    pub fn intersect_with(&mut self, other: &Self) -> bool {
        match (self, other) {
            (BitSet::Small(a), BitSet::Small(b)) => a.intersect_with(b),
            (BitSet::Large(a), BitSet::Large(b)) => a.intersect_with(b),
            _ => panic!("BitSet type mismatch in intersect_with"),
        }
    }

    pub fn num_bits(&self) -> usize {
        match self {
            BitSet::Small(inner) => inner.num_bits(),
            BitSet::Large(inner) => inner.num_bits(),
        }
    }
}


#[derive(Clone)]
pub struct SmallBitSet<T: Into<usize> + Copy> {
    bits: Entry,
    num_bits: usize,
    phantom: std::marker::PhantomData<T>,
}

impl<T: Into<usize> + Copy> BitSetBackend<T> for SmallBitSet<T> {
    fn insert(&mut self, idx: T) -> bool {
        let idx = idx.into();
        debug_assert!(idx < self.num_bits);
        let mask = 1 << idx;
        let was_set = self.bits & mask != 0;
        self.bits |= mask;
        !was_set
    }

    fn insert_all(&mut self) {
        self.bits = (1 << self.num_bits) - 1;
    }

    fn get(&self, idx: T) -> bool {
        let idx = idx.into();
        debug_assert!(idx < self.num_bits);
        (self.bits >> idx) & 1 == 1
    }

    fn intersect_with(&mut self, other: &Self) -> bool {
        assert_eq!(self.num_bits, other.num_bits);
        let before = self.bits;
        self.bits &= other.bits;
        self.bits != before
    }

    fn num_bits(&self) -> usize {
        self.num_bits
    }
}

#[derive(Clone)]
pub struct LargeBitSet<T: Into<usize> + Copy> {
    entries: Vec<Entry>,
    num_bits: usize,
    phantom: std::marker::PhantomData<T>,
}

impl<T: Into<usize> + Copy> BitSetBackend<T> for LargeBitSet<T> {

    fn insert(&mut self, idx: T) -> bool {
        debug_assert!(idx.into() < self.num_bits);
        let entry_idx = idx.into() / ENTRY_NUM_BITS;
        let bit_idx = idx.into() % ENTRY_NUM_BITS;
        let newly_inserted = (self.entries[entry_idx] & (1 << bit_idx)) == 0;
        self.entries[entry_idx] |= 1 << bit_idx;
        newly_inserted
    }

    fn insert_all(&mut self) {
        for i in 0..self.entries.len() {
            self.entries[i] = !0;
        }
    }

    fn get(&self, idx: T) -> bool {
        debug_assert!(idx.into() < self.num_bits);
        let entry_idx = idx.into() / ENTRY_NUM_BITS;
        let bit_idx = idx.into() % ENTRY_NUM_BITS;
        (self.entries[entry_idx] & (1 << bit_idx)) != 0
    }

    /// `self` and `other` must have the same number of bits.
    fn intersect_with(&mut self, other: &Self) -> bool {
        assert_eq!(self.num_bits, other.num_bits);
        let mut changed = false;
        for i in 0..self.entries.len() {
            let before = self.entries[i];
            self.entries[i] &= other.entries[i];
            changed |= self.entries[i] != before;
        }
        changed
    }

    fn num_bits(&self) -> usize {
        self.num_bits
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
