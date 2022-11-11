#include "vm_core.h"
#include "vm_sync.h"
#include "shape.h"
#include "gc.h"
#include "internal/class.h"
#include "internal/symbol.h"
#include "internal/variable.h"
#include <stdbool.h>

static ID id_frozen;
static ID size_pool_edge_names[SIZE_POOL_COUNT];

/*
 * Shape getters
 */
rb_shape_t *
rb_shape_get_root_shape(void)
{
    return GET_VM()->root_shape;
}

shape_id_t
rb_shape_id(rb_shape_t * shape)
{
    return (shape_id_t)(shape - GET_VM()->shape_list);
}

bool
rb_shape_root_shape_p(rb_shape_t* shape)
{
    return shape == rb_shape_get_root_shape();
}

rb_shape_t*
rb_shape_get_shape_by_id(shape_id_t shape_id)
{
    RUBY_ASSERT(shape_id != INVALID_SHAPE_ID);

    rb_vm_t *vm = GET_VM();
    rb_shape_t *shape = &vm->shape_list[shape_id];
    return shape;
}

rb_shape_t*
rb_shape_get_shape_by_id_without_assertion(shape_id_t shape_id)
{
    RUBY_ASSERT(shape_id != INVALID_SHAPE_ID);

    rb_vm_t *vm = GET_VM();
    rb_shape_t *shape = &vm->shape_list[shape_id];
    return shape;
}

rb_shape_t *
rb_shape_get_parent(rb_shape_t * shape)
{
    return rb_shape_get_shape_by_id(shape->parent_id);
}

#if !SHAPE_IN_BASIC_FLAGS
shape_id_t
rb_rclass_shape_id(VALUE obj)
{
    RUBY_ASSERT(RB_TYPE_P(obj, T_CLASS) || RB_TYPE_P(obj, T_MODULE));
    return RCLASS_EXT(obj)->shape_id;
}

shape_id_t rb_generic_shape_id(VALUE obj);
#endif

shape_id_t
rb_shape_get_shape_id(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        return SPECIAL_CONST_SHAPE_ID;
    }

#if SHAPE_IN_BASIC_FLAGS
    return RBASIC_SHAPE_ID(obj);
#else
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
          return ROBJECT_SHAPE_ID(obj);
          break;
      case T_CLASS:
      case T_MODULE:
          return RCLASS_SHAPE_ID(obj);
      default:
          return rb_generic_shape_id(obj);
    }
#endif
}

rb_shape_t*
rb_shape_get_shape(VALUE obj)
{
    return rb_shape_get_shape_by_id(rb_shape_get_shape_id(obj));
}

static rb_shape_t *
rb_shape_lookup_id(rb_shape_t* shape, ID id, enum shape_type shape_type)
{
    while (shape->parent_id != INVALID_SHAPE_ID) {
        if (shape->edge_name == id) {
            // If the shape type is different, we don't
            // want this to count as a "found" ID
            if (shape_type == (enum shape_type)shape->type) {
                return shape;
            }
            else {
                return NULL;
            }
        }
        shape = rb_shape_get_parent(shape);
    }
    return NULL;
}

static rb_shape_t*
get_next_shape_internal(rb_shape_t * shape, ID id, enum shape_type shape_type)
{
    rb_shape_t *res = NULL;
    RB_VM_LOCK_ENTER();
    {
        if (rb_shape_lookup_id(shape, id, shape_type)) {
            // If shape already contains the ivar that is being set, we'll return shape
            res = shape;
        }
        else {
            if (!shape->edges) {
                shape->edges = rb_id_table_create(0);
            }

            // Lookup the shape in edges - if there's already an edge and a corresponding shape for it,
            // we can return that. Otherwise, we'll need to get a new shape
            if (!rb_id_table_lookup(shape->edges, id, (VALUE *)&res)) {
                // In this case, the shape exists, but the shape is garbage, so we need to recreate it
                if (res) {
                    rb_id_table_delete(shape->edges, id);
                    res->parent_id = INVALID_SHAPE_ID;
                }

                rb_shape_t * new_shape = rb_shape_alloc(id, shape);

                new_shape->type = (uint8_t)shape_type;
                new_shape->capacity = shape->capacity;

                switch (shape_type) {
                  case SHAPE_IVAR:
                    new_shape->next_iv_index = shape->next_iv_index + 1;
                    break;
                  case SHAPE_CAPACITY_CHANGE:
                  case SHAPE_IVAR_UNDEF:
                  case SHAPE_FROZEN:
                    new_shape->next_iv_index = shape->next_iv_index;
                    break;
                  case SHAPE_INITIAL_CAPACITY:
                  case SHAPE_ROOT:
                    rb_bug("Unreachable");
                    break;
                }

                rb_id_table_insert(shape->edges, id, (VALUE)new_shape);

                res = new_shape;
            }
        }
    }
    RB_VM_LOCK_LEAVE();
    return res;
}

