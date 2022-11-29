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

// An offsetof implementation that works for unnamed struct and union.
// Multiplying 8 for compatibility with libclang's offsetof.
#define OFFSETOF(ptr, member) RB_SIZE2NUM(((char *)&ptr.member - (char*)&ptr) * 8)

#define SIZEOF(type) RB_SIZE2NUM(sizeof(type))
#define SIGNED_TYPE_P(type) RBOOL((type)(-1) < (type)(1))

#include "mjit_c.rbinc"

#endif // USE_MJIT
