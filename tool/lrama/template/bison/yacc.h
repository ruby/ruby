<%# b4_generated_by -%>
/* A Bison parser, made by Lrama <%= Lrama::VERSION %>.  */

<%# b4_copyright -%>
/* Bison interface for Yacc-like parsers in C

   Copyright (C) 1984, 1989-1990, 2000-2015, 2018-2021 Free Software Foundation,
   Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

<%# b4_disclaimer -%>
/* DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
   especially those whose name start with YY_ or yy_.  They are
   private implementation details that can be changed or removed.  */

<%# b4_shared_declarations -%>
<%# b4_shared_declarations -%>
  <%-# b4_cpp_guard_open([b4_spec_mapped_header_file]) -%>
    <%- if output.spec_mapped_header_file -%>
#ifndef <%= output.b4_cpp_guard__b4_spec_mapped_header_file %>
# define <%= output.b4_cpp_guard__b4_spec_mapped_header_file %>
    <%- end -%>
  <%-# b4_declare_yydebug & b4_YYDEBUG_define -%>
/* Debug traces.  */
#ifndef YYDEBUG
# define YYDEBUG 0
#endif
#if YYDEBUG
extern int yydebug;
#endif
  <%-# b4_percent_code_get([[requires]]). %code is not supported -%>

  <%-# b4_token_enums_defines -%>
/* Token kinds.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
  enum yytokentype
  {
<%= output.token_enums -%>
  };
  typedef enum yytokentype yytoken_kind_t;
#endif

  <%-# b4_declare_yylstype -%>
    <%-# b4_value_type_define -%>
/* Value type.  */
#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
union YYSTYPE
{
#line <%= output.grammar.union.lineno %> "<%= output.grammar_file_path %>"
<%= output.grammar.union.braces_less_code %>
#line [@oline@] [@ofile@]

};
typedef union YYSTYPE YYSTYPE;
# define YYSTYPE_IS_TRIVIAL 1
# define YYSTYPE_IS_DECLARED 1
#endif

    <%-# b4_location_type_define -%>
/* Location type.  */
#if ! defined YYLTYPE && ! defined YYLTYPE_IS_DECLARED
typedef struct YYLTYPE YYLTYPE;
struct YYLTYPE
{
  int first_line;
  int first_column;
  int last_line;
  int last_column;
};
# define YYLTYPE_IS_DECLARED 1
# define YYLTYPE_IS_TRIVIAL 1
#endif




  <%-# b4_declare_yyerror_and_yylex. Not supported -%>
  <%-# b4_declare_yyparse -%>
int yyparse (<%= output.parse_param %>);


  <%-# b4_percent_code_get([[provides]]). %code is not supported -%>
  <%-# b4_cpp_guard_close([b4_spec_mapped_header_file]) -%>
    <%- if output.spec_mapped_header_file -%>
#endif /* !<%= output.b4_cpp_guard__b4_spec_mapped_header_file %>  */
    <%- end -%>
