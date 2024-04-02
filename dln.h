#ifndef DLN_H
#define DLN_H
/**********************************************************************

  dln.h -

  $Author$
  created at: Wed Jan 19 16:53:09 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/defines.h"       /* for RUBY_SYMBOL_EXPORT_BEGIN */

RUBY_SYMBOL_EXPORT_BEGIN

#ifndef DLN_FIND_EXTRA_ARG
#define DLN_FIND_EXTRA_ARG
#endif
#ifndef DLN_FIND_EXTRA_ARG_DECL
#define DLN_FIND_EXTRA_ARG_DECL
#endif

char *dln_find_exe_r(const char*,const char*,char*,size_t DLN_FIND_EXTRA_ARG_DECL);
char *dln_find_file_r(const char*,const char*,char*,size_t DLN_FIND_EXTRA_ARG_DECL);
void *dln_load(const char*);
void *dln_open(const char *file);
void *dln_symbol(void*,const char*);

RUBY_SYMBOL_EXPORT_END

#endif
