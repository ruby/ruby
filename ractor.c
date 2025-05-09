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
#include "internal/variable.h"
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

static struct rb_ractor_basket *ractor_queue_at(rb_ractor_t *r, struct rb_ractor_queue *rq, int i);
static void ractor_local_storage_mark(rb_ractor_t *r);
static void ractor_local_storage_free(rb_ractor_t *r);

static void
ractor_queue_mark(struct rb_ractor_queue *rq)
{
    for (int i=0; i<rq->cnt; i++) {
        struct rb_ractor_basket *b = ractor_queue_at(NULL, rq, i);
        rb_gc_mark(b->sender);

        switch (b->type.e) {
          case basket_type_yielding:
          case basket_type_take_basket:
          case basket_type_deleted:
          case basket_type_reserved:
            // ignore
            break;
          default:
            rb_gc_mark(b->p.send.v);
        }
    }
}

static void
ractor_mark(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;

    ractor_queue_mark(&r->sync.recv_queue);
    ractor_queue_mark(&r->sync.takers_queue);

    rb_gc_mark(r->receiving_mutex);

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
ractor_queue_free(struct rb_ractor_queue *rq)
{
    free(rq->baskets);
}

static void
ractor_free(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;
    RUBY_DEBUG_LOG("free r:%d", rb_ractor_id(r));
    rb_native_mutex_destroy(&r->sync.lock);
#ifdef RUBY_THREAD_WIN32_H
    rb_native_cond_destroy(&r->sync.cond);
#endif
    ractor_queue_free(&r->sync.recv_queue);
    ractor_queue_free(&r->sync.takers_queue);
    ractor_local_storage_free(r);
    rb_hook_list_free(&r->pub.hooks);

    if (r->newobj_cache) {
        RUBY_ASSERT(r == ruby_single_main_ractor);

        rb_gc_ractor_cache_free(r->newobj_cache);
        r->newobj_cache = NULL;
    }

    ruby_xfree(r);
}

static size_t
ractor_queue_memsize(const struct rb_ractor_queue *rq)
{
    return sizeof(struct rb_ractor_basket) * rq->size;
}

static size_t
ractor_memsize(const void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;

    // TODO: more correct?
    return sizeof(rb_ractor_t) +
           ractor_queue_memsize(&r->sync.recv_queue) +
           ractor_queue_memsize(&r->sync.takers_queue);
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

// Ractor queue

static void
ractor_queue_setup(struct rb_ractor_queue *rq)
{
    rq->size = 2;
    rq->cnt = 0;
    rq->start = 0;
    rq->baskets = malloc(sizeof(struct rb_ractor_basket) * rq->size);
}

static struct rb_ractor_basket *
ractor_queue_head(rb_ractor_t *r, struct rb_ractor_queue *rq)
{
    if (r != NULL) ASSERT_ractor_locking(r);
    return &rq->baskets[rq->start];
}

static struct rb_ractor_basket *
ractor_queue_at(rb_ractor_t *r, struct rb_ractor_queue *rq, int i)
{
    if (r != NULL) ASSERT_ractor_locking(r);
    return &rq->baskets[(rq->start + i) % rq->size];
}

static void
ractor_queue_advance(rb_ractor_t *r, struct rb_ractor_queue *rq)
{
    ASSERT_ractor_locking(r);

    if (rq->reserved_cnt == 0) {
        rq->cnt--;
        rq->start = (rq->start + 1) % rq->size;
        rq->serial++;
    }
    else {
        ractor_queue_at(r, rq, 0)->type.e = basket_type_deleted;
    }
}

static bool
ractor_queue_skip_p(rb_ractor_t *r, struct rb_ractor_queue *rq, int i)
{
    struct rb_ractor_basket *b = ractor_queue_at(r, rq, i);
    return basket_type_p(b, basket_type_deleted) ||
           basket_type_p(b, basket_type_reserved);
}

static void
ractor_queue_compact(rb_ractor_t *r, struct rb_ractor_queue *rq)
{
    ASSERT_ractor_locking(r);

    while (rq->cnt > 0 && basket_type_p(ractor_queue_at(r, rq, 0), basket_type_deleted)) {
        ractor_queue_advance(r, rq);
    }
}

static bool
ractor_queue_empty_p(rb_ractor_t *r, struct rb_ractor_queue *rq)
{
    ASSERT_ractor_locking(r);

    if (rq->cnt == 0) {
        return true;
    }

    ractor_queue_compact(r, rq);

    for (int i=0; i<rq->cnt; i++) {
        if (!ractor_queue_skip_p(r, rq, i)) {
            return false;
        }
    }

    return true;
}

static bool
ractor_queue_deq(rb_ractor_t *r, struct rb_ractor_queue *rq, struct rb_ractor_basket *basket)
{
    ASSERT_ractor_locking(r);

    for (int i=0; i<rq->cnt; i++) {
        if (!ractor_queue_skip_p(r, rq, i)) {
            struct rb_ractor_basket *b = ractor_queue_at(r, rq, i);
            *basket = *b;

            // remove from queue
            b->type.e = basket_type_deleted;
            ractor_queue_compact(r, rq);
            return true;
        }
    }

    return false;
}

static void
ractor_queue_enq(rb_ractor_t *r, struct rb_ractor_queue *rq, struct rb_ractor_basket *basket)
{
    ASSERT_ractor_locking(r);

    if (rq->size <= rq->cnt) {
        rq->baskets = realloc(rq->baskets, sizeof(struct rb_ractor_basket) * rq->size * 2);
        for (int i=rq->size - rq->start; i<rq->cnt; i++) {
            rq->baskets[i + rq->start] = rq->baskets[i + rq->start - rq->size];
        }
        rq->size *= 2;
    }
    rq->baskets[(rq->start + rq->cnt++) % rq->size] = *basket;
    // fprintf(stderr, "%s %p->cnt:%d\n", RUBY_FUNCTION_NAME_STRING, (void *)rq, rq->cnt);
}

static void
ractor_queue_delete(rb_ractor_t *r, struct rb_ractor_queue *rq, struct rb_ractor_basket *basket)
{
    basket->type.e = basket_type_deleted;
}

// Ractor basket

static VALUE ractor_reset_belonging(VALUE obj); // in this file

static VALUE
ractor_basket_value(struct rb_ractor_basket *b)
{
    switch (b->type.e) {
      case basket_type_ref:
        break;
      case basket_type_copy:
      case basket_type_move:
      case basket_type_will:
        b->type.e = basket_type_ref;
        b->p.send.v = ractor_reset_belonging(b->p.send.v);
        break;
      default:
        rb_bug("unreachable");
    }

    return b->p.send.v;
}

static VALUE
ractor_basket_accept(struct rb_ractor_basket *b)
{
    VALUE v = ractor_basket_value(b);

    if (b->p.send.exception) {
        VALUE cause = v;
        VALUE err = rb_exc_new_cstr(rb_eRactorRemoteError, "thrown by remote Ractor.");
        rb_ivar_set(err, rb_intern("@ractor"), b->sender);
        rb_ec_setup_exception(NULL, err, cause);
        rb_exc_raise(err);
    }

    return v;
}

// Ractor synchronizations

#if USE_RUBY_DEBUG_LOG
static const char *
wait_status_str(enum rb_ractor_wait_status wait_status)
{
    switch ((int)wait_status) {
      case wait_none: return "none";
      case wait_receiving: return "receiving";
      case wait_taking: return "taking";
      case wait_yielding: return "yielding";
      case wait_receiving|wait_taking: return "receiving|taking";
      case wait_receiving|wait_yielding: return "receiving|yielding";
      case wait_taking|wait_yielding: return "taking|yielding";
      case wait_receiving|wait_taking|wait_yielding: return "receiving|taking|yielding";
    }
    rb_bug("unreachable");
}

static const char *
wakeup_status_str(enum rb_ractor_wakeup_status wakeup_status)
{
    switch (wakeup_status) {
      case wakeup_none: return "none";
      case wakeup_by_send: return "by_send";
      case wakeup_by_yield: return "by_yield";
      case wakeup_by_take: return "by_take";
      case wakeup_by_close: return "by_close";
      case wakeup_by_interrupt: return "by_interrupt";
      case wakeup_by_retry: return "by_retry";
    }
    rb_bug("unreachable");
}

static const char *
basket_type_name(enum rb_ractor_basket_type type)
{
    switch (type) {
      case basket_type_none: return  "none";
      case basket_type_ref: return "ref";
      case basket_type_copy: return "copy";
      case basket_type_move: return "move";
      case basket_type_will: return "will";
      case basket_type_deleted: return "deleted";
      case basket_type_reserved: return "reserved";
      case basket_type_take_basket: return "take_basket";
      case basket_type_yielding: return "yielding";
    }
    VM_ASSERT(0);
    return NULL;
}
#endif // USE_RUBY_DEBUG_LOG

static bool
ractor_sleeping_by(const rb_ractor_t *r, enum rb_ractor_wait_status wait_status)
{
    return (r->sync.wait.status & wait_status) && r->sync.wait.wakeup_status == wakeup_none;
}

#ifdef RUBY_THREAD_PTHREAD_H
// thread_*.c
void rb_ractor_sched_wakeup(rb_ractor_t *r);
#else

static void
rb_ractor_sched_wakeup(rb_ractor_t *r)
{
    rb_native_cond_broadcast(&r->sync.cond);
}
#endif


static bool
ractor_wakeup(rb_ractor_t *r, enum rb_ractor_wait_status wait_status, enum rb_ractor_wakeup_status wakeup_status)
{
    ASSERT_ractor_locking(r);

    RUBY_DEBUG_LOG("r:%u wait_by:%s -> wait:%s wakeup:%s",
                   rb_ractor_id(r),
                   wait_status_str(r->sync.wait.status),
                   wait_status_str(wait_status),
                   wakeup_status_str(wakeup_status));

    if (ractor_sleeping_by(r, wait_status)) {
        r->sync.wait.wakeup_status = wakeup_status;
        rb_ractor_sched_wakeup(r);
        return true;
    }
    else {
        return false;
    }
}

static void
ractor_sleep_interrupt(void *ptr)
{
    rb_ractor_t *r = ptr;

    RACTOR_LOCK(r);
    {
        ractor_wakeup(r, wait_receiving | wait_taking | wait_yielding, wakeup_by_interrupt);
    }
    RACTOR_UNLOCK(r);
}

typedef void (*ractor_sleep_cleanup_function)(rb_ractor_t *cr, void *p);

static void
ractor_check_ints(rb_execution_context_t *ec, rb_ractor_t *cr, ractor_sleep_cleanup_function cf_func, void *cf_data)
{
    if (cr->sync.wait.status != wait_none) {
        enum rb_ractor_wait_status prev_wait_status = cr->sync.wait.status;
        cr->sync.wait.status = wait_none;
        cr->sync.wait.wakeup_status = wakeup_by_interrupt;

        RACTOR_UNLOCK(cr);
        {
            if (cf_func) {
                enum ruby_tag_type state;
                EC_PUSH_TAG(ec);
                if ((state = EC_EXEC_TAG()) == TAG_NONE) {
                    rb_ec_check_ints(ec);
                }
                EC_POP_TAG();

                if (state) {
                    (*cf_func)(cr, cf_data);
                    EC_JUMP_TAG(ec, state);
                }
            }
            else {
                rb_ec_check_ints(ec);
            }
        }

        // reachable?
        RACTOR_LOCK(cr);
        cr->sync.wait.status = prev_wait_status;
    }
}

#ifdef RUBY_THREAD_PTHREAD_H
void rb_ractor_sched_sleep(rb_execution_context_t *ec, rb_ractor_t *cr, rb_unblock_function_t *ubf);
#else

// win32
static void
ractor_cond_wait(rb_ractor_t *r)
{
#if RACTOR_CHECK_MODE > 0
    VALUE locked_by = r->sync.locked_by;
    r->sync.locked_by = Qnil;
#endif
    rb_native_cond_wait(&r->sync.cond, &r->sync.lock);

#if RACTOR_CHECK_MODE > 0
    r->sync.locked_by = locked_by;
#endif
}

static void *
ractor_sleep_wo_gvl(void *ptr)
{
    rb_ractor_t *cr = ptr;
    RACTOR_LOCK_SELF(cr);
    {
        VM_ASSERT(cr->sync.wait.status != wait_none);
        if (cr->sync.wait.wakeup_status == wakeup_none) {
            ractor_cond_wait(cr);
        }
        cr->sync.wait.status = wait_none;
    }
    RACTOR_UNLOCK_SELF(cr);
    return NULL;
}

static void
rb_ractor_sched_sleep(rb_execution_context_t *ec, rb_ractor_t *cr, rb_unblock_function_t *ubf)
{
    RACTOR_UNLOCK(cr);
    {
        rb_nogvl(ractor_sleep_wo_gvl, cr,
                 ubf, cr,
                 RB_NOGVL_UBF_ASYNC_SAFE | RB_NOGVL_INTR_FAIL);
    }
    RACTOR_LOCK(cr);
}
#endif

static enum rb_ractor_wakeup_status
ractor_sleep_with_cleanup(rb_execution_context_t *ec, rb_ractor_t *cr, enum rb_ractor_wait_status wait_status,
                          ractor_sleep_cleanup_function cf_func, void *cf_data)
{
    enum rb_ractor_wakeup_status wakeup_status;
    VM_ASSERT(GET_RACTOR() == cr);

    // TODO: multi-threads
    VM_ASSERT(cr->sync.wait.status == wait_none);
    VM_ASSERT(wait_status != wait_none);
    cr->sync.wait.status = wait_status;
    cr->sync.wait.wakeup_status = wakeup_none;

    // fprintf(stderr, "%s  r:%p status:%s, wakeup_status:%s\n", RUBY_FUNCTION_NAME_STRING, (void *)cr,
    //                 wait_status_str(cr->sync.wait.status), wakeup_status_str(cr->sync.wait.wakeup_status));

    RUBY_DEBUG_LOG("sleep by %s", wait_status_str(wait_status));

    while (cr->sync.wait.wakeup_status == wakeup_none) {
        rb_ractor_sched_sleep(ec, cr, ractor_sleep_interrupt);
        ractor_check_ints(ec, cr, cf_func, cf_data);
    }

    cr->sync.wait.status = wait_none;

    // TODO: multi-thread
    wakeup_status = cr->sync.wait.wakeup_status;
    cr->sync.wait.wakeup_status = wakeup_none;

    RUBY_DEBUG_LOG("wakeup %s", wakeup_status_str(wakeup_status));

    return wakeup_status;
}

static enum rb_ractor_wakeup_status
ractor_sleep(rb_execution_context_t *ec, rb_ractor_t *cr, enum rb_ractor_wait_status wait_status)
{
    return ractor_sleep_with_cleanup(ec, cr, wait_status, 0, NULL);
}

// Ractor.receive

static void
ractor_recursive_receive_if(rb_ractor_t *r)
{
    if (r->receiving_mutex && rb_mutex_owned_p(r->receiving_mutex)) {
        rb_raise(rb_eRactorError, "can not call receive/receive_if recursively");
    }
}

static VALUE
ractor_try_receive(rb_execution_context_t *ec, rb_ractor_t *cr, struct rb_ractor_queue *rq)
{
    struct rb_ractor_basket basket;
    ractor_recursive_receive_if(cr);
    bool received = false;

    RACTOR_LOCK_SELF(cr);
    {
        RUBY_DEBUG_LOG("rq->cnt:%d", rq->cnt);
        received = ractor_queue_deq(cr, rq, &basket);
    }
    RACTOR_UNLOCK_SELF(cr);

    if (!received) {
        if (cr->sync.incoming_port_closed) {
            rb_raise(rb_eRactorClosedError, "The incoming port is already closed");
        }
        return Qundef;
    }
    else {
        return ractor_basket_accept(&basket);
    }
}

static void
ractor_wait_receive(rb_execution_context_t *ec, rb_ractor_t *cr, struct rb_ractor_queue *rq)
{
    VM_ASSERT(cr == rb_ec_ractor_ptr(ec));
    ractor_recursive_receive_if(cr);

    RACTOR_LOCK(cr);
    {
        while (ractor_queue_empty_p(cr, rq) && !cr->sync.incoming_port_closed) {
            ractor_sleep(ec, cr, wait_receiving);
        }
    }
    RACTOR_UNLOCK(cr);
}

static VALUE
ractor_receive(rb_execution_context_t *ec, rb_ractor_t *cr)
{
    VM_ASSERT(cr == rb_ec_ractor_ptr(ec));
    VALUE v;
    struct rb_ractor_queue *rq = &cr->sync.recv_queue;

    while (UNDEF_P(v = ractor_try_receive(ec, cr, rq))) {
        ractor_wait_receive(ec, cr, rq);
    }

    return v;
}

#if 0
static void
rq_dump(struct rb_ractor_queue *rq)
{
    bool bug = false;
    for (int i=0; i<rq->cnt; i++) {
        struct rb_ractor_basket *b = ractor_queue_at(NULL, rq, i);
        fprintf(stderr, "%d (start:%d) type:%s %p %s\n", i, rq->start, basket_type_name(b->type),
                (void *)b, RSTRING_PTR(RARRAY_AREF(b->v, 1)));
        if (basket_type_p(b, basket_type_reserved) bug = true;
    }
    if (bug) rb_bug("!!");
}
#endif

struct receive_block_data {
    rb_ractor_t *cr;
    struct rb_ractor_queue *rq;
    VALUE v;
    int index;
    bool success;
};

static void
ractor_receive_if_lock(rb_ractor_t *cr)
{
    VALUE m = cr->receiving_mutex;
    if (m == Qfalse) {
        m = cr->receiving_mutex = rb_mutex_new();
    }
    rb_mutex_lock(m);
}

static VALUE
receive_if_body(VALUE ptr)
{
    struct receive_block_data *data = (struct receive_block_data *)ptr;

    ractor_receive_if_lock(data->cr);
    VALUE block_result = rb_yield(data->v);
    rb_ractor_t *cr = data->cr;

    RACTOR_LOCK_SELF(cr);
    {
        struct rb_ractor_basket *b = ractor_queue_at(cr, data->rq, data->index);
        VM_ASSERT(basket_type_p(b, basket_type_reserved));
        data->rq->reserved_cnt--;

        if (RTEST(block_result)) {
            ractor_queue_delete(cr, data->rq, b);
            ractor_queue_compact(cr, data->rq);
        }
        else {
            b->type.e = basket_type_ref;
        }
    }
    RACTOR_UNLOCK_SELF(cr);

    data->success = true;

    if (RTEST(block_result)) {
        return data->v;
    }
    else {
        return Qundef;
    }
}

static VALUE
receive_if_ensure(VALUE v)
{
    struct receive_block_data *data = (struct receive_block_data *)v;
    rb_ractor_t *cr = data->cr;

    if (!data->success) {
        RACTOR_LOCK_SELF(cr);
        {
            struct rb_ractor_basket *b = ractor_queue_at(cr, data->rq, data->index);
            VM_ASSERT(basket_type_p(b, basket_type_reserved));
            b->type.e = basket_type_deleted;
            data->rq->reserved_cnt--;
        }
        RACTOR_UNLOCK_SELF(cr);
    }

    rb_mutex_unlock(cr->receiving_mutex);
    return Qnil;
}

static VALUE
ractor_receive_if(rb_execution_context_t *ec, VALUE crv, VALUE b)
{
    if (!RTEST(b)) rb_raise(rb_eArgError, "no block given");

    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    unsigned int serial = (unsigned int)-1;
    int index = 0;
    struct rb_ractor_queue *rq = &cr->sync.recv_queue;

    while (1) {
        VALUE v = Qundef;

        ractor_wait_receive(ec, cr, rq);

        RACTOR_LOCK_SELF(cr);
        {
            if (serial != rq->serial) {
                serial = rq->serial;
                index = 0;
            }

            // check newer version
            for (int i=index; i<rq->cnt; i++) {
                if (!ractor_queue_skip_p(cr, rq, i)) {
                    struct rb_ractor_basket *b = ractor_queue_at(cr, rq, i);
                    v = ractor_basket_value(b);
                    b->type.e = basket_type_reserved;
                    rq->reserved_cnt++;
                    index = i;
                    break;
                }
            }
        }
        RACTOR_UNLOCK_SELF(cr);

        if (!UNDEF_P(v)) {
            struct receive_block_data data = {
                .cr = cr,
                .rq = rq,
                .v = v,
                .index = index,
                .success = false,
            };

            VALUE result = rb_ensure(receive_if_body, (VALUE)&data,
                                     receive_if_ensure, (VALUE)&data);

            if (!UNDEF_P(result)) return result;
            index++;
        }

        RUBY_VM_CHECK_INTS(ec);
    }
}

static void
ractor_send_basket(rb_execution_context_t *ec, rb_ractor_t *r, struct rb_ractor_basket *b)
{
    bool closed = false;

    RACTOR_LOCK(r);
    {
        if (r->sync.incoming_port_closed) {
            closed = true;
        }
        else {
            ractor_queue_enq(r, &r->sync.recv_queue, b);
            ractor_wakeup(r, wait_receiving, wakeup_by_send);
        }
    }
    RACTOR_UNLOCK(r);

    if (closed) {
        rb_raise(rb_eRactorClosedError, "The incoming-port is already closed");
    }
}

// Ractor#send

static VALUE ractor_move(VALUE obj); // in this file
static VALUE ractor_copy(VALUE obj); // in this file

static void
ractor_basket_prepare_contents(VALUE obj, VALUE move, volatile VALUE *pobj, enum rb_ractor_basket_type *ptype)
{
    VALUE v;
    enum rb_ractor_basket_type type;

    if (rb_ractor_shareable_p(obj)) {
        type = basket_type_ref;
        v = obj;
    }
    else if (!RTEST(move)) {
        v = ractor_copy(obj);
        type = basket_type_copy;
    }
    else {
        type = basket_type_move;
        v = ractor_move(obj);
    }

    *pobj = v;
    *ptype = type;
}

static void
ractor_basket_fill_(rb_ractor_t *cr, struct rb_ractor_basket *basket, VALUE obj, bool exc)
{
    VM_ASSERT(cr == GET_RACTOR());

    basket->sender = cr->pub.self;
    basket->p.send.exception = exc;
    basket->p.send.v = obj;
}

static void
ractor_basket_fill(rb_ractor_t *cr, struct rb_ractor_basket *basket, VALUE obj, VALUE move, bool exc)
{
    VALUE v;
    enum rb_ractor_basket_type type;
    ractor_basket_prepare_contents(obj, move, &v, &type);
    ractor_basket_fill_(cr, basket, v, exc);
    basket->type.e = type;
}

static void
ractor_basket_fill_will(rb_ractor_t *cr, struct rb_ractor_basket *basket, VALUE obj, bool exc)
{
    ractor_basket_fill_(cr, basket, obj, exc);
    basket->type.e = basket_type_will;
}

static VALUE
ractor_send(rb_execution_context_t *ec, rb_ractor_t *r, VALUE obj, VALUE move)
{
    struct rb_ractor_basket basket;
    // TODO: Ractor local GC
    ractor_basket_fill(rb_ec_ractor_ptr(ec), &basket, obj, move, false);
    ractor_send_basket(ec, r, &basket);
    return r->pub.self;
}

// Ractor#take

static bool
ractor_take_has_will(rb_ractor_t *r)
{
    ASSERT_ractor_locking(r);

    return basket_type_p(&r->sync.will_basket, basket_type_will);
}

static bool
ractor_take_will(rb_ractor_t *r, struct rb_ractor_basket *b)
{
    ASSERT_ractor_locking(r);

    if (ractor_take_has_will(r)) {
        *b = r->sync.will_basket;
        r->sync.will_basket.type.e = basket_type_none;
        return true;
    }
    else {
        VM_ASSERT(basket_type_p(&r->sync.will_basket, basket_type_none));
        return false;
    }
}

static bool
ractor_take_will_lock(rb_ractor_t *r, struct rb_ractor_basket *b)
{
    ASSERT_ractor_unlocking(r);
    bool taken;

    RACTOR_LOCK(r);
    {
        taken = ractor_take_will(r, b);
    }
    RACTOR_UNLOCK(r);

    return taken;
}

static bool
ractor_register_take(rb_ractor_t *cr, rb_ractor_t *r, struct rb_ractor_basket *take_basket,
                     bool is_take, struct rb_ractor_selector_take_config *config, bool ignore_error)
{
    struct rb_ractor_basket b = {
        .type.e = basket_type_take_basket,
        .sender = cr->pub.self,
        .p = {
            .take = {
                .basket = take_basket,
                .config = config,
            },
        },
    };
    bool closed = false;

    RACTOR_LOCK(r);
    {
        if (is_take && ractor_take_will(r, take_basket)) {
            RUBY_DEBUG_LOG("take over a will of r:%d", rb_ractor_id(r));
        }
        else if (!is_take && ractor_take_has_will(r)) {
            RUBY_DEBUG_LOG("has_will");
            VM_ASSERT(config != NULL);
            config->closed = true;
        }
        else if (r->sync.outgoing_port_closed) {
            closed = true;
        }
        else {
            RUBY_DEBUG_LOG("register in r:%d", rb_ractor_id(r));
            ractor_queue_enq(r, &r->sync.takers_queue, &b);

            if (basket_none_p(take_basket)) {
                ractor_wakeup(r, wait_yielding, wakeup_by_take);
            }
        }
    }
    RACTOR_UNLOCK(r);

    if (closed) {
        if (!ignore_error) rb_raise(rb_eRactorClosedError, "The outgoing-port is already closed");
        return false;
    }
    else {
        return true;
    }
}

static bool
ractor_deregister_take(rb_ractor_t *r, struct rb_ractor_basket *take_basket)
{
    struct rb_ractor_queue *ts = &r->sync.takers_queue;
    bool deleted = false;

    RACTOR_LOCK(r);
    {
        if (r->sync.outgoing_port_closed) {
            // ok
        }
        else {
            for (int i=0; i<ts->cnt; i++) {
                struct rb_ractor_basket *b = ractor_queue_at(r, ts, i);
                if (basket_type_p(b, basket_type_take_basket) && b->p.take.basket == take_basket) {
                    ractor_queue_delete(r, ts, b);
                    deleted = true;
                }
            }
            if (deleted) {
                ractor_queue_compact(r, ts);
            }
        }
    }
    RACTOR_UNLOCK(r);

    return deleted;
}

static VALUE
ractor_try_take(rb_ractor_t *cr, rb_ractor_t *r, struct rb_ractor_basket *take_basket)
{
    bool taken;

    RACTOR_LOCK_SELF(cr);
    {
        if (basket_none_p(take_basket) || basket_type_p(take_basket, basket_type_yielding)) {
            taken = false;
        }
        else {
            taken = true;
        }
    }
    RACTOR_UNLOCK_SELF(cr);

    if (taken) {
        RUBY_DEBUG_LOG("taken");
        if (basket_type_p(take_basket, basket_type_deleted)) {
            VM_ASSERT(r->sync.outgoing_port_closed);
            rb_raise(rb_eRactorClosedError, "The outgoing-port is already closed");
        }
        return ractor_basket_accept(take_basket);
    }
    else {
        RUBY_DEBUG_LOG("not taken");
        return Qundef;
    }
}


#if VM_CHECK_MODE > 0
static bool
ractor_check_specific_take_basket_lock(rb_ractor_t *r, struct rb_ractor_basket *tb)
{
    bool ret = false;
    struct rb_ractor_queue *ts = &r->sync.takers_queue;

    RACTOR_LOCK(r);
    {
        for (int i=0; i<ts->cnt; i++) {
            struct rb_ractor_basket *b = ractor_queue_at(r, ts, i);
            if (basket_type_p(b, basket_type_take_basket) && b->p.take.basket == tb) {
                ret = true;
                break;
            }
        }
    }
    RACTOR_UNLOCK(r);

    return ret;
}
#endif

static void
ractor_take_cleanup(rb_ractor_t *cr, rb_ractor_t *r, struct rb_ractor_basket *tb)
{
  retry:
    if (basket_none_p(tb)) { // not yielded yet
        if (!ractor_deregister_take(r, tb)) {
            // not in r's takers queue
            rb_thread_sleep(0);
            goto retry;
        }
    }
    else {
        VM_ASSERT(!ractor_check_specific_take_basket_lock(r, tb));
    }
}

struct take_wait_take_cleanup_data {
    rb_ractor_t *r;
    struct rb_ractor_basket *tb;
};

static void
ractor_wait_take_cleanup(rb_ractor_t *cr, void *ptr)
{
    struct take_wait_take_cleanup_data *data = (struct take_wait_take_cleanup_data *)ptr;
    ractor_take_cleanup(cr, data->r, data->tb);
}

static void
ractor_wait_take(rb_execution_context_t *ec, rb_ractor_t *cr, rb_ractor_t *r, struct rb_ractor_basket *take_basket)
{
    struct take_wait_take_cleanup_data data = {
        .r = r,
        .tb = take_basket,
    };

    RACTOR_LOCK_SELF(cr);
    {
        if (basket_none_p(take_basket) || basket_type_p(take_basket, basket_type_yielding)) {
            ractor_sleep_with_cleanup(ec, cr, wait_taking, ractor_wait_take_cleanup, &data);
        }
    }
    RACTOR_UNLOCK_SELF(cr);
}

static VALUE
ractor_take(rb_execution_context_t *ec, rb_ractor_t *r)
{
    RUBY_DEBUG_LOG("from r:%u", rb_ractor_id(r));
    VALUE v;
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);

    struct rb_ractor_basket take_basket = {
        .type.e = basket_type_none,
        .sender = 0,
    };

    ractor_register_take(cr, r, &take_basket, true, NULL, false);

    while (UNDEF_P(v = ractor_try_take(cr, r, &take_basket))) {
        ractor_wait_take(ec, cr, r, &take_basket);
    }

    VM_ASSERT(!basket_none_p(&take_basket));
    VM_ASSERT(!ractor_check_specific_take_basket_lock(r, &take_basket));

    return v;
}

// Ractor.yield

static bool
ractor_check_take_basket(rb_ractor_t *cr, struct rb_ractor_queue *rs)
{
    ASSERT_ractor_locking(cr);

    for (int i=0; i<rs->cnt; i++) {
        struct rb_ractor_basket *b = ractor_queue_at(cr, rs, i);
        if (basket_type_p(b, basket_type_take_basket) &&
            basket_none_p(b->p.take.basket)) {
            return true;
        }
    }

    return false;
}

static bool
ractor_deq_take_basket(rb_ractor_t *cr, struct rb_ractor_queue *rs, struct rb_ractor_basket *b)
{
    ASSERT_ractor_unlocking(cr);
    struct rb_ractor_basket *first_tb = NULL;
    bool found = false;

    RACTOR_LOCK_SELF(cr);
    {
        while (ractor_queue_deq(cr, rs, b)) {
            if (basket_type_p(b, basket_type_take_basket)) {
                struct rb_ractor_basket *tb = b->p.take.basket;

                if (RUBY_ATOMIC_CAS(tb->type.atomic, basket_type_none, basket_type_yielding) == basket_type_none) {
                    found = true;
                    break;
                }
                else {
                    ractor_queue_enq(cr, rs, b);
                    if (first_tb == NULL) first_tb = tb;
                    struct rb_ractor_basket *head = ractor_queue_head(cr, rs);
                    VM_ASSERT(head != NULL);
                    if (basket_type_p(head, basket_type_take_basket) && head->p.take.basket == first_tb) {
                        break; // loop detected
                    }
                }
            }
            else {
                VM_ASSERT(basket_none_p(b));
            }
        }

        if (found && b->p.take.config && !b->p.take.config->oneshot) {
            ractor_queue_enq(cr, rs, b);
        }
    }
    RACTOR_UNLOCK_SELF(cr);

    return found;
}

static bool
ractor_try_yield(rb_execution_context_t *ec, rb_ractor_t *cr, struct rb_ractor_queue *ts, volatile VALUE obj, VALUE move, bool exc, bool is_will)
{
    ASSERT_ractor_unlocking(cr);

    struct rb_ractor_basket b;

    if (ractor_deq_take_basket(cr, ts, &b)) {
        VM_ASSERT(basket_type_p(&b, basket_type_take_basket));
        VM_ASSERT(basket_type_p(b.p.take.basket, basket_type_yielding));

        rb_ractor_t *tr = RACTOR_PTR(b.sender);
        struct rb_ractor_basket *tb = b.p.take.basket;
        enum rb_ractor_basket_type type;

        RUBY_DEBUG_LOG("basket from r:%u", rb_ractor_id(tr));

        if (is_will) {
            type = basket_type_will;
        }
        else {
            enum ruby_tag_type state;

            // begin
            EC_PUSH_TAG(ec);
            if ((state = EC_EXEC_TAG()) == TAG_NONE) {
                // TODO: Ractor local GC
                ractor_basket_prepare_contents(obj, move, &obj, &type);
            }
            EC_POP_TAG();
            // rescue
            if (state) {
                RACTOR_LOCK_SELF(cr);
                {
                    b.p.take.basket->type.e = basket_type_none;
                    ractor_queue_enq(cr, ts, &b);
                }
                RACTOR_UNLOCK_SELF(cr);
                EC_JUMP_TAG(ec, state);
            }
        }

        RACTOR_LOCK(tr);
        {
            VM_ASSERT(basket_type_p(tb, basket_type_yielding));
            // fill atomic
            RUBY_DEBUG_LOG("fill %sbasket from r:%u", is_will ? "will " : "", rb_ractor_id(tr));
            ractor_basket_fill_(cr, tb, obj, exc);
            if (RUBY_ATOMIC_CAS(tb->type.atomic, basket_type_yielding, type) != basket_type_yielding) {
                rb_bug("unreachable");
            }
            ractor_wakeup(tr, wait_taking, wakeup_by_yield);
        }
        RACTOR_UNLOCK(tr);

        return true;
    }
    else if (cr->sync.outgoing_port_closed) {
        rb_raise(rb_eRactorClosedError, "The outgoing-port is already closed");
    }
    else {
        RUBY_DEBUG_LOG("no take basket");
        return false;
    }
}

static void
ractor_wait_yield(rb_execution_context_t *ec, rb_ractor_t *cr, struct rb_ractor_queue *ts)
{
    RACTOR_LOCK_SELF(cr);
    {
        while (!ractor_check_take_basket(cr, ts) && !cr->sync.outgoing_port_closed) {
            ractor_sleep(ec, cr, wait_yielding);
        }
    }
    RACTOR_UNLOCK_SELF(cr);
}

static VALUE
ractor_yield(rb_execution_context_t *ec, rb_ractor_t *cr, VALUE obj, VALUE move)
{
    struct rb_ractor_queue *ts = &cr->sync.takers_queue;

    while (!ractor_try_yield(ec, cr, ts, obj, move, false, false)) {
        ractor_wait_yield(ec, cr, ts);
    }

    return Qnil;
}

// Ractor::Selector

struct rb_ractor_selector {
    rb_ractor_t *r;
    struct rb_ractor_basket take_basket;
    st_table *take_ractors; // rb_ractor_t * => (struct rb_ractor_selector_take_config *)
};

static int
ractor_selector_mark_ractors_i(st_data_t key, st_data_t value, st_data_t data)
{
    const rb_ractor_t *r = (rb_ractor_t *)key;
    rb_gc_mark(r->pub.self);
    return ST_CONTINUE;
}

static void
ractor_selector_mark(void *ptr)
{
    struct rb_ractor_selector *s = ptr;

    if (s->take_ractors) {
        st_foreach(s->take_ractors, ractor_selector_mark_ractors_i, 0);
    }

    switch (s->take_basket.type.e) {
      case basket_type_ref:
      case basket_type_copy:
      case basket_type_move:
      case basket_type_will:
        rb_gc_mark(s->take_basket.sender);
        rb_gc_mark(s->take_basket.p.send.v);
        break;
      default:
        break;
    }
}

static int
ractor_selector_release_i(st_data_t key, st_data_t val, st_data_t data)
{
    struct rb_ractor_selector *s = (struct rb_ractor_selector *)data;
    struct rb_ractor_selector_take_config *config = (struct rb_ractor_selector_take_config *)val;

    if (!config->closed) {
        ractor_deregister_take((rb_ractor_t *)key, &s->take_basket);
    }
    free(config);
    return ST_CONTINUE;
}

static void
ractor_selector_free(void *ptr)
{
    struct rb_ractor_selector *s = ptr;
    st_foreach(s->take_ractors, ractor_selector_release_i, (st_data_t)s);
    st_free_table(s->take_ractors);
    ruby_xfree(ptr);
}

static size_t
ractor_selector_memsize(const void *ptr)
{
    const struct rb_ractor_selector *s = ptr;
    return sizeof(struct rb_ractor_selector) +
      st_memsize(s->take_ractors) +
      s->take_ractors->num_entries * sizeof(struct rb_ractor_selector_take_config);
}

static const rb_data_type_t ractor_selector_data_type = {
    "ractor/selector",
    {
        ractor_selector_mark,
        ractor_selector_free,
        ractor_selector_memsize,
        NULL, // update
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static struct rb_ractor_selector *
RACTOR_SELECTOR_PTR(VALUE selv)
{
    VM_ASSERT(rb_typeddata_is_kind_of(selv, &ractor_selector_data_type));

    return (struct rb_ractor_selector *)DATA_PTR(selv);
}

// Ractor::Selector.new

static VALUE
ractor_selector_create(VALUE klass)
{
    struct rb_ractor_selector *s;
    VALUE selv = TypedData_Make_Struct(klass, struct rb_ractor_selector, &ractor_selector_data_type, s);
    s->take_basket.type.e = basket_type_reserved;
    s->take_ractors = st_init_numtable(); // ractor (ptr) -> take_config
    return selv;
}

// Ractor::Selector#add(r)

/*
 * call-seq:
 *   add(ractor) -> ractor
 *
 * Adds _ractor_ to +self+.  Raises an exception if _ractor_ is already added.
 * Returns _ractor_.
 */
static VALUE
ractor_selector_add(VALUE selv, VALUE rv)
{
    if (!rb_ractor_p(rv)) {
        rb_raise(rb_eArgError, "Not a ractor object");
    }

    rb_ractor_t *r = RACTOR_PTR(rv);
    struct rb_ractor_selector *s = RACTOR_SELECTOR_PTR(selv);

    if (st_lookup(s->take_ractors, (st_data_t)r, NULL)) {
        rb_raise(rb_eArgError, "already added");
    }

    struct rb_ractor_selector_take_config *config = malloc(sizeof(struct rb_ractor_selector_take_config));
    VM_ASSERT(config != NULL);
    config->closed = false;
    config->oneshot = false;

    if (ractor_register_take(GET_RACTOR(), r, &s->take_basket, false, config, true)) {
        st_insert(s->take_ractors, (st_data_t)r, (st_data_t)config);
    }

    return rv;
}

// Ractor::Selector#remove(r)

/* call-seq:
 *   remove(ractor) -> ractor
 *
 * Removes _ractor_ from +self+.  Raises an exception if _ractor_ is not added.
 * Returns the removed _ractor_.
 */
static VALUE
ractor_selector_remove(VALUE selv, VALUE rv)
{
    if (!rb_ractor_p(rv)) {
        rb_raise(rb_eArgError, "Not a ractor object");
    }

    rb_ractor_t *r = RACTOR_PTR(rv);
    struct rb_ractor_selector *s = RACTOR_SELECTOR_PTR(selv);

    RUBY_DEBUG_LOG("r:%u", rb_ractor_id(r));

    if (!st_lookup(s->take_ractors, (st_data_t)r, NULL)) {
        rb_raise(rb_eArgError, "not added yet");
    }

    ractor_deregister_take(r, &s->take_basket);
    struct rb_ractor_selector_take_config *config;
    st_delete(s->take_ractors, (st_data_t *)&r, (st_data_t *)&config);
    free(config);

    return rv;
}

// Ractor::Selector#clear

struct ractor_selector_clear_data {
    VALUE selv;
    rb_execution_context_t *ec;
};

static int
ractor_selector_clear_i(st_data_t key, st_data_t val, st_data_t data)
{
    VALUE selv = (VALUE)data;
    rb_ractor_t *r = (rb_ractor_t *)key;
    ractor_selector_remove(selv, r->pub.self);
    return ST_CONTINUE;
}

/*
 * call-seq:
 *   clear -> self
 *
 * Removes all ractors from +self+.  Raises +self+.
 */
static VALUE
ractor_selector_clear(VALUE selv)
{
    struct rb_ractor_selector *s = RACTOR_SELECTOR_PTR(selv);

    st_foreach(s->take_ractors, ractor_selector_clear_i, (st_data_t)selv);
    st_clear(s->take_ractors);
    return selv;
}

/*
 * call-seq:
 *  empty? -> true or false
 *
 * Returns +true+ if no ractor is added.
 */
static VALUE
ractor_selector_empty_p(VALUE selv)
{
    struct rb_ractor_selector *s = RACTOR_SELECTOR_PTR(selv);
    return s->take_ractors->num_entries == 0 ? Qtrue : Qfalse;
}

static int
ractor_selector_wait_i(st_data_t key, st_data_t val, st_data_t dat)
{
    rb_ractor_t *r = (rb_ractor_t *)key;
    struct rb_ractor_basket *tb = (struct rb_ractor_basket *)dat;
    int ret;

    if (!basket_none_p(tb)) {
        RUBY_DEBUG_LOG("already taken:%s", basket_type_name(tb->type.e));
        return ST_STOP;
    }

    RACTOR_LOCK(r);
    {
        if (basket_type_p(&r->sync.will_basket, basket_type_will)) {
            RUBY_DEBUG_LOG("r:%u has will", rb_ractor_id(r));

            if (RUBY_ATOMIC_CAS(tb->type.atomic, basket_type_none, basket_type_will) == basket_type_none) {
                ractor_take_will(r, tb);
                ret = ST_STOP;
            }
            else {
                RUBY_DEBUG_LOG("has will, but already taken (%s)", basket_type_name(tb->type.e));
                ret = ST_CONTINUE;
            }
        }
        else if (r->sync.outgoing_port_closed) {
            RUBY_DEBUG_LOG("r:%u is closed", rb_ractor_id(r));

            if (RUBY_ATOMIC_CAS(tb->type.atomic, basket_type_none, basket_type_deleted) == basket_type_none) {
                tb->sender = r->pub.self;
                ret = ST_STOP;
            }
            else {
                RUBY_DEBUG_LOG("closed, but already taken (%s)", basket_type_name(tb->type.e));
                ret = ST_CONTINUE;
            }
        }
        else {
            RUBY_DEBUG_LOG("wakeup r:%u", rb_ractor_id(r));
            ractor_wakeup(r, wait_yielding, wakeup_by_take);
            ret = ST_CONTINUE;
        }
    }
    RACTOR_UNLOCK(r);

    return ret;
}

// Ractor::Selector#wait

static void
ractor_selector_wait_cleaup(rb_ractor_t *cr, void *ptr)
{
    struct rb_ractor_basket *tb = (struct rb_ractor_basket *)ptr;

    RACTOR_LOCK_SELF(cr);
    {
        while (basket_type_p(tb, basket_type_yielding)) rb_thread_sleep(0);
        // if tb->type is not none, taking is succeeded, but interruption ignore it unfortunately.
        tb->type.e = basket_type_reserved;
    }
    RACTOR_UNLOCK_SELF(cr);
}

/* :nodoc: */
static VALUE
ractor_selector__wait(VALUE selv, VALUE do_receivev, VALUE do_yieldv, VALUE yield_value, VALUE move)
{
    rb_execution_context_t *ec = GET_EC();
    struct rb_ractor_selector *s = RACTOR_SELECTOR_PTR(selv);
    struct rb_ractor_basket *tb = &s->take_basket;
    struct rb_ractor_basket taken_basket;
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    bool do_receive = !!RTEST(do_receivev);
    bool do_yield = !!RTEST(do_yieldv);
    VALUE ret_v, ret_r;
    enum rb_ractor_wait_status wait_status;
    struct rb_ractor_queue *rq = &cr->sync.recv_queue;
    struct rb_ractor_queue *ts = &cr->sync.takers_queue;

    RUBY_DEBUG_LOG("start");

  retry:
    RUBY_DEBUG_LOG("takers:%ld", s->take_ractors->num_entries);

    // setup wait_status
    wait_status = wait_none;
    if (s->take_ractors->num_entries > 0) wait_status |= wait_taking;
    if (do_receive)                       wait_status |= wait_receiving;
    if (do_yield)                         wait_status |= wait_yielding;

    RUBY_DEBUG_LOG("wait:%s", wait_status_str(wait_status));

    if (wait_status == wait_none) {
        rb_raise(rb_eRactorError, "no taking ractors");
    }

    // check recv_queue
    if (do_receive && !UNDEF_P(ret_v = ractor_try_receive(ec, cr, rq))) {
        ret_r = ID2SYM(rb_intern("receive"));
        goto success;
    }

    // check takers
    if (do_yield && ractor_try_yield(ec, cr, ts, yield_value, move, false, false)) {
        ret_v = Qnil;
        ret_r = ID2SYM(rb_intern("yield"));
        goto success;
    }

    // check take_basket
    VM_ASSERT(basket_type_p(&s->take_basket, basket_type_reserved));
    s->take_basket.type.e = basket_type_none;
    // kick all take target ractors
    st_foreach(s->take_ractors, ractor_selector_wait_i, (st_data_t)tb);

    RACTOR_LOCK_SELF(cr);
    {
      retry_waiting:
        while (1) {
            if (!basket_none_p(tb)) {
                RUBY_DEBUG_LOG("taken:%s from r:%u", basket_type_name(tb->type.e),
                               tb->sender ? rb_ractor_id(RACTOR_PTR(tb->sender)) : 0);
                break;
            }
            if (do_receive && !ractor_queue_empty_p(cr, rq)) {
                RUBY_DEBUG_LOG("can receive (%d)", rq->cnt);
                break;
            }
            if (do_yield && ractor_check_take_basket(cr, ts)) {
                RUBY_DEBUG_LOG("can yield");
                break;
            }

            ractor_sleep_with_cleanup(ec, cr, wait_status, ractor_selector_wait_cleaup, tb);
        }

        taken_basket = *tb;

        // ensure
        //   tb->type.e = basket_type_reserved # do it atomic in the following code
        if (taken_basket.type.e == basket_type_yielding ||
            RUBY_ATOMIC_CAS(tb->type.atomic, taken_basket.type.e, basket_type_reserved) != taken_basket.type.e) {

            if (basket_type_p(tb, basket_type_yielding)) {
                RACTOR_UNLOCK_SELF(cr);
                {
                    rb_thread_sleep(0);
                }
                RACTOR_LOCK_SELF(cr);
            }
            goto retry_waiting;
        }
    }
    RACTOR_UNLOCK_SELF(cr);

    // check the taken result
    switch (taken_basket.type.e) {
      case basket_type_none:
        VM_ASSERT(do_receive || do_yield);
        goto retry;
      case basket_type_yielding:
        rb_bug("unreachable");
      case basket_type_deleted: {
          ractor_selector_remove(selv, taken_basket.sender);

          rb_ractor_t *r = RACTOR_PTR(taken_basket.sender);
          if (ractor_take_will_lock(r, &taken_basket)) {
              RUBY_DEBUG_LOG("has_will");
          }
          else {
              RUBY_DEBUG_LOG("no will");
              // rb_raise(rb_eRactorClosedError, "The outgoing-port is already closed");
              // remove and retry wait
              goto retry;
          }
          break;
      }
      case basket_type_will:
        // no more messages
        ractor_selector_remove(selv, taken_basket.sender);
        break;
      default:
        break;
    }

    RUBY_DEBUG_LOG("taken_basket:%s", basket_type_name(taken_basket.type.e));

    ret_v = ractor_basket_accept(&taken_basket);
    ret_r = taken_basket.sender;
  success:
    return rb_ary_new_from_args(2, ret_r, ret_v);
}

/*
 * call-seq:
 *  wait(receive: false, yield_value: undef, move: false) -> [ractor, value]
 *
 * Waits until any ractor in _selector_ can be active.
 */
static VALUE
ractor_selector_wait(int argc, VALUE *argv, VALUE selector)
{
    VALUE options;
    ID keywords[3];
    VALUE values[3];

    keywords[0] = rb_intern("receive");
    keywords[1] = rb_intern("yield_value");
    keywords[2] = rb_intern("move");

    rb_scan_args(argc, argv, "0:", &options);
    rb_get_kwargs(options, keywords, 0, numberof(values), values);
    return ractor_selector__wait(selector,
                                 values[0] == Qundef ? Qfalse : RTEST(values[0]),
                                 values[1] != Qundef, values[1], values[2]);
}

static VALUE
ractor_selector_new(int argc, VALUE *ractors, VALUE klass)
{
    VALUE selector = ractor_selector_create(klass);

    for (int i=0; i<argc; i++) {
        ractor_selector_add(selector, ractors[i]);
    }

    return selector;
}

static VALUE
ractor_select_internal(rb_execution_context_t *ec, VALUE self, VALUE ractors, VALUE do_receive, VALUE do_yield, VALUE yield_value, VALUE move)
{
    VALUE selector = ractor_selector_new(RARRAY_LENINT(ractors), (VALUE *)RARRAY_CONST_PTR(ractors), rb_cRactorSelector);
    VALUE result;
    int state;

    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        result = ractor_selector__wait(selector, do_receive, do_yield, yield_value, move);
    }
    EC_POP_TAG();
    if (state != TAG_NONE) {
        // ensure
        ractor_selector_clear(selector);

        // jump
        EC_JUMP_TAG(ec, state);
    }

    RB_GC_GUARD(ractors);
    return result;
}

// Ractor#close_incoming

static VALUE
ractor_close_incoming(rb_execution_context_t *ec, rb_ractor_t *r)
{
    VALUE prev;

    RACTOR_LOCK(r);
    {
        if (!r->sync.incoming_port_closed) {
            prev = Qfalse;
            r->sync.incoming_port_closed = true;
            if (ractor_wakeup(r, wait_receiving, wakeup_by_close)) {
                VM_ASSERT(ractor_queue_empty_p(r, &r->sync.recv_queue));
                RUBY_DEBUG_LOG("cancel receiving");
            }
        }
        else {
            prev = Qtrue;
        }
    }
    RACTOR_UNLOCK(r);
    return prev;
}

// Ractor#close_outgoing

static VALUE
ractor_close_outgoing(rb_execution_context_t *ec, rb_ractor_t *r)
{
    VALUE prev;

    RACTOR_LOCK(r);
    {
        struct rb_ractor_queue *ts = &r->sync.takers_queue;
        rb_ractor_t *tr;
        struct rb_ractor_basket b;

        if (!r->sync.outgoing_port_closed) {
            prev = Qfalse;
            r->sync.outgoing_port_closed = true;
        }
        else {
            VM_ASSERT(ractor_queue_empty_p(r, ts));
            prev = Qtrue;
        }

        // wakeup all taking ractors
        while (ractor_queue_deq(r, ts, &b)) {
            if (basket_type_p(&b, basket_type_take_basket)) {
                tr = RACTOR_PTR(b.sender);
                struct rb_ractor_basket *tb = b.p.take.basket;

                if (RUBY_ATOMIC_CAS(tb->type.atomic, basket_type_none, basket_type_yielding) == basket_type_none) {
                    b.p.take.basket->sender = r->pub.self;
                    if (RUBY_ATOMIC_CAS(tb->type.atomic, basket_type_yielding, basket_type_deleted) != basket_type_yielding) {
                        rb_bug("unreachable");
                    }
                    RUBY_DEBUG_LOG("set delete for r:%u", rb_ractor_id(RACTOR_PTR(b.sender)));
                }

                if (b.p.take.config) {
                    b.p.take.config->closed = true;
                }

                // TODO: deadlock-able?
                RACTOR_LOCK(tr);
                {
                    ractor_wakeup(tr, wait_taking, wakeup_by_close);
                }
                RACTOR_UNLOCK(tr);
            }
        }

        // raising yielding Ractor
        ractor_wakeup(r, wait_yielding, wakeup_by_close);

        VM_ASSERT(ractor_queue_empty_p(r, ts));
    }
    RACTOR_UNLOCK(r);
    return prev;
}

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
    r->sync.outgoing_port_closed = true;
    r->sync.incoming_port_closed = true;
    r->sync.will_basket.type.e = basket_type_none;
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
    ractor_queue_setup(&r->sync.recv_queue);
    ractor_queue_setup(&r->sync.takers_queue);
    rb_native_mutex_initialize(&r->sync.lock);
    rb_native_cond_initialize(&r->barrier_wait_cond);

#ifdef RUBY_THREAD_WIN32_H
    rb_native_cond_initialize(&r->sync.cond);
    rb_native_cond_initialize(&r->barrier_wait_cond);
#endif

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
    r->pub.self = TypedData_Wrap_Struct(rb_cRactor, &ractor_data_type, r);
    FL_SET_RAW(r->pub.self, RUBY_FL_SHAREABLE);
    ractor_init(r, Qnil, Qnil);
    r->threads.main = th;
    rb_ractor_living_threads_insert(r, th);
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

static VALUE
ractor_create_func(VALUE klass, VALUE loc, VALUE name, VALUE args, rb_block_call_func_t func)
{
    VALUE block = rb_proc_new(func, Qnil);
    return ractor_create(rb_current_ec_noinline(), klass, loc, name, args, block);
}

static void
ractor_yield_atexit(rb_execution_context_t *ec, rb_ractor_t *cr, VALUE v, bool exc)
{
    if (cr->sync.outgoing_port_closed) {
        return;
    }

    ASSERT_ractor_unlocking(cr);

    struct rb_ractor_queue *ts = &cr->sync.takers_queue;

  retry:
    if (ractor_try_yield(ec, cr, ts, v, Qfalse, exc, true)) {
        // OK.
    }
    else {
        bool retry = false;
        RACTOR_LOCK(cr);
        {
            if (!ractor_check_take_basket(cr, ts)) {
                VM_ASSERT(cr->sync.wait.status == wait_none);
                RUBY_DEBUG_LOG("leave a will");
                ractor_basket_fill_will(cr, &cr->sync.will_basket, v, exc);
            }
            else {
                RUBY_DEBUG_LOG("rare timing!");
                retry = true; // another ractor is waiting for the yield.
            }
        }
        RACTOR_UNLOCK(cr);

        if (retry) goto retry;
    }
}

void
rb_ractor_atexit(rb_execution_context_t *ec, VALUE result)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    ractor_yield_atexit(ec, cr, result, false);
}

void
rb_ractor_atexit_exception(rb_execution_context_t *ec)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    ractor_yield_atexit(ec, cr, ec->errinfo, true);
}

void
rb_ractor_teardown(rb_execution_context_t *ec)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    ractor_close_incoming(ec, cr);
    ractor_close_outgoing(ec, cr);

    // sync with rb_ractor_terminate_interrupt_main_thread()
    RB_VM_LOCK_ENTER();
    {
        VM_ASSERT(cr->threads.main != NULL);
        cr->threads.main = NULL;
    }
    RB_VM_LOCK_LEAVE();
}

