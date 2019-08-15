/**********************************************************************
  regparse.c -  Onigmo (Oniguruma-mod) (regular expression library)
**********************************************************************/
/*-
 * Copyright (c) 2002-2008  K.Kosako  <sndgk393 AT ybb DOT ne DOT jp>
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

#include "regparse.h"
#include <stdarg.h>

#define WARN_BUFSIZE    256

#define CASE_FOLD_IS_APPLIED_INSIDE_NEGATIVE_CCLASS


const OnigSyntaxType OnigSyntaxRuby = {
  (( SYN_GNU_REGEX_OP | ONIG_SYN_OP_QMARK_NON_GREEDY |
     ONIG_SYN_OP_ESC_OCTAL3 | ONIG_SYN_OP_ESC_X_HEX2 |
     ONIG_SYN_OP_ESC_X_BRACE_HEX8 | ONIG_SYN_OP_ESC_CONTROL_CHARS |
     ONIG_SYN_OP_ESC_C_CONTROL )
   & ~ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END )
  , ( ONIG_SYN_OP2_QMARK_GROUP_EFFECT |
      ONIG_SYN_OP2_OPTION_RUBY |
      ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP | ONIG_SYN_OP2_ESC_K_NAMED_BACKREF |
      ONIG_SYN_OP2_ESC_G_SUBEXP_CALL |
      ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY  |
      ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT |
      ONIG_SYN_OP2_PLUS_POSSESSIVE_REPEAT |
      ONIG_SYN_OP2_CCLASS_SET_OP | ONIG_SYN_OP2_ESC_CAPITAL_C_BAR_CONTROL |
      ONIG_SYN_OP2_ESC_CAPITAL_M_BAR_META | ONIG_SYN_OP2_ESC_V_VTAB |
      ONIG_SYN_OP2_ESC_H_XDIGIT |
#ifndef RUBY
      ONIG_SYN_OP2_ESC_U_HEX4 |
#endif
      ONIG_SYN_OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER |
      ONIG_SYN_OP2_QMARK_LPAREN_CONDITION |
      ONIG_SYN_OP2_ESC_CAPITAL_R_LINEBREAK |
      ONIG_SYN_OP2_ESC_CAPITAL_K_KEEP |
      ONIG_SYN_OP2_QMARK_TILDE_ABSENT )
  , ( SYN_GNU_REGEX_BV |
      ONIG_SYN_ALLOW_INTERVAL_LOW_ABBREV |
      ONIG_SYN_DIFFERENT_LEN_ALT_LOOK_BEHIND |
      ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP |
      ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME |
      ONIG_SYN_FIXED_INTERVAL_IS_GREEDY_ONLY |
      ONIG_SYN_WARN_CC_OP_NOT_ESCAPED |
      ONIG_SYN_WARN_CC_DUP |
      ONIG_SYN_WARN_REDUNDANT_NESTED_REPEAT )
  , ( ONIG_OPTION_ASCII_RANGE | ONIG_OPTION_POSIX_BRACKET_ALL_RANGE |
      ONIG_OPTION_WORD_BOUND_ALL_RANGE )
  ,
  {
      (OnigCodePoint )'\\'                       /* esc */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* anychar '.'  */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* anytime '*'  */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* zero or one time '?' */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* one or more time '+' */
    , (OnigCodePoint )ONIG_INEFFECTIVE_META_CHAR /* anychar anytime */
  }
};

const OnigSyntaxType*  OnigDefaultSyntax = ONIG_SYNTAX_RUBY;

extern void onig_null_warn(const char* s ARG_UNUSED) { }

#ifdef DEFAULT_WARN_FUNCTION
static OnigWarnFunc onig_warn = (OnigWarnFunc )DEFAULT_WARN_FUNCTION;
#else
static OnigWarnFunc onig_warn = onig_null_warn;
#endif

#ifdef DEFAULT_VERB_WARN_FUNCTION
static OnigWarnFunc onig_verb_warn = (OnigWarnFunc )DEFAULT_VERB_WARN_FUNCTION;
#else
static OnigWarnFunc onig_verb_warn = onig_null_warn;
#endif

extern void onig_set_warn_func(OnigWarnFunc f)
{
  onig_warn = f;
}

extern void onig_set_verb_warn_func(OnigWarnFunc f)
{
  onig_verb_warn = f;
}

static void CC_DUP_WARN(ScanEnv *env, OnigCodePoint from, OnigCodePoint to);


static unsigned int ParseDepthLimit = DEFAULT_PARSE_DEPTH_LIMIT;

extern unsigned int
onig_get_parse_depth_limit(void)
{
  return ParseDepthLimit;
}

extern int
onig_set_parse_depth_limit(unsigned int depth)
{
  if (depth == 0)
    ParseDepthLimit = DEFAULT_PARSE_DEPTH_LIMIT;
  else
    ParseDepthLimit = depth;
  return 0;
}


static void
bbuf_free(BBuf* bbuf)
{
  if (IS_NOT_NULL(bbuf)) {
    if (IS_NOT_NULL(bbuf->p)) xfree(bbuf->p);
    xfree(bbuf);
  }
}

static int
bbuf_clone(BBuf** rto, BBuf* from)
{
  int r;
  BBuf *to;

  *rto = to = (BBuf* )xmalloc(sizeof(BBuf));
  CHECK_NULL_RETURN_MEMERR(to);
  r = BBUF_INIT(to, from->alloc);
  if (r != 0) return r;
  to->used = from->used;
  xmemcpy(to->p, from->p, from->used);
  return 0;
}

#define BACKREF_REL_TO_ABS(rel_no, env) \
  ((env)->num_mem + 1 + (rel_no))

#define ONOFF(v,f,negative)    (negative) ? ((v) &= ~(f)) : ((v) |= (f))

#define MBCODE_START_POS(enc) \
  (OnigCodePoint )(ONIGENC_MBC_MINLEN(enc) > 1 ? 0 : 0x80)

#define SET_ALL_MULTI_BYTE_RANGE(enc, pbuf) \
  add_code_range_to_buf(pbuf, env, MBCODE_START_POS(enc), ONIG_LAST_CODE_POINT)

#define ADD_ALL_MULTI_BYTE_RANGE(enc, mbuf) do {\
  if (! ONIGENC_IS_SINGLEBYTE(enc)) {\
    r = SET_ALL_MULTI_BYTE_RANGE(enc, &(mbuf));\
    if (r) return r;\
  }\
} while (0)


#define BITSET_SET_BIT_CHKDUP(bs, pos) do { \
  if (BITSET_AT(bs, pos)) CC_DUP_WARN(env, pos, pos); \
  BS_ROOM(bs, pos) |= BS_BIT(pos); \
} while (0)

#define BITSET_IS_EMPTY(bs,empty) do {\
  int i;\
  empty = 1;\
  for (i = 0; i < BITSET_SIZE; i++) {\
    if ((bs)[i] != 0) {\
      empty = 0; break;\
    }\
  }\
} while (0)

static void
bitset_set_range(ScanEnv *env, BitSetRef bs, int from, int to)
{
  int i;
  for (i = from; i <= to && i < SINGLE_BYTE_SIZE; i++) {
    BITSET_SET_BIT_CHKDUP(bs, i);
  }
}

#if 0
static void
bitset_set_all(BitSetRef bs)
{
  int i;
  for (i = 0; i < BITSET_SIZE; i++) { bs[i] = ~((Bits )0); }
}
#endif

static void
bitset_invert(BitSetRef bs)
{
  int i;
  for (i = 0; i < BITSET_SIZE; i++) { bs[i] = ~(bs[i]); }
}

static void
bitset_invert_to(BitSetRef from, BitSetRef to)
{
  int i;
  for (i = 0; i < BITSET_SIZE; i++) { to[i] = ~(from[i]); }
}

static void
bitset_and(BitSetRef dest, BitSetRef bs)
{
  int i;
  for (i = 0; i < BITSET_SIZE; i++) { dest[i] &= bs[i]; }
}

static void
bitset_or(BitSetRef dest, BitSetRef bs)
{
  int i;
  for (i = 0; i < BITSET_SIZE; i++) { dest[i] |= bs[i]; }
}

static void
bitset_copy(BitSetRef dest, BitSetRef bs)
{
  int i;
  for (i = 0; i < BITSET_SIZE; i++) { dest[i] = bs[i]; }
}

#if defined(USE_NAMED_GROUP) && !defined(USE_ST_LIBRARY)
extern int
onig_strncmp(const UChar* s1, const UChar* s2, int n)
{
  int x;

  while (n-- > 0) {
    x = *s2++ - *s1++;
    if (x) return x;
  }
  return 0;
}
#endif

extern void
onig_strcpy(UChar* dest, const UChar* src, const UChar* end)
{
  ptrdiff_t len = end - src;
  if (len > 0) {
    xmemcpy(dest, src, len);
    dest[len] = (UChar )0;
  }
}

#ifdef USE_NAMED_GROUP
static UChar*
strdup_with_null(OnigEncoding enc, UChar* s, UChar* end)
{
  ptrdiff_t slen;
  int term_len, i;
  UChar *r;

  slen = end - s;
  term_len = ONIGENC_MBC_MINLEN(enc);

  r = (UChar* )xmalloc(slen + term_len);
  CHECK_NULL_RETURN(r);
  xmemcpy(r, s, slen);

  for (i = 0; i < term_len; i++)
    r[slen + i] = (UChar )0;

  return r;
}
#endif

/* scan pattern methods */
#define PEND_VALUE   0

#ifdef __GNUC__
/* get rid of Wunused-but-set-variable and Wuninitialized */
# define PFETCH_READY  UChar* pfetch_prev = NULL; (void)pfetch_prev
#else
# define PFETCH_READY  UChar* pfetch_prev
#endif
#define PEND         (p < end ?  0 : 1)
#define PUNFETCH     p = pfetch_prev
#define PINC       do { \
  pfetch_prev = p; \
  p += enclen(enc, p, end); \
} while (0)
#define PFETCH(c)  do { \
  c = ((enc->max_enc_len == 1) ? *p : ONIGENC_MBC_TO_CODE(enc, p, end)); \
  pfetch_prev = p; \
  p += enclen(enc, p, end); \
} while (0)

#define PINC_S     do { \
  p += enclen(enc, p, end); \
} while (0)
#define PFETCH_S(c) do { \
  c = ((enc->max_enc_len == 1) ? *p : ONIGENC_MBC_TO_CODE(enc, p, end)); \
  p += enclen(enc, p, end); \
} while (0)

#define PPEEK        (p < end ? ONIGENC_MBC_TO_CODE(enc, p, end) : PEND_VALUE)
#define PPEEK_IS(c)  (PPEEK == (OnigCodePoint )c)

static UChar*
strcat_capa(UChar* dest, UChar* dest_end, const UChar* src, const UChar* src_end,
	      size_t capa)
{
  UChar* r;

  if (dest)
    r = (UChar* )xrealloc(dest, capa + 1);
  else
    r = (UChar* )xmalloc(capa + 1);

  CHECK_NULL_RETURN(r);
  onig_strcpy(r + (dest_end - dest), src, src_end);
  return r;
}

/* dest on static area */
static UChar*
strcat_capa_from_static(UChar* dest, UChar* dest_end,
			const UChar* src, const UChar* src_end, size_t capa)
{
  UChar* r;

  r = (UChar* )xmalloc(capa + 1);
  CHECK_NULL_RETURN(r);
  onig_strcpy(r, dest, dest_end);
  onig_strcpy(r + (dest_end - dest), src, src_end);
  return r;
}


#ifdef USE_ST_LIBRARY

# ifdef RUBY
#  include "ruby/st.h"
# else
#  include "st.h"
# endif

typedef struct {
  const UChar* s;
  const UChar* end;
} st_str_end_key;

static int
str_end_cmp(st_data_t xp, st_data_t yp)
{
  const st_str_end_key *x, *y;
  const UChar *p, *q;
  int c;

  x = (const st_str_end_key *)xp;
  y = (const st_str_end_key *)yp;
  if ((x->end - x->s) != (y->end - y->s))
    return 1;

  p = x->s;
  q = y->s;
  while (p < x->end) {
    c = (int )*p - (int )*q;
    if (c != 0) return c;

    p++; q++;
  }

  return 0;
}

static st_index_t
str_end_hash(st_data_t xp)
{
  const st_str_end_key *x = (const st_str_end_key *)xp;
  const UChar *p;
  st_index_t val = 0;

  p = x->s;
  while (p < x->end) {
    val = val * 997 + (int )*p++;
  }

  return val + (val >> 5);
}

extern hash_table_type*
onig_st_init_strend_table_with_size(st_index_t size)
{
  static const struct st_hash_type hashType = {
    str_end_cmp,
    str_end_hash,
  };

  return (hash_table_type* )
           onig_st_init_table_with_size(&hashType, size);
}

extern int
onig_st_lookup_strend(hash_table_type* table, const UChar* str_key,
		      const UChar* end_key, hash_data_type *value)
{
  st_str_end_key key;

  key.s   = (UChar* )str_key;
  key.end = (UChar* )end_key;

  return onig_st_lookup(table, (st_data_t )(&key), value);
}

extern int
onig_st_insert_strend(hash_table_type* table, const UChar* str_key,
		      const UChar* end_key, hash_data_type value)
{
  st_str_end_key* key;
  int result;

  key = (st_str_end_key* )xmalloc(sizeof(st_str_end_key));
  key->s   = (UChar* )str_key;
  key->end = (UChar* )end_key;
  result = onig_st_insert(table, (st_data_t )key, value);
  if (result) {
    xfree(key);
  }
  return result;
}

#endif /* USE_ST_LIBRARY */


#ifdef USE_NAMED_GROUP

# define INIT_NAME_BACKREFS_ALLOC_NUM   8

typedef struct {
  UChar* name;
  size_t name_len;   /* byte length */
  int    back_num;   /* number of backrefs */
  int    back_alloc;
  int    back_ref1;
  int*   back_refs;
} NameEntry;

# ifdef USE_ST_LIBRARY

typedef st_table  NameTable;
typedef st_data_t HashDataType;   /* 1.6 st.h doesn't define st_data_t type */

#  ifdef ONIG_DEBUG
static int
i_print_name_entry(UChar* key, NameEntry* e, void* arg)
{
  int i;
  FILE* fp = (FILE* )arg;

  fprintf(fp, "%s: ", e->name);
  if (e->back_num == 0)
    fputs("-", fp);
  else if (e->back_num == 1)
    fprintf(fp, "%d", e->back_ref1);
  else {
    for (i = 0; i < e->back_num; i++) {
      if (i > 0) fprintf(fp, ", ");
      fprintf(fp, "%d", e->back_refs[i]);
    }
  }
  fputs("\n", fp);
  return ST_CONTINUE;
}

extern int
onig_print_names(FILE* fp, regex_t* reg)
{
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t)) {
    fprintf(fp, "name table\n");
    onig_st_foreach(t, i_print_name_entry, (HashDataType )fp);
    fputs("\n", fp);
  }
  return 0;
}
#  endif /* ONIG_DEBUG */

static int
i_free_name_entry(UChar* key, NameEntry* e, void* arg ARG_UNUSED)
{
  xfree(e->name);
  if (IS_NOT_NULL(e->back_refs)) xfree(e->back_refs);
  xfree(key);
  xfree(e);
  return ST_DELETE;
}

static int
names_clear(regex_t* reg)
{
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t)) {
    onig_st_foreach(t, i_free_name_entry, 0);
  }
  return 0;
}

extern int
onig_names_free(regex_t* reg)
{
  int r;
  NameTable* t;

  r = names_clear(reg);
  if (r) return r;

  t = (NameTable* )reg->name_table;
  if (IS_NOT_NULL(t)) onig_st_free_table(t);
  reg->name_table = (void* )NULL;
  return 0;
}

static NameEntry*
name_find(regex_t* reg, const UChar* name, const UChar* name_end)
{
  NameEntry* e;
  NameTable* t = (NameTable* )reg->name_table;

  e = (NameEntry* )NULL;
  if (IS_NOT_NULL(t)) {
    onig_st_lookup_strend(t, name, name_end, (HashDataType* )((void* )(&e)));
  }
  return e;
}

typedef struct {
  int (*func)(const UChar*, const UChar*,int,int*,regex_t*,void*);
  regex_t* reg;
  void* arg;
  int ret;
  OnigEncoding enc;
} INamesArg;

static int
i_names(UChar* key ARG_UNUSED, NameEntry* e, INamesArg* arg)
{
  int r = (*(arg->func))(e->name,
			 e->name + e->name_len,
			 e->back_num,
			 (e->back_num > 1 ? e->back_refs : &(e->back_ref1)),
			 arg->reg, arg->arg);
  if (r != 0) {
    arg->ret = r;
    return ST_STOP;
  }
  return ST_CONTINUE;
}

extern int
onig_foreach_name(regex_t* reg,
  int (*func)(const UChar*, const UChar*,int,int*,regex_t*,void*), void* arg)
{
  INamesArg narg;
  NameTable* t = (NameTable* )reg->name_table;

  narg.ret = 0;
  if (IS_NOT_NULL(t)) {
    narg.func = func;
    narg.reg  = reg;
    narg.arg  = arg;
    narg.enc  = reg->enc; /* should be pattern encoding. */
    onig_st_foreach(t, i_names, (HashDataType )&narg);
  }
  return narg.ret;
}

static int
i_renumber_name(UChar* key ARG_UNUSED, NameEntry* e, GroupNumRemap* map)
{
  int i;

  if (e->back_num > 1) {
    for (i = 0; i < e->back_num; i++) {
      e->back_refs[i] = map[e->back_refs[i]].new_val;
    }
  }
  else if (e->back_num == 1) {
    e->back_ref1 = map[e->back_ref1].new_val;
  }

  return ST_CONTINUE;
}

extern int
onig_renumber_name_table(regex_t* reg, GroupNumRemap* map)
{
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t)) {
    onig_st_foreach(t, i_renumber_name, (HashDataType )map);
  }
  return 0;
}


extern int
onig_number_of_names(const regex_t* reg)
{
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t))
    return (int )t->num_entries;
  else
    return 0;
}

# else  /* USE_ST_LIBRARY */

#  define INIT_NAMES_ALLOC_NUM    8

typedef struct {
  NameEntry* e;
  int        num;
  int        alloc;
} NameTable;

#  ifdef ONIG_DEBUG
extern int
onig_print_names(FILE* fp, regex_t* reg)
{
  int i, j;
  NameEntry* e;
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t) && t->num > 0) {
    fprintf(fp, "name table\n");
    for (i = 0; i < t->num; i++) {
      e = &(t->e[i]);
      fprintf(fp, "%s: ", e->name);
      if (e->back_num == 0) {
	fputs("-", fp);
      }
      else if (e->back_num == 1) {
	fprintf(fp, "%d", e->back_ref1);
      }
      else {
	for (j = 0; j < e->back_num; j++) {
	  if (j > 0) fprintf(fp, ", ");
	  fprintf(fp, "%d", e->back_refs[j]);
	}
      }
      fputs("\n", fp);
    }
    fputs("\n", fp);
  }
  return 0;
}
#  endif

static int
names_clear(regex_t* reg)
{
  int i;
  NameEntry* e;
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t)) {
    for (i = 0; i < t->num; i++) {
      e = &(t->e[i]);
      if (IS_NOT_NULL(e->name)) {
	xfree(e->name);
	e->name       = NULL;
	e->name_len   = 0;
	e->back_num   = 0;
	e->back_alloc = 0;
	if (IS_NOT_NULL(e->back_refs)) xfree(e->back_refs);
	e->back_refs = (int* )NULL;
      }
    }
    if (IS_NOT_NULL(t->e)) {
      xfree(t->e);
      t->e = NULL;
    }
    t->num = 0;
  }
  return 0;
}

extern int
onig_names_free(regex_t* reg)
{
  int r;
  NameTable* t;

  r = names_clear(reg);
  if (r) return r;

  t = (NameTable* )reg->name_table;
  if (IS_NOT_NULL(t)) xfree(t);
  reg->name_table = NULL;
  return 0;
}

static NameEntry*
name_find(regex_t* reg, const UChar* name, const UChar* name_end)
{
  int i, len;
  NameEntry* e;
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t)) {
    len = name_end - name;
    for (i = 0; i < t->num; i++) {
      e = &(t->e[i]);
      if (len == e->name_len && onig_strncmp(name, e->name, len) == 0)
	return e;
    }
  }
  return (NameEntry* )NULL;
}

extern int
onig_foreach_name(regex_t* reg,
  int (*func)(const UChar*, const UChar*,int,int*,regex_t*,void*), void* arg)
{
  int i, r;
  NameEntry* e;
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t)) {
    for (i = 0; i < t->num; i++) {
      e = &(t->e[i]);
      r = (*func)(e->name, e->name + e->name_len, e->back_num,
		  (e->back_num > 1 ? e->back_refs : &(e->back_ref1)),
		  reg, arg);
      if (r != 0) return r;
    }
  }
  return 0;
}

extern int
onig_number_of_names(const regex_t* reg)
{
  NameTable* t = (NameTable* )reg->name_table;

  if (IS_NOT_NULL(t))
    return t->num;
  else
    return 0;
}

# endif /* else USE_ST_LIBRARY */

static int
name_add(regex_t* reg, UChar* name, UChar* name_end, int backref, ScanEnv* env)
{
  int alloc;
  NameEntry* e;
  NameTable* t = (NameTable* )reg->name_table;

  if (name_end - name <= 0)
    return ONIGERR_EMPTY_GROUP_NAME;

  e = name_find(reg, name, name_end);
  if (IS_NULL(e)) {
# ifdef USE_ST_LIBRARY
    if (IS_NULL(t)) {
      t = onig_st_init_strend_table_with_size(5);
      reg->name_table = (void* )t;
    }
    e = (NameEntry* )xmalloc(sizeof(NameEntry));
    CHECK_NULL_RETURN_MEMERR(e);

    e->name = strdup_with_null(reg->enc, name, name_end);
    if (IS_NULL(e->name)) {
      xfree(e);
      return ONIGERR_MEMORY;
    }
    onig_st_insert_strend(t, e->name, (e->name + (name_end - name)),
                          (HashDataType )e);

    e->name_len   = name_end - name;
    e->back_num   = 0;
    e->back_alloc = 0;
    e->back_refs  = (int* )NULL;

# else

    if (IS_NULL(t)) {
      alloc = INIT_NAMES_ALLOC_NUM;
      t = (NameTable* )xmalloc(sizeof(NameTable));
      CHECK_NULL_RETURN_MEMERR(t);
      t->e     = NULL;
      t->alloc = 0;
      t->num   = 0;

      t->e = (NameEntry* )xmalloc(sizeof(NameEntry) * alloc);
      if (IS_NULL(t->e)) {
	xfree(t);
	return ONIGERR_MEMORY;
      }
      t->alloc = alloc;
      reg->name_table = t;
      goto clear;
    }
    else if (t->num == t->alloc) {
      int i;
      NameEntry* p;

      alloc = t->alloc * 2;
      p = (NameEntry* )xrealloc(t->e, sizeof(NameEntry) * alloc);
      CHECK_NULL_RETURN_MEMERR(p);
      t->e = p;
      t->alloc = alloc;

    clear:
      for (i = t->num; i < t->alloc; i++) {
	t->e[i].name       = NULL;
	t->e[i].name_len   = 0;
	t->e[i].back_num   = 0;
	t->e[i].back_alloc = 0;
	t->e[i].back_refs  = (int* )NULL;
      }
    }
    e = &(t->e[t->num]);
    t->num++;
    e->name = strdup_with_null(reg->enc, name, name_end);
    if (IS_NULL(e->name)) return ONIGERR_MEMORY;
    e->name_len = name_end - name;
# endif
  }

  if (e->back_num >= 1 &&
      ! IS_SYNTAX_BV(env->syntax, ONIG_SYN_ALLOW_MULTIPLEX_DEFINITION_NAME)) {
    onig_scan_env_set_error_string(env, ONIGERR_MULTIPLEX_DEFINED_NAME,
				    name, name_end);
    return ONIGERR_MULTIPLEX_DEFINED_NAME;
  }

  e->back_num++;
  if (e->back_num == 1) {
    e->back_ref1 = backref;
  }
  else {
    if (e->back_num == 2) {
      alloc = INIT_NAME_BACKREFS_ALLOC_NUM;
      e->back_refs = (int* )xmalloc(sizeof(int) * alloc);
      CHECK_NULL_RETURN_MEMERR(e->back_refs);
      e->back_alloc = alloc;
      e->back_refs[0] = e->back_ref1;
      e->back_refs[1] = backref;
    }
    else {
      if (e->back_num > e->back_alloc) {
	int* p;
	alloc = e->back_alloc * 2;
	p = (int* )xrealloc(e->back_refs, sizeof(int) * alloc);
	CHECK_NULL_RETURN_MEMERR(p);
	e->back_refs = p;
	e->back_alloc = alloc;
      }
      e->back_refs[e->back_num - 1] = backref;
    }
  }

  return 0;
}

extern int
onig_name_to_group_numbers(regex_t* reg, const UChar* name,
			   const UChar* name_end, int** nums)
{
  NameEntry* e = name_find(reg, name, name_end);

  if (IS_NULL(e)) return ONIGERR_UNDEFINED_NAME_REFERENCE;

  switch (e->back_num) {
  case 0:
    *nums = 0;
    break;
  case 1:
    *nums = &(e->back_ref1);
    break;
  default:
    *nums = e->back_refs;
    break;
  }
  return e->back_num;
}

