#ifndef INCLUDE_RUBYGC_H
#define INCLUDE_RUBYGC_H
#include "ruby/internal/config.h"
#ifdef _WIN32
# include "ruby/ruby.h"
#endif

RUBY_FUNC_EXPORTED void GC_Init(void);
#endif
