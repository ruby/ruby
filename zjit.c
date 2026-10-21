#include "internal.h"
#include "internal/sanitizers.h"
#include "internal/string.h"
#include "internal/hash.h"
#include "internal/variable.h"
#include "internal/compile.h"
#include "internal/class.h"
#include "internal/fixnum.h"
#include "internal/numeric.h"
#include "internal/gc.h"
#include "internal/vm.h"
#include "yjit.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "zjit.h"
#include "vm_insnhelper.h"
#include "probes.h"
#include "probes_helper.h"
#include "constant.h"
#include "iseq.h"
#include "ruby/debug.h"
#include "internal/cont.h"
#include "internal/jit.h"
#include "ractor_core.h"
#include "shape.h"

#ifndef _WIN32
#include <sys/mman.h>
#endif

// This build config impacts the pointer tagging scheme and we only want to
// support one scheme for simplicity.
STATIC_ASSERT(pointer_tagging_scheme, USE_FLONUM);

enum zjit_struct_offsets {
    ISEQ_BODY_OFFSET_PARAM = offsetof(struct rb_iseq_constant_body, param),
    ISEQ_BODY_OFFSET_OUTER_VARIABLES = offsetof(struct rb_iseq_constant_body, outer_variables),
    RUBY_OFFSET_THREAD_RACTOR = offsetof(rb_thread_t, ractor),
};

// Struct offsets that cannot be constants in the checked-in bindgen output
// (zjit/src/cruby_bindings.inc.rs) because they vary with the build target
// and configuration. For example, offsetof(rb_ractor_t, newobj_cache) depends
// on the sizes of pthread types embedded in rb_ractor_t, which differ across
// architectures and OSes, as well as on VM_CHECK_MODE and RACTOR_CHECK_MODE.
// This table is filled out at C compile time and read by Rust at JIT compile
// time. Offsets that are identical on all supported builds should be added to
// enum zjit_struct_offsets above instead.
struct rb_zjit_runtime_offsets {
    int32_t ractor_newobj_cache;
    int32_t ractor_objspace;
};
const struct rb_zjit_runtime_offsets rb_zjit_runtime_offsets = {
    .ractor_newobj_cache = offsetof(rb_ractor_t, newobj_cache),
    .ractor_objspace = offsetof(rb_ractor_t, objspace),
};

// Special JITFrame used by all C method calls. We don't control the native
// stack layout for C frames, so cfp->jit_return points at this static frame
// via the ZJIT_JIT_RETURN_C_FRAME sentinel instead of a per-call allocation.
const zjit_jit_frame_t rb_zjit_c_frame = (zjit_jit_frame_t) {
    .pc = 0,
    .iseq = 0,
    .materialize_block_code = false,
};

#if !defined(_WIN32) && defined(MAP_ANONYMOUS)
uint8_t *rb_jit_align_ptr(uint8_t *ptr, uint32_t multiple); // defined in jit.c

