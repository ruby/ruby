/************************************************

  fcntl.c -

  $Author$
  created at: Mon Apr  7 18:53:05 JST 1997

  Copyright (C) 1997-2001 Yukihiro Matsumoto

************************************************/

/************************************************
= NAME

fcntl - load the C fcntl.h defines

= DESCRIPTION

This module is just a translation of the C <fcntl.h> file.

= NOTE

Only #define symbols get translated; you must still correctly
pack up your own arguments to pass as args for locking functions, etc.

************************************************/

#include "ruby.h"
#include <fcntl.h>

/* Fcntl loads the constants defined in the system's <fcntl.h> C header
 * file, and used with both the fcntl(2) and open(2) POSIX system calls.
 *
 * To perform a fcntl(2) operation, use IO::fcntl.
 *
 * To perform an open(2) operation, use IO::sysopen.
 *
 * The set of operations and constants available depends upon specific
 * operating system.  Some values listed below may not be supported on your
 * system.
 *
 * See your fcntl(2) man page for complete details.
 *
 * Open /tmp/tempfile as a write-only file that is created if it doesn't
 * exist:
 *
 *   require 'fcntl'
 *
 *   fd = IO.sysopen('/tmp/tempfile',
 *                   Fcntl::O_WRONLY | Fcntl::O_EXCL | Fcntl::O_CREAT)
 *   f = IO.open(fd)
 *   f.syswrite("TEMP DATA")
 *   f.close
 *
 * Get the flags on file +s+:
 *
 *   m = s.fcntl(Fcntl::F_GETFL, 0)
 *
 * Set the non-blocking flag on +f+ in addition to the existing flags in +m+.
 *
 *   f.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK|m)
 *
 */

#define FCNTL_VERSION "1.1.0"

