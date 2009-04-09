/*
 *  NKF - Ruby extension for Network Kanji Filter
 *
 *  original nkf2.x is maintained at http://sourceforge.jp/projects/nkf/
 *
 *  $Id$
 *
 */

#define RUBY_NKF_REVISION "$Revision$"
#define RUBY_NKF_VERSION NKF_VERSION " (" NKF_RELEASE_DATE ")"

#include "ruby.h"

/* Encoding Constants */
#define	_AUTO		0
#define	_JIS		1
#define	_EUC		2
#define	_SJIS		3
#define	_BINARY		4
#define	_NOCONV		4
#define	_ASCII		5
/* 0b011x is reserved for UTF-8 Family */
#define	_UTF8		6
/* 0b10xx is reserved for UTF-16 Family */
#define	_UTF16		8
/* 0b11xx is reserved for UTF-32 Family */
#define	_UTF32		12
#define	_OTHER		16
#define	_UNKNOWN	_AUTO

/* Replace nkf's getchar/putchar for variable modification */
/* we never use getc, ungetc */

#undef getc
#undef ungetc
#define getc(f)         (input_ctr>=i_len?-1:input[input_ctr++])
#define ungetc(c,f)     input_ctr--

#define INCSIZE         32
#undef putchar
#undef TRUE
#undef FALSE
#define putchar(c)      rb_nkf_putchar(c)

/* Input/Output pointers */

static unsigned char *output;
static unsigned char *input;
static int input_ctr;
static int i_len;
static int output_ctr;
static int o_len;
static int incsize;

static VALUE result;

static int
rb_nkf_putchar(c)
  unsigned int c;
{
  if (output_ctr >= o_len) {
    o_len += incsize;
    rb_str_resize(result, o_len);
    incsize *= 2;
    output = (unsigned char *)RSTRING(result)->ptr;
  }
  output[output_ctr++] = c;

  return c;
}

/* Include kanji filter main part */
/* getchar and putchar will be replaced during inclusion */

#define PERL_XS 1
#include "nkf-utf8/config.h"
#include "nkf-utf8/utf8tbl.c"
#include "nkf-utf8/nkf.c"

int nkf_split_options(arg)
    const char* arg;
{
    int count = 0;
    unsigned char option[256];
    int i = 0, j = 0;
    int is_escaped = FALSE;
    int is_single_quoted = FALSE;
    int is_double_quoted = FALSE;
    for(i = 0; arg[i]; i++){
	if(j == 255){
	    return -1;
	}else if(is_single_quoted){
	    if(arg[i] == '\''){
		is_single_quoted = FALSE;
	    }else{
		option[j++] = arg[i];
	    }
	}else if(is_escaped){
	    is_escaped = FALSE;
	    option[j++] = arg[i];
	}else if(arg[i] == '\\'){
	    is_escaped = TRUE;
	}else if(is_double_quoted){
	    if(arg[i] == '"'){
		is_double_quoted = FALSE;
	    }else{
		option[j++] = arg[i];
	    }
	}else if(arg[i] == '\''){
	    is_single_quoted = TRUE;
	}else if(arg[i] == '"'){
	    is_double_quoted = TRUE;
	}else if(arg[i] == ' '){
	    option[j] = '\0';
	    options(option);
	    j = 0;
	}else{
	    option[j++] = arg[i];
	}
    }
    if(j){
	option[j] = '\0';
	options(option);
    }
    return count;
}

/*
 *  call-seq:
 *     NKF.nkf(opt, str)   -> string
 *
 *  Convert _str_ and return converted result.
 *  Conversion details are specified by _opt_ as String.
 *
 *     require 'nkf'
 *     output = NKF.nkf("-s", input)
 *
 *  *Note*
 *  By default, nkf decodes MIME encoded string.
 *  If you want not to decode input, use NKF.nkf with <b>-m0</b> flag.
 */

