// Ractor implementation

#include "ruby/ruby.h"
#include "ruby/thread.h"
#include "ruby/ractor.h"
#include "ruby/thread_native.h"
#include "vm_core.h"
#include "eval_intern.h"
#include "vm_sync.h"
#include "ractor_core.h"
#include "internal/complex.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/ractor.h"
#include "internal/rational.h"
#include "internal/struct.h"
#include "internal/thread.h"
#include "variable.h"
#include "yjit.h"

VALUE rb_cRactor;
static VALUE rb_cRactorSelector;

VALUE rb_eRactorUnsafeError;
VALUE rb_eRactorIsolationError;
static VALUE rb_eRactorError;
static VALUE rb_eRactorRemoteError;
static VALUE rb_eRactorMovedError;
static VALUE rb_eRactorClosedError;
static VALUE rb_cRactorMovedObject;

static void vm_ractor_blocking_cnt_inc(rb_vm_t *vm, rb_ractor_t *r, const char *file, int line);


#if RACTOR_CHECK_MODE > 0
bool rb_ractor_ignore_belonging_flag = false;
#endif

// Ractor locking

static void
ASSERT_ractor_unlocking(rb_ractor_t *r)
{
#if RACTOR_CHECK_MODE > 0
    const rb_execution_context_t *ec = rb_current_ec_noinline();
    if (ec != NULL && r->sync.locked_by == rb_ractor_self(rb_ec_ractor_ptr(ec))) {
        rb_bug("recursive ractor locking");
    }
#endif
}

static void
ASSERT_ractor_locking(rb_ractor_t *r)
{
#if RACTOR_CHECK_MODE > 0
    const rb_execution_context_t *ec = rb_current_ec_noinline();
    if (ec != NULL && r->sync.locked_by != rb_ractor_self(rb_ec_ractor_ptr(ec))) {
        rp(r->sync.locked_by);
        rb_bug("ractor lock is not acquired.");
    }
#endif
}

static void
ractor_lock(rb_ractor_t *r, const char *file, int line)
{
    RUBY_DEBUG_LOG2(file, line, "locking r:%u%s", r->pub.id, rb_current_ractor_raw(false) == r ? " (self)" : "");

    ASSERT_ractor_unlocking(r);
    rb_native_mutex_lock(&r->sync.lock);

#if RACTOR_CHECK_MODE > 0
    if (rb_current_execution_context(false) != NULL) {
        rb_ractor_t *cr = rb_current_ractor_raw(false);
        r->sync.locked_by = cr ? rb_ractor_self(cr) : Qundef;
    }
#endif

    RUBY_DEBUG_LOG2(file, line, "locked  r:%u%s", r->pub.id, rb_current_ractor_raw(false) == r ? " (self)" : "");
}

static void
ractor_lock_self(rb_ractor_t *cr, const char *file, int line)
{
    VM_ASSERT(cr == rb_ec_ractor_ptr(rb_current_ec_noinline()));
#if RACTOR_CHECK_MODE > 0
    VM_ASSERT(cr->sync.locked_by != cr->pub.self);
#endif
    ractor_lock(cr, file, line);
}

static void
ractor_unlock(rb_ractor_t *r, const char *file, int line)
{
    ASSERT_ractor_locking(r);
#if RACTOR_CHECK_MODE > 0
    r->sync.locked_by = Qnil;
#endif
    rb_native_mutex_unlock(&r->sync.lock);

    RUBY_DEBUG_LOG2(file, line, "r:%u%s", r->pub.id, rb_current_ractor_raw(false) == r ? " (self)" : "");
}

static void
ractor_unlock_self(rb_ractor_t *cr, const char *file, int line)
{
    VM_ASSERT(cr == rb_ec_ractor_ptr(rb_current_ec_noinline()));
#if RACTOR_CHECK_MODE > 0
    VM_ASSERT(cr->sync.locked_by == cr->pub.self);
#endif
    ractor_unlock(cr, file, line);
}

#define RACTOR_LOCK(r) ractor_lock(r, __FILE__, __LINE__)
#define RACTOR_UNLOCK(r) ractor_unlock(r, __FILE__, __LINE__)
#define RACTOR_LOCK_SELF(r) ractor_lock_self(r, __FILE__, __LINE__)
#define RACTOR_UNLOCK_SELF(r) ractor_unlock_self(r, __FILE__, __LINE__)

void
rb_ractor_lock_self(rb_ractor_t *r)
{
    RACTOR_LOCK_SELF(r);
}

void
rb_ractor_unlock_self(rb_ractor_t *r)
{
    RACTOR_UNLOCK_SELF(r);
}

// Ractor status

static const char *
ractor_status_str(enum ractor_status status)
{
    switch (status) {
      case ractor_created: return "created";
      case ractor_running: return "running";
      case ractor_blocking: return "blocking";
      case ractor_terminated: return "terminated";
    }
    rb_bug("unreachable");
}

static void
ractor_status_set(rb_ractor_t *r, enum ractor_status status)
{
    RUBY_DEBUG_LOG("r:%u [%s]->[%s]", r->pub.id, ractor_status_str(r->status_), ractor_status_str(status));

    // check 1
    if (r->status_ != ractor_created) {
        VM_ASSERT(r == GET_RACTOR()); // only self-modification is allowed.
        ASSERT_vm_locking();
    }

    // check2: transition check. assume it will be vanished on non-debug build.
    switch (r->status_) {
      case ractor_created:
        VM_ASSERT(status == ractor_blocking);
        break;
      case ractor_running:
        VM_ASSERT(status == ractor_blocking||
                  status == ractor_terminated);
        break;
      case ractor_blocking:
        VM_ASSERT(status == ractor_running);
        break;
      case ractor_terminated:
        rb_bug("unreachable");
        break;
    }

    r->status_ = status;
}

static bool
ractor_status_p(rb_ractor_t *r, enum ractor_status status)
{
    return rb_ractor_status_p(r, status);
}

// Ractor data/mark/free

static void ractor_local_storage_mark(rb_ractor_t *r);
static void ractor_local_storage_free(rb_ractor_t *r);

static void ractor_sync_mark(rb_ractor_t *r);
static void ractor_sync_free(rb_ractor_t *r);
static size_t ractor_sync_memsize(const rb_ractor_t *r);
static void ractor_sync_init(rb_ractor_t *r);

static void
ractor_mark(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;

    // mark received messages
    ractor_sync_mark(r);

    rb_gc_mark(r->loc);
    rb_gc_mark(r->name);
    rb_gc_mark(r->r_stdin);
    rb_gc_mark(r->r_stdout);
    rb_gc_mark(r->r_stderr);
    rb_hook_list_mark(&r->pub.hooks);

    if (r->threads.cnt > 0) {
        rb_thread_t *th = 0;
        ccan_list_for_each(&r->threads.set, th, lt_node) {
            VM_ASSERT(th != NULL);
            rb_gc_mark(th->self);
        }
    }

    ractor_local_storage_mark(r);
}

static void
ractor_free(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;
    RUBY_DEBUG_LOG("free r:%d", rb_ractor_id(r));
    rb_native_mutex_destroy(&r->sync.lock);
#ifdef RUBY_THREAD_WIN32_H
    rb_native_cond_destroy(&r->sync.wakeup_cond);
#endif
    ractor_local_storage_free(r);
    rb_hook_list_free(&r->pub.hooks);

    if (r->newobj_cache) {
        RUBY_ASSERT(r == ruby_single_main_ractor);

        rb_gc_ractor_cache_free(r->newobj_cache);
        r->newobj_cache = NULL;
    }

    ractor_sync_free(r);
    ruby_xfree(r);
}

static size_t
ractor_memsize(const void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;

    // TODO: more correct?
    return sizeof(rb_ractor_t) + ractor_sync_memsize(r);
}

