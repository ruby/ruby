#include "../defs.h"
#include "sha2ossl.h"

#define SHA_Finish(bit) \
    void SHA##bit##_Finish(SHA##bit##_CTX *ctx, char *buf) \
    { SHA##bit##_Final((unsigned char *)buf, ctx);}
#define SHA384_Final SHA512_Final

SHA_Finish(256)
SHA_Finish(384)
SHA_Finish(512)
