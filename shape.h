#ifndef RUBY_SHAPE_H
#define RUBY_SHAPE_H

#include "internal/gc.h"

#if (SIZEOF_UINT64_T == SIZEOF_VALUE)
#define SIZEOF_SHAPE_T 4
#define SHAPE_IN_BASIC_FLAGS 1
typedef uint32_t attr_index_t;
#else
#define SIZEOF_SHAPE_T 2
#define SHAPE_IN_BASIC_FLAGS 0
typedef uint16_t attr_index_t;
#endif

#define MAX_IVARS (attr_index_t)(-1)

#if SIZEOF_SHAPE_T == 4
typedef uint32_t shape_id_t;
# define SHAPE_ID_NUM_BITS 32
#else
typedef uint16_t shape_id_t;
# define SHAPE_ID_NUM_BITS 16
#endif

# define SHAPE_MASK (((uintptr_t)1 << SHAPE_ID_NUM_BITS) - 1)
# define SHAPE_FLAG_MASK (((VALUE)-1) >> SHAPE_ID_NUM_BITS)

# define SHAPE_FLAG_SHIFT ((SIZEOF_VALUE * 8) - SHAPE_ID_NUM_BITS)

# define SHAPE_BITMAP_SIZE 16384

# define SHAPE_MAX_VARIATIONS 8

# define MAX_SHAPE_ID (SHAPE_MASK - 1)
# define INVALID_SHAPE_ID SHAPE_MASK
# define ROOT_SHAPE_ID 0x0

# define SPECIAL_CONST_SHAPE_ID (SIZE_POOL_COUNT * 2)
# define OBJ_TOO_COMPLEX_SHAPE_ID (SPECIAL_CONST_SHAPE_ID + 1)

struct rb_shape {
    struct rb_id_table * edges; // id_table from ID (ivar) to next shape
    ID edge_name; // ID (ivar) for transition from parent to rb_shape
    attr_index_t next_iv_index;
    uint32_t capacity; // Total capacity of the object with this shape
    uint8_t type;
    uint8_t size_pool_index;
    shape_id_t parent_id;
};

typedef struct rb_shape rb_shape_t;

enum shape_type {
    SHAPE_ROOT,
    SHAPE_IVAR,
    SHAPE_FROZEN,
    SHAPE_CAPACITY_CHANGE,
    SHAPE_INITIAL_CAPACITY,
    SHAPE_T_OBJECT,
    SHAPE_OBJ_TOO_COMPLEX,
};

#if SHAPE_IN_BASIC_FLAGS
static inline shape_id_t
RBASIC_SHAPE_ID(VALUE obj)
{
    RUBY_ASSERT(!RB_SPECIAL_CONST_P(obj));
    return (shape_id_t)(SHAPE_MASK & ((RBASIC(obj)->flags) >> SHAPE_FLAG_SHIFT));
}

static inline void
RBASIC_SET_SHAPE_ID(VALUE obj, shape_id_t shape_id)
{
    // Ractors are occupying the upper 32 bits of flags, but only in debug mode
    // Object shapes are occupying top bits
    RBASIC(obj)->flags &= SHAPE_FLAG_MASK;
    RBASIC(obj)->flags |= ((VALUE)(shape_id) << SHAPE_FLAG_SHIFT);
}

static inline shape_id_t
ROBJECT_SHAPE_ID(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    return RBASIC_SHAPE_ID(obj);
}

static inline void
ROBJECT_SET_SHAPE_ID(VALUE obj, shape_id_t shape_id)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    RBASIC_SET_SHAPE_ID(obj, shape_id);
}

static inline shape_id_t
RCLASS_SHAPE_ID(VALUE obj)
{
    RUBY_ASSERT(RB_TYPE_P(obj, T_CLASS) || RB_TYPE_P(obj, T_MODULE));
    return RBASIC_SHAPE_ID(obj);
}

#else

static inline shape_id_t
ROBJECT_SHAPE_ID(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    return (shape_id_t)(SHAPE_MASK & (RBASIC(obj)->flags >> SHAPE_FLAG_SHIFT));
}

static inline void
ROBJECT_SET_SHAPE_ID(VALUE obj, shape_id_t shape_id)
{
    RBASIC(obj)->flags &= SHAPE_FLAG_MASK;
    RBASIC(obj)->flags |= ((VALUE)(shape_id) << SHAPE_FLAG_SHIFT);
}

MJIT_SYMBOL_EXPORT_BEGIN
shape_id_t rb_rclass_shape_id(VALUE obj);
MJIT_SYMBOL_EXPORT_END

static inline shape_id_t RCLASS_SHAPE_ID(VALUE obj)
{
    return rb_rclass_shape_id(obj);
}

#endif

bool rb_shape_root_shape_p(rb_shape_t* shape);
rb_shape_t * rb_shape_get_root_shape(void);
uint8_t rb_shape_id_num_bits(void);
int32_t rb_shape_id_offset(void);