static VALUE
rb_nkf_kconv(obj, opt, src)
  VALUE obj, opt, src;
{
  char *opt_ptr, *opt_end;
  volatile VALUE v;

  reinit();
  StringValue(opt);
  opt_ptr = RSTRING(opt)->ptr;
  opt_end = opt_ptr + RSTRING(opt)->len;
  nkf_split_options(opt_ptr);

  incsize = INCSIZE;

  input_ctr = 0;
  StringValue(src);
  input = (unsigned char *)RSTRING(src)->ptr;
  i_len = RSTRING(src)->len;
  result = rb_str_new(0, i_len*3 + 10);
  v = result;

  output_ctr = 0;
  output     = (unsigned char *)RSTRING(result)->ptr;
  o_len      = RSTRING(result)->len;
  *output    = '\0';

  if(x0201_f == WISH_TRUE)
    x0201_f = ((!iso2022jp_f)? TRUE : NO_X0201);

  kanji_convert(NULL);
  RSTRING(result)->ptr[output_ctr] = '\0';
  RSTRING(result)->len = output_ctr;
  OBJ_INFECT(result, src);

  return result;
}


/*
 *  call-seq:
 *     NKF.guess1(str)  -> integer
 *
 *  Returns guessed encoding of _str_ as integer.
 *
 *  Algorithm described in:
 *  Ken Lunde. `Understanding Japanese Information Processing'
 *  Sebastopol, CA: O'Reilly & Associates.
 *
 *      case NKF.guess1(input)
 *      when NKF::JIS
 *        "ISO-2022-JP"
 *      when NKF::SJIS
 *        "Shift_JIS"
 *      when NKF::EUC
 *        "EUC-JP"
 *      when NKF::UNKNOWN
 *        "UNKNOWN(ASCII)"
 *      when NKF::BINARY
 *        "BINARY"
 *      end
 */

static VALUE
rb_nkf_guess1(obj, src)
  VALUE obj, src;
{
  unsigned char *p;
  unsigned char *pend;
  int sequence_counter = 0;

  StringValue(src);
  p = (unsigned char *)RSTRING(src)->ptr;
  pend = p + RSTRING(src)->len;
  if (p == pend) return INT2FIX(_UNKNOWN);

#define INCR do {\
      p++;\
      if (p==pend) return INT2FIX(_UNKNOWN);\
      sequence_counter++;\
      if (sequence_counter % 2 == 1 && *p != 0xa4)\
	sequence_counter = 0;\
      if (6 <= sequence_counter) {\
	  sequence_counter = 0;\
	  return INT2FIX(_EUC);\
      }\
  } while (0)

  if (*p == 0xa4)
    sequence_counter = 1;

  while (p<pend) {
    if (*p == '\033') {
      return INT2FIX(_JIS);
    }
    if (*p < '\006' || *p == 0x7f || *p == 0xff) {
      return INT2FIX(_BINARY);
    }
    if (0x81 <= *p && *p <= 0x8d) {
      return INT2FIX(_SJIS);
    }
    if (0x8f <= *p && *p <= 0x9f) {
      return INT2FIX(_SJIS);
    }
    if (*p == 0x8e) {	/* SS2 */
      INCR;
      if ((0x40 <= *p && *p <= 0x7e) ||
	  (0x80 <= *p && *p <= 0xa0) ||
	  (0xe0 <= *p && *p <= 0xfc))
	return INT2FIX(_SJIS);
    }
    else if (0xa1 <= *p && *p <= 0xdf) {
      INCR;
      if (0xf0 <= *p && *p <= 0xfe)
	return INT2FIX(_EUC);
      if (0xe0 <= *p && *p <= 0xef) {
	while (p < pend && *p >= 0x40) {
	  if (*p >= 0x81) {
	    if (*p <= 0x8d || (0x8f <= *p && *p <= 0x9f)) {
	      return INT2FIX(_SJIS);
	    }
	    else if (0xfd <= *p && *p <= 0xfe) {
	      return INT2FIX(_EUC);
	    }
	  }
	  INCR;
	}
      }
      else if (*p <= 0x9f) {
	return INT2FIX(_SJIS);
      }
    }
    else if (0xf0 <= *p && *p <= 0xfe) {
      return INT2FIX(_EUC);
    }
    else if (0xe0 <= *p && *p <= 0xef) {
      INCR;
      if ((0x40 <= *p && *p <= 0x7e) ||
	  (0x80 <= *p && *p <= 0xa0)) {
	return INT2FIX(_SJIS);
      }
      if (0xfd <= *p && *p <= 0xfe) {
	return INT2FIX(_EUC);
      }
    }
    INCR;
  }
  return INT2FIX(_UNKNOWN);
}


