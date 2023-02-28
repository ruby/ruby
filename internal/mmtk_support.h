#ifndef INTERNAL_MMTK_SUPPORT_H                                 /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_MMTK_SUPPORT_H

#include "ruby/internal/config.h"

#if !USE_MMTK
#error This file should only be included when MMTk is enabled. Guard the #include with #if USE_MMTK
#endif

#include "ruby/ruby.h"

VALUE rb_mmtk_plan_name(VALUE _);
VALUE rb_mmtk_enabled(VALUE _);
VALUE rb_mmtk_harness_begin(VALUE _);
VALUE rb_mmtk_harness_end(VALUE _);

#endif // INTERNAL_MMTK_SUPPORT_H