void
rb_ractor_receive_parameters(rb_execution_context_t *ec, rb_ractor_t *r, int len, VALUE *ptr)
{
    for (int i=0; i<len; i++) {
        ptr[i] = ractor_receive(ec, r);
    }
}

void
rb_ractor_send_parameters(rb_execution_context_t *ec, rb_ractor_t *r, VALUE args)
{
    int len = RARRAY_LENINT(args);
    for (int i=0; i<len; i++) {
        ractor_send(ec, r, RARRAY_AREF(args, i), false);
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

        RB_VM_LOCK_ENTER();
        {
            rb_vm_ractor_blocking_cnt_inc(vm, cr, file, line);
        }
        RB_VM_LOCK_LEAVE();
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

        RB_VM_LOCK_ENTER();
        {
            rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);
        }
        RB_VM_LOCK_LEAVE();
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

#ifndef USE_RACTOR_SELECTOR
#define USE_RACTOR_SELECTOR 0
#endif

RUBY_SYMBOL_EXPORT_BEGIN
void rb_init_ractor_selector(void);
RUBY_SYMBOL_EXPORT_END

/*
 * Document-class: Ractor::Selector
 * :nodoc: currently
 *
 * Selects multiple Ractors to be activated.
 */
void
rb_init_ractor_selector(void)
{
    rb_cRactorSelector = rb_define_class_under(rb_cRactor, "Selector", rb_cObject);
    rb_undef_alloc_func(rb_cRactorSelector);

    rb_define_singleton_method(rb_cRactorSelector, "new", ractor_selector_new , -1);
    rb_define_method(rb_cRactorSelector, "add", ractor_selector_add, 1);
    rb_define_method(rb_cRactorSelector, "remove", ractor_selector_remove, 1);
    rb_define_method(rb_cRactorSelector, "clear", ractor_selector_clear, 0);
    rb_define_method(rb_cRactorSelector, "empty?", ractor_selector_empty_p, 0);
    rb_define_method(rb_cRactorSelector, "wait", ractor_selector_wait, -1);
    rb_define_method(rb_cRactorSelector, "_wait", ractor_selector__wait, 4);
}

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

    // internal

#if USE_RACTOR_SELECTOR
    rb_init_ractor_selector();
#endif
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
            RB_VM_LOCK_ENTER_NO_BARRIER();
            {
                rb_objspace_reachable_objects_from(obj, obj_traverse_reachable_i, &d);
            }
            RB_VM_LOCK_LEAVE_NO_BARRIER();
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
            rb_raise(rb_eRactorError, "can not make shareable object for %"PRIsVALUE, obj);
        }
    }

    if (RB_TYPE_P(obj, T_IMEMO)) {
        return traverse_skip;
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
    RB_VM_LOCK_ENTER_NO_BARRIER();
    {
        rb_objspace_reachable_objects_from(obj, obj_refer_only_shareables_p_i, &cnt);
    }
    RB_VM_LOCK_LEAVE_NO_BARRIER();
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
    }

    if (!data->move) {
        obj = replacement;
    }

