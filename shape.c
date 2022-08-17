#include "vm_core.h"
#include "vm_sync.h"
#include "shape.h"
#include "internal/class.h"
#include "internal/symbol.h"

/*
 * Getters for root_shape, frozen_root_shape and no_cache_shape
 */
static rb_shape_t*
rb_shape_get_root_shape(void) {
    rb_vm_t *vm = GET_VM();
    return vm->root_shape;
}

static rb_shape_t*
rb_shape_get_frozen_root_shape(void) {
    rb_vm_t *vm = GET_VM();
    return vm->frozen_root_shape;
}

static rb_shape_t*
rb_shape_get_no_cache_shape(void) {
    rb_vm_t *vm = GET_VM();
    return vm->no_cache_shape;
}

/*
 * Predicate methods for root_shape and no_cache_shape
 */
bool
rb_shape_root_shape_p(rb_shape_t* shape) {
    return shape == rb_shape_get_root_shape();
}

bool
rb_shape_no_cache_shape_p(rb_shape_t * shape)
{
    return shape == rb_shape_get_no_cache_shape();
}

/*
 * Shape getters
 */
rb_shape_t*
rb_shape_get_shape_by_id(shape_id_t shape_id)
{
    RUBY_ASSERT(shape_id != INVALID_SHAPE_ID);

    rb_vm_t *vm = GET_VM();
    rb_shape_t *shape = vm->shape_list[shape_id];
    RUBY_ASSERT(IMEMO_TYPE_P(shape, imemo_shape));
    return shape;
}

rb_shape_t*
rb_shape_get_shape_by_id_without_assertion(shape_id_t shape_id)
{
    RUBY_ASSERT(shape_id != INVALID_SHAPE_ID);

    rb_vm_t *vm = GET_VM();
    rb_shape_t *shape = vm->shape_list[shape_id];
    return shape;
}

static inline shape_id_t
shape_get_shape_id(rb_shape_t *shape) {
    return (shape_id_t)(0xffff & (shape->flags >> 16));
}

static inline shape_id_t
RCLASS_SHAPE_ID(VALUE obj)
{
    return RCLASS_EXT(obj)->shape_id;
}

shape_id_t
rb_shape_get_shape_id(VALUE obj)
{
    shape_id_t shape_id = ROOT_SHAPE_ID;

    if (RB_SPECIAL_CONST_P(obj)) {
        return SHAPE_ID(rb_shape_get_frozen_root_shape());
    }

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
          return ROBJECT_SHAPE_ID(obj);
          break;
      case T_CLASS:
      case T_MODULE:
          return RCLASS_SHAPE_ID(obj);
      case T_IMEMO:
          if (imemo_type(obj) == imemo_shape) {
              return shape_get_shape_id((rb_shape_t *)obj);
              break;
          }
      default:
          return rb_generic_shape_id(obj);
    }

    RUBY_ASSERT(shape_id < MAX_SHAPE_ID);
    return shape_id;
}

rb_shape_t*
rb_shape_get_shape(VALUE obj)
{
    return rb_shape_get_shape_by_id(rb_shape_get_shape_id(obj));
}

enum transition_type {
    SHAPE_IVAR,
    SHAPE_FROZEN,
};

static shape_id_t
get_next_shape_id(void)
{
    rb_vm_t *vm = GET_VM();
    int next_shape_id = 0;

    /*
     * Speedup for getting next shape_id by using bitmaps
     * TODO: Can further optimize here by nesting more bitmaps
     */
    for (int i = 0; i < 2048; i++) {
        uint32_t cur_bitmap = vm->shape_bitmaps[i];
        if (~cur_bitmap) {
            uint32_t copied_curbitmap = ~cur_bitmap;

            uint32_t count = 0;
            while (!(copied_curbitmap & 0x1)) {
                copied_curbitmap >>= 1;
                count++;
            }
            next_shape_id = i * 32 + count;
            break;
        }
    }

    if (next_shape_id > vm->max_shape_count) {
        vm->max_shape_count = next_shape_id;
    }

    return next_shape_id;
}

static bool
rb_shape_lookup_id(rb_shape_t* shape, ID id) {
    while (shape->parent) {
        if (shape->edge_name == id) {
            return true;
        }
        shape = shape->parent;
    }
    return false;
}

