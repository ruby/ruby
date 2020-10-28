#ifndef INTERNAL_MJIT_H                                  /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_MJIT_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for MJIT.
 */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "ruby/ruby.h"          /* for VALUE */

/* mjit.c */

#if USE_MJIT
extern bool mjit_enabled;
VALUE mjit_pause(bool wait_p);
VALUE mjit_resume(void);
void mjit_finish(bool close_handle_p);
#else
#define mjit_enabled 0
static inline VALUE mjit_pause(bool wait_p){ return Qnil; } // unreachable
static inline VALUE mjit_resume(void){ return Qnil; } // unreachable
static inline void mjit_finish(bool close_handle_p){}
#endif

#endif /* INTERNAL_MJIT_H */
