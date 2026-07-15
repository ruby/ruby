#ifndef RUBY_SHAPE_H
#define RUBY_SHAPE_H

#include "internal/gc.h"

typedef uint8_t attr_index_t;
typedef uint32_t shape_id_t;
#define SHAPE_ID_NUM_BITS 32
#define SHAPE_ID_OFFSET_NUM_BITS 19

STATIC_ASSERT(shape_id_num_bits, SHAPE_ID_NUM_BITS == sizeof(shape_id_t) * CHAR_BIT);

#define SHAPE_BUFFER_SIZE (1 << SHAPE_ID_OFFSET_NUM_BITS)
#define SHAPE_ID_OFFSET_MASK (SHAPE_BUFFER_SIZE - 1)

#define SHAPE_ID_CAPACITY_BITS 7
#define SHAPE_ID_CAPACITY_MAX ((1U << SHAPE_ID_CAPACITY_BITS) - 1)

#define SHAPE_ID_CAPACITY_OFFSET SHAPE_ID_OFFSET_NUM_BITS
#define SHAPE_ID_FL_USHIFT (SHAPE_ID_OFFSET_NUM_BITS + SHAPE_ID_CAPACITY_BITS)

// shape_id_t bits:
//      0-18 SHAPE_ID_OFFSET_MASK
//              index in rb_shape_tree.shape_list. Allow to access `rb_shape_t *`.
//              This is the part that describe how fields are laid out in memory.
//      19-25 SHAPE_ID_CAPACITY_MASK
//              Embedded field capacity for T_OBJECT objects.
//      26 SHAPE_ID_FL_COMPLEX
//              The object is backed by a `st_table`.
//      27 SHAPE_ID_FL_FROZEN
//              Whether the object is frozen or not.
//      28 SHAPE_ID_FL_HAS_OBJECT_ID
//              Whether the object has an `SHAPE_OBJ_ID` transition.
//      29-30 SHAPE_ID_LAYOUT_MASK
//              The object's physical field layout.

STATIC_ASSERT(robject_rdata_fields_offset, offsetof(struct RObject, as.extended) == offsetof(struct RTypedData, fields_obj));

enum shape_id_fl_type {
#define RBIMPL_SHAPE_ID_FL(n) (1<<(SHAPE_ID_FL_USHIFT+n))

    SHAPE_ID_CAPACITY_MASK = ((1 << SHAPE_ID_CAPACITY_BITS) - 1) << SHAPE_ID_CAPACITY_OFFSET,

    SHAPE_ID_FL_COMPLEX = RBIMPL_SHAPE_ID_FL(0),
    SHAPE_ID_FL_FROZEN = RBIMPL_SHAPE_ID_FL(1),
    SHAPE_ID_FL_HAS_OBJECT_ID = RBIMPL_SHAPE_ID_FL(2),

    // Means IVs are found at an offset from the object's addr, or in a
    // malloc allocated side table
    SHAPE_ID_LAYOUT_ROBJECT = 0,

    // Means this object is a class/module that is NOT RCLASS_BOXABLE, and IV's
    // are found in the fields_obj found on the rclass struct
    SHAPE_ID_LAYOUT_RCLASS = RBIMPL_SHAPE_ID_FL(3),

    // Means this object is an extened RObject or a RTypedData and IVs are found in the
    // fields_obj found on the RObject/RTypedData struct at offset `sizeof(VALUE) * 2`.
    SHAPE_ID_LAYOUT_EXTENDED = RBIMPL_SHAPE_ID_FL(4),
    SHAPE_ID_LAYOUT_RDATA = SHAPE_ID_LAYOUT_EXTENDED,

    // Means this is a complicated object: boxable classes, structs, objects
    // that store IVs on the geniv table
    SHAPE_ID_LAYOUT_OTHER = SHAPE_ID_LAYOUT_RCLASS | SHAPE_ID_LAYOUT_EXTENDED,

    SHAPE_ID_LAYOUT_MASK = SHAPE_ID_LAYOUT_OTHER,

