/**********************************************************************

  rjit_c.c - C helpers for RJIT

  Copyright (C) 2017 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "rjit.h" // defines USE_RJIT

#if USE_RJIT

#include "rjit_c.h"
#include "internal.h"
#include "internal/compile.h"
#include "internal/fixnum.h"
#include "internal/hash.h"
#include "internal/sanitizers.h"
#include "internal/gc.h"
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
        uint8_t *const cfunc_sample_addr = (void *)&rjit_reserve_addr_space;
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
        rb_bug("Couldn't make JIT page (%p, %lu bytes) executable, errno: %s\n",
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

// An offsetof implementation that works for unnamed struct and union.
// Multiplying 8 for compatibility with libclang's offsetof.
#define OFFSETOF(ptr, member) RB_SIZE2NUM(((char *)&ptr.member - (char*)&ptr) * 8)

#define SIZEOF(type) RB_SIZE2NUM(sizeof(type))
#define SIGNED_TYPE_P(type) RBOOL((type)(-1) < (type)(1))

#if RJIT_STATS
// Insn side exit counters
static size_t rjit_insn_exits[VM_INSTRUCTION_SIZE] = { 0 };
#endif // YJIT_STATS

// macOS: brew install capstone
// Ubuntu/Debian: apt-get install libcapstone-dev
// Fedora: dnf -y install capstone-devel
#ifdef HAVE_LIBCAPSTONE
#include <capstone/capstone.h>
#endif

// Return an array of [address, mnemonic, op_str]
static VALUE
dump_disasm(rb_execution_context_t *ec, VALUE self, VALUE from, VALUE to)
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
    size_t count = cs_disasm(handle, (const uint8_t *)from_addr, to_addr - from_addr, from_addr, 0, &insns);
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
        void *ptr = asan_poisoned_object_p(v);
        asan_unpoison_object(v, false);

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

extern bool rb_simple_iseq_p(const rb_iseq_t *iseq);
extern ID rb_get_symbol_id(VALUE name);

#include "rjit_c.rbinc"

#endif // USE_RJIT
