// This part of YJIT helps interfacing with the rest of CRuby and with the OS.
// Sometimes our FFI binding generation tool gives undesirable outputs when it
// sees C features that Rust doesn't support well. We mitigate that by binding
// functions which have simple parameter types. The boilerplate C functions for
// that purpose are in this file.
// Similarly, we wrap OS facilities we need in simple functions to help with
// FFI and to avoid the need to use external crates.io Rust libraries.

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
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "yjit.h"
#include "zjit.h"
#include "vm_insnhelper.h"
#include "probes.h"
#include "probes_helper.h"
#include "iseq.h"
#include "ruby/debug.h"
#include "internal/cont.h"

// For mmapp(), sysconf()
#ifndef _WIN32
#include <unistd.h>
#include <sys/mman.h>
#endif

#include <errno.h>

// We need size_t to have a known size to simplify code generation and FFI.
// TODO(alan): check this in configure.ac to fail fast on 32 bit platforms.
STATIC_ASSERT(64b_size_t, SIZE_MAX == UINT64_MAX);
// I don't know any C implementation that has uint64_t and puts padding bits
// into size_t but the standard seems to allow it.
STATIC_ASSERT(size_t_no_padding_bits, sizeof(size_t) == sizeof(uint64_t));

// This build config impacts the pointer tagging scheme and we only want to
// support one scheme for simplicity.
STATIC_ASSERT(pointer_tagging_scheme, USE_FLONUM);

// NOTE: We can trust that uint8_t has no "padding bits" since the C spec
// guarantees it. Wording about padding bits is more explicit in C11 compared
// to C99. See C11 7.20.1.1p2. All this is to say we have _some_ standards backing to
// use a Rust `*mut u8` to represent a C `uint8_t *`.
//
// If we don't want to trust that we can interpreter the C standard correctly, we
// could outsource that work to the Rust standard library by sticking to fundamental
// types in C such as int, long, etc. and use `std::os::raw::c_long` and friends on
// the Rust side.
//
// What's up with the long prefix? Even though we build with `-fvisibility=hidden`
// we are sometimes a static library where the option doesn't prevent name collision.
// The "_yjit_" part is for trying to be informative. We might want different
// suffixes for symbols meant for Rust and symbols meant for broader CRuby.

// For a given raw_sample (frame), set the hash with the caller's
// name, file, and line number. Return the  hash with collected frame_info.
static void
rb_yjit_add_frame(VALUE hash, VALUE frame)
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

// Parses the YjitExitLocations raw_samples and line_samples collected by
// rb_yjit_record_exit_stack and turns them into 3 hashes (raw, lines, and frames) to
// be used by RubyVM::YJIT.exit_locations. yjit_raw_samples represents the raw frames information
// (without name, file, and line), and yjit_line_samples represents the line information
// of the iseq caller.
VALUE
rb_yjit_exit_locations_dict(VALUE *yjit_raw_samples, int *yjit_line_samples, int samples_len)
{
    VALUE result = rb_hash_new();
    VALUE raw_samples = rb_ary_new_capa(samples_len);
    VALUE line_samples = rb_ary_new_capa(samples_len);
    VALUE frames = rb_hash_new();
    int idx = 0;

    // While the index is less than samples_len, parse yjit_raw_samples and
    // yjit_line_samples, then add casted values to raw_samples and line_samples array.
    while (idx < samples_len) {
        int num = (int)yjit_raw_samples[idx];
        int line_num = (int)yjit_line_samples[idx];
        idx++;

        // + 1 as we append an additional sample for the insn
        rb_ary_push(raw_samples, SIZET2NUM(num + 1));
        rb_ary_push(line_samples, INT2NUM(line_num + 1));

        // Loop through the length of samples_len and add data to the
        // frames hash. Also push the current value onto the raw_samples
        // and line_samples array respectively.
        for (int o = 0; o < num; o++) {
            rb_yjit_add_frame(frames, yjit_raw_samples[idx]);
            rb_ary_push(raw_samples, SIZET2NUM(yjit_raw_samples[idx]));
            rb_ary_push(line_samples, INT2NUM(yjit_line_samples[idx]));
            idx++;
        }

        rb_ary_push(raw_samples, SIZET2NUM(yjit_raw_samples[idx]));
        rb_ary_push(line_samples, INT2NUM(yjit_line_samples[idx]));
        idx++;

        rb_ary_push(raw_samples, SIZET2NUM(yjit_raw_samples[idx]));
        rb_ary_push(line_samples, INT2NUM(yjit_line_samples[idx]));
        idx++;
    }

    // Set add the raw_samples, line_samples, and frames to the results
    // hash.
    rb_hash_aset(result, ID2SYM(rb_intern("raw")), raw_samples);
    rb_hash_aset(result, ID2SYM(rb_intern("lines")), line_samples);
    rb_hash_aset(result, ID2SYM(rb_intern("frames")), frames);

    return result;
}

