#include "ruby/ruby.h"
#include "ruby/thread.h"
#include <dlfcn.h>

struct data_for_loop_dlsym {
    const char *name;
    volatile int stop;
};

static void*
native_loop_dlsym(void *data)
{
    struct data_for_loop_dlsym *s = data;

    while (!(s->stop)) {
        dlsym(RTLD_DEFAULT, s->name);
    }

    return NULL;
}

static void
ubf_for_loop_dlsym(void *data)
{
    struct data_for_loop_dlsym *s = data;

    s->stop = 1;

    return;
}

static VALUE
loop_dlsym(VALUE self, VALUE name)
{
    struct data_for_loop_dlsym d;

    d.stop = 0;
    d.name = StringValuePtr(name);

    rb_thread_call_without_gvl(native_loop_dlsym, &d,
                               ubf_for_loop_dlsym, &d);

    return self;
}

void
Init_infinite_loop_dlsym(void)
{
    rb_define_method(rb_cThread, "__infinite_loop_dlsym__", loop_dlsym, 1);
}
