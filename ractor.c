// Ractor implementation

#include "ruby/ruby.h"
#include "ruby/thread.h"
#include "ruby/ractor.h"
#include "ruby/re.h"
#include "ruby/thread_native.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "ractor_core.h"
#include "internal/array.h"
#include "internal/complex.h"
#include "internal/cont.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/array.h"
#include "internal/string.h"
#include "internal/variable.h"
#include "eval_intern.h"
#include "internal/io.h"
#include "internal/ractor.h"
#include "internal/rational.h"
#include "internal/re.h"
#include "internal/struct.h"
#include "internal/st.h"
#include "internal/thread.h"
#include "internal/vm.h"
#include "ruby/encoding.h"
#include "variable.h"
#include "shape.h"
#include "yjit.h"
#include "zjit.h"

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

    const rb_execution_context_t *ec = rb_current_ec_noinline();
    if (ec) {
        rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
        VM_ASSERT(!cr->malloc_gc_disabled);
        cr->malloc_gc_disabled = true;
    }

#if RACTOR_CHECK_MODE > 0
    if (ec != NULL) {
        rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
        r->sync.locked_by = rb_ractor_self(cr);
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

    const rb_execution_context_t *ec = rb_current_ec_noinline();
    if (ec) {
        rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
        VM_ASSERT(cr->malloc_gc_disabled);
        cr->malloc_gc_disabled = false;
    }

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

static int
mark_targeted_hook_list(st_data_t key, st_data_t value, st_data_t _arg)
{
    rb_hook_list_t *hook_list = (rb_hook_list_t*)value;

    if (hook_list->type == hook_list_type_targeted_iseq) {
        rb_gc_mark((VALUE)key);
    }
    else {
        rb_method_definition_t *def = (rb_method_definition_t*)key;
        RUBY_ASSERT(hook_list->type == hook_list_type_targeted_def);
        rb_gc_mark(def->body.bmethod.proc);
    }
    rb_hook_list_mark(hook_list);

    return ST_CONTINUE;
}

static void
ractor_mark_unshareable_parts(rb_ractor_t *r)
{
    /* A single VALUE slot written by the owner in one word, so any GC reads it safely.
     * Its target belongs to another Ractor, so containment makes a foreign marker skip
     * it. */
    rb_gc_mark(r->r_stdin);
    rb_gc_mark(r->r_stdout);
    rb_gc_mark(r->r_stderr);
    rb_gc_mark(r->verbose);
    rb_gc_mark(r->debug);

    // mark the received messages (the structures the owner mutates guard themselves)
    ractor_sync_mark(r);

    /* Structures the owner mutates while running follow. */

    rb_hook_list_mark(&r->pub.hooks);
    if (r->pub.targeted_hooks.num_entries) {
        st_foreach(&r->pub.targeted_hooks, mark_targeted_hook_list, 0);
    }

    if (r->threads.cnt > 0) {
        rb_thread_t *th = 0;
        ccan_list_for_each(&r->threads.set, th, lt_node) {
            VM_ASSERT(th != NULL);
            rb_gc_mark(th->self);

            /* A thread's ec lives inside the root fiber struct and is freed with that
             * fiber's wrapper object, so keep the fiber wrappers alive from here too. */
            if (th->root_fiber) {
                VALUE root_fiber_self = rb_fiberptr_self(th->root_fiber);
                if (root_fiber_self) rb_gc_mark(root_fiber_self);
            }
            /* The ec sits inside its fiber, so marking that fiber's wrapper scans the ec
             * as well.  Only when there is no wrapper yet (mid-creation, teardown) does
             * the ec need marking of its own. */
            VALUE ec_fiber_self = (th->ec && th->ec->fiber_ptr) ? rb_fiberptr_self(th->ec->fiber_ptr) : 0;
            if (ec_fiber_self) {
                rb_gc_mark(ec_fiber_self);
            }
            else if (th->ec) {
                rb_execution_context_mark(th->ec);
            }

            /* Root the thread's remaining possessions directly as well; thgroup in
             * particular has no other root. */
            rb_thread_mark_owned_roots(th);
        }
    }

    ractor_local_storage_mark(r);
}

static void
ractor_mark(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;

    /* Only the wrapper's direct references: following an unshareable object from the
     * shareable wrapper would break the shref rule.  Unshareable roots are marked by the
     * root scan (rb_ractor_mark_local_roots); zombie_objspaces covers the terminated. */
    rb_gc_mark(r->loc);
    rb_gc_mark(r->name);
    /* The default port is shareable, so following it breaks no rule.  Other Ractors
     * still send/value through it after termination, and once a terminated Ractor left
     * both the set and zombie_objspaces (orphan-merged) this marker is its only cover. */
    rb_gc_mark(r->sync.default_port_value);
    /* A single-objspace impl (mmtk) has no zombie_objspaces and no pin/shref bits, so
     * the root scan cannot reach a terminated Ractor's legacy value, queue or in-flight
     * payloads; and no shref rule forbids following them from the wrapper. */
    if (!rb_gc_multi_objspace_p()) {
        ractor_mark_unshareable_parts(r);
        rb_ractor_mark_in_flight_for_single_objspace(r);
    }
}

/* Mark the GC roots reachable from Ractor r's C structs.  A local GC cannot rely on the
 * heap Ractor and Thread wrapper objects, which may live in another objspace, so this
 * Ractor's own possessions are rooted directly from here. */
void
rb_ractor_mark_local_roots(rb_ractor_t *r)
{
    if (r->postmortem) {
        /* The final self collection: everything else -- the Thread and Fiber
         * wrappers, stdio, stack leftovers -- is what it exists to reclaim. */
        rb_ractor_mark_terminated_join_value(r);
        rb_gc_mark_vm_stack_values((long)r->registered_marks_cnt, r->registered_marks);
        return;
    }

    rb_gc_mark(r->loc);
    rb_gc_mark(r->name);
    /* Only the root scan calls this: a local GC for itself, a global GC for the whole
     * set under the barrier.  A terminated Ractor has left the set; zombie_objspaces
     * covers it instead. */
    VM_ASSERT(r == rb_current_ractor_raw(false) || rb_gc_during_global_gc_p());
    VM_ASSERT(!rb_ractor_status_p(r, ractor_terminated));
    ractor_mark_unshareable_parts(r);

    /* This Ractor's rb_gc_register_mark_object pins, treated conservatively: a local GC
     * marks only its own residents and leaves foreign or shareable entries to their
     * owner or to the global GC. */
    rb_gc_mark_vm_stack_values((long)r->registered_marks_cnt, r->registered_marks);

}

/* Mark and pin a terminated, unfreed Ractor's return value (legacy); the global GC
 * calls this via zombie_objspaces.  Pinned because compaction does not update C-struct
 * slots.  The default port is covered by the mutual wrapper/port marking instead. */
void
rb_ractor_mark_terminated_join_value(rb_ractor_t *r)
{
    VALUE slots[] = {
        r->sync.legacy,
    };
    rb_gc_mark_vm_stack_values((long)numberof(slots), slots);
}

/* Move src's rb_gc_register_mark_object pins to dst.  Called before merging src's
 * objspace into dst, so a pinned object never loses its root in between.  An absorb can
 * run during a GC sweep, so plain realloc keeps it from re-entering GC. */
void
rb_ractor_absorb_registered_marks(rb_ractor_t *dst, rb_ractor_t *src)
{
    if (src->registered_marks_cnt == 0) return;
    size_t need = dst->registered_marks_cnt + src->registered_marks_cnt;
    if (need > dst->registered_marks_capa) {
        size_t nc = dst->registered_marks_capa ? dst->registered_marks_capa : 64;
        while (nc < need) nc *= 2;
        VALUE *p = realloc(dst->registered_marks, nc * sizeof(VALUE));
        if (!p) rb_bug("rb_ractor_absorb_registered_marks: out of memory");
        dst->registered_marks = p;
        dst->registered_marks_capa = nc;
    }
    MEMCPY(dst->registered_marks + dst->registered_marks_cnt,
           src->registered_marks, VALUE, src->registered_marks_cnt);
    dst->registered_marks_cnt = need;
    src->registered_marks_cnt = 0;
}

static int
free_targeted_hook_lists(st_data_t key, st_data_t val, st_data_t _arg)
{
    rb_hook_list_t *hook_list = (rb_hook_list_t*)val;
    rb_hook_list_free(hook_list);
    return ST_DELETE;
}

static void
free_targeted_hooks(st_table *hooks_tbl)
{
    st_foreach(hooks_tbl, free_targeted_hook_lists, 0);
}

static void
ractor_free(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;
    RUBY_DEBUG_LOG("free r:%d", rb_ractor_id(r));

    free_targeted_hooks(&r->pub.targeted_hooks);
    rb_native_mutex_destroy(&r->sync.lock);
#ifdef RUBY_THREAD_WIN32_H
    rb_native_cond_destroy(&r->sync.wakeup_cond);
#endif
    ractor_local_storage_free(r);
    rb_hook_list_free(&r->pub.hooks);
    rb_st_free_embedded_table(&r->pub.targeted_hooks);

    if (r->newobj_cache) {
        RUBY_ASSERT(r == ruby_single_main_ractor);

        rb_gc_ractor_cache_free(r->newobj_cache);
        r->newobj_cache = NULL;
    }

    /* Died unjoined and the handle is collected: nobody can inherit it.  We are in a
     * sweep under the global GC barrier, so disown the zombie_objspaces entry and post
     * the merge to main.  main itself only gets here in the free-at-exit walk: leave it
     * and its objspace to VM destruct. */
    if (r->objspace && !r->main_ractor) {
        rb_gc_objspace_disown(r->objspace);
        r->objspace = NULL;
    }

    ractor_sync_free(r);

    if (r->in_terminated_set) {
        rb_native_mutex_lock(&GET_VM()->gc.registered_globals.lock);
        ccan_list_del(&r->vmlr_node);
        r->in_terminated_set = false;
        rb_native_mutex_unlock(&GET_VM()->gc.registered_globals.lock);
    }

    /* An orphan (unjoined) Ractor hands its rb_gc_register_mark_object pins to main
     * before its objspace is absorbed; the join path does the same for the joiner.
     * Both happen before the objspace merge, so no window has unmoved registrations. */
    if (!r->main_ractor) {
        rb_ractor_absorb_registered_marks(GET_VM()->ractor.main_ractor, r);
    }
    free(r->registered_marks);
    r->registered_marks = NULL;
    r->registered_marks_cnt = r->registered_marks_capa = 0;

    free(r->pin_capture);
    r->pin_capture = NULL;
    r->pin_capture_cnt = r->pin_capture_capa = 0;

    if (!r->main_ractor) {
        SIZED_FREE(r);
    }
}

static size_t
ractor_memsize(const void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;

    // TODO: more correct?
    return sizeof(rb_ractor_t) + ractor_sync_memsize(r);
}

static void
ractor_update_references(void *ptr)
{
    /* registered_marks are pinned (marked by rb_gc_mark_vm_stack_values), so
     * compaction does not need to update them. */
}

static const rb_data_type_t ractor_data_type = {
    "ractor",
    {
        ractor_mark,
        ractor_free,
        ractor_memsize,
        ractor_update_references,
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

#define MAIN_RACTOR_ID 1
static rb_atomic_t ractor_last_id = MAIN_RACTOR_ID;

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

    /* Just before the process goes multi-objspace.  Incremental marking only runs in a
     * single-objspace world, so finish any cycle in progress before the count changes. */
    if (vm->ractor.cnt == 1) {
        rb_gc_finish_in_flight_gc();
    }

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
    rb_yjit_invalidate_single_ractor();
    rb_zjit_invalidate_single_ractor();

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
            /* The child is in the set and enumerated on its own now, so drop the cover
             * through its creator and avoid enumerating it twice.  Cleared under the
             * same VM lock that added it, so no whole-VM walk sees both. */
            rb_ractor_t *cur = rb_current_ractor_raw(false);
            if (cur && cur->creating_child_objspace == r->objspace) {
                cur->creating_child_objspace = NULL;
            }
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
            /* As in the multi-Ractor branch: the child joined the set, so drop the
             * creator's cover, or a global GC enumerates the child's objspace twice and
             * sweeps its live main Thread and root Fiber. */
            rb_ractor_t *cur = rb_current_ractor_raw(false);
            if (cur && cur->creating_child_objspace == r->objspace) {
                cur->creating_child_objspace = NULL;
            }
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

        /* A single-objspace impl has no zombie_objspaces, so nothing roots the
         * registered_marks of a Ractor that left the set; track it in a separate list
         * until ractor_free. */
        if (!rb_gc_multi_objspace_p()) {
            rb_native_mutex_lock(&vm->gc.registered_globals.lock);
            ccan_list_add(&vm->ractor.terminated_set, &cr->vmlr_node);
            cr->in_terminated_set = true;
            rb_native_mutex_unlock(&vm->gc.registered_globals.lock);
        }

        if (vm->ractor.cnt <= 2 && vm->ractor.sync.terminate_waiting) {
            rb_native_cond_signal(&vm->ractor.sync.terminate_cond);
        }

        rb_gc_ractor_cache_free(cr->newobj_cache);
        cr->newobj_cache = NULL;

        /* The objspace loses its owning thread: keep it enumerable until inheritance
         * merges it.  Register in zombie_objspaces BEFORE decrementing cnt: other
         * Ractors read rb_gc_single_objspace_p lock-free, and the other order opens a
         * cnt==1-no-zombie window where a GC skips shareable pinning and collects
         * objects (a cc, say) reachable only through this objspace. */
        if (cr->objspace) {
            /* The final self collection already ran (ractor_postmortem_collect),
             * so the entry measures exactly the pages the joiner will inherit. */
            rb_gc_objspace_retire(&cr->objspace);
        }
        vm->ractor.cnt--;

        ractor_status_set(cr, ractor_terminated);
    }
    RB_VM_UNLOCK();
}

/* The dying thread's final collection of its own objspace, and the capture of what it
 * must free itself.  Called with the GVL still held: a concurrent global GC waits for
 * this thread's safepoint, so the collection is lock-free like any local GC. */
static void
ractor_postmortem_collect(rb_thread_t *th, struct rb_ractor_postmortem_frees *pf)
{
    rb_ractor_t *const cr = th->ractor;
    VM_ASSERT(cr != GET_VM()->ractor.main_ractor);
    VM_ASSERT(th->ec != NULL);

    struct rb_fiber_struct *const fiber = th->ec->fiber_ptr;
    const bool fiber_wrapped = fiber && rb_fiberptr_self(fiber) != 0;

    /* With a thread-event hook registered the callbacks may retain any Ractor's Thread
     * object (rb_internal_thread_event_hook_t), and such references are invisible to
     * the reduced roots: keep the ordinary retire roots, wrappers survive to absorb. */
    cr->postmortem = rb_gc_multi_objspace_p() && !rb_thread_event_hooks_registered_p();
    rb_gc_objspace_postmortem_self();

    /* Only what this collection provably swept (wrapper gone, struct deferred with an
     * in-band mark) may be touched after vm_remove_ractor unlinks the Ractor. */
    pf->th = (th->self == 0) ? th : NULL;
    pf->fiber = (fiber_wrapped && rb_fiberptr_self(fiber) == 0) ? fiber : NULL;
}

void
rb_ractor_postmortem_free(const struct rb_ractor_postmortem_frees *pf)
{
    if (pf->fiber == NULL && pf->th == NULL) return;

    /* The frees below resolve their objspace through the TLS ec, which sits inside
     * pf->fiber and leads to the retired Ractor: cut the resolution off so they fall
     * back to the main objspace.  (The MN epilogue has already done this.) */
#ifdef RB_THREAD_LOCAL_SPECIFIER
    rb_current_ec_set(NULL);
#else
    native_tls_set(ruby_current_ec_key, NULL);
#endif

    /* the fiber struct embeds the thread's final ec, so free it first */
    if (pf->fiber) rb_fiber_free_body(pf->fiber);
    if (pf->th) rb_thread_free_body(pf->th);
}

static VALUE
ractor_alloc(VALUE klass)
{
    rb_ractor_t *r;
    VALUE rv = TypedData_Make_Struct(klass, rb_ractor_t, &ractor_data_type, r);
    FL_SET_RAW(rv, RUBY_FL_SHAREABLE);
    rb_gc_obj_became_shareable(rv);
    r->pub.self = rv;
    r->next_ec_serial = 1;
    VM_ASSERT(ractor_status_p(r, ractor_created));
    return rv;
}

static rb_ractor_t _main_ractor = {
    .loc = Qnil,
    .name = Qnil,
    .pub.id = MAIN_RACTOR_ID,
    .pub.self = Qnil,
    .next_ec_serial = 1,
    .main_ractor = true,
};

rb_ractor_t *
rb_ractor_main_alloc(void)
{
    rb_ractor_t *r = &_main_ractor;
    /* The main Ractor is allocated before its objspace exists, so its newobj cache is
     * created later in Init_BareVM, once rb_gc_init_objspaces has set r->objspace. */
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
    /* Another thread may have held the lock at fork, so rebuild it in the child (the
     * same reason generic_fields_lock is re-initialized at fork).  The registry's list
     * head is left alone: the nodes of surviving couriers are still linked into it. */
    rb_native_mutex_initialize(&vm->ractor.move_courier_registry_lock);
    /* Only main survives a fork: the holds of dead Ractors and of critical sections are
     * gone, leaving main's own disable. */
    rb_gc_disable_holders_atfork();
    /* Only the main Ractor survives a fork, so drop the creation cover.  The set was
     * just emptied by rb_vm_living_threads_init, and zombie_objspaces still holds the
     * non-main objspaces that terminate_atfork parked there for the orphan merge. */
    th->ractor->creating_child_objspace = NULL;
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
    /* In a forked child every other Ractor is terminated-unjoined, so keep its objspace
     * enumerable until a join or a global GC merges it. */
    if (r->objspace) {
        rb_gc_objspace_retire(&r->objspace);
    }
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
    r->gen_fields_capturing = false;
    r->pin_capture = NULL;
    r->pin_capture_cnt = r->pin_capture_capa = 0;
    r->sending_basket = NULL;
    st_init_existing_numtable_with_size(&r->pub.targeted_hooks, 0);
    r->pub.hooks.type = hook_list_type_ractor_local;

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
        name = RB_OBJ_SET_SHAREABLE(rb_str_new_frozen(name));
    }

    if (!SPECIAL_CONST_P(loc)) RB_OBJ_SET_SHAREABLE(loc);
    r->loc = loc;
    r->name = name;
}

