
#ifndef RUBY_GC_H
#define RUBY_GC_H 1

NOINLINE(void rb_gc_set_stack_end(VALUE **stack_end_p));
NOINLINE(void rb_gc_save_machine_context(rb_thread_t *));

/* for GC debug */

#ifndef MARK_FREE_DEBUG
#define MARK_FREE_DEBUG 0
#endif


#if MARK_FREE_DEBUG
static int g_indent = 0;

static void
rb_gc_debug_indent(void)
{
    int i;
    for (i = 0; i < g_indent; i++) {
	printf(" ");
    }
}

static void
rb_gc_debug_body(char *mode, char *msg, int st, void *ptr)
{
    if (st == 0) {
	g_indent--;
    }
    rb_gc_debug_indent();
    printf("%s: %s %s (%p)\n", mode, st ? "->" : "<-", msg, ptr);
    if (st) {
	g_indent++;
    }
    fflush(stdout);
}

#define MARK_REPORT_ENTER(msg) rb_gc_debug_body("mark", msg, 1, ptr)
#define MARK_REPORT_LEAVE(msg) rb_gc_debug_body("mark", msg, 0, ptr)
#define FREE_REPORT_ENTER(msg) rb_gc_debug_body("free", msg, 1, ptr)
#define FREE_REPORT_LEAVE(msg) rb_gc_debug_body("free", msg, 0, ptr)
#define GC_INFO                rb_gc_debug_indent(); printf

#else
#define MARK_REPORT_ENTER(msg)
#define MARK_REPORT_LEAVE(msg)
#define FREE_REPORT_ENTER(msg)
#define FREE_REPORT_LEAVE(msg)
#define GC_INFO if(0)printf
#endif

#define MARK_UNLESS_NULL(ptr) if(ptr){rb_gc_mark(ptr);}
#define FREE_UNLESS_NULL(ptr) if(ptr){ruby_xfree(ptr);}
#endif /* RUBY_GC_H */

