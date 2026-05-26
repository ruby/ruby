//! A GC trigger that adjusts the heap size based on the CPU overhead of GC.
//!
//! This is an implementation of the heap sizing policy described in
//! Tavakolisomeh, Shimchenko, Österlund, Bruno, Ferreira, Wrigstad,
//! "Heap Size Adjustment with CPU Control", MPLR '23.
//! <https://doi.org/10.1145/3617651.3622988>
//!
//! The idea: rather than letting heap size control GC frequency, let a
//! user-supplied *target GC CPU overhead* control the heap size. After each GC
//! cycle, we measure the GC CPU overhead (fraction of process CPU time spent
//! in GC) and compare it to the target. If GC is over budget we grow the heap
//! (reducing GC frequency); if it is under budget we shrink the heap (trading
//! memory for more frequent collections).
//!
//! ## Algorithm
//!
//! After each GC cycle we compute, using an average of the last `n` cycles:
//!
//! ```text
//! GC_CPU             = T_GC / T_APP                                  (Eq. 1)
//! overhead_error     = GC_CPU - target                                (Eq. 2)
//! sigmoid_error      = 1 / (1 + e^(-overhead_error))                  (Eq. 3)
//! adjustment_factor  = sigmoid_error + 0.5   (in (0.5, 1.5))          (Eq. 4)
//! new_size           = current_size * adjustment_factor               (Eq. 5)
//! ```
//!
//! where:
//! - `T_GC` is the wall-clock duration of each GC cycle.
//! - `T_APP` is process CPU time elapsed between consecutive GC cycles (sum of
//!   CPU time over all threads — mutators, GC workers, compilers, etc.), read
//!   via `clock_gettime(CLOCK_PROCESS_CPUTIME_ID)`.
//!
//! The final heap size is then clamped to the range
//! `[max(1.1 * used, min_heap_pages), max_heap_pages]`, providing 10% headroom
//! above current live memory to avoid triggering GC on an effectively-empty
//! heap.
//!
//! ## Differences from the paper
//!
//! The paper targets ZGC, a concurrent generational collector. MMTk's Ruby
//! binding currently ships stop-the-world collectors (Immix, MarkSweep). The
//! paper's formula still applies: with a STW collector the process CPU time
//! during GC closely tracks the wall-clock GC time, and mutator CPU time
//! during the mutator phase is correctly attributed. For generational plans
//! we skip nursery-only GCs, consistent with MemBalancer.

use std::sync::atomic::AtomicUsize;
use std::sync::atomic::Ordering;
use std::sync::Mutex;

use mmtk::util::heap::GCTriggerPolicy;
use mmtk::util::heap::SpaceStats;
use mmtk::Plan;
use mmtk::MMTK;
use once_cell::sync::OnceCell;

use crate::Ruby;

pub static CPU_HEAP_TRIGGER_CONFIG: OnceCell<CpuHeapTriggerConfig> = OnceCell::new();

/// Configuration for the [`CpuHeapTrigger`].
pub struct CpuHeapTriggerConfig {
    /// Lower bound on heap size (in pages). The trigger will never shrink below
    /// this value.
    pub min_heap_pages: usize,
    /// Upper bound on heap size (in pages). The trigger will never grow above
    /// this value.
    pub max_heap_pages: usize,
    /// Initial heap size (in pages).
    pub initial_heap_pages: usize,
    /// Target GC CPU overhead as a fraction of total process CPU time. For
    /// example, `0.15` means the policy will try to keep GC CPU usage near 15%.
    /// Valid range: `(0.0, 1.0)`.
    pub target_gc_cpu: f64,
    /// Number of recent GC cycles averaged together when computing the CPU
    /// overhead signal. Smoothes out short-term fluctuations. The paper uses 3.
    pub window_size: usize,
}

/// A single GC cycle's timing measurements.
#[derive(Clone, Copy, Debug, Default)]
struct GcSample {
    /// Wall-clock seconds spent inside this GC cycle.
    gc_seconds: f64,
    /// Seconds of process CPU time elapsed since the previous GC cycle ended.
    /// This covers both mutator time and (on multi-threaded mutators) any
    /// mutator CPU time consumed in parallel with the previous GC.
    app_cpu_seconds: f64,
}

struct CpuHeapTriggerState {
    /// Ring buffer of the last `window_size` samples. Oldest-first.
    samples: Vec<GcSample>,
    /// Wall-clock time when the current GC cycle started. `None` when no GC is
    /// in progress.
    gc_start_wall: Option<std::time::Instant>,
    /// Process CPU time (seconds) recorded at the end of the previous GC
    /// cycle. `None` until the first cycle completes.
    last_gc_end_cpu: Option<f64>,
}

