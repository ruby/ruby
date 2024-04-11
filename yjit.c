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
#include "vm_sync.h"
#include "yjit.h"
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

// Field offsets for the RObject struct
enum robject_offsets {
    ROBJECT_OFFSET_AS_HEAP_IVPTR = offsetof(struct RObject, as.heap.ivptr),
    ROBJECT_OFFSET_AS_HEAP_IV_INDEX_TBL = offsetof(struct RObject, as.heap.iv_index_tbl),
    ROBJECT_OFFSET_AS_ARY = offsetof(struct RObject, as.ary),
};

// Field offsets for the RString struct
enum rstring_offsets {
    RUBY_OFFSET_RSTRING_LEN = offsetof(struct RString, len)
};

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

bool
rb_yjit_mark_writable(void *mem_block, uint32_t mem_size)
{
    return mprotect(mem_block, mem_size, PROT_READ | PROT_WRITE) == 0;
}

void
rb_yjit_mark_executable(void *mem_block, uint32_t mem_size)
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
rb_yjit_mark_unused(void *mem_block, uint32_t mem_size)
{
    // On Linux, you need to use madvise MADV_DONTNEED to free memory.
    // We might not need to call this on macOS, but it's not really documented.
    // We generally prefer to do the same thing on both to ease testing too.
    madvise(mem_block, mem_size, MADV_DONTNEED);

    // On macOS, mprotect PROT_NONE seems to reduce RSS.
    // We also call this on Linux to avoid executing unused pages.
    return mprotect(mem_block, mem_size, PROT_NONE) == 0;
}

long
rb_yjit_array_len(VALUE a)
{
    return rb_array_len(a);
}

// `start` is inclusive and `end` is exclusive.
void
rb_yjit_icache_invalidate(void *start, void *end)
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

# define PTR2NUM(x)   (rb_int2inum((intptr_t)(void *)(x)))

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

uint32_t
rb_yjit_get_page_size(void)
{
#if defined(_SC_PAGESIZE)
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) rb_bug("yjit: failed to get page size");

    // 1 GiB limit. x86 CPUs with PDPE1GB can do this and anything larger is unexpected.
    // Though our design sort of assume we have fine grained control over memory protection
    // which require small page sizes.
    if (page_size > 0x40000000l) rb_bug("yjit page size too large");

    return (uint32_t)page_size;
