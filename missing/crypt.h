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

#ifndef CRYPT_H
#define CRYPT_H 1

/* =====  Configuration ==================== */

#ifdef CHAR_BITS
#if CHAR_BITS != 8
	#error C_block structure assumes 8 bit characters
#endif
#endif

#ifndef LONG_LONG
# if SIZEOF_LONG_LONG > 0
#   define LONG_LONG long long
# elif SIZEOF___INT64 > 0
#   define HAVE_LONG_LONG 1
#   define LONG_LONG __int64
#   undef SIZEOF_LONG_LONG
#   define SIZEOF_LONG_LONG SIZEOF___INT64
# endif
#endif

/*
 * define "LONG_IS_32_BITS" only if sizeof(long)==4.
 * This avoids use of bit fields (your compiler may be sloppy with them).
 */
#if SIZEOF_LONG == 4
#define	LONG_IS_32_BITS
#endif

/*
 * define "B64" to be the declaration for a 64 bit integer.
 * XXX this feature is currently unused, see "endian" comment below.
 */
#if SIZEOF_LONG == 8
#define	B64	long
#elif SIZEOF_LONG_LONG == 8
#define	B64	LONG_LONG
#endif

/*
 * define "LARGEDATA" to get faster permutations, by using about 72 kilobytes
 * of lookup tables.  This speeds up des_setkey() and des_cipher(), but has
 * little effect on crypt().
 */
#if defined(notdef)
#define	LARGEDATA
#endif

/* compile with "-DSTATIC=int" when profiling */
#ifndef STATIC
#define	STATIC	static
#endif

/* ==================================== */

