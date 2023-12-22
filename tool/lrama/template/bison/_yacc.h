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
#if YYDEBUG && !defined(yydebug)
extern int yydebug;
#endif
<%= output.percent_code("requires") %>

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


<%= output.percent_code("provides") %>
  <%-# b4_cpp_guard_close([b4_spec_mapped_header_file]) -%>
    <%- if output.spec_mapped_header_file -%>
#endif /* !<%= output.b4_cpp_guard__b4_spec_mapped_header_file %>  */
    <%- end -%>
