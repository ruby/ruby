/* Definitions for data structures callers pass the regex library.

   Copyright (C) 1985, 1989-90 Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 1, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.  */
/* Multi-byte extension added May, 1993 by t^2 (Takahiro Tanimoto)
   Last change: May 21, 1993 by t^2  */
/* modifis for Ruby by matz@caelum.co.jp */

#ifndef __REGEXP_LIBRARY
#define __REGEXP_LIBRARY

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

#define RE_OPTION_EXTENDED   (1L<<0)
#define RE_OPTION_IGNORECASE (1L<<1)
#define RE_MAY_IGNORECASE    (1L<<2)
#define RE_OPTIMIZE_ANCHOR   (1L<<4)
#define RE_OPTIMIZE_EXACTN   (1L<<5)
#define RE_OPTIMIZE_NO_BM    (1L<<6)

/* For multi-byte char support */
#define MBCTYPE_ASCII 0
#define MBCTYPE_EUC 1
#define MBCTYPE_SJIS 2
#define MBCTYPE_UTF8 3

#ifdef __STDC__
extern const unsigned char *re_mbctab;
void re_mbcinit (int);
#else
extern unsigned char *re_mbctab;
void re_mbcinit ();
#endif

#undef ismbchar
#define ismbchar(c) re_mbctab[(unsigned char)(c)]
#define mbclen(c)   (re_mbctab[(unsigned char)(c)]+1)

/* This data structure is used to represent a compiled pattern.  */

struct re_pattern_buffer
  {
    char *buffer;	/* Space holding the compiled pattern commands.  */
    size_t allocated;	/* Size of space that `buffer' points to. */
    size_t used;		/* Length of portion of buffer actually occupied  */
    char *fastmap;	/* Pointer to fastmap, if any, or zero if none.  */
			/* re_search uses the fastmap, if there is one,
			   to skip over totally implausible characters.  */
    char *must;	        /* Pointer to exact pattern which strings should have
			   to be matched.  */
    int *must_skip;     /* Pointer to exact pattern skip table for bm_search */
    char *stclass;      /* Pointer to character class list at top */
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
    size_t allocated;
    size_t num_regs;
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


#ifdef NeXT
#define re_match rre_match
#endif

#ifdef __STDC__

extern char *re_compile_pattern (char *, size_t, struct re_pattern_buffer *);
void re_free_pattern (struct re_pattern_buffer *);
/* Is this really advertised?  */
extern void re_compile_fastmap (struct re_pattern_buffer *);
extern int re_search (struct re_pattern_buffer *, char*, size_t, size_t, size_t,
		      struct re_registers *);
extern int re_match (struct re_pattern_buffer *, char *, size_t, size_t,
		     struct re_registers *);
extern void re_set_casetable (char *table);
extern void re_copy_registers (struct re_registers*, struct re_registers*);
extern void re_free_registers (struct re_registers*);

#ifndef RUBY
/* 4.2 bsd compatibility.  */
extern char *re_comp (char *);
extern int re_exec (char *);
#endif

#else /* !__STDC__ */

extern char *re_compile_pattern ();
void re_free_regexp ();
/* Is this really advertised? */
extern void re_compile_fastmap ();
extern int re_search ();
extern int re_match ();
extern void re_set_casetable ();
extern void re_copy_registers ();
extern void re_free_registers ();

#endif /* __STDC__ */

#endif /* !__REGEXP_LIBRARY */
