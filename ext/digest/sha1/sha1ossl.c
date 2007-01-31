/* $Id: sha1ossl.c,v 1.1.2.1 2006/08/07 09:01:27 matz Exp $ */

#include "defs.h"
#include "sha1ossl.h"
#include <assert.h>
#include <stdlib.h>

#ifndef _DIAGASSERT
#define _DIAGASSERT(cond)	assert(cond)
#endif

char *
SHA1_End(SHA1_CTX *ctx, char *buf)
{
    int i;
    char *p = buf;
    uint8_t digest[20];
    static const char hex[]="0123456789abcdef";

    _DIAGASSERT(ctx != NULL);
    /* buf may be NULL */

    if (p == NULL && (p = malloc(41)) == NULL)
	return 0;

    SHA1_Final(digest,ctx);
    for (i = 0; i < 20; i++) {
	p[i + i] = hex[((uint32_t)digest[i]) >> 4];
	p[i + i + 1] = hex[digest[i] & 0x0f];
    }
    p[i + i] = '\0';
    return(p);
}

int SHA1_Equal(SHA1_CTX* pctx1, SHA1_CTX* pctx2) {
	return pctx1->num == pctx2->num
	  && pctx1->h0 == pctx2->h0
	  && pctx1->h1 == pctx2->h1
	  && pctx1->h2 == pctx2->h2
	  && pctx1->h3 == pctx2->h3
	  && pctx1->h4 == pctx2->h4
	  && pctx1->Nl == pctx2->Nl
	  && pctx1->Nh == pctx2->Nh
	  && memcmp(pctx1->data, pctx2->data, sizeof(pctx1->data)) == 0;
}
