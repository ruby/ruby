#define COMMON_DIGEST_FOR_OPENSSL 1
#include <CommonCrypto/CommonDigest.h>

#define SHA1_BLOCK_LENGTH	CC_SHA1_BLOCK_BYTES
#define SHA1_DIGEST_LENGTH	CC_SHA1_DIGEST_LENGTH
#define SHA1_CTX		CC_SHA1_CTX

static DEFINE_UPDATE_FUNC_FOR_UINT(SHA1)
static DEFINE_FINISH_FUNC_FROM_FINAL(SHA1)

#undef SHA1_Update
#undef SHA1_Finish
#define SHA1_Update rb_digest_SHA1_update
#define SHA1_Finish rb_digest_SHA1_finish