// Reserve address space that lives entirely below INT32_MAX for JITFrame.
//
// When a JITFrame pointer fits in 32 bits, x86_64 can encode the store
// as `mov qword ptr [mem], imm32` (8 bytes) instead of `movabs` + a store,
// and arm64 materializes it in two instructions instead of four.
//
// Like rb_jit_reserve_addr_space in jit.c, this only reserves address space (PROT_NONE).
// VirtualMem is in charge of mapping physical memory into the reserved space page by page.
void *
rb_zjit_reserve_low_addr_space(size_t size)
{
    void *mem_block = MAP_FAILED;

    // Linux (x86_64): Use MAP_32BIT to map within the first 2GiB of address space.
    // This works only for x86_64, and the kernel restricts it to [1GiB, 2GiB).
  #ifdef MAP_32BIT
    mem_block = mmap(NULL, size, PROT_NONE,
                     MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0);
  #endif

    // Linux (all arch): Probe a free hole below 2GiB if MAP_32BIT is not possible.
    // MAP_FIXED_NOREPLACE fails rather than clobbering an existing mapping.
  #if defined(MAP_FIXED_NOREPLACE) && defined(_SC_PAGESIZE)
    if (mem_block == MAP_FAILED) {
        // Distance between probes. 64MiB sweeps the usable 2GiB in at most 32 mmap calls.
        const uintptr_t probe_stride = 64 * 1024 * 1024;
        const uint32_t page_size = (uint32_t)sysconf(_SC_PAGESIZE);
        const uintptr_t limit = (uintptr_t)INT32_MAX - size;
        for (uintptr_t addr = probe_stride; addr < limit; addr += probe_stride) {
            // mmap only honors a hint that is page-aligned.
            void *req = rb_jit_align_ptr((uint8_t *)addr, page_size);
            mem_block = mmap(req, size, PROT_NONE,
                             MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
            if (mem_block != MAP_FAILED) break;
        }
    }
  #endif

    if (mem_block == MAP_FAILED) return NULL;

    // Both MAP_32BIT and MAP_FIXED_NOREPLACE are advisory in some platforms, e.g.
    // sandboxes or older kernels. Fallback to normal allocation if it doesn't work.
    if ((uintptr_t)mem_block + size > (uintptr_t)INT32_MAX) {
        munmap(mem_block, size);
        return NULL;
    }
    ruby_annotate_mmap(mem_block, size, "Ruby:rb_zjit_reserve_low_addr_space");
    return mem_block;
}

#else

// Windows not supported for now
void *rb_zjit_reserve_low_addr_space(size_t size) { return NULL; }

#endif

static VALUE
rb_zjit_total_compile_time_ns_get(rb_execution_context_t *ec, VALUE self)
{
    return ULL2NUM(rb_zjit_total_compile_time_ns);
}

static VALUE
rb_zjit_max_compile_time_ns_get(rb_execution_context_t *ec, VALUE self)
{
    return ULL2NUM(rb_zjit_max_compile_time_ns);
}

void rb_zjit_update_max_compile_time_ns(uint64_t max_compile_time_ns);

static VALUE
rb_zjit_max_compile_time_ns_set(rb_execution_context_t *ec, VALUE self, VALUE max_compile_time_ns)
{
    rb_zjit_update_max_compile_time_ns(NUM2ULL(max_compile_time_ns));
    return max_compile_time_ns;
}

void rb_zjit_profile_disable(const rb_iseq_t *iseq);
int rb_zjit_insn_to_bare_insn(int insn);

void
rb_zjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception)
{
    RB_VM_LOCKING() {
        rb_vm_barrier();

        // Compile a block version starting at the current instruction
        uint8_t *rb_zjit_iseq_gen_entry_point(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception); // defined in Rust
        uintptr_t code_ptr = (uintptr_t)rb_zjit_iseq_gen_entry_point(iseq, ec, jit_exception);

        if (jit_exception) {
            ISEQ_BODY(iseq)->jit_exception = (rb_jit_func_t)code_ptr;
        }
        else {
            ISEQ_BODY(iseq)->jit_entry = (rb_jit_func_t)code_ptr;
        }
    }
}

// This is used by a function stub to install compiled code as the ISEQ's entry point.
void
rb_zjit_iseq_set_jit_entry(const rb_iseq_t *iseq, void *code_ptr)
{
    ISEQ_BODY(iseq)->jit_entry = (rb_jit_func_t)code_ptr;
}

extern VALUE *rb_vm_base_ptr(struct rb_control_frame_struct *cfp);

// Convert a given ISEQ's instructions to zjit_* instructions
void
rb_zjit_profile_enable(const rb_iseq_t *iseq)
{
    // This table encodes an opcode into the instruction's address
    const void *const *insn_table = rb_vm_get_insns_address_table();

    unsigned int insn_idx = 0;
    while (insn_idx < ISEQ_BODY(iseq)->iseq_size) {
        int insn = rb_vm_insn_addr2opcode((void *)ISEQ_BODY(iseq)->iseq_encoded[insn_idx]);
        int zjit_insn = vm_bare_insn_to_zjit_insn(insn);
        if (insn != zjit_insn) {
            ISEQ_BODY(iseq)->iseq_encoded[insn_idx] = (VALUE)insn_table[zjit_insn];
        }
        insn_idx += insn_len(insn);
    }
}

// Return false if a function stub has not collected enough profiles yet, enabling
// profiling instructions as needed. Return true once enough profiles are collected.
bool
rb_zjit_iseq_has_profiled_enough(const rb_iseq_t *iseq)
{
    struct rb_iseq_constant_body *body = ISEQ_BODY(iseq);
    uint64_t profile_threshold = rb_zjit_iseq_profile_threshold(iseq);

    if (body->jit_entry_calls < profile_threshold) {
        // Skip the unprofiled warmup. The compiled caller already establishes
        // that the callee is hot, so go straight to the profiling window.
        // Thresholds derive from the unsigned int options, so this is exact.
        body->jit_entry_calls = (unsigned int)profile_threshold;
        rb_zjit_profile_enable(iseq);
    }
    else {
        body->jit_entry_calls++;
    }

    return body->jit_entry_calls >= rb_zjit_iseq_compile_threshold(iseq);
}