impl CpuHeapTriggerState {
    fn new() -> Self {
        Self {
            samples: Vec::new(),
            gc_start_wall: None,
            last_gc_end_cpu: None,
        }
    }

    /// Pushes a new sample, dropping the oldest when the window is full.
    fn push_sample(&mut self, sample: GcSample, window_size: usize) {
        if self.samples.len() >= window_size {
            self.samples.remove(0);
        }
        self.samples.push(sample);
    }

    /// Returns the arithmetic mean GC CPU overhead across the window, or
    /// `None` if we don't yet have a full sample (which happens on the first
    /// GC cycle — we have no baseline for `app_cpu_seconds`).
    fn mean_gc_cpu(&self) -> Option<f64> {
        if self.samples.is_empty() {
            return None;
        }
        let total_gc: f64 = self.samples.iter().map(|s| s.gc_seconds).sum();
        let total_app: f64 = self.samples.iter().map(|s| s.app_cpu_seconds).sum();
        if total_app <= 0.0 {
            return None;
        }
        Some(total_gc / total_app)
    }
}

pub struct CpuHeapTrigger {
    /// Target heap size in pages. Updated at the end of each GC cycle.
    target_heap_pages: AtomicUsize,
    /// Mutable timing state. Wrapped in a `Mutex` because `on_gc_start` and
    /// `on_gc_end` are the only mutation sites and they are not on an
    /// allocation hot path; avoiding the complexity of lock-free state is
    /// worth the trivial contention.
    state: Mutex<CpuHeapTriggerState>,
}

impl Default for CpuHeapTrigger {
    fn default() -> Self {
        let cfg = Self::get_config();
        Self {
            target_heap_pages: AtomicUsize::new(cfg.initial_heap_pages),
            state: Mutex::new(CpuHeapTriggerState::new()),
        }
    }
}

impl GCTriggerPolicy<Ruby> for CpuHeapTrigger {
    fn is_gc_required(
        &self,
        space_full: bool,
        space: Option<SpaceStats<Ruby>>,
        plan: &dyn Plan<VM = Ruby>,
    ) -> bool {
        // Let the plan decide, matching the other triggers.
        plan.collection_required(space_full, space)
    }

    fn on_gc_start(&self, _mmtk: &'static MMTK<Ruby>) {
        let mut state = self.state.lock().unwrap();
        state.gc_start_wall = Some(std::time::Instant::now());
    }

