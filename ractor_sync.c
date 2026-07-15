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

// off-heap な move 用 courier。実体は ractor.c にある。
struct rb_ractor_move_courier *ractor_move_courier_build(VALUE obj);
VALUE ractor_move_courier_materialize(struct rb_ractor_move_courier *c);
void ractor_move_courier_free(struct rb_ractor_move_courier *c);
void ractor_move_courier_mark(struct rb_ractor_move_courier *c);

static void
ractor_port_mark(void *ptr)
{
    const struct ractor_port *rp = (struct ractor_port *)ptr;

    if (rp->r) {
        rb_gc_mark(rp->r->pub.self);
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

    VALUE v = ractor_receive(ec, rp);
    RB_GC_GUARD(self);
    return v;
}

static VALUE
ractor_port_send(rb_execution_context_t *ec, VALUE self, VALUE obj, VALUE move)
{
    const struct ractor_port *rp = RACTOR_PORT_PTR(self);
    ractor_send(ec, rp, obj, RTEST(move));
    RB_GC_GUARD(self);
    return self;
}

static bool ractor_closed_port_p(rb_execution_context_t *ec, rb_ractor_t *r, const struct ractor_port *rp);
static bool ractor_close_port(rb_execution_context_t *ec, rb_ractor_t *r, const struct ractor_port *rp);

static VALUE
ractor_port_closed_p(rb_execution_context_t *ec, VALUE self)
{
    const struct ractor_port *rp = RACTOR_PORT_PTR(self);
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
        /* v が native copier 非対応の型を含み Marshal バイト列 String に
         * なった場合 true。受信側は native 走査でなく Marshal.load で復元する。 */
        bool marshaled;
        /* basket_type_move 用の off-heap（xmalloc）courier。move basket では v は未使用。 */
        struct rb_ractor_move_courier *move_courier;
        /* native copy snapshot の generic-ivar 対応表 {snapshot host -> fields_obj}。
         * 送信時に構築し受信側 materialize が引く（sender の per-Ractor 表を跨がないため）。
         * 値は snapshot と共に sender objspace で pin され生きるので別途 mark 不要。
         * 対応表が無い（generic ivar 無し / marshaled / move）ときは NULL。 */
        struct st_table *gen_fields;
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
    if (b->type == basket_type_move) {
        /* courier は off-heap。運んでいる shareable な VALUE だけを mark する。 */
        ractor_move_courier_mark(b->p.move_courier);
    }
    else {
        rb_gc_mark(b->p.v);
    }
}

static void
ractor_basket_free(struct ractor_basket *b)
{
    if (b->type == basket_type_move && b->p.move_courier) {
        /* 未消費の move courier（例: queue の破棄途中）。 */
        ractor_move_courier_free(b->p.move_courier);
        b->p.move_courier = NULL;
    }
    else if (b->type != basket_type_move && b->p.gen_fields) {
        /* native copy の generic-ivar 対応表（st は raw malloc）。 */
        st_free_table(b->p.gen_fields);
        b->p.gen_fields = NULL;
    }
    SIZED_FREE(b);
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

    RACTOR_LOCK(r);
    {
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

/* r->sync.monitors は GC mark で辿らない。entry は複製 port（ractor ポインタと
 * id のみで VALUE を持たない）だけを運び、監視側 Ractor のオブジェクトは生きている
 * 間 VM の ractor 集合から root される。また foreign Ractor が自分をこのリストに
 * 登録/解除するため、所有者のロックフリー local GC が辿ると競合して不健全。 */

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

    // send token

    VALUE token = ractor_exit_token(exc);
    struct ractor_monitor *rm, *nxt;

    ccan_list_for_each_safe(&cr->sync.monitors, rm, nxt, node)
    {
        RUBY_DEBUG_LOG("port:%u@r%u", (unsigned int)ractor_port_id(&rm->port), (unsigned int)rb_ractor_id(rm->port.r));

        ractor_try_send(ec, &rm->port, token, false);

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
    /* default_port_value は安定した単一スロット（生成時に一度だけ、所有者が
     * アラインされた 1 word で書く）なので、どの GC から読んでも安全。 */
    rb_gc_mark(r->sync.default_port_value);

    /* queue・port 表・monitor リスト・materialize フレーム鎖は所有者が sync lock
     * 下で（フレーム鎖は receive 中に）書き換えるので、ロックフリーな foreign mark
     * が辿ると壊れて読める。しかも containment によりその中身はどれもこの marker に
     * とって foreign（payload snapshot は sender の in-flight pin で、port は
     * shareable pin で生存）。並行する所有者が居ない場合のみ辿る: 自 Ractor、
     * 終了済み Ractor、または global GC の barrier 下。 */
    rb_ractor_t *cr = rb_current_ractor_raw(false);
    if (r == cr || rb_ractor_status_p(r, ractor_terminated) || rb_gc_during_global_gc_p()) {
        /* receive が復元中の snapshot / courier。既に queue から外れ、global GC の
         * re-pin のためここだけが root。user の load フックからの入れ子 receive が
         * 各々フレームを push して鎖になる。foreign marker は読んではならない。 */
        for (const struct rlgc_materialize_frame *f = r->sync.materialize_frames;
             f != NULL; f = f->prev) {
            rb_gc_mark(f->snapshot);
            /* courier は off-heap。運ぶ shareable な VALUE を mark し、並行 global GC
             * に維持させる。 */
            ractor_move_courier_mark(f->courier);
        }

        /* 戻り値（exit 時に設定、Ractor#value が読む）は今や終了済み Ractor の
         * objspace に在る。value 時の継承が pin する（rb_ractor_pin_inherited_parts）
         * までは、確実な root はここだけ。所有者が書く単純スロットなので同じゲートで
         * mark する（Qundef=未終了なら no-op）。さもないと死んだ main thread の
         * th->value/errinfo 別名に生存を頼ることになり、例外 teardown 経路がそれを
         * 落とすと Ractor#value が解放済みオブジェクトを返してしまう。 */
        rb_gc_mark(r->sync.legacy);

        if (r->sync.ports) {
            /* recv_queue（と ports 表）は r の sync lock を持つ foreign な送信側が
             * 書く（RACTOR_LOCK 下の ractor_queue_enq）。これが自分の並行 local GC
             * （r == cr かつ STW な global GC でない）だと、別スレッドの送信側が
             * 走査中に queue を変更しうる=真のデータ競合。lock を取り送信側を排除する。
             * 自己 deadlock はしない: いずれかの ractor lock 保持中は malloc 起因の
             * GC が無効なので、GC marker が既に r の lock を持つことはない。global GC
             * 下は全送信側が停止、終了済み Ractor には送信側が無く、どちらも lock 不要。 */
            bool lock_against_senders = (r == cr) && !rb_gc_during_global_gc_p();
            if (lock_against_senders) RACTOR_LOCK(r);
            ractor_queue_mark(r->sync.recv_queue);
            st_foreach(r->sync.ports, ractor_mark_ports_i, 0);
            if (lock_against_senders) RACTOR_UNLOCK(r);
        }
        /* monitors は辿らない。理由は ractor_monitor 定義上のコメント参照。 */
    }
}

static void
ractor_queue_repin_in_flight(const struct ractor_queue *rq)
{
    const struct ractor_basket *b;
    ccan_list_for_each(&rq->set, b, node) {
        /* move basket は off-heap courier を運ぶ（re-pin する shref は無い）。運ぶ
         * shareable な VALUE は代わりに ractor_basket_mark で mark される。 */
        if (b->type == basket_type_copy) {
            rb_gc_pin_in_flight_message(b->p.v);
        }
    }
}

static int
ractor_repin_ports_i(st_data_t key, st_data_t val, st_data_t data)
{
    ractor_queue_repin_in_flight((struct ractor_queue *)val);
    return ST_CONTINUE;
}

/* global GC は全 shref ビットを消すので、unified mark の前に全 in-flight payload
 * （queue 済み basket と receive が今 materialize 中の snapshot）を re-pin する
 * 必要がある。barrier 下で driver 上で走る。 */
void
rb_ractor_repin_in_flight(rb_ractor_t *r)
{
    if (r->sync.ports) {
        ractor_queue_repin_in_flight(r->sync.recv_queue);
        st_foreach(r->sync.ports, ractor_repin_ports_i, 0);
    }
    for (const struct rlgc_materialize_frame *f = r->sync.materialize_frames;
         f != NULL; f = f->prev) {
        if (f->snapshot && !RB_SPECIAL_CONST_P(f->snapshot)) {
            rb_gc_pin_in_flight_message(f->snapshot);
        }
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
        return st_table_size(r->sync.ports);
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
    ccan_list_head_init(&r->sync.monitors);

    // waiters
    ccan_list_head_init(&r->sync.waiters);

    // receiving queue
    r->sync.recv_queue = ractor_queue_new();

    // ports
    r->sync.ports = st_init_numtable();
    r->sync.default_port_value = ractor_port_new(r);
    FL_SET_RAW(r->sync.default_port_value, RUBY_FL_SHAREABLE); // only default ports are shareable
    rb_gc_obj_became_shareable(r->sync.default_port_value);

    // legacy
    r->sync.legacy = Qundef;

    // payload を再構築中の receive はまだ無い
    r->sync.materialize_frames = NULL;

#ifndef RUBY_THREAD_PTHREAD_H
    rb_native_cond_initialize(&r->sync.wakeup_cond);
#endif
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

static VALUE ractor_reset_belonging(VALUE obj);

static VALUE
ractor_make_remote_exception(VALUE cause, VALUE sender)
{
    VALUE err = rb_exc_new_cstr(rb_eRactorRemoteError, "thrown by remote Ractor.");
    rb_ivar_set(err, rb_intern("@ractor"), sender);
    rb_ec_setup_exception(NULL, err, cause);
    return err;
}

/* Ractor#value が死んだ Ractor の objspace を吸収した後、その C struct から今も
 * 参照される物（再度の #value 用 legacy 値、stdio、local storage）は呼び出し側の
 * objspace に属すが、経路は Ractor オブジェクト経由のみ。そのオブジェクトは通常
 * 別 Ractor の objspace に在り、その mark は我々のオブジェクトを foreign-skip し、
 * 我々の GC は foreign な Ractor オブジェクトを辿らない。各トップレベルスロットを
 * shref ビットで pin する（今や我々のページなので通常のストア）。子は通常の root
 * 走査で生き、global GC は Ractor オブジェクトが生きる間、その shareable エッジから
 * 同じビットを再導出する。 */
void
rb_ractor_pin_inherited_parts(rb_ractor_t *r)
{
    VALUE slots[] = {
        r->sync.legacy,
        r->r_stdin, r->r_stdout, r->r_stderr,
        r->verbose, r->debug,
    };
    for (size_t i = 0; i < numberof(slots); i++) {
        if (!SPECIAL_CONST_P(slots[i])) {
            rb_gc_pin_in_flight_message(slots[i]);
        }
    }

    /* 死んだ Ractor の local storage はこれ以降 Ruby コードから到達不能
     * （Ractor#[] は内側からのみ動く）。pin せずここで解放する。値は自然に死ね、
     * ractor_mark も ractor_free も後で stale な表を辿らずに済む。 */
    ractor_local_storage_free(r);
    r->local_storage = NULL;
    r->idkey_local_storage = NULL;

    /* 死んだ Ractor の main thread は threads リストに残り、その Thread/Fiber の
     * ラッパオブジェクトは死んだ objspace で生まれた（thread.c の
     * rb_thread_create_ractor）ので他と共に継承される。ラッパを pin すれば十分:
     * その dmark が残りの thread 状態（th->value など）へ推移的に到達する。 */
    rb_thread_t *th = 0;
    ccan_list_for_each(&r->threads.set, th, lt_node) {
        if (th->self && !SPECIAL_CONST_P(th->self)) {
            rb_gc_pin_in_flight_message(th->self);
        }
        if (th->root_fiber) {
            VALUE fself = rb_fiberptr_self(th->root_fiber);
            if (fself && !SPECIAL_CONST_P(fself)) {
                rb_gc_pin_in_flight_message(fself);
            }
        }
        if (th->ec && th->ec->fiber_ptr) {
            VALUE fself = rb_fiberptr_self(th->ec->fiber_ptr);
            if (fself && !SPECIAL_CONST_P(fself)) {
                rb_gc_pin_in_flight_message(fself);
            }
        }
    }
}

static VALUE
ractor_value(rb_execution_context_t *ec, VALUE self)
{
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    rb_ractor_t *r = RACTOR_PTR(self);
    rb_ractor_t *sr = ractor_set_successor_once(r, cr);

    if (sr == cr) {
        /* 値は参照で返すので、まず死んだ Ractor の objspace を我々のものへ継承する。
         * merge 後は戻り値も我々のオブジェクトになり、コピー無しで containment が成立。
         * monitor-port の wakeup は死ぬ thread の teardown 終了より前に起こる
         * （vm_remove_ractor がまだ objspace を触る）ので、terminated 状態を待つ。
         * これは teardown 最後の objspace アクセス後に VM lock 下で設定される。 */
        while (!rb_ractor_status_p(r, ractor_terminated)) {
            rb_thread_schedule();
        }

        /* r の per-Ractor generic_fields 表を joiner へ移送する。objspace merge より
         * 前に行う必要がある: 下の absorb は内部で r の objspace を sweep し、その最中に
         * r の dead host が obj_free 経由で rb_free_generic_ivar を呼ぶが、その時点の
         * GET_RACTOR() は joiner なので entry を joiner 表に引きに行く。先に移送しないと
         * 「objspace は移ったが登録情報は未移送」の窓で miss する。移送から merge の間に
         * GC safepoint は無く、移送先 key はまだ r の objspace だが誰も引かないので安全。 */
        rb_ractor_absorb_generic_fields(GET_RACTOR(), r);
        /* rb_gc_register_mark_object の pin も同じ窓。下の merge が r の objspace を
         * sweep するので、先に r の per-Ractor 登録を joiner へ移さないと、r の objspace
         * に残った pin 済みオブジェクトが root を失う。 */
        rb_ractor_absorb_registered_marks(GET_RACTOR(), r);

        rb_gc_objspace_absorb_into_current(&r->objspace);

        /* 継承したオブジェクトへの唯一の経路は死んだ Ractor の C struct であり、
         * 我々の local GC はそれを辿らない。トップレベルスロットを shref ビットで
         * pin して root にする（詳細は rb_ractor_pin_inherited_parts 参照）。 */
        rb_ractor_pin_inherited_parts(r);

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
ractor_prepare_payload(rb_execution_context_t *ec, VALUE obj, enum ractor_basket_type *ptype, bool *pmarshaled)
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
            /* 送信側で、利用者に見える #clone を呼ばずに snapshot コピーする。中核型は
             * native に deep copy し、それ以外は snapshot を Marshal バイト列にする
             * （その利用者フックはここ、送信側で走る）。 */
            *ptype = basket_type_copy;
            /* native copy 中、copy_enter が snapshot の generic-ivar host の fields_obj を
             * cr->gen_fields_capture に記録する（host が出て初めて遅延確保）。
             * ractor_basket_new が basket へ移して回収し、Marshal fallback 時は破棄する。 */
            rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
            VM_ASSERT(!cr->gen_fields_capturing && cr->gen_fields_capture == NULL);
            cr->gen_fields_capturing = true;
            VALUE snapshot = Qundef;
            /* native copy は raise しうる（確保・非同期割り込み）。capturing フラグが
             * 立ちっぱなしだと次の send の assert に失敗し、stale な capture 表がその
             * basket に漏れる。 */
            enum ruby_tag_type state;
            EC_PUSH_TAG(ec);
            if ((state = EC_EXEC_TAG()) == TAG_NONE) {
                snapshot = ractor_copy_native_try(obj);
            }
            EC_POP_TAG();
            cr->gen_fields_capturing = false;
            if (state != TAG_NONE) {
                if (cr->gen_fields_capture) {
                    st_free_table(cr->gen_fields_capture);
                    cr->gen_fields_capture = NULL;
                }
                EC_JUMP_TAG(ec, state);
            }
            if (UNDEF_P(snapshot)) {
                if (cr->gen_fields_capture) {
                    st_free_table(cr->gen_fields_capture);
                    cr->gen_fields_capture = NULL;
                }
                snapshot = rb_rescue2(ractor_marshal_dump_body, obj,
                                      ractor_marshal_dump_rescue, obj,
                                      rb_eTypeError, (VALUE)0);
                *pmarshaled = true;
            }
            return snapshot;
        }
    }
}

static struct ractor_basket *
ractor_basket_new(rb_execution_context_t *ec, VALUE obj, enum ractor_basket_type type, bool exc)
{
    struct ractor_basket *b = ractor_basket_alloc();
    b->p.exception = exc;
    b->p.marshaled = false;
    b->p.move_courier = NULL;
    b->p.gen_fields = NULL;

    if (type == basket_type_move) {
        /* グラフを off-heap courier へ直列化する。元オブジェクトは RactorMovedObject に
         * なる。in-flight 中は GC オブジェクトが無いので、送信側の GC が mark/sweep/move
         * することはない。 */
        b->type = basket_type_move;
        b->p.v = Qfalse;
        b->p.move_courier = ractor_move_courier_build(obj);
    }
    else {
        bool marshaled = false;
        VALUE v = ractor_prepare_payload(ec, obj, &type, &marshaled);
        if (type == basket_type_copy) {
            /* copy snapshot（native グラフまたは Marshal 文字列）は受信側が
             * materialize するまで送信側の objspace に在る。shref で pin し、
             * 送信側の local GC に維持させる。 */
            rb_gc_pin_in_flight_message(v);
            /* native copy の generic-ivar 対応表を basket へ移す（prepare_payload が
             * cr->gen_fields_capture に構築、marshaled/generic-ivar 無しなら空/NULL）。 */
            b->p.gen_fields = rb_ec_ractor_ptr(ec)->gen_fields_capture;
            rb_ec_ractor_ptr(ec)->gen_fields_capture = NULL;
        }
        b->type = type;
        b->p.v = v;
        b->p.marshaled = marshaled;
    }
    return b;
}

/* この Ractor が到着した copy を materialize 中の間 true
 * （ractor_basket_value -> ractor_copy_native_try）。その窓では作りかけの結果が
 * 送信側常駐の snapshot（pin 済み）へのエッジを正当に持つので、local GC の verifier は
 * それを containment 違反と誤検出してはならない（copy 自身の確保がその GC を途中で
 * 起こしうる）。 */
bool
rb_gc_current_ractor_materializing_p(void)
{
    const rb_ractor_t *cr = rb_current_ractor_raw(false);
    if (cr == NULL) return false;
    /* true になるのは COPY の materialize のみ（snapshot != Qfalse）。move の殻は
     * この objspace 内の他の殻を参照し、送信側のグラフは参照しない。 */
    for (const struct rlgc_materialize_frame *f = cr->sync.materialize_frames;
         f != NULL; f = f->prev) {
        if (f->snapshot != Qfalse) return true;
    }
    return false;
}

static VALUE
ractor_basket_value(struct ractor_basket *b)
{
    switch (b->type) {
      case basket_type_ref:
        break;
      case basket_type_copy: {
        /* 送信側の snapshot を受信 Ractor の objspace へ materialize する。送信側常駐の
         * グラフを参照で渡すと、どちらの local GC も辿れない unshareable な
         * cross-objspace エッジを作ってしまう。snapshot は送信側 objspace に pin された
         * まま残り、このコピー完了後にそこで garbage になる。Marshal.load はこの Ractor の
         * 通常の newobj/write-barrier 経路で確保する。basket は既に queue から外れており、
         * コピー中は materialize フレームが snapshot を root（かつ global GC が re-pin 可）
         * に保つ。
         *
         * 再構築は raise しうる（marshal の load フックや autoload は利用者コード、
         * 非同期割り込みもどこでも起きうる）し、それらフックが入れ子の Ractor.receive を
         * 走らせうる。マシンスタックにフレームを push し TAG 保護下で pop するので、鎖が
         * 死んだ materialization を漏らしたり外側を落としたりしない。 */
        rb_execution_context_t *ec = rb_current_ec_noinline();
        rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
        struct rlgc_materialize_frame frame = {
            .snapshot = b->p.v, .courier = NULL, .prev = cr->sync.materialize_frames,
        };
        cr->sync.materialize_frames = &frame;
        struct st_table *prev_gf = cr->gen_fields_materialize;
        VALUE result = Qundef;
        enum ruby_tag_type state;
        EC_PUSH_TAG(ec);
        if ((state = EC_EXEC_TAG()) == TAG_NONE) {
            if (b->p.marshaled) {
                result = rb_marshal_load(b->p.v);
            }
            else {
                /* materialize 中、snapshot host の generic-ivar を読む際（native copy の
                 * rb_copy_generic_ivar）、送信側の per-Ractor 表を跨がずこの対応表から
                 * fields_obj を引く（rb_obj_fields_generic_uncached が
                 * gen_fields_materialize を参照）。 */
                cr->gen_fields_materialize = b->p.gen_fields;
                result = ractor_copy_native_try(b->p.v);
                if (UNDEF_P(result)) rb_bug("ractor_basket_value: native snapshot not natively copyable");
            }
        }
        EC_POP_TAG();
        cr->gen_fields_materialize = prev_gf;
        cr->sync.materialize_frames = frame.prev;
        /* rb_copy_generic_ivar はこの EC の gen_fields_cache に送信側の snapshot host と
         * fields_obj（共に送信側常駐）を入れた。snapshot は今や送信側で garbage であり、
         * その解放アドレスに後で受信側が新オブジェクトを得ると、stale な cache ヒットが
         * foreign な解放済み fields_obj を deref しうる。cache を無効化する
         * （raise 経路でも同じリセットで行う）。 */
        ec->gen_fields_cache.obj = Qundef;
        ec->gen_fields_cache.fields_obj = Qundef;
        if (state != TAG_NONE) EC_JUMP_TAG(ec, state);
        /* フレームが pop された後も result をスタックから root し続ける */
        ractor_reset_belonging(result);
        b->p.v = result;
        RB_GC_GUARD(result);
        break;
      }
      case basket_type_move: {
        /* move されたグラフを off-heap courier からこの Ractor の objspace へ再構築する。
         * 元オブジェクトは既に RactorMovedObject（courier 構築時に設定）なので move の
         * snapshot 意味論が成り立つ。courier は xmalloc で GC オブジェクトでないため、
         * 送信側の並行 local GC が mark/sweep/move/競合することはない。運ぶ VALUE は
         * shareable/即値のみで、再構築中は materialize フレームがそれらを global GC に対し
         * root する。
         *
         * ここでも再構築は raise しうる（custom #hash を持つ move 済み key への
         * rb_hash_aset は利用者コード、非同期割り込みも）。同じフレーム + TAG 規律。
         * raise 時は courier が basket 所有のまま（b->p.move_courier != NULL）なので
         * basket の teardown が解放する。 */
        rb_execution_context_t *ec = rb_current_ec_noinline();
        rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
        struct rb_ractor_move_courier *courier = b->p.move_courier;
        struct rlgc_materialize_frame frame = {
            .snapshot = Qfalse, .courier = courier, .prev = cr->sync.materialize_frames,
        };
        cr->sync.materialize_frames = &frame;
        /* materialize したグラフを、以降の一連の処理の間ずっとマシンスタック（result）に
         * 保持する。フレームを pop した後は、それが呼び出し側スタックへ届くまで唯一の
         * root。ここで ractor_move_courier_free が長い解放ループを回るので、グラフが
         * malloc された basket の p.v にしか無ければ、並行 global GC に回収されうる窓が
         * 広く開く。 */
        VALUE result = Qundef;
        enum ruby_tag_type state;
        EC_PUSH_TAG(ec);
        if ((state = EC_EXEC_TAG()) == TAG_NONE) {
            result = ractor_move_courier_materialize(courier);
        }
        EC_POP_TAG();
        cr->sync.materialize_frames = frame.prev;
        if (state != TAG_NONE) EC_JUMP_TAG(ec, state);
        ractor_move_courier_free(courier);
        b->p.move_courier = NULL;
        ractor_reset_belonging(result);
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
ractor_cond_wait(rb_ractor_t *r)
{
#if RACTOR_CHECK_MODE > 0
    VALUE locked_by = r->sync.locked_by;
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
        if (waiter->wakeup_status == wakeup_none) {
            ractor_cond_wait(cr);
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

static enum ractor_wakeup_status
ractor_wait(rb_execution_context_t *ec, rb_ractor_t *cr)
{
    rb_thread_t *th = rb_ec_thread_ptr(ec);

    struct ractor_waiter waiter = {
        .wakeup_status = wakeup_none,
        .th = th,
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
    const struct ractor_port *rp = RACTOR_PORT_PTR(rpv);

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
    rb_define_method(rb_cRactorPort, "initialize", ractor_port_initialize, 0);
    rb_define_method(rb_cRactorPort, "initialize_copy", ractor_port_initialize_copy, 1);

#if USE_RACTOR_SELECTOR
    rb_init_ractor_selector();
#endif
}
