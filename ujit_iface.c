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

bool rb_ujit_enabled;

// Hash table of encoded instructions
extern st_table *rb_encoded_insn_data;

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

// GC root for interacting with the GC
struct ujit_root_struct {};

// Map cme_or_cc => [[iseq, offset]]. An entry in the map means compiled code at iseq[offset]
// is only valid when cme_or_cc is valid
static st_table *method_lookup_dependency;

struct compiled_region_array {
    int32_t size;
    int32_t capa;
    struct compiled_region {
        const rb_iseq_t *iseq;
        size_t start_idx;
        uint8_t *code;
    } data[];
};

// Add an element to a region array, or allocate a new region array.
static struct compiled_region_array *
add_compiled_region(struct compiled_region_array *array, const rb_iseq_t *iseq, size_t start_idx, uint8_t *code)
{
    if (!array) {
        // Allocate a brand new array with space for one
        array = malloc(sizeof(*array) + sizeof(struct compiled_region));
        if (!array) {
            return NULL;
        }
        array->size = 0;
        array->capa = 1;
    }
    if (array->size == INT32_MAX) {
        return NULL;
    }
    // Check if the region is already present
    for (int32_t i = 0; i < array->size; i++) {
        if (array->data[i].iseq == iseq && array->data[i].start_idx == start_idx) {
            return array;
        }
    }
    if (array->size + 1 > array->capa) {
        // Double the array's capacity.
        int64_t double_capa = ((int64_t)array->capa) * 2;
        int32_t new_capa = (int32_t)double_capa;
        if (new_capa != double_capa) {
            return NULL;
        }
        array = realloc(array, sizeof(*array) + new_capa * sizeof(struct compiled_region));
        if (array == NULL) {
            return NULL;
        }
        array->capa = new_capa;
    }

    int32_t size = array->size;
    array->data[size].iseq = iseq;
    array->data[size].start_idx = start_idx;
    array->data[size].code = code;
    array->size++;
    return array;
}

static int
add_lookup_dependency_i(st_data_t *key, st_data_t *value, st_data_t data, int existing)
{
    ctx_t *ctx = (ctx_t *)data;
    struct compiled_region_array *regions = NULL;
    if (existing) {
        regions = (struct compiled_region_array *)*value;
    }
    regions = add_compiled_region(regions, ctx->iseq, ctx->start_idx, ctx->code_ptr);
    if (!regions) {
        rb_bug("ujit: failed to add method lookup dependency"); // TODO: we could bail out of compiling instead
    }
    *value = (st_data_t)regions;
    return ST_CONTINUE;
}

// Remember that the currently compiling region is only valid while cme and cc are valid
void
assume_method_lookup_stable(const struct rb_callcache *cc, const rb_callable_method_entry_t *cme,  ctx_t *ctx)
{
    st_update(method_lookup_dependency, (st_data_t)cme, add_lookup_dependency_i, (st_data_t)ctx);
    st_update(method_lookup_dependency, (st_data_t)cc, add_lookup_dependency_i, (st_data_t)ctx);
    // FIXME: This is a leak! When either the cme or the cc become invalid, the other also needs to go
}

static int
ujit_root_mark_i(st_data_t k, st_data_t v, st_data_t ignore)
{
    // FIXME: This leaks everything that end up in the dependency table!
    // One way to deal with this is with weak references...
    rb_gc_mark((VALUE)k);
    struct compiled_region_array *regions = (void *)v;
    for (int32_t i = 0; i < regions->size; i++) {
        rb_gc_mark((VALUE)regions->data[i].iseq);
    }

    return ST_CONTINUE;
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
    {ujit_root_mark, ujit_root_free, ujit_root_memsize, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

// Callback when cme or cc become invalid
void
rb_ujit_method_lookup_change(VALUE cme_or_cc)
{
    if (!method_lookup_dependency) return;

    RUBY_ASSERT(IMEMO_TYPE_P(cme_or_cc, imemo_ment) || IMEMO_TYPE_P(cme_or_cc, imemo_callcache));

    st_data_t image;
    if (st_lookup(method_lookup_dependency, (st_data_t)cme_or_cc, &image)) {
        struct compiled_region_array *array = (void *)image;
        // Invalidate all regions that depend on the cme or cc
        for (int32_t i = 0; i < array->size; i++) {
            struct compiled_region *region = &array->data[i];
            const struct rb_iseq_constant_body *body = region->iseq->body;
            RUBY_ASSERT((unsigned int)region->start_idx < body->iseq_size);
            // Restore region address to interpreter address in bytecode sequence
            if (body->iseq_encoded[region->start_idx] == (VALUE)region->code) {
                const void *const *code_threading_table = rb_vm_get_insns_address_table();
                int opcode = rb_vm_insn_addr2insn(region->code);
                body->iseq_encoded[region->start_idx] = (VALUE)code_threading_table[opcode];
                if (UJIT_DUMP_MODE > 0) {
                    fprintf(stderr, "cc_or_cme=%p now out of date. Restored idx=%u in iseq=%p\n", (void *)cme_or_cc, (unsigned)region->start_idx, (void *)region->iseq);
                }
            }
        }

        array->size = 0;
    }
}

void
rb_ujit_compile_iseq(const rb_iseq_t *iseq)
{
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
    RB_VM_LOCK_ENTER();
    VALUE *encoded = (VALUE *)iseq->body->iseq_encoded;

    unsigned int insn_idx;
    unsigned int next_ujit_idx = 0;

    for (insn_idx = 0; insn_idx < iseq->body->iseq_size; /* */) {
        int insn = opcode_at_pc(iseq, &encoded[insn_idx]);
        int len = insn_len(insn);

        uint8_t *native_code_ptr = NULL;

        // If ujit hasn't already compiled this instruction
        if (insn_idx >= next_ujit_idx) {
            native_code_ptr = ujit_compile_insn(iseq, insn_idx, &next_ujit_idx);
        }

        if (native_code_ptr) {
            encoded[insn_idx] = (VALUE)native_code_ptr;
        }
        insn_idx += len;
    }
    RB_VM_LOCK_LEAVE();
#endif
}

void
rb_ujit_init(void)
{
    if (!ujit_scrape_successful || !PLATFORM_SUPPORTED_P)
    {
        return;
    }

    rb_ujit_enabled = true;

    // Initialize ujit codegen
    ujit_init_codegen();

    // Initialize the GC hooks
    method_lookup_dependency = st_init_numtable();
    struct ujit_root_struct *root;
    VALUE ujit_root = TypedData_Make_Struct(0, struct ujit_root_struct, &ujit_root_type, root);
    rb_gc_register_mark_object(ujit_root);
}
