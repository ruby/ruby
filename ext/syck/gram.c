/* A Bison parser, made from gram.y, by GNU bison 1.75.  */

/* Skeleton parser for Yacc-like parsing with Bison,
   Copyright (C) 1984, 1989, 1990, 2000, 2001, 2002 Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place - Suite 330,
   Boston, MA 02111-1307, USA.  */

/* As a special exception, when this file is copied by Bison into a
   Bison output file, you may use that output file without restriction.
   This special exception was added by the Free Software Foundation
   in version 1.24 of Bison.  */

/* Written by Richard Stallman by simplifying the original so called
   ``semantic'' parser.  */

/* All symbols defined below should begin with yy or YY, to avoid
   infringing on user name space.  This should be done even for local
   variables, as they might otherwise be expanded by user macros.
   There are some unavoidable exceptions within include files to
   define necessary library symbols; they are noted "INFRINGES ON
   USER NAME SPACE" below.  */

/* Identify Bison output.  */
#define YYBISON	1

/* Pure parsers.  */
#define YYPURE	1

/* Using locations.  */
#define YYLSP_NEEDED 0

/* If NAME_PREFIX is specified substitute the variables and functions
   names.  */
#define yyparse syckparse
#define yylex   sycklex
#define yyerror syckerror
#define yylval  sycklval
#define yychar  syckchar
#define yydebug syckdebug
#define yynerrs sycknerrs


/* Tokens.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
   /* Put the tokens into the symbol table, so that GDB and other debuggers
      know about them.  */
   enum yytokentype {
     YAML_ANCHOR = 258,
     YAML_ALIAS = 259,
     YAML_TRANSFER = 260,
     YAML_ITRANSFER = 261,
     YAML_WORD = 262,
     YAML_PLAIN = 263,
     YAML_BLOCK = 264,
     YAML_DOCSEP = 265,
     YAML_IOPEN = 266,
     YAML_INDENT = 267,
     YAML_IEND = 268
   };
#endif
#define YAML_ANCHOR 258
#define YAML_ALIAS 259
#define YAML_TRANSFER 260
#define YAML_ITRANSFER 261
#define YAML_WORD 262
#define YAML_PLAIN 263
#define YAML_BLOCK 264
#define YAML_DOCSEP 265
#define YAML_IOPEN 266
#define YAML_INDENT 267
#define YAML_IEND 268




/* Copy the first part of user declarations.  */
#line 14 "gram.y"


#include "syck.h"

#define YYPARSE_PARAM   parser
#define YYLEX_PARAM     parser



/* Enabling traces.  */
#ifndef YYDEBUG
# define YYDEBUG 1
#endif

/* Enabling verbose error messages.  */
#ifdef YYERROR_VERBOSE
# undef YYERROR_VERBOSE
# define YYERROR_VERBOSE 1
#else
# define YYERROR_VERBOSE 0
#endif

#ifndef YYSTYPE
#line 23 "gram.y"
typedef union {
    SYMID nodeId;
    SyckNode *nodeData;
    char *name;
} yystype;
/* Line 193 of /usr/local/share/bison/yacc.c.  */
#line 123 "y.tab.c"
# define YYSTYPE yystype
# define YYSTYPE_IS_TRIVIAL 1
#endif

#ifndef YYLTYPE
typedef struct yyltype
{
  int first_line;
  int first_column;
  int last_line;
  int last_column;
} yyltype;
# define YYLTYPE yyltype
# define YYLTYPE_IS_TRIVIAL 1
#endif

/* Copy the second part of user declarations.  */
int sycklex( YYSTYPE *, SyckParser * );


/* Line 213 of /usr/local/share/bison/yacc.c.  */
#line 144 "y.tab.c"

#if ! defined (yyoverflow) || YYERROR_VERBOSE

/* The parser invokes alloca or malloc; define the necessary symbols.  */

# if YYSTACK_USE_ALLOCA
#  define YYSTACK_ALLOC alloca
# else
#  ifndef YYSTACK_USE_ALLOCA
#   if defined (alloca) || defined (_ALLOCA_H)
#    define YYSTACK_ALLOC alloca
#   else
#    ifdef __GNUC__
#     define YYSTACK_ALLOC __builtin_alloca
#    endif
#   endif
#  endif
# endif

# ifdef YYSTACK_ALLOC
   /* Pacify GCC's `empty if-body' warning. */
#  define YYSTACK_FREE(Ptr) do { /* empty */; } while (0)
# else
#  if defined (__STDC__) || defined (__cplusplus)
#   include <stdlib.h> /* INFRINGES ON USER NAME SPACE */
#   define YYSIZE_T size_t
#  endif
#  define YYSTACK_ALLOC malloc
#  define YYSTACK_FREE free
# endif
#endif /* ! defined (yyoverflow) || YYERROR_VERBOSE */


#if (! defined (yyoverflow) \
     && (! defined (__cplusplus) \
	 || (YYLTYPE_IS_TRIVIAL && YYSTYPE_IS_TRIVIAL)))

/* A type that is properly aligned for any stack member.  */
union yyalloc
{
  short yyss;
  YYSTYPE yyvs;
  };

/* The size of the maximum gap between one aligned stack and the next.  */
# define YYSTACK_GAP_MAX (sizeof (union yyalloc) - 1)

/* The size of an array large to enough to hold all stacks, each with
   N elements.  */
# define YYSTACK_BYTES(N) \
     ((N) * (sizeof (short) + sizeof (YYSTYPE))				\
      + YYSTACK_GAP_MAX)

/* Copy COUNT objects from FROM to TO.  The source and destination do
   not overlap.  */
# ifndef YYCOPY
#  if 1 < __GNUC__
#   define YYCOPY(To, From, Count) \
      __builtin_memcpy (To, From, (Count) * sizeof (*(From)))
#  else
#   define YYCOPY(To, From, Count)		\
      do					\
	{					\
	  register YYSIZE_T yyi;		\
	  for (yyi = 0; yyi < (Count); yyi++)	\
	    (To)[yyi] = (From)[yyi];	\
	}					\
      while (0)
#  endif
# endif

/* Relocate STACK from its old location to the new one.  The
   local variables YYSIZE and YYSTACKSIZE give the old and new number of
   elements in the stack, and YYPTR gives the new location of the
   stack.  Advance YYPTR to a properly aligned location for the next
   stack.  */
