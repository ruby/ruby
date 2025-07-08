
// this file is included by ractor.c

struct ractor_port {
    rb_ractor_t *r;
    st_data_t id_;
};

static st_data_t
ractor_port_id(const struct ractor_port *rp)
{
    return rp->id_;
}

static VALUE rb_cRactorPort;

static VALUE ractor_receive(rb_execution_context_t *ec, const struct ractor_port *rp);
static VALUE ractor_send(rb_execution_context_t *ec, const struct ractor_port *rp, VALUE obj, VALUE move);
static VALUE ractor_try_send(rb_execution_context_t *ec, const struct ractor_port *rp, VALUE obj, VALUE move);
static void ractor_add_port(rb_ractor_t *r, st_data_t id);

static void
ractor_port_mark(void *ptr)
{
    const struct ractor_port *rp = (struct ractor_port *)ptr;

    if (rp->r) {
        rb_gc_mark(rp->r->pub.self);
    }
}

static void
ractor_port_free(void *ptr)
{
    xfree(ptr);
}

static size_t
ractor_port_memsize(const void *ptr)
{
    return sizeof(struct ractor_port);
}

static const rb_data_type_t ractor_port_data_type = {
    "ractor/port",
    {
        ractor_port_mark,
        ractor_port_free,
        ractor_port_memsize,
        NULL, // update
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};

static st_data_t
ractor_genid_for_port(rb_ractor_t *cr)
{
    // TODO: enough?
    return cr->sync.next_port_id++;
}

static struct ractor_port *
RACTOR_PORT_PTR(VALUE self)
{
    VM_ASSERT(rb_typeddata_is_kind_of(self, &ractor_port_data_type));
    struct ractor_port *rp = DATA_PTR(self);
    return rp;
}

static VALUE
ractor_port_alloc(VALUE klass)
{
    struct ractor_port *rp;
    VALUE rpv = TypedData_Make_Struct(klass, struct ractor_port, &ractor_port_data_type, rp);
    return rpv;
}

static VALUE
ractor_port_init(VALUE rpv, rb_ractor_t *r)
{
    struct ractor_port *rp = RACTOR_PORT_PTR(rpv);

    rp->r = r;
    RB_OBJ_WRITTEN(rpv, Qundef, r->pub.self);
    rp->id_ = ractor_genid_for_port(r);

    ractor_add_port(r, ractor_port_id(rp));

    rb_obj_freeze(rpv);

    return rpv;
}

static VALUE
ractor_port_initialzie(VALUE self)
{
    return ractor_port_init(self, GET_RACTOR());
}

static VALUE
ractor_port_initialzie_copy(VALUE self, VALUE orig)
{
    struct ractor_port *dst = RACTOR_PORT_PTR(self);
    struct ractor_port *src = RACTOR_PORT_PTR(orig);
    dst->r = src->r;
    RB_OBJ_WRITTEN(self, Qundef, dst->r->pub.self);
    dst->id_ = ractor_port_id(src);

    return self;
}

static VALUE
ractor_port_new(rb_ractor_t *r)
{
    VALUE rpv = ractor_port_alloc(rb_cRactorPort);
    ractor_port_init(rpv, r);
    return rpv;
}

static bool
ractor_port_p(VALUE self)
{
    return rb_typeddata_is_kind_of(self, &ractor_port_data_type);
}

static VALUE
ractor_port_receive(rb_execution_context_t *ec, VALUE self)
{
    const struct ractor_port *rp = RACTOR_PORT_PTR(self);

    if (rp->r != rb_ec_ractor_ptr(ec)) {
        rb_raise(rb_eRactorError, "only allowed from the creator Ractor of this port");
    }

    return ractor_receive(ec, rp);
}

static VALUE
ractor_port_send(rb_execution_context_t *ec, VALUE self, VALUE obj, VALUE move)
{
    const struct ractor_port *rp = RACTOR_PORT_PTR(self);
    ractor_send(ec, rp, obj, RTEST(move));
    return self;
}

static bool ractor_closed_port_p(rb_execution_context_t *ec, rb_ractor_t *r, const struct ractor_port *rp);
static bool ractor_close_port(rb_execution_context_t *ec, rb_ractor_t *r, const struct ractor_port *rp);

static VALUE
ractor_port_closed_p(rb_execution_context_t *ec, VALUE self)
{
    const struct ractor_port *rp = RACTOR_PORT_PTR(self);

    if (ractor_closed_port_p(ec, rp->r, rp)) {
        return Qtrue;
    }
    else {
        return Qfalse;
    }
}

static VALUE
ractor_port_close(rb_execution_context_t *ec, VALUE self)
{
    const struct ractor_port *rp = RACTOR_PORT_PTR(self);
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);

    if (cr != rp->r) {
        rb_raise(rb_eRactorError, "closing port by other ractors is not allowed");
    }

    ractor_close_port(ec, cr, rp);
    return self;
}

// ractor-internal

// ractor-internal - ractor_basket

enum ractor_basket_type {
    // basket is empty
    basket_type_none,

    // value is available
    basket_type_ref,
    basket_type_copy,
    basket_type_move,
};

