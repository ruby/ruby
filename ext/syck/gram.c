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
     YAML_TAGURI = 261,
     YAML_ITRANSFER = 262,
     YAML_WORD = 263,
     YAML_PLAIN = 264,
     YAML_BLOCK = 265,
     YAML_DOCSEP = 266,
     YAML_IOPEN = 267,
     YAML_INDENT = 268,
     YAML_IEND = 269
   };
#endif
#define YAML_ANCHOR 258
#define YAML_ALIAS 259
#define YAML_TRANSFER 260
#define YAML_TAGURI 261
#define YAML_ITRANSFER 262
#define YAML_WORD 263
#define YAML_PLAIN 264
#define YAML_BLOCK 265
#define YAML_DOCSEP 266
#define YAML_IOPEN 267
#define YAML_INDENT 268
#define YAML_IEND 269




/* Copy the first part of user declarations.  */
#line 14 "gram.y"


#include "syck.h"

#define YYPARSE_PARAM   parser
#define YYLEX_PARAM     parser

#define NULL_NODE(parser, node) \
        SyckNode *node = syck_new_str( "" ); \
        if ( ((SyckParser *)parser)->taguri_expansion == 1 ) \
        { \
            node->type_id = syck_taguri( YAML_DOMAIN, "null", 4 ); \
        } \
        else \
        { \
            node->type_id = syck_strndup( "null", 4 ); \
        }


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
#line 33 "gram.y"
typedef union {
    SYMID nodeId;
    SyckNode *nodeData;
    char *name;
} yystype;
/* Line 193 of /usr/local/share/bison/yacc.c.  */
#line 135 "y.tab.c"
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


/* Line 213 of /usr/local/share/bison/yacc.c.  */
#line 156 "y.tab.c"

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
#define YYFINAL  43
#define YYLAST   436

/* YYNTOKENS -- Number of terminals. */
#define YYNTOKENS  23
/* YYNNTS -- Number of nonterminals. */
#define YYNNTS  28
/* YYNRULES -- Number of rules. */
#define YYNRULES  75
/* YYNRULES -- Number of states. */
#define YYNSTATES  128

/* YYTRANSLATE(YYLEX) -- Bison symbol number corresponding to YYLEX.  */
#define YYUNDEFTOK  2
#define YYMAXUTOK   269

#define YYTRANSLATE(X) \
  ((unsigned)(X) <= YYMAXUTOK ? yytranslate[X] : YYUNDEFTOK)

/* YYTRANSLATE[YYLEX] -- Bison symbol number corresponding to YYLEX.  */
static const unsigned char yytranslate[] =
{
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,    21,    15,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,    16,     2,
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
       5,     6,     7,     8,     9,    10,    11,    12,    13,    14
};

#if YYDEBUG
/* YYPRHS[YYN] -- Index of the first RHS symbol of rule number YYN in
   YYRHS.  */
static const unsigned char yyprhs[] =
{
       0,     0,     3,     5,     8,     9,    11,    13,    15,    19,
      21,    24,    28,    32,    34,    37,    38,    40,    43,    45,
      47,    49,    52,    55,    58,    61,    64,    66,    68,    70,
      73,    76,    78,    80,    82,    84,    86,    90,    93,    95,
      99,   102,   106,   109,   113,   116,   118,   122,   125,   129,
     132,   134,   138,   140,   142,   146,   150,   154,   157,   161,
     164,   168,   171,   175,   177,   183,   185,   189,   193,   196,
     200,   204,   207,   209,   213,   215
};

