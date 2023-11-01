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

#ifndef _WIN32
#include <sys/mman.h>
#endif

#ifndef SHAPE_DEBUG
#define SHAPE_DEBUG (VM_CHECK_MODE > 0)
#endif

#if SIZEOF_SHAPE_T == 4
#if RUBY_DEBUG
#define SHAPE_BUFFER_SIZE 0x8000
#else
#define SHAPE_BUFFER_SIZE 0x80000
#endif
#else
#define SHAPE_BUFFER_SIZE 0x8000
#endif

#define REDBLACK_CACHE_SIZE (SHAPE_BUFFER_SIZE * 32)

#define SINGLE_CHILD_TAG 0x1
#define TAG_SINGLE_CHILD(x) (struct rb_id_table *)((uintptr_t)x | SINGLE_CHILD_TAG)
#define SINGLE_CHILD_MASK (~((uintptr_t)SINGLE_CHILD_TAG))
#define SINGLE_CHILD_P(x) (((uintptr_t)x) & SINGLE_CHILD_TAG)
#define SINGLE_CHILD(x) (rb_shape_t *)((uintptr_t)x & SINGLE_CHILD_MASK)
#define ANCESTOR_CACHE_THRESHOLD 10
#define MAX_SHAPE_ID (SHAPE_BUFFER_SIZE - 1)

static ID id_frozen;
static ID id_t_object;
static ID size_pool_edge_names[SIZE_POOL_COUNT];

#define LEAF 0
#define BLACK 0x0
#define RED 0x1

static redblack_node_t *
redblack_left(redblack_node_t * node)
{
    if (node->l == LEAF) {
        return LEAF;
    }
    else {
        RUBY_ASSERT(node->l < GET_SHAPE_TREE()->cache_size);
        redblack_node_t * left = &GET_SHAPE_TREE()->shape_cache[node->l - 1];
        return left;
    }
}

static redblack_node_t *
redblack_right(redblack_node_t * node)
{
    if (node->r == LEAF) {
        return LEAF;
    }
    else {
        RUBY_ASSERT(node->r < GET_SHAPE_TREE()->cache_size);
        redblack_node_t * right = &GET_SHAPE_TREE()->shape_cache[node->r - 1];
        return right;
    }
}

static redblack_node_t *
redblack_find(redblack_node_t * tree, ID key)
{
    if (tree == LEAF) {
        return LEAF;
    }
    else {
        if (tree->key == key) {
            return tree;
        }
        else {
            if (key < tree->key) {
                return redblack_find(redblack_left(tree), key);
            }
            else {
                return redblack_find(redblack_right(tree), key);
            }
        }
    }
}

static inline char
redblack_color(redblack_node_t * node)
{
    return node && ((uintptr_t)node->value & RED);
}

static inline bool
redblack_red_p(redblack_node_t * node)
{
    return redblack_color(node) == RED;
}

static inline rb_shape_t *
redblack_value(redblack_node_t * node)
{
    // Color is stored in the bottom bit of the shape pointer
    // Mask away the bit so we get the actual pointer back
    return (rb_shape_t *)((uintptr_t)node->value & (((uintptr_t)-1) - 1));
}

static redblack_id_t
redblack_id_for(redblack_node_t * node)
{
    RUBY_ASSERT(node || node == LEAF);
    if (node == LEAF) {
        return 0;
    }
    else {
        redblack_node_t * redblack_nodes = GET_SHAPE_TREE()->shape_cache;
        redblack_id_t id = (redblack_id_t)(node - redblack_nodes);
        return id + 1;
    }
}

static redblack_node_t *
redblack_new(char color, ID key, rb_shape_t * value, redblack_node_t * left, redblack_node_t * right)
{
    if (GET_SHAPE_TREE()->cache_size + 1 >= REDBLACK_CACHE_SIZE) {
        // We're out of cache, just quit
        return LEAF;
    }
    redblack_node_t * redblack_nodes = GET_SHAPE_TREE()->shape_cache;
    redblack_node_t * node = &redblack_nodes[(GET_SHAPE_TREE()->cache_size)++];
    node->key = key;
    node->value = (rb_shape_t *)((uintptr_t)value | color);
    node->l = redblack_id_for(left);
    node->r = redblack_id_for(right);
    return node;
}

