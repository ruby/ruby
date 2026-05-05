#include "vm_core.h"
#include "vm_sync.h"
#include "shape.h"
#include "symbol.h"
#include "id_table.h"
#include "internal/class.h"
#include "internal/error.h"
#include "internal/gc.h"
#include "internal/object.h"
#include "internal/symbol.h"
#include "internal/variable.h"
#include "variable.h"
#include <stdbool.h>

#ifndef _WIN32
#include <sys/mman.h>
#endif

#ifndef SHAPE_DEBUG
#define SHAPE_DEBUG (VM_CHECK_MODE > 0)
#endif

#define REDBLACK_CACHE_SIZE (SHAPE_BUFFER_SIZE * 32)

/* This depends on that the allocated memory by Ruby's allocator or
 * mmap is not located at an odd address. */
#define SINGLE_CHILD_TAG 0x1
#define TAG_SINGLE_CHILD(x) (VALUE)((uintptr_t)(x) | SINGLE_CHILD_TAG)
#define SINGLE_CHILD_MASK (~((uintptr_t)SINGLE_CHILD_TAG))
#define SINGLE_CHILD_P(x) ((uintptr_t)(x) & SINGLE_CHILD_TAG)
#define SINGLE_CHILD(x) (rb_shape_t *)((uintptr_t)(x) & SINGLE_CHILD_MASK)
#define ANCESTOR_CACHE_THRESHOLD 10
#define MAX_SHAPE_ID (SHAPE_BUFFER_SIZE - 1)
#define ANCESTOR_SEARCH_MAX_DEPTH 2

static ID id_object_id;

// Should be on its own cache line
static RUBY_ALIGNAS(128) rb_atomic_t redblack_cache_size;

struct redblack_node {
    ID key;
    rb_shape_t *value;
    redblack_id_t l;
    redblack_id_t r;
};
typedef struct redblack_node redblack_node_t;

static redblack_node_t *redblack_cache;

#define LEAF 0
#define BLACK 0x0
#define RED 0x1

static inline redblack_node_t *
redblack_node(redblack_id_t id)
{
    return id ? &redblack_cache[id - 1] : LEAF;
}

static redblack_node_t *
redblack_left(redblack_node_t *node)
{
    if (node->l == LEAF) {
        return LEAF;
    }
    else {
        RUBY_ASSERT(node->l < redblack_cache_size);
        redblack_node_t *left = redblack_node(node->l);
        return left;
    }
}

static redblack_node_t *
redblack_right(redblack_node_t *node)
{
    if (node->r == LEAF) {
        return LEAF;
    }
    else {
        RUBY_ASSERT(node->r < redblack_cache_size);
        redblack_node_t *right = redblack_node(node->r);
        return right;
    }
}

static redblack_node_t *
redblack_find0(redblack_node_t *tree, ID key)
{
    if (tree == LEAF) {
        return LEAF;
    }
    else {
        RUBY_ASSERT(redblack_left(tree) == LEAF || redblack_left(tree)->key < tree->key);
        RUBY_ASSERT(redblack_right(tree) == LEAF || redblack_right(tree)->key > tree->key);

        if (tree->key == key) {
            return tree;
        }
        else {
            if (key < tree->key) {
                return redblack_find0(redblack_left(tree), key);
            }
            else {
                return redblack_find0(redblack_right(tree), key);
            }
        }
    }
}

static redblack_node_t *
redblack_find(redblack_id_t tree_id, ID key)
{
    return redblack_find0(redblack_node(tree_id), key);
}

static inline rb_shape_t *
redblack_value(redblack_node_t *node)
{
    // Color is stored in the bottom bit of the shape pointer
    // Mask away the bit so we get the actual pointer back
    return (rb_shape_t *)((uintptr_t)node->value & ~(uintptr_t)1);
}

#ifdef HAVE_MMAP
static inline char
redblack_color(redblack_node_t *node)
{
    return node && ((uintptr_t)node->value & RED);
}

static inline bool
redblack_red_p(redblack_node_t *node)
{
    return redblack_color(node) == RED;
}

static redblack_id_t
redblack_id_for(redblack_node_t *node)
{
    RUBY_ASSERT(node || node == LEAF);
    if (node == LEAF) {
        return 0;
    }
    else {
        redblack_node_t *redblack_nodes = redblack_cache;
        redblack_id_t id = (redblack_id_t)(node - redblack_nodes);
        return id + 1;
    }
}

static redblack_node_t *
redblack_new(char color, ID key, rb_shape_t *value, redblack_node_t *left, redblack_node_t *right)
{
    if (redblack_cache_size + 1 >= REDBLACK_CACHE_SIZE) {
        // We're out of cache, just quit
        return LEAF;
    }

    RUBY_ASSERT(left == LEAF || left->key < key);
    RUBY_ASSERT(right == LEAF || right->key > key);

    redblack_node_t *redblack_nodes = redblack_cache;
    redblack_node_t *node = &redblack_nodes[RUBY_ATOMIC_FETCH_ADD(redblack_cache_size, 1)];
    node->key = key;
    node->value = (rb_shape_t *)((uintptr_t)value | color);
    node->l = redblack_id_for(left);
    node->r = redblack_id_for(right);
    return node;
}

static redblack_node_t *
redblack_balance(char color, ID key, rb_shape_t *value, redblack_node_t *left, redblack_node_t *right)
{
    if (color == BLACK) {
        ID new_key, new_left_key, new_right_key;
        rb_shape_t *new_value, *new_left_value, *new_right_value;
        redblack_node_t *new_left_left, *new_left_right, *new_right_left, *new_right_right;

        if (redblack_red_p(left) && redblack_red_p(redblack_left(left))) {
            new_right_key = key;
            new_right_value = value;
            new_right_right = right;

            new_key = left->key;
            new_value = redblack_value(left);
            new_right_left = redblack_right(left);

            new_left_key = redblack_left(left)->key;
            new_left_value = redblack_value(redblack_left(left));

            new_left_left = redblack_left(redblack_left(left));
            new_left_right = redblack_right(redblack_left(left));
        }
        else if (redblack_red_p(left) && redblack_red_p(redblack_right(left))) {
            new_right_key = key;
            new_right_value = value;
            new_right_right = right;

            new_left_key = left->key;
            new_left_value = redblack_value(left);
            new_left_left = redblack_left(left);

            new_key = redblack_right(left)->key;
            new_value = redblack_value(redblack_right(left));
            new_left_right = redblack_left(redblack_right(left));
            new_right_left = redblack_right(redblack_right(left));
        }
        else if (redblack_red_p(right) && redblack_red_p(redblack_left(right))) {
            new_left_key = key;
            new_left_value = value;
            new_left_left = left;

            new_right_key = right->key;
            new_right_value = redblack_value(right);
            new_right_right = redblack_right(right);

            new_key = redblack_left(right)->key;
            new_value = redblack_value(redblack_left(right));
            new_left_right = redblack_left(redblack_left(right));
            new_right_left = redblack_right(redblack_left(right));
        }
        else if (redblack_red_p(right) && redblack_red_p(redblack_right(right))) {
            new_left_key = key;
            new_left_value = value;
            new_left_left = left;

            new_key = right->key;
            new_value = redblack_value(right);
            new_left_right = redblack_left(right);

            new_right_key = redblack_right(right)->key;
            new_right_value = redblack_value(redblack_right(right));
            new_right_left = redblack_left(redblack_right(right));
            new_right_right = redblack_right(redblack_right(right));
        }
        else {
            return redblack_new(color, key, value, left, right);
        }

        RUBY_ASSERT(new_left_key < new_key);
        RUBY_ASSERT(new_right_key > new_key);
        RUBY_ASSERT(new_left_left == LEAF || new_left_left->key < new_left_key);
        RUBY_ASSERT(new_left_right == LEAF || new_left_right->key > new_left_key);
        RUBY_ASSERT(new_left_right == LEAF || new_left_right->key < new_key);
        RUBY_ASSERT(new_right_left == LEAF || new_right_left->key < new_right_key);
        RUBY_ASSERT(new_right_left == LEAF || new_right_left->key > new_key);
        RUBY_ASSERT(new_right_right == LEAF || new_right_right->key > new_right_key);

        return redblack_new(
                RED, new_key, new_value,
                redblack_new(BLACK, new_left_key, new_left_value, new_left_left, new_left_right),
                redblack_new(BLACK, new_right_key, new_right_value, new_right_left, new_right_right));
    }

    return redblack_new(color, key, value, left, right);
}

