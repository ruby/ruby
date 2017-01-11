#ifndef SHA2OSSL_H_INCLUDED
#define SHA2OSSL_H_INCLUDED

#include <stddef.h>
#include <openssl/sha.h>

#define SHA256_BLOCK_LENGTH	SHA256_CBLOCK
#define SHA384_BLOCK_LENGTH	SHA512_CBLOCK
#define SHA512_BLOCK_LENGTH	SHA512_CBLOCK

#ifndef __DragonFly__
#define SHA384_Final SHA512_Final
#endif

typedef SHA512_CTX SHA384_CTX;

#undef SHA256_Finish
#undef SHA384_Finish
#undef SHA512_Finish
#define SHA256_Finish rb_digest_SHA256_finish
#define SHA384_Finish rb_digest_SHA384_finish
#define SHA512_Finish rb_digest_SHA512_finish
static DEFINE_FINISH_FUNC_FROM_FINAL(SHA256)
static DEFINE_FINISH_FUNC_FROM_FINAL(SHA384)
static DEFINE_FINISH_FUNC_FROM_FINAL(SHA512)

#endif
