/**********************************************************************

  debug.h - YARV Debug function interface

  $Author$
  $Date$
  created at: 04/08/25 02:33:49 JST

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#ifndef _DEBUG_H_INCLUDED_
#define _DEBUG_H_INCLUDED_

#include <ruby.h>

#define dpv(h,v) ruby_debug_value(-1, 0, h, v)
#define dp(v)    ruby_debug_value(-1, 0, "", v)
#define dpi(i)   ruby_debug_id   (-1, 0, "", i)
#define bp()     ruby_debug_breakpoint()

VALUE ruby_debug_value(int level, int debug_level, char *header, VALUE v);
ID    ruby_debug_id(int level, int debug_level, char *header, ID id);
void  ruby_debug_indent(int level, int debug_level, int indent_level);
void  ruby_debug_breakpoint(void);
void  ruby_debug_gc_check_func();

#if GCDEBUG == 1

#define GC_CHECK() \
  gc_check_func()

#elif GCDEBUG == 2

#define GC_CHECK()                                    \
  (printf("** %s:%d gc start\n", __FILE__, __LINE__), \
   ruby_debug_gc_check_func(),                        \
   printf("** end\n"))

#else

#define GC_CHECK()

#endif

#endif /* _DEBUG_H_INCLUDED_ */
