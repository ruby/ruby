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


/* This defines the various regexp syntaxes.  */
extern long re_syntax_options;


/* The following bits are used in the re_syntax_options variable to choose among
   alternative regexp syntaxes.  */

/* If this bit is set, plain parentheses serve as grouping, and backslash
     parentheses are needed for literal searching.
   If not set, backslash-parentheses are grouping, and plain parentheses
     are for literal searching.  */
#define RE_NO_BK_PARENS	1L

/* If this bit is set, plain | serves as the `or'-operator, and \| is a 
     literal.
   If not set, \| serves as the `or'-operator, and | is a literal.  */
#define RE_NO_BK_VBAR (1L << 1)

/* If this bit is set, | binds tighter than ^ or $.
   If not set, the contrary.  */
#define RE_TIGHT_VBAR (1L << 3)

/* If this bit is set, then treat newline as an OR operator.
   If not set, treat it as a normal character.  */
#define RE_NEWLINE_OR (1L << 4)

/* If this bit is set, then special characters may act as normal
   characters in some contexts. Specifically, this applies to:
	^ -- only special at the beginning, or after ( or |;
	$ -- only special at the end, or before ) or |;
	*, +, ? -- only special when not after the beginning, (, or |.
   If this bit is not set, special characters (such as *, ^, and $)
   always have their special meaning regardless of the surrounding
   context.  */
#define RE_CONTEXT_INDEP_OPS (1L << 5)

/* If this bit is not set, then \ before anything inside [ and ] is taken as 
     a real \.
   If set, then such a \ escapes the following character.  This is a
     special case for awk.  */
#define RE_AWK_CLASS_HACK (1L << 6)

/* If this bit is set, then \{ and \} or { and } serve as interval operators.
   If not set, then \{ and \} and { and } are treated as literals.  */
#define RE_INTERVALS (1L << 7)

/* If this bit is not set, then \{ and \} serve as interval operators and 
     { and } are literals.
   If set, then { and } serve as interval operators and \{ and \} are 
     literals.  */
#define RE_NO_BK_CURLY_BRACES (1L << 8)
#define RE_NO_BK_BRACES RE_NO_BK_CURLY_BRACES

/* If this bit is set, then character classes are supported; they are:
     [:alpha:],	[:upper:], [:lower:],  [:digit:], [:alnum:], [:xdigit:],
     [:space:], [:print:], [:punct:], [:graph:], and [:cntrl:].
   If not set, then character classes are not supported.  */
#define RE_CHAR_CLASSES (1L << 9)

/* If this bit is set, then the dot re doesn't match a null byte.
   If not set, it does.  */
#define RE_DOT_NOT_NULL (1L << 10)

/* If this bit is set, then [^...] doesn't match a newline.
   If not set, it does.  */
#define RE_HAT_NOT_NEWLINE (1L << 11)

/* If this bit is set, back references are recognized.
   If not set, they aren't.  */
#define RE_NO_BK_REFS (1L << 12)

/* If this bit is set, back references must refer to a preceding
   subexpression.  If not set, a back reference to a nonexistent
   subexpression is treated as literal characters.  */
#define RE_NO_EMPTY_BK_REF (1L << 13)

/* If this bit is set, bracket expressions can't be empty.  
   If it is set, they can be empty.  */
#define RE_NO_EMPTY_BRACKETS (1L << 14)

/* If this bit is set, then *, +, ? and { cannot be first in an re or
   immediately after a |, or a (.  Furthermore, a | cannot be first or
   last in an re, or immediately follow another | or a (.  Also, a ^
   cannot appear in a nonleading position and a $ cannot appear in a
   nontrailing position (outside of bracket expressions, that is).  */
#define RE_CONTEXTUAL_INVALID_OPS (1L << 15)

/* If this bit is set, then +, ? and | aren't recognized as operators.
   If it's not, they are.  */
#define RE_LIMITED_OPS (1L << 16)

/* If this bit is set, then an ending range point has to collate higher
     or equal to the starting range point.
   If it's not set, then when the ending range point collates higher
     than the starting range point, the range is just considered empty.  */
#define RE_NO_EMPTY_RANGES (1L << 17)

/* If this bit is set, then a hyphen (-) can't be an ending range point.
   If it isn't, then it can.  */
#define RE_NO_HYPHEN_RANGE_END (1L << 18)

/* If this bit is not set, then \ inside a bracket expression is literal.
   If set, then such a \ quotes the following character.  */
#define RE_BACKSLASH_ESCAPE_IN_LISTS (1L << 19)