void
Init_fcntl(void)
{
    VALUE mFcntl = rb_define_module("Fcntl");

    rb_define_const(mFcntl, "VERSION", rb_str_new_cstr(FCNTL_VERSION));

#ifdef F_DUPFD
    /*
     * Duplicate a file descriptor to the minimum unused file descriptor
     * greater than or equal to the argument.
     *
     * The close-on-exec flag of the duplicated file descriptor is set.
     * (Ruby uses F_DUPFD_CLOEXEC internally if available to avoid race
     * condition.  F_SETFD is used if F_DUPFD_CLOEXEC is not available.)
     */
    rb_define_const(mFcntl, "F_DUPFD", INT2NUM(F_DUPFD));
#endif
#ifdef F_GETFD
    /*
     * Read the close-on-exec flag of a file descriptor.
     */
    rb_define_const(mFcntl, "F_GETFD", INT2NUM(F_GETFD));
#endif
#ifdef F_GETLK
    /*
     * Determine whether a given region of a file is locked.  This uses one of
     * the F_*LK flags.
     */
    rb_define_const(mFcntl, "F_GETLK", INT2NUM(F_GETLK));
#endif
#ifdef F_SETFD
    /*
     * Set the close-on-exec flag of a file descriptor.
     */
    rb_define_const(mFcntl, "F_SETFD", INT2NUM(F_SETFD));
#endif
#ifdef F_GETFL
    /*
     * Get the file descriptor flags.  This will be one or more of the O_*
     * flags.
     */
    rb_define_const(mFcntl, "F_GETFL", INT2NUM(F_GETFL));
#endif
#ifdef F_SETFL
    /*
     * Set the file descriptor flags.  This will be one or more of the O_*
     * flags.
     */
    rb_define_const(mFcntl, "F_SETFL", INT2NUM(F_SETFL));
#endif
#ifdef F_SETLK
    /*
     * Acquire a lock on a region of a file.  This uses one of the F_*LCK
     * flags.
     */
    rb_define_const(mFcntl, "F_SETLK", INT2NUM(F_SETLK));
#endif
#ifdef F_SETLKW
    /*
     * Acquire a lock on a region of a file, waiting if necessary.  This uses
     * one of the F_*LCK flags
     */
    rb_define_const(mFcntl, "F_SETLKW", INT2NUM(F_SETLKW));
#endif
#ifdef FD_CLOEXEC
    /*
     * the value of the close-on-exec flag.
     */
    rb_define_const(mFcntl, "FD_CLOEXEC", INT2NUM(FD_CLOEXEC));
#endif
#ifdef F_RDLCK
    /*
     * Read lock for a region of a file
     */
    rb_define_const(mFcntl, "F_RDLCK", INT2NUM(F_RDLCK));
#endif
#ifdef F_UNLCK
    /*
     * Remove lock for a region of a file
     */
    rb_define_const(mFcntl, "F_UNLCK", INT2NUM(F_UNLCK));
#endif
#ifdef F_WRLCK
    /*
     * Write lock for a region of a file
     */
    rb_define_const(mFcntl, "F_WRLCK", INT2NUM(F_WRLCK));
#endif
#ifdef F_SETPIPE_SZ
    /*
     * Change the capacity of the pipe referred to by fd to be at least arg bytes.
     */
    rb_define_const(mFcntl, "F_SETPIPE_SZ", INT2NUM(F_SETPIPE_SZ));
#endif
#ifdef F_GETPIPE_SZ
    /*
     * Return (as the function result) the capacity of the pipe referred to by fd.
     */
    rb_define_const(mFcntl, "F_GETPIPE_SZ", INT2NUM(F_GETPIPE_SZ));
#endif
#ifdef O_CREAT
    /*
     * Create the file if it doesn't exist
     */
    rb_define_const(mFcntl, "O_CREAT", INT2NUM(O_CREAT));
#endif
#ifdef O_EXCL
    /*
     * Used with O_CREAT, fail if the file exists
     */
    rb_define_const(mFcntl, "O_EXCL", INT2NUM(O_EXCL));
#endif
#ifdef O_NOCTTY
    /*
     * Open TTY without it becoming the controlling TTY
     */
    rb_define_const(mFcntl, "O_NOCTTY", INT2NUM(O_NOCTTY));
#endif
#ifdef O_TRUNC
    /*
     * Truncate the file on open
     */
    rb_define_const(mFcntl, "O_TRUNC", INT2NUM(O_TRUNC));
#endif
#ifdef O_APPEND
    /*
     * Open the file in append mode
     */
    rb_define_const(mFcntl, "O_APPEND", INT2NUM(O_APPEND));
#endif
#ifdef O_NONBLOCK
    /*
     * Open the file in non-blocking mode
     */
    rb_define_const(mFcntl, "O_NONBLOCK", INT2NUM(O_NONBLOCK));
#endif
#ifdef O_NDELAY
    /*
     * Open the file in non-blocking mode
     */
    rb_define_const(mFcntl, "O_NDELAY", INT2NUM(O_NDELAY));
#endif
#ifdef O_RDONLY
    /*
     * Open the file in read-only mode
     */
    rb_define_const(mFcntl, "O_RDONLY", INT2NUM(O_RDONLY));
#endif
#ifdef O_RDWR
    /*
     * Open the file in read-write mode
     */
    rb_define_const(mFcntl, "O_RDWR", INT2NUM(O_RDWR));
#endif
#ifdef O_WRONLY
    /*
     * Open the file in write-only mode.
     */
    rb_define_const(mFcntl, "O_WRONLY", INT2NUM(O_WRONLY));
#endif
#ifndef O_ACCMODE
    int O_ACCMODE = (O_RDONLY | O_WRONLY | O_RDWR);
#endif
    /*
     * Mask to extract the read/write flags
     */
    rb_define_const(mFcntl, "O_ACCMODE", INT2FIX(O_ACCMODE));
#ifdef F_DUP2FD
    /*
     * It is a FreeBSD specific constant and equivalent
     * to dup2 call.
     */
    rb_define_const(mFcntl, "F_DUP2FD", INT2NUM(F_DUP2FD));
#endif
#ifdef F_DUP2FD_CLOEXEC
    /*
     * It is a FreeBSD specific constant and acts
     * similarly as F_DUP2FD but set the FD_CLOEXEC
     * flag in addition.
     */
    rb_define_const(mFcntl, "F_DUP2FD_CLOEXEC", INT2NUM(F_DUP2FD_CLOEXEC));
#endif
}
