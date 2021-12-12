// This file is a fragment of the yjit.o compilation unit. See yjit.c.
#include "internal.h"
#include "vm_sync.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "gc.h"
#include "iseq.h"
#include "internal/compile.h"
#include "internal/class.h"
#include "yjit.h"
#include "yjit_iface.h"
#include "yjit_codegen.h"
#include "yjit_core.h"
#include "darray.h"

#ifdef HAVE_LIBCAPSTONE
#include <capstone/capstone.h>
static VALUE cYjitDisasm;
static VALUE cYjitDisasmInsn;
#endif

static VALUE mYjit;
static VALUE cYjitBlock;

#if YJIT_STATS
static VALUE cYjitCodeComment;
#endif

#if YJIT_STATS
extern const int rb_vm_max_insn_name_size;
static int64_t exit_op_count[VM_INSTRUCTION_SIZE] = { 0 };
#endif

// Hash table of encoded instructions
extern st_table *rb_encoded_insn_data;

struct rb_yjit_options rb_yjit_opts;

// Size of code pages to allocate
#define CODE_PAGE_SIZE 16 * 1024

// How many code pages to allocate at once
#define PAGES_PER_ALLOC 512

static const rb_data_type_t yjit_block_type = {
    "YJIT/Block",
    {0, 0, 0, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

// Get the PC for a given index in an iseq
static VALUE *
yjit_iseq_pc_at_idx(const rb_iseq_t *iseq, uint32_t insn_idx)
{
    RUBY_ASSERT(iseq != NULL);
    RUBY_ASSERT(insn_idx < iseq->body->iseq_size);
    VALUE *encoded = iseq->body->iseq_encoded;
    VALUE *pc = &encoded[insn_idx];
    return pc;
}

// For debugging. Print the disassembly of an iseq.
RBIMPL_ATTR_MAYBE_UNUSED()
static void
yjit_print_iseq(const rb_iseq_t *iseq)
{
    char *ptr;
    long len;
    VALUE disassembly = rb_iseq_disasm(iseq);
    RSTRING_GETMEM(disassembly, ptr, len);
    fprintf(stderr, "%.*s\n", (int)len, ptr);
}

static int
yjit_opcode_at_pc(const rb_iseq_t *iseq, const VALUE *pc)
{
    const VALUE at_pc = *pc;
    if (FL_TEST_RAW((VALUE)iseq, ISEQ_TRANSLATED)) {
        return rb_vm_insn_addr2opcode((const void *)at_pc);
    }
    else {
        return (int)at_pc;
    }
}

// Verify that calling with cd on receiver goes to callee
static void
check_cfunc_dispatch(VALUE receiver, struct rb_callinfo *ci, void *callee, rb_callable_method_entry_t *compile_time_cme)
{
    if (METHOD_ENTRY_INVALIDATED(compile_time_cme)) {
        rb_bug("yjit: output code uses invalidated cme %p", (void *)compile_time_cme);
    }

    bool callee_correct = false;
    const rb_callable_method_entry_t *cme = rb_callable_method_entry(CLASS_OF(receiver), vm_ci_mid(ci));
    if (cme->def->type == VM_METHOD_TYPE_CFUNC) {
        const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(cme->def, body.cfunc);
        if ((void *)cfunc->func == callee) {
            callee_correct = true;
        }
    }
    if (!callee_correct) {
        rb_bug("yjit: output code calls wrong method");
    }
}

MJIT_FUNC_EXPORTED VALUE rb_hash_has_key(VALUE hash, VALUE key);

// GC root for interacting with the GC
struct yjit_root_struct {
    int unused; // empty structs are not legal in C99
};

// Hash table of BOP blocks
static st_table *blocks_assuming_bops;

static bool
assume_bop_not_redefined(jitstate_t *jit, int redefined_flag, enum ruby_basic_operators bop)
{
    if (BASIC_OP_UNREDEFINED_P(bop, redefined_flag)) {
        RUBY_ASSERT(blocks_assuming_bops);

        jit_ensure_block_entry_exit(jit);
        st_insert(blocks_assuming_bops, (st_data_t)jit->block, 0);
        return true;
    }
    else {
        return false;
    }
}

// Map klass => id_table[mid, set of blocks]
// While a block `b` is in the table, b->callee_cme == rb_callable_method_entry(klass, mid).
// See assume_method_lookup_stable()
static st_table *method_lookup_dependency;

// For adding to method_lookup_dependency data with st_update
struct lookup_dependency_insertion {
    block_t *block;
    ID mid;
};

// Map cme => set of blocks
// See assume_method_lookup_stable()
static st_table *cme_validity_dependency;

static int
add_cme_validity_dependency_i(st_data_t *key, st_data_t *value, st_data_t new_block, int existing)
{
    st_table *block_set;
    if (existing) {
        block_set = (st_table *)*value;
    }
    else {
        // Make the set and put it into cme_validity_dependency
        block_set = st_init_numtable();
        *value = (st_data_t)block_set;
    }

    // Put block into set
    st_insert(block_set, new_block, 1);

    return ST_CONTINUE;
}

static int
add_lookup_dependency_i(st_data_t *key, st_data_t *value, st_data_t data, int existing)
{
    struct lookup_dependency_insertion *info = (void *)data;

    // Find or make an id table
    struct rb_id_table *id2blocks;
    if (existing) {
        id2blocks = (void *)*value;
    }
    else {
        // Make an id table and put it into the st_table
        id2blocks = rb_id_table_create(1);
        *value = (st_data_t)id2blocks;
    }

    // Find or make a block set
    st_table *block_set;
    {
        VALUE blocks;
        if (rb_id_table_lookup(id2blocks, info->mid, &blocks)) {
            // Take existing set
            block_set = (st_table *)blocks;
        }
        else {
            // Make new block set and put it into the id table
            block_set = st_init_numtable();
            rb_id_table_insert(id2blocks, info->mid, (VALUE)block_set);
        }
    }

    st_insert(block_set, (st_data_t)info->block, 1);

    return ST_CONTINUE;
}

// Remember that a block assumes that
// `rb_callable_method_entry(receiver_klass, cme->called_id) == cme` and that
// `cme` is valid.
// When either of these assumptions becomes invalid, rb_yjit_method_lookup_change() or
// rb_yjit_cme_invalidate() invalidates the block.
//
// @raise NoMemoryError
static void
assume_method_lookup_stable(VALUE receiver_klass, const rb_callable_method_entry_t *cme, jitstate_t *jit)
{
    RUBY_ASSERT(cme_validity_dependency);
    RUBY_ASSERT(method_lookup_dependency);
    RUBY_ASSERT(rb_callable_method_entry(receiver_klass, cme->called_id) == cme);
    RUBY_ASSERT_ALWAYS(RB_TYPE_P(receiver_klass, T_CLASS) || RB_TYPE_P(receiver_klass, T_ICLASS));
    RUBY_ASSERT_ALWAYS(!rb_objspace_garbage_object_p(receiver_klass));

    jit_ensure_block_entry_exit(jit);

    block_t *block = jit->block;

    cme_dependency_t cme_dep = { receiver_klass, (VALUE)cme };
    rb_darray_append(&block->cme_dependencies, cme_dep);

    st_update(cme_validity_dependency, (st_data_t)cme, add_cme_validity_dependency_i, (st_data_t)block);

    struct lookup_dependency_insertion info = { block, cme->called_id };
    st_update(method_lookup_dependency, (st_data_t)receiver_klass, add_lookup_dependency_i, (st_data_t)&info);
}

static st_table *blocks_assuming_single_ractor_mode;

// Can raise NoMemoryError.
RBIMPL_ATTR_NODISCARD()
static bool
assume_single_ractor_mode(jitstate_t *jit)
{
    if (rb_multi_ractor_p()) return false;

    jit_ensure_block_entry_exit(jit);

    st_insert(blocks_assuming_single_ractor_mode, (st_data_t)jit->block, 1);
    return true;
}

static st_table *blocks_assuming_stable_global_constant_state;

// Assume that the global constant state has not changed since call to this function.
// Can raise NoMemoryError.
static void
assume_stable_global_constant_state(jitstate_t *jit)
{
    jit_ensure_block_entry_exit(jit);
    st_insert(blocks_assuming_stable_global_constant_state, (st_data_t)jit->block, 1);
}

static int
mark_and_pin_keys_i(st_data_t k, st_data_t v, st_data_t ignore)
{
    rb_gc_mark((VALUE)k);

    return ST_CONTINUE;
}

// GC callback during mark phase
static void
yjit_root_mark(void *ptr)
{
    if (method_lookup_dependency) {
        // TODO: This is a leak. Unused blocks linger in the table forever, preventing the
        // callee class they speculate on from being collected.
        // We could do a bespoke weak reference scheme on classes similar to
        // the interpreter's call cache. See finalizer for T_CLASS and cc_table_free().
        st_foreach(method_lookup_dependency, mark_and_pin_keys_i, 0);
    }

    if (cme_validity_dependency) {
        // Why not let the GC move the cme keys in this table?
        // Because this is basically a compare_by_identity Hash.
        // If a key moves, we would need to reinsert it into the table so it is rehashed.
        // That is tricky to do, espcially as it could trigger allocation which could
        // trigger GC. Not sure if it is okay to trigger GC while the GC is updating
        // references.
        st_foreach(cme_validity_dependency, mark_and_pin_keys_i, 0);
    }
}

static void
yjit_root_free(void *ptr)
{
    // Do nothing. The root lives as long as the process.
}

static size_t
yjit_root_memsize(const void *ptr)
{
    // Count off-gc-heap allocation size of the dependency table
    return st_memsize(method_lookup_dependency); // TODO: more accurate accounting
}

// GC callback during compaction
static void
yjit_root_update_references(void *ptr)
{
}

// Custom type for interacting with the GC
// TODO: make this write barrier protected
static const rb_data_type_t yjit_root_type = {
    "yjit_root",
    {yjit_root_mark, yjit_root_free, yjit_root_memsize, yjit_root_update_references},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

// st_table iterator for invalidating blocks that are keys to the table.
static int
block_set_invalidate_i(st_data_t key, st_data_t v, st_data_t ignore)
{
    block_t *version = (block_t *)key;

    // Thankfully, st_table supports deleting while iterating.
    invalidate_block_version(version);

    return ST_CONTINUE;
}

// Callback for when rb_callable_method_entry(klass, mid) is going to change.
// Invalidate blocks that assume stable method lookup of `mid` in `klass` when this happens.
void
rb_yjit_method_lookup_change(VALUE klass, ID mid)
{
    if (!method_lookup_dependency) return;

    RB_VM_LOCK_ENTER();

    st_data_t image;
    st_data_t key = (st_data_t)klass;
    if (st_lookup(method_lookup_dependency, key, &image)) {
        struct rb_id_table *id2blocks = (void *)image;
        VALUE blocks;

        // Invalidate all blocks in method_lookup_dependency[klass][mid]
        if (rb_id_table_lookup(id2blocks, mid, &blocks)) {
            rb_id_table_delete(id2blocks, mid);

            st_table *block_set = (st_table *)blocks;

#if YJIT_STATS
            yjit_runtime_counters.invalidate_method_lookup += block_set->num_entries;
#endif

            st_foreach(block_set, block_set_invalidate_i, 0);

            st_free_table(block_set);
        }
    }

    RB_VM_LOCK_LEAVE();
}

// Callback for when a cme becomes invalid.
// Invalidate all blocks that depend on cme being valid.
void
rb_yjit_cme_invalidate(VALUE cme)
{
    if (!cme_validity_dependency) return;

    RUBY_ASSERT(IMEMO_TYPE_P(cme, imemo_ment));

    RB_VM_LOCK_ENTER();

    // Delete the block set from the table
    st_data_t cme_as_st_data = (st_data_t)cme;
    st_data_t blocks;
    if (st_delete(cme_validity_dependency, &cme_as_st_data, &blocks)) {
        st_table *block_set = (st_table *)blocks;

#if YJIT_STATS
        yjit_runtime_counters.invalidate_method_lookup += block_set->num_entries;
#endif

        // Invalidate each block
        st_foreach(block_set, block_set_invalidate_i, 0);

        st_free_table(block_set);
    }

    RB_VM_LOCK_LEAVE();
}

// For dealing with refinements
void
rb_yjit_invalidate_all_method_lookup_assumptions(void)
{
    // It looks like Module#using actually doesn't need to invalidate all the
    // method caches, so we do nothing here for now.
}

// Remove a block from the method lookup dependency table
static void
remove_method_lookup_dependency(block_t *block, VALUE receiver_klass, const rb_callable_method_entry_t *callee_cme)
{
    RUBY_ASSERT(receiver_klass);
    RUBY_ASSERT(callee_cme); // callee_cme should be set when receiver_klass is set

    st_data_t image;
    st_data_t key = (st_data_t)receiver_klass;
    if (st_lookup(method_lookup_dependency, key, &image)) {
        struct rb_id_table *id2blocks = (void *)image;
        ID mid = callee_cme->called_id;

        // Find block set
        VALUE blocks;
        if (rb_id_table_lookup(id2blocks, mid, &blocks)) {
            st_table *block_set = (st_table *)blocks;

            // Remove block from block set
            st_data_t block_as_st_data = (st_data_t)block;
            (void)st_delete(block_set, &block_as_st_data, NULL);

            if (block_set->num_entries == 0) {
                // Block set now empty. Remove from id table.
                rb_id_table_delete(id2blocks, mid);
                st_free_table(block_set);
            }
        }
    }
}

// Remove a block from cme_validity_dependency
static void
remove_cme_validity_dependency(block_t *block, const rb_callable_method_entry_t *callee_cme)
{
    RUBY_ASSERT(callee_cme);

    st_data_t blocks;
    if (st_lookup(cme_validity_dependency, (st_data_t)callee_cme, &blocks)) {
        st_table *block_set = (st_table *)blocks;

        st_data_t block_as_st_data = (st_data_t)block;
        (void)st_delete(block_set, &block_as_st_data, NULL);
    }
}

static void
yjit_unlink_method_lookup_dependency(block_t *block)
{
    cme_dependency_t *cme_dep;
    rb_darray_foreach(block->cme_dependencies, cme_dependency_idx, cme_dep) {
        remove_method_lookup_dependency(block, cme_dep->receiver_klass, (const rb_callable_method_entry_t *)cme_dep->callee_cme);
        remove_cme_validity_dependency(block, (const rb_callable_method_entry_t *)cme_dep->callee_cme);
    }
    rb_darray_free(block->cme_dependencies);
}

static void
yjit_block_assumptions_free(block_t *block)
{
    st_data_t as_st_data = (st_data_t)block;
    if (blocks_assuming_stable_global_constant_state) {
        st_delete(blocks_assuming_stable_global_constant_state, &as_st_data, NULL);
    }

    if (blocks_assuming_single_ractor_mode) {
        st_delete(blocks_assuming_single_ractor_mode, &as_st_data, NULL);
    }

    if (blocks_assuming_bops) {
        st_delete(blocks_assuming_bops, &as_st_data, NULL);
    }
}

typedef VALUE (*yjit_func_t)(rb_execution_context_t *, rb_control_frame_t *);

bool
rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec)
{
#if (OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE) && JIT_ENABLED
    bool success = true;
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    // Compile a block version starting at the first instruction
    uint8_t *code_ptr = gen_entry_point(iseq, 0, ec);

    if (code_ptr) {
        iseq->body->jit_func = (yjit_func_t)code_ptr;
    }
    else {
        iseq->body->jit_func = 0;
        success = false;
    }

    RB_VM_LOCK_LEAVE();
    return success;
#else
    return false;
#endif
}

struct yjit_block_itr {
    const rb_iseq_t *iseq;
    VALUE list;
};

/* Get a list of the YJIT blocks associated with `rb_iseq` */
static VALUE
yjit_blocks_for(VALUE mod, VALUE rb_iseq)
{
    if (CLASS_OF(rb_iseq) != rb_cISeq) {
        return rb_ary_new();
    }

    const rb_iseq_t *iseq = rb_iseqw_to_iseq(rb_iseq);

    VALUE all_versions = rb_ary_new();
    rb_darray_for(iseq->body->yjit_blocks, version_array_idx) {
        rb_yjit_block_array_t versions = rb_darray_get(iseq->body->yjit_blocks, version_array_idx);

        rb_darray_for(versions, block_idx) {
            block_t *block = rb_darray_get(versions, block_idx);

            // FIXME: The object craeted here can outlive the block itself
            VALUE rb_block = TypedData_Wrap_Struct(cYjitBlock, &yjit_block_type, block);
            rb_ary_push(all_versions, rb_block);
        }
    }

    return all_versions;
}

/* Get the address of the code associated with a YJIT::Block */
static VALUE
block_address(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &yjit_block_type, block);
    return LONG2NUM((intptr_t)block->start_addr);
}

/* Get the machine code for YJIT::Block as a binary string */
static VALUE
block_code(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &yjit_block_type, block);

    return (VALUE)rb_str_new(
        (const char*)block->start_addr,
        block->end_addr - block->start_addr
    );
}