struct ractor_basket {
    enum ractor_basket_type type;
    VALUE sender;
    st_data_t port_id;

    struct {
        VALUE v;
        bool exception;
    } p; // payload

    struct ccan_list_node node;
};

#if 0
static inline bool
ractor_basket_type_p(const struct ractor_basket *b, enum ractor_basket_type type)
{
    return b->type == type;
}

static inline bool
ractor_basket_none_p(const struct ractor_basket *b)
{
    return ractor_basket_type_p(b, basket_type_none);
}
#endif

static void
ractor_basket_mark(const struct ractor_basket *b)
{
    rb_gc_mark(b->p.v);
}

static void
ractor_basket_free(struct ractor_basket *b)
{
    xfree(b);
}

static struct ractor_basket *
ractor_basket_alloc(void)
{
    struct ractor_basket *b = ALLOC(struct ractor_basket);
    return b;
}

// ractor-internal - ractor_queue

struct ractor_queue {
    struct ccan_list_head set;
    bool closed;
};

static void
ractor_queue_init(struct ractor_queue *rq)
{
    ccan_list_head_init(&rq->set);
    rq->closed = false;
}

static struct ractor_queue *
ractor_queue_new(void)
{
    struct ractor_queue *rq = ALLOC(struct ractor_queue);
    ractor_queue_init(rq);
    return rq;
}

static void
ractor_queue_mark(const struct ractor_queue *rq)
{
    const struct ractor_basket *b;

    ccan_list_for_each(&rq->set, b, node) {
        ractor_basket_mark(b);
    }
}

static void
ractor_queue_free(struct ractor_queue *rq)
{
    struct ractor_basket *b, *nxt;

    ccan_list_for_each_safe(&rq->set, b, nxt, node) {
        ccan_list_del_init(&b->node);
        ractor_basket_free(b);
    }

    VM_ASSERT(ccan_list_empty(&rq->set));

    xfree(rq);
}

RBIMPL_ATTR_MAYBE_UNUSED()
static size_t
ractor_queue_size(const struct ractor_queue *rq)
{
    size_t size = 0;
    const struct ractor_basket *b;

    ccan_list_for_each(&rq->set, b, node) {
        size++;
    }
    return size;
}

static void
ractor_queue_close(struct ractor_queue *rq)
{
    rq->closed = true;
}

static void
ractor_queue_move(struct ractor_queue *dst_rq, struct ractor_queue *src_rq)
{
    struct ccan_list_head *src = &src_rq->set;
    struct ccan_list_head *dst = &dst_rq->set;

    dst->n.next = src->n.next;
    dst->n.prev = src->n.prev;
    dst->n.next->prev = &dst->n;
    dst->n.prev->next = &dst->n;
    ccan_list_head_init(src);
}

#if 0
static struct ractor_basket *
ractor_queue_head(rb_ractor_t *r, struct ractor_queue *rq)
{
    return ccan_list_top(&rq->set, struct ractor_basket, node);
}
#endif

static bool
ractor_queue_empty_p(rb_ractor_t *r, const struct ractor_queue *rq)
{
    return ccan_list_empty(&rq->set);
}

static struct ractor_basket *
ractor_queue_deq(rb_ractor_t *r, struct ractor_queue *rq)
{
    VM_ASSERT(GET_RACTOR() == r);

    return ccan_list_pop(&rq->set, struct ractor_basket, node);
}

static void
ractor_queue_enq(rb_ractor_t *r, struct ractor_queue *rq, struct ractor_basket *basket)
{
    ccan_list_add_tail(&rq->set, &basket->node);
}

#if 0
static void
rq_dump(const struct ractor_queue *rq)
{
    int i=0;
    struct ractor_basket *b;
    ccan_list_for_each(&rq->set, b, node) {
        fprintf(stderr, "%d type:%s %p\n", i, basket_type_name(b->type), (void *)b);
        i++;
    }
}
#endif

static void ractor_delete_port(rb_ractor_t *cr, st_data_t id, bool locked);

static struct ractor_queue *
ractor_get_queue(rb_ractor_t *cr, st_data_t id, bool locked)
{
    VM_ASSERT(cr == GET_RACTOR());

    struct ractor_queue *rq;

    if (cr->sync.ports && st_lookup(cr->sync.ports, id, (st_data_t *)&rq)) {
        if (rq->closed && ractor_queue_empty_p(cr, rq)) {
            ractor_delete_port(cr, id, locked);
            return NULL;
        }
        else {
            return rq;
        }
    }
    else {
        return NULL;
    }
}

// ractor-internal - ports

static void
ractor_add_port(rb_ractor_t *r, st_data_t id)
{
    struct ractor_queue *rq = ractor_queue_new();
    ASSERT_ractor_unlocking(r);

    RUBY_DEBUG_LOG("id:%u", (unsigned int)id);

    RACTOR_LOCK(r);
    {
        // memo: can cause GC, but GC doesn't use ractor locking.
        st_insert(r->sync.ports, id, (st_data_t)rq);
    }
    RACTOR_UNLOCK(r);
}

