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
#include "iseq.h"
#include "ruby/debug.h"
#include "internal/cont.h"

// This build config impacts the pointer tagging scheme and we only want to
// support one scheme for simplicity.
STATIC_ASSERT(pointer_tagging_scheme, USE_FLONUM);

enum zjit_struct_offsets {
    ISEQ_BODY_OFFSET_PARAM = offsetof(struct rb_iseq_constant_body, param)
};

// For a given raw_sample (frame), set the hash with the caller's
// name, file, and line number. Return the  hash with collected frame_info.
static void
rb_zjit_add_frame(VALUE hash, VALUE frame)
{
    VALUE frame_id = PTR2NUM(frame);

    if (RTEST(rb_hash_aref(hash, frame_id))) {
        return;
    }
    else {
        VALUE frame_info = rb_hash_new();
        // Full label for the frame
        VALUE name = rb_profile_frame_full_label(frame);
        // Absolute path of the frame from rb_iseq_realpath
        VALUE file = rb_profile_frame_absolute_path(frame);
        // Line number of the frame
        VALUE line = rb_profile_frame_first_lineno(frame);

        // If absolute path isn't available use the rb_iseq_path
        if (NIL_P(file)) {
            file = rb_profile_frame_path(frame);
        }

        rb_hash_aset(frame_info, ID2SYM(rb_intern("name")), name);
        rb_hash_aset(frame_info, ID2SYM(rb_intern("file")), file);
        rb_hash_aset(frame_info, ID2SYM(rb_intern("samples")), INT2NUM(0));
        rb_hash_aset(frame_info, ID2SYM(rb_intern("total_samples")), INT2NUM(0));
        rb_hash_aset(frame_info, ID2SYM(rb_intern("edges")), rb_hash_new());
        rb_hash_aset(frame_info, ID2SYM(rb_intern("lines")), rb_hash_new());

        if (line != INT2FIX(0)) {
            rb_hash_aset(frame_info, ID2SYM(rb_intern("line")), line);
        }

       rb_hash_aset(hash, frame_id, frame_info);
    }
}

// Parses the ZjitExitLocations raw_samples and line_samples collected by
// rb_zjit_record_exit_stack and turns them into 3 hashes (raw, lines, and frames) to
// be used by RubyVM::ZJIT.exit_locations. zjit_raw_samples represents the raw frames information
// (without name, file, and line), and zjit_line_samples represents the line information
// of the iseq caller.
VALUE
rb_zjit_exit_locations_dict(VALUE *zjit_raw_samples, int *zjit_line_samples, int samples_len)
{
    VALUE result = rb_hash_new();
    VALUE raw_samples = rb_ary_new_capa(samples_len);
    VALUE line_samples = rb_ary_new_capa(samples_len);
    VALUE frames = rb_hash_new();
    int idx = 0;

    // While the index is less than samples_len, parse zjit_raw_samples and
    // zjit_line_samples, then add casted values to raw_samples and line_samples array.
    while (idx < samples_len) {
        int num = (int)zjit_raw_samples[idx];
        int line_num = (int)zjit_line_samples[idx];
        idx++;

        // + 1 as we append an additional sample for the insn
        rb_ary_push(raw_samples, SIZET2NUM(num + 1));
        rb_ary_push(line_samples, INT2NUM(line_num + 1));

        // Loop through the length of samples_len and add data to the
        // frames hash. Also push the current value onto the raw_samples
        // and line_samples array respectively.
        for (int o = 0; o < num; o++) {
            rb_zjit_add_frame(frames, zjit_raw_samples[idx]);
            rb_ary_push(raw_samples, SIZET2NUM(zjit_raw_samples[idx]));
            rb_ary_push(line_samples, INT2NUM(zjit_line_samples[idx]));
            idx++;
        }

        rb_ary_push(raw_samples, SIZET2NUM(zjit_raw_samples[idx]));
        rb_ary_push(line_samples, INT2NUM(zjit_line_samples[idx]));
        idx++;

        rb_ary_push(raw_samples, SIZET2NUM(zjit_raw_samples[idx]));
        rb_ary_push(line_samples, INT2NUM(zjit_line_samples[idx]));
        idx++;
    }

    // Set add the raw_samples, line_samples, and frames to the results
    // hash.
    rb_hash_aset(result, ID2SYM(rb_intern("raw")), raw_samples);
    rb_hash_aset(result, ID2SYM(rb_intern("lines")), line_samples);
    rb_hash_aset(result, ID2SYM(rb_intern("frames")), frames);

    return result;
}

void rb_zjit_profile_disable(const rb_iseq_t *iseq);

