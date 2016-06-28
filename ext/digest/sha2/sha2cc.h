#define COMMON_DIGEST_FOR_OPENSSL 1
#include <CommonCrypto/CommonDigest.h>

#define SHA256_BLOCK_LENGTH	CC_SHA256_BLOCK_BYTES
#define SHA384_BLOCK_LENGTH	CC_SHA384_BLOCK_BYTES
#define SHA512_BLOCK_LENGTH	CC_SHA512_BLOCK_BYTES

#define SHA384_CTX		CC_SHA512_CTX

static DEFINE_UPDATE_FUNC_FOR_UINT(SHA256)
static DEFINE_FINISH_FUNC_FROM_FINAL(SHA256)
static DEFINE_UPDATE_FUNC_FOR_UINT(SHA384)
static DEFINE_FINISH_FUNC_FROM_FINAL(SHA384)
static DEFINE_UPDATE_FUNC_FOR_UINT(SHA512)
static DEFINE_FINISH_FUNC_FROM_FINAL(SHA512)


#undef SHA256_Update
#undef SHA256_Finish
#define SHA256_Update rb_digest_SHA256_update
#define SHA256_Finish rb_digest_SHA256_finish

#undef SHA384_Update
#undef SHA384_Finish
#define SHA384_Update rb_digest_SHA384_update
#define SHA384_Finish rb_digest_SHA384_finish

#undef SHA512_Update
#undef SHA512_Finish
#define SHA512_Update rb_digest_SHA512_update
#define SHA512_Finish rb_digest_SHA512_finish
