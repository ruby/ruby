#include "yp_strspn.h"

#define YP_STRSPN_BIT_WHITESPACE (1 << 0)
#define YP_STRSPN_BIT_INLINE_WHITESPACE (1 << 1)
#define YP_STRSPN_BIT_DECIMAL_DIGIT (1 << 2)
#define YP_STRSPN_BIT_HEXIDECIMAL_DIGIT (1 << 3)
#define YP_STRSPN_BIT_OCTAL_NUMBER (1 << 4)
#define YP_STRSPN_BIT_DECIMAL_NUMBER (1 << 5)
#define YP_STRSPN_BIT_HEXIDECIMAL_NUMBER (1 << 6)
#define YP_STRSPN_BIT_REGEXP_OPTION (1 << 7)

const unsigned char yp_strspn_table[256] = {
  //       0           1           2           3           4           5           6           7           8           9           A           B           C           D           E           F
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000011, 0b00000001, 0b00000011, 0b00000011, 0b00000011, 0b00000000, 0b00000000, // 0x
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // 1x
  0b00000011, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // 2x
  0b01111100, 0b01111100, 0b01111100, 0b01111100, 0b01111100, 0b01111100, 0b01111100, 0b01111100, 0b01101100, 0b01101100, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // 3x
  0b00000000, 0b01001000, 0b01001000, 0b01001000, 0b01001000, 0b01001000, 0b01001000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // 4x
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b01110000, // 5x
  0b00000000, 0b01001000, 0b01001000, 0b01001000, 0b01001000, 0b11001000, 0b01001000, 0b00000000, 0b00000000, 0b10000000, 0b00000000, 0b00000000, 0b00000000, 0b10000000, 0b10000000, 0b10000000, // 6x
  0b00000000, 0b00000000, 0b00000000, 0b10000000, 0b00000000, 0b10000000, 0b00000000, 0b00000000, 0b10000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // 7x
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // 8x
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // 9x
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // Ax
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // Bx
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // Cx
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // Dx
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // Ex
  0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, // Fx
};

// Returns the number of characters at the start of the string string that are a
// whitespace. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_whitespace(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (yp_strspn_table[(unsigned char) string[size]] & YP_STRSPN_BIT_WHITESPACE)) size++;
  return size;
}

// Returns the number of characters at the start of the string string that are a
// inline whitespace. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_inline_whitespace(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (yp_strspn_table[(unsigned char) string[size]] & YP_STRSPN_BIT_INLINE_WHITESPACE)) size++;
  return size;
}

// Returns the number of characters at the start of the string string that are a
// decimal digit. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_decimal_digit(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (yp_strspn_table[(unsigned char) string[size]] & YP_STRSPN_BIT_DECIMAL_DIGIT)) size++;
  return size;
}

// Returns the number of characters at the start of the string string that are a
// hexidecimal digit. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_hexidecimal_digit(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (yp_strspn_table[(unsigned char) string[size]] & YP_STRSPN_BIT_HEXIDECIMAL_DIGIT)) size++;
  return size;
}

// Returns the number of characters at the start of the string string that are a
// octal number. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_octal_number(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (yp_strspn_table[(unsigned char) string[size]] & YP_STRSPN_BIT_OCTAL_NUMBER)) size++;
  return size;
}

// Returns the number of characters at the start of the string string that are a
// decimal number. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_decimal_number(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (yp_strspn_table[(unsigned char) string[size]] & YP_STRSPN_BIT_DECIMAL_NUMBER)) size++;
  return size;
}

// Returns the number of characters at the start of the string string that are a
// hexidecimal number. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_hexidecimal_number(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (yp_strspn_table[(unsigned char) string[size]] & YP_STRSPN_BIT_HEXIDECIMAL_NUMBER)) size++;
  return size;
}

// Returns the number of characters at the start of the string string that are a
// regexp option. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_regexp_option(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (yp_strspn_table[(unsigned char) string[size]] & YP_STRSPN_BIT_REGEXP_OPTION)) size++;
  return size;
}

// Returns the number of characters at the start of the string string that are a
// binary number. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_binary_number(const char *string, int maximum) {
  if (maximum <= 0) return 0;
  size_t size = 0;

  while (size < maximum && (string[size] == '0' || string[size] == '1' || string[size] == '_')) size++;
  return size;
}

#undef YP_STRSPN_BIT_WHITESPACE
#undef YP_STRSPN_BIT_INLINE_WHITESPACE
#undef YP_STRSPN_BIT_DECIMAL_DIGIT
#undef YP_STRSPN_BIT_HEXIDECIMAL_DIGIT
#undef YP_STRSPN_BIT_OCTAL_NUMBER
#undef YP_STRSPN_BIT_DECIMAL_NUMBER
#undef YP_STRSPN_BIT_HEXIDECIMAL_NUMBER
#undef YP_STRSPN_BIT_REGEXP_OPTION