#define CHECK_AND_REPLACE(v) do { \
    VALUE _val = (v); \
    if (obj_traverse_replace_i(_val, data)) { return 1; } \
    else if (data->replacement != _val)     { RB_OBJ_WRITE(obj, &v, data->replacement); } \
} while (0)

    if (UNLIKELY(FL_TEST_RAW(obj, FL_EXIVAR))) {
        struct gen_fields_tbl *fields_tbl;
        rb_ivar_generic_fields_tbl_lookup(obj, &fields_tbl);

        if (UNLIKELY(rb_shape_obj_too_complex_p(obj))) {
            struct obj_traverse_replace_callback_data d = {
                .stop = false,
                .data = data,
                .src = obj,
            };
            rb_st_foreach_with_replace(
                fields_tbl->as.complex.table,
                obj_iv_hash_traverse_replace_foreach_i,
                obj_iv_hash_traverse_replace_i,
                (st_data_t)&d
            );
            if (d.stop) return 1;
        }
        else {
            for (uint32_t i = 0; i < fields_tbl->as.shape.fields_count; i++) {
                if (!UNDEF_P(fields_tbl->as.shape.fields[i])) {
                    CHECK_AND_REPLACE(fields_tbl->as.shape.fields[i]);
                }
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
                    CHECK_AND_REPLACE(ptr[i]);
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
                CHECK_AND_REPLACE(ptr[i]);
            }
        }
        break;

      case T_RATIONAL:
        CHECK_AND_REPLACE(RRATIONAL(obj)->num);
        CHECK_AND_REPLACE(RRATIONAL(obj)->den);
        break;
      case T_COMPLEX:
        CHECK_AND_REPLACE(RCOMPLEX(obj)->real);
        CHECK_AND_REPLACE(RCOMPLEX(obj)->imag);
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
    size_t size = rb_gc_obj_slot_size(obj);
    memcpy((void *)data->replacement, (void *)obj, size);

    void rb_replace_generic_ivar(VALUE clone, VALUE obj); // variable.c

    rb_gc_obj_id_moved(data->replacement);

    if (UNLIKELY(FL_TEST_RAW(obj, FL_EXIVAR))) {
        rb_replace_generic_ivar(data->replacement, obj);
    }

    if (FL_TEST_RAW(obj, RUBY_FL_ADDRESS_SEEN) && !rb_obj_old_address_p(obj)) {
        rb_shape_t *old_address_shape = rb_obj_old_address_shape(obj);
        VALUE old_address;
#if SIZEOF_LONG == SIZEOF_VOIDP
        old_address = LONG2NUM(obj);
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
        old_address = LL2NUM(obj);
#endif
        rb_obj_field_set(data->replacement, old_address_shape, old_address);
    }

    // Avoid mutations using bind_call, etc.
    // We keep FL_SEEN_OBJ_ID so GC later clean the obj_id_table.
    MEMZERO((char *)obj + sizeof(struct RBasic), char, size - sizeof(struct RBasic));
    RBASIC(obj)->flags = T_OBJECT | FL_FREEZE;
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
    RB_VM_LOCK_ENTER();
    {
        if (freed_ractor_local_keys.cnt == freed_ractor_local_keys.capa) {
            freed_ractor_local_keys.capa = freed_ractor_local_keys.capa ? freed_ractor_local_keys.capa * 2 : 4;
            REALLOC_N(freed_ractor_local_keys.keys, rb_ractor_local_key_t, freed_ractor_local_keys.capa);
        }
        freed_ractor_local_keys.keys[freed_ractor_local_keys.cnt++] = key;
    }
    RB_VM_LOCK_LEAVE();
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

// Ractor::Channel (emulate with Ractor)

typedef rb_ractor_t rb_ractor_channel_t;

static VALUE
ractor_channel_func(RB_BLOCK_CALL_FUNC_ARGLIST(y, c))
{
    rb_execution_context_t *ec = GET_EC();
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);

    while (1) {
        int state;

        EC_PUSH_TAG(ec);
        if ((state = EC_EXEC_TAG()) == TAG_NONE) {
            VALUE obj = ractor_receive(ec, cr);
            ractor_yield(ec, cr, obj, Qfalse);
        }
        EC_POP_TAG();

        if (state) {
            // ignore the error
            break;
        }
    }

    return Qnil;
}

