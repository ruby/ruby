#include <string.h>
#include <stdio.h>
#include "siphash.h"
#ifndef SIP_HASH_STREAMING
  #define SIP_HASH_STREAMING 1
#endif

#ifdef _WIN32
  #define BYTE_ORDER __LITTLE_ENDIAN
#elif !defined BYTE_ORDER
  #include <endian.h>
#endif
#ifndef LITTLE_ENDIAN
#define LITTLE_ENDIAN __LITTLE_ENDIAN
#endif
#ifndef BIG_ENDIAN
#define BIG_ENDIAN __BIG_ENDIAN
#endif

#if BYTE_ORDER == LITTLE_ENDIAN
  #define lo u32[0]
  #define hi u32[1]
#elif BYTE_ORDER == BIG_ENDIAN
  #define hi u32[0]
  #define lo u32[1]
#else
  #error "Only strictly little or big endian supported"
#endif

#ifndef UNALIGNED_WORD_ACCESS
# if defined(__i386) || defined(__i386__) || defined(_M_IX86) || \
     defined(__x86_64) || defined(__x86_64__) || defined(_M_AMD86) || \
     defined(__mc68020__)
#   define UNALIGNED_WORD_ACCESS 1
# endif
#endif
#ifndef UNALIGNED_WORD_ACCESS
# define UNALIGNED_WORD_ACCESS 0
#endif

#define U8TO32_LE(p)         						\
    (((uint32_t)((p)[0])       ) | ((uint32_t)((p)[1]) <<  8) |  	\
     ((uint32_t)((p)[2]) <<  16) | ((uint32_t)((p)[3]) << 24))		\

#define U32TO8_LE(p, v)			\
do {					\
    (p)[0] = (uint8_t)((v)      );	\
    (p)[1] = (uint8_t)((v) >>  8); 	\
    (p)[2] = (uint8_t)((v) >> 16);	\
    (p)[3] = (uint8_t)((v) >> 24);	\
} while (0)

#ifdef HAVE_UINT64_T
#define U8TO64_LE(p) 							\
    ((uint64_t)U8TO32_LE(p) | ((uint64_t)U8TO32_LE((p) + 4)) << 32 )

#define U64TO8_LE(p, v) \
do {						\
    U32TO8_LE((p),     (uint32_t)((v)      )); 	\
    U32TO8_LE((p) + 4, (uint32_t)((v) >> 32));	\
} while (0)

#define ROTL64(v, s)			\
    ((v) << (s)) | ((v) >> (64 - (s)))

#define ROTL64_TO(v, s) ((v) = ROTL64((v), (s)))

#define ADD64_TO(v, s) ((v) += (s))
#define XOR64_TO(v, s) ((v) ^= (s))
#define XOR64_INT(v, x) ((v) ^= (x))
#else
#define U8TO64_LE(p) u8to64_le(p)
static inline uint64_t
u8to64_le(const uint8_t *p)
{
    uint64_t ret;
    ret.lo = U8TO32_LE(p);
    ret.hi = U8TO32_LE(p + 4);
    return ret;
}

#define U64TO8_LE(p, v) u64to8_le(p, v)
static inline void
u64to8_le(uint8_t *p, uint64_t v)
{
    U32TO8_LE(p,     v.lo);
    U32TO8_LE(p + 4, v.hi);
}

#define ROTL64_TO(v, s) ((s) > 32 ? rotl64_swap(rotl64_to(&(v), (s) - 32)) : \
			 (s) == 32 ? rotl64_swap(&(v)) : rotl64_to(&(v), (s)))
static inline uint64_t *
rotl64_to(uint64_t *v, unsigned int s)
{
    uint32_t uhi = (v->hi << s) | (v->lo >> (32 - s));
    uint32_t ulo = (v->lo << s) | (v->hi >> (32 - s));
    v->hi = uhi;
    v->lo = ulo;
    return v;
}

