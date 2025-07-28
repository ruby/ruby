/**********************************************************************
  regexec.c -  Onigmo (Oniguruma-mod) (regular expression library)
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

#include "regint.h"

#ifdef RUBY
# undef USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE
#else
# define USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE
#endif

#ifndef USE_TOKEN_THREADED_VM
# ifdef __GNUC__
#  define USE_TOKEN_THREADED_VM 1
# else
#  define USE_TOKEN_THREADED_VM 0
# endif
#endif

#ifdef RUBY
# define ENC_DUMMY_FLAG (1<<24)
static inline int
rb_enc_asciicompat(OnigEncoding enc)
{
  return ONIGENC_MBC_MINLEN(enc)==1 && !((enc)->ruby_encoding_index & ENC_DUMMY_FLAG);
}
# undef ONIGENC_IS_MBC_ASCII_WORD
# define ONIGENC_IS_MBC_ASCII_WORD(enc,s,end) \
    (rb_enc_asciicompat(enc) ? (ISALNUM(*s) || *s=='_') : \
   onigenc_ascii_is_code_ctype( \
	ONIGENC_MBC_TO_CODE(enc,s,end),ONIGENC_CTYPE_WORD,enc))
#endif /* RUBY */

#ifdef USE_CRNL_AS_LINE_TERMINATOR
# define ONIGENC_IS_MBC_CRNL(enc,p,end) \
  (ONIGENC_MBC_TO_CODE(enc,p,end) == 13 && \
   ONIGENC_MBC_TO_CODE(enc,(p+enclen(enc,p,end)),end) == 10)
# define ONIGENC_IS_MBC_NEWLINE_EX(enc,p,start,end,option,check_prev) \
  is_mbc_newline_ex((enc),(p),(start),(end),(option),(check_prev))
static int
is_mbc_newline_ex(OnigEncoding enc, const UChar *p, const UChar *start,
		  const UChar *end, OnigOptionType option, int check_prev)
{
  if (IS_NEWLINE_CRLF(option)) {
    if (ONIGENC_MBC_TO_CODE(enc, p, end) == 0x0a) {
      if (check_prev) {
	const UChar *prev = onigenc_get_prev_char_head(enc, start, p, end);
	if ((prev != NULL) && ONIGENC_MBC_TO_CODE(enc, prev, end) == 0x0d)
	  return 0;
	else
	  return 1;
      }
      else
	return 1;
    }
    else {
      const UChar *pnext = p + enclen(enc, p, end);
      if (pnext < end &&
	  ONIGENC_MBC_TO_CODE(enc, p, end) == 0x0d &&
	  ONIGENC_MBC_TO_CODE(enc, pnext, end) == 0x0a)
	return 1;
      if (ONIGENC_IS_MBC_NEWLINE(enc, p, end))
	return 1;
      return 0;
    }
  }
  else {
    return ONIGENC_IS_MBC_NEWLINE(enc, p, end);
  }
}
#else /* USE_CRNL_AS_LINE_TERMINATOR */
# define ONIGENC_IS_MBC_NEWLINE_EX(enc,p,start,end,option,check_prev) \
  ONIGENC_IS_MBC_NEWLINE((enc), (p), (end))
#endif /* USE_CRNL_AS_LINE_TERMINATOR */

#ifdef USE_CAPTURE_HISTORY
static void history_tree_free(OnigCaptureTreeNode* node);

static void
history_tree_clear(OnigCaptureTreeNode* node)
{
  int i;

  if (IS_NOT_NULL(node)) {
    for (i = 0; i < node->num_childs; i++) {
      if (IS_NOT_NULL(node->childs[i])) {
	history_tree_free(node->childs[i]);
      }
    }
    for (i = 0; i < node->allocated; i++) {
      node->childs[i] = (OnigCaptureTreeNode* )0;
    }
    node->num_childs = 0;
    node->beg = ONIG_REGION_NOTPOS;
    node->end = ONIG_REGION_NOTPOS;
    node->group = -1;
    xfree(node->childs);
    node->childs = (OnigCaptureTreeNode** )0;
  }
}

static void
history_tree_free(OnigCaptureTreeNode* node)
{
  history_tree_clear(node);
  xfree(node);
}

static void
history_root_free(OnigRegion* r)
{
  if (IS_NOT_NULL(r->history_root)) {
    history_tree_free(r->history_root);
    r->history_root = (OnigCaptureTreeNode* )0;
  }
}

static OnigCaptureTreeNode*
history_node_new(void)
{
  OnigCaptureTreeNode* node;

  node = (OnigCaptureTreeNode* )xmalloc(sizeof(OnigCaptureTreeNode));
  CHECK_NULL_RETURN(node);
  node->childs     = (OnigCaptureTreeNode** )0;
  node->allocated  = 0;
  node->num_childs = 0;
  node->group      = -1;
  node->beg        = ONIG_REGION_NOTPOS;
  node->end        = ONIG_REGION_NOTPOS;

  return node;
}

static int
history_tree_add_child(OnigCaptureTreeNode* parent, OnigCaptureTreeNode* child)
{
# define HISTORY_TREE_INIT_ALLOC_SIZE  8

  if (parent->num_childs >= parent->allocated) {
    int n, i;

    if (IS_NULL(parent->childs)) {
      n = HISTORY_TREE_INIT_ALLOC_SIZE;
      parent->childs =
	(OnigCaptureTreeNode** )xmalloc(sizeof(OnigCaptureTreeNode*) * n);
      CHECK_NULL_RETURN_MEMERR(parent->childs);
    }
    else {
      OnigCaptureTreeNode** tmp;
      n = parent->allocated * 2;
      tmp =
	(OnigCaptureTreeNode** )xrealloc(parent->childs,
					 sizeof(OnigCaptureTreeNode*) * n);
      if (tmp == 0) {
	history_tree_clear(parent);
	return ONIGERR_MEMORY;
      }
      parent->childs = tmp;
    }
    for (i = parent->allocated; i < n; i++) {
      parent->childs[i] = (OnigCaptureTreeNode* )0;
    }
    parent->allocated = n;
  }

  parent->childs[parent->num_childs] = child;
  parent->num_childs++;
  return 0;
}

static OnigCaptureTreeNode*
history_tree_clone(OnigCaptureTreeNode* node)
{
  int i, r;
  OnigCaptureTreeNode *clone, *child;

  clone = history_node_new();
  CHECK_NULL_RETURN(clone);

  clone->beg = node->beg;
  clone->end = node->end;
  for (i = 0; i < node->num_childs; i++) {
    child = history_tree_clone(node->childs[i]);
    if (IS_NULL(child)) {
      history_tree_free(clone);
      return (OnigCaptureTreeNode* )0;
    }
    r = history_tree_add_child(clone, child);
    if (r != 0) {
      history_tree_free(child);
      history_tree_free(clone);
      return (OnigCaptureTreeNode* )0;
    }
  }

  return clone;
}

extern  OnigCaptureTreeNode*
onig_get_capture_tree(OnigRegion* region)
{
  return region->history_root;
}
#endif /* USE_CAPTURE_HISTORY */

#ifdef USE_MATCH_CACHE

/*
Glossary for "match cache"

"match cache" or "match cache optimization"
The `Regexp#match` optimization by using a cache.

"cache opcode"
A cachable opcode (e.g. `OP_PUSH`, `OP_REPEAT`, etc).
It is corresponding to some cache points.

"cache point"
A cachable point on matching.
Usually, one-to-one corresponding between a cache opcode and a cache point exists,
but cache opcodes between `OP_REPEAT` and `OP_REPEAT_INC` have some corresponding
cache points depending on repetition counts.

"match cache point"
A pair of a cache point and a position on an input string.
We encode a match cache point to an integer value by the following equation:
"match cache point" = "position on input string" * "total number of cache points" + "cache point"

"match cache buffer"
A bit-array for memoizing (recording) match cache points once backtracked.
*/

static OnigPosition count_num_cache_opcodes_inner(
    const regex_t* reg,
    MemNumType current_repeat_mem, int lookaround_nesting,
    UChar** pp, long* num_cache_opcodes_ptr
)
{
  UChar* p = *pp;
  UChar* pend = reg->p + reg->used;
  LengthType len;
  MemNumType repeat_mem;
  OnigEncoding enc = reg->enc;
  long num_cache_opcodes = *num_cache_opcodes_ptr;
  OnigPosition result;

  while (p < pend) {
    switch (*p++) {
      case OP_FINISH:
      case OP_END:
	break;

      case OP_EXACT1: p++; break;
      case OP_EXACT2: p += 2; break;
      case OP_EXACT3: p += 3; break;
      case OP_EXACT4: p += 4; break;
      case OP_EXACT5: p += 5; break;
      case OP_EXACTN:
	GET_LENGTH_INC(len, p); p += len; break;
      case OP_EXACTMB2N1: p += 2; break;
      case OP_EXACTMB2N2: p += 4; break;
      case OP_EXACTMB2N3: p += 6; break;
      case OP_EXACTMB2N:
	GET_LENGTH_INC(len, p); p += len * 2; break;
      case OP_EXACTMB3N:
	GET_LENGTH_INC(len, p); p += len * 3; break;
      case OP_EXACTMBN:
	{
	  int mb_len;
	  GET_LENGTH_INC(mb_len, p);
	  GET_LENGTH_INC(len, p);
	  p += mb_len * len;
	}
	break;

      case OP_EXACT1_IC:
	len = enclen(enc, p, pend); p += len; break;
      case OP_EXACTN_IC:
	GET_LENGTH_INC(len, p); p += len; break;

      case OP_CCLASS:
      case OP_CCLASS_NOT:
	p += SIZE_BITSET; break;
      case OP_CCLASS_MB:
      case OP_CCLASS_MB_NOT:
	GET_LENGTH_INC(len, p); p += len; break;
      case OP_CCLASS_MIX:
      case OP_CCLASS_MIX_NOT:
	p += SIZE_BITSET;
	GET_LENGTH_INC(len, p);
	p += len;
	break;

      case OP_ANYCHAR:
      case OP_ANYCHAR_ML:
	break;
      case OP_ANYCHAR_STAR:
      case OP_ANYCHAR_ML_STAR:
	num_cache_opcodes++; break;
      case OP_ANYCHAR_STAR_PEEK_NEXT:
      case OP_ANYCHAR_ML_STAR_PEEK_NEXT:
	p++; num_cache_opcodes++; break;

      case OP_WORD:
      case OP_NOT_WORD:
      case OP_WORD_BOUND:
      case OP_NOT_WORD_BOUND:
      case OP_WORD_BEGIN:
      case OP_WORD_END:
	break;

      case OP_ASCII_WORD:
      case OP_NOT_ASCII_WORD:
      case OP_ASCII_WORD_BOUND:
      case OP_NOT_ASCII_WORD_BOUND:
      case OP_ASCII_WORD_BEGIN:
      case OP_ASCII_WORD_END:
	break;

      case OP_BEGIN_BUF:
      case OP_END_BUF:
      case OP_BEGIN_LINE:
      case OP_END_LINE:
      case OP_SEMI_END_BUF:
      case OP_BEGIN_POSITION:
	break;

      case OP_BACKREF1:
      case OP_BACKREF2:
      case OP_BACKREFN:
      case OP_BACKREFN_IC:
      case OP_BACKREF_MULTI:
      case OP_BACKREF_MULTI_IC:
      case OP_BACKREF_WITH_LEVEL:
	goto impossible;

      case OP_MEMORY_START:
      case OP_MEMORY_START_PUSH:
      case OP_MEMORY_END_PUSH:
      case OP_MEMORY_END_PUSH_REC:
      case OP_MEMORY_END:
      case OP_MEMORY_END_REC:
	p += SIZE_MEMNUM;
	// A memory (capture) in look-around is found.
	if (lookaround_nesting != 0) {
	  goto impossible;
        }
	break;

      case OP_KEEP:
	break;

      case OP_FAIL:
	break;
      case OP_JUMP:
	p += SIZE_RELADDR;
	break;
      case OP_PUSH:
	p += SIZE_RELADDR;
	num_cache_opcodes++;
	break;
      case OP_POP:
	break;
      case OP_PUSH_OR_JUMP_EXACT1:
      case OP_PUSH_IF_PEEK_NEXT:
	p += SIZE_RELADDR + 1; num_cache_opcodes++; break;
      case OP_REPEAT:
      case OP_REPEAT_NG:
	if (current_repeat_mem != -1) {
	  // A nested OP_REPEAT is not yet supported.
	  goto impossible;
	}
	GET_MEMNUM_INC(repeat_mem, p);
	p += SIZE_RELADDR;
	if (reg->repeat_range[repeat_mem].lower == 0) {
	  num_cache_opcodes++;
	}
	result = count_num_cache_opcodes_inner(reg, repeat_mem, lookaround_nesting, &p, &num_cache_opcodes);
	if (result < 0 || num_cache_opcodes < 0) {
	  goto fail;
	}
        {
	  OnigRepeatRange *repeat_range = &reg->repeat_range[repeat_mem];
	  if (repeat_range->lower < repeat_range->upper) {
	    num_cache_opcodes++;
	  }
        }
	break;
      case OP_REPEAT_INC:
      case OP_REPEAT_INC_NG:
	GET_MEMNUM_INC(repeat_mem, p);
	if (repeat_mem != current_repeat_mem) {
	  // A lone or invalid OP_REPEAT_INC is found.
	  goto impossible;
	}
	goto exit;
      case OP_REPEAT_INC_SG:
      case OP_REPEAT_INC_NG_SG:
	goto impossible;
      case OP_NULL_CHECK_START:
	p += SIZE_MEMNUM;
	break;
      case OP_NULL_CHECK_END:
      case OP_NULL_CHECK_END_MEMST_PUSH:
	p += SIZE_MEMNUM;
	break;
      case OP_NULL_CHECK_END_MEMST:
	p += SIZE_MEMNUM;
	break;

      case OP_PUSH_POS:
	if (lookaround_nesting < 0) {
	  // A look-around nested in a atomic grouping is found.
	  goto impossible;
	}
	result = count_num_cache_opcodes_inner(reg, current_repeat_mem, lookaround_nesting + 1, &p, &num_cache_opcodes);
	if (result < 0 || num_cache_opcodes < 0) {
	  goto fail;
	}
	break;
      case OP_PUSH_POS_NOT:
	if (lookaround_nesting < 0) {
	  // A look-around nested in a atomic grouping is found.
	  goto impossible;
	}
	p += SIZE_RELADDR;
	result = count_num_cache_opcodes_inner(reg, current_repeat_mem, lookaround_nesting + 1, &p, &num_cache_opcodes);
	if (result < 0 || num_cache_opcodes < 0) {
	  goto fail;
	}
	break;
      case OP_PUSH_LOOK_BEHIND_NOT:
	if (lookaround_nesting < 0) {
	  // A look-around nested in a atomic grouping is found.
	  goto impossible;
	}
	p += SIZE_RELADDR;
	p += SIZE_LENGTH;
	result = count_num_cache_opcodes_inner(reg, current_repeat_mem, lookaround_nesting + 1, &p, &num_cache_opcodes);
	if (result < 0 || num_cache_opcodes < 0) {
	  goto fail;
	}
	break;
      case OP_PUSH_STOP_BT:
	if (lookaround_nesting != 0) {
	  // A nested atomic grouping is found.
	  goto impossible;
	}
	result = count_num_cache_opcodes_inner(reg, current_repeat_mem, -1, &p, &num_cache_opcodes);
	if (result < 0 || num_cache_opcodes < 0) {
	  goto fail;
	}
	break;
      case OP_POP_POS:
      case OP_FAIL_POS:
      case OP_FAIL_LOOK_BEHIND_NOT:
      case OP_POP_STOP_BT:
	goto exit;
      case OP_LOOK_BEHIND:
	p += SIZE_LENGTH;
	break;

      case OP_PUSH_ABSENT_POS:
      case OP_ABSENT_END:
      case OP_ABSENT:
	goto impossible;

      case OP_CALL:
      case OP_RETURN:
	goto impossible;

      case OP_CONDITION:
	goto impossible;

      case OP_STATE_CHECK_PUSH:
      case OP_STATE_CHECK_PUSH_OR_JUMP:
      case OP_STATE_CHECK:
      case OP_STATE_CHECK_ANYCHAR_STAR:
      case OP_STATE_CHECK_ANYCHAR_ML_STAR:
	goto impossible;

      case OP_SET_OPTION_PUSH:
      case OP_SET_OPTION:
	p += SIZE_OPTION;
	break;

      default:
	goto bytecode_error;
    }
  }

exit:
  *pp = p;
  *num_cache_opcodes_ptr = num_cache_opcodes;
  return 0;

fail:
  *num_cache_opcodes_ptr = num_cache_opcodes;
  return result;

impossible:
  *num_cache_opcodes_ptr = NUM_CACHE_OPCODES_IMPOSSIBLE;
  return 0;

bytecode_error:
  return ONIGERR_UNDEFINED_BYTECODE;
}

/* count the total number of cache opcodes for allocating a match cache buffer. */
static OnigPosition
count_num_cache_opcodes(const regex_t* reg, long* num_cache_opcodes_ptr)
{
  UChar* p = reg->p;
  *num_cache_opcodes_ptr = 0;
  OnigPosition result = count_num_cache_opcodes_inner(reg, -1, 0, &p, num_cache_opcodes_ptr);
  if (result == 0 && *num_cache_opcodes_ptr >= 0 && p != reg->p + reg->used) {
    return ONIGERR_UNDEFINED_BYTECODE;
  }

  return result;
}

static OnigPosition
init_cache_opcodes_inner(
    const regex_t* reg,
    MemNumType current_repeat_mem, int lookaround_nesting,
    OnigCacheOpcode** cache_opcodes_ptr, UChar** pp, long* num_cache_points_ptr
)
{
  UChar* p = *pp;
  UChar* pend = reg->p + reg->used;
  UChar* pbegin;
  LengthType len;
  MemNumType repeat_mem;
  OnigEncoding enc = reg->enc;
  long cache_point = *num_cache_points_ptr;
  OnigCacheOpcode *cache_opcodes = *cache_opcodes_ptr;
  OnigPosition result;

# define INC_CACHE_OPCODES do {\
    cache_opcodes->addr = pbegin;\
    cache_opcodes->cache_point = cache_point;\
    cache_opcodes->outer_repeat_mem = current_repeat_mem;\
    cache_opcodes->num_cache_points_at_outer_repeat = 0;\
    cache_opcodes->num_cache_points_in_outer_repeat = 0;\
    cache_opcodes->lookaround_nesting = lookaround_nesting;\
    cache_opcodes->match_addr = NULL;\
    cache_point += lookaround_nesting != 0 ? 2 : 1;\
    cache_opcodes++;\
  } while (0)

  while (p < pend) {
    pbegin = p;
    switch (*p++) {
      case OP_FINISH:
      case OP_END:
	break;

      case OP_EXACT1: p++; break;
      case OP_EXACT2: p += 2; break;
      case OP_EXACT3: p += 3; break;
      case OP_EXACT4: p += 4; break;
      case OP_EXACT5: p += 5; break;
      case OP_EXACTN:
	GET_LENGTH_INC(len, p); p += len; break;
      case OP_EXACTMB2N1: p += 2; break;
      case OP_EXACTMB2N2: p += 4; break;
      case OP_EXACTMB2N3: p += 6; break;
      case OP_EXACTMB2N:
	GET_LENGTH_INC(len, p); p += len * 2; break;
      case OP_EXACTMB3N:
	GET_LENGTH_INC(len, p); p += len * 3; break;
      case OP_EXACTMBN:
	{
	  int mb_len;
	  GET_LENGTH_INC(mb_len, p);
	  GET_LENGTH_INC(len, p);
	  p += mb_len * len;
	}
	break;

      case OP_EXACT1_IC:
	len = enclen(enc, p, pend); p += len; break;
      case OP_EXACTN_IC:
	GET_LENGTH_INC(len, p); p += len; break;

      case OP_CCLASS:
      case OP_CCLASS_NOT:
	p += SIZE_BITSET; break;
      case OP_CCLASS_MB:
      case OP_CCLASS_MB_NOT:
	GET_LENGTH_INC(len, p); p += len; break;
      case OP_CCLASS_MIX:
      case OP_CCLASS_MIX_NOT:
	p += SIZE_BITSET;
	GET_LENGTH_INC(len, p);
	p += len;
	break;

      case OP_ANYCHAR:
      case OP_ANYCHAR_ML:
	break;
      case OP_ANYCHAR_STAR:
      case OP_ANYCHAR_ML_STAR:
	INC_CACHE_OPCODES;
	break;
      case OP_ANYCHAR_STAR_PEEK_NEXT:
      case OP_ANYCHAR_ML_STAR_PEEK_NEXT:
	p++;
	INC_CACHE_OPCODES;
	break;

      case OP_WORD:
      case OP_NOT_WORD:
      case OP_WORD_BOUND:
      case OP_NOT_WORD_BOUND:
      case OP_WORD_BEGIN:
      case OP_WORD_END:
	break;

      case OP_ASCII_WORD:
      case OP_NOT_ASCII_WORD:
      case OP_ASCII_WORD_BOUND:
      case OP_NOT_ASCII_WORD_BOUND:
      case OP_ASCII_WORD_BEGIN:
      case OP_ASCII_WORD_END:
	break;

      case OP_BEGIN_BUF:
      case OP_END_BUF:
      case OP_BEGIN_LINE:
      case OP_END_LINE:
      case OP_SEMI_END_BUF:
      case OP_BEGIN_POSITION:
	break;

      case OP_BACKREF1:
      case OP_BACKREF2:
      case OP_BACKREFN:
      case OP_BACKREFN_IC:
      case OP_BACKREF_MULTI:
      case OP_BACKREF_MULTI_IC:
      case OP_BACKREF_WITH_LEVEL:
	goto unexpected_bytecode_error;

      case OP_MEMORY_START:
      case OP_MEMORY_START_PUSH:
      case OP_MEMORY_END_PUSH:
      case OP_MEMORY_END_PUSH_REC:
      case OP_MEMORY_END:
      case OP_MEMORY_END_REC:
	p += SIZE_MEMNUM;
	if (lookaround_nesting != 0) {
	  goto unexpected_bytecode_error;
	}
	break;

      case OP_KEEP:
	break;

      case OP_FAIL:
	break;
      case OP_JUMP:
	p += SIZE_RELADDR;
	break;
      case OP_PUSH:
	p += SIZE_RELADDR;
	INC_CACHE_OPCODES;
	break;
      case OP_POP:
	break;
      case OP_PUSH_OR_JUMP_EXACT1:
      case OP_PUSH_IF_PEEK_NEXT:
	p += SIZE_RELADDR + 1;
	INC_CACHE_OPCODES;
	break;
      case OP_REPEAT:
      case OP_REPEAT_NG:
	GET_MEMNUM_INC(repeat_mem, p);
	p += SIZE_RELADDR;
	if (reg->repeat_range[repeat_mem].lower == 0) {
	  INC_CACHE_OPCODES;
	}
	{
	  long num_cache_points_in_repeat = 0;
          long num_cache_points_at_repeat = cache_point;
	  OnigCacheOpcode* cache_opcodes_in_repeat = cache_opcodes;
	  result = init_cache_opcodes_inner(reg, repeat_mem, lookaround_nesting, &cache_opcodes, &p, &num_cache_points_in_repeat);
	  if (result != 0) {
	    goto fail;
	  }
	  OnigRepeatRange *repeat_range = &reg->repeat_range[repeat_mem];
	  if (repeat_range->lower < repeat_range->upper) {
	    INC_CACHE_OPCODES;
	    cache_point -= lookaround_nesting != 0 ? 2 : 1;
	  }
	  int repeat_bounds = repeat_range->upper == 0x7fffffff ? 1 : repeat_range->upper - repeat_range->lower;
	  cache_point += num_cache_points_in_repeat * repeat_range->lower + (num_cache_points_in_repeat + (lookaround_nesting != 0 ? 2 : 1)) * repeat_bounds;
	  for (; cache_opcodes_in_repeat < cache_opcodes; cache_opcodes_in_repeat++) {
	    cache_opcodes_in_repeat->num_cache_points_at_outer_repeat = num_cache_points_at_repeat;
	    cache_opcodes_in_repeat->num_cache_points_in_outer_repeat = num_cache_points_in_repeat;
	  }
	}
	break;
      case OP_REPEAT_INC:
      case OP_REPEAT_INC_NG:
	p += SIZE_MEMNUM;
        goto exit;
      case OP_REPEAT_INC_SG:
      case OP_REPEAT_INC_NG_SG:
	goto unexpected_bytecode_error;
      case OP_NULL_CHECK_START:
	p += SIZE_MEMNUM;
	break;
      case OP_NULL_CHECK_END:
      case OP_NULL_CHECK_END_MEMST_PUSH:
	p += SIZE_MEMNUM;
	break;
      case OP_NULL_CHECK_END_MEMST:
	p += SIZE_MEMNUM;
	break;

      case OP_PUSH_POS:
	lookaround:
	{
	  OnigCacheOpcode* cache_opcodes_in_lookaround = cache_opcodes;
	  result = init_cache_opcodes_inner(reg, current_repeat_mem, lookaround_nesting + 1, &cache_opcodes, &p, &cache_point);
	  if (result != 0) {
	    goto fail;
	  }
	  UChar* match_addr = p - 1;
	  for (; cache_opcodes_in_lookaround < cache_opcodes; cache_opcodes_in_lookaround++) {
	    if (cache_opcodes_in_lookaround->match_addr == NULL) {
	      cache_opcodes_in_lookaround->match_addr = match_addr;
	    }
	  }
	}
	break;
      case OP_PUSH_POS_NOT:
	p += SIZE_RELADDR;
        goto lookaround;
      case OP_PUSH_LOOK_BEHIND_NOT:
	p += SIZE_RELADDR;
	p += SIZE_LENGTH;
        goto lookaround;
      case OP_PUSH_STOP_BT:
	{
	  OnigCacheOpcode* cache_opcodes_in_atomic = cache_opcodes;
	  result = init_cache_opcodes_inner(reg, current_repeat_mem, -1, &cache_opcodes, &p, &cache_point);
	  if (result != 0) {
	    goto fail;
	  }
	  UChar* match_addr = p - 1;
	  for (; cache_opcodes_in_atomic < cache_opcodes; cache_opcodes_in_atomic++) {
	    if (cache_opcodes_in_atomic->match_addr == NULL) {
	      cache_opcodes_in_atomic->match_addr = match_addr;
	    }
	  }
	}
	break;
      case OP_POP_POS:
      case OP_FAIL_POS:
      case OP_FAIL_LOOK_BEHIND_NOT:
      case OP_POP_STOP_BT:
	goto exit;
      case OP_LOOK_BEHIND:
	p += SIZE_LENGTH;
	break;

      case OP_ABSENT_END:
      case OP_ABSENT:
	goto unexpected_bytecode_error;

      case OP_CALL:
      case OP_RETURN:
	goto unexpected_bytecode_error;

      case OP_CONDITION:
	goto unexpected_bytecode_error;

      case OP_STATE_CHECK_PUSH:
      case OP_STATE_CHECK_PUSH_OR_JUMP:
      case OP_STATE_CHECK:
      case OP_STATE_CHECK_ANYCHAR_STAR:
      case OP_STATE_CHECK_ANYCHAR_ML_STAR:
	goto unexpected_bytecode_error;

      case OP_SET_OPTION_PUSH:
      case OP_SET_OPTION:
	p += SIZE_OPTION;
	break;

      default:
	goto bytecode_error;
    }
  }

