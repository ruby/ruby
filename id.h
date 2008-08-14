/**********************************************************************

  id.h - 

  $Author: ko1 $
  created at: Thu Jul 12 04:38:07 2007

  Copyright (C) 2007 Koichi Sasada

**********************************************************************/

#ifndef RUBY_ID_H
#define RUBY_ID_H

#define ID_SCOPE_SHIFT 3
#define ID_SCOPE_MASK 0x07
#define ID_LOCAL      0x00
#define ID_INSTANCE   0x01
#define ID_GLOBAL     0x03
#define ID_ATTRSET    0x04
#define ID_CONST      0x05
#define ID_CLASS      0x06
#define ID_JUNK       0x07
#define ID_INTERNAL   ID_JUNK

#include "parse.h"

#define symIFUNC ID2SYM(idIFUNC)
#define symCFUNC ID2SYM(idCFUNC)

enum ruby_method_ids {
    idPLUS = '+',
    idMINUS = '-',
    idMULT = '*',
    idDIV = '/',
    idMOD = '%',
    idLT = '<',
    idLTLT = tLSHFT,
    idLE = tLEQ,
    idGT = '>',
    idGE = tGEQ,
    idEq = tEQ,
    idEqq = tEQQ,
    idNeq = tNEQ,
    idNot = '!',
    idBackquote = '`',
    idEqTilde = tMATCH,
    idAREF = tAREF,
    idASET = tASET,
    idLAST_TOKEN = tLAST_TOKEN >> ID_SCOPE_SHIFT,
    tIntern,
    tMethodMissing,
    tLength,
    tGets,
    tSucc,
    tEach,
    tLambda,
    tSend,
    t__send__,
    tInitialize,
#if SUPPORT_JOKE
    tBitblt,
    tAnswer,
#endif
    tLAST_ID
};

#define idIntern ((tIntern<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idMethodMissing ((tMethodMissing<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idLength ((tLength<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idGets ((tGets<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idSucc ((tSucc<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idEach ((tEach<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idLambda ((tLambda<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idSend ((tSend<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define id__send__ ((t__send__<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idInitialize ((tInitialize<<ID_SCOPE_SHIFT)|ID_LOCAL)
#if SUPPORT_JOKE
#define idBitblt ((tBitblt<<ID_SCOPE_SHIFT)|ID_LOCAL)
#define idAnswer ((tAnswer<<ID_SCOPE_SHIFT)|ID_LOCAL)
#endif

#endif /* RUBY_ID_H */
