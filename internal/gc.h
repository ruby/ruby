#ifndef INTERNAL_GC_H /* -*- C -*- */
#define INTERNAL_GC_H
/**
 * @file
 * @brief      Internal header for GC.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* gc.c */
extern VALUE *ruby_initial_gc_stress_ptr;
extern int ruby_disable_gc;
void *ruby_mimmalloc(size_t size) RUBY_ATTR_MALLOC;
void ruby_mimfree(void *ptr);
void rb_objspace_set_event_hook(const rb_event_flag_t event);
#if USE_RGENGC
void rb_gc_writebarrier_remember(VALUE obj);
#else
#define rb_gc_writebarrier_remember(obj) 0
#endif
void ruby_gc_set_params(void);
void rb_copy_wb_protected_attribute(VALUE dest, VALUE obj);

#if defined(HAVE_MALLOC_USABLE_SIZE) || defined(HAVE_MALLOC_SIZE) || defined(_WIN32)
#define ruby_sized_xrealloc(ptr, new_size, old_size) ruby_xrealloc(ptr, new_size)
#define ruby_sized_xrealloc2(ptr, new_count, element_size, old_count) ruby_xrealloc2(ptr, new_count, element_size)
#define ruby_sized_xfree(ptr, size) ruby_xfree(ptr)
#define SIZED_REALLOC_N(var,type,n,old_n) REALLOC_N(var, type, n)
#else
RUBY_SYMBOL_EXPORT_BEGIN
void *ruby_sized_xrealloc(void *ptr, size_t new_size, size_t old_size) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2));
void *ruby_sized_xrealloc2(void *ptr, size_t new_count, size_t element_size, size_t old_count) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2, 3));
void ruby_sized_xfree(void *x, size_t size);
RUBY_SYMBOL_EXPORT_END
#define SIZED_REALLOC_N(var,type,n,old_n) ((var)=(type*)ruby_sized_xrealloc2((void*)(var), (n), sizeof(type), (old_n)))
#endif

/* optimized version of NEWOBJ() */
#undef NEWOBJF_OF
#undef RB_NEWOBJ_OF
#define RB_NEWOBJ_OF(obj,type,klass,flags) \
  type *(obj) = (type*)(((flags) & FL_WB_PROTECTED) ? \
                        rb_wb_protected_newobj_of(klass, (flags) & ~FL_WB_PROTECTED) : \
                        rb_wb_unprotected_newobj_of(klass, flags))
#define NEWOBJ_OF(obj,type,klass,flags) RB_NEWOBJ_OF(obj,type,klass,flags)

#if __has_attribute(alloc_align)
__attribute__((__alloc_align__(1)))
#endif
void *rb_aligned_malloc(size_t, size_t) RUBY_ATTR_MALLOC RUBY_ATTR_ALLOC_SIZE((2));

size_t rb_size_mul_or_raise(size_t, size_t, VALUE); /* used in compile.c */
size_t rb_size_mul_add_or_raise(size_t, size_t, size_t, VALUE); /* used in iseq.h */
void *rb_xmalloc_mul_add(size_t, size_t, size_t) RUBY_ATTR_MALLOC;
void *rb_xrealloc_mul_add(const void *, size_t, size_t, size_t);
void *rb_xmalloc_mul_add_mul(size_t, size_t, size_t, size_t) RUBY_ATTR_MALLOC;
void *rb_xcalloc_mul_add_mul(size_t, size_t, size_t, size_t) RUBY_ATTR_MALLOC;

RUBY_SYMBOL_EXPORT_BEGIN
const char *rb_objspace_data_type_name(VALUE obj);

/* gc.c (export) */
VALUE rb_wb_protected_newobj_of(VALUE, VALUE);
VALUE rb_wb_unprotected_newobj_of(VALUE, VALUE);

size_t rb_obj_memsize_of(VALUE);
void rb_gc_verify_internal_consistency(void);

#define RB_OBJ_GC_FLAGS_MAX 6
size_t rb_obj_gc_flags(VALUE, ID[], size_t);
void rb_gc_mark_values(long n, const VALUE *values);
void rb_gc_mark_vm_stack_values(long n, const VALUE *values);
RUBY_SYMBOL_EXPORT_END
#endif /* INTERNAL_GC_H */