// Convert a given ISEQ's ZJIT instructions to bare instructions
void
rb_zjit_profile_disable(const rb_iseq_t *iseq)
{
    // This table encodes an opcode into the instruction's address
    const void *const *insn_table = rb_vm_get_insns_address_table();

    unsigned int insn_idx = 0;
    while (insn_idx < ISEQ_BODY(iseq)->iseq_size) {
        int insn = rb_vm_insn_addr2opcode((void *)ISEQ_BODY(iseq)->iseq_encoded[insn_idx]);
        int bare_insn = vm_zjit_insn_to_bare_insn(insn);
        if (insn != bare_insn) {
            ISEQ_BODY(iseq)->iseq_encoded[insn_idx] = (VALUE)insn_table[bare_insn];
        }
        insn_idx += insn_len(insn);
    }
}

// Map `zjit_* instructions back to their bare form. This is an identity function for all others.
int
rb_zjit_insn_to_bare_insn(int insn)
{
    return vm_zjit_insn_to_bare_insn(insn);
}

// Update a YARV instruction to a given opcode (to disable ZJIT profiling).
void
rb_zjit_iseq_insn_set(const rb_iseq_t *iseq, unsigned int insn_idx, enum ruby_vminsn_type bare_insn)
{
#if RUBY_DEBUG
    int insn = rb_vm_insn_addr2opcode((void *)ISEQ_BODY(iseq)->iseq_encoded[insn_idx]);
    RUBY_ASSERT(vm_zjit_insn_to_bare_insn(insn) == (int)bare_insn);
#endif
    const void *const *insn_table = rb_vm_get_insns_address_table();
    ISEQ_BODY(iseq)->iseq_encoded[insn_idx] = (VALUE)insn_table[bare_insn];
}

void
rb_zjit_print_exception(void)
{
    VALUE exception = rb_errinfo();
    rb_set_errinfo(Qnil);
    assert(RTEST(exception));
    rb_warn("Ruby error: %"PRIsVALUE"", rb_funcall(exception, rb_intern("full_message"), 0));
}

bool
rb_zjit_singleton_class_p(VALUE klass)
{
    return RCLASS_SINGLETON_P(klass);
}

// Whether this ISEQ is lexically rooted in an eval body. Such ISEQs are
// usually short-lived (templating engines re-eval per render, so every render
// creates fresh ISEQs); vm.c holds them to a much higher call threshold.
bool
rb_zjit_iseq_eval_rooted(const rb_iseq_t *iseq)
{
    while (iseq) {
        if (ISEQ_BODY(iseq)->type == ISEQ_TYPE_EVAL) return true;
        iseq = ISEQ_BODY(iseq)->parent_iseq;
    }
    return false;
}

// Whether Ruby::Box is enabled (RUBY_BOX=1, fixed at boot). Symbol block
// handler yields then resolve the method in the caller's box, which JIT code's
// direct symbol yield does not implement, so the JIT leaves them generic.
bool
rb_zjit_box_enabled(void)
{
    return rb_box_available();
}

unsigned int
rb_zjit_iseq_exception_entry_count(const rb_iseq_t *iseq)
{
    const struct iseq_catch_table *table = ISEQ_BODY(iseq)->catch_table;
    return table ? table->size : 0;
}

bool
rb_zjit_iseq_exception_entry(const rb_iseq_t *iseq, unsigned int index,
                             enum rb_catch_type *type, unsigned int *cont,
                             unsigned int *stack_size)
{
    const struct iseq_catch_table *table = ISEQ_BODY(iseq)->catch_table;
    if (!table || index >= table->size) return false;

    const struct iseq_catch_table_entry *entry =
        UNALIGNED_MEMBER_PTR(table, entries[index]);
    switch (entry->type) {
      case CATCH_TYPE_RETRY:
      case CATCH_TYPE_REDO:
        *stack_size = entry->sp;
        break;
      case CATCH_TYPE_BREAK:
      case CATCH_TYPE_NEXT:
        // compile.c removes the value pushed by vm_exec_handle_exception()
        // when it records these catch-table stack depths.
        *stack_size = entry->sp + 1;
        break;
      default:
        return false;
    }

    *type = entry->type;
    *cont = entry->cont;
    return true;
}

