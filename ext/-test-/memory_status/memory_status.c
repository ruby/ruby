#include "ruby.h"
#ifdef __APPLE__
# include <mach/mach.h>
# include <mach/message.h>
# include <mach/kern_return.h>
# include <mach/task_info.h>
#endif

static VALUE cMemoryStatus;

static VALUE
read_status(VALUE self)
{
    VALUE size = INT2FIX(0);
#if defined __APPLE__
    VALUE rss;
    kern_return_t error;
    mach_msg_type_number_t out_count;
    mach_task_basic_info_data_t taskinfo;

    taskinfo.virtual_size = 0;
    out_count = MACH_TASK_BASIC_INFO_COUNT;
    error = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
		      (task_info_t)&taskinfo, &out_count);
    if (error != KERN_SUCCESS) return Qnil;
    size = ULL2NUM(taskinfo.virtual_size);
    rss = ULL2NUM(taskinfo.resident_size);
    rb_struct_aset(self, INT2FIX(1), rss);
#endif
    rb_struct_aset(self, INT2FIX(0), size);
    return self;
}

void
Init_memory_status(void)
{
    VALUE mMemory = rb_define_module("Memory");
    cMemoryStatus =
	rb_struct_define_under(mMemory, "Status", "size",
#if defined __APPLE__
			       "rss",
#endif
			       (char *)NULL);
    rb_define_method(cMemoryStatus, "_update", read_status, 0);
}
