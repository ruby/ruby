/*
 * Copyright (c) 1989, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * This code is derived from software contributed to Berkeley by
 * Tom Truscott.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#if defined(LIBC_SCCS) && !defined(lint)
static char sccsid[] = "@(#)crypt.c	8.1 (Berkeley) 6/4/93";
#endif /* LIBC_SCCS and not lint */

#include "ruby/missing.h"
#include "crypt.h"
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <limits.h>
#ifdef HAVE_PWD_H
#include <pwd.h>
#endif
#include <stdio.h>
#include <string.h>
#ifndef _PASSWORD_EFMT1
#define _PASSWORD_EFMT1 '_'
#endif

#ifndef numberof
#define numberof(array) (int)(sizeof(array) / sizeof((array)[0]))
#endif

/*
 * UNIX password, and DES, encryption.
 * By Tom Truscott, trt@rti.rti.org,
 * from algorithms by Robert W. Baldwin and James Gillogly.
 *
 * References:
 * "Mathematical Cryptology for Computer Scientists and Mathematicians,"
 * by Wayne Patterson, 1987, ISBN 0-8476-7438-X.
 *
 * "Password Security: A Case History," R. Morris and Ken Thompson,
 * Communications of the ACM, vol. 22, pp. 594-597, Nov. 1979.
 *
 * "DES will be Totally Insecure within Ten Years," M.E. Hellman,
 * IEEE Spectrum, vol. 16, pp. 32-39, July 1979.
 */

/* =====  Configuration ==================== */

/*
 * define "MUST_ALIGN" if your compiler cannot load/store
 * long integers at arbitrary (e.g. odd) memory locations.
 * (Either that or never pass unaligned addresses to des_cipher!)
 */
#if !defined(vax)
#define	MUST_ALIGN
#endif

#ifdef CHAR_BITS
#if CHAR_BITS != 8
	#error C_block structure assumes 8 bit characters
#endif
#endif

#ifndef INIT_DES
# if defined DUMP || defined NO_DES_TABLES
#   define INIT_DES 1
# else
#   define INIT_DES 0
# endif
#endif
#if !INIT_DES
# include "des_tables.c"
# ifdef HAVE_DES_TABLES
#   define init_des() ((void)0)
# else
#   undef INIT_DES
#   define INIT_DES 1
# endif
#endif

/*
 * Convert twenty-four-bit long in host-order
 * to six bits (and 2 low-order zeroes) per char little-endian format.
 */
#define	TO_SIX_BIT(rslt, src) {				\
		C_block cvt;				\
		cvt.b[0] = (unsigned char)(src); (src) >>= 6; \
		cvt.b[1] = (unsigned char)(src); (src) >>= 6; \
		cvt.b[2] = (unsigned char)(src); (src) >>= 6; \
		cvt.b[3] = (unsigned char)(src);		\
		(rslt) = (cvt.b32.i0 & 0x3f3f3f3fL) << 2;	\
	}

/*
 * These macros may someday permit efficient use of 64-bit integers.
 */
#define	ZERO(d,d0,d1)			((d0) = 0, (d1) = 0)
#define	LOAD(d,d0,d1,bl)		((d0) = (bl).b32.i0, (d1) = (bl).b32.i1)
#define	LOADREG(d,d0,d1,s,s0,s1)	((d0) = (s0), (d1) = (s1))
#define	OR(d,d0,d1,bl)			((d0) |= (bl).b32.i0, (d1) |= (bl).b32.i1)
#define	STORE(s,s0,s1,bl)		((bl).b32.i0 = (s0), (bl).b32.i1 = (s1))
#define	DCL_BLOCK(d,d0,d1)		long d0, d1

#if defined(LARGEDATA)
	/* Waste memory like crazy.  Also, do permutations in line */
#define	PERM6464(d,d0,d1,cpp,p)				\
	LOAD((d),(d0),(d1),(p)[(0<<CHUNKBITS)+(cpp)[0]]);		\
	OR ((d),(d0),(d1),(p)[(1<<CHUNKBITS)+(cpp)[1]]);		\
	OR ((d),(d0),(d1),(p)[(2<<CHUNKBITS)+(cpp)[2]]);		\
	OR ((d),(d0),(d1),(p)[(3<<CHUNKBITS)+(cpp)[3]]);		\
	OR (d),(d0),(d1),(p)[(4<<CHUNKBITS)+(cpp)[4]]);		\
	OR (d),(d0),(d1),(p)[(5<<CHUNKBITS)+(cpp)[5]]);		\
	OR (d),(d0),(d1),(p)[(6<<CHUNKBITS)+(cpp)[6]]);		\
	OR (d),(d0),(d1),(p)[(7<<CHUNKBITS)+(cpp)[7]]);
