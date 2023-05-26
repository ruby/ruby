#include "vm_core.h"
#include "vm_sync.h"
#include "shape.h"
#include "symbol.h"
#include "id_table.h"
#include "internal/class.h"
#include "internal/gc.h"
#include "internal/symbol.h"
#include "internal/variable.h"
#include "internal/error.h"
#include "variable.h"
#include <stdbool.h>

#ifndef SHAPE_DEBUG
#define SHAPE_DEBUG (VM_CHECK_MODE > 0)
#endif

#define SINGLE_CHILD_TAG 0x1
#define TAG_SINGLE_CHILD(x) (struct rb_id_table *)((uintptr_t)x | SINGLE_CHILD_TAG)
#define SINGLE_CHILD_MASK (~((uintptr_t)SINGLE_CHILD_TAG))
#define SINGLE_CHILD_P(x) (((uintptr_t)x) & SINGLE_CHILD_TAG)
#define SINGLE_CHILD(x) (rb_shape_t *)((uintptr_t)x & SINGLE_CHILD_MASK)

static ID id_frozen;
static ID id_t_object;
static ID size_pool_edge_names[SIZE_POOL_COUNT];

rb_shape_tree_t *rb_shape_tree_ptr = NULL;

/*
 * Shape getters
 */
rb_shape_t *
rb_shape_get_root_shape(void)
{
    return GET_SHAPE_TREE()->root_shape;
}

shape_id_t
rb_shape_id(rb_shape_t * shape)
{
    return (shape_id_t)(shape - GET_SHAPE_TREE()->shape_list);
}

void
rb_shape_each_shape(each_shape_callback callback, void *data)
{
    rb_shape_t *cursor = rb_shape_get_root_shape();
    rb_shape_t *end = rb_shape_get_shape_by_id(GET_SHAPE_TREE()->next_shape_id);
    while (cursor < end) {
        callback(cursor, data);
        cursor += 1;
    }
}

RUBY_FUNC_EXPORTED rb_shape_t*
rb_shape_get_shape_by_id(shape_id_t shape_id)
{
    RUBY_ASSERT(shape_id != INVALID_SHAPE_ID);

    rb_shape_t *shape = &GET_SHAPE_TREE()->shape_list[shape_id];
    return shape;
}

rb_shape_t *
rb_shape_get_parent(rb_shape_t * shape)
{
    return rb_shape_get_shape_by_id(shape->parent_id);
}

#if !SHAPE_IN_BASIC_FLAGS
shape_id_t rb_generic_shape_id(VALUE obj);
#endif

RUBY_FUNC_EXPORTED shape_id_t
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

size_t
rb_shape_depth(rb_shape_t * shape)
{
    size_t depth = 1;

    while (shape->parent_id != INVALID_SHAPE_ID) {
        depth++;
        shape = rb_shape_get_parent(shape);
    }

    return depth;
}

rb_shape_t*
rb_shape_get_shape(VALUE obj)
{
    return rb_shape_get_shape_by_id(rb_shape_get_shape_id(obj));
}

static rb_shape_t *
shape_alloc(void)
{
    shape_id_t shape_id = GET_SHAPE_TREE()->next_shape_id;
    GET_SHAPE_TREE()->next_shape_id++;

    if (shape_id == MAX_SHAPE_ID) {
        // TODO: Make an OutOfShapesError ??
        rb_bug("Out of shapes");
    }

    return &GET_SHAPE_TREE()->shape_list[shape_id];
}

static rb_shape_t *
rb_shape_alloc_with_parent_id(ID edge_name, shape_id_t parent_id)
{
    rb_shape_t * shape = shape_alloc();

    shape->edge_name = edge_name;
    shape->next_iv_index = 0;
    shape->parent_id = parent_id;
    shape->edges = NULL;

    return shape;
}

static rb_shape_t *
rb_shape_alloc(ID edge_name, rb_shape_t * parent, enum shape_type type)
{
    rb_shape_t * shape = rb_shape_alloc_with_parent_id(edge_name, rb_shape_id(parent));
    shape->type = (uint8_t)type;
    shape->size_pool_index = parent->size_pool_index;
    shape->capacity = parent->capacity;
    shape->edges = 0;
    return shape;
}

