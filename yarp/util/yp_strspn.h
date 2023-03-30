#ifndef YP_STRSPN_H
#define YP_STRSPN_H

#include <stddef.h>

// Returns the number of characters at the start of the string string that are a
// whitespace. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_whitespace(const char *string, int maximum);

// Returns the number of characters at the start of the string string that are a
// inline whitespace. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_inline_whitespace(const char *string, int maximum);

// Returns the number of characters at the start of the string string that are a
// decimal digit. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_decimal_digit(const char *string, int maximum);

// Returns the number of characters at the start of the string string that are a
// hexidecimal digit. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_hexidecimal_digit(const char *string, int maximum);

// Returns the number of characters at the start of the string string that are a
// octal number. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_octal_number(const char *string, int maximum);

// Returns the number of characters at the start of the string string that are a
// decimal number. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_decimal_number(const char *string, int maximum);

// Returns the number of characters at the start of the string string that are a
// hexidecimal number. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_hexidecimal_number(const char *string, int maximum);

// Returns the number of characters at the start of the string string that are a
// regexp option. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_regexp_option(const char *string, int maximum);

// Returns the number of characters at the start of the string string that are a
// binary number. Disallows searching past the given maximum number of characters.
size_t
yp_strspn_binary_number(const char *string, int maximum);

#endif
