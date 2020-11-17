#include "ruby/ruby.h"
#include "vm_core.h"
#include "id_table.h"
#include "vm_debug.h"
#include "ractor_pub.h"

#ifndef RACTOR_CHECK_MODE
#define RACTOR_CHECK_MODE (0 || VM_CHECK_MODE || RUBY_DEBUG)
#endif

enum rb_ractor_basket_type {
    basket_type_none = 0,
    basket_type_ref  = 1,
    basket_type_copy = 2,
    basket_type_move = 3,
    basket_type_will = 4, // 3 bit
};

struct rb_ractor_basket {
    enum rb_ractor_basket_type type;
    bool exception;
    VALUE v;
    VALUE sender;
};

struct rb_ractor_queue {
    struct rb_ractor_basket *baskets;
    int start;
    int cnt;
    int size;
};

struct rb_ractor_waiting_list {
    int cnt;
    int size;
    rb_ractor_t **ractors;
};

struct rb_ractor_struct {
    // ractor lock
    rb_nativethread_lock_t lock;
#if RACTOR_CHECK_MODE > 0
    VALUE locked_by;
#endif

    // communication
    struct rb_ractor_queue  incoming_queue;

    bool incoming_port_closed;
    bool outgoing_port_closed;
    bool yield_atexit;

    struct rb_ractor_waiting_list taking_ractors;

    struct ractor_wait {
        enum ractor_wait_status {
            wait_none      = 0x00,
            wait_receiving = 0x01,
            wait_taking    = 0x02,
            wait_yielding  = 0x04,
        } status;

        enum ractor_wakeup_status {
            wakeup_none,
            wakeup_by_send,
            wakeup_by_yield,
            wakeup_by_take,
            wakeup_by_close,
            wakeup_by_interrupt,
            wakeup_by_retry,
        } wakeup_status;

        struct rb_ractor_basket taken_basket;
        struct rb_ractor_basket yielded_basket;

        rb_nativethread_cond_t cond;
    } wait;

    // vm wide barrier synchronization
    rb_nativethread_cond_t barrier_wait_cond;

    // thread management
    struct {
        struct list_head set;
        unsigned int cnt;
        unsigned int blocking_cnt;
        unsigned int sleeper;
        rb_global_vm_lock_t gvl;
        rb_execution_context_t *running_ec;
        rb_thread_t *main;
    } threads;
    VALUE thgroup_default;

    // identity
    VALUE self;
    uint32_t id;
    VALUE name;
    VALUE loc;

    // created
    //   | ready to run
    // ====================== inserted to vm->ractor
    //   v
    // blocking <---+ all threads are blocking
    //   |          |
    //   v          |
    // running -----+
    //   | all threads are terminated.
    // ====================== removed from vm->ractor
    //   v
    // terminated
    //
    // status is protected by VM lock (global state)

    enum ractor_status {
        ractor_created,
        ractor_running,
        ractor_blocking,
        ractor_terminated,
    } status_;

    struct list_node vmlr_node;

    VALUE r_stdin;
    VALUE r_stdout;
    VALUE r_stderr;
    VALUE verbose;
    VALUE debug;

    // gc.c rb_objspace_reachable_objects_from
    struct gc_mark_func_data_struct {
        void *data;
        void (*mark_func)(VALUE v, void *data);
    } *mfd;
}; // rb_ractor_t is defined in vm_core.h

rb_ractor_t *rb_ractor_main_alloc(void);
void rb_ractor_main_setup(rb_vm_t *vm, rb_ractor_t *main_ractor, rb_thread_t *main_thread);
VALUE rb_ractor_self(const rb_ractor_t *g);
void rb_ractor_atexit(rb_execution_context_t *ec, VALUE result);
void rb_ractor_atexit_exception(rb_execution_context_t *ec);
void rb_ractor_teardown(rb_execution_context_t *ec);
void rb_ractor_receive_parameters(rb_execution_context_t *ec, rb_ractor_t *g, int len, VALUE *ptr);
void rb_ractor_send_parameters(rb_execution_context_t *ec, rb_ractor_t *g, VALUE args);

VALUE rb_thread_create_ractor(rb_ractor_t *g, VALUE args, VALUE proc); // defined in thread.c

rb_global_vm_lock_t *rb_ractor_gvl(rb_ractor_t *);
int rb_ractor_living_thread_num(const rb_ractor_t *);
VALUE rb_ractor_thread_list(rb_ractor_t *r);