/*
 * Cipher-block representation (Bob Baldwin):
 *
 * DES operates on groups of 64 bits, numbered 1..64 (sigh).  One
 * representation is to store one bit per byte in an array of bytes.  Bit N of
 * the NBS spec is stored as the LSB of the Nth byte (index N-1) in the array.
 * Another representation stores the 64 bits in 8 bytes, with bits 1..8 in the
 * first byte, 9..16 in the second, and so on.  The DES spec apparently has
 * bit 1 in the MSB of the first byte, but that is particularly noxious so we
 * bit-reverse each byte so that bit 1 is the LSB of the first byte, bit 8 is
 * the MSB of the first byte.  Specifically, the 64-bit input data and key are
 * converted to LSB format, and the output 64-bit block is converted back into
 * MSB format.
 *
 * DES operates internally on groups of 32 bits which are expanded to 48 bits
 * by permutation E and shrunk back to 32 bits by the S boxes.  To speed up
 * the computation, the expansion is applied only once, the expanded
 * representation is maintained during the encryption, and a compression
 * permutation is applied only at the end.  To speed up the S-box lookups,
 * the 48 bits are maintained as eight 6 bit groups, one per byte, which
 * directly feed the eight S-boxes.  Within each byte, the 6 bits are the
 * most significant ones.  The low two bits of each byte are zero.  (Thus,
 * bit 1 of the 48 bit E expansion is stored as the "4"-valued bit of the
 * first byte in the eight byte representation, bit 2 of the 48 bit value is
 * the "8"-valued bit, and so on.)  In fact, a combined "SPE"-box lookup is
 * used, in which the output is the 64 bit result of an S-box lookup which
 * has been permuted by P and expanded by E, and is ready for use in the next
 * iteration.  Two 32-bit wide tables, SPE[0] and SPE[1], are used for this
 * lookup.  Since each byte in the 48 bit path is a multiple of four, indexed
 * lookup of SPE[0] and SPE[1] is simple and fast.  The key schedule and
 * "salt" are also converted to this 8*(6+2) format.  The SPE table size is
 * 8*64*8 = 4K bytes.
 *
 * To speed up bit-parallel operations (such as XOR), the 8 byte
 * representation is "union"ed with 32 bit values "i0" and "i1", and, on
 * machines which support it, a 64 bit value "b64".  This data structure,
 * "C_block", has two problems.  First, alignment restrictions must be
 * honored.  Second, the byte-order (e.g. little-endian or big-endian) of
 * the architecture becomes visible.
 *
 * The byte-order problem is unfortunate, since on the one hand it is good
 * to have a machine-independent C_block representation (bits 1..8 in the
 * first byte, etc.), and on the other hand it is good for the LSB of the
 * first byte to be the LSB of i0.  We cannot have both these things, so we
 * currently use the "little-endian" representation and avoid any multi-byte
 * operations that depend on byte order.  This largely precludes use of the
 * 64-bit datatype since the relative order of i0 and i1 are unknown.  It
 * also inhibits grouping the SPE table to look up 12 bits at a time.  (The
 * 12 bits can be stored in a 16-bit field with 3 low-order zeroes and 1
 * high-order zero, providing fast indexing into a 64-bit wide SPE.)  On the
 * other hand, 64-bit datatypes are currently rare, and a 12-bit SPE lookup
 * requires a 128 kilobyte table, so perhaps this is not a big loss.
 *
 * Permutation representation (Jim Gillogly):
 *
 * A transformation is defined by its effect on each of the 8 bytes of the
 * 64-bit input.  For each byte we give a 64-bit output that has the bits in
 * the input distributed appropriately.  The transformation is then the OR
 * of the 8 sets of 64-bits.  This uses 8*256*8 = 16K bytes of storage for
 * each transformation.  Unless LARGEDATA is defined, however, a more compact
 * table is used which looks up 16 4-bit "chunks" rather than 8 8-bit chunks.
 * The smaller table uses 16*16*8 = 2K bytes for each transformation.  This
 * is slower but tolerable, particularly for password encryption in which
 * the SPE transformation is iterated many times.  The small tables total 9K
 * bytes, the large tables total 72K bytes.
 *
 * The transformations used are:
 * IE3264: MSB->LSB conversion, initial permutation, and expansion.
 *	This is done by collecting the 32 even-numbered bits and applying
 *	a 32->64 bit transformation, and then collecting the 32 odd-numbered
 *	bits and applying the same transformation.  Since there are only
 *	32 input bits, the IE3264 transformation table is half the size of
 *	the usual table.
 * CF6464: Compression, final permutation, and LSB->MSB conversion.
 *	This is done by two trivial 48->32 bit compressions to obtain
 *	a 64-bit block (the bit numbering is given in the "CIFP" table)
 *	followed by a 64->64 bit "cleanup" transformation.  (It would
 *	be possible to group the bits in the 64-bit block so that 2
 *	identical 32->32 bit transformations could be used instead,
 *	saving a factor of 4 in space and possibly 2 in time, but
 *	byte-ordering and other complications rear their ugly head.
 *	Similar opportunities/problems arise in the key schedule
 *	transforms.)
 * PC1ROT: MSB->LSB, PC1 permutation, rotate, and PC2 permutation.
 *	This admittedly baroque 64->64 bit transformation is used to
 *	produce the first code (in 8*(6+2) format) of the key schedule.
 * PC2ROT[0]: Inverse PC2 permutation, rotate, and PC2 permutation.
 *	It would be possible to define 15 more transformations, each
 *	with a different rotation, to generate the entire key schedule.
 *	To save space, however, we instead permute each code into the
 *	next by using a transformation that "undoes" the PC2 permutation,
 *	rotates the code, and then applies PC2.  Unfortunately, PC2
 *	transforms 56 bits into 48 bits, dropping 8 bits, so PC2 is not
 *	invertible.  We get around that problem by using a modified PC2
 *	which retains the 8 otherwise-lost bits in the unused low-order
 *	bits of each byte.  The low-order bits are cleared when the
 *	codes are stored into the key schedule.
 * PC2ROT[1]: Same as PC2ROT[0], but with two rotations.
 *	This is faster than applying PC2ROT[0] twice,
 *
 * The Bell Labs "salt" (Bob Baldwin):
 *
 * The salting is a simple permutation applied to the 48-bit result of E.
 * Specifically, if bit i (1 <= i <= 24) of the salt is set then bits i and
 * i+24 of the result are swapped.  The salt is thus a 24 bit number, with
 * 16777216 possible values.  (The original salt was 12 bits and could not
 * swap bits 13..24 with 36..48.)
 *
 * It is possible, but ugly, to warp the SPE table to account for the salt
 * permutation.  Fortunately, the conditional bit swapping requires only
 * about four machine instructions and can be done on-the-fly with about an
 * 8% performance penalty.
 */

typedef union {
	unsigned char b[8];
	struct {
#if defined(LONG_IS_32_BITS)
		/* long is often faster than a 32-bit bit field */
		long	i0;
		long	i1;
#else
		long	i0: 32;
		long	i1: 32;
#endif
	} b32;
#if defined(B64)
	B64	b64;
#endif
} C_block;

#if defined(LARGEDATA)
	/* Waste memory like crazy.  Also, do permutations in line */
#define	LGCHUNKBITS	3
#define	CHUNKBITS	(1<<LGCHUNKBITS)
#else
	/* "small data" */
#define	LGCHUNKBITS	2
#define	CHUNKBITS	(1<<LGCHUNKBITS)
#endif

struct crypt_data {
	/* The Key Schedule, filled in by des_setkey() or setkey(). */
#define	KS_SIZE	16
	C_block	KS[KS_SIZE];

	/* ==================================== */

	char	cryptresult[1+4+4+11+1];	/* encrypted result */
};

char *crypt(const char *key, const char *setting);
void setkey(const char *key);
void encrypt(char *block, int flag);

char *crypt_r(const char *key, const char *setting, struct crypt_data *data);
void setkey_r(const char *key, struct crypt_data *data);
void encrypt_r(char *block, int flag, struct crypt_data *data);

#endif /* CRYPT_H */