// Is anyone listening for :c_call and :c_return event currently?
bool
rb_c_method_tracing_currently_enabled(const rb_execution_context_t *ec)
{
    return ruby_vm_c_events_enabled > 0;
}

// The code we generate in gen_send_cfunc() doesn't fire the c_return TracePoint event
// like the interpreter. When tracing for c_return is enabled, we patch the code after
// the C method return to call into this to fire the event.
void
rb_full_cfunc_return(rb_execution_context_t *ec, VALUE return_value)
{
    rb_control_frame_t *cfp = ec->cfp;
    RUBY_ASSERT_ALWAYS(cfp == GET_EC()->cfp);
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    RUBY_ASSERT_ALWAYS(RUBYVM_CFUNC_FRAME_P(cfp));
    RUBY_ASSERT_ALWAYS(me->def->type == VM_METHOD_TYPE_CFUNC);

    // CHECK_CFP_CONSISTENCY("full_cfunc_return"); TODO revive this

    // Pop the C func's frame and fire the c_return TracePoint event
    // Note that this is the same order as vm_call_cfunc_with_frame().
    rb_vm_pop_frame(ec);
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, cfp->self, me->def->original_id, me->called_id, me->owner, return_value);
    // Note, this deviates from the interpreter in that users need to enable
    // a c_return TracePoint for this DTrace hook to work. A reasonable change
    // since the Ruby return event works this way as well.
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, me->owner, me->def->original_id);

    // Push return value into the caller's stack. We know that it's a frame that
    // uses cfp->sp because we are patching a call done with gen_send_cfunc().
    ec->cfp->sp[0] = return_value;
    ec->cfp->sp++;
}

// TODO(alan): consider using an opaque pointer for the payload rather than a void pointer
void *
rb_iseq_get_yjit_payload(const rb_iseq_t *iseq)
{
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(iseq, imemo_iseq));
    if (iseq->body) {
        return iseq->body->yjit_payload;
    }
    else {
        // Body is NULL when constructing the iseq.
        return NULL;
    }
}

void
rb_iseq_set_yjit_payload(const rb_iseq_t *iseq, void *payload)
{
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(iseq, imemo_iseq));
    RUBY_ASSERT_ALWAYS(iseq->body);
    RUBY_ASSERT_ALWAYS(NULL == iseq->body->yjit_payload);
    iseq->body->yjit_payload = payload;
}

// This is defined only as a named struct inside rb_iseq_constant_body.
// By giving it a separate typedef, we make it nameable by rust-bindgen.
// Bindgen's temp/anon name isn't guaranteed stable.
typedef struct rb_iseq_param_keyword rb_seq_param_keyword_struct;

ID rb_get_symbol_id(VALUE namep);

