/**********************************************************************

  inits.c -

  $Author$
  created at: Tue Dec 28 16:01:58 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "internal.h"
#include "builtin.h"
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
    CALL(safe);
    CALL(jump);
    CALL(Numeric);
    CALL(Bignum);
    CALL(syserr);
    CALL(Array);
    CALL(Hash);
    CALL(Struct);
    CALL(Regexp);
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
    CALL(Enumerator);
    CALL(VM);
    CALL(ISeq);
    CALL(Thread);
    CALL(process);
    CALL(Cont);
    CALL(Rational);
    CALL(Complex);
    CALL(version);
    CALL(vm_stack_canary);
    CALL(gc_stress);

    // enable builtin loading
    CALL(builtin);

    CALL(GC);
    CALL(IO_nonblock);
    CALL(ast);
    CALL(vm_trace);
    CALL(pack);
    CALL(warning);
    load_prelude();
}
#undef CALL
