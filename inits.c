/**********************************************************************

  inits.c -

  $Author$
  created at: Tue Dec 28 16:01:58 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"

void Init_Array(void);
void Init_Bignum(void);
void Init_Binding(void);
void Init_Comparable(void);
void Init_Complex(void);
void Init_transcode(void);
void Init_Dir(void);
void Init_Enumerable(void);
void Init_Enumerator(void);
void Init_Exception(void);
void Init_syserr(void);
void Init_eval(void);
void Init_load(void);
void Init_Proc(void);
void Init_File(void);
void Init_GC(void);
void Init_Hash(void);
void Init_IO(void);
void Init_Math(void);
void Init_marshal(void);
void Init_Numeric(void);
void Init_Object(void);
void Init_pack(void);
void Init_sym(void);
void Init_process(void);
void Init_RandomSeed(void);
void Init_Random(void);
void Init_Range(void);
void Init_Rational(void);
void Init_Regexp(void);
void Init_signal(void);
void Init_String(void);
void Init_Struct(void);
void Init_Time(void);
void Init_var_tables(void);
void Init_version(void);
void Init_ISeq(void);
void Init_VM(void);
void Init_Thread(void);
void Init_Cont(void);
void Init_top_self(void);
void Init_Encoding(void);

void
rb_call_inits()
{
    Init_RandomSeed();
    Init_sym();
    Init_var_tables();
    Init_Object();
    Init_top_self();
    Init_Encoding();
    Init_Comparable();
    Init_Enumerable();
    Init_String();
    Init_Exception();
    Init_eval();
    Init_jump();
    Init_Numeric();
    Init_Bignum();
    Init_syserr();
    Init_Array();
    Init_Hash();
    Init_Struct();
    Init_Regexp();
    Init_pack();
    Init_transcode();
    Init_marshal();
    Init_Range();
    Init_IO();
    Init_Dir();
    Init_Time();
    Init_Random();
    Init_signal();
    Init_process();
    Init_load();
    Init_Proc();
    Init_Binding();
    Init_Math();
    Init_GC();
    Init_Enumerator();
    Init_VM();
    Init_ISeq();
    Init_Thread();
    Init_Cont();
    Init_Rational();
    Init_Complex();
    Init_version();
}