static redblack_node_t *
redblack_insert_aux(redblack_node_t *tree, ID key, rb_shape_t *value)
{
    if (tree == LEAF) {
        return redblack_new(RED, key, value, LEAF, LEAF);
    }
    else {
        redblack_node_t *left, *right;
        if (key < tree->key) {
            left = redblack_insert_aux(redblack_left(tree), key, value);
            RUBY_ASSERT(left != LEAF);
            right = redblack_right(tree);
            RUBY_ASSERT(right == LEAF || right->key > tree->key);
        }
        else if (key > tree->key) {
            left = redblack_left(tree);
            RUBY_ASSERT(left == LEAF || left->key < tree->key);
            right = redblack_insert_aux(redblack_right(tree), key, value);
            RUBY_ASSERT(right != LEAF);
        }
        else {
            return tree;
        }

        return redblack_balance(
            redblack_color(tree),
            tree->key,
            redblack_value(tree),
            left,
            right
        );
    }
}

static redblack_node_t *
redblack_force_black(redblack_node_t *node)
{
    node->value = redblack_value(node);
    return node;
}

static redblack_id_t
redblack_insert(redblack_node_t *tree, ID key, rb_shape_t *value)
{
    redblack_node_t *root = redblack_insert_aux(tree, key, value);

    if (redblack_red_p(root)) {
        return redblack_id_for(redblack_force_black(root));
    }
    else {
        return redblack_id_for(root);
    }
}
#endif

static VALUE shape_tree_obj = Qfalse;
rb_shape_tree_t rb_shape_tree = { 0 };

// Should be on its own cache line
static RUBY_ALIGNAS(128) rb_atomic_t shape_next_id;

rb_shape_t *
rb_shape_get_root_shape(void)
{
    return rb_shape_tree.shape_list;
}

static void
shape_tree_mark_and_move(void *data)
{
    rb_shape_t *cursor = rb_shape_get_root_shape();
    rb_shape_t *end = RSHAPE(shape_next_id - 1);
    while (cursor <= end) {
        if (cursor->edges && !SINGLE_CHILD_P(cursor->edges)) {
            rb_gc_mark_and_move(&cursor->edges);
        }
        cursor++;
    }
}

size_t
rb_shapes_cache_size(void)
{
    return redblack_cache ? redblack_cache_size : 0;
}

size_t
rb_shapes_count(void)
{
    return (size_t)RUBY_ATOMIC_LOAD(shape_next_id);
}

static size_t
shape_tree_memsize(const void *data)
{
    if (redblack_cache) {
        return redblack_cache_size * sizeof(redblack_node_t);
    }
    return 0;
}

static const rb_data_type_t shape_tree_type = {
    .wrap_struct_name = "VM/shape_tree",
    .function = {
        .dmark = shape_tree_mark_and_move,
        .dfree = NULL, // Nothing to free, done at VM exit in rb_shape_free_all,
        .dsize = shape_tree_memsize,
        .dcompact = shape_tree_mark_and_move,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED,
};


/*
 * Shape getters
 */

static inline shape_id_t
SHAPE_OFFSET(rb_shape_t *shape)
{
    RUBY_ASSERT(shape);
    return (shape_id_t)(shape - rb_shape_tree.shape_list);
}

static inline shape_id_t
SHAPE_ID(rb_shape_t *shape, shape_id_t previous_shape_id)
{
    RUBY_ASSERT(shape);
    shape_id_t offset = (shape_id_t)(shape - rb_shape_tree.shape_list);
    return offset | RSHAPE_FLAGS(previous_shape_id);
}

void
rb_shape_each_shape_id(each_shape_callback callback, void *data)
{
    rb_shape_t *start = rb_shape_get_root_shape();
    rb_shape_t *cursor = start;
    rb_shape_t *end = RSHAPE(RUBY_ATOMIC_LOAD(shape_next_id));
    while (cursor < end) {
        callback((shape_id_t)(cursor - start), data);
        cursor += 1;
    }
}

RUBY_FUNC_EXPORTED shape_id_t
rb_obj_shape_id(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        rb_bug("rb_obj_shape_id: called on a special constant");
    }

    if (BUILTIN_TYPE(obj) == T_CLASS || BUILTIN_TYPE(obj) == T_MODULE) {
        VALUE fields_obj = RCLASS_WRITABLE_FIELDS_OBJ(obj);
        if (fields_obj) {
            return RBASIC_SHAPE_ID(fields_obj);
        }
        return ROOT_SHAPE_ID;
    }
    return RBASIC_SHAPE_ID(obj);
}

size_t
rb_shape_depth(shape_id_t shape_id)
{
    size_t depth = 1;
    rb_shape_t *shape = RSHAPE(shape_id);

    while (shape->parent_offset != INVALID_SHAPE_ID) {
        depth++;
        shape = RSHAPE(shape->parent_offset);
    }

    return depth;
}

static rb_shape_t *
shape_alloc(void)
{
    shape_id_t current, new_id;

    do {
        current = RUBY_ATOMIC_LOAD(shape_next_id);
        if (current > MAX_SHAPE_ID) {
            return NULL;  // Out of shapes
        }
        new_id = current + 1;
    } while (current != RUBY_ATOMIC_CAS(shape_next_id, current, new_id));

    return &rb_shape_tree.shape_list[current];
}

static rb_shape_t *
rb_shape_alloc_with_parent_offset(ID edge_name, shape_id_t parent_offset)
{
    rb_shape_t *shape = shape_alloc();
    if (!shape) return NULL;

    shape->edge_name = edge_name;
    shape->next_field_index = 0;
    shape->parent_offset = parent_offset;
    shape->edges = 0;

    return shape;
}

static rb_shape_t *
rb_shape_alloc(ID edge_name, rb_shape_t *parent, enum shape_type type)
{
    rb_shape_t *shape = rb_shape_alloc_with_parent_offset(edge_name, SHAPE_OFFSET(parent));
    if (!shape) return NULL;

    shape->type = (uint8_t)type;
    shape->capacity = parent->capacity;
    shape->edges = 0;
    return shape;
}

