#ifndef RUBY_SHAPE_H
#define RUBY_SHAPE_H

#include "internal/gc.h"

typedef uint16_t attr_index_t;
typedef uint32_t shape_id_t;
#define SHAPE_ID_NUM_BITS 32
#define SHAPE_ID_OFFSET_NUM_BITS 19

STATIC_ASSERT(shape_id_num_bits, SHAPE_ID_NUM_BITS == sizeof(shape_id_t) * CHAR_BIT);

#define SHAPE_BUFFER_SIZE (1 << SHAPE_ID_OFFSET_NUM_BITS)
#define SHAPE_ID_OFFSET_MASK (SHAPE_BUFFER_SIZE - 1)
#define SHAPE_ID_FLAGS_MASK (shape_id_t)(((1 << (SHAPE_ID_NUM_BITS - SHAPE_ID_OFFSET_NUM_BITS)) - 1) << SHAPE_ID_OFFSET_NUM_BITS)
#define SHAPE_ID_FL_FROZEN (SHAPE_FL_FROZEN << SHAPE_ID_OFFSET_NUM_BITS)
#define SHAPE_ID_FL_HAS_OBJECT_ID (SHAPE_FL_HAS_OBJECT_ID << SHAPE_ID_OFFSET_NUM_BITS)
#define SHAPE_ID_FL_TOO_COMPLEX (SHAPE_FL_TOO_COMPLEX << SHAPE_ID_OFFSET_NUM_BITS)
#define SHAPE_ID_FL_NON_CANONICAL_MASK (SHAPE_FL_NON_CANONICAL_MASK << SHAPE_ID_OFFSET_NUM_BITS)

#define SHAPE_ID_HEAP_INDEX_BITS 3
#define SHAPE_ID_HEAP_INDEX_OFFSET (SHAPE_ID_NUM_BITS - SHAPE_ID_HEAP_INDEX_BITS)
#define SHAPE_ID_HEAP_INDEX_MAX ((1 << SHAPE_ID_HEAP_INDEX_BITS) - 1)
#define SHAPE_ID_HEAP_INDEX_MASK (SHAPE_ID_HEAP_INDEX_MAX << SHAPE_ID_HEAP_INDEX_OFFSET)

// This masks allows to check if a shape_id contains any ivar.
// It rely on ROOT_SHAPE_WITH_OBJ_ID==1.
#define SHAPE_ID_HAS_IVAR_MASK (SHAPE_ID_FL_TOO_COMPLEX | (SHAPE_ID_OFFSET_MASK - 1))

// The interpreter doesn't care about frozen status or slot size when reading ivars.
// So we normalize shape_id by clearing these bits to improve cache hits.
// JITs however might care about it.
#define SHAPE_ID_READ_ONLY_MASK (~(SHAPE_ID_FL_FROZEN | SHAPE_ID_HEAP_INDEX_MASK))

typedef uint32_t redblack_id_t;

#define SHAPE_MAX_FIELDS (attr_index_t)(-1)
#define SHAPE_FLAG_SHIFT ((SIZEOF_VALUE * CHAR_BIT) - SHAPE_ID_NUM_BITS)
#define SHAPE_FLAG_MASK (((VALUE)-1) >> SHAPE_ID_NUM_BITS)

#define SHAPE_MAX_VARIATIONS 8

#define INVALID_SHAPE_ID ((shape_id_t)-1)
#define ATTR_INDEX_NOT_SET ((attr_index_t)-1)

#define ROOT_SHAPE_ID                   0x0
#define ROOT_SHAPE_WITH_OBJ_ID          0x1
#define ROOT_TOO_COMPLEX_SHAPE_ID       (ROOT_SHAPE_ID | SHAPE_ID_FL_TOO_COMPLEX)
#define ROOT_TOO_COMPLEX_WITH_OBJ_ID    (ROOT_SHAPE_WITH_OBJ_ID | SHAPE_ID_FL_TOO_COMPLEX | SHAPE_ID_FL_HAS_OBJECT_ID)
#define SPECIAL_CONST_SHAPE_ID          (ROOT_SHAPE_ID | SHAPE_ID_FL_FROZEN)

