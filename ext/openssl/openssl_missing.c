/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */

#if !defined(OPENSSL_NO_HMAC)
#include <string.h> /* memcpy() */
#include <openssl/hmac.h>

#if !defined(HAVE_HMAC_CTX_COPY)
int
HMAC_CTX_copy(HMAC_CTX *out, HMAC_CTX *in)
{
    if (!out || !in) {
	/* HMACerr(HMAC_CTX_COPY,HMAC_R_INPUT_NOT_INITIALIZED); */
	return 0;
    }
    memcpy(out, in, sizeof(HMAC_CTX));

    if (!EVP_MD_CTX_copy(&out->md_ctx, &in->md_ctx)) {
	return 0;
    }
    if (!EVP_MD_CTX_copy(&out->i_ctx, &in->i_ctx)) {
	return 0;
    }
    if (!EVP_MD_CTX_copy(&out->o_ctx, &in->o_ctx)) {
	return 0;
    }
    return 1;
}
#endif /* HAVE_HMAC_CTX_COPY */
#endif /* NO_HMAC */

#if !defined(HAVE_X509_STORE_SET_EX_DATA)
#include <openssl/x509_vfy.h>

int X509_STORE_set_ex_data(X509_STORE *str, int idx, void *data)
{
    return CRYPTO_set_ex_data(&str->ex_data,idx,data);
}
 
void *X509_STORE_get_ex_data(X509_STORE *str, int idx)
{
    return CRYPTO_get_ex_data(&str->ex_data,idx);
}
#endif

#if !defined(HAVE_EVP_MD_CTX_CREATE)
EVP_MD_CTX *
EVP_MD_CTX_create(void)
{
    EVP_MD_CTX *ctx = OPENSSL_malloc(sizeof *ctx);

    memset(ctx, '\0', sizeof *ctx);

    return ctx;
}
#endif

#if !defined(HAVE_EVP_MD_CTX_CLEANUP)
int
EVP_MD_CTX_cleanup(EVP_MD_CTX *ctx)
{
    /* FIXME!!! */
    memset(ctx, '\0', sizeof *ctx);

    return 1;
}
#endif

#if !defined(HAVE_EVP_MD_CTX_DESTROY)
void
EVP_MD_CTX_destroy(EVP_MD_CTX *ctx)
{
    EVP_MD_CTX_cleanup(ctx);
    OPENSSL_free(ctx);
}
#endif

#if !defined(HAVE_EVP_MD_CTX_INIT)
void
EVP_MD_CTX_init(EVP_MD_CTX *ctx)
{
    memset(ctx,'\0',sizeof *ctx);
}
#endif

#if !defined(HAVE_HMAC_CTX_INIT)
void
HMAC_CTX_init(HMAC_CTX *ctx)
{
    EVP_MD_CTX_init(&ctx->i_ctx);
    EVP_MD_CTX_init(&ctx->o_ctx);
    EVP_MD_CTX_init(&ctx->md_ctx);
}
#endif

#if !defined(HAVE_HMAC_CTX_CLEANUP)
void
HMAC_CTX_cleanup(HMAC_CTX *ctx)
{
    EVP_MD_CTX_cleanup(&ctx->i_ctx);
    EVP_MD_CTX_cleanup(&ctx->o_ctx);
    EVP_MD_CTX_cleanup(&ctx->md_ctx);
    memset(ctx,0,sizeof *ctx);
}
#endif

#if !defined(HAVE_X509_CRL_SET_VERSION)
int
X509_CRL_set_version(X509_CRL *x, long version)
{
    if (x == NULL) return(0);
    if (x->crl->version == NULL)
	{
	if ((x->crl->version=M_ASN1_INTEGER_new()) == NULL)
	    return(0);
	}
    return(ASN1_INTEGER_set(x->crl->version,version));
}
#endif

#if !defined(HAVE_X509_CRL_SET_ISSUER_NAME)
int
X509_CRL_set_issuer_name(X509_CRL *x, X509_NAME *name)
{
    if ((x == NULL) || (x->crl == NULL)) return(0);
    return(X509_NAME_set(&x->crl->issuer,name));
}
#endif

#if !defined(HAVE_X509_CRL_SORT)
int
X509_CRL_sort(X509_CRL *c)
{
    int i;
    X509_REVOKED *r;
    /* sort the data so it will be written in serial
     * number order */
    sk_X509_REVOKED_sort(c->crl->revoked);
    for (i=0; i<sk_X509_REVOKED_num(c->crl->revoked); i++){
	r=sk_X509_REVOKED_value(c->crl->revoked,i);
	r->sequence=i;
    }
    return 1;
}
#endif

