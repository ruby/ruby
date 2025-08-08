/// This implementation was inspired by the type feedback module from Google's S6, which was
/// written in C++ for use with Python. This is a new implementation in Rust created for use with
/// Ruby instead of Python.
#[derive(Debug, Clone)]
pub struct Distribution<T: Copy + PartialEq + Default, const N: usize> {
    /// buckets and counts have the same length
    /// buckets[0] is always the most common item
    buckets: [T; N],
    counts: [usize; N],
    /// if there is no more room, increment the fallback
    other: usize,
    // TODO(max): Add count disparity, which can help determine when to reset the distribution
}

impl<T: Copy + PartialEq + Default, const N: usize> Distribution<T, N> {
    pub fn new() -> Self {
        Self { buckets: [Default::default(); N], counts: [0; N], other: 0 }
    }

    pub fn observe(&mut self, item: T) {
        for (bucket, count) in self.buckets.iter_mut().zip(self.counts.iter_mut()) {
            if *bucket == item || *count == 0 {
                *bucket = item;
                *count += 1;
                // Keep the most frequent item at the front
                self.bubble_up();
                return;
            }
        }
        self.other += 1;
    }

    /// Keep the highest counted bucket at index 0
    fn bubble_up(&mut self) {
        if N == 0 { return; }
        let max_index = self.counts.into_iter().enumerate().max_by_key(|(_, val)| *val).unwrap().0;
        if max_index != 0 {
            self.counts.swap(0, max_index);
            self.buckets.swap(0, max_index);
        }
    }

    pub fn each_item(&self) -> impl Iterator<Item = T> + '_ {
        self.buckets.iter().zip(self.counts.iter())
            .filter_map(|(&bucket, &count)| if count > 0 { Some(bucket) } else { None })
    }

    pub fn each_item_mut(&mut self) -> impl Iterator<Item = &mut T> + '_ {
        self.buckets.iter_mut().zip(self.counts.iter())
            .filter_map(|(bucket, &count)| if count > 0 { Some(bucket) } else { None })
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

#[derive(Debug)]
pub struct DistributionSummary<T: Copy + PartialEq + Default + std::fmt::Debug, const N: usize> {
    kind: DistributionKind,
    buckets: [T; N],
    // TODO(max): Determine if we need some notion of stability
}

const SKEW_THRESHOLD: f64 = 0.75;

impl<T: Copy + PartialEq + Default + std::fmt::Debug, const N: usize> DistributionSummary<T, N> {
    pub fn new(dist: &Distribution<T, N>) -> Self {
        #[cfg(debug_assertions)]
        {
            let first_count = dist.counts[0];
            for &count in &dist.counts[1..] {
                assert!(first_count >= count, "First count should be the largest");
            }
        }
        let num_seen = dist.counts.iter().sum::<usize>() + dist.other;
        let kind = if dist.other == 0 {
            // Seen <= N types total
            if dist.counts[0] == 0 {
                DistributionKind::Empty
            } else if dist.counts[1] == 0 {
                DistributionKind::Monomorphic
            } else if (dist.counts[0] as f64)/(num_seen as f64) >= SKEW_THRESHOLD {
                DistributionKind::SkewedPolymorphic
            } else {
                DistributionKind::Polymorphic
            }
        } else {
            // Seen > N types total; considered megamorphic
            if (dist.counts[0] as f64)/(num_seen as f64) >= SKEW_THRESHOLD {
                DistributionKind::SkewedMegamorphic
            } else {
                DistributionKind::Megamorphic
            }
        };
        Self { kind, buckets: dist.buckets }
    }

    pub fn is_monomorphic(&self) -> bool {
        self.kind == DistributionKind::Monomorphic
    }

    pub fn is_skewed_polymorphic(&self) -> bool {
        self.kind == DistributionKind::SkewedPolymorphic
    }

    pub fn is_skewed_megamorphic(&self) -> bool {
        self.kind == DistributionKind::SkewedMegamorphic
    }

    pub fn bucket(&self, idx: usize) -> T {
        assert!(idx < N, "index {idx} out of bounds for buckets[{N}]");
        self.buckets[idx]
    }
}

#[cfg(test)]
mod distribution_tests {
    use super::*;

    #[test]
    fn start_empty() {
        let dist = Distribution::<usize, 4>::new();
        assert_eq!(dist.other, 0);
        assert!(dist.counts.iter().all(|&b| b == 0));
    }

    #[test]
    fn observe_adds_record() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        assert_eq!(dist.buckets[0], 10);
        assert_eq!(dist.counts[0], 1);
        assert_eq!(dist.other, 0);
    }

    #[test]
    fn observe_increments_record() {
        let mut dist = Distribution::<usize, 4>::new();
        dist.observe(10);
        dist.observe(10);
        assert_eq!(dist.buckets[0], 10);
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
        assert_eq!(dist.buckets[0], 11);
        assert_eq!(dist.counts[0], 3);
        assert_eq!(dist.buckets[1], 10);
        assert_eq!(dist.counts[1], 2);
        assert_eq!(dist.other, 0);
    }

    #[test]
    fn observe_with_max_increments_other() {
        let mut dist = Distribution::<usize, 0>::new();
        dist.observe(10);
        assert!(dist.buckets.is_empty());
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
}
