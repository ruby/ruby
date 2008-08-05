#include "transcode_data.h"

<%
  require 'sjis-tbl'
  require 'eucjp-tbl'
%>

<%= transcode_tblgen "Shift_JIS", "UTF-8", [["{00-7f}", :nomap], *SJIS_TO_UCS_TBL] %>
<%= transcode_tblgen "Windows-31J", "UTF-8", [["{00-7f}", :nomap], *SJIS_TO_UCS_TBL] %>

<%= transcode_tblgen "UTF-8", "Shift_JIS", [["{00-7f}", :nomap], *UCS_TO_SJIS_TBL] %>
<%= transcode_tblgen "UTF-8", "Windows-31J", [["{00-7f}", :nomap], *UCS_TO_SJIS_TBL] %>

<%= transcode_tblgen "EUC-JP", "UTF-8", [["{00-7f}", :nomap], *EUCJP_TO_UCS_TBL] %>
<%= transcode_tblgen "CP51932", "UTF-8", [["{00-7f}", :nomap], *EUCJP_TO_UCS_TBL] %>

<%= transcode_tblgen "UTF-8", "EUC-JP", [["{00-7f}", :nomap], *UCS_TO_EUCJP_TBL] %>
<%= transcode_tblgen "UTF-8", "CP51932", [["{00-7f}", :nomap], *UCS_TO_EUCJP_TBL] %>

#define ISO_2022_ENCODING(escseq, byte) ((escseq<<8)|byte)
enum ISO_2022_ESCSEQ {
    ISO_2022_CZD   = '!',
    ISO_2022_C1D   = '"',
    ISO_2022_GZD4  = '(',
    ISO_2022_G1D4  = ')',
    ISO_2022_G2D4  = '*',
    ISO_2022_G3D4  = '+',
    ISO_2022_G1D6  = '-',
    ISO_2022_G2D6  = '.',
    ISO_2022_G3D6  = '/',
    ISO_2022_GZDM4 = ISO_2022_ENCODING('$','('),
    ISO_2022_G1DM4 = ISO_2022_ENCODING('$',')'),
    ISO_2022_G2DM4 = ISO_2022_ENCODING('$','*'),
    ISO_2022_G3DM4 = ISO_2022_ENCODING('$','+'),
    ISO_2022_G1DM6 = ISO_2022_ENCODING('$','-'),
    ISO_2022_G2DM6 = ISO_2022_ENCODING('$','.'),
    ISO_2022_G3DM6 = ISO_2022_ENCODING('$','/'),
    ISO_2022_DOCS  = ISO_2022_ENCODING('%','I'),
    ISO_2022_IRR   = '&'
};


#define ISO_2022_GZ_ASCII                       ISO_2022_ENCODING(ISO_2022_GZD4, 'B')
#define ISO_2022_GZ_JIS_X_0201_Katakana         ISO_2022_ENCODING(ISO_2022_GZD4, 'I')
#define ISO_2022_GZ_JIS_X_0201_Roman            ISO_2022_ENCODING(ISO_2022_GZD4, 'J')
#define ISO_2022_GZ_JIS_C_6226_1978             ISO_2022_ENCODING(ISO_2022_GZDM4,'@')
#define ISO_2022_GZ_JIS_X_0208_1983             ISO_2022_ENCODING(ISO_2022_GZDM4,'B')
#define ISO_2022_GZ_JIS_X_0212_1990             ISO_2022_ENCODING(ISO_2022_GZDM4,'D')
#define ISO_2022_GZ_JIS_X_0213_2000_1           ISO_2022_ENCODING(ISO_2022_GZDM4,'O')
#define ISO_2022_GZ_JIS_X_0213_2000_2           ISO_2022_ENCODING(ISO_2022_GZDM4,'P')
#define ISO_2022_GZ_JIS_X_0213_2004_1           ISO_2022_ENCODING(ISO_2022_GZDM4,'Q')

#define UNSUPPORTED_MODE TRANSCODE_ERROR

static int
get_iso_2022_mode(const unsigned char **in_pos)
{
    int new_mode;
    const unsigned char *in_p = *in_pos;
    switch (*in_p++) {
      case '(':
	switch (*in_p++) {
	  case 'B': case 'I': case 'J':
	    new_mode = ISO_2022_ENCODING(ISO_2022_GZD4, *(in_p-1));
	    break;
	  default:
	    rb_raise(UNSUPPORTED_MODE, "this mode is not supported (ESC ( %c)", *(in_p-1));
	    break;
	}
	break;
      case '$':
	switch (*in_p++) {
	  case '@': case 'A': case 'B':
	    new_mode = ISO_2022_ENCODING(ISO_2022_GZDM4, *(in_p-1));
	    break;
	  case '(':
	    switch (*in_p++) {
	      case 'D': case 'O': case 'P': case 'Q':
		new_mode = ISO_2022_ENCODING(ISO_2022_GZDM4, *(in_p-1));
		break;
	      default:
		rb_raise(UNSUPPORTED_MODE, "this mode is not supported (ESC $ ( %c)", *(in_p-1));
		break;
	    }
	    break;
	  default:
	    rb_raise(UNSUPPORTED_MODE, "this mode is not supported (ESC $ %c)", *(in_p-1));
	    break;
	}
	break;
      default:
	rb_raise(UNSUPPORTED_MODE, "this mode is not supported (ESC %c)", *(in_p-1));
	break;
    }
    *in_pos = in_p;
    return new_mode;
}

