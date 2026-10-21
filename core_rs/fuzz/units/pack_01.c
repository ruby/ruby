/*
 * Differential fuzz: pack.c helper functions (port unit pack-A-01,
 * core_rs/src/pack.rs) against the original C.
 *
 * FUZZ-EXTRACT: pack.c NATINT:53-87 is_bigendian skip_to_eol pack_alignof hex2num
 */
#define FUZZ_UNIT "pack_01"
#include "ruby/ruby.h"
#include "ruby/util.h"
#include <ctype.h>
#include <string.h>
#include FUZZ_REF
#include "fuzz.h"

int rs_rb_core_pack_is_bigendian(void);
char *rs_rb_core_pack_skip_to_eol(const char *p, const char *pend);
size_t rs_rb_core_pack_pack_alignof(char type, int natint);
int rs_rb_core_pack_hex2num(char c);

static void
fuzz_one(void)
{
    uint64_t choice = fuzz_below(4);
    switch (choice) {
      case 0: { /* is_bigendian */
        int c_res = ref_is_bigendian();
        int rs_res = rs_rb_core_pack_is_bigendian();
        FUZZ_EQ("is_bigendian", c_res, rs_res);
        break;
      }
      case 1: { /* skip_to_eol */
        unsigned char buf[128];
        size_t len = fuzz_len(120);
        fuzz_fill(buf, len, "abcdefghijklmnopqrstuvwxyz0123456789 \t\n\r#$_!<>/\\");
        fuzz_input("skip_to_eol str", buf, len);
        const char *c_p = (const char *)buf;
        const char *c_pend = c_p + len;
        const char *rs_p = (const char *)fuzz_rs_bytes(buf, len);
        const char *rs_pend = rs_p + len;

        char *c_res = ref_skip_to_eol(c_p, c_pend);
        char *rs_res = rs_rb_core_pack_skip_to_eol(rs_p, rs_pend);

        FUZZ_EQ("skip_to_eol offset", (long)(c_res - c_p), (long)(rs_res - rs_p));
        break;
      }
      case 2: { /* pack_alignof */
        static const char directives[] = "cCsSiIlLqQjJnNvVVfFeEgGdDpPxX123@!#$&*()";
        char type = directives[fuzz_below(sizeof(directives) - 1)];
        int natint = (int)fuzz_below(2);
        fuzz_input_num("pack_alignof type", type);
        fuzz_input_num("pack_alignof natint", natint);

        size_t c_res = ref_pack_alignof(type, natint);
        size_t rs_res = rs_rb_core_pack_pack_alignof((char)fuzz_rs_long(type), natint);

        FUZZ_EQ("pack_alignof", c_res, rs_res);
        break;
      }
      case 3: { /* hex2num */
        int c = (int)fuzz_below(300) - 20;
        fuzz_input_num("hex2num c", c);

        int c_res = ref_hex2num((char)c);
        int rs_res = rs_rb_core_pack_hex2num((char)fuzz_rs_long(c));

        FUZZ_EQ("hex2num", c_res, rs_res);
        break;
      }
    }
}
