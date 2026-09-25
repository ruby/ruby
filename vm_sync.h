#ifndef RUBY_VM_SYNC_H
#define RUBY_VM_SYNC_H

#include "vm_debug.h"
#include "debug_counter.h"

#if USE_RUBY_DEBUG_LOG
#define LOCATION_ARGS const char *file, int line
#define LOCATION_PARAMS file, line
#define APPEND_LOCATION_ARGS , const char *file, int line
#define APPEND_LOCATION_PARAMS , file, line
#else
#define LOCATION_ARGS void
#define LOCATION_PARAMS
#define APPEND_LOCATION_ARGS
#define APPEND_LOCATION_PARAMS
#endif

struct rb_ractor_struct;

bool rb_vm_locked_p(void);
void rb_vm_lock_body(LOCATION_ARGS);
void rb_vm_unlock_body(LOCATION_ARGS);

/* A call deferred out of a VM lock critical section; see rb_vm_call_when_unlocked(). */
struct rb_deferred_call {
    void (*func)(VALUE arg0, VALUE arg1);
    VALUE arg0, arg1;
};

/* Call func(arg0, arg1) once the outermost VM lock has been released -- or right away,
 * if the lock is not held.  For work that must not happen inside a critical section:
 * anything that dispatches a Ruby method, checks interrupts, or can raise.  arg0 and
 * arg1 are GC roots until the call runs.
 *
 * A pending call is dropped if the critical section is left by a non-local exit (see
 * rb_ec_vm_lock_rec_release): the operation that queued it did not complete, and a
 * longjmp is not a safe point at which to run Ruby. */
void rb_vm_call_when_unlocked(void (*func)(VALUE, VALUE), VALUE arg0, VALUE arg1);
void rb_vm_discard_deferred_calls(struct rb_ractor_struct *cr);

NOINLINE(void rb_vm_lock_enter_body_cr(struct rb_ractor_struct *cr, unsigned int *lev APPEND_LOCATION_ARGS));
NOINLINE(void rb_vm_lock_enter_body_nb(unsigned int *lev APPEND_LOCATION_ARGS));
NOINLINE(void rb_vm_lock_enter_body(unsigned int *lev APPEND_LOCATION_ARGS));
void rb_vm_lock_leave_body_nb(unsigned int *lev APPEND_LOCATION_ARGS);
void rb_vm_lock_leave_body(unsigned int *lev APPEND_LOCATION_ARGS);
void rb_vm_barrier(void);

RUBY_SYMBOL_EXPORT_BEGIN
VALUE rb_vm_lock_with_barrier(VALUE (*func)(void *args), void *args);
RUBY_SYMBOL_EXPORT_END

#if RUBY_DEBUG
// GET_VM()
#include "vm_core.h"
#endif

RUBY_EXTERN struct rb_ractor_struct *ruby_single_main_ractor; // ractor.c

static inline bool
rb_multi_ractor_p(void)
{
    if (LIKELY(ruby_single_main_ractor)) {
        // 0 on boot time.
        RUBY_ASSERT(GET_VM()->ractor.cnt <= 1);
        return false;
    }
    else {
        // multi-ractor mode can run ractor.cnt == 1
        return true;
    }
}

// The VM lock is a no-op in single ractor mode, where it is not needed for
// mutual exclusion. Debug builds take it anyway so that the lock bookkeeping
// and the assertions built on it are exercised outside of multi-ractor runs.
static inline bool
rb_vm_locking_needed_p(void)
{
#if RUBY_DEBUG
    return true;
#else
    return rb_multi_ractor_p();
#endif
}

static inline void
rb_vm_lock(const char *file, int line)
{
    RB_DEBUG_COUNTER_INC(vm_sync_lock);

    if (rb_vm_locking_needed_p()) {
        rb_vm_lock_body(LOCATION_PARAMS);
    }
}

static inline void
rb_vm_unlock(const char *file, int line)
{
    if (rb_vm_locking_needed_p()) {
        rb_vm_unlock_body(LOCATION_PARAMS);
    }
}

static inline void
rb_vm_lock_enter(unsigned int *lev, const char *file, int line)
{
    RB_DEBUG_COUNTER_INC(vm_sync_lock_enter);

    if (rb_vm_locking_needed_p()) {
        rb_vm_lock_enter_body(lev APPEND_LOCATION_PARAMS);
    }
}

