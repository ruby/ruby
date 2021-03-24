#include "ruby/ruby.h"
#include "vm_core.h"
#include "insns.inc"
#include "internal.h"
#include "vm_sync.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "gc.h"
#include "internal/compile.h"
#include "internal/class.h"
#include "insns_info.inc"
#include "yjit.h"
#include "yjit_iface.h"
#include "yjit_codegen.h"
#include "yjit_core.h"
#include "yjit_hooks.inc"
#include "darray.h"

#if HAVE_LIBCAPSTONE
#include <capstone/capstone.h>
static VALUE cYjitDisasm;
static VALUE cYjitDisasmInsn;
#endif

static VALUE mYjit;
static VALUE cYjitBlock;

#if RUBY_DEBUG
static int64_t vm_insns_count = 0;
static int64_t exit_op_count[VM_INSTRUCTION_SIZE] = { 0 };
int64_t rb_compiled_iseq_count = 0;
struct rb_yjit_runtime_counters yjit_runtime_counters = { 0 };
static VALUE cYjitCodeComment;
#endif

// Machine code blocks (executable memory)
extern codeblock_t *cb;
extern codeblock_t *ocb;

// Hash table of encoded instructions
extern st_table *rb_encoded_insn_data;

struct rb_yjit_options rb_yjit_opts;

static const rb_data_type_t yjit_block_type = {
    "YJIT/Block",
    {0, 0, 0, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

// Write the YJIT entry point pre-call bytes
void
cb_write_pre_call_bytes(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(yjit_with_ec_pre_call_bytes); ++i)
        cb_write_byte(cb, yjit_with_ec_pre_call_bytes[i]);
}

// Write the YJIT exit post-call bytes
void
cb_write_post_call_bytes(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(yjit_with_ec_post_call_bytes); ++i)
        cb_write_byte(cb, yjit_with_ec_post_call_bytes[i]);
}

// Get the PC for a given index in an iseq
VALUE *
yjit_iseq_pc_at_idx(const rb_iseq_t *iseq, uint32_t insn_idx)
{
    RUBY_ASSERT(iseq != NULL);
    RUBY_ASSERT(insn_idx < iseq->body->iseq_size);
    VALUE *encoded = iseq->body->iseq_encoded;
    VALUE *pc = &encoded[insn_idx];
    return pc;
}

// Keep track of mapping from instructions to generated code
// See comment for rb_encoded_insn_data in iseq.c
void
map_addr2insn(void *code_ptr, int insn)
{
    const void * const *table = rb_vm_get_insns_address_table();
    const void * const translated_address = table[insn];
    st_data_t encoded_insn_data;
    if (st_lookup(rb_encoded_insn_data, (st_data_t)translated_address, &encoded_insn_data)) {
        st_insert(rb_encoded_insn_data, (st_data_t)code_ptr, encoded_insn_data);
    }
    else {
        rb_bug("yjit: failed to find info for original instruction while dealing with addr2insn");
    }
}

int
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
void
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

bool
cfunc_needs_frame(const rb_method_cfunc_t *cfunc)
{
    void* fptr = (void*)cfunc->func;

    // Leaf C functions do not need a stack frame
    // or a stack overflow check
    return !(
        // Hash#key?
        fptr == (void*)rb_hash_has_key
    );
}

// GC root for interacting with the GC
struct yjit_root_struct {
    int unused; // empty structs are not legal in C99
};

// Hash table of BOP blocks
static st_table *blocks_assuming_bops;

