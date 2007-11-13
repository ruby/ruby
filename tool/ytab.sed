#!/bin/sed -f
/^int yydebug;/{
i\
#ifndef yydebug
a\
#endif
}
s/\<\(yyerror[ 	]*([ 	]*parser,\)/parser_\1/
s!^ *extern char \*getenv();!/* & */!
s/^\(#.*\)".*\.tab\.c"/\1"parse.c"/
