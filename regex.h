/**********************************************************************

  regex.h -

  $Author$
  $Date$

  Copyright (C) 1993-2005 Yukihiro Matsumoto

**********************************************************************/

#ifndef REGEX_H
#define REGEX_H

#include "oniguruma.h"

#ifndef ONIG_RUBY_M17N

ONIG_EXTERN OnigEncoding    OnigEncDefaultCharEncoding;

#undef ismbchar
#define ismbchar(c) (mbclen((c)) != 1)
#define mbclen(c)  \
  ONIGENC_MBC_ENC_LEN(OnigEncDefaultCharEncoding, (UChar* )(&c))

#endif /* ifndef ONIG_RUBY_M17N */

#endif /* !REGEX_H */
