
#ifndef RUBY_VM_SYNC_H
#define RUBY_VM_SYNC_H

#include "vm_debug.h"

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

bool rb_vm_locked_p(void);
void rb_vm_lock_body(LOCATION_ARGS);
void rb_vm_unlock_body(LOCATION_ARGS);
void rb_vm_lock_enter_body(unsigned int *lev APPEND_LOCATION_ARGS);
void rb_vm_lock_leave_body(unsigned int *lev APPEND_LOCATION_ARGS);
void rb_vm_barrier(void);

#if RUBY_DEBUG
// GET_VM()
#include "vm_core.h"
#endif

extern struct rb_ractor_struct *ruby_single_main_ractor; // ractor.c

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
    if (rb_multi_ractor_p()) {
        rb_vm_lock_body(LOCATION_PARAMS);
    }
}

static inline void
rb_vm_unlock(const char *file, int line)
{
    if (rb_multi_ractor_p()) {
        rb_vm_unlock_body(LOCATION_PARAMS);
    }
}

static inline void
rb_vm_lock_enter(unsigned int *lev, const char *file, int line)
{
    if (rb_multi_ractor_p()) {
        rb_vm_lock_enter_body(lev APPEND_LOCATION_PARAMS);
    }
}

static inline void
rb_vm_lock_leave(unsigned int *lev, const char *file, int line)
{
    if (rb_multi_ractor_p()) {
        rb_vm_lock_leave_body(lev APPEND_LOCATION_PARAMS);
    }
}

#define RB_VM_LOCKED_P()   rb_vm_locked_p()

#define RB_VM_LOCK()       rb_vm_lock(__FILE__, __LINE__)
#define RB_VM_UNLOCK()     rb_vm_unlock(__FILE__, __LINE__)

#define RB_VM_LOCK_ENTER_LEV(levp) rb_vm_lock_enter(levp, __FILE__, __LINE__)
#define RB_VM_LOCK_LEAVE_LEV(levp) rb_vm_lock_leave(levp, __FILE__, __LINE__)

#define RB_VM_LOCK_ENTER()  { unsigned int _lev; RB_VM_LOCK_ENTER_LEV(&_lev);
#define RB_VM_LOCK_LEAVE()    RB_VM_LOCK_LEAVE_LEV(&_lev); }

#if RUBY_DEBUG > 0
void ASSERT_vm_locking(void);
void ASSERT_vm_unlocking(void);
#else
#define ASSERT_vm_locking()
#define ASSERT_vm_unlocking()
#endif

#endif // RUBY_VM_SYNC_H
