#include "vm_core.h"
#include "vm_sync.h"
#include "ractor.h"
#include "vm_debug.h"
#include "gc.h"

static bool vm_barrier_finish_p(rb_vm_t *vm);

static bool
vm_locked(rb_vm_t *vm)
{
    return vm->ractor.sync.lock_owner == GET_RACTOR();
}

#if RUBY_DEBUG > 0
void
ASSERT_vm_locking(void)
{
    if (rb_multi_ractor_p()) {
        rb_vm_t *vm = GET_VM();
        VM_ASSERT(vm_locked(vm));
    }
}

void
ASSERT_vm_unlocking(void)
{
    if (rb_multi_ractor_p()) {
        rb_vm_t *vm = GET_VM();
        VM_ASSERT(!vm_locked(vm));
    }
}
#endif

bool
rb_vm_locked_p(void)
{
    return vm_locked(GET_VM());
}

static void
vm_lock_enter(rb_vm_t *vm, bool locked, unsigned int *lev APPEND_LOCATION_ARGS)
{
    if (locked) {
        ASSERT_vm_locking();
    }
    else {
        rb_ractor_t *cr = GET_RACTOR();
#if RACTOR_CHECK_MODE
        // locking ractor and acquire VM lock will cause deadlock
        VM_ASSERT(cr->locked_by != cr->self);
#endif

        // lock
        rb_native_mutex_lock(&vm->ractor.sync.lock);
        VM_ASSERT(vm->ractor.sync.lock_owner == NULL);
        vm->ractor.sync.lock_owner = cr;

        // barrier
        while (vm->ractor.sync.barrier_waiting) {
            unsigned int barrier_cnt = vm->ractor.sync.barrier_cnt;
            rb_thread_t *th = GET_THREAD();
            bool running;

            RB_GC_SAVE_MACHINE_CONTEXT(th);

            if (rb_ractor_status_p(cr, ractor_running)) {
                rb_vm_ractor_blocking_cnt_inc(vm, cr, __FILE__, __LINE__);
                running = true;
            }
            else {
                running = false;
            }
            VM_ASSERT(rb_ractor_status_p(cr, ractor_blocking));

            if (vm_barrier_finish_p(vm)) {
                RUBY_DEBUG_LOG("wakeup barrier owner", 0);
                rb_native_cond_signal(&vm->ractor.sync.barrier_cond);
            }
            else {
                RUBY_DEBUG_LOG("wait for barrier finish", 0);
            }

            // wait for restart
            while (barrier_cnt == vm->ractor.sync.barrier_cnt) {
                vm->ractor.sync.lock_owner = NULL;
                rb_native_cond_wait(&cr->barrier_wait_cond, &vm->ractor.sync.lock);
                VM_ASSERT(vm->ractor.sync.lock_owner == NULL);
                vm->ractor.sync.lock_owner = cr;
            }

            RUBY_DEBUG_LOG("barrier is released. Acquire vm_lock", 0);

            if (running) {
                rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);
            }
        }

        VM_ASSERT(vm->ractor.sync.lock_rec == 0);
        VM_ASSERT(vm->ractor.sync.lock_owner == cr);
    }

    vm->ractor.sync.lock_rec++;
    *lev = vm->ractor.sync.lock_rec;

    RUBY_DEBUG_LOG2(file, line, "rec:%u owner:%d", vm->ractor.sync.lock_rec, rb_ractor_id(vm->ractor.sync.lock_owner));
}

static void
vm_lock_leave(rb_vm_t *vm, unsigned int *lev APPEND_LOCATION_ARGS)
{
    RUBY_DEBUG_LOG2(file, line, "rec:%u owner:%d", vm->ractor.sync.lock_rec, rb_ractor_id(vm->ractor.sync.lock_owner));

    ASSERT_vm_locking();
    VM_ASSERT(vm->ractor.sync.lock_rec > 0);
    VM_ASSERT(vm->ractor.sync.lock_rec == *lev);

    vm->ractor.sync.lock_rec--;
    *lev = vm->ractor.sync.lock_rec;

    if (vm->ractor.sync.lock_rec == 0) {
        vm->ractor.sync.lock_owner = NULL;
        rb_native_mutex_unlock(&vm->ractor.sync.lock);
    }
}

MJIT_FUNC_EXPORTED void
rb_vm_lock_enter_body(unsigned int *lev APPEND_LOCATION_ARGS)
{
    rb_vm_t *vm = GET_VM();
    vm_lock_enter(vm, vm_locked(vm), lev APPEND_LOCATION_PARAMS);
}

MJIT_FUNC_EXPORTED void
rb_vm_lock_leave_body(unsigned int *lev APPEND_LOCATION_ARGS)
{
    vm_lock_leave(GET_VM(), lev APPEND_LOCATION_PARAMS);
}

