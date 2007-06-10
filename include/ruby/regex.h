/**********************************************************************

  regex.h -

  $Author$
  $Date$

  Copyright (C) 1993-2005 Yukihiro Matsumoto

**********************************************************************/

#ifndef ONIGURUMA_REGEX_H
#define ONIGURUMA_REGEX_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#ifdef RUBY
#include "ruby/oniguruma.h"
#else
#include "oniguruma.h"
#endif

#ifndef ONIG_RUBY_M17N

ONIG_EXTERN OnigEncoding    OnigEncDefaultCharEncoding;

#undef ismbchar
#define ismbchar(c) (mbclen((c)) != 1)
#define mbclen(c)  \
  ONIGENC_MBC_ENC_LEN(OnigEncDefaultCharEncoding, (UChar* )(&c))

#endif /* ifndef ONIG_RUBY_M17N */

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* ONIGURUMA_REGEX_H */