/* Define combinations of bits for the standard possibilities.  */
#define RE_SYNTAX_POSIX_AWK (RE_NO_BK_PARENS | RE_NO_BK_VBAR \
			| RE_CONTEXT_INDEP_OPS)
#define RE_SYNTAX_AWK (RE_NO_BK_PARENS | RE_NO_BK_VBAR | RE_AWK_CLASS_HACK)
#define RE_SYNTAX_EGREP (RE_NO_BK_PARENS | RE_NO_BK_VBAR \
			| RE_CONTEXT_INDEP_OPS | RE_NEWLINE_OR)
#define RE_SYNTAX_GREP (RE_BK_PLUS_QM | RE_NEWLINE_OR)
#define RE_SYNTAX_EMACS 0
#define RE_SYNTAX_POSIX_BASIC (RE_INTERVALS | RE_BK_PLUS_QM 		\
			| RE_CHAR_CLASSES | RE_DOT_NOT_NULL 		\
                        | RE_HAT_NOT_NEWLINE | RE_NO_EMPTY_BK_REF 	\
                        | RE_NO_EMPTY_BRACKETS | RE_LIMITED_OPS		\
                        | RE_NO_EMPTY_RANGES | RE_NO_HYPHEN_RANGE_END)	
                        
#define RE_SYNTAX_POSIX_EXTENDED (RE_INTERVALS | RE_NO_BK_CURLY_BRACES	   \
			| RE_NO_BK_VBAR | RE_NO_BK_PARENS 		   \
                        | RE_HAT_NOT_NEWLINE | RE_CHAR_CLASSES 		   \
                        | RE_NO_EMPTY_BRACKETS | RE_CONTEXTUAL_INVALID_OPS \
                        | RE_NO_BK_REFS | RE_NO_EMPTY_RANGES 		   \
                        | RE_NO_HYPHEN_RANGE_END)

#define RE_OPTION_IGNORECASE (1L<<0)
#define RE_OPTION_EXTENDED   (1L<<1)

/* For multi-byte char support */
#define MBCTYPE_ASCII 0
#define MBCTYPE_EUC 1
#define MBCTYPE_SJIS 2

extern int current_mbctype;

#ifdef __STDC__
extern const unsigned char *mbctab;
void mbcinit (int);
#else
extern unsigned char *mbctab;
void mbcinit ();
#endif

#undef ismbchar
#define ismbchar(c) mbctab[(unsigned char)(c)]

/* This data structure is used to represent a compiled pattern.  */

struct re_pattern_buffer
  {
    char *buffer;	/* Space holding the compiled pattern commands.  */
    long allocated;	/* Size of space that `buffer' points to. */
    long used;		/* Length of portion of buffer actually occupied  */
    char *fastmap;	/* Pointer to fastmap, if any, or zero if none.  */
			/* re_search uses the fastmap, if there is one,
			   to skip over totally implausible characters.  */
    char *must;	        /* Pointer to exact pattern which strings should have
			   to be matched.  */

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


/* Structure to store register contents data in.

   Pass the address of such a structure as an argument to re_match, etc.,
   if you want this information back.

   For i from 1 to RE_NREGS - 1, start[i] records the starting index in
   the string of where the ith subexpression matched, and end[i] records
   one after the ending index.  start[0] and end[0] are analogous, for
   the entire pattern.  */

struct re_registers
  {
    unsigned allocated;
    unsigned num_regs;
    int *beg;
    int *end;
  };



#ifdef NeXT
#define re_match rre_match
#endif

#ifdef __STDC__

extern char *re_compile_pattern (char *, size_t, struct re_pattern_buffer *);
/* Is this really advertised?  */
extern void re_compile_fastmap (struct re_pattern_buffer *);
extern int re_search (struct re_pattern_buffer *, char*, int, int, int,
		      struct re_registers *);
extern int re_match (struct re_pattern_buffer *, char *, int, int,
		     struct re_registers *);
extern long re_set_syntax (long syntax);
extern void re_set_casetable(char *table);
extern void re_copy_registers (struct re_registers*, struct re_registers*);
extern void re_free_registers (struct re_registers*);

#ifndef RUBY
/* 4.2 bsd compatibility.  */
extern char *re_comp (char *);
extern int re_exec (char *);
#endif

#else /* !__STDC__ */

extern char *re_compile_pattern ();
/* Is this really advertised? */
extern void re_compile_fastmap ();
extern int re_search ();
extern int re_match ();
extern long re_set_syntax();
extern void re_set_casetable();
extern void re_copy_registers ();
extern void re_free_registers ();

#endif /* __STDC__ */


#ifdef SYNTAX_TABLE
extern char *re_syntax_table;
#endif

#endif /* !__REGEXP_LIBRARY */
