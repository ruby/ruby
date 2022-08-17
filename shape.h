#define USE_SHAPE_CACHE_P (SIZEOF_UINT64_T == SIZEOF_VALUE)

#ifndef shape_id_t
typedef uint16_t shape_id_t;
#define shape_id_t shape_id_t
#endif

#ifndef rb_shape
struct rb_shape {
    VALUE flags; // Shape ID and frozen status encoded within flags
    struct rb_shape * parent; // Pointer to the parent
    struct rb_id_table * edges; // id_table from ID (ivar) to next shape
    ID edge_name; // ID (ivar) for transition from parent to rb_shape
    uint32_t iv_count;
};
#endif

#ifndef rb_shape_t
typedef struct rb_shape rb_shape_t;
#define rb_shape_t rb_shape_t
#endif

# define MAX_SHAPE_ID 0xFFFE
# define NO_CACHE_SHAPE_ID (0x2)
# define INVALID_SHAPE_ID (MAX_SHAPE_ID + 1)
# define ROOT_SHAPE_ID 0x0
# define FROZEN_ROOT_SHAPE_ID 0x1

#define SHAPE_ID(shape) rb_shape_get_shape_id((VALUE)shape)

bool rb_shape_root_shape_p(rb_shape_t* shape);

rb_shape_t* rb_shape_get_shape_by_id_without_assertion(shape_id_t shape_id);

MJIT_SYMBOL_EXPORT_BEGIN
bool rb_shape_no_cache_shape_p(rb_shape_t * shape);
rb_shape_t* rb_shape_get_shape_by_id(shape_id_t shape_id);
void rb_shape_set_shape(VALUE obj, rb_shape_t* shape);
shape_id_t rb_shape_get_shape_id(VALUE obj);
rb_shape_t* rb_shape_get_shape(VALUE obj);
int rb_shape_frozen_shape_p(rb_shape_t* shape);
void rb_shape_transition_shape_frozen(VALUE obj);
void rb_shape_transition_shape(VALUE obj, ID id, rb_shape_t *shape);
rb_shape_t* rb_shape_get_next(rb_shape_t* shape, VALUE obj, ID id);
int rb_shape_get_iv_index(rb_shape_t * shape, ID id, VALUE * value);
MJIT_SYMBOL_EXPORT_END

rb_shape_t * rb_shape_alloc(shape_id_t shape_id, ID edge_name, rb_shape_t * parent);
struct rb_id_table * rb_shape_generate_iv_table(rb_shape_t* shape);

bool rb_shape_set_shape_id(VALUE obj, shape_id_t shape_id);
void rb_shape_set_shape_by_id(shape_id_t, rb_shape_t *);

VALUE rb_obj_debug_shape(VALUE self, VALUE obj);
