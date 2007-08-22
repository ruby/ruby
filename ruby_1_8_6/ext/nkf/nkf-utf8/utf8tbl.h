#ifndef _UTF8TBL_H_
#define _UTF8TBL_H_

#ifdef UTF8_OUTPUT_ENABLE
extern const unsigned short euc_to_utf8_1byte[];
extern const unsigned short *const euc_to_utf8_2bytes[];
extern const unsigned short *const euc_to_utf8_2bytes_ms[];
extern const unsigned short *const x0212_to_utf8_2bytes[];
#endif /* UTF8_OUTPUT_ENABLE */

#ifdef UTF8_INPUT_ENABLE
extern const unsigned short *const utf8_to_euc_2bytes[];
extern const unsigned short *const utf8_to_euc_2bytes_ms[];
extern const unsigned short *const utf8_to_euc_2bytes_932[];
extern const unsigned short *const *const utf8_to_euc_3bytes[];
extern const unsigned short *const *const utf8_to_euc_3bytes_ms[];
extern const unsigned short *const *const utf8_to_euc_3bytes_932[];
#endif /* UTF8_INPUT_ENABLE */

#ifdef UNICODE_NORMALIZATION
extern const struct normalization_pair normalization_table[];
#endif

#ifdef SHIFTJIS_CP932
extern const unsigned short shiftjis_cp932[3][189];
extern const unsigned short cp932inv[2][189];
#endif /* SHIFTJIS_CP932 */

#ifdef X0212_ENABLE
extern const unsigned short shiftjis_x0212[3][189];
extern const unsigned short *const x0212_shiftjis[];
#endif /* X0212_ENABLE */

#endif