static const rb_data_type_t ractor_data_type = {
    "ractor",
    {
        ractor_mark,
        ractor_free,
        ractor_memsize,
        NULL, // update
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY /* | RUBY_TYPED_WB_PROTECTED */
};

bool
rb_ractor_p(VALUE gv)
{
    if (rb_typeddata_is_kind_of(gv, &ractor_data_type)) {
        return true;
    }
    else {
        return false;
    }
}

static inline rb_ractor_t *
RACTOR_PTR(VALUE self)
{
    VM_ASSERT(rb_ractor_p(self));
    rb_ractor_t *r = DATA_PTR(self);
    return r;
}

static rb_atomic_t ractor_last_id;

#if RACTOR_CHECK_MODE > 0
uint32_t
rb_ractor_current_id(void)
{
    if (GET_THREAD()->ractor == NULL) {
        return 1; // main ractor
    }
    else {
        return rb_ractor_id(GET_RACTOR());
    }
}
#endif

#include "ractor_sync.c"

// creation/termination

static uint32_t
ractor_next_id(void)
{
    uint32_t id;

    id = (uint32_t)(RUBY_ATOMIC_FETCH_ADD(ractor_last_id, 1) + 1);

    return id;
}

static void
vm_insert_ractor0(rb_vm_t *vm, rb_ractor_t *r, bool single_ractor_mode)
{
    RUBY_DEBUG_LOG("r:%u ractor.cnt:%u++", r->pub.id, vm->ractor.cnt);
    VM_ASSERT(single_ractor_mode || RB_VM_LOCKED_P());

    ccan_list_add_tail(&vm->ractor.set, &r->vmlr_node);
    vm->ractor.cnt++;

    if (r->newobj_cache) {
        VM_ASSERT(r == ruby_single_main_ractor);
    }
    else {
        r->newobj_cache = rb_gc_ractor_cache_alloc(r);
    }
}

static void
cancel_single_ractor_mode(void)
{
    // enable multi-ractor mode
    RUBY_DEBUG_LOG("enable multi-ractor mode");

    ruby_single_main_ractor = NULL;
    rb_funcall(rb_cRactor, rb_intern("_activated"), 0);
}

static void
vm_insert_ractor(rb_vm_t *vm, rb_ractor_t *r)
{
    VM_ASSERT(ractor_status_p(r, ractor_created));

    if (rb_multi_ractor_p()) {
        RB_VM_LOCK();
        {
            vm_insert_ractor0(vm, r, false);
            vm_ractor_blocking_cnt_inc(vm, r, __FILE__, __LINE__);
        }
        RB_VM_UNLOCK();
    }
    else {
        if (vm->ractor.cnt == 0) {
            // main ractor
            vm_insert_ractor0(vm, r, true);
            ractor_status_set(r, ractor_blocking);
            ractor_status_set(r, ractor_running);
        }
        else {
            cancel_single_ractor_mode();
            vm_insert_ractor0(vm, r, true);
            vm_ractor_blocking_cnt_inc(vm, r, __FILE__, __LINE__);
        }
    }
}

static void
vm_remove_ractor(rb_vm_t *vm, rb_ractor_t *cr)
{
    VM_ASSERT(ractor_status_p(cr, ractor_running));
    VM_ASSERT(vm->ractor.cnt > 1);
    VM_ASSERT(cr->threads.cnt == 1);

    RB_VM_LOCK();
    {
        RUBY_DEBUG_LOG("ractor.cnt:%u-- terminate_waiting:%d",
                       vm->ractor.cnt,  vm->ractor.sync.terminate_waiting);

        VM_ASSERT(vm->ractor.cnt > 0);
        ccan_list_del(&cr->vmlr_node);

        if (vm->ractor.cnt <= 2 && vm->ractor.sync.terminate_waiting) {
            rb_native_cond_signal(&vm->ractor.sync.terminate_cond);
        }
        vm->ractor.cnt--;

        rb_gc_ractor_cache_free(cr->newobj_cache);
        cr->newobj_cache = NULL;

        ractor_status_set(cr, ractor_terminated);
    }
    RB_VM_UNLOCK();
}

static VALUE
ractor_alloc(VALUE klass)
{
    rb_ractor_t *r;
    VALUE rv = TypedData_Make_Struct(klass, rb_ractor_t, &ractor_data_type, r);
    FL_SET_RAW(rv, RUBY_FL_SHAREABLE);
    r->pub.self = rv;
    VM_ASSERT(ractor_status_p(r, ractor_created));
    return rv;
}

rb_ractor_t *
rb_ractor_main_alloc(void)
{
    rb_ractor_t *r = ruby_mimcalloc(1, sizeof(rb_ractor_t));
    if (r == NULL) {
        fprintf(stderr, "[FATAL] failed to allocate memory for main ractor\n");
        exit(EXIT_FAILURE);
    }
    r->pub.id = ++ractor_last_id;
    r->loc = Qnil;
    r->name = Qnil;
    r->pub.self = Qnil;
    r->newobj_cache = rb_gc_ractor_cache_alloc(r);
    ruby_single_main_ractor = r;

    return r;
}

#if defined(HAVE_WORKING_FORK)
// Set up the main Ractor for the VM after fork.
// Puts us in "single Ractor mode"
void
rb_ractor_atfork(rb_vm_t *vm, rb_thread_t *th)
{
    // initialize as a main ractor
    vm->ractor.cnt = 0;
    vm->ractor.blocking_cnt = 0;
    ruby_single_main_ractor = th->ractor;
    th->ractor->status_ = ractor_created;

    rb_ractor_living_threads_init(th->ractor);
    rb_ractor_living_threads_insert(th->ractor, th);

    VM_ASSERT(vm->ractor.blocking_cnt == 0);
    VM_ASSERT(vm->ractor.cnt == 1);
}

void
rb_ractor_terminate_atfork(rb_vm_t *vm, rb_ractor_t *r)
{
    rb_gc_ractor_cache_free(r->newobj_cache);
    r->newobj_cache = NULL;
    r->status_ = ractor_terminated;
    ractor_sync_terminate_atfork(vm, r);
}
#endif

void rb_thread_sched_init(struct rb_thread_sched *, bool atfork);

void
rb_ractor_living_threads_init(rb_ractor_t *r)
{
    ccan_list_head_init(&r->threads.set);
    r->threads.cnt = 0;
    r->threads.blocking_cnt = 0;
}

static void
ractor_init(rb_ractor_t *r, VALUE name, VALUE loc)
{
    ractor_sync_init(r);

    // thread management
    rb_thread_sched_init(&r->threads.sched, false);
    rb_ractor_living_threads_init(r);

    // naming
    if (!NIL_P(name)) {
        rb_encoding *enc;
        StringValueCStr(name);
        enc = rb_enc_get(name);
        if (!rb_enc_asciicompat(enc)) {
            rb_raise(rb_eArgError, "ASCII incompatible encoding (%s)",
                 rb_enc_name(enc));
        }
        name = rb_str_new_frozen(name);
    }
    r->name = name;
    r->loc = loc;
}

void
rb_ractor_main_setup(rb_vm_t *vm, rb_ractor_t *r, rb_thread_t *th)
{
    VALUE rv = r->pub.self = TypedData_Wrap_Struct(rb_cRactor, &ractor_data_type, r);
    FL_SET_RAW(r->pub.self, RUBY_FL_SHAREABLE);
    ractor_init(r, Qnil, Qnil);
    r->threads.main = th;
    rb_ractor_living_threads_insert(r, th);

    RB_GC_GUARD(rv);
}

static VALUE
ractor_create(rb_execution_context_t *ec, VALUE self, VALUE loc, VALUE name, VALUE args, VALUE block)
{
    VALUE rv = ractor_alloc(self);
    rb_ractor_t *r = RACTOR_PTR(rv);
    ractor_init(r, name, loc);

    // can block here
    r->pub.id = ractor_next_id();
    RUBY_DEBUG_LOG("r:%u", r->pub.id);

    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    r->verbose = cr->verbose;
    r->debug = cr->debug;

    rb_yjit_before_ractor_spawn();
    rb_thread_create_ractor(r, args, block);

    RB_GC_GUARD(rv);
    return rv;
}

#if 0
static VALUE
ractor_create_func(VALUE klass, VALUE loc, VALUE name, VALUE args, rb_block_call_func_t func)
{
    VALUE block = rb_proc_new(func, Qnil);
    return ractor_create(rb_current_ec_noinline(), klass, loc, name, args, block);
}
#endif

static void
ractor_atexit(rb_execution_context_t *ec, rb_ractor_t *cr, VALUE result, bool exc)
{
    ractor_notify_exit(ec, cr, result, exc);
}

void
rb_ractor_atexit(rb_execution_context_t *ec, VALUE result)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    ractor_atexit(ec, cr, result, false);
}

void
rb_ractor_atexit_exception(rb_execution_context_t *ec)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    ractor_atexit(ec, cr, ec->errinfo, true);
}

void
rb_ractor_teardown(rb_execution_context_t *ec)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);

    // sync with rb_ractor_terminate_interrupt_main_thread()
    RB_VM_LOCKING() {
        VM_ASSERT(cr->threads.main != NULL);
        cr->threads.main = NULL;
    }
}

void
rb_ractor_receive_parameters(rb_execution_context_t *ec, rb_ractor_t *r, int len, VALUE *ptr)
{
    for (int i=0; i<len; i++) {
        ptr[i] = ractor_receive(ec, ractor_default_port(r));
    }
}

void
rb_ractor_send_parameters(rb_execution_context_t *ec, rb_ractor_t *r, VALUE args)
{
    int len = RARRAY_LENINT(args);
    for (int i=0; i<len; i++) {
        ractor_send(ec, ractor_default_port(r), RARRAY_AREF(args, i), false);
    }
}

bool
rb_ractor_main_p_(void)
{
    VM_ASSERT(rb_multi_ractor_p());
    rb_execution_context_t *ec = GET_EC();
    return rb_ec_ractor_ptr(ec) == rb_ec_vm_ptr(ec)->ractor.main_ractor;
}

bool
rb_obj_is_main_ractor(VALUE gv)
{
    if (!rb_ractor_p(gv)) return false;
    rb_ractor_t *r = DATA_PTR(gv);
    return r == GET_VM()->ractor.main_ractor;
}

int
rb_ractor_living_thread_num(const rb_ractor_t *r)
{
    return r->threads.cnt;
}

// only for current ractor
VALUE
rb_ractor_thread_list(void)
{
    rb_ractor_t *r = GET_RACTOR();
    rb_thread_t *th = 0;
    VALUE ary = rb_ary_new();

    ccan_list_for_each(&r->threads.set, th, lt_node) {
        switch (th->status) {
          case THREAD_RUNNABLE:
          case THREAD_STOPPED:
          case THREAD_STOPPED_FOREVER:
            rb_ary_push(ary, th->self);
          default:
            break;
        }
    }

    return ary;
}

void
rb_ractor_living_threads_insert(rb_ractor_t *r, rb_thread_t *th)
{
    VM_ASSERT(th != NULL);

    RACTOR_LOCK(r);
    {
        RUBY_DEBUG_LOG("r(%d)->threads.cnt:%d++", r->pub.id, r->threads.cnt);
        ccan_list_add_tail(&r->threads.set, &th->lt_node);
        r->threads.cnt++;
    }
    RACTOR_UNLOCK(r);

    // first thread for a ractor
    if (r->threads.cnt == 1) {
        VM_ASSERT(ractor_status_p(r, ractor_created));
        vm_insert_ractor(th->vm, r);
    }
}

