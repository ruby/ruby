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
    /* never used */
    return Qnil;
}

int
rb_locale_charmap_index(void)
{
    return -1;
}

int
Init_enc_set_filesystem_encoding(void)
{
    return rb_enc_to_index(rb_default_external_encoding());
}

void
Init_enc(void)
{
    void rb_encdb_declare(const char *name);
    rb_encdb_declare("ASCII-8BIT");
    rb_encdb_declare("US-ASCII");
    rb_encdb_declare("UTF-8");
}
