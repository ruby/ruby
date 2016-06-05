/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#if !defined(_OSSL_OPENSSL_MISSING_H_)
#define _OSSL_OPENSSL_MISSING_H_

/* added in 1.0.0 */
#if !defined(HAVE_EVP_CIPHER_CTX_COPY)
int EVP_CIPHER_CTX_copy(EVP_CIPHER_CTX *out, const EVP_CIPHER_CTX *in);
#endif

#if !defined(HAVE_HMAC_CTX_COPY)
void HMAC_CTX_copy(HMAC_CTX *out, HMAC_CTX *in);
#endif

/* added in 1.0.2 */
#if !defined(OPENSSL_NO_EC)
#if !defined(HAVE_EC_CURVE_NIST2NID)
int EC_curve_nist2nid(const char *);
#endif
#endif

#if !defined(HAVE_X509_REVOKED_DUP)
# define X509_REVOKED_dup(rev) (X509_REVOKED *)ASN1_dup((i2d_of_void *)i2d_X509_REVOKED, \
	(d2i_of_void *)d2i_X509_REVOKED, (char *)(rev))
#endif

/* added in 1.1.0 */
#if !defined(HAVE_X509_STORE_GET_EX_DATA)
#  define X509_STORE_get_ex_data(x, idx) \
	CRYPTO_get_ex_data(&(x)->ex_data, (idx))
#endif

#if !defined(HAVE_X509_STORE_SET_EX_DATA)
#  define X509_STORE_set_ex_data(x, idx, data) \
	CRYPTO_set_ex_data(&(x)->ex_data, (idx), (data))
#  define X509_STORE_get_ex_new_index(l, p, newf, dupf, freef) \
	CRYPTO_get_ex_new_index(CRYPTO_EX_INDEX_X509_STORE, (l), (p), \
				(newf), (dupf), (freef))
#endif

#if !defined(HAVE_X509_UP_REF)
#  define X509_up_ref(x) \
	CRYPTO_add(&(x)->references, 1, CRYPTO_LOCK_X509)
#endif

#if !defined(HAVE_X509_CRL_UP_REF)
#  define X509_CRL_up_ref(x) \
	CRYPTO_add(&(x)->references, 1, CRYPTO_LOCK_X509_CRL);
#endif

#if !defined(HAVE_X509_STORE_UP_REF)
#  define X509_STORE_up_ref(x) \
	CRYPTO_add(&(x)->references, 1, CRYPTO_LOCK_X509_STORE);
#endif

#if !defined(HAVE_SSL_SESSION_UP_REF)
#  define SSL_SESSION_up_ref(x) \
	CRYPTO_add(&(x)->references, 1, CRYPTO_LOCK_SSL_SESSION);
#endif

#if !defined(HAVE_EVP_PKEY_UP_REF)
#  define EVP_PKEY_up_ref(x) \
	CRYPTO_add(&(x)->references, 1, CRYPTO_LOCK_EVP_PKEY);
#endif

#endif /* _OSSL_OPENSSL_MISSING_H_ */
