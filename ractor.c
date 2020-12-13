// Ractor implementation

#include "ruby/ruby.h"
#include "ruby/thread.h"
#include "ruby/ractor.h"
#include "ruby/thread_native.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "ractor_core.h"
#include "internal/complex.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/rational.h"
#include "internal/struct.h"
#include "variable.h"
#include "gc.h"
#include "transient_heap.h"

VALUE rb_cRactor;
static VALUE rb_eRactorError;
static VALUE rb_eRactorRemoteError;
static VALUE rb_eRactorMovedError;
static VALUE rb_eRactorClosedError;
static VALUE rb_cRactorMovedObject;
VALUE rb_eRactorUnsafeError;

VALUE
rb_ractor_error_class(void)
{
    return rb_eRactorError;
}

static void vm_ractor_blocking_cnt_inc(rb_vm_t *vm, rb_ractor_t *r, const char *file, int line);

static void
ASSERT_ractor_unlocking(rb_ractor_t *r)
{
#if RACTOR_CHECK_MODE > 0
    // GET_EC is NULL in an MJIT worker
    if (GET_EC() != NULL && r->sync.locked_by == GET_RACTOR()->self) {
        rb_bug("recursive ractor locking");
    }
#endif
}

static void
ASSERT_ractor_locking(rb_ractor_t *r)
{
#if RACTOR_CHECK_MODE > 0
    // GET_EC is NULL in an MJIT worker
    if (GET_EC() != NULL && r->sync.locked_by != GET_RACTOR()->self) {
        rp(r->sync.locked_by);
        rb_bug("ractor lock is not acquired.");
    }
#endif
}

static void
ractor_lock(rb_ractor_t *r, const char *file, int line)
{
    RUBY_DEBUG_LOG2(file, line, "locking r:%u%s", r->id, GET_RACTOR() == r ? " (self)" : "");

    ASSERT_ractor_unlocking(r);
    rb_native_mutex_lock(&r->sync.lock);

#if RACTOR_CHECK_MODE > 0
    if (GET_EC() != NULL) { // GET_EC is NULL in an MJIT worker
        r->sync.locked_by = GET_RACTOR()->self;
    }
#endif

    RUBY_DEBUG_LOG2(file, line, "locked  r:%u%s", r->id, GET_RACTOR() == r ? " (self)" : "");
}

static void
ractor_lock_self(rb_ractor_t *cr, const char *file, int line)
{
    VM_ASSERT(cr == GET_RACTOR());
    VM_ASSERT(cr->sync.locked_by != cr->self);
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

    RUBY_DEBUG_LOG2(file, line, "r:%u%s", r->id, GET_RACTOR() == r ? " (self)" : "");
}

static void
ractor_unlock_self(rb_ractor_t *cr, const char *file, int line)
{
    VM_ASSERT(cr == GET_RACTOR());
    VM_ASSERT(cr->sync.locked_by == cr->self);
    ractor_unlock(cr, file, line);
}

#define RACTOR_LOCK(r) ractor_lock(r, __FILE__, __LINE__)
#define RACTOR_UNLOCK(r) ractor_unlock(r, __FILE__, __LINE__)
#define RACTOR_LOCK_SELF(r) ractor_lock_self(r, __FILE__, __LINE__)
#define RACTOR_UNLOCK_SELF(r) ractor_unlock_self(r, __FILE__, __LINE__)

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
    RUBY_DEBUG_LOG("r:%u [%s]->[%s]", r->id, ractor_status_str(r->status_), ractor_status_str(status));

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
        VM_ASSERT(0); // unreachable
        break;
    }

    r->status_ = status;
}

static bool
ractor_status_p(rb_ractor_t *r, enum ractor_status status)
{
    return rb_ractor_status_p(r, status);
}

static void
ractor_queue_mark(struct rb_ractor_queue *rq)
{
    for (int i=0; i<rq->cnt; i++) {
        int idx = (rq->start + i) % rq->size;
        rb_gc_mark(rq->baskets[idx].v);
        rb_gc_mark(rq->baskets[idx].sender);
    }
}

static void ractor_local_storage_mark(rb_ractor_t *r);
static void ractor_local_storage_free(rb_ractor_t *r);