static rb_shape_t*
get_next_shape_internal(rb_shape_t* shape, ID id, VALUE obj, enum transition_type tt)
{
    rb_shape_t *res = NULL;
    RB_VM_LOCK_ENTER();
    {
        // no_cache_shape should only transition to other no_cache_shapes
        if(shape == rb_shape_get_no_cache_shape()) return shape;

        if (rb_shape_lookup_id(shape, id)) {
            // If shape already contains the ivar that is being set, we'll return shape
            res = shape;
        }
        else {
            if (!shape->edges) {
                shape->edges = rb_id_table_create(0);
            }

            // Lookup the shape in edges - if there's already an edge and a corresponding shape for it,
            // we can return that. Otherwise, we'll need to get a new shape
            if (!rb_id_table_lookup(shape->edges, id, (VALUE *)&res) || rb_objspace_garbage_object_p((VALUE)res)) {
                // In this case, the shape exists, but the shape is garbage, so we need to recreate it
                if (res) {
                    rb_id_table_delete(shape->edges, id);
                    res->parent = NULL;
                }

                shape_id_t next_shape_id = get_next_shape_id();

                if (next_shape_id == MAX_SHAPE_ID) {
                    res = rb_shape_get_no_cache_shape();
                }
                else {
                    RUBY_ASSERT(next_shape_id < MAX_SHAPE_ID);
                    rb_shape_t * new_shape = rb_shape_alloc(next_shape_id,
                            id,
                            shape);

                    // Check if we should update max_iv_count on the object's class
                    if (BUILTIN_TYPE(obj) == T_OBJECT) {
                        VALUE klass = rb_obj_class(obj);
                        uint32_t cur_iv_count = RCLASS_EXT(klass)->max_iv_count;
                        uint32_t new_iv_count = new_shape->iv_count;
                        if (new_iv_count > cur_iv_count) {
                            RCLASS_EXT(klass)->max_iv_count = new_iv_count;
                        }
                    }

                    rb_id_table_insert(shape->edges, id, (VALUE)new_shape);
                    RB_OBJ_WRITTEN((VALUE)new_shape, Qundef, (VALUE)shape);

                    rb_shape_set_shape_by_id(next_shape_id, new_shape);

                    if (tt == SHAPE_FROZEN) {
                        new_shape->iv_count--;
                        RB_OBJ_FREEZE_RAW((VALUE)new_shape);
                    }

                    res = new_shape;
                }
            }
        }
    }
    RB_VM_LOCK_LEAVE();
    return res;
}

MJIT_FUNC_EXPORTED int
rb_shape_frozen_shape_p(rb_shape_t* shape)
{
    return RB_OBJ_FROZEN((VALUE)shape);
}

void
rb_shape_transition_shape_frozen(VALUE obj)
{
    rb_shape_t* shape = rb_shape_get_shape(obj);
    RUBY_ASSERT(shape);

    if (rb_shape_frozen_shape_p(shape)) {
        return;
    }

    rb_shape_t* next_shape;

    if (shape == rb_shape_get_root_shape()) {
        switch(BUILTIN_TYPE(obj)) {
            case T_OBJECT:
            case T_CLASS:
            case T_MODULE:
                break;
            default:
                return;
        }
        next_shape = rb_shape_get_frozen_root_shape();
    }
    else {
        static ID id_frozen;
        if (!id_frozen) {
            id_frozen = rb_make_internal_id();
        }

        next_shape = get_next_shape_internal(shape, (ID)id_frozen, obj, SHAPE_FROZEN);
    }

    RUBY_ASSERT(next_shape);
    rb_shape_set_shape(obj, next_shape);
}

void
rb_shape_transition_shape(VALUE obj, ID id, rb_shape_t *shape)
{
    rb_shape_t* next_shape = rb_shape_get_next(shape, obj, id);
    if (shape == next_shape) {
        return;
    }

    if (BUILTIN_TYPE(obj) == T_OBJECT && next_shape == rb_shape_get_no_cache_shape()) {
        // If the object is embedded, we need to make it extended so that
        // the instance variable index table can be stored on the object.
        // The "no cache shape" is a singleton and is allowed to be shared
        // among objects, so it cannot store instance variable index information.
        // Therefore we need to store the iv index table on the object itself.
        // Embedded objects don't have the room for an iv index table, so
        // we'll force it to be extended
        uint32_t num_iv = ROBJECT_NUMIV(obj);
        // Make the object extended
        rb_ensure_iv_list_size(obj, num_iv, num_iv + 1);
        RUBY_ASSERT(!(RBASIC(obj)->flags & ROBJECT_EMBED));
        ROBJECT(obj)->as.heap.iv_index_tbl = rb_shape_generate_iv_table(shape);
    }

    RUBY_ASSERT(!rb_objspace_garbage_object_p((VALUE)next_shape));
    rb_shape_set_shape(obj, next_shape);
}

rb_shape_t*
rb_shape_get_next(rb_shape_t* shape, VALUE obj, ID id)
{
    return get_next_shape_internal(shape, id, obj, SHAPE_IVAR);
}

