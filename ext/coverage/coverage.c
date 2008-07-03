/************************************************

  coverage.c -

  $Author: $

  Copyright (c) 2008 Yusuke Endoh

************************************************/

#include "ruby.h"

extern void rb_enable_coverages(void);

/* Coverage provides coverage measurement feature for Ruby.
 *
 * = Usage
 *
 * (1) require "coverage.so"
 * (2) require or load Ruby source file
 * (3) Coverage.result will return a hash that contains filename as key and
 *     coverage array as value.
 *
 * = Example
 *
 *   [foo.rb]
 *   s = 0
 *   10.times do |x|
 *     s += x
 *   end
 *
 *   if s == 45
 *     p :ok
 *   else
 *     p :ng
 *   end
 *   [EOF]
 *
 *   require "coverage.so"
 *   require "foo.rb"
 *   p COVERAGE__  #=> {"foo.rb"=>[1, 1, 10, nil, nil, 1, 1, nil, 0, nil]}
 */
void
Init_coverage(void)
{
    rb_enable_coverages();
}
