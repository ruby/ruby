#include "ruby.h"
#ifdef HAVE_WORKING_FORK
# ifdef HAVE_SYS_TYPES_H
#   include <sys/types.h>
# endif
# ifdef HAVE_SYS_MMAN_H
#   include <sys/mman.h>
# endif
# include <pthread.h>
#endif
#include <errno.h>

static ID id_prepare;

#if defined HAVE_MINHERIT && !defined MAP_INHERIT_ZERO
# undef HAVE_MINHERIT
#endif

#if defined HAVE_MINHERIT || !defined HAVE_WORKING_FORK
struct fork_detector {
    VALUE value;
};
# if defined HAVE_MINHERIT
static void
fork_detector_free(void *p)
{
    munmap(p, sizeof(struct fork_detector));
}
# else
# define fork_detector_free RUBY_TYPED_NEVER_FREE
# endif
#else
# ifdef __GLIBC__
extern void *__dso_handle;
extern int __register_atfork(void (*)(void), void(*)(void), void (*)(void), void *);
#   define ATFORK(f) __register_atfork(NULL, NULL, (f), __dso_handle)
# else
#   define ATFORK(f) pthread_atfork(NULL, NULL, (f))
# endif
struct fork_detector {
    struct fork_detector *next;
    VALUE value;
};

static struct fork_detector *detector;

static void
forkhandler(void)
{
    struct fork_detector *p;
    for (p = detector; p; p = p->next) {
	p->value = Qfalse;
    }
}

static void
fork_detector_free(void *p)
{
    struct fork_detector **ptr;
    for (ptr = &detector; p != *ptr; ptr = &(*ptr)->next) {
	if (!*ptr) {
	    rb_fatal("not registered fork detector: %p", p);
	}
    }
    *ptr = ((struct fork_detector *)p)->next;
}
#endif

static void
fork_detector_mark(void *p)
{
    struct fork_detector *ptr = p;
    rb_gc_mark(ptr->value);
}

static size_t
fork_detector_memsize(const void *p)
{
    return sizeof(struct fork_detector);
}

static const rb_data_type_t fork_detector_type = {
    "fork-detector",
    {
	fork_detector_mark,
	fork_detector_free,
	fork_detector_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
fork_detector_alloc(VALUE klass)
{
    struct fork_detector *ptr;
#if defined HAVE_MINHERIT
    VALUE obj = TypedData_Wrap_Struct(klass, &fork_detector_type, NULL);
    ptr = mmap(NULL, sizeof(*ptr), PROT_READ|PROT_WRITE,
	       MAP_ANON|MAP_PRIVATE, -1, 0);
    if (ptr == MAP_FAILED) {
	int e = errno;
	rb_syserr_fail(e, "mmap");
    }
    if (minherit(ptr, sizeof(*ptr), MAP_INHERIT_ZERO)) {
	int e = errno;
	munmap(ptr, sizeof(*ptr));
	rb_syserr_fail(e, "minherit");
    }
    DATA_PTR(obj) = ptr;
#else
    VALUE obj = TypedData_Make_Struct(klass, struct fork_detector, &fork_detector_type, ptr);
# ifdef HAVE_WORKING_FORK
    ptr->next = detector;
    detector = ptr;
# endif
#endif
    return obj;
}

static VALUE
fork_detector_set(VALUE self, VALUE obj)
{
    struct fork_detector *ptr = rb_check_typeddata(self, &fork_detector_type);
    VALUE old = ptr->value;
    if (old)
	rb_raise(rb_eRuntimeError, "%"PRIsVALUE" is already set to %"PRIsVALUE,
		 self, old);
    ptr->value = obj;
    return self;
}

static VALUE
fork_detector_get(VALUE self)
{
    struct fork_detector *ptr = rb_check_typeddata(self, &fork_detector_type);
    VALUE obj = ptr->value;
    if (!obj) {
	obj = rb_funcallv(self, id_prepare, 0, 0);
	if (!obj) rb_raise(rb_eRuntimeError, "failed to prepare");
	ptr->value = obj;
    }
    return obj;
}

static VALUE
fork_detector_get_p(VALUE self)
{
    struct fork_detector *ptr = rb_check_typeddata(self, &fork_detector_type);
    VALUE obj = ptr->value;
    if (!obj) obj = Qnil;
    return obj;
}

static VALUE
fork_detector_prepare(VALUE self)
{
    rb_raise(rb_eTypeError, "%"PRIsVALUE" needs prepare", CLASS_OF(self));
}

static VALUE
fork_detector_init(int argc, VALUE *argv, VALUE self)
{
    if (rb_check_arity(argc, 0, 1))
	fork_detector_set(self, argv[0]);
    return self;
}

void
InitVM_securerandom(void)
{
    VALUE m = rb_define_module("SecureRandom");
    VALUE f = rb_define_class_under(m, "ForkDetector", rb_cData);
    rb_define_alloc_func(f, fork_detector_alloc);
    rb_define_method(f, "initialize", fork_detector_init, -1);
    rb_define_method(f, "set", fork_detector_set, 1);
    rb_define_method(f, "get", fork_detector_get, 0);
    rb_define_method(f, "get?", fork_detector_get_p, 0);
    rb_define_method(f, "prepare", fork_detector_prepare, 0);
}

void
Init_securerandom(void)
{
    id_prepare = rb_intern_const("prepare");
    InitVM(securerandom);
#if defined ATFORK
    ATFORK(forkhandler);
#endif
}