void
rb_vm_lock_body(LOCATION_ARGS)
{
    rb_vm_t *vm = GET_VM();
    ASSERT_vm_unlocking();
    vm_lock_enter(vm, false, &vm->ractor.sync.lock_rec APPEND_LOCATION_PARAMS);
}

void
rb_vm_unlock_body(LOCATION_ARGS)
{
    rb_vm_t *vm = GET_VM();
    ASSERT_vm_locking();
    VM_ASSERT(vm->ractor.sync.lock_rec == 1);
    vm_lock_leave(vm, &vm->ractor.sync.lock_rec APPEND_LOCATION_PARAMS);
}

static void
vm_cond_wait(rb_vm_t *vm, rb_nativethread_cond_t *cond, unsigned long msec)
{
    ASSERT_vm_locking();
    unsigned int lock_rec = vm->ractor.sync.lock_rec;
    rb_ractor_t *cr = vm->ractor.sync.lock_owner;

    vm->ractor.sync.lock_rec = 0;
    vm->ractor.sync.lock_owner = NULL;
    if (msec > 0) {
        rb_native_cond_timedwait(cond, &vm->ractor.sync.lock, msec);
    }
    else {
        rb_native_cond_wait(cond, &vm->ractor.sync.lock);
    }
    vm->ractor.sync.lock_rec = lock_rec;
    vm->ractor.sync.lock_owner = cr;
}

void
rb_vm_cond_wait(rb_vm_t *vm, rb_nativethread_cond_t *cond)
{
    vm_cond_wait(vm, cond, 0);
}

void
rb_vm_cond_timedwait(rb_vm_t *vm, rb_nativethread_cond_t *cond, unsigned long msec)
{
    vm_cond_wait(vm, cond, msec);
}

static bool
vm_barrier_finish_p(rb_vm_t *vm)
{
    RUBY_DEBUG_LOG("cnt:%u living:%u blocking:%u",
                   vm->ractor.sync.barrier_cnt,
                   vm->ractor.cnt,
                   vm->ractor.blocking_cnt);

    VM_ASSERT(vm->ractor.blocking_cnt <= vm->ractor.cnt);
    return vm->ractor.blocking_cnt == vm->ractor.cnt;
}

void
rb_vm_barrier(void)
{
    if (!rb_multi_ractor_p()) {
        // no other ractors
        return;
    }
    else {
        rb_vm_t *vm = GET_VM();
        VM_ASSERT(vm->ractor.sync.barrier_waiting == false);
        ASSERT_vm_locking();

        rb_ractor_t *cr = vm->ractor.sync.lock_owner;
        VM_ASSERT(cr == GET_RACTOR());
        VM_ASSERT(rb_ractor_status_p(cr, ractor_running));

        vm->ractor.sync.barrier_waiting = true;

        RUBY_DEBUG_LOG("barrier start. cnt:%u living:%u blocking:%u",
                       vm->ractor.sync.barrier_cnt,
                       vm->ractor.cnt,
                       vm->ractor.blocking_cnt);

        rb_vm_ractor_blocking_cnt_inc(vm, cr, __FILE__, __LINE__);

        // send signal
        rb_ractor_t *r = 0;
        list_for_each(&vm->ractor.set, r, vmlr_node) {
            if (r != cr) {
                rb_ractor_vm_barrier_interrupt_running_thread(r);
            }
        }

        // wait
        while (!vm_barrier_finish_p(vm)) {
            rb_vm_cond_wait(vm, &vm->ractor.sync.barrier_cond);
        }

        RUBY_DEBUG_LOG("cnt:%u barrier success", vm->ractor.sync.barrier_cnt);

        rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);

        vm->ractor.sync.barrier_waiting = false;
        vm->ractor.sync.barrier_cnt++;

        list_for_each(&vm->ractor.set, r, vmlr_node) {
            rb_native_cond_signal(&r->barrier_wait_cond);
        }
    }
}

void
rb_ec_vm_lock_rec_release(const rb_execution_context_t *ec,
                          unsigned int recorded_lock_rec,
                          unsigned int current_lock_rec)
{
    VM_ASSERT(recorded_lock_rec != current_lock_rec);

    if (UNLIKELY(recorded_lock_rec > current_lock_rec)) {
        rb_bug("unexpected situation - recordd:%u current:%u",
               recorded_lock_rec, current_lock_rec);
    }
    else {
        while (recorded_lock_rec < current_lock_rec) {
            RB_VM_LOCK_LEAVE_LEV(&current_lock_rec);
        }
    }

    VM_ASSERT(recorded_lock_rec == rb_ec_vm_lock_rec(ec));
}