exit:
  *cache_opcodes_ptr = cache_opcodes;
  *pp = p;
  *num_cache_points_ptr = cache_point;
  return 0;

fail:
  return result;

unexpected_bytecode_error:
  return ONIGERR_UNEXPECTED_BYTECODE;

bytecode_error:
  return ONIGERR_UNDEFINED_BYTECODE;
}

/* collect cache opcodes from the given regex program, and compute the total number of cache points. */
static OnigPosition
init_cache_opcodes(const regex_t* reg, OnigCacheOpcode* cache_opcodes_ptr, long* num_cache_points_ptr)
{
  UChar* p = reg->p;
  *num_cache_points_ptr = 0;
  OnigPosition result = init_cache_opcodes_inner(reg, -1, 0, &cache_opcodes_ptr, &p, num_cache_points_ptr);
  if (result == 0 && p != reg->p + reg->used) {
    return ONIGERR_UNDEFINED_BYTECODE;
  }

  return result;
}
#else
static OnigPosition
count_num_cache_opcodes(regex_t* reg, long* num_cache_opcodes)
{
  *num_cache_opcodes = NUM_CACHE_OPCODES_IMPOSSIBLE;
  return 0;
}
#endif /* USE_MATCH_CACHE */

extern int
onig_check_linear_time(OnigRegexType* reg)
{
  long num_cache_opcodes = 0;
  count_num_cache_opcodes(reg, &num_cache_opcodes);
  return num_cache_opcodes != NUM_CACHE_OPCODES_IMPOSSIBLE;
}

extern void
onig_region_clear(OnigRegion* region)
{
  int i;

  for (i = 0; i < region->num_regs; i++) {
    region->beg[i] = region->end[i] = ONIG_REGION_NOTPOS;
  }
#ifdef USE_CAPTURE_HISTORY
  history_root_free(region);
#endif
}

extern int
onig_region_resize(OnigRegion* region, int n)
{
  region->num_regs = n;

  if (n < ONIG_NREGION)
    n = ONIG_NREGION;

  if (region->allocated == 0) {
    region->beg = (OnigPosition* )xmalloc(n * sizeof(OnigPosition));
    if (region->beg == 0)
      return ONIGERR_MEMORY;

    region->end = (OnigPosition* )xmalloc(n * sizeof(OnigPosition));
    if (region->end == 0) {
      xfree(region->beg);
      return ONIGERR_MEMORY;
    }

    region->allocated = n;
  }
  else if (region->allocated < n) {
    OnigPosition *tmp;

    region->allocated = 0;
    tmp = (OnigPosition* )xrealloc(region->beg, n * sizeof(OnigPosition));
    if (tmp == 0) {
      xfree(region->beg);
      xfree(region->end);
      return ONIGERR_MEMORY;
    }
    region->beg = tmp;
    tmp = (OnigPosition* )xrealloc(region->end, n * sizeof(OnigPosition));
    if (tmp == 0) {
      xfree(region->beg);
      xfree(region->end);
      return ONIGERR_MEMORY;
    }
    region->end = tmp;

    region->allocated = n;
  }

  return 0;
}

static int
onig_region_resize_clear(OnigRegion* region, int n)
{
  int r;

  r = onig_region_resize(region, n);
  if (r != 0) return r;
  onig_region_clear(region);
  return 0;
}

extern int
onig_region_set(OnigRegion* region, int at, int beg, int end)
{
  if (at < 0) return ONIGERR_INVALID_ARGUMENT;

  if (at >= region->allocated) {
    int r = onig_region_resize(region, at + 1);
    if (r < 0) return r;
  }

  region->beg[at] = beg;
  region->end[at] = end;
  return 0;
}

extern void
onig_region_init(OnigRegion* region)
{
  region->num_regs     = 0;
  region->allocated    = 0;
  region->beg          = (OnigPosition* )0;
  region->end          = (OnigPosition* )0;
#ifdef USE_CAPTURE_HISTORY
  region->history_root = (OnigCaptureTreeNode* )0;
#endif
}

extern OnigRegion*
onig_region_new(void)
{
  OnigRegion* r;

  r = (OnigRegion* )xmalloc(sizeof(OnigRegion));
  if (r)
    onig_region_init(r);
  return r;
}

extern void
onig_region_free(OnigRegion* r, int free_self)
{
  if (r) {
    if (r->allocated > 0) {
      xfree(r->beg);
      xfree(r->end);
    }
#ifdef USE_CAPTURE_HISTORY
    history_root_free(r);
#endif
    if (free_self) {
      xfree(r);
    }
    else {
      memset(r, 0, sizeof(OnigRegion));
    }
  }
}

extern void
onig_region_copy(OnigRegion* to, const OnigRegion* from)
{
#define RREGC_SIZE   (sizeof(int) * from->num_regs)
  int i, r;

  if (to == from) return;

  r = onig_region_resize(to, from->num_regs);
  if (r) return;

  for (i = 0; i < from->num_regs; i++) {
    to->beg[i] = from->beg[i];
    to->end[i] = from->end[i];
  }
  to->num_regs = from->num_regs;

#ifdef USE_CAPTURE_HISTORY
  history_root_free(to);

  if (IS_NOT_NULL(from->history_root)) {
    to->history_root = history_tree_clone(from->history_root);
  }
#endif
}


/** stack **/
#define INVALID_STACK_INDEX   -1

/* stack type */
/* used by normal-POP */
#define STK_ALT                      0x0001
#define STK_LOOK_BEHIND_NOT          0x0002
#define STK_POS_NOT                  0x0003
/* handled by normal-POP */
#define STK_MEM_START                0x0100
#define STK_MEM_END                  0x8200
#define STK_REPEAT_INC               0x0300
#define STK_STATE_CHECK_MARK         0x1000
/* avoided by normal-POP */
#define STK_NULL_CHECK_START         0x3000
#define STK_NULL_CHECK_END           0x5000  /* for recursive call */
#define STK_MEM_END_MARK             0x8400
#define STK_POS                      0x0500  /* used when POP-POS */
#define STK_STOP_BT                  0x0600  /* mark for "(?>...)" */
#define STK_REPEAT                   0x0700
#define STK_CALL_FRAME               0x0800
#define STK_RETURN                   0x0900
#define STK_VOID                     0x0a00  /* for fill a blank */
#define STK_ABSENT_POS               0x0b00  /* for absent */
#define STK_ABSENT                   0x0c00  /* absent inner loop marker */
#define STK_MATCH_CACHE_POINT        0x0d00  /* for the match cache optimization */
#define STK_ATOMIC_MATCH_CACHE_POINT 0x0e00

/* stack type check mask */
#define STK_MASK_POP_USED            0x00ff
#define STK_MASK_TO_VOID_TARGET      0x10ff
#define STK_MASK_MEM_END_OR_MARK     0x8000  /* MEM_END or MEM_END_MARK */

#ifdef USE_MATCH_CACHE
#define MATCH_ARG_INIT_MATCH_CACHE(msa) do {\
  (msa).match_cache_status = MATCH_CACHE_STATUS_UNINIT;\
  (msa).num_fails = 0;\
  (msa).num_cache_opcodes = NUM_CACHE_OPCODES_UNINIT;\
  (msa).cache_opcodes = (OnigCacheOpcode*)NULL;\
  (msa).num_cache_points = 0;\
  (msa).match_cache_buf = (uint8_t*)NULL;\
} while(0)
#define MATCH_ARG_FREE_MATCH_CACHE(msa) do {\
  xfree((msa).cache_opcodes);\
  xfree((msa).match_cache_buf);\
  (msa).cache_opcodes = (OnigCacheOpcode*)NULL;\
  (msa).match_cache_buf = (uint8_t*)NULL;\
} while(0)
#else
#define MATCH_ARG_INIT_MATCH_CACHE(msa)
#define MATCH_ARG_FREE_MATCH_CACHE(msa)
#endif

#ifdef USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE
# define MATCH_ARG_INIT(msa, arg_option, arg_region, arg_start, arg_gpos) do {\
  (msa).stack_p  = (void* )0;\
  (msa).options  = (arg_option);\
  (msa).region   = (arg_region);\
  (msa).start    = (arg_start);\
  (msa).gpos     = (arg_gpos);\
  (msa).best_len = ONIG_MISMATCH;\
  (msa).counter  = 0;\
  (msa).end_time = 0;\
  MATCH_ARG_INIT_MATCH_CACHE(msa);\
} while(0)
#else
# define MATCH_ARG_INIT(msa, arg_option, arg_region, arg_start, arg_gpos) do {\
  (msa).stack_p  = (void* )0;\
  (msa).options  = (arg_option);\
  (msa).region   = (arg_region);\
  (msa).start    = (arg_start);\
  (msa).gpos     = (arg_gpos);\
  (msa).counter  = 0;\
  (msa).end_time = 0;\
  MATCH_ARG_INIT_MATCH_CACHE(msa);\
} while(0)
#endif

#ifdef USE_COMBINATION_EXPLOSION_CHECK

# define STATE_CHECK_BUFF_MALLOC_THRESHOLD_SIZE  16

# define STATE_CHECK_BUFF_INIT(msa, str_len, offset, state_num) do {	\
  if ((state_num) > 0 && str_len >= STATE_CHECK_STRING_THRESHOLD_LEN) {\
    unsigned int size = (unsigned int )(((str_len) + 1) * (state_num) + 7) >> 3;\
    offset = ((offset) * (state_num)) >> 3;\
    if (size > 0 && offset < size && size < STATE_CHECK_BUFF_MAX_SIZE) {\
      if (size >= STATE_CHECK_BUFF_MALLOC_THRESHOLD_SIZE) {\
        (msa).state_check_buff = (void* )xmalloc(size);\
        CHECK_NULL_RETURN_MEMERR((msa).state_check_buff);\
      }\
      else \
        (msa).state_check_buff = (void* )xalloca(size);\
      xmemset(((char* )((msa).state_check_buff)+(offset)), 0, \
              (size_t )(size - (offset))); \
      (msa).state_check_buff_size = size;\
    }\
    else {\
      (msa).state_check_buff = (void* )0;\
      (msa).state_check_buff_size = 0;\
    }\
  }\
  else {\
    (msa).state_check_buff = (void* )0;\
    (msa).state_check_buff_size = 0;\
  }\
  } while(0)

# define MATCH_ARG_FREE(msa) do {\
  xfree((msa).stack_p);\
  if ((msa).state_check_buff_size >= STATE_CHECK_BUFF_MALLOC_THRESHOLD_SIZE) { \
    xfree((msa).state_check_buff);\
  }\
  MATCH_ARG_FREE_MATCH_CACHE(msa);\
} while(0)
#else /* USE_COMBINATION_EXPLOSION_CHECK */
# define MATCH_ARG_FREE(msa) do {\
  xfree((msa).stack_p);\
  MATCH_ARG_FREE_MATCH_CACHE(msa);\
} while (0)
#endif /* USE_COMBINATION_EXPLOSION_CHECK */



#define MAX_PTR_NUM 100

#define STACK_INIT(alloc_addr, heap_addr, ptr_num, stack_num)  do {\
  if (ptr_num > MAX_PTR_NUM) {\
    alloc_addr = (char* )xmalloc(sizeof(OnigStackIndex) * (ptr_num));\
    heap_addr  = alloc_addr;\
    if (msa->stack_p) {\
      stk_alloc = (OnigStackType* )(msa->stack_p);\
      stk_base  = stk_alloc;\
      stk       = stk_base;\
      stk_end   = stk_base + msa->stack_n;\
    } else {\
      stk_alloc = (OnigStackType* )xalloca(sizeof(OnigStackType) * (stack_num));\
      stk_base  = stk_alloc;\
      stk       = stk_base;\
      stk_end   = stk_base + (stack_num);\
    }\
  } else if (msa->stack_p) {\
    alloc_addr = (char* )xalloca(sizeof(OnigStackIndex) * (ptr_num));\
    heap_addr  = NULL;\
    stk_alloc  = (OnigStackType* )(msa->stack_p);\
    stk_base   = stk_alloc;\
    stk        = stk_base;\
    stk_end    = stk_base + msa->stack_n;\
  }\
  else {\
    alloc_addr = (char* )xalloca(sizeof(OnigStackIndex) * (ptr_num)\
		       + sizeof(OnigStackType) * (stack_num));\
    heap_addr  = NULL;\
    stk_alloc  = (OnigStackType* )(alloc_addr + sizeof(OnigStackIndex) * (ptr_num));\
    stk_base   = stk_alloc;\
    stk        = stk_base;\
    stk_end    = stk_base + (stack_num);\
  }\
} while(0)

#define STACK_SAVE do{\
  if (stk_base != stk_alloc) {\
    msa->stack_p = stk_base;\
    msa->stack_n = stk_end - stk_base; /* TODO: check overflow */\
  };\
} while(0)

static unsigned int MatchStackLimitSize = DEFAULT_MATCH_STACK_LIMIT_SIZE;

extern unsigned int
onig_get_match_stack_limit_size(void)
{
  return MatchStackLimitSize;
}

extern int
onig_set_match_stack_limit_size(unsigned int size)
{
  MatchStackLimitSize = size;
  return 0;
}

static int
stack_double(OnigStackType** arg_stk_base, OnigStackType** arg_stk_end,
	     OnigStackType** arg_stk, OnigStackType* stk_alloc, OnigMatchArg* msa)
{
  size_t n;
  OnigStackType *x, *stk_base, *stk_end, *stk;

  stk_base = *arg_stk_base;
  stk_end  = *arg_stk_end;
  stk      = *arg_stk;

  n = stk_end - stk_base;
  if (stk_base == stk_alloc && IS_NULL(msa->stack_p)) {
    x = (OnigStackType* )xmalloc(sizeof(OnigStackType) * n * 2);
    if (IS_NULL(x)) {
      STACK_SAVE;
      return ONIGERR_MEMORY;
    }
    xmemcpy(x, stk_base, n * sizeof(OnigStackType));
    n *= 2;
  }
  else {
    unsigned int limit_size = MatchStackLimitSize;
    n *= 2;
    if (limit_size != 0 && n > limit_size) {
      if ((unsigned int )(stk_end - stk_base) == limit_size)
	return ONIGERR_MATCH_STACK_LIMIT_OVER;
      else
	n = limit_size;
    }
    x = (OnigStackType* )xrealloc(stk_base, sizeof(OnigStackType) * n);
    if (IS_NULL(x)) {
      STACK_SAVE;
      return ONIGERR_MEMORY;
    }
  }
  *arg_stk      = x + (stk - stk_base);
  *arg_stk_base = x;
  *arg_stk_end  = x + n;
  return 0;
}

#define STACK_ENSURE(n)	do {\
  if (stk_end - stk < (n)) {\
    int r = stack_double(&stk_base, &stk_end, &stk, stk_alloc, msa);\
    if (r != 0) {\
      STACK_SAVE;\
      xfree(xmalloc_base);\
      return r;\
    }\
  }\
} while(0)

#define STACK_AT(index)        (stk_base + (index))
#define GET_STACK_INDEX(stk)   ((stk) - stk_base)

#define STACK_PUSH_TYPE(stack_type) do {\
  STACK_ENSURE(1);\
  stk->type = (stack_type);\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  STACK_INC;\
} while(0)

#define IS_TO_VOID_TARGET(stk) (((stk)->type & STK_MASK_TO_VOID_TARGET) != 0)

#ifdef USE_COMBINATION_EXPLOSION_CHECK
# define STATE_CHECK_POS(s,snum) \
  (((s) - str) * num_comb_exp_check + ((snum) - 1))
# define STATE_CHECK_VAL(v,snum) do {\
  if (state_check_buff != NULL) {\
    ptrdiff_t x = STATE_CHECK_POS(s,snum);\
    (v) = state_check_buff[x/8] & (1<<(x%8));\
  }\
  else (v) = 0;\
} while(0)


# define ELSE_IF_STATE_CHECK_MARK(stk) \
  else if ((stk)->type == STK_STATE_CHECK_MARK) { \
    ptrdiff_t x = STATE_CHECK_POS(stk->u.state.pstr, stk->u.state.state_check);\
    state_check_buff[x/8] |= (1<<(x%8));				\
  }

# define STACK_PUSH(stack_type,pat,s,sprev,keep) do {\
  STACK_ENSURE(1);\
  stk->type = (stack_type);\
  stk->u.state.pcode     = (pat);\
  stk->u.state.pstr      = (s);\
  stk->u.state.pstr_prev = (sprev);\
  stk->u.state.state_check = 0;\
  stk->u.state.pkeep     = (keep);\
  STACK_INC;\
} while(0)

# define STACK_PUSH_ENSURED(stack_type,pat) do {\
  stk->type = (stack_type);\
  stk->u.state.pcode = (pat);\
  stk->u.state.state_check = 0;\
  STACK_INC;\
} while(0)

# define STACK_PUSH_ALT_WITH_STATE_CHECK(pat,s,sprev,snum,keep) do {\
  STACK_ENSURE(1);\
  stk->type = STK_ALT;\
  stk->u.state.pcode     = (pat);\
  stk->u.state.pstr      = (s);\
  stk->u.state.pstr_prev = (sprev);\
  stk->u.state.state_check = ((state_check_buff != NULL) ? (snum) : 0);\
  stk->u.state.pkeep     = (keep);\
  STACK_INC;\
} while(0)

# define STACK_PUSH_STATE_CHECK(s,snum) do {\
  if (state_check_buff != NULL) {\
    STACK_ENSURE(1);\
    stk->type = STK_STATE_CHECK_MARK;\
    stk->u.state.pstr = (s);\
    stk->u.state.state_check = (snum);\
    STACK_INC;\
  }\
} while(0)

#else /* USE_COMBINATION_EXPLOSION_CHECK */

# define ELSE_IF_STATE_CHECK_MARK(stk)

# define STACK_PUSH(stack_type,pat,s,sprev,keep) do {\
  STACK_ENSURE(1);\
  stk->type = (stack_type);\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.state.pcode     = (pat);\
  stk->u.state.pstr      = (s);\
  stk->u.state.pstr_prev = (sprev);\
  stk->u.state.pkeep     = (keep);\
  STACK_INC;\
} while(0)

# define STACK_PUSH_ENSURED(stack_type,pat) do {\
  stk->type = (stack_type);\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.state.pcode = (pat);\
  STACK_INC;\
} while(0)
#endif /* USE_COMBINATION_EXPLOSION_CHECK */

#define STACK_PUSH_ALT(pat,s,sprev,keep)     STACK_PUSH(STK_ALT,pat,s,sprev,keep)
#define STACK_PUSH_POS(s,sprev,keep)         STACK_PUSH(STK_POS,NULL_UCHARP,s,sprev,keep)
#define STACK_PUSH_POS_NOT(pat,s,sprev,keep) STACK_PUSH(STK_POS_NOT,pat,s,sprev,keep)
#define STACK_PUSH_ABSENT                    STACK_PUSH_TYPE(STK_ABSENT)
#define STACK_PUSH_STOP_BT                   STACK_PUSH_TYPE(STK_STOP_BT)
#define STACK_PUSH_LOOK_BEHIND_NOT(pat,s,sprev,keep) \
        STACK_PUSH(STK_LOOK_BEHIND_NOT,pat,s,sprev,keep)

#define STACK_PUSH_REPEAT(id, pat) do {\
  STACK_ENSURE(1);\
  stk->type = STK_REPEAT;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.repeat.num    = (id);\
  stk->u.repeat.pcode  = (pat);\
  stk->u.repeat.count  = 0;\
  STACK_INC;\
} while(0)

#define STACK_PUSH_REPEAT_INC(sindex) do {\
  STACK_ENSURE(1);\
  stk->type = STK_REPEAT_INC;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.repeat_inc.si  = (sindex);\
  STACK_INC;\
} while(0)

#define STACK_PUSH_MEM_START(mnum, s) do {\
  STACK_ENSURE(1);\
  stk->type = STK_MEM_START;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.mem.num      = (mnum);\
  stk->u.mem.pstr     = (s);\
  stk->u.mem.start    = mem_start_stk[mnum];\
  stk->u.mem.end      = mem_end_stk[mnum];\
  mem_start_stk[mnum] = GET_STACK_INDEX(stk);\
  mem_end_stk[mnum]   = INVALID_STACK_INDEX;\
  STACK_INC;\
} while(0)

#define STACK_PUSH_MEM_END(mnum, s) do {\
  STACK_ENSURE(1);\
  stk->type = STK_MEM_END;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.mem.num    = (mnum);\
  stk->u.mem.pstr   = (s);\
  stk->u.mem.start  = mem_start_stk[mnum];\
  stk->u.mem.end    = mem_end_stk[mnum];\
  mem_end_stk[mnum] = GET_STACK_INDEX(stk);\
  STACK_INC;\
} while(0)

#define STACK_PUSH_MEM_END_MARK(mnum) do {\
  STACK_ENSURE(1);\
  stk->type = STK_MEM_END_MARK;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.mem.num = (mnum);\
  STACK_INC;\
} while(0)

#define STACK_GET_MEM_START(mnum, k) do {\
  int level = 0;\
  k = stk;\
  while (k > stk_base) {\
    k--;\
    if ((k->type & STK_MASK_MEM_END_OR_MARK) != 0 \
      && k->u.mem.num == (mnum)) {\
      level++;\
    }\
    else if (k->type == STK_MEM_START && k->u.mem.num == (mnum)) {\
      if (level == 0) break;\
      level--;\
    }\
  }\
} while(0)

