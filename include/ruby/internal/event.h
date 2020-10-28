#ifndef RBIMPL_EVENT_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_EVENT_H
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
 * @brief      Debugging and tracing APIs.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* traditional set_trace_func events */
#define RUBY_EVENT_NONE      0x0000
#define RUBY_EVENT_LINE      0x0001
#define RUBY_EVENT_CLASS     0x0002
#define RUBY_EVENT_END       0x0004
#define RUBY_EVENT_CALL      0x0008
#define RUBY_EVENT_RETURN    0x0010
#define RUBY_EVENT_C_CALL    0x0020
#define RUBY_EVENT_C_RETURN  0x0040
#define RUBY_EVENT_RAISE     0x0080
#define RUBY_EVENT_ALL       0x00ff

/* for TracePoint extended events */
#define RUBY_EVENT_B_CALL            0x0100
#define RUBY_EVENT_B_RETURN          0x0200
#define RUBY_EVENT_THREAD_BEGIN      0x0400
#define RUBY_EVENT_THREAD_END        0x0800
#define RUBY_EVENT_FIBER_SWITCH      0x1000
#define RUBY_EVENT_SCRIPT_COMPILED   0x2000
#define RUBY_EVENT_TRACEPOINT_ALL    0xffff

/* special events */
#define RUBY_EVENT_RESERVED_FOR_INTERNAL_USE 0x030000

/* internal events */
#define RUBY_INTERNAL_EVENT_SWITCH          0x040000
#define RUBY_EVENT_SWITCH                   0x040000 /* obsolete name. this macro is for compatibility */
                                         /* 0x080000 */
#define RUBY_INTERNAL_EVENT_NEWOBJ          0x100000
#define RUBY_INTERNAL_EVENT_FREEOBJ         0x200000
#define RUBY_INTERNAL_EVENT_GC_START        0x400000
#define RUBY_INTERNAL_EVENT_GC_END_MARK     0x800000
#define RUBY_INTERNAL_EVENT_GC_END_SWEEP   0x1000000
#define RUBY_INTERNAL_EVENT_GC_ENTER       0x2000000
#define RUBY_INTERNAL_EVENT_GC_EXIT        0x4000000
#define RUBY_INTERNAL_EVENT_OBJSPACE_MASK  0x7f00000
#define RUBY_INTERNAL_EVENT_MASK          0xffff0000

typedef uint32_t rb_event_flag_t;
typedef void (*rb_event_hook_func_t)(rb_event_flag_t evflag, VALUE data, VALUE self, ID mid, VALUE klass);

#define RB_EVENT_HOOKS_HAVE_CALLBACK_DATA 1
void rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);
int rb_remove_event_hook(rb_event_hook_func_t func);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_EVENT_H */