# define YYSTACK_RELOCATE(Stack)					\
    do									\
      {									\
	YYSIZE_T yynewbytes;						\
	YYCOPY (&yyptr->Stack, Stack, yysize);				\
	Stack = &yyptr->Stack;						\
	yynewbytes = yystacksize * sizeof (*Stack) + YYSTACK_GAP_MAX;	\
	yyptr += yynewbytes / sizeof (*yyptr);				\
      }									\
    while (0)

#endif

#if defined (__STDC__) || defined (__cplusplus)
   typedef signed char yysigned_char;
#else
   typedef short yysigned_char;
#endif

/* YYFINAL -- State number of the termination state. */
#define YYFINAL  35
#define YYLAST   333

/* YYNTOKENS -- Number of terminals. */
#define YYNTOKENS  23
/* YYNNTS -- Number of nonterminals. */
#define YYNNTS  25
/* YYNRULES -- Number of rules. */
#define YYNRULES  63
/* YYNRULES -- Number of states. */
#define YYNSTATES  106

/* YYTRANSLATE(YYLEX) -- Bison symbol number corresponding to YYLEX.  */
#define YYUNDEFTOK  2
#define YYMAXUTOK   268

#define YYTRANSLATE(X) \
  ((unsigned)(X) <= YYMAXUTOK ? yytranslate[X] : YYUNDEFTOK)

/* YYTRANSLATE[YYLEX] -- Bison symbol number corresponding to YYLEX.  */
static const unsigned char yytranslate[] =
{
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    16,    21,    14,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,    15,     2,
       2,     2,     2,    22,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,    17,     2,    18,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    19,     2,    20,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     1,     2,     3,     4,
       5,     6,     7,     8,     9,    10,    11,    12,    13
};

#if YYDEBUG
/* YYPRHS[YYN] -- Index of the first RHS symbol of rule number YYN in
   YYRHS.  */
static const unsigned char yyprhs[] =
{
       0,     0,     3,     5,     8,     9,    11,    13,    15,    18,
      22,    26,    28,    31,    32,    34,    37,    39,    41,    43,
      46,    49,    52,    55,    57,    59,    61,    64,    66,    68,
      70,    72,    74,    78,    81,    83,    87,    90,    94,    97,
      99,   103,   106,   110,   113,   115,   119,   123,   127,   131,
     134,   138,   141,   145,   147,   153,   155,   159,   163,   166,
     170,   174,   177,   179
};

/* YYRHS -- A `-1'-separated list of the rules' RHS. */
static const yysigned_char yyrhs[] =
{
      24,     0,    -1,    33,    -1,    10,    27,    -1,    -1,    32,
      -1,    26,    -1,    33,    -1,     3,    26,    -1,    28,    32,
      31,    -1,    28,    26,    31,    -1,    25,    -1,    28,    29,
      -1,    -1,    11,    -1,    28,    12,    -1,    13,    -1,    12,
      -1,    13,    -1,    30,    31,    -1,     5,    32,    -1,     6,
      32,    -1,     3,    32,    -1,     4,    -1,     7,    -1,     8,
      -1,     5,    33,    -1,     9,    -1,    34,    -1,    38,    -1,
      40,    -1,    46,    -1,    28,    36,    29,    -1,    14,    27,
      -1,    37,    -1,     5,    30,    36,    -1,     5,    36,    -1,
       3,    30,    36,    -1,     3,    36,    -1,    35,    -1,    37,
      30,    35,    -1,    37,    30,    -1,    17,    39,    18,    -1,
      17,    18,    -1,    25,    -1,    39,    21,    25,    -1,    28,
      41,    29,    -1,    28,    44,    29,    -1,     5,    30,    44,
      -1,     5,    41,    -1,     3,    30,    44,    -1,     3,    41,
      -1,    32,    15,    27,    -1,    42,    -1,    22,    25,    30,
      15,    27,    -1,    43,    -1,    44,    30,    35,    -1,    44,
      30,    43,    -1,    44,    30,    -1,    25,    15,    27,    -1,
      19,    47,    20,    -1,    19,    20,    -1,    45,    -1,    47,
      21,    45,    -1
};

/* YYRLINE[YYN] -- source line where rule number YYN was defined.  */
static const unsigned short yyrline[] =
{
       0,    44,    44,    48,    52,    58,    59,    62,    63,    72,
      76,    82,    83,    96,   114,   115,   118,   121,   124,   125,
     133,   138,   146,   150,   158,   171,   178,   183,   184,   185,
     186,   187,   193,   199,   205,   206,   211,   216,   220,   226,
     230,   235,   244,   248,   254,   258,   268,   273,   280,   285,
     290,   294,   300,   315,   316,   324,   325,   337,   344,   353,
     361,   365,   371,   372
};
#endif

#if YYDEBUG || YYERROR_VERBOSE
/* YYTNME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
   First, the terminals, then, starting at YYNTOKENS, nonterminals. */
static const char *const yytname[] =
{
  "$end", "error", "$undefined", "YAML_ANCHOR", "YAML_ALIAS", 
  "YAML_TRANSFER", "YAML_ITRANSFER", "YAML_WORD", "YAML_PLAIN", 
  "YAML_BLOCK", "YAML_DOCSEP", "YAML_IOPEN", "YAML_INDENT", "YAML_IEND", 
  "'-'", "':'", "'+'", "'['", "']'", "'{'", "'}'", "','", "'?'", 
  "$accept", "doc", "atom", "ind_rep", "atom_or_empty", "indent_open", 
  "indent_end", "indent_sep", "indent_flex_end", "word_rep", "struct_rep", 
  "implicit_seq", "basic_seq", "top_imp_seq", "in_implicit_seq", 
  "inline_seq", "in_inline_seq", "implicit_map", "top_imp_map", 
  "basic_mapping", "complex_mapping", "in_implicit_map", "basic_mapping2", 
  "inline_map", "in_inline_map", 0
};
#endif

# ifdef YYPRINT
/* YYTOKNUM[YYLEX-NUM] -- Internal token number corresponding to
   token YYLEX-NUM.  */
static const unsigned short yytoknum[] =
{
       0,   256,   257,   258,   259,   260,   261,   262,   263,   264,
     265,   266,   267,   268,    45,    58,    43,    91,    93,   123,
     125,    44,    63
};
# endif

/* YYR1[YYN] -- Symbol number of symbol that rule YYN derives.  */
static const unsigned char yyr1[] =
{
       0,    23,    24,    24,    24,    25,    25,    26,    26,    26,
      26,    27,    27,    27,    28,    28,    29,    30,    31,    31,
      32,    32,    32,    32,    32,    32,    33,    33,    33,    33,
      33,    33,    34,    35,    36,    36,    36,    36,    36,    37,
      37,    37,    38,    38,    39,    39,    40,    40,    41,    41,
      41,    41,    42,    43,    43,    44,    44,    44,    44,    45,
      46,    46,    47,    47
};

