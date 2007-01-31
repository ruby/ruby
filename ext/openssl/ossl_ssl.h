/*
 * $Id: ossl_ssl.h,v 1.1 2003/07/23 16:11:29 gotoyuzo Exp $
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_SSL_H_)
#define _OSSL_SSL_H_

extern VALUE mSSL;
extern VALUE eSSLError;
extern VALUE cSSLSocket;
extern VALUE cSSLContext;

void Init_ossl_ssl(void);

#endif /* _OSSL_SSL_H_ */