static void
ractor_delete_port_locked(rb_ractor_t *cr, st_data_t id)
{
    ASSERT_ractor_locking(cr);

    RUBY_DEBUG_LOG("id:%u", (unsigned int)id);

    struct ractor_queue *rq;

    if (st_delete(cr->sync.ports, &id, (st_data_t *)&rq)) {
        ractor_queue_free(rq);
    }
    else {
        VM_ASSERT(0);
    }
}

static void
ractor_delete_port(rb_ractor_t *cr, st_data_t id, bool locked)
{
    if (locked) {
        ractor_delete_port_locked(cr, id);
    }
    else {
        RACTOR_LOCK_SELF(cr);
        {
            ractor_delete_port_locked(cr, id);
        }
        RACTOR_UNLOCK_SELF(cr);
    }
}

static const struct ractor_port *
ractor_default_port(rb_ractor_t *r)
{
    return RACTOR_PORT_PTR(r->sync.default_port_value);
}

static VALUE
ractor_default_port_value(rb_ractor_t *r)
{
    return r->sync.default_port_value;
}

static bool
ractor_closed_port_p(rb_execution_context_t *ec, rb_ractor_t *r, const struct ractor_port *rp)
{
    VM_ASSERT(rb_ec_ractor_ptr(ec) == rp->r ? 1 : (ASSERT_ractor_locking(rp->r), 1));

    const struct ractor_queue *rq;

    if (rp->r->sync.ports && st_lookup(rp->r->sync.ports, ractor_port_id(rp), (st_data_t *)&rq)) {
        return rq->closed;
    }
    else {
        return true;
    }
}

static void ractor_deliver_incoming_messages(rb_execution_context_t *ec, rb_ractor_t *cr);
static bool ractor_queue_empty_p(rb_ractor_t *r, const struct ractor_queue *rq);

static bool
ractor_close_port(rb_execution_context_t *ec, rb_ractor_t *cr, const struct ractor_port *rp)
{
    VM_ASSERT(cr == rp->r);
    struct ractor_queue *rq = NULL;

    RACTOR_LOCK_SELF(cr);
    {
        ractor_deliver_incoming_messages(ec, cr); // check incoming messages

        if (st_lookup(rp->r->sync.ports, ractor_port_id(rp), (st_data_t *)&rq)) {
            ractor_queue_close(rq);

            if (ractor_queue_empty_p(cr, rq)) {
                // delete from the table
                ractor_delete_port(cr, ractor_port_id(rp), true);
            }

            // TODO: free rq
        }
    }
    RACTOR_UNLOCK_SELF(cr);

    return rq != NULL;
}

static int
ractor_free_all_ports_i(st_data_t port_id, st_data_t val, st_data_t dat)
{
    struct ractor_queue *rq = (struct ractor_queue *)val;
    // rb_ractor_t *cr = (rb_ractor_t *)dat;

    ractor_queue_free(rq);
    return ST_CONTINUE;
}

static void
ractor_free_all_ports(rb_ractor_t *cr)
{
    if (cr->sync.ports) {
        st_foreach(cr->sync.ports, ractor_free_all_ports_i, (st_data_t)cr);
        st_free_table(cr->sync.ports);
        cr->sync.ports = NULL;
    }

    if (cr->sync.recv_queue) {
        ractor_queue_free(cr->sync.recv_queue);
        cr->sync.recv_queue = NULL;
    }
}

#if defined(HAVE_WORKING_FORK)
static void
ractor_sync_terminate_atfork(rb_vm_t *vm, rb_ractor_t *r)
{
    ractor_free_all_ports(r);
    r->sync.legacy = Qnil;
}
#endif

// Ractor#monitor

struct ractor_monitor {
    struct ractor_port port;
    struct ccan_list_node node;
};

static void
ractor_mark_monitors(rb_ractor_t *r)
{
    const struct ractor_monitor *rm;
    ccan_list_for_each(&r->sync.monitors, rm, node) {
        rb_gc_mark(rm->port.r->pub.self);
    }
}

static VALUE
ractor_exit_token(bool exc)
{
    if (exc) {
        RUBY_DEBUG_LOG("aborted");
        return ID2SYM(idAborted);
    }
    else {
        RUBY_DEBUG_LOG("exited");
        return ID2SYM(idExited);
    }
}

static VALUE
ractor_monitor(rb_execution_context_t *ec, VALUE self, VALUE port)
{
    rb_ractor_t *r = RACTOR_PTR(self);
    bool terminated = false;
    const struct ractor_port *rp = RACTOR_PORT_PTR(port);
    struct ractor_monitor *rm = ALLOC(struct ractor_monitor);
    rm->port = *rp; // copy port information

    RACTOR_LOCK(r);
    {
        if (UNDEF_P(r->sync.legacy)) { // not terminated
            RUBY_DEBUG_LOG("OK/r:%u -> port:%u@r%u", (unsigned int)rb_ractor_id(r), (unsigned int)ractor_port_id(&rm->port), (unsigned int)rb_ractor_id(rm->port.r));
            ccan_list_add_tail(&r->sync.monitors, &rm->node);
        }
        else {
            RUBY_DEBUG_LOG("NG/r:%u -> port:%u@r%u", (unsigned int)rb_ractor_id(r), (unsigned int)ractor_port_id(&rm->port), (unsigned int)rb_ractor_id(rm->port.r));
            terminated = true;
        }
    }
    RACTOR_UNLOCK(r);

    if (terminated) {
        xfree(rm);
        ractor_port_send(ec, port, ractor_exit_token(r->sync.legacy_exc), Qfalse);

        return Qfalse;
    }
    else {
        return Qtrue;
    }
}