static VALUE
rb_ractor_channel_new(void)
{
#if 0
    return rb_funcall(rb_const_get(rb_cRactor, rb_intern("Channel")), rb_intern("new"), 0);
#else
    // class Channel
    //   def self.new
    //     Ractor.new do # func body
    //       while true
    //         obj = Ractor.receive
    //         Ractor.yield obj
    //       end
    //     rescue Ractor::ClosedError
    //       nil
    //     end
    //   end
    // end

    return ractor_create_func(rb_cRactor, Qnil, rb_str_new2("Ractor/channel"), rb_ary_new(), ractor_channel_func);
#endif
}

static VALUE
rb_ractor_channel_yield(rb_execution_context_t *ec, VALUE vch, VALUE obj)
{
    VM_ASSERT(ec == rb_current_ec_noinline());
    rb_ractor_channel_t *ch = RACTOR_PTR(vch);

    ractor_send(ec, (rb_ractor_t *)ch, obj, Qfalse);
    return Qnil;
}

static VALUE
rb_ractor_channel_take(rb_execution_context_t *ec, VALUE vch)
{
    VM_ASSERT(ec == rb_current_ec_noinline());
    rb_ractor_channel_t *ch = RACTOR_PTR(vch);

    return ractor_take(ec, (rb_ractor_t *)ch);
}

