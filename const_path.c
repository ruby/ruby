#include "const_path.h"

rb_const_path_t
rb_const_path_from_array(VALUE arr)
{
    RUBY_ASSERT(RB_TYPE_P(arr, T_ARRAY));
    rb_len_t array_size = RARRAY_LEN(arr);
    RUBY_ASSERT(array_size >= 1);

    size_t size = array_size;

    rb_len_t i = 0;
    bool absolute = RARRAY_AREF(arr, i) == ID2SYM(idNULL);
    if (absolute) {
        size--;
        i++;
    }

    RUBY_ASSERT(size >= 1);
    RUBY_ASSERT(size < UINT32_MAX);

#if SIZEOF_VOIDP == 8
    if (size == 1) {
        VALUE sym = RARRAY_AREF(arr, i);
        return const_path_packed(SYM2ID(sym), absolute);
    }
#endif

    struct rb_const_path_heap *heap = (struct rb_const_path_heap *)ruby_xmalloc(const_path_memsize_for(size));
    heap->size = 0;

    for (; i < array_size; i++) {
        VALUE sym = RARRAY_AREF(arr, i);
        ID id = SYM2ID(sym);
        heap->segments[heap->size] = const_path_pack_id(id);
        heap->size++;
    }

    rb_const_path_t const_path = {
        .heap = heap
    };

    RUBY_ASSERT((const_path.packed & (ABSOLUTE_FLAG | PACKED_FLAG)) == 0);
    if (absolute) {
        const_path.packed |= ABSOLUTE_FLAG;
    }

    return const_path;
}

VALUE
rb_const_path_to_array(const rb_const_path_t const_path)
{
    VALUE arr;

    if (const_path_absolute_p(const_path)) {
        arr = rb_ary_new_capa(const_path_size(const_path) + 1);
        rb_ary_push(arr, ID2SYM(idNULL));
    }
    else {
        arr = rb_ary_new_capa(const_path_size(const_path));
    }

    for (size_t i = 0; i < const_path_size(const_path); i++) {
        rb_ary_push(arr, ID2SYM(const_path_aref(const_path, i)));
    }

    return arr;
}
