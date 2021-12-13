//
// These are definitions YJIT uses to interface with the CRuby codebase,
// but which are only used internally by YJIT.
//

#ifndef YJIT_IFACE_H
#define YJIT_IFACE_H 1

#include "ruby/internal/config.h"
#include "ruby_assert.h" // for RUBY_DEBUG
#include "yjit.h" // for YJIT_STATS
#include "vm_core.h"
#include "yjit_core.h"

#ifndef YJIT_DEFAULT_CALL_THRESHOLD
# define YJIT_DEFAULT_CALL_THRESHOLD 10
#endif

RUBY_EXTERN struct rb_yjit_options rb_yjit_opts;

static VALUE *yjit_iseq_pc_at_idx(const rb_iseq_t *iseq, uint32_t insn_idx);
static int yjit_opcode_at_pc(const rb_iseq_t *iseq, const VALUE *pc);
static void yjit_print_iseq(const rb_iseq_t *iseq);

#if YJIT_STATS
// this function *must* return passed exit_pc
static const VALUE *yjit_count_side_exit_op(const VALUE *exit_pc);
#endif

static void yjit_unlink_method_lookup_dependency(block_t *block);
static void yjit_block_assumptions_free(block_t *block);

static VALUE yjit_get_code_page(uint32_t cb_bytes_needed, uint32_t ocb_bytes_needed);
//code_page_t *rb_yjit_code_page_unwrap(VALUE cp_obj);
//void rb_yjit_get_cb(codeblock_t* cb, uint8_t* code_ptr);
//void rb_yjit_get_ocb(codeblock_t* cb, uint8_t* code_ptr);

#endif // #ifndef YJIT_IFACE_H