int
rb_shape_get_iv_index(rb_shape_t * shape, ID id, VALUE *value) {
    size_t depth = 0;
    int counting = FALSE;
    while (shape->parent) {
        if (counting) {
            depth++;
        }
        else {
            counting = (shape->edge_name == id);
        }
        shape = shape->parent;
    }
    if (counting) {
        *value = depth;
    }
    return counting;
}

static rb_shape_t *
shape_alloc(void)
{
    rb_shape_t *shape = (rb_shape_t *)rb_imemo_new(imemo_shape, 0, 0, 0, 0);
    FL_SET_RAW((VALUE)shape, RUBY_FL_SHAREABLE);
    return shape;
}

rb_shape_t *
rb_shape_alloc(shape_id_t shape_id, ID edge_name, rb_shape_t * parent)
{
    rb_shape_t * shape = shape_alloc();
    rb_shape_set_shape_id((VALUE)shape, shape_id);

    shape->edge_name = edge_name;
    shape->iv_count = parent ? parent->iv_count + 1 : 0;

    RB_OBJ_WRITE(shape, &shape->parent, parent);

    RUBY_ASSERT(!parent || IMEMO_TYPE_P(parent, imemo_shape));

    return shape;
}

MJIT_FUNC_EXPORTED struct rb_id_table *
rb_shape_generate_iv_table(rb_shape_t* shape) {
    if (rb_shape_frozen_shape_p(shape)) {
        return rb_shape_generate_iv_table(shape->parent);
    }

    struct rb_id_table *iv_table = rb_id_table_create(0);
    uint32_t index = 0;
    while (shape->parent) {
        rb_id_table_insert(iv_table, shape->edge_name, shape->iv_count - (VALUE)index - 1);
        index++;
        shape = shape->parent;
    }

    return iv_table;
}

MJIT_FUNC_EXPORTED void
rb_shape_set_shape(VALUE obj, rb_shape_t* shape)
{
    RUBY_ASSERT(IMEMO_TYPE_P(shape, imemo_shape));
    if(rb_shape_set_shape_id(obj, shape_get_shape_id(shape))) {
        RB_OBJ_WRITTEN(obj, Qundef, (VALUE)shape);
    }
}

static void
rb_shape_set_shape_in_bitmap(shape_id_t shape_id) {
    uint16_t bitmap_index = shape_id >> 5;
    uint32_t mask = (1 << (shape_id & 31));
    GET_VM()->shape_bitmaps[bitmap_index] |= mask;
}

static void
rb_shape_unset_shape_in_bitmap(shape_id_t shape_id) {
    uint16_t bitmap_index = shape_id >> 5;
    uint32_t mask = (1 << (shape_id & 31));
    GET_VM()->shape_bitmaps[bitmap_index] &= ~mask;
}

void
rb_shape_set_shape_by_id(shape_id_t shape_id, rb_shape_t *shape)
{
    rb_vm_t *vm = GET_VM();

    RUBY_ASSERT(shape == NULL || IMEMO_TYPE_P(shape, imemo_shape));

    if (shape == NULL) {
        rb_shape_unset_shape_in_bitmap(shape_id);
    }
    else {
        rb_shape_set_shape_in_bitmap(shape_id);
    }

    vm->shape_list[shape_id] = shape;
}

VALUE rb_cShape;

static void
shape_mark(void *ptr)
{
    rb_gc_mark((VALUE)ptr);
}

/*
 * Exposing Shape to Ruby via RubyVM.debug_shape
 */
static const rb_data_type_t shape_data_type = {
    "Shape",
    {shape_mark, NULL, NULL,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
};

static VALUE
rb_shape_id(VALUE self) {
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);
    return INT2NUM(SHAPE_ID(shape));
}

static VALUE
rb_shape_parent_id(VALUE self)
{
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);
    return INT2NUM(SHAPE_ID(shape->parent));
}

static VALUE parse_key(ID key) {
    if ((key & RUBY_ID_INTERNAL) == RUBY_ID_INTERNAL) {
        return LONG2NUM(key);
    } else {
        return ID2SYM(key);
    }
}

static VALUE
rb_shape_t_to_rb_cShape(rb_shape_t *shape) {
    union { const rb_shape_t *in; void *out; } deconst;
    VALUE res;
    deconst.in = shape;
    res = TypedData_Wrap_Struct(rb_cShape, &shape_data_type, deconst.out);
    RB_OBJ_WRITTEN(res, Qundef, shape);

    return res;
}

