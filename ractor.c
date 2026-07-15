// Ractor implementation

#include "ruby/ruby.h"
#include "ruby/thread.h"
#include "ruby/ractor.h"
#include "ruby/re.h"
#include "ruby/thread_native.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "ractor_core.h"
#include "internal/complex.h"
#include "internal/cont.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/array.h"
#include "internal/string.h"
#include "internal/struct.h"
#include "internal/re.h"
#include "internal/variable.h"
#include "eval_intern.h"
#include "ruby/encoding.h"
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
    /* 単一 VALUE スロット。owner が 1 語で書くのでどの GC からも安全に読める。
     * 参照先は foreign marker には他 Ractor のものなので containment で skip される。 */
    rb_gc_mark(r->r_stdin);
    rb_gc_mark(r->r_stdout);
    rb_gc_mark(r->r_stderr);
    rb_gc_mark(r->verbose);
    rb_gc_mark(r->debug);

    // 受信メッセージを mark（owner が変更する構造は内部で自らガードする）
    ractor_sync_mark(r);

    /* 以下は owner が実行中に変更する構造（thread/EC/fiber は並行に free もされる）。
     * 並行 owner が居ない時だけ walk する。自分・終了済み・global GC barrier 下。
     * 生きた他 Ractor は自分で local root を張るので取りこぼさない。 */
    rb_ractor_t *cr = rb_current_ractor_raw(false);
    if (!(r == cr || rb_ractor_status_p(r, ractor_terminated) || rb_gc_during_global_gc_p())) {
        return;
    }

    rb_hook_list_mark(&r->pub.hooks);
    if (r->pub.targeted_hooks.num_entries) {
        st_foreach(&r->pub.targeted_hooks, mark_targeted_hook_list, 0);
    }

    if (r->threads.cnt > 0) {
        rb_thread_t *th = 0;
        ccan_list_for_each(&r->threads.set, th, lt_node) {
            VM_ASSERT(th != NULL);
            rb_gc_mark(th->self);
            /* EC も直接 mark する。confined GC では Thread wrapper が別 objspace に
             * ある場合があり（re-home まで）その mark 関数がここで走らないが、
             * stack は生かす必要がある。 */
            if (th->ec) rb_execution_context_mark(th->ec);

            /* thread の ec は root fiber 構造体内にあり、その wrapper object と共に
             * free される。main thread の wrapper は生成元 Ractor の objspace に
             * あり他に root が無いので、ここで fiber wrapper を mark して生かす。 */
            if (th->root_fiber) {
                VALUE root_fiber_self = rb_fiberptr_self(th->root_fiber);
                if (root_fiber_self) rb_gc_mark(root_fiber_self);
            }
            if (th->ec && th->ec->fiber_ptr) {
                VALUE fiber_self = rb_fiberptr_self(th->ec->fiber_ptr);
                if (fiber_self) rb_gc_mark(fiber_self);
            }

            /* wrapper が別 objspace にあると thread_mark が走らず、thread 所有の
             * 残り root が到達不能になる。特に thgroup はこの Ractor の objspace に
             * あり他に root が無いので、直接 mark しないと local GC に free される。 */
            rb_thread_mark_owned_roots(th);
        }
    }

    ractor_local_storage_mark(r);
}

static void
ractor_mark(void *ptr)
{
    rb_ractor_t *r = (rb_ractor_t *)ptr;
    bool checking_shareable = rb_gc_checking_shareable();

    rb_gc_mark(r->loc);
    rb_gc_mark(r->name);

    if (!checking_shareable) {
        // may unshareable objects
        ractor_mark_unshareable_parts(r);
    }
}

/* Ractor r の C 構造体から到達可能な GC root を mark する。confined GC は heap 上の
 * Ractor/Thread wrapper object に頼れない（別 objspace にある場合がある）ため、
 * この Ractor の所有物はここから直接 root にする。 */
void
rb_ractor_mark_local_roots(rb_ractor_t *r)
{
    rb_gc_mark(r->loc);
    rb_gc_mark(r->name);
    ractor_mark_unshareable_parts(r);

    /* この Ractor の rb_gc_register_mark_object pin。保守的に扱い、local GC は
     * 自分の住人だけ mark する。foreign/shareable entry は owner か global GC が拾う。 */
    rb_gc_mark_vm_stack_values((long)r->registered_marks_cnt, r->registered_marks);
}