static inline uint64_t *
rotl64_swap(uint64_t *v)
{
    uint32_t t = v->lo;
    v->lo = v->hi;
    v->hi = t;
    return v;
}

#define ADD64_TO(v, s) add64_to(&(v), (s))
static inline uint64_t *
add64_to(uint64_t *v, const uint64_t s)
{
    v->lo += s.lo;
    v->hi += s.hi;
    if (v->lo < s.lo) v->hi++;
    return v;
}

#define XOR64_TO(v, s) xor64_to(&(v), (s))
static inline uint64_t *
xor64_to(uint64_t *v, const uint64_t s)
{
    v->lo ^= s.lo;
    v->hi ^= s.hi;
    return v;
}

#define XOR64_INT(v, x) ((v).lo ^= (x))
#endif

static const union {
    char bin[32];
    uint64_t u64[4];
} sip_init_state_bin = {"uespemos""modnarod""arenegyl""setybdet"};
#define sip_init_state sip_init_state_bin.u64

#if SIP_HASH_STREAMING
struct sip_interface_st {
    void (*init)(sip_state *s, const uint8_t *key);
    void (*update)(sip_state *s, const uint8_t *data, size_t len);
    void (*final)(sip_state *s, uint64_t *digest);
};

static void int_sip_init(sip_state *state, const uint8_t *key);
static void int_sip_update(sip_state *state, const uint8_t *data, size_t len);
static void int_sip_final(sip_state *state, uint64_t *digest);

static const sip_interface sip_methods = {
    int_sip_init,
    int_sip_update,
    int_sip_final
};
#endif /* SIP_HASH_STREAMING */

#define SIP_COMPRESS(v0, v1, v2, v3)	\
do {					\
    ADD64_TO((v0), (v1));		\
    ADD64_TO((v2), (v3));		\
    ROTL64_TO((v1), 13);		\
    ROTL64_TO((v3), 16);		\
    XOR64_TO((v1), (v0));		\
    XOR64_TO((v3), (v2));		\
    ROTL64_TO((v0), 32);		\
    ADD64_TO((v2), (v1));		\
    ADD64_TO((v0), (v3));		\
    ROTL64_TO((v1), 17);		\
    ROTL64_TO((v3), 21);		\
    XOR64_TO((v1), (v2));		\
    XOR64_TO((v3), (v0));		\
    ROTL64_TO((v2), 32);		\
} while(0)

#if SIP_HASH_STREAMING
static void
int_sip_dump(sip_state *state)
{
    int v;

    for (v = 0; v < 4; v++) {
#if HAVE_UINT64_T
	printf("v%d: %" PRIx64 "\n", v, state->v[v]);
#else
	printf("v%d: %" PRIx32 "%.8" PRIx32 "\n", v, state->v[v].hi, state->v[v].lo);
#endif
    }
}

static void
int_sip_init(sip_state *state, const uint8_t key[16])
{
    uint64_t k0, k1;

    k0 = U8TO64_LE(key);
    k1 = U8TO64_LE(key + sizeof(uint64_t));

    state->v[0] = k0; XOR64_TO(state->v[0], sip_init_state[0]);
    state->v[1] = k1; XOR64_TO(state->v[1], sip_init_state[1]);
    state->v[2] = k0; XOR64_TO(state->v[2], sip_init_state[2]);
    state->v[3] = k1; XOR64_TO(state->v[3], sip_init_state[3]);
}

static inline void
int_sip_round(sip_state *state, int n)
{
    int i;

    for (i = 0; i < n; i++) {
	SIP_COMPRESS(state->v[0], state->v[1], state->v[2], state->v[3]);
    }
}

static inline void
int_sip_update_block(sip_state *state, uint64_t m)
{
    XOR64_TO(state->v[3], m);
    int_sip_round(state, state->c);
    XOR64_TO(state->v[0], m);
}

