#ifndef RUBY_GC_MMTK_ZJIT_FASTPATH_H
#define RUBY_GC_MMTK_ZJIT_FASTPATH_H

#include <stddef.h>
#include <stdint.h>

#include "gc/gc_impl.h"
#include "ruby/internal/static_assert.h"
#include "ruby/ruby.h"

struct rb_gc_zjit_mmtk_new_obj_fastpath {
    const void *objspace;
    size_t objspace_total_allocated_objects_offset;
    size_t ractor_cache_mutator_offset;
    size_t ractor_cache_bump_pointer_offset;
    size_t ractor_cache_obj_free_parallel_buf_offset;
    size_t ractor_cache_obj_free_parallel_count_offset;
    size_t bump_pointer_cursor_offset;
    size_t bump_pointer_limit_offset;
    size_t min_obj_align;
    size_t payload_size;
    size_t total_alloc_size;
    uint32_t allocation_semantics_default;
    uintptr_t gc_stress_p_func;
    uintptr_t newobj_tracing_p_func;
    uintptr_t post_alloc_func;
    size_t obj_free_buf_capacity_minus_one;
    size_t value_size_shift;
    VALUE flags;
    VALUE klass;
};

RBIMPL_STATIC_ASSERT(zjit_mmtk_fastpath_fits,
                     sizeof(struct rb_gc_zjit_mmtk_new_obj_fastpath) <= sizeof(union rb_gc_zjit_fastpath_data));

#endif /* RUBY_GC_MMTK_ZJIT_FASTPATH_H */
