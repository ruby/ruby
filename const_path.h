#ifndef CONST_PATH_H
#define CONST_PATH_H

#include "internal/compilers.h"
#include "symbol.h"

struct rb_const_path_heap {
    uint32_t size;
    rb_id_serial_t segments[FLEX_ARY_LEN];
};

/**
 * Represent a constant's path, e.g. `Foo::Bar`, `::Foo` or `Foo`.
 */
typedef union {
    const struct rb_const_path_heap *heap;

    // On 32bit:
    // |    31-2   |     1    |    0   |
    // |   first   | absolute | packed |
    //
    // On 64bit:
    // |   63-33   |    32-2   |     1    |    0   |
    // |  second   |   first   | absolute | packed |
    uintptr_t packed;
} rb_const_path_t;

#define PACKED_SHIFT    2
#define PACKED_FLAG     0x1
#define ABSOLUTE_FLAG   0x2

#if SIZEOF_VOIDP == 8
#define PACKED_ID_BITS 31
#else
#define PACKED_ID_BITS 30
#endif

#define PACKED_ID_BITS_MASK (((uintptr_t)1 << PACKED_ID_BITS) - 1)

#define PACKED_ID_STATIC_FLAG 0x1

static inline bool
const_path_packed_p(const rb_const_path_t const_path)
{
    return const_path.packed & PACKED_FLAG;
}

static inline const struct rb_const_path_heap *
const_path_heap(const rb_const_path_t const_path)
{
    rb_const_path_t unpacked_path = const_path;
    unpacked_path.packed &= ~ABSOLUTE_FLAG;
    return unpacked_path.heap;
}

static inline size_t
const_path_memsize_for(size_t size)
{
    return offsetof(struct rb_const_path_heap, segments) + size * sizeof(rb_id_serial_t);
}

static inline size_t
const_path_memsize(const rb_const_path_t const_path)
{
    if (const_path_packed_p(const_path)) {
        return 0;
    }

    const struct rb_const_path_heap *heap = const_path_heap(const_path);
    if (!heap) {
        return 0;
    }

    return const_path_memsize_for(heap->size);
}

static inline void
const_path_free(const rb_const_path_t const_path)
{
    if (!const_path_packed_p(const_path)) {
        ruby_xfree_sized((void *)const_path_heap(const_path), const_path_memsize(const_path));
    }
}

static inline bool
const_path_absolute_p(const rb_const_path_t const_path)
{
    return const_path.packed & ABSOLUTE_FLAG;
}

static inline ID
const_path_unpack_id(uint32_t packed_id)
{
    bool static_p = packed_id & PACKED_ID_STATIC_FLAG;
    packed_id >>= 1;

    ID id = rb_id_from_serial_and_type(packed_id, RUBY_ID_CONST);
    if (static_p) {
        id |= RUBY_ID_STATIC_SYM;
    }
    return id;
}

static inline ID
const_path_aref(const rb_const_path_t const_path, size_t index)
{
    rb_id_serial_t serial;
    if (const_path_packed_p(const_path)) {
        switch (index) {
          case 0:
            serial = ((const_path.packed >> PACKED_SHIFT) & PACKED_ID_BITS_MASK);
            break;
#if SIZEOF_VOIDP == 8
          case 1:
            serial = (const_path.packed >> PACKED_SHIFT >> PACKED_ID_BITS) & PACKED_ID_BITS_MASK;
            break;
#endif
          default:
            return 0;
        }
        if (!serial) {
            return 0;
        }
    }
    else {
        const struct rb_const_path_heap *heap = const_path_heap(const_path);
        if (!heap || index >= heap->size) {
            return 0;
        }
        serial = heap->segments[index];
    }
    return const_path_unpack_id(serial);
}

VALUE rb_const_path_to_array(const rb_const_path_t const_path);
rb_const_path_t rb_const_path_from_array(VALUE arr);

#endif /* CONST_PATH_H */