static inline void
int_sip_pre_update(sip_state *state, const uint8_t **pdata, size_t *plen)
{
    int to_read;
    uint64_t m;

    if (!state->buflen) return;

    to_read = sizeof(uint64_t) - state->buflen;
    memcpy(state->buf + state->buflen, *pdata, to_read);
    m = U8TO64_LE(state->buf);
    int_sip_update_block(state, m);
    *pdata += to_read;
    *plen -= to_read;
    state->buflen = 0;
}

static inline void
int_sip_post_update(sip_state *state, const uint8_t *data, size_t len)
{
    uint8_t r = len % sizeof(uint64_t);
    if (r) {
	memcpy(state->buf, data + len - r, r);
	state->buflen = r;
    }
}

static void
int_sip_update(sip_state *state, const uint8_t *data, size_t len)
{
    uint64_t *end;
    uint64_t *data64;

    state->msglen_byte = state->msglen_byte + (len % 256);
    data64 = (uint64_t *) data;

    int_sip_pre_update(state, &data, &len);

    end = data64 + (len / sizeof(uint64_t));

#if BYTE_ORDER == LITTLE_ENDIAN
    while (data64 != end) {
	int_sip_update_block(state, *data64++);
    }
#elif BYTE_ORDER == BIG_ENDIAN
    {
	uint64_t m;
	uint8_t *data8 = data;
	for (; data8 != (uint8_t *) end; data8 += sizeof(uint64_t)) {
	    m = U8TO64_LE(data8);
	    int_sip_update_block(state, m);
	}
    }
#endif

    int_sip_post_update(state, data, len);
}

static inline void
int_sip_pad_final_block(sip_state *state)
{
    int i;
    /* pad with 0's and finalize with msg_len mod 256 */
    for (i = state->buflen; i < sizeof(uint64_t); i++) {
	state->buf[i] = 0x00;
    }
    state->buf[sizeof(uint64_t) - 1] = state->msglen_byte;
}

static void
int_sip_final(sip_state *state, uint64_t *digest)
{
    uint64_t m;

    int_sip_pad_final_block(state);

    m = U8TO64_LE(state->buf);
    int_sip_update_block(state, m);

    XOR64_INT(state->v[2], 0xff);

    int_sip_round(state, state->d);

    *digest = state->v[0];
    XOR64_TO(*digest, state->v[1]);
    XOR64_TO(*digest, state->v[2]);
    XOR64_TO(*digest, state->v[3]);
}

sip_hash *
sip_hash_new(const uint8_t key[16], int c, int d)
{
    sip_hash *h = NULL;

    if (!(h = (sip_hash *) malloc(sizeof(sip_hash)))) return NULL;
    return sip_hash_init(h, key, c, d);
}

sip_hash *
sip_hash_init(sip_hash *h, const uint8_t key[16], int c, int d)
{
    h->state->c = c;
    h->state->d = d;
    h->state->buflen = 0;
    h->state->msglen_byte = 0;
    h->methods = &sip_methods;
    h->methods->init(h->state, key);
    return h;
}

int
sip_hash_update(sip_hash *h, const uint8_t *msg, size_t len)
{
    h->methods->update(h->state, msg, len);
    return 1;
}

int
sip_hash_final(sip_hash *h, uint8_t **digest, size_t* len)
{
    uint64_t digest64;
    uint8_t *ret;

    h->methods->final(h->state, &digest64);
    if (!(ret = (uint8_t *)malloc(sizeof(uint64_t)))) return 0;
    U64TO8_LE(ret, digest64);
    *len = sizeof(uint64_t);
    *digest = ret;

    return 1;
}

int
sip_hash_final_integer(sip_hash *h, uint64_t *digest)
{
    h->methods->final(h->state, digest);
    return 1;
}

int
sip_hash_digest(sip_hash *h, const uint8_t *data, size_t data_len, uint8_t **digest, size_t *digest_len)
{
    if (!sip_hash_update(h, data, data_len)) return 0;
    return sip_hash_final(h, digest, digest_len);
}

