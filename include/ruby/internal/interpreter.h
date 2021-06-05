#ifndef RBIMPL_INTERPRETER_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERPRETER_H
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
 * @brief      Interpreter embedding APIs.
 */
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * @defgroup embed CRuby Embedding APIs
 * CRuby interpreter APIs. These are APIs to embed MRI interpreter into your
 * program.
 * These functions are not a part of Ruby extension library API.
 * Extension libraries of Ruby should not depend on these functions.
 * @{
 */

/** @defgroup ruby1 ruby(1) implementation
 * A part of the implementation of ruby(1) command.
 * Other programs that embed Ruby interpreter do not always need to use these
 * functions.
 * @{
 */

void ruby_sysinit(int *argc, char ***argv);
void ruby_init(void);
void* ruby_options(int argc, char** argv);
int ruby_executable_node(void *n, int *status);
int ruby_run_node(void *n);

/* version.c */
void ruby_show_version(void);
#ifndef ruby_show_copyright
void ruby_show_copyright(void);
#endif

/*! A convenience macro to call ruby_init_stack(). Must be placed just after
 *  variable declarations */
#define RUBY_INIT_STACK \
    VALUE variable_in_this_stack_frame; \
    ruby_init_stack(&variable_in_this_stack_frame);
/*! @} */

void ruby_init_stack(volatile VALUE*);

int ruby_setup(void);
int ruby_cleanup(volatile int);

void ruby_finalize(void);

RBIMPL_ATTR_NORETURN()
void ruby_stop(int);

int ruby_stack_check(void);
size_t ruby_stack_length(VALUE**);

int ruby_exec_node(void *n);

void ruby_script(const char* name);
void ruby_set_script_name(VALUE name);

void ruby_prog_init(void);
void ruby_set_argv(int, char**);
void *ruby_process_options(int, char**);
void ruby_init_loadpath(void);
void ruby_incpush(const char*);
void ruby_sig_finalize(void);

/*! @} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERPRETER_H */