static void
vm_ractor_blocking_cnt_inc(rb_vm_t *vm, rb_ractor_t *r, const char *file, int line)
{
    ractor_status_set(r, ractor_blocking);

    RUBY_DEBUG_LOG2(file, line, "vm->ractor.blocking_cnt:%d++", vm->ractor.blocking_cnt);
    vm->ractor.blocking_cnt++;
    VM_ASSERT(vm->ractor.blocking_cnt <= vm->ractor.cnt);
}

void
rb_vm_ractor_blocking_cnt_inc(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line)
{
    ASSERT_vm_locking();
    VM_ASSERT(GET_RACTOR() == cr);
    vm_ractor_blocking_cnt_inc(vm, cr, file, line);
}

void
rb_vm_ractor_blocking_cnt_dec(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line)
{
    ASSERT_vm_locking();
    VM_ASSERT(GET_RACTOR() == cr);

    RUBY_DEBUG_LOG2(file, line, "vm->ractor.blocking_cnt:%d--", vm->ractor.blocking_cnt);
    VM_ASSERT(vm->ractor.blocking_cnt > 0);
    vm->ractor.blocking_cnt--;

    ractor_status_set(cr, ractor_running);
}

static void
ractor_check_blocking(rb_ractor_t *cr, unsigned int remained_thread_cnt, const char *file, int line)
{
    VM_ASSERT(cr == GET_RACTOR());

    RUBY_DEBUG_LOG2(file, line,
                    "cr->threads.cnt:%u cr->threads.blocking_cnt:%u vm->ractor.cnt:%u vm->ractor.blocking_cnt:%u",
                    cr->threads.cnt, cr->threads.blocking_cnt,
                    GET_VM()->ractor.cnt, GET_VM()->ractor.blocking_cnt);

    VM_ASSERT(cr->threads.cnt >= cr->threads.blocking_cnt + 1);

    if (remained_thread_cnt > 0 &&
        // will be block
        cr->threads.cnt == cr->threads.blocking_cnt + 1) {
        // change ractor status: running -> blocking
        rb_vm_t *vm = GET_VM();

        RB_VM_LOCKING() {
            rb_vm_ractor_blocking_cnt_inc(vm, cr, file, line);
        }
    }
}

void rb_threadptr_remove(rb_thread_t *th);

void
rb_ractor_living_threads_remove(rb_ractor_t *cr, rb_thread_t *th)
{
    VM_ASSERT(cr == GET_RACTOR());
    RUBY_DEBUG_LOG("r->threads.cnt:%d--", cr->threads.cnt);
    ractor_check_blocking(cr, cr->threads.cnt - 1, __FILE__, __LINE__);

    rb_threadptr_remove(th);

    if (cr->threads.cnt == 1) {
        vm_remove_ractor(th->vm, cr);
    }
    else {
        RACTOR_LOCK(cr);
        {
            ccan_list_del(&th->lt_node);
            cr->threads.cnt--;
        }
        RACTOR_UNLOCK(cr);
    }
}

void
rb_ractor_blocking_threads_inc(rb_ractor_t *cr, const char *file, int line)
{
    RUBY_DEBUG_LOG2(file, line, "cr->threads.blocking_cnt:%d++", cr->threads.blocking_cnt);

    VM_ASSERT(cr->threads.cnt > 0);
    VM_ASSERT(cr == GET_RACTOR());

    ractor_check_blocking(cr, cr->threads.cnt, __FILE__, __LINE__);
    cr->threads.blocking_cnt++;
}

void
rb_ractor_blocking_threads_dec(rb_ractor_t *cr, const char *file, int line)
{
    RUBY_DEBUG_LOG2(file, line,
                    "r->threads.blocking_cnt:%d--, r->threads.cnt:%u",
                    cr->threads.blocking_cnt, cr->threads.cnt);

    VM_ASSERT(cr == GET_RACTOR());

    if (cr->threads.cnt == cr->threads.blocking_cnt) {
        rb_vm_t *vm = GET_VM();

        RB_VM_LOCKING() {
            rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);
        }
    }

    cr->threads.blocking_cnt--;
}

void
rb_ractor_vm_barrier_interrupt_running_thread(rb_ractor_t *r)
{
    VM_ASSERT(r != GET_RACTOR());
    ASSERT_ractor_unlocking(r);
    ASSERT_vm_locking();

    RACTOR_LOCK(r);
    {
        if (ractor_status_p(r, ractor_running)) {
            rb_execution_context_t *ec = r->threads.running_ec;
            if (ec) {
                RUBY_VM_SET_VM_BARRIER_INTERRUPT(ec);
            }
        }
    }
    RACTOR_UNLOCK(r);
}

void
rb_ractor_terminate_interrupt_main_thread(rb_ractor_t *r)
{
    VM_ASSERT(r != GET_RACTOR());
    ASSERT_ractor_unlocking(r);
    ASSERT_vm_locking();

    rb_thread_t *main_th = r->threads.main;
    if (main_th) {
        if (main_th->status != THREAD_KILLED) {
            RUBY_VM_SET_TERMINATE_INTERRUPT(main_th->ec);
            rb_threadptr_interrupt(main_th);
        }
        else {
            RUBY_DEBUG_LOG("killed (%p)", (void *)main_th);
        }
    }
}

void rb_thread_terminate_all(rb_thread_t *th); // thread.c

static void
ractor_terminal_interrupt_all(rb_vm_t *vm)
{
    if (vm->ractor.cnt > 1) {
        // send terminate notification to all ractors
        rb_ractor_t *r = 0;
        ccan_list_for_each(&vm->ractor.set, r, vmlr_node) {
            if (r != vm->ractor.main_ractor) {
                RUBY_DEBUG_LOG("r:%d", rb_ractor_id(r));
                rb_ractor_terminate_interrupt_main_thread(r);
            }
        }
    }
}

void rb_add_running_thread(rb_thread_t *th);
void rb_del_running_thread(rb_thread_t *th);

void
rb_ractor_terminate_all(void)
{
    rb_vm_t *vm = GET_VM();
    rb_ractor_t *cr = vm->ractor.main_ractor;

    RUBY_DEBUG_LOG("ractor.cnt:%d", (int)vm->ractor.cnt);

    VM_ASSERT(cr == GET_RACTOR()); // only main-ractor's main-thread should kick it.

    if (vm->ractor.cnt > 1) {
        RB_VM_LOCK();
        {
            ractor_terminal_interrupt_all(vm); // kill all ractors
        }
        RB_VM_UNLOCK();
    }
    rb_thread_terminate_all(GET_THREAD()); // kill other threads in main-ractor and wait

    RB_VM_LOCK();
    {
        while (vm->ractor.cnt > 1) {
            RUBY_DEBUG_LOG("terminate_waiting:%d", vm->ractor.sync.terminate_waiting);
            vm->ractor.sync.terminate_waiting = true;

            // wait for 1sec
            rb_vm_ractor_blocking_cnt_inc(vm, cr, __FILE__, __LINE__);
            rb_del_running_thread(rb_ec_thread_ptr(cr->threads.running_ec));
            rb_vm_cond_timedwait(vm, &vm->ractor.sync.terminate_cond, 1000 /* ms */);
            rb_add_running_thread(rb_ec_thread_ptr(cr->threads.running_ec));
            rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);

            ractor_terminal_interrupt_all(vm);
        }
    }
    RB_VM_UNLOCK();
}

rb_execution_context_t *
rb_vm_main_ractor_ec(rb_vm_t *vm)
{
    /* This code needs to carefully work around two bugs:
     *   - Bug #20016: When M:N threading is enabled, running_ec is NULL if no thread is
     *     actually currently running (as opposed to without M:N threading, when
     *     running_ec will still point to the _last_ thread which ran)
     *   - Bug #20197: If the main thread is sleeping, setting its postponed job
     *     interrupt flag is pointless; it won't look at the flag until it stops sleeping
     *     for some reason. It would be better to set the flag on the running ec, which
     *     will presumably look at it soon.
     *
     *  Solution: use running_ec if it's set, otherwise fall back to the main thread ec.
     *  This is still susceptible to some rare race conditions (what if the last thread
     *  to run just entered a long-running sleep?), but seems like the best balance of
     *  robustness and complexity.
     */
    rb_execution_context_t *running_ec = vm->ractor.main_ractor->threads.running_ec;
    if (running_ec) { return running_ec; }
    return vm->ractor.main_thread->ec;
}

static VALUE
ractor_moved_missing(int argc, VALUE *argv, VALUE self)
{
    rb_raise(rb_eRactorMovedError, "can not send any methods to a moved object");
}

/*
 *  Document-class: Ractor::Error
 *
 *  The parent class of Ractor-related error classes.
 */

/*
 *  Document-class: Ractor::ClosedError
 *
 *  Raised when an attempt is made to send a message to a closed port,
 *  or to retrieve a message from a closed and empty port.
 *  Ports may be closed explicitly with Ractor#close_outgoing/close_incoming
 *  and are closed implicitly when a Ractor terminates.
 *
 *     r = Ractor.new { sleep(500) }
 *     r.close_outgoing
 *     r.take # Ractor::ClosedError
 *
 *  ClosedError is a descendant of StopIteration, so the closing of the ractor will break
 *  the loops without propagating the error:
 *
 *     r = Ractor.new do
 *       loop do
 *         msg = receive # raises ClosedError and loop traps it
 *         puts "Received: #{msg}"
 *       end
 *       puts "loop exited"
 *     end
 *
 *     3.times{|i| r << i}
 *     r.close_incoming
 *     r.take
 *     puts "Continue successfully"
 *
 *  This will print:
 *
 *     Received: 0
 *     Received: 1
 *     Received: 2
 *     loop exited
 *     Continue successfully
 */