    fn on_gc_end(&self, mmtk: &'static MMTK<Ruby>) {
        // Skip nursery-only GCs for generational plans. The heap resizing
        // decision is driven by the (much more expensive) full collections
        // where the signal-to-noise ratio is high enough to be useful.
        if let Some(gen_plan) = mmtk.get_plan().generational() {
            if gen_plan.is_current_gc_nursery() {
                return;
            }
        }

        let cfg = Self::get_config();
        let gc_end_cpu = process_cpu_time_seconds();

        let mut state = self.state.lock().unwrap();

        // Duration of this GC cycle (wall clock).
        let gc_seconds = state
            .gc_start_wall
            .take()
            .map(|start| start.elapsed().as_secs_f64())
            .unwrap_or(0.0);

        // Process CPU time elapsed since the previous GC cycle ended. We
        // require at least one previous end timestamp to produce a valid
        // sample — without it we cannot compute `T_APP`.
        if let (Some(last_end), Some(now)) = (state.last_gc_end_cpu, gc_end_cpu) {
            let app_cpu_seconds = (now - last_end).max(0.0);
            // Only record non-degenerate samples to avoid poisoning the window
            // with zero-time entries from back-to-back GCs.
            if app_cpu_seconds > 0.0 {
                state.push_sample(
                    GcSample {
                        gc_seconds,
                        app_cpu_seconds,
                    },
                    cfg.window_size,
                );
            }
        }
        state.last_gc_end_cpu = gc_end_cpu;

        // Compute the new heap size only when we have samples to average over.
        if let Some(gc_cpu) = state.mean_gc_cpu() {
            // Drop the lock before doing the (relatively cheap) math and
            // atomic update; nothing below needs the state.
            drop(state);

            let overhead_error = gc_cpu - cfg.target_gc_cpu; // Eq. (2)
            let sigmoid_error = sigmoid(overhead_error); // Eq. (3)
            let adjustment_factor = sigmoid_error + 0.5; // Eq. (4), range (0.5, 1.5)

            let current = self.target_heap_pages.load(Ordering::Relaxed);
            let suggested = ((current as f64) * adjustment_factor) as usize; // Eq. (5)

            // Clamp:
            // - upper bound: configured max
            // - lower bound: max(1.1 * used, min) — 10% headroom above current
            //   live memory, so we never request a heap so small that GC is
            //   triggered immediately on return from this one.
            let used = mmtk.get_plan().get_used_pages();
            let floor = ((used as f64) * 1.1).ceil() as usize;
            let lower = floor.max(cfg.min_heap_pages).min(cfg.max_heap_pages);
            let upper = cfg.max_heap_pages;
            let new_target = suggested.clamp(lower, upper);

            self.target_heap_pages.store(new_target, Ordering::Relaxed);

            info!(
                "CpuHeapTrigger: gc_cpu={:.4} target={:.4} factor={:.4} \
                 pages {} -> {} (used={}, clamp=[{}, {}])",
                gc_cpu,
                cfg.target_gc_cpu,
                adjustment_factor,
                current,
                new_target,
                used,
                lower,
                upper
            );
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

impl CpuHeapTrigger {
    fn get_config<'b>() -> &'b CpuHeapTriggerConfig {
        CPU_HEAP_TRIGGER_CONFIG
            .get()
            .expect("Attempt to use CPU_HEAP_TRIGGER_CONFIG before it is initialized")
    }
}

/// Standard logistic sigmoid. Returns 0.5 when x == 0, asymptotes to 0 and 1.
fn sigmoid(x: f64) -> f64 {
    1.0 / (1.0 + (-x).exp())
}

/// Reads the process-wide CPU time as a floating-point number of seconds,
/// summed across all threads of this process. Returns `None` if the clock
/// query fails (which should be essentially impossible on supported
/// platforms).
fn process_cpu_time_seconds() -> Option<f64> {
    let mut ts = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: `clock_gettime` writes exactly `sizeof(timespec)` bytes to the
    // pointer we pass, which is a valid local stack allocation.
    let rc = unsafe { libc::clock_gettime(libc::CLOCK_PROCESS_CPUTIME_ID, &mut ts) };
    if rc != 0 {
        return None;
    }
    Some((ts.tv_sec as f64) + (ts.tv_nsec as f64) / 1_000_000_000.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sigmoid_is_well_behaved() {
        assert!((sigmoid(0.0) - 0.5).abs() < 1e-12);
        assert!(sigmoid(-100.0) < 1e-9);
        assert!(sigmoid(100.0) > 1.0 - 1e-9);
        // Monotonic.
        assert!(sigmoid(-1.0) < sigmoid(0.0));
        assert!(sigmoid(0.0) < sigmoid(1.0));
    }

    #[test]
    fn adjustment_factor_is_within_paper_bounds() {
        // Eq. (4): adjustment_factor = sigmoid(e) + 0.5 must lie in (0.5, 1.5).
        for e in [-10.0_f64, -1.0, 0.0, 1.0, 10.0] {
            let f = sigmoid(e) + 0.5;
            assert!(f > 0.5 && f < 1.5, "factor {f} out of range for e={e}");
        }
    }

    #[test]
    fn mean_gc_cpu_is_total_weighted() {
        let mut state = CpuHeapTriggerState::new();
        state.push_sample(
            GcSample {
                gc_seconds: 1.0,
                app_cpu_seconds: 10.0,
            },
            3,
        );
        state.push_sample(
            GcSample {
                gc_seconds: 3.0,
                app_cpu_seconds: 10.0,
            },
            3,
        );
        // (1 + 3) / (10 + 10) = 0.2
        assert!((state.mean_gc_cpu().unwrap() - 0.2).abs() < 1e-12);
    }

    #[test]
    fn window_drops_oldest() {
        let mut state = CpuHeapTriggerState::new();
        for i in 0..5 {
            state.push_sample(
                GcSample {
                    gc_seconds: i as f64,
                    app_cpu_seconds: 1.0,
                },
                3,
            );
        }
        assert_eq!(state.samples.len(), 3);
        // After pushing 0,1,2,3,4 with window 3, we should have [2,3,4].
        assert_eq!(state.samples[0].gc_seconds, 2.0);
        assert_eq!(state.samples[2].gc_seconds, 4.0);
    }

    #[test]
    fn no_sample_without_prior_gc() {
        // First GC cycle cannot produce a sample (no previous end time). The
        // push happens only when last_gc_end_cpu is Some.
        let state = CpuHeapTriggerState::new();
        assert!(state.mean_gc_cpu().is_none());
    }
}