typedef struct redblack_node redblack_node_t;

struct rb_shape {
    VALUE edges; // id_table from ID (ivar) to next shape
    ID edge_name; // ID (ivar) for transition from parent to rb_shape
    redblack_node_t *ancestor_index;
    shape_id_t parent_id;
    attr_index_t next_field_index; // Fields are either ivars or internal properties like `object_id`
    attr_index_t capacity; // Total capacity of the object with this shape
    uint8_t type;
};

typedef struct rb_shape rb_shape_t;

struct redblack_node {
    ID key;
    rb_shape_t *value;
    redblack_id_t l;
    redblack_id_t r;
};

enum shape_type {
    SHAPE_ROOT,
    SHAPE_IVAR,
    SHAPE_OBJ_ID,
};

enum shape_flags {
    SHAPE_FL_FROZEN             = 1 << 0,
    SHAPE_FL_HAS_OBJECT_ID      = 1 << 1,
    SHAPE_FL_TOO_COMPLEX        = 1 << 2,

    SHAPE_FL_NON_CANONICAL_MASK = SHAPE_FL_FROZEN | SHAPE_FL_HAS_OBJECT_ID,
};

typedef struct {
    /* object shapes */
    rb_shape_t *shape_list;
    rb_shape_t *root_shape;
    const attr_index_t *capacities;
    rb_atomic_t next_shape_id;

    redblack_node_t *shape_cache;
    unsigned int cache_size;
} rb_shape_tree_t;

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN rb_shape_tree_t rb_shape_tree;
RUBY_SYMBOL_EXPORT_END

union rb_attr_index_cache {
    uint64_t pack;
    struct {
        shape_id_t shape_id;
        attr_index_t index;
    } unpack;
};

static inline shape_id_t
RBASIC_SHAPE_ID(VALUE obj)
{
    RUBY_ASSERT(!RB_SPECIAL_CONST_P(obj));
    RUBY_ASSERT(!RB_TYPE_P(obj, T_IMEMO) || IMEMO_TYPE_P(obj, imemo_class_fields));
#if RBASIC_SHAPE_ID_FIELD
    return (shape_id_t)((RBASIC(obj)->shape_id));
#else
    return (shape_id_t)((RBASIC(obj)->flags) >> SHAPE_FLAG_SHIFT);
#endif
}

// Same as RBASIC_SHAPE_ID but with flags that have no impact
// on reads removed. e.g. Remove FL_FROZEN.
static inline shape_id_t
RBASIC_SHAPE_ID_FOR_READ(VALUE obj)
{
    return RBASIC_SHAPE_ID(obj) & SHAPE_ID_READ_ONLY_MASK;
}

#if RUBY_DEBUG
bool rb_shape_verify_consistency(VALUE obj, shape_id_t shape_id);
#endif

static inline void
RBASIC_SET_SHAPE_ID(VALUE obj, shape_id_t shape_id)
{
    RUBY_ASSERT(!RB_SPECIAL_CONST_P(obj));
    RUBY_ASSERT(!RB_TYPE_P(obj, T_IMEMO) || IMEMO_TYPE_P(obj, imemo_class_fields));
#if RBASIC_SHAPE_ID_FIELD
    RBASIC(obj)->shape_id = (VALUE)shape_id;
#else
    // Object shapes are occupying top bits
    RBASIC(obj)->flags &= SHAPE_FLAG_MASK;
    RBASIC(obj)->flags |= ((VALUE)(shape_id) << SHAPE_FLAG_SHIFT);
#endif
    RUBY_ASSERT(rb_shape_verify_consistency(obj, shape_id));
}

