#ifndef ONIGMO_REGINT_H
#define ONIGMO_REGINT_H
/**********************************************************************
  regint.h -  Onigmo (Oniguruma-mod) (regular expression library)
**********************************************************************/
/*-
 * Copyright (c) 2002-2013  K.Kosako  <sndgk393 AT ybb DOT ne DOT jp>
 * Copyright (c) 2011-2016  K.Takata  <kentkt AT csc DOT jp>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/* for debug */
/* #define ONIG_DEBUG_PARSE_TREE */
/* #define ONIG_DEBUG_COMPILE */
/* #define ONIG_DEBUG_SEARCH */
/* #define ONIG_DEBUG_MATCH */
/* #define ONIG_DEBUG_MATCH_CACHE */
/* #define ONIG_DEBUG_MEMLEAK */
/* #define ONIG_DONT_OPTIMIZE */

/* for byte-code statistical data. */
/* #define ONIG_DEBUG_STATISTICS */

/* enable the match optimization by using a cache. */
#define USE_MATCH_CACHE

#if defined(ONIG_DEBUG_PARSE_TREE) || defined(ONIG_DEBUG_MATCH) || \
    defined(ONIG_DEBUG_SEARCH) || defined(ONIG_DEBUG_COMPILE) || \
    defined(ONIG_DEBUG_STATISTICS) || defined(ONIG_DEBUG_MEMLEAK)
# ifndef ONIG_DEBUG
#  define ONIG_DEBUG
# endif
#endif

/* __POWERPC__ added to accommodate Darwin case. */
#ifndef UNALIGNED_WORD_ACCESS
# if defined(__i386) || defined(__i386__) || defined(_M_IX86) || \
     defined(__x86_64) || defined(__x86_64__) || defined(_M_AMD64) || \
     defined(__powerpc64__) || defined(__POWERPC__) || defined(__aarch64__) || \
     defined(__mc68020__)
#  define UNALIGNED_WORD_ACCESS 1
# else
#  define UNALIGNED_WORD_ACCESS 0
# endif
#endif

#if UNALIGNED_WORD_ACCESS
# define PLATFORM_UNALIGNED_WORD_ACCESS
#endif

/* config */
/* spec. config */
#define USE_NAMED_GROUP
#define USE_SUBEXP_CALL
#define USE_PERL_SUBEXP_CALL
#define USE_CAPITAL_P_NAMED_GROUP
#define USE_BACKREF_WITH_LEVEL        /* \k<name+n>, \k<name-n> */
#define USE_MONOMANIAC_CHECK_CAPTURES_IN_ENDLESS_REPEAT  /* /(?:()|())*\2/ */
#define USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE     /* /\n$/ =~ "\n" */
#define USE_WARNING_REDUNDANT_NESTED_REPEAT_OPERATOR
/* !!! moved to regenc.h. */ /* #define USE_CRNL_AS_LINE_TERMINATOR */
#define USE_NO_INVALID_QUANTIFIER

/* internal config */
/* #define USE_OP_PUSH_OR_JUMP_EXACT */
#define USE_QTFR_PEEK_NEXT
#define USE_ST_LIBRARY
#define USE_SUNDAY_QUICK_SEARCH

#define INIT_MATCH_STACK_SIZE                     160
#define DEFAULT_MATCH_STACK_LIMIT_SIZE              0 /* unlimited */
#define DEFAULT_PARSE_DEPTH_LIMIT                4096

#define OPT_EXACT_MAXLEN   24

/* check config */
#if defined(USE_PERL_SUBEXP_CALL) || defined(USE_CAPITAL_P_NAMED_GROUP)
# if !defined(USE_NAMED_GROUP) || !defined(USE_SUBEXP_CALL)
#  error USE_NAMED_GROUP and USE_SUBEXP_CALL must be defined.
# endif
#endif

#if defined(__GNUC__)
# define ARG_UNUSED  __attribute__ ((unused))
#else
# define ARG_UNUSED
#endif

#if !defined(RUBY) && defined(RUBY_EXPORT)
# define RUBY
#endif
#ifdef RUBY
# ifndef RUBY_DEFINES_H
#  include "ruby/ruby.h"
#  undef xmalloc
#  undef xrealloc
#  undef xcalloc
#  undef xfree
# endif
#else /* RUBY */
# include "config.h"
# if SIZEOF_LONG_LONG > 0
#  define LONG_LONG long long
# endif
#endif /* RUBY */

#include <stdarg.h>

/* */
/* escape other system UChar definition */
#ifdef ONIG_ESCAPE_UCHAR_COLLISION
# undef ONIG_ESCAPE_UCHAR_COLLISION
#endif

#define USE_WORD_BEGIN_END          /* "\<": word-begin, "\>": word-end */
#ifdef RUBY
# undef USE_CAPTURE_HISTORY
#else
# define USE_CAPTURE_HISTORY
#endif
#define USE_VARIABLE_META_CHARS
#define USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE
/* #define USE_COMBINATION_EXPLOSION_CHECK */     /* (X*)* */


#ifndef xmalloc
# define xmalloc     malloc
# define xrealloc    realloc
# define xcalloc     calloc
# define xfree       free
#endif

#ifdef RUBY

# define CHECK_INTERRUPT_IN_MATCH_AT do { \
  msa->counter++;                         \
  if (msa->counter >= 128) {              \
    msa->counter = 0;                     \
    rb_reg_check_timeout(reg, &msa->end_time);  \
    rb_thread_check_ints();               \
  }                                       \
} while(0)
# define onig_st_init_table                  st_init_table
# define onig_st_init_table_with_size        st_init_table_with_size
# define onig_st_init_numtable               st_init_numtable
# define onig_st_init_numtable_with_size     st_init_numtable_with_size
# define onig_st_init_strtable               st_init_strtable
# define onig_st_init_strtable_with_size     st_init_strtable_with_size
# define onig_st_delete                      st_delete
# define onig_st_delete_safe                 st_delete_safe
# define onig_st_insert                      st_insert
# define onig_st_lookup                      st_lookup
# define onig_st_foreach                     st_foreach
# define onig_st_add_direct                  st_add_direct
# define onig_st_free_table                  st_free_table
# define onig_st_cleanup_safe                st_cleanup_safe
# define onig_st_copy                        st_copy
# define onig_st_nothing_key_clone           st_nothing_key_clone
# define onig_st_nothing_key_free            st_nothing_key_free
# define onig_st_is_member                   st_is_member

