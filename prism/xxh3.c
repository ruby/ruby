/**
 * An implementation of the XXH3 hash function.
 *
 * The reason some of these names do not look quite like the style of the rest
 * of the code in Prism is that this was adapted straight from the XXH3
 * specification here:
 *
 * https://github.com/Cyan4973/xxHash/blob/release/doc/xxhash_spec.md
 *
 * To better understand this code it is recommended to read the XXH3
 * specification linked above, where you should be able to follow along with
 * this implementation more easily. Note this only implements the XXH3_64
 * variant with the default secret and a seed of 0. Additionally it does not
 * include a lot of the various CPU-specific optimizations that exist in the
 * reference implementation.
 */

#include "prism/internal/xxh3.h"

#include "prism/compiler/accel.h"
#include "prism/compiler/bswap.h"
#include "prism/compiler/endianness.h"

#include <string.h>

#if defined(PRISM_HAS_NEON) && defined(PRISM_LITTLE_ENDIAN_COMPTIME)
    #include <arm_neon.h>
    #define XXH3_NEON
#elif defined(PRISM_HAS_SSE2)
    #include <emmintrin.h>
    #define XXH3_SSE2
#endif

#if defined(__SIZEOF_INT128__)
static uint64_t
XXH3_mul128_fold64(uint64_t lhs, uint64_t rhs) {
    __uint128_t x = (__uint128_t) lhs * (__uint128_t) rhs;
    return ((uint64_t) (x & 0xFFFFFFFFFFFFFFFFULL)) ^ ((uint64_t) (x >> 64));
}
#else
#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_ARM64))
#include <intrin.h>
#endif

static uint64_t
XXH3_mul128_fold64(uint64_t lhs, uint64_t rhs) {
    uint64_t lo, hi;
#if defined(_MSC_VER) && defined(_M_X64)
    lo = _umul128(lhs, rhs, &hi);
#elif defined(_MSC_VER) && defined(_M_ARM64)
    hi = __umulh(lhs, rhs);
    lo = lhs * rhs;
#else
    uint64_t lo_lo = (lhs & 0xFFFFFFFF) * (rhs & 0xFFFFFFFF);
    uint64_t hi_lo = (lhs >> 32) * (rhs & 0xFFFFFFFF);
    uint64_t lo_hi = (lhs & 0xFFFFFFFF) * (rhs >> 32);
    uint64_t hi_hi = (lhs >> 32) * (rhs >> 32);

    uint64_t cross = (lo_lo >> 32) + (hi_lo & 0xFFFFFFFF) + lo_hi;
    hi = hi_hi + (hi_lo >> 32) + (cross >> 32);
    lo = (cross << 32) | (lo_lo & 0xFFFFFFFF);
#endif
    return lo ^ hi;
}
#endif

static uint32_t
read32(const void* ptr) {
    uint32_t val;
    memcpy(&val, ptr, sizeof(val));
    if (!PRISM_LITTLE_ENDIAN_RUNTIME) {
        val = pm_bswap32(val);
    }
    return val;
}

static uint64_t
read64(const void* ptr) {
    uint64_t val;
    memcpy(&val, ptr, sizeof(val));
    if (!PRISM_LITTLE_ENDIAN_RUNTIME) {
        val = pm_bswap64(val);
    }
    return val;
}

static const uint64_t PRIME32_1 = 0x9E3779B1U;
static const uint64_t PRIME32_2 = 0x85EBCA77U;
static const uint64_t PRIME32_3 = 0xC2B2AE3DU;
static const uint64_t PRIME64_1 = 0x9E3779B185EBCA87ULL;
static const uint64_t PRIME64_2 = 0xC2B2AE3D27D4EB4FULL;
static const uint64_t PRIME64_3 = 0x165667B19E3779F9ULL;
static const uint64_t PRIME64_4 = 0x85EBCA77C2B2AE63ULL;
static const uint64_t PRIME64_5 = 0x27D4EB2F165667C5ULL;
static const uint64_t PRIME_MX1 = 0x165667919E3779F9ULL;
static const uint64_t PRIME_MX2 = 0x9FB21C651E98DF25ULL;

