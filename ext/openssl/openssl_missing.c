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
#if !defined(OPENSSL_NO_HMAC)
# include <openssl/hmac.h>
#endif
#include <openssl/x509_vfy.h>

#include "openssl_missing.h"

/* added in 1.0.0 */
#if !defined(HAVE_EVP_CIPHER_CTX_COPY)
/*
 * this function does not exist in OpenSSL yet... or ever?.
 * a future version may break this function.
 * tested on 0.9.7d.
 */
int
EVP_CIPHER_CTX_copy(EVP_CIPHER_CTX *out, const EVP_CIPHER_CTX *in)
{
    memcpy(out, in, sizeof(EVP_CIPHER_CTX));

#if !defined(OPENSSL_NO_ENGINE)
    if (in->engine) ENGINE_add(out->engine);
    if (in->cipher_data) {
	out->cipher_data = OPENSSL_malloc(in->cipher->ctx_size);
	memcpy(out->cipher_data, in->cipher_data, in->cipher->ctx_size);
    }
#endif

    return 1;
}
#endif

#if !defined(OPENSSL_NO_HMAC)
#if !defined(HAVE_HMAC_CTX_COPY)
void
HMAC_CTX_copy(HMAC_CTX *out, HMAC_CTX *in)
{
    if (!out || !in) return;
    memcpy(out, in, sizeof(HMAC_CTX));

    EVP_MD_CTX_copy(&out->md_ctx, &in->md_ctx);
    EVP_MD_CTX_copy(&out->i_ctx, &in->i_ctx);
    EVP_MD_CTX_copy(&out->o_ctx, &in->o_ctx);
}
#endif /* HAVE_HMAC_CTX_COPY */
#endif /* NO_HMAC */
