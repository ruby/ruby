#ifndef FIDDLE_H
#define FIDDLE_H

#include <ruby.h>
#include <errno.h>

#if defined(HAVE_WINDOWS_H)
#include <windows.h>
#endif

#ifdef HAVE_SYS_MMAN_H
#include <sys/mman.h>
#endif

#ifdef USE_HEADER_HACKS
#include <ffi/ffi.h>
#else
#include <ffi.h>
#endif

#include <closure.h>
#include <conversions.h>
#include <function.h>

/* FIXME
 * These constants need to match up with DL. We need to refactor this to use
 * the DL header files or vice versa.
 */

#define TYPE_VOID  0
#define TYPE_VOIDP 1
#define TYPE_CHAR  2
#define TYPE_SHORT 3
#define TYPE_INT   4
#define TYPE_LONG  5
#if HAVE_LONG_LONG
#define TYPE_LONG_LONG 6
#endif
#define TYPE_FLOAT 7
#define TYPE_DOUBLE 8

extern VALUE mFiddle;

#endif
/* vim: set noet sws=4 sw=4: */