static rb_shape_t *
rb_shape_alloc_new_child(ID id, rb_shape_t * shape, enum shape_type shape_type)
{
    rb_shape_t * new_shape = rb_shape_alloc(id, shape, shape_type);

    switch (shape_type) {
      case SHAPE_IVAR:
        new_shape->next_iv_index = shape->next_iv_index + 1;
        break;
      case SHAPE_CAPACITY_CHANGE:
      case SHAPE_FROZEN:
      case SHAPE_T_OBJECT:
        new_shape->next_iv_index = shape->next_iv_index;
        break;
      case SHAPE_OBJ_TOO_COMPLEX:
      case SHAPE_INITIAL_CAPACITY:
      case SHAPE_ROOT:
        rb_bug("Unreachable");
        break;
    }

    return new_shape;
}

static rb_shape_t*
get_next_shape_internal(rb_shape_t * shape, ID id, enum shape_type shape_type, bool * variation_created, bool new_shapes_allowed, bool new_shape_necessary)
{
    rb_shape_t *res = NULL;

    // There should never be outgoing edges from "too complex"
    RUBY_ASSERT(rb_shape_id(shape) != OBJ_TOO_COMPLEX_SHAPE_ID);

    *variation_created = false;

    if (new_shape_necessary || (new_shapes_allowed && (shape->next_iv_index < SHAPE_MAX_NUM_IVS))) {
        RB_VM_LOCK_ENTER();
        {
            // If the current shape has children
            if (shape->edges) {
                // Check if it only has one child
                if (SINGLE_CHILD_P(shape->edges)) {
                    rb_shape_t * child = SINGLE_CHILD(shape->edges);
                    // If the one child has a matching edge name, then great,
                    // we found what we want.
                    if (child->edge_name == id) {
                        res = child;
                    }
                    else {
                        // Otherwise we're going to have to create a new shape
                        // and insert it as a child node, so create an id
                        // table and insert the existing child
                        shape->edges = rb_id_table_create(2);
                        rb_id_table_insert(shape->edges, child->edge_name, (VALUE)child);
                    }
                }
                else {
                    // If it has more than one child, do a hash lookup to find it.
                    VALUE lookup_result;
                    if (rb_id_table_lookup(shape->edges, id, &lookup_result)) {
                        res = (rb_shape_t *)lookup_result;
                    }
                }

                // If the shape we were looking for above was found,
                // then `res` will be set to the child.  If it isn't set, then
                // we know we need a new child shape, and that we must insert
                // it in to the table.
                if (!res) {
                    *variation_created = true;
                    rb_shape_t * new_shape = rb_shape_alloc_new_child(id, shape, shape_type);
                    rb_id_table_insert(shape->edges, id, (VALUE)new_shape);
                    res = new_shape;
                }
            }
            else {
                // If the shape didn't have any outgoing edges, then create
                // the new outgoing edge and tag the pointer.
                rb_shape_t * new_shape = rb_shape_alloc_new_child(id, shape, shape_type);
                shape->edges = TAG_SINGLE_CHILD(new_shape);
                res = new_shape;
            }
        }
        RB_VM_LOCK_LEAVE();
    }
    return res;
}

int
rb_shape_frozen_shape_p(rb_shape_t* shape)
{
    return SHAPE_FROZEN == (enum shape_type)shape->type;
}

static void
move_iv(VALUE obj, ID id, attr_index_t from, attr_index_t to)
{
    switch(BUILTIN_TYPE(obj)) {
      case T_CLASS:
      case T_MODULE:
        RCLASS_IVPTR(obj)[to] = RCLASS_IVPTR(obj)[from];
        break;
      case T_OBJECT:
        RUBY_ASSERT(!rb_shape_obj_too_complex(obj));
        ROBJECT_IVPTR(obj)[to] = ROBJECT_IVPTR(obj)[from];
        break;
      default: {
        struct gen_ivtbl *ivtbl;
        rb_gen_ivtbl_get(obj, id, &ivtbl);
        ivtbl->ivptr[to] = ivtbl->ivptr[from];
        break;
      }
    }
}

