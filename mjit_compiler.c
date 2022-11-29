/**********************************************************************

  mjit_compiler.c - MRI method JIT compiler

  Copyright (C) 2017 Takashi Kokubun <takashikkbn@gmail.com>.

**********************************************************************/

#include "ruby/internal/config.h" // defines USE_MJIT

#if USE_MJIT

#include "mjit_c.h"
#include "internal.h"
#include "internal/compile.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/variable.h"
#include "mjit.h"
#include "mjit_unit.h"
#include "yjit.h"
#include "vm_callinfo.h"
#include "vm_exec.h"
#include "vm_insnhelper.h"

#include "builtin.h"
#include "insns.inc"
#include "insns_info.inc"

// Returns true if call cache is still not obsoleted and vm_cc_cme(cc)->def->type is available.
static bool
has_valid_method_type(CALL_CACHE cc)
{
    return vm_cc_cme(cc) != NULL;
}

// Returns true if iseq can use fastpath for setup, otherwise NULL. This becomes true in the same condition
// as CC_SET_FASTPATH (in vm_callee_setup_arg) is called from vm_call_iseq_setup.
static bool
fastpath_applied_iseq_p(const CALL_INFO ci, const CALL_CACHE cc, const rb_iseq_t *iseq)
{
    extern bool rb_simple_iseq_p(const rb_iseq_t *iseq);
    return iseq != NULL
        && !(vm_ci_flag(ci) & VM_CALL_KW_SPLAT) && rb_simple_iseq_p(iseq) // Top of vm_callee_setup_arg. In this case, opt_pc is 0.
        && vm_ci_argc(ci) == (unsigned int)ISEQ_BODY(iseq)->param.lead_num // exclude argument_arity_error (assumption: `calling->argc == ci->orig_argc` in send insns)
        && vm_call_iseq_optimizable_p(ci, cc); // CC_SET_FASTPATH condition
}

#include "mjit_compile_attr.inc"

#if SIZEOF_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULONG(x)
#define PTR2NUM(x) ULONG2NUM(x)
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
#define NUM2PTR(x) NUM2ULL(x)
#define PTR2NUM(x) ULL2NUM(x)
#endif

// Compile ISeq to C code in `f`. It returns true if it succeeds to compile.
bool
mjit_compile(FILE *f, const rb_iseq_t *iseq, const char *funcname, int id)
{
    bool original_call_p = mjit_call_p;
    mjit_call_p = false; // Avoid impacting JIT metrics by itself

    extern VALUE rb_cMJITCompiler;
    extern VALUE rb_cMJITIseqPtr;
    VALUE iseq_ptr = rb_funcall(rb_cMJITIseqPtr, rb_intern("new"), 1, ULONG2NUM((size_t)iseq));
    VALUE src = rb_funcall(rb_cMJITCompiler, rb_intern("compile"), 3,
                           iseq_ptr, rb_str_new_cstr(funcname), INT2NUM(id));
    if (!NIL_P(src)) {
        fprintf(f, "%s", RSTRING_PTR(src));
    }

    mjit_call_p = original_call_p;
    return !NIL_P(src);
}

//
// Primitive.methods
//

static VALUE
builtin_compile(rb_execution_context_t *ec, VALUE self, VALUE buf, VALUE bf_addr, VALUE index, VALUE stack_size, VALUE builtin_inline_p)
{
    // Call "mjit_compile_invokebuiltin_for_#{func}" in mk_builtin_loader.rb
    RB_BUILTIN bf = (RB_BUILTIN)NUM2PTR(bf_addr);
    bf->compiler(buf, NIL_P(index) ? -1 : NUM2LONG(index), NUM2UINT(stack_size), RTEST(builtin_inline_p));
    return Qnil;
}

// Returns true if MJIT thinks this cc's opt_* insn may fallback to opt_send_without_block.
static VALUE
has_cache_for_send(rb_execution_context_t *ec, VALUE self, VALUE cc_addr, VALUE insn)
{
    extern bool rb_vm_opt_cfunc_p(CALL_CACHE cc, int insn);
    CALL_CACHE cc = (CALL_CACHE)NUM2PTR(cc_addr);
    bool has_cache = has_valid_method_type(cc) &&
        !(vm_cc_cme(cc)->def->type == VM_METHOD_TYPE_CFUNC && rb_vm_opt_cfunc_p(cc, NUM2INT(insn)));
    return RBOOL(has_cache);
}

// An offsetof implementation that works for unnamed struct and union.
// Multiplying 8 for compatibility with libclang's offsetof.
#define OFFSETOF(ptr, member) RB_SIZE2NUM(((char *)&ptr.member - (char*)&ptr) * 8)

#define SIZEOF(type) RB_SIZE2NUM(sizeof(type))
#define SIGNED_TYPE_P(type) RBOOL((type)(-1) < (type)(1))

#include "mjit_c.rbinc"

#endif // USE_MJIT