void
rb_ractor_main_setup(rb_vm_t *vm, rb_ractor_t *r, rb_thread_t *th)
{
    VALUE rv = r->pub.self = TypedData_Wrap_Struct(rb_cRactor, &ractor_data_type, r);
    FL_SET_RAW(r->pub.self, RUBY_FL_SHAREABLE);
    rb_gc_obj_became_shareable(r->pub.self);
    ractor_init(r, Qnil, Qnil);
    r->threads.main = th;
    rb_ractor_living_threads_insert(r, th);
    rb_ractor_setup_default_port(r);

    RB_GC_GUARD(rv);
}

static VALUE
ractor_create(rb_execution_context_t *ec, VALUE self, VALUE loc, VALUE name, VALUE args, VALUE block)
{
    VALUE rv = ractor_alloc(self);
    rb_ractor_t *r = RACTOR_PTR(rv);
    ractor_init(r, name, loc);

    r->pub.id = ractor_next_id();
    RUBY_DEBUG_LOG("r:%u", r->pub.id);

    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    r->verbose = cr->verbose;
    r->debug = cr->debug;

    /* Every Ractor has an objspace, and it must exist before its thread runs: the
     * first allocation goes there through rb_gc_get_objspace. */
    r->objspace = rb_gc_objspace_alloc();

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

/* The dying thread's last work inside its Ractor.  The order is the point: a joiner woken
 * before the collection spins in ractor_value for the whole of it. */
void
rb_ractor_postmortem(rb_thread_t *th, struct rb_ractor_postmortem_frees *pf)
{
    ractor_postmortem_collect(th, pf);
    ractor_send_exit_tokens(th->ec, th->ractor);
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


/* Remove a child that never started (send_parameters failed during creation).  The
 * creator calls this (rb_ractor_living_threads_remove assumes the current Ractor);
 * leaving the set and disowning the objspace share one VM-lock section, no window. */
void
rb_ractor_cancel_creation(rb_ractor_t *r, rb_thread_t *th)
{
    RACTOR_LOCK(r);
    {
        ccan_list_del(&th->lt_node);
        r->threads.cnt--;
    }
    RACTOR_UNLOCK(r);

    RB_VM_LOCK();
    {
        rb_vm_t *vm = th->vm;
        VM_ASSERT(vm->ractor.cnt > 1);
        ccan_list_del(&r->vmlr_node);
        vm->ractor.cnt--;
        /* Give back the blocking count vm_insert_ractor took at insert time.  A child
         * that never ran has no chance to decrement it, and without this the
         * blocking_cnt <= cnt invariant breaks on the next insert. */
        VM_ASSERT(r->status_ == ractor_blocking);
        VM_ASSERT(vm->ractor.blocking_cnt > 0);
        vm->ractor.blocking_cnt--;

        rb_gc_ractor_cache_free(r->newobj_cache);
        r->newobj_cache = NULL;

        if (r->objspace) {
            rb_gc_objspace_disown(r->objspace);
            r->objspace = NULL;
        }
        r->status_ = ractor_terminated;
    }
    RB_VM_UNLOCK();
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

    RB_VM_LOCK();
    {
        ractor_terminal_interrupt_all(vm); // kill all ractors
    }
    RB_VM_UNLOCK();
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
#ifdef RUBY_THREAD_PTHREAD_H
            while (vm->ractor.sched.barrier_waiting) {
                // A barrier is waiting. Threads relinquish the VM lock before joining the barrier and
                // since we just acquired the VM lock back, we're blocking other threads from joining it.
                // We loop until the barrier is over. We can't join this barrier because our thread isn't added to
                // running_threads until the call below to `rb_add_running_thread`.
                RB_VM_UNLOCK();
                unsigned int lev;
                RB_VM_LOCK_ENTER_LEV_NB(&lev);
            }
#endif
            rb_add_running_thread(rb_ec_thread_ptr(cr->threads.running_ec));
            rb_vm_ractor_blocking_cnt_dec(vm, cr, __FILE__, __LINE__);

            ractor_terminal_interrupt_all(vm);
        }
    }
    RB_VM_UNLOCK();

    /* Every other Ractor is dead.  main inherits all uninherited objspaces, so the
     * remaining at-exit work (finalizers, IO flush, free-at-exit) sees every object. */
    rb_gc_objspace_absorb_all_zombies();
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
 *  Ports may be closed explicitly with Ractor::Port#close
 *  and are closed implicitly when a Ractor terminates.
 *
 *     port = Ractor::Port.new
 *     port.close
 *     port << "test"  # Ractor::ClosedError
 *     port.receive    # Ractor::ClosedError
 *
 *  ClosedError is a descendant of StopIteration, so the closing of a port will break
 *  out of loops without propagating the error.
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
 *  Raised on Ractor#join or Ractor#value if there was an uncaught exception in the Ractor.
 *  Its +cause+ will contain the original exception, and +ractor+ is the original ractor
 *  it was raised in.
 *
 *     r = Ractor.new { raise "Something weird happened" }
 *
 *     begin
 *       r.value
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
 *  Raised on an attempt to access an object which was moved in Ractor#send or Ractor::Port#send.
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
 *  or Ractor::Port#send. Any attempt to access the object results in Ractor::MovedError.
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
        if (UNLIKELY(cr->r_stdin == 0)) {
            cr->r_stdin = rb_io_prep_stdin();
        }
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
        if (UNLIKELY(cr->r_stdout == 0)) {
            cr->r_stdout = rb_io_prep_stdout();
        }
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
        if (UNLIKELY(cr->r_stderr == 0)) {
            cr->r_stderr = rb_io_prep_stderr();
        }
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

st_table *
rb_ractor_targeted_hooks(rb_ractor_t *cr)
{
    return &cr->pub.targeted_hooks;
}

static void
rb_obj_set_shareable_no_assert(VALUE obj)
{
    /* make_shareable_check_shareable refuses an IO, because the traversal cannot reach
     * the VALUE members inside its fptr. */
    VM_ASSERT(!RB_TYPE_P(obj, T_FILE));

    FL_SET_RAW(obj, FL_SHAREABLE);
    rb_gc_obj_became_shareable(obj);

    /* A T_OBJECT can have a fields imemo too (too_complex and friends), and an imemo
     * born while its owner was unshareable stays unshareable
     * (imemo_fields_complex_from_obj), so align it here. */
    if (rb_obj_gen_fields_p(obj) || BUILTIN_TYPE(obj) == T_OBJECT) {
        /* obj is shareable already, so rb_obj_fields_no_ractor_check finds the right
         * table.  Make the fields imemo itself shareable and record shrefs for the
         * hidden field values the traversal never reaches. */
        VALUE fields = rb_obj_fields_no_ractor_check(obj);
        if (imemo_type_p(fields, imemo_fields)) {
            // no recursive mark
            FL_SET_RAW(fields, FL_SHAREABLE);
            rb_gc_obj_became_shareable(fields);
            // Field values the traversal never reaches (hidden internal ivars, say)
            // can stay unshareable, so record their shrefs to keep the shareable
            // fields imemo's edges correct.
            rb_imemo_fields_record_shrefs(fields);
        }
    }
}

#ifndef STRICT_VERIFY_SHAREABLE
#define STRICT_VERIFY_SHAREABLE 0
#endif

bool
rb_ractor_verify_shareable(VALUE obj)
{
#if STRICT_VERIFY_SHAREABLE
    rb_gc_verify_shareable(obj);
#endif
    return true;
}

VALUE
rb_obj_set_shareable(VALUE obj)
{
    RUBY_ASSERT(!RB_SPECIAL_CONST_P(obj));

    rb_obj_set_shareable_no_assert(obj);
    RUBY_ASSERT(rb_ractor_verify_shareable(obj));

    return obj;
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

// Traverse obj's children via its GC mark function. Returns 1 to stop.
static int
obj_traverse_reachable(VALUE obj, struct obj_traverse_data *data)
{
    struct obj_traverse_callback_data d = {
        .stop = false,
        .data = data,
    };
    RB_VM_LOCKING_NO_BARRIER() {
        rb_objspace_reachable_objects_from(obj, obj_traverse_reachable_i, &d);
    }
    return d.stop;
}

static struct st_table *
obj_traverse_rec(struct obj_traverse_data *data)
{
    if (UNLIKELY(!data->rec)) {
        data->rec_hash = rb_ident_hash_new();
        rb_obj_hide(data->rec_hash);
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

    if (rb_obj_shape_has_ivars(obj)) {
        struct obj_traverse_callback_data d = {
            .stop = false,
            .data = data,
        };
        rb_ivar_foreach(obj, obj_traverse_ivar_foreach_i, (st_data_t)&d);
        if (d.stop) return 1;
    }

    switch (BUILTIN_TYPE(obj)) {
      // no child node
      case T_STRING:
      case T_FLOAT:
      case T_BIGNUM:
      case T_REGEXP:
      case T_SYMBOL:
        break;

      case T_OBJECT:
        /* Instance variables already traversed. */
        break;

      case T_ARRAY:
        {
            rb_ary_cancel_sharing(obj);

            for (int i = 0; i < RARRAY_LENINT(obj); i++) {
                VALUE e = RARRAY_AREF(obj, i);
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
            long len = RSTRUCT_LEN_RAW(obj);
            const VALUE *ptr = RSTRUCT_CONST_PTR(obj);

            for (long i=0; i<len; i++) {
                if (obj_traverse_i(ptr[i], data)) return 1;
            }
        }
        break;

      case T_MATCH:
        if (obj_traverse_i(RMATCH(obj)->str, data)) return 1;
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
        {
            void *const ptr = RTYPEDDATA_GET_DATA(obj);
            const rb_data_type_t *type = RTYPEDDATA_TYPE(obj);

            if (!ptr || !type->function.dmark) {
                // no references (the class and ivars are handled elsewhere)
            }
            else if (type->flags & RUBY_TYPED_DECL_MARKING) {
                const size_t *offsets = (const size_t *)(uintptr_t)type->function.dmark;
                for (; *offsets != RUBY_REF_END; offsets++) {
                    VALUE ref = *(VALUE *)((char *)ptr + *offsets);
                    if (obj_traverse_i(ref, data)) return 1;
                }
            }
            else {
                if (obj_traverse_reachable(obj, data)) return 1;
            }
        }
        break;

      case T_IMEMO:
        // TODO: Not sure this can actually happen; traverse rather than crash.
        if (obj_traverse_reachable(obj, data)) return 1;
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
    if (RB_TYPE_P(obj, T_FILE)) {
        return false;
    }
    else if (!RB_TYPE_P(obj, T_DATA)) {
        return true;
    }
    else {
        const rb_data_type_t *type = RTYPEDDATA_TYPE(obj);
        if (type->flags & RUBY_TYPED_FROZEN_SHAREABLE) {
            return true;
        }
    }

    return false;
}

static void
make_shareable_freeze(VALUE obj)
{
    VALUE klass = RBASIC_CLASS(obj);
    if (klass == rb_cString && BASIC_OP_UNREDEFINED_P(BOP_FREEZE, STRING_REDEFINED_OP_FLAG)) {
        rb_str_freeze(obj);
    }
    else if (klass == rb_cArray && BASIC_OP_UNREDEFINED_P(BOP_FREEZE, ARRAY_REDEFINED_OP_FLAG)) {
        rb_ary_freeze(obj);
    }
    else if (klass == rb_cHash && BASIC_OP_UNREDEFINED_P(BOP_FREEZE, HASH_REDEFINED_OP_FLAG)) {
        rb_hash_freeze(obj);
    }
    else {
        rb_funcall(obj, idFreeze, 0);
    }
}

static enum obj_traverse_iterator_result
make_shareable_check_shareable_freeze(VALUE obj, enum obj_traverse_iterator_result result)
{
    if (!RB_OBJ_FROZEN_RAW(obj)) {
        make_shareable_freeze(obj);

        if (UNLIKELY(!RB_OBJ_FROZEN_RAW(obj))) {
            rb_raise(rb_eRactorError, "#freeze does not freeze object correctly");
        }

        if (RB_OBJ_SHAREABLE_P(obj)) {
            return traverse_skip;
        }
    }

    return result;
}

static int obj_refer_only_shareables_p(VALUE obj);

static enum obj_traverse_iterator_result
make_shareable_check_shareable(VALUE obj)
{
    VM_ASSERT(!SPECIAL_CONST_P(obj));

    if (rb_ractor_shareable_p(obj)) {
        return traverse_skip;
    }
    else if (!allow_frozen_shareable_p(obj)) {
        if (!RB_TYPE_P(obj, T_DATA)) {
            rb_raise(rb_eRactorError,
                     "can not make shareable object for %+"PRIsVALUE, obj);
        }
        else if (RTYPEDDATA_TYPE(obj)->flags & RUBY_TYPED_FROZEN_SHAREABLE_NO_REC) {
            if (obj_refer_only_shareables_p(obj)) {
                make_shareable_check_shareable_freeze(obj, traverse_skip);
                RB_OBJ_SET_SHAREABLE(obj);
                return traverse_skip;
            }
            else {
                rb_raise(rb_eRactorError,
                         "can not make shareable object for %+"PRIsVALUE" because it refers unshareable objects", obj);
            }
        }
        else if (rb_obj_is_proc(obj)) {
            rb_proc_ractor_make_shareable(obj, Qundef);
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

    return make_shareable_check_shareable_freeze(obj, traverse_cont);
}

static enum obj_traverse_iterator_result
mark_shareable(VALUE obj)
{
    if (RB_BUILTIN_TYPE(obj) == T_STRING) {
        rb_str_make_independent(obj);
    }

    rb_obj_set_shareable_no_assert(obj);
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

static VALUE ractor_copy(VALUE obj); // defined below

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
    else if (RB_OBJ_FROZEN_RAW(obj) &&
             RB_TYPE_P(obj, T_DATA) &&
             (RTYPEDDATA_TYPE(obj)->flags & RUBY_TYPED_FROZEN_SHAREABLE_NO_REC)) {
        // Similar to RUBY_TYPED_FROZEN_SHAREABLE, but the object is only
        // shareable if all reachable objects are already shareable (they
        // are not made shareable recursively).
        if (obj_refer_only_shareables_p(obj)) {
            mark_shareable(obj);
            return traverse_skip;
        }
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

static enum obj_traverse_iterator_result
null_leave(VALUE obj)
{
    return traverse_cont;
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

    /* old -> new map, a plain st_table: an OLD key may live in another Ractor's
     * objspace and must not become a GC edge here (marking a freed foreign key is a
     * UAF).  Keys compare by address; replacements stay alive via rec_keepalive. */
    st_table *rec;
    VALUE rec_keepalive;

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
        data->rec = st_init_numtable();
        data->rec_keepalive = rb_ary_hidden_new(0);
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

    /* Dedup before enter_func, so a revisited shared/cyclic node reuses its recorded
     * replacement; otherwise the copy path would build a wasteful temporary holding a
     * containment-breaking cross-objspace edge. */
    if (UNLIKELY(st_lookup(obj_traverse_replace_rec(data), (st_data_t)obj, &replacement))) {
        data->replacement = (VALUE)replacement;
        return 0;
    }

    switch (data->enter_func(obj, data)) {
      case traverse_cont: break;
      case traverse_skip: return 0; // skip children
      case traverse_stop: return 1; // stop search
    }

    replacement = (st_data_t)data->replacement;
    st_insert(obj_traverse_replace_rec(data), (st_data_t)obj, replacement);
    if (!RB_SPECIAL_CONST_P((VALUE)replacement)) {
        rb_ary_push(data->rec_keepalive, (VALUE)replacement);
    }

    if (!data->move) {
        obj = replacement;
    }

#define CHECK_AND_REPLACE(parent_obj, v) do { \
    VALUE _val = (v); \
    if (obj_traverse_replace_i(_val, data)) { return 1; } \
    else if (data->replacement != _val)     { RB_OBJ_WRITE(parent_obj, &v, data->replacement); } \
} while (0)

    if (UNLIKELY(rb_obj_gen_fields_p(obj))) {
        VALUE fields_obj = rb_obj_fields_no_ractor_check(obj);

        if (UNLIKELY(rb_obj_shape_complex_p(obj))) {
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
        break;
      case T_STRING:
        rb_str_make_independent(obj);
        break;

      case T_OBJECT:
        {
            VALUE fields_obj = ROBJECT_FIELDS_OBJ(obj);
            shape_id_t shape_id = RBASIC_SHAPE_ID(fields_obj);
            if (rb_shape_complex_p(shape_id)) {
                struct obj_traverse_replace_callback_data d = {
                    .stop = false,
                    .data = data,
                    .src = obj,
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
                attr_index_t len = RSHAPE_LEN(shape_id);
                VALUE *ptr = rb_imemo_fields_ptr(fields_obj);

                for (attr_index_t i = 0; i < len; i++) {
                    CHECK_AND_REPLACE(obj, ptr[i]);
                }
            }
        }
        break;

      case T_ARRAY:
        {
            rb_ary_cancel_sharing(obj);

            for (int i = 0; i < RARRAY_LENINT(obj); i++) {
                VALUE e = RARRAY_AREF(obj, i);

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
            long len = RSTRUCT_LEN_RAW(obj);
            const VALUE *ptr = RSTRUCT_CONST_PTR(obj);

            for (long i=0; i<len; i++) {
                CHECK_AND_REPLACE(obj, ptr[i]);
            }
        }
        break;

      case T_MATCH:
        CHECK_AND_REPLACE(obj, RMATCH(obj)->str);
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
        .rec_keepalive = Qfalse,
        .replacement = Qundef,
        .move = move,
    };

    int stopped = obj_traverse_replace_i(obj, &data);

    /* The enter and leave functions report failure with traverse_stop rather than by
     * raising, so this is the only place the table is freed. */
    if (data.rec) st_free_table(data.rec);
    RB_GC_GUARD(data.rec_keepalive);

    if (stopped) {
        return Qundef;
    }
    else {
        return data.replacement;
    }
}

/* Move courier: serializes the payload of Ractor#send(move: true) into an xmalloc'd
 * structure that belongs to no objspace, so no sender GC can mark, sweep, compact or
 * race with it.  A node array with id references handles sharing and cycles, and the
 * receiver rebuilds it in its own objspace in two passes. */

enum move_node_kind {
    MOVE_KIND_REF,       /* an immediate or a shareable object: carried by value */
    MOVE_KIND_STRING,
    MOVE_KIND_ARRAY,
    MOVE_KIND_HASH,
    MOVE_KIND_OBJECT,
    MOVE_KIND_STRUCT,
    MOVE_KIND_MATCH,
    MOVE_KIND_IO,
};

struct move_node {
    enum move_node_kind kind;
    bool frozen;
    /* The instance and generic ivars every non-REF node can have (a String or Array
     * can hold generic ivars too) */
    uint32_t niv;
    ID *iv_ids;          /* owned by the courier */
    uint32_t *iv_vals;   /* owned by the courier; node ids */
    union {
        VALUE ref;
        struct { char *ptr; long len; int encidx; VALUE klass; } str;        /* the courier owns ptr */
        struct { long len; uint32_t *elems; VALUE klass; } ary;              /* the courier owns elems */
        struct { long size; uint32_t *kv; uint32_t ifnone_id; bool compare_by_id; bool proc_default; VALUE klass; } hash; /* owns kv (2*size) */
        struct { VALUE klass; } obj;
        struct { long len; uint32_t *elems; VALUE klass; } strct; /* owns elems */
        struct { uint32_t regexp_id, str_id; int num_regs; void *regs; VALUE klass; } match; /* owns regs */
        struct {
            struct rb_io *fptr;  /* carried by pointer (it owns the fd) */
            VALUE klass;
            /* The sender-side VALUE members of fptr travel as ordinary child nodes:
             * capture detaches them from fptr (see the T_FILE case) and rebuild writes
             * them back into the receiving shell with RB_OBJ_WRITE. */
            uint32_t pathv_id, ecopts_id, wc_pre_ecopts_id, wc_asciicompat_id, timeout_id;
        } io;
    } u;
};

/* A child slot holds a node id, or -- with this bit set -- an index into c->refs.
 * The courier is in-process, so a shareable payload can travel as the VALUE itself
 * instead of costing a whole move_node; the registry marks and pins c->refs. */
#define MOVE_ID_REF_BIT 0x80000000u

struct rb_ractor_move_courier {
    struct move_node *nodes;
    uint32_t count;
    uint32_t capa;
    VALUE *refs;              /* shareable payloads, embedded by value */
    uint32_t refs_count;
    uint32_t refs_capa;
    uint32_t root;
    struct ccan_list_node reg_node;  /* in-flight courier registry (a GC root while it lives) */
};

/* VM-global list of move couriers in flight (vm->ractor.move_courier_registry).  A
 * courier is off-heap and carries shareable REFs as raw pointers; in some windows only
 * a transient (a stack-local message queue, say) reaches it, so a global GC could
 * collect the REFs.  Registered from build to free, marked and pinned by the global
 * GC's root pass (only a global GC frees shareable objects, so only it needs this).
 * add/remove run concurrently and take the lock; stop-the-world marking does not, which
 * is sound only because add/remove contain no safepoint (none may be added: a mark
 * could then see a half-linked list across the barrier). */

static void
move_courier_registry_add(struct rb_ractor_move_courier *c)
{
    rb_native_mutex_lock(&GET_VM()->ractor.move_courier_registry_lock);
    ccan_list_add(&GET_VM()->ractor.move_courier_registry, &c->reg_node);
    rb_native_mutex_unlock(&GET_VM()->ractor.move_courier_registry_lock);
}

static void
move_courier_registry_remove(struct rb_ractor_move_courier *c)
{
    rb_native_mutex_lock(&GET_VM()->ractor.move_courier_registry_lock);
    ccan_list_del(&c->reg_node);
    rb_native_mutex_unlock(&GET_VM()->ractor.move_courier_registry_lock);
}

void rb_ractor_move_courier_mark(struct rb_ractor_move_courier *c);

/* Called from the global GC's root pass; stop-the-world, so no lock. */
void
rb_ractor_move_courier_registry_mark(void)
{
    struct rb_ractor_move_courier *c;
    ccan_list_for_each(&GET_VM()->ractor.move_courier_registry, c, reg_node) {
        rb_ractor_move_courier_mark(c);
    }
}

struct move_build {
    struct rb_ractor_move_courier *c;
    st_table *seen;   /* src VALUE -> (node id + 1) */
    /* Copy mode: read the sources instead of taking them apart.  No husk, no buffer
     * hand-over, no freeing of the source's internals. */
    bool copy;
};

static uint32_t move_capture(struct move_build *b, VALUE obj);

static uint32_t
move_alloc_node(struct rb_ractor_move_courier *c)
{
    if (c->count == c->capa) {
        c->capa = c->capa ? c->capa * 2 : 8;
        REALLOC_N(c->nodes, struct move_node, c->capa);
    }
    uint32_t id = c->count++;
    /* Initialize to a harmless REF/Qnil so the courier mark (a GC root while sending)
     * is safe even mid-construction; a captured node overwrites it later. */
    c->nodes[id].kind = MOVE_KIND_REF;
    c->nodes[id].frozen = false;
    c->nodes[id].niv = 0;
    c->nodes[id].iv_ids = NULL;
    c->nodes[id].iv_vals = NULL;
    c->nodes[id].u.ref = Qnil;
    return id;
}

/* Embed a shareable payload by value and return its tagged child id.  No dedup: a REF
 * is the same word however often it appears, and an array of immediates would otherwise
 * pay a lookup and an insert per element. */
static uint32_t
move_alloc_ref(struct rb_ractor_move_courier *c, VALUE v)
{
    if (c->refs_count == c->refs_capa) {
        c->refs_capa = c->refs_capa ? c->refs_capa * 2 : 8;
        REALLOC_N(c->refs, VALUE, c->refs_capa);
    }
    uint32_t idx = c->refs_count++;
    c->refs[idx] = v;
    return MOVE_ID_REF_BIT | idx;
}

/* Resolve a child slot to the object it names. */
static VALUE
move_child(const struct rb_ractor_move_courier *c, VALUE shells, uint32_t id)
{
    if (id & MOVE_ID_REF_BIT) return c->refs[id & ~MOVE_ID_REF_BIT];
    return RARRAY_AREF(shells, id);
}

/* Turn a moved source into a valid RactorMovedObject without passing through flags==0,
 * so a concurrent foreign marker always sees either the original object or the shell. */
static void
move_neutralize_source(VALUE obj)
{
    /* The shell stays in the original slot: keep the capacity bits, give it a frozen
     * field-less ROBJECT shape (read before the flags are overwritten).  The old body is
     * then never read as ivars and compaction's slot-size check still holds. */
    shape_id_t shape_id = (RBASIC_SHAPE_ID(obj) & SHAPE_ID_CAPACITY_MASK) |
                          ROOT_SHAPE_ID | SHAPE_ID_LAYOUT_ROBJECT | SHAPE_ID_FL_FROZEN;

    /* A non-T_OBJECT host (a String with ivars, say) must drop its generic_fields
     * entry: obj stops being a host below and its fields_obj is collected, so a stale
     * entry would let the global GC walk a freed value. */
    rb_free_generic_ivar(obj);

    /* A copy-on-write sharer reads its payload straight out of an embedded root's slot
     * (String#dup of a frozen string, Array#[] of a frozen array), and it outlives the
     * move, so that body has to survive as it is. */
    bool wipe_body = true;
    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
        wipe_body = !rb_str_embedded_shared_root_p(obj);
        break;
      case T_ARRAY:
        wipe_body = !rb_ary_embedded_shared_root_p(obj);
        break;
      default:
        break;
    }

    VALUE flags = T_OBJECT | FL_FREEZE | (RBASIC(obj)->flags & FL_PROMOTED);
    /* Read the slot size before the header is rewritten. */
    size_t slot_size = rb_gc_obj_slot_size(obj);
    RBASIC_SET_CLASS_RAW(obj, rb_cRactorMovedObject);
    RBASIC(obj)->flags = flags;
    RBASIC_SET_FULL_SHAPE_ID(obj, shape_id);

    /* Wipe the old body.  The shell has no fields, so nothing reads it as ivars, but
     * C code holding the object from before the move still reads it with its old type
     * (a running Array iteration, the RMatch capa of a $~ entry): a zeroed body makes
     * those reads see an empty object instead of stale internals. */
    if (wipe_body) {
        MEMZERO((char *)obj + sizeof(struct RBasic), char, slot_size - sizeof(struct RBasic));
    }
}

struct move_hash_ctx {
    struct move_build *b;
    uint32_t *kv;
    long i;
};

static int
move_capture_hash_i(st_data_t key, st_data_t val, st_data_t arg)
{
    struct move_hash_ctx *hc = (struct move_hash_ctx *)arg;
    uint32_t kid = move_capture(hc->b, (VALUE)key);
    uint32_t vid = move_capture(hc->b, (VALUE)val);
    hc->kv[hc->i++] = kid;
    hc->kv[hc->i++] = vid;
    return ST_CONTINUE;
}

struct move_obj_ctx {
    struct move_build *b;
    ID *ids;
    uint32_t *vals;
    long n;
    long capa;
};

static int
move_capture_ivar_i(ID name, VALUE val, st_data_t arg)
{
    struct move_obj_ctx *oc = (struct move_obj_ctx *)arg;
    if (oc->n == oc->capa) {
        oc->capa = oc->capa ? oc->capa * 2 : 4;
        REALLOC_N(oc->ids, ID, oc->capa);
        REALLOC_N(oc->vals, uint32_t, oc->capa);
    }
    uint32_t vid = move_capture(oc->b, val);
    oc->ids[oc->n] = name;
    oc->vals[oc->n] = vid;
    oc->n++;
    return ST_CONTINUE;
}

/* Capture obj's instance and generic ivars as node ids, recursing into the values.
 * Handles both a T_OBJECT's inline ivars and the generic ivars of a String, Array and
 * so on. */
static void
move_capture_ivars(struct move_build *b, VALUE obj, uint32_t id)
{
    struct move_obj_ctx oc = { b, NULL, NULL, 0, 0 };
    rb_ivar_foreach_buffered(obj, move_capture_ivar_i, (st_data_t)&oc);
    b->c->nodes[id].niv = (uint32_t)oc.n;
    b->c->nodes[id].iv_ids = oc.ids;
    b->c->nodes[id].iv_vals = oc.vals;
}

/* Capture obj into the courier, recurse into its children, return its node id.  The id
 * is registered before recursing (a cycle back resolves to the same node); node fields
 * are written after (recursion can realloc c->nodes); the source is neutralized exactly
 * once after the switch. */
static uint32_t
move_capture(struct move_build *b, VALUE obj)
{
    /* An immediate is never in seen (only captured objects are inserted), so it can
     * skip the lookup entirely: that is the whole cost of an array of numbers. */
    if (RB_SPECIAL_CONST_P(obj)) {
        return move_alloc_ref(b->c, obj);
    }

    /* Seen first, and only then shareable: move husks each source as it goes, and a
     * husk is a frozen field-less object, which rb_ractor_shareable_p answers true for.
     * Testing shareable first would embed the husk instead of resolving the second
     * occurrence to the node the first one built. */
    st_data_t existing;
    if (st_lookup(b->seen, (st_data_t)obj, &existing)) {
        return (uint32_t)existing - 1;
    }

    if (rb_ractor_shareable_p(obj)) {
        return move_alloc_ref(b->c, obj);
    }

    uint32_t id = move_alloc_node(b->c);
    st_insert(b->seen, (st_data_t)obj, (st_data_t)(uintptr_t)(id + 1));

    /* Reject an unmovable object before anything is mutated. */
    if (BUILTIN_TYPE(obj) == T_FILE && RFILE(obj)->fptr == NULL) {
        rb_raise(rb_eRactorError, "can not move an uninitialized IO");
    }

    bool frozen = OBJ_FROZEN(obj);
    b->c->nodes[id].frozen = frozen;
    move_capture_ivars(b, obj, id);   /* shared: instance and generic ivars */

    switch (BUILTIN_TYPE(obj)) {
      case T_STRING: {
        /* Give the source its own buffer (drop sharing, copy a static STR_NOFREE one).
         * Safe even when frozen: it changes ownership, not content.  Afterwards a string
         * is embedded, owns a private heap buffer, or is a shared ROOT (a no-op). */
        if (!b->copy) rb_str_make_independent(obj);
        long len = RSTRING_LEN(obj);
        int encidx = ENCODING_GET(obj);
        char *ptr;
        if (!b->copy && !STR_EMBED_P(obj) && rb_str_reembeddable_p(obj)) {
            /* Owns a private heap buffer: carry the pointer over (zero-copy) and leave
             * the source as a shell that does not free it. */
            ptr = RSTRING(obj)->as.heap.ptr;
        }
        else {
            /* Embedded or a shared root: copy the bytes into a courier-owned buffer.
             * Taking a root's buffer would dangle its copy-on-write children, so leave
             * it (the same reason T_ARRAY excludes ARY_SHARED_ROOT_P below). */
            ptr = ALLOC_N(char, len + 1);
            if (len) memcpy(ptr, RSTRING_PTR(obj), len);
            ptr[len] = '\0';
        }
        b->c->nodes[id].kind = MOVE_KIND_STRING;
        b->c->nodes[id].u.str.klass = RBASIC_CLASS(obj);
        b->c->nodes[id].u.str.ptr = ptr;
        b->c->nodes[id].u.str.len = len;
        b->c->nodes[id].u.str.encidx = encidx;
        break;
      }

      case T_ARRAY: {
        long len = RARRAY_LEN(obj);
        uint32_t *elems = len ? ALLOC_N(uint32_t, len) : NULL;
        for (long i = 0; i < len; i++) {
            elems[i] = move_capture(b, RARRAY_AREF(obj, i));
        }
        b->c->nodes[id].kind = MOVE_KIND_ARRAY;
        b->c->nodes[id].u.ary.klass = RBASIC_CLASS(obj);
        b->c->nodes[id].u.ary.len = len;
        b->c->nodes[id].u.ary.elems = elems;
        /* Free the source's heap buffer now that the children were read, but only when it
         * is private: a sharer's belongs to its root, a root's to its sharers -- and a
         * frozen array is a root without carrying the flag. */
        if (!b->copy && !ARY_EMBED_P(obj) && !ARY_SHARED_P(obj) && !ARY_SHARED_ROOT_P(obj) && !OBJ_FROZEN(obj)) {
            ruby_xfree((void *)RARRAY_CONST_PTR(obj));
        }
        break;
      }

      case T_HASH: {
        uint32_t ifnone_id = move_capture(b, RHASH_IFNONE(obj));
        long size = RHASH_SIZE(obj);
        uint32_t *kv = size ? ALLOC_N(uint32_t, size * 2) : NULL;
        struct move_hash_ctx hc = { b, kv, 0 };
        rb_hash_stlike_foreach(obj, move_capture_hash_i, (st_data_t)&hc);
        b->c->nodes[id].kind = MOVE_KIND_HASH;
        b->c->nodes[id].u.hash.klass = RBASIC_CLASS(obj);
        b->c->nodes[id].u.hash.size = size;
        b->c->nodes[id].u.hash.kv = kv;
        b->c->nodes[id].u.hash.ifnone_id = ifnone_id;
        b->c->nodes[id].u.hash.compare_by_id = RTEST(rb_hash_compare_by_id_p(obj));
        b->c->nodes[id].u.hash.proc_default = FL_TEST_RAW(obj, RHASH_PROC_DEFAULT) != 0;
        /* Free the source's st-table internals (an ar table lives in the slot) */
        if (!b->copy) rb_hash_free(obj);
        break;
      }

      case T_OBJECT:
        b->c->nodes[id].kind = MOVE_KIND_OBJECT;
        /* Keep the real class: even a singleton class is shareable, so a cross-objspace
         * reference is safe.  rebuild re-attaches it after allocating with a
         * non-singleton class. */
        b->c->nodes[id].u.obj.klass = RBASIC_CLASS(obj);
        break;

      case T_STRUCT: {
        long len = RSTRUCT_LEN(obj);
        uint32_t *elems = len ? ALLOC_N(uint32_t, len) : NULL;
        for (long i = 0; i < len; i++) {
            elems[i] = move_capture(b, RSTRUCT_GET(obj, (int)i));
        }
        b->c->nodes[id].kind = MOVE_KIND_STRUCT;
        b->c->nodes[id].u.strct.len = len;
        b->c->nodes[id].u.strct.elems = elems;
        b->c->nodes[id].u.strct.klass = RBASIC_CLASS(obj);
        /* Free the source's private heap buffer (an embedded struct has none) */
        if (!b->copy && RSTRUCT_EMBED_LEN(obj) == 0) {
            ruby_xfree((void *)RSTRUCT_CONST_PTR(obj));
        }
        break;
      }

      case T_MATCH: {
        /* The regexp and the matched string travel as ordinary children; re.c dumps the
         * registers (freeing the source's onig and char_offset). */
        VM_ASSERT(!b->copy);   /* copy_courier_supported_p rejects it */
        VALUE re, st;
        int nregs;
        void *regs = rb_match_move_dump(obj, &re, &st, &nregs);
        uint32_t rid = move_capture(b, re);
        uint32_t sid = move_capture(b, st);
        b->c->nodes[id].kind = MOVE_KIND_MATCH;
        b->c->nodes[id].u.match.regexp_id = rid;
        b->c->nodes[id].u.match.str_id = sid;
        b->c->nodes[id].u.match.num_regs = nregs;
        b->c->nodes[id].u.match.regs = regs;
        b->c->nodes[id].u.match.klass = RBASIC_CLASS(obj);
        break;
      }

      case T_FILE:
      {
        VM_ASSERT(!b->copy);   /* copy_courier_supported_p rejects it */
        /* Carry the whole fptr (fd included) by pointer; the source shell does not
         * close it.  fptr's VALUE members lose their root once the source is T_MOVED,
         * so capture them as ordinary child nodes, detached; rebuild writes them back. */
        struct rb_io *fptr = RFILE(obj)->fptr;
        VM_ASSERT(!RTEST(fptr->tied_io_for_writing) && !RTEST(fptr->wakeup_mutex));
        uint32_t pathv_id   = move_capture(b, fptr->pathv);
        uint32_t ecopts_id  = move_capture(b, fptr->encs.ecopts);
        uint32_t wc_pre_id  = move_capture(b, fptr->writeconv_pre_ecopts);
        uint32_t wc_ac_id   = move_capture(b, fptr->writeconv_asciicompat);
        uint32_t timeout_id = move_capture(b, fptr->timeout);
        fptr->self = Qnil;   /* it points at the moved-from T_MOVED; attach rebuilds it */
        fptr->pathv = Qnil;
        fptr->encs.ecopts = Qnil;
        fptr->writeconv_pre_ecopts = Qnil;
        fptr->writeconv_asciicompat = Qnil;
        fptr->timeout = Qnil;
        fptr->write_lock = Qnil;
        fptr->wakeup_mutex = Qnil;
        fptr->tied_io_for_writing = 0;  /* io.c tests it as a C boolean, so 0 rather than Qnil */
        b->c->nodes[id].kind = MOVE_KIND_IO;
        b->c->nodes[id].u.io.fptr = fptr;
        b->c->nodes[id].u.io.klass = RBASIC_CLASS(obj);
        b->c->nodes[id].u.io.pathv_id = pathv_id;
        b->c->nodes[id].u.io.ecopts_id = ecopts_id;
        b->c->nodes[id].u.io.wc_pre_ecopts_id = wc_pre_id;
        b->c->nodes[id].u.io.wc_asciicompat_id = wc_ac_id;
        b->c->nodes[id].u.io.timeout_id = timeout_id;
        break;
      }

      default:
        rb_raise(rb_eRactorError, "can not move a %"PRIsVALUE" object",
                 rb_class_name(rb_obj_class(obj)));
    }

    if (!b->copy) move_neutralize_source(obj);
    return id;
}

static void move_preflight(VALUE obj, st_table *seen);

static int
move_preflight_ivar_i(ID name, VALUE val, st_data_t arg)
{
    move_preflight(val, (st_table *)arg);
    return ST_CONTINUE;
}

static int
move_preflight_hash_i(st_data_t key, st_data_t val, st_data_t arg)
{
    move_preflight((VALUE)key, (st_table *)arg);
    move_preflight((VALUE)val, (st_table *)arg);
    return ST_CONTINUE;
}

/* A read-only pre-walk of move_capture's decision tree.  Capture turns sources into
 * T_MOVED as it goes, so an unmovable object midway would leave the graph broken beyond
 * repair; every "can not move" error is raised here, before anything is mutated. */
static void
move_preflight(VALUE obj, st_table *seen)
{
    if (RB_SPECIAL_CONST_P(obj) || rb_ractor_shareable_p(obj)) return;
    if (st_lookup(seen, (st_data_t)obj, NULL)) return;   /* cycle */
    st_insert(seen, (st_data_t)obj, 0);

    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
      case T_OBJECT:
        break;                       /* children are ivars only (below) */
      case T_MATCH: {
        struct RMatch *rm = RMATCH(obj);
        move_preflight(rm->regexp, seen);
        move_preflight(rm->str, seen);
        break;
      }
      case T_ARRAY:
        for (long i = 0; i < RARRAY_LEN(obj); i++) {
            move_preflight(RARRAY_AREF(obj, i), seen);
        }
        break;
      case T_HASH:
        rb_hash_stlike_foreach(obj, move_preflight_hash_i, (st_data_t)seen);
        move_preflight(RHASH_IFNONE(obj), seen);
        break;
      case T_STRUCT:
        for (long i = 0; i < RSTRUCT_LEN(obj); i++) {
            move_preflight(RSTRUCT_GET(obj, (int)i), seen);
        }
        break;
      case T_FILE: {
        struct rb_io *fptr = RFILE(obj)->fptr;
        if (fptr == NULL) {
            rb_raise(rb_eRactorError, "can not move an uninitialized IO");
        }
        if (RTEST(fptr->tied_io_for_writing)) {
            /* A popen("r+") pair: moving one side would dangle the tied writer on the
             * sender. */
            rb_raise(rb_eRactorError, "can not move an IO tied to a writer IO");
        }
        if (RTEST(fptr->wakeup_mutex)) {
            /* A close is in progress: a thread is blocked on this IO. */
            rb_raise(rb_eRactorError, "can not move an IO that is being closed");
        }
        move_preflight(fptr->pathv, seen);
        move_preflight(fptr->encs.ecopts, seen);
        move_preflight(fptr->writeconv_pre_ecopts, seen);
        move_preflight(fptr->writeconv_asciicompat, seen);
        move_preflight(fptr->timeout, seen);
        break;
      }
      default:
        rb_raise(rb_eRactorError, "can not move a %"PRIsVALUE" object",
                 rb_class_name(rb_obj_class(obj)));
    }

    rb_ivar_foreach(obj, move_preflight_ivar_i, (st_data_t)seen);
}

struct copy_support_ctx {
    st_table *seen;
    bool ok;
};

static bool copy_courier_supported_p(VALUE obj, st_table *seen);

static int
copy_support_val_i(st_data_t val, st_data_t arg)
{
    struct copy_support_ctx *ctx = (struct copy_support_ctx *)arg;
    if (!copy_courier_supported_p((VALUE)val, ctx->seen)) {
        ctx->ok = false;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

static int
copy_support_ivar_i(ID name, VALUE val, st_data_t arg)
{
    return copy_support_val_i((st_data_t)val, arg);
}

static int
copy_support_hash_i(st_data_t key, st_data_t val, st_data_t arg)
{
    if (copy_support_val_i(key, arg) == ST_STOP) return ST_STOP;
    return copy_support_val_i(val, arg);
}

/* Read-only walk: can the copy courier carry obj's whole graph?  Everything it says no
 * to (MatchData, IO, any other T_DATA, a singleton class) stays on the older on-heap
 * snapshot path, which keeps handling or rejecting it exactly as before. */
static bool
copy_courier_supported_p(VALUE obj, st_table *seen)
{
    if (RB_SPECIAL_CONST_P(obj) || rb_ractor_shareable_p(obj)) return true;
    if (st_lookup(seen, (st_data_t)obj, NULL)) return true;   /* cycle */
    st_insert(seen, (st_data_t)obj, 0);

    /* A singleton class is a send error today (the native copier refuses it and Marshal
     * then raises); the courier would happily carry it, so keep it off this path. */
    VALUE klass = RBASIC_CLASS(obj);
    if (klass == 0 || FL_TEST_RAW(klass, FL_SINGLETON)) return false;

    struct copy_support_ctx ctx = { seen, true };

    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
      case T_OBJECT:
        break;                       /* children are ivars only (below) */
      case T_ARRAY:
        for (long i = 0; i < RARRAY_LEN(obj); i++) {
            if (!copy_courier_supported_p(RARRAY_AREF(obj, i), seen)) return false;
        }
        break;
      case T_HASH:
        rb_hash_stlike_foreach(obj, copy_support_hash_i, (st_data_t)&ctx);
        if (!ctx.ok) return false;
        if (!copy_courier_supported_p(RHASH_IFNONE(obj), seen)) return false;
        break;
      case T_STRUCT:
        for (long i = 0; i < RSTRUCT_LEN(obj); i++) {
            if (!copy_courier_supported_p(RSTRUCT_GET(obj, (int)i), seen)) return false;
        }
        break;
      default:
        return false;
    }

    rb_ivar_foreach(obj, copy_support_ivar_i, (st_data_t)&ctx);
    return ctx.ok;
}

/* Build a courier holding a copy of obj's graph, leaving the sources untouched.
 * Returns NULL when the graph has a type only the on-heap snapshot path handles. */
struct rb_ractor_move_courier *
rb_ractor_copy_courier_build(VALUE obj)
{
    {
        st_table *seen = st_init_numtable();
        bool ok = copy_courier_supported_p(obj, seen);
        st_free_table(seen);
        if (!ok) return NULL;
    }

    struct rb_ractor_move_courier *c = ZALLOC(struct rb_ractor_move_courier);
    struct move_build b = { c, st_init_numtable(), true };

    /* Same registry cover as a move courier: the shareable REFs it carries need a root
     * for its whole lifetime. */
    move_courier_registry_add(c);

    enum ruby_tag_type state;
    rb_execution_context_t *ec = GET_EC();
    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        c->root = move_capture(&b, obj);
    }
    EC_POP_TAG();
    st_free_table(b.seen);
    if (state != TAG_NONE) {
        rb_ractor_move_courier_free(c);
        EC_JUMP_TAG(ec, state);
    }
    return c;
}

/* Build a move courier from obj and turn every captured source into a
 * RactorMovedObject (move semantics).  Returns the xmalloc'd courier. */
struct rb_ractor_move_courier *
rb_ractor_move_courier_build(VALUE obj)
{
    /* Two phases, preflight then commit, so an unmovable object is raised from the
     * read-only walk while the graph is still intact. */
    {
        st_table *pf_seen = st_init_numtable();
        enum ruby_tag_type state;
        rb_execution_context_t *ec = GET_EC();
        EC_PUSH_TAG(ec);
        if ((state = EC_EXEC_TAG()) == TAG_NONE) {
            move_preflight(obj, pf_seen);
        }
        EC_POP_TAG();
        st_free_table(pf_seen);
        if (state != TAG_NONE) EC_JUMP_TAG(ec, state);
    }

    struct rb_ractor_move_courier *c = ZALLOC(struct rb_ractor_move_courier);
    struct move_build b = { c, st_init_numtable(), false };

    /* Between send and materialization the courier's shareable REFs pass through
     * windows where nothing else roots them; register it for its whole lifetime so the
     * registry root pass marks and pins them.  Registering before the sources become
     * T_MOVED is safe: partial nodes are initialized mark-safe. */
    move_courier_registry_add(c);

    enum ruby_tag_type state;
    rb_execution_context_t *ec = GET_EC();
    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        c->root = move_capture(&b, obj);
    }
    EC_POP_TAG();
    st_free_table(b.seen);
    if (state != TAG_NONE) {
        /* move_capture raised (an unmovable type, an interrupt).  Remove the courier
         * from the registry and free it before re-raising; the partial nodes are
         * mark-safe and safe to free. */
        rb_ractor_move_courier_free(c);
        EC_JUMP_TAG(ec, state);
    }
    return c;
}

/* Shells are created with the base/real class, so re-attach the original subclass or
 * singleton class (classes are shareable; the reference is safe).  A singleton's
 * attached object still points at the sender's source: re-attach it to the shell. */
static void
move_apply_moved_klass(VALUE shell, VALUE klass)
{
    if (klass != RBASIC_CLASS(shell)) {
        RBASIC_SET_CLASS(shell, klass);
    }
    if (RB_UNLIKELY(FL_TEST_RAW(klass, FL_SINGLETON))) {
        rb_singleton_class_attached(klass, shell);
    }
}

/* Rebuild the courier's graph in the current Ractor's objspace and return its root.
 * Two passes (allocate shells, then fill) break reference cycles. */
VALUE
rb_ractor_move_courier_materialize(struct rb_ractor_move_courier *c)
{
    /* A hidden Array roots every shell, keeping them alive while the allocations that
     * build the rest of the graph (which can start this Ractor's GC) run. */
    VALUE shells = rb_ary_hidden_new(c->count);

    for (uint32_t i = 0; i < c->count; i++) {
        struct move_node *n = &c->nodes[i];
        VALUE shell;
        switch (n->kind) {
          case MOVE_KIND_REF:
            shell = n->u.ref;
            break;
          case MOVE_KIND_STRING:
            shell = rb_enc_str_new(n->u.str.ptr, n->u.str.len, rb_enc_from_index(n->u.str.encidx));
            move_apply_moved_klass(shell, n->u.str.klass);
            break;
          case MOVE_KIND_ARRAY:
            shell = rb_ary_new_capa(n->u.ary.len);
            move_apply_moved_klass(shell, n->u.ary.klass);
            break;
          case MOVE_KIND_HASH:
            shell = n->u.hash.compare_by_id ? rb_ident_hash_new() : rb_hash_new();
            move_apply_moved_klass(shell, n->u.hash.klass);
            break;
          case MOVE_KIND_OBJECT:
            /* A singleton class cannot allocate, so make an instance of the real class
             * and re-attach it afterwards */
            shell = rb_obj_alloc(rb_class_real(n->u.obj.klass));
            move_apply_moved_klass(shell, n->u.obj.klass);
            break;
          case MOVE_KIND_STRUCT:
            shell = rb_obj_alloc(rb_class_real(n->u.strct.klass));
            move_apply_moved_klass(shell, n->u.strct.klass);
            break;
          case MOVE_KIND_MATCH:
            shell = rb_match_move_alloc(rb_class_real(n->u.match.klass), n->u.match.num_regs);
            move_apply_moved_klass(shell, n->u.match.klass);
            break;
          case MOVE_KIND_IO:
            shell = rb_obj_alloc(rb_class_real(n->u.io.klass));
            move_apply_moved_klass(shell, n->u.io.klass);
            RFILE(shell)->fptr = n->u.io.fptr;
            n->u.io.fptr->self = shell;
            n->u.io.fptr = NULL; /* consumed: the new IO owns it now */
            break;
          default:
            rb_bug("rb_ractor_move_courier_materialize: bad node kind");
        }
        rb_ary_push(shells, shell);
    }

    for (uint32_t i = 0; i < c->count; i++) {
        struct move_node *n = &c->nodes[i];
        VALUE shell = RARRAY_AREF(shells, i);
        switch (n->kind) {
          case MOVE_KIND_ARRAY:
            for (long j = 0; j < n->u.ary.len; j++) {
                rb_ary_push(shell, move_child(c, shells, n->u.ary.elems[j]));
            }
            break;
          case MOVE_KIND_HASH:
            /* Entry insertion is deferred to a third pass: insertion calls the key's
             * #hash / #eql?, and a content-based #hash would collide on every key while
             * the graph is still empty, collapsing entries. */
            break;
          case MOVE_KIND_STRUCT:
            for (long j = 0; j < n->u.strct.len; j++) {
                RSTRUCT_SET(shell, (int)j, move_child(c, shells, n->u.strct.elems[j]));
            }
            break;
          case MOVE_KIND_MATCH:
            rb_match_move_load(shell, move_child(c, shells, n->u.match.regexp_id),
                               move_child(c, shells, n->u.match.str_id),
                               n->u.match.num_regs, n->u.match.regs);
            break;
          case MOVE_KIND_IO: {
            /* Write the rebuilt VALUE members back into fptr (capture detached them).
             * write_lock and wakeup_mutex stay nil; io.c recreates them lazily. */
            struct rb_io *fptr = RFILE(shell)->fptr;
            RB_OBJ_WRITE(shell, &fptr->pathv, move_child(c, shells, n->u.io.pathv_id));
            RB_OBJ_WRITE(shell, &fptr->encs.ecopts, move_child(c, shells, n->u.io.ecopts_id));
            RB_OBJ_WRITE(shell, &fptr->writeconv_pre_ecopts, move_child(c, shells, n->u.io.wc_pre_ecopts_id));
            RB_OBJ_WRITE(shell, &fptr->writeconv_asciicompat, move_child(c, shells, n->u.io.wc_asciicompat_id));
            RB_OBJ_WRITE(shell, &fptr->timeout, move_child(c, shells, n->u.io.timeout_id));
            break;
          }
          default:
            break;
        }
        /* Restore instance and generic ivars (any non-REF node can have them) */
        for (uint32_t j = 0; j < n->niv; j++) {
            rb_ivar_set(shell, n->iv_ids[j], move_child(c, shells, n->iv_vals[j]));
        }
    }

    /* Insert hash entries only once every shell is filled.  Ids are assigned
     * depth-first (children larger), so inserting in reverse settles nested hash keys
     * inside-out (a #hash cycling through itself is out of scope). */
    for (uint32_t i = c->count; i > 0; i--) {
        struct move_node *n = &c->nodes[i - 1];
        if (n->kind != MOVE_KIND_HASH) continue;
        VALUE shell = RARRAY_AREF(shells, i - 1);
        for (long j = 0; j < n->u.hash.size; j++) {
            rb_hash_aset(shell, move_child(c, shells, n->u.hash.kv[2 * j]),
                         move_child(c, shells, n->u.hash.kv[2 * j + 1]));
        }
        /* Restore the default value and default proc (before freezing) */
        VALUE ifnone = move_child(c, shells, n->u.hash.ifnone_id);
        if (n->u.hash.proc_default) {
            rb_hash_set_default_proc(shell, ifnone);
        }
        else if (ifnone != Qnil) {
            rb_hash_set_default(shell, ifnone);
        }
    }

    /* Freeze after filling, so frozen containers and strings can be built too. */
    for (uint32_t i = 0; i < c->count; i++) {
        VALUE shell = RARRAY_AREF(shells, i);
        if (c->nodes[i].frozen && !RB_SPECIAL_CONST_P(shell)) {
            rb_obj_freeze(shell);
        }
    }

    VALUE root = (c->count || c->refs_count) ? move_child(c, shells, c->root) : Qnil;
    RB_GC_GUARD(shells);
    return root;
}

void
rb_ractor_move_courier_free(struct rb_ractor_move_courier *c)
{
    for (uint32_t i = 0; i < c->count; i++) {
        struct move_node *n = &c->nodes[i];
        ruby_xfree(n->iv_ids);
        ruby_xfree(n->iv_vals);
        switch (n->kind) {
          case MOVE_KIND_STRING:
            ruby_xfree(n->u.str.ptr);
            break;
          case MOVE_KIND_ARRAY:
            ruby_xfree(n->u.ary.elems);
            break;
          case MOVE_KIND_HASH:
            ruby_xfree(n->u.hash.kv);
            break;
          case MOVE_KIND_STRUCT:
            ruby_xfree(n->u.strct.elems);
            break;
          case MOVE_KIND_MATCH:
            rb_match_move_free(n->u.match.regs);
            break;
          case MOVE_KIND_IO:
            /* A delivered IO left fptr == NULL (the rebuilt IO owns it).  An
             * undelivered one still owns the fd and its source is already a
             * RactorMovedObject nobody can close: close it here, not leak it. */
            if (n->u.io.fptr) {
                rb_io_fptr_finalize(n->u.io.fptr);
                n->u.io.fptr = NULL;
            }
            break;
          default:
            break;
        }
    }
    move_courier_registry_remove(c);
    ruby_xfree(c->nodes);
    ruby_xfree(c->refs);
    ruby_xfree(c);
}

/* Mark the only VALUEs a courier holds: shareable objects and immediates (REF) and the
 * classes of its objects.  All of them are shareable, so marking cannot race, and the
 * global GC keeps them reachable through the courier. */
void
rb_ractor_move_courier_mark(struct rb_ractor_move_courier *c)
{
    if (!c) return;
    for (uint32_t i = 0; i < c->refs_count; i++) {
        rb_gc_mark(c->refs[i]);
    }
    for (uint32_t i = 0; i < c->count; i++) {
        struct move_node *n = &c->nodes[i];
        if (n->kind == MOVE_KIND_REF) {
            rb_gc_mark(n->u.ref);
        }
        else if (n->kind == MOVE_KIND_OBJECT) {
            rb_gc_mark(n->u.obj.klass);
        }
        else if (n->kind == MOVE_KIND_STRUCT) {
            rb_gc_mark(n->u.strct.klass);
        }
        else if (n->kind == MOVE_KIND_MATCH) {
            rb_gc_mark(n->u.match.klass);
        }
        else if (n->kind == MOVE_KIND_IO) {
            rb_gc_mark(n->u.io.klass);
        }
        else if (n->kind == MOVE_KIND_STRING) {
            rb_gc_mark(n->u.str.klass);
        }
        else if (n->kind == MOVE_KIND_ARRAY) {
            rb_gc_mark(n->u.ary.klass);
        }
        else if (n->kind == MOVE_KIND_HASH) {
            rb_gc_mark(n->u.hash.klass);
        }
    }
}

/* The message copy traversal never calls #clone or #initialize_clone.  Core container
 * types get a native shallow copy here (the traversal then rewrites the children inside
 * the copy); any other unshareable type falls back to a full Marshal round trip. */
static VALUE
ractor_native_shallow_copy(VALUE obj)
{
    VALUE copy;

    /* An object with a singleton class cannot be copied natively; fall back to Marshal
     * so it reports a proper error. */
    VALUE klass = RBASIC_CLASS(obj);
    if (klass == 0 || FL_TEST_RAW(klass, FL_SINGLETON)) {
        return Qundef;
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        copy = rb_obj_alloc(rb_obj_class(obj));
        rb_obj_copy_ivar(copy, obj);
        break;
      case T_STRING:
        copy = rb_enc_str_new(RSTRING_PTR(obj), RSTRING_LEN(obj), rb_enc_get(obj));
        break;
      case T_ARRAY:
        copy = rb_ary_new_from_values(RARRAY_LEN(obj), RARRAY_CONST_PTR(obj));
        break;
      case T_HASH:
        copy = rb_hash_dup(obj);
        break;
      case T_STRUCT:
        copy = rb_obj_alloc(rb_obj_class(obj));
        rb_struct_init_copy(copy, obj);
        break;
      case T_MATCH:
        copy = rb_obj_alloc(rb_obj_class(obj));
        rb_match_init_copy(copy, obj);
        break;
      case T_DATA:
        /* Keep a copied exception from carrying a raw pointer to the sender's backtrace
         * across objspaces */
        if (rb_backtrace_p(obj)) {
            copy = rb_backtrace_dup(obj);
            break;
        }
        return Qundef;
      default:
        return Qundef;
    }

    /* A non-T_OBJECT host keeps its ivars in the generic fields table: copy them.
     * T_HASH is excluded: rb_hash_dup already ran rb_copy_generic_ivar, and a second
     * call asserts in rb_shape_rebuild (the first gave the copy an ivar shape). */
    if (BUILTIN_TYPE(obj) != T_OBJECT && BUILTIN_TYPE(obj) != T_HASH &&
        UNLIKELY(rb_obj_gen_fields_p(obj))) {
        rb_copy_generic_ivar(copy, obj);
    }

    /* The traversal rewrites the children inside the copy with raw stores, so the frozen
     * bit can be set now: by the time leave runs the original is out of sight. */
    if (OBJ_FROZEN(obj)) {
        RB_FL_SET_RAW(copy, RUBY_FL_FREEZE);
    }
    return copy;
}

/* Add a node of the snapshot under construction to the pin list and pin it now. */
static void
ractor_pin_capture_push(rb_ractor_t *cr, VALUE v)
{
    if (cr->pin_capture_cnt == cr->pin_capture_capa) {
        size_t nc = cr->pin_capture_capa ? cr->pin_capture_capa * 2 : 16;
        VALUE *p = realloc(cr->pin_capture, nc * sizeof(VALUE));
        if (!p) rb_bug("ractor_pin_capture_push: out of memory");
        cr->pin_capture = p;
        cr->pin_capture_capa = nc;
    }
    cr->pin_capture[cr->pin_capture_cnt++] = v;
    rb_gc_pin_in_flight_message(v);
}

static enum obj_traverse_iterator_result
copy_enter(VALUE obj, struct obj_traverse_replace_data *data)
{
    if (rb_ractor_shareable_p(obj)) {
        data->replacement = obj;
        return traverse_skip;
    }
    else {
        VALUE copy = ractor_native_shallow_copy(obj);
        if (UNDEF_P(copy)) return traverse_stop; /* no native copy for this type */
        data->replacement = copy;
        /* Collect every node into the pin list as the snapshot is built: the global
         * GC's re-pin must cover all nodes, not just the root (moving one breaks the
         * address-keyed dedup table).  fields_obj is not included: the global
         * generic_fields table reaches it and compaction updates that. */
        rb_ractor_t *cr = GET_RACTOR();
        if (cr->gen_fields_capturing) {
            /* Pin from birth (shref bit, plus the pin bit during a global compaction).
             * rb_ractor_repin_in_flight re-pins via cr->pin_capture, so the cover runs
             * unbroken from construction through enqueue to materialization. */
            ractor_pin_capture_push(cr, copy);
        }
        return traverse_cont;
    }
}

static enum obj_traverse_iterator_result
copy_leave(VALUE obj, struct obj_traverse_replace_data *data)
{
    return traverse_cont;
}

/* Native deep copy of obj's graph.  Returns Qundef when it contains a type the native
 * copier does not support, and the caller falls back to Marshal. */
static VALUE
ractor_copy_native_try(VALUE obj)
{
    return rb_obj_traverse_replace(obj, copy_enter, copy_leave, false);
}

/* Deep copy within one objspace (Ractor.make_shareable(obj, copy: true)): native first,
 * then a whole-graph Marshal round trip. */
static VALUE
ractor_copy(VALUE obj)
{
    VALUE copy = ractor_copy_native_try(obj);
    if (UNDEF_P(copy)) {
        copy = rb_marshal_load(rb_rescue2(ractor_marshal_dump_body, obj,
                                          ractor_marshal_dump_rescue, obj,
                                          rb_eTypeError, (VALUE)0));
    }
    return copy;
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

/* Purge deleted ractor-local keys from the storage tables and run their free hooks. */
static void
ractor_local_keys_purge(st_table *local_storage)
{
    for (int i=0; i<freed_ractor_local_keys.cnt; i++) {
        rb_ractor_local_key_t key = freed_ractor_local_keys.keys[i];
        st_data_t val, k = (st_data_t)key;
        if (st_delete(local_storage, &k, &val) &&
            (key = (rb_ractor_local_key_t)k)->type->free) {
            (*key->type->free)((void *)val);
        }
    }
}


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

        /* A deleted key is purged from every Ractor's storage in one collection, which
         * then frees its struct.  Only a collection that visits every Ractor with no
         * other marker running can do that: a global GC, or a single objspace. */
        if (rb_gc_single_objspace_p() || rb_gc_during_global_gc_p()) {
            ractor_local_keys_purge(r->local_storage);
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
            SIZED_REALLOC_N(freed_ractor_local_keys.keys, rb_ractor_local_key_t, freed_ractor_local_keys.capa, freed_ractor_local_keys.cnt);
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
    /* A freed key's struct may only be released by a collection that purged every
     * Ractor's storage with no other marker running: a global GC, or a single objspace.
     * A local GC also reaches here (gc_marks_finish) and must do nothing. */
    if (!(rb_gc_single_objspace_p() || rb_gc_during_global_gc_p())) {
        return;
    }

    /* The root scan's purge never reaches a zombie's storage (not in the set;
     * zombie_objspaces only marks the join slot): purge here, under the barrier, before
     * the struct is freed, or a later ractor_free reads a freed key. */
    rb_vm_t *vm = GET_VM();
    for (size_t zi = 0; zi < vm->gc.zombie_objspaces_count; zi++) {
        rb_ractor_t *owner = vm->gc.zombie_objspaces[zi].owner;
        if (owner == NULL || owner->local_storage == NULL) continue;
        ractor_local_keys_purge(owner->local_storage);
    }

    for (int i=0; i<freed_ractor_local_keys.cnt; i++) {
        SIZED_FREE(freed_ractor_local_keys.keys[i]);
    }
    freed_ractor_local_keys.cnt = 0;
    if (freed_ractor_local_keys.capa > DEFAULT_KEYS_CAPA) {
        freed_ractor_local_keys.capa = DEFAULT_KEYS_CAPA;
        SIZED_REALLOC_N(freed_ractor_local_keys.keys, rb_ractor_local_key_t, DEFAULT_KEYS_CAPA, freed_ractor_local_keys.capa);
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

// shareable_proc

static VALUE
ractor_shareable_proc(rb_execution_context_t *ec, VALUE replace_self, bool is_lambda)
{
    if (!rb_ractor_shareable_p(replace_self)) {
        rb_raise(rb_eRactorIsolationError, "self should be shareable: %" PRIsVALUE, replace_self);
    }
    else {
        VALUE proc = is_lambda ? rb_block_lambda() : rb_block_proc();
        return rb_proc_ractor_make_shareable(rb_proc_dup(proc), replace_self);
    }
}

// Ractor#require

struct cross_ractor_require {
    VALUE port;
    bool raised;

    union {
        struct {
            VALUE feature;
        } require;

        struct {
            VALUE module;
            ID name;
        } autoload;
    } as;

    bool silent;
};

RUBY_REFERENCES(cross_ractor_require_refs) = {
    RUBY_REF_EDGE(struct cross_ractor_require, port),
    RUBY_REF_EDGE(struct cross_ractor_require, as.require.feature),
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
    0, 0, RUBY_TYPED_THREAD_SAFE_FREE | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_DECL_MARKING | RUBY_TYPED_EMBEDDABLE
};

static VALUE
require_body(VALUE crr_obj)
{
    struct cross_ractor_require *crr;
    TypedData_Get_Struct(crr_obj, struct cross_ractor_require, &cross_ractor_require_data_type, crr);
    VALUE feature = crr->as.require.feature;

    ID require;
    CONST_ID(require, "require");

    if (crr->silent) {
        int rb_require_internal_silent(VALUE fname);
        return INT2NUM(rb_require_internal_silent(feature));
    }
    else {
        return rb_funcallv(Qnil, require, 1, &feature);
    }
}

static VALUE
require_rescue(VALUE crr_obj, VALUE errinfo)
{
    struct cross_ractor_require *crr;
    TypedData_Get_Struct(crr_obj, struct cross_ractor_require, &cross_ractor_require_data_type, crr);
    crr->raised = true;
    return errinfo;
}

static VALUE
require_result_send_body(VALUE ary)
{
    VALUE port = RARRAY_AREF(ary, 0);
    VALUE results = RARRAY_AREF(ary, 1);

    rb_execution_context_t *ec = GET_EC();

    ractor_port_send(ec, port, results, Qfalse);
    return Qnil;
}

static VALUE
require_result_send_resuce(VALUE port, VALUE errinfo)
{
    // TODO: need rescue?
    ractor_port_send(GET_EC(), port, errinfo, Qfalse);
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

    // get normal result or raised exception (with crr->raised == true)
    VALUE result = rb_rescue2(func, crr_obj, require_rescue, crr_obj, rb_eException, 0);

    if (silent) {
        ruby_debug = debug;
        rb_set_errinfo(errinfo);
    }

    rb_rescue2(require_result_send_body,
               // [port, [result, raised]]
               rb_ary_new_from_args(2, crr->port, rb_ary_new_from_args(2, result, crr->raised ? Qtrue : Qfalse)),
               require_result_send_resuce, rb_eException, crr->port);

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
    RB_OBJ_SET_SHAREABLE(crr_obj); // TODO: internal data?

    // Convert feature to proper file path and make it shareable as fstring
    RB_OBJ_WRITE(crr_obj, &crr->as.require.feature, rb_fstring(FilePathValue(feature)));
    RB_OBJ_WRITE(crr_obj, &crr->port, rb_ractor_make_shareable(ractor_port_new(GET_RACTOR())));
    crr->raised = false;
    crr->silent = silent;

    rb_execution_context_t *ec = GET_EC();
    rb_ractor_t *main_r = GET_VM()->ractor.main_ractor;
    rb_ractor_interrupt_exec(main_r, ractor_require_func, (void *)crr_obj, rb_interrupt_exec_flag_value_data);

    // wait for require done
    VALUE results = ractor_port_receive(ec, crr->port);
    ractor_port_close(ec, crr->port);

    VALUE exc = rb_ary_pop(results);
    VALUE result = rb_ary_pop(results);
    RB_GC_GUARD(crr_obj);

    if (RTEST(exc)) {
        rb_exc_raise(result);
    }
    else {
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
    return rb_autoload_load(crr->as.autoload.module, crr->as.autoload.name);
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
    RB_OBJ_SET_SHAREABLE(crr_obj); // TODO: internal data?

    RB_OBJ_WRITE(crr_obj, &crr->as.autoload.module, module);
    RB_OBJ_WRITE(crr_obj, &crr->as.autoload.name, name);
    RB_OBJ_WRITE(crr_obj, &crr->port, rb_ractor_make_shareable(ractor_port_new(GET_RACTOR())));

    rb_execution_context_t *ec = GET_EC();
    rb_ractor_t *main_r = GET_VM()->ractor.main_ractor;
    rb_ractor_interrupt_exec(main_r, ractor_autoload_load_func, (void *)crr_obj, rb_interrupt_exec_flag_value_data);

    // wait for require done
    VALUE results = ractor_port_receive(ec, crr->port);
    ractor_port_close(ec, crr->port);

    VALUE exc = rb_ary_pop(results);
    VALUE result = rb_ary_pop(results);
    RB_GC_GUARD(crr_obj);

    if (RTEST(exc)) {
        rb_exc_raise(result);
    }
    else {
        return result;
    }
}

#include "ractor.rbinc"