/* YYRHS -- A `-1'-separated list of the rules' RHS. */
static const yysigned_char yyrhs[] =
{
      24,     0,    -1,    26,    -1,    11,    28,    -1,    -1,    33,
      -1,    27,    -1,    34,    -1,    29,    26,    32,    -1,    34,
      -1,     3,    27,    -1,    29,    33,    32,    -1,    29,    27,
      32,    -1,    25,    -1,    29,    30,    -1,    -1,    12,    -1,
      29,    13,    -1,    14,    -1,    13,    -1,    14,    -1,    31,
      32,    -1,     5,    33,    -1,     6,    33,    -1,     7,    33,
      -1,     3,    33,    -1,     4,    -1,     8,    -1,     9,    -1,
       5,    34,    -1,     6,    34,    -1,    10,    -1,    35,    -1,
      39,    -1,    42,    -1,    48,    -1,    29,    37,    30,    -1,
      15,    28,    -1,    38,    -1,     5,    31,    37,    -1,     5,
      37,    -1,     6,    31,    37,    -1,     6,    37,    -1,     3,
      31,    37,    -1,     3,    37,    -1,    36,    -1,    38,    31,
      36,    -1,    38,    31,    -1,    17,    40,    18,    -1,    17,
      18,    -1,    41,    -1,    40,    21,    41,    -1,    25,    -1,
      47,    -1,    29,    43,    30,    -1,    29,    46,    30,    -1,
       5,    31,    46,    -1,     5,    43,    -1,     6,    31,    46,
      -1,     6,    43,    -1,     3,    31,    46,    -1,     3,    43,
      -1,    33,    16,    28,    -1,    44,    -1,    22,    25,    31,
      16,    28,    -1,    45,    -1,    46,    31,    36,    -1,    46,
      31,    45,    -1,    46,    31,    -1,    25,    16,    28,    -1,
      19,    49,    20,    -1,    19,    20,    -1,    50,    -1,    49,
      21,    50,    -1,    25,    -1,    47,    -1
};

/* YYRLINE[YYN] -- source line where rule number YYN was defined.  */
static const unsigned short yyrline[] =
{
       0,    54,    54,    58,    62,    68,    69,    72,    73,    79,
      80,    89,    93,    99,   100,   105,   115,   116,   119,   122,
     125,   126,   134,   139,   144,   152,   156,   164,   177,   184,
     189,   194,   195,   196,   197,   198,   204,   210,   216,   217,
     222,   227,   232,   237,   241,   247,   251,   256,   265,   269,
     275,   279,   286,   287,   293,   298,   305,   310,   315,   320,
     325,   329,   335,   350,   351,   369,   370,   382,   389,   398,
     406,   410,   416,   417,   425,   432
};
#endif

#if YYDEBUG || YYERROR_VERBOSE
/* YYTNME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
   First, the terminals, then, starting at YYNTOKENS, nonterminals. */
static const char *const yytname[] =
{
  "$end", "error", "$undefined", "YAML_ANCHOR", "YAML_ALIAS", 
  "YAML_TRANSFER", "YAML_TAGURI", "YAML_ITRANSFER", "YAML_WORD", 
  "YAML_PLAIN", "YAML_BLOCK", "YAML_DOCSEP", "YAML_IOPEN", "YAML_INDENT", 
  "YAML_IEND", "'-'", "':'", "'['", "']'", "'{'", "'}'", "','", "'?'", 
  "$accept", "doc", "atom", "doc_struct_rep", "ind_rep", "atom_or_empty", 
  "indent_open", "indent_end", "indent_sep", "indent_flex_end", 
  "word_rep", "struct_rep", "implicit_seq", "basic_seq", "top_imp_seq", 
  "in_implicit_seq", "inline_seq", "in_inline_seq", "inline_seq_atom", 
  "implicit_map", "top_imp_map", "basic_mapping", "complex_mapping", 
  "in_implicit_map", "basic_mapping2", "inline_map", "in_inline_map", 
  "inline_map_atom", 0
};
#endif

# ifdef YYPRINT
/* YYTOKNUM[YYLEX-NUM] -- Internal token number corresponding to
   token YYLEX-NUM.  */
static const unsigned short yytoknum[] =
{
       0,   256,   257,   258,   259,   260,   261,   262,   263,   264,
     265,   266,   267,   268,   269,    45,    58,    91,    93,   123,
     125,    44,    63
};
# endif

/* YYR1[YYN] -- Symbol number of symbol that rule YYN derives.  */
static const unsigned char yyr1[] =
{
       0,    23,    24,    24,    24,    25,    25,    26,    26,    27,
      27,    27,    27,    28,    28,    28,    29,    29,    30,    31,
      32,    32,    33,    33,    33,    33,    33,    33,    33,    34,
      34,    34,    34,    34,    34,    34,    35,    36,    37,    37,
      37,    37,    37,    37,    37,    38,    38,    38,    39,    39,
      40,    40,    41,    41,    42,    42,    43,    43,    43,    43,
      43,    43,    44,    45,    45,    46,    46,    46,    46,    47,
      48,    48,    49,    49,    50,    50
};

