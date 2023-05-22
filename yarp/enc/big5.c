#include "yarp/enc/yp_encoding.h"

typedef uint32_t big5_codepoint_t;

static big5_codepoint_t
big5_codepoint(const char *c, size_t *width) {
  const unsigned char *uc = (const unsigned char *) c;

  // These are the single byte characters.
  if (*uc < 0x80) {
    *width = 1;
    return *uc;
  }

  // These are the double byte characters.
  if ((uc[0] >= 0xA1 && uc[0] <= 0xFE) && (uc[1] >= 0x40 && uc[1] <= 0xFE)) {
    *width = 2;
    return (big5_codepoint_t) (uc[0] << 8 | uc[1]);
  }

  *width = 0;
  return 0;
}

size_t
yp_encoding_big5_char_width(const char *c) {
  size_t width;
  big5_codepoint(c, &width);

  return width;
}

size_t
yp_encoding_big5_alpha_char(const char *c) {
  size_t width;
  big5_codepoint_t codepoint = big5_codepoint(c, &width);

  if (width == 1) {
    const char value = (const char) codepoint;
    return yp_encoding_ascii_alpha_char(&value);
  } else {
    return 0;
  }
}

size_t
yp_encoding_big5_alnum_char(const char *c) {
  size_t width;
  big5_codepoint_t codepoint = big5_codepoint(c, &width);

  if (width == 1) {
    const char value = (const char) codepoint;
    return yp_encoding_ascii_alnum_char(&value);
  } else {
    return 0;
  }
}

bool
yp_encoding_big5_isupper_char(const char *c) {
  size_t width;
  big5_codepoint_t codepoint = big5_codepoint(c, &width);

  if (width == 1) {
    const char value = (const char) codepoint;
    return yp_encoding_ascii_isupper_char(&value);
  } else {
    return false;
  }
}
