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



/* Tokens.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
   /* Put the tokens into the symbol table, so that GDB and other debuggers
      know about them.  */
   enum yytokentype {
     ANCHOR = 258,
     ALIAS = 259,
     TRANSFER = 260,
     ITRANSFER = 261,
     WORD = 262,
     PLAIN = 263,
     BLOCK = 264,
     DOCSEP = 265,
     IOPEN = 266,
     INDENT = 267,
     IEND = 268
   };
#endif
#define ANCHOR 258
#define ALIAS 259
#define TRANSFER 260
#define ITRANSFER 261
#define WORD 262
#define PLAIN 263
#define BLOCK 264
#define DOCSEP 265
#define IOPEN 266
#define INDENT 267
#define IEND 268




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
#line 114 "y.tab.c"
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
#line 135 "y.tab.c"

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
#define YYFINAL  34
#define YYLAST   217

/* YYNTOKENS -- Number of terminals. */
#define YYNTOKENS  23
/* YYNNTS -- Number of nonterminals. */
#define YYNNTS  23
/* YYNRULES -- Number of rules. */
#define YYNRULES  54
/* YYNRULES -- Number of states. */
#define YYNSTATES  88

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
      22,    26,    28,    29,    31,    34,    36,    38,    40,    43,
      46,    49,    52,    54,    56,    58,    61,    63,    65,    67,
      69,    71,    75,    81,    84,    86,    90,    93,    97,   100,
     102,   106,   110,   116,   120,   122,   128,   130,   134,   138,
     141,   145,   149,   152,   154
};

/* YYRHS -- A `-1'-separated list of the rules' RHS. */
static const yysigned_char yyrhs[] =
{
      24,     0,    -1,    33,    -1,    10,    27,    -1,    -1,    32,
      -1,    26,    -1,    33,    -1,     3,    26,    -1,    28,    32,
      31,    -1,    28,    26,    31,    -1,    25,    -1,    -1,    11,
      -1,    28,    12,    -1,    13,    -1,    12,    -1,    13,    -1,
      30,    31,    -1,     5,    32,    -1,     6,    32,    -1,     3,
      32,    -1,     4,    -1,     7,    -1,     8,    -1,     5,    33,
      -1,     9,    -1,    34,    -1,    37,    -1,    39,    -1,    44,
      -1,    28,    36,    29,    -1,    28,     5,    30,    36,    29,
      -1,    14,    27,    -1,    35,    -1,    36,    30,    35,    -1,
      36,    30,    -1,    17,    38,    18,    -1,    17,    18,    -1,
      25,    -1,    38,    21,    25,    -1,    28,    42,    29,    -1,
      28,     5,    30,    42,    29,    -1,    32,    15,    27,    -1,
      40,    -1,    22,    25,    30,    15,    27,    -1,    41,    -1,
      42,    30,    35,    -1,    42,    30,    41,    -1,    42,    30,
      -1,    25,    15,    27,    -1,    19,    45,    20,    -1,    19,
      20,    -1,    43,    -1,    45,    21,    43,    -1
};

/* YYRLINE[YYN] -- source line where rule number YYN was defined.  */
static const unsigned short yyrline[] =
{
       0,    44,    44,    48,    52,    58,    59,    62,    63,    72,
      76,    82,    83,   101,   102,   105,   108,   111,   112,   120,
     125,   133,   137,   145,   158,   165,   170,   171,   172,   173,
     174,   180,   184,   191,   197,   201,   206,   215,   219,   225,
     229,   239,   244,   252,   267,   268,   276,   277,   289,   296,
     305,   313,   317,   323,   324
};
#endif

#if YYDEBUG || YYERROR_VERBOSE
/* YYTNME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
   First, the terminals, then, starting at YYNTOKENS, nonterminals. */