extern int
onig_name_to_backref_number(regex_t* reg, const UChar* name,
			    const UChar* name_end, const OnigRegion *region)
{
  int i, n, *nums;

  n = onig_name_to_group_numbers(reg, name, name_end, &nums);
  if (n < 0)
    return n;
  else if (n == 0)
    return ONIGERR_PARSER_BUG;
  else if (n == 1)
    return nums[0];
  else {
    if (IS_NOT_NULL(region)) {
      for (i = n - 1; i >= 0; i--) {
	if (region->beg[nums[i]] != ONIG_REGION_NOTPOS)
	  return nums[i];
      }
    }
    return nums[n - 1];
  }
}

#else /* USE_NAMED_GROUP */

extern int
onig_name_to_group_numbers(regex_t* reg, const UChar* name,
			   const UChar* name_end, int** nums)
{
  return ONIG_NO_SUPPORT_CONFIG;
}

extern int
onig_name_to_backref_number(regex_t* reg, const UChar* name,
			    const UChar* name_end, const OnigRegion* region)
{
  return ONIG_NO_SUPPORT_CONFIG;
}

extern int
onig_foreach_name(regex_t* reg,
  int (*func)(const UChar*, const UChar*,int,int*,regex_t*,void*), void* arg)
{
  return ONIG_NO_SUPPORT_CONFIG;
}

extern int
onig_number_of_names(const regex_t* reg)
{
  return 0;
}
#endif /* else USE_NAMED_GROUP */

extern int
onig_noname_group_capture_is_active(const regex_t* reg)
{
  if (ONIG_IS_OPTION_ON(reg->options, ONIG_OPTION_DONT_CAPTURE_GROUP))
    return 0;

#ifdef USE_NAMED_GROUP
  if (onig_number_of_names(reg) > 0 &&
      IS_SYNTAX_BV(reg->syntax, ONIG_SYN_CAPTURE_ONLY_NAMED_GROUP) &&
      !ONIG_IS_OPTION_ON(reg->options, ONIG_OPTION_CAPTURE_GROUP)) {
    return 0;
  }
#endif

  return 1;
}


#define INIT_SCANENV_MEMNODES_ALLOC_SIZE   16

static void
scan_env_clear(ScanEnv* env)
{
  int i;

  BIT_STATUS_CLEAR(env->capture_history);
  BIT_STATUS_CLEAR(env->bt_mem_start);
  BIT_STATUS_CLEAR(env->bt_mem_end);
  BIT_STATUS_CLEAR(env->backrefed_mem);
  env->error      = (UChar* )NULL;
  env->error_end  = (UChar* )NULL;
  env->num_call   = 0;
  env->num_mem    = 0;
#ifdef USE_NAMED_GROUP
  env->num_named  = 0;
#endif
  env->mem_alloc         = 0;
  env->mem_nodes_dynamic = (Node** )NULL;

  for (i = 0; i < SCANENV_MEMNODES_SIZE; i++)
    env->mem_nodes_static[i] = NULL_NODE;

#ifdef USE_COMBINATION_EXPLOSION_CHECK
  env->num_comb_exp_check  = 0;
  env->comb_exp_max_regnum = 0;
  env->curr_max_regnum     = 0;
  env->has_recursion       = 0;
#endif
  env->parse_depth         = 0;
  env->warnings_flag       = 0;
}

static int
scan_env_add_mem_entry(ScanEnv* env)
{
  int i, need, alloc;
  Node** p;

  need = env->num_mem + 1;
  if (need > ONIG_MAX_CAPTURE_GROUP_NUM)
    return ONIGERR_TOO_MANY_CAPTURE_GROUPS;
  if (need >= SCANENV_MEMNODES_SIZE) {
    if (env->mem_alloc <= need) {
      if (IS_NULL(env->mem_nodes_dynamic)) {
	alloc = INIT_SCANENV_MEMNODES_ALLOC_SIZE;
	p = (Node** )xmalloc(sizeof(Node*) * alloc);
	CHECK_NULL_RETURN_MEMERR(p);
	xmemcpy(p, env->mem_nodes_static,
		sizeof(Node*) * SCANENV_MEMNODES_SIZE);
      }
      else {
	alloc = env->mem_alloc * 2;
	p = (Node** )xrealloc(env->mem_nodes_dynamic, sizeof(Node*) * alloc);
	CHECK_NULL_RETURN_MEMERR(p);
      }

      for (i = env->num_mem + 1; i < alloc; i++)
	p[i] = NULL_NODE;

      env->mem_nodes_dynamic = p;
      env->mem_alloc = alloc;
    }
  }

  env->num_mem++;
  return env->num_mem;
}

static int
scan_env_set_mem_node(ScanEnv* env, int num, Node* node)
{
  if (env->num_mem >= num)
    SCANENV_MEM_NODES(env)[num] = node;
  else
    return ONIGERR_PARSER_BUG;
  return 0;
}


extern void
onig_node_free(Node* node)
{
 start:
  if (IS_NULL(node)) return ;

  switch (NTYPE(node)) {
  case NT_STR:
    if (NSTR(node)->capa != 0 &&
	IS_NOT_NULL(NSTR(node)->s) && NSTR(node)->s != NSTR(node)->buf) {
      xfree(NSTR(node)->s);
    }
    break;

  case NT_LIST:
  case NT_ALT:
    onig_node_free(NCAR(node));
    {
      Node* next_node = NCDR(node);

      xfree(node);
      node = next_node;
      goto start;
    }
    break;

  case NT_CCLASS:
    {
      CClassNode* cc = NCCLASS(node);

      if (cc->mbuf)
	bbuf_free(cc->mbuf);
    }
    break;

  case NT_QTFR:
    if (NQTFR(node)->target)
      onig_node_free(NQTFR(node)->target);
    break;

  case NT_ENCLOSE:
    if (NENCLOSE(node)->target)
      onig_node_free(NENCLOSE(node)->target);
    break;

  case NT_BREF:
    if (IS_NOT_NULL(NBREF(node)->back_dynamic))
      xfree(NBREF(node)->back_dynamic);
    break;

  case NT_ANCHOR:
    if (NANCHOR(node)->target)
      onig_node_free(NANCHOR(node)->target);
    break;
  }

  xfree(node);
}

static Node*
node_new(void)
{
  Node* node;

  node = (Node* )xmalloc(sizeof(Node));
  /* xmemset(node, 0, sizeof(Node)); */
  return node;
}

static void
initialize_cclass(CClassNode* cc)
{
  BITSET_CLEAR(cc->bs);
  /* cc->base.flags = 0; */
  cc->flags = 0;
  cc->mbuf  = NULL;
}

static Node*
node_new_cclass(void)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_CCLASS);
  initialize_cclass(NCCLASS(node));
  return node;
}

static Node*
node_new_ctype(int type, int not, int ascii_range)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_CTYPE);
  NCTYPE(node)->ctype = type;
  NCTYPE(node)->not   = not;
  NCTYPE(node)->ascii_range = ascii_range;
  return node;
}

static Node*
node_new_anychar(void)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_CANY);
  return node;
}

static Node*
node_new_list(Node* left, Node* right)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_LIST);
  NCAR(node)  = left;
  NCDR(node) = right;
  return node;
}

extern Node*
onig_node_new_list(Node* left, Node* right)
{
  return node_new_list(left, right);
}

extern Node*
onig_node_list_add(Node* list, Node* x)
{
  Node *n;

  n = onig_node_new_list(x, NULL);
  if (IS_NULL(n)) return NULL_NODE;

  if (IS_NOT_NULL(list)) {
    while (IS_NOT_NULL(NCDR(list)))
      list = NCDR(list);

    NCDR(list) = n;
  }

  return n;
}

extern Node*
onig_node_new_alt(Node* left, Node* right)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_ALT);
  NCAR(node)  = left;
  NCDR(node) = right;
  return node;
}

extern Node*
onig_node_new_anchor(int type)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_ANCHOR);
  NANCHOR(node)->type     = type;
  NANCHOR(node)->target   = NULL;
  NANCHOR(node)->char_len = -1;
  NANCHOR(node)->ascii_range = 0;
  return node;
}

static Node*
node_new_backref(int back_num, int* backrefs, int by_name,
#ifdef USE_BACKREF_WITH_LEVEL
		 int exist_level, int nest_level,
#endif
		 ScanEnv* env)
{
  int i;
  Node* node = node_new();

  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_BREF);
  NBREF(node)->state    = 0;
  NBREF(node)->back_num = back_num;
  NBREF(node)->back_dynamic = (int* )NULL;
  if (by_name != 0)
    NBREF(node)->state |= NST_NAME_REF;

#ifdef USE_BACKREF_WITH_LEVEL
  if (exist_level != 0) {
    NBREF(node)->state |= NST_NEST_LEVEL;
    NBREF(node)->nest_level  = nest_level;
  }
#endif

  for (i = 0; i < back_num; i++) {
    if (backrefs[i] <= env->num_mem &&
	IS_NULL(SCANENV_MEM_NODES(env)[backrefs[i]])) {
      NBREF(node)->state |= NST_RECURSION;   /* /...(\1).../ */
      break;
    }
  }

  if (back_num <= NODE_BACKREFS_SIZE) {
    for (i = 0; i < back_num; i++)
      NBREF(node)->back_static[i] = backrefs[i];
  }
  else {
    int* p = (int* )xmalloc(sizeof(int) * back_num);
    if (IS_NULL(p)) {
      onig_node_free(node);
      return NULL;
    }
    NBREF(node)->back_dynamic = p;
    for (i = 0; i < back_num; i++)
      p[i] = backrefs[i];
  }
  return node;
}

#ifdef USE_SUBEXP_CALL
static Node*
node_new_call(UChar* name, UChar* name_end, int gnum)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_CALL);
  NCALL(node)->state     = 0;
  NCALL(node)->target    = NULL_NODE;
  NCALL(node)->name      = name;
  NCALL(node)->name_end  = name_end;
  NCALL(node)->group_num = gnum;  /* call by number if gnum != 0 */
  return node;
}
#endif

static Node*
node_new_quantifier(int lower, int upper, int by_number)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_QTFR);
  NQTFR(node)->state  = 0;
  NQTFR(node)->target = NULL;
  NQTFR(node)->lower  = lower;
  NQTFR(node)->upper  = upper;
  NQTFR(node)->greedy = 1;
  NQTFR(node)->target_empty_info = NQ_TARGET_ISNOT_EMPTY;
  NQTFR(node)->head_exact        = NULL_NODE;
  NQTFR(node)->next_head_exact   = NULL_NODE;
  NQTFR(node)->is_referred       = 0;
  if (by_number != 0)
    NQTFR(node)->state |= NST_BY_NUMBER;

#ifdef USE_COMBINATION_EXPLOSION_CHECK
  NQTFR(node)->comb_exp_check_num = 0;
#endif

  return node;
}

static Node*
node_new_enclose(int type)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_ENCLOSE);
  NENCLOSE(node)->type      = type;
  NENCLOSE(node)->state     =  0;
  NENCLOSE(node)->regnum    =  0;
  NENCLOSE(node)->option    =  0;
  NENCLOSE(node)->target    = NULL;
  NENCLOSE(node)->call_addr = -1;
  NENCLOSE(node)->opt_count =  0;
  return node;
}

extern Node*
onig_node_new_enclose(int type)
{
  return node_new_enclose(type);
}

static Node*
node_new_enclose_memory(OnigOptionType option, int is_named)
{
  Node* node = node_new_enclose(ENCLOSE_MEMORY);
  CHECK_NULL_RETURN(node);
  if (is_named != 0)
    SET_ENCLOSE_STATUS(node, NST_NAMED_GROUP);

#ifdef USE_SUBEXP_CALL
  NENCLOSE(node)->option = option;
#endif
  return node;
}

static Node*
node_new_option(OnigOptionType option)
{
  Node* node = node_new_enclose(ENCLOSE_OPTION);
  CHECK_NULL_RETURN(node);
  NENCLOSE(node)->option = option;
  return node;
}

extern int
onig_node_str_cat(Node* node, const UChar* s, const UChar* end)
{
  ptrdiff_t addlen = end - s;

  if (addlen > 0) {
    ptrdiff_t len  = NSTR(node)->end - NSTR(node)->s;

    if (NSTR(node)->capa > 0 || (len + addlen > NODE_STR_BUF_SIZE - 1)) {
      UChar* p;
      ptrdiff_t capa = len + addlen + NODE_STR_MARGIN;

      if (capa <= NSTR(node)->capa) {
	onig_strcpy(NSTR(node)->s + len, s, end);
      }
      else {
	if (NSTR(node)->s == NSTR(node)->buf)
	  p = strcat_capa_from_static(NSTR(node)->s, NSTR(node)->end,
				      s, end, capa);
	else
	  p = strcat_capa(NSTR(node)->s, NSTR(node)->end, s, end, capa);

	CHECK_NULL_RETURN_MEMERR(p);
	NSTR(node)->s    = p;
	NSTR(node)->capa = (int )capa;
      }
    }
    else {
      onig_strcpy(NSTR(node)->s + len, s, end);
    }
    NSTR(node)->end = NSTR(node)->s + len + addlen;
  }

  return 0;
}

extern int
onig_node_str_set(Node* node, const UChar* s, const UChar* end)
{
  onig_node_str_clear(node);
  return onig_node_str_cat(node, s, end);
}

static int
node_str_cat_char(Node* node, UChar c)
{
  UChar s[1];

  s[0] = c;
  return onig_node_str_cat(node, s, s + 1);
}

static int
node_str_cat_codepoint(Node* node, OnigEncoding enc, OnigCodePoint c)
{
  UChar buf[ONIGENC_CODE_TO_MBC_MAXLEN];
  int num = ONIGENC_CODE_TO_MBC(enc, c, buf);
  if (num < 0) return num;
  return onig_node_str_cat(node, buf, buf + num);
}

#if 0
extern void
onig_node_conv_to_str_node(Node* node, int flag)
{
  SET_NTYPE(node, NT_STR);
  NSTR(node)->flag = flag;
  NSTR(node)->capa = 0;
  NSTR(node)->s    = NSTR(node)->buf;
  NSTR(node)->end  = NSTR(node)->buf;
}
#endif

extern void
onig_node_str_clear(Node* node)
{
  if (NSTR(node)->capa != 0 &&
      IS_NOT_NULL(NSTR(node)->s) && NSTR(node)->s != NSTR(node)->buf) {
    xfree(NSTR(node)->s);
  }

  NSTR(node)->capa = 0;
  NSTR(node)->flag = 0;
  NSTR(node)->s    = NSTR(node)->buf;
  NSTR(node)->end  = NSTR(node)->buf;
}

static Node*
node_new_str(const UChar* s, const UChar* end)
{
  Node* node = node_new();
  CHECK_NULL_RETURN(node);

  SET_NTYPE(node, NT_STR);
  NSTR(node)->capa = 0;
  NSTR(node)->flag = 0;
  NSTR(node)->s    = NSTR(node)->buf;
  NSTR(node)->end  = NSTR(node)->buf;
  if (onig_node_str_cat(node, s, end)) {
    onig_node_free(node);
    return NULL;
  }
  return node;
}

extern Node*
onig_node_new_str(const UChar* s, const UChar* end)
{
  return node_new_str(s, end);
}

static Node*
node_new_str_raw(UChar* s, UChar* end)
{
  Node* node = node_new_str(s, end);
  if (IS_NOT_NULL(node))
    NSTRING_SET_RAW(node);
  return node;
}

static Node*
node_new_empty(void)
{
  return node_new_str(NULL, NULL);
}

static Node*
node_new_str_raw_char(UChar c)
{
  UChar p[1];

  p[0] = c;
  return node_new_str_raw(p, p + 1);
}

static Node*
str_node_split_last_char(StrNode* sn, OnigEncoding enc)
{
  const UChar *p;
  Node* n = NULL_NODE;

  if (sn->end > sn->s) {
    p = onigenc_get_prev_char_head(enc, sn->s, sn->end, sn->end);
    if (p && p > sn->s) { /* can be split. */
      n = node_new_str(p, sn->end);
      if (IS_NOT_NULL(n) && (sn->flag & NSTR_RAW) != 0)
	NSTRING_SET_RAW(n);
      sn->end = (UChar* )p;
    }
  }
  return n;
}

static int
str_node_can_be_split(StrNode* sn, OnigEncoding enc)
{
  if (sn->end > sn->s) {
    return ((enclen(enc, sn->s, sn->end) < sn->end - sn->s)  ?  1 : 0);
  }
  return 0;
}

#ifdef USE_PAD_TO_SHORT_BYTE_CHAR
static int
node_str_head_pad(StrNode* sn, int num, UChar val)
{
  UChar buf[NODE_STR_BUF_SIZE];
  int i, len;

  len = sn->end - sn->s;
  onig_strcpy(buf, sn->s, sn->end);
  onig_strcpy(&(sn->s[num]), buf, buf + len);
  sn->end += num;

  for (i = 0; i < num; i++) {
    sn->s[i] = val;
  }
}
#endif

extern int
onig_scan_unsigned_number(UChar** src, const UChar* end, OnigEncoding enc)
{
  unsigned int num, val;
  OnigCodePoint c;
  UChar* p = *src;
  PFETCH_READY;

  num = 0;
  while (!PEND) {
    PFETCH(c);
    if (ONIGENC_IS_CODE_DIGIT(enc, c)) {
      val = (unsigned int )DIGITVAL(c);
      if ((INT_MAX_LIMIT - val) / 10UL < num)
	return -1;  /* overflow */

      num = num * 10 + val;
    }
    else {
      PUNFETCH;
      break;
    }
  }
  *src = p;
  return num;
}

static int
scan_unsigned_hexadecimal_number(UChar** src, UChar* end, int minlen,
				 int maxlen, OnigEncoding enc)
{
  OnigCodePoint c;
  unsigned int num, val;
  int restlen;
  UChar* p = *src;
  PFETCH_READY;

  restlen = maxlen - minlen;
  num = 0;
  while (!PEND && maxlen-- != 0) {
    PFETCH(c);
    if (ONIGENC_IS_CODE_XDIGIT(enc, c)) {
      val = (unsigned int )XDIGITVAL(enc,c);
      if ((INT_MAX_LIMIT - val) / 16UL < num)
	return -1;  /* overflow */

      num = (num << 4) + XDIGITVAL(enc,c);
    }
    else {
      PUNFETCH;
      maxlen++;
      break;
    }
  }
  if (maxlen > restlen)
    return -2;  /* not enough digits */
  *src = p;
  return num;
}

static int
scan_unsigned_octal_number(UChar** src, UChar* end, int maxlen,
			   OnigEncoding enc)
{
  OnigCodePoint c;
  unsigned int num, val;
  UChar* p = *src;
  PFETCH_READY;

  num = 0;
  while (!PEND && maxlen-- != 0) {
    PFETCH(c);
    if (ONIGENC_IS_CODE_DIGIT(enc, c) && c < '8') {
      val = ODIGITVAL(c);
      if ((INT_MAX_LIMIT - val) / 8UL < num)
	return -1;  /* overflow */

      num = (num << 3) + val;
    }
    else {
      PUNFETCH;
      break;
    }
  }
  *src = p;
  return num;
}


#define BBUF_WRITE_CODE_POINT(bbuf,pos,code) \
    BBUF_WRITE(bbuf, pos, &(code), SIZE_CODE_POINT)

/* data format:
     [n][from-1][to-1][from-2][to-2] ... [from-n][to-n]
     (all data size is OnigCodePoint)
 */
static int
new_code_range(BBuf** pbuf)
{
#define INIT_MULTI_BYTE_RANGE_SIZE  (SIZE_CODE_POINT * 5)
  int r;
  OnigCodePoint n;
  BBuf* bbuf;

  bbuf = *pbuf = (BBuf* )xmalloc(sizeof(BBuf));
  CHECK_NULL_RETURN_MEMERR(*pbuf);
  r = BBUF_INIT(*pbuf, INIT_MULTI_BYTE_RANGE_SIZE);
  if (r) return r;

  n = 0;
  BBUF_WRITE_CODE_POINT(bbuf, 0, n);
  return 0;
}

static int
add_code_range_to_buf0(BBuf** pbuf, ScanEnv* env, OnigCodePoint from, OnigCodePoint to,
	int checkdup)
{
  int r, inc_n, pos;
  OnigCodePoint low, high, bound, x;
  OnigCodePoint n, *data;
  BBuf* bbuf;

  if (from > to) {
    n = from; from = to; to = n;
  }

  if (IS_NULL(*pbuf)) {
    r = new_code_range(pbuf);
    if (r) return r;
    bbuf = *pbuf;
    n = 0;
  }
  else {
    bbuf = *pbuf;
    GET_CODE_POINT(n, bbuf->p);
  }
  data = (OnigCodePoint* )(bbuf->p);
  data++;

  bound = (from == 0) ? 0 : n;
  for (low = 0; low < bound; ) {
    x = (low + bound) >> 1;
    if (from - 1 > data[x*2 + 1])
      low = x + 1;
    else
      bound = x;
  }

  high = (to == ONIG_LAST_CODE_POINT) ? n : low;
  for (bound = n; high < bound; ) {
    x = (high + bound) >> 1;
    if (to + 1 >= data[x*2])
      high = x + 1;
    else
      bound = x;
  }
  /* data[(low-1)*2+1] << from <= data[low*2]
   * data[(high-1)*2+1] <= to << data[high*2]
   */

  inc_n = low + 1 - high;
  if (n + inc_n > ONIG_MAX_MULTI_BYTE_RANGES_NUM)
    return ONIGERR_TOO_MANY_MULTI_BYTE_RANGES;

  if (inc_n != 1) {
    if (checkdup && from <= data[low*2+1]
	&& (data[low*2] <= from || data[low*2+1] <= to))
      CC_DUP_WARN(env, from, to);
    if (from > data[low*2])
      from = data[low*2];
    if (to < data[(high - 1)*2 + 1])
      to = data[(high - 1)*2 + 1];
  }

  if (inc_n != 0) {
    int from_pos = SIZE_CODE_POINT * (1 + high * 2);
    int to_pos   = SIZE_CODE_POINT * (1 + (low + 1) * 2);

    if (inc_n > 0) {
      if (high < n) {
	int size = (n - high) * 2 * SIZE_CODE_POINT;
	BBUF_MOVE_RIGHT(bbuf, from_pos, to_pos, size);
      }
    }
    else {
      BBUF_MOVE_LEFT_REDUCE(bbuf, from_pos, to_pos);
    }
  }

  pos = SIZE_CODE_POINT * (1 + low * 2);
  BBUF_ENSURE_SIZE(bbuf, pos + SIZE_CODE_POINT * 2);
  BBUF_WRITE_CODE_POINT(bbuf, pos, from);
  BBUF_WRITE_CODE_POINT(bbuf, pos + SIZE_CODE_POINT, to);
  n += inc_n;
  BBUF_WRITE_CODE_POINT(bbuf, 0, n);

  return 0;
}

static int
add_code_range_to_buf(BBuf** pbuf, ScanEnv* env, OnigCodePoint from, OnigCodePoint to)
{
  return add_code_range_to_buf0(pbuf, env, from, to, 1);
}

static int
add_code_range0(BBuf** pbuf, ScanEnv* env, OnigCodePoint from, OnigCodePoint to, int checkdup)
{
  if (from > to) {
    if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC))
      return 0;
    else
      return ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS;
  }

  return add_code_range_to_buf0(pbuf, env, from, to, checkdup);
}

static int
add_code_range(BBuf** pbuf, ScanEnv* env, OnigCodePoint from, OnigCodePoint to)
{
  return add_code_range0(pbuf, env, from, to, 1);
}

static int
not_code_range_buf(OnigEncoding enc, BBuf* bbuf, BBuf** pbuf, ScanEnv* env)
{
  int r, i, n;
  OnigCodePoint pre, from, *data, to = 0;

  *pbuf = (BBuf* )NULL;
  if (IS_NULL(bbuf)) {
  set_all:
    return SET_ALL_MULTI_BYTE_RANGE(enc, pbuf);
  }

  data = (OnigCodePoint* )(bbuf->p);
  GET_CODE_POINT(n, data);
  data++;
  if (n <= 0) goto set_all;

  r = 0;
  pre = MBCODE_START_POS(enc);
  for (i = 0; i < n; i++) {
    from = data[i*2];
    to   = data[i*2+1];
    if (pre <= from - 1) {
      r = add_code_range_to_buf(pbuf, env, pre, from - 1);
      if (r != 0) return r;
    }
    if (to == ONIG_LAST_CODE_POINT) break;
    pre = to + 1;
  }
  if (to < ONIG_LAST_CODE_POINT) {
    r = add_code_range_to_buf(pbuf, env, to + 1, ONIG_LAST_CODE_POINT);
  }
  return r;
}

#define SWAP_BBUF_NOT(bbuf1, not1, bbuf2, not2) do {\
  BBuf *tbuf; \
  int  tnot; \
  tnot = not1;  not1  = not2;  not2  = tnot; \
  tbuf = bbuf1; bbuf1 = bbuf2; bbuf2 = tbuf; \
} while (0)