#define	PERM3264(d,d0,d1,cpp,p)				\
	LOAD((d),(d0),(d1),(p)[(0<<CHUNKBITS)+(cpp)[0]]);		\
	OR ((d),(d0),(d1),(p)[(1<<CHUNKBITS)+(cpp)[1]]);		\
	OR ((d),(d0),(d1),(p)[(2<<CHUNKBITS)+(cpp)[2]]);		\
	OR ((d),(d0),(d1),(p)[(3<<CHUNKBITS)+(cpp)[3]]);
#else
	/* "small data" */
#define	PERM6464(d,d0,d1,cpp,p)				\
	{ C_block tblk; permute((cpp),&tblk,(p),8); LOAD ((d),(d0),(d1),tblk); }
#define	PERM3264(d,d0,d1,cpp,p)				\
	{ C_block tblk; permute((cpp),&tblk,(p),4); LOAD ((d),(d0),(d1),tblk); }

STATIC void
permute(const unsigned char *cp, C_block *out, register const C_block *p, int chars_in)
{
	register DCL_BLOCK(D,D0,D1);
	register const C_block *tp;
	register int t;

	ZERO(D,D0,D1);
	do {
		t = *cp++;
		tp = &p[t&0xf]; OR(D,D0,D1,*tp); p += (1<<CHUNKBITS);
		tp = &p[t>>4];  OR(D,D0,D1,*tp); p += (1<<CHUNKBITS);
	} while (--chars_in > 0);
	STORE(D,D0,D1,*out);
}
#endif /* LARGEDATA */

#ifdef DEBUG
STATIC void prtab(const char *s, const unsigned char *t, int num_rows);
#endif

#if INIT_DES
/* =====  (mostly) Standard DES Tables ==================== */

static const unsigned char IP[] = {	/* initial permutation */
	58, 50, 42, 34, 26, 18, 10,  2,
	60, 52, 44, 36, 28, 20, 12,  4,
	62, 54, 46, 38, 30, 22, 14,  6,
	64, 56, 48, 40, 32, 24, 16,  8,
	57, 49, 41, 33, 25, 17,  9,  1,
	59, 51, 43, 35, 27, 19, 11,  3,
	61, 53, 45, 37, 29, 21, 13,  5,
	63, 55, 47, 39, 31, 23, 15,  7,
};

/* The final permutation is the inverse of IP - no table is necessary */

static const unsigned char ExpandTr[] = { /* expansion operation */
	32,  1,  2,  3,  4,  5,
	 4,  5,  6,  7,  8,  9,
	 8,  9, 10, 11, 12, 13,
	12, 13, 14, 15, 16, 17,
	16, 17, 18, 19, 20, 21,
	20, 21, 22, 23, 24, 25,
	24, 25, 26, 27, 28, 29,
	28, 29, 30, 31, 32,  1,
};

static const unsigned char PC1[] = {	/* permuted choice table 1 */
	57, 49, 41, 33, 25, 17,  9,
	 1, 58, 50, 42, 34, 26, 18,
	10,  2, 59, 51, 43, 35, 27,
	19, 11,  3, 60, 52, 44, 36,

	63, 55, 47, 39, 31, 23, 15,
	 7, 62, 54, 46, 38, 30, 22,
	14,  6, 61, 53, 45, 37, 29,
	21, 13,  5, 28, 20, 12,  4,
};
#endif

static const unsigned char Rotates[] = { /* PC1 rotation schedule */
	1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1,
};

#if INIT_DES
/* note: each "row" of PC2 is left-padded with bits that make it invertible */
static const unsigned char PC2[] = {	/* permuted choice table 2 */
	 9, 18,    14, 17, 11, 24,  1,  5,
	22, 25,     3, 28, 15,  6, 21, 10,
	35, 38,    23, 19, 12,  4, 26,  8,
	43, 54,    16,  7, 27, 20, 13,  2,

	 0,  0,    41, 52, 31, 37, 47, 55,
	 0,  0,    30, 40, 51, 45, 33, 48,
	 0,  0,    44, 49, 39, 56, 34, 53,
	 0,  0,    46, 42, 50, 36, 29, 32,
};