    SHAPE_ID_FL_NON_CANONICAL_MASK = SHAPE_ID_FL_FROZEN | SHAPE_ID_FL_HAS_OBJECT_ID,
    SHAPE_ID_FLAGS_MASK = SHAPE_ID_CAPACITY_MASK | SHAPE_ID_FL_NON_CANONICAL_MASK | SHAPE_ID_FL_COMPLEX | SHAPE_ID_LAYOUT_MASK,

    // These parts of the shape id are specific to the object.
    // Typically, when replicating a shape transition from an object to
    // its IMEMO/fields, these bits should be stripped.
    // All other bits are shared between an IMEMO/fields and its owner.
    SHAPE_ID_FL_PRIVATE_MASK = SHAPE_ID_LAYOUT_MASK|SHAPE_ID_CAPACITY_MASK,
#undef RBIMPL_SHAPE_ID_FL
};

// This mask allows to check if a shape_id contains any ivar.
// It relies on ROOT_SHAPE_WITH_OBJ_ID==1.
enum shape_id_mask {
    SHAPE_ID_HAS_IVAR_MASK = SHAPE_ID_FL_COMPLEX | (SHAPE_ID_OFFSET_MASK - 1),
};

// The interpreter doesn't care about frozen status, embedded capacity, or object id, and
// has its own checks for physical field layout when reading ivars.
// So we normalize shape_id by clearing these bits to improve cache hits.
// JITs however might care about some of it.
#define SHAPE_ID_READ_ONLY_MASK (~(SHAPE_ID_FL_FROZEN | SHAPE_ID_CAPACITY_MASK | SHAPE_ID_FL_HAS_OBJECT_ID | SHAPE_ID_LAYOUT_MASK))
// For write it's the same idea, but here we do care about frozen status.
#define SHAPE_ID_WRITE_MASK (~(SHAPE_ID_CAPACITY_MASK | SHAPE_ID_FL_HAS_OBJECT_ID | SHAPE_ID_LAYOUT_MASK))

typedef uint32_t redblack_id_t;

#define SHAPE_FLAG_SHIFT ((SIZEOF_VALUE * CHAR_BIT) - SHAPE_ID_NUM_BITS)
#define SHAPE_FLAG_MASK (((VALUE)-1) >> SHAPE_ID_NUM_BITS)

#define SHAPE_MAX_VARIATIONS 8

#define INVALID_SHAPE_ID (SHAPE_BUFFER_SIZE - 1)
#define ATTR_INDEX_NOT_SET ((attr_index_t)-1)

#define ROOT_SHAPE_ID                   0x0
#define ROOT_SHAPE_WITH_OBJ_ID          0x1
#define ROOT_COMPLEX_SHAPE_ID       (ROOT_SHAPE_ID | SHAPE_ID_FL_COMPLEX)
#define ROOT_COMPLEX_WITH_OBJ_ID    (ROOT_SHAPE_WITH_OBJ_ID | SHAPE_ID_FL_COMPLEX | SHAPE_ID_FL_HAS_OBJECT_ID)

enum shape_type {
    SHAPE_ROOT,
    SHAPE_IVAR,
    SHAPE_OBJ_ID,
};

struct rb_shape {
    VALUE edges; // id_table from ID (ivar) to next shape
    ID edge_name; // ID (ivar) for transition from parent to rb_shape
    redblack_id_t ancestor_index;
    shape_id_t parent_offset;
    attr_index_t next_field_index; // Fields are either ivars or internal properties like `object_id`
    attr_index_t capacity; // Total capacity of the object with this shape
    enum shape_type type : 8;
};

typedef struct rb_shape rb_shape_t;

enum shape_flags {
    SHAPE_FL_FROZEN             = 1 << 0,
    SHAPE_FL_HAS_OBJECT_ID      = 1 << 1,
    SHAPE_FL_COMPLEX        = 1 << 2,

    SHAPE_FL_NON_CANONICAL_MASK = SHAPE_FL_FROZEN | SHAPE_FL_HAS_OBJECT_ID,
};

typedef struct {
    rb_shape_t *shape_list;
    attr_index_t max_capacity;
    ID id_object_id;
} rb_shape_tree_t;

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_EXTERN rb_shape_tree_t rb_shape_tree;
RUBY_SYMBOL_EXPORT_END

size_t rb_shapes_cache_size(void);
size_t rb_shapes_count(void);