static inline rb_shape_t *
RSHAPE(shape_id_t shape_id)
{
    uint32_t offset = (shape_id & SHAPE_ID_OFFSET_MASK);
    RUBY_ASSERT(offset != INVALID_SHAPE_ID);

    return &rb_shape_tree.shape_list[offset];
}

int32_t rb_shape_id_offset(void);

RUBY_FUNC_EXPORTED shape_id_t rb_obj_shape_id(VALUE obj);
shape_id_t rb_shape_get_next_iv_shape(shape_id_t shape_id, ID id);
bool rb_shape_get_iv_index(shape_id_t shape_id, ID id, attr_index_t *value);
bool rb_shape_get_iv_index_with_hint(shape_id_t shape_id, ID id, attr_index_t *value, shape_id_t *shape_id_hint);

typedef int rb_shape_foreach_transition_callback(shape_id_t shape_id, void *data);
bool rb_shape_foreach_field(shape_id_t shape_id, rb_shape_foreach_transition_callback func, void *data);

shape_id_t rb_shape_transition_frozen(VALUE obj);
shape_id_t rb_shape_transition_complex(VALUE obj);
shape_id_t rb_shape_transition_remove_ivar(VALUE obj, ID id, shape_id_t *removed_shape_id);
shape_id_t rb_shape_transition_add_ivar(VALUE obj, ID id);
shape_id_t rb_shape_transition_add_ivar_no_warnings(VALUE obj, ID id);
shape_id_t rb_shape_transition_object_id(VALUE obj);
shape_id_t rb_shape_transition_heap(VALUE obj, size_t heap_index);
shape_id_t rb_shape_object_id(shape_id_t original_shape_id);

void rb_shape_free_all(void);

shape_id_t rb_shape_rebuild(shape_id_t initial_shape_id, shape_id_t dest_shape_id);
void rb_shape_copy_fields(VALUE dest, VALUE *dest_buf, shape_id_t dest_shape_id, VALUE src, VALUE *src_buf, shape_id_t src_shape_id);
void rb_shape_copy_complex_ivars(VALUE dest, VALUE obj, shape_id_t src_shape_id, st_table *fields_table);

static inline bool
rb_shape_too_complex_p(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_FL_TOO_COMPLEX;
}

static inline bool
rb_shape_obj_too_complex_p(VALUE obj)
{
    return !RB_SPECIAL_CONST_P(obj) && rb_shape_too_complex_p(RBASIC_SHAPE_ID(obj));
}

static inline bool
rb_shape_has_object_id(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_FL_HAS_OBJECT_ID;
}

static inline bool
rb_shape_canonical_p(shape_id_t shape_id)
{
    return !(shape_id & SHAPE_ID_FL_NON_CANONICAL_MASK);
}

static inline uint8_t
rb_shape_heap_index(shape_id_t shape_id)
{
    return (uint8_t)((shape_id & SHAPE_ID_HEAP_INDEX_MASK) >> SHAPE_ID_HEAP_INDEX_OFFSET);
}

static inline shape_id_t
rb_shape_root(size_t heap_id)
{
    shape_id_t heap_index = (shape_id_t)heap_id;

    return ROOT_SHAPE_ID | ((heap_index + 1) << SHAPE_ID_HEAP_INDEX_OFFSET);
}

static inline shape_id_t
RSHAPE_PARENT(shape_id_t shape_id)
{
    return RSHAPE(shape_id)->parent_id;
}

static inline enum shape_type
RSHAPE_TYPE(shape_id_t shape_id)
{
    return RSHAPE(shape_id)->type;
}

static inline bool
RSHAPE_TYPE_P(shape_id_t shape_id, enum shape_type type)
{
    return RSHAPE_TYPE(shape_id) == type;
}

static inline attr_index_t
RSHAPE_EMBEDDED_CAPACITY(shape_id_t shape_id)
{
    uint8_t heap_index = rb_shape_heap_index(shape_id);
    if (heap_index) {
        return rb_shape_tree.capacities[heap_index - 1];
    }
    return 0;
}

