#include "internal.h"
#include "const_path.h"
#include "internal/array.h"
#include "internal/gc.h"
#include "id_table.h"
#include "vm_sync.h"

#if SIZEOF_VOIDP == 8
// On 64 bits, we only need the top two bits to be 0.
#define PACKABLE_SERIAL_MASK (((uint32_t)0x3) << 30)
#else
// On 32 bits, we need the top tree bits to be 0.
#define PACKABLE_SERIAL_MASK (((uint32_t)0x7) << 29)
#endif

#ifdef HAVE_MMAP
#include <sys/mman.h>
#endif

static inline uint32_t
const_path_pack_id(ID id)
{
    RUBY_ASSERT(is_notop_id(id));
    RUBY_ASSERT(id_type(id) == RUBY_ID_CONST);
    uint32_t packed_id = rb_id_to_serial(id) << 1;
    return DYNAMIC_ID_P(id) ? packed_id : packed_id | PACKED_ID_STATIC_FLAG;
}

static inline bool
packable_id_p(ID id)
{
    return (const_path_pack_id(id) & PACKABLE_SERIAL_MASK) == 0;
}

static inline rb_const_path_t
const_path_packed1(bool absolute, ID id)
{
    uintptr_t num = (uintptr_t)const_path_pack_id(id);

    rb_const_path_t packed = (num << CONST_PATH_SHIFT) | CONST_PATH_IMMEDIATE_FLAG;
    if (absolute) {
        packed |= CONST_PATH_ABSOLUTE_FLAG;
    }
    return packed;
}

#if SIZEOF_VOIDP == 8
static inline rb_const_path_t
const_path_packed2(bool absolute, ID first_id, ID second_id)
{
    rb_const_path_t num = (rb_const_path_t)const_path_pack_id(first_id);
    num |= ((rb_const_path_t)const_path_pack_id(second_id)) << PACKED_ID_BITS;

    rb_const_path_t packed = (num << CONST_PATH_SHIFT) | CONST_PATH_IMMEDIATE_FLAG;
    if (absolute) {
        packed |= CONST_PATH_ABSOLUTE_FLAG;
    }
    return packed;
}
#endif

#define SINGLE_CHILD_TAG 0x1
#define TAG_SINGLE_CHILD(offset) ((((uintptr_t)(offset) << 1) | SINGLE_CHILD_TAG))
#define SINGLE_CHILD_P(edges) ((edges) & SINGLE_CHILD_TAG)
#define SINGLE_CHILD(edges) ((rb_const_path_node_offset_t)((edges) >> 1))
#define EDGES_TABLE(edges) ((struct rb_id_table *)(edges))

static inline bool
edges_table_p(uintptr_t edges)
{
    return edges && !SINGLE_CHILD_P(edges);
}

static size_t
const_path_tree_memsize(size_t capa)
{
    return rb_size_mul_add_or_raise(sizeof(struct rb_const_path_node), capa, offsetof(struct rb_const_path_tree, nodes), rb_eRuntimeError);
}

static struct rb_const_path_tree *
const_path_tree_mmap(size_t capa)
{
    RUBY_ASSERT(capa <= UINT32_MAX);

    size_t size = const_path_tree_memsize(capa);
    struct rb_const_path_tree *tree;
#ifdef HAVE_MMAP
    tree = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (tree == MAP_FAILED) {
        return NULL;
    }
    ruby_annotate_mmap(tree, size, "Ruby:const_path_tree");
#else
    tree = ruby_xmalloc(size);
#endif

    tree->capa = (uint32_t)capa;
    return tree;
}

static void
const_path_tree_unmap(struct rb_const_path_tree *tree)
{
#ifdef HAVE_MMAP
    munmap(tree, const_path_tree_memsize(tree->capa));
#else
    ruby_xfree_sized(tree, const_path_tree_memsize(tree->capa));
#endif
}

static struct rb_const_path_tree *const_path_live_tree = NULL;

static inline bool
const_path_live_tree_p(const struct rb_const_path_tree *tree)
{
    return tree == RUBY_ATOMIC_PTR_LOAD(const_path_live_tree);
}