MJIT_FUNC_EXPORTED int
rb_shape_frozen_shape_p(rb_shape_t* shape)
{
    return SHAPE_FROZEN == (enum shape_type)shape->type;
}

void
rb_shape_transition_shape_remove_ivar(VALUE obj, ID id, rb_shape_t *shape)
{
    rb_shape_t * next_shape = get_next_shape_internal(shape, id, SHAPE_IVAR_UNDEF);

    if (shape == next_shape) {
        return;
    }

    rb_shape_set_shape(obj, next_shape);
}

void
rb_shape_transition_shape_frozen(VALUE obj)
{
    rb_shape_t* shape = rb_shape_get_shape(obj);
    RUBY_ASSERT(shape);
    RUBY_ASSERT(RB_OBJ_FROZEN(obj));

    if (rb_shape_frozen_shape_p(shape)) {
        return;
    }

    rb_shape_t* next_shape;

    if (shape == rb_shape_get_root_shape()) {
        rb_shape_set_shape_id(obj, SPECIAL_CONST_SHAPE_ID);
        return;
    }

    next_shape = get_next_shape_internal(shape, (ID)id_frozen, SHAPE_FROZEN);

    RUBY_ASSERT(next_shape);
    rb_shape_set_shape(obj, next_shape);
}

/*
 * This function is used for assertions where we don't want to increment
 * max_iv_count
 */
rb_shape_t *
rb_shape_get_next_iv_shape(rb_shape_t* shape, ID id)
{
    return get_next_shape_internal(shape, id, SHAPE_IVAR);
}

rb_shape_t *
rb_shape_get_next(rb_shape_t* shape, VALUE obj, ID id)
{
    rb_shape_t * new_shape = rb_shape_get_next_iv_shape(shape, id);

    // Check if we should update max_iv_count on the object's class
    if (BUILTIN_TYPE(obj) == T_OBJECT) {
        VALUE klass = rb_obj_class(obj);
        if (new_shape->next_iv_index > RCLASS_EXT(klass)->max_iv_count) {
            RCLASS_EXT(klass)->max_iv_count = new_shape->next_iv_index;
        }
    }

    return new_shape;
}

rb_shape_t *
rb_shape_transition_shape_capa(rb_shape_t* shape, uint32_t new_capacity)
{
    ID edge_name = rb_make_temporary_id(new_capacity);
    rb_shape_t * new_shape = get_next_shape_internal(shape, edge_name, SHAPE_CAPACITY_CHANGE);
    new_shape->capacity = new_capacity;
    return new_shape;
}

bool
rb_shape_get_iv_index(rb_shape_t * shape, ID id, attr_index_t *value)
{
    while (shape->parent_id != INVALID_SHAPE_ID) {
        if (shape->edge_name == id) {
            enum shape_type shape_type;
            shape_type = (enum shape_type)shape->type;

            switch (shape_type) {
              case SHAPE_IVAR:
                RUBY_ASSERT(shape->next_iv_index > 0);
                *value = shape->next_iv_index - 1;
                return true;
              case SHAPE_CAPACITY_CHANGE:
              case SHAPE_IVAR_UNDEF:
              case SHAPE_ROOT:
              case SHAPE_INITIAL_CAPACITY:
                return false;
              case SHAPE_FROZEN:
                rb_bug("Ivar should not exist on transition\n");
            }
        }
        shape = rb_shape_get_parent(shape);
    }
    return false;
}

