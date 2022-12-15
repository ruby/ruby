#ifndef INTERNAL_GC_H                                    /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_GC_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for GC.
 */
#include "ruby/internal/config.h"

#include <stddef.h>             /* for size_t */

#include "internal/compilers.h" /* for __has_attribute */
#include "ruby/ruby.h"          /* for rb_event_flag_t */

struct rb_execution_context_struct; /* in vm_core.h */
struct rb_objspace; /* in vm_core.h */

#ifdef NEWOBJ_OF
# undef NEWOBJ_OF
# undef RB_NEWOBJ_OF
# undef RB_OBJ_WRITE
#endif

#define RVALUE_SIZE (sizeof(struct RBasic) + sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX]))

#define RB_RVARGC_NEWOBJ_OF(var, T, c, f, s) \
  T *(var) = (T *)(((f) & FL_WB_PROTECTED) ? \
                   rb_wb_protected_newobj_of((c), (f) & ~FL_WB_PROTECTED, s) : \
                   rb_wb_unprotected_newobj_of((c), (f), s))

#define RB_RVARGC_EC_NEWOBJ_OF(ec, var, T, c, f, s) \
  T *(var) = (T *)(((f) & FL_WB_PROTECTED) ? \
                   rb_ec_wb_protected_newobj_of((ec), (c), (f) & ~FL_WB_PROTECTED, s) : \
                   rb_wb_unprotected_newobj_of((c), (f), s))

/* optimized version of NEWOBJ() */
#define RB_NEWOBJ_OF(var, T, c, f) RB_RVARGC_NEWOBJ_OF(var, T, c, f, RVALUE_SIZE)

#define RB_EC_NEWOBJ_OF(ec, var, T, c, f) RB_RVARGC_EC_NEWOBJ_OF(ec, var, T, c, f, RVALUE_SIZE)

#define NEWOBJ_OF(var, T, c, f) RB_NEWOBJ_OF((var), T, (c), (f))
#define RVARGC_NEWOBJ_OF(var, T, c, f, s) RB_RVARGC_NEWOBJ_OF((var), T, (c), (f), (s))
#define RB_OBJ_GC_FLAGS_MAX 6   /* used in ext/objspace */

#ifndef USE_UNALIGNED_MEMBER_ACCESS
# define UNALIGNED_MEMBER_ACCESS(expr) (expr)
#elif ! USE_UNALIGNED_MEMBER_ACCESS
# define UNALIGNED_MEMBER_ACCESS(expr) (expr)
#elif ! (__has_warning("-Waddress-of-packed-member") || GCC_VERSION_SINCE(9, 0, 0))
# define UNALIGNED_MEMBER_ACCESS(expr) (expr)
#else
# include "internal/warnings.h"
# define UNALIGNED_MEMBER_ACCESS(expr) __extension__({ \
    COMPILER_WARNING_PUSH; \
    COMPILER_WARNING_IGNORED(-Waddress-of-packed-member); \
    __typeof__(expr) unaligned_member_access_result = (expr); \
    COMPILER_WARNING_POP; \
    unaligned_member_access_result; \
})
#endif

#define UNALIGNED_MEMBER_PTR(ptr, mem) UNALIGNED_MEMBER_ACCESS(&(ptr)->mem)
#define RB_OBJ_WRITE(a, slot, b) \
    rb_obj_write((VALUE)(a), UNALIGNED_MEMBER_ACCESS((VALUE *)(slot)), \
                 (VALUE)(b), __FILE__, __LINE__)

// We use SIZE_POOL_COUNT number of shape IDs for transitions out of different size pools
// The next available shapd ID will be the SPECIAL_CONST_SHAPE_ID
#if USE_RVARGC && (SIZEOF_UINT64_T == SIZEOF_VALUE)
# define SIZE_POOL_COUNT 5
#else
# define SIZE_POOL_COUNT 1
#endif

#define RCLASS_EXT_EMBEDDED (SIZE_POOL_COUNT > 1)

typedef struct ractor_newobj_size_pool_cache {
    struct RVALUE *freelist;
    struct heap_page *using_page;
} rb_ractor_newobj_size_pool_cache_t;

typedef struct ractor_newobj_cache {
    size_t incremental_mark_step_allocated_slots;
    rb_ractor_newobj_size_pool_cache_t size_pool_caches[SIZE_POOL_COUNT];
} rb_ractor_newobj_cache_t;

