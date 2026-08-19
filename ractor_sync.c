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

static VALUE ractor_receive(rb_execution_context_t *ec, const struct ractor_port *rp, const rb_hrtime_t *end);
static VALUE ractor_send(rb_execution_context_t *ec, const struct ractor_port *rp, VALUE obj, VALUE move);
static struct ractor_basket *ractor_basket_new_ref(VALUE shareable);
static void ractor_send_basket(rb_execution_context_t *ec, const struct ractor_port *rp, struct ractor_basket *b, bool raise_on_error);
static void ractor_add_port(rb_ractor_t *r, st_data_t id);

// The off-heap courier a copy or a move payload travels in.  Defined in ractor.c.
struct rb_ractor_courier *rb_ractor_courier_build_move(VALUE obj, struct rb_ractor_courier **slot);
VALUE rb_ractor_courier_materialize(struct rb_ractor_courier *c);
void rb_ractor_courier_free(struct rb_ractor_courier *c);
static void ractor_off_queue_add(rb_ractor_t *cr, struct ractor_basket *b);
static void ractor_off_queue_remove(struct ractor_basket *b);
void rb_ractor_courier_mark(struct rb_ractor_courier *c);
struct rb_ractor_courier *rb_ractor_courier_build_copy(VALUE obj, struct rb_ractor_courier **slot);

static void ractor_port_note_alive(const struct ractor_port *rp);

static void
ractor_port_mark(void *ptr)
{
    const struct ractor_port *rp = (struct ractor_port *)ptr;

    if (rp->r) {
        rb_gc_mark(rp->r->pub.self);

        /* Only a mark that covers every objspace can call a port dead.  Ask the single
         * objspace first: it answers without the VM, which a GC worker thread cannot
         * reach (mmtk marks from several of them). */
        if (rb_gc_single_objspace_p() || rb_gc_during_global_gc_p()) {
            ractor_port_note_alive(rp);
        }
    }
}

static const rb_data_type_t ractor_port_data_type = {
    "ractor/port",
    {
        ractor_port_mark,
        RUBY_TYPED_DEFAULT_FREE,
        NULL, // memsize
        NULL, // update
    },
    0, 0, RUBY_TYPED_THREAD_SAFE_FREE | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FROZEN_SHAREABLE | RUBY_TYPED_EMBEDDABLE,
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
    return RTYPEDDATA_GET_DATA(self);
}

// r is NULL between Ractor::Port.allocate and ractor_port_init()
static struct ractor_port *
ractor_port_ptr_check(VALUE self)
{
    struct ractor_port *rp = RACTOR_PORT_PTR(self);

    if (UNLIKELY(rp->r == NULL)) {
        rb_raise(rb_eTypeError, "uninitialized %"PRIsVALUE, rb_obj_class(self));
    }

    return rp;
}

