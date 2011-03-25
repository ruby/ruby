/**********************************************************************

  addr2line.h -

  $Author$

  Copyright (C) 2010 Shinichiro Hamaji

**********************************************************************/

#ifndef RUBY_ADDR2LINE_H
#define RUBY_ADDR2LINE_H

#ifdef __ELF__

void
rb_dump_backtrace_with_lines(int num_traces, void **traces, char **syms);

#endif /* __ELF__ */

#endif /* RUBY_ADDR2LINE_H */
