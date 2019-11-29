#ifndef INTERNAL_MJIT_H /* -*- C -*- */
#define INTERNAL_MJIT_H
/**
 * @file
 * @brief      Internal header for MJIT.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

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