static int
or_code_range_buf(OnigEncoding enc, BBuf* bbuf1, int not1,
                  BBuf* bbuf2, int not2, BBuf** pbuf, ScanEnv* env)
{
  int r;
  OnigCodePoint i, n1, *data1;
  OnigCodePoint from, to;

  *pbuf = (BBuf* )NULL;
  if (IS_NULL(bbuf1) && IS_NULL(bbuf2)) {
    if (not1 != 0 || not2 != 0)
      return SET_ALL_MULTI_BYTE_RANGE(enc, pbuf);
    return 0;
  }

  r = 0;
  if (IS_NULL(bbuf2))
    SWAP_BBUF_NOT(bbuf1, not1, bbuf2, not2);

  if (IS_NULL(bbuf1)) {
    if (not1 != 0) {
      return SET_ALL_MULTI_BYTE_RANGE(enc, pbuf);
    }
    else {
      if (not2 == 0) {
	return bbuf_clone(pbuf, bbuf2);
      }
      else {
	return not_code_range_buf(enc, bbuf2, pbuf, env);
      }
    }
  }

  if (not1 != 0)
    SWAP_BBUF_NOT(bbuf1, not1, bbuf2, not2);

  data1 = (OnigCodePoint* )(bbuf1->p);
  GET_CODE_POINT(n1, data1);
  data1++;

  if (not2 == 0 && not1 == 0) { /* 1 OR 2 */
    r = bbuf_clone(pbuf, bbuf2);
  }
  else if (not1 == 0) { /* 1 OR (not 2) */
    r = not_code_range_buf(enc, bbuf2, pbuf, env);
  }
  if (r != 0) return r;

  for (i = 0; i < n1; i++) {
    from = data1[i*2];
    to   = data1[i*2+1];
    r = add_code_range_to_buf(pbuf, env, from, to);
    if (r != 0) return r;
  }
  return 0;
}

static int
and_code_range1(BBuf** pbuf, ScanEnv* env, OnigCodePoint from1, OnigCodePoint to1,
		OnigCodePoint* data, int n)
{
  int i, r;
  OnigCodePoint from2, to2;

  for (i = 0; i < n; i++) {
    from2 = data[i*2];
    to2   = data[i*2+1];
    if (from2 < from1) {
      if (to2 < from1) continue;
      else {
	from1 = to2 + 1;
      }
    }
    else if (from2 <= to1) {
      if (to2 < to1) {
	if (from1 <= from2 - 1) {
	  r = add_code_range_to_buf(pbuf, env, from1, from2-1);
	  if (r != 0) return r;
	}
	from1 = to2 + 1;
      }
      else {
	to1 = from2 - 1;
      }
    }
    else {
      from1 = from2;
    }
    if (from1 > to1) break;
  }
  if (from1 <= to1) {
    r = add_code_range_to_buf(pbuf, env, from1, to1);
    if (r != 0) return r;
  }
  return 0;
}

static int
and_code_range_buf(BBuf* bbuf1, int not1, BBuf* bbuf2, int not2, BBuf** pbuf, ScanEnv* env)
{
  int r;
  OnigCodePoint i, j, n1, n2, *data1, *data2;
  OnigCodePoint from, to, from1, to1, from2, to2;

  *pbuf = (BBuf* )NULL;
  if (IS_NULL(bbuf1)) {
    if (not1 != 0 && IS_NOT_NULL(bbuf2)) /* not1 != 0 -> not2 == 0 */
      return bbuf_clone(pbuf, bbuf2);
    return 0;
  }
  else if (IS_NULL(bbuf2)) {
    if (not2 != 0)
      return bbuf_clone(pbuf, bbuf1);
    return 0;
  }

  if (not1 != 0)
    SWAP_BBUF_NOT(bbuf1, not1, bbuf2, not2);

  data1 = (OnigCodePoint* )(bbuf1->p);
  data2 = (OnigCodePoint* )(bbuf2->p);
  GET_CODE_POINT(n1, data1);
  GET_CODE_POINT(n2, data2);
  data1++;
  data2++;

  if (not2 == 0 && not1 == 0) { /* 1 AND 2 */
    for (i = 0; i < n1; i++) {
      from1 = data1[i*2];
      to1   = data1[i*2+1];
      for (j = 0; j < n2; j++) {
	from2 = data2[j*2];
	to2   = data2[j*2+1];
	if (from2 > to1) break;
	if (to2 < from1) continue;
	from = MAX(from1, from2);
	to   = MIN(to1, to2);
	r = add_code_range_to_buf(pbuf, env, from, to);
	if (r != 0) return r;
      }
    }
  }
  else if (not1 == 0) { /* 1 AND (not 2) */
    for (i = 0; i < n1; i++) {
      from1 = data1[i*2];
      to1   = data1[i*2+1];
      r = and_code_range1(pbuf, env, from1, to1, data2, n2);
      if (r != 0) return r;
    }
  }

  return 0;
}

static int
and_cclass(CClassNode* dest, CClassNode* cc, ScanEnv* env)
{
  OnigEncoding enc = env->enc;
  int r, not1, not2;
  BBuf *buf1, *buf2, *pbuf = 0;
  BitSetRef bsr1, bsr2;
  BitSet bs1, bs2;

  not1 = IS_NCCLASS_NOT(dest);
  bsr1 = dest->bs;
  buf1 = dest->mbuf;
  not2 = IS_NCCLASS_NOT(cc);
  bsr2 = cc->bs;
  buf2 = cc->mbuf;

  if (not1 != 0) {
    bitset_invert_to(bsr1, bs1);
    bsr1 = bs1;
  }
  if (not2 != 0) {
    bitset_invert_to(bsr2, bs2);
    bsr2 = bs2;
  }
  bitset_and(bsr1, bsr2);
  if (bsr1 != dest->bs) {
    bitset_copy(dest->bs, bsr1);
    bsr1 = dest->bs;
  }
  if (not1 != 0) {
    bitset_invert(dest->bs);
  }

  if (! ONIGENC_IS_SINGLEBYTE(enc)) {
    if (not1 != 0 && not2 != 0) {
      r = or_code_range_buf(enc, buf1, 0, buf2, 0, &pbuf, env);
    }
    else {
      r = and_code_range_buf(buf1, not1, buf2, not2, &pbuf, env);
      if (r == 0 && not1 != 0) {
	BBuf *tbuf = 0;
	r = not_code_range_buf(enc, pbuf, &tbuf, env);
	bbuf_free(pbuf);
	pbuf = tbuf;
      }
    }
    if (r != 0) {
      bbuf_free(pbuf);
      return r;
    }

    dest->mbuf = pbuf;
    bbuf_free(buf1);
    return r;
  }
  return 0;
}

static int
or_cclass(CClassNode* dest, CClassNode* cc, ScanEnv* env)
{
  OnigEncoding enc = env->enc;
  int r, not1, not2;
  BBuf *buf1, *buf2, *pbuf = 0;
  BitSetRef bsr1, bsr2;
  BitSet bs1, bs2;

  not1 = IS_NCCLASS_NOT(dest);
  bsr1 = dest->bs;
  buf1 = dest->mbuf;
  not2 = IS_NCCLASS_NOT(cc);
  bsr2 = cc->bs;
  buf2 = cc->mbuf;

  if (not1 != 0) {
    bitset_invert_to(bsr1, bs1);
    bsr1 = bs1;
  }
  if (not2 != 0) {
    bitset_invert_to(bsr2, bs2);
    bsr2 = bs2;
  }
  bitset_or(bsr1, bsr2);
  if (bsr1 != dest->bs) {
    bitset_copy(dest->bs, bsr1);
    bsr1 = dest->bs;
  }
  if (not1 != 0) {
    bitset_invert(dest->bs);
  }

  if (! ONIGENC_IS_SINGLEBYTE(enc)) {
    if (not1 != 0 && not2 != 0) {
      r = and_code_range_buf(buf1, 0, buf2, 0, &pbuf, env);
    }
    else {
      r = or_code_range_buf(enc, buf1, not1, buf2, not2, &pbuf, env);
      if (r == 0 && not1 != 0) {
	BBuf *tbuf = 0;
	r = not_code_range_buf(enc, pbuf, &tbuf, env);
	bbuf_free(pbuf);
	pbuf = tbuf;
      }
    }
    if (r != 0) {
      bbuf_free(pbuf);
      return r;
    }

    dest->mbuf = pbuf;
    bbuf_free(buf1);
    return r;
  }
  else
    return 0;
}

static void UNKNOWN_ESC_WARN(ScanEnv *env, int c);

static OnigCodePoint
conv_backslash_value(OnigCodePoint c, ScanEnv* env)
{
  if (IS_SYNTAX_OP(env->syntax, ONIG_SYN_OP_ESC_CONTROL_CHARS)) {
    switch (c) {
    case 'n': return '\n';
    case 't': return '\t';
    case 'r': return '\r';
    case 'f': return '\f';
    case 'a': return '\007';
    case 'b': return '\010';
    case 'e': return '\033';
    case 'v':
      if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_ESC_V_VTAB))
	return '\v';
      break;

    default:
      if (('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z'))
	  UNKNOWN_ESC_WARN(env, c);
      break;
    }
  }
  return c;
}

#ifdef USE_NO_INVALID_QUANTIFIER
# define is_invalid_quantifier_target(node) 0
#else
static int
is_invalid_quantifier_target(Node* node)
{
  switch (NTYPE(node)) {
  case NT_ANCHOR:
    return 1;
    break;

  case NT_ENCLOSE:
    /* allow enclosed elements */
    /* return is_invalid_quantifier_target(NENCLOSE(node)->target); */
    break;

  case NT_LIST:
    do {
      if (! is_invalid_quantifier_target(NCAR(node))) return 0;
    } while (IS_NOT_NULL(node = NCDR(node)));
    return 0;
    break;

  case NT_ALT:
    do {
      if (is_invalid_quantifier_target(NCAR(node))) return 1;
    } while (IS_NOT_NULL(node = NCDR(node)));
    break;

  default:
    break;
  }
  return 0;
}
#endif

/* ?:0, *:1, +:2, ??:3, *?:4, +?:5 */
static int
popular_quantifier_num(QtfrNode* q)
{
  if (q->greedy) {
    if (q->lower == 0) {
      if (q->upper == 1) return 0;
      else if (IS_REPEAT_INFINITE(q->upper)) return 1;
    }
    else if (q->lower == 1) {
      if (IS_REPEAT_INFINITE(q->upper)) return 2;
    }
  }
  else {
    if (q->lower == 0) {
      if (q->upper == 1) return 3;
      else if (IS_REPEAT_INFINITE(q->upper)) return 4;
    }
    else if (q->lower == 1) {
      if (IS_REPEAT_INFINITE(q->upper)) return 5;
    }
  }
  return -1;
}


enum ReduceType {
  RQ_ASIS = 0, /* as is */
  RQ_DEL  = 1, /* delete parent */
  RQ_A,        /* to '*'    */
  RQ_AQ,       /* to '*?'   */
  RQ_QQ,       /* to '??'   */
  RQ_P_QQ,     /* to '+)??' */
  RQ_PQ_Q      /* to '+?)?' */
};

static enum ReduceType const ReduceTypeTable[6][6] = {
/* '?',     '*',     '+',    '??',    '*?',    '+?'      p / c   */
  {RQ_DEL,  RQ_A,    RQ_A,   RQ_QQ,   RQ_AQ,   RQ_ASIS}, /* '?'  */
  {RQ_DEL,  RQ_DEL,  RQ_DEL, RQ_P_QQ, RQ_P_QQ, RQ_DEL},  /* '*'  */
  {RQ_A,    RQ_A,    RQ_DEL, RQ_ASIS, RQ_P_QQ, RQ_DEL},  /* '+'  */
  {RQ_DEL,  RQ_AQ,   RQ_AQ,  RQ_DEL,  RQ_AQ,   RQ_AQ},   /* '??' */
  {RQ_DEL,  RQ_DEL,  RQ_DEL, RQ_DEL,  RQ_DEL,  RQ_DEL},  /* '*?' */
  {RQ_ASIS, RQ_PQ_Q, RQ_DEL, RQ_AQ,   RQ_AQ,   RQ_DEL}   /* '+?' */
};

extern void
onig_reduce_nested_quantifier(Node* pnode, Node* cnode)
{
  int pnum, cnum;
  QtfrNode *p, *c;

  p = NQTFR(pnode);
  c = NQTFR(cnode);
  pnum = popular_quantifier_num(p);
  cnum = popular_quantifier_num(c);
  if (pnum < 0 || cnum < 0) return ;

  switch (ReduceTypeTable[cnum][pnum]) {
  case RQ_DEL:
    *pnode = *cnode;
    break;
  case RQ_A:
    p->target = c->target;
    p->lower  = 0;  p->upper = REPEAT_INFINITE;  p->greedy = 1;
    break;
  case RQ_AQ:
    p->target = c->target;
    p->lower  = 0;  p->upper = REPEAT_INFINITE;  p->greedy = 0;
    break;
  case RQ_QQ:
    p->target = c->target;
    p->lower  = 0;  p->upper = 1;  p->greedy = 0;
    break;
  case RQ_P_QQ:
    p->target = cnode;
    p->lower  = 0;  p->upper = 1;  p->greedy = 0;
    c->lower  = 1;  c->upper = REPEAT_INFINITE;  c->greedy = 1;
    return ;
    break;
  case RQ_PQ_Q:
    p->target = cnode;
    p->lower  = 0;  p->upper = 1;  p->greedy = 1;
    c->lower  = 1;  c->upper = REPEAT_INFINITE;  c->greedy = 0;
    return ;
    break;
  case RQ_ASIS:
    p->target = cnode;
    return ;
    break;
  }

  c->target = NULL_NODE;
  onig_node_free(cnode);
}


enum TokenSyms {
  TK_EOT      = 0,   /* end of token */
  TK_RAW_BYTE = 1,
  TK_CHAR,
  TK_STRING,
  TK_CODE_POINT,
  TK_ANYCHAR,
  TK_CHAR_TYPE,
  TK_BACKREF,
  TK_CALL,
  TK_ANCHOR,
  TK_OP_REPEAT,
  TK_INTERVAL,
  TK_ANYCHAR_ANYTIME,  /* SQL '%' == .* */
  TK_ALT,
  TK_SUBEXP_OPEN,
  TK_SUBEXP_CLOSE,
  TK_CC_OPEN,
  TK_QUOTE_OPEN,
  TK_CHAR_PROPERTY,    /* \p{...}, \P{...} */
  TK_LINEBREAK,
  TK_EXTENDED_GRAPHEME_CLUSTER,
  TK_KEEP,
  /* in cc */
  TK_CC_CLOSE,
  TK_CC_RANGE,
  TK_POSIX_BRACKET_OPEN,
  TK_CC_AND,             /* && */
  TK_CC_CC_OPEN          /* [ */
};

typedef struct {
  enum TokenSyms type;
  int escaped;
  int base;   /* is number: 8, 16 (used in [....]) */
  UChar* backp;
  union {
    UChar* s;
    int   c;
    OnigCodePoint code;
    struct {
      int subtype;
      int ascii_range;
    } anchor;
    struct {
      int lower;
      int upper;
      int greedy;
      int possessive;
    } repeat;
    struct {
      int  num;
      int  ref1;
      int* refs;
      int  by_name;
#ifdef USE_BACKREF_WITH_LEVEL
      int  exist_level;
      int  level;   /* \k<name+n> */
#endif
    } backref;
    struct {
      UChar* name;
      UChar* name_end;
      int    gnum;
      int    rel;
    } call;
    struct {
      int ctype;
      int not;
    } prop;
  } u;
} OnigToken;


static int
fetch_range_quantifier(UChar** src, UChar* end, OnigToken* tok, ScanEnv* env)
{
  int low, up, syn_allow, non_low = 0;
  int r = 0;
  OnigCodePoint c;
  OnigEncoding enc = env->enc;
  UChar* p = *src;
  PFETCH_READY;

  syn_allow = IS_SYNTAX_BV(env->syntax, ONIG_SYN_ALLOW_INVALID_INTERVAL);

  if (PEND) {
    if (syn_allow)
      return 1;  /* "....{" : OK! */
    else
      return ONIGERR_END_PATTERN_AT_LEFT_BRACE;  /* "....{" syntax error */
  }

  if (! syn_allow) {
    c = PPEEK;
    if (c == ')' || c == '(' || c == '|') {
      return ONIGERR_END_PATTERN_AT_LEFT_BRACE;
    }
  }

  low = onig_scan_unsigned_number(&p, end, env->enc);
  if (low < 0) return ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE;
  if (low > ONIG_MAX_REPEAT_NUM)
    return ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE;

  if (p == *src) { /* can't read low */
    if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_ALLOW_INTERVAL_LOW_ABBREV)) {
      /* allow {,n} as {0,n} */
      low = 0;
      non_low = 1;
    }
    else
      goto invalid;
  }

  if (PEND) goto invalid;
  PFETCH(c);
  if (c == ',') {
    UChar* prev = p;
    up = onig_scan_unsigned_number(&p, end, env->enc);
    if (up < 0) return ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE;
    if (up > ONIG_MAX_REPEAT_NUM)
      return ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE;

    if (p == prev) {
      if (non_low != 0)
	goto invalid;
      up = REPEAT_INFINITE;  /* {n,} : {n,infinite} */
    }
  }
  else {
    if (non_low != 0)
      goto invalid;

    PUNFETCH;
    up = low;  /* {n} : exact n times */
    r = 2;     /* fixed */
  }

  if (PEND) goto invalid;
  PFETCH(c);
  if (IS_SYNTAX_OP(env->syntax, ONIG_SYN_OP_ESC_BRACE_INTERVAL)) {
    if (c != MC_ESC(env->syntax)) goto invalid;
    if (PEND) goto invalid;
    PFETCH(c);
  }
  if (c != '}') goto invalid;

  if (!IS_REPEAT_INFINITE(up) && low > up) {
    return ONIGERR_UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE;
  }

  tok->type = TK_INTERVAL;
  tok->u.repeat.lower = low;
  tok->u.repeat.upper = up;
  *src = p;
  return r; /* 0: normal {n,m}, 2: fixed {n} */

 invalid:
  if (syn_allow)
    return 1;  /* OK */
  else
    return ONIGERR_INVALID_REPEAT_RANGE_PATTERN;
}

/* \M-, \C-, \c, or \... */
static int
fetch_escaped_value(UChar** src, UChar* end, ScanEnv* env, OnigCodePoint* val)
{
  int v;
  OnigCodePoint c;
  OnigEncoding enc = env->enc;
  UChar* p = *src;

  if (PEND) return ONIGERR_END_PATTERN_AT_ESCAPE;

  PFETCH_S(c);
  switch (c) {
  case 'M':
    if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_ESC_CAPITAL_M_BAR_META)) {
      if (PEND) return ONIGERR_END_PATTERN_AT_META;
      PFETCH_S(c);
      if (c != '-') return ONIGERR_META_CODE_SYNTAX;
      if (PEND) return ONIGERR_END_PATTERN_AT_META;
      PFETCH_S(c);
      if (c == MC_ESC(env->syntax)) {
	v = fetch_escaped_value(&p, end, env, &c);
	if (v < 0) return v;
      }
      c = ((c & 0xff) | 0x80);
    }
    else
      goto backslash;
    break;

  case 'C':
    if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_ESC_CAPITAL_C_BAR_CONTROL)) {
      if (PEND) return ONIGERR_END_PATTERN_AT_CONTROL;
      PFETCH_S(c);
      if (c != '-') return ONIGERR_CONTROL_CODE_SYNTAX;
      goto control;
    }
    else
      goto backslash;

  case 'c':
    if (IS_SYNTAX_OP(env->syntax, ONIG_SYN_OP_ESC_C_CONTROL)) {
    control:
      if (PEND) return ONIGERR_END_PATTERN_AT_CONTROL;
      PFETCH_S(c);
      if (c == '?') {
	c = 0177;
      }
      else {
	if (c == MC_ESC(env->syntax)) {
	  v = fetch_escaped_value(&p, end, env, &c);
	  if (v < 0) return v;
	}
	c &= 0x9f;
      }
      break;
    }
    /* fall through */

  default:
    {
    backslash:
      c = conv_backslash_value(c, env);
    }
    break;
  }

  *src = p;
  *val = c;
  return 0;
}

static int fetch_token(OnigToken* tok, UChar** src, UChar* end, ScanEnv* env);

static OnigCodePoint
get_name_end_code_point(OnigCodePoint start)
{
  switch (start) {
  case '<':  return (OnigCodePoint )'>'; break;
  case '\'': return (OnigCodePoint )'\''; break;
  case '(':  return (OnigCodePoint )')'; break;
  case '{':  return (OnigCodePoint )'}'; break;
  default:
    break;
  }

  return (OnigCodePoint )0;
}

#ifdef USE_NAMED_GROUP
# ifdef RUBY
#  define ONIGENC_IS_CODE_NAME(enc, c)  TRUE
# else
#  define ONIGENC_IS_CODE_NAME(enc, c)  ONIGENC_IS_CODE_WORD(enc, c)
# endif

# ifdef USE_BACKREF_WITH_LEVEL
/*
   \k<name+n>, \k<name-n>
   \k<num+n>,  \k<num-n>
   \k<-num+n>, \k<-num-n>
*/
static int
fetch_name_with_level(OnigCodePoint start_code, UChar** src, UChar* end,
		      UChar** rname_end, ScanEnv* env,
		      int* rback_num, int* rlevel)
{
  int r, sign, is_num, exist_level;
  OnigCodePoint end_code;
  OnigCodePoint c = 0;
  OnigEncoding enc = env->enc;
  UChar *name_end;
  UChar *pnum_head;
  UChar *p = *src;
  PFETCH_READY;

  *rback_num = 0;
  is_num = exist_level = 0;
  sign = 1;
  pnum_head = *src;

  end_code = get_name_end_code_point(start_code);

  name_end = end;
  r = 0;
  if (PEND) {
    return ONIGERR_EMPTY_GROUP_NAME;
  }
  else {
    PFETCH(c);
    if (c == end_code)
      return ONIGERR_EMPTY_GROUP_NAME;

    if (ONIGENC_IS_CODE_DIGIT(enc, c)) {
      is_num = 1;
    }
    else if (c == '-') {
      is_num = 2;
      sign = -1;
      pnum_head = p;
    }
    else if (!ONIGENC_IS_CODE_NAME(enc, c)) {
      r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
    }
  }

  while (!PEND) {
    name_end = p;
    PFETCH(c);
    if (c == end_code || c == ')' || c == '+' || c == '-') {
      if (is_num == 2) r = ONIGERR_INVALID_GROUP_NAME;
      break;
    }

    if (is_num != 0) {
      if (ONIGENC_IS_CODE_DIGIT(enc, c)) {
	is_num = 1;
      }
      else {
	r = ONIGERR_INVALID_GROUP_NAME;
	is_num = 0;
      }
    }
    else if (!ONIGENC_IS_CODE_NAME(enc, c)) {
      r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
    }
  }

  if (r == 0 && c != end_code) {
    if (c == '+' || c == '-') {
      int level;
      int flag = (c == '-' ? -1 : 1);

      if (PEND) {
	r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
	goto end;
      }
      PFETCH(c);
      if (! ONIGENC_IS_CODE_DIGIT(enc, c)) goto err;
      PUNFETCH;
      level = onig_scan_unsigned_number(&p, end, enc);
      if (level < 0) return ONIGERR_TOO_BIG_NUMBER;
      *rlevel = (level * flag);
      exist_level = 1;

      if (!PEND) {
	PFETCH(c);
	if (c == end_code)
	  goto end;
      }
    }

  err:
    r = ONIGERR_INVALID_GROUP_NAME;
    name_end = end;
  }

 end:
  if (r == 0) {
    if (is_num != 0) {
      *rback_num = onig_scan_unsigned_number(&pnum_head, name_end, enc);
      if (*rback_num < 0) return ONIGERR_TOO_BIG_NUMBER;
      else if (*rback_num == 0) goto err;

      *rback_num *= sign;
    }

    *rname_end = name_end;
    *src = p;
    return (exist_level ? 1 : 0);
  }
  else {
    onig_scan_env_set_error_string(env, r, *src, name_end);
    return r;
  }
}
# endif /* USE_BACKREF_WITH_LEVEL */

