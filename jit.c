// Glue code shared between YJIT and ZJIT for use from Rust.
// For FFI safety and bindgen compatibility reasons, certain types of C
// functions require wrapping before they can be called from Rust. Those show
// up here.
//
// Code specific to YJIT and ZJIT should go to yjit.c and zjit.c respectively.

#include "internal.h"
#include "vm_core.h"
#include "vm_callinfo.h"
#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"
#include "iseq.h"
#include "internal/gc.h"

unsigned int
rb_iseq_encoded_size(const rb_iseq_t *iseq)
{
    return iseq->body->iseq_size;
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
    return (void*)(uintptr_t)mct->func; // this field is defined as type VALUE (*func)(ANYARGS)
}

const rb_iseq_t *
rb_get_def_iseq_ptr(rb_method_definition_t *def)
{
    return def_iseq_ptr(def);
}

const rb_iseq_t *
rb_get_iseq_body_local_iseq(const rb_iseq_t *iseq)
{
    return iseq->body->local_iseq;
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

enum rb_iseq_type
rb_get_iseq_body_type(const rb_iseq_t *iseq)
{
    return iseq->body->type;
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

bool
rb_get_iseq_flags_forwardable(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.forwardable;
}

// This is defined only as a named struct inside rb_iseq_constant_body.
// By giving it a separate typedef, we make it nameable by rust-bindgen.
// Bindgen's temp/anon name isn't guaranteed stable.
typedef struct rb_iseq_param_keyword rb_iseq_param_keyword_struct;

const rb_iseq_param_keyword_struct *
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

VALUE
rb_yarv_class_of(VALUE obj)
{
    return rb_class_of(obj);
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

// For debug builds
void
rb_assert_iseq_handle(VALUE handle)
{
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
    RUBY_ASSERT_ALWAYS(!rb_objspace_garbage_object_p(handle));
    RUBY_ASSERT_ALWAYS(IMEMO_TYPE_P(handle, imemo_ment));
}

// YJIT and ZJIT need this function to never allocate and never raise
VALUE
rb_yarv_ary_entry_internal(VALUE ary, long offset)
{
    return rb_ary_entry_internal(ary, offset);
}
