/************************************************

  util.h -

  $Author$
  $Date$
  created at: Thu Mar  9 11:55:53 JST 1995

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/
#ifndef UTIL_H
#define UTIL_H

#define scan_oct ruby_scan_oct
unsigned long scan_oct();
#define scan_hex ruby_scan_hex
unsigned long scan_hex();

#if defined(MSDOS) || defined(__CYGWIN32__) || defined(NT)
#define add_suffix ruby_add_suffix
void add_suffix();
#endif

char *ruby_mktemp();

#endif /* UTIL_H */
