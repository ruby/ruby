/* Extended regular expression matching and search library.
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


/* To test, compile with -Dtest.  This Dtestable feature turns this into
   a self-contained program which reads a pattern, describes how it
   compiles, then reads a string and searches for it.
   
   On the other hand, if you compile with both -Dtest and -Dcanned you
   can run some tests we've already thought of.  */


/* We write fatal error messages on standard error.  */
#include <stdio.h>

/* isalpha(3) etc. are used for the character classes.  */
#include <ctype.h>

#ifdef emacs

/* The `emacs' switch turns on certain special matching commands
  that make sense only in emacs. */

#include "lisp.h"
#include "buffer.h"
#include "syntax.h"

#else	/* not emacs */

#define RUBY
#include <sys/types.h>

#ifdef __STDC__
#define P(s)    s
#define MALLOC_ARG_T size_t
#else
#define P(s)    ()
#define MALLOC_ARG_T unsigned
#define volatile
#define const
#endif

/* #define	NO_ALLOCA	/* try it out for now */
#ifndef NO_ALLOCA
/* Make alloca work the best possible way.  */
#ifdef __GNUC__
#ifndef atarist
#ifndef alloca
#define alloca __builtin_alloca
#endif
#endif /* atarist */
#else
#if defined(sparc) && !defined(__GNUC__)
#include <alloca.h>
#else
char *alloca ();
#endif
#endif /* __GNUC__ */

#define FREE_AND_RETURN_VOID(stackb)	return
#define FREE_AND_RETURN(stackb,val)	return(val)
#define DOUBLE_STACK(stackx,stackb,len) \
        (stackx = (unsigned char **) alloca (2 * len			\
                                            * sizeof (unsigned char *)),\
	/* Only copy what is in use.  */				\
        (unsigned char **) memcpy (stackx, stackb, len * sizeof (char *)))
#else  /* NO_ALLOCA defined */
#define FREE_AND_RETURN_VOID(stackb)   free(stackb);return
#define FREE_AND_RETURN(stackb,val)    free(stackb);return(val)
#define DOUBLE_STACK(stackx,stackb,len) \
        (unsigned char **)xrealloc (stackb, 2 * len * sizeof (unsigned char *))
#endif /* NO_ALLOCA */

static void store_jump P((char *, int, char *));
static void insert_jump P((int, char *, char *, char *));
static void store_jump_n P((char *, int, char *, unsigned));
static void insert_jump_n P((int, char *, char *, char *, unsigned));
static void insert_op_2 P((int, char *, char *, int, int ));
static int memcmp_translate P((unsigned char *, unsigned char *,
			       int, unsigned char *));
long re_set_syntax P((long));

/* Define the syntax stuff, so we can do the \<, \>, etc.  */

/* This must be nonzero for the wordchar and notwordchar pattern
   commands in re_match_2.  */
#ifndef Sword 
#define Sword 1
#endif

#define SYNTAX(c) re_syntax_table[c]


#ifdef SYNTAX_TABLE

char *re_syntax_table;

#else /* not SYNTAX_TABLE */

static char re_syntax_table[256];
static void init_syntax_once P((void));


static void
init_syntax_once ()
{
   register int c;
   static int done = 0;

   if (done)
     return;

   memset (re_syntax_table, 0, sizeof re_syntax_table);

   for (c = 'a'; c <= 'z'; c++)
     re_syntax_table[c] = Sword;

   for (c = 'A'; c <= 'Z'; c++)
     re_syntax_table[c] = Sword;

   for (c = '0'; c <= '9'; c++)
     re_syntax_table[c] = Sword;
 
   /* Add specific syntax for ISO Latin-1.  */
   for (c = 0300; c <= 0377; c++)
     re_syntax_table[c] = Sword;
   re_syntax_table[0327] = 0;
   re_syntax_table[0367] = 0;

   done = 1;
}

#endif /* SYNTAX_TABLE */
#undef P
#endif /* emacs */


/* Sequents are missing isgraph.  */
#ifndef isgraph
#define isgraph(c) (isprint((c)) && !isspace((c)))
#endif

/* Get the interface, including the syntax bits.  */
#include "regex.h"


/* These are the command codes that appear in compiled regular
   expressions, one per byte.  Some command codes are followed by
   argument bytes.  A command code can specify any interpretation
   whatsoever for its arguments.  Zero-bytes may appear in the compiled
   regular expression.
   
   The value of `exactn' is needed in search.c (search_buffer) in emacs.
   So regex.h defines a symbol `RE_EXACTN_VALUE' to be 1; the value of
   `exactn' we use here must also be 1.  */

enum regexpcode
  {
    unused=0,
    exactn=1, /* Followed by one byte giving n, then by n literal bytes.  */
    begline,  /* Fail unless at beginning of line.  */
    endline,  /* Fail unless at end of line.  */
    jump,     /* Followed by two bytes giving relative address to jump to.  */
    on_failure_jump,	 /* Followed by two bytes giving relative address of 
			    place to resume at in case of failure.  */
    finalize_jump,	 /* Throw away latest failure point and then jump to 
			    address.  */
    maybe_finalize_jump, /* Like jump but finalize if safe to do so.
			    This is used to jump back to the beginning
			    of a repeat.  If the command that follows
			    this jump is clearly incompatible with the
			    one at the beginning of the repeat, such that
			    we can be sure that there is no use backtracking
			    out of repetitions already completed,
			    then we finalize.  */
    dummy_failure_jump,  /* Jump, and push a dummy failure point. This 
			    failure point will be thrown away if an attempt 
                            is made to use it for a failure. A + construct 
                            makes this before the first repeat.  Also
                            use it as an intermediary kind of jump when
                            compiling an or construct.  */
    succeed_n,	 /* Used like on_failure_jump except has to succeed n times;
		    then gets turned into an on_failure_jump. The relative
                    address following it is useless until then.  The
                    address is followed by two bytes containing n.  */
    jump_n,	 /* Similar to jump, but jump n times only; also the relative
		    address following is in turn followed by yet two more bytes
                    containing n.  */
    set_number_at,	/* Set the following relative location to the
			   subsequent number.  */
    anychar,	 /* Matches any (more or less) one character.  */
    charset,     /* Matches any one char belonging to specified set.
		    First following byte is number of bitmap bytes.
		    Then come bytes for a bitmap saying which chars are in.
		    Bits in each byte are ordered low-bit-first.
		    A character is in the set if its bit is 1.
		    A character too large to have a bit in the map
		    is automatically not in the set.  */
    charset_not, /* Same parameters as charset, but match any character
                    that is not one of those specified.  */
    start_memory, /* Start remembering the text that is matched, for
		    storing in a memory register.  Followed by one
                    byte containing the register number.  Register numbers
                    must be in the range 0 through RE_NREGS.  */
    stop_memory, /* Stop remembering the text that is matched
		    and store it in a memory register.  Followed by
                    one byte containing the register number. Register
                    numbers must be in the range 0 through RE_NREGS.  */
    duplicate,   /* Match a duplicate of something remembered.
		    Followed by one byte containing the index of the memory 
                    register.  */
    before_dot,	 /* Succeeds if before point.  */
    at_dot,	 /* Succeeds if at point.  */
    after_dot,	 /* Succeeds if after point.  */
    begbuf,      /* Succeeds if at beginning of buffer.  */
    endbuf,      /* Succeeds if at end of buffer.  */
    wordchar,    /* Matches any word-constituent character.  */
    notwordchar, /* Matches any char that is not a word-constituent.  */
    wordbeg,	 /* Succeeds if at word beginning.  */
    wordend,	 /* Succeeds if at word end.  */
    wordbound,   /* Succeeds if at a word boundary.  */
    notwordbound,/* Succeeds if not at a word boundary.  */
    syntaxspec,  /* Matches any character whose syntax is specified.
		    followed by a byte which contains a syntax code,
                    e.g., Sword.  */
    notsyntaxspec /* Matches any character whose syntax differs from
                     that specified.  */
  };

 
/* Number of failure points to allocate space for initially,
   when matching.  If this number is exceeded, more space is allocated,
   so it is not a hard limit.  */

#ifndef NFAILURES
#define NFAILURES 80
#endif

#ifdef CHAR_UNSIGNED
#define SIGN_EXTEND_CHAR(c) ((c)>(char)127?(c)-256:(c)) /* for IBM RT */
#endif
#ifndef SIGN_EXTEND_CHAR
#define SIGN_EXTEND_CHAR(x) (x)
#endif
 

/* Store NUMBER in two contiguous bytes starting at DESTINATION.  */
#define STORE_NUMBER(destination, number)				\
  { (destination)[0] = (number) & 0377;					\
    (destination)[1] = (number) >> 8; }
  
/* Same as STORE_NUMBER, except increment the destination pointer to
   the byte after where the number is stored.  Watch out that values for
   DESTINATION such as p + 1 won't work, whereas p will.  */
#define STORE_NUMBER_AND_INCR(destination, number)			\
  { STORE_NUMBER(destination, number);					\
    (destination) += 2; }


/* Put into DESTINATION a number stored in two contingous bytes starting
   at SOURCE.  */
#define EXTRACT_NUMBER(destination, source)				\
  { (destination) = *(source) & 0377;					\
    (destination) += SIGN_EXTEND_CHAR (*(char *)((source) + 1)) << 8; }

/* Same as EXTRACT_NUMBER, except increment the pointer for source to
   point to second byte of SOURCE.  Note that SOURCE has to be a value
   such as p, not, e.g., p + 1. */
#define EXTRACT_NUMBER_AND_INCR(destination, source)			\
  { EXTRACT_NUMBER (destination, source);				\
    (source) += 2; }


/* Specify the precise syntax of regexps for compilation.  This provides
   for compatibility for various utilities which historically have
   different, incompatible syntaxes.
   
   The argument SYNTAX is a bit-mask comprised of the various bits
   defined in regex.h.  */

long
re_set_syntax (syntax)
  long syntax;
{
  long ret;

  ret = obscure_syntax;
  obscure_syntax = syntax;
  return ret;
}

/* Set by re_set_syntax to the current regexp syntax to recognize.  */
#ifdef EUC
#define DEFAULT_MBCTYPE RE_MBCTYPE_EUC
#else
#ifdef SJIS
#define DEFAULT_MBCTYPE RE_MBCTYPE_SJIS
#else
#define DEFAULT_MBCTYPE 0
#endif
#endif
long obscure_syntax = DEFAULT_MBCTYPE;


/* Macros for re_compile_pattern, which is found below these definitions.  */

#define CHAR_CLASS_MAX_LENGTH  6

/* Fetch the next character in the uncompiled pattern, translating it if
   necessary.  */
#define PATFETCH(c)							\
  {if (p == pend) goto end_of_pattern;					\
  c = * (unsigned char *) p++;						\
  if (translate && !ismbchar (c))					\
    c = (unsigned char) translate[(unsigned char) c]; }

/* Fetch the next character in the uncompiled pattern, with no
   translation.  */
#define PATFETCH_RAW(c)							\
 {if (p == pend) goto end_of_pattern;					\
  c = * (unsigned char *) p++; }

#define PATUNFETCH p--


/* If the buffer isn't allocated when it comes in, use this.  */
#define INIT_BUF_SIZE  28

/* Make sure we have at least N more bytes of space in buffer.  */
#define GET_BUFFER_SPACE(n)						\
  {								        \
    while (b - bufp->buffer + (n) >= bufp->allocated)			\
      EXTEND_BUFFER;							\
  }

/* Make sure we have one more byte of buffer space and then add CH to it.  */
#define BUFPUSH(ch)							\
  {									\
    GET_BUFFER_SPACE (1);						\
    *b++ = (char) (ch);							\
  }
  
/* Extend the buffer by twice its current size via reallociation and
   reset the pointers that pointed into the old allocation to point to
   the correct places in the new allocation.  If extending the buffer
   results in it being larger than 1 << 16, then flag memory exhausted.  */
#define EXTEND_BUFFER							\
  { char *old_buffer = bufp->buffer;					\
    if (bufp->allocated == (1L<<16)) goto too_big;			\
    bufp->allocated *= 2;						\
    if (bufp->allocated > (1L<<16)) bufp->allocated = (1L<<16);		\
    bufp->buffer = (char *) xrealloc (bufp->buffer, bufp->allocated);	\
    if (bufp->buffer == 0)						\
      goto memory_exhausted;						\
    b = (b - old_buffer) + bufp->buffer;				\
    if (fixup_jump)							\
      fixup_jump = (fixup_jump - old_buffer) + bufp->buffer;		\
    if (laststart)							\
      laststart = (laststart - old_buffer) + bufp->buffer;		\
    begalt = (begalt - old_buffer) + bufp->buffer;			\
    if (pending_exact)							\
      pending_exact = (pending_exact - old_buffer) + bufp->buffer;	\
  }

/* Set the bit for character C in a character set list.  */
#define SET_LIST_BIT(c)							\
  (b[(unsigned char) (c) / BYTEWIDTH]					\
   |= 1 << ((unsigned char) (c) % BYTEWIDTH))