bool
assume_bop_not_redefined(block_t *block, int redefined_flag, enum ruby_basic_operators bop)
{
    if (BASIC_OP_UNREDEFINED_P(bop, redefined_flag)) {
        if (blocks_assuming_bops) {
            st_insert(blocks_assuming_bops, (st_data_t)block, 0);
        }
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

// Remember that a block assumes that rb_callable_method_entry(receiver_klass, mid) == cme and that
// cme is vald.
// When either of these assumptions becomes invalid, rb_yjit_method_lookup_change() or
// rb_yjit_cme_invalidate() invalidates the block.
//
// @raise NoMemoryError
void
assume_method_lookup_stable(VALUE receiver_klass, const rb_callable_method_entry_t *cme, block_t *block)
{
    RUBY_ASSERT(!block->receiver_klass && !block->callee_cme);
    RUBY_ASSERT(cme_validity_dependency);
    RUBY_ASSERT(method_lookup_dependency);
    RUBY_ASSERT_ALWAYS(RB_TYPE_P(receiver_klass, T_CLASS));
    RUBY_ASSERT_ALWAYS(!rb_objspace_garbage_object_p(receiver_klass));

    block->callee_cme = (VALUE)cme;
    st_update(cme_validity_dependency, (st_data_t)cme, add_cme_validity_dependency_i, (st_data_t)block);

    block->receiver_klass = receiver_klass;
    struct lookup_dependency_insertion info = { block, cme->called_id };
    st_update(method_lookup_dependency, (st_data_t)receiver_klass, add_lookup_dependency_i, (st_data_t)&info);
}

static st_table *blocks_assuming_single_ractor_mode;

// Can raise NoMemoryError.
RBIMPL_ATTR_NODISCARD()
bool
assume_single_ractor_mode(block_t *block) {
    if (rb_multi_ractor_p()) return false;

    st_insert(blocks_assuming_single_ractor_mode, (st_data_t)block, 1);
    return true;
}

static st_table *blocks_assuming_stable_global_constant_state;

// Assume that the global constant state has not changed since call to this function.
// Can raise NoMemoryError.
void
assume_stable_global_constant_state(block_t *block) {
    st_insert(blocks_assuming_stable_global_constant_state, (st_data_t)block, 1);
}

static int
mark_and_pin_keys_i(st_data_t k, st_data_t v, st_data_t ignore)
{
    rb_gc_mark((VALUE)k);

    return ST_CONTINUE;
}

// GC callback during compaction
static void
yjit_root_update_references(void *ptr)
{
    yjit_branches_update_references();
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

// Custom type for interacting with the GC
// TODO: make this write barrier protected
static const rb_data_type_t yjit_root_type = {
    "yjit_root",
    {yjit_root_mark, yjit_root_free, yjit_root_memsize, yjit_root_update_references},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static int
block_set_invalidate_i(st_data_t key, st_data_t v, st_data_t ignore)
{
    block_t *version = (block_t *)key;

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
    // TODO: implement
}

// Remove a block from the method lookup dependency table
static void
remove_method_lookup_dependency(block_t *block)
{
    if (!block->receiver_klass) return;
    RUBY_ASSERT(block->callee_cme); // callee_cme should be set when receiver_klass is set

    st_data_t image;
    st_data_t key = (st_data_t)block->receiver_klass;
    if (st_lookup(method_lookup_dependency, key, &image)) {
        struct rb_id_table *id2blocks = (void *)image;
        const rb_callable_method_entry_t *cme = (void *)block->callee_cme;
        ID mid = cme->called_id;

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
remove_cme_validity_dependency(block_t *block)
{
    if (!block->callee_cme) return;

    st_data_t blocks;
    if (st_lookup(cme_validity_dependency, block->callee_cme, &blocks)) {
        st_table *block_set = (st_table *)blocks;

        st_data_t block_as_st_data = (st_data_t)block;
        (void)st_delete(block_set, &block_as_st_data, NULL);
    }
}

void
yjit_unlink_method_lookup_dependency(block_t *block)
{
    remove_method_lookup_dependency(block);
    remove_cme_validity_dependency(block);
}

void
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

void
rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec)
{
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
    RB_VM_LOCK_ENTER();
    VALUE *encoded = (VALUE *)iseq->body->iseq_encoded;

    // Compile a block version starting at the first instruction
    uint8_t* code_ptr = gen_entry_point(iseq, 0, ec);

    if (code_ptr)
    {
        // Map the code address to the corresponding opcode
        int first_opcode = yjit_opcode_at_pc(iseq, &encoded[0]);
        map_addr2insn(code_ptr, first_opcode);
        encoded[0] = (VALUE)code_ptr;
    }

    RB_VM_LOCK_LEAVE();
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

/* Get the address of the the code associated with a YJIT::Block */
static VALUE
block_address(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &yjit_block_type, block);
    uint8_t* code_addr = cb_get_ptr(cb, block->start_pos);
    return LONG2NUM((intptr_t)code_addr);
}

/* Get the machine code for YJIT::Block as a binary string */
static VALUE
block_code(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &yjit_block_type, block);

    return (VALUE)rb_str_new(
        (const char*)cb->mem_block + block->start_pos,
        block->end_pos - block->start_pos
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

static int
block_invalidation_iterator(st_data_t key, st_data_t value, st_data_t data) {
    block_t *block = (block_t *)key;
    invalidate_block_version(block); // Thankfully, st_table supports deleteing while iterating
    return ST_CONTINUE;
}

/* Called when a basic operation is redefined */
void
rb_yjit_bop_redefined(VALUE klass, const rb_method_entry_t *me, enum ruby_basic_operators bop)
{
    if (blocks_assuming_bops) {
        st_foreach(blocks_assuming_bops, block_invalidation_iterator, 0);
    }
}

/* Called when the constant state changes */
void
rb_yjit_constant_state_changed(void)
{
    if (blocks_assuming_stable_global_constant_state) {
        st_foreach(blocks_assuming_stable_global_constant_state, block_invalidation_iterator, 0);
    }
}

// Callback from the opt_setinlinecache instruction in the interpreter
void
yjit_constant_ic_update(const rb_iseq_t *iseq, IC ic)
{
    RB_VM_LOCK_ENTER();
    rb_vm_barrier(); // Stop other ractors since we are going to patch machine code.
    {

        const struct rb_iseq_constant_body *const body = iseq->body;
        VALUE *code = body->iseq_encoded;

        // This should come from a running iseq, so direct threading translation
        // should have been done
        RUBY_ASSERT(FL_TEST((VALUE)iseq, ISEQ_TRANSLATED));
        RUBY_ASSERT(ic->get_insn_idx < body->iseq_size);
        RUBY_ASSERT(rb_vm_insn_addr2insn((const void *)code[ic->get_insn_idx]) == BIN(opt_getinlinecache));

        // Find the matching opt_getinlinecache and invalidate all the blocks there
        RUBY_ASSERT(insn_op_type(BIN(opt_getinlinecache), 1) == TS_IC);
        if (ic == (IC)code[ic->get_insn_idx + 1 + 1]) {
            rb_yjit_block_array_t getinlinecache_blocks = yjit_get_version_array(iseq, ic->get_insn_idx);
            rb_darray_for(getinlinecache_blocks, i) {
                block_t *block = rb_darray_get(getinlinecache_blocks, i);
                invalidate_block_version(block);
            }
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
        st_foreach(blocks_assuming_single_ractor_mode, block_invalidation_iterator, 0);
    }
}

#if HAVE_LIBCAPSTONE
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

static VALUE
at_exit_print_stats(RB_BLOCK_CALL_FUNC_ARGLIST(yieldarg, data))
{
    // Defined in yjit.rb
    rb_funcall(mYjit, rb_intern("_print_stats"), 0);
    return Qnil;
}

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

// Primitive called in yjit.rb. Export all runtime counters as a Ruby hash.
static VALUE
get_stat_counters(rb_execution_context_t *ec, VALUE self)
{
#if RUBY_DEBUG
    if (!rb_yjit_opts.gen_stats) return Qnil;

    VALUE hash = rb_hash_new();
    RB_VM_LOCK_ENTER();
    {
        int64_t *counter_reader = (int64_t *)&yjit_runtime_counters;
        int64_t *counter_reader_end = &yjit_runtime_counters.last_member;

        // Iterate through comma separated counter name list
        char *name_reader = yjit_counter_names;
        char *counter_name_end = yjit_counter_names + sizeof(yjit_counter_names);
        while (name_reader < counter_name_end && counter_reader < counter_reader_end) {
            if (*name_reader == ',' || *name_reader == ' ') {
                name_reader++;
                continue;
            }

            // Compute name of counter name
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
    }
    RB_VM_LOCK_LEAVE();
    return hash;
#else
    return Qnil;
#endif // if RUBY_DEBUG
}

// Primitive called in yjit.rb. Zero out all the counters.
static VALUE
reset_stats_bang(rb_execution_context_t *ec, VALUE self)
{
#if RUBY_DEBUG
    vm_insns_count = 0;
    rb_compiled_iseq_count = 0;
    memset(&exit_op_count, 0, sizeof(exit_op_count));
    memset(&yjit_runtime_counters, 0, sizeof(yjit_runtime_counters));
#endif // if RUBY_DEBUG
    return Qnil;
}

#include "yjit.rbinc"

#if RUBY_DEBUG
// implementation for --yjit-stats

void
rb_yjit_collect_vm_usage_insn(int insn)
{
    vm_insns_count++;
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

const VALUE *
rb_yjit_count_side_exit_op(const VALUE *exit_pc)
{
    int insn = rb_vm_insn_addr2opcode((const void *)*exit_pc);
    exit_op_count[insn]++;
    return exit_pc; // This function must return exit_pc!
}

struct insn_count {
    int64_t insn;
    int64_t count;
};

static int
insn_count_sort_comp(const void *a, const void *b)
{
    const struct insn_count *count_a = a;
    const struct insn_count *count_b = b;
    if (count_a->count > count_b->count) {
        return -1;
    }
    else if (count_a->count < count_b->count) {
        return 1;
    }
    return 0;
}

static struct insn_count insn_sorting_buffer[VM_INSTRUCTION_SIZE];
static const struct insn_count *
sort_insn_count_array(int64_t *array)
{
    for (int i = 0; i < VM_INSTRUCTION_SIZE; i++) {
        insn_sorting_buffer[i] = (struct insn_count) { i, array[i] };
    }
    qsort(insn_sorting_buffer, VM_INSTRUCTION_SIZE, sizeof(insn_sorting_buffer[0]), &insn_count_sort_comp);
    return insn_sorting_buffer;
}

// Compute the total interpreter exit count
static int64_t
calc_total_exit_count()
{
    size_t total_exit_count = 0;
    for (int i = 0; i < VM_INSTRUCTION_SIZE; i++) {
        total_exit_count += exit_op_count[i];
    }

    return total_exit_count;
}

static void
print_insn_count_buffer(int how_many, int left_pad)
{
    size_t total_exit_count = calc_total_exit_count();

    // Sort the exit ops by decreasing frequency
    const struct insn_count *sorted_exit_ops = sort_insn_count_array(exit_op_count);

    // Compute the longest instruction name and top10_exit_count
    size_t longest_insn_len = 0;
    size_t top10_exit_count = 0;
    for (int i = 0; i < how_many; i++) {
        const char *instruction_name = insn_name(sorted_exit_ops[i].insn);
        size_t len = strlen(instruction_name);
        if (len > longest_insn_len) {
            longest_insn_len = len;
        }
        top10_exit_count += sorted_exit_ops[i].count;
    }

    double top10_exit_percent = 100.0 * top10_exit_count / total_exit_count;

    fprintf(stderr, "top-%d most frequent exit ops (%.1f%% of exits):\n", how_many, top10_exit_percent);

    // Print the top-N most frequent exit counts
    for (int i = 0; i < how_many; i++) {
        const char *instruction_name = insn_name(sorted_exit_ops[i].insn);
        size_t padding = left_pad + longest_insn_len - strlen(instruction_name);
        for (size_t j = 0; j < padding; j++) {
            fputc(' ', stderr);
        }
        double percent = 100 * sorted_exit_ops[i].count / (double)total_exit_count;
        fprintf(stderr, "%s: %10" PRId64 " (%.1f%%)\n", instruction_name, sorted_exit_ops[i].count, percent);
    }
}

__attribute__((destructor))
static void
print_yjit_stats(void)
{
    if (!rb_yjit_opts.gen_stats) {
        return;
    }

    // Compute the total exit count
    int64_t total_exit_count = calc_total_exit_count();

    // Number of instructions that finish executing in YJIT. See :count-placement:.
    int64_t retired_in_yjit = yjit_runtime_counters.exec_instruction - total_exit_count;

    // Average length of instruction sequences executed by YJIT
    double avg_len_in_yjit = (double)retired_in_yjit / total_exit_count;

    // Proportion of instructions that retire in YJIT
    int64_t total_insns_count = retired_in_yjit + vm_insns_count;
    double ratio = retired_in_yjit / (double)total_insns_count;

    fprintf(stderr, "compiled_iseq_count:   %10" PRId64 "\n", rb_compiled_iseq_count);
    fprintf(stderr, "inline_code_size:      %10d\n", cb->write_pos);
    fprintf(stderr, "outlined_code_size:    %10d\n", ocb->write_pos);

    fprintf(stderr, "total_exit_count:      %10" PRId64 "\n", total_exit_count);
    fprintf(stderr, "total_insns_count:     %10" PRId64 "\n", total_insns_count);
    fprintf(stderr, "vm_insns_count:        %10" PRId64 "\n", vm_insns_count);
    fprintf(stderr, "yjit_insns_count:      %10" PRId64 "\n", yjit_runtime_counters.exec_instruction);
    fprintf(stderr, "ratio_in_yjit:         %9.1f%%\n", ratio * 100);
    fprintf(stderr, "avg_len_in_yjit:       %10.1f\n", avg_len_in_yjit);

    // Print the top-10 most frequent exit ops
    print_insn_count_buffer(10, 4);
}
#endif // if RUBY_DEBUG

void
rb_yjit_iseq_mark(const struct rb_iseq_constant_body *body)
{
    rb_darray_for(body->yjit_blocks, version_array_idx) {
        rb_yjit_block_array_t version_array = rb_darray_get(body->yjit_blocks, version_array_idx);

        rb_darray_for(version_array, block_idx) {
            block_t *block = rb_darray_get(version_array, block_idx);

            rb_gc_mark_movable((VALUE)block->blockid.iseq);
            rb_gc_mark_movable(block->receiver_klass);
            rb_gc_mark_movable(block->callee_cme);

            // Walk over references to objects in generated code.
            uint32_t *offset_element;
            rb_darray_foreach(block->gc_object_offsets, offset_idx, offset_element) {
                uint32_t offset_to_value = *offset_element;
                uint8_t *value_address = cb_get_ptr(cb, offset_to_value);

                VALUE object;
                memcpy(&object, value_address, SIZEOF_VALUE);
                rb_gc_mark_movable(object);
            }
        }
    }
}

void
rb_yjit_iseq_update_references(const struct rb_iseq_constant_body *body)
{
    rb_darray_for(body->yjit_blocks, version_array_idx) {
        rb_yjit_block_array_t version_array = rb_darray_get(body->yjit_blocks, version_array_idx);

        rb_darray_for(version_array, block_idx) {
            block_t *block = rb_darray_get(version_array, block_idx);

            block->blockid.iseq = (const rb_iseq_t *)rb_gc_location((VALUE)block->blockid.iseq);

            block->receiver_klass = rb_gc_location(block->receiver_klass);
            block->callee_cme = rb_gc_location(block->callee_cme);

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
                    memcpy(value_address, &possibly_moved, SIZEOF_VALUE);
                }
            }
        }
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

void
rb_yjit_init(struct rb_yjit_options *options)
{
    if (!yjit_scrape_successful || !PLATFORM_SUPPORTED_P) {
        return;
    }

    rb_yjit_opts = *options;
    rb_yjit_opts.yjit_enabled = true;

    // Normalize command-line options
    if (rb_yjit_opts.call_threshold < 1) {
        rb_yjit_opts.call_threshold = 2;
    }

    blocks_assuming_stable_global_constant_state = st_init_numtable();
    blocks_assuming_single_ractor_mode = st_init_numtable();
    blocks_assuming_bops = st_init_numtable();

    yjit_init_core();
    yjit_init_codegen();

    // YJIT Ruby module
    mYjit = rb_define_module("YJIT");
    rb_define_module_function(mYjit, "blocks_for", yjit_blocks_for, 1);

    // YJIT::Block (block version, code block)
    cYjitBlock = rb_define_class_under(mYjit, "Block", rb_cObject);
    rb_define_method(cYjitBlock, "address", block_address, 0);
    rb_define_method(cYjitBlock, "code", block_code, 0);
    rb_define_method(cYjitBlock, "iseq_start_index", iseq_start_index, 0);
    rb_define_method(cYjitBlock, "iseq_end_index", iseq_end_index, 0);

    // YJIT disassembler interface
#if HAVE_LIBCAPSTONE
    cYjitDisasm = rb_define_class_under(mYjit, "Disasm", rb_cObject);
    rb_define_alloc_func(cYjitDisasm, yjit_disasm_init);
    rb_define_method(cYjitDisasm, "disasm", yjit_disasm, 2);
    cYjitDisasmInsn = rb_struct_define_under(cYjitDisasm, "Insn", "address", "mnemonic", "op_str", NULL);
    cYjitCodeComment = rb_struct_define_under(cYjitDisasm, "Comment", "address", "comment");
#endif

    if (RUBY_DEBUG && rb_yjit_opts.gen_stats) {
        // Setup at_exit callback for printing out counters
        rb_block_call(rb_mKernel, rb_intern("at_exit"), 0, NULL, at_exit_print_stats, Qfalse);
    }

    // Make dependency tables
    method_lookup_dependency = st_init_numtable();
    cme_validity_dependency = st_init_numtable();

    // Initialize the GC hooks
    struct yjit_root_struct *root;
    VALUE yjit_root = TypedData_Make_Struct(0, struct yjit_root_struct, &yjit_root_type, root);
    rb_gc_register_mark_object(yjit_root);
}
