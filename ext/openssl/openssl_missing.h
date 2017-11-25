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

#include "ruby/config.h"

/* added in 1.0.2 */
#if !defined(OPENSSL_NO_EC)
#if !defined(HAVE_EC_CURVE_NIST2NID)
int ossl_EC_curve_nist2nid(const char *);
#  define EC_curve_nist2nid ossl_EC_curve_nist2nid
#endif
#endif

#if !defined(HAVE_X509_REVOKED_DUP)
# define X509_REVOKED_dup(rev) (X509_REVOKED *)ASN1_dup((i2d_of_void *)i2d_X509_REVOKED, \
	(d2i_of_void *)d2i_X509_REVOKED, (char *)(rev))
#endif

#if !defined(HAVE_X509_STORE_CTX_GET0_STORE)
#  define X509_STORE_CTX_get0_store(x) ((x)->ctx)
#endif

#if !defined(HAVE_SSL_IS_SERVER)
#  define SSL_is_server(s) ((s)->server)
#endif

/* added in 1.1.0 */
#if !defined(HAVE_BN_GENCB_NEW)
#  define BN_GENCB_new() ((BN_GENCB *)OPENSSL_malloc(sizeof(BN_GENCB)))
#endif

#if !defined(HAVE_BN_GENCB_FREE)
#  define BN_GENCB_free(cb) OPENSSL_free(cb)
#endif

#if !defined(HAVE_BN_GENCB_GET_ARG)
#  define BN_GENCB_get_arg(cb) (cb)->arg
#endif

#if !defined(HAVE_EVP_MD_CTX_NEW)
#  define EVP_MD_CTX_new EVP_MD_CTX_create
#endif

#if !defined(HAVE_EVP_MD_CTX_FREE)
#  define EVP_MD_CTX_free EVP_MD_CTX_destroy
#endif

#if !defined(HAVE_HMAC_CTX_NEW)
HMAC_CTX *ossl_HMAC_CTX_new(void);
#  define HMAC_CTX_new ossl_HMAC_CTX_new
#endif

#if !defined(HAVE_HMAC_CTX_FREE)
void ossl_HMAC_CTX_free(HMAC_CTX *);
#  define HMAC_CTX_free ossl_HMAC_CTX_free
#endif

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

#if !defined(HAVE_X509_CRL_GET0_SIGNATURE)
void ossl_X509_CRL_get0_signature(const X509_CRL *, const ASN1_BIT_STRING **, const X509_ALGOR **);
#  define X509_CRL_get0_signature ossl_X509_CRL_get0_signature
#endif

#if !defined(HAVE_X509_REQ_GET0_SIGNATURE)
void ossl_X509_REQ_get0_signature(const X509_REQ *, const ASN1_BIT_STRING **, const X509_ALGOR **);
#  define X509_REQ_get0_signature ossl_X509_REQ_get0_signature
#endif

#if !defined(HAVE_X509_REVOKED_GET0_SERIALNUMBER)
#  define X509_REVOKED_get0_serialNumber(x) ((x)->serialNumber)
#endif

#if !defined(HAVE_X509_REVOKED_GET0_REVOCATIONDATE)
#  define X509_REVOKED_get0_revocationDate(x) ((x)->revocationDate)
#endif

#if !defined(HAVE_X509_GET0_TBS_SIGALG)
#  define X509_get0_tbs_sigalg(x) ((x)->cert_info->signature)
#endif

#if !defined(HAVE_X509_STORE_CTX_GET0_UNTRUSTED)
#  define X509_STORE_CTX_get0_untrusted(x) ((x)->untrusted)
#endif

#if !defined(HAVE_X509_STORE_CTX_GET0_CERT)
#  define X509_STORE_CTX_get0_cert(x) ((x)->cert)
#endif

#if !defined(HAVE_X509_STORE_CTX_GET0_CHAIN)
#  define X509_STORE_CTX_get0_chain(ctx) X509_STORE_CTX_get_chain(ctx)
#endif

#if !defined(HAVE_OCSP_SINGLERESP_GET0_ID)
#  define OCSP_SINGLERESP_get0_id(s) ((s)->certId)
#endif

#if !defined(HAVE_SSL_CTX_GET_CIPHERS)
#  define SSL_CTX_get_ciphers(ctx) ((ctx)->cipher_list)
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

#if !defined(HAVE_OPAQUE_OPENSSL)
#define IMPL_PKEY_GETTER(_type, _name) \
static inline _type *EVP_PKEY_get0_##_type(EVP_PKEY *pkey) { \
	return pkey->pkey._name; }