int
sip_hash_digest_integer(sip_hash *h, const uint8_t *data, size_t data_len, uint64_t *digest)
{
    if (!sip_hash_update(h, data, data_len)) return 0;
    return sip_hash_final_integer(h, digest);
}

void
sip_hash_free(sip_hash *h)
{
    free(h);
}

void
sip_hash_dump(sip_hash *h)
{
    int_sip_dump(h->state);
}
#endif /* SIP_HASH_STREAMING */

#define SIP_2_ROUND(m, v0, v1, v2, v3)	\
do {					\
    XOR64_TO((v3), (m));		\
    SIP_COMPRESS(v0, v1, v2, v3);	\
    SIP_COMPRESS(v0, v1, v2, v3);	\
    XOR64_TO((v0), (m));		\
} while (0)

uint64_t
sip_hash24(const uint8_t key[16], const uint8_t *data, size_t len)
{
    uint64_t k0, k1;
    uint64_t v0, v1, v2, v3;
    uint64_t m, last;
    const uint8_t *end = data + len - (len % sizeof(uint64_t));

    k0 = U8TO64_LE(key);
    k1 = U8TO64_LE(key + sizeof(uint64_t));

    v0 = k0; XOR64_TO(v0, sip_init_state[0]);
    v1 = k1; XOR64_TO(v1, sip_init_state[1]);
    v2 = k0; XOR64_TO(v2, sip_init_state[2]);
    v3 = k1; XOR64_TO(v3, sip_init_state[3]);

#if BYTE_ORDER == LITTLE_ENDIAN && UNALIGNED_WORD_ACCESS
    {
        uint64_t *data64 = (uint64_t *)data;
        while (data64 != (uint64_t *) end) {
	    m = *data64++;
	    SIP_2_ROUND(m, v0, v1, v2, v3);
        }
    }
#elif BYTE_ORDER == BIG_ENDIAN
    for (; data != end; data += sizeof(uint64_t)) {
	m = U8TO64_LE(data);
	SIP_2_ROUND(m, v0, v1, v2, v3);
    }
#endif

#ifdef HAVE_UINT64_T
    last = (uint64_t)len << 56;
#define OR_BYTE(n) (last |= ((uint64_t) end[n]) << ((n) * 8))
#else
    last.hi = len << 24;
    last.lo = 0;
#define OR_BYTE(n) do { \
	if (n >= 4) \
	    last.hi |= ((uint32_t) end[n]) << ((n) >= 4 ? (n) * 8 - 32 : 0); \
	else \
	    last.lo |= ((uint32_t) end[n]) << ((n) >= 4 ? 0 : (n) * 8); \
    } while (0)
#endif

    switch (len % sizeof(uint64_t)) {
	case 7:
	    OR_BYTE(6);
	case 6:
	    OR_BYTE(5);
	case 5:
	    OR_BYTE(4);
	case 4:
#if BYTE_ORDER == LITTLE_ENDIAN && UNALIGNED_WORD_ACCESS
  #if HAVE_UINT64_T
	    last |= (uint64_t) ((uint32_t *) end)[0];
  #else
	    last.lo |= ((uint32_t *) end)[0];
  #endif
	    break;
#elif BYTE_ORDER == BIG_ENDIAN
	    OR_BYTE(3);
#endif
	case 3:
	    OR_BYTE(2);
	case 2:
	    OR_BYTE(1);
	case 1:
	    OR_BYTE(0);
	    break;
	case 0:
	    break;
    }

    SIP_2_ROUND(last, v0, v1, v2, v3);

    XOR64_INT(v2, 0xff);

    SIP_COMPRESS(v0, v1, v2, v3);
    SIP_COMPRESS(v0, v1, v2, v3);
    SIP_COMPRESS(v0, v1, v2, v3);
    SIP_COMPRESS(v0, v1, v2, v3);

    XOR64_TO(v0, v1);
    XOR64_TO(v0, v2);
    XOR64_TO(v0, v3);
    return v0;
}