#define STACK_GET_MEM_RANGE(k, mnum, start, end) do {\
  int level = 0;\
  while (k < stk) {\
    if (k->type == STK_MEM_START && k->u.mem.num == (mnum)) {\
      if (level == 0) (start) = k->u.mem.pstr;\
      level++;\
    }\
    else if (k->type == STK_MEM_END && k->u.mem.num == (mnum)) {\
      level--;\
      if (level == 0) {\
        (end) = k->u.mem.pstr;\
        break;\
      }\
    }\
    k++;\
  }\
} while(0)

#define STACK_PUSH_NULL_CHECK_START(cnum, s) do {\
  STACK_ENSURE(1);\
  stk->type = STK_NULL_CHECK_START;\
  stk->null_check = (OnigStackIndex)(stk - stk_base);\
  stk->u.null_check.num  = (cnum);\
  stk->u.null_check.pstr = (s);\
  STACK_INC;\
} while(0)

#define STACK_PUSH_NULL_CHECK_END(cnum) do {\
  STACK_ENSURE(1);\
  stk->type = STK_NULL_CHECK_END;\
  stk->null_check = (OnigStackIndex)(stk - stk_base);\
  stk->u.null_check.num  = (cnum);\
  STACK_INC;\
} while(0)

#define STACK_PUSH_CALL_FRAME(pat) do {\
  STACK_ENSURE(1);\
  stk->type = STK_CALL_FRAME;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.call_frame.ret_addr = (pat);\
  STACK_INC;\
} while(0)

#define STACK_PUSH_RETURN do {\
  STACK_ENSURE(1);\
  stk->type = STK_RETURN;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  STACK_INC;\
} while(0)

#define STACK_PUSH_ABSENT_POS(start, end) do {\
  STACK_ENSURE(1);\
  stk->type = STK_ABSENT_POS;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.absent_pos.abs_pstr = (start);\
  stk->u.absent_pos.end_pstr = (end);\
  STACK_INC;\
} while(0)

#define STACK_PUSH_MATCH_CACHE_POINT(match_cache_point_index, match_cache_point_mask) do {\
  STACK_ENSURE(1);\
  stk->type = STK_MATCH_CACHE_POINT;\
  stk->null_check = stk == stk_base ? 0 : (stk-1)->null_check;\
  stk->u.match_cache_point.index = (match_cache_point_index);\
  stk->u.match_cache_point.mask = (match_cache_point_mask);\
  STACK_INC;\
} while(0)


#ifdef ONIG_DEBUG
# define STACK_BASE_CHECK(p, at) \
  if ((p) < stk_base) {\
    fprintf(stderr, "at %s\n", at);\
    goto stack_error;\
  }
#else
# define STACK_BASE_CHECK(p, at)
#endif

#ifdef ONIG_DEBUG_MATCH_CACHE
# define MATCH_CACHE_DEBUG_MEMOIZE(stkp) fprintf(stderr, "MATCH CACHE: memoize (index=%ld mask=%d)\n", stkp->u.match_cache_point.index, stkp->u.match_cache_point.mask);
#else
# define MATCH_CACHE_DEBUG_MEMOIZE(stkp) ((void) 0)
#endif

#ifdef USE_MATCH_CACHE
# define INC_NUM_FAILS msa->num_fails++
# define MEMOIZE_MATCH_CACHE_POINT do {\
    if (stk->type == STK_MATCH_CACHE_POINT) {\
      msa->match_cache_buf[stk->u.match_cache_point.index] |= stk->u.match_cache_point.mask;\
      MATCH_CACHE_DEBUG_MEMOIZE(stk);\
    } else if (stk->type == STK_ATOMIC_MATCH_CACHE_POINT) {\
      memoize_extended_match_cache_point(msa->match_cache_buf, stk->u.match_cache_point.index, stk->u.match_cache_point.mask);\
      MATCH_CACHE_DEBUG_MEMOIZE(stkp);\
    }\
  } while(0)
# define MEMOIZE_LOOKAROUND_MATCH_CACHE_POINT(stkp) do {\
    if (stkp->type == STK_MATCH_CACHE_POINT) {\
      stkp->type = STK_VOID;\
      memoize_extended_match_cache_point(msa->match_cache_buf, stkp->u.match_cache_point.index, stkp->u.match_cache_point.mask);\
      MATCH_CACHE_DEBUG_MEMOIZE(stkp);\
    }\
  } while(0)
# define MEMOIZE_ATOMIC_MATCH_CACHE_POINT do {\
    if (stk->type == STK_MATCH_CACHE_POINT) {\
      memoize_extended_match_cache_point(msa->match_cache_buf, stk->u.match_cache_point.index, stk->u.match_cache_point.mask);\
      MATCH_CACHE_DEBUG_MEMOIZE(stkp);\
    }\
  } while(0)
#else
# define INC_NUM_FAILS ((void) 0)
# define MEMOIZE_MATCH_CACHE_POINT ((void) 0)
# define MEMOIZE_LOOKAROUND_MATCH_CACHE_POINT ((void) 0)
#endif

#define STACK_POP_ONE do {\
  stk--;\
  STACK_BASE_CHECK(stk, "STACK_POP_ONE"); \
} while(0)

#define STACK_POP  do {\
  switch (pop_level) {\
  case STACK_POP_LEVEL_FREE:\
    while (1) {\
      stk--;\
      STACK_BASE_CHECK(stk, "STACK_POP"); \
      if ((stk->type & STK_MASK_POP_USED) != 0)  break;\
      ELSE_IF_STATE_CHECK_MARK(stk);\
      MEMOIZE_MATCH_CACHE_POINT;\
    }\
    break;\
  case STACK_POP_LEVEL_MEM_START:\
    while (1) {\
      stk--;\
      STACK_BASE_CHECK(stk, "STACK_POP 2"); \
      if ((stk->type & STK_MASK_POP_USED) != 0)  break;\
      else if (stk->type == STK_MEM_START) {\
        mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
        mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
      }\
      ELSE_IF_STATE_CHECK_MARK(stk);\
      MEMOIZE_MATCH_CACHE_POINT;\
    }\
    break;\
  default:\
    while (1) {\
      stk--;\
      STACK_BASE_CHECK(stk, "STACK_POP 3"); \
      if ((stk->type & STK_MASK_POP_USED) != 0)  break;\
      else if (stk->type == STK_MEM_START) {\
        mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
        mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
      }\
      else if (stk->type == STK_REPEAT_INC) {\
        STACK_AT(stk->u.repeat_inc.si)->u.repeat.count--;\
      }\
      else if (stk->type == STK_MEM_END) {\
        mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
        mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
      }\
      ELSE_IF_STATE_CHECK_MARK(stk);\
      MEMOIZE_MATCH_CACHE_POINT;\
    }\
    break;\
  }\
} while(0)

#define STACK_POP_TIL_POS_NOT  do {\
  while (1) {\
    stk--;\
    STACK_BASE_CHECK(stk, "STACK_POP_TIL_POS_NOT"); \
    if (stk->type == STK_POS_NOT) break;\
    else if (stk->type == STK_MEM_START) {\
      mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
      mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
    }\
    else if (stk->type == STK_REPEAT_INC) {\
      STACK_AT(stk->u.repeat_inc.si)->u.repeat.count--;\
    }\
    else if (stk->type == STK_MEM_END) {\
      mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
      mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
    }\
    else if (IS_TO_VOID_TARGET(stk)) {\
      INC_NUM_FAILS;\
    }\
    ELSE_IF_STATE_CHECK_MARK(stk);\
    MEMOIZE_LOOKAROUND_MATCH_CACHE_POINT(stk);\
  }\
} while(0)

#define STACK_POP_TIL_LOOK_BEHIND_NOT  do {\
  while (1) {\
    stk--;\
    STACK_BASE_CHECK(stk, "STACK_POP_TIL_LOOK_BEHIND_NOT"); \
    if (stk->type == STK_LOOK_BEHIND_NOT) break;\
    else if (stk->type == STK_MEM_START) {\
      mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
      mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
    }\
    else if (stk->type == STK_REPEAT_INC) {\
      STACK_AT(stk->u.repeat_inc.si)->u.repeat.count--;\
    }\
    else if (stk->type == STK_MEM_END) {\
      mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
      mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
    }\
    ELSE_IF_STATE_CHECK_MARK(stk);\
  }\
} while(0)

#define STACK_POP_TIL_ABSENT  do {\
  while (1) {\
    stk--;\
    STACK_BASE_CHECK(stk, "STACK_POP_TIL_ABSENT"); \
    if (stk->type == STK_ABSENT) break;\
    else if (stk->type == STK_MEM_START) {\
      mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
      mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
    }\
    else if (stk->type == STK_REPEAT_INC) {\
      STACK_AT(stk->u.repeat_inc.si)->u.repeat.count--;\
    }\
    else if (stk->type == STK_MEM_END) {\
      mem_start_stk[stk->u.mem.num] = stk->u.mem.start;\
      mem_end_stk[stk->u.mem.num]   = stk->u.mem.end;\
    }\
    ELSE_IF_STATE_CHECK_MARK(stk);\
  }\
} while(0)

#define STACK_POP_ABSENT_POS(start, end) do {\
  stk--;\
  STACK_BASE_CHECK(stk, "STACK_POP_ABSENT_POS"); \
  (start) = stk->u.absent_pos.abs_pstr;\
  (end) = stk->u.absent_pos.end_pstr;\
} while(0)

#define STACK_POS_END(k) do {\
  k = stk;\
  while (1) {\
    k--;\
    STACK_BASE_CHECK(k, "STACK_POS_END"); \
    if (IS_TO_VOID_TARGET(k)) {\
      INC_NUM_FAILS;\
      k->type = STK_VOID;\
    }\
    else if (k->type == STK_POS) {\
      k->type = STK_VOID;\
      break;\
    }\
    MEMOIZE_LOOKAROUND_MATCH_CACHE_POINT(k);\
  }\
} while(0)

#define STACK_STOP_BT_END do {\
  OnigStackType *k = stk;\
  while (1) {\
    k--;\
    STACK_BASE_CHECK(k, "STACK_STOP_BT_END"); \
    if (IS_TO_VOID_TARGET(k)) {\
      INC_NUM_FAILS;\
      k->type = STK_VOID;\
    }\
    else if (k->type == STK_STOP_BT) {\
      k->type = STK_VOID;\
      break;\
    }\
    else if (k->type == STK_MATCH_CACHE_POINT) {\
      k->type = STK_ATOMIC_MATCH_CACHE_POINT;\
    }\
  }\
} while(0)

#define STACK_STOP_BT_FAIL do {\
  while (1) {\
    stk--;\
    STACK_BASE_CHECK(stk, "STACK_STOP_BT_END"); \
    if (stk->type == STK_STOP_BT) {\
      stk->type = STK_VOID;\
      break;\
    }\
    MEMOIZE_ATOMIC_MATCH_CACHE_POINT;\
  }\
} while(0)

#define STACK_NULL_CHECK(isnull,id,s) do {\
  OnigStackType* k = STACK_AT((stk-1)->null_check)+1;\
  while (1) {\
    k--;\
    STACK_BASE_CHECK(k, "STACK_NULL_CHECK"); \
    if (k->type == STK_NULL_CHECK_START) {\
      if (k->u.null_check.num == (id)) {\
        (isnull) = (k->u.null_check.pstr == (s));\
        break;\
      }\
    }\
  }\
} while(0)

#define STACK_NULL_CHECK_REC(isnull,id,s) do {\
  int level = 0;\
  OnigStackType* k = STACK_AT((stk-1)->null_check)+1;\
  while (1) {\
    k--;\
    STACK_BASE_CHECK(k, "STACK_NULL_CHECK_REC"); \
    if (k->type == STK_NULL_CHECK_START) {\
      if (k->u.null_check.num == (id)) {\
        if (level == 0) {\
          (isnull) = (k->u.null_check.pstr == (s));\
          break;\
        }\
        else level--;\
      }\
    }\
    else if (k->type == STK_NULL_CHECK_END) {\
      level++;\
    }\
  }\
} while(0)

#define STACK_NULL_CHECK_MEMST(isnull,id,s,reg) do {\
  OnigStackType* k = STACK_AT((stk-1)->null_check)+1;\
  while (1) {\
    k--;\
    STACK_BASE_CHECK(k, "STACK_NULL_CHECK_MEMST"); \
    if (k->type == STK_NULL_CHECK_START) {\
      if (k->u.null_check.num == (id)) {\
        if (k->u.null_check.pstr != (s)) {\
          (isnull) = 0;\
          break;\
        }\
        else {\
          UChar* endp;\
          (isnull) = 1;\
          while (k < stk) {\
            if (k->type == STK_MEM_START) {\
              if (k->u.mem.end == INVALID_STACK_INDEX) {\
                (isnull) = 0; break;\
              }\
              if (BIT_STATUS_AT(reg->bt_mem_end, k->u.mem.num))\
                endp = STACK_AT(k->u.mem.end)->u.mem.pstr;\
              else\
                endp = (UChar* )k->u.mem.end;\
              if (STACK_AT(k->u.mem.start)->u.mem.pstr != endp) {\
                (isnull) = 0; break;\
              }\
              else if (endp != s) {\
                (isnull) = -1; /* empty, but position changed */ \
              }\
            }\
            k++;\
          }\
          break;\
        }\
      }\
    }\
  }\
} while(0)

#define STACK_NULL_CHECK_MEMST_REC(isnull,id,s,reg) do {\
  int level = 0;\
  OnigStackType* k = STACK_AT((stk-1)->null_check)+1;\
  while (1) {\
    k--;\
    STACK_BASE_CHECK(k, "STACK_NULL_CHECK_MEMST_REC"); \
    if (k->type == STK_NULL_CHECK_START) {\
      if (k->u.null_check.num == (id)) {\
        if (level == 0) {\
          if (k->u.null_check.pstr != (s)) {\
            (isnull) = 0;\
            break;\
          }\
          else {\
            UChar* endp;\
            (isnull) = 1;\
            while (k < stk) {\
              if (k->type == STK_MEM_START) {\
                if (k->u.mem.end == INVALID_STACK_INDEX) {\
                  (isnull) = 0; break;\
                }\
                if (BIT_STATUS_AT(reg->bt_mem_end, k->u.mem.num))\
                  endp = STACK_AT(k->u.mem.end)->u.mem.pstr;\
                else\
                  endp = (UChar* )k->u.mem.end;\
                if (STACK_AT(k->u.mem.start)->u.mem.pstr != endp) {\
                  (isnull) = 0; break;\
                }\
                else if (endp != s) {\
                  (isnull) = -1; /* empty, but position changed */ \
                }\
              }\
              k++;\
            }\
            break;\
          }\
        }\
        else {\
          level--;\
        }\
      }\
    }\
    else if (k->type == STK_NULL_CHECK_END) {\
      if (k->u.null_check.num == (id)) level++;\
    }\
  }\
} while(0)

#define STACK_GET_REPEAT(id, k) do {\
  int level = 0;\
  k = stk;\
  while (1) {\
    k--;\
    STACK_BASE_CHECK(k, "STACK_GET_REPEAT"); \
    if (k->type == STK_REPEAT) {\
      if (level == 0) {\
        if (k->u.repeat.num == (id)) {\
          break;\
        }\
      }\
    }\
    else if (k->type == STK_CALL_FRAME) level--;\
    else if (k->type == STK_RETURN)     level++;\
  }\
} while(0)

#define STACK_RETURN(addr)  do {\
  int level = 0;\
  OnigStackType* k = stk;\
  while (1) {\
    k--;\
    STACK_BASE_CHECK(k, "STACK_RETURN"); \
    if (k->type == STK_CALL_FRAME) {\
      if (level == 0) {\
        (addr) = k->u.call_frame.ret_addr;\
        break;\
      }\
      else level--;\
    }\
    else if (k->type == STK_RETURN)\
      level++;\
  }\
} while(0)


#define STRING_CMP(s1,s2,len) do {\
  while (len-- > 0) {\
    if (*s1++ != *s2++) goto fail;\
  }\
} while(0)

#define STRING_CMP_IC(case_fold_flag,s1,ps2,len,text_end) do {\
  if (string_cmp_ic(encode, case_fold_flag, s1, ps2, len, text_end) == 0) \
    goto fail; \
} while(0)

static int string_cmp_ic(OnigEncoding enc, int case_fold_flag,
			 UChar* s1, UChar** ps2, OnigDistance mblen, const UChar* text_end)
{
  UChar buf1[ONIGENC_MBC_CASE_FOLD_MAXLEN];
  UChar buf2[ONIGENC_MBC_CASE_FOLD_MAXLEN];
  UChar *p1, *p2, *end1, *s2;
  int len1, len2;

  s2   = *ps2;
  end1 = s1 + mblen;
  while (s1 < end1) {
    len1 = ONIGENC_MBC_CASE_FOLD(enc, case_fold_flag, &s1, text_end, buf1);
    len2 = ONIGENC_MBC_CASE_FOLD(enc, case_fold_flag, &s2, text_end, buf2);
    if (len1 != len2) return 0;
    p1 = buf1;
    p2 = buf2;
    while (len1-- > 0) {
      if (*p1 != *p2) return 0;
      p1++;
      p2++;
    }
  }

  *ps2 = s2;
  return 1;
}

#define STRING_CMP_VALUE(s1,s2,len,is_fail) do {\
  is_fail = 0;\
  while (len-- > 0) {\
    if (*s1++ != *s2++) {\
      is_fail = 1; break;\
    }\
  }\
} while(0)

#define STRING_CMP_VALUE_IC(case_fold_flag,s1,ps2,len,text_end,is_fail) do {\
  if (string_cmp_ic(encode, case_fold_flag, s1, ps2, len, text_end) == 0) \
    is_fail = 1; \
  else \
    is_fail = 0; \
} while(0)


#define IS_EMPTY_STR           (str == end)
#define ON_STR_BEGIN(s)        ((s) == str)
#define ON_STR_END(s)          ((s) == end)
#ifdef USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE
# define DATA_ENSURE_CHECK1    (s < right_range)
# define DATA_ENSURE_CHECK(n)  (s + (n) <= right_range)
# define DATA_ENSURE(n)        if (s + (n) > right_range) goto fail
# define DATA_ENSURE_CONTINUE(n) if (s + (n) > right_range) continue
# define ABSENT_END_POS        right_range
#else
# define DATA_ENSURE_CHECK1    (s < end)
# define DATA_ENSURE_CHECK(n)  (s + (n) <= end)
# define DATA_ENSURE(n)        if (s + (n) > end) goto fail
# define DATA_ENSURE_CONTINUE(n) if (s + (n) > end) continue
# define ABSENT_END_POS        end
#endif /* USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE */

int onigenc_mbclen_approximate(const OnigUChar* p,const OnigUChar* e, const struct OnigEncodingTypeST* enc);

static inline int
enclen_approx(OnigEncoding enc, const OnigUChar* p, const OnigUChar* e)
{
    if (enc->max_enc_len == enc->min_enc_len) {
        return (p < e ? enc->min_enc_len : 0);
    }
    else {
        return onigenc_mbclen_approximate(p, e, enc);
    }
}


#ifdef USE_CAPTURE_HISTORY
static int
make_capture_history_tree(OnigCaptureTreeNode* node, OnigStackType** kp,
                          OnigStackType* stk_top, UChar* str, regex_t* reg)
{
  int n, r;
  OnigCaptureTreeNode* child;
  OnigStackType* k = *kp;

  while (k < stk_top) {
    if (k->type == STK_MEM_START) {
      n = k->u.mem.num;
      if (n <= ONIG_MAX_CAPTURE_HISTORY_GROUP &&
	  BIT_STATUS_AT(reg->capture_history, n) != 0) {
	child = history_node_new();
	CHECK_NULL_RETURN_MEMERR(child);
	child->group = n;
	child->beg = k->u.mem.pstr - str;
	r = history_tree_add_child(node, child);
	if (r != 0) {
	  history_tree_free(child);
	  return r;
	}
	*kp = (k + 1);
	r = make_capture_history_tree(child, kp, stk_top, str, reg);
	if (r != 0) return r;

	k = *kp;
	child->end = k->u.mem.pstr - str;
      }
    }
    else if (k->type == STK_MEM_END) {
      if (k->u.mem.num == node->group) {
	node->end = k->u.mem.pstr - str;
	*kp = k;
	return 0;
      }
    }
    k++;
  }

  return 1; /* 1: root node ending. */
}
#endif /* USE_CAPTURE_HISTORY */

#ifdef USE_BACKREF_WITH_LEVEL
static int
mem_is_in_memp(int mem, int num, UChar* memp)
{
  int i;
  MemNumType m;

  for (i = 0; i < num; i++) {
    GET_MEMNUM_INC(m, memp);
    if (mem == (int )m) return 1;
  }
  return 0;
}

static int backref_match_at_nested_level(regex_t* reg,
	 OnigStackType* top, OnigStackType* stk_base,
	 int ignore_case, int case_fold_flag,
	 int nest, int mem_num, UChar* memp, UChar** s, const UChar* send)
{
  UChar *ss, *p, *pstart, *pend = NULL_UCHARP;
  int level;
  OnigStackType* k;

  level = 0;
  k = top;
  k--;
  while (k >= stk_base) {
    if (k->type == STK_CALL_FRAME) {
      level--;
    }
    else if (k->type == STK_RETURN) {
      level++;
    }
    else if (level == nest) {
      if (k->type == STK_MEM_START) {
	if (mem_is_in_memp(k->u.mem.num, mem_num, memp)) {
	  pstart = k->u.mem.pstr;
	  if (pend != NULL_UCHARP) {
	    if (pend - pstart > send - *s) return 0; /* or goto next_mem; */
	    p  = pstart;
	    ss = *s;

	    if (ignore_case != 0) {
	      if (string_cmp_ic(reg->enc, case_fold_flag,
				pstart, &ss, pend - pstart, send) == 0)
		return 0; /* or goto next_mem; */
	    }
	    else {
	      while (p < pend) {
		if (*p++ != *ss++) return 0; /* or goto next_mem; */
	      }
	    }

	    *s = ss;
	    return 1;
	  }
	}
      }
      else if (k->type == STK_MEM_END) {
	if (mem_is_in_memp(k->u.mem.num, mem_num, memp)) {
	  pend = k->u.mem.pstr;
	}
      }
    }
    k--;
  }

  return 0;
}
#endif /* USE_BACKREF_WITH_LEVEL */


#ifdef ONIG_DEBUG_STATISTICS

# ifdef _WIN32
#  include <windows.h>
static LARGE_INTEGER ts, te, freq;
#  define GETTIME(t)	  QueryPerformanceCounter(&(t))
#  define TIMEDIFF(te,ts) (unsigned long )(((te).QuadPart - (ts).QuadPart) \
			    * 1000000 / freq.QuadPart)
# else /* _WIN32 */

#  define USE_TIMEOFDAY

#  ifdef USE_TIMEOFDAY
#   ifdef HAVE_SYS_TIME_H
#    include <sys/time.h>
#   endif
#   ifdef HAVE_UNISTD_H
#    include <unistd.h>
#   endif
static struct timeval ts, te;
#   define GETTIME(t)      gettimeofday(&(t), (struct timezone* )0)
#   define TIMEDIFF(te,ts) (((te).tv_usec - (ts).tv_usec) + \
                            (((te).tv_sec - (ts).tv_sec)*1000000))
#  else /* USE_TIMEOFDAY */
#   ifdef HAVE_SYS_TIMES_H
#    include <sys/times.h>
#   endif
static struct tms ts, te;
#   define GETTIME(t)       times(&(t))
#   define TIMEDIFF(te,ts)  ((te).tms_utime - (ts).tms_utime)
#  endif /* USE_TIMEOFDAY */

# endif /* _WIN32 */

static int OpCounter[256];
static int OpPrevCounter[256];
static unsigned long OpTime[256];
static int OpCurr = OP_FINISH;
static int OpPrevTarget = OP_FAIL;
static int MaxStackDepth = 0;

# define MOP_IN(opcode) do {\
  if (opcode == OpPrevTarget) OpPrevCounter[OpCurr]++;\
  OpCurr = opcode;\
  OpCounter[opcode]++;\
  GETTIME(ts);\
} while(0)

# define MOP_OUT do {\
  GETTIME(te);\
  OpTime[OpCurr] += TIMEDIFF(te, ts);\
} while(0)

extern void
onig_statistics_init(void)
{
  int i;
  for (i = 0; i < 256; i++) {
    OpCounter[i] = OpPrevCounter[i] = 0; OpTime[i] = 0;
  }
  MaxStackDepth = 0;
# ifdef _WIN32
  QueryPerformanceFrequency(&freq);
# endif
}

