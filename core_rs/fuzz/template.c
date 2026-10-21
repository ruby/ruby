/*
 * Template for a differential fuzz unit.
 *
 * Scaffolding with signatures filled in can be generated via:
 *   ruby tool/core_rs/inventory.rb --fuzz-unit <unit-id>
 * Or copy this file to core_rs/fuzz/units/<c-file>_<topic>.c and fill in the three TODOs.
 * See core_rs/fuzz/README.md for the rules.
 *
 * TODO 1: name every C definition the port replaces, plus the static
 * helpers and tables they use, as they appear in the CRuby source.  Each
 * is copied verbatim and renamed ref_<name>.
 *
 * FUZZ-EXTRACT: util.c ruby_scan_digits
 */
#define FUZZ_UNIT "TODO_unit_name"
/* #define FUZZ_HAVE_SETUP 1  -- only if fuzz_setup() is needed (e.g. ruby_init()). */
#include "ruby/ruby.h"
/* TODO 2: the headers the extracted C needs (the ones its .c file includes). */
#include "ruby/util.h"
#include FUZZ_REF
#include "fuzz.h"

/* The Rust port of each function, with its rb_/ruby_ prefix renamed rs_. */
unsigned long rs_ruby_scan_digits(const char *str, ssize_t len, int base, size_t *retlen, int *overflow);

#define MAXLEN 64

/* TODO 3: one random case.  Draw inputs that reach every branch (boundary
 * lengths, every base/flag value, overflow), record them, call both sides,
 * and compare EVERY observable effect: return value, out-parameters,
 * errno, bytes written, callbacks made. */
static void
fuzz_one(void)
{
    unsigned char buf[MAXLEN + 1];
    size_t len = fuzz_len(MAXLEN);
    int base = 2 + (int)fuzz_below(35);
    size_t c_ret = 1, rs_ret = 2;         /* distinct sentinels catch unwritten out-params */
    int c_ov = 3, rs_ov = 4;
    const char *rs_in;

    fuzz_fill(buf, len, "0123456789abcdefxyz+- ");
    buf[len] = '\0';
    fuzz_input("str", buf, len);
    fuzz_input_num("base", base);
    rs_in = (const char *)fuzz_rs_bytes(buf, len);   /* the Rust side's view (mutated with --mutate) */

    FUZZ_EQ("value",
            ref_ruby_scan_digits((const char *)buf, (ssize_t)len, base, &c_ret, &c_ov),
            rs_ruby_scan_digits(rs_in, (ssize_t)len, base, &rs_ret, &rs_ov));
    FUZZ_EQ("retlen", c_ret, rs_ret);
    FUZZ_EQ("overflow", c_ov, rs_ov);
}