static void
ractor_mark(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;

    ractor_queue_mark(&r->sync.incoming_queue);
    rb_gc_mark(r->sync.wait.taken_basket.v);
    rb_gc_mark(r->sync.wait.taken_basket.sender);
    rb_gc_mark(r->sync.wait.yielded_basket.v);
    rb_gc_mark(r->sync.wait.yielded_basket.sender);
    rb_gc_mark(r->loc);
    rb_gc_mark(r->name);
    rb_gc_mark(r->r_stdin);
    rb_gc_mark(r->r_stdout);
    rb_gc_mark(r->r_stderr);

    if (r->threads.cnt > 0) {
        rb_thread_t *th = 0;
        list_for_each(&r->threads.set, th, lt_node) {
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
ractor_waiting_list_free(struct rb_ractor_waiting_list *wl)
{
    free(wl->ractors);
}

static void
ractor_free(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;
    rb_native_mutex_destroy(&r->sync.lock);
    rb_native_cond_destroy(&r->sync.cond);
    ractor_queue_free(&r->sync.incoming_queue);
    ractor_waiting_list_free(&r->sync.taking_ractors);
    ractor_local_storage_free(r);
    ruby_xfree(r);
}

static size_t
ractor_queue_memsize(const struct rb_ractor_queue *rq)
{
    return sizeof(struct rb_ractor_basket) * rq->size;
}

static size_t
ractor_waiting_list_memsize(const struct rb_ractor_waiting_list *wl)
{
    return sizeof(rb_ractor_t *) * wl->size;
}

static size_t
ractor_memsize(const void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;

    // TODO
    return sizeof(rb_ractor_t) +
      ractor_queue_memsize(&r->sync.incoming_queue) +
      ractor_waiting_list_memsize(&r->sync.taking_ractors);
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
    // TODO: check
    return r;
}

uint32_t
rb_ractor_id(const rb_ractor_t *g)
{
    return g->id;
}

static uint32_t ractor_last_id;

#if RACTOR_CHECK_MODE > 0
MJIT_FUNC_EXPORTED uint32_t
rb_ractor_current_id(void)
{
    if (GET_THREAD()->ractor == NULL) {
        return 1; // main ractor
    }
    else {
        return GET_RACTOR()->id;
    }
}
#endif

static void
ractor_queue_setup(struct rb_ractor_queue *rq)
{
    rq->size = 2;
    rq->cnt = 0;
    rq->start = 0;
    rq->baskets = malloc(sizeof(struct rb_ractor_basket) * rq->size);
}

static bool
ractor_queue_empty_p(rb_ractor_t *r, struct rb_ractor_queue *rq)
{
    ASSERT_ractor_locking(r);
    return rq->cnt == 0;
}

static bool
ractor_queue_deq(rb_ractor_t *r, struct rb_ractor_queue *rq, struct rb_ractor_basket *basket)
{
    bool b;

    RACTOR_LOCK(r);
    {
        if (!ractor_queue_empty_p(r, rq)) {
            *basket = rq->baskets[rq->start];
            rq->cnt--;
            rq->start = (rq->start + 1) % rq->size;
            b = true;
        }
        else {
            b = false;
        }
    }
    RACTOR_UNLOCK(r);

    return b;
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
    // fprintf(stderr, "%s %p->cnt:%d\n", __func__, rq, rq->cnt);
}

static void
ractor_basket_clear(struct rb_ractor_basket *b)
{
    b->type = basket_type_none;
    b->v = Qfalse;
    b->sender = Qfalse;
}

static VALUE ractor_reset_belonging(VALUE obj); // in this file

static VALUE
ractor_basket_accept(struct rb_ractor_basket *b)
{
    VALUE v;

    switch (b->type) {
      case basket_type_ref:
        VM_ASSERT(rb_ractor_shareable_p(b->v));
        v = b->v;
        break;
      case basket_type_copy:
      case basket_type_move:
      case basket_type_will:
        v = ractor_reset_belonging(b->v);
        break;
      default:
        rb_bug("unreachable");
    }

    if (b->exception) {
        VALUE cause = v;
        VALUE err = rb_exc_new_cstr(rb_eRactorRemoteError, "thrown by remote Ractor.");
        rb_ivar_set(err, rb_intern("@ractor"), b->sender);
        ractor_basket_clear(b);
        rb_ec_setup_exception(NULL, err, cause);
        rb_exc_raise(err);
    }

    ractor_basket_clear(b);
    return v;
}

static VALUE
ractor_try_receive(rb_execution_context_t *ec, rb_ractor_t *r)
{
    struct rb_ractor_queue *rq = &r->sync.incoming_queue;
    struct rb_ractor_basket basket;

    if (ractor_queue_deq(r, rq, &basket) == false) {
        if (r->sync.incoming_port_closed) {
            rb_raise(rb_eRactorClosedError, "The incoming port is already closed");
        }
        else {
            return Qundef;
        }
    }

    return ractor_basket_accept(&basket);
}

static void *
ractor_sleep_wo_gvl(void *ptr)
{
    rb_ractor_t *cr = ptr;
    RACTOR_LOCK_SELF(cr);
    VM_ASSERT(cr->sync.wait.status != wait_none);
    if (cr->sync.wait.wakeup_status == wakeup_none) {
        ractor_cond_wait(cr);
    }
    cr->sync.wait.status = wait_none;
    RACTOR_UNLOCK_SELF(cr);
    return NULL;
}

static void
ractor_sleep_interrupt(void *ptr)
{
    rb_ractor_t *r = ptr;

    RACTOR_LOCK(r);
    if (r->sync.wait.wakeup_status == wakeup_none) {
        r->sync.wait.wakeup_status = wakeup_by_interrupt;
        rb_native_cond_signal(&r->sync.cond);
    }
    RACTOR_UNLOCK(r);
}

#if USE_RUBY_DEBUG_LOG
static const char *
wait_status_str(enum ractor_wait_status wait_status)
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
    rb_bug("unrechable");
}

static const char *
wakeup_status_str(enum ractor_wakeup_status wakeup_status)
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
    rb_bug("unrechable");
}
#endif // USE_RUBY_DEBUG_LOG

static void
ractor_sleep(rb_execution_context_t *ec, rb_ractor_t *cr)
{
    VM_ASSERT(GET_RACTOR() == cr);
    VM_ASSERT(cr->sync.wait.status != wait_none);
    // fprintf(stderr, "%s  r:%p status:%s, wakeup_status:%s\n", __func__, cr,
    //                 wait_status_str(cr->sync.wait.status), wakeup_status_str(cr->sync.wait.wakeup_status));

    RACTOR_UNLOCK(cr);
    rb_nogvl(ractor_sleep_wo_gvl, cr,
             ractor_sleep_interrupt, cr,
             RB_NOGVL_UBF_ASYNC_SAFE);
    RACTOR_LOCK(cr);
}

static bool
ractor_sleeping_by(const rb_ractor_t *r, enum ractor_wait_status wait_status)
{
    return (r->sync.wait.status & wait_status) && r->sync.wait.wakeup_status == wakeup_none;
}

static bool
ractor_wakeup(rb_ractor_t *r, enum ractor_wait_status wait_status, enum ractor_wakeup_status wakeup_status)
{
    ASSERT_ractor_locking(r);

    // fprintf(stderr, "%s r:%p status:%s/%s wakeup_status:%s/%s\n", __func__, r,
    //         wait_status_str(r->sync.wait.status), wait_status_str(wait_status),
    //         wakeup_status_str(r->sync.wait.wakeup_status), wakeup_status_str(wakeup_status));

    if (ractor_sleeping_by(r, wait_status)) {
        r->sync.wait.wakeup_status = wakeup_status;
        rb_native_cond_signal(&r->sync.cond);
        return true;
    }
    else {
        return false;
    }
}

static void
ractor_register_taking(rb_ractor_t *r, rb_ractor_t *cr)
{
    VM_ASSERT(cr == GET_RACTOR());
    bool retry_try = false;

    RACTOR_LOCK(r);
    {
        if (ractor_sleeping_by(r, wait_yielding)) {
            // already waiting for yielding. retry try_take.
            retry_try = true;
        }
        else {
            // insert cr into taking list
            struct rb_ractor_waiting_list *wl = &r->sync.taking_ractors;

            for (int i=0; i<wl->cnt; i++) {
                if (wl->ractors[i] == cr) {
                    // TODO: make it clean code.
                    rb_native_mutex_unlock(&r->sync.lock);
                    rb_raise(rb_eRuntimeError, "Already another thread of same ractor is waiting.");
                }
            }

            if (wl->size == 0) {
                wl->size = 1;
                wl->ractors = malloc(sizeof(rb_ractor_t *) * wl->size);
                if (wl->ractors == NULL) rb_bug("can't allocate buffer");
            }
            else if (wl->size <= wl->cnt + 1) {
                wl->size *= 2;
                wl->ractors = realloc(wl->ractors, sizeof(rb_ractor_t *) * wl->size);
                if (wl->ractors == NULL) rb_bug("can't re-allocate buffer");
            }
            wl->ractors[wl->cnt++] = cr;
        }
    }
    RACTOR_UNLOCK(r);

    if (retry_try) {
        RACTOR_LOCK(cr);
        {
            if (cr->sync.wait.wakeup_status == wakeup_none) {
                VM_ASSERT(cr->sync.wait.status != wait_none);

                cr->sync.wait.wakeup_status = wakeup_by_retry;
                cr->sync.wait.status = wait_none;
            }
        }
        RACTOR_UNLOCK(cr);
    }
}

static void
ractor_waiting_list_del(rb_ractor_t *r, struct rb_ractor_waiting_list *wl, rb_ractor_t *wr)
{
    RACTOR_LOCK(r);
    {
        int pos = -1;
        for (int i=0; i<wl->cnt; i++) {
            if (wl->ractors[i] == wr) {
                pos = i;
                break;
            }
        }
        if (pos >= 0) { // found
            wl->cnt--;
            for (int i=pos; i<wl->cnt; i++) {
                wl->ractors[i] = wl->ractors[i+1];
            }
        }
    }
    RACTOR_UNLOCK(r);
}

static rb_ractor_t *
ractor_waiting_list_shift(rb_ractor_t *r, struct rb_ractor_waiting_list *wl)
{
    ASSERT_ractor_locking(r);
    VM_ASSERT(&r->sync.taking_ractors == wl);

    if (wl->cnt > 0) {
        rb_ractor_t *tr = wl->ractors[0];
        for (int i=1; i<wl->cnt; i++) {
            wl->ractors[i-1] = wl->ractors[i];
        }
        wl->cnt--;
        return tr;
    }
    else {
        return NULL;
    }
}

static VALUE
ractor_receive(rb_execution_context_t *ec, rb_ractor_t *r)
{
    VM_ASSERT(r == rb_ec_ractor_ptr(ec));
    VALUE v;

    while ((v = ractor_try_receive(ec, r)) == Qundef) {
        RACTOR_LOCK(r);
        {
            if (ractor_queue_empty_p(r, &r->sync.incoming_queue)) {
                VM_ASSERT(r->sync.wait.status == wait_none);
                r->sync.wait.status = wait_receiving;
                r->sync.wait.wakeup_status = wakeup_none;

                ractor_sleep(ec, r);

                r->sync.wait.wakeup_status = wakeup_none;
            }
        }
        RACTOR_UNLOCK(r);
    }

    return v;
}

static void
ractor_send_basket(rb_execution_context_t *ec, rb_ractor_t *r, struct rb_ractor_basket *b)
{
    bool closed = false;
    struct rb_ractor_queue *rq = &r->sync.incoming_queue;

    RACTOR_LOCK(r);
    {
        if (r->sync.incoming_port_closed) {
            closed = true;
        }
        else {
            ractor_queue_enq(r, rq, b);
            if (ractor_wakeup(r, wait_receiving, wakeup_by_send)) {
                RUBY_DEBUG_LOG("wakeup", 0);
            }
        }
    }
    RACTOR_UNLOCK(r);

    if (closed) {
        rb_raise(rb_eRactorClosedError, "The incoming-port is already closed");
    }
}

static VALUE ractor_move(VALUE obj); // in this file
static VALUE ractor_copy(VALUE obj); // in this file

static void
ractor_basket_setup(rb_execution_context_t *ec, struct rb_ractor_basket *basket, VALUE obj, VALUE move, bool exc, bool is_will)
{
    basket->sender = rb_ec_ractor_ptr(ec)->self;
    basket->exception = exc;

    if (is_will) {
        basket->type = basket_type_will;
        basket->v = obj;
    }
    else if (rb_ractor_shareable_p(obj)) {
        basket->type = basket_type_ref;
        basket->v = obj;
    }
    else if (!RTEST(move)) {
        basket->v = ractor_copy(obj);
        basket->type = basket_type_copy;
    }
    else {
        basket->type = basket_type_move;
        basket->v = ractor_move(obj);
    }
}

static VALUE
ractor_send(rb_execution_context_t *ec, rb_ractor_t *r, VALUE obj, VALUE move)
{
    struct rb_ractor_basket basket;
    ractor_basket_setup(ec, &basket, obj, move, false, false);
    ractor_send_basket(ec, r, &basket);
    return r->self;
}

static VALUE
ractor_try_take(rb_execution_context_t *ec, rb_ractor_t *r)
{
    struct rb_ractor_basket basket = {
        .type = basket_type_none,
    };
    bool closed = false;

    RACTOR_LOCK(r);
    {
        if (ractor_wakeup(r, wait_yielding, wakeup_by_take)) {
            VM_ASSERT(r->sync.wait.yielded_basket.type != basket_type_none);
            basket = r->sync.wait.yielded_basket;
            ractor_basket_clear(&r->sync.wait.yielded_basket);
        }
        else if (r->sync.outgoing_port_closed) {
            closed = true;
        }
        else {
            // not reached.
        }
    }
    RACTOR_UNLOCK(r);

    if (basket.type == basket_type_none) {
        if (closed) {
            rb_raise(rb_eRactorClosedError, "The outgoing-port is already closed");
        }
        else {
            return Qundef;
        }
    }
    else {
        return ractor_basket_accept(&basket);
    }
}

static bool
ractor_try_yield(rb_execution_context_t *ec, rb_ractor_t *cr, struct rb_ractor_basket *basket)
{
    ASSERT_ractor_unlocking(cr);
    VM_ASSERT(basket->type != basket_type_none);

    if (cr->sync.outgoing_port_closed) {
        rb_raise(rb_eRactorClosedError, "The outgoing-port is already closed");
    }

    rb_ractor_t *r;

  retry_shift:
    RACTOR_LOCK(cr);
    {
        r = ractor_waiting_list_shift(cr, &cr->sync.taking_ractors);
    }
    RACTOR_UNLOCK(cr);

    if (r) {
        bool retry_shift = false;

        RACTOR_LOCK(r);
        {
            if (ractor_wakeup(r, wait_taking, wakeup_by_yield)) {
                VM_ASSERT(r->sync.wait.taken_basket.type == basket_type_none);
                r->sync.wait.taken_basket = *basket;
            }
            else {
                retry_shift = true;
            }
        }
        RACTOR_UNLOCK(r);

        if (retry_shift) {
            // get candidate take-waiting ractor, but already woke up by another reason.
            // retry to check another ractor.
            goto retry_shift;
        }
        else {
            return true;
        }
    }
    else {
        return false;
    }
}

// select(r1, r2, r3, receive: true, yield: obj)
static VALUE
ractor_select(rb_execution_context_t *ec, const VALUE *rs, int alen, VALUE yielded_value, bool move, VALUE *ret_r)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    VALUE crv = cr->self;
    VALUE ret = Qundef;
    int i;
    bool interrupted = false;
    enum ractor_wait_status wait_status = 0;
    bool yield_p = (yielded_value != Qundef) ? true : false;
    const int rs_len = alen;

    struct ractor_select_action {
        enum ractor_select_action_type {
            ractor_select_action_take,
            ractor_select_action_receive,
            ractor_select_action_yield,
        } type;
        VALUE v;
    } *actions = ALLOCA_N(struct ractor_select_action, alen + (yield_p ? 1 : 0));

    VM_ASSERT(cr->sync.wait.status == wait_none);
    VM_ASSERT(cr->sync.wait.wakeup_status == wakeup_none);
    VM_ASSERT(cr->sync.wait.taken_basket.type == basket_type_none);
    VM_ASSERT(cr->sync.wait.yielded_basket.type == basket_type_none);

    // setup actions
    for (i=0; i<alen; i++) {
        VALUE v = rs[i];

        if (v == crv) {
            actions[i].type = ractor_select_action_receive;
            actions[i].v = Qnil;
            wait_status |= wait_receiving;
        }
        else if (rb_ractor_p(v)) {
            actions[i].type = ractor_select_action_take;
            actions[i].v = v;
            wait_status |= wait_taking;
        }
        else {
            rb_raise(rb_eArgError, "should be a ractor object, but %"PRIsVALUE, v);
        }
    }
    rs = NULL;

  restart:

    if (yield_p) {
        actions[rs_len].type = ractor_select_action_yield;
        actions[rs_len].v = Qundef;
        wait_status |= wait_yielding;
        alen++;

        ractor_basket_setup(ec, &cr->sync.wait.yielded_basket, yielded_value, move, false, false);
    }

    // TODO: shuffle actions

    while (1) {
        RUBY_DEBUG_LOG("try actions (%s)", wait_status_str(wait_status));

        for (i=0; i<alen; i++) {
            VALUE v, rv;
            switch (actions[i].type) {
              case ractor_select_action_take:
                rv = actions[i].v;
                v = ractor_try_take(ec, RACTOR_PTR(rv));
                if (v != Qundef) {
                    *ret_r = rv;
                    ret = v;
                    goto cleanup;
                }
                break;
              case ractor_select_action_receive:
                v = ractor_try_receive(ec, cr);
                if (v != Qundef) {
                    *ret_r = ID2SYM(rb_intern("receive"));
                    ret = v;
                    goto cleanup;
                }
                break;
              case ractor_select_action_yield:
                {
                    if (ractor_try_yield(ec, cr, &cr->sync.wait.yielded_basket)) {
                        *ret_r = ID2SYM(rb_intern("yield"));
                        ret = Qnil;
                        goto cleanup;
                    }
                }
                break;
            }
        }

        RUBY_DEBUG_LOG("wait actions (%s)", wait_status_str(wait_status));

        RACTOR_LOCK(cr);
        {
            VM_ASSERT(cr->sync.wait.status == wait_none);
            cr->sync.wait.status = wait_status;
            cr->sync.wait.wakeup_status = wakeup_none;
        }
        RACTOR_UNLOCK(cr);

        // prepare waiting
        for (i=0; i<alen; i++) {
            rb_ractor_t *r;
            switch (actions[i].type) {
              case ractor_select_action_take:
                r = RACTOR_PTR(actions[i].v);
                ractor_register_taking(r, cr);
                break;
              case ractor_select_action_yield:
              case ractor_select_action_receive:
                break;
            }
        }

        // wait
        RACTOR_LOCK(cr);
        {
            if (cr->sync.wait.wakeup_status == wakeup_none) {
                for (i=0; i<alen; i++) {
                    rb_ractor_t *r;

                    switch (actions[i].type) {
                      case ractor_select_action_take:
                        r = RACTOR_PTR(actions[i].v);
                        if (ractor_sleeping_by(r, wait_yielding)) {
                            RUBY_DEBUG_LOG("wakeup_none, but r:%u is waiting for yielding", r->id);
                            cr->sync.wait.wakeup_status = wakeup_by_retry;
                            goto skip_sleep;
                        }
                        break;
                      case ractor_select_action_receive:
                        if (cr->sync.incoming_queue.cnt > 0) {
                            RUBY_DEBUG_LOG("wakeup_none, but incoming_queue has %u messages", cr->sync.incoming_queue.cnt);
                            cr->sync.wait.wakeup_status = wakeup_by_retry;
                            goto skip_sleep;
                        }
                        break;
                      case ractor_select_action_yield:
                        if (cr->sync.taking_ractors.cnt > 0) {
                            RUBY_DEBUG_LOG("wakeup_none, but %u taking_ractors are waiting", cr->sync.taking_ractors.cnt);
                            cr->sync.wait.wakeup_status = wakeup_by_retry;
                            goto skip_sleep;
                        }
                        else if (cr->sync.outgoing_port_closed) {
                            cr->sync.wait.wakeup_status = wakeup_by_close;
                            goto skip_sleep;
                        }
                        break;
                    }
                }

                RUBY_DEBUG_LOG("sleep %s", wait_status_str(cr->sync.wait.status));
                ractor_sleep(ec, cr);
                RUBY_DEBUG_LOG("awaken %s", wakeup_status_str(cr->sync.wait.wakeup_status));
            }
            else {
              skip_sleep:
                RUBY_DEBUG_LOG("no need to sleep %s->%s",
                               wait_status_str(cr->sync.wait.status),
                               wakeup_status_str(cr->sync.wait.wakeup_status));
                cr->sync.wait.status = wait_none;
            }
        }
        RACTOR_UNLOCK(cr);

        // cleanup waiting
        for (i=0; i<alen; i++) {
            rb_ractor_t *r;
            switch (actions[i].type) {
              case ractor_select_action_take:
                r = RACTOR_PTR(actions[i].v);
                ractor_waiting_list_del(r, &r->sync.taking_ractors, cr);
                break;
              case ractor_select_action_receive:
              case ractor_select_action_yield:
                break;
            }
        }

        // check results
        enum ractor_wakeup_status wakeup_status = cr->sync.wait.wakeup_status;
        cr->sync.wait.wakeup_status = wakeup_none;

        switch (wakeup_status) {
          case wakeup_none:
            // OK. something happens.
            // retry loop.
            break;
          case wakeup_by_retry:
            // Retry request.
            break;
          case wakeup_by_send:
            // OK.
            // retry loop and try_receive will succss.
            break;
          case wakeup_by_yield:
            // take was succeeded!
            // cr.wait.taken_basket contains passed block
            VM_ASSERT(cr->sync.wait.taken_basket.type != basket_type_none);
            *ret_r = cr->sync.wait.taken_basket.sender;
            VM_ASSERT(rb_ractor_p(*ret_r));
            ret = ractor_basket_accept(&cr->sync.wait.taken_basket);
            goto cleanup;
          case wakeup_by_take:
            *ret_r = ID2SYM(rb_intern("yield"));
            ret = Qnil;
            goto cleanup;
          case wakeup_by_close:
            // OK.
            // retry loop and will get CloseError.
            break;
          case wakeup_by_interrupt:
            ret = Qundef;
            interrupted = true;
            goto cleanup;
        }
    }

  cleanup:
    RUBY_DEBUG_LOG("cleanup actions (%s)", wait_status_str(wait_status));

    if (cr->sync.wait.yielded_basket.type != basket_type_none) {
        ractor_basket_clear(&cr->sync.wait.yielded_basket);
    }

    VM_ASSERT(cr->sync.wait.status == wait_none);
    VM_ASSERT(cr->sync.wait.wakeup_status == wakeup_none);
    VM_ASSERT(cr->sync.wait.taken_basket.type == basket_type_none);
    VM_ASSERT(cr->sync.wait.yielded_basket.type == basket_type_none);

    if (interrupted) {
        rb_vm_check_ints_blocking(ec);
        interrupted = false;
        goto restart;
    }

    VM_ASSERT(ret != Qundef);
    return ret;
}

