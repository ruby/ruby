#include <assert.h>
#include "insns.inc"
#include "internal.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "internal/compile.h"
#include "internal/class.h"
#include "insns_info.inc"
#include "ujit.h"
#include "ujit_iface.h"
#include "ujit_codegen.h"
#include "ujit_core.h"
#include "ujit_hooks.inc"
#include "ujit.rbinc"
#include "darray.h"

#if HAVE_LIBCAPSTONE
#include <capstone/capstone.h>
#endif

VALUE cUjitBlock;
VALUE cUjitDisasm;
VALUE cUjitDisasmInsn;

bool rb_ujit_enabled;

static int64_t vm_insns_count = 0;
int64_t rb_ujit_exec_insns_count = 0;
static int64_t exit_op_count[VM_INSTRUCTION_SIZE] = { 0 };
int64_t rb_compiled_iseq_count = 0;

// Machine code blocks (executable memory)
extern codeblock_t *cb;
extern codeblock_t *ocb;

// Hash table of encoded instructions
extern st_table *rb_encoded_insn_data;

struct rb_ujit_options rb_ujit_opts;

static const rb_data_type_t ujit_block_type = {
    "UJIT/Block",
    {0, 0, 0, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

// Write the uJIT entry point pre-call bytes
void 
cb_write_pre_call_bytes(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(ujit_with_ec_pre_call_bytes); ++i)
        cb_write_byte(cb, ujit_with_ec_pre_call_bytes[i]);
}

// Write the uJIT exit post-call bytes
void 
cb_write_post_call_bytes(codeblock_t* cb)
{
    for (size_t i = 0; i < sizeof(ujit_with_ec_post_call_bytes); ++i)
        cb_write_byte(cb, ujit_with_ec_post_call_bytes[i]);
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
        rb_bug("ujit: failed to find info for original instruction while dealing with addr2insn");
    }
}