/* YYR2[YYN] -- Number of symbols composing right hand side of rule YYN.  */
static const unsigned char yyr2[] =
{
       0,     2,     1,     2,     0,     1,     1,     1,     3,     1,
       2,     3,     3,     1,     2,     0,     1,     2,     1,     1,
       1,     2,     2,     2,     2,     2,     1,     1,     1,     2,
       2,     1,     1,     1,     1,     1,     3,     2,     1,     3,
       2,     3,     2,     3,     2,     1,     3,     2,     3,     2,
       1,     3,     1,     1,     3,     3,     3,     2,     3,     2,
       3,     2,     3,     1,     5,     1,     3,     3,     2,     3,
       3,     2,     1,     3,     1,     1
};

/* YYDEFACT[STATE-NAME] -- Default rule to reduce with in state
   STATE-NUM when YYTABLE doesn't specify something else to do.  Zero
   means the default is an error.  */
static const unsigned char yydefact[] =
{
       4,     0,     0,    31,    15,    16,     0,     0,     0,     2,
       0,     7,    32,    33,    34,    35,     0,    29,    30,     0,
      26,     0,     0,     0,    27,    28,    13,     6,     3,     0,
       5,     9,    49,    52,     0,     0,    50,    53,    71,    74,
      75,     0,    72,     1,     0,     0,     0,    17,    15,     0,
       0,     0,    45,     0,    38,     0,    63,    65,     0,     0,
       0,    10,    25,     0,    22,    23,     0,     0,    24,     0,
      18,     0,    14,     0,    15,    48,     0,    70,     0,    19,
       0,    44,    61,     0,    40,    57,     0,    42,    59,    37,
       0,    20,     0,     8,    15,    36,    47,    54,    55,    68,
      12,    11,    69,    51,    73,     0,     0,     0,    43,    60,
      39,    56,    41,    58,     0,    21,    62,    46,    66,    67,
       0,     0,     0,    15,     0,     0,     0,    64
};

/* YYDEFGOTO[NTERM-NUM]. */
static const yysigned_char yydefgoto[] =
{
      -1,     8,    26,     9,    27,    28,    34,    72,    92,    93,
      30,    31,    12,    52,    53,    54,    13,    35,    36,    14,
      55,    56,    57,    58,    37,    15,    41,    42
};

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
#define YYPACT_NINF -77
static const short yypact[] =
{
     103,   155,   155,   -77,   367,   -77,   350,   298,    14,   -77,
     198,   -77,   -77,   -77,   -77,   -77,   238,   -77,   -77,   367,
     -77,   384,   384,   427,   -77,   -77,   -77,   -77,   -77,   174,
     -77,   -77,   -77,     8,   218,   -13,   -77,   -77,   -77,     8,
     -77,     7,   -77,   -77,   401,   316,   316,   -77,   367,   367,
      20,    28,   -77,    -7,    30,    -7,   -77,   -77,    25,   401,
     401,   -77,   -77,   427,   -77,   -77,   427,   427,   -77,   333,
     -77,    20,   -77,   111,   367,   -77,   367,   -77,   367,   -77,
     258,   -77,   -77,   258,   -77,   -77,   258,   -77,   -77,   -77,
      30,   -77,    20,   -77,   367,   -77,    32,   -77,   -77,   278,
     -77,   -77,   -77,   -77,   -77,   414,   414,   414,   -77,    30,
     -77,    30,   -77,    30,    37,   -77,   -77,   -77,   -77,   -77,
      85,    85,    85,   367,   113,   113,   113,   -77
};

/* YYPGOTO[NTERM-NUM].  */
static const short yypgoto[] =
{
     -77,   -77,    92,    57,    -3,   -45,     0,    -1,    27,   -60,
      -4,   154,   -77,   -76,    24,   -77,   -77,   -77,     1,   -77,
      -9,   -77,   -24,   -22,     2,   -77,   -77,    11
};

/* YYTABLE[YYPACT[STATE-NUM]].  What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule which
   number is the opposite.  If zero, do what YYDEFACT says.
   If YYTABLE_NINF, parse error.  */
