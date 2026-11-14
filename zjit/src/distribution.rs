//! Type frequency distribution tracker.

use crate::options::NumProfiles;

#[derive(Debug, Clone)]
enum Buckets<T> {
    Empty,
    Single(T),
    Multiple(Vec<T>),
}

/// This implementation was inspired by the type feedback module from Google's S6, which was
/// written in C++ for use with Python. This is a new implementation in Rust created for use with
/// Ruby instead of Python.
#[derive(Debug, Clone)]
pub struct Distribution<T: Copy + PartialEq + Default, const N: usize> {
    /// Store the common monomorphic case inline. Allocate only for polymorphic profiles.
    buckets: Buckets<T>,
    /// `counts[0]` corresponds to the most common item.
    counts: [NumProfiles; N],
    /// if there is no more room, increment the fallback
    other: NumProfiles,
    // TODO(max): Add count disparity, which can help determine when to reset the distribution
}

impl<T: Copy + PartialEq + Default, const N: usize> Distribution<T, N> {
    pub fn new() -> Self {
        Self {
            buckets: Buckets::Empty,
            counts: [0; N],
            other: 0,
        }
    }

    pub fn observe(&mut self, item: T) {
        if matches!(&self.buckets, Buckets::Empty) {
            if N == 0 {
                self.other = self.other.saturating_add(1);
            } else {
                self.buckets = Buckets::Single(item);
                self.counts[0] = 1;
            }
            return;
        }

        if let Buckets::Single(existing) = &self.buckets {
            let existing = *existing;
            if existing == item {
                self.counts[0] = self.counts[0].saturating_add(1);
            } else if N == 1 {
                self.other = self.other.saturating_add(1);
                return;
            } else {
                let buckets = vec![existing, item];
                self.buckets = Buckets::Multiple(buckets);
                self.counts[1] = 1;
            }
            self.bubble_up();
            return;
        }

        let Buckets::Multiple(buckets) = &self.buckets else {
            unreachable!("empty distributions are handled above");
        };
        let existing_index = buckets.iter().position(|&bucket| bucket == item);
        if let Some(index) = existing_index {
            self.counts[index] = self.counts[index].saturating_add(1);
        } else if buckets.len() == N {
            self.other = self.other.saturating_add(1);
            return;
        } else {
            let index = buckets.len();
            let Buckets::Multiple(buckets) = &mut self.buckets else {
                unreachable!()
            };
            buckets.reserve_exact(1);
            buckets.push(item);
            self.counts[index] = 1;
        }

        // Keep the most frequent item at the front.
        self.bubble_up();
    }

    /// Count an item without recording it, as if all buckets were taken by other items.
    pub fn observe_other(&mut self) {
        self.other = self.other.saturating_add(1);
    }

    /// Keep the highest counted bucket at index 0
    fn bubble_up(&mut self) {
        let bucket_count = match &self.buckets {
            Buckets::Empty => 0,
            Buckets::Single(_) => 1,
            Buckets::Multiple(buckets) => buckets.len(),
        };
        if bucket_count < 2 {
            return;
        }

        let max_index = self.counts[..bucket_count]
            .iter()
            .enumerate()
            .max_by_key(|(_, val)| **val)
            .unwrap()
            .0;
        if max_index != 0 {
            self.counts.swap(0, max_index);
            let Buckets::Multiple(buckets) = &mut self.buckets else {
                unreachable!()
            };
            buckets.swap(0, max_index);
        }
    }

    fn len(&self) -> usize {
        match &self.buckets {
            Buckets::Empty => 0,
            Buckets::Single(_) => 1,
            Buckets::Multiple(buckets) => buckets.len(),
        }
    }

    pub fn each_item(&self) -> impl Iterator<Item = T> + '_ {
        let buckets: &[T] = match &self.buckets {
            Buckets::Empty => &[],
            Buckets::Single(bucket) => std::slice::from_ref(bucket),
            Buckets::Multiple(buckets) => buckets,
        };
        buckets.iter().copied()
    }

    pub fn each_item_mut(&mut self) -> impl Iterator<Item = &mut T> + '_ {
        let buckets: &mut [T] = match &mut self.buckets {
            Buckets::Empty => &mut [],
            Buckets::Single(bucket) => std::slice::from_mut(bucket),
            Buckets::Multiple(buckets) => buckets,
        };
        buckets.iter_mut()
    }
}