static VALUE
ractor_unmonitor(rb_execution_context_t *ec, VALUE self, VALUE port)
{
    rb_ractor_t *r = RACTOR_PTR(self);
    const struct ractor_port *rp = RACTOR_PORT_PTR(port);

    RACTOR_LOCK(r);
    {
        if (UNDEF_P(r->sync.legacy)) { // not terminated
            struct ractor_monitor *rm, *nxt;

            ccan_list_for_each_safe(&r->sync.monitors, rm, nxt, node) {
                if (ractor_port_id(&rm->port) == ractor_port_id(rp)) {
                    RUBY_DEBUG_LOG("r:%u -> port:%u@r%u",
                                   (unsigned int)rb_ractor_id(r),
                                   (unsigned int)ractor_port_id(&rm->port),
                                   (unsigned int)rb_ractor_id(rm->port.r));
                    ccan_list_del(&rm->node);
                    xfree(rm);
                }
            }
        }
    }
    RACTOR_UNLOCK(r);

    return self;
}

static void
ractor_notify_exit(rb_execution_context_t *ec, rb_ractor_t *cr, VALUE legacy, bool exc)
{
    RUBY_DEBUG_LOG("exc:%d", exc);
    VM_ASSERT(!UNDEF_P(legacy));
    VM_ASSERT(cr->sync.legacy == Qundef);

    RACTOR_LOCK_SELF(cr);
    {
        ractor_free_all_ports(cr);

        cr->sync.legacy = legacy;
        cr->sync.legacy_exc = exc;
    }
    RACTOR_UNLOCK_SELF(cr);

    // send token

    VALUE token = ractor_exit_token(exc);
    struct ractor_monitor *rm, *nxt;

    ccan_list_for_each_safe(&cr->sync.monitors, rm, nxt, node)
    {
        RUBY_DEBUG_LOG("port:%u@r%u", (unsigned int)ractor_port_id(&rm->port), (unsigned int)rb_ractor_id(rm->port.r));

        ractor_try_send(ec, &rm->port, token, false);

        ccan_list_del(&rm->node);
        xfree(rm);
    }

    VM_ASSERT(ccan_list_empty(&cr->sync.monitors));
}

// ractor-internal - initialize, mark, free, memsize

static int
ractor_mark_ports_i(st_data_t key, st_data_t val, st_data_t data)
{
    // id -> ractor_queue
    const struct ractor_queue *rq = (struct ractor_queue *)val;
    ractor_queue_mark(rq);
    return ST_CONTINUE;
}

static void
ractor_sync_mark(rb_ractor_t *r)
{
    rb_gc_mark(r->sync.default_port_value);

    if (r->sync.ports) {
        ractor_queue_mark(r->sync.recv_queue);
        st_foreach(r->sync.ports, ractor_mark_ports_i, 0);
    }

    ractor_mark_monitors(r);
}

static int
ractor_sync_free_ports_i(st_data_t _key, st_data_t val, st_data_t _args)
{
    struct ractor_queue *queue = (struct ractor_queue *)val;

    ractor_queue_free(queue);

    return ST_CONTINUE;
}

static void
ractor_sync_free(rb_ractor_t *r)
{
    if (r->sync.recv_queue) {
        ractor_queue_free(r->sync.recv_queue);
    }

    // maybe NULL
    if (r->sync.ports) {
        st_foreach(r->sync.ports, ractor_sync_free_ports_i, 0);
        st_free_table(r->sync.ports);
        r->sync.ports = NULL;
    }
}

static size_t
ractor_sync_memsize(const rb_ractor_t *r)
{
    return st_table_size(r->sync.ports);
}

static void
ractor_sync_init(rb_ractor_t *r)
{
    // lock
    rb_native_mutex_initialize(&r->sync.lock);

    // monitors
    ccan_list_head_init(&r->sync.monitors);

    // waiters
    ccan_list_head_init(&r->sync.waiters);

    // receiving queue
    r->sync.recv_queue = ractor_queue_new();

    // ports
    r->sync.ports = st_init_numtable();
    r->sync.default_port_value = ractor_port_new(r);
    FL_SET_RAW(r->sync.default_port_value, RUBY_FL_SHAREABLE); // only default ports are shareable

    // legacy
    r->sync.legacy = Qundef;

#ifndef RUBY_THREAD_PTHREAD_H
    rb_native_cond_initialize(&r->sync.wakeup_cond);
#endif
}

// Ractor#value