extern void
onig_print_statistics(FILE* f)
{
  int i;
  fprintf(f, "   count      prev        time\n");
  for (i = 0; OnigOpInfo[i].opcode >= 0; i++) {
    fprintf(f, "%8d: %8d: %10lu: %s\n",
	    OpCounter[i], OpPrevCounter[i], OpTime[i], OnigOpInfo[i].name);
  }
  fprintf(f, "\nmax stack depth: %d\n", MaxStackDepth);
}

# define STACK_INC do {\
  stk++;\
  if (stk - stk_base > MaxStackDepth) \
    MaxStackDepth = stk - stk_base;\
} while(0)

#else /* ONIG_DEBUG_STATISTICS */
# define STACK_INC     stk++

# define MOP_IN(opcode)
# define MOP_OUT
#endif /* ONIG_DEBUG_STATISTICS */


#ifdef ONIG_DEBUG_MATCH
static const char *
stack_type_str(int stack_type)
{
  switch (stack_type) {
    case STK_ALT:		return "Alt   ";
    case STK_LOOK_BEHIND_NOT:	return "LBNot ";
    case STK_POS_NOT:		return "PosNot";
    case STK_MEM_START:		return "MemS  ";
    case STK_MEM_END:		return "MemE  ";
    case STK_REPEAT_INC:	return "RepInc";
    case STK_STATE_CHECK_MARK:	return "StChMk";
    case STK_NULL_CHECK_START:	return "NulChS";
    case STK_NULL_CHECK_END:	return "NulChE";
    case STK_MEM_END_MARK:	return "MemEMk";
    case STK_POS:		return "Pos   ";
    case STK_STOP_BT:		return "StopBt";
    case STK_REPEAT:		return "Rep   ";
    case STK_CALL_FRAME:	return "Call  ";
    case STK_RETURN:		return "Ret   ";
    case STK_VOID:		return "Void  ";
    case STK_ABSENT_POS:	return "AbsPos";
    case STK_ABSENT:		return "Absent";
    case STK_MATCH_CACHE_POINT:	return "MCache";
    default:			return "      ";
  }
}
#endif
#ifdef USE_MATCH_CACHE

static long
bsearch_cache_opcodes(const OnigCacheOpcode *cache_opcodes, long num_cache_opcodes, const UChar* p)
{
  long l = 0, r = num_cache_opcodes - 1, m = 0;

  while (l <= r) {
    m = (l + r) / 2;
    if (cache_opcodes[m].addr == p) break;
    if (cache_opcodes[m].addr < p) l = m + 1;
    else r = m - 1;
  }
  return m;
}

static long
find_cache_point(regex_t* reg, const OnigCacheOpcode* cache_opcodes, long num_cache_opcodes, const UChar* p, const OnigStackType *stk, const OnigStackIndex *repeat_stk, const OnigCacheOpcode **cache_opcode_ptr)
{
  long m;
  const OnigCacheOpcode* cache_opcode;
  const OnigRepeatRange* range;
  const OnigStackType *stkp;
  int count = 0;
  int is_inc = *p == OP_REPEAT_INC || *p == OP_REPEAT_INC_NG;
  long cache_point;
  long num_cache_points_at_outer_repeat;
  long num_cache_points_in_outer_repeat;

  m = bsearch_cache_opcodes(cache_opcodes, num_cache_opcodes, p);

  if (!(0 <= m && m < num_cache_opcodes && cache_opcodes[m].addr == p)) {
    return -1;
  }

  cache_opcode = &cache_opcodes[m];
  *cache_opcode_ptr = &cache_opcodes[m];
  cache_point = cache_opcode->cache_point;
  if (cache_opcode->outer_repeat_mem == -1) {
    return cache_point;
  }

  num_cache_points_at_outer_repeat = cache_opcode->num_cache_points_at_outer_repeat;
  num_cache_points_in_outer_repeat = cache_opcode->num_cache_points_in_outer_repeat;

  range = &reg->repeat_range[cache_opcode->outer_repeat_mem];

  stkp = &stk[repeat_stk[cache_opcode->outer_repeat_mem]];
  count = is_inc ? stkp->u.repeat.count - 1 : stkp->u.repeat.count;

  if (count < range->lower) {
    return num_cache_points_at_outer_repeat +
      num_cache_points_in_outer_repeat * count +
      cache_point;
  }

  if (range->upper == 0x7fffffff) {
    return num_cache_points_at_outer_repeat +
      num_cache_points_in_outer_repeat * (range->lower - (is_inc ? 1 : 0)) + (is_inc ? 0 : 1) +
      cache_point;
  }

  return num_cache_points_at_outer_repeat +
    num_cache_points_in_outer_repeat * (range->lower - 1) +
    (num_cache_points_in_outer_repeat + 1) * (count - range->lower + 1) +
    cache_point;
}

static int check_extended_match_cache_point(uint8_t *match_cache_buf, long match_cache_point_index, uint8_t match_cache_point_mask) {
  if (match_cache_point_mask & 0x80) {
    return (match_cache_buf[match_cache_point_index + 1] & 0x01) > 0;
  } else {
    return (match_cache_buf[match_cache_point_index] & (match_cache_point_mask << 1)) > 0;
  }
}

static void memoize_extended_match_cache_point(uint8_t *match_cache_buf, long match_cache_point_index, uint8_t match_cache_point_mask) {
  match_cache_buf[match_cache_point_index] |= match_cache_point_mask;
  if (match_cache_point_mask & 0x80) {
    match_cache_buf[match_cache_point_index + 1] |= 0x01;
  } else {
    match_cache_buf[match_cache_point_index] |= match_cache_point_mask << 1;
  }
}

#endif /* USE_MATCH_CACHE */

/* match data(str - end) from position (sstart). */
/* if sstart == str then set sprev to NULL. */
static OnigPosition
match_at(regex_t* reg, const UChar* str, const UChar* end,
#ifdef USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE
	 const UChar* right_range,
#endif
	 const UChar* sstart, UChar* sprev, OnigMatchArg* msa)
{
  static const UChar FinishCode[] = { OP_FINISH };

  int i, num_mem, pop_level;
  ptrdiff_t n, best_len;
  LengthType tlen, tlen2;
  MemNumType mem;
  RelAddrType addr;
  OnigOptionType option = reg->options;
  OnigEncoding encode = reg->enc;
  OnigCaseFoldType case_fold_flag = reg->case_fold_flag;
  UChar *s, *q, *sbegin;
  UChar *p = reg->p;
  UChar *pbegin = p;
  UChar *pkeep;
  char *alloca_base;
  char *xmalloc_base = NULL;
  OnigStackType *stk_alloc, *stk_base = NULL, *stk, *stk_end;
  OnigStackType *stkp; /* used as any purpose. */
  OnigStackIndex si;
  OnigStackIndex *repeat_stk;
  OnigStackIndex *mem_start_stk, *mem_end_stk;
#ifdef USE_COMBINATION_EXPLOSION_CHECK
  int scv;
  unsigned char* state_check_buff = msa->state_check_buff;
  int num_comb_exp_check = reg->num_comb_exp_check;
#endif

#if USE_TOKEN_THREADED_VM
# define OP_OFFSET  1
# define VM_LOOP JUMP;
# define VM_LOOP_END
# define CASE(x) L_##x: sbegin = s; OPCODE_EXEC_HOOK;
# define DEFAULT L_DEFAULT:
# define NEXT sprev = sbegin; JUMP
# define JUMP pbegin = p; RB_GNUC_EXTENSION_BLOCK(goto *oplabels[*p++])

  RB_GNUC_EXTENSION static const void *oplabels[] = {
    &&L_OP_FINISH,               /* matching process terminator (no more alternative) */
    &&L_OP_END,                  /* pattern code terminator (success end) */

    &&L_OP_EXACT1,               /* single byte, N = 1 */
    &&L_OP_EXACT2,               /* single byte, N = 2 */
    &&L_OP_EXACT3,               /* single byte, N = 3 */
    &&L_OP_EXACT4,               /* single byte, N = 4 */
    &&L_OP_EXACT5,               /* single byte, N = 5 */
    &&L_OP_EXACTN,               /* single byte */
    &&L_OP_EXACTMB2N1,           /* mb-length = 2 N = 1 */
    &&L_OP_EXACTMB2N2,           /* mb-length = 2 N = 2 */
    &&L_OP_EXACTMB2N3,           /* mb-length = 2 N = 3 */
    &&L_OP_EXACTMB2N,            /* mb-length = 2 */
    &&L_OP_EXACTMB3N,            /* mb-length = 3 */
    &&L_OP_EXACTMBN,             /* other length */

    &&L_OP_EXACT1_IC,            /* single byte, N = 1, ignore case */
    &&L_OP_EXACTN_IC,            /* single byte,        ignore case */

    &&L_OP_CCLASS,
    &&L_OP_CCLASS_MB,
    &&L_OP_CCLASS_MIX,
    &&L_OP_CCLASS_NOT,
    &&L_OP_CCLASS_MB_NOT,
    &&L_OP_CCLASS_MIX_NOT,

    &&L_OP_ANYCHAR,                 /* "."  */
    &&L_OP_ANYCHAR_ML,              /* "."  multi-line */
    &&L_OP_ANYCHAR_STAR,            /* ".*" */
    &&L_OP_ANYCHAR_ML_STAR,         /* ".*" multi-line */
    &&L_OP_ANYCHAR_STAR_PEEK_NEXT,
    &&L_OP_ANYCHAR_ML_STAR_PEEK_NEXT,

    &&L_OP_WORD,
    &&L_OP_NOT_WORD,
    &&L_OP_WORD_BOUND,
    &&L_OP_NOT_WORD_BOUND,
# ifdef USE_WORD_BEGIN_END
    &&L_OP_WORD_BEGIN,
    &&L_OP_WORD_END,
# else
    &&L_DEFAULT,
    &&L_DEFAULT,
# endif
    &&L_OP_ASCII_WORD,
    &&L_OP_NOT_ASCII_WORD,
    &&L_OP_ASCII_WORD_BOUND,
    &&L_OP_NOT_ASCII_WORD_BOUND,
# ifdef USE_WORD_BEGIN_END
    &&L_OP_ASCII_WORD_BEGIN,
    &&L_OP_ASCII_WORD_END,
# else
    &&L_DEFAULT,
    &&L_DEFAULT,
# endif

    &&L_OP_BEGIN_BUF,
    &&L_OP_END_BUF,
    &&L_OP_BEGIN_LINE,
    &&L_OP_END_LINE,
    &&L_OP_SEMI_END_BUF,
    &&L_OP_BEGIN_POSITION,

    &&L_OP_BACKREF1,
    &&L_OP_BACKREF2,
    &&L_OP_BACKREFN,
    &&L_OP_BACKREFN_IC,
    &&L_OP_BACKREF_MULTI,
    &&L_OP_BACKREF_MULTI_IC,
# ifdef USE_BACKREF_WITH_LEVEL
    &&L_OP_BACKREF_WITH_LEVEL,   /* \k<xxx+n>, \k<xxx-n> */
# else
    &&L_DEFAULT,
# endif
    &&L_OP_MEMORY_START,
    &&L_OP_MEMORY_START_PUSH,    /* push back-tracker to stack */
    &&L_OP_MEMORY_END_PUSH,      /* push back-tracker to stack */
# ifdef USE_SUBEXP_CALL
    &&L_OP_MEMORY_END_PUSH_REC,  /* push back-tracker to stack */
# else
    &&L_DEFAULT,
# endif
    &&L_OP_MEMORY_END,
# ifdef USE_SUBEXP_CALL
    &&L_OP_MEMORY_END_REC,       /* push marker to stack */
# else
    &&L_DEFAULT,
# endif

    &&L_OP_KEEP,

    &&L_OP_FAIL,                 /* pop stack and move */
    &&L_OP_JUMP,
    &&L_OP_PUSH,
    &&L_OP_POP,
# ifdef USE_OP_PUSH_OR_JUMP_EXACT
    &&L_OP_PUSH_OR_JUMP_EXACT1,  /* if match exact then push, else jump. */
# else
    &&L_DEFAULT,
# endif
    &&L_OP_PUSH_IF_PEEK_NEXT,    /* if match exact then push, else none. */
    &&L_OP_REPEAT,               /* {n,m} */
    &&L_OP_REPEAT_NG,            /* {n,m}? (non greedy) */
    &&L_OP_REPEAT_INC,
    &&L_OP_REPEAT_INC_NG,        /* non greedy */
    &&L_OP_REPEAT_INC_SG,        /* search and get in stack */
    &&L_OP_REPEAT_INC_NG_SG,     /* search and get in stack (non greedy) */
    &&L_OP_NULL_CHECK_START,     /* null loop checker start */
    &&L_OP_NULL_CHECK_END,       /* null loop checker end   */
# ifdef USE_MONOMANIAC_CHECK_CAPTURES_IN_ENDLESS_REPEAT
    &&L_OP_NULL_CHECK_END_MEMST, /* null loop checker end (with capture status) */
# else
    &&L_DEFAULT,
# endif
# ifdef USE_SUBEXP_CALL
    &&L_OP_NULL_CHECK_END_MEMST_PUSH, /* with capture status and push check-end */
# else
    &&L_DEFAULT,
# endif

    &&L_OP_PUSH_POS,             /* (?=...)  start */
    &&L_OP_POP_POS,              /* (?=...)  end   */
    &&L_OP_PUSH_POS_NOT,         /* (?!...)  start */
    &&L_OP_FAIL_POS,             /* (?!...)  end   */
    &&L_OP_PUSH_STOP_BT,         /* (?>...)  start */
    &&L_OP_POP_STOP_BT,          /* (?>...)  end   */
    &&L_OP_LOOK_BEHIND,          /* (?<=...) start (no needs end opcode) */
    &&L_OP_PUSH_LOOK_BEHIND_NOT, /* (?<!...) start */
    &&L_OP_FAIL_LOOK_BEHIND_NOT, /* (?<!...) end   */
    &&L_OP_PUSH_ABSENT_POS,      /* (?~...)  start */
    &&L_OP_ABSENT,               /* (?~...)  start of inner loop */
    &&L_OP_ABSENT_END,           /* (?~...)  end   */

# ifdef USE_SUBEXP_CALL
    &&L_OP_CALL,                 /* \g<name> */
    &&L_OP_RETURN,
# else
    &&L_DEFAULT,
    &&L_DEFAULT,
# endif
    &&L_OP_CONDITION,

# ifdef USE_COMBINATION_EXPLOSION_CHECK
    &&L_OP_STATE_CHECK_PUSH,         /* combination explosion check and push */
    &&L_OP_STATE_CHECK_PUSH_OR_JUMP, /* check ok -> push, else jump  */
    &&L_OP_STATE_CHECK,              /* check only */
# else
    &&L_DEFAULT,
    &&L_DEFAULT,
    &&L_DEFAULT,
# endif
# ifdef USE_COMBINATION_EXPLOSION_CHECK
    &&L_OP_STATE_CHECK_ANYCHAR_STAR,
    &&L_OP_STATE_CHECK_ANYCHAR_ML_STAR,
# else
    &&L_DEFAULT,
    &&L_DEFAULT,
# endif
    /* no need: IS_DYNAMIC_OPTION() == 0 */
# if 0   /* no need: IS_DYNAMIC_OPTION() == 0 */
    &&L_OP_SET_OPTION_PUSH,    /* set option and push recover option */
    &&L_OP_SET_OPTION          /* set option */
# else
    &&L_DEFAULT,
    &&L_DEFAULT
# endif
  };
#else /* USE_TOKEN_THREADED_VM */

# define OP_OFFSET  0
# define VM_LOOP                                \
  while (1) {                                   \
  OPCODE_EXEC_HOOK;                             \
  pbegin = p;                                   \
  sbegin = s;                                   \
  switch (*p++) {
# define VM_LOOP_END } sprev = sbegin; }
# define CASE(x) case x:
# define DEFAULT default:
# define NEXT break
# define JUMP continue; break
#endif /* USE_TOKEN_THREADED_VM */


#ifdef USE_SUBEXP_CALL
/* Stack #0 is used to store the pattern itself and used for (?R), \g<0>,
   etc. Additional space is required. */
# define ADD_NUMMEM 1
#else
/* Stack #0 not is used. */
# define ADD_NUMMEM 0
#endif

  n = reg->num_repeat + (reg->num_mem + ADD_NUMMEM) * 2;

  STACK_INIT(alloca_base, xmalloc_base, n, INIT_MATCH_STACK_SIZE);
  pop_level = reg->stack_pop_level;
  num_mem = reg->num_mem;
  repeat_stk = (OnigStackIndex* )alloca_base;

  mem_start_stk = (OnigStackIndex* )(repeat_stk + reg->num_repeat);
  mem_end_stk   = mem_start_stk + (num_mem + ADD_NUMMEM);
  {
    OnigStackIndex *pp = mem_start_stk;
    for (; pp < repeat_stk + n; pp += 2) {
      pp[0] = INVALID_STACK_INDEX;
      pp[1] = INVALID_STACK_INDEX;
    }
  }
#ifndef USE_SUBEXP_CALL
  mem_start_stk--; /* for index start from 1,
		      mem_start_stk[1]..mem_start_stk[num_mem] */
  mem_end_stk--;   /* for index start from 1,
		      mem_end_stk[1]..mem_end_stk[num_mem] */
#endif

#ifdef ONIG_DEBUG_MATCH
  fprintf(stderr, "match_at: str: %"PRIuPTR" (%p), end: %"PRIuPTR" (%p), start: %"PRIuPTR" (%p), sprev: %"PRIuPTR" (%p)\n",
	  (uintptr_t )str, str, (uintptr_t )end, end, (uintptr_t )sstart, sstart, (uintptr_t )sprev, sprev);
  fprintf(stderr, "size: %d, start offset: %d\n",
	  (int )(end - str), (int )(sstart - str));
  fprintf(stderr, "\n ofs> str                   stk:type   addr:opcode\n");
#endif

  STACK_PUSH_ENSURED(STK_ALT, (UChar* )FinishCode);  /* bottom stack */
  best_len = ONIG_MISMATCH;
  s = (UChar* )sstart;
  pkeep = (UChar* )sstart;


#ifdef ONIG_DEBUG_MATCH
# define OPCODE_EXEC_HOOK                                               \
    if (s) {                                                            \
      UChar *op, *q, *bp, buf[50];                                      \
      int len;                                                          \
      op = p - OP_OFFSET;                                               \
      fprintf(stderr, "%4"PRIdPTR"> \"", (*op == OP_FINISH) ? (ptrdiff_t )-1 : s - str); \
      bp = buf;                                                         \
      q = s;                                                            \
      if (*op != OP_FINISH) {    /* s may not be a valid pointer if OP_FINISH. */ \
	for (i = 0; i < 7 && q < end; i++) {                            \
	  len = enclen(encode, q, end);                                 \
	  while (len-- > 0) *bp++ = *q++;                               \
	}                                                               \
        if (q < end) { xmemcpy(bp, "...", 3); bp += 3; }                \
      }                                                                 \
      xmemcpy(bp, "\"", 1); bp += 1;                                    \
      *bp = 0;                                                          \
      fputs((char* )buf, stderr);                                       \
      for (i = 0; i < 20 - (bp - buf); i++) fputc(' ', stderr);         \
      fprintf(stderr, "%4"PRIdPTR":%s %4"PRIdPTR":",                    \
	  stk - stk_base - 1,                                           \
	  (stk > stk_base) ? stack_type_str(stk[-1].type) : "      ",   \
	  (op == FinishCode) ? (ptrdiff_t )-1 : op - reg->p);           \
      onig_print_compiled_byte_code(stderr, op, reg->p+reg->used, NULL, encode); \
      fprintf(stderr, "\n");                                            \
    }
#else
# define OPCODE_EXEC_HOOK ((void) 0)
#endif

#ifdef USE_MATCH_CACHE
#ifdef ONIG_DEBUG_MATCH_CACHE
#define MATCH_CACHE_DEBUG fprintf(stderr, "MATCH CACHE: cache %ld (p=%p index=%ld mask=%d)\n", match_cache_point, pbegin, match_cache_point_index, match_cache_point_mask)
#define MATCH_CACHE_DEBUG_HIT fprintf(stderr, "MATCH CACHE: cache hit\n")
#else
#define MATCH_CACHE_DEBUG ((void) 0)
#define MATCH_CACHE_DEBUG_HIT ((void) 0)
#endif

#define MATCH_CACHE_HIT ((void) 0)

#  define CHECK_MATCH_CACHE do {\
  if (msa->match_cache_status == MATCH_CACHE_STATUS_ENABLED) {\
    const OnigCacheOpcode *cache_opcode;\
    long cache_point = find_cache_point(reg, msa->cache_opcodes, msa->num_cache_opcodes, pbegin, stk_base, repeat_stk, &cache_opcode);\
    if (cache_point >= 0) {\
      long match_cache_point = msa->num_cache_points * (long)(s - str) + cache_point;\
      long match_cache_point_index = match_cache_point >> 3;\
      uint8_t match_cache_point_mask = 1 << (match_cache_point & 7);\
      MATCH_CACHE_DEBUG;\
      if (msa->match_cache_buf[match_cache_point_index] & match_cache_point_mask) {\
	MATCH_CACHE_DEBUG_HIT; MATCH_CACHE_HIT;\
	if (cache_opcode->lookaround_nesting == 0) goto fail;\
	else if (cache_opcode->lookaround_nesting < 0) {\
	  if (check_extended_match_cache_point(msa->match_cache_buf, match_cache_point_index, match_cache_point_mask)) {\
            STACK_STOP_BT_FAIL;\
            goto fail;\
          } else goto fail;\
        } else {\
	  if (check_extended_match_cache_point(msa->match_cache_buf, match_cache_point_index, match_cache_point_mask)) {\
	    p = cache_opcode->match_addr;\
            MOP_OUT;\
            JUMP;\
          } else goto fail;\
        }\
      }\
      STACK_PUSH_MATCH_CACHE_POINT(match_cache_point_index, match_cache_point_mask);\
    }\
  }\
} while (0)
#else
#  define CHECK_MATCH_CACHE ((void) 0)
#endif

  VM_LOOP {
    CASE(OP_END)  MOP_IN(OP_END);
      n = s - sstart;
      if (n > best_len) {
	OnigRegion* region;
#ifdef USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE
	if (IS_FIND_LONGEST(option)) {
	  if (n > msa->best_len) {
	    msa->best_len = n;
	    msa->best_s   = (UChar* )sstart;
	  }
	  else
	    goto end_best_len;
	}
#endif
	best_len = n;
	region = msa->region;
	if (region) {
	  region->beg[0] = ((pkeep > s) ? s : pkeep) - str;
	  region->end[0] = s - str;
	  for (i = 1; i <= num_mem; i++) {
	    if (mem_end_stk[i] != INVALID_STACK_INDEX) {
	      if (BIT_STATUS_AT(reg->bt_mem_start, i))
		region->beg[i] = STACK_AT(mem_start_stk[i])->u.mem.pstr - str;
	      else
		region->beg[i] = (UChar* )((void* )mem_start_stk[i]) - str;

	      region->end[i] = (BIT_STATUS_AT(reg->bt_mem_end, i)
				? STACK_AT(mem_end_stk[i])->u.mem.pstr
				: (UChar* )((void* )mem_end_stk[i])) - str;
	    }
	    else {
	      region->beg[i] = region->end[i] = ONIG_REGION_NOTPOS;
	    }
	  }

#ifdef USE_CAPTURE_HISTORY
	  if (reg->capture_history != 0) {
	    int r;
	    OnigCaptureTreeNode* node;

	    if (IS_NULL(region->history_root)) {
	      region->history_root = node = history_node_new();
	      CHECK_NULL_RETURN_MEMERR(node);
	    }
	    else {
	      node = region->history_root;
	      history_tree_clear(node);
	    }

	    node->group = 0;
	    node->beg   = ((pkeep > s) ? s : pkeep) - str;
	    node->end   = s - str;

	    stkp = stk_base;
	    r = make_capture_history_tree(region->history_root, &stkp,
		stk, (UChar* )str, reg);
	    if (r < 0) {
	      best_len = r; /* error code */
	      goto finish;
	    }
	  }
#endif /* USE_CAPTURE_HISTORY */
	} /* if (region) */
      } /* n > best_len */

#ifdef USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE
    end_best_len:
#endif
      MOP_OUT;

      if (IS_FIND_CONDITION(option)) {
	if (IS_FIND_NOT_EMPTY(option) && s == sstart) {
	  best_len = ONIG_MISMATCH;
	  goto fail; /* for retry */
	}
	if (IS_FIND_LONGEST(option) && DATA_ENSURE_CHECK1) {
	  goto fail; /* for retry */
	}
      }

      /* default behavior: return first-matching result. */
      goto finish;
      NEXT;

    CASE(OP_EXACT1)  MOP_IN(OP_EXACT1);
      DATA_ENSURE(1);
      if (*p != *s) goto fail;
      p++; s++;
      MOP_OUT;
      NEXT;

    CASE(OP_EXACT1_IC)  MOP_IN(OP_EXACT1_IC);
      {
	int len;
	UChar *q, lowbuf[ONIGENC_MBC_CASE_FOLD_MAXLEN];

	DATA_ENSURE(1);
	len = ONIGENC_MBC_CASE_FOLD(encode,
		    /* DISABLE_CASE_FOLD_MULTI_CHAR(case_fold_flag), */
		    case_fold_flag,
		    &s, end, lowbuf);
	DATA_ENSURE(0);
	q = lowbuf;
	while (len-- > 0) {
	  if (*p != *q) {
	    goto fail;
	  }
	  p++; q++;
	}
      }
      MOP_OUT;
      NEXT;

    CASE(OP_EXACT2)  MOP_IN(OP_EXACT2);
      DATA_ENSURE(2);
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      sprev = s;
      p++; s++;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACT3)  MOP_IN(OP_EXACT3);
      DATA_ENSURE(3);
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      sprev = s;
      p++; s++;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACT4)  MOP_IN(OP_EXACT4);
      DATA_ENSURE(4);
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      sprev = s;
      p++; s++;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACT5)  MOP_IN(OP_EXACT5);
      DATA_ENSURE(5);
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      sprev = s;
      p++; s++;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACTN)  MOP_IN(OP_EXACTN);
      GET_LENGTH_INC(tlen, p);
      DATA_ENSURE(tlen);
      while (tlen-- > 0) {
	if (*p++ != *s++) goto fail;
      }
      sprev = s - 1;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACTN_IC)  MOP_IN(OP_EXACTN_IC);
      {
	int len;
	UChar *q, *endp, lowbuf[ONIGENC_MBC_CASE_FOLD_MAXLEN];

	GET_LENGTH_INC(tlen, p);
	endp = p + tlen;

	while (p < endp) {
	  sprev = s;
	  DATA_ENSURE(1);
	  len = ONIGENC_MBC_CASE_FOLD(encode,
		      /* DISABLE_CASE_FOLD_MULTI_CHAR(case_fold_flag), */
		      case_fold_flag,
		      &s, end, lowbuf);
	  DATA_ENSURE(0);
	  q = lowbuf;
	  while (len-- > 0) {
	    if (*p != *q) goto fail;
	    p++; q++;
	  }
	}
      }

      MOP_OUT;
      JUMP;

    CASE(OP_EXACTMB2N1)  MOP_IN(OP_EXACTMB2N1);
      DATA_ENSURE(2);
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      MOP_OUT;
      NEXT;

    CASE(OP_EXACTMB2N2)  MOP_IN(OP_EXACTMB2N2);
      DATA_ENSURE(4);
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      sprev = s;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACTMB2N3)  MOP_IN(OP_EXACTMB2N3);
      DATA_ENSURE(6);
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      sprev = s;
      if (*p != *s) goto fail;
      p++; s++;
      if (*p != *s) goto fail;
      p++; s++;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACTMB2N)  MOP_IN(OP_EXACTMB2N);
      GET_LENGTH_INC(tlen, p);
      DATA_ENSURE(tlen * 2);
      while (tlen-- > 0) {
	if (*p != *s) goto fail;
	p++; s++;
	if (*p != *s) goto fail;
	p++; s++;
      }
      sprev = s - 2;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACTMB3N)  MOP_IN(OP_EXACTMB3N);
      GET_LENGTH_INC(tlen, p);
      DATA_ENSURE(tlen * 3);
      while (tlen-- > 0) {
	if (*p != *s) goto fail;
	p++; s++;
	if (*p != *s) goto fail;
	p++; s++;
	if (*p != *s) goto fail;
	p++; s++;
      }
      sprev = s - 3;
      MOP_OUT;
      JUMP;

    CASE(OP_EXACTMBN)  MOP_IN(OP_EXACTMBN);
      GET_LENGTH_INC(tlen,  p);  /* mb-len */
      GET_LENGTH_INC(tlen2, p);  /* string len */
      tlen2 *= tlen;
      DATA_ENSURE(tlen2);
      while (tlen2-- > 0) {
	if (*p != *s) goto fail;
	p++; s++;
      }
      sprev = s - tlen;
      MOP_OUT;
      JUMP;

    CASE(OP_CCLASS)  MOP_IN(OP_CCLASS);
      DATA_ENSURE(1);
      if (BITSET_AT(((BitSetRef )p), *s) == 0) goto fail;
      p += SIZE_BITSET;
      s += enclen(encode, s, end);   /* OP_CCLASS can match mb-code. \D, \S */
      MOP_OUT;
      NEXT;

    CASE(OP_CCLASS_MB)  MOP_IN(OP_CCLASS_MB);
      if (! ONIGENC_IS_MBC_HEAD(encode, s, end)) goto fail;

    cclass_mb:
      GET_LENGTH_INC(tlen, p);
      {
	OnigCodePoint code;
	UChar *ss;
	int mb_len;

	DATA_ENSURE(1);
	mb_len = enclen_approx(encode, s, end);
	DATA_ENSURE(mb_len);
	ss = s;
	s += mb_len;
	code = ONIGENC_MBC_TO_CODE(encode, ss, s);

#ifdef PLATFORM_UNALIGNED_WORD_ACCESS
	if (! onig_is_in_code_range(p, code)) goto fail;
#else
	q = p;
	ALIGNMENT_RIGHT(q);
	if (! onig_is_in_code_range(q, code)) goto fail;
#endif
      }
      p += tlen;
      MOP_OUT;
      NEXT;

    CASE(OP_CCLASS_MIX)  MOP_IN(OP_CCLASS_MIX);
      DATA_ENSURE(1);
      if (ONIGENC_IS_MBC_HEAD(encode, s, end)) {
	p += SIZE_BITSET;
	goto cclass_mb;
      }
      else {
	if (BITSET_AT(((BitSetRef )p), *s) == 0)
	  goto fail;

	p += SIZE_BITSET;
	GET_LENGTH_INC(tlen, p);
	p += tlen;
	s++;
      }
      MOP_OUT;
      NEXT;

    CASE(OP_CCLASS_NOT)  MOP_IN(OP_CCLASS_NOT);
      DATA_ENSURE(1);
      if (BITSET_AT(((BitSetRef )p), *s) != 0) goto fail;
      p += SIZE_BITSET;
      s += enclen(encode, s, end);
      MOP_OUT;
      NEXT;

    CASE(OP_CCLASS_MB_NOT)  MOP_IN(OP_CCLASS_MB_NOT);
      DATA_ENSURE(1);
      if (! ONIGENC_IS_MBC_HEAD(encode, s, end)) {
	s++;
	GET_LENGTH_INC(tlen, p);
	p += tlen;
	goto cc_mb_not_success;
      }

    cclass_mb_not:
      GET_LENGTH_INC(tlen, p);
      {
	OnigCodePoint code;
	UChar *ss;
	int mb_len = enclen(encode, s, end);

	if (! DATA_ENSURE_CHECK(mb_len)) {
	  DATA_ENSURE(1);
	  s = (UChar* )end;
	  p += tlen;
	  goto cc_mb_not_success;
	}

	ss = s;
	s += mb_len;
	code = ONIGENC_MBC_TO_CODE(encode, ss, s);

#ifdef PLATFORM_UNALIGNED_WORD_ACCESS
	if (onig_is_in_code_range(p, code)) goto fail;
#else
	q = p;
	ALIGNMENT_RIGHT(q);
	if (onig_is_in_code_range(q, code)) goto fail;
#endif
      }
      p += tlen;

    cc_mb_not_success:
      MOP_OUT;
      NEXT;

    CASE(OP_CCLASS_MIX_NOT)  MOP_IN(OP_CCLASS_MIX_NOT);
      DATA_ENSURE(1);
      if (ONIGENC_IS_MBC_HEAD(encode, s, end)) {
	p += SIZE_BITSET;
	goto cclass_mb_not;
      }
      else {
	if (BITSET_AT(((BitSetRef )p), *s) != 0)
	  goto fail;

	p += SIZE_BITSET;
	GET_LENGTH_INC(tlen, p);
	p += tlen;
	s++;
      }
      MOP_OUT;
      NEXT;

    CASE(OP_ANYCHAR)  MOP_IN(OP_ANYCHAR);
      DATA_ENSURE(1);
      n = enclen_approx(encode, s, end);
      DATA_ENSURE(n);
      if (ONIGENC_IS_MBC_NEWLINE_EX(encode, s, str, end, option, 0)) goto fail;
      s += n;
      MOP_OUT;
      NEXT;

    CASE(OP_ANYCHAR_ML)  MOP_IN(OP_ANYCHAR_ML);
      DATA_ENSURE(1);
      n = enclen_approx(encode, s, end);
      DATA_ENSURE(n);
      s += n;
      MOP_OUT;
      NEXT;

    CASE(OP_ANYCHAR_STAR)  MOP_IN(OP_ANYCHAR_STAR);
      while (DATA_ENSURE_CHECK1) {
	CHECK_MATCH_CACHE;
	STACK_PUSH_ALT(p, s, sprev, pkeep);
	n = enclen_approx(encode, s, end);
	DATA_ENSURE(n);
	if (ONIGENC_IS_MBC_NEWLINE_EX(encode, s, str, end, option, 0))  goto fail;
	sprev = s;
	s += n;
      }
      MOP_OUT;
      JUMP;

    CASE(OP_ANYCHAR_ML_STAR)  MOP_IN(OP_ANYCHAR_ML_STAR);
      while (DATA_ENSURE_CHECK1) {
	CHECK_MATCH_CACHE;
	STACK_PUSH_ALT(p, s, sprev, pkeep);
	n = enclen_approx(encode, s, end);
	if (n > 1) {
	  DATA_ENSURE(n);
	  sprev = s;
	  s += n;
	}
	else {
	  sprev = s;
	  s++;
	}
      }
      MOP_OUT;
      JUMP;

    CASE(OP_ANYCHAR_STAR_PEEK_NEXT)  MOP_IN(OP_ANYCHAR_STAR_PEEK_NEXT);
      while (DATA_ENSURE_CHECK1) {
	CHECK_MATCH_CACHE;
	if (*p == *s) {
	  STACK_PUSH_ALT(p + 1, s, sprev, pkeep);
	} else {
#ifdef USE_MATCH_CACHE
	  /* We need to increment num_fails here, for invoking a cache optimization correctly. */
	  /* Actually, the matching will be failed if we use `OP_ANYCHAR_STAR` simply in this case.*/
	  msa->num_fails++;
#endif
	}
	n = enclen_approx(encode, s, end);
	DATA_ENSURE(n);
	if (ONIGENC_IS_MBC_NEWLINE_EX(encode, s, str, end, option, 0))  goto fail;
	sprev = s;
	s += n;
      }
      p++;
      MOP_OUT;
      NEXT;

    CASE(OP_ANYCHAR_ML_STAR_PEEK_NEXT)MOP_IN(OP_ANYCHAR_ML_STAR_PEEK_NEXT);
      while (DATA_ENSURE_CHECK1) {
	CHECK_MATCH_CACHE;
	if (*p == *s) {
	  STACK_PUSH_ALT(p + 1, s, sprev, pkeep);
	} else {
#ifdef USE_MATCH_CACHE
	  /* We need to increment num_fails here, for invoking a cache optimization correctly. */
	  /* Actually, the matching will be failed if we use `OP_ANYCHAR_STAR_ML` simply in this case.*/
	  msa->num_fails++;
#endif
	}
	n = enclen_approx(encode, s, end);
	if (n > 1) {
	  DATA_ENSURE(n);
	  sprev = s;
	  s += n;
	}
	else {
	  sprev = s;
	  s++;
	}
      }
      p++;
      MOP_OUT;
      NEXT;

