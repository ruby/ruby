/************************************************

  fcntl.c -

  $Author$
  created at: Mon Apr  7 18:53:05 JST 1997

  Copyright (C) 1997-1998 Yukihiro Matsumoto

************************************************/

/************************************************
= NAME

fcntl - load the C fcntl.h defines

= SYNOPSIS

    require "fcntl"
    m = s.fcntl(Fcntl::F_GETFL, 0)
    f.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK|m)

= DESCRIPTION

This module is just a translation of the C <fnctl.h> file.

= NOTE

Only #define symbols get translated; you must still correctly
pack up your own arguments to pass as args for locking functions, etc.

************************************************/

#include "ruby.h"
#include <fcntl.h>

void
Init_fcntl()
{
    VALUE mFcntl = rb_define_module("Fcntl");
#ifdef F_DUPFD
    rb_define_const(mFcntl, "F_DUPFD", INT2NUM(F_DUPFD));
#endif
#ifdef F_GETFD
    rb_define_const(mFcntl, "F_GETFD", INT2NUM(F_GETFD));
#endif
#ifdef F_GETLK
    rb_define_const(mFcntl, "F_GETLK", INT2NUM(F_GETLK));
#endif
#ifdef F_SETFD
    rb_define_const(mFcntl, "F_SETFD", INT2NUM(F_SETFD));
#endif
#ifdef F_GETFL
    rb_define_const(mFcntl, "F_GETFL", INT2NUM(F_GETFL));
#endif
#ifdef F_SETFL
    rb_define_const(mFcntl, "F_SETFL", INT2NUM(F_SETFL));
#endif
#ifdef F_SETLK
    rb_define_const(mFcntl, "F_SETLK", INT2NUM(F_SETLK));
#endif
#ifdef F_SETLKW
    rb_define_const(mFcntl, "F_SETLKW", INT2NUM(F_SETLKW));
#endif
#ifdef FD_CLOEXEC
    rb_define_const(mFcntl, "FD_CLOEXEC", INT2NUM(FD_CLOEXEC));
#endif
#ifdef F_RDLCK
    rb_define_const(mFcntl, "F_RDLCK", INT2NUM(F_RDLCK));
#endif
#ifdef F_UNLCK
    rb_define_const(mFcntl, "F_UNLCK", INT2NUM(F_UNLCK));
#endif
#ifdef F_WRLCK
    rb_define_const(mFcntl, "F_WRLCK", INT2NUM(F_WRLCK));
#endif
#ifdef O_CREAT
    rb_define_const(mFcntl, "O_CREAT", INT2NUM(O_CREAT));
#endif
#ifdef O_EXCL
    rb_define_const(mFcntl, "O_EXCL", INT2NUM(O_EXCL));
#endif
#ifdef O_NOCTTY
    rb_define_const(mFcntl, "O_NOCTTY", INT2NUM(O_NOCTTY));
#endif
#ifdef O_TRUNC
    rb_define_const(mFcntl, "O_TRUNC", INT2NUM(O_TRUNC));
#endif
#ifdef O_APPEND
    rb_define_const(mFcntl, "O_APPEND", INT2NUM(O_APPEND));
#endif
#ifdef O_NONBLOCK
    rb_define_const(mFcntl, "O_NONBLOCK", INT2NUM(O_NONBLOCK));
#endif
#ifdef O_NDELAY
    rb_define_const(mFcntl, "O_NDELAY", INT2NUM(O_NDELAY));
#endif
#ifdef O_RDONLY
    rb_define_const(mFcntl, "O_RDONLY", INT2NUM(O_RDONLY));
#endif
#ifdef O_RDWR
    rb_define_const(mFcntl, "O_RDWR", INT2NUM(O_RDWR));
#endif
#ifdef O_WRONLY
    rb_define_const(mFcntl, "O_WRONLY", INT2NUM(O_WRONLY));
#endif
}
