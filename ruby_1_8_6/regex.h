/* Definitions for data structures and routines for the regular
   expression library, version 0.12.
   Copyright (C) 1985,89,90,91,92,93,95,96,97,98 Free Software Foundation, Inc.

   This file is part of the GNU C Library.  Its master source is NOT part of
   the C library, however.  The master source lives in /gd/gnu/lib.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public License as
   published by the Free Software Foundation; either version 2 of the
   License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with the GNU C Library; see the file LGPL.  If not,
   write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
   Boston, MA 02111-1307, USA.  */
/* Multi-byte extension added May, 1993 by t^2 (Takahiro Tanimoto)
   Last change: May 21, 1993 by t^2  */
/* modified for Ruby by matz@netlab.co.jp */

#ifndef REGEX_H
#define REGEX_H

/* symbol mangling for ruby */
#ifdef RUBY
# define re_adjust_startpos ruby_re_adjust_startpos
# define re_compile_fastmap ruby_re_compile_fastmap
# define re_compile_pattern ruby_re_compile_pattern
# define re_copy_registers ruby_re_copy_registers
# define re_free_pattern ruby_re_free_pattern
# define re_free_registers ruby_re_free_registers
# define re_match ruby_re_match
# define re_mbcinit ruby_re_mbcinit
# define re_search ruby_re_search
# define re_set_casetable ruby_re_set_casetable
# define register_info_type ruby_register_info_type
#endif

#include <stddef.h>

/* Define number of parens for which we record the beginnings and ends.
   This affects how much space the `struct re_registers' type takes up.  */
#ifndef RE_NREGS
#define RE_NREGS 10
#endif

#define BYTEWIDTH 8

#define RE_REG_MAX ((1<<BYTEWIDTH)-1)

/* Maximum number of duplicates an interval can allow.  */
#ifndef RE_DUP_MAX
#define RE_DUP_MAX  ((1 << 15) - 1) 
#endif


/* If this bit is set, then character classes are supported; they are:
     [:alpha:],	[:upper:], [:lower:],  [:digit:], [:alnum:], [:xdigit:],
     [:space:], [:print:], [:punct:], [:graph:], and [:cntrl:].
   If not set, then character classes are not supported.  */
#define RE_CHAR_CLASSES (1L << 9)

/* match will be done case insensetively */
#define RE_OPTION_IGNORECASE (1L)
/* perl-style extended pattern available */
#define RE_OPTION_EXTENDED   (RE_OPTION_IGNORECASE<<1)
/* newline will be included for . */
#define RE_OPTION_MULTILINE  (RE_OPTION_EXTENDED<<1)
/* ^ and $ ignore newline */
#define RE_OPTION_SINGLELINE (RE_OPTION_MULTILINE<<1)
/* search for longest match, in accord with POSIX regexp */
#define RE_OPTION_LONGEST    (RE_OPTION_SINGLELINE<<1)

#define RE_MAY_IGNORECASE    (RE_OPTION_LONGEST<<1)
#define RE_OPTIMIZE_ANCHOR   (RE_MAY_IGNORECASE<<1)
#define RE_OPTIMIZE_EXACTN   (RE_OPTIMIZE_ANCHOR<<1)
#define RE_OPTIMIZE_NO_BM    (RE_OPTIMIZE_EXACTN<<1)
#define RE_OPTIMIZE_BMATCH   (RE_OPTIMIZE_NO_BM<<1)

/* For multi-byte char support */
#define MBCTYPE_ASCII 0
#define MBCTYPE_EUC 1
#define MBCTYPE_SJIS 2
#define MBCTYPE_UTF8 3

extern
#if defined _WIN32 && !defined __GNUC__ && !defined RUBY_EXPORT
__declspec(dllimport)
# endif
const unsigned char *re_mbctab;
#if defined(__STDC__)
void re_mbcinit (int);
#else
void re_mbcinit ();
#endif

