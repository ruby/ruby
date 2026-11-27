#include "const_path.h"

#if SIZEOF_VOIDP == 8
// On 64 bits, we only need the top two bits to be 0.
#define PACKABLE_SERIAL_MASK (((uint32_t)0x3) << 30)
#else
// On 32 bits, we need the top tree bits to be 0.
#define PACKABLE_SERIAL_MASK (((uint32_t)0x7) << 29)
#endif

static inline uint32_t
const_path_pack_id(ID id)
{
    RUBY_ASSERT(is_notop_id(id));
    RUBY_ASSERT(id_type(id) == RUBY_ID_CONST);
    uint32_t packed_id = rb_id_to_serial(id) << 1;
    return DYNAMIC_ID_P(id) ? packed_id : packed_id | PACKED_ID_STATIC_FLAG;
}

static inline bool
packable_id_p(ID id)
{
    return (const_path_pack_id(id) & PACKABLE_SERIAL_MASK) == 0;
}

static size_t
const_path_size(const rb_const_path_t const_path)
{
    if (const_path_packed_p(const_path)) {
#if SIZEOF_VOIDP == 8
        if ((const_path.packed >> 33)) {
            return 2;
        }
#endif
        return 1;
    }
    else {
        const struct rb_const_path_heap *heap = const_path_heap(const_path);
        if (!heap) {
            return 0;
        }
        return heap->size;
    }
}

static inline rb_const_path_t
const_path_packed1(bool absolute, ID id)
{
    uintptr_t num = (uintptr_t)const_path_pack_id(id);

    rb_const_path_t const_path = {
        .packed = (num << PACKED_SHIFT) | PACKED_FLAG
    };
    if (absolute) {
        const_path.packed |= ABSOLUTE_FLAG;
    }
    return const_path;
}

#if SIZEOF_VOIDP == 8
static inline rb_const_path_t
const_path_packed2(bool absolute, ID first_id, ID second_id)
{
    uintptr_t num = (uintptr_t)const_path_pack_id(first_id);
    num |= ((uintptr_t)const_path_pack_id(second_id)) << PACKED_ID_BITS;

    rb_const_path_t const_path = {
        .packed = (num << PACKED_SHIFT) | PACKED_FLAG
    };
    if (absolute) {
        const_path.packed |= ABSOLUTE_FLAG;
    }
    return const_path;
}
#endif

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

    if (size == 1) {
        VALUE sym = RARRAY_AREF(arr, i);
        ID id = SYM2ID(sym);
        if (packable_id_p(id)) {
            return const_path_packed1(absolute, id);
        }
    }

#if SIZEOF_VOIDP == 8
    if (size == 2) {
        VALUE first_sym = RARRAY_AREF(arr, i);
        VALUE second_sym = RARRAY_AREF(arr, i + 1);
        ID first_id = SYM2ID(first_sym);
        ID second_id = SYM2ID(second_sym);

        if (packable_id_p(first_id) && packable_id_p(second_id)) {
            return const_path_packed2(absolute, first_id, second_id);
        }
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