static rb_shape_t *
shape_alloc(void)
{
    rb_vm_t *vm = GET_VM();
    shape_id_t shape_id = vm->next_shape_id;
    vm->next_shape_id++;

    if (shape_id == MAX_SHAPE_ID) {
        // TODO: Make an OutOfShapesError ??
        rb_bug("Out of shapes\n");
    }

    return &GET_VM()->shape_list[shape_id];
}

rb_shape_t *
rb_shape_alloc_with_parent_id(ID edge_name, shape_id_t parent_id)
{
    rb_shape_t * shape = shape_alloc();

    shape->edge_name = edge_name;
    shape->next_iv_index = 0;
    shape->parent_id = parent_id;

    return shape;
}

rb_shape_t *
rb_shape_alloc_with_size_pool_index(ID edge_name, rb_shape_t * parent, uint8_t size_pool_index)
{
    rb_shape_t * shape = rb_shape_alloc_with_parent_id(edge_name, rb_shape_id(parent));
    shape->size_pool_index = size_pool_index;
    return shape;
}


rb_shape_t *
rb_shape_alloc(ID edge_name, rb_shape_t * parent)
{
    return rb_shape_alloc_with_size_pool_index(edge_name, parent, parent->size_pool_index);
}

MJIT_FUNC_EXPORTED void
rb_shape_set_shape(VALUE obj, rb_shape_t* shape)
{
    rb_shape_set_shape_id(obj, rb_shape_id(shape));
}

VALUE
rb_shape_flags_mask(void)
{
    return SHAPE_FLAG_MASK;
}

rb_shape_t *
rb_shape_rebuild_shape(rb_shape_t * initial_shape, rb_shape_t * dest_shape)
{
    rb_shape_t * midway_shape;

    if (dest_shape->type != SHAPE_ROOT) {
        midway_shape = rb_shape_rebuild_shape(initial_shape, rb_shape_get_parent(dest_shape));
    }
    else {
        midway_shape = initial_shape;
    }

    switch (dest_shape->type) {
        case SHAPE_IVAR:
            if (midway_shape->capacity < midway_shape->next_iv_index) {
                // There isn't enough room to write this IV, so we need to increase the capacity
                midway_shape = rb_shape_transition_shape_capa(midway_shape, midway_shape->capacity * 2);
            }

            midway_shape = rb_shape_get_next_iv_shape(midway_shape, dest_shape->edge_name);
            break;
        case SHAPE_IVAR_UNDEF:
            midway_shape = get_next_shape_internal(midway_shape, dest_shape->edge_name, SHAPE_IVAR_UNDEF);
            break;
        case SHAPE_ROOT:
        case SHAPE_FROZEN:
        case SHAPE_CAPACITY_CHANGE:
            break;
    }

    return midway_shape;
}

#if VM_CHECK_MODE > 0
VALUE rb_cShape;

/*
 * Exposing Shape to Ruby via RubyVM.debug_shape
 */
static const rb_data_type_t shape_data_type = {
    "Shape",
    {NULL, NULL, NULL,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
};

static VALUE
rb_wrapped_shape_id(VALUE self)
{
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);
    return INT2NUM(rb_shape_id(shape));
}

static VALUE
rb_shape_type(VALUE self)
{
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);
    return INT2NUM(shape->type);
}

static VALUE
rb_shape_capacity(VALUE self)
{
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);
    return INT2NUM(shape->capacity);
}

static VALUE
rb_shape_parent_id(VALUE self)
{
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);
    if (shape->parent_id != INVALID_SHAPE_ID) {
        return INT2NUM(shape->parent_id);
    }
    else {
        return Qnil;
    }
}

static VALUE
parse_key(ID key)
{
    if ((key & RUBY_ID_INTERNAL) == RUBY_ID_INTERNAL) {
        return LONG2NUM(key);
    }
    else {
        return ID2SYM(key);
    }
}