# define USE_UPPER_CASE_TABLE
#else /* RUBY */

# define CHECK_INTERRUPT_IN_MATCH_AT

# define st_init_table                  onig_st_init_table
# define st_init_table_with_size        onig_st_init_table_with_size
# define st_init_numtable               onig_st_init_numtable
# define st_init_numtable_with_size     onig_st_init_numtable_with_size
# define st_init_strtable               onig_st_init_strtable
# define st_init_strtable_with_size     onig_st_init_strtable_with_size
# define st_delete                      onig_st_delete
# define st_delete_safe                 onig_st_delete_safe
# define st_insert                      onig_st_insert
# define st_lookup                      onig_st_lookup
# define st_foreach                     onig_st_foreach
# define st_add_direct                  onig_st_add_direct
# define st_free_table                  onig_st_free_table
# define st_cleanup_safe                onig_st_cleanup_safe
# define st_copy                        onig_st_copy
# define st_nothing_key_clone           onig_st_nothing_key_clone
# define st_nothing_key_free            onig_st_nothing_key_free
/* */
# define onig_st_is_member              st_is_member

#endif /* RUBY */

#define STATE_CHECK_STRING_THRESHOLD_LEN             7
#define STATE_CHECK_BUFF_MAX_SIZE               0x4000

#define xmemset     memset
#define xmemcpy     memcpy
#define xmemmove    memmove

#if ((defined(RUBY_MSVCRT_VERSION) && RUBY_MSVCRT_VERSION >= 90) \
        || (!defined(RUBY_MSVCRT_VERSION) && defined(_WIN32))) \
    && !defined(__GNUC__)
# define xalloca     _alloca
# define xvsnprintf(buf,size,fmt,args)  _vsnprintf_s(buf,size,_TRUNCATE,fmt,args)
# define xsnprintf   sprintf_s
# define xstrcat(dest,src,size)   strcat_s(dest,size,src)
#else
# define xalloca     alloca
# define xvsnprintf  vsnprintf
# define xsnprintf   snprintf
# define xstrcat(dest,src,size)	  strcat(dest,src)
#endif

#if defined(ONIG_DEBUG_MEMLEAK) && defined(_MSC_VER)
# define _CRTDBG_MAP_ALLOC
# include <malloc.h>
# include <crtdbg.h>
#endif

#include <stdlib.h>

#if defined(HAVE_ALLOCA_H) && (defined(_AIX) || !defined(__GNUC__))
# include <alloca.h>
#endif

#include <string.h>

#include <ctype.h>
#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>
#endif

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#ifdef HAVE_INTTYPES_H
# include <inttypes.h>
#endif

#include <stddef.h>

#ifdef _WIN32
# include <malloc.h>	/* for alloca() */
#endif

#ifdef ONIG_DEBUG
# include <stdio.h>
#endif

#ifdef _WIN32
# if defined(_MSC_VER) && (_MSC_VER < 1300)
#  ifndef _INTPTR_T_DEFINED
#   define _INTPTR_T_DEFINED
typedef int intptr_t;
#  endif
#  ifndef _UINTPTR_T_DEFINED
#   define _UINTPTR_T_DEFINED
typedef unsigned int uintptr_t;
#  endif
# endif
#endif /* _WIN32 */

#ifndef PRIdPTR
# ifdef _WIN64
#  define PRIdPTR	"I64d"
#  define PRIuPTR	"I64u"
#  define PRIxPTR	"I64x"
# else
#  define PRIdPTR	"ld"
#  define PRIuPTR	"lu"
#  define PRIxPTR	"lx"
# endif
#endif

#ifndef PRIdPTRDIFF
# define PRIdPTRDIFF PRIdPTR
#endif

#include "regenc.h"

RUBY_SYMBOL_EXPORT_BEGIN

#ifdef MIN
# undef MIN
#endif
#ifdef MAX
# undef MAX
#endif
#define MIN(a,b) (((a)>(b))?(b):(a))
#define MAX(a,b) (((a)<(b))?(b):(a))

#define IS_NULL(p)                    (((void*)(p)) == (void*)0)
#define IS_NOT_NULL(p)                (((void*)(p)) != (void*)0)
#define CHECK_NULL_RETURN(p)          if (IS_NULL(p)) return NULL
#define CHECK_NULL_RETURN_MEMERR(p)   if (IS_NULL(p)) return ONIGERR_MEMORY
#define NULL_UCHARP                   ((UChar* )0)

#define ONIG_LAST_CODE_POINT    (~((OnigCodePoint )0))

#define PLATFORM_GET_INC_ARGUMENTS_ASSERT(val, type) \
  ((void)sizeof(char[2 * (sizeof(val) == sizeof(type)) - 1]))

#ifdef PLATFORM_UNALIGNED_WORD_ACCESS

# define PLATFORM_GET_INC(val,p,type) do{\
  PLATFORM_GET_INC_ARGUMENTS_ASSERT(val, type);\
  val  = *(type* )p;\
  (p) += sizeof(type);\
} while(0)

#else

# define PLATFORM_GET_INC(val,p,type) do{\
  PLATFORM_GET_INC_ARGUMENTS_ASSERT(val, type);\
  type platform_get_value;\
  xmemcpy(&platform_get_value, (p), sizeof(type));\
  val = platform_get_value;\
  (p) += sizeof(type);\
} while(0)