#define IMPL_KEY_ACCESSOR2(_type, _group, a1, a2, _fail_cond) \
static inline void _type##_get0_##_group(_type *obj, const BIGNUM **a1, const BIGNUM **a2) { \
	if (a1) *a1 = obj->a1; \
	if (a2) *a2 = obj->a2; } \
static inline int _type##_set0_##_group(_type *obj, BIGNUM *a1, BIGNUM *a2) { \
	if (_fail_cond) return 0; \
	BN_clear_free(obj->a1); obj->a1 = a1; \
	BN_clear_free(obj->a2); obj->a2 = a2; \
	return 1; }
#define IMPL_KEY_ACCESSOR3(_type, _group, a1, a2, a3, _fail_cond) \
static inline void _type##_get0_##_group(_type *obj, const BIGNUM **a1, const BIGNUM **a2, const BIGNUM **a3) { \
	if (a1) *a1 = obj->a1; \
	if (a2) *a2 = obj->a2; \
	if (a3) *a3 = obj->a3; } \
static inline int _type##_set0_##_group(_type *obj, BIGNUM *a1, BIGNUM *a2, BIGNUM *a3) { \
	if (_fail_cond) return 0; \
	BN_clear_free(obj->a1); obj->a1 = a1; \
	BN_clear_free(obj->a2); obj->a2 = a2; \
	BN_clear_free(obj->a3); obj->a3 = a3; \
	return 1; }

#if !defined(OPENSSL_NO_RSA)
IMPL_PKEY_GETTER(RSA, rsa)
IMPL_KEY_ACCESSOR3(RSA, key, n, e, d, (n == obj->n || e == obj->e || (obj->d && d == obj->d)))
IMPL_KEY_ACCESSOR2(RSA, factors, p, q, (p == obj->p || q == obj->q))
IMPL_KEY_ACCESSOR3(RSA, crt_params, dmp1, dmq1, iqmp, (dmp1 == obj->dmp1 || dmq1 == obj->dmq1 || iqmp == obj->iqmp))
#endif

#if !defined(OPENSSL_NO_DSA)
IMPL_PKEY_GETTER(DSA, dsa)
IMPL_KEY_ACCESSOR2(DSA, key, pub_key, priv_key, (pub_key == obj->pub_key || (obj->priv_key && priv_key == obj->priv_key)))
IMPL_KEY_ACCESSOR3(DSA, pqg, p, q, g, (p == obj->p || q == obj->q || g == obj->g))
#endif

#if !defined(OPENSSL_NO_DH)
IMPL_PKEY_GETTER(DH, dh)
IMPL_KEY_ACCESSOR2(DH, key, pub_key, priv_key, (pub_key == obj->pub_key || (obj->priv_key && priv_key == obj->priv_key)))
IMPL_KEY_ACCESSOR3(DH, pqg, p, q, g, (p == obj->p || obj->q && q == obj->q || g == obj->g))
static inline ENGINE *DH_get0_engine(DH *dh) { return dh->engine; }
#endif

#if !defined(OPENSSL_NO_EC)
IMPL_PKEY_GETTER(EC_KEY, ec)
#endif

#undef IMPL_PKEY_GETTER
#undef IMPL_KEY_ACCESSOR2
#undef IMPL_KEY_ACCESSOR3
#endif /* HAVE_OPAQUE_OPENSSL */

#if !defined(EVP_CTRL_AEAD_GET_TAG)
#  define EVP_CTRL_AEAD_GET_TAG EVP_CTRL_GCM_GET_TAG
#  define EVP_CTRL_AEAD_SET_TAG EVP_CTRL_GCM_SET_TAG
#  define EVP_CTRL_AEAD_SET_IVLEN EVP_CTRL_GCM_SET_IVLEN
#endif

#if !defined(HAVE_X509_GET0_NOTBEFORE)
#  define X509_get0_notBefore(x) X509_get_notBefore(x)
#  define X509_get0_notAfter(x) X509_get_notAfter(x)
#  define X509_CRL_get0_lastUpdate(x) X509_CRL_get_lastUpdate(x)
#  define X509_CRL_get0_nextUpdate(x) X509_CRL_get_nextUpdate(x)
#  define X509_set1_notBefore(x, t) X509_set_notBefore(x, t)
#  define X509_set1_notAfter(x, t) X509_set_notAfter(x, t)
#  define X509_CRL_set1_lastUpdate(x, t) X509_CRL_set_lastUpdate(x, t)
#  define X509_CRL_set1_nextUpdate(x, t) X509_CRL_set_nextUpdate(x, t)
#endif

#if !defined(HAVE_SSL_SESSION_GET_PROTOCOL_VERSION)
#  define SSL_SESSION_get_protocol_version(s) ((s)->ssl_version)
#endif

#endif /* _OSSL_OPENSSL_MISSING_H_ */
