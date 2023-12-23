/**********************************************************************

  parse.y -

  $Author$
  created at: Fri May 28 18:02:42 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

%require "3.0"

%{

#if !YYPURE
# error needs pure parser
#endif
#define YYDEBUG 1
#define YYERROR_VERBOSE 1
#define YYSTACK_USE_ALLOCA 0
#define YYLTYPE rb_code_location_t
#define YYLTYPE_IS_DECLARED 1

/* For Ripper */
#ifdef RUBY_EXTCONF_H
# include RUBY_EXTCONF_H
#endif

#include "ruby/internal/config.h"

#include <errno.h>

#ifdef UNIVERSAL_PARSER

#include "internal/ruby_parser.h"
#include "parser_node.h"
#include "universal_parser.c"

#ifdef RIPPER
#undef T_NODE
#define T_NODE 0x1b
#define STATIC_ID2SYM p->config->static_id2sym
#define rb_str_coderange_scan_restartable p->config->str_coderange_scan_restartable
#endif

#else

#include "internal.h"
#include "internal/compile.h"
#include "internal/compilers.h"
#include "internal/complex.h"
#include "internal/encoding.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/imemo.h"
#include "internal/io.h"
#include "internal/numeric.h"
#include "internal/parse.h"
#include "internal/rational.h"
#include "internal/re.h"
#include "internal/ruby_parser.h"
#include "internal/symbol.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "node.h"
#include "parser_node.h"
#include "probes.h"
#include "regenc.h"
#include "ruby/encoding.h"
#include "ruby/regex.h"
#include "ruby/ruby.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby/ractor.h"
#include "symbol.h"

#ifndef RIPPER
static void
bignum_negate(VALUE b)
{
    BIGNUM_NEGATE(b);
}

static void
rational_set_num(VALUE r, VALUE n)
{
    RATIONAL_SET_NUM(r, n);
}

static VALUE
rational_get_num(VALUE obj)
{
    return RRATIONAL(obj)->num;
}

static void
rcomplex_set_real(VALUE cmp, VALUE r)
{
    RCOMPLEX_SET_REAL(cmp, r);
}

static VALUE
rcomplex_get_real(VALUE obj)
{
    return RCOMPLEX(obj)->real;
}

static void
rcomplex_set_imag(VALUE cmp, VALUE i)
{
    RCOMPLEX_SET_IMAG(cmp, i);
}

static VALUE
rcomplex_get_imag(VALUE obj)
{
    return RCOMPLEX(obj)->imag;
}

static bool
hash_literal_key_p(VALUE k)
{
    switch (OBJ_BUILTIN_TYPE(k)) {
      case T_NODE:
        return false;
      default:
        return true;
    }
}

static int
literal_cmp(VALUE val, VALUE lit)
{
    if (val == lit) return 0;
    if (!hash_literal_key_p(val) || !hash_literal_key_p(lit)) return -1;
    return rb_iseq_cdhash_cmp(val, lit);
}

static st_index_t
literal_hash(VALUE a)
{
    if (!hash_literal_key_p(a)) return (st_index_t)a;
    return rb_iseq_cdhash_hash(a);
}

static VALUE
syntax_error_new(void)
{
    return rb_class_new_instance(0, 0, rb_eSyntaxError);
}

static NODE *reg_named_capture_assign(struct parser_params* p, VALUE regexp, const YYLTYPE *loc);
#endif /* !RIPPER */

#define compile_callback rb_suppress_tracing
VALUE rb_io_gets_internal(VALUE io);

VALUE rb_node_case_when_optimizable_literal(const NODE *const node);
#endif /* !UNIVERSAL_PARSER */

static inline int
parse_isascii(int c)
{
    return '\0' <= c && c <= '\x7f';
}

#undef ISASCII
#define ISASCII parse_isascii

static inline int
parse_isspace(int c)
{
    return c == ' ' || ('\t' <= c && c <= '\r');
}

#undef ISSPACE
#define ISSPACE parse_isspace

static inline int
parse_iscntrl(int c)
{
    return ('\0' <= c && c < ' ') || c == '\x7f';
}

#undef ISCNTRL
#define ISCNTRL(c) parse_iscntrl(c)

static inline int
parse_isupper(int c)
{
    return 'A' <= c && c <= 'Z';
}

static inline int
parse_islower(int c)
{
    return 'a' <= c && c <= 'z';
}

static inline int
parse_isalpha(int c)
{
    return parse_isupper(c) || parse_islower(c);
}

#undef ISALPHA
#define ISALPHA(c) parse_isalpha(c)

static inline int
parse_isdigit(int c)
{
    return '0' <= c && c <= '9';
}

#undef ISDIGIT
#define ISDIGIT(c) parse_isdigit(c)

static inline int
parse_isalnum(int c)
{
    return parse_isalpha(c) || parse_isdigit(c);
}

#undef ISALNUM
#define ISALNUM(c) parse_isalnum(c)

static inline int
parse_isxdigit(int c)
{
    return parse_isdigit(c) || ('A' <= c && c <= 'F') || ('a' <= c && c <= 'f');
}

#undef ISXDIGIT
#define ISXDIGIT(c) parse_isxdigit(c)

#include "parser_st.h"

#undef STRCASECMP
#define STRCASECMP rb_parser_st_locale_insensitive_strcasecmp

#undef STRNCASECMP
#define STRNCASECMP rb_parser_st_locale_insensitive_strncasecmp

#ifdef RIPPER
#include "ripper_init.h"
#endif

enum shareability {
    shareable_none,
    shareable_literal,
    shareable_copy,
    shareable_everything,
};

enum rescue_context {
    before_rescue,
    after_rescue,
    after_else,
    after_ensure,
};

struct lex_context {
    unsigned int in_defined: 1;
    unsigned int in_kwarg: 1;
    unsigned int in_argdef: 1;
    unsigned int in_def: 1;
    unsigned int in_class: 1;
    BITFIELD(enum shareability, shareable_constant_value, 2);
    BITFIELD(enum rescue_context, in_rescue, 2);
};

typedef struct RNode_DEF_TEMP rb_node_def_temp_t;
typedef struct RNode_EXITS rb_node_exits_t;

#if defined(__GNUC__) && !defined(__clang__)
// Suppress "parameter passing for argument of type 'struct
// lex_context' changed" notes.  `struct lex_context` is file scope,
// and has no ABI compatibility issue.
RBIMPL_WARNING_PUSH()
RBIMPL_WARNING_IGNORED(-Wpsabi)
RBIMPL_WARNING_POP()
// Not sure why effective even after popped.
#endif

#include "parse.h"

#define NO_LEX_CTXT (struct lex_context){0}

#define AREF(ary, i) RARRAY_AREF(ary, i)

#ifndef WARN_PAST_SCOPE
# define WARN_PAST_SCOPE 0
#endif

#define TAB_WIDTH 8

#define yydebug (p->debug)	/* disable the global variable definition */

#define YYMALLOC(size)		rb_parser_malloc(p, (size))
#define YYREALLOC(ptr, size)	rb_parser_realloc(p, (ptr), (size))
#define YYCALLOC(nelem, size)	rb_parser_calloc(p, (nelem), (size))
#define YYFREE(ptr)		rb_parser_free(p, (ptr))
#define YYFPRINTF(out, ...)	rb_parser_printf(p, __VA_ARGS__)
#define YY_LOCATION_PRINT(File, loc, p) \
     rb_parser_printf(p, "%d.%d-%d.%d", \
                      (loc).beg_pos.lineno, (loc).beg_pos.column,\
                      (loc).end_pos.lineno, (loc).end_pos.column)
#define YYLLOC_DEFAULT(Current, Rhs, N)					\
    do									\
      if (N)								\
        {								\
          (Current).beg_pos = YYRHSLOC(Rhs, 1).beg_pos;			\
          (Current).end_pos = YYRHSLOC(Rhs, N).end_pos;			\
        }								\
      else								\
        {                                                               \
          (Current).beg_pos = YYRHSLOC(Rhs, 0).end_pos;                 \
          (Current).end_pos = YYRHSLOC(Rhs, 0).end_pos;                 \
        }                                                               \
    while (0)
#define YY_(Msgid) \
    (((Msgid)[0] == 'm') && (strcmp((Msgid), "memory exhausted") == 0) ? \
     "nesting too deep" : (Msgid))

#define RUBY_SET_YYLLOC_FROM_STRTERM_HEREDOC(Current)			\
    rb_parser_set_location_from_strterm_heredoc(p, &p->lex.strterm->u.heredoc, &(Current))
#define RUBY_SET_YYLLOC_OF_DELAYED_TOKEN(Current)			\
    rb_parser_set_location_of_delayed_token(p, &(Current))
#define RUBY_SET_YYLLOC_OF_HEREDOC_END(Current)				\
    rb_parser_set_location_of_heredoc_end(p, &(Current))
#define RUBY_SET_YYLLOC_OF_DUMMY_END(Current)				\
    rb_parser_set_location_of_dummy_end(p, &(Current))
#define RUBY_SET_YYLLOC_OF_NONE(Current)				\
    rb_parser_set_location_of_none(p, &(Current))
#define RUBY_SET_YYLLOC(Current)					\
    rb_parser_set_location(p, &(Current))
#define RUBY_INIT_YYLLOC() \
    { \
        {p->ruby_sourceline, (int)(p->lex.ptok - p->lex.pbeg)}, \
        {p->ruby_sourceline, (int)(p->lex.pcur - p->lex.pbeg)}, \
    }

#define IS_lex_state_for(x, ls)	((x) & (ls))
#define IS_lex_state_all_for(x, ls) (((x) & (ls)) == (ls))
#define IS_lex_state(ls)	IS_lex_state_for(p->lex.state, (ls))
#define IS_lex_state_all(ls)	IS_lex_state_all_for(p->lex.state, (ls))

# define SET_LEX_STATE(ls) \
    parser_set_lex_state(p, ls, __LINE__)
static inline enum lex_state_e parser_set_lex_state(struct parser_params *p, enum lex_state_e ls, int line);

typedef VALUE stack_type;

static const rb_code_location_t NULL_LOC = { {0, -1}, {0, -1} };

# define SHOW_BITSTACK(stack, name) (p->debug ? rb_parser_show_bitstack(p, stack, name, __LINE__) : (void)0)
# define BITSTACK_PUSH(stack, n) (((p->stack) = ((p->stack)<<1)|((n)&1)), SHOW_BITSTACK(p->stack, #stack"(push)"))
# define BITSTACK_POP(stack)	 (((p->stack) = (p->stack) >> 1), SHOW_BITSTACK(p->stack, #stack"(pop)"))
# define BITSTACK_SET_P(stack)	 (SHOW_BITSTACK(p->stack, #stack), (p->stack)&1)
# define BITSTACK_SET(stack, n)	 ((p->stack)=(n), SHOW_BITSTACK(p->stack, #stack"(set)"))

/* A flag to identify keyword_do_cond, "do" keyword after condition expression.
   Examples: `while ... do`, `until ... do`, and `for ... in ... do` */
#define COND_PUSH(n)	BITSTACK_PUSH(cond_stack, (n))
#define COND_POP()	BITSTACK_POP(cond_stack)
#define COND_P()	BITSTACK_SET_P(cond_stack)
#define COND_SET(n)	BITSTACK_SET(cond_stack, (n))

/* A flag to identify keyword_do_block; "do" keyword after command_call.
   Example: `foo 1, 2 do`. */
#define CMDARG_PUSH(n)	BITSTACK_PUSH(cmdarg_stack, (n))
#define CMDARG_POP()	BITSTACK_POP(cmdarg_stack)
#define CMDARG_P()	BITSTACK_SET_P(cmdarg_stack)
#define CMDARG_SET(n)	BITSTACK_SET(cmdarg_stack, (n))

struct vtable {
    ID *tbl;
    int pos;
    int capa;
    struct vtable *prev;
};

struct local_vars {
    struct vtable *args;
    struct vtable *vars;
    struct vtable *used;
# if WARN_PAST_SCOPE
    struct vtable *past;
# endif
    struct local_vars *prev;
# ifndef RIPPER
    struct {
        NODE *outer, *inner, *current;
    } numparam;
# endif
};

enum {
    ORDINAL_PARAM = -1,
    NO_PARAM = 0,
    NUMPARAM_MAX = 9,
};

#define DVARS_INHERIT ((void*)1)
#define DVARS_TOPSCOPE NULL
#define DVARS_TERMINAL_P(tbl) ((tbl) == DVARS_INHERIT || (tbl) == DVARS_TOPSCOPE)

typedef struct token_info {
    const char *token;
    rb_code_position_t beg;
    int indent;
    int nonspc;
    struct token_info *next;
} token_info;

/*
    Structure of Lexer Buffer:

 lex.pbeg     lex.ptok     lex.pcur     lex.pend
    |            |            |            |
    |------------+------------+------------|
                 |<---------->|
                     token
*/
struct parser_params {
    rb_imemo_tmpbuf_t *heap;

    YYSTYPE *lval;
    YYLTYPE *yylloc;

    struct {
        rb_strterm_t *strterm;
        VALUE (*gets)(struct parser_params*,VALUE);
        VALUE input;
        VALUE lastline;
        VALUE nextline;
        const char *pbeg;
        const char *pcur;
        const char *pend;
        const char *ptok;
        union {
            long ptr;
            VALUE (*call)(VALUE, int);
        } gets_;
        enum lex_state_e state;
        /* track the nest level of any parens "()[]{}" */
        int paren_nest;
        /* keep p->lex.paren_nest at the beginning of lambda "->" to detect tLAMBEG and keyword_do_LAMBDA */
        int lpar_beg;
        /* track the nest level of only braces "{}" */
        int brace_nest;
    } lex;
    stack_type cond_stack;
    stack_type cmdarg_stack;
    int tokidx;
    int toksiz;
    int heredoc_end;
    int heredoc_indent;
    int heredoc_line_indent;
    char *tokenbuf;
    struct local_vars *lvtbl;
    st_table *pvtbl;
    st_table *pktbl;
    int line_count;
    int ruby_sourceline;	/* current line no. */
    const char *ruby_sourcefile; /* current source file */
    VALUE ruby_sourcefile_string;
    rb_encoding *enc;
    token_info *token_info;
    VALUE case_labels;
    rb_node_exits_t *exits;

    VALUE debug_buffer;
    VALUE debug_output;

    struct {
        VALUE token;
        int beg_line;
        int beg_col;
        int end_line;
        int end_col;
    } delayed;

    ID cur_arg;

    rb_ast_t *ast;
    int node_id;

    int max_numparam;

    struct lex_context ctxt;

#ifdef UNIVERSAL_PARSER
    rb_parser_config_t *config;
#endif
    /* compile_option */
    signed int frozen_string_literal:2; /* -1: not specified, 0: false, 1: true */

    unsigned int command_start:1;
    unsigned int eofp: 1;
    unsigned int ruby__end__seen: 1;
    unsigned int debug: 1;
    unsigned int has_shebang: 1;
    unsigned int token_seen: 1;
    unsigned int token_info_enabled: 1;
# if WARN_PAST_SCOPE
    unsigned int past_scope_enabled: 1;
# endif
    unsigned int error_p: 1;
    unsigned int cr_seen: 1;

#ifndef RIPPER
    /* Ruby core only */

    unsigned int do_print: 1;
    unsigned int do_loop: 1;
    unsigned int do_chomp: 1;
    unsigned int do_split: 1;
    unsigned int error_tolerant: 1;
    unsigned int keep_tokens: 1;

    NODE *eval_tree_begin;
    NODE *eval_tree;
    VALUE error_buffer;
    VALUE debug_lines;
    const struct rb_iseq_struct *parent_iseq;
    /* store specific keyword locations to generate dummy end token */
    VALUE end_expect_token_locations;
    /* id for terms */
    int token_id;
    /* Array for term tokens */
    VALUE tokens;
#else
    /* Ripper only */

    VALUE value;
    VALUE result;
    VALUE parsing_thread;
#endif
};

#define NUMPARAM_ID_P(id) numparam_id_p(p, id)
#define NUMPARAM_ID_TO_IDX(id) (unsigned int)(((id) >> ID_SCOPE_SHIFT) - (tNUMPARAM_1 - 1))
#define NUMPARAM_IDX_TO_ID(idx) TOKEN2LOCALID((tNUMPARAM_1 - 1 + (idx)))
static int
numparam_id_p(struct parser_params *p, ID id)
{
    if (!is_local_id(id) || id < (tNUMPARAM_1 << ID_SCOPE_SHIFT)) return 0;
    unsigned int idx = NUMPARAM_ID_TO_IDX(id);
    return idx > 0 && idx <= NUMPARAM_MAX;
}
static void numparam_name(struct parser_params *p, ID id);


#define intern_cstr(n,l,en) rb_intern3(n,l,en)

#define STR_NEW(ptr,len) rb_enc_str_new((ptr),(len),p->enc)
#define STR_NEW0() rb_enc_str_new(0,0,p->enc)
#define STR_NEW2(ptr) rb_enc_str_new((ptr),strlen(ptr),p->enc)
#define STR_NEW3(ptr,len,e,func) parser_str_new(p, (ptr),(len),(e),(func),p->enc)
#define TOK_INTERN() intern_cstr(tok(p), toklen(p), p->enc)
#define VALID_SYMNAME_P(s, l, enc, type) (rb_enc_symname_type(s, l, enc, (1U<<(type))) == (int)(type))

static inline bool
end_with_newline_p(struct parser_params *p, VALUE str)
{
    return RSTRING_LEN(str) > 0 && RSTRING_END(str)[-1] == '\n';
}

static void
pop_pvtbl(struct parser_params *p, st_table *tbl)
{
    st_free_table(p->pvtbl);
    p->pvtbl = tbl;
}

static void
pop_pktbl(struct parser_params *p, st_table *tbl)
{
    if (p->pktbl) st_free_table(p->pktbl);
    p->pktbl = tbl;
}

#ifndef RIPPER
static void flush_debug_buffer(struct parser_params *p, VALUE out, VALUE str);

static void
debug_end_expect_token_locations(struct parser_params *p, const char *name)
{
    if(p->debug) {
        VALUE mesg = rb_sprintf("%s: ", name);
        rb_str_catf(mesg, " %"PRIsVALUE"\n", p->end_expect_token_locations);
        flush_debug_buffer(p, p->debug_output, mesg);
    }
}

static void
push_end_expect_token_locations(struct parser_params *p, const rb_code_position_t *pos)
{
    if(NIL_P(p->end_expect_token_locations)) return;
    rb_ary_push(p->end_expect_token_locations, rb_ary_new_from_args(2, INT2NUM(pos->lineno), INT2NUM(pos->column)));
    debug_end_expect_token_locations(p, "push_end_expect_token_locations");
}

static void
pop_end_expect_token_locations(struct parser_params *p)
{
    if(NIL_P(p->end_expect_token_locations)) return;
    rb_ary_pop(p->end_expect_token_locations);
    debug_end_expect_token_locations(p, "pop_end_expect_token_locations");
}

static VALUE
peek_end_expect_token_locations(struct parser_params *p)
{
    if(NIL_P(p->end_expect_token_locations)) return Qnil;
    return rb_ary_last(0, 0, p->end_expect_token_locations);
}

static ID
parser_token2id(struct parser_params *p, enum yytokentype tok)
{
    switch ((int) tok) {
#define TOKEN2ID(tok) case tok: return rb_intern(#tok);
#define TOKEN2ID2(tok, name) case tok: return rb_intern(name);
      TOKEN2ID2(' ', "words_sep")
      TOKEN2ID2('!', "!")
      TOKEN2ID2('%', "%");
      TOKEN2ID2('&', "&");
      TOKEN2ID2('*', "*");
      TOKEN2ID2('+', "+");
      TOKEN2ID2('-', "-");
      TOKEN2ID2('/', "/");
      TOKEN2ID2('<', "<");
      TOKEN2ID2('=', "=");
      TOKEN2ID2('>', ">");
      TOKEN2ID2('?', "?");
      TOKEN2ID2('^', "^");
      TOKEN2ID2('|', "|");
      TOKEN2ID2('~', "~");
      TOKEN2ID2(':', ":");
      TOKEN2ID2(',', ",");
      TOKEN2ID2('.', ".");
      TOKEN2ID2(';', ";");
      TOKEN2ID2('`', "`");
      TOKEN2ID2('\n', "nl");
      TOKEN2ID2('{', "{");
      TOKEN2ID2('}', "}");
      TOKEN2ID2('[', "[");
      TOKEN2ID2(']', "]");
      TOKEN2ID2('(', "(");
      TOKEN2ID2(')', ")");
      TOKEN2ID2('\\', "backslash");
      TOKEN2ID(keyword_class);
      TOKEN2ID(keyword_module);
      TOKEN2ID(keyword_def);
      TOKEN2ID(keyword_undef);
      TOKEN2ID(keyword_begin);
      TOKEN2ID(keyword_rescue);
      TOKEN2ID(keyword_ensure);
      TOKEN2ID(keyword_end);
      TOKEN2ID(keyword_if);
      TOKEN2ID(keyword_unless);
      TOKEN2ID(keyword_then);
      TOKEN2ID(keyword_elsif);
      TOKEN2ID(keyword_else);
      TOKEN2ID(keyword_case);
      TOKEN2ID(keyword_when);
      TOKEN2ID(keyword_while);
      TOKEN2ID(keyword_until);
      TOKEN2ID(keyword_for);
      TOKEN2ID(keyword_break);
      TOKEN2ID(keyword_next);
      TOKEN2ID(keyword_redo);
      TOKEN2ID(keyword_retry);
      TOKEN2ID(keyword_in);
      TOKEN2ID(keyword_do);
      TOKEN2ID(keyword_do_cond);
      TOKEN2ID(keyword_do_block);
      TOKEN2ID(keyword_do_LAMBDA);
      TOKEN2ID(keyword_return);
      TOKEN2ID(keyword_yield);
      TOKEN2ID(keyword_super);
      TOKEN2ID(keyword_self);
      TOKEN2ID(keyword_nil);
      TOKEN2ID(keyword_true);
      TOKEN2ID(keyword_false);
      TOKEN2ID(keyword_and);
      TOKEN2ID(keyword_or);
      TOKEN2ID(keyword_not);
      TOKEN2ID(modifier_if);
      TOKEN2ID(modifier_unless);
      TOKEN2ID(modifier_while);
      TOKEN2ID(modifier_until);
      TOKEN2ID(modifier_rescue);
      TOKEN2ID(keyword_alias);
      TOKEN2ID(keyword_defined);
      TOKEN2ID(keyword_BEGIN);
      TOKEN2ID(keyword_END);
      TOKEN2ID(keyword__LINE__);
      TOKEN2ID(keyword__FILE__);
      TOKEN2ID(keyword__ENCODING__);
      TOKEN2ID(tIDENTIFIER);
      TOKEN2ID(tFID);
      TOKEN2ID(tGVAR);
      TOKEN2ID(tIVAR);
      TOKEN2ID(tCONSTANT);
      TOKEN2ID(tCVAR);
      TOKEN2ID(tLABEL);
      TOKEN2ID(tINTEGER);
      TOKEN2ID(tFLOAT);
      TOKEN2ID(tRATIONAL);
      TOKEN2ID(tIMAGINARY);
      TOKEN2ID(tCHAR);
      TOKEN2ID(tNTH_REF);
      TOKEN2ID(tBACK_REF);
      TOKEN2ID(tSTRING_CONTENT);
      TOKEN2ID(tREGEXP_END);
      TOKEN2ID(tDUMNY_END);
      TOKEN2ID(tSP);
      TOKEN2ID(tUPLUS);
      TOKEN2ID(tUMINUS);
      TOKEN2ID(tPOW);
      TOKEN2ID(tCMP);
      TOKEN2ID(tEQ);
      TOKEN2ID(tEQQ);
      TOKEN2ID(tNEQ);
      TOKEN2ID(tGEQ);
      TOKEN2ID(tLEQ);
      TOKEN2ID(tANDOP);
      TOKEN2ID(tOROP);
      TOKEN2ID(tMATCH);
      TOKEN2ID(tNMATCH);
      TOKEN2ID(tDOT2);
      TOKEN2ID(tDOT3);
      TOKEN2ID(tBDOT2);
      TOKEN2ID(tBDOT3);
      TOKEN2ID(tAREF);
      TOKEN2ID(tASET);
      TOKEN2ID(tLSHFT);
      TOKEN2ID(tRSHFT);
      TOKEN2ID(tANDDOT);
      TOKEN2ID(tCOLON2);
      TOKEN2ID(tCOLON3);
      TOKEN2ID(tOP_ASGN);
      TOKEN2ID(tASSOC);
      TOKEN2ID(tLPAREN);
      TOKEN2ID(tLPAREN_ARG);
      TOKEN2ID(tRPAREN);
      TOKEN2ID(tLBRACK);
      TOKEN2ID(tLBRACE);
      TOKEN2ID(tLBRACE_ARG);
      TOKEN2ID(tSTAR);
      TOKEN2ID(tDSTAR);
      TOKEN2ID(tAMPER);
      TOKEN2ID(tLAMBDA);
      TOKEN2ID(tSYMBEG);
      TOKEN2ID(tSTRING_BEG);
      TOKEN2ID(tXSTRING_BEG);
      TOKEN2ID(tREGEXP_BEG);
      TOKEN2ID(tWORDS_BEG);
      TOKEN2ID(tQWORDS_BEG);
      TOKEN2ID(tSYMBOLS_BEG);
      TOKEN2ID(tQSYMBOLS_BEG);
      TOKEN2ID(tSTRING_END);
      TOKEN2ID(tSTRING_DEND);
      TOKEN2ID(tSTRING_DBEG);
      TOKEN2ID(tSTRING_DVAR);
      TOKEN2ID(tLAMBEG);
      TOKEN2ID(tLABEL_END);
      TOKEN2ID(tIGNORED_NL);
      TOKEN2ID(tCOMMENT);
      TOKEN2ID(tEMBDOC_BEG);
      TOKEN2ID(tEMBDOC);
      TOKEN2ID(tEMBDOC_END);
      TOKEN2ID(tHEREDOC_BEG);
      TOKEN2ID(tHEREDOC_END);
      TOKEN2ID(k__END__);
      TOKEN2ID(tLOWEST);
      TOKEN2ID(tUMINUS_NUM);
      TOKEN2ID(tLAST_TOKEN);
#undef TOKEN2ID
#undef TOKEN2ID2
    }

    rb_bug("parser_token2id: unknown token %d", tok);

    UNREACHABLE_RETURN(0);
}

#endif

RBIMPL_ATTR_NONNULL((1, 2, 3))
static int parser_yyerror(struct parser_params*, const YYLTYPE *yylloc, const char*);
RBIMPL_ATTR_NONNULL((1, 2))
static int parser_yyerror0(struct parser_params*, const char*);
#define yyerror0(msg) parser_yyerror0(p, (msg))
#define yyerror1(loc, msg) parser_yyerror(p, (loc), (msg))
#define yyerror(yylloc, p, msg) parser_yyerror(p, yylloc, msg)
#define token_flush(ptr) ((ptr)->lex.ptok = (ptr)->lex.pcur)
#define lex_goto_eol(p) ((p)->lex.pcur = (p)->lex.pend)
#define lex_eol_p(p) lex_eol_n_p(p, 0)
#define lex_eol_n_p(p,n) lex_eol_ptr_n_p(p, (p)->lex.pcur, n)
#define lex_eol_ptr_p(p,ptr) lex_eol_ptr_n_p(p,ptr,0)
#define lex_eol_ptr_n_p(p,ptr,n) ((ptr)+(n) >= (p)->lex.pend)

static void token_info_setup(token_info *ptinfo, const char *ptr, const rb_code_location_t *loc);
static void token_info_push(struct parser_params*, const char *token, const rb_code_location_t *loc);
static void token_info_pop(struct parser_params*, const char *token, const rb_code_location_t *loc);
static void token_info_warn(struct parser_params *p, const char *token, token_info *ptinfo_beg, int same, const rb_code_location_t *loc);
static void token_info_drop(struct parser_params *p, const char *token, rb_code_position_t beg_pos);

#ifdef RIPPER
#define compile_for_eval	(0)
#else
#define compile_for_eval	(p->parent_iseq != 0)
#endif

#define token_column		((int)(p->lex.ptok - p->lex.pbeg))

#define CALL_Q_P(q) ((q) == TOKEN2VAL(tANDDOT))
#define NEW_QCALL(q,r,m,a,loc) (CALL_Q_P(q) ? NEW_QCALL0(r,m,a,loc) : NEW_CALL(r,m,a,loc))

#define lambda_beginning_p() (p->lex.lpar_beg == p->lex.paren_nest)

static enum yytokentype yylex(YYSTYPE*, YYLTYPE*, struct parser_params*);

#ifndef RIPPER
static inline void
rb_discard_node(struct parser_params *p, NODE *n)
{
    rb_ast_delete_node(p->ast, n);
}
#endif

#ifdef RIPPER
static inline VALUE
add_mark_object(struct parser_params *p, VALUE obj)
{
    if (!SPECIAL_CONST_P(obj)
        && !RB_TYPE_P(obj, T_NODE) /* Ripper jumbles NODE objects and other objects... */
    ) {
        rb_ast_add_mark_object(p->ast, obj);
    }
    return obj;
}

static rb_node_ripper_t *rb_node_ripper_new(struct parser_params *p, ID a, VALUE b, VALUE c, const YYLTYPE *loc);
static rb_node_ripper_values_t *rb_node_ripper_values_new(struct parser_params *p, VALUE a, VALUE b, VALUE c, const YYLTYPE *loc);
#define NEW_RIPPER(a,b,c,loc) (VALUE)rb_node_ripper_new(p,a,b,c,loc)
#define NEW_RIPPER_VALUES(a,b,c,loc) (VALUE)rb_node_ripper_values_new(p,a,b,c,loc)

#else
static rb_node_scope_t *rb_node_scope_new(struct parser_params *p, rb_node_args_t *nd_args, NODE *nd_body, const YYLTYPE *loc);
static rb_node_scope_t *rb_node_scope_new2(struct parser_params *p, rb_ast_id_table_t *nd_tbl, rb_node_args_t *nd_args, NODE *nd_body, const YYLTYPE *loc);
static rb_node_block_t *rb_node_block_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc);
static rb_node_if_t *rb_node_if_new(struct parser_params *p, NODE *nd_cond, NODE *nd_body, NODE *nd_else, const YYLTYPE *loc);
static rb_node_unless_t *rb_node_unless_new(struct parser_params *p, NODE *nd_cond, NODE *nd_body, NODE *nd_else, const YYLTYPE *loc);
static rb_node_case_t *rb_node_case_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, const YYLTYPE *loc);
static rb_node_case2_t *rb_node_case2_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc);
static rb_node_case3_t *rb_node_case3_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, const YYLTYPE *loc);
static rb_node_when_t *rb_node_when_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, NODE *nd_next, const YYLTYPE *loc);
static rb_node_in_t *rb_node_in_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, NODE *nd_next, const YYLTYPE *loc);
static rb_node_while_t *rb_node_while_new(struct parser_params *p, NODE *nd_cond, NODE *nd_body, long nd_state, const YYLTYPE *loc);
static rb_node_until_t *rb_node_until_new(struct parser_params *p, NODE *nd_cond, NODE *nd_body, long nd_state, const YYLTYPE *loc);
static rb_node_iter_t *rb_node_iter_new(struct parser_params *p, rb_node_args_t *nd_args, NODE *nd_body, const YYLTYPE *loc);
static rb_node_for_t *rb_node_for_new(struct parser_params *p, NODE *nd_iter, NODE *nd_body, const YYLTYPE *loc);
static rb_node_for_masgn_t *rb_node_for_masgn_new(struct parser_params *p, NODE *nd_var, const YYLTYPE *loc);
static rb_node_retry_t *rb_node_retry_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_begin_t *rb_node_begin_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc);
static rb_node_rescue_t *rb_node_rescue_new(struct parser_params *p, NODE *nd_head, NODE *nd_resq, NODE *nd_else, const YYLTYPE *loc);
static rb_node_resbody_t *rb_node_resbody_new(struct parser_params *p, NODE *nd_args, NODE *nd_body, NODE *nd_head, const YYLTYPE *loc);
static rb_node_ensure_t *rb_node_ensure_new(struct parser_params *p, NODE *nd_head, NODE *nd_ensr, const YYLTYPE *loc);
static rb_node_and_t *rb_node_and_new(struct parser_params *p, NODE *nd_1st, NODE *nd_2nd, const YYLTYPE *loc);
static rb_node_or_t *rb_node_or_new(struct parser_params *p, NODE *nd_1st, NODE *nd_2nd, const YYLTYPE *loc);
static rb_node_masgn_t *rb_node_masgn_new(struct parser_params *p, NODE *nd_head, NODE *nd_args, const YYLTYPE *loc);
static rb_node_lasgn_t *rb_node_lasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc);
static rb_node_dasgn_t *rb_node_dasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc);
static rb_node_gasgn_t *rb_node_gasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc);
static rb_node_iasgn_t *rb_node_iasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc);
static rb_node_cdecl_t *rb_node_cdecl_new(struct parser_params *p, ID nd_vid, NODE *nd_value, NODE *nd_else, const YYLTYPE *loc);
static rb_node_cvasgn_t *rb_node_cvasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc);
static rb_node_op_asgn1_t *rb_node_op_asgn1_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *index, NODE *rvalue, const YYLTYPE *loc);
static rb_node_op_asgn2_t *rb_node_op_asgn2_new(struct parser_params *p, NODE *nd_recv, NODE *nd_value, ID nd_vid, ID nd_mid, bool nd_aid, const YYLTYPE *loc);
static rb_node_op_asgn_or_t *rb_node_op_asgn_or_new(struct parser_params *p, NODE *nd_head, NODE *nd_value, const YYLTYPE *loc);
static rb_node_op_asgn_and_t *rb_node_op_asgn_and_new(struct parser_params *p, NODE *nd_head, NODE *nd_value, const YYLTYPE *loc);
static rb_node_op_cdecl_t *rb_node_op_cdecl_new(struct parser_params *p, NODE *nd_head, NODE *nd_value, ID nd_aid, const YYLTYPE *loc);
static rb_node_call_t *rb_node_call_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_args, const YYLTYPE *loc);
static rb_node_opcall_t *rb_node_opcall_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_args, const YYLTYPE *loc);
static rb_node_fcall_t *rb_node_fcall_new(struct parser_params *p, ID nd_mid, NODE *nd_args, const YYLTYPE *loc);
static rb_node_vcall_t *rb_node_vcall_new(struct parser_params *p, ID nd_mid, const YYLTYPE *loc);
static rb_node_qcall_t *rb_node_qcall_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_args, const YYLTYPE *loc);
static rb_node_super_t *rb_node_super_new(struct parser_params *p, NODE *nd_args, const YYLTYPE *loc);
static rb_node_zsuper_t * rb_node_zsuper_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_list_t *rb_node_list_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc);
static rb_node_list_t *rb_node_list_new2(struct parser_params *p, NODE *nd_head, long nd_alen, NODE *nd_next, const YYLTYPE *loc);
static rb_node_zlist_t *rb_node_zlist_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_hash_t *rb_node_hash_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc);
static rb_node_return_t *rb_node_return_new(struct parser_params *p, NODE *nd_stts, const YYLTYPE *loc);
static rb_node_yield_t *rb_node_yield_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc);
static rb_node_lvar_t *rb_node_lvar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc);
static rb_node_dvar_t *rb_node_dvar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc);
static rb_node_gvar_t *rb_node_gvar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc);
static rb_node_ivar_t *rb_node_ivar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc);
static rb_node_const_t *rb_node_const_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc);
static rb_node_cvar_t *rb_node_cvar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc);
static rb_node_nth_ref_t *rb_node_nth_ref_new(struct parser_params *p, long nd_nth, const YYLTYPE *loc);
static rb_node_back_ref_t *rb_node_back_ref_new(struct parser_params *p, long nd_nth, const YYLTYPE *loc);
static rb_node_match2_t *rb_node_match2_new(struct parser_params *p, NODE *nd_recv, NODE *nd_value, const YYLTYPE *loc);
static rb_node_match3_t *rb_node_match3_new(struct parser_params *p, NODE *nd_recv, NODE *nd_value, const YYLTYPE *loc);
static rb_node_lit_t *rb_node_lit_new(struct parser_params *p, VALUE nd_lit, const YYLTYPE *loc);
static rb_node_str_t *rb_node_str_new(struct parser_params *p, VALUE nd_lit, const YYLTYPE *loc);
static rb_node_dstr_t *rb_node_dstr_new0(struct parser_params *p, VALUE nd_lit, long nd_alen, NODE *nd_next, const YYLTYPE *loc);
static rb_node_dstr_t *rb_node_dstr_new(struct parser_params *p, VALUE nd_lit, const YYLTYPE *loc);
static rb_node_xstr_t *rb_node_xstr_new(struct parser_params *p, VALUE nd_lit, const YYLTYPE *loc);
static rb_node_dxstr_t *rb_node_dxstr_new(struct parser_params *p, VALUE nd_lit, long nd_alen, NODE *nd_next, const YYLTYPE *loc);
static rb_node_evstr_t *rb_node_evstr_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc);
static rb_node_once_t *rb_node_once_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc);
static rb_node_args_t *rb_node_args_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_args_aux_t *rb_node_args_aux_new(struct parser_params *p, ID nd_pid, long nd_plen, const YYLTYPE *loc);
static rb_node_opt_arg_t *rb_node_opt_arg_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc);
static rb_node_kw_arg_t *rb_node_kw_arg_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc);
static rb_node_postarg_t *rb_node_postarg_new(struct parser_params *p, NODE *nd_1st, NODE *nd_2nd, const YYLTYPE *loc);
static rb_node_argscat_t *rb_node_argscat_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, const YYLTYPE *loc);
static rb_node_argspush_t *rb_node_argspush_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, const YYLTYPE *loc);
static rb_node_splat_t *rb_node_splat_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc);
static rb_node_block_pass_t *rb_node_block_pass_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc);
static rb_node_defn_t *rb_node_defn_new(struct parser_params *p, ID nd_mid, NODE *nd_defn, const YYLTYPE *loc);
static rb_node_defs_t *rb_node_defs_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_defn, const YYLTYPE *loc);
static rb_node_alias_t *rb_node_alias_new(struct parser_params *p, NODE *nd_1st, NODE *nd_2nd, const YYLTYPE *loc);
static rb_node_valias_t *rb_node_valias_new(struct parser_params *p, ID nd_alias, ID nd_orig, const YYLTYPE *loc);
static rb_node_undef_t *rb_node_undef_new(struct parser_params *p, NODE *nd_undef, const YYLTYPE *loc);
static rb_node_class_t *rb_node_class_new(struct parser_params *p, NODE *nd_cpath, NODE *nd_body, NODE *nd_super, const YYLTYPE *loc);
static rb_node_module_t *rb_node_module_new(struct parser_params *p, NODE *nd_cpath, NODE *nd_body, const YYLTYPE *loc);
static rb_node_sclass_t *rb_node_sclass_new(struct parser_params *p, NODE *nd_recv, NODE *nd_body, const YYLTYPE *loc);
static rb_node_colon2_t *rb_node_colon2_new(struct parser_params *p, NODE *nd_head, ID nd_mid, const YYLTYPE *loc);
static rb_node_colon3_t *rb_node_colon3_new(struct parser_params *p, ID nd_mid, const YYLTYPE *loc);
static rb_node_dot2_t *rb_node_dot2_new(struct parser_params *p, NODE *nd_beg, NODE *nd_end, const YYLTYPE *loc);
static rb_node_dot3_t *rb_node_dot3_new(struct parser_params *p, NODE *nd_beg, NODE *nd_end, const YYLTYPE *loc);
static rb_node_self_t *rb_node_self_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_nil_t *rb_node_nil_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_true_t *rb_node_true_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_false_t *rb_node_false_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_errinfo_t *rb_node_errinfo_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_defined_t *rb_node_defined_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc);
static rb_node_postexe_t *rb_node_postexe_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc);
static rb_node_dsym_t *rb_node_dsym_new(struct parser_params *p, VALUE nd_lit, long nd_alen, NODE *nd_next, const YYLTYPE *loc);
static rb_node_attrasgn_t *rb_node_attrasgn_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_args, const YYLTYPE *loc);
static rb_node_lambda_t *rb_node_lambda_new(struct parser_params *p, rb_node_args_t *nd_args, NODE *nd_body, const YYLTYPE *loc);
static rb_node_aryptn_t *rb_node_aryptn_new(struct parser_params *p, NODE *pre_args, NODE *rest_arg, NODE *post_args, const YYLTYPE *loc);
static rb_node_hshptn_t *rb_node_hshptn_new(struct parser_params *p, NODE *nd_pconst, NODE *nd_pkwargs, NODE *nd_pkwrestarg, const YYLTYPE *loc);
static rb_node_fndptn_t *rb_node_fndptn_new(struct parser_params *p, NODE *pre_rest_arg, NODE *args, NODE *post_rest_arg, const YYLTYPE *loc);
static rb_node_error_t *rb_node_error_new(struct parser_params *p, const YYLTYPE *loc);

#define NEW_SCOPE(a,b,loc) (NODE *)rb_node_scope_new(p,a,b,loc)
#define NEW_SCOPE2(t,a,b,loc) (NODE *)rb_node_scope_new2(p,t,a,b,loc)
#define NEW_BLOCK(a,loc) (NODE *)rb_node_block_new(p,a,loc)
#define NEW_IF(c,t,e,loc) (NODE *)rb_node_if_new(p,c,t,e,loc)
#define NEW_UNLESS(c,t,e,loc) (NODE *)rb_node_unless_new(p,c,t,e,loc)
#define NEW_CASE(h,b,loc) (NODE *)rb_node_case_new(p,h,b,loc)
#define NEW_CASE2(b,loc) (NODE *)rb_node_case2_new(p,b,loc)
#define NEW_CASE3(h,b,loc) (NODE *)rb_node_case3_new(p,h,b,loc)
#define NEW_WHEN(c,t,e,loc) (NODE *)rb_node_when_new(p,c,t,e,loc)
#define NEW_IN(c,t,e,loc) (NODE *)rb_node_in_new(p,c,t,e,loc)
#define NEW_WHILE(c,b,n,loc) (NODE *)rb_node_while_new(p,c,b,n,loc)
#define NEW_UNTIL(c,b,n,loc) (NODE *)rb_node_until_new(p,c,b,n,loc)
#define NEW_ITER(a,b,loc) (NODE *)rb_node_iter_new(p,a,b,loc)
#define NEW_FOR(i,b,loc) (NODE *)rb_node_for_new(p,i,b,loc)
#define NEW_FOR_MASGN(v,loc) (NODE *)rb_node_for_masgn_new(p,v,loc)
#define NEW_RETRY(loc) (NODE *)rb_node_retry_new(p,loc)
#define NEW_BEGIN(b,loc) (NODE *)rb_node_begin_new(p,b,loc)
#define NEW_RESCUE(b,res,e,loc) (NODE *)rb_node_rescue_new(p,b,res,e,loc)
#define NEW_RESBODY(a,ex,n,loc) (NODE *)rb_node_resbody_new(p,a,ex,n,loc)
#define NEW_ENSURE(b,en,loc) (NODE *)rb_node_ensure_new(p,b,en,loc)
#define NEW_AND(f,s,loc) (NODE *)rb_node_and_new(p,f,s,loc)
#define NEW_OR(f,s,loc) (NODE *)rb_node_or_new(p,f,s,loc)
#define NEW_MASGN(l,r,loc)   rb_node_masgn_new(p,l,r,loc)
#define NEW_LASGN(v,val,loc) (NODE *)rb_node_lasgn_new(p,v,val,loc)
#define NEW_DASGN(v,val,loc) (NODE *)rb_node_dasgn_new(p,v,val,loc)
#define NEW_GASGN(v,val,loc) (NODE *)rb_node_gasgn_new(p,v,val,loc)
#define NEW_IASGN(v,val,loc) (NODE *)rb_node_iasgn_new(p,v,val,loc)
#define NEW_CDECL(v,val,path,loc) (NODE *)rb_node_cdecl_new(p,v,val,path,loc)
#define NEW_CVASGN(v,val,loc) (NODE *)rb_node_cvasgn_new(p,v,val,loc)
#define NEW_OP_ASGN1(r,id,idx,rval,loc) (NODE *)rb_node_op_asgn1_new(p,r,id,idx,rval,loc)
#define NEW_OP_ASGN2(r,t,i,o,val,loc) (NODE *)rb_node_op_asgn2_new(p,r,val,i,o,t,loc)
#define NEW_OP_ASGN_OR(i,val,loc) (NODE *)rb_node_op_asgn_or_new(p,i,val,loc)
#define NEW_OP_ASGN_AND(i,val,loc) (NODE *)rb_node_op_asgn_and_new(p,i,val,loc)
#define NEW_OP_CDECL(v,op,val,loc) (NODE *)rb_node_op_cdecl_new(p,v,val,op,loc)
#define NEW_CALL(r,m,a,loc) (NODE *)rb_node_call_new(p,r,m,a,loc)
#define NEW_OPCALL(r,m,a,loc) (NODE *)rb_node_opcall_new(p,r,m,a,loc)
#define NEW_FCALL(m,a,loc) rb_node_fcall_new(p,m,a,loc)
#define NEW_VCALL(m,loc) (NODE *)rb_node_vcall_new(p,m,loc)
#define NEW_QCALL0(r,m,a,loc) (NODE *)rb_node_qcall_new(p,r,m,a,loc)
#define NEW_SUPER(a,loc) (NODE *)rb_node_super_new(p,a,loc)
#define NEW_ZSUPER(loc) (NODE *)rb_node_zsuper_new(p,loc)
#define NEW_LIST(a,loc) (NODE *)rb_node_list_new(p,a,loc)
#define NEW_LIST2(h,l,n,loc) (NODE *)rb_node_list_new2(p,h,l,n,loc)
#define NEW_ZLIST(loc) (NODE *)rb_node_zlist_new(p,loc)
#define NEW_HASH(a,loc) (NODE *)rb_node_hash_new(p,a,loc)
#define NEW_RETURN(s,loc) (NODE *)rb_node_return_new(p,s,loc)
#define NEW_YIELD(a,loc) (NODE *)rb_node_yield_new(p,a,loc)
#define NEW_LVAR(v,loc) (NODE *)rb_node_lvar_new(p,v,loc)
#define NEW_DVAR(v,loc) (NODE *)rb_node_dvar_new(p,v,loc)
#define NEW_GVAR(v,loc) (NODE *)rb_node_gvar_new(p,v,loc)
#define NEW_IVAR(v,loc) (NODE *)rb_node_ivar_new(p,v,loc)
#define NEW_CONST(v,loc) (NODE *)rb_node_const_new(p,v,loc)
#define NEW_CVAR(v,loc) (NODE *)rb_node_cvar_new(p,v,loc)
#define NEW_NTH_REF(n,loc)  (NODE *)rb_node_nth_ref_new(p,n,loc)
#define NEW_BACK_REF(n,loc) (NODE *)rb_node_back_ref_new(p,n,loc)
#define NEW_MATCH2(n1,n2,loc) (NODE *)rb_node_match2_new(p,n1,n2,loc)
#define NEW_MATCH3(r,n2,loc) (NODE *)rb_node_match3_new(p,r,n2,loc)
#define NEW_LIT(l,loc) (NODE *)rb_node_lit_new(p,l,loc)
#define NEW_STR(s,loc) (NODE *)rb_node_str_new(p,s,loc)
#define NEW_DSTR0(s,l,n,loc) (NODE *)rb_node_dstr_new0(p,s,l,n,loc)
#define NEW_DSTR(s,loc) (NODE *)rb_node_dstr_new(p,s,loc)
#define NEW_XSTR(s,loc) (NODE *)rb_node_xstr_new(p,s,loc)
#define NEW_DXSTR(s,l,n,loc) (NODE *)rb_node_dxstr_new(p,s,l,n,loc)
#define NEW_EVSTR(n,loc) (NODE *)rb_node_evstr_new(p,n,loc)
#define NEW_ONCE(b,loc) (NODE *)rb_node_once_new(p,b,loc)
#define NEW_ARGS(loc) rb_node_args_new(p,loc)
#define NEW_ARGS_AUX(r,b,loc) rb_node_args_aux_new(p,r,b,loc)
#define NEW_OPT_ARG(v,loc) rb_node_opt_arg_new(p,v,loc)
#define NEW_KW_ARG(v,loc) rb_node_kw_arg_new(p,v,loc)
#define NEW_POSTARG(i,v,loc) (NODE *)rb_node_postarg_new(p,i,v,loc)
#define NEW_ARGSCAT(a,b,loc) (NODE *)rb_node_argscat_new(p,a,b,loc)
#define NEW_ARGSPUSH(a,b,loc) (NODE *)rb_node_argspush_new(p,a,b,loc)
#define NEW_SPLAT(a,loc) (NODE *)rb_node_splat_new(p,a,loc)
#define NEW_BLOCK_PASS(b,loc) rb_node_block_pass_new(p,b,loc)
#define NEW_DEFN(i,s,loc) (NODE *)rb_node_defn_new(p,i,s,loc)
#define NEW_DEFS(r,i,s,loc) (NODE *)rb_node_defs_new(p,r,i,s,loc)
#define NEW_ALIAS(n,o,loc) (NODE *)rb_node_alias_new(p,n,o,loc)
#define NEW_VALIAS(n,o,loc) (NODE *)rb_node_valias_new(p,n,o,loc)
#define NEW_UNDEF(i,loc) (NODE *)rb_node_undef_new(p,i,loc)
#define NEW_CLASS(n,b,s,loc) (NODE *)rb_node_class_new(p,n,b,s,loc)
#define NEW_MODULE(n,b,loc) (NODE *)rb_node_module_new(p,n,b,loc)
#define NEW_SCLASS(r,b,loc) (NODE *)rb_node_sclass_new(p,r,b,loc)
#define NEW_COLON2(c,i,loc) (NODE *)rb_node_colon2_new(p,c,i,loc)
#define NEW_COLON3(i,loc) (NODE *)rb_node_colon3_new(p,i,loc)
#define NEW_DOT2(b,e,loc) (NODE *)rb_node_dot2_new(p,b,e,loc)
#define NEW_DOT3(b,e,loc) (NODE *)rb_node_dot3_new(p,b,e,loc)
#define NEW_SELF(loc) (NODE *)rb_node_self_new(p,loc)
#define NEW_NIL(loc) (NODE *)rb_node_nil_new(p,loc)
#define NEW_TRUE(loc) (NODE *)rb_node_true_new(p,loc)
#define NEW_FALSE(loc) (NODE *)rb_node_false_new(p,loc)
#define NEW_ERRINFO(loc) (NODE *)rb_node_errinfo_new(p,loc)
#define NEW_DEFINED(e,loc) (NODE *)rb_node_defined_new(p,e,loc)
#define NEW_POSTEXE(b,loc) (NODE *)rb_node_postexe_new(p,b,loc)
#define NEW_DSYM(s,l,n,loc) (NODE *)rb_node_dsym_new(p,s,l,n,loc)
#define NEW_ATTRASGN(r,m,a,loc) (NODE *)rb_node_attrasgn_new(p,r,m,a,loc)
#define NEW_LAMBDA(a,b,loc) (NODE *)rb_node_lambda_new(p,a,b,loc)
#define NEW_ARYPTN(pre,r,post,loc) (NODE *)rb_node_aryptn_new(p,pre,r,post,loc)
#define NEW_HSHPTN(c,kw,kwrest,loc) (NODE *)rb_node_hshptn_new(p,c,kw,kwrest,loc)
#define NEW_FNDPTN(pre,a,post,loc) (NODE *)rb_node_fndptn_new(p,pre,a,post,loc)
#define NEW_ERROR(loc) (NODE *)rb_node_error_new(p,loc)

#endif

enum internal_node_type {
    NODE_INTERNAL_ONLY = NODE_LAST,
    NODE_DEF_TEMP,
    NODE_EXITS,
    NODE_INTERNAL_LAST
};

static const char *
parser_node_name(int node)
{
    switch (node) {
      case NODE_DEF_TEMP:
        return "NODE_DEF_TEMP";
      case NODE_EXITS:
        return "NODE_EXITS";
      default:
        return ruby_node_name(node);
    }
}

/* This node is parse.y internal */
struct RNode_DEF_TEMP {
    NODE node;

    /* for NODE_DEFN/NODE_DEFS */
#ifndef RIPPER
    struct RNode *nd_def;
    ID nd_mid;
#else
    VALUE nd_recv;
    VALUE nd_mid;
    VALUE dot_or_colon;
#endif

    struct {
        ID cur_arg;
        int max_numparam;
        NODE *numparam_save;
        struct lex_context ctxt;
    } save;
};

#define RNODE_DEF_TEMP(node) ((struct RNode_DEF_TEMP *)(node))

static rb_node_break_t *rb_node_break_new(struct parser_params *p, NODE *nd_stts, const YYLTYPE *loc);
static rb_node_next_t *rb_node_next_new(struct parser_params *p, NODE *nd_stts, const YYLTYPE *loc);
static rb_node_redo_t *rb_node_redo_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_def_temp_t *rb_node_def_temp_new(struct parser_params *p, const YYLTYPE *loc);
static rb_node_def_temp_t *def_head_save(struct parser_params *p, rb_node_def_temp_t *n);

#define NEW_BREAK(s,loc) (NODE *)rb_node_break_new(p,s,loc)
#define NEW_NEXT(s,loc) (NODE *)rb_node_next_new(p,s,loc)
#define NEW_REDO(loc) (NODE *)rb_node_redo_new(p,loc)
#define NEW_DEF_TEMP(loc) rb_node_def_temp_new(p,loc)

/* Make a new internal node, which should not be appeared in the
 * result AST and does not have node_id and location. */
static NODE* node_new_internal(struct parser_params *p, enum node_type type, size_t size, size_t alignment);
#define NODE_NEW_INTERNAL(ndtype, type) (type *)node_new_internal(p, (enum node_type)(ndtype), sizeof(type), RUBY_ALIGNOF(type))

static NODE *nd_set_loc(NODE *nd, const YYLTYPE *loc);

static int
parser_get_node_id(struct parser_params *p)
{
    int node_id = p->node_id;
    p->node_id++;
    return node_id;
}

static void
anddot_multiple_assignment_check(struct parser_params* p, const YYLTYPE *loc, ID id)
{
    if (id == tANDDOT) {
	yyerror1(loc, "&. inside multiple assignment destination");
    }
}

#ifndef RIPPER
static inline void
set_line_body(NODE *body, int line)
{
    if (!body) return;
    switch (nd_type(body)) {
      case NODE_RESCUE:
      case NODE_ENSURE:
        nd_set_line(body, line);
    }
}

static void
set_embraced_location(NODE *node, const rb_code_location_t *beg, const rb_code_location_t *end)
{
    RNODE_ITER(node)->nd_body->nd_loc = code_loc_gen(beg, end);
    nd_set_line(node, beg->end_pos.lineno);
}

static NODE *
last_expr_node(NODE *expr)
{
    while (expr) {
        if (nd_type_p(expr, NODE_BLOCK)) {
            expr = RNODE_BLOCK(RNODE_BLOCK(expr)->nd_end)->nd_head;
        }
        else if (nd_type_p(expr, NODE_BEGIN)) {
            expr = RNODE_BEGIN(expr)->nd_body;
        }
        else {
            break;
        }
    }
    return expr;
}

#define yyparse ruby_yyparse

static NODE* cond(struct parser_params *p, NODE *node, const YYLTYPE *loc);
static NODE* method_cond(struct parser_params *p, NODE *node, const YYLTYPE *loc);
#define new_nil(loc) NEW_NIL(loc)
static NODE *new_nil_at(struct parser_params *p, const rb_code_position_t *pos);
static NODE *new_if(struct parser_params*,NODE*,NODE*,NODE*,const YYLTYPE*);
static NODE *new_unless(struct parser_params*,NODE*,NODE*,NODE*,const YYLTYPE*);
static NODE *logop(struct parser_params*,ID,NODE*,NODE*,const YYLTYPE*,const YYLTYPE*);

static NODE *newline_node(NODE*);
static void fixpos(NODE*,NODE*);

static int value_expr_gen(struct parser_params*,NODE*);
static void void_expr(struct parser_params*,NODE*);
static NODE *remove_begin(NODE*);
static NODE *remove_begin_all(NODE*);
#define value_expr(node) value_expr_gen(p, (node))
static NODE *void_stmts(struct parser_params*,NODE*);
static void reduce_nodes(struct parser_params*,NODE**);
static void block_dup_check(struct parser_params*,NODE*,NODE*);

static NODE *block_append(struct parser_params*,NODE*,NODE*);
static NODE *list_append(struct parser_params*,NODE*,NODE*);
static NODE *list_concat(NODE*,NODE*);
static NODE *arg_append(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
static NODE *last_arg_append(struct parser_params *p, NODE *args, NODE *last_arg, const YYLTYPE *loc);
static NODE *rest_arg_append(struct parser_params *p, NODE *args, NODE *rest_arg, const YYLTYPE *loc);
static NODE *literal_concat(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
static NODE *new_evstr(struct parser_params*,NODE*,const YYLTYPE*);
static NODE *new_dstr(struct parser_params*,NODE*,const YYLTYPE*);
static NODE *str2dstr(struct parser_params*,NODE*);
static NODE *evstr2dstr(struct parser_params*,NODE*);
static NODE *splat_array(NODE*);
static void mark_lvar_used(struct parser_params *p, NODE *rhs);

static NODE *call_bin_op(struct parser_params*,NODE*,ID,NODE*,const YYLTYPE*,const YYLTYPE*);
static NODE *call_uni_op(struct parser_params*,NODE*,ID,const YYLTYPE*,const YYLTYPE*);
static NODE *new_qcall(struct parser_params* p, ID atype, NODE *recv, ID mid, NODE *args, const YYLTYPE *op_loc, const YYLTYPE *loc);
static NODE *new_command_qcall(struct parser_params* p, ID atype, NODE *recv, ID mid, NODE *args, NODE *block, const YYLTYPE *op_loc, const YYLTYPE *loc);
static NODE *method_add_block(struct parser_params*p, NODE *m, NODE *b, const YYLTYPE *loc) {RNODE_ITER(b)->nd_iter = m; b->nd_loc = *loc; return b;}

static bool args_info_empty_p(struct rb_args_info *args);
static rb_node_args_t *new_args(struct parser_params*,rb_node_args_aux_t*,rb_node_opt_arg_t*,ID,rb_node_args_aux_t*,rb_node_args_t*,const YYLTYPE*);
static rb_node_args_t *new_args_tail(struct parser_params*,rb_node_kw_arg_t*,ID,ID,const YYLTYPE*);
static NODE *new_array_pattern(struct parser_params *p, NODE *constant, NODE *pre_arg, NODE *aryptn, const YYLTYPE *loc);
static NODE *new_array_pattern_tail(struct parser_params *p, NODE *pre_args, int has_rest, NODE *rest_arg, NODE *post_args, const YYLTYPE *loc);
static NODE *new_find_pattern(struct parser_params *p, NODE *constant, NODE *fndptn, const YYLTYPE *loc);
static NODE *new_find_pattern_tail(struct parser_params *p, NODE *pre_rest_arg, NODE *args, NODE *post_rest_arg, const YYLTYPE *loc);
static NODE *new_hash_pattern(struct parser_params *p, NODE *constant, NODE *hshptn, const YYLTYPE *loc);
static NODE *new_hash_pattern_tail(struct parser_params *p, NODE *kw_args, ID kw_rest_arg, const YYLTYPE *loc);

static rb_node_kw_arg_t *new_kw_arg(struct parser_params *p, NODE *k, const YYLTYPE *loc);
static rb_node_args_t *args_with_numbered(struct parser_params*,rb_node_args_t*,int);

static VALUE negate_lit(struct parser_params*, VALUE);
static NODE *ret_args(struct parser_params*,NODE*);
static NODE *arg_blk_pass(NODE*,rb_node_block_pass_t*);
static NODE *new_yield(struct parser_params*,NODE*,const YYLTYPE*);
static NODE *dsym_node(struct parser_params*,NODE*,const YYLTYPE*);

static NODE *gettable(struct parser_params*,ID,const YYLTYPE*);
static NODE *assignable(struct parser_params*,ID,NODE*,const YYLTYPE*);

static NODE *aryset(struct parser_params*,NODE*,NODE*,const YYLTYPE*);
static NODE *attrset(struct parser_params*,NODE*,ID,ID,const YYLTYPE*);

static void rb_backref_error(struct parser_params*,NODE*);
static NODE *node_assign(struct parser_params*,NODE*,NODE*,struct lex_context,const YYLTYPE*);

static NODE *new_op_assign(struct parser_params *p, NODE *lhs, ID op, NODE *rhs, struct lex_context, const YYLTYPE *loc);
static NODE *new_ary_op_assign(struct parser_params *p, NODE *ary, NODE *args, ID op, NODE *rhs, const YYLTYPE *args_loc, const YYLTYPE *loc);
static NODE *new_attr_op_assign(struct parser_params *p, NODE *lhs, ID atype, ID attr, ID op, NODE *rhs, const YYLTYPE *loc);
static NODE *new_const_op_assign(struct parser_params *p, NODE *lhs, ID op, NODE *rhs, struct lex_context, const YYLTYPE *loc);
static NODE *new_bodystmt(struct parser_params *p, NODE *head, NODE *rescue, NODE *rescue_else, NODE *ensure, const YYLTYPE *loc);

static NODE *const_decl(struct parser_params *p, NODE* path, const YYLTYPE *loc);

static rb_node_opt_arg_t *opt_arg_append(rb_node_opt_arg_t*, rb_node_opt_arg_t*);
static rb_node_kw_arg_t *kwd_append(rb_node_kw_arg_t*, rb_node_kw_arg_t*);

static NODE *new_hash(struct parser_params *p, NODE *hash, const YYLTYPE *loc);
static NODE *new_unique_key_hash(struct parser_params *p, NODE *hash, const YYLTYPE *loc);

static NODE *new_defined(struct parser_params *p, NODE *expr, const YYLTYPE *loc);

static NODE *new_regexp(struct parser_params *, NODE *, int, const YYLTYPE *);

#define make_list(list, loc) ((list) ? (nd_set_loc(list, loc), list) : NEW_ZLIST(loc))

static NODE *new_xstring(struct parser_params *, NODE *, const YYLTYPE *loc);

static NODE *symbol_append(struct parser_params *p, NODE *symbols, NODE *symbol);

static NODE *match_op(struct parser_params*,NODE*,NODE*,const YYLTYPE*,const YYLTYPE*);

static rb_ast_id_table_t *local_tbl(struct parser_params*);

static VALUE reg_compile(struct parser_params*, VALUE, int);
static void reg_fragment_setenc(struct parser_params*, VALUE, int);
static int reg_fragment_check(struct parser_params*, VALUE, int);

static int literal_concat0(struct parser_params *p, VALUE head, VALUE tail);
static NODE *heredoc_dedent(struct parser_params*,NODE*);

static void check_literal_when(struct parser_params *p, NODE *args, const YYLTYPE *loc);

#define get_id(id) (id)
#define get_value(val) (val)
#define get_num(num) (num)
#else  /* RIPPER */

static inline int ripper_is_node_yylval(struct parser_params *p, VALUE n);

static inline VALUE
ripper_new_yylval(struct parser_params *p, ID a, VALUE b, VALUE c)
{
    if (ripper_is_node_yylval(p, c)) c = RNODE_RIPPER(c)->nd_cval;
    add_mark_object(p, b);
    add_mark_object(p, c);
    return NEW_RIPPER(a, b, c, &NULL_LOC);
}

static inline VALUE
ripper_new_yylval2(struct parser_params *p, VALUE a, VALUE b, VALUE c)
{
    add_mark_object(p, a);
    add_mark_object(p, b);
    add_mark_object(p, c);
    return NEW_RIPPER_VALUES(a, b, c, &NULL_LOC);
}

static inline int
ripper_is_node_yylval(struct parser_params *p, VALUE n)
{
    return RB_TYPE_P(n, T_NODE) && nd_type_p(RNODE(n), NODE_RIPPER);
}

#define value_expr(node) ((void)(node))
#define remove_begin(node) (node)
#define void_stmts(p,x) (x)
#undef rb_dvar_defined
#define rb_dvar_defined(id, base) 0
#undef rb_local_defined
#define rb_local_defined(id, base) 0
#define get_id(id) ripper_get_id(id)
#define get_value(val) ripper_get_value(val)
#define get_num(num) (int)get_id(num)
static VALUE assignable(struct parser_params*,VALUE);
static int id_is_var(struct parser_params *p, ID id);

#define method_cond(p,node,loc) (node)
#define call_bin_op(p, recv,id,arg1,op_loc,loc) dispatch3(binary, (recv), STATIC_ID2SYM(id), (arg1))
#define match_op(p,node1,node2,op_loc,loc) call_bin_op(0, (node1), idEqTilde, (node2), op_loc, loc)
#define call_uni_op(p, recv,id,op_loc,loc) dispatch2(unary, STATIC_ID2SYM(id), (recv))
#define logop(p,id,node1,node2,op_loc,loc) call_bin_op(0, (node1), (id), (node2), op_loc, loc)

#define new_nil(loc) Qnil

static VALUE new_regexp(struct parser_params *, VALUE, VALUE, const YYLTYPE *);

static VALUE const_decl(struct parser_params *p, VALUE path);

static VALUE var_field(struct parser_params *p, VALUE a);
static VALUE assign_error(struct parser_params *p, const char *mesg, VALUE a);

static VALUE parser_reg_compile(struct parser_params*, VALUE, int, VALUE *);

static VALUE backref_error(struct parser_params*, NODE *, VALUE);
#endif /* !RIPPER */

RUBY_SYMBOL_EXPORT_BEGIN
VALUE rb_parser_reg_compile(struct parser_params* p, VALUE str, int options);
int rb_reg_fragment_setenc(struct parser_params*, VALUE, int);
enum lex_state_e rb_parser_trace_lex_state(struct parser_params *, enum lex_state_e, enum lex_state_e, int);
VALUE rb_parser_lex_state_name(struct parser_params *p, enum lex_state_e state);
void rb_parser_show_bitstack(struct parser_params *, stack_type, const char *, int);
PRINTF_ARGS(void rb_parser_fatal(struct parser_params *p, const char *fmt, ...), 2, 3);
YYLTYPE *rb_parser_set_location_from_strterm_heredoc(struct parser_params *p, rb_strterm_heredoc_t *here, YYLTYPE *yylloc);
YYLTYPE *rb_parser_set_location_of_delayed_token(struct parser_params *p, YYLTYPE *yylloc);
YYLTYPE *rb_parser_set_location_of_heredoc_end(struct parser_params *p, YYLTYPE *yylloc);
YYLTYPE *rb_parser_set_location_of_dummy_end(struct parser_params *p, YYLTYPE *yylloc);
YYLTYPE *rb_parser_set_location_of_none(struct parser_params *p, YYLTYPE *yylloc);
YYLTYPE *rb_parser_set_location(struct parser_params *p, YYLTYPE *yylloc);
RUBY_SYMBOL_EXPORT_END

static void error_duplicate_pattern_variable(struct parser_params *p, ID id, const YYLTYPE *loc);
static void error_duplicate_pattern_key(struct parser_params *p, ID id, const YYLTYPE *loc);
#ifndef RIPPER
static ID formal_argument(struct parser_params*, ID);
#else
static ID formal_argument(struct parser_params*, VALUE);
#endif
static ID shadowing_lvar(struct parser_params*,ID);
static void new_bv(struct parser_params*,ID);

static void local_push(struct parser_params*,int);
static void local_pop(struct parser_params*);
static void local_var(struct parser_params*, ID);
static void arg_var(struct parser_params*, ID);
static int  local_id(struct parser_params *p, ID id);
static int  local_id_ref(struct parser_params*, ID, ID **);
#ifndef RIPPER
static ID   internal_id(struct parser_params*);
static NODE *new_args_forward_call(struct parser_params*, NODE*, const YYLTYPE*, const YYLTYPE*);
#endif
static int check_forwarding_args(struct parser_params*);
static void add_forwarding_args(struct parser_params *p);
static void forwarding_arg_check(struct parser_params *p, ID arg, ID all, const char *var);

static const struct vtable *dyna_push(struct parser_params *);
static void dyna_pop(struct parser_params*, const struct vtable *);
static int dyna_in_block(struct parser_params*);
#define dyna_var(p, id) local_var(p, id)
static int dvar_defined(struct parser_params*, ID);
static int dvar_defined_ref(struct parser_params*, ID, ID**);
static int dvar_curr(struct parser_params*,ID);

static int lvar_defined(struct parser_params*, ID);

static NODE *numparam_push(struct parser_params *p);
static void numparam_pop(struct parser_params *p, NODE *prev_inner);

#ifdef RIPPER
# define METHOD_NOT idNOT
#else
# define METHOD_NOT '!'
#endif

#define idFWD_REST   '*'
#define idFWD_KWREST idPow /* Use simple "**", as tDSTAR is "**arg" */
#define idFWD_BLOCK  '&'
#define idFWD_ALL    idDot3
#ifdef RIPPER
#define arg_FWD_BLOCK Qnone
#else
#define arg_FWD_BLOCK idFWD_BLOCK
#endif
#define FORWARD_ARGS_WITH_RUBY2_KEYWORDS

#define RE_OPTION_ONCE (1<<16)
#define RE_OPTION_ENCODING_SHIFT 8
#define RE_OPTION_ENCODING(e) (((e)&0xff)<<RE_OPTION_ENCODING_SHIFT)
#define RE_OPTION_ENCODING_IDX(o) (((o)>>RE_OPTION_ENCODING_SHIFT)&0xff)
#define RE_OPTION_ENCODING_NONE(o) ((o)&RE_OPTION_ARG_ENCODING_NONE)
#define RE_OPTION_MASK  0xff
#define RE_OPTION_ARG_ENCODING_NONE 32

#define yytnamerr(yyres, yystr) (YYSIZE_T)rb_yytnamerr(p, yyres, yystr)
size_t rb_yytnamerr(struct parser_params *p, char *yyres, const char *yystr);

#define TOKEN2ID(tok) ( \
    tTOKEN_LOCAL_BEGIN<(tok)&&(tok)<tTOKEN_LOCAL_END ? TOKEN2LOCALID(tok) : \
    tTOKEN_INSTANCE_BEGIN<(tok)&&(tok)<tTOKEN_INSTANCE_END ? TOKEN2INSTANCEID(tok) : \
    tTOKEN_GLOBAL_BEGIN<(tok)&&(tok)<tTOKEN_GLOBAL_END ? TOKEN2GLOBALID(tok) : \
    tTOKEN_CONST_BEGIN<(tok)&&(tok)<tTOKEN_CONST_END ? TOKEN2CONSTID(tok) : \
    tTOKEN_CLASS_BEGIN<(tok)&&(tok)<tTOKEN_CLASS_END ? TOKEN2CLASSID(tok) : \
    tTOKEN_ATTRSET_BEGIN<(tok)&&(tok)<tTOKEN_ATTRSET_END ? TOKEN2ATTRSETID(tok) : \
    ((tok) / ((tok)<tPRESERVED_ID_END && ((tok)>=128 || rb_ispunct(tok)))))

/****** Ripper *******/

#ifdef RIPPER

#include "eventids1.h"
#include "eventids2.h"

extern const struct ripper_parser_ids ripper_parser_ids;

static VALUE ripper_dispatch0(struct parser_params*,ID);
static VALUE ripper_dispatch1(struct parser_params*,ID,VALUE);
static VALUE ripper_dispatch2(struct parser_params*,ID,VALUE,VALUE);
static VALUE ripper_dispatch3(struct parser_params*,ID,VALUE,VALUE,VALUE);
static VALUE ripper_dispatch4(struct parser_params*,ID,VALUE,VALUE,VALUE,VALUE);
static VALUE ripper_dispatch5(struct parser_params*,ID,VALUE,VALUE,VALUE,VALUE,VALUE);
static VALUE ripper_dispatch7(struct parser_params*,ID,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE,VALUE);
void ripper_error(struct parser_params *p);

#define dispatch0(n)            ripper_dispatch0(p, TOKEN_PASTE(ripper_id_, n))
#define dispatch1(n,a)          ripper_dispatch1(p, TOKEN_PASTE(ripper_id_, n), (a))
#define dispatch2(n,a,b)        ripper_dispatch2(p, TOKEN_PASTE(ripper_id_, n), (a), (b))
#define dispatch3(n,a,b,c)      ripper_dispatch3(p, TOKEN_PASTE(ripper_id_, n), (a), (b), (c))
#define dispatch4(n,a,b,c,d)    ripper_dispatch4(p, TOKEN_PASTE(ripper_id_, n), (a), (b), (c), (d))
#define dispatch5(n,a,b,c,d,e)  ripper_dispatch5(p, TOKEN_PASTE(ripper_id_, n), (a), (b), (c), (d), (e))
#define dispatch7(n,a,b,c,d,e,f,g) ripper_dispatch7(p, TOKEN_PASTE(ripper_id_, n), (a), (b), (c), (d), (e), (f), (g))

#define yyparse ripper_yyparse

#define ID2VAL(id) STATIC_ID2SYM(id)
#define TOKEN2VAL(t) ID2VAL(TOKEN2ID(t))
#define KWD2EID(t, v) ripper_new_yylval(p, keyword_##t, get_value(v), 0)

#define params_new(pars, opts, rest, pars2, kws, kwrest, blk) \
        dispatch7(params, (pars), (opts), (rest), (pars2), (kws), (kwrest), (blk))

static inline VALUE
new_args(struct parser_params *p, VALUE pre_args, VALUE opt_args, VALUE rest_arg, VALUE post_args, VALUE tail, YYLTYPE *loc)
{
    struct RNode_RIPPER_VALUES *t = RNODE_RIPPER_VALUES(tail);
    VALUE kw_args = t->nd_val1, kw_rest_arg = t->nd_val2, block = t->nd_val3;
    return params_new(pre_args, opt_args, rest_arg, post_args, kw_args, kw_rest_arg, block);
}

static inline VALUE
new_args_tail(struct parser_params *p, VALUE kw_args, VALUE kw_rest_arg, VALUE block, YYLTYPE *loc)
{
    return ripper_new_yylval2(p, kw_args, kw_rest_arg, block);
}

static inline VALUE
args_with_numbered(struct parser_params *p, VALUE args, int max_numparam)
{
    return args;
}

static VALUE
new_array_pattern(struct parser_params *p, VALUE constant, VALUE pre_arg, VALUE aryptn, const YYLTYPE *loc)
{
    struct RNode_RIPPER_VALUES *t = RNODE_RIPPER_VALUES(aryptn);
    VALUE pre_args = t->nd_val1, rest_arg = t->nd_val2, post_args = t->nd_val3;

    if (!NIL_P(pre_arg)) {
        if (!NIL_P(pre_args)) {
            rb_ary_unshift(pre_args, pre_arg);
        }
        else {
            pre_args = rb_ary_new_from_args(1, pre_arg);
        }
    }
    return dispatch4(aryptn, constant, pre_args, rest_arg, post_args);
}

static VALUE
new_array_pattern_tail(struct parser_params *p, VALUE pre_args, VALUE has_rest, VALUE rest_arg, VALUE post_args, const YYLTYPE *loc)
{
    return ripper_new_yylval2(p, pre_args, rest_arg, post_args);
}

static VALUE
new_find_pattern(struct parser_params *p, VALUE constant, VALUE fndptn, const YYLTYPE *loc)
{
    struct RNode_RIPPER_VALUES *t = RNODE_RIPPER_VALUES(fndptn);
    VALUE pre_rest_arg = t->nd_val1, args = t->nd_val2, post_rest_arg = t->nd_val3;

    return dispatch4(fndptn, constant, pre_rest_arg, args, post_rest_arg);
}

static VALUE
new_find_pattern_tail(struct parser_params *p, VALUE pre_rest_arg, VALUE args, VALUE post_rest_arg, const YYLTYPE *loc)
{
    return ripper_new_yylval2(p, pre_rest_arg, args, post_rest_arg);
}

#define new_hash(p,h,l) rb_ary_new_from_args(0)

static VALUE
new_unique_key_hash(struct parser_params *p, VALUE ary, const YYLTYPE *loc)
{
    return ary;
}

static VALUE
new_hash_pattern(struct parser_params *p, VALUE constant, VALUE hshptn, const YYLTYPE *loc)
{
    struct RNode_RIPPER_VALUES *t = RNODE_RIPPER_VALUES(hshptn);
    VALUE kw_args = t->nd_val1, kw_rest_arg = t->nd_val2;
    return dispatch3(hshptn, constant, kw_args, kw_rest_arg);
}

static VALUE
new_hash_pattern_tail(struct parser_params *p, VALUE kw_args, VALUE kw_rest_arg, const YYLTYPE *loc)
{
    if (kw_rest_arg) {
        kw_rest_arg = dispatch1(var_field, kw_rest_arg);
    }
    else {
        kw_rest_arg = Qnil;
    }
    return ripper_new_yylval2(p, kw_args, kw_rest_arg, Qnil);
}

#define new_defined(p,expr,loc) dispatch1(defined, (expr))

static VALUE heredoc_dedent(struct parser_params*,VALUE);

#else
#define ID2VAL(id) (id)
#define TOKEN2VAL(t) ID2VAL(t)
#define KWD2EID(t, v) keyword_##t

static NODE *
new_scope_body(struct parser_params *p, rb_node_args_t *args, NODE *body, const YYLTYPE *loc)
{
    body = remove_begin(body);
    reduce_nodes(p, &body);
    NODE *n = NEW_SCOPE(args, body, loc);
    nd_set_line(n, loc->end_pos.lineno);
    set_line_body(body, loc->beg_pos.lineno);
    return n;
}

static NODE *
rescued_expr(struct parser_params *p, NODE *arg, NODE *rescue,
             const YYLTYPE *arg_loc, const YYLTYPE *mod_loc, const YYLTYPE *res_loc)
{
    YYLTYPE loc = code_loc_gen(mod_loc, res_loc);
    rescue = NEW_RESBODY(0, remove_begin(rescue), 0, &loc);
    loc.beg_pos = arg_loc->beg_pos;
    return NEW_RESCUE(arg, rescue, 0, &loc);
}

#endif /* RIPPER */

static NODE *add_block_exit(struct parser_params *p, NODE *node);
static rb_node_exits_t *init_block_exit(struct parser_params *p);
static rb_node_exits_t *allow_block_exit(struct parser_params *p);
static void restore_block_exit(struct parser_params *p, rb_node_exits_t *exits);
static void clear_block_exit(struct parser_params *p, bool error);

static void
next_rescue_context(struct lex_context *next, const struct lex_context *outer, enum rescue_context def)
{
    next->in_rescue = outer->in_rescue == after_rescue ? after_rescue : def;
}

static void
restore_defun(struct parser_params *p, rb_node_def_temp_t *temp)
{
    /* See: def_name action */
    struct lex_context ctxt = temp->save.ctxt;
    p->cur_arg = temp->save.cur_arg;
    p->ctxt.in_def = ctxt.in_def;
    p->ctxt.shareable_constant_value = ctxt.shareable_constant_value;
    p->ctxt.in_rescue = ctxt.in_rescue;
    p->max_numparam = temp->save.max_numparam;
    numparam_pop(p, temp->save.numparam_save);
    clear_block_exit(p, true);
}

static void
endless_method_name(struct parser_params *p, ID mid, const YYLTYPE *loc)
{
    if (is_attrset_id(mid)) {
        yyerror1(loc, "setter method cannot be defined in an endless method definition");
    }
    token_info_drop(p, "def", loc->beg_pos);
}

#define debug_token_line(p, name, line) do { \
        if (p->debug) { \
            const char *const pcur = p->lex.pcur; \
            const char *const ptok = p->lex.ptok; \
            rb_parser_printf(p, name ":%d (%d: %"PRIdPTRDIFF"|%"PRIdPTRDIFF"|%"PRIdPTRDIFF")\n", \
                             line, p->ruby_sourceline, \
                             ptok - p->lex.pbeg, pcur - ptok, p->lex.pend - pcur); \
        } \
    } while (0)

#define begin_definition(k, loc_beg, loc_end) \
    do { \
        if (!(p->ctxt.in_class = (k)[0] != 0)) { \
            p->ctxt.in_def = 0; \
        } \
        else if (p->ctxt.in_def) { \
            YYLTYPE loc = code_loc_gen(loc_beg, loc_end); \
            yyerror1(&loc, k " definition in method body"); \
        } \
        local_push(p, 0); \
    } while (0)

#ifndef RIPPER
# define Qnone 0
# define Qnull 0
# define ifndef_ripper(x) (x)
#else
# define Qnone Qnil
# define Qnull Qundef
# define ifndef_ripper(x)
#endif

# define rb_warn0(fmt)         WARN_CALL(WARN_ARGS(fmt, 1))
# define rb_warn1(fmt,a)       WARN_CALL(WARN_ARGS(fmt, 2), (a))
# define rb_warn2(fmt,a,b)     WARN_CALL(WARN_ARGS(fmt, 3), (a), (b))
# define rb_warn3(fmt,a,b,c)   WARN_CALL(WARN_ARGS(fmt, 4), (a), (b), (c))
# define rb_warn4(fmt,a,b,c,d) WARN_CALL(WARN_ARGS(fmt, 5), (a), (b), (c), (d))
# define rb_warning0(fmt)         WARNING_CALL(WARNING_ARGS(fmt, 1))
# define rb_warning1(fmt,a)       WARNING_CALL(WARNING_ARGS(fmt, 2), (a))
# define rb_warning2(fmt,a,b)     WARNING_CALL(WARNING_ARGS(fmt, 3), (a), (b))
# define rb_warning3(fmt,a,b,c)   WARNING_CALL(WARNING_ARGS(fmt, 4), (a), (b), (c))
# define rb_warning4(fmt,a,b,c,d) WARNING_CALL(WARNING_ARGS(fmt, 5), (a), (b), (c), (d))
# define rb_warn0L(l,fmt)         WARN_CALL(WARN_ARGS_L(l, fmt, 1))
# define rb_warn1L(l,fmt,a)       WARN_CALL(WARN_ARGS_L(l, fmt, 2), (a))
# define rb_warn2L(l,fmt,a,b)     WARN_CALL(WARN_ARGS_L(l, fmt, 3), (a), (b))
# define rb_warn3L(l,fmt,a,b,c)   WARN_CALL(WARN_ARGS_L(l, fmt, 4), (a), (b), (c))
# define rb_warn4L(l,fmt,a,b,c,d) WARN_CALL(WARN_ARGS_L(l, fmt, 5), (a), (b), (c), (d))
# define rb_warning0L(l,fmt)         WARNING_CALL(WARNING_ARGS_L(l, fmt, 1))
# define rb_warning1L(l,fmt,a)       WARNING_CALL(WARNING_ARGS_L(l, fmt, 2), (a))
# define rb_warning2L(l,fmt,a,b)     WARNING_CALL(WARNING_ARGS_L(l, fmt, 3), (a), (b))
# define rb_warning3L(l,fmt,a,b,c)   WARNING_CALL(WARNING_ARGS_L(l, fmt, 4), (a), (b), (c))
# define rb_warning4L(l,fmt,a,b,c,d) WARNING_CALL(WARNING_ARGS_L(l, fmt, 5), (a), (b), (c), (d))
#ifdef RIPPER
extern const ID id_warn, id_warning, id_gets, id_assoc;
# define ERR_MESG() STR_NEW2(mesg) /* to bypass Ripper DSL */
# define WARN_S_L(s,l) STR_NEW(s,l)
# define WARN_S(s) STR_NEW2(s)
# define WARN_I(i) INT2NUM(i)
# define WARN_ID(i) rb_id2str(i)
# define WARN_IVAL(i) i
# define PRIsWARN "s"
# define rb_warn0L_experimental(l,fmt)         WARN_CALL(WARN_ARGS_L(l, fmt, 1))
# define WARN_ARGS(fmt,n) p->value, id_warn, n, rb_usascii_str_new_lit(fmt)
# define WARN_ARGS_L(l,fmt,n) WARN_ARGS(fmt,n)
# ifdef HAVE_VA_ARGS_MACRO
# define WARN_CALL(...) rb_funcall(__VA_ARGS__)
# else
# define WARN_CALL rb_funcall
# endif
# define WARNING_ARGS(fmt,n) p->value, id_warning, n, rb_usascii_str_new_lit(fmt)
# define WARNING_ARGS_L(l, fmt,n) WARNING_ARGS(fmt,n)
# ifdef HAVE_VA_ARGS_MACRO
# define WARNING_CALL(...) rb_funcall(__VA_ARGS__)
# else
# define WARNING_CALL rb_funcall
# endif
# define compile_error ripper_compile_error
#else
# define WARN_S_L(s,l) s
# define WARN_S(s) s
# define WARN_I(i) i
# define WARN_ID(i) rb_id2name(i)
# define WARN_IVAL(i) NUM2INT(i)
# define PRIsWARN PRIsVALUE
# define WARN_ARGS(fmt,n) WARN_ARGS_L(p->ruby_sourceline,fmt,n)
# define WARN_ARGS_L(l,fmt,n) p->ruby_sourcefile, (l), (fmt)
# define WARN_CALL rb_compile_warn
# define rb_warn0L_experimental(l,fmt) rb_category_compile_warn(RB_WARN_CATEGORY_EXPERIMENTAL, WARN_ARGS_L(l, fmt, 1))
# define WARNING_ARGS(fmt,n) WARN_ARGS(fmt,n)
# define WARNING_ARGS_L(l,fmt,n) WARN_ARGS_L(l,fmt,n)
# define WARNING_CALL rb_compile_warning
PRINTF_ARGS(static void parser_compile_error(struct parser_params*, const rb_code_location_t *loc, const char *fmt, ...), 3, 4);
# define compile_error(p, ...) parser_compile_error(p, NULL, __VA_ARGS__)
#endif

struct RNode_EXITS {
    NODE node;

    NODE *nd_chain; /* Assume NODE_BREAK, NODE_NEXT, NODE_REDO have nd_chain here */
    NODE *nd_end;
};

#define RNODE_EXITS(node) ((rb_node_exits_t*)(node))

static NODE *
add_block_exit(struct parser_params *p, NODE *node)
{
    if (!node) {
        compile_error(p, "unexpected null node");
        return 0;
    }
    switch (nd_type(node)) {
      case NODE_BREAK: case NODE_NEXT: case NODE_REDO: break;
      default:
        compile_error(p, "unexpected node: %s", parser_node_name(nd_type(node)));
        return node;
    }
    if (!p->ctxt.in_defined) {
        rb_node_exits_t *exits = p->exits;
        if (exits) {
            RNODE_EXITS(exits->nd_end)->nd_chain = node;
            exits->nd_end = node;
        }
    }
    return node;
}

static rb_node_exits_t *
init_block_exit(struct parser_params *p)
{
    rb_node_exits_t *old = p->exits;
    rb_node_exits_t *exits = NODE_NEW_INTERNAL(NODE_EXITS, rb_node_exits_t);
    exits->nd_chain = 0;
    exits->nd_end = RNODE(exits);
    p->exits = exits;
    return old;
}

static rb_node_exits_t *
allow_block_exit(struct parser_params *p)
{
    rb_node_exits_t *exits = p->exits;
    p->exits = 0;
    return exits;
}

static void
restore_block_exit(struct parser_params *p, rb_node_exits_t *exits)
{
    p->exits = exits;
}

static void
clear_block_exit(struct parser_params *p, bool error)
{
    rb_node_exits_t *exits = p->exits;
    if (!exits) return;
    if (error && !compile_for_eval) {
        for (NODE *e = RNODE(exits); (e = RNODE_EXITS(e)->nd_chain) != 0; ) {
            switch (nd_type(e)) {
              case NODE_BREAK:
                yyerror1(&e->nd_loc, "Invalid break");
                break;
              case NODE_NEXT:
                yyerror1(&e->nd_loc, "Invalid next");
                break;
              case NODE_REDO:
                yyerror1(&e->nd_loc, "Invalid redo");
                break;
              default:
                yyerror1(&e->nd_loc, "unexpected node");
                goto end_checks; /* no nd_chain */
            }
        }
      end_checks:;
    }
    exits->nd_end = RNODE(exits);
    exits->nd_chain = 0;
}

#define WARN_EOL(tok) \
    (looking_at_eol_p(p) ? \
     (void)rb_warning0("`" tok "' at the end of line without an expression") : \
     (void)0)
static int looking_at_eol_p(struct parser_params *p);

#ifndef RIPPER
static NODE *
get_nd_value(struct parser_params *p, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_GASGN:
        return RNODE_GASGN(node)->nd_value;
      case NODE_IASGN:
        return RNODE_IASGN(node)->nd_value;
      case NODE_LASGN:
        return RNODE_LASGN(node)->nd_value;
      case NODE_DASGN:
        return RNODE_DASGN(node)->nd_value;
      case NODE_MASGN:
        return RNODE_MASGN(node)->nd_value;
      case NODE_CVASGN:
        return RNODE_CVASGN(node)->nd_value;
      case NODE_CDECL:
        return RNODE_CDECL(node)->nd_value;
      default:
        compile_error(p, "unexpected node: %s", parser_node_name(nd_type(node)));
        return 0;
    }
}

static void
set_nd_value(struct parser_params *p, NODE *node, NODE *rhs)
{
    switch (nd_type(node)) {
      case NODE_CDECL:
        RNODE_CDECL(node)->nd_value = rhs;
        break;
      case NODE_GASGN:
        RNODE_GASGN(node)->nd_value = rhs;
        break;
      case NODE_IASGN:
        RNODE_IASGN(node)->nd_value = rhs;
        break;
      case NODE_LASGN:
        RNODE_LASGN(node)->nd_value = rhs;
        break;
      case NODE_DASGN:
        RNODE_DASGN(node)->nd_value = rhs;
        break;
      case NODE_MASGN:
        RNODE_MASGN(node)->nd_value = rhs;
        break;
      case NODE_CVASGN:
        RNODE_CVASGN(node)->nd_value = rhs;
        break;
      default:
        compile_error(p, "unexpected node: %s", parser_node_name(nd_type(node)));
        break;
    }
}

static ID
get_nd_vid(struct parser_params *p, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_CDECL:
        return RNODE_CDECL(node)->nd_vid;
      case NODE_GASGN:
        return RNODE_GASGN(node)->nd_vid;
      case NODE_IASGN:
        return RNODE_IASGN(node)->nd_vid;
      case NODE_LASGN:
        return RNODE_LASGN(node)->nd_vid;
      case NODE_DASGN:
        return RNODE_DASGN(node)->nd_vid;
      case NODE_CVASGN:
        return RNODE_CVASGN(node)->nd_vid;
      default:
        compile_error(p, "unexpected node: %s", parser_node_name(nd_type(node)));
        return 0;
    }
}

static NODE *
get_nd_args(struct parser_params *p, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_CALL:
        return RNODE_CALL(node)->nd_args;
      case NODE_OPCALL:
        return RNODE_OPCALL(node)->nd_args;
      case NODE_FCALL:
        return RNODE_FCALL(node)->nd_args;
      case NODE_QCALL:
        return RNODE_QCALL(node)->nd_args;
      case NODE_VCALL:
      case NODE_SUPER:
      case NODE_ZSUPER:
      case NODE_YIELD:
      case NODE_RETURN:
      case NODE_BREAK:
      case NODE_NEXT:
        return 0;
      default:
        compile_error(p, "unexpected node: %s", parser_node_name(nd_type(node)));
        return 0;
    }
}
#endif
%}

%expect 0
%define api.pure
%define parse.error verbose
%printer {
#ifndef RIPPER
    if ((NODE *)$$ == (NODE *)-1) {
        rb_parser_printf(p, "NODE_SPECIAL");
    }
    else if ($$) {
        rb_parser_printf(p, "%s", parser_node_name(nd_type(RNODE($$))));
    }
#else
#endif
} <node> <node_fcall> <node_args> <node_args_aux> <node_opt_arg> <node_kw_arg> <node_block_pass>
%printer {
#ifndef RIPPER
    rb_parser_printf(p, "%"PRIsVALUE, rb_id2str($$));
#else
    rb_parser_printf(p, "%"PRIsVALUE, RNODE_RIPPER($$)->nd_rval);
#endif
} tIDENTIFIER tFID tGVAR tIVAR tCONSTANT tCVAR tLABEL tOP_ASGN
%printer {
#ifndef RIPPER
    rb_parser_printf(p, "%+"PRIsVALUE, RNODE_LIT($$)->nd_lit);
#else
    rb_parser_printf(p, "%+"PRIsVALUE, get_value($$));
#endif
} tINTEGER tFLOAT tRATIONAL tIMAGINARY tSTRING_CONTENT tCHAR
%printer {
#ifndef RIPPER
    rb_parser_printf(p, "$%ld", RNODE_NTH_REF($$)->nd_nth);
#else
    rb_parser_printf(p, "%"PRIsVALUE, $$);
#endif
} tNTH_REF
%printer {
#ifndef RIPPER
    rb_parser_printf(p, "$%c", (int)RNODE_BACK_REF($$)->nd_nth);
#else
    rb_parser_printf(p, "%"PRIsVALUE, $$);
#endif
} tBACK_REF

%lex-param {struct parser_params *p}
%parse-param {struct parser_params *p}
%initial-action
{
    RUBY_SET_YYLLOC_OF_NONE(@$);
};

%union {
    VALUE val;
    NODE *node;
    rb_node_fcall_t *node_fcall;
    rb_node_args_t *node_args;
    rb_node_args_aux_t *node_args_aux;
    rb_node_opt_arg_t *node_opt_arg;
    rb_node_kw_arg_t *node_kw_arg;
    rb_node_block_pass_t *node_block_pass;
    rb_node_masgn_t *node_masgn;
    rb_node_def_temp_t *node_def_temp;
    rb_node_exits_t *node_exits;
    ID id;
    int num;
    st_table *tbl;
    const struct vtable *vars;
    struct rb_strterm_struct *strterm;
    struct lex_context ctxt;
}

%token <id>
        keyword_class        "`class'"
        keyword_module       "`module'"
        keyword_def          "`def'"
        keyword_undef        "`undef'"
        keyword_begin        "`begin'"
        keyword_rescue       "`rescue'"
        keyword_ensure       "`ensure'"
        keyword_end          "`end'"
        keyword_if           "`if'"
        keyword_unless       "`unless'"
        keyword_then         "`then'"
        keyword_elsif        "`elsif'"
        keyword_else         "`else'"
        keyword_case         "`case'"
        keyword_when         "`when'"
        keyword_while        "`while'"
        keyword_until        "`until'"
        keyword_for          "`for'"
        keyword_break        "`break'"
        keyword_next         "`next'"
        keyword_redo         "`redo'"
        keyword_retry        "`retry'"
        keyword_in           "`in'"
        keyword_do           "`do'"
        keyword_do_cond      "`do' for condition"
        keyword_do_block     "`do' for block"
        keyword_do_LAMBDA    "`do' for lambda"
        keyword_return       "`return'"
        keyword_yield        "`yield'"
        keyword_super        "`super'"
        keyword_self         "`self'"
        keyword_nil          "`nil'"
        keyword_true         "`true'"
        keyword_false        "`false'"
        keyword_and          "`and'"
        keyword_or           "`or'"
        keyword_not          "`not'"
        modifier_if          "`if' modifier"
        modifier_unless      "`unless' modifier"
        modifier_while       "`while' modifier"
        modifier_until       "`until' modifier"
        modifier_rescue      "`rescue' modifier"
        keyword_alias        "`alias'"
        keyword_defined      "`defined?'"
        keyword_BEGIN        "`BEGIN'"
        keyword_END          "`END'"
        keyword__LINE__      "`__LINE__'"
        keyword__FILE__      "`__FILE__'"
        keyword__ENCODING__  "`__ENCODING__'"

%token <id>   tIDENTIFIER    "local variable or method"
%token <id>   tFID           "method"
%token <id>   tGVAR          "global variable"
%token <id>   tIVAR          "instance variable"
%token <id>   tCONSTANT      "constant"
%token <id>   tCVAR          "class variable"
%token <id>   tLABEL         "label"
%token <node> tINTEGER       "integer literal"
%token <node> tFLOAT         "float literal"
%token <node> tRATIONAL      "rational literal"
%token <node> tIMAGINARY     "imaginary literal"
%token <node> tCHAR          "char literal"
%token <node> tNTH_REF       "numbered reference"
%token <node> tBACK_REF      "back reference"
%token <node> tSTRING_CONTENT "literal content"
%token <num>  tREGEXP_END
%token <num>  tDUMNY_END     "dummy end"

%type <node> singleton strings string string1 xstring regexp
%type <node> string_contents xstring_contents regexp_contents string_content
%type <node> words symbols symbol_list qwords qsymbols word_list qword_list qsym_list word
%type <node> literal numeric simple_numeric ssym dsym symbol cpath
/*ripper*/ %type <node_def_temp> defn_head defs_head k_def
/*ripper*/ %type <node_exits> block_open k_while k_until k_for allow_exits
%type <node> top_compstmt top_stmts top_stmt begin_block endless_arg endless_command
%type <node> bodystmt compstmt stmts stmt_or_begin stmt expr arg primary command command_call method_call
%type <node> expr_value expr_value_do arg_value primary_value rel_expr
%type <node_fcall> fcall
%type <node> if_tail opt_else case_body case_args cases opt_rescue exc_list exc_var opt_ensure
%type <node> args arg_splat call_args opt_call_args
%type <node> paren_args opt_paren_args
%type <node_args> args_tail opt_args_tail block_args_tail opt_block_args_tail
%type <node> command_args aref_args
%type <node_block_pass> opt_block_arg block_arg
%type <node> var_ref var_lhs
%type <node> command_rhs arg_rhs
%type <node> command_asgn mrhs mrhs_arg superclass block_call block_command
%type <node_opt_arg> f_block_optarg f_block_opt
%type <node_args> f_arglist f_opt_paren_args f_paren_args f_args
%type <node_args_aux> f_arg f_arg_item
%type <node_opt_arg> f_optarg
%type <node> f_marg f_marg_list f_rest_marg
%type <node_masgn> f_margs
%type <node> assoc_list assocs assoc undef_list backref string_dvar for_var
%type <node_args> block_param opt_block_param block_param_def
%type <node_opt_arg> f_opt
%type <node_kw_arg> f_kwarg f_kw f_block_kwarg f_block_kw
%type <node> bv_decls opt_bv_decl bvar
%type <node> lambda lambda_body brace_body do_body
%type <node_args> f_larglist
%type <node> brace_block cmd_brace_block do_block lhs none fitem
%type <node> mlhs_head mlhs_item mlhs_node mlhs_post
%type <node_masgn> mlhs mlhs_basic mlhs_inner
%type <node> p_case_body p_cases p_top_expr p_top_expr_body
%type <node> p_expr p_as p_alt p_expr_basic p_find
%type <node> p_args p_args_head p_args_tail p_args_post p_arg p_rest
%type <node> p_value p_primitive p_variable p_var_ref p_expr_ref p_const
%type <node> p_kwargs p_kwarg p_kw
%type <id>   keyword_variable user_variable sym operation operation2 operation3
%type <id>   cname fname op f_rest_arg f_block_arg opt_f_block_arg f_norm_arg f_bad_arg
%type <id>   f_kwrest f_label f_arg_asgn call_op call_op2 reswords relop dot_or_colon
%type <id>   p_kwrest p_kwnorest p_any_kwrest p_kw_label
%type <id>   f_no_kwarg f_any_kwrest args_forward excessed_comma nonlocal_var def_name
%type <ctxt> lex_ctxt begin_defined k_class k_module k_END k_rescue k_ensure after_rescue
%type <ctxt> p_in_kwarg
%type <tbl>  p_lparen p_lbracket p_pktbl p_pvtbl
/* ripper */ %type <num>  max_numparam
/* ripper */ %type <node> numparam
%token END_OF_INPUT 0	"end-of-input"
%token <id> '.'

/* escaped chars, should be ignored otherwise */
%token <id> '\\'	"backslash"
%token tSP		"escaped space"
%token <id> '\t' 	"escaped horizontal tab"
%token <id> '\f'	"escaped form feed"
%token <id> '\r'	"escaped carriage return"
%token <id> '\13'	"escaped vertical tab"
%token tUPLUS		RUBY_TOKEN(UPLUS)  "unary+"
%token tUMINUS		RUBY_TOKEN(UMINUS) "unary-"
%token tPOW		RUBY_TOKEN(POW)    "**"
%token tCMP		RUBY_TOKEN(CMP)    "<=>"
%token tEQ		RUBY_TOKEN(EQ)     "=="
%token tEQQ		RUBY_TOKEN(EQQ)    "==="
%token tNEQ		RUBY_TOKEN(NEQ)    "!="
%token tGEQ		RUBY_TOKEN(GEQ)    ">="
%token tLEQ		RUBY_TOKEN(LEQ)    "<="
%token tANDOP		RUBY_TOKEN(ANDOP)  "&&"
%token tOROP		RUBY_TOKEN(OROP)   "||"
%token tMATCH		RUBY_TOKEN(MATCH)  "=~"
%token tNMATCH		RUBY_TOKEN(NMATCH) "!~"
%token tDOT2		RUBY_TOKEN(DOT2)   ".."
%token tDOT3		RUBY_TOKEN(DOT3)   "..."
%token tBDOT2		RUBY_TOKEN(BDOT2)   "(.."
%token tBDOT3		RUBY_TOKEN(BDOT3)   "(..."
%token tAREF		RUBY_TOKEN(AREF)   "[]"
%token tASET		RUBY_TOKEN(ASET)   "[]="
%token tLSHFT		RUBY_TOKEN(LSHFT)  "<<"
%token tRSHFT		RUBY_TOKEN(RSHFT)  ">>"
%token <id> tANDDOT	RUBY_TOKEN(ANDDOT) "&."
%token <id> tCOLON2	RUBY_TOKEN(COLON2) "::"
%token tCOLON3		":: at EXPR_BEG"
%token <id> tOP_ASGN	"operator-assignment" /* +=, -=  etc. */
%token tASSOC		"=>"
%token tLPAREN		"("
%token tLPAREN_ARG	"( arg"
%token tRPAREN		")"
%token tLBRACK		"["
%token tLBRACE		"{"
%token tLBRACE_ARG	"{ arg"
%token tSTAR		"*"
%token tDSTAR		"**arg"
%token tAMPER		"&"
%token tLAMBDA		"->"
%token tSYMBEG		"symbol literal"
%token tSTRING_BEG	"string literal"
%token tXSTRING_BEG	"backtick literal"
%token tREGEXP_BEG	"regexp literal"
%token tWORDS_BEG	"word list"
%token tQWORDS_BEG	"verbatim word list"
%token tSYMBOLS_BEG	"symbol list"
%token tQSYMBOLS_BEG	"verbatim symbol list"
%token tSTRING_END	"terminator"
%token tSTRING_DEND	"'}'"
%token tSTRING_DBEG tSTRING_DVAR tLAMBEG tLABEL_END

%token tIGNORED_NL tCOMMENT tEMBDOC_BEG tEMBDOC tEMBDOC_END
%token tHEREDOC_BEG tHEREDOC_END k__END__

/*
 *	precedence table
 */

%nonassoc tLOWEST
%nonassoc tLBRACE_ARG

%nonassoc  modifier_if modifier_unless modifier_while modifier_until keyword_in
%left  keyword_or keyword_and
%right keyword_not
%nonassoc keyword_defined
%right '=' tOP_ASGN
%left modifier_rescue
%right '?' ':'
%nonassoc tDOT2 tDOT3 tBDOT2 tBDOT3
%left  tOROP
%left  tANDOP
%nonassoc  tCMP tEQ tEQQ tNEQ tMATCH tNMATCH
%left  '>' tGEQ '<' tLEQ
%left  '|' '^'
%left  '&'
%left  tLSHFT tRSHFT
%left  '+' '-'
%left  '*' '/' '%'
%right tUMINUS_NUM tUMINUS
%right tPOW
%right '!' '~' tUPLUS

%token tLAST_TOKEN

%%
program		:  {
                        SET_LEX_STATE(EXPR_BEG);
                        local_push(p, ifndef_ripper(1)+0);
                        /* jumps are possible in the top-level loop. */
                        if (!ifndef_ripper(p->do_loop) + 0) init_block_exit(p);
                    }
                  top_compstmt
                    {
                    /*%%%*/
                        if ($2 && !compile_for_eval) {
                            NODE *node = $2;
                            /* last expression should not be void */
                            if (nd_type_p(node, NODE_BLOCK)) {
                                while (RNODE_BLOCK(node)->nd_next) {
                                    node = RNODE_BLOCK(node)->nd_next;
                                }
                                node = RNODE_BLOCK(node)->nd_head;
                            }
                            node = remove_begin(node);
                            void_expr(p, node);
                        }
                        p->eval_tree = NEW_SCOPE(0, block_append(p, p->eval_tree, $2), &@$);
                    /*% %*/
                    /*% ripper[final]: program!($2) %*/
                        local_pop(p);
                    }
                ;

top_compstmt	: top_stmts opt_terms
                    {
                        $$ = void_stmts(p, $1);
                    }
                ;

top_stmts	: none
                    {
                    /*%%%*/
                        $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper: stmts_add!(stmts_new!, void_stmt!) %*/
                    }
                | top_stmt
                    {
                    /*%%%*/
                        $$ = newline_node($1);
                    /*% %*/
                    /*% ripper: stmts_add!(stmts_new!, $1) %*/
                    }
                | top_stmts terms top_stmt
                    {
                    /*%%%*/
                        $$ = block_append(p, $1, newline_node($3));
                    /*% %*/
                    /*% ripper: stmts_add!($1, $3) %*/
                    }
                ;

top_stmt	: stmt
                    {
                        clear_block_exit(p, true);
                        $$ = $1;
                    }
                | keyword_BEGIN begin_block
                    {
                        $$ = $2;
                    }
                ;

block_open	: '{' {$$ = init_block_exit(p);};

begin_block	: block_open top_compstmt '}'
                    {
                        restore_block_exit(p, $block_open);
                    /*%%%*/
                        p->eval_tree_begin = block_append(p, p->eval_tree_begin,
                                                          NEW_BEGIN($2, &@$));
                        $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper: BEGIN!($2) %*/
                    }
                ;

bodystmt	: compstmt[body]
                  lex_ctxt[ctxt]
                  opt_rescue
                  k_else
                    {
                        if (!$opt_rescue) yyerror1(&@k_else, "else without rescue is useless");
                        next_rescue_context(&p->ctxt, &$ctxt, after_else);
                    }
                  compstmt[elsebody]
                    {
                        next_rescue_context(&p->ctxt, &$ctxt, after_ensure);
                    }
                  opt_ensure
                    {
                    /*%%%*/
                        $$ = new_bodystmt(p, $body, $opt_rescue, $elsebody, $opt_ensure, &@$);
                    /*% %*/
                    /*% ripper: bodystmt!($body, $opt_rescue, $elsebody, $opt_ensure) %*/
                    }
                | compstmt[body]
                  lex_ctxt[ctxt]
                  opt_rescue
                    {
                        next_rescue_context(&p->ctxt, &$ctxt, after_ensure);
                    }
                  opt_ensure
                    {
                    /*%%%*/
                        $$ = new_bodystmt(p, $body, $opt_rescue, 0, $opt_ensure, &@$);
                    /*% %*/
                    /*% ripper: bodystmt!($body, $opt_rescue, Qnil, $opt_ensure) %*/
                    }
                ;

compstmt	: stmts opt_terms
                    {
                        $$ = void_stmts(p, $1);
                    }
                ;

stmts		: none
                    {
                    /*%%%*/
                        $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper: stmts_add!(stmts_new!, void_stmt!) %*/
                    }
                | stmt_or_begin
                    {
                    /*%%%*/
                        $$ = newline_node($1);
                    /*% %*/
                    /*% ripper: stmts_add!(stmts_new!, $1) %*/
                    }
                | stmts terms stmt_or_begin
                    {
                    /*%%%*/
                        $$ = block_append(p, $1, newline_node($3));
                    /*% %*/
                    /*% ripper: stmts_add!($1, $3) %*/
                    }
                ;

stmt_or_begin	: stmt
                    {
                        $$ = $1;
                    }
                | keyword_BEGIN
                    {
                        yyerror1(&@1, "BEGIN is permitted only at toplevel");
                    }
                  begin_block
                    {
                        $$ = $3;
                    }
                ;

allow_exits	: {$$ = allow_block_exit(p);};

k_END		: keyword_END lex_ctxt
                    {
                        $$ = $2;
                        p->ctxt.in_rescue = before_rescue;
                    };

stmt		: keyword_alias fitem {SET_LEX_STATE(EXPR_FNAME|EXPR_FITEM);} fitem
                    {
                    /*%%%*/
                        $$ = NEW_ALIAS($2, $4, &@$);
                    /*% %*/
                    /*% ripper: alias!($2, $4) %*/
                    }
                | keyword_alias tGVAR tGVAR
                    {
                    /*%%%*/
                        $$ = NEW_VALIAS($2, $3, &@$);
                    /*% %*/
                    /*% ripper: var_alias!($2, $3) %*/
                    }
                | keyword_alias tGVAR tBACK_REF
                    {
                    /*%%%*/
                        char buf[2];
                        buf[0] = '$';
                        buf[1] = (char)RNODE_BACK_REF($3)->nd_nth;
                        $$ = NEW_VALIAS($2, rb_intern2(buf, 2), &@$);
                    /*% %*/
                    /*% ripper: var_alias!($2, $3) %*/
                    }
                | keyword_alias tGVAR tNTH_REF
                    {
                        static const char mesg[] = "can't make alias for the number variables";
                    /*%%%*/
                        yyerror1(&@3, mesg);
                        $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper[error]: alias_error!(ERR_MESG(), $3) %*/
                    }
                | keyword_undef undef_list
                    {
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: undef!($2) %*/
                    }
                | stmt modifier_if expr_value
                    {
                    /*%%%*/
                        $$ = new_if(p, $3, remove_begin($1), 0, &@$);
                        fixpos($$, $3);
                    /*% %*/
                    /*% ripper: if_mod!($3, $1) %*/
                    }
                | stmt modifier_unless expr_value
                    {
                    /*%%%*/
                        $$ = new_unless(p, $3, remove_begin($1), 0, &@$);
                        fixpos($$, $3);
                    /*% %*/
                    /*% ripper: unless_mod!($3, $1) %*/
                    }
                | stmt modifier_while expr_value
                    {
                        clear_block_exit(p, false);
                    /*%%%*/
                        if ($1 && nd_type_p($1, NODE_BEGIN)) {
                            $$ = NEW_WHILE(cond(p, $3, &@3), RNODE_BEGIN($1)->nd_body, 0, &@$);
                        }
                        else {
                            $$ = NEW_WHILE(cond(p, $3, &@3), $1, 1, &@$);
                        }
                    /*% %*/
                    /*% ripper: while_mod!($3, $1) %*/
                    }
                | stmt modifier_until expr_value
                    {
                        clear_block_exit(p, false);
                    /*%%%*/
                        if ($1 && nd_type_p($1, NODE_BEGIN)) {
                            $$ = NEW_UNTIL(cond(p, $3, &@3), RNODE_BEGIN($1)->nd_body, 0, &@$);
                        }
                        else {
                            $$ = NEW_UNTIL(cond(p, $3, &@3), $1, 1, &@$);
                        }
                    /*% %*/
                    /*% ripper: until_mod!($3, $1) %*/
                    }
                | stmt modifier_rescue after_rescue stmt
                    {
                        p->ctxt.in_rescue = $3.in_rescue;
                    /*%%%*/
                        NODE *resq;
                        YYLTYPE loc = code_loc_gen(&@2, &@4);
                        resq = NEW_RESBODY(0, remove_begin($4), 0, &loc);
                        $$ = NEW_RESCUE(remove_begin($1), resq, 0, &@$);
                    /*% %*/
                    /*% ripper: rescue_mod!($1, $4) %*/
                    }
                | k_END allow_exits '{' compstmt '}'
                    {
                        if (p->ctxt.in_def) {
                            rb_warn0("END in method; use at_exit");
                        }
                        restore_block_exit(p, $allow_exits);
                        p->ctxt = $k_END;
                    /*%%%*/
                        {
                            NODE *scope = NEW_SCOPE2(0 /* tbl */, 0 /* args */, $compstmt /* body */, &@$);
                            $$ = NEW_POSTEXE(scope, &@$);
                        }
                    /*% %*/
                    /*% ripper: END!($compstmt) %*/
                    }
                | command_asgn
                | mlhs '=' lex_ctxt command_call
                    {
                    /*%%%*/
                        value_expr($4);
                        $$ = node_assign(p, (NODE *)$1, $4, $3, &@$);
                    /*% %*/
                    /*% ripper: massign!($1, $4) %*/
                    }
                | lhs '=' lex_ctxt mrhs
                    {
                    /*%%%*/
                        $$ = node_assign(p, $1, $4, $3, &@$);
                    /*% %*/
                    /*% ripper: assign!($1, $4) %*/
                    }
                | mlhs '=' lex_ctxt mrhs_arg modifier_rescue
                  after_rescue stmt[resbody]
                    {
                        p->ctxt.in_rescue = $3.in_rescue;
                    /*%%%*/
                        YYLTYPE loc = code_loc_gen(&@modifier_rescue, &@resbody);
                        $resbody = NEW_RESBODY(0, remove_begin($resbody), 0, &loc);
                        loc.beg_pos = @mrhs_arg.beg_pos;
                        $mrhs_arg = NEW_RESCUE($mrhs_arg, $resbody, 0, &loc);
                        $$ = node_assign(p, (NODE *)$mlhs, $mrhs_arg, $lex_ctxt, &@$);
                    /*% %*/
                    /*% ripper: massign!($1, rescue_mod!($4, $7)) %*/
                    }
                | mlhs '=' lex_ctxt mrhs_arg
                    {
                    /*%%%*/
                        $$ = node_assign(p, (NODE *)$1, $4, $3, &@$);
                    /*% %*/
                    /*% ripper: massign!($1, $4) %*/
                    }
                | expr
                | error
                    {
                        (void)yynerrs;
                    /*%%%*/
                        $$ = NEW_ERROR(&@$);
                    /*% %*/
                    }
                ;

command_asgn	: lhs '=' lex_ctxt command_rhs
                    {
                    /*%%%*/
                        $$ = node_assign(p, $1, $4, $3, &@$);
                    /*% %*/
                    /*% ripper: assign!($1, $4) %*/
                    }
                | var_lhs tOP_ASGN lex_ctxt command_rhs
                    {
                    /*%%%*/
                        $$ = new_op_assign(p, $1, $2, $4, $3, &@$);
                    /*% %*/
                    /*% ripper: opassign!($1, $2, $4) %*/
                    }
                | primary_value '[' opt_call_args rbracket tOP_ASGN lex_ctxt command_rhs
                    {
                    /*%%%*/
                        $$ = new_ary_op_assign(p, $1, $3, $5, $7, &@3, &@$);
                    /*% %*/
                    /*% ripper: opassign!(aref_field!($1, $3), $5, $7) %*/

                    }
                | primary_value call_op tIDENTIFIER tOP_ASGN lex_ctxt command_rhs
                    {
                    /*%%%*/
                        $$ = new_attr_op_assign(p, $1, $2, $3, $4, $6, &@$);
                    /*% %*/
                    /*% ripper: opassign!(field!($1, $2, $3), $4, $6) %*/
                    }
                | primary_value call_op tCONSTANT tOP_ASGN lex_ctxt command_rhs
                    {
                    /*%%%*/
                        $$ = new_attr_op_assign(p, $1, $2, $3, $4, $6, &@$);
                    /*% %*/
                    /*% ripper: opassign!(field!($1, $2, $3), $4, $6) %*/
                    }
                | primary_value tCOLON2 tCONSTANT tOP_ASGN lex_ctxt command_rhs
                    {
                    /*%%%*/
                        YYLTYPE loc = code_loc_gen(&@1, &@3);
                        $$ = new_const_op_assign(p, NEW_COLON2($1, $3, &loc), $4, $6, $5, &@$);
                    /*% %*/
                    /*% ripper: opassign!(const_path_field!($1, $3), $4, $6) %*/
                    }
                | primary_value tCOLON2 tIDENTIFIER tOP_ASGN lex_ctxt command_rhs
                    {
                    /*%%%*/
                        $$ = new_attr_op_assign(p, $1, ID2VAL(idCOLON2), $3, $4, $6, &@$);
                    /*% %*/
                    /*% ripper: opassign!(field!($1, $2, $3), $4, $6) %*/
                    }
                | defn_head[head] f_opt_paren_args[args] '=' endless_command[bodystmt]
                    {
                        endless_method_name(p, get_id($head->nd_mid), &@head);
                        restore_defun(p, $head);
                    /*%%%*/
                        $bodystmt = new_scope_body(p, $args, $bodystmt, &@$);
                        ($$ = $head->nd_def)->nd_loc = @$;
                        RNODE_DEFN($$)->nd_defn = $bodystmt;
                    /*% %*/
                    /*% ripper[$bodystmt]: bodystmt!($bodystmt, Qnil, Qnil, Qnil) %*/
                    /*% ripper: def!($head->nd_mid, $args, $bodystmt) %*/
                        local_pop(p);
                    }
                | defs_head[head] f_opt_paren_args[args] '=' endless_command[bodystmt]
                    {
                        endless_method_name(p, get_id($head->nd_mid), &@head);
                        restore_defun(p, $head);
                    /*%%%*/
                        $bodystmt = new_scope_body(p, $args, $bodystmt, &@$);
                        ($$ = $head->nd_def)->nd_loc = @$;
                        RNODE_DEFS($$)->nd_defn = $bodystmt;
                    /*% %*/
                    /*% ripper[$bodystmt]: bodystmt!($bodystmt, Qnil, Qnil, Qnil) %*/
                    /*% ripper: defs!($head->nd_recv, $head->dot_or_colon, $head->nd_mid, $args, $bodystmt) %*/
                        local_pop(p);
                    }
                | backref tOP_ASGN lex_ctxt command_rhs
                    {
                    /*%%%*/
                        rb_backref_error(p, $1);
                        $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper[error]: backref_error(p, RNODE($1), assign!(var_field(p, $1), $4)) %*/
                    }
                ;

endless_command : command
                | endless_command modifier_rescue after_rescue arg
                    {
                        p->ctxt.in_rescue = $3.in_rescue;
                    /*%%%*/
                        $$ = rescued_expr(p, $1, $4, &@1, &@2, &@4);
                    /*% %*/
                    /*% ripper: rescue_mod!($1, $4) %*/
                    }
                | keyword_not opt_nl endless_command
                    {
                        $$ = call_uni_op(p, method_cond(p, $3, &@3), METHOD_NOT, &@1, &@$);
                    }
                ;

command_rhs	: command_call   %prec tOP_ASGN
                    {
                        value_expr($1);
                        $$ = $1;
                    }
                | command_call modifier_rescue after_rescue stmt
                    {
                        p->ctxt.in_rescue = $3.in_rescue;
                    /*%%%*/
                        YYLTYPE loc = code_loc_gen(&@2, &@4);
                        value_expr($1);
                        $$ = NEW_RESCUE($1, NEW_RESBODY(0, remove_begin($4), 0, &loc), 0, &@$);
                    /*% %*/
                    /*% ripper: rescue_mod!($1, $4) %*/
                    }
                | command_asgn
                ;

expr		: command_call
                | expr keyword_and expr
                    {
                        $$ = logop(p, idAND, $1, $3, &@2, &@$);
                    }
                | expr keyword_or expr
                    {
                        $$ = logop(p, idOR, $1, $3, &@2, &@$);
                    }
                | keyword_not opt_nl expr
                    {
                        $$ = call_uni_op(p, method_cond(p, $3, &@3), METHOD_NOT, &@1, &@$);
                    }
                | '!' command_call
                    {
                        $$ = call_uni_op(p, method_cond(p, $2, &@2), '!', &@1, &@$);
                    }
                | arg tASSOC
                    {
                        value_expr($arg);
                    }
                  p_in_kwarg[ctxt] p_pvtbl p_pktbl
                  p_top_expr_body[body]
                    {
                        pop_pktbl(p, $p_pktbl);
                        pop_pvtbl(p, $p_pvtbl);
                        p->ctxt.in_kwarg = $ctxt.in_kwarg;
                    /*%%%*/
                        $$ = NEW_CASE3($arg, NEW_IN($body, 0, 0, &@body), &@$);
                    /*% %*/
                    /*% ripper: case!($arg, in!($body, Qnil, Qnil)) %*/
                    }
                | arg keyword_in
                    {
                        value_expr($arg);
                    }
                  p_in_kwarg[ctxt] p_pvtbl p_pktbl
                  p_top_expr_body[body]
                    {
                        pop_pktbl(p, $p_pktbl);
                        pop_pvtbl(p, $p_pvtbl);
                        p->ctxt.in_kwarg = $ctxt.in_kwarg;
                    /*%%%*/
                        $$ = NEW_CASE3($arg, NEW_IN($body, NEW_TRUE(&@body), NEW_FALSE(&@body), &@body), &@$);
                    /*% %*/
                    /*% ripper: case!($arg, in!($body, Qnil, Qnil)) %*/
                    }
                | arg %prec tLBRACE_ARG
                ;

def_name	: fname
                    {
                        ID fname = get_id($1);
                        numparam_name(p, fname);
                        local_push(p, 0);
                        p->cur_arg = 0;
                        p->ctxt.in_def = 1;
                        p->ctxt.in_rescue = before_rescue;
                        $$ = $1;
                    }
                ;

defn_head	: k_def def_name
                    {
                        $$ = def_head_save(p, $k_def);
                        $$->nd_mid = $def_name;
                    /*%%%*/
                        $$->nd_def = NEW_DEFN($def_name, 0, &@$);
                    /*%
                        add_mark_object(p, $def_name);
                    %*/
                    }
                ;

defs_head	: k_def singleton dot_or_colon
                    {
                        SET_LEX_STATE(EXPR_FNAME);
                        p->ctxt.in_argdef = 1;
                    }
                  def_name
                    {
                        SET_LEX_STATE(EXPR_ENDFN|EXPR_LABEL); /* force for args */
                        $$ = def_head_save(p, $k_def);
                        $$->nd_mid = $def_name;
                    /*%%%*/
                        $$->nd_def = NEW_DEFS($singleton, $def_name, 0, &@$);
                    /*%
                        add_mark_object(p, $def_name);
                        $$->nd_recv = add_mark_object(p, $singleton);
                        $$->dot_or_colon = add_mark_object(p, $dot_or_colon);
                    %*/
                    }
                ;

expr_value	: expr
                    {
                        value_expr($1);
                        $$ = $1;
                    }
                | error
                    {
                    /*%%%*/
                        $$ = NEW_ERROR(&@$);
                    /*% %*/
                    }
                ;

expr_value_do	: {COND_PUSH(1);} expr_value do {COND_POP();}
                    {
                        $$ = $2;
                    }
                ;

command_call	: command
                | block_command
                ;

block_command	: block_call
                | block_call call_op2 operation2 command_args
                    {
                    /*%%%*/
                        $$ = new_qcall(p, $2, $1, $3, $4, &@3, &@$);
                    /*% %*/
                    /*% ripper: method_add_arg!(call!($1, $2, $3), $4) %*/
                    }
                ;

cmd_brace_block	: tLBRACE_ARG brace_body '}'
                    {
                        $$ = $2;
                    /*%%%*/
                        set_embraced_location($$, &@1, &@3);
                    /*% %*/
                    }
                ;

fcall		: operation
                    {
                    /*%%%*/
                        $$ = NEW_FCALL($1, 0, &@$);
                    /*% %*/
                    /*% ripper: $1 %*/
                    }
                ;

command		: fcall command_args       %prec tLOWEST
                    {
                    /*%%%*/
                        $1->nd_args = $2;
                        nd_set_last_loc($1, @2.end_pos);
                        $$ = (NODE *)$1;
                    /*% %*/
                    /*% ripper: command!($1, $2) %*/
                    }
                | fcall command_args cmd_brace_block
                    {
                    /*%%%*/
                        block_dup_check(p, $2, $3);
                        $1->nd_args = $2;
                        $$ = method_add_block(p, (NODE *)$1, $3, &@$);
                        fixpos($$, RNODE($1));
                        nd_set_last_loc($1, @2.end_pos);
                    /*% %*/
                    /*% ripper: method_add_block!(command!($1, $2), $3) %*/
                    }
                | primary_value call_op operation2 command_args	%prec tLOWEST
                    {
                    /*%%%*/
                        $$ = new_command_qcall(p, $2, $1, $3, $4, Qnull, &@3, &@$);
                    /*% %*/
                    /*% ripper: command_call!($1, $2, $3, $4) %*/
                    }
                | primary_value call_op operation2 command_args cmd_brace_block
                    {
                    /*%%%*/
                        $$ = new_command_qcall(p, $2, $1, $3, $4, $5, &@3, &@$);
                    /*% %*/
                    /*% ripper: method_add_block!(command_call!($1, $2, $3, $4), $5) %*/
                    }
                | primary_value tCOLON2 operation2 command_args	%prec tLOWEST
                    {
                    /*%%%*/
                        $$ = new_command_qcall(p, ID2VAL(idCOLON2), $1, $3, $4, Qnull, &@3, &@$);
                    /*% %*/
                    /*% ripper: command_call!($1, $2, $3, $4) %*/
                    }
                | primary_value tCOLON2 operation2 command_args cmd_brace_block
                    {
                    /*%%%*/
                        $$ = new_command_qcall(p, ID2VAL(idCOLON2), $1, $3, $4, $5, &@3, &@$);
                    /*% %*/
                    /*% ripper: method_add_block!(command_call!($1, $2, $3, $4), $5) %*/
                   }
                | primary_value tCOLON2 tCONSTANT '{' brace_body '}'
                    {
                    /*%%%*/
                        set_embraced_location($5, &@4, &@6);
                        $$ = new_command_qcall(p, ID2VAL(idCOLON2), $1, $3, Qnull, $5, &@3, &@$);
                    /*% %*/
                    /*% ripper: method_add_block!(command_call!($1, $2, $3, Qnull), $5) %*/
                   }
                | keyword_super command_args
                    {
                    /*%%%*/
                        $$ = NEW_SUPER($2, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: super!($2) %*/
                    }
                | k_yield command_args
                    {
                    /*%%%*/
                        $$ = new_yield(p, $2, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: yield!($2) %*/
                    }
                | k_return call_args
                    {
                    /*%%%*/
                        $$ = NEW_RETURN(ret_args(p, $2), &@$);
                    /*% %*/
                    /*% ripper: return!($2) %*/
                    }
                | keyword_break call_args
                    {
                        NODE *args = 0;
                    /*%%%*/
                        args = ret_args(p, $2);
                    /*% %*/
                        $<node>$ = add_block_exit(p, NEW_BREAK(args, &@$));
                    /*% ripper: break!($2) %*/
                    }
                | keyword_next call_args
                    {
                        NODE *args = 0;
                    /*%%%*/
                        args = ret_args(p, $2);
                    /*% %*/
                        $<node>$ = add_block_exit(p, NEW_NEXT(args, &@$));
                    /*% ripper: next!($2) %*/
                    }
                ;

mlhs		: mlhs_basic
                | tLPAREN mlhs_inner rparen
                    {
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: mlhs_paren!($2) %*/
                    }
                ;

mlhs_inner	: mlhs_basic
                | tLPAREN mlhs_inner rparen
                    {
                    /*%%%*/
                        $$ = NEW_MASGN(NEW_LIST((NODE *)$2, &@$), 0, &@$);
                    /*% %*/
                    /*% ripper: mlhs_paren!($2) %*/
                    }
                ;

mlhs_basic	: mlhs_head
                    {
                    /*%%%*/
                        $$ = NEW_MASGN($1, 0, &@$);
                    /*% %*/
                    /*% ripper: $1 %*/
                    }
                | mlhs_head mlhs_item
                    {
                    /*%%%*/
                        $$ = NEW_MASGN(list_append(p, $1, $2), 0, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add!($1, $2) %*/
                    }
                | mlhs_head tSTAR mlhs_node
                    {
                    /*%%%*/
                        $$ = NEW_MASGN($1, $3, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_star!($1, $3) %*/
                    }
                | mlhs_head tSTAR mlhs_node ',' mlhs_post
                    {
                    /*%%%*/
                        $$ = NEW_MASGN($1, NEW_POSTARG($3,$5,&@$), &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_post!(mlhs_add_star!($1, $3), $5) %*/
                    }
                | mlhs_head tSTAR
                    {
                    /*%%%*/
                        $$ = NEW_MASGN($1, NODE_SPECIAL_NO_NAME_REST, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_star!($1, Qnil) %*/
                    }
                | mlhs_head tSTAR ',' mlhs_post
                    {
                    /*%%%*/
                        $$ = NEW_MASGN($1, NEW_POSTARG(NODE_SPECIAL_NO_NAME_REST, $4, &@$), &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_post!(mlhs_add_star!($1, Qnil), $4) %*/
                    }
                | tSTAR mlhs_node
                    {
                    /*%%%*/
                        $$ = NEW_MASGN(0, $2, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_star!(mlhs_new!, $2) %*/
                    }
                | tSTAR mlhs_node ',' mlhs_post
                    {
                    /*%%%*/
                        $$ = NEW_MASGN(0, NEW_POSTARG($2,$4,&@$), &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_post!(mlhs_add_star!(mlhs_new!, $2), $4) %*/
                    }
                | tSTAR
                    {
                    /*%%%*/
                        $$ = NEW_MASGN(0, NODE_SPECIAL_NO_NAME_REST, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_star!(mlhs_new!, Qnil) %*/
                    }
                | tSTAR ',' mlhs_post
                    {
                    /*%%%*/
                        $$ = NEW_MASGN(0, NEW_POSTARG(NODE_SPECIAL_NO_NAME_REST, $3, &@$), &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_post!(mlhs_add_star!(mlhs_new!, Qnil), $3) %*/
                    }
                ;

mlhs_item	: mlhs_node
                | tLPAREN mlhs_inner rparen
                    {
                    /*%%%*/
                        $$ = (NODE *)$2;
                    /*% %*/
                    /*% ripper: mlhs_paren!($2) %*/
                    }
                ;

mlhs_head	: mlhs_item ','
                    {
                    /*%%%*/
                        $$ = NEW_LIST($1, &@1);
                    /*% %*/
                    /*% ripper: mlhs_add!(mlhs_new!, $1) %*/
                    }
                | mlhs_head mlhs_item ','
                    {
                    /*%%%*/
                        $$ = list_append(p, $1, $2);
                    /*% %*/
                    /*% ripper: mlhs_add!($1, $2) %*/
                    }
                ;

mlhs_post	: mlhs_item
                    {
                    /*%%%*/
                        $$ = NEW_LIST($1, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add!(mlhs_new!, $1) %*/
                    }
                | mlhs_post ',' mlhs_item
                    {
                    /*%%%*/
                        $$ = list_append(p, $1, $3);
                    /*% %*/
                    /*% ripper: mlhs_add!($1, $3) %*/
                    }
                ;

mlhs_node	: user_variable
                    {
                    /*%%%*/
                        $$ = assignable(p, $1, 0, &@$);
                    /*% %*/
                    /*% ripper: assignable(p, var_field(p, $1)) %*/
                    }
                | keyword_variable
                    {
                    /*%%%*/
                        $$ = assignable(p, $1, 0, &@$);
                    /*% %*/
                    /*% ripper: assignable(p, var_field(p, $1)) %*/
                    }
                | primary_value '[' opt_call_args rbracket
                    {
                    /*%%%*/
                        $$ = aryset(p, $1, $3, &@$);
                    /*% %*/
                    /*% ripper: aref_field!($1, $3) %*/
                    }
                | primary_value call_op tIDENTIFIER
                    {
                        anddot_multiple_assignment_check(p, &@2, $2);
                    /*%%%*/
                        $$ = attrset(p, $1, $2, $3, &@$);
                    /*% %*/
                    /*% ripper: field!($1, $2, $3) %*/
                    }
                | primary_value tCOLON2 tIDENTIFIER
                    {
                    /*%%%*/
                        $$ = attrset(p, $1, idCOLON2, $3, &@$);
                    /*% %*/
                    /*% ripper: const_path_field!($1, $3) %*/
                    }
                | primary_value call_op tCONSTANT
                    {
                        anddot_multiple_assignment_check(p, &@2, $2);
                    /*%%%*/
                        $$ = attrset(p, $1, $2, $3, &@$);
                    /*% %*/
                    /*% ripper: field!($1, $2, $3) %*/
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                    /*%%%*/
                        $$ = const_decl(p, NEW_COLON2($1, $3, &@$), &@$);
                    /*% %*/
                    /*% ripper: const_decl(p, const_path_field!($1, $3)) %*/
                    }
                | tCOLON3 tCONSTANT
                    {
                    /*%%%*/
                        $$ = const_decl(p, NEW_COLON3($2, &@$), &@$);
                    /*% %*/
                    /*% ripper: const_decl(p, top_const_field!($2)) %*/
                    }
                | backref
                    {
                    /*%%%*/
                        rb_backref_error(p, $1);
                        $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper[error]: backref_error(p, RNODE($1), var_field(p, $1)) %*/
                    }
                ;

lhs		: user_variable
                    {
                    /*%%%*/
                        $$ = assignable(p, $1, 0, &@$);
                    /*% %*/
                    /*% ripper: assignable(p, var_field(p, $1)) %*/
                    }
                | keyword_variable
                    {
                    /*%%%*/
                        $$ = assignable(p, $1, 0, &@$);
                    /*% %*/
                    /*% ripper: assignable(p, var_field(p, $1)) %*/
                    }
                | primary_value '[' opt_call_args rbracket
                    {
                    /*%%%*/
                        $$ = aryset(p, $1, $3, &@$);
                    /*% %*/
                    /*% ripper: aref_field!($1, $3) %*/
                    }
                | primary_value call_op tIDENTIFIER
                    {
                    /*%%%*/
                        $$ = attrset(p, $1, $2, $3, &@$);
                    /*% %*/
                    /*% ripper: field!($1, $2, $3) %*/
                    }
                | primary_value tCOLON2 tIDENTIFIER
                    {
                    /*%%%*/
                        $$ = attrset(p, $1, idCOLON2, $3, &@$);
                    /*% %*/
                    /*% ripper: field!($1, $2, $3) %*/
                    }
                | primary_value call_op tCONSTANT
                    {
                    /*%%%*/
                        $$ = attrset(p, $1, $2, $3, &@$);
                    /*% %*/
                    /*% ripper: field!($1, $2, $3) %*/
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                    /*%%%*/
                        $$ = const_decl(p, NEW_COLON2($1, $3, &@$), &@$);
                    /*% %*/
                    /*% ripper: const_decl(p, const_path_field!($1, $3)) %*/
                    }
                | tCOLON3 tCONSTANT
                    {
                    /*%%%*/
                        $$ = const_decl(p, NEW_COLON3($2, &@$), &@$);
                    /*% %*/
                    /*% ripper: const_decl(p, top_const_field!($2)) %*/
                    }
                | backref
                    {
                    /*%%%*/
                        rb_backref_error(p, $1);
                        $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper[error]: backref_error(p, RNODE($1), var_field(p, $1)) %*/
                    }
                ;

cname		: tIDENTIFIER
                    {
                        static const char mesg[] = "class/module name must be CONSTANT";
                    /*%%%*/
                        yyerror1(&@1, mesg);
                    /*% %*/
                    /*% ripper[error]: class_name_error!(ERR_MESG(), $1) %*/
                    }
                | tCONSTANT
                ;

cpath		: tCOLON3 cname
                    {
                    /*%%%*/
                        $$ = NEW_COLON3($2, &@$);
                    /*% %*/
                    /*% ripper: top_const_ref!($2) %*/
                    }
                | cname
                    {
                    /*%%%*/
                        $$ = NEW_COLON2(0, $1, &@$);
                    /*% %*/
                    /*% ripper: const_ref!($1) %*/
                    }
                | primary_value tCOLON2 cname
                    {
                    /*%%%*/
                        $$ = NEW_COLON2($1, $3, &@$);
                    /*% %*/
                    /*% ripper: const_path_ref!($1, $3) %*/
                    }
                ;

fname		: tIDENTIFIER
                | tCONSTANT
                | tFID
                | op
                    {
                        SET_LEX_STATE(EXPR_ENDFN);
                        $$ = $1;
                    }
                | reswords
                ;

fitem		: fname
                    {
                    /*%%%*/
                        $$ = NEW_LIT(ID2SYM($1), &@$);
                    /*% %*/
                    /*% ripper: symbol_literal!($1) %*/
                    }
                | symbol
                ;

undef_list	: fitem
                    {
                    /*%%%*/
                        $$ = NEW_UNDEF($1, &@$);
                    /*% %*/
                    /*% ripper: rb_ary_new3(1, get_value($1)) %*/
                    }
                | undef_list ',' {SET_LEX_STATE(EXPR_FNAME|EXPR_FITEM);} fitem
                    {
                    /*%%%*/
                        NODE *undef = NEW_UNDEF($4, &@4);
                        $$ = block_append(p, $1, undef);
                    /*% %*/
                    /*% ripper: rb_ary_push($1, get_value($4)) %*/
                    }
                ;

op		: '|'		{ ifndef_ripper($$ = '|'); }
                | '^'		{ ifndef_ripper($$ = '^'); }
                | '&'		{ ifndef_ripper($$ = '&'); }
                | tCMP		{ ifndef_ripper($$ = tCMP); }
                | tEQ		{ ifndef_ripper($$ = tEQ); }
                | tEQQ		{ ifndef_ripper($$ = tEQQ); }
                | tMATCH	{ ifndef_ripper($$ = tMATCH); }
                | tNMATCH	{ ifndef_ripper($$ = tNMATCH); }
                | '>'		{ ifndef_ripper($$ = '>'); }
                | tGEQ		{ ifndef_ripper($$ = tGEQ); }
                | '<'		{ ifndef_ripper($$ = '<'); }
                | tLEQ		{ ifndef_ripper($$ = tLEQ); }
                | tNEQ		{ ifndef_ripper($$ = tNEQ); }
                | tLSHFT	{ ifndef_ripper($$ = tLSHFT); }
                | tRSHFT	{ ifndef_ripper($$ = tRSHFT); }
                | '+'		{ ifndef_ripper($$ = '+'); }
                | '-'		{ ifndef_ripper($$ = '-'); }
                | '*'		{ ifndef_ripper($$ = '*'); }
                | tSTAR		{ ifndef_ripper($$ = '*'); }
                | '/'		{ ifndef_ripper($$ = '/'); }
                | '%'		{ ifndef_ripper($$ = '%'); }
                | tPOW		{ ifndef_ripper($$ = tPOW); }
                | tDSTAR	{ ifndef_ripper($$ = tDSTAR); }
                | '!'		{ ifndef_ripper($$ = '!'); }
                | '~'		{ ifndef_ripper($$ = '~'); }
                | tUPLUS	{ ifndef_ripper($$ = tUPLUS); }
                | tUMINUS	{ ifndef_ripper($$ = tUMINUS); }
                | tAREF		{ ifndef_ripper($$ = tAREF); }
                | tASET		{ ifndef_ripper($$ = tASET); }
                | '`'		{ ifndef_ripper($$ = '`'); }
                ;

reswords	: keyword__LINE__ | keyword__FILE__ | keyword__ENCODING__
                | keyword_BEGIN | keyword_END
                | keyword_alias | keyword_and | keyword_begin
                | keyword_break | keyword_case | keyword_class | keyword_def
                | keyword_defined | keyword_do | keyword_else | keyword_elsif
                | keyword_end | keyword_ensure | keyword_false
                | keyword_for | keyword_in | keyword_module | keyword_next
                | keyword_nil | keyword_not | keyword_or | keyword_redo
                | keyword_rescue | keyword_retry | keyword_return | keyword_self
                | keyword_super | keyword_then | keyword_true | keyword_undef
                | keyword_when | keyword_yield | keyword_if | keyword_unless
                | keyword_while | keyword_until
                ;

arg		: lhs '=' lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        $$ = node_assign(p, $1, $4, $3, &@$);
                    /*% %*/
                    /*% ripper: assign!($1, $4) %*/
                    }
                | var_lhs tOP_ASGN lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        $$ = new_op_assign(p, $1, $2, $4, $3, &@$);
                    /*% %*/
                    /*% ripper: opassign!($1, $2, $4) %*/
                    }
                | primary_value '[' opt_call_args rbracket tOP_ASGN lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        $$ = new_ary_op_assign(p, $1, $3, $5, $7, &@3, &@$);
                    /*% %*/
                    /*% ripper: opassign!(aref_field!($1, $3), $5, $7) %*/
                    }
                | primary_value call_op tIDENTIFIER tOP_ASGN lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        $$ = new_attr_op_assign(p, $1, $2, $3, $4, $6, &@$);
                    /*% %*/
                    /*% ripper: opassign!(field!($1, $2, $3), $4, $6) %*/
                    }
                | primary_value call_op tCONSTANT tOP_ASGN lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        $$ = new_attr_op_assign(p, $1, $2, $3, $4, $6, &@$);
                    /*% %*/
                    /*% ripper: opassign!(field!($1, $2, $3), $4, $6) %*/
                    }
                | primary_value tCOLON2 tIDENTIFIER tOP_ASGN lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        $$ = new_attr_op_assign(p, $1, ID2VAL(idCOLON2), $3, $4, $6, &@$);
                    /*% %*/
                    /*% ripper: opassign!(field!($1, $2, $3), $4, $6) %*/
                    }
                | primary_value tCOLON2 tCONSTANT tOP_ASGN lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        YYLTYPE loc = code_loc_gen(&@1, &@3);
                        $$ = new_const_op_assign(p, NEW_COLON2($1, $3, &loc), $4, $6, $5, &@$);
                    /*% %*/
                    /*% ripper: opassign!(const_path_field!($1, $3), $4, $6) %*/
                    }
                | tCOLON3 tCONSTANT tOP_ASGN lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        YYLTYPE loc = code_loc_gen(&@1, &@2);
                        $$ = new_const_op_assign(p, NEW_COLON3($2, &loc), $3, $5, $4, &@$);
                    /*% %*/
                    /*% ripper: opassign!(top_const_field!($2), $3, $5) %*/
                    }
                | backref tOP_ASGN lex_ctxt arg_rhs
                    {
                    /*%%%*/
                        rb_backref_error(p, $1);
                        $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper[error]: backref_error(p, RNODE($1), opassign!(var_field(p, $1), $2, $4)) %*/
                    }
                | arg tDOT2 arg
                    {
                    /*%%%*/
                        value_expr($1);
                        value_expr($3);
                        $$ = NEW_DOT2($1, $3, &@$);
                    /*% %*/
                    /*% ripper: dot2!($1, $3) %*/
                    }
                | arg tDOT3 arg
                    {
                    /*%%%*/
                        value_expr($1);
                        value_expr($3);
                        $$ = NEW_DOT3($1, $3, &@$);
                    /*% %*/
                    /*% ripper: dot3!($1, $3) %*/
                    }
                | arg tDOT2
                    {
                    /*%%%*/
                        value_expr($1);
                        $$ = NEW_DOT2($1, new_nil_at(p, &@2.end_pos), &@$);
                    /*% %*/
                    /*% ripper: dot2!($1, Qnil) %*/
                    }
                | arg tDOT3
                    {
                    /*%%%*/
                        value_expr($1);
                        $$ = NEW_DOT3($1, new_nil_at(p, &@2.end_pos), &@$);
                    /*% %*/
                    /*% ripper: dot3!($1, Qnil) %*/
                    }
                | tBDOT2 arg
                    {
                    /*%%%*/
                        value_expr($2);
                        $$ = NEW_DOT2(new_nil_at(p, &@1.beg_pos), $2, &@$);
                    /*% %*/
                    /*% ripper: dot2!(Qnil, $2) %*/
                    }
                | tBDOT3 arg
                    {
                    /*%%%*/
                        value_expr($2);
                        $$ = NEW_DOT3(new_nil_at(p, &@1.beg_pos), $2, &@$);
                    /*% %*/
                    /*% ripper: dot3!(Qnil, $2) %*/
                    }
                | arg '+' arg
                    {
                        $$ = call_bin_op(p, $1, '+', $3, &@2, &@$);
                    }
                | arg '-' arg
                    {
                        $$ = call_bin_op(p, $1, '-', $3, &@2, &@$);
                    }
                | arg '*' arg
                    {
                        $$ = call_bin_op(p, $1, '*', $3, &@2, &@$);
                    }
                | arg '/' arg
                    {
                        $$ = call_bin_op(p, $1, '/', $3, &@2, &@$);
                    }
                | arg '%' arg
                    {
                        $$ = call_bin_op(p, $1, '%', $3, &@2, &@$);
                    }
                | arg tPOW arg
                    {
                        $$ = call_bin_op(p, $1, idPow, $3, &@2, &@$);
                    }
                | tUMINUS_NUM simple_numeric tPOW arg
                    {
                        $$ = call_uni_op(p, call_bin_op(p, $2, idPow, $4, &@2, &@$), idUMinus, &@1, &@$);
                    }
                | tUPLUS arg
                    {
                        $$ = call_uni_op(p, $2, idUPlus, &@1, &@$);
                    }
                | tUMINUS arg
                    {
                        $$ = call_uni_op(p, $2, idUMinus, &@1, &@$);
                    }
                | arg '|' arg
                    {
                        $$ = call_bin_op(p, $1, '|', $3, &@2, &@$);
                    }
                | arg '^' arg
                    {
                        $$ = call_bin_op(p, $1, '^', $3, &@2, &@$);
                    }
                | arg '&' arg
                    {
                        $$ = call_bin_op(p, $1, '&', $3, &@2, &@$);
                    }
                | arg tCMP arg
                    {
                        $$ = call_bin_op(p, $1, idCmp, $3, &@2, &@$);
                    }
                | rel_expr   %prec tCMP
                | arg tEQ arg
                    {
                        $$ = call_bin_op(p, $1, idEq, $3, &@2, &@$);
                    }
                | arg tEQQ arg
                    {
                        $$ = call_bin_op(p, $1, idEqq, $3, &@2, &@$);
                    }
                | arg tNEQ arg
                    {
                        $$ = call_bin_op(p, $1, idNeq, $3, &@2, &@$);
                    }
                | arg tMATCH arg
                    {
                        $$ = match_op(p, $1, $3, &@2, &@$);
                    }
                | arg tNMATCH arg
                    {
                        $$ = call_bin_op(p, $1, idNeqTilde, $3, &@2, &@$);
                    }
                | '!' arg
                    {
                        $$ = call_uni_op(p, method_cond(p, $2, &@2), '!', &@1, &@$);
                    }
                | '~' arg
                    {
                        $$ = call_uni_op(p, $2, '~', &@1, &@$);
                    }
                | arg tLSHFT arg
                    {
                        $$ = call_bin_op(p, $1, idLTLT, $3, &@2, &@$);
                    }
                | arg tRSHFT arg
                    {
                        $$ = call_bin_op(p, $1, idGTGT, $3, &@2, &@$);
                    }
                | arg tANDOP arg
                    {
                        $$ = logop(p, idANDOP, $1, $3, &@2, &@$);
                    }
                | arg tOROP arg
                    {
                        $$ = logop(p, idOROP, $1, $3, &@2, &@$);
                    }
                | keyword_defined opt_nl begin_defined arg
                    {
                        p->ctxt.in_defined = $3.in_defined;
                        $$ = new_defined(p, $4, &@$);
                    }
                | arg '?' arg opt_nl ':' arg
                    {
                    /*%%%*/
                        value_expr($1);
                        $$ = new_if(p, $1, $3, $6, &@$);
                        fixpos($$, $1);
                    /*% %*/
                    /*% ripper: ifop!($1, $3, $6) %*/
                    }
                | defn_head[head] f_opt_paren_args[args] '=' endless_arg[bodystmt]
                    {
                        endless_method_name(p, get_id($head->nd_mid), &@head);
                        restore_defun(p, $head);
                    /*%%%*/
                        $bodystmt = new_scope_body(p, $args, $bodystmt, &@$);
                        ($$ = $head->nd_def)->nd_loc = @$;
                        RNODE_DEFN($$)->nd_defn = $bodystmt;
                    /*% %*/
                    /*% ripper[$bodystmt]: bodystmt!($bodystmt, Qnil, Qnil, Qnil) %*/
                    /*% ripper: def!($head->nd_mid, $args, $bodystmt) %*/
                        local_pop(p);
                    }
                | defs_head[head] f_opt_paren_args[args] '=' endless_arg[bodystmt]
                    {
                        endless_method_name(p, get_id($head->nd_mid), &@head);
                        restore_defun(p, $head);
                    /*%%%*/
                        $bodystmt = new_scope_body(p, $args, $bodystmt, &@$);
                        ($$ = $head->nd_def)->nd_loc = @$;
                        RNODE_DEFS($$)->nd_defn = $bodystmt;
                    /*% %*/
                    /*% ripper[$bodystmt]: bodystmt!($bodystmt, Qnil, Qnil, Qnil) %*/
                    /*% ripper: defs!($head->nd_recv, $head->dot_or_colon, $head->nd_mid, $args, $bodystmt) %*/
                        local_pop(p);
                    }
                | primary
                    {
                        $$ = $1;
                    }
                ;

endless_arg	: arg %prec modifier_rescue
                | endless_arg modifier_rescue after_rescue arg
                    {
                        p->ctxt.in_rescue = $3.in_rescue;
                    /*%%%*/
                        $$ = rescued_expr(p, $1, $4, &@1, &@2, &@4);
                    /*% %*/
                    /*% ripper: rescue_mod!($1, $4) %*/
                    }
                | keyword_not opt_nl endless_arg
                    {
                        $$ = call_uni_op(p, method_cond(p, $3, &@3), METHOD_NOT, &@1, &@$);
                    }
                ;

relop		: '>'  {$$ = '>';}
                | '<'  {$$ = '<';}
                | tGEQ {$$ = idGE;}
                | tLEQ {$$ = idLE;}
                ;

rel_expr	: arg relop arg   %prec '>'
                    {
                        $$ = call_bin_op(p, $1, $2, $3, &@2, &@$);
                    }
                | rel_expr relop arg   %prec '>'
                    {
                        rb_warning1("comparison '%s' after comparison", WARN_ID($2));
                        $$ = call_bin_op(p, $1, $2, $3, &@2, &@$);
                    }
                ;

lex_ctxt	: none
                    {
                        $$ = p->ctxt;
                    }
                ;

begin_defined	: lex_ctxt
                    {
                        p->ctxt.in_defined = 1;
                        $$ = $1;
                    }
                ;

after_rescue	: lex_ctxt
                    {
                        p->ctxt.in_rescue = after_rescue;
                        $$ = $1;
                    }
                ;

arg_value	: arg
                    {
                        value_expr($1);
                        $$ = $1;
                    }
                ;

aref_args	: none
                | args trailer
                    {
                        $$ = $1;
                    }
                | args ',' assocs trailer
                    {
                    /*%%%*/
                        $$ = $3 ? arg_append(p, $1, new_hash(p, $3, &@3), &@$) : $1;
                    /*% %*/
                    /*% ripper: args_add!($1, bare_assoc_hash!($3)) %*/
                    }
                | assocs trailer
                    {
                    /*%%%*/
                        $$ = $1 ? NEW_LIST(new_hash(p, $1, &@1), &@$) : 0;
                    /*% %*/
                    /*% ripper: args_add!(args_new!, bare_assoc_hash!($1)) %*/
                    }
                ;

arg_rhs 	: arg   %prec tOP_ASGN
                    {
                        value_expr($1);
                        $$ = $1;
                    }
                | arg modifier_rescue after_rescue arg
                    {
                        p->ctxt.in_rescue = $3.in_rescue;
                    /*%%%*/
                        value_expr($1);
                        $$ = rescued_expr(p, $1, $4, &@1, &@2, &@4);
                    /*% %*/
                    /*% ripper: rescue_mod!($1, $4) %*/
                    }
                ;

paren_args	: '(' opt_call_args rparen
                    {
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: arg_paren!($2) %*/
                    }
                | '(' args ',' args_forward rparen
                    {
                        if (!check_forwarding_args(p)) {
                            $$ = Qnone;
                        }
                        else {
                        /*%%%*/
                            $$ = new_args_forward_call(p, $2, &@4, &@$);
                        /*% %*/
                        /*% ripper: arg_paren!(args_add!($2, $4)) %*/
                        }
                    }
                | '(' args_forward rparen
                    {
                        if (!check_forwarding_args(p)) {
                            $$ = Qnone;
                        }
                        else {
                        /*%%%*/
                            $$ = new_args_forward_call(p, 0, &@2, &@$);
                        /*% %*/
                        /*% ripper: arg_paren!($2) %*/
                        }
                    }
                ;

opt_paren_args	: none
                | paren_args
                ;

opt_call_args	: none
                | call_args
                | args ','
                    {
                      $$ = $1;
                    }
                | args ',' assocs ','
                    {
                    /*%%%*/
                        $$ = $3 ? arg_append(p, $1, new_hash(p, $3, &@3), &@$) : $1;
                    /*% %*/
                    /*% ripper: args_add!($1, bare_assoc_hash!($3)) %*/
                    }
                | assocs ','
                    {
                    /*%%%*/
                        $$ = $1 ? NEW_LIST(new_hash(p, $1, &@1), &@1) : 0;
                    /*% %*/
                    /*% ripper: args_add!(args_new!, bare_assoc_hash!($1)) %*/
                    }
                ;

call_args	: command
                    {
                    /*%%%*/
                        value_expr($1);
                        $$ = NEW_LIST($1, &@$);
                    /*% %*/
                    /*% ripper: args_add!(args_new!, $1) %*/
                    }
                | args opt_block_arg
                    {
                    /*%%%*/
                        $$ = arg_blk_pass($1, $2);
                    /*% %*/
                    /*% ripper: args_add_block!($1, $2) %*/
                    }
                | assocs opt_block_arg
                    {
                    /*%%%*/
                        $$ = $1 ? NEW_LIST(new_hash(p, $1, &@1), &@1) : 0;
                        $$ = arg_blk_pass($$, $2);
                    /*% %*/
                    /*% ripper: args_add_block!(args_add!(args_new!, bare_assoc_hash!($1)), $2) %*/
                    }
                | args ',' assocs opt_block_arg
                    {
                    /*%%%*/
                        $$ = $3 ? arg_append(p, $1, new_hash(p, $3, &@3), &@$) : $1;
                        $$ = arg_blk_pass($$, $4);
                    /*% %*/
                    /*% ripper: args_add_block!(args_add!($1, bare_assoc_hash!($3)), $4) %*/
                    }
                | block_arg
                    /*% ripper[brace]: args_add_block!(args_new!, $1) %*/
                ;

command_args	:   {
                        /* If call_args starts with a open paren '(' or '[',
                         * look-ahead reading of the letters calls CMDARG_PUSH(0),
                         * but the push must be done after CMDARG_PUSH(1).
                         * So this code makes them consistent by first cancelling
                         * the premature CMDARG_PUSH(0), doing CMDARG_PUSH(1),
                         * and finally redoing CMDARG_PUSH(0).
                         */
                        int lookahead = 0;
                        switch (yychar) {
                          case '(': case tLPAREN: case tLPAREN_ARG: case '[': case tLBRACK:
                            lookahead = 1;
                        }
                        if (lookahead) CMDARG_POP();
                        CMDARG_PUSH(1);
                        if (lookahead) CMDARG_PUSH(0);
                    }
                  call_args
                    {
                        /* call_args can be followed by tLBRACE_ARG (that does CMDARG_PUSH(0) in the lexer)
                         * but the push must be done after CMDARG_POP() in the parser.
                         * So this code does CMDARG_POP() to pop 0 pushed by tLBRACE_ARG,
                         * CMDARG_POP() to pop 1 pushed by command_args,
                         * and CMDARG_PUSH(0) to restore back the flag set by tLBRACE_ARG.
                         */
                        int lookahead = 0;
                        switch (yychar) {
                          case tLBRACE_ARG:
                            lookahead = 1;
                        }
                        if (lookahead) CMDARG_POP();
                        CMDARG_POP();
                        if (lookahead) CMDARG_PUSH(0);
                        $$ = $2;
                    }
                ;

block_arg	: tAMPER arg_value
                    {
                    /*%%%*/
                        $$ = NEW_BLOCK_PASS($2, &@$);
                    /*% %*/
                    /*% ripper: $2 %*/
                    }
                | tAMPER
                    {
                        forwarding_arg_check(p, idFWD_BLOCK, 0, "block");
                    /*%%%*/
                        $$ = NEW_BLOCK_PASS(NEW_LVAR(idFWD_BLOCK, &@1), &@$);
                    /*% %*/
                    /*% ripper: Qnil %*/
                    }
                ;

opt_block_arg	: ',' block_arg
                    {
                        $$ = $2;
                    }
                | none
                    {
                        $$ = 0;
                    }
                ;

/* value */
args		: arg_value
                    {
                    /*%%%*/
                        $$ = NEW_LIST($1, &@$);
                    /*% %*/
                    /*% ripper: args_add!(args_new!, $1) %*/
                    }
                | arg_splat
                    {
                    /*%%%*/
                        $$ = NEW_SPLAT($arg_splat, &@$);
                    /*% %*/
                    /*% ripper: args_add_star!(args_new!, $arg_splat) %*/
                    }
                | args ',' arg_value
                    {
                    /*%%%*/
                        $$ = last_arg_append(p, $1, $3, &@$);
                    /*% %*/
                    /*% ripper: args_add!($1, $3) %*/
                    }
                | args ',' arg_splat
                    {
                    /*%%%*/
                        $$ = rest_arg_append(p, $args, $arg_splat, &@$);
                    /*% %*/
                    /*% ripper: args_add_star!($args, $arg_splat) %*/
                    }
                ;

/* value */
arg_splat	: tSTAR arg_value
                    {
                        $$ = $2;
                    }
                | tSTAR /* none */
                    {
                        forwarding_arg_check(p, idFWD_REST, idFWD_ALL, "rest");
                    /*%%%*/
                        $$ = NEW_LVAR(idFWD_REST, &@1);
                    /*% %*/
                    /*% ripper: Qnil %*/
                    }
                ;

/* value */
mrhs_arg	: mrhs
                | arg_value
                ;

/* value */
mrhs		: args ',' arg_value
                    {
                    /*%%%*/
                        $$ = last_arg_append(p, $1, $3, &@$);
                    /*% %*/
                    /*% ripper: mrhs_add!(mrhs_new_from_args!($1), $3) %*/
                    }
                | args ',' tSTAR arg_value
                    {
                    /*%%%*/
                        $$ = rest_arg_append(p, $1, $4, &@$);
                    /*% %*/
                    /*% ripper: mrhs_add_star!(mrhs_new_from_args!($1), $4) %*/
                    }
                | tSTAR arg_value
                    {
                    /*%%%*/
                        $$ = NEW_SPLAT($2, &@$);
                    /*% %*/
                    /*% ripper: mrhs_add_star!(mrhs_new!, $2) %*/
                    }
                ;

primary		: literal
                | strings
                | xstring
                | regexp
                | words
                | qwords
                | symbols
                | qsymbols
                | var_ref
                | backref
                | tFID
                    {
                    /*%%%*/
                        $$ = (NODE *)NEW_FCALL($1, 0, &@$);
                    /*% %*/
                    /*% ripper: method_add_arg!(fcall!($1), args_new!) %*/
                    }
                | k_begin
                    {
                        CMDARG_PUSH(0);
                    }
                  bodystmt
                  k_end
                    {
                        CMDARG_POP();
                    /*%%%*/
                        set_line_body($3, @1.end_pos.lineno);
                        $$ = NEW_BEGIN($3, &@$);
                        nd_set_line($$, @1.end_pos.lineno);
                    /*% %*/
                    /*% ripper: begin!($3) %*/
                    }
                | tLPAREN_ARG compstmt {SET_LEX_STATE(EXPR_ENDARG);} ')'
                    {
                    /*%%%*/
                        if (nd_type_p($2, NODE_SELF)) RNODE_SELF($2)->nd_state = 0;
                        $$ = $2;
                    /*% %*/
                    /*% ripper: paren!($2) %*/
                    }
                | tLPAREN compstmt ')'
                    {
                    /*%%%*/
                        if (nd_type_p($2, NODE_SELF)) RNODE_SELF($2)->nd_state = 0;
                        $$ = NEW_BEGIN($2, &@$);
                    /*% %*/
                    /*% ripper: paren!($2) %*/
                    }
                | primary_value tCOLON2 tCONSTANT
                    {
                    /*%%%*/
                        $$ = NEW_COLON2($1, $3, &@$);
                    /*% %*/
                    /*% ripper: const_path_ref!($1, $3) %*/
                    }
                | tCOLON3 tCONSTANT
                    {
                    /*%%%*/
                        $$ = NEW_COLON3($2, &@$);
                    /*% %*/
                    /*% ripper: top_const_ref!($2) %*/
                    }
                | tLBRACK aref_args ']'
                    {
                    /*%%%*/
                        $$ = make_list($2, &@$);
                    /*% %*/
                    /*% ripper: array!($2) %*/
                    }
                | tLBRACE assoc_list '}'
                    {
                    /*%%%*/
                        $$ = new_hash(p, $2, &@$);
                        RNODE_HASH($$)->nd_brace = TRUE;
                    /*% %*/
                    /*% ripper: hash!($2) %*/
                    }
                | k_return
                    {
                    /*%%%*/
                        $$ = NEW_RETURN(0, &@$);
                    /*% %*/
                    /*% ripper: return0! %*/
                    }
                | k_yield '(' call_args rparen
                    {
                    /*%%%*/
                        $$ = new_yield(p, $3, &@$);
                    /*% %*/
                    /*% ripper: yield!(paren!($3)) %*/
                    }
                | k_yield '(' rparen
                    {
                    /*%%%*/
                        $$ = NEW_YIELD(0, &@$);
                    /*% %*/
                    /*% ripper: yield!(paren!(args_new!)) %*/
                    }
                | k_yield
                    {
                    /*%%%*/
                        $$ = NEW_YIELD(0, &@$);
                    /*% %*/
                    /*% ripper: yield0! %*/
                    }
                | keyword_defined opt_nl '(' begin_defined expr rparen
                    {
                        p->ctxt.in_defined = $4.in_defined;
                        $$ = new_defined(p, $5, &@$);
                    }
                | keyword_not '(' expr rparen
                    {
                        $$ = call_uni_op(p, method_cond(p, $3, &@3), METHOD_NOT, &@1, &@$);
                    }
                | keyword_not '(' rparen
                    {
                        $$ = call_uni_op(p, method_cond(p, new_nil(&@2), &@2), METHOD_NOT, &@1, &@$);
                    }
                | fcall brace_block
                    {
                    /*%%%*/
                        $$ = method_add_block(p, (NODE *)$1, $2, &@$);
                    /*% %*/
                    /*% ripper: method_add_block!(method_add_arg!(fcall!($1), args_new!), $2) %*/
                    }
                | method_call
                | method_call brace_block
                    {
                    /*%%%*/
                        block_dup_check(p, get_nd_args(p, $1), $2);
                        $$ = method_add_block(p, $1, $2, &@$);
                    /*% %*/
                    /*% ripper: method_add_block!($1, $2) %*/
                    }
                | lambda
                | k_if expr_value then
                  compstmt
                  if_tail
                  k_end
                    {
                    /*%%%*/
                        $$ = new_if(p, $2, $4, $5, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: if!($2, $4, $5) %*/
                    }
                | k_unless expr_value then
                  compstmt
                  opt_else
                  k_end
                    {
                    /*%%%*/
                        $$ = new_unless(p, $2, $4, $5, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: unless!($2, $4, $5) %*/
                    }
                | k_while expr_value_do
                  compstmt
                  k_end
                    {
                        restore_block_exit(p, $1);
                    /*%%%*/
                        $$ = NEW_WHILE(cond(p, $2, &@2), $3, 1, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: while!($2, $3) %*/
                    }
                | k_until expr_value_do
                  compstmt
                  k_end
                    {
                        restore_block_exit(p, $1);
                    /*%%%*/
                        $$ = NEW_UNTIL(cond(p, $2, &@2), $3, 1, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: until!($2, $3) %*/
                    }
                | k_case expr_value opt_terms
                    {
                        $<val>$ = p->case_labels;
                        p->case_labels = Qnil;
                    }
                  case_body
                  k_end
                    {
                        if (RTEST(p->case_labels)) rb_hash_clear(p->case_labels);
                        p->case_labels = $<val>4;
                    /*%%%*/
                        $$ = NEW_CASE($2, $5, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: case!($2, $5) %*/
                    }
                | k_case opt_terms
                    {
                        $<val>$ = p->case_labels;
                        p->case_labels = 0;
                    }
                  case_body
                  k_end
                    {
                        if (RTEST(p->case_labels)) rb_hash_clear(p->case_labels);
                        p->case_labels = $<val>3;
                    /*%%%*/
                        $$ = NEW_CASE2($4, &@$);
                    /*% %*/
                    /*% ripper: case!(Qnil, $4) %*/
                    }
                | k_case expr_value opt_terms
                  p_case_body
                  k_end
                    {
                    /*%%%*/
                        $$ = NEW_CASE3($2, $4, &@$);
                    /*% %*/
                    /*% ripper: case!($2, $4) %*/
                    }
                | k_for for_var keyword_in expr_value_do
                  compstmt
                  k_end
                    {
                        restore_block_exit(p, $1);
                    /*%%%*/
                        /*
                         *  for a, b, c in e
                         *  #=>
                         *  e.each{|*x| a, b, c = x}
                         *
                         *  for a in e
                         *  #=>
                         *  e.each{|x| a, = x}
                         */
                        ID id = internal_id(p);
                        rb_node_args_aux_t *m = NEW_ARGS_AUX(0, 0, &NULL_LOC);
                        rb_node_args_t *args;
                        NODE *scope, *internal_var = NEW_DVAR(id, &@2);
                        rb_ast_id_table_t *tbl = rb_ast_new_local_table(p->ast, 1);
                        tbl->ids[0] = id; /* internal id */

                        switch (nd_type($2)) {
                          case NODE_LASGN:
                          case NODE_DASGN: /* e.each {|internal_var| a = internal_var; ... } */
                            set_nd_value(p, $2, internal_var);
                            id = 0;
                            m->nd_plen = 1;
                            m->nd_next = $2;
                            break;
                          case NODE_MASGN: /* e.each {|*internal_var| a, b, c = (internal_var.length == 1 && Array === (tmp = internal_var[0]) ? tmp : internal_var); ... } */
                            m->nd_next = node_assign(p, $2, NEW_FOR_MASGN(internal_var, &@2), NO_LEX_CTXT, &@2);
                            break;
                          default: /* e.each {|*internal_var| @a, B, c[1], d.attr = internal_val; ... } */
                            m->nd_next = node_assign(p, (NODE *)NEW_MASGN(NEW_LIST($2, &@2), 0, &@2), internal_var, NO_LEX_CTXT, &@2);
                        }
                        /* {|*internal_id| <m> = internal_id; ... } */
                        args = new_args(p, m, 0, id, 0, new_args_tail(p, 0, 0, 0, &@2), &@2);
                        scope = NEW_SCOPE2(tbl, args, $5, &@$);
                        $$ = NEW_FOR($4, scope, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: for!($2, $4, $5) %*/
                    }
                | k_class cpath superclass
                    {
                        begin_definition("class", &@k_class, &@cpath);
                    }
                  bodystmt
                  k_end
                    {
                    /*%%%*/
                        $$ = NEW_CLASS($cpath, $bodystmt, $superclass, &@$);
                        nd_set_line(RNODE_CLASS($$)->nd_body, @k_end.end_pos.lineno);
                        set_line_body($bodystmt, @superclass.end_pos.lineno);
                        nd_set_line($$, @superclass.end_pos.lineno);
                    /*% %*/
                    /*% ripper: class!($cpath, $superclass, $bodystmt) %*/
                        local_pop(p);
                        p->ctxt.in_class = $k_class.in_class;
                        p->ctxt.shareable_constant_value = $k_class.shareable_constant_value;
                    }
                | k_class tLSHFT expr_value
                    {
                        begin_definition("", &@k_class, &@tLSHFT);
                    }
                  term
                  bodystmt
                  k_end
                    {
                    /*%%%*/
                        $$ = NEW_SCLASS($expr_value, $bodystmt, &@$);
                        nd_set_line(RNODE_SCLASS($$)->nd_body, @k_end.end_pos.lineno);
                        set_line_body($bodystmt, nd_line($expr_value));
                        fixpos($$, $expr_value);
                    /*% %*/
                    /*% ripper: sclass!($expr_value, $bodystmt) %*/
                        local_pop(p);
                        p->ctxt.in_def = $k_class.in_def;
                        p->ctxt.in_class = $k_class.in_class;
                        p->ctxt.shareable_constant_value = $k_class.shareable_constant_value;
                    }
                | k_module cpath
                    {
                        begin_definition("module", &@k_module, &@cpath);
                    }
                  bodystmt
                  k_end
                    {
                    /*%%%*/
                        $$ = NEW_MODULE($cpath, $bodystmt, &@$);
                        nd_set_line(RNODE_MODULE($$)->nd_body, @k_end.end_pos.lineno);
                        set_line_body($bodystmt, @cpath.end_pos.lineno);
                        nd_set_line($$, @cpath.end_pos.lineno);
                    /*% %*/
                    /*% ripper: module!($cpath, $bodystmt) %*/
                        local_pop(p);
                        p->ctxt.in_class = $k_module.in_class;
                        p->ctxt.shareable_constant_value = $k_module.shareable_constant_value;
                    }
                | defn_head[head]
                  f_arglist[args]
                    {
                    /*%%%*/
                        push_end_expect_token_locations(p, &@head.beg_pos);
                    /*% %*/
                    }
                  bodystmt
                  k_end
                    {
                        restore_defun(p, $head);
                    /*%%%*/
                        $bodystmt = new_scope_body(p, $args, $bodystmt, &@$);
                        ($$ = $head->nd_def)->nd_loc = @$;
                        RNODE_DEFN($$)->nd_defn = $bodystmt;
                    /*% %*/
                    /*% ripper: def!($head->nd_mid, $args, $bodystmt) %*/
                        local_pop(p);
                    }
                | defs_head[head]
                  f_arglist[args]
                    {
                    /*%%%*/
                        push_end_expect_token_locations(p, &@head.beg_pos);
                    /*% %*/
                    }
                  bodystmt
                  k_end
                    {
                        restore_defun(p, $head);
                    /*%%%*/
                        $bodystmt = new_scope_body(p, $args, $bodystmt, &@$);
                        ($$ = $head->nd_def)->nd_loc = @$;
                        RNODE_DEFS($$)->nd_defn = $bodystmt;
                    /*% %*/
                    /*% ripper: defs!($head->nd_recv, $head->dot_or_colon, $head->nd_mid, $args, $bodystmt) %*/
                        local_pop(p);
                    }
                | keyword_break
                    {
                        $<node>$ = add_block_exit(p, NEW_BREAK(0, &@$));
                    /*% ripper: break!(args_new!) %*/
                    }
                | keyword_next
                    {
                        $<node>$ = add_block_exit(p, NEW_NEXT(0, &@$));
                    /*% ripper: next!(args_new!) %*/
                    }
                | keyword_redo
                    {
                        $<node>$ = add_block_exit(p, NEW_REDO(&@$));
                    /*% ripper: redo! %*/
                    }
                | keyword_retry
                    {
                        if (!p->ctxt.in_defined) {
                            switch (p->ctxt.in_rescue) {
                              case before_rescue: yyerror1(&@1, "Invalid retry without rescue"); break;
                              case after_rescue: /* ok */ break;
                              case after_else: yyerror1(&@1, "Invalid retry after else"); break;
                              case after_ensure: yyerror1(&@1, "Invalid retry after ensure"); break;
                            }
                        }
                    /*%%%*/
                        $$ = NEW_RETRY(&@$);
                    /*% %*/
                    /*% ripper: retry! %*/
                    }
                ;

primary_value	: primary
                    {
                        value_expr($1);
                        $$ = $1;
                    }
                ;

k_begin		: keyword_begin
                    {
                        token_info_push(p, "begin", &@$);
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_if		: keyword_if
                    {
                        WARN_EOL("if");
                        token_info_push(p, "if", &@$);
                        if (p->token_info && p->token_info->nonspc &&
                            p->token_info->next && !strcmp(p->token_info->next->token, "else")) {
                            const char *tok = p->lex.ptok - rb_strlen_lit("if");
                            const char *beg = p->lex.pbeg + p->token_info->next->beg.column;
                            beg += rb_strlen_lit("else");
                            while (beg < tok && ISSPACE(*beg)) beg++;
                            if (beg == tok) {
                                p->token_info->nonspc = 0;
                            }
                        }
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_unless	: keyword_unless
                    {
                        token_info_push(p, "unless", &@$);
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_while		: keyword_while allow_exits
                    {
                        $$ = $allow_exits;
                        token_info_push(p, "while", &@$);
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_until		: keyword_until allow_exits
                    {
                        $$ = $allow_exits;
                        token_info_push(p, "until", &@$);
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_case		: keyword_case
                    {
                        token_info_push(p, "case", &@$);
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_for		: keyword_for allow_exits
                    {
                        $$ = $allow_exits;
                        token_info_push(p, "for", &@$);
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_class		: keyword_class
                    {
                        token_info_push(p, "class", &@$);
                        $$ = p->ctxt;
                        p->ctxt.in_rescue = before_rescue;
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_module	: keyword_module
                    {
                        token_info_push(p, "module", &@$);
                        $$ = p->ctxt;
                        p->ctxt.in_rescue = before_rescue;
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_def		: keyword_def
                    {
                        token_info_push(p, "def", &@$);
                        $$ = NEW_DEF_TEMP(&@$);
                        p->ctxt.in_argdef = 1;
                    }
                ;

k_do		: keyword_do
                    {
                        token_info_push(p, "do", &@$);
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_do_block	: keyword_do_block
                    {
                        token_info_push(p, "do", &@$);
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                ;

k_rescue	: keyword_rescue
                    {
                        token_info_warn(p, "rescue", p->token_info, 1, &@$);
                        $$ = p->ctxt;
                        p->ctxt.in_rescue = after_rescue;
                    }
                ;

k_ensure	: keyword_ensure
                    {
                        token_info_warn(p, "ensure", p->token_info, 1, &@$);
                        $$ = p->ctxt;
                    }
                ;

k_when		: keyword_when
                    {
                        token_info_warn(p, "when", p->token_info, 0, &@$);
                    }
                ;

k_else		: keyword_else
                    {
                        token_info *ptinfo_beg = p->token_info;
                        int same = ptinfo_beg && strcmp(ptinfo_beg->token, "case") != 0;
                        token_info_warn(p, "else", p->token_info, same, &@$);
                        if (same) {
                            token_info e;
                            e.next = ptinfo_beg->next;
                            e.token = "else";
                            token_info_setup(&e, p->lex.pbeg, &@$);
                            if (!e.nonspc) *ptinfo_beg = e;
                        }
                    }
                ;

k_elsif 	: keyword_elsif
                    {
                        WARN_EOL("elsif");
                        token_info_warn(p, "elsif", p->token_info, 1, &@$);
                    }
                ;

k_end		: keyword_end
                    {
                        token_info_pop(p, "end", &@$);
                    /*%%%*/
                        pop_end_expect_token_locations(p);
                    /*% %*/
                    }
                | tDUMNY_END
                    {
                        compile_error(p, "syntax error, unexpected end-of-input");
                    }
                ;

k_return	: keyword_return
                    {
                        if (p->ctxt.in_class && !p->ctxt.in_def && !dyna_in_block(p))
                            yyerror1(&@1, "Invalid return in class/module body");
                    }
                ;

k_yield 	: keyword_yield
                    {
                        if (!p->ctxt.in_defined && !p->ctxt.in_def && !compile_for_eval)
                            yyerror1(&@1, "Invalid yield");
                    }
                ;

then		: term
                | keyword_then
                | term keyword_then
                ;

do		: term
                | keyword_do_cond
                ;

if_tail		: opt_else
                | k_elsif expr_value then
                  compstmt
                  if_tail
                    {
                    /*%%%*/
                        $$ = new_if(p, $2, $4, $5, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: elsif!($2, $4, $5) %*/
                    }
                ;

opt_else	: none
                | k_else compstmt
                    {
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: else!($2) %*/
                    }
                ;

for_var		: lhs
                | mlhs
                ;

f_marg		: f_norm_arg
                    {
                    /*%%%*/
                        $$ = assignable(p, $1, 0, &@$);
                        mark_lvar_used(p, $$);
                    /*% %*/
                    /*% ripper: assignable(p, $1) %*/
                    }
                | tLPAREN f_margs rparen
                    {
                    /*%%%*/
                        $$ = (NODE *)$2;
                    /*% %*/
                    /*% ripper: mlhs_paren!($2) %*/
                    }
                ;

f_marg_list	: f_marg
                    {
                    /*%%%*/
                        $$ = NEW_LIST($1, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add!(mlhs_new!, $1) %*/
                    }
                | f_marg_list ',' f_marg
                    {
                    /*%%%*/
                        $$ = list_append(p, $1, $3);
                    /*% %*/
                    /*% ripper: mlhs_add!($1, $3) %*/
                    }
                ;

f_margs		: f_marg_list
                    {
                    /*%%%*/
                        $$ = NEW_MASGN($1, 0, &@$);
                    /*% %*/
                    /*% ripper: $1 %*/
                    }
                | f_marg_list ',' f_rest_marg
                    {
                    /*%%%*/
                        $$ = NEW_MASGN($1, $3, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_star!($1, $3) %*/
                    }
                | f_marg_list ',' f_rest_marg ',' f_marg_list
                    {
                    /*%%%*/
                        $$ = NEW_MASGN($1, NEW_POSTARG($3, $5, &@$), &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_post!(mlhs_add_star!($1, $3), $5) %*/
                    }
                | f_rest_marg
                    {
                    /*%%%*/
                        $$ = NEW_MASGN(0, $1, &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_star!(mlhs_new!, $1) %*/
                    }
                | f_rest_marg ',' f_marg_list
                    {
                    /*%%%*/
                        $$ = NEW_MASGN(0, NEW_POSTARG($1, $3, &@$), &@$);
                    /*% %*/
                    /*% ripper: mlhs_add_post!(mlhs_add_star!(mlhs_new!, $1), $3) %*/
                    }
                ;

f_rest_marg	: tSTAR f_norm_arg
                    {
                    /*%%%*/
                        $$ = assignable(p, $2, 0, &@$);
                        mark_lvar_used(p, $$);
                    /*% %*/
                    /*% ripper: assignable(p, $2) %*/
                    }
                | tSTAR
                    {
                    /*%%%*/
                        $$ = NODE_SPECIAL_NO_NAME_REST;
                    /*% %*/
                    /*% ripper: Qnil %*/
                    }
                ;

f_any_kwrest	: f_kwrest
                | f_no_kwarg {$$ = ID2VAL(idNil);}
                ;

f_eq		: {p->ctxt.in_argdef = 0;} '=';

block_args_tail	: f_block_kwarg ',' f_kwrest opt_f_block_arg
                    {
                        $$ = new_args_tail(p, $1, $3, $4, &@3);
                    }
                | f_block_kwarg opt_f_block_arg
                    {
                        $$ = new_args_tail(p, $1, Qnone, $2, &@1);
                    }
                | f_any_kwrest opt_f_block_arg
                    {
                        $$ = new_args_tail(p, Qnone, $1, $2, &@1);
                    }
                | f_block_arg
                    {
                        $$ = new_args_tail(p, Qnone, Qnone, $1, &@1);
                    }
                ;

opt_block_args_tail : ',' block_args_tail
                    {
                        $$ = $2;
                    }
                | /* none */
                    {
                        $$ = new_args_tail(p, Qnone, Qnone, Qnone, &@0);
                    }
                ;

excessed_comma	: ','
                    {
                        /* magic number for rest_id in iseq_set_arguments() */
                    /*%%%*/
                        $$ = NODE_SPECIAL_EXCESSIVE_COMMA;
                    /*% %*/
                    /*% ripper: excessed_comma! %*/
                    }
                ;

block_param	: f_arg ',' f_block_optarg ',' f_rest_arg opt_block_args_tail
                    {
                        $$ = new_args(p, $1, $3, $5, Qnone, $6, &@$);
                    }
                | f_arg ',' f_block_optarg ',' f_rest_arg ',' f_arg opt_block_args_tail
                    {
                        $$ = new_args(p, $1, $3, $5, $7, $8, &@$);
                    }
                | f_arg ',' f_block_optarg opt_block_args_tail
                    {
                        $$ = new_args(p, $1, $3, Qnone, Qnone, $4, &@$);
                    }
                | f_arg ',' f_block_optarg ',' f_arg opt_block_args_tail
                    {
                        $$ = new_args(p, $1, $3, Qnone, $5, $6, &@$);
                    }
                | f_arg ',' f_rest_arg opt_block_args_tail
                    {
                        $$ = new_args(p, $1, Qnone, $3, Qnone, $4, &@$);
                    }
                | f_arg excessed_comma
                    {
                        $$ = new_args_tail(p, Qnone, Qnone, Qnone, &@2);
                        $$ = new_args(p, $1, Qnone, $2, Qnone, $$, &@$);
                    }
                | f_arg ',' f_rest_arg ',' f_arg opt_block_args_tail
                    {
                        $$ = new_args(p, $1, Qnone, $3, $5, $6, &@$);
                    }
                | f_arg opt_block_args_tail
                    {
                        $$ = new_args(p, $1, Qnone, Qnone, Qnone, $2, &@$);
                    }
                | f_block_optarg ',' f_rest_arg opt_block_args_tail
                    {
                        $$ = new_args(p, Qnone, $1, $3, Qnone, $4, &@$);
                    }
                | f_block_optarg ',' f_rest_arg ',' f_arg opt_block_args_tail
                    {
                        $$ = new_args(p, Qnone, $1, $3, $5, $6, &@$);
                    }
                | f_block_optarg opt_block_args_tail
                    {
                        $$ = new_args(p, Qnone, $1, Qnone, Qnone, $2, &@$);
                    }
                | f_block_optarg ',' f_arg opt_block_args_tail
                    {
                        $$ = new_args(p, Qnone, $1, Qnone, $3, $4, &@$);
                    }
                | f_rest_arg opt_block_args_tail
                    {
                        $$ = new_args(p, Qnone, Qnone, $1, Qnone, $2, &@$);
                    }
                | f_rest_arg ',' f_arg opt_block_args_tail
                    {
                        $$ = new_args(p, Qnone, Qnone, $1, $3, $4, &@$);
                    }
                | block_args_tail
                    {
                        $$ = new_args(p, Qnone, Qnone, Qnone, Qnone, $1, &@$);
                    }
                ;

opt_block_param	: none
                | block_param_def
                    {
                        p->command_start = TRUE;
                    }
                ;

block_param_def	: '|' opt_bv_decl '|'
                    {
                        p->cur_arg = 0;
                        p->max_numparam = ORDINAL_PARAM;
                        p->ctxt.in_argdef = 0;
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: params!(Qnil,Qnil,Qnil,Qnil,Qnil,Qnil,Qnil) %*/
                    /*% ripper: block_var!($$, $2) %*/
                    }
                | '|' block_param opt_bv_decl '|'
                    {
                        p->cur_arg = 0;
                        p->max_numparam = ORDINAL_PARAM;
                        p->ctxt.in_argdef = 0;
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: block_var!($2, $3) %*/
                    }
                ;


opt_bv_decl	: opt_nl
                    {
                        $$ = 0;
                    }
                | opt_nl ';' bv_decls opt_nl
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: $3 %*/
                    }
                ;

bv_decls	: bvar
                    /*% ripper[brace]: rb_ary_new3(1, get_value($1)) %*/
                | bv_decls ',' bvar
                    /*% ripper[brace]: rb_ary_push($1, get_value($3)) %*/
                ;

bvar		: tIDENTIFIER
                    {
                        new_bv(p, get_id($1));
                    /*% ripper: get_value($1) %*/
                    }
                | f_bad_arg
                    {
                        $$ = 0;
                    }
                ;

max_numparam	:   {
                        $$ = p->max_numparam;
                        p->max_numparam = 0;
                    }
                ;

numparam	:   {
                        $$ = numparam_push(p);
                    }
                ;

lambda		: tLAMBDA[dyna]
                    {
                        token_info_push(p, "->", &@1);
                        $<vars>dyna = dyna_push(p);
                        $<num>$ = p->lex.lpar_beg;
                        p->lex.lpar_beg = p->lex.paren_nest;
                    }[lpar]
                  max_numparam numparam allow_exits
                  f_larglist[args]
                    {
                        CMDARG_PUSH(0);
                    }
                  lambda_body[body]
                    {
                        int max_numparam = p->max_numparam;
                        p->lex.lpar_beg = $<num>lpar;
                        p->max_numparam = $max_numparam;
                        restore_block_exit(p, $allow_exits);
                        CMDARG_POP();
                        $args = args_with_numbered(p, $args, max_numparam);
                    /*%%%*/
                        {
                            YYLTYPE loc = code_loc_gen(&@args, &@body);
                            $$ = NEW_LAMBDA($args, $body, &loc);
                            nd_set_line(RNODE_LAMBDA($$)->nd_body, @body.end_pos.lineno);
                            nd_set_line($$, @args.end_pos.lineno);
                            nd_set_first_loc($$, @1.beg_pos);
                        }
                    /*% %*/
                    /*% ripper: lambda!($args, $body) %*/
                        numparam_pop(p, $numparam);
                        dyna_pop(p, $<vars>dyna);
                    }
                ;

f_larglist	: '(' f_args opt_bv_decl ')'
                    {
                        p->ctxt.in_argdef = 0;
                    /*%%%*/
                        $$ = $2;
                        p->max_numparam = ORDINAL_PARAM;
                    /*% %*/
                    /*% ripper: paren!($2) %*/
                    }
                | f_args
                    {
                        p->ctxt.in_argdef = 0;
                    /*%%%*/
                        if (!args_info_empty_p(&$1->nd_ainfo))
                            p->max_numparam = ORDINAL_PARAM;
                    /*% %*/
                        $$ = $1;
                    }
                ;

lambda_body	: tLAMBEG compstmt '}'
                    {
                        token_info_pop(p, "}", &@3);
                        $$ = $2;
                    }
                | keyword_do_LAMBDA
                    {
                    /*%%%*/
                        push_end_expect_token_locations(p, &@1.beg_pos);
                    /*% %*/
                    }
                  bodystmt k_end
                    {
                        $$ = $3;
                    }
                ;

do_block	: k_do_block do_body k_end
                    {
                        $$ = $2;
                    /*%%%*/
                        set_embraced_location($$, &@1, &@3);
                    /*% %*/
                    }
                ;

block_call	: command do_block
                    {
                    /*%%%*/
                        if (nd_type_p($1, NODE_YIELD)) {
                            compile_error(p, "block given to yield");
                        }
                        else {
                            block_dup_check(p, get_nd_args(p, $1), $2);
                        }
                        $$ = method_add_block(p, $1, $2, &@$);
                        fixpos($$, $1);
                    /*% %*/
                    /*% ripper: method_add_block!($1, $2) %*/
                    }
                | block_call call_op2 operation2 opt_paren_args
                    {
                    /*%%%*/
                        $$ = new_qcall(p, $2, $1, $3, $4, &@3, &@$);
                    /*% %*/
                    /*% ripper: opt_event(:method_add_arg!, call!($1, $2, $3), $4) %*/
                    }
                | block_call call_op2 operation2 opt_paren_args brace_block
                    {
                    /*%%%*/
                        $$ = new_command_qcall(p, $2, $1, $3, $4, $5, &@3, &@$);
                    /*% %*/
                    /*% ripper: opt_event(:method_add_block!, command_call!($1, $2, $3, $4), $5) %*/
                    }
                | block_call call_op2 operation2 command_args do_block
                    {
                    /*%%%*/
                        $$ = new_command_qcall(p, $2, $1, $3, $4, $5, &@3, &@$);
                    /*% %*/
                    /*% ripper: method_add_block!(command_call!($1, $2, $3, $4), $5) %*/
                    }
                ;

method_call	: fcall paren_args
                    {
                    /*%%%*/
                        $1->nd_args = $2;
                        $$ = (NODE *)$1;
                        nd_set_last_loc($1, @2.end_pos);
                    /*% %*/
                    /*% ripper: method_add_arg!(fcall!($1), $2) %*/
                    }
                | primary_value call_op operation2 opt_paren_args
                    {
                    /*%%%*/
                        $$ = new_qcall(p, $2, $1, $3, $4, &@3, &@$);
                        nd_set_line($$, @3.end_pos.lineno);
                    /*% %*/
                    /*% ripper: opt_event(:method_add_arg!, call!($1, $2, $3), $4) %*/
                    }
                | primary_value tCOLON2 operation2 paren_args
                    {
                    /*%%%*/
                        $$ = new_qcall(p, ID2VAL(idCOLON2), $1, $3, $4, &@3, &@$);
                        nd_set_line($$, @3.end_pos.lineno);
                    /*% %*/
                    /*% ripper: method_add_arg!(call!($1, $2, $3), $4) %*/
                    }
                | primary_value tCOLON2 operation3
                    {
                    /*%%%*/
                        $$ = new_qcall(p, ID2VAL(idCOLON2), $1, $3, Qnull, &@3, &@$);
                    /*% %*/
                    /*% ripper: call!($1, $2, $3) %*/
                    }
                | primary_value call_op paren_args
                    {
                    /*%%%*/
                        $$ = new_qcall(p, $2, $1, ID2VAL(idCall), $3, &@2, &@$);
                        nd_set_line($$, @2.end_pos.lineno);
                    /*% %*/
                    /*% ripper: method_add_arg!(call!($1, $2, ID2VAL(idCall)), $3) %*/
                    }
                | primary_value tCOLON2 paren_args
                    {
                    /*%%%*/
                        $$ = new_qcall(p, ID2VAL(idCOLON2), $1, ID2VAL(idCall), $3, &@2, &@$);
                        nd_set_line($$, @2.end_pos.lineno);
                    /*% %*/
                    /*% ripper: method_add_arg!(call!($1, $2, ID2VAL(idCall)), $3) %*/
                    }
                | keyword_super paren_args
                    {
                    /*%%%*/
                        $$ = NEW_SUPER($2, &@$);
                    /*% %*/
                    /*% ripper: super!($2) %*/
                    }
                | keyword_super
                    {
                    /*%%%*/
                        $$ = NEW_ZSUPER(&@$);
                    /*% %*/
                    /*% ripper: zsuper! %*/
                    }
                | primary_value '[' opt_call_args rbracket
                    {
                    /*%%%*/
                        $$ = NEW_CALL($1, tAREF, $3, &@$);
                        fixpos($$, $1);
                    /*% %*/
                    /*% ripper: aref!($1, $3) %*/
                    }
                ;

brace_block	: '{' brace_body '}'
                    {
                        $$ = $2;
                    /*%%%*/
                        set_embraced_location($$, &@1, &@3);
                    /*% %*/
                    }
                | k_do do_body k_end
                    {
                        $$ = $2;
                    /*%%%*/
                        set_embraced_location($$, &@1, &@3);
                    /*% %*/
                    }
                ;

brace_body	: {$<vars>$ = dyna_push(p);}[dyna]
                  max_numparam numparam allow_exits
                  opt_block_param[args] compstmt
                    {
                        int max_numparam = p->max_numparam;
                        p->max_numparam = $max_numparam;
                        $args = args_with_numbered(p, $args, max_numparam);
                    /*%%%*/
                        $$ = NEW_ITER($args, $compstmt, &@$);
                    /*% %*/
                    /*% ripper: brace_block!($args, $compstmt) %*/
                        restore_block_exit(p, $allow_exits);
                        numparam_pop(p, $numparam);
                        dyna_pop(p, $<vars>dyna);
                    }
                ;

do_body 	:   {
                        $<vars>$ = dyna_push(p);
                        CMDARG_PUSH(0);
                    }[dyna]
                  max_numparam numparam allow_exits
                  opt_block_param[args] bodystmt
                    {
                        int max_numparam = p->max_numparam;
                        p->max_numparam = $max_numparam;
                        $args = args_with_numbered(p, $args, max_numparam);
                    /*%%%*/
                        $$ = NEW_ITER($args, $bodystmt, &@$);
                    /*% %*/
                    /*% ripper: do_block!($args, $bodystmt) %*/
                        CMDARG_POP();
                        restore_block_exit(p, $allow_exits);
                        numparam_pop(p, $numparam);
                        dyna_pop(p, $<vars>dyna);
                    }
                ;

case_args	: arg_value
                    {
                    /*%%%*/
                        check_literal_when(p, $1, &@1);
                        $$ = NEW_LIST($1, &@$);
                    /*% %*/
                    /*% ripper: args_add!(args_new!, $1) %*/
                    }
                | tSTAR arg_value
                    {
                    /*%%%*/
                        $$ = NEW_SPLAT($2, &@$);
                    /*% %*/
                    /*% ripper: args_add_star!(args_new!, $2) %*/
                    }
                | case_args ',' arg_value
                    {
                    /*%%%*/
                        check_literal_when(p, $3, &@3);
                        $$ = last_arg_append(p, $1, $3, &@$);
                    /*% %*/
                    /*% ripper: args_add!($1, $3) %*/
                    }
                | case_args ',' tSTAR arg_value
                    {
                    /*%%%*/
                        $$ = rest_arg_append(p, $1, $4, &@$);
                    /*% %*/
                    /*% ripper: args_add_star!($1, $4) %*/
                    }
                ;

case_body	: k_when case_args then
                  compstmt
                  cases
                    {
                    /*%%%*/
                        $$ = NEW_WHEN($2, $4, $5, &@$);
                        fixpos($$, $2);
                    /*% %*/
                    /*% ripper: when!($2, $4, $5) %*/
                    }
                ;

cases		: opt_else
                | case_body
                ;

p_pvtbl 	: {$$ = p->pvtbl; p->pvtbl = st_init_numtable();};
p_pktbl 	: {$$ = p->pktbl; p->pktbl = 0;};

p_in_kwarg	:   {
                        $$ = p->ctxt;
                        SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
                        p->command_start = FALSE;
                        p->ctxt.in_kwarg = 1;
                    }
                ;

p_case_body	: keyword_in
                  p_in_kwarg[ctxt] p_pvtbl p_pktbl
                  p_top_expr[expr] then
                    {
                        pop_pktbl(p, $p_pktbl);
                        pop_pvtbl(p, $p_pvtbl);
                        p->ctxt.in_kwarg = $ctxt.in_kwarg;
                    }
                  compstmt
                  p_cases[cases]
                    {
                    /*%%%*/
                        $$ = NEW_IN($expr, $compstmt, $cases, &@$);
                    /*% %*/
                    /*% ripper: in!($expr, $compstmt, $cases) %*/
                    }
                ;

p_cases 	: opt_else
                | p_case_body
                ;

p_top_expr	: p_top_expr_body
                | p_top_expr_body modifier_if expr_value
                    {
                    /*%%%*/
                        $$ = new_if(p, $3, $1, 0, &@$);
                        fixpos($$, $3);
                    /*% %*/
                    /*% ripper: if_mod!($3, $1) %*/
                    }
                | p_top_expr_body modifier_unless expr_value
                    {
                    /*%%%*/
                        $$ = new_unless(p, $3, $1, 0, &@$);
                        fixpos($$, $3);
                    /*% %*/
                    /*% ripper: unless_mod!($3, $1) %*/
                    }
                ;

p_top_expr_body : p_expr
                | p_expr ','
                    {
                        $$ = new_array_pattern_tail(p, Qnone, 1, Qnone, Qnone, &@$);
                        $$ = new_array_pattern(p, Qnone, get_value($1), $$, &@$);
                    }
                | p_expr ',' p_args
                    {
                        $$ = new_array_pattern(p, Qnone, get_value($1), $3, &@$);
                    /*%%%*/
                        nd_set_first_loc($$, @1.beg_pos);
                    /*%
                    %*/
                    }
                | p_find
                    {
                        $$ = new_find_pattern(p, Qnone, $1, &@$);
                    }
                | p_args_tail
                    {
                        $$ = new_array_pattern(p, Qnone, Qnone, $1, &@$);
                    }
                | p_kwargs
                    {
                        $$ = new_hash_pattern(p, Qnone, $1, &@$);
                    }
                ;

p_expr		: p_as
                ;

p_as		: p_expr tASSOC p_variable
                    {
                    /*%%%*/
                        NODE *n = NEW_LIST($1, &@$);
                        n = list_append(p, n, $3);
                        $$ = new_hash(p, n, &@$);
                    /*% %*/
                    /*% ripper: binary!($1, STATIC_ID2SYM((id_assoc)), $3) %*/
                    }
                | p_alt
                ;

p_alt		: p_alt '|' p_expr_basic
                    {
                    /*%%%*/
                        $$ = NEW_OR($1, $3, &@$);
                    /*% %*/
                    /*% ripper: binary!($1, STATIC_ID2SYM(idOr), $3) %*/
                    }
                | p_expr_basic
                ;

p_lparen	: '(' p_pktbl { $$ = $2;};
p_lbracket	: '[' p_pktbl { $$ = $2;};

p_expr_basic	: p_value
                | p_variable
                | p_const p_lparen[p_pktbl] p_args rparen
                    {
                        pop_pktbl(p, $p_pktbl);
                        $$ = new_array_pattern(p, $p_const, Qnone, $p_args, &@$);
                    /*%%%*/
                        nd_set_first_loc($$, @p_const.beg_pos);
                    /*%
                    %*/
                    }
                | p_const p_lparen[p_pktbl] p_find rparen
                    {
                        pop_pktbl(p, $p_pktbl);
                        $$ = new_find_pattern(p, $p_const, $p_find, &@$);
                    /*%%%*/
                        nd_set_first_loc($$, @p_const.beg_pos);
                    /*%
                    %*/
                    }
                | p_const p_lparen[p_pktbl] p_kwargs rparen
                    {
                        pop_pktbl(p, $p_pktbl);
                        $$ = new_hash_pattern(p, $p_const, $p_kwargs, &@$);
                    /*%%%*/
                        nd_set_first_loc($$, @p_const.beg_pos);
                    /*%
                    %*/
                    }
                | p_const '(' rparen
                    {
                        $$ = new_array_pattern_tail(p, Qnone, 0, Qnone, Qnone, &@$);
                        $$ = new_array_pattern(p, $p_const, Qnone, $$, &@$);
                    }
                | p_const p_lbracket[p_pktbl] p_args rbracket
                    {
                        pop_pktbl(p, $p_pktbl);
                        $$ = new_array_pattern(p, $p_const, Qnone, $p_args, &@$);
                    /*%%%*/
                        nd_set_first_loc($$, @p_const.beg_pos);
                    /*%
                    %*/
                    }
                | p_const p_lbracket[p_pktbl] p_find rbracket
                    {
                        pop_pktbl(p, $p_pktbl);
                        $$ = new_find_pattern(p, $p_const, $p_find, &@$);
                    /*%%%*/
                        nd_set_first_loc($$, @p_const.beg_pos);
                    /*%
                    %*/
                    }
                | p_const p_lbracket[p_pktbl] p_kwargs rbracket
                    {
                        pop_pktbl(p, $p_pktbl);
                        $$ = new_hash_pattern(p, $p_const, $p_kwargs, &@$);
                    /*%%%*/
                        nd_set_first_loc($$, @p_const.beg_pos);
                    /*%
                    %*/
                    }
                | p_const '[' rbracket
                    {
                        $$ = new_array_pattern_tail(p, Qnone, 0, Qnone, Qnone, &@$);
                        $$ = new_array_pattern(p, $1, Qnone, $$, &@$);
                    }
                | tLBRACK p_args rbracket
                    {
                        $$ = new_array_pattern(p, Qnone, Qnone, $p_args, &@$);
                    }
                | tLBRACK p_find rbracket
                    {
                        $$ = new_find_pattern(p, Qnone, $p_find, &@$);
                    }
                | tLBRACK rbracket
                    {
                        $$ = new_array_pattern_tail(p, Qnone, 0, Qnone, Qnone, &@$);
                        $$ = new_array_pattern(p, Qnone, Qnone, $$, &@$);
                    }
                | tLBRACE p_pktbl lex_ctxt[ctxt]
                    {
                        p->ctxt.in_kwarg = 0;
                    }
                  p_kwargs rbrace
                    {
                        pop_pktbl(p, $p_pktbl);
                        p->ctxt.in_kwarg = $ctxt.in_kwarg;
                        $$ = new_hash_pattern(p, Qnone, $p_kwargs, &@$);
                    }
                | tLBRACE rbrace
                    {
                        $$ = new_hash_pattern_tail(p, Qnone, 0, &@$);
                        $$ = new_hash_pattern(p, Qnone, $$, &@$);
                    }
                | tLPAREN p_pktbl p_expr rparen
                    {
                        pop_pktbl(p, $p_pktbl);
                        $$ = $p_expr;
                    }
                ;

p_args		: p_expr
                    {
                    /*%%%*/
                        NODE *pre_args = NEW_LIST($1, &@$);
                        $$ = new_array_pattern_tail(p, pre_args, 0, Qnone, Qnone, &@$);
                    /*%
                        $$ = new_array_pattern_tail(p, rb_ary_new_from_args(1, get_value($1)), 0, Qnone, Qnone, &@$);
                    %*/
                    }
                | p_args_head
                    {
                        $$ = new_array_pattern_tail(p, $1, 1, Qnone, Qnone, &@$);
                    }
                | p_args_head p_arg
                    {
                    /*%%%*/
                        $$ = new_array_pattern_tail(p, list_concat($1, $2), 0, Qnone, Qnone, &@$);
                    /*%
                        VALUE pre_args = rb_ary_concat($1, get_value($2));
                        $$ = new_array_pattern_tail(p, pre_args, 0, Qnone, Qnone, &@$);
                    %*/
                    }
                | p_args_head p_rest
                    {
                        $$ = new_array_pattern_tail(p, $1, 1, $2, Qnone, &@$);
                    }
                | p_args_head p_rest ',' p_args_post
                    {
                        $$ = new_array_pattern_tail(p, $1, 1, $2, $4, &@$);
                    }
                | p_args_tail
                ;

p_args_head	: p_arg ','
                    {
                        $$ = $1;
                    }
                | p_args_head p_arg ','
                    {
                    /*%%%*/
                        $$ = list_concat($1, $2);
                    /*% %*/
                    /*% ripper: rb_ary_concat($1, get_value($2)) %*/
                    }
                ;

p_args_tail	: p_rest
                    {
                        $$ = new_array_pattern_tail(p, Qnone, 1, $1, Qnone, &@$);
                    }
                | p_rest ',' p_args_post
                    {
                        $$ = new_array_pattern_tail(p, Qnone, 1, $1, $3, &@$);
                    }
                ;

p_find		: p_rest ',' p_args_post ',' p_rest
                    {
                        $$ = new_find_pattern_tail(p, $1, $3, $5, &@$);
                    }
                ;


p_rest		: tSTAR tIDENTIFIER
                    {
                    /*%%%*/
                        error_duplicate_pattern_variable(p, $2, &@2);
                        $$ = assignable(p, $2, 0, &@$);
                    /*% %*/
                    /*% ripper: assignable(p, var_field(p, $2)) %*/
                    }
                | tSTAR
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: var_field(p, Qnil) %*/
                    }
                ;

p_args_post	: p_arg
                | p_args_post ',' p_arg
                    {
                    /*%%%*/
                        $$ = list_concat($1, $3);
                    /*% %*/
                    /*% ripper: rb_ary_concat($1, get_value($3)) %*/
                    }
                ;

p_arg		: p_expr
                    {
                    /*%%%*/
                        $$ = NEW_LIST($1, &@$);
                    /*% %*/
                    /*% ripper: rb_ary_new_from_args(1, get_value($1)) %*/
                    }
                ;

p_kwargs	: p_kwarg ',' p_any_kwrest
                    {
                        $$ =  new_hash_pattern_tail(p, new_unique_key_hash(p, $1, &@$), $3, &@$);
                    }
                | p_kwarg
                    {
                        $$ =  new_hash_pattern_tail(p, new_unique_key_hash(p, $1, &@$), 0, &@$);
                    }
                | p_kwarg ','
                    {
                        $$ =  new_hash_pattern_tail(p, new_unique_key_hash(p, $1, &@$), 0, &@$);
                    }
                | p_any_kwrest
                    {
                        $$ =  new_hash_pattern_tail(p, new_hash(p, Qnone, &@$), $1, &@$);
                    }
                ;

p_kwarg 	: p_kw
                    /*% ripper[brace]: rb_ary_new_from_args(1, $1) %*/
                | p_kwarg ',' p_kw
                    {
                    /*%%%*/
                        $$ = list_concat($1, $3);
                    /*% %*/
                    /*% ripper: rb_ary_push($1, $3) %*/
                    }
                ;

p_kw		: p_kw_label p_expr
                    {
                        error_duplicate_pattern_key(p, get_id($1), &@1);
                    /*%%%*/
                        $$ = list_append(p, NEW_LIST(NEW_LIT(ID2SYM($1), &@1), &@$), $2);
                    /*% %*/
                    /*% ripper: rb_ary_new_from_args(2, get_value($1), get_value($2)) %*/
                    }
                | p_kw_label
                    {
                        error_duplicate_pattern_key(p, get_id($1), &@1);
                        if ($1 && !is_local_id(get_id($1))) {
                            yyerror1(&@1, "key must be valid as local variables");
                        }
                        error_duplicate_pattern_variable(p, get_id($1), &@1);
                    /*%%%*/
                        $$ = list_append(p, NEW_LIST(NEW_LIT(ID2SYM($1), &@$), &@$), assignable(p, $1, 0, &@$));
                    /*% %*/
                    /*% ripper: rb_ary_new_from_args(2, get_value(assignable(p, $1)), Qnil) %*/
                    }
                ;

p_kw_label	: tLABEL
                | tSTRING_BEG string_contents tLABEL_END
                    {
                        YYLTYPE loc = code_loc_gen(&@1, &@3);
                    /*%%%*/
                        if (!$2 || nd_type_p($2, NODE_STR)) {
                            NODE *node = dsym_node(p, $2, &loc);
                            $$ = SYM2ID(RNODE_LIT(node)->nd_lit);
                        }
                    /*%
                        if (ripper_is_node_yylval(p, $2) && RNODE_RIPPER($2)->nd_cval) {
                            VALUE label = RNODE_RIPPER($2)->nd_cval;
                            VALUE rval = RNODE_RIPPER($2)->nd_rval;
                            $$ = ripper_new_yylval(p, rb_intern_str(label), rval, label);
                            RNODE($$)->nd_loc = loc;
                        }
                    %*/
                        else {
                            yyerror1(&loc, "symbol literal with interpolation is not allowed");
                            $$ = 0;
                        }
                    }
                ;

p_kwrest	: kwrest_mark tIDENTIFIER
                    {
                        $$ = $2;
                    }
                | kwrest_mark
                    {
                        $$ = 0;
                    }
                ;

p_kwnorest	: kwrest_mark keyword_nil
                    {
                        $$ = 0;
                    }
                ;

p_any_kwrest	: p_kwrest
                | p_kwnorest {$$ = ID2VAL(idNil);}
                ;

p_value 	: p_primitive
                | p_primitive tDOT2 p_primitive
                    {
                    /*%%%*/
                        value_expr($1);
                        value_expr($3);
                        $$ = NEW_DOT2($1, $3, &@$);
                    /*% %*/
                    /*% ripper: dot2!($1, $3) %*/
                    }
                | p_primitive tDOT3 p_primitive
                    {
                    /*%%%*/
                        value_expr($1);
                        value_expr($3);
                        $$ = NEW_DOT3($1, $3, &@$);
                    /*% %*/
                    /*% ripper: dot3!($1, $3) %*/
                    }
                | p_primitive tDOT2
                    {
                    /*%%%*/
                        value_expr($1);
                        $$ = NEW_DOT2($1, new_nil_at(p, &@2.end_pos), &@$);
                    /*% %*/
                    /*% ripper: dot2!($1, Qnil) %*/
                    }
                | p_primitive tDOT3
                    {
                    /*%%%*/
                        value_expr($1);
                        $$ = NEW_DOT3($1, new_nil_at(p, &@2.end_pos), &@$);
                    /*% %*/
                    /*% ripper: dot3!($1, Qnil) %*/
                    }
                | p_var_ref
                | p_expr_ref
                | p_const
                | tBDOT2 p_primitive
                    {
                    /*%%%*/
                        value_expr($2);
                        $$ = NEW_DOT2(new_nil_at(p, &@1.beg_pos), $2, &@$);
                    /*% %*/
                    /*% ripper: dot2!(Qnil, $2) %*/
                    }
                | tBDOT3 p_primitive
                    {
                    /*%%%*/
                        value_expr($2);
                        $$ = NEW_DOT3(new_nil_at(p, &@1.beg_pos), $2, &@$);
                    /*% %*/
                    /*% ripper: dot3!(Qnil, $2) %*/
                    }
                ;

p_primitive	: literal
                | strings
                | xstring
                | regexp
                | words
                | qwords
                | symbols
                | qsymbols
                | keyword_variable
                    {
                    /*%%%*/
                        if (!($$ = gettable(p, $1, &@$))) $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper: var_ref!($1) %*/
                    }
                | lambda
                ;

p_variable	: tIDENTIFIER
                    {
                    /*%%%*/
                        error_duplicate_pattern_variable(p, $1, &@1);
                        $$ = assignable(p, $1, 0, &@$);
                    /*% %*/
                    /*% ripper: assignable(p, var_field(p, $1)) %*/
                    }
                ;

p_var_ref	: '^' tIDENTIFIER
                    {
                    /*%%%*/
                        NODE *n = gettable(p, $2, &@$);
                        if (!(nd_type_p(n, NODE_LVAR) || nd_type_p(n, NODE_DVAR))) {
                            compile_error(p, "%"PRIsVALUE": no such local variable", rb_id2str($2));
                        }
                        $$ = n;
                    /*% %*/
                    /*% ripper: var_ref!($2) %*/
                    }
                | '^' nonlocal_var
                    {
                    /*%%%*/
                        if (!($$ = gettable(p, $2, &@$))) $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper: var_ref!($2) %*/
                    }
                ;

p_expr_ref	: '^' tLPAREN expr_value rparen
                    {
                    /*%%%*/
                        $$ = NEW_BEGIN($3, &@$);
                    /*% %*/
                    /*% ripper: begin!($3) %*/
                    }
                ;

p_const 	: tCOLON3 cname
                    {
                    /*%%%*/
                        $$ = NEW_COLON3($2, &@$);
                    /*% %*/
                    /*% ripper: top_const_ref!($2) %*/
                    }
                | p_const tCOLON2 cname
                    {
                    /*%%%*/
                        $$ = NEW_COLON2($1, $3, &@$);
                    /*% %*/
                    /*% ripper: const_path_ref!($1, $3) %*/
                    }
                | tCONSTANT
                   {
                    /*%%%*/
                        $$ = gettable(p, $1, &@$);
                    /*% %*/
                    /*% ripper: var_ref!($1) %*/
                   }
                ;

opt_rescue	: k_rescue exc_list exc_var then
                  compstmt
                  opt_rescue
                    {
                    /*%%%*/
                        NODE *body = $5;
                        if ($3) {
                            NODE *err = NEW_ERRINFO(&@3);
                            err = node_assign(p, $3, err, NO_LEX_CTXT, &@3);
                            body = block_append(p, err, body);
                        }
                        $$ = NEW_RESBODY($2, body, $6, &@$);
                        if ($2) {
                            fixpos($$, $2);
                        }
                        else if ($3) {
                            fixpos($$, $3);
                        }
                        else {
                            fixpos($$, $5);
                        }
                    /*% %*/
                    /*% ripper: rescue!($2, $3, $5, $6) %*/
                    }
                | none
                ;

exc_list	: arg_value
                    {
                    /*%%%*/
                        $$ = NEW_LIST($1, &@$);
                    /*% %*/
                    /*% ripper: rb_ary_new3(1, get_value($1)) %*/
                    }
                | mrhs
                    {
                    /*%%%*/
                        if (!($$ = splat_array($1))) $$ = $1;
                    /*% %*/
                    /*% ripper: $1 %*/
                    }
                | none
                ;

exc_var		: tASSOC lhs
                    {
                        $$ = $2;
                    }
                | none
                ;

opt_ensure	: k_ensure compstmt
                    {
                        p->ctxt.in_rescue = $1.in_rescue;
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: ensure!($2) %*/
                    }
                | none
                ;

literal		: numeric
                | symbol
                ;

strings		: string
                    {
                    /*%%%*/
                        NODE *node = $1;
                        if (!node) {
                            node = NEW_STR(STR_NEW0(), &@$);
                            RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_STR(node)->nd_lit);
                        }
                        else {
                            node = evstr2dstr(p, node);
                        }
                        $$ = node;
                    /*% %*/
                    /*% ripper: $1 %*/
                    }
                ;

string		: tCHAR
                | string1
                | string string1
                    {
                    /*%%%*/
                        $$ = literal_concat(p, $1, $2, &@$);
                    /*% %*/
                    /*% ripper: string_concat!($1, $2) %*/
                    }
                ;

string1		: tSTRING_BEG string_contents tSTRING_END
                    {
                    /*%%%*/
                        $$ = heredoc_dedent(p, $2);
                        if ($$) nd_set_loc($$, &@$);
                    /*% %*/
                    /*% ripper: string_literal!(heredoc_dedent(p, $2)) %*/
                    }
                ;

xstring		: tXSTRING_BEG xstring_contents tSTRING_END
                    {
                    /*%%%*/
                        $$ = new_xstring(p, heredoc_dedent(p, $2), &@$);
                    /*% %*/
                    /*% ripper: xstring_literal!(heredoc_dedent(p, $2)) %*/
                    }
                ;

regexp		: tREGEXP_BEG regexp_contents tREGEXP_END
                    {
                        $$ = new_regexp(p, $2, $3, &@$);
                    }
                ;

words_sep	: ' ' {}
                | words_sep ' '
                ;

words		: tWORDS_BEG words_sep word_list tSTRING_END
                    {
                    /*%%%*/
                        $$ = make_list($3, &@$);
                    /*% %*/
                    /*% ripper: array!($3) %*/
                    }
                ;

word_list	: /* none */
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: words_new! %*/
                    }
                | word_list word words_sep
                    {
                    /*%%%*/
                        $$ = list_append(p, $1, evstr2dstr(p, $2));
                    /*% %*/
                    /*% ripper: words_add!($1, $2) %*/
                    }
                ;

word		: string_content
                    /*% ripper[brace]: word_add!(word_new!, $1) %*/
                | word string_content
                    {
                    /*%%%*/
                        $$ = literal_concat(p, $1, $2, &@$);
                    /*% %*/
                    /*% ripper: word_add!($1, $2) %*/
                    }
                ;

symbols 	: tSYMBOLS_BEG words_sep symbol_list tSTRING_END
                    {
                    /*%%%*/
                        $$ = make_list($3, &@$);
                    /*% %*/
                    /*% ripper: array!($3) %*/
                    }
                ;

symbol_list	: /* none */
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: symbols_new! %*/
                    }
                | symbol_list word words_sep
                    {
                    /*%%%*/
                        $$ = symbol_append(p, $1, evstr2dstr(p, $2));
                    /*% %*/
                    /*% ripper: symbols_add!($1, $2) %*/
                    }
                ;

qwords		: tQWORDS_BEG words_sep qword_list tSTRING_END
                    {
                    /*%%%*/
                        $$ = make_list($3, &@$);
                    /*% %*/
                    /*% ripper: array!($3) %*/
                    }
                ;

qsymbols	: tQSYMBOLS_BEG words_sep qsym_list tSTRING_END
                    {
                    /*%%%*/
                        $$ = make_list($3, &@$);
                    /*% %*/
                    /*% ripper: array!($3) %*/
                    }
                ;

qword_list	: /* none */
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: qwords_new! %*/
                    }
                | qword_list tSTRING_CONTENT words_sep
                    {
                    /*%%%*/
                        $$ = list_append(p, $1, $2);
                    /*% %*/
                    /*% ripper: qwords_add!($1, $2) %*/
                    }
                ;

qsym_list	: /* none */
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: qsymbols_new! %*/
                    }
                | qsym_list tSTRING_CONTENT words_sep
                    {
                    /*%%%*/
                        $$ = symbol_append(p, $1, $2);
                    /*% %*/
                    /*% ripper: qsymbols_add!($1, $2) %*/
                    }
                ;

string_contents : /* none */
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: string_content! %*/
                    /*%%%*/
                    /*%
                        $$ = ripper_new_yylval(p, 0, $$, 0);
                    %*/
                    }
                | string_contents string_content
                    {
                    /*%%%*/
                        $$ = literal_concat(p, $1, $2, &@$);
                    /*% %*/
                    /*% ripper: string_add!($1, $2) %*/
                    /*%%%*/
                    /*%
                        if (ripper_is_node_yylval(p, $1) && ripper_is_node_yylval(p, $2) &&
                            !RNODE_RIPPER($1)->nd_cval) {
                            RNODE_RIPPER($1)->nd_cval = RNODE_RIPPER($2)->nd_cval;
                            RNODE_RIPPER($1)->nd_rval = add_mark_object(p, $$);
                            $$ = $1;
                        }
                    %*/
                    }
                ;

xstring_contents: /* none */
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: xstring_new! %*/
                    }
                | xstring_contents string_content
                    {
                    /*%%%*/
                        $$ = literal_concat(p, $1, $2, &@$);
                    /*% %*/
                    /*% ripper: xstring_add!($1, $2) %*/
                    }
                ;

regexp_contents: /* none */
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: regexp_new! %*/
                    /*%%%*/
                    /*%
                        $$ = ripper_new_yylval(p, 0, $$, 0);
                    %*/
                    }
                | regexp_contents string_content
                    {
                    /*%%%*/
                        NODE *head = $1, *tail = $2;
                        if (!head) {
                            $$ = tail;
                        }
                        else if (!tail) {
                            $$ = head;
                        }
                        else {
                            switch (nd_type(head)) {
                              case NODE_STR:
                                head = str2dstr(p, head);
                                break;
                              case NODE_DSTR:
                                break;
                              default:
                                head = list_append(p, NEW_DSTR(Qnil, &@$), head);
                                break;
                            }
                            $$ = list_append(p, head, tail);
                        }
                    /*%
                        VALUE s1 = 1, s2 = 0, n1 = $1, n2 = $2;
                        if (ripper_is_node_yylval(p, n1)) {
                            s1 = RNODE_RIPPER(n1)->nd_cval;
                            n1 = RNODE_RIPPER(n1)->nd_rval;
                        }
                        if (ripper_is_node_yylval(p, n2)) {
                            s2 = RNODE_RIPPER(n2)->nd_cval;
                            n2 = RNODE_RIPPER(n2)->nd_rval;
                        }
                        $$ = dispatch2(regexp_add, n1, n2);
                        if (!s1 && s2) {
                            $$ = ripper_new_yylval(p, 0, $$, s2);
                        }
                    %*/
                    }
                ;

string_content	: tSTRING_CONTENT
                    /*% ripper[brace]: ripper_new_yylval(p, 0, get_value($1), $1) %*/
                | tSTRING_DVAR
                    {
                        /* need to backup p->lex.strterm so that a string literal `%&foo,#$&,bar&` can be parsed */
                        $<strterm>$ = p->lex.strterm;
                        p->lex.strterm = 0;
                        SET_LEX_STATE(EXPR_BEG);
                    }
                  string_dvar
                    {
                        p->lex.strterm = $<strterm>2;
                    /*%%%*/
                        $$ = NEW_EVSTR($3, &@$);
                        nd_set_line($$, @3.end_pos.lineno);
                    /*% %*/
                    /*% ripper: string_dvar!($3) %*/
                    }
                | tSTRING_DBEG[term]
                    {
                        CMDARG_PUSH(0);
                        COND_PUSH(0);
                        /* need to backup p->lex.strterm so that a string literal `%!foo,#{ !0 },bar!` can be parsed */
                        $<strterm>term = p->lex.strterm;
                        p->lex.strterm = 0;
                        $<num>$ = p->lex.state;
                        SET_LEX_STATE(EXPR_BEG);
                    }[state]
                    {
                        $<num>$ = p->lex.brace_nest;
                        p->lex.brace_nest = 0;
                    }[brace]
                    {
                        $<num>$ = p->heredoc_indent;
                        p->heredoc_indent = 0;
                    }[indent]
                  compstmt string_dend
                    {
                        COND_POP();
                        CMDARG_POP();
                        p->lex.strterm = $<strterm>term;
                        SET_LEX_STATE($<num>state);
                        p->lex.brace_nest = $<num>brace;
                        p->heredoc_indent = $<num>indent;
                        p->heredoc_line_indent = -1;
                    /*%%%*/
                        if ($compstmt) nd_unset_fl_newline($compstmt);
                        $$ = new_evstr(p, $compstmt, &@$);
                    /*% %*/
                    /*% ripper: string_embexpr!($compstmt) %*/
                    }
                ;

string_dend	: tSTRING_DEND
                | END_OF_INPUT
                ;

string_dvar	: nonlocal_var
                    {
                    /*%%%*/
                        if (!($$ = gettable(p, $1, &@$))) $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper: var_ref!($1) %*/
                    }
                | backref
                ;

symbol		: ssym
                | dsym
                ;

ssym		: tSYMBEG sym
                    {
                        SET_LEX_STATE(EXPR_END);
                    /*%%%*/
                        $$ = NEW_LIT(ID2SYM($2), &@$);
                    /*% %*/
                    /*% ripper: symbol_literal!(symbol!($2)) %*/
                    }
                ;

sym		: fname
                | nonlocal_var
                ;

dsym		: tSYMBEG string_contents tSTRING_END
                    {
                        SET_LEX_STATE(EXPR_END);
                    /*%%%*/
                        $$ = dsym_node(p, $2, &@$);
                    /*% %*/
                    /*% ripper: dyna_symbol!($2) %*/
                    }
                ;

numeric 	: simple_numeric
                | tUMINUS_NUM simple_numeric   %prec tLOWEST
                    {
                    /*%%%*/
                        $$ = $2;
                        RB_OBJ_WRITE(p->ast, &RNODE_LIT($$)->nd_lit, negate_lit(p, RNODE_LIT($$)->nd_lit));
                    /*% %*/
                    /*% ripper: unary!(ID2VAL(idUMinus), $2) %*/
                    }
                ;

simple_numeric	: tINTEGER
                | tFLOAT
                | tRATIONAL
                | tIMAGINARY
                ;

nonlocal_var    : tIVAR
                | tGVAR
                | tCVAR
                ;

user_variable	: tIDENTIFIER
                | tCONSTANT
                | nonlocal_var
                ;

keyword_variable: keyword_nil {$$ = KWD2EID(nil, $1);}
                | keyword_self {$$ = KWD2EID(self, $1);}
                | keyword_true {$$ = KWD2EID(true, $1);}
                | keyword_false {$$ = KWD2EID(false, $1);}
                | keyword__FILE__ {$$ = KWD2EID(_FILE__, $1);}
                | keyword__LINE__ {$$ = KWD2EID(_LINE__, $1);}
                | keyword__ENCODING__ {$$ = KWD2EID(_ENCODING__, $1);}
                ;

var_ref		: user_variable
                    {
                    /*%%%*/
                        if (!($$ = gettable(p, $1, &@$))) $$ = NEW_BEGIN(0, &@$);
                    /*%
                        if (id_is_var(p, get_id($1))) {
                            $$ = dispatch1(var_ref, $1);
                        }
                        else {
                            $$ = dispatch1(vcall, $1);
                        }
                    %*/
                    }
                | keyword_variable
                    {
                    /*%%%*/
                        if (!($$ = gettable(p, $1, &@$))) $$ = NEW_BEGIN(0, &@$);
                    /*% %*/
                    /*% ripper: var_ref!($1) %*/
                    }
                ;

var_lhs		: user_variable
                    {
                    /*%%%*/
                        $$ = assignable(p, $1, 0, &@$);
                    /*% %*/
                    /*% ripper: assignable(p, var_field(p, $1)) %*/
                    }
                | keyword_variable
                    {
                    /*%%%*/
                        $$ = assignable(p, $1, 0, &@$);
                    /*% %*/
                    /*% ripper: assignable(p, var_field(p, $1)) %*/
                    }
                ;

backref		: tNTH_REF
                | tBACK_REF
                ;

superclass	: '<'
                    {
                        SET_LEX_STATE(EXPR_BEG);
                        p->command_start = TRUE;
                    }
                  expr_value term
                    {
                        $$ = $3;
                    }
                | /* none */
                    {
                    /*%%%*/
                        $$ = 0;
                    /*% %*/
                    /*% ripper: Qnil %*/
                    }
                ;

f_opt_paren_args: f_paren_args
                | none
                    {
                        p->ctxt.in_argdef = 0;
                        $$ = new_args_tail(p, Qnone, Qnone, Qnone, &@0);
                        $$ = new_args(p, Qnone, Qnone, Qnone, Qnone, $$, &@0);
                    }
                ;

f_paren_args	: '(' f_args rparen
                    {
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: paren!($2) %*/
                        SET_LEX_STATE(EXPR_BEG);
                        p->command_start = TRUE;
                        p->ctxt.in_argdef = 0;
                    }
                ;

f_arglist	: f_paren_args
                |   {
                        $<ctxt>$ = p->ctxt;
                        p->ctxt.in_kwarg = 1;
                        p->ctxt.in_argdef = 1;
                        SET_LEX_STATE(p->lex.state|EXPR_LABEL); /* force for args */
                    }
                  f_args term
                    {
                        p->ctxt.in_kwarg = $<ctxt>1.in_kwarg;
                        p->ctxt.in_argdef = 0;
                        $$ = $2;
                        SET_LEX_STATE(EXPR_BEG);
                        p->command_start = TRUE;
                    }
                ;

args_tail	: f_kwarg ',' f_kwrest opt_f_block_arg
                    {
                        $$ = new_args_tail(p, $1, $3, $4, &@3);
                    }
                | f_kwarg opt_f_block_arg
                    {
                        $$ = new_args_tail(p, $1, Qnone, $2, &@1);
                    }
                | f_any_kwrest opt_f_block_arg
                    {
                        $$ = new_args_tail(p, Qnone, $1, $2, &@1);
                    }
                | f_block_arg
                    {
                        $$ = new_args_tail(p, Qnone, Qnone, $1, &@1);
                    }
                | args_forward
                    {
                        add_forwarding_args(p);
                        $$ = new_args_tail(p, Qnone, $1, arg_FWD_BLOCK, &@1);
                    /*%%%*/
                        $$->nd_ainfo.forwarding = 1;
                    /*% %*/
                    }
                ;

opt_args_tail	: ',' args_tail
                    {
                        $$ = $2;
                    }
                | /* none */
                    {
                        $$ = new_args_tail(p, Qnone, Qnone, Qnone, &@0);
                    }
                ;

f_args		: f_arg ',' f_optarg ',' f_rest_arg opt_args_tail
                    {
                        $$ = new_args(p, $1, $3, $5, Qnone, $6, &@$);
                    }
                | f_arg ',' f_optarg ',' f_rest_arg ',' f_arg opt_args_tail
                    {
                        $$ = new_args(p, $1, $3, $5, $7, $8, &@$);
                    }
                | f_arg ',' f_optarg opt_args_tail
                    {
                        $$ = new_args(p, $1, $3, Qnone, Qnone, $4, &@$);
                    }
                | f_arg ',' f_optarg ',' f_arg opt_args_tail
                    {
                        $$ = new_args(p, $1, $3, Qnone, $5, $6, &@$);
                    }
                | f_arg ',' f_rest_arg opt_args_tail
                    {
                        $$ = new_args(p, $1, Qnone, $3, Qnone, $4, &@$);
                    }
                | f_arg ',' f_rest_arg ',' f_arg opt_args_tail
                    {
                        $$ = new_args(p, $1, Qnone, $3, $5, $6, &@$);
                    }
                | f_arg opt_args_tail
                    {
                        $$ = new_args(p, $1, Qnone, Qnone, Qnone, $2, &@$);
                    }
                | f_optarg ',' f_rest_arg opt_args_tail
                    {
                        $$ = new_args(p, Qnone, $1, $3, Qnone, $4, &@$);
                    }
                | f_optarg ',' f_rest_arg ',' f_arg opt_args_tail
                    {
                        $$ = new_args(p, Qnone, $1, $3, $5, $6, &@$);
                    }
                | f_optarg opt_args_tail
                    {
                        $$ = new_args(p, Qnone, $1, Qnone, Qnone, $2, &@$);
                    }
                | f_optarg ',' f_arg opt_args_tail
                    {
                        $$ = new_args(p, Qnone, $1, Qnone, $3, $4, &@$);
                    }
                | f_rest_arg opt_args_tail
                    {
                        $$ = new_args(p, Qnone, Qnone, $1, Qnone, $2, &@$);
                    }
                | f_rest_arg ',' f_arg opt_args_tail
                    {
                        $$ = new_args(p, Qnone, Qnone, $1, $3, $4, &@$);
                    }
                | args_tail
                    {
                        $$ = new_args(p, Qnone, Qnone, Qnone, Qnone, $1, &@$);
                    }
                | /* none */
                    {
                        $$ = new_args_tail(p, Qnone, Qnone, Qnone, &@0);
                        $$ = new_args(p, Qnone, Qnone, Qnone, Qnone, $$, &@0);
                    }
                ;

args_forward	: tBDOT3
                    {
                    /*%%%*/
#ifdef FORWARD_ARGS_WITH_RUBY2_KEYWORDS
                        $$ = 0;
#else
                        $$ = idFWD_KWREST;
#endif
                    /*% %*/
                    /*% ripper: args_forward! %*/
                    }
                ;

f_bad_arg	: tCONSTANT
                    {
                        static const char mesg[] = "formal argument cannot be a constant";
                    /*%%%*/
                        yyerror1(&@1, mesg);
                        $$ = 0;
                    /*% %*/
                    /*% ripper[error]: param_error!(ERR_MESG(), $1) %*/
                    }
                | tIVAR
                    {
                        static const char mesg[] = "formal argument cannot be an instance variable";
                    /*%%%*/
                        yyerror1(&@1, mesg);
                        $$ = 0;
                    /*% %*/
                    /*% ripper[error]: param_error!(ERR_MESG(), $1) %*/
                    }
                | tGVAR
                    {
                        static const char mesg[] = "formal argument cannot be a global variable";
                    /*%%%*/
                        yyerror1(&@1, mesg);
                        $$ = 0;
                    /*% %*/
                    /*% ripper[error]: param_error!(ERR_MESG(), $1) %*/
                    }
                | tCVAR
                    {
                        static const char mesg[] = "formal argument cannot be a class variable";
                    /*%%%*/
                        yyerror1(&@1, mesg);
                        $$ = 0;
                    /*% %*/
                    /*% ripper[error]: param_error!(ERR_MESG(), $1) %*/
                    }
                ;

f_norm_arg	: f_bad_arg
                | tIDENTIFIER
                    {
                        formal_argument(p, $1);
                        p->max_numparam = ORDINAL_PARAM;
                        $$ = $1;
                    }
                ;

f_arg_asgn	: f_norm_arg
                    {
                        ID id = get_id($1);
                        arg_var(p, id);
                        p->cur_arg = id;
                        $$ = $1;
                    }
                ;

f_arg_item	: f_arg_asgn
                    {
                        p->cur_arg = 0;
                    /*%%%*/
                        $$ = NEW_ARGS_AUX($1, 1, &NULL_LOC);
                    /*% %*/
                    /*% ripper: get_value($1) %*/
                    }
                | tLPAREN f_margs rparen
                    {
                    /*%%%*/
                        ID tid = internal_id(p);
                        YYLTYPE loc;
                        loc.beg_pos = @2.beg_pos;
                        loc.end_pos = @2.beg_pos;
                        arg_var(p, tid);
                        if (dyna_in_block(p)) {
                            $2->nd_value = NEW_DVAR(tid, &loc);
                        }
                        else {
                            $2->nd_value = NEW_LVAR(tid, &loc);
                        }
                        $$ = NEW_ARGS_AUX(tid, 1, &NULL_LOC);
                        $$->nd_next = (NODE *)$2;
                    /*% %*/
                    /*% ripper: mlhs_paren!($2) %*/
                    }
                ;

f_arg		: f_arg_item
                    /*% ripper[brace]: rb_ary_new3(1, get_value($1)) %*/
                | f_arg ',' f_arg_item
                    {
                    /*%%%*/
                        $$ = $1;
                        $$->nd_plen++;
                        $$->nd_next = block_append(p, $$->nd_next, $3->nd_next);
                        rb_discard_node(p, (NODE *)$3);
                    /*% %*/
                    /*% ripper: rb_ary_push($1, get_value($3)) %*/
                    }
                ;


f_label 	: tLABEL
                    {
                        arg_var(p, formal_argument(p, $1));
                        p->cur_arg = get_id($1);
                        p->max_numparam = ORDINAL_PARAM;
                        p->ctxt.in_argdef = 0;
                        $$ = $1;
                    }
                ;

f_kw		: f_label arg_value
                    {
                        p->cur_arg = 0;
                        p->ctxt.in_argdef = 1;
                    /*%%%*/
                        $$ = new_kw_arg(p, assignable(p, $1, $2, &@$), &@$);
                    /*% %*/
                    /*% ripper: rb_assoc_new(get_value(assignable(p, $1)), get_value($2)) %*/
                    }
                | f_label
                    {
                        p->cur_arg = 0;
                        p->ctxt.in_argdef = 1;
                    /*%%%*/
                        $$ = new_kw_arg(p, assignable(p, $1, NODE_SPECIAL_REQUIRED_KEYWORD, &@$), &@$);
                    /*% %*/
                    /*% ripper: rb_assoc_new(get_value(assignable(p, $1)), 0) %*/
                    }
                ;

f_block_kw	: f_label primary_value
                    {
                        p->ctxt.in_argdef = 1;
                    /*%%%*/
                        $$ = new_kw_arg(p, assignable(p, $1, $2, &@$), &@$);
                    /*% %*/
                    /*% ripper: rb_assoc_new(get_value(assignable(p, $1)), get_value($2)) %*/
                    }
                | f_label
                    {
                        p->ctxt.in_argdef = 1;
                    /*%%%*/
                        $$ = new_kw_arg(p, assignable(p, $1, NODE_SPECIAL_REQUIRED_KEYWORD, &@$), &@$);
                    /*% %*/
                    /*% ripper: rb_assoc_new(get_value(assignable(p, $1)), 0) %*/
                    }
                ;

f_block_kwarg	: f_block_kw
                    {
                    /*%%%*/
                        $$ = $1;
                    /*% %*/
                    /*% ripper: rb_ary_new3(1, get_value($1)) %*/
                    }
                | f_block_kwarg ',' f_block_kw
                    {
                    /*%%%*/
                        $$ = kwd_append($1, $3);
                    /*% %*/
                    /*% ripper: rb_ary_push($1, get_value($3)) %*/
                    }
                ;


f_kwarg		: f_kw
                    {
                    /*%%%*/
                        $$ = $1;
                    /*% %*/
                    /*% ripper: rb_ary_new3(1, get_value($1)) %*/
                    }
                | f_kwarg ',' f_kw
                    {
                    /*%%%*/
                        $$ = kwd_append($1, $3);
                    /*% %*/
                    /*% ripper: rb_ary_push($1, get_value($3)) %*/
                    }
                ;

kwrest_mark	: tPOW
                | tDSTAR
                ;

f_no_kwarg	: p_kwnorest
                    {
                    /*%%%*/
                    /*% %*/
                    /*% ripper: nokw_param!(Qnil) %*/
                    }
                ;

f_kwrest	: kwrest_mark tIDENTIFIER
                    {
                        arg_var(p, shadowing_lvar(p, get_id($2)));
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: kwrest_param!($2) %*/
                    }
                | kwrest_mark
                    {
                        arg_var(p, idFWD_KWREST);
                    /*%%%*/
                        $$ = idFWD_KWREST;
                    /*% %*/
                    /*% ripper: kwrest_param!(Qnil) %*/
                    }
                ;

f_opt		: f_arg_asgn f_eq arg_value
                    {
                        p->cur_arg = 0;
                        p->ctxt.in_argdef = 1;
                    /*%%%*/
                        $$ = NEW_OPT_ARG(assignable(p, $1, $3, &@$), &@$);
                    /*% %*/
                    /*% ripper: rb_assoc_new(get_value(assignable(p, $1)), get_value($3)) %*/
                    }
                ;

f_block_opt	: f_arg_asgn f_eq primary_value
                    {
                        p->cur_arg = 0;
                        p->ctxt.in_argdef = 1;
                    /*%%%*/
                        $$ = NEW_OPT_ARG(assignable(p, $1, $3, &@$), &@$);
                    /*% %*/
                    /*% ripper: rb_assoc_new(get_value(assignable(p, $1)), get_value($3)) %*/
                    }
                ;

f_block_optarg	: f_block_opt
                    {
                    /*%%%*/
                        $$ = $1;
                    /*% %*/
                    /*% ripper: rb_ary_new3(1, get_value($1)) %*/
                    }
                | f_block_optarg ',' f_block_opt
                    {
                    /*%%%*/
                        $$ = opt_arg_append($1, $3);
                    /*% %*/
                    /*% ripper: rb_ary_push($1, get_value($3)) %*/
                    }
                ;

f_optarg	: f_opt
                    {
                    /*%%%*/
                        $$ = $1;
                    /*% %*/
                    /*% ripper: rb_ary_new3(1, get_value($1)) %*/
                    }
                | f_optarg ',' f_opt
                    {
                    /*%%%*/
                        $$ = opt_arg_append($1, $3);
                    /*% %*/
                    /*% ripper: rb_ary_push($1, get_value($3)) %*/
                    }
                ;

restarg_mark	: '*'
                | tSTAR
                ;

f_rest_arg	: restarg_mark tIDENTIFIER
                    {
                        arg_var(p, shadowing_lvar(p, get_id($2)));
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: rest_param!($2) %*/
                    }
                | restarg_mark
                    {
                        arg_var(p, idFWD_REST);
                    /*%%%*/
                        $$ = idFWD_REST;
                    /*% %*/
                    /*% ripper: rest_param!(Qnil) %*/
                    }
                ;

blkarg_mark	: '&'
                | tAMPER
                ;

f_block_arg	: blkarg_mark tIDENTIFIER
                    {
                        arg_var(p, shadowing_lvar(p, get_id($2)));
                    /*%%%*/
                        $$ = $2;
                    /*% %*/
                    /*% ripper: blockarg!($2) %*/
                    }
                | blkarg_mark
                    {
                        arg_var(p, idFWD_BLOCK);
                    /*%%%*/
                        $$ = idFWD_BLOCK;
                    /*% %*/
                    /*% ripper: blockarg!(Qnil) %*/
                    }
                ;

opt_f_block_arg	: ',' f_block_arg
                    {
                        $$ = $2;
                    }
                | none
                    {
                        $$ = Qnull;
                    }
                ;

singleton	: var_ref
                    {
                        value_expr($1);
                        $$ = $1;
                    }
                | '(' {SET_LEX_STATE(EXPR_BEG);} expr rparen
                    {
                    /*%%%*/
                        NODE *expr = last_expr_node($3);
                        switch (nd_type(expr)) {
                          case NODE_STR:
                          case NODE_DSTR:
                          case NODE_XSTR:
                          case NODE_DXSTR:
                          case NODE_DREGX:
                          case NODE_LIT:
                          case NODE_DSYM:
                          case NODE_LIST:
                          case NODE_ZLIST:
                            yyerror1(&expr->nd_loc, "can't define singleton method for literals");
                            break;
                          default:
                            value_expr($3);
                            break;
                        }
                        $$ = $3;
                    /*% %*/
                    /*% ripper: paren!($3) %*/
                    }
                ;

assoc_list	: none
                | assocs trailer
                    {
                    /*%%%*/
                        $$ = $1;
                    /*% %*/
                    /*% ripper: assoclist_from_args!($1) %*/
                    }
                ;

assocs		: assoc
                    /*% ripper[brace]: rb_ary_new3(1, get_value($1)) %*/
                | assocs ',' assoc
                    {
                    /*%%%*/
                        NODE *assocs = $1;
                        NODE *tail = $3;
                        if (!assocs) {
                            assocs = tail;
                        }
                        else if (tail) {
                            if (RNODE_LIST(assocs)->nd_head &&
                                !RNODE_LIST(tail)->nd_head && nd_type_p(RNODE_LIST(tail)->nd_next, NODE_LIST) &&
                                nd_type_p(RNODE_LIST(RNODE_LIST(tail)->nd_next)->nd_head, NODE_HASH)) {
                                /* DSTAR */
                                tail = RNODE_HASH(RNODE_LIST(RNODE_LIST(tail)->nd_next)->nd_head)->nd_head;
                            }
                            assocs = list_concat(assocs, tail);
                        }
                        $$ = assocs;
                    /*% %*/
                    /*% ripper: rb_ary_push($1, get_value($3)) %*/
                    }
                ;

assoc		: arg_value tASSOC arg_value
                    {
                    /*%%%*/
                        if (nd_type_p($1, NODE_STR)) {
                            nd_set_type($1, NODE_LIT);
                            RB_OBJ_WRITE(p->ast, &RNODE_LIT($1)->nd_lit, rb_fstring(RNODE_LIT($1)->nd_lit));
                        }
                        $$ = list_append(p, NEW_LIST($1, &@$), $3);
                    /*% %*/
                    /*% ripper: assoc_new!($1, $3) %*/
                    }
                | tLABEL arg_value
                    {
                    /*%%%*/
                        $$ = list_append(p, NEW_LIST(NEW_LIT(ID2SYM($1), &@1), &@$), $2);
                    /*% %*/
                    /*% ripper: assoc_new!($1, $2) %*/
                    }
                | tLABEL
                    {
                    /*%%%*/
                        NODE *val = gettable(p, $1, &@$);
                        if (!val) val = NEW_BEGIN(0, &@$);
                        $$ = list_append(p, NEW_LIST(NEW_LIT(ID2SYM($1), &@1), &@$), val);
                    /*% %*/
                    /*% ripper: assoc_new!($1, Qnil) %*/
                    }
                | tSTRING_BEG string_contents tLABEL_END arg_value
                    {
                    /*%%%*/
                        YYLTYPE loc = code_loc_gen(&@1, &@3);
                        $$ = list_append(p, NEW_LIST(dsym_node(p, $2, &loc), &loc), $4);
                    /*% %*/
                    /*% ripper: assoc_new!(dyna_symbol!($2), $4) %*/
                    }
                | tDSTAR arg_value
                    {
                    /*%%%*/
                        if (nd_type_p($2, NODE_HASH) &&
                            !(RNODE_HASH($2)->nd_head && RNODE_LIST(RNODE_HASH($2)->nd_head)->as.nd_alen)) {
                            static VALUE empty_hash;
                            if (!empty_hash) {
                                empty_hash = rb_obj_freeze(rb_hash_new());
                                rb_gc_register_mark_object(empty_hash);
                            }
                            $$ = list_append(p, NEW_LIST(0, &@$), NEW_LIT(empty_hash, &@$));
                        }
                        else
                            $$ = list_append(p, NEW_LIST(0, &@$), $2);
                    /*% %*/
                    /*% ripper: assoc_splat!($2) %*/
                    }
                | tDSTAR
                    {
                        forwarding_arg_check(p, idFWD_KWREST, idFWD_ALL, "keyword rest");
                    /*%%%*/
                        $$ = list_append(p, NEW_LIST(0, &@$),
                                         NEW_LVAR(idFWD_KWREST, &@$));
                    /*% %*/
                    /*% ripper: assoc_splat!(Qnil) %*/
                    }
                ;

operation	: tIDENTIFIER
                | tCONSTANT
                | tFID
                ;

operation2	: operation
                | op
                ;

operation3	: tIDENTIFIER
                | tFID
                | op
                ;

dot_or_colon	: '.'
                | tCOLON2
                ;

call_op 	: '.'
                | tANDDOT
                ;

call_op2	: call_op
                | tCOLON2
                ;

opt_terms	: /* none */
                | terms
                ;

opt_nl		: /* none */
                | '\n'
                ;

rparen		: opt_nl ')'
                ;

rbracket	: opt_nl ']'
                ;

rbrace		: opt_nl '}'
                ;

trailer		: opt_nl
                | ','
                ;

term		: ';' {yyerrok;token_flush(p);}
                | '\n'
                    {
                        @$.end_pos = @$.beg_pos;
                        token_flush(p);
                    }
                ;

terms		: term
                | terms ';' {yyerrok;}
                ;

none		: /* none */
                    {
                        $$ = Qnull;
                    }
                ;
%%
# undef p
# undef yylex
# undef yylval
# define yylval  (*p->lval)

static int regx_options(struct parser_params*);
static int tokadd_string(struct parser_params*,int,int,int,long*,rb_encoding**,rb_encoding**);
static void tokaddmbc(struct parser_params *p, int c, rb_encoding *enc);
static enum yytokentype parse_string(struct parser_params*,rb_strterm_literal_t*);
static enum yytokentype here_document(struct parser_params*,rb_strterm_heredoc_t*);

#ifndef RIPPER
# define set_yylval_node(x) {				\
  YYLTYPE _cur_loc;					\
  rb_parser_set_location(p, &_cur_loc);			\
  yylval.node = (x);					\
}
# define set_yylval_str(x) \
do { \
  set_yylval_node(NEW_STR(x, &_cur_loc)); \
  RB_OBJ_WRITTEN(p->ast, Qnil, x); \
} while(0)
# define set_yylval_literal(x) \
do { \
  set_yylval_node(NEW_LIT(x, &_cur_loc)); \
  RB_OBJ_WRITTEN(p->ast, Qnil, x); \
} while(0)
# define set_yylval_num(x) (yylval.num = (x))
# define set_yylval_id(x)  (yylval.id = (x))
# define set_yylval_name(x)  (yylval.id = (x))
# define yylval_id() (yylval.id)
#else
static inline VALUE
ripper_yylval_id(struct parser_params *p, ID x)
{
    return ripper_new_yylval(p, x, ID2SYM(x), 0);
}
# define set_yylval_str(x) (yylval.val = add_mark_object(p, (x)))
# define set_yylval_num(x) (yylval.val = ripper_new_yylval(p, (x), 0, 0))
# define set_yylval_id(x)  (void)(x)
# define set_yylval_name(x) (void)(yylval.val = ripper_yylval_id(p, x))
# define set_yylval_literal(x) add_mark_object(p, (x))
# define set_yylval_node(x) (yylval.val = ripper_new_yylval(p, 0, 0, STR_NEW(p->lex.ptok, p->lex.pcur-p->lex.ptok)))
# define yylval_id() yylval.id
# define _cur_loc NULL_LOC /* dummy */
#endif

#define set_yylval_noname() set_yylval_id(keyword_nil)
#define has_delayed_token(p) (!NIL_P(p->delayed.token))

#ifndef RIPPER
#define literal_flush(p, ptr) ((p)->lex.ptok = (ptr))
#define dispatch_scan_event(p, t) parser_dispatch_scan_event(p, t, __LINE__)

static bool
parser_has_token(struct parser_params *p)
{
    const char *const pcur = p->lex.pcur;
    const char *const ptok = p->lex.ptok;
    if (p->keep_tokens && (pcur < ptok)) {
        rb_bug("lex.pcur < lex.ptok. (line: %d) %"PRIdPTRDIFF"|%"PRIdPTRDIFF"|%"PRIdPTRDIFF"",
               p->ruby_sourceline, ptok - p->lex.pbeg, pcur - ptok, p->lex.pend - pcur);
    }
    return pcur > ptok;
}

static VALUE
code_loc_to_ary(struct parser_params *p, const rb_code_location_t *loc)
{
    VALUE ary = rb_ary_new_from_args(4,
        INT2NUM(loc->beg_pos.lineno), INT2NUM(loc->beg_pos.column),
        INT2NUM(loc->end_pos.lineno), INT2NUM(loc->end_pos.column));
    rb_obj_freeze(ary);

    return ary;
}

static void
parser_append_tokens(struct parser_params *p, VALUE str, enum yytokentype t, int line)
{
    VALUE ary;
    int token_id;

    ary = rb_ary_new2(4);
    token_id = p->token_id;
    rb_ary_push(ary, INT2FIX(token_id));
    rb_ary_push(ary, ID2SYM(parser_token2id(p, t)));
    rb_ary_push(ary, str);
    rb_ary_push(ary, code_loc_to_ary(p, p->yylloc));
    rb_obj_freeze(ary);
    rb_ary_push(p->tokens, ary);
    p->token_id++;

    if (p->debug) {
        rb_parser_printf(p, "Append tokens (line: %d) %"PRIsVALUE"\n", line, ary);
    }
}

static void
parser_dispatch_scan_event(struct parser_params *p, enum yytokentype t, int line)
{
    debug_token_line(p, "parser_dispatch_scan_event", line);

    if (!parser_has_token(p)) return;

    RUBY_SET_YYLLOC(*p->yylloc);

    if (p->keep_tokens) {
        VALUE str = STR_NEW(p->lex.ptok, p->lex.pcur - p->lex.ptok);
        parser_append_tokens(p, str, t, line);
    }

    token_flush(p);
}

#define dispatch_delayed_token(p, t) parser_dispatch_delayed_token(p, t, __LINE__)
static void
parser_dispatch_delayed_token(struct parser_params *p, enum yytokentype t, int line)
{
    debug_token_line(p, "parser_dispatch_delayed_token", line);

    if (!has_delayed_token(p)) return;

    RUBY_SET_YYLLOC_OF_DELAYED_TOKEN(*p->yylloc);

    if (p->keep_tokens) {
        parser_append_tokens(p, p->delayed.token, t, line);
    }

    p->delayed.token = Qnil;
}
#else
#define literal_flush(p, ptr) ((void)(ptr))

#define yylval_rval (*(RB_TYPE_P(yylval.val, T_NODE) ? &RNODE_RIPPER(yylval.node)->nd_rval : &yylval.val))

static int
ripper_has_scan_event(struct parser_params *p)
{
    if (p->lex.pcur < p->lex.ptok) rb_raise(rb_eRuntimeError, "lex.pcur < lex.ptok");
    return p->lex.pcur > p->lex.ptok;
}

static VALUE
ripper_scan_event_val(struct parser_params *p, enum yytokentype t)
{
    VALUE str = STR_NEW(p->lex.ptok, p->lex.pcur - p->lex.ptok);
    VALUE rval = ripper_dispatch1(p, ripper_token2eventid(t), str);
    RUBY_SET_YYLLOC(*p->yylloc);
    token_flush(p);
    return rval;
}

static void
ripper_dispatch_scan_event(struct parser_params *p, enum yytokentype t)
{
    if (!ripper_has_scan_event(p)) return;
    add_mark_object(p, yylval_rval = ripper_scan_event_val(p, t));
}
#define dispatch_scan_event(p, t) ripper_dispatch_scan_event(p, t)

static void
ripper_dispatch_delayed_token(struct parser_params *p, enum yytokentype t)
{
    /* save and adjust the location to delayed token for callbacks */
    int saved_line = p->ruby_sourceline;
    const char *saved_tokp = p->lex.ptok;

    if (!has_delayed_token(p)) return;
    p->ruby_sourceline = p->delayed.beg_line;
    p->lex.ptok = p->lex.pbeg + p->delayed.beg_col;
    add_mark_object(p, yylval_rval = ripper_dispatch1(p, ripper_token2eventid(t), p->delayed.token));
    p->delayed.token = Qnil;
    p->ruby_sourceline = saved_line;
    p->lex.ptok = saved_tokp;
}
#define dispatch_delayed_token(p, t) ripper_dispatch_delayed_token(p, t)
#endif /* RIPPER */

static inline int
is_identchar(struct parser_params *p, const char *ptr, const char *MAYBE_UNUSED(ptr_end), rb_encoding *enc)
{
    return rb_enc_isalnum((unsigned char)*ptr, enc) || *ptr == '_' || !ISASCII(*ptr);
}

static inline int
parser_is_identchar(struct parser_params *p)
{
    return !(p)->eofp && is_identchar(p, p->lex.pcur-1, p->lex.pend, p->enc);
}

static inline int
parser_isascii(struct parser_params *p)
{
    return ISASCII(*(p->lex.pcur-1));
}

static void
token_info_setup(token_info *ptinfo, const char *ptr, const rb_code_location_t *loc)
{
    int column = 1, nonspc = 0, i;
    for (i = 0; i < loc->beg_pos.column; i++, ptr++) {
        if (*ptr == '\t') {
            column = (((column - 1) / TAB_WIDTH) + 1) * TAB_WIDTH;
        }
        column++;
        if (*ptr != ' ' && *ptr != '\t') {
            nonspc = 1;
        }
    }

    ptinfo->beg = loc->beg_pos;
    ptinfo->indent = column;
    ptinfo->nonspc = nonspc;
}

static void
token_info_push(struct parser_params *p, const char *token, const rb_code_location_t *loc)
{
    token_info *ptinfo;

    if (!p->token_info_enabled) return;
    ptinfo = ALLOC(token_info);
    ptinfo->token = token;
    ptinfo->next = p->token_info;
    token_info_setup(ptinfo, p->lex.pbeg, loc);

    p->token_info = ptinfo;
}

static void
token_info_pop(struct parser_params *p, const char *token, const rb_code_location_t *loc)
{
    token_info *ptinfo_beg = p->token_info;

    if (!ptinfo_beg) return;
    p->token_info = ptinfo_beg->next;

    /* indentation check of matched keywords (begin..end, if..end, etc.) */
    token_info_warn(p, token, ptinfo_beg, 1, loc);
    ruby_sized_xfree(ptinfo_beg, sizeof(*ptinfo_beg));
}

static void
token_info_drop(struct parser_params *p, const char *token, rb_code_position_t beg_pos)
{
    token_info *ptinfo_beg = p->token_info;

    if (!ptinfo_beg) return;
    p->token_info = ptinfo_beg->next;

    if (ptinfo_beg->beg.lineno != beg_pos.lineno ||
        ptinfo_beg->beg.column != beg_pos.column ||
        strcmp(ptinfo_beg->token, token)) {
        compile_error(p, "token position mismatch: %d:%d:%s expected but %d:%d:%s",
                      beg_pos.lineno, beg_pos.column, token,
                      ptinfo_beg->beg.lineno, ptinfo_beg->beg.column,
                      ptinfo_beg->token);
    }

    ruby_sized_xfree(ptinfo_beg, sizeof(*ptinfo_beg));
}

static void
token_info_warn(struct parser_params *p, const char *token, token_info *ptinfo_beg, int same, const rb_code_location_t *loc)
{
    token_info ptinfo_end_body, *ptinfo_end = &ptinfo_end_body;
    if (!p->token_info_enabled) return;
    if (!ptinfo_beg) return;
    token_info_setup(ptinfo_end, p->lex.pbeg, loc);
    if (ptinfo_beg->beg.lineno == ptinfo_end->beg.lineno) return; /* ignore one-line block */
    if (ptinfo_beg->nonspc || ptinfo_end->nonspc) return; /* ignore keyword in the middle of a line */
    if (ptinfo_beg->indent == ptinfo_end->indent) return; /* the indents are matched */
    if (!same && ptinfo_beg->indent < ptinfo_end->indent) return;
    rb_warn3L(ptinfo_end->beg.lineno,
              "mismatched indentations at '%s' with '%s' at %d",
              WARN_S(token), WARN_S(ptinfo_beg->token), WARN_I(ptinfo_beg->beg.lineno));
}

static int
parser_precise_mbclen(struct parser_params *p, const char *ptr)
{
    int len = rb_enc_precise_mbclen(ptr, p->lex.pend, p->enc);
    if (!MBCLEN_CHARFOUND_P(len)) {
        compile_error(p, "invalid multibyte char (%s)", rb_enc_name(p->enc));
        return -1;
    }
    return len;
}

#ifndef RIPPER
static void ruby_show_error_line(struct parser_params *p, VALUE errbuf, const YYLTYPE *yylloc, int lineno, VALUE str);

static inline void
parser_show_error_line(struct parser_params *p, const YYLTYPE *yylloc)
{
    VALUE str;
    int lineno = p->ruby_sourceline;
    if (!yylloc) {
        return;
    }
    else if (yylloc->beg_pos.lineno == lineno) {
        str = p->lex.lastline;
    }
    else {
        return;
    }
    ruby_show_error_line(p, p->error_buffer, yylloc, lineno, str);
}

static int
parser_yyerror(struct parser_params *p, const rb_code_location_t *yylloc, const char *msg)
{
#if 0
    YYLTYPE current;

    if (!yylloc) {
        yylloc = RUBY_SET_YYLLOC(current);
    }
    else if ((p->ruby_sourceline != yylloc->beg_pos.lineno &&
              p->ruby_sourceline != yylloc->end_pos.lineno)) {
        yylloc = 0;
    }
#endif
    parser_compile_error(p, yylloc, "%s", msg);
    parser_show_error_line(p, yylloc);
    return 0;
}

static int
parser_yyerror0(struct parser_params *p, const char *msg)
{
    YYLTYPE current;
    return parser_yyerror(p, RUBY_SET_YYLLOC(current), msg);
}

static void
ruby_show_error_line(struct parser_params *p, VALUE errbuf, const YYLTYPE *yylloc, int lineno, VALUE str)
{
    VALUE mesg;
    const int max_line_margin = 30;
    const char *ptr, *ptr_end, *pt, *pb;
    const char *pre = "", *post = "", *pend;
    const char *code = "", *caret = "";
    const char *lim;
    const char *const pbeg = RSTRING_PTR(str);
    char *buf;
    long len;
    int i;

    if (!yylloc) return;
    pend = RSTRING_END(str);
    if (pend > pbeg && pend[-1] == '\n') {
        if (--pend > pbeg && pend[-1] == '\r') --pend;
    }

    pt = pend;
    if (lineno == yylloc->end_pos.lineno &&
        (pend - pbeg) > yylloc->end_pos.column) {
        pt = pbeg + yylloc->end_pos.column;
    }

    ptr = ptr_end = pt;
    lim = ptr - pbeg > max_line_margin ? ptr - max_line_margin : pbeg;
    while ((lim < ptr) && (*(ptr-1) != '\n')) ptr--;

    lim = pend - ptr_end > max_line_margin ? ptr_end + max_line_margin : pend;
    while ((ptr_end < lim) && (*ptr_end != '\n') && (*ptr_end != '\r')) ptr_end++;

    len = ptr_end - ptr;
    if (len > 4) {
        if (ptr > pbeg) {
            ptr = rb_enc_prev_char(pbeg, ptr, pt, rb_enc_get(str));
            if (ptr > pbeg) pre = "...";
        }
        if (ptr_end < pend) {
            ptr_end = rb_enc_prev_char(pt, ptr_end, pend, rb_enc_get(str));
            if (ptr_end < pend) post = "...";
        }
    }
    pb = pbeg;
    if (lineno == yylloc->beg_pos.lineno) {
        pb += yylloc->beg_pos.column;
        if (pb > pt) pb = pt;
    }
    if (pb < ptr) pb = ptr;
    if (len <= 4 && yylloc->beg_pos.lineno == yylloc->end_pos.lineno) {
        return;
    }
    if (RTEST(errbuf)) {
        mesg = rb_attr_get(errbuf, idMesg);
        if (RSTRING_LEN(mesg) > 0 && *(RSTRING_END(mesg)-1) != '\n')
            rb_str_cat_cstr(mesg, "\n");
    }
    else {
        mesg = rb_enc_str_new(0, 0, rb_enc_get(str));
    }
    if (!errbuf && rb_stderr_tty_p()) {
#define CSI_BEGIN "\033["
#define CSI_SGR "m"
        rb_str_catf(mesg,
                    CSI_BEGIN""CSI_SGR"%s" /* pre */
                    CSI_BEGIN"1"CSI_SGR"%.*s"
                    CSI_BEGIN"1;4"CSI_SGR"%.*s"
                    CSI_BEGIN";1"CSI_SGR"%.*s"
                    CSI_BEGIN""CSI_SGR"%s" /* post */
                    "\n",
                    pre,
                    (int)(pb - ptr), ptr,
                    (int)(pt - pb), pb,
                    (int)(ptr_end - pt), pt,
                    post);
    }
    else {
        char *p2;

        len = ptr_end - ptr;
        lim = pt < pend ? pt : pend;
        i = (int)(lim - ptr);
        buf = ALLOCA_N(char, i+2);
        code = ptr;
        caret = p2 = buf;
        if (ptr <= pb) {
            while (ptr < pb) {
                *p2++ = *ptr++ == '\t' ? '\t' : ' ';
            }
            *p2++ = '^';
            ptr++;
        }
        if (lim > ptr) {
            memset(p2, '~', (lim - ptr));
            p2 += (lim - ptr);
        }
        *p2 = '\0';
        rb_str_catf(mesg, "%s%.*s%s\n""%s%s\n",
                    pre, (int)len, code, post,
                    pre, caret);
    }
    if (!errbuf) rb_write_error_str(mesg);
}
#else
static int
parser_yyerror(struct parser_params *p, const YYLTYPE *yylloc, const char *msg)
{
    const char *pcur = 0, *ptok = 0;
    if (p->ruby_sourceline == yylloc->beg_pos.lineno &&
        p->ruby_sourceline == yylloc->end_pos.lineno) {
        pcur = p->lex.pcur;
        ptok = p->lex.ptok;
        p->lex.ptok = p->lex.pbeg + yylloc->beg_pos.column;
        p->lex.pcur = p->lex.pbeg + yylloc->end_pos.column;
    }
    parser_yyerror0(p, msg);
    if (pcur) {
        p->lex.ptok = ptok;
        p->lex.pcur = pcur;
    }
    return 0;
}

static int
parser_yyerror0(struct parser_params *p, const char *msg)
{
    dispatch1(parse_error, STR_NEW2(msg));
    ripper_error(p);
    return 0;
}

static inline void
parser_show_error_line(struct parser_params *p, const YYLTYPE *yylloc)
{
}
#endif /* !RIPPER */

#ifndef RIPPER
static int
vtable_size(const struct vtable *tbl)
{
    if (!DVARS_TERMINAL_P(tbl)) {
        return tbl->pos;
    }
    else {
        return 0;
    }
}
#endif

static struct vtable *
vtable_alloc_gen(struct parser_params *p, int line, struct vtable *prev)
{
    struct vtable *tbl = ALLOC(struct vtable);
    tbl->pos = 0;
    tbl->capa = 8;
    tbl->tbl = ALLOC_N(ID, tbl->capa);
    tbl->prev = prev;
#ifndef RIPPER
    if (p->debug) {
        rb_parser_printf(p, "vtable_alloc:%d: %p\n", line, (void *)tbl);
    }
#endif
    return tbl;
}
#define vtable_alloc(prev) vtable_alloc_gen(p, __LINE__, prev)

static void
vtable_free_gen(struct parser_params *p, int line, const char *name,
                struct vtable *tbl)
{
#ifndef RIPPER
    if (p->debug) {
        rb_parser_printf(p, "vtable_free:%d: %s(%p)\n", line, name, (void *)tbl);
    }
#endif
    if (!DVARS_TERMINAL_P(tbl)) {
        if (tbl->tbl) {
            ruby_sized_xfree(tbl->tbl, tbl->capa * sizeof(ID));
        }
        ruby_sized_xfree(tbl, sizeof(*tbl));
    }
}
#define vtable_free(tbl) vtable_free_gen(p, __LINE__, #tbl, tbl)

static void
vtable_add_gen(struct parser_params *p, int line, const char *name,
               struct vtable *tbl, ID id)
{
#ifndef RIPPER
    if (p->debug) {
        rb_parser_printf(p, "vtable_add:%d: %s(%p), %s\n",
                         line, name, (void *)tbl, rb_id2name(id));
    }
#endif
    if (DVARS_TERMINAL_P(tbl)) {
        rb_parser_fatal(p, "vtable_add: vtable is not allocated (%p)", (void *)tbl);
        return;
    }
    if (tbl->pos == tbl->capa) {
        tbl->capa = tbl->capa * 2;
        SIZED_REALLOC_N(tbl->tbl, ID, tbl->capa, tbl->pos);
    }
    tbl->tbl[tbl->pos++] = id;
}
#define vtable_add(tbl, id) vtable_add_gen(p, __LINE__, #tbl, tbl, id)

#ifndef RIPPER
static void
vtable_pop_gen(struct parser_params *p, int line, const char *name,
               struct vtable *tbl, int n)
{
    if (p->debug) {
        rb_parser_printf(p, "vtable_pop:%d: %s(%p), %d\n",
                         line, name, (void *)tbl, n);
    }
    if (tbl->pos < n) {
        rb_parser_fatal(p, "vtable_pop: unreachable (%d < %d)", tbl->pos, n);
        return;
    }
    tbl->pos -= n;
}
#define vtable_pop(tbl, n) vtable_pop_gen(p, __LINE__, #tbl, tbl, n)
#endif

static int
vtable_included(const struct vtable * tbl, ID id)
{
    int i;

    if (!DVARS_TERMINAL_P(tbl)) {
        for (i = 0; i < tbl->pos; i++) {
            if (tbl->tbl[i] == id) {
                return i+1;
            }
        }
    }
    return 0;
}

static void parser_prepare(struct parser_params *p);

#ifndef RIPPER
static NODE *parser_append_options(struct parser_params *p, NODE *node);

static int
e_option_supplied(struct parser_params *p)
{
    return strcmp(p->ruby_sourcefile, "-e") == 0;
}

static VALUE
yycompile0(VALUE arg)
{
    int n;
    NODE *tree;
    struct parser_params *p = (struct parser_params *)arg;
    int cov = FALSE;

    if (!compile_for_eval && !NIL_P(p->ruby_sourcefile_string)) {
        if (p->debug_lines && p->ruby_sourceline > 0) {
            VALUE str = rb_default_rs;
            n = p->ruby_sourceline;
            do {
                rb_ary_push(p->debug_lines, str);
            } while (--n);
        }

        if (!e_option_supplied(p)) {
            cov = TRUE;
        }
    }

    if (p->debug_lines) {
        RB_OBJ_WRITE(p->ast, &p->ast->body.script_lines, p->debug_lines);
    }

    parser_prepare(p);
#define RUBY_DTRACE_PARSE_HOOK(name) \
    if (RUBY_DTRACE_PARSE_##name##_ENABLED()) { \
        RUBY_DTRACE_PARSE_##name(p->ruby_sourcefile, p->ruby_sourceline); \
    }
    RUBY_DTRACE_PARSE_HOOK(BEGIN);
    n = yyparse(p);
    RUBY_DTRACE_PARSE_HOOK(END);
    p->debug_lines = 0;

    p->lex.strterm = 0;
    p->lex.pcur = p->lex.pbeg = p->lex.pend = 0;
    if (n || p->error_p) {
        VALUE mesg = p->error_buffer;
        if (!mesg) {
            mesg = syntax_error_new();
        }
        if (!p->error_tolerant) {
            rb_set_errinfo(mesg);
            return FALSE;
        }
    }
    tree = p->eval_tree;
    if (!tree) {
        tree = NEW_NIL(&NULL_LOC);
    }
    else {
        VALUE tokens = p->tokens;
        NODE *prelude;
        NODE *body = parser_append_options(p, RNODE_SCOPE(tree)->nd_body);
        prelude = block_append(p, p->eval_tree_begin, body);
        RNODE_SCOPE(tree)->nd_body = prelude;
        p->ast->body.frozen_string_literal = p->frozen_string_literal;
        p->ast->body.coverage_enabled = cov;
        if (p->keep_tokens) {
            rb_obj_freeze(tokens);
            rb_ast_set_tokens(p->ast, tokens);
        }
    }
    p->ast->body.root = tree;
    if (!p->ast->body.script_lines) p->ast->body.script_lines = INT2FIX(p->line_count);
    return TRUE;
}

static rb_ast_t *
yycompile(struct parser_params *p, VALUE fname, int line)
{
    rb_ast_t *ast;
    if (NIL_P(fname)) {
        p->ruby_sourcefile_string = Qnil;
        p->ruby_sourcefile = "(none)";
    }
    else {
        p->ruby_sourcefile_string = rb_fstring(fname);
        p->ruby_sourcefile = StringValueCStr(fname);
    }
    p->ruby_sourceline = line - 1;

    p->lvtbl = NULL;

    p->ast = ast = rb_ast_new();
    compile_callback(yycompile0, (VALUE)p);
    p->ast = 0;

    while (p->lvtbl) {
        local_pop(p);
    }

    return ast;
}
#endif /* !RIPPER */

static rb_encoding *
must_be_ascii_compatible(struct parser_params *p, VALUE s)
{
    rb_encoding *enc = rb_enc_get(s);
    if (!rb_enc_asciicompat(enc)) {
        rb_raise(rb_eArgError, "invalid source encoding");
    }
    return enc;
}

static VALUE
lex_get_str(struct parser_params *p, VALUE s)
{
    char *beg, *end, *start;
    long len;

    beg = RSTRING_PTR(s);
    len = RSTRING_LEN(s);
    start = beg;
    if (p->lex.gets_.ptr) {
        if (len == p->lex.gets_.ptr) return Qnil;
        beg += p->lex.gets_.ptr;
        len -= p->lex.gets_.ptr;
    }
    end = memchr(beg, '\n', len);
    if (end) len = ++end - beg;
    p->lex.gets_.ptr += len;
    return rb_str_subseq(s, beg - start, len);
}

static VALUE
lex_getline(struct parser_params *p)
{
    VALUE line = (*p->lex.gets)(p, p->lex.input);
    if (NIL_P(line)) return line;
    must_be_ascii_compatible(p, line);
    if (RB_OBJ_FROZEN(line)) line = rb_str_dup(line); // needed for RubyVM::AST.of because script_lines in iseq is deep-frozen
    p->line_count++;
    return line;
}

#ifndef RIPPER
static rb_ast_t*
parser_compile_string(rb_parser_t *p, VALUE fname, VALUE s, int line)
{
    p->lex.gets = lex_get_str;
    p->lex.gets_.ptr = 0;
    p->lex.input = rb_str_new_frozen(s);
    p->lex.pbeg = p->lex.pcur = p->lex.pend = 0;

    return yycompile(p, fname, line);
}

rb_ast_t*
rb_ruby_parser_compile_string_path(rb_parser_t *p, VALUE f, VALUE s, int line)
{
    must_be_ascii_compatible(p, s);
    return parser_compile_string(p, f, s, line);
}

rb_ast_t*
rb_ruby_parser_compile_string(rb_parser_t *p, const char *f, VALUE s, int line)
{
    return rb_ruby_parser_compile_string_path(p, rb_filesystem_str_new_cstr(f), s, line);
}

static VALUE
lex_io_gets(struct parser_params *p, VALUE io)
{
    return rb_io_gets_internal(io);
}

rb_ast_t*
rb_ruby_parser_compile_file_path(rb_parser_t *p, VALUE fname, VALUE file, int start)
{
    p->lex.gets = lex_io_gets;
    p->lex.input = file;
    p->lex.pbeg = p->lex.pcur = p->lex.pend = 0;

    return yycompile(p, fname, start);
}

static VALUE
lex_generic_gets(struct parser_params *p, VALUE input)
{
    return (*p->lex.gets_.call)(input, p->line_count);
}

rb_ast_t*
rb_ruby_parser_compile_generic(rb_parser_t *p, VALUE (*lex_gets)(VALUE, int), VALUE fname, VALUE input, int start)
{
    p->lex.gets = lex_generic_gets;
    p->lex.gets_.call = lex_gets;
    p->lex.input = input;
    p->lex.pbeg = p->lex.pcur = p->lex.pend = 0;

    return yycompile(p, fname, start);
}
#endif  /* !RIPPER */

#define STR_FUNC_ESCAPE 0x01
#define STR_FUNC_EXPAND 0x02
#define STR_FUNC_REGEXP 0x04
#define STR_FUNC_QWORDS 0x08
#define STR_FUNC_SYMBOL 0x10
#define STR_FUNC_INDENT 0x20
#define STR_FUNC_LABEL  0x40
#define STR_FUNC_LIST   0x4000
#define STR_FUNC_TERM   0x8000

enum string_type {
    str_label  = STR_FUNC_LABEL,
    str_squote = (0),
    str_dquote = (STR_FUNC_EXPAND),
    str_xquote = (STR_FUNC_EXPAND),
    str_regexp = (STR_FUNC_REGEXP|STR_FUNC_ESCAPE|STR_FUNC_EXPAND),
    str_sword  = (STR_FUNC_QWORDS|STR_FUNC_LIST),
    str_dword  = (STR_FUNC_QWORDS|STR_FUNC_EXPAND|STR_FUNC_LIST),
    str_ssym   = (STR_FUNC_SYMBOL),
    str_dsym   = (STR_FUNC_SYMBOL|STR_FUNC_EXPAND)
};

static VALUE
parser_str_new(struct parser_params *p, const char *ptr, long len, rb_encoding *enc, int func, rb_encoding *enc0)
{
    VALUE str;

    str = rb_enc_str_new(ptr, len, enc);
    if (!(func & STR_FUNC_REGEXP) && rb_enc_asciicompat(enc)) {
        if (is_ascii_string(str)) {
        }
        else if (rb_is_usascii_enc((void *)enc0) && enc != rb_utf8_encoding()) {
            rb_enc_associate(str, rb_ascii8bit_encoding());
        }
    }

    return str;
}

static int
strterm_is_heredoc(rb_strterm_t *strterm)
{
    return strterm->flags & STRTERM_HEREDOC;
}

static rb_strterm_t *
new_strterm(struct parser_params *p, int func, int term, int paren)
{
    rb_strterm_t *strterm = ZALLOC(rb_strterm_t);
    strterm->u.literal.func = func;
    strterm->u.literal.term = term;
    strterm->u.literal.paren = paren;
    return strterm;
}

static rb_strterm_t *
new_heredoc(struct parser_params *p)
{
    rb_strterm_t *strterm = ZALLOC(rb_strterm_t);
    strterm->flags |= STRTERM_HEREDOC;
    return strterm;
}

#define peek(p,c) peek_n(p, (c), 0)
#define peek_n(p,c,n) (!lex_eol_n_p(p, n) && (c) == (unsigned char)(p)->lex.pcur[n])
#define peekc(p) peekc_n(p, 0)
#define peekc_n(p,n) (lex_eol_n_p(p, n) ? -1 : (unsigned char)(p)->lex.pcur[n])

static void
add_delayed_token(struct parser_params *p, const char *tok, const char *end, int line)
{
#ifndef RIPPER
    debug_token_line(p, "add_delayed_token", line);
#endif

    if (tok < end) {
        if (has_delayed_token(p)) {
            bool next_line = end_with_newline_p(p, p->delayed.token);
            int end_line = (next_line ? 1 : 0) + p->delayed.end_line;
            int end_col = (next_line ? 0 : p->delayed.end_col);
            if (end_line != p->ruby_sourceline || end_col != tok - p->lex.pbeg) {
                dispatch_delayed_token(p, tSTRING_CONTENT);
            }
        }
        if (!has_delayed_token(p)) {
            p->delayed.token = rb_str_buf_new(end - tok);
            rb_enc_associate(p->delayed.token, p->enc);
            p->delayed.beg_line = p->ruby_sourceline;
            p->delayed.beg_col = rb_long2int(tok - p->lex.pbeg);
        }
        rb_str_buf_cat(p->delayed.token, tok, end - tok);
        p->delayed.end_line = p->ruby_sourceline;
        p->delayed.end_col = rb_long2int(end - p->lex.pbeg);
        p->lex.ptok = end;
    }
}

static void
set_lastline(struct parser_params *p, VALUE v)
{
    p->lex.pbeg = p->lex.pcur = RSTRING_PTR(v);
    p->lex.pend = p->lex.pcur + RSTRING_LEN(v);
    p->lex.lastline = v;
}

static int
nextline(struct parser_params *p, int set_encoding)
{
    VALUE v = p->lex.nextline;
    p->lex.nextline = 0;
    if (!v) {
        if (p->eofp)
            return -1;

        if (!lex_eol_ptr_p(p, p->lex.pbeg) && *(p->lex.pend-1) != '\n') {
            goto end_of_input;
        }

        if (!p->lex.input || NIL_P(v = lex_getline(p))) {
          end_of_input:
            p->eofp = 1;
            lex_goto_eol(p);
            return -1;
        }
#ifndef RIPPER
        if (p->debug_lines) {
            if (set_encoding) rb_enc_associate(v, p->enc);
            rb_ary_push(p->debug_lines, v);
        }
#endif
        p->cr_seen = FALSE;
    }
    else if (NIL_P(v)) {
        /* after here-document without terminator */
        goto end_of_input;
    }
    add_delayed_token(p, p->lex.ptok, p->lex.pend, __LINE__);
    if (p->heredoc_end > 0) {
        p->ruby_sourceline = p->heredoc_end;
        p->heredoc_end = 0;
    }
    p->ruby_sourceline++;
    set_lastline(p, v);
    token_flush(p);
    return 0;
}

static int
parser_cr(struct parser_params *p, int c)
{
    if (peek(p, '\n')) {
        p->lex.pcur++;
        c = '\n';
    }
    return c;
}

static inline int
nextc0(struct parser_params *p, int set_encoding)
{
    int c;

    if (UNLIKELY(lex_eol_p(p) || p->eofp || RTEST(p->lex.nextline))) {
        if (nextline(p, set_encoding)) return -1;
    }
    c = (unsigned char)*p->lex.pcur++;
    if (UNLIKELY(c == '\r')) {
        c = parser_cr(p, c);
    }

    return c;
}
#define nextc(p) nextc0(p, TRUE)

static void
pushback(struct parser_params *p, int c)
{
    if (c == -1) return;
    p->eofp = 0;
    p->lex.pcur--;
    if (p->lex.pcur > p->lex.pbeg && p->lex.pcur[0] == '\n' && p->lex.pcur[-1] == '\r') {
        p->lex.pcur--;
    }
}

#define was_bol(p) ((p)->lex.pcur == (p)->lex.pbeg + 1)

#define tokfix(p) ((p)->tokenbuf[(p)->tokidx]='\0')
#define tok(p) (p)->tokenbuf
#define toklen(p) (p)->tokidx

static int
looking_at_eol_p(struct parser_params *p)
{
    const char *ptr = p->lex.pcur;
    while (!lex_eol_ptr_p(p, ptr)) {
        int c = (unsigned char)*ptr++;
        int eol = (c == '\n' || c == '#');
        if (eol || !ISSPACE(c)) {
            return eol;
        }
    }
    return TRUE;
}

static char*
newtok(struct parser_params *p)
{
    p->tokidx = 0;
    if (!p->tokenbuf) {
        p->toksiz = 60;
        p->tokenbuf = ALLOC_N(char, 60);
    }
    if (p->toksiz > 4096) {
        p->toksiz = 60;
        REALLOC_N(p->tokenbuf, char, 60);
    }
    return p->tokenbuf;
}

static char *
tokspace(struct parser_params *p, int n)
{
    p->tokidx += n;

    if (p->tokidx >= p->toksiz) {
        do {p->toksiz *= 2;} while (p->toksiz < p->tokidx);
        REALLOC_N(p->tokenbuf, char, p->toksiz);
    }
    return &p->tokenbuf[p->tokidx-n];
}

static void
tokadd(struct parser_params *p, int c)
{
    p->tokenbuf[p->tokidx++] = (char)c;
    if (p->tokidx >= p->toksiz) {
        p->toksiz *= 2;
        REALLOC_N(p->tokenbuf, char, p->toksiz);
    }
}

static int
tok_hex(struct parser_params *p, size_t *numlen)
{
    int c;

    c = (int)ruby_scan_hex(p->lex.pcur, 2, numlen);
    if (!*numlen) {
        yyerror0("invalid hex escape");
        dispatch_scan_event(p, tSTRING_CONTENT);
        return 0;
    }
    p->lex.pcur += *numlen;
    return c;
}

#define tokcopy(p, n) memcpy(tokspace(p, n), (p)->lex.pcur - (n), (n))

static int
escaped_control_code(int c)
{
    int c2 = 0;
    switch (c) {
      case ' ':
        c2 = 's';
        break;
      case '\n':
        c2 = 'n';
        break;
      case '\t':
        c2 = 't';
        break;
      case '\v':
        c2 = 'v';
        break;
      case '\r':
        c2 = 'r';
        break;
      case '\f':
        c2 = 'f';
        break;
    }
    return c2;
}

#define WARN_SPACE_CHAR(c, prefix) \
    rb_warn1("invalid character syntax; use "prefix"\\%c", WARN_I(c2))

static int
tokadd_codepoint(struct parser_params *p, rb_encoding **encp,
                 int regexp_literal, int wide)
{
    size_t numlen;
    int codepoint = (int)ruby_scan_hex(p->lex.pcur, wide ? p->lex.pend - p->lex.pcur : 4, &numlen);
    p->lex.pcur += numlen;
    if (p->lex.strterm == NULL ||
        strterm_is_heredoc(p->lex.strterm) ||
        (p->lex.strterm->u.literal.func != str_regexp)) {
        if (wide ? (numlen == 0 || numlen > 6) : (numlen < 4))  {
            literal_flush(p, p->lex.pcur);
            yyerror0("invalid Unicode escape");
            return wide && numlen > 0;
        }
        if (codepoint > 0x10ffff) {
            literal_flush(p, p->lex.pcur);
            yyerror0("invalid Unicode codepoint (too large)");
            return wide;
        }
        if ((codepoint & 0xfffff800) == 0xd800) {
            literal_flush(p, p->lex.pcur);
            yyerror0("invalid Unicode codepoint");
            return wide;
        }
    }
    if (regexp_literal) {
        tokcopy(p, (int)numlen);
    }
    else if (codepoint >= 0x80) {
        rb_encoding *utf8 = rb_utf8_encoding();
        if (*encp && utf8 != *encp) {
            YYLTYPE loc = RUBY_INIT_YYLLOC();
            compile_error(p, "UTF-8 mixed within %s source", rb_enc_name(*encp));
            parser_show_error_line(p, &loc);
            return wide;
        }
        *encp = utf8;
        tokaddmbc(p, codepoint, *encp);
    }
    else {
        tokadd(p, codepoint);
    }
    return TRUE;
}

static int tokadd_mbchar(struct parser_params *p, int c);

static int
tokskip_mbchar(struct parser_params *p)
{
    int len = parser_precise_mbclen(p, p->lex.pcur-1);
    if (len > 0) {
        p->lex.pcur += len - 1;
    }
    return len;
}

/* return value is for ?\u3042 */
static void
tokadd_utf8(struct parser_params *p, rb_encoding **encp,
            int term, int symbol_literal, int regexp_literal)
{
    /*
     * If `term` is not -1, then we allow multiple codepoints in \u{}
     * upto `term` byte, otherwise we're parsing a character literal.
     * And then add the codepoints to the current token.
     */
    static const char multiple_codepoints[] = "Multiple codepoints at single character literal";

    const int open_brace = '{', close_brace = '}';

    if (regexp_literal) { tokadd(p, '\\'); tokadd(p, 'u'); }

    if (peek(p, open_brace)) {  /* handle \u{...} form */
        if (regexp_literal && p->lex.strterm->u.literal.func == str_regexp) {
            /*
             * Skip parsing validation code and copy bytes as-is until term or
             * closing brace, in order to correctly handle extended regexps where
             * invalid unicode escapes are allowed in comments. The regexp parser
             * does its own validation and will catch any issues.
             */
            tokadd(p, open_brace);
            while (!lex_eol_ptr_p(p, ++p->lex.pcur)) {
                int c = peekc(p);
                if (c == close_brace) {
                    tokadd(p, c);
                    ++p->lex.pcur;
                    break;
                }
                else if (c == term) {
                    break;
                }
                if (c == '\\' && !lex_eol_n_p(p, 1)) {
                    tokadd(p, c);
                    c = *++p->lex.pcur;
                }
                tokadd_mbchar(p, c);
            }
        }
        else {
            const char *second = NULL;
            int c, last = nextc(p);
            if (lex_eol_p(p)) goto unterminated;
            while (ISSPACE(c = peekc(p)) && !lex_eol_ptr_p(p, ++p->lex.pcur));
            while (c != close_brace) {
                if (c == term) goto unterminated;
                if (second == multiple_codepoints)
                    second = p->lex.pcur;
                if (regexp_literal) tokadd(p, last);
                if (!tokadd_codepoint(p, encp, regexp_literal, TRUE)) {
                    break;
                }
                while (ISSPACE(c = peekc(p))) {
                    if (lex_eol_ptr_p(p, ++p->lex.pcur)) goto unterminated;
                    last = c;
                }
                if (term == -1 && !second)
                    second = multiple_codepoints;
            }

            if (c != close_brace) {
              unterminated:
                token_flush(p);
                yyerror0("unterminated Unicode escape");
                return;
            }
            if (second && second != multiple_codepoints) {
                const char *pcur = p->lex.pcur;
                p->lex.pcur = second;
                dispatch_scan_event(p, tSTRING_CONTENT);
                token_flush(p);
                p->lex.pcur = pcur;
                yyerror0(multiple_codepoints);
                token_flush(p);
            }

            if (regexp_literal) tokadd(p, close_brace);
            nextc(p);
        }
    }
    else {			/* handle \uxxxx form */
        if (!tokadd_codepoint(p, encp, regexp_literal, FALSE)) {
            token_flush(p);
            return;
        }
    }
}

#define ESCAPE_CONTROL 1
#define ESCAPE_META    2

static int
read_escape(struct parser_params *p, int flags)
{
    int c;
    size_t numlen;

    switch (c = nextc(p)) {
      case '\\':	/* Backslash */
        return c;

      case 'n':	/* newline */
        return '\n';

      case 't':	/* horizontal tab */
        return '\t';

      case 'r':	/* carriage-return */
        return '\r';

      case 'f':	/* form-feed */
        return '\f';

      case 'v':	/* vertical tab */
        return '\13';

      case 'a':	/* alarm(bell) */
        return '\007';

      case 'e':	/* escape */
        return 033;

      case '0': case '1': case '2': case '3': /* octal constant */
      case '4': case '5': case '6': case '7':
        pushback(p, c);
        c = (int)ruby_scan_oct(p->lex.pcur, 3, &numlen);
        p->lex.pcur += numlen;
        return c;

      case 'x':	/* hex constant */
        c = tok_hex(p, &numlen);
        if (numlen == 0) return 0;
        return c;

      case 'b':	/* backspace */
        return '\010';

      case 's':	/* space */
        return ' ';

      case 'M':
        if (flags & ESCAPE_META) goto eof;
        if ((c = nextc(p)) != '-') {
            goto eof;
        }
        if ((c = nextc(p)) == '\\') {
            switch (peekc(p)) {
              case 'u': case 'U':
                nextc(p);
                goto eof;
            }
            return read_escape(p, flags|ESCAPE_META) | 0x80;
        }
        else if (c == -1 || !ISASCII(c)) goto eof;
        else {
            int c2 = escaped_control_code(c);
            if (c2) {
                if (ISCNTRL(c) || !(flags & ESCAPE_CONTROL)) {
                    WARN_SPACE_CHAR(c2, "\\M-");
                }
                else {
                    WARN_SPACE_CHAR(c2, "\\C-\\M-");
                }
            }
            else if (ISCNTRL(c)) goto eof;
            return ((c & 0xff) | 0x80);
        }

      case 'C':
        if ((c = nextc(p)) != '-') {
            goto eof;
        }
      case 'c':
        if (flags & ESCAPE_CONTROL) goto eof;
        if ((c = nextc(p))== '\\') {
            switch (peekc(p)) {
              case 'u': case 'U':
                nextc(p);
                goto eof;
            }
            c = read_escape(p, flags|ESCAPE_CONTROL);
        }
        else if (c == '?')
            return 0177;
        else if (c == -1) goto eof;
        else if (!ISASCII(c)) {
            tokskip_mbchar(p);
            goto eof;
        }
        else {
            int c2 = escaped_control_code(c);
            if (c2) {
                if (ISCNTRL(c)) {
                    if (flags & ESCAPE_META) {
                        WARN_SPACE_CHAR(c2, "\\M-");
                    }
                    else {
                        WARN_SPACE_CHAR(c2, "");
                    }
                }
                else {
                    if (flags & ESCAPE_META) {
                        WARN_SPACE_CHAR(c2, "\\M-\\C-");
                    }
                    else {
                        WARN_SPACE_CHAR(c2, "\\C-");
                    }
                }
            }
            else if (ISCNTRL(c)) goto eof;
        }
        return c & 0x9f;

      eof:
      case -1:
        yyerror0("Invalid escape character syntax");
        dispatch_scan_event(p, tSTRING_CONTENT);
        return '\0';

      default:
        return c;
    }
}

static void
tokaddmbc(struct parser_params *p, int c, rb_encoding *enc)
{
    int len = rb_enc_codelen(c, enc);
    rb_enc_mbcput(c, tokspace(p, len), enc);
}

static int
tokadd_escape(struct parser_params *p)
{
    int c;
    size_t numlen;

    switch (c = nextc(p)) {
      case '\n':
        return 0;		/* just ignore */

      case '0': case '1': case '2': case '3': /* octal constant */
      case '4': case '5': case '6': case '7':
        {
            ruby_scan_oct(--p->lex.pcur, 3, &numlen);
            if (numlen == 0) goto eof;
            p->lex.pcur += numlen;
            tokcopy(p, (int)numlen + 1);
        }
        return 0;

      case 'x':	/* hex constant */
        {
            tok_hex(p, &numlen);
            if (numlen == 0) return -1;
            tokcopy(p, (int)numlen + 2);
        }
        return 0;

      eof:
      case -1:
        yyerror0("Invalid escape character syntax");
        token_flush(p);
        return -1;

      default:
        tokadd(p, '\\');
        tokadd(p, c);
    }
    return 0;
}

static int
regx_options(struct parser_params *p)
{
    int kcode = 0;
    int kopt = 0;
    int options = 0;
    int c, opt, kc;

    newtok(p);
    while (c = nextc(p), ISALPHA(c)) {
        if (c == 'o') {
            options |= RE_OPTION_ONCE;
        }
        else if (rb_char_to_option_kcode(c, &opt, &kc)) {
            if (kc >= 0) {
                if (kc != rb_ascii8bit_encindex()) kcode = c;
                kopt = opt;
            }
            else {
                options |= opt;
            }
        }
        else {
            tokadd(p, c);
        }
    }
    options |= kopt;
    pushback(p, c);
    if (toklen(p)) {
        YYLTYPE loc = RUBY_INIT_YYLLOC();
        tokfix(p);
        compile_error(p, "unknown regexp option%s - %*s",
                      toklen(p) > 1 ? "s" : "", toklen(p), tok(p));
        parser_show_error_line(p, &loc);
    }
    return options | RE_OPTION_ENCODING(kcode);
}

static int
tokadd_mbchar(struct parser_params *p, int c)
{
    int len = parser_precise_mbclen(p, p->lex.pcur-1);
    if (len < 0) return -1;
    tokadd(p, c);
    p->lex.pcur += --len;
    if (len > 0) tokcopy(p, len);
    return c;
}

static inline int
simple_re_meta(int c)
{
    switch (c) {
      case '$': case '*': case '+': case '.':
      case '?': case '^': case '|':
      case ')': case ']': case '}': case '>':
        return TRUE;
      default:
        return FALSE;
    }
}

static int
parser_update_heredoc_indent(struct parser_params *p, int c)
{
    if (p->heredoc_line_indent == -1) {
        if (c == '\n') p->heredoc_line_indent = 0;
    }
    else {
        if (c == ' ') {
            p->heredoc_line_indent++;
            return TRUE;
        }
        else if (c == '\t') {
            int w = (p->heredoc_line_indent / TAB_WIDTH) + 1;
            p->heredoc_line_indent = w * TAB_WIDTH;
            return TRUE;
        }
        else if (c != '\n') {
            if (p->heredoc_indent > p->heredoc_line_indent) {
                p->heredoc_indent = p->heredoc_line_indent;
            }
            p->heredoc_line_indent = -1;
        }
    }
    return FALSE;
}

static void
parser_mixed_error(struct parser_params *p, rb_encoding *enc1, rb_encoding *enc2)
{
    YYLTYPE loc = RUBY_INIT_YYLLOC();
    const char *n1 = rb_enc_name(enc1), *n2 = rb_enc_name(enc2);
    compile_error(p, "%s mixed within %s source", n1, n2);
    parser_show_error_line(p, &loc);
}

static void
parser_mixed_escape(struct parser_params *p, const char *beg, rb_encoding *enc1, rb_encoding *enc2)
{
    const char *pos = p->lex.pcur;
    p->lex.pcur = beg;
    parser_mixed_error(p, enc1, enc2);
    p->lex.pcur = pos;
}

static inline char
nibble_char_upper(unsigned int c)
{
    c &= 0xf;
    return c + (c < 10 ? '0' : 'A' - 10);
}

static int
tokadd_string(struct parser_params *p,
              int func, int term, int paren, long *nest,
              rb_encoding **encp, rb_encoding **enc)
{
    int c;
    bool erred = false;
#ifdef RIPPER
    const int heredoc_end = (p->heredoc_end ? p->heredoc_end + 1 : 0);
    int top_of_line = FALSE;
#endif

#define mixed_error(enc1, enc2) \
    (void)(erred || (parser_mixed_error(p, enc1, enc2), erred = true))
#define mixed_escape(beg, enc1, enc2) \
    (void)(erred || (parser_mixed_escape(p, beg, enc1, enc2), erred = true))

    while ((c = nextc(p)) != -1) {
        if (p->heredoc_indent > 0) {
            parser_update_heredoc_indent(p, c);
        }
#ifdef RIPPER
        if (top_of_line && heredoc_end == p->ruby_sourceline) {
            pushback(p, c);
            break;
        }
#endif

        if (paren && c == paren) {
            ++*nest;
        }
        else if (c == term) {
            if (!nest || !*nest) {
                pushback(p, c);
                break;
            }
            --*nest;
        }
        else if ((func & STR_FUNC_EXPAND) && c == '#' && !lex_eol_p(p)) {
            unsigned char c2 = *p->lex.pcur;
            if (c2 == '$' || c2 == '@' || c2 == '{') {
                pushback(p, c);
                break;
            }
        }
        else if (c == '\\') {
            c = nextc(p);
            switch (c) {
              case '\n':
                if (func & STR_FUNC_QWORDS) break;
                if (func & STR_FUNC_EXPAND) {
                    if (!(func & STR_FUNC_INDENT) || (p->heredoc_indent < 0))
                        continue;
                    if (c == term) {
                        c = '\\';
                        goto terminate;
                    }
                }
                tokadd(p, '\\');
                break;

              case '\\':
                if (func & STR_FUNC_ESCAPE) tokadd(p, c);
                break;

              case 'u':
                if ((func & STR_FUNC_EXPAND) == 0) {
                    tokadd(p, '\\');
                    break;
                }
                tokadd_utf8(p, enc, term,
                            func & STR_FUNC_SYMBOL,
                            func & STR_FUNC_REGEXP);
                continue;

              default:
                if (c == -1) return -1;
                if (!ISASCII(c)) {
                    if ((func & STR_FUNC_EXPAND) == 0) tokadd(p, '\\');
                    goto non_ascii;
                }
                if (func & STR_FUNC_REGEXP) {
                    switch (c) {
                      case 'c':
                      case 'C':
                      case 'M': {
                        pushback(p, c);
                        c = read_escape(p, 0);

                        char *t = tokspace(p, rb_strlen_lit("\\x00"));
                        *t++ = '\\';
                        *t++ = 'x';
                        *t++ = nibble_char_upper(c >> 4);
                        *t++ = nibble_char_upper(c);
                        continue;
                      }
                    }

                    if (c == term && !simple_re_meta(c)) {
                        tokadd(p, c);
                        continue;
                    }
                    pushback(p, c);
                    if ((c = tokadd_escape(p)) < 0)
                        return -1;
                    if (*enc && *enc != *encp) {
                        mixed_escape(p->lex.ptok+2, *enc, *encp);
                    }
                    continue;
                }
                else if (func & STR_FUNC_EXPAND) {
                    pushback(p, c);
                    if (func & STR_FUNC_ESCAPE) tokadd(p, '\\');
                    c = read_escape(p, 0);
                }
                else if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
                    /* ignore backslashed spaces in %w */
                }
                else if (c != term && !(paren && c == paren)) {
                    tokadd(p, '\\');
                    pushback(p, c);
                    continue;
                }
            }
        }
        else if (!parser_isascii(p)) {
          non_ascii:
            if (!*enc) {
                *enc = *encp;
            }
            else if (*enc != *encp) {
                mixed_error(*enc, *encp);
                continue;
            }
            if (tokadd_mbchar(p, c) == -1) return -1;
            continue;
        }
        else if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
            pushback(p, c);
            break;
        }
        if (c & 0x80) {
            if (!*enc) {
                *enc = *encp;
            }
            else if (*enc != *encp) {
                mixed_error(*enc, *encp);
                continue;
            }
        }
        tokadd(p, c);
#ifdef RIPPER
        top_of_line = (c == '\n');
#endif
    }
  terminate:
    if (*enc) *encp = *enc;
    return c;
}

#define NEW_STRTERM(func, term, paren) new_strterm(p, func, term, paren)

#ifdef RIPPER
static void
flush_string_content(struct parser_params *p, rb_encoding *enc)
{
    VALUE content = yylval.val;
    if (!ripper_is_node_yylval(p, content))
        content = ripper_new_yylval(p, 0, 0, content);
    if (has_delayed_token(p)) {
        ptrdiff_t len = p->lex.pcur - p->lex.ptok;
        if (len > 0) {
            rb_enc_str_buf_cat(p->delayed.token, p->lex.ptok, len, enc);
        }
        dispatch_delayed_token(p, tSTRING_CONTENT);
        p->lex.ptok = p->lex.pcur;
        RNODE_RIPPER(content)->nd_rval = yylval.val;
    }
    dispatch_scan_event(p, tSTRING_CONTENT);
    if (yylval.val != content)
        RNODE_RIPPER(content)->nd_rval = yylval.val;
    yylval.val = content;
}
#else
static void
flush_string_content(struct parser_params *p, rb_encoding *enc)
{
    if (has_delayed_token(p)) {
        ptrdiff_t len = p->lex.pcur - p->lex.ptok;
        if (len > 0) {
            rb_enc_str_buf_cat(p->delayed.token, p->lex.ptok, len, enc);
            p->delayed.end_line = p->ruby_sourceline;
            p->delayed.end_col = rb_long2int(p->lex.pcur - p->lex.pbeg);
        }
        dispatch_delayed_token(p, tSTRING_CONTENT);
        p->lex.ptok = p->lex.pcur;
    }
    dispatch_scan_event(p, tSTRING_CONTENT);
}
#endif

RUBY_FUNC_EXPORTED const uint_least32_t ruby_global_name_punct_bits[(0x7e - 0x20 + 31) / 32];
/* this can be shared with ripper, since it's independent from struct
 * parser_params. */
#ifndef RIPPER
#define BIT(c, idx) (((c) / 32 - 1 == idx) ? (1U << ((c) % 32)) : 0)
#define SPECIAL_PUNCT(idx) ( \
        BIT('~', idx) | BIT('*', idx) | BIT('$', idx) | BIT('?', idx) | \
        BIT('!', idx) | BIT('@', idx) | BIT('/', idx) | BIT('\\', idx) | \
        BIT(';', idx) | BIT(',', idx) | BIT('.', idx) | BIT('=', idx) | \
        BIT(':', idx) | BIT('<', idx) | BIT('>', idx) | BIT('\"', idx) | \
        BIT('&', idx) | BIT('`', idx) | BIT('\'', idx) | BIT('+', idx) | \
        BIT('0', idx))
const uint_least32_t ruby_global_name_punct_bits[] = {
    SPECIAL_PUNCT(0),
    SPECIAL_PUNCT(1),
    SPECIAL_PUNCT(2),
};
#undef BIT
#undef SPECIAL_PUNCT
#endif

static enum yytokentype
parser_peek_variable_name(struct parser_params *p)
{
    int c;
    const char *ptr = p->lex.pcur;

    if (lex_eol_ptr_n_p(p, ptr, 1)) return 0;
    c = *ptr++;
    switch (c) {
      case '$':
        if ((c = *ptr) == '-') {
            if (lex_eol_ptr_p(p, ++ptr)) return 0;
            c = *ptr;
        }
        else if (is_global_name_punct(c) || ISDIGIT(c)) {
            return tSTRING_DVAR;
        }
        break;
      case '@':
        if ((c = *ptr) == '@') {
            if (lex_eol_ptr_p(p, ++ptr)) return 0;
            c = *ptr;
        }
        break;
      case '{':
        p->lex.pcur = ptr;
        p->command_start = TRUE;
        return tSTRING_DBEG;
      default:
        return 0;
    }
    if (!ISASCII(c) || c == '_' || ISALPHA(c))
        return tSTRING_DVAR;
    return 0;
}

#define IS_ARG() IS_lex_state(EXPR_ARG_ANY)
#define IS_END() IS_lex_state(EXPR_END_ANY)
#define IS_BEG() (IS_lex_state(EXPR_BEG_ANY) || IS_lex_state_all(EXPR_ARG|EXPR_LABELED))
#define IS_SPCARG(c) (IS_ARG() && space_seen && !ISSPACE(c))
#define IS_LABEL_POSSIBLE() (\
        (IS_lex_state(EXPR_LABEL|EXPR_ENDFN) && !cmd_state) || \
        IS_ARG())
#define IS_LABEL_SUFFIX(n) (peek_n(p, ':',(n)) && !peek_n(p, ':', (n)+1))
#define IS_AFTER_OPERATOR() IS_lex_state(EXPR_FNAME | EXPR_DOT)

static inline enum yytokentype
parser_string_term(struct parser_params *p, int func)
{
    xfree(p->lex.strterm);
    p->lex.strterm = 0;
    if (func & STR_FUNC_REGEXP) {
        set_yylval_num(regx_options(p));
        dispatch_scan_event(p, tREGEXP_END);
        SET_LEX_STATE(EXPR_END);
        return tREGEXP_END;
    }
    if ((func & STR_FUNC_LABEL) && IS_LABEL_SUFFIX(0)) {
        nextc(p);
        SET_LEX_STATE(EXPR_ARG|EXPR_LABELED);
        return tLABEL_END;
    }
    SET_LEX_STATE(EXPR_END);
    return tSTRING_END;
}

static enum yytokentype
parse_string(struct parser_params *p, rb_strterm_literal_t *quote)
{
    int func = quote->func;
    int term = quote->term;
    int paren = quote->paren;
    int c, space = 0;
    rb_encoding *enc = p->enc;
    rb_encoding *base_enc = 0;
    VALUE lit;

    if (func & STR_FUNC_TERM) {
        if (func & STR_FUNC_QWORDS) nextc(p); /* delayed term */
        SET_LEX_STATE(EXPR_END);
        xfree(p->lex.strterm);
        p->lex.strterm = 0;
        return func & STR_FUNC_REGEXP ? tREGEXP_END : tSTRING_END;
    }
    c = nextc(p);
    if ((func & STR_FUNC_QWORDS) && ISSPACE(c)) {
        while (c != '\n' && ISSPACE(c = nextc(p)));
        space = 1;
    }
    if (func & STR_FUNC_LIST) {
        quote->func &= ~STR_FUNC_LIST;
        space = 1;
    }
    if (c == term && !quote->nest) {
        if (func & STR_FUNC_QWORDS) {
            quote->func |= STR_FUNC_TERM;
            pushback(p, c); /* dispatch the term at tSTRING_END */
            add_delayed_token(p, p->lex.ptok, p->lex.pcur, __LINE__);
            return ' ';
        }
        return parser_string_term(p, func);
    }
    if (space) {
        if (!ISSPACE(c)) pushback(p, c);
        add_delayed_token(p, p->lex.ptok, p->lex.pcur, __LINE__);
        return ' ';
    }
    newtok(p);
    if ((func & STR_FUNC_EXPAND) && c == '#') {
        enum yytokentype t = parser_peek_variable_name(p);
        if (t) return t;
        tokadd(p, '#');
        c = nextc(p);
    }
    pushback(p, c);
    if (tokadd_string(p, func, term, paren, &quote->nest,
                      &enc, &base_enc) == -1) {
        if (p->eofp) {
#ifndef RIPPER
# define unterminated_literal(mesg) yyerror0(mesg)
#else
# define unterminated_literal(mesg) compile_error(p,  mesg)
#endif
            literal_flush(p, p->lex.pcur);
            if (func & STR_FUNC_QWORDS) {
                /* no content to add, bailing out here */
                unterminated_literal("unterminated list meets end of file");
                xfree(p->lex.strterm);
                p->lex.strterm = 0;
                return tSTRING_END;
            }
            if (func & STR_FUNC_REGEXP) {
                unterminated_literal("unterminated regexp meets end of file");
            }
            else {
                unterminated_literal("unterminated string meets end of file");
            }
            quote->func |= STR_FUNC_TERM;
        }
    }

    tokfix(p);
    lit = STR_NEW3(tok(p), toklen(p), enc, func);
    set_yylval_str(lit);
    flush_string_content(p, enc);

    return tSTRING_CONTENT;
}

static enum yytokentype
heredoc_identifier(struct parser_params *p)
{
    /*
     * term_len is length of `<<"END"` except `END`,
     * in this case term_len is 4 (<, <, " and ").
     */
    long len, offset = p->lex.pcur - p->lex.pbeg;
    int c = nextc(p), term, func = 0, quote = 0;
    enum yytokentype token = tSTRING_BEG;
    int indent = 0;

    if (c == '-') {
        c = nextc(p);
        func = STR_FUNC_INDENT;
        offset++;
    }
    else if (c == '~') {
        c = nextc(p);
        func = STR_FUNC_INDENT;
        offset++;
        indent = INT_MAX;
    }
    switch (c) {
      case '\'':
        func |= str_squote; goto quoted;
      case '"':
        func |= str_dquote; goto quoted;
      case '`':
        token = tXSTRING_BEG;
        func |= str_xquote; goto quoted;

      quoted:
        quote++;
        offset++;
        term = c;
        len = 0;
        while ((c = nextc(p)) != term) {
            if (c == -1 || c == '\r' || c == '\n') {
                yyerror0("unterminated here document identifier");
                return -1;
            }
        }
        break;

      default:
        if (!parser_is_identchar(p)) {
            pushback(p, c);
            if (func & STR_FUNC_INDENT) {
                pushback(p, indent > 0 ? '~' : '-');
            }
            return 0;
        }
        func |= str_dquote;
        do {
            int n = parser_precise_mbclen(p, p->lex.pcur-1);
            if (n < 0) return 0;
            p->lex.pcur += --n;
        } while ((c = nextc(p)) != -1 && parser_is_identchar(p));
        pushback(p, c);
        break;
    }

    len = p->lex.pcur - (p->lex.pbeg + offset) - quote;
    if ((unsigned long)len >= HERETERM_LENGTH_MAX)
        yyerror0("too long here document identifier");
    dispatch_scan_event(p, tHEREDOC_BEG);
    lex_goto_eol(p);

    p->lex.strterm = new_heredoc(p);
    rb_strterm_heredoc_t *here = &p->lex.strterm->u.heredoc;
    here->offset = offset;
    here->sourceline = p->ruby_sourceline;
    here->length = (unsigned)len;
    here->quote = quote;
    here->func = func;
    here->lastline = p->lex.lastline;
    rb_ast_add_mark_object(p->ast, p->lex.lastline);

    token_flush(p);
    p->heredoc_indent = indent;
    p->heredoc_line_indent = 0;
    return token;
}

static void
heredoc_restore(struct parser_params *p, rb_strterm_heredoc_t *here)
{
    VALUE line;
    rb_strterm_t *term = p->lex.strterm;

    p->lex.strterm = 0;
    line = here->lastline;
    p->lex.lastline = line;
    p->lex.pbeg = RSTRING_PTR(line);
    p->lex.pend = p->lex.pbeg + RSTRING_LEN(line);
    p->lex.pcur = p->lex.pbeg + here->offset + here->length + here->quote;
    p->lex.ptok = p->lex.pbeg + here->offset - here->quote;
    p->heredoc_end = p->ruby_sourceline;
    p->ruby_sourceline = (int)here->sourceline;
    if (p->eofp) p->lex.nextline = Qnil;
    p->eofp = 0;
    xfree(term);
    rb_ast_delete_mark_object(p->ast, line);
}

static int
dedent_string(struct parser_params *p, VALUE string, int width)
{
    char *str;
    long len;
    int i, col = 0;

    RSTRING_GETMEM(string, str, len);
    for (i = 0; i < len && col < width; i++) {
        if (str[i] == ' ') {
            col++;
        }
        else if (str[i] == '\t') {
            int n = TAB_WIDTH * (col / TAB_WIDTH + 1);
            if (n > width) break;
            col = n;
        }
        else {
            break;
        }
    }
    if (!i) return 0;
    rb_str_modify(string);
    str = RSTRING_PTR(string);
    if (RSTRING_LEN(string) != len)
        rb_fatal("literal string changed: %+"PRIsVALUE, string);
    MEMMOVE(str, str + i, char, len - i);
    rb_str_set_len(string, len - i);
    return i;
}

#ifndef RIPPER
static NODE *
heredoc_dedent(struct parser_params *p, NODE *root)
{
    NODE *node, *str_node, *prev_node;
    int indent = p->heredoc_indent;
    VALUE prev_lit = 0;

    if (indent <= 0) return root;
    p->heredoc_indent = 0;
    if (!root) return root;

    prev_node = node = str_node = root;
    if (nd_type_p(root, NODE_LIST)) str_node = RNODE_LIST(root)->nd_head;

    while (str_node) {
        VALUE lit = RNODE_LIT(str_node)->nd_lit;
        if (nd_fl_newline(str_node)) {
            dedent_string(p, lit, indent);
        }
        if (!prev_lit) {
            prev_lit = lit;
        }
        else if (!literal_concat0(p, prev_lit, lit)) {
            return 0;
        }
        else {
            NODE *end = RNODE_LIST(node)->as.nd_end;
            node = RNODE_LIST(prev_node)->nd_next = RNODE_LIST(node)->nd_next;
            if (!node) {
                if (nd_type_p(prev_node, NODE_DSTR))
                    nd_set_type(prev_node, NODE_STR);
                break;
            }
            RNODE_LIST(node)->as.nd_end = end;
            goto next_str;
        }

        str_node = 0;
        while ((nd_type_p(node, NODE_LIST) || nd_type_p(node, NODE_DSTR)) && (node = RNODE_LIST(prev_node = node)->nd_next) != 0) {
          next_str:
            if (!nd_type_p(node, NODE_LIST)) break;
            if ((str_node = RNODE_LIST(node)->nd_head) != 0) {
                enum node_type type = nd_type(str_node);
                if (type == NODE_STR || type == NODE_DSTR) break;
                prev_lit = 0;
                str_node = 0;
            }
        }
    }
    return root;
}
#else /* RIPPER */
static VALUE
heredoc_dedent(struct parser_params *p, VALUE array)
{
    int indent = p->heredoc_indent;

    if (indent <= 0) return array;
    p->heredoc_indent = 0;
    dispatch2(heredoc_dedent, array, INT2NUM(indent));
    return array;
}
#endif

static int
whole_match_p(struct parser_params *p, const char *eos, long len, int indent)
{
    const char *beg = p->lex.pbeg;
    const char *ptr = p->lex.pend;

    if (ptr - beg < len) return FALSE;
    if (ptr > beg && ptr[-1] == '\n') {
        if (--ptr > beg && ptr[-1] == '\r') --ptr;
        if (ptr - beg < len) return FALSE;
    }
    if (strncmp(eos, ptr -= len, len)) return FALSE;
    if (indent) {
        while (beg < ptr && ISSPACE(*beg)) beg++;
    }
    return beg == ptr;
}

static int
word_match_p(struct parser_params *p, const char *word, long len)
{
    if (strncmp(p->lex.pcur, word, len)) return 0;
    if (lex_eol_n_p(p, len)) return 1;
    int c = (unsigned char)p->lex.pcur[len];
    if (ISSPACE(c)) return 1;
    switch (c) {
      case '\0': case '\004': case '\032': return 1;
    }
    return 0;
}

#define NUM_SUFFIX_R   (1<<0)
#define NUM_SUFFIX_I   (1<<1)
#define NUM_SUFFIX_ALL 3

static int
number_literal_suffix(struct parser_params *p, int mask)
{
    int c, result = 0;
    const char *lastp = p->lex.pcur;

    while ((c = nextc(p)) != -1) {
        if ((mask & NUM_SUFFIX_I) && c == 'i') {
            result |= (mask & NUM_SUFFIX_I);
            mask &= ~NUM_SUFFIX_I;
            /* r after i, rational of complex is disallowed */
            mask &= ~NUM_SUFFIX_R;
            continue;
        }
        if ((mask & NUM_SUFFIX_R) && c == 'r') {
            result |= (mask & NUM_SUFFIX_R);
            mask &= ~NUM_SUFFIX_R;
            continue;
        }
        if (!ISASCII(c) || ISALPHA(c) || c == '_') {
            p->lex.pcur = lastp;
            literal_flush(p, p->lex.pcur);
            return 0;
        }
        pushback(p, c);
        break;
    }
    return result;
}

static enum yytokentype
set_number_literal(struct parser_params *p, VALUE v,
                   enum yytokentype type, int suffix)
{
    if (suffix & NUM_SUFFIX_I) {
        v = rb_complex_raw(INT2FIX(0), v);
        type = tIMAGINARY;
    }
    set_yylval_literal(v);
    SET_LEX_STATE(EXPR_END);
    return type;
}

static enum yytokentype
set_integer_literal(struct parser_params *p, VALUE v, int suffix)
{
    enum yytokentype type = tINTEGER;
    if (suffix & NUM_SUFFIX_R) {
        v = rb_rational_raw1(v);
        type = tRATIONAL;
    }
    return set_number_literal(p, v, type, suffix);
}

#ifdef RIPPER
static void
dispatch_heredoc_end(struct parser_params *p)
{
    VALUE str;
    if (has_delayed_token(p))
        dispatch_delayed_token(p, tSTRING_CONTENT);
    str = STR_NEW(p->lex.ptok, p->lex.pend - p->lex.ptok);
    ripper_dispatch1(p, ripper_token2eventid(tHEREDOC_END), str);
    RUBY_SET_YYLLOC_FROM_STRTERM_HEREDOC(*p->yylloc);
    lex_goto_eol(p);
    token_flush(p);
}

#else
#define dispatch_heredoc_end(p) parser_dispatch_heredoc_end(p, __LINE__)
static void
parser_dispatch_heredoc_end(struct parser_params *p, int line)
{
    if (has_delayed_token(p))
        dispatch_delayed_token(p, tSTRING_CONTENT);

    if (p->keep_tokens) {
        VALUE str = STR_NEW(p->lex.ptok, p->lex.pend - p->lex.ptok);
        RUBY_SET_YYLLOC_OF_HEREDOC_END(*p->yylloc);
        parser_append_tokens(p, str, tHEREDOC_END, line);
    }

    RUBY_SET_YYLLOC_FROM_STRTERM_HEREDOC(*p->yylloc);
    lex_goto_eol(p);
    token_flush(p);
}
#endif

static enum yytokentype
here_document(struct parser_params *p, rb_strterm_heredoc_t *here)
{
    int c, func, indent = 0;
    const char *eos, *ptr, *ptr_end;
    long len;
    VALUE str = 0;
    rb_encoding *enc = p->enc;
    rb_encoding *base_enc = 0;
    int bol;

    eos = RSTRING_PTR(here->lastline) + here->offset;
    len = here->length;
    indent = (func = here->func) & STR_FUNC_INDENT;

    if ((c = nextc(p)) == -1) {
      error:
#ifdef RIPPER
        if (!has_delayed_token(p)) {
            dispatch_scan_event(p, tSTRING_CONTENT);
        }
        else {
            if ((len = p->lex.pcur - p->lex.ptok) > 0) {
                if (!(func & STR_FUNC_REGEXP) && rb_enc_asciicompat(enc)) {
                    int cr = ENC_CODERANGE_UNKNOWN;
                    rb_str_coderange_scan_restartable(p->lex.ptok, p->lex.pcur, enc, &cr);
                    if (cr != ENC_CODERANGE_7BIT &&
                        rb_is_usascii_enc(p->enc) &&
                        enc != rb_utf8_encoding()) {
                        enc = rb_ascii8bit_encoding();
                    }
                }
                rb_enc_str_buf_cat(p->delayed.token, p->lex.ptok, len, enc);
            }
            dispatch_delayed_token(p, tSTRING_CONTENT);
        }
        lex_goto_eol(p);
#endif
        heredoc_restore(p, &p->lex.strterm->u.heredoc);
        compile_error(p, "can't find string \"%.*s\" anywhere before EOF",
                      (int)len, eos);
        token_flush(p);
        SET_LEX_STATE(EXPR_END);
        return tSTRING_END;
    }
    bol = was_bol(p);
    if (!bol) {
        /* not beginning of line, cannot be the terminator */
    }
    else if (p->heredoc_line_indent == -1) {
        /* `heredoc_line_indent == -1` means
         * - "after an interpolation in the same line", or
         * - "in a continuing line"
         */
        p->heredoc_line_indent = 0;
    }
    else if (whole_match_p(p, eos, len, indent)) {
        dispatch_heredoc_end(p);
      restore:
        heredoc_restore(p, &p->lex.strterm->u.heredoc);
        token_flush(p);
        SET_LEX_STATE(EXPR_END);
        return tSTRING_END;
    }

    if (!(func & STR_FUNC_EXPAND)) {
        do {
            ptr = RSTRING_PTR(p->lex.lastline);
            ptr_end = p->lex.pend;
            if (ptr_end > ptr) {
                switch (ptr_end[-1]) {
                  case '\n':
                    if (--ptr_end == ptr || ptr_end[-1] != '\r') {
                        ptr_end++;
                        break;
                    }
                  case '\r':
                    --ptr_end;
                }
            }

            if (p->heredoc_indent > 0) {
                long i = 0;
                while (ptr + i < ptr_end && parser_update_heredoc_indent(p, ptr[i]))
                    i++;
                p->heredoc_line_indent = 0;
            }

            if (str)
                rb_str_cat(str, ptr, ptr_end - ptr);
            else
                str = STR_NEW(ptr, ptr_end - ptr);
            if (!lex_eol_ptr_p(p, ptr_end)) rb_str_cat(str, "\n", 1);
            lex_goto_eol(p);
            if (p->heredoc_indent > 0) {
                goto flush_str;
            }
            if (nextc(p) == -1) {
                if (str) {
                    str = 0;
                }
                goto error;
            }
        } while (!whole_match_p(p, eos, len, indent));
    }
    else {
        /*	int mb = ENC_CODERANGE_7BIT, *mbp = &mb;*/
        newtok(p);
        if (c == '#') {
            enum yytokentype t = parser_peek_variable_name(p);
            if (p->heredoc_line_indent != -1) {
                if (p->heredoc_indent > p->heredoc_line_indent) {
                    p->heredoc_indent = p->heredoc_line_indent;
                }
                p->heredoc_line_indent = -1;
            }
            if (t) return t;
            tokadd(p, '#');
            c = nextc(p);
        }
        do {
            pushback(p, c);
            enc = p->enc;
            if ((c = tokadd_string(p, func, '\n', 0, NULL, &enc, &base_enc)) == -1) {
                if (p->eofp) goto error;
                goto restore;
            }
            if (c != '\n') {
                if (c == '\\') p->heredoc_line_indent = -1;
              flush:
                str = STR_NEW3(tok(p), toklen(p), enc, func);
              flush_str:
                set_yylval_str(str);
#ifndef RIPPER
                if (bol) nd_set_fl_newline(yylval.node);
#endif
                flush_string_content(p, enc);
                return tSTRING_CONTENT;
            }
            tokadd(p, nextc(p));
            if (p->heredoc_indent > 0) {
                lex_goto_eol(p);
                goto flush;
            }
            /*	    if (mbp && mb == ENC_CODERANGE_UNKNOWN) mbp = 0;*/
            if ((c = nextc(p)) == -1) goto error;
        } while (!whole_match_p(p, eos, len, indent));
        str = STR_NEW3(tok(p), toklen(p), enc, func);
    }
    dispatch_heredoc_end(p);
#ifdef RIPPER
    str = ripper_new_yylval(p, ripper_token2eventid(tSTRING_CONTENT),
                            yylval.val, str);
#endif
    heredoc_restore(p, &p->lex.strterm->u.heredoc);
    token_flush(p);
    p->lex.strterm = NEW_STRTERM(func | STR_FUNC_TERM, 0, 0);
    set_yylval_str(str);
#ifndef RIPPER
    if (bol) nd_set_fl_newline(yylval.node);
#endif
    return tSTRING_CONTENT;
}

#include "lex.c"

static int
arg_ambiguous(struct parser_params *p, char c)
{
#ifndef RIPPER
    if (c == '/') {
        rb_warning1("ambiguity between regexp and two divisions: wrap regexp in parentheses or add a space after `%c' operator", WARN_I(c));
    }
    else {
        rb_warning1("ambiguous first argument; put parentheses or a space even after `%c' operator", WARN_I(c));
    }
#else
    dispatch1(arg_ambiguous, rb_usascii_str_new(&c, 1));
#endif
    return TRUE;
}

static ID
#ifndef RIPPER
formal_argument(struct parser_params *p, ID lhs)
#else
formal_argument(struct parser_params *p, VALUE lhs)
#endif
{
    ID id = get_id(lhs);

    switch (id_type(id)) {
      case ID_LOCAL:
        break;
#ifndef RIPPER
# define ERR(mesg) yyerror0(mesg)
#else
# define ERR(mesg) (dispatch2(param_error, WARN_S(mesg), lhs), ripper_error(p))
#endif
      case ID_CONST:
        ERR("formal argument cannot be a constant");
        return 0;
      case ID_INSTANCE:
        ERR("formal argument cannot be an instance variable");
        return 0;
      case ID_GLOBAL:
        ERR("formal argument cannot be a global variable");
        return 0;
      case ID_CLASS:
        ERR("formal argument cannot be a class variable");
        return 0;
      default:
        ERR("formal argument must be local variable");
        return 0;
#undef ERR
    }
    shadowing_lvar(p, id);
    return lhs;
}

static int
lvar_defined(struct parser_params *p, ID id)
{
    return (dyna_in_block(p) && dvar_defined(p, id)) || local_id(p, id);
}

/* emacsen -*- hack */
static long
parser_encode_length(struct parser_params *p, const char *name, long len)
{
    long nlen;

    if (len > 5 && name[nlen = len - 5] == '-') {
        if (rb_memcicmp(name + nlen + 1, "unix", 4) == 0)
            return nlen;
    }
    if (len > 4 && name[nlen = len - 4] == '-') {
        if (rb_memcicmp(name + nlen + 1, "dos", 3) == 0)
            return nlen;
        if (rb_memcicmp(name + nlen + 1, "mac", 3) == 0 &&
            !(len == 8 && rb_memcicmp(name, "utf8-mac", len) == 0))
            /* exclude UTF8-MAC because the encoding named "UTF8" doesn't exist in Ruby */
            return nlen;
    }
    return len;
}

static void
parser_set_encode(struct parser_params *p, const char *name)
{
    int idx = rb_enc_find_index(name);
    rb_encoding *enc;
    VALUE excargs[3];

    if (idx < 0) {
        excargs[1] = rb_sprintf("unknown encoding name: %s", name);
      error:
        excargs[0] = rb_eArgError;
        excargs[2] = rb_make_backtrace();
        rb_ary_unshift(excargs[2], rb_sprintf("%"PRIsVALUE":%d", p->ruby_sourcefile_string, p->ruby_sourceline));
        rb_exc_raise(rb_make_exception(3, excargs));
    }
    enc = rb_enc_from_index(idx);
    if (!rb_enc_asciicompat(enc)) {
        excargs[1] = rb_sprintf("%s is not ASCII compatible", rb_enc_name(enc));
        goto error;
    }
    p->enc = enc;
#ifndef RIPPER
    if (p->debug_lines) {
        VALUE lines = p->debug_lines;
        long i, n = RARRAY_LEN(lines);
        for (i = 0; i < n; ++i) {
            rb_enc_associate_index(RARRAY_AREF(lines, i), idx);
        }
    }
#endif
}

static int
comment_at_top(struct parser_params *p)
{
    const char *ptr = p->lex.pbeg, *ptr_end = p->lex.pcur - 1;
    if (p->line_count != (p->has_shebang ? 2 : 1)) return 0;
    while (ptr < ptr_end) {
        if (!ISSPACE(*ptr)) return 0;
        ptr++;
    }
    return 1;
}

typedef long (*rb_magic_comment_length_t)(struct parser_params *p, const char *name, long len);
typedef void (*rb_magic_comment_setter_t)(struct parser_params *p, const char *name, const char *val);

static int parser_invalid_pragma_value(struct parser_params *p, const char *name, const char *val);

static void
magic_comment_encoding(struct parser_params *p, const char *name, const char *val)
{
    if (!comment_at_top(p)) {
        return;
    }
    parser_set_encode(p, val);
}

static int
parser_get_bool(struct parser_params *p, const char *name, const char *val)
{
    switch (*val) {
      case 't': case 'T':
        if (STRCASECMP(val, "true") == 0) {
            return TRUE;
        }
        break;
      case 'f': case 'F':
        if (STRCASECMP(val, "false") == 0) {
            return FALSE;
        }
        break;
    }
    return parser_invalid_pragma_value(p, name, val);
}

static int
parser_invalid_pragma_value(struct parser_params *p, const char *name, const char *val)
{
    rb_warning2("invalid value for %s: %s", WARN_S(name), WARN_S(val));
    return -1;
}

static void
parser_set_token_info(struct parser_params *p, const char *name, const char *val)
{
    int b = parser_get_bool(p, name, val);
    if (b >= 0) p->token_info_enabled = b;
}

static void
parser_set_frozen_string_literal(struct parser_params *p, const char *name, const char *val)
{
    int b;

    if (p->token_seen) {
        rb_warning1("`%s' is ignored after any tokens", WARN_S(name));
        return;
    }

    b = parser_get_bool(p, name, val);
    if (b < 0) return;

    p->frozen_string_literal = b;
}

static void
parser_set_shareable_constant_value(struct parser_params *p, const char *name, const char *val)
{
    for (const char *s = p->lex.pbeg, *e = p->lex.pcur; s < e; ++s) {
        if (*s == ' ' || *s == '\t') continue;
        if (*s == '#') break;
        rb_warning1("`%s' is ignored unless in comment-only line", WARN_S(name));
        return;
    }

    switch (*val) {
      case 'n': case 'N':
        if (STRCASECMP(val, "none") == 0) {
            p->ctxt.shareable_constant_value = shareable_none;
            return;
        }
        break;
      case 'l': case 'L':
        if (STRCASECMP(val, "literal") == 0) {
            p->ctxt.shareable_constant_value = shareable_literal;
            return;
        }
        break;
      case 'e': case 'E':
        if (STRCASECMP(val, "experimental_copy") == 0) {
            p->ctxt.shareable_constant_value = shareable_copy;
            return;
        }
        if (STRCASECMP(val, "experimental_everything") == 0) {
            p->ctxt.shareable_constant_value = shareable_everything;
            return;
        }
        break;
    }
    parser_invalid_pragma_value(p, name, val);
}

# if WARN_PAST_SCOPE
static void
parser_set_past_scope(struct parser_params *p, const char *name, const char *val)
{
    int b = parser_get_bool(p, name, val);
    if (b >= 0) p->past_scope_enabled = b;
}
# endif

struct magic_comment {
    const char *name;
    rb_magic_comment_setter_t func;
    rb_magic_comment_length_t length;
};

static const struct magic_comment magic_comments[] = {
    {"coding", magic_comment_encoding, parser_encode_length},
    {"encoding", magic_comment_encoding, parser_encode_length},
    {"frozen_string_literal", parser_set_frozen_string_literal},
    {"shareable_constant_value", parser_set_shareable_constant_value},
    {"warn_indent", parser_set_token_info},
# if WARN_PAST_SCOPE
    {"warn_past_scope", parser_set_past_scope},
# endif
};

static const char *
magic_comment_marker(const char *str, long len)
{
    long i = 2;

    while (i < len) {
        switch (str[i]) {
          case '-':
            if (str[i-1] == '*' && str[i-2] == '-') {
                return str + i + 1;
            }
            i += 2;
            break;
          case '*':
            if (i + 1 >= len) return 0;
            if (str[i+1] != '-') {
                i += 4;
            }
            else if (str[i-1] != '-') {
                i += 2;
            }
            else {
                return str + i + 2;
            }
            break;
          default:
            i += 3;
            break;
        }
    }
    return 0;
}

static int
parser_magic_comment(struct parser_params *p, const char *str, long len)
{
    int indicator = 0;
    VALUE name = 0, val = 0;
    const char *beg, *end, *vbeg, *vend;
#define str_copy(_s, _p, _n) ((_s) \
        ? (void)(rb_str_resize((_s), (_n)), \
           MEMCPY(RSTRING_PTR(_s), (_p), char, (_n)), (_s)) \
        : (void)((_s) = STR_NEW((_p), (_n))))

    if (len <= 7) return FALSE;
    if (!!(beg = magic_comment_marker(str, len))) {
        if (!(end = magic_comment_marker(beg, str + len - beg)))
            return FALSE;
        indicator = TRUE;
        str = beg;
        len = end - beg - 3;
    }

    /* %r"([^\\s\'\":;]+)\\s*:\\s*(\"(?:\\\\.|[^\"])*\"|[^\"\\s;]+)[\\s;]*" */
    while (len > 0) {
        const struct magic_comment *mc = magic_comments;
        char *s;
        int i;
        long n = 0;

        for (; len > 0 && *str; str++, --len) {
            switch (*str) {
              case '\'': case '"': case ':': case ';':
                continue;
            }
            if (!ISSPACE(*str)) break;
        }
        for (beg = str; len > 0; str++, --len) {
            switch (*str) {
              case '\'': case '"': case ':': case ';':
                break;
              default:
                if (ISSPACE(*str)) break;
                continue;
            }
            break;
        }
        for (end = str; len > 0 && ISSPACE(*str); str++, --len);
        if (!len) break;
        if (*str != ':') {
            if (!indicator) return FALSE;
            continue;
        }

        do str++; while (--len > 0 && ISSPACE(*str));
        if (!len) break;
        if (*str == '"') {
            for (vbeg = ++str; --len > 0 && *str != '"'; str++) {
                if (*str == '\\') {
                    --len;
                    ++str;
                }
            }
            vend = str;
            if (len) {
                --len;
                ++str;
            }
        }
        else {
            for (vbeg = str; len > 0 && *str != '"' && *str != ';' && !ISSPACE(*str); --len, str++);
            vend = str;
        }
        if (indicator) {
            while (len > 0 && (*str == ';' || ISSPACE(*str))) --len, str++;
        }
        else {
            while (len > 0 && (ISSPACE(*str))) --len, str++;
            if (len) return FALSE;
        }

        n = end - beg;
        str_copy(name, beg, n);
        s = RSTRING_PTR(name);
        for (i = 0; i < n; ++i) {
            if (s[i] == '-') s[i] = '_';
        }
        do {
            if (STRNCASECMP(mc->name, s, n) == 0 && !mc->name[n]) {
                n = vend - vbeg;
                if (mc->length) {
                    n = (*mc->length)(p, vbeg, n);
                }
                str_copy(val, vbeg, n);
                (*mc->func)(p, mc->name, RSTRING_PTR(val));
                break;
            }
        } while (++mc < magic_comments + numberof(magic_comments));
#ifdef RIPPER
        str_copy(val, vbeg, vend - vbeg);
        dispatch2(magic_comment, name, val);
#endif
    }

    return TRUE;
}

static void
set_file_encoding(struct parser_params *p, const char *str, const char *send)
{
    int sep = 0;
    const char *beg = str;
    VALUE s;

    for (;;) {
        if (send - str <= 6) return;
        switch (str[6]) {
          case 'C': case 'c': str += 6; continue;
          case 'O': case 'o': str += 5; continue;
          case 'D': case 'd': str += 4; continue;
          case 'I': case 'i': str += 3; continue;
          case 'N': case 'n': str += 2; continue;
          case 'G': case 'g': str += 1; continue;
          case '=': case ':':
            sep = 1;
            str += 6;
            break;
          default:
            str += 6;
            if (ISSPACE(*str)) break;
            continue;
        }
        if (STRNCASECMP(str-6, "coding", 6) == 0) break;
        sep = 0;
    }
    for (;;) {
        do {
            if (++str >= send) return;
        } while (ISSPACE(*str));
        if (sep) break;
        if (*str != '=' && *str != ':') return;
        sep = 1;
        str++;
    }
    beg = str;
    while ((*str == '-' || *str == '_' || ISALNUM(*str)) && ++str < send);
    s = rb_str_new(beg, parser_encode_length(p, beg, str - beg));
    parser_set_encode(p, RSTRING_PTR(s));
    rb_str_resize(s, 0);
}

static void
parser_prepare(struct parser_params *p)
{
    int c = nextc0(p, FALSE);
    p->token_info_enabled = !compile_for_eval && RTEST(ruby_verbose);
    switch (c) {
      case '#':
        if (peek(p, '!')) p->has_shebang = 1;
        break;
      case 0xef:		/* UTF-8 BOM marker */
        if (!lex_eol_n_p(p, 2) &&
            (unsigned char)p->lex.pcur[0] == 0xbb &&
            (unsigned char)p->lex.pcur[1] == 0xbf) {
            p->enc = rb_utf8_encoding();
            p->lex.pcur += 2;
#ifndef RIPPER
            if (p->debug_lines) {
                rb_enc_associate(p->lex.lastline, p->enc);
            }
#endif
            p->lex.pbeg = p->lex.pcur;
            token_flush(p);
            return;
        }
        break;
      case EOF:
        return;
    }
    pushback(p, c);
    p->enc = rb_enc_get(p->lex.lastline);
}

#ifndef RIPPER
#define ambiguous_operator(tok, op, syn) ( \
    rb_warning0("`"op"' after local variable or literal is interpreted as binary operator"), \
    rb_warning0("even though it seems like "syn""))
#else
#define ambiguous_operator(tok, op, syn) \
    dispatch2(operator_ambiguous, TOKEN2VAL(tok), rb_str_new_cstr(syn))
#endif
#define warn_balanced(tok, op, syn) ((void) \
    (!IS_lex_state_for(last_state, EXPR_CLASS|EXPR_DOT|EXPR_FNAME|EXPR_ENDFN) && \
     space_seen && !ISSPACE(c) && \
     (ambiguous_operator(tok, op, syn), 0)), \
     (enum yytokentype)(tok))

static VALUE
parse_rational(struct parser_params *p, char *str, int len, int seen_point)
{
    VALUE v;
    char *point = &str[seen_point];
    size_t fraclen = len-seen_point-1;
    memmove(point, point+1, fraclen+1);
    v = rb_cstr_to_inum(str, 10, FALSE);
    return rb_rational_new(v, rb_int_positive_pow(10, fraclen));
}

static enum yytokentype
no_digits(struct parser_params *p)
{
    yyerror0("numeric literal without digits");
    if (peek(p, '_')) nextc(p);
    /* dummy 0, for tUMINUS_NUM at numeric */
    return set_integer_literal(p, INT2FIX(0), 0);
}

static enum yytokentype
parse_numeric(struct parser_params *p, int c)
{
    int is_float, seen_point, seen_e, nondigit;
    int suffix;

    is_float = seen_point = seen_e = nondigit = 0;
    SET_LEX_STATE(EXPR_END);
    newtok(p);
    if (c == '-' || c == '+') {
        tokadd(p, c);
        c = nextc(p);
    }
    if (c == '0') {
        int start = toklen(p);
        c = nextc(p);
        if (c == 'x' || c == 'X') {
            /* hexadecimal */
            c = nextc(p);
            if (c != -1 && ISXDIGIT(c)) {
                do {
                    if (c == '_') {
                        if (nondigit) break;
                        nondigit = c;
                        continue;
                    }
                    if (!ISXDIGIT(c)) break;
                    nondigit = 0;
                    tokadd(p, c);
                } while ((c = nextc(p)) != -1);
            }
            pushback(p, c);
            tokfix(p);
            if (toklen(p) == start) {
                return no_digits(p);
            }
            else if (nondigit) goto trailing_uc;
            suffix = number_literal_suffix(p, NUM_SUFFIX_ALL);
            return set_integer_literal(p, rb_cstr_to_inum(tok(p), 16, FALSE), suffix);
        }
        if (c == 'b' || c == 'B') {
            /* binary */
            c = nextc(p);
            if (c == '0' || c == '1') {
                do {
                    if (c == '_') {
                        if (nondigit) break;
                        nondigit = c;
                        continue;
                    }
                    if (c != '0' && c != '1') break;
                    nondigit = 0;
                    tokadd(p, c);
                } while ((c = nextc(p)) != -1);
            }
            pushback(p, c);
            tokfix(p);
            if (toklen(p) == start) {
                return no_digits(p);
            }
            else if (nondigit) goto trailing_uc;
            suffix = number_literal_suffix(p, NUM_SUFFIX_ALL);
            return set_integer_literal(p, rb_cstr_to_inum(tok(p), 2, FALSE), suffix);
        }
        if (c == 'd' || c == 'D') {
            /* decimal */
            c = nextc(p);
            if (c != -1 && ISDIGIT(c)) {
                do {
                    if (c == '_') {
                        if (nondigit) break;
                        nondigit = c;
                        continue;
                    }
                    if (!ISDIGIT(c)) break;
                    nondigit = 0;
                    tokadd(p, c);
                } while ((c = nextc(p)) != -1);
            }
            pushback(p, c);
            tokfix(p);
            if (toklen(p) == start) {
                return no_digits(p);
            }
            else if (nondigit) goto trailing_uc;
            suffix = number_literal_suffix(p, NUM_SUFFIX_ALL);
            return set_integer_literal(p, rb_cstr_to_inum(tok(p), 10, FALSE), suffix);
        }
        if (c == '_') {
            /* 0_0 */
            goto octal_number;
        }
        if (c == 'o' || c == 'O') {
            /* prefixed octal */
            c = nextc(p);
            if (c == -1 || c == '_' || !ISDIGIT(c)) {
                return no_digits(p);
            }
        }
        if (c >= '0' && c <= '7') {
            /* octal */
          octal_number:
            do {
                if (c == '_') {
                    if (nondigit) break;
                    nondigit = c;
                    continue;
                }
                if (c < '0' || c > '9') break;
                if (c > '7') goto invalid_octal;
                nondigit = 0;
                tokadd(p, c);
            } while ((c = nextc(p)) != -1);
            if (toklen(p) > start) {
                pushback(p, c);
                tokfix(p);
                if (nondigit) goto trailing_uc;
                suffix = number_literal_suffix(p, NUM_SUFFIX_ALL);
                return set_integer_literal(p, rb_cstr_to_inum(tok(p), 8, FALSE), suffix);
            }
            if (nondigit) {
                pushback(p, c);
                goto trailing_uc;
            }
        }
        if (c > '7' && c <= '9') {
          invalid_octal:
            yyerror0("Invalid octal digit");
        }
        else if (c == '.' || c == 'e' || c == 'E') {
            tokadd(p, '0');
        }
        else {
            pushback(p, c);
            suffix = number_literal_suffix(p, NUM_SUFFIX_ALL);
            return set_integer_literal(p, INT2FIX(0), suffix);
        }
    }

    for (;;) {
        switch (c) {
          case '0': case '1': case '2': case '3': case '4':
          case '5': case '6': case '7': case '8': case '9':
            nondigit = 0;
            tokadd(p, c);
            break;

          case '.':
            if (nondigit) goto trailing_uc;
            if (seen_point || seen_e) {
                goto decode_num;
            }
            else {
                int c0 = nextc(p);
                if (c0 == -1 || !ISDIGIT(c0)) {
                    pushback(p, c0);
                    goto decode_num;
                }
                c = c0;
            }
            seen_point = toklen(p);
            tokadd(p, '.');
            tokadd(p, c);
            is_float++;
            nondigit = 0;
            break;

          case 'e':
          case 'E':
            if (nondigit) {
                pushback(p, c);
                c = nondigit;
                goto decode_num;
            }
            if (seen_e) {
                goto decode_num;
            }
            nondigit = c;
            c = nextc(p);
            if (c != '-' && c != '+' && !ISDIGIT(c)) {
                pushback(p, c);
                c = nondigit;
                nondigit = 0;
                goto decode_num;
            }
            tokadd(p, nondigit);
            seen_e++;
            is_float++;
            tokadd(p, c);
            nondigit = (c == '-' || c == '+') ? c : 0;
            break;

          case '_':	/* `_' in number just ignored */
            if (nondigit) goto decode_num;
            nondigit = c;
            break;

          default:
            goto decode_num;
        }
        c = nextc(p);
    }

  decode_num:
    pushback(p, c);
    if (nondigit) {
      trailing_uc:
        literal_flush(p, p->lex.pcur - 1);
        YYLTYPE loc = RUBY_INIT_YYLLOC();
        compile_error(p, "trailing `%c' in number", nondigit);
        parser_show_error_line(p, &loc);
    }
    tokfix(p);
    if (is_float) {
        enum yytokentype type = tFLOAT;
        VALUE v;

        suffix = number_literal_suffix(p, seen_e ? NUM_SUFFIX_I : NUM_SUFFIX_ALL);
        if (suffix & NUM_SUFFIX_R) {
            type = tRATIONAL;
            v = parse_rational(p, tok(p), toklen(p), seen_point);
        }
        else {
            double d = strtod(tok(p), 0);
            if (errno == ERANGE) {
                rb_warning1("Float %s out of range", WARN_S(tok(p)));
                errno = 0;
            }
            v = DBL2NUM(d);
        }
        return set_number_literal(p, v, type, suffix);
    }
    suffix = number_literal_suffix(p, NUM_SUFFIX_ALL);
    return set_integer_literal(p, rb_cstr_to_inum(tok(p), 10, FALSE), suffix);
}

static enum yytokentype
parse_qmark(struct parser_params *p, int space_seen)
{
    rb_encoding *enc;
    register int c;
    VALUE lit;

    if (IS_END()) {
        SET_LEX_STATE(EXPR_VALUE);
        return '?';
    }
    c = nextc(p);
    if (c == -1) {
        compile_error(p, "incomplete character syntax");
        return 0;
    }
    if (rb_enc_isspace(c, p->enc)) {
        if (!IS_ARG()) {
            int c2 = escaped_control_code(c);
            if (c2) {
                WARN_SPACE_CHAR(c2, "?");
            }
        }
      ternary:
        pushback(p, c);
        SET_LEX_STATE(EXPR_VALUE);
        return '?';
    }
    newtok(p);
    enc = p->enc;
    if (!parser_isascii(p)) {
        if (tokadd_mbchar(p, c) == -1) return 0;
    }
    else if ((rb_enc_isalnum(c, p->enc) || c == '_') &&
             !lex_eol_p(p) && is_identchar(p, p->lex.pcur, p->lex.pend, p->enc)) {
        if (space_seen) {
            const char *start = p->lex.pcur - 1, *ptr = start;
            do {
                int n = parser_precise_mbclen(p, ptr);
                if (n < 0) return -1;
                ptr += n;
            } while (!lex_eol_ptr_p(p, ptr) && is_identchar(p, ptr, p->lex.pend, p->enc));
            rb_warn2("`?' just followed by `%.*s' is interpreted as" \
                     " a conditional operator, put a space after `?'",
                     WARN_I((int)(ptr - start)), WARN_S_L(start, (ptr - start)));
        }
        goto ternary;
    }
    else if (c == '\\') {
        if (peek(p, 'u')) {
            nextc(p);
            enc = rb_utf8_encoding();
            tokadd_utf8(p, &enc, -1, 0, 0);
        }
        else if (!ISASCII(c = peekc(p))) {
            nextc(p);
            if (tokadd_mbchar(p, c) == -1) return 0;
        }
        else {
            c = read_escape(p, 0);
            tokadd(p, c);
        }
    }
    else {
        tokadd(p, c);
    }
    tokfix(p);
    lit = STR_NEW3(tok(p), toklen(p), enc, 0);
    set_yylval_str(lit);
    SET_LEX_STATE(EXPR_END);
    return tCHAR;
}

static enum yytokentype
parse_percent(struct parser_params *p, const int space_seen, const enum lex_state_e last_state)
{
    register int c;
    const char *ptok = p->lex.pcur;

    if (IS_BEG()) {
        int term;
        int paren;

        c = nextc(p);
      quotation:
        if (c == -1) goto unterminated;
        if (!ISALNUM(c)) {
            term = c;
            if (!ISASCII(c)) goto unknown;
            c = 'Q';
        }
        else {
            term = nextc(p);
            if (rb_enc_isalnum(term, p->enc) || !parser_isascii(p)) {
              unknown:
                pushback(p, term);
                c = parser_precise_mbclen(p, p->lex.pcur);
                if (c < 0) return 0;
                p->lex.pcur += c;
                yyerror0("unknown type of %string");
                return 0;
            }
        }
        if (term == -1) {
          unterminated:
            compile_error(p, "unterminated quoted string meets end of file");
            return 0;
        }
        paren = term;
        if (term == '(') term = ')';
        else if (term == '[') term = ']';
        else if (term == '{') term = '}';
        else if (term == '<') term = '>';
        else paren = 0;

        p->lex.ptok = ptok-1;
        switch (c) {
          case 'Q':
            p->lex.strterm = NEW_STRTERM(str_dquote, term, paren);
            return tSTRING_BEG;

          case 'q':
            p->lex.strterm = NEW_STRTERM(str_squote, term, paren);
            return tSTRING_BEG;

          case 'W':
            p->lex.strterm = NEW_STRTERM(str_dword, term, paren);
            return tWORDS_BEG;

          case 'w':
            p->lex.strterm = NEW_STRTERM(str_sword, term, paren);
            return tQWORDS_BEG;

          case 'I':
            p->lex.strterm = NEW_STRTERM(str_dword, term, paren);
            return tSYMBOLS_BEG;

          case 'i':
            p->lex.strterm = NEW_STRTERM(str_sword, term, paren);
            return tQSYMBOLS_BEG;

          case 'x':
            p->lex.strterm = NEW_STRTERM(str_xquote, term, paren);
            return tXSTRING_BEG;

          case 'r':
            p->lex.strterm = NEW_STRTERM(str_regexp, term, paren);
            return tREGEXP_BEG;

          case 's':
            p->lex.strterm = NEW_STRTERM(str_ssym, term, paren);
            SET_LEX_STATE(EXPR_FNAME|EXPR_FITEM);
            return tSYMBEG;

          default:
            yyerror0("unknown type of %string");
            return 0;
        }
    }
    if ((c = nextc(p)) == '=') {
        set_yylval_id('%');
        SET_LEX_STATE(EXPR_BEG);
        return tOP_ASGN;
    }
    if (IS_SPCARG(c) || (IS_lex_state(EXPR_FITEM) && c == 's')) {
        goto quotation;
    }
    SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
    pushback(p, c);
    return warn_balanced('%', "%%", "string literal");
}

static int
tokadd_ident(struct parser_params *p, int c)
{
    do {
        if (tokadd_mbchar(p, c) == -1) return -1;
        c = nextc(p);
    } while (parser_is_identchar(p));
    pushback(p, c);
    return 0;
}

static ID
tokenize_ident(struct parser_params *p)
{
    ID ident = TOK_INTERN();

    set_yylval_name(ident);

    return ident;
}

static int
parse_numvar(struct parser_params *p)
{
    size_t len;
    int overflow;
    unsigned long n = ruby_scan_digits(tok(p)+1, toklen(p)-1, 10, &len, &overflow);
    const unsigned long nth_ref_max =
        ((FIXNUM_MAX < INT_MAX) ? FIXNUM_MAX : INT_MAX) >> 1;
    /* NTH_REF is left-shifted to be ORed with back-ref flag and
     * turned into a Fixnum, in compile.c */

    if (overflow || n > nth_ref_max) {
        /* compile_error()? */
        rb_warn1("`%s' is too big for a number variable, always nil", WARN_S(tok(p)));
        return 0;		/* $0 is $PROGRAM_NAME, not NTH_REF */
    }
    else {
        return (int)n;
    }
}

static enum yytokentype
parse_gvar(struct parser_params *p, const enum lex_state_e last_state)
{
    const char *ptr = p->lex.pcur;
    register int c;

    SET_LEX_STATE(EXPR_END);
    p->lex.ptok = ptr - 1; /* from '$' */
    newtok(p);
    c = nextc(p);
    switch (c) {
      case '_':		/* $_: last read line string */
        c = nextc(p);
        if (parser_is_identchar(p)) {
            tokadd(p, '$');
            tokadd(p, '_');
            break;
        }
        pushback(p, c);
        c = '_';
        /* fall through */
      case '~': 	/* $~: match-data */
      case '*': 	/* $*: argv */
      case '$': 	/* $$: pid */
      case '?': 	/* $?: last status */
      case '!': 	/* $!: error string */
      case '@': 	/* $@: error position */
      case '/': 	/* $/: input record separator */
      case '\\':	/* $\: output record separator */
      case ';': 	/* $;: field separator */
      case ',': 	/* $,: output field separator */
      case '.': 	/* $.: last read line number */
      case '=': 	/* $=: ignorecase */
      case ':': 	/* $:: load path */
      case '<': 	/* $<: reading filename */
      case '>': 	/* $>: default output handle */
      case '\"':	/* $": already loaded files */
        tokadd(p, '$');
        tokadd(p, c);
        goto gvar;

      case '-':
        tokadd(p, '$');
        tokadd(p, c);
        c = nextc(p);
        if (parser_is_identchar(p)) {
            if (tokadd_mbchar(p, c) == -1) return 0;
        }
        else {
            pushback(p, c);
            pushback(p, '-');
            return '$';
        }
      gvar:
        set_yylval_name(TOK_INTERN());
        return tGVAR;

      case '&': 	/* $&: last match */
      case '`': 	/* $`: string before last match */
      case '\'':	/* $': string after last match */
      case '+': 	/* $+: string matches last paren. */
        if (IS_lex_state_for(last_state, EXPR_FNAME)) {
            tokadd(p, '$');
            tokadd(p, c);
            goto gvar;
        }
        set_yylval_node(NEW_BACK_REF(c, &_cur_loc));
        return tBACK_REF;

      case '1': case '2': case '3':
      case '4': case '5': case '6':
      case '7': case '8': case '9':
        tokadd(p, '$');
        do {
            tokadd(p, c);
            c = nextc(p);
        } while (c != -1 && ISDIGIT(c));
        pushback(p, c);
        if (IS_lex_state_for(last_state, EXPR_FNAME)) goto gvar;
        tokfix(p);
        c = parse_numvar(p);
        set_yylval_node(NEW_NTH_REF(c, &_cur_loc));
        return tNTH_REF;

      default:
        if (!parser_is_identchar(p)) {
            YYLTYPE loc = RUBY_INIT_YYLLOC();
            if (c == -1 || ISSPACE(c)) {
                compile_error(p, "`$' without identifiers is not allowed as a global variable name");
            }
            else {
                pushback(p, c);
                compile_error(p, "`$%c' is not allowed as a global variable name", c);
            }
            parser_show_error_line(p, &loc);
            set_yylval_noname();
            return tGVAR;
        }
        /* fall through */
      case '0':
        tokadd(p, '$');
    }

    if (tokadd_ident(p, c)) return 0;
    SET_LEX_STATE(EXPR_END);
    if (VALID_SYMNAME_P(tok(p), toklen(p), p->enc, ID_GLOBAL)) {
        tokenize_ident(p);
    }
    else {
        compile_error(p, "`%.*s' is not allowed as a global variable name", toklen(p), tok(p));
        set_yylval_noname();
    }
    return tGVAR;
}

#ifndef RIPPER
static bool
parser_numbered_param(struct parser_params *p, int n)
{
    if (n < 0) return false;

    if (DVARS_TERMINAL_P(p->lvtbl->args) || DVARS_TERMINAL_P(p->lvtbl->args->prev)) {
        return false;
    }
    if (p->max_numparam == ORDINAL_PARAM) {
        compile_error(p, "ordinary parameter is defined");
        return false;
    }
    struct vtable *args = p->lvtbl->args;
    if (p->max_numparam < n) {
        p->max_numparam = n;
    }
    while (n > args->pos) {
        vtable_add(args, NUMPARAM_IDX_TO_ID(args->pos+1));
    }
    return true;
}
#endif

static enum yytokentype
parse_atmark(struct parser_params *p, const enum lex_state_e last_state)
{
    const char *ptr = p->lex.pcur;
    enum yytokentype result = tIVAR;
    register int c = nextc(p);
    YYLTYPE loc;

    p->lex.ptok = ptr - 1; /* from '@' */
    newtok(p);
    tokadd(p, '@');
    if (c == '@') {
        result = tCVAR;
        tokadd(p, '@');
        c = nextc(p);
    }
    SET_LEX_STATE(IS_lex_state_for(last_state, EXPR_FNAME) ? EXPR_ENDFN : EXPR_END);
    if (c == -1 || !parser_is_identchar(p)) {
        pushback(p, c);
        RUBY_SET_YYLLOC(loc);
        if (result == tIVAR) {
            compile_error(p, "`@' without identifiers is not allowed as an instance variable name");
        }
        else {
            compile_error(p, "`@@' without identifiers is not allowed as a class variable name");
        }
        parser_show_error_line(p, &loc);
        set_yylval_noname();
        SET_LEX_STATE(EXPR_END);
        return result;
    }
    else if (ISDIGIT(c)) {
        pushback(p, c);
        RUBY_SET_YYLLOC(loc);
        if (result == tIVAR) {
            compile_error(p, "`@%c' is not allowed as an instance variable name", c);
        }
        else {
            compile_error(p, "`@@%c' is not allowed as a class variable name", c);
        }
        parser_show_error_line(p, &loc);
        set_yylval_noname();
        SET_LEX_STATE(EXPR_END);
        return result;
    }

    if (tokadd_ident(p, c)) return 0;
    tokenize_ident(p);
    return result;
}

static enum yytokentype
parse_ident(struct parser_params *p, int c, int cmd_state)
{
    enum yytokentype result;
    int mb = ENC_CODERANGE_7BIT;
    const enum lex_state_e last_state = p->lex.state;
    ID ident;
    int enforce_keyword_end = 0;

    do {
        if (!ISASCII(c)) mb = ENC_CODERANGE_UNKNOWN;
        if (tokadd_mbchar(p, c) == -1) return 0;
        c = nextc(p);
    } while (parser_is_identchar(p));
    if ((c == '!' || c == '?') && !peek(p, '=')) {
        result = tFID;
        tokadd(p, c);
    }
    else if (c == '=' && IS_lex_state(EXPR_FNAME) &&
             (!peek(p, '~') && !peek(p, '>') && (!peek(p, '=') || (peek_n(p, '>', 1))))) {
        result = tIDENTIFIER;
        tokadd(p, c);
    }
    else {
        result = tCONSTANT;	/* assume provisionally */
        pushback(p, c);
    }
    tokfix(p);

    if (IS_LABEL_POSSIBLE()) {
        if (IS_LABEL_SUFFIX(0)) {
            SET_LEX_STATE(EXPR_ARG|EXPR_LABELED);
            nextc(p);
            set_yylval_name(TOK_INTERN());
            return tLABEL;
        }
    }

#ifndef RIPPER
    if (!NIL_P(peek_end_expect_token_locations(p))) {
        VALUE end_loc;
        int lineno, column;
        int beg_pos = (int)(p->lex.ptok - p->lex.pbeg);

        end_loc = peek_end_expect_token_locations(p);
        lineno = NUM2INT(rb_ary_entry(end_loc, 0));
        column = NUM2INT(rb_ary_entry(end_loc, 1));

        if (p->debug) {
            rb_parser_printf(p, "enforce_keyword_end check. current: (%d, %d), peek: (%d, %d)\n",
                                p->ruby_sourceline, beg_pos, lineno, column);
        }

        if ((p->ruby_sourceline > lineno) && (beg_pos <= column)) {
            const struct kwtable *kw;

            if ((IS_lex_state(EXPR_DOT)) && (kw = rb_reserved_word(tok(p), toklen(p))) && (kw && kw->id[0] == keyword_end)) {
                if (p->debug) rb_parser_printf(p, "enforce_keyword_end is enabled\n");
                enforce_keyword_end = 1;
            }
        }
    }
#endif

    if (mb == ENC_CODERANGE_7BIT && (!IS_lex_state(EXPR_DOT) || enforce_keyword_end)) {
        const struct kwtable *kw;

        /* See if it is a reserved word.  */
        kw = rb_reserved_word(tok(p), toklen(p));
        if (kw) {
            enum lex_state_e state = p->lex.state;
            if (IS_lex_state_for(state, EXPR_FNAME)) {
                SET_LEX_STATE(EXPR_ENDFN);
                set_yylval_name(rb_intern2(tok(p), toklen(p)));
                return kw->id[0];
            }
            SET_LEX_STATE(kw->state);
            if (IS_lex_state(EXPR_BEG)) {
                p->command_start = TRUE;
            }
            if (kw->id[0] == keyword_do) {
                if (lambda_beginning_p()) {
                    p->lex.lpar_beg = -1; /* make lambda_beginning_p() == FALSE in the body of "-> do ... end" */
                    return keyword_do_LAMBDA;
                }
                if (COND_P()) return keyword_do_cond;
                if (CMDARG_P() && !IS_lex_state_for(state, EXPR_CMDARG))
                    return keyword_do_block;
                return keyword_do;
            }
            if (IS_lex_state_for(state, (EXPR_BEG | EXPR_LABELED | EXPR_CLASS)))
                return kw->id[0];
            else {
                if (kw->id[0] != kw->id[1])
                    SET_LEX_STATE(EXPR_BEG | EXPR_LABEL);
                return kw->id[1];
            }
        }
    }

    if (IS_lex_state(EXPR_BEG_ANY | EXPR_ARG_ANY | EXPR_DOT)) {
        if (cmd_state) {
            SET_LEX_STATE(EXPR_CMDARG);
        }
        else {
            SET_LEX_STATE(EXPR_ARG);
        }
    }
    else if (p->lex.state == EXPR_FNAME) {
        SET_LEX_STATE(EXPR_ENDFN);
    }
    else {
        SET_LEX_STATE(EXPR_END);
    }

    ident = tokenize_ident(p);
    if (result == tCONSTANT && is_local_id(ident)) result = tIDENTIFIER;
    if (!IS_lex_state_for(last_state, EXPR_DOT|EXPR_FNAME) &&
        (result == tIDENTIFIER) && /* not EXPR_FNAME, not attrasgn */
        (lvar_defined(p, ident) || NUMPARAM_ID_P(ident))) {
        SET_LEX_STATE(EXPR_END|EXPR_LABEL);
    }
    return result;
}

static void
warn_cr(struct parser_params *p)
{
    if (!p->cr_seen) {
        p->cr_seen = TRUE;
        /* carried over with p->lex.nextline for nextc() */
        rb_warn0("encountered \\r in middle of line, treated as a mere space");
    }
}

static enum yytokentype
parser_yylex(struct parser_params *p)
{
    register int c;
    int space_seen = 0;
    int cmd_state;
    int label;
    enum lex_state_e last_state;
    int fallthru = FALSE;
    int token_seen = p->token_seen;

    if (p->lex.strterm) {
        if (strterm_is_heredoc(p->lex.strterm)) {
            token_flush(p);
            return here_document(p, &p->lex.strterm->u.heredoc);
        }
        else {
            token_flush(p);
            return parse_string(p, &p->lex.strterm->u.literal);
        }
    }
    cmd_state = p->command_start;
    p->command_start = FALSE;
    p->token_seen = TRUE;
#ifndef RIPPER
    token_flush(p);
#endif
  retry:
    last_state = p->lex.state;
    switch (c = nextc(p)) {
      case '\0':		/* NUL */
      case '\004':		/* ^D */
      case '\032':		/* ^Z */
      case -1:			/* end of script. */
        p->eofp  = 1;
#ifndef RIPPER
        if (!NIL_P(p->end_expect_token_locations) && RARRAY_LEN(p->end_expect_token_locations) > 0) {
            pop_end_expect_token_locations(p);
            RUBY_SET_YYLLOC_OF_DUMMY_END(*p->yylloc);
            return tDUMNY_END;
        }
#endif
        /* Set location for end-of-input because dispatch_scan_event is not called. */
        RUBY_SET_YYLLOC(*p->yylloc);
        return END_OF_INPUT;

        /* white spaces */
      case '\r':
        warn_cr(p);
        /* fall through */
      case ' ': case '\t': case '\f':
      case '\13': /* '\v' */
        space_seen = 1;
        while ((c = nextc(p))) {
            switch (c) {
              case '\r':
                warn_cr(p);
                /* fall through */
              case ' ': case '\t': case '\f':
              case '\13': /* '\v' */
                break;
              default:
                goto outofloop;
            }
        }
      outofloop:
        pushback(p, c);
        dispatch_scan_event(p, tSP);
#ifndef RIPPER
        token_flush(p);
#endif
        goto retry;

      case '#':		/* it's a comment */
        p->token_seen = token_seen;
        /* no magic_comment in shebang line */
        if (!parser_magic_comment(p, p->lex.pcur, p->lex.pend - p->lex.pcur)) {
            if (comment_at_top(p)) {
                set_file_encoding(p, p->lex.pcur, p->lex.pend);
            }
        }
        lex_goto_eol(p);
        dispatch_scan_event(p, tCOMMENT);
        fallthru = TRUE;
        /* fall through */
      case '\n':
        p->token_seen = token_seen;
        VALUE prevline = p->lex.lastline;
        c = (IS_lex_state(EXPR_BEG|EXPR_CLASS|EXPR_FNAME|EXPR_DOT) &&
             !IS_lex_state(EXPR_LABELED));
        if (c || IS_lex_state_all(EXPR_ARG|EXPR_LABELED)) {
            if (!fallthru) {
                dispatch_scan_event(p, tIGNORED_NL);
            }
            fallthru = FALSE;
            if (!c && p->ctxt.in_kwarg) {
                goto normal_newline;
            }
            goto retry;
        }
        while (1) {
            switch (c = nextc(p)) {
              case ' ': case '\t': case '\f': case '\r':
              case '\13': /* '\v' */
                space_seen = 1;
                break;
              case '#':
                pushback(p, c);
                if (space_seen) {
                    dispatch_scan_event(p, tSP);
                    token_flush(p);
                }
                goto retry;
              case '&':
              case '.': {
                dispatch_delayed_token(p, tIGNORED_NL);
                if (peek(p, '.') == (c == '&')) {
                    pushback(p, c);
                    dispatch_scan_event(p, tSP);
                    goto retry;
                }
              }
              default:
                p->ruby_sourceline--;
                p->lex.nextline = p->lex.lastline;
                set_lastline(p, prevline);
              case -1:		/* EOF no decrement*/
                lex_goto_eol(p);
                if (c != -1) {
                    token_flush(p);
                    RUBY_SET_YYLLOC(*p->yylloc);
                }
                goto normal_newline;
            }
        }
      normal_newline:
        p->command_start = TRUE;
        SET_LEX_STATE(EXPR_BEG);
        return '\n';

      case '*':
        if ((c = nextc(p)) == '*') {
            if ((c = nextc(p)) == '=') {
                set_yylval_id(idPow);
                SET_LEX_STATE(EXPR_BEG);
                return tOP_ASGN;
            }
            pushback(p, c);
            if (IS_SPCARG(c)) {
                rb_warning0("`**' interpreted as argument prefix");
                c = tDSTAR;
            }
            else if (IS_BEG()) {
                c = tDSTAR;
            }
            else {
                c = warn_balanced((enum ruby_method_ids)tPOW, "**", "argument prefix");
            }
        }
        else {
            if (c == '=') {
                set_yylval_id('*');
                SET_LEX_STATE(EXPR_BEG);
                return tOP_ASGN;
            }
            pushback(p, c);
            if (IS_SPCARG(c)) {
                rb_warning0("`*' interpreted as argument prefix");
                c = tSTAR;
            }
            else if (IS_BEG()) {
                c = tSTAR;
            }
            else {
                c = warn_balanced('*', "*", "argument prefix");
            }
        }
        SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
        return c;

      case '!':
        c = nextc(p);
        if (IS_AFTER_OPERATOR()) {
            SET_LEX_STATE(EXPR_ARG);
            if (c == '@') {
                return '!';
            }
        }
        else {
            SET_LEX_STATE(EXPR_BEG);
        }
        if (c == '=') {
            return tNEQ;
        }
        if (c == '~') {
            return tNMATCH;
        }
        pushback(p, c);
        return '!';

      case '=':
        if (was_bol(p)) {
            /* skip embedded rd document */
            if (word_match_p(p, "begin", 5)) {
                int first_p = TRUE;

                lex_goto_eol(p);
                dispatch_scan_event(p, tEMBDOC_BEG);
                for (;;) {
                    lex_goto_eol(p);
                    if (!first_p) {
                        dispatch_scan_event(p, tEMBDOC);
                    }
                    first_p = FALSE;
                    c = nextc(p);
                    if (c == -1) {
                        compile_error(p, "embedded document meets end of file");
                        return END_OF_INPUT;
                    }
                    if (c == '=' && word_match_p(p, "end", 3)) {
                        break;
                    }
                    pushback(p, c);
                }
                lex_goto_eol(p);
                dispatch_scan_event(p, tEMBDOC_END);
                goto retry;
            }
        }

        SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
        if ((c = nextc(p)) == '=') {
            if ((c = nextc(p)) == '=') {
                return tEQQ;
            }
            pushback(p, c);
            return tEQ;
        }
        if (c == '~') {
            return tMATCH;
        }
        else if (c == '>') {
            return tASSOC;
        }
        pushback(p, c);
        return '=';

      case '<':
        c = nextc(p);
        if (c == '<' &&
            !IS_lex_state(EXPR_DOT | EXPR_CLASS) &&
            !IS_END() &&
            (!IS_ARG() || IS_lex_state(EXPR_LABELED) || space_seen)) {
            enum  yytokentype token = heredoc_identifier(p);
            if (token) return token < 0 ? 0 : token;
        }
        if (IS_AFTER_OPERATOR()) {
            SET_LEX_STATE(EXPR_ARG);
        }
        else {
            if (IS_lex_state(EXPR_CLASS))
                p->command_start = TRUE;
            SET_LEX_STATE(EXPR_BEG);
        }
        if (c == '=') {
            if ((c = nextc(p)) == '>') {
                return tCMP;
            }
            pushback(p, c);
            return tLEQ;
        }
        if (c == '<') {
            if ((c = nextc(p)) == '=') {
                set_yylval_id(idLTLT);
                SET_LEX_STATE(EXPR_BEG);
                return tOP_ASGN;
            }
            pushback(p, c);
            return warn_balanced((enum ruby_method_ids)tLSHFT, "<<", "here document");
        }
        pushback(p, c);
        return '<';

      case '>':
        SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
        if ((c = nextc(p)) == '=') {
            return tGEQ;
        }
        if (c == '>') {
            if ((c = nextc(p)) == '=') {
                set_yylval_id(idGTGT);
                SET_LEX_STATE(EXPR_BEG);
                return tOP_ASGN;
            }
            pushback(p, c);
            return tRSHFT;
        }
        pushback(p, c);
        return '>';

      case '"':
        label = (IS_LABEL_POSSIBLE() ? str_label : 0);
        p->lex.strterm = NEW_STRTERM(str_dquote | label, '"', 0);
        p->lex.ptok = p->lex.pcur-1;
        return tSTRING_BEG;

      case '`':
        if (IS_lex_state(EXPR_FNAME)) {
            SET_LEX_STATE(EXPR_ENDFN);
            return c;
        }
        if (IS_lex_state(EXPR_DOT)) {
            if (cmd_state)
                SET_LEX_STATE(EXPR_CMDARG);
            else
                SET_LEX_STATE(EXPR_ARG);
            return c;
        }
        p->lex.strterm = NEW_STRTERM(str_xquote, '`', 0);
        return tXSTRING_BEG;

      case '\'':
        label = (IS_LABEL_POSSIBLE() ? str_label : 0);
        p->lex.strterm = NEW_STRTERM(str_squote | label, '\'', 0);
        p->lex.ptok = p->lex.pcur-1;
        return tSTRING_BEG;

      case '?':
        return parse_qmark(p, space_seen);

      case '&':
        if ((c = nextc(p)) == '&') {
            SET_LEX_STATE(EXPR_BEG);
            if ((c = nextc(p)) == '=') {
                set_yylval_id(idANDOP);
                SET_LEX_STATE(EXPR_BEG);
                return tOP_ASGN;
            }
            pushback(p, c);
            return tANDOP;
        }
        else if (c == '=') {
            set_yylval_id('&');
            SET_LEX_STATE(EXPR_BEG);
            return tOP_ASGN;
        }
        else if (c == '.') {
            set_yylval_id(idANDDOT);
            SET_LEX_STATE(EXPR_DOT);
            return tANDDOT;
        }
        pushback(p, c);
        if (IS_SPCARG(c)) {
            if ((c != ':') ||
                (c = peekc_n(p, 1)) == -1 ||
                !(c == '\'' || c == '"' ||
                  is_identchar(p, (p->lex.pcur+1), p->lex.pend, p->enc))) {
                rb_warning0("`&' interpreted as argument prefix");
            }
            c = tAMPER;
        }
        else if (IS_BEG()) {
            c = tAMPER;
        }
        else {
            c = warn_balanced('&', "&", "argument prefix");
        }
        SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
        return c;

      case '|':
        if ((c = nextc(p)) == '|') {
            SET_LEX_STATE(EXPR_BEG);
            if ((c = nextc(p)) == '=') {
                set_yylval_id(idOROP);
                SET_LEX_STATE(EXPR_BEG);
                return tOP_ASGN;
            }
            pushback(p, c);
            if (IS_lex_state_for(last_state, EXPR_BEG)) {
                c = '|';
                pushback(p, '|');
                return c;
            }
            return tOROP;
        }
        if (c == '=') {
            set_yylval_id('|');
            SET_LEX_STATE(EXPR_BEG);
            return tOP_ASGN;
        }
        SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG|EXPR_LABEL);
        pushback(p, c);
        return '|';

      case '+':
        c = nextc(p);
        if (IS_AFTER_OPERATOR()) {
            SET_LEX_STATE(EXPR_ARG);
            if (c == '@') {
                return tUPLUS;
            }
            pushback(p, c);
            return '+';
        }
        if (c == '=') {
            set_yylval_id('+');
            SET_LEX_STATE(EXPR_BEG);
            return tOP_ASGN;
        }
        if (IS_BEG() || (IS_SPCARG(c) && arg_ambiguous(p, '+'))) {
            SET_LEX_STATE(EXPR_BEG);
            pushback(p, c);
            if (c != -1 && ISDIGIT(c)) {
                return parse_numeric(p, '+');
            }
            return tUPLUS;
        }
        SET_LEX_STATE(EXPR_BEG);
        pushback(p, c);
        return warn_balanced('+', "+", "unary operator");

      case '-':
        c = nextc(p);
        if (IS_AFTER_OPERATOR()) {
            SET_LEX_STATE(EXPR_ARG);
            if (c == '@') {
                return tUMINUS;
            }
            pushback(p, c);
            return '-';
        }
        if (c == '=') {
            set_yylval_id('-');
            SET_LEX_STATE(EXPR_BEG);
            return tOP_ASGN;
        }
        if (c == '>') {
            SET_LEX_STATE(EXPR_ENDFN);
            return tLAMBDA;
        }
        if (IS_BEG() || (IS_SPCARG(c) && arg_ambiguous(p, '-'))) {
            SET_LEX_STATE(EXPR_BEG);
            pushback(p, c);
            if (c != -1 && ISDIGIT(c)) {
                return tUMINUS_NUM;
            }
            return tUMINUS;
        }
        SET_LEX_STATE(EXPR_BEG);
        pushback(p, c);
        return warn_balanced('-', "-", "unary operator");

      case '.': {
        int is_beg = IS_BEG();
        SET_LEX_STATE(EXPR_BEG);
        if ((c = nextc(p)) == '.') {
            if ((c = nextc(p)) == '.') {
                if (p->ctxt.in_argdef) {
                    SET_LEX_STATE(EXPR_ENDARG);
                    return tBDOT3;
                }
                if (p->lex.paren_nest == 0 && looking_at_eol_p(p)) {
                    rb_warn0("... at EOL, should be parenthesized?");
                }
                else if (p->lex.lpar_beg >= 0 && p->lex.lpar_beg+1 == p->lex.paren_nest) {
                    if (IS_lex_state_for(last_state, EXPR_LABEL))
                        return tDOT3;
                }
                return is_beg ? tBDOT3 : tDOT3;
            }
            pushback(p, c);
            return is_beg ? tBDOT2 : tDOT2;
        }
        pushback(p, c);
        if (c != -1 && ISDIGIT(c)) {
            char prev = p->lex.pcur-1 > p->lex.pbeg ? *(p->lex.pcur-2) : 0;
            parse_numeric(p, '.');
            if (ISDIGIT(prev)) {
                yyerror0("unexpected fraction part after numeric literal");
            }
            else {
                yyerror0("no .<digit> floating literal anymore; put 0 before dot");
            }
            SET_LEX_STATE(EXPR_END);
            p->lex.ptok = p->lex.pcur;
            goto retry;
        }
        set_yylval_id('.');
        SET_LEX_STATE(EXPR_DOT);
        return '.';
      }

      case '0': case '1': case '2': case '3': case '4':
      case '5': case '6': case '7': case '8': case '9':
        return parse_numeric(p, c);

      case ')':
        COND_POP();
        CMDARG_POP();
        SET_LEX_STATE(EXPR_ENDFN);
        p->lex.paren_nest--;
        return c;

      case ']':
        COND_POP();
        CMDARG_POP();
        SET_LEX_STATE(EXPR_END);
        p->lex.paren_nest--;
        return c;

      case '}':
        /* tSTRING_DEND does COND_POP and CMDARG_POP in the yacc's rule */
        if (!p->lex.brace_nest--) return tSTRING_DEND;
        COND_POP();
        CMDARG_POP();
        SET_LEX_STATE(EXPR_END);
        p->lex.paren_nest--;
        return c;

      case ':':
        c = nextc(p);
        if (c == ':') {
            if (IS_BEG() || IS_lex_state(EXPR_CLASS) || IS_SPCARG(-1)) {
                SET_LEX_STATE(EXPR_BEG);
                return tCOLON3;
            }
            set_yylval_id(idCOLON2);
            SET_LEX_STATE(EXPR_DOT);
            return tCOLON2;
        }
        if (IS_END() || ISSPACE(c) || c == '#') {
            pushback(p, c);
            c = warn_balanced(':', ":", "symbol literal");
            SET_LEX_STATE(EXPR_BEG);
            return c;
        }
        switch (c) {
          case '\'':
            p->lex.strterm = NEW_STRTERM(str_ssym, c, 0);
            break;
          case '"':
            p->lex.strterm = NEW_STRTERM(str_dsym, c, 0);
            break;
          default:
            pushback(p, c);
            break;
        }
        SET_LEX_STATE(EXPR_FNAME);
        return tSYMBEG;

      case '/':
        if (IS_BEG()) {
            p->lex.strterm = NEW_STRTERM(str_regexp, '/', 0);
            return tREGEXP_BEG;
        }
        if ((c = nextc(p)) == '=') {
            set_yylval_id('/');
            SET_LEX_STATE(EXPR_BEG);
            return tOP_ASGN;
        }
        pushback(p, c);
        if (IS_SPCARG(c)) {
            arg_ambiguous(p, '/');
            p->lex.strterm = NEW_STRTERM(str_regexp, '/', 0);
            return tREGEXP_BEG;
        }
        SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
        return warn_balanced('/', "/", "regexp literal");

      case '^':
        if ((c = nextc(p)) == '=') {
            set_yylval_id('^');
            SET_LEX_STATE(EXPR_BEG);
            return tOP_ASGN;
        }
        SET_LEX_STATE(IS_AFTER_OPERATOR() ? EXPR_ARG : EXPR_BEG);
        pushback(p, c);
        return '^';

      case ';':
        SET_LEX_STATE(EXPR_BEG);
        p->command_start = TRUE;
        return ';';

      case ',':
        SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
        return ',';

      case '~':
        if (IS_AFTER_OPERATOR()) {
            if ((c = nextc(p)) != '@') {
                pushback(p, c);
            }
            SET_LEX_STATE(EXPR_ARG);
        }
        else {
            SET_LEX_STATE(EXPR_BEG);
        }
        return '~';

      case '(':
        if (IS_BEG()) {
            c = tLPAREN;
        }
        else if (!space_seen) {
            /* foo( ... ) => method call, no ambiguity */
        }
        else if (IS_ARG() || IS_lex_state_all(EXPR_END|EXPR_LABEL)) {
            c = tLPAREN_ARG;
        }
        else if (IS_lex_state(EXPR_ENDFN) && !lambda_beginning_p()) {
            rb_warning0("parentheses after method name is interpreted as "
                        "an argument list, not a decomposed argument");
        }
        p->lex.paren_nest++;
        COND_PUSH(0);
        CMDARG_PUSH(0);
        SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
        return c;

      case '[':
        p->lex.paren_nest++;
        if (IS_AFTER_OPERATOR()) {
            if ((c = nextc(p)) == ']') {
                p->lex.paren_nest--;
                SET_LEX_STATE(EXPR_ARG);
                if ((c = nextc(p)) == '=') {
                    return tASET;
                }
                pushback(p, c);
                return tAREF;
            }
            pushback(p, c);
            SET_LEX_STATE(EXPR_ARG|EXPR_LABEL);
            return '[';
        }
        else if (IS_BEG()) {
            c = tLBRACK;
        }
        else if (IS_ARG() && (space_seen || IS_lex_state(EXPR_LABELED))) {
            c = tLBRACK;
        }
        SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
        COND_PUSH(0);
        CMDARG_PUSH(0);
        return c;

      case '{':
        ++p->lex.brace_nest;
        if (lambda_beginning_p())
            c = tLAMBEG;
        else if (IS_lex_state(EXPR_LABELED))
            c = tLBRACE;      /* hash */
        else if (IS_lex_state(EXPR_ARG_ANY | EXPR_END | EXPR_ENDFN))
            c = '{';          /* block (primary) */
        else if (IS_lex_state(EXPR_ENDARG))
            c = tLBRACE_ARG;  /* block (expr) */
        else
            c = tLBRACE;      /* hash */
        if (c != tLBRACE) {
            p->command_start = TRUE;
            SET_LEX_STATE(EXPR_BEG);
        }
        else {
            SET_LEX_STATE(EXPR_BEG|EXPR_LABEL);
        }
        ++p->lex.paren_nest;  /* after lambda_beginning_p() */
        COND_PUSH(0);
        CMDARG_PUSH(0);
        return c;

      case '\\':
        c = nextc(p);
        if (c == '\n') {
            space_seen = 1;
            dispatch_scan_event(p, tSP);
            goto retry; /* skip \\n */
        }
        if (c == ' ') return tSP;
        if (ISSPACE(c)) return c;
        pushback(p, c);
        return '\\';

      case '%':
        return parse_percent(p, space_seen, last_state);

      case '$':
        return parse_gvar(p, last_state);

      case '@':
        return parse_atmark(p, last_state);

      case '_':
        if (was_bol(p) && whole_match_p(p, "__END__", 7, 0)) {
            p->ruby__end__seen = 1;
            p->eofp = 1;
#ifdef RIPPER
            lex_goto_eol(p);
            dispatch_scan_event(p, k__END__);
#endif
            return END_OF_INPUT;
        }
        newtok(p);
        break;

      default:
        if (!parser_is_identchar(p)) {
            compile_error(p, "Invalid char `\\x%02X' in expression", c);
            token_flush(p);
            goto retry;
        }

        newtok(p);
        break;
    }

    return parse_ident(p, c, cmd_state);
}

static enum yytokentype
yylex(YYSTYPE *lval, YYLTYPE *yylloc, struct parser_params *p)
{
    enum yytokentype t;

    p->lval = lval;
    lval->val = Qundef;
    p->yylloc = yylloc;

    t = parser_yylex(p);

    if (has_delayed_token(p))
        dispatch_delayed_token(p, t);
    else if (t != END_OF_INPUT)
        dispatch_scan_event(p, t);

    return t;
}

#define LVAR_USED ((ID)1 << (sizeof(ID) * CHAR_BIT - 1))

static NODE*
node_new_internal(struct parser_params *p, enum node_type type, size_t size, size_t alignment)
{
    NODE *n = rb_ast_newnode(p->ast, type, size, alignment);

    rb_node_init(n, type);
    return n;
}

static NODE *
nd_set_loc(NODE *nd, const YYLTYPE *loc)
{
    nd->nd_loc = *loc;
    nd_set_line(nd, loc->beg_pos.lineno);
    return nd;
}

static NODE*
node_newnode(struct parser_params *p, enum node_type type, size_t size, size_t alignment, const rb_code_location_t *loc)
{
    NODE *n = node_new_internal(p, type, size, alignment);

    nd_set_loc(n, loc);
    nd_set_node_id(n, parser_get_node_id(p));
    return n;
}

#define NODE_NEWNODE(node_type, type, loc) (type *)(node_newnode(p, node_type, sizeof(type), RUBY_ALIGNOF(type), loc))

#ifndef RIPPER

static rb_node_scope_t *
rb_node_scope_new(struct parser_params *p, rb_node_args_t *nd_args, NODE *nd_body, const YYLTYPE *loc)
{
    rb_ast_id_table_t *nd_tbl;
    nd_tbl = local_tbl(p);
    rb_node_scope_t *n = NODE_NEWNODE(NODE_SCOPE, rb_node_scope_t, loc);
    n->nd_tbl = nd_tbl;
    n->nd_body = nd_body;
    n->nd_args = nd_args;

    return n;
}

static rb_node_scope_t *
rb_node_scope_new2(struct parser_params *p, rb_ast_id_table_t *nd_tbl, rb_node_args_t *nd_args, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_scope_t *n = NODE_NEWNODE(NODE_SCOPE, rb_node_scope_t, loc);
    n->nd_tbl = nd_tbl;
    n->nd_body = nd_body;
    n->nd_args = nd_args;

    return n;
}

static rb_node_defn_t *
rb_node_defn_new(struct parser_params *p, ID nd_mid, NODE *nd_defn, const YYLTYPE *loc)
{
    rb_node_defn_t *n = NODE_NEWNODE(NODE_DEFN, rb_node_defn_t, loc);
    n->nd_mid = nd_mid;
    n->nd_defn = nd_defn;

    return n;
}

static rb_node_defs_t *
rb_node_defs_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_defn, const YYLTYPE *loc)
{
    rb_node_defs_t *n = NODE_NEWNODE(NODE_DEFS, rb_node_defs_t, loc);
    n->nd_recv = nd_recv;
    n->nd_mid = nd_mid;
    n->nd_defn = nd_defn;

    return n;
}

static rb_node_block_t *
rb_node_block_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc)
{
    rb_node_block_t *n = NODE_NEWNODE(NODE_BLOCK, rb_node_block_t, loc);
    n->nd_head = nd_head;
    n->nd_end = 0;
    n->nd_next = 0;

    return n;
}

static rb_node_for_t *
rb_node_for_new(struct parser_params *p, NODE *nd_iter, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_for_t *n = NODE_NEWNODE(NODE_FOR, rb_node_for_t, loc);
    n->nd_body = nd_body;
    n->nd_iter = nd_iter;

    return n;
}

static rb_node_for_masgn_t *
rb_node_for_masgn_new(struct parser_params *p, NODE *nd_var, const YYLTYPE *loc)
{
    rb_node_for_masgn_t *n = NODE_NEWNODE(NODE_FOR_MASGN, rb_node_for_masgn_t, loc);
    n->nd_var = nd_var;

    return n;
}

static rb_node_retry_t *
rb_node_retry_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_retry_t *n = NODE_NEWNODE(NODE_RETRY, rb_node_retry_t, loc);

    return n;
}

static rb_node_begin_t *
rb_node_begin_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_begin_t *n = NODE_NEWNODE(NODE_BEGIN, rb_node_begin_t, loc);
    n->nd_body = nd_body;

    return n;
}

static rb_node_rescue_t *
rb_node_rescue_new(struct parser_params *p, NODE *nd_head, NODE *nd_resq, NODE *nd_else, const YYLTYPE *loc)
{
    rb_node_rescue_t *n = NODE_NEWNODE(NODE_RESCUE, rb_node_rescue_t, loc);
    n->nd_head = nd_head;
    n->nd_resq = nd_resq;
    n->nd_else = nd_else;

    return n;
}

static rb_node_resbody_t *
rb_node_resbody_new(struct parser_params *p, NODE *nd_args, NODE *nd_body, NODE *nd_head, const YYLTYPE *loc)
{
    rb_node_resbody_t *n = NODE_NEWNODE(NODE_RESBODY, rb_node_resbody_t, loc);
    n->nd_head = nd_head;
    n->nd_body = nd_body;
    n->nd_args = nd_args;

    return n;
}

static rb_node_ensure_t *
rb_node_ensure_new(struct parser_params *p, NODE *nd_head, NODE *nd_ensr, const YYLTYPE *loc)
{
    rb_node_ensure_t *n = NODE_NEWNODE(NODE_ENSURE, rb_node_ensure_t, loc);
    n->nd_head = nd_head;
    n->nd_resq = 0;
    n->nd_ensr = nd_ensr;

    return n;
}

static rb_node_and_t *
rb_node_and_new(struct parser_params *p, NODE *nd_1st, NODE *nd_2nd, const YYLTYPE *loc)
{
    rb_node_and_t *n = NODE_NEWNODE(NODE_AND, rb_node_and_t, loc);
    n->nd_1st = nd_1st;
    n->nd_2nd = nd_2nd;

    return n;
}

static rb_node_or_t *
rb_node_or_new(struct parser_params *p, NODE *nd_1st, NODE *nd_2nd, const YYLTYPE *loc)
{
    rb_node_or_t *n = NODE_NEWNODE(NODE_OR, rb_node_or_t, loc);
    n->nd_1st = nd_1st;
    n->nd_2nd = nd_2nd;

    return n;
}

static rb_node_return_t *
rb_node_return_new(struct parser_params *p, NODE *nd_stts, const YYLTYPE *loc)
{
    rb_node_return_t *n = NODE_NEWNODE(NODE_RETURN, rb_node_return_t, loc);
    n->nd_stts = nd_stts;
    return n;
}

static rb_node_yield_t *
rb_node_yield_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc)
{
    rb_node_yield_t *n = NODE_NEWNODE(NODE_YIELD, rb_node_yield_t, loc);
    n->nd_head = nd_head;

    return n;
}

static rb_node_if_t *
rb_node_if_new(struct parser_params *p, NODE *nd_cond, NODE *nd_body, NODE *nd_else, const YYLTYPE *loc)
{
    rb_node_if_t *n = NODE_NEWNODE(NODE_IF, rb_node_if_t, loc);
    n->nd_cond = nd_cond;
    n->nd_body = nd_body;
    n->nd_else = nd_else;

    return n;
}

static rb_node_unless_t *
rb_node_unless_new(struct parser_params *p, NODE *nd_cond, NODE *nd_body, NODE *nd_else, const YYLTYPE *loc)
{
    rb_node_unless_t *n = NODE_NEWNODE(NODE_UNLESS, rb_node_unless_t, loc);
    n->nd_cond = nd_cond;
    n->nd_body = nd_body;
    n->nd_else = nd_else;

    return n;
}

static rb_node_class_t *
rb_node_class_new(struct parser_params *p, NODE *nd_cpath, NODE *nd_body, NODE *nd_super, const YYLTYPE *loc)
{
    /* Keep the order of node creation */
    NODE *scope = NEW_SCOPE(0, nd_body, loc);
    rb_node_class_t *n = NODE_NEWNODE(NODE_CLASS, rb_node_class_t, loc);
    n->nd_cpath = nd_cpath;
    n->nd_body = scope;
    n->nd_super = nd_super;

    return n;
}

static rb_node_sclass_t *
rb_node_sclass_new(struct parser_params *p, NODE *nd_recv, NODE *nd_body, const YYLTYPE *loc)
{
    /* Keep the order of node creation */
    NODE *scope = NEW_SCOPE(0, nd_body, loc);
    rb_node_sclass_t *n = NODE_NEWNODE(NODE_SCLASS, rb_node_sclass_t, loc);
    n->nd_recv = nd_recv;
    n->nd_body = scope;

    return n;
}

static rb_node_module_t *
rb_node_module_new(struct parser_params *p, NODE *nd_cpath, NODE *nd_body, const YYLTYPE *loc)
{
    /* Keep the order of node creation */
    NODE *scope = NEW_SCOPE(0, nd_body, loc);
    rb_node_module_t *n = NODE_NEWNODE(NODE_MODULE, rb_node_module_t, loc);
    n->nd_cpath = nd_cpath;
    n->nd_body = scope;

    return n;
}

static rb_node_iter_t *
rb_node_iter_new(struct parser_params *p, rb_node_args_t *nd_args, NODE *nd_body, const YYLTYPE *loc)
{
    /* Keep the order of node creation */
    NODE *scope = NEW_SCOPE(nd_args, nd_body, loc);
    rb_node_iter_t *n = NODE_NEWNODE(NODE_ITER, rb_node_iter_t, loc);
    n->nd_body = scope;
    n->nd_iter = 0;

    return n;
}

static rb_node_lambda_t *
rb_node_lambda_new(struct parser_params *p, rb_node_args_t *nd_args, NODE *nd_body, const YYLTYPE *loc)
{
    /* Keep the order of node creation */
    NODE *scope = NEW_SCOPE(nd_args, nd_body, loc);
    rb_node_lambda_t *n = NODE_NEWNODE(NODE_LAMBDA, rb_node_lambda_t, loc);
    n->nd_body = scope;

    return n;
}

static rb_node_case_t *
rb_node_case_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_case_t *n = NODE_NEWNODE(NODE_CASE, rb_node_case_t, loc);
    n->nd_head = nd_head;
    n->nd_body = nd_body;

    return n;
}

static rb_node_case2_t *
rb_node_case2_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_case2_t *n = NODE_NEWNODE(NODE_CASE2, rb_node_case2_t, loc);
    n->nd_head = 0;
    n->nd_body = nd_body;

    return n;
}

static rb_node_case3_t *
rb_node_case3_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_case3_t *n = NODE_NEWNODE(NODE_CASE3, rb_node_case3_t, loc);
    n->nd_head = nd_head;
    n->nd_body = nd_body;

    return n;
}

static rb_node_when_t *
rb_node_when_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, NODE *nd_next, const YYLTYPE *loc)
{
    rb_node_when_t *n = NODE_NEWNODE(NODE_WHEN, rb_node_when_t, loc);
    n->nd_head = nd_head;
    n->nd_body = nd_body;
    n->nd_next = nd_next;

    return n;
}

static rb_node_in_t *
rb_node_in_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, NODE *nd_next, const YYLTYPE *loc)
{
    rb_node_in_t *n = NODE_NEWNODE(NODE_IN, rb_node_in_t, loc);
    n->nd_head = nd_head;
    n->nd_body = nd_body;
    n->nd_next = nd_next;

    return n;
}

static rb_node_while_t *
rb_node_while_new(struct parser_params *p, NODE *nd_cond, NODE *nd_body, long nd_state, const YYLTYPE *loc)
{
    rb_node_while_t *n = NODE_NEWNODE(NODE_WHILE, rb_node_while_t, loc);
    n->nd_cond = nd_cond;
    n->nd_body = nd_body;
    n->nd_state = nd_state;

    return n;
}

static rb_node_until_t *
rb_node_until_new(struct parser_params *p, NODE *nd_cond, NODE *nd_body, long nd_state, const YYLTYPE *loc)
{
    rb_node_until_t *n = NODE_NEWNODE(NODE_UNTIL, rb_node_until_t, loc);
    n->nd_cond = nd_cond;
    n->nd_body = nd_body;
    n->nd_state = nd_state;

    return n;
}

static rb_node_colon2_t *
rb_node_colon2_new(struct parser_params *p, NODE *nd_head, ID nd_mid, const YYLTYPE *loc)
{
    rb_node_colon2_t *n = NODE_NEWNODE(NODE_COLON2, rb_node_colon2_t, loc);
    n->nd_head = nd_head;
    n->nd_mid = nd_mid;

    return n;
}

static rb_node_colon3_t *
rb_node_colon3_new(struct parser_params *p, ID nd_mid, const YYLTYPE *loc)
{
    rb_node_colon3_t *n = NODE_NEWNODE(NODE_COLON3, rb_node_colon3_t, loc);
    n->nd_mid = nd_mid;

    return n;
}

static rb_node_dot2_t *
rb_node_dot2_new(struct parser_params *p, NODE *nd_beg, NODE *nd_end, const YYLTYPE *loc)
{
    rb_node_dot2_t *n = NODE_NEWNODE(NODE_DOT2, rb_node_dot2_t, loc);
    n->nd_beg = nd_beg;
    n->nd_end = nd_end;

    return n;
}

static rb_node_dot3_t *
rb_node_dot3_new(struct parser_params *p, NODE *nd_beg, NODE *nd_end, const YYLTYPE *loc)
{
    rb_node_dot3_t *n = NODE_NEWNODE(NODE_DOT3, rb_node_dot3_t, loc);
    n->nd_beg = nd_beg;
    n->nd_end = nd_end;

    return n;
}

static rb_node_self_t *
rb_node_self_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_self_t *n = NODE_NEWNODE(NODE_SELF, rb_node_self_t, loc);
    n->nd_state = 1;

    return n;
}

static rb_node_nil_t *
rb_node_nil_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_nil_t *n = NODE_NEWNODE(NODE_NIL, rb_node_nil_t, loc);

    return n;
}

static rb_node_true_t *
rb_node_true_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_true_t *n = NODE_NEWNODE(NODE_TRUE, rb_node_true_t, loc);

    return n;
}

static rb_node_false_t *
rb_node_false_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_false_t *n = NODE_NEWNODE(NODE_FALSE, rb_node_false_t, loc);

    return n;
}

static rb_node_super_t *
rb_node_super_new(struct parser_params *p, NODE *nd_args, const YYLTYPE *loc)
{
    rb_node_super_t *n = NODE_NEWNODE(NODE_SUPER, rb_node_super_t, loc);
    n->nd_args = nd_args;

    return n;
}

static rb_node_zsuper_t *
rb_node_zsuper_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_zsuper_t *n = NODE_NEWNODE(NODE_ZSUPER, rb_node_zsuper_t, loc);

    return n;
}

static rb_node_match2_t *
rb_node_match2_new(struct parser_params *p, NODE *nd_recv, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_match2_t *n = NODE_NEWNODE(NODE_MATCH2, rb_node_match2_t, loc);
    n->nd_recv = nd_recv;
    n->nd_value = nd_value;
    n->nd_args = 0;

    return n;
}

static rb_node_match3_t *
rb_node_match3_new(struct parser_params *p, NODE *nd_recv, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_match3_t *n = NODE_NEWNODE(NODE_MATCH3, rb_node_match3_t, loc);
    n->nd_recv = nd_recv;
    n->nd_value = nd_value;

    return n;
}

/* TODO: Use union for NODE_LIST2 */
static rb_node_list_t *
rb_node_list_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc)
{
    rb_node_list_t *n = NODE_NEWNODE(NODE_LIST, rb_node_list_t, loc);
    n->nd_head = nd_head;
    n->as.nd_alen = 1;
    n->nd_next = 0;

    return n;
}

static rb_node_list_t *
rb_node_list_new2(struct parser_params *p, NODE *nd_head, long nd_alen, NODE *nd_next, const YYLTYPE *loc)
{
    rb_node_list_t *n = NODE_NEWNODE(NODE_LIST, rb_node_list_t, loc);
    n->nd_head = nd_head;
    n->as.nd_alen = nd_alen;
    n->nd_next = nd_next;

    return n;
}

static rb_node_zlist_t *
rb_node_zlist_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_zlist_t *n = NODE_NEWNODE(NODE_ZLIST, rb_node_zlist_t, loc);

    return n;
}

static rb_node_hash_t *
rb_node_hash_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc)
{
    rb_node_hash_t *n = NODE_NEWNODE(NODE_HASH, rb_node_hash_t, loc);
    n->nd_head = nd_head;
    n->nd_brace = 0;

    return n;
}

static rb_node_masgn_t *
rb_node_masgn_new(struct parser_params *p, NODE *nd_head, NODE *nd_args, const YYLTYPE *loc)
{
    rb_node_masgn_t *n = NODE_NEWNODE(NODE_MASGN, rb_node_masgn_t, loc);
    n->nd_head = nd_head;
    n->nd_value = 0;
    n->nd_args = nd_args;

    return n;
}

static rb_node_gasgn_t *
rb_node_gasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_gasgn_t *n = NODE_NEWNODE(NODE_GASGN, rb_node_gasgn_t, loc);
    n->nd_vid = nd_vid;
    n->nd_value = nd_value;

    return n;
}

static rb_node_lasgn_t *
rb_node_lasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_lasgn_t *n = NODE_NEWNODE(NODE_LASGN, rb_node_lasgn_t, loc);
    n->nd_vid = nd_vid;
    n->nd_value = nd_value;

    return n;
}

static rb_node_dasgn_t *
rb_node_dasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_dasgn_t *n = NODE_NEWNODE(NODE_DASGN, rb_node_dasgn_t, loc);
    n->nd_vid = nd_vid;
    n->nd_value = nd_value;

    return n;
}

static rb_node_iasgn_t *
rb_node_iasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_iasgn_t *n = NODE_NEWNODE(NODE_IASGN, rb_node_iasgn_t, loc);
    n->nd_vid = nd_vid;
    n->nd_value = nd_value;

    return n;
}

static rb_node_cvasgn_t *
rb_node_cvasgn_new(struct parser_params *p, ID nd_vid, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_cvasgn_t *n = NODE_NEWNODE(NODE_CVASGN, rb_node_cvasgn_t, loc);
    n->nd_vid = nd_vid;
    n->nd_value = nd_value;

    return n;
}

static rb_node_op_asgn1_t *
rb_node_op_asgn1_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *index, NODE *rvalue, const YYLTYPE *loc)
{
    rb_node_op_asgn1_t *n = NODE_NEWNODE(NODE_OP_ASGN1, rb_node_op_asgn1_t, loc);
    n->nd_recv = nd_recv;
    n->nd_mid = nd_mid;
    n->nd_index = index;
    n->nd_rvalue = rvalue;

    return n;
}

static rb_node_op_asgn2_t *
rb_node_op_asgn2_new(struct parser_params *p, NODE *nd_recv, NODE *nd_value, ID nd_vid, ID nd_mid, bool nd_aid, const YYLTYPE *loc)
{
    rb_node_op_asgn2_t *n = NODE_NEWNODE(NODE_OP_ASGN2, rb_node_op_asgn2_t, loc);
    n->nd_recv = nd_recv;
    n->nd_value = nd_value;
    n->nd_vid = nd_vid;
    n->nd_mid = nd_mid;
    n->nd_aid = nd_aid;

    return n;
}

static rb_node_op_asgn_or_t *
rb_node_op_asgn_or_new(struct parser_params *p, NODE *nd_head, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_op_asgn_or_t *n = NODE_NEWNODE(NODE_OP_ASGN_OR, rb_node_op_asgn_or_t, loc);
    n->nd_head = nd_head;
    n->nd_value = nd_value;

    return n;
}

static rb_node_op_asgn_and_t *
rb_node_op_asgn_and_new(struct parser_params *p, NODE *nd_head, NODE *nd_value, const YYLTYPE *loc)
{
    rb_node_op_asgn_and_t *n = NODE_NEWNODE(NODE_OP_ASGN_AND, rb_node_op_asgn_and_t, loc);
    n->nd_head = nd_head;
    n->nd_value = nd_value;

    return n;
}

static rb_node_gvar_t *
rb_node_gvar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc)
{
    rb_node_gvar_t *n = NODE_NEWNODE(NODE_GVAR, rb_node_gvar_t, loc);
    n->nd_vid = nd_vid;

    return n;
}

static rb_node_lvar_t *
rb_node_lvar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc)
{
    rb_node_lvar_t *n = NODE_NEWNODE(NODE_LVAR, rb_node_lvar_t, loc);
    n->nd_vid = nd_vid;

    return n;
}

static rb_node_dvar_t *
rb_node_dvar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc)
{
    rb_node_dvar_t *n = NODE_NEWNODE(NODE_DVAR, rb_node_dvar_t, loc);
    n->nd_vid = nd_vid;

    return n;
}

static rb_node_ivar_t *
rb_node_ivar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc)
{
    rb_node_ivar_t *n = NODE_NEWNODE(NODE_IVAR, rb_node_ivar_t, loc);
    n->nd_vid = nd_vid;

    return n;
}

static rb_node_const_t *
rb_node_const_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc)
{
    rb_node_const_t *n = NODE_NEWNODE(NODE_CONST, rb_node_const_t, loc);
    n->nd_vid = nd_vid;

    return n;
}

static rb_node_cvar_t *
rb_node_cvar_new(struct parser_params *p, ID nd_vid, const YYLTYPE *loc)
{
    rb_node_cvar_t *n = NODE_NEWNODE(NODE_CVAR, rb_node_cvar_t, loc);
    n->nd_vid = nd_vid;

    return n;
}

static rb_node_nth_ref_t *
rb_node_nth_ref_new(struct parser_params *p, long nd_nth, const YYLTYPE *loc)
{
    rb_node_nth_ref_t *n = NODE_NEWNODE(NODE_NTH_REF, rb_node_nth_ref_t, loc);
    n->nd_nth = nd_nth;

    return n;
}

static rb_node_back_ref_t *
rb_node_back_ref_new(struct parser_params *p, long nd_nth, const YYLTYPE *loc)
{
    rb_node_back_ref_t *n = NODE_NEWNODE(NODE_BACK_REF, rb_node_back_ref_t, loc);
    n->nd_nth = nd_nth;

    return n;
}

static rb_node_lit_t *
rb_node_lit_new(struct parser_params *p, VALUE nd_lit, const YYLTYPE *loc)
{
    rb_node_lit_t *n = NODE_NEWNODE(NODE_LIT, rb_node_lit_t, loc);
    n->nd_lit = nd_lit;

    return n;
}

static rb_node_str_t *
rb_node_str_new(struct parser_params *p, VALUE nd_lit, const YYLTYPE *loc)
{
    rb_node_str_t *n = NODE_NEWNODE(NODE_STR, rb_node_str_t, loc);
    n->nd_lit = nd_lit;

    return n;
}

/* TODO; Use union for NODE_DSTR2 */
static rb_node_dstr_t *
rb_node_dstr_new0(struct parser_params *p, VALUE nd_lit, long nd_alen, NODE *nd_next, const YYLTYPE *loc)
{
    rb_node_dstr_t *n = NODE_NEWNODE(NODE_DSTR, rb_node_dstr_t, loc);
    n->nd_lit = nd_lit;
    n->as.nd_alen = nd_alen;
    n->nd_next = (rb_node_list_t *)nd_next;

    return n;
}

static rb_node_dstr_t *
rb_node_dstr_new(struct parser_params *p, VALUE nd_lit, const YYLTYPE *loc)
{
    return rb_node_dstr_new0(p, nd_lit, 1, 0, loc);
}

static rb_node_xstr_t *
rb_node_xstr_new(struct parser_params *p, VALUE nd_lit, const YYLTYPE *loc)
{
    rb_node_xstr_t *n = NODE_NEWNODE(NODE_XSTR, rb_node_xstr_t, loc);
    n->nd_lit = nd_lit;

    return n;
}

static rb_node_dxstr_t *
rb_node_dxstr_new(struct parser_params *p, VALUE nd_lit, long nd_alen, NODE *nd_next, const YYLTYPE *loc)
{
    rb_node_dxstr_t *n = NODE_NEWNODE(NODE_DXSTR, rb_node_dxstr_t, loc);
    n->nd_lit = nd_lit;
    n->nd_alen = nd_alen;
    n->nd_next = (rb_node_list_t *)nd_next;

    return n;
}

static rb_node_dsym_t *
rb_node_dsym_new(struct parser_params *p, VALUE nd_lit, long nd_alen, NODE *nd_next, const YYLTYPE *loc)
{
    rb_node_dsym_t *n = NODE_NEWNODE(NODE_DSYM, rb_node_dsym_t, loc);
    n->nd_lit = nd_lit;
    n->nd_alen = nd_alen;
    n->nd_next = (rb_node_list_t *)nd_next;

    return n;
}

static rb_node_evstr_t *
rb_node_evstr_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_evstr_t *n = NODE_NEWNODE(NODE_EVSTR, rb_node_evstr_t, loc);
    n->nd_body = nd_body;

    return n;
}

static rb_node_call_t *
rb_node_call_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_args, const YYLTYPE *loc)
{
    rb_node_call_t *n = NODE_NEWNODE(NODE_CALL, rb_node_call_t, loc);
    n->nd_recv = nd_recv;
    n->nd_mid = nd_mid;
    n->nd_args = nd_args;

    return n;
}

static rb_node_opcall_t *
rb_node_opcall_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_args, const YYLTYPE *loc)
{
    rb_node_opcall_t *n = NODE_NEWNODE(NODE_OPCALL, rb_node_opcall_t, loc);
    n->nd_recv = nd_recv;
    n->nd_mid = nd_mid;
    n->nd_args = nd_args;

    return n;
}

static rb_node_fcall_t *
rb_node_fcall_new(struct parser_params *p, ID nd_mid, NODE *nd_args, const YYLTYPE *loc)
{
    rb_node_fcall_t *n = NODE_NEWNODE(NODE_FCALL, rb_node_fcall_t, loc);
    n->nd_mid = nd_mid;
    n->nd_args = nd_args;

    return n;
}

static rb_node_qcall_t *
rb_node_qcall_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_args, const YYLTYPE *loc)
{
    rb_node_qcall_t *n = NODE_NEWNODE(NODE_QCALL, rb_node_qcall_t, loc);
    n->nd_recv = nd_recv;
    n->nd_mid = nd_mid;
    n->nd_args = nd_args;

    return n;
}

static rb_node_vcall_t *
rb_node_vcall_new(struct parser_params *p, ID nd_mid, const YYLTYPE *loc)
{
    rb_node_vcall_t *n = NODE_NEWNODE(NODE_VCALL, rb_node_vcall_t, loc);
    n->nd_mid = nd_mid;

    return n;
}

static rb_node_once_t *
rb_node_once_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_once_t *n = NODE_NEWNODE(NODE_ONCE, rb_node_once_t, loc);
    n->nd_body = nd_body;

    return n;
}

static rb_node_args_t *
rb_node_args_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_args_t *n = NODE_NEWNODE(NODE_ARGS, rb_node_args_t, loc);
    MEMZERO(&n->nd_ainfo, struct rb_args_info, 1);

    return n;
}

static rb_node_args_aux_t *
rb_node_args_aux_new(struct parser_params *p, ID nd_pid, long nd_plen, const YYLTYPE *loc)
{
    rb_node_args_aux_t *n = NODE_NEWNODE(NODE_ARGS_AUX, rb_node_args_aux_t, loc);
    n->nd_pid = nd_pid;
    n->nd_plen = nd_plen;
    n->nd_next = 0;

    return n;
}

static rb_node_opt_arg_t *
rb_node_opt_arg_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_opt_arg_t *n = NODE_NEWNODE(NODE_OPT_ARG, rb_node_opt_arg_t, loc);
    n->nd_body = nd_body;
    n->nd_next = 0;

    return n;
}

static rb_node_kw_arg_t *
rb_node_kw_arg_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_kw_arg_t *n = NODE_NEWNODE(NODE_KW_ARG, rb_node_kw_arg_t, loc);
    n->nd_body = nd_body;
    n->nd_next = 0;

    return n;
}

static rb_node_postarg_t *
rb_node_postarg_new(struct parser_params *p, NODE *nd_1st, NODE *nd_2nd, const YYLTYPE *loc)
{
    rb_node_postarg_t *n = NODE_NEWNODE(NODE_POSTARG, rb_node_postarg_t, loc);
    n->nd_1st = nd_1st;
    n->nd_2nd = nd_2nd;

    return n;
}

static rb_node_argscat_t *
rb_node_argscat_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_argscat_t *n = NODE_NEWNODE(NODE_ARGSCAT, rb_node_argscat_t, loc);
    n->nd_head = nd_head;
    n->nd_body = nd_body;

    return n;
}

static rb_node_argspush_t *
rb_node_argspush_new(struct parser_params *p, NODE *nd_head, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_argspush_t *n = NODE_NEWNODE(NODE_ARGSPUSH, rb_node_argspush_t, loc);
    n->nd_head = nd_head;
    n->nd_body = nd_body;

    return n;
}

static rb_node_splat_t *
rb_node_splat_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc)
{
    rb_node_splat_t *n = NODE_NEWNODE(NODE_SPLAT, rb_node_splat_t, loc);
    n->nd_head = nd_head;

    return n;
}

static rb_node_block_pass_t *
rb_node_block_pass_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_block_pass_t *n = NODE_NEWNODE(NODE_BLOCK_PASS, rb_node_block_pass_t, loc);
    n->nd_head = 0;
    n->nd_body = nd_body;

    return n;
}

static rb_node_alias_t *
rb_node_alias_new(struct parser_params *p, NODE *nd_1st, NODE *nd_2nd, const YYLTYPE *loc)
{
    rb_node_alias_t *n = NODE_NEWNODE(NODE_ALIAS, rb_node_alias_t, loc);
    n->nd_1st = nd_1st;
    n->nd_2nd = nd_2nd;

    return n;
}

static rb_node_valias_t *
rb_node_valias_new(struct parser_params *p, ID nd_alias, ID nd_orig, const YYLTYPE *loc)
{
    rb_node_valias_t *n = NODE_NEWNODE(NODE_VALIAS, rb_node_valias_t, loc);
    n->nd_alias = nd_alias;
    n->nd_orig = nd_orig;

    return n;
}

static rb_node_undef_t *
rb_node_undef_new(struct parser_params *p, NODE *nd_undef, const YYLTYPE *loc)
{
    rb_node_undef_t *n = NODE_NEWNODE(NODE_UNDEF, rb_node_undef_t, loc);
    n->nd_undef = nd_undef;

    return n;
}

static rb_node_errinfo_t *
rb_node_errinfo_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_errinfo_t *n = NODE_NEWNODE(NODE_ERRINFO, rb_node_errinfo_t, loc);

    return n;
}

static rb_node_defined_t *
rb_node_defined_new(struct parser_params *p, NODE *nd_head, const YYLTYPE *loc)
{
    rb_node_defined_t *n = NODE_NEWNODE(NODE_DEFINED, rb_node_defined_t, loc);
    n->nd_head = nd_head;

    return n;
}

static rb_node_postexe_t *
rb_node_postexe_new(struct parser_params *p, NODE *nd_body, const YYLTYPE *loc)
{
    rb_node_postexe_t *n = NODE_NEWNODE(NODE_POSTEXE, rb_node_postexe_t, loc);
    n->nd_body = nd_body;

    return n;
}

static rb_node_attrasgn_t *
rb_node_attrasgn_new(struct parser_params *p, NODE *nd_recv, ID nd_mid, NODE *nd_args, const YYLTYPE *loc)
{
    rb_node_attrasgn_t *n = NODE_NEWNODE(NODE_ATTRASGN, rb_node_attrasgn_t, loc);
    n->nd_recv = nd_recv;
    n->nd_mid = nd_mid;
    n->nd_args = nd_args;

    return n;
}

static rb_node_aryptn_t *
rb_node_aryptn_new(struct parser_params *p, NODE *pre_args, NODE *rest_arg, NODE *post_args, const YYLTYPE *loc)
{
    rb_node_aryptn_t *n = NODE_NEWNODE(NODE_ARYPTN, rb_node_aryptn_t, loc);
    n->nd_pconst = 0;
    n->pre_args = pre_args;
    n->rest_arg = rest_arg;
    n->post_args = post_args;

    return n;
}

static rb_node_hshptn_t *
rb_node_hshptn_new(struct parser_params *p, NODE *nd_pconst, NODE *nd_pkwargs, NODE *nd_pkwrestarg, const YYLTYPE *loc)
{
    rb_node_hshptn_t *n = NODE_NEWNODE(NODE_HSHPTN, rb_node_hshptn_t, loc);
    n->nd_pconst = nd_pconst;
    n->nd_pkwargs = nd_pkwargs;
    n->nd_pkwrestarg = nd_pkwrestarg;

    return n;
}

static rb_node_fndptn_t *
rb_node_fndptn_new(struct parser_params *p, NODE *pre_rest_arg, NODE *args, NODE *post_rest_arg, const YYLTYPE *loc)
{
    rb_node_fndptn_t *n = NODE_NEWNODE(NODE_FNDPTN, rb_node_fndptn_t, loc);
    n->nd_pconst = 0;
    n->pre_rest_arg = pre_rest_arg;
    n->args = args;
    n->post_rest_arg = post_rest_arg;

    return n;
}

static rb_node_cdecl_t *
rb_node_cdecl_new(struct parser_params *p, ID nd_vid, NODE *nd_value, NODE *nd_else, const YYLTYPE *loc)
{
    rb_node_cdecl_t *n = NODE_NEWNODE(NODE_CDECL, rb_node_cdecl_t, loc);
    n->nd_vid = nd_vid;
    n->nd_value = nd_value;
    n->nd_else = nd_else;

    return n;
}

static rb_node_op_cdecl_t *
rb_node_op_cdecl_new(struct parser_params *p, NODE *nd_head, NODE *nd_value, ID nd_aid, const YYLTYPE *loc)
{
    rb_node_op_cdecl_t *n = NODE_NEWNODE(NODE_OP_CDECL, rb_node_op_cdecl_t, loc);
    n->nd_head = nd_head;
    n->nd_value = nd_value;
    n->nd_aid = nd_aid;

    return n;
}

static rb_node_error_t *
rb_node_error_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_error_t *n = NODE_NEWNODE(NODE_ERROR, rb_node_error_t, loc);

    return n;
}

#else

static rb_node_ripper_t *
rb_node_ripper_new(struct parser_params *p, ID nd_vid, VALUE nd_rval, VALUE nd_cval, const YYLTYPE *loc)
{
    rb_node_ripper_t *n = NODE_NEWNODE(NODE_RIPPER, rb_node_ripper_t, loc);
    n->nd_vid = nd_vid;
    n->nd_rval = nd_rval;
    n->nd_cval = nd_cval;

    return n;
}

static rb_node_ripper_values_t *
rb_node_ripper_values_new(struct parser_params *p, VALUE nd_val1, VALUE nd_val2, VALUE nd_val3, const YYLTYPE *loc)
{
    rb_node_ripper_values_t *n = NODE_NEWNODE(NODE_RIPPER_VALUES, rb_node_ripper_values_t, loc);
    n->nd_val1 = nd_val1;
    n->nd_val2 = nd_val2;
    n->nd_val3 = nd_val3;

    return n;
}

#endif

static rb_node_break_t *
rb_node_break_new(struct parser_params *p, NODE *nd_stts, const YYLTYPE *loc)
{
    rb_node_break_t *n = NODE_NEWNODE(NODE_BREAK, rb_node_break_t, loc);
    n->nd_stts = nd_stts;
    n->nd_chain = 0;

    return n;
}

static rb_node_next_t *
rb_node_next_new(struct parser_params *p, NODE *nd_stts, const YYLTYPE *loc)
{
    rb_node_next_t *n = NODE_NEWNODE(NODE_NEXT, rb_node_next_t, loc);
    n->nd_stts = nd_stts;
    n->nd_chain = 0;

    return n;
}

static rb_node_redo_t *
rb_node_redo_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_redo_t *n = NODE_NEWNODE(NODE_REDO, rb_node_redo_t, loc);
    n->nd_chain = 0;

    return n;
}

static rb_node_def_temp_t *
rb_node_def_temp_new(struct parser_params *p, const YYLTYPE *loc)
{
    rb_node_def_temp_t *n = NODE_NEWNODE((enum node_type)NODE_DEF_TEMP, rb_node_def_temp_t, loc);
    n->save.cur_arg = p->cur_arg;
    n->save.numparam_save = 0;
    n->save.max_numparam = 0;
    n->save.ctxt = p->ctxt;
#ifdef RIPPER
    n->nd_recv = Qnil;
    n->nd_mid = Qnil;
    n->dot_or_colon = Qnil;
#else
    n->nd_def = 0;
    n->nd_mid = 0;
#endif

    return n;
}

static rb_node_def_temp_t *
def_head_save(struct parser_params *p, rb_node_def_temp_t *n)
{
    n->save.numparam_save = numparam_push(p);
    n->save.max_numparam = p->max_numparam;
    return n;
}

#ifndef RIPPER
static enum node_type
nodetype(NODE *node)			/* for debug */
{
    return (enum node_type)nd_type(node);
}

static int
nodeline(NODE *node)
{
    return nd_line(node);
}

static NODE*
newline_node(NODE *node)
{
    if (node) {
        node = remove_begin(node);
        nd_set_fl_newline(node);
    }
    return node;
}

static void
fixpos(NODE *node, NODE *orig)
{
    if (!node) return;
    if (!orig) return;
    nd_set_line(node, nd_line(orig));
}

static void
parser_warning(struct parser_params *p, NODE *node, const char *mesg)
{
    rb_compile_warning(p->ruby_sourcefile, nd_line(node), "%s", mesg);
}

static void
parser_warn(struct parser_params *p, NODE *node, const char *mesg)
{
    rb_compile_warn(p->ruby_sourcefile, nd_line(node), "%s", mesg);
}

static NODE*
block_append(struct parser_params *p, NODE *head, NODE *tail)
{
    NODE *end, *h = head, *nd;

    if (tail == 0) return head;

    if (h == 0) return tail;
    switch (nd_type(h)) {
      default:
        h = end = NEW_BLOCK(head, &head->nd_loc);
        RNODE_BLOCK(end)->nd_end = end;
        head = end;
        break;
      case NODE_BLOCK:
        end = RNODE_BLOCK(h)->nd_end;
        break;
    }

    nd = RNODE_BLOCK(end)->nd_head;
    switch (nd_type(nd)) {
      case NODE_RETURN:
      case NODE_BREAK:
      case NODE_NEXT:
      case NODE_REDO:
      case NODE_RETRY:
        if (RTEST(ruby_verbose)) {
            parser_warning(p, tail, "statement not reached");
        }
        break;

      default:
        break;
    }

    if (!nd_type_p(tail, NODE_BLOCK)) {
        tail = NEW_BLOCK(tail, &tail->nd_loc);
        RNODE_BLOCK(tail)->nd_end = tail;
    }
    RNODE_BLOCK(end)->nd_next = tail;
    RNODE_BLOCK(h)->nd_end = RNODE_BLOCK(tail)->nd_end;
    nd_set_last_loc(head, nd_last_loc(tail));
    return head;
}

/* append item to the list */
static NODE*
list_append(struct parser_params *p, NODE *list, NODE *item)
{
    NODE *last;

    if (list == 0) return NEW_LIST(item, &item->nd_loc);
    if (RNODE_LIST(list)->nd_next) {
        last = RNODE_LIST(RNODE_LIST(list)->nd_next)->as.nd_end;
    }
    else {
        last = list;
    }

    RNODE_LIST(list)->as.nd_alen += 1;
    RNODE_LIST(last)->nd_next = NEW_LIST(item, &item->nd_loc);
    RNODE_LIST(RNODE_LIST(list)->nd_next)->as.nd_end = RNODE_LIST(last)->nd_next;

    nd_set_last_loc(list, nd_last_loc(item));

    return list;
}

/* concat two lists */
static NODE*
list_concat(NODE *head, NODE *tail)
{
    NODE *last;

    if (RNODE_LIST(head)->nd_next) {
        last = RNODE_LIST(RNODE_LIST(head)->nd_next)->as.nd_end;
    }
    else {
        last = head;
    }

    RNODE_LIST(head)->as.nd_alen += RNODE_LIST(tail)->as.nd_alen;
    RNODE_LIST(last)->nd_next = tail;
    if (RNODE_LIST(tail)->nd_next) {
        RNODE_LIST(RNODE_LIST(head)->nd_next)->as.nd_end = RNODE_LIST(RNODE_LIST(tail)->nd_next)->as.nd_end;
    }
    else {
        RNODE_LIST(RNODE_LIST(head)->nd_next)->as.nd_end = tail;
    }

    nd_set_last_loc(head, nd_last_loc(tail));

    return head;
}

static int
literal_concat0(struct parser_params *p, VALUE head, VALUE tail)
{
    if (NIL_P(tail)) return 1;
    if (!rb_enc_compatible(head, tail)) {
        compile_error(p, "string literal encodings differ (%s / %s)",
                      rb_enc_name(rb_enc_get(head)),
                      rb_enc_name(rb_enc_get(tail)));
        rb_str_resize(head, 0);
        rb_str_resize(tail, 0);
        return 0;
    }
    rb_str_buf_append(head, tail);
    return 1;
}

static VALUE
string_literal_head(struct parser_params *p, enum node_type htype, NODE *head)
{
    if (htype != NODE_DSTR) return Qfalse;
    if (RNODE_DSTR(head)->nd_next) {
        head = RNODE_LIST(RNODE_LIST(RNODE_DSTR(head)->nd_next)->as.nd_end)->nd_head;
        if (!head || !nd_type_p(head, NODE_STR)) return Qfalse;
    }
    const VALUE lit = RNODE_DSTR(head)->nd_lit;
    ASSUME(lit != Qfalse);
    return lit;
}

/* concat two string literals */
static NODE *
literal_concat(struct parser_params *p, NODE *head, NODE *tail, const YYLTYPE *loc)
{
    enum node_type htype;
    VALUE lit;

    if (!head) return tail;
    if (!tail) return head;

    htype = nd_type(head);
    if (htype == NODE_EVSTR) {
        head = new_dstr(p, head, loc);
        htype = NODE_DSTR;
    }
    if (p->heredoc_indent > 0) {
        switch (htype) {
          case NODE_STR:
            head = str2dstr(p, head);
          case NODE_DSTR:
            return list_append(p, head, tail);
          default:
            break;
        }
    }
    switch (nd_type(tail)) {
      case NODE_STR:
        if ((lit = string_literal_head(p, htype, head)) != Qfalse) {
            htype = NODE_STR;
        }
        else {
            lit = RNODE_DSTR(head)->nd_lit;
        }
        if (htype == NODE_STR) {
            if (!literal_concat0(p, lit, RNODE_STR(tail)->nd_lit)) {
              error:
                rb_discard_node(p, head);
                rb_discard_node(p, tail);
                return 0;
            }
            rb_discard_node(p, tail);
        }
        else {
            list_append(p, head, tail);
        }
        break;

      case NODE_DSTR:
        if (htype == NODE_STR) {
            if (!literal_concat0(p, RNODE_STR(head)->nd_lit, RNODE_DSTR(tail)->nd_lit))
                goto error;
            RNODE_DSTR(tail)->nd_lit = RNODE_STR(head)->nd_lit;
            rb_discard_node(p, head);
            head = tail;
        }
        else if (NIL_P(RNODE_DSTR(tail)->nd_lit)) {
          append:
            RNODE_DSTR(head)->as.nd_alen += RNODE_DSTR(tail)->as.nd_alen - 1;
            if (!RNODE_DSTR(head)->nd_next) {
                RNODE_DSTR(head)->nd_next = RNODE_DSTR(tail)->nd_next;
            }
            else if (RNODE_DSTR(tail)->nd_next) {
                RNODE_DSTR(RNODE_DSTR(RNODE_DSTR(head)->nd_next)->as.nd_end)->nd_next = RNODE_DSTR(tail)->nd_next;
                RNODE_DSTR(RNODE_DSTR(head)->nd_next)->as.nd_end = RNODE_DSTR(RNODE_DSTR(tail)->nd_next)->as.nd_end;
            }
            rb_discard_node(p, tail);
        }
        else if ((lit = string_literal_head(p, htype, head)) != Qfalse) {
            if (!literal_concat0(p, lit, RNODE_DSTR(tail)->nd_lit))
                goto error;
            RNODE_DSTR(tail)->nd_lit = Qnil;
            goto append;
        }
        else {
            list_concat(head, NEW_LIST2(NEW_STR(RNODE_DSTR(tail)->nd_lit, loc), RNODE_DSTR(tail)->as.nd_alen, (NODE *)RNODE_DSTR(tail)->nd_next, loc));
        }
        break;

      case NODE_EVSTR:
        if (htype == NODE_STR) {
            head = str2dstr(p, head);
            RNODE_DSTR(head)->as.nd_alen = 1;
        }
        list_append(p, head, tail);
        break;
    }
    return head;
}

static void
nd_copy_flag(NODE *new_node, NODE *old_node)
{
    if (nd_fl_newline(old_node)) nd_set_fl_newline(new_node);
    nd_set_line(new_node, nd_line(old_node));
    new_node->nd_loc = old_node->nd_loc;
    new_node->node_id = old_node->node_id;
}

static NODE *
str2dstr(struct parser_params *p, NODE *node)
{
    NODE *new_node = (NODE *)NODE_NEW_INTERNAL(NODE_DSTR, rb_node_dstr_t);
    nd_copy_flag(new_node, node);
    RNODE_DSTR(new_node)->nd_lit = RNODE_STR(node)->nd_lit;
    RNODE_DSTR(new_node)->as.nd_alen = 0;
    RNODE_DSTR(new_node)->nd_next = 0;
    RNODE_STR(node)->nd_lit = 0;

    return new_node;
}

static NODE *
evstr2dstr(struct parser_params *p, NODE *node)
{
    if (nd_type_p(node, NODE_EVSTR)) {
        node = new_dstr(p, node, &node->nd_loc);
    }
    return node;
}

static NODE *
new_evstr(struct parser_params *p, NODE *node, const YYLTYPE *loc)
{
    NODE *head = node;

    if (node) {
        switch (nd_type(node)) {
          case NODE_STR:
            return str2dstr(p, node);
          case NODE_DSTR:
            break;
          case NODE_EVSTR:
            return node;
        }
    }
    return NEW_EVSTR(head, loc);
}

static NODE *
new_dstr(struct parser_params *p, NODE *node, const YYLTYPE *loc)
{
    VALUE lit = STR_NEW0();
    NODE *dstr = NEW_DSTR(lit, loc);
    RB_OBJ_WRITTEN(p->ast, Qnil, lit);
    return list_append(p, dstr, node);
}

static NODE *
call_bin_op(struct parser_params *p, NODE *recv, ID id, NODE *arg1,
                const YYLTYPE *op_loc, const YYLTYPE *loc)
{
    NODE *expr;
    value_expr(recv);
    value_expr(arg1);
    expr = NEW_OPCALL(recv, id, NEW_LIST(arg1, &arg1->nd_loc), loc);
    nd_set_line(expr, op_loc->beg_pos.lineno);
    return expr;
}

static NODE *
call_uni_op(struct parser_params *p, NODE *recv, ID id, const YYLTYPE *op_loc, const YYLTYPE *loc)
{
    NODE *opcall;
    value_expr(recv);
    opcall = NEW_OPCALL(recv, id, 0, loc);
    nd_set_line(opcall, op_loc->beg_pos.lineno);
    return opcall;
}

static NODE *
new_qcall(struct parser_params* p, ID atype, NODE *recv, ID mid, NODE *args, const YYLTYPE *op_loc, const YYLTYPE *loc)
{
    NODE *qcall = NEW_QCALL(atype, recv, mid, args, loc);
    nd_set_line(qcall, op_loc->beg_pos.lineno);
    return qcall;
}

static NODE*
new_command_qcall(struct parser_params* p, ID atype, NODE *recv, ID mid, NODE *args, NODE *block, const YYLTYPE *op_loc, const YYLTYPE *loc)
{
    NODE *ret;
    if (block) block_dup_check(p, args, block);
    ret = new_qcall(p, atype, recv, mid, args, op_loc, loc);
    if (block) ret = method_add_block(p, ret, block, loc);
    fixpos(ret, recv);
    return ret;
}

#define nd_once_body(node) (nd_type_p((node), NODE_ONCE) ? RNODE_ONCE(node)->nd_body : node)

static NODE*
last_expr_once_body(NODE *node)
{
    if (!node) return 0;
    return nd_once_body(node);
}

static NODE*
match_op(struct parser_params *p, NODE *node1, NODE *node2, const YYLTYPE *op_loc, const YYLTYPE *loc)
{
    NODE *n;
    int line = op_loc->beg_pos.lineno;

    value_expr(node1);
    value_expr(node2);

    if ((n = last_expr_once_body(node1)) != 0) {
        switch (nd_type(n)) {
          case NODE_DREGX:
            {
                NODE *match = NEW_MATCH2(node1, node2, loc);
                nd_set_line(match, line);
                return match;
            }

          case NODE_LIT:
            if (RB_TYPE_P(RNODE_LIT(n)->nd_lit, T_REGEXP)) {
                const VALUE lit = RNODE_LIT(n)->nd_lit;
                NODE *match = NEW_MATCH2(node1, node2, loc);
                RNODE_MATCH2(match)->nd_args = reg_named_capture_assign(p, lit, loc);
                nd_set_line(match, line);
                return match;
            }
        }
    }

    if ((n = last_expr_once_body(node2)) != 0) {
        NODE *match3;

        switch (nd_type(n)) {
          case NODE_LIT:
            if (!RB_TYPE_P(RNODE_LIT(n)->nd_lit, T_REGEXP)) break;
            /* fallthru */
          case NODE_DREGX:
            match3 = NEW_MATCH3(node2, node1, loc);
            return match3;
        }
    }

    n = NEW_CALL(node1, tMATCH, NEW_LIST(node2, &node2->nd_loc), loc);
    nd_set_line(n, line);
    return n;
}

# if WARN_PAST_SCOPE
static int
past_dvar_p(struct parser_params *p, ID id)
{
    struct vtable *past = p->lvtbl->past;
    while (past) {
        if (vtable_included(past, id)) return 1;
        past = past->prev;
    }
    return 0;
}
# endif

static int
numparam_nested_p(struct parser_params *p)
{
    struct local_vars *local = p->lvtbl;
    NODE *outer = local->numparam.outer;
    NODE *inner = local->numparam.inner;
    if (outer || inner) {
        NODE *used = outer ? outer : inner;
        compile_error(p, "numbered parameter is already used in\n"
                      "%s:%d: %s block here",
                      p->ruby_sourcefile, nd_line(used),
                      outer ? "outer" : "inner");
        parser_show_error_line(p, &used->nd_loc);
        return 1;
    }
    return 0;
}

static NODE*
gettable(struct parser_params *p, ID id, const YYLTYPE *loc)
{
    ID *vidp = NULL;
    NODE *node;
    switch (id) {
      case keyword_self:
        return NEW_SELF(loc);
      case keyword_nil:
        return NEW_NIL(loc);
      case keyword_true:
        return NEW_TRUE(loc);
      case keyword_false:
        return NEW_FALSE(loc);
      case keyword__FILE__:
        {
            VALUE file = p->ruby_sourcefile_string;
            if (NIL_P(file))
                file = rb_str_new(0, 0);
            else
                file = rb_str_dup(file);
            node = NEW_STR(file, loc);
            RB_OBJ_WRITTEN(p->ast, Qnil, file);
        }
        return node;
      case keyword__LINE__:
        return NEW_LIT(INT2FIX(loc->beg_pos.lineno), loc);
      case keyword__ENCODING__:
        node = NEW_LIT(rb_enc_from_encoding(p->enc), loc);
        RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_LIT(node)->nd_lit);
        return node;

    }
    switch (id_type(id)) {
      case ID_LOCAL:
        if (dyna_in_block(p) && dvar_defined_ref(p, id, &vidp)) {
            if (NUMPARAM_ID_P(id) && numparam_nested_p(p)) return 0;
            if (id == p->cur_arg) {
                compile_error(p, "circular argument reference - %"PRIsWARN, rb_id2str(id));
                return 0;
            }
            if (vidp) *vidp |= LVAR_USED;
            node = NEW_DVAR(id, loc);
            return node;
        }
        if (local_id_ref(p, id, &vidp)) {
            if (id == p->cur_arg) {
                compile_error(p, "circular argument reference - %"PRIsWARN, rb_id2str(id));
                return 0;
            }
            if (vidp) *vidp |= LVAR_USED;
            node = NEW_LVAR(id, loc);
            return node;
        }
        if (dyna_in_block(p) && NUMPARAM_ID_P(id) &&
            parser_numbered_param(p, NUMPARAM_ID_TO_IDX(id))) {
            if (numparam_nested_p(p)) return 0;
            node = NEW_DVAR(id, loc);
            struct local_vars *local = p->lvtbl;
            if (!local->numparam.current) local->numparam.current = node;
            return node;
        }
# if WARN_PAST_SCOPE
        if (!p->ctxt.in_defined && RTEST(ruby_verbose) && past_dvar_p(p, id)) {
            rb_warning1("possible reference to past scope - %"PRIsWARN, rb_id2str(id));
        }
# endif
        /* method call without arguments */
        if (dyna_in_block(p) && id == rb_intern("it")
            && !(DVARS_TERMINAL_P(p->lvtbl->args) || DVARS_TERMINAL_P(p->lvtbl->args->prev))
            && p->max_numparam != ORDINAL_PARAM) {
            rb_warn0("`it` calls without arguments will refer to the first block param in Ruby 3.4; use it() or self.it");
        }
        return NEW_VCALL(id, loc);
      case ID_GLOBAL:
        return NEW_GVAR(id, loc);
      case ID_INSTANCE:
        return NEW_IVAR(id, loc);
      case ID_CONST:
        return NEW_CONST(id, loc);
      case ID_CLASS:
        return NEW_CVAR(id, loc);
    }
    compile_error(p, "identifier %"PRIsVALUE" is not valid to get", rb_id2str(id));
    return 0;
}

static rb_node_opt_arg_t *
opt_arg_append(rb_node_opt_arg_t *opt_list, rb_node_opt_arg_t *opt)
{
    rb_node_opt_arg_t *opts = opt_list;
    RNODE(opts)->nd_loc.end_pos = RNODE(opt)->nd_loc.end_pos;

    while (opts->nd_next) {
        opts = opts->nd_next;
        RNODE(opts)->nd_loc.end_pos = RNODE(opt)->nd_loc.end_pos;
    }
    opts->nd_next = opt;

    return opt_list;
}

static rb_node_kw_arg_t *
kwd_append(rb_node_kw_arg_t *kwlist, rb_node_kw_arg_t *kw)
{
    if (kwlist) {
        /* Assume rb_node_kw_arg_t and rb_node_opt_arg_t has same structure */
        opt_arg_append(RNODE_OPT_ARG(kwlist), RNODE_OPT_ARG(kw));
    }
    return kwlist;
}

static NODE *
new_defined(struct parser_params *p, NODE *expr, const YYLTYPE *loc)
{
    return NEW_DEFINED(remove_begin_all(expr), loc);
}

static NODE*
symbol_append(struct parser_params *p, NODE *symbols, NODE *symbol)
{
    enum node_type type = nd_type(symbol);
    switch (type) {
      case NODE_DSTR:
        nd_set_type(symbol, NODE_DSYM);
        break;
      case NODE_STR:
        nd_set_type(symbol, NODE_LIT);
        RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_LIT(symbol)->nd_lit = rb_str_intern(RNODE_LIT(symbol)->nd_lit));
        break;
      default:
        compile_error(p, "unexpected node as symbol: %s", parser_node_name(type));
    }
    return list_append(p, symbols, symbol);
}

static NODE *
new_regexp(struct parser_params *p, NODE *node, int options, const YYLTYPE *loc)
{
    struct RNode_LIST *list;
    NODE *prev;
    VALUE lit;

    if (!node) {
        node = NEW_LIT(reg_compile(p, STR_NEW0(), options), loc);
        RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_LIT(node)->nd_lit);
        return node;
    }
    switch (nd_type(node)) {
      case NODE_STR:
        {
            VALUE src = RNODE_STR(node)->nd_lit;
            nd_set_type(node, NODE_LIT);
            nd_set_loc(node, loc);
            RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_LIT(node)->nd_lit = reg_compile(p, src, options));
        }
        break;
      default:
        lit = STR_NEW0();
        node = NEW_DSTR0(lit, 1, NEW_LIST(node, loc), loc);
        RB_OBJ_WRITTEN(p->ast, Qnil, lit);
        /* fall through */
      case NODE_DSTR:
        nd_set_type(node, NODE_DREGX);
        nd_set_loc(node, loc);
        RNODE_DREGX(node)->nd_cflag = options & RE_OPTION_MASK;
        if (!NIL_P(RNODE_DREGX(node)->nd_lit)) reg_fragment_check(p, RNODE_DREGX(node)->nd_lit, options);
        for (list = RNODE_DREGX(prev = node)->nd_next; list; list = RNODE_LIST(list->nd_next)) {
            NODE *frag = list->nd_head;
            enum node_type type = nd_type(frag);
            if (type == NODE_STR || (type == NODE_DSTR && !RNODE_DSTR(frag)->nd_next)) {
                VALUE tail = RNODE_STR(frag)->nd_lit;
                if (reg_fragment_check(p, tail, options) && prev && !NIL_P(RNODE_DREGX(prev)->nd_lit)) {
                    VALUE lit = prev == node ? RNODE_DREGX(prev)->nd_lit : RNODE_LIT(RNODE_LIST(prev)->nd_head)->nd_lit;
                    if (!literal_concat0(p, lit, tail)) {
                        return NEW_NIL(loc); /* dummy node on error */
                    }
                    rb_str_resize(tail, 0);
                    RNODE_LIST(prev)->nd_next = list->nd_next;
                    rb_discard_node(p, list->nd_head);
                    rb_discard_node(p, (NODE *)list);
                    list = RNODE_LIST(prev);
                }
                else {
                    prev = (NODE *)list;
                }
            }
            else {
                prev = 0;
            }
        }
        if (!RNODE_DREGX(node)->nd_next) {
            VALUE src = RNODE_DREGX(node)->nd_lit;
            VALUE re = reg_compile(p, src, options);
            RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_DREGX(node)->nd_lit = re);
        }
        if (options & RE_OPTION_ONCE) {
            node = NEW_ONCE(node, loc);
        }
        break;
    }
    return node;
}

static rb_node_kw_arg_t *
new_kw_arg(struct parser_params *p, NODE *k, const YYLTYPE *loc)
{
    if (!k) return 0;
    return NEW_KW_ARG((k), loc);
}

static NODE *
new_xstring(struct parser_params *p, NODE *node, const YYLTYPE *loc)
{
    if (!node) {
        VALUE lit = STR_NEW0();
        NODE *xstr = NEW_XSTR(lit, loc);
        RB_OBJ_WRITTEN(p->ast, Qnil, lit);
        return xstr;
    }
    switch (nd_type(node)) {
      case NODE_STR:
        nd_set_type(node, NODE_XSTR);
        nd_set_loc(node, loc);
        break;
      case NODE_DSTR:
        nd_set_type(node, NODE_DXSTR);
        nd_set_loc(node, loc);
        break;
      default:
        node = NEW_DXSTR(Qnil, 1, NEW_LIST(node, loc), loc);
        break;
    }
    return node;
}

static void
check_literal_when(struct parser_params *p, NODE *arg, const YYLTYPE *loc)
{
    VALUE lit;

    if (!arg || !p->case_labels) return;

    lit = rb_node_case_when_optimizable_literal(arg);
    if (UNDEF_P(lit)) return;
    if (nd_type_p(arg, NODE_STR)) {
        RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_STR(arg)->nd_lit = lit);
    }

    if (NIL_P(p->case_labels)) {
        p->case_labels = rb_obj_hide(rb_hash_new());
    }
    else {
        VALUE line = rb_hash_lookup(p->case_labels, lit);
        if (!NIL_P(line)) {
            rb_warning1("duplicated `when' clause with line %d is ignored",
                        WARN_IVAL(line));
            return;
        }
    }
    rb_hash_aset(p->case_labels, lit, INT2NUM(p->ruby_sourceline));
}

#else  /* !RIPPER */
static int
id_is_var(struct parser_params *p, ID id)
{
    if (is_notop_id(id)) {
        switch (id & ID_SCOPE_MASK) {
          case ID_GLOBAL: case ID_INSTANCE: case ID_CONST: case ID_CLASS:
            return 1;
          case ID_LOCAL:
            if (dyna_in_block(p)) {
                if (NUMPARAM_ID_P(id) || dvar_defined(p, id)) return 1;
            }
            if (local_id(p, id)) return 1;
            /* method call without arguments */
            return 0;
        }
    }
    compile_error(p, "identifier %"PRIsVALUE" is not valid to get", rb_id2str(id));
    return 0;
}

static VALUE
new_regexp(struct parser_params *p, VALUE re, VALUE opt, const YYLTYPE *loc)
{
    VALUE src = 0, err = 0;
    int options = 0;
    if (ripper_is_node_yylval(p, re)) {
        src = RNODE_RIPPER(re)->nd_cval;
        re = RNODE_RIPPER(re)->nd_rval;
    }
    if (ripper_is_node_yylval(p, opt)) {
        options = (int)RNODE_RIPPER(opt)->nd_vid;
        opt = RNODE_RIPPER(opt)->nd_rval;
    }
    if (src && NIL_P(parser_reg_compile(p, src, options, &err))) {
        compile_error(p, "%"PRIsVALUE, err);
    }
    return dispatch2(regexp_literal, re, opt);
}
#endif /* !RIPPER */

static inline enum lex_state_e
parser_set_lex_state(struct parser_params *p, enum lex_state_e ls, int line)
{
    if (p->debug) {
        ls = rb_parser_trace_lex_state(p, p->lex.state, ls, line);
    }
    return p->lex.state = ls;
}

#ifndef RIPPER
static const char rb_parser_lex_state_names[][8] = {
    "BEG",    "END",    "ENDARG", "ENDFN",  "ARG",
    "CMDARG", "MID",    "FNAME",  "DOT",    "CLASS",
    "LABEL",  "LABELED","FITEM",
};

static VALUE
append_lex_state_name(struct parser_params *p, enum lex_state_e state, VALUE buf)
{
    int i, sep = 0;
    unsigned int mask = 1;
    static const char none[] = "NONE";

    for (i = 0; i < EXPR_MAX_STATE; ++i, mask <<= 1) {
        if ((unsigned)state & mask) {
            if (sep) {
                rb_str_cat(buf, "|", 1);
            }
            sep = 1;
            rb_str_cat_cstr(buf, rb_parser_lex_state_names[i]);
        }
    }
    if (!sep) {
        rb_str_cat(buf, none, sizeof(none)-1);
    }
    return buf;
}

static void
flush_debug_buffer(struct parser_params *p, VALUE out, VALUE str)
{
    VALUE mesg = p->debug_buffer;

    if (!NIL_P(mesg) && RSTRING_LEN(mesg)) {
        p->debug_buffer = Qnil;
        rb_io_puts(1, &mesg, out);
    }
    if (!NIL_P(str) && RSTRING_LEN(str)) {
        rb_io_write(p->debug_output, str);
    }
}

enum lex_state_e
rb_parser_trace_lex_state(struct parser_params *p, enum lex_state_e from,
                          enum lex_state_e to, int line)
{
    VALUE mesg;
    mesg = rb_str_new_cstr("lex_state: ");
    append_lex_state_name(p, from, mesg);
    rb_str_cat_cstr(mesg, " -> ");
    append_lex_state_name(p, to, mesg);
    rb_str_catf(mesg, " at line %d\n", line);
    flush_debug_buffer(p, p->debug_output, mesg);
    return to;
}

VALUE
rb_parser_lex_state_name(struct parser_params *p, enum lex_state_e state)
{
    return rb_fstring(append_lex_state_name(p, state, rb_str_new(0, 0)));
}

static void
append_bitstack_value(struct parser_params *p, stack_type stack, VALUE mesg)
{
    if (stack == 0) {
        rb_str_cat_cstr(mesg, "0");
    }
    else {
        stack_type mask = (stack_type)1U << (CHAR_BIT * sizeof(stack_type) - 1);
        for (; mask && !(stack & mask); mask >>= 1) continue;
        for (; mask; mask >>= 1) rb_str_cat(mesg, stack & mask ? "1" : "0", 1);
    }
}

void
rb_parser_show_bitstack(struct parser_params *p, stack_type stack,
                        const char *name, int line)
{
    VALUE mesg = rb_sprintf("%s: ", name);
    append_bitstack_value(p, stack, mesg);
    rb_str_catf(mesg, " at line %d\n", line);
    flush_debug_buffer(p, p->debug_output, mesg);
}

void
rb_parser_fatal(struct parser_params *p, const char *fmt, ...)
{
    va_list ap;
    VALUE mesg = rb_str_new_cstr("internal parser error: ");

    va_start(ap, fmt);
    rb_str_vcatf(mesg, fmt, ap);
    va_end(ap);
    yyerror0(RSTRING_PTR(mesg));
    RB_GC_GUARD(mesg);

    mesg = rb_str_new(0, 0);
    append_lex_state_name(p, p->lex.state, mesg);
    compile_error(p, "lex.state: %"PRIsVALUE, mesg);
    rb_str_resize(mesg, 0);
    append_bitstack_value(p, p->cond_stack, mesg);
    compile_error(p, "cond_stack: %"PRIsVALUE, mesg);
    rb_str_resize(mesg, 0);
    append_bitstack_value(p, p->cmdarg_stack, mesg);
    compile_error(p, "cmdarg_stack: %"PRIsVALUE, mesg);
    if (p->debug_output == rb_ractor_stdout())
        p->debug_output = rb_ractor_stderr();
    p->debug = TRUE;
}

static YYLTYPE *
rb_parser_set_pos(YYLTYPE *yylloc, int sourceline, int beg_pos, int end_pos)
{
    yylloc->beg_pos.lineno = sourceline;
    yylloc->beg_pos.column = beg_pos;
    yylloc->end_pos.lineno = sourceline;
    yylloc->end_pos.column = end_pos;
    return yylloc;
}

YYLTYPE *
rb_parser_set_location_from_strterm_heredoc(struct parser_params *p, rb_strterm_heredoc_t *here, YYLTYPE *yylloc)
{
    int sourceline = here->sourceline;
    int beg_pos = (int)here->offset - here->quote
        - (rb_strlen_lit("<<-") - !(here->func & STR_FUNC_INDENT));
    int end_pos = (int)here->offset + here->length + here->quote;

    return rb_parser_set_pos(yylloc, sourceline, beg_pos, end_pos);
}

YYLTYPE *
rb_parser_set_location_of_delayed_token(struct parser_params *p, YYLTYPE *yylloc)
{
    yylloc->beg_pos.lineno = p->delayed.beg_line;
    yylloc->beg_pos.column = p->delayed.beg_col;
    yylloc->end_pos.lineno = p->delayed.end_line;
    yylloc->end_pos.column = p->delayed.end_col;

    return yylloc;
}

YYLTYPE *
rb_parser_set_location_of_heredoc_end(struct parser_params *p, YYLTYPE *yylloc)
{
    int sourceline = p->ruby_sourceline;
    int beg_pos = (int)(p->lex.ptok - p->lex.pbeg);
    int end_pos = (int)(p->lex.pend - p->lex.pbeg);
    return rb_parser_set_pos(yylloc, sourceline, beg_pos, end_pos);
}

YYLTYPE *
rb_parser_set_location_of_dummy_end(struct parser_params *p, YYLTYPE *yylloc)
{
    yylloc->end_pos = yylloc->beg_pos;

    return yylloc;
}

YYLTYPE *
rb_parser_set_location_of_none(struct parser_params *p, YYLTYPE *yylloc)
{
    int sourceline = p->ruby_sourceline;
    int beg_pos = (int)(p->lex.ptok - p->lex.pbeg);
    int end_pos = (int)(p->lex.ptok - p->lex.pbeg);
    return rb_parser_set_pos(yylloc, sourceline, beg_pos, end_pos);
}

YYLTYPE *
rb_parser_set_location(struct parser_params *p, YYLTYPE *yylloc)
{
    int sourceline = p->ruby_sourceline;
    int beg_pos = (int)(p->lex.ptok - p->lex.pbeg);
    int end_pos = (int)(p->lex.pcur - p->lex.pbeg);
    return rb_parser_set_pos(yylloc, sourceline, beg_pos, end_pos);
}
#endif /* !RIPPER */

static int
assignable0(struct parser_params *p, ID id, const char **err)
{
    if (!id) return -1;
    switch (id) {
      case keyword_self:
        *err = "Can't change the value of self";
        return -1;
      case keyword_nil:
        *err = "Can't assign to nil";
        return -1;
      case keyword_true:
        *err = "Can't assign to true";
        return -1;
      case keyword_false:
        *err = "Can't assign to false";
        return -1;
      case keyword__FILE__:
        *err = "Can't assign to __FILE__";
        return -1;
      case keyword__LINE__:
        *err = "Can't assign to __LINE__";
        return -1;
      case keyword__ENCODING__:
        *err = "Can't assign to __ENCODING__";
        return -1;
    }
    switch (id_type(id)) {
      case ID_LOCAL:
        if (dyna_in_block(p)) {
            if (p->max_numparam > NO_PARAM && NUMPARAM_ID_P(id)) {
                compile_error(p, "Can't assign to numbered parameter _%d",
                              NUMPARAM_ID_TO_IDX(id));
                return -1;
            }
            if (dvar_curr(p, id)) return NODE_DASGN;
            if (dvar_defined(p, id)) return NODE_DASGN;
            if (local_id(p, id)) return NODE_LASGN;
            dyna_var(p, id);
            return NODE_DASGN;
        }
        else {
            if (!local_id(p, id)) local_var(p, id);
            return NODE_LASGN;
        }
        break;
      case ID_GLOBAL: return NODE_GASGN;
      case ID_INSTANCE: return NODE_IASGN;
      case ID_CONST:
        if (!p->ctxt.in_def) return NODE_CDECL;
        *err = "dynamic constant assignment";
        return -1;
      case ID_CLASS: return NODE_CVASGN;
      default:
        compile_error(p, "identifier %"PRIsVALUE" is not valid to set", rb_id2str(id));
    }
    return -1;
}

#ifndef RIPPER
static NODE*
assignable(struct parser_params *p, ID id, NODE *val, const YYLTYPE *loc)
{
    const char *err = 0;
    int node_type = assignable0(p, id, &err);
    switch (node_type) {
      case NODE_DASGN: return NEW_DASGN(id, val, loc);
      case NODE_LASGN: return NEW_LASGN(id, val, loc);
      case NODE_GASGN: return NEW_GASGN(id, val, loc);
      case NODE_IASGN: return NEW_IASGN(id, val, loc);
      case NODE_CDECL: return NEW_CDECL(id, val, 0, loc);
      case NODE_CVASGN: return NEW_CVASGN(id, val, loc);
    }
    if (err) yyerror1(loc, err);
    return NEW_BEGIN(0, loc);
}
#else
static VALUE
assignable(struct parser_params *p, VALUE lhs)
{
    const char *err = 0;
    assignable0(p, get_id(lhs), &err);
    if (err) lhs = assign_error(p, err, lhs);
    return lhs;
}
#endif

static int
is_private_local_id(struct parser_params *p, ID name)
{
    VALUE s;
    if (name == idUScore) return 1;
    if (!is_local_id(name)) return 0;
    s = rb_id2str(name);
    if (!s) return 0;
    return RSTRING_PTR(s)[0] == '_';
}

static int
shadowing_lvar_0(struct parser_params *p, ID name)
{
    if (dyna_in_block(p)) {
        if (dvar_curr(p, name)) {
            if (is_private_local_id(p, name)) return 1;
            yyerror0("duplicated argument name");
        }
        else if (dvar_defined(p, name) || local_id(p, name)) {
            vtable_add(p->lvtbl->vars, name);
            if (p->lvtbl->used) {
                vtable_add(p->lvtbl->used, (ID)p->ruby_sourceline | LVAR_USED);
            }
            return 0;
        }
    }
    else {
        if (local_id(p, name)) {
            if (is_private_local_id(p, name)) return 1;
            yyerror0("duplicated argument name");
        }
    }
    return 1;
}

static ID
shadowing_lvar(struct parser_params *p, ID name)
{
    shadowing_lvar_0(p, name);
    return name;
}

static void
new_bv(struct parser_params *p, ID name)
{
    if (!name) return;
    if (!is_local_id(name)) {
        compile_error(p, "invalid local variable - %"PRIsVALUE,
                      rb_id2str(name));
        return;
    }
    if (!shadowing_lvar_0(p, name)) return;
    dyna_var(p, name);
}

#ifndef RIPPER
static NODE *
aryset(struct parser_params *p, NODE *recv, NODE *idx, const YYLTYPE *loc)
{
    return NEW_ATTRASGN(recv, tASET, idx, loc);
}

static void
block_dup_check(struct parser_params *p, NODE *node1, NODE *node2)
{
    if (node2 && node1 && nd_type_p(node1, NODE_BLOCK_PASS)) {
        compile_error(p, "both block arg and actual block given");
    }
}

static NODE *
attrset(struct parser_params *p, NODE *recv, ID atype, ID id, const YYLTYPE *loc)
{
    if (!CALL_Q_P(atype)) id = rb_id_attrset(id);
    return NEW_ATTRASGN(recv, id, 0, loc);
}

static void
rb_backref_error(struct parser_params *p, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_NTH_REF:
        compile_error(p, "Can't set variable $%ld", RNODE_NTH_REF(node)->nd_nth);
        break;
      case NODE_BACK_REF:
        compile_error(p, "Can't set variable $%c", (int)RNODE_BACK_REF(node)->nd_nth);
        break;
    }
}
#else
static VALUE
backref_error(struct parser_params *p, NODE *ref, VALUE expr)
{
    VALUE mesg = rb_str_new_cstr("Can't set variable ");
    rb_str_append(mesg, RNODE_RIPPER(ref)->nd_cval);
    return dispatch2(assign_error, mesg, expr);
}
#endif

#ifndef RIPPER
static NODE *
arg_append(struct parser_params *p, NODE *node1, NODE *node2, const YYLTYPE *loc)
{
    if (!node1) return NEW_LIST(node2, &node2->nd_loc);
    switch (nd_type(node1))  {
      case NODE_LIST:
        return list_append(p, node1, node2);
      case NODE_BLOCK_PASS:
        RNODE_BLOCK_PASS(node1)->nd_head = arg_append(p, RNODE_BLOCK_PASS(node1)->nd_head, node2, loc);
        node1->nd_loc.end_pos = RNODE_BLOCK_PASS(node1)->nd_head->nd_loc.end_pos;
        return node1;
      case NODE_ARGSPUSH:
        RNODE_ARGSPUSH(node1)->nd_body = list_append(p, NEW_LIST(RNODE_ARGSPUSH(node1)->nd_body, &RNODE_ARGSPUSH(node1)->nd_body->nd_loc), node2);
        node1->nd_loc.end_pos = RNODE_ARGSPUSH(node1)->nd_body->nd_loc.end_pos;
        nd_set_type(node1, NODE_ARGSCAT);
        return node1;
      case NODE_ARGSCAT:
        if (!nd_type_p(RNODE_ARGSCAT(node1)->nd_body, NODE_LIST)) break;
        RNODE_ARGSCAT(node1)->nd_body = list_append(p, RNODE_ARGSCAT(node1)->nd_body, node2);
        node1->nd_loc.end_pos = RNODE_ARGSCAT(node1)->nd_body->nd_loc.end_pos;
        return node1;
    }
    return NEW_ARGSPUSH(node1, node2, loc);
}

static NODE *
arg_concat(struct parser_params *p, NODE *node1, NODE *node2, const YYLTYPE *loc)
{
    if (!node2) return node1;
    switch (nd_type(node1)) {
      case NODE_BLOCK_PASS:
        if (RNODE_BLOCK_PASS(node1)->nd_head)
            RNODE_BLOCK_PASS(node1)->nd_head = arg_concat(p, RNODE_BLOCK_PASS(node1)->nd_head, node2, loc);
        else
            RNODE_LIST(node1)->nd_head = NEW_LIST(node2, loc);
        return node1;
      case NODE_ARGSPUSH:
        if (!nd_type_p(node2, NODE_LIST)) break;
        RNODE_ARGSPUSH(node1)->nd_body = list_concat(NEW_LIST(RNODE_ARGSPUSH(node1)->nd_body, loc), node2);
        nd_set_type(node1, NODE_ARGSCAT);
        return node1;
      case NODE_ARGSCAT:
        if (!nd_type_p(node2, NODE_LIST) ||
            !nd_type_p(RNODE_ARGSCAT(node1)->nd_body, NODE_LIST)) break;
        RNODE_ARGSCAT(node1)->nd_body = list_concat(RNODE_ARGSCAT(node1)->nd_body, node2);
        return node1;
    }
    return NEW_ARGSCAT(node1, node2, loc);
}

static NODE *
last_arg_append(struct parser_params *p, NODE *args, NODE *last_arg, const YYLTYPE *loc)
{
    NODE *n1;
    if ((n1 = splat_array(args)) != 0) {
        return list_append(p, n1, last_arg);
    }
    return arg_append(p, args, last_arg, loc);
}

static NODE *
rest_arg_append(struct parser_params *p, NODE *args, NODE *rest_arg, const YYLTYPE *loc)
{
    NODE *n1;
    if ((nd_type_p(rest_arg, NODE_LIST)) && (n1 = splat_array(args)) != 0) {
        return list_concat(n1, rest_arg);
    }
    return arg_concat(p, args, rest_arg, loc);
}

static NODE *
splat_array(NODE* node)
{
    if (nd_type_p(node, NODE_SPLAT)) node = RNODE_SPLAT(node)->nd_head;
    if (nd_type_p(node, NODE_LIST)) return node;
    return 0;
}

static void
mark_lvar_used(struct parser_params *p, NODE *rhs)
{
    ID *vidp = NULL;
    if (!rhs) return;
    switch (nd_type(rhs)) {
      case NODE_LASGN:
        if (local_id_ref(p, RNODE_LASGN(rhs)->nd_vid, &vidp)) {
            if (vidp) *vidp |= LVAR_USED;
        }
        break;
      case NODE_DASGN:
        if (dvar_defined_ref(p, RNODE_DASGN(rhs)->nd_vid, &vidp)) {
            if (vidp) *vidp |= LVAR_USED;
        }
        break;
#if 0
      case NODE_MASGN:
        for (rhs = rhs->nd_head; rhs; rhs = rhs->nd_next) {
            mark_lvar_used(p, rhs->nd_head);
        }
        break;
#endif
    }
}

static NODE *
const_decl_path(struct parser_params *p, NODE **dest)
{
    NODE *n = *dest;
    if (!nd_type_p(n, NODE_CALL)) {
        const YYLTYPE *loc = &n->nd_loc;
        VALUE path;
        if (RNODE_CDECL(n)->nd_vid) {
             path = rb_id2str(RNODE_CDECL(n)->nd_vid);
        }
        else {
            n = RNODE_CDECL(n)->nd_else;
            path = rb_ary_new();
            for (; n && nd_type_p(n, NODE_COLON2); n = RNODE_COLON2(n)->nd_head) {
                rb_ary_push(path, rb_id2str(RNODE_COLON2(n)->nd_mid));
            }
            if (n && nd_type_p(n, NODE_CONST)) {
                // Const::Name
                rb_ary_push(path, rb_id2str(RNODE_CONST(n)->nd_vid));
            }
            else if (n && nd_type_p(n, NODE_COLON3)) {
                // ::Const::Name
                rb_ary_push(path, rb_str_new(0, 0));
            }
            else {
                // expression::Name
                rb_ary_push(path, rb_str_new_cstr("..."));
            }
            path = rb_ary_join(rb_ary_reverse(path), rb_str_new_cstr("::"));
            path = rb_fstring(path);
        }
        *dest = n = NEW_LIT(path, loc);
        RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_LIT(n)->nd_lit);
    }
    return n;
}

static NODE *
make_shareable_node(struct parser_params *p, NODE *value, bool copy, const YYLTYPE *loc)
{
    NODE *fcore = NEW_LIT(rb_mRubyVMFrozenCore, loc);

    if (copy) {
        return NEW_CALL(fcore, rb_intern("make_shareable_copy"),
                        NEW_LIST(value, loc), loc);
    }
    else {
        return NEW_CALL(fcore, rb_intern("make_shareable"),
                        NEW_LIST(value, loc), loc);
    }
}

static NODE *
ensure_shareable_node(struct parser_params *p, NODE **dest, NODE *value, const YYLTYPE *loc)
{
    NODE *fcore = NEW_LIT(rb_mRubyVMFrozenCore, loc);
    NODE *args = NEW_LIST(value, loc);
    args = list_append(p, args, const_decl_path(p, dest));
    return NEW_CALL(fcore, rb_intern("ensure_shareable"), args, loc);
}

static int is_static_content(NODE *node);

static VALUE
shareable_literal_value(struct parser_params *p, NODE *node)
{
    if (!node) return Qnil;
    enum node_type type = nd_type(node);
    switch (type) {
      case NODE_TRUE:
        return Qtrue;
      case NODE_FALSE:
        return Qfalse;
      case NODE_NIL:
        return Qnil;
      case NODE_LIT:
        return RNODE_LIT(node)->nd_lit;
      default:
        return Qundef;
    }
}

#ifndef SHAREABLE_BARE_EXPRESSION
#define SHAREABLE_BARE_EXPRESSION 1
#endif

static NODE *
shareable_literal_constant(struct parser_params *p, enum shareability shareable,
                           NODE **dest, NODE *value, const YYLTYPE *loc, size_t level)
{
# define shareable_literal_constant_next(n) \
    shareable_literal_constant(p, shareable, dest, (n), &(n)->nd_loc, level+1)
    VALUE lit = Qnil;

    if (!value) return 0;
    enum node_type type = nd_type(value);
    switch (type) {
      case NODE_TRUE:
      case NODE_FALSE:
      case NODE_NIL:
      case NODE_LIT:
        return value;

      case NODE_DSTR:
        if (shareable == shareable_literal) {
            value = NEW_CALL(value, idUMinus, 0, loc);
        }
        return value;

      case NODE_STR:
        lit = rb_fstring(RNODE_STR(value)->nd_lit);
        nd_set_type(value, NODE_LIT);
        RB_OBJ_WRITE(p->ast, &RNODE_LIT(value)->nd_lit, lit);
        return value;

      case NODE_ZLIST:
        lit = rb_ary_new();
        OBJ_FREEZE_RAW(lit);
        NODE *n = NEW_LIT(lit, loc);
        RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_LIT(n)->nd_lit);
        return n;

      case NODE_LIST:
        lit = rb_ary_new();
        for (NODE *n = value; n; n = RNODE_LIST(n)->nd_next) {
            NODE *elt = RNODE_LIST(n)->nd_head;
            if (elt) {
                elt = shareable_literal_constant_next(elt);
                if (elt) {
                    RNODE_LIST(n)->nd_head = elt;
                }
                else if (RTEST(lit)) {
                    rb_ary_clear(lit);
                    lit = Qfalse;
                }
            }
            if (RTEST(lit)) {
                VALUE e = shareable_literal_value(p, elt);
                if (!UNDEF_P(e)) {
                    rb_ary_push(lit, e);
                }
                else {
                    rb_ary_clear(lit);
                    lit = Qnil;	/* make shareable at runtime */
                }
            }
        }
        break;

      case NODE_HASH:
        if (!RNODE_HASH(value)->nd_brace) return 0;
        lit = rb_hash_new();
        for (NODE *n = RNODE_HASH(value)->nd_head; n; n = RNODE_LIST(RNODE_LIST(n)->nd_next)->nd_next) {
            NODE *key = RNODE_LIST(n)->nd_head;
            NODE *val = RNODE_LIST(RNODE_LIST(n)->nd_next)->nd_head;
            if (key) {
                key = shareable_literal_constant_next(key);
                if (key) {
                    RNODE_LIST(n)->nd_head = key;
                }
                else if (RTEST(lit)) {
                    rb_hash_clear(lit);
                    lit = Qfalse;
                }
            }
            if (val) {
                val = shareable_literal_constant_next(val);
                if (val) {
                    RNODE_LIST(RNODE_LIST(n)->nd_next)->nd_head = val;
                }
                else if (RTEST(lit)) {
                    rb_hash_clear(lit);
                    lit = Qfalse;
                }
            }
            if (RTEST(lit)) {
                VALUE k = shareable_literal_value(p, key);
                VALUE v = shareable_literal_value(p, val);
                if (!UNDEF_P(k) && !UNDEF_P(v)) {
                    rb_hash_aset(lit, k, v);
                }
                else {
                    rb_hash_clear(lit);
                    lit = Qnil;	/* make shareable at runtime */
                }
            }
        }
        break;

      default:
        if (shareable == shareable_literal &&
            (SHAREABLE_BARE_EXPRESSION || level > 0)) {
            return ensure_shareable_node(p, dest, value, loc);
        }
        return 0;
    }

    /* Array or Hash */
    if (!lit) return 0;
    if (NIL_P(lit)) {
        // if shareable_literal, all elements should have been ensured
        // as shareable
        value = make_shareable_node(p, value, false, loc);
    }
    else {
        value = NEW_LIT(rb_ractor_make_shareable(lit), loc);
        RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_LIT(value)->nd_lit);
    }

    return value;
# undef shareable_literal_constant_next
}

static NODE *
shareable_constant_value(struct parser_params *p, enum shareability shareable,
                         NODE *lhs, NODE *value, const YYLTYPE *loc)
{
    if (!value) return 0;
    switch (shareable) {
      case shareable_none:
        return value;

      case shareable_literal:
        {
            NODE *lit = shareable_literal_constant(p, shareable, &lhs, value, loc, 0);
            if (lit) return lit;
            return value;
        }
        break;

      case shareable_copy:
      case shareable_everything:
        {
            NODE *lit = shareable_literal_constant(p, shareable, &lhs, value, loc, 0);
            if (lit) return lit;
            return make_shareable_node(p, value, shareable == shareable_copy, loc);
        }
        break;

      default:
        UNREACHABLE_RETURN(0);
    }
}

static NODE *
node_assign(struct parser_params *p, NODE *lhs, NODE *rhs, struct lex_context ctxt, const YYLTYPE *loc)
{
    if (!lhs) return 0;

    switch (nd_type(lhs)) {
      case NODE_CDECL:
        rhs = shareable_constant_value(p, ctxt.shareable_constant_value, lhs, rhs, loc);
        /* fallthru */

      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_MASGN:
      case NODE_CVASGN:
        set_nd_value(p, lhs, rhs);
        nd_set_loc(lhs, loc);
        break;

      case NODE_ATTRASGN:
        RNODE_ATTRASGN(lhs)->nd_args = arg_append(p, RNODE_ATTRASGN(lhs)->nd_args, rhs, loc);
        nd_set_loc(lhs, loc);
        break;

      default:
        /* should not happen */
        break;
    }

    return lhs;
}

static NODE *
value_expr_check(struct parser_params *p, NODE *node)
{
    NODE *void_node = 0, *vn;

    if (!node) {
        rb_warning0("empty expression");
    }
    while (node) {
        switch (nd_type(node)) {
          case NODE_RETURN:
          case NODE_BREAK:
          case NODE_NEXT:
          case NODE_REDO:
          case NODE_RETRY:
            return void_node ? void_node : node;

          case NODE_CASE3:
            if (!RNODE_CASE3(node)->nd_body || !nd_type_p(RNODE_CASE3(node)->nd_body, NODE_IN)) {
                compile_error(p, "unexpected node");
                return NULL;
            }
            if (RNODE_IN(RNODE_CASE3(node)->nd_body)->nd_body) {
                return NULL;
            }
            /* single line pattern matching with "=>" operator */
            return void_node ? void_node : node;

          case NODE_BLOCK:
            while (RNODE_BLOCK(node)->nd_next) {
                node = RNODE_BLOCK(node)->nd_next;
            }
            node = RNODE_BLOCK(node)->nd_head;
            break;

          case NODE_BEGIN:
            node = RNODE_BEGIN(node)->nd_body;
            break;

          case NODE_IF:
          case NODE_UNLESS:
            if (!RNODE_IF(node)->nd_body) {
                return NULL;
            }
            else if (!RNODE_IF(node)->nd_else) {
                return NULL;
            }
            vn = value_expr_check(p, RNODE_IF(node)->nd_body);
            if (!vn) return NULL;
            if (!void_node) void_node = vn;
            node = RNODE_IF(node)->nd_else;
            break;

          case NODE_AND:
          case NODE_OR:
            node = RNODE_AND(node)->nd_1st;
            break;

          case NODE_LASGN:
          case NODE_DASGN:
          case NODE_MASGN:
            mark_lvar_used(p, node);
            return NULL;

          default:
            return NULL;
        }
    }

    return NULL;
}

static int
value_expr_gen(struct parser_params *p, NODE *node)
{
    NODE *void_node = value_expr_check(p, node);
    if (void_node) {
        yyerror1(&void_node->nd_loc, "void value expression");
        /* or "control never reach"? */
        return FALSE;
    }
    return TRUE;
}

static void
void_expr(struct parser_params *p, NODE *node)
{
    const char *useless = 0;

    if (!RTEST(ruby_verbose)) return;

    if (!node || !(node = nd_once_body(node))) return;
    switch (nd_type(node)) {
      case NODE_OPCALL:
        switch (RNODE_OPCALL(node)->nd_mid) {
          case '+':
          case '-':
          case '*':
          case '/':
          case '%':
          case tPOW:
          case tUPLUS:
          case tUMINUS:
          case '|':
          case '^':
          case '&':
          case tCMP:
          case '>':
          case tGEQ:
          case '<':
          case tLEQ:
          case tEQ:
          case tNEQ:
            useless = rb_id2name(RNODE_OPCALL(node)->nd_mid);
            break;
        }
        break;

      case NODE_LVAR:
      case NODE_DVAR:
      case NODE_GVAR:
      case NODE_IVAR:
      case NODE_CVAR:
      case NODE_NTH_REF:
      case NODE_BACK_REF:
        useless = "a variable";
        break;
      case NODE_CONST:
        useless = "a constant";
        break;
      case NODE_LIT:
      case NODE_STR:
      case NODE_DSTR:
      case NODE_DREGX:
        useless = "a literal";
        break;
      case NODE_COLON2:
      case NODE_COLON3:
        useless = "::";
        break;
      case NODE_DOT2:
        useless = "..";
        break;
      case NODE_DOT3:
        useless = "...";
        break;
      case NODE_SELF:
        useless = "self";
        break;
      case NODE_NIL:
        useless = "nil";
        break;
      case NODE_TRUE:
        useless = "true";
        break;
      case NODE_FALSE:
        useless = "false";
        break;
      case NODE_DEFINED:
        useless = "defined?";
        break;
    }

    if (useless) {
        rb_warn1L(nd_line(node), "possibly useless use of %s in void context", WARN_S(useless));
    }
}

static NODE *
void_stmts(struct parser_params *p, NODE *node)
{
    NODE *const n = node;
    if (!RTEST(ruby_verbose)) return n;
    if (!node) return n;
    if (!nd_type_p(node, NODE_BLOCK)) return n;

    while (RNODE_BLOCK(node)->nd_next) {
        void_expr(p, RNODE_BLOCK(node)->nd_head);
        node = RNODE_BLOCK(node)->nd_next;
    }
    return n;
}

static NODE *
remove_begin(NODE *node)
{
    NODE **n = &node, *n1 = node;
    while (n1 && nd_type_p(n1, NODE_BEGIN) && RNODE_BEGIN(n1)->nd_body) {
        *n = n1 = RNODE_BEGIN(n1)->nd_body;
    }
    return node;
}

static NODE *
remove_begin_all(NODE *node)
{
    NODE **n = &node, *n1 = node;
    while (n1 && nd_type_p(n1, NODE_BEGIN)) {
        *n = n1 = RNODE_BEGIN(n1)->nd_body;
    }
    return node;
}

static void
reduce_nodes(struct parser_params *p, NODE **body)
{
    NODE *node = *body;

    if (!node) {
        *body = NEW_NIL(&NULL_LOC);
        return;
    }
#define subnodes(type, n1, n2) \
    ((!type(node)->n1) ? (type(node)->n2 ? (body = &type(node)->n2, 1) : 0) : \
     (!type(node)->n2) ? (body = &type(node)->n1, 1) : \
     (reduce_nodes(p, &type(node)->n1), body = &type(node)->n2, 1))

    while (node) {
        int newline = (int)(nd_fl_newline(node));
        switch (nd_type(node)) {
          end:
          case NODE_NIL:
            *body = 0;
            return;
          case NODE_RETURN:
            *body = node = RNODE_RETURN(node)->nd_stts;
            if (newline && node) nd_set_fl_newline(node);
            continue;
          case NODE_BEGIN:
            *body = node = RNODE_BEGIN(node)->nd_body;
            if (newline && node) nd_set_fl_newline(node);
            continue;
          case NODE_BLOCK:
            body = &RNODE_BLOCK(RNODE_BLOCK(node)->nd_end)->nd_head;
            break;
          case NODE_IF:
          case NODE_UNLESS:
            if (subnodes(RNODE_IF, nd_body, nd_else)) break;
            return;
          case NODE_CASE:
            body = &RNODE_CASE(node)->nd_body;
            break;
          case NODE_WHEN:
            if (!subnodes(RNODE_WHEN, nd_body, nd_next)) goto end;
            break;
          case NODE_ENSURE:
            if (!subnodes(RNODE_ENSURE, nd_head, nd_resq)) goto end;
            break;
          case NODE_RESCUE:
            newline = 0; // RESBODY should not be a NEWLINE
            if (RNODE_RESCUE(node)->nd_else) {
                body = &RNODE_RESCUE(node)->nd_resq;
                break;
            }
            if (!subnodes(RNODE_RESCUE, nd_head, nd_resq)) goto end;
            break;
          default:
            return;
        }
        node = *body;
        if (newline && node) nd_set_fl_newline(node);
    }

#undef subnodes
}

static int
is_static_content(NODE *node)
{
    if (!node) return 1;
    switch (nd_type(node)) {
      case NODE_HASH:
        if (!(node = RNODE_HASH(node)->nd_head)) break;
      case NODE_LIST:
        do {
            if (!is_static_content(RNODE_LIST(node)->nd_head)) return 0;
        } while ((node = RNODE_LIST(node)->nd_next) != 0);
      case NODE_LIT:
      case NODE_STR:
      case NODE_NIL:
      case NODE_TRUE:
      case NODE_FALSE:
      case NODE_ZLIST:
        break;
      default:
        return 0;
    }
    return 1;
}

static int
assign_in_cond(struct parser_params *p, NODE *node)
{
    switch (nd_type(node)) {
      case NODE_MASGN:
      case NODE_LASGN:
      case NODE_DASGN:
      case NODE_GASGN:
      case NODE_IASGN:
      case NODE_CVASGN:
      case NODE_CDECL:
        break;

      default:
        return 0;
    }

    if (!get_nd_value(p, node)) return 1;
    if (is_static_content(get_nd_value(p, node))) {
        /* reports always */
        parser_warn(p, get_nd_value(p, node), "found `= literal' in conditional, should be ==");
    }
    return 1;
}

enum cond_type {
    COND_IN_OP,
    COND_IN_COND,
    COND_IN_FF
};

#define SWITCH_BY_COND_TYPE(t, w, arg) do { \
    switch (t) { \
      case COND_IN_OP: break; \
      case COND_IN_COND: rb_##w##0(arg "literal in condition"); break; \
      case COND_IN_FF: rb_##w##0(arg "literal in flip-flop"); break; \
    } \
} while (0)

static NODE *cond0(struct parser_params*,NODE*,enum cond_type,const YYLTYPE*,bool);

static NODE*
range_op(struct parser_params *p, NODE *node, const YYLTYPE *loc)
{
    enum node_type type;

    if (node == 0) return 0;

    type = nd_type(node);
    value_expr(node);
    if (type == NODE_LIT && FIXNUM_P(RNODE_LIT(node)->nd_lit)) {
        if (!e_option_supplied(p)) parser_warn(p, node, "integer literal in flip-flop");
        ID lineno = rb_intern("$.");
        return NEW_CALL(node, tEQ, NEW_LIST(NEW_GVAR(lineno, loc), loc), loc);
    }
    return cond0(p, node, COND_IN_FF, loc, true);
}

static NODE*
cond0(struct parser_params *p, NODE *node, enum cond_type type, const YYLTYPE *loc, bool top)
{
    if (node == 0) return 0;
    if (!(node = nd_once_body(node))) return 0;
    assign_in_cond(p, node);

    switch (nd_type(node)) {
      case NODE_BEGIN:
        RNODE_BEGIN(node)->nd_body = cond0(p, RNODE_BEGIN(node)->nd_body, type, loc, top);
        break;

      case NODE_DSTR:
      case NODE_EVSTR:
      case NODE_STR:
        SWITCH_BY_COND_TYPE(type, warn, "string ");
        break;

      case NODE_DREGX:
        if (!e_option_supplied(p)) SWITCH_BY_COND_TYPE(type, warning, "regex ");

        return NEW_MATCH2(node, NEW_GVAR(idLASTLINE, loc), loc);

      case NODE_BLOCK:
        RNODE_BLOCK(RNODE_BLOCK(node)->nd_end)->nd_head = cond0(p, RNODE_BLOCK(RNODE_BLOCK(node)->nd_end)->nd_head, type, loc, false);
        break;

      case NODE_AND:
      case NODE_OR:
        RNODE_AND(node)->nd_1st = cond0(p, RNODE_AND(node)->nd_1st, COND_IN_COND, loc, true);
        RNODE_AND(node)->nd_2nd = cond0(p, RNODE_AND(node)->nd_2nd, COND_IN_COND, loc, true);
        break;

      case NODE_DOT2:
      case NODE_DOT3:
        if (!top) break;
        RNODE_DOT2(node)->nd_beg = range_op(p, RNODE_DOT2(node)->nd_beg, loc);
        RNODE_DOT2(node)->nd_end = range_op(p, RNODE_DOT2(node)->nd_end, loc);
        if (nd_type_p(node, NODE_DOT2)) nd_set_type(node,NODE_FLIP2);
        else if (nd_type_p(node, NODE_DOT3)) nd_set_type(node, NODE_FLIP3);
        break;

      case NODE_DSYM:
      warn_symbol:
        SWITCH_BY_COND_TYPE(type, warning, "symbol ");
        break;

      case NODE_LIT:
        if (RB_TYPE_P(RNODE_LIT(node)->nd_lit, T_REGEXP)) {
            if (!e_option_supplied(p)) SWITCH_BY_COND_TYPE(type, warn, "regex ");
            nd_set_type(node, NODE_MATCH);
        }
        else if (RNODE_LIT(node)->nd_lit == Qtrue ||
                 RNODE_LIT(node)->nd_lit == Qfalse) {
            /* booleans are OK, e.g., while true */
        }
        else if (SYMBOL_P(RNODE_LIT(node)->nd_lit)) {
            goto warn_symbol;
        }
        else {
            SWITCH_BY_COND_TYPE(type, warning, "");
        }
      default:
        break;
    }
    return node;
}

static NODE*
cond(struct parser_params *p, NODE *node, const YYLTYPE *loc)
{
    if (node == 0) return 0;
    return cond0(p, node, COND_IN_COND, loc, true);
}

static NODE*
method_cond(struct parser_params *p, NODE *node, const YYLTYPE *loc)
{
    if (node == 0) return 0;
    return cond0(p, node, COND_IN_OP, loc, true);
}

static NODE*
new_nil_at(struct parser_params *p, const rb_code_position_t *pos)
{
    YYLTYPE loc = {*pos, *pos};
    return NEW_NIL(&loc);
}

static NODE*
new_if(struct parser_params *p, NODE *cc, NODE *left, NODE *right, const YYLTYPE *loc)
{
    if (!cc) return right;
    cc = cond0(p, cc, COND_IN_COND, loc, true);
    return newline_node(NEW_IF(cc, left, right, loc));
}

static NODE*
new_unless(struct parser_params *p, NODE *cc, NODE *left, NODE *right, const YYLTYPE *loc)
{
    if (!cc) return right;
    cc = cond0(p, cc, COND_IN_COND, loc, true);
    return newline_node(NEW_UNLESS(cc, left, right, loc));
}

#define NEW_AND_OR(type, f, s, loc) (type == NODE_AND ? NEW_AND(f,s,loc) : NEW_OR(f,s,loc))

static NODE*
logop(struct parser_params *p, ID id, NODE *left, NODE *right,
          const YYLTYPE *op_loc, const YYLTYPE *loc)
{
    enum node_type type = id == idAND || id == idANDOP ? NODE_AND : NODE_OR;
    NODE *op;
    value_expr(left);
    if (left && nd_type_p(left, type)) {
        NODE *node = left, *second;
        while ((second = RNODE_AND(node)->nd_2nd) != 0 && nd_type_p(second, type)) {
            node = second;
        }
        RNODE_AND(node)->nd_2nd = NEW_AND_OR(type, second, right, loc);
        nd_set_line(RNODE_AND(node)->nd_2nd, op_loc->beg_pos.lineno);
        left->nd_loc.end_pos = loc->end_pos;
        return left;
    }
    op = NEW_AND_OR(type, left, right, loc);
    nd_set_line(op, op_loc->beg_pos.lineno);
    return op;
}

#undef NEW_AND_OR

static void
no_blockarg(struct parser_params *p, NODE *node)
{
    if (nd_type_p(node, NODE_BLOCK_PASS)) {
        compile_error(p, "block argument should not be given");
    }
}

static NODE *
ret_args(struct parser_params *p, NODE *node)
{
    if (node) {
        no_blockarg(p, node);
        if (nd_type_p(node, NODE_LIST) && !RNODE_LIST(node)->nd_next) {
            node = RNODE_LIST(node)->nd_head;
        }
    }
    return node;
}

static NODE *
new_yield(struct parser_params *p, NODE *node, const YYLTYPE *loc)
{
    if (node) no_blockarg(p, node);

    return NEW_YIELD(node, loc);
}

static VALUE
negate_lit(struct parser_params *p, VALUE lit)
{
    if (FIXNUM_P(lit)) {
        return LONG2FIX(-FIX2LONG(lit));
    }
    if (SPECIAL_CONST_P(lit)) {
#if USE_FLONUM
        if (FLONUM_P(lit)) {
            return DBL2NUM(-RFLOAT_VALUE(lit));
        }
#endif
        goto unknown;
    }
    switch (BUILTIN_TYPE(lit)) {
      case T_BIGNUM:
        bignum_negate(lit);
        lit = rb_big_norm(lit);
        break;
      case T_RATIONAL:
        rational_set_num(lit, negate_lit(p, rational_get_num(lit)));
        break;
      case T_COMPLEX:
        rcomplex_set_real(lit, negate_lit(p, rcomplex_get_real(lit)));
        rcomplex_set_imag(lit, negate_lit(p, rcomplex_get_imag(lit)));
        break;
      case T_FLOAT:
        lit = DBL2NUM(-RFLOAT_VALUE(lit));
        break;
      unknown:
      default:
        rb_parser_fatal(p, "unknown literal type (%s) passed to negate_lit",
                        rb_builtin_class_name(lit));
        break;
    }
    return lit;
}

static NODE *
arg_blk_pass(NODE *node1, rb_node_block_pass_t *node2)
{
    if (node2) {
        if (!node1) return (NODE *)node2;
        node2->nd_head = node1;
        nd_set_first_lineno(node2, nd_first_lineno(node1));
        nd_set_first_column(node2, nd_first_column(node1));
        return (NODE *)node2;
    }
    return node1;
}

static bool
args_info_empty_p(struct rb_args_info *args)
{
    if (args->pre_args_num) return false;
    if (args->post_args_num) return false;
    if (args->rest_arg) return false;
    if (args->opt_args) return false;
    if (args->block_arg) return false;
    if (args->kw_args) return false;
    if (args->kw_rest_arg) return false;
    return true;
}

static rb_node_args_t *
new_args(struct parser_params *p, rb_node_args_aux_t *pre_args, rb_node_opt_arg_t *opt_args, ID rest_arg, rb_node_args_aux_t *post_args, rb_node_args_t *tail, const YYLTYPE *loc)
{
    struct rb_args_info *args = &tail->nd_ainfo;

    if (args->forwarding) {
        if (rest_arg) {
            yyerror1(&RNODE(tail)->nd_loc, "... after rest argument");
            return tail;
        }
        rest_arg = idFWD_REST;
    }

    args->pre_args_num   = pre_args ? rb_long2int(pre_args->nd_plen) : 0;
    args->pre_init       = pre_args ? pre_args->nd_next : 0;

    args->post_args_num  = post_args ? rb_long2int(post_args->nd_plen) : 0;
    args->post_init      = post_args ? post_args->nd_next : 0;
    args->first_post_arg = post_args ? post_args->nd_pid : 0;

    args->rest_arg       = rest_arg;

    args->opt_args       = opt_args;

#ifdef FORWARD_ARGS_WITH_RUBY2_KEYWORDS
    args->ruby2_keywords = args->forwarding;
#else
    args->ruby2_keywords = 0;
#endif

    nd_set_loc(RNODE(tail), loc);

    return tail;
}

static rb_node_args_t *
new_args_tail(struct parser_params *p, rb_node_kw_arg_t *kw_args, ID kw_rest_arg, ID block, const YYLTYPE *kw_rest_loc)
{
    rb_node_args_t *node = NEW_ARGS(&NULL_LOC);
    struct rb_args_info *args = &node->nd_ainfo;
    if (p->error_p) return node;

    args->block_arg      = block;
    args->kw_args        = kw_args;

    if (kw_args) {
        /*
         * def foo(k1: 1, kr1:, k2: 2, **krest, &b)
         * variable order: k1, kr1, k2, &b, internal_id, krest
         * #=> <reorder>
         * variable order: kr1, k1, k2, internal_id, krest, &b
         */
        ID kw_bits = internal_id(p), *required_kw_vars, *kw_vars;
        struct vtable *vtargs = p->lvtbl->args;
        rb_node_kw_arg_t *kwn = kw_args;

        if (block) block = vtargs->tbl[vtargs->pos-1];
        vtable_pop(vtargs, !!block + !!kw_rest_arg);
        required_kw_vars = kw_vars = &vtargs->tbl[vtargs->pos];
        while (kwn) {
            if (!NODE_REQUIRED_KEYWORD_P(get_nd_value(p, kwn->nd_body)))
                --kw_vars;
            --required_kw_vars;
            kwn = kwn->nd_next;
        }

        for (kwn = kw_args; kwn; kwn = kwn->nd_next) {
            ID vid = get_nd_vid(p, kwn->nd_body);
            if (NODE_REQUIRED_KEYWORD_P(get_nd_value(p, kwn->nd_body))) {
                *required_kw_vars++ = vid;
            }
            else {
                *kw_vars++ = vid;
            }
        }

        arg_var(p, kw_bits);
        if (kw_rest_arg) arg_var(p, kw_rest_arg);
        if (block) arg_var(p, block);

        args->kw_rest_arg = NEW_DVAR(kw_rest_arg, kw_rest_loc);
    }
    else if (kw_rest_arg == idNil) {
        args->no_kwarg = 1;
    }
    else if (kw_rest_arg) {
        args->kw_rest_arg = NEW_DVAR(kw_rest_arg, kw_rest_loc);
    }

    return node;
}

static rb_node_args_t *
args_with_numbered(struct parser_params *p, rb_node_args_t *args, int max_numparam)
{
    if (max_numparam > NO_PARAM) {
        if (!args) {
            YYLTYPE loc = RUBY_INIT_YYLLOC();
            args = new_args_tail(p, 0, 0, 0, 0);
            nd_set_loc(RNODE(args), &loc);
        }
        args->nd_ainfo.pre_args_num = max_numparam;
    }
    return args;
}

static NODE*
new_array_pattern(struct parser_params *p, NODE *constant, NODE *pre_arg, NODE *aryptn, const YYLTYPE *loc)
{
    RNODE_ARYPTN(aryptn)->nd_pconst = constant;

    if (pre_arg) {
        NODE *pre_args = NEW_LIST(pre_arg, loc);
        if (RNODE_ARYPTN(aryptn)->pre_args) {
            RNODE_ARYPTN(aryptn)->pre_args = list_concat(pre_args, RNODE_ARYPTN(aryptn)->pre_args);
        }
        else {
            RNODE_ARYPTN(aryptn)->pre_args = pre_args;
        }
    }
    return aryptn;
}

static NODE*
new_array_pattern_tail(struct parser_params *p, NODE *pre_args, int has_rest, NODE *rest_arg, NODE *post_args, const YYLTYPE *loc)
{
    if (has_rest) {
        rest_arg = rest_arg ? rest_arg : NODE_SPECIAL_NO_NAME_REST;
    }
    else {
        rest_arg = NULL;
    }
    NODE *node = NEW_ARYPTN(pre_args, rest_arg, post_args, loc);

    return node;
}

static NODE*
new_find_pattern(struct parser_params *p, NODE *constant, NODE *fndptn, const YYLTYPE *loc)
{
    RNODE_FNDPTN(fndptn)->nd_pconst = constant;

    return fndptn;
}

static NODE*
new_find_pattern_tail(struct parser_params *p, NODE *pre_rest_arg, NODE *args, NODE *post_rest_arg, const YYLTYPE *loc)
{
    pre_rest_arg = pre_rest_arg ? pre_rest_arg : NODE_SPECIAL_NO_NAME_REST;
    post_rest_arg = post_rest_arg ? post_rest_arg : NODE_SPECIAL_NO_NAME_REST;
    NODE *node = NEW_FNDPTN(pre_rest_arg, args, post_rest_arg, loc);

    return node;
}

static NODE*
new_hash_pattern(struct parser_params *p, NODE *constant, NODE *hshptn, const YYLTYPE *loc)
{
    RNODE_HSHPTN(hshptn)->nd_pconst = constant;
    return hshptn;
}

static NODE*
new_hash_pattern_tail(struct parser_params *p, NODE *kw_args, ID kw_rest_arg, const YYLTYPE *loc)
{
    NODE *node, *kw_rest_arg_node;

    if (kw_rest_arg == idNil) {
        kw_rest_arg_node = NODE_SPECIAL_NO_REST_KEYWORD;
    }
    else if (kw_rest_arg) {
        kw_rest_arg_node = assignable(p, kw_rest_arg, 0, loc);
    }
    else {
        kw_rest_arg_node = NULL;
    }

    node = NEW_HSHPTN(0, kw_args, kw_rest_arg_node, loc);

    return node;
}

static NODE*
dsym_node(struct parser_params *p, NODE *node, const YYLTYPE *loc)
{
    VALUE lit;

    if (!node) {
        return NEW_LIT(ID2SYM(idNULL), loc);
    }

    switch (nd_type(node)) {
      case NODE_DSTR:
        nd_set_type(node, NODE_DSYM);
        nd_set_loc(node, loc);
        break;
      case NODE_STR:
        lit = RNODE_STR(node)->nd_lit;
        RB_OBJ_WRITTEN(p->ast, Qnil, RNODE_STR(node)->nd_lit = ID2SYM(rb_intern_str(lit)));
        nd_set_type(node, NODE_LIT);
        nd_set_loc(node, loc);
        break;
      default:
        node = NEW_DSYM(Qnil, 1, NEW_LIST(node, loc), loc);
        break;
    }
    return node;
}

static int
append_literal_keys(st_data_t k, st_data_t v, st_data_t h)
{
    NODE *node = (NODE *)v;
    NODE **result = (NODE **)h;
    RNODE_LIST(node)->as.nd_alen = 2;
    RNODE_LIST(RNODE_LIST(node)->nd_next)->as.nd_end = RNODE_LIST(node)->nd_next;
    RNODE_LIST(RNODE_LIST(node)->nd_next)->nd_next = 0;
    if (*result)
        list_concat(*result, node);
    else
        *result = node;
    return ST_CONTINUE;
}

static NODE *
remove_duplicate_keys(struct parser_params *p, NODE *hash)
{
    struct st_hash_type literal_type = {
        literal_cmp,
        literal_hash,
    };

    st_table *literal_keys = st_init_table_with_size(&literal_type, RNODE_LIST(hash)->as.nd_alen / 2);
    NODE *result = 0;
    NODE *last_expr = 0;
    rb_code_location_t loc = hash->nd_loc;
    while (hash && RNODE_LIST(hash)->nd_next) {
        NODE *head = RNODE_LIST(hash)->nd_head;
        NODE *value = RNODE_LIST(hash)->nd_next;
        NODE *next = RNODE_LIST(value)->nd_next;
        st_data_t key = (st_data_t)head;
        st_data_t data;
        RNODE_LIST(value)->nd_next = 0;
        if (!head) {
            key = (st_data_t)value;
        }
        else if (nd_type_p(head, NODE_LIT) &&
                 st_delete(literal_keys, (key = (st_data_t)RNODE_LIT(head)->nd_lit, &key), &data)) {
            NODE *dup_value = (RNODE_LIST((NODE *)data))->nd_next;
            rb_compile_warn(p->ruby_sourcefile, nd_line((NODE *)data),
                            "key %+"PRIsVALUE" is duplicated and overwritten on line %d",
                            RNODE_LIT(head)->nd_lit, nd_line(head));
            if (dup_value == last_expr) {
                RNODE_LIST(value)->nd_head = block_append(p, RNODE_LIST(dup_value)->nd_head, RNODE_LIST(value)->nd_head);
            }
            else {
                RNODE_LIST(last_expr)->nd_head = block_append(p, RNODE_LIST(dup_value)->nd_head, RNODE_LIST(last_expr)->nd_head);
            }
        }
        st_insert(literal_keys, (st_data_t)key, (st_data_t)hash);
        last_expr = !head || nd_type_p(head, NODE_LIT) ? value : head;
        hash = next;
    }
    st_foreach(literal_keys, append_literal_keys, (st_data_t)&result);
    st_free_table(literal_keys);
    if (hash) {
        if (!result) result = hash;
        else list_concat(result, hash);
    }
    result->nd_loc = loc;
    return result;
}

static NODE *
new_hash(struct parser_params *p, NODE *hash, const YYLTYPE *loc)
{
    if (hash) hash = remove_duplicate_keys(p, hash);
    return NEW_HASH(hash, loc);
}
#endif

static void
error_duplicate_pattern_variable(struct parser_params *p, ID id, const YYLTYPE *loc)
{
    if (is_private_local_id(p, id)) {
        return;
    }
    if (st_is_member(p->pvtbl, id)) {
        yyerror1(loc, "duplicated variable name");
    }
    else {
        st_insert(p->pvtbl, (st_data_t)id, 0);
    }
}

static void
error_duplicate_pattern_key(struct parser_params *p, VALUE key, const YYLTYPE *loc)
{
    if (!p->pktbl) {
        p->pktbl = st_init_numtable();
    }
    else if (st_is_member(p->pktbl, key)) {
        yyerror1(loc, "duplicated key name");
        return;
    }
    st_insert(p->pktbl, (st_data_t)key, 0);
}

#ifndef RIPPER
static NODE *
new_unique_key_hash(struct parser_params *p, NODE *hash, const YYLTYPE *loc)
{
    return NEW_HASH(hash, loc);
}
#endif /* !RIPPER */

#ifndef RIPPER
static NODE *
new_op_assign(struct parser_params *p, NODE *lhs, ID op, NODE *rhs, struct lex_context ctxt, const YYLTYPE *loc)
{
    NODE *asgn;

    if (lhs) {
        ID vid = get_nd_vid(p, lhs);
        YYLTYPE lhs_loc = lhs->nd_loc;
        int shareable = ctxt.shareable_constant_value;
        if (shareable) {
            switch (nd_type(lhs)) {
              case NODE_CDECL:
              case NODE_COLON2:
              case NODE_COLON3:
                break;
              default:
                shareable = 0;
                break;
            }
        }
        if (op == tOROP) {
            rhs = shareable_constant_value(p, shareable, lhs, rhs, &rhs->nd_loc);
            set_nd_value(p, lhs, rhs);
            nd_set_loc(lhs, loc);
            asgn = NEW_OP_ASGN_OR(gettable(p, vid, &lhs_loc), lhs, loc);
        }
        else if (op == tANDOP) {
            if (shareable) {
                rhs = shareable_constant_value(p, shareable, lhs, rhs, &rhs->nd_loc);
            }
            set_nd_value(p, lhs, rhs);
            nd_set_loc(lhs, loc);
            asgn = NEW_OP_ASGN_AND(gettable(p, vid, &lhs_loc), lhs, loc);
        }
        else {
            asgn = lhs;
            rhs = NEW_CALL(gettable(p, vid, &lhs_loc), op, NEW_LIST(rhs, &rhs->nd_loc), loc);
            if (shareable) {
                rhs = shareable_constant_value(p, shareable, lhs, rhs, &rhs->nd_loc);
            }
            set_nd_value(p, asgn, rhs);
            nd_set_loc(asgn, loc);
        }
    }
    else {
        asgn = NEW_BEGIN(0, loc);
    }
    return asgn;
}

static NODE *
new_ary_op_assign(struct parser_params *p, NODE *ary,
                  NODE *args, ID op, NODE *rhs, const YYLTYPE *args_loc, const YYLTYPE *loc)
{
    NODE *asgn;

    args = make_list(args, args_loc);
    asgn = NEW_OP_ASGN1(ary, op, args, rhs, loc);
    fixpos(asgn, ary);
    return asgn;
}

static NODE *
new_attr_op_assign(struct parser_params *p, NODE *lhs,
                   ID atype, ID attr, ID op, NODE *rhs, const YYLTYPE *loc)
{
    NODE *asgn;

    asgn = NEW_OP_ASGN2(lhs, CALL_Q_P(atype), attr, op, rhs, loc);
    fixpos(asgn, lhs);
    return asgn;
}

static NODE *
new_const_op_assign(struct parser_params *p, NODE *lhs, ID op, NODE *rhs, struct lex_context ctxt, const YYLTYPE *loc)
{
    NODE *asgn;

    if (lhs) {
        rhs = shareable_constant_value(p, ctxt.shareable_constant_value, lhs, rhs, loc);
        asgn = NEW_OP_CDECL(lhs, op, rhs, loc);
    }
    else {
        asgn = NEW_BEGIN(0, loc);
    }
    fixpos(asgn, lhs);
    return asgn;
}

static NODE *
const_decl(struct parser_params *p, NODE *path, const YYLTYPE *loc)
{
    if (p->ctxt.in_def) {
        yyerror1(loc, "dynamic constant assignment");
    }
    return NEW_CDECL(0, 0, (path), loc);
}
#else
static VALUE
const_decl(struct parser_params *p, VALUE path)
{
    if (p->ctxt.in_def) {
        path = assign_error(p, "dynamic constant assignment", path);
    }
    return path;
}

static VALUE
assign_error(struct parser_params *p, const char *mesg, VALUE a)
{
    a = dispatch2(assign_error, ERR_MESG(), a);
    ripper_error(p);
    return a;
}

static VALUE
var_field(struct parser_params *p, VALUE a)
{
    return ripper_new_yylval(p, get_id(a), dispatch1(var_field, a), 0);
}
#endif

#ifndef RIPPER
static NODE *
new_bodystmt(struct parser_params *p, NODE *head, NODE *rescue, NODE *rescue_else, NODE *ensure, const YYLTYPE *loc)
{
    NODE *result = head;
    if (rescue) {
        NODE *tmp = rescue_else ? rescue_else : rescue;
        YYLTYPE rescue_loc = code_loc_gen(&head->nd_loc, &tmp->nd_loc);

        result = NEW_RESCUE(head, rescue, rescue_else, &rescue_loc);
        nd_set_line(result, rescue->nd_loc.beg_pos.lineno);
    }
    else if (rescue_else) {
        result = block_append(p, result, rescue_else);
    }
    if (ensure) {
        result = NEW_ENSURE(result, ensure, loc);
    }
    fixpos(result, head);
    return result;
}
#endif

static void
warn_unused_var(struct parser_params *p, struct local_vars *local)
{
    int cnt;

    if (!local->used) return;
    cnt = local->used->pos;
    if (cnt != local->vars->pos) {
        rb_parser_fatal(p, "local->used->pos != local->vars->pos");
    }
#ifndef RIPPER
    ID *v = local->vars->tbl;
    ID *u = local->used->tbl;
    for (int i = 0; i < cnt; ++i) {
        if (!v[i] || (u[i] & LVAR_USED)) continue;
        if (is_private_local_id(p, v[i])) continue;
        rb_warn1L((int)u[i], "assigned but unused variable - %"PRIsWARN, rb_id2str(v[i]));
    }
#endif
}

static void
local_push(struct parser_params *p, int toplevel_scope)
{
    struct local_vars *local;
    int inherits_dvars = toplevel_scope && compile_for_eval;
    int warn_unused_vars = RTEST(ruby_verbose);

    local = ALLOC(struct local_vars);
    local->prev = p->lvtbl;
    local->args = vtable_alloc(0);
    local->vars = vtable_alloc(inherits_dvars ? DVARS_INHERIT : DVARS_TOPSCOPE);
#ifndef RIPPER
    if (toplevel_scope && compile_for_eval) warn_unused_vars = 0;
    if (toplevel_scope && e_option_supplied(p)) warn_unused_vars = 0;
    local->numparam.outer = 0;
    local->numparam.inner = 0;
    local->numparam.current = 0;
#endif
    local->used = warn_unused_vars ? vtable_alloc(0) : 0;

# if WARN_PAST_SCOPE
    local->past = 0;
# endif
    CMDARG_PUSH(0);
    COND_PUSH(0);
    p->lvtbl = local;
}

static void
vtable_chain_free(struct parser_params *p, struct vtable *table)
{
    while (!DVARS_TERMINAL_P(table)) {
        struct vtable *cur_table = table;
        table = cur_table->prev;
        vtable_free(cur_table);
    }
}

static void
local_free(struct parser_params *p, struct local_vars *local)
{
    vtable_chain_free(p, local->used);

# if WARN_PAST_SCOPE
    vtable_chain_free(p, local->past);
# endif

    vtable_chain_free(p, local->args);
    vtable_chain_free(p, local->vars);

    ruby_sized_xfree(local, sizeof(struct local_vars));
}

static void
local_pop(struct parser_params *p)
{
    struct local_vars *local = p->lvtbl->prev;
    if (p->lvtbl->used) {
        warn_unused_var(p, p->lvtbl);
    }

    local_free(p, p->lvtbl);
    p->lvtbl = local;

    CMDARG_POP();
    COND_POP();
}

#ifndef RIPPER
static rb_ast_id_table_t *
local_tbl(struct parser_params *p)
{
    int cnt_args = vtable_size(p->lvtbl->args);
    int cnt_vars = vtable_size(p->lvtbl->vars);
    int cnt = cnt_args + cnt_vars;
    int i, j;
    rb_ast_id_table_t *tbl;

    if (cnt <= 0) return 0;
    tbl = rb_ast_new_local_table(p->ast, cnt);
    MEMCPY(tbl->ids, p->lvtbl->args->tbl, ID, cnt_args);
    /* remove IDs duplicated to warn shadowing */
    for (i = 0, j = cnt_args; i < cnt_vars; ++i) {
        ID id = p->lvtbl->vars->tbl[i];
        if (!vtable_included(p->lvtbl->args, id)) {
            tbl->ids[j++] = id;
        }
    }
    if (j < cnt) {
        tbl = rb_ast_resize_latest_local_table(p->ast, j);
    }

    return tbl;
}

#endif

static void
numparam_name(struct parser_params *p, ID id)
{
    if (!NUMPARAM_ID_P(id)) return;
    compile_error(p, "_%d is reserved for numbered parameter",
        NUMPARAM_ID_TO_IDX(id));
}

static void
arg_var(struct parser_params *p, ID id)
{
    numparam_name(p, id);
    vtable_add(p->lvtbl->args, id);
}

static void
local_var(struct parser_params *p, ID id)
{
    numparam_name(p, id);
    vtable_add(p->lvtbl->vars, id);
    if (p->lvtbl->used) {
        vtable_add(p->lvtbl->used, (ID)p->ruby_sourceline);
    }
}

static int
local_id_ref(struct parser_params *p, ID id, ID **vidrefp)
{
    struct vtable *vars, *args, *used;

    vars = p->lvtbl->vars;
    args = p->lvtbl->args;
    used = p->lvtbl->used;

    while (vars && !DVARS_TERMINAL_P(vars->prev)) {
        vars = vars->prev;
        args = args->prev;
        if (used) used = used->prev;
    }

    if (vars && vars->prev == DVARS_INHERIT) {
        return rb_local_defined(id, p->parent_iseq);
    }
    else if (vtable_included(args, id)) {
        return 1;
    }
    else {
        int i = vtable_included(vars, id);
        if (i && used && vidrefp) *vidrefp = &used->tbl[i-1];
        return i != 0;
    }
}

static int
local_id(struct parser_params *p, ID id)
{
    return local_id_ref(p, id, NULL);
}

static int
check_forwarding_args(struct parser_params *p)
{
    if (local_id(p, idFWD_ALL)) return TRUE;
    compile_error(p, "unexpected ...");
    return FALSE;
}

static void
add_forwarding_args(struct parser_params *p)
{
    arg_var(p, idFWD_REST);
#ifndef FORWARD_ARGS_WITH_RUBY2_KEYWORDS
    arg_var(p, idFWD_KWREST);
#endif
    arg_var(p, idFWD_BLOCK);
    arg_var(p, idFWD_ALL);
}

static void
forwarding_arg_check(struct parser_params *p, ID arg, ID all, const char *var)
{
    bool conflict = false;

    struct vtable *vars, *args;

    vars = p->lvtbl->vars;
    args = p->lvtbl->args;

    while (vars && !DVARS_TERMINAL_P(vars->prev)) {
        vars = vars->prev;
        args = args->prev;
        conflict |= (vtable_included(args, arg) && !(all && vtable_included(args, all)));
    }

    bool found = false;
    if (vars && vars->prev == DVARS_INHERIT) {
        found = (rb_local_defined(arg, p->parent_iseq) &&
                 !(all && rb_local_defined(all, p->parent_iseq)));
    }
    else {
        found = (vtable_included(args, arg) &&
                 !(all && vtable_included(args, all)));
    }

    if (!found) {
        compile_error(p, "no anonymous %s parameter", var);
    }
    else if (conflict) {
        compile_error(p, "anonymous %s parameter is also used within block", var);
    }
}

#ifndef RIPPER
static NODE *
new_args_forward_call(struct parser_params *p, NODE *leading, const YYLTYPE *loc, const YYLTYPE *argsloc)
{
    NODE *rest = NEW_LVAR(idFWD_REST, loc);
#ifndef FORWARD_ARGS_WITH_RUBY2_KEYWORDS
    NODE *kwrest = list_append(p, NEW_LIST(0, loc), NEW_LVAR(idFWD_KWREST, loc));
#endif
    rb_node_block_pass_t *block = NEW_BLOCK_PASS(NEW_LVAR(idFWD_BLOCK, loc), loc);
    NODE *args = leading ? rest_arg_append(p, leading, rest, argsloc) : NEW_SPLAT(rest, loc);
#ifndef FORWARD_ARGS_WITH_RUBY2_KEYWORDS
    args = arg_append(p, args, new_hash(p, kwrest, loc), loc);
#endif
    return arg_blk_pass(args, block);
}
#endif

static NODE *
numparam_push(struct parser_params *p)
{
#ifndef RIPPER
    struct local_vars *local = p->lvtbl;
    NODE *inner = local->numparam.inner;
    if (!local->numparam.outer) {
        local->numparam.outer = local->numparam.current;
    }
    local->numparam.inner = 0;
    local->numparam.current = 0;
    return inner;
#else
    return 0;
#endif
}

static void
numparam_pop(struct parser_params *p, NODE *prev_inner)
{
#ifndef RIPPER
    struct local_vars *local = p->lvtbl;
    if (prev_inner) {
        /* prefer first one */
        local->numparam.inner = prev_inner;
    }
    else if (local->numparam.current) {
        /* current and inner are exclusive */
        local->numparam.inner = local->numparam.current;
    }
    if (p->max_numparam > NO_PARAM) {
        /* current and outer are exclusive */
        local->numparam.current = local->numparam.outer;
        local->numparam.outer = 0;
    }
    else {
        /* no numbered parameter */
        local->numparam.current = 0;
    }
#endif
}

static const struct vtable *
dyna_push(struct parser_params *p)
{
    p->lvtbl->args = vtable_alloc(p->lvtbl->args);
    p->lvtbl->vars = vtable_alloc(p->lvtbl->vars);
    if (p->lvtbl->used) {
        p->lvtbl->used = vtable_alloc(p->lvtbl->used);
    }
    return p->lvtbl->args;
}

static void
dyna_pop_vtable(struct parser_params *p, struct vtable **vtblp)
{
    struct vtable *tmp = *vtblp;
    *vtblp = tmp->prev;
# if WARN_PAST_SCOPE
    if (p->past_scope_enabled) {
        tmp->prev = p->lvtbl->past;
        p->lvtbl->past = tmp;
        return;
    }
# endif
    vtable_free(tmp);
}

static void
dyna_pop_1(struct parser_params *p)
{
    struct vtable *tmp;

    if ((tmp = p->lvtbl->used) != 0) {
        warn_unused_var(p, p->lvtbl);
        p->lvtbl->used = p->lvtbl->used->prev;
        vtable_free(tmp);
    }
    dyna_pop_vtable(p, &p->lvtbl->args);
    dyna_pop_vtable(p, &p->lvtbl->vars);
}

static void
dyna_pop(struct parser_params *p, const struct vtable *lvargs)
{
    while (p->lvtbl->args != lvargs) {
        dyna_pop_1(p);
        if (!p->lvtbl->args) {
            struct local_vars *local = p->lvtbl->prev;
            ruby_sized_xfree(p->lvtbl, sizeof(*p->lvtbl));
            p->lvtbl = local;
        }
    }
    dyna_pop_1(p);
}

static int
dyna_in_block(struct parser_params *p)
{
    return !DVARS_TERMINAL_P(p->lvtbl->vars) && p->lvtbl->vars->prev != DVARS_TOPSCOPE;
}

static int
dvar_defined_ref(struct parser_params *p, ID id, ID **vidrefp)
{
    struct vtable *vars, *args, *used;
    int i;

    args = p->lvtbl->args;
    vars = p->lvtbl->vars;
    used = p->lvtbl->used;

    while (!DVARS_TERMINAL_P(vars)) {
        if (vtable_included(args, id)) {
            return 1;
        }
        if ((i = vtable_included(vars, id)) != 0) {
            if (used && vidrefp) *vidrefp = &used->tbl[i-1];
            return 1;
        }
        args = args->prev;
        vars = vars->prev;
        if (!vidrefp) used = 0;
        if (used) used = used->prev;
    }

    if (vars == DVARS_INHERIT && !NUMPARAM_ID_P(id)) {
        return rb_dvar_defined(id, p->parent_iseq);
    }

    return 0;
}

static int
dvar_defined(struct parser_params *p, ID id)
{
    return dvar_defined_ref(p, id, NULL);
}

static int
dvar_curr(struct parser_params *p, ID id)
{
    return (vtable_included(p->lvtbl->args, id) ||
            vtable_included(p->lvtbl->vars, id));
}

static void
reg_fragment_enc_error(struct parser_params* p, VALUE str, int c)
{
    compile_error(p,
        "regexp encoding option '%c' differs from source encoding '%s'",
        c, rb_enc_name(rb_enc_get(str)));
}

#ifndef RIPPER
int
rb_reg_fragment_setenc(struct parser_params* p, VALUE str, int options)
{
    int c = RE_OPTION_ENCODING_IDX(options);

    if (c) {
        int opt, idx;
        rb_char_to_option_kcode(c, &opt, &idx);
        if (idx != ENCODING_GET(str) &&
            !is_ascii_string(str)) {
            goto error;
        }
        ENCODING_SET(str, idx);
    }
    else if (RE_OPTION_ENCODING_NONE(options)) {
        if (!ENCODING_IS_ASCII8BIT(str) &&
            !is_ascii_string(str)) {
            c = 'n';
            goto error;
        }
        rb_enc_associate(str, rb_ascii8bit_encoding());
    }
    else if (rb_is_usascii_enc(p->enc)) {
        if (!is_ascii_string(str)) {
            /* raise in re.c */
            rb_enc_associate(str, rb_usascii_encoding());
        }
        else {
            rb_enc_associate(str, rb_ascii8bit_encoding());
        }
    }
    return 0;

  error:
    return c;
}

static void
reg_fragment_setenc(struct parser_params* p, VALUE str, int options)
{
    int c = rb_reg_fragment_setenc(p, str, options);
    if (c) reg_fragment_enc_error(p, str, c);
}

static int
reg_fragment_check(struct parser_params* p, VALUE str, int options)
{
    VALUE err;
    reg_fragment_setenc(p, str, options);
    err = rb_reg_check_preprocess(str);
    if (err != Qnil) {
        err = rb_obj_as_string(err);
        compile_error(p, "%"PRIsVALUE, err);
        return 0;
    }
    return 1;
}

#ifndef UNIVERSAL_PARSER
typedef struct {
    struct parser_params* parser;
    rb_encoding *enc;
    NODE *succ_block;
    const YYLTYPE *loc;
} reg_named_capture_assign_t;

static int
reg_named_capture_assign_iter(const OnigUChar *name, const OnigUChar *name_end,
          int back_num, int *back_refs, OnigRegex regex, void *arg0)
{
    reg_named_capture_assign_t *arg = (reg_named_capture_assign_t*)arg0;
    struct parser_params* p = arg->parser;
    rb_encoding *enc = arg->enc;
    long len = name_end - name;
    const char *s = (const char *)name;

    return rb_reg_named_capture_assign_iter_impl(p, s, len, enc, &arg->succ_block, arg->loc);
}

static NODE *
reg_named_capture_assign(struct parser_params* p, VALUE regexp, const YYLTYPE *loc)
{
    reg_named_capture_assign_t arg;

    arg.parser = p;
    arg.enc = rb_enc_get(regexp);
    arg.succ_block = 0;
    arg.loc = loc;
    onig_foreach_name(RREGEXP_PTR(regexp), reg_named_capture_assign_iter, &arg);

    if (!arg.succ_block) return 0;
    return RNODE_BLOCK(arg.succ_block)->nd_next;
}
#endif

int
rb_reg_named_capture_assign_iter_impl(struct parser_params *p, const char *s, long len,
          rb_encoding *enc, NODE **succ_block, const rb_code_location_t *loc)
{
    ID var;
    NODE *node, *succ;

    if (!len) return ST_CONTINUE;
    if (!VALID_SYMNAME_P(s, len, enc, ID_LOCAL))
        return ST_CONTINUE;

    var = intern_cstr(s, len, enc);
    if (len < MAX_WORD_LENGTH && rb_reserved_word(s, (int)len)) {
        if (!lvar_defined(p, var)) return ST_CONTINUE;
    }
    node = node_assign(p, assignable(p, var, 0, loc), NEW_LIT(ID2SYM(var), loc), NO_LEX_CTXT, loc);
    succ = *succ_block;
    if (!succ) succ = NEW_BEGIN(0, loc);
    succ = block_append(p, succ, node);
    *succ_block = succ;
    return ST_CONTINUE;
}

static VALUE
parser_reg_compile(struct parser_params* p, VALUE str, int options)
{
    reg_fragment_setenc(p, str, options);
    return rb_parser_reg_compile(p, str, options);
}

VALUE
rb_parser_reg_compile(struct parser_params* p, VALUE str, int options)
{
    return rb_reg_compile(str, options & RE_OPTION_MASK, p->ruby_sourcefile, p->ruby_sourceline);
}

static VALUE
reg_compile(struct parser_params* p, VALUE str, int options)
{
    VALUE re;
    VALUE err;

    err = rb_errinfo();
    re = parser_reg_compile(p, str, options);
    if (NIL_P(re)) {
        VALUE m = rb_attr_get(rb_errinfo(), idMesg);
        rb_set_errinfo(err);
        compile_error(p, "%"PRIsVALUE, m);
        return Qnil;
    }
    return re;
}
#else
static VALUE
parser_reg_compile(struct parser_params* p, VALUE str, int options, VALUE *errmsg)
{
    VALUE err = rb_errinfo();
    VALUE re;
    str = ripper_is_node_yylval(p, str) ? RNODE_RIPPER(str)->nd_cval : str;
    int c = rb_reg_fragment_setenc(p, str, options);
    if (c) reg_fragment_enc_error(p, str, c);
    re = rb_parser_reg_compile(p, str, options);
    if (NIL_P(re)) {
        *errmsg = rb_attr_get(rb_errinfo(), idMesg);
        rb_set_errinfo(err);
    }
    return re;
}
#endif

#ifndef RIPPER
void
rb_ruby_parser_set_options(struct parser_params *p, int print, int loop, int chomp, int split)
{
    p->do_print = print;
    p->do_loop = loop;
    p->do_chomp = chomp;
    p->do_split = split;
}

static NODE *
parser_append_options(struct parser_params *p, NODE *node)
{
    static const YYLTYPE default_location = {{1, 0}, {1, 0}};
    const YYLTYPE *const LOC = &default_location;

    if (p->do_print) {
        NODE *print = (NODE *)NEW_FCALL(rb_intern("print"),
                                NEW_LIST(NEW_GVAR(idLASTLINE, LOC), LOC),
                                LOC);
        node = block_append(p, node, print);
    }

    if (p->do_loop) {
        NODE *irs = NEW_LIST(NEW_GVAR(rb_intern("$/"), LOC), LOC);

        if (p->do_split) {
            ID ifs = rb_intern("$;");
            ID fields = rb_intern("$F");
            NODE *args = NEW_LIST(NEW_GVAR(ifs, LOC), LOC);
            NODE *split = NEW_GASGN(fields,
                                    NEW_CALL(NEW_GVAR(idLASTLINE, LOC),
                                             rb_intern("split"), args, LOC),
                                    LOC);
            node = block_append(p, split, node);
        }
        if (p->do_chomp) {
            NODE *chomp = NEW_LIT(ID2SYM(rb_intern("chomp")), LOC);
            chomp = list_append(p, NEW_LIST(chomp, LOC), NEW_TRUE(LOC));
            irs = list_append(p, irs, NEW_HASH(chomp, LOC));
        }

        node = NEW_WHILE((NODE *)NEW_FCALL(idGets, irs, LOC), node, 1, LOC);
    }

    return node;
}

void
rb_init_parse(void)
{
    /* just to suppress unused-function warnings */
    (void)nodetype;
    (void)nodeline;
}

static ID
internal_id(struct parser_params *p)
{
    return rb_make_temporary_id(vtable_size(p->lvtbl->args) + vtable_size(p->lvtbl->vars));
}
#endif /* !RIPPER */

static void
parser_initialize(struct parser_params *p)
{
    /* note: we rely on TypedData_Make_Struct to set most fields to 0 */
    p->command_start = TRUE;
    p->ruby_sourcefile_string = Qnil;
    p->lex.lpar_beg = -1; /* make lambda_beginning_p() == FALSE at first */
    p->node_id = 0;
    p->delayed.token = Qnil;
    p->frozen_string_literal = -1; /* not specified */
#ifdef RIPPER
    p->result = Qnil;
    p->parsing_thread = Qnil;
#else
    p->error_buffer = Qfalse;
    p->end_expect_token_locations = Qnil;
    p->token_id = 0;
    p->tokens = Qnil;
#endif
    p->debug_buffer = Qnil;
    p->debug_output = rb_ractor_stdout();
    p->enc = rb_utf8_encoding();
    p->exits = 0;
}

#ifdef RIPPER
#define rb_ruby_parser_mark ripper_parser_mark
#define rb_ruby_parser_free ripper_parser_free
#define rb_ruby_parser_memsize ripper_parser_memsize
#endif

void
rb_ruby_parser_mark(void *ptr)
{
    struct parser_params *p = (struct parser_params*)ptr;

    rb_gc_mark(p->lex.input);
    rb_gc_mark(p->lex.lastline);
    rb_gc_mark(p->lex.nextline);
    rb_gc_mark(p->ruby_sourcefile_string);
    rb_gc_mark((VALUE)p->ast);
    rb_gc_mark(p->case_labels);
    rb_gc_mark(p->delayed.token);
#ifndef RIPPER
    rb_gc_mark(p->debug_lines);
    rb_gc_mark(p->error_buffer);
    rb_gc_mark(p->end_expect_token_locations);
    rb_gc_mark(p->tokens);
#else
    rb_gc_mark(p->value);
    rb_gc_mark(p->result);
    rb_gc_mark(p->parsing_thread);
#endif
    rb_gc_mark(p->debug_buffer);
    rb_gc_mark(p->debug_output);
#ifdef YYMALLOC
    rb_gc_mark((VALUE)p->heap);
#endif
}

void
rb_ruby_parser_free(void *ptr)
{
    struct parser_params *p = (struct parser_params*)ptr;
    struct local_vars *local, *prev;
#ifdef UNIVERSAL_PARSER
    rb_parser_config_t *config = p->config;
#endif

    if (p->tokenbuf) {
        ruby_sized_xfree(p->tokenbuf, p->toksiz);
    }

    for (local = p->lvtbl; local; local = prev) {
        prev = local->prev;
        local_free(p, local);
    }

    {
        token_info *ptinfo;
        while ((ptinfo = p->token_info) != 0) {
            p->token_info = ptinfo->next;
            xfree(ptinfo);
        }
    }
    xfree(ptr);

#ifdef UNIVERSAL_PARSER
    config->counter--;
    if (config->counter <= 0) {
        rb_ruby_parser_config_free(config);
    }
#endif
}

size_t
rb_ruby_parser_memsize(const void *ptr)
{
    struct parser_params *p = (struct parser_params*)ptr;
    struct local_vars *local;
    size_t size = sizeof(*p);

    size += p->toksiz;
    for (local = p->lvtbl; local; local = local->prev) {
        size += sizeof(*local);
        if (local->vars) size += local->vars->capa * sizeof(ID);
    }
    return size;
}

#ifdef UNIVERSAL_PARSER
rb_parser_config_t *
rb_ruby_parser_config_new(void *(*malloc)(size_t size))
{
    return (rb_parser_config_t *)malloc(sizeof(rb_parser_config_t));
}

void
rb_ruby_parser_config_free(rb_parser_config_t *config)
{
    config->free(config);
}
#endif

#ifndef UNIVERSAL_PARSER
#ifndef RIPPER
static const rb_data_type_t parser_data_type = {
    "parser",
    {
        rb_ruby_parser_mark,
        rb_ruby_parser_free,
        rb_ruby_parser_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};
#endif
#endif

#ifndef RIPPER
#undef rb_reserved_word

const struct kwtable *
rb_reserved_word(const char *str, unsigned int len)
{
    return reserved_word(str, len);
}

#ifdef UNIVERSAL_PARSER
rb_parser_t *
rb_ruby_parser_allocate(rb_parser_config_t *config)
{
    /* parser_initialize expects fields to be set to 0 */
    rb_parser_t *p = (rb_parser_t *)config->calloc(1, sizeof(rb_parser_t));
    p->config = config;
    p->config->counter++;
    return p;
}

rb_parser_t *
rb_ruby_parser_new(rb_parser_config_t *config)
{
    /* parser_initialize expects fields to be set to 0 */
    rb_parser_t *p = rb_ruby_parser_allocate(config);
    parser_initialize(p);
    return p;
}
#endif

rb_parser_t *
rb_ruby_parser_set_context(rb_parser_t *p, const struct rb_iseq_struct *base, int main)
{
    p->error_buffer = main ? Qfalse : Qnil;
    p->parent_iseq = base;
    return p;
}

void
rb_ruby_parser_set_script_lines(rb_parser_t *p, VALUE lines)
{
    if (!RTEST(lines)) {
        lines = Qfalse;
    }
    else if (lines == Qtrue) {
        lines = rb_ary_new();
    }
    else {
        Check_Type(lines, T_ARRAY);
        rb_ary_modify(lines);
    }
    p->debug_lines = lines;
}

void
rb_ruby_parser_error_tolerant(rb_parser_t *p)
{
    p->error_tolerant = 1;
    // TODO
    p->end_expect_token_locations = rb_ary_new();
}

void
rb_ruby_parser_keep_tokens(rb_parser_t *p)
{
    p->keep_tokens = 1;
    // TODO
    p->tokens = rb_ary_new();
}

#ifndef UNIVERSAL_PARSER
rb_ast_t*
rb_parser_compile_file_path(VALUE vparser, VALUE fname, VALUE file, int start)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    RB_GC_GUARD(vparser); /* prohibit tail call optimization */
    return rb_ruby_parser_compile_file_path(p, fname, file, start);
}

rb_ast_t*
rb_parser_compile_generic(VALUE vparser, VALUE (*lex_gets)(VALUE, int), VALUE fname, VALUE input, int start)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    RB_GC_GUARD(vparser); /* prohibit tail call optimization */
    return rb_ruby_parser_compile_generic(p, lex_gets, fname, input, start);
}

rb_ast_t*
rb_parser_compile_string(VALUE vparser, const char *f, VALUE s, int line)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    RB_GC_GUARD(vparser); /* prohibit tail call optimization */
    return rb_ruby_parser_compile_string(p, f, s, line);
}

rb_ast_t*
rb_parser_compile_string_path(VALUE vparser, VALUE f, VALUE s, int line)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    RB_GC_GUARD(vparser); /* prohibit tail call optimization */
    return rb_ruby_parser_compile_string_path(p, f, s, line);
}

VALUE
rb_parser_encoding(VALUE vparser)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    return rb_ruby_parser_encoding(p);
}

VALUE
rb_parser_end_seen_p(VALUE vparser)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    return RBOOL(rb_ruby_parser_end_seen_p(p));
}

void
rb_parser_error_tolerant(VALUE vparser)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    rb_ruby_parser_error_tolerant(p);
}

void
rb_parser_set_script_lines(VALUE vparser, VALUE lines)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    rb_ruby_parser_set_script_lines(p, lines);
}

void
rb_parser_keep_tokens(VALUE vparser)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    rb_ruby_parser_keep_tokens(p);
}

VALUE
rb_parser_new(void)
{
    struct parser_params *p;
    VALUE parser = TypedData_Make_Struct(0, struct parser_params,
                                         &parser_data_type, p);
    parser_initialize(p);
    return parser;
}

VALUE
rb_parser_set_context(VALUE vparser, const struct rb_iseq_struct *base, int main)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    rb_ruby_parser_set_context(p, base, main);
    return vparser;
}

void
rb_parser_set_options(VALUE vparser, int print, int loop, int chomp, int split)
{
    struct parser_params *p;

    TypedData_Get_Struct(vparser, struct parser_params, &parser_data_type, p);
    rb_ruby_parser_set_options(p, print, loop, chomp, split);
}

VALUE
rb_parser_set_yydebug(VALUE self, VALUE flag)
{
    struct parser_params *p;

    TypedData_Get_Struct(self, struct parser_params, &parser_data_type, p);
    rb_ruby_parser_set_yydebug(p, RTEST(flag));
    return flag;
}
#endif /* !UNIVERSAL_PARSER */

VALUE
rb_ruby_parser_encoding(rb_parser_t *p)
{
    return rb_enc_from_encoding(p->enc);
}

int
rb_ruby_parser_end_seen_p(rb_parser_t *p)
{
    return p->ruby__end__seen;
}

int
rb_ruby_parser_set_yydebug(rb_parser_t *p, int flag)
{
    p->debug = flag;
    return flag;
}
#endif /* !RIPPER */

#ifdef RIPPER
int
rb_ruby_parser_get_yydebug(rb_parser_t *p)
{
    return p->debug;
}

void
rb_ruby_parser_set_value(rb_parser_t *p, VALUE value)
{
    p->value = value;
}

int
rb_ruby_parser_error_p(rb_parser_t *p)
{
    return p->error_p;
}

VALUE
rb_ruby_parser_debug_output(rb_parser_t *p)
{
    return p->debug_output;
}

void
rb_ruby_parser_set_debug_output(rb_parser_t *p, VALUE output)
{
    p->debug_output = output;
}

VALUE
rb_ruby_parser_parsing_thread(rb_parser_t *p)
{
    return p->parsing_thread;
}

void
rb_ruby_parser_set_parsing_thread(rb_parser_t *p, VALUE parsing_thread)
{
    p->parsing_thread = parsing_thread;
}

void
rb_ruby_parser_ripper_initialize(rb_parser_t *p, VALUE (*gets)(struct parser_params*,VALUE), VALUE input, VALUE sourcefile_string, const char *sourcefile, int sourceline)
{
    p->lex.gets = gets;
    p->lex.input = input;
    p->eofp = 0;
    p->ruby_sourcefile_string = sourcefile_string;
    p->ruby_sourcefile = sourcefile;
    p->ruby_sourceline = sourceline;
}

VALUE
rb_ruby_parser_result(rb_parser_t *p)
{
    return p->result;
}

rb_encoding *
rb_ruby_parser_enc(rb_parser_t *p)
{
    return p->enc;
}

VALUE
rb_ruby_parser_ruby_sourcefile_string(rb_parser_t *p)
{
    return p->ruby_sourcefile_string;
}

int
rb_ruby_parser_ruby_sourceline(rb_parser_t *p)
{
    return p->ruby_sourceline;
}

int
rb_ruby_parser_lex_state(rb_parser_t *p)
{
    return p->lex.state;
}

void
rb_ruby_ripper_parse0(rb_parser_t *p)
{
    parser_prepare(p);
    p->ast = rb_ast_new();
    ripper_yyparse((void*)p);
    rb_ast_dispose(p->ast);
    p->ast = 0;
}

int
rb_ruby_ripper_dedent_string(rb_parser_t *p, VALUE string, int width)
{
    return dedent_string(p, string, width);
}

VALUE
rb_ruby_ripper_lex_get_str(rb_parser_t *p, VALUE s)
{
    return lex_get_str(p, s);
}

int
rb_ruby_ripper_initialized_p(rb_parser_t *p)
{
    return p->lex.input != 0;
}

void
rb_ruby_ripper_parser_initialize(rb_parser_t *p)
{
    parser_initialize(p);
}

long
rb_ruby_ripper_column(rb_parser_t *p)
{
    return p->lex.ptok - p->lex.pbeg;
}

long
rb_ruby_ripper_token_len(rb_parser_t *p)
{
    return p->lex.pcur - p->lex.ptok;
}

VALUE
rb_ruby_ripper_lex_lastline(rb_parser_t *p)
{
    return p->lex.lastline;
}

VALUE
rb_ruby_ripper_lex_state_name(struct parser_params *p, int state)
{
    return rb_parser_lex_state_name(p, (enum lex_state_e)state);
}

struct parser_params*
rb_ruby_ripper_parser_allocate(void)
{
    return (struct parser_params *)ruby_xcalloc(1, sizeof(struct parser_params));
}
#endif /* RIPPER */

#ifndef RIPPER
#ifdef YYMALLOC
#define HEAPCNT(n, size) ((n) * (size) / sizeof(YYSTYPE))
/* Keep the order; NEWHEAP then xmalloc and ADD2HEAP to get rid of
 * potential memory leak */
#define NEWHEAP() rb_imemo_tmpbuf_parser_heap(0, p->heap, 0)
#define ADD2HEAP(new, cnt, ptr) ((p->heap = (new))->ptr = (ptr), \
                           (new)->cnt = (cnt), (ptr))

void *
rb_parser_malloc(struct parser_params *p, size_t size)
{
    size_t cnt = HEAPCNT(1, size);
    rb_imemo_tmpbuf_t *n = NEWHEAP();
    void *ptr = xmalloc(size);

    return ADD2HEAP(n, cnt, ptr);
}

void *
rb_parser_calloc(struct parser_params *p, size_t nelem, size_t size)
{
    size_t cnt = HEAPCNT(nelem, size);
    rb_imemo_tmpbuf_t *n = NEWHEAP();
    void *ptr = xcalloc(nelem, size);

    return ADD2HEAP(n, cnt, ptr);
}

void *
rb_parser_realloc(struct parser_params *p, void *ptr, size_t size)
{
    rb_imemo_tmpbuf_t *n;
    size_t cnt = HEAPCNT(1, size);

    if (ptr && (n = p->heap) != NULL) {
        do {
            if (n->ptr == ptr) {
                n->ptr = ptr = xrealloc(ptr, size);
                if (n->cnt) n->cnt = cnt;
                return ptr;
            }
        } while ((n = n->next) != NULL);
    }
    n = NEWHEAP();
    ptr = xrealloc(ptr, size);
    return ADD2HEAP(n, cnt, ptr);
}

void
rb_parser_free(struct parser_params *p, void *ptr)
{
    rb_imemo_tmpbuf_t **prev = &p->heap, *n;

    while ((n = *prev) != NULL) {
        if (n->ptr == ptr) {
            *prev = n->next;
            break;
        }
        prev = &n->next;
    }
}
#endif

void
rb_parser_printf(struct parser_params *p, const char *fmt, ...)
{
    va_list ap;
    VALUE mesg = p->debug_buffer;

    if (NIL_P(mesg)) p->debug_buffer = mesg = rb_str_new(0, 0);
    va_start(ap, fmt);
    rb_str_vcatf(mesg, fmt, ap);
    va_end(ap);
    if (end_with_newline_p(p, mesg)) {
        rb_io_write(p->debug_output, mesg);
        p->debug_buffer = Qnil;
    }
}

static void
parser_compile_error(struct parser_params *p, const rb_code_location_t *loc, const char *fmt, ...)
{
    va_list ap;
    int lineno, column;

    if (loc) {
        lineno = loc->end_pos.lineno;
        column = loc->end_pos.column;
    }
    else {
        lineno = p->ruby_sourceline;
        column = rb_long2int(p->lex.pcur - p->lex.pbeg);
    }

    rb_io_flush(p->debug_output);
    p->error_p = 1;
    va_start(ap, fmt);
    p->error_buffer =
        rb_syntax_error_append(p->error_buffer,
                               p->ruby_sourcefile_string,
                               lineno, column,
                               p->enc, fmt, ap);
    va_end(ap);
}

static size_t
count_char(const char *str, int c)
{
    int n = 0;
    while (str[n] == c) ++n;
    return n;
}

/*
 * strip enclosing double-quotes, same as the default yytnamerr except
 * for that single-quotes matching back-quotes do not stop stripping.
 *
 *  "\"`class' keyword\"" => "`class' keyword"
 */
RUBY_FUNC_EXPORTED size_t
rb_yytnamerr(struct parser_params *p, char *yyres, const char *yystr)
{
    if (*yystr == '"') {
        size_t yyn = 0, bquote = 0;
        const char *yyp = yystr;

        while (*++yyp) {
            switch (*yyp) {
              case '`':
                if (!bquote) {
                    bquote = count_char(yyp+1, '`') + 1;
                    if (yyres) memcpy(&yyres[yyn], yyp, bquote);
                    yyn += bquote;
                    yyp += bquote - 1;
                    break;
                }
                goto default_char;

              case '\'':
                if (bquote && count_char(yyp+1, '\'') + 1 == bquote) {
                    if (yyres) memcpy(yyres + yyn, yyp, bquote);
                    yyn += bquote;
                    yyp += bquote - 1;
                    bquote = 0;
                    break;
                }
                if (yyp[1] && yyp[1] != '\'' && yyp[2] == '\'') {
                    if (yyres) memcpy(yyres + yyn, yyp, 3);
                    yyn += 3;
                    yyp += 2;
                    break;
                }
                goto do_not_strip_quotes;

              case ',':
                goto do_not_strip_quotes;

              case '\\':
                if (*++yyp != '\\')
                    goto do_not_strip_quotes;
                /* Fall through.  */
              default_char:
              default:
                if (yyres)
                    yyres[yyn] = *yyp;
                yyn++;
                break;

              case '"':
              case '\0':
                if (yyres)
                    yyres[yyn] = '\0';
                return yyn;
            }
        }
      do_not_strip_quotes: ;
    }

    if (!yyres) return strlen(yystr);

    return (YYSIZE_T)(yystpcpy(yyres, yystr) - yyres);
}
#endif

#ifdef RIPPER
#ifdef RIPPER_DEBUG
/* :nodoc: */
static VALUE
ripper_validate_object(VALUE self, VALUE x)
{
    if (x == Qfalse) return x;
    if (x == Qtrue) return x;
    if (NIL_P(x)) return x;
    if (UNDEF_P(x))
        rb_raise(rb_eArgError, "Qundef given");
    if (FIXNUM_P(x)) return x;
    if (SYMBOL_P(x)) return x;
    switch (BUILTIN_TYPE(x)) {
      case T_STRING:
      case T_OBJECT:
      case T_ARRAY:
      case T_BIGNUM:
      case T_FLOAT:
      case T_COMPLEX:
      case T_RATIONAL:
        break;
      case T_NODE:
        if (!nd_type_p((NODE *)x, NODE_RIPPER)) {
            rb_raise(rb_eArgError, "NODE given: %p", (void *)x);
        }
        x = ((NODE *)x)->nd_rval;
        break;
      default:
        rb_raise(rb_eArgError, "wrong type of ruby object: %p (%s)",
                 (void *)x, rb_obj_classname(x));
    }
    if (!RBASIC_CLASS(x)) {
        rb_raise(rb_eArgError, "hidden ruby object: %p (%s)",
                 (void *)x, rb_builtin_type_name(TYPE(x)));
    }
    return x;
}
#endif

#define validate(x) ((x) = get_value(x))

static VALUE
ripper_dispatch0(struct parser_params *p, ID mid)
{
    return rb_funcall(p->value, mid, 0);
}

static VALUE
ripper_dispatch1(struct parser_params *p, ID mid, VALUE a)
{
    validate(a);
    return rb_funcall(p->value, mid, 1, a);
}

static VALUE
ripper_dispatch2(struct parser_params *p, ID mid, VALUE a, VALUE b)
{
    validate(a);
    validate(b);
    return rb_funcall(p->value, mid, 2, a, b);
}

static VALUE
ripper_dispatch3(struct parser_params *p, ID mid, VALUE a, VALUE b, VALUE c)
{
    validate(a);
    validate(b);
    validate(c);
    return rb_funcall(p->value, mid, 3, a, b, c);
}

static VALUE
ripper_dispatch4(struct parser_params *p, ID mid, VALUE a, VALUE b, VALUE c, VALUE d)
{
    validate(a);
    validate(b);
    validate(c);
    validate(d);
    return rb_funcall(p->value, mid, 4, a, b, c, d);
}

static VALUE
ripper_dispatch5(struct parser_params *p, ID mid, VALUE a, VALUE b, VALUE c, VALUE d, VALUE e)
{
    validate(a);
    validate(b);
    validate(c);
    validate(d);
    validate(e);
    return rb_funcall(p->value, mid, 5, a, b, c, d, e);
}

static VALUE
ripper_dispatch7(struct parser_params *p, ID mid, VALUE a, VALUE b, VALUE c, VALUE d, VALUE e, VALUE f, VALUE g)
{
    validate(a);
    validate(b);
    validate(c);
    validate(d);
    validate(e);
    validate(f);
    validate(g);
    return rb_funcall(p->value, mid, 7, a, b, c, d, e, f, g);
}

void
ripper_error(struct parser_params *p)
{
    p->error_p = TRUE;
}

VALUE
ripper_value(struct parser_params *p)
{
    (void)yystpcpy; /* may not used in newer bison */

    return p->value;
}

#endif /* RIPPER */
/*
 * Local variables:
 * mode: c
 * c-file-style: "ruby"
 * End:
 */