/* sizeof(OnigCodePoint) */
# define WORD_ALIGNMENT_SIZE     SIZEOF_LONG

# define GET_ALIGNMENT_PAD_SIZE(addr,pad_size) do {\
  (pad_size) = WORD_ALIGNMENT_SIZE \
               - ((uintptr_t )(addr) % WORD_ALIGNMENT_SIZE);\
  if ((pad_size) == WORD_ALIGNMENT_SIZE) (pad_size) = 0;\
} while (0)

# define ALIGNMENT_RIGHT(addr) do {\
  (addr) += (WORD_ALIGNMENT_SIZE - 1);\
  (addr) -= ((uintptr_t )(addr) % WORD_ALIGNMENT_SIZE);\
} while (0)

#endif /* PLATFORM_UNALIGNED_WORD_ACCESS */

/* stack pop level */
#define STACK_POP_LEVEL_FREE        0
#define STACK_POP_LEVEL_MEM_START   1
#define STACK_POP_LEVEL_ALL         2

/* optimize flags */
#define ONIG_OPTIMIZE_NONE              0
#define ONIG_OPTIMIZE_EXACT             1   /* Slow Search */
#define ONIG_OPTIMIZE_EXACT_BM          2   /* Boyer Moore Search */
#define ONIG_OPTIMIZE_EXACT_BM_NOT_REV  3   /* BM (applied to a multibyte string) */
#define ONIG_OPTIMIZE_EXACT_IC          4   /* Slow Search (ignore case) */
#define ONIG_OPTIMIZE_MAP               5   /* char map */
#define ONIG_OPTIMIZE_EXACT_BM_IC         6 /* BM (ignore case) */
#define ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC 7 /* BM (applied to a multibyte string) (ignore case) */

/* bit status */
typedef unsigned int  BitStatusType;

#define BIT_STATUS_BITS_NUM          (sizeof(BitStatusType) * 8)
#define BIT_STATUS_CLEAR(stats)      (stats) = 0
#define BIT_STATUS_ON_ALL(stats)     (stats) = ~((BitStatusType )0)
#define BIT_STATUS_AT(stats,n) \
  ((n) < (int )BIT_STATUS_BITS_NUM  ?  ((stats) & ((BitStatusType )1 << n)) : ((stats) & 1))

#define BIT_STATUS_ON_AT(stats,n) do {\
  if ((n) < (int )BIT_STATUS_BITS_NUM)\
    (stats) |= (1 << (n));\
  else\
    (stats) |= 1;\
} while (0)

#define BIT_STATUS_ON_AT_SIMPLE(stats,n) do {\
  if ((n) < (int )BIT_STATUS_BITS_NUM)\
    (stats) |= (1 << (n));\
} while (0)


#define INT_MAX_LIMIT           ((1UL << (SIZEOF_INT * 8 - 1)) - 1)
#define LONG_MAX_LIMIT           ((1UL << (SIZEOF_LONG * 8 - 1)) - 1)

#define DIGITVAL(code)    ((code) - '0')
#define ODIGITVAL(code)   DIGITVAL(code)
#define XDIGITVAL(enc,code) \
  (ONIGENC_IS_CODE_DIGIT(enc,code) ? DIGITVAL(code) \
   : (ONIGENC_IS_CODE_UPPER(enc,code) ? (code) - 'A' + 10 : (code) - 'a' + 10))

#define IS_SINGLELINE(option)     ((option) & ONIG_OPTION_SINGLELINE)
#define IS_MULTILINE(option)      ((option) & ONIG_OPTION_MULTILINE)
#define IS_IGNORECASE(option)     ((option) & ONIG_OPTION_IGNORECASE)
#define IS_EXTEND(option)         ((option) & ONIG_OPTION_EXTEND)
#define IS_FIND_LONGEST(option)   ((option) & ONIG_OPTION_FIND_LONGEST)
#define IS_FIND_NOT_EMPTY(option) ((option) & ONIG_OPTION_FIND_NOT_EMPTY)
#define IS_FIND_CONDITION(option) ((option) & \
          (ONIG_OPTION_FIND_LONGEST | ONIG_OPTION_FIND_NOT_EMPTY))
#define IS_NOTBOL(option)         ((option) & ONIG_OPTION_NOTBOL)
#define IS_NOTEOL(option)         ((option) & ONIG_OPTION_NOTEOL)
#define IS_NOTBOS(option)         ((option) & ONIG_OPTION_NOTBOS)
#define IS_NOTEOS(option)         ((option) & ONIG_OPTION_NOTEOS)
#define IS_ASCII_RANGE(option)    ((option) & ONIG_OPTION_ASCII_RANGE)
#define IS_POSIX_BRACKET_ALL_RANGE(option)  ((option) & ONIG_OPTION_POSIX_BRACKET_ALL_RANGE)
#define IS_WORD_BOUND_ALL_RANGE(option)     ((option) & ONIG_OPTION_WORD_BOUND_ALL_RANGE)
#define IS_NEWLINE_CRLF(option)   ((option) & ONIG_OPTION_NEWLINE_CRLF)

/* OP_SET_OPTION is required for these options.
#define IS_DYNAMIC_OPTION(option) \
  (((option) & (ONIG_OPTION_MULTILINE | ONIG_OPTION_IGNORECASE)) != 0)
*/
/* ignore-case and multibyte status are included in compiled code. */
#define IS_DYNAMIC_OPTION(option)  0

#define DISABLE_CASE_FOLD_MULTI_CHAR(case_fold_flag) \
  ((case_fold_flag) & ~INTERNAL_ONIGENC_CASE_FOLD_MULTI_CHAR)

#define REPEAT_INFINITE         -1
#define IS_REPEAT_INFINITE(n)   ((n) == REPEAT_INFINITE)

