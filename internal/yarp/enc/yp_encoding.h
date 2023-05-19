#ifndef YARP_ENCODING_H
#define YARP_ENCODING_H

#include "yarp/defines.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define YP_ENCODING_ALPHABETIC_BIT 1 << 0
#define YP_ENCODING_ALPHANUMERIC_BIT 1 << 1
#define YP_ENCODING_UPPERCASE_BIT 1 << 2

// The function is shared between all of the encodings that use single bytes to
// represent characters. They don't have need of a dynamic function to determine
// their width.
size_t
yp_encoding_single_char_width(__attribute__((unused)) const char *c);

/******************************************************************************/
/* ASCII                                                                      */
/******************************************************************************/

size_t
yp_encoding_ascii_char_width(const char *c);

size_t
yp_encoding_ascii_alpha_char(const char *c);

size_t
yp_encoding_ascii_alnum_char(const char *c);

bool
yp_encoding_ascii_isupper_char(const char *c);

/******************************************************************************/
/* Big5                                                                       */
/******************************************************************************/

size_t
yp_encoding_big5_char_width(const char *c);

size_t
yp_encoding_big5_alpha_char(const char *c);

size_t
yp_encoding_big5_alnum_char(const char *c);

bool
yp_encoding_big5_isupper_char(const char *c);

/******************************************************************************/
/* EUC-JP                                                                     */
/******************************************************************************/

size_t
yp_encoding_euc_jp_char_width(const char *c);

size_t
yp_encoding_euc_jp_alpha_char(const char *c);

size_t
yp_encoding_euc_jp_alnum_char(const char *c);

bool
yp_encoding_euc_jp_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-1                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_1_char_width(const char *c);

size_t
yp_encoding_iso_8859_1_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_1_alnum_char(const char *c);

bool
yp_encoding_iso_8859_1_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-2                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_2_char_width(const char *c);

size_t
yp_encoding_iso_8859_2_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_2_alnum_char(const char *c);

bool
yp_encoding_iso_8859_2_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-3                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_3_char_width(const char *c);

size_t
yp_encoding_iso_8859_3_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_3_alnum_char(const char *c);

bool
yp_encoding_iso_8859_3_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-4                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_4_char_width(const char *c);

size_t
yp_encoding_iso_8859_4_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_4_alnum_char(const char *c);

bool
yp_encoding_iso_8859_4_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-5                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_5_char_width(const char *c);

size_t
yp_encoding_iso_8859_5_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_5_alnum_char(const char *c);

bool
yp_encoding_iso_8859_5_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-6                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_6_char_width(const char *c);

size_t
yp_encoding_iso_8859_6_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_6_alnum_char(const char *c);

bool
yp_encoding_iso_8859_6_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-7                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_7_char_width(const char *c);

size_t
yp_encoding_iso_8859_7_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_7_alnum_char(const char *c);

bool
yp_encoding_iso_8859_7_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-8                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_8_char_width(const char *c);

size_t
yp_encoding_iso_8859_8_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_8_alnum_char(const char *c);

bool
yp_encoding_iso_8859_8_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-9                                                                 */
/******************************************************************************/

size_t
yp_encoding_iso_8859_9_char_width(const char *c);

size_t
yp_encoding_iso_8859_9_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_9_alnum_char(const char *c);

bool
yp_encoding_iso_8859_9_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-10                                                                */
/******************************************************************************/

size_t
yp_encoding_iso_8859_10_char_width(const char *c);

size_t
yp_encoding_iso_8859_10_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_10_alnum_char(const char *c);

bool
yp_encoding_iso_8859_10_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-11                                                                */
/******************************************************************************/

size_t
yp_encoding_iso_8859_11_char_width(const char *c);

size_t
yp_encoding_iso_8859_11_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_11_alnum_char(const char *c);

bool
yp_encoding_iso_8859_11_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-13                                                                */
/******************************************************************************/

size_t
yp_encoding_iso_8859_13_char_width(const char *c);

size_t
yp_encoding_iso_8859_13_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_13_alnum_char(const char *c);

bool
yp_encoding_iso_8859_13_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-14                                                                */
/******************************************************************************/

size_t
yp_encoding_iso_8859_14_char_width(const char *c);

size_t
yp_encoding_iso_8859_14_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_14_alnum_char(const char *c);

bool
yp_encoding_iso_8859_14_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-15                                                                */
/******************************************************************************/

size_t
yp_encoding_iso_8859_15_char_width(const char *c);

size_t
yp_encoding_iso_8859_15_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_15_alnum_char(const char *c);

bool
yp_encoding_iso_8859_15_isupper_char(const char *c);

/******************************************************************************/
/* ISO-8859-16                                                                */
/******************************************************************************/

size_t
yp_encoding_iso_8859_16_char_width(const char *c);

size_t
yp_encoding_iso_8859_16_alpha_char(const char *c);

size_t
yp_encoding_iso_8859_16_alnum_char(const char *c);

bool
yp_encoding_iso_8859_16_isupper_char(const char *c);

/******************************************************************************/
/* Shift-JIS                                                                  */
/******************************************************************************/

size_t
yp_encoding_shift_jis_char_width(const char *c);

size_t
yp_encoding_shift_jis_alpha_char(const char *c);

size_t
yp_encoding_shift_jis_alnum_char(const char *c);

bool
yp_encoding_shift_jis_isupper_char(const char *c);

/******************************************************************************/
/* UTF-8                                                                      */
/******************************************************************************/

size_t
yp_encoding_utf_8_char_width(const char *c);

size_t
yp_encoding_utf_8_alpha_char(const char *c);

size_t
yp_encoding_utf_8_alnum_char(const char *c);

bool
yp_encoding_utf_8_isupper_char(const char *c);

/******************************************************************************/
/* Windows-31J                                                                */
/******************************************************************************/

size_t
yp_encoding_windows_31j_char_width(const char *c);

size_t
yp_encoding_windows_31j_alpha_char(const char *c);

size_t
yp_encoding_windows_31j_alnum_char(const char *c);

bool
yp_encoding_windows_31j_isupper_char(const char *c);

/******************************************************************************/
/* Windows-1251                                                               */
/******************************************************************************/

size_t
yp_encoding_windows_1251_char_width(const char *c);

size_t
yp_encoding_windows_1251_alpha_char(const char *c);

size_t
yp_encoding_windows_1251_alnum_char(const char *c);

bool
yp_encoding_windows_1251_isupper_char(const char *c);

/******************************************************************************/
/* Windows-1252                                                               */
/******************************************************************************/

size_t
yp_encoding_windows_1252_char_width(const char *c);

size_t
yp_encoding_windows_1252_alpha_char(const char *c);

size_t
yp_encoding_windows_1252_alnum_char(const char *c);

bool
yp_encoding_windows_1252_isupper_char(const char *c);

#endif
