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

#ifndef BISON_Y_TAB_H
# define BISON_Y_TAB_H

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




#ifndef YYSTYPE
#line 33 "gram.y"
typedef union {
    SYMID nodeId;
    SyckNode *nodeData;
    char *name;
} yystype;
/* Line 1281 of /usr/local/share/bison/yacc.c.  */
#line 74 "y.tab.h"
# define YYSTYPE yystype
#endif




#endif /* not BISON_Y_TAB_H */

