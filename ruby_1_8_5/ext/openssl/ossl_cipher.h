/*
 * $Id: ossl_cipher.h,v 1.2 2003/09/05 09:08:40 gotoyuzo Exp $
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_CIPHER_H_)
#define _OSSL_CIPHER_H_

extern VALUE mCipher;
extern VALUE cCipher;
extern VALUE eCipherError;

const EVP_CIPHER *GetCipherPtr(VALUE);
VALUE ossl_cipher_new(const EVP_CIPHER *);
void Init_ossl_cipher(void);

#endif /* _OSSL_CIPHER_H_ */

