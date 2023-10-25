#ifndef RUBY_ADDR2LINE_H
#define RUBY_ADDR2LINE_H
/**********************************************************************

  addr2line.h -

  $Author$

  Copyright (C) 2010 Shinichiro Hamaji

**********************************************************************/

#if (defined(USE_ELF) || defined(HAVE_MACH_O_LOADER_H))

#include <stdio.h>

void
rb_dump_backtrace_with_lines(int num_traces, void **traces, FILE *errout);

#endif /* USE_ELF */

#endif /* RUBY_ADDR2LINE_H */