/* bitset */
#define BITS_PER_BYTE      8
#define SINGLE_BYTE_SIZE   (1 << BITS_PER_BYTE)
#define BITS_IN_ROOM       ((int )sizeof(Bits) * BITS_PER_BYTE)
#define BITSET_SIZE        (SINGLE_BYTE_SIZE / BITS_IN_ROOM)

#ifdef PLATFORM_UNALIGNED_WORD_ACCESS
typedef unsigned int   Bits;
#else
typedef unsigned char  Bits;
#endif
typedef Bits           BitSet[BITSET_SIZE];
typedef Bits*          BitSetRef;

#define SIZE_BITSET        (int )sizeof(BitSet)

#define BITSET_CLEAR(bs) do {\
  int i;\
  for (i = 0; i < BITSET_SIZE; i++) { (bs)[i] = 0; }	\
} while (0)

#define BS_ROOM(bs,pos)            (bs)[(int )(pos) / BITS_IN_ROOM]
#define BS_BIT(pos)                (1U << ((int )(pos) % BITS_IN_ROOM))

#define BITSET_AT(bs, pos)         (BS_ROOM(bs,pos) & BS_BIT(pos))
#define BITSET_SET_BIT(bs, pos)     BS_ROOM(bs,pos) |= BS_BIT(pos)
#define BITSET_CLEAR_BIT(bs, pos)   BS_ROOM(bs,pos) &= ~(BS_BIT(pos))
#define BITSET_INVERT_BIT(bs, pos)  BS_ROOM(bs,pos) ^= BS_BIT(pos)

/* bytes buffer */
typedef struct _BBuf {
  UChar* p;
  unsigned int used;
  unsigned int alloc;
} BBuf;

#define BBUF_INIT(buf,size)    onig_bbuf_init((BBuf* )(buf), (size))

#define BBUF_SIZE_INC(buf,inc) do{\
  UChar *tmp;\
  (buf)->alloc += (inc);\
  tmp = (UChar* )xrealloc((buf)->p, (buf)->alloc);\
  if (IS_NULL(tmp)) return(ONIGERR_MEMORY);\
  (buf)->p = tmp;\
} while (0)

#define BBUF_EXPAND(buf,low) do{\
  UChar *tmp;\
  do { (buf)->alloc *= 2; } while ((buf)->alloc < (unsigned int )low);\
  tmp = (UChar* )xrealloc((buf)->p, (buf)->alloc);\
  if (IS_NULL(tmp)) return(ONIGERR_MEMORY);\
  (buf)->p = tmp;\
} while (0)

#define BBUF_ENSURE_SIZE(buf,size) do{\
  unsigned int new_alloc = (buf)->alloc;\
  while (new_alloc < (unsigned int )(size)) { new_alloc *= 2; }\
  if ((buf)->alloc != new_alloc) {\
    UChar *tmp;\
    tmp = (UChar* )xrealloc((buf)->p, new_alloc);\
    if (IS_NULL(tmp)) return(ONIGERR_MEMORY);\
    (buf)->p = tmp;\
    (buf)->alloc = new_alloc;\
  }\
} while (0)

#define BBUF_WRITE(buf,pos,bytes,n) do{\
  int used = (pos) + (int )(n);\
  if ((buf)->alloc < (unsigned int )used) BBUF_EXPAND((buf),used);\
  xmemcpy((buf)->p + (pos), (bytes), (n));\
  if ((buf)->used < (unsigned int )used) (buf)->used = used;\
} while (0)

#define BBUF_WRITE1(buf,pos,byte) do{\
  int used = (pos) + 1;\
  if ((buf)->alloc < (unsigned int )used) BBUF_EXPAND((buf),used);\
  (buf)->p[(pos)] = (UChar )(byte);\
  if ((buf)->used < (unsigned int )used) (buf)->used = used;\
} while (0)

#define BBUF_ADD(buf,bytes,n)       BBUF_WRITE((buf),(buf)->used,(bytes),(n))
#define BBUF_ADD1(buf,byte)         BBUF_WRITE1((buf),(buf)->used,(byte))
#define BBUF_GET_ADD_ADDRESS(buf)   ((buf)->p + (buf)->used)
#define BBUF_GET_OFFSET_POS(buf)    ((buf)->used)

/* from < to */
#define BBUF_MOVE_RIGHT(buf,from,to,n) do {\
  if ((unsigned int )((to)+(n)) > (buf)->alloc) BBUF_EXPAND((buf),(to) + (n));\
  xmemmove((buf)->p + (to), (buf)->p + (from), (n));\
  if ((unsigned int )((to)+(n)) > (buf)->used) (buf)->used = (to) + (n);\
} while (0)

/* from > to */
#define BBUF_MOVE_LEFT(buf,from,to,n) do {\
  xmemmove((buf)->p + (to), (buf)->p + (from), (n));\
} while (0)

/* from > to */
#define BBUF_MOVE_LEFT_REDUCE(buf,from,to) do {\
  xmemmove((buf)->p + (to), (buf)->p + (from), (buf)->used - (from));\
  (buf)->used -= (from - to);\
} while (0)

#define BBUF_INSERT(buf,pos,bytes,n) do {\
  if (pos >= (buf)->used) {\
    BBUF_WRITE(buf,pos,bytes,n);\
  }\
  else {\
    BBUF_MOVE_RIGHT((buf),(pos),(pos) + (n),((buf)->used - (pos)));\
    xmemcpy((buf)->p + (pos), (bytes), (n));\
  }\
} while (0)

#define BBUF_GET_BYTE(buf, pos) (buf)->p[(pos)]


