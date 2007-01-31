/* $Id: md5ossl.c,v 1.2 2003/01/06 11:47:53 knu Exp $ */

#include "md5ossl.h"
#include <sys/types.h>
#include <stdio.h>
#include <string.h>

void
MD5_End(MD5_CTX *pctx, unsigned char *hexdigest)
{
    unsigned char digest[16];
    size_t i;

    MD5_Final(digest, pctx);

    for (i = 0; i < 16; i++)
        sprintf(hexdigest + i * 2, "%02x", digest[i]);
}

int
MD5_Equal(MD5_CTX* pctx1, MD5_CTX* pctx2) {
    return pctx1->num == pctx2->num
      && pctx1->A == pctx2->A
      && pctx1->B == pctx2->B
      && pctx1->C == pctx2->C
      && pctx1->D == pctx2->D
      && pctx1->Nl == pctx2->Nl
      && pctx1->Nh == pctx2->Nh
      && memcmp(pctx1->data, pctx2->data, sizeof(pctx1->data)) == 0;
}
