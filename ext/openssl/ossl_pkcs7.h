/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'COPYING'.)
 */
#if !defined(_OSSL_PKCS7_H_)
#define _OSSL_PKCS7_H_

VALUE ossl_pkcs7_new(PKCS7 *p7);
void Init_ossl_pkcs7(void);

#endif /* _OSSL_PKCS7_H_ */