/*
 *  Document-class: Ractor::IsolationError
 *
 *  Raised on attempt to make a Ractor-unshareable object
 *  Ractor-shareable.
 */

/*
 *  Document-class: Ractor::RemoteError
 *
 *  Raised on attempt to Ractor#take if there was an uncaught exception in the Ractor.
 *  Its +cause+ will contain the original exception, and +ractor+ is the original ractor
 *  it was raised in.
 *
 *     r = Ractor.new { raise "Something weird happened" }
 *
 *     begin
 *       r.take
 *     rescue => e
 *       p e             # => #<Ractor::RemoteError: thrown by remote Ractor.>
 *       p e.ractor == r # => true
 *       p e.cause       # => #<RuntimeError: Something weird happened>
 *     end
 *
 */

/*
 *  Document-class: Ractor::MovedError
 *
 *  Raised on an attempt to access an object which was moved in Ractor#send or Ractor.yield.
 *
 *     r = Ractor.new { sleep }
 *
 *     ary = [1, 2, 3]
 *     r.send(ary, move: true)
 *     ary.inspect
 *     # Ractor::MovedError (can not send any methods to a moved object)
 *
 */

/*
 *  Document-class: Ractor::MovedObject
 *
 *  A special object which replaces any value that was moved to another ractor in Ractor#send
 *  or Ractor.yield. Any attempt to access the object results in Ractor::MovedError.
 *
 *     r = Ractor.new { receive }
 *
 *     ary = [1, 2, 3]
 *     r.send(ary, move: true)
 *     p Ractor::MovedObject === ary
 *     # => true
 *     ary.inspect
 *     # Ractor::MovedError (can not send any methods to a moved object)
 */

/*
 *  Document-class: Ractor::UnsafeError
 *
 *  Raised when Ractor-unsafe C-methods is invoked by a non-main Ractor.
 */

// Main docs are in ractor.rb, but without this clause there are weird artifacts
// in their rendering.
/*
 *  Document-class: Ractor
 *
 */

void
Init_Ractor(void)
{
    rb_cRactor = rb_define_class("Ractor", rb_cObject);
    rb_undef_alloc_func(rb_cRactor);

    rb_eRactorError          = rb_define_class_under(rb_cRactor, "Error", rb_eRuntimeError);
    rb_eRactorIsolationError = rb_define_class_under(rb_cRactor, "IsolationError", rb_eRactorError);
    rb_eRactorRemoteError    = rb_define_class_under(rb_cRactor, "RemoteError", rb_eRactorError);
    rb_eRactorMovedError     = rb_define_class_under(rb_cRactor, "MovedError",  rb_eRactorError);
    rb_eRactorClosedError    = rb_define_class_under(rb_cRactor, "ClosedError", rb_eStopIteration);
    rb_eRactorUnsafeError    = rb_define_class_under(rb_cRactor, "UnsafeError", rb_eRactorError);

    rb_cRactorMovedObject = rb_define_class_under(rb_cRactor, "MovedObject", rb_cBasicObject);
    rb_undef_alloc_func(rb_cRactorMovedObject);
    rb_define_method(rb_cRactorMovedObject, "method_missing", ractor_moved_missing, -1);

    // override methods defined in BasicObject
    rb_define_method(rb_cRactorMovedObject, "__send__", ractor_moved_missing, -1);
    rb_define_method(rb_cRactorMovedObject, "!", ractor_moved_missing, -1);
    rb_define_method(rb_cRactorMovedObject, "==", ractor_moved_missing, -1);
    rb_define_method(rb_cRactorMovedObject, "!=", ractor_moved_missing, -1);
    rb_define_method(rb_cRactorMovedObject, "__id__", ractor_moved_missing, -1);
    rb_define_method(rb_cRactorMovedObject, "equal?", ractor_moved_missing, -1);
    rb_define_method(rb_cRactorMovedObject, "instance_eval", ractor_moved_missing, -1);
    rb_define_method(rb_cRactorMovedObject, "instance_exec", ractor_moved_missing, -1);

    Init_RactorPort();
}

void
rb_ractor_dump(void)
{
    rb_vm_t *vm = GET_VM();
    rb_ractor_t *r = 0;

    ccan_list_for_each(&vm->ractor.set, r, vmlr_node) {
        if (r != vm->ractor.main_ractor) {
            fprintf(stderr, "r:%u (%s)\n", r->pub.id, ractor_status_str(r->status_));
        }
    }
}

VALUE
rb_ractor_stdin(void)
{
    if (rb_ractor_main_p()) {
        return rb_stdin;
    }
    else {
        rb_ractor_t *cr = GET_RACTOR();
        return cr->r_stdin;
    }
}

VALUE
rb_ractor_stdout(void)
{
    if (rb_ractor_main_p()) {
        return rb_stdout;
    }
    else {
        rb_ractor_t *cr = GET_RACTOR();
        return cr->r_stdout;
    }
}

VALUE
rb_ractor_stderr(void)
{
    if (rb_ractor_main_p()) {
        return rb_stderr;
    }
    else {
        rb_ractor_t *cr = GET_RACTOR();
        return cr->r_stderr;
    }
}

void
rb_ractor_stdin_set(VALUE in)
{
    if (rb_ractor_main_p()) {
        rb_stdin = in;
    }
    else {
        rb_ractor_t *cr = GET_RACTOR();
        RB_OBJ_WRITE(cr->pub.self, &cr->r_stdin, in);
    }
}

void
rb_ractor_stdout_set(VALUE out)
{
    if (rb_ractor_main_p()) {
        rb_stdout = out;
    }
    else {
        rb_ractor_t *cr = GET_RACTOR();
        RB_OBJ_WRITE(cr->pub.self, &cr->r_stdout, out);
    }
}

void
rb_ractor_stderr_set(VALUE err)
{
    if (rb_ractor_main_p()) {
        rb_stderr = err;
    }
    else {
        rb_ractor_t *cr = GET_RACTOR();
        RB_OBJ_WRITE(cr->pub.self, &cr->r_stderr, err);
    }
}

rb_hook_list_t *
rb_ractor_hooks(rb_ractor_t *cr)
{
    return &cr->pub.hooks;
}

/// traverse function

// 2: stop search
// 1: skip child
// 0: continue

enum obj_traverse_iterator_result {
    traverse_cont,
    traverse_skip,
    traverse_stop,
};

typedef enum obj_traverse_iterator_result (*rb_obj_traverse_enter_func)(VALUE obj);
typedef enum obj_traverse_iterator_result (*rb_obj_traverse_leave_func)(VALUE obj);
typedef enum obj_traverse_iterator_result (*rb_obj_traverse_final_func)(VALUE obj);

static enum obj_traverse_iterator_result null_leave(VALUE obj);

struct obj_traverse_data {
    rb_obj_traverse_enter_func enter_func;
    rb_obj_traverse_leave_func leave_func;

    st_table *rec;
    VALUE rec_hash;
};


struct obj_traverse_callback_data {
    bool stop;
    struct obj_traverse_data *data;
};

static int obj_traverse_i(VALUE obj, struct obj_traverse_data *data);

static int
obj_hash_traverse_i(VALUE key, VALUE val, VALUE ptr)
{
    struct obj_traverse_callback_data *d = (struct obj_traverse_callback_data *)ptr;

    if (obj_traverse_i(key, d->data)) {
        d->stop = true;
        return ST_STOP;
    }

    if (obj_traverse_i(val, d->data)) {
        d->stop = true;
        return ST_STOP;
    }

    return ST_CONTINUE;
}

static void
obj_traverse_reachable_i(VALUE obj, void *ptr)
{
    struct obj_traverse_callback_data *d = (struct obj_traverse_callback_data *)ptr;

    if (obj_traverse_i(obj, d->data)) {
        d->stop = true;
    }
}

static struct st_table *
obj_traverse_rec(struct obj_traverse_data *data)
{
    if (UNLIKELY(!data->rec)) {
        data->rec_hash = rb_ident_hash_new();
        data->rec = RHASH_ST_TABLE(data->rec_hash);
    }
    return data->rec;
}

static int
obj_traverse_ivar_foreach_i(ID key, VALUE val, st_data_t ptr)
{
    struct obj_traverse_callback_data *d = (struct obj_traverse_callback_data *)ptr;

    if (obj_traverse_i(val, d->data)) {
        d->stop = true;
        return ST_STOP;
    }

    return ST_CONTINUE;
}