#define ANCHOR_BEGIN_BUF        (1<<0)
#define ANCHOR_BEGIN_LINE       (1<<1)
#define ANCHOR_BEGIN_POSITION   (1<<2)
#define ANCHOR_END_BUF          (1<<3)
#define ANCHOR_SEMI_END_BUF     (1<<4)
#define ANCHOR_END_LINE         (1<<5)

#define ANCHOR_WORD_BOUND       (1<<6)
#define ANCHOR_NOT_WORD_BOUND   (1<<7)
#define ANCHOR_WORD_BEGIN       (1<<8)
#define ANCHOR_WORD_END         (1<<9)
#define ANCHOR_PREC_READ        (1<<10)
#define ANCHOR_PREC_READ_NOT    (1<<11)
#define ANCHOR_LOOK_BEHIND      (1<<12)
#define ANCHOR_LOOK_BEHIND_NOT  (1<<13)

#define ANCHOR_ANYCHAR_STAR     (1<<14)   /* ".*" optimize info */
#define ANCHOR_ANYCHAR_STAR_ML  (1<<15)   /* ".*" optimize info (multi-line) */

#define ANCHOR_KEEP             (1<<16)

/* operation code */
enum OpCode {
  OP_FINISH = 0,        /* matching process terminator (no more alternative) */
  OP_END    = 1,        /* pattern code terminator (success end) */

  OP_EXACT1 = 2,        /* single byte, N = 1 */
  OP_EXACT2,            /* single byte, N = 2 */
  OP_EXACT3,            /* single byte, N = 3 */
  OP_EXACT4,            /* single byte, N = 4 */
  OP_EXACT5,            /* single byte, N = 5 */
  OP_EXACTN,            /* single byte */
  OP_EXACTMB2N1,        /* mb-length = 2 N = 1 */
  OP_EXACTMB2N2,        /* mb-length = 2 N = 2 */
  OP_EXACTMB2N3,        /* mb-length = 2 N = 3 */
  OP_EXACTMB2N,         /* mb-length = 2 */
  OP_EXACTMB3N,         /* mb-length = 3 */
  OP_EXACTMBN,          /* other length */

  OP_EXACT1_IC,         /* single byte, N = 1, ignore case */
  OP_EXACTN_IC,         /* single byte,        ignore case */

  OP_CCLASS,
  OP_CCLASS_MB,
  OP_CCLASS_MIX,
  OP_CCLASS_NOT,
  OP_CCLASS_MB_NOT,
  OP_CCLASS_MIX_NOT,

  OP_ANYCHAR,                 /* "."  */
  OP_ANYCHAR_ML,              /* "."  multi-line */
  OP_ANYCHAR_STAR,            /* ".*" */
  OP_ANYCHAR_ML_STAR,         /* ".*" multi-line */
  OP_ANYCHAR_STAR_PEEK_NEXT,
  OP_ANYCHAR_ML_STAR_PEEK_NEXT,

  OP_WORD,
  OP_NOT_WORD,
  OP_WORD_BOUND,
  OP_NOT_WORD_BOUND,
  OP_WORD_BEGIN,
  OP_WORD_END,

  OP_ASCII_WORD,
  OP_NOT_ASCII_WORD,
  OP_ASCII_WORD_BOUND,
  OP_NOT_ASCII_WORD_BOUND,
  OP_ASCII_WORD_BEGIN,
  OP_ASCII_WORD_END,

  OP_BEGIN_BUF,
  OP_END_BUF,
  OP_BEGIN_LINE,
  OP_END_LINE,
  OP_SEMI_END_BUF,
  OP_BEGIN_POSITION,

  OP_BACKREF1,
  OP_BACKREF2,
  OP_BACKREFN,
  OP_BACKREFN_IC,
  OP_BACKREF_MULTI,
  OP_BACKREF_MULTI_IC,
  OP_BACKREF_WITH_LEVEL,    /* \k<xxx+n>, \k<xxx-n> */

  OP_MEMORY_START,
  OP_MEMORY_START_PUSH,   /* push back-tracker to stack */
  OP_MEMORY_END_PUSH,     /* push back-tracker to stack */
  OP_MEMORY_END_PUSH_REC, /* push back-tracker to stack */
  OP_MEMORY_END,
  OP_MEMORY_END_REC,      /* push marker to stack */

  OP_KEEP,

  OP_FAIL,               /* pop stack and move */
  OP_JUMP,
  OP_PUSH,
  OP_POP,
  OP_PUSH_OR_JUMP_EXACT1,  /* if match exact then push, else jump. */
  OP_PUSH_IF_PEEK_NEXT,    /* if match exact then push, else none. */
  OP_REPEAT,               /* {n,m} */
  OP_REPEAT_NG,            /* {n,m}? (non greedy) */
  OP_REPEAT_INC,
  OP_REPEAT_INC_NG,        /* non greedy */
  OP_REPEAT_INC_SG,        /* search and get in stack */
  OP_REPEAT_INC_NG_SG,     /* search and get in stack (non greedy) */
  OP_NULL_CHECK_START,     /* null loop checker start */
  OP_NULL_CHECK_END,       /* null loop checker end   */
  OP_NULL_CHECK_END_MEMST, /* null loop checker end (with capture status) */
  OP_NULL_CHECK_END_MEMST_PUSH, /* with capture status and push check-end */

  OP_PUSH_POS,             /* (?=...)  start */
  OP_POP_POS,              /* (?=...)  end   */
  OP_PUSH_POS_NOT,         /* (?!...)  start */
  OP_FAIL_POS,             /* (?!...)  end   */
  OP_PUSH_STOP_BT,         /* (?>...)  start */
  OP_POP_STOP_BT,          /* (?>...)  end   */
  OP_LOOK_BEHIND,          /* (?<=...) start (no needs end opcode) */
  OP_PUSH_LOOK_BEHIND_NOT, /* (?<!...) start */
  OP_FAIL_LOOK_BEHIND_NOT, /* (?<!...) end   */
  OP_PUSH_ABSENT_POS,      /* (?~...)  start */
  OP_ABSENT,               /* (?~...)  start of inner loop */
  OP_ABSENT_END,           /* (?~...)  end   */

