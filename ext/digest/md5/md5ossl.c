/* $Id$ */

#include "md5ossl.h"

int
rb_digest_md5osslevp_Init(EVP_MD_CTX *pctx)
{
    return EVP_DigestInit_ex(pctx, EVP_md5(), NULL);
}

int
rb_digest_md5osslevp_Finish(EVP_MD_CTX *pctx, unsigned char *digest)
{
    /* if EVP_DigestFinal_ex fails, we ignore that */
    return EVP_DigestFinal_ex(pctx, digest, NULL);
}
