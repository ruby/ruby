/*	$NetBSD: sha1.h,v 1.2 1998/05/29 22:55:44 thorpej Exp $	*/
/*	$RoughId: sha1.h,v 1.3 2002/02/24 08:14:32 knu Exp $	*/
/*	$Id: sha1.h,v 1.2 2002/02/24 08:20:22 knu Exp $	*/

/*
 * SHA-1 in C
 * By Steve Reid <steve@edmweb.com>
 * 100% Public Domain
 */

#ifndef _SYS_SHA1_H_
#define	_SYS_SHA1_H_

#include "defs.h"

typedef struct {
	uint32_t state[5];
	uint32_t count[2];  
	uint8_t buffer[64];
} SHA1_CTX;

#ifdef RUBY
#define SHA1_Transform	rb_Digest_SHA1_Transform
#define SHA1_Init	rb_Digest_SHA1_Init
#define SHA1_Update	rb_Digest_SHA1_Update
#define SHA1_Final	rb_Digest_SHA1_Final
#define SHA1_Equal	rb_Digest_SHA1_Equal
#ifndef _KERNEL
#define SHA1_End	rb_Digest_SHA1_End
#define SHA1_File	rb_Digest_SHA1_File
#define SHA1_Data	rb_Digest_SHA1_Data
#endif /* _KERNEL */
#endif

void	SHA1_Transform _((uint32_t state[5], const uint8_t buffer[64]));
void	SHA1_Init _((SHA1_CTX *context));
void	SHA1_Update _((SHA1_CTX *context, const uint8_t *data, size_t len));
void	SHA1_Final _((uint8_t digest[20], SHA1_CTX *context));
int	SHA1_Equal _((SHA1_CTX *pctx1, SHA1_CTX *pctx2));
#ifndef _KERNEL
char	*SHA1_End _((SHA1_CTX *, char *));
char	*SHA1_File _((char *, char *));
char	*SHA1_Data _((const uint8_t *, size_t, char *));
#endif /* _KERNEL */

#define SHA1_BLOCK_LENGTH		64
#define SHA1_DIGEST_LENGTH		20
#define SHA1_DIGEST_STRING_LENGTH	(SHA1_DIGEST_LENGTH * 2 + 1)
  
#endif /* _SYS_SHA1_H_ */
