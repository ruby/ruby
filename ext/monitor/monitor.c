#include "ruby/ruby.h"

/* Thread::Monitor */

struct rb_monitor {
    long count;
    const VALUE owner;
    const VALUE mutex;
};

static void
monitor_mark(void *ptr)
{
    struct rb_monitor *mc = ptr;
    rb_gc_mark(mc->owner);
    rb_gc_mark(mc->mutex);
}

static size_t
monitor_memsize(const void *ptr)
{
    return sizeof(struct rb_monitor);
}

static const rb_data_type_t monitor_data_type = {
    "monitor",
    {monitor_mark, RUBY_TYPED_DEFAULT_FREE, monitor_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
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

static int
mc_owner_p(struct rb_monitor *mc)
{
    return mc->owner == rb_thread_current();
}

static VALUE
monitor_try_enter(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);

    if (!mc_owner_p(mc)) {
        if (!rb_mutex_trylock(mc->mutex)) {
            return Qfalse;
        }
        RB_OBJ_WRITE(monitor, &mc->owner, rb_thread_current());
        mc->count = 0;
    }
    mc->count += 1;
    return Qtrue;
}

static VALUE
monitor_enter(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);
    if (!mc_owner_p(mc)) {
        rb_mutex_lock(mc->mutex);
        RB_OBJ_WRITE(monitor, &mc->owner, rb_thread_current());
        mc->count = 0;
    }
    mc->count++;
    return Qnil;
}

static VALUE
monitor_check_owner(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);
    if (!mc_owner_p(mc)) {
        rb_raise(rb_eThreadError, "current thread not owner");
    }
    return Qnil;
}

static VALUE
monitor_exit(VALUE monitor)
{
    monitor_check_owner(monitor);

    struct rb_monitor *mc = monitor_ptr(monitor);

    if (mc->count <= 0) rb_bug("monitor_exit: count:%d\n", (int)mc->count);
    mc->count--;

    if (mc->count == 0) {
        RB_OBJ_WRITE(monitor, &mc->owner, Qnil);
        rb_mutex_unlock(mc->mutex);
    }
    return Qnil;
}

static VALUE
monitor_locked_p(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);
    return rb_mutex_locked_p(mc->mutex);
}

static VALUE
monitor_owned_p(VALUE monitor)
{
    struct rb_monitor *mc = monitor_ptr(monitor);
    return (rb_mutex_locked_p(mc->mutex) && mc_owner_p(mc)) ? Qtrue : Qfalse;
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
    rb_funcall(data->cond, rb_intern("wait"), 2, mc->mutex, data->timeout);
    return Qtrue;
}

static VALUE
monitor_enter_for_cond(VALUE v)
{
    // assert(rb_mutex_owned_p(mc->mutex) == Qtrue)
    // but rb_mutex_owned_p is not exported...

    struct wait_for_cond_data *data = (struct wait_for_cond_data *)v;
    struct rb_monitor *mc = monitor_ptr(data->monitor);
    RB_OBJ_WRITE(data->monitor, &mc->owner, rb_thread_current());
    mc->count = NUM2LONG(data->count);
    return Qnil;
}

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
monitor_sync_ensure(VALUE monitor)
{
    return monitor_exit(monitor);
}

static VALUE
monitor_synchronize(VALUE monitor)
{
    monitor_enter(monitor);
    return rb_ensure(monitor_sync_body, monitor, monitor_sync_ensure, monitor);
}

void
Init_monitor(void)
{
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

    /* internal methods for MonitorMixin::ConditionalVariable */
    rb_define_method(rb_cMonitor, "wait_for_cond", monitor_wait_for_cond, 2);
}