int
opcode_at_pc(const rb_iseq_t *iseq, const VALUE *pc)
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
check_cfunc_dispatch(VALUE receiver, struct rb_call_data *cd, void *callee, rb_callable_method_entry_t *compile_time_cme)
{
    if (METHOD_ENTRY_INVALIDATED(compile_time_cme)) {
        rb_bug("ujit: output code uses invalidated cme %p", (void *)compile_time_cme);
    }

    bool callee_correct = false;
    const rb_callable_method_entry_t *cme = rb_callable_method_entry(CLASS_OF(receiver), vm_ci_mid(cd->ci));
    if (cme->def->type == VM_METHOD_TYPE_CFUNC) {
        const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(cme->def, body.cfunc);
        if ((void *)cfunc->func == callee) {
            callee_correct = true;
        }
    }
    if (!callee_correct) {
        rb_bug("ujit: output code calls wrong method cd->cc->klass: %p", (void *)cd->cc->klass);
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
struct ujit_root_struct {
    int unused; // empty structs are not legal in C99
};

// Map cme_or_cc => [[iseq, offset]]. An entry in the map means compiled code at iseq[offset]
// is only valid when cme_or_cc is valid
static st_table *method_lookup_dependency;

struct compiled_region {
    block_t *block;
};

typedef rb_darray(struct compiled_region) block_array_t;

static int
add_lookup_dependency_i(st_data_t *key, st_data_t *value, st_data_t data, int existing)
{
    struct compiled_region *region = (struct compiled_region *)data;

    block_array_t regions = NULL;
    if (existing) {
        regions = (block_array_t )*value;
    }
    if (!rb_darray_append(&regions, *region)) {
        rb_bug("ujit: failed to add method lookup dependency"); // TODO: we could bail out of compiling instead
    }

    *value = (st_data_t)regions;
    return ST_CONTINUE;
}

// Remember that the currently compiling region is only valid while cme and cc are valid
void
assume_method_lookup_stable(const struct rb_callcache *cc, const rb_callable_method_entry_t *cme, block_t *block)
{
    RUBY_ASSERT(block != NULL);
    RUBY_ASSERT(block->dependencies.cc == 0 && block->dependencies.cme == 0);
    struct compiled_region region = { .block = block };
    st_update(method_lookup_dependency, (st_data_t)cme, add_lookup_dependency_i, (st_data_t)&region);
    block->dependencies.cme = (VALUE)cme;
    st_update(method_lookup_dependency, (st_data_t)cc, add_lookup_dependency_i, (st_data_t)&region);
    block->dependencies.cc = (VALUE)cc;
}

static int
ujit_root_mark_i(st_data_t k, st_data_t v, st_data_t ignore)
{
    // Lifetime notes: cc and cme get added in pairs into the table. One of
    // them should become invalid before dying. When one of them invalidate we
    // remove the pair from the table. Blocks remove themself from the table
    // when they die.
    rb_gc_mark_movable((VALUE)k);

    return ST_CONTINUE;
}

static int
method_lookup_dep_table_update_keys(st_data_t *key, st_data_t *value, st_data_t argp, int existing)
{
    *key = rb_gc_location(rb_gc_location((VALUE)*key));

    return ST_CONTINUE;
}

static int
replace_all(st_data_t key, st_data_t value, st_data_t argp, int error)
{
    return ST_REPLACE;
}

// GC callback during compaction
static void
ujit_root_update_references(void *ptr)
{
    if (method_lookup_dependency) {
        if (st_foreach_with_replace(method_lookup_dependency, replace_all, method_lookup_dep_table_update_keys, 0)) {
            RUBY_ASSERT(false);
        }
    }
}

// GC callback during mark phase
static void
ujit_root_mark(void *ptr)
{
    if (method_lookup_dependency) {
        st_foreach(method_lookup_dependency, ujit_root_mark_i, 0);
    }
}

static void
ujit_root_free(void *ptr)
{
    // Do nothing. The root lives as long as the process.
}

static size_t
ujit_root_memsize(const void *ptr)
{
    // Count off-gc-heap allocation size of the dependency table
    return st_memsize(method_lookup_dependency); // TODO: more accurate accounting
}

// Custom type for interacting with the GC
// TODO: compaction support
// TODO: make this write barrier protected
static const rb_data_type_t ujit_root_type = {
    "ujit_root",
    {ujit_root_mark, ujit_root_free, ujit_root_memsize, ujit_root_update_references},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

// Callback when cme or cc become invalid
void
rb_ujit_method_lookup_change(VALUE cme_or_cc)
{
    if (!method_lookup_dependency)
        return;

    RB_VM_LOCK_ENTER();

    RUBY_ASSERT(IMEMO_TYPE_P(cme_or_cc, imemo_ment) || IMEMO_TYPE_P(cme_or_cc, imemo_callcache));

    // Invalidate all regions that depend on the cme or cc
    st_data_t key = (st_data_t)cme_or_cc, image;
    if (st_delete(method_lookup_dependency, &key, &image)) {
        block_array_t array = (void *)image;
        struct compiled_region *elem;

        rb_darray_foreach(array, i, elem) {
            invalidate_block_version(elem->block);
        }

        rb_darray_free(array);
    }

    RB_VM_LOCK_LEAVE();
}

// Remove a block from the method lookup dependency table
static void
remove_method_lookup_dependency(VALUE cc_or_cme, block_t *block)
{
    st_data_t key = (st_data_t)cc_or_cme, image;
    if (st_lookup(method_lookup_dependency, key, &image)) {
        block_array_t array = (void *)image;
        struct compiled_region *elem;

        // Find the block we are removing
        rb_darray_foreach(array, i, elem) {
            if (elem->block == block) {
                // Remove the current element by moving the last element here.
                // Order in the region array doesn't matter.
                *elem = rb_darray_get(array, rb_darray_size(array) - 1);
                rb_darray_pop_back(array);
                break;
            }
        }

        if (rb_darray_size(array) == 0) {
            st_delete(method_lookup_dependency, &key, NULL);
            rb_darray_free(array);
        }
    }
}

void
ujit_unlink_method_lookup_dependency(block_t *block)
{
    if (block->dependencies.cc) remove_method_lookup_dependency(block->dependencies.cc, block);
    if (block->dependencies.cme) remove_method_lookup_dependency(block->dependencies.cme, block);
}

void
rb_ujit_compile_iseq(const rb_iseq_t *iseq)
{
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
    RB_VM_LOCK_ENTER();
    VALUE *encoded = (VALUE *)iseq->body->iseq_encoded;

    // Compile a block version starting at the first instruction
    uint8_t* code_ptr = gen_entry_point(iseq, 0);

    if (code_ptr)
    {
        // Map the code address to the corresponding opcode
        int first_opcode = opcode_at_pc(iseq, &encoded[0]);
        map_addr2insn(code_ptr, first_opcode);
        encoded[0] = (VALUE)code_ptr;
    }

    RB_VM_LOCK_LEAVE();
#endif
}

struct ujit_block_itr {
    const rb_iseq_t *iseq;
    VALUE list;
};

/* Get a list of the UJIT blocks associated with `rb_iseq` */
static VALUE
ujit_blocks_for(VALUE mod, VALUE rb_iseq)
{
    if (CLASS_OF(rb_iseq) != rb_cISeq) {
        return rb_ary_new();
    }

    const rb_iseq_t *iseq = rb_iseqw_to_iseq(rb_iseq);
    block_t **element;
    VALUE all_versions = rb_ary_new();

    rb_darray_foreach(iseq->body->ujit_blocks, idx, element) {
        for (block_t *version = *element; version; version = version->next) {
            VALUE rb_block = TypedData_Wrap_Struct(cUjitBlock, &ujit_block_type, version);
            rb_ary_push(all_versions, rb_block);
        }
    }

    return all_versions;
}

static VALUE
ujit_install_entry(VALUE mod, VALUE iseq)
{
    if (CLASS_OF(iseq) != rb_cISeq) {
	rb_raise(rb_eTypeError, "not an InstructionSequence");
    }
    rb_ujit_compile_iseq(rb_iseqw_to_iseq(iseq));
    return iseq;
}

/* Get the address of the the code associated with a UJIT::Block */
static VALUE
block_address(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &ujit_block_type, block);
    uint8_t* code_addr = cb_get_ptr(cb, block->start_pos);
    return LONG2NUM((intptr_t)code_addr);
}

/* Get the machine code for UJIT::Block as a binary string */
static VALUE
block_code(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &ujit_block_type, block);

    return (VALUE)rb_str_new(
        (const char*)cb->mem_block + block->start_pos,
        block->end_pos - block->start_pos
    );
}

/* Get the start index in the Instruction Sequence that corresponds to this
 * UJIT::Block */
static VALUE
iseq_start_index(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &ujit_block_type, block);

    return INT2NUM(block->blockid.idx);
}

