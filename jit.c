// Glue code shared between YJIT and ZJIT for use from Rust.
// For FFI safety and bindgen compatibility reasons, certain types of C
// functions require wrapping before they can be called from Rust. Those show
// up here.
//
// Code specific to YJIT and ZJIT should go to yjit.c and zjit.c respectively.

#include "internal.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "iseq.h"
#include "internal/gc.h"
#include "vm_sync.h"
#include "internal/fixnum.h"
#include "internal/string.h"

enum jit_bindgen_constants {
    // Field offsets for the RObject struct
    ROBJECT_OFFSET_AS_HEAP_FIELDS = offsetof(struct RObject, as.heap.fields),
    ROBJECT_OFFSET_AS_ARY = offsetof(struct RObject, as.ary),

    // Field offsets for the RString struct
    RUBY_OFFSET_RSTRING_LEN = offsetof(struct RString, len),

    // Field offsets for rb_execution_context_t
    RUBY_OFFSET_EC_CFP = offsetof(rb_execution_context_t, cfp),
    RUBY_OFFSET_EC_INTERRUPT_FLAG = offsetof(rb_execution_context_t, interrupt_flag),
    RUBY_OFFSET_EC_INTERRUPT_MASK = offsetof(rb_execution_context_t, interrupt_mask),
    RUBY_OFFSET_EC_THREAD_PTR = offsetof(rb_execution_context_t, thread_ptr),
    RUBY_OFFSET_EC_RACTOR_ID = offsetof(rb_execution_context_t, ractor_id),
};

// Manually bound in rust since this is out-of-range of `int`,
// so this can't be in a `enum`, and we avoid `static const`
// to avoid allocating storage for the constant.
const shape_id_t rb_invalid_shape_id = INVALID_SHAPE_ID;

unsigned int
rb_iseq_encoded_size(const rb_iseq_t *iseq)
{
    return iseq->body->iseq_size;
}

// Get the PC for a given index in an iseq
VALUE *
rb_iseq_pc_at_idx(const rb_iseq_t *iseq, uint32_t insn_idx)
{
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(iseq, imemo_iseq));
    RUBY_ASSERT_ALWAYS(insn_idx < iseq->body->iseq_size);
    VALUE *encoded = iseq->body->iseq_encoded;
    VALUE *pc = &encoded[insn_idx];
    return pc;
}

// Get the opcode given a program counter. Can return trace opcode variants.
int
rb_iseq_opcode_at_pc(const rb_iseq_t *iseq, const VALUE *pc)
{
    // YJIT should only use iseqs after AST to bytecode compilation.
    // (Certain non-default interpreter configurations never set ISEQ_TRANSLATED)
    if (OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE) {
        RUBY_ASSERT_ALWAYS(FL_TEST_RAW((VALUE)iseq, ISEQ_TRANSLATED));
    }

    const VALUE at_pc = *pc;
    return rb_vm_insn_addr2opcode((const void *)at_pc);
}

unsigned long
rb_RSTRING_LEN(VALUE str)
{
    return RSTRING_LEN(str);
}

char *
rb_RSTRING_PTR(VALUE str)
{
    return RSTRING_PTR(str);
}

const char *
rb_insn_name(VALUE insn)
{
    return insn_name(insn);
}

unsigned int
rb_vm_ci_argc(const struct rb_callinfo *ci)
{
    return vm_ci_argc(ci);
}

ID
rb_vm_ci_mid(const struct rb_callinfo *ci)
{
    return vm_ci_mid(ci);
}

unsigned int
rb_vm_ci_flag(const struct rb_callinfo *ci)
{
    return vm_ci_flag(ci);
}

const struct rb_callinfo_kwarg *
rb_vm_ci_kwarg(const struct rb_callinfo *ci)
{
    return vm_ci_kwarg(ci);
}

int
rb_get_cikw_keyword_len(const struct rb_callinfo_kwarg *cikw)
{
    return cikw->keyword_len;
}

VALUE
rb_get_cikw_keywords_idx(const struct rb_callinfo_kwarg *cikw, int idx)
{
    return cikw->keywords[idx];
}

rb_method_visibility_t
rb_METHOD_ENTRY_VISI(const rb_callable_method_entry_t *me)
{
    return METHOD_ENTRY_VISI(me);
}

