#include "yarp/enc/yp_encoding.h"

typedef uint32_t euc_jp_codepoint_t;

static euc_jp_codepoint_t
euc_jp_codepoint(const char *c, size_t *width) {
  const unsigned char *uc = (const unsigned char *) c;

  // These are the single byte characters.
  if (*uc < 0x80) {
    *width = 1;
    return *uc;
  }

  // These are the double byte characters.
  if (
    ((uc[0] == 0x8E) && (uc[1] >= 0xA1 && uc[1] <= 0xFE)) ||
    ((uc[0] >= 0xA1 && uc[0] <= 0xFE) && (uc[1] >= 0xA1 && uc[1] <= 0xFE))
  ) {
    *width = 2;
    return (euc_jp_codepoint_t) (uc[0] << 8 | uc[1]);
  }

  *width = 0;
  return 0;
}

size_t
yp_encoding_euc_jp_char_width(const char *c) {
  size_t width;
  euc_jp_codepoint(c, &width);

  return width;
}

size_t
yp_encoding_euc_jp_alpha_char(const char *c) {
  size_t width;
  euc_jp_codepoint_t codepoint = euc_jp_codepoint(c, &width);

  if (width == 1) {
    const char value = (const char) codepoint;
    return yp_encoding_ascii_alpha_char(&value);
  } else {
    return 0;
  }
}

size_t
yp_encoding_euc_jp_alnum_char(const char *c) {
  size_t width;
  euc_jp_codepoint_t codepoint = euc_jp_codepoint(c, &width);

  if (width == 1) {
    const char value = (const char) codepoint;
    return yp_encoding_ascii_alnum_char(&value);
  } else {
    return 0;
  }
}

bool
yp_encoding_euc_jp_isupper_char(const char *c) {
  size_t width;
  euc_jp_codepoint_t codepoint = euc_jp_codepoint(c, &width);

  if (width == 1) {
    const char value = (const char) codepoint;
    return yp_encoding_ascii_isupper_char(&value);
  } else {
    return 0;
  }
}