/* Get the end index in the Instruction Sequence that corresponds to this
 * UJIT::Block */
static VALUE
iseq_end_index(VALUE self)
{
    block_t * block;
    TypedData_Get_Struct(self, block_t, &ujit_block_type, block);

    return INT2NUM(block->end_idx);
}

/* Called when a basic operation is redefined */
void
rb_ujit_bop_redefined(VALUE klass, const rb_method_entry_t *me, enum ruby_basic_operators bop)
{
    //fprintf(stderr, "bop redefined\n");
}

/* Called when the constant state changes */
void
rb_ujit_constant_state_changed(void)
{
    //fprintf(stderr, "bop redefined\n");
}

#if HAVE_LIBCAPSTONE
static const rb_data_type_t ujit_disasm_type = {
    "UJIT/Disasm",
    {0, (void(*)(void *))cs_close, 0, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
ujit_disasm_init(VALUE klass)
{
    csh * handle;
    VALUE disasm = TypedData_Make_Struct(klass, csh, &ujit_disasm_type, handle);
    cs_open(CS_ARCH_X86, CS_MODE_64, handle);
    return disasm;
}

static VALUE
ujit_disasm(VALUE self, VALUE code, VALUE from)
{
    size_t count;
    csh * handle;
    cs_insn *insns;

    TypedData_Get_Struct(self, csh, &ujit_disasm_type, handle);
    count = cs_disasm(*handle, (uint8_t*)StringValuePtr(code), RSTRING_LEN(code), NUM2INT(from), 0, &insns);
    VALUE insn_list = rb_ary_new_capa(count);

    for (size_t i = 0; i < count; i++) {
        VALUE vals = rb_ary_new_from_args(3, LONG2NUM(insns[i].address),
                rb_str_new2(insns[i].mnemonic),
                rb_str_new2(insns[i].op_str));
        rb_ary_push(insn_list, rb_struct_alloc(cUjitDisasmInsn, vals));
    }
    cs_free(insns, count);
    return insn_list;
}
#endif

#if RUBY_DEBUG
// implementation for --ujit-stats

void
rb_ujit_collect_vm_usage_insn(int insn)
{
    vm_insns_count++;
}

const VALUE *
rb_ujit_count_side_exit_op(const VALUE *exit_pc)
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

static void
print_insn_count_buffer(const struct insn_count *buffer, int how_many, int left_pad)
{
    size_t longest_insn_len = 0;
    size_t total_exit_count = 0;

    for (int i = 0; i < how_many; i++) {
        const char *instruction_name = insn_name(buffer[i].insn);
        size_t len = strlen(instruction_name);
        if (len > longest_insn_len) {
            longest_insn_len = len;
        }
        total_exit_count += buffer[i].count;
    }

    fprintf(stderr, "total_exit_count:      %10ld\n", total_exit_count);
    fprintf(stderr, "most frequent exit op:\n");

    for (int i = 0; i < how_many; i++) {
        const char *instruction_name = insn_name(buffer[i].insn);
        size_t padding = left_pad + longest_insn_len - strlen(instruction_name);
        for (size_t j = 0; j < padding; j++) {
            fputc(' ', stderr);
        }
        double percent = 100 * buffer[i].count / (double)total_exit_count;
        fprintf(stderr, "%s: %10" PRId64 " (%.1f%%)\n", instruction_name, buffer[i].count, percent);
    }
}

__attribute__((destructor))
static void
print_ujit_stats(void)
{
    if (!rb_ujit_opts.gen_stats) return;

    const struct insn_count *sorted_exit_ops = sort_insn_count_array(exit_op_count);

    double total_insns_count = vm_insns_count + rb_ujit_exec_insns_count;
    double ratio = rb_ujit_exec_insns_count / total_insns_count;

    fprintf(stderr, "compiled_iseq_count:   %10" PRId64 "\n", rb_compiled_iseq_count);
    fprintf(stderr, "main_block_code_size:  %6.1f MiB\n", ((double)cb->write_pos) / 1048576.0);
    fprintf(stderr, "side_block_code_size:  %6.1f MiB\n", ((double)ocb->write_pos) / 1048576.0);
    fprintf(stderr, "vm_insns_count:        %10" PRId64 "\n", vm_insns_count);
    fprintf(stderr, "ujit_exec_insns_count: %10" PRId64 "\n", rb_ujit_exec_insns_count);
    fprintf(stderr, "ratio_in_ujit:         %9.1f%%\n", ratio * 100);
    print_insn_count_buffer(sorted_exit_ops, 10, 4);
}
#endif // if RUBY_DEBUG

void
rb_ujit_iseq_mark(const struct rb_iseq_constant_body *body)
{
    block_t **element;
    rb_darray_foreach(body->ujit_blocks, idx, element) {
        for (block_t *block = *element; block; block = block->next) {
            rb_gc_mark_movable((VALUE)block->blockid.iseq);

            rb_gc_mark_movable(block->dependencies.cc);
            rb_gc_mark_movable(block->dependencies.cme);
            rb_gc_mark_movable(block->dependencies.iseq);
        }
    }
}

void
rb_ujit_iseq_update_references(const struct rb_iseq_constant_body *body)
{
    block_t **element;
    rb_darray_foreach(body->ujit_blocks, idx, element) {
        for (block_t *block = *element; block; block = block->next) {
            block->blockid.iseq = (const rb_iseq_t *)rb_gc_location((VALUE)block->blockid.iseq);

            block->dependencies.cc = rb_gc_location(block->dependencies.cc);
            block->dependencies.cme = rb_gc_location(block->dependencies.cme);
            block->dependencies.iseq = rb_gc_location(block->dependencies.iseq);
        }
    }
}

void
rb_ujit_iseq_free(const struct rb_iseq_constant_body *body)
{
    block_t **element;
    rb_darray_foreach(body->ujit_blocks, idx, element) {
        block_t *block = *element;
        while (block) {
            block_t *next = block->next;
            ujit_free_block(block);
            block = next;
        }
    }

    rb_darray_free(body->ujit_blocks);
}

void
rb_ujit_init(struct rb_ujit_options *options)
{
    if (!ujit_scrape_successful || !PLATFORM_SUPPORTED_P)
    {
        return;
    }

    rb_ujit_opts = *options;

    rb_ujit_enabled = true;

    ujit_init_core();
    ujit_init_codegen();

    // UJIT Ruby module
    VALUE mUjit = rb_define_module("UJIT");
    rb_define_module_function(mUjit, "install_entry", ujit_install_entry, 1);
    rb_define_module_function(mUjit, "blocks_for", ujit_blocks_for, 1);

    // UJIT::Block (block version, code block)
    cUjitBlock = rb_define_class_under(mUjit, "Block", rb_cObject);
    rb_define_method(cUjitBlock, "address", block_address, 0);
    rb_define_method(cUjitBlock, "code", block_code, 0);
    rb_define_method(cUjitBlock, "iseq_start_index", iseq_start_index, 0);
    rb_define_method(cUjitBlock, "iseq_end_index", iseq_end_index, 0);

    // UJIT disassembler interface
#if HAVE_LIBCAPSTONE
    cUjitDisasm = rb_define_class_under(mUjit, "Disasm", rb_cObject);
    rb_define_alloc_func(cUjitDisasm, ujit_disasm_init);
    rb_define_method(cUjitDisasm, "disasm", ujit_disasm, 2);
    cUjitDisasmInsn = rb_struct_define_under(cUjitDisasm, "Insn", "address", "mnemonic", "op_str", NULL);
#endif

    // Initialize the GC hooks
    method_lookup_dependency = st_init_numtable();
    struct ujit_root_struct *root;
    VALUE ujit_root = TypedData_Make_Struct(0, struct ujit_root_struct, &ujit_root_type, root);
    rb_gc_register_mark_object(ujit_root);
}