#if !defined(HAVE_X509_CRL_ADD0_REVOKED)
static int
OSSL_X509_REVOKED_cmp(const X509_REVOKED * const *a, const X509_REVOKED * const *b)
{
    return(ASN1_STRING_cmp(
		(ASN1_STRING *)(*a)->serialNumber,
		(ASN1_STRING *)(*b)->serialNumber));
}
		    
int
X509_CRL_add0_revoked(X509_CRL *crl, X509_REVOKED *rev)
{
    X509_CRL_INFO *inf;
    inf = crl->crl;
    if(!inf->revoked)
	inf->revoked = sk_X509_REVOKED_new(OSSL_X509_REVOKED_cmp);
    if(!inf->revoked || !sk_X509_REVOKED_push(inf->revoked, rev)) {
	/* ASN1err(ASN1_F_X509_CRL_ADD0_REVOKED, ERR_R_MALLOC_FAILURE); */
	return 0;
    }
    return 1;
}
#endif

#if !defined(HAVE_BN_MOD_SQR)
int
BN_mod_sqr(BIGNUM *r, const BIGNUM *a, const BIGNUM *m, BN_CTX *ctx)
{
    if (!BN_sqr(r, (BIGNUM*)a, ctx)) return 0;
    /* r->neg == 0,  thus we don't need BN_nnmod */
    return BN_mod(r, r, m, ctx);
}
#endif

#if !defined(HAVE_BN_MOD_ADD) || !defined(HAVE_BN_MOD_SUB)
int BN_nnmod(BIGNUM *r, const BIGNUM *m, const BIGNUM *d, BN_CTX *ctx)
{
    /* like BN_mod, but returns non-negative remainder
     * (i.e.,  0 <= r < |d|  always holds) */
    if (!(BN_mod(r,m,d,ctx))) return 0;
    if (!r->neg) return 1;
    /* now   -|d| < r < 0,  so we have to set  r := r + |d| */
    return (d->neg ? BN_sub : BN_add)(r, r, d);
}
#endif

#if !defined(HAVE_BN_MOD_ADD)
int
BN_mod_add(BIGNUM *r, const BIGNUM *a, const BIGNUM *b, const BIGNUM *m, BN_CTX *ctx)
{
    if (!BN_add(r, a, b)) return 0;
    return BN_nnmod(r, r, m, ctx);
}
#endif

#if !defined(HAVE_BN_MOD_SUB)
int
BN_mod_sub(BIGNUM *r, const BIGNUM *a, const BIGNUM *b, const BIGNUM *m, BN_CTX *ctx)
{
    if (!BN_sub(r, a, b)) return 0;
    return BN_nnmod(r, r, m, ctx);
}
#endif

#if !defined(HAVE_CONF_GET1_DEFAULT_CONFIG_FILE)
#define OPENSSL_CONF "openssl.cnf"
char *
CONF_get1_default_config_file(void)
{
    char *file;
    int len;

    file = getenv("OPENSSL_CONF");
    if (file) return BUF_strdup(file);
    len = strlen(X509_get_default_cert_area());
#ifndef OPENSSL_SYS_VMS
    len++;
#endif
    len += strlen(OPENSSL_CONF);
    file = OPENSSL_malloc(len + 1);
    if (!file) return NULL;
    strcpy(file,X509_get_default_cert_area());
#ifndef OPENSSL_SYS_VMS
    strcat(file,"/");
#endif
    strcat(file,OPENSSL_CONF);

    return file;
}
#endif

#if !defined(HAVE_PEM_DEF_CALLBACK)
#define OSSL_PASS_MIN_LENGTH 4
int
PEM_def_callback(char *buf, int num, int w, void *key)
{
    int i,j;
    const char *prompt;
    if(key){
	i = strlen(key);
	i = (i > num) ? num : i;
	memcpy(buf, key, i);
	return(i);
    }

    prompt = EVP_get_pw_prompt();
    if (prompt == NULL) prompt= "Enter PEM pass phrase:";
    for(;;){
	i = EVP_read_pw_string(buf, num, prompt, w);
	if(i != 0){
	    memset(buf,0,(unsigned int)num);
	    return(-1);
	}
	j = strlen(buf);
	if(j < OSSL_PASS_MIN_LENGTH){
	    fprintf(stderr,
		    "phrase is too short, needs to be at least %d chars\n",
		    OSSL_PASS_MIN_LENGTH);
	}
	else break;
    }
    return(j);
}
#endif

