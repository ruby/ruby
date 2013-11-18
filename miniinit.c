/**********************************************************************

  miniinit.c -

  $Author$
  created at: Thu Jul 11 22:09:57 JST 2013

  Copyright (C) 2013 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"

/* loadpath.c */
const char ruby_exec_prefix[] = "";
const char ruby_initial_load_paths[] = "";

/* localeinit.c */
VALUE
rb_locale_charmap(VALUE klass)
{
    return rb_usascii_str_new2("ASCII-8BIT");
}

int
Init_enc_set_filesystem_encoding(void)
{
    return rb_enc_to_index(rb_default_external_encoding());
}