static VALUE
rb_ractor_channel_close(rb_execution_context_t *ec, VALUE vch)
{
    VM_ASSERT(ec == rb_current_ec_noinline());
    rb_ractor_channel_t *ch = RACTOR_PTR(vch);

    ractor_close_incoming(ec, (rb_ractor_t *)ch);
    return ractor_close_outgoing(ec, (rb_ractor_t *)ch);
}

// Ractor#require

struct cross_ractor_require {
    VALUE ch;
    VALUE result;
    VALUE exception;

    // require
    VALUE feature;

    // autoload
    VALUE module;
    ID name;
};

static VALUE
require_body(VALUE data)
{
    struct cross_ractor_require *crr = (struct cross_ractor_require *)data;

    ID require;
    CONST_ID(require, "require");
    crr->result = rb_funcallv(Qnil, require, 1, &crr->feature);

    return Qnil;
}

static VALUE
require_rescue(VALUE data, VALUE errinfo)
{
    struct cross_ractor_require *crr = (struct cross_ractor_require *)data;
    crr->exception = errinfo;
    return Qundef;
}

static VALUE
require_result_copy_body(VALUE data)
{
    struct cross_ractor_require *crr = (struct cross_ractor_require *)data;

    if (crr->exception != Qundef) {
        VM_ASSERT(crr->result == Qundef);
        crr->exception = ractor_copy(crr->exception);
    }
    else{
        VM_ASSERT(crr->result != Qundef);
        crr->result = ractor_copy(crr->result);
    }

    return Qnil;
}

