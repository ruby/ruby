use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};

use mmtk::util::VMMutatorThread;

/// Ruby's GC-disable state, owned by the binding instead of mmtk-core.
///
/// mmtk-core cannot run a GC while collection is disabled, and every pause ends in `NotInGC`.
/// A forced `GC.start` therefore has to enable collection in mmtk-core, and mmtk-core alone
/// would lose the disabled state across that GC. The binding keeps the state here and mirrors
/// it into mmtk-core, where it holds at most one `disable_collection` once all callers return.
///
/// CRuby's fatal-signal handlers call `rb_gc_impl_gc_disable` and `rb_gc_impl_gc_enable`, and a
/// handler can interrupt a thread anywhere in this module. The state is therefore an atomic word.
/// `apply` runs one caller at a time. A caller that read an old state corrects mmtk-core before
/// it returns, so a stale step never undoes the result of an `apply` that already returned. A
/// handler that interrupts the applying thread does not wait for it, because it would wait
/// forever.
#[derive(Default)]
pub struct GcDisableState {
    state: AtomicU64,
    /// The thread that runs `apply`, as returned by `current_thread_id`, or 0.
    applier: AtomicUsize,
}

/// A nonzero value that is unique to the calling thread. It must be safe to call in a signal
/// handler. A Rust thread-local is not: this library is loaded with `dlopen`, so the first access
/// on a thread can allocate in `__tls_get_addr`. `pthread_self` only reads the thread pointer.
fn current_thread_id() -> usize {
    unsafe { libc::pthread_self() as usize }
}

#[derive(Clone, Copy)]
struct State {
    /// Set by `rb_gc_impl_gc_disable` and cleared by `rb_gc_impl_gc_enable`.
    internal_disabled: bool,
    /// Set and cleared by `GC.disable` and `GC.enable`.
    user_disabled: bool,
    /// Forced `GC.start` calls that enabled collection and wait for a pause.
    forced_gc_requests: u32,
    /// Set between `stop_all_mutators` and `resume_mutators`.
    in_pause: bool,
    /// Incremented when a pause ends. A pause serves every forced request made before it ends.
    pause_epoch: u32,
}

impl State {
    const INTERNAL_DISABLED: u64 = 1 << 0;
    const USER_DISABLED: u64 = 1 << 1;
    const IN_PAUSE: u64 = 1 << 2;
    const FORCED_SHIFT: u32 = 3;
    const FORCED_MAX: u32 = (1 << 29) - 1;
    const EPOCH_SHIFT: u32 = 32;

    fn decode(bits: u64) -> Self {
        Self {
            internal_disabled: bits & Self::INTERNAL_DISABLED != 0,
            user_disabled: bits & Self::USER_DISABLED != 0,
            in_pause: bits & Self::IN_PAUSE != 0,
            forced_gc_requests: (bits >> Self::FORCED_SHIFT) as u32 & Self::FORCED_MAX,
            pause_epoch: (bits >> Self::EPOCH_SHIFT) as u32,
        }
    }

    fn encode(self) -> u64 {
        debug_assert!(self.forced_gc_requests <= Self::FORCED_MAX);
        (self.internal_disabled as u64)
            | (self.user_disabled as u64) << 1
            | (self.in_pause as u64) << 2
            | (self.forced_gc_requests as u64) << Self::FORCED_SHIFT
            | (self.pause_epoch as u64) << Self::EPOCH_SHIFT
    }

    fn want_disabled(self) -> bool {
        (self.internal_disabled || self.user_disabled) && self.forced_gc_requests == 0
    }
}

impl GcDisableState {
    fn load(&self) -> State {
        State::decode(self.state.load(Ordering::SeqCst))
    }

    /// Returns the state before the update.
    fn update(&self, f: impl Fn(&mut State)) -> State {
        let bits = self
            .state
            .update(Ordering::SeqCst, Ordering::SeqCst, |bits| {
                let mut state = State::decode(bits);
                f(&mut state);
                state.encode()
            });
        State::decode(bits)
    }