static const unsigned char S[8][64] = { /* 48->32 bit substitution tables */
    {
					/* S[1]			*/
	14,  4, 13,  1,  2, 15, 11,  8,  3, 10,  6, 12,  5,  9,  0,  7,
	 0, 15,  7,  4, 14,  2, 13,  1, 10,  6, 12, 11,  9,  5,  3,  8,
	 4,  1, 14,  8, 13,  6,  2, 11, 15, 12,  9,  7,  3, 10,  5,  0,
	15, 12,  8,  2,  4,  9,  1,  7,  5, 11,  3, 14, 10,  0,  6, 13,
    },
    {
					/* S[2]			*/
	15,  1,  8, 14,  6, 11,  3,  4,  9,  7,  2, 13, 12,  0,  5, 10,
	 3, 13,  4,  7, 15,  2,  8, 14, 12,  0,  1, 10,  6,  9, 11,  5,
	 0, 14,  7, 11, 10,  4, 13,  1,  5,  8, 12,  6,  9,  3,  2, 15,
	13,  8, 10,  1,  3, 15,  4,  2, 11,  6,  7, 12,  0,  5, 14,  9,
    },
    {
					/* S[3]			*/
	10,  0,  9, 14,  6,  3, 15,  5,  1, 13, 12,  7, 11,  4,  2,  8,
	13,  7,  0,  9,  3,  4,  6, 10,  2,  8,  5, 14, 12, 11, 15,  1,
	13,  6,  4,  9,  8, 15,  3,  0, 11,  1,  2, 12,  5, 10, 14,  7,
	 1, 10, 13,  0,  6,  9,  8,  7,  4, 15, 14,  3, 11,  5,  2, 12,
    },
    {
					/* S[4]			*/
	 7, 13, 14,  3,  0,  6,  9, 10,  1,  2,  8,  5, 11, 12,  4, 15,
	13,  8, 11,  5,  6, 15,  0,  3,  4,  7,  2, 12,  1, 10, 14,  9,
	10,  6,  9,  0, 12, 11,  7, 13, 15,  1,  3, 14,  5,  2,  8,  4,
	 3, 15,  0,  6, 10,  1, 13,  8,  9,  4,  5, 11, 12,  7,  2, 14,
    },
    {
					/* S[5]			*/
	 2, 12,  4,  1,  7, 10, 11,  6,  8,  5,  3, 15, 13,  0, 14,  9,
	14, 11,  2, 12,  4,  7, 13,  1,  5,  0, 15, 10,  3,  9,  8,  6,
	 4,  2,  1, 11, 10, 13,  7,  8, 15,  9, 12,  5,  6,  3,  0, 14,
	11,  8, 12,  7,  1, 14,  2, 13,  6, 15,  0,  9, 10,  4,  5,  3,
    },
    {
					/* S[6]			*/
	12,  1, 10, 15,  9,  2,  6,  8,  0, 13,  3,  4, 14,  7,  5, 11,
	10, 15,  4,  2,  7, 12,  9,  5,  6,  1, 13, 14,  0, 11,  3,  8,
	 9, 14, 15,  5,  2,  8, 12,  3,  7,  0,  4, 10,  1, 13, 11,  6,
	 4,  3,  2, 12,  9,  5, 15, 10, 11, 14,  1,  7,  6,  0,  8, 13,
    },
    {
					/* S[7]			*/
	 4, 11,  2, 14, 15,  0,  8, 13,  3, 12,  9,  7,  5, 10,  6,  1,
	13,  0, 11,  7,  4,  9,  1, 10, 14,  3,  5, 12,  2, 15,  8,  6,
	 1,  4, 11, 13, 12,  3,  7, 14, 10, 15,  6,  8,  0,  5,  9,  2,
	 6, 11, 13,  8,  1,  4, 10,  7,  9,  5,  0, 15, 14,  2,  3, 12,
    },
    {
					/* S[8]			*/
	13,  2,  8,  4,  6, 15, 11,  1, 10,  9,  3, 14,  5,  0, 12,  7,
	 1, 15, 13,  8, 10,  3,  7,  4, 12,  5,  6, 11,  0, 14,  9,  2,
	 7, 11,  4,  1,  9, 12, 14,  2,  0,  6, 10, 13, 15,  3,  5,  8,
	 2,  1, 14,  7,  4, 10,  8, 13, 15, 12,  9,  0,  3,  5,  6, 11,
    },
};

static const unsigned char P32Tr[] = {	/* 32-bit permutation function */
	16,  7, 20, 21,
	29, 12, 28, 17,
	 1, 15, 23, 26,
	 5, 18, 31, 10,
	 2,  8, 24, 14,
	32, 27,  3,  9,
	19, 13, 30,  6,
	22, 11,  4, 25,
};

static const unsigned char CIFP[] = {	/* compressed/interleaved permutation */
	 1,  2,  3,  4,   17, 18, 19, 20,
	 5,  6,  7,  8,   21, 22, 23, 24,
	 9, 10, 11, 12,   25, 26, 27, 28,
	13, 14, 15, 16,   29, 30, 31, 32,

	33, 34, 35, 36,   49, 50, 51, 52,
	37, 38, 39, 40,   53, 54, 55, 56,
	41, 42, 43, 44,   57, 58, 59, 60,
	45, 46, 47, 48,   61, 62, 63, 64,
};
#endif

