/* $Id$ */

#include "defs.h"
#include "sha1ossl.h"
#include <stdlib.h>

void
SHA1_Finish(SHA1_CTX *ctx, char *buf)
{
	SHA1_Final(buf, ctx);
}

int
SHA1_Equal(SHA1_CTX* pctx1, SHA1_CTX* pctx2)
{
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
