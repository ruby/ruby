/************************************************

  rubysig.h -

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
void trap_restore_mask _((void));

#ifdef THREAD
extern int thred_critical;
void thred_schedule _((void));
#if defined(HAVE_SETITIMER) && !defined(__BOW__)
extern int thred_pending;
# define CHECK_INTS if (!prohibit_interrupt) {\
    if (trap_pending) rb_trap_exec();\
    if (thred_pending && !thred_critical) thred_schedule();\
}
# else
/* pseudo preemptive thread switching */
extern int thred_tick;
#define THREAD_TICK 500
# define CHECK_INTS if (!prohibit_interrupt) {\
    if (trap_pending) rb_trap_exec();\
    if (!thred_critical) {\
	if (thred_tick-- <= 0) {\
	    thred_tick = THREAD_TICK;\
	    thred_schedule();\
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