/* Get the next unsigned number in the uncompiled pattern.  */
#define GET_UNSIGNED_NUMBER(num) 					\
  { if (p != pend) 							\
      { 								\
        PATFETCH (c); 							\
	while (isdigit (c)) 						\
	  { 								\
	    if (num < 0) 						\
	       num = 0; 						\
            num = num * 10 + c - '0'; 					\
	    if (p == pend) 						\
	       break; 							\
	    PATFETCH (c); 						\
	  } 								\
        } 								\
  }

/* Subroutines for re_compile_pattern.  */
/* static void store_jump (), insert_jump (), store_jump_n (),
	    insert_jump_n (), insert_op_2 (); */

#define STORE_MBC(p, c) \
  ((p)[0] = (unsigned char)(c >> 8), (p)[1] = (unsigned char)(c))
#define STORE_MBC_AND_INCR(p, c) \
  (*(p)++ = (unsigned char)(c >> 8), *(p)++ = (unsigned char)(c))

#define EXTRACT_MBC(p) \
  ((unsigned char)(p)[0] << 8 | (unsigned char)(p)[1])
#define EXTRACT_MBC_AND_INCR(p) \
  ((p) += 2, (unsigned char)(p)[-2] << 8 | (unsigned char)(p)[-1])

#define EXTRACT_UNSIGNED(p) \
  ((unsigned char)(p)[0] | (unsigned char)(p)[1] << 8)
#define EXTRACT_UNSIGNED_AND_INCR(p) \
  ((p) += 2, (unsigned char)(p)[-2] | (unsigned char)(p)[-1] << 8)

/* Handle (mb)?charset(_not)?.

   Structure of mbcharset(_not)? in compiled pattern.

     struct {
       unsinged char id;		mbcharset(_not)?
       unsigned char sbc_size;
       unsigned char sbc_map[sbc_size];	same as charset(_not)? up to here.
       unsigned short mbc_size;		number of intervals.
       struct {
	 unsigned short beg;		beginning of interval.
	 unsigned short end;		end of interval.
       } intervals[mbc_size];
     }; */

static void
#ifdef __STDC__
set_list_bits (unsigned short c1, unsigned short c2,
	       unsigned char *b, const unsigned char *translate)
#else
set_list_bits (c1, c2, b, translate)
     unsigned short c1, c2;
     unsigned char *b;
     const unsigned char *translate;
#endif
{
  enum regexpcode op = (enum regexpcode) b[-2];
  unsigned char sbc_size = b[-1];
  unsigned short mbc_size = EXTRACT_UNSIGNED (&b[sbc_size]);
  unsigned short c, beg, end, upb;

  if (c1 > c2)
    return;
  if (c1 < 1 << BYTEWIDTH) {
    upb = c2;
    if (1 << BYTEWIDTH <= upb)
      upb = (1 << BYTEWIDTH) - 1;	/* The last single-byte char */
    if (sbc_size <= upb / BYTEWIDTH) {
      /* Allocate maximum size so it never happens again.  */
      /* NOTE: memcpy() would not work here.  */
      memmove (&b[(1 << BYTEWIDTH) / BYTEWIDTH], &b[sbc_size], 2 + mbc_size*4);
      memset (&b[sbc_size], 0, (1 << BYTEWIDTH) / BYTEWIDTH - sbc_size);
      b[-1] = sbc_size = (1 << BYTEWIDTH) / BYTEWIDTH;
    }
    if (!translate) {
      for (; c1 <= upb; c1++)
	if (!ismbchar (c1))
	  SET_LIST_BIT (c1);
    }
    else
      for (; c1 <= upb; c1++)
	if (!ismbchar (c1))
	  SET_LIST_BIT (translate[c1]);
    if (c2 < 1 << BYTEWIDTH)
      return;
    c1 = 0x8000;			/* The first wide char */
  }
  b = &b[sbc_size + 2];

  for (beg = 0, upb = mbc_size; beg < upb; ) {
    unsigned short mid = (beg + upb) >> 1;

    if (c1 - 1 > EXTRACT_MBC (&b[mid*4 + 2]))
      beg = mid + 1;
    else
      upb = mid;
  }

  for (end = beg, upb = mbc_size; end < upb; ) {
    unsigned short mid = (end + upb) >> 1;

    if (c2 >= EXTRACT_MBC (&b[mid*4]) - 1)
      end = mid + 1;
    else
      upb = mid;
  }

  if (beg != end) {
    if (c1 > EXTRACT_MBC (&b[beg*4]))
      c1 = EXTRACT_MBC (&b[beg*4]);
    if (c2 < EXTRACT_MBC (&b[(end - 1)*4]))
      c2 = EXTRACT_MBC (&b[(end - 1)*4]);
  }
  if (end < mbc_size && end != beg + 1)
    /* NOTE: memcpy() would not work here.  */
    memmove (&b[(beg + 1)*4], &b[end*4], (mbc_size - end)*4);
  STORE_MBC (&b[beg*4 + 0], c1);
  STORE_MBC (&b[beg*4 + 2], c2);
  mbc_size += beg + 1 - end;
  STORE_NUMBER (&b[-2], mbc_size);
}

static int
#ifdef __STDC__
is_in_list (unsigned short c, const unsigned char *b)
#else
is_in_list (c, b)
     unsigned short c;
     const unsigned char *b;
#endif
{
  unsigned short size;
  int in = (enum regexpcode) b[-1] == charset_not;

  size = *b++;
  if (c < 1 << BYTEWIDTH) {
    if (c / BYTEWIDTH < size && b[c / BYTEWIDTH] & 1 << c % BYTEWIDTH)
      in = !in;
  }
  else {
    unsigned short i, j;

    b += size + 2;
    size = EXTRACT_UNSIGNED (&b[-2]);

    for (i = 0, j = size; i < j; ) {
      unsigned short k = (i + j) >> 1;

      if (c > EXTRACT_MBC (&b[k*4 + 2]))
	i = k + 1;
      else
	j = k;
    }
    if (i < size && EXTRACT_MBC (&b[i*4]) <= c
	&& ((unsigned char) c != '\n' && (unsigned char) c != '\0'))
      in = !in;
  }
  return in;
}

/* re_compile_pattern takes a regular-expression string
   and converts it into a buffer full of byte commands for matching.

   PATTERN   is the address of the pattern string
   SIZE      is the length of it.
   BUFP	    is a  struct re_pattern_buffer *  which points to the info
	     on where to store the byte commands.
	     This structure contains a  char *  which points to the
	     actual space, which should have been obtained with malloc.
	     re_compile_pattern may use realloc to grow the buffer space.

   The number of bytes of commands can be found out by looking in
   the `struct re_pattern_buffer' that bufp pointed to, after
   re_compile_pattern returns. */

char *
re_compile_pattern (pattern, size, bufp)
     char *pattern;
     size_t size;
     struct re_pattern_buffer *bufp;
{
  register char *b = bufp->buffer;
  register char *p = pattern;
  char *pend = pattern + size;
  register unsigned c, c1;
  char *p0;
  unsigned char *translate = (unsigned char *) bufp->translate;

  /* Address of the count-byte of the most recently inserted `exactn'
     command.  This makes it possible to tell whether a new exact-match
     character can be added to that command or requires a new `exactn'
     command.  */
     
  char *pending_exact = 0;

  /* Address of the place where a forward-jump should go to the end of
     the containing expression.  Each alternative of an `or', except the
     last, ends with a forward-jump of this sort.  */

  char *fixup_jump = 0;

  /* Address of start of the most recently finished expression.
     This tells postfix * where to find the start of its operand.  */

  char *laststart = 0;

  /* In processing a repeat, 1 means zero matches is allowed.  */

  char zero_times_ok;

  /* In processing a repeat, 1 means many matches is allowed.  */

  char many_times_ok;

  /* Address of beginning of regexp, or inside of last \(.  */

  char *begalt = b;

  /* In processing an interval, at least this many matches must be made.  */
  int lower_bound;

  /* In processing an interval, at most this many matches can be made.  */
  int upper_bound;

  /* Place in pattern (i.e., the {) to which to go back if the interval
     is invalid.  */
  char *beg_interval = 0;
  
  /* Stack of information saved by \( and restored by \).
     Four stack elements are pushed by each \(:
       First, the value of b.
       Second, the value of fixup_jump.
       Third, the value of regnum.
       Fourth, the value of begalt.  */

  int stackb[40];
  int *stackp = stackb;
  int *stacke = stackb + 40;
  int *stackt;

  /* Counts \('s as they are encountered.  Remembered for the matching \),
     where it becomes the register number to put in the stop_memory
     command.  */

  int regnum = 1;

  bufp->fastmap_accurate = 0;

#ifndef emacs
#ifndef SYNTAX_TABLE
  /* Initialize the syntax table.  */
   init_syntax_once();
#endif
#endif

  if (bufp->allocated == 0)
    {
      bufp->allocated = INIT_BUF_SIZE;
      if (bufp->buffer)
	/* EXTEND_BUFFER loses when bufp->allocated is 0.  */
	bufp->buffer = (char *) xrealloc (bufp->buffer, INIT_BUF_SIZE);
      else
	/* Caller did not allocate a buffer.  Do it for them.  */
	bufp->buffer = (char *) xmalloc (INIT_BUF_SIZE);
      if (!bufp->buffer) goto memory_exhausted;
      begalt = b = bufp->buffer;
    }

