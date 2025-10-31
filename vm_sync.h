#ifndef RUBY_VM_SYNC_H
#define RUBY_VM_SYNC_H

#include "vm_debug.h"
#include "debug_counter.h"

#if USE_RUBY_DEBUG_LOG || RUBY_DEBUG || VM_CHECK_MODE > 0
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

bool rb_vm_locked_p(void);
void rb_vm_lock_body(LOCATION_ARGS);
void rb_vm_unlock_body(LOCATION_ARGS);

struct rb_ractor_struct;
NOINLINE(void rb_vm_lock_enter_body_cr(struct rb_ractor_struct *cr, unsigned int *lev APPEND_LOCATION_ARGS));
NOINLINE(void rb_vm_lock_enter_body_nb(unsigned int *lev APPEND_LOCATION_ARGS));
NOINLINE(void rb_vm_lock_enter_body(unsigned int *lev APPEND_LOCATION_ARGS));
void rb_vm_lock_leave_body_nb(unsigned int *lev APPEND_LOCATION_ARGS);
void rb_vm_lock_leave_body(unsigned int *lev APPEND_LOCATION_ARGS);
void rb_vm_barrier(void);

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

static inline void
rb_vm_lock(const char *file, int line)
{
    RB_DEBUG_COUNTER_INC(vm_sync_lock);

    if (rb_multi_ractor_p()) {
        rb_vm_lock_body(LOCATION_PARAMS);
    }
    else {
#if VM_CHECK_MODE > 0
        if (GET_VM()->running) {
            rb_vm_lock_body(LOCATION_PARAMS);
        }
#endif
    }
}

static inline void
rb_vm_unlock(const char *file, int line)
{
    if (rb_multi_ractor_p()) {
        rb_vm_unlock_body(LOCATION_PARAMS);
    }
    else {
#if VM_CHECK_MODE > 0
        if (GET_VM()->running) {
            rb_vm_unlock_body(LOCATION_PARAMS);
        }
#endif
    }
}

static inline void
rb_vm_lock_enter(unsigned int *lev, const char *file, int line)
{
    RB_DEBUG_COUNTER_INC(vm_sync_lock_enter);

    if (rb_multi_ractor_p()) {
        rb_vm_lock_enter_body(lev APPEND_LOCATION_PARAMS);
    }
    else {
#if VM_CHECK_MODE > 0
        if (GET_VM()->running) {
            rb_vm_lock_enter_body(lev APPEND_LOCATION_PARAMS);
        }
#endif
    }
}

static inline void
rb_vm_lock_enter_nb(unsigned int *lev, const char *file, int line)
{
    RB_DEBUG_COUNTER_INC(vm_sync_lock_enter_nb);

    if (rb_multi_ractor_p()) {
        rb_vm_lock_enter_body_nb(lev APPEND_LOCATION_PARAMS);
    }
    else {
#if VM_CHECK_MODE > 0
        if (GET_VM()->running) {
            rb_vm_lock_enter_body_nb(lev APPEND_LOCATION_PARAMS);
        }
#endif
    }
}

static inline void
rb_vm_lock_leave_nb(unsigned int *lev, const char *file, int line)
{
    if (rb_multi_ractor_p()) {
        rb_vm_lock_leave_body_nb(lev APPEND_LOCATION_PARAMS);
    }
    else {
#if VM_CHECK_MODE > 0
        if (GET_VM()->running) {
            rb_vm_lock_leave_body_nb(lev APPEND_LOCATION_PARAMS);
        }
#endif
    }
}

static inline void
rb_vm_lock_leave(unsigned int *lev, const char *file, int line)
{
    if (rb_multi_ractor_p()) {
        rb_vm_lock_leave_body(lev APPEND_LOCATION_PARAMS);
    }
    else {
#if VM_CHECK_MODE > 0
        if (GET_VM()->running) {
            rb_vm_lock_leave_body(lev APPEND_LOCATION_PARAMS);
        }
#endif
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

static inline unsigned int
rb_vm_unlock_all(const char *file, int line)
{
    rb_vm_t *vm = GET_VM();
    unsigned int saved_rec = vm->ractor.sync.lock_rec;
    unsigned int rec;
    if (!rb_vm_locked_p()) {
        return 0;
    }
    bool needs_unlock = rb_multi_ractor_p();
# if VM_CHECK_MODE > 0
    needs_unlock = true;
#endif
    if (needs_unlock) {
        while (vm->ractor.sync.lock_rec > 0) {
            rec = vm->ractor.sync.lock_rec;
            rb_vm_lock_leave(&rec, file, line);
        }
    }
    VM_ASSERT(vm->ractor.sync.lock_rec == 0);
    return saved_rec;
}

static inline void
rb_vm_relock_all(unsigned int lev, const char *file, int line)
{
    rb_vm_t *vm = GET_VM();
    unsigned int levout;
    ASSERT_vm_unlocking();
    if (lev == 0) return;
    bool needs_relock = rb_multi_ractor_p();
#if VM_CHECK_MODE > 0
    needs_relock = true;
#endif
    if (needs_relock) {
        rb_vm_lock(file, line);
        while (vm->ractor.sync.lock_rec < lev) {
            rb_vm_lock_enter(&levout, file, line);
        }
    }
    VM_ASSERT(vm->ractor.sync.lock_rec == lev);
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
#define RB_VM_UNLOCK_ALL() (RB_VM_LOCKED_P() ? rb_vm_unlock_all(__FILE__, __LINE__) : 0)
#define RB_VM_RELOCK_ALL(lev) rb_vm_relock_all(lev, __FILE__, __LINE__)

#endif // RUBY_VM_SYNC_H
