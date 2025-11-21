/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'COPYING'.)
 */
#if !defined(_OSSL_DIGEST_H_)
#define _OSSL_DIGEST_H_

/*
 * Gets EVP_MD from a String or an OpenSSL::Digest instance (discouraged, but
 * still supported for compatibility). A holder object is created if the EVP_MD
 * is a "fetched" algorithm.
 */
const EVP_MD *ossl_evp_md_fetch(VALUE obj, volatile VALUE *holder);
/*
 * This is meant for OpenSSL::Engine#digest. EVP_MD must not be a fetched one.
 */
VALUE ossl_digest_new(const EVP_MD *);
void Init_ossl_digest(void);

#endif /* _OSSL_DIGEST_H_ */