static rb_shape_t *
remove_shape_recursive(VALUE obj, ID id, rb_shape_t * shape, VALUE * removed)
{
    if (shape->parent_id == INVALID_SHAPE_ID) {
        // We've hit the top of the shape tree and couldn't find the
        // IV we wanted to remove, so return NULL
        return NULL;
    }
    else {
        if (shape->type == SHAPE_IVAR && shape->edge_name == id) {
            // We've hit the edge we wanted to remove, return it's _parent_
            // as the new parent while we go back down the stack.
            attr_index_t index = shape->next_iv_index - 1;

            switch(BUILTIN_TYPE(obj)) {
              case T_CLASS:
              case T_MODULE:
                *removed = RCLASS_IVPTR(obj)[index];
                break;
              case T_OBJECT:
                *removed = ROBJECT_IVPTR(obj)[index];
                break;
              default: {
                struct gen_ivtbl *ivtbl;
                rb_gen_ivtbl_get(obj, id, &ivtbl);
                *removed = ivtbl->ivptr[index];
                break;
              }
            }
            return rb_shape_get_parent(shape);
        }
        else {
            // This isn't the IV we want to remove, keep walking up.
            rb_shape_t * new_parent = remove_shape_recursive(obj, id, rb_shape_get_parent(shape), removed);

            // We found a new parent.  Create a child of the new parent that
            // has the same attributes as this shape.
            if (new_parent) {
                bool dont_care;
                enum ruby_value_type type = BUILTIN_TYPE(obj);
                bool new_shape_necessary = type != T_OBJECT;
                rb_shape_t * new_child = get_next_shape_internal(new_parent, shape->edge_name, shape->type, &dont_care, true, new_shape_necessary);
                new_child->capacity = shape->capacity;
                if (new_child->type == SHAPE_IVAR) {
                    move_iv(obj, id, shape->next_iv_index - 1, new_child->next_iv_index - 1);
                }

                return new_child;
            }
            else {
                // We went all the way to the top of the shape tree and couldn't
                // find an IV to remove, so return NULL
                return NULL;
            }
        }
    }
}

void
rb_shape_transition_shape_remove_ivar(VALUE obj, ID id, rb_shape_t *shape, VALUE * removed)
{
    rb_shape_t * new_shape = remove_shape_recursive(obj, id, shape, removed);
    if (new_shape) {
        rb_shape_set_shape(obj, new_shape);
    }
}

void
rb_shape_transition_shape_frozen(VALUE obj)
{
    rb_shape_t* shape = rb_shape_get_shape(obj);
    RUBY_ASSERT(shape);
    RUBY_ASSERT(RB_OBJ_FROZEN(obj));

    if (rb_shape_frozen_shape_p(shape) || rb_shape_obj_too_complex(obj)) {
        return;
    }

    rb_shape_t* next_shape;

    if (shape == rb_shape_get_root_shape()) {
        rb_shape_set_shape_id(obj, SPECIAL_CONST_SHAPE_ID);
        return;
    }

    bool dont_care;
    next_shape = get_next_shape_internal(shape, (ID)id_frozen, SHAPE_FROZEN, &dont_care, true, false);

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
    RUBY_ASSERT(!is_instance_id(id) || RTEST(rb_sym2str(ID2SYM(id))));
    bool dont_care;
    return get_next_shape_internal(shape, id, SHAPE_IVAR, &dont_care, true, false);
}

rb_shape_t *
rb_shape_get_next(rb_shape_t* shape, VALUE obj, ID id)
{
    RUBY_ASSERT(!is_instance_id(id) || RTEST(rb_sym2str(ID2SYM(id))));

    bool allow_new_shape = true;

    if (BUILTIN_TYPE(obj) == T_OBJECT) {
        VALUE klass = rb_obj_class(obj);
        allow_new_shape = RCLASS_EXT(klass)->variation_count < SHAPE_MAX_VARIATIONS;
    }

    bool variation_created = false;
    // For non T_OBJECTS, force a new shape
    bool new_shape_necessary = BUILTIN_TYPE(obj) != T_OBJECT;
    rb_shape_t * new_shape = get_next_shape_internal(shape, id, SHAPE_IVAR, &variation_created, allow_new_shape, new_shape_necessary);

    if (!new_shape) {
        RUBY_ASSERT(BUILTIN_TYPE(obj) == T_OBJECT);
        new_shape = rb_shape_get_shape_by_id(OBJ_TOO_COMPLEX_SHAPE_ID);
    }

    // Check if we should update max_iv_count on the object's class
    if (BUILTIN_TYPE(obj) == T_OBJECT) {
        VALUE klass = rb_obj_class(obj);
        if (new_shape->next_iv_index > RCLASS_EXT(klass)->max_iv_count) {
            RCLASS_EXT(klass)->max_iv_count = new_shape->next_iv_index;
        }

        if (variation_created) {
            RCLASS_EXT(klass)->variation_count++;
            if (rb_warning_category_enabled_p(RB_WARN_CATEGORY_PERFORMANCE)) {
                if (RCLASS_EXT(klass)->variation_count >= SHAPE_MAX_VARIATIONS) {
                    rb_category_warn(
                        RB_WARN_CATEGORY_PERFORMANCE,
                        "Maximum shapes variations (%d) reached by %"PRIsVALUE", instance variables accesses will be slower.",
                        SHAPE_MAX_VARIATIONS,
                        rb_class_path(klass)
                    );
                }
            }
        }
    }

    return new_shape;
}