static rb_ractor_t *
ractor_set_successor_once(rb_ractor_t *r, rb_ractor_t *cr)
{
    if (r->sync.successor == NULL) {
        RACTOR_LOCK(r);
        {
            if (r->sync.successor != NULL) {
                // already `value`ed
            }
            else {
                r->sync.successor = cr;
            }
        }
        RACTOR_UNLOCK(r);
    }

    VM_ASSERT(r->sync.successor != NULL);

    return r->sync.successor;
}

static VALUE ractor_reset_belonging(VALUE obj);

static VALUE
ractor_make_remote_exception(VALUE cause, VALUE sender)
{
    VALUE err = rb_exc_new_cstr(rb_eRactorRemoteError, "thrown by remote Ractor.");
    rb_ivar_set(err, rb_intern("@ractor"), sender);
    rb_ec_setup_exception(NULL, err, cause);
    return err;
}

static VALUE
ractor_value(rb_execution_context_t *ec, VALUE self)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    rb_ractor_t *r = RACTOR_PTR(self);
    rb_ractor_t *sr = ractor_set_successor_once(r, cr);

    if (sr == cr) {
        ractor_reset_belonging(r->sync.legacy);

        if (r->sync.legacy_exc) {
            rb_exc_raise(ractor_make_remote_exception(r->sync.legacy, self));
        }
        return r->sync.legacy;
    }
    else {
        rb_raise(rb_eRactorError, "Only the successor ractor can take a value");
    }
}

static VALUE ractor_move(VALUE obj); // in this file
static VALUE ractor_copy(VALUE obj); // in this file

static VALUE
ractor_prepare_payload(rb_execution_context_t *ec, VALUE obj, enum ractor_basket_type *ptype)
{
    switch (*ptype) {
      case basket_type_ref:
        return obj;
      case basket_type_move:
        return ractor_move(obj);
      default:
        if (rb_ractor_shareable_p(obj)) {
            *ptype = basket_type_ref;
            return obj;
        }
        else {
            *ptype = basket_type_copy;
            return ractor_copy(obj);
        }
    }
}

static struct ractor_basket *
ractor_basket_new(rb_execution_context_t *ec, VALUE obj, enum ractor_basket_type type, bool exc)
{
    VALUE v = ractor_prepare_payload(ec, obj, &type);

    struct ractor_basket *b = ractor_basket_alloc();
    b->type = type;
    b->p.v = v;
    b->p.exception = exc;
    return b;
}

static VALUE
ractor_basket_value(struct ractor_basket *b)
{
    switch (b->type) {
      case basket_type_ref:
        break;
      case basket_type_copy:
      case basket_type_move:
        ractor_reset_belonging(b->p.v);
        break;
      default:
        VM_ASSERT(0); // unreachable
    }

    VM_ASSERT(!RB_TYPE_P(b->p.v, T_NONE));
    return b->p.v;
}

static VALUE
ractor_basket_accept(struct ractor_basket *b)
{
    VALUE v = ractor_basket_value(b);

    if (b->p.exception) {
        VALUE err = ractor_make_remote_exception(v, b->sender);
        ractor_basket_free(b);
        rb_exc_raise(err);
    }

    ractor_basket_free(b);
    return v;
}

#if VM_CHECK_MODE > 0
static bool
ractor_waiter_included(rb_ractor_t *cr, rb_thread_t *th)
{
    ASSERT_ractor_locking(cr);

    struct ractor_waiter *w;

    ccan_list_for_each(&cr->sync.waiters, w, node) {
        if (w->th == th) {
            return true;
        }
    }

    return false;
}
#endif

#if USE_RUBY_DEBUG_LOG

static const char *
wakeup_status_str(enum ractor_wakeup_status wakeup_status)
{
    switch (wakeup_status) {
      case wakeup_none: return "none";
      case wakeup_by_send: return "by_send";
      case wakeup_by_interrupt: return "by_interrupt";
      case wakeup_invalid: return "wakeup_invalid";
      // case wakeup_by_close: return "by_close";
    }
    rb_bug("unreachable");
}

static const char *
basket_type_name(enum ractor_basket_type type)
{
    switch (type) {
      case basket_type_none: return  "none";
      case basket_type_ref: return "ref";
      case basket_type_copy: return "copy";
      case basket_type_move: return "move";
    }
    VM_ASSERT(0);
    return NULL;
}

#endif // USE_RUBY_DEBUG_LOG

#ifdef RUBY_THREAD_PTHREAD_H

//

#else // win32

static void
ractor_cond_wait(rb_ractor_t *r)
{
#if RACTOR_CHECK_MODE > 0
    VALUE locked_by = r->sync.locked_by;
    VM_ASSERT(locked_by && locked_by != Qnil);
    r->sync.locked_by = Qnil;
#endif
    rb_native_cond_wait(&r->sync.wakeup_cond, &r->sync.lock);

#if RACTOR_CHECK_MODE > 0
    r->sync.locked_by = locked_by;
#endif
}