static VALUE
ractor_port_alloc(VALUE klass)
{
    struct ractor_port *rp;
    VALUE rpv = TypedData_Make_Struct(klass, struct ractor_port, &ractor_port_data_type, rp);
    rb_obj_freeze(rpv);
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

/*
 *  call-seq:
 *    Ractor::Port.new  -> new_port
 *
 *  Returns a new Ractor::Port object.
 */
static VALUE
ractor_port_initialize(VALUE self)
{
    return ractor_port_init(self, GET_RACTOR());
}

/* :nodoc: */
static VALUE
ractor_port_initialize_copy(VALUE self, VALUE orig)
{
    struct ractor_port *dst = RACTOR_PORT_PTR(self); // uninitialized by definition
    struct ractor_port *src = ractor_port_ptr_check(orig);
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

static const rb_hrtime_t *ractor_timeout_deadline(VALUE timeout, rb_hrtime_t *storage);

static VALUE
ractor_port_receive(rb_execution_context_t *ec, VALUE self, VALUE timeout)
{
    const struct ractor_port *rp = ractor_port_ptr_check(self);

    if (rp->r != rb_ec_ractor_ptr(ec)) {
        rb_raise(rb_eRactorError, "only allowed from the creator Ractor of this port");
    }

    rb_hrtime_t deadline;
    const rb_hrtime_t *end = ractor_timeout_deadline(timeout, &deadline);

    VALUE v = ractor_receive(ec, rp, end);
    RB_GC_GUARD(self);

    // no message before the timeout
    return UNDEF_P(v) ? Qnil : v;
}

static VALUE
ractor_port_send(rb_execution_context_t *ec, VALUE self, VALUE obj, VALUE move)
{
    const struct ractor_port *rp = ractor_port_ptr_check(self);
    ractor_send(ec, rp, obj, RTEST(move));
    RB_GC_GUARD(self);
    return self;
}

static bool ractor_closed_port_p(rb_execution_context_t *ec, rb_ractor_t *r, const struct ractor_port *rp);
static bool ractor_close_port(rb_execution_context_t *ec, rb_ractor_t *r, const struct ractor_port *rp);

static VALUE
ractor_port_closed_p(rb_execution_context_t *ec, VALUE self)
{
    const struct ractor_port *rp = ractor_port_ptr_check(self);
    rb_ractor_t *r = rp->r;
    bool closed;

    if (rb_ec_ractor_ptr(ec) == r) {
        /* The owner's threads are serialized by the ractor GVL, so the ports
         * table can't change under this lookup. */
        closed = ractor_closed_port_p(ec, r, rp);
    }
    else {
        /* A foreign Ractor races the owner's st_insert/st_delete on the ports
         * table; take the lock like every other foreign reader. ractor_closed_port_p
         * asserts the lock is held for foreign access, and Port#closed? was the
         * only path reaching it without the lock. */
        RACTOR_LOCK(r);
        {
            closed = ractor_closed_port_p(ec, r, rp);
        }
        RACTOR_UNLOCK(r);
    }

    return closed ? Qtrue : Qfalse;
}

static VALUE
ractor_port_close(rb_execution_context_t *ec, VALUE self)
{
    const struct ractor_port *rp = ractor_port_ptr_check(self);
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
        /* True when v held a type the native copier does not support and became a
         * Marshal byte String.  The receiver rebuilds it with Marshal.load instead
         * of walking it natively. */
        bool marshaled;
        /* The off-heap (xmalloc) courier the payload graph was serialized into.
         * Copy and move both use it; when set, v is unused. */
        struct rb_ractor_courier *courier;
        /* The marshaled bytes of a copy payload, off-heap like the courier.  When
         * set, v is unused: an in-flight payload that is not a GC object needs no
         * in-flight pin, so it never keeps a page of the sender's heap alive. */
        char *mbuf;
        size_t mlen;
    } p; // payload

    struct ccan_list_node node;           /* the port queue it waits on */
    struct ccan_list_node off_queue_node; /* or sync.off_queue_baskets, when on none */
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
    if (b->p.courier != NULL) {
        /* The payload became this Ractor's to root the moment the message was enqueued
         * here: the sender's own roots stop at the send.  Before and after the queue the
         * basket is on its holder's off_queue_baskets instead, so a courier is rooted
         * from the moment it is allocated to the moment it is freed. */
        rb_ractor_courier_mark(b->p.courier);
    }
    else if (b->p.mbuf == NULL) {
        /* Marshaled bytes are off-heap and hold nothing to mark. */
        rb_gc_mark(b->p.v);
    }
}

static void
ractor_basket_free(struct ractor_basket *b)
{
    ractor_off_queue_remove(b);
    ruby_xfree(b->p.mbuf);
    b->p.mbuf = NULL;
    b->p.mlen = 0;
    if (b->p.courier) {
        /* A courier that was never consumed (a queue being torn down, say). */
        rb_ractor_courier_free(b->p.courier);
        b->p.courier = NULL;
    }
    SIZED_FREE(b);
}

static struct ractor_basket *
ractor_basket_alloc(void)
{
    struct ractor_basket *b = ALLOC(struct ractor_basket);

    /* Empty and mark-safe from the start: a basket goes on its holder's in-flight list
     * before it has a payload, so a GC can walk it while it is still being filled. */
    b->type = basket_type_none;
    b->sender = Qnil;
    b->port_id = 0;
    b->p.v = Qnil;
    b->p.exception = false;
    b->p.marshaled = false;
    b->p.courier = NULL;
    b->p.mbuf = NULL;
    b->p.mlen = 0;
    ccan_list_node_init(&b->off_queue_node);

    return b;
}

/* A basket is rooted by whoever holds it: a port queue while it waits there, and its
 * holder's off-queue list while it is being built or materialized. */
static void
ractor_off_queue_add(rb_ractor_t *cr, struct ractor_basket *b)
{
    VM_ASSERT(cr == rb_current_ractor_raw(false));
    ccan_list_add_tail(&cr->sync.off_queue_baskets, &b->off_queue_node);
}

static void
ractor_off_queue_remove(struct ractor_basket *b)
{
    ccan_list_del_init(&b->off_queue_node);
}

static void
ractor_mark_off_queue_baskets(rb_ractor_t *r)
{
    struct ractor_basket *b;
    ccan_list_for_each(&r->sync.off_queue_baskets, b, off_queue_node) {
        ractor_basket_mark(b);
    }
}

// ractor-internal - ractor_queue

struct ractor_queue {
    struct ccan_list_head set;
    bool closed;
    bool alive;  /* its Ractor::Port is still reachable; see the reap below */
};

static void
ractor_queue_init(struct ractor_queue *rq)
{
    ccan_list_head_init(&rq->set);
    rq->closed = false;
    rq->alive = true;
}

static struct ractor_queue *
ractor_queue_new(void)
{
    struct ractor_queue *rq = ALLOC(struct ractor_queue);
    ractor_queue_init(rq);
    return rq;
}

static void
ractor_port_note_alive(const struct ractor_port *rp)
{
    struct ractor_queue *rq;

    if (rp->r->sync.ports && st_lookup(rp->r->sync.ports, rp->id_, (st_data_t *)&rq)) {
        /* Several markers can reach the same port at once (mmtk marks from its GC worker
         * threads), but they all store the same value and the reap reads it once marking
         * is over. */
        rq->alive = true;
    }
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

    SIZED_FREE(rq);
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

    // Rebuilding the table on insertion can run GC by the allocation and the
    // GC acquires the VM lock, which is prohibited under the ractor lock.
    st_table *const old_tab = r->sync.ports;
    bool inserted;

    RACTOR_LOCK(r);
    {
        inserted = st_insert_no_rebuild(old_tab, id, (st_data_t)rq) >= 0;
    }
    RACTOR_UNLOCK(r);

    if (!inserted) {
        // The table is full. Rebuild it outside of the ractor lock (mutators
        // are serialized by the per-ractor GVL) and swap it under the lock
        // to exclude the readers (other ractors).
        st_table *const new_tab = st_copy(old_tab);
        st_insert(new_tab, id, (st_data_t)rq);

        RACTOR_LOCK(r);
        {
            VM_ASSERT(r->sync.ports == old_tab);
            r->sync.ports = new_tab;
        }
        RACTOR_UNLOCK(r);

        st_free_table(old_tab);
    }
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

/* A port is the only way to receive from its queue, so a queue whose port is gone is
 * unreachable -- but the table is keyed by id, so no sweep finds it.  Mark and sweep the
 * table itself: ractor_port_mark sets the flag, this clears it for the next cycle. */
static int
ractor_reap_dead_ports_i(st_data_t port_id, st_data_t val, st_data_t dat)
{
    struct ractor_queue *rq = (struct ractor_queue *)val;

    if (rq->alive) {
        rq->alive = false;
        return ST_CONTINUE;
    }
    else {
        ractor_queue_free(rq);
        return ST_DELETE;
    }
}

void
rb_ractor_reap_dead_ports(rb_ractor_t *r)
{
    if (r->sync.ports) {
        st_foreach(r->sync.ports, ractor_reap_dead_ports_i, 0);
    }
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

/* Mark the Ractors monitoring r.  ractor_notify_exit sends the exit token through each
 * entry's port, so the monitoring Ractor's struct must outlive r, and its wrapper is
 * what keeps it alive. */
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
    const struct ractor_port *rp = ractor_port_ptr_check(port);
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
        SIZED_FREE(rm);
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
    const struct ractor_port *rp = ractor_port_ptr_check(port);

    RACTOR_LOCK(r);
    {
        if (UNDEF_P(r->sync.legacy)) { // not terminated
            struct ractor_monitor *rm, *nxt;

            ccan_list_for_each_safe(&r->sync.monitors, rm, nxt, node) {
                if (rm->port.r == rp->r && ractor_port_id(&rm->port) == ractor_port_id(rp)) {
                    RUBY_DEBUG_LOG("r:%u -> port:%u@r%u",
                                   (unsigned int)rb_ractor_id(r),
                                   (unsigned int)ractor_port_id(&rm->port),
                                   (unsigned int)rb_ractor_id(rm->port.r));
                    ccan_list_del(&rm->node);
                    SIZED_FREE(rm);
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

}

/* Sent after the dying thread's post-mortem collection: waking a joiner any earlier makes
 * ractor_value spin for the whole of that collection. */
static void
ractor_send_exit_tokens(rb_execution_context_t *ec, rb_ractor_t *cr)
{
    VALUE token = ractor_exit_token(cr->sync.legacy_exc);
    struct ractor_monitor *rm, *nxt;

    ccan_list_for_each_safe(&cr->sync.monitors, rm, nxt, node)
    {
        RUBY_DEBUG_LOG("port:%u@r%u", (unsigned int)ractor_port_id(&rm->port), (unsigned int)rb_ractor_id(rm->port.r));

        ractor_send_basket(ec, &rm->port, ractor_basket_new_ref(token), false);

        ccan_list_del(&rm->node);
        SIZED_FREE(rm);
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
    /* The owner rewrites the queues, the port table and the monitor list under its sync
     * lock, so only the owner itself or the stopped world may walk them. */
    const bool world_stopped = rb_gc_during_global_gc_p();
    VM_ASSERT(world_stopped || r == rb_current_ractor_raw(false));

    rb_gc_mark(r->sync.default_port_value);

    /* Until the value is absorbed this is its only reliable root (Qundef while the
     * Ractor still runs); after Ractor#value returns it, the Ruby side roots it. */
    rb_gc_mark(r->sync.legacy);

    /* ractor_sync_init builds the rest, and a root scan reaches the main Ractor before
     * that: ports is what tells the two apart (the lock and the list heads are still
     * zeroed, and walking those crashes).  Lock out foreign senders while walking them
     * (self-lock: not recursive, and a held Ractor lock disables malloc-GC, so no GC
     * nests); a stopped world needs no lock. */
    if (r->sync.ports) {
        if (!world_stopped) RACTOR_LOCK_SELF(r);
        {
            ractor_queue_mark(r->sync.recv_queue);
            st_foreach(r->sync.ports, ractor_mark_ports_i, 0);
            ractor_mark_monitors(r);
        }
        if (!world_stopped) RACTOR_UNLOCK_SELF(r);

        /* The baskets on no queue: one being built to send, one being materialized.
         * Walked in every collection, like the queues.  What they hold is shareable, but
         * "only a global GC frees a shareable" does not hold: pinned_roots_mark, which
         * roots a shareable from its page bit, is skipped once the process is back to a
         * single Ractor (rb_gc_single_objspace_p), and then an ordinary local GC frees
         * one that nothing else names.  A payload in flight is named by its basket and
         * nothing else, so this list has to be a root whenever the queues are.  No sync
         * lock, though: only the owner touches it (the lock above guards the queues,
         * which a foreign sender writes). */
        ractor_mark_off_queue_baskets(r);
    }
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
    if (r->sync.ports) {
        return st_memsize(r->sync.ports);
    }
    else {
        return 0;
    }
}

static void
ractor_sync_init(rb_ractor_t *r)
{
    // lock
    rb_native_mutex_initialize(&r->sync.lock);

    // monitors
    ccan_list_head_init(&r->sync.off_queue_baskets);
    ccan_list_head_init(&r->sync.monitors);

    // waiters
    ccan_list_head_init(&r->sync.waiters);

    // receiving queue
    r->sync.recv_queue = ractor_queue_new();

    // ports
    r->sync.ports = st_init_numtable();
    /* ractor_setup_default_port creates it only after the Ractor joins
     * vm->ractor.set, so a global GC cannot free the rootless port in between. */
    r->sync.default_port_value = Qfalse;

    // legacy
    r->sync.legacy = Qundef;

    // no receive is rebuilding a payload yet

#ifndef RUBY_THREAD_PTHREAD_H
    rb_native_cond_initialize(&r->sync.wakeup_cond);
#endif
}

/* Create the default port.  Call only after the Ractor joined vm->ractor.set, so the
 * root scan can mark the shareable port from creation onwards. */
void
rb_ractor_setup_default_port(rb_ractor_t *r)
{
    VM_ASSERT(r->sync.default_port_value == Qfalse);
    r->sync.default_port_value = ractor_port_new(r);
    FL_SET_RAW(r->sync.default_port_value, RUBY_FL_SHAREABLE); // only default ports are shareable
    rb_gc_obj_became_shareable(r->sync.default_port_value);
}

// Ractor#value

static rb_ractor_t *
ractor_set_successor_once(rb_ractor_t *r, rb_ractor_t *cr)
{
    if (r->sync.successor == NULL) {
        rb_ractor_t *successor = ATOMIC_PTR_CAS(r->sync.successor, NULL, cr);
        return successor == NULL ? cr : successor;
    }

    return r->sync.successor;
}

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
        if (r->sync.legacy_taken) {
            rb_raise(rb_eRactorError, "The value was already taken");
        }

        /* The value is returned by reference: inherit the dead Ractor's objspace first,
         * making it our own object (containment without a copy).  Wait for
         * ractor_terminated: a monitor-port wakeup arrives before the dying thread
         * finishes teardown (vm_remove_ractor still touches the objspace). */
        while (!rb_ractor_status_p(r, ractor_terminated)) {
            rb_thread_schedule();
        }

        /* The wait above yields the GVL, so another thread of this Ractor can take the
         * value first: re-check. */
        if (r->sync.legacy_taken) {
            rb_raise(rb_eRactorError, "The value was already taken");
        }

        /* Move r's rb_gc_register_mark_object pins to the joiner before the merge
         * below sweeps r's objspace, or the objects pinned there lose their root. */
        rb_ractor_absorb_registered_marks(GET_RACTOR(), r);
        rb_ractor_absorb_registered_addrs_without_gc(GET_RACTOR(), r);

        rb_gc_objspace_absorb_into_current(&r->objspace);

        /* Keep legacy alive in a C local until it is returned: after the absorb only
         * the C struct reaches it, so let the conservative machine-stack mark find it. */
        volatile VALUE legacy_keep = r->sync.legacy;

        /* A dead Ractor's local storage is unreachable from Ruby (Ractor#[] only works
         * from inside), so let the values die and keep ractor_mark and ractor_free from
         * walking a stale table later. */
        ractor_local_storage_free(r);
        r->local_storage = NULL;
        r->idkey_local_storage = NULL;

        /* The value is returned to the caller and rooted from Ruby afterwards.  Drop it
         * from the C struct: keeping it would leave a C-only reference into the
         * successor's objspace, needing marking and a pin against compaction. */
        VALUE legacy = r->sync.legacy;
        r->sync.legacy = Qnil;
        r->sync.legacy_taken = true;
        RB_GC_GUARD(legacy_keep);

        if (r->sync.legacy_exc) {
            rb_exc_raise(ractor_make_remote_exception(legacy, self));
        }
        return legacy;
    }
    else {
        rb_raise(rb_eRactorError, "Only the successor ractor can take a value");
    }
}

static VALUE ractor_copy_native_try(VALUE obj); // in ractor.c

static VALUE
ractor_marshal_dump_body(VALUE obj)
{
    return rb_marshal_dump(obj, Qnil);
}

static VALUE
ractor_marshal_dump_rescue(VALUE obj, VALUE errinfo)
{
    rb_raise(rb_eRactorError, "can not copy %"PRIsVALUE" object.", rb_class_of(obj));
    UNREACHABLE_RETURN(Qnil);
}

static VALUE
ractor_prepare_payload(rb_execution_context_t *ec, VALUE obj, enum ractor_basket_type *ptype, bool *pmarshaled,
                       struct rb_ractor_courier **pcourier)
{
    switch (*ptype) {
      case basket_type_ref:
        return obj;
      default:
        if (rb_ractor_shareable_p(obj)) {
            *ptype = basket_type_ref;
            return obj;
        }
        else {
            /* Snapshot the object on the sender side without calling the user-visible
             * #clone.  Both forms are off-heap, so an in-flight payload is never a GC
             * object and needs no pin: nothing of the sender's heap stays alive while
             * the message waits (design_v2.md 4.5).  The courier carries the core
             * types; anything else is marshaled here, so its user hooks run on the
             * sender, and the dump travels as plain bytes. */
            *ptype = basket_type_copy;
            if (rb_ractor_courier_build_copy(obj, pcourier) != NULL) return Qundef;

            *pmarshaled = true;
            return rb_rescue2(ractor_marshal_dump_body, obj,
                              ractor_marshal_dump_rescue, obj,
                              rb_eTypeError, (VALUE)0);
        }
    }
}

#if RBIMPL_COMPILER_IS(GCC) && defined(__OPTIMIZE__)
/* GCC produces false-positive -Wclobbered warnings after inlining
 * this function into ractor_basket_new(). */
NOINLINE(static void ractor_basket_build_payload(rb_execution_context_t *ec, struct ractor_basket *b, VALUE obj, enum ractor_basket_type type, bool exc));
#endif
static void
ractor_basket_build_payload(rb_execution_context_t *ec, struct ractor_basket *b, VALUE obj,
                            enum ractor_basket_type type, bool exc)
{
    b->p.exception = exc;
    if (type == basket_type_move) {
        /* Serialize the graph into an off-heap courier; the sources become
         * RactorMovedObject.  While in flight there is no GC object left for the
         * sender's GC to mark, sweep or move.  The build publishes the courier into
         * the basket as soon as it exists. */
        rb_ractor_courier_build_move(obj, &b->p.courier);
        b->type = type;
        b->p.v = Qfalse;
    }
    else {
        bool marshaled = false;
        VALUE v = ractor_prepare_payload(ec, obj, &type, &marshaled, &b->p.courier);

        if (type == basket_type_copy && marshaled) {
            /* Take the dump off-heap: the sender's copy of it is ordinary garbage
             * from here, so nothing of its heap is held while the message waits. */
            size_t mlen = (size_t)RSTRING_LEN(v);
            char *mbuf = ALLOC_N(char, mlen > 0 ? mlen : 1);
            b->p.marshaled = marshaled;
            b->p.mbuf = mbuf;
            b->p.mlen = mlen;
            memcpy(mbuf, RSTRING_PTR(v), mlen);
            v = Qundef;
        }
        b->type = type;
        b->p.v = v;
    }
}

static struct ractor_basket *
ractor_basket_new(rb_execution_context_t *ec, VALUE obj, enum ractor_basket_type type, bool exc)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    /* Allocate and list the basket before anything is built into it: from here the
     * courier it is about to hold is rooted by this Ractor's in-flight list, even
     * half-built, and every raise below frees it through one path. */
    struct ractor_basket *b = ractor_basket_alloc();
    ractor_off_queue_add(cr, b);

    enum ruby_tag_type state;
    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        ractor_basket_build_payload(ec, b, obj, type, exc);
    }
    EC_POP_TAG();
    if (state != TAG_NONE) {
        ractor_basket_free(b);   /* leaves the list and frees a courier already built */
        EC_JUMP_TAG(ec, state);
    }

    return b;
}

static VALUE
ractor_basket_value(struct ractor_basket *b)
{
    switch (b->type) {
      case basket_type_ref:
        break;
      case basket_type_copy: {
        /* An off-heap copy courier rebuilds exactly like a move one; only the sources
         * differ (still alive here, already shells there). */
        if (b->p.courier != NULL) goto materialize_courier;
        /* The payload is the marshaled bytes.  Marshal.load allocates through this
         * Ractor's normal newobj and write-barrier paths, and can raise (load hooks and
         * autoload run user code, an async interrupt can arrive anywhere), so it runs
         * under a TAG. */
        rb_execution_context_t *ec = rb_current_ec_noinline();
        VALUE result = Qundef;
        enum ruby_tag_type state;
        EC_PUSH_TAG(ec);
        if ((state = EC_EXEC_TAG()) == TAG_NONE) {
            /* Rebuild the byte string in this Ractor's objspace.  Marshal does not mark
             * its source (mark_load_arg) and the basket is off the queue, so this
             * frame's stack slot is the String's only root for the load. */
            VALUE bin = rb_str_new(b->p.mbuf, (long)b->p.mlen);
            result = rb_marshal_load(bin);
            RB_GC_GUARD(bin);
        }
        EC_POP_TAG();
        /* rb_copy_generic_ivar left the sender-resident snapshot host and fields_obj in
         * this EC's gen_fields_cache; the snapshot is garbage on the sender now, and a
         * stale cache hit on a reused address would deref a freed foreign fields_obj.
         * Invalidate (the raise path resets it the same way). */
        ec->gen_fields_cache.obj = Qundef;
        ec->gen_fields_cache.fields_obj = Qundef;
        if (state != TAG_NONE) {
            /* The basket left the queue and has no other owner, and a raise skips
             * accept, so free it here before propagating. */
            ractor_basket_free(b);
            EC_JUMP_TAG(ec, state);
        }
        /* keep rooting result from the stack after the frame is popped */
        b->p.v = result;
        RB_GC_GUARD(result);
        break;
      }
      case basket_type_move:
      materialize_courier: {
        /* Rebuild the moved graph from the off-heap courier into this Ractor's
         * objspace.  The sources are already RactorMovedObject (set when the courier
         * was built), so move's snapshot semantics hold.  The courier is xmalloc'd
         * rather than a GC object, so the sender's concurrent local GC never touches
         * it; the shareable VALUEs it carries are marked through this basket, which is
         * on this Ractor's off-queue list until it is freed.
         *
         * Rebuilding can raise here too (rb_hash_aset on a moved key with a custom
         * #hash runs user code, and an async interrupt can arrive).  On a raise the
         * courier is still owned by the basket, whose teardown frees it. */
        rb_execution_context_t *ec = rb_current_ec_noinline();
        struct rb_ractor_courier *courier = b->p.courier;
        /* Keep the materialized graph on the machine stack (result): it is the only
         * root until it reaches the caller.  courier_free below runs a long loop, and
         * only the malloc'd basket's p.v holding it would give a concurrent global GC a
         * wide window. */
        VALUE result = Qundef;
        enum ruby_tag_type state;
        EC_PUSH_TAG(ec);
        if ((state = EC_EXEC_TAG()) == TAG_NONE) {
            result = rb_ractor_courier_materialize(courier);
        }
        EC_POP_TAG();
        if (state != TAG_NONE) {
            /* An unconsumed courier stays in b->p.courier; basket_free frees it. */
            ractor_basket_free(b);
            EC_JUMP_TAG(ec, state);
        }
        rb_ractor_courier_free(courier);
        b->p.courier = NULL;
        b->p.v = result;
        RB_GC_GUARD(result);
        break;
      }
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

// Ractor blocking by receive

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
ractor_cond_wait(rb_ractor_t *r, const rb_hrtime_t *end)
{
#if RACTOR_CHECK_MODE > 0
    VALUE locked_by = r->sync.locked_by;
    r->sync.locked_by = Qnil;
#endif
    if (end) {
        rb_hrtime_t now = rb_hrtime_now();
        rb_hrtime_t rel = *end > now ? *end - now : 0;
        // the condvar takes msec: never round a live timeout down to 0
        unsigned long msec = (unsigned long)(rel / RB_HRTIME_PER_MSEC);
        rb_native_cond_timedwait(&r->sync.wakeup_cond, &r->sync.lock, msec > 0 ? msec : 1);
    }
    else {
        rb_native_cond_wait(&r->sync.wakeup_cond, &r->sync.lock);
    }

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
        if (waiter->wakeup_status == wakeup_none) {
            ractor_cond_wait(cr, waiter->end);
        }
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
    // ractor lock is acquired
    rb_native_cond_broadcast(&r->sync.wakeup_cond);
}
#endif

static bool
ractor_wakeup_all(rb_ractor_t *r, enum ractor_wakeup_status wakeup_status)
{
    ASSERT_ractor_unlocking(r);

    RUBY_DEBUG_LOG("r:%u wakeup:%s", rb_ractor_id(r), wakeup_status_str(wakeup_status));

    bool wakeup_p = false;

    RACTOR_LOCK(r);
    while (1) {
        struct ractor_waiter *waiter = ccan_list_pop(&r->sync.waiters, struct ractor_waiter, node);

        if (waiter) {
            VM_ASSERT(waiter->wakeup_status == wakeup_none);

            waiter->wakeup_status = wakeup_status;
            rb_ractor_sched_wakeup(r, waiter->th);

            wakeup_p = true;
        }
        else {
            break;
        }
    }
    RACTOR_UNLOCK(r);

    return wakeup_p;
}

static void
ubf_ractor_wait(void *ptr)
{
    struct ractor_waiter *waiter = (struct ractor_waiter *)ptr;

    rb_thread_t *th = waiter->th;
    rb_ractor_t *r = th->ractor;
    rb_atomic_t event_serial = waiter->event_serial;

    // clear ubf and nobody can kick UBF
    th->unblock.func = NULL;
    th->unblock.arg  = NULL;

    rb_native_mutex_unlock(&th->interrupt_lock);
    {
        RACTOR_LOCK(r);
        {
            if (RUBY_ATOMIC_LOAD(th->unblock.event_serial) == event_serial && waiter->wakeup_status == wakeup_none) {
                RUBY_DEBUG_LOG("waiter:%p", (void *)waiter);

                waiter->wakeup_status = wakeup_by_interrupt;
                ccan_list_del(&waiter->node);

                rb_ractor_sched_wakeup(r, waiter->th);
            }
        }
        RACTOR_UNLOCK(r);
    }
    rb_native_mutex_lock(&th->interrupt_lock);
}

// Waits for an event on cr.  `end` is an absolute deadline, NULL to wait forever.
static enum ractor_wakeup_status
ractor_wait(rb_execution_context_t *ec, rb_ractor_t *cr, const rb_hrtime_t *end)
{
    rb_thread_t *th = rb_ec_thread_ptr(ec);

    struct ractor_waiter waiter = {
        .wakeup_status = wakeup_none,
        .th = th,
        .end = end,
    };

    RUBY_DEBUG_LOG("wait%s", "");

    ASSERT_ractor_locking(cr);

    VM_ASSERT(GET_RACTOR() == cr);
    VM_ASSERT(!ractor_waiter_included(cr, th));

    ccan_list_add_tail(&cr->sync.waiters, &waiter.node);

    // resume another ready thread and wait for an event
    rb_ractor_sched_wait(ec, cr, ubf_ractor_wait, &waiter);

    if (waiter.wakeup_status == wakeup_none) {
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

// Returns false if the deadline `end` passed with nothing to deliver.  Incoming
// messages are delivered even then, so the caller retries its queue once more.
static bool
ractor_wait_receive(rb_execution_context_t *ec, rb_ractor_t *cr, const rb_hrtime_t *end)
{
    struct ractor_queue messages;
    bool deliverred = false;
    bool timedout = false;

    RACTOR_LOCK_SELF(cr);
    {
        if (ractor_check_received(cr, &messages)) {
            deliverred = true;
        }
        else if (!end) {
            ractor_wait(ec, cr, NULL); // no timeout: wait until a message arrives
        }
        else if (*end == 0) {
            timedout = true; // `timeout: 0`: over without reading any clock
        }
        else {
            // only a wakeup nobody claimed can be the deadline, so only then look at
            // the clock: a send or an interrupt says what woke this thread by itself
            timedout = ractor_wait(ec, cr, end) == wakeup_none && rb_hrtime_now() >= *end;
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

    return !timedout;
}

static VALUE
ractor_try_receive(rb_execution_context_t *ec, rb_ractor_t *cr, const struct ractor_port *rp)
{
    struct ractor_queue *rq = ractor_get_queue(cr, ractor_port_id(rp), false);

    if (rq == NULL) {
        rb_raise(rb_eRactorClosedError, "The port was already closed");
    }

    struct ractor_basket *b = ractor_queue_deq(cr, rq);
    /* Off the queue and not yet freed: this Ractor roots it while it materializes. */
    if (b) ractor_off_queue_add(cr, b);

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

// Returns Qundef if the deadline passed first.  It bounds how long this blocks; it
// does not cut delivery off.  A message that lands while the timeout is being
// reported is still returned, as Thread::Queue#pop(timeout:) does.  Either way
// nothing is lost: a basket only leaves the queue when it is returned.
static VALUE
ractor_receive(rb_execution_context_t *ec, const struct ractor_port *rp, const rb_hrtime_t *end)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    VM_ASSERT(cr == rp->r);

    RUBY_DEBUG_LOG("port:%u", (unsigned int)ractor_port_id(rp));

    while (1) {
        VALUE v = ractor_try_receive(ec, cr, rp);

        if (v != Qundef) {
            return v;
        }
        else if (!ractor_wait_receive(ec, cr, end)) {
            return Qundef;
        }
    }
}

// A timeout argument becomes an absolute deadline, or 0 for `timeout: 0`, which
// every wait reads as "do not wait".  Returns NULL when there is no timeout.
static const rb_hrtime_t *
ractor_timeout_deadline(VALUE timeout, rb_hrtime_t *storage)
{
    if (NIL_P(timeout)) return NULL;

    if (!(FIXNUM_P(timeout) && FIX2LONG(timeout) == 0)) {
        struct timeval tv = rb_time_interval(timeout); // raises on a negative timeout
        rb_hrtime_t rel = rb_timeval2hrtime(&tv);

        if (rel > 0) {
            *storage = rb_hrtime_add(rb_hrtime_now(), rel);
            return storage;
        }
    }

    *storage = 0;
    return storage;
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
            /* The receiver's queue roots it from here; drop it from ours. */
            ractor_off_queue_remove(b);
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

        /* Nothing took the basket: it was not enqueued, so free it whether or not the
         * caller wants the error raised. */
        ractor_basket_free(b);

        if (raise_on_error) {
            rb_raise(rb_eRactorClosedError, "The port was already closed");
        }
    }
}

/* A shareable payload needs no preparation, so this skips the tag ractor_basket_new
 * pushes.  The exit tokens travel this way: they are sent from a thread whose EC has
 * already lost its VM stack, and EC_PUSH_TAG reads ec->cfp under ZJIT. */
static struct ractor_basket *
ractor_basket_new_ref(VALUE shareable)
{
    struct ractor_basket *b = ractor_basket_alloc();

    b->type = basket_type_ref;
    b->sender = Qnil;
    b->p.v = shareable;
    b->p.exception = false;
    b->p.marshaled = false;
    b->p.courier = NULL;
    b->p.mbuf = NULL;
    b->p.mlen = 0;

    return b;
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

// Ractor::Selector

struct ractor_selector {
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
    SIZED_FREE(s);
}

static size_t
ractor_selector_memsize(const void *ptr)
{
    const struct ractor_selector *s = ptr;
    size_t size = sizeof(struct ractor_selector);
    if (s->ports) {
        size += st_memsize(s->ports);
    }
    return size;
}

static const rb_data_type_t ractor_selector_data_type = {
    "ractor/selector",
    {
        ractor_selector_mark,
        ractor_selector_free,
        ractor_selector_memsize,
        NULL, // update
    },
    0, 0, RUBY_TYPED_THREAD_SAFE_FREE | RUBY_TYPED_WB_PROTECTED,
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
    const struct ractor_port *rp = ractor_port_ptr_check(rpv);

    if (st_lookup(s->ports, (st_data_t)rpv, NULL)) {
        rb_raise(rb_eArgError, "already added");
    }

    st_insert(s->ports, (st_data_t)rpv, (st_data_t)rp);
    RB_OBJ_WRITTEN(selv, Qundef, rpv);

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
ractor_selector__wait(rb_execution_context_t *ec, VALUE selector, const rb_hrtime_t *end)
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
        else if (!ractor_wait_receive(ec, cr, end)) {
            return Qnil;
        }
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
    return ractor_selector__wait(GET_EC(), selector, NULL);
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
ractor_select_internal(rb_execution_context_t *ec, VALUE self, VALUE ports, VALUE timeout)
{
    rb_hrtime_t deadline;
    const rb_hrtime_t *end = ractor_timeout_deadline(timeout, &deadline);

    VALUE selector = ractor_selector_new(RARRAY_LENINT(ports), (VALUE *)RARRAY_CONST_PTR(ports), rb_cRactorSelector);
    VALUE result = ractor_selector__wait(ec, selector, end);

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
    rb_define_method(rb_cRactorPort, "initialize", ractor_port_initialize, 0);
    rb_define_method(rb_cRactorPort, "initialize_copy", ractor_port_initialize_copy, 1);

#if USE_RACTOR_SELECTOR
    rb_init_ractor_selector();
#endif
}
