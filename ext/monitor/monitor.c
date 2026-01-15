#include "ruby/ruby.h"

/* Thread::Monitor */

struct rb_monitor {
    long count;
    VALUE owner;
    VALUE mutex;
};

static void
monitor_mark(void *ptr)
{
    struct rb_monitor *mc = ptr;
    rb_gc_mark_movable(mc->owner);
    rb_gc_mark_movable(mc->mutex);
}

static void
monitor_compact(void *ptr)
{
    struct rb_monitor *mc = ptr;
    mc->owner = rb_gc_location(mc->owner);
    mc->mutex = rb_gc_location(mc->mutex);
}

static const rb_data_type_t monitor_data_type = {
    .wrap_struct_name = "monitor",
    .function = {
        .dmark = monitor_mark,
        .dfree = RUBY_TYPED_DEFAULT_FREE,
        .dsize = NULL, // Fully embeded
        .dcompact = monitor_compact,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE,
};

static VALUE
monitor_alloc(VALUE klass)
{
    struct rb_monitor *mc;
    VALUE obj;

    obj = TypedData_Make_Struct(klass, struct rb_monitor, &monitor_data_type, mc);
    RB_OBJ_WRITE(obj, &mc->mutex, rb_mutex_new());
    RB_OBJ_WRITE(obj, &mc->owner, Qnil);
    mc->count = 0;

    return obj;
}

static struct rb_monitor *
monitor_ptr(VALUE monitor)
{
    struct rb_monitor *mc;
    TypedData_Get_Struct(monitor, struct rb_monitor, &monitor_data_type, mc);
    return mc;
}

static bool
mc_owner_p(struct rb_monitor *mc, VALUE current_fiber)
{
    return mc->owner == current_fiber;
}

/*
 * call-seq:
 *   try_enter -> true or false
 *
 * Attempts to enter exclusive section.  Returns +false+ if lock fails.
 */
static VALUE
monitor_try_enter(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);

    VALUE current_fiber = rb_fiber_current();
    if (!mc_owner_p(mc, current_fiber)) {
        if (!rb_mutex_trylock(mc->mutex)) {
            return Qfalse;
        }
        RB_OBJ_WRITE(monitor, &mc->owner, current_fiber);
        mc->count = 0;
    }
    mc->count += 1;
    return Qtrue;
}


struct monitor_args {
    VALUE monitor;
    struct rb_monitor *mc;
    VALUE current_fiber;
};

static inline void
monitor_args_init(struct monitor_args *args, VALUE monitor)
{
    args->monitor = monitor;
    args->mc = monitor_ptr(monitor);
    args->current_fiber = rb_fiber_current();
}

static void
monitor_enter0(struct monitor_args *args)
{
    if (!mc_owner_p(args->mc, args->current_fiber)) {
        rb_mutex_lock(args->mc->mutex);
        RB_OBJ_WRITE(args->monitor, &args->mc->owner, args->current_fiber);
        args->mc->count = 0;
    }
    args->mc->count++;
}

/*
 * call-seq:
 *   enter -> nil
 *
 * Enters exclusive section.
 */
static VALUE
monitor_enter(VALUE monitor)
{
    struct monitor_args args;
    monitor_args_init(&args, monitor);
    monitor_enter0(&args);
    return Qnil;
}

static inline void
monitor_check_owner0(struct monitor_args *args)
{
    if (!mc_owner_p(args->mc, args->current_fiber)) {
        rb_raise(rb_eThreadError, "current fiber not owner");
    }
}

/* :nodoc: */
static VALUE
monitor_check_owner(VALUE monitor)
{
    struct monitor_args args;
    monitor_args_init(&args, monitor);
    monitor_check_owner0(&args);
    return Qnil;
}

static void
monitor_exit0(struct monitor_args *args)
{
    monitor_check_owner0(args);

    if (args->mc->count <= 0) rb_bug("monitor_exit: count:%d", (int)args->mc->count);
    args->mc->count--;

    if (args->mc->count == 0) {
        RB_OBJ_WRITE(args->monitor, &args->mc->owner, Qnil);
        rb_mutex_unlock(args->mc->mutex);
    }
}

/*
 * call-seq:
 *   exit -> nil
 *
 * Leaves exclusive section.
 */