#ifdef HAVE_MMAP
static redblack_node_t *
redblack_cache_ancestors(rb_shape_t *shape)
{
    if (!(shape->ancestor_index || shape->parent_offset == INVALID_SHAPE_ID)) {
        redblack_node_t *parent_index_node = redblack_cache_ancestors(RSHAPE(shape->parent_offset));

        if (shape->type == SHAPE_IVAR) {
            shape->ancestor_index = redblack_insert(parent_index_node, shape->edge_name, shape);

#if RUBY_DEBUG
            if (shape->ancestor_index) {
                redblack_node_t *inserted_node = redblack_find(shape->ancestor_index, shape->edge_name);
                RUBY_ASSERT(inserted_node);
                RUBY_ASSERT(redblack_value(inserted_node) == shape);
            }
#endif
        }
        else {
            shape->ancestor_index = redblack_id_for(parent_index_node);
        }
    }

    return redblack_node(shape->ancestor_index);
}
#else
static redblack_node_t *
redblack_cache_ancestors(rb_shape_t *shape)
{
    return LEAF;
}
#endif

static attr_index_t
shape_grow_capa(attr_index_t current_capa)
{
    const attr_index_t *capacities = rb_shape_tree.capacities;
    size_t heaps_count = rb_shape_tree.heaps_count;

    // First try to use the next size that will be embeddable in a larger object slot.
    for (size_t i = 0; i < heaps_count; i++) {
        attr_index_t capa = capacities[i];
        if (capa > current_capa) {
            return capa;
        }
    }

    return (attr_index_t)rb_malloc_grow_capa(current_capa, sizeof(VALUE));
}

static rb_shape_t *
rb_shape_alloc_new_child(ID id, rb_shape_t *shape, enum shape_type shape_type)
{
    rb_shape_t *new_shape = rb_shape_alloc(id, shape, shape_type);
    if (!new_shape) return NULL;

    switch (shape_type) {
      case SHAPE_OBJ_ID:
      case SHAPE_IVAR:
        if (UNLIKELY(shape->next_field_index >= shape->capacity)) {
            RUBY_ASSERT(shape->next_field_index == shape->capacity);
            new_shape->capacity = shape_grow_capa(shape->capacity);
        }
        RUBY_ASSERT(new_shape->capacity > shape->next_field_index);
        new_shape->next_field_index = shape->next_field_index + 1;
        if (new_shape->next_field_index > ANCESTOR_CACHE_THRESHOLD) {
            RB_VM_LOCKING() {
                redblack_cache_ancestors(new_shape);
            }
        }
        break;
      case SHAPE_ROOT:
        rb_bug("Unreachable");
        break;
    }

    return new_shape;
}

static rb_shape_t *
get_next_shape_internal_atomic(rb_shape_t *shape, ID id, enum shape_type shape_type, bool *variation_created, bool new_variations_allowed)
{
    rb_shape_t *res = NULL;

    *variation_created = false;
    VALUE edges_table;

retry:
    edges_table = RUBY_ATOMIC_VALUE_LOAD(shape->edges);

    // If the current shape has children
    if (edges_table) {
        // Check if it only has one child
        if (SINGLE_CHILD_P(edges_table)) {
            rb_shape_t *child = SINGLE_CHILD(edges_table);
            // If the one child has a matching edge name, then great,
            // we found what we want.
            if (child->edge_name == id) {
                res = child;
            }
        }
        else {
            // If it has more than one child, do a hash lookup to find it.
            VALUE lookup_result;
            if (rb_managed_id_table_lookup(edges_table, id, &lookup_result)) {
                res = (rb_shape_t *)lookup_result;
            }
        }
    }

    // If we didn't find the shape we're looking for and we're allowed more variations we create it.
    if (!res && new_variations_allowed) {
        VALUE new_edges = 0;

        rb_shape_t *new_shape = rb_shape_alloc_new_child(id, shape, shape_type);

        // If we're out of shapes, return NULL
        if (new_shape) {
            if (!edges_table) {
                // If the shape had no edge yet, we can directly set the new child
                new_edges = TAG_SINGLE_CHILD(new_shape);
            }
            else {
                // If the edge was single child we need to allocate a table.
                if (SINGLE_CHILD_P(edges_table)) {
                    rb_shape_t *old_child = SINGLE_CHILD(edges_table);
                    new_edges = rb_managed_id_table_new(2);
                    rb_managed_id_table_insert(new_edges, old_child->edge_name, (VALUE)old_child);
                }
                else {
                    new_edges = rb_managed_id_table_dup(edges_table);
                }

                rb_managed_id_table_insert(new_edges, new_shape->edge_name, (VALUE)new_shape);
                *variation_created = true;
            }

            if (edges_table != RUBY_ATOMIC_VALUE_CAS(shape->edges, edges_table, new_edges)) {
                // Another thread updated the table;
                goto retry;
            }
            RB_OBJ_WRITTEN(shape_tree_obj, Qundef, new_edges);
            res = new_shape;
            RB_GC_GUARD(new_edges);
        }
    }

    return res;
}

static rb_shape_t *
get_next_shape_internal(rb_shape_t *shape, ID id, enum shape_type shape_type, bool *variation_created, bool new_variations_allowed)
{
    if (rb_multi_ractor_p()) {
        return get_next_shape_internal_atomic(shape, id, shape_type, variation_created, new_variations_allowed);
    }

    rb_shape_t *res = NULL;
    *variation_created = false;

    VALUE edges_table = shape->edges;

    // If the current shape has children
    if (edges_table) {
        // Check if it only has one child
        if (SINGLE_CHILD_P(edges_table)) {
            rb_shape_t *child = SINGLE_CHILD(edges_table);
            // If the one child has a matching edge name, then great,
            // we found what we want.
            if (child->edge_name == id) {
                res = child;
            }
        }
        else {
            // If it has more than one child, do a hash lookup to find it.
            VALUE lookup_result;
            if (rb_managed_id_table_lookup(edges_table, id, &lookup_result)) {
                res = (rb_shape_t *)lookup_result;
            }
        }
    }

    // If we didn't find the shape we're looking for we create it.
    if (!res) {
        // If we're not allowed to create a new variation, of if we're out of shapes
        // we return TOO_COMPLEX_SHAPE.
        if (!new_variations_allowed || rb_shapes_count() > MAX_SHAPE_ID) {
            res = NULL;
        }
        else {
            rb_shape_t *new_shape = rb_shape_alloc_new_child(id, shape, shape_type);

            if (!edges_table) {
                // If the shape had no edge yet, we can directly set the new child
                shape->edges = TAG_SINGLE_CHILD(new_shape);
            }
            else {
                // If the edge was single child we need to allocate a table.
                if (SINGLE_CHILD_P(edges_table)) {
                    rb_shape_t *old_child = SINGLE_CHILD(edges_table);
                    VALUE new_edges = rb_managed_id_table_new(2);
                    rb_managed_id_table_insert(new_edges, old_child->edge_name, (VALUE)old_child);
                    RB_OBJ_WRITE(shape_tree_obj, &shape->edges, new_edges);
                }

                rb_managed_id_table_insert(shape->edges, new_shape->edge_name, (VALUE)new_shape);
                *variation_created = true;
            }

            res = new_shape;
        }
    }

    return res;
}

