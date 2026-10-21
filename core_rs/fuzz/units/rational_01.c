/*
 * Differential fuzz: rational.c fixnum GCD and string-scanner helpers
 * (port unit rational-A-01, core_rs/src/rational.rs) against the original C.
 *
 * FUZZ-EXTRACT: rational.c i_gcd issign read_sign islettere isletterr skip_ws
 *
 * Exercised through the entry points the remaining C calls: i_gcd,
 * read_sign, islettere, isletterr, skip_ws.  The private helper issign is
 * reached through read_sign.
 */
#define FUZZ_UNIT "rational_01"
#define FUZZ_HAVE_SETUP 1
#include "ruby/ruby.h"
#include <ctype.h>
#include <limits.h>
#include <locale.h>
#include <string.h>
#include FUZZ_REF
#include "fuzz.h"

long rs_rb_core_rational_i_gcd(long x, long y);
int rs_rb_core_rational_read_sign(const char **s, const char *const e);
int rs_rb_core_rational_islettere(int c);
int rs_rb_core_rational_isletterr(int c);
const char *rs_rb_core_rational_skip_ws(const char *s, const char *e);

static void
fuzz_setup(void)
{
    /* Ruby runs with LC_CTYPE from the environment; so does the harness
     * (skip_ws calls isspace(), which depends on it for bytes >= 0x80). */
    setlocale(LC_CTYPE, "");
}

#define MAXLEN 48

/* Signs, whitespace (ASCII and the Latin-1 NBSP/NEL bytes), letters the
 * scanner tests, digits. */
static const char alphabet[] = "+-+- \t\n\v\f\r\xa0\x85 eErR?0123456789/._";

/*
 * A long for i_gcd.  i_gcd's precondition: neither argument is LONG_MIN
 * (`x = -x` would be signed overflow, undefined behaviour in C); every C
 * caller passes FIX2LONG() values, which are within +-2**62.
 */
static long
draw_long(void)
{
    long v;
    switch (fuzz_below(8)) {
      case 0: v = (long)fuzz_below(3); break;                   /* 0, 1, 2 */
      case 1: v = (long)fuzz_below(1000); break;
      case 2: v = (long)(fuzz_below(1 << 20) << fuzz_below(40)); break; /* many trailing zeros */
      case 3: v = (long)(fuzz_next() >> fuzz_below(64)); break;
      case 4: { /* fixnum bounds and powers of two */
        static const long edge[] = {
            (1L << 62) - 1, -(1L << 62), LONG_MAX, LONG_MIN + 1,
            1L << 62, 1L << 61, 1L << 32, 3L << 40, 1, -1,
        };
        v = edge[fuzz_below(sizeof(edge) / sizeof(edge[0]))];
        break;
      }
      default: v = (long)fuzz_next(); break;
    }
    if (v == LONG_MIN) v = LONG_MIN + 1;
    if (fuzz_one_in(2) && v != LONG_MIN) v = -v;
    return v;
}

static void
fuzz_one(void)
{
    uint64_t which = fuzz_below(8);

    if (which <= 2) { /* i_gcd */
        long x = draw_long(), y = draw_long();
        long rx, ry;
        /* A common factor makes the GCD non-trivial. */
        if (fuzz_one_in(2)) {
            long k = (long)fuzz_below(1 << 16) + 1;
            x = (long)((unsigned long)(x / (1L << 20)) * (unsigned long)k);
            y = (long)((unsigned long)(y / (1L << 20)) * (unsigned long)k);
            if (x == LONG_MIN) x = 0;
            if (y == LONG_MIN) y = 0;
        }
        fuzz_input_num("x", x);
        fuzz_input_num("y", y);
        rx = fuzz_rs_long(x);
        ry = y;
        if (rx == LONG_MIN) rx = x; /* mutation mode: stay inside the precondition */
        FUZZ_EQ("i_gcd", ref_i_gcd(x, y), rs_rb_core_rational_i_gcd(rx, ry));
        return;
    }

    if (which == 3) { /* islettere / isletterr: every char value and beyond */
        int c = (int)fuzz_below(600) - 300;
        int rc = (int)fuzz_rs_long(c);
        fuzz_input_num("c", c);
        FUZZ_EQ("islettere", ref_islettere(c), rs_rb_core_rational_islettere(rc));
        FUZZ_EQ("isletterr", ref_isletterr(c), rs_rb_core_rational_isletterr(rc));
        return;
    }

    {
        unsigned char in[MAXLEN + 1];
        size_t len = fuzz_len(MAXLEN);
        size_t so, eo;
        const char *c_in, *rs_in;

        fuzz_fill(in, len, alphabet);
        in[len] = '\0';
        /* s and e anywhere in [0, len]; s > e is a valid pointer comparison
         * in the C and must read nothing. */
        so = (size_t)fuzz_below(len + 1);
        eo = fuzz_one_in(4) ? (size_t)fuzz_below(len + 1) : len;
        if (fuzz_one_in(2) && so > eo) so = eo;
        fuzz_input("str", in, len);
        fuzz_input_num("s", (long)so);
        fuzz_input_num("e", (long)eo);
        c_in = (const char *)in;
        rs_in = (const char *)fuzz_rs_bytes(in, len);

        if (which <= 5) { /* read_sign */
            const char *c_s = c_in + so, *rs_s = rs_in + so;
            int c_r, rs_r;
            fuzz_input_num("fn read_sign", 0);
            c_r = ref_read_sign(&c_s, c_in + eo);
            rs_r = rs_rb_core_rational_read_sign(&rs_s, rs_in + eo);
            FUZZ_EQ("read_sign return", c_r, rs_r);
            FUZZ_EQ("read_sign *s offset", (long)(c_s - c_in), (long)(rs_s - rs_in));
        }
        else { /* skip_ws */
            const char *c_r = ref_skip_ws(c_in + so, c_in + eo);
            const char *rs_r = rs_rb_core_rational_skip_ws(rs_in + so, rs_in + eo);
            FUZZ_EQ("skip_ws offset", (long)(c_r - c_in), (long)(rs_r - rs_in));
        }
    }
}
