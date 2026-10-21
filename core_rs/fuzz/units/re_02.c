/*
 * Differential fuzz: re.c check_unicode_range (port unit re-A-02,
 * core_rs/src/re.rs) against the original C.
 *
 * FUZZ-EXTRACT: re.c check_unicode_range
 *
 * Codes are drawn uniformly over unsigned long and densely around the
 * boundaries (U+D7FF/U+D800, U+DFFF/U+E000, U+10FFFF/U+110000), so both
 * branches and every edge are hit.  The error buffer starts filled with a
 * random byte pattern; every byte of it is compared afterwards, which
 * checks that the message, its NUL and nothing else are written.
 */
#define FUZZ_UNIT "re_02"
#include "ruby/ruby.h"
#include "ruby/onigmo.h"
#include <string.h>

typedef char onig_errmsg_buffer[ONIG_MAX_ERROR_MESSAGE_LEN];
#define errcpy(err, msg) strlcpy((err), (msg), ONIG_MAX_ERROR_MESSAGE_LEN)

#include FUZZ_REF
#include "fuzz.h"

int rs_rb_core_re_check_unicode_range(unsigned long code, char *err);

static const unsigned long edges[] = {
    0, 0x7f, 0x80, 0xd7ff, 0xd800, 0xdbff, 0xdc00, 0xdfff, 0xe000,
    0xffff, 0x10000, 0x10ffff, 0x110000, 0x7fffffffUL, 0xffffffffUL,
};

static void
fuzz_one(void)
{
    onig_errmsg_buffer c_err, rs_err;
    unsigned long code;
    int c_ret, rs_ret;
    size_t i;

    switch (fuzz_below(3)) {
      case 0: code = (unsigned long)fuzz_next(); break;
      case 1: code = (unsigned long)fuzz_below(0x120000); break;
      default:
        code = edges[fuzz_below(sizeof(edges) / sizeof(edges[0]))] + (unsigned long)fuzz_below(5) - 2;
        break;
    }
    fuzz_fill((unsigned char *)c_err, sizeof(c_err), NULL);
    memcpy(rs_err, c_err, sizeof(rs_err));
    fuzz_input_num("code", (long)code);

    c_ret = ref_check_unicode_range(code, c_err);
    rs_ret = rs_rb_core_re_check_unicode_range((unsigned long)fuzz_rs_long((long)code), rs_err);
    FUZZ_EQ("ret", c_ret, rs_ret);
    for (i = 0; i < sizeof(c_err); i++) {
        FUZZ_EQ("err byte", (unsigned char)c_err[i], (unsigned char)rs_err[i]);
    }
}
