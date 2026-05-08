/**********************************************************************

  scheduler.h - Fiber scheduler.

  $Author$

  Copyright (C) 2026 Samuel Williams.

**********************************************************************/
#pragma once

// Advance the current fiber's runtime by n back-edges worth of work.
// Triggers preemption if the quantum is exhausted. Use in CPU-bound C
// extensions to participate in fiber scheduler fairness without releasing the GVL.
void rb_fiber_runtime_advance(uint32_t runtime);

// Set the preempted re-entrancy guard and yield the current fiber to the
// scheduler. Defined in scheduler.c. Use rb_fiber_scheduler_maybe_preempt()
// below for the guarded inline version, or call directly from timer interrupt
// handlers where the guard state is managed externally.
void rb_fiber_scheduler_preempt(rb_execution_context_t *ec);

// Forward declaration of rb_fiber_scheduler_yield.
VALUE rb_fiber_scheduler_yield(VALUE scheduler);

/**
 * Inline preemption check for non-blocking fibers.
 *
 * Yields to the scheduler when all three conditions hold:
 *   - The fiber is non-blocking  (thread->blocking == 0)
 *   - The fiber is not already in a preemption call  (!ec->preempted)
 *   - The fiber has consumed its scheduling quantum  (runtime >= quantum)
 *
 * Called from RUBY_VM_CHECK_INTS (every loop back-edge) and from
 * rb_fiber_runtime_advance (C extension work accounting).  The fast path
 * — no scheduler, or blocking fiber, or mid-quantum — compiles to a few
 * compare-and-branch instructions with no function call.
 */
static inline void
rb_fiber_scheduler_maybe_preempt(rb_execution_context_t *ec)
{
    if (UNLIKELY(ec->thread_ptr->blocking == 0 && !ec->preempted && ec->runtime >= ec->quantum)) {
        // Since we confirmed that blocking is 0, we can safely access the scheduler:
        VALUE scheduler = ec->thread_ptr->scheduler;

        // If the scheduler is set, we can preempt the fiber:
        if (scheduler != Qnil) {
            // Set the preempted flag to prevent re-entrancy:
            ec->preempted = 1;

            // Yield to the scheduler:
            rb_fiber_scheduler_yield(scheduler);
        }
    }
}