#ifdef USE_COMBINATION_EXPLOSION_CHECK
    CASE(OP_STATE_CHECK_ANYCHAR_STAR)  MOP_IN(OP_STATE_CHECK_ANYCHAR_STAR);
      GET_STATE_CHECK_NUM_INC(mem, p);
      while (DATA_ENSURE_CHECK1) {
	STATE_CHECK_VAL(scv, mem);
	if (scv) goto fail;

	STACK_PUSH_ALT_WITH_STATE_CHECK(p, s, sprev, mem, pkeep);
	n = enclen_approx(encode, s, end);
	DATA_ENSURE(n);
	if (ONIGENC_IS_MBC_NEWLINE_EX(encode, s, str, end, option, 0))  goto fail;
	sprev = s;
	s += n;
      }
      MOP_OUT;
      NEXT;

    CASE(OP_STATE_CHECK_ANYCHAR_ML_STAR)
      MOP_IN(OP_STATE_CHECK_ANYCHAR_ML_STAR);

      GET_STATE_CHECK_NUM_INC(mem, p);
      while (DATA_ENSURE_CHECK1) {
	STATE_CHECK_VAL(scv, mem);
	if (scv) goto fail;

	STACK_PUSH_ALT_WITH_STATE_CHECK(p, s, sprev, mem, pkeep);
	n = enclen_approx(encode, s, end);
	if (n > 1) {
	  DATA_ENSURE(n);
	  sprev = s;
	  s += n;
	}
	else {
	  sprev = s;
	  s++;
	}
      }
      MOP_OUT;
      NEXT;
#endif /* USE_COMBINATION_EXPLOSION_CHECK */

    CASE(OP_WORD)  MOP_IN(OP_WORD);
      DATA_ENSURE(1);
      if (! ONIGENC_IS_MBC_WORD(encode, s, end))
	goto fail;

      s += enclen(encode, s, end);
      MOP_OUT;
      NEXT;

    CASE(OP_ASCII_WORD)  MOP_IN(OP_ASCII_WORD);
      DATA_ENSURE(1);
      if (! ONIGENC_IS_MBC_ASCII_WORD(encode, s, end))
	goto fail;

      s += enclen(encode, s, end);
      MOP_OUT;
      NEXT;

    CASE(OP_NOT_WORD)  MOP_IN(OP_NOT_WORD);
      DATA_ENSURE(1);
      if (ONIGENC_IS_MBC_WORD(encode, s, end))
	goto fail;

      s += enclen(encode, s, end);
      MOP_OUT;
      NEXT;

    CASE(OP_NOT_ASCII_WORD)  MOP_IN(OP_NOT_ASCII_WORD);
      DATA_ENSURE(1);
      if (ONIGENC_IS_MBC_ASCII_WORD(encode, s, end))
	goto fail;

      s += enclen(encode, s, end);
      MOP_OUT;
      NEXT;

    CASE(OP_WORD_BOUND)  MOP_IN(OP_WORD_BOUND);
      if (ON_STR_BEGIN(s)) {
	DATA_ENSURE(1);
	if (! ONIGENC_IS_MBC_WORD(encode, s, end))
	  goto fail;
      }
      else if (ON_STR_END(s)) {
	if (! ONIGENC_IS_MBC_WORD(encode, sprev, end))
	  goto fail;
      }
      else {
	if (ONIGENC_IS_MBC_WORD(encode, s, end)
	    == ONIGENC_IS_MBC_WORD(encode, sprev, end))
	  goto fail;
      }
      MOP_OUT;
      JUMP;

    CASE(OP_ASCII_WORD_BOUND)  MOP_IN(OP_ASCII_WORD_BOUND);
      if (ON_STR_BEGIN(s)) {
	DATA_ENSURE(1);
	if (! ONIGENC_IS_MBC_ASCII_WORD(encode, s, end))
	  goto fail;
      }
      else if (ON_STR_END(s)) {
	if (! ONIGENC_IS_MBC_ASCII_WORD(encode, sprev, end))
	  goto fail;
      }
      else {
	if (ONIGENC_IS_MBC_ASCII_WORD(encode, s, end)
	    == ONIGENC_IS_MBC_ASCII_WORD(encode, sprev, end))
	  goto fail;
      }
      MOP_OUT;
      JUMP;

    CASE(OP_NOT_WORD_BOUND)  MOP_IN(OP_NOT_WORD_BOUND);
      if (ON_STR_BEGIN(s)) {
	if (DATA_ENSURE_CHECK1 && ONIGENC_IS_MBC_WORD(encode, s, end))
	  goto fail;
      }
      else if (ON_STR_END(s)) {
	if (ONIGENC_IS_MBC_WORD(encode, sprev, end))
	  goto fail;
      }
      else {
	if (ONIGENC_IS_MBC_WORD(encode, s, end)
	    != ONIGENC_IS_MBC_WORD(encode, sprev, end))
	  goto fail;
      }
      MOP_OUT;
      JUMP;

    CASE(OP_NOT_ASCII_WORD_BOUND)  MOP_IN(OP_NOT_ASCII_WORD_BOUND);
      if (ON_STR_BEGIN(s)) {
	if (DATA_ENSURE_CHECK1 && ONIGENC_IS_MBC_ASCII_WORD(encode, s, end))
	  goto fail;
      }
      else if (ON_STR_END(s)) {
	if (ONIGENC_IS_MBC_ASCII_WORD(encode, sprev, end))
	  goto fail;
      }
      else {
	if (ONIGENC_IS_MBC_ASCII_WORD(encode, s, end)
	    != ONIGENC_IS_MBC_ASCII_WORD(encode, sprev, end))
	  goto fail;
      }
      MOP_OUT;
      JUMP;

#ifdef USE_WORD_BEGIN_END
    CASE(OP_WORD_BEGIN)  MOP_IN(OP_WORD_BEGIN);
      if (DATA_ENSURE_CHECK1 && ONIGENC_IS_MBC_WORD(encode, s, end)) {
	if (ON_STR_BEGIN(s) || !ONIGENC_IS_MBC_WORD(encode, sprev, end)) {
	  MOP_OUT;
	  JUMP;
	}
      }
      goto fail;
      NEXT;

    CASE(OP_ASCII_WORD_BEGIN)  MOP_IN(OP_ASCII_WORD_BEGIN);
      if (DATA_ENSURE_CHECK1 && ONIGENC_IS_MBC_ASCII_WORD(encode, s, end)) {
	if (ON_STR_BEGIN(s) || !ONIGENC_IS_MBC_ASCII_WORD(encode, sprev, end)) {
	  MOP_OUT;
	  JUMP;
	}
      }
      goto fail;
      NEXT;

    CASE(OP_WORD_END)  MOP_IN(OP_WORD_END);
      if (!ON_STR_BEGIN(s) && ONIGENC_IS_MBC_WORD(encode, sprev, end)) {
	if (ON_STR_END(s) || !ONIGENC_IS_MBC_WORD(encode, s, end)) {
	  MOP_OUT;
	  JUMP;
	}
      }
      goto fail;
      NEXT;

    CASE(OP_ASCII_WORD_END)  MOP_IN(OP_ASCII_WORD_END);
      if (!ON_STR_BEGIN(s) && ONIGENC_IS_MBC_ASCII_WORD(encode, sprev, end)) {
	if (ON_STR_END(s) || !ONIGENC_IS_MBC_ASCII_WORD(encode, s, end)) {
	  MOP_OUT;
	  JUMP;
	}
      }
      goto fail;
      NEXT;
#endif

    CASE(OP_BEGIN_BUF)  MOP_IN(OP_BEGIN_BUF);
      if (! ON_STR_BEGIN(s)) goto fail;
      if (IS_NOTBOS(msa->options)) goto fail;

      MOP_OUT;
      JUMP;

    CASE(OP_END_BUF)  MOP_IN(OP_END_BUF);
      if (! ON_STR_END(s)) goto fail;
      if (IS_NOTEOS(msa->options)) goto fail;

      MOP_OUT;
      JUMP;

    CASE(OP_BEGIN_LINE)  MOP_IN(OP_BEGIN_LINE);
      if (ON_STR_BEGIN(s)) {
	if (IS_NOTBOL(msa->options)) goto fail;
	MOP_OUT;
	JUMP;
      }
      else if (ONIGENC_IS_MBC_NEWLINE(encode, sprev, end)
#ifdef USE_CRNL_AS_LINE_TERMINATOR
		&& !(IS_NEWLINE_CRLF(option)
		     && ONIGENC_IS_MBC_CRNL(encode, sprev, end))
#endif
		&& !ON_STR_END(s)) {
	MOP_OUT;
	JUMP;
      }
      goto fail;
      NEXT;

    CASE(OP_END_LINE)  MOP_IN(OP_END_LINE);
      if (ON_STR_END(s)) {
#ifndef USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE
	if (IS_EMPTY_STR || !ONIGENC_IS_MBC_NEWLINE_EX(encode, sprev, str, end, option, 1)) {
#endif
	  if (IS_NOTEOL(msa->options)) goto fail;
	  MOP_OUT;
	  JUMP;
#ifndef USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE
	}
#endif
      }
      else if (ONIGENC_IS_MBC_NEWLINE_EX(encode, s, str, end, option, 1)) {
	MOP_OUT;
	JUMP;
      }
      goto fail;
      NEXT;

    CASE(OP_SEMI_END_BUF)  MOP_IN(OP_SEMI_END_BUF);
      if (ON_STR_END(s)) {
#ifndef USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE
	if (IS_EMPTY_STR || !ONIGENC_IS_MBC_NEWLINE_EX(encode, sprev, str, end, option, 1)) {
#endif
	  if (IS_NOTEOL(msa->options)) goto fail;
	  MOP_OUT;
	  JUMP;
#ifndef USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE
	}
#endif
      }
      else if (ONIGENC_IS_MBC_NEWLINE_EX(encode, s, str, end, option, 1)) {
	UChar* ss = s + enclen(encode, s, end);
	if (ON_STR_END(ss)) {
	  MOP_OUT;
	  JUMP;
	}
#ifdef USE_CRNL_AS_LINE_TERMINATOR
	else if (IS_NEWLINE_CRLF(option)
	    && ONIGENC_IS_MBC_CRNL(encode, s, end)) {
	  ss += enclen(encode, ss, end);
	  if (ON_STR_END(ss)) {
	    MOP_OUT;
	    JUMP;
	  }
	}
#endif
      }
      goto fail;
      NEXT;

    CASE(OP_BEGIN_POSITION)  MOP_IN(OP_BEGIN_POSITION);
      if (s != msa->gpos)
	goto fail;

      MOP_OUT;
      JUMP;

    CASE(OP_MEMORY_START_PUSH)  MOP_IN(OP_MEMORY_START_PUSH);
      GET_MEMNUM_INC(mem, p);
      STACK_PUSH_MEM_START(mem, s);
      MOP_OUT;
      JUMP;

    CASE(OP_MEMORY_START)  MOP_IN(OP_MEMORY_START);
      GET_MEMNUM_INC(mem, p);
      mem_start_stk[mem] = (OnigStackIndex )((void* )s);
      mem_end_stk[mem] = INVALID_STACK_INDEX;
      MOP_OUT;
      JUMP;

    CASE(OP_MEMORY_END_PUSH)  MOP_IN(OP_MEMORY_END_PUSH);
      GET_MEMNUM_INC(mem, p);
      STACK_PUSH_MEM_END(mem, s);
      MOP_OUT;
      JUMP;

    CASE(OP_MEMORY_END)  MOP_IN(OP_MEMORY_END);
      GET_MEMNUM_INC(mem, p);
      mem_end_stk[mem] = (OnigStackIndex )((void* )s);
      MOP_OUT;
      JUMP;

    CASE(OP_KEEP)  MOP_IN(OP_KEEP);
      pkeep = s;
      MOP_OUT;
      JUMP;

#ifdef USE_SUBEXP_CALL
    CASE(OP_MEMORY_END_PUSH_REC)  MOP_IN(OP_MEMORY_END_PUSH_REC);
      GET_MEMNUM_INC(mem, p);
      STACK_GET_MEM_START(mem, stkp); /* should be before push mem-end. */
      mem_start_stk[mem] = GET_STACK_INDEX(stkp);
      STACK_PUSH_MEM_END(mem, s);
      MOP_OUT;
      JUMP;

    CASE(OP_MEMORY_END_REC)  MOP_IN(OP_MEMORY_END_REC);
      GET_MEMNUM_INC(mem, p);
      mem_end_stk[mem] = (OnigStackIndex )((void* )s);
      STACK_GET_MEM_START(mem, stkp);

      if (BIT_STATUS_AT(reg->bt_mem_start, mem))
	mem_start_stk[mem] = GET_STACK_INDEX(stkp);
      else
	mem_start_stk[mem] = (OnigStackIndex )((void* )stkp->u.mem.pstr);

      STACK_PUSH_MEM_END_MARK(mem);
      MOP_OUT;
      JUMP;