void rb_ractor_living_threads_init(rb_ractor_t *r);
void rb_ractor_living_threads_insert(rb_ractor_t *r, rb_thread_t *th);
void rb_ractor_living_threads_remove(rb_ractor_t *r, rb_thread_t *th);
void rb_ractor_blocking_threads_inc(rb_ractor_t *r, const char *file, int line); // TODO: file, line only for RUBY_DEBUG_LOG
void rb_ractor_blocking_threads_dec(rb_ractor_t *r, const char *file, int line); // TODO: file, line only for RUBY_DEBUG_LOG

void rb_ractor_vm_barrier_interrupt_running_thread(rb_ractor_t *r);
void rb_ractor_terminate_interrupt_main_thread(rb_ractor_t *r);
void rb_ractor_terminate_all(void);

static inline bool
rb_ractor_status_p(rb_ractor_t *r, enum ractor_status status)
{
    return r->status_ == status;
}

static inline void
rb_ractor_sleeper_threads_inc(rb_ractor_t *r)
{
    r->threads.sleeper++;
}

static inline void
rb_ractor_sleeper_threads_dec(rb_ractor_t *r)
{
    r->threads.sleeper--;
}

static inline void
rb_ractor_sleeper_threads_clear(rb_ractor_t *r)
{
    r->threads.sleeper = 0;
}

static inline int
rb_ractor_sleeper_thread_num(rb_ractor_t *r)
{
    return r->threads.sleeper;
}

static inline void
rb_ractor_thread_switch(rb_ractor_t *cr, rb_thread_t *th)
{
  if (cr->threads.running_ec != th->ec) {
        if (0) fprintf(stderr, "rb_ractor_thread_switch ec:%p->%p\n",
                       (void *)cr->threads.running_ec, (void *)th->ec);
    }
    else {
        return;
    }

    if (cr->threads.running_ec != th->ec) {
        th->running_time_us = 0;
    }

    cr->threads.running_ec = th->ec;

    VM_ASSERT(cr == GET_RACTOR());
}

static inline void
rb_ractor_set_current_ec(rb_ractor_t *cr, rb_execution_context_t *ec)
{
#ifdef RB_THREAD_LOCAL_SPECIFIER
  #if __APPLE__
    rb_current_ec_set(ec);
  #else
    ruby_current_ec = ec;
  #endif
#else
    native_tls_set(ruby_current_ec_key, ec);
#endif

    if (cr->threads.running_ec != ec) {
        if (0) fprintf(stderr, "rb_ractor_set_current_ec ec:%p->%p\n",
                       (void *)cr->threads.running_ec, (void *)ec);
    }
    else {
        VM_ASSERT(0); // should be different
    }

    cr->threads.running_ec = ec;
}

void rb_vm_ractor_blocking_cnt_inc(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line);
void rb_vm_ractor_blocking_cnt_dec(rb_vm_t *vm, rb_ractor_t *cr, const char *file, int line);

uint32_t rb_ractor_id(const rb_ractor_t *r);

#if RACTOR_CHECK_MODE > 0
uint32_t rb_ractor_current_id(void);

static inline void
rb_ractor_setup_belonging_to(VALUE obj, uint32_t rid)
{
    VALUE flags = RBASIC(obj)->flags & 0xffffffff; // 4B
    RBASIC(obj)->flags = flags | ((VALUE)rid << 32);
}

static inline void
rb_ractor_setup_belonging(VALUE obj)
{
    rb_ractor_setup_belonging_to(obj, rb_ractor_current_id());
}

static inline uint32_t
rb_ractor_belonging(VALUE obj)
{
    if (SPECIAL_CONST_P(obj) || RB_OBJ_SHAREABLE_P(obj)) {
        return 0;
    }
    else {
        return RBASIC(obj)->flags >> 32;
    }
}

static inline VALUE
rb_ractor_confirm_belonging(VALUE obj)
{
    uint32_t id = rb_ractor_belonging(obj);

    if (id == 0) {
        if (UNLIKELY(!rb_ractor_shareable_p(obj))) {
            rp(obj);
            rb_bug("id == 0 but not shareable");
        }
    }
    else if (UNLIKELY(id != rb_ractor_current_id())) {
        if (rb_ractor_shareable_p(obj)) {
            // ok
        }
        else {
            rp(obj);
            rb_bug("rb_ractor_confirm_belonging object-ractor id:%u, current-ractor id:%u", id, rb_ractor_current_id());
        }
    }
    return obj;
}
#else
#define rb_ractor_confirm_belonging(obj) obj
#endif