  while (p != pend)
    {
      PATFETCH (c);

      switch (c)
	{
	case '$':
	  {
	    char *p1 = p;
	    /* When testing what follows the $,
	       look past the \-constructs that don't consume anything.  */
	    if (! (obscure_syntax & RE_CONTEXT_INDEP_OPS))
	      while (p1 != pend)
		{
		  if (*p1 == '\\' && p1 + 1 != pend
		      && (p1[1] == '<' || p1[1] == '>'
			  || p1[1] == '`' || p1[1] == '\''
#ifdef emacs
			  || p1[1] == '='
#endif
			  || p1[1] == 'b' || p1[1] == 'B'))
		    p1 += 2;
		  else
		    break;
		}
            if (obscure_syntax & RE_TIGHT_VBAR)
	      {
		if (! (obscure_syntax & RE_CONTEXT_INDEP_OPS) && p1 != pend)
		  goto normal_char;
		/* Make operand of last vbar end before this `$'.  */
		if (fixup_jump)
		  store_jump (fixup_jump, jump, b);
		fixup_jump = 0;
		BUFPUSH (endline);
		break;
	      }
	    /* $ means succeed if at end of line, but only in special contexts.
	      If validly in the middle of a pattern, it is a normal character. */

            if ((obscure_syntax & RE_CONTEXTUAL_INVALID_OPS) && p1 != pend)
	      goto invalid_pattern;
	    if (p1 == pend || *p1 == '\n'
		|| (obscure_syntax & RE_CONTEXT_INDEP_OPS)
		|| (obscure_syntax & RE_NO_BK_PARENS
		    ? *p1 == ')'
		    : *p1 == '\\' && p1[1] == ')')
		|| (obscure_syntax & RE_NO_BK_VBAR
		    ? *p1 == '|'
		    : *p1 == '\\' && p1[1] == '|'))
	      {
		BUFPUSH (endline);
		break;
	      }
	    goto normal_char;
          }
	case '^':
	  /* ^ means succeed if at beg of line, but only if no preceding 
             pattern.  */
             
          if ((obscure_syntax & RE_CONTEXTUAL_INVALID_OPS) && laststart)
            goto invalid_pattern;
          if (laststart && p - 2 >= pattern && p[-2] != '\n'
	       && !(obscure_syntax & RE_CONTEXT_INDEP_OPS))
	    goto normal_char;
	  if (obscure_syntax & RE_TIGHT_VBAR)
	    {
	      if (p != pattern + 1
		  && ! (obscure_syntax & RE_CONTEXT_INDEP_OPS))
		goto normal_char;
	      BUFPUSH (begline);
	      begalt = b;
	    }
	  else
	    BUFPUSH (begline);
	  break;

	case '+':
	case '?':
	  if ((obscure_syntax & RE_BK_PLUS_QM)
	      || (obscure_syntax & RE_LIMITED_OPS))
	    goto normal_char;
	handle_plus:
	case '*':
	  /* If there is no previous pattern, char not special. */
	  if (!laststart)
            {
              if (obscure_syntax & RE_CONTEXTUAL_INVALID_OPS)
                goto invalid_pattern;
              else if (! (obscure_syntax & RE_CONTEXT_INDEP_OPS))
		goto normal_char;
            }
	  /* If there is a sequence of repetition chars,
	     collapse it down to just one.  */
	  zero_times_ok = 0;
	  many_times_ok = 0;
	  while (1)
	    {
	      zero_times_ok |= c != '+';
	      many_times_ok |= c != '?';
	      if (p == pend)
		break;
	      PATFETCH (c);
	      if (c == '*')
		;
	      else if (!(obscure_syntax & RE_BK_PLUS_QM)
		       && (c == '+' || c == '?'))
		;
	      else if ((obscure_syntax & RE_BK_PLUS_QM)
		       && c == '\\')
		{
		  /* int c1; */
		  PATFETCH (c1);
		  if (!(c1 == '+' || c1 == '?'))
		    {
		      PATUNFETCH;
		      PATUNFETCH;
		      break;
		    }
		  c = c1;
		}
	      else
		{
		  PATUNFETCH;
		  break;
		}
	    }

	  /* Star, etc. applied to an empty pattern is equivalent
	     to an empty pattern.  */
	  if (!laststart)  
	    break;

	  /* Now we know whether or not zero matches is allowed
	     and also whether or not two or more matches is allowed.  */
	  if (many_times_ok)
	    {
	      /* If more than one repetition is allowed, put in at the
                 end a backward relative jump from b to before the next
                 jump we're going to put in below (which jumps from
                 laststart to after this jump).  */
              GET_BUFFER_SPACE (3);
	      store_jump (b, maybe_finalize_jump, laststart - 3);
	      b += 3;  	/* Because store_jump put stuff here.  */
	    }
          /* On failure, jump from laststart to b + 3, which will be the
             end of the buffer after this jump is inserted.  */
          GET_BUFFER_SPACE (3);
	  insert_jump (on_failure_jump, laststart, b + 3, b);
	  pending_exact = 0;
	  b += 3;
	  if (!zero_times_ok)
	    {
	      /* At least one repetition is required, so insert a
                 dummy-failure before the initial on-failure-jump
                 instruction of the loop. This effects a skip over that
                 instruction the first time we hit that loop.  */
              GET_BUFFER_SPACE (6);
              insert_jump (dummy_failure_jump, laststart, laststart + 6, b);
	      b += 3;
	    }
	  break;

	case '.':
	  laststart = b;
	  BUFPUSH (anychar);
	  break;

        case '[':
          if (p == pend)
            goto invalid_pattern;
	  while (b - bufp->buffer
		 > bufp->allocated - 9 - (1 << BYTEWIDTH) / BYTEWIDTH)
	    EXTEND_BUFFER;

	  laststart = b;
	  if (*p == '^')
	    {
              BUFPUSH (charset_not); 
              p++;
            }
	  else
	    BUFPUSH (charset);
	  p0 = p;

	  BUFPUSH ((1 << BYTEWIDTH) / BYTEWIDTH);
	  /* Clear the whole map */
	  memset (b, 0, (1 << BYTEWIDTH) / BYTEWIDTH + 2);
          
	  if ((obscure_syntax & RE_HAT_NOT_NEWLINE) && b[-2] == charset_not)
            SET_LIST_BIT ('\n');


	  /* Read in characters and ranges, setting map bits.  */
	  while (1)
	    {
	      int size;

	      if ((size = EXTRACT_UNSIGNED (&b[(1 << BYTEWIDTH) / BYTEWIDTH]))) {
		/* Ensure the space is enough to hold another interval
		   of multi-byte chars in charset(_not)?.  */
		size = (1 << BYTEWIDTH) / BYTEWIDTH + 2 + size*4 + 4;
		while (b + size + 1 > bufp->buffer + bufp->allocated)
		  EXTEND_BUFFER;
	      }
	      /* Don't translate while fetching, in case it's a range bound.
		 When we set the bit for the character, we translate it.  */
	      PATFETCH_RAW (c);

	      /* If set, \ escapes characters when inside [...].  */
	      if ((obscure_syntax & RE_AWK_CLASS_HACK) && c == '\\')
	        {
	          PATFETCH(c1);
		  if (ismbchar (c1)) {
		    unsigned char c2;

		    PATFETCH_RAW (c2);
		    c1 = c1 << 8 | c2;
		    set_list_bits (c1, c1, (unsigned char *) b, translate);
		    continue;
		  }
                  SET_LIST_BIT (c1);
	          continue;
	        }
              if (c == ']')
                {
                  if (p == p0 + 1)
                    {
		      /* If this is an empty bracket expression.  */
                      if ((obscure_syntax & RE_NO_EMPTY_BRACKETS) 
                          && p == pend)
                        goto invalid_pattern;
                    }
                  else 
		    /* Stop if this isn't merely a ] inside a bracket
                       expression, but rather the end of a bracket
                       expression.  */
                    break;
                }
	      if (ismbchar (c)) {
		unsigned char c2;

		PATFETCH_RAW (c2);
		c = c << 8 | c2;
	      }
              /* Get a range.  */
              if (p[0] == '-' && p[1] != ']')
		{
		  PATFETCH_RAW (c1);
		  /* Don't translate the range bounds while fetching them.  */
		  PATFETCH_RAW (c1);
		  if (ismbchar (c)) {
		    unsigned char c2;

		    PATFETCH_RAW (c2);
		    c1 = c1 << 8 | c2;
		  }
                  
		  if ((obscure_syntax & RE_NO_EMPTY_RANGES) && c > c1)
                    goto invalid_pattern;
                    
		  if ((obscure_syntax & RE_NO_HYPHEN_RANGE_END) 
                      && c1 == '-' && *p != ']')
                    goto invalid_pattern;
                    
 		  set_list_bits (c, c1, (unsigned char *) b, translate);
                }
	      else if ((obscure_syntax & RE_CHAR_CLASSES)
			&&  c == '[' && p[0] == ':')
                {
		  /* Longest valid character class word has six characters.  */
                  char str[CHAR_CLASS_MAX_LENGTH];
		  PATFETCH_RAW (c);
		  c1 = 0;
		  /* If no ] at end.  */
                  if (p == pend)
                    goto invalid_pattern;
		  while (1)
		    {
		      /* Don't translate the ``character class'' characters. */
                      PATFETCH_RAW (c);
		      if (c == ':' || c == ']' || p == pend
                          || c1 == CHAR_CLASS_MAX_LENGTH)
		        break;
		      str[c1++] = c;
		    }
		  str[c1] = '\0';
		  if (p == pend 	
		      || c == ']'	/* End of the bracket expression.  */
                      || p[0] != ']'
		      || p + 1 == pend
                      || (strcmp (str, "alpha") != 0 
                          && strcmp (str, "upper") != 0
			  && strcmp (str, "lower") != 0 
                          && strcmp (str, "digit") != 0
			  && strcmp (str, "alnum") != 0 
                          && strcmp (str, "xdigit") != 0
			  && strcmp (str, "space") != 0 
                          && strcmp (str, "print") != 0
			  && strcmp (str, "punct") != 0 
                          && strcmp (str, "graph") != 0
			  && strcmp (str, "cntrl") != 0))
		    {
		       /* Undo the ending character, the letters, and leave 
                          the leading : and [ (but set bits for them).  */
                      c1++;
		      while (c1--)    
			PATUNFETCH;
#if 1 /* The original was: */
		      SET_LIST_BIT ('[');
		      SET_LIST_BIT (':');
#else /* I think this is the right way.  */
		      if (translate) {
			SET_LIST_BIT (translate['[']);
			SET_LIST_BIT (trasnlate[':']);
		      }
		      else {
			SET_LIST_BIT ('[');
			SET_LIST_BIT (':');
		      }
#endif
	            }
                  else
                    {
                      /* The ] at the end of the character class.  */
                      PATFETCH (c);
                      if (c != ']')
                        goto invalid_pattern;
		      for (c = 0; c < (1 << BYTEWIDTH); c++)
			{
			  if ((strcmp (str, "alpha") == 0  && isalpha (c))
			       || (strcmp (str, "upper") == 0  && isupper (c))
			       || (strcmp (str, "lower") == 0  && islower (c))
			       || (strcmp (str, "digit") == 0  && isdigit (c))
			       || (strcmp (str, "alnum") == 0  && isalnum (c))
			       || (strcmp (str, "xdigit") == 0  && isxdigit (c))
			       || (strcmp (str, "space") == 0  && isspace (c))
			       || (strcmp (str, "print") == 0  && isprint (c))
			       || (strcmp (str, "punct") == 0  && ispunct (c))
			       || (strcmp (str, "graph") == 0  && isgraph (c))
			       || (strcmp (str, "cntrl") == 0  && iscntrl (c)))
			    SET_LIST_BIT (c);
			}
		    }
                }
              else if (translate && c < 1 << BYTEWIDTH)
		SET_LIST_BIT (translate[c]);
	      else
		set_list_bits (c, c, (unsigned char *) b, translate);
	    }

          /* Discard any character set/class bitmap bytes that are all
             0 at the end of the map. Decrement the map-length byte too.  */
          while ((int) b[-1] > 0 && b[b[-1] - 1] == 0) 
            b[-1]--; 
	  if (b[-1] != (1 << BYTEWIDTH) / BYTEWIDTH)
	    memmove (&b[b[-1]], &b[(1 << BYTEWIDTH) / BYTEWIDTH],
		     2 + EXTRACT_UNSIGNED (&b[(1 << BYTEWIDTH) / BYTEWIDTH])*4);
	  b += b[-1] + 2 + EXTRACT_UNSIGNED (&b[b[-1]])*4;
          break;

	case '(':
	  if (! (obscure_syntax & RE_NO_BK_PARENS))
	    goto normal_char;
	  else
	    goto handle_open;

	case ')':
	  if (! (obscure_syntax & RE_NO_BK_PARENS))
	    goto normal_char;
	  else
	    goto handle_close;

        case '\n':
	  if (! (obscure_syntax & RE_NEWLINE_OR))
	    goto normal_char;
	  else
	    goto handle_bar;

	case '|':
	  if ((obscure_syntax & RE_CONTEXTUAL_INVALID_OPS)
              && (! laststart  ||  p == pend))
	    goto invalid_pattern;
          else if (! (obscure_syntax & RE_NO_BK_VBAR))
	    goto normal_char;
	  else
	    goto handle_bar;

	case '{':
           if (! ((obscure_syntax & RE_NO_BK_CURLY_BRACES)
                  && (obscure_syntax & RE_INTERVALS)))
             goto normal_char;
           else
             goto handle_interval;
             
        case '\\':
	  if (p == pend) goto invalid_pattern;
	  PATFETCH_RAW (c);
	  switch (c)
	    {
	    case '(':
	      if (obscure_syntax & RE_NO_BK_PARENS)
		goto normal_backsl;
	    handle_open:
	      if (stackp == stacke) goto nesting_too_deep;

              /* Laststart should point to the start_memory that we are about
                 to push (unless the pattern has RE_NREGS or more ('s).  */
              *stackp++ = b - bufp->buffer;    
	      if (regnum < RE_NREGS)
	        {
		  BUFPUSH (start_memory);
		  BUFPUSH (regnum);
	        }
	      *stackp++ = fixup_jump ? fixup_jump - bufp->buffer + 1 : 0;
	      *stackp++ = regnum++;
	      *stackp++ = begalt - bufp->buffer;
	      fixup_jump = 0;
	      laststart = 0;
	      begalt = b;
	      break;

	    case ')':
	      if (obscure_syntax & RE_NO_BK_PARENS)
		goto normal_backsl;
	    handle_close:
	      if (stackp == stackb) goto unmatched_close;
	      begalt = *--stackp + bufp->buffer;
	      if (fixup_jump)
		store_jump (fixup_jump, jump, b);
	      if (stackp[-1] < RE_NREGS)
		{
		  BUFPUSH (stop_memory);
		  BUFPUSH (stackp[-1]);
		}
	      stackp -= 2;
              fixup_jump = *stackp ? *stackp + bufp->buffer - 1 : 0;
              laststart = *--stackp + bufp->buffer;
	      break;

	    case '|':
              if ((obscure_syntax & RE_LIMITED_OPS)
	          || (obscure_syntax & RE_NO_BK_VBAR))
		goto normal_backsl;
	    handle_bar:
              if (obscure_syntax & RE_LIMITED_OPS)
                goto normal_char;
	      /* Insert before the previous alternative a jump which
                 jumps to this alternative if the former fails.  */
              GET_BUFFER_SPACE (6);
              insert_jump (on_failure_jump, begalt, b + 6, b);
	      pending_exact = 0;
	      b += 3;
	      /* The alternative before the previous alternative has a
                 jump after it which gets executed if it gets matched.
                 Adjust that jump so it will jump to the previous
                 alternative's analogous jump (put in below, which in
                 turn will jump to the next (if any) alternative's such
                 jump, etc.).  The last such jump jumps to the correct
                 final destination.  */
              if (fixup_jump)
		store_jump (fixup_jump, jump, b);
                
	      /* Leave space for a jump after previous alternative---to be 
                 filled in later.  */
              fixup_jump = b;
              b += 3;

              laststart = 0;
	      begalt = b;
	      break;

            case '{': 
              if (! (obscure_syntax & RE_INTERVALS)
		  /* Let \{ be a literal.  */
                  || ((obscure_syntax & RE_INTERVALS)
                      && (obscure_syntax & RE_NO_BK_CURLY_BRACES))
		  /* If it's the string "\{".  */
		  || (p - 2 == pattern  &&  p == pend))
                goto normal_backsl;
            handle_interval:
	      beg_interval = p - 1;		/* The {.  */
              /* If there is no previous pattern, this isn't an interval.  */
	      if (!laststart)
	        {
                  if (obscure_syntax & RE_CONTEXTUAL_INVALID_OPS)
		    goto invalid_pattern;
                  else
                    goto normal_backsl;
                }
              /* It also isn't an interval if not preceded by an re
                 matching a single character or subexpression, or if
                 the current type of intervals can't handle back
                 references and the previous thing is a back reference.  */
              if (! (*laststart == anychar
		     || *laststart == charset
		     || *laststart == charset_not
		     || *laststart == start_memory
		     || (*laststart == exactn  &&  laststart[1] == 1)
		     || (! (obscure_syntax & RE_NO_BK_REFS)
                         && *laststart == duplicate)))
                {
                  if (obscure_syntax & RE_NO_BK_CURLY_BRACES)
                    goto normal_char;
                    
		  /* Posix extended syntax is handled in previous
                     statement; this is for Posix basic syntax.  */
                  if (obscure_syntax & RE_INTERVALS)
                    goto invalid_pattern;
                    
                  goto normal_backsl;
		}
              lower_bound = -1;			/* So can see if are set.  */
	      upper_bound = -1;
              GET_UNSIGNED_NUMBER (lower_bound);
	      if (c == ',')
		{
		  GET_UNSIGNED_NUMBER (upper_bound);
		  if (upper_bound < 0)
		    upper_bound = RE_DUP_MAX;
		}
	      if (upper_bound < 0)
		upper_bound = lower_bound;
              if (! (obscure_syntax & RE_NO_BK_CURLY_BRACES)) 
                {
                  if (c != '\\')
                    goto invalid_pattern;
                  PATFETCH (c);
                }
	      if (c != '}' || lower_bound < 0 || upper_bound > RE_DUP_MAX
		  || lower_bound > upper_bound 
                  || ((obscure_syntax & RE_NO_BK_CURLY_BRACES) 
		      && p != pend  && *p == '{')) 
	        {
		  if (obscure_syntax & RE_NO_BK_CURLY_BRACES)
                    goto unfetch_interval;
                  else
                    goto invalid_pattern;
		}

	      /* If upper_bound is zero, don't want to succeed at all; 
 		 jump from laststart to b + 3, which will be the end of
                 the buffer after this jump is inserted.  */
                 
               if (upper_bound == 0)
                 {
                   GET_BUFFER_SPACE (3);
                   insert_jump (jump, laststart, b + 3, b);
                   b += 3;
                 }

               /* Otherwise, after lower_bound number of succeeds, jump
                  to after the jump_n which will be inserted at the end
                  of the buffer, and insert that jump_n.  */
               else 
		 { /* Set to 5 if only one repetition is allowed and
	              hence no jump_n is inserted at the current end of
                      the buffer; then only space for the succeed_n is
                      needed.  Otherwise, need space for both the
                      succeed_n and the jump_n.  */
                      
                   unsigned slots_needed = upper_bound == 1 ? 5 : 10;
                     
                   GET_BUFFER_SPACE (slots_needed);
                   /* Initialize the succeed_n to n, even though it will
                      be set by its attendant set_number_at, because
                      re_compile_fastmap will need to know it.  Jump to
                      what the end of buffer will be after inserting
                      this succeed_n and possibly appending a jump_n.  */
                   insert_jump_n (succeed_n, laststart, b + slots_needed, 
		                  b, lower_bound);
                   b += 5; 	/* Just increment for the succeed_n here.  */

		  /* More than one repetition is allowed, so put in at
		     the end of the buffer a backward jump from b to the
                     succeed_n we put in above.  By the time we've gotten
                     to this jump when matching, we'll have matched once
                     already, so jump back only upper_bound - 1 times.  */

                   if (upper_bound > 1)
                     {
                       store_jump_n (b, jump_n, laststart, upper_bound - 1);
                       b += 5;
                       /* When hit this when matching, reset the
                          preceding jump_n's n to upper_bound - 1.  */
                       BUFPUSH (set_number_at);
		       GET_BUFFER_SPACE (2);
                       STORE_NUMBER_AND_INCR (b, -5);
                       STORE_NUMBER_AND_INCR (b, upper_bound - 1);
                     }
		   /* When hit this when matching, set the succeed_n's n.  */
                   GET_BUFFER_SPACE (5);
		   insert_op_2 (set_number_at, laststart, b, 5, lower_bound);
                   b += 5;
                 }
              pending_exact = 0;
	      beg_interval = 0;
              break;


            unfetch_interval:
	      /* If an invalid interval, match the characters as literals.  */
	       if (beg_interval)
                 p = beg_interval;
  	       else
                 {
                   fprintf (stderr, 
		      "regex: no interval beginning to which to backtrack.\n");
		   exit (1);
                 }
                 
               beg_interval = 0;
               PATFETCH (c);		/* normal_char expects char in `c'.  */
	       goto normal_char;
	       break;

#ifdef emacs
	    case '=':
	      BUFPUSH (at_dot);
	      break;

	    case 's':
	      laststart = b;
	      BUFPUSH (syntaxspec);
	      PATFETCH (c);
	      BUFPUSH (syntax_spec_code[c]);
	      break;

	    case 'S':
	      laststart = b;
	      BUFPUSH (notsyntaxspec);
	      PATFETCH (c);
	      BUFPUSH (syntax_spec_code[c]);
	      break;
#endif /* emacs */

#ifdef RUBY
	    case 's':
	    case 'S':
	    case 'd':
	    case 'D':
	      while (b - bufp->buffer
		     > bufp->allocated - 9 - (1 << BYTEWIDTH) / BYTEWIDTH)
		  EXTEND_BUFFER;

	      laststart = b;
	      if (c == 's' || c == 'd') {
		  BUFPUSH (charset);
	      }
	      else {
		  BUFPUSH (charset_not);
	      }

	      BUFPUSH ((1 << BYTEWIDTH) / BYTEWIDTH);
	      memset (b, 0, (1 << BYTEWIDTH) / BYTEWIDTH + 2);
	      if (c == 's' || c == 'S') {
		  SET_LIST_BIT (' ');
		  SET_LIST_BIT ('\t');
		  SET_LIST_BIT ('\n');
		  SET_LIST_BIT ('\r');
		  SET_LIST_BIT ('\f');
	      }
	      else {
		  char cc;

		  for (cc = '0'; cc <= '9'; cc++) {
		      SET_LIST_BIT (cc);
		  }
	      }

	      while ((int) b[-1] > 0 && b[b[-1] - 1] == 0) 
		  b[-1]--; 
	      if (b[-1] != (1 << BYTEWIDTH) / BYTEWIDTH)
		  memmove (&b[b[-1]], &b[(1 << BYTEWIDTH) / BYTEWIDTH],
		    2 + EXTRACT_UNSIGNED (&b[(1 << BYTEWIDTH) / BYTEWIDTH])*4);
	      b += b[-1] + 2 + EXTRACT_UNSIGNED (&b[b[-1]])*4;
	      break;
#endif /* RUBY */

	    case 'w':
	      laststart = b;
	      BUFPUSH (wordchar);
	      break;

	    case 'W':
	      laststart = b;
	      BUFPUSH (notwordchar);
	      break;
#ifndef RUBY
	    case '<':
	      BUFPUSH (wordbeg);
	      break;

	    case '>':
	      BUFPUSH (wordend);
	      break;
#endif /* RUBY */
	    case 'b':
	      BUFPUSH (wordbound);
	      break;

	    case 'B':
	      BUFPUSH (notwordbound);
	      break;

	    case '`':
	      BUFPUSH (begbuf);
	      break;

	    case '\'':
	      BUFPUSH (endbuf);
	      break;

	    case '1':
	    case '2':
	    case '3':
	    case '4':
	    case '5':
	    case '6':
	    case '7':
	    case '8':
	    case '9':
	      if (obscure_syntax & RE_NO_BK_REFS)
                goto normal_char;
              c1 = c - '0';
	      if (c1 >= regnum)
		{
  		  if (obscure_syntax & RE_NO_EMPTY_BK_REF)
                    goto invalid_pattern;
                  else
                    goto normal_char;
                }
              /* Can't back reference to a subexpression if inside of it.  */
              for (stackt = stackp - 2;  stackt > stackb;  stackt -= 4)
 		if (*stackt == c1)
		  goto normal_char;
	      laststart = b;
	      BUFPUSH (duplicate);
	      BUFPUSH (c1);
	      break;

	    case '+':
	    case '?':
	      if (obscure_syntax & RE_BK_PLUS_QM)
		goto handle_plus;
	      else
                goto normal_backsl;
              break;

            default:
	    normal_backsl:
	      /* You might think it would be useful for \ to mean
		 not to translate; but if we don't translate it
		 it will never match anything.  */
	      if (translate && !ismbchar (c)) c = (unsigned char) translate[c];
	      goto normal_char;
	    }
	  break;

	default:
	normal_char:		/* Expects the character in `c'.  */
	  c1 = 0;
	  if (ismbchar (c)) {
	    c1 = c;
	    PATFETCH_RAW (c);
	  }
	  if (!pending_exact || pending_exact + *pending_exact + 1 != b
	      || *pending_exact >= (c1 ? 0176 : 0177)
	      || *p == '*' || *p == '^'
	      || ((obscure_syntax & RE_BK_PLUS_QM)
		  ? *p == '\\' && (p[1] == '+' || p[1] == '?')
		  : (*p == '+' || *p == '?'))
	      || ((obscure_syntax & RE_INTERVALS) 
                  && ((obscure_syntax & RE_NO_BK_CURLY_BRACES)
		      ? *p == '{'
                      : (p[0] == '\\' && p[1] == '{'))))
	    {
	      laststart = b;
	      BUFPUSH (exactn);
	      pending_exact = b;
	      BUFPUSH (0);
	    }
	  if (c1) {
	    BUFPUSH (c1);
	    (*pending_exact)++;
	  }
	  BUFPUSH (c);
	  (*pending_exact)++;
	}
    }