static int
obj_traverse_i(VALUE obj, struct obj_traverse_data *data)
{
    if (RB_SPECIAL_CONST_P(obj)) return 0;

    switch (data->enter_func(obj)) {
      case traverse_cont: break;
      case traverse_skip: return 0; // skip children
      case traverse_stop: return 1; // stop search
    }

    if (UNLIKELY(st_insert(obj_traverse_rec(data), obj, 1))) {
        // already traversed
        return 0;
    }
    RB_OBJ_WRITTEN(data->rec_hash, Qundef, obj);

    struct obj_traverse_callback_data d = {
        .stop = false,
        .data = data,
    };
    rb_ivar_foreach(obj, obj_traverse_ivar_foreach_i, (st_data_t)&d);
    if (d.stop) return 1;

    switch (BUILTIN_TYPE(obj)) {
      // no child node
      case T_STRING:
      case T_FLOAT:
      case T_BIGNUM:
      case T_REGEXP:
      case T_FILE:
      case T_SYMBOL:
      case T_MATCH:
        break;

      case T_OBJECT:
        /* Instance variables already traversed. */
        break;

      case T_ARRAY:
        {
            for (int i = 0; i < RARRAY_LENINT(obj); i++) {
                VALUE e = rb_ary_entry(obj, i);
                if (obj_traverse_i(e, data)) return 1;
            }
        }
        break;

      case T_HASH:
        {
            if (obj_traverse_i(RHASH_IFNONE(obj), data)) return 1;

            struct obj_traverse_callback_data d = {
                .stop = false,
                .data = data,
            };
            rb_hash_foreach(obj, obj_hash_traverse_i, (VALUE)&d);
            if (d.stop) return 1;
        }
        break;

      case T_STRUCT:
        {
            long len = RSTRUCT_LEN(obj);
            const VALUE *ptr = RSTRUCT_CONST_PTR(obj);

            for (long i=0; i<len; i++) {
                if (obj_traverse_i(ptr[i], data)) return 1;
            }
        }
        break;

      case T_RATIONAL:
        if (obj_traverse_i(RRATIONAL(obj)->num, data)) return 1;
        if (obj_traverse_i(RRATIONAL(obj)->den, data)) return 1;
        break;
      case T_COMPLEX:
        if (obj_traverse_i(RCOMPLEX(obj)->real, data)) return 1;
        if (obj_traverse_i(RCOMPLEX(obj)->imag, data)) return 1;
        break;

      case T_DATA:
      case T_IMEMO:
        {
            struct obj_traverse_callback_data d = {
                .stop = false,
                .data = data,
            };
            RB_VM_LOCKING_NO_BARRIER() {
                rb_objspace_reachable_objects_from(obj, obj_traverse_reachable_i, &d);
            }
            if (d.stop) return 1;
        }
        break;

      // unreachable
      case T_CLASS:
      case T_MODULE:
      case T_ICLASS:
      default:
        rp(obj);
        rb_bug("unreachable");
    }

    if (data->leave_func(obj) == traverse_stop) {
        return 1;
    }
    else {
        return 0;
    }
}

struct rb_obj_traverse_final_data {
    rb_obj_traverse_final_func final_func;
    int stopped;
};