/*
 *  call-seq:
 *     NKF.guess2(str)  -> integer
 *
 *  Returns guessed encoding of _str_ as integer by nkf routine.
 *
 *     case NKF.guess(input)
 *     when NKF::ASCII
 *       "ASCII"
 *     when NKF::JIS
 *       "ISO-2022-JP"
 *     when NKF::SJIS
 *       "Shift_JIS"
 *     when NKF::EUC
 *       "EUC-JP"
 *     when NKF::UTF8
 *       "UTF-8"
 *     when NKF::UTF16
 *       "UTF-16"
 *     when NKF::UNKNOWN
 *       "UNKNOWN"
 *     when NKF::BINARY
 *       "BINARY"
 *     end
 */

static VALUE
rb_nkf_guess2(obj, src)
  VALUE obj, src;
{
  int code = _BINARY;

  reinit();

  input_ctr = 0;
  StringValue(src);
  input = (unsigned char *)RSTRING(src)->ptr;
  i_len = RSTRING(src)->len;

  if(x0201_f == WISH_TRUE)
    x0201_f = ((!iso2022jp_f)? TRUE : NO_X0201);

  guess_f = TRUE;
  kanji_convert( NULL );
  guess_f = FALSE;

  if (!is_inputcode_mixed) {
    if (strcmp(input_codename, "") == 0) {
      code = _ASCII;
    } else if (strcmp(input_codename, "ISO-2022-JP") == 0) {
      code = _JIS;
    } else if (strcmp(input_codename, "EUC-JP") == 0) {
      code = _EUC;
    } else if (strcmp(input_codename, "Shift_JIS") == 0) {
      code = _SJIS;
    } else if (strcmp(input_codename, "UTF-8") == 0) {
      code = _UTF8;
    } else if (strcmp(input_codename, "UTF-16") == 0) {
      code = _UTF16;
    } else if (strlen(input_codename) > 0) {
      code = _UNKNOWN;
    }
  }

  return INT2FIX( code );
}