/* YYR2[YYN] -- Number of symbols composing right hand side of rule YYN.  */
static const unsigned char yyr2[] =
{
       0,     2,     1,     2,     0,     1,     1,     1,     2,     3,
       3,     1,     2,     0,     1,     2,     1,     1,     1,     2,
       2,     2,     2,     1,     1,     1,     2,     1,     1,     1,
       1,     1,     3,     2,     1,     3,     2,     3,     2,     1,
       3,     2,     3,     2,     1,     3,     3,     3,     3,     2,
       3,     2,     3,     1,     5,     1,     3,     3,     2,     3,
       3,     2,     1,     3
};

/* YYDEFACT[STATE-NAME] -- Default rule to reduce with in state
   STATE-NUM when YYTABLE doesn't specify something else to do.  Zero
   means the default is an error.  */
static const unsigned char yydefact[] =
{
       4,     0,    27,    13,    14,     0,     0,     0,     0,     2,
      28,    29,    30,    31,    26,     0,    23,     0,     0,    24,
      25,    11,     6,     3,     0,     5,     7,    43,    44,     0,
       0,    61,     0,    62,     0,     1,     0,     0,    15,    13,
       0,     0,    39,     0,    34,     0,    53,    55,     0,     8,
      22,     0,    20,     0,    21,     0,     0,    16,     0,    12,
       0,    42,     0,    13,    60,     0,    17,     0,    38,    51,
       0,    36,    49,    33,     0,    13,    32,    41,    46,    47,
      58,    18,     0,    10,     9,    45,    59,    63,     0,     0,
      37,    50,    35,    48,     0,    52,    40,    56,    57,    19,
       0,     0,    13,     0,     0,    54
};

/* YYDEFGOTO[NTERM-NUM]. */
static const yysigned_char yydefgoto[] =
{
      -1,     7,    21,    22,    23,    29,    59,    80,    83,    25,
      26,    10,    42,    68,    44,    11,    30,    12,    45,    46,
      47,    48,    33,    13,    34
};

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
#define YYPACT_NINF -54
static const short yypact[] =
{
     267,   278,   -54,   245,   -54,   228,   176,     8,   140,   -54,
     -54,   -54,   -54,   -54,   -54,   245,   -54,   262,   325,   -54,
     -54,   -54,   -54,   -54,   100,   -54,   -54,   -54,   -54,   120,
      48,   -54,    -5,   -54,    52,   -54,   295,   295,   -54,   245,
     245,    -3,   -54,    13,     9,    13,   -54,   -54,    76,   -54,
     -54,   325,   -54,   325,   -54,   194,   211,   -54,   108,   -54,
     103,   -54,   245,   245,   -54,   245,   -54,   152,   -54,   -54,
     152,   -54,   -54,   -54,     9,   245,   -54,    24,   -54,   -54,
     164,   -54,   108,   -54,   -54,   -54,   -54,   -54,   307,   307,
     -54,     9,   -54,     9,    32,   -54,   -54,   -54,   -54,   -54,
       6,     6,   245,   313,   313,   -54
};

/* YYPGOTO[NTERM-NUM].  */
static const yysigned_char yypgoto[] =
{
     -54,   -54,    31,   -10,   -35,     0,    12,   -12,   -53,    -2,
      41,   -54,   -47,    -6,   -54,   -54,   -54,   -54,    44,   -54,
     -28,    15,    14,   -54,   -54
};

/* YYTABLE[YYPACT[STATE-NUM]].  What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule which
   number is the opposite.  If zero, do what YYDEFACT says.
   If YYTABLE_NINF, parse error.  */
#define YYTABLE_NINF -1
static const unsigned char yytable[] =
{
       8,     8,    43,    24,    73,    49,    41,    84,    35,   103,
      63,   104,    75,    50,    58,    52,    54,     8,    43,    58,
      39,    66,    60,    43,    67,    70,    57,    60,    86,    99,
      96,    71,    77,    97,    50,    52,    28,    32,    39,    24,
      95,     9,    14,    67,    70,    49,    82,   102,    82,    50,
      71,    52,    98,    50,    52,    76,     8,    78,    14,     0,
      79,    90,    94,    24,    92,    41,    61,   105,    41,    62,
      82,    74,    64,    65,     0,    24,   100,   101,    41,    87,
      69,    72,    91,    71,     0,    93,    50,    52,    66,    57,
       0,   100,   101,    85,    90,    92,    32,    14,    71,    69,
      72,     0,    24,    55,    16,    56,    18,    19,    20,     2,
       0,     4,    38,    57,    39,    66,    81,     5,    75,     6,
      66,    81,    40,    55,    16,    56,    18,    19,    20,     2,
       0,     4,    38,     0,    39,     0,     0,     5,     0,     6,
       0,     0,    40,    36,    16,    37,    18,    19,    20,     0,
       0,     0,    38,     0,    39,    88,    16,    89,    18,    19,
      20,     0,    40,     0,     0,     0,    39,    51,    16,    53,
      18,    19,    20,     0,    40,     0,     0,     0,    39,    15,
      16,    17,    18,    19,    20,     2,    40,     4,     0,     0,
       0,     0,     0,     5,     0,     6,    31,    55,    16,    56,
      18,    19,    20,     2,     0,     4,    66,     0,    39,     0,
       0,     5,     0,     6,    36,    16,    56,    18,    19,    20,
       2,     0,     4,    66,     0,    39,     0,     0,     5,     0,
       6,    15,    16,    17,    18,    19,    20,     2,     0,     4,
       0,     0,     0,     0,     0,     5,    27,     6,    15,    16,
      17,    18,    19,    20,     2,     0,     4,     0,     0,     0,
       0,     0,     5,     0,     6,    51,    16,    17,    18,    19,
      20,     2,     1,     4,     0,     0,     2,     3,     4,     5,
       0,     6,     0,     1,     5,     0,     6,     2,     0,     4,
       0,     0,     0,     0,     0,     5,     0,     6,    36,    16,
      37,    18,    19,    20,     0,     0,     0,    66,     0,    39,
      88,    16,    89,    18,    19,    20,   103,     0,   104,    66,
       0,    39,     0,     0,     0,    66,     0,    39,    51,    16,
      53,    18,    19,    20
};