  if (fixup_jump)
    store_jump (fixup_jump, jump, b);

  if (stackp != stackb) goto unmatched_open;

  bufp->used = b - bufp->buffer;
  return 0;

 invalid_pattern:
  return "Invalid regular expression";

 unmatched_open:
  return "Unmatched \\(";

 unmatched_close:
  return "Unmatched \\)";

 end_of_pattern:
  return "Premature end of regular expression";

 nesting_too_deep:
  return "Nesting too deep";

 too_big:
  return "Regular expression too big";

 memory_exhausted:
  return "Memory exhausted";
}


/* Store a jump of the form <OPCODE> <relative address>.
   Store in the location FROM a jump operation to jump to relative
   address FROM - TO.  OPCODE is the opcode to store.  */

static void
store_jump (from, opcode, to)
     char *from, *to;
     int opcode;
{
  from[0] = (char)opcode;
  STORE_NUMBER(from + 1, to - (from + 3));
}


/* Open up space before char FROM, and insert there a jump to TO.
   CURRENT_END gives the end of the storage not in use, so we know 
   how much data to copy up. OP is the opcode of the jump to insert.

   If you call this function, you must zero out pending_exact.  */

static void
insert_jump (op, from, to, current_end)
     int op;
     char *from, *to, *current_end;
{
  register char *pfrom = current_end;		/* Copy from here...  */
  register char *pto = current_end + 3;		/* ...to here.  */

  while (pfrom != from)			       
    *--pto = *--pfrom;
  store_jump (from, op, to);
}


/* Store a jump of the form <opcode> <relative address> <n> .

   Store in the location FROM a jump operation to jump to relative
   address FROM - TO.  OPCODE is the opcode to store, N is a number the
   jump uses, say, to decide how many times to jump.
   
   If you call this function, you must zero out pending_exact.  */

static void
store_jump_n (from, opcode, to, n)
     char *from, *to;
     int opcode;
     unsigned n;
{
  from[0] = (char)opcode;
  STORE_NUMBER (from + 1, to - (from + 3));
  STORE_NUMBER (from + 3, n);
}


/* Similar to insert_jump, but handles a jump which needs an extra
   number to handle minimum and maximum cases.  Open up space at
   location FROM, and insert there a jump to TO.  CURRENT_END gives the
   end of the storage in use, so we know how much data to copy up. OP is
   the opcode of the jump to insert.

   If you call this function, you must zero out pending_exact.  */

static void
insert_jump_n (op, from, to, current_end, n)
     int op;
     char *from, *to, *current_end;
     unsigned n;
{
  register char *pfrom = current_end;		/* Copy from here...  */
  register char *pto = current_end + 5;		/* ...to here.  */

  while (pfrom != from)			       
    *--pto = *--pfrom;
  store_jump_n (from, op, to, n);
}


/* Open up space at location THERE, and insert operation OP followed by
   NUM_1 and NUM_2.  CURRENT_END gives the end of the storage in use, so
   we know how much data to copy up.

   If you call this function, you must zero out pending_exact.  */