static VALUE
ractor_yield(rb_execution_context_t *ec, rb_ractor_t *r, VALUE obj, VALUE move)
{
    VALUE ret_r;
    ractor_select(ec, NULL, 0, obj, RTEST(move) ? true : false, &ret_r);
    return Qnil;
}

static VALUE
ractor_take(rb_execution_context_t *ec, rb_ractor_t *r)
{
    VALUE ret_r;
    VALUE v = ractor_select(ec, &r->self, 1, Qundef, false, &ret_r);
    return v;
}

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
                VM_ASSERT(r->sync.incoming_queue.cnt == 0);
                RUBY_DEBUG_LOG("cancel receiving", 0);
            }
        }
        else {
            prev = Qtrue;
        }
    }
    RACTOR_UNLOCK(r);
    return prev;
}

static VALUE
ractor_close_outgoing(rb_execution_context_t *ec, rb_ractor_t *r)
{
    VALUE prev;

    RACTOR_LOCK(r);
    {
        if (!r->sync.outgoing_port_closed) {
            prev = Qfalse;
            r->sync.outgoing_port_closed = true;
        }
        else {
            prev = Qtrue;
        }

        // wakeup all taking ractors
        rb_ractor_t *taking_ractor;
        while ((taking_ractor = ractor_waiting_list_shift(r, &r->sync.taking_ractors)) != NULL) {
            RACTOR_LOCK(taking_ractor);
            ractor_wakeup(taking_ractor, wait_taking, wakeup_by_close);
            RACTOR_UNLOCK(taking_ractor);
        }

        // raising yielding Ractor
        if (!r->yield_atexit &&
            ractor_wakeup(r, wait_yielding, wakeup_by_close)) {
            RUBY_DEBUG_LOG("cancel yielding", 0);
        }
    }
    RACTOR_UNLOCK(r);
    return prev;
}

