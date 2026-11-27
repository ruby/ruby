/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'COPYING'.)
 */
#if !defined(_OSSL_OPENSSL_MISSING_H_)
#define _OSSL_OPENSSL_MISSING_H_

#include "ruby/config.h"

/* added in 3.0.0 */
#ifndef HAVE_EVP_MD_CTX_GET0_MD
#  define EVP_MD_CTX_get0_md(ctx) EVP_MD_CTX_md(ctx)
#endif

/*
 * OpenSSL 1.1.0 added EVP_MD_CTX_pkey_ctx(), and then it was renamed to
 * EVP_MD_CTX_get_pkey_ctx(x) in OpenSSL 3.0.
 */
#ifndef HAVE_EVP_MD_CTX_GET_PKEY_CTX
#  define EVP_MD_CTX_get_pkey_ctx(x) EVP_MD_CTX_pkey_ctx(x)
#endif

#ifndef HAVE_EVP_PKEY_EQ
#  define EVP_PKEY_eq(a, b) EVP_PKEY_cmp(a, b)
#endif

/* added in 4.0.0 */
#ifndef HAVE_ASN1_BIT_STRING_SET1
static inline int
ASN1_BIT_STRING_set1(ASN1_BIT_STRING *bitstr, const uint8_t *data,
                     size_t length, int unused_bits)
{
    if (length > INT_MAX || !ASN1_STRING_set(bitstr, data, (int)length))
        return 0;
    bitstr->flags &= ~(ASN1_STRING_FLAG_BITS_LEFT | 0x07);
    bitstr->flags |= ASN1_STRING_FLAG_BITS_LEFT | unused_bits;
    return 1;
}

static inline int
ASN1_BIT_STRING_get_length(const ASN1_BIT_STRING *bitstr, size_t *length,
                           int *unused_bits)
{
    *length = bitstr->length;
    *unused_bits = bitstr->flags & 0x07;
    return 1;
}
#endif

#endif /* _OSSL_OPENSSL_MISSING_H_ */
