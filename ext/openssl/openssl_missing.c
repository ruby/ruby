/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include RUBY_EXTCONF_H

#include <string.h> /* memcpy() */
#if !defined(OPENSSL_NO_ENGINE)
# include <openssl/engine.h>
#endif
#include <openssl/x509_vfy.h>

#include "openssl_missing.h"

/* added in 1.0.2 */
#if !defined(OPENSSL_NO_EC)
#if !defined(HAVE_EC_CURVE_NIST2NID)
static struct {
    const char *name;
    int nid;
} nist_curves[] = {
    {"B-163", NID_sect163r2},
    {"B-233", NID_sect233r1},
    {"B-283", NID_sect283r1},
    {"B-409", NID_sect409r1},
    {"B-571", NID_sect571r1},
    {"K-163", NID_sect163k1},
    {"K-233", NID_sect233k1},
    {"K-283", NID_sect283k1},
    {"K-409", NID_sect409k1},
    {"K-571", NID_sect571k1},
    {"P-192", NID_X9_62_prime192v1},
    {"P-224", NID_secp224r1},
    {"P-256", NID_X9_62_prime256v1},
    {"P-384", NID_secp384r1},
    {"P-521", NID_secp521r1}
};

int
ossl_EC_curve_nist2nid(const char *name)
{
    size_t i;
    for (i = 0; i < (sizeof(nist_curves) / sizeof(nist_curves[0])); i++) {
	if (!strcmp(nist_curves[i].name, name))
	    return nist_curves[i].nid;
    }
    return NID_undef;
}
#endif
#endif

/*** added in 1.1.0 ***/
#if !defined(HAVE_X509_CRL_GET0_SIGNATURE)
void
ossl_X509_CRL_get0_signature(const X509_CRL *crl, const ASN1_BIT_STRING **psig,
			     const X509_ALGOR **palg)
{
    if (psig != NULL)
	*psig = crl->signature;
    if (palg != NULL)
	*palg = crl->sig_alg;
}
#endif

#if !defined(HAVE_X509_REQ_GET0_SIGNATURE)
void
ossl_X509_REQ_get0_signature(const X509_REQ *req, const ASN1_BIT_STRING **psig,
			     const X509_ALGOR **palg)
{
    if (psig != NULL)
	*psig = req->signature;
    if (palg != NULL)
	*palg = req->sig_alg;
}
#endif