rb_method_type_t
rb_get_cme_def_type(const rb_callable_method_entry_t *cme)
{
    if (UNDEFINED_METHOD_ENTRY_P(cme)) {
        return VM_METHOD_TYPE_UNDEF;
    }
    else {
        return cme->def->type;
    }
}

ID
rb_get_cme_def_body_attr_id(const rb_callable_method_entry_t *cme)
{
    return cme->def->body.attr.id;
}

enum method_optimized_type
rb_get_cme_def_body_optimized_type(const rb_callable_method_entry_t *cme)
{
    return cme->def->body.optimized.type;
}

unsigned int
rb_get_cme_def_body_optimized_index(const rb_callable_method_entry_t *cme)
{
    return cme->def->body.optimized.index;
}

rb_method_cfunc_t *
rb_get_cme_def_body_cfunc(const rb_callable_method_entry_t *cme)
{
    return UNALIGNED_MEMBER_PTR(cme->def, body.cfunc);
}

uintptr_t
rb_get_def_method_serial(const rb_method_definition_t *def)
{
    return def->method_serial;
}

ID
rb_get_def_original_id(const rb_method_definition_t *def)
{
    return def->original_id;
}

VALUE
rb_get_def_bmethod_proc(rb_method_definition_t *def)
{
    RUBY_ASSERT(def->type == VM_METHOD_TYPE_BMETHOD);
    return def->body.bmethod.proc;
}

rb_proc_t *
rb_jit_get_proc_ptr(VALUE procv)
{
    rb_proc_t *proc;
    GetProcPtr(procv, proc);
    return proc;
}

unsigned int
rb_jit_iseq_builtin_attrs(const rb_iseq_t *iseq)
{
    return iseq->body->builtin_attrs;
}

int
rb_get_mct_argc(const rb_method_cfunc_t *mct)
{
    return mct->argc;
}

void *
rb_get_mct_func(const rb_method_cfunc_t *mct)
{
    return (void*)(uintptr_t)mct->func; // this field is defined as type VALUE (*func)(ANYARGS)
}

const rb_iseq_t *
rb_get_def_iseq_ptr(rb_method_definition_t *def)
{
    return def_iseq_ptr(def);
}

const rb_iseq_t *
rb_get_iseq_body_local_iseq(const rb_iseq_t *iseq)
{
    return iseq->body->local_iseq;
}

const rb_iseq_t *
rb_get_iseq_body_parent_iseq(const rb_iseq_t *iseq)
{
    return iseq->body->parent_iseq;
}

unsigned int
rb_get_iseq_body_local_table_size(const rb_iseq_t *iseq)
{
    return iseq->body->local_table_size;
}

VALUE *
rb_get_iseq_body_iseq_encoded(const rb_iseq_t *iseq)
{
    return iseq->body->iseq_encoded;
}

unsigned
rb_get_iseq_body_stack_max(const rb_iseq_t *iseq)
{
    return iseq->body->stack_max;
}

enum rb_iseq_type
rb_get_iseq_body_type(const rb_iseq_t *iseq)
{
    return iseq->body->type;
}

bool
rb_get_iseq_flags_has_lead(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_lead;
}

bool
rb_get_iseq_flags_has_opt(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_opt;
}

bool
rb_get_iseq_flags_has_kw(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_kw;
}

bool
rb_get_iseq_flags_has_post(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_post;
}

bool
rb_get_iseq_flags_has_kwrest(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_kwrest;
}

bool
rb_get_iseq_flags_anon_kwrest(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.anon_kwrest;
}

bool
rb_get_iseq_flags_has_rest(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_rest;
}

bool
rb_get_iseq_flags_ruby2_keywords(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.ruby2_keywords;
}

bool
rb_get_iseq_flags_has_block(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_block;
}

bool
rb_get_iseq_flags_ambiguous_param0(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.ambiguous_param0;
}

bool
rb_get_iseq_flags_accepts_no_kwarg(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.accepts_no_kwarg;
}

bool
rb_get_iseq_flags_forwardable(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.forwardable;
}

// This is defined only as a named struct inside rb_iseq_constant_body.
// By giving it a separate typedef, we make it nameable by rust-bindgen.
// Bindgen's temp/anon name isn't guaranteed stable.
typedef struct rb_iseq_param_keyword rb_iseq_param_keyword_struct;

const rb_iseq_param_keyword_struct *
rb_get_iseq_body_param_keyword(const rb_iseq_t *iseq)
{
    return iseq->body->param.keyword;
}

unsigned
rb_get_iseq_body_param_size(const rb_iseq_t *iseq)
{
    return iseq->body->param.size;
}

