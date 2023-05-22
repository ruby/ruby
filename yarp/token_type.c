/******************************************************************************/
/* This file is generated by the bin/template script and should not be        */
/* modified manually. See                                                     */
/* bin/templates/src/token_type.c.erb                                         */
/* if you are looking to modify the                                           */
/* template                                                                   */
/******************************************************************************/
#include <string.h>

#include "yarp/ast.h"

// Returns a string representation of the given token type.
__attribute__((__visibility__("default"))) const char *
yp_token_type_to_str(yp_token_type_t token_type)
{
  switch (token_type) {
    case YP_TOKEN_EOF:
      return "EOF";
    case YP_TOKEN_MISSING:
      return "MISSING";
    case YP_TOKEN_NOT_PROVIDED:
      return "NOT_PROVIDED";
    case YP_TOKEN_AMPERSAND:
      return "AMPERSAND";
    case YP_TOKEN_AMPERSAND_AMPERSAND:
      return "AMPERSAND_AMPERSAND";
    case YP_TOKEN_AMPERSAND_AMPERSAND_EQUAL:
      return "AMPERSAND_AMPERSAND_EQUAL";
    case YP_TOKEN_AMPERSAND_DOT:
      return "AMPERSAND_DOT";
    case YP_TOKEN_AMPERSAND_EQUAL:
      return "AMPERSAND_EQUAL";
    case YP_TOKEN_BACKTICK:
      return "BACKTICK";
    case YP_TOKEN_BACK_REFERENCE:
      return "BACK_REFERENCE";
    case YP_TOKEN_BANG:
      return "BANG";
    case YP_TOKEN_BANG_EQUAL:
      return "BANG_EQUAL";
    case YP_TOKEN_BANG_TILDE:
      return "BANG_TILDE";
    case YP_TOKEN_BRACE_LEFT:
      return "BRACE_LEFT";
    case YP_TOKEN_BRACE_RIGHT:
      return "BRACE_RIGHT";
    case YP_TOKEN_BRACKET_LEFT:
      return "BRACKET_LEFT";
    case YP_TOKEN_BRACKET_LEFT_ARRAY:
      return "BRACKET_LEFT_ARRAY";
    case YP_TOKEN_BRACKET_LEFT_RIGHT:
      return "BRACKET_LEFT_RIGHT";
    case YP_TOKEN_BRACKET_LEFT_RIGHT_EQUAL:
      return "BRACKET_LEFT_RIGHT_EQUAL";
    case YP_TOKEN_BRACKET_RIGHT:
      return "BRACKET_RIGHT";
    case YP_TOKEN_CARET:
      return "CARET";
    case YP_TOKEN_CARET_EQUAL:
      return "CARET_EQUAL";
    case YP_TOKEN_CHARACTER_LITERAL:
      return "CHARACTER_LITERAL";
    case YP_TOKEN_CLASS_VARIABLE:
      return "CLASS_VARIABLE";
    case YP_TOKEN_COLON:
      return "COLON";
    case YP_TOKEN_COLON_COLON:
      return "COLON_COLON";
    case YP_TOKEN_COMMA:
      return "COMMA";
    case YP_TOKEN_COMMENT:
      return "COMMENT";
    case YP_TOKEN_CONSTANT:
      return "CONSTANT";
    case YP_TOKEN_DOT:
      return "DOT";
    case YP_TOKEN_DOT_DOT:
      return "DOT_DOT";
    case YP_TOKEN_DOT_DOT_DOT:
      return "DOT_DOT_DOT";
    case YP_TOKEN_EMBDOC_BEGIN:
      return "EMBDOC_BEGIN";
    case YP_TOKEN_EMBDOC_END:
      return "EMBDOC_END";
    case YP_TOKEN_EMBDOC_LINE:
      return "EMBDOC_LINE";
    case YP_TOKEN_EMBEXPR_BEGIN:
      return "EMBEXPR_BEGIN";
    case YP_TOKEN_EMBEXPR_END:
      return "EMBEXPR_END";
    case YP_TOKEN_EMBVAR:
      return "EMBVAR";
    case YP_TOKEN_EQUAL:
      return "EQUAL";
    case YP_TOKEN_EQUAL_EQUAL:
      return "EQUAL_EQUAL";
    case YP_TOKEN_EQUAL_EQUAL_EQUAL:
      return "EQUAL_EQUAL_EQUAL";
    case YP_TOKEN_EQUAL_GREATER:
      return "EQUAL_GREATER";
    case YP_TOKEN_EQUAL_TILDE:
      return "EQUAL_TILDE";
    case YP_TOKEN_FLOAT:
      return "FLOAT";
    case YP_TOKEN_GLOBAL_VARIABLE:
      return "GLOBAL_VARIABLE";
    case YP_TOKEN_GREATER:
      return "GREATER";
    case YP_TOKEN_GREATER_EQUAL:
      return "GREATER_EQUAL";
    case YP_TOKEN_GREATER_GREATER:
      return "GREATER_GREATER";
    case YP_TOKEN_GREATER_GREATER_EQUAL:
      return "GREATER_GREATER_EQUAL";
    case YP_TOKEN_HEREDOC_END:
      return "HEREDOC_END";
    case YP_TOKEN_HEREDOC_START:
      return "HEREDOC_START";
    case YP_TOKEN_IDENTIFIER:
      return "IDENTIFIER";
    case YP_TOKEN_IGNORED_NEWLINE:
      return "IGNORED_NEWLINE";
    case YP_TOKEN_IMAGINARY_NUMBER:
      return "IMAGINARY_NUMBER";
    case YP_TOKEN_INSTANCE_VARIABLE:
      return "INSTANCE_VARIABLE";
    case YP_TOKEN_INTEGER:
      return "INTEGER";
    case YP_TOKEN_KEYWORD_ALIAS:
      return "KEYWORD_ALIAS";
    case YP_TOKEN_KEYWORD_AND:
      return "KEYWORD_AND";
    case YP_TOKEN_KEYWORD_BEGIN:
      return "KEYWORD_BEGIN";
    case YP_TOKEN_KEYWORD_BEGIN_UPCASE:
      return "KEYWORD_BEGIN_UPCASE";
    case YP_TOKEN_KEYWORD_BREAK:
      return "KEYWORD_BREAK";
    case YP_TOKEN_KEYWORD_CASE:
      return "KEYWORD_CASE";
    case YP_TOKEN_KEYWORD_CLASS:
      return "KEYWORD_CLASS";
    case YP_TOKEN_KEYWORD_DEF:
      return "KEYWORD_DEF";
    case YP_TOKEN_KEYWORD_DEFINED:
      return "KEYWORD_DEFINED";
    case YP_TOKEN_KEYWORD_DO:
      return "KEYWORD_DO";
    case YP_TOKEN_KEYWORD_DO_LOOP:
      return "KEYWORD_DO_LOOP";
    case YP_TOKEN_KEYWORD_ELSE:
      return "KEYWORD_ELSE";
    case YP_TOKEN_KEYWORD_ELSIF:
      return "KEYWORD_ELSIF";
    case YP_TOKEN_KEYWORD_END:
      return "KEYWORD_END";
    case YP_TOKEN_KEYWORD_END_UPCASE:
      return "KEYWORD_END_UPCASE";
    case YP_TOKEN_KEYWORD_ENSURE:
      return "KEYWORD_ENSURE";
    case YP_TOKEN_KEYWORD_FALSE:
      return "KEYWORD_FALSE";
    case YP_TOKEN_KEYWORD_FOR:
      return "KEYWORD_FOR";
    case YP_TOKEN_KEYWORD_IF:
      return "KEYWORD_IF";
    case YP_TOKEN_KEYWORD_IF_MODIFIER:
      return "KEYWORD_IF_MODIFIER";
    case YP_TOKEN_KEYWORD_IN:
      return "KEYWORD_IN";
    case YP_TOKEN_KEYWORD_MODULE:
      return "KEYWORD_MODULE";
    case YP_TOKEN_KEYWORD_NEXT:
      return "KEYWORD_NEXT";
    case YP_TOKEN_KEYWORD_NIL:
      return "KEYWORD_NIL";
    case YP_TOKEN_KEYWORD_NOT:
      return "KEYWORD_NOT";
    case YP_TOKEN_KEYWORD_OR:
      return "KEYWORD_OR";
    case YP_TOKEN_KEYWORD_REDO:
      return "KEYWORD_REDO";
    case YP_TOKEN_KEYWORD_RESCUE:
      return "KEYWORD_RESCUE";
    case YP_TOKEN_KEYWORD_RESCUE_MODIFIER:
      return "KEYWORD_RESCUE_MODIFIER";
    case YP_TOKEN_KEYWORD_RETRY:
      return "KEYWORD_RETRY";
    case YP_TOKEN_KEYWORD_RETURN:
      return "KEYWORD_RETURN";
    case YP_TOKEN_KEYWORD_SELF:
      return "KEYWORD_SELF";
    case YP_TOKEN_KEYWORD_SUPER:
      return "KEYWORD_SUPER";
    case YP_TOKEN_KEYWORD_THEN:
      return "KEYWORD_THEN";
    case YP_TOKEN_KEYWORD_TRUE:
      return "KEYWORD_TRUE";
    case YP_TOKEN_KEYWORD_UNDEF:
      return "KEYWORD_UNDEF";
    case YP_TOKEN_KEYWORD_UNLESS:
      return "KEYWORD_UNLESS";
    case YP_TOKEN_KEYWORD_UNLESS_MODIFIER:
      return "KEYWORD_UNLESS_MODIFIER";
    case YP_TOKEN_KEYWORD_UNTIL:
      return "KEYWORD_UNTIL";
    case YP_TOKEN_KEYWORD_UNTIL_MODIFIER:
      return "KEYWORD_UNTIL_MODIFIER";
    case YP_TOKEN_KEYWORD_WHEN:
      return "KEYWORD_WHEN";
    case YP_TOKEN_KEYWORD_WHILE:
      return "KEYWORD_WHILE";
    case YP_TOKEN_KEYWORD_WHILE_MODIFIER:
      return "KEYWORD_WHILE_MODIFIER";
    case YP_TOKEN_KEYWORD_YIELD:
      return "KEYWORD_YIELD";
    case YP_TOKEN_KEYWORD___ENCODING__:
      return "KEYWORD___ENCODING__";
    case YP_TOKEN_KEYWORD___FILE__:
      return "KEYWORD___FILE__";
    case YP_TOKEN_KEYWORD___LINE__:
      return "KEYWORD___LINE__";
    case YP_TOKEN_LABEL:
      return "LABEL";
    case YP_TOKEN_LABEL_END:
      return "LABEL_END";
    case YP_TOKEN_LAMBDA_BEGIN:
      return "LAMBDA_BEGIN";
    case YP_TOKEN_LESS:
      return "LESS";
    case YP_TOKEN_LESS_EQUAL:
      return "LESS_EQUAL";
    case YP_TOKEN_LESS_EQUAL_GREATER:
      return "LESS_EQUAL_GREATER";
    case YP_TOKEN_LESS_LESS:
      return "LESS_LESS";
    case YP_TOKEN_LESS_LESS_EQUAL:
      return "LESS_LESS_EQUAL";
    case YP_TOKEN_MINUS:
      return "MINUS";
    case YP_TOKEN_MINUS_EQUAL:
      return "MINUS_EQUAL";
    case YP_TOKEN_MINUS_GREATER:
      return "MINUS_GREATER";
    case YP_TOKEN_NEWLINE:
      return "NEWLINE";
    case YP_TOKEN_NTH_REFERENCE:
      return "NTH_REFERENCE";
    case YP_TOKEN_PARENTHESIS_LEFT:
      return "PARENTHESIS_LEFT";
    case YP_TOKEN_PARENTHESIS_LEFT_PARENTHESES:
      return "PARENTHESIS_LEFT_PARENTHESES";
    case YP_TOKEN_PARENTHESIS_RIGHT:
      return "PARENTHESIS_RIGHT";
    case YP_TOKEN_PERCENT:
      return "PERCENT";
    case YP_TOKEN_PERCENT_EQUAL:
      return "PERCENT_EQUAL";
    case YP_TOKEN_PERCENT_LOWER_I:
      return "PERCENT_LOWER_I";
    case YP_TOKEN_PERCENT_LOWER_W:
      return "PERCENT_LOWER_W";
    case YP_TOKEN_PERCENT_LOWER_X:
      return "PERCENT_LOWER_X";
    case YP_TOKEN_PERCENT_UPPER_I:
      return "PERCENT_UPPER_I";
    case YP_TOKEN_PERCENT_UPPER_W:
      return "PERCENT_UPPER_W";
    case YP_TOKEN_PIPE:
      return "PIPE";
    case YP_TOKEN_PIPE_EQUAL:
      return "PIPE_EQUAL";
    case YP_TOKEN_PIPE_PIPE:
      return "PIPE_PIPE";
    case YP_TOKEN_PIPE_PIPE_EQUAL:
      return "PIPE_PIPE_EQUAL";
    case YP_TOKEN_PLUS:
      return "PLUS";
    case YP_TOKEN_PLUS_EQUAL:
      return "PLUS_EQUAL";
    case YP_TOKEN_QUESTION_MARK:
      return "QUESTION_MARK";
    case YP_TOKEN_RATIONAL_NUMBER:
      return "RATIONAL_NUMBER";
    case YP_TOKEN_REGEXP_BEGIN:
      return "REGEXP_BEGIN";
    case YP_TOKEN_REGEXP_END:
      return "REGEXP_END";
    case YP_TOKEN_SEMICOLON:
      return "SEMICOLON";
    case YP_TOKEN_SLASH:
      return "SLASH";
    case YP_TOKEN_SLASH_EQUAL:
      return "SLASH_EQUAL";
    case YP_TOKEN_STAR:
      return "STAR";
    case YP_TOKEN_STAR_EQUAL:
      return "STAR_EQUAL";
    case YP_TOKEN_STAR_STAR:
      return "STAR_STAR";
    case YP_TOKEN_STAR_STAR_EQUAL:
      return "STAR_STAR_EQUAL";
    case YP_TOKEN_STRING_BEGIN:
      return "STRING_BEGIN";
    case YP_TOKEN_STRING_CONTENT:
      return "STRING_CONTENT";
    case YP_TOKEN_STRING_END:
      return "STRING_END";
    case YP_TOKEN_SYMBOL_BEGIN:
      return "SYMBOL_BEGIN";
    case YP_TOKEN_TILDE:
      return "TILDE";
    case YP_TOKEN_UCOLON_COLON:
      return "UCOLON_COLON";
    case YP_TOKEN_UDOT_DOT:
      return "UDOT_DOT";
    case YP_TOKEN_UDOT_DOT_DOT:
      return "UDOT_DOT_DOT";
    case YP_TOKEN_UMINUS:
      return "UMINUS";
    case YP_TOKEN_UMINUS_NUM:
      return "UMINUS_NUM";
    case YP_TOKEN_UPLUS:
      return "UPLUS";
    case YP_TOKEN_USTAR:
      return "USTAR";
    case YP_TOKEN_USTAR_STAR:
      return "USTAR_STAR";
    case YP_TOKEN_WORDS_SEP:
      return "WORDS_SEP";
    case YP_TOKEN___END__:
      return "__END__";
    case YP_TOKEN_MAXIMUM:
      return "MAXIMUM";
  }
  return "\0";
}
