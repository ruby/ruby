/**********************************************************************

  mjit_c.c - C helpers for MJIT

  Copyright (C) 2017 Takashi Kokubun <k0kubun@ruby-lang.org>.

**********************************************************************/

#include "ruby/internal/config.h" // defines USE_MJIT

#if USE_MJIT

#include "mjit.h"
#include "mjit_c.h"
#include "internal.h"
#include "internal/compile.h"
#include "internal/hash.h"
#include "yjit.h"
#include "vm_insnhelper.h"

#include "insns.inc"
#include "insns_info.inc"

#include "mjit_sp_inc.inc"

#if SIZEOF_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULONG(x)
#define PTR2NUM(x) ULONG2NUM(x)
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULL(x)
#define PTR2NUM(x) ULL2NUM(x)
#endif

// An offsetof implementation that works for unnamed struct and union.
// Multiplying 8 for compatibility with libclang's offsetof.
#define OFFSETOF(ptr, member) RB_SIZE2NUM(((char *)&ptr.member - (char*)&ptr) * 8)

#define SIZEOF(type) RB_SIZE2NUM(sizeof(type))
#define SIGNED_TYPE_P(type) RBOOL((type)(-1) < (type)(1))

#if MJIT_STATS
// Insn side exit counters
static size_t mjit_insn_exits[VM_INSTRUCTION_SIZE] = { 0 };
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

// Same as `RubyVM::MJIT.enabled?`, but this is used before it's defined.
static VALUE
mjit_enabled_p(rb_execution_context_t *ec, VALUE self)
{
    return RBOOL(mjit_enabled);
}

#include "mjit_c.rbinc"

#endif // USE_MJIT