static size_t
const_path_tree_size(const void *data)
{
    const struct rb_const_path_tree *tree = (const struct rb_const_path_tree *)data;
    size_t size = const_path_tree_memsize(tree->capa);
    if (const_path_live_tree_p(tree)) {
        for (rb_const_path_node_offset_t i = 0; i < tree->size; i++) {
            uintptr_t edges = tree->nodes[i].edges;
            if (edges_table_p(edges)) {
                size += rb_id_table_memsize(EDGES_TABLE(edges));
            }
        }
    }
    return size;
}

static void
const_path_tree_free(void *data)
{
    struct rb_const_path_tree *tree = (struct rb_const_path_tree *)data;

    // The live tree is freed by ruby_vm_destruct
    if (!const_path_live_tree_p(tree)) {
        const_path_tree_unmap(tree);
    }
}

bool
rb_obj_is_const_path_tree(VALUE obj)
{
    return obj == rb_const_path_tree;
}

void
rb_free_const_path_tree(void)
{
    struct rb_const_path_tree *tree = const_path_live_tree;
    if (!tree) return;

    for (rb_const_path_node_offset_t i = 0; i < tree->size; i++) {
        uintptr_t edges = tree->nodes[i].edges;
        if (edges_table_p(edges)) {
            rb_id_table_free(EDGES_TABLE(edges));
        }
    }
    const_path_tree_unmap(tree);
    const_path_live_tree = NULL;
}

// The tree holds no object references, so it needs neither marking nor compaction.
static const rb_data_type_t const_path_tree_type = {
    .wrap_struct_name = "VM/const_path_tree",
    .function = {
        .dfree = const_path_tree_free,
        .dsize = const_path_tree_size,
    },
    .flags = RUBY_TYPED_THREAD_SAFE_FREE | RUBY_TYPED_WB_PROTECTED,
};

#define SIZEOF_NODE sizeof(struct rb_const_path_node)
#define TREE_HEADER_SIZE ((offsetof(struct rb_const_path_tree, nodes) + SIZEOF_NODE - 1) / SIZEOF_NODE)

VALUE rb_const_path_tree = 0;
#if RUBY_DEBUG
#define CONST_PATH_INITIAL_TREE_SIZE (16384 - TREE_HEADER_SIZE)
#else
#define CONST_PATH_INITIAL_TREE_SIZE (1024 - TREE_HEADER_SIZE)
#endif

static VALUE
const_path_tree_alloc(rb_const_path_node_offset_t capa)
{
    struct rb_const_path_tree *tree = const_path_tree_mmap(capa);
    if (tree == NULL) {
        rb_memerror();
    }
    tree->capa = capa;
    return TypedData_Wrap_Struct(0, &const_path_tree_type, tree);
}
static rb_const_path_node_offset_t
const_path_tree_find_or_create(uint32_t node_offset, ID id)
{
    ASSERT_vm_locking();

    struct rb_const_path_tree *tree = const_path_live_tree;
    RUBY_ASSERT(node_offset < tree->size);
    uintptr_t edges = tree->nodes[node_offset].edges;
    uint32_t packed_serial = const_path_pack_id(id);

    if (edges) {
        if (SINGLE_CHILD_P(edges)) {
            rb_const_path_node_offset_t child_offset = SINGLE_CHILD(edges);
            if (tree->nodes[child_offset].packed_serial == packed_serial) {
                return child_offset;
            }
        }
        else {
            VALUE offset;
            if (rb_id_table_lookup(EDGES_TABLE(edges), id, &offset)) {
                return (rb_const_path_node_offset_t)offset;
            }
        }
    }

    if (tree->size >= tree->capa) {
        // powers of two
        size_t new_capa = (((size_t)tree->capa + TREE_HEADER_SIZE) * 2) - TREE_HEADER_SIZE;
        VALUE new_vtree = const_path_tree_alloc((rb_const_path_node_offset_t)new_capa);
        struct rb_const_path_tree *new_tree = RTYPEDDATA_GET_DATA(new_vtree);
        memcpy(new_tree, tree, const_path_tree_memsize(tree->size));
        // The memcpy above also copied the old header.
        new_tree->capa = (rb_const_path_node_offset_t)new_capa;
        RUBY_ATOMIC_VALUE_SET(rb_const_path_tree, new_vtree);
        RUBY_ATOMIC_PTR_SET(const_path_live_tree, new_tree);
        tree = new_tree;
    }

    rb_const_path_node_offset_t child_offset = tree->size;
    tree->size++;
    tree->nodes[child_offset].parent_offset = node_offset;
    tree->nodes[child_offset].packed_serial = packed_serial;
    tree->nodes[child_offset].edges = 0;

    if (!edges) {
        tree->nodes[node_offset].edges = TAG_SINGLE_CHILD(child_offset);
    }
    else {
        if (SINGLE_CHILD_P(edges)) {
            rb_const_path_node_offset_t sibling_offset = SINGLE_CHILD(edges);
            struct rb_id_table *table = rb_id_table_create(node_offset ? 2 : 128);
            rb_id_table_insert(table, const_path_unpack_id(tree->nodes[sibling_offset].packed_serial), sibling_offset);
            edges = (uintptr_t)table;
            tree->nodes[node_offset].edges = edges;
        }
        rb_id_table_insert(EDGES_TABLE(edges), id, child_offset);
    }

    return child_offset;
}

