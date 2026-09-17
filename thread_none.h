#ifndef RUBY_THREAD_NONE_H
#define RUBY_THREAD_NONE_H

#define RB_NATIVETHREAD_LOCK_INIT (void)(0)
#define RB_NATIVETHREAD_COND_INIT (void)(0)

// no-thread impl doesn't use TLS but define this to avoid using tls key
// based implementation in vm.c
#define RB_THREAD_LOCAL_SPECIFIER

// This model brings its own scheduler stubs (thread_none.c) instead of the
// common one; thread.c keys off this.
#define RB_THREAD_SCHED_NONE 1

// The scheduler's types are shared with the threaded platforms: the code that
// reads them (vm_sync.c, ractor.c, thread.c) is compiled for every thread
// model, so it needs the real fields even here, where nothing ever runs
// concurrently and they all stay zero.  thread_none.c only ever passes the
// structs around, never looks inside them.
#include "thread_sched.h"

RUBY_EXTERN struct rb_execution_context_struct *ruby_current_ec;
NOINLINE(struct rb_execution_context_struct *rb_current_ec_noinline(void)); // for assertions

#endif /* RUBY_THREAD_NONE_H */