VALUE
rb_optimized_call(VALUE *recv, rb_execution_context_t *ec, int argc, VALUE *argv, int kw_splat, VALUE block_handler)
{
    rb_proc_t *proc;
    GetProcPtr(recv, proc);
    return rb_vm_invoke_proc(ec, proc, argc, argv, kw_splat, block_handler);
}

// If true, the iseq has only opt_invokebuiltin_delegate(_leave) and leave insns.
static bool
invokebuiltin_delegate_leave_p(const rb_iseq_t *iseq)
{
    int insn1 = rb_vm_insn_addr2opcode((void *)iseq->body->iseq_encoded[0]);
    if ((int)iseq->body->iseq_size != insn_len(insn1) + insn_len(BIN(leave))) {
        return false;
    }
    int insn2 = rb_vm_insn_addr2opcode((void *)iseq->body->iseq_encoded[insn_len(insn1)]);
    return (insn1 == BIN(opt_invokebuiltin_delegate) || insn1 == BIN(opt_invokebuiltin_delegate_leave)) &&
            insn2 == BIN(leave);
}

// Return an rb_builtin_function if the iseq contains only that builtin function.
const struct rb_builtin_function *
rb_yjit_builtin_function(const rb_iseq_t *iseq)
{
    if (invokebuiltin_delegate_leave_p(iseq)) {
        return (const struct rb_builtin_function *)iseq->body->iseq_encoded[1];
    }
    else {
        return NULL;
    }
}

VALUE
rb_yjit_str_simple_append(VALUE str1, VALUE str2)
{
    return rb_str_cat(str1, RSTRING_PTR(str2), RSTRING_LEN(str2));
}

extern VALUE *rb_vm_base_ptr(struct rb_control_frame_struct *cfp);

VALUE
rb_str_neq_internal(VALUE str1, VALUE str2)
{
    return rb_str_eql_internal(str1, str2) == Qtrue ? Qfalse : Qtrue;
}

extern VALUE rb_ary_unshift_m(int argc, VALUE *argv, VALUE ary);

VALUE
rb_yjit_rb_ary_subseq_length(VALUE ary, long beg)
{
    long len = RARRAY_LEN(ary);
    return rb_ary_subseq(ary, beg, len);
}

// Return non-zero when `obj` is an array and its last item is a
// `ruby2_keywords` hash. We don't support this kind of splat.
size_t
rb_yjit_ruby2_keywords_splat_p(VALUE obj)
{
    if (!RB_TYPE_P(obj, T_ARRAY)) return 0;
    long len = RARRAY_LEN(obj);
    if (len == 0) return 0;
    VALUE last = RARRAY_AREF(obj, len - 1);
    if (!RB_TYPE_P(last, T_HASH)) return 0;
    return FL_TEST_RAW(last, RHASH_PASS_AS_KEYWORDS);
}

// Checks to establish preconditions for rb_yjit_splat_varg_cfunc()
VALUE
rb_yjit_splat_varg_checks(VALUE *sp, VALUE splat_array, rb_control_frame_t *cfp)
{
    // We inserted a T_ARRAY guard before this call
    long len = RARRAY_LEN(splat_array);

    // Large splat arrays need a separate allocation
    if (len < 0 || len > VM_ARGC_STACK_MAX) return Qfalse;

    // Would we overflow if we put the contents of the array onto the stack?
    if (sp + len > (VALUE *)(cfp - 2)) return Qfalse;

    // Reject keywords hash since that requires duping it sometimes
    if (len > 0) {
        VALUE last_hash = RARRAY_AREF(splat_array, len - 1);
        if (RB_TYPE_P(last_hash, T_HASH) &&
                FL_TEST_RAW(last_hash, RHASH_PASS_AS_KEYWORDS)) {
            return Qfalse;
        }
    }

    return Qtrue;
}

