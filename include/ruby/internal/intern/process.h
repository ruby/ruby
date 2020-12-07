#ifndef RBIMPL_INTERN_PROCESS_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_PROCESS_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
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
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/config.h"      /* rb_pid_t is defined here. */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* process.c */
RUBY_EXTERN void (* rb_socket_before_fork_func)();

void rb_last_status_set(rb_pid_t pid, int status, int error);
VALUE rb_last_status_get(void);
int rb_proc_exec(const char*);

RBIMPL_ATTR_NORETURN()
VALUE rb_f_exec(int, const VALUE*);
rb_pid_t rb_waitpid(rb_pid_t pid, int *status, int flags);
void rb_syswait(rb_pid_t pid);
rb_pid_t rb_spawn(int, const VALUE*);
rb_pid_t rb_spawn_err(int, const VALUE*, char*, size_t);
VALUE rb_proc_times(VALUE);
VALUE rb_detach_process(rb_pid_t pid);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_PROCESS_H */