/* Get the start index in the Instruction Sequence that corresponds to this
 * YJIT::Block */
static VALUE
iseq_start_index(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &yjit_block_type, block);

    return INT2NUM(block->blockid.idx);
}

/* Get the end index in the Instruction Sequence that corresponds to this
 * YJIT::Block */
static VALUE
iseq_end_index(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &yjit_block_type, block);

    return INT2NUM(block->end_idx);
}

/* Called when a basic operation is redefined */
void
rb_yjit_bop_redefined(VALUE klass, const rb_method_entry_t *me, enum ruby_basic_operators bop)
{
    if (blocks_assuming_bops) {
#if YJIT_STATS
        yjit_runtime_counters.invalidate_bop_redefined += blocks_assuming_bops->num_entries;
#endif

        st_foreach(blocks_assuming_bops, block_set_invalidate_i, 0);
    }
}

/* Called when the constant state changes */
void
rb_yjit_constant_state_changed(void)
{
    if (blocks_assuming_stable_global_constant_state) {
#if YJIT_STATS
        yjit_runtime_counters.constant_state_bumps++;
        yjit_runtime_counters.invalidate_constant_state_bump += blocks_assuming_stable_global_constant_state->num_entries;
#endif

        st_foreach(blocks_assuming_stable_global_constant_state, block_set_invalidate_i, 0);
    }
}

