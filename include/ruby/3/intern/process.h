/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Public APIs related to ::rb_mProcess.
 */
#ifndef  RUBY3_INTERN_PROCESS_H
#define  RUBY3_INTERN_PROCESS_H
#include "ruby/3/attr/noreturn.h"
#include "ruby/3/config.h"      /* rb_pid_t is defined here. */
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

/* process.c */
void rb_last_status_set(int status, rb_pid_t pid);
VALUE rb_last_status_get(void);
int rb_proc_exec(const char*);

RUBY3_ATTR_NORETURN()
VALUE rb_f_exec(int, const VALUE*);
rb_pid_t rb_waitpid(rb_pid_t pid, int *status, int flags);
void rb_syswait(rb_pid_t pid);
rb_pid_t rb_spawn(int, const VALUE*);
rb_pid_t rb_spawn_err(int, const VALUE*, char*, size_t);
VALUE rb_proc_times(VALUE);
VALUE rb_detach_process(rb_pid_t pid);

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_INTERN_PROCESS_H */