#[derive(PartialEq, Debug, Clone, Copy)]
enum DistributionKind {
    /// No types seen
    Empty,
    /// One type seen
    Monomorphic,
    /// Between 2 and (fixed) N types seen
    Polymorphic,
    /// Polymorphic, but with a significant skew towards one type
    SkewedPolymorphic,
    /// More than N types seen with no clear winner
    Megamorphic,
    /// Megamorphic, but with a significant skew towards one type
    SkewedMegamorphic,
}

#[derive(Debug, Clone)]
pub struct DistributionSummary<T: Copy + PartialEq + Default + std::fmt::Debug, const N: usize> {
    kind: DistributionKind,
    buckets: [T; N],
    // TODO(max): Determine if we need some notion of stability
}

const SKEW_THRESHOLD: f64 = 0.75;

impl<T: Copy + PartialEq + Default + std::fmt::Debug, const N: usize> DistributionSummary<T, N> {
    pub fn empty() -> Self {
        Self {
            kind: DistributionKind::Empty,
            buckets: [Default::default(); N],
        }
    }

    /// Construct a monomorphic summary from the single entry `item`.
    pub fn monomorphic(item: T) -> Self {
        assert!(N > 0, "need at least one bucket");
        let mut buckets = [Default::default(); N];
        buckets[0] = item;
        Self { kind: DistributionKind::Monomorphic, buckets }
    }

    pub fn new(dist: &Distribution<T, N>) -> Self {
        #[cfg(debug_assertions)]
        {
            let first_count = dist.counts[0];
            for &count in &dist.counts[1..] {
                assert!(first_count >= count, "First count should be the largest");
            }
        }
        let num_seen =
            dist.counts.iter().map(|&c| usize::from(c)).sum::<usize>() + usize::from(dist.other);
        let kind = if dist.other == 0 {
            // Seen <= N types total
            if dist.len() == 0 {
                DistributionKind::Empty
            } else if dist.len() == 1 {
                DistributionKind::Monomorphic
            } else if (dist.counts[0] as f64) / (num_seen as f64) >= SKEW_THRESHOLD {
                DistributionKind::SkewedPolymorphic
            } else {
                DistributionKind::Polymorphic
            }
        } else {
            // Seen > N types total; considered megamorphic
            if (dist.counts[0] as f64) / (num_seen as f64) >= SKEW_THRESHOLD {
                DistributionKind::SkewedMegamorphic
            } else {
                DistributionKind::Megamorphic
            }
        };
        let mut buckets = [Default::default(); N];
        for (bucket, item) in buckets.iter_mut().zip(dist.each_item()) {
            *bucket = item;
        }
        Self { kind, buckets }
    }

    pub fn is_monomorphic(&self) -> bool {
        self.kind == DistributionKind::Monomorphic
    }

    pub fn is_polymorphic(&self) -> bool {
        self.kind == DistributionKind::Polymorphic
    }

    pub fn is_skewed_polymorphic(&self) -> bool {
        self.kind == DistributionKind::SkewedPolymorphic
    }

    pub fn is_megamorphic(&self) -> bool {
        self.kind == DistributionKind::Megamorphic
    }

    pub fn is_skewed_megamorphic(&self) -> bool {
        self.kind == DistributionKind::SkewedMegamorphic
    }

    pub fn bucket(&self, idx: usize) -> T {
        assert!(idx < N, "index {idx} out of bounds for buckets[{N}]");
        self.buckets[idx]
    }

    pub fn buckets(&self) -> &[T] {
        &self.buckets
    }
}

#[cfg(test)]
mod distribution_tests {
    use super::*;

    #[test]
    fn start_empty() {
        let dist = Distribution::<usize, 4>::new();
        assert_eq!(dist.len(), 0);
        assert_eq!(dist.other, 0);
        assert!(dist.counts.iter().all(|&b| b == 0));
    }