static redblack_node_t *
redblack_balance(char color, ID key, rb_shape_t * value, redblack_node_t * left, redblack_node_t * right)
{
    if (color == BLACK) {
        ID z, y, x;
        rb_shape_t * z_, * y_, * x_;
        redblack_node_t * a, * b, * c, * d;

        if (redblack_red_p(left) && redblack_red_p(redblack_left(left))) {
            z = key;
            z_ = value;
            d = right;

            y = left->key;
            y_ = redblack_value(left);
            c = redblack_right(left);

            x = redblack_left(left)->key;
            x_ = redblack_value(redblack_left(left));

            a = redblack_left(redblack_left(left));
            b = redblack_right(redblack_left(left));
        }
        else if (redblack_red_p(left) && redblack_red_p(redblack_right(left))) {
            z = key;
            z_ = value;
            d = right;

            x = left->key;
            x_ = redblack_value(left);
            a = redblack_left(left);

            y = redblack_right(left)->key;
            y_ = redblack_value(redblack_right(left));
            b = redblack_left(redblack_right(left));
            c = redblack_right(redblack_right(left));
        }
        else if (redblack_red_p(right) && redblack_red_p(redblack_left(right))) {
            x = key;
            x_ = value;
            a = left;

            z = right->key;
            z_ = redblack_value(right);
            d = redblack_right(right);

            y = redblack_left(right)->key;
            y_ = redblack_value(redblack_left(right));
            b = redblack_left(redblack_left(right));
            c = redblack_right(redblack_left(right));
        }
        else if (redblack_red_p(right) && redblack_red_p(redblack_right(right))) {
            x = key;
            x_ = value;
            a = left;

            y = right->key;
            y_ = redblack_value(right);
            b = redblack_left(right);

            z = redblack_right(right)->key;
            z_ = redblack_value(redblack_right(right));
            c = redblack_left(redblack_right(right));
            d = redblack_right(redblack_right(right));
        }
        else {
            return redblack_new(color, key, value, left, right);
        }
        return redblack_new(
                RED, y, y_,
                redblack_new(BLACK, x, x_, a, b),
                redblack_new(BLACK, z, z_, c, d));
    }

    return redblack_new(color, key, value, left, right);
}

static redblack_node_t *
redblack_insert_aux(redblack_node_t * tree, ID key, rb_shape_t * value)
{
    if (tree == LEAF) {
        return redblack_new(RED, key, value, LEAF, LEAF);
    }
    else {
        if (key < tree->key) {
            return redblack_balance(redblack_color(tree),
                    tree->key,
                    redblack_value(tree),
                    redblack_insert_aux(redblack_left(tree), key, value),
                    redblack_right(tree));
        }
        else {
            if (key > tree->key) {
                return redblack_balance(redblack_color(tree),
                        tree->key,
                        redblack_value(tree),
                        redblack_left(tree),
                        redblack_insert_aux(redblack_right(tree), key, value));
            }
            else {
                return tree;
            }
        }
    }
}

static redblack_node_t *
redblack_force_black(redblack_node_t * node)
{
    node->value = redblack_value(node);
    return node;
}