rb_const_path_t
rb_const_path_from_array(VALUE arr)
{
    RUBY_ASSERT(RB_TYPE_P(arr, T_ARRAY));
    rb_len_t array_size = RARRAY_LEN(arr);
    RUBY_ASSERT(array_size >= 1);

    size_t size = array_size;

    rb_len_t i = 0;
    bool absolute = RARRAY_AREF(arr, i) == ID2SYM(idNULL);
    if (absolute) {
        size--;
        i++;
    }

    RUBY_ASSERT(size >= 1);
    RUBY_ASSERT(size < UINT32_MAX);

    if (size == 1) {
        VALUE sym = RARRAY_AREF(arr, i);
        ID id = SYM2ID(sym);
        if (packable_id_p(id)) {
            return const_path_packed1(absolute, id);
        }
    }

#if SIZEOF_VOIDP == 8
    if (size == 2) {
        VALUE first_sym = RARRAY_AREF(arr, i);
        VALUE second_sym = RARRAY_AREF(arr, i + 1);
        ID first_id = SYM2ID(first_sym);
        ID second_id = SYM2ID(second_sym);

        if (packable_id_p(first_id) && packable_id_p(second_id)) {
            return const_path_packed2(absolute, first_id, second_id);
        }
    }
#endif

    rb_const_path_t packed;
    RB_VM_LOCKING() {
        rb_const_path_node_offset_t node_offset = 0;

        for (; i < array_size; i++) {
            VALUE sym = RARRAY_AREF(arr, i);
            node_offset = const_path_tree_find_or_create(node_offset, SYM2ID(sym));
        }

        packed = (rb_const_path_t)node_offset << CONST_PATH_SHIFT;

        RUBY_ASSERT((packed & (CONST_PATH_ABSOLUTE_FLAG | CONST_PATH_IMMEDIATE_FLAG)) == 0);
        if (absolute) {
            packed |= CONST_PATH_ABSOLUTE_FLAG;
        }
    }

    return packed;
}

VALUE
rb_const_path_to_array(const rb_const_path_t const_path)
{
    VALUE arr = rb_ary_new();

    if (const_path_absolute_p(const_path)) {
        rb_ary_push(arr, ID2SYM(idNULL));
    }

    size_t i = 0;
    ID segment;
    while ((segment = const_path_aref(const_path, i))) {
        rb_ary_push(arr, ID2SYM(segment));
        i++;
    }
    return arr;
}

void
Init_default_const_path(void)
{
    rb_gc_register_address(&rb_const_path_tree);
    rb_const_path_tree = const_path_tree_alloc(CONST_PATH_INITIAL_TREE_SIZE);
    struct rb_const_path_tree *tree = RTYPEDDATA_GET_DATA(rb_const_path_tree);
    tree->size = 1;
    MEMZERO(tree->nodes, struct rb_const_path_node, 1);
    const_path_live_tree = tree;
}
