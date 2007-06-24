/**********************************************************************

  debug.h - YARV Debug function interface

  $Author$
  $Date$
  created at: 04/08/25 02:33:49 JST

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

#ifndef _DEBUG_H_INCLUDED_
#define _DEBUG_H_INCLUDED_

#include "ruby/ruby.h"
#include "ruby/node.h"

#define dpv(h,v) ruby_debug_print_value(-1, 0, h, v)
#define dp(v)    ruby_debug_print_value(-1, 0, "", v)
#define dpi(i)   ruby_debug_print_id(-1, 0, "", i)
#define dpn(n)   ruby_debug_print_node(-1, 0, "", n)

#define bp()     ruby_debug_breakpoint()

VALUE ruby_debug_print_value(int level, int debug_level, char *header, VALUE v);
ID    ruby_debug_print_id(int level, int debug_level, char *header, ID id);
NODE *ruby_debug_print_node(int level, int debug_level, char *header, NODE *node);
void  ruby_debug_print_indent(int level, int debug_level, int indent_level);
void  ruby_debug_breakpoint(void);
void  ruby_debug_gc_check_func(void);

#endif /* _DEBUG_H_INCLUDED_ */