static const char *const yytname[] =
{
  "$end", "error", "$undefined", "ANCHOR", "ALIAS", "TRANSFER", "ITRANSFER", 
  "WORD", "PLAIN", "BLOCK", "DOCSEP", "IOPEN", "INDENT", "IEND", "'-'", 
  "':'", "'+'", "'['", "']'", "'{'", "'}'", "','", "'?'", "$accept", 
  "doc", "atom", "ind_rep", "atom_or_empty", "indent_open", "indent_end", 
  "indent_sep", "indent_flex_end", "word_rep", "struct_rep", 
  "implicit_seq", "basic_seq", "in_implicit_seq", "inline_seq", 
  "in_inline_seq", "implicit_map", "basic_mapping", "complex_mapping", 
  "in_implicit_map", "basic_mapping2", "inline_map", "in_inline_map", 0
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
      26,    27,    27,    28,    28,    29,    30,    31,    31,    32,
      32,    32,    32,    32,    32,    33,    33,    33,    33,    33,
      33,    34,    34,    35,    36,    36,    36,    37,    37,    38,
      38,    39,    39,    40,    41,    41,    42,    42,    42,    42,
      43,    44,    44,    45,    45
};

/* YYR2[YYN] -- Number of symbols composing right hand side of rule YYN.  */
static const unsigned char yyr2[] =
{
       0,     2,     1,     2,     0,     1,     1,     1,     2,     3,
       3,     1,     0,     1,     2,     1,     1,     1,     2,     2,
       2,     2,     1,     1,     1,     2,     1,     1,     1,     1,
       1,     3,     5,     2,     1,     3,     2,     3,     2,     1,
       3,     3,     5,     3,     1,     5,     1,     3,     3,     2,
       3,     3,     2,     1,     3
};

/* YYDEFACT[STATE-NAME] -- Default rule to reduce with in state
   STATE-NUM when YYTABLE doesn't specify something else to do.  Zero
   means the default is an error.  */
static const unsigned char yydefact[] =
{
       4,     0,    26,    12,    13,     0,     0,     0,     0,     2,
      27,    28,    29,    30,    25,     0,    22,     0,     0,    23,
      24,    11,     6,     3,     0,     5,     7,    38,    39,     0,
      52,     0,    53,     0,     1,     0,     0,    14,    12,     0,
       0,    34,     0,    44,    46,     0,     8,    21,    19,     0,
      20,     0,     0,     0,    37,     0,    12,    51,     0,    16,
       0,    33,     0,    12,    15,    31,    36,    41,    49,    17,
       0,    10,     9,    40,    50,    54,     0,     0,     0,    43,
      35,    47,    48,    18,    32,    42,    12,    45
};

/* YYDEFGOTO[NTERM-NUM]. */
static const yysigned_char yydefgoto[] =
{
      -1,     7,    21,    22,    23,    24,    65,    70,    71,    25,
      26,    10,    41,    42,    11,    29,    12,    43,    44,    45,
      32,    13,    33
};

/* YYPACT[STATE-NUM] -- Index in YYTABLE of the portion describing
   STATE-NUM.  */
#define YYPACT_NINF -51
static const short yypact[] =
{
      13,   188,   -51,   166,   -51,   132,   114,    19,    90,   -51,
     -51,   -51,   -51,   -51,   -51,   166,   -51,   183,    61,   -51,
     -51,   -51,   -51,   -51,    70,   -51,   -51,   -51,   -51,    -7,
     -51,    10,   -51,    18,   -51,    61,   205,   -51,   166,   166,
      27,   -51,    46,   -51,   -51,    46,   -51,   -51,   -51,    61,
     -51,   149,    49,    32,   -51,   166,   166,   -51,   166,   -51,
     102,   -51,    38,   166,   -51,   -51,    39,   -51,   102,   -51,
      49,   -51,   -51,   -51,   -51,   -51,    46,    46,    55,   -51,
     -51,   -51,   -51,   -51,   -51,   -51,   166,   -51
};

/* YYPGOTO[NTERM-NUM].  */
static const yysigned_char yypgoto[] =
{
     -51,   -51,    -4,    -9,   -30,     4,   -28,    -5,   -50,    -8,
      12,   -51,   -32,    20,   -51,   -51,   -51,   -51,    15,    25,
      28,   -51,   -51
};

/* YYTABLE[YYPACT[STATE-NUM]].  What to do in state STATE-NUM.  If
   positive, shift that token.  If negative, reduce the rule which
   number is the opposite.  If zero, do what YYDEFACT says.
   If YYTABLE_NINF, parse error.  */