#endif

    CASE(OP_BACKREF1)  MOP_IN(OP_BACKREF1);
      mem = 1;
      goto backref;
      NEXT;

    CASE(OP_BACKREF2)  MOP_IN(OP_BACKREF2);
      mem = 2;
      goto backref;
      NEXT;

    CASE(OP_BACKREFN)  MOP_IN(OP_BACKREFN);
      GET_MEMNUM_INC(mem, p);
    backref:
      {
	int len;
	UChar *pstart, *pend;

	/* if you want to remove following line,
	   you should check in parse and compile time. */
	if (mem > num_mem) goto fail;
	if (mem_end_stk[mem]   == INVALID_STACK_INDEX) goto fail;
	if (mem_start_stk[mem] == INVALID_STACK_INDEX) goto fail;

	if (BIT_STATUS_AT(reg->bt_mem_start, mem))
	  pstart = STACK_AT(mem_start_stk[mem])->u.mem.pstr;
	else
	  pstart = (UChar* )((void* )mem_start_stk[mem]);

	pend = (BIT_STATUS_AT(reg->bt_mem_end, mem)
		? STACK_AT(mem_end_stk[mem])->u.mem.pstr
		: (UChar* )((void* )mem_end_stk[mem]));
	n = pend - pstart;
	DATA_ENSURE(n);
	sprev = s;
	STRING_CMP(pstart, s, n);
	while (sprev + (len = enclen_approx(encode, sprev, end)) < s)
	  sprev += len;

	MOP_OUT;
	JUMP;
      }

    CASE(OP_BACKREFN_IC)  MOP_IN(OP_BACKREFN_IC);
      GET_MEMNUM_INC(mem, p);
      {
	int len;
	UChar *pstart, *pend;

	/* if you want to remove following line,
	   you should check in parse and compile time. */
	if (mem > num_mem) goto fail;
	if (mem_end_stk[mem]   == INVALID_STACK_INDEX) goto fail;
	if (mem_start_stk[mem] == INVALID_STACK_INDEX) goto fail;

	if (BIT_STATUS_AT(reg->bt_mem_start, mem))
	  pstart = STACK_AT(mem_start_stk[mem])->u.mem.pstr;
	else
	  pstart = (UChar* )((void* )mem_start_stk[mem]);

	pend = (BIT_STATUS_AT(reg->bt_mem_end, mem)
		? STACK_AT(mem_end_stk[mem])->u.mem.pstr
		: (UChar* )((void* )mem_end_stk[mem]));
	n = pend - pstart;
	DATA_ENSURE(n);
	sprev = s;
	STRING_CMP_IC(case_fold_flag, pstart, &s, n, end);
	while (sprev + (len = enclen_approx(encode, sprev, end)) < s)
	  sprev += len;

	MOP_OUT;
	JUMP;
      }
      NEXT;

    CASE(OP_BACKREF_MULTI)  MOP_IN(OP_BACKREF_MULTI);
      {
	int len, is_fail;
	UChar *pstart, *pend, *swork;

	GET_LENGTH_INC(tlen, p);
	for (i = 0; i < tlen; i++) {
	  GET_MEMNUM_INC(mem, p);

	  if (mem_end_stk[mem]   == INVALID_STACK_INDEX) continue;
	  if (mem_start_stk[mem] == INVALID_STACK_INDEX) continue;

	  if (BIT_STATUS_AT(reg->bt_mem_start, mem))
	    pstart = STACK_AT(mem_start_stk[mem])->u.mem.pstr;
	  else
	    pstart = (UChar* )((void* )mem_start_stk[mem]);

	  pend = (BIT_STATUS_AT(reg->bt_mem_end, mem)
		  ? STACK_AT(mem_end_stk[mem])->u.mem.pstr
		  : (UChar* )((void* )mem_end_stk[mem]));
	  n = pend - pstart;
	  DATA_ENSURE_CONTINUE(n);
	  sprev = s;
	  swork = s;
	  STRING_CMP_VALUE(pstart, swork, n, is_fail);
	  if (is_fail) continue;
	  s = swork;
	  while (sprev + (len = enclen_approx(encode, sprev, end)) < s)
	    sprev += len;

	  p += (SIZE_MEMNUM * (tlen - i - 1));
	  break; /* success */
	}
	if (i == tlen) goto fail;
	MOP_OUT;
	JUMP;
      }
      NEXT;

    CASE(OP_BACKREF_MULTI_IC)  MOP_IN(OP_BACKREF_MULTI_IC);
      {
	int len, is_fail;
	UChar *pstart, *pend, *swork;

	GET_LENGTH_INC(tlen, p);
	for (i = 0; i < tlen; i++) {
	  GET_MEMNUM_INC(mem, p);

	  if (mem_end_stk[mem]   == INVALID_STACK_INDEX) continue;
	  if (mem_start_stk[mem] == INVALID_STACK_INDEX) continue;

	  if (BIT_STATUS_AT(reg->bt_mem_start, mem))
	    pstart = STACK_AT(mem_start_stk[mem])->u.mem.pstr;
	  else
	    pstart = (UChar* )((void* )mem_start_stk[mem]);

	  pend = (BIT_STATUS_AT(reg->bt_mem_end, mem)
		  ? STACK_AT(mem_end_stk[mem])->u.mem.pstr
		  : (UChar* )((void* )mem_end_stk[mem]));
	  n = pend - pstart;
	  DATA_ENSURE_CONTINUE(n);
	  sprev = s;
	  swork = s;
	  STRING_CMP_VALUE_IC(case_fold_flag, pstart, &swork, n, end, is_fail);
	  if (is_fail) continue;
	  s = swork;
	  while (sprev + (len = enclen(encode, sprev, end)) < s)
	    sprev += len;

	  p += (SIZE_MEMNUM * (tlen - i - 1));
	  break; /* success */
	}
	if (i == tlen) goto fail;
	MOP_OUT;
	JUMP;
      }

#ifdef USE_BACKREF_WITH_LEVEL
    CASE(OP_BACKREF_WITH_LEVEL)
      {
	int len;
	OnigOptionType ic;
	LengthType level;

	GET_OPTION_INC(ic,    p);
	GET_LENGTH_INC(level, p);
	GET_LENGTH_INC(tlen,  p);

	sprev = s;
	if (backref_match_at_nested_level(reg, stk, stk_base, ic,
		  case_fold_flag, (int )level, (int )tlen, p, &s, end)) {
	  while (sprev + (len = enclen(encode, sprev, end)) < s)
	    sprev += len;

	  p += (SIZE_MEMNUM * tlen);
	}
	else
	  goto fail;

	MOP_OUT;
	JUMP;
      }

#endif

#if 0   /* no need: IS_DYNAMIC_OPTION() == 0 */
    CASE(OP_SET_OPTION_PUSH)  MOP_IN(OP_SET_OPTION_PUSH);
      GET_OPTION_INC(option, p);
      STACK_PUSH_ALT(p, s, sprev, pkeep);
      p += SIZE_OP_SET_OPTION + SIZE_OP_FAIL;
      MOP_OUT;
      JUMP;

    CASE(OP_SET_OPTION)  MOP_IN(OP_SET_OPTION);
      GET_OPTION_INC(option, p);
      MOP_OUT;
      JUMP;
#endif

    CASE(OP_NULL_CHECK_START)  MOP_IN(OP_NULL_CHECK_START);
      GET_MEMNUM_INC(mem, p);    /* mem: null check id */
      STACK_PUSH_NULL_CHECK_START(mem, s);
      MOP_OUT;
      JUMP;

    CASE(OP_NULL_CHECK_END)  MOP_IN(OP_NULL_CHECK_END);
      {
	int isnull;

	GET_MEMNUM_INC(mem, p); /* mem: null check id */
	STACK_NULL_CHECK(isnull, mem, s);
	if (isnull) {
#ifdef ONIG_DEBUG_MATCH
	  fprintf(stderr, "NULL_CHECK_END: skip  id:%d, s:%"PRIuPTR" (%p)\n",
		  (int )mem, (uintptr_t )s, s);
#endif
	null_check_found:
	  /* empty loop founded, skip next instruction */
	  switch (*p++) {
	  case OP_JUMP:
	  case OP_PUSH:
	    p += SIZE_RELADDR;
	    break;
	  case OP_REPEAT_INC:
	  case OP_REPEAT_INC_NG:
	  case OP_REPEAT_INC_SG:
	  case OP_REPEAT_INC_NG_SG:
	    p += SIZE_MEMNUM;
	    break;
	  default:
	    goto unexpected_bytecode_error;
	    break;
	  }
	}
      }
      MOP_OUT;
      JUMP;

#ifdef USE_MONOMANIAC_CHECK_CAPTURES_IN_ENDLESS_REPEAT
    CASE(OP_NULL_CHECK_END_MEMST)  MOP_IN(OP_NULL_CHECK_END_MEMST);
      {
	int isnull;

	GET_MEMNUM_INC(mem, p); /* mem: null check id */
	STACK_NULL_CHECK_MEMST(isnull, mem, s, reg);
	if (isnull) {
# ifdef ONIG_DEBUG_MATCH
	  fprintf(stderr, "NULL_CHECK_END_MEMST: skip  id:%d, s:%"PRIuPTR" (%p)\n",
		  (int )mem, (uintptr_t )s, s);
# endif
	  if (isnull == -1) goto fail;
	  goto null_check_found;
	}
      }
      MOP_OUT;
      JUMP;
#endif

#ifdef USE_SUBEXP_CALL
    CASE(OP_NULL_CHECK_END_MEMST_PUSH)
      MOP_IN(OP_NULL_CHECK_END_MEMST_PUSH);
      {
	int isnull;

	GET_MEMNUM_INC(mem, p); /* mem: null check id */
# ifdef USE_MONOMANIAC_CHECK_CAPTURES_IN_ENDLESS_REPEAT
	STACK_NULL_CHECK_MEMST_REC(isnull, mem, s, reg);
# else
	STACK_NULL_CHECK_REC(isnull, mem, s);
# endif
	if (isnull) {
# ifdef ONIG_DEBUG_MATCH
	  fprintf(stderr, "NULL_CHECK_END_MEMST_PUSH: skip  id:%d, s:%"PRIuPTR" (%p)\n",
		  (int )mem, (uintptr_t )s, s);
# endif
	  if (isnull == -1) goto fail;
	  goto null_check_found;
	}
	else {
	  STACK_PUSH_NULL_CHECK_END(mem);
	}
      }
      MOP_OUT;
      JUMP;
#endif

    CASE(OP_JUMP)  MOP_IN(OP_JUMP);
      GET_RELADDR_INC(addr, p);
      p += addr;
      MOP_OUT;
      CHECK_INTERRUPT_IN_MATCH_AT;
      JUMP;

    CASE(OP_PUSH)  MOP_IN(OP_PUSH);
      GET_RELADDR_INC(addr, p);
      CHECK_MATCH_CACHE;
      STACK_PUSH_ALT(p + addr, s, sprev, pkeep);
      MOP_OUT;
      JUMP;

#ifdef USE_COMBINATION_EXPLOSION_CHECK
    CASE(OP_STATE_CHECK_PUSH)  MOP_IN(OP_STATE_CHECK_PUSH);
      GET_STATE_CHECK_NUM_INC(mem, p);
      STATE_CHECK_VAL(scv, mem);
      if (scv) goto fail;

      GET_RELADDR_INC(addr, p);
      STACK_PUSH_ALT_WITH_STATE_CHECK(p + addr, s, sprev, mem, pkeep);
      MOP_OUT;
      JUMP;

    CASE(OP_STATE_CHECK_PUSH_OR_JUMP)  MOP_IN(OP_STATE_CHECK_PUSH_OR_JUMP);
      GET_STATE_CHECK_NUM_INC(mem, p);
      GET_RELADDR_INC(addr, p);
      STATE_CHECK_VAL(scv, mem);
      if (scv) {
	p += addr;
      }
      else {
	STACK_PUSH_ALT_WITH_STATE_CHECK(p + addr, s, sprev, mem, pkeep);
      }
      MOP_OUT;
      JUMP;

    CASE(OP_STATE_CHECK)  MOP_IN(OP_STATE_CHECK);
      GET_STATE_CHECK_NUM_INC(mem, p);
      STATE_CHECK_VAL(scv, mem);
      if (scv) goto fail;

      STACK_PUSH_STATE_CHECK(s, mem);
      MOP_OUT;
      JUMP;
#endif /* USE_COMBINATION_EXPLOSION_CHECK */

    CASE(OP_POP)  MOP_IN(OP_POP);
      STACK_POP_ONE;
#ifdef USE_MATCH_CACHE
      /* We need to increment num_fails here, for invoking a cache optimization correctly, */
      /* because Onigmo makes a loop, which is pairwise disjoint to the following set, as atomic. */
      msa->num_fails++;
#endif
      MOP_OUT;
      JUMP;

#ifdef USE_OP_PUSH_OR_JUMP_EXACT
    CASE(OP_PUSH_OR_JUMP_EXACT1)  MOP_IN(OP_PUSH_OR_JUMP_EXACT1);
      GET_RELADDR_INC(addr, p);
      if (*p == *s && DATA_ENSURE_CHECK1) {
	p++;
	CHECK_MATCH_CACHE;
	STACK_PUSH_ALT(p + addr, s, sprev, pkeep);
	MOP_OUT;
	JUMP;
      }
      p += (addr + 1);
      MOP_OUT;
      JUMP;
#endif

    CASE(OP_PUSH_IF_PEEK_NEXT)  MOP_IN(OP_PUSH_IF_PEEK_NEXT);
      GET_RELADDR_INC(addr, p);
      CHECK_MATCH_CACHE;
      if (*p == *s) {
	p++;
	STACK_PUSH_ALT(p + addr, s, sprev, pkeep);
	MOP_OUT;
	JUMP;
      }
      p++;
      INC_NUM_FAILS;
      MOP_OUT;
      JUMP;

    CASE(OP_REPEAT)  MOP_IN(OP_REPEAT);
      {
	GET_MEMNUM_INC(mem, p);    /* mem: OP_REPEAT ID */
	GET_RELADDR_INC(addr, p);

	STACK_ENSURE(1);
	repeat_stk[mem] = GET_STACK_INDEX(stk);
	STACK_PUSH_REPEAT(mem, p);

	if (reg->repeat_range[mem].lower == 0) {
	  CHECK_MATCH_CACHE;
	  STACK_PUSH_ALT(p + addr, s, sprev, pkeep);
	}
      }
      MOP_OUT;
      JUMP;

    CASE(OP_REPEAT_NG)  MOP_IN(OP_REPEAT_NG);
      {
	GET_MEMNUM_INC(mem, p);    /* mem: OP_REPEAT ID */
	GET_RELADDR_INC(addr, p);

	STACK_ENSURE(1);
	repeat_stk[mem] = GET_STACK_INDEX(stk);
	STACK_PUSH_REPEAT(mem, p);

	if (reg->repeat_range[mem].lower == 0) {
	  CHECK_MATCH_CACHE;
	  STACK_PUSH_ALT(p, s, sprev, pkeep);
	  p += addr;
	}
      }
      MOP_OUT;
      JUMP;

    CASE(OP_REPEAT_INC)  MOP_IN(OP_REPEAT_INC);
      GET_MEMNUM_INC(mem, p); /* mem: OP_REPEAT ID */
      si = repeat_stk[mem];
      stkp = STACK_AT(si);

    repeat_inc:
      stkp->u.repeat.count++;
      if (stkp->u.repeat.count >= reg->repeat_range[mem].upper) {
	/* end of repeat. Nothing to do. */
      }
      else if (stkp->u.repeat.count >= reg->repeat_range[mem].lower) {
#ifdef USE_MATCH_CACHE
	if (*pbegin == OP_REPEAT_INC) {
#undef MATCH_CACHE_HIT
#define MATCH_CACHE_HIT stkp->u.repeat.count--;
	  CHECK_MATCH_CACHE;
#undef MATCH_CACHE_HIT
#define MATCH_CACHE_HIT ((void) 0)
	}
#endif
	STACK_PUSH_ALT(p, s, sprev, pkeep);
	p = STACK_AT(si)->u.repeat.pcode; /* Don't use stkp after PUSH. */
      }
      else {
	p = stkp->u.repeat.pcode;
      }
      STACK_PUSH_REPEAT_INC(si);
      MOP_OUT;
      CHECK_INTERRUPT_IN_MATCH_AT;
      JUMP;

    CASE(OP_REPEAT_INC_SG)  MOP_IN(OP_REPEAT_INC_SG);
      GET_MEMNUM_INC(mem, p); /* mem: OP_REPEAT ID */
      STACK_GET_REPEAT(mem, stkp);
      si = GET_STACK_INDEX(stkp);
      goto repeat_inc;
      NEXT;

    CASE(OP_REPEAT_INC_NG)  MOP_IN(OP_REPEAT_INC_NG);
      GET_MEMNUM_INC(mem, p); /* mem: OP_REPEAT ID */
      si = repeat_stk[mem];
      stkp = STACK_AT(si);

    repeat_inc_ng:
      stkp->u.repeat.count++;
      if (stkp->u.repeat.count < reg->repeat_range[mem].upper) {
	if (stkp->u.repeat.count >= reg->repeat_range[mem].lower) {
	  UChar* pcode = stkp->u.repeat.pcode;

	  STACK_PUSH_REPEAT_INC(si);
	  if (*pbegin == OP_REPEAT_INC_NG) {
	    CHECK_MATCH_CACHE;
	  }
	  STACK_PUSH_ALT(pcode, s, sprev, pkeep);
	}
	else {
	  p = stkp->u.repeat.pcode;
	  STACK_PUSH_REPEAT_INC(si);
	}
      }
      else if (stkp->u.repeat.count == reg->repeat_range[mem].upper) {
	STACK_PUSH_REPEAT_INC(si);
      }
      MOP_OUT;
      CHECK_INTERRUPT_IN_MATCH_AT;
      JUMP;

    CASE(OP_REPEAT_INC_NG_SG)  MOP_IN(OP_REPEAT_INC_NG_SG);
      GET_MEMNUM_INC(mem, p); /* mem: OP_REPEAT ID */
      STACK_GET_REPEAT(mem, stkp);
      si = GET_STACK_INDEX(stkp);
      goto repeat_inc_ng;
      NEXT;

    CASE(OP_PUSH_POS)  MOP_IN(OP_PUSH_POS);
      STACK_PUSH_POS(s, sprev, pkeep);
      MOP_OUT;
      JUMP;

    CASE(OP_POP_POS)  MOP_IN(OP_POP_POS);
      {
	STACK_POS_END(stkp);
	s     = stkp->u.state.pstr;
	sprev = stkp->u.state.pstr_prev;
      }
      MOP_OUT;
      JUMP;

    CASE(OP_PUSH_POS_NOT)  MOP_IN(OP_PUSH_POS_NOT);
      GET_RELADDR_INC(addr, p);
      STACK_PUSH_POS_NOT(p + addr, s, sprev, pkeep);
      MOP_OUT;
      JUMP;

    CASE(OP_FAIL_POS)  MOP_IN(OP_FAIL_POS);
      STACK_POP_TIL_POS_NOT;
      goto fail;
      NEXT;

    CASE(OP_PUSH_STOP_BT)  MOP_IN(OP_PUSH_STOP_BT);
      STACK_PUSH_STOP_BT;
      MOP_OUT;
      JUMP;

    CASE(OP_POP_STOP_BT)  MOP_IN(OP_POP_STOP_BT);
      STACK_STOP_BT_END;
      MOP_OUT;
      JUMP;

    CASE(OP_LOOK_BEHIND)  MOP_IN(OP_LOOK_BEHIND);
      GET_LENGTH_INC(tlen, p);
      s = (UChar* )ONIGENC_STEP_BACK(encode, str, s, end, (int )tlen);
      if (IS_NULL(s)) goto fail;
      sprev = (UChar* )onigenc_get_prev_char_head(encode, str, s, end);
      MOP_OUT;
      JUMP;

    CASE(OP_PUSH_LOOK_BEHIND_NOT)  MOP_IN(OP_PUSH_LOOK_BEHIND_NOT);
      GET_RELADDR_INC(addr, p);
      GET_LENGTH_INC(tlen, p);
      q = (UChar* )ONIGENC_STEP_BACK(encode, str, s, end, (int )tlen);
      if (IS_NULL(q)) {
	/* too short case -> success. ex. /(?<!XXX)a/.match("a")
	   If you want to change to fail, replace following line. */
	p += addr;
	/* goto fail; */
      }
      else {
	STACK_PUSH_LOOK_BEHIND_NOT(p + addr, s, sprev, pkeep);
	s = q;
	sprev = (UChar* )onigenc_get_prev_char_head(encode, str, s, end);
      }
      MOP_OUT;
      JUMP;

    CASE(OP_FAIL_LOOK_BEHIND_NOT)  MOP_IN(OP_FAIL_LOOK_BEHIND_NOT);
      STACK_POP_TIL_LOOK_BEHIND_NOT;
      goto fail;
      NEXT;

    CASE(OP_PUSH_ABSENT_POS)  MOP_IN(OP_PUSH_ABSENT_POS);
      /* Save the absent-start-pos and the original end-pos. */
      STACK_PUSH_ABSENT_POS(s, ABSENT_END_POS);
      MOP_OUT;
      JUMP;

    CASE(OP_ABSENT)  MOP_IN(OP_ABSENT);
      {
	const UChar* aend = ABSENT_END_POS;
	UChar* absent;
	UChar* selfp = p - 1;

	STACK_POP_ABSENT_POS(absent, ABSENT_END_POS);  /* Restore end-pos. */
	GET_RELADDR_INC(addr, p);
#ifdef ONIG_DEBUG_MATCH
	fprintf(stderr, "ABSENT: s:%p, end:%p, absent:%p, aend:%p\n", s, end, absent, aend);
#endif
	if ((absent > aend) && (s > absent)) {
	  /* An empty match occurred in (?~...) at the start point.
	   * Never match. */
	  STACK_POP;
	  goto fail;
	}
	else if ((s >= aend) && (s > absent)) {
	  if (s > aend) {
	    /* Only one (or less) character matched in the last iteration.
	     * This is not a possible point. */
	    goto fail;
	  }
	  /* All possible points were found. Try matching after (?~...). */
	  DATA_ENSURE(0);
	  p += addr;
	}
	else if (s == end) {
	  /* At the end of the string, just match with it */
	  DATA_ENSURE(0);
	  p += addr;
	}
	else {
	  STACK_PUSH_ALT(p + addr, s, sprev, pkeep); /* Push possible point. */
	  n = enclen(encode, s, end);
	  STACK_PUSH_ABSENT_POS(absent, ABSENT_END_POS); /* Save the original pos. */
	  STACK_PUSH_ALT(selfp, s + n, s, pkeep); /* Next iteration. */
	  STACK_PUSH_ABSENT;
	  ABSENT_END_POS = aend;
	}
      }
      MOP_OUT;
      JUMP;

    CASE(OP_ABSENT_END)  MOP_IN(OP_ABSENT_END);
      /* The pattern inside (?~...) was matched.
       * Set the end-pos temporary and go to next iteration. */
      if (sprev < ABSENT_END_POS)
	ABSENT_END_POS = sprev;
#ifdef ONIG_DEBUG_MATCH
      fprintf(stderr, "ABSENT_END: end:%p\n", ABSENT_END_POS);
#endif
      STACK_POP_TIL_ABSENT;
      goto fail;
      NEXT;

#ifdef USE_SUBEXP_CALL
    CASE(OP_CALL)  MOP_IN(OP_CALL);
      GET_ABSADDR_INC(addr, p);
      STACK_PUSH_CALL_FRAME(p);
      p = reg->p + addr;
      MOP_OUT;
      JUMP;

    CASE(OP_RETURN)  MOP_IN(OP_RETURN);
      STACK_RETURN(p);
      STACK_PUSH_RETURN;
      MOP_OUT;
      JUMP;
#endif

    CASE(OP_CONDITION)  MOP_IN(OP_CONDITION);
      GET_MEMNUM_INC(mem, p);
      GET_RELADDR_INC(addr, p);
      if ((mem > num_mem) ||
	  (mem_end_stk[mem]   == INVALID_STACK_INDEX) ||
	  (mem_start_stk[mem] == INVALID_STACK_INDEX)) {
	p += addr;
      }
      MOP_OUT;
      JUMP;

    CASE(OP_FINISH)
      goto finish;
      NEXT;

    CASE(OP_FAIL)
      if (0) {
	/* fall */
      fail:
	MOP_OUT;
      }
      MOP_IN(OP_FAIL);
      STACK_POP;
      p     = stk->u.state.pcode;
      s     = stk->u.state.pstr;
      sprev = stk->u.state.pstr_prev;
      pkeep = stk->u.state.pkeep;