/*
 *  NKF - Ruby extension for Network Kanji Filter 
 *
 *  == Description
 *
 *  This is a Ruby Extension version of nkf (Network Kanji Filter).
 *  It converts the first argument and return converted result. Conversion
 *  details are specified by flags as the first argument.
 *
 *  *Nkf* is a yet another kanji code converter among networks, hosts and terminals.
 *  It converts input kanji code to designated kanji code
 *  such as ISO-2022-JP, Shift_JIS, EUC-JP, UTF-8 or UTF-16.
 *
 *  One of the most unique faculty of *nkf* is the guess of the input kanji encodings.
 *  It currently recognizes ISO-2022-JP, Shift_JIS, EUC-JP, UTF-8 and UTF-16.
 *  So users needn't set the input kanji code explicitly.
 *
 *  By default, X0201 kana is converted into X0208 kana.
 *  For X0201 kana, SO/SI, SSO and ESC-(-I methods are supported.
 *  For automatic code detection, nkf assumes no X0201 kana in Shift_JIS.
 *  To accept X0201 in Shift_JIS, use <b>-X</b>, <b>-x</b> or <b>-S</b>.
 *
 *  == Flags
 *
 *  === -b -u
 *
 *  Output is buffered (DEFAULT), Output is unbuffered.
 *
 *  === -j -s -e -w -w16
 *
 *  Output code is ISO-2022-JP (7bit JIS), Shift_JIS, EUC-JP,
 *  UTF-8N, UTF-16BE.
 *  Without this option and compile option, ISO-2022-JP is assumed.
 *
 *  === -J -S -E -W -W16
 *
 *  Input assumption is JIS 7 bit, Shift_JIS, EUC-JP,
 *  UTF-8, UTF-16LE.
 *
 *  ==== -J
 *
 *  Assume  JIS input. It also accepts EUC-JP.
 *  This is the default. This flag does not exclude Shift_JIS.
 *
 *  ==== -S
 *
 *  Assume Shift_JIS and X0201 kana input. It also accepts JIS.
 *  EUC-JP is recognized as X0201 kana. Without <b>-x</b> flag,
 *  X0201 kana (halfwidth kana) is converted into X0208.
 *
 *  ==== -E
 *
 *  Assume EUC-JP input. It also accepts JIS.
 *  Same as -J.
 *
 *  === -t
 *
 *  No conversion.
 *
 *  === -i_
 *
 *  Output sequence to designate JIS-kanji. (DEFAULT B)
 *
 *  === -o_
 *
 *  Output sequence to designate ASCII. (DEFAULT B)
 *
 *  === -r
 *
 *  {de/en}crypt ROT13/47
 *
 *  === -h[123] --hiragana --katakana --katakana-hiragana
 *
 *  [-h1 --hiragana] Katakana to Hiragana conversion.
 *
 *  [-h2 --katakana] Hiragana to Katakana conversion.
 *
 *  [-h3 --katakana-hiragana] Katakana to Hiragana and Hiragana to Katakana conversion.
 *
 *  === -T
 *
 *  Text mode output (MS-DOS)
 *
 *  === -l
 *
 *  ISO8859-1 (Latin-1) support
 *
 *  === -f[<code>m</code> [- <code>n</code>]]
 *
 *  Folding on <code>m</code> length with <code>n</code> margin in a line.
 *  Without this option, fold length is 60 and fold margin is 10.
 *
 *  === -F
 *
 *  New line preserving line folding.
 *
 *  === -Z[0-3]
 *
 *  Convert X0208 alphabet (Fullwidth Alphabets) to ASCII.
 *
 *  [-Z -Z0] Convert X0208 alphabet to ASCII.
 *
 *  [-Z1] Converts X0208 kankaku to single ASCII space.
 *
 *  [-Z2] Converts X0208 kankaku to double ASCII spaces.
 *
 *  [-Z3] Replacing Fullwidth >, <, ", & into '&gt;', '&lt;', '&quot;', '&amp;' as in HTML.
 *
 *  === -X -x
 *
 *  Assume X0201 kana in MS-Kanji.
 *  With <b>-X</b> or without this option, X0201 is converted into X0208 Kana.
 *  With <b>-x</b>, try to preserve X0208 kana and do not convert X0201 kana to X0208.
 *  In JIS output, ESC-(-I is used. In EUC output, SSO is used.
 *
 *  === -B[0-2]
 *
 *  Assume broken JIS-Kanji input, which lost ESC.
 *  Useful when your site is using old B-News Nihongo patch.
 *
 *  [-B1] allows any char after ESC-( or ESC-$.
 *
 *  [-B2] forces ASCII after NL.
 *
 *  === -I
 *
 *  Replacing non iso-2022-jp char into a geta character
 *  (substitute character in Japanese).
 *
 *  === -d -c
 *
 *  Delete \r in line feed, Add \r in line feed.
 *
 *  === -m[BQN0]
 *
 *  MIME ISO-2022-JP/ISO8859-1 decode. (DEFAULT)
 *  To see ISO8859-1 (Latin-1) -l is necessary.
 *
 *  [-mB] Decode MIME base64 encoded stream. Remove header or other part before
 *  conversion. 
 *
 *  [-mQ] Decode MIME quoted stream. '_' in quoted stream is converted to space.
 *
 *  [-mN] Non-strict decoding.
 *  It allows line break in the middle of the base64 encoding.
 *
 *  [-m0] No MIME decode.
 *
 *  === -M
 *
 *  MIME encode. Header style. All ASCII code and control characters are intact.
 *  Kanji conversion is performed before encoding, so this cannot be used as a picture encoder.
 *
 *  [-MB] MIME encode Base64 stream.
 *
 *  [-MQ] Perfome quoted encoding.
 *
 *  === -l
 *
 *  Input and output code is ISO8859-1 (Latin-1) and ISO-2022-JP.
 *  <b>-s</b>, <b>-e</b> and <b>-x</b> are not compatible with this option.
 *
 *  === -L[uwm]
 *
 *  new line mode
 *  Without this option, nkf doesn't convert line breaks.
 *
 *  [-Lu] unix (LF)
 *
 *  [-Lw] windows (CRLF)
 *
 *  [-Lm] mac (CR)
 *
 *  === --fj --unix --mac --msdos --windows
 *
 *  convert for these system
 *
 *  === --jis --euc --sjis --mime --base64
 *
 *  convert for named code
 *
 *  === --jis-input --euc-input --sjis-input --mime-input --base64-input
 *
 *  assume input system
 *
 *  === --ic=<code>input codeset</code> --oc=<code>output codeset</code>
 *
 *  Set the input or output codeset.
 *  NKF supports following codesets and those codeset name are case insensitive.
 *
 *  [ISO-2022-JP] a.k.a. RFC1468, 7bit JIS, JUNET
 *
 *  [EUC-JP (eucJP-nkf)] a.k.a. AT&T JIS, Japanese EUC, UJIS
 *
 *  [eucJP-ascii] a.k.a. x-eucjp-open-19970715-ascii
 *
 *  [eucJP-ms] a.k.a. x-eucjp-open-19970715-ms
 *
 *  [CP51932] Microsoft Version of EUC-JP.
 *
 *  [Shift_JIS] SJIS, MS-Kanji
 *
 *  [CP932] a.k.a. Windows-31J
 *
 *  [UTF-8] same as UTF-8N
 *
 *  [UTF-8N] UTF-8 without BOM
 *
 *  [UTF-8-BOM] UTF-8 with BOM
 *
 *  [UTF-16] same as UTF-16BE
 *
 *  [UTF-16BE] UTF-16 Big Endian without BOM
 *
 *  [UTF-16BE-BOM] UTF-16 Big Endian with BOM
 *
 *  [UTF-16LE] UTF-16 Little Endian without BOM
 *
 *  [UTF-16LE-BOM] UTF-16 Little Endian with BOM
 *
 *  [UTF8-MAC] NKDed UTF-8, a.k.a. UTF8-NFD (input only)
 *
 *  === --fb-{skip, html, xml, perl, java, subchar}
 *
 *  Specify the way that nkf handles unassigned characters.
 *  Without this option, --fb-skip is assumed.
 *
 *  === --prefix= <code>escape character</code> <code>target character</code> ..
 *
 *  When nkf converts to Shift_JIS,
 *  nkf adds a specified escape character to specified 2nd byte of Shift_JIS characters.
 *  1st byte of argument is the escape character and following bytes are target characters.
 *
 *  === --disable-cp932ext
 *
 *  Handle the characters extended in CP932 as unassigned characters.
 *
 *  === --cap-input
 *
 *  Decode hex encoded characters.
 *
 *  === --url-input
 *
 *  Unescape percent escaped characters.
 *
 *  === --
 *
 *  Ignore rest of -option.
 */

