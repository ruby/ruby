#ifndef YARP_ENCODING_H
#define YARP_ENCODING_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define YP_ENCODING_ALPHABETIC_BIT 0b001
#define YP_ENCODING_ALPHANUMERIC_BIT 0b010
#define YP_ENCODING_UPPERCASE_BIT 0b100

/******************************************************************************/
/* ASCII                                                                      */
/******************************************************************************/

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_ascii_alpha_char(const char *c);

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_ascii_alnum_char(const char *c);

__attribute__((__visibility__("default"))) extern bool
yp_encoding_ascii_isupper_char(const char *c);

/******************************************************************************/
/* Big5                                                                       */
/******************************************************************************/

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_big5_alpha_char(const char *c);

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_big5_alnum_char(const char *c);

__attribute__((__visibility__("default"))) extern bool
yp_encoding_big5_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-9                                                                 */
/******************************************************************************/

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_iso_8859_9_alpha_char(const char *c);

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_iso_8859_9_alnum_char(const char *c);

__attribute__((__visibility__("default"))) extern bool
yp_encoding_iso_8859_9_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-15                                                                */
/******************************************************************************/

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_iso_8859_15_alpha_char(const char *c);

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_iso_8859_15_alnum_char(const char *c);

__attribute__((__visibility__("default"))) extern bool
yp_encoding_iso_8859_15_isupper_char(const char *c);

/******************************************************************************/
/* UTF-8                                                                      */
/******************************************************************************/

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_utf_8_alpha_char(const char *c);

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_utf_8_alnum_char(const char *c);

__attribute__((__visibility__("default"))) extern bool
yp_encoding_utf_8_isupper_char(const char *c);

/******************************************************************************/
/* Windows-1252                                                               */
/******************************************************************************/

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_windows_1252_alpha_char(const char *c);

__attribute__((__visibility__("default"))) extern size_t
yp_encoding_windows_1252_alnum_char(const char *c);

__attribute__((__visibility__("default"))) extern bool
yp_encoding_windows_1252_isupper_char(const char *c);


#endif
