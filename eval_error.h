#ifndef RUBY_EVAL_ERROR_H
#define RUBY_EVAL_ERROR_H 1
#include "ruby/ruby.h"

void rb_error_write(VALUE errinfo, VALUE emesg, VALUE errat, VALUE str, VALUE highlight, VALUE reverse);

#endif