// Symbol block handler yield for the single-argument shape: `yield x` to a
// &:sym block calls x.sym, exactly vm_yield_with_symbol -> rb_sym_proc_call
// with no kw-splat and no sub-block. Only used while Ruby::Box is disabled.
VALUE
rb_zjit_yield_symbol1(VALUE symbol, VALUE recv)
{
    RUBY_ASSERT(!rb_box_available());
    return rb_sym_proc_call(SYM2ID(symbol), 1, &recv, 0, Qnil);
}

// The captured block of a plain (non-lambda, non-refined) iseq-proc, or NULL
// when the value is anything else (not a Proc, a lambda, a refined proc, a
// symbol/method proc, or the no-block sentinel). Lets JIT code dispatch a Proc
// block handler to the same direct block call a plain ISEQ handler takes; NULL
// routes to the generic path. Lambda procs use strict arity and a lambda frame
// flag, and refined procs (Proc#refined) push a refinement cref, neither of
// which the direct block call implements.
const struct rb_captured_block *
rb_zjit_proc_iseq_captured(VALUE procv)
{
    if (!RB_SPECIAL_CONST_P(procv) && RTEST(rb_obj_is_proc(procv))) {
        const rb_proc_t *proc;
        GetProcPtr(procv, proc);
        if (!proc->header.is_lambda && !proc->header.is_refined && vm_block_type(&proc->block) == block_type_iseq) {
            return &proc->block.as.captured;
        }
    }
    return NULL;
}

// Coderange of a string, scanning and caching it when still unknown. Returns
// the RUBY_ENC_CODERANGE_* flag value widened to a full register.
unsigned long
rb_zjit_str_coderange(VALUE str)
{
    return (unsigned long)rb_enc_str_coderange(str);
}

/* Sets all of the required shape flags for the object including the layout type,
 * the frozen status, and the slot size. Mimics `rb_newobj`.
 */
VALUE
rb_zjit_new_obj_shape(VALUE flags, size_t alloc_size)
{
    shape_id_t shape_id;
    switch (flags & T_MASK) {
      case T_OBJECT:
        shape_id = ROOT_SHAPE_ID;
        break;
      case T_STRUCT:
        shape_id = ROOT_SHAPE_ID | SHAPE_ID_LAYOUT_EXTENDED;
        break;
      case T_DATA:
        shape_id = ROOT_SHAPE_ID | SHAPE_ID_LAYOUT_RDATA;
        break;
      default:
        shape_id = ROOT_SHAPE_ID | SHAPE_ID_LAYOUT_OTHER;
        break;
    }

    if (flags & FL_FREEZE) {
        shape_id = rb_shape_transition_frozen(shape_id);
    }

    shape_id = rb_shape_transition_slot_size(shape_id, rb_gc_size_slot_size(alloc_size));

    return (flags & SHAPE_FLAG_MASK) | ((VALUE)shape_id << SHAPE_FLAG_SHIFT);
}

// Pre-sized result array for ZJIT's fused `<fixnum>.times.map` loop. The
// length is known up front, so reserving capacity removes rb_ary_push's
// per-element growth reallocs. Capacity is clamped defensively; pushes beyond
// it just grow the array as usual.
VALUE
rb_zjit_ary_new_capa_fix(VALUE n)
{
    long capa = FIX2LONG(n);
    if (capa < 0) capa = 0;
    if (capa > 0x100000) capa = 0x100000;
    return rb_ary_new_capa(capa);
}

VALUE
rb_zjit_defined_ivar(VALUE obj, ID id, VALUE pushval)
{
    VALUE result = rb_ivar_defined(obj, id);
    return result ? pushval : Qnil;
}

// Flonum comparison fast paths for ZJIT's Float#< / #<= / #> / #>= / #==
// specialization. ZJIT guards that both operands are flonums before calling
// these, so a plain double comparison is exact and matches the interpreter's
// FLONUM_2_P fast path in vm_opt_lt() and friends (NaN compares false in every
// direction, as with the C operators). RFLOAT_VALUE reads both flonums and heap
// floats. These never allocate, raise, or re-enter the VM, so ZJIT calls them
// as leaf functions.
VALUE rb_zjit_flo_lt(VALUE recv, VALUE obj) { return RBOOL(RFLOAT_VALUE(recv) <  RFLOAT_VALUE(obj)); }
VALUE rb_zjit_flo_le(VALUE recv, VALUE obj) { return RBOOL(RFLOAT_VALUE(recv) <= RFLOAT_VALUE(obj)); }
VALUE rb_zjit_flo_gt(VALUE recv, VALUE obj) { return RBOOL(RFLOAT_VALUE(recv) >  RFLOAT_VALUE(obj)); }
VALUE rb_zjit_flo_ge(VALUE recv, VALUE obj) { return RBOOL(RFLOAT_VALUE(recv) >= RFLOAT_VALUE(obj)); }
VALUE rb_zjit_flo_eq(VALUE recv, VALUE obj) { return RBOOL(RFLOAT_VALUE(recv) == RFLOAT_VALUE(obj)); }

