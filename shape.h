#ifndef RUBY_SHAPE_H
#define RUBY_SHAPE_H
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

#if RUBY_DEBUG || (defined(VM_CHECK_MODE) && VM_CHECK_MODE > 0)
#  if SIZEOF_SHAPE_T == 4
typedef uint32_t shape_id_t;
# define SHAPE_BITS 16
#  else
typedef uint16_t shape_id_t;
# define SHAPE_BITS 16
#  endif
#else
#  if SIZEOF_SHAPE_T == 4
typedef uint32_t shape_id_t;
# define SHAPE_BITS 32
#  else
typedef uint16_t shape_id_t;
# define SHAPE_BITS 16
#  endif
#endif

# define SHAPE_MASK (((uintptr_t)1 << SHAPE_BITS) - 1)
# define SHAPE_FLAG_MASK (((VALUE)-1) >> SHAPE_BITS)

# define SHAPE_FLAG_SHIFT ((SIZEOF_VALUE * 8) - SHAPE_BITS)

# define SHAPE_BITMAP_SIZE 16384

# define MAX_SHAPE_ID (SHAPE_MASK - 1)
# define INVALID_SHAPE_ID SHAPE_MASK
# define ROOT_SHAPE_ID 0x0
# define FROZEN_ROOT_SHAPE_ID 0x1

struct rb_shape {
    struct rb_id_table * edges; // id_table from ID (ivar) to next shape
    ID edge_name; // ID (ivar) for transition from parent to rb_shape
    attr_index_t iv_count;
    uint8_t type;
    shape_id_t parent_id;
};

typedef struct rb_shape rb_shape_t;

enum shape_type {
    SHAPE_ROOT,
    SHAPE_IVAR,
    SHAPE_FROZEN,
    SHAPE_IVAR_UNDEF,
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
#endif

bool rb_shape_root_shape_p(rb_shape_t* shape);

rb_shape_t* rb_shape_get_shape_by_id_without_assertion(shape_id_t shape_id);

MJIT_SYMBOL_EXPORT_BEGIN
rb_shape_t* rb_shape_get_shape_by_id(shape_id_t shape_id);
void rb_shape_set_shape(VALUE obj, rb_shape_t* shape);
shape_id_t rb_shape_get_shape_id(VALUE obj);
rb_shape_t* rb_shape_get_shape(VALUE obj);
int rb_shape_frozen_shape_p(rb_shape_t* shape);
void rb_shape_transition_shape_frozen(VALUE obj);
void rb_shape_transition_shape_remove_ivar(VALUE obj, ID id, rb_shape_t *shape);
void rb_shape_transition_shape(VALUE obj, ID id, rb_shape_t *shape);
rb_shape_t* rb_shape_get_next(rb_shape_t* shape, VALUE obj, ID id);
bool rb_shape_get_iv_index(rb_shape_t * shape, ID id, attr_index_t * value);
shape_id_t rb_shape_id(rb_shape_t * shape);
MJIT_SYMBOL_EXPORT_END

static inline uint32_t
ROBJECT_IV_COUNT(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);
    uint32_t ivc = rb_shape_get_shape_by_id(ROBJECT_SHAPE_ID(obj))->iv_count;
    RUBY_ASSERT(ivc <= ROBJECT_NUMIV(obj));
    return ivc;
}

rb_shape_t * rb_shape_alloc(ID edge_name, rb_shape_t * parent);
rb_shape_t * rb_shape_alloc_with_parent_id(ID edge_name, shape_id_t parent_id);

bool rb_shape_set_shape_id(VALUE obj, shape_id_t shape_id);

VALUE rb_obj_debug_shape(VALUE self, VALUE obj);
VALUE rb_shape_flags_mask(void);

#endif
