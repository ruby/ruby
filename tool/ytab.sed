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
/^yydestruct.*yymsg/,/#endif/{
  /^yydestruct/{
    /[, *]p)/!{
      H
      s/^/ruby_parser_&/
      s/)$/, p)/
      /\*/s/parser)$/struct parser_params *&/
    }
  }
  /^#endif/{
    x
    /yydestruct/{
      i\
\    struct parser_params *p;
      a\
#define yydestruct(m, t, v) ruby_parser_yydestruct(m, t, v, p)
    }
    x
  }
}
/^yy_stack_print /,/#endif/{
  /^yy_stack_print/{
    /[, *]p)/!{
      H
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
}
/yy_stack_print.*;/{
  x
  /yy_stack_print/{
    x
    s/\(yy_stack_print *\)(\(.*\));/\1(\2, p);/
    x
  }
  x
}
/^yy_reduce_print/,/^}/{
  s/fprintf *(stderr,/YYFPRINTF (p,/g
}
s/\( YYFPRINTF *(\)yyoutput,/\1p,/
s/\( YYFPRINTF *(\)stderr,/\1p,/
s/\( YYDPRINTF *((\)stderr,/\1p,/
s/^\([ 	]*\)\(yyerror[ 	]*([ 	]*parser,\)/\1parser_\2/
s!^ *extern char \*getenv();!/* & */!
s/^\(#.*\)".*\.tab\.c"/\1"parse.c"/
/^\(#.*\)".*\.y"/s:\\\\:/:g
