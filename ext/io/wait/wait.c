/* -*- c-file-style: "ruby"; indent-tabs-mode: t -*- */
/**********************************************************************

  io/wait.c -

  $Author$
  created at: Tue Aug 28 09:08:06 JST 2001

  All the files in this distribution are covered under the Ruby's
  license (see the file COPYING).

**********************************************************************/

#include "ruby.h"
#include "ruby/io.h"


/*
 * IO wait methods
 */

void
Init_wait(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    RB_EXT_RACTOR_SAFE(true);
#endif

}