  OP_CALL,                 /* \g<name> */
  OP_RETURN,

  OP_CONDITION,

  OP_STATE_CHECK_PUSH,         /* combination explosion check and push */
  OP_STATE_CHECK_PUSH_OR_JUMP, /* check ok -> push, else jump  */
  OP_STATE_CHECK,              /* check only */
  OP_STATE_CHECK_ANYCHAR_STAR,
  OP_STATE_CHECK_ANYCHAR_ML_STAR,

  /* no need: IS_DYNAMIC_OPTION() == 0 */
  OP_SET_OPTION_PUSH,    /* set option and push recover option */
  OP_SET_OPTION          /* set option */
};

typedef int RelAddrType;
typedef int AbsAddrType;
typedef int LengthType;
typedef int RepeatNumType;
typedef short int MemNumType;
typedef short int StateCheckNumType;
typedef void* PointerType;

#define SIZE_OPCODE           1
#define SIZE_RELADDR          (int )sizeof(RelAddrType)
#define SIZE_ABSADDR          (int )sizeof(AbsAddrType)
#define SIZE_LENGTH           (int )sizeof(LengthType)
#define SIZE_MEMNUM           (int )sizeof(MemNumType)
#define SIZE_STATE_CHECK_NUM  (int )sizeof(StateCheckNumType)
#define SIZE_REPEATNUM        (int )sizeof(RepeatNumType)
#define SIZE_OPTION           (int )sizeof(OnigOptionType)
#define SIZE_CODE_POINT       (int )sizeof(OnigCodePoint)
#define SIZE_POINTER          (int )sizeof(PointerType)


#define GET_RELADDR_INC(addr,p)    PLATFORM_GET_INC(addr,   p, RelAddrType)
#define GET_ABSADDR_INC(addr,p)    PLATFORM_GET_INC(addr,   p, AbsAddrType)
#define GET_LENGTH_INC(len,p)      PLATFORM_GET_INC(len,    p, LengthType)
#define GET_MEMNUM_INC(num,p)      PLATFORM_GET_INC(num,    p, MemNumType)
#define GET_REPEATNUM_INC(num,p)   PLATFORM_GET_INC(num,    p, RepeatNumType)
#define GET_OPTION_INC(option,p)   PLATFORM_GET_INC(option, p, OnigOptionType)
#define GET_POINTER_INC(ptr,p)     PLATFORM_GET_INC(ptr,    p, PointerType)
#define GET_STATE_CHECK_NUM_INC(num,p)  PLATFORM_GET_INC(num, p, StateCheckNumType)

/* code point's address must be aligned address. */
#define GET_CODE_POINT(code,p)   code = *((OnigCodePoint* )(p))
#define GET_BYTE_INC(byte,p) do{\
  byte = *(p);\
  (p)++;\
} while(0)


/* op-code + arg size */
#define SIZE_OP_ANYCHAR_STAR            SIZE_OPCODE
#define SIZE_OP_ANYCHAR_STAR_PEEK_NEXT (SIZE_OPCODE + 1)
#define SIZE_OP_JUMP                   (SIZE_OPCODE + SIZE_RELADDR)
#define SIZE_OP_PUSH                   (SIZE_OPCODE + SIZE_RELADDR)
#define SIZE_OP_POP                     SIZE_OPCODE
#define SIZE_OP_PUSH_OR_JUMP_EXACT1    (SIZE_OPCODE + SIZE_RELADDR + 1)
#define SIZE_OP_PUSH_IF_PEEK_NEXT      (SIZE_OPCODE + SIZE_RELADDR + 1)
#define SIZE_OP_REPEAT_INC             (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_REPEAT_INC_NG          (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_PUSH_POS                SIZE_OPCODE
#define SIZE_OP_PUSH_POS_NOT           (SIZE_OPCODE + SIZE_RELADDR)
#define SIZE_OP_POP_POS                 SIZE_OPCODE
#define SIZE_OP_FAIL_POS                SIZE_OPCODE
#define SIZE_OP_SET_OPTION             (SIZE_OPCODE + SIZE_OPTION)
#define SIZE_OP_SET_OPTION_PUSH        (SIZE_OPCODE + SIZE_OPTION)
#define SIZE_OP_FAIL                    SIZE_OPCODE
#define SIZE_OP_MEMORY_START           (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_MEMORY_START_PUSH      (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_MEMORY_END_PUSH        (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_MEMORY_END_PUSH_REC    (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_MEMORY_END             (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_MEMORY_END_REC         (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_PUSH_STOP_BT            SIZE_OPCODE
#define SIZE_OP_POP_STOP_BT             SIZE_OPCODE
#define SIZE_OP_NULL_CHECK_START       (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_NULL_CHECK_END         (SIZE_OPCODE + SIZE_MEMNUM)
#define SIZE_OP_LOOK_BEHIND            (SIZE_OPCODE + SIZE_LENGTH)
#define SIZE_OP_PUSH_LOOK_BEHIND_NOT   (SIZE_OPCODE + SIZE_RELADDR + SIZE_LENGTH)
#define SIZE_OP_FAIL_LOOK_BEHIND_NOT    SIZE_OPCODE
#define SIZE_OP_CALL                   (SIZE_OPCODE + SIZE_ABSADDR)
#define SIZE_OP_RETURN                  SIZE_OPCODE
#define SIZE_OP_CONDITION              (SIZE_OPCODE + SIZE_MEMNUM + SIZE_RELADDR)
#define SIZE_OP_PUSH_ABSENT_POS         SIZE_OPCODE
#define SIZE_OP_ABSENT                 (SIZE_OPCODE + SIZE_RELADDR)
#define SIZE_OP_ABSENT_END              SIZE_OPCODE

