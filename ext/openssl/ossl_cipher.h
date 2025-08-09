/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'COPYING'.)
 */
#if !defined(_OSSL_CIPHER_H_)
#define _OSSL_CIPHER_H_

/*
 * Gets EVP_CIPHER from a String or an OpenSSL::Digest instance (discouraged,
 * but still supported for compatibility). A holder object is created if the
 * EVP_CIPHER is a "fetched" algorithm.
 */
const EVP_CIPHER *ossl_evp_cipher_fetch(VALUE obj, volatile VALUE *holder);
/*
 * This is meant for OpenSSL::Engine#cipher. EVP_CIPHER must not be a fetched
 * one.
 */
VALUE ossl_cipher_new(const EVP_CIPHER *);
void Init_ossl_cipher(void);

#endif /* _OSSL_CIPHER_H_ */
