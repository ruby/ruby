/**********************************************************************

  inits.c -

  $Author$
  created at: Tue Dec 28 16:01:58 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "internal/inits.h"
#include "ruby.h"
#include "builtin.h"
static void Init_builtin_prelude(void);
#include "prelude.rbinc"

#define CALL(n) {void Init_##n(void); Init_##n();}

void
rb_call_inits(void)
{
#if USE_TRANSIENT_HEAP
    CALL(TransientHeap);
#endif
    CALL(vm_postponed_job);
    CALL(Method);
    CALL(RandomSeedCore);
    CALL(encodings);
    CALL(sym);
    CALL(var_tables);
    CALL(Object);
    CALL(top_self);
    CALL(Encoding);
    CALL(Comparable);
    CALL(Enumerable);
    CALL(String);
    CALL(Exception);
    CALL(eval);
    CALL(jump);
    CALL(Numeric);
    CALL(Bignum);
    CALL(syserr);
    CALL(Array);
    CALL(Hash);
    CALL(Struct);
    CALL(Regexp);
    CALL(pack);
    CALL(transcode);
    CALL(marshal);
    CALL(Range);
    CALL(IO);
    CALL(Dir);
    CALL(Time);
    CALL(Random);
    CALL(signal);
    CALL(load);
    CALL(Proc);
    CALL(Binding);
    CALL(Math);
    CALL(GC);
    CALL(Enumerator);
    CALL(VM);
    CALL(ISeq);
    CALL(Thread);
    CALL(process);
    CALL(Cont);
    CALL(Rational);
    CALL(Complex);
    CALL(version);
    CALL(vm_trace);
    CALL(vm_stack_canary);
    CALL(ast);
    CALL(gc_stress);

    // enable builtin loading
    CALL(builtin);

#define BUILTIN(n) CALL(builtin_##n)
    BUILTIN(gc);
    BUILTIN(io);
    BUILTIN(ast);
    BUILTIN(trace_point);
    BUILTIN(pack);
    BUILTIN(warning);
    Init_builtin_prelude();
}
#undef CALL
