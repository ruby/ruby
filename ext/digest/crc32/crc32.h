#ifndef _CRC32_H_
#define _CRC32_H_

#include "../defs.h"

typedef struct {
    uint32_t state;
} CRC32_CTX;

#ifdef RUBY
#define CRC32_Init	rb_Digest_CRC32_Init
#define CRC32_Update	rb_Digest_CRC32_Update
#define CRC32_Finish	rb_Digest_CRC32_Finish
#endif

__BEGIN_DECLS
int	CRC32_Init _((CRC32_CTX *));
void	CRC32_Update _((CRC32_CTX *, const uint8_t *, size_t));
int	CRC32_Finish _((CRC32_CTX *, uint8_t[4]));
__END_DECLS

#define CRC32_BLOCK_LENGTH             8
#define CRC32_DIGEST_LENGTH            4
#define CRC32_DIGEST_STRING_LENGTH     (CRC32_DIGEST_LENGTH * 2 + 1)

#endif  /* !_CRC32_H_ */