static void
from_iso_2022_jp_transcoder_preprocessor(const unsigned char **in_pos, unsigned char **out_pos,
					 const unsigned char *in_stop, unsigned char *out_stop,
					 rb_transcoding *my_transcoding)
{
    const rb_transcoder *my_transcoder = my_transcoding->transcoder;
    const unsigned char *in_p = *in_pos;
    unsigned char *out_p = *out_pos;
    int cur_mode = ISO_2022_GZ_ASCII;
    unsigned char c1;
    unsigned char *out_s = out_stop - my_transcoder->max_output + 1;
    while (in_p < in_stop) {
	if (out_p >= out_s) {
	    int len = (out_p - *out_pos);
	    int new_len = (len + my_transcoder->max_output) * 2;
	    *out_pos = (*my_transcoding->flush_func)(my_transcoding, len, new_len);
	    out_p = *out_pos + len;
	    out_s = *out_pos + new_len - my_transcoder->max_output;
	}
	c1 = *in_p++;
	if (c1 == 0x1B) {
	    cur_mode = get_iso_2022_mode(&in_p);
	}
	else if (c1 == 0x1E || c1 == 0x1F) {
	    /* SHIFT */
	    rb_raise(UNSUPPORTED_MODE, "shift is not supported");
	}
	else if (c1 >= 0x80) {
	    rb_raise(TRANSCODE_ERROR, "invalid byte sequence");
	}
	else {
	    switch (cur_mode) {
	      case ISO_2022_GZ_ASCII:
	      case ISO_2022_GZ_JIS_X_0201_Roman:
		*out_p++ = c1;
		break;
	      case ISO_2022_GZ_JIS_X_0201_Katakana:
		*out_p++ = 0x8E;
		*out_p++ = c1 | 0x80;
		break;
	      case ISO_2022_GZ_JIS_X_0212_1990:
		*out_p++ = 0x8F;
	      case ISO_2022_GZ_JIS_C_6226_1978:
	      case ISO_2022_GZ_JIS_X_0208_1983:
		*out_p++ = c1 | 0x80;
		*out_p++ = *in_p++ | 0x80;
		break;
	    }
	}
    }
    /* cleanup */
    *in_pos  = in_p;
    *out_pos = out_p;
}

static int
select_iso_2022_mode(unsigned char **out_pos, int new_mode)
{
    unsigned char *out_p = *out_pos;
    *out_p++ = '\x1b';
    switch (new_mode>>8) {
      case ISO_2022_GZD4:
	*out_p++ = new_mode >> 8;
	*out_p++ = new_mode & 0x7F;
	break;
      case ISO_2022_GZDM4:
	*out_p++ = new_mode >> 16;
	if ((new_mode & 0x7F) != '@' &&
	    (new_mode & 0x7F) != 'A' &&
	    (new_mode & 0x7F) != 'B')
	{
	    *out_p++ = (new_mode>>8) & 0x7F;
	}
	*out_p++ = new_mode & 0x7F;
	break;
      default:
	rb_raise(UNSUPPORTED_MODE, "this mode is not supported.");
	break;
    }
    *out_pos = out_p;
    return new_mode;
}

static void
to_iso_2022_jp_transcoder_postprocessor(const unsigned char **in_pos, unsigned char **out_pos,
					const unsigned char *in_stop, unsigned char *out_stop,
					rb_transcoding *my_transcoding)
{
    const rb_transcoder *my_transcoder = my_transcoding->transcoder;
    const unsigned char *in_p = *in_pos;
    unsigned char *out_p = *out_pos;
    int cur_mode = ISO_2022_GZ_ASCII, new_mode = 0;
    unsigned char next_byte;
    unsigned char *out_s = out_stop - my_transcoder->max_output + 1;
    while (in_p < in_stop) {
	if (out_p >= out_s) {
	    int len = (out_p - *out_pos);
	    int new_len = (len + my_transcoder->max_output) * 2;
	    *out_pos = (*my_transcoding->flush_func)(my_transcoding, len, new_len);
	    out_p = *out_pos + len;
	    out_s = *out_pos + new_len - my_transcoder->max_output;
	}
	next_byte = *in_p++;
	if (next_byte < 0x80) {
	    new_mode = ISO_2022_GZ_ASCII;
	}
	else if (next_byte == 0x8E) {
	    new_mode = ISO_2022_GZ_JIS_X_0201_Katakana;
	    next_byte = *in_p++;
	}
	else if (next_byte == 0x8F) {
	    new_mode = ISO_2022_GZ_JIS_X_0212_1990;
	    next_byte = *in_p++;
	}
	else {
	    new_mode = ISO_2022_GZ_JIS_X_0208_1983;
	}
	if (cur_mode != new_mode)
	    cur_mode = select_iso_2022_mode(&out_p, new_mode);
	if (cur_mode < 0xFFFF) {
	    *out_p++ = next_byte & 0x7F;
	}
	else {
	    *out_p++ = next_byte & 0x7F;
	    *out_p++ = *in_p++ & 0x7F;
	}
    }
    if (cur_mode != ISO_2022_GZ_ASCII)
	cur_mode = select_iso_2022_mode(&out_p, ISO_2022_GZ_ASCII);
    /* cleanup */
    *in_pos  = in_p;
    *out_pos = out_p;
}

static const rb_transcoder
rb_from_ISO_2022_JP = {
    "ISO-2022-JP", "UTF-8", &from_EUC_JP, 8, 0,
    &from_iso_2022_jp_transcoder_preprocessor, NULL,
};

static const rb_transcoder
rb_to_ISO_2022_JP = {
    "UTF-8", "ISO-2022-JP", &to_EUC_JP, 8, 1,
    NULL, &to_iso_2022_jp_transcoder_postprocessor,
};

void
Init_japanese(void)
{
<%= transcode_register_code %>
    rb_register_transcoder(&rb_from_ISO_2022_JP);
    rb_register_transcoder(&rb_to_ISO_2022_JP);
}