static void *
ractor_wait_no_gvl(void *ptr)
{
    struct ractor_waiter *waiter = (struct ractor_waiter *)ptr;
    rb_ractor_t *cr = waiter->th->ractor;

    RACTOR_LOCK_SELF(cr);
    {
        waiter->wakeup_status = wakeup_none;
        ccan_list_add_tail(&cr->sync.waiters, &waiter->node);
        ractor_cond_wait(cr);
    }
    RACTOR_UNLOCK_SELF(cr);
    return NULL;
}

static void
rb_ractor_sched_wait(rb_execution_context_t *ec, rb_ractor_t *cr, rb_unblock_function_t *ubf, void *ptr)
{
    struct ractor_waiter *waiter = (struct ractor_waiter *)ptr;

    RACTOR_UNLOCK(cr);
    {
        rb_nogvl(ractor_wait_no_gvl, waiter,
                 ubf, waiter,
                 RB_NOGVL_UBF_ASYNC_SAFE | RB_NOGVL_INTR_FAIL);
    }
    RACTOR_LOCK(cr);
}

static void
rb_ractor_sched_wakeup(rb_ractor_t *r, rb_thread_t *th)
{
    RACTOR_LOCK(r);
    {
        rb_native_cond_signal(&r->sync.wakeup_cond);
    }
    RACTOR_UNLOCK(r);
}
#endif

static void
ractor_wakeup_all(rb_ractor_t *r, enum ractor_wakeup_status wakeup_status)
{
    ASSERT_ractor_unlocking(r);

    RUBY_DEBUG_LOG("r:%u wakeup:%s", rb_ractor_id(r), wakeup_status_str(wakeup_status));

    struct ractor_waiter *waiter;
    rb_thread_t *th;
    do  {
        RACTOR_LOCK(r);
        {
            waiter = ccan_list_pop(&r->sync.waiters, struct ractor_waiter, node);

            if (waiter) {
                VM_ASSERT(waiter->wakeup_status == wakeup_none);
                waiter->wakeup_status = wakeup_status;
                th = waiter->th;
            }
        }
        RACTOR_UNLOCK(r);
        if (waiter) rb_ractor_sched_wakeup(r, th);
    } while (waiter);
}

static void
ubf_ractor_wait(void *ptr)
{
    struct ractor_waiter *waiter = (struct ractor_waiter *)ptr;

    rb_thread_t *th = waiter->th;
    rb_ractor_t *r = th->ractor;

    // clear ubf and nobody can kick UBF
    th->unblock.func = NULL;
    th->unblock.arg  = NULL;

    rb_native_mutex_unlock(&th->interrupt_lock);
    {
        bool should_wake = false;
        RACTOR_LOCK(r);
        {
            if (waiter->wakeup_status == wakeup_none) {
                RUBY_DEBUG_LOG("waiter:%p", (void *)waiter);

                waiter->wakeup_status = wakeup_by_interrupt;
                ccan_list_del(&waiter->node);
                should_wake = true;
            }
        }
        RACTOR_UNLOCK(r);

        if (should_wake) {
            rb_ractor_sched_wakeup(r, th);
        }
    }
    rb_native_mutex_lock(&th->interrupt_lock);
}

static enum ractor_wakeup_status
ractor_wait(rb_execution_context_t *ec, rb_ractor_t *cr)
{
    rb_thread_t *th = rb_ec_thread_ptr(ec);

    struct ractor_waiter waiter = {
        .wakeup_status = wakeup_invalid,
        .th = th,
    };

    RUBY_DEBUG_LOG("wait%s", "");

    ASSERT_ractor_locking(cr);

    VM_ASSERT(GET_RACTOR() == cr);
    VM_ASSERT(!ractor_waiter_included(cr, th));

    // resume another ready thread and wait for an event
    rb_ractor_sched_wait(ec, cr, ubf_ractor_wait, &waiter);

    if (waiter.wakeup_status == wakeup_none) { // ex: rb_nogvl failed due to interrupt
        ccan_list_del(&waiter.node);
    }

    RUBY_DEBUG_LOG("wakeup_status:%s", wakeup_status_str(waiter.wakeup_status));

    RACTOR_UNLOCK_SELF(cr);
    {
        rb_ec_check_ints(ec);
    }
    RACTOR_LOCK_SELF(cr);

    VM_ASSERT(!ractor_waiter_included(cr, th));
    return waiter.wakeup_status;
}

static void
ractor_deliver_incoming_messages(rb_execution_context_t *ec, rb_ractor_t *cr)
{
    ASSERT_ractor_locking(cr);
    struct ractor_queue *recv_q = cr->sync.recv_queue;

    struct ractor_basket *b;
    while ((b = ractor_queue_deq(cr, recv_q)) != NULL) {
        ractor_queue_enq(cr, ractor_get_queue(cr, b->port_id, true), b);
    }
}

static bool
ractor_check_received(rb_ractor_t *cr, struct ractor_queue *messages)
{
    struct ractor_queue *received_queue = cr->sync.recv_queue;
    bool received = false;

    ASSERT_ractor_locking(cr);

    if (ractor_queue_empty_p(cr, received_queue)) {
        RUBY_DEBUG_LOG("empty");
    }
    else {
        received = true;

        // messages <- incoming
        ractor_queue_init(messages);
        ractor_queue_move(messages, received_queue);
    }

    VM_ASSERT(ractor_queue_empty_p(cr, received_queue));

    RUBY_DEBUG_LOG("received:%d", received);
    return received;
}

