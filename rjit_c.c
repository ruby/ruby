/**********************************************************************

  rjit_c.c - C helpers for RJIT

  Copyright (C) 2017 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "rjit.h" // defines USE_RJIT

#if USE_RJIT

#include "rjit_c.h"
#include "include/ruby/assert.h"
#include "include/ruby/debug.h"
#include "internal.h"
#include "internal/compile.h"
#include "internal/fixnum.h"
#include "internal/hash.h"
#include "internal/sanitizers.h"
#include "internal/gc.h"
#include "internal/proc.h"
#include "yjit.h"
#include "vm_insnhelper.h"
#include "probes.h"
#include "probes_helper.h"

#include "insns.inc"
#include "insns_info.inc"

// For mmapp(), sysconf()
#ifndef _WIN32
#include <unistd.h>
#include <sys/mman.h>
#endif

#include <errno.h>

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
static uint8_t *
rjit_reserve_addr_space(uint32_t mem_size)
{
#ifndef _WIN32
    uint8_t *mem_block;

    // On Linux
    #if defined(MAP_FIXED_NOREPLACE) && defined(_SC_PAGESIZE)
        uint32_t const page_size = (uint32_t)sysconf(_SC_PAGESIZE);
        uint8_t *const cfunc_sample_addr = (void *)(uintptr_t)&rjit_reserve_addr_space;
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
                ruby_annotate_mmap(mem_block, mem_size, "Ruby:rjit_reserve_addr_space");
                break;
            }

            // +4MB
            req_addr += 4 * 1024 * 1024;
        } while (req_addr < probe_region_end);

    // On MacOS and other platforms
    #else
        // Try to map a chunk of memory as executable
        mem_block = mmap(
            (void *)rjit_reserve_addr_space,
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
            ruby_annotate_mmap(mem_block, mem_size, "Ruby:rjit_reserve_addr_space:fallback");
        }
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

static VALUE
mprotect_write(rb_execution_context_t *ec, VALUE self, VALUE rb_mem_block, VALUE rb_mem_size)
{
    void *mem_block = (void *)NUM2SIZET(rb_mem_block);
    uint32_t mem_size = NUM2UINT(rb_mem_size);
    return RBOOL(mprotect(mem_block, mem_size, PROT_READ | PROT_WRITE) == 0);
}

static VALUE
mprotect_exec(rb_execution_context_t *ec, VALUE self, VALUE rb_mem_block, VALUE rb_mem_size)
{
    void *mem_block = (void *)NUM2SIZET(rb_mem_block);
    uint32_t mem_size = NUM2UINT(rb_mem_size);
    if (mem_size == 0) return Qfalse; // Some platforms return an error for mem_size 0.

    if (mprotect(mem_block, mem_size, PROT_READ | PROT_EXEC)) {
        rb_bug("Couldn't make JIT page (%p, %lu bytes) executable, errno: %s",
            mem_block, (unsigned long)mem_size, strerror(errno));
    }
    return Qtrue;
}

static VALUE
rjit_optimized_call(VALUE *recv, rb_execution_context_t *ec, int argc, VALUE *argv, int kw_splat, VALUE block_handler)
{
    rb_proc_t *proc;
    GetProcPtr(recv, proc);
    return rb_vm_invoke_proc(ec, proc, argc, argv, kw_splat, block_handler);
}

static VALUE
rjit_str_neq_internal(VALUE str1, VALUE str2)
{
    return rb_str_eql_internal(str1, str2) == Qtrue ? Qfalse : Qtrue;
}

static VALUE
rjit_str_simple_append(VALUE str1, VALUE str2)
{
    return rb_str_cat(str1, RSTRING_PTR(str2), RSTRING_LEN(str2));
}

static VALUE
rjit_rb_ary_subseq_length(VALUE ary, long beg)
{
    long len = RARRAY_LEN(ary);
    return rb_ary_subseq(ary, beg, len);
}

static VALUE
rjit_build_kwhash(const struct rb_callinfo *ci, VALUE *sp)
{
    const struct rb_callinfo_kwarg *kw_arg = vm_ci_kwarg(ci);
    int kw_len = kw_arg->keyword_len;
    VALUE hash = rb_hash_new_with_size(kw_len);

    for (int i = 0; i < kw_len; i++) {
        VALUE key = kw_arg->keywords[i];
        VALUE val = *(sp - kw_len + i);
        rb_hash_aset(hash, key, val);
    }
    return hash;
}

// The code we generate in gen_send_cfunc() doesn't fire the c_return TracePoint event
// like the interpreter. When tracing for c_return is enabled, we patch the code after
// the C method return to call into this to fire the event.
static void
rjit_full_cfunc_return(rb_execution_context_t *ec, VALUE return_value)
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

static rb_proc_t *
rjit_get_proc_ptr(VALUE procv)
{
    rb_proc_t *proc;
    GetProcPtr(procv, proc);
    return proc;
}

// Use the same buffer size as Stackprof.
#define BUFF_LEN 2048

extern VALUE rb_rjit_raw_samples;
extern VALUE rb_rjit_line_samples;

static void
rjit_record_exit_stack(const VALUE *exit_pc)
{
    // Let Primitive.rjit_stop_stats stop this
    if (!rb_rjit_call_p) return;

    // Get the opcode from the encoded insn handler at this PC
    int insn = rb_vm_insn_addr2opcode((void *)*exit_pc);

    // Create 2 array buffers to be used to collect frames and lines.
    VALUE frames_buffer[BUFF_LEN] = { 0 };
    int lines_buffer[BUFF_LEN] = { 0 };

    // Records call frame and line information for each method entry into two
    // temporary buffers. Returns the number of times we added to the buffer (ie
    // the length of the stack).
    //
    // Call frame info is stored in the frames_buffer, line number information
    // in the lines_buffer. The first argument is the start point and the second
    // argument is the buffer limit, set at 2048.
    int stack_length = rb_profile_frames(0, BUFF_LEN, frames_buffer, lines_buffer);
    int samples_length = stack_length + 3; // 3: length, insn, count

    // If yjit_raw_samples is less than or equal to the current length of the samples
    // we might have seen this stack trace previously.
    int prev_stack_len_index = (int)RARRAY_LEN(rb_rjit_raw_samples) - samples_length;
    VALUE prev_stack_len_obj;
    if (RARRAY_LEN(rb_rjit_raw_samples) >= samples_length && FIXNUM_P(prev_stack_len_obj = RARRAY_AREF(rb_rjit_raw_samples, prev_stack_len_index))) {
        int prev_stack_len = NUM2INT(prev_stack_len_obj);
        int idx = stack_length - 1;
        int prev_frame_idx = 0;
        bool seen_already = true;

        // If the previous stack length and current stack length are equal,
        // loop and compare the current frame to the previous frame. If they are
        // not equal, set seen_already to false and break out of the loop.
        if (prev_stack_len == stack_length) {
            while (idx >= 0) {
                VALUE current_frame = frames_buffer[idx];
                VALUE prev_frame = RARRAY_AREF(rb_rjit_raw_samples, prev_stack_len_index + prev_frame_idx + 1);

                // If the current frame and previous frame are not equal, set
                // seen_already to false and break out of the loop.
                if (current_frame != prev_frame) {
                    seen_already = false;
                    break;
                }

                idx--;
                prev_frame_idx++;
            }

            // If we know we've seen this stack before, increment the counter by 1.
            if (seen_already) {
                int prev_idx = (int)RARRAY_LEN(rb_rjit_raw_samples) - 1;
                int prev_count = NUM2INT(RARRAY_AREF(rb_rjit_raw_samples, prev_idx));
                int new_count = prev_count + 1;

                rb_ary_store(rb_rjit_raw_samples, prev_idx, INT2NUM(new_count));
                rb_ary_store(rb_rjit_line_samples, prev_idx, INT2NUM(new_count));
                return;
            }
        }
    }

    rb_ary_push(rb_rjit_raw_samples, INT2NUM(stack_length));
    rb_ary_push(rb_rjit_line_samples, INT2NUM(stack_length));

    int idx = stack_length - 1;

    while (idx >= 0) {
        VALUE frame = frames_buffer[idx];
        int line = lines_buffer[idx];

        rb_ary_push(rb_rjit_raw_samples, frame);
        rb_ary_push(rb_rjit_line_samples, INT2NUM(line));

        idx--;
    }

    // Push the insn value into the yjit_raw_samples Vec.
    rb_ary_push(rb_rjit_raw_samples, INT2NUM(insn));

    // Push the current line onto the yjit_line_samples Vec. This
    // points to the line in insns.def.
    int line = (int)RARRAY_LEN(rb_rjit_line_samples) - 1;
    rb_ary_push(rb_rjit_line_samples, INT2NUM(line));

    // Push number of times seen onto the stack, which is 1
    // because it's the first time we've seen it.
    rb_ary_push(rb_rjit_raw_samples, INT2NUM(1));
    rb_ary_push(rb_rjit_line_samples, INT2NUM(1));
}

// For a given raw_sample (frame), set the hash with the caller's
// name, file, and line number. Return the  hash with collected frame_info.
static void
rjit_add_frame(VALUE hash, VALUE frame)
{
    VALUE frame_id = SIZET2NUM(frame);

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

static VALUE
rjit_exit_traces(void)
{
    int samples_len = (int)RARRAY_LEN(rb_rjit_raw_samples);
    RUBY_ASSERT(samples_len == RARRAY_LEN(rb_rjit_line_samples));

    VALUE result = rb_hash_new();
    VALUE raw_samples = rb_ary_new_capa(samples_len);
    VALUE line_samples = rb_ary_new_capa(samples_len);
    VALUE frames = rb_hash_new();
    int idx = 0;

    // While the index is less than samples_len, parse yjit_raw_samples and
    // yjit_line_samples, then add casted values to raw_samples and line_samples array.
    while (idx < samples_len) {
        int num = NUM2INT(RARRAY_AREF(rb_rjit_raw_samples, idx));
        int line_num = NUM2INT(RARRAY_AREF(rb_rjit_line_samples, idx));
        idx++;

        rb_ary_push(raw_samples, SIZET2NUM(num));
        rb_ary_push(line_samples, INT2NUM(line_num));

        // Loop through the length of samples_len and add data to the
        // frames hash. Also push the current value onto the raw_samples
        // and line_samples array respectively.
        for (int o = 0; o < num; o++) {
            rjit_add_frame(frames, RARRAY_AREF(rb_rjit_raw_samples, idx));
            rb_ary_push(raw_samples, SIZET2NUM(RARRAY_AREF(rb_rjit_raw_samples, idx)));
            rb_ary_push(line_samples, RARRAY_AREF(rb_rjit_line_samples, idx));
            idx++;
        }

        // insn BIN and lineno
        rb_ary_push(raw_samples, RARRAY_AREF(rb_rjit_raw_samples, idx));
        rb_ary_push(line_samples, RARRAY_AREF(rb_rjit_line_samples, idx));
        idx++;

        // Number of times seen
        rb_ary_push(raw_samples, RARRAY_AREF(rb_rjit_raw_samples, idx));
        rb_ary_push(line_samples, RARRAY_AREF(rb_rjit_line_samples, idx));
        idx++;
    }

    // Set add the raw_samples, line_samples, and frames to the results
    // hash.
    rb_hash_aset(result, ID2SYM(rb_intern("raw")), raw_samples);
    rb_hash_aset(result, ID2SYM(rb_intern("lines")), line_samples);
    rb_hash_aset(result, ID2SYM(rb_intern("frames")), frames);

    return result;
}

// An offsetof implementation that works for unnamed struct and union.
// Multiplying 8 for compatibility with libclang's offsetof.
#define OFFSETOF(ptr, member) RB_SIZE2NUM(((char *)&ptr.member - (char*)&ptr) * 8)

#define SIZEOF(type) RB_SIZE2NUM(sizeof(type))
#define SIGNED_TYPE_P(type) RBOOL((type)(-1) < (type)(1))

// Insn side exit counters
static size_t rjit_insn_exits[VM_INSTRUCTION_SIZE] = { 0 };

// macOS: brew install capstone
// Ubuntu/Debian: apt-get install libcapstone-dev
// Fedora: dnf -y install capstone-devel
#ifdef HAVE_LIBCAPSTONE
#include <capstone/capstone.h>
#endif

// Return an array of [address, mnemonic, op_str]
static VALUE
dump_disasm(rb_execution_context_t *ec, VALUE self, VALUE from, VALUE to, VALUE test)
{
    VALUE result = rb_ary_new();
#ifdef HAVE_LIBCAPSTONE
    // Prepare for calling cs_disasm
    static csh handle;
    if (cs_open(CS_ARCH_X86, CS_MODE_64, &handle) != CS_ERR_OK) {
        rb_raise(rb_eRuntimeError, "failed to make Capstone handle");
    }
    size_t from_addr = NUM2SIZET(from);
    size_t to_addr = NUM2SIZET(to);

    // Call cs_disasm and convert results to a Ruby array
    cs_insn *insns;
    size_t base_addr = RTEST(test) ? 0 : from_addr; // On tests, start from 0 for output stability.
    size_t count = cs_disasm(handle, (const uint8_t *)from_addr, to_addr - from_addr, base_addr, 0, &insns);
    for (size_t i = 0; i < count; i++) {
        VALUE vals = rb_ary_new_from_args(3, LONG2NUM(insns[i].address), rb_str_new2(insns[i].mnemonic), rb_str_new2(insns[i].op_str));
        rb_ary_push(result, vals);
    }

    // Free memory used by capstone
    cs_free(insns, count);
    cs_close(&handle);
#endif
    return result;
}

// Same as `RubyVM::RJIT.enabled?`, but this is used before it's defined.
static VALUE
rjit_enabled_p(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(rb_rjit_enabled);
}

static int
for_each_iseq_i(void *vstart, void *vend, size_t stride, void *data)
{
    VALUE block = (VALUE)data;
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        void *ptr = rb_asan_poisoned_object_p(v);
        rb_asan_unpoison_object(v, false);

        if (rb_obj_is_iseq(v)) {
            extern VALUE rb_rjit_iseq_new(rb_iseq_t *iseq);
            rb_iseq_t *iseq = (rb_iseq_t *)v;
            rb_funcall(block, rb_intern("call"), 1, rb_rjit_iseq_new(iseq));
        }

        asan_poison_object_if(ptr, v);
    }
    return 0;
}

static VALUE
rjit_for_each_iseq(rb_execution_context_t *ec, VALUE self, VALUE block)
{
    rb_objspace_each_objects(for_each_iseq_i, (void *)block);
    return Qnil;
}

// bindgen references
extern ID rb_get_symbol_id(VALUE name);
extern VALUE rb_fix_aref(VALUE fix, VALUE idx);
extern VALUE rb_str_getbyte(VALUE str, VALUE index);
extern VALUE rb_vm_concat_array(VALUE ary1, VALUE ary2st);
extern VALUE rb_vm_get_ev_const(rb_execution_context_t *ec, VALUE orig_klass, ID id, VALUE allow_nil);
extern VALUE rb_vm_getclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *cfp, ID id, ICVARC ic);
extern VALUE rb_vm_opt_newarray_min(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr);
extern VALUE rb_vm_opt_newarray_max(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr);
extern VALUE rb_vm_opt_newarray_hash(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr);
extern VALUE rb_vm_opt_newarray_pack(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr, VALUE fmt);
extern VALUE rb_vm_splat_array(VALUE flag, VALUE array);
extern bool rb_simple_iseq_p(const rb_iseq_t *iseq);
extern bool rb_vm_defined(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t op_type, VALUE obj, VALUE v);
extern bool rb_vm_ic_hit_p(IC ic, const VALUE *reg_ep);
extern rb_event_flag_t rb_rjit_global_events;
extern void rb_vm_setinstancevariable(const rb_iseq_t *iseq, VALUE obj, ID id, VALUE val, IVC ic);
extern VALUE rb_vm_throw(const rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t throw_state, VALUE throwobj);
extern VALUE rb_reg_new_ary(VALUE ary, int opt);
extern void rb_vm_setclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *cfp, ID id, VALUE val, ICVARC ic);
extern VALUE rb_str_bytesize(VALUE str);
extern const rb_callable_method_entry_t *rb_callable_method_entry_or_negative(VALUE klass, ID mid);
extern VALUE rb_vm_yield_with_cfunc(rb_execution_context_t *ec, const struct rb_captured_block *captured, int argc, const VALUE *argv);
extern VALUE rb_vm_set_ivar_id(VALUE obj, ID id, VALUE val);
extern VALUE rb_ary_unshift_m(int argc, VALUE *argv, VALUE ary);
extern void* rb_rjit_entry_stub_hit(VALUE branch_stub);
extern void* rb_rjit_branch_stub_hit(VALUE branch_stub, int sp_offset, int target0_p);
extern uint64_t rb_vm_insns_count;

#include "rjit_c.rbinc"

#endif // USE_RJIT
