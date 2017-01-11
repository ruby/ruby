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
    /parser/!{
      H
      s/^/ruby_parser_&/
      s/)$/, parser)/
      /\*/s/parser)$/struct parser_params *&/
    }
  }
  /^#endif/{
    x
    /yydestruct/{
      i\
    struct parser_params *parser;
      a\
#define yydestruct(m, t, v) ruby_parser_yydestruct(m, t, v, parser)
    }
    x
  }
}
/^yy_stack_print/{
  /parser/!{
    H
    s/)$/, parser)/
    /\*/s/parser)$/struct parser_params *&/
  }
}
/yy_stack_print.*;/{
  x
  /yy_stack_print/{
    x
    s/\(yy_stack_print *\)(\(.*\));/\1(\2, parser);/
    x
  }
  x
}
/^yy_reduce_print/,/^}/{
  s/fprintf *(stderr,/YYFPRINTF (parser,/g
}
s/\( YYFPRINTF *(\)yyoutput,/\1parser,/
s/\( YYFPRINTF *(\)stderr,/\1parser,/
s/\( YYDPRINTF *((\)stderr,/\1parser,/
s/^\([ 	]*\)\(yyerror[ 	]*([ 	]*parser,\)/\1parser_\2/
s!^ *extern char \*getenv();!/* & */!
s/^\(#.*\)".*\.tab\.c"/\1"parse.c"/
/^\(#.*\)".*\.y"/s:\\\\:/:g