static inline attr_index_t
rb_shape_max_capacity(void)
{
    return rb_shape_tree.max_capacity;
}

static inline shape_id_t
RBASIC_SHAPE_ID(VALUE obj)
{
    RUBY_ASSERT(!RB_SPECIAL_CONST_P(obj));
    RUBY_ASSERT(!RB_TYPE_P(obj, T_IMEMO) || IMEMO_TYPE_P(obj, imemo_fields));
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
RBASIC_SET_FULL_SHAPE_ID_NO_CHECKS(VALUE obj, shape_id_t shape_id)
{
#if RBASIC_SHAPE_ID_FIELD
    RBASIC(obj)->shape_id = (VALUE)shape_id;
#else
    // Object shapes are occupying top bits
    RBASIC(obj)->flags &= SHAPE_FLAG_MASK;
    RBASIC(obj)->flags |= ((VALUE)(shape_id) << SHAPE_FLAG_SHIFT);
#endif
}

static inline shape_id_t
rb_shape_layout(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_LAYOUT_MASK;
}

static inline bool
rb_shape_embedded_p(shape_id_t shape_id)
{
    return rb_shape_layout(shape_id) == SHAPE_ID_LAYOUT_ROBJECT;
}

static inline bool
rb_shape_extended_p(shape_id_t shape_id)
{
    return rb_shape_layout(shape_id) == SHAPE_ID_LAYOUT_EXTENDED;
}

static inline bool
rb_obj_shape_embedded_p(VALUE obj)
{
    return rb_shape_embedded_p(RBASIC_SHAPE_ID(obj));
}

static inline bool
rb_obj_shape_extended_p(VALUE obj)
{
    return rb_shape_extended_p(RBASIC_SHAPE_ID(obj));
}

// Assigns the entire shape_id.
// shape_id_t is composed of two parts:
//  - The layout and capacity part, which never changes except on GC compaction.
//  - All the other bits that regularly change.
// In the overwhelming majority of cases, you want to use RBASIC_SET_SHAPE_ID
// which preserves the object's layout and capacity bits.
// In rare cases you may want to set all bits.
static inline void
RBASIC_SET_FULL_SHAPE_ID(VALUE obj, shape_id_t shape_id)
{
    RUBY_ASSERT(!RB_SPECIAL_CONST_P(obj));
    RUBY_ASSERT(!RB_TYPE_P(obj, T_IMEMO) || IMEMO_TYPE_P(obj, imemo_fields));

    RBASIC_SET_FULL_SHAPE_ID_NO_CHECKS(obj, shape_id);

    RUBY_ASSERT(rb_shape_verify_consistency(obj, shape_id));
}

static inline shape_id_t rb_shape_transition_layout(shape_id_t, shape_id_t);

static inline void
RBASIC_SET_SHAPE_ID_WITH_LAYOUT(VALUE obj, shape_id_t target_shape_id, shape_id_t layout)
{
    RUBY_ASSERT((layout & SHAPE_ID_LAYOUT_MASK) == layout);
    shape_id_t current_shape_id = RBASIC_SHAPE_ID(obj);
    current_shape_id = rb_shape_transition_layout(current_shape_id, layout);
    current_shape_id = (current_shape_id & SHAPE_ID_FL_PRIVATE_MASK) | (target_shape_id & ~SHAPE_ID_FL_PRIVATE_MASK);
    RBASIC_SET_FULL_SHAPE_ID(obj, current_shape_id);
}

static inline void
RBASIC_SET_SHAPE_ID(VALUE obj, shape_id_t shape_id)
{
    RUBY_ASSERT(!RB_SPECIAL_CONST_P(obj));

    RBASIC_SET_FULL_SHAPE_ID(obj, (
        (shape_id & ~SHAPE_ID_FL_PRIVATE_MASK) |
        (RBASIC_SHAPE_ID(obj) & SHAPE_ID_FL_PRIVATE_MASK)
    ));
}

static inline shape_id_t
RSHAPE_FLAGS(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_FLAGS_MASK;
}

static inline shape_id_t
RSHAPE_OFFSET(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_OFFSET_MASK;
}

static inline rb_shape_t *
RSHAPE(shape_id_t shape_id)
{
    shape_id_t offset = RSHAPE_OFFSET(shape_id);
    RUBY_ASSERT(offset != INVALID_SHAPE_ID);
    return &rb_shape_tree.shape_list[offset];
}

int32_t rb_shape_id_offset(void);

RUBY_FUNC_EXPORTED shape_id_t rb_obj_shape_id(VALUE obj);
bool rb_shape_get_iv_index(shape_id_t shape_id, ID id, attr_index_t *value);
bool rb_shape_get_iv_index_with_hint(shape_id_t shape_id, ID id, attr_index_t *value, shape_id_t *shape_id_hint);
bool rb_shape_find_ivar(shape_id_t shape_id, ID id, shape_id_t *ivar_shape);

typedef int rb_shape_foreach_transition_callback(shape_id_t shape_id, void *data);
bool rb_shape_foreach_field(shape_id_t shape_id, rb_shape_foreach_transition_callback func, void *data);

shape_id_t rb_shape_transition_add_ivar_no_warnings(shape_id_t shape_id, ID id, VALUE klass);

shape_id_t rb_shape_object_id(shape_id_t original_shape_id);
shape_id_t rb_shape_rebuild(shape_id_t initial_shape_id, shape_id_t dest_shape_id);
void rb_shape_copy_fields(VALUE dest, VALUE *dest_buf, shape_id_t dest_shape_id, VALUE *src_buf, shape_id_t src_shape_id);

static inline bool
rb_shape_frozen_p(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_FL_FROZEN;
}

static inline bool
rb_shape_complex_p(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_FL_COMPLEX;
}

static inline bool
rb_obj_shape_complex_p(VALUE obj)
{
    return !RB_SPECIAL_CONST_P(obj) && rb_shape_complex_p(RBASIC_SHAPE_ID(obj));
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

static inline attr_index_t
rb_shape_embedded_capacity(shape_id_t shape_id)
{
    return (attr_index_t)((shape_id & SHAPE_ID_CAPACITY_MASK) >> SHAPE_ID_CAPACITY_OFFSET);
}

static inline size_t
rb_shape_slot_size(shape_id_t shape_id)
{
    return sizeof(struct RBasic) + (rb_shape_embedded_capacity(shape_id) * sizeof(VALUE));
}

static inline size_t
rb_obj_shape_slot_size(VALUE obj)
{
    RUBY_ASSERT(!RB_TYPE_P(obj, T_IMEMO) || IMEMO_TYPE_P(obj, imemo_fields));
    return rb_shape_slot_size(RBASIC_SHAPE_ID(obj));
}

static inline attr_index_t
rb_shape_capacity_for_slot_size(size_t slot_size)
{
    size_t capacity = (slot_size - sizeof(struct RBasic)) / sizeof(VALUE);
    RUBY_ASSERT(capacity <= SHAPE_ID_CAPACITY_MAX);
    return (attr_index_t)capacity;
}

static inline shape_id_t
RSHAPE_PARENT_OFFSET(shape_id_t shape_id)
{
    return RSHAPE(shape_id)->parent_offset;
}

static inline bool
RSHAPE_DIRECT_CHILD_P(shape_id_t parent_offset, shape_id_t child_id)
{
    return RSHAPE_PARENT_OFFSET(child_id) == RSHAPE_OFFSET(parent_offset);
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
RSHAPE_CAPACITY(shape_id_t shape_id)
{
    attr_index_t embedded_capacity = rb_shape_embedded_capacity(shape_id);

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
    RUBY_ASSERT(RSHAPE_LEN(shape_id) > 0);
    return RSHAPE_LEN(shape_id) - 1;
}

static inline ID
RSHAPE_EDGE_NAME(shape_id_t shape_id)
{
    return RSHAPE(shape_id)->edge_name;
}

static inline VALUE *
rb_imemo_fields_ptr(VALUE fields_obj)
{
    if (!fields_obj) {
        return NULL;
    }

    RUBY_ASSERT(rb_obj_shape_embedded_p(fields_obj));
    return IMEMO_OBJ_FIELDS(fields_obj)->as.embed.fields;
}

static inline uint32_t
RBASIC_FIELDS_COUNT(VALUE obj)
{
    return RSHAPE(RBASIC_SHAPE_ID(obj))->next_field_index;
}

static inline bool
rb_obj_shape_has_id(VALUE obj)
{
    return rb_shape_has_object_id(RBASIC_SHAPE_ID(obj));
}

static inline bool
rb_shape_has_ivars(shape_id_t shape_id)
{
    return shape_id & SHAPE_ID_HAS_IVAR_MASK;
}

static inline bool
rb_obj_shape_has_ivars(VALUE obj)
{
    return rb_shape_has_ivars(RBASIC_SHAPE_ID(obj));
}

static inline bool
rb_shape_has_fields(shape_id_t shape_id)
{
    return shape_id & (SHAPE_ID_OFFSET_MASK | SHAPE_ID_FL_COMPLEX);
}

static inline bool
rb_obj_shape_has_fields(VALUE obj)
{
    return rb_shape_has_fields(RBASIC_SHAPE_ID(obj));
}

static inline bool
rb_obj_gen_fields_p(VALUE obj)
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
    return rb_obj_shape_has_fields(obj);
}

static inline shape_id_t
rb_shape_transition_layout(shape_id_t shape_id, shape_id_t layout)
{
    return (shape_id & (~SHAPE_ID_LAYOUT_MASK)) | layout;
}

static inline shape_id_t
rb_shape_transition_robject(shape_id_t shape_id)
{
    return rb_shape_transition_layout(shape_id, SHAPE_ID_LAYOUT_ROBJECT);
}

static inline shape_id_t
rb_shape_transition_extended(shape_id_t shape_id)
{
    return rb_shape_transition_layout(shape_id, SHAPE_ID_LAYOUT_EXTENDED);
}

static inline shape_id_t
rb_shape_transition_frozen(shape_id_t shape_id)
{
    return shape_id | SHAPE_ID_FL_FROZEN;
}

static inline shape_id_t
rb_shape_transition_complex(shape_id_t shape_id)
{
    shape_id_t next_shape_id = rb_shape_layout(shape_id) | ROOT_COMPLEX_SHAPE_ID;

    if (rb_shape_has_object_id(shape_id)) {
        next_shape_id = rb_shape_layout(shape_id) | ROOT_COMPLEX_WITH_OBJ_ID;
    }

    next_shape_id |= shape_id & SHAPE_ID_CAPACITY_MASK;

    RUBY_ASSERT(rb_shape_has_object_id(shape_id) == rb_shape_has_object_id(next_shape_id));

    return next_shape_id;
}

static inline shape_id_t
rb_shape_transition_offset(shape_id_t shape_id, shape_id_t offset)
{
    offset = RSHAPE_OFFSET(offset);
    RUBY_ASSERT(RSHAPE_OFFSET(shape_id) == offset || RSHAPE_DIRECT_CHILD_P(shape_id, offset));
    return RSHAPE_FLAGS(shape_id) | offset;
}

static inline shape_id_t
rb_shape_transition_capacity(shape_id_t shape_id, size_t capacity)
{
    RUBY_ASSERT(capacity <= SHAPE_ID_CAPACITY_MAX);

    shape_id_t capacity_flags = (shape_id_t)capacity << SHAPE_ID_CAPACITY_OFFSET;
    return (shape_id & (~SHAPE_ID_CAPACITY_MASK)) | capacity_flags;
}

static inline shape_id_t
rb_shape_transition_slot_size(shape_id_t shape_id, size_t slot_size)
{
    return rb_shape_transition_capacity(shape_id, rb_shape_capacity_for_slot_size(slot_size));
}

shape_id_t rb_shape_transition_object_id(shape_id_t shape_id);

static inline shape_id_t
rb_obj_shape_transition_frozen(VALUE obj)
{
    RUBY_ASSERT(RB_OBJ_FROZEN(obj));
    return rb_shape_transition_frozen(RBASIC_SHAPE_ID(obj));
}

static inline shape_id_t
rb_obj_shape_transition_complex(VALUE obj)
{
    return rb_shape_transition_complex(RBASIC_SHAPE_ID(obj));
}

static inline shape_id_t
rb_obj_shape_transition_capacity(VALUE obj, size_t capacity)
{
    return rb_shape_transition_capacity(RBASIC_SHAPE_ID(obj), capacity);
}

static inline shape_id_t
rb_obj_shape_transition_slot_size(VALUE obj, size_t slot_size)
{
    return rb_shape_transition_slot_size(RBASIC_SHAPE_ID(obj), slot_size);
}

static inline shape_id_t
rb_obj_shape_transition_object_id(VALUE obj)
{
    return rb_shape_transition_object_id(RBASIC_SHAPE_ID(obj));
}

shape_id_t rb_obj_shape_transition_remove_ivar(VALUE obj, ID id, shape_id_t *removed_shape_id);
shape_id_t rb_obj_shape_transition_add_ivar(VALUE obj, ID id);

// For ext/objspace
RUBY_SYMBOL_EXPORT_BEGIN
typedef void each_shape_callback(shape_id_t shape_id, void *data);
void rb_shape_each_shape_id(each_shape_callback callback, void *data);
size_t rb_shape_memsize(shape_id_t shape);
size_t rb_shape_edges_count(shape_id_t shape_id);
size_t rb_shape_depth(shape_id_t shape_id);
RUBY_SYMBOL_EXPORT_END

// Inline cache helpers

typedef struct {
    attr_index_t index;
    shape_id_t shape_offset;
} rb_getivar_cache;

union rb_getivar_cache {
    uint64_t pack;
    rb_getivar_cache unpack;
};
STATIC_ASSERT(rb_getivar_cache_size, sizeof(union rb_getivar_cache) <= sizeof(uint64_t));

#define IVAR_CACHE_INIT ((uint64_t)-1)
#define ATTR_INDEX_T_NUM_BITS (sizeof(attr_index_t) * CHAR_BIT)

static inline rb_getivar_cache
rb_getivar_cache_unpack(uint64_t packed)
{
    union rb_getivar_cache cache = {
        .pack = packed,
    };

    // Because caches may initialized with all bits set (IVAR_CACHE_INIT), and `shape_offset` if 32bits,
    // we need to remove any potential extra bits set in the "padding".
    cache.unpack.shape_offset &= SHAPE_ID_OFFSET_MASK;
    return cache.unpack;
}

static inline uint64_t
rb_getivar_cache_pack(shape_id_t shape_offset, attr_index_t index)
{
    RUBY_ASSERT(shape_offset == RSHAPE_OFFSET(shape_offset));
    RUBY_ASSERT(shape_offset != INVALID_SHAPE_ID);

    union rb_getivar_cache cache = {
        .unpack = {
            .shape_offset = shape_offset,
            .index = index,
        },
    };
    return cache.pack;
}

typedef struct {
    attr_index_t index;
    shape_id_t source_shape_offset;
    shape_id_t dest_shape_offset;
} rb_setivar_cache;

static inline rb_setivar_cache
rb_setivar_cache_unpack(uint64_t packed)
{
    rb_setivar_cache cache = {
        .index = (attr_index_t)packed,
        .source_shape_offset = RSHAPE_OFFSET((shape_id_t)(packed >> ATTR_INDEX_T_NUM_BITS)),
        .dest_shape_offset = RSHAPE_OFFSET((shape_id_t)(packed >> (ATTR_INDEX_T_NUM_BITS + SHAPE_ID_OFFSET_NUM_BITS))),
    };
    return cache;
}

static inline uint64_t
rb_setivar_cache_pack(shape_id_t shape_offset, shape_id_t dest_shape_offset, attr_index_t index)
{
    RUBY_ASSERT(shape_offset == RSHAPE_OFFSET(shape_offset));
    RUBY_ASSERT(dest_shape_offset == RSHAPE_OFFSET(dest_shape_offset));
    RUBY_ASSERT(shape_offset == dest_shape_offset || RSHAPE_DIRECT_CHILD_P(shape_offset, dest_shape_offset));

    uint64_t packed_cache = (uint64_t)dest_shape_offset << (ATTR_INDEX_T_NUM_BITS + SHAPE_ID_OFFSET_NUM_BITS);
    packed_cache |= (uint64_t)shape_offset << ATTR_INDEX_T_NUM_BITS;
    packed_cache |= (uint64_t)index;
    return packed_cache;
}

ALWAYS_INLINE(static shape_id_t rb_setivar_cache_revalidate(shape_id_t shape_id, shape_id_t fields_shape_id, rb_setivar_cache cache));
static shape_id_t
rb_setivar_cache_revalidate(shape_id_t shape_id, shape_id_t fields_shape_id, rb_setivar_cache cache)
{
    RUBY_ASSERT(shape_id != INVALID_SHAPE_ID);
    RUBY_ASSERT(cache.dest_shape_offset == INVALID_SHAPE_ID || cache.dest_shape_offset == RSHAPE_OFFSET(cache.dest_shape_offset));

    shape_id_t normalized_shape_id = shape_id & SHAPE_ID_WRITE_MASK;
    if (UNLIKELY(normalized_shape_id != cache.source_shape_offset)) {
        return INVALID_SHAPE_ID;
    }

    if (UNLIKELY(cache.index >= RSHAPE_CAPACITY(fields_shape_id))) {
        // That's still a hit in term of layout, but the object will need to be resized,
        // so unfortunately we'll have to go through the slow path regardless...
        return INVALID_SHAPE_ID;
    }

    // Cache hit case
    RUBY_ASSERT(cache.source_shape_offset == cache.dest_shape_offset || RSHAPE_DIRECT_CHILD_P(shape_id, cache.dest_shape_offset));
    RUBY_ASSERT(cache.index < RSHAPE_CAPACITY(shape_id));
    RUBY_ASSERT(!rb_shape_frozen_p(shape_id));
    RUBY_ASSERT(!rb_shape_complex_p(shape_id));

    // We use the cached offset, but combined with the current shape flags.
    return rb_shape_transition_offset(shape_id, cache.dest_shape_offset);
}

static inline st_table *
rb_imemo_fields_complex_tbl(VALUE fields_obj)
{
    if (!fields_obj) {
        return NULL;
    }

    RUBY_ASSERT(IMEMO_TYPE_P(fields_obj, imemo_fields));

    // Some codepaths unconditionally access the fields_ptr, and assume it can be used as st_table if the
    // shape is complex.
    RUBY_ASSERT((st_table *)rb_imemo_fields_ptr(fields_obj) == &IMEMO_OBJ_FIELDS(fields_obj)->as.complex.table);

    return &IMEMO_OBJ_FIELDS(fields_obj)->as.complex.table;
}

static inline uint32_t
ROBJECT_FIELDS_CAPACITY(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    // Asking for capacity doesn't make sense when the object is using
    // a hash table for storing instance variables
    RUBY_ASSERT(!rb_obj_shape_complex_p(obj));
    return RSHAPE_CAPACITY(RBASIC_SHAPE_ID(obj));
}

static inline st_table *
ROBJECT_FIELDS_HASH(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    RUBY_ASSERT(rb_obj_shape_complex_p(obj));
    RUBY_ASSERT(rb_obj_shape_extended_p(obj));

    return rb_imemo_fields_complex_tbl(ROBJECT(obj)->as.extended);
}

static inline uint32_t
ROBJECT_FIELDS_COUNT_COMPLEX(VALUE obj)
{
    return (uint32_t)rb_st_table_size(ROBJECT_FIELDS_HASH(obj));
}

static inline uint32_t
ROBJECT_FIELDS_COUNT_NOT_COMPLEX(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    RUBY_ASSERT(!rb_obj_shape_complex_p(obj));
    return RSHAPE(RBASIC_SHAPE_ID(obj))->next_field_index;
}

static inline uint32_t
ROBJECT_FIELDS_COUNT(VALUE obj)
{
    if (rb_obj_shape_complex_p(obj)) {
        return ROBJECT_FIELDS_COUNT_COMPLEX(obj);
    }
    else {
        return ROBJECT_FIELDS_COUNT_NOT_COMPLEX(obj);
    }
}

static inline VALUE
ROBJECT_FIELDS_OBJ(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    return rb_obj_shape_embedded_p(obj) ? obj : ROBJECT(obj)->as.extended;
}

static inline VALUE *
ROBJECT_EMBEDDED_FIELDS(VALUE obj)
{
    return ROBJECT(obj)->as.ary;
}

static inline VALUE *
ROBJECT_FIELDS(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    return ROBJECT_EMBEDDED_FIELDS(ROBJECT_FIELDS_OBJ(obj));
}

#endif
