#define COMMON_DIGEST_FOR_OPENSSL 1
#include <CommonCrypto/CommonDigest.h>

/*
 * Prior to 10.5, OpenSSL-compatible definitions are missing for
 * SHA2 macros, though the CC_ versions are present.
 * Add the missing definitions we actually use here if needed.
 * Note that the definitions are the argless 10.6+-style.
 * The weird CTX mismatch is copied from the 10.6 header.
 */
#ifndef SHA256_DIGEST_LENGTH
#define SHA256_DIGEST_LENGTH	CC_SHA256_DIGEST_LENGTH
#define SHA256_CTX		CC_SHA256_CTX
#define SHA256_Update		CC_SHA256_Update
#define SHA256_Final		CC_SHA256_Final
#endif /* !defined SHA256_DIGEST_LENGTH */

#ifndef SHA384_DIGEST_LENGTH
#define SHA384_DIGEST_LENGTH	CC_SHA384_DIGEST_LENGTH
#define SHA512_CTX		CC_SHA512_CTX
#define SHA384_Update		CC_SHA384_Update
#define SHA384_Final		CC_SHA384_Final
#endif /* !defined SHA384_DIGEST_LENGTH */

#ifndef SHA512_DIGEST_LENGTH
#define SHA512_DIGEST_LENGTH	CC_SHA512_DIGEST_LENGTH
#define SHA512_Update		CC_SHA512_Update
#define SHA512_Final		CC_SHA512_Final
#endif /* !defined SHA512_DIGEST_LENGTH */

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

/*
 * Pre-10.6 defines are with args, which don't match the argless use in
 * the function pointer inits.  Thus, we redefine SHA*_Init as well.
 * This is a NOP on 10.6+.
 */
#undef SHA256_Init
#define SHA256_Init CC_SHA256_Init
#undef SHA384_Init
#define SHA384_Init CC_SHA384_Init
#undef SHA512_Init
#define SHA512_Init CC_SHA512_Init
