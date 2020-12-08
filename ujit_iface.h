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
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "ujit_core.h"

#ifndef rb_callcache
struct rb_callcache;
#define rb_callcache rb_callcache
#endif

void cb_write_pre_call_bytes(codeblock_t* cb);
void cb_write_post_call_bytes(codeblock_t* cb);
void map_addr2insn(void *code_ptr, int insn);
int opcode_at_pc(const rb_iseq_t *iseq, const VALUE *pc);
void assume_method_lookup_stable(const struct rb_callcache *cc, const rb_callable_method_entry_t *cme, ctx_t *ctx);

#endif // #ifndef UJIT_IFACE_H
