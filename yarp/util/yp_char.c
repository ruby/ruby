#include "yarp/include/yarp/util/yp_char.h"

#define YP_CHAR_BIT_WHITESPACE (1 << 0)
#define YP_CHAR_BIT_INLINE_WHITESPACE (1 << 1)
#define YP_CHAR_BIT_REGEXP_OPTION (1 << 2)

#define YP_NUMBER_BIT_BINARY_DIGIT (1 << 0)
#define YP_NUMBER_BIT_BINARY_NUMBER (1 << 1)
#define YP_NUMBER_BIT_OCTAL_DIGIT (1 << 2)
#define YP_NUMBER_BIT_OCTAL_NUMBER (1 << 3)
#define YP_NUMBER_BIT_DECIMAL_DIGIT (1 << 4)
#define YP_NUMBER_BIT_DECIMAL_NUMBER (1 << 5)
#define YP_NUMBER_BIT_HEXADECIMAL_DIGIT (1 << 6)
#define YP_NUMBER_BIT_HEXADECIMAL_NUMBER (1 << 7)

static const unsigned char yp_char_table[256] = {
//0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
  0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 1, 3, 3, 3, 0, 0, // 0x
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 1x
  3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 2x
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 3x
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 4x
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 5x
  0, 0, 0, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 4, 4, 4, // 6x
  0, 0, 0, 4, 0, 4, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, // 7x
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 8x
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 9x
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Ax
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Bx
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Cx
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Dx
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Ex
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // Fx
};

static const unsigned char yp_number_table[256] = {
  // 0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 0x
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 1x
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 2x
  0xff, 0xff, 0xfc, 0xfc, 0xfc, 0xfc, 0xfc, 0xfc, 0xf0, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 3x
  0x00, 0xc0, 0xc0, 0xc0, 0xc0, 0xc0, 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 4x
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xaa, // 5x
  0x00, 0xc0, 0xc0, 0xc0, 0xc0, 0xc0, 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 6x
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 7x
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 8x
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 9x
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Ax
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Bx
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Cx
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Dx
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Ex
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Fx
};

static inline size_t
yp_strspn_char_kind(const char *string, long length, unsigned char kind) {
  if (length <= 0) return 0;

  size_t size = 0;
  size_t maximum = (size_t) length;

  while (size < maximum && (yp_char_table[(unsigned char) string[size]] & kind)) size++;
  return size;
}

// Returns the number of characters at the start of the string that are
// whitespace. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_whitespace(const char *string, long length) {
  return yp_strspn_char_kind(string, length, YP_CHAR_BIT_WHITESPACE);
}

// Returns the number of characters at the start of the string that are inline
// whitespace. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_inline_whitespace(const char *string, long length) {
  return yp_strspn_char_kind(string, length, YP_CHAR_BIT_INLINE_WHITESPACE);
}

// Returns the number of characters at the start of the string that are regexp
// options. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_regexp_option(const char *string, long length) {
  return yp_strspn_char_kind(string, length, YP_CHAR_BIT_REGEXP_OPTION);
}

static inline bool
yp_char_is_char_kind(const char c, unsigned char kind) {
  return (yp_char_table[(unsigned char) c] & kind) != 0;
}

// Returns true if the given character is a whitespace character.
bool
yp_char_is_whitespace(const char c) {
  return yp_char_is_char_kind(c, YP_CHAR_BIT_WHITESPACE);
}

// Returns true if the given character is an inline whitespace character.
bool
yp_char_is_inline_whitespace(const char c) {
  return yp_char_is_char_kind(c, YP_CHAR_BIT_INLINE_WHITESPACE);
}

static inline size_t
yp_strspn_number_kind(const char *string, long length, unsigned char kind) {
  if (length <= 0) return 0;

  size_t size = 0;
  size_t maximum = (size_t) length;

  while (size < maximum && (yp_number_table[(unsigned char) string[size]] & kind)) size++;
  return size;
}

// Returns the number of characters at the start of the string that are binary
// digits or underscores. Disallows searching past the given maximum number of
// characters.
size_t
yp_strspn_binary_number(const char *string, long length) {
  return yp_strspn_number_kind(string, length, YP_NUMBER_BIT_BINARY_NUMBER);
}

// Returns the number of characters at the start of the string that are octal
// digits or underscores.  Disallows searching past the given maximum number of
// characters.
size_t
yp_strspn_octal_number(const char *string, long length) {
  return yp_strspn_number_kind(string, length, YP_NUMBER_BIT_OCTAL_NUMBER);
}

// Returns the number of characters at the start of the string that are decimal
// digits. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_decimal_digit(const char *string, long length) {
  return yp_strspn_number_kind(string, length, YP_NUMBER_BIT_DECIMAL_DIGIT);
}

// Returns the number of characters at the start of the string that are decimal
// digits or underscores. Disallows searching past the given maximum number of
// characters.
size_t
yp_strspn_decimal_number(const char *string, long length) {
  return yp_strspn_number_kind(string, length, YP_NUMBER_BIT_DECIMAL_NUMBER);
}

// Returns the number of characters at the start of the string that are
// hexadecimal digits. Disallows searching past the given maximum number of
// characters.
size_t
yp_strspn_hexadecimal_digit(const char *string, long length) {
  return yp_strspn_number_kind(string, length, YP_NUMBER_BIT_HEXADECIMAL_DIGIT);
}

// Returns the number of characters at the start of the string that are
// hexadecimal digits or underscores. Disallows searching past the given maximum
// number of characters.
size_t
yp_strspn_hexadecimal_number(const char *string, long length) {
  return yp_strspn_number_kind(string, length, YP_NUMBER_BIT_HEXADECIMAL_NUMBER);
}

static inline bool
yp_char_is_number_kind(const char c, unsigned char kind) {
  return (yp_number_table[(unsigned char) c] & kind) != 0;
}

// Returns true if the given character is a binary digit.
bool
yp_char_is_binary_digit(const char c) {
  return yp_char_is_number_kind(c, YP_NUMBER_BIT_BINARY_DIGIT);
}

// Returns true if the given character is an octal digit.
bool
yp_char_is_octal_digit(const char c) {
  return yp_char_is_number_kind(c, YP_NUMBER_BIT_OCTAL_DIGIT);
}

// Returns true if the given character is a decimal digit.
bool
yp_char_is_decimal_digit(const char c) {
  return yp_char_is_number_kind(c, YP_NUMBER_BIT_DECIMAL_DIGIT);
}

// Returns true if the given character is a hexadecimal digit.
bool
yp_char_is_hexadecimal_digit(const char c) {
  return yp_char_is_number_kind(c, YP_NUMBER_BIT_HEXADECIMAL_DIGIT);
}

#undef YP_CHAR_BIT_WHITESPACE
#undef YP_CHAR_BIT_INLINE_WHITESPACE
#undef YP_CHAR_BIT_REGEXP_OPTION

#undef YP_NUMBER_BIT_BINARY_DIGIT
#undef YP_NUMBER_BIT_BINARY_NUMBER
#undef YP_NUMBER_BIT_OCTAL_DIGIT
#undef YP_NUMBER_BIT_OCTAL_NUMBER
#undef YP_NUMBER_BIT_DECIMAL_DIGIT
#undef YP_NUMBER_BIT_DECIMAL_NUMBER
#undef YP_NUMBER_BIT_HEXADECIMAL_NUMBER
#undef YP_NUMBER_BIT_HEXADECIMAL_DIGIT