static const unsigned char itoa64[] =	/* 0..63 => ascii-64 */
	"./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/* table that converts chars "./0-9A-Za-z"to integers 0-63. */
static const unsigned char a64toi[256] = {
#define A64TOI1(c) \
	((c) == '.' ? 0 :						\
	 (c) == '/' ? 1 :						\
	 ('0' <= (c) && (c) <= '9') ? (c) - '0' + 2 :			\
	 ('A' <= (c) && (c) <= 'Z') ? (c) - 'A' + 12 :			\
	 ('a' <= (c) && (c) <= 'z') ? (c) - 'a' + 38 :			\
	 0)
#define A64TOI4(base) A64TOI1(base+0), A64TOI1(base+1), A64TOI1(base+2), A64TOI1(base+3)
#define A64TOI16(base) A64TOI4(base+0), A64TOI4(base+4), A64TOI4(base+8), A64TOI4(base+12)
#define A64TOI64(base) A64TOI16(base+0x00), A64TOI16(base+0x10), A64TOI16(base+0x20), A64TOI16(base+0x30)
	A64TOI64(0x00), A64TOI64(0x40),
	A64TOI64(0x00), A64TOI64(0x40),
};

#if INIT_DES
/* =====  Tables that are initialized at run time  ==================== */

typedef struct {
	/* Initial key schedule permutation */
	C_block	PC1ROT[64/CHUNKBITS][1<<CHUNKBITS];

	/* Subsequent key schedule rotation permutations */
	C_block	PC2ROT[2][64/CHUNKBITS][1<<CHUNKBITS];

	/* Initial permutation/expansion table */
	C_block	IE3264[32/CHUNKBITS][1<<CHUNKBITS];

	/* Table that combines the S, P, and E operations.  */
	unsigned long SPE[2][8][64];

	/* compressed/interleaved => final permutation table */
	C_block CF6464[64/CHUNKBITS][1<<CHUNKBITS];

	int ready;
} des_tables_t;
static des_tables_t des_tables[1];

#define des_tables	((const des_tables_t *)des_tables)
#define PC1ROT		(des_tables->PC1ROT)
#define PC2ROT		(des_tables->PC2ROT)
#define IE3264		(des_tables->IE3264)
#define SPE		(des_tables->SPE)
#define CF6464		(des_tables->CF6464)

STATIC void init_des(void);
STATIC void init_perm(C_block perm[64/CHUNKBITS][1<<CHUNKBITS], unsigned char p[64], int chars_in, int chars_out);
#endif

static const C_block constdatablock = {{0}}; /* encryption constant */

#define KS	(data->KS)
#define cryptresult (data->cryptresult)

static void des_setkey_r(const unsigned char *key, struct crypt_data *data);
static void des_cipher_r(const unsigned char *in, unsigned char *out, long salt, int num_iter, struct crypt_data *data);

#ifdef USE_NONREENTRANT_CRYPT
static struct crypt_data default_crypt_data;
#endif

#ifdef USE_NONREENTRANT_CRYPT
/*
 * Return a pointer to static data consisting of the "setting"
 * followed by an encryption produced by the "key" and "setting".
 */
char *
crypt(const char *key, const char *setting)
{
	return crypt_r(key, setting, &default_crypt_data);
}
#endif

/*
 * Return a pointer to data consisting of the "setting" followed by an
 * encryption produced by the "key" and "setting".
 */