static VALUE
rb_shape_t_to_rb_cShape(rb_shape_t *shape)
{
    union { const rb_shape_t *in; void *out; } deconst;
    VALUE res;
    deconst.in = shape;
    res = TypedData_Wrap_Struct(rb_cShape, &shape_data_type, deconst.out);

    return res;
}

static enum rb_id_table_iterator_result
rb_edges_to_hash(ID key, VALUE value, void *ref)
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
rb_shape_edge_name(VALUE self)
{
    rb_shape_t* shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);

    if ((shape->edge_name & (ID_INTERNAL)) == ID_INTERNAL) {
        return INT2NUM(shape->capacity);
    }
    else {
        if (shape->edge_name) {
            return ID2SYM(shape->edge_name);
        }
        else {
            return Qnil;
        }
    }
}

static VALUE
rb_shape_next_iv_index(VALUE self)
{
    rb_shape_t* shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);

    return INT2NUM(shape->next_iv_index);
}

static VALUE
rb_shape_size_pool_index(VALUE self)
{
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);

    return INT2NUM(shape->size_pool_index);
}

static VALUE
rb_shape_export_depth(VALUE self)
{
    rb_shape_t* shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);

    unsigned int depth = 0;
    while (shape->parent_id != INVALID_SHAPE_ID) {
        depth++;
        shape = rb_shape_get_parent(shape);
    }
    return INT2NUM(depth);
}

static VALUE
rb_shape_parent(VALUE self)
{
    rb_shape_t * shape;
    TypedData_Get_Struct(self, rb_shape_t, &shape_data_type, shape);
    if (shape->parent_id != INVALID_SHAPE_ID) {
        return rb_shape_t_to_rb_cShape(rb_shape_get_parent(shape));
    }
    else {
        return Qnil;
    }
}

static VALUE
rb_shape_debug_shape(VALUE self, VALUE obj)
{
    return rb_shape_t_to_rb_cShape(rb_shape_get_shape(obj));
}