#else
#error "YJIT supports POSIX only for now"
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
rb_yjit_reserve_addr_space(uint32_t mem_size)
{
#ifndef _WIN32
    uint8_t *mem_block;

    // On Linux
    #if defined(MAP_FIXED_NOREPLACE) && defined(_SC_PAGESIZE)
        uint32_t const page_size = (uint32_t)sysconf(_SC_PAGESIZE);
        uint8_t *const cfunc_sample_addr = (void *)&rb_yjit_reserve_addr_space;
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
                break;
            }

            // +4MB
            req_addr += 4 * 1024 * 1024;
        } while (req_addr < probe_region_end);

    // On MacOS and other platforms
    #else
        // Try to map a chunk of memory as executable
        mem_block = mmap(
            (void *)rb_yjit_reserve_addr_space,
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
    }

    // Check that the memory mapping was successful
    if (mem_block == MAP_FAILED) {
        perror("ruby: yjit: mmap:");
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

// Is anyone listening for :c_call and :c_return event currently?
bool
rb_c_method_tracing_currently_enabled(const rb_execution_context_t *ec)
{
    rb_event_flag_t tracing_events;
    if (rb_multi_ractor_p()) {
        tracing_events = ruby_vm_event_enabled_global_flags;
    }
    else {
        // At the time of writing, events are never removed from
        // ruby_vm_event_enabled_global_flags so always checking using it would
        // mean we don't compile even after tracing is disabled.
        tracing_events = rb_ec_ractor_hooks(ec)->events;
    }

    return tracing_events & (RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN);
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

unsigned int
rb_iseq_encoded_size(const rb_iseq_t *iseq)
{
    return iseq->body->iseq_size;
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
    // YJIT should only use iseqs after AST to bytecode compilation
    RUBY_ASSERT_ALWAYS(FL_TEST_RAW((VALUE)iseq, ISEQ_TRANSLATED));

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

rb_proc_t *
rb_yjit_get_proc_ptr(VALUE procv)
{
    rb_proc_t *proc;
    GetProcPtr(procv, proc);
    return proc;
}

// This is defined only as a named struct inside rb_iseq_constant_body.
// By giving it a separate typedef, we make it nameable by rust-bindgen.
// Bindgen's temp/anon name isn't guaranteed stable.
typedef struct rb_iseq_param_keyword rb_seq_param_keyword_struct;

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

ID rb_get_symbol_id(VALUE namep);

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

int
rb_get_mct_argc(const rb_method_cfunc_t *mct)
{
    return mct->argc;
}

void *
rb_get_mct_func(const rb_method_cfunc_t *mct)
{
    return (void*)mct->func; // this field is defined as type VALUE (*func)(ANYARGS)
}

const rb_iseq_t *
rb_get_def_iseq_ptr(rb_method_definition_t *def)
{
    return def_iseq_ptr(def);
}

VALUE
rb_get_def_bmethod_proc(rb_method_definition_t *def)
{
    RUBY_ASSERT(def->type == VM_METHOD_TYPE_BMETHOD);
    return def->body.bmethod.proc;
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

const rb_seq_param_keyword_struct *
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

VALUE
rb_optimized_call(VALUE *recv, rb_execution_context_t *ec, int argc, VALUE *argv, int kw_splat, VALUE block_handler)
{
    rb_proc_t *proc;
    GetProcPtr(recv, proc);
    return rb_vm_invoke_proc(ec, proc, argc, argv, kw_splat, block_handler);
}

unsigned int
rb_yjit_iseq_builtin_attrs(const rb_iseq_t *iseq)
{
    return iseq->body->builtin_attrs;
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

extern VALUE *rb_vm_base_ptr(struct rb_control_frame_struct *cfp);

VALUE
rb_yarv_class_of(VALUE obj)
{
    return rb_class_of(obj);
}

// YJIT needs this function to never allocate and never raise
VALUE
rb_yarv_str_eql_internal(VALUE str1, VALUE str2)
{
    // We wrap this since it's static inline
    return rb_str_eql_internal(str1, str2);
}

VALUE
rb_str_neq_internal(VALUE str1, VALUE str2)
{
    return rb_str_eql_internal(str1, str2) == Qtrue ? Qfalse : Qtrue;
}

// YJIT needs this function to never allocate and never raise
VALUE
rb_yarv_ary_entry_internal(VALUE ary, long offset)
{
    return rb_ary_entry_internal(ary, offset);
}

extern VALUE rb_ary_unshift_m(int argc, VALUE *argv, VALUE ary);

VALUE
rb_yjit_rb_ary_subseq_length(VALUE ary, long beg)
{
    long len = RARRAY_LEN(ary);
    return rb_ary_subseq(ary, beg, len);
}

VALUE
rb_yjit_fix_div_fix(VALUE recv, VALUE obj)
{
    return rb_fix_div_fix(recv, obj);
}

VALUE
rb_yjit_fix_mod_fix(VALUE recv, VALUE obj)
{
    return rb_fix_mod_fix(recv, obj);
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

    char *buf = ZALLOC_N(char, strlen(label) + strlen(path) + num_digits(lineno) + 3);
    sprintf(buf, "%s@%s:%d", label, path, lineno);
    return buf;
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

// There are RSTRUCT_SETs in ruby/internal/core/rstruct.h and internal/struct.h
// with different types (int vs long) for k. Here we use the one from ruby/internal/core/rstruct.h,
// which takes an int.
void
rb_RSTRUCT_SET(VALUE st, int k, VALUE v)
{
    RSTRUCT_SET(st, k, v);
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

// Return the string encoding index
int
rb_ENCODING_GET(VALUE obj)
{
    return RB_ENCODING_GET(obj);
}

bool
rb_yjit_multi_ractor_p(void)
{
    return rb_multi_ractor_p();
}

// For debug builds
void
rb_assert_iseq_handle(VALUE handle)
{
    RUBY_ASSERT_ALWAYS(rb_objspace_markable_object_p(handle));
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(handle, imemo_iseq));
}

int
rb_IMEMO_TYPE_P(VALUE imemo, enum imemo_type imemo_type)
{
    return IMEMO_TYPE_P(imemo, imemo_type);
}

void
rb_assert_cme_handle(VALUE handle)
{
    RUBY_ASSERT_ALWAYS(rb_objspace_markable_object_p(handle));
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(handle, imemo_ment));
}

// Used for passing a callback and other data over rb_objspace_each_objects
struct iseq_callback_data {
    rb_iseq_callback callback;
    void *data;
};

// Heap-walking callback for rb_yjit_for_each_iseq().
static int
for_each_iseq_i(void *vstart, void *vend, size_t stride, void *data)
{
    const struct iseq_callback_data *callback_data = (struct iseq_callback_data *)data;
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        void *ptr = asan_poisoned_object_p(v);
        asan_unpoison_object(v, false);

        if (rb_obj_is_iseq(v)) {
            rb_iseq_t *iseq = (rb_iseq_t *)v;
            callback_data->callback(iseq, callback_data->data);
        }

        asan_poison_object_if(ptr, v);
    }
    return 0;
}

// Iterate through the whole GC heap and invoke a callback for each iseq.
// Used for global code invalidation.
void
rb_yjit_for_each_iseq(rb_iseq_callback callback, void *data)
{
    struct iseq_callback_data callback_data = { .callback = callback, .data = data };
    rb_objspace_each_objects(for_each_iseq_i, (void *)&callback_data);
}

// For running write barriers from Rust. Required when we add a new edge in the
// object graph from `old` to `young`.
void
rb_yjit_obj_written(VALUE old, VALUE young, const char *file, int line)
{
    rb_obj_written(old, Qundef, young, file, line);
}

// Acquire the VM lock and then signal all other Ruby threads (ractors) to
// contend for the VM lock, putting them to sleep. YJIT uses this to evict
// threads running inside generated code so among other things, it can
// safely change memory protection of regions housing generated code.
void
rb_yjit_vm_lock_then_barrier(unsigned int *recursive_lock_level, const char *file, int line)
{
    rb_vm_lock_enter(recursive_lock_level, file, line);
    rb_vm_barrier();
}

// Release the VM lock. The lock level must point to the same integer used to
// acquire the lock.
void
rb_yjit_vm_unlock(unsigned int *recursive_lock_level, const char *file, int line)
{
    rb_vm_lock_leave(recursive_lock_level, file, line);
}

void
rb_yjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception)
{
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    // Compile a block version starting at the current instruction
    uint8_t *rb_yjit_iseq_gen_entry_point(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception); // defined in Rust
    uint8_t *code_ptr = rb_yjit_iseq_gen_entry_point(iseq, ec, jit_exception);

    if (jit_exception) {
        iseq->body->jit_exception = (rb_jit_func_t)code_ptr;
    }
    else {
        iseq->body->jit_entry = (rb_jit_func_t)code_ptr;
    }

    RB_VM_LOCK_LEAVE();
}

// GC root for interacting with the GC
struct yjit_root_struct {
    bool unused; // empty structs are not legal in C99
};

static void
yjit_root_free(void *ptr)
{
    // Do nothing. The root lives as long as the process.
}

static size_t
yjit_root_memsize(const void *ptr)
{
    // Count off-gc-heap allocation size of the dependency table
    return 0; // TODO: more accurate accounting
}

// GC callback during compaction
static void
yjit_root_update_references(void *ptr)
{
    // Do nothing since we use rb_gc_mark(), which pins.
}

void rb_yjit_root_mark(void *ptr); // in Rust

// Custom type for interacting with the GC
// TODO: make this write barrier protected
static const rb_data_type_t yjit_root_type = {
    "yjit_root",
    {rb_yjit_root_mark, yjit_root_free, yjit_root_memsize, yjit_root_update_references},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

// For dealing with refinements
void
rb_yjit_invalidate_all_method_lookup_assumptions(void)
{
    // It looks like Module#using actually doesn't need to invalidate all the
    // method caches, so we do nothing here for now.
}

// Number of object shapes, which might be useful for investigating YJIT exit reasons.
static VALUE
object_shape_count(rb_execution_context_t *ec, VALUE self)
{
    // next_shape_id starts from 0, so it's the same as the count
    return ULONG2NUM((unsigned long)GET_SHAPE_TREE()->next_shape_id);
}

// Assert that we have the VM lock. Relevant mostly for multi ractor situations.
// The GC takes the lock before calling us, and this asserts that it indeed happens.
void
rb_yjit_assert_holding_vm_lock(void)
{
    ASSERT_vm_locking();
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

// Primitives used by yjit.rb
VALUE rb_yjit_stats_enabled_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_print_stats_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_trace_exit_locations_enabled_p(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_get_stats(rb_execution_context_t *ec, VALUE self, VALUE context);
VALUE rb_yjit_reset_stats_bang(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_disasm_iseq(rb_execution_context_t *ec, VALUE self, VALUE iseq);
VALUE rb_yjit_insns_compiled(rb_execution_context_t *ec, VALUE self, VALUE iseq);
VALUE rb_yjit_code_gc(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_simulate_oom_bang(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_get_exit_locations(rb_execution_context_t *ec, VALUE self);
VALUE rb_yjit_enable(rb_execution_context_t *ec, VALUE self, VALUE gen_stats, VALUE print_stats);

// Preprocessed yjit.rb generated during build
#include "yjit.rbinc"

// Initialize the GC hooks
void
rb_yjit_init_gc_hooks(void)
{
    struct yjit_root_struct *root;
    VALUE yjit_root = TypedData_Make_Struct(0, struct yjit_root_struct, &yjit_root_type, root);
    rb_vm_register_global_object(yjit_root);
}
