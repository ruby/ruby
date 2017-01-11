#define COMMON_DIGEST_FOR_OPENSSL 1
#include <CommonCrypto/CommonDigest.h>

#define MD5_BLOCK_LENGTH	CC_MD5_BLOCK_BYTES

static DEFINE_UPDATE_FUNC_FOR_UINT(MD5)
static DEFINE_FINISH_FUNC_FROM_FINAL(MD5)

#undef MD5_Update
#undef MD5_Finish
#define MD5_Update rb_digest_MD5_update
#define MD5_Finish rb_digest_MD5_finish
