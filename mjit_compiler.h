// This file is parsed by tool/mjit/generate.rb for MJIT's C/Ruby interop.
#ifndef MJIT_COMPILER_H
#define MJIT_COMPILER_H

#include "ruby/internal/config.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "mjit.h"
#include "mjit_unit.h"

// Macros to check if a position is already compiled using compile_status.stack_size_for_pos
#define NOT_COMPILED_STACK_SIZE -1
#define ALREADY_COMPILED_P(status, pos) (status->stack_size_for_pos[pos] != NOT_COMPILED_STACK_SIZE)

// Storage to keep data which is consistent in each conditional branch.
// This is created and used for one `compile_insns` call and its values
// should be copied for extra `compile_insns` call.
struct compile_branch {
    unsigned int stack_size; // this simulates sp (stack pointer) of YARV
    bool finish_p; // if true, compilation in this branch should stop and let another branch to be compiled
};

// For propagating information needed for lazily pushing a frame.
struct inlined_call_context {
    int orig_argc; // ci->orig_argc
    VALUE me; // vm_cc_cme(cc)
    int param_size; // def_iseq_ptr(vm_cc_cme(cc)->def)->body->param.size
    int local_size; // def_iseq_ptr(vm_cc_cme(cc)->def)->body->local_table_size
};

// Storage to keep compiler's status.  This should have information
// which is global during one `mjit_compile` call.  Ones conditional
// in each branch should be stored in `compile_branch`.
struct compile_status {
    bool success; // has true if compilation has had no issue
    int *stack_size_for_pos; // stack_size_for_pos[pos] has stack size for the position (otherwise -1)
    // If true, JIT-ed code will use local variables to store pushed values instead of
    // using VM's stack and moving stack pointer.
    bool local_stack_p;
    // Safely-accessible ivar cache entries copied from main thread.
    union iseq_inline_storage_entry *is_entries;
    // Index of call cache entries captured to compiled_iseq to be marked on GC
    int cc_entries_index;
    // A pointer to root (i.e. not inlined) iseq being compiled.
    const struct rb_iseq_constant_body *compiled_iseq;
    int compiled_id; // Just a copy of compiled_iseq->jit_unit->id
    // Mutated optimization levels
    struct rb_mjit_compile_info *compile_info;
    bool merge_ivar_guards_p; // If true, merge guards of ivar accesses
    rb_serial_t ivar_serial; // ic_serial of IVC in is_entries (used only when merge_ivar_guards_p)
    size_t max_ivar_index; // Max IVC index in is_entries (used only when merge_ivar_guards_p)
    // If `inlined_iseqs[pos]` is not NULL, `mjit_compile_body` tries to inline ISeq there.
    const struct rb_iseq_constant_body **inlined_iseqs;
    struct inlined_call_context inline_context;
};

#endif /* MJIT_COMPILER_H */
