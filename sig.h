/************************************************

  sig.h -

  $Author$
  $Date$
  created at: Wed Aug 16 01:15:38 JST 1995

************************************************/
#ifndef SIG_H
#define SIG_H

extern int trap_immediate;
#define TRAP_BEG (trap_immediate=1)
#define TRAP_END (trap_immediate=0)

extern int prohibit_interrupt;
#define DEFER_INTS {prohibit_interrupt++;}
#define ALLOW_INTS {prohibit_interrupt--; CHECK_INTS;}
#define ENABLE_INTS {prohibit_interrupt--;}

extern int trap_pending;
#ifdef THREAD
extern int thread_critical;
#if defined(HAVE_SETITIMER) && !defined(__BOW__)
extern int thread_pending;
void thread_schedule();
# define CHECK_INTS if (!prohibit_interrupt) {\
    if (trap_pending) rb_trap_exec();\
    if (thread_pending && !thread_critical) thread_schedule();\
}
# else
/* pseudo preemptive thread switching */
extern int thread_tick;
#define THREAD_TICK 500
void thread_schedule();
# define CHECK_INTS if (!prohibit_interrupt) {\
    if (trap_pending) rb_trap_exec();\
    if (!thread_critical) {\
	if (thread_tick-- <= 0) {\
	    thread_tick = THREAD_TICK;\
	    thread_schedule();\
	}\
    }\
}
# endif
#else
# define CHECK_INTS if (!prohibit_interrupt) {\
    if (trap_pending) rb_trap_exec();\
}
#endif

#endif
