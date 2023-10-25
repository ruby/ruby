/**********************************************************************

  enc/trans/transdb.c -

  $Author$
  created at: Mon Apr  7 15:51:31 2008

  Copyright (C) 2008 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"

void rb_declare_transcoder(const char *enc1, const char *enc2, const char *lib);

void
Init_transdb(void)
{
#include "transdb.h"
}
