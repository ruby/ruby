#ifndef SIPHASH_H
#define SIPHASH_H 1
#include <stdlib.h>
#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif
#ifdef HAVE_INTTYPES_H
#include <inttypes.h>
#endif

#ifndef HAVE_UINT64_T
typedef struct {
    uint32_t u32[2];
} sip_uint64_t;
#define uint64_t sip_uint64_t
#else
typedef uint64_t sip_uint64_t;
#endif

typedef struct {
    int c;
    int d;
    uint64_t v[4];
    uint8_t buf[sizeof(uint64_t)];
    uint8_t buflen;
    uint8_t msglen_byte;
} sip_state;

typedef struct sip_interface_st sip_interface;

typedef struct {
    sip_state state[1];
    const sip_interface *methods;
} sip_hash;

sip_hash *sip_hash_new(const uint8_t key[16], int c, int d);
sip_hash *sip_hash_init(sip_hash *h, const uint8_t key[16], int c, int d);
int sip_hash_update(sip_hash *h, const uint8_t *data, size_t len);
int sip_hash_final(sip_hash *h, uint8_t **digest, size_t *len);
int sip_hash_final_integer(sip_hash *h, uint64_t *digest);
int sip_hash_digest(sip_hash *h, const uint8_t *data, size_t data_len, uint8_t **digest, size_t *digest_len);
int sip_hash_digest_integer(sip_hash *h, const uint8_t *data, size_t data_len, uint64_t *digest);
void sip_hash_free(sip_hash *h);
void sip_hash_dump(sip_hash *h);

uint64_t sip_hash24(const uint8_t key[16], const uint8_t *data, size_t len);

#endif
