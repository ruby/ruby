/**********************************************************************

  id.c - 

  $Author$
  created at: Thu Jul 12 04:37:51 2007

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"

#define extern
#include "id.h"
#undef extern

void
Init_id(void)
{
#undef rb_intern

    /* Symbols */
    symIFUNC = ID2SYM(rb_intern("<IFUNC>"));
    symCFUNC = ID2SYM(rb_intern("<CFUNC>"));

    /* IDs */
    idPLUS = rb_intern("+");
    idMINUS = rb_intern("-");
    idMULT = rb_intern("*");
    idDIV = rb_intern("/");
    idMOD = rb_intern("%");
    idLT = rb_intern("<");
    idLTLT = rb_intern("<<");
    idLE = rb_intern("<=");
    idGT = rb_intern(">");
    idGE = rb_intern(">=");
    idEq = rb_intern("==");
    idEqq = rb_intern("===");
    idBackquote = rb_intern("`");
    idEqTilde = rb_intern("=~");
    idNot = rb_intern("!");
    idNeq = rb_intern("!=");

    idAREF = rb_intern("[]");
    idASET = rb_intern("[]=");

    idEach = rb_intern("each");
    idTimes = rb_intern("times");
    idLength = rb_intern("length");
    idLambda = rb_intern("lambda");
    idIntern = rb_intern("intern");
    idGets = rb_intern("gets");
    idSucc = rb_intern("succ");
    idEnd = rb_intern("end");
    idRangeEachLT = rb_intern("Range#each#LT");
    idRangeEachLE = rb_intern("Range#each#LE");
    idArrayEach = rb_intern("Array#each");
    idMethodMissing = rb_intern("method_missing");

    idThrowState = rb_intern("#__ThrowState__");

    idBitblt = rb_intern("bitblt");
    idAnswer = rb_intern("the_answer_to_life_the_universe_and_everything");

    idSend = rb_intern("send");
    id__send__ = rb_intern("__send__");

    idRespond_to = rb_intern("respond_to?");
    idInitialize = rb_intern("initialize");

    id_core_set_method_alias = rb_intern("core_set_method_alias");
    id_core_set_variable_alias = rb_intern("core_set_variable_alias");
    id_core_undef_method = rb_intern("core_undef_method");
    id_core_define_method = rb_intern("core_define_method");
    id_core_define_singleton_method = rb_intern("core_define_singleton_method");
}