static const yysigned_char yycheck[] =
{
       0,     1,     8,     3,    39,    15,     8,    60,     0,     3,
      15,     5,    15,    15,    24,    17,    18,    17,    24,    29,
      14,    12,    24,    29,    36,    37,    13,    29,    63,    82,
      77,    37,    44,    80,    36,    37,     5,     6,    14,    39,
      75,     0,     1,    55,    56,    55,    58,    15,    60,    51,
      56,    53,    80,    55,    56,    43,    56,    45,    17,    -1,
      48,    67,    74,    63,    70,    67,    18,   102,    70,    21,
      82,    40,    20,    21,    -1,    75,    88,    89,    80,    65,
      36,    37,    67,    89,    -1,    70,    88,    89,    12,    13,
      -1,   103,   104,    62,   100,   101,    65,    56,   104,    55,
      56,    -1,   102,     3,     4,     5,     6,     7,     8,     9,
      -1,    11,    12,    13,    14,    12,    13,    17,    15,    19,
      12,    13,    22,     3,     4,     5,     6,     7,     8,     9,
      -1,    11,    12,    -1,    14,    -1,    -1,    17,    -1,    19,
      -1,    -1,    22,     3,     4,     5,     6,     7,     8,    -1,
      -1,    -1,    12,    -1,    14,     3,     4,     5,     6,     7,
       8,    -1,    22,    -1,    -1,    -1,    14,     3,     4,     5,
       6,     7,     8,    -1,    22,    -1,    -1,    -1,    14,     3,
       4,     5,     6,     7,     8,     9,    22,    11,    -1,    -1,
      -1,    -1,    -1,    17,    -1,    19,    20,     3,     4,     5,
       6,     7,     8,     9,    -1,    11,    12,    -1,    14,    -1,
      -1,    17,    -1,    19,     3,     4,     5,     6,     7,     8,
       9,    -1,    11,    12,    -1,    14,    -1,    -1,    17,    -1,
      19,     3,     4,     5,     6,     7,     8,     9,    -1,    11,
      -1,    -1,    -1,    -1,    -1,    17,    18,    19,     3,     4,
       5,     6,     7,     8,     9,    -1,    11,    -1,    -1,    -1,
      -1,    -1,    17,    -1,    19,     3,     4,     5,     6,     7,
       8,     9,     5,    11,    -1,    -1,     9,    10,    11,    17,
      -1,    19,    -1,     5,    17,    -1,    19,     9,    -1,    11,
      -1,    -1,    -1,    -1,    -1,    17,    -1,    19,     3,     4,
       5,     6,     7,     8,    -1,    -1,    -1,    12,    -1,    14,
       3,     4,     5,     6,     7,     8,     3,    -1,     5,    12,
      -1,    14,    -1,    -1,    -1,    12,    -1,    14,     3,     4,
       5,     6,     7,     8
};

/* YYSTOS[STATE-NUM] -- The (internal number of the) accessing
   symbol of state STATE-NUM.  */
static const unsigned char yystos[] =
{
       0,     5,     9,    10,    11,    17,    19,    24,    28,    33,
      34,    38,    40,    46,    33,     3,     4,     5,     6,     7,
       8,    25,    26,    27,    28,    32,    33,    18,    25,    28,
      39,    20,    25,    45,    47,     0,     3,     5,    12,    14,
      22,    32,    35,    36,    37,    41,    42,    43,    44,    26,
      32,     3,    32,     5,    32,     3,     5,    13,    26,    29,
      32,    18,    21,    15,    20,    21,    12,    30,    36,    41,
      30,    36,    41,    27,    25,    15,    29,    30,    29,    29,
      30,    13,    30,    31,    31,    25,    27,    45,     3,     5,
      36,    44,    36,    44,    30,    27,    35,    35,    43,    31,
      30,    30,    15,     3,     5,    27
};

#if ! defined (YYSIZE_T) && defined (__SIZE_TYPE__)
# define YYSIZE_T __SIZE_TYPE__
#endif
#if ! defined (YYSIZE_T) && defined (size_t)
# define YYSIZE_T size_t
#endif
#if ! defined (YYSIZE_T)
# if defined (__STDC__) || defined (__cplusplus)
#  include <stddef.h> /* INFRINGES ON USER NAME SPACE */
#  define YYSIZE_T size_t
# endif
#endif
#if ! defined (YYSIZE_T)
# define YYSIZE_T unsigned int
#endif

#define yyerrok		(yyerrstatus = 0)
#define yyclearin	(yychar = YYEMPTY)
#define YYEMPTY		-2
#define YYEOF		0

#define YYACCEPT	goto yyacceptlab
#define YYABORT		goto yyabortlab
#define YYERROR		goto yyerrlab1

/* Like YYERROR except do call yyerror.  This remains here temporarily
   to ease the transition to the new meaning of YYERROR, for GCC.
   Once GCC version 2 has supplanted version 1, this can go.  */

#define YYFAIL		goto yyerrlab

#define YYRECOVERING()  (!!yyerrstatus)

#define YYBACKUP(Token, Value)					\
do								\
  if (yychar == YYEMPTY && yylen == 1)				\
    {								\
      yychar = (Token);						\
      yylval = (Value);						\
      yychar1 = YYTRANSLATE (yychar);				\
      YYPOPSTACK;						\
      goto yybackup;						\
    }								\
  else								\
    { 								\
      yyerror ("syntax error: cannot back up");			\
      YYERROR;							\
    }								\
while (0)

#define YYTERROR	1
#define YYERRCODE	256

/* YYLLOC_DEFAULT -- Compute the default location (before the actions
   are run).  */

#ifndef YYLLOC_DEFAULT
# define YYLLOC_DEFAULT(Current, Rhs, N)           \
  Current.first_line   = Rhs[1].first_line;      \
  Current.first_column = Rhs[1].first_column;    \
  Current.last_line    = Rhs[N].last_line;       \
  Current.last_column  = Rhs[N].last_column;
#endif

/* YYLEX -- calling `yylex' with the right arguments.  */

#ifdef YYLEX_PARAM
# define YYLEX	yylex (&yylval, YYLEX_PARAM)
#else
# define YYLEX	yylex (&yylval)
#endif

/* Enable debugging if requested.  */
#if YYDEBUG

# ifndef YYFPRINTF
#  include <stdio.h> /* INFRINGES ON USER NAME SPACE */
#  define YYFPRINTF fprintf
# endif