// Push array elements to the stack for a C method that has a variable number
// of parameters. Returns the number of arguments the splat array contributes.
int
rb_yjit_splat_varg_cfunc(VALUE *stack_splat_array)
{
    VALUE splat_array = *stack_splat_array;
    int len;

    // We already checked that length fits in `int`
    RUBY_ASSERT(RB_TYPE_P(splat_array, T_ARRAY));
    len = (int)RARRAY_LEN(splat_array);

    // Push the contents of the array onto the stack
    MEMCPY(stack_splat_array, RARRAY_CONST_PTR(splat_array), VALUE, len);

    return len;
}

// Print the Ruby source location of some ISEQ for debugging purposes
void
rb_yjit_dump_iseq_loc(const rb_iseq_t *iseq, uint32_t insn_idx)
{
    char *ptr;
    long len;
    VALUE path = rb_iseq_path(iseq);
    RSTRING_GETMEM(path, ptr, len);
    fprintf(stderr, "%s %.*s:%u\n", __func__, (int)len, ptr, rb_iseq_line_no(iseq, insn_idx));
}

// Get the number of digits required to print an integer
static int
num_digits(int integer)
{
    int num = 1;
    while (integer /= 10) {
        num++;
    }
    return num;
}

// Allocate a C string that formats an ISEQ label like iseq_inspect()
char *
rb_yjit_iseq_inspect(const rb_iseq_t *iseq)
{
    const char *label = RSTRING_PTR(iseq->body->location.label);
    const char *path = RSTRING_PTR(rb_iseq_path(iseq));
    int lineno = iseq->body->location.code_location.beg_pos.lineno;

    const size_t size = strlen(label) + strlen(path) + num_digits(lineno) + 3;
    char *buf = ZALLOC_N(char, size);
    snprintf(buf, size, "%s@%s:%d", label, path, lineno);
    return buf;
}

// There are RSTRUCT_SETs in ruby/internal/core/rstruct.h and internal/struct.h
// with different types (int vs long) for k. Here we use the one from ruby/internal/core/rstruct.h,
// which takes an int.
void
rb_RSTRUCT_SET(VALUE st, int k, VALUE v)
{
    RSTRUCT_SET(st, k, v);
}

// Return the string encoding index
int
rb_ENCODING_GET(VALUE obj)
{
    return RB_ENCODING_GET(obj);
}

bool
rb_yjit_constcache_shareable(const struct iseq_inline_constant_cache_entry *ice)
{
    return (ice->flags & IMEMO_CONST_CACHE_SHAREABLE) != 0;
}

// For running write barriers from Rust. Required when we add a new edge in the
// object graph from `old` to `young`.
void
rb_yjit_obj_written(VALUE old, VALUE young, const char *file, int line)
{
    rb_obj_written(old, Qundef, young, file, line);
}

void
rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception)
{
    RB_VM_LOCKING() {
        rb_vm_barrier();

        // Compile a block version starting at the current instruction
        uint8_t *rb_yjit_iseq_gen_entry_point(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception); // defined in Rust
        uintptr_t code_ptr = (uintptr_t)rb_yjit_iseq_gen_entry_point(iseq, ec, jit_exception);

        if (jit_exception) {
            iseq->body->jit_exception = (rb_jit_func_t)code_ptr;
        }
        else {
            iseq->body->jit_entry = (rb_jit_func_t)code_ptr;
        }
    }
}

// GC root for interacting with the GC
struct yjit_root_struct {
    bool unused; // empty structs are not legal in C99
};

// For dealing with refinements
void
rb_yjit_invalidate_all_method_lookup_assumptions(void)
{
    // It looks like Module#using actually doesn't need to invalidate all the
    // method caches, so we do nothing here for now.
}

// Number of object shapes, which might be useful for investigating YJIT exit reasons.
VALUE
rb_object_shape_count(void)
{
    // next_shape_id starts from 0, so it's the same as the count
    return ULONG2NUM((unsigned long)rb_shapes_count());
}

bool
rb_yjit_shape_obj_too_complex_p(VALUE obj)
{
    return rb_shape_obj_too_complex_p(obj);
}