shape_id_t
rb_shape_transition_object_id(shape_id_t original_shape_id)
{
    RUBY_ASSERT(!rb_shape_has_object_id(original_shape_id));

    bool dont_care;
    rb_shape_t *shape = get_next_shape_internal(RSHAPE(original_shape_id), id_object_id, SHAPE_OBJ_ID, &dont_care, true);
    if (!shape) {
        return ROOT_TOO_COMPLEX_WITH_OBJ_ID | RSHAPE_FLAGS(original_shape_id);
    }

    RUBY_ASSERT(shape);
    return SHAPE_ID(shape, original_shape_id) | SHAPE_ID_FL_HAS_OBJECT_ID;
}

shape_id_t
rb_shape_object_id(shape_id_t original_shape_id)
{
    RUBY_ASSERT(rb_shape_has_object_id(original_shape_id));

    rb_shape_t *shape = RSHAPE(original_shape_id);
    while (shape->type != SHAPE_OBJ_ID) {
        if (UNLIKELY(shape->parent_offset == INVALID_SHAPE_ID)) {
            rb_bug("Missing object_id in shape tree");
        }
        shape = RSHAPE(shape->parent_offset);
    }

    return SHAPE_ID(shape, original_shape_id) | SHAPE_ID_FL_HAS_OBJECT_ID;
}

/*
 * This function is used for assertions where we don't want to increment
 * max_iv_count
 */
static inline rb_shape_t *
shape_get_next_iv_shape(rb_shape_t *shape, ID id)
{
    RUBY_ASSERT(!is_instance_id(id) || RTEST(rb_sym2str(ID2SYM(id))));
    bool dont_care;
    return get_next_shape_internal(shape, id, SHAPE_IVAR, &dont_care, true);
}

shape_id_t
rb_shape_get_next_iv_shape(shape_id_t shape_id, ID id)
{
    rb_shape_t *shape = RSHAPE(shape_id);
    rb_shape_t *next_shape = shape_get_next_iv_shape(shape, id);
    if (!next_shape) {
        return INVALID_SHAPE_ID;
    }
    return SHAPE_OFFSET(next_shape);
}

static bool
shape_get_iv_index(rb_shape_t *shape, ID id, attr_index_t *value)
{
    while (shape->parent_offset != INVALID_SHAPE_ID) {
        if (shape->edge_name == id) {
            enum shape_type shape_type;
            shape_type = (enum shape_type)shape->type;

            switch (shape_type) {
              case SHAPE_IVAR:
                RUBY_ASSERT(shape->next_field_index > 0);
                *value = shape->next_field_index - 1;
                return true;
              case SHAPE_ROOT:
                return false;
              case SHAPE_OBJ_ID:
                rb_bug("Ivar should not exist on transition");
            }
        }

        shape = RSHAPE(shape->parent_offset);
    }

    return false;
}

static inline rb_shape_t *
shape_get_next(rb_shape_t *shape, enum shape_type shape_type, VALUE klass, ID id, bool emit_warnings)
{
    RUBY_ASSERT(!is_instance_id(id) || RTEST(rb_sym2str(ID2SYM(id))));

#if RUBY_DEBUG
    attr_index_t index;
    if (shape_get_iv_index(shape, id, &index)) {
        rb_bug("rb_shape_get_next: trying to create ivar that already exists at index %u", index);
    }
#endif

    bool allow_new_shape = RCLASS_VARIATION_COUNT(klass) < SHAPE_MAX_VARIATIONS;
    bool variation_created = false;
    rb_shape_t *new_shape = get_next_shape_internal(shape, id, shape_type, &variation_created, allow_new_shape);

    if (!new_shape) {
        // We could create a new variation, transitioning to TOO_COMPLEX.
        return NULL;
    }

    // Check if we should update max_iv_count on the object's class
    if (new_shape->next_field_index > RCLASS_MAX_IV_COUNT(klass) && !RCLASS_EXPECT_NO_IVAR(klass)) {
        RCLASS_SET_MAX_IV_COUNT(klass, new_shape->next_field_index);
    }

    if (variation_created) {
        RCLASS_VARIATION_COUNT(klass)++;

        if (emit_warnings && rb_warning_category_enabled_p(RB_WARN_CATEGORY_PERFORMANCE)) {
            if (RCLASS_VARIATION_COUNT(klass) >= SHAPE_MAX_VARIATIONS) {
                rb_category_warn(
                    RB_WARN_CATEGORY_PERFORMANCE,
                    "The class %"PRIsVALUE" reached %d shape variations, instance variables accesses will be slower and memory usage increased.\n"
                    "It is recommended to define instance variables in a consistent order, for instance by eagerly defining them all in the #initialize method.",
                    rb_class_path(klass),
                    SHAPE_MAX_VARIATIONS
                );
            }
        }
    }

    return new_shape;
}

static VALUE
obj_get_owner_class(VALUE obj)
{
    VALUE klass;
    if (IMEMO_TYPE_P(obj, imemo_fields)) {
        VALUE owner = rb_imemo_fields_owner(obj);
        switch (BUILTIN_TYPE(owner)) {
          case T_CLASS:
          case T_MODULE:
            klass = rb_singleton_class(owner);
            break;
          default:
            klass = rb_obj_class(owner);
            break;
        }
    }
    else {
        klass = rb_obj_class(obj);
    }
    return klass;
}

static rb_shape_t *
remove_shape_recursive(VALUE obj, rb_shape_t *shape, ID id, rb_shape_t **removed_shape)
{
    if (shape->parent_offset == INVALID_SHAPE_ID) {
        // We've hit the top of the shape tree and couldn't find the
        // IV we wanted to remove, so return NULL
        *removed_shape = NULL;
        return NULL;
    }
    else {
        if (shape->type == SHAPE_IVAR && shape->edge_name == id) {
            *removed_shape = shape;

            return RSHAPE(shape->parent_offset);
        }
        else {
            // This isn't the IV we want to remove, keep walking up.
            rb_shape_t *new_parent = remove_shape_recursive(obj, RSHAPE(shape->parent_offset), id, removed_shape);

            // We found a new parent.  Create a child of the new parent that
            // has the same attributes as this shape.
            if (new_parent) {
                VALUE klass = obj_get_owner_class(obj);
                rb_shape_t *new_child = shape_get_next(new_parent, shape->type, klass, shape->edge_name, true);
                RUBY_ASSERT(!new_child || new_child->capacity <= shape->capacity);
                return new_child;
            }
            else {
                // We went all the way to the top of the shape tree and couldn't
                // find an IV to remove so return NULL.
                return NULL;
            }
        }
    }
}

shape_id_t
rb_obj_shape_transition_remove_ivar(VALUE obj, ID id, shape_id_t *removed_shape_id)
{
    shape_id_t original_shape_id = RBASIC_SHAPE_ID(obj);
    RUBY_ASSERT(!rb_shape_frozen_p(original_shape_id));

    if (rb_shape_too_complex_p(original_shape_id)) {
        return original_shape_id;
    }

    rb_shape_t *removed_shape = NULL;
    rb_shape_t *new_shape = remove_shape_recursive(obj, RSHAPE(original_shape_id), id, &removed_shape);

    if (removed_shape) {
        *removed_shape_id = SHAPE_OFFSET(removed_shape);
    }

    if (new_shape) {
        return SHAPE_ID(new_shape, original_shape_id);
    }
    else if (removed_shape) {
        // We found the shape to remove, but couldn't create a new variation.
        // We must transition to TOO_COMPLEX.
        shape_id_t next_shape_id = rb_shape_transition_complex(original_shape_id);
        RUBY_ASSERT(rb_shape_has_object_id(next_shape_id) == rb_shape_has_object_id(original_shape_id));
        return next_shape_id;
    }
    return original_shape_id;
}

