/**********************************************************************

  rubysig.h -

  $Author$
  created at: Wed Aug 16 01:15:38 JST 1995

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBYSIG_H
#define RUBYSIG_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include <errno.h>

#ifdef _WIN32
typedef LONG rb_atomic_t;

# define ATOMIC_TEST(var) InterlockedExchange(&(var), 0)
# define ATOMIC_SET(var, val) InterlockedExchange(&(var), (val))
# define ATOMIC_INC(var) InterlockedIncrement(&(var))
# define ATOMIC_DEC(var) InterlockedDecrement(&(var))

/* Windows doesn't allow interrupt while system calls */
# define TRAP_BEG do {\
    rb_atomic_t trap_immediate = ATOMIC_SET(rb_trap_immediate, 1)

# define TRAP_END\
    ATOMIC_SET(rb_trap_immediate, trap_immediate);\
} while (0)

# define RUBY_CRITICAL(statements) do {\
    rb_atomic_t trap_immediate = ATOMIC_SET(rb_trap_immediate, 0);\
    statements;\
    ATOMIC_SET(rb_trap_immediate, trap_immediate);\
} while (0)
#else
typedef int rb_atomic_t;

# define ATOMIC_TEST(var) ((var) ? ((var) = 0, 1) : 0)
# define ATOMIC_SET(var, val) ((var) = (val))
# define ATOMIC_INC(var) (++(var))
# define ATOMIC_DEC(var) (--(var))

# define TRAP_BEG do {\
    int trap_immediate = rb_trap_immediate;\
    rb_trap_immediate = 1

# define TRAP_END \
    rb_trap_immediate = trap_immediate;\
} while (0)

# define RUBY_CRITICAL(statements) do {\
    int trap_immediate = rb_trap_immediate;\
    rb_trap_immediate = 0;\
    statements;\
    rb_trap_immediate = trap_immediate;\
} while (0)
#endif
RUBY_EXTERN rb_atomic_t rb_trap_immediate;

RUBY_EXTERN int rb_prohibit_interrupt;
#define DEFER_INTS (rb_prohibit_interrupt++)
#define ALLOW_INTS do {\
    rb_prohibit_interrupt--;\
} while (0)
#define ENABLE_INTS (rb_prohibit_interrupt--)

VALUE rb_with_disable_interrupt(VALUE(*)(ANYARGS),VALUE);

RUBY_EXTERN rb_atomic_t rb_trap_pending;
void rb_trap_restore_mask(void);

RUBY_EXTERN int rb_thread_critical;
void rb_thread_schedule(void);

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBYSIG_H */