static void
insert_op_2 (op, there, current_end, num_1, num_2)
     int op;
     char *there, *current_end;
     int num_1, num_2;
{
  register char *pfrom = current_end;		/* Copy from here...  */
  register char *pto = current_end + 5;		/* ...to here.  */

  while (pfrom != there)			       
    *--pto = *--pfrom;
  
  there[0] = (char)op;
  STORE_NUMBER (there + 1, num_1);
  STORE_NUMBER (there + 3, num_2);
}



/* Given a pattern, compute a fastmap from it.  The fastmap records
   which of the (1 << BYTEWIDTH) possible characters can start a string
   that matches the pattern.  This fastmap is used by re_search to skip
   quickly over totally implausible text.

   The caller must supply the address of a (1 << BYTEWIDTH)-byte data 
   area as bufp->fastmap.
   The other components of bufp describe the pattern to be used.  */

void
re_compile_fastmap (bufp)
     struct re_pattern_buffer *bufp;
{
  unsigned char *pattern = (unsigned char *) bufp->buffer;
  int size = bufp->used;
  register char *fastmap = bufp->fastmap;
  register unsigned char *p = pattern;
  register unsigned char *pend = pattern + size;
  register int j, k;
  unsigned char *translate = (unsigned char *) bufp->translate;
  unsigned is_a_succeed_n;

#ifndef NO_ALLOCA
  unsigned char *stackb[NFAILURES];
  unsigned char **stackp = stackb;

#else
  unsigned char **stackb;
  unsigned char **stackp;
  stackb = (unsigned char **) xmalloc (NFAILURES * sizeof (unsigned char *));
  stackp = stackb;

#endif /* NO_ALLOCA */
  memset (fastmap, 0, (1 << BYTEWIDTH));
  bufp->fastmap_accurate = 1;
  bufp->can_be_null = 0;
      
  while (p)
    {
      is_a_succeed_n = 0;
      if (p == pend)
	{
	  bufp->can_be_null = 1;
	  break;
	}
#ifdef SWITCH_ENUM_BUG
      switch ((int) ((enum regexpcode) *p++))
#else
      switch ((enum regexpcode) *p++)
#endif
	{
	case exactn:
#if 0 /* The original was: */
	  if (translate)
	    fastmap[translate[p[1]]] = 1;
	  else
	    fastmap[p[1]] = 1;
#else /* The compiled pattern has already been translated.  */
	  fastmap[p[1]] = 1;
#endif
	  break;

        case begline:
        case before_dot:
	case at_dot:
	case after_dot:
	case begbuf:
	case endbuf:
	case wordbound:
	case notwordbound:
	case wordbeg:
	case wordend:
          continue;

	case endline:
	  if (translate)
	    fastmap[translate['\n']] = 1;
	  else
	    fastmap['\n'] = 1;
            
	  if (bufp->can_be_null != 1)
	    bufp->can_be_null = 2;
	  break;

	case jump_n:
        case finalize_jump:
	case maybe_finalize_jump:
	case jump:
	case dummy_failure_jump:
          EXTRACT_NUMBER_AND_INCR (j, p);
	  p += j;	
	  if (j > 0)
	    continue;
          /* Jump backward reached implies we just went through
	     the body of a loop and matched nothing.
	     Opcode jumped to should be an on_failure_jump.
	     Just treat it like an ordinary jump.
	     For a * loop, it has pushed its failure point already;
	     If so, discard that as redundant.  */

          if ((enum regexpcode) *p != on_failure_jump
	      && (enum regexpcode) *p != succeed_n)
	    continue;
          p++;
          EXTRACT_NUMBER_AND_INCR (j, p);
          p += j;		
          if (stackp != stackb && *stackp == p)
            stackp--;
          continue;
	  
        case on_failure_jump:
	handle_on_failure_jump:
          EXTRACT_NUMBER_AND_INCR (j, p);
          *++stackp = p + j;
	  if (is_a_succeed_n)
            EXTRACT_NUMBER_AND_INCR (k, p);	/* Skip the n.  */
	  continue;

	case succeed_n:
	  is_a_succeed_n = 1;
          /* Get to the number of times to succeed.  */
          p += 2;		
	  /* Increment p past the n for when k != 0.  */
          EXTRACT_NUMBER_AND_INCR (k, p);
          if (k == 0)
	    {
              p -= 4;
              goto handle_on_failure_jump;
            }
          continue;
          
	case set_number_at:
          p += 4;
          continue;

        case start_memory:
	case stop_memory:
	  p++;
	  continue;

	case duplicate:
	  bufp->can_be_null = 1;
	  fastmap['\n'] = 1;
	case anychar:
	  for (j = 0; j < (1 << BYTEWIDTH); j++)
	    if (j != '\n')
	      fastmap[j] = 1;
	  if (bufp->can_be_null)
	    {
	      FREE_AND_RETURN_VOID(stackb);
	    }
	  /* Don't return; check the alternative paths
	     so we can set can_be_null if appropriate.  */
	  break;

	case wordchar:
	  for (j = 0; j < (1 << BYTEWIDTH); j++)
	    if (SYNTAX (j) == Sword)
	      fastmap[j] = 1;
	  break;

	case notwordchar:
	  for (j = 0; j < (1 << BYTEWIDTH); j++)
	    if (SYNTAX (j) != Sword)
	      fastmap[j] = 1;
	  break;

#ifdef emacs
	case syntaxspec:
	  k = *p++;
	  for (j = 0; j < (1 << BYTEWIDTH); j++)
	    if (SYNTAX (j) == (enum syntaxcode) k)
	      fastmap[j] = 1;
	  break;

	case notsyntaxspec:
	  k = *p++;
	  for (j = 0; j < (1 << BYTEWIDTH); j++)
	    if (SYNTAX (j) != (enum syntaxcode) k)
	      fastmap[j] = 1;
	  break;

#else /* not emacs */
	case syntaxspec:
	case notsyntaxspec:
	  break;
#endif /* not emacs */

	case charset:
	  /* NOTE: Charset for single-byte chars never contain
		   multi-byte char.  See set_list_bits().  */
	  for (j = *p++ * BYTEWIDTH - 1; j >= 0; j--)
	    if (p[j / BYTEWIDTH] & (1 << (j % BYTEWIDTH)))
	      {
#if 0 /* The original was: */
		if (translate)
		  fastmap[translate[j]] = 1;
		else
		  fastmap[j] = 1;
#else /* The compiled pattern has already been translated.  */
	      fastmap[j] = 1;
#endif
	      }
	  {
	    unsigned short size;
	    unsigned char c, end;

	    p += p[-1] + 2;
	    size = EXTRACT_UNSIGNED (&p[-2]);
	    for (j = 0; j < size; j++)
	      /* set bits for 1st bytes of multi-byte chars.  */
	      for (c = (unsigned char) p[j*4],
		   end = (unsigned char) p[j*4 + 2];
		   c <= end; c++)
		/* NOTE: Charset for multi-byte chars might contain
		         single-byte chars.  We must reject them. */
		if (ismbchar (c))
		  fastmap[c] = 1;
	  }
	  break;

	case charset_not:
	  /* S: set of all single-byte chars.
	     M: set of all first bytes that can start multi-byte chars.
	     s: any set of single-byte chars.
	     m: any set of first bytes that can start multi-byte chars.

	     We assume S+M = U.
	       ___      _   _
	       s+m = (S*s+M*m).  */
	  /* Chars beyond end of map must be allowed */
	  /* NOTE: Charset_not for single-byte chars might contain
		   multi-byte chars.  See set_list_bits(). */
	  for (j = *p * BYTEWIDTH; j < (1 << BYTEWIDTH); j++)
	    if (!ismbchar (j))
	      fastmap[j] = 1;

	  for (j = *p++ * BYTEWIDTH - 1; j >= 0; j--)
	    if (!(p[j / BYTEWIDTH] & (1 << (j % BYTEWIDTH))))
	      {
		if (!ismbchar (j))
		  fastmap[j] = 1;
	      }
	  {
	    unsigned short size;
	    unsigned char c, beg;

	    p += p[-1] + 2;
	    size = EXTRACT_UNSIGNED (&p[-2]);
	    c = 0x8000;
	    for (j = 0; j < size; j++) {
	      for (beg = (unsigned char) p[j*4 + 0]; c < beg; c++)
		if (ismbchar (c))
		  fastmap[c] = 1;
	      c = (unsigned char) p[j*4 + 2] + 1;
	    }
	  }
	  break;

	case unused:	/* pacify gcc -Wall */
	  break;
	}

      /* Get here means we have successfully found the possible starting
         characters of one path of the pattern.  We need not follow this
         path any farther.  Instead, look at the next alternative
         remembered in the stack.  */
   if (stackp != stackb)
	p = *stackp--;
      else
	break;
    }
   FREE_AND_RETURN_VOID(stackb);
}



/* Like re_search_2, below, but only one string is specified, and
   doesn't let you say where to stop matching. */

int
re_search (pbufp, string, size, startpos, range, regs)
     struct re_pattern_buffer *pbufp;
     char *string;
     int size, startpos, range;
     struct re_registers *regs;
{
  return re_search_2 (pbufp, (char *) 0, 0, string, size, startpos, range, 
		      regs, size);
}


/* Using the compiled pattern in PBUFP->buffer, first tries to match the
   virtual concatenation of STRING1 and STRING2, starting first at index
   STARTPOS, then at STARTPOS + 1, and so on.  RANGE is the number of
   places to try before giving up.  If RANGE is negative, it searches
   backwards, i.e., the starting positions tried are STARTPOS, STARTPOS
   - 1, etc.  STRING1 and STRING2 are of SIZE1 and SIZE2, respectively.
   In REGS, return the indices of the virtual concatenation of STRING1
   and STRING2 that matched the entire PBUFP->buffer and its contained
   subexpressions.  Do not consider matching one past the index MSTOP in
   the virtual concatenation of STRING1 and STRING2.

   The value returned is the position in the strings at which the match
   was found, or -1 if no match was found, or -2 if error (such as
   failure stack overflow).  */

int
re_search_2 (pbufp, string1, size1, string2, size2, startpos, range,
	     regs, mstop)
     struct re_pattern_buffer *pbufp;
     char *string1, *string2;
     int size1, size2;
     int startpos;
     register int range;
     struct re_registers *regs;
     int mstop;
{
  register char *fastmap = pbufp->fastmap;
  register unsigned char *translate = (unsigned char *) pbufp->translate;
  int total_size = size1 + size2;
  int endpos = startpos + range;
  int val;

  /* Check for out-of-range starting position.  */
  if (startpos < 0  ||  startpos > total_size)
    return -1;
    
  /* Fix up range if it would eventually take startpos outside of the
     virtual concatenation of string1 and string2.  */
  if (endpos < -1)
    range = -1 - startpos;
  else if (endpos > total_size)
    range = total_size - startpos;

  /* Update the fastmap now if not correct already.  */
  if (fastmap && !pbufp->fastmap_accurate)
    re_compile_fastmap (pbufp);
  
  /* If the search isn't to be a backwards one, don't waste time in a
     long search for a pattern that says it is anchored.  */
  if (pbufp->used > 0 && (enum regexpcode) pbufp->buffer[0] == begbuf
      && range > 0)
    {
      if (startpos > 0)
	return -1;
      else
	range = 1;
    }

  while (1)
    { 
      /* If a fastmap is supplied, skip quickly over characters that
         cannot possibly be the start of a match.  Note, however, that
         if the pattern can possibly match the null string, we must
         test it at each starting point so that we take the first null
         string we get.  */

      if (fastmap && startpos < total_size && pbufp->can_be_null != 1)
	{
	  if (range > 0)	/* Searching forwards.  */
	    {
	      register int lim = 0;
	      register unsigned char *p, c;
	      int irange = range;
	      if (startpos < size1 && startpos + range >= size1)
		lim = range - (size1 - startpos);

	      p = ((unsigned char *)
		   &(startpos >= size1 ? string2 - size1 : string1)[startpos]);

	      while (range > lim) {
		c = *p++;
		if (ismbchar (c)) {
		  if (fastmap[c])
		    break;
		  p++;
		  range--;
		}
		else
		  if (fastmap[translate ? translate[c] : c])
		    break;
		range--;
	      }
	      startpos += irange - range;
	    }
	  else				/* Searching backwards.  */
	    {
	      register unsigned char c;

              if (string1 == 0 || startpos >= size1)
		c = string2[startpos - size1];
	      else 
		c = string1[startpos];

              c &= 0xff;
	      if (translate ? !fastmap[translate[c]] : !fastmap[c])
		goto advance;
	    }
	}

      if (range >= 0 && startpos == total_size
	  && fastmap && pbufp->can_be_null == 0)
	return -1;

      val = re_match_2 (pbufp, string1, size1, string2, size2, startpos,
			regs, mstop);
      if (val >= 0)
	return startpos;
      if (val == -2)
	return -2;

#ifndef NO_ALLOCA
#ifdef C_ALLOCA
      alloca (0);
#endif /* C_ALLOCA */

#endif /* NO_ALLOCA */
    advance:
      if (!range) 
        break;
      else if (range > 0) {
	const char *d = ((startpos >= size1 ? string2 - size1 : string1)
			 + startpos);

	if (ismbchar (*d)) {
	  range--, startpos++;
	  if (!range)
	    break;
	}
	range--, startpos++;
      }
      else {
	range++, startpos--;
	{
	  const char *s, *d, *p;

	  if (startpos < size1)
	    s = string1, d = string1 + startpos;
	  else
	    s = string2, d = string2 + startpos - size1;
	  for (p = d; p-- > s && ismbchar(*p); )
	    /* --p >= s would not work on 80[12]?86. 
	      (when the offset of s equals 0 other than huge model.)  */
	    ;
	  if (!((d - p) & 1)) {
	    if (!range)
	      break;
	    range++, startpos--;
	  }
	}
      }
    }
  return -1;
}



