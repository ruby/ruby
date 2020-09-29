#include "internal/fixnum.h"
#include "ruby/util.h"

// Thread/Ractor support transactional variable Thread::TVar

// 0: null (BUG/only for evaluation)
// 1: mutex
// TODO: 1: atomic
#define SLOT_LOCK_TYPE 1

struct slot_lock {
#if   SLOT_LOCK_TYPE == 0
#elif SLOT_LOCK_TYPE == 1
    rb_nativethread_lock_t lock;
#else
#error unknown
#endif
};

struct tvar_slot {
    uint64_t version;
    VALUE value;
    VALUE index;
    struct slot_lock lock;
};

struct tx_global {
    uint64_t version;
    rb_nativethread_lock_t version_lock;

    uint64_t slot_index;
    rb_nativethread_lock_t slot_index_lock;
};

struct tx_log {
    VALUE value;
    struct tvar_slot *slot;
    VALUE tvar; // mark slot
};

struct tx_logs {
    uint64_t version;
    uint32_t logs_cnt;
    uint32_t logs_capa;

    struct tx_log *logs;

    bool enabled;
    bool stop_adding;

    uint32_t retry_history;
    size_t retry_on_commit;
    size_t retry_on_read_lock;
    size_t retry_on_read_version;
};

static struct tx_global tx_global;

static VALUE rb_eThreadTxRetry;
static VALUE rb_eThreadTxError;
static VALUE rb_exc_tx_retry;
static VALUE rb_cThreadTVar;

static VALUE
txg_next_index(struct tx_global *txg)
{
    VALUE index;
    rb_native_mutex_lock(&txg->slot_index_lock);
    {
        txg->slot_index++;
        index = INT2FIX(txg->slot_index);
    }
    rb_native_mutex_unlock(&txg->slot_index_lock);

    return index;
}

static struct tx_global *
tx_global_ptr(rb_execution_context_t *ec)
{
    return &tx_global;
}

static uint64_t
txg_version(const struct tx_global *txg)
{
    uint64_t version;
    version = txg->version;
    return version;
}

static uint64_t
txg_next_version(struct tx_global *txg)
{
    uint64_t version;

    rb_native_mutex_lock(&txg->version_lock);
    {
        txg->version++;
        version = txg->version;
        RUBY_DEBUG_LOG("new_version:%lu", version);
    }
    rb_native_mutex_unlock(&txg->version_lock);

    return version;
}

// tx: transaction

static void
tx_slot_lock_init(struct slot_lock *lock)
{
#if   SLOT_LOCK_TYPE == 0
#elif SLOT_LOCK_TYPE == 1
    rb_native_mutex_initialize(&lock->lock);
#else
#error unknown
#endif
}

static void
tx_slot_lock_free(struct slot_lock *lock)
{
#if   SLOT_LOCK_TYPE == 0
#elif SLOT_LOCK_TYPE == 1
    rb_native_mutex_destroy(&lock->lock);
#else
#error unknown
#endif
}

static bool
tx_slot_lock_trylock(struct slot_lock *lock)
{
#if   SLOT_LOCK_TYPE == 0
    return true;
#elif SLOT_LOCK_TYPE == 1
    return rb_native_mutex_trylock(&lock->lock) == 0;
#else
#error unknown
#endif
}

static void
tx_slot_lock_lock(struct slot_lock *lock)
{
#if   SLOT_LOCK_TYPE == 0
#elif SLOT_LOCK_TYPE == 1
    rb_native_mutex_lock(&lock->lock);
#else
#error unknown
#endif
}

static void
tx_slot_lock_unlock(struct slot_lock *lock)
{
#if   SLOT_LOCK_TYPE == 0
#elif SLOT_LOCK_TYPE == 1
    rb_native_mutex_unlock(&lock->lock);
#else
#error unknown
#endif
}

static bool
tx_slot_trylock(struct tvar_slot *slot)
{
    return tx_slot_lock_trylock(&slot->lock);
}

static void
tx_slot_lock(struct tvar_slot *slot)
{
    tx_slot_lock_lock(&slot->lock);
}

static void
tx_slot_unlock(struct tvar_slot *slot)
{
    tx_slot_lock_unlock(&slot->lock);
}

