//
// These are definitions uJIT uses to interface with the CRuby codebase,
// but which are only used internally by uJIT.
//

#ifndef UJIT_IFACE_H
#define UJIT_IFACE_H 1

#include "stddef.h"
#include "stdint.h"
#include "stdbool.h"
#include "internal.h"
#include "ruby/internal/attr/nodiscard.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "ujit_core.h"

#ifndef rb_callcache
struct rb_callcache;
#define rb_callcache rb_callcache
#endif

RUBY_EXTERN struct rb_ujit_options rb_ujit_opts;
RUBY_EXTERN int64_t rb_ujit_exec_insns_count;
RUBY_EXTERN int64_t rb_compiled_iseq_count;

void cb_write_pre_call_bytes(codeblock_t* cb);
void cb_write_post_call_bytes(codeblock_t* cb);

void map_addr2insn(void *code_ptr, int insn);
int opcode_at_pc(const rb_iseq_t *iseq, const VALUE *pc);

void check_cfunc_dispatch(VALUE receiver, struct rb_call_data *cd, void *callee, rb_callable_method_entry_t *compile_time_cme);
bool cfunc_needs_frame(const rb_method_cfunc_t *cfunc);

void assume_method_lookup_stable(const struct rb_callcache *cc, const rb_callable_method_entry_t *cme, block_t* block);
RBIMPL_ATTR_NODISCARD() bool assume_single_ractor_mode(block_t *block);
RBIMPL_ATTR_NODISCARD() bool assume_stable_global_constant_state(block_t *block);

// this function *must* return passed exit_pc
const VALUE *rb_ujit_count_side_exit_op(const VALUE *exit_pc);

void ujit_unlink_method_lookup_dependency(block_t *block);
void ujit_block_assumptions_free(block_t *block);

#endif // #ifndef UJIT_IFACE_H