#ifndef emacs   /* emacs never uses this.  */
int
re_match (pbufp, string, size, pos, regs)
     struct re_pattern_buffer *pbufp;
     char *string;
     int size, pos;
     struct re_registers *regs;
{
  return re_match_2 (pbufp, (char *) 0, 0, string, size, pos, regs, size); 
}
#endif /* not emacs */


/* The following are used for re_match_2, defined below:  */

/* Roughly the maximum number of failure points on the stack.  Would be
   exactly that if always pushed MAX_NUM_FAILURE_ITEMS each time we failed.  */
   
int re_max_failures = 2000;

/* Routine used by re_match_2.  */
/* static int memcmp_translate (); *//* already declared */


/* Structure and accessing macros used in re_match_2:  */

struct register_info
{
  unsigned is_active : 1;
  unsigned matched_something : 1;
};

#define IS_ACTIVE(R)  ((R).is_active)
#define MATCHED_SOMETHING(R)  ((R).matched_something)


/* Macros used by re_match_2:  */


/* I.e., regstart, regend, and reg_info.  */

#define NUM_REG_ITEMS  3

/* We push at most this many things on the stack whenever we
   fail.  The `+ 2' refers to PATTERN_PLACE and STRING_PLACE, which are
   arguments to the PUSH_FAILURE_POINT macro.  */

#define MAX_NUM_FAILURE_ITEMS   (RE_NREGS * NUM_REG_ITEMS + 2)


/* We push this many things on the stack whenever we fail.  */

#define NUM_FAILURE_ITEMS  (last_used_reg * NUM_REG_ITEMS + 2)


/* This pushes most of the information about the current state we will want
   if we ever fail back to it.  */

#define PUSH_FAILURE_POINT(pattern_place, string_place)			\
  {									\
    long last_used_reg, this_reg;					\
									\
    /* Find out how many registers are active or have been matched.	\
       (Aside from register zero, which is only set at the end.)  */	\
    for (last_used_reg = RE_NREGS - 1; last_used_reg > 0; last_used_reg--)\
      if (regstart[last_used_reg] != (unsigned char *)(-1L))		\
        break;								\
									\
    if (stacke - stackp < NUM_FAILURE_ITEMS)				\
      {									\
	unsigned char **stackx;						\
	unsigned int len = stacke - stackb;				\
	if (len > re_max_failures * MAX_NUM_FAILURE_ITEMS)		\
	  {								\
	    FREE_AND_RETURN(stackb,(-2));				\
	  }								\
									\
        /* Roughly double the size of the stack.  */			\
        stackx = DOUBLE_STACK(stackx,stackb,len);			\
	/* Rearrange the pointers. */					\
	stackp = stackx + (stackp - stackb);				\
	stackb = stackx;						\
	stacke = stackb + 2 * len;					\
      }									\
									\
    /* Now push the info for each of those registers.  */		\
    for (this_reg = 1; this_reg <= last_used_reg; this_reg++)		\
      {									\
        *stackp++ = regstart[this_reg];					\
        *stackp++ = regend[this_reg];					\
        *stackp++ = (unsigned char *) &reg_info[this_reg];		\
      }									\
									\
    /* Push how many registers we saved.  */				\
    *stackp++ = (unsigned char *) last_used_reg;			\
									\
    *stackp++ = pattern_place;                                          \
    *stackp++ = string_place;                                           \
  }
  

/* This pops what PUSH_FAILURE_POINT pushes.  */

#define POP_FAILURE_POINT()						\
  {									\
    int temp;								\
    stackp -= 2;		/* Remove failure points.  */		\
    temp = (int) *--stackp;	/* How many regs pushed.  */	        \
    temp *= NUM_REG_ITEMS;	/* How much to take off the stack.  */	\
    stackp -= temp; 		/* Remove the register info.  */	\
  }


#define MATCHING_IN_FIRST_STRING  (dend == end_match_1)

/* Is true if there is a first string and if PTR is pointing anywhere
   inside it or just past the end.  */
   
#define IS_IN_FIRST_STRING(ptr) 					\
	(size1 && string1 <= (ptr) && (ptr) <= string1 + size1)

/* Call before fetching a character with *d.  This switches over to
   string2 if necessary.  */

#define PREFETCH							\
 while (d == dend)						    	\
  {									\
    /* end of string2 => fail.  */					\
    if (dend == end_match_2) 						\
      goto fail;							\
    /* end of string1 => advance to string2.  */ 			\
    d = string2;						        \
    dend = end_match_2;							\
  }


/* Call this when have matched something; it sets `matched' flags for the
   registers corresponding to the subexpressions of which we currently
   are inside.  */
#define SET_REGS_MATCHED 						\
  { unsigned this_reg; 							\
    for (this_reg = 0; this_reg < RE_NREGS; this_reg++) 		\
      { 								\
        if (IS_ACTIVE(reg_info[this_reg]))				\
          MATCHED_SOMETHING(reg_info[this_reg]) = 1;			\
        else								\
          MATCHED_SOMETHING(reg_info[this_reg]) = 0;			\
      } 								\
  }

/* Test if at very beginning or at very end of the virtual concatenation
   of string1 and string2.  If there is only one string, we've put it in
   string2.  */

#define AT_STRINGS_BEG  (d == (size1 ? string1 : string2)  ||  !size2)
#define AT_STRINGS_END  (d == end2)	

#define AT_WORD_BOUNDARY						\
  (AT_STRINGS_BEG || AT_STRINGS_END || IS_A_LETTER (d - 1) != IS_A_LETTER (d))

/* We have two special cases to check for: 
     1) if we're past the end of string1, we have to look at the first
        character in string2;
     2) if we're before the beginning of string2, we have to look at the
        last character in string1; we assume there is a string1, so use
        this in conjunction with AT_STRINGS_BEG.  */
#define IS_A_LETTER(d)							\
  (SYNTAX ((d) == end1 ? *string2 : (d) == string2 - 1 ? *(end1 - 1) : *(d))\
   == Sword)


/* Match the pattern described by PBUFP against the virtual
   concatenation of STRING1 and STRING2, which are of SIZE1 and SIZE2,
   respectively.  Start the match at index POS in the virtual
   concatenation of STRING1 and STRING2.  In REGS, return the indices of
   the virtual concatenation of STRING1 and STRING2 that matched the
   entire PBUFP->buffer and its contained subexpressions.  Do not
   consider matching one past the index MSTOP in the virtual
   concatenation of STRING1 and STRING2.

   If pbufp->fastmap is nonzero, then it had better be up to date.

   The reason that the data to match are specified as two components
   which are to be regarded as concatenated is so this function can be
   used directly on the contents of an Emacs buffer.

   -1 is returned if there is no match.  -2 is returned if there is an
   error (such as match stack overflow).  Otherwise the value is the
   length of the substring which was matched.  */