// Callback from the opt_setinlinecache instruction in the interpreter.
// Invalidate the block for the matching opt_getinlinecache so it could regenerate code
// using the new value in the constant cache.
void
rb_yjit_constant_ic_update(const rb_iseq_t *const iseq, IC ic)
{
    if (!rb_yjit_enabled_p()) return;

    // We can't generate code in these situations, so no need to invalidate.
    // See gen_opt_getinlinecache.
    if (ic->entry->ic_cref || rb_multi_ractor_p()) {
        return;
    }

    RB_VM_LOCK_ENTER();
    rb_vm_barrier(); // Stop other ractors since we are going to patch machine code.
    {
        const struct rb_iseq_constant_body *const body = iseq->body;
        VALUE *code = body->iseq_encoded;
        const unsigned get_insn_idx = ic->get_insn_idx;

        // This should come from a running iseq, so direct threading translation
        // should have been done
        RUBY_ASSERT(FL_TEST((VALUE)iseq, ISEQ_TRANSLATED));
        RUBY_ASSERT(get_insn_idx < body->iseq_size);
        RUBY_ASSERT(rb_vm_insn_addr2insn((const void *)code[get_insn_idx]) == BIN(opt_getinlinecache));

        // Find the matching opt_getinlinecache and invalidate all the blocks there
        RUBY_ASSERT(insn_op_type(BIN(opt_getinlinecache), 1) == TS_IC);
        if (ic == (IC)code[get_insn_idx + 1 + 1]) {
            rb_yjit_block_array_t getinlinecache_blocks = yjit_get_version_array(iseq, get_insn_idx);

            // Put a bound for loop below to be defensive
            const int32_t initial_version_count = rb_darray_size(getinlinecache_blocks);
            for (int32_t iteration=0; iteration<initial_version_count; ++iteration) {
                getinlinecache_blocks = yjit_get_version_array(iseq, get_insn_idx);

                if (rb_darray_size(getinlinecache_blocks) > 0) {
                    block_t *block = rb_darray_get(getinlinecache_blocks, 0);
                    invalidate_block_version(block);
#if YJIT_STATS
                    yjit_runtime_counters.invalidate_constant_ic_fill++;
#endif
                }
                else {
                    break;
                }
            }

            // All versions at get_insn_idx should now be gone
            RUBY_ASSERT(0 == rb_darray_size(yjit_get_version_array(iseq, get_insn_idx)));
        }
        else {
            RUBY_ASSERT(false && "ic->get_insn_diex not set properly");
        }
    }
    RB_VM_LOCK_LEAVE();
}