#define YYTABLE_NINF -1
static const unsigned char yytable[] =
{
      10,    16,    16,    89,    29,    75,    51,    70,    76,    40,
      10,   100,    51,   101,    43,    62,    61,    64,    65,    68,
     117,    16,    16,   118,    74,    73,    71,    77,    78,   102,
      73,    71,   115,    79,    91,    82,    85,    88,    79,    70,
      62,    64,    65,    79,    94,    16,    16,    48,    29,   116,
      85,    88,    95,   123,    97,    64,    65,    98,   109,    62,
      82,   111,    64,    65,   113,    62,    61,    50,    81,    84,
      87,    80,    83,    86,    29,   119,    51,   103,   127,    51,
      40,    96,    51,    84,    87,    99,    83,    86,   124,   104,
     125,   126,     0,    81,    29,    51,    80,     0,    33,    39,
      48,    62,    64,    65,   108,     0,     0,   110,     1,     2,
     112,     0,     0,     3,     4,     5,   124,   114,   125,   126,
       6,     0,     7,    29,    79,    91,    79,    94,    48,    81,
      84,    87,   120,   121,   122,     0,    99,     0,    99,     0,
      99,    90,     0,     0,   108,   110,   112,     0,    81,    84,
      87,   120,   121,   122,    11,    17,    18,     0,     0,     0,
       1,     2,     0,     0,    11,     3,     0,     5,    33,     0,
      39,     0,     6,     0,     7,    17,    18,    69,    20,    45,
      46,    23,    24,    25,     3,     0,     5,    47,    70,    48,
       0,     6,     0,     7,     0,     0,    49,     0,     0,    17,
      18,    44,    20,    45,    46,    23,    24,    25,     3,     0,
       5,    47,     0,    48,     0,     6,     0,     7,     0,     0,
      49,    69,    20,    45,    46,    23,    24,    25,     3,     0,
       5,    47,     0,    48,     0,     6,     0,     7,     0,     0,
      49,    44,    20,    59,    60,    23,    24,    25,     0,     0,
       0,    47,     0,    48,     0,     0,     0,     0,     0,     0,
      49,   105,    20,   106,   107,    23,    24,    25,     0,     0,
       0,     0,     0,    48,     0,     0,     0,     0,     0,     0,
      49,    63,    20,    66,    67,    23,    24,    25,     0,     0,
       0,     0,     0,    48,     0,     0,     0,     0,     0,     0,
      49,    19,    20,    21,    22,    23,    24,    25,     3,     0,
       5,     0,     0,     0,     0,     6,     0,     7,    38,    44,
      20,    45,    46,    23,    24,    25,     3,     0,     5,    79,
       0,    48,     0,     6,     0,     7,    69,    20,    45,    46,
      23,    24,    25,     3,     0,     5,    79,     0,    48,     0,
       6,     0,     7,    19,    20,    21,    22,    23,    24,    25,
       3,     0,     5,     0,     0,     0,     0,     6,    32,     7,
      19,    20,    21,    22,    23,    24,    25,     3,     0,     5,
       0,     0,     0,     0,     6,     0,     7,    63,    20,    21,
      22,    23,    24,    25,     3,     0,     5,     0,     0,     0,
       0,     6,     0,     7,    44,    20,    59,    60,    23,    24,
      25,     0,     0,     0,    79,     0,    48,   105,    20,   106,
     107,    23,    24,    25,     0,     0,     0,    79,     0,    48,
      63,    20,    66,    67,    23,    24,    25
};

