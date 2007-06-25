
#ifndef RUBY_GC_H
#define RUBY_GC_H 1

NOINLINE(void rb_gc_set_stack_end(VALUE **stack_end_p));
NOINLINE(void rb_gc_save_machine_context(rb_thread_t *));

/* for GC debug */

#ifndef RUBY_MARK_FREE_DEBUG
#define RUBY_MARK_FREE_DEBUG 0
#endif

#if RUBY_MARK_FREE_DEBUG
extern int ruby_gc_debug_indent = 0;

static void
rb_gc_debug_indent(void)
{
    printf("%*s", ruby_gc_debug_indent, "");
}

static void
rb_gc_debug_body(char *mode, char *msg, int st, void *ptr)
{
    if (st == 0) {
	ruby_gc_debug_indent--;
    }
    rb_gc_debug_indent();
    printf("%s: %s %s (%p)\n", mode, st ? "->" : "<-", msg, ptr);

    if (st) {
	ruby_gc_debug_indent++;
    }

    fflush(stdout);
}

#define RUBY_MARK_ENTER(msg) rb_gc_debug_body("mark", msg, 1, ptr)
#define RUBY_MARK_LEAVE(msg) rb_gc_debug_body("mark", msg, 0, ptr)
#define RUBY_FREE_ENTER(msg) rb_gc_debug_body("free", msg, 1, ptr)
#define RUBY_FREE_LEAVE(msg) rb_gc_debug_body("free", msg, 0, ptr)
#define RUBY_GC_INFO         rb_gc_debug_indent(); printf

#else
#define RUBY_MARK_ENTER(msg)
#define RUBY_MARK_LEAVE(msg)
#define RUBY_FREE_ENTER(msg)
#define RUBY_FREE_LEAVE(msg)
#define RUBY_GC_INFO if(0)printf
#endif

#define RUBY_MARK_UNLESS_NULL(ptr) if(RTEST(ptr)){rb_gc_mark(ptr);}
#define RUBY_FREE_UNLESS_NULL(ptr) if(ptr){ruby_xfree(ptr);}
#endif /* RUBY_GC_H */