int
re_match_2 (pbufp, string1_arg, size1, string2_arg, size2, pos, regs, mstop)
     struct re_pattern_buffer *pbufp;
     char *string1_arg, *string2_arg;
     int size1, size2;
     int pos;
     struct re_registers *regs;
     int mstop;
{
  register unsigned char *p = (unsigned char *) pbufp->buffer;

  /* Pointer to beyond end of buffer.  */
  register unsigned char *pend = p + pbufp->used;

  unsigned char *string1 = (unsigned char *) string1_arg;
  unsigned char *string2 = (unsigned char *) string2_arg;
  unsigned char *end1;		/* Just past end of first string.  */
  unsigned char *end2;		/* Just past end of second string.  */

  /* Pointers into string1 and string2, just past the last characters in
     each to consider matching.  */
  unsigned char *end_match_1, *end_match_2;

  register unsigned char *d, *dend;
  register int mcnt;			/* Multipurpose.  */
  unsigned char *translate = (unsigned char *) pbufp->translate;
  unsigned is_a_jump_n = 0;

 /* Failure point stack.  Each place that can handle a failure further
    down the line pushes a failure point on this stack.  It consists of
    restart, regend, and reg_info for all registers corresponding to the
    subexpressions we're currently inside, plus the number of such
    registers, and, finally, two char *'s.  The first char * is where to
    resume scanning the pattern; the second one is where to resume
    scanning the strings.  If the latter is zero, the failure point is a
    ``dummy''; if a failure happens and the failure point is a dummy, it
    gets discarded and the next next one is tried.  */

#ifndef NO_ALLOCA
  unsigned char *initial_stack[MAX_NUM_FAILURE_ITEMS * NFAILURES];
#endif
  unsigned char **stackb;
  unsigned char **stackp;
  unsigned char **stacke;


  /* Information on the contents of registers. These are pointers into
     the input strings; they record just what was matched (on this
     attempt) by a subexpression part of the pattern, that is, the
     regnum-th regstart pointer points to where in the pattern we began
     matching and the regnum-th regend points to right after where we
     stopped matching the regnum-th subexpression.  (The zeroth register
     keeps track of what the whole pattern matches.)  */
     
  unsigned char *regstart[RE_NREGS];
  unsigned char *regend[RE_NREGS];

  /* The is_active field of reg_info helps us keep track of which (possibly
     nested) subexpressions we are currently in. The matched_something
     field of reg_info[reg_num] helps us tell whether or not we have
     matched any of the pattern so far this time through the reg_num-th
     subexpression.  These two fields get reset each time through any
     loop their register is in.  */

  struct register_info reg_info[RE_NREGS];


  /* The following record the register info as found in the above
     variables when we find a match better than any we've seen before. 
     This happens as we backtrack through the failure points, which in
     turn happens only if we have not yet matched the entire string.  */

  unsigned best_regs_set = 0;
  unsigned char *best_regstart[RE_NREGS];
  unsigned char *best_regend[RE_NREGS];

  /* Initialize the stack. */
#ifdef NO_ALLOCA
  stackb = (unsigned char **) xmalloc (MAX_NUM_FAILURE_ITEMS * NFAILURES * sizeof (char *));
#else
  stackb = initial_stack;
#endif
  stackp = stackb;
  stacke = &stackb[MAX_NUM_FAILURE_ITEMS * NFAILURES];

#ifdef DEBUG_REGEX
  fprintf (stderr, "Entering re_match_2(%s%s)\n", string1_arg, string2_arg);
#endif

  /* Initialize subexpression text positions to -1 to mark ones that no
     \( or ( and \) or ) has been seen for. Also set all registers to
     inactive and mark them as not having matched anything or ever
     failed.  */
  for (mcnt = 0; mcnt < RE_NREGS; mcnt++)
    {
      regstart[mcnt] = regend[mcnt] = (unsigned char *) (-1L);
      IS_ACTIVE (reg_info[mcnt]) = 0;
      MATCHED_SOMETHING (reg_info[mcnt]) = 0;
    }
  
  if (regs)
    for (mcnt = 0; mcnt < RE_NREGS; mcnt++)
      regs->start[mcnt] = regs->end[mcnt] = -1;

  /* Set up pointers to ends of strings.
     Don't allow the second string to be empty unless both are empty.  */
  if (size2 == 0)
    {
      string2 = string1;
      size2 = size1;
      string1 = 0;
      size1 = 0;
    }
  end1 = string1 + size1;
  end2 = string2 + size2;

  /* Compute where to stop matching, within the two strings.  */
  if (mstop <= size1)
    {
      end_match_1 = string1 + mstop;
      end_match_2 = string2;
    }
  else
    {
      end_match_1 = end1;
      end_match_2 = string2 + mstop - size1;
    }

  /* `p' scans through the pattern as `d' scans through the data. `dend'
     is the end of the input string that `d' points within. `d' is
     advanced into the following input string whenever necessary, but
     this happens before fetching; therefore, at the beginning of the
     loop, `d' can be pointing at the end of a string, but it cannot
     equal string2.  */

  if (size1 != 0 && pos <= size1)
    d = string1 + pos, dend = end_match_1;
  else
    d = string2 + pos - size1, dend = end_match_2;


  /* This loops over pattern commands.  It exits by returning from the
     function if match is complete, or it drops through if match fails
     at this starting point in the input data.  */

  while (1)
    {
#ifdef DEBUG_REGEX
      fprintf (stderr,
	       "regex loop(%d):  matching 0x%02d\n",
	       p - (unsigned char *) pbufp->buffer,
	       *p);
#endif
      is_a_jump_n = 0;
      /* End of pattern means we might have succeeded.  */
      if (p == pend)
	{
	  /* If not end of string, try backtracking.  Otherwise done.  */
          if (d != end_match_2)
	    {
              if (stackp != stackb)
                {
                  /* More failure points to try.  */

                  unsigned in_same_string = 
        	          	IS_IN_FIRST_STRING (best_regend[0]) 
	        	        == MATCHING_IN_FIRST_STRING;

                  /* If exceeds best match so far, save it.  */
                  if (! best_regs_set
                      || (in_same_string && d > best_regend[0])
                      || (! in_same_string && ! MATCHING_IN_FIRST_STRING))
                    {
                      best_regs_set = 1;
                      best_regend[0] = d;	/* Never use regstart[0].  */
                      
                      for (mcnt = 1; mcnt < RE_NREGS; mcnt++)
                        {
                          best_regstart[mcnt] = regstart[mcnt];
                          best_regend[mcnt] = regend[mcnt];
                        }
                    }
                  goto fail;	       
                }
              /* If no failure points, don't restore garbage.  */
              else if (best_regs_set)   
                {
	      restore_best_regs:
                  /* Restore best match.  */
                  d = best_regend[0];
                  
		  for (mcnt = 0; mcnt < RE_NREGS; mcnt++)
		    {
		      regstart[mcnt] = best_regstart[mcnt];
		      regend[mcnt] = best_regend[mcnt];
		    }
                }
            }

	  /* If caller wants register contents data back, convert it 
	     to indices.  */
	  if (regs)
	    {
	      regs->start[0] = pos;
	      if (MATCHING_IN_FIRST_STRING)
		regs->end[0] = d - string1;
	      else
		regs->end[0] = d - string2 + size1;
	      for (mcnt = 1; mcnt < RE_NREGS; mcnt++)
		{
		  if (regend[mcnt] == (unsigned char *)(-1L))
		    {
		      regs->start[mcnt] = -1;
		      regs->end[mcnt] = -1;
		      continue;
		    }
		  if (IS_IN_FIRST_STRING (regstart[mcnt]))
		    regs->start[mcnt] = regstart[mcnt] - string1;
		  else
		    regs->start[mcnt] = regstart[mcnt] - string2 + size1;
                    
		  if (IS_IN_FIRST_STRING (regend[mcnt]))
		    regs->end[mcnt] = regend[mcnt] - string1;
		  else
		    regs->end[mcnt] = regend[mcnt] - string2 + size1;
		}
	    }
	  FREE_AND_RETURN(stackb,
			  (d - pos - (MATCHING_IN_FIRST_STRING ?
				      string1 :
				      string2 - size1)));
        }

      /* Otherwise match next pattern command.  */
#ifdef SWITCH_ENUM_BUG
      switch ((int) ((enum regexpcode) *p++))
#else
      switch ((enum regexpcode) *p++)
#endif
	{

	/* \( [or `(', as appropriate] is represented by start_memory,
           \) by stop_memory.  Both of those commands are followed by
           a register number in the next byte.  The text matched
           within the \( and \) is recorded under that number.  */
	case start_memory:
          regstart[*p] = d;
          IS_ACTIVE (reg_info[*p]) = 1;
          MATCHED_SOMETHING (reg_info[*p]) = 0;
          p++;
          break;

	case stop_memory:
          regend[*p] = d;
          IS_ACTIVE (reg_info[*p]) = 0;

          /* If just failed to match something this time around with a sub-
	     expression that's in a loop, try to force exit from the loop.  */
          if ((! MATCHED_SOMETHING (reg_info[*p])
	       || (enum regexpcode) p[-3] == start_memory)
	      && (p + 1) != pend)              
            {
	      register unsigned char *p2 = p + 1;
              mcnt = 0;
              switch (*p2++)
                {
                  case jump_n:
		    is_a_jump_n = 1;
                  case finalize_jump:
		  case maybe_finalize_jump:
		  case jump:
		  case dummy_failure_jump:
                    EXTRACT_NUMBER_AND_INCR (mcnt, p2);
		    if (is_a_jump_n)
		      p2 += 2;
                    break;
                }
	      p2 += mcnt;
        
              /* If the next operation is a jump backwards in the pattern
	         to an on_failure_jump, exit from the loop by forcing a
                 failure after pushing on the stack the on_failure_jump's 
                 jump in the pattern, and d.  */
	      if (mcnt < 0 && (enum regexpcode) *p2++ == on_failure_jump)
		{
                  EXTRACT_NUMBER_AND_INCR (mcnt, p2);
                  PUSH_FAILURE_POINT (p2 + mcnt, d);
                  goto fail;
                }
            }
          p++;
          break;

	/* \<digit> has been turned into a `duplicate' command which is
           followed by the numeric value of <digit> as the register number.  */
        case duplicate:
	  {
	    int regno = *p++;   /* Get which register to match against */
	    register unsigned char *d2, *dend2;

	    /* Where in input to try to start matching.  */
            d2 = regstart[regno];
            
            /* Where to stop matching; if both the place to start and
               the place to stop matching are in the same string, then
               set to the place to stop, otherwise, for now have to use
               the end of the first string.  */

            dend2 = ((IS_IN_FIRST_STRING (regstart[regno]) 
		      == IS_IN_FIRST_STRING (regend[regno]))
		     ? regend[regno] : end_match_1);
	    while (1)
	      {
		/* If necessary, advance to next segment in register
                   contents.  */
		while (d2 == dend2)
		  {
		    if (dend2 == end_match_2) break;
		    if (dend2 == regend[regno]) break;
		    d2 = string2, dend2 = regend[regno];  /* end of string1 => advance to string2. */
		  }
		/* At end of register contents => success */
		if (d2 == dend2) break;

		/* If necessary, advance to next segment in data.  */
		PREFETCH;

		/* How many characters left in this segment to match.  */
		mcnt = dend - d;
                
		/* Want how many consecutive characters we can match in
                   one shot, so, if necessary, adjust the count.  */
                if (mcnt > dend2 - d2)
		  mcnt = dend2 - d2;
                  
		/* Compare that many; failure if mismatch, else move
                   past them.  */
		if (translate 
                    ? memcmp_translate (d, d2, mcnt, translate) 
                    : memcmp ((char *)d, (char *)d2, mcnt))
		  goto fail;
		d += mcnt, d2 += mcnt;
	      }
	  }
	  break;

	case anychar:
	  PREFETCH;	  /* Fetch a data character. */
	  /* Match anything but a newline, maybe even a null.  */
	  if (ismbchar (*d)) {
	    if (d + 1 == dend || d[1] == '\n' || d[1] == '\0')
	      goto fail;
	    SET_REGS_MATCHED;
	    d += 2;
	    break;
	  }
	  if ((translate ? translate[*d] : *d) == '\n'
              || ((obscure_syntax & RE_DOT_NOT_NULL) 
                  && (translate ? translate[*d] : *d) == '\000'))
	    goto fail;
	  SET_REGS_MATCHED;
          d++;
	  break;

	case charset:
	case charset_not:
	  {
	    int not;	    /* Nonzero for charset_not.  */
	    register int c;
	    if (*(p - 1) == (unsigned char) charset_not)
	      not = 1;

	    PREFETCH;	    /* Fetch a data character. */

	    c = (unsigned char) *d;
	    if (ismbchar (c)) {
	      c <<= 8;
	      if (d + 1 != dend)
		c |= (unsigned char) d[1];
	    }
	    else if (translate)
	      c = (unsigned char) translate[c];

	    not = is_in_list (c, p);

	    p += 1 + *p + 2 + EXTRACT_UNSIGNED (&p[1 + *p])*4;

	    if (!not) goto fail;
	    SET_REGS_MATCHED;
            d++;
	    if (d != dend && c >= 1 << BYTEWIDTH)
	      d++;
	    break;
	  }

	case begline:
          if ((size1 != 0 && d == string1)
              || (size1 == 0 && size2 != 0 && d == string2)
              || (d && d[-1] == '\n')
              || (size1 == 0 && size2 == 0))
            break;
          else
            goto fail;
            
	case endline:
	  if (d == end2
	      || (d == end1 ? (size2 == 0 || *string2 == '\n') : *d == '\n'))
	    break;
	  goto fail;

	/* `or' constructs are handled by starting each alternative with
           an on_failure_jump that points to the start of the next
           alternative.  Each alternative except the last ends with a
           jump to the joining point.  (Actually, each jump except for
           the last one really jumps to the following jump, because
           tensioning the jumps is a hassle.)  */

	/* The start of a stupid repeat has an on_failure_jump that points
	   past the end of the repeat text. This makes a failure point so 
           that on failure to match a repetition, matching restarts past
           as many repetitions have been found with no way to fail and
           look for another one.  */

	/* A smart repeat is similar but loops back to the on_failure_jump
	   so that each repetition makes another failure point.  */

	case on_failure_jump:
        on_failure:
          EXTRACT_NUMBER_AND_INCR (mcnt, p);
          PUSH_FAILURE_POINT (p + mcnt, d);
          break;

	/* The end of a smart repeat has a maybe_finalize_jump back.
	   Change it either to a finalize_jump or an ordinary jump.  */
	case maybe_finalize_jump:
          EXTRACT_NUMBER_AND_INCR (mcnt, p);
	  {
	    register unsigned char *p2 = p;
	    /* Compare what follows with the beginning of the repeat.
	       If we can establish that there is nothing that they would
	       both match, we can change to finalize_jump.  */
	    while (p2 + 1 != pend
		   && (*p2 == (unsigned char) stop_memory
		       || *p2 == (unsigned char) start_memory))
	      p2 += 2;				/* Skip over reg number.  */
	    if (p2 == pend)
	      p[-3] = (unsigned char) finalize_jump;
	    else if (*p2 == (unsigned char) exactn
		     || *p2 == (unsigned char) endline)
	      {
		register int c = *p2 == (unsigned char) endline ? '\n' : p2[2];
		register unsigned char *p1 = p + mcnt;
		/* p1[0] ... p1[2] are an on_failure_jump.
		   Examine what follows that.  */
		if (p1[3] == (unsigned char) exactn && p1[5] != c)
		  p[-3] = (unsigned char) finalize_jump;
		else if (p1[3] == (unsigned char) charset
			 || p1[3] == (unsigned char) charset_not)
		  {
		    if (ismbchar (c))
		      c = c << 8 | p2[3];
		    /* `is_in_list()' is TRUE if c would match */
		    /* That means it is not safe to finalize.  */
		    if (!is_in_list (c, p1 + 4))
		      p[-3] = (unsigned char) finalize_jump;
		  }
	      }
	  }
	  p -= 2;		/* Point at relative address again.  */
	  if (p[-1] != (unsigned char) finalize_jump)
	    {
	      p[-1] = (unsigned char) jump;	
	      goto nofinalize;
	    }
        /* Note fall through.  */

	/* The end of a stupid repeat has a finalize_jump back to the
           start, where another failure point will be made which will
           point to after all the repetitions found so far.  */

        /* Take off failure points put on by matching on_failure_jump 
           because didn't fail.  Also remove the register information
           put on by the on_failure_jump.  */
        case finalize_jump:
          POP_FAILURE_POINT ();
        /* Note fall through.  */
        
	/* Jump without taking off any failure points.  */
        case jump:
	nofinalize:
	  EXTRACT_NUMBER_AND_INCR (mcnt, p);
	  p += mcnt;
	  break;

        case dummy_failure_jump:
          /* Normally, the on_failure_jump pushes a failure point, which
             then gets popped at finalize_jump.  We will end up at
             finalize_jump, also, and with a pattern of, say, `a+', we
             are skipping over the on_failure_jump, so we have to push
             something meaningless for finalize_jump to pop.  */
          PUSH_FAILURE_POINT (0, 0);
          goto nofinalize;


        /* Have to succeed matching what follows at least n times.  Then
          just handle like an on_failure_jump.  */
        case succeed_n: 
          EXTRACT_NUMBER (mcnt, p + 2);
          /* Originally, this is how many times we HAVE to succeed.  */
          if (mcnt)
            {
               mcnt--;
	       p += 2;
               STORE_NUMBER_AND_INCR (p, mcnt);
            }
	  else if (mcnt == 0)
            {
	      p[2] = unused;
              p[3] = unused;
              goto on_failure;
            }
          else
	    { 
              fprintf (stderr, "regex: the succeed_n's n is not set.\n");
              exit (1);
	    }
          break;
        
        case jump_n: 
          EXTRACT_NUMBER (mcnt, p + 2);
          /* Originally, this is how many times we CAN jump.  */
          if (mcnt)
            {
               mcnt--;
               STORE_NUMBER(p + 2, mcnt);
	       goto nofinalize;	     /* Do the jump without taking off
			                any failure points.  */
            }
          /* If don't have to jump any more, skip over the rest of command.  */
	  else      
	    p += 4;		     
          break;
        
	case set_number_at:
	  {
  	    register unsigned char *p1;

            EXTRACT_NUMBER_AND_INCR (mcnt, p);
            p1 = p + mcnt;
            EXTRACT_NUMBER_AND_INCR (mcnt, p);
	    STORE_NUMBER (p1, mcnt);
            break;
          }

        /* Ignore these.  Used to ignore the n of succeed_n's which
           currently have n == 0.  */
        case unused:
          break;

        case wordbound:
	  if (AT_WORD_BOUNDARY)
	    break;
	  goto fail;

	case notwordbound:
	  if (AT_WORD_BOUNDARY)
	    goto fail;
	  break;

	case wordbeg:
	  if (IS_A_LETTER (d) && (AT_STRINGS_BEG || !IS_A_LETTER (d - 1)))
	    break;
	  goto fail;

	case wordend:
          /* Have to check if AT_STRINGS_BEG before looking at d - 1.  */
	  if (!AT_STRINGS_BEG && IS_A_LETTER (d - 1) 
              && (!IS_A_LETTER (d) || AT_STRINGS_END))
	    break;
	  goto fail;

#ifdef emacs
	case before_dot:
	  if (PTR_CHAR_POS (d) >= point)
	    goto fail;
	  break;

	case at_dot:
	  if (PTR_CHAR_POS (d) != point)
	    goto fail;
	  break;

	case after_dot:
	  if (PTR_CHAR_POS (d) <= point)
	    goto fail;
	  break;

	case wordchar:
	  mcnt = (int) Sword;
	  goto matchsyntax;

	case syntaxspec:
	  mcnt = *p++;
	matchsyntax:
	  PREFETCH;
	  if (SYNTAX (*d++) != (enum syntaxcode) mcnt) goto fail;
          SET_REGS_MATCHED;
	  break;
	  
	case notwordchar:
	  mcnt = (int) Sword;
	  goto matchnotsyntax;

	case notsyntaxspec:
	  mcnt = *p++;
	matchnotsyntax:
	  PREFETCH;
	  if (SYNTAX (*d++) == (enum syntaxcode) mcnt) goto fail;
	  SET_REGS_MATCHED;
          break;

#else /* not emacs */

	case wordchar:
	  PREFETCH;
          if (!IS_A_LETTER (d))
            goto fail;
	  d++;
	  SET_REGS_MATCHED;
	  break;
	  
	case notwordchar:
	  PREFETCH;
	  if (IS_A_LETTER (d))
            goto fail;
	  d++;
          SET_REGS_MATCHED;
	  break;

	case before_dot:
	case at_dot:
	case after_dot:
	case syntaxspec:
	case notsyntaxspec:
	  break;

#endif /* not emacs */

	case begbuf:
          if (AT_STRINGS_BEG)
            break;
          goto fail;

        case endbuf:
	  if (AT_STRINGS_END)
	    break;
	  goto fail;

	case exactn:
	  /* Match the next few pattern characters exactly.
	     mcnt is how many characters to match.  */
	  mcnt = *p++;
	  /* This is written out as an if-else so we don't waste time
             testing `translate' inside the loop.  */
          if (translate)
	    {
	      do
		{
		  unsigned char c;

		  PREFETCH;
		  c = *d++;
		  if (ismbchar (c)) {
		    if (c != (unsigned char) *p++
			|| !--mcnt	/* パターンが正しくコンパイルさ
					   れている限り, このチェックは
					   冗長だが念のため.  */
			|| d == dend
			|| (unsigned char) *d++ != (unsigned char) *p++)
		      goto fail;
		    continue;
		  }
		  if ((unsigned char) translate[c] != (unsigned char) *p++)
		    goto fail;
		}
	      while (--mcnt);
	    }
	  else
	    {
	      do
		{
#if 0
		  /* this code suppose that multi-byte chars are not splited
		     in string1 and string2. If you want to check this with
		     speed cost, change `#if 0' here and next to `#if 1'. */
		  unsigned char c;

#endif
		  PREFETCH;
#if 0
		  c = *d++;
		  if (ismbchar (c)) {
		    if (c != (unsigned char) *p++
			|| !--mcnt
			|| d == dend)
		      goto fail;
		    c = *d++;
		  }
		  if (c != (unsigned char) *p++) goto fail;
#else
		  if (*d++ != *p++) goto fail;
#endif
		}
	      while (--mcnt);
	    }
	  SET_REGS_MATCHED;
          break;
	}
      continue;  /* Successfully executed one pattern command; keep going.  */

    /* Jump here if any matching operation fails. */
    fail:
      if (stackp != stackb)
	/* A restart point is known.  Restart there and pop it. */
	{
          short last_used_reg, this_reg;
          
          /* If this failure point is from a dummy_failure_point, just
             skip it.  */
	  if (!stackp[-2])
            {
              POP_FAILURE_POINT ();
              goto fail;
            }

          d = *--stackp;
	  p = *--stackp;
          if (d >= string1 && d <= end1)
	    dend = end_match_1;
          /* Restore register info.  */
          last_used_reg = (long) *--stackp;
          
          /* Make the ones that weren't saved -1 or 0 again.  */
          for (this_reg = RE_NREGS - 1; this_reg > last_used_reg; this_reg--)
            {
              regend[this_reg] = (unsigned char *) (-1L);
              regstart[this_reg] = (unsigned char *) (-1L);
              IS_ACTIVE (reg_info[this_reg]) = 0;
              MATCHED_SOMETHING (reg_info[this_reg]) = 0;
            }
          
          /* And restore the rest from the stack.  */
          for ( ; this_reg > 0; this_reg--)
            {
              reg_info[this_reg] = *(struct register_info *) *--stackp;
              regend[this_reg] = *--stackp;
              regstart[this_reg] = *--stackp;
            }
	}
      else
        break;   /* Matching at this starting point really fails.  */
    }

  if (best_regs_set)
    goto restore_best_regs;

  FREE_AND_RETURN(stackb,(-1)); 	/* Failure to match.  */
}