rb_shape_t *
rb_shape_transition_shape_capa(rb_shape_t* shape, uint32_t new_capacity)
{
    ID edge_name = rb_make_temporary_id(new_capacity);
    bool dont_care;
    rb_shape_t * new_shape = get_next_shape_internal(shape, edge_name, SHAPE_CAPACITY_CHANGE, &dont_care, true, false);
    new_shape->capacity = new_capacity;
    return new_shape;
}

bool
rb_shape_get_iv_index(rb_shape_t * shape, ID id, attr_index_t *value)
{
    // It doesn't make sense to ask for the index of an IV that's stored
    // on an object that is "too complex" as it uses a hash for storing IVs
    RUBY_ASSERT(rb_shape_id(shape) != OBJ_TOO_COMPLEX_SHAPE_ID);

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
              case SHAPE_ROOT:
              case SHAPE_INITIAL_CAPACITY:
              case SHAPE_T_OBJECT:
                return false;
              case SHAPE_OBJ_TOO_COMPLEX:
              case SHAPE_FROZEN:
                rb_bug("Ivar should not exist on transition");
            }
        }
        shape = rb_shape_get_parent(shape);
    }
    return false;
}

void
rb_shape_set_shape(VALUE obj, rb_shape_t* shape)
{
    rb_shape_set_shape_id(obj, rb_shape_id(shape));
}

int32_t
rb_shape_id_offset(void)
{
    return sizeof(uintptr_t) - SHAPE_ID_NUM_BITS / sizeof(uintptr_t);
}

rb_shape_t *
rb_shape_traverse_from_new_root(rb_shape_t *initial_shape, rb_shape_t *dest_shape)
{
    RUBY_ASSERT(initial_shape->type == SHAPE_T_OBJECT);
    rb_shape_t *next_shape = initial_shape;

    if (dest_shape->type != initial_shape->type) {
        next_shape = rb_shape_traverse_from_new_root(initial_shape, rb_shape_get_parent(dest_shape));
        if (!next_shape) {
            return NULL;
        }
    }

    switch ((enum shape_type)dest_shape->type) {
      case SHAPE_IVAR:
      case SHAPE_FROZEN:
        if (!next_shape->edges) {
            return NULL;
        }

        VALUE lookup_result;
        if (SINGLE_CHILD_P(next_shape->edges)) {
            rb_shape_t * child = SINGLE_CHILD(next_shape->edges);
            if (child->edge_name == dest_shape->edge_name) {
                return child;
            }
            else {
                return NULL;
            }
        }
        else {
            if (rb_id_table_lookup(next_shape->edges, dest_shape->edge_name, &lookup_result)) {
                next_shape = (rb_shape_t *)lookup_result;
            }
            else {
                return NULL;
            }
        }
        break;
      case SHAPE_ROOT:
      case SHAPE_CAPACITY_CHANGE:
      case SHAPE_INITIAL_CAPACITY:
      case SHAPE_T_OBJECT:
        break;
      case SHAPE_OBJ_TOO_COMPLEX:
        rb_bug("Unreachable");
        break;
    }

    return next_shape;
}

