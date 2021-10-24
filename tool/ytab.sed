#!/bin/sed -f
# This file is used when generating code for the Ruby parser.
/^int yydebug;/{
i\
#ifndef yydebug
a\
#endif
}
/^extern int yydebug;/{
i\
#ifndef yydebug
a\
#endif
}
/^yydestruct.*yymsg/,/{/{
  /^yydestruct/{
    /,$/N
    /[, *]p)/!{
      H
      s/^/ruby_parser_&/
      s/)$/, p)/
      /\*/s/p)$/struct parser_params *&/
    }
  }
  /^#endif/{
    x
    /yydestruct/{
      i\
\    struct parser_params *p;
    }
    x
  }
  /^{/{
    x
    /yydestruct/{
      i\
#define yydestruct(m, t, v) ruby_parser_yydestruct(m, t, v, p)
    }
    x
  }
}
/^yy_stack_print /,/{/{
  /^yy_stack_print/{
    /[, *]p)/!{
      H
      s/^/ruby_parser_&/
      s/)$/, p)/
      /\*/s/p)$/struct parser_params *&/
    }
  }
  /^#endif/{
    x
    /yy_stack_print/{
      i\
\    struct parser_params *p;
    }
    x
  }
  /^{/{
    x
    /yy_stack_print/{
      i\
#define yy_stack_print(b, t) ruby_parser_yy_stack_print(b, t, p)
    }
    x
  }
}
/^yy_reduce_print/,/^}/{
  s/fprintf *(stderr,/YYFPRINTF (p,/g
}
s/^yysyntax_error (/&struct parser_params *p, /
s/ yysyntax_error (/&p, /
s/\( YYFPRINTF *(\)yyoutput,/\1p,/
s/\( YYFPRINTF *(\)yyo,/\1p,/
s/\( YYFPRINTF *(\)stderr,/\1p,/
s/\( YYDPRINTF *((\)stderr,/\1p,/
s/^\([ 	]*\)\(yyerror[ 	]*([ 	]*parser,\)/\1parser_\2/
s!^ *extern char \*getenv();!/* & */!
s/^\(#.*\)".*\.tab\.c"/\1"parse.c"/
/^\(#.*\)".*\.y"/s:\\\\:/:g
