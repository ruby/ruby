
#ifndef RUBY_GC_H
#define RUBY_GC_H 1

#if defined(__x86_64__) && !defined(_ILP32) && defined(__GNUC__)
#define SET_MACHINE_STACK_END(p) __asm__ __volatile__ ("movq\t%%rsp, %0" : "=r" (*(p)))
#elif defined(__i386) && defined(__GNUC__)
#define SET_MACHINE_STACK_END(p) __asm__ __volatile__ ("movl\t%%esp, %0" : "=r" (*(p)))
#else
NOINLINE(void rb_gc_set_stack_end(VALUE **stack_end_p));
#define SET_MACHINE_STACK_END(p) rb_gc_set_stack_end(p)
#define USE_CONSERVATIVE_STACK_END
#endif

/* for GC debug */

#ifndef RUBY_MARK_FREE_DEBUG
#define RUBY_MARK_FREE_DEBUG 0
#endif

#if RUBY_MARK_FREE_DEBUG
extern int ruby_gc_debug_indent;

static inline void
rb_gc_debug_indent(void)
{
    printf("%*s", ruby_gc_debug_indent, "");
}

static inline void
rb_gc_debug_body(const char *mode, const char *msg, int st, void *ptr)
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

#define RUBY_MARK_ENTER(msg) rb_gc_debug_body("mark", (msg), 1, ptr)
#define RUBY_MARK_LEAVE(msg) rb_gc_debug_body("mark", (msg), 0, ptr)
#define RUBY_FREE_ENTER(msg) rb_gc_debug_body("free", (msg), 1, ptr)
#define RUBY_FREE_LEAVE(msg) rb_gc_debug_body("free", (msg), 0, ptr)
#define RUBY_GC_INFO         rb_gc_debug_indent(); printf

#else
#define RUBY_MARK_ENTER(msg)
#define RUBY_MARK_LEAVE(msg)
#define RUBY_FREE_ENTER(msg)
#define RUBY_FREE_LEAVE(msg)
#define RUBY_GC_INFO if(0)printf
#endif

#define RUBY_MARK_NO_PIN_UNLESS_NULL(ptr) do { \
    VALUE markobj = (ptr); \
    if (RTEST(markobj)) {rb_gc_mark_no_pin(markobj);} \
} while (0)
#define RUBY_MARK_UNLESS_NULL(ptr) do { \
    VALUE markobj = (ptr); \
    if (RTEST(markobj)) {rb_gc_mark(markobj);} \
} while (0)
#define RUBY_FREE_UNLESS_NULL(ptr) if(ptr){ruby_xfree(ptr);(ptr)=NULL;}

#if STACK_GROW_DIRECTION > 0
# define STACK_UPPER(x, a, b) (a)
#elif STACK_GROW_DIRECTION < 0
# define STACK_UPPER(x, a, b) (b)
#else
RUBY_EXTERN int ruby_stack_grow_direction;
int ruby_get_stack_grow_direction(volatile VALUE *addr);
# define stack_growup_p(x) (			\
	(ruby_stack_grow_direction ?		\
	 ruby_stack_grow_direction :		\
	 ruby_get_stack_grow_direction(x)) > 0)
# define STACK_UPPER(x, a, b) (stack_growup_p(x) ? (a) : (b))
#endif

#if STACK_GROW_DIRECTION
#define STACK_GROW_DIR_DETECTION
#define STACK_DIR_UPPER(a,b) STACK_UPPER(0, (a), (b))
#else
#define STACK_GROW_DIR_DETECTION VALUE stack_grow_dir_detection
#define STACK_DIR_UPPER(a,b) STACK_UPPER(&stack_grow_dir_detection, (a), (b))
#endif
#define IS_STACK_DIR_UPPER() STACK_DIR_UPPER(1,0)

const char *rb_obj_info(VALUE obj);
const char *rb_raw_obj_info(char *buff, const int buff_size, VALUE obj);
void rb_obj_info_dump(VALUE obj);

VALUE rb_gc_disable_no_rest(void);

struct rb_thread_struct;

RUBY_SYMBOL_EXPORT_BEGIN

/* exports for objspace module */
size_t rb_objspace_data_type_memsize(VALUE obj);
void rb_objspace_reachable_objects_from(VALUE obj, void (func)(VALUE, void *), void *data);
void rb_objspace_reachable_objects_from_root(void (func)(const char *category, VALUE, void *), void *data);
int rb_objspace_markable_object_p(VALUE obj);
int rb_objspace_internal_object_p(VALUE obj);
int rb_objspace_marked_object_p(VALUE obj);
int rb_objspace_garbage_object_p(VALUE obj);

void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);

void rb_objspace_each_objects_without_setup(
    int (*callback)(void *, void *, size_t, void *),
    void *data);

RUBY_SYMBOL_EXPORT_END

#endif /* RUBY_GC_H */