char *
crypt_r(const char *key, const char *setting, struct crypt_data *data)
{
	register char *encp;
	register long i;
	register int t;
	long salt;
	int num_iter, salt_size;
	C_block keyblock, rsltblock;

	for (i = 0; i < 8; i++) {
		if ((t = 2*(unsigned char)(*key)) != 0)
			key++;
		keyblock.b[i] = t;
	}
	des_setkey_r(keyblock.b, data);	/* also initializes "a64toi" */

	encp = &cryptresult[0];
	switch (*setting) {
	case _PASSWORD_EFMT1:
		/*
		 * Involve the rest of the password 8 characters at a time.
		 */
		while (*key) {
			des_cipher_r(keyblock.b, keyblock.b, 0L, 1, data);
			for (i = 0; i < 8; i++) {
				if ((t = 2*(unsigned char)(*key)) != 0)
					key++;
				keyblock.b[i] ^= t;
			}
			des_setkey_r(keyblock.b, data);
		}

		*encp++ = *setting++;

		/* get iteration count */
		num_iter = 0;
		for (i = 4; --i >= 0; ) {
			if ((t = (unsigned char)setting[i]) == '\0')
				t = '.';
			encp[i] = t;
			num_iter = (num_iter<<6) | a64toi[t];
		}
		setting += 4;
		encp += 4;
		salt_size = 4;
		break;
	default:
		num_iter = 25;
		salt_size = 2;
	}

	salt = 0;
	for (i = salt_size; --i >= 0; ) {
		if ((t = (unsigned char)setting[i]) == '\0')
			t = '.';
		encp[i] = t;
		salt = (salt<<6) | a64toi[t];
	}
	encp += salt_size;
	des_cipher_r(constdatablock.b, rsltblock.b, salt, num_iter, data);

	/*
	 * Encode the 64 cipher bits as 11 ascii characters.
	 */
	i = ((long)((rsltblock.b[0]<<8) | rsltblock.b[1])<<8) | rsltblock.b[2];
	encp[3] = itoa64[i&0x3f];	i >>= 6;
	encp[2] = itoa64[i&0x3f];	i >>= 6;
	encp[1] = itoa64[i&0x3f];	i >>= 6;
	encp[0] = itoa64[i];		encp += 4;
	i = ((long)((rsltblock.b[3]<<8) | rsltblock.b[4])<<8) | rsltblock.b[5];
	encp[3] = itoa64[i&0x3f];	i >>= 6;
	encp[2] = itoa64[i&0x3f];	i >>= 6;
	encp[1] = itoa64[i&0x3f];	i >>= 6;
	encp[0] = itoa64[i];		encp += 4;
	i = ((long)((rsltblock.b[6])<<8) | rsltblock.b[7])<<2;
	encp[2] = itoa64[i&0x3f];	i >>= 6;
	encp[1] = itoa64[i&0x3f];	i >>= 6;
	encp[0] = itoa64[i];

	encp[3] = 0;

	return (cryptresult);
}

/*
 * Set up the key schedule from the key.
 */
static void
des_setkey_r(const unsigned char *key, struct crypt_data *data)
{
	register DCL_BLOCK(K, K0, K1);
	register const C_block *ptabp;
	register int i;
	C_block *ksp;

	init_des();

	PERM6464(K,K0,K1,key,PC1ROT[0]);
	ksp = &KS[0];
	STORE(K&~0x03030303L, K0&~0x03030303L, K1, *ksp);
	for (i = 1; i < numberof(KS); i++) {
		ksp++;
		STORE(K,K0,K1,*ksp);
		ptabp = PC2ROT[Rotates[i]-1][0];
		PERM6464(K,K0,K1,ksp->b,ptabp);
		STORE(K&~0x03030303L, K0&~0x03030303L, K1, *ksp);
	}
}

/*
 * Encrypt (or decrypt if num_iter < 0) the 8 chars at "in" with abs(num_iter)
 * iterations of DES, using the given 24-bit salt and the pre-computed key
 * schedule, and store the resulting 8 chars at "out" (in == out is permitted).
 *
 * NOTE: the performance of this routine is critically dependent on your
 * compiler and machine architecture.
 */