/*
  ref: 0 -> define name    (don't allow number name)
       1 -> reference name (allow number name)
*/
static int
fetch_name(OnigCodePoint start_code, UChar** src, UChar* end,
	   UChar** rname_end, ScanEnv* env, int* rback_num, int ref)
{
  int r, is_num, sign;
  OnigCodePoint end_code;
  OnigCodePoint c = 0;
  OnigEncoding enc = env->enc;
  UChar *name_end;
  UChar *pnum_head;
  UChar *p = *src;

  *rback_num = 0;

  end_code = get_name_end_code_point(start_code);

  name_end = end;
  pnum_head = *src;
  r = 0;
  is_num = 0;
  sign = 1;
  if (PEND) {
    return ONIGERR_EMPTY_GROUP_NAME;
  }
  else {
    PFETCH_S(c);
    if (c == end_code)
      return ONIGERR_EMPTY_GROUP_NAME;

    if (ONIGENC_IS_CODE_DIGIT(enc, c)) {
      if (ref == 1)
	is_num = 1;
      else {
	r = ONIGERR_INVALID_GROUP_NAME;
	is_num = 0;
      }
    }
    else if (c == '-') {
      if (ref == 1) {
	is_num = 2;
	sign = -1;
	pnum_head = p;
      }
      else {
	r = ONIGERR_INVALID_GROUP_NAME;
	is_num = 0;
      }
    }
    else if (!ONIGENC_IS_CODE_NAME(enc, c)) {
      r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
    }
  }

  if (r == 0) {
    while (!PEND) {
      name_end = p;
      PFETCH_S(c);
      if (c == end_code || c == ')') {
	if (is_num == 2) {
	  r = ONIGERR_INVALID_GROUP_NAME;
	  goto teardown;
	}
	break;
      }

      if (is_num != 0) {
	if (ONIGENC_IS_CODE_DIGIT(enc, c)) {
	  is_num = 1;
	}
	else {
	  if (!ONIGENC_IS_CODE_WORD(enc, c))
	    r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
	  else
	    r = ONIGERR_INVALID_GROUP_NAME;
	  goto teardown;
	}
      }
      else {
	if (!ONIGENC_IS_CODE_NAME(enc, c)) {
	  r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
	  goto teardown;
	}
      }
    }

    if (c != end_code) {
      r = ONIGERR_INVALID_GROUP_NAME;
      name_end = end;
      goto err;
    }

    if (is_num != 0) {
      *rback_num = onig_scan_unsigned_number(&pnum_head, name_end, enc);
      if (*rback_num < 0) return ONIGERR_TOO_BIG_NUMBER;
      else if (*rback_num == 0) {
	r = ONIGERR_INVALID_GROUP_NAME;
	goto err;
      }

      *rback_num *= sign;
    }

    *rname_end = name_end;
    *src = p;
    return 0;
  }
  else {
teardown:
    while (!PEND) {
      name_end = p;
      PFETCH_S(c);
      if (c == end_code || c == ')')
	break;
    }
    if (PEND)
      name_end = end;

  err:
    onig_scan_env_set_error_string(env, r, *src, name_end);
    return r;
  }
}
#else
static int
fetch_name(OnigCodePoint start_code, UChar** src, UChar* end,
	   UChar** rname_end, ScanEnv* env, int* rback_num, int ref)
{
  int r, is_num, sign;
  OnigCodePoint end_code;
  OnigCodePoint c = 0;
  UChar *name_end;
  OnigEncoding enc = env->enc;
  UChar *pnum_head;
  UChar *p = *src;
  PFETCH_READY;

  *rback_num = 0;

  end_code = get_name_end_code_point(start_code);

  *rname_end = name_end = end;
  r = 0;
  pnum_head = *src;
  is_num = 0;
  sign = 1;

  if (PEND) {
    return ONIGERR_EMPTY_GROUP_NAME;
  }
  else {
    PFETCH(c);
    if (c == end_code)
      return ONIGERR_EMPTY_GROUP_NAME;

    if (ONIGENC_IS_CODE_DIGIT(enc, c)) {
      is_num = 1;
    }
    else if (c == '-') {
      is_num = 2;
      sign = -1;
      pnum_head = p;
    }
    else {
      r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
    }
  }

  while (!PEND) {
    name_end = p;

    PFETCH(c);
    if (c == end_code || c == ')') break;
    if (! ONIGENC_IS_CODE_DIGIT(enc, c))
      r = ONIGERR_INVALID_CHAR_IN_GROUP_NAME;
  }
  if (r == 0 && c != end_code) {
    r = ONIGERR_INVALID_GROUP_NAME;
    name_end = end;
  }

  if (r == 0) {
    *rback_num = onig_scan_unsigned_number(&pnum_head, name_end, enc);
    if (*rback_num < 0) return ONIGERR_TOO_BIG_NUMBER;
    else if (*rback_num == 0) {
      r = ONIGERR_INVALID_GROUP_NAME;
      goto err;
    }
    *rback_num *= sign;

    *rname_end = name_end;
    *src = p;
    return 0;
  }
  else {
  err:
    onig_scan_env_set_error_string(env, r, *src, name_end);
    return r;
  }
}
#endif /* USE_NAMED_GROUP */


static void
onig_syntax_warn(ScanEnv *env, const char *fmt, ...)
{
    va_list args;
    UChar buf[WARN_BUFSIZE];
    va_start(args, fmt);
    onig_vsnprintf_with_pattern(buf, WARN_BUFSIZE, env->enc,
		env->pattern, env->pattern_end,
		(const UChar *)fmt, args);
    va_end(args);
#ifdef RUBY
    if (env->sourcefile == NULL)
      rb_warn("%s", (char *)buf);
    else
      rb_compile_warn(env->sourcefile, env->sourceline, "%s", (char *)buf);
#else
    (*onig_warn)((char* )buf);
#endif
}

static void
CC_ESC_WARN(ScanEnv *env, UChar *c)
{
  if (onig_warn == onig_null_warn) return ;

  if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_WARN_CC_OP_NOT_ESCAPED) &&
      IS_SYNTAX_BV(env->syntax, ONIG_SYN_BACKSLASH_ESCAPE_IN_CC)) {
    onig_syntax_warn(env, "character class has '%s' without escape", c);
  }
}

static void
CLOSE_BRACKET_WITHOUT_ESC_WARN(ScanEnv* env, UChar* c)
{
  if (onig_warn == onig_null_warn) return ;

  if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_WARN_CC_OP_NOT_ESCAPED)) {
    onig_syntax_warn(env, "regular expression has '%s' without escape", c);
  }
}

#ifndef RTEST
# define RTEST(v)  1
#endif

static void
CC_DUP_WARN(ScanEnv *env, OnigCodePoint from ARG_UNUSED, OnigCodePoint to ARG_UNUSED)
{
  if (onig_warn == onig_null_warn || !RTEST(ruby_verbose)) return ;

  if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_WARN_CC_DUP) &&
      !(env->warnings_flag & ONIG_SYN_WARN_CC_DUP)) {
#ifdef WARN_ALL_CC_DUP
    onig_syntax_warn(env, "character class has duplicated range: %04x-%04x", from, to);
#else
    env->warnings_flag |= ONIG_SYN_WARN_CC_DUP;
    onig_syntax_warn(env, "character class has duplicated range");
#endif
  }
}

static void
UNKNOWN_ESC_WARN(ScanEnv *env, int c)
{
  if (onig_warn == onig_null_warn || !RTEST(ruby_verbose)) return ;
  onig_syntax_warn(env, "Unknown escape \\%c is ignored", c);
}

static UChar*
find_str_position(OnigCodePoint s[], int n, UChar* from, UChar* to,
		  UChar **next, OnigEncoding enc)
{
  int i;
  OnigCodePoint x;
  UChar *q;
  UChar *p = from;

  while (p < to) {
    x = ONIGENC_MBC_TO_CODE(enc, p, to);
    q = p + enclen(enc, p, to);
    if (x == s[0]) {
      for (i = 1; i < n && q < to; i++) {
	x = ONIGENC_MBC_TO_CODE(enc, q, to);
	if (x != s[i]) break;
	q += enclen(enc, q, to);
      }
      if (i >= n) {
	if (IS_NOT_NULL(next))
	  *next = q;
	return p;
      }
    }
    p = q;
  }
  return NULL_UCHARP;
}

static int
str_exist_check_with_esc(OnigCodePoint s[], int n, UChar* from, UChar* to,
		 OnigCodePoint bad, OnigEncoding enc, const OnigSyntaxType* syn)
{
  int i, in_esc;
  OnigCodePoint x;
  UChar *q;
  UChar *p = from;

  in_esc = 0;
  while (p < to) {
    if (in_esc) {
      in_esc = 0;
      p += enclen(enc, p, to);
    }
    else {
      x = ONIGENC_MBC_TO_CODE(enc, p, to);
      q = p + enclen(enc, p, to);
      if (x == s[0]) {
	for (i = 1; i < n && q < to; i++) {
	  x = ONIGENC_MBC_TO_CODE(enc, q, to);
	  if (x != s[i]) break;
	  q += enclen(enc, q, to);
	}
	if (i >= n) return 1;
	p += enclen(enc, p, to);
      }
      else {
	x = ONIGENC_MBC_TO_CODE(enc, p, to);
	if (x == bad) return 0;
	else if (x == MC_ESC(syn)) in_esc = 1;
	p = q;
      }
    }
  }
  return 0;
}

static int
fetch_token_in_cc(OnigToken* tok, UChar** src, UChar* end, ScanEnv* env)
{
  int num;
  OnigCodePoint c, c2;
  const OnigSyntaxType* syn = env->syntax;
  OnigEncoding enc = env->enc;
  UChar* prev;
  UChar* p = *src;
  PFETCH_READY;

  if (PEND) {
    tok->type = TK_EOT;
    return tok->type;
  }

  PFETCH(c);
  tok->type = TK_CHAR;
  tok->base = 0;
  tok->u.c  = c;
  tok->escaped = 0;

  if (c == ']') {
    tok->type = TK_CC_CLOSE;
  }
  else if (c == '-') {
    tok->type = TK_CC_RANGE;
  }
  else if (c == MC_ESC(syn)) {
    if (! IS_SYNTAX_BV(syn, ONIG_SYN_BACKSLASH_ESCAPE_IN_CC))
      goto end;

    if (PEND) return ONIGERR_END_PATTERN_AT_ESCAPE;

    PFETCH(c);
    tok->escaped = 1;
    tok->u.c = c;
    switch (c) {
    case 'w':
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_WORD;
      tok->u.prop.not   = 0;
      break;
    case 'W':
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_WORD;
      tok->u.prop.not   = 1;
      break;
    case 'd':
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_DIGIT;
      tok->u.prop.not   = 0;
      break;
    case 'D':
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_DIGIT;
      tok->u.prop.not   = 1;
      break;
    case 's':
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_SPACE;
      tok->u.prop.not   = 0;
      break;
    case 'S':
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_SPACE;
      tok->u.prop.not   = 1;
      break;
    case 'h':
      if (! IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_H_XDIGIT)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_XDIGIT;
      tok->u.prop.not   = 0;
      break;
    case 'H':
      if (! IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_H_XDIGIT)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_XDIGIT;
      tok->u.prop.not   = 1;
      break;

    case 'p':
    case 'P':
      if (PEND) break;

      c2 = PPEEK;
      if (c2 == '{' &&
	  IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY)) {
	PINC;
	tok->type = TK_CHAR_PROPERTY;
	tok->u.prop.not = (c == 'P' ? 1 : 0);

	if (!PEND && IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT)) {
	  PFETCH(c2);
	  if (c2 == '^') {
	    tok->u.prop.not = (tok->u.prop.not == 0 ? 1 : 0);
	  }
	  else
	    PUNFETCH;
	}
      }
      else {
	onig_syntax_warn(env, "invalid Unicode Property \\%c", c);
      }
      break;

    case 'x':
      if (PEND) break;

      prev = p;
      if (PPEEK_IS('{') && IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_X_BRACE_HEX8)) {
	PINC;
	num = scan_unsigned_hexadecimal_number(&p, end, 0, 8, enc);
	if (num < 0) return ONIGERR_TOO_BIG_WIDE_CHAR_VALUE;
	if (!PEND) {
	  c2 = PPEEK;
	  if (ONIGENC_IS_CODE_XDIGIT(enc, c2))
	    return ONIGERR_TOO_LONG_WIDE_CHAR_VALUE;
	}

	if (p > prev + enclen(enc, prev, end) && !PEND && (PPEEK_IS('}'))) {
	  PINC;
	  tok->type   = TK_CODE_POINT;
	  tok->base   = 16;
	  tok->u.code = (OnigCodePoint )num;
	}
	else {
	  /* can't read nothing or invalid format */
	  p = prev;
	}
      }
      else if (IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_X_HEX2)) {
	num = scan_unsigned_hexadecimal_number(&p, end, 0, 2, enc);
	if (num < 0) return ONIGERR_TOO_BIG_NUMBER;
	if (p == prev) {  /* can't read nothing. */
	  num = 0; /* but, it's not error */
	}
	tok->type = TK_RAW_BYTE;
	tok->base = 16;
	tok->u.c  = num;
      }
      break;

    case 'u':
      if (PEND) break;

      prev = p;
      if (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_U_HEX4)) {
	num = scan_unsigned_hexadecimal_number(&p, end, 4, 4, enc);
	if (num < -1) return ONIGERR_TOO_SHORT_DIGITS;
	else if (num < 0) return ONIGERR_TOO_BIG_NUMBER;
	if (p == prev) {  /* can't read nothing. */
	  num = 0; /* but, it's not error */
	}
	tok->type   = TK_CODE_POINT;
	tok->base   = 16;
	tok->u.code = (OnigCodePoint )num;
      }
      break;

    case 'o':
      if (PEND) break;

      prev = p;
      if (PPEEK_IS('{') && IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_O_BRACE_OCTAL)) {
	PINC;
	num = scan_unsigned_octal_number(&p, end, 11, enc);
	if (num < 0) return ONIGERR_TOO_BIG_WIDE_CHAR_VALUE;
	if (!PEND) {
	  c2 = PPEEK;
	  if (ONIGENC_IS_CODE_DIGIT(enc, c2) && c2 < '8')
	    return ONIGERR_TOO_LONG_WIDE_CHAR_VALUE;
	}

	if (p > prev + enclen(enc, prev, end) && !PEND && (PPEEK_IS('}'))) {
	  PINC;
	  tok->type   = TK_CODE_POINT;
	  tok->base   = 8;
	  tok->u.code = (OnigCodePoint )num;
	}
	else {
	  /* can't read nothing or invalid format */
	  p = prev;
	}
      }
      break;

    case '0':
    case '1': case '2': case '3': case '4': case '5': case '6': case '7':
      if (IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_OCTAL3)) {
	PUNFETCH;
	prev = p;
	num = scan_unsigned_octal_number(&p, end, 3, enc);
	if (num < 0 || 0xff < num) return ONIGERR_TOO_BIG_NUMBER;
	if (p == prev) {  /* can't read nothing. */
	  num = 0; /* but, it's not error */
	}
	tok->type = TK_RAW_BYTE;
	tok->base = 8;
	tok->u.c  = num;
      }
      break;

    default:
      PUNFETCH;
      num = fetch_escaped_value(&p, end, env, &c2);
      if (num < 0) return num;
      if ((OnigCodePoint )tok->u.c != c2) {
	tok->u.code = (OnigCodePoint )c2;
	tok->type   = TK_CODE_POINT;
      }
      break;
    }
  }
  else if (c == '[') {
    if (IS_SYNTAX_OP(syn, ONIG_SYN_OP_POSIX_BRACKET) && (PPEEK_IS(':'))) {
      OnigCodePoint send[] = { (OnigCodePoint )':', (OnigCodePoint )']' };
      tok->backp = p; /* point at '[' is read */
      PINC;
      if (str_exist_check_with_esc(send, 2, p, end,
                                   (OnigCodePoint )']', enc, syn)) {
	tok->type = TK_POSIX_BRACKET_OPEN;
      }
      else {
	PUNFETCH;
	goto cc_in_cc;
      }
    }
    else {
    cc_in_cc:
      if (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_CCLASS_SET_OP)) {
	tok->type = TK_CC_CC_OPEN;
      }
      else {
	CC_ESC_WARN(env, (UChar* )"[");
      }
    }
  }
  else if (c == '&') {
    if (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_CCLASS_SET_OP) &&
	!PEND && (PPEEK_IS('&'))) {
      PINC;
      tok->type = TK_CC_AND;
    }
  }

 end:
  *src = p;
  return tok->type;
}

#ifdef USE_NAMED_GROUP
static int
fetch_named_backref_token(OnigCodePoint c, OnigToken* tok, UChar** src,
			  UChar* end, ScanEnv* env)
{
  int r, num;
  const OnigSyntaxType* syn = env->syntax;
  UChar* prev;
  UChar* p = *src;
  UChar* name_end;
  int* backs;
  int back_num;

  prev = p;

# ifdef USE_BACKREF_WITH_LEVEL
  name_end = NULL_UCHARP; /* no need. escape gcc warning. */
  r = fetch_name_with_level(c, &p, end, &name_end,
			    env, &back_num, &tok->u.backref.level);
  if (r == 1) tok->u.backref.exist_level = 1;
  else        tok->u.backref.exist_level = 0;
# else
  r = fetch_name(&p, end, &name_end, env, &back_num, 1);
# endif
  if (r < 0) return r;

  if (back_num != 0) {
    if (back_num < 0) {
      back_num = BACKREF_REL_TO_ABS(back_num, env);
      if (back_num <= 0)
	return ONIGERR_INVALID_BACKREF;
    }

    if (IS_SYNTAX_BV(syn, ONIG_SYN_STRICT_CHECK_BACKREF)) {
      if (back_num > env->num_mem ||
	  IS_NULL(SCANENV_MEM_NODES(env)[back_num]))
	return ONIGERR_INVALID_BACKREF;
    }
    tok->type = TK_BACKREF;
    tok->u.backref.by_name = 0;
    tok->u.backref.num  = 1;
    tok->u.backref.ref1 = back_num;
  }
  else {
    num = onig_name_to_group_numbers(env->reg, prev, name_end, &backs);
    if (num <= 0) {
      onig_scan_env_set_error_string(env,
		     ONIGERR_UNDEFINED_NAME_REFERENCE, prev, name_end);
      return ONIGERR_UNDEFINED_NAME_REFERENCE;
    }
    if (IS_SYNTAX_BV(syn, ONIG_SYN_STRICT_CHECK_BACKREF)) {
      int i;
      for (i = 0; i < num; i++) {
	if (backs[i] > env->num_mem ||
	    IS_NULL(SCANENV_MEM_NODES(env)[backs[i]]))
	  return ONIGERR_INVALID_BACKREF;
      }
    }

    tok->type = TK_BACKREF;
    tok->u.backref.by_name = 1;
    if (num == 1 || IS_SYNTAX_BV(syn, ONIG_SYN_USE_LEFT_MOST_NAMED_GROUP)) {
      tok->u.backref.num  = 1;
      tok->u.backref.ref1 = backs[0];
    }
    else {
      tok->u.backref.num  = num;
      tok->u.backref.refs = backs;
    }
  }
  *src = p;
  return 0;
}
#endif

static int
fetch_token(OnigToken* tok, UChar** src, UChar* end, ScanEnv* env)
{
  int r, num;
  OnigCodePoint c;
  OnigEncoding enc = env->enc;
  const OnigSyntaxType* syn = env->syntax;
  UChar* prev;
  UChar* p = *src;
  PFETCH_READY;

 start:
  if (PEND) {
    tok->type = TK_EOT;
    return tok->type;
  }

  tok->type  = TK_STRING;
  tok->base  = 0;
  tok->backp = p;

  PFETCH(c);
  if (IS_MC_ESC_CODE(c, syn)) {
    if (PEND) return ONIGERR_END_PATTERN_AT_ESCAPE;

    tok->backp = p;
    PFETCH(c);

    tok->u.c = c;
    tok->escaped = 1;
    switch (c) {
    case '*':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_ASTERISK_ZERO_INF)) break;
      tok->type = TK_OP_REPEAT;
      tok->u.repeat.lower = 0;
      tok->u.repeat.upper = REPEAT_INFINITE;
      goto greedy_check;
      break;

    case '+':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_PLUS_ONE_INF)) break;
      tok->type = TK_OP_REPEAT;
      tok->u.repeat.lower = 1;
      tok->u.repeat.upper = REPEAT_INFINITE;
      goto greedy_check;
      break;

    case '?':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_QMARK_ZERO_ONE)) break;
      tok->type = TK_OP_REPEAT;
      tok->u.repeat.lower = 0;
      tok->u.repeat.upper = 1;
    greedy_check:
      if (!PEND && PPEEK_IS('?') &&
	  IS_SYNTAX_OP(syn, ONIG_SYN_OP_QMARK_NON_GREEDY)) {
	PFETCH(c);
	tok->u.repeat.greedy     = 0;
	tok->u.repeat.possessive = 0;
      }
      else {
      possessive_check:
	if (!PEND && PPEEK_IS('+') &&
	    ((IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_PLUS_POSSESSIVE_REPEAT) &&
	      tok->type != TK_INTERVAL)  ||
	     (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_PLUS_POSSESSIVE_INTERVAL) &&
	      tok->type == TK_INTERVAL))) {
	  PFETCH(c);
	  tok->u.repeat.greedy     = 1;
	  tok->u.repeat.possessive = 1;
	}
	else {
	  tok->u.repeat.greedy     = 1;
	  tok->u.repeat.possessive = 0;
	}
      }
      break;

    case '{':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_BRACE_INTERVAL)) break;
      r = fetch_range_quantifier(&p, end, tok, env);
      if (r < 0) return r;  /* error */
      if (r == 0) goto greedy_check;
      else if (r == 2) { /* {n} */
	if (IS_SYNTAX_BV(syn, ONIG_SYN_FIXED_INTERVAL_IS_GREEDY_ONLY))
	  goto possessive_check;

	goto greedy_check;
      }
      /* r == 1 : normal char */
      break;

    case '|':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_VBAR_ALT)) break;
      tok->type = TK_ALT;
      break;

    case '(':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_LPAREN_SUBEXP)) break;
      tok->type = TK_SUBEXP_OPEN;
      break;

    case ')':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_LPAREN_SUBEXP)) break;
      tok->type = TK_SUBEXP_CLOSE;
      break;

    case 'w':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_W_WORD)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_WORD;
      tok->u.prop.not   = 0;
      break;

    case 'W':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_W_WORD)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_WORD;
      tok->u.prop.not   = 1;
      break;

    case 'b':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_B_WORD_BOUND)) break;
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = ANCHOR_WORD_BOUND;
      tok->u.anchor.ascii_range = IS_ASCII_RANGE(env->option)
		&& ! IS_WORD_BOUND_ALL_RANGE(env->option);
      break;

    case 'B':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_B_WORD_BOUND)) break;
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = ANCHOR_NOT_WORD_BOUND;
      tok->u.anchor.ascii_range = IS_ASCII_RANGE(env->option)
		&& ! IS_WORD_BOUND_ALL_RANGE(env->option);
      break;

#ifdef USE_WORD_BEGIN_END
    case '<':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END)) break;
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = ANCHOR_WORD_BEGIN;
      tok->u.anchor.ascii_range = IS_ASCII_RANGE(env->option);
      break;

    case '>':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_LTGT_WORD_BEGIN_END)) break;
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = ANCHOR_WORD_END;
      tok->u.anchor.ascii_range = IS_ASCII_RANGE(env->option);
      break;
#endif

    case 's':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_S_WHITE_SPACE)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_SPACE;
      tok->u.prop.not   = 0;
      break;

    case 'S':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_S_WHITE_SPACE)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_SPACE;
      tok->u.prop.not   = 1;
      break;

    case 'd':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_D_DIGIT)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_DIGIT;
      tok->u.prop.not   = 0;
      break;

    case 'D':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_D_DIGIT)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_DIGIT;
      tok->u.prop.not   = 1;
      break;

    case 'h':
      if (! IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_H_XDIGIT)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_XDIGIT;
      tok->u.prop.not   = 0;
      break;

    case 'H':
      if (! IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_H_XDIGIT)) break;
      tok->type = TK_CHAR_TYPE;
      tok->u.prop.ctype = ONIGENC_CTYPE_XDIGIT;
      tok->u.prop.not   = 1;
      break;

    case 'A':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR)) break;
    begin_buf:
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = ANCHOR_BEGIN_BUF;
      break;

    case 'Z':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR)) break;
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = ANCHOR_SEMI_END_BUF;
      break;

    case 'z':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_AZ_BUF_ANCHOR)) break;
    end_buf:
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = ANCHOR_END_BUF;
      break;

    case 'G':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_CAPITAL_G_BEGIN_ANCHOR)) break;
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = ANCHOR_BEGIN_POSITION;
      break;

    case '`':
      if (! IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_GNU_BUF_ANCHOR)) break;
      goto begin_buf;
      break;

    case '\'':
      if (! IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_GNU_BUF_ANCHOR)) break;
      goto end_buf;
      break;

    case 'x':
      if (PEND) break;

      prev = p;
      if (PPEEK_IS('{') && IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_X_BRACE_HEX8)) {
	PINC;
	num = scan_unsigned_hexadecimal_number(&p, end, 0, 8, enc);
	if (num < 0) return ONIGERR_TOO_BIG_WIDE_CHAR_VALUE;
	if (!PEND) {
	  if (ONIGENC_IS_CODE_XDIGIT(enc, PPEEK))
	    return ONIGERR_TOO_LONG_WIDE_CHAR_VALUE;
	}

	if ((p > prev + enclen(enc, prev, end)) && !PEND && PPEEK_IS('}')) {
	  PINC;
	  tok->type   = TK_CODE_POINT;
	  tok->u.code = (OnigCodePoint )num;
	}
	else {
	  /* can't read nothing or invalid format */
	  p = prev;
	}
      }
      else if (IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_X_HEX2)) {
	num = scan_unsigned_hexadecimal_number(&p, end, 0, 2, enc);
	if (num < 0) return ONIGERR_TOO_BIG_NUMBER;
	if (p == prev) {  /* can't read nothing. */
	  num = 0; /* but, it's not error */
	}
	tok->type = TK_RAW_BYTE;
	tok->base = 16;
	tok->u.c  = num;
      }
      break;

    case 'u':
      if (PEND) break;

      prev = p;
      if (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_U_HEX4)) {
	num = scan_unsigned_hexadecimal_number(&p, end, 4, 4, enc);
	if (num < -1) return ONIGERR_TOO_SHORT_DIGITS;
	else if (num < 0) return ONIGERR_TOO_BIG_NUMBER;
	if (p == prev) {  /* can't read nothing. */
	  num = 0; /* but, it's not error */
	}
	tok->type   = TK_CODE_POINT;
	tok->base   = 16;
	tok->u.code = (OnigCodePoint )num;
      }
      break;

    case 'o':
      if (PEND) break;

      prev = p;
      if (PPEEK_IS('{') && IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_O_BRACE_OCTAL)) {
	PINC;
	num = scan_unsigned_octal_number(&p, end, 11, enc);
	if (num < 0) return ONIGERR_TOO_BIG_WIDE_CHAR_VALUE;
	if (!PEND) {
	  OnigCodePoint c = PPEEK;
	  if (ONIGENC_IS_CODE_DIGIT(enc, c) && c < '8')
	    return ONIGERR_TOO_LONG_WIDE_CHAR_VALUE;
	}

	if ((p > prev + enclen(enc, prev, end)) && !PEND && PPEEK_IS('}')) {
	  PINC;
	  tok->type   = TK_CODE_POINT;
	  tok->u.code = (OnigCodePoint )num;
	}
	else {
	  /* can't read nothing or invalid format */
	  p = prev;
	}
      }
      break;

    case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8': case '9':
      PUNFETCH;
      prev = p;
      num = onig_scan_unsigned_number(&p, end, enc);
      if (num < 0 || num > ONIG_MAX_BACKREF_NUM) {
	goto skip_backref;
      }

      if (IS_SYNTAX_OP(syn, ONIG_SYN_OP_DECIMAL_BACKREF) &&
	  (num <= env->num_mem || num <= 9)) { /* This spec. from GNU regex */
	if (IS_SYNTAX_BV(syn, ONIG_SYN_STRICT_CHECK_BACKREF)) {
	  if (num > env->num_mem || IS_NULL(SCANENV_MEM_NODES(env)[num]))
	    return ONIGERR_INVALID_BACKREF;
	}

	tok->type = TK_BACKREF;
	tok->u.backref.num     = 1;
	tok->u.backref.ref1    = num;
	tok->u.backref.by_name = 0;
#ifdef USE_BACKREF_WITH_LEVEL
	tok->u.backref.exist_level = 0;
#endif
	break;
      }

    skip_backref:
      if (c == '8' || c == '9') {
	/* normal char */
	p = prev; PINC;
	break;
      }

      p = prev;
      /* fall through */
    case '0':
      if (IS_SYNTAX_OP(syn, ONIG_SYN_OP_ESC_OCTAL3)) {
	prev = p;
	num = scan_unsigned_octal_number(&p, end, (c == '0' ? 2:3), enc);
	if (num < 0 || 0xff < num) return ONIGERR_TOO_BIG_NUMBER;
	if (p == prev) {  /* can't read nothing. */
	  num = 0; /* but, it's not error */
	}
	tok->type = TK_RAW_BYTE;
	tok->base = 8;
	tok->u.c  = num;
      }
      else if (c != '0') {
	PINC;
      }
      break;