static const uint8_t secret[192] = {
    0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe, 0x7c, 0x01, 0x81, 0x2c, 0xf7, 0x21, 0xad, 0x1c,
    0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb, 0x72, 0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f,
    0xcb, 0x79, 0xe6, 0x4e, 0xcc, 0xc0, 0xe5, 0x78, 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21,
    0xb8, 0x08, 0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e, 0xe0, 0x35, 0x90, 0xe6, 0x81, 0x3a, 0x26, 0x4c,
    0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb, 0x88, 0xd0, 0x65, 0x8b, 0x1b, 0x53, 0x2e, 0xa3,
    0x71, 0x64, 0x48, 0x97, 0xa2, 0x0d, 0xf9, 0x4e, 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8,
    0xa8, 0xfa, 0x76, 0x3f, 0xe3, 0x9c, 0x34, 0x3f, 0xf9, 0xdc, 0xbb, 0xc7, 0xc7, 0x0b, 0x4f, 0x1d,
    0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31, 0xc8, 0x9f, 0x7e, 0xc9, 0xd9, 0x78, 0x73, 0x64,
    0xea, 0xc5, 0xac, 0x83, 0x34, 0xd3, 0xeb, 0xc3, 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb,
    0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0, 0xda, 0x49, 0xd3, 0x16, 0x55, 0x26, 0x29, 0xd4, 0x68, 0x9e,
    0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc, 0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31, 0xce,
    0x45, 0xcb, 0x3a, 0x8f, 0x95, 0x16, 0x04, 0x28, 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e,
};

static uint64_t
avalanche(uint64_t x) {
    x ^= (x >> 37);
    x *= PRIME_MX1;
    x ^= (x >> 32);
    return x;
}

static uint64_t
avalanche_XXH64(uint64_t x) {
    x ^= (x >> 33);
    x *= PRIME64_2;
    x ^= (x >> 29);
    x *= PRIME64_3;
    x ^= (x >> 32);
    return x;
}

static uint64_t
XXH3_64_empty(void) {
    return avalanche_XXH64(read64(secret + 56) ^ read64(secret + 64));
}

static uint64_t
XXH3_64_1to3(const uint8_t *input, size_t length) {
    uint32_t combined = (uint32_t) input[length - 1] | ((uint32_t) length << 8) | ((uint32_t) input[0] << 16) | ((uint32_t) input[length >> 1] << 24);
    return avalanche_XXH64((uint64_t) (read32(secret) ^ read32(secret + 4)) ^ (uint64_t) combined);
}

static uint64_t
XXH3_64_4to8(const uint8_t *input, size_t length) {
#define rot(x_, r_) (((x_) << (r_)) | ((x_) >> (64 - (r_))))

    uint64_t combined = (uint64_t) read32(input + length - 4) | ((uint64_t) read32(input) << 32);
    uint64_t value = (read64(secret + 8) ^ read64(secret + 16)) ^ combined;
    value ^= rot(value, 49) ^ rot(value, 24);
    value *= PRIME_MX2;
    value ^= ((value >> 35) + length);
    value *= PRIME_MX2;
    value ^= (value >> 28);
    return value;

#undef rot
}

static uint64_t
XXH3_64_9to16(const uint8_t *input, size_t length) {
    uint64_t lo = (read64(secret + 24) ^ read64(secret + 32)) ^ read64(input);
    uint64_t hi = (read64(secret + 40) ^ read64(secret + 48)) ^ read64(input + length - 8);
    return avalanche(length + pm_bswap64(lo) + hi + XXH3_mul128_fold64(lo, hi));
}

static uint64_t
XXH3_64_17to240(const uint8_t *input, size_t length) {
#define mix(data_, offset_) XXH3_mul128_fold64(read64((data_)) ^ read64(secret + (offset_)), read64((data_) + 8) ^ read64(secret + (offset_) + 8))

    uint64_t acc = length * PRIME64_1;

    if (length <= 128) {
        size_t idx = (length - 1) / 32;
        do {
            acc += mix(input + idx * 16, idx * 32) + mix(input + length - idx * 16 - 16, idx * 32 + 16);
        } while (idx--);
    } else {
        for (size_t idx = 0; idx < 8; idx++) {
            acc += mix(input + idx * 16, idx * 16);
        }
        acc = avalanche(acc);
        for (size_t idx = 8; idx < length >> 4; idx++) {
            acc += mix(input + idx * 16, (idx - 8) * 16 + 3);
        }
        acc += mix(input + length - 16, 119);
    }

    return avalanche(acc);

#undef mix
}