// creation/termination

static uint32_t
ractor_next_id(void)
{
    uint32_t id;

    RB_VM_LOCK();
    {
        id = ++ractor_last_id;
    }
    RB_VM_UNLOCK();

    return id;
}

static void
vm_insert_ractor0(rb_vm_t *vm, rb_ractor_t *r, bool single_ractor_mode)
{
    RUBY_DEBUG_LOG("r:%u ractor.cnt:%u++", r->id, vm->ractor.cnt);
    VM_ASSERT(single_ractor_mode || RB_VM_LOCKED_P());

    list_add_tail(&vm->ractor.set, &r->vmlr_node);
    vm->ractor.cnt++;
}

static void
cancel_single_ractor_mode(void)
{
    // enable multi-ractor mode
    RUBY_DEBUG_LOG("enable multi-ractor mode", 0);

    rb_gc_start();
    rb_transient_heap_evacuate();

    if (rb_warning_category_enabled_p(RB_WARN_CATEGORY_EXPERIMENTAL)) {
        rb_warn("Ractor is experimental, and the behavior may change in future versions of Ruby! "
                "Also there are many implementation issues.");
    }

    ruby_single_main_ractor = NULL;
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
        list_del(&cr->vmlr_node);

        if (vm->ractor.cnt <= 2 && vm->ractor.sync.terminate_waiting) {
            rb_native_cond_signal(&vm->ractor.sync.terminate_cond);
        }
        vm->ractor.cnt--;

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
    r->self = rv;
    VM_ASSERT(ractor_status_p(r, ractor_created));
    return rv;
}

