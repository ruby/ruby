/************************************************

  sig.h -

  $Author$
  $Date$
  created at: Wed Aug 16 01:15:38 JST 1995

************************************************/
#ifndef SIG_H
#define SIG_H

#ifdef SAFE_SIGHANDLE
extern int trap_immediate;
# define TRAP_BEG (trap_immediate=1)
# define TRAP_END (trap_immediate=0)
#else
# define TRAP_BEG
# define TRAP_END
#endif

typedef RETSIGTYPE(*SIGHANDLE)();
SIGHANDLE sig_beg();
void sig_end();

extern int trap_pending;

#endif
