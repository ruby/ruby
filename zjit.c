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

void
rb_zjit_compile_iseq(const rb_iseq_t *iseq, rb_execution_context_t *ec, bool jit_exception)
{
    RB_VM_LOCK_ENTER();
    rb_vm_barrier();

    // Compile a block version starting at the current instruction
    uint8_t *rb_zjit_iseq_gen_entry_point(const rb_iseq_t *iseq, rb_execution_context_t *ec); // defined in Rust
    uintptr_t code_ptr = (uintptr_t)rb_zjit_iseq_gen_entry_point(iseq, ec);

    // TODO: support jit_exception
    iseq->body->jit_entry = (rb_jit_func_t)code_ptr;

    RB_VM_LOCK_LEAVE();
}