shape_id_t
rb_obj_shape_transition_add_ivar(VALUE obj, ID id)
{
    shape_id_t original_shape_id = RBASIC_SHAPE_ID(obj);
    RUBY_ASSERT(!rb_shape_frozen_p(original_shape_id));

    VALUE klass = obj_get_owner_class(obj);
    rb_shape_t *next_shape = shape_get_next(RSHAPE(original_shape_id), SHAPE_IVAR, klass, id, true);
    if (next_shape) {
        return SHAPE_ID(next_shape, original_shape_id);
    }
    else {
        return rb_shape_transition_complex(original_shape_id);
    }
}

shape_id_t
rb_shape_transition_add_ivar_no_warnings(shape_id_t original_shape_id, ID id, VALUE klass)
{
    RUBY_ASSERT(!rb_shape_frozen_p(original_shape_id));

    rb_shape_t *next_shape = shape_get_next(RSHAPE(original_shape_id), SHAPE_IVAR, klass, id, false);
    if (next_shape) {
        return SHAPE_ID(next_shape, original_shape_id);
    }
    else {
        return rb_shape_transition_complex(original_shape_id);
    }
}

// Same as rb_shape_get_iv_index, but uses a provided valid shape id and index
// to return a result faster if branches of the shape tree are closely related.
bool
rb_shape_get_iv_index_with_hint(shape_id_t shape_id, ID id, attr_index_t *value, shape_id_t *shape_id_hint)
{
    attr_index_t index_hint = *value;

    if (*shape_id_hint == INVALID_SHAPE_ID) {
        *shape_id_hint = shape_id;
        return rb_shape_get_iv_index(shape_id, id, value);
    }

    rb_shape_t *shape = RSHAPE(shape_id);
    rb_shape_t *initial_shape = shape;
    rb_shape_t *shape_hint = RSHAPE(*shape_id_hint);

    // We assume it's likely shape_id_hint and shape_id have a close common
    // ancestor, so we check up to ANCESTOR_SEARCH_MAX_DEPTH ancestors before
    // eventually using the index, as in case of a match it will be faster.
    // However if the shape doesn't have an index, we walk the entire tree.
    int depth = INT_MAX;
    if (shape->ancestor_index && shape->next_field_index >= ANCESTOR_CACHE_THRESHOLD) {
        depth = ANCESTOR_SEARCH_MAX_DEPTH;
    }

    while (depth > 0 && shape->next_field_index > index_hint) {
        while (shape_hint->next_field_index > shape->next_field_index) {
            shape_hint = RSHAPE(shape_hint->parent_offset);
        }

        if (shape_hint == shape) {
            // We've found a common ancestor so use the index hint
            *value = index_hint;
            *shape_id_hint = SHAPE_OFFSET(shape);
            return true;
        }
        if (shape->edge_name == id) {
            // We found the matching id before a common ancestor
            *value = shape->next_field_index - 1;
            *shape_id_hint = SHAPE_OFFSET(shape);
            return true;
        }

        shape = RSHAPE(shape->parent_offset);
        depth--;
    }

    // If the original shape had an index but its ancestor doesn't
    // we switch back to the original one as it will be faster.
    if (!shape->ancestor_index && initial_shape->ancestor_index) {
        shape = initial_shape;
    }
    *shape_id_hint = shape_id;
    return shape_get_iv_index(shape, id, value);
}

static bool
shape_cache_find_ivar(rb_shape_t *shape, ID id, rb_shape_t **ivar_shape)
{
    if (shape->ancestor_index && shape->next_field_index >= ANCESTOR_CACHE_THRESHOLD) {
        redblack_node_t *node = redblack_find(shape->ancestor_index, id);
        if (node) {
            *ivar_shape = redblack_value(node);

            return true;
        }
    }

    return false;
}

static bool
shape_find_ivar(rb_shape_t *shape, ID id, rb_shape_t **ivar_shape)
{
    while (shape->parent_offset != INVALID_SHAPE_ID) {
        if (shape->edge_name == id) {
            RUBY_ASSERT(shape->type == SHAPE_IVAR);
            *ivar_shape = shape;
            return true;
        }

        shape = RSHAPE(shape->parent_offset);
    }

    return false;
}

bool
rb_shape_find_ivar(shape_id_t current_shape_id, ID id, shape_id_t *ivar_shape_id)
{
    RUBY_ASSERT(!rb_shape_too_complex_p(current_shape_id));

    rb_shape_t *shape = RSHAPE(current_shape_id);
    rb_shape_t *ivar_shape;

    if (!shape_cache_find_ivar(shape, id, &ivar_shape)) {
        // If it wasn't in the ancestor cache, then don't do a linear search
        if (shape->ancestor_index && shape->next_field_index >= ANCESTOR_CACHE_THRESHOLD) {
            return false;
        }
        else {
            if (!shape_find_ivar(shape, id, &ivar_shape)) {
                return false;
            }
        }
    }

    *ivar_shape_id = SHAPE_ID(ivar_shape, current_shape_id);

    return true;
}

bool
rb_shape_get_iv_index(shape_id_t shape_id, ID id, attr_index_t *value)
{
    // It doesn't make sense to ask for the index of an IV that's stored
    // on an object that is "too complex" as it uses a hash for storing IVs
    RUBY_ASSERT(!rb_shape_too_complex_p(shape_id));

    shape_id_t ivar_shape_id;
    if (rb_shape_find_ivar(shape_id, id, &ivar_shape_id)) {
        *value = RSHAPE_INDEX(ivar_shape_id);
        return true;
    }
    return false;
}

int32_t
rb_shape_id_offset(void)
{
    return sizeof(uintptr_t) - SHAPE_ID_NUM_BITS / sizeof(uintptr_t);
}

// Rebuild a similar shape with the same ivars but without "non-canonical"
// edges such as SHAPE_OBJ_ID.
static rb_shape_t *
shape_rebuild(rb_shape_t *initial_shape, rb_shape_t *dest_shape)
{
    rb_shape_t *midway_shape;

    RUBY_ASSERT(initial_shape->type == SHAPE_ROOT);

    if (dest_shape->type != initial_shape->type) {
        midway_shape = shape_rebuild(initial_shape, RSHAPE(dest_shape->parent_offset));
        if (UNLIKELY(!midway_shape)) {
            return NULL;
        }
    }
    else {
        midway_shape = initial_shape;
    }

    switch ((enum shape_type)dest_shape->type) {
      case SHAPE_IVAR:
        midway_shape = shape_get_next_iv_shape(midway_shape, dest_shape->edge_name);
        break;
      case SHAPE_OBJ_ID:
      case SHAPE_ROOT:
        break;
    }

    return midway_shape;
}