# define YYDPRINTF(Args)			\
do {						\
  if (yydebug)					\
    YYFPRINTF Args;				\
} while (0)
# define YYDSYMPRINT(Args)			\
do {						\
  if (yydebug)					\
    yysymprint Args;				\
} while (0)
/* Nonzero means print parse trace.  It is left uninitialized so that
   multiple parsers can coexist.  */
int yydebug;
#else /* !YYDEBUG */
# define YYDPRINTF(Args)
# define YYDSYMPRINT(Args)
#endif /* !YYDEBUG */

/* YYINITDEPTH -- initial size of the parser's stacks.  */
#ifndef	YYINITDEPTH
# define YYINITDEPTH 200
#endif

/* YYMAXDEPTH -- maximum size the stacks can grow to (effective only
   if the built-in stack extension method is used).

   Do not make this value too large; the results are undefined if
   SIZE_MAX < YYSTACK_BYTES (YYMAXDEPTH)
   evaluated with infinite-precision integer arithmetic.  */

#if YYMAXDEPTH == 0
# undef YYMAXDEPTH
#endif

#ifndef YYMAXDEPTH
# define YYMAXDEPTH 10000
#endif



#if YYERROR_VERBOSE

# ifndef yystrlen
#  if defined (__GLIBC__) && defined (_STRING_H)
#   define yystrlen strlen
#  else
/* Return the length of YYSTR.  */
static YYSIZE_T
#   if defined (__STDC__) || defined (__cplusplus)
yystrlen (const char *yystr)
#   else
yystrlen (yystr)
     const char *yystr;
#   endif
{
  register const char *yys = yystr;

  while (*yys++ != '\0')
    continue;

  return yys - yystr - 1;
}
#  endif
# endif

# ifndef yystpcpy
#  if defined (__GLIBC__) && defined (_STRING_H) && defined (_GNU_SOURCE)
#   define yystpcpy stpcpy
#  else
/* Copy YYSRC to YYDEST, returning the address of the terminating '\0' in
   YYDEST.  */
static char *
#   if defined (__STDC__) || defined (__cplusplus)
yystpcpy (char *yydest, const char *yysrc)
#   else
yystpcpy (yydest, yysrc)
     char *yydest;
     const char *yysrc;
#   endif
{
  register char *yyd = yydest;
  register const char *yys = yysrc;

  while ((*yyd++ = *yys++) != '\0')
    continue;

  return yyd - 1;
}
#  endif
# endif

#endif /* !YYERROR_VERBOSE */



#if YYDEBUG
/*-----------------------------.
| Print this symbol on YYOUT.  |
`-----------------------------*/

static void
#if defined (__STDC__) || defined (__cplusplus)
yysymprint (FILE* yyout, int yytype, YYSTYPE yyvalue)
#else
yysymprint (yyout, yytype, yyvalue)
    FILE* yyout;
    int yytype;
    YYSTYPE yyvalue;
#endif
{
  /* Pacify ``unused variable'' warnings.  */
  (void) yyvalue;

  if (yytype < YYNTOKENS)
    {
      YYFPRINTF (yyout, "token %s (", yytname[yytype]);
# ifdef YYPRINT
      YYPRINT (yyout, yytoknum[yytype], yyvalue);
# endif
    }
  else
    YYFPRINTF (yyout, "nterm %s (", yytname[yytype]);

  switch (yytype)
    {
      default:
        break;
    }
  YYFPRINTF (yyout, ")");
}
#endif /* YYDEBUG. */


/*-----------------------------------------------.
| Release the memory associated to this symbol.  |
`-----------------------------------------------*/

static void
#if defined (__STDC__) || defined (__cplusplus)
yydestruct (int yytype, YYSTYPE yyvalue)
#else
yydestruct (yytype, yyvalue)
    int yytype;
    YYSTYPE yyvalue;
#endif
{
  /* Pacify ``unused variable'' warnings.  */
  (void) yyvalue;

  switch (yytype)
    {
      default:
        break;
    }
}



/* The user can define YYPARSE_PARAM as the name of an argument to be passed
   into yyparse.  The argument should have type void *.
   It should actually point to an object.
   Grammar actions can access the variable by casting it
   to the proper pointer type.  */

#ifdef YYPARSE_PARAM
# if defined (__STDC__) || defined (__cplusplus)
#  define YYPARSE_PARAM_ARG void *YYPARSE_PARAM
#  define YYPARSE_PARAM_DECL
# else
#  define YYPARSE_PARAM_ARG YYPARSE_PARAM
#  define YYPARSE_PARAM_DECL void *YYPARSE_PARAM;
# endif
#else /* !YYPARSE_PARAM */
# define YYPARSE_PARAM_ARG
# define YYPARSE_PARAM_DECL
#endif /* !YYPARSE_PARAM */

/* Prevent warning if -Wstrict-prototypes.  */
#ifdef __GNUC__
# ifdef YYPARSE_PARAM
int yyparse (void *);
# else
int yyparse (void);
# endif
#endif