/* src の rb_gc_register_mark_object pin を dst へ移す。src の objspace が dst に
 * 吸収される際、objspace merge の前に呼び、pin object が無 root になる窓を防ぐ。
 * absorb は GC sweep 中に走りうるので生 realloc で GC を再入させない。 */
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

    if (!r->main_ractor) {
        /* この Ractor の generic_fields 表を main へ移送する。struct と共に失うと、
         * objspace が後で main に merge された後、host の obj_free が entry を見つけられず
         * rb_bug になる。st は raw malloc なので sweep 中でも安全。 */
        rb_ractor_absorb_generic_fields(GET_VM()->ractor.main_ractor, r);
    }

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

    /* unjoin で死んだ Ractor（handle も消え誰も継げない）。ここは global GC barrier 下の
     * sweep なので zombie ledger を放し objspace merge を main に postponed job で渡す。
     * main は free-at-exit walk で来るので触らず、objspace も残す（VM destruct が最後に free）。 */
    if (r->objspace && !r->main_ractor) {
        rb_gc_objspace_disown(r->objspace);
        r->objspace = NULL;
    }

    ractor_sync_free(r);

    /* generic_fields 表を解放。非 main は上で main へ移送済み（NULL）だが、
     * main は shutdown 時に非 NULL のことがある。NULL は no-op。 */
    rb_ractor_free_generic_fields(r);

    /* orphan Ractor（未 join）は objspace を main に吸収される前に
     * rb_gc_register_mark_object pin を main へ渡す。join 側も同様に、
     * objspace merge の前に joiner へ渡す（registration 未移送の窓を防ぐ）。 */
    if (!r->main_ractor) {
        rb_ractor_absorb_registered_marks(GET_VM()->ractor.main_ractor, r);
    }
    free(r->registered_marks);
    r->registered_marks = NULL;
    r->registered_marks_cnt = r->registered_marks_capa = 0;

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
    /* registered_marks は pin されている（rb_gc_mark_vm_stack_values で mark）ので、
     * compaction による更新は不要。 */
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

    /* multi-objspace になる直前。incremental marking は single-objspace の
     * 世界でしか走らないので、count が変わる前に進行中の cycle を終える。 */
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
            /* child は set に入り単独で列挙されるので、生成元経由の被覆をやめる
             * （二重列挙を防ぐ）。追加と同じ VM lock 下でクリアするので、
             * whole-VM walk が両方を見ることはない。 */
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
            /* child は set に入ったので生成元経由の被覆をやめる（上の multi-Ractor 分岐と同じ）。
             * single->multi 経路はこれを飛ばしていたため、global GC が child の objspace を
             * 二重列挙・二重 sweep し、生きた main Thread/root Fiber を free して起動を壊した。 */
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

        if (vm->ractor.cnt <= 2 && vm->ractor.sync.terminate_waiting) {
            rb_native_cond_signal(&vm->ractor.sync.terminate_cond);
        }
        vm->ractor.cnt--;

        rb_gc_ractor_cache_free(cr->newobj_cache);
        cr->newobj_cache = NULL;

        /* ここで objspace は owner thread を失う。継承で merge されるまで
         * global GC から列挙可能に保つ。 */
        if (cr->objspace) {
            rb_gc_objspace_retire(&cr->objspace);
        }

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
    /* main Ractor は objspace 生成前に確保されるので、newobj cache は後で
     * Init_BareVM（rb_gc_init_objspaces が r->objspace を設定した後）で作る。 */
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
    /* fork した子では他の全 Ractor が terminated-unjoined になる。join か
     * global GC が merge するまで objspace を列挙可能に保つ。 */
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
    r->gen_fields_capture = NULL;
    r->gen_fields_materialize = NULL;
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

    /* 全 Ractor は objspace を持つ。thread が走る前に存在させる必要がある
     * （最初の allocation が rb_gc_get_objspace 経由でそこへ行く）。 */
    r->objspace = rb_gc_objspace_alloc();

    rb_yjit_before_ractor_spawn();
    rb_zjit_before_ractor_spawn();
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

    /* 他の全 Ractor は死んだ。main が未継承の objspace を全て継ぐので、
     * 後続の at-exit 処理（finalizer, IO flush, free-at-exit）が全 object を見られる。 */
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

st_table *
rb_ractor_targeted_hooks(rb_ractor_t *cr)
{
    return &cr->pub.targeted_hooks;
}

/* upstream が gc.c 内の static inline に移したので、ここで同じ判定を持つ。
 * generic fields 表を使う object かどうかの純粋な型/フラグ検査。 */
static inline bool
ractor_obj_using_gen_fields_table_p(VALUE obj)
{
    switch (BUILTIN_TYPE(obj)) {
      case T_DATA:
        return false;
      case T_STRUCT:
        if (!FL_TEST_RAW(obj, RSTRUCT_GEN_FIELDS)) return false;
        break;
      default:
        break;
    }
    return rb_obj_gen_fields_p(obj);
}

