/*
 * Differential fuzz: io_buffer.c in-place mask operations and bit count
 * (port unit io_buffer-A-03, core_rs/src/io_buffer.rs) against the
 * original C.
 *
 * FUZZ-EXTRACT: io_buffer.c memory_or_inplace memory_xor_inplace memory_not_inplace memory_bit_count
 *
 * memory_or_inplace / memory_xor_inplace apply the mask cyclically
 * (mask[offset % mask_size]); the harness draws masks shorter than, equal
 * to and longer than the buffer, including length 1, and buffers of length
 * 0.  memory_bit_count counts whole 8-byte words and then the tail; the
 * harness draws every length 0..MAXCOUNT (every tail length 0..7, zero and
 * several words) at every alignment 0..7, since the C reads the words
 * through a possibly unaligned uint64_t pointer.
 *
 * Preconditions honoured (as the C callers guarantee): mask_size > 0
 * (io_buffer_check_mask_size), and the buffer and mask do not overlap
 * (restrict; io_buffer_check_overlaps).
 */
#define FUZZ_UNIT "io_buffer_03"
#include "ruby/ruby.h"
#include "internal/bits.h"
#include <string.h>
#include FUZZ_REF
#include "fuzz.h"

void rs_rb_core_io_buffer_memory_or_inplace(unsigned char * restrict base, size_t size, unsigned char * restrict mask, size_t mask_size);
void rs_rb_core_io_buffer_memory_xor_inplace(unsigned char * restrict base, size_t size, unsigned char * restrict mask, size_t mask_size);
void rs_rb_core_io_buffer_memory_not_inplace(unsigned char * restrict base, size_t size);
size_t rs_rb_core_io_buffer_memory_bit_count(const unsigned char *base, size_t size);

#define MAXLEN 64
#define MAXMASK 80
#define MAXCOUNT 200
#define SLACK 16

/* Bytes with interesting bit patterns; fuzz_fill() adds any byte 1/8. */
static const char alphabet[] = "\xff\x01\x80\x7f\x0f\xf0\x55\xaa\xfe";

static void
fuzz_one(void)
{
    uint64_t which = fuzz_below(4);

    if (which <= 2) {
        /* Buffers are followed by SLACK sentinel bytes on both sides; all
         * of them are compared, so a write past `size` is a mismatch. */
        unsigned char in[MAXLEN], mask[MAXMASK];
        unsigned char c_base[MAXLEN + SLACK], rs_base[MAXLEN + SLACK];
        unsigned char c_mask[MAXMASK + SLACK], rs_mask[MAXMASK + SLACK];
        size_t len = fuzz_len(MAXLEN), mask_len = 0, k;

        fuzz_fill(in, len, alphabet);
        memset(c_base, 0xa5, sizeof(c_base));
        memset(rs_base, 0xa5, sizeof(rs_base));
        memcpy(c_base, in, len);
        memcpy(rs_base, fuzz_rs_bytes(in, len), len);
        fuzz_input("base", in, len);

        if (which < 2) {
            switch (fuzz_below(4)) {
              case 0: mask_len = 1; break;
              case 1: mask_len = len ? len : 1; break;
              default: mask_len = 1 + (size_t)fuzz_below(MAXMASK); break;
            }
            fuzz_fill(mask, mask_len, alphabet);
            memset(c_mask, 0x3c, sizeof(c_mask));
            memset(rs_mask, 0x3c, sizeof(rs_mask));
            memcpy(c_mask, mask, mask_len);
            memcpy(rs_mask, fuzz_rs_bytes_slot(1, mask, mask_len), mask_len);
            fuzz_input("mask", mask, mask_len);
        }

        switch (which) {
          case 0:
            fuzz_input_num("fn or_inplace", 0);
            ref_memory_or_inplace(c_base, len, c_mask, mask_len);
            rs_rb_core_io_buffer_memory_or_inplace(rs_base, len, rs_mask, mask_len);
            break;
          case 1:
            fuzz_input_num("fn xor_inplace", 1);
            ref_memory_xor_inplace(c_base, len, c_mask, mask_len);
            rs_rb_core_io_buffer_memory_xor_inplace(rs_base, len, rs_mask, mask_len);
            break;
          default:
            fuzz_input_num("fn not_inplace", 2);
            ref_memory_not_inplace(c_base, len);
            rs_rb_core_io_buffer_memory_not_inplace(rs_base, len);
            break;
        }

        for (k = 0; k < sizeof(c_base); k++)
            FUZZ_EQ("base byte", c_base[k], rs_base[k]);
        if (which < 2) {
            for (k = 0; k < sizeof(c_mask); k++)
                FUZZ_EQ("mask byte", c_mask[k], rs_mask[k]);
        }
    }
    else {
        /* memory_bit_count: any length at any alignment.  The storage is
         * 8-aligned so `align` is the real misalignment of the pointer. */
        union { uint64_t words[(MAXCOUNT + 8 + 7) / 8]; unsigned char bytes[MAXCOUNT + 8]; } c_buf, rs_buf;
        unsigned char in[MAXCOUNT];
        size_t len, align = (size_t)fuzz_below(8);
        size_t c_r, rs_r;

        len = fuzz_one_in(2) ? fuzz_len(MAXCOUNT) : (size_t)fuzz_below(25);
        fuzz_fill(in, len, alphabet);
        memset(&c_buf, 0, sizeof(c_buf));
        memset(&rs_buf, 0, sizeof(rs_buf));
        memcpy(c_buf.bytes + align, in, len);
        memcpy(rs_buf.bytes + align, fuzz_rs_bytes(in, len), len);
        fuzz_input("bytes", in, len);
        fuzz_input_num("align", (long)align);
        fuzz_input_num("fn bit_count", 3);

        c_r = ref_memory_bit_count(c_buf.bytes + align, len);
        rs_r = rs_rb_core_io_buffer_memory_bit_count(rs_buf.bytes + align, len);
        FUZZ_EQ("bit_count", c_r, rs_r);
    }
}
