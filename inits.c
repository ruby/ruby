/************************************************

  inits.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:38 $
  created at: Tue Dec 28 16:01:58 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

rb_call_inits()
{
    Init_sym();
    Init_var_tables();
    Init_Object();
    Init_GC();
    Init_eval();
    Init_Comparable();
    Init_Enumerable();
    Init_Numeric();
    Init_Bignum();
    Init_Array();
    Init_Dict();
    Init_Struct();
    Init_String();
    Init_Regexp();
    Init_Glob();
    Init_pack();
    Init_Cons();
    Init_Range();
    Init_IO();
    Init_Dir();
    Init_Time();
    Init_Random();
    Init_process();
    Init_Etc();
    Init_load();
    Init_Block();
    Init_Math();
#ifdef USE_DBM
    Init_DBM();
#endif
#ifdef HAVE_SOCKET
    Init_Socket();
#endif
    /* new Inits comes between here.. */

    /* .. and here. */
    Init_version();
}
