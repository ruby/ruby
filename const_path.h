#ifndef CONST_PATH_H
#define CONST_PATH_H

#include "ruby/ruby.h"
#include "internal/compilers.h"
#include "ruby_atomic.h"
#include "symbol.h"

typedef uint32_t rb_const_path_node_offset_t;

struct rb_const_path_node {
    rb_const_path_node_offset_t parent_offset;
    uint32_t packed_serial;
    // 0, a tagged single child offset, or a `struct rb_id_table *` from segment ID to child offset.
    uintptr_t edges;
};

struct rb_const_path_tree {
    rb_const_path_node_offset_t size;
    rb_const_path_node_offset_t capa;
    struct rb_const_path_node nodes[FLEX_ARY_LEN];
};

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN VALUE rb_const_path_tree;
RUBY_SYMBOL_EXPORT_END

/**
 * Represent a constant's path, e.g. `Foo::Bar`, `::Foo` or `Foo`.
 *
 * Can either be an immediate:
 *
 * On 32bit:
 * |    31-2   |     1    |    0      |
 * |   first   | absolute | immediate |
 *
 * On 64bit:
 * |   63-33   |    32-2   |     1    |    0      |
 * |  second   |   first   | absolute | immediate |
 *
 * Or an offset in the `rb_const_path_tree`.
 *
 * |    31-2   |     1    |    0      |
 * |   offset  | absolute | immediate |
 *
 */

typedef uintptr_t rb_const_path_t;

#define CONST_PATH_SHIFT            2
#define CONST_PATH_IMMEDIATE_FLAG   0x1
#define CONST_PATH_ABSOLUTE_FLAG    0x2

#if SIZEOF_VOIDP == 8
#define PACKED_ID_BITS 31
#else
#define PACKED_ID_BITS 30
#endif

#define PACKED_ID_BITS_MASK (((uintptr_t)1 << PACKED_ID_BITS) - 1)

#define PACKED_ID_STATIC_FLAG 0x1

static inline bool
const_path_immediate_p(const rb_const_path_t const_path)
{
    return const_path & CONST_PATH_IMMEDIATE_FLAG;
}

static inline bool
const_path_absolute_p(const rb_const_path_t const_path)
{
    return const_path & CONST_PATH_ABSOLUTE_FLAG;
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

static inline rb_const_path_node_offset_t
const_path_node_offset(rb_const_path_t const_path)
{
    return (rb_const_path_node_offset_t)(const_path >> CONST_PATH_SHIFT);
}

static inline ID
const_path_aref(const rb_const_path_t const_path, size_t index)
{
    rb_id_serial_t serial;
    if (const_path_immediate_p(const_path)) {
        switch (index) {
          case 0:
            serial = ((const_path >> CONST_PATH_SHIFT) & PACKED_ID_BITS_MASK);
            break;
#if SIZEOF_VOIDP == 8
          case 1:
            serial = (const_path >> CONST_PATH_SHIFT >> PACKED_ID_BITS) & PACKED_ID_BITS_MASK;
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
        rb_const_path_node_offset_t node_offset = const_path_node_offset(const_path);
        VALUE v_tree = RUBY_ATOMIC_VALUE_LOAD(rb_const_path_tree);
        struct rb_const_path_tree *tree = RTYPEDDATA_GET_DATA(v_tree);
        RUBY_ASSERT(node_offset < tree->size);

        // Nodes only link to their parent, so the leaf is the last segment.
        size_t depth = 1;
        struct rb_const_path_node *n = tree->nodes + node_offset;
        while (n->parent_offset) {
            n = tree->nodes + n->parent_offset;
            depth++;
        }

        if (index >= depth) {
            return 0;
        }

        struct rb_const_path_node *node = tree->nodes + node_offset;
        for (size_t i = depth - 1; i > index; i--) {
            node = tree->nodes + node->parent_offset;
        }
        serial = node->packed_serial;
        RB_GC_GUARD(v_tree);
    }
    return const_path_unpack_id(serial);
}

VALUE rb_const_path_to_array(const rb_const_path_t const_path);
rb_const_path_t rb_const_path_from_array(VALUE arr);
void rb_free_const_path_tree(void);
bool rb_obj_is_const_path_tree(VALUE obj);

#endif /* CONST_PATH_H */
