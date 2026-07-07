#ifndef RUBY_GC_DEFAULT_ZJIT_FASTPATH_H
#define RUBY_GC_DEFAULT_ZJIT_FASTPATH_H

#include <stddef.h>

#include "gc/gc_impl.h"
#include "ruby/internal/static_assert.h"
#include "ruby/ruby.h"

struct rb_gc_zjit_default_new_obj_fastpath {
    size_t cursor_offset;
    size_t jit_cursor_end_offset;
    size_t slot_size;
    VALUE flags;
    VALUE klass;
};

RBIMPL_STATIC_ASSERT(zjit_default_fastpath_fits,
                     sizeof(struct rb_gc_zjit_default_new_obj_fastpath) <= sizeof(union rb_gc_zjit_fastpath_data));

#endif /* RUBY_GC_DEFAULT_ZJIT_FASTPATH_H */