static int
obj_traverse_final_i(st_data_t key, st_data_t val, st_data_t arg)
{
    struct rb_obj_traverse_final_data *data = (void *)arg;
    if (data->final_func(key)) {
        data->stopped = 1;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

// 0: traverse all
// 1: stopped
static int
rb_obj_traverse(VALUE obj,
                rb_obj_traverse_enter_func enter_func,
                rb_obj_traverse_leave_func leave_func,
                rb_obj_traverse_final_func final_func)
{
    struct obj_traverse_data data = {
        .enter_func = enter_func,
        .leave_func = leave_func,
        .rec = NULL,
    };

    if (obj_traverse_i(obj, &data)) return 1;
    if (final_func && data.rec) {
        struct rb_obj_traverse_final_data f = {final_func, 0};
        st_foreach(data.rec, obj_traverse_final_i, (st_data_t)&f);
        return f.stopped;
    }
    return 0;
}

static int
allow_frozen_shareable_p(VALUE obj)
{
    if (!RB_TYPE_P(obj, T_DATA)) {
        return true;
    }
    else if (RTYPEDDATA_P(obj)) {
        const rb_data_type_t *type = RTYPEDDATA_TYPE(obj);
        if (type->flags & RUBY_TYPED_FROZEN_SHAREABLE) {
            return true;
        }
    }

    return false;
}

static enum obj_traverse_iterator_result
make_shareable_check_shareable(VALUE obj)
{
    VM_ASSERT(!SPECIAL_CONST_P(obj));

    if (rb_ractor_shareable_p(obj)) {
        return traverse_skip;
    }
    else if (!allow_frozen_shareable_p(obj)) {
        if (rb_obj_is_proc(obj)) {
            rb_proc_ractor_make_shareable(obj);
            return traverse_cont;
        }
        else {
            rb_raise(rb_eRactorError, "can not make shareable object for %+"PRIsVALUE, obj);
        }
    }

    switch (TYPE(obj)) {
      case T_IMEMO:
        return traverse_skip;
      case T_OBJECT:
        {
            // If a T_OBJECT is shared and has no free capacity, we can't safely store the object_id inline,
            // as it would require to move the object content into an external buffer.
            // This is only a problem for T_OBJECT, given other types have external fields and can do RCU.
            // To avoid this issue, we proactively create the object_id.
            shape_id_t shape_id = RBASIC_SHAPE_ID(obj);
            attr_index_t capacity = RSHAPE_CAPACITY(shape_id);
            attr_index_t free_capacity = capacity - RSHAPE_LEN(shape_id);
            if (!rb_shape_has_object_id(shape_id) && capacity && !free_capacity) {
                rb_obj_id(obj);
            }
        }
        break;
      default:
        break;
    }

    if (!RB_OBJ_FROZEN_RAW(obj)) {
        rb_funcall(obj, idFreeze, 0);

        if (UNLIKELY(!RB_OBJ_FROZEN_RAW(obj))) {
            rb_raise(rb_eRactorError, "#freeze does not freeze object correctly");
        }

        if (RB_OBJ_SHAREABLE_P(obj)) {
            return traverse_skip;
        }
    }

    return traverse_cont;
}

static enum obj_traverse_iterator_result
mark_shareable(VALUE obj)
{
    FL_SET_RAW(obj, RUBY_FL_SHAREABLE);
    return traverse_cont;
}

VALUE
rb_ractor_make_shareable(VALUE obj)
{
    rb_obj_traverse(obj,
                    make_shareable_check_shareable,
                    null_leave, mark_shareable);
    return obj;
}

VALUE
rb_ractor_make_shareable_copy(VALUE obj)
{
    VALUE copy = ractor_copy(obj);
    return rb_ractor_make_shareable(copy);
}

VALUE
rb_ractor_ensure_shareable(VALUE obj, VALUE name)
{
    if (!rb_ractor_shareable_p(obj)) {
        VALUE message = rb_sprintf("cannot assign unshareable object to %"PRIsVALUE,
                                   name);
        rb_exc_raise(rb_exc_new_str(rb_eRactorIsolationError, message));
    }
    return obj;
}

void
rb_ractor_ensure_main_ractor(const char *msg)
{
    if (!rb_ractor_main_p()) {
        rb_raise(rb_eRactorIsolationError, "%s", msg);
    }
}

static enum obj_traverse_iterator_result
shareable_p_enter(VALUE obj)
{
    if (RB_OBJ_SHAREABLE_P(obj)) {
        return traverse_skip;
    }
    else if (RB_TYPE_P(obj, T_CLASS)  ||
             RB_TYPE_P(obj, T_MODULE) ||
             RB_TYPE_P(obj, T_ICLASS)) {
        // TODO: remove it
        mark_shareable(obj);
        return traverse_skip;
    }
    else if (RB_OBJ_FROZEN_RAW(obj) &&
             allow_frozen_shareable_p(obj)) {
        return traverse_cont;
    }

    return traverse_stop; // fail
}

bool
rb_ractor_shareable_p_continue(VALUE obj)
{
    if (rb_obj_traverse(obj,
                        shareable_p_enter, null_leave,
                        mark_shareable)) {
        return false;
    }
    else {
        return true;
    }
}

#if RACTOR_CHECK_MODE > 0
void
rb_ractor_setup_belonging(VALUE obj)
{
    rb_ractor_setup_belonging_to(obj, rb_ractor_current_id());
}

static enum obj_traverse_iterator_result
reset_belonging_enter(VALUE obj)
{
    if (rb_ractor_shareable_p(obj)) {
        return traverse_skip;
    }
    else {
        rb_ractor_setup_belonging(obj);
        return traverse_cont;
    }
}
#endif

static enum obj_traverse_iterator_result
null_leave(VALUE obj)
{
    return traverse_cont;
}

static VALUE
ractor_reset_belonging(VALUE obj)
{
#if RACTOR_CHECK_MODE > 0
    rb_obj_traverse(obj, reset_belonging_enter, null_leave, NULL);
#endif
    return obj;
}


/// traverse and replace function

// 2: stop search
// 1: skip child
// 0: continue

struct obj_traverse_replace_data;
static int obj_traverse_replace_i(VALUE obj, struct obj_traverse_replace_data *data);
typedef enum obj_traverse_iterator_result (*rb_obj_traverse_replace_enter_func)(VALUE obj, struct obj_traverse_replace_data *data);
typedef enum obj_traverse_iterator_result (*rb_obj_traverse_replace_leave_func)(VALUE obj, struct obj_traverse_replace_data *data);

struct obj_traverse_replace_data {
    rb_obj_traverse_replace_enter_func enter_func;
    rb_obj_traverse_replace_leave_func leave_func;

    st_table *rec;
    VALUE rec_hash;

    VALUE replacement;
    bool move;
};

struct obj_traverse_replace_callback_data {
    bool stop;
    VALUE src;
    struct obj_traverse_replace_data *data;
};

static int
obj_hash_traverse_replace_foreach_i(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    return ST_REPLACE;
}

static int
obj_hash_traverse_replace_i(st_data_t *key, st_data_t *val, st_data_t ptr, int exists)
{
    struct obj_traverse_replace_callback_data *d = (struct obj_traverse_replace_callback_data *)ptr;
    struct obj_traverse_replace_data *data = d->data;

    if (obj_traverse_replace_i(*key, data)) {
        d->stop = true;
        return ST_STOP;
    }
    else if (*key != data->replacement) {
        VALUE v = *key = data->replacement;
        RB_OBJ_WRITTEN(d->src, Qundef, v);
    }

    if (obj_traverse_replace_i(*val, data)) {
        d->stop = true;
        return ST_STOP;
    }
    else if (*val != data->replacement) {
        VALUE v = *val = data->replacement;
        RB_OBJ_WRITTEN(d->src, Qundef, v);
    }

    return ST_CONTINUE;
}

static int
obj_iv_hash_traverse_replace_foreach_i(st_data_t _key, st_data_t _val, st_data_t _data, int _x)
{
    return ST_REPLACE;
}

static int
obj_iv_hash_traverse_replace_i(st_data_t * _key, st_data_t * val, st_data_t ptr, int exists)
{
    struct obj_traverse_replace_callback_data *d = (struct obj_traverse_replace_callback_data *)ptr;
    struct obj_traverse_replace_data *data = d->data;

    if (obj_traverse_replace_i(*(VALUE *)val, data)) {
        d->stop = true;
        return ST_STOP;
    }
    else if (*(VALUE *)val != data->replacement) {
        VALUE v = *(VALUE *)val = data->replacement;
        RB_OBJ_WRITTEN(d->src, Qundef, v);
    }

    return ST_CONTINUE;
}

static struct st_table *
obj_traverse_replace_rec(struct obj_traverse_replace_data *data)
{
    if (UNLIKELY(!data->rec)) {
        data->rec_hash = rb_ident_hash_new();
        data->rec = RHASH_ST_TABLE(data->rec_hash);
    }
    return data->rec;
}

static void
obj_refer_only_shareables_p_i(VALUE obj, void *ptr)
{
    int *pcnt = (int *)ptr;

    if (!rb_ractor_shareable_p(obj)) {
        ++*pcnt;
    }
}

static int
obj_refer_only_shareables_p(VALUE obj)
{
    int cnt = 0;
    RB_VM_LOCKING_NO_BARRIER() {
        rb_objspace_reachable_objects_from(obj, obj_refer_only_shareables_p_i, &cnt);
    }
    return cnt == 0;
}

static int
obj_traverse_replace_i(VALUE obj, struct obj_traverse_replace_data *data)
{
    st_data_t replacement;

    if (RB_SPECIAL_CONST_P(obj)) {
        data->replacement = obj;
        return 0;
    }

    switch (data->enter_func(obj, data)) {
      case traverse_cont: break;
      case traverse_skip: return 0; // skip children
      case traverse_stop: return 1; // stop search
    }

    replacement = (st_data_t)data->replacement;

    if (UNLIKELY(st_lookup(obj_traverse_replace_rec(data), (st_data_t)obj, &replacement))) {
        data->replacement = (VALUE)replacement;
        return 0;
    }
    else {
        st_insert(obj_traverse_replace_rec(data), (st_data_t)obj, replacement);
        RB_OBJ_WRITTEN(data->rec_hash, Qundef, obj);
        RB_OBJ_WRITTEN(data->rec_hash, Qundef, replacement);
    }

    if (!data->move) {
        obj = replacement;
    }

#define CHECK_AND_REPLACE(parent_obj, v) do { \
    VALUE _val = (v); \
    if (obj_traverse_replace_i(_val, data)) { return 1; } \
    else if (data->replacement != _val)     { RB_OBJ_WRITE(parent_obj, &v, data->replacement); } \
} while (0)

    if (UNLIKELY(rb_obj_exivar_p(obj))) {
        VALUE fields_obj = rb_obj_fields_no_ractor_check(obj);

        if (UNLIKELY(rb_shape_obj_too_complex_p(obj))) {
            struct obj_traverse_replace_callback_data d = {
                .stop = false,
                .data = data,
                .src = fields_obj,
            };
            rb_st_foreach_with_replace(
                rb_imemo_fields_complex_tbl(fields_obj),
                obj_iv_hash_traverse_replace_foreach_i,
                obj_iv_hash_traverse_replace_i,
                (st_data_t)&d
            );
            if (d.stop) return 1;
        }
        else {
            uint32_t fields_count = RSHAPE_LEN(RBASIC_SHAPE_ID(obj));
            VALUE *fields = rb_imemo_fields_ptr(fields_obj);
            for (uint32_t i = 0; i < fields_count; i++) {
                CHECK_AND_REPLACE(fields_obj, fields[i]);
            }
        }
    }

    switch (BUILTIN_TYPE(obj)) {
      // no child node
      case T_FLOAT:
      case T_BIGNUM:
      case T_REGEXP:
      case T_FILE:
      case T_SYMBOL:
      case T_MATCH:
        break;
      case T_STRING:
        rb_str_make_independent(obj);
        break;

      case T_OBJECT:
        {
            if (rb_shape_obj_too_complex_p(obj)) {
                struct obj_traverse_replace_callback_data d = {
                    .stop = false,
                    .data = data,
                    .src = obj,
                };
                rb_st_foreach_with_replace(
                    ROBJECT_FIELDS_HASH(obj),
                    obj_iv_hash_traverse_replace_foreach_i,
                    obj_iv_hash_traverse_replace_i,
                    (st_data_t)&d
                );
                if (d.stop) return 1;
            }
            else {
                uint32_t len = ROBJECT_FIELDS_COUNT(obj);
                VALUE *ptr = ROBJECT_FIELDS(obj);

                for (uint32_t i = 0; i < len; i++) {
                    CHECK_AND_REPLACE(obj, ptr[i]);
                }
            }
        }
        break;

      case T_ARRAY:
        {
            rb_ary_cancel_sharing(obj);

            for (int i = 0; i < RARRAY_LENINT(obj); i++) {
                VALUE e = rb_ary_entry(obj, i);

                if (obj_traverse_replace_i(e, data)) {
                    return 1;
                }
                else if (e != data->replacement) {
                    RARRAY_ASET(obj, i, data->replacement);
                }
            }
            RB_GC_GUARD(obj);
        }
        break;
      case T_HASH:
        {
            struct obj_traverse_replace_callback_data d = {
                .stop = false,
                .data = data,
                .src = obj,
            };
            rb_hash_stlike_foreach_with_replace(obj,
                                                obj_hash_traverse_replace_foreach_i,
                                                obj_hash_traverse_replace_i,
                                                (VALUE)&d);
            if (d.stop) return 1;
            // TODO: rehash here?

            VALUE ifnone = RHASH_IFNONE(obj);
            if (obj_traverse_replace_i(ifnone, data)) {
                return 1;
            }
            else if (ifnone != data->replacement) {
                RHASH_SET_IFNONE(obj, data->replacement);
            }
        }
        break;

      case T_STRUCT:
        {
            long len = RSTRUCT_LEN(obj);
            const VALUE *ptr = RSTRUCT_CONST_PTR(obj);

            for (long i=0; i<len; i++) {
                CHECK_AND_REPLACE(obj, ptr[i]);
            }
        }
        break;

      case T_RATIONAL:
        CHECK_AND_REPLACE(obj, RRATIONAL(obj)->num);
        CHECK_AND_REPLACE(obj, RRATIONAL(obj)->den);
        break;
      case T_COMPLEX:
        CHECK_AND_REPLACE(obj, RCOMPLEX(obj)->real);
        CHECK_AND_REPLACE(obj, RCOMPLEX(obj)->imag);
        break;

      case T_DATA:
        if (!data->move && obj_refer_only_shareables_p(obj)) {
            break;
        }
        else {
            rb_raise(rb_eRactorError, "can not %s %"PRIsVALUE" object.",
                     data->move ? "move" : "copy", rb_class_of(obj));
        }

      case T_IMEMO:
        // not supported yet
        return 1;

      // unreachable
      case T_CLASS:
      case T_MODULE:
      case T_ICLASS:
      default:
        rp(obj);
        rb_bug("unreachable");
    }

    data->replacement = (VALUE)replacement;

    if (data->leave_func(obj, data) == traverse_stop) {
        return 1;
    }
    else {
        return 0;
    }
}

// 0: traverse all
// 1: stopped
static VALUE
rb_obj_traverse_replace(VALUE obj,
                        rb_obj_traverse_replace_enter_func enter_func,
                        rb_obj_traverse_replace_leave_func leave_func,
                        bool move)
{
    struct obj_traverse_replace_data data = {
        .enter_func = enter_func,
        .leave_func = leave_func,
        .rec = NULL,
        .replacement = Qundef,
        .move = move,
    };

    if (obj_traverse_replace_i(obj, &data)) {
        return Qundef;
    }
    else {
        return data.replacement;
    }
}

static const bool wb_protected_types[RUBY_T_MASK] = {
    [T_OBJECT] = RGENGC_WB_PROTECTED_OBJECT,
    [T_HASH] = RGENGC_WB_PROTECTED_HASH,
    [T_ARRAY] = RGENGC_WB_PROTECTED_ARRAY,
    [T_STRING] = RGENGC_WB_PROTECTED_STRING,
    [T_STRUCT] = RGENGC_WB_PROTECTED_STRUCT,
    [T_COMPLEX] = RGENGC_WB_PROTECTED_COMPLEX,
    [T_REGEXP] = RGENGC_WB_PROTECTED_REGEXP,
    [T_MATCH] = RGENGC_WB_PROTECTED_MATCH,
    [T_FLOAT] = RGENGC_WB_PROTECTED_FLOAT,
    [T_RATIONAL] = RGENGC_WB_PROTECTED_RATIONAL,
};

static enum obj_traverse_iterator_result
move_enter(VALUE obj, struct obj_traverse_replace_data *data)
{
    if (rb_ractor_shareable_p(obj)) {
        data->replacement = obj;
        return traverse_skip;
    }
    else {
        VALUE type = RB_BUILTIN_TYPE(obj);
        type |= wb_protected_types[type] ? FL_WB_PROTECTED : 0;
        NEWOBJ_OF(moved, struct RBasic, 0, type, rb_gc_obj_slot_size(obj), 0);
        data->replacement = (VALUE)moved;
        return traverse_cont;
    }
}

static enum obj_traverse_iterator_result
move_leave(VALUE obj, struct obj_traverse_replace_data *data)
{
    // Copy flags
    VALUE ignored_flags = RUBY_FL_PROMOTED;
    RBASIC(data->replacement)->flags = (RBASIC(obj)->flags & ~ignored_flags) | (RBASIC(data->replacement)->flags & ignored_flags);
    // Copy contents without the flags
    memcpy(
        (char *)data->replacement + sizeof(VALUE),
        (char *)obj + sizeof(VALUE),
        rb_gc_obj_slot_size(obj) - sizeof(VALUE)
    );

    // We've copied obj's references to the replacement
    rb_gc_writebarrier_remember(data->replacement);

    void rb_replace_generic_ivar(VALUE clone, VALUE obj); // variable.c

    rb_gc_obj_id_moved(data->replacement);

    if (UNLIKELY(rb_obj_exivar_p(obj))) {
        rb_replace_generic_ivar(data->replacement, obj);
    }

    VALUE flags = T_OBJECT | FL_FREEZE | ROBJECT_EMBED | (RBASIC(obj)->flags & FL_PROMOTED);

    // Avoid mutations using bind_call, etc.
    MEMZERO((char *)obj, char, sizeof(struct RBasic));
    RBASIC(obj)->flags = flags;
    RBASIC_SET_CLASS_RAW(obj, rb_cRactorMovedObject);
    return traverse_cont;
}

static VALUE
ractor_move(VALUE obj)
{
    VALUE val = rb_obj_traverse_replace(obj, move_enter, move_leave, true);
    if (!UNDEF_P(val)) {
        return val;
    }
    else {
        rb_raise(rb_eRactorError, "can not move the object");
    }
}

static enum obj_traverse_iterator_result
copy_enter(VALUE obj, struct obj_traverse_replace_data *data)
{
    if (rb_ractor_shareable_p(obj)) {
        data->replacement = obj;
        return traverse_skip;
    }
    else {
        data->replacement = rb_obj_clone(obj);
        return traverse_cont;
    }
}

static enum obj_traverse_iterator_result
copy_leave(VALUE obj, struct obj_traverse_replace_data *data)
{
    return traverse_cont;
}

static VALUE
ractor_copy(VALUE obj)
{
    VALUE val = rb_obj_traverse_replace(obj, copy_enter, copy_leave, false);
    if (!UNDEF_P(val)) {
        return val;
    }
    else {
        rb_raise(rb_eRactorError, "can not copy the object");
    }
}

// Ractor local storage

struct rb_ractor_local_key_struct {
    const struct rb_ractor_local_storage_type *type;
    void *main_cache;
};

static struct freed_ractor_local_keys_struct {
    int cnt;
    int capa;
    rb_ractor_local_key_t *keys;
} freed_ractor_local_keys;

static int
ractor_local_storage_mark_i(st_data_t key, st_data_t val, st_data_t dmy)
{
    struct rb_ractor_local_key_struct *k = (struct rb_ractor_local_key_struct *)key;
    if (k->type->mark) (*k->type->mark)((void *)val);
    return ST_CONTINUE;
}

static enum rb_id_table_iterator_result
idkey_local_storage_mark_i(VALUE val, void *dmy)
{
    rb_gc_mark(val);
    return ID_TABLE_CONTINUE;
}

static void
ractor_local_storage_mark(rb_ractor_t *r)
{
    if (r->local_storage) {
        st_foreach(r->local_storage, ractor_local_storage_mark_i, 0);

        for (int i=0; i<freed_ractor_local_keys.cnt; i++) {
            rb_ractor_local_key_t key = freed_ractor_local_keys.keys[i];
            st_data_t val, k = (st_data_t)key;
            if (st_delete(r->local_storage, &k, &val) &&
                (key = (rb_ractor_local_key_t)k)->type->free) {
                (*key->type->free)((void *)val);
            }
        }
    }

    if (r->idkey_local_storage) {
        rb_id_table_foreach_values(r->idkey_local_storage, idkey_local_storage_mark_i, NULL);
    }

    rb_gc_mark(r->local_storage_store_lock);
}

static int
ractor_local_storage_free_i(st_data_t key, st_data_t val, st_data_t dmy)
{
    struct rb_ractor_local_key_struct *k = (struct rb_ractor_local_key_struct *)key;
    if (k->type->free) (*k->type->free)((void *)val);
    return ST_CONTINUE;
}

static void
ractor_local_storage_free(rb_ractor_t *r)
{
    if (r->local_storage) {
        st_foreach(r->local_storage, ractor_local_storage_free_i, 0);
        st_free_table(r->local_storage);
    }

    if (r->idkey_local_storage) {
        rb_id_table_free(r->idkey_local_storage);
    }
}

static void
rb_ractor_local_storage_value_mark(void *ptr)
{
    rb_gc_mark((VALUE)ptr);
}

static const struct rb_ractor_local_storage_type ractor_local_storage_type_null = {
    NULL,
    NULL,
};

const struct rb_ractor_local_storage_type rb_ractor_local_storage_type_free = {
    NULL,
    ruby_xfree,
};

static const struct rb_ractor_local_storage_type ractor_local_storage_type_value = {
    rb_ractor_local_storage_value_mark,
    NULL,
};

rb_ractor_local_key_t
rb_ractor_local_storage_ptr_newkey(const struct rb_ractor_local_storage_type *type)
{
    rb_ractor_local_key_t key = ALLOC(struct rb_ractor_local_key_struct);
    key->type = type ? type : &ractor_local_storage_type_null;
    key->main_cache = (void *)Qundef;
    return key;
}

rb_ractor_local_key_t
rb_ractor_local_storage_value_newkey(void)
{
    return rb_ractor_local_storage_ptr_newkey(&ractor_local_storage_type_value);
}

void
rb_ractor_local_storage_delkey(rb_ractor_local_key_t key)
{
    RB_VM_LOCKING() {
        if (freed_ractor_local_keys.cnt == freed_ractor_local_keys.capa) {
            freed_ractor_local_keys.capa = freed_ractor_local_keys.capa ? freed_ractor_local_keys.capa * 2 : 4;
            REALLOC_N(freed_ractor_local_keys.keys, rb_ractor_local_key_t, freed_ractor_local_keys.capa);
        }
        freed_ractor_local_keys.keys[freed_ractor_local_keys.cnt++] = key;
    }
}

static bool
ractor_local_ref(rb_ractor_local_key_t key, void **pret)
{
    if (rb_ractor_main_p()) {
        if (!UNDEF_P((VALUE)key->main_cache)) {
            *pret = key->main_cache;
            return true;
        }
        else {
            return false;
        }
    }
    else {
        rb_ractor_t *cr = GET_RACTOR();

        if (cr->local_storage && st_lookup(cr->local_storage, (st_data_t)key, (st_data_t *)pret)) {
            return true;
        }
        else {
            return false;
        }
    }
}

static void
ractor_local_set(rb_ractor_local_key_t key, void *ptr)
{
    rb_ractor_t *cr = GET_RACTOR();

    if (cr->local_storage == NULL) {
        cr->local_storage = st_init_numtable();
    }

    st_insert(cr->local_storage, (st_data_t)key, (st_data_t)ptr);

    if (rb_ractor_main_p()) {
        key->main_cache = ptr;
    }
}

VALUE
rb_ractor_local_storage_value(rb_ractor_local_key_t key)
{
    void *val;
    if (ractor_local_ref(key, &val)) {
        return (VALUE)val;
    }
    else {
        return Qnil;
    }
}

bool
rb_ractor_local_storage_value_lookup(rb_ractor_local_key_t key, VALUE *val)
{
    if (ractor_local_ref(key, (void **)val)) {
        return true;
    }
    else {
        return false;
    }
}

void
rb_ractor_local_storage_value_set(rb_ractor_local_key_t key, VALUE val)
{
    ractor_local_set(key, (void *)val);
}

void *
rb_ractor_local_storage_ptr(rb_ractor_local_key_t key)
{
    void *ret;
    if (ractor_local_ref(key, &ret)) {
        return ret;
    }
    else {
        return NULL;
    }
}

void
rb_ractor_local_storage_ptr_set(rb_ractor_local_key_t key, void *ptr)
{
    ractor_local_set(key, ptr);
}

#define DEFAULT_KEYS_CAPA 0x10

void
rb_ractor_finish_marking(void)
{
    for (int i=0; i<freed_ractor_local_keys.cnt; i++) {
        ruby_xfree(freed_ractor_local_keys.keys[i]);
    }
    freed_ractor_local_keys.cnt = 0;
    if (freed_ractor_local_keys.capa > DEFAULT_KEYS_CAPA) {
        freed_ractor_local_keys.capa = DEFAULT_KEYS_CAPA;
        REALLOC_N(freed_ractor_local_keys.keys, rb_ractor_local_key_t, DEFAULT_KEYS_CAPA);
    }
}

static VALUE
ractor_local_value(rb_execution_context_t *ec, VALUE self, VALUE sym)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    ID id = rb_check_id(&sym);
    struct rb_id_table *tbl = cr->idkey_local_storage;
    VALUE val;

    if (id && tbl && rb_id_table_lookup(tbl, id, &val)) {
        return val;
    }
    else {
        return Qnil;
    }
}