static inline attr_index_t
RSHAPE_CAPACITY(shape_id_t shape_id)
{
    attr_index_t embedded_capacity = RSHAPE_EMBEDDED_CAPACITY(shape_id);

    if (embedded_capacity > RSHAPE(shape_id)->capacity) {
        return embedded_capacity;
    }
    else {
        return RSHAPE(shape_id)->capacity;
    }
}

static inline attr_index_t
RSHAPE_LEN(shape_id_t shape_id)
{
    return RSHAPE(shape_id)->next_field_index;
}

static inline attr_index_t
RSHAPE_INDEX(shape_id_t shape_id)
{
    return RSHAPE_LEN(shape_id) - 1;
}

static inline ID
RSHAPE_EDGE_NAME(shape_id_t shape_id)
{
    return RSHAPE(shape_id)->edge_name;
}

static inline uint32_t
ROBJECT_FIELDS_CAPACITY(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    // Asking for capacity doesn't make sense when the object is using
    // a hash table for storing instance variables
    RUBY_ASSERT(!rb_shape_obj_too_complex_p(obj));
    return RSHAPE_CAPACITY(RBASIC_SHAPE_ID(obj));
}

static inline st_table *
ROBJECT_FIELDS_HASH(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    RUBY_ASSERT(rb_shape_obj_too_complex_p(obj));
    return (st_table *)ROBJECT(obj)->as.heap.fields;
}

static inline void
ROBJECT_SET_FIELDS_HASH(VALUE obj, const st_table *tbl)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    RUBY_ASSERT(rb_shape_obj_too_complex_p(obj));
    ROBJECT(obj)->as.heap.fields = (VALUE *)tbl;
}

static inline uint32_t
ROBJECT_FIELDS_COUNT(VALUE obj)
{
    if (rb_shape_obj_too_complex_p(obj)) {
        return (uint32_t)rb_st_table_size(ROBJECT_FIELDS_HASH(obj));
    }
    else {
        RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
        RUBY_ASSERT(!rb_shape_obj_too_complex_p(obj));
        return RSHAPE(RBASIC_SHAPE_ID(obj))->next_field_index;
    }
}

static inline uint32_t
RBASIC_FIELDS_COUNT(VALUE obj)
{
    return RSHAPE(rb_obj_shape_id(obj))->next_field_index;
}

bool rb_obj_set_shape_id(VALUE obj, shape_id_t shape_id);

static inline bool
rb_shape_obj_has_id(VALUE obj)
{
    return rb_shape_has_object_id(RBASIC_SHAPE_ID(obj));
}

static inline bool
rb_shape_has_ivars(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_HAS_IVAR_MASK;
}

static inline bool
rb_shape_obj_has_ivars(VALUE obj)
{
    return rb_shape_has_ivars(RBASIC_SHAPE_ID(obj));
}

static inline bool
rb_shape_has_fields(shape_id_t shape_id)
{
    return shape_id & (SHAPE_ID_OFFSET_MASK | SHAPE_ID_FL_TOO_COMPLEX);
}

static inline bool
rb_shape_obj_has_fields(VALUE obj)
{
    return rb_shape_has_fields(RBASIC_SHAPE_ID(obj));
}

static inline bool
rb_obj_has_exivar(VALUE obj)
{
    switch (TYPE(obj)) {
        case T_NONE:
        case T_OBJECT:
        case T_CLASS:
        case T_MODULE:
        case T_IMEMO:
          return false;
        default:
          break;
    }
    return rb_shape_obj_has_fields(obj);
}

// For ext/objspace
RUBY_SYMBOL_EXPORT_BEGIN
typedef void each_shape_callback(shape_id_t shape_id, void *data);
void rb_shape_each_shape_id(each_shape_callback callback, void *data);
size_t rb_shape_memsize(shape_id_t shape);
size_t rb_shape_edges_count(shape_id_t shape_id);
size_t rb_shape_depth(shape_id_t shape_id);
RUBY_SYMBOL_EXPORT_END

#endif