static int
memcmp_translate (s1, s2, len, translate)
     unsigned char *s1, *s2;
     register int len;
     unsigned char *translate;
{
  register unsigned char *p1 = s1, *p2 = s2, c;
  while (len)
    {
      c = *p1++;
      if (ismbchar (c)) {
	if (c != *p2++ || !--len || *p1++ != *p2++)
	  return 1;
      }
      else
	if (translate[c] != translate[*p2++])
	  return 1;
      len--;
    }
  return 0;
}



/* Entry points compatible with 4.2 BSD regex library.  */

#if !defined(emacs) && !defined(GAWK) && !defined(RUBY)

static struct re_pattern_buffer re_comp_buf;

char *
re_comp (s)
     char *s;
{
  if (!s)
    {
      if (!re_comp_buf.buffer)
	return "No previous regular expression";
      return 0;
    }

  if (!re_comp_buf.buffer)
    {
      if (!(re_comp_buf.buffer = (char *) xmalloc (200)))
	return "Memory exhausted";
      re_comp_buf.allocated = 200;
      if (!(re_comp_buf.fastmap = (char *) xmalloc (1 << BYTEWIDTH)))
	return "Memory exhausted";
    }
  return re_compile_pattern (s, strlen (s), &re_comp_buf);
}

int
re_exec (s)
     char *s;
{
  int len = strlen (s);
  return 0 <= re_search (&re_comp_buf, s, len, 0, len,
			 (struct re_registers *) 0);
}
#endif /* not emacs && not GAWK && not RUBY */



#ifdef test

#ifdef atarist
long _stksize = 2L;  /* reserve memory for stack */
#endif
#include <stdio.h>

/* Indexed by a character, gives the upper case equivalent of the
   character.  */

char upcase[0400] = 
  { 000, 001, 002, 003, 004, 005, 006, 007,
    010, 011, 012, 013, 014, 015, 016, 017,
    020, 021, 022, 023, 024, 025, 026, 027,
    030, 031, 032, 033, 034, 035, 036, 037,
    040, 041, 042, 043, 044, 045, 046, 047,
    050, 051, 052, 053, 054, 055, 056, 057,
    060, 061, 062, 063, 064, 065, 066, 067,
    070, 071, 072, 073, 074, 075, 076, 077,
    0100, 0101, 0102, 0103, 0104, 0105, 0106, 0107,
    0110, 0111, 0112, 0113, 0114, 0115, 0116, 0117,
    0120, 0121, 0122, 0123, 0124, 0125, 0126, 0127,
    0130, 0131, 0132, 0133, 0134, 0135, 0136, 0137,
    0140, 0101, 0102, 0103, 0104, 0105, 0106, 0107,
    0110, 0111, 0112, 0113, 0114, 0115, 0116, 0117,
    0120, 0121, 0122, 0123, 0124, 0125, 0126, 0127,
    0130, 0131, 0132, 0173, 0174, 0175, 0176, 0177,
    0200, 0201, 0202, 0203, 0204, 0205, 0206, 0207,
    0210, 0211, 0212, 0213, 0214, 0215, 0216, 0217,
    0220, 0221, 0222, 0223, 0224, 0225, 0226, 0227,
    0230, 0231, 0232, 0233, 0234, 0235, 0236, 0237,
    0240, 0241, 0242, 0243, 0244, 0245, 0246, 0247,
    0250, 0251, 0252, 0253, 0254, 0255, 0256, 0257,
    0260, 0261, 0262, 0263, 0264, 0265, 0266, 0267,
    0270, 0271, 0272, 0273, 0274, 0275, 0276, 0277,
    0300, 0301, 0302, 0303, 0304, 0305, 0306, 0307,
    0310, 0311, 0312, 0313, 0314, 0315, 0316, 0317,
    0320, 0321, 0322, 0323, 0324, 0325, 0326, 0327,
    0330, 0331, 0332, 0333, 0334, 0335, 0336, 0337,
    0340, 0341, 0342, 0343, 0344, 0345, 0346, 0347,
    0350, 0351, 0352, 0353, 0354, 0355, 0356, 0357,
    0360, 0361, 0362, 0363, 0364, 0365, 0366, 0367,
    0370, 0371, 0372, 0373, 0374, 0375, 0376, 0377
  };

#ifdef canned

#include "tests.h"

typedef enum { extended_test, basic_test } test_type;

/* Use this to run the tests we've thought of.  */

void
main ()
{
  test_type t = extended_test;

  if (t == basic_test)
    {
      printf ("Running basic tests:\n\n");
      test_posix_basic ();
    }
  else if (t == extended_test)
    {
      printf ("Running extended tests:\n\n");
      test_posix_extended (); 
    }
}

#else /* not canned */

/* Use this to run interactive tests.  */

int
main (argc, argv)
     int argc;
     char **argv;
{
  char pat[80];
  struct re_pattern_buffer buf;
  int i;
  char c;
  char fastmap[(1 << BYTEWIDTH)];

  /* Allow a command argument to specify the style of syntax.  */
  if (argc > 1)
    obscure_syntax = atol (argv[1]);

  buf.allocated = 40;
  buf.buffer = (char *) xmalloc (buf.allocated);
  buf.fastmap = fastmap;
  buf.translate = upcase;

  while (1)
    {
      gets (pat);

      if (*pat)
	{
          re_compile_pattern (pat, strlen(pat), &buf);

	  for (i = 0; i < buf.used; i++)
	    printchar (buf.buffer[i]);

	  putchar ('\n');

	  printf ("%d allocated, %d used.\n", buf.allocated, buf.used);

	  re_compile_fastmap (&buf);
	  printf ("Allowed by fastmap: ");
	  for (i = 0; i < (1 << BYTEWIDTH); i++)
	    if (fastmap[i]) printchar (i);
	  putchar ('\n');
	}

      gets (pat);	/* Now read the string to match against */

      i = re_match (&buf, pat, strlen (pat), 0, 0);
      printf ("Match value %d.\n", i);
    }
}

#endif


#ifdef NOTDEF
print_buf (bufp)
     struct re_pattern_buffer *bufp;
{
  int i;

  printf ("buf is :\n----------------\n");
  for (i = 0; i < bufp->used; i++)
    printchar (bufp->buffer[i]);
  
  printf ("\n%d allocated, %d used.\n", bufp->allocated, bufp->used);
  
  printf ("Allowed by fastmap: ");
  for (i = 0; i < (1 << BYTEWIDTH); i++)
    if (bufp->fastmap[i])
      printchar (i);
  printf ("\nAllowed by translate: ");
  if (bufp->translate)
    for (i = 0; i < (1 << BYTEWIDTH); i++)
      if (bufp->translate[i])
	printchar (i);
  printf ("\nfastmap is%s accurate\n", bufp->fastmap_accurate ? "" : "n't");
  printf ("can %s be null\n----------", bufp->can_be_null ? "" : "not");
}
#endif /* NOTDEF */

printchar (c)
     char c;
{
  if (c < 040 || c >= 0177)
    {
      putchar ('\\');
      putchar (((c >> 6) & 3) + '0');
      putchar (((c >> 3) & 7) + '0');
      putchar ((c & 7) + '0');
    }
  else
    putchar (c);
}

error (string)
     char *string;
{
  puts (string);
  exit (1);
}
#endif /* test */
