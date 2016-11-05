/**********************************************************************

  dln.h -

  $Author$
  created at: Wed Jan 19 16:53:09 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifndef DLN_H
#define DLN_H

#ifdef __cplusplus
# ifndef  HAVE_PROTOTYPES
#  define HAVE_PROTOTYPES 1
# endif
# ifndef  HAVE_STDARG_PROTOTYPES
#  define HAVE_STDARG_PROTOTYPES 1
# endif
#endif

#undef _
#ifdef HAVE_PROTOTYPES
# define _(args) args
#else
# define _(args) ()
#endif

typedef char *(*dln_alloc_func)(char *, size_t, void *);

RUBY_SYMBOL_EXPORT_BEGIN

#ifndef DLN_FIND_EXTRA_ARG
#define DLN_FIND_EXTRA_ARG
#endif
#ifndef DLN_FIND_EXTRA_ARG_DECL
#define DLN_FIND_EXTRA_ARG_DECL
#endif

char *dln_find_exe_r(const char*,const char*,char*,size_t DLN_FIND_EXTRA_ARG_DECL);
char *dln_find_file_r(const char*,const char*,char*,size_t DLN_FIND_EXTRA_ARG_DECL);

char *dln_realloc(char *, size_t, void *);
char *dln_find_exe_alloc(const char*,const char*,dln_alloc_func,void* DLN_FIND_EXTRA_ARG_DECL);
char *dln_find_file_alloc(const char*,const char*,dln_alloc_func,void* DLN_FIND_EXTRA_ARG_DECL);

#ifdef USE_DLN_A_OUT
extern char *dln_argv0;
#endif

void *dln_load(const char*);

RUBY_SYMBOL_EXPORT_END

#endif