int
rb_get_iseq_body_param_lead_num(const rb_iseq_t *iseq)
{
    return iseq->body->param.lead_num;
}

int
rb_get_iseq_body_param_opt_num(const rb_iseq_t *iseq)
{
    return iseq->body->param.opt_num;
}

const VALUE *
rb_get_iseq_body_param_opt_table(const rb_iseq_t *iseq)
{
    return iseq->body->param.opt_table;
}

struct rb_control_frame_struct *
rb_get_ec_cfp(const rb_execution_context_t *ec)
{
    return ec->cfp;
}

const rb_iseq_t *
rb_get_cfp_iseq(struct rb_control_frame_struct *cfp)
{
    return cfp->iseq;
}

VALUE *
rb_get_cfp_pc(struct rb_control_frame_struct *cfp)
{
    return (VALUE*)cfp->pc;
}

VALUE *
rb_get_cfp_sp(struct rb_control_frame_struct *cfp)
{
    return cfp->sp;
}

VALUE
rb_get_cfp_self(struct rb_control_frame_struct *cfp)
{
    return cfp->self;
}

VALUE *
rb_get_cfp_ep(struct rb_control_frame_struct *cfp)
{
    return (VALUE*)cfp->ep;
}

const VALUE *
rb_get_cfp_ep_level(struct rb_control_frame_struct *cfp, uint32_t lv)
{
    uint32_t i;
    const VALUE *ep = (VALUE*)cfp->ep;
    for (i = 0; i < lv; i++) {
        ep = VM_ENV_PREV_EP(ep);
    }
    return ep;
}

VALUE
rb_yarv_class_of(VALUE obj)
{
    return rb_class_of(obj);
}

// The FL_TEST() macro
VALUE
rb_FL_TEST(VALUE obj, VALUE flags)
{
    return RB_FL_TEST(obj, flags);
}

// The FL_TEST_RAW() macro, normally an internal implementation detail
VALUE
rb_FL_TEST_RAW(VALUE obj, VALUE flags)
{
    return FL_TEST_RAW(obj, flags);
}

// The RB_TYPE_P macro
bool
rb_RB_TYPE_P(VALUE obj, enum ruby_value_type t)
{
    return RB_TYPE_P(obj, t);
}

long
rb_RSTRUCT_LEN(VALUE st)
{
    return RSTRUCT_LEN(st);
}

const struct rb_callinfo *
rb_get_call_data_ci(const struct rb_call_data *cd)
{
    return cd->ci;
}

bool
rb_BASIC_OP_UNREDEFINED_P(enum ruby_basic_operators bop, uint32_t klass)
{
    return BASIC_OP_UNREDEFINED_P(bop, klass);
}

VALUE
rb_RCLASS_ORIGIN(VALUE c)
{
    return RCLASS_ORIGIN(c);
}

// For debug builds
void
rb_assert_iseq_handle(VALUE handle)
{
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(handle, imemo_iseq));
}

// Assert that we have the VM lock. Relevant mostly for multi ractor situations.
// The GC takes the lock before calling us, and this asserts that it indeed happens.
void
rb_assert_holding_vm_lock(void)
{
    ASSERT_vm_locking();
}

int
rb_IMEMO_TYPE_P(VALUE imemo, enum imemo_type imemo_type)
{
    return IMEMO_TYPE_P(imemo, imemo_type);
}

void
rb_assert_cme_handle(VALUE handle)
{
    RUBY_ASSERT_ALWAYS(!rb_objspace_garbage_object_p(handle));
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(handle, imemo_ment));
}

// YJIT and ZJIT need this function to never allocate and never raise
VALUE
rb_yarv_ary_entry_internal(VALUE ary, long offset)
{
    return rb_ary_entry_internal(ary, offset);
}

long
rb_jit_array_len(VALUE a)
{
    return rb_array_len(a);
}

void
rb_set_cfp_pc(struct rb_control_frame_struct *cfp, const VALUE *pc)
{
    cfp->pc = pc;
}

void
rb_set_cfp_sp(struct rb_control_frame_struct *cfp, VALUE *sp)
{
    cfp->sp = sp;
}

bool
rb_jit_shape_too_complex_p(shape_id_t shape_id)
{
    return rb_shape_too_complex_p(shape_id);
}

bool
rb_jit_multi_ractor_p(void)
{
    return rb_multi_ractor_p();
}