void
des_cipher_r(const unsigned char *in, unsigned char *out, long salt, int num_iter, struct crypt_data *data)
{
	/* variables that we want in registers, most important first */
#if defined(pdp11)
	register int j;
#endif
	register unsigned long L0, L1, R0, R1, k;
	register const C_block *kp;
	register int ks_inc, loop_count;
	C_block B;

	L0 = salt;
	TO_SIX_BIT(salt, L0);	/* convert to 4*(6+2) format */

#if defined(vax) || defined(pdp11)
	salt = ~salt;	/* "x &~ y" is faster than "x & y". */
#define	SALT (~salt)
#else
#define	SALT salt
#endif

#if defined(MUST_ALIGN)
	B.b[0] = in[0]; B.b[1] = in[1]; B.b[2] = in[2]; B.b[3] = in[3];
	B.b[4] = in[4]; B.b[5] = in[5]; B.b[6] = in[6]; B.b[7] = in[7];
	LOAD(L,L0,L1,B);
#else
	LOAD(L,L0,L1,*(C_block *)in);
#endif
	LOADREG(R,R0,R1,L,L0,L1);
	L0 &= 0x55555555L;
	L1 &= 0x55555555L;
	L0 = (L0 << 1) | L1;	/* L0 is the even-numbered input bits */
	R0 &= 0xaaaaaaaaL;
	R1 = (R1 >> 1) & 0x55555555L;
	L1 = R0 | R1;		/* L1 is the odd-numbered input bits */
	STORE(L,L0,L1,B);
	PERM3264(L,L0,L1,B.b,  IE3264[0]);	/* even bits */
	PERM3264(R,R0,R1,B.b+4,IE3264[0]);	/* odd bits */

	if (num_iter >= 0)
	{		/* encryption */
		kp = &KS[0];
		ks_inc  = +1;
	}
	else
	{		/* decryption */
		num_iter = -num_iter;
		kp = &KS[KS_SIZE-1];
		ks_inc  = -1;
	}

	while (--num_iter >= 0) {
		loop_count = 8;
		do {

#define	SPTAB(t, i)	(*(const unsigned long *)((const unsigned char *)(t) + (i)*(sizeof(long)/4)))
#if defined(gould)
			/* use this if B.b[i] is evaluated just once ... */
#define	DOXOR(x,y,i)	(x)^=SPTAB(SPE[0][(i)],B.b[(i)]); (y)^=SPTAB(SPE[1][(i)],B.b[(i)]);
#else
#if defined(pdp11)
			/* use this if your "long" int indexing is slow */
#define	DOXOR(x,y,i)	j=B.b[(i)]; (x)^=SPTAB(SPE[0][(i)],j); (y)^=SPTAB(SPE[1][(i)],j);
#else
			/* use this if "k" is allocated to a register ... */
#define	DOXOR(x,y,i)	k=B.b[(i)]; (x)^=SPTAB(SPE[0][(i)],k); (y)^=SPTAB(SPE[1][(i)],k);
#endif
#endif

#define	CRUNCH(p0, p1, q0, q1)	\
			k = ((q0) ^ (q1)) & SALT;	\
			B.b32.i0 = k ^ (q0) ^ kp->b32.i0;		\
			B.b32.i1 = k ^ (q1) ^ kp->b32.i1;		\
			kp += ks_inc;			\
							\
			DOXOR((p0), (p1), 0);		\
			DOXOR((p0), (p1), 1);		\
			DOXOR((p0), (p1), 2);		\
			DOXOR((p0), (p1), 3);		\
			DOXOR((p0), (p1), 4);		\
			DOXOR((p0), (p1), 5);		\
			DOXOR((p0), (p1), 6);		\
			DOXOR((p0), (p1), 7);

			CRUNCH(L0, L1, R0, R1);
			CRUNCH(R0, R1, L0, L1);
		} while (--loop_count != 0);
		kp -= (ks_inc*KS_SIZE);


		/* swap L and R */
		L0 ^= R0;  L1 ^= R1;
		R0 ^= L0;  R1 ^= L1;
		L0 ^= R0;  L1 ^= R1;
	}

	/* store the encrypted (or decrypted) result */
	L0 = ((L0 >> 3) & 0x0f0f0f0fL) | ((L1 << 1) & 0xf0f0f0f0L);
	L1 = ((R0 >> 3) & 0x0f0f0f0fL) | ((R1 << 1) & 0xf0f0f0f0L);
	STORE(L,L0,L1,B);
	PERM6464(L,L0,L1,B.b, CF6464[0]);
#if defined(MUST_ALIGN)
	STORE(L,L0,L1,B);
	out[0] = B.b[0]; out[1] = B.b[1]; out[2] = B.b[2]; out[3] = B.b[3];
	out[4] = B.b[4]; out[5] = B.b[5]; out[6] = B.b[6]; out[7] = B.b[7];
#else
	STORE(L,L0,L1,*(C_block *)out);
#endif
}

#undef des_tables
#undef KS
#undef cryptresult

#if INIT_DES
/*
 * Initialize various tables.  This need only be done once.  It could even be
 * done at compile time, if the compiler were capable of that sort of thing.
 */