#ifdef USE_COMBINATION_EXPLOSION_CHECK
# define SIZE_OP_STATE_CHECK           (SIZE_OPCODE + SIZE_STATE_CHECK_NUM)
# define SIZE_OP_STATE_CHECK_PUSH      (SIZE_OPCODE + SIZE_STATE_CHECK_NUM + SIZE_RELADDR)
# define SIZE_OP_STATE_CHECK_PUSH_OR_JUMP (SIZE_OPCODE + SIZE_STATE_CHECK_NUM + SIZE_RELADDR)
# define SIZE_OP_STATE_CHECK_ANYCHAR_STAR (SIZE_OPCODE + SIZE_STATE_CHECK_NUM)
#endif

#define MC_ESC(syn)               (syn)->meta_char_table.esc
#define MC_ANYCHAR(syn)           (syn)->meta_char_table.anychar
#define MC_ANYTIME(syn)           (syn)->meta_char_table.anytime
#define MC_ZERO_OR_ONE_TIME(syn)  (syn)->meta_char_table.zero_or_one_time
#define MC_ONE_OR_MORE_TIME(syn)  (syn)->meta_char_table.one_or_more_time
#define MC_ANYCHAR_ANYTIME(syn)   (syn)->meta_char_table.anychar_anytime

#define IS_MC_ESC_CODE(code, syn) \
  ((code) == MC_ESC(syn) && \
   !IS_SYNTAX_OP2((syn), ONIG_SYN_OP2_INEFFECTIVE_ESCAPE))


#define SYN_POSIX_COMMON_OP \
 ( ONIG_SYN_OP_DOT_ANYCHAR | ONIG_SYN_OP_POSIX_BRACKET | \
   ONIG_SYN_OP_DECIMAL_BACKREF | \
   ONIG_SYN_OP_BRACKET_CC | ONIG_SYN_OP_ASTERISK_ZERO_INF | \
   ONIG_SYN_OP_LINE_ANCHOR | \
   ONIG_SYN_OP_ESC_CONTROL_CHARS )

#define SYN_GNU_REGEX_OP \
  ( ONIG_SYN_OP_DOT_ANYCHAR | ONIG_SYN_OP_BRACKET_CC | \
    ONIG_SYN_OP_POSIX_BRACKET | ONIG_SYN_OP_DECIMAL_BACKREF | \
    ONIG_SYN_OP_BRACE_INTERVAL | ONIG_SYN_OP_LPAREN_SUBEXP | \
    ONIG_SYN_OP_VBAR_ALT | \
    ONIG_SYN_OP_ASTERISK_ZERO_INF | ONIG_SYN_OP_PLUS_ONE_INF | \
    ONIG_SYN_OP_QMARK_ZERO_ONE | \
    ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR | ONIG_SYN_OP_ESC_CAPITAL_G_BEGIN_ANCHOR | \
    ONIG_SYN_OP_ESC_W_WORD | \
    ONIG_SYN_OP_ESC_B_WORD_BOUND | ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END | \
    ONIG_SYN_OP_ESC_S_WHITE_SPACE | ONIG_SYN_OP_ESC_D_DIGIT | \
    ONIG_SYN_OP_LINE_ANCHOR )

#define SYN_GNU_REGEX_BV \
  ( ONIG_SYN_CONTEXT_INDEP_ANCHORS | ONIG_SYN_CONTEXT_INDEP_REPEAT_OPS | \
    ONIG_SYN_CONTEXT_INVALID_REPEAT_OPS | ONIG_SYN_ALLOW_INVALID_INTERVAL | \
    ONIG_SYN_BACKSLASH_ESCAPE_IN_CC | ONIG_SYN_ALLOW_DOUBLE_RANGE_OP_IN_CC )


#define NCCLASS_FLAGS(cc)           ((cc)->flags)
#define NCCLASS_FLAG_SET(cc,flag)    (NCCLASS_FLAGS(cc) |= (flag))
#define NCCLASS_FLAG_CLEAR(cc,flag)  (NCCLASS_FLAGS(cc) &= ~(flag))
#define IS_NCCLASS_FLAG_ON(cc,flag) ((NCCLASS_FLAGS(cc) & (flag)) != 0)

/* cclass node */
#define FLAG_NCCLASS_NOT           (1<<0)

#define NCCLASS_SET_NOT(nd)     NCCLASS_FLAG_SET(nd, FLAG_NCCLASS_NOT)
#define NCCLASS_CLEAR_NOT(nd)   NCCLASS_FLAG_CLEAR(nd, FLAG_NCCLASS_NOT)
#define IS_NCCLASS_NOT(nd)      IS_NCCLASS_FLAG_ON(nd, FLAG_NCCLASS_NOT)

typedef struct {
  int type;
  /* struct _Node* next; */
  /* unsigned int flags; */
} NodeBase;

typedef struct {
  NodeBase base;
  unsigned int flags;
  BitSet bs;
  BBuf*  mbuf;   /* multi-byte info or NULL */
} CClassNode;

typedef intptr_t OnigStackIndex;

