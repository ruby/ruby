#!/bin/sed -f
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
/^yy_symbol_value_print/{
  a\
#define yy_symbol_value_print(output, type, value, parser) yy_symbol_value_print(0, type, value, parser)
}
/^yy_symbol_print/{
  a\
#define yy_symbol_print(output, type, value, parser) yy_symbol_print(0, type, value, parser)
  a\
#define yyoutput parser
}
s/^\([ 	]*\)\(yyerror[ 	]*([ 	]*parser,\)/\1parser_\2/
s!^ *extern char \*getenv();!/* & */!
s/^\(#.*\)".*\.tab\.c"/\1"parse.c"/
/^\(#.*\)".*\.y"/s:\\\\:/:g