STATIC void
init_des(void)
{
	register int i, j;
	register long k;
	register int tableno;
	unsigned char perm[64], tmp32[32];

	if (des_tables->ready) return;

	/*
	 * PC1ROT - bit reverse, then PC1, then Rotate, then PC2.
	 */
	for (i = 0; i < 64; i++)
		perm[i] = 0;
	for (i = 0; i < 64; i++) {
		if ((k = PC2[i]) == 0)
			continue;
		k += Rotates[0]-1;
		if ((k%28) < Rotates[0]) k -= 28;
		k = PC1[k];
		if (k > 0) {
			k--;
			k = (k|07) - (k&07);
			k++;
		}
		perm[i] = (unsigned char)k;
	}
#ifdef DEBUG
	prtab("pc1tab", perm, 8);
#endif
	init_perm(PC1ROT, perm, 8, 8);

	/*
	 * PC2ROT - PC2 inverse, then Rotate (once or twice), then PC2.
	 */
	for (j = 0; j < 2; j++) {
		unsigned char pc2inv[64];
		for (i = 0; i < 64; i++)
			perm[i] = pc2inv[i] = 0;
		for (i = 0; i < 64; i++) {
			if ((k = PC2[i]) == 0)
				continue;
			pc2inv[k-1] = i+1;
		}
		for (i = 0; i < 64; i++) {
			if ((k = PC2[i]) == 0)
				continue;
			k += j;
			if ((k%28) <= j) k -= 28;
			perm[i] = pc2inv[k];
		}
#ifdef DEBUG
		prtab("pc2tab", perm, 8);
#endif
		init_perm(PC2ROT[j], perm, 8, 8);
	}

	/*
	 * Bit reverse, then initial permutation, then expansion.
	 */
	for (i = 0; i < 8; i++) {
		for (j = 0; j < 8; j++) {
			k = (j < 2)? 0: IP[ExpandTr[i*6+j-2]-1];
			if (k > 32)
				k -= 32;
			else if (k > 0)
				k--;
			if (k > 0) {
				k--;
				k = (k|07) - (k&07);
				k++;
			}
			perm[i*8+j] = (unsigned char)k;
		}
	}
#ifdef DEBUG
	prtab("ietab", perm, 8);
#endif
	init_perm(IE3264, perm, 4, 8);

	/*
	 * Compression, then final permutation, then bit reverse.
	 */
	for (i = 0; i < 64; i++) {
		k = IP[CIFP[i]-1];
		if (k > 0) {
			k--;
			k = (k|07) - (k&07);
			k++;
		}
		perm[k-1] = i+1;
	}
#ifdef DEBUG
	prtab("cftab", perm, 8);
#endif
	init_perm(CF6464, perm, 8, 8);

	/*
	 * SPE table
	 */
	for (i = 0; i < 48; i++)
		perm[i] = P32Tr[ExpandTr[i]-1];
	for (tableno = 0; tableno < 8; tableno++) {
		for (j = 0; j < 64; j++)  {
			k = (((j >> 0) &01) << 5)|
			    (((j >> 1) &01) << 3)|
			    (((j >> 2) &01) << 2)|
			    (((j >> 3) &01) << 1)|
			    (((j >> 4) &01) << 0)|
			    (((j >> 5) &01) << 4);
			k = S[tableno][k];
			k = (((k >> 3)&01) << 0)|
			    (((k >> 2)&01) << 1)|
			    (((k >> 1)&01) << 2)|
			    (((k >> 0)&01) << 3);
			for (i = 0; i < 32; i++)
				tmp32[i] = 0;
			for (i = 0; i < 4; i++)
				tmp32[4 * tableno + i] = (unsigned char)(k >> i) & 01;
			k = 0;
			for (i = 24; --i >= 0; )
				k = (k<<1) | tmp32[perm[i]-1];
			TO_SIX_BIT(SPE[0][tableno][j], k);
			k = 0;
			for (i = 24; --i >= 0; )
				k = (k<<1) | tmp32[perm[i+24]-1];
			TO_SIX_BIT(SPE[1][tableno][j], k);
		}
	}

	des_tables->ready = 1;
}

/*
 * Initialize "perm" to represent transformation "p", which rearranges
 * (perhaps with expansion and/or contraction) one packed array of bits
 * (of size "chars_in" characters) into another array (of size "chars_out"
 * characters).
 *
 * "perm" must be all-zeroes on entry to this routine.
 */
STATIC void
init_perm(C_block perm[64/CHUNKBITS][1<<CHUNKBITS],
	  unsigned char p[64], int chars_in, int chars_out)
{
	register int i, j, k, l;

	for (k = 0; k < chars_out*8; k++) {	/* each output bit position */
		l = p[k] - 1;		/* where this bit comes from */
		if (l < 0)
			continue;	/* output bit is always 0 */
		i = l>>LGCHUNKBITS;	/* which chunk this bit comes from */
		l = 1<<(l&(CHUNKBITS-1));	/* mask for this bit */
		for (j = 0; j < (1<<CHUNKBITS); j++) {	/* each chunk value */
			if ((j & l) != 0)
				perm[i][j].b[k>>3] |= 1<<(k&07);
		}
	}
}
#endif

/*
 * "setkey" routine (for backwards compatibility)
 */
#ifdef USE_NONREENTRANT_CRYPT
void
setkey(const char *key)
{
	setkey_r(key, &default_crypt_data);
}
#endif

void
setkey_r(const char *key, struct crypt_data *data)
{
	register int i, j, k;
	C_block keyblock;

	for (i = 0; i < 8; i++) {
		k = 0;
		for (j = 0; j < 8; j++) {
			k <<= 1;
			k |= (unsigned char)*key++;
		}
		keyblock.b[i] = k;
	}
	des_setkey_r(keyblock.b, data);
}