rb_ractor_t *
rb_ractor_main_alloc(void)
{
    rb_ractor_t *r = ruby_mimmalloc(sizeof(rb_ractor_t));
    if (r == NULL) {
	fprintf(stderr, "[FATAL] failed to allocate memory for main ractor\n");
        exit(EXIT_FAILURE);
    }
    MEMZERO(r, rb_ractor_t, 1);
    r->id = ++ractor_last_id;
    r->loc = Qnil;
    r->name = Qnil;
    r->self = Qnil;
    ruby_single_main_ractor = r;

    return r;
}

void rb_gvl_init(rb_global_vm_lock_t *gvl);

void
rb_ractor_living_threads_init(rb_ractor_t *r)
{
    list_head_init(&r->threads.set);
    r->threads.cnt = 0;
    r->threads.blocking_cnt = 0;
}

static void
ractor_init(rb_ractor_t *r, VALUE name, VALUE loc)
{
    ractor_queue_setup(&r->sync.incoming_queue);
    rb_native_mutex_initialize(&r->sync.lock);
    rb_native_cond_initialize(&r->sync.cond);
    rb_native_cond_initialize(&r->barrier_wait_cond);

    // thread management
    rb_gvl_init(&r->threads.gvl);
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
    r->self = TypedData_Wrap_Struct(rb_cRactor, &ractor_data_type, r);
    FL_SET_RAW(r->self, RUBY_FL_SHAREABLE);
    ractor_init(r, Qnil, Qnil);
    r->threads.main = th;
    rb_ractor_living_threads_insert(r, th);
}