void
rb_yjit_before_ractor_spawn(void)
{
    if (blocks_assuming_single_ractor_mode) {
#if YJIT_STATS
        yjit_runtime_counters.invalidate_ractor_spawn += blocks_assuming_single_ractor_mode->num_entries;
#endif

        st_foreach(blocks_assuming_single_ractor_mode, block_set_invalidate_i, 0);
    }
}

#ifdef HAVE_LIBCAPSTONE
static const rb_data_type_t yjit_disasm_type = {
    "YJIT/Disasm",
    {0, (void(*)(void *))cs_close, 0, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
yjit_disasm_init(VALUE klass)
{
    csh * handle;
    VALUE disasm = TypedData_Make_Struct(klass, csh, &yjit_disasm_type, handle);
    if (cs_open(CS_ARCH_X86, CS_MODE_64, handle) != CS_ERR_OK) {
        rb_raise(rb_eRuntimeError, "failed to make Capstone handle");
    }
    return disasm;
}

static VALUE
yjit_disasm(VALUE self, VALUE code, VALUE from)
{
    size_t count;
    csh * handle;
    cs_insn *insns;

    TypedData_Get_Struct(self, csh, &yjit_disasm_type, handle);
    count = cs_disasm(*handle, (uint8_t*)StringValuePtr(code), RSTRING_LEN(code), NUM2ULL(from), 0, &insns);
    VALUE insn_list = rb_ary_new_capa(count);

    for (size_t i = 0; i < count; i++) {
        VALUE vals = rb_ary_new_from_args(3, LONG2NUM(insns[i].address),
                rb_str_new2(insns[i].mnemonic),
                rb_str_new2(insns[i].op_str));
        rb_ary_push(insn_list, rb_struct_alloc(cYjitDisasmInsn, vals));
    }
    cs_free(insns, count);
    return insn_list;
}
#endif

// Primitive called in yjit.rb. Export all machine code comments as a Ruby array.
static VALUE
comments_for(rb_execution_context_t *ec, VALUE self, VALUE start_address, VALUE end_address)
{
    VALUE comment_array = rb_ary_new();
#if RUBY_DEBUG
    uint8_t *start = (void *)NUM2ULL(start_address);
    uint8_t *end = (void *)NUM2ULL(end_address);

    rb_darray_for(yjit_code_comments, i) {
        struct yjit_comment comment = rb_darray_get(yjit_code_comments, i);
        uint8_t *comment_pos = cb_get_ptr(cb, comment.offset);

        if (comment_pos >= end) {
            break;
        }
        if (comment_pos >= start) {
            VALUE vals = rb_ary_new_from_args(
                2,
                LL2NUM((long long) comment_pos),
                rb_str_new_cstr(comment.comment)
            );
            rb_ary_push(comment_array, rb_struct_alloc(cYjitCodeComment, vals));
        }
    }

#endif // if RUBY_DEBUG

    return comment_array;
}

static VALUE
yjit_stats_enabled_p(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(YJIT_STATS && rb_yjit_opts.gen_stats);
}

// Primitive called in yjit.rb. Export all YJIT statistics as a Ruby hash.
static VALUE
get_yjit_stats(rb_execution_context_t *ec, VALUE self)
{
    // Return Qnil if YJIT isn't enabled
    if (cb == NULL) {
        return Qnil;
    }

    VALUE hash = rb_hash_new();

    RB_VM_LOCK_ENTER();

    {
        VALUE key = ID2SYM(rb_intern("inline_code_size"));
        VALUE value = LL2NUM((long long)cb->write_pos);
        rb_hash_aset(hash, key, value);

        key = ID2SYM(rb_intern("outlined_code_size"));
        value = LL2NUM((long long)ocb->write_pos);
        rb_hash_aset(hash, key, value);
    }

#if YJIT_STATS
    if (rb_yjit_opts.gen_stats) {
        // Indicate that the complete set of stats is available
        rb_hash_aset(hash, ID2SYM(rb_intern("all_stats")), Qtrue);

        int64_t *counter_reader = (int64_t *)&yjit_runtime_counters;
        int64_t *counter_reader_end = &yjit_runtime_counters.last_member;

        // For each counter in yjit_counter_names, add that counter as
        // a key/value pair.

        // Iterate through comma separated counter name list
        char *name_reader = yjit_counter_names;
        char *counter_name_end = yjit_counter_names + sizeof(yjit_counter_names);
        while (name_reader < counter_name_end && counter_reader < counter_reader_end) {
            if (*name_reader == ',' || *name_reader == ' ') {
                name_reader++;
                continue;
            }

            // Compute length of counter name
            int name_len;
            char *name_end;
            {
                name_end = strchr(name_reader, ',');
                if (name_end == NULL) break;
                name_len = (int)(name_end - name_reader);
            }

            // Put counter into hash
            VALUE key = ID2SYM(rb_intern2(name_reader, name_len));
            VALUE value = LL2NUM((long long)*counter_reader);
            rb_hash_aset(hash, key, value);

            counter_reader++;
            name_reader = name_end;
        }

        // For each entry in exit_op_count, add a stats entry with key "exit_INSTRUCTION_NAME"
        // and the value is the count of side exits for that instruction.

        char key_string[rb_vm_max_insn_name_size + 6]; // Leave room for "exit_" and a final NUL
        for (int i = 0; i < VM_INSTRUCTION_SIZE; i++) {
            const char *i_name = insn_name(i); // Look up Ruby's NUL-terminated insn name string
            snprintf(key_string, rb_vm_max_insn_name_size + 6, "%s%s", "exit_", i_name);

            VALUE key = ID2SYM(rb_intern(key_string));
            VALUE value = LL2NUM((long long)exit_op_count[i]);
            rb_hash_aset(hash, key, value);
        }
    }
#endif

    RB_VM_LOCK_LEAVE();

    return hash;
}

// Primitive called in yjit.rb. Zero out all the counters.
static VALUE
reset_stats_bang(rb_execution_context_t *ec, VALUE self)
{
#if YJIT_STATS
    memset(&exit_op_count, 0, sizeof(exit_op_count));
    memset(&yjit_runtime_counters, 0, sizeof(yjit_runtime_counters));
#endif // if YJIT_STATS
    return Qnil;
}

// Primitive for yjit.rb. For testing running out of executable memory
static VALUE
simulate_oom_bang(rb_execution_context_t *ec, VALUE self)
{
    if (RUBY_DEBUG && cb && ocb) {
        // Only simulate in debug builds for paranoia.
        cb_set_pos(cb, cb->mem_size-1);
        cb_set_pos(ocb, ocb->mem_size-1);
    }
    return Qnil;
}

#include "yjit.rbinc"

#if YJIT_STATS
void
rb_yjit_collect_vm_usage_insn(int insn)
{
    yjit_runtime_counters.vm_insns_count++;
}

void
rb_yjit_collect_binding_alloc(void)
{
    yjit_runtime_counters.binding_allocations++;
}

void
rb_yjit_collect_binding_set(void)
{
    yjit_runtime_counters.binding_set++;
}

static const VALUE *
yjit_count_side_exit_op(const VALUE *exit_pc)
{
    int insn = rb_vm_insn_addr2opcode((const void *)*exit_pc);
    exit_op_count[insn]++;
    return exit_pc; // This function must return exit_pc!
}
#endif

void
rb_yjit_iseq_mark(const struct rb_iseq_constant_body *body)
{
    rb_darray_for(body->yjit_blocks, version_array_idx) {
        rb_yjit_block_array_t version_array = rb_darray_get(body->yjit_blocks, version_array_idx);

        rb_darray_for(version_array, block_idx) {
            block_t *block = rb_darray_get(version_array, block_idx);

            rb_gc_mark_movable((VALUE)block->blockid.iseq);

            cme_dependency_t *cme_dep;
            rb_darray_foreach(block->cme_dependencies, cme_dependency_idx, cme_dep) {
                rb_gc_mark_movable(cme_dep->receiver_klass);
                rb_gc_mark_movable(cme_dep->callee_cme);
            }

            // Mark outgoing branch entries
            rb_darray_for(block->outgoing, branch_idx) {
                branch_t *branch = rb_darray_get(block->outgoing, branch_idx);
                for (int i = 0; i < 2; ++i) {
                    rb_gc_mark_movable((VALUE)branch->targets[i].iseq);
                }
            }

            // Walk over references to objects in generated code.
            uint32_t *offset_element;
            rb_darray_foreach(block->gc_object_offsets, offset_idx, offset_element) {
                uint32_t offset_to_value = *offset_element;
                uint8_t *value_address = cb_get_ptr(cb, offset_to_value);

                VALUE object;
                memcpy(&object, value_address, SIZEOF_VALUE);
                rb_gc_mark_movable(object);
            }

            // Mark the machine code page this block lives on
            //rb_gc_mark_movable(block->code_page);
        }
    }
}

void
rb_yjit_iseq_update_references(const struct rb_iseq_constant_body *body)
{
    rb_vm_barrier();

    rb_darray_for(body->yjit_blocks, version_array_idx) {
        rb_yjit_block_array_t version_array = rb_darray_get(body->yjit_blocks, version_array_idx);

        rb_darray_for(version_array, block_idx) {
            block_t *block = rb_darray_get(version_array, block_idx);

            block->blockid.iseq = (const rb_iseq_t *)rb_gc_location((VALUE)block->blockid.iseq);

            cme_dependency_t *cme_dep;
            rb_darray_foreach(block->cme_dependencies, cme_dependency_idx, cme_dep) {
                cme_dep->receiver_klass = rb_gc_location(cme_dep->receiver_klass);
                cme_dep->callee_cme = rb_gc_location(cme_dep->callee_cme);
            }

            // Update outgoing branch entries
            rb_darray_for(block->outgoing, branch_idx) {
                branch_t *branch = rb_darray_get(block->outgoing, branch_idx);
                for (int i = 0; i < 2; ++i) {
                    branch->targets[i].iseq = (const void *)rb_gc_location((VALUE)branch->targets[i].iseq);
                }
            }

            // Walk over references to objects in generated code.
            uint32_t *offset_element;
            rb_darray_foreach(block->gc_object_offsets, offset_idx, offset_element) {
                uint32_t offset_to_value = *offset_element;
                uint8_t *value_address = cb_get_ptr(cb, offset_to_value);

                VALUE object;
                memcpy(&object, value_address, SIZEOF_VALUE);
                VALUE possibly_moved = rb_gc_location(object);
                // Only write when the VALUE moves, to be CoW friendly.
                if (possibly_moved != object) {
                    // Possibly unlock the page we need to update
                    cb_mark_position_writeable(cb, offset_to_value);

                    // Object could cross a page boundary, so unlock there as well
                    cb_mark_position_writeable(cb, offset_to_value + SIZEOF_VALUE - 1);
                    memcpy(value_address, &possibly_moved, SIZEOF_VALUE);
                }
            }

            // Update the machine code page this block lives on
            //block->code_page = rb_gc_location(block->code_page);
        }
    }

    /* If YJIT isn't initialized, then cb or ocb could be NULL. */
    if (cb) {
        cb_mark_all_executable(cb);
    }

    if (ocb) {
        cb_mark_all_executable(ocb);
    }
}

// Free the yjit resources associated with an iseq
void
rb_yjit_iseq_free(const struct rb_iseq_constant_body *body)
{
    rb_darray_for(body->yjit_blocks, version_array_idx) {
        rb_yjit_block_array_t version_array = rb_darray_get(body->yjit_blocks, version_array_idx);

        rb_darray_for(version_array, block_idx) {
            block_t *block = rb_darray_get(version_array, block_idx);
            yjit_free_block(block);
        }

        rb_darray_free(version_array);
    }

    rb_darray_free(body->yjit_blocks);
}

// Struct representing a code page
typedef struct code_page_struct
{
    // Chunk of executable memory
    uint8_t* mem_block;

    // Size of the executable memory chunk
    uint32_t page_size;

    // Inline code block
    codeblock_t cb;

    // Outlined code block
    codeblock_t ocb;

    // Next node in the free list (private)
    struct code_page_struct* _next;

} code_page_t;

// Current code page we are writing machine code into
static VALUE yjit_cur_code_page = Qfalse;

// Head of the list of free code pages
static code_page_t *code_page_freelist = NULL;

// Free a code page, add it to the free list
static void
yjit_code_page_free(void *voidp)
{
    code_page_t* code_page = (code_page_t*)voidp;
    code_page->_next = code_page_freelist;
    code_page_freelist = code_page;
}

// Custom type for interacting with the GC
static const rb_data_type_t yjit_code_page_type = {
    "yjit_code_page",
    {NULL, yjit_code_page_free, NULL, NULL},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

// Allocate a code page and wrap it into a Ruby object owned by the GC
static VALUE
rb_yjit_code_page_alloc(void)
{
    // If the free list is empty
    if (!code_page_freelist) {
        // Allocate many pages at once
        uint8_t* code_chunk = alloc_exec_mem(PAGES_PER_ALLOC * CODE_PAGE_SIZE);

        // Do this in reverse order so we allocate our pages in order
        for (int i = PAGES_PER_ALLOC - 1; i >= 0; --i) {
            code_page_t* code_page = malloc(sizeof(code_page_t));
            code_page->mem_block = code_chunk + i * CODE_PAGE_SIZE;
            assert ((intptr_t)code_page->mem_block % CODE_PAGE_SIZE == 0);
            code_page->page_size = CODE_PAGE_SIZE;
            code_page->_next = code_page_freelist;
            code_page_freelist = code_page;
        }
    }

    code_page_t* code_page = code_page_freelist;
    code_page_freelist = code_page_freelist->_next;

    // Create a Ruby wrapper struct for the code page object
    VALUE wrapper = TypedData_Wrap_Struct(0, &yjit_code_page_type, code_page);

    // Write a pointer to the wrapper object on the page
    *((VALUE*)code_page->mem_block) = wrapper;

    // Initialize the code blocks
    uint8_t* page_start = code_page->mem_block + sizeof(VALUE);
    uint8_t* page_end = code_page->mem_block + CODE_PAGE_SIZE;
    uint32_t halfsize = (uint32_t)(page_end - page_start) / 2;
    cb_init(&code_page->cb, page_start, halfsize);
    cb_init(&code_page->cb, page_start + halfsize, halfsize);

    return wrapper;
}

// Unwrap the Ruby object representing a code page
static code_page_t *
rb_yjit_code_page_unwrap(VALUE cp_obj)
{
    code_page_t * code_page;
    TypedData_Get_Struct(cp_obj, code_page_t, &yjit_code_page_type, code_page);
    return code_page;
}

// Get the code page wrapper object for a code pointer
static VALUE
rb_yjit_code_page_from_ptr(uint8_t* code_ptr)
{
    VALUE* page_start = (VALUE*)((intptr_t)code_ptr & ~(CODE_PAGE_SIZE - 1));
    VALUE wrapper = *page_start;
    return wrapper;
}

// Get the inline code block corresponding to a code pointer
static void
yjit_get_cb(codeblock_t* cb, uint8_t* code_ptr)
{
    VALUE page_wrapper = rb_yjit_code_page_from_ptr(code_ptr);
    code_page_t *code_page = rb_yjit_code_page_unwrap(page_wrapper);

    // A pointer to the page wrapper object is written at the start of the code page
    uint8_t* mem_block = code_page->mem_block + sizeof(VALUE);
    uint32_t mem_size = (code_page->page_size/2) - sizeof(VALUE);
    RUBY_ASSERT(mem_block);

    // Map the code block to this memory region
    cb_init(cb, mem_block, mem_size);
}

// Get the outlined code block corresponding to a code pointer
static void
yjit_get_ocb(codeblock_t* cb, uint8_t* code_ptr)
{
    VALUE page_wrapper = rb_yjit_code_page_from_ptr(code_ptr);
    code_page_t *code_page = rb_yjit_code_page_unwrap(page_wrapper);

    // A pointer to the page wrapper object is written at the start of the code page
    uint8_t* mem_block = code_page->mem_block + (code_page->page_size/2);
    uint32_t mem_size = code_page->page_size/2;
    RUBY_ASSERT(mem_block);

    // Map the code block to this memory region
    cb_init(cb, mem_block, mem_size);
}

// Get the current code page or allocate a new one
static VALUE
yjit_get_code_page(uint32_t cb_bytes_needed, uint32_t ocb_bytes_needed)
{
    // If this is the first code page
    if (yjit_cur_code_page == Qfalse) {
        yjit_cur_code_page = rb_yjit_code_page_alloc();
    }

    // Get the current code page
    code_page_t *code_page = rb_yjit_code_page_unwrap(yjit_cur_code_page);

    // Compute how many bytes are left in the code blocks
    uint32_t cb_bytes_left = code_page->cb.mem_size - code_page->cb.write_pos;
    uint32_t ocb_bytes_left = code_page->ocb.mem_size - code_page->ocb.write_pos;
    RUBY_ASSERT_ALWAYS(cb_bytes_needed <= code_page->cb.mem_size);
    RUBY_ASSERT_ALWAYS(ocb_bytes_needed <= code_page->ocb.mem_size);

    // If there's enough space left in the current code page
    if (cb_bytes_needed <= cb_bytes_left && ocb_bytes_needed <= ocb_bytes_left) {
        return yjit_cur_code_page;
    }

    // Allocate a new code page
    yjit_cur_code_page = rb_yjit_code_page_alloc();
    code_page_t *new_code_page = rb_yjit_code_page_unwrap(yjit_cur_code_page);

    // Jump to the new code page
    jmp_ptr(&code_page->cb, cb_get_ptr(&new_code_page->cb, 0));

    return yjit_cur_code_page;
}

bool
rb_yjit_enabled_p(void)
{
    return rb_yjit_opts.yjit_enabled;
}

unsigned
rb_yjit_call_threshold(void)
{
    return rb_yjit_opts.call_threshold;
}

# define PTR2NUM(x)   (LONG2NUM((long)(x)))

/**
 *  call-seq: block.id -> unique_id
 *
 *  Returns a unique integer ID for the block.  For example:
 *
 *      blocks = blocks_for(iseq)
 *      blocks.group_by(&:id)
 */
static VALUE
block_id(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &yjit_block_type, block);
    return PTR2NUM(block);
}

/**
 *  call-seq: block.outgoing_ids -> list
 *
 *  Returns a list of outgoing ids for the current block.  This list can be used
 *  in conjunction with Block#id to construct a graph of block objects.
 */
static VALUE
outgoing_ids(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &yjit_block_type, block);

    VALUE ids = rb_ary_new();

    rb_darray_for(block->outgoing, branch_idx) {
        branch_t *out_branch = rb_darray_get(block->outgoing, branch_idx);

        for (size_t succ_idx = 0; succ_idx < 2; succ_idx++) {
            block_t *succ = out_branch->blocks[succ_idx];

            if (succ == NULL)
                continue;

            rb_ary_push(ids, PTR2NUM(succ));
        }

    }

    return ids;
}

// Can raise RuntimeError
void
rb_yjit_init(struct rb_yjit_options *options)
{
    if (!YJIT_SUPPORTED_P || !JIT_ENABLED) {
        return;
    }

    rb_yjit_opts = *options;
    rb_yjit_opts.yjit_enabled = true;

    rb_yjit_opts.gen_stats = rb_yjit_opts.gen_stats || getenv("RUBY_YJIT_STATS");

#if !YJIT_STATS
    if(rb_yjit_opts.gen_stats) {
        rb_warning("--yjit-stats requires that Ruby is compiled with CPPFLAGS='-DYJIT_STATS=1' or CPPFLAGS='-DRUBY_DEBUG=1'");
    }
#endif

    // Normalize command-line options to default values
    if (rb_yjit_opts.exec_mem_size < 1) {
        rb_yjit_opts.exec_mem_size = 256;
    }
    if (rb_yjit_opts.call_threshold < 1) {
        rb_yjit_opts.call_threshold = YJIT_DEFAULT_CALL_THRESHOLD;
    }
    if (rb_yjit_opts.max_versions < 1) {
        rb_yjit_opts.max_versions = 4;
    }

    // If type propagation is disabled, max 1 version per block
    if (rb_yjit_opts.no_type_prop) {
        rb_yjit_opts.max_versions = 1;
    }

    blocks_assuming_stable_global_constant_state = st_init_numtable();
    blocks_assuming_single_ractor_mode = st_init_numtable();
    blocks_assuming_bops = st_init_numtable();

    yjit_init_codegen();
    yjit_init_core();

    // YJIT Ruby module
    mYjit = rb_define_module_under(rb_cRubyVM, "YJIT");
    rb_define_module_function(mYjit, "blocks_for", yjit_blocks_for, 1);

    // YJIT::Block (block version, code block)
    cYjitBlock = rb_define_class_under(mYjit, "Block", rb_cObject);
    rb_define_method(cYjitBlock, "address", block_address, 0);
    rb_define_method(cYjitBlock, "id", block_id, 0);
    rb_define_method(cYjitBlock, "code", block_code, 0);
    rb_define_method(cYjitBlock, "iseq_start_index", iseq_start_index, 0);
    rb_define_method(cYjitBlock, "iseq_end_index", iseq_end_index, 0);
    rb_define_method(cYjitBlock, "outgoing_ids", outgoing_ids, 0);

    // YJIT disassembler interface
#ifdef HAVE_LIBCAPSTONE
    cYjitDisasm = rb_define_class_under(mYjit, "Disasm", rb_cObject);
    rb_define_alloc_func(cYjitDisasm, yjit_disasm_init);
    rb_define_method(cYjitDisasm, "disasm", yjit_disasm, 2);
    cYjitDisasmInsn = rb_struct_define_under(cYjitDisasm, "Insn", "address", "mnemonic", "op_str", NULL);
#if RUBY_DEBUG
    cYjitCodeComment = rb_struct_define_under(cYjitDisasm, "Comment", "address", "comment", NULL);
#endif
#endif

    // Make dependency tables
    method_lookup_dependency = st_init_numtable();
    cme_validity_dependency = st_init_numtable();

    // Initialize the GC hooks
    struct yjit_root_struct *root;
    VALUE yjit_root = TypedData_Make_Struct(0, struct yjit_root_struct, &yjit_root_type, root);
    rb_gc_register_mark_object(yjit_root);

    (void)yjit_get_cb;
    (void)yjit_get_ocb;
    (void)yjit_get_code_page;
}