attr_index_t
rb_yjit_shape_capacity(shape_id_t shape_id)
{
    return RSHAPE_CAPACITY(shape_id);
}

attr_index_t
rb_yjit_shape_index(shape_id_t shape_id)
{
    return RSHAPE_INDEX(shape_id);
}

// The number of stack slots that vm_sendish() pops for send and invokesuper.
size_t
rb_yjit_sendish_sp_pops(const struct rb_callinfo *ci)
{
    return 1 - sp_inc_of_sendish(ci); // + 1 to ignore return value push
}

// The number of stack slots that vm_sendish() pops for invokeblock.
size_t
rb_yjit_invokeblock_sp_pops(const struct rb_callinfo *ci)
{
    return 1 - sp_inc_of_invokeblock(ci); // + 1 to ignore return value push
}

rb_serial_t
rb_yjit_cme_ractor_serial(const rb_callable_method_entry_t *cme)
{
    return cme->def->body.bmethod.defined_ractor_id;
}

// Setup jit_return to avoid returning a non-Qundef value on a non-FINISH frame.
// See [jit_compile_exception] for details.
void
rb_yjit_set_exception_return(rb_control_frame_t *cfp, void *leave_exit, void *leave_exception)
{
    if (VM_FRAME_FINISHED_P(cfp)) {
        // If it's a FINISH frame, just normally exit with a non-Qundef value.
        cfp->jit_return = leave_exit;
    }
    else if (cfp->jit_return) {
        while (!VM_FRAME_FINISHED_P(cfp)) {
            if (cfp->jit_return == leave_exit) {
                // Unlike jit_exec(), leave_exit is not safe on a non-FINISH frame on
                // jit_exec_exception(). See [jit_exec] and [jit_exec_exception] for
                // details. Exit to the interpreter with Qundef to let it keep executing
                // other Ruby frames.
                cfp->jit_return = leave_exception;
                return;
            }
            cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
        }
    }
    else {
        // If the caller was not JIT code, exit to the interpreter with Qundef
        // to keep executing Ruby frames with the interpreter.
        cfp->jit_return = leave_exception;
    }
}

// VM_INSTRUCTION_SIZE changes depending on if ZJIT is in the build. Since
// bindgen can only grab one version of the constant and copy that to rust,
// we make that the upper bound and this the accurate value.
uint32_t
rb_vm_instruction_size(void)
{
    return VM_INSTRUCTION_SIZE;
}

// Primitives used by yjit.rb
VALUE rb_yjit_stats_enabled_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_print_stats_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_log_enabled_p(rb_execution_context_t *c, VALUE self);
VALUE rb_yjit_print_log_p(rb_execution_context_t *c, VALUE self);
VALUE rb_yjit_trace_exit_locations_enabled_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_get_stats(rb_execution_context_t *ec, VALUE self, VALUE key);
VALUE rb_yjit_reset_stats_bang(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_get_log(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_disasm_iseq(rb_execution_context_t *ec, VALUE self, VALUE iseq);
VALUE rb_yjit_insns_compiled(rb_execution_context_t *ec, VALUE self, VALUE iseq);
VALUE rb_yjit_code_gc(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_simulate_oom_bang(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_get_exit_locations(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_enable(rb_execution_context_t *ec, VALUE self, VALUE gen_stats, VALUE print_stats, VALUE gen_compilation_log, VALUE print_compilation_log, VALUE mem_size, VALUE call_threshold);
VALUE rb_yjit_c_builtin_p(rb_execution_context_t *ec, VALUE self);

// Allow YJIT_C_BUILTIN macro to force --yjit-c-builtin
#ifdef YJIT_C_BUILTIN
static VALUE yjit_c_builtin_p(rb_execution_context_t *ec, VALUE self) { return Qtrue; }
#else
#define yjit_c_builtin_p rb_yjit_c_builtin_p
#endif

// Preprocessed yjit.rb generated during build
#include "yjit.rbinc"