    fn apply(&self) {
        let me = current_thread_id();

        // A signal handler interrupted this thread in `apply`. CRuby's handlers never return to
        // the interrupted code: they abort or longjmp. Apply the state and release `applier`,
        // so that a longjmp does not leave it held.
        if self.applier.load(Ordering::SeqCst) == me {
            self.mirror_into_mmtk();
            let _ = self
                .applier
                .compare_exchange(me, 0, Ordering::SeqCst, Ordering::SeqCst);
            return;
        }

        while self
            .applier
            .compare_exchange_weak(0, me, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            std::thread::yield_now();
        }
        self.mirror_into_mmtk();
        let _ = self
            .applier
            .compare_exchange(me, 0, Ordering::SeqCst, Ordering::SeqCst);
    }

    /// Brings mmtk-core to the state that `want_disabled` asks for. The binding is the only
    /// caller of `disable_collection` and `enable_collection`, so mmtk-core's status is the
    /// mirror.
    fn mirror_into_mmtk(&self) {
        let mmtk = crate::mmtk();
        loop {
            let want_disabled = self.load().want_disabled();
            let disabled = !mmtk.is_collection_enabled();
            if want_disabled == disabled {
                return;
            }

            if want_disabled {
                match mmtk.disable_collection() {
                    Ok(true) => {}
                    // Only if a signal handler ran `apply` on this thread and then returned.
                    // Remove the extra nesting level.
                    Ok(false) => {
                        mmtk.enable_collection();
                    }
                    // A pause is requested or running, or collection is not initialized. The end
                    // of that pause, or the initialization of collection, applies the state again.
                    Err(_) => return,
                }
            } else {
                mmtk.enable_collection();
            }
        }
    }

    /// GC workers run CRuby's `DURING_GC_COULD_MALLOC_REGION` in parallel. Its read-then-set of
    /// this flag is not atomic, so two workers can leave it set. Mutators are stopped during a
    /// pause, so writes made then are dropped, as mmtk-core dropped them before this state existed.
    pub fn set_internal_disabled(&self, disabled: bool) {
        let before = self.update(|state| {
            if !state.in_pause {
                state.internal_disabled = disabled;
            }
        });
        if !before.in_pause {
            self.apply();
        }
    }

    pub fn internal_disabled(&self) -> bool {
        self.load().internal_disabled
    }

    /// Returns the previous value.
    pub fn set_user_disabled(&self, disabled: bool) -> bool {
        let was = self
            .update(|state| state.user_disabled = disabled)
            .user_disabled;
        self.apply();
        was
    }

    pub fn user_disabled(&self) -> bool {
        self.load().user_disabled
    }

    /// `GC.start` (`force`) runs even when GC is disabled. `GC.stress` does not.
    pub fn handle_user_collection_request(
        &self,
        tls: VMMutatorThread,
        force: bool,
        exhaustive: bool,
    ) {
        let mmtk = crate::mmtk();

        if !force {
            mmtk.handle_user_collection_request(tls, false, exhaustive);
            return;
        }

        let epoch = self
            .update(|state| state.forced_gc_requests += 1)
            .pause_epoch;

        self.apply();
        mmtk.handle_user_collection_request(tls, true, exhaustive);

        self.update(|state| {
            if state.pause_epoch == epoch {
                state.forced_gc_requests = state.forced_gc_requests.saturating_sub(1);
            }
        });
        self.apply();
    }

    /// Called after mmtk-core has stopped every mutator and before GC work starts.
    pub fn on_pause_start(&self) {
        self.update(|state| state.in_pause = true);
    }

    /// Called after mmtk-core sets `NotInGC` at the end of a pause and before mutators resume,
    /// so no mutator can request another pause before the disabled state is applied.
    pub fn on_pause_end(&self) {
        self.update(|state| {
            state.in_pause = false;
            state.forced_gc_requests = 0;
            state.pause_epoch = state.pause_epoch.wrapping_add(1);
        });
        self.apply();
    }

    pub fn on_collection_initialized(&self) {
        self.apply();
    }
}
