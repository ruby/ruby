use std::sync::atomic::{AtomicUsize, Ordering};

use mmtk::util::heap::GCTriggerPolicy;
use mmtk::util::heap::SpaceStats;
use mmtk::Plan;
use mmtk::MMTK;
use once_cell::sync::OnceCell;

use crate::Ruby;

pub static RUBY_HEAP_TRIGGER_CONFIG: OnceCell<RubyHeapTriggerConfig> = OnceCell::new();

pub struct RubyHeapTriggerConfig {
    /// Min heap size
    pub min_heap_pages: usize,
    /// Max heap size
    pub max_heap_pages: usize,
    /// Minimum ratio of empty space after a GC before the heap will grow
    pub heap_pages_min_ratio: f64,
    /// Ratio the heap will grow by
    pub heap_pages_goal_ratio: f64,
    /// Maximum ratio of empty space after a GC before the heap will shrink
    pub heap_pages_max_ratio: f64,
}

pub struct RubyHeapTrigger {
    /// Target number of heap pages
    target_heap_pages: AtomicUsize,
}

impl GCTriggerPolicy<Ruby> for RubyHeapTrigger {
    fn is_gc_required(
        &self,
        space_full: bool,
        space: Option<SpaceStats<Ruby>>,
        plan: &dyn Plan<VM = Ruby>,
    ) -> bool {
        // Let the plan decide
        plan.collection_required(space_full, space)
    }

    fn on_gc_end(&self, mmtk: &'static MMTK<Ruby>) {
        if let Some(plan) = mmtk.get_plan().generational() {
            if plan.is_current_gc_nursery() {
                // Nursery GC
            } else {
                // Full GC
            }

            panic!("TODO: support for generational GC not implemented")
        } else {
            let used_pages = mmtk.get_plan().get_used_pages();

            let target_min =
                (used_pages as f64 * (1.0 + Self::get_config().heap_pages_min_ratio)) as usize;
            let target_max =
                (used_pages as f64 * (1.0 + Self::get_config().heap_pages_max_ratio)) as usize;
            let new_target =
                (((used_pages as f64) * (1.0 + Self::get_config().heap_pages_goal_ratio)) as usize)
                    .clamp(
                        Self::get_config().min_heap_pages,
                        Self::get_config().max_heap_pages,
                    );

            if used_pages < target_min || used_pages > target_max {
                self.target_heap_pages.store(new_target, Ordering::Relaxed);
            }
        }
    }

    fn is_heap_full(&self, plan: &dyn Plan<VM = Ruby>) -> bool {
        plan.get_reserved_pages() > self.target_heap_pages.load(Ordering::Relaxed)
    }

    fn get_current_heap_size_in_pages(&self) -> usize {
        self.target_heap_pages.load(Ordering::Relaxed)
    }

    fn get_max_heap_size_in_pages(&self) -> usize {
        Self::get_config().max_heap_pages
    }

    fn can_heap_size_grow(&self) -> bool {
        self.target_heap_pages.load(Ordering::Relaxed) < Self::get_config().max_heap_pages
    }
}

impl Default for RubyHeapTrigger {
    fn default() -> Self {
        let min_heap_pages = Self::get_config().min_heap_pages;

        Self {
            target_heap_pages: AtomicUsize::new(min_heap_pages),
        }
    }
}

impl RubyHeapTrigger {
    fn get_config<'b>() -> &'b RubyHeapTriggerConfig {
        RUBY_HEAP_TRIGGER_CONFIG
            .get()
            .expect("Attempt to use RUBY_HEAP_TRIGGER_CONFIG before it is initialized")
    }
}