/*
 * "encrypt" routine (for backwards compatibility)
 */
#ifdef USE_NONREENTRANT_CRYPT
void
encrypt(char *block, int flag)
{
	encrypt_r(block, flag, &default_crypt_data);
}
#endif

void
encrypt_r(char *block, int flag, struct crypt_data *data)
{
	register int i, j, k;
	C_block cblock;

	for (i = 0; i < 8; i++) {
		k = 0;
		for (j = 0; j < 8; j++) {
			k <<= 1;
			k |= (unsigned char)*block++;
		}
		cblock.b[i] = k;
	}
	des_cipher_r(cblock.b, cblock.b, 0L, (flag ? -1: 1), data);
	for (i = 7; i >= 0; i--) {
		k = cblock.b[i];
		for (j = 7; j >= 0; j--) {
			*--block = k&01;
			k >>= 1;
		}
	}
}

#ifdef DEBUG
STATIC void
prtab(const char *s, const unsigned char *t, int num_rows)
{
	register int i, j;

	(void)printf("%s:\n", s);
	for (i = 0; i < num_rows; i++) {
		for (j = 0; j < 8; j++) {
			 (void)printf("%3d", t[i*8+j]);
		}
		(void)printf("\n");
	}
	(void)printf("\n");
}
#endif

#ifdef DUMP
void
dump_block(const C_block *block)
{
	int i;
	printf("{{");
	for (i = 0; i < numberof(block->b); ++i) {
		printf("%3d,", block->b[i]);
	}
	printf("}},\n");
}

int
main(void)
{
	int i, j, k;
	init_des();

	printf("#ifndef HAVE_DES_TABLES\n\n");
	printf("/* Initial key schedule permutation */\n");
	printf("static const C_block	PC1ROT[64/CHUNKBITS][1<<CHUNKBITS] = {\n");
	for (i = 0; i < numberof(PC1ROT); ++i) {
		printf("\t{\n");
		for (j = 0; j < numberof(PC1ROT[0]); ++j) {
			printf("\t\t");
			dump_block(&PC1ROT[i][j]);
		}
		printf("\t},\n");
	}
	printf("};\n\n");

	printf("/* Subsequent key schedule rotation permutations */\n");
	printf("static const C_block	PC2ROT[2][64/CHUNKBITS][1<<CHUNKBITS] = {\n");
	for (i = 0; i < numberof(PC2ROT); ++i) {
		printf("\t{\n");
		for (j = 0; j < numberof(PC2ROT[0]); ++j) {
			printf("\t\t{\n");
			for (k = 0; k < numberof(PC2ROT[0][0]); ++k) {
				printf("\t\t\t");
				dump_block(&PC2ROT[i][j][k]);
			}
			printf("\t\t},\n");
		}
		printf("\t},\n");
	}
	printf("};\n\n");

	printf("/* Initial permutation/expansion table */\n");
	printf("static const C_block	IE3264[32/CHUNKBITS][1<<CHUNKBITS] = {\n");
	for (i = 0; i < numberof(IE3264); ++i) {
		printf("\t{\n");
		for (j = 0; j < numberof(IE3264[0]); ++j) {
			printf("\t\t");
			dump_block(&IE3264[i][j]);
		}
		printf("\t},\n");
	}
	printf("};\n\n");

	printf("/* Table that combines the S, P, and E operations.  */\n");
	printf("static const unsigned long SPE[2][8][64] = {\n");
	for (i = 0; i < numberof(SPE); ++i) {
		printf("\t{\n");
		for (j = 0; j < numberof(SPE[0]); ++j) {
			int r = 0;
			printf("\t\t{");
			for (k = 0; k < numberof(SPE[0][0]); ++k) {
				if (r == 0) printf("\n\t\t\t");
				printf("%#10lx,", SPE[i][j][k]);
				if (++r == 4) r = 0;
			}
			printf("\n\t\t},\n");
		}
		printf("\t},\n");
	}
	printf("};\n\n");

	printf("/* compressed/interleaved => final permutation table */\n");
	printf("static const C_block CF6464[64/CHUNKBITS][1<<CHUNKBITS] = {\n");
	for (i = 0; i < numberof(CF6464); ++i) {
		printf("\t{\n");
		for (j = 0; j < numberof(CF6464[0]); ++j) {
			printf("\t\t");
			dump_block(&CF6464[i][j]);
		}
		printf("\t},\n");
	}
	printf("};\n\n");
	printf("#define HAVE_DES_TABLES 1\n""#endif\n");

	return 0;
}
#endif