    #[test]
    fn observe_adds_record() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        assert_eq!(dist.each_item().next(), Some(10));
        assert_eq!(dist.counts[0], 1);
        assert_eq!(dist.other, 0);
        assert!(matches!(dist.buckets, Buckets::Single(10)));
    }

    #[test]
    fn observe_increments_record() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(10);
        assert_eq!(dist.each_item().next(), Some(10));
        assert_eq!(dist.counts[0], 2);
        assert_eq!(dist.other, 0);
    }

    #[test]
    fn observe_two() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(10);
        dist.observe(11);
        dist.observe(11);
        dist.observe(11);
        assert_eq!(dist.each_item().next(), Some(11));
        assert_eq!(dist.counts[0], 3);
        assert_eq!(dist.each_item().nth(1), Some(10));
        assert_eq!(dist.counts[1], 2);
        assert_eq!(dist.other, 0);
        assert!(matches!(dist.buckets, Buckets::Multiple(_)));
    }

    #[test]
    fn tied_counts_keep_the_latest_item_first() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(11);
        assert_eq!(dist.each_item().collect::<Vec<_>>(), vec![11, 10]);
        assert_eq!(dist.counts[..2], [1, 1]);
    }

    #[test]
    fn one_bucket_keeps_tracking_its_item_after_overflow() {
        let mut dist = Distribution::<usize, 1>::new();
        dist.observe(10);
        dist.observe(20);
        dist.observe(10);
        assert_eq!(dist.each_item().collect::<Vec<_>>(), vec![10]);
        assert_eq!(dist.counts, [2]);
        assert_eq!(dist.other, 1);
    }

    #[test]
    fn each_item_mut_visits_inline_and_heap_buckets() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        for item in dist.each_item_mut() {
            *item += 1;
        }
        assert_eq!(dist.each_item().collect::<Vec<_>>(), vec![11]);

        dist.observe(20);
        for item in dist.each_item_mut() {
            *item += 1;
        }
        assert_eq!(dist.each_item().collect::<Vec<_>>(), vec![21, 12]);
    }

    #[test]
    fn observe_with_max_increments_other() {
        let mut dist = Distribution::<usize, 0>::new();
        dist.observe(10);
        assert_eq!(dist.len(), 0);
        assert!(dist.counts.is_empty());
        assert_eq!(dist.other, 1);
    }

    #[test]
    fn empty_distribution_returns_empty_summary() {
        let dist = Distribution::<usize, 4>::new();
        let summary = DistributionSummary::new(&dist);
        assert_eq!(summary.kind, DistributionKind::Empty);
    }

    #[test]
    fn monomorphic_distribution_returns_monomorphic_summary() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(10);
        let summary = DistributionSummary::new(&dist);
        assert_eq!(summary.kind, DistributionKind::Monomorphic);
        assert_eq!(summary.buckets[0], 10);
        assert_eq!(summary.buckets(), &[10, 0, 0, 0]);
    }

    #[test]
    fn polymorphic_distribution_returns_polymorphic_summary() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(11);
        dist.observe(11);
        let summary = DistributionSummary::new(&dist);
        assert_eq!(summary.kind, DistributionKind::Polymorphic);
        assert_eq!(summary.buckets[0], 11);
        assert_eq!(summary.buckets[1], 10);
    }

    #[test]
    fn skewed_polymorphic_distribution_returns_skewed_polymorphic_summary() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(11);
        dist.observe(11);
        dist.observe(11);
        let summary = DistributionSummary::new(&dist);
        assert_eq!(summary.kind, DistributionKind::SkewedPolymorphic);
        assert_eq!(summary.buckets[0], 11);
        assert_eq!(summary.buckets[1], 10);
    }

    #[test]
    fn megamorphic_distribution_returns_megamorphic_summary() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(11);
        dist.observe(12);
        dist.observe(13);
        dist.observe(14);
        dist.observe(11);
        let summary = DistributionSummary::new(&dist);
        assert_eq!(summary.kind, DistributionKind::Megamorphic);
        assert_eq!(summary.buckets[0], 11);
    }

    #[test]
    fn skewed_megamorphic_distribution_returns_skewed_megamorphic_summary() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(11);
        dist.observe(11);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(12);
        dist.observe(13);
        dist.observe(14);
        let summary = DistributionSummary::new(&dist);
        assert_eq!(summary.kind, DistributionKind::SkewedMegamorphic);
        assert_eq!(summary.buckets[0], 12);
    }

    #[test]
    fn distribution_header_is_smaller_than_fixed_bucket_storage() {
        type ProfileType = [usize; 2];
        let old_fixed_size =
            std::mem::size_of::<ProfileType>() * 8 + std::mem::size_of::<NumProfiles>() * 9;
        assert!(std::mem::size_of::<Distribution<ProfileType, 8>>() < old_fixed_size,);
    }
}