static struct tx_logs *
tx_logs(rb_execution_context_t *ec)
{
    rb_thread_t *th = rb_ec_thread_ptr(ec);

    if (UNLIKELY(th->tx == NULL)) {
        th->tx = ZALLOC(struct tx_logs);
        // th->tx->version = 0;
        // th->tx->enabled = false;
        // th->tx->stop_adding = false;
        // th->tx->logs_cnt = 0;
        th->tx->logs_capa = 0x10; // default
        th->tx->logs = ALLOC_N(struct tx_log, th->tx->logs_capa);
    }
    return th->tx;
}

void
rb_threadptr_tx_free(rb_thread_t *th)
{
    if (th->tx) {
        RUBY_DEBUG_LOG("retry %5lu commit:%lu read_lock:%lu read_version:%lu",
                       th->tx->retry_on_commit + th->tx->retry_on_read_lock + th->tx->retry_on_read_version,
                       th->tx->retry_on_commit,
                       th->tx->retry_on_read_lock,
                       th->tx->retry_on_read_version);

        ruby_xfree(th->tx->logs);
        ruby_xfree(th->tx);
    }
}

static struct tx_log *
tx_lookup(struct tx_logs *tx, VALUE tvar)
{
    struct tx_log *copies = tx->logs;
    uint32_t cnt = tx->logs_cnt;

    for (uint32_t i = 0; i< cnt; i++) {
        if (copies[i].tvar == tvar) {
            return &copies[i];
        }
    }

    return NULL;
}

static void
tx_add(struct tx_logs *tx, VALUE val, struct tvar_slot *slot, VALUE tvar)
{
    if (UNLIKELY(tx->logs_capa == tx->logs_cnt)) {
        uint32_t new_capa =  tx->logs_capa * 2;
        SIZED_REALLOC_N(tx->logs, struct tx_log, new_capa, tx->logs_capa);
        tx->logs_capa = new_capa;
    }
    if (UNLIKELY(tx->stop_adding)) {
        rb_raise(rb_eThreadTxError, "can not handle more transactional variable: %"PRIxVALUE, rb_inspect(tvar));
    }
    struct tx_log *log = &tx->logs[tx->logs_cnt++];

    log->value = val;
    log->slot = slot;
    log->tvar = tvar;
}

static VALUE
tx_get(struct tx_logs *tx, struct tvar_slot *slot, VALUE tvar)
{
    struct tx_log *ent = tx_lookup(tx, tvar);

    if (ent == NULL) {
        VALUE val;

        if (tx_slot_trylock(slot)) {
            if (slot->version > tx->version) {
                RUBY_DEBUG_LOG("RV < slot->V slot:%u slot->version:%lu, tx->version:%lu", FIX2INT(slot->index), slot->version, tx->version);
                tx_slot_unlock(slot);
                tx->retry_on_read_version++;
                goto abort_and_retry;
            }
            val = slot->value;
            tx_slot_unlock(slot);
        }
        else {
            RUBY_DEBUG_LOG("RV < slot->V slot:%u slot->version:%lu, tx->version:%lu", FIX2INT(slot->index), slot->version, tx->version);
            tx->retry_on_read_lock++;
            goto abort_and_retry;
        }
        tx_add(tx, val, slot, tvar);
        return val;

      abort_and_retry:
        rb_raise(rb_eThreadTxRetry, "retry");
    }
    else {
        return ent->value;
    }
}

static void
tx_set(struct tx_logs *tx, VALUE val, struct tvar_slot *slot, VALUE tvar)
{
    struct tx_log *ent = tx_lookup(tx, tvar);

    if (ent == NULL) {
        tx_add(tx, val, slot, tvar);
    }
    else {
        ent->value = val;
    }
}

static void
tx_check(struct tx_logs *tx)
{
    if (UNLIKELY(!tx->enabled)) {
        rb_raise(rb_eThreadTxError, "can not set without transaction");
    }
}

static void
tx_setup(struct tx_global *txg, struct tx_logs *tx)
{
    VM_ASSERT(tx->enabled);
    VM_ASSERT(tx->logs_cnt == 0);

    tx->version = txg_version(txg);

    RUBY_DEBUG_LOG("tx:%lu", tx->version);
}

static VALUE
tx_begin(rb_execution_context_t *ec, VALUE self)
{
    struct tx_global *txg = tx_global_ptr(ec);
    struct tx_logs *tx = tx_logs(ec);

    VM_ASSERT(tx->stop_adding == false);
    VM_ASSERT(tx->logs_cnt == 0);

    if (tx->enabled == false) {
        tx->enabled = true;
        tx_setup(txg, tx);
        return Qtrue;
    }
    else {
        return Qfalse;
    }
}

