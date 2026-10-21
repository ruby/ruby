/*
 * Differential fuzz: the MT19937 generator of missing/mt19937.c (compiled
 * into random.c; port unit mt19937-A-01, core_rs/src/mt19937.rs) against
 * the original C.
 *
 * FUZZ-EXTRACT: missing/mt19937.c MT_MAX_STATE:53-72 init_genrand init_by_array next_state genrand_int32
 *
 * MT_MAX_STATE:53-72 copies the period macros (N, M, MATRIX_A, TWIST, ...)
 * and the definition of struct MT that the functions need; the harness uses
 * the same struct MT for both sides, which the port mirrors with #[repr(C)].
 *
 * Exercised through the entry points random.c calls: init_genrand,
 * init_by_array and genrand_int32.  next_state (private in the port) is
 * reached through genrand_int32 whenever `left` runs out.  Every case
 * compares each generated number and then the whole struct: all 624 state
 * words, `left`, and `next` as an offset from its own `state`.
 */
#define FUZZ_UNIT "mt19937_01"
#include "ruby/ruby.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* The extracted prototypes name struct MT before its definition. */
struct MT;
#include FUZZ_REF
#include "fuzz.h"

void rs_rb_core_mt19937_init_genrand(struct MT *mt, unsigned int s);
void rs_rb_core_mt19937_init_by_array(struct MT *mt, const uint32_t init_key[], int key_length);
unsigned int rs_rb_core_mt19937_genrand_int32(struct MT *mt);

/* Longer than N, so init_by_array's first loop runs key_length times. */
#define MAXKEY 700

static struct MT c_mt, rs_mt;
static uint32_t key[MAXKEY];

static uint32_t
interesting_u32(void)
{
    switch (fuzz_below(6)) {
      case 0: return 0;
      case 1: return 0xffffffffU;
      case 2: return 0x80000000U;
      case 3: return (uint32_t)fuzz_below(16);
      case 4: return 19650218U;
      default: return (uint32_t)fuzz_next();
    }
}

/* How many numbers to draw: none, a few, and around the regeneration
 * boundaries (N, 2N). */
static long
draw_count(void)
{
    switch (fuzz_below(6)) {
      case 0: return (long)fuzz_below(4);
      case 1: return N - 1 + (long)fuzz_below(3);
      case 2: return 2 * N - 1 + (long)fuzz_below(3);
      default: return (long)fuzz_below(2 * N + 8);
    }
}

static void
compare_struct(void)
{
    int k;
    for (k = 0; k < N; k++)
        FUZZ_EQ("state word", c_mt.state[k], rs_mt.state[k]);
    FUZZ_EQ("left", c_mt.left, rs_mt.left);
    FUZZ_EQ("next offset", (long)(c_mt.next - c_mt.state), (long)(rs_mt.next - rs_mt.state));
}

static void
fuzz_one(void)
{
    uint64_t which = fuzz_below(3);
    long draws, d;

    /* The same garbage on both sides, so every write of init is compared. */
    memset(&c_mt, 0xa5, sizeof(c_mt));
    memset(&rs_mt, 0xa5, sizeof(rs_mt));

    switch (which) {
      case 0: {
        unsigned int s = interesting_u32();
        fuzz_input_num("fn init_genrand, seed", (long)s);
        ref_init_genrand(&c_mt, s);
        rs_rb_core_mt19937_init_genrand(&rs_mt, (unsigned int)fuzz_rs_long((long)s));
        break;
      }
      case 1: {
        /* key_length: 0 and negative (the C then reads init_key[0] only;
         * random.c passes a one-element array with length 0), short keys,
         * N-ish and longer than N. */
        int key_length;
        size_t nwords, i;
        const uint32_t *rs_key;
        switch (fuzz_below(5)) {
          case 0: key_length = -(int)fuzz_below(3); break;
          case 1: key_length = 1 + (int)fuzz_below(8); break;
          case 2: key_length = N - 2 + (int)fuzz_below(5); break;
          case 3: key_length = MAXKEY; break;
          default: key_length = (int)fuzz_below(MAXKEY + 1); break;
        }
        nwords = key_length > 0 ? (size_t)key_length : 1;
        for (i = 0; i < nwords; i++) key[i] = interesting_u32();
        fuzz_input_num("fn init_by_array, key_length", key_length);
        fuzz_input("key", key, nwords * sizeof(uint32_t));
        rs_key = (const uint32_t *)fuzz_rs_bytes((const unsigned char *)key, nwords * sizeof(uint32_t));
        ref_init_by_array(&c_mt, key, key_length);
        rs_rb_core_mt19937_init_by_array(&rs_mt, rs_key, key_length);
        break;
      }
      default: {
        /* An arbitrary state as random.c's marshal_load / initialize_copy
         * produce it: 1 <= left <= N and next = state + N - left + 1.  Also
         * left <= 0 (no C path creates it, but genrand_int32 then
         * regenerates without reading next), with next anywhere in state. */
        const unsigned char *rs_state;
        int left;
        long pos;
        fuzz_fill((unsigned char *)c_mt.state, sizeof(c_mt.state), NULL);
        if (fuzz_one_in(8)) {
            left = -(int)fuzz_below(1000);
            pos = (long)fuzz_below(N + 1);
        }
        else {
            left = fuzz_one_in(4) ? (fuzz_one_in(2) ? 1 : N) : 1 + (int)fuzz_below(N);
            pos = N - left + 1;
        }
        fuzz_input_num("fn genrand_int32, left", left);
        fuzz_input_num("pos", pos);
        fuzz_input("state", c_mt.state, sizeof(c_mt.state));
        rs_state = fuzz_rs_bytes((const unsigned char *)c_mt.state, sizeof(c_mt.state));
        memcpy(rs_mt.state, rs_state, sizeof(rs_mt.state));
        /* Mutation mode perturbs the Rust copy of the state only: a
         * perturbed `left` would break next == state + N - left + 1 and
         * make the C read past state[] (undefined behaviour). */
        c_mt.left = left;
        rs_mt.left = left;
        c_mt.next = c_mt.state + pos;
        rs_mt.next = rs_mt.state + pos;
        break;
      }
    }
    compare_struct();

    draws = draw_count();
    if (which == 2 && draws == 0) draws = 1;
    for (d = 0; d < draws; d++) {
        unsigned int c_y = ref_genrand_int32(&c_mt);
        unsigned int rs_y = rs_rb_core_mt19937_genrand_int32(&rs_mt);
        FUZZ_EQ("genrand_int32", c_y, rs_y);
        if (fuzz_case_failed) break;
    }
    compare_struct();
}