/* gc.c */
extern VALUE *ruby_initial_gc_stress_ptr;
extern int ruby_disable_gc;
RUBY_ATTR_MALLOC void *ruby_mimmalloc(size_t size);
void ruby_mimfree(void *ptr);
void rb_objspace_set_event_hook(const rb_event_flag_t event);
VALUE rb_objspace_gc_enable(struct rb_objspace *);
VALUE rb_objspace_gc_disable(struct rb_objspace *);
void ruby_gc_set_params(void);
void rb_copy_wb_protected_attribute(VALUE dest, VALUE obj);
#if __has_attribute(alloc_align)
__attribute__((__alloc_align__(1)))
#endif
RUBY_ATTR_MALLOC void *rb_aligned_malloc(size_t, size_t) RUBY_ATTR_ALLOC_SIZE((2));
size_t rb_size_mul_or_raise(size_t, size_t, VALUE); /* used in compile.c */
size_t rb_size_mul_add_or_raise(size_t, size_t, size_t, VALUE); /* used in iseq.h */
RUBY_ATTR_MALLOC void *rb_xmalloc_mul_add(size_t, size_t, size_t);
RUBY_ATTR_MALLOC void *rb_xcalloc_mul_add(size_t, size_t, size_t);
void *rb_xrealloc_mul_add(const void *, size_t, size_t, size_t);
RUBY_ATTR_MALLOC void *rb_xmalloc_mul_add_mul(size_t, size_t, size_t, size_t);
RUBY_ATTR_MALLOC void *rb_xcalloc_mul_add_mul(size_t, size_t, size_t, size_t);
static inline void *ruby_sized_xrealloc_inlined(void *ptr, size_t new_size, size_t old_size) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2));
static inline void *ruby_sized_xrealloc2_inlined(void *ptr, size_t new_count, size_t elemsiz, size_t old_count) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2, 3));
static inline void ruby_sized_xfree_inlined(void *ptr, size_t size);
VALUE rb_class_allocate_instance(VALUE klass);
void rb_gc_ractor_newobj_cache_clear(rb_ractor_newobj_cache_t *newobj_cache);
size_t rb_gc_obj_slot_size(VALUE obj);
bool rb_gc_size_allocatable_p(size_t size);
int rb_objspace_garbage_object_p(VALUE obj);

RUBY_SYMBOL_EXPORT_BEGIN
/* gc.c (export) */
const char *rb_objspace_data_type_name(VALUE obj);
VALUE rb_wb_protected_newobj_of(VALUE, VALUE, size_t);
VALUE rb_wb_unprotected_newobj_of(VALUE, VALUE, size_t);
VALUE rb_ec_wb_protected_newobj_of(struct rb_execution_context_struct *ec, VALUE klass, VALUE flags, size_t);
size_t rb_obj_memsize_of(VALUE);
void rb_gc_verify_internal_consistency(void);
size_t rb_obj_gc_flags(VALUE, ID[], size_t);
void rb_gc_mark_values(long n, const VALUE *values);
void rb_gc_mark_vm_stack_values(long n, const VALUE *values);
void *ruby_sized_xrealloc(void *ptr, size_t new_size, size_t old_size) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2));
void *ruby_sized_xrealloc2(void *ptr, size_t new_count, size_t element_size, size_t old_count) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2, 3));
void ruby_sized_xfree(void *x, size_t size);
RUBY_SYMBOL_EXPORT_END

MJIT_SYMBOL_EXPORT_BEGIN
int rb_ec_stack_check(struct rb_execution_context_struct *ec);
void rb_gc_writebarrier_remember(VALUE obj);
const char *rb_obj_info(VALUE obj);
MJIT_SYMBOL_EXPORT_END

#if defined(HAVE_MALLOC_USABLE_SIZE) || defined(HAVE_MALLOC_SIZE) || defined(_WIN32)

static inline void *
ruby_sized_xrealloc_inlined(void *ptr, size_t new_size, size_t old_size)
{
    return ruby_xrealloc(ptr, new_size);
}

static inline void *
ruby_sized_xrealloc2_inlined(void *ptr, size_t new_count, size_t elemsiz, size_t old_count)
{
    return ruby_xrealloc2(ptr, new_count, elemsiz);
}

static inline void
ruby_sized_xfree_inlined(void *ptr, size_t size)
{
    ruby_xfree(ptr);
}

# define SIZED_REALLOC_N(x, y, z, w) REALLOC_N(x, y, z)

#else

static inline void *
ruby_sized_xrealloc_inlined(void *ptr, size_t new_size, size_t old_size)
{
    return ruby_sized_xrealloc(ptr, new_size, old_size);
}

static inline void *
ruby_sized_xrealloc2_inlined(void *ptr, size_t new_count, size_t elemsiz, size_t old_count)
{
    return ruby_sized_xrealloc2(ptr, new_count, elemsiz, old_count);
}

static inline void
ruby_sized_xfree_inlined(void *ptr, size_t size)
{
    ruby_sized_xfree(ptr, size);
}

# define SIZED_REALLOC_N(v, T, m, n) \
    ((v) = (T *)ruby_sized_xrealloc2((void *)(v), (m), sizeof(T), (n)))

#endif /* HAVE_MALLOC_USABLE_SIZE */

#define ruby_sized_xrealloc ruby_sized_xrealloc_inlined
#define ruby_sized_xrealloc2 ruby_sized_xrealloc2_inlined
#define ruby_sized_xfree ruby_sized_xfree_inlined
#endif /* INTERNAL_GC_H */
