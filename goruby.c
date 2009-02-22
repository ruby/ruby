void Init_golf(void);
#define ruby_run_node goruby_run_node
#include "main.c"
#undef ruby_run_node

RUBY_EXTERN int ruby_run_node(void*);
RUBY_EXTERN void ruby_init_ext(const char *name, void (*init)(void));

static VALUE
init_golf(VALUE arg)
{
    ruby_init_ext("golf", Init_golf);
    return arg;
}

int
goruby_run_node(void *arg)
{
    int state;
    if (NIL_P(rb_protect(init_golf, Qtrue, &state))) {
	return state == EXIT_SUCCESS ? EXIT_FAILURE : state;
    }
    return ruby_run_node(arg);
}