// Rebuild `dest_shape_id` starting from `initial_shape_id`, and keep only SHAPE_IVAR transitions.
// SHAPE_OBJ_ID and frozen status are lost.
shape_id_t
rb_shape_rebuild(shape_id_t initial_shape_id, shape_id_t dest_shape_id)
{
    RUBY_ASSERT(!rb_shape_too_complex_p(initial_shape_id));
    RUBY_ASSERT(!rb_shape_too_complex_p(dest_shape_id));

    shape_id_t next_shape_id;
    // The shape has a SHAPE_OBJ_ID edge, it needs to be rebuilt.
    if (dest_shape_id & SHAPE_ID_FL_HAS_OBJECT_ID) {
        rb_shape_t *next_shape = shape_rebuild(RSHAPE(initial_shape_id), RSHAPE(dest_shape_id));
        if (next_shape) {
            next_shape_id = SHAPE_ID(next_shape, initial_shape_id & ~SHAPE_ID_FL_NON_CANONICAL_MASK);
        }
        else {
            return rb_shape_transition_complex(initial_shape_id | (dest_shape_id & ~SHAPE_ID_FL_NON_CANONICAL_MASK));
        }
    }
    else {
        // Happy path, we have nothing to do other than change the flags.
        next_shape_id = RSHAPE_OFFSET(dest_shape_id) | RSHAPE_FLAGS(initial_shape_id);
    }
    return next_shape_id;
}

void
rb_shape_copy_fields(VALUE dest, VALUE *dest_buf, shape_id_t dest_shape_id, VALUE *src_buf, shape_id_t src_shape_id)
{
    rb_shape_t *dest_shape = RSHAPE(dest_shape_id);
    rb_shape_t *src_shape = RSHAPE(src_shape_id);

    if (src_shape->next_field_index == dest_shape->next_field_index) {
        // Happy path, we can just memcpy the ivptr content
        MEMCPY(dest_buf, src_buf, VALUE, dest_shape->next_field_index);

        // Fire write barriers
        for (uint32_t i = 0; i < dest_shape->next_field_index; i++) {
            RB_OBJ_WRITTEN(dest, Qundef, dest_buf[i]);
        }
    }
    else {
        while (src_shape->parent_offset != INVALID_SHAPE_ID) {
            if (src_shape->type == SHAPE_IVAR) {
                while (dest_shape->edge_name != src_shape->edge_name) {
                    if (UNLIKELY(dest_shape->parent_offset == INVALID_SHAPE_ID)) {
                        rb_bug("Lost field %s", rb_id2name(src_shape->edge_name));
                    }
                    dest_shape = RSHAPE(dest_shape->parent_offset);
                }

                RB_OBJ_WRITE(dest, &dest_buf[dest_shape->next_field_index - 1], src_buf[src_shape->next_field_index - 1]);
            }
            src_shape = RSHAPE(src_shape->parent_offset);
        }
    }
}

void
rb_shape_copy_complex_ivars(VALUE dest, VALUE obj, shape_id_t src_shape_id, st_table *fields_table)
{
    // obj is TOO_COMPLEX so we can copy its iv_hash
    st_table *table = st_copy(fields_table);
    if (rb_shape_has_object_id(src_shape_id)) {
        st_data_t id = (st_data_t)id_object_id;
        st_delete(table, &id, NULL);
    }
    rb_obj_init_too_complex(dest, table);
    rb_gc_writebarrier_remember(dest);
}

size_t
rb_shape_edges_count(shape_id_t shape_id)
{
    rb_shape_t *shape = RSHAPE(shape_id);
    if (shape->edges) {
        if (SINGLE_CHILD_P(shape->edges)) {
            return 1;
        }
        else {
            return rb_managed_id_table_size(shape->edges);
        }
    }
    return 0;
}

size_t
rb_shape_memsize(shape_id_t shape_id)
{
    rb_shape_t *shape = RSHAPE(shape_id);

    size_t memsize = sizeof(rb_shape_t);
    if (shape->edges && !SINGLE_CHILD_P(shape->edges)) {
        memsize += rb_managed_id_table_size(shape->edges);
    }
    return memsize;
}

bool
rb_shape_foreach_field(shape_id_t initial_shape_id, rb_shape_foreach_transition_callback func, void *data)
{
    RUBY_ASSERT(!rb_shape_too_complex_p(initial_shape_id));

    rb_shape_t *shape = RSHAPE(initial_shape_id);
    if (shape->type == SHAPE_ROOT) {
        return true;
    }

    shape_id_t parent_offset = SHAPE_ID(RSHAPE(shape->parent_offset), initial_shape_id);
    if (rb_shape_foreach_field(parent_offset, func, data)) {
        switch (func(SHAPE_ID(shape, initial_shape_id), data)) {
          case ST_STOP:
            return false;
          case ST_CHECK:
          case ST_CONTINUE:
            break;
          default:
            rb_bug("unreachable");
        }
    }
    return true;
}

#if RUBY_DEBUG
bool
rb_shape_verify_consistency(VALUE obj, shape_id_t shape_id)
{
    if (shape_id == ROOT_SHAPE_ID) {
        return true;
    }

    if (shape_id == INVALID_SHAPE_ID) {
        rb_bug("Can't set INVALID_SHAPE_ID on an object");
    }

    rb_shape_t *shape = RSHAPE(shape_id);

    bool has_object_id = false;
    while (shape->parent_offset != INVALID_SHAPE_ID) {
        if (shape->type == SHAPE_OBJ_ID) {
            has_object_id = true;
            break;
        }
        shape = RSHAPE(shape->parent_offset);
    }

    if (rb_shape_has_object_id(shape_id)) {
        if (!has_object_id) {
            rb_p(obj);
            rb_bug("shape_id claim having obj_id but doesn't shape_id=%u, obj=%s", shape_id, rb_obj_info(obj));
        }
    }
    else {
        if (has_object_id) {
            rb_p(obj);
            rb_bug("shape_id claim not having obj_id but it does shape_id=%u, obj=%s", shape_id, rb_obj_info(obj));
        }
    }

    // Make sure SHAPE_ID_HAS_IVAR_MASK is valid.
    if (rb_shape_too_complex_p(shape_id)) {
        RUBY_ASSERT(shape_id & SHAPE_ID_HAS_IVAR_MASK);

        // Ensure complex object don't appear as embedded
        if (RB_TYPE_P(obj, T_OBJECT) || IMEMO_TYPE_P(obj, imemo_fields)) {
            RUBY_ASSERT(FL_TEST_RAW(obj, ROBJECT_HEAP));
        }
    }
    else {
        attr_index_t ivar_count = RSHAPE_LEN(shape_id);
        if (has_object_id) {
            ivar_count--;
        }
        if (ivar_count) {
            RUBY_ASSERT(shape_id & SHAPE_ID_HAS_IVAR_MASK);
        }
        else {
            RUBY_ASSERT(!(shape_id & SHAPE_ID_HAS_IVAR_MASK));
        }
    }

    uint8_t flags_heap_index = rb_shape_heap_index(shape_id);
    if (RB_TYPE_P(obj, T_OBJECT)) {
        RUBY_ASSERT(flags_heap_index > 0);
        size_t shape_id_slot_size = rb_shape_tree.capacities[flags_heap_index - 1] * sizeof(VALUE) + sizeof(struct RBasic);
        size_t actual_slot_size = rb_gc_obj_slot_size(obj);

        if (shape_id_slot_size != actual_slot_size) {
            rb_bug("shape_id heap_index flags mismatch: shape_id_slot_size=%zu, gc_slot_size=%zu\n", shape_id_slot_size, actual_slot_size);
        }
    }
    else {
        if (flags_heap_index) {
            rb_bug("shape_id indicate heap_index > 0 but object is not T_OBJECT: %s", rb_obj_info(obj));
        }
    }

    return true;
}
#endif