int
yyparse (YYPARSE_PARAM_ARG)
     YYPARSE_PARAM_DECL
{
  /* The lookahead symbol.  */
int yychar;

/* The semantic value of the lookahead symbol.  */
YYSTYPE yylval;

/* Number of parse errors so far.  */
int yynerrs;

  register int yystate;
  register int yyn;
  int yyresult;
  /* Number of tokens to shift before error messages enabled.  */
  int yyerrstatus;
  /* Lookahead token as an internal (translated) token number.  */
  int yychar1 = 0;

  /* Three stacks and their tools:
     `yyss': related to states,
     `yyvs': related to semantic values,
     `yyls': related to locations.

     Refer to the stacks thru separate pointers, to allow yyoverflow
     to reallocate them elsewhere.  */

  /* The state stack.  */
  short	yyssa[YYINITDEPTH];
  short *yyss = yyssa;
  register short *yyssp;

  /* The semantic value stack.  */
  YYSTYPE yyvsa[YYINITDEPTH];
  YYSTYPE *yyvs = yyvsa;
  register YYSTYPE *yyvsp;



#define YYPOPSTACK   (yyvsp--, yyssp--)

  YYSIZE_T yystacksize = YYINITDEPTH;

  /* The variables used to return semantic value and location from the
     action routines.  */
  YYSTYPE yyval;


  /* When reducing, the number of symbols on the RHS of the reduced
     rule.  */
  int yylen;

  YYDPRINTF ((stderr, "Starting parse\n"));

  yystate = 0;
  yyerrstatus = 0;
  yynerrs = 0;
  yychar = YYEMPTY;		/* Cause a token to be read.  */

  /* Initialize stack pointers.
     Waste one element of value and location stack
     so that they stay on the same level as the state stack.
     The wasted elements are never initialized.  */

  yyssp = yyss;
  yyvsp = yyvs;

  goto yysetstate;

/*------------------------------------------------------------.
| yynewstate -- Push a new state, which is found in yystate.  |
`------------------------------------------------------------*/
 yynewstate:
  /* In all cases, when you get here, the value and location stacks
     have just been pushed. so pushing a state here evens the stacks.
     */
  yyssp++;

 yysetstate:
  *yyssp = yystate;

  if (yyssp >= yyss + yystacksize - 1)
    {
      /* Get the current used size of the three stacks, in elements.  */
      YYSIZE_T yysize = yyssp - yyss + 1;

#ifdef yyoverflow
      {
	/* Give user a chance to reallocate the stack. Use copies of
	   these so that the &'s don't force the real ones into
	   memory.  */
	YYSTYPE *yyvs1 = yyvs;
	short *yyss1 = yyss;


	/* Each stack pointer address is followed by the size of the
	   data in use in that stack, in bytes.  This used to be a
	   conditional around just the two extra args, but that might
	   be undefined if yyoverflow is a macro.  */
	yyoverflow ("parser stack overflow",
		    &yyss1, yysize * sizeof (*yyssp),
		    &yyvs1, yysize * sizeof (*yyvsp),

		    &yystacksize);

	yyss = yyss1;
	yyvs = yyvs1;
      }
#else /* no yyoverflow */
# ifndef YYSTACK_RELOCATE
      goto yyoverflowlab;
# else
      /* Extend the stack our own way.  */
      if (yystacksize >= YYMAXDEPTH)
	goto yyoverflowlab;
      yystacksize *= 2;
      if (yystacksize > YYMAXDEPTH)
	yystacksize = YYMAXDEPTH;

      {
	short *yyss1 = yyss;
	union yyalloc *yyptr =
	  (union yyalloc *) YYSTACK_ALLOC (YYSTACK_BYTES (yystacksize));
	if (! yyptr)
	  goto yyoverflowlab;
	YYSTACK_RELOCATE (yyss);
	YYSTACK_RELOCATE (yyvs);

#  undef YYSTACK_RELOCATE
	if (yyss1 != yyssa)
	  YYSTACK_FREE (yyss1);
      }
# endif
#endif /* no yyoverflow */

      yyssp = yyss + yysize - 1;
      yyvsp = yyvs + yysize - 1;


      YYDPRINTF ((stderr, "Stack size increased to %lu\n",
		  (unsigned long int) yystacksize));

      if (yyssp >= yyss + yystacksize - 1)
	YYABORT;
    }

  YYDPRINTF ((stderr, "Entering state %d\n", yystate));

  goto yybackup;

/*-----------.
| yybackup.  |
`-----------*/
yybackup:

/* Do appropriate processing given the current state.  */
/* Read a lookahead token if we need one and don't already have one.  */
/* yyresume: */

  /* First try to decide what to do without reference to lookahead token.  */

  yyn = yypact[yystate];
  if (yyn == YYPACT_NINF)
    goto yydefault;

  /* Not known => get a lookahead token if don't already have one.  */

  /* yychar is either YYEMPTY or YYEOF
     or a valid token in external form.  */

  if (yychar == YYEMPTY)
    {
      YYDPRINTF ((stderr, "Reading a token: "));
      yychar = YYLEX;
    }

  /* Convert token to internal form (in yychar1) for indexing tables with.  */

  if (yychar <= 0)		/* This means end of input.  */
    {
      yychar1 = 0;
      yychar = YYEOF;		/* Don't call YYLEX any more.  */

      YYDPRINTF ((stderr, "Now at end of input.\n"));
    }
  else
    {
      yychar1 = YYTRANSLATE (yychar);

      /* We have to keep this `#if YYDEBUG', since we use variables
	 which are defined only if `YYDEBUG' is set.  */
      YYDPRINTF ((stderr, "Next token is "));
      YYDSYMPRINT ((stderr, yychar1, yylval));
      YYDPRINTF ((stderr, "\n"));
    }

  /* If the proper action on seeing token YYCHAR1 is to reduce or to
     detect an error, take that action.  */
  yyn += yychar1;
  if (yyn < 0 || YYLAST < yyn || yycheck[yyn] != yychar1)
    goto yydefault;
  yyn = yytable[yyn];
  if (yyn <= 0)
    {
      if (yyn == 0 || yyn == YYTABLE_NINF)
	goto yyerrlab;
      yyn = -yyn;
      goto yyreduce;
    }

  if (yyn == YYFINAL)
    YYACCEPT;

  /* Shift the lookahead token.  */
  YYDPRINTF ((stderr, "Shifting token %d (%s), ",
	      yychar, yytname[yychar1]));

  /* Discard the token being shifted unless it is eof.  */
  if (yychar != YYEOF)
    yychar = YYEMPTY;

  *++yyvsp = yylval;


  /* Count tokens shifted since error; after three, turn off error
     status.  */
  if (yyerrstatus)
    yyerrstatus--;

  yystate = yyn;
  goto yynewstate;


/*-----------------------------------------------------------.
| yydefault -- do the default action for the current state.  |
`-----------------------------------------------------------*/
yydefault:
  yyn = yydefact[yystate];
  if (yyn == 0)
    goto yyerrlab;
  goto yyreduce;


/*-----------------------------.
| yyreduce -- Do a reduction.  |
`-----------------------------*/
yyreduce:
  /* yyn is the number of a rule to reduce with.  */
  yylen = yyr2[yyn];

  /* If YYLEN is nonzero, implement the default value of the action:
     `$$ = $1'.

     Otherwise, the following line sets YYVAL to garbage.
     This behavior is undocumented and Bison
     users should not rely upon it.  Assigning to YYVAL
     unconditionally makes the parser a bit smaller, and it avoids a
     GCC warning that YYVAL may be used uninitialized.  */
  yyval = yyvsp[1-yylen];



#if YYDEBUG
  /* We have to keep this `#if YYDEBUG', since we use variables which
     are defined only if `YYDEBUG' is set.  */
  if (yydebug)
    {
      int yyi;

      YYFPRINTF (stderr, "Reducing via rule %d (line %d), ",
		 yyn - 1, yyrline[yyn]);

      /* Print the symbols being reduced, and their result.  */
      for (yyi = yyprhs[yyn]; yyrhs[yyi] >= 0; yyi++)
	YYFPRINTF (stderr, "%s ", yytname[yyrhs[yyi]]);
      YYFPRINTF (stderr, " -> %s\n", yytname[yyr1[yyn]]);
    }
#endif
  switch (yyn)
    {
        case 2:
#line 45 "gram.y"
    {
           ((SyckParser *)parser)->root = syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData );
        }
    break;

  case 3:
#line 49 "gram.y"
    {
           ((SyckParser *)parser)->root = syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData );
        }
    break;

  case 4:
#line 53 "gram.y"
    {
           ((SyckParser *)parser)->eof = 1;
        }
    break;

  case 8:
#line 64 "gram.y"
    { 
           /*
            * _Anchors_: The language binding must keep a separate symbol table
            * for anchors.  The actual ID in the symbol table is returned to the
            * higher nodes, though.
            */
           yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
        }
    break;

  case 9:
#line 73 "gram.y"
    {
           yyval.nodeData = yyvsp[-1].nodeData;
        }
    break;

  case 10:
#line 77 "gram.y"
    {
           yyval.nodeData = yyvsp[-1].nodeData;
        }
    break;

  case 12:
#line 84 "gram.y"
    {
                   SyckNode *n = syck_new_str( "" ); 
                   if ( ((SyckParser *)parser)->taguri_expansion == 1 )
                   {
                       n->type_id = syck_taguri( YAML_DOMAIN, "null", 4 );
                   }
                   else
                   {
                       n->type_id = syck_strndup( "null", 4 );
                   }
                   yyval.nodeData = n;
                }
    break;

  case 13:
#line 97 "gram.y"
    {
                   SyckNode *n = syck_new_str( "" ); 
                   if ( ((SyckParser *)parser)->taguri_expansion == 1 )
                   {
                       n->type_id = syck_taguri( YAML_DOMAIN, "null", 4 );
                   }
                   else
                   {
                       n->type_id = syck_strndup( "null", 4 );
                   }
                   yyval.nodeData = n;
                }
    break;

  case 20:
