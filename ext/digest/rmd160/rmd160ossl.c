/* $Id$ */

#include "defs.h"
#include "rmd160ossl.h"
#include <assert.h>
#include <stdlib.h>

void RMD160_Finish(RMD160_CTX *ctx, char *buf) {
	RIPEMD160_Final(buf, ctx);
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