static enum rb_id_table_iterator_result rb_edges_to_hash(ID key, VALUE value, void *ref)
{
    rb_hash_aset(*(VALUE *)ref, parse_key(key), rb_shape_t_to_rb_cShape((rb_shape_t*)value));
    return ID_TABLE_CONTINUE;
}

static VALUE
rb_shape_edges(VALUE self)
{
    rb_shape_t* shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);

    VALUE hash = rb_hash_new();

    if (shape->edges) {
        rb_id_table_foreach(shape->edges, rb_edges_to_hash, &hash);
    }

    return hash;
}

static VALUE
rb_shape_export_depth(VALUE self)
{
    rb_shape_t* shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);

    unsigned int depth = 0;
    while (shape->parent) {
        depth++;
        shape = shape->parent;
    }
    return INT2NUM(depth);
}

static VALUE
rb_shape_parent(VALUE self)
{
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);
    return rb_shape_t_to_rb_cShape(shape->parent);
}

VALUE rb_shape_debug_shape(VALUE self, VALUE obj) {
    return rb_shape_t_to_rb_cShape(rb_shape_get_shape(obj));
}

VALUE rb_shape_debug_root_shape(VALUE self) {
    return rb_shape_t_to_rb_cShape(rb_shape_get_root_shape());
}

VALUE rb_shape_debug_frozen_root_shape(VALUE self) {
    return rb_shape_t_to_rb_cShape(rb_shape_get_frozen_root_shape());
}

VALUE rb_obj_shape(rb_shape_t* shape);

static enum rb_id_table_iterator_result collect_keys_and_values(ID key, VALUE value, void *ref)
{
    rb_hash_aset(*(VALUE *)ref, parse_key(key), rb_obj_shape((rb_shape_t*)value));
    return ID_TABLE_CONTINUE;
}

static VALUE edges(struct rb_id_table* edges)
{
    VALUE hash = rb_hash_new();
    if (edges)
        rb_id_table_foreach(edges, collect_keys_and_values, &hash);
    return hash;
}

VALUE rb_obj_shape(rb_shape_t* shape) {
    VALUE rb_shape = rb_hash_new();

    rb_hash_aset(rb_shape, ID2SYM(rb_intern("id")), INT2NUM(SHAPE_ID(shape)));
    rb_hash_aset(rb_shape, ID2SYM(rb_intern("edges")), edges(shape->edges));

    if (shape == rb_shape_get_root_shape()) {
        rb_hash_aset(rb_shape, ID2SYM(rb_intern("parent_id")), INT2NUM(ROOT_SHAPE_ID));
    }
    else {
        rb_hash_aset(rb_shape, ID2SYM(rb_intern("parent_id")), INT2NUM(SHAPE_ID(shape->parent)));
    }

    rb_hash_aset(rb_shape, ID2SYM(rb_intern("edge_name")), rb_id2str(shape->edge_name));
    return rb_shape;
}

static VALUE shape_transition_tree(VALUE self) {
    return rb_obj_shape(rb_shape_get_root_shape());
}

static VALUE shape_count(VALUE self) {
    int shape_count = 0;
    for(int i=0; i<MAX_SHAPE_ID; i++) {
        if(rb_shape_get_shape_by_id_without_assertion(i)) {
            shape_count++;
        }
    }
    return INT2NUM(shape_count);
}

static VALUE
shape_max_shape_count(VALUE self)
{
    return INT2NUM(GET_VM()->max_shape_count);
}

void
Init_shape(void)
{
    rb_cShape = rb_define_class_under(rb_cRubyVM, "Shape", rb_cObject);
    rb_undef_alloc_func(rb_cShape);

    rb_define_method(rb_cShape, "parent_id", rb_shape_parent_id, 0);
    rb_define_method(rb_cShape, "parent", rb_shape_parent, 0);
    rb_define_method(rb_cShape, "edges", rb_shape_edges, 0);
    rb_define_method(rb_cShape, "depth", rb_shape_export_depth, 0);
    rb_define_method(rb_cShape, "id", rb_shape_id, 0);

    rb_define_module_function(rb_cRubyVM, "debug_shape_transition_tree", shape_transition_tree, 0);
    rb_define_module_function(rb_cRubyVM, "debug_shape_count", shape_count, 0);
    rb_define_singleton_method(rb_cRubyVM, "debug_shape", rb_shape_debug_shape, 1);
    rb_define_singleton_method(rb_cRubyVM, "debug_max_shape_count", shape_max_shape_count, 0);
    rb_define_singleton_method(rb_cRubyVM, "debug_root_shape", rb_shape_debug_root_shape, 0);
    rb_define_singleton_method(rb_cRubyVM, "debug_frozen_root_shape", rb_shape_debug_frozen_root_shape, 0);
}