#line 134 "gram.y"
    { 
               syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
               yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 21:
#line 139 "gram.y"
    { 
               if ( ((SyckParser *)parser)->implicit_typing == 1 )
               {
                  try_tag_implicit( yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
               }
               yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 22:
#line 147 "gram.y"
    { 
               yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
            }
    break;

  case 23:
#line 151 "gram.y"
    {
               /*
                * _Aliases_: The anchor symbol table is scanned for the anchor name.
                * The anchor's ID in the language's symbol table is returned.
                */
               yyval.nodeData = syck_hdlr_get_anchor( (SyckParser *)parser, yyvsp[0].name );
            }
    break;

  case 24:
#line 159 "gram.y"
    { 
               SyckNode *n = yyvsp[0].nodeData;
               if ( ((SyckParser *)parser)->taguri_expansion == 1 )
               {
                   n->type_id = syck_taguri( YAML_DOMAIN, "str", 3 );
               }
               else
               {
                   n->type_id = syck_strndup( "str", 3 );
               }
               yyval.nodeData = n;
            }
    break;

  case 26:
#line 179 "gram.y"
    { 
                syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 32:
#line 194 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 33:
#line 200 "gram.y"
    { 
                    yyval.nodeId = syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData );
                }
    break;

  case 35:
#line 207 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-2].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 36:
#line 212 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 37:
#line 217 "gram.y"
    { 
                    yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-2].name, yyvsp[0].nodeData );
                }
    break;

  case 38:
#line 221 "gram.y"
    { 
                    yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
                }
    break;

  case 39:
#line 227 "gram.y"
    {
                    yyval.nodeData = syck_new_seq( yyvsp[0].nodeId );
                }
    break;

  case 40:
#line 231 "gram.y"
    { 
                    syck_seq_add( yyvsp[-2].nodeData, yyvsp[0].nodeId );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;

  case 41:
#line 236 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
				}
    break;

  case 42:
#line 245 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 43:
#line 249 "gram.y"
    { 
                    yyval.nodeData = syck_alloc_seq();
                }
    break;

  case 44:
#line 255 "gram.y"
    {
                    yyval.nodeData = syck_new_seq( syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 45:
#line 259 "gram.y"
    { 
                    syck_seq_add( yyvsp[-2].nodeData, syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;

  case 46:
#line 269 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-1].nodeData );
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 47:
#line 274 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-1].nodeData );
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 48:
#line 281 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-2].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 49:
#line 286 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 50:
#line 291 "gram.y"
    { 
                    yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-2].name, yyvsp[0].nodeData );
                }
    break;

  case 51:
#line 295 "gram.y"
    { 
                    yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
                }
    break;

  case 52:
#line 301 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-2].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 54:
#line 317 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-3].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 56:
#line 326 "gram.y"
    { 
                    if ( yyvsp[-2].nodeData->shortcut == NULL )
                    {
                        yyvsp[-2].nodeData->shortcut = syck_new_seq( yyvsp[0].nodeId );
                    }
                    else
                    {
                        syck_seq_add( yyvsp[-2].nodeData->shortcut, yyvsp[0].nodeId );
                    }
                    yyval.nodeData = yyvsp[-2].nodeData;
                }
    break;

  case 57:
#line 338 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-2].nodeData );
                    syck_map_update( yyvsp[-2].nodeData, yyvsp[0].nodeData );
                    syck_free_node( yyvsp[0].nodeData );
                    yyval.nodeData = yyvsp[-2].nodeData;
                }
    break;

  case 58:
#line 345 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 59:
#line 354 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-2].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 60:
#line 362 "gram.y"
    {
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 61:
#line 366 "gram.y"
    {
                    yyval.nodeData = syck_alloc_map();
                }
    break;

  case 63:
#line 373 "gram.y"
    {
                    syck_map_update( yyvsp[-2].nodeData, yyvsp[0].nodeData );
                    syck_free_node( yyvsp[0].nodeData );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;


    }

/* Line 1016 of /usr/local/share/bison/yacc.c.  */
#line 1464 "y.tab.c"

  yyvsp -= yylen;
  yyssp -= yylen;


#if YYDEBUG
  if (yydebug)
    {
      short *yyssp1 = yyss - 1;
      YYFPRINTF (stderr, "state stack now");
      while (yyssp1 != yyssp)
	YYFPRINTF (stderr, " %d", *++yyssp1);
      YYFPRINTF (stderr, "\n");
    }
#endif

  *++yyvsp = yyval;


  /* Now `shift' the result of the reduction.  Determine what state
     that goes to, based on the state we popped back to and the rule
     number reduced by.  */

  yyn = yyr1[yyn];

  yystate = yypgoto[yyn - YYNTOKENS] + *yyssp;
  if (0 <= yystate && yystate <= YYLAST && yycheck[yystate] == *yyssp)
    yystate = yytable[yystate];
  else
    yystate = yydefgoto[yyn - YYNTOKENS];

  goto yynewstate;


/*------------------------------------.
| yyerrlab -- here on detecting error |
`------------------------------------*/
yyerrlab:
  /* If not already recovering from an error, report this error.  */
  if (!yyerrstatus)
    {
      ++yynerrs;
#if YYERROR_VERBOSE
      yyn = yypact[yystate];

      if (YYPACT_NINF < yyn && yyn < YYLAST)
	{
	  YYSIZE_T yysize = 0;
	  int yytype = YYTRANSLATE (yychar);
	  char *yymsg;
	  int yyx, yycount;

	  yycount = 0;
	  /* Start YYX at -YYN if negative to avoid negative indexes in
	     YYCHECK.  */
	  for (yyx = yyn < 0 ? -yyn : 0;
	       yyx < (int) (sizeof (yytname) / sizeof (char *)); yyx++)
	    if (yycheck[yyx + yyn] == yyx && yyx != YYTERROR)
	      yysize += yystrlen (yytname[yyx]) + 15, yycount++;
	  yysize += yystrlen ("parse error, unexpected ") + 1;
	  yysize += yystrlen (yytname[yytype]);
	  yymsg = (char *) YYSTACK_ALLOC (yysize);
	  if (yymsg != 0)
	    {
	      char *yyp = yystpcpy (yymsg, "parse error, unexpected ");
	      yyp = yystpcpy (yyp, yytname[yytype]);

	      if (yycount < 5)
		{
		  yycount = 0;
		  for (yyx = yyn < 0 ? -yyn : 0;
		       yyx < (int) (sizeof (yytname) / sizeof (char *));
		       yyx++)
		    if (yycheck[yyx + yyn] == yyx && yyx != YYTERROR)
		      {
			const char *yyq = ! yycount ? ", expecting " : " or ";
			yyp = yystpcpy (yyp, yyq);
			yyp = yystpcpy (yyp, yytname[yyx]);
			yycount++;
		      }
		}
	      yyerror (yymsg);
	      YYSTACK_FREE (yymsg);
	    }
	  else
	    yyerror ("parse error; also virtual memory exhausted");
	}
      else
#endif /* YYERROR_VERBOSE */
	yyerror ("parse error");
    }
  goto yyerrlab1;


/*----------------------------------------------------.
| yyerrlab1 -- error raised explicitly by an action.  |
`----------------------------------------------------*/
yyerrlab1:
  if (yyerrstatus == 3)
    {
      /* If just tried and failed to reuse lookahead token after an
	 error, discard it.  */

      /* Return failure if at end of input.  */
      if (yychar == YYEOF)
        {
	  /* Pop the error token.  */
          YYPOPSTACK;
	  /* Pop the rest of the stack.  */
	  while (yyssp > yyss)
	    {
	      YYDPRINTF ((stderr, "Error: popping "));
	      YYDSYMPRINT ((stderr,
			    yystos[*yyssp],
			    *yyvsp));
	      YYDPRINTF ((stderr, "\n"));
	      yydestruct (yystos[*yyssp], *yyvsp);
	      YYPOPSTACK;
	    }
	  YYABORT;
        }

      YYDPRINTF ((stderr, "Discarding token %d (%s).\n",
		  yychar, yytname[yychar1]));
      yydestruct (yychar1, yylval);
      yychar = YYEMPTY;
    }

  /* Else will try to reuse lookahead token after shifting the error
     token.  */

  yyerrstatus = 3;	/* Each real token shifted decrements this.  */

  for (;;)
    {
      yyn = yypact[yystate];
      if (yyn != YYPACT_NINF)
	{
	  yyn += YYTERROR;
	  if (0 <= yyn && yyn <= YYLAST && yycheck[yyn] == YYTERROR)
	    {
	      yyn = yytable[yyn];
	      if (0 < yyn)
		break;
	    }
	}

      /* Pop the current state because it cannot handle the error token.  */
      if (yyssp == yyss)
	YYABORT;

      YYDPRINTF ((stderr, "Error: popping "));
      YYDSYMPRINT ((stderr,
		    yystos[*yyssp], *yyvsp));
      YYDPRINTF ((stderr, "\n"));

      yydestruct (yystos[yystate], *yyvsp);
      yyvsp--;
      yystate = *--yyssp;


#if YYDEBUG
      if (yydebug)
	{
	  short *yyssp1 = yyss - 1;
	  YYFPRINTF (stderr, "Error: state stack now");
	  while (yyssp1 != yyssp)
	    YYFPRINTF (stderr, " %d", *++yyssp1);
	  YYFPRINTF (stderr, "\n");
	}
#endif
    }

  if (yyn == YYFINAL)
    YYACCEPT;

  YYDPRINTF ((stderr, "Shifting error token, "));

  *++yyvsp = yylval;


  yystate = yyn;
  goto yynewstate;


/*-------------------------------------.
| yyacceptlab -- YYACCEPT comes here.  |
`-------------------------------------*/
yyacceptlab:
  yyresult = 0;
  goto yyreturn;

/*-----------------------------------.
| yyabortlab -- YYABORT comes here.  |
`-----------------------------------*/
yyabortlab:
  yyresult = 1;
  goto yyreturn;

#ifndef yyoverflow
/*----------------------------------------------.
| yyoverflowlab -- parser overflow comes here.  |
`----------------------------------------------*/
yyoverflowlab:
  yyerror ("parser stack overflow");
  yyresult = 2;
  /* Fall through.  */
#endif

yyreturn:
#ifndef yyoverflow
  if (yyss != yyssa)
    YYSTACK_FREE (yyss);
#endif
  return yyresult;
}


#line 380 "gram.y"


void
apply_seq_in_map( SyckParser *parser, SyckNode *n )
{
    long map_len;
    if ( n->shortcut == NULL )
    {
        return;
    }

    map_len = syck_map_count( n );
    syck_map_assign( n, map_value, map_len - 1,
        syck_hdlr_add_node( parser, n->shortcut ) );

    n->shortcut = NULL;
}