#ifdef USE_MATCH_CACHE
      if (
	  msa->match_cache_status != MATCH_CACHE_STATUS_DISABLED &&
	  ++msa->num_fails >= (long)(end - str) * msa->num_cache_opcodes
      ) {
	if (msa->match_cache_status == MATCH_CACHE_STATUS_UNINIT) {
	  msa->match_cache_status = MATCH_CACHE_STATUS_INIT;
	  OnigPosition r = count_num_cache_opcodes(reg, &msa->num_cache_opcodes);
	  if (r < 0) goto bytecode_error;
	}
	if (msa->num_cache_opcodes == NUM_CACHE_OPCODES_IMPOSSIBLE || msa->num_cache_opcodes == 0) {
	  msa->match_cache_status = MATCH_CACHE_STATUS_DISABLED;
	  goto fail_match_cache;
	}
	if (msa->num_fails < (long)(end - str) * msa->num_cache_opcodes) {
	  goto fail_match_cache;
	}
	if (msa->cache_opcodes == NULL) {
	  msa->match_cache_status = MATCH_CACHE_STATUS_ENABLED;
	  OnigCacheOpcode* cache_opcodes = (OnigCacheOpcode*)xmalloc(msa->num_cache_opcodes * sizeof(OnigCacheOpcode));
	  if (cache_opcodes == NULL) {
	    return ONIGERR_MEMORY;
	  }
	  OnigPosition r = init_cache_opcodes(reg, cache_opcodes, &msa->num_cache_points);
	  if (r < 0) {
	    if (r == ONIGERR_UNEXPECTED_BYTECODE) goto unexpected_bytecode_error;
	    else goto bytecode_error;
	  }
	  msa->cache_opcodes = cache_opcodes;
#ifdef ONIG_DEBUG_MATCH_CACHE
	  fprintf(stderr, "MATCH CACHE: #cache opcodes = %ld\n", msa->num_cache_opcodes);
	  fprintf(stderr, "MATCH CACHE: #cache points = %ld\n", msa->num_cache_points);
	  fprintf(stderr, "MATCH CACHE: cache opcodes (%p):\n", msa->cache_opcodes);
	  for (int i = 0; i < msa->num_cache_opcodes; i++) {
	    fprintf(stderr, "MATCH CACHE:   [%p] cache_point=%ld outer_repeat_mem=%d num_cache_opcodes_at_outer_repeat=%ld num_cache_opcodes_in_outer_repeat=%ld lookaround_nesting=%d match_addr=%p\n", msa->cache_opcodes[i].addr, msa->cache_opcodes[i].cache_point, msa->cache_opcodes[i].outer_repeat_mem, msa->cache_opcodes[i].num_cache_points_at_outer_repeat, msa->cache_opcodes[i].num_cache_points_in_outer_repeat, msa->cache_opcodes[i].lookaround_nesting, msa->cache_opcodes[i].match_addr);
	  }
#endif
	}
	if (msa->match_cache_buf == NULL) {
	  size_t length = (end - str) + 1;
	  size_t num_match_cache_points = (size_t)msa->num_cache_points * length;
#ifdef ONIG_DEBUG_MATCH_CACHE
	  fprintf(stderr, "MATCH CACHE: #match cache points = %"PRIuSIZE" (length = %"PRIuSIZE")\n", num_match_cache_points, length);
#endif
	  /* Overflow check */
	  if (num_match_cache_points / length != (size_t)msa->num_cache_points) {
	    return ONIGERR_MEMORY;
	  }
	  if (num_match_cache_points >= LONG_MAX_LIMIT) {
	    return ONIGERR_MEMORY;
	  }
	  size_t match_cache_buf_length = (num_match_cache_points >> 3) + (num_match_cache_points & 7 ? 1 : 0) + 1;
	  uint8_t* match_cache_buf = (uint8_t*)xmalloc(match_cache_buf_length * sizeof(uint8_t));
	  if (match_cache_buf == NULL) {
	    return ONIGERR_MEMORY;
	  }
	  xmemset(match_cache_buf, 0, match_cache_buf_length * sizeof(uint8_t));
	  msa->match_cache_buf = match_cache_buf;
	}
      }
      fail_match_cache:
#endif

#ifdef USE_COMBINATION_EXPLOSION_CHECK
      if (stk->u.state.state_check != 0) {
	stk->type = STK_STATE_CHECK_MARK;
	stk++;
      }
#endif

      MOP_OUT;
      CHECK_INTERRUPT_IN_MATCH_AT;
      JUMP;

    DEFAULT
      goto bytecode_error;
  } VM_LOOP_END

 finish:
  STACK_SAVE;
  xfree(xmalloc_base);
  return best_len;

#ifdef ONIG_DEBUG
 stack_error:
  STACK_SAVE;
  xfree(xmalloc_base);
  return ONIGERR_STACK_BUG;
#endif

 bytecode_error:
  STACK_SAVE;
  xfree(xmalloc_base);
  return ONIGERR_UNDEFINED_BYTECODE;

 unexpected_bytecode_error:
  STACK_SAVE;
  xfree(xmalloc_base);
  return ONIGERR_UNEXPECTED_BYTECODE;

 timeout:
  STACK_SAVE;
  xfree(xmalloc_base);
  return ONIGERR_TIMEOUT;
}


static UChar*
slow_search(OnigEncoding enc, UChar* target, UChar* target_end,
	    const UChar* text, const UChar* text_end, UChar* text_range)
{
  UChar *t, *p, *s, *end;

  end = (UChar* )text_end;
  end -= target_end - target - 1;
  if (end > text_range)
    end = text_range;

  s = (UChar* )text;

  if (enc->max_enc_len == enc->min_enc_len) {
    int n = enc->max_enc_len;

    while (s < end) {
      if (*s == *target) {
	p = s + 1;
	t = target + 1;
	if (target_end == t || memcmp(t, p, target_end - t) == 0)
	  return s;
      }
      s += n;
    }
    return (UChar* )NULL;
  }
  while (s < end) {
    if (*s == *target) {
      p = s + 1;
      t = target + 1;
      if (target_end == t || memcmp(t, p, target_end - t) == 0)
	return s;
    }
    s += enclen(enc, s, text_end);
  }

  return (UChar* )NULL;
}

static int
str_lower_case_match(OnigEncoding enc, int case_fold_flag,
		     const UChar* t, const UChar* tend,
		     const UChar* p, const UChar* end)
{
  int lowlen;
  UChar *q, lowbuf[ONIGENC_MBC_CASE_FOLD_MAXLEN];

  while (t < tend) {
    lowlen = ONIGENC_MBC_CASE_FOLD(enc, case_fold_flag, &p, end, lowbuf);
    q = lowbuf;
    while (lowlen > 0) {
      if (*t++ != *q++)	return 0;
      lowlen--;
    }
  }

  return 1;
}

static UChar*
slow_search_ic(OnigEncoding enc, int case_fold_flag,
	       UChar* target, UChar* target_end,
	       const UChar* text, const UChar* text_end, UChar* text_range)
{
  UChar *s, *end;

  end = (UChar* )text_end;
  end -= target_end - target - 1;
  if (end > text_range)
    end = text_range;

  s = (UChar* )text;

  while (s < end) {
    if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			     s, text_end))
      return s;

    s += enclen(enc, s, text_end);
  }

  return (UChar* )NULL;
}

static UChar*
slow_search_backward(OnigEncoding enc, UChar* target, UChar* target_end,
		     const UChar* text, const UChar* adjust_text,
		     const UChar* text_end, const UChar* text_start)
{
  UChar *t, *p, *s;

  s = (UChar* )text_end;
  s -= (target_end - target);
  if (s > text_start)
    s = (UChar* )text_start;
  else
    s = ONIGENC_LEFT_ADJUST_CHAR_HEAD(enc, adjust_text, s, text_end);

  while (s >= text) {
    if (*s == *target) {
      p = s + 1;
      t = target + 1;
      while (t < target_end) {
	if (*t != *p++)
	  break;
	t++;
      }
      if (t == target_end)
	return s;
    }
    s = (UChar* )onigenc_get_prev_char_head(enc, adjust_text, s, text_end);
  }

  return (UChar* )NULL;
}

static UChar*
slow_search_backward_ic(OnigEncoding enc, int case_fold_flag,
			UChar* target, UChar* target_end,
			const UChar* text, const UChar* adjust_text,
			const UChar* text_end, const UChar* text_start)
{
  UChar *s;

  s = (UChar* )text_end;
  s -= (target_end - target);
  if (s > text_start)
    s = (UChar* )text_start;
  else
    s = ONIGENC_LEFT_ADJUST_CHAR_HEAD(enc, adjust_text, s, text_end);

  while (s >= text) {
    if (str_lower_case_match(enc, case_fold_flag,
			     target, target_end, s, text_end))
      return s;

    s = (UChar* )onigenc_get_prev_char_head(enc, adjust_text, s, text_end);
  }

  return (UChar* )NULL;
}

#ifndef USE_SUNDAY_QUICK_SEARCH
/* Boyer-Moore-Horspool search applied to a multibyte string */
static UChar*
bm_search_notrev(regex_t* reg, const UChar* target, const UChar* target_end,
		 const UChar* text, const UChar* text_end,
		 const UChar* text_range)
{
  const UChar *s, *se, *t, *p, *end;
  const UChar *tail;
  ptrdiff_t skip, tlen1;

# ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "bm_search_notrev: text: %"PRIuPTR" (%p), text_end: %"PRIuPTR" (%p), text_range: %"PRIuPTR" (%p)\n",
	  (uintptr_t )text, text, (uintptr_t )text_end, text_end, (uintptr_t )text_range, text_range);
# endif

  tail = target_end - 1;
  tlen1 = tail - target;
  end = text_range;
  if (end + tlen1 > text_end)
    end = text_end - tlen1;

  s = text;

  if (IS_NULL(reg->int_map)) {
    while (s < end) {
      p = se = s + tlen1;
      t = tail;
      while (*p == *t) {
	if (t == target) return (UChar* )s;
	p--; t--;
      }
      skip = reg->map[*se];
      t = s;
      do {
	s += enclen(reg->enc, s, end);
      } while ((s - t) < skip && s < end);
    }
  }
  else {
# if OPT_EXACT_MAXLEN >= ONIG_CHAR_TABLE_SIZE
    while (s < end) {
      p = se = s + tlen1;
      t = tail;
      while (*p == *t) {
	if (t == target) return (UChar* )s;
	p--; t--;
      }
      skip = reg->int_map[*se];
      t = s;
      do {
	s += enclen(reg->enc, s, end);
      } while ((s - t) < skip && s < end);
    }
# endif
  }

  return (UChar* )NULL;
}

/* Boyer-Moore-Horspool search */
static UChar*
bm_search(regex_t* reg, const UChar* target, const UChar* target_end,
	  const UChar* text, const UChar* text_end, const UChar* text_range)
{
  const UChar *s, *t, *p, *end;
  const UChar *tail;

# ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "bm_search: text: %"PRIuPTR" (%p), text_end: %"PRIuPTR" (%p), text_range: %"PRIuPTR" (%p)\n",
	  (uintptr_t )text, text, (uintptr_t )text_end, text_end, (uintptr_t )text_range, text_range);
# endif

  end = text_range + (target_end - target) - 1;
  if (end > text_end)
    end = text_end;

  tail = target_end - 1;
  s = text + (target_end - target) - 1;
  if (IS_NULL(reg->int_map)) {
    while (s < end) {
      p = s;
      t = tail;
# ifdef ONIG_DEBUG_SEARCH
      fprintf(stderr, "bm_search_loop: pos: %"PRIdPTR" %s\n",
	  (intptr_t )(s - text), s);
# endif
      while (*p == *t) {
	if (t == target) return (UChar* )p;
	p--; t--;
      }
      s += reg->map[*s];
    }
  }
  else { /* see int_map[] */
# if OPT_EXACT_MAXLEN >= ONIG_CHAR_TABLE_SIZE
    while (s < end) {
      p = s;
      t = tail;
      while (*p == *t) {
	if (t == target) return (UChar* )p;
	p--; t--;
      }
      s += reg->int_map[*s];
    }
# endif
  }
  return (UChar* )NULL;
}

/* Boyer-Moore-Horspool search applied to a multibyte string (ignore case) */
static UChar*
bm_search_notrev_ic(regex_t* reg, const UChar* target, const UChar* target_end,
		    const UChar* text, const UChar* text_end,
		    const UChar* text_range)
{
  const UChar *s, *se, *t, *end;
  const UChar *tail;
  ptrdiff_t skip, tlen1;
  OnigEncoding enc = reg->enc;
  int case_fold_flag = reg->case_fold_flag;

# ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "bm_search_notrev_ic: text: %d (%p), text_end: %d (%p), text_range: %d (%p)\n",
	  (int )text, text, (int )text_end, text_end, (int )text_range, text_range);
# endif

  tail = target_end - 1;
  tlen1 = tail - target;
  end = text_range;
  if (end + tlen1 > text_end)
    end = text_end - tlen1;

  s = text;

  if (IS_NULL(reg->int_map)) {
    while (s < end) {
      se = s + tlen1;
      if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			       s, se + 1))
	return (UChar* )s;
      skip = reg->map[*se];
      t = s;
      do {
	s += enclen(reg->enc, s, end);
      } while ((s - t) < skip && s < end);
    }
  }
  else {
# if OPT_EXACT_MAXLEN >= ONIG_CHAR_TABLE_SIZE
    while (s < end) {
      se = s + tlen1;
      if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			       s, se + 1))
	return (UChar* )s;
      skip = reg->int_map[*se];
      t = s;
      do {
	s += enclen(reg->enc, s, end);
      } while ((s - t) < skip && s < end);
    }
# endif
  }

  return (UChar* )NULL;
}

/* Boyer-Moore-Horspool search (ignore case) */
static UChar*
bm_search_ic(regex_t* reg, const UChar* target, const UChar* target_end,
	     const UChar* text, const UChar* text_end, const UChar* text_range)
{
  const UChar *s, *p, *end;
  const UChar *tail;
  OnigEncoding enc = reg->enc;
  int case_fold_flag = reg->case_fold_flag;

# ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "bm_search_ic: text: %d (%p), text_end: %d (%p), text_range: %d (%p)\n",
	  (int )text, text, (int )text_end, text_end, (int )text_range, text_range);
# endif

  end = text_range + (target_end - target) - 1;
  if (end > text_end)
    end = text_end;

  tail = target_end - 1;
  s = text + (target_end - target) - 1;
  if (IS_NULL(reg->int_map)) {
    while (s < end) {
      p = s - (target_end - target) + 1;
      if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			       p, s + 1))
	return (UChar* )p;
      s += reg->map[*s];
    }
  }
  else { /* see int_map[] */
# if OPT_EXACT_MAXLEN >= ONIG_CHAR_TABLE_SIZE
    while (s < end) {
      p = s - (target_end - target) + 1;
      if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			       p, s + 1))
	return (UChar* )p;
      s += reg->int_map[*s];
    }
# endif
  }
  return (UChar* )NULL;
}

#else /* USE_SUNDAY_QUICK_SEARCH */

/* Sunday's quick search applied to a multibyte string */
static UChar*
bm_search_notrev(regex_t* reg, const UChar* target, const UChar* target_end,
		 const UChar* text, const UChar* text_end,
		 const UChar* text_range)
{
  const UChar *s, *se, *t, *p, *end;
  const UChar *tail;
  ptrdiff_t skip, tlen1;
  OnigEncoding enc = reg->enc;

# ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "bm_search_notrev: text: %"PRIuPTR" (%p), text_end: %"PRIuPTR" (%p), text_range: %"PRIuPTR" (%p)\n",
	  (uintptr_t )text, text, (uintptr_t )text_end, text_end, (uintptr_t )text_range, text_range);
# endif

  tail = target_end - 1;
  tlen1 = tail - target;
  end = text_range;
  if (end + tlen1 > text_end)
    end = text_end - tlen1;

  s = text;

  if (IS_NULL(reg->int_map)) {
    while (s < end) {
      p = se = s + tlen1;
      t = tail;
      while (*p == *t) {
	if (t == target) return (UChar* )s;
	p--; t--;
      }
      if (s + 1 >= end) break;
      skip = reg->map[se[1]];
      t = s;
      do {
	s += enclen(enc, s, end);
      } while ((s - t) < skip && s < end);
    }
  }
  else {
# if OPT_EXACT_MAXLEN >= ONIG_CHAR_TABLE_SIZE
    while (s < end) {
      p = se = s + tlen1;
      t = tail;
      while (*p == *t) {
	if (t == target) return (UChar* )s;
	p--; t--;
      }
      if (s + 1 >= end) break;
      skip = reg->int_map[se[1]];
      t = s;
      do {
	s += enclen(enc, s, end);
      } while ((s - t) < skip && s < end);
    }
# endif
  }

  return (UChar* )NULL;
}

/* Sunday's quick search */
static UChar*
bm_search(regex_t* reg, const UChar* target, const UChar* target_end,
	  const UChar* text, const UChar* text_end, const UChar* text_range)
{
  const UChar *s, *t, *p, *end;
  const UChar *tail;
  ptrdiff_t tlen1;

# ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "bm_search: text: %"PRIuPTR" (%p), text_end: %"PRIuPTR" (%p), text_range: %"PRIuPTR" (%p)\n",
	  (uintptr_t )text, text, (uintptr_t )text_end, text_end, (uintptr_t )text_range, text_range);
# endif

  tail = target_end - 1;
  tlen1 = tail - target;
  end = text_range + tlen1;
  if (end > text_end)
    end = text_end;

  s = text + tlen1;
  if (IS_NULL(reg->int_map)) {
    while (s < end) {
      p = s;
      t = tail;
      while (*p == *t) {
	if (t == target) return (UChar* )p;
	p--; t--;
      }
      if (s + 1 >= end) break;
      s += reg->map[s[1]];
    }
  }
  else { /* see int_map[] */
# if OPT_EXACT_MAXLEN >= ONIG_CHAR_TABLE_SIZE
    while (s < end) {
      p = s;
      t = tail;
      while (*p == *t) {
	if (t == target) return (UChar* )p;
	p--; t--;
      }
      if (s + 1 >= end) break;
      s += reg->int_map[s[1]];
    }
# endif
  }
  return (UChar* )NULL;
}

/* Sunday's quick search applied to a multibyte string (ignore case) */
static UChar*
bm_search_notrev_ic(regex_t* reg, const UChar* target, const UChar* target_end,
		    const UChar* text, const UChar* text_end,
		    const UChar* text_range)
{
  const UChar *s, *se, *t, *end;
  const UChar *tail;
  ptrdiff_t skip, tlen1;
  OnigEncoding enc = reg->enc;
  int case_fold_flag = reg->case_fold_flag;

# ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "bm_search_notrev_ic: text: %"PRIuPTR" (%p), text_end: %"PRIuPTR" (%p), text_range: %"PRIuPTR" (%p)\n",
	  (uintptr_t )text, text, (uintptr_t )text_end, text_end, (uintptr_t )text_range, text_range);
# endif

  tail = target_end - 1;
  tlen1 = tail - target;
  end = text_range;
  if (end + tlen1 > text_end)
    end = text_end - tlen1;

  s = text;

  if (IS_NULL(reg->int_map)) {
    while (s < end) {
      se = s + tlen1;
      if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			       s, se + 1))
	return (UChar* )s;
      if (s + 1 >= end) break;
      skip = reg->map[se[1]];
      t = s;
      do {
	s += enclen(enc, s, end);
      } while ((s - t) < skip && s < end);
    }
  }
  else {
# if OPT_EXACT_MAXLEN >= ONIG_CHAR_TABLE_SIZE
    while (s < end) {
      se = s + tlen1;
      if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			       s, se + 1))
	return (UChar* )s;
      if (s + 1 >= end) break;
      skip = reg->int_map[se[1]];
      t = s;
      do {
	s += enclen(enc, s, end);
      } while ((s - t) < skip && s < end);
    }
# endif
  }

  return (UChar* )NULL;
}

/* Sunday's quick search (ignore case) */
static UChar*
bm_search_ic(regex_t* reg, const UChar* target, const UChar* target_end,
	     const UChar* text, const UChar* text_end, const UChar* text_range)
{
  const UChar *s, *p, *end;
  const UChar *tail;
  ptrdiff_t tlen1;
  OnigEncoding enc = reg->enc;
  int case_fold_flag = reg->case_fold_flag;

# ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "bm_search_ic: text: %"PRIuPTR" (%p), text_end: %"PRIuPTR" (%p), text_range: %"PRIuPTR" (%p)\n",
	  (uintptr_t )text, text, (uintptr_t )text_end, text_end, (uintptr_t )text_range, text_range);
# endif

  tail = target_end - 1;
  tlen1 = tail - target;
  end = text_range + tlen1;
  if (end > text_end)
    end = text_end;

  s = text + tlen1;
  if (IS_NULL(reg->int_map)) {
    while (s < end) {
      p = s - tlen1;
      if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			       p, s + 1))
	return (UChar* )p;
      if (s + 1 >= end) break;
      s += reg->map[s[1]];
    }
  }
  else { /* see int_map[] */
# if OPT_EXACT_MAXLEN >= ONIG_CHAR_TABLE_SIZE
    while (s < end) {
      p = s - tlen1;
      if (str_lower_case_match(enc, case_fold_flag, target, target_end,
			       p, s + 1))
	return (UChar* )p;
      if (s + 1 >= end) break;
      s += reg->int_map[s[1]];
    }
# endif
  }
  return (UChar* )NULL;
}
#endif /* USE_SUNDAY_QUICK_SEARCH */

#ifdef USE_INT_MAP_BACKWARD
static int
set_bm_backward_skip(UChar* s, UChar* end, OnigEncoding enc ARG_UNUSED,
		     int** skip)
{
  int i, len;

  if (IS_NULL(*skip)) {
    *skip = (int* )xmalloc(sizeof(int) * ONIG_CHAR_TABLE_SIZE);
    if (IS_NULL(*skip)) return ONIGERR_MEMORY;
  }

  len = (int )(end - s);
  for (i = 0; i < ONIG_CHAR_TABLE_SIZE; i++)
    (*skip)[i] = len;

  for (i = len - 1; i > 0; i--)
    (*skip)[s[i]] = i;

  return 0;
}

static UChar*
bm_search_backward(regex_t* reg, const UChar* target, const UChar* target_end,
		   const UChar* text, const UChar* adjust_text,
		   const UChar* text_end, const UChar* text_start)
{
  const UChar *s, *t, *p;

  s = text_end - (target_end - target);
  if (text_start < s)
    s = text_start;
  else
    s = ONIGENC_LEFT_ADJUST_CHAR_HEAD(reg->enc, adjust_text, s, text_end);

  while (s >= text) {
    p = s;
    t = target;
    while (t < target_end && *p == *t) {
      p++; t++;
    }
    if (t == target_end)
      return (UChar* )s;

    s -= reg->int_map_backward[*s];
    s = ONIGENC_LEFT_ADJUST_CHAR_HEAD(reg->enc, adjust_text, s, text_end);
  }

  return (UChar* )NULL;
}
#endif

static UChar*
map_search(OnigEncoding enc, UChar map[],
	   const UChar* text, const UChar* text_range, const UChar* text_end)
{
  const UChar *s = text;

  while (s < text_range) {
    if (map[*s]) return (UChar* )s;

    s += enclen(enc, s, text_end);
  }
  return (UChar* )NULL;
}

static UChar*
map_search_backward(OnigEncoding enc, UChar map[],
		    const UChar* text, const UChar* adjust_text,
		    const UChar* text_start, const UChar* text_end)
{
  const UChar *s = text_start;

  while (s >= text) {
    if (map[*s]) return (UChar* )s;

    s = onigenc_get_prev_char_head(enc, adjust_text, s, text_end);
  }
  return (UChar* )NULL;
}

