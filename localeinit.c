/**********************************************************************

  localeinit.c -

  $Author$
  created at: Thu Jul 11 22:09:57 JST 2013

  Copyright (C) 2013 Yukihiro Matsumoto

**********************************************************************/

#include "internal.h"
#ifdef __CYGWIN__
#include <windows.h>
#endif
#ifdef HAVE_LANGINFO_H
#include <langinfo.h>
#endif

#if defined _WIN32 || defined __CYGWIN__
#define SIZEOF_CP_NAME ((sizeof(UINT) * 8 / 3) + 4)
#define CP_FORMAT(buf, codepage) snprintf(buf, sizeof(buf), "CP%u", (codepage))
#endif

VALUE
rb_locale_charmap(VALUE klass)
{
#if defined NO_LOCALE_CHARMAP
# error NO_LOCALE_CHARMAP defined
#elif defined _WIN32 || defined __CYGWIN__
    const char *codeset = 0;
    char cp[SIZEOF_CP_NAME];
# ifdef __CYGWIN__
    const char *nl_langinfo_codeset(void);
    codeset = nl_langinfo_codeset();
# endif
    if (!codeset) {
	UINT codepage = GetConsoleCP();
	if (!codepage) codepage = GetACP();
	CP_FORMAT(cp, codepage);
	codeset = cp;
    }
    return rb_usascii_str_new2(codeset);
#elif defined HAVE_LANGINFO_H
    char *codeset;
    codeset = nl_langinfo(CODESET);
    return rb_usascii_str_new2(codeset);
#else
    return Qnil;
#endif
}

int
Init_enc_set_filesystem_encoding(void)
{
    int idx;
#if defined NO_LOCALE_CHARMAP
# error NO_LOCALE_CHARMAP defined
#elif defined _WIN32 || defined __CYGWIN__
    char cp[SIZEOF_CP_NAME];
    CP_FORMAT(cp, AreFileApisANSI() ? GetACP() : GetOEMCP());
    idx = rb_enc_find_index(cp);
    if (idx < 0) idx = ENCINDEX_ASCII;
#else
    idx = rb_enc_to_index(rb_default_external_encoding());
#endif
    return idx;
}