void
rb_zjit_compile_iseq(const rb_iseq_t *iseq, bool jit_exception)
{
    RB_VM_LOCKING() {
        rb_vm_barrier();

        // Compile a block version starting at the current instruction
        uint8_t *rb_zjit_iseq_gen_entry_point(const rb_iseq_t *iseq, bool jit_exception); // defined in Rust
        uintptr_t code_ptr = (uintptr_t)rb_zjit_iseq_gen_entry_point(iseq, jit_exception);

        if (jit_exception) {
            iseq->body->jit_exception = (rb_jit_func_t)code_ptr;
        }
        else {
            iseq->body->jit_entry = (rb_jit_func_t)code_ptr;
        }
    }
}

extern VALUE *rb_vm_base_ptr(struct rb_control_frame_struct *cfp);

bool
rb_zjit_constcache_shareable(const struct iseq_inline_constant_cache_entry *ice)
{
    return (ice->flags & IMEMO_CONST_CACHE_SHAREABLE) != 0;
}

// Convert a given ISEQ's instructions to zjit_* instructions
void
rb_zjit_profile_enable(const rb_iseq_t *iseq)
{
    // This table encodes an opcode into the instruction's address
    const void *const *insn_table = rb_vm_get_insns_address_table();

    unsigned int insn_idx = 0;
    while (insn_idx < iseq->body->iseq_size) {
        int insn = rb_vm_insn_addr2opcode((void *)iseq->body->iseq_encoded[insn_idx]);
        int zjit_insn = vm_bare_insn_to_zjit_insn(insn);
        if (insn != zjit_insn) {
            iseq->body->iseq_encoded[insn_idx] = (VALUE)insn_table[zjit_insn];
        }
        insn_idx += insn_len(insn);
    }
}

// Convert a given ISEQ's ZJIT instructions to bare instructions
void
rb_zjit_profile_disable(const rb_iseq_t *iseq)
{
    // This table encodes an opcode into the instruction's address
    const void *const *insn_table = rb_vm_get_insns_address_table();

    unsigned int insn_idx = 0;
    while (insn_idx < iseq->body->iseq_size) {
        int insn = rb_vm_insn_addr2opcode((void *)iseq->body->iseq_encoded[insn_idx]);
        int bare_insn = vm_zjit_insn_to_bare_insn(insn);
        if (insn != bare_insn) {
            iseq->body->iseq_encoded[insn_idx] = (VALUE)insn_table[bare_insn];
        }
        insn_idx += insn_len(insn);
    }
}

// Update a YARV instruction to a given opcode (to disable ZJIT profiling).
void
rb_zjit_iseq_insn_set(const rb_iseq_t *iseq, unsigned int insn_idx, enum ruby_vminsn_type bare_insn)
{
#if RUBY_DEBUG
    int insn = rb_vm_insn_addr2opcode((void *)iseq->body->iseq_encoded[insn_idx]);
    RUBY_ASSERT(vm_zjit_insn_to_bare_insn(insn) == (int)bare_insn);
#endif
    const void *const *insn_table = rb_vm_get_insns_address_table();
    iseq->body->iseq_encoded[insn_idx] = (VALUE)insn_table[bare_insn];
}

// Get profiling information for ISEQ
void *
rb_iseq_get_zjit_payload(const rb_iseq_t *iseq)
{
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(iseq, imemo_iseq));
    if (iseq->body) {
        return iseq->body->zjit_payload;
    }
    else {
        // Body is NULL when constructing the iseq.
        return NULL;
    }
}

// Set profiling information for ISEQ
void
rb_iseq_set_zjit_payload(const rb_iseq_t *iseq, void *payload)
{
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(iseq, imemo_iseq));
    RUBY_ASSERT_ALWAYS(iseq->body);
    RUBY_ASSERT_ALWAYS(NULL == iseq->body->zjit_payload);
    iseq->body->zjit_payload = payload;
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

VALUE
rb_zjit_defined_ivar(VALUE obj, ID id, VALUE pushval)
{
    VALUE result = rb_ivar_defined(obj, id);
    return result ? pushval : Qnil;
}

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

bool
rb_zjit_class_initialized_p(VALUE klass)
{
    return RCLASS_INITIALIZED_P(klass);
}

rb_alloc_func_t rb_zjit_class_get_alloc_func(VALUE klass);

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

void
rb_zjit_writebarrier_check_immediate(VALUE recv, VALUE val)
{
    if (!RB_SPECIAL_CONST_P(val)) {
        rb_gc_writebarrier(recv, val);
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