#ifdef USE_NAMED_GROUP
    case 'k':
      if (!PEND && IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_K_NAMED_BACKREF)) {
	PFETCH(c);
	if (c == '<' || c == '\'') {
	  r = fetch_named_backref_token(c, tok, &p, end, env);
	  if (r < 0) return r;
	}
	else {
	  PUNFETCH;
	  onig_syntax_warn(env, "invalid back reference");
	}
      }
      break;
#endif

#if defined(USE_SUBEXP_CALL) || defined(USE_NAMED_GROUP)
    case 'g':
# ifdef USE_NAMED_GROUP
      if (!PEND && IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_G_BRACE_BACKREF)) {
	PFETCH(c);
	if (c == '{') {
	  r = fetch_named_backref_token(c, tok, &p, end, env);
	  if (r < 0) return r;
	}
	else
	  PUNFETCH;
      }
# endif
# ifdef USE_SUBEXP_CALL
      if (!PEND && IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_G_SUBEXP_CALL)) {
	PFETCH(c);
	if (c == '<' || c == '\'') {
	  int gnum = -1, rel = 0;
	  UChar* name_end;
	  OnigCodePoint cnext;

	  cnext = PPEEK;
	  if (cnext == '0') {
	    PINC;
	    if (PPEEK_IS(get_name_end_code_point(c))) {  /* \g<0>, \g'0' */
	      PINC;
	      name_end = p;
	      gnum = 0;
	    }
	  }
	  else if (cnext == '+') {
	    PINC;
	    rel = 1;
	  }
	  prev = p;
	  if (gnum < 0) {
	    r = fetch_name((OnigCodePoint )c, &p, end, &name_end, env, &gnum, 1);
	    if (r < 0) return r;
	  }

	  tok->type = TK_CALL;
	  tok->u.call.name     = prev;
	  tok->u.call.name_end = name_end;
	  tok->u.call.gnum     = gnum;
	  tok->u.call.rel      = rel;
	}
	else {
	  onig_syntax_warn(env, "invalid subexp call");
	  PUNFETCH;
	}
      }
# endif
      break;
#endif

    case 'Q':
      if (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_CAPITAL_Q_QUOTE)) {
	tok->type = TK_QUOTE_OPEN;
      }
      break;

    case 'p':
    case 'P':
      if (PPEEK_IS('{') &&
	  IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_P_BRACE_CHAR_PROPERTY)) {
	PINC;
	tok->type = TK_CHAR_PROPERTY;
	tok->u.prop.not = (c == 'P' ? 1 : 0);

	if (!PEND && IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_P_BRACE_CIRCUMFLEX_NOT)) {
	  PFETCH(c);
	  if (c == '^') {
	    tok->u.prop.not = (tok->u.prop.not == 0 ? 1 : 0);
	  }
	  else
	    PUNFETCH;
	}
      }
      else {
	onig_syntax_warn(env, "invalid Unicode Property \\%c", c);
      }
      break;

    case 'R':
      if (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_CAPITAL_R_LINEBREAK)) {
	tok->type = TK_LINEBREAK;
      }
      break;

    case 'X':
      if (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER)) {
	tok->type = TK_EXTENDED_GRAPHEME_CLUSTER;
      }
      break;

    case 'K':
      if (IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_ESC_CAPITAL_K_KEEP)) {
	tok->type = TK_KEEP;
      }
      break;

    default:
      {
	OnigCodePoint c2;

	PUNFETCH;
	num = fetch_escaped_value(&p, end, env, &c2);
	if (num < 0) return num;
	/* set_raw: */
	if ((OnigCodePoint )tok->u.c != c2) {
	  tok->type = TK_CODE_POINT;
	  tok->u.code = (OnigCodePoint )c2;
	}
	else { /* string */
	  p = tok->backp + enclen(enc, tok->backp, end);
	}
      }
      break;
    }
  }
  else {
    tok->u.c = c;
    tok->escaped = 0;

#ifdef USE_VARIABLE_META_CHARS
    if ((c != ONIG_INEFFECTIVE_META_CHAR) &&
	IS_SYNTAX_OP(syn, ONIG_SYN_OP_VARIABLE_META_CHARACTERS)) {
      if (c == MC_ANYCHAR(syn))
	goto any_char;
      else if (c == MC_ANYTIME(syn))
	goto anytime;
      else if (c == MC_ZERO_OR_ONE_TIME(syn))
	goto zero_or_one_time;
      else if (c == MC_ONE_OR_MORE_TIME(syn))
	goto one_or_more_time;
      else if (c == MC_ANYCHAR_ANYTIME(syn)) {
	tok->type = TK_ANYCHAR_ANYTIME;
	goto out;
      }
    }
#endif

    switch (c) {
    case '.':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_DOT_ANYCHAR)) break;
#ifdef USE_VARIABLE_META_CHARS
    any_char:
#endif
      tok->type = TK_ANYCHAR;
      break;

    case '*':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_ASTERISK_ZERO_INF)) break;
#ifdef USE_VARIABLE_META_CHARS
    anytime:
#endif
      tok->type = TK_OP_REPEAT;
      tok->u.repeat.lower = 0;
      tok->u.repeat.upper = REPEAT_INFINITE;
      goto greedy_check;
      break;

    case '+':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_PLUS_ONE_INF)) break;
#ifdef USE_VARIABLE_META_CHARS
    one_or_more_time:
#endif
      tok->type = TK_OP_REPEAT;
      tok->u.repeat.lower = 1;
      tok->u.repeat.upper = REPEAT_INFINITE;
      goto greedy_check;
      break;

    case '?':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_QMARK_ZERO_ONE)) break;
#ifdef USE_VARIABLE_META_CHARS
    zero_or_one_time:
#endif
      tok->type = TK_OP_REPEAT;
      tok->u.repeat.lower = 0;
      tok->u.repeat.upper = 1;
      goto greedy_check;
      break;

    case '{':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_BRACE_INTERVAL)) break;
      r = fetch_range_quantifier(&p, end, tok, env);
      if (r < 0) return r;  /* error */
      if (r == 0) goto greedy_check;
      else if (r == 2) { /* {n} */
	if (IS_SYNTAX_BV(syn, ONIG_SYN_FIXED_INTERVAL_IS_GREEDY_ONLY))
	  goto possessive_check;

	goto greedy_check;
      }
      /* r == 1 : normal char */
      break;

    case '|':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_VBAR_ALT)) break;
      tok->type = TK_ALT;
      break;

    case '(':
      if (PPEEK_IS('?') &&
	  IS_SYNTAX_OP2(syn, ONIG_SYN_OP2_QMARK_GROUP_EFFECT)) {
	PINC;
	if (PPEEK_IS('#')) {
	  PFETCH(c);
	  while (1) {
	    if (PEND) return ONIGERR_END_PATTERN_IN_GROUP;
	    PFETCH(c);
	    if (c == MC_ESC(syn)) {
	      if (!PEND) PFETCH(c);
	    }
	    else {
	      if (c == ')') break;
	    }
	  }
	  goto start;
	}
#ifdef USE_PERL_SUBEXP_CALL
	/* (?&name), (?n), (?R), (?0), (?+n), (?-n) */
	c = PPEEK;
	if ((c == '&' || c == 'R' || ONIGENC_IS_CODE_DIGIT(enc, c)) &&
	    IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_SUBEXP_CALL)) {
	  /* (?&name), (?n), (?R), (?0) */
	  int gnum;
	  UChar *name;
	  UChar *name_end;

	  if (c == 'R' || c == '0') {
	    PINC;   /* skip 'R' / '0' */
	    if (!PPEEK_IS(')')) return ONIGERR_INVALID_GROUP_NAME;
	    PINC;   /* skip ')' */
	    name_end = name = p;
	    gnum = 0;
	  }
	  else {
	    int numref = 1;
	    if (c == '&') {     /* (?&name) */
	      PINC;
	      numref = 0;       /* don't allow number name */
	    }
	    name = p;
	    r = fetch_name((OnigCodePoint )'(', &p, end, &name_end, env, &gnum, numref);
	    if (r < 0) return r;
	  }

	  tok->type = TK_CALL;
	  tok->u.call.name     = name;
	  tok->u.call.name_end = name_end;
	  tok->u.call.gnum     = gnum;
	  tok->u.call.rel      = 0;
	  break;
	}
	else if ((c == '-' || c == '+') &&
	    IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_SUBEXP_CALL)) {
	  /* (?+n), (?-n) */
	  int gnum;
	  UChar *name;
	  UChar *name_end;
	  OnigCodePoint cnext;
	  PFETCH_READY;

	  PINC;     /* skip '-' / '+' */
	  cnext = PPEEK;
	  if (ONIGENC_IS_CODE_DIGIT(enc, cnext)) {
	    if (c == '-') PUNFETCH;
	    name = p;
	    r = fetch_name((OnigCodePoint )'(', &p, end, &name_end, env, &gnum, 1);
	    if (r < 0) return r;

	    tok->type = TK_CALL;
	    tok->u.call.name     = name;
	    tok->u.call.name_end = name_end;
	    tok->u.call.gnum     = gnum;
	    tok->u.call.rel      = 1;
	    break;
	  }
	}
#endif /* USE_PERL_SUBEXP_CALL */
#ifdef USE_CAPITAL_P_NAMED_GROUP
	if (PPEEK_IS('P') &&
	    IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_CAPITAL_P_NAMED_GROUP)) {
	  int gnum;
	  UChar *name;
	  UChar *name_end;
	  PFETCH_READY;

	  PINC;     /* skip 'P' */
	  if (PEND) return ONIGERR_UNDEFINED_GROUP_OPTION;
	  PFETCH(c);
	  if (c == '=') {       /* (?P=name): backref */
	    r = fetch_named_backref_token((OnigCodePoint )'(', tok, &p, end, env);
	    if (r < 0) return r;
	    break;
	  }
	  else if (c == '>') {  /* (?P>name): subexp call */
	    name = p;
	    r = fetch_name((OnigCodePoint )'(', &p, end, &name_end, env, &gnum, 0);
	    if (r < 0) return r;

	    tok->type = TK_CALL;
	    tok->u.call.name     = name;
	    tok->u.call.name_end = name_end;
	    tok->u.call.gnum     = gnum;
	    tok->u.call.rel      = 0;
	    break;
	  }
	}
#endif /* USE_CAPITAL_P_NAMED_GROUP */
	PUNFETCH;
      }

      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_LPAREN_SUBEXP)) break;
      tok->type = TK_SUBEXP_OPEN;
      break;

    case ')':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_LPAREN_SUBEXP)) break;
      tok->type = TK_SUBEXP_CLOSE;
      break;

    case '^':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_LINE_ANCHOR)) break;
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = (IS_SINGLELINE(env->option)
			       ? ANCHOR_BEGIN_BUF : ANCHOR_BEGIN_LINE);
      break;

    case '$':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_LINE_ANCHOR)) break;
      tok->type = TK_ANCHOR;
      tok->u.anchor.subtype = (IS_SINGLELINE(env->option)
			       ? ANCHOR_SEMI_END_BUF : ANCHOR_END_LINE);
      break;

    case '[':
      if (! IS_SYNTAX_OP(syn, ONIG_SYN_OP_BRACKET_CC)) break;
      tok->type = TK_CC_OPEN;
      break;

    case ']':
      if (*src > env->pattern)   /* /].../ is allowed. */
	CLOSE_BRACKET_WITHOUT_ESC_WARN(env, (UChar* )"]");
      break;

    case '#':
      if (IS_EXTEND(env->option)) {
	while (!PEND) {
	  PFETCH(c);
	  if (ONIGENC_IS_CODE_NEWLINE(enc, c))
	    break;
	}
	goto start;
	break;
      }
      break;

    case ' ': case '\t': case '\n': case '\r': case '\f':
      if (IS_EXTEND(env->option))
	goto start;
      break;

    default:
      /* string */
      break;
    }
  }

#ifdef USE_VARIABLE_META_CHARS
 out:
#endif
  *src = p;
  return tok->type;
}

static int
add_ctype_to_cc_by_range(CClassNode* cc, int ctype ARG_UNUSED, int not,
                         ScanEnv* env,
                         OnigCodePoint sb_out, const OnigCodePoint mbr[])
{
  int i, r;
  OnigCodePoint j;

  int n = ONIGENC_CODE_RANGE_NUM(mbr);

  if (not == 0) {
    for (i = 0; i < n; i++) {
      for (j = ONIGENC_CODE_RANGE_FROM(mbr, i);
	  j <= ONIGENC_CODE_RANGE_TO(mbr, i); j++) {
	if (j >= sb_out) {
	  if (j > ONIGENC_CODE_RANGE_FROM(mbr, i)) {
	    r = add_code_range_to_buf(&(cc->mbuf), env, j,
				      ONIGENC_CODE_RANGE_TO(mbr, i));
	    if (r != 0) return r;
	    i++;
	  }

	  goto sb_end;
	}
	BITSET_SET_BIT_CHKDUP(cc->bs, j);
      }
    }

  sb_end:
    for ( ; i < n; i++) {
      r = add_code_range_to_buf(&(cc->mbuf), env,
                                ONIGENC_CODE_RANGE_FROM(mbr, i),
                                ONIGENC_CODE_RANGE_TO(mbr, i));
      if (r != 0) return r;
    }
  }
  else {
    OnigCodePoint prev = 0;

    for (i = 0; i < n; i++) {
      for (j = prev;
	   j < ONIGENC_CODE_RANGE_FROM(mbr, i); j++) {
	if (j >= sb_out) {
	  goto sb_end2;
	}
	BITSET_SET_BIT_CHKDUP(cc->bs, j);
      }
      prev = ONIGENC_CODE_RANGE_TO(mbr, i) + 1;
    }
    for (j = prev; j < sb_out; j++) {
      BITSET_SET_BIT_CHKDUP(cc->bs, j);
    }

  sb_end2:
    prev = sb_out;

    for (i = 0; i < n; i++) {
      if (prev < ONIGENC_CODE_RANGE_FROM(mbr, i)) {
	r = add_code_range_to_buf(&(cc->mbuf), env, prev,
                                  ONIGENC_CODE_RANGE_FROM(mbr, i) - 1);
	if (r != 0) return r;
      }
      prev = ONIGENC_CODE_RANGE_TO(mbr, i) + 1;
    }
    if (prev < 0x7fffffff) {
      r = add_code_range_to_buf(&(cc->mbuf), env, prev, 0x7fffffff);
      if (r != 0) return r;
    }
  }

  return 0;
}

static int
add_ctype_to_cc(CClassNode* cc, int ctype, int not, int ascii_range, ScanEnv* env)
{
  int maxcode;
  int c, r;
  const OnigCodePoint *ranges;
  OnigCodePoint sb_out;
  OnigEncoding enc = env->enc;

  r = ONIGENC_GET_CTYPE_CODE_RANGE(enc, ctype, &sb_out, &ranges);
  if (r == 0) {
    if (ascii_range) {
      CClassNode ccwork;
      initialize_cclass(&ccwork);
      r = add_ctype_to_cc_by_range(&ccwork, ctype, not, env, sb_out,
				   ranges);
      if (r == 0) {
	if (not) {
	  r = add_code_range_to_buf0(&(ccwork.mbuf), env, 0x80, ONIG_LAST_CODE_POINT, FALSE);
	}
	else {
	  CClassNode ccascii;
	  initialize_cclass(&ccascii);
	  if (ONIGENC_MBC_MINLEN(env->enc) > 1) {
	    r = add_code_range(&(ccascii.mbuf), env, 0x00, 0x7F);
	  }
	  else {
	    bitset_set_range(env, ccascii.bs, 0x00, 0x7F);
	    r = 0;
	  }
	  if (r == 0) {
	    r = and_cclass(&ccwork, &ccascii, env);
	  }
	  if (IS_NOT_NULL(ccascii.mbuf)) bbuf_free(ccascii.mbuf);
	}
	if (r == 0) {
	  r = or_cclass(cc, &ccwork, env);
	}
	if (IS_NOT_NULL(ccwork.mbuf)) bbuf_free(ccwork.mbuf);
      }
    }
    else {
      r = add_ctype_to_cc_by_range(cc, ctype, not, env, sb_out, ranges);
    }
    return r;
  }
  else if (r != ONIG_NO_SUPPORT_CONFIG) {
    return r;
  }

  maxcode = ascii_range ? 0x80 : SINGLE_BYTE_SIZE;
  r = 0;
  switch (ctype) {
  case ONIGENC_CTYPE_ALPHA:
  case ONIGENC_CTYPE_BLANK:
  case ONIGENC_CTYPE_CNTRL:
  case ONIGENC_CTYPE_DIGIT:
  case ONIGENC_CTYPE_LOWER:
  case ONIGENC_CTYPE_PUNCT:
  case ONIGENC_CTYPE_SPACE:
  case ONIGENC_CTYPE_UPPER:
  case ONIGENC_CTYPE_XDIGIT:
  case ONIGENC_CTYPE_ASCII:
  case ONIGENC_CTYPE_ALNUM:
    if (not != 0) {
      for (c = 0; c < SINGLE_BYTE_SIZE; c++) {
	if (! ONIGENC_IS_CODE_CTYPE(enc, (OnigCodePoint )c, ctype))
	  BITSET_SET_BIT_CHKDUP(cc->bs, c);
      }
      ADD_ALL_MULTI_BYTE_RANGE(enc, cc->mbuf);
    }
    else {
      for (c = 0; c < SINGLE_BYTE_SIZE; c++) {
	if (ONIGENC_IS_CODE_CTYPE(enc, (OnigCodePoint )c, ctype))
	  BITSET_SET_BIT_CHKDUP(cc->bs, c);
      }
    }
    break;

  case ONIGENC_CTYPE_GRAPH:
  case ONIGENC_CTYPE_PRINT:
    if (not != 0) {
      for (c = 0; c < SINGLE_BYTE_SIZE; c++) {
	if (! ONIGENC_IS_CODE_CTYPE(enc, (OnigCodePoint )c, ctype)
	    || c >= maxcode)
	  BITSET_SET_BIT_CHKDUP(cc->bs, c);
      }
      if (ascii_range)
	ADD_ALL_MULTI_BYTE_RANGE(enc, cc->mbuf);
    }
    else {
      for (c = 0; c < maxcode; c++) {
	if (ONIGENC_IS_CODE_CTYPE(enc, (OnigCodePoint )c, ctype))
	  BITSET_SET_BIT_CHKDUP(cc->bs, c);
      }
      if (! ascii_range)
	ADD_ALL_MULTI_BYTE_RANGE(enc, cc->mbuf);
    }
    break;

  case ONIGENC_CTYPE_WORD:
    if (not == 0) {
      for (c = 0; c < maxcode; c++) {
	if (ONIGENC_IS_CODE_WORD(enc, c)) BITSET_SET_BIT_CHKDUP(cc->bs, c);
      }
      if (! ascii_range)
	ADD_ALL_MULTI_BYTE_RANGE(enc, cc->mbuf);
    }
    else {
      for (c = 0; c < SINGLE_BYTE_SIZE; c++) {
	if ((ONIGENC_CODE_TO_MBCLEN(enc, c) > 0) /* check invalid code point */
	    && (! ONIGENC_IS_CODE_WORD(enc, c) || c >= maxcode))
	  BITSET_SET_BIT_CHKDUP(cc->bs, c);
      }
      if (ascii_range)
	ADD_ALL_MULTI_BYTE_RANGE(enc, cc->mbuf);
    }
    break;

  default:
    return ONIGERR_PARSER_BUG;
    break;
  }

  return r;
}

static int
parse_posix_bracket(CClassNode* cc, CClassNode* asc_cc,
		    UChar** src, UChar* end, ScanEnv* env)
{
#define POSIX_BRACKET_CHECK_LIMIT_LENGTH  20
#define POSIX_BRACKET_NAME_MIN_LEN         4

  static const PosixBracketEntryType PBS[] = {
    POSIX_BRACKET_ENTRY_INIT("alnum",  ONIGENC_CTYPE_ALNUM),
    POSIX_BRACKET_ENTRY_INIT("alpha",  ONIGENC_CTYPE_ALPHA),
    POSIX_BRACKET_ENTRY_INIT("blank",  ONIGENC_CTYPE_BLANK),
    POSIX_BRACKET_ENTRY_INIT("cntrl",  ONIGENC_CTYPE_CNTRL),
    POSIX_BRACKET_ENTRY_INIT("digit",  ONIGENC_CTYPE_DIGIT),
    POSIX_BRACKET_ENTRY_INIT("graph",  ONIGENC_CTYPE_GRAPH),
    POSIX_BRACKET_ENTRY_INIT("lower",  ONIGENC_CTYPE_LOWER),
    POSIX_BRACKET_ENTRY_INIT("print",  ONIGENC_CTYPE_PRINT),
    POSIX_BRACKET_ENTRY_INIT("punct",  ONIGENC_CTYPE_PUNCT),
    POSIX_BRACKET_ENTRY_INIT("space",  ONIGENC_CTYPE_SPACE),
    POSIX_BRACKET_ENTRY_INIT("upper",  ONIGENC_CTYPE_UPPER),
    POSIX_BRACKET_ENTRY_INIT("xdigit", ONIGENC_CTYPE_XDIGIT),
    POSIX_BRACKET_ENTRY_INIT("ascii",  ONIGENC_CTYPE_ASCII),
    POSIX_BRACKET_ENTRY_INIT("word",   ONIGENC_CTYPE_WORD),
  };

  const PosixBracketEntryType *pb;
  int not, i, r;
  int ascii_range;
  OnigCodePoint c;
  OnigEncoding enc = env->enc;
  UChar *p = *src;

  if (PPEEK_IS('^')) {
    PINC_S;
    not = 1;
  }
  else
    not = 0;

  if (onigenc_strlen(enc, p, end) < POSIX_BRACKET_NAME_MIN_LEN + 3)
    goto not_posix_bracket;

  ascii_range = IS_ASCII_RANGE(env->option) &&
		  ! IS_POSIX_BRACKET_ALL_RANGE(env->option);
  for (pb = PBS; pb < PBS + numberof(PBS); pb++) {
    if (onigenc_with_ascii_strncmp(enc, p, end, pb->name, pb->len) == 0) {
      p = (UChar* )onigenc_step(enc, p, end, pb->len);
      if (onigenc_with_ascii_strncmp(enc, p, end, (UChar* )":]", 2) != 0)
	return ONIGERR_INVALID_POSIX_BRACKET_TYPE;

      r = add_ctype_to_cc(cc, pb->ctype, not, ascii_range, env);
      if (r != 0) return r;

      if (IS_NOT_NULL(asc_cc)) {
	if (pb->ctype != ONIGENC_CTYPE_WORD &&
	    pb->ctype != ONIGENC_CTYPE_ASCII &&
	    !ascii_range)
	  r = add_ctype_to_cc(asc_cc, pb->ctype, not, ascii_range, env);
	if (r != 0) return r;
      }

      PINC_S; PINC_S;
      *src = p;
      return 0;
    }
  }

 not_posix_bracket:
  c = 0;
  i = 0;
  while (!PEND && ((c = PPEEK) != ':') && c != ']') {
    PINC_S;
    if (++i > POSIX_BRACKET_CHECK_LIMIT_LENGTH) break;
  }
  if (c == ':' && ! PEND) {
    PINC_S;
    if (! PEND) {
      PFETCH_S(c);
      if (c == ']')
	return ONIGERR_INVALID_POSIX_BRACKET_TYPE;
    }
  }

  return 1;  /* 1: is not POSIX bracket, but no error. */
}