// io.c
VALUE rb_io_prep_stdin(void);
VALUE rb_io_prep_stdout(void);
VALUE rb_io_prep_stderr(void);

static VALUE
ractor_create(rb_execution_context_t *ec, VALUE self, VALUE loc, VALUE name, VALUE args, VALUE block)
{
    VALUE rv = ractor_alloc(self);
    rb_ractor_t *r = RACTOR_PTR(rv);
    ractor_init(r, name, loc);

    // can block here
    r->id = ractor_next_id();
    RUBY_DEBUG_LOG("r:%u", r->id);

    r->r_stdin = rb_io_prep_stdin();
    r->r_stdout = rb_io_prep_stdout();
    r->r_stderr = rb_io_prep_stderr();

    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    r->verbose = cr->verbose;
    r->debug = cr->debug;

    rb_thread_create_ractor(r, args, block);

    RB_GC_GUARD(rv);
    return rv;
}

static void
ractor_yield_atexit(rb_execution_context_t *ec, rb_ractor_t *cr, VALUE v, bool exc)
{
    if (cr->sync.outgoing_port_closed) {
        return;
    }

    ASSERT_ractor_unlocking(cr);

    struct rb_ractor_basket basket;
    ractor_basket_setup(ec, &basket, v, Qfalse, exc, true);

  retry:
    if (ractor_try_yield(ec, cr, &basket)) {
        // OK.
    }
    else {
        bool retry = false;
        RACTOR_LOCK(cr);
        {
            if (cr->sync.taking_ractors.cnt == 0) {
                cr->sync.wait.yielded_basket = basket;

                VM_ASSERT(cr->sync.wait.status == wait_none);
                cr->sync.wait.status = wait_yielding;
                cr->sync.wait.wakeup_status = wakeup_none;

                VM_ASSERT(cr->yield_atexit == false);
                cr->yield_atexit = true;
            }
            else {
                retry = true; // another ractor is waiting for the yield.
            }
        }
        RACTOR_UNLOCK(cr);

        if (retry) goto retry;
    }
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

VALUE
rb_ractor_self(const rb_ractor_t *r)
{
    return r->self;
}

MJIT_FUNC_EXPORTED bool
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

rb_global_vm_lock_t *
rb_ractor_gvl(rb_ractor_t *r)
{
    return &r->threads.gvl;
}

int
rb_ractor_living_thread_num(const rb_ractor_t *r)
{
    return r->threads.cnt;
}

VALUE
rb_ractor_thread_list(rb_ractor_t *r)
{
    VALUE ary = rb_ary_new();
    rb_thread_t *th = 0;

    RACTOR_LOCK(r);
    list_for_each(&r->threads.set, th, lt_node) {
        switch (th->status) {
          case THREAD_RUNNABLE:
          case THREAD_STOPPED:
          case THREAD_STOPPED_FOREVER:
            rb_ary_push(ary, th->self);
          default:
            break;
        }
    }
    RACTOR_UNLOCK(r);
    return ary;
}

void
rb_ractor_living_threads_insert(rb_ractor_t *r, rb_thread_t *th)
{
    VM_ASSERT(th != NULL);

    RACTOR_LOCK(r);
    {
        RUBY_DEBUG_LOG("r(%d)->threads.cnt:%d++", r->id, r->threads.cnt);
        list_add_tail(&r->threads.set, &th->lt_node);
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
        ASSERT_vm_unlocking();

        RB_VM_LOCK();
        {
            rb_vm_ractor_blocking_cnt_inc(vm, cr, file, line);
        }
        RB_VM_UNLOCK();
    }
}

void
rb_ractor_living_threads_remove(rb_ractor_t *cr, rb_thread_t *th)
{
    VM_ASSERT(cr == GET_RACTOR());
    RUBY_DEBUG_LOG("r->threads.cnt:%d--", cr->threads.cnt);
    ractor_check_blocking(cr, cr->threads.cnt - 1, __FILE__, __LINE__);

    if (cr->threads.cnt == 1) {
        vm_remove_ractor(th->vm, cr);
    }
    else {
        RACTOR_LOCK(cr);
        {
            list_del(&th->lt_node);
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
            RUBY_DEBUG_LOG("killed (%p)", main_th);
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
        list_for_each(&vm->ractor.set, r, vmlr_node) {
            if (r != vm->ractor.main_ractor) {
                rb_ractor_terminate_interrupt_main_thread(r);
            }
        }
    }
}

void
rb_ractor_terminate_all(void)
{
    rb_vm_t *vm = GET_VM();
    rb_ractor_t *cr = vm->ractor.main_ractor;

    VM_ASSERT(cr == GET_RACTOR()); // only main-ractor's main-thread should kick it.

    if (vm->ractor.cnt > 1) {
        RB_VM_LOCK();
        ractor_terminal_interrupt_all(vm); // kill all ractors
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
            rb_vm_cond_timedwait(vm, &vm->ractor.sync.terminate_cond, 1000 /* ms */);
            rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);

            ractor_terminal_interrupt_all(vm);
        }
    }
    RB_VM_UNLOCK();
}