static inline void
rb_vm_lock_enter_nb(unsigned int *lev, const char *file, int line)
{
    RB_DEBUG_COUNTER_INC(vm_sync_lock_enter_nb);

    if (rb_vm_locking_needed_p()) {
        rb_vm_lock_enter_body_nb(lev APPEND_LOCATION_PARAMS);
    }
}

static inline void
rb_vm_lock_leave_nb(unsigned int *lev, const char *file, int line)
{
    if (rb_vm_locking_needed_p()) {
        rb_vm_lock_leave_body_nb(lev APPEND_LOCATION_PARAMS);
    }
}

static inline void
rb_vm_lock_leave(unsigned int *lev, const char *file, int line)
{
    if (rb_vm_locking_needed_p()) {
        rb_vm_lock_leave_body(lev APPEND_LOCATION_PARAMS);
    }
}

static inline void
rb_vm_lock_enter_cr(struct rb_ractor_struct *cr, unsigned int *levp, const char *file, int line)
{
    RB_DEBUG_COUNTER_INC(vm_sync_lock_enter_cr);
    rb_vm_lock_enter_body_cr(cr, levp APPEND_LOCATION_PARAMS);
}

static inline void
rb_vm_lock_leave_cr(struct rb_ractor_struct *cr, unsigned int *levp, const char *file, int line)
{
    rb_vm_lock_leave_body(levp APPEND_LOCATION_PARAMS);
}

#define RB_VM_LOCKED_P()   rb_vm_locked_p()

#define RB_VM_LOCK()       rb_vm_lock(__FILE__, __LINE__)
#define RB_VM_UNLOCK()     rb_vm_unlock(__FILE__, __LINE__)

#define RB_VM_LOCK_ENTER_CR_LEV(cr, levp) rb_vm_lock_enter_cr(cr, levp, __FILE__, __LINE__)
#define RB_VM_LOCK_LEAVE_CR_LEV(cr, levp) rb_vm_lock_leave_cr(cr, levp, __FILE__, __LINE__)
#define RB_VM_LOCK_ENTER_LEV(levp) rb_vm_lock_enter(levp, __FILE__, __LINE__)
#define RB_VM_LOCK_LEAVE_LEV(levp) rb_vm_lock_leave(levp, __FILE__, __LINE__)

#define RB_VM_LOCK_ENTER()  { unsigned int _lev; RB_VM_LOCK_ENTER_LEV(&_lev);
#define RB_VM_LOCK_LEAVE()    RB_VM_LOCK_LEAVE_LEV(&_lev); }
#define RB_VM_LOCKING() \
    for (unsigned int vm_locking_level, vm_locking_do = (RB_VM_LOCK_ENTER_LEV(&vm_locking_level), 1); \
         vm_locking_do; RB_VM_LOCK_LEAVE_LEV(&vm_locking_level), vm_locking_do = 0)

#define RB_VM_LOCK_ENTER_LEV_NB(levp) rb_vm_lock_enter_nb(levp, __FILE__, __LINE__)
#define RB_VM_LOCK_LEAVE_LEV_NB(levp) rb_vm_lock_leave_nb(levp, __FILE__, __LINE__)
#define RB_VM_LOCK_ENTER_NO_BARRIER()  { unsigned int _lev; RB_VM_LOCK_ENTER_LEV_NB(&_lev);
#define RB_VM_LOCK_LEAVE_NO_BARRIER()    RB_VM_LOCK_LEAVE_LEV_NB(&_lev); }
#define RB_VM_LOCKING_NO_BARRIER() \
    for (unsigned int vm_locking_level, vm_locking_do = (RB_VM_LOCK_ENTER_LEV_NB(&vm_locking_level), 1); \
         vm_locking_do; RB_VM_LOCK_LEAVE_LEV_NB(&vm_locking_level), vm_locking_do = 0)

#if RUBY_DEBUG > 0
void RUBY_ASSERT_vm_locking(void);
void RUBY_ASSERT_vm_locking_with_barrier(void);
void RUBY_ASSERT_vm_unlocking(void);
#define ASSERT_vm_locking() RUBY_ASSERT_vm_locking()
#define ASSERT_vm_locking_with_barrier() RUBY_ASSERT_vm_locking_with_barrier()
#define ASSERT_vm_unlocking() RUBY_ASSERT_vm_unlocking()
#else
#define ASSERT_vm_locking()
#define ASSERT_vm_locking_with_barrier()
#define ASSERT_vm_unlocking()
#endif

#endif // RUBY_VM_SYNC_H