static VALUE
require_result_copy_resuce(VALUE data, VALUE errinfo)
{
    struct cross_ractor_require *crr = (struct cross_ractor_require *)data;
    crr->exception = errinfo; // ractor_move(crr->exception);
    return Qnil;
}

static VALUE
ractor_require_protect(struct cross_ractor_require *crr, VALUE (*func)(VALUE))
{
    // catch any error
    rb_rescue2(func, (VALUE)crr,
               require_rescue, (VALUE)crr, rb_eException, 0);

    rb_rescue2(require_result_copy_body, (VALUE)crr,
               require_result_copy_resuce, (VALUE)crr, rb_eException, 0);

    rb_ractor_channel_yield(GET_EC(), crr->ch, Qtrue);
    return Qnil;

}

static VALUE
ractore_require_func(void *data)
{
    struct cross_ractor_require *crr = (struct cross_ractor_require *)data;
    return ractor_require_protect(crr, require_body);
}

VALUE
rb_ractor_require(VALUE feature)
{
    // TODO: make feature shareable
    struct cross_ractor_require crr = {
        .feature = feature, // TODO: ractor
        .ch = rb_ractor_channel_new(),
        .result = Qundef,
        .exception = Qundef,
    };

    rb_execution_context_t *ec = GET_EC();
    rb_ractor_t *main_r = GET_VM()->ractor.main_ractor;
    rb_ractor_interrupt_exec(main_r, ractore_require_func, &crr, 0);

    // wait for require done
    rb_ractor_channel_take(ec, crr.ch);
    rb_ractor_channel_close(ec, crr.ch);

    if (crr.exception != Qundef) {
        rb_exc_raise(crr.exception);
    }
    else {
        return crr.result;
    }
}

