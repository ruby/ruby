/**********************************************************************

  enc/encdb.c -

  $Author$
  created at: Mon Apr  7 15:51:31 2008

  Copyright (C) 2008 Yukihiro Matsumoto

**********************************************************************/

#include "internal.h"

#define ENC_REPLICATE(name, orig) rb_encdb_replicate((name), (orig))
#define ENC_ALIAS(name, orig) rb_encdb_alias((name), (orig))
#define ENC_DUMMY(name) rb_encdb_dummy(name)
#define ENC_DEFINE(name) rb_encdb_declare(name)
#define ENC_SET_BASE(name, orig) rb_enc_set_base((name), (orig))
#define ENC_SET_DUMMY(name, orig) rb_enc_set_dummy(name)
#define ENC_DUMMY_UNICODE(name) rb_encdb_set_unicode(rb_enc_set_dummy(ENC_REPLICATE((name), name "BE")))

void
Init_encdb(void)
{
#include "encdb.h"
}