rb_shape_t *
rb_shape_rebuild_shape(rb_shape_t * initial_shape, rb_shape_t * dest_shape)
{
    rb_shape_t * midway_shape;

    RUBY_ASSERT(initial_shape->type == SHAPE_T_OBJECT);

    if (dest_shape->type != initial_shape->type) {
        midway_shape = rb_shape_rebuild_shape(initial_shape, rb_shape_get_parent(dest_shape));
    }
    else {
        midway_shape = initial_shape;
    }

    switch ((enum shape_type)dest_shape->type) {
      case SHAPE_IVAR:
        if (midway_shape->capacity <= midway_shape->next_iv_index) {
            // There isn't enough room to write this IV, so we need to increase the capacity
            midway_shape = rb_shape_transition_shape_capa(midway_shape, midway_shape->capacity * 2);
        }

        midway_shape = rb_shape_get_next_iv_shape(midway_shape, dest_shape->edge_name);
        break;
      case SHAPE_ROOT:
      case SHAPE_FROZEN:
      case SHAPE_CAPACITY_CHANGE:
      case SHAPE_INITIAL_CAPACITY:
      case SHAPE_T_OBJECT:
        break;
      case SHAPE_OBJ_TOO_COMPLEX:
        rb_bug("Unreachable");
        break;
    }

    return midway_shape;
}

RUBY_FUNC_EXPORTED bool
rb_shape_obj_too_complex(VALUE obj)
{
    return rb_shape_get_shape_id(obj) == OBJ_TOO_COMPLEX_SHAPE_ID;
}

void
rb_shape_set_too_complex(VALUE obj)
{
    RUBY_ASSERT(BUILTIN_TYPE(obj) == T_OBJECT);
    RUBY_ASSERT(!rb_shape_obj_too_complex(obj));
    rb_shape_set_shape_id(obj, OBJ_TOO_COMPLEX_SHAPE_ID);
}

size_t
rb_shape_edges_count(rb_shape_t *shape)
{
    if (shape->edges) {
        if (SINGLE_CHILD_P(shape->edges)) {
            return 1;
        }
        else {
            return rb_id_table_size(shape->edges);
        }
    }
    return 0;
}

size_t
rb_shape_memsize(rb_shape_t *shape)
{
    size_t memsize = sizeof(rb_shape_t);
    if (shape->edges && !SINGLE_CHILD_P(shape->edges)) {
        memsize += rb_id_table_memsize(shape->edges);
    }
    return memsize;
}

#if SHAPE_DEBUG
/*
 * Exposing Shape to Ruby via RubyVM.debug_shape
 */

/* :nodoc: */
static VALUE
rb_shape_too_complex(VALUE self)
{
    rb_shape_t * shape;
    shape = rb_shape_get_shape_by_id(NUM2INT(rb_struct_getmember(self, rb_intern("id"))));
    if (rb_shape_id(shape) == OBJ_TOO_COMPLEX_SHAPE_ID) {
        return Qtrue;
    }
    else {
        return Qfalse;
    }
}

static VALUE
parse_key(ID key)
{
    if (is_instance_id(key)) {
        return ID2SYM(key);
    }
    return LONG2NUM(key);
}

static VALUE rb_shape_edge_name(rb_shape_t * shape);

static VALUE
rb_shape_t_to_rb_cShape(rb_shape_t *shape)
{
    VALUE rb_cShape = rb_const_get(rb_cRubyVM, rb_intern("Shape"));

    VALUE obj = rb_struct_new(rb_cShape,
            INT2NUM(rb_shape_id(shape)),
            INT2NUM(shape->parent_id),
            rb_shape_edge_name(shape),
            INT2NUM(shape->next_iv_index),
            INT2NUM(shape->size_pool_index),
            INT2NUM(shape->type),
            INT2NUM(shape->capacity));
    rb_obj_freeze(obj);
    return obj;
}

static enum rb_id_table_iterator_result
rb_edges_to_hash(ID key, VALUE value, void *ref)
{
    rb_hash_aset(*(VALUE *)ref, parse_key(key), rb_shape_t_to_rb_cShape((rb_shape_t*)value));
    return ID_TABLE_CONTINUE;
}

/* :nodoc: */
static VALUE
rb_shape_edges(VALUE self)
{
    rb_shape_t* shape;

    shape = rb_shape_get_shape_by_id(NUM2INT(rb_struct_getmember(self, rb_intern("id"))));

    VALUE hash = rb_hash_new();

    if (shape->edges) {
        if (SINGLE_CHILD_P(shape->edges)) {
            rb_shape_t * child = SINGLE_CHILD(shape->edges);
            rb_edges_to_hash(child->edge_name, (VALUE)child, &hash);
        }
        else {
            rb_id_table_foreach(shape->edges, rb_edges_to_hash, &hash);
        }
    }

    return hash;
}

