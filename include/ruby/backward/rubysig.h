#ifndef RUBYSIG_H                                    /*-*-C++-*-vi:se ft=cpp:*/
#define RUBYSIG_H
/**
 * @file
 * @author     $Author$
 * @date       Wed Aug 16 01:15:38 JST 1995
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#if   defined __GNUC__
#warning rubysig.h is obsolete
#elif defined _MSC_VER
#pragma message("warning: rubysig.h is obsolete")
#endif

#include "ruby/ruby.h"

#define RUBY_CRITICAL(statements) do {statements;} while (0)
#define DEFER_INTS (0)
#define ENABLE_INTS (1)
#define ALLOW_INTS do {CHECK_INTS;} while (0)
#define CHECK_INTS rb_thread_check_ints()

#endif /* RUBYSIG_H */
