#ifndef YP_CHAR_H
#define YP_CHAR_H

#include "yarp/defines.h"
#include "yarp/util/yp_newline_list.h"

#include <stdbool.h>
#include <stddef.h>

// Returns the number of characters at the start of the string that are
// whitespace. Disallows searching past the given maximum number of characters.
size_t yp_strspn_whitespace(const char *string, ptrdiff_t length);

// Returns the number of characters at the start of the string that are
// whitespace while also tracking the location of each newline. Disallows
// searching past the given maximum number of characters.
size_t
yp_strspn_whitespace_newlines(const char *string, ptrdiff_t length, yp_newline_list_t *newline_list, bool);

// Returns the number of characters at the start of the string that are inline
// whitespace. Disallows searching past the given maximum number of characters.
size_t yp_strspn_inline_whitespace(const char *string, ptrdiff_t length);

// Returns the number of characters at the start of the string that are decimal
// digits. Disallows searching past the given maximum number of characters.
size_t yp_strspn_decimal_digit(const char *string, ptrdiff_t length);

// Returns the number of characters at the start of the string that are
// hexadecimal digits. Disallows searching past the given maximum number of
// characters.
size_t yp_strspn_hexadecimal_digit(const char *string, ptrdiff_t length);

// Returns the number of characters at the start of the string that are octal
// digits or underscores.  Disallows searching past the given maximum number of
// characters.
size_t yp_strspn_octal_number(const char *string, ptrdiff_t length);

// Returns the number of characters at the start of the string that are decimal
// digits or underscores. Disallows searching past the given maximum number of
// characters.
size_t yp_strspn_decimal_number(const char *string, ptrdiff_t length);

// Returns the number of characters at the start of the string that are
// hexadecimal digits or underscores. Disallows searching past the given maximum
// number of characters.
size_t yp_strspn_hexadecimal_number(const char *string, ptrdiff_t length);

// Returns the number of characters at the start of the string that are regexp
// options. Disallows searching past the given maximum number of characters.
size_t yp_strspn_regexp_option(const char *string, ptrdiff_t length);

// Returns the number of characters at the start of the string that are binary
// digits or underscores. Disallows searching past the given maximum number of
// characters.
size_t yp_strspn_binary_number(const char *string, ptrdiff_t length);

// Returns true if the given character is a whitespace character.
bool yp_char_is_whitespace(const char c);

// Returns true if the given character is an inline whitespace character.
bool yp_char_is_inline_whitespace(const char c);

// Returns true if the given character is a binary digit.
bool yp_char_is_binary_digit(const char c);

// Returns true if the given character is an octal digit.
bool yp_char_is_octal_digit(const char c);

// Returns true if the given character is a decimal digit.
bool yp_char_is_decimal_digit(const char c);

// Returns true if the given character is a hexadecimal digit.
bool yp_char_is_hexadecimal_digit(const char c);

#endif