bool
rb_zjit_method_tracing_currently_enabled(void)
{
    rb_event_flag_t tracing_events;
    if (rb_multi_ractor_p()) {
        tracing_events = ruby_vm_event_enabled_global_flags;
    }
    else {
        // At the time of writing, events are never removed from
        // ruby_vm_event_enabled_global_flags so always checking using it would
        // mean we don't compile even after tracing is disabled.
        tracing_events = rb_ec_ractor_hooks(GET_EC())->events;
    }

    return tracing_events & (RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN);
}

// Check if any ISEQ trace events are currently enabled.
// Used to prevent ZJIT from compiling while tracing is active, since ZJIT's
// send fallback (rb_vm_opt_send_without_block) uses VM_EXEC which sets
// VM_FRAME_FLAG_FINISH on the callee frame, changing exception handling
// semantics for throw TAG_RETURN (e.g. return from rescue).
bool
rb_zjit_iseq_tracing_currently_enabled(void)
{
    rb_event_flag_t tracing_events;
    if (rb_multi_ractor_p()) {
        tracing_events = ruby_vm_event_enabled_global_flags;
    }
    else {
        tracing_events = rb_ec_ractor_hooks(GET_EC())->events;
    }

    return tracing_events & ISEQ_TRACE_EVENTS;
}

bool
rb_zjit_insn_leaf(int insn, const VALUE *opes)
{
    return insn_leaf(insn, opes);
}

ID
rb_zjit_local_id(const rb_iseq_t *iseq, unsigned idx)
{
    return ISEQ_BODY(iseq)->local_table[idx];
}

bool rb_zjit_cme_is_cfunc(const rb_callable_method_entry_t *me, const void *func);

const struct rb_callable_method_entry_struct *
rb_zjit_vm_search_method(VALUE cd_owner, struct rb_call_data *cd, VALUE recv);

rb_alloc_func_t rb_zjit_class_get_alloc_func(VALUE klass);

// Defined in struct.c, where struct_alloc and the members ivar are visible.
bool rb_zjit_class_has_struct_allocator(VALUE klass);
rb_len_t rb_zjit_struct_num_members(VALUE klass);
ID rb_zjit_struct_member_id(VALUE klass, rb_len_t index);
bool rb_zjit_struct_embedded_p(rb_len_t num_members);
VALUE rb_struct_s_keyword_init(VALUE klass);

VALUE rb_class_allocate_instance(VALUE klass);

bool
rb_zjit_class_has_default_allocator(VALUE klass)
{
    assert(RCLASS_INITIALIZED_P(klass));
    assert(!RCLASS_SINGLETON_P(klass));
    rb_alloc_func_t alloc = rb_zjit_class_get_alloc_func(klass);
    return alloc == rb_class_allocate_instance;
}


VALUE rb_vm_get_untagged_block_handler(rb_control_frame_t *reg_cfp);
bool rb_vm_once_done_value(ISE is, VALUE *result);

bool
rb_zjit_array_aref_with_adjusted_index(VALUE ary, rb_len_t index, VALUE *out)
{
    RUBY_ASSERT(RB_TYPE_P(ary, T_ARRAY));
    if (index >= 0 && index < RARRAY_LEN(ary)) {
        *out = RARRAY_AREF(ary, index);
        return true;
    }
    else {
        return false;
    }
}

// Primitives used by zjit.rb. Don't put other functions below, which wouldn't use them.
VALUE rb_zjit_enable(rb_execution_context_t *ec, VALUE self);
VALUE rb_zjit_assert_compiles(rb_execution_context_t *ec, VALUE self);
VALUE rb_zjit_stats(rb_execution_context_t *ec, VALUE self, VALUE target_key);
VALUE rb_zjit_reset_stats_bang(rb_execution_context_t *ec, VALUE self);
VALUE rb_zjit_stats_enabled_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_zjit_print_stats_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_zjit_get_stats_file_path_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_zjit_trace_exit_locations_enabled_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_zjit_get_exit_locations(rb_execution_context_t *ec, VALUE self);

// Preprocessed zjit.rb generated during build
#include "zjit.rbinc"
