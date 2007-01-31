/* $Id: rmd160ossl.c,v 1.1.2.1 2006/08/07 09:01:27 matz Exp $ */

#include "defs.h"
#include "rmd160ossl.h"
#include <assert.h>
#include <stdlib.h>

#ifndef _DIAGASSERT
#define _DIAGASSERT(cond)	assert(cond)
#endif

char *
RMD160_End(RMD160_CTX *ctx, char *buf)
{
    size_t i;
    char *p = buf;
    uint8_t digest[20];
    static const char hex[]="0123456789abcdef";

    _DIAGASSERT(ctx != NULL);
    /* buf may be NULL */

    if (p == NULL && (p = malloc(41)) == NULL)
	return 0;

    RMD160_Final(digest,ctx);
    for (i = 0; i < 20; i++) {
	p[i + i] = hex[(uint32_t)digest[i] >> 4];
	p[i + i + 1] = hex[digest[i] & 0x0f];
    }
    p[i + i] = '\0';
    return(p);
}

int RMD160_Equal(RMD160_CTX* pctx1, RMD160_CTX* pctx2) {
	return pctx1->num == pctx2->num
	  && pctx1->A == pctx2->A
	  && pctx1->B == pctx2->B
	  && pctx1->C == pctx2->C
	  && pctx1->D == pctx2->D
	  && pctx1->E == pctx2->E
	  && pctx1->Nl == pctx2->Nl
	  && pctx1->Nh == pctx2->Nh
	  && memcmp(pctx1->data, pctx2->data, sizeof(pctx1->data)) == 0;
}