static VALUE
ractor_local_value_set(rb_execution_context_t *ec, VALUE self, VALUE sym, VALUE val)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    ID id = SYM2ID(rb_to_symbol(sym));
    struct rb_id_table *tbl = cr->idkey_local_storage;

    if (tbl == NULL) {
        tbl = cr->idkey_local_storage = rb_id_table_create(2);
    }
    rb_id_table_insert(tbl, id, val);
    return val;
}

struct ractor_local_storage_store_data {
    rb_execution_context_t *ec;
    struct rb_id_table *tbl;
    ID id;
    VALUE sym;
};

static VALUE
ractor_local_value_store_i(VALUE ptr)
{
    VALUE val;
    struct ractor_local_storage_store_data *data = (struct ractor_local_storage_store_data *)ptr;

    if (rb_id_table_lookup(data->tbl, data->id, &val)) {
        // after synchronization, we found already registered entry
    }
    else {
        val = rb_yield(Qnil);
        ractor_local_value_set(data->ec, Qnil, data->sym, val);
    }
    return val;
}

static VALUE
ractor_local_value_store_if_absent(rb_execution_context_t *ec, VALUE self, VALUE sym)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    struct ractor_local_storage_store_data data = {
        .ec = ec,
        .sym = sym,
        .id = SYM2ID(rb_to_symbol(sym)),
        .tbl = cr->idkey_local_storage,
    };
    VALUE val;

    if (data.tbl == NULL) {
        data.tbl = cr->idkey_local_storage = rb_id_table_create(2);
    }
    else if (rb_id_table_lookup(data.tbl, data.id, &val)) {
        // already set
        return val;
    }

    if (!cr->local_storage_store_lock) {
        cr->local_storage_store_lock = rb_mutex_new();
    }

    return rb_mutex_synchronize(cr->local_storage_store_lock, ractor_local_value_store_i, (VALUE)&data);
}

