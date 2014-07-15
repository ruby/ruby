/* $Id$ */

#ifndef MD5OSSL_H_INCLUDED
#define MD5OSSL_H_INCLUDED

#include <stddef.h>
#include <openssl/evp.h>

#define MD5_Init   rb_digest_md5osslevp_Init
#define MD5_Update EVP_DigestUpdate
#define MD5_Finish rb_digest_md5osslevp_Finish
#define MD5_CTX    EVP_MD_CTX

/* We should use EVP_MD_size(3) and EVP_MD_block_size(3), but the
   advantage of these is that they are flexible across digest
   algorithms and we are fixing the digest algorithm here; and these
   numbers must be constants because the rb_digest_metadata_t
   structure is declared const. Simplest way is to write literals. */
#define MD5_BLOCK_LENGTH		64
#define MD5_DIGEST_LENGTH		16

int MD5_Init(MD5_CTX *pctx);
int MD5_Finish(MD5_CTX *pctx, unsigned char *digest);

#endif