static void
ractor_wait_receive(rb_execution_context_t *ec, rb_ractor_t *cr)
{
    struct ractor_queue messages;
    bool deliverred = false;

    RACTOR_LOCK_SELF(cr);
    {
        if (ractor_check_received(cr, &messages)) {
            deliverred = true;
        }
        else {
            ractor_wait(ec, cr);
        }
    }
    RACTOR_UNLOCK_SELF(cr);

    if (deliverred) {
        VM_ASSERT(!ractor_queue_empty_p(cr, &messages));
        struct ractor_basket *b;

        while ((b = ractor_queue_deq(cr, &messages)) != NULL) {
            ractor_queue_enq(cr, ractor_get_queue(cr, b->port_id, false), b);
        }
    }
}

static VALUE
ractor_try_receive(rb_execution_context_t *ec, rb_ractor_t *cr, const struct ractor_port *rp)
{
    struct ractor_queue *rq = ractor_get_queue(cr, ractor_port_id(rp), false);

    if (rq == NULL) {
        rb_raise(rb_eRactorClosedError, "The port was already closed");
    }

    struct ractor_basket *b = ractor_queue_deq(cr, rq);

    if (rq->closed && ractor_queue_empty_p(cr, rq)) {
        ractor_delete_port(cr, ractor_port_id(rp), false);
    }

    if (b) {
        return ractor_basket_accept(b);
    }
    else {
        return Qundef;
    }
}

static VALUE
ractor_receive(rb_execution_context_t *ec, const struct ractor_port *rp)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    VM_ASSERT(cr == rp->r);

    RUBY_DEBUG_LOG("port:%u", (unsigned int)ractor_port_id(rp));

    while (1) {
        VALUE v = ractor_try_receive(ec, cr, rp);

        if (v != Qundef) {
            return v;
        }
        else {
            ractor_wait_receive(ec, cr);
        }
    }
}

// Ractor#send

static void
ractor_send_basket(rb_execution_context_t *ec, const struct ractor_port *rp, struct ractor_basket *b, bool raise_on_error)
{
    bool closed = false;

    RUBY_DEBUG_LOG("port:%u@r%u b:%s v:%p", (unsigned int)ractor_port_id(rp), rb_ractor_id(rp->r), basket_type_name(b->type), (void *)b->p.v);

    RACTOR_LOCK(rp->r);
    {
        if (ractor_closed_port_p(ec, rp->r, rp)) {
            closed = true;
        }
        else {
            b->port_id = ractor_port_id(rp);
            ractor_queue_enq(rp->r, rp->r->sync.recv_queue, b);
        }
    }
    RACTOR_UNLOCK(rp->r);

    // NOTE: ref r -> b->p.v is created, but Ractor is unprotected object, so no problem on that.

    if (!closed) {
        ractor_wakeup_all(rp->r, wakeup_by_send);
    }
    else {
        RUBY_DEBUG_LOG("closed:%u@r%u", (unsigned int)ractor_port_id(rp), rb_ractor_id(rp->r));

        if (raise_on_error) {
            ractor_basket_free(b);
            rb_raise(rb_eRactorClosedError, "The port was already closed");
        }
    }
}

static VALUE
ractor_send0(rb_execution_context_t *ec, const struct ractor_port *rp, VALUE obj, VALUE move, bool raise_on_error)
{
    struct ractor_basket *b = ractor_basket_new(ec, obj, RTEST(move) ? basket_type_move : basket_type_none, false);
    ractor_send_basket(ec, rp, b, raise_on_error);
    RB_GC_GUARD(obj);
    return rp->r->pub.self;
}

static VALUE
ractor_send(rb_execution_context_t *ec, const struct ractor_port *rp, VALUE obj, VALUE move)
{
    return ractor_send0(ec, rp, obj, move, true);
}

static VALUE
ractor_try_send(rb_execution_context_t *ec, const struct ractor_port *rp, VALUE obj, VALUE move)
{
    return ractor_send0(ec, rp, obj, move, false);
}

// Ractor::Selector

struct ractor_selector {
    rb_ractor_t *r;
    struct st_table *ports; // rpv -> rp

};

static int
ractor_selector_mark_i(st_data_t key, st_data_t val, st_data_t dmy)
{
    rb_gc_mark((VALUE)key); // rpv

    return ST_CONTINUE;
}

static void
ractor_selector_mark(void *ptr)
{
    struct ractor_selector *s = ptr;

    if (s->ports) {
        st_foreach(s->ports, ractor_selector_mark_i, 0);
    }
}

static void
ractor_selector_free(void *ptr)
{
    struct ractor_selector *s = ptr;
    st_free_table(s->ports);
    ruby_xfree(ptr);
}