static VALUE
rb_shape_edge_name(rb_shape_t * shape)
{
    if (shape->edge_name) {
        if (is_instance_id(shape->edge_name)) {
            return ID2SYM(shape->edge_name);
        }
        return INT2NUM(shape->capacity);
    }
    return Qnil;
}

/* :nodoc: */
static VALUE
rb_shape_export_depth(VALUE self)
{
    rb_shape_t* shape;
    shape = rb_shape_get_shape_by_id(NUM2INT(rb_struct_getmember(self, rb_intern("id"))));
    return SIZET2NUM(rb_shape_depth(shape));
}

/* :nodoc: */
static VALUE
rb_shape_parent(VALUE self)
{
    rb_shape_t * shape;
    shape = rb_shape_get_shape_by_id(NUM2INT(rb_struct_getmember(self, rb_intern("id"))));
    if (shape->parent_id != INVALID_SHAPE_ID) {
        return rb_shape_t_to_rb_cShape(rb_shape_get_parent(shape));
    }
    else {
        return Qnil;
    }
}

/* :nodoc: */
static VALUE
rb_shape_debug_shape(VALUE self, VALUE obj)
{
    return rb_shape_t_to_rb_cShape(rb_shape_get_shape(obj));
}

/* :nodoc: */
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
    if (SINGLE_CHILD_P(edges)) {
        rb_shape_t * child = SINGLE_CHILD(edges);
        collect_keys_and_values(child->edge_name, (VALUE)child, &hash);
    }
    else {
        rb_id_table_foreach(edges, collect_keys_and_values, &hash);
    }
    return hash;
}

/* :nodoc: */
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

/* :nodoc: */
static VALUE
shape_transition_tree(VALUE self)
{
    return rb_obj_shape(rb_shape_get_root_shape());
}

/* :nodoc: */
static VALUE
rb_shape_find_by_id(VALUE mod, VALUE id)
{
    shape_id_t shape_id = NUM2UINT(id);
    if (shape_id >= GET_SHAPE_TREE()->next_shape_id) {
        rb_raise(rb_eArgError, "Shape ID %d is out of bounds\n", shape_id);
    }
    return rb_shape_t_to_rb_cShape(rb_shape_get_shape_by_id(shape_id));
}
#endif

#ifdef HAVE_MMAP
#include <sys/mman.h>
#endif