rb_execution_context_t *
rb_vm_main_ractor_ec(rb_vm_t *vm)
{
    return vm->ractor.main_ractor->threads.running_ec;
}

static VALUE
ractor_moved_missing(int argc, VALUE *argv, VALUE self)
{
    rb_raise(rb_eRactorMovedError, "can not send any methods to a moved object");
}

void
Init_Ractor(void)
{
    rb_cRactor = rb_define_class("Ractor", rb_cObject);
    rb_eRactorError       = rb_define_class_under(rb_cRactor, "Error", rb_eRuntimeError);
    rb_eRactorRemoteError = rb_define_class_under(rb_cRactor, "RemoteError", rb_eRactorError);
    rb_eRactorMovedError  = rb_define_class_under(rb_cRactor, "MovedError",  rb_eRactorError);
    rb_eRactorClosedError = rb_define_class_under(rb_cRactor, "ClosedError", rb_eStopIteration);
    rb_eRactorUnsafeError = rb_define_class_under(rb_cRactor, "UnsafeError", rb_eRactorError);

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

    rb_obj_freeze(rb_cRactorMovedObject);
}

void
rb_ractor_dump(void)
{
    rb_vm_t *vm = GET_VM();
    rb_ractor_t *r = 0;

    list_for_each(&vm->ractor.set, r, vmlr_node) {
        if (r != vm->ractor.main_ractor) {
            fprintf(stderr, "r:%u (%s)\n", r->id, ractor_status_str(r->status_));
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
        RB_OBJ_WRITE(cr->self, &cr->r_stdin, in);
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
        RB_OBJ_WRITE(cr->self, &cr->r_stdout, out);
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
        RB_OBJ_WRITE(cr->self, &cr->r_stderr, err);
    }
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
        data->rec = rb_hash_st_table(data->rec_hash);
    }
    return data->rec;
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

    if (UNLIKELY(FL_TEST_RAW(obj, FL_EXIVAR))) {
        struct gen_ivtbl *ivtbl;
        rb_ivar_generic_ivtbl_lookup(obj, &ivtbl);
        for (uint32_t i = 0; i < ivtbl->numiv; i++) {
            VALUE val = ivtbl->ivptr[i];
            if (val != Qundef && obj_traverse_i(val, data)) return 1;
        }
    }

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
        {
            uint32_t len = ROBJECT_NUMIV(obj);
            VALUE *ptr = ROBJECT_IVPTR(obj);

            for (uint32_t i=0; i<len; i++) {
                VALUE val = ptr[i];
                if (val != Qundef && obj_traverse_i(val, data)) return 1;
            }
        }
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
            rb_objspace_reachable_objects_from(obj, obj_traverse_reachable_i, &d);
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
frozen_shareable_p(VALUE obj, bool *made_shareable)
{
    if (!RB_TYPE_P(obj, T_DATA)) {
        return true;
    }
    else if (RTYPEDDATA_P(obj)) {
        const rb_data_type_t *type = RTYPEDDATA_TYPE(obj);
        if (type->flags & RUBY_TYPED_FROZEN_SHAREABLE) {
            return true;
        }
        else if (made_shareable && rb_obj_is_proc(obj)) {
            // special path to make shareable Proc.
            rb_proc_ractor_make_shareable(obj);
            *made_shareable = true;
            VM_ASSERT(RB_OBJ_SHAREABLE_P(obj));
            return false;
        }
    }

    return false;
}

static enum obj_traverse_iterator_result
make_shareable_check_shareable(VALUE obj)
{
    VM_ASSERT(!SPECIAL_CONST_P(obj));
    bool made_shareable = false;

    if (RB_OBJ_SHAREABLE_P(obj)) {
        return traverse_skip;
    }
    else if (!frozen_shareable_p(obj, &made_shareable)) {
        if (made_shareable) {
            return traverse_skip;
        }
        else {
            rb_raise(rb_eRactorError, "can not make shareable object for %"PRIsVALUE, obj);
        }
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
             frozen_shareable_p(obj, NULL)) {
        return traverse_cont;
    }

    return traverse_stop; // fail
}

MJIT_FUNC_EXPORTED bool
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

static struct st_table *
obj_traverse_replace_rec(struct obj_traverse_replace_data *data)
{
    if (UNLIKELY(!data->rec)) {
        data->rec_hash = rb_ident_hash_new();
        data->rec = rb_hash_st_table(data->rec_hash);
    }
    return data->rec;
}

#if USE_TRANSIENT_HEAP
void rb_ary_transient_heap_evacuate(VALUE ary, int promote);
void rb_obj_transient_heap_evacuate(VALUE obj, int promote);
void rb_hash_transient_heap_evacuate(VALUE hash, int promote);
void rb_struct_transient_heap_evacuate(VALUE st, int promote);
#endif

static void
obj_refer_only_shareables_p_i(VALUE obj, void *ptr)
{
    int *pcnt = (int *)ptr;

    if (!rb_ractor_shareable_p(obj)) {
        pcnt++;
    }
}

static int
obj_refer_only_shareables_p(VALUE obj)
{
    int cnt = 0;
    rb_objspace_reachable_objects_from(obj, obj_refer_only_shareables_p_i, &cnt);
    return cnt == 0;
}

static int
obj_traverse_replace_i(VALUE obj, struct obj_traverse_replace_data *data)
{
    VALUE replacement;

    if (RB_SPECIAL_CONST_P(obj)) {
        data->replacement = obj;
        return 0;
    }

    switch (data->enter_func(obj, data)) {
      case traverse_cont: break;
      case traverse_skip: return 0; // skip children
      case traverse_stop: return 1; // stop search
    }

    replacement = data->replacement;

    if (UNLIKELY(st_lookup(obj_traverse_replace_rec(data), (st_data_t)obj, (st_data_t *)&replacement))) {
        data->replacement = replacement;
        return 0;
    }
    else {
        st_insert(obj_traverse_replace_rec(data), (st_data_t)obj, (st_data_t)replacement);
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
        struct gen_ivtbl *ivtbl;
        rb_ivar_generic_ivtbl_lookup(obj, &ivtbl);
        for (uint32_t i = 0; i < ivtbl->numiv; i++) {
            if (ivtbl->ivptr[i] != Qundef) {
                CHECK_AND_REPLACE(ivtbl->ivptr[i]);
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
#if USE_TRANSIENT_HEAP
            if (data->move) rb_obj_transient_heap_evacuate(obj, TRUE);
#endif

            uint32_t len = ROBJECT_NUMIV(obj);
            VALUE *ptr = ROBJECT_IVPTR(obj);

            for (uint32_t i=0; i<len; i++) {
                if (ptr[i] != Qundef) {
                    CHECK_AND_REPLACE(ptr[i]);
                }
            }
        }
        break;

      case T_ARRAY:
        {
            rb_ary_cancel_sharing(obj);
#if USE_TRANSIENT_HEAP
            if (data->move) rb_ary_transient_heap_evacuate(obj, TRUE);
#endif

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
#if USE_TRANSIENT_HEAP
            if (data->move) rb_hash_transient_heap_evacuate(obj, TRUE);
#endif
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
#if USE_TRANSIENT_HEAP
            if (data->move) rb_struct_transient_heap_evacuate(obj, TRUE);
#endif
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

    data->replacement = replacement;

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

struct RVALUE {
    VALUE flags;
    VALUE klass;
    VALUE v1;
    VALUE v2;
    VALUE v3;
};

static const VALUE fl_users = FL_USER1  | FL_USER2  | FL_USER3  |
                              FL_USER4  | FL_USER5  | FL_USER6  | FL_USER7  |
                              FL_USER8  | FL_USER9  | FL_USER10 | FL_USER11 |
                              FL_USER12 | FL_USER13 | FL_USER14 | FL_USER15 |
                              FL_USER16 | FL_USER17 | FL_USER18 | FL_USER19;

static void
ractor_moved_bang(VALUE obj)
{
    // invalidate src object
    struct RVALUE *rv = (void *)obj;

    rv->klass = rb_cRactorMovedObject;
    rv->v1 = 0;
    rv->v2 = 0;
    rv->v3 = 0;
    rv->flags = rv->flags & ~fl_users;

    // TODO: record moved location
}

static enum obj_traverse_iterator_result
move_enter(VALUE obj, struct obj_traverse_replace_data *data)
{
    if (rb_ractor_shareable_p(obj)) {
        data->replacement = obj;
        return traverse_skip;
    }
    else {
        data->replacement = rb_obj_alloc(RBASIC_CLASS(obj));
        return traverse_cont;
    }
}

void rb_replace_generic_ivar(VALUE clone, VALUE obj); // variable.c

static enum obj_traverse_iterator_result
move_leave(VALUE obj, struct obj_traverse_replace_data *data)
{
    VALUE v = data->replacement;
    struct RVALUE *dst = (struct RVALUE *)v;
    struct RVALUE *src = (struct RVALUE *)obj;

    dst->flags = (dst->flags & ~fl_users) | (src->flags & fl_users);

    dst->v1 = src->v1;
    dst->v2 = src->v2;
    dst->v3 = src->v3;

    if (UNLIKELY(FL_TEST_RAW(obj, FL_EXIVAR))) {
        rb_replace_generic_ivar(v, obj);
    }

    // TODO: generic_ivar

    ractor_moved_bang(obj);
    return traverse_cont;
}

static VALUE
ractor_move(VALUE obj)
{
    VALUE val = rb_obj_traverse_replace(obj, move_enter, move_leave, true);
    if (val != Qundef) {
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
    if (val != Qundef) {
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

static void
ractor_local_storage_mark(rb_ractor_t *r)
{
    if (r->local_storage) {
        st_foreach(r->local_storage, ractor_local_storage_mark_i, 0);

        for (int i=0; i<freed_ractor_local_keys.cnt; i++) {
            rb_ractor_local_key_t key = freed_ractor_local_keys.keys[i];
            st_data_t val;
            if (st_delete(r->local_storage, (st_data_t *)&key, &val) &&
                key->type->free) {
                (*key->type->free)((void *)val);
            }
        }
    }
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
        if ((VALUE)key->main_cache != Qundef) {
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
    VALUE val;
    if (ractor_local_ref(key, (void **)&val)) {
        return val;
    }
    else {
        return Qnil;
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

#include "ractor.rbinc"
