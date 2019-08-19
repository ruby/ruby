/**********************************************************************

  addr2line.h -

  $Author$

  Copyright (C) 2010 Shinichiro Hamaji

**********************************************************************/

#ifndef RUBY_ADDR2LINE_H
#define RUBY_ADDR2LINE_H

#if (defined(USE_ELF) || defined(HAVE_MACH_O_LOADER_H))

void
rb_dump_backtrace_with_lines(int num_traces, void **traces);

#endif /* USE_ELF */

#endif /* RUBY_ADDR2LINE_H */