static const yysigned_char yycheck[] =
{
       0,     1,     2,    48,     4,    18,    10,    14,    21,     7,
      10,    71,    16,    73,     0,    19,    19,    21,    22,    23,
      96,    21,    22,    99,    16,    29,    29,    20,    21,    74,
      34,    34,    92,    13,    14,    44,    45,    46,    13,    14,
      44,    45,    46,    13,    16,    45,    46,    15,    48,    94,
      59,    60,    53,    16,    55,    59,    60,    58,    80,    63,
      69,    83,    66,    67,    86,    69,    69,    10,    44,    45,
      46,    44,    45,    46,    74,    99,    80,    76,   123,    83,
      78,    54,    86,    59,    60,    58,    59,    60,     3,    78,
       5,     6,    -1,    69,    94,    99,    69,    -1,     6,     7,
      15,   105,   106,   107,    80,    -1,    -1,    83,     5,     6,
      86,    -1,    -1,    10,    11,    12,     3,    90,     5,     6,
      17,    -1,    19,   123,    13,    14,    13,    16,    15,   105,
     106,   107,   105,   106,   107,    -1,   109,    -1,   111,    -1,
     113,    49,    -1,    -1,   120,   121,   122,    -1,   124,   125,
     126,   124,   125,   126,     0,     1,     2,    -1,    -1,    -1,
       5,     6,    -1,    -1,    10,    10,    -1,    12,    76,    -1,
      78,    -1,    17,    -1,    19,    21,    22,     3,     4,     5,
       6,     7,     8,     9,    10,    -1,    12,    13,    14,    15,
      -1,    17,    -1,    19,    -1,    -1,    22,    -1,    -1,    45,
      46,     3,     4,     5,     6,     7,     8,     9,    10,    -1,
      12,    13,    -1,    15,    -1,    17,    -1,    19,    -1,    -1,
      22,     3,     4,     5,     6,     7,     8,     9,    10,    -1,
      12,    13,    -1,    15,    -1,    17,    -1,    19,    -1,    -1,
      22,     3,     4,     5,     6,     7,     8,     9,    -1,    -1,
      -1,    13,    -1,    15,    -1,    -1,    -1,    -1,    -1,    -1,
      22,     3,     4,     5,     6,     7,     8,     9,    -1,    -1,
      -1,    -1,    -1,    15,    -1,    -1,    -1,    -1,    -1,    -1,
      22,     3,     4,     5,     6,     7,     8,     9,    -1,    -1,
      -1,    -1,    -1,    15,    -1,    -1,    -1,    -1,    -1,    -1,
      22,     3,     4,     5,     6,     7,     8,     9,    10,    -1,
      12,    -1,    -1,    -1,    -1,    17,    -1,    19,    20,     3,
       4,     5,     6,     7,     8,     9,    10,    -1,    12,    13,
      -1,    15,    -1,    17,    -1,    19,     3,     4,     5,     6,
       7,     8,     9,    10,    -1,    12,    13,    -1,    15,    -1,
      17,    -1,    19,     3,     4,     5,     6,     7,     8,     9,
      10,    -1,    12,    -1,    -1,    -1,    -1,    17,    18,    19,
       3,     4,     5,     6,     7,     8,     9,    10,    -1,    12,
      -1,    -1,    -1,    -1,    17,    -1,    19,     3,     4,     5,
       6,     7,     8,     9,    10,    -1,    12,    -1,    -1,    -1,
      -1,    17,    -1,    19,     3,     4,     5,     6,     7,     8,
       9,    -1,    -1,    -1,    13,    -1,    15,     3,     4,     5,
       6,     7,     8,     9,    -1,    -1,    -1,    13,    -1,    15,
       3,     4,     5,     6,     7,     8,     9
};

/* YYSTOS[STATE-NUM] -- The (internal number of the) accessing
   symbol of state STATE-NUM.  */
static const unsigned char yystos[] =
{
       0,     5,     6,    10,    11,    12,    17,    19,    24,    26,
      29,    34,    35,    39,    42,    48,    29,    34,    34,     3,
       4,     5,     6,     7,     8,     9,    25,    27,    28,    29,
      33,    34,    18,    25,    29,    40,    41,    47,    20,    25,
      47,    49,    50,     0,     3,     5,     6,    13,    15,    22,
      26,    33,    36,    37,    38,    43,    44,    45,    46,     5,
       6,    27,    33,     3,    33,    33,     5,     6,    33,     3,
      14,    27,    30,    33,    16,    18,    21,    20,    21,    13,
      31,    37,    43,    31,    37,    43,    31,    37,    43,    28,
      25,    14,    31,    32,    16,    30,    31,    30,    30,    31,
      32,    32,    28,    41,    50,     3,     5,     6,    37,    46,
      37,    46,    37,    46,    31,    32,    28,    36,    36,    45,
      31,    31,    31,    16,     3,     5,     6,    28
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
#line 55 "gram.y"
    {
           ((SyckParser *)parser)->root = syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData );
        }
    break;

  case 3:
#line 59 "gram.y"
    {
           ((SyckParser *)parser)->root = syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData );
        }
    break;

  case 4:
#line 63 "gram.y"
    {
           ((SyckParser *)parser)->eof = 1;
        }
    break;

  case 8:
#line 74 "gram.y"
    {
           yyval.nodeData = yyvsp[-1].nodeData;
        }
    break;

  case 10:
#line 81 "gram.y"
    { 
           /*
            * _Anchors_: The language binding must keep a separate symbol table
            * for anchors.  The actual ID in the symbol table is returned to the
            * higher nodes, though.
            */
           yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
        }
    break;

  case 11:
#line 90 "gram.y"
    {
           yyval.nodeData = yyvsp[-1].nodeData;
        }
    break;

  case 12:
#line 94 "gram.y"
    {
           yyval.nodeData = yyvsp[-1].nodeData;
        }
    break;

  case 14:
#line 101 "gram.y"
    {
                    NULL_NODE( parser, n );
                    yyval.nodeData = n;
                }
    break;

  case 15:
#line 106 "gram.y"
    {
                    NULL_NODE( parser, n );
                    yyval.nodeData = n;
                }
    break;

  case 22:
#line 135 "gram.y"
    { 
               syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
               yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 23:
#line 140 "gram.y"
    { 
               syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, 0 );
               yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 24:
#line 145 "gram.y"
    { 
               if ( ((SyckParser *)parser)->implicit_typing == 1 )
               {
                  try_tag_implicit( yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
               }
               yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 25:
#line 153 "gram.y"
    { 
               yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
            }
    break;

  case 26:
#line 157 "gram.y"
    {
               /*
                * _Aliases_: The anchor symbol table is scanned for the anchor name.
                * The anchor's ID in the language's symbol table is returned.
                */
               yyval.nodeData = syck_hdlr_get_anchor( (SyckParser *)parser, yyvsp[0].name );
            }
    break;

  case 27:
#line 165 "gram.y"
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

  case 29:
#line 185 "gram.y"
    { 
                syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 30:
#line 190 "gram.y"
    {
                syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, 0 );
                yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 36:
#line 205 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 37:
#line 211 "gram.y"
    { 
                    yyval.nodeId = syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData );
                }
    break;

  case 39:
#line 218 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-2].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 40:
#line 223 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 41:
#line 228 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-2].name, yyvsp[0].nodeData, 0 );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 42:
#line 233 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, 0 );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 43:
#line 238 "gram.y"
    { 
                    yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-2].name, yyvsp[0].nodeData );
                }
    break;

  case 44:
#line 242 "gram.y"
    { 
                    yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
                }
    break;

  case 45:
#line 248 "gram.y"
    {
                    yyval.nodeData = syck_new_seq( yyvsp[0].nodeId );
                }
    break;

  case 46:
#line 252 "gram.y"
    { 
                    syck_seq_add( yyvsp[-2].nodeData, yyvsp[0].nodeId );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;

  case 47:
#line 257 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
				}
    break;

  case 48:
#line 266 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 49:
#line 270 "gram.y"
    { 
                    yyval.nodeData = syck_alloc_seq();
                }
    break;

  case 50:
#line 276 "gram.y"
    {
                    yyval.nodeData = syck_new_seq( syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 51:
#line 280 "gram.y"
    { 
                    syck_seq_add( yyvsp[-2].nodeData, syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;

  case 54:
#line 294 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-1].nodeData );
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 55:
#line 299 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-1].nodeData );
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 56:
#line 306 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-2].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 57:
#line 311 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 58:
#line 316 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-2].name, yyvsp[0].nodeData, 0 );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 59:
#line 321 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, 0 );
                    yyval.nodeData = yyvsp[0].nodeData;
                }
    break;

  case 60:
#line 326 "gram.y"
    { 
                    yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-2].name, yyvsp[0].nodeData );
                }
    break;

  case 61:
#line 330 "gram.y"
    { 
                    yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
                }
    break;

  case 62:
#line 336 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-2].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 64:
#line 352 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-3].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 66:
#line 371 "gram.y"
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

  case 67:
#line 383 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-2].nodeData );
                    syck_map_update( yyvsp[-2].nodeData, yyvsp[0].nodeData );
                    syck_free_node( yyvsp[0].nodeData );
                    yyval.nodeData = yyvsp[-2].nodeData;
                }
    break;

  case 68:
#line 390 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 69:
#line 399 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-2].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 70:
#line 407 "gram.y"
    {
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 71:
#line 411 "gram.y"
    {
                    yyval.nodeData = syck_alloc_map();
                }
    break;

  case 73:
#line 418 "gram.y"
    {
                    syck_map_update( yyvsp[-2].nodeData, yyvsp[0].nodeData );
                    syck_free_node( yyvsp[0].nodeData );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;

  case 74:
#line 426 "gram.y"
    {
                    NULL_NODE( parser, n );
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, n ) );
                }
    break;


    }

/* Line 1016 of /usr/local/share/bison/yacc.c.  */
#line 1559 "y.tab.c"

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


#line 435 "gram.y"


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


