#ifndef RUBY_BACKWARD_RUBYIO_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_BACKWARD_RUBYIO_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#if   defined __GNUC__
#warning use "ruby/io.h" instead of "rubyio.h"
#elif defined _MSC_VER
#pragma message("warning: use \"ruby/io.h\" instead of \"rubyio.h\"")
#endif
#include "ruby/io.h"

#endif /* RUBY_BACKWARD_RUBYIO_H */