// Acquire the VM lock and then signal all other Ruby threads (ractors) to
// contend for the VM lock, putting them to sleep. ZJIT and YJIT use this to
// evict threads running inside generated code so among other things, it can
// safely change memory protection of regions housing generated code.
void
rb_jit_vm_lock_then_barrier(unsigned int *recursive_lock_level, const char *file, int line)
{
    rb_vm_lock_enter(recursive_lock_level, file, line);
    rb_vm_barrier();
}

// Release the VM lock. The lock level must point to the same integer used to
// acquire the lock.
void
rb_jit_vm_unlock(unsigned int *recursive_lock_level, const char *file, int line)
{
    rb_vm_lock_leave(recursive_lock_level, file, line);
}

void
rb_iseq_reset_jit_func(const rb_iseq_t *iseq)
{
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(iseq, imemo_iseq));
    iseq->body->jit_entry = NULL;
    iseq->body->jit_exception = NULL;
    // Enable re-compiling this ISEQ. Event when it's invalidated for TracePoint,
    // we'd like to re-compile ISEQs that haven't been converted to trace_* insns.
    iseq->body->jit_entry_calls = 0;
    iseq->body->jit_exception_calls = 0;
}

// Callback data for rb_jit_for_each_iseq
struct iseq_callback_data {
    rb_iseq_callback callback;
    void *data;
};

// Heap-walking callback for rb_jit_for_each_iseq
static int
for_each_iseq_i(void *vstart, void *vend, size_t stride, void *data)
{
    const struct iseq_callback_data *callback_data = (struct iseq_callback_data *)data;
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        void *ptr = rb_asan_poisoned_object_p(v);
        rb_asan_unpoison_object(v, false);

        if (rb_obj_is_iseq(v)) {
            rb_iseq_t *iseq = (rb_iseq_t *)v;
            callback_data->callback(iseq, callback_data->data);
        }

        if (ptr) {
            rb_asan_poison_object(v);
        }
    }
    return 0;
}

uint32_t
rb_jit_get_page_size(void)
{
#if defined(_SC_PAGESIZE)
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) rb_bug("jit: failed to get page size");

    // 1 GiB limit. x86 CPUs with PDPE1GB can do this and anything larger is unexpected.
    // Though our design sort of assume we have fine grained control over memory protection
    // which require small page sizes.
    if (page_size > 0x40000000l) rb_bug("jit page size too large");

    return (uint32_t)page_size;
#else
#error "JIT supports POSIX only for now"
#endif
}

#if defined(MAP_FIXED_NOREPLACE) && defined(_SC_PAGESIZE)
// Align the current write position to a multiple of bytes
static uint8_t *
align_ptr(uint8_t *ptr, uint32_t multiple)
{
    // Compute the pointer modulo the given alignment boundary
    uint32_t rem = ((uint32_t)(uintptr_t)ptr) % multiple;

    // If the pointer is already aligned, stop
    if (rem == 0)
        return ptr;

    // Pad the pointer by the necessary amount to align it
    uint32_t pad = multiple - rem;

    return ptr + pad;
}
#endif