void
Init_default_shapes(void)
{
    rb_shape_tree_t *st = ruby_mimmalloc(sizeof(rb_shape_tree_t));
    memset(st, 0, sizeof(rb_shape_tree_t));
    rb_shape_tree_ptr = st;

#ifdef HAVE_MMAP
    rb_shape_tree_ptr->shape_list = (rb_shape_t *)mmap(NULL, rb_size_mul_or_raise(SHAPE_BUFFER_SIZE, sizeof(rb_shape_t), rb_eRuntimeError),
                         PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (GET_SHAPE_TREE()->shape_list == MAP_FAILED) {
        GET_SHAPE_TREE()->shape_list = 0;
    }
#else
    GET_SHAPE_TREE()->shape_list = xcalloc(SHAPE_BUFFER_SIZE, sizeof(rb_shape_t));
#endif

    if (!GET_SHAPE_TREE()->shape_list) {
        rb_memerror();
    }

    id_frozen = rb_make_internal_id();
    id_t_object = rb_make_internal_id();

    // Shapes by size pool
    for (int i = 0; i < SIZE_POOL_COUNT; i++) {
        size_pool_edge_names[i] = rb_make_internal_id();
    }

    // Root shape
    rb_shape_t * root = rb_shape_alloc_with_parent_id(0, INVALID_SHAPE_ID);
    root->capacity = (uint32_t)((rb_size_pool_slot_size(0) - offsetof(struct RObject, as.ary)) / sizeof(VALUE));
    root->type = SHAPE_ROOT;
    root->size_pool_index = 0;
    GET_SHAPE_TREE()->root_shape = root;
    RUBY_ASSERT(rb_shape_id(GET_SHAPE_TREE()->root_shape) == ROOT_SHAPE_ID);

    // Shapes by size pool
    for (int i = 1; i < SIZE_POOL_COUNT; i++) {
        uint32_t capa = (uint32_t)((rb_size_pool_slot_size(i) - offsetof(struct RObject, as.ary)) / sizeof(VALUE));
        rb_shape_t * new_shape = rb_shape_transition_shape_capa(root, capa);
        new_shape->type = SHAPE_INITIAL_CAPACITY;
        new_shape->size_pool_index = i;
        RUBY_ASSERT(rb_shape_id(new_shape) == (shape_id_t)i);
    }

    // Make shapes for T_OBJECT
    for (int i = 0; i < SIZE_POOL_COUNT; i++) {
        rb_shape_t * shape = rb_shape_get_shape_by_id(i);
        bool dont_care;
        rb_shape_t * t_object_shape =
            get_next_shape_internal(shape, id_t_object, SHAPE_T_OBJECT, &dont_care, true, false);
        t_object_shape->edges = rb_id_table_create(0);
        RUBY_ASSERT(rb_shape_id(t_object_shape) == (shape_id_t)(i + SIZE_POOL_COUNT));
    }

    bool dont_care;
    // Special const shape
#if RUBY_DEBUG
    rb_shape_t * special_const_shape =
#endif
        get_next_shape_internal(root, (ID)id_frozen, SHAPE_FROZEN, &dont_care, true, false);
    RUBY_ASSERT(rb_shape_id(special_const_shape) == SPECIAL_CONST_SHAPE_ID);
    RUBY_ASSERT(SPECIAL_CONST_SHAPE_ID == (GET_SHAPE_TREE()->next_shape_id - 1));
    RUBY_ASSERT(rb_shape_frozen_shape_p(special_const_shape));

    rb_shape_t * hash_fallback_shape = rb_shape_alloc_with_parent_id(0, ROOT_SHAPE_ID);
    hash_fallback_shape->type = SHAPE_OBJ_TOO_COMPLEX;
    hash_fallback_shape->size_pool_index = 0;
    RUBY_ASSERT(OBJ_TOO_COMPLEX_SHAPE_ID == (GET_SHAPE_TREE()->next_shape_id - 1));
    RUBY_ASSERT(rb_shape_id(hash_fallback_shape) == OBJ_TOO_COMPLEX_SHAPE_ID);
}

void
Init_shape(void)
{
#if SHAPE_DEBUG
    VALUE rb_cShape = rb_struct_define_under(rb_cRubyVM, "Shape",
            "id",
            "parent_id",
            "edge_name",
            "next_iv_index",
            "size_pool_index",
            "type",
            "capacity",
            NULL);

    rb_define_method(rb_cShape, "parent", rb_shape_parent, 0);
    rb_define_method(rb_cShape, "edges", rb_shape_edges, 0);
    rb_define_method(rb_cShape, "depth", rb_shape_export_depth, 0);
    rb_define_method(rb_cShape, "too_complex?", rb_shape_too_complex, 0);
    rb_define_const(rb_cShape, "SHAPE_ROOT", INT2NUM(SHAPE_ROOT));
    rb_define_const(rb_cShape, "SHAPE_IVAR", INT2NUM(SHAPE_IVAR));
    rb_define_const(rb_cShape, "SHAPE_T_OBJECT", INT2NUM(SHAPE_T_OBJECT));
    rb_define_const(rb_cShape, "SHAPE_FROZEN", INT2NUM(SHAPE_FROZEN));
    rb_define_const(rb_cShape, "SHAPE_ID_NUM_BITS", INT2NUM(SHAPE_ID_NUM_BITS));
    rb_define_const(rb_cShape, "SHAPE_FLAG_SHIFT", INT2NUM(SHAPE_FLAG_SHIFT));
    rb_define_const(rb_cShape, "SPECIAL_CONST_SHAPE_ID", INT2NUM(SPECIAL_CONST_SHAPE_ID));
    rb_define_const(rb_cShape, "OBJ_TOO_COMPLEX_SHAPE_ID", INT2NUM(OBJ_TOO_COMPLEX_SHAPE_ID));
    rb_define_const(rb_cShape, "SHAPE_MAX_VARIATIONS", INT2NUM(SHAPE_MAX_VARIATIONS));
    rb_define_const(rb_cShape, "SHAPE_MAX_NUM_IVS", INT2NUM(SHAPE_MAX_NUM_IVS));

    rb_define_singleton_method(rb_cShape, "transition_tree", shape_transition_tree, 0);
    rb_define_singleton_method(rb_cShape, "find_by_id", rb_shape_find_by_id, 1);
    rb_define_singleton_method(rb_cShape, "of", rb_shape_debug_shape, 1);
    rb_define_singleton_method(rb_cShape, "root_shape", rb_shape_root_shape, 0);
#endif
}