static VALUE
tx_reset(rb_execution_context_t *ec, VALUE self)
{
    struct tx_global *txg = tx_global_ptr(ec);
    struct tx_logs *tx = tx_logs(ec);
    tx->logs_cnt = 0;

    // contention management (CM)
    if (tx->retry_history != 0) {
        int recent_retries = rb_popcount32(tx->retry_history);
        RUBY_DEBUG_LOG("retry recent_retries:%d", recent_retries);

        struct timeval tv = {
            .tv_sec = 0,
            .tv_usec = 1 * recent_retries,
        };

        RUBY_DEBUG_LOG("CM tv_usec:%lu", (unsigned long)tv.tv_usec);
        rb_thread_wait_for(tv);
    }

    tx_setup(txg, tx);
    RUBY_DEBUG_LOG("tx:%lu", tx->version);

    return Qnil;
}

static VALUE
tx_end(rb_execution_context_t *ec, VALUE self)
{
    struct tx_logs *tx = tx_logs(ec);

    RUBY_DEBUG_LOG("tx:%lu", tx->version);

    VM_ASSERT(tx->enabled);
    VM_ASSERT(tx->stop_adding == false);
    tx->enabled = false;
    tx->logs_cnt = 0;
    return Qnil;
}

static void
tx_commit_release(struct tx_logs *tx, uint32_t n)
{
    struct tx_log *copies = tx->logs;

    for (uint32_t i = 0; i<n; i++) {
        struct tx_log *copy = &copies[i];
        struct tvar_slot *slot = copy->slot;
        tx_slot_unlock(slot);
    }
}

static VALUE
tx_commit(rb_execution_context_t *ec, VALUE self)
{
    struct tx_global *txg = tx_global_ptr(ec);
    struct tx_logs *tx = tx_logs(ec);
    uint32_t i;
    struct tx_log *copies = tx->logs;
    uint32_t logs_cnt = tx->logs_cnt;

    for (i=0; i<logs_cnt; i++) {
        struct tx_log *copy = &copies[i];
        struct tvar_slot *slot = copy->slot;

        if (LIKELY(tx_slot_trylock(slot))) {
            if (UNLIKELY(slot->version > tx->version)) {
                RUBY_DEBUG_LOG("RV < slot->V slot:%lu tx:%lu rs:%lu", slot->version, tx->version, txg->version);
                tx_commit_release(tx, i+1);
                goto abort_and_retry;
            }
            else {
                // lock success
                RUBY_DEBUG_LOG("lock slot:%lu tx:%lu rs:%lu", slot->version, tx->version, txg->version);
            }
        }
        else {
            RUBY_DEBUG_LOG("trylock fail slot:%lu tx:%lu rs:%lu", slot->version, tx->version, txg->version);
            tx_commit_release(tx, i);
            goto abort_and_retry;
        }
    }

    // ok
    tx->retry_history <<= 1;

    uint64_t new_version = txg_next_version(txg);

    for (i=0; i<logs_cnt; i++) {
        struct tx_log *copy = &copies[i];
        struct tvar_slot *slot = copy->slot;

        if (slot->value != copy->value) {
            RUBY_DEBUG_LOG("write slot:%d %d->%d slot->version:%lu->%lu tx:%lu rs:%lu",
                           FIX2INT(slot->index), FIX2INT(slot->value), FIX2INT(copy->value),
                           slot->version, new_version, tx->version, txg->version);

            slot->version = new_version;
            slot->value = copy->value;
        }
    }

    tx_commit_release(tx, logs_cnt);

    return Qtrue;

  abort_and_retry:
    tx->retry_on_commit++;

    return Qfalse;
}

// tvar

static void
tvar_mark(void *ptr)
{
    struct tvar_slot *slot = (struct tvar_slot *)ptr;
    rb_gc_mark(slot->value);
}

static void
tvar_free(void *ptr)
{
    struct tvar_slot *slot = (struct tvar_slot *)ptr;
    tx_slot_lock_free(&slot->lock);
    ruby_xfree(slot);
}