#if SHAPE_DEBUG

/*
 * Exposing Shape to Ruby via RubyVM::Shape.of(object)
 */

static VALUE
shape_too_complex(VALUE self)
{
    shape_id_t shape_id = NUM2INT(rb_struct_getmember(self, rb_intern("id")));
    return RBOOL(rb_shape_too_complex_p(shape_id));
}

static VALUE
shape_frozen(VALUE self)
{
    shape_id_t shape_id = NUM2INT(rb_struct_getmember(self, rb_intern("id")));
    return RBOOL(shape_id & SHAPE_ID_FL_FROZEN);
}

static VALUE
shape_has_object_id_p(VALUE self)
{
    shape_id_t shape_id = NUM2INT(rb_struct_getmember(self, rb_intern("id")));
    return RBOOL(rb_shape_has_object_id(shape_id));
}

static VALUE
parse_key(ID key)
{
    if (is_instance_id(key)) {
        return ID2SYM(key);
    }
    return LONG2NUM(key);
}

static VALUE rb_shape_edge_name(rb_shape_t *shape);

static VALUE
shape_id_t_to_rb_cShape(shape_id_t shape_id)
{
    VALUE rb_cShape = rb_const_get(rb_cRubyVM, rb_intern("Shape"));
    rb_shape_t *shape = RSHAPE(shape_id);

    VALUE obj = rb_struct_new(rb_cShape,
            INT2NUM(shape_id),
            INT2NUM(RSHAPE_OFFSET(shape_id)),
            INT2NUM(shape->parent_offset),
            rb_shape_edge_name(shape),
            INT2NUM(shape->next_field_index),
            INT2NUM(rb_shape_heap_index(shape_id)),
            INT2NUM(shape->type),
            INT2NUM(RSHAPE_CAPACITY(shape_id)));
    rb_obj_freeze(obj);
    return obj;
}

static enum rb_id_table_iterator_result
rb_edges_to_hash(ID key, VALUE value, void *ref)
{
    rb_hash_aset(*(VALUE *)ref, parse_key(key), shape_id_t_to_rb_cShape(SHAPE_OFFSET((rb_shape_t *)value)));
    return ID_TABLE_CONTINUE;
}

static VALUE
rb_shape_edges(VALUE self)
{
    rb_shape_t *shape = RSHAPE(NUM2INT(rb_struct_getmember(self, rb_intern("id"))));

    VALUE hash = rb_hash_new();

    if (shape->edges) {
        if (SINGLE_CHILD_P(shape->edges)) {
            rb_shape_t *child = SINGLE_CHILD(shape->edges);
            rb_edges_to_hash(child->edge_name, (VALUE)child, &hash);
        }
        else {
            VALUE edges = shape->edges;
            rb_managed_id_table_foreach(edges, rb_edges_to_hash, &hash);
            RB_GC_GUARD(edges);
        }
    }

    return hash;
}

static VALUE
rb_shape_edge_name(rb_shape_t *shape)
{
    if (shape->edge_name) {
        if (is_instance_id(shape->edge_name)) {
            return ID2SYM(shape->edge_name);
        }
        return INT2NUM(shape->capacity);
    }
    return Qnil;
}

static VALUE
rb_shape_export_depth(VALUE self)
{
    shape_id_t shape_id = NUM2INT(rb_struct_getmember(self, rb_intern("id")));
    return SIZET2NUM(rb_shape_depth(shape_id));
}

static VALUE
rb_shape_parent(VALUE self)
{
    rb_shape_t *shape;
    shape = RSHAPE(NUM2INT(rb_struct_getmember(self, rb_intern("id"))));
    if (shape->parent_offset != INVALID_SHAPE_ID) {
        return shape_id_t_to_rb_cShape(shape->parent_offset);
    }
    else {
        return Qnil;
    }
}

static VALUE
rb_shape_debug_shape(VALUE self, VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        rb_raise(rb_eArgError, "Can't get shape of special constant");
    }
    return shape_id_t_to_rb_cShape(rb_obj_shape_id(obj));
}

static VALUE
rb_shape_root_shape(VALUE self)
{
    return shape_id_t_to_rb_cShape(ROOT_SHAPE_ID);
}

static VALUE
rb_shape_shapes_available(VALUE self)
{
    return ULL2NUM(MAX_SHAPE_ID - (rb_shapes_count() - 1));
}

static VALUE
rb_shape_exhaust(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 0, 1);
    int offset = argc == 1 ? NUM2INT(argv[0]) : 0;
    RUBY_ATOMIC_SET(shape_next_id, MAX_SHAPE_ID - offset + 1);
    return Qnil;
}

static VALUE
rb_shape_class_max_iv_count(VALUE self, VALUE klass)
{
    return INT2NUM(RCLASS_MAX_IV_COUNT(klass));
}

static VALUE shape_to_h(rb_shape_t *shape);

static enum rb_id_table_iterator_result collect_keys_and_values(ID key, VALUE value, void *ref)
{
    rb_hash_aset(*(VALUE *)ref, parse_key(key), shape_to_h((rb_shape_t *)value));
    return ID_TABLE_CONTINUE;
}

static VALUE edges(VALUE edges)
{
    VALUE hash = rb_hash_new();
    if (edges) {
        if (SINGLE_CHILD_P(edges)) {
            rb_shape_t *child = SINGLE_CHILD(edges);
            collect_keys_and_values(child->edge_name, (VALUE)child, &hash);
        }
        else {
            rb_managed_id_table_foreach(edges, collect_keys_and_values, &hash);
        }
    }
    return hash;
}

static VALUE
shape_to_h(rb_shape_t *shape)
{
    VALUE rb_shape = rb_hash_new();

    rb_hash_aset(rb_shape, ID2SYM(rb_intern("id")), INT2NUM(SHAPE_OFFSET(shape)));
    rb_hash_aset(rb_shape, ID2SYM(rb_intern("edges")), edges(shape->edges));

    if (shape == rb_shape_get_root_shape()) {
        rb_hash_aset(rb_shape, ID2SYM(rb_intern("parent_offset")), INT2NUM(ROOT_SHAPE_ID));
    }
    else {
        rb_hash_aset(rb_shape, ID2SYM(rb_intern("parent_offset")), INT2NUM(shape->parent_offset));
    }

    rb_hash_aset(rb_shape, ID2SYM(rb_intern("edge_name")), rb_id2str(shape->edge_name));
    return rb_shape;
}

static VALUE
shape_transition_tree(VALUE self)
{
    return shape_to_h(rb_shape_get_root_shape());
}

static VALUE
rb_shape_find_by_id(VALUE mod, VALUE id)
{
    shape_id_t shape_id = NUM2UINT(id);
    if (shape_id >= rb_shapes_count()) {
        rb_raise(rb_eArgError, "Shape ID %d is out of bounds\n", shape_id);
    }
    return shape_id_t_to_rb_cShape(shape_id);
}
#endif