static int
fetch_char_property_to_ctype(UChar** src, UChar* end, ScanEnv* env)
{
  int r;
  OnigCodePoint c;
  OnigEncoding enc = env->enc;
  UChar *prev, *start, *p = *src;

  r = 0;
  start = prev = p;

  while (!PEND) {
    prev = p;
    PFETCH_S(c);
    if (c == '}') {
      r = ONIGENC_PROPERTY_NAME_TO_CTYPE(enc, start, prev);
      if (r < 0) break;

      *src = p;
      return r;
    }
    else if (c == '(' || c == ')' || c == '{' || c == '|') {
      r = ONIGERR_INVALID_CHAR_PROPERTY_NAME;
      break;
    }
  }

  onig_scan_env_set_error_string(env, r, *src, prev);
  return r;
}

static int cclass_case_fold(Node** np, CClassNode* cc, CClassNode* asc_cc, ScanEnv* env);

static int
parse_char_property(Node** np, OnigToken* tok, UChar** src, UChar* end,
		    ScanEnv* env)
{
  int r, ctype;
  CClassNode* cc;

  ctype = fetch_char_property_to_ctype(src, end, env);
  if (ctype < 0) return ctype;

  *np = node_new_cclass();
  CHECK_NULL_RETURN_MEMERR(*np);
  cc = NCCLASS(*np);
  r = add_ctype_to_cc(cc, ctype, 0, 0, env);
  if (r != 0) return r;
  if (tok->u.prop.not != 0) NCCLASS_SET_NOT(cc);

  if (IS_IGNORECASE(env->option)) {
    if (ctype != ONIGENC_CTYPE_ASCII)
      r = cclass_case_fold(np, cc, cc, env);
  }
  return r;
}


enum CCSTATE {
  CCS_VALUE,
  CCS_RANGE,
  CCS_COMPLETE,
  CCS_START
};

enum CCVALTYPE {
  CCV_SB,
  CCV_CODE_POINT,
  CCV_CLASS
};

static int
next_state_class(CClassNode* cc, CClassNode* asc_cc,
		 OnigCodePoint* vs, enum CCVALTYPE* type,
		 enum CCSTATE* state, ScanEnv* env)
{
  int r;

  if (*state == CCS_RANGE)
    return ONIGERR_CHAR_CLASS_VALUE_AT_END_OF_RANGE;

  if (*state == CCS_VALUE && *type != CCV_CLASS) {
    if (*type == CCV_SB) {
      BITSET_SET_BIT_CHKDUP(cc->bs, (int )(*vs));
      if (IS_NOT_NULL(asc_cc))
	BITSET_SET_BIT(asc_cc->bs, (int )(*vs));
    }
    else if (*type == CCV_CODE_POINT) {
      r = add_code_range(&(cc->mbuf), env, *vs, *vs);
      if (r < 0) return r;
      if (IS_NOT_NULL(asc_cc)) {
	r = add_code_range0(&(asc_cc->mbuf), env, *vs, *vs, 0);
	if (r < 0) return r;
      }
    }
  }

  *state = CCS_VALUE;
  *type  = CCV_CLASS;
  return 0;
}

static int
next_state_val(CClassNode* cc, CClassNode* asc_cc,
	       OnigCodePoint *from, OnigCodePoint to,
	       int* from_israw, int to_israw,
	       enum CCVALTYPE intype, enum CCVALTYPE* type,
	       enum CCSTATE* state, ScanEnv* env)
{
  int r;

  switch (*state) {
  case CCS_VALUE:
    if (*type == CCV_SB) {
      BITSET_SET_BIT_CHKDUP(cc->bs, (int )(*from));
      if (IS_NOT_NULL(asc_cc))
	BITSET_SET_BIT(asc_cc->bs, (int )(*from));
    }
    else if (*type == CCV_CODE_POINT) {
      r = add_code_range(&(cc->mbuf), env, *from, *from);
      if (r < 0) return r;
      if (IS_NOT_NULL(asc_cc)) {
	r = add_code_range0(&(asc_cc->mbuf), env, *from, *from, 0);
	if (r < 0) return r;
      }
    }
    break;

  case CCS_RANGE:
    if (intype == *type) {
      if (intype == CCV_SB) {
	if (*from > 0xff || to > 0xff)
	  return ONIGERR_INVALID_CODE_POINT_VALUE;

	if (*from > to) {
	  if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC))
	    goto ccs_range_end;
	  else
	    return ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS;
	}
	bitset_set_range(env, cc->bs, (int )*from, (int )to);
	if (IS_NOT_NULL(asc_cc))
	  bitset_set_range(env, asc_cc->bs, (int )*from, (int )to);
      }
      else {
	r = add_code_range(&(cc->mbuf), env, *from, to);
	if (r < 0) return r;
	if (IS_NOT_NULL(asc_cc)) {
	  r = add_code_range0(&(asc_cc->mbuf), env, *from, to, 0);
	  if (r < 0) return r;
	}
      }
    }
    else {
      if (*from > to) {
	if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_ALLOW_EMPTY_RANGE_IN_CC))
	  goto ccs_range_end;
	else
	  return ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS;
      }
      bitset_set_range(env, cc->bs, (int )*from, (int )(to < 0xff ? to : 0xff));
      r = add_code_range(&(cc->mbuf), env, (OnigCodePoint )*from, to);
      if (r < 0) return r;
      if (IS_NOT_NULL(asc_cc)) {
	bitset_set_range(env, asc_cc->bs, (int )*from, (int )(to < 0xff ? to : 0xff));
	r = add_code_range0(&(asc_cc->mbuf), env, (OnigCodePoint )*from, to, 0);
	if (r < 0) return r;
      }
    }
  ccs_range_end:
    *state = CCS_COMPLETE;
    break;

  case CCS_COMPLETE:
  case CCS_START:
    *state = CCS_VALUE;
    break;

  default:
    break;
  }

  *from_israw = to_israw;
  *from       = to;
  *type       = intype;
  return 0;
}

static int
code_exist_check(OnigCodePoint c, UChar* from, UChar* end, int ignore_escaped,
		 ScanEnv* env)
{
  int in_esc;
  OnigCodePoint code;
  OnigEncoding enc = env->enc;
  UChar* p = from;

  in_esc = 0;
  while (! PEND) {
    if (ignore_escaped && in_esc) {
      in_esc = 0;
    }
    else {
      PFETCH_S(code);
      if (code == c) return 1;
      if (code == MC_ESC(env->syntax)) in_esc = 1;
    }
  }
  return 0;
}

static int
parse_char_class(Node** np, Node** asc_np, OnigToken* tok, UChar** src, UChar* end,
		 ScanEnv* env)
{
  int r, neg, len, fetched, and_start;
  OnigCodePoint v, vs;
  UChar *p;
  Node* node;
  Node* asc_node;
  CClassNode *cc, *prev_cc;
  CClassNode *asc_cc, *asc_prev_cc;
  CClassNode work_cc, asc_work_cc;

  enum CCSTATE state;
  enum CCVALTYPE val_type, in_type;
  int val_israw, in_israw;

  *np = *asc_np = NULL_NODE;
  env->parse_depth++;
  if (env->parse_depth > ParseDepthLimit)
    return ONIGERR_PARSE_DEPTH_LIMIT_OVER;
  prev_cc = asc_prev_cc = (CClassNode* )NULL;
  r = fetch_token_in_cc(tok, src, end, env);
  if (r == TK_CHAR && tok->u.c == '^' && tok->escaped == 0) {
    neg = 1;
    r = fetch_token_in_cc(tok, src, end, env);
  }
  else {
    neg = 0;
  }

  if (r < 0) return r;
  if (r == TK_CC_CLOSE) {
    if (! code_exist_check((OnigCodePoint )']',
                           *src, env->pattern_end, 1, env))
      return ONIGERR_EMPTY_CHAR_CLASS;

    CC_ESC_WARN(env, (UChar* )"]");
    r = tok->type = TK_CHAR;  /* allow []...] */
  }

  *np = node = node_new_cclass();
  CHECK_NULL_RETURN_MEMERR(node);
  cc = NCCLASS(node);

  if (IS_IGNORECASE(env->option)) {
    *asc_np = asc_node = node_new_cclass();
    CHECK_NULL_RETURN_MEMERR(asc_node);
    asc_cc = NCCLASS(asc_node);
  }
  else {
    asc_node = NULL_NODE;
    asc_cc = NULL;
  }

  and_start = 0;
  state = CCS_START;
  p = *src;
  while (r != TK_CC_CLOSE) {
    fetched = 0;
    switch (r) {
    case TK_CHAR:
      if ((tok->u.code >= SINGLE_BYTE_SIZE) ||
	  (len = ONIGENC_CODE_TO_MBCLEN(env->enc, tok->u.c)) > 1) {
	in_type = CCV_CODE_POINT;
      }
      else if (len < 0) {
	r = len;
	goto err;
      }
      else {
      sb_char:
	in_type = CCV_SB;
      }
      v = (OnigCodePoint )tok->u.c;
      in_israw = 0;
      goto val_entry2;
      break;

    case TK_RAW_BYTE:
      /* tok->base != 0 : octal or hexadec. */
      if (! ONIGENC_IS_SINGLEBYTE(env->enc) && tok->base != 0) {
	UChar buf[ONIGENC_CODE_TO_MBC_MAXLEN];
	UChar* bufe = buf + ONIGENC_CODE_TO_MBC_MAXLEN;
	UChar* psave = p;
	int i, base = tok->base;

	buf[0] = (UChar )tok->u.c;
	for (i = 1; i < ONIGENC_MBC_MAXLEN(env->enc); i++) {
	  r = fetch_token_in_cc(tok, &p, end, env);
	  if (r < 0) goto err;
	  if (r != TK_RAW_BYTE || tok->base != base) {
	    fetched = 1;
	    break;
	  }
	  buf[i] = (UChar )tok->u.c;
	}

	if (i < ONIGENC_MBC_MINLEN(env->enc)) {
	  r = ONIGERR_TOO_SHORT_MULTI_BYTE_STRING;
	  goto err;
	}

	len = enclen(env->enc, buf, buf + i);
	if (i < len) {
	  r = ONIGERR_TOO_SHORT_MULTI_BYTE_STRING;
	  goto err;
	}
	else if (i > len) { /* fetch back */
	  p = psave;
	  for (i = 1; i < len; i++) {
	    (void)fetch_token_in_cc(tok, &p, end, env);
	    /* no need to check the retun value (already checked above) */
	  }
	  fetched = 0;
	}

	if (i == 1) {
	  v = (OnigCodePoint )buf[0];
	  goto raw_single;
	}
	else {
	  v = ONIGENC_MBC_TO_CODE(env->enc, buf, bufe);
	  in_type = CCV_CODE_POINT;
	}
      }
      else {
	v = (OnigCodePoint )tok->u.c;
      raw_single:
	in_type = CCV_SB;
      }
      in_israw = 1;
      goto val_entry2;
      break;

    case TK_CODE_POINT:
      v = tok->u.code;
      in_israw = 1;
    val_entry:
      len = ONIGENC_CODE_TO_MBCLEN(env->enc, v);
      if (len < 0) {
	r = len;
	goto err;
      }
      in_type = (len == 1 ? CCV_SB : CCV_CODE_POINT);
    val_entry2:
      r = next_state_val(cc, asc_cc, &vs, v, &val_israw, in_israw, in_type, &val_type,
			 &state, env);
      if (r != 0) goto err;
      break;

    case TK_POSIX_BRACKET_OPEN:
      r = parse_posix_bracket(cc, asc_cc, &p, end, env);
      if (r < 0) goto err;
      if (r == 1) {  /* is not POSIX bracket */
	CC_ESC_WARN(env, (UChar* )"[");
	p = tok->backp;
	v = (OnigCodePoint )tok->u.c;
	in_israw = 0;
	goto val_entry;
      }
      goto next_class;
      break;

    case TK_CHAR_TYPE:
      r = add_ctype_to_cc(cc, tok->u.prop.ctype, tok->u.prop.not,
			  IS_ASCII_RANGE(env->option), env);
      if (r != 0) return r;
      if (IS_NOT_NULL(asc_cc)) {
	if (tok->u.prop.ctype != ONIGENC_CTYPE_WORD)
	  r = add_ctype_to_cc(asc_cc, tok->u.prop.ctype, tok->u.prop.not,
			      IS_ASCII_RANGE(env->option), env);
	if (r != 0) return r;
      }

    next_class:
      r = next_state_class(cc, asc_cc, &vs, &val_type, &state, env);
      if (r != 0) goto err;
      break;

    case TK_CHAR_PROPERTY:
      {
	int ctype;

	ctype = fetch_char_property_to_ctype(&p, end, env);
	if (ctype < 0) return ctype;
	r = add_ctype_to_cc(cc, ctype, tok->u.prop.not, 0, env);
	if (r != 0) return r;
	if (IS_NOT_NULL(asc_cc)) {
	  if (ctype != ONIGENC_CTYPE_ASCII)
	    r = add_ctype_to_cc(asc_cc, ctype, tok->u.prop.not, 0, env);
	  if (r != 0) return r;
	}
	goto next_class;
      }
      break;

    case TK_CC_RANGE:
      if (state == CCS_VALUE) {
	r = fetch_token_in_cc(tok, &p, end, env);
	if (r < 0) goto err;
	fetched = 1;
	if (r == TK_CC_CLOSE) { /* allow [x-] */
	range_end_val:
	  v = (OnigCodePoint )'-';
	  in_israw = 0;
	  goto val_entry;
	}
	else if (r == TK_CC_AND) {
	  CC_ESC_WARN(env, (UChar* )"-");
	  goto range_end_val;
	}

	if (val_type == CCV_CLASS) {
	  r = ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS;
	  goto err;
	}

	state = CCS_RANGE;
      }
      else if (state == CCS_START) {
	/* [-xa] is allowed */
	v = (OnigCodePoint )tok->u.c;
	in_israw = 0;

	r = fetch_token_in_cc(tok, &p, end, env);
	if (r < 0) goto err;
	fetched = 1;
	/* [--x] or [a&&-x] is warned. */
	if (r == TK_CC_RANGE || and_start != 0)
	  CC_ESC_WARN(env, (UChar* )"-");

	goto val_entry;
      }
      else if (state == CCS_RANGE) {
	CC_ESC_WARN(env, (UChar* )"-");
	goto sb_char;  /* [!--x] is allowed */
      }
      else { /* CCS_COMPLETE */
	r = fetch_token_in_cc(tok, &p, end, env);
	if (r < 0) goto err;
	fetched = 1;
	if (r == TK_CC_CLOSE) goto range_end_val; /* allow [a-b-] */
	else if (r == TK_CC_AND) {
	  CC_ESC_WARN(env, (UChar* )"-");
	  goto range_end_val;
	}

	if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_ALLOW_DOUBLE_RANGE_OP_IN_CC)) {
	  CC_ESC_WARN(env, (UChar* )"-");
	  goto range_end_val;   /* [0-9-a] is allowed as [0-9\-a] */
	}
	r = ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS;
	goto err;
      }
      break;

    case TK_CC_CC_OPEN: /* [ */
      {
	Node *anode, *aasc_node;
	CClassNode* acc;

	r = parse_char_class(&anode, &aasc_node, tok, &p, end, env);
	if (r == 0) {
	  acc = NCCLASS(anode);
	  r = or_cclass(cc, acc, env);
	}
	if (r == 0 && IS_NOT_NULL(aasc_node)) {
	  acc = NCCLASS(aasc_node);
	  r = or_cclass(asc_cc, acc, env);
	}
	onig_node_free(anode);
	onig_node_free(aasc_node);
	if (r != 0) goto err;
      }
      break;

    case TK_CC_AND: /* && */
      {
	if (state == CCS_VALUE) {
	  r = next_state_val(cc, asc_cc, &vs, 0, &val_israw, 0, val_type,
			     &val_type, &state, env);
	  if (r != 0) goto err;
	}
	/* initialize local variables */
	and_start = 1;
	state = CCS_START;

	if (IS_NOT_NULL(prev_cc)) {
	  r = and_cclass(prev_cc, cc, env);
	  if (r != 0) goto err;
	  bbuf_free(cc->mbuf);
	  if (IS_NOT_NULL(asc_cc)) {
	    r = and_cclass(asc_prev_cc, asc_cc, env);
	    if (r != 0) goto err;
	    bbuf_free(asc_cc->mbuf);
	  }
	}
	else {
	  prev_cc = cc;
	  cc = &work_cc;
	  if (IS_NOT_NULL(asc_cc)) {
	    asc_prev_cc = asc_cc;
	    asc_cc = &asc_work_cc;
	  }
	}
	initialize_cclass(cc);
	if (IS_NOT_NULL(asc_cc))
	  initialize_cclass(asc_cc);
      }
      break;

    case TK_EOT:
      r = ONIGERR_PREMATURE_END_OF_CHAR_CLASS;
      goto err;
      break;
    default:
      r = ONIGERR_PARSER_BUG;
      goto err;
      break;
    }

    if (fetched)
      r = tok->type;
    else {
      r = fetch_token_in_cc(tok, &p, end, env);
      if (r < 0) goto err;
    }
  }

  if (state == CCS_VALUE) {
    r = next_state_val(cc, asc_cc, &vs, 0, &val_israw, 0, val_type,
		       &val_type, &state, env);
    if (r != 0) goto err;
  }

  if (IS_NOT_NULL(prev_cc)) {
    r = and_cclass(prev_cc, cc, env);
    if (r != 0) goto err;
    bbuf_free(cc->mbuf);
    cc = prev_cc;
    if (IS_NOT_NULL(asc_cc)) {
      r = and_cclass(asc_prev_cc, asc_cc, env);
      if (r != 0) goto err;
      bbuf_free(asc_cc->mbuf);
      asc_cc = asc_prev_cc;
    }
  }

  if (neg != 0) {
    NCCLASS_SET_NOT(cc);
    if (IS_NOT_NULL(asc_cc))
      NCCLASS_SET_NOT(asc_cc);
  }
  else {
    NCCLASS_CLEAR_NOT(cc);
    if (IS_NOT_NULL(asc_cc))
      NCCLASS_CLEAR_NOT(asc_cc);
  }
  if (IS_NCCLASS_NOT(cc) &&
      IS_SYNTAX_BV(env->syntax, ONIG_SYN_NOT_NEWLINE_IN_NEGATIVE_CC)) {
    int is_empty;

    is_empty = (IS_NULL(cc->mbuf) ? 1 : 0);
    if (is_empty != 0)
      BITSET_IS_EMPTY(cc->bs, is_empty);

    if (is_empty == 0) {
#define NEWLINE_CODE    0x0a

      if (ONIGENC_IS_CODE_NEWLINE(env->enc, NEWLINE_CODE)) {
	if (ONIGENC_CODE_TO_MBCLEN(env->enc, NEWLINE_CODE) == 1)
	  BITSET_SET_BIT_CHKDUP(cc->bs, NEWLINE_CODE);
	else {
	  r = add_code_range(&(cc->mbuf), env, NEWLINE_CODE, NEWLINE_CODE);
	  if (r < 0) goto err;
	}
      }
    }
  }
  *src = p;
  env->parse_depth--;
  return 0;

 err:
  if (cc != NCCLASS(*np))
    bbuf_free(cc->mbuf);
  if (IS_NOT_NULL(asc_cc) && (asc_cc != NCCLASS(*asc_np)))
    bbuf_free(asc_cc->mbuf);
  return r;
}

static int parse_subexp(Node** top, OnigToken* tok, int term,
			UChar** src, UChar* end, ScanEnv* env);

static int
parse_enclose(Node** np, OnigToken* tok, int term, UChar** src, UChar* end,
	      ScanEnv* env)
{
  int r = 0, num;
  Node *target, *work1 = NULL, *work2 = NULL;
  OnigOptionType option;
  OnigCodePoint c;
  OnigEncoding enc = env->enc;

#ifdef USE_NAMED_GROUP
  int list_capture;
#endif

  UChar* p = *src;
  PFETCH_READY;

  *np = NULL;
  if (PEND) return ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS;

  option = env->option;
  if (PPEEK_IS('?') &&
      IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_GROUP_EFFECT)) {
    PINC;
    if (PEND) return ONIGERR_END_PATTERN_IN_GROUP;

    PFETCH(c);
    switch (c) {
    case ':':   /* (?:...) grouping only */
    group:
      r = fetch_token(tok, &p, end, env);
      if (r < 0) return r;
      r = parse_subexp(np, tok, term, &p, end, env);
      if (r < 0) return r;
      *src = p;
      return 1; /* group */
      break;

    case '=':
      *np = onig_node_new_anchor(ANCHOR_PREC_READ);
      break;
    case '!':   /* preceding read */
      *np = onig_node_new_anchor(ANCHOR_PREC_READ_NOT);
      break;
    case '>':   /* (?>...) stop backtrack */
      *np = node_new_enclose(ENCLOSE_STOP_BACKTRACK);
      break;
    case '~':   /* (?~...) absent operator */
      if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_TILDE_ABSENT)) {
	*np = node_new_enclose(ENCLOSE_ABSENT);
      }
      else {
	return ONIGERR_UNDEFINED_GROUP_OPTION;
      }
      break;

#ifdef USE_NAMED_GROUP
    case '\'':
      if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP)) {
	goto named_group1;
      }
      else
	return ONIGERR_UNDEFINED_GROUP_OPTION;
      break;

# ifdef USE_CAPITAL_P_NAMED_GROUP
    case 'P':   /* (?P<name>...) */
      if (!PEND &&
	  IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_CAPITAL_P_NAMED_GROUP)) {
	PFETCH(c);
	if (c == '<') goto named_group1;
      }
      return ONIGERR_UNDEFINED_GROUP_OPTION;
      break;
# endif
#endif

    case '<':   /* look behind (?<=...), (?<!...) */
      if (PEND) return ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS;
      PFETCH(c);
      if (c == '=')
	*np = onig_node_new_anchor(ANCHOR_LOOK_BEHIND);
      else if (c == '!')
	*np = onig_node_new_anchor(ANCHOR_LOOK_BEHIND_NOT);
#ifdef USE_NAMED_GROUP
      else {    /* (?<name>...) */
	if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP)) {
	  UChar *name;
	  UChar *name_end;

	  PUNFETCH;
	  c = '<';

	named_group1:
	  list_capture = 0;

# ifdef USE_CAPTURE_HISTORY
	named_group2:
# endif
	  name = p;
	  r = fetch_name((OnigCodePoint )c, &p, end, &name_end, env, &num, 0);
	  if (r < 0) return r;

	  num = scan_env_add_mem_entry(env);
	  if (num < 0) return num;
	  if (list_capture != 0 && num >= (int )BIT_STATUS_BITS_NUM)
	    return ONIGERR_GROUP_NUMBER_OVER_FOR_CAPTURE_HISTORY;

	  r = name_add(env->reg, name, name_end, num, env);
	  if (r != 0) return r;
	  *np = node_new_enclose_memory(env->option, 1);
	  CHECK_NULL_RETURN_MEMERR(*np);
	  NENCLOSE(*np)->regnum = num;
	  if (list_capture != 0)
	    BIT_STATUS_ON_AT_SIMPLE(env->capture_history, num);
	  env->num_named++;
	}
	else {
	  return ONIGERR_UNDEFINED_GROUP_OPTION;
	}
      }
#else
      else {
	return ONIGERR_UNDEFINED_GROUP_OPTION;
      }
#endif
      break;

#ifdef USE_CAPTURE_HISTORY
    case '@':
      if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_ATMARK_CAPTURE_HISTORY)) {
# ifdef USE_NAMED_GROUP
	if (!PEND &&
	    IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_LT_NAMED_GROUP)) {
	  PFETCH(c);
	  if (c == '<' || c == '\'') {
	    list_capture = 1;
	    goto named_group2; /* (?@<name>...) */
	  }
	  PUNFETCH;
	}
# endif
	*np = node_new_enclose_memory(env->option, 0);
	CHECK_NULL_RETURN_MEMERR(*np);
	num = scan_env_add_mem_entry(env);
	if (num < 0) return num;
	if (num >= (int )BIT_STATUS_BITS_NUM)
	  return ONIGERR_GROUP_NUMBER_OVER_FOR_CAPTURE_HISTORY;

	NENCLOSE(*np)->regnum = num;
	BIT_STATUS_ON_AT_SIMPLE(env->capture_history, num);
      }
      else {
	return ONIGERR_UNDEFINED_GROUP_OPTION;
      }
      break;
#endif /* USE_CAPTURE_HISTORY */

    case '(':   /* conditional expression: (?(cond)yes), (?(cond)yes|no) */
      if (!PEND &&
	  IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_LPAREN_CONDITION)) {
	UChar *name = NULL;
	UChar *name_end;
	PFETCH(c);
	if (ONIGENC_IS_CODE_DIGIT(enc, c)) {     /* (n) */
	  PUNFETCH;
	  r = fetch_name((OnigCodePoint )'(', &p, end, &name_end, env, &num, 1);
	  if (r < 0) return r;
#if 0
	  /* Relative number is not currently supported. (same as Perl) */
	  if (num < 0) {
	    num = BACKREF_REL_TO_ABS(num, env);
	    if (num <= 0)
	      return ONIGERR_INVALID_BACKREF;
	  }
#endif
	  if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_STRICT_CHECK_BACKREF)) {
	    if (num > env->num_mem ||
		IS_NULL(SCANENV_MEM_NODES(env)[num]))
	    return ONIGERR_INVALID_BACKREF;
	  }
	}
