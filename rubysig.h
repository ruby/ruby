/************************************************

  rubysig.h -

  $Author$
  $Date$
  created at: Wed Aug 16 01:15:38 JST 1995

************************************************/
#ifndef SIG_H
#define SIG_H

extern int rb_trap_immediate;
#define TRAP_BEG (rb_trap_immediate=1)
#define TRAP_END (rb_trap_immediate=0)

extern int rb_prohibit_interrupt;
#define DEFER_INTS {rb_prohibit_interrupt++;}
#define ALLOW_INTS {rb_prohibit_interrupt--; CHECK_INTS;}
#define ENABLE_INTS {rb_prohibit_interrupt--;}

extern int rb_trap_pending;
void rb_trap_restore_mask _((void));

#ifdef THREAD
extern int rb_thread_critical;
void rb_thread_schedule _((void));
#if defined(HAVE_SETITIMER) && !defined(__BOW__)
extern int rb_thread_pending;
# define CHECK_INTS if (!rb_prohibit_interrupt) {\
    if (rb_trap_pending) rb_trap_exec();\
    if (rb_thread_pending && !rb_thread_critical) rb_thread_schedule();\
}
# else
/* pseudo preemptive thread switching */
extern int rb_thread_tick;
#define THREAD_TICK 500
# define CHECK_INTS if (!rb_prohibit_interrupt) {\
    if (rb_trap_pending) rb_trap_exec();\
    if (!rb_thread_critical) {\
	if (rb_thread_tick-- <= 0) {\
	    rb_thread_tick = THREAD_TICK;\
	    rb_thread_schedule();\
	}\
    }\
}
# endif
#else
# define CHECK_INTS if (!rb_prohibit_interrupt) {\
    if (rb_trap_pending) rb_trap_exec();\
}
#endif

#endif