static VALUE
monitor_exit(VALUE monitor)
{
    struct monitor_args args;
    monitor_args_init(&args, monitor);
    monitor_exit0(&args);
    return Qnil;
}

/* :nodoc: */
static VALUE
monitor_locked_p(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);
    return rb_mutex_locked_p(mc->mutex);
}

/* :nodoc: */
static VALUE
monitor_owned_p(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);
    return rb_mutex_locked_p(mc->mutex) && mc_owner_p(mc, rb_fiber_current()) ? Qtrue : Qfalse;
}

static VALUE
monitor_exit_for_cond(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);
    long cnt = mc->count;
    RB_OBJ_WRITE(monitor, &mc->owner, Qnil);
    mc->count = 0;
    return LONG2NUM(cnt);
}

struct wait_for_cond_data {
    VALUE monitor;
    VALUE cond;
    VALUE timeout;
    VALUE count;
};

static VALUE
monitor_wait_for_cond_body(VALUE v)
{
    struct wait_for_cond_data *data = (struct wait_for_cond_data *)v;
    struct rb_monitor *mc = monitor_ptr(data->monitor);
    // cond.wait(monitor.mutex, timeout)
    VALUE signaled = rb_funcall(data->cond, rb_intern("wait"), 2, mc->mutex, data->timeout);
    return RTEST(signaled) ? Qtrue : Qfalse;
}

static VALUE
monitor_enter_for_cond(VALUE v)
{
    // assert(rb_mutex_owned_p(mc->mutex) == Qtrue)
    // but rb_mutex_owned_p is not exported...

    struct wait_for_cond_data *data = (struct wait_for_cond_data *)v;
    struct rb_monitor *mc = monitor_ptr(data->monitor);
    RB_OBJ_WRITE(data->monitor, &mc->owner, rb_fiber_current());
    mc->count = NUM2LONG(data->count);
    return Qnil;
}

/* :nodoc: */
static VALUE
monitor_wait_for_cond(VALUE monitor, VALUE cond, VALUE timeout)
{
    VALUE count = monitor_exit_for_cond(monitor);
    struct wait_for_cond_data data = {
        monitor,
        cond,
        timeout,
        count,
    };

    return rb_ensure(monitor_wait_for_cond_body, (VALUE)&data,
                     monitor_enter_for_cond, (VALUE)&data);
}

static VALUE
monitor_sync_body(VALUE monitor)
{
    return rb_yield_values(0);
}

static VALUE
monitor_sync_ensure(VALUE v_args)
{
    monitor_exit0((struct monitor_args *)v_args);
    return Qnil;
}

/*
 * call-seq:
 *   synchronize { } -> result of the block
 *
 * Enters exclusive section and executes the block.  Leaves the exclusive
 * section automatically when the block exits.  See example under
 * +MonitorMixin+.
 */
static VALUE
monitor_synchronize(VALUE monitor)
{
    struct monitor_args args;
    monitor_args_init(&args, monitor);
    monitor_enter0(&args);
    return rb_ensure(monitor_sync_body, (VALUE)&args, monitor_sync_ensure, (VALUE)&args);
}

void
Init_monitor(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

    VALUE rb_cMonitor = rb_define_class("Monitor", rb_cObject);
    rb_define_alloc_func(rb_cMonitor, monitor_alloc);

    rb_define_method(rb_cMonitor, "try_enter", monitor_try_enter, 0);
    rb_define_method(rb_cMonitor, "enter", monitor_enter, 0);
    rb_define_method(rb_cMonitor, "exit", monitor_exit, 0);
    rb_define_method(rb_cMonitor, "synchronize", monitor_synchronize, 0);

    /* internal methods for MonitorMixin */
    rb_define_method(rb_cMonitor, "mon_locked?", monitor_locked_p, 0);
    rb_define_method(rb_cMonitor, "mon_check_owner", monitor_check_owner, 0);
    rb_define_method(rb_cMonitor, "mon_owned?", monitor_owned_p, 0);

    /* internal methods for MonitorMixin::ConditionVariable */
    rb_define_method(rb_cMonitor, "wait_for_cond", monitor_wait_for_cond, 2);
}