typedef struct _OnigStackType {
  unsigned int type;
  OnigStackIndex null_check;
  union {
    struct {
      UChar *pcode;      /* byte code position */
      UChar *pstr;       /* string position */
      UChar *pstr_prev;  /* previous char position of pstr */
#ifdef USE_COMBINATION_EXPLOSION_CHECK
      unsigned int state_check;
#endif
      UChar *pkeep;      /* keep pattern position */
    } state;
    struct {
      int   count;       /* for OP_REPEAT_INC, OP_REPEAT_INC_NG */
      UChar *pcode;      /* byte code position (head of repeated target) */
      int   num;         /* repeat id */
    } repeat;
    struct {
      OnigStackIndex si;     /* index of stack */
    } repeat_inc;
    struct {
      int num;           /* memory num */
      UChar *pstr;       /* start/end position */
      /* Following information is set, if this stack type is MEM-START */
      OnigStackIndex start;  /* prev. info (for backtrack  "(...)*" ) */
      OnigStackIndex end;    /* prev. info (for backtrack  "(...)*" ) */
    } mem;
    struct {
      int num;           /* null check id */
      UChar *pstr;       /* start position */
    } null_check;
#ifdef USE_SUBEXP_CALL
    struct {
      UChar *ret_addr;   /* byte code position */
      int    num;        /* null check id */
      UChar *pstr;       /* string position */
    } call_frame;
#endif
    struct {
      UChar *abs_pstr;        /* absent start position */
      const UChar *end_pstr;  /* end position */
    } absent_pos;
#ifdef USE_MATCH_CACHE
    struct {
      long    index;      /* index of the match cache buffer */
      uint8_t mask;       /* bit-mask for the match cache buffer */
    } match_cache_point;
#endif
  } u;
} OnigStackType;

#ifdef USE_MATCH_CACHE
typedef struct {
  UChar *addr;
  long cache_point;
  int outer_repeat_mem;
  long num_cache_points_at_outer_repeat;
  long num_cache_points_in_outer_repeat;
  int lookaround_nesting;
  UChar *match_addr;
} OnigCacheOpcode;
#endif

typedef struct {
  void* stack_p;
  size_t stack_n;
  OnigOptionType options;
  OnigRegion*    region;
  const UChar* start;   /* search start position */
  const UChar* gpos;    /* global position (for \G: BEGIN_POSITION) */
#ifdef USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE
  OnigPosition best_len;  /* for ONIG_OPTION_FIND_LONGEST */
  UChar* best_s;
#endif
#ifdef USE_COMBINATION_EXPLOSION_CHECK
  void* state_check_buff;
  int   state_check_buff_size;
#endif
  int counter;
  /* rb_hrtime_t from hrtime.h */
#ifdef MY_RUBY_BUILD_MAY_TIME_TRAVEL
  int128_t end_time;
#else
  uint64_t end_time;
#endif
#ifdef USE_MATCH_CACHE
  int              match_cache_status;
  long             num_fails;
  long             num_cache_opcodes;
  OnigCacheOpcode* cache_opcodes;
  long             num_cache_points;
  uint8_t*         match_cache_buf;
#endif
} OnigMatchArg;

#define NUM_CACHE_OPCODES_UNINIT      1
#define NUM_CACHE_OPCODES_IMPOSSIBLE -1

#define MATCH_CACHE_STATUS_UNINIT    1
#define MATCH_CACHE_STATUS_INIT      2
#define MATCH_CACHE_STATUS_DISABLED -1
#define MATCH_CACHE_STATUS_ENABLED   0

#define IS_CODE_SB_WORD(enc,code) \
  (ONIGENC_IS_CODE_ASCII(code) && ONIGENC_IS_CODE_WORD(enc,code))

typedef struct OnigEndCallListItem {
  struct OnigEndCallListItem* next;
  void (*func)(void);
} OnigEndCallListItemType;

extern void onig_add_end_call(void (*func)(void));


#ifdef ONIG_DEBUG

typedef struct {
  short int opcode;
  const char* name;
  short int arg_type;
} OnigOpInfoType;

extern OnigOpInfoType OnigOpInfo[];


extern void onig_print_compiled_byte_code(FILE* f, UChar* bp, UChar* bpend, UChar** nextp, OnigEncoding enc);

# ifdef ONIG_DEBUG_STATISTICS
extern void onig_statistics_init(void);
extern void onig_print_statistics(FILE* f);
# endif
#endif

#ifndef PRINTF_ARGS
#define PRINTF_ARGS(func, fmt, vargs) func
#endif

extern UChar* onig_error_code_to_format(OnigPosition code);
PRINTF_ARGS(extern void onig_vsnprintf_with_pattern(UChar buf[], int bufsize, OnigEncoding enc, UChar* pat, UChar* pat_end, const char *fmt, va_list args), 6, 0);
PRINTF_ARGS(extern void onig_snprintf_with_pattern(UChar buf[], int bufsize, OnigEncoding enc, UChar* pat, UChar* pat_end, const char *fmt, ...), 6, 7);
extern int  onig_bbuf_init(BBuf* buf, OnigDistance size);
extern int  onig_compile(regex_t* reg, const UChar* pattern, const UChar* pattern_end, OnigErrorInfo* einfo);
#ifdef RUBY
extern int  onig_compile_ruby(regex_t* reg, const UChar* pattern, const UChar* pattern_end, OnigErrorInfo* einfo, const char *sourcefile, int sourceline);
#endif
extern void onig_transfer(regex_t* to, regex_t* from);
extern int  onig_is_code_in_cc(OnigEncoding enc, OnigCodePoint code, CClassNode* cc);
extern int  onig_is_code_in_cc_len(int enclen, OnigCodePoint code, CClassNode* cc);

/* strend hash */
typedef void hash_table_type;
#ifdef RUBY
# include "ruby/st.h"
#else
# include "st.h"
#endif
typedef st_data_t hash_data_type;

extern hash_table_type* onig_st_init_strend_table_with_size(st_index_t size);
extern int onig_st_lookup_strend(hash_table_type* table, const UChar* str_key, const UChar* end_key, hash_data_type *value);
extern int onig_st_insert_strend(hash_table_type* table, const UChar* str_key, const UChar* end_key, hash_data_type value);

#ifdef RUBY
extern size_t onig_memsize(const regex_t *reg);
extern size_t onig_region_memsize(const struct re_registers *regs);
void rb_reg_check_timeout(regex_t *reg, void *end_time);
#endif

RUBY_SYMBOL_EXPORT_END

#endif /* ONIGMO_REGINT_H */