#define YYTABLE_NINF -1
static const unsigned char yytable[] =
{
      40,    28,    31,    72,     8,     8,    46,    47,    61,    48,
      50,    54,     9,    14,    55,    52,    53,    67,     1,    34,
      83,     8,     2,     3,     4,    56,    74,    47,    48,    14,
       5,    60,     6,    79,    80,    62,    81,    66,    57,    58,
      68,    48,    63,    48,    59,    69,    60,    63,    84,    85,
      59,    73,    40,    38,    31,     8,    87,    78,    59,    64,
      40,    59,    69,    14,    35,    16,    49,    18,    19,    20,
      86,    66,    68,    15,    16,    51,    18,    19,    20,     2,
      76,     4,    37,    82,    38,    77,    75,     5,     0,     6,
       0,     0,    39,    35,    16,    36,    18,    19,    20,     0,
       0,     0,    37,     0,    38,    35,    16,    49,    18,    19,
      20,     0,    39,     0,     0,     0,    38,    15,    16,    17,
      18,    19,    20,     2,    39,     4,     0,     0,     0,     0,
       0,     5,     0,     6,    30,    15,    16,    17,    18,    19,
      20,     2,     0,     4,     0,     0,     0,     0,     0,     5,
      27,     6,    35,    16,    17,    18,    19,    20,     2,     0,
       4,    59,     0,     0,     0,     0,     5,     0,     6,    15,
      16,    17,    18,    19,    20,     2,     0,     4,     0,     0,
       0,     0,     0,     5,     0,     6,    35,    16,    17,    18,
      19,    20,     2,     1,     4,     0,     0,     2,     0,     4,
       5,     0,     6,     0,     0,     5,     0,     6,    35,    16,
      49,    18,    19,    20,     0,     0,     0,    59
};

static const yysigned_char yycheck[] =
{
       8,     5,     6,    53,     0,     1,    15,    15,    38,    17,
      18,    18,     0,     1,    21,    24,    24,    45,     5,     0,
      70,    17,     9,    10,    11,    15,    56,    35,    36,    17,
      17,    36,    19,    63,    66,    39,    68,    42,    20,    21,
      45,    49,    15,    51,    12,    13,    51,    15,    76,    77,
      12,    55,    60,    14,    58,    51,    86,    62,    12,    13,
      68,    12,    13,    51,     3,     4,     5,     6,     7,     8,
      15,    76,    77,     3,     4,     5,     6,     7,     8,     9,
      60,    11,    12,    68,    14,    60,    58,    17,    -1,    19,
      -1,    -1,    22,     3,     4,     5,     6,     7,     8,    -1,
      -1,    -1,    12,    -1,    14,     3,     4,     5,     6,     7,
       8,    -1,    22,    -1,    -1,    -1,    14,     3,     4,     5,
       6,     7,     8,     9,    22,    11,    -1,    -1,    -1,    -1,
      -1,    17,    -1,    19,    20,     3,     4,     5,     6,     7,
       8,     9,    -1,    11,    -1,    -1,    -1,    -1,    -1,    17,
      18,    19,     3,     4,     5,     6,     7,     8,     9,    -1,
      11,    12,    -1,    -1,    -1,    -1,    17,    -1,    19,     3,
       4,     5,     6,     7,     8,     9,    -1,    11,    -1,    -1,
      -1,    -1,    -1,    17,    -1,    19,     3,     4,     5,     6,
       7,     8,     9,     5,    11,    -1,    -1,     9,    -1,    11,
      17,    -1,    19,    -1,    -1,    17,    -1,    19,     3,     4,
       5,     6,     7,     8,    -1,    -1,    -1,    12
};

/* YYSTOS[STATE-NUM] -- The (internal number of the) accessing
   symbol of state STATE-NUM.  */