#ifdef USE_NAMED_GROUP
	else if (c == '<' || c == '\'') {    /* (<name>), ('name') */
	  name = p;
	  r = fetch_named_backref_token(c, tok, &p, end, env);
	  if (r < 0) return r;
	  if (!PPEEK_IS(')')) return ONIGERR_UNDEFINED_GROUP_OPTION;
	  PINC;

	  if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_USE_LEFT_MOST_NAMED_GROUP)) {
	    num = tok->u.backref.ref1;
	  }
	  else {
	    /* FIXME:
	     * Use left most named group for now. This is the same as Perl.
	     * However this should use the same strategy as normal back-
	     * references on Ruby syntax; search right to left. */
	    int len = tok->u.backref.num;
	    num = len > 1 ? tok->u.backref.refs[0] : tok->u.backref.ref1;
	  }
	}
#endif
	else
	  return ONIGERR_INVALID_CONDITION_PATTERN;
	*np = node_new_enclose(ENCLOSE_CONDITION);
	CHECK_NULL_RETURN_MEMERR(*np);
	NENCLOSE(*np)->regnum = num;
	if (IS_NOT_NULL(name)) NENCLOSE(*np)->state |= NST_NAME_REF;
      }
      else
	return ONIGERR_UNDEFINED_GROUP_OPTION;
      break;

#if 0
    case '|':   /* branch reset: (?|...) */
      if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_QMARK_VBAR_BRANCH_RESET)) {
	/* TODO */
      }
      else
	return ONIGERR_UNDEFINED_GROUP_OPTION;
      break;
#endif

    case '^':   /* loads default options */
      if (!PEND && IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_PERL)) {
	/* d-imsx */
	ONOFF(option, ONIG_OPTION_ASCII_RANGE, 1);
	ONOFF(option, ONIG_OPTION_IGNORECASE, 1);
	ONOFF(option, ONIG_OPTION_SINGLELINE, 0);
	ONOFF(option, ONIG_OPTION_MULTILINE,  1);
	ONOFF(option, ONIG_OPTION_EXTEND, 1);
	PFETCH(c);
      }
#if 0
      else if (!PEND && IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_RUBY)) {
	/* d-imx */
	ONOFF(option, ONIG_OPTION_ASCII_RANGE, 0);
	ONOFF(option, ONIG_OPTION_POSIX_BRACKET_ALL_RANGE, 0);
	ONOFF(option, ONIG_OPTION_WORD_BOUND_ALL_RANGE, 0);
	ONOFF(option, ONIG_OPTION_IGNORECASE, 1);
	ONOFF(option, ONIG_OPTION_MULTILINE,  1);
	ONOFF(option, ONIG_OPTION_EXTEND, 1);
	PFETCH(c);
      }
#endif
      else {
	return ONIGERR_UNDEFINED_GROUP_OPTION;
      }
      /* fall through */
#ifdef USE_POSIXLINE_OPTION
    case 'p':
#endif
    case '-': case 'i': case 'm': case 's': case 'x':
    case 'a': case 'd': case 'l': case 'u':
      {
	int neg = 0;

	while (1) {
	  switch (c) {
	  case ':':
	  case ')':
	  break;

	  case '-':  neg = 1; break;
	  case 'x':  ONOFF(option, ONIG_OPTION_EXTEND,     neg); break;
	  case 'i':  ONOFF(option, ONIG_OPTION_IGNORECASE, neg); break;
	  case 's':
	    if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_PERL)) {
	      ONOFF(option, ONIG_OPTION_MULTILINE,  neg);
	    }
	    else
	      return ONIGERR_UNDEFINED_GROUP_OPTION;
	    break;

	  case 'm':
	    if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_PERL)) {
	      ONOFF(option, ONIG_OPTION_SINGLELINE, (neg == 0 ? 1 : 0));
	    }
	    else if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_RUBY)) {
	      ONOFF(option, ONIG_OPTION_MULTILINE,  neg);
	    }
	    else
	      return ONIGERR_UNDEFINED_GROUP_OPTION;
	    break;
#ifdef USE_POSIXLINE_OPTION
	  case 'p':
	    ONOFF(option, ONIG_OPTION_MULTILINE|ONIG_OPTION_SINGLELINE, neg);
	    break;
#endif

	  case 'a':     /* limits \d, \s, \w and POSIX brackets to ASCII range */
	    if ((IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_PERL) ||
		 IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_RUBY)) &&
		(neg == 0)) {
	      ONOFF(option, ONIG_OPTION_ASCII_RANGE, 0);
	      ONOFF(option, ONIG_OPTION_POSIX_BRACKET_ALL_RANGE, 1);
	      ONOFF(option, ONIG_OPTION_WORD_BOUND_ALL_RANGE, 1);
	    }
	    else
	      return ONIGERR_UNDEFINED_GROUP_OPTION;
	    break;

	  case 'u':
	    if ((IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_PERL) ||
		 IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_RUBY)) &&
		(neg == 0)) {
	      ONOFF(option, ONIG_OPTION_ASCII_RANGE, 1);
	      ONOFF(option, ONIG_OPTION_POSIX_BRACKET_ALL_RANGE, 1);
	      ONOFF(option, ONIG_OPTION_WORD_BOUND_ALL_RANGE, 1);
	    }
	    else
	      return ONIGERR_UNDEFINED_GROUP_OPTION;
	    break;

	  case 'd':
	    if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_PERL) &&
		(neg == 0)) {
	      ONOFF(option, ONIG_OPTION_ASCII_RANGE, 1);
	    }
	    else if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_RUBY) &&
		(neg == 0)) {
	      ONOFF(option, ONIG_OPTION_ASCII_RANGE, 0);
	      ONOFF(option, ONIG_OPTION_POSIX_BRACKET_ALL_RANGE, 0);
	      ONOFF(option, ONIG_OPTION_WORD_BOUND_ALL_RANGE, 0);
	    }
	    else
	      return ONIGERR_UNDEFINED_GROUP_OPTION;
	    break;

	  case 'l':
	    if (IS_SYNTAX_OP2(env->syntax, ONIG_SYN_OP2_OPTION_PERL) && (neg == 0)) {
	      ONOFF(option, ONIG_OPTION_ASCII_RANGE, 1);
	    }
	    else
	      return ONIGERR_UNDEFINED_GROUP_OPTION;
	    break;

	  default:
	    return ONIGERR_UNDEFINED_GROUP_OPTION;
	  }

	  if (c == ')') {
	    *np = node_new_option(option);
	    CHECK_NULL_RETURN_MEMERR(*np);
	    *src = p;
	    return 2; /* option only */
	  }
	  else if (c == ':') {
	    OnigOptionType prev = env->option;

	    env->option = option;
	    r = fetch_token(tok, &p, end, env);
	    if (r < 0) {
	      env->option = prev;
	      return r;
	    }
	    r = parse_subexp(&target, tok, term, &p, end, env);
	    env->option = prev;
	    if (r < 0) return r;
	    *np = node_new_option(option);
	    CHECK_NULL_RETURN_MEMERR(*np);
	    NENCLOSE(*np)->target = target;
	    *src = p;
	    return 0;
	  }

	  if (PEND) return ONIGERR_END_PATTERN_IN_GROUP;
	  PFETCH(c);
	}
      }
      break;

    default:
      return ONIGERR_UNDEFINED_GROUP_OPTION;
    }
  }
  else {
    if (ONIG_IS_OPTION_ON(env->option, ONIG_OPTION_DONT_CAPTURE_GROUP))
      goto group;

    *np = node_new_enclose_memory(env->option, 0);
    CHECK_NULL_RETURN_MEMERR(*np);
    num = scan_env_add_mem_entry(env);
    if (num < 0) return num;
    NENCLOSE(*np)->regnum = num;
  }

  CHECK_NULL_RETURN_MEMERR(*np);
  r = fetch_token(tok, &p, end, env);
  if (r < 0) return r;
  r = parse_subexp(&target, tok, term, &p, end, env);
  if (r < 0) {
    onig_node_free(target);
    return r;
  }

  if (NTYPE(*np) == NT_ANCHOR)
    NANCHOR(*np)->target = target;
  else {
    NENCLOSE(*np)->target = target;
    if (NENCLOSE(*np)->type == ENCLOSE_MEMORY) {
      /* Don't move this to previous of parse_subexp() */
      r = scan_env_set_mem_node(env, NENCLOSE(*np)->regnum, *np);
      if (r != 0) return r;
    }
    else if (NENCLOSE(*np)->type == ENCLOSE_CONDITION) {
      if (NTYPE(target) != NT_ALT) {
	/* convert (?(cond)yes) to (?(cond)yes|empty) */
	work1 = node_new_empty();
	if (IS_NULL(work1)) goto err;
	work2 = onig_node_new_alt(work1, NULL_NODE);
	if (IS_NULL(work2)) goto err;
	work1 = onig_node_new_alt(target, work2);
	if (IS_NULL(work1)) goto err;
	NENCLOSE(*np)->target = work1;
      }
    }
  }

  *src = p;
  return 0;

 err:
  onig_node_free(work1);
  onig_node_free(work2);
  onig_node_free(*np);
  *np = NULL;
  return ONIGERR_MEMORY;
}

static const char* const PopularQStr[] = {
  "?", "*", "+", "??", "*?", "+?"
};

static const char* const ReduceQStr[] = {
  "", "", "*", "*?", "??", "+ and ??", "+? and ?"
};

static int
set_quantifier(Node* qnode, Node* target, int group, ScanEnv* env)
{
  QtfrNode* qn;

  qn = NQTFR(qnode);
  if (qn->lower == 1 && qn->upper == 1) {
    return 1;
  }

  switch (NTYPE(target)) {
  case NT_STR:
    if (! group) {
      StrNode* sn = NSTR(target);
      if (str_node_can_be_split(sn, env->enc)) {
	Node* n = str_node_split_last_char(sn, env->enc);
	if (IS_NOT_NULL(n)) {
	  qn->target = n;
	  return 2;
	}
      }
    }
    break;

  case NT_QTFR:
    { /* check redundant double repeat. */
      /* verbose warn (?:.?)? etc... but not warn (.?)? etc... */
      QtfrNode* qnt   = NQTFR(target);
      int nestq_num   = popular_quantifier_num(qn);
      int targetq_num = popular_quantifier_num(qnt);

#ifdef USE_WARNING_REDUNDANT_NESTED_REPEAT_OPERATOR
      if (nestq_num >= 0 && targetq_num >= 0 &&
	  IS_SYNTAX_BV(env->syntax, ONIG_SYN_WARN_REDUNDANT_NESTED_REPEAT)) {
	switch (ReduceTypeTable[targetq_num][nestq_num]) {
	case RQ_ASIS:
	  break;

	case RQ_DEL:
	  if (onig_warn != onig_null_warn) {
	    onig_syntax_warn(env, "regular expression has redundant nested repeat operator '%s'",
		PopularQStr[targetq_num]);
	  }
	  goto warn_exit;
	  break;

	default:
	  if (onig_warn != onig_null_warn) {
	    onig_syntax_warn(env, "nested repeat operator '%s' and '%s' was replaced with '%s' in regular expression",
		PopularQStr[targetq_num], PopularQStr[nestq_num],
		ReduceQStr[ReduceTypeTable[targetq_num][nestq_num]]);
	  }
	  goto warn_exit;
	  break;
	}
      }

    warn_exit:
#endif
      if (targetq_num >= 0) {
	if (nestq_num >= 0) {
	  onig_reduce_nested_quantifier(qnode, target);
	  goto q_exit;
	}
	else if (targetq_num == 1 || targetq_num == 2) { /* * or + */
	  /* (?:a*){n,m}, (?:a+){n,m} => (?:a*){n,n}, (?:a+){n,n} */
	  if (! IS_REPEAT_INFINITE(qn->upper) && qn->upper > 1 && qn->greedy) {
	    qn->upper = (qn->lower == 0 ? 1 : qn->lower);
	  }
	}
      }
    }
    break;

  default:
    break;
  }

  qn->target = target;
 q_exit:
  return 0;
}


#ifndef CASE_FOLD_IS_APPLIED_INSIDE_NEGATIVE_CCLASS
static int
clear_not_flag_cclass(CClassNode* cc, OnigEncoding enc)
{
  BBuf *tbuf;
  int r;

  if (IS_NCCLASS_NOT(cc)) {
    bitset_invert(cc->bs);

    if (! ONIGENC_IS_SINGLEBYTE(enc)) {
      r = not_code_range_buf(enc, cc->mbuf, &tbuf);
      if (r != 0) return r;

      bbuf_free(cc->mbuf);
      cc->mbuf = tbuf;
    }

    NCCLASS_CLEAR_NOT(cc);
  }

  return 0;
}
#endif /* CASE_FOLD_IS_APPLIED_INSIDE_NEGATIVE_CCLASS */

typedef struct {
  ScanEnv*    env;
  CClassNode* cc;
  CClassNode* asc_cc;
  Node*       alt_root;
  Node**      ptail;
} IApplyCaseFoldArg;

static int
i_apply_case_fold(OnigCodePoint from, OnigCodePoint to[],
		  int to_len, void* arg)
{
  IApplyCaseFoldArg* iarg;
  ScanEnv* env;
  CClassNode* cc;
  CClassNode* asc_cc;
  BitSetRef bs;
  int add_flag, r;

  iarg = (IApplyCaseFoldArg* )arg;
  env = iarg->env;
  cc  = iarg->cc;
  asc_cc = iarg->asc_cc;
  bs = cc->bs;

  if (IS_NULL(asc_cc)) {
    add_flag = 0;
  }
  else if (ONIGENC_IS_ASCII_CODE(from) == ONIGENC_IS_ASCII_CODE(*to)) {
    add_flag = 1;
  }
  else {
    add_flag = onig_is_code_in_cc(env->enc, from, asc_cc);
    if (IS_NCCLASS_NOT(asc_cc))
      add_flag = !add_flag;
  }

  if (to_len == 1) {
    int is_in = onig_is_code_in_cc(env->enc, from, cc);
#ifdef CASE_FOLD_IS_APPLIED_INSIDE_NEGATIVE_CCLASS
    if ((is_in != 0 && !IS_NCCLASS_NOT(cc)) ||
	(is_in == 0 &&  IS_NCCLASS_NOT(cc))) {
      if (add_flag) {
	if (ONIGENC_MBC_MINLEN(env->enc) > 1 || *to >= SINGLE_BYTE_SIZE) {
	  r = add_code_range0(&(cc->mbuf), env, *to, *to, 0);
	  if (r < 0) return r;
	}
	else {
	  BITSET_SET_BIT(bs, *to);
	}
      }
    }
#else
    if (is_in != 0) {
      if (add_flag) {
	if (ONIGENC_MBC_MINLEN(env->enc) > 1 || *to >= SINGLE_BYTE_SIZE) {
	  if (IS_NCCLASS_NOT(cc)) clear_not_flag_cclass(cc, env->enc);
	  r = add_code_range0(&(cc->mbuf), env, *to, *to, 0);
	  if (r < 0) return r;
	}
	else {
	  if (IS_NCCLASS_NOT(cc)) {
	    BITSET_CLEAR_BIT(bs, *to);
	  }
	  else {
	    BITSET_SET_BIT(bs, *to);
	  }
	}
      }
    }
#endif /* CASE_FOLD_IS_APPLIED_INSIDE_NEGATIVE_CCLASS */
  }
  else {
    int r, i, len;
    UChar buf[ONIGENC_CODE_TO_MBC_MAXLEN];
    Node *snode = NULL_NODE;

    if (onig_is_code_in_cc(env->enc, from, cc)
#ifdef CASE_FOLD_IS_APPLIED_INSIDE_NEGATIVE_CCLASS
	&& !IS_NCCLASS_NOT(cc)
#endif
	) {
      for (i = 0; i < to_len; i++) {
	len = ONIGENC_CODE_TO_MBC(env->enc, to[i], buf);
	if (i == 0) {
	  snode = onig_node_new_str(buf, buf + len);
	  CHECK_NULL_RETURN_MEMERR(snode);

	  /* char-class expanded multi-char only
	     compare with string folded at match time. */
	  NSTRING_SET_AMBIG(snode);
	}
	else {
	  r = onig_node_str_cat(snode, buf, buf + len);
	  if (r < 0) {
	    onig_node_free(snode);
	    return r;
	  }
	}
      }

      *(iarg->ptail) = onig_node_new_alt(snode, NULL_NODE);
      CHECK_NULL_RETURN_MEMERR(*(iarg->ptail));
      iarg->ptail = &(NCDR((*(iarg->ptail))));
    }
  }

  return 0;
}

static int
cclass_case_fold(Node** np, CClassNode* cc, CClassNode* asc_cc, ScanEnv* env)
{
  int r;
  IApplyCaseFoldArg iarg;

  iarg.env         = env;
  iarg.cc          = cc;
  iarg.asc_cc      = asc_cc;
  iarg.alt_root    = NULL_NODE;
  iarg.ptail       = &(iarg.alt_root);

  r = ONIGENC_APPLY_ALL_CASE_FOLD(env->enc, env->case_fold_flag,
				  i_apply_case_fold, &iarg);
  if (r != 0) {
    onig_node_free(iarg.alt_root);
    return r;
  }
  if (IS_NOT_NULL(iarg.alt_root)) {
    Node* work = onig_node_new_alt(*np, iarg.alt_root);
    if (IS_NULL(work)) {
      onig_node_free(iarg.alt_root);
      return ONIGERR_MEMORY;
    }
    *np = work;
  }
  return r;
}

static int
node_linebreak(Node** np, ScanEnv* env)
{
  /* same as (?>\x0D\x0A|[\x0A-\x0D\x{85}\x{2028}\x{2029}]) */
  Node* left = NULL;
  Node* right = NULL;
  Node* target1 = NULL;
  Node* target2 = NULL;
  CClassNode* cc;
  int num1, num2, r;
  UChar buf[ONIGENC_CODE_TO_MBC_MAXLEN * 2];

  /* \x0D\x0A */
  num1 = ONIGENC_CODE_TO_MBC(env->enc, 0x0D, buf);
  if (num1 < 0) return num1;
  num2 = ONIGENC_CODE_TO_MBC(env->enc, 0x0A, buf + num1);
  if (num2 < 0) return num2;
  left = node_new_str_raw(buf, buf + num1 + num2);
  if (IS_NULL(left)) goto err;

  /* [\x0A-\x0D] or [\x0A-\x0D\x{85}\x{2028}\x{2029}] */
  right = node_new_cclass();
  if (IS_NULL(right)) goto err;
  cc = NCCLASS(right);
  if (ONIGENC_MBC_MINLEN(env->enc) > 1) {
    r = add_code_range(&(cc->mbuf), env, 0x0A, 0x0D);
    if (r != 0) goto err;
  }
  else {
    bitset_set_range(env, cc->bs, 0x0A, 0x0D);
  }

  /* TODO: move this block to enc/unicode.c */
  if (ONIGENC_IS_UNICODE(env->enc)) {
    /* UTF-8, UTF-16BE/LE, UTF-32BE/LE */
    r = add_code_range(&(cc->mbuf), env, 0x85, 0x85);
    if (r != 0) goto err;
    r = add_code_range(&(cc->mbuf), env, 0x2028, 0x2029);
    if (r != 0) goto err;
  }

  /* ...|... */
  target1 = onig_node_new_alt(right, NULL_NODE);
  if (IS_NULL(target1)) goto err;
  right = NULL;
  target2 = onig_node_new_alt(left, target1);
  if (IS_NULL(target2)) goto err;
  left = NULL;
  target1 = NULL;

  /* (?>...) */
  *np = node_new_enclose(ENCLOSE_STOP_BACKTRACK);
  if (IS_NULL(*np)) goto err;
  NENCLOSE(*np)->target = target2;
  return ONIG_NORMAL;

 err:
  onig_node_free(left);
  onig_node_free(right);
  onig_node_free(target1);
  onig_node_free(target2);
  return ONIGERR_MEMORY;
}

static int
propname2ctype(ScanEnv* env, const char* propname)
{
  UChar* name = (UChar* )propname;
  UChar* name_end = name + strlen(propname);
  int ctype = env->enc->property_name_to_ctype(ONIG_ENCODING_ASCII,
      name, name_end);
  if (ctype < 0) {
    onig_scan_env_set_error_string(env, ctype, name, name_end);
  }
  return ctype;
}

static int
add_property_to_cc(CClassNode* cc, const char* propname, int not, ScanEnv* env)
{
  int ctype = propname2ctype(env, propname);
  if (ctype < 0) return ctype;
  return add_ctype_to_cc(cc, ctype, not, 0, env);
}

/*
 * helper methods for node_extended_grapheme_cluster (/\X/)
 */
static int
create_property_node(Node **np, ScanEnv* env, const char* propname)
{
  int r;
  CClassNode* cc;

  *np = node_new_cclass();
  if (IS_NULL(*np)) return ONIGERR_MEMORY;
  cc = NCCLASS(*np);
  r = add_property_to_cc(cc, propname, 0, env);
  if (r != 0)
    onig_node_free(*np);
  return r;
}

static int
quantify_node(Node **np, int lower, int upper)
{
  Node* tmp = node_new_quantifier(lower, upper, 0);
  if (IS_NULL(tmp)) return ONIGERR_MEMORY;
  NQTFR(tmp)->target = *np;
  *np = tmp;
  return 0;
}

static int
quantify_property_node(Node **np, ScanEnv* env, const char* propname, char repetitions)
{
  int r;
  int lower = 0;
  int upper = REPEAT_INFINITE;

  r = create_property_node(np, env, propname);
  if (r != 0) return r;
  switch (repetitions) {
    case '?':  upper = 1;          break;
    case '+':  lower = 1;          break;
    case '*':                      break;
    case '2':  lower = upper = 2;  break;
    default :  return ONIGERR_PARSER_BUG;
  }
  return quantify_node(np, lower, upper);
}

#define LIST 0
#define ALT  1

/* IMPORTANT: Make sure node_array ends with NULL_NODE */
static int
create_node_from_array(int kind, Node **np, Node **node_array)
{
  Node* tmp = NULL_NODE;
  int i = 0;

  while (node_array[i] != NULL_NODE)  i++;
  while (--i >= 0) {
    *np = kind==LIST ? node_new_list(node_array[i], tmp)
                     : onig_node_new_alt(node_array[i], tmp);
    if (IS_NULL(*np)) {
      while (i >= 0) {
        onig_node_free(node_array[i]);
        node_array[i--] = NULL_NODE;
      }
      onig_node_free(tmp);
      return ONIGERR_MEMORY;
    }
    else
      node_array[i] = NULL_NODE;
    tmp = *np;
  }
  return 0;
}

#define R_ERR(call) r=(call);if(r!=0)goto err

/* Memory layout for common node array:
 * The main purpose is to be able to easily free all leftover nodes
 * after an error. As a side effect, we share some memory.
 *
 * The layout is as shown below (each line corresponds to one call of
 * create_node_from_array()). Because create_node_from_array sets all
 * nodes of the source to NULL_NODE, we can overlap the target array
 * as long as we do not override the actual target location.
 *
 * Target       Array name          Index
 *
 *              node_array          0 1 2 3 4 5 6 7 8 9 A B C D E F
 * top_alts     alts[5]             0 1 2 3 4*
 * alts+1       list[4]                   0 1 2 3*
 * list+1       core_alts[7]                  0 1 2 3 4 5 6*
 * core_alts+0  H_list[4]                       0 1 2 3*
 * H_list+1     H_alt2[4]                           0 1 2 3*
 * h_alt2+1     H_list2[3]                              0 1 2*
 * core_alts+4  XP_list[4]                              0 1 2 3*
 * XP_list+1    Ex_list[4]                                  0 1 2 3*
 */
#define NODE_COMMON_SIZE 16