static redblack_node_t *
redblack_insert(redblack_node_t * tree, ID key, rb_shape_t * value)
{
    redblack_node_t * root = redblack_insert_aux(tree, key, value);

    if (redblack_red_p(root)) {
        return redblack_force_black(root);
    }
    else {
        return root;
    }
}

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

    if (shape_id == (MAX_SHAPE_ID + 1)) {
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

#ifdef HAVE_MMAP
static redblack_node_t *
redblack_cache_ancestors(rb_shape_t * shape)
{
    if (!(shape->ancestor_index || shape->parent_id == INVALID_SHAPE_ID)) {
        redblack_node_t * parent_index;

        parent_index = redblack_cache_ancestors(rb_shape_get_parent(shape));

        if (shape->type == SHAPE_IVAR) {
            shape->ancestor_index = redblack_insert(parent_index, shape->edge_name, shape);
        }
        else {
            shape->ancestor_index = parent_index;
        }
    }

    return shape->ancestor_index;
}
#else
static redblack_node_t *
redblack_cache_ancestors(rb_shape_t * shape)
{
    return LEAF;
}
#endif

static rb_shape_t *
rb_shape_alloc_new_child(ID id, rb_shape_t * shape, enum shape_type shape_type)
{
    rb_shape_t * new_shape = rb_shape_alloc(id, shape, shape_type);

    switch (shape_type) {
      case SHAPE_IVAR:
        new_shape->next_iv_index = shape->next_iv_index + 1;
        if (new_shape->next_iv_index > ANCESTOR_CACHE_THRESHOLD) {
            redblack_cache_ancestors(new_shape);
        }
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
get_next_shape_internal(rb_shape_t * shape, ID id, enum shape_type shape_type, bool * variation_created, bool new_variations_allowed)
{
    rb_shape_t *res = NULL;

    // There should never be outgoing edges from "too complex"
    RUBY_ASSERT(rb_shape_id(shape) != OBJ_TOO_COMPLEX_SHAPE_ID);

    *variation_created = false;

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
            }
            else {
                // If it has more than one child, do a hash lookup to find it.
                VALUE lookup_result;
                if (rb_id_table_lookup(shape->edges, id, &lookup_result)) {
                    res = (rb_shape_t *)lookup_result;
                }
            }
        }

        // If we didn't find the shape we're looking for we create it.
        if (!res) {
            // If we're not allowed to create a new variation, of if we're out of shapes
            // we return TOO_COMPLEX_SHAPE.
            if (!new_variations_allowed || GET_SHAPE_TREE()->next_shape_id > MAX_SHAPE_ID) {
                res = rb_shape_get_shape_by_id(OBJ_TOO_COMPLEX_SHAPE_ID);
            }
            else {
                rb_shape_t * new_shape = rb_shape_alloc_new_child(id, shape, shape_type);

                if (!shape->edges) {
                    // If the shape had no edge yet, we can directly set the new child
                    shape->edges = TAG_SINGLE_CHILD(new_shape);
                }
                else {
                    // If the edge was single child we need to allocate a table.
                    if (SINGLE_CHILD_P(shape->edges)) {
                        rb_shape_t * old_child = SINGLE_CHILD(shape->edges);
                        shape->edges = rb_id_table_create(2);
                        rb_id_table_insert(shape->edges, old_child->edge_name, (VALUE)old_child);
                    }

                    rb_id_table_insert(shape->edges, new_shape->edge_name, (VALUE)new_shape);
                    *variation_created = true;
                }

                res = new_shape;
            }
        }
    }
    RB_VM_LOCK_LEAVE();

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
        ivtbl->as.shape.ivptr[to] = ivtbl->as.shape.ivptr[from];
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
                *removed = ivtbl->as.shape.ivptr[index];
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
                rb_shape_t * new_child = get_next_shape_internal(new_parent, shape->edge_name, shape->type, &dont_care, true);
                if (UNLIKELY(new_parent->type == SHAPE_OBJ_TOO_COMPLEX)) {
                    return new_parent;
                }

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

bool
rb_shape_transition_shape_remove_ivar(VALUE obj, ID id, rb_shape_t *shape, VALUE * removed)
{
    if (UNLIKELY(shape->type == SHAPE_OBJ_TOO_COMPLEX)) {
        return false;
    }

    rb_shape_t * new_shape = remove_shape_recursive(obj, id, shape, removed);
    if (new_shape) {
        if (UNLIKELY(new_shape->type == SHAPE_OBJ_TOO_COMPLEX)) {
            return false;
        }

        rb_shape_set_shape(obj, new_shape);
    }
    return true;
}

rb_shape_t *
rb_shape_transition_shape_frozen(VALUE obj)
{
    rb_shape_t* shape = rb_shape_get_shape(obj);
    RUBY_ASSERT(shape);
    RUBY_ASSERT(RB_OBJ_FROZEN(obj));

    if (rb_shape_frozen_shape_p(shape) || rb_shape_obj_too_complex(obj)) {
        return shape;
    }

    rb_shape_t* next_shape;

    if (shape == rb_shape_get_root_shape()) {
        return rb_shape_get_shape_by_id(SPECIAL_CONST_SHAPE_ID);
    }

    bool dont_care;
    next_shape = get_next_shape_internal(shape, (ID)id_frozen, SHAPE_FROZEN, &dont_care, true);

    RUBY_ASSERT(next_shape);
    return next_shape;
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
    return get_next_shape_internal(shape, id, SHAPE_IVAR, &dont_care, true);
}

rb_shape_t *
rb_shape_get_next(rb_shape_t* shape, VALUE obj, ID id)
{
    RUBY_ASSERT(!is_instance_id(id) || RTEST(rb_sym2str(ID2SYM(id))));
    RUBY_ASSERT(shape->type != SHAPE_OBJ_TOO_COMPLEX);

    bool allow_new_shape = true;

    if (BUILTIN_TYPE(obj) == T_OBJECT) {
        VALUE klass = rb_obj_class(obj);
        allow_new_shape = RCLASS_EXT(klass)->variation_count < SHAPE_MAX_VARIATIONS;
    }

    bool variation_created = false;
    rb_shape_t * new_shape = get_next_shape_internal(shape, id, SHAPE_IVAR, &variation_created, allow_new_shape);

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

static inline rb_shape_t *
rb_shape_transition_shape_capa_create(rb_shape_t* shape, size_t new_capacity)
{
    RUBY_ASSERT(new_capacity < (size_t)MAX_IVARS);

    ID edge_name = rb_make_temporary_id(new_capacity);
    bool dont_care;
    rb_shape_t * new_shape = get_next_shape_internal(shape, edge_name, SHAPE_CAPACITY_CHANGE, &dont_care, true);
    if (rb_shape_id(new_shape) != OBJ_TOO_COMPLEX_SHAPE_ID) {
        new_shape->capacity = (uint32_t)new_capacity;
    }
    return new_shape;
}

rb_shape_t *
rb_shape_transition_shape_capa(rb_shape_t* shape)
{
    return rb_shape_transition_shape_capa_create(shape, rb_malloc_grow_capa(shape->capacity, sizeof(VALUE)));
}

bool
rb_shape_get_iv_index(rb_shape_t * shape, ID id, attr_index_t *value)
{
    // It doesn't make sense to ask for the index of an IV that's stored
    // on an object that is "too complex" as it uses a hash for storing IVs
    RUBY_ASSERT(rb_shape_id(shape) != OBJ_TOO_COMPLEX_SHAPE_ID);

    while (shape->parent_id != INVALID_SHAPE_ID) {
        // Try the ancestor cache if it's available
        if (shape->ancestor_index && shape->next_iv_index >= ANCESTOR_CACHE_THRESHOLD) {
            redblack_node_t * node = redblack_find(shape->ancestor_index, id);
            if (node) {
                rb_shape_t * shape = redblack_value(node);
                *value = shape->next_iv_index - 1;
                return true;
            }
            else {
                return false;
            }
        }
        else {
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
    RUBY_ASSERT(rb_shape_id(initial_shape) != OBJ_TOO_COMPLEX_SHAPE_ID);
    RUBY_ASSERT(rb_shape_id(dest_shape) != OBJ_TOO_COMPLEX_SHAPE_ID);

    rb_shape_t * midway_shape;

    RUBY_ASSERT(initial_shape->type == SHAPE_T_OBJECT);

    if (dest_shape->type != initial_shape->type) {
        midway_shape = rb_shape_rebuild_shape(initial_shape, rb_shape_get_parent(dest_shape));
        if (UNLIKELY(rb_shape_id(midway_shape) == OBJ_TOO_COMPLEX_SHAPE_ID)) {
            return midway_shape;
        }
    }
    else {
        midway_shape = initial_shape;
    }

    switch ((enum shape_type)dest_shape->type) {
      case SHAPE_IVAR:
        if (midway_shape->capacity <= midway_shape->next_iv_index) {
            // There isn't enough room to write this IV, so we need to increase the capacity
            midway_shape = rb_shape_transition_shape_capa(midway_shape);
        }

        if (LIKELY(rb_shape_id(midway_shape) != OBJ_TOO_COMPLEX_SHAPE_ID)) {
            midway_shape = rb_shape_get_next_iv_shape(midway_shape, dest_shape->edge_name);
        }
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

/* :nodoc: */
static VALUE
rb_shape_shapes_available(VALUE self)
{
    return INT2NUM(MAX_SHAPE_ID - (GET_SHAPE_TREE()->next_shape_id - 1));
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

#ifdef HAVE_MMAP
    rb_shape_tree_ptr->shape_cache = (redblack_node_t *)mmap(NULL, rb_size_mul_or_raise(REDBLACK_CACHE_SIZE, sizeof(redblack_node_t), rb_eRuntimeError),
                         PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    rb_shape_tree_ptr->cache_size = 0;
#endif

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
        size_t capa = ((rb_size_pool_slot_size(i) - offsetof(struct RObject, as.ary)) / sizeof(VALUE));
        rb_shape_t * new_shape = rb_shape_transition_shape_capa_create(root, capa);
        new_shape->type = SHAPE_INITIAL_CAPACITY;
        new_shape->size_pool_index = i;
        new_shape->ancestor_index = LEAF;
        RUBY_ASSERT(rb_shape_id(new_shape) == (shape_id_t)i);
    }

    // Make shapes for T_OBJECT
    for (int i = 0; i < SIZE_POOL_COUNT; i++) {
        rb_shape_t * shape = rb_shape_get_shape_by_id(i);
        bool dont_care;
        rb_shape_t * t_object_shape =
            get_next_shape_internal(shape, id_t_object, SHAPE_T_OBJECT, &dont_care, true);
        t_object_shape->edges = rb_id_table_create(0);
        t_object_shape->ancestor_index = LEAF;
        RUBY_ASSERT(rb_shape_id(t_object_shape) == (shape_id_t)(i + SIZE_POOL_COUNT));
    }

    bool dont_care;
    // Special const shape
#if RUBY_DEBUG
    rb_shape_t * special_const_shape =
#endif
        get_next_shape_internal(root, (ID)id_frozen, SHAPE_FROZEN, &dont_care, true);
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
    rb_define_const(rb_cShape, "SIZEOF_RB_SHAPE_T", INT2NUM(sizeof(rb_shape_t)));
    rb_define_const(rb_cShape, "SIZEOF_REDBLACK_NODE_T", INT2NUM(sizeof(redblack_node_t)));
    rb_define_const(rb_cShape, "SHAPE_BUFFER_SIZE", INT2NUM(sizeof(rb_shape_t) * SHAPE_BUFFER_SIZE));
    rb_define_const(rb_cShape, "REDBLACK_CACHE_SIZE", INT2NUM(sizeof(redblack_node_t) * REDBLACK_CACHE_SIZE));

    rb_define_singleton_method(rb_cShape, "transition_tree", shape_transition_tree, 0);
    rb_define_singleton_method(rb_cShape, "find_by_id", rb_shape_find_by_id, 1);
    rb_define_singleton_method(rb_cShape, "of", rb_shape_debug_shape, 1);
    rb_define_singleton_method(rb_cShape, "root_shape", rb_shape_root_shape, 0);
    rb_define_singleton_method(rb_cShape, "shapes_available", rb_shape_shapes_available, 0);
#endif
}