#undef ismbchar
#define ismbchar(c) re_mbctab[(unsigned char)(c)]
#define mbclen(c)   (re_mbctab[(unsigned char)(c)]+1)

/* Structure used in re_match() */

typedef union
{
  unsigned char *word;
  struct {
    unsigned is_active : 1;
    unsigned matched_something : 1;
  } bits;
} register_info_type;

/* This data structure is used to represent a compiled pattern.  */

struct re_pattern_buffer
  {
    char *buffer;	/* Space holding the compiled pattern commands.  */
    int allocated;	/* Size of space that `buffer' points to. */
    int used;		/* Length of portion of buffer actually occupied  */
    char *fastmap;	/* Pointer to fastmap, if any, or zero if none.  */
			/* re_search uses the fastmap, if there is one,
			   to skip over totally implausible characters.  */
    char *must;	        /* Pointer to exact pattern which strings should have
			   to be matched.  */
    int *must_skip;     /* Pointer to exact pattern skip table for bm_search */
    long options;	/* Flags for options such as extended_pattern. */
    long re_nsub;	/* Number of subexpressions found by the compiler. */
    char fastmap_accurate;
			/* Set to zero when a new pattern is stored,
			   set to one when the fastmap is updated from it.  */
    char can_be_null;   /* Set to one by compiling fastmap
			   if this pattern might match the null string.
			   It does not necessarily match the null string
			   in that case, but if this is zero, it cannot.
			   2 as value means can match null string
			   but at end of range or before a character
			   listed in the fastmap.  */

    /* stack & working area for re_match() */
    unsigned char **regstart;
    unsigned char **regend;
    unsigned char **old_regstart;
    unsigned char **old_regend;
    register_info_type *reg_info;
    unsigned char **best_regstart;
    unsigned char **best_regend;
  };

typedef struct re_pattern_buffer regex_t;

/* Structure to store register contents data in.

   Pass the address of such a structure as an argument to re_match, etc.,
   if you want this information back.

   For i from 1 to RE_NREGS - 1, start[i] records the starting index in
   the string of where the ith subexpression matched, and end[i] records
   one after the ending index.  start[0] and end[0] are analogous, for
   the entire pattern.  */

struct re_registers
  {
    int allocated;
    int num_regs;
    int *beg;
    int *end;
  };

/* Type for byte offsets within the string.  POSIX mandates this.  */
typedef size_t regoff_t;

/* POSIX specification for registers.  Aside from the different names than
   `re_registers', POSIX uses an array of structures, instead of a
   structure of arrays.  */
typedef struct
{
  regoff_t rm_so;  /* Byte offset from string's start to substring's start.  */
  regoff_t rm_eo;  /* Byte offset from string's start to substring's end.  */
} regmatch_t;

#ifdef __STDC__

extern char *re_compile_pattern (const char *, int, struct re_pattern_buffer *);
void re_free_pattern (struct re_pattern_buffer *);
/* Is this really advertised?  */
extern int re_adjust_startpos (struct re_pattern_buffer *, const char*, int, int, int);
extern void re_compile_fastmap (struct re_pattern_buffer *);
extern int re_search (struct re_pattern_buffer *, const char*, int, int, int,
		      struct re_registers *);
extern int re_match (struct re_pattern_buffer *, const char *, int, int,
		     struct re_registers *);
extern void re_set_casetable (const char *table);
extern void re_copy_registers (struct re_registers*, struct re_registers*);
extern void re_free_registers (struct re_registers*);

#ifndef RUBY
/* 4.2 bsd compatibility.  */
extern char *re_comp (const char *);
extern int re_exec (const char *);
#endif

#else /* !__STDC__ */

extern char *re_compile_pattern ();
void re_free_regexp ();
/* Is this really advertised? */
extern int re_adjust_startpos ();
extern void re_compile_fastmap ();
extern int re_search ();
extern int re_match ();
extern void re_set_casetable ();
extern void re_copy_registers ();
extern void re_free_registers ();

#endif /* __STDC__ */

#endif /* !REGEX_H */
