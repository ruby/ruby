/*
 * $Id: ossl_hmac.h,v 1.1 2003/07/23 16:11:29 gotoyuzo Exp $
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_HMAC_H_)
#define _OSSL_HMAC_H_

extern VALUE cHMAC;
extern VALUE eHMACError;

void Init_ossl_hmac(void);

#endif /* _OSSL_HMAC_H_ */