void
Init_nkf()
{
    /* hoge */
    VALUE mKconv = rb_define_module("NKF");
    /* hoge */

    rb_define_module_function(mKconv, "nkf", rb_nkf_kconv, 2);
    rb_define_module_function(mKconv, "guess1", rb_nkf_guess1, 1);
    rb_define_module_function(mKconv, "guess2", rb_nkf_guess2, 1);
    rb_define_alias(mKconv, "guess", "guess2");
    rb_define_alias(rb_singleton_class(mKconv), "guess", "guess2");

    /* Auto-Detect */
    rb_define_const(mKconv, "AUTO", INT2FIX(_AUTO));
    /* ISO-2022-JP */
    rb_define_const(mKconv, "JIS", INT2FIX(_JIS));
    /* EUC-JP */
    rb_define_const(mKconv, "EUC", INT2FIX(_EUC));
    /* Shift_JIS */
    rb_define_const(mKconv, "SJIS", INT2FIX(_SJIS));
    /* BINARY */
    rb_define_const(mKconv, "BINARY", INT2FIX(_BINARY));
    /* No conversion */
    rb_define_const(mKconv, "NOCONV", INT2FIX(_NOCONV));
    /* ASCII */
    rb_define_const(mKconv, "ASCII", INT2FIX(_ASCII));
    /* UTF-8 */
    rb_define_const(mKconv, "UTF8", INT2FIX(_UTF8));
    /* UTF-16 */
    rb_define_const(mKconv, "UTF16", INT2FIX(_UTF16));
    /* UTF-32 */
    rb_define_const(mKconv, "UTF32", INT2FIX(_UTF32));
    /* UNKNOWN */
    rb_define_const(mKconv, "UNKNOWN", INT2FIX(_UNKNOWN));
    /* Full version string of nkf */
    rb_define_const(mKconv, "VERSION", rb_str_new2(RUBY_NKF_VERSION));
    /* Version of nkf */
    rb_define_const(mKconv, "NKF_VERSION", rb_str_new2(NKF_VERSION));
    /* Release date of nkf */
    rb_define_const(mKconv, "NKF_RELEASE_DATE", rb_str_new2(NKF_RELEASE_DATE));
}