rb_shape_t* rb_shape_get_shape_by_id_without_assertion(shape_id_t shape_id);
rb_shape_t * rb_shape_get_parent(rb_shape_t * shape);

MJIT_SYMBOL_EXPORT_BEGIN
rb_shape_t* rb_shape_get_shape_by_id(shape_id_t shape_id);
shape_id_t rb_shape_get_shape_id(VALUE obj);
rb_shape_t * rb_shape_get_next_iv_shape(rb_shape_t * shape, ID id);
bool rb_shape_get_iv_index(rb_shape_t * shape, ID id, attr_index_t * value);
bool rb_shape_obj_too_complex(VALUE obj);
MJIT_SYMBOL_EXPORT_END

void rb_shape_set_shape(VALUE obj, rb_shape_t* shape);
rb_shape_t* rb_shape_get_shape(VALUE obj);
int rb_shape_frozen_shape_p(rb_shape_t* shape);
void rb_shape_transition_shape_frozen(VALUE obj);
void rb_shape_transition_shape_remove_ivar(VALUE obj, ID id, rb_shape_t *shape, VALUE * removed);
rb_shape_t * rb_shape_transition_shape_capa(rb_shape_t * shape, uint32_t new_capacity);
rb_shape_t* rb_shape_get_next(rb_shape_t* shape, VALUE obj, ID id);

rb_shape_t * rb_shape_rebuild_shape(rb_shape_t * initial_shape, rb_shape_t * dest_shape);

static inline uint32_t
ROBJECT_IV_CAPACITY(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    // Asking for capacity doesn't make sense when the object is using
    // a hash table for storing instance variables
    RUBY_ASSERT(ROBJECT_SHAPE_ID(obj) != OBJ_TOO_COMPLEX_SHAPE_ID);
    return rb_shape_get_shape_by_id(ROBJECT_SHAPE_ID(obj))->capacity;
}

static inline st_table *
ROBJECT_IV_HASH(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    RUBY_ASSERT(ROBJECT_SHAPE_ID(obj) == OBJ_TOO_COMPLEX_SHAPE_ID);
    return (st_table *)ROBJECT(obj)->as.heap.ivptr;
}

static inline void
ROBJECT_SET_IV_HASH(VALUE obj, const struct rb_id_table *tbl)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    RUBY_ASSERT(ROBJECT_SHAPE_ID(obj) == OBJ_TOO_COMPLEX_SHAPE_ID);
    ROBJECT(obj)->as.heap.ivptr = (VALUE *)tbl;
}

size_t rb_id_table_size(const struct rb_id_table *tbl);

static inline uint32_t
ROBJECT_IV_COUNT(VALUE obj)
{
    if (ROBJECT_SHAPE_ID(obj) == OBJ_TOO_COMPLEX_SHAPE_ID) {
        return (uint32_t)rb_st_table_size(ROBJECT_IV_HASH(obj));
    }
    else {
        RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
        RUBY_ASSERT(ROBJECT_SHAPE_ID(obj) != OBJ_TOO_COMPLEX_SHAPE_ID);
        return rb_shape_get_shape_by_id(ROBJECT_SHAPE_ID(obj))->next_iv_index;
    }
}

static inline uint32_t
RBASIC_IV_COUNT(VALUE obj)
{
    return rb_shape_get_shape_by_id(rb_shape_get_shape_id(obj))->next_iv_index;
}

static inline uint32_t
RCLASS_IV_COUNT(VALUE obj)
{
    RUBY_ASSERT(RB_TYPE_P(obj, RUBY_T_CLASS) || RB_TYPE_P(obj, RUBY_T_MODULE));
    uint32_t ivc = rb_shape_get_shape_by_id(RCLASS_SHAPE_ID(obj))->next_iv_index;
    return ivc;
}

rb_shape_t * rb_shape_alloc(ID edge_name, rb_shape_t * parent);
rb_shape_t * rb_shape_alloc_with_size_pool_index(ID edge_name, rb_shape_t * parent, uint8_t size_pool_index);
rb_shape_t * rb_shape_alloc_with_parent_id(ID edge_name, shape_id_t parent_id);

rb_shape_t *rb_shape_traverse_from_new_root(rb_shape_t *initial_shape, rb_shape_t *orig_shape);

bool rb_shape_set_shape_id(VALUE obj, shape_id_t shape_id);

VALUE rb_obj_debug_shape(VALUE self, VALUE obj);
VALUE rb_shape_flags_mask(void);
void rb_shape_set_too_complex(VALUE obj);

// For ext/objspace
RUBY_SYMBOL_EXPORT_BEGIN
typedef void each_shape_callback(rb_shape_t * shape, void *data);
void rb_shape_each_shape(each_shape_callback callback, void *data);
size_t rb_shape_memsize(rb_shape_t *shape);
size_t rb_shape_edges_count(rb_shape_t *shape);
size_t rb_shape_depth(rb_shape_t *shape);
shape_id_t rb_shape_id(rb_shape_t * shape);
RUBY_SYMBOL_EXPORT_END

#endif