extern OnigPosition
onig_match(regex_t* reg, const UChar* str, const UChar* end, const UChar* at, OnigRegion* region,
	    OnigOptionType option)
{
  ptrdiff_t r;
  UChar *prev;
  OnigMatchArg msa;

  MATCH_ARG_INIT(msa, option, region, at, at);
#ifdef USE_COMBINATION_EXPLOSION_CHECK
  {
    ptrdiff_t offset = at - str;
    STATE_CHECK_BUFF_INIT(msa, end - str, offset, reg->num_comb_exp_check);
  }
#endif

  if (region) {
    r = onig_region_resize_clear(region, reg->num_mem + 1);
  }
  else
    r = 0;

  if (r == 0) {
    prev = (UChar* )onigenc_get_prev_char_head(reg->enc, str, at, end);
    r = match_at(reg, str, end,
#ifdef USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE
		 end,
#endif
		 at, prev, &msa);
  }

  MATCH_ARG_FREE(msa);
  return r;
}

static int
forward_search_range(regex_t* reg, const UChar* str, const UChar* end, UChar* s,
		     UChar* range, UChar** low, UChar** high, UChar** low_prev)
{
  UChar *p, *pprev = (UChar* )NULL;
  size_t input_len = end - str;

#ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "forward_search_range: str: %"PRIuPTR" (%p), end: %"PRIuPTR" (%p), s: %"PRIuPTR" (%p), range: %"PRIuPTR" (%p)\n",
	  (uintptr_t )str, str, (uintptr_t )end, end, (uintptr_t )s, s, (uintptr_t )range, range);
#endif

  if (reg->dmin > input_len) {
    return 0;
  }

  p = s;
  if (reg->dmin != 0) {
    if (end - p <= reg->dmin) return 0; /* fail */
    if (ONIGENC_IS_SINGLEBYTE(reg->enc)) {
      p += reg->dmin;
    }
    else {
      UChar *q = p + reg->dmin;

      while (p < q) p += enclen(reg->enc, p, end);
    }
  }

 retry:
  switch (reg->optimize) {
  case ONIG_OPTIMIZE_EXACT:
    p = slow_search(reg->enc, reg->exact, reg->exact_end, p, end, range);
    break;
  case ONIG_OPTIMIZE_EXACT_IC:
    p = slow_search_ic(reg->enc, reg->case_fold_flag,
		       reg->exact, reg->exact_end, p, end, range);
    break;

  case ONIG_OPTIMIZE_EXACT_BM:
    p = bm_search(reg, reg->exact, reg->exact_end, p, end, range);
    break;

  case ONIG_OPTIMIZE_EXACT_BM_NOT_REV:
    p = bm_search_notrev(reg, reg->exact, reg->exact_end, p, end, range);
    break;

  case ONIG_OPTIMIZE_EXACT_BM_IC:
    p = bm_search_ic(reg, reg->exact, reg->exact_end, p, end, range);
    break;

  case ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC:
    p = bm_search_notrev_ic(reg, reg->exact, reg->exact_end, p, end, range);
    break;

  case ONIG_OPTIMIZE_MAP:
    p = map_search(reg->enc, reg->map, p, range, end);
    break;
  }

  if (p && p < range) {
    if (p - s < reg->dmin) {
    retry_gate:
      pprev = p;
      p += enclen(reg->enc, p, end);
      goto retry;
    }

    if (reg->sub_anchor) {
      UChar* prev;

      switch (reg->sub_anchor) {
      case ANCHOR_BEGIN_LINE:
	if (!ON_STR_BEGIN(p)) {
	  prev = onigenc_get_prev_char_head(reg->enc,
					    (pprev ? pprev : str), p, end);
	  if (!ONIGENC_IS_MBC_NEWLINE_EX(reg->enc, prev, str, end, reg->options, 0))
	    goto retry_gate;
	}
	break;

      case ANCHOR_END_LINE:
	if (ON_STR_END(p)) {
#ifndef USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE
	  prev = (UChar* )onigenc_get_prev_char_head(reg->enc,
					    (pprev ? pprev : str), p);
	  if (prev && ONIGENC_IS_MBC_NEWLINE_EX(reg->enc, prev, str, end, reg->options, 1))
	    goto retry_gate;
#endif
	}
	else if (! ONIGENC_IS_MBC_NEWLINE_EX(reg->enc, p, str, end, reg->options, 1))
	  goto retry_gate;
	break;
      }
    }

    if (reg->dmax == 0) {
      *low = p;
      if (low_prev) {
	if (*low > s)
	  *low_prev = onigenc_get_prev_char_head(reg->enc, s, p, end);
	else
	  *low_prev = onigenc_get_prev_char_head(reg->enc,
						 (pprev ? pprev : str), p, end);
      }
      *high = p;
    }
    else {
      if (reg->dmax != ONIG_INFINITE_DISTANCE) {
	if (p - str < reg->dmax) {
	  *low = (UChar* )str;
	  if (low_prev)
	    *low_prev = onigenc_get_prev_char_head(reg->enc, str, *low, end);
	}
	else {
	  *low = p - reg->dmax;
	  if (*low > s) {
	    *low = onigenc_get_right_adjust_char_head_with_prev(reg->enc, s,
								*low, end, (const UChar** )low_prev);
	    if (low_prev && IS_NULL(*low_prev))
	      *low_prev = onigenc_get_prev_char_head(reg->enc,
						     (pprev ? pprev : s), *low, end);
	  }
	  else {
	    if (low_prev)
	      *low_prev = onigenc_get_prev_char_head(reg->enc,
						 (pprev ? pprev : str), *low, end);
	  }
	}
      }
      /* no needs to adjust *high, *high is used as range check only */
      if (p - str < reg->dmin)
        *high = (UChar* )str;
      else
        *high = p - reg->dmin;
    }

#ifdef ONIG_DEBUG_SEARCH
    fprintf(stderr,
    "forward_search_range success: low: %"PRIdPTR", high: %"PRIdPTR", dmin: %"PRIdPTR", dmax: %"PRIdPTR"\n",
	    *low - str, *high - str, reg->dmin, reg->dmax);
#endif
    return 1; /* success */
  }

  return 0; /* fail */
}

#define BM_BACKWARD_SEARCH_LENGTH_THRESHOLD   100

static int
backward_search_range(regex_t* reg, const UChar* str, const UChar* end,
		      UChar* s, const UChar* range, UChar* adjrange,
		      UChar** low, UChar** high)
{
  UChar *p;
  size_t input_len = end - str;

  if (reg->dmin > input_len) {
    return 0;
  }

  p = s;

 retry:
  switch (reg->optimize) {
  case ONIG_OPTIMIZE_EXACT:
  exact_method:
    p = slow_search_backward(reg->enc, reg->exact, reg->exact_end,
			     range, adjrange, end, p);
    break;

  case ONIG_OPTIMIZE_EXACT_IC:
  case ONIG_OPTIMIZE_EXACT_BM_IC:
  case ONIG_OPTIMIZE_EXACT_BM_NOT_REV_IC:
    p = slow_search_backward_ic(reg->enc, reg->case_fold_flag,
				reg->exact, reg->exact_end,
				range, adjrange, end, p);
    break;

  case ONIG_OPTIMIZE_EXACT_BM:
  case ONIG_OPTIMIZE_EXACT_BM_NOT_REV:
#ifdef USE_INT_MAP_BACKWARD
    if (IS_NULL(reg->int_map_backward)) {
      int r;
      if (s - range < BM_BACKWARD_SEARCH_LENGTH_THRESHOLD)
	goto exact_method;

      r = set_bm_backward_skip(reg->exact, reg->exact_end, reg->enc,
			       &(reg->int_map_backward));
      if (r) return r;
    }
    p = bm_search_backward(reg, reg->exact, reg->exact_end, range, adjrange,
			   end, p);
#else
    goto exact_method;
#endif
    break;

  case ONIG_OPTIMIZE_MAP:
    p = map_search_backward(reg->enc, reg->map, range, adjrange, p, end);
    break;
  }

  if (p) {
    if (reg->sub_anchor) {
      UChar* prev;

      switch (reg->sub_anchor) {
      case ANCHOR_BEGIN_LINE:
	if (!ON_STR_BEGIN(p)) {
	  prev = onigenc_get_prev_char_head(reg->enc, str, p, end);
	  if (!ONIGENC_IS_MBC_NEWLINE_EX(reg->enc, prev, str, end, reg->options, 0)) {
	    p = prev;
	    goto retry;
	  }
	}
	break;

      case ANCHOR_END_LINE:
	if (ON_STR_END(p)) {
#ifndef USE_NEWLINE_AT_END_OF_STRING_HAS_EMPTY_LINE
	  prev = onigenc_get_prev_char_head(reg->enc, adjrange, p);
	  if (IS_NULL(prev)) goto fail;
	  if (ONIGENC_IS_MBC_NEWLINE_EX(reg->enc, prev, str, end, reg->options, 1)) {
	    p = prev;
	    goto retry;
	  }
#endif
	}
	else if (! ONIGENC_IS_MBC_NEWLINE_EX(reg->enc, p, str, end, reg->options, 1)) {
	  p = onigenc_get_prev_char_head(reg->enc, adjrange, p, end);
	  if (IS_NULL(p)) goto fail;
	  goto retry;
	}
	break;
      }
    }

    if (reg->dmax != ONIG_INFINITE_DISTANCE) {
      if (p - str < reg->dmax)
	*low = (UChar* )str;
      else
	*low = p - reg->dmax;

      if (reg->dmin != 0) {
	if (p - str < reg->dmin)
	  *high = (UChar* )str;
	else
	  *high = p - reg->dmin;
      }
      else {
	*high = p;
      }

      *high = onigenc_get_right_adjust_char_head(reg->enc, adjrange, *high, end);
    }

#ifdef ONIG_DEBUG_SEARCH
    fprintf(stderr, "backward_search_range: low: %d, high: %d\n",
	    (int )(*low - str), (int )(*high - str));
#endif
    return 1; /* success */
  }

 fail:
#ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "backward_search_range: fail.\n");
#endif
  return 0; /* fail */
}


extern OnigPosition
onig_search(regex_t* reg, const UChar* str, const UChar* end,
	    const UChar* start, const UChar* range, OnigRegion* region, OnigOptionType option)
{
  return onig_search_gpos(reg, str, end, start, start, range, region, option);
}

extern OnigPosition
onig_search_gpos(regex_t* reg, const UChar* str, const UChar* end,
	    const UChar* global_pos,
	    const UChar* start, const UChar* range, OnigRegion* region, OnigOptionType option)
{
  ptrdiff_t r;
  UChar *s, *prev;
  OnigMatchArg msa;
#ifdef USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE
  const UChar *orig_start = start;
  const UChar *orig_range = range;
#endif

#ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr,
     "onig_search (entry point): str: %"PRIuPTR" (%p), end: %"PRIuPTR", start: %"PRIuPTR", range: %"PRIuPTR"\n",
     (uintptr_t )str, str, end - str, start - str, range - str);
#endif

  if (region) {
    r = onig_region_resize_clear(region, reg->num_mem + 1);
    if (r) goto finish_no_msa;
  }

  if (start > end || start < str) goto mismatch_no_msa;


#ifdef USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE
# ifdef USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE
#  define MATCH_AND_RETURN_CHECK(upper_range) \
  r = match_at(reg, str, end, (upper_range), s, prev, &msa); \
  switch (r) { \
    case ONIG_MISMATCH: \
      break; \
    case ONIGERR_TIMEOUT: \
      goto timeout; \
    default: \
      if (r >= 0) { \
        if (! IS_FIND_LONGEST(reg->options)) { \
          goto match; \
        }\
      }\
      else goto finish; /* error */ \
  }
# else
#  define MATCH_AND_RETURN_CHECK(upper_range) \
  r = match_at(reg, str, end, (upper_range), s, prev, &msa); \
  switch (r) { \
    case ONIG_MISMATCH: \
      break; \
    case ONIGERR_TIMEOUT: \
      goto timeout; \
    default: \
      if (r >= 0) { \
        goto match; \
      }\
      else goto finish; /* error */ \
  }
# endif /* USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE */
#else
# ifdef USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE
#  define MATCH_AND_RETURN_CHECK(none) \
  r = match_at(reg, str, end, s, prev, &msa);\
  switch (r) { \
    case ONIG_MISMATCH: \
      break; \
    case ONIGERR_TIMEOUT: \
      goto timeout; \
    default: \
      if (r >= 0) { \
        if (! IS_FIND_LONGEST(reg->options)) { \
          goto match; \
        } \
      } \
      else goto finish; /* error */ \
  }
# else
#  define MATCH_AND_RETURN_CHECK(none) \
  r = match_at(reg, str, end, s, prev, &msa);\
  switch (r) { \
    case ONIG_MISMATCH: \
      break; \
    case ONIGERR_TIMEOUT: \
      goto timeout; \
    default: \
    if (r >= 0) { \
        goto match; \
      } \
      else goto finish; /* error */ \
  }
# endif /* USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE */
#endif /* USE_MATCH_RANGE_MUST_BE_INSIDE_OF_SPECIFIED_RANGE */


  /* anchor optimize: resume search range */
  if (reg->anchor != 0 && str < end) {
    UChar *min_semi_end, *max_semi_end;

    if (reg->anchor & ANCHOR_BEGIN_POSITION) {
      /* search start-position only */
    begin_position:
      if (range > start)
      {
	if (global_pos > start)
	{
	  if (global_pos < range)
	    range = global_pos + 1;
	}
	else
	  range = start + 1;
      }
      else
	range = start;
    }
    else if (reg->anchor & ANCHOR_BEGIN_BUF) {
      /* search str-position only */
      if (range > start) {
	if (start != str) goto mismatch_no_msa;
	range = str + 1;
      }
      else {
	if (range <= str) {
	  start = str;
	  range = str;
	}
	else
	  goto mismatch_no_msa;
      }
    }
    else if (reg->anchor & ANCHOR_END_BUF) {
      min_semi_end = max_semi_end = (UChar* )end;

    end_buf:
      if ((OnigDistance )(max_semi_end - str) < reg->anchor_dmin)
	goto mismatch_no_msa;

      if (range > start) {
	if ((OnigDistance )(min_semi_end - start) > reg->anchor_dmax) {
	  start = min_semi_end - reg->anchor_dmax;
	  if (start < end)
	    start = onigenc_get_right_adjust_char_head(reg->enc, str, start, end);
	}
	if ((OnigDistance )(max_semi_end - (range - 1)) < reg->anchor_dmin) {
	  range = max_semi_end - reg->anchor_dmin + 1;
	}

	if (start > range) goto mismatch_no_msa;
	/* If start == range, match with empty at end.
	   Backward search is used. */
      }
      else {
	if ((OnigDistance )(min_semi_end - range) > reg->anchor_dmax) {
	  range = min_semi_end - reg->anchor_dmax;
	}
	if ((OnigDistance )(max_semi_end - start) < reg->anchor_dmin) {
	  start = max_semi_end - reg->anchor_dmin;
	  start = ONIGENC_LEFT_ADJUST_CHAR_HEAD(reg->enc, str, start, end);
	}
	if (range > start) goto mismatch_no_msa;
      }
    }
    else if (reg->anchor & ANCHOR_SEMI_END_BUF) {
      UChar* pre_end = ONIGENC_STEP_BACK(reg->enc, str, end, end, 1);

      max_semi_end = (UChar* )end;
      if (ONIGENC_IS_MBC_NEWLINE(reg->enc, pre_end, end)) {
	min_semi_end = pre_end;

#ifdef USE_CRNL_AS_LINE_TERMINATOR
	pre_end = ONIGENC_STEP_BACK(reg->enc, str, pre_end, end, 1);
	if (IS_NOT_NULL(pre_end) &&
	    IS_NEWLINE_CRLF(reg->options) &&
	    ONIGENC_IS_MBC_CRNL(reg->enc, pre_end, end)) {
	  min_semi_end = pre_end;
	}
#endif
	if (min_semi_end > str && start <= min_semi_end) {
	  goto end_buf;
	}
      }
      else {
	min_semi_end = (UChar* )end;
	goto end_buf;
      }
    }
    else if ((reg->anchor & ANCHOR_ANYCHAR_STAR_ML)) {
      goto begin_position;
    }
  }
  else if (str == end) { /* empty string */
    static const UChar address_for_empty_string[] = "";

#ifdef ONIG_DEBUG_SEARCH
    fprintf(stderr, "onig_search: empty string.\n");
#endif

    if (reg->threshold_len == 0) {
      start = end = str = address_for_empty_string;
      s = (UChar* )start;
      prev = (UChar* )NULL;

      MATCH_ARG_INIT(msa, option, region, start, start);
#ifdef USE_COMBINATION_EXPLOSION_CHECK
      msa.state_check_buff = (void* )0;
      msa.state_check_buff_size = 0;   /* NO NEED, for valgrind */
#endif
      MATCH_AND_RETURN_CHECK(end);
      goto mismatch;
    }
    goto mismatch_no_msa;
  }

#ifdef ONIG_DEBUG_SEARCH
  fprintf(stderr, "onig_search(apply anchor): end: %d, start: %d, range: %d\n",
	  (int )(end - str), (int )(start - str), (int )(range - str));
#endif

  MATCH_ARG_INIT(msa, option, region, start, global_pos);
#ifdef USE_COMBINATION_EXPLOSION_CHECK
  {
    ptrdiff_t offset = (MIN(start, range) - str);
    STATE_CHECK_BUFF_INIT(msa, end - str, offset, reg->num_comb_exp_check);
  }
#endif

  s = (UChar* )start;
  if (range > start) {   /* forward search */
    if (s > str)
      prev = onigenc_get_prev_char_head(reg->enc, str, s, end);
    else
      prev = (UChar* )NULL;

    if (reg->optimize != ONIG_OPTIMIZE_NONE) {
      UChar *sch_range, *low, *high, *low_prev;

      sch_range = (UChar* )range;
      if (reg->dmax != 0) {
	if (reg->dmax == ONIG_INFINITE_DISTANCE)
	  sch_range = (UChar* )end;
	else {
	  sch_range += reg->dmax;
	  if (sch_range > end) sch_range = (UChar* )end;
	}
      }

      if ((end - start) < reg->threshold_len)
	goto mismatch;

      if (reg->dmax != ONIG_INFINITE_DISTANCE) {
	do {
	  if (! forward_search_range(reg, str, end, s, sch_range,
				     &low, &high, &low_prev)) goto mismatch;
	  if (s < low) {
	    s    = low;
	    prev = low_prev;
	  }
	  while (s <= high) {
	    MATCH_AND_RETURN_CHECK(orig_range);
	    prev = s;
	    s += enclen(reg->enc, s, end);
	  }
	} while (s < range);
	goto mismatch;
      }
      else { /* check only. */
	if (! forward_search_range(reg, str, end, s, sch_range,
				   &low, &high, (UChar** )NULL)) goto mismatch;

	if ((reg->anchor & ANCHOR_ANYCHAR_STAR) != 0) {
	  do {
	    MATCH_AND_RETURN_CHECK(orig_range);
	    prev = s;
	    s += enclen(reg->enc, s, end);

	    if ((reg->anchor & (ANCHOR_LOOK_BEHIND | ANCHOR_PREC_READ_NOT)) == 0) {
	      while (!ONIGENC_IS_MBC_NEWLINE_EX(reg->enc, prev, str, end, reg->options, 0)
		  && s < range) {
		prev = s;
		s += enclen(reg->enc, s, end);
	      }
	    }
	  } while (s < range);
	  goto mismatch;
	}
      }
    }

    do {
      MATCH_AND_RETURN_CHECK(orig_range);
      prev = s;
      s += enclen(reg->enc, s, end);
    } while (s < range);

    if (s == range) { /* because empty match with /$/. */
      MATCH_AND_RETURN_CHECK(orig_range);
    }
  }
  else {  /* backward search */
    if (reg->optimize != ONIG_OPTIMIZE_NONE) {
      UChar *low, *high, *adjrange, *sch_start;
      const UChar *min_range;

      if (range < end)
	adjrange = ONIGENC_LEFT_ADJUST_CHAR_HEAD(reg->enc, str, range, end);
      else
	adjrange = (UChar* )end;

      if (end - range > reg->dmin)
	min_range = range + reg->dmin;
      else
	min_range = end;

      if (reg->dmax != ONIG_INFINITE_DISTANCE &&
	  (end - range) >= reg->threshold_len) {
	do {
	  sch_start = s + reg->dmax;
	  if (sch_start > end) sch_start = (UChar* )end;
	  if (backward_search_range(reg, str, end, sch_start, min_range, adjrange,
				    &low, &high) <= 0)
	    goto mismatch;

	  if (s > high)
	    s = high;

	  while (s >= low) {
	    prev = onigenc_get_prev_char_head(reg->enc, str, s, end);
	    MATCH_AND_RETURN_CHECK(orig_start);
	    s = prev;
	  }
	} while (s >= range);
	goto mismatch;
      }
      else { /* check only. */
	if ((end - range) < reg->threshold_len) goto mismatch;

	sch_start = s;
	if (reg->dmax != 0) {
	  if (reg->dmax == ONIG_INFINITE_DISTANCE)
	    sch_start = (UChar* )end;
	  else {
	    sch_start += reg->dmax;
	    if (sch_start > end) sch_start = (UChar* )end;
	    else
	      sch_start = ONIGENC_LEFT_ADJUST_CHAR_HEAD(reg->enc,
						    start, sch_start, end);
	  }
	}
	if (backward_search_range(reg, str, end, sch_start, min_range, adjrange,
				  &low, &high) <= 0) goto mismatch;
      }
    }

    do {
      prev = onigenc_get_prev_char_head(reg->enc, str, s, end);
      MATCH_AND_RETURN_CHECK(orig_start);
      s = prev;
    } while (s >= range);
  }

 mismatch:
#ifdef USE_FIND_LONGEST_SEARCH_ALL_OF_RANGE
  if (IS_FIND_LONGEST(reg->options)) {
    if (msa.best_len >= 0) {
      s = msa.best_s;
      goto match;
    }
  }
#endif
  r = ONIG_MISMATCH;

 finish:
  MATCH_ARG_FREE(msa);

  /* If result is mismatch and no FIND_NOT_EMPTY option,
     then the region is not set in match_at(). */
  if (IS_FIND_NOT_EMPTY(reg->options) && region) {
    onig_region_clear(region);
  }

#ifdef ONIG_DEBUG
  if (r != ONIG_MISMATCH)
    fprintf(stderr, "onig_search: error %"PRIdPTRDIFF"\n", r);
#endif
  return r;

 mismatch_no_msa:
  r = ONIG_MISMATCH;
 finish_no_msa:
#ifdef ONIG_DEBUG
  if (r != ONIG_MISMATCH)
    fprintf(stderr, "onig_search: error %"PRIdPTRDIFF"\n", r);
#endif
  return r;

 match:
  MATCH_ARG_FREE(msa);
  return s - str;

timeout:
  MATCH_ARG_FREE(msa);
  return ONIGERR_TIMEOUT;
}

extern OnigPosition
onig_scan(regex_t* reg, const UChar* str, const UChar* end,
	  OnigRegion* region, OnigOptionType option,
	  int (*scan_callback)(OnigPosition, OnigPosition, OnigRegion*, void*),
	  void* callback_arg)
{
  OnigPosition r;
  OnigPosition n;
  int rs;
  const UChar* start;

  n = 0;
  start = str;
  while (1) {
    r = onig_search(reg, str, end, start, end, region, option);
    if (r >= 0) {
      rs = scan_callback(n, r, region, callback_arg);
      n++;
      if (rs != 0)
	return rs;

      if (region->end[0] == start - str) {
	if (start >= end) break;
	start += enclen(reg->enc, start, end);
      }
      else
	start = str + region->end[0];

      if (start > end)
	break;
    }
    else if (r == ONIG_MISMATCH) {
      break;
    }
    else { /* error */
      return r;
    }
  }

  return n;
}

extern OnigEncoding
onig_get_encoding(const regex_t* reg)
{
  return reg->enc;
}

extern OnigOptionType
onig_get_options(const regex_t* reg)
{
  return reg->options;
}

extern  OnigCaseFoldType
onig_get_case_fold_flag(const regex_t* reg)
{
  return reg->case_fold_flag;
}

extern const OnigSyntaxType*
onig_get_syntax(const regex_t* reg)
{
  return reg->syntax;
}

extern int
onig_number_of_captures(const regex_t* reg)
{
  return reg->num_mem;
}

extern int
onig_number_of_capture_histories(const regex_t* reg)
{
#ifdef USE_CAPTURE_HISTORY
  int i, n;

  n = 0;
  for (i = 0; i <= ONIG_MAX_CAPTURE_HISTORY_GROUP; i++) {
    if (BIT_STATUS_AT(reg->capture_history, i) != 0)
      n++;
  }
  return n;
#else
  return 0;
#endif
}

extern void
onig_copy_encoding(OnigEncodingType *to, OnigEncoding from)
{
  *to = *from;
}
