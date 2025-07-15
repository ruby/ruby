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
    CALL(default_shapes);
    CALL(Thread_Mutex);
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
    CALL(IO_Buffer)
    CALL(Dir);
    CALL(Time);
    CALL(Random);
    CALL(load);
    CALL(Proc);
    CALL(Binding);
    CALL(Math);
    CALL(GC);
    CALL(WeakMap);
    CALL(Enumerator);
    CALL(Ractor);
    CALL(VM);
    CALL(ISeq);
    CALL(Thread);
    CALL(signal);
    CALL(Cont);
    CALL(Fiber_Scheduler);
    CALL(process);
    CALL(Rational);
    CALL(Complex);
    CALL(MemoryView);
    CALL(pathname);
    CALL(version);
    CALL(vm_trace);
    CALL(vm_stack_canary);
    CALL(ast);
    CALL(shape);
    CALL(Prism);
    CALL(unicode_version);
    CALL(Set);
    CALL(Namespace);

    // enable builtin loading
    CALL(builtin);
}

void
rb_call_builtin_inits(void)
{
#define BUILTIN(n) CALL(builtin_##n)
    BUILTIN(kernel);
    BUILTIN(yjit);
    // BUILTIN(yjit_hook) is called after rb_yjit_init()
    BUILTIN(gc);
    BUILTIN(ractor);
    BUILTIN(numeric);
    BUILTIN(io);
    BUILTIN(dir);
    BUILTIN(ast);
    BUILTIN(trace_point);
    BUILTIN(pack);
    BUILTIN(pathname);
    BUILTIN(warning);
    BUILTIN(array);
    BUILTIN(hash);
    BUILTIN(symbol);
    BUILTIN(timev);
    BUILTIN(thread_sync);
    BUILTIN(nilclass);
    BUILTIN(marshal);
    BUILTIN(zjit);
    Init_builtin_prelude();
}
#undef CALL