static int
node_extended_grapheme_cluster(Node** np, ScanEnv* env)
{
  Node* tmp = NULL;
  Node* np1 = NULL;
  Node* top_alt = NULL;
  int r = 0;
  int num1;
  int i;
  int any_target_position;
  UChar buf[ONIGENC_CODE_TO_MBC_MAXLEN * 2];
  OnigOptionType option;
  /* node_common is function-global so that we can free all nodes
   * in case of error. Unused slots are set to NULL_NODE at all times. */
  Node *node_common[NODE_COMMON_SIZE];
  Node **alts = node_common+0; /* size: 5 */

  for (i=0; i<NODE_COMMON_SIZE; i++)
    node_common[i] = NULL_NODE;

  /* CRLF, common for both Unicode and non-Unicode */
  /* \x0D\x0A */
  r = ONIGENC_CODE_TO_MBC(env->enc, 0x0D, buf);
  if (r < 0) goto err;
  num1 = r;
  r = ONIGENC_CODE_TO_MBC(env->enc, 0x0A, buf + num1);
  if (r < 0) goto err;
  alts[0] = node_new_str_raw(buf, buf + num1 + r);
  if (IS_NULL(alts[0])) goto err;

#ifdef USE_UNICODE_PROPERTIES
  if (ONIGENC_IS_UNICODE(env->enc)) {  /* UTF-8, UTF-16BE/LE, UTF-32BE/LE */
    CClassNode* cc;

    if (propname2ctype(env, "Grapheme_Cluster_Break=Extend") < 0) goto err;
    /* Unicode 11.0.0
     *   CRLF     (already done)
     * | [Control CR LF]
     * | precore* core postcore*
     * | .      (to catch invalid stuff, because this seems to be spec for String#grapheme_clusters) */

    /* [Control CR LF]    (CR and LF are not in the spec, but this is a conformed fix) */
    alts[1] = node_new_cclass();
    if (IS_NULL(alts[1])) goto err;
    cc = NCCLASS(alts[1]);
    R_ERR(add_property_to_cc(cc, "Grapheme_Cluster_Break=Control", 0, env));
    if (ONIGENC_MBC_MINLEN(env->enc) > 1) { /* UTF-16/UTF-32 */
      R_ERR(add_code_range(&(cc->mbuf), env, 0x000A, 0x000A)); /* CR */
      R_ERR(add_code_range(&(cc->mbuf), env, 0x000D, 0x000D)); /* LF */
    }
    else {
      BITSET_SET_BIT(cc->bs, 0x0a);
      BITSET_SET_BIT(cc->bs, 0x0d);
    }

    /* precore* core postcore* */
    {
      Node **list = alts + 3; /* size: 4 */

      /* precore*; precore := Prepend */
      R_ERR(quantify_property_node(list+0, env, "Grapheme_Cluster_Break=Prepend", '*'));

      /* core := hangul-syllable
       *       | ri-sequence
       *       | xpicto-sequence
       *       | [^Control CR LF] */
      {
        Node **core_alts = list + 2; /* size: 7 */

        /* hangul-syllable :=
         *     L* (V+ | LV V* | LVT) T*
         *   | L+
         *   | T+ */
        /* hangul-syllable is an alternative (would be called H_alt)
         * inside an alternative, but we flatten it into core_alts */

        /* L* (V+ | LV V* | LVT) T* */
        {
          Node **H_list = core_alts + 1; /* size: 4 */
          R_ERR(quantify_property_node(H_list+0, env, "Grapheme_Cluster_Break=L", '*'));

          /* V+ | LV V* | LVT */
          {
            Node **H_alt2 = H_list + 2; /* size: 4 */
            R_ERR(quantify_property_node(H_alt2+0, env, "Grapheme_Cluster_Break=V", '+'));

            /* LV V* */
            {
              Node **H_list2 = H_alt2 + 2; /* size: 3 */

              R_ERR(create_property_node(H_list2+0, env, "Grapheme_Cluster_Break=LV"));
              R_ERR(quantify_property_node(H_list2+1, env, "Grapheme_Cluster_Break=V", '*'));
              R_ERR(create_node_from_array(LIST, H_alt2+1, H_list2));
            }

            R_ERR(create_property_node(H_alt2+2, env, "Grapheme_Cluster_Break=LVT"));
            R_ERR(create_node_from_array(ALT, H_list+1, H_alt2));
          }

          R_ERR(quantify_property_node(H_list+2, env, "Grapheme_Cluster_Break=T", '*'));
          R_ERR(create_node_from_array(LIST, core_alts+0, H_list));
        }

        R_ERR(quantify_property_node(core_alts+1, env, "Grapheme_Cluster_Break=L", '+'));
        R_ERR(quantify_property_node(core_alts+2, env, "Grapheme_Cluster_Break=T", '+'));
        /* end of hangul-syllable */

        /* ri-sequence := RI RI */
        R_ERR(quantify_property_node(core_alts+3, env, "Regional_Indicator", '2'));

        /* xpicto-sequence := \p{Extended_Pictographic} (Extend* ZWJ \p{Extended_Pictographic})* */
        {
          Node **XP_list = core_alts + 5; /* size: 3 */
          R_ERR(create_property_node(XP_list+0, env, "Extended_Pictographic"));

          /* (Extend* ZWJ \p{Extended_Pictographic})* */
          {
            Node **Ex_list = XP_list + 2; /* size: 4 */
            /* assert(Ex_list+4 == node_common+NODE_COMMON_SIZE); */
            R_ERR(quantify_property_node(Ex_list+0, env, "Grapheme_Cluster_Break=Extend", '*'));

            /* ZWJ (ZERO WIDTH JOINER) */
            r = ONIGENC_CODE_TO_MBC(env->enc, 0x200D, buf);
            if (r < 0) goto err;
            Ex_list[1] = node_new_str_raw(buf, buf + r);
            if (IS_NULL(Ex_list[1])) goto err;

            R_ERR(create_property_node(Ex_list+2, env, "Extended_Pictographic"));
            R_ERR(create_node_from_array(LIST, XP_list+1, Ex_list));
          }
          R_ERR(quantify_node(XP_list+1, 0, REPEAT_INFINITE)); /* TODO: Check about node freeing */

          R_ERR(create_node_from_array(LIST, core_alts+4, XP_list));
        }

        /* [^Control CR LF] */
        core_alts[5] = node_new_cclass();
        if (IS_NULL(core_alts[5])) goto err;
        cc = NCCLASS(core_alts[5]);
        if (ONIGENC_MBC_MINLEN(env->enc) > 1) { /* UTF-16/UTF-32 */
          BBuf *inverted_buf = NULL;

          /* TODO: fix false warning */
          const int dup_not_warned = env->warnings_flag | ~ONIG_SYN_WARN_CC_DUP;
          env->warnings_flag |= ONIG_SYN_WARN_CC_DUP;

          /* Start with a positive buffer and invert at the end.
           * Otherwise, adding single-character ranges work the wrong way. */
          R_ERR(add_property_to_cc(cc, "Grapheme_Cluster_Break=Control", 0, env));
          R_ERR(add_code_range(&(cc->mbuf), env, 0x000A, 0x000A)); /* CR */
          R_ERR(add_code_range(&(cc->mbuf), env, 0x000D, 0x000D)); /* LF */
          R_ERR(not_code_range_buf(env->enc, cc->mbuf, &inverted_buf, env));
          cc->mbuf = inverted_buf; /* TODO: check what to do with buffer before inversion */

          env->warnings_flag &= dup_not_warned; /* TODO: fix false warning */
        }
        else {
          R_ERR(add_property_to_cc(cc, "Grapheme_Cluster_Break=Control", 1, env));
          BITSET_CLEAR_BIT(cc->bs, 0x0a);
          BITSET_CLEAR_BIT(cc->bs, 0x0d);
        }

        R_ERR(create_node_from_array(ALT, list+1, core_alts));
      }

      /* postcore*; postcore = [Extend ZWJ SpacingMark] */
      R_ERR(create_property_node(list+2, env, "Grapheme_Cluster_Break=Extend"));
      cc = NCCLASS(list[2]);
      R_ERR(add_property_to_cc(cc, "Grapheme_Cluster_Break=SpacingMark", 0, env));
      R_ERR(add_code_range(&(cc->mbuf), env, 0x200D, 0x200D));
      R_ERR(quantify_node(list+2, 0, REPEAT_INFINITE));

      R_ERR(create_node_from_array(LIST, alts+2, list));
    }

    any_target_position = 3;
  }
  else
#endif /* USE_UNICODE_PROPERTIES */
  {
    any_target_position = 1;
  }

  /* PerlSyntax: (?s:.), RubySyntax: (?m:.), common for both Unicode and non-Unicode */
  /* Not in Unicode spec (UAX #29), but added to catch invalid stuff,
   * because this is Ruby spec for String#grapheme_clusters. */
  np1 = node_new_anychar();
  if (IS_NULL(np1)) goto err;

  option = env->option;
  ONOFF(option, ONIG_OPTION_MULTILINE, 0);
  tmp = node_new_option(option);
  if (IS_NULL(tmp)) goto err;
  NENCLOSE(tmp)->target = np1;
  alts[any_target_position] = tmp;
  np1 = NULL;

  R_ERR(create_node_from_array(ALT, &top_alt, alts));

  /* (?>): For efficiency, because there is no text piece
   *       that is not in a grapheme cluster, and there is only one way
   *       to split a string into grapheme clusters. */
  tmp = node_new_enclose(ENCLOSE_STOP_BACKTRACK);
  if (IS_NULL(tmp)) goto err;
  NENCLOSE(tmp)->target = top_alt;
  np1 = tmp;

#ifdef USE_UNICODE_PROPERTIES
  if (ONIGENC_IS_UNICODE(env->enc)) {
    /* Don't ignore case. */
    option = env->option;
    ONOFF(option, ONIG_OPTION_IGNORECASE, 1);
    *np = node_new_option(option);
    if (IS_NULL(*np)) goto err;
    NENCLOSE(*np)->target = np1;
  }
  else
#endif
  {
    *np = np1;
  }
  return ONIG_NORMAL;

 err:
  onig_node_free(np1);
  for (i=0; i<NODE_COMMON_SIZE; i++)
    onig_node_free(node_common[i]);
  return (r == 0) ? ONIGERR_MEMORY : r;
}
#undef R_ERR

static int
countbits(unsigned int bits)
{
  bits = (bits & 0x55555555) + ((bits >> 1) & 0x55555555);
  bits = (bits & 0x33333333) + ((bits >> 2) & 0x33333333);
  bits = (bits & 0x0f0f0f0f) + ((bits >> 4) & 0x0f0f0f0f);
  bits = (bits & 0x00ff00ff) + ((bits >> 8) & 0x00ff00ff);
  return (bits & 0x0000ffff) + ((bits >>16) & 0x0000ffff);
}

static int
is_onechar_cclass(CClassNode* cc, OnigCodePoint* code)
{
  const OnigCodePoint not_found = ONIG_LAST_CODE_POINT;
  OnigCodePoint c = not_found;
  int i;
  BBuf *bbuf = cc->mbuf;

  if (IS_NCCLASS_NOT(cc)) return 0;

  /* check bbuf */
  if (IS_NOT_NULL(bbuf)) {
    OnigCodePoint n, *data;
    GET_CODE_POINT(n, bbuf->p);
    data = (OnigCodePoint* )(bbuf->p) + 1;
    if ((n == 1) && (data[0] == data[1])) {
      /* only one char found in the bbuf, save the code point. */
      c = data[0];
      if (((c < SINGLE_BYTE_SIZE) && BITSET_AT(cc->bs, c))) {
	/* skip if c is included in the bitset */
	c = not_found;
      }
    }
    else {
      return 0;  /* the bbuf contains multiple chars */
    }
  }

  /* check bitset */
  for (i = 0; i < BITSET_SIZE; i++) {
    Bits b1 = cc->bs[i];
    if (b1 != 0) {
      if (((b1 & (b1 - 1)) == 0) && (c == not_found)) {
	c = BITS_IN_ROOM * i + countbits(b1 - 1);
      } else {
	return 0;  /* the character class contains multiple chars */
      }
    }
  }

  if (c != not_found) {
    *code = c;
    return 1;
  }

  /* the character class contains no char. */
  return 0;
}


static int
parse_exp(Node** np, OnigToken* tok, int term,
	  UChar** src, UChar* end, ScanEnv* env)
{
  int r, len, group = 0;
  Node* qn;
  Node** targetp;

  *np = NULL;
  if (tok->type == (enum TokenSyms )term)
    goto end_of_token;

  switch (tok->type) {
  case TK_ALT:
  case TK_EOT:
  end_of_token:
    *np = node_new_empty();
    return tok->type;
    break;

  case TK_SUBEXP_OPEN:
    r = parse_enclose(np, tok, TK_SUBEXP_CLOSE, src, end, env);
    if (r < 0) return r;
    if (r == 1) group = 1;
    else if (r == 2) { /* option only */
      Node* target;
      OnigOptionType prev = env->option;

      env->option = NENCLOSE(*np)->option;
      r = fetch_token(tok, src, end, env);
      if (r < 0) {
	env->option = prev;
	return r;
      }
      r = parse_subexp(&target, tok, term, src, end, env);
      env->option = prev;
      if (r < 0) {
	onig_node_free(target);
	return r;
      }
      NENCLOSE(*np)->target = target;
      return tok->type;
    }
    break;

  case TK_SUBEXP_CLOSE:
    if (! IS_SYNTAX_BV(env->syntax, ONIG_SYN_ALLOW_UNMATCHED_CLOSE_SUBEXP))
      return ONIGERR_UNMATCHED_CLOSE_PARENTHESIS;

    if (tok->escaped) goto tk_raw_byte;
    else goto tk_byte;
    break;

  case TK_LINEBREAK:
    r = node_linebreak(np, env);
    if (r < 0) return r;
    break;

  case TK_EXTENDED_GRAPHEME_CLUSTER:
    r = node_extended_grapheme_cluster(np, env);
    if (r < 0) return r;
    break;

  case TK_KEEP:
    *np = onig_node_new_anchor(ANCHOR_KEEP);
    CHECK_NULL_RETURN_MEMERR(*np);
    break;

  case TK_STRING:
  tk_byte:
    {
      *np = node_new_str(tok->backp, *src);
      CHECK_NULL_RETURN_MEMERR(*np);

    string_loop:
      while (1) {
	r = fetch_token(tok, src, end, env);
	if (r < 0) return r;
	if (r == TK_STRING) {
	  r = onig_node_str_cat(*np, tok->backp, *src);
	}
#ifndef NUMBERED_CHAR_IS_NOT_CASE_AMBIG
	else if (r == TK_CODE_POINT) {
	  r = node_str_cat_codepoint(*np, env->enc, tok->u.code);
	}
#endif
	else {
	  break;
	}
	if (r < 0) return r;
      }

    string_end:
      targetp = np;
      goto repeat;
    }
    break;

  case TK_RAW_BYTE:
  tk_raw_byte:
    {
      *np = node_new_str_raw_char((UChar )tok->u.c);
      CHECK_NULL_RETURN_MEMERR(*np);
      len = 1;
      while (1) {
	if (len >= ONIGENC_MBC_MINLEN(env->enc)) {
	  if (len == enclen(env->enc, NSTR(*np)->s, NSTR(*np)->end)) {
	    r = fetch_token(tok, src, end, env);
	    NSTRING_CLEAR_RAW(*np);
	    goto string_end;
	  }
	}

	r = fetch_token(tok, src, end, env);
	if (r < 0) return r;
	if (r != TK_RAW_BYTE) {
	  /* Don't use this, it is wrong for little endian encodings. */
#ifdef USE_PAD_TO_SHORT_BYTE_CHAR
	  int rem;
	  if (len < ONIGENC_MBC_MINLEN(env->enc)) {
	    rem = ONIGENC_MBC_MINLEN(env->enc) - len;
	    (void )node_str_head_pad(NSTR(*np), rem, (UChar )0);
	    if (len + rem == enclen(env->enc, NSTR(*np)->s)) {
	      NSTRING_CLEAR_RAW(*np);
	      goto string_end;
	    }
	  }
#endif
	  return ONIGERR_TOO_SHORT_MULTI_BYTE_STRING;
	}

	r = node_str_cat_char(*np, (UChar )tok->u.c);
	if (r < 0) return r;

	len++;
      }
    }
    break;

  case TK_CODE_POINT:
    {
      *np = node_new_empty();
      CHECK_NULL_RETURN_MEMERR(*np);
      r = node_str_cat_codepoint(*np, env->enc, tok->u.code);
      if (r != 0) return r;
#ifdef NUMBERED_CHAR_IS_NOT_CASE_AMBIG
      NSTRING_SET_RAW(*np);
#else
      goto string_loop;
#endif
    }
    break;

  case TK_QUOTE_OPEN:
    {
      OnigCodePoint end_op[2];
      UChar *qstart, *qend, *nextp;

      end_op[0] = (OnigCodePoint )MC_ESC(env->syntax);
      end_op[1] = (OnigCodePoint )'E';
      qstart = *src;
      qend = find_str_position(end_op, 2, qstart, end, &nextp, env->enc);
      if (IS_NULL(qend)) {
	nextp = qend = end;
      }
      *np = node_new_str(qstart, qend);
      CHECK_NULL_RETURN_MEMERR(*np);
      *src = nextp;
    }
    break;

  case TK_CHAR_TYPE:
    {
      switch (tok->u.prop.ctype) {
      case ONIGENC_CTYPE_WORD:
	*np = node_new_ctype(tok->u.prop.ctype, tok->u.prop.not,
			     IS_ASCII_RANGE(env->option));
	CHECK_NULL_RETURN_MEMERR(*np);
	break;

      case ONIGENC_CTYPE_SPACE:
      case ONIGENC_CTYPE_DIGIT:
      case ONIGENC_CTYPE_XDIGIT:
	{
	  CClassNode* cc;

	  *np = node_new_cclass();
	  CHECK_NULL_RETURN_MEMERR(*np);
	  cc = NCCLASS(*np);
	  r = add_ctype_to_cc(cc, tok->u.prop.ctype, 0,
	      IS_ASCII_RANGE(env->option), env);
	  if (r != 0) return r;
	  if (tok->u.prop.not != 0) NCCLASS_SET_NOT(cc);
	}
	break;

      default:
	return ONIGERR_PARSER_BUG;
	break;
      }
    }
    break;

  case TK_CHAR_PROPERTY:
    r = parse_char_property(np, tok, src, end, env);
    if (r != 0) return r;
    break;

  case TK_CC_OPEN:
    {
      Node *asc_node;
      CClassNode* cc;
      OnigCodePoint code;

      r = parse_char_class(np, &asc_node, tok, src, end, env);
      if (r != 0) {
	onig_node_free(asc_node);
	return r;
      }

      cc = NCCLASS(*np);
      if (is_onechar_cclass(cc, &code)) {
	onig_node_free(*np);
	onig_node_free(asc_node);
	*np = node_new_empty();
	CHECK_NULL_RETURN_MEMERR(*np);
	r = node_str_cat_codepoint(*np, env->enc, code);
	if (r != 0) return r;
	goto string_loop;
      }
      if (IS_IGNORECASE(env->option)) {
	r = cclass_case_fold(np, cc, NCCLASS(asc_node), env);
	if (r != 0) {
	  onig_node_free(asc_node);
	  return r;
	}
      }
      onig_node_free(asc_node);
    }
    break;

  case TK_ANYCHAR:
    *np = node_new_anychar();
    CHECK_NULL_RETURN_MEMERR(*np);
    break;

  case TK_ANYCHAR_ANYTIME:
    *np = node_new_anychar();
    CHECK_NULL_RETURN_MEMERR(*np);
    qn = node_new_quantifier(0, REPEAT_INFINITE, 0);
    CHECK_NULL_RETURN_MEMERR(qn);
    NQTFR(qn)->target = *np;
    *np = qn;
    break;

  case TK_BACKREF:
    len = tok->u.backref.num;
    *np = node_new_backref(len,
		   (len > 1 ? tok->u.backref.refs : &(tok->u.backref.ref1)),
			   tok->u.backref.by_name,
#ifdef USE_BACKREF_WITH_LEVEL
			   tok->u.backref.exist_level,
			   tok->u.backref.level,
#endif
			   env);
    CHECK_NULL_RETURN_MEMERR(*np);
    break;

#ifdef USE_SUBEXP_CALL
  case TK_CALL:
    {
      int gnum = tok->u.call.gnum;

      if (gnum < 0 || tok->u.call.rel != 0) {
	if (gnum > 0) gnum--;
	gnum = BACKREF_REL_TO_ABS(gnum, env);
	if (gnum <= 0)
	  return ONIGERR_INVALID_BACKREF;
      }
      *np = node_new_call(tok->u.call.name, tok->u.call.name_end, gnum);
      CHECK_NULL_RETURN_MEMERR(*np);
      env->num_call++;
    }
    break;
#endif

  case TK_ANCHOR:
    *np = onig_node_new_anchor(tok->u.anchor.subtype);
    CHECK_NULL_RETURN_MEMERR(*np);
    NANCHOR(*np)->ascii_range = tok->u.anchor.ascii_range;
    break;

  case TK_OP_REPEAT:
  case TK_INTERVAL:
    if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_CONTEXT_INDEP_REPEAT_OPS)) {
      if (IS_SYNTAX_BV(env->syntax, ONIG_SYN_CONTEXT_INVALID_REPEAT_OPS))
	return ONIGERR_TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED;
      else
	*np = node_new_empty();
    }
    else {
      goto tk_byte;
    }
    break;

  default:
    return ONIGERR_PARSER_BUG;
    break;
  }

  {
    targetp = np;

  re_entry:
    r = fetch_token(tok, src, end, env);
    if (r < 0) return r;

  repeat:
    if (r == TK_OP_REPEAT || r == TK_INTERVAL) {
      if (is_invalid_quantifier_target(*targetp))
	return ONIGERR_TARGET_OF_REPEAT_OPERATOR_INVALID;

      qn = node_new_quantifier(tok->u.repeat.lower, tok->u.repeat.upper,
			       (r == TK_INTERVAL ? 1 : 0));
      CHECK_NULL_RETURN_MEMERR(qn);
      NQTFR(qn)->greedy = tok->u.repeat.greedy;
      r = set_quantifier(qn, *targetp, group, env);
      if (r < 0) {
	onig_node_free(qn);
	return r;
      }

      if (tok->u.repeat.possessive != 0) {
	Node* en;
	en = node_new_enclose(ENCLOSE_STOP_BACKTRACK);
	if (IS_NULL(en)) {
	  onig_node_free(qn);
	  return ONIGERR_MEMORY;
	}
	NENCLOSE(en)->target = qn;
	qn = en;
      }

      if (r == 0) {
	*targetp = qn;
      }
      else if (r == 1) {
	onig_node_free(qn);
      }
      else if (r == 2) { /* split case: /abc+/ */
	Node *tmp;

	*targetp = node_new_list(*targetp, NULL);
	if (IS_NULL(*targetp)) {
	  onig_node_free(qn);
	  return ONIGERR_MEMORY;
	}
	tmp = NCDR(*targetp) = node_new_list(qn, NULL);
	if (IS_NULL(tmp)) {
	  onig_node_free(qn);
	  return ONIGERR_MEMORY;
	}
	targetp = &(NCAR(tmp));
      }
      goto re_entry;
    }
  }

  return r;
}

static int
parse_branch(Node** top, OnigToken* tok, int term,
	     UChar** src, UChar* end, ScanEnv* env)
{
  int r;
  Node *node, **headp;

  *top = NULL;
  r = parse_exp(&node, tok, term, src, end, env);
  if (r < 0) {
    onig_node_free(node);
    return r;
  }

  if (r == TK_EOT || r == term || r == TK_ALT) {
    *top = node;
  }
  else {
    *top  = node_new_list(node, NULL);
    headp = &(NCDR(*top));
    while (r != TK_EOT && r != term && r != TK_ALT) {
      r = parse_exp(&node, tok, term, src, end, env);
      if (r < 0) {
	onig_node_free(node);
	return r;
      }

      if (NTYPE(node) == NT_LIST) {
	*headp = node;
	while (IS_NOT_NULL(NCDR(node))) node = NCDR(node);
	headp = &(NCDR(node));
      }
      else {
	*headp = node_new_list(node, NULL);
	headp = &(NCDR(*headp));
      }
    }
  }

  return r;
}

/* term_tok: TK_EOT or TK_SUBEXP_CLOSE */
static int
parse_subexp(Node** top, OnigToken* tok, int term,
	     UChar** src, UChar* end, ScanEnv* env)
{
  int r;
  Node *node, **headp;

  *top = NULL;
  env->parse_depth++;
  if (env->parse_depth > ParseDepthLimit)
    return ONIGERR_PARSE_DEPTH_LIMIT_OVER;
  r = parse_branch(&node, tok, term, src, end, env);
  if (r < 0) {
    onig_node_free(node);
    return r;
  }

  if (r == term) {
    *top = node;
  }
  else if (r == TK_ALT) {
    *top  = onig_node_new_alt(node, NULL);
    headp = &(NCDR(*top));
    while (r == TK_ALT) {
      r = fetch_token(tok, src, end, env);
      if (r < 0) return r;
      r = parse_branch(&node, tok, term, src, end, env);
      if (r < 0) {
	onig_node_free(node);
	return r;
      }

      *headp = onig_node_new_alt(node, NULL);
      headp = &(NCDR(*headp));
    }

    if (tok->type != (enum TokenSyms )term)
      goto err;
  }
  else {
    onig_node_free(node);
  err:
    if (term == TK_SUBEXP_CLOSE)
      return ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS;
    else
      return ONIGERR_PARSER_BUG;
  }

  env->parse_depth--;
  return r;
}

static int
parse_regexp(Node** top, UChar** src, UChar* end, ScanEnv* env)
{
  int r;
  OnigToken tok;

  r = fetch_token(&tok, src, end, env);
  if (r < 0) return r;
  r = parse_subexp(top, &tok, TK_EOT, src, end, env);
  if (r < 0) return r;

#ifdef USE_SUBEXP_CALL
  if (env->num_call > 0) {
    /* Capture the pattern itself. It is used for (?R), (?0) and \g<0>. */
    const int num = 0;
    Node* np;
    np = node_new_enclose_memory(env->option, 0);
    CHECK_NULL_RETURN_MEMERR(np);
    NENCLOSE(np)->regnum = num;
    NENCLOSE(np)->target = *top;
    r = scan_env_set_mem_node(env, num, np);
    if (r != 0) {
	onig_node_free(np);
	return r;
    }
    *top = np;
  }
#endif
  return 0;
}

extern int
onig_parse_make_tree(Node** root, const UChar* pattern, const UChar* end,
		     regex_t* reg, ScanEnv* env)
{
  int r;
  UChar* p;

#ifdef USE_NAMED_GROUP
  names_clear(reg);
#endif

  scan_env_clear(env);
  env->option         = reg->options;
  env->case_fold_flag = reg->case_fold_flag;
  env->enc            = reg->enc;
  env->syntax         = reg->syntax;
  env->pattern        = (UChar* )pattern;
  env->pattern_end    = (UChar* )end;
  env->reg            = reg;

  *root = NULL;
  p = (UChar* )pattern;
  r = parse_regexp(root, &p, (UChar* )end, env);
  reg->num_mem = env->num_mem;
  return r;
}

extern void
onig_scan_env_set_error_string(ScanEnv* env, int ecode ARG_UNUSED,
				UChar* arg, UChar* arg_end)
{
  env->error     = arg;
  env->error_end = arg_end;
}
