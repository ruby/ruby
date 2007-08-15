/*	$NetBSD: rmd160.h,v 1.2 2000/07/07 10:47:06 ad Exp $	*/
/*	$RoughId: rmd160.h,v 1.3 2002/02/24 08:14:31 knu Exp $	*/
/*	$Id: rmd160.h,v 1.2 2002/02/24 08:20:22 knu Exp $	*/

/********************************************************************\
 *
 *      FILE:     rmd160.h
 *
 *      CONTENTS: Header file for a sample C-implementation of the
 *                RIPEMD-160 hash-function. 
 *      TARGET:   any computer with an ANSI C compiler
 *
 *      AUTHOR:   Antoon Bosselaers, ESAT-COSIC
 *      DATE:     1 March 1996
 *      VERSION:  1.0
 *
 *      Copyright (c) Katholieke Universiteit Leuven
 *      1996, All Rights Reserved
 *
\********************************************************************/

/*
 * from OpenBSD: rmd160.h,v 1.4 1999/08/16 09:59:04 millert Exp
 */

#ifndef _RMD160_H_
#define _RMD160_H_

#include "defs.h"

typedef struct {
	uint32_t	state[5];	/* state (ABCDE) */
	uint32_t	length[2];	/* number of bits */
	uint8_t		bbuffer[64];    /* overflow buffer */
	uint32_t	buflen;		/* number of chars in bbuffer */
} RMD160_CTX;

#ifdef RUBY
#define RMD160_Init	rb_Digest_RMD160_Init
#define RMD160_Transform	rb_Digest_RMD160_Transform
#define RMD160_Update	rb_Digest_RMD160_Update
#define RMD160_Final	rb_Digest_RMD160_Final
#define RMD160_Equal	rb_Digest_RMD160_Equal
#ifndef _KERNEL
#define RMD160_End	rb_Digest_RMD160_End
#define RMD160_File	rb_Digest_RMD160_File
#define RMD160_Data	rb_Digest_RMD160_Data
#endif /* _KERNEL */
#endif

__BEGIN_DECLS
void	RMD160_Init _((RMD160_CTX *));
void	RMD160_Transform _((uint32_t[5], const uint32_t[16]));
void	RMD160_Update _((RMD160_CTX *, const uint8_t *, size_t));
void	RMD160_Final _((uint8_t[20], RMD160_CTX *));
int	RMD160_Equal _((RMD160_CTX *, RMD160_CTX *));
#ifndef	_KERNEL
char	*RMD160_End _((RMD160_CTX *, char *));
char	*RMD160_File _((char *, char *));
char	*RMD160_Data _((const uint8_t *, size_t, char *));
#endif /* _KERNEL */
__END_DECLS

#define RMD160_BLOCK_LENGTH             64
#define RMD160_DIGEST_LENGTH            20
#define RMD160_DIGEST_STRING_LENGTH     (RMD160_DIGEST_LENGTH * 2 + 1)

#endif  /* !_RMD160_H_ */
