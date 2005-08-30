/* $Id$ */

#ifndef MD5OSSL_H_INCLUDED
#define MD5OSSL_H_INCLUDED

#include <stddef.h>
#include <openssl/md5.h>

void MD5_End(MD5_CTX *pctx, unsigned char *hexdigest);
int MD5_Equal(MD5_CTX *pctx1, MD5_CTX *pctx2);

#endif