static void
accumulate(uint64_t acc[8], const uint8_t *stripe, size_t secret_offset) {
#if defined(XXH3_NEON)
    for (int idx = 0; idx < 8; idx += 2) {
        uint64x2_t data = vreinterpretq_u64_u8(vld1q_u8(stripe + 8 * idx));
        uint64x2_t value = veorq_u64(data, vreinterpretq_u64_u8(vld1q_u8(secret + secret_offset + 8 * idx)));
        uint64x2_t product = vmull_u32(vmovn_u64(value), vshrn_n_u64(value, 32));
        vst1q_u64(acc + idx, vaddq_u64(vld1q_u64(acc + idx), vaddq_u64(vextq_u64(data, data, 1), product)));
    }
#elif defined(XXH3_SSE2)
    for (int idx = 0; idx < 8; idx += 2) {
        __m128i data = _mm_loadu_si128((const __m128i *) (stripe + 8 * idx));
        __m128i value = _mm_xor_si128(data, _mm_loadu_si128((const __m128i *) (secret + secret_offset + 8 * idx)));
        __m128i product = _mm_mul_epu32(value, _mm_shuffle_epi32(value, _MM_SHUFFLE(0, 3, 0, 1)));
        _mm_storeu_si128((__m128i *) (acc + idx), _mm_add_epi64(_mm_loadu_si128((const __m128i *) (acc + idx)), _mm_add_epi64(_mm_shuffle_epi32(data, _MM_SHUFFLE(1, 0, 3, 2)), product)));
    }
#else
    for (int idx = 0; idx < 8; idx++) {
        uint64_t data = read64(stripe + 8 * idx);
        uint64_t value = data ^ read64(secret + secret_offset + 8 * idx);
        acc[idx ^ 1] = acc[idx ^ 1] + data;
        acc[idx] += (value & 0xFFFFFFFF) * (value >> 32);
    }
#endif
}

static uint64_t
XXH3_64_large(const uint8_t *input, size_t length) {
    const size_t secret_length = sizeof(secret);
    const size_t stripes_per_block = (secret_length - 64) / 8;
    const size_t block_size = 64 * stripes_per_block;
    const size_t block_count = (length - 1) / block_size;
    const size_t last_offset = block_count * block_size;

    uint64_t acc[8] = {
        PRIME32_3, PRIME64_1, PRIME64_2, PRIME64_3,
        PRIME64_4, PRIME32_2, PRIME64_5, PRIME32_1
    };

    for (size_t block_idx = 0; block_idx < block_count; block_idx++) {
        const uint8_t *block = input + block_idx * block_size;

        for (size_t stripe_idx = 0; stripe_idx < stripes_per_block; stripe_idx++) {
            accumulate(acc, block + stripe_idx * 64, stripe_idx * 8);
        }

#if defined(XXH3_NEON)
        const uint32x2_t prime = vdup_n_u32((uint32_t) PRIME32_1);
        for (size_t idx = 0; idx < 8; idx += 2) {
            uint64x2_t value = vld1q_u64(acc + idx);
            value = veorq_u64(value, vshrq_n_u64(value, 47));
            value = veorq_u64(value, vreinterpretq_u64_u8(vld1q_u8(secret + secret_length - 64 + idx * 8)));
            vst1q_u64(acc + idx, vaddq_u64(vmull_u32(vmovn_u64(value), prime), vshlq_n_u64(vmull_u32(vshrn_n_u64(value, 32), prime), 32)));
        }
#elif defined(XXH3_SSE2)
        const __m128i prime = _mm_set1_epi32((int) (uint32_t) PRIME32_1);
        for (size_t idx = 0; idx < 8; idx += 2) {
            __m128i value = _mm_loadu_si128((const __m128i *) (acc + idx));
            value = _mm_xor_si128(value, _mm_srli_epi64(value, 47));
            value = _mm_xor_si128(value, _mm_loadu_si128((const __m128i *) (secret + secret_length - 64 + idx * 8)));
            _mm_storeu_si128((__m128i *) (acc + idx), _mm_add_epi64(_mm_mul_epu32(value, prime), _mm_slli_epi64(_mm_mul_epu32(_mm_shuffle_epi32(value, _MM_SHUFFLE(0, 3, 0, 1)), prime), 32)));
        }
#else
        for (size_t idx = 0; idx < 8; idx++) {
            acc[idx] ^= (acc[idx] >> 47);
            acc[idx] ^= read64(secret + secret_length - 64 + idx * 8);
            acc[idx] *= PRIME32_1;
        }
#endif
    }

    for (size_t stripe_idx = 0; stripe_idx < (length - last_offset - 1) / 64; stripe_idx++) {
        accumulate(acc, input + last_offset + stripe_idx * 64, stripe_idx * 8);
    }

    accumulate(acc, input + length - 64, secret_length - 71);

    uint64_t result = (uint64_t) length * PRIME64_1;
    for (size_t idx = 0; idx < 4; idx++) {
        result += XXH3_mul128_fold64(acc[idx * 2] ^ read64(secret + 11 + 16 * idx), acc[idx * 2 + 1] ^ read64(secret + 11 + 16 * idx + 8));
    }

    return avalanche(result);
}

uint64_t
pm_xxh3(const uint8_t *input, size_t length) {
    if (length == 0) {
        return XXH3_64_empty();
    } else if (length <= 3) {
        return XXH3_64_1to3(input, length);
    } else if (length <= 8) {
        return XXH3_64_4to8(input, length);
    } else if (length <= 16) {
        return XXH3_64_9to16(input, length);
    } else if (length <= 240) {
        return XXH3_64_17to240(input, length);
    } else {
        return XXH3_64_large(input, length);
    }
}
