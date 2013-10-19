#include <ruby.h>
#include <stdio.h>

int rb_bug_reporter_add(void (*func)(FILE *, void *), void *data);

static void
sample_bug_reporter(FILE *out, void *ptr)
{
    int n = (int)(uintptr_t)ptr;
    fprintf(out, "Sample bug reporter: %d\n", n);
}

static VALUE
register_sample_bug_reporter(VALUE self, VALUE obj)
{
    rb_bug_reporter_add(sample_bug_reporter, (void *)(uintptr_t)NUM2INT(obj));
    return Qnil;
}

void
Init_bug_reporter(void)
{
    rb_define_global_function("register_sample_bug_reporter", register_sample_bug_reporter, 1);
}