static void
rb_obj_set_shareable_no_assert(VALUE obj)
{
    /* FL_SHAREABLE を立てる。generic fields が per-Ractor 表にある object は、
     * flag 反転を generic_fields_lock 下の共有表への移送と交錯させるので、
     * ここでは flag を立てない。それ以外は直接立てる。 */
    if (rb_obj_gen_fields_p(obj) && ractor_obj_using_gen_fields_table_p(obj)) {
        rb_mv_generic_ivar_to_shared(obj); /* sets FL_SHAREABLE + pin, in order */
    }
    else {
        FL_SET_RAW(obj, FL_SHAREABLE);
        rb_gc_obj_became_shareable(obj);
    }

    if (BUILTIN_TYPE(obj) == T_FILE && RFILE(obj)->fptr) {
        /* fptr の VALUE メンバは make_shareable の traversal で到達されず（C struct 内、
         * WB 無しで格納）、shareable IO が owner 限定 object へ裸の辺を持つ。local GC は
         * shareable を辿らないので、owner が回収すると T_FILE mark が freed を踏む。shref を記録する。 */
        const struct rb_io *const fptr = RFILE(obj)->fptr;
        const VALUE members[] = {
            fptr->self, fptr->pathv, fptr->tied_io_for_writing,
            fptr->writeconv_asciicompat, fptr->writeconv_pre_ecopts,
            fptr->encs.ecopts, fptr->write_lock, fptr->timeout,
            fptr->wakeup_mutex,
        };
        for (size_t i = 0; i < numberof(members); i++) {
            const VALUE v = members[i];
            if (v && !RB_SPECIAL_CONST_P(v) && !RB_OBJ_SHAREABLE_P(v)) {
                rb_gc_writebarrier(obj, v);
            }
        }
    }

    if (rb_obj_gen_fields_p(obj)) {
        /* obj は既に shareable なので rb_obj_fields_no_ractor_check は正しい表を引く。
         * ここでは fields imemo 自身を shareable 化し、traversal で届かない
         * 隠しフィールド値の shref を記録する。 */
        VALUE fields = rb_obj_fields_no_ractor_check(obj);
        if (imemo_type_p(fields, imemo_fields)) {
            // no recursive mark
            FL_SET_RAW(fields, FL_SHAREABLE);
            rb_gc_obj_became_shareable(fields);
            // ただし traversal で到達しない field 値（隠し内部 ivar 等）は
            // unshareable のままになりうるので、shref を記録して
            // shareable fields imemo が正しい辺記録を保つようにする。
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
      case T_FILE:
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
    if (!RB_TYPE_P(obj, T_DATA)) {
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
        VM_ASSERT(RB_TYPE_P(obj, T_DATA));
        const rb_data_type_t *type = RTYPEDDATA_TYPE(obj);

        if (type->flags & RUBY_TYPED_FROZEN_SHAREABLE_NO_REC) {
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

static VALUE ractor_copy(VALUE obj); // 後述

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

    /* old -> new 対応表（素の st table）。OLD key は別 Ractor の objspace に
     * ある場合があるので、この Ractor の GC 辺にしてはならない（freed foreign key の
     * mark は UAF）。key は address 比較のみ。REPLACEMENT は rec_keepalive で生かす。 */
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

    /* enter_func の前に dedup する。再訪した共有/循環 node は記録済み replacement を
     * enter_func 無しで再利用する。さもないと copy 経路が作る一時 copy が
     * cross-objspace 辺を持ち objspace containment 不変条件を破る（無駄でもある）。 */
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

    /* enter/leave 関数は失敗を raise でなく traverse_stop で返すので、
     * ここが table の唯一の解放点。 */
    if (data.rec) st_free_table(data.rec);
    RB_GC_GUARD(data.rec_keepalive);

    if (stopped) {
        return Qundef;
    }
    else {
        return data.replacement;
    }
}

/* move courier: Ractor#send(move: true) の payload を、どの objspace にも属さない
 * xmalloc 構造体に直列化する（GC 管理外なので送信側 GC が mark/sweep/compact/race しない）。
 * node 配列＋id 参照で共有・循環を扱い、受信側が自 objspace で 2 パス再構築する。 */

enum move_node_kind {
    MOVE_K_REF,       /* immediate か shareable: 値で運ぶ */
    MOVE_K_STRING,
    MOVE_K_ARRAY,
    MOVE_K_HASH,
    MOVE_K_OBJECT,
    MOVE_K_STRUCT,
    MOVE_K_MATCH,
    MOVE_K_IO,
};

struct move_node {
    enum move_node_kind kind;
    bool frozen;
    /* 全 non-REF node が持つ instance/generic ivar（String や Array も
     * generic ivar を持ちうる） */
    uint32_t niv;
    ID *iv_ids;          /* courier 所有 */
    uint32_t *iv_vals;   /* courier 所有; node id */
    union {
        VALUE ref;
        struct { char *ptr; long len; int encidx; VALUE klass; } str;        /* courier が ptr を所有 */
        struct { long len; uint32_t *elems; VALUE klass; } ary;              /* courier が elems を所有 */
        struct { long size; uint32_t *kv; uint32_t ifnone_id; bool compare_by_id; bool proc_default; VALUE klass; } hash; /* kv(2*size) を所有 */
        struct { VALUE klass; } obj;
        struct { long len; uint32_t *elems; VALUE klass; } strct; /* elems を所有 */
        struct { uint32_t regexp_id, str_id; int num_regs; void *regs; VALUE klass; } match; /* regs を所有 */
        struct {
            struct rb_io *fptr;  /* ポインタで持ち越す（fd を所有） */
            VALUE klass;
            /* fptr の送信側 VALUE メンバは通常の child node として運ぶ。capture が
             * fptr から切り離し（T_FILE 節参照）、rebuild が受信側 shell を
             * RB_OBJ_WRITE で書き戻す。 */
            uint32_t pathv_id, ecopts_id, wc_pre_ecopts_id, wc_asciicompat_id, timeout_id;
        } io;
    } u;
};

struct rb_ractor_move_courier {
    struct move_node *nodes;
    uint32_t count;
    uint32_t capa;
    uint32_t root;
};

struct move_build {
    struct rb_ractor_move_courier *c;
    st_table *seen;   /* src VALUE -> (node id + 1) */
};

static uint32_t move_capture(struct move_build *b, VALUE obj);

static uint32_t
move_alloc_node(struct rb_ractor_move_courier *c)
{
    if (c->count == c->capa) {
        c->capa = c->capa ? c->capa * 2 : 8;
        REALLOC_N(c->nodes, struct move_node, c->capa);
    }
    return c->count++;
}

/* move 済み source を、flags==0 を経ずに正当な RactorMovedObject へ変える
 * （並行 foreign marker が常に元 object か shell のどちらかを見るように）。 */
static void
move_neutralize_source(VALUE obj)
{
    /* 殻は元のスロットに残るので capacity ビットを保持したまま、フィールド無しの
     * ROBJECT レイアウト・frozen な shape を与える。古い body が ivar として読まれず、
     * compaction の slot_size と shape_slot_size 一致検査も満たす。フラグ潰しの前に取る。 */
    shape_id_t shape_id = (RBASIC_SHAPE_ID(obj) & SHAPE_ID_CAPACITY_MASK) |
                          ROOT_SHAPE_ID | SHAPE_ID_LAYOUT_ROBJECT | SHAPE_ID_FL_FROZEN;

    /* source が非 T_OBJECT ホスト（ivar 持ちの String/Array 等）なら generic_fields
     * entry を削除する。下で obj は host でなくなり fields_obj が回収されるので、消さないと
     * freed 値を指す stale entry が残り global GC が踏む。 */
    rb_free_generic_ivar(obj);

    VALUE flags = T_OBJECT | FL_FREEZE | (RBASIC(obj)->flags & FL_PROMOTED);
    RBASIC_SET_CLASS_RAW(obj, rb_cRactorMovedObject);
    RBASIC(obj)->flags = flags;
    RBASIC_SET_FULL_SHAPE_ID(obj, shape_id);
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

/* obj の instance/generic ivar を node id に取り込む（値へ再帰）。
 * T_OBJECT の inline ivar も String/Array 等の generic ivar も扱う。 */
static void
move_capture_ivars(struct move_build *b, VALUE obj, uint32_t id)
{
    struct move_obj_ctx oc = { b, NULL, NULL, 0, 0 };
    rb_ivar_foreach_buffered(obj, move_capture_ivar_i, (st_data_t)&oc);
    b->c->nodes[id].niv = (uint32_t)oc.n;
    b->c->nodes[id].iv_ids = oc.ids;
    b->c->nodes[id].iv_vals = oc.vals;
}

/* obj を courier に取り込み子へ再帰し node id を返す。id は再帰前に登録するので
 * obj への循環は同じ node に解決する。c->nodes は再帰中に realloc されうるので
 * node フィールドは再帰後に書く。source の neutralize は switch 後に一度だけ。 */
static uint32_t
move_capture(struct move_build *b, VALUE obj)
{
    st_data_t existing;
    if (st_lookup(b->seen, (st_data_t)obj, &existing)) {
        return (uint32_t)existing - 1;
    }

    uint32_t id = move_alloc_node(b->c);
    st_insert(b->seen, (st_data_t)obj, (st_data_t)(uintptr_t)(id + 1));

    if (RB_SPECIAL_CONST_P(obj) || rb_ractor_shareable_p(obj)) {
        b->c->nodes[id].kind = MOVE_K_REF;
        b->c->nodes[id].frozen = false;
        b->c->nodes[id].niv = 0;
        b->c->nodes[id].iv_ids = NULL;
        b->c->nodes[id].iv_vals = NULL;
        b->c->nodes[id].u.ref = obj;
        return id;
    }

    /* 変更を始める前に move 不可を早期に弾く */
    if (BUILTIN_TYPE(obj) == T_FILE && RFILE(obj)->fptr == NULL) {
        rb_raise(rb_eRactorError, "can not move an uninitialized IO");
    }

    bool frozen = OBJ_FROZEN(obj);
    b->c->nodes[id].frozen = frozen;
    move_capture_ivars(b, obj, id);   /* 共通: instance/generic ivar */

    switch (BUILTIN_TYPE(obj)) {
      case T_STRING: {
        /* source に専有 buffer を持たせる（sharer を解除、静的 STR_NOFREE を複製）。
         * frozen でも内容でなく所有権を変えるだけで安全。以後 string は embed か、
         * 専有 heap buffer 所有か、shared ROOT（root には no-op）のいずれか。 */
        rb_str_make_independent(obj);
        long len = RSTRING_LEN(obj);
        int encidx = ENCODING_GET(obj);
        char *ptr;
        if (!STR_EMBED_P(obj) && rb_str_reembeddable_p(obj)) {
            /* 専有 heap buffer 所有: ポインタで持ち越す（zero-copy）。
             * source は buffer を free しない shell になる。 */
            ptr = RSTRING(obj)->as.heap.ptr;
        }
        else {
            /* embed か shared root: byte を courier 所有 buffer に複製する。
             * root の buffer を奪うと CoW child が dangling するので child に残す
             * （下の T_ARRAY の ARY_SHARED_ROOT_P 除外と同じ）。 */
            ptr = ALLOC_N(char, len + 1);
            if (len) memcpy(ptr, RSTRING_PTR(obj), len);
            ptr[len] = '\0';
        }
        b->c->nodes[id].kind = MOVE_K_STRING;
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
        b->c->nodes[id].kind = MOVE_K_ARRAY;
        b->c->nodes[id].u.ary.klass = RBASIC_CLASS(obj);
        b->c->nodes[id].u.ary.len = len;
        b->c->nodes[id].u.ary.elems = elems;
        /* source の専有 heap buffer を解放（child は読み終えた）。embed（buffer 無し）、
         * sharer（root が所有）、shared-root（他の array が指すので解放で dangling）は skip。 */
        if (!ARY_EMBED_P(obj) && !ARY_SHARED_P(obj) && !ARY_SHARED_ROOT_P(obj)) {
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
        b->c->nodes[id].kind = MOVE_K_HASH;
        b->c->nodes[id].u.hash.klass = RBASIC_CLASS(obj);
        b->c->nodes[id].u.hash.size = size;
        b->c->nodes[id].u.hash.kv = kv;
        b->c->nodes[id].u.hash.ifnone_id = ifnone_id;
        b->c->nodes[id].u.hash.compare_by_id = RTEST(rb_hash_compare_by_id_p(obj));
        b->c->nodes[id].u.hash.proc_default = FL_TEST_RAW(obj, RHASH_PROC_DEFAULT) != 0;
        /* source の st-table 内部を解放（ar table は slot 内） */
        rb_hash_free(obj);
        break;
      }

      case T_OBJECT:
        b->c->nodes[id].kind = MOVE_K_OBJECT;
        /* 本来の class を保持（singleton でも shareable なので cross-objspace 参照は安全）。
         * rebuild が非 singleton class で確保した後で付け直す。 */
        b->c->nodes[id].u.obj.klass = RBASIC_CLASS(obj);
        break;

      case T_STRUCT: {
        long len = RSTRUCT_LEN(obj);
        uint32_t *elems = len ? ALLOC_N(uint32_t, len) : NULL;
        for (long i = 0; i < len; i++) {
            elems[i] = move_capture(b, RSTRUCT_GET(obj, (int)i));
        }
        b->c->nodes[id].kind = MOVE_K_STRUCT;
        b->c->nodes[id].u.strct.len = len;
        b->c->nodes[id].u.strct.elems = elems;
        b->c->nodes[id].u.strct.klass = RBASIC_CLASS(obj);
        /* source の専有 heap buffer を解放（embed struct は持たない） */
        if (RSTRUCT_EMBED_LEN(obj) == 0) {
            ruby_xfree((void *)RSTRUCT_CONST_PTR(obj));
        }
        break;
      }

      case T_MATCH: {
        /* regexp と matched string は通常の child として運ぶ。re.c が
         * register を dump する（source の onig/char_offset を解放）。 */
        VALUE re, st;
        int nregs;
        void *regs = rb_match_move_dump(obj, &re, &st, &nregs);
        uint32_t rid = move_capture(b, re);
        uint32_t sid = move_capture(b, st);
        b->c->nodes[id].kind = MOVE_K_MATCH;
        b->c->nodes[id].u.match.regexp_id = rid;
        b->c->nodes[id].u.match.str_id = sid;
        b->c->nodes[id].u.match.num_regs = nregs;
        b->c->nodes[id].u.match.regs = regs;
        b->c->nodes[id].u.match.klass = RBASIC_CLASS(obj);
        break;
      }

      case T_FILE:
      {
        /* fptr（と fd）を丸ごとポインタで持ち越し、source は close しない shell になる。
         * fptr の VALUE メンバは送信側 object で husk 後は無 root になるので、通常の
         * child node として capture し fptr から切り離す。rebuild が受信側 shell を書き戻す。 */
        struct rb_io *fptr = RFILE(obj)->fptr;
        VM_ASSERT(!RTEST(fptr->tied_io_for_writing) && !RTEST(fptr->wakeup_mutex));
        uint32_t pathv_id   = move_capture(b, fptr->pathv);
        uint32_t ecopts_id  = move_capture(b, fptr->encs.ecopts);
        uint32_t wc_pre_id  = move_capture(b, fptr->writeconv_pre_ecopts);
        uint32_t wc_ac_id   = move_capture(b, fptr->writeconv_asciicompat);
        uint32_t timeout_id = move_capture(b, fptr->timeout);
        fptr->self = Qnil;   /* husk を指すため; attach 時に再構築 */
        fptr->pathv = Qnil;
        fptr->encs.ecopts = Qnil;
        fptr->writeconv_pre_ecopts = Qnil;
        fptr->writeconv_asciicompat = Qnil;
        fptr->timeout = Qnil;
        fptr->write_lock = Qnil;
        fptr->wakeup_mutex = Qnil;
        fptr->tied_io_for_writing = 0;  /* io.c は C 真偽で判定するので Qnil でなく 0 */
        b->c->nodes[id].kind = MOVE_K_IO;
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

    move_neutralize_source(obj);
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

/* move_capture の判定木を変更なしで辿る事前walk。capture は各 object を
 * husk しながら進むので、途中で move 不可に当たると graph が壊れ回復不能になる。
 * 「can not move」系のエラーは最初の変更前にここで全て raise する。 */
static void
move_preflight(VALUE obj, st_table *seen)
{
    if (RB_SPECIAL_CONST_P(obj) || rb_ractor_shareable_p(obj)) return;
    if (st_lookup(seen, (st_data_t)obj, NULL)) return;   /* cycle */
    st_insert(seen, (st_data_t)obj, 0);

    switch (BUILTIN_TYPE(obj)) {
      case T_STRING:
      case T_OBJECT:
        break;                       /* child は ivar のみ（下記） */
      case T_MATCH:
        break;                       /* child = Regexp（shareable）+ String */
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
            /* popen("r+") 系の対: 片方を move すると tied writer が
             * 送信側で dangling する */
            rb_raise(rb_eRactorError, "can not move an IO tied to a writer IO");
        }
        if (RTEST(fptr->wakeup_mutex)) {
            /* close 進行中: thread がこの IO で block している */
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

/* obj から move courier を作り、capture した元 object を全て RactorMovedObject 化する
 * （move セマンティクス）。xmalloc した courier を返す。 */
struct rb_ractor_move_courier *
ractor_move_courier_build(VALUE obj)
{
    /* 2 相（preflight → commit）。move 可否のエラーは graph が無傷のうちに
     * read-only walk から raise する。 */
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
    struct move_build b = { c, st_init_numtable() };
    c->root = move_capture(&b, obj);
    st_free_table(b.seen);
    return c;
}

/* shell は base/real class で作るので、元が subclass や singleton class を持つ場合は
 * shell に付け直して class を保つ（class は shareable なので参照は安全）。singleton は
 * attached object も送信側 source のままなので shell に re-attach する。 */
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

/* courier の graph を現在の Ractor の objspace に再構築し root を返す。
 * 2 パス（shell 確保 → fill）で参照循環を解く。 */
VALUE
ractor_move_courier_materialize(struct rb_ractor_move_courier *c)
{
    /* 隠し Array が全 shell を root する。後続の allocation（この Ractor の
     * GC を起こしうる）が graph の残りを作る間、生かしておくため。 */
    VALUE shells = rb_ary_hidden_new(c->count);

    for (uint32_t i = 0; i < c->count; i++) {
        struct move_node *n = &c->nodes[i];
        VALUE shell;
        switch (n->kind) {
          case MOVE_K_REF:
            shell = n->u.ref;
            break;
          case MOVE_K_STRING:
            shell = rb_enc_str_new(n->u.str.ptr, n->u.str.len, rb_enc_from_index(n->u.str.encidx));
            move_apply_moved_klass(shell, n->u.str.klass);
            break;
          case MOVE_K_ARRAY:
            shell = rb_ary_new_capa(n->u.ary.len);
            move_apply_moved_klass(shell, n->u.ary.klass);
            break;
          case MOVE_K_HASH:
            shell = n->u.hash.compare_by_id ? rb_ident_hash_new() : rb_hash_new();
            move_apply_moved_klass(shell, n->u.hash.klass);
            break;
          case MOVE_K_OBJECT:
            /* singleton class では確保できないので real class の instance を作り、
             * 後で付け直す */
            shell = rb_obj_alloc(rb_class_real(n->u.obj.klass));
            move_apply_moved_klass(shell, n->u.obj.klass);
            break;
          case MOVE_K_STRUCT:
            shell = rb_obj_alloc(rb_class_real(n->u.strct.klass));
            move_apply_moved_klass(shell, n->u.strct.klass);
            break;
          case MOVE_K_MATCH:
            shell = rb_match_move_alloc(rb_class_real(n->u.match.klass), n->u.match.num_regs);
            move_apply_moved_klass(shell, n->u.match.klass);
            break;
          case MOVE_K_IO:
            shell = rb_obj_alloc(rb_class_real(n->u.io.klass));
            move_apply_moved_klass(shell, n->u.io.klass);
            RFILE(shell)->fptr = n->u.io.fptr;
            n->u.io.fptr->self = shell;
            n->u.io.fptr = NULL; /* 消費済み: 新 IO が所有 */
            break;
          default:
            rb_bug("ractor_move_courier_materialize: bad node kind");
        }
        rb_ary_push(shells, shell);
    }

    for (uint32_t i = 0; i < c->count; i++) {
        struct move_node *n = &c->nodes[i];
        VALUE shell = RARRAY_AREF(shells, i);
        switch (n->kind) {
          case MOVE_K_ARRAY:
            for (long j = 0; j < n->u.ary.len; j++) {
                rb_ary_push(shell, RARRAY_AREF(shells, n->u.ary.elems[j]));
            }
            break;
          case MOVE_K_HASH: {
            for (long j = 0; j < n->u.hash.size; j++) {
                rb_hash_aset(shell, RARRAY_AREF(shells, n->u.hash.kv[2 * j]),
                             RARRAY_AREF(shells, n->u.hash.kv[2 * j + 1]));
            }
            /* default 値 / default proc を復元（freeze 前に設定） */
            VALUE ifnone = RARRAY_AREF(shells, n->u.hash.ifnone_id);
            if (n->u.hash.proc_default) {
                rb_hash_set_default_proc(shell, ifnone);
            }
            else if (ifnone != Qnil) {
                rb_hash_set_default(shell, ifnone);
            }
            break;
          }
          case MOVE_K_STRUCT:
            for (long j = 0; j < n->u.strct.len; j++) {
                RSTRUCT_SET(shell, (int)j, RARRAY_AREF(shells, n->u.strct.elems[j]));
            }
            break;
          case MOVE_K_MATCH:
            rb_match_move_load(shell, RARRAY_AREF(shells, n->u.match.regexp_id),
                               RARRAY_AREF(shells, n->u.match.str_id),
                               n->u.match.num_regs, n->u.match.regs);
            break;
          case MOVE_K_IO: {
            /* 再構築した VALUE メンバを fptr に書き戻す（capture で切り離した）。
             * write_lock / wakeup_mutex は nil のままで io.c が遅延再生成する。 */
            struct rb_io *fptr = RFILE(shell)->fptr;
            RB_OBJ_WRITE(shell, &fptr->pathv, RARRAY_AREF(shells, n->u.io.pathv_id));
            RB_OBJ_WRITE(shell, &fptr->encs.ecopts, RARRAY_AREF(shells, n->u.io.ecopts_id));
            RB_OBJ_WRITE(shell, &fptr->writeconv_pre_ecopts, RARRAY_AREF(shells, n->u.io.wc_pre_ecopts_id));
            RB_OBJ_WRITE(shell, &fptr->writeconv_asciicompat, RARRAY_AREF(shells, n->u.io.wc_asciicompat_id));
            RB_OBJ_WRITE(shell, &fptr->timeout, RARRAY_AREF(shells, n->u.io.timeout_id));
            break;
          }
          default:
            break;
        }
        /* instance/generic ivar を復元（全 non-REF node が持ちうる） */
        for (uint32_t j = 0; j < n->niv; j++) {
            rb_ivar_set(shell, n->iv_ids[j], RARRAY_AREF(shells, n->iv_vals[j]));
        }
    }

    /* fill 後に freeze する。frozen container/string も構築できるように。 */
    for (uint32_t i = 0; i < c->count; i++) {
        VALUE shell = RARRAY_AREF(shells, i);
        if (c->nodes[i].frozen && !RB_SPECIAL_CONST_P(shell)) {
            rb_obj_freeze(shell);
        }
    }

    VALUE root = c->count ? RARRAY_AREF(shells, c->root) : Qnil;
    RB_GC_GUARD(shells);
    return root;
}

void
ractor_move_courier_free(struct rb_ractor_move_courier *c)
{
    for (uint32_t i = 0; i < c->count; i++) {
        struct move_node *n = &c->nodes[i];
        ruby_xfree(n->iv_ids);
        ruby_xfree(n->iv_vals);
        switch (n->kind) {
          case MOVE_K_STRING:
            ruby_xfree(n->u.str.ptr);
            break;
          case MOVE_K_ARRAY:
            ruby_xfree(n->u.ary.elems);
            break;
          case MOVE_K_HASH:
            ruby_xfree(n->u.hash.kv);
            break;
          case MOVE_K_STRUCT:
            ruby_xfree(n->u.strct.elems);
            break;
          case MOVE_K_MATCH:
            rb_match_move_free(n->u.match.regs);
            break;
          case MOVE_K_IO:
            /* 消費済み IO は fptr==NULL。未消費（受信前に queue が壊れた）は
             * fd/fptr を保持したままになる。未配送 IO を捨てた時だけの leak。 */
            break;
          default:
            break;
        }
    }
    ruby_xfree(c->nodes);
    ruby_xfree(c);
}

/* courier が持つ唯一の VALUE を mark する: shareable/immediate（REF）と
 * object の class。どれも shareable なので mark は race せず、global GC が
 * courier 経由で到達可能に保つ。 */
void
ractor_move_courier_mark(struct rb_ractor_move_courier *c)
{
    if (!c) return;
    for (uint32_t i = 0; i < c->count; i++) {
        struct move_node *n = &c->nodes[i];
        if (n->kind == MOVE_K_REF) {
            rb_gc_mark(n->u.ref);
        }
        else if (n->kind == MOVE_K_OBJECT) {
            rb_gc_mark(n->u.obj.klass);
        }
        else if (n->kind == MOVE_K_STRUCT) {
            rb_gc_mark(n->u.strct.klass);
        }
        else if (n->kind == MOVE_K_MATCH) {
            rb_gc_mark(n->u.match.klass);
        }
        else if (n->kind == MOVE_K_IO) {
            rb_gc_mark(n->u.io.klass);
        }
        else if (n->kind == MOVE_K_STRING) {
            rb_gc_mark(n->u.str.klass);
        }
        else if (n->kind == MOVE_K_ARRAY) {
            rb_gc_mark(n->u.ary.klass);
        }
        else if (n->kind == MOVE_K_HASH) {
            rb_gc_mark(n->u.hash.klass);
        }
    }
}

/* message copy の traversal は #clone / #initialize_clone を呼ばない。中核の
 * container 型はここで native な shallow copy を作り（traversal が copy 内の child を
 * 書き換える）、他の unshareable 型は全体を Marshal 往復に fallback する。 */
static VALUE
ractor_native_shallow_copy(VALUE obj)
{
    VALUE copy;

    /* singleton class を持つ object は native copy 不可。Marshal に
     * fallback させ、適切なエラーを出させる。 */
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
        /* copy した例外が送信側 backtrace への生ポインタを objspace 跨ぎで
         * 持ち込まないようにする */
        if (rb_backtrace_p(obj)) {
            copy = rb_backtrace_dup(obj);
            break;
        }
        return Qundef;
      default:
        return Qundef;
    }

    /* 非 T_OBJECT ホストは instance 変数を generic fields 表に持つので複製する。 */
    if (BUILTIN_TYPE(obj) != T_OBJECT && UNLIKELY(rb_obj_gen_fields_p(obj))) {
        rb_copy_generic_ivar(copy, obj);
    }

    /* traversal が copy 内の child を raw store で書き換えるので、frozen bit は
     * 先に立ててよい（leave 時には元 object はもう見えない）。 */
    if (OBJ_FROZEN(obj)) {
        RB_FL_SET_RAW(copy, RUBY_FL_FREEZE);
    }
    return copy;
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
        if (UNDEF_P(copy)) return traverse_stop; /* native copy 不可 */
        data->replacement = copy;
        /* snapshot 作成中に copy が generic-ivar host なら、その fields_obj を対応表に
         * 記録する。こうすると受信側 materialize が送信側の per-Ractor 表を跨いで
         * 読まずに済む。表は host が出て初めて遅延確保する。 */
        rb_ractor_t *cr = GET_RACTOR();
        if (cr->gen_fields_capturing &&
            BUILTIN_TYPE(copy) != T_OBJECT && rb_obj_gen_fields_p(copy)) {
            if (cr->gen_fields_capture == NULL) {
                cr->gen_fields_capture = st_init_numtable();
            }
            st_insert(cr->gen_fields_capture, (st_data_t)copy,
                      (st_data_t)rb_obj_fields_no_ractor_check(copy));
        }
        return traverse_cont;
    }
}

static enum obj_traverse_iterator_result
copy_leave(VALUE obj, struct obj_traverse_replace_data *data)
{
    return traverse_cont;
}

/* obj の graph の native deep copy。native copier が非対応の型を含むと Qundef
 * （呼び出し側は Marshal に fallback）。 */
static VALUE
ractor_copy_native_try(VALUE obj)
{
    return rb_obj_traverse_replace(obj, copy_enter, copy_leave, false);
}

/* 同一 objspace の deep copy（Ractor.make_shareable(obj, copy: true)）。
 * まず native、駄目なら全体を Marshal 往復する。 */
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

        /* 削除済み key は 1 回の collection で全 Ractor の storage から purge し、
         * その struct を最後に free する。これは全 Ractor を他 marker 無しで
         * 巡る collection、つまり global GC（か single-objspace）でのみ可能。 */
        if (rb_gc_single_objspace_p() || rb_gc_during_global_gc_p()) {
            for (int i=0; i<freed_ractor_local_keys.cnt; i++) {
                rb_ractor_local_key_t key = freed_ractor_local_keys.keys[i];
                st_data_t val, k = (st_data_t)key;
                if (st_delete(r->local_storage, &k, &val) &&
                    (key = (rb_ractor_local_key_t)k)->type->free) {
                    (*key->type->free)((void *)val);
                }
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
    /* freed-key の struct は、全 Ractor の storage から他 marker 無しで purge した
     * collection、つまり global GC（か single-objspace）でのみ解放できる。local GC も
     * gc_marks_finish 経由でここに来るが、その時は何もしない（二重 free 防止）。 */
    if (!(rb_gc_single_objspace_p() || rb_gc_during_global_gc_p())) {
        return;
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