// Ractor#require

struct cross_ractor_require {
    VALUE port;
    VALUE result;
    VALUE exception;

    // require
    VALUE feature;

    // autoload
    VALUE module;
    ID name;

    bool silent;
};

RUBY_REFERENCES(cross_ractor_require_refs) = {
    RUBY_REF_EDGE(struct cross_ractor_require, port),
    RUBY_REF_EDGE(struct cross_ractor_require, result),
    RUBY_REF_EDGE(struct cross_ractor_require, exception),
    RUBY_REF_EDGE(struct cross_ractor_require, feature),
    RUBY_REF_EDGE(struct cross_ractor_require, module),
    RUBY_REF_END
};

static const rb_data_type_t cross_ractor_require_data_type = {
    "ractor/cross_ractor_require",
    {
        RUBY_REFS_LIST_PTR(cross_ractor_require_refs),
        RUBY_DEFAULT_FREE,
        NULL, // memsize
        NULL, // compact
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_DECL_MARKING
};

static VALUE
require_body(VALUE crr_obj)
{
    struct cross_ractor_require *crr;
    TypedData_Get_Struct(crr_obj, struct cross_ractor_require, &cross_ractor_require_data_type, crr);

    ID require;
    CONST_ID(require, "require");

    if (crr->silent) {
        int rb_require_internal_silent(VALUE fname);

        RB_OBJ_WRITE(crr_obj, &crr->result, INT2NUM(rb_require_internal_silent(crr->feature)));
    }
    else {
        RB_OBJ_WRITE(crr_obj, &crr->result, rb_funcallv(Qnil, require, 1, &crr->feature));
    }

    return Qnil;
}

static VALUE
require_rescue(VALUE crr_obj, VALUE errinfo)
{
    struct cross_ractor_require *crr;
    TypedData_Get_Struct(crr_obj, struct cross_ractor_require, &cross_ractor_require_data_type, crr);

    RB_OBJ_WRITE(crr_obj, &crr->exception, errinfo);

    return Qundef;
}

static VALUE
require_result_copy_body(VALUE crr_obj)
{
    struct cross_ractor_require *crr;
    TypedData_Get_Struct(crr_obj, struct cross_ractor_require, &cross_ractor_require_data_type, crr);

    if (crr->exception != Qundef) {
        VM_ASSERT(crr->result == Qundef);
        RB_OBJ_WRITE(crr_obj, &crr->exception, ractor_copy(crr->exception));
    }
    else{
        VM_ASSERT(crr->result != Qundef);
        RB_OBJ_WRITE(crr_obj, &crr->result, ractor_copy(crr->result));
    }

    return Qnil;
}

static VALUE
require_result_copy_resuce(VALUE crr_obj, VALUE errinfo)
{
    struct cross_ractor_require *crr;
    TypedData_Get_Struct(crr_obj, struct cross_ractor_require, &cross_ractor_require_data_type, crr);

    RB_OBJ_WRITE(crr_obj, &crr->exception, errinfo);

    return Qnil;
}

static VALUE
ractor_require_protect(VALUE crr_obj, VALUE (*func)(VALUE))
{
    struct cross_ractor_require *crr;
    TypedData_Get_Struct(crr_obj, struct cross_ractor_require, &cross_ractor_require_data_type, crr);

    const bool silent = crr->silent;
    VALUE debug, errinfo;
    if (silent) {
        debug = ruby_debug;
        errinfo = rb_errinfo();
    }

    // catch any error
    rb_rescue2(func, crr_obj,
               require_rescue, crr_obj, rb_eException, 0);

    if (silent) {
        ruby_debug = debug;
        rb_set_errinfo(errinfo);
    }

    rb_rescue2(require_result_copy_body, crr_obj,
               require_result_copy_resuce, crr_obj, rb_eException, 0);

    ractor_port_send(GET_EC(), crr->port, Qtrue, Qfalse);
    RB_GC_GUARD(crr_obj);
    return Qnil;
}

static VALUE
ractor_require_func(void *crr_obj)
{
    return ractor_require_protect((VALUE)crr_obj, require_body);
}

VALUE
rb_ractor_require(VALUE feature, bool silent)
{
    // We're about to block on the main ractor, so if we're holding the global lock we'll deadlock.
    ASSERT_vm_unlocking();

    struct cross_ractor_require *crr;
    VALUE crr_obj = TypedData_Make_Struct(0, struct cross_ractor_require, &cross_ractor_require_data_type, crr);
    FL_SET_RAW(crr_obj, RUBY_FL_SHAREABLE);

    // Convert feature to proper file path and make it shareable as fstring
    RB_OBJ_WRITE(crr_obj, &crr->feature, rb_fstring(FilePathValue(feature)));
    RB_OBJ_WRITE(crr_obj, &crr->port, ractor_port_new(GET_RACTOR()));
    crr->result = Qundef;
    crr->exception = Qundef;
    crr->silent = silent;

    rb_execution_context_t *ec = GET_EC();
    rb_ractor_t *main_r = GET_VM()->ractor.main_ractor;
    rb_ractor_interrupt_exec(main_r, ractor_require_func, (void *)crr_obj, rb_interrupt_exec_flag_value_data);

    // wait for require done
    ractor_port_receive(ec, crr->port);
    ractor_port_close(ec, crr->port);

    VALUE exc = crr->exception;
    VALUE result = crr->result;
    RB_GC_GUARD(crr_obj);

    if (exc != Qundef) {
        ractor_reset_belonging(exc);
        rb_exc_raise(exc);
    }
    else {
        RUBY_ASSERT(result != Qundef);
        ractor_reset_belonging(result);
        return result;
    }
}

static VALUE
ractor_require(rb_execution_context_t *ec, VALUE self, VALUE feature)
{
    return rb_ractor_require(feature, false);
}

static VALUE
autoload_load_body(VALUE crr_obj)
{
    struct cross_ractor_require *crr;
    TypedData_Get_Struct(crr_obj, struct cross_ractor_require, &cross_ractor_require_data_type, crr);

    RB_OBJ_WRITE(crr_obj, &crr->result, rb_autoload_load(crr->module, crr->name));

    return Qnil;
}

static VALUE
ractor_autoload_load_func(void *crr_obj)
{
    return ractor_require_protect((VALUE)crr_obj, autoload_load_body);
}

VALUE
rb_ractor_autoload_load(VALUE module, ID name)
{
    struct cross_ractor_require *crr;
    VALUE crr_obj = TypedData_Make_Struct(0, struct cross_ractor_require, &cross_ractor_require_data_type, crr);
    FL_SET_RAW(crr_obj, RUBY_FL_SHAREABLE);
    RB_OBJ_WRITE(crr_obj, &crr->module, module);
    RB_OBJ_WRITE(crr_obj, &crr->name, name);
    RB_OBJ_WRITE(crr_obj, &crr->port, ractor_port_new(GET_RACTOR()));
    crr->result = Qundef;
    crr->exception = Qundef;

    rb_execution_context_t *ec = GET_EC();
    rb_ractor_t *main_r = GET_VM()->ractor.main_ractor;
    rb_ractor_interrupt_exec(main_r, ractor_autoload_load_func, (void *)crr_obj, rb_interrupt_exec_flag_value_data);

    // wait for require done
    ractor_port_receive(ec, crr->port);
    ractor_port_close(ec, crr->port);

    VALUE exc = crr->exception;
    VALUE result = crr->result;
    RB_GC_GUARD(crr_obj);

    if (exc != Qundef) {
        rb_exc_raise(exc);
    }
    else {
        return result;
    }
}

#include "ractor.rbinc"
