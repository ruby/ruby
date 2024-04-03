#ifndef INTERNAL_RUBY_PARSE_H
#define INTERNAL_RUBY_PARSE_H

#include "internal.h"
#include "internal/bignum.h"
#include "internal/compilers.h"
#include "internal/complex.h"
#include "internal/rational.h"
#include "rubyparser.h"
#include "vm.h"

RUBY_SYMBOL_EXPORT_BEGIN
#ifdef UNIVERSAL_PARSER
const rb_parser_config_t *rb_ruby_parser_config(void);
rb_parser_t *rb_parser_params_allocate(void);
rb_parser_t *rb_parser_params_new(void);
#endif
VALUE rb_parser_set_context(VALUE, const struct rb_iseq_struct *, int);
VALUE rb_parser_new(void);
rb_ast_t *rb_parser_compile_string_path(VALUE vparser, VALUE fname, VALUE src, int line);
VALUE rb_str_new_parser_string(rb_parser_string_t *str);

VALUE rb_node_str_string_val(const NODE *);
VALUE rb_node_sym_string_val(const NODE *);
VALUE rb_node_dstr_string_val(const NODE *);
VALUE rb_node_regx_string_val(const NODE *);
VALUE rb_node_dregx_string_val(const NODE *);
VALUE rb_node_line_lineno_val(const NODE *);
VALUE rb_node_file_path_val(const NODE *);
VALUE rb_node_encoding_val(const NODE *);

VALUE rb_node_integer_literal_val(const NODE *);
VALUE rb_node_float_literal_val(const NODE *);
VALUE rb_node_rational_literal_val(const NODE *);
VALUE rb_node_imaginary_literal_val(const NODE *);
RUBY_SYMBOL_EXPORT_END

VALUE rb_parser_end_seen_p(VALUE);
VALUE rb_parser_encoding(VALUE);
VALUE rb_parser_set_yydebug(VALUE, VALUE);
void rb_parser_set_options(VALUE, int, int, int, int);
void *rb_parser_load_file(VALUE parser, VALUE name);
void rb_parser_set_script_lines(VALUE vparser, VALUE lines_array);
void rb_parser_error_tolerant(VALUE vparser);
void rb_parser_keep_tokens(VALUE vparser);

rb_ast_t *rb_parser_compile_string(VALUE, const char*, VALUE, int);
rb_ast_t *rb_parser_compile_file_path(VALUE vparser, VALUE fname, VALUE input, int line);
rb_ast_t *rb_parser_compile_generic(VALUE vparser, VALUE (*lex_gets)(VALUE, int), VALUE fname, VALUE input, int line);

enum lex_state_bits {
    EXPR_BEG_bit,		/* ignore newline, +/- is a sign. */
    EXPR_END_bit,		/* newline significant, +/- is an operator. */
    EXPR_ENDARG_bit,		/* ditto, and unbound braces. */
    EXPR_ENDFN_bit,		/* ditto, and unbound braces. */
    EXPR_ARG_bit,		/* newline significant, +/- is an operator. */
    EXPR_CMDARG_bit,		/* newline significant, +/- is an operator. */
    EXPR_MID_bit,		/* newline significant, +/- is an operator. */
    EXPR_FNAME_bit,		/* ignore newline, no reserved words. */
    EXPR_DOT_bit,		/* right after `.', `&.' or `::', no reserved words. */
    EXPR_CLASS_bit,		/* immediate after `class', no here document. */
    EXPR_LABEL_bit,		/* flag bit, label is allowed. */
    EXPR_LABELED_bit,		/* flag bit, just after a label. */
    EXPR_FITEM_bit,		/* symbol literal as FNAME. */
    EXPR_MAX_STATE
};
/* examine combinations */
enum lex_state_e {
#define DEF_EXPR(n) EXPR_##n = (1 << EXPR_##n##_bit)
    DEF_EXPR(BEG),
    DEF_EXPR(END),
    DEF_EXPR(ENDARG),
    DEF_EXPR(ENDFN),
    DEF_EXPR(ARG),
    DEF_EXPR(CMDARG),
    DEF_EXPR(MID),
    DEF_EXPR(FNAME),
    DEF_EXPR(DOT),
    DEF_EXPR(CLASS),
    DEF_EXPR(LABEL),
    DEF_EXPR(LABELED),
    DEF_EXPR(FITEM),
    EXPR_VALUE = EXPR_BEG,
    EXPR_BEG_ANY  =  (EXPR_BEG | EXPR_MID | EXPR_CLASS),
    EXPR_ARG_ANY  =  (EXPR_ARG | EXPR_CMDARG),
    EXPR_END_ANY  =  (EXPR_END | EXPR_ENDARG | EXPR_ENDFN),
    EXPR_NONE = 0
};

#endif /* INTERNAL_RUBY_PARSE_H */