static size_t
ractor_selector_memsize(const void *ptr)
{
    const struct ractor_selector *s = ptr;
    return sizeof(struct ractor_selector) + st_memsize(s->ports);
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

static struct ractor_selector *
RACTOR_SELECTOR_PTR(VALUE selv)
{
    VM_ASSERT(rb_typeddata_is_kind_of(selv, &ractor_selector_data_type));
    return (struct ractor_selector *)DATA_PTR(selv);
}

// Ractor::Selector.new

static VALUE
ractor_selector_create(VALUE klass)
{
    struct ractor_selector *s;
    VALUE selv = TypedData_Make_Struct(klass, struct ractor_selector, &ractor_selector_data_type, s);
    s->ports = st_init_numtable(); // TODO
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
ractor_selector_add(VALUE selv, VALUE rpv)
{
    if (!ractor_port_p(rpv)) {
        rb_raise(rb_eArgError, "Not a Ractor::Port object");
    }

    struct ractor_selector *s = RACTOR_SELECTOR_PTR(selv);
    const struct ractor_port *rp = RACTOR_PORT_PTR(rpv);

    if (st_lookup(s->ports, (st_data_t)rpv, NULL)) {
        rb_raise(rb_eArgError, "already added");
    }

    st_insert(s->ports, (st_data_t)rpv, (st_data_t)rp);
    return selv;
}

// Ractor::Selector#remove(r)

/* call-seq:
 *   remove(ractor) -> ractor
 *
 * Removes _ractor_ from +self+.  Raises an exception if _ractor_ is not added.
 * Returns the removed _ractor_.
 */
static VALUE
ractor_selector_remove(VALUE selv, VALUE rpv)
{
    if (!ractor_port_p(rpv)) {
        rb_raise(rb_eArgError, "Not a Ractor::Port object");
    }

    struct ractor_selector *s = RACTOR_SELECTOR_PTR(selv);

    if (!st_lookup(s->ports, (st_data_t)rpv, NULL)) {
        rb_raise(rb_eArgError, "not added yet");
    }

    st_delete(s->ports, (st_data_t *)&rpv, NULL);

    return selv;
}

// Ractor::Selector#clear

/*
 * call-seq:
 *   clear -> self
 *
 * Removes all ractors from +self+.  Raises +self+.
 */
static VALUE
ractor_selector_clear(VALUE selv)
{
    struct ractor_selector *s = RACTOR_SELECTOR_PTR(selv);
    st_clear(s->ports);
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
    struct ractor_selector *s = RACTOR_SELECTOR_PTR(selv);
    return s->ports->num_entries == 0 ? Qtrue : Qfalse;
}

// Ractor::Selector#wait

struct ractor_selector_wait_data {
    rb_ractor_t *cr;
    rb_execution_context_t *ec;
    bool found;
    VALUE v;
    VALUE rpv;
};

static int
ractor_selector_wait_i(st_data_t key, st_data_t val, st_data_t data)
{
    struct ractor_selector_wait_data *p = (struct ractor_selector_wait_data *)data;
    const struct ractor_port *rp = (const struct ractor_port *)val;

    VALUE v = ractor_try_receive(p->ec, p->cr, rp);

    if (v != Qundef) {
        p->found = true;
        p->v = v;
        p->rpv = (VALUE)key;
        return ST_STOP;
    }
    else {
        return ST_CONTINUE;
    }
}

static VALUE
ractor_selector__wait(rb_execution_context_t *ec, VALUE selector)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    struct ractor_selector *s = RACTOR_SELECTOR_PTR(selector);

    struct ractor_selector_wait_data data = {
        .ec = ec,
        .cr = cr,
        .found = false,
    };

    while (1) {
        st_foreach(s->ports, ractor_selector_wait_i, (st_data_t)&data);

        if (data.found) {
            return rb_ary_new_from_args(2, data.rpv, data.v);
        }

        ractor_wait_receive(ec, cr);
    }
}

/*
 * call-seq:
 *  wait(receive: false, yield_value: undef, move: false) -> [ractor, value]
 *
 * Waits until any ractor in _selector_ can be active.
 */
static VALUE
ractor_selector_wait(VALUE selector)
{
    return ractor_selector__wait(GET_EC(), selector);
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
ractor_select_internal(rb_execution_context_t *ec, VALUE self, VALUE ports)
{
    VALUE selector = ractor_selector_new(RARRAY_LENINT(ports), (VALUE *)RARRAY_CONST_PTR(ports), rb_cRactorSelector);
    VALUE result = ractor_selector__wait(ec, selector);

    RB_GC_GUARD(selector);
    RB_GC_GUARD(ports);
    return result;
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
    rb_define_method(rb_cRactorSelector, "wait", ractor_selector_wait, 0);
}

static void
Init_RactorPort(void)
{
    rb_cRactorPort = rb_define_class_under(rb_cRactor, "Port", rb_cObject);
    rb_define_alloc_func(rb_cRactorPort, ractor_port_alloc);
    rb_define_method(rb_cRactorPort, "initialize", ractor_port_initialzie, 0);
    rb_define_method(rb_cRactorPort, "initialize_copy", ractor_port_initialzie_copy, 1);

#if USE_RACTOR_SELECTOR
    rb_init_ractor_selector();
#endif
}