#ifdef HAVE_MMAP
#include <sys/mman.h>
#endif

void
Init_default_shapes(void)
{
    size_t *heap_sizes = rb_gc_heap_sizes();
    size_t heaps_count = 0;
    while (heap_sizes[heaps_count]) {
        heaps_count++;
    }

    if (heaps_count > SHAPE_ID_HEAP_INDEX_MAX) {
        rb_bug("Init_default_shapes initialized with %lu heaps, only up to %u are supported", heaps_count, SHAPE_ID_HEAP_INDEX_MAX);
    }

    size_t index;
    for (index = 0; index < heaps_count; index++) {
        if (heap_sizes[index] > sizeof(struct RBasic)) {
            rb_shape_tree.capacities[index] = (heap_sizes[index] - sizeof(struct RBasic)) / sizeof(VALUE);
        }
        else {
            rb_shape_tree.capacities[index] = 0;
        }
    }
    rb_shape_tree.heaps_count = heaps_count;

#ifdef HAVE_MMAP
    size_t shape_list_mmap_size = rb_size_mul_or_raise(SHAPE_BUFFER_SIZE, sizeof(rb_shape_t), rb_eRuntimeError);
    rb_shape_tree.shape_list = (rb_shape_t *)mmap(NULL, shape_list_mmap_size,
                         PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (rb_shape_tree.shape_list == MAP_FAILED) {
        rb_shape_tree.shape_list = 0;
    }
    else {
        ruby_annotate_mmap(rb_shape_tree.shape_list, shape_list_mmap_size, "Ruby:Init_default_shapes:shape_list");
    }
#else
    rb_shape_tree.shape_list = xcalloc(SHAPE_BUFFER_SIZE, sizeof(rb_shape_t));
#endif

    if (!rb_shape_tree.shape_list) {
        rb_memerror();
    }

    id_object_id = rb_make_internal_id();

#ifdef HAVE_MMAP
    size_t shape_cache_mmap_size = rb_size_mul_or_raise(REDBLACK_CACHE_SIZE, sizeof(redblack_node_t), rb_eRuntimeError);
    redblack_cache = (redblack_node_t *)mmap(NULL, shape_cache_mmap_size,
                         PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    redblack_cache_size = 0;

    // If mmap fails, then give up on the redblack tree cache.
    // We set the cache size such that the redblack node allocators think
    // the cache is full.
    if (redblack_cache == MAP_FAILED) {
        redblack_cache = NULL;
        redblack_cache_size = REDBLACK_CACHE_SIZE;
    }
    else {
        ruby_annotate_mmap(redblack_cache, shape_cache_mmap_size, "Ruby:Init_default_shapes:shape_cache");
    }
#endif

    rb_gc_register_address(&shape_tree_obj);
    shape_tree_obj = TypedData_Wrap_Struct(0, &shape_tree_type, (void *)1);

    // Root shape
    rb_shape_t *root = rb_shape_alloc_with_parent_offset(0, INVALID_SHAPE_ID);
    root->capacity = 0;
    root->type = SHAPE_ROOT;
    RUBY_ASSERT(SHAPE_OFFSET(root) == ROOT_SHAPE_ID);
    RUBY_ASSERT(!(SHAPE_OFFSET(root) & SHAPE_ID_HAS_IVAR_MASK));

    bool dontcare;
    rb_shape_t *root_with_obj_id = get_next_shape_internal(root, id_object_id, SHAPE_OBJ_ID, &dontcare, true);
    RUBY_ASSERT(root_with_obj_id);
    RUBY_ASSERT(SHAPE_OFFSET(root_with_obj_id) == ROOT_SHAPE_WITH_OBJ_ID);
    RUBY_ASSERT(root_with_obj_id->type == SHAPE_OBJ_ID);
    RUBY_ASSERT(root_with_obj_id->edge_name == id_object_id);
    RUBY_ASSERT(root_with_obj_id->next_field_index == 1);
    RUBY_ASSERT(!(SHAPE_OFFSET(root_with_obj_id) & SHAPE_ID_HAS_IVAR_MASK));
    (void)root_with_obj_id;
}

void
Init_shape(void)
{
#if SHAPE_DEBUG
    /* Document-class: RubyVM::Shape
     * :nodoc: */
    VALUE rb_cShape = rb_struct_define_under(rb_cRubyVM, "Shape",
            "id",
            "offset",
            "parent_offset",
            "edge_name",
            "next_field_index",
            "heap_index",
            "type",
            "capacity",
            NULL);

    rb_define_method(rb_cShape, "parent", rb_shape_parent, 0);
    rb_define_method(rb_cShape, "edges", rb_shape_edges, 0);
    rb_define_method(rb_cShape, "depth", rb_shape_export_depth, 0);
    rb_define_method(rb_cShape, "too_complex?", shape_too_complex, 0);
    rb_define_method(rb_cShape, "shape_frozen?", shape_frozen, 0);
    rb_define_method(rb_cShape, "has_object_id?", shape_has_object_id_p, 0);

    rb_define_const(rb_cShape, "SHAPE_ROOT", INT2NUM(SHAPE_ROOT));
    rb_define_const(rb_cShape, "SHAPE_IVAR", INT2NUM(SHAPE_IVAR));
    rb_define_const(rb_cShape, "SHAPE_ID_NUM_BITS", INT2NUM(SHAPE_ID_NUM_BITS));
    rb_define_const(rb_cShape, "SHAPE_FLAG_SHIFT", INT2NUM(SHAPE_FLAG_SHIFT));
    rb_define_const(rb_cShape, "SHAPE_MAX_VARIATIONS", INT2NUM(SHAPE_MAX_VARIATIONS));
    rb_define_const(rb_cShape, "SHAPE_MAX_EMBEDDED_CAPACITY", INT2NUM(rb_shape_tree.capacities[rb_shape_tree.heaps_count - 1]));
    rb_define_const(rb_cShape, "SIZEOF_RB_SHAPE_T", INT2NUM(sizeof(rb_shape_t)));
    rb_define_const(rb_cShape, "SIZEOF_REDBLACK_NODE_T", INT2NUM(sizeof(redblack_node_t)));
    rb_define_const(rb_cShape, "SHAPE_BUFFER_SIZE", INT2NUM(sizeof(rb_shape_t) * SHAPE_BUFFER_SIZE));
    rb_define_const(rb_cShape, "REDBLACK_CACHE_SIZE", INT2NUM(sizeof(redblack_node_t) * REDBLACK_CACHE_SIZE));

    rb_define_singleton_method(rb_cShape, "transition_tree", shape_transition_tree, 0);
    rb_define_singleton_method(rb_cShape, "find_by_id", rb_shape_find_by_id, 1);
    rb_define_singleton_method(rb_cShape, "of", rb_shape_debug_shape, 1);
    rb_define_singleton_method(rb_cShape, "root_shape", rb_shape_root_shape, 0);
    rb_define_singleton_method(rb_cShape, "shapes_available", rb_shape_shapes_available, 0);
    rb_define_singleton_method(rb_cShape, "exhaust_shapes", rb_shape_exhaust, -1);
    rb_define_singleton_method(rb_cShape, "class_max_iv_count", rb_shape_class_max_iv_count, 1);
#endif
}
