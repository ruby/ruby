/**********************************************************************

  ruby/mvm.h -

  $Author$
  created at: Sun 10 12:06:15 Jun JST 2007

  Copyright (C) 2007-2008 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_H
#define RUBY_H 1

#include <ruby/ruby.h>
#if RUBY_VM
#include <ruby/mvm.h>
#endif

extern void ruby_set_debug_option(const char *);
#endif /* RUBY_H */