static VALUE
rb_shape_root_shape(VALUE self)
{
    return rb_shape_t_to_rb_cShape(rb_shape_get_root_shape());
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

VALUE
rb_obj_shape(rb_shape_t* shape)
{
    VALUE rb_shape = rb_hash_new();

    rb_hash_aset(rb_shape, ID2SYM(rb_intern("id")), INT2NUM(rb_shape_id(shape)));
    rb_hash_aset(rb_shape, ID2SYM(rb_intern("edges")), edges(shape->edges));

    if (shape == rb_shape_get_root_shape()) {
        rb_hash_aset(rb_shape, ID2SYM(rb_intern("parent_id")), INT2NUM(ROOT_SHAPE_ID));
    }
    else {
        rb_hash_aset(rb_shape, ID2SYM(rb_intern("parent_id")), INT2NUM(shape->parent_id));
    }

    rb_hash_aset(rb_shape, ID2SYM(rb_intern("edge_name")), rb_id2str(shape->edge_name));
    return rb_shape;
}

static VALUE
shape_transition_tree(VALUE self)
{
    return rb_obj_shape(rb_shape_get_root_shape());
}

static VALUE
next_shape_id(VALUE self)
{
    return INT2NUM(GET_VM()->next_shape_id);
}

static VALUE
rb_shape_find_by_id(VALUE mod, VALUE id)
{
    shape_id_t shape_id = NUM2UINT(id);
    if (shape_id >= GET_VM()->next_shape_id) {
        rb_raise(rb_eArgError, "Shape ID %d is out of bounds\n", shape_id);
    }
    return rb_shape_t_to_rb_cShape(rb_shape_get_shape_by_id(shape_id));
}
#endif

void
Init_default_shapes(void)
{
    id_frozen = rb_make_internal_id();

    // Shapes by size pool
    for (int i = 0; i < SIZE_POOL_COUNT; i++) {
        size_pool_edge_names[i] = rb_make_internal_id();
    }

    // Root shape
    rb_shape_t * root = rb_shape_alloc_with_parent_id(0, INVALID_SHAPE_ID);
    root->capacity = (uint32_t)((rb_size_pool_slot_size(0) - offsetof(struct RObject, as.ary)) / sizeof(VALUE));
    root->type = SHAPE_ROOT;
    root->size_pool_index = 0;
    GET_VM()->root_shape = root;
    RUBY_ASSERT(rb_shape_id(GET_VM()->root_shape) == ROOT_SHAPE_ID);

    // Shapes by size pool
    for (int i = 1; i < SIZE_POOL_COUNT; i++) {
        uint32_t capa = (uint32_t)((rb_size_pool_slot_size(i) - offsetof(struct RObject, as.ary)) / sizeof(VALUE));
        rb_shape_t * new_shape = rb_shape_transition_shape_capa(root, capa);
        new_shape->type = SHAPE_INITIAL_CAPACITY;
        new_shape->size_pool_index = i;
        RUBY_ASSERT(rb_shape_id(new_shape) == (shape_id_t)i);
    }

    // Special const shape
#if RUBY_DEBUG
    rb_shape_t * special_const_shape =
#endif
        get_next_shape_internal(root, (ID)id_frozen, SHAPE_FROZEN);
    RUBY_ASSERT(rb_shape_id(special_const_shape) == SPECIAL_CONST_SHAPE_ID);
    RUBY_ASSERT(SPECIAL_CONST_SHAPE_ID == (GET_VM()->next_shape_id - 1));
    RUBY_ASSERT(rb_shape_frozen_shape_p(special_const_shape));
}

void
Init_shape(void)
{
#if VM_CHECK_MODE > 0
    rb_cShape = rb_define_class_under(rb_cRubyVM, "Shape", rb_cObject);
    rb_undef_alloc_func(rb_cShape);

    rb_define_method(rb_cShape, "parent_id", rb_shape_parent_id, 0);
    rb_define_method(rb_cShape, "parent", rb_shape_parent, 0);
    rb_define_method(rb_cShape, "edges", rb_shape_edges, 0);
    rb_define_method(rb_cShape, "edge_name", rb_shape_edge_name, 0);
    rb_define_method(rb_cShape, "next_iv_index", rb_shape_next_iv_index, 0);
    rb_define_method(rb_cShape, "size_pool_index", rb_shape_size_pool_index, 0);
    rb_define_method(rb_cShape, "depth", rb_shape_export_depth, 0);
    rb_define_method(rb_cShape, "id", rb_wrapped_shape_id, 0);
    rb_define_method(rb_cShape, "type", rb_shape_type, 0);
    rb_define_method(rb_cShape, "capacity", rb_shape_capacity, 0);
    rb_define_const(rb_cShape, "SHAPE_ROOT", INT2NUM(SHAPE_ROOT));
    rb_define_const(rb_cShape, "SHAPE_IVAR", INT2NUM(SHAPE_IVAR));
    rb_define_const(rb_cShape, "SHAPE_IVAR_UNDEF", INT2NUM(SHAPE_IVAR_UNDEF));
    rb_define_const(rb_cShape, "SHAPE_FROZEN", INT2NUM(SHAPE_FROZEN));
    rb_define_const(rb_cShape, "SHAPE_BITS", INT2NUM(SHAPE_BITS));
    rb_define_const(rb_cShape, "SHAPE_FLAG_SHIFT", INT2NUM(SHAPE_FLAG_SHIFT));
    rb_define_const(rb_cShape, "SPECIAL_CONST_SHAPE_ID", INT2NUM(SPECIAL_CONST_SHAPE_ID));

    rb_define_singleton_method(rb_cShape, "transition_tree", shape_transition_tree, 0);
    rb_define_singleton_method(rb_cShape, "find_by_id", rb_shape_find_by_id, 1);
    rb_define_singleton_method(rb_cShape, "next_shape_id", next_shape_id, 0);
    rb_define_singleton_method(rb_cShape, "of", rb_shape_debug_shape, 1);
    rb_define_singleton_method(rb_cShape, "root_shape", rb_shape_root_shape, 0);
#endif
}