static VALUE
ractor_require(rb_execution_context_t *ec, VALUE self, VALUE feature)
{
    return rb_ractor_require(feature);
}

static VALUE
autoload_load_body(VALUE data)
{
    struct cross_ractor_require *crr = (struct cross_ractor_require *)data;
    crr->result = rb_autoload_load(crr->module, crr->name);
    return Qnil;
}

static VALUE
ractor_autoload_load_func(void *data)
{
    struct cross_ractor_require *crr = (struct cross_ractor_require *)data;
    return ractor_require_protect(crr, autoload_load_body);
}

VALUE
rb_ractor_autoload_load(VALUE module, ID name)
{
    struct cross_ractor_require crr = {
        .module = module,
        .name = name,
        .ch = rb_ractor_channel_new(),
        .result = Qundef,
        .exception = Qundef,
    };

    rb_execution_context_t *ec = GET_EC();
    rb_ractor_t *main_r = GET_VM()->ractor.main_ractor;
    rb_ractor_interrupt_exec(main_r, ractor_autoload_load_func, &crr, 0);

    // wait for require done
    rb_ractor_channel_take(ec, crr.ch);
    rb_ractor_channel_close(ec, crr.ch);

    if (crr.exception != Qundef) {
        rb_exc_raise(crr.exception);
    }
    else {
        return crr.result;
    }
}

#include "ractor.rbinc"