static const rb_data_type_t tvar_data_type = {
    "Thread::TVar",
    {tvar_mark, tvar_free, NULL,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
tvar_new(rb_execution_context_t *ec, VALUE self, VALUE init)
{
    // init should be shareable
    if (UNLIKELY(!rb_ractor_shareable_p(init))) {
        rb_raise(rb_eArgError, "only shareable object are allowed");
    }

    struct tx_global *txg = tx_global_ptr(ec);
    struct tvar_slot *slot;
    VALUE obj = TypedData_Make_Struct(rb_cThreadTVar, struct tvar_slot, &tvar_data_type, slot);
    slot->version = 0;
    slot->value = init;
    slot->index = txg_next_index(txg);
    tx_slot_lock_init(&slot->lock);

    rb_obj_freeze(obj);
    FL_SET_RAW(obj, RUBY_FL_SHAREABLE);

    return obj;
}

static VALUE
tvar_value(rb_execution_context_t *ec, VALUE self)
{
    struct tx_logs *tx = tx_logs(ec);
    struct tvar_slot *slot = DATA_PTR(self);

    if (tx->enabled) {
        return tx_get(tx, slot, self);
    }
    else {
        // TODO: warn on multi-ractors?
        return slot->value;
    }
}

static VALUE
tvar_value_set(rb_execution_context_t *ec, VALUE self, VALUE val)
{
    if (UNLIKELY(!rb_ractor_shareable_p(val))) {
        rb_raise(rb_eArgError, "only shareable object are allowed");
    }

    struct tx_logs *tx = tx_logs(ec);
    tx_check(tx);
    struct tvar_slot *slot = DATA_PTR(self);
    tx_set(tx, val, slot, self);
    return val;
}

static VALUE
tvar_calc_inc(VALUE v, VALUE inc)
{
    if (LIKELY(FIXNUM_P(v) && FIXNUM_P(inc))) {
        return rb_fix_plus_fix(v, inc);
    }
    else {
        return Qundef;
    }
}

static VALUE
tvar_value_increment(rb_execution_context_t *ec, VALUE self, VALUE inc)
{
    struct tx_global *txg = tx_global_ptr(ec);
    struct tx_logs *tx = tx_logs(ec);
    VALUE recv, ret;
    struct tvar_slot *slot = DATA_PTR(self);

    if (!tx->enabled) {
        tx_slot_lock(slot);
        {
            uint64_t new_version = txg_next_version(txg);
            recv = slot->value;
            ret = tvar_calc_inc(recv, inc);

            if (LIKELY(ret != Qundef)) {
                slot->value = ret;
                slot->version = new_version;
                txg->version = new_version;
            }
        }
        tx_slot_unlock(slot);

        if (UNLIKELY(ret == Qundef)) {
            // atomically{ self.value += inc }
            ret = rb_funcall(self, rb_intern("__increment_any__"), 1, inc);
        }
    }
    else {
        recv = tx_get(tx, slot, self);
        if (UNLIKELY((ret = tvar_calc_inc(recv, inc)) == Qundef)) {
            ret = rb_funcall(recv, rb_intern("+"), 1, inc);
        }
        tx_set(tx, ret, slot, self);
    }

    return ret;
}

static struct tvar_slot *
tvar_slot_ptr(VALUE v)
{
    if (rb_typeddata_is_kind_of(v, &tvar_data_type)) {
        return DATA_PTR(v);
    }
    else {
        rb_raise(rb_eArgError, "TVar is needed");
    }
}

static void
Init_thread_tvar(void)
{
    struct tx_global *txg = tx_global_ptr(GET_EC());
    txg->slot_index = 0;
    txg->version = 0;
    rb_native_mutex_initialize(&txg->slot_index_lock);
    rb_native_mutex_initialize(&txg->version_lock);

    rb_eThreadTxError = rb_define_class_under(rb_cThread, "TransactionError", rb_eRuntimeError);
    rb_eThreadTxRetry = rb_define_class_under(rb_cThread, "RetryTransaction", rb_eException);

    rb_cThreadTVar = rb_define_class_under(rb_cThread, "TVar", rb_cObject);

    rb_exc_tx_retry = rb_exc_new_cstr(rb_eThreadTxRetry, "Thread::RetryTransaction");
    rb_obj_freeze(rb_exc_tx_retry);
    rb_gc_register_mark_object(rb_exc_tx_retry);
}

#include "thread.rbinc"