// Address space reservation. Memory pages are mapped on an as needed basis.
// See the Rust mm module for details.
uint8_t *
rb_jit_reserve_addr_space(uint32_t mem_size)
{
#ifndef _WIN32
    uint8_t *mem_block;

    // On Linux
    #if defined(MAP_FIXED_NOREPLACE) && defined(_SC_PAGESIZE)
        uint32_t const page_size = (uint32_t)sysconf(_SC_PAGESIZE);
        uint8_t *const cfunc_sample_addr = (void *)(uintptr_t)&rb_jit_reserve_addr_space;
        uint8_t *const probe_region_end = cfunc_sample_addr + INT32_MAX;
        // Align the requested address to page size
        uint8_t *req_addr = align_ptr(cfunc_sample_addr, page_size);

        // Probe for addresses close to this function using MAP_FIXED_NOREPLACE
        // to improve odds of being in range for 32-bit relative call instructions.
        do {
            mem_block = mmap(
                req_addr,
                mem_size,
                PROT_NONE,
                MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE,
                -1,
                0
            );

            // If we succeeded, stop
            if (mem_block != MAP_FAILED) {
                ruby_annotate_mmap(mem_block, mem_size, "Ruby:rb_jit_reserve_addr_space");
                break;
            }

            // -4MiB. Downwards to probe away from the heap. (On x86/A64 Linux
            // main_code_addr < heap_addr, and in case we are in a shared
            // library mapped higher than the heap, downwards is still better
            // since it's towards the end of the heap rather than the stack.)
            req_addr -= 4 * 1024 * 1024;
        } while (req_addr < probe_region_end);

    // On MacOS and other platforms
    #else
        // Try to map a chunk of memory as executable
        mem_block = mmap(
            (void *)rb_jit_reserve_addr_space,
            mem_size,
            PROT_NONE,
            MAP_PRIVATE | MAP_ANONYMOUS,
            -1,
            0
        );
    #endif

    // Fallback
    if (mem_block == MAP_FAILED) {
        // Try again without the address hint (e.g., valgrind)
        mem_block = mmap(
            NULL,
            mem_size,
            PROT_NONE,
            MAP_PRIVATE | MAP_ANONYMOUS,
            -1,
            0
        );

        if (mem_block != MAP_FAILED) {
            ruby_annotate_mmap(mem_block, mem_size, "Ruby:rb_jit_reserve_addr_space:fallback");
        }
    }

    // Check that the memory mapping was successful
    if (mem_block == MAP_FAILED) {
        perror("ruby: jit: mmap:");
        if(errno == ENOMEM) {
            // No crash report if it's only insufficient memory
            exit(EXIT_FAILURE);
        }
        rb_bug("mmap failed");
    }

    return mem_block;
#else
    // Windows not supported for now
    return NULL;
#endif
}

// Walk all ISEQs in the heap and invoke the callback - shared between YJIT and ZJIT
void
rb_jit_for_each_iseq(rb_iseq_callback callback, void *data)
{
    struct iseq_callback_data callback_data = { .callback = callback, .data = data };
    rb_objspace_each_objects(for_each_iseq_i, (void *)&callback_data);
}

bool
rb_jit_mark_writable(void *mem_block, uint32_t mem_size)
{
    return mprotect(mem_block, mem_size, PROT_READ | PROT_WRITE) == 0;
}

void
rb_jit_mark_executable(void *mem_block, uint32_t mem_size)
{
    // Do not call mprotect when mem_size is zero. Some platforms may return
    // an error for it. https://github.com/Shopify/ruby/issues/450
    if (mem_size == 0) {
        return;
    }
    if (mprotect(mem_block, mem_size, PROT_READ | PROT_EXEC)) {
        rb_bug("Couldn't make JIT page (%p, %lu bytes) executable, errno: %s",
            mem_block, (unsigned long)mem_size, strerror(errno));
    }
}

// Free the specified memory block.
bool
rb_jit_mark_unused(void *mem_block, uint32_t mem_size)
{
    // On Linux, you need to use madvise MADV_DONTNEED to free memory.
    // We might not need to call this on macOS, but it's not really documented.
    // We generally prefer to do the same thing on both to ease testing too.
    madvise(mem_block, mem_size, MADV_DONTNEED);

    // On macOS, mprotect PROT_NONE seems to reduce RSS.
    // We also call this on Linux to avoid executing unused pages.
    return mprotect(mem_block, mem_size, PROT_NONE) == 0;
}

// Invalidate icache for arm64.
// `start` is inclusive and `end` is exclusive.
void
rb_jit_icache_invalidate(void *start, void *end)
{
    // Clear/invalidate the instruction cache. Compiles to nothing on x86_64
    // but required on ARM before running freshly written code.
    // On Darwin it's the same as calling sys_icache_invalidate().
#ifdef __GNUC__
    __builtin___clear_cache(start, end);
#elif defined(__aarch64__)
#error No instruction cache clear available with this compiler on Aarch64!
#endif
}

VALUE
rb_jit_fix_mod_fix(VALUE recv, VALUE obj)
{
    return rb_fix_mod_fix(recv, obj);
}

VALUE
rb_jit_fix_div_fix(VALUE recv, VALUE obj)
{
    return rb_fix_div_fix(recv, obj);
}

// YJIT/ZJIT need this function to never allocate and never raise
VALUE
rb_yarv_str_eql_internal(VALUE str1, VALUE str2)
{
    // We wrap this since it's static inline
    return rb_str_eql_internal(str1, str2);
}

void rb_jit_str_concat_codepoint(VALUE str, VALUE codepoint);

attr_index_t
rb_jit_shape_capacity(shape_id_t shape_id)
{
    return RSHAPE_CAPACITY(shape_id);
}
