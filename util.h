/************************************************

  util.h -

  $Author$
  $Date$
  created at: Thu Mar  9 11:55:53 JST 1995

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/
#ifndef UTIL_H
#define UTIL_H

#ifndef _
# ifdef __STDC__
#  define _(args) args
# else
#  define _(args) ()
# endif
#endif

#define scan_oct ruby_scan_oct
unsigned long scan_oct _((char*, int, int*));
#define scan_hex ruby_scan_hex
unsigned long scan_hex _((char*, int, int*));

#if defined(MSDOS) || defined(__CYGWIN32__) || defined(NT)
#define add_suffix ruby_add_suffix
void add_suffix();
#endif

char *ruby_mktemp _((void));

void ruby_qsort _((void*, int, int, int (*)()));
#define qsort(b,n,s,c) ruby_qsort(b,n,s,c)

#endif /* UTIL_H */