static const unsigned char yystos[] =
{
       0,     5,     9,    10,    11,    17,    19,    24,    28,    33,
      34,    37,    39,    44,    33,     3,     4,     5,     6,     7,
       8,    25,    26,    27,    28,    32,    33,    18,    25,    38,
      20,    25,    43,    45,     0,     3,     5,    12,    14,    22,
      32,    35,    36,    40,    41,    42,    26,    32,    32,     5,
      32,     5,    26,    32,    18,    21,    15,    20,    21,    12,
      30,    27,    25,    15,    13,    29,    30,    29,    30,    13,
      30,    31,    31,    25,    27,    43,    36,    42,    30,    27,
      35,    35,    41,    31,    29,    29,    15,    27
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

  case 19:
#line 121 "gram.y"
    { 
               syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
               yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 20:
#line 126 "gram.y"
    { 
               if ( ((SyckParser *)parser)->implicit_typing == 1 )
               {
                  try_tag_implicit( yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
               }
               yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 21:
#line 134 "gram.y"
    { 
               yyval.nodeData = syck_hdlr_add_anchor( (SyckParser *)parser, yyvsp[-1].name, yyvsp[0].nodeData );
            }
    break;

  case 22:
#line 138 "gram.y"
    {
               /*
                * _Aliases_: The anchor symbol table is scanned for the anchor name.
                * The anchor's ID in the language's symbol table is returned.
                */
               yyval.nodeData = syck_hdlr_add_alias( (SyckParser *)parser, yyvsp[0].name );
            }
    break;

  case 23:
#line 146 "gram.y"
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

  case 25:
#line 166 "gram.y"
    { 
                syck_add_transfer( yyvsp[-1].name, yyvsp[0].nodeData, ((SyckParser *)parser)->taguri_expansion );
                yyval.nodeData = yyvsp[0].nodeData;
            }
    break;

  case 31:
#line 181 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 32:
#line 185 "gram.y"
    { 
                    syck_add_transfer( yyvsp[-3].name, yyvsp[-1].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 33:
#line 192 "gram.y"
    { 
                    yyval.nodeId = syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData );
                }
    break;

  case 34:
#line 198 "gram.y"
    {
                    yyval.nodeData = syck_new_seq( yyvsp[0].nodeId );
                }
    break;

  case 35:
#line 202 "gram.y"
    { 
                    syck_seq_add( yyvsp[-2].nodeData, yyvsp[0].nodeId );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;

  case 36:
#line 207 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
				}
    break;

  case 37:
#line 216 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 38:
#line 220 "gram.y"
    { 
                    yyval.nodeData = syck_alloc_seq();
                }
    break;

  case 39:
#line 226 "gram.y"
    {
                    yyval.nodeData = syck_new_seq( syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 40:
#line 230 "gram.y"
    { 
                    syck_seq_add( yyvsp[-2].nodeData, syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;

  case 41:
#line 240 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-1].nodeData );
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 42:
#line 245 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-1].nodeData );
                    syck_add_transfer( yyvsp[-3].name, yyvsp[-1].nodeData, ((SyckParser *)parser)->taguri_expansion );
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 43:
#line 253 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-2].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 45:
#line 269 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-3].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 47:
#line 278 "gram.y"
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

  case 48:
#line 290 "gram.y"
    { 
                    apply_seq_in_map( (SyckParser *)parser, yyvsp[-2].nodeData );
                    syck_map_update( yyvsp[-2].nodeData, yyvsp[0].nodeData );
                    syck_free_node( yyvsp[0].nodeData );
                    yyval.nodeData = yyvsp[-2].nodeData;
                }
    break;

  case 49:
#line 297 "gram.y"
    { 
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 50:
#line 306 "gram.y"
    {
                    yyval.nodeData = syck_new_map( 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[-2].nodeData ), 
                        syck_hdlr_add_node( (SyckParser *)parser, yyvsp[0].nodeData ) );
                }
    break;

  case 51:
#line 314 "gram.y"
    {
                    yyval.nodeData = yyvsp[-1].nodeData;
                }
    break;

  case 52:
#line 318 "gram.y"
    {
                    yyval.nodeData = syck_alloc_map();
                }
    break;

  case 54:
#line 325 "gram.y"
    {
                    syck_map_update( yyvsp[-2].nodeData, yyvsp[0].nodeData );
                    syck_free_node( yyvsp[0].nodeData );
                    yyval.nodeData = yyvsp[-2].nodeData;
				}
    break;


    }

/* Line 1016 of /usr/local/share/bison/yacc.c.  */
#line 1349 "y.tab.c"

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


#line 332 "gram.y"


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


