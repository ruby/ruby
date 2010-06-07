/** Network Kanji Filter. (PDS Version)
************************************************************************
** Copyright (C) 1987, Fujitsu LTD. (Itaru ICHIKAWA)
** 連絡先： （株）富士通研究所　ソフト３研　市川　至 
** （E-Mail Address: ichikawa@flab.fujitsu.co.jp）
** Copyright (C) 1996,1998
** Copyright (C) 2002
** 連絡先： 琉球大学情報工学科 河野 真治  mime/X0208 support
** （E-Mail Address: kono@ie.u-ryukyu.ac.jp）
** 連絡先： COW for DOS & Win16 & Win32 & OS/2
** （E-Mail Address: GHG00637@niftyserve.or.p）
**
**    このソースのいかなる複写，改変，修正も許諾します。ただし、
**    その際には、誰が貢献したを示すこの部分を残すこと。
**    再配布や雑誌の付録などの問い合わせも必要ありません。
**    営利利用も上記に反しない範囲で許可します。
**    バイナリの配布の際にはversion messageを保存することを条件とします。
**    このプログラムについては特に何の保証もしない、悪しからず。
**
**    Everyone is permitted to do anything on this program 
**    including copying, modifying, improving,
**    as long as you don't try to pretend that you wrote it.
**    i.e., the above copyright notice has to appear in all copies.  
**    Binary distribution requires original version messages.
**    You don't have to ask before copying, redistribution or publishing.
**    THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE.
***********************************************************************/

/***********************************************************************
** UTF-8 サポートについて
**    従来の nkf と入れかえてそのまま使えるようになっています
**    nkf -e などとして起動すると、自動判別で UTF-8 と判定されれば、
**    そのまま euc-jp に変換されます
**
**    まだバグがある可能性が高いです。
**    (特に自動判別、コード混在、エラー処理系)
**
**    何か問題を見つけたら、
**        E-Mail: furukawa@tcp-ip.or.jp
**    まで御連絡をお願いします。
***********************************************************************/
/* $Id$ */
#define NKF_VERSION "2.0.8"
#define NKF_RELEASE_DATE "2008-11-08"
#include "config.h"
#include "utf8tbl.h"

#define COPY_RIGHT \
    "Copyright (C) 1987, FUJITSU LTD. (I.Ichikawa),2000 S. Kono, COW\n" \
    "Copyright (C) 2002-2008 Kono, Furukawa, Naruse, mastodon"


/*
**
**
**
** USAGE:       nkf [flags] [file] 
**
** Flags:
** b    Output is buffered             (DEFAULT)
** u    Output is unbuffered
**
** t    no operation
**
** j    Output code is JIS 7 bit        (DEFAULT SELECT) 
** s    Output code is MS Kanji         (DEFAULT SELECT) 
** e    Output code is AT&T JIS         (DEFAULT SELECT) 
** w    Output code is AT&T JIS         (DEFAULT SELECT) 
** l    Output code is JIS 7bit and ISO8859-1 Latin-1
**
** m    MIME conversion for ISO-2022-JP
** I    Convert non ISO-2022-JP charactor to GETA by Pekoe <pekoe@lair.net>
** i_ Output sequence to designate JIS-kanji (DEFAULT_J)
** o_ Output sequence to designate single-byte roman characters (DEFAULT_R)
** M    MIME output conversion 
**
** r  {de/en}crypt ROT13/47
**
** v  display Version
**
** T  Text mode output        (for MS-DOS)
**
** x    Do not convert X0201 kana into X0208
** Z    Convert X0208 alphabet to ASCII
**
** f60  fold option
**
** m    MIME decode
** B    try to fix broken JIS, missing Escape
** B[1-9]  broken level
**
** O   Output to 'nkf.out' file or last file name
** d   Delete \r in line feed 
** c   Add \r in line feed 
** -- other long option
** -- ignore following option (don't use with -O )
**
**/

#if (defined(__TURBOC__) || defined(_MSC_VER) || defined(LSI_C) || defined(__MINGW32__) || defined(__EMX__) || defined(__MSDOS__) || defined(__WINDOWS__) || defined(__DOS__) || defined(__OS2__)) && !defined(MSDOS)
#define MSDOS
#if (defined(__Win32__) || defined(_WIN32)) && !defined(__WIN32__)
#define __WIN32__
#endif
#endif

#ifdef PERL_XS
#undef OVERWRITE
#endif

#ifndef PERL_XS
#include <stdio.h>
#endif

#include <stdlib.h>
#include <string.h>

#if defined(MSDOS) || defined(__OS2__)
#include <fcntl.h>
#include <io.h>
#if defined(_MSC_VER) || defined(__WATCOMC__)
#define mktemp _mktemp
#endif
#endif

#ifdef MSDOS
#ifdef LSI_C
#define setbinmode(fp) fsetbin(fp)
#elif defined(__DJGPP__)
#include <libc/dosio.h>
#define setbinmode(fp) djgpp_setbinmode(fp)
#else /* Microsoft C, Turbo C */
#define setbinmode(fp) setmode(fileno(fp), O_BINARY)
#endif
#else /* UNIX */
#define setbinmode(fp)
#endif

#if defined(__DJGPP__)
void  djgpp_setbinmode(FILE *fp)
{
    /* we do not use libc's setmode(), which changes COOKED/RAW mode in device. */
    int fd, m;
    fd = fileno(fp);
    m = (__file_handle_modes[fd] & (~O_TEXT)) | O_BINARY;
    __file_handle_set(fd, m);
}
#endif

#ifdef _IOFBF /* SysV and MSDOS, Windows */
#define       setvbuffer(fp, buf, size)       setvbuf(fp, buf, _IOFBF, size)
#else /* BSD */
#define       setvbuffer(fp, buf, size)       setbuffer(fp, buf, size)
#endif

/*Borland C++ 4.5 EasyWin*/
#if defined(__TURBOC__) && defined(_Windows) && !defined(__WIN32__) /*Easy Win */
#define         EASYWIN
#ifndef __WIN16__
#define __WIN16__
#endif
#include <windows.h>
#endif

#ifdef OVERWRITE
/* added by satoru@isoternet.org */
#if defined(__EMX__)
#include <sys/types.h>
#endif
#include <sys/stat.h>
#if !defined(MSDOS) || defined(__DJGPP__) /* UNIX, djgpp */
#include <unistd.h>
#if defined(__WATCOMC__)
#include <sys/utime.h>
#else
#include <utime.h>
#endif
#else /* defined(MSDOS) */
#ifdef __WIN32__
#ifdef __BORLANDC__ /* BCC32 */
#include <utime.h>
#else /* !defined(__BORLANDC__) */
#include <sys/utime.h>
#endif /* (__BORLANDC__) */
#else /* !defined(__WIN32__) */
#if defined(_MSC_VER) || defined(__MINGW32__) || defined(__WATCOMC__) || defined(__OS2__) || defined(__EMX__) || defined(__IBMC__) || defined(__IBMCPP__)  /* VC++, MinGW, Watcom, emx+gcc, IBM VAC++ */
#include <sys/utime.h>
#elif defined(__TURBOC__) /* BCC */
#include <utime.h>
#elif defined(LSI_C) /* LSI C */
#endif /* (__WIN32__) */
#endif
#endif
#endif

#define         FALSE   0
#define         TRUE    1

/* state of output_mode and input_mode  

   c2           0 means ASCII
                X0201
                ISO8859_1
                X0208
                EOF      all termination
   c1           32bit data

 */

#define         ASCII           0
#define         X0208           1
#define         X0201           2
#define         ISO8859_1       8
#define         NO_X0201        3
#define         X0212      0x2844
#define         X0213_1    0x284F
#define         X0213_2    0x2850

/* Input Assumption */

#define         JIS_INPUT       4
#define         EUC_INPUT      16
#define         SJIS_INPUT      5
#define         LATIN1_INPUT    6
#define         FIXED_MIME      7
#define         STRICT_MIME     8

/* MIME ENCODE */

#define        	ISO2022JP       9
#define  	JAPANESE_EUC   10
#define		SHIFT_JIS      11

#define		UTF8           12
#define		UTF8_INPUT     13
#define		UTF16_INPUT    1015
#define		UTF32_INPUT    1017

/* byte order */

#define		ENDIAN_BIG	1234
#define		ENDIAN_LITTLE	4321
#define		ENDIAN_2143	2143
#define		ENDIAN_3412	3412

#define         WISH_TRUE      15

/* ASCII CODE */

#define         BS      0x08
#define         TAB     0x09
#define         NL      0x0a
#define         CR      0x0d
#define         ESC     0x1b
#define         SPACE   0x20
#define         AT      0x40
#define         SSP     0xa0
#define         DEL     0x7f
#define         SI      0x0f
#define         SO      0x0e
#define         SSO     0x8e
#define         SS3     0x8f

#define		is_alnum(c)  \
            (('a'<=c && c<='z')||('A'<= c && c<='Z')||('0'<=c && c<='9'))

/* I don't trust portablity of toupper */
#define nkf_toupper(c)  (('a'<=c && c<='z')?(c-('a'-'A')):c)
#define nkf_isoctal(c)  ('0'<=c && c<='7')
#define nkf_isdigit(c)  ('0'<=c && c<='9')
#define nkf_isxdigit(c)  (nkf_isdigit(c) || ('a'<=c && c<='f') || ('A'<=c && c <= 'F'))
#define nkf_isblank(c) (c == SPACE || c == TAB)
#define nkf_isspace(c) (nkf_isblank(c) || c == CR || c == NL)
#define nkf_isalpha(c) (('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z'))
#define nkf_isalnum(c) (nkf_isdigit(c) || nkf_isalpha(c))
#define nkf_isprint(c) (' '<=c && c<='~')
#define nkf_isgraph(c) ('!'<=c && c<='~')
#define hex2bin(c) (('0'<=c&&c<='9') ? (c-'0') : \
                    ('A'<=c&&c<='F') ? (c-'A'+10) : \
                    ('a'<=c&&c<='f') ? (c-'a'+10) : 0 )
#define is_eucg3(c2) (((unsigned short)c2 >> 8) == SS3)

#define CP932_TABLE_BEGIN 0xFA
#define CP932_TABLE_END   0xFC
#define CP932INV_TABLE_BEGIN 0xED
#define CP932INV_TABLE_END   0xEE
#define is_ibmext_in_sjis(c2) (CP932_TABLE_BEGIN <= c2 && c2 <= CP932_TABLE_END)

#define         HOLD_SIZE       1024
#if defined(INT_IS_SHORT)
#define         IOBUF_SIZE      2048
#else
#define         IOBUF_SIZE      16384
#endif

#define         DEFAULT_J       'B'
#define         DEFAULT_R       'B'

#define         SJ0162  0x00e1          /* 01 - 62 ku offset */
#define         SJ6394  0x0161          /* 63 - 94 ku offset */

#define         RANGE_NUM_MAX   18
#define         GETA1   0x22
#define         GETA2   0x2e


#if defined(UTF8_OUTPUT_ENABLE) || defined(UTF8_INPUT_ENABLE)
#define sizeof_euc_to_utf8_1byte 94
#define sizeof_euc_to_utf8_2bytes 94
#define sizeof_utf8_to_euc_C2 64
#define sizeof_utf8_to_euc_E5B8 64
#define sizeof_utf8_to_euc_2bytes 112
#define sizeof_utf8_to_euc_3bytes 16
#endif

/* MIME preprocessor */

#ifdef EASYWIN /*Easy Win */
extern POINT _BufferSize;
#endif

struct input_code{
    char *name;
    nkf_char stat;
    nkf_char score;
    nkf_char index;
    nkf_char buf[3];
    void (*status_func)(struct input_code *, nkf_char);
    nkf_char (*iconv_func)(nkf_char c2, nkf_char c1, nkf_char c0);
    int _file_stat;
};

static char *input_codename = "";

#ifndef PERL_XS
static const char *CopyRight = COPY_RIGHT;
#endif
#if !defined(PERL_XS) && !defined(WIN32DLL)
static  nkf_char     noconvert(FILE *f);
#endif
static  void    module_connection(void);
static  nkf_char     kanji_convert(FILE *f);
static  nkf_char     h_conv(FILE *f,nkf_char c2,nkf_char c1);
static  nkf_char     push_hold_buf(nkf_char c2);
static  void    set_iconv(nkf_char f, nkf_char (*iconv_func)(nkf_char c2,nkf_char c1,nkf_char c0));
static  nkf_char     s_iconv(nkf_char c2,nkf_char c1,nkf_char c0);
static  nkf_char     s2e_conv(nkf_char c2, nkf_char c1, nkf_char *p2, nkf_char *p1);
static  nkf_char     e_iconv(nkf_char c2,nkf_char c1,nkf_char c0);
#if defined(UTF8_INPUT_ENABLE) || defined(UTF8_OUTPUT_ENABLE)
/* UCS Mapping
 * 0: Shift_JIS, eucJP-ascii
 * 1: eucJP-ms
 * 2: CP932, CP51932
 */
#define UCS_MAP_ASCII 0
#define UCS_MAP_MS    1
#define UCS_MAP_CP932 2
static int ms_ucs_map_f = UCS_MAP_ASCII;
#endif
#ifdef UTF8_INPUT_ENABLE
/* no NEC special, NEC-selected IBM extended and IBM extended characters */
static  int     no_cp932ext_f = FALSE;
/* ignore ZERO WIDTH NO-BREAK SPACE */
static  int     no_best_fit_chars_f = FALSE;
static  int     input_endian = ENDIAN_BIG;
static  nkf_char     unicode_subchar = '?'; /* the regular substitution character */
static  void    nkf_each_char_to_hex(void (*f)(nkf_char c2,nkf_char c1), nkf_char c);
static  void    encode_fallback_html(nkf_char c);
static  void    encode_fallback_xml(nkf_char c);
static  void    encode_fallback_java(nkf_char c);
static  void    encode_fallback_perl(nkf_char c);
static  void    encode_fallback_subchar(nkf_char c);
static  void    (*encode_fallback)(nkf_char c) = NULL;
static  nkf_char     w2e_conv(nkf_char c2,nkf_char c1,nkf_char c0,nkf_char *p2,nkf_char *p1);
static  nkf_char     w_iconv(nkf_char c2,nkf_char c1,nkf_char c0);
static  nkf_char     w_iconv16(nkf_char c2,nkf_char c1,nkf_char c0);
static  nkf_char     w_iconv32(nkf_char c2,nkf_char c1,nkf_char c0);
static  nkf_char	unicode_to_jis_common(nkf_char c2,nkf_char c1,nkf_char c0,nkf_char *p2,nkf_char *p1);
static  nkf_char	w_iconv_common(nkf_char c1,nkf_char c0,const unsigned short *const *pp,nkf_char psize,nkf_char *p2,nkf_char *p1);
static  void    w16w_conv(nkf_char val, nkf_char *p2, nkf_char *p1, nkf_char *p0);
static  nkf_char     ww16_conv(nkf_char c2, nkf_char c1, nkf_char c0);
static  nkf_char     w16e_conv(nkf_char val,nkf_char *p2,nkf_char *p1);
static  void    w_status(struct input_code *, nkf_char);
#endif
#ifdef UTF8_OUTPUT_ENABLE
static  int     output_bom_f = FALSE;
static  int     output_endian = ENDIAN_BIG;
static  nkf_char     e2w_conv(nkf_char c2,nkf_char c1);
static  void    w_oconv(nkf_char c2,nkf_char c1);
static  void    w_oconv16(nkf_char c2,nkf_char c1);
static  void    w_oconv32(nkf_char c2,nkf_char c1);
#endif
static  void    e_oconv(nkf_char c2,nkf_char c1);
static  nkf_char     e2s_conv(nkf_char c2, nkf_char c1, nkf_char *p2, nkf_char *p1);
static  void    s_oconv(nkf_char c2,nkf_char c1);
static  void    j_oconv(nkf_char c2,nkf_char c1);
static  void    fold_conv(nkf_char c2,nkf_char c1);
static  void    cr_conv(nkf_char c2,nkf_char c1);
static  void    z_conv(nkf_char c2,nkf_char c1);
static  void    rot_conv(nkf_char c2,nkf_char c1);
static  void    hira_conv(nkf_char c2,nkf_char c1);
static  void    base64_conv(nkf_char c2,nkf_char c1);
static  void    iso2022jp_check_conv(nkf_char c2,nkf_char c1);
static  void    no_connection(nkf_char c2,nkf_char c1);
static  nkf_char     no_connection2(nkf_char c2,nkf_char c1,nkf_char c0);

static  void    code_score(struct input_code *ptr);
static  void    code_status(nkf_char c);

static  void    std_putc(nkf_char c);
static  nkf_char     std_getc(FILE *f);
static  nkf_char     std_ungetc(nkf_char c,FILE *f);

static  nkf_char     broken_getc(FILE *f);
static  nkf_char     broken_ungetc(nkf_char c,FILE *f);

static  nkf_char     mime_begin(FILE *f);
static  nkf_char     mime_getc(FILE *f);
static  nkf_char     mime_ungetc(nkf_char c,FILE *f);

static  void    switch_mime_getc(void);
static  void    unswitch_mime_getc(void);
static  nkf_char     mime_begin_strict(FILE *f);
static  nkf_char     mime_getc_buf(FILE *f);
static  nkf_char     mime_ungetc_buf(nkf_char c,FILE *f);
static  nkf_char     mime_integrity(FILE *f,const unsigned char *p);

static  nkf_char     base64decode(nkf_char c);
static  void    mime_prechar(nkf_char c2, nkf_char c1);
static  void    mime_putc(nkf_char c);
static  void    open_mime(nkf_char c);
static  void    close_mime(void);
static  void    eof_mime(void);
static  void    mimeout_addchar(nkf_char c);
#ifndef PERL_XS
static  void    usage(void);
static  void    version(void);
#endif
static  void    options(unsigned char *c);
#if defined(PERL_XS) || defined(WIN32DLL)
static  void    reinit(void);
#endif

/* buffers */

#if !defined(PERL_XS) && !defined(WIN32DLL)
static unsigned char   stdibuf[IOBUF_SIZE];
static unsigned char   stdobuf[IOBUF_SIZE];
#endif
static unsigned char   hold_buf[HOLD_SIZE*2];
static int             hold_count = 0;

/* MIME preprocessor fifo */

#define MIME_BUF_SIZE   (1024)    /* 2^n ring buffer */
#define MIME_BUF_MASK   (MIME_BUF_SIZE-1)   
#define Fifo(n)         mime_buf[(n)&MIME_BUF_MASK]
static unsigned char           mime_buf[MIME_BUF_SIZE];
static unsigned int            mime_top = 0;
static unsigned int            mime_last = 0;  /* decoded */
static unsigned int            mime_input = 0; /* undecoded */
static nkf_char (*mime_iconv_back)(nkf_char c2,nkf_char c1,nkf_char c0) = NULL;

/* flags */
static int             unbuf_f = FALSE;
static int             estab_f = FALSE;
static int             nop_f = FALSE;
static int             binmode_f = TRUE;       /* binary mode */
static int             rot_f = FALSE;          /* rot14/43 mode */
static int             hira_f = FALSE;          /* hira/kata henkan */
static int             input_f = FALSE;        /* non fixed input code  */
static int             alpha_f = FALSE;        /* convert JIx0208 alphbet to ASCII */
static int             mime_f = STRICT_MIME;   /* convert MIME B base64 or Q */
static int             mime_decode_f = FALSE;  /* mime decode is explicitly on */
static int             mimebuf_f = FALSE;      /* MIME buffered input */
static int             broken_f = FALSE;       /* convert ESC-less broken JIS */
static int             iso8859_f = FALSE;      /* ISO8859 through */
static int             mimeout_f = FALSE;       /* base64 mode */
#if defined(MSDOS) || defined(__OS2__) 
static int             x0201_f = TRUE;         /* Assume JISX0201 kana */
#else
static int             x0201_f = NO_X0201;     /* Assume NO JISX0201 */
#endif
static int             iso2022jp_f = FALSE;    /* convert ISO-2022-JP */

#ifdef UNICODE_NORMALIZATION
static int nfc_f = FALSE;
static nkf_char (*i_nfc_getc)(FILE *) = std_getc; /* input of ugetc */
static nkf_char (*i_nfc_ungetc)(nkf_char c ,FILE *f) = std_ungetc;
static nkf_char nfc_getc(FILE *f);
static nkf_char nfc_ungetc(nkf_char c,FILE *f);
#endif

#ifdef INPUT_OPTION
static int cap_f = FALSE;
static nkf_char (*i_cgetc)(FILE *) = std_getc; /* input of cgetc */
static nkf_char (*i_cungetc)(nkf_char c ,FILE *f) = std_ungetc;
static nkf_char cap_getc(FILE *f);
static nkf_char cap_ungetc(nkf_char c,FILE *f);

static int url_f = FALSE;
static nkf_char (*i_ugetc)(FILE *) = std_getc; /* input of ugetc */
static nkf_char (*i_uungetc)(nkf_char c ,FILE *f) = std_ungetc;
static nkf_char url_getc(FILE *f);
static nkf_char url_ungetc(nkf_char c,FILE *f);
#endif

#if defined(INT_IS_SHORT)
#define NKF_INT32_C(n)   (n##L)
#else
#define NKF_INT32_C(n)   (n)
#endif
#define PREFIX_EUCG3	NKF_INT32_C(0x8F00)
#define CLASS_MASK	NKF_INT32_C(0xFF000000)
#define CLASS_UNICODE	NKF_INT32_C(0x01000000)
#define VALUE_MASK	NKF_INT32_C(0x00FFFFFF)
#define UNICODE_MAX	NKF_INT32_C(0x0010FFFF)
#define is_unicode_capsule(c) ((c & CLASS_MASK) == CLASS_UNICODE)
#define is_unicode_bmp(c) ((c & VALUE_MASK) <= NKF_INT32_C(0xFFFF))

#ifdef NUMCHAR_OPTION
static int numchar_f = FALSE;
static nkf_char (*i_ngetc)(FILE *) = std_getc; /* input of ugetc */
static nkf_char (*i_nungetc)(nkf_char c ,FILE *f) = std_ungetc;
static nkf_char numchar_getc(FILE *f);
static nkf_char numchar_ungetc(nkf_char c,FILE *f);
#endif

#ifdef CHECK_OPTION
static int noout_f = FALSE;
static void no_putc(nkf_char c);
static nkf_char debug_f = FALSE;
static void debug(const char *str);
static nkf_char (*iconv_for_check)(nkf_char c2,nkf_char c1,nkf_char c0) = 0;
#endif

static int guess_f = FALSE;
#if !defined PERL_XS
static  void    print_guessed_code(char *filename);
#endif
static  void    set_input_codename(char *codename);
static int is_inputcode_mixed = FALSE;
static int is_inputcode_set   = FALSE;

#ifdef EXEC_IO
static int exec_f = 0;
#endif

#ifdef SHIFTJIS_CP932
/* invert IBM extended characters to others */
static int cp51932_f = FALSE;

/* invert NEC-selected IBM extended characters to IBM extended characters */
static int cp932inv_f = TRUE;

/* static nkf_char cp932_conv(nkf_char c2, nkf_char c1); */
#endif /* SHIFTJIS_CP932 */

#ifdef X0212_ENABLE
static int x0212_f = FALSE;
static nkf_char x0212_shift(nkf_char c);
static nkf_char x0212_unshift(nkf_char c);
#endif
static int x0213_f = FALSE;

static unsigned char prefix_table[256];

static void set_code_score(struct input_code *ptr, nkf_char score);
static void clr_code_score(struct input_code *ptr, nkf_char score);
static void status_disable(struct input_code *ptr);
static void status_push_ch(struct input_code *ptr, nkf_char c);
static void status_clear(struct input_code *ptr);
static void status_reset(struct input_code *ptr);
static void status_reinit(struct input_code *ptr);
static void status_check(struct input_code *ptr, nkf_char c);
static void e_status(struct input_code *, nkf_char);
static void s_status(struct input_code *, nkf_char);

struct input_code input_code_list[] = {
    {"EUC-JP",    0, 0, 0, {0, 0, 0}, e_status, e_iconv, 0},
    {"Shift_JIS", 0, 0, 0, {0, 0, 0}, s_status, s_iconv, 0},
#ifdef UTF8_INPUT_ENABLE
    {"UTF-8",     0, 0, 0, {0, 0, 0}, w_status, w_iconv, 0},
    {"UTF-16",    0, 0, 0, {0, 0, 0},     NULL, w_iconv16, 0},
    {"UTF-32",    0, 0, 0, {0, 0, 0},     NULL, w_iconv32, 0},
#endif
    {0}
};

static int              mimeout_mode = 0;
static int              base64_count = 0;

/* X0208 -> ASCII converter */

/* fold parameter */
static int             f_line = 0;    /* chars in line */
static int             f_prev = 0;
static int             fold_preserve_f = FALSE; /* preserve new lines */
static int             fold_f  = FALSE;
static int             fold_len  = 0;

/* options */
static unsigned char   kanji_intro = DEFAULT_J;
static unsigned char   ascii_intro = DEFAULT_R;

/* Folding */

#define FOLD_MARGIN  10
#define DEFAULT_FOLD 60

static int             fold_margin  = FOLD_MARGIN;

/* converters */

#ifdef DEFAULT_CODE_JIS
#   define  DEFAULT_CONV j_oconv
#endif
#ifdef DEFAULT_CODE_SJIS
#   define  DEFAULT_CONV s_oconv
#endif
#ifdef DEFAULT_CODE_EUC
#   define  DEFAULT_CONV e_oconv
#endif
#ifdef DEFAULT_CODE_UTF8
#   define  DEFAULT_CONV w_oconv
#endif

/* process default */
static void (*output_conv)(nkf_char c2,nkf_char c1) = DEFAULT_CONV;

static void (*oconv)(nkf_char c2,nkf_char c1) = no_connection;
/* s_iconv or oconv */
static nkf_char (*iconv)(nkf_char c2,nkf_char c1,nkf_char c0) = no_connection2;

static void (*o_zconv)(nkf_char c2,nkf_char c1) = no_connection;
static void (*o_fconv)(nkf_char c2,nkf_char c1) = no_connection;
static void (*o_crconv)(nkf_char c2,nkf_char c1) = no_connection;
static void (*o_rot_conv)(nkf_char c2,nkf_char c1) = no_connection;
static void (*o_hira_conv)(nkf_char c2,nkf_char c1) = no_connection;
static void (*o_base64conv)(nkf_char c2,nkf_char c1) = no_connection;
static void (*o_iso2022jp_check_conv)(nkf_char c2,nkf_char c1) = no_connection;

/* static redirections */

static  void   (*o_putc)(nkf_char c) = std_putc;

static  nkf_char    (*i_getc)(FILE *f) = std_getc; /* general input */
static  nkf_char    (*i_ungetc)(nkf_char c,FILE *f) =std_ungetc;

static  nkf_char    (*i_bgetc)(FILE *) = std_getc; /* input of mgetc */
static  nkf_char    (*i_bungetc)(nkf_char c ,FILE *f) = std_ungetc;

static  void   (*o_mputc)(nkf_char c) = std_putc ; /* output of mputc */

static  nkf_char    (*i_mgetc)(FILE *) = std_getc; /* input of mgetc */
static  nkf_char    (*i_mungetc)(nkf_char c ,FILE *f) = std_ungetc;

/* for strict mime */
static  nkf_char    (*i_mgetc_buf)(FILE *) = std_getc; /* input of mgetc_buf */
static  nkf_char    (*i_mungetc_buf)(nkf_char c,FILE *f) = std_ungetc;

/* Global states */
static int output_mode = ASCII,    /* output kanji mode */
           input_mode =  ASCII,    /* input kanji mode */
           shift_mode =  FALSE;    /* TRUE shift out, or X0201  */
static int mime_decode_mode =   FALSE;    /* MIME mode B base64, Q hex */

/* X0201 / X0208 conversion tables */

/* X0201 kana conversion table */
/* 90-9F A0-DF */
static const
unsigned char cv[]= {
    0x21,0x21,0x21,0x23,0x21,0x56,0x21,0x57,
    0x21,0x22,0x21,0x26,0x25,0x72,0x25,0x21,
    0x25,0x23,0x25,0x25,0x25,0x27,0x25,0x29,
    0x25,0x63,0x25,0x65,0x25,0x67,0x25,0x43,
    0x21,0x3c,0x25,0x22,0x25,0x24,0x25,0x26,
    0x25,0x28,0x25,0x2a,0x25,0x2b,0x25,0x2d,
    0x25,0x2f,0x25,0x31,0x25,0x33,0x25,0x35,
    0x25,0x37,0x25,0x39,0x25,0x3b,0x25,0x3d,
    0x25,0x3f,0x25,0x41,0x25,0x44,0x25,0x46,
    0x25,0x48,0x25,0x4a,0x25,0x4b,0x25,0x4c,
    0x25,0x4d,0x25,0x4e,0x25,0x4f,0x25,0x52,
    0x25,0x55,0x25,0x58,0x25,0x5b,0x25,0x5e,
    0x25,0x5f,0x25,0x60,0x25,0x61,0x25,0x62,
    0x25,0x64,0x25,0x66,0x25,0x68,0x25,0x69,
    0x25,0x6a,0x25,0x6b,0x25,0x6c,0x25,0x6d,
    0x25,0x6f,0x25,0x73,0x21,0x2b,0x21,0x2c,
    0x00,0x00};


/* X0201 kana conversion table for daguten */
/* 90-9F A0-DF */
static const
unsigned char dv[]= { 
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x25,0x74,
    0x00,0x00,0x00,0x00,0x25,0x2c,0x25,0x2e,
    0x25,0x30,0x25,0x32,0x25,0x34,0x25,0x36,
    0x25,0x38,0x25,0x3a,0x25,0x3c,0x25,0x3e,
    0x25,0x40,0x25,0x42,0x25,0x45,0x25,0x47,
    0x25,0x49,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x25,0x50,0x25,0x53,
    0x25,0x56,0x25,0x59,0x25,0x5c,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00};

/* X0201 kana conversion table for han-daguten */
/* 90-9F A0-DF */
static const
unsigned char ev[]= { 
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x25,0x51,0x25,0x54,
    0x25,0x57,0x25,0x5a,0x25,0x5d,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00};


/* X0208 kigou conversion table */
/* 0x8140 - 0x819e */
static const
unsigned char fv[] = {

    0x00,0x00,0x00,0x00,0x2c,0x2e,0x00,0x3a,
    0x3b,0x3f,0x21,0x00,0x00,0x27,0x60,0x00,
    0x5e,0x00,0x5f,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x2d,0x00,0x2f,
    0x5c,0x00,0x00,0x7c,0x00,0x00,0x60,0x27,
    0x22,0x22,0x28,0x29,0x00,0x00,0x5b,0x5d,
    0x7b,0x7d,0x3c,0x3e,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x2b,0x2d,0x00,0x00,
    0x00,0x3d,0x00,0x3c,0x3e,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x24,0x00,0x00,0x25,0x23,0x26,0x2a,0x40,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
} ;


#define    CRLF      1

static int             file_out_f = FALSE;
#ifdef OVERWRITE
static int             overwrite_f = FALSE;
static int             preserve_time_f = FALSE;
static int             backup_f = FALSE;
static char            *backup_suffix = "";
static char *get_backup_filename(const char *suffix, const char *filename);
#endif

static int             crmode_f = 0;   /* CR, NL, CRLF */
#ifdef EASYWIN /*Easy Win */
static int             end_check;
#endif /*Easy Win */

#define STD_GC_BUFSIZE (256)
nkf_char std_gc_buf[STD_GC_BUFSIZE];
nkf_char std_gc_ndx;

#ifdef WIN32DLL
#include "nkf32dll.c"
#elif defined(PERL_XS)
#else /* WIN32DLL */
int main(int argc, char **argv)
{
    FILE  *fin;
    unsigned char  *cp;

    char *outfname = NULL;
    char *origfname;

#ifdef EASYWIN /*Easy Win */
    _BufferSize.y = 400;/*Set Scroll Buffer Size*/
#endif

    for (argc--,argv++; (argc > 0) && **argv == '-'; argc--, argv++) {
        cp = (unsigned char *)*argv;
        options(cp);
#ifdef EXEC_IO
        if (exec_f){
            int fds[2], pid;
            if (pipe(fds) < 0 || (pid = fork()) < 0){
                abort();
            }
            if (pid == 0){
                if (exec_f > 0){
                    close(fds[0]);
                    dup2(fds[1], 1);
                }else{
                    close(fds[1]);
                    dup2(fds[0], 0);
                }
                execvp(argv[1], &argv[1]);
            }
            if (exec_f > 0){
                close(fds[1]);
                dup2(fds[0], 0);
            }else{
                close(fds[0]);
                dup2(fds[1], 1);
            }
            argc = 0;
            break;
        }
#endif
    }
    if(x0201_f == WISH_TRUE)
         x0201_f = ((!iso2022jp_f)? TRUE : NO_X0201);

    if (binmode_f == TRUE)
#if defined(__OS2__) && (defined(__IBMC__) || defined(__IBMCPP__))
    if (freopen("","wb",stdout) == NULL) 
        return (-1);
#else
    setbinmode(stdout);
#endif

    if (unbuf_f)
      setbuf(stdout, (char *) NULL);
    else
      setvbuffer(stdout, (char *) stdobuf, IOBUF_SIZE);

    if (argc == 0) {
      if (binmode_f == TRUE)
#if defined(__OS2__) && (defined(__IBMC__) || defined(__IBMCPP__))
      if (freopen("","rb",stdin) == NULL) return (-1);
#else
      setbinmode(stdin);
#endif
      setvbuffer(stdin, (char *) stdibuf, IOBUF_SIZE);
      if (nop_f)
          noconvert(stdin);
      else {
          kanji_convert(stdin);
          if (guess_f) print_guessed_code(NULL);
      }
    } else {
      int nfiles = argc;
	int is_argument_error = FALSE;
      while (argc--) {
	    is_inputcode_mixed = FALSE;
	    is_inputcode_set   = FALSE;
	    input_codename = "";
#ifdef CHECK_OPTION
	    iconv_for_check = 0;
#endif
          if ((fin = fopen((origfname = *argv++), "r")) == NULL) {
              perror(*--argv);
		*argv++;
		is_argument_error = TRUE;
		continue;
          } else {
#ifdef OVERWRITE
              int fd = 0;
              int fd_backup = 0;
#endif

/* reopen file for stdout */
              if (file_out_f == TRUE) {
#ifdef OVERWRITE
                  if (overwrite_f){
                      outfname = malloc(strlen(origfname)
                                        + strlen(".nkftmpXXXXXX")
                                        + 1);
                      if (!outfname){
                          perror(origfname);
                          return -1;
                      }
                      strcpy(outfname, origfname);
#ifdef MSDOS
                      {
                          int i;
                          for (i = strlen(outfname); i; --i){
                              if (outfname[i - 1] == '/'
                                  || outfname[i - 1] == '\\'){
                                  break;
                              }
                          }
                          outfname[i] = '\0';
                      }
                      strcat(outfname, "ntXXXXXX");
                      mktemp(outfname);
			fd = open(outfname, O_WRONLY | O_CREAT | O_TRUNC | O_EXCL,
                                S_IREAD | S_IWRITE);
#else
                      strcat(outfname, ".nkftmpXXXXXX");
                      fd = mkstemp(outfname);
#endif
                      if (fd < 0
                          || (fd_backup = dup(fileno(stdout))) < 0
                          || dup2(fd, fileno(stdout)) < 0
                          ){
                          perror(origfname);
                          return -1;
                      }
                  }else
#endif
		  if(argc == 1 ) {
		      outfname = *argv++;
		      argc--;
		  } else {
		      outfname = "nkf.out";
		  }

		  if(freopen(outfname, "w", stdout) == NULL) {
		      perror (outfname);
		      return (-1);
		  }
                  if (binmode_f == TRUE) {
#if defined(__OS2__) && (defined(__IBMC__) || defined(__IBMCPP__))
                      if (freopen("","wb",stdout) == NULL) 
                           return (-1);
#else
                      setbinmode(stdout);
#endif
                  }
              }
              if (binmode_f == TRUE)
#if defined(__OS2__) && (defined(__IBMC__) || defined(__IBMCPP__))
                 if (freopen("","rb",fin) == NULL) 
                    return (-1);
#else
                 setbinmode(fin);
#endif 
              setvbuffer(fin, (char *) stdibuf, IOBUF_SIZE);
              if (nop_f)
                  noconvert(fin);
              else {
                  char *filename = NULL;
                  kanji_convert(fin);
                  if (nfiles > 1) filename = origfname;
                  if (guess_f) print_guessed_code(filename);
              }
              fclose(fin);
#ifdef OVERWRITE
              if (overwrite_f) {
                  struct stat     sb;
#if defined(MSDOS) && !defined(__MINGW32__) && !defined(__WIN32__) && !defined(__WATCOMC__) && !defined(__EMX__) && !defined(__OS2__) && !defined(__DJGPP__)
                  time_t tb[2];
#else
                  struct utimbuf  tb;
#endif

                  fflush(stdout);
                  close(fd);
                  if (dup2(fd_backup, fileno(stdout)) < 0){
                      perror("dup2");
                  }
                  if (stat(origfname, &sb)) {
                      fprintf(stderr, "Can't stat %s\n", origfname);
                  }
                  /* パーミッションを復元 */
                  if (chmod(outfname, sb.st_mode)) {
                      fprintf(stderr, "Can't set permission %s\n", outfname);
                  }

                  /* タイムスタンプを復元 */
		    if(preserve_time_f){
#if defined(MSDOS) && !defined(__MINGW32__) && !defined(__WIN32__) && !defined(__WATCOMC__) && !defined(__EMX__) && !defined(__OS2__) && !defined(__DJGPP__)
			tb[0] = tb[1] = sb.st_mtime;
			if (utime(outfname, tb)) {
			    fprintf(stderr, "Can't set timestamp %s\n", outfname);
			}
#else
			tb.actime  = sb.st_atime;
			tb.modtime = sb.st_mtime;
			if (utime(outfname, &tb)) {
			    fprintf(stderr, "Can't set timestamp %s\n", outfname);
			}
#endif
		    }
		    if(backup_f){
			char *backup_filename = get_backup_filename(backup_suffix, origfname);
#ifdef MSDOS
			unlink(backup_filename);
#endif
			if (rename(origfname, backup_filename)) {
			    perror(backup_filename);
			    fprintf(stderr, "Can't rename %s to %s\n",
				    origfname, backup_filename);
			}
		    }else{
#ifdef MSDOS
			if (unlink(origfname)){
			    perror(origfname);
			}
#endif
		    }
                  if (rename(outfname, origfname)) {
                      perror(origfname);
                      fprintf(stderr, "Can't rename %s to %s\n",
                              outfname, origfname);
                  }
                  free(outfname);
              }
#endif
          }
      }
	if (is_argument_error)
	    return(-1);
    }
#ifdef EASYWIN /*Easy Win */
    if (file_out_f == FALSE) 
        scanf("%d",&end_check);
    else 
        fclose(stdout);
#else /* for Other OS */
    if (file_out_f == TRUE) 
        fclose(stdout);
#endif /*Easy Win */
    return (0);
}
#endif /* WIN32DLL */

#ifdef OVERWRITE
char *get_backup_filename(const char *suffix, const char *filename)
{
    char *backup_filename;
    int asterisk_count = 0;
    int i, j;
    int filename_length = strlen(filename);

    for(i = 0; suffix[i]; i++){
	if(suffix[i] == '*') asterisk_count++;
    }

    if(asterisk_count){
	backup_filename = malloc(strlen(suffix) + (asterisk_count * (filename_length - 1)) + 1);
	if (!backup_filename){
	    perror("Can't malloc backup filename.");
	    return NULL;
	}

	for(i = 0, j = 0; suffix[i];){
	    if(suffix[i] == '*'){
		backup_filename[j] = '\0';
		strncat(backup_filename, filename, filename_length);
		i++;
		j += filename_length;
	    }else{
		backup_filename[j++] = suffix[i++];
	    }
	}
	backup_filename[j] = '\0';
    }else{
	j = strlen(suffix) + filename_length;
	backup_filename = malloc( + 1);
	strcpy(backup_filename, filename);
	strcat(backup_filename, suffix);
	backup_filename[j] = '\0';
    }
    return backup_filename;
}
#endif

static const
struct {
    const char *name;
    const char *alias;
} long_option[] = {
    {"ic=", ""},
    {"oc=", ""},
    {"base64","jMB"},
    {"euc","e"},
    {"euc-input","E"},
    {"fj","jm"},
    {"help","v"},
    {"jis","j"},
    {"jis-input","J"},
    {"mac","sLm"},
    {"mime","jM"},
    {"mime-input","m"},
    {"msdos","sLw"},
    {"sjis","s"},
    {"sjis-input","S"},
    {"unix","eLu"},
    {"version","V"},
    {"windows","sLw"},
    {"hiragana","h1"},
    {"katakana","h2"},
    {"katakana-hiragana","h3"},
    {"guess", "g"},
    {"cp932", ""},
    {"no-cp932", ""},
#ifdef X0212_ENABLE
    {"x0212", ""},
#endif
#ifdef UTF8_OUTPUT_ENABLE
    {"utf8", "w"},
    {"utf16", "w16"},
    {"ms-ucs-map", ""},
    {"fb-skip", ""},
    {"fb-html", ""},
    {"fb-xml", ""},
    {"fb-perl", ""},
    {"fb-java", ""},
    {"fb-subchar", ""},
    {"fb-subchar=", ""},
#endif
#ifdef UTF8_INPUT_ENABLE
    {"utf8-input", "W"},
    {"utf16-input", "W16"},
    {"no-cp932ext", ""},
    {"no-best-fit-chars",""},
#endif
#ifdef UNICODE_NORMALIZATION
    {"utf8mac-input", ""},
#endif
#ifdef OVERWRITE
    {"overwrite", ""},
    {"overwrite=", ""},
    {"in-place", ""},
    {"in-place=", ""},
#endif
#ifdef INPUT_OPTION
    {"cap-input", ""},
    {"url-input", ""},
#endif
#ifdef NUMCHAR_OPTION
    {"numchar-input", ""},
#endif
#ifdef CHECK_OPTION
    {"no-output", ""},
    {"debug", ""},
#endif
#ifdef SHIFTJIS_CP932
    {"cp932inv", ""},
#endif
#ifdef EXEC_IO
    {"exec-in", ""},
    {"exec-out", ""},
#endif
    {"prefix=", ""},
};

static int option_mode = 0;

void options(unsigned char *cp)
{
    nkf_char i, j;
    unsigned char *p;
    unsigned char *cp_back = NULL;
    char codeset[32];

    if (option_mode==1)
	return;
    while(*cp && *cp++!='-');
    while (*cp || cp_back) {
	if(!*cp){
	    cp = cp_back;
	    cp_back = NULL;
	    continue;
	}
	p = 0;
        switch (*cp++) {
        case '-':  /* literal options */
	    if (!*cp || *cp == SPACE) {        /* ignore the rest of arguments */
		option_mode = 1;
		return;
	    }
            for (i=0;i<sizeof(long_option)/sizeof(long_option[0]);i++) {
                p = (unsigned char *)long_option[i].name;
                for (j=0;*p && *p != '=' && *p == cp[j];p++, j++);
		if (*p == cp[j] || cp[j] == ' '){
		    p = &cp[j] + 1;
		    break;
		}
		p = 0;
            }
	    if (p == 0) return;
	    while(*cp && *cp != SPACE && cp++);
            if (long_option[i].alias[0]){
		cp_back = cp;
		cp = (unsigned char *)long_option[i].alias;
	    }else{
                if (strcmp(long_option[i].name, "ic=") == 0){
		    for (i=0; i < 16 && SPACE < p[i] && p[i] < DEL; i++){
			codeset[i] = nkf_toupper(p[i]);
		    }
		    codeset[i] = 0;
		    if(strcmp(codeset, "ISO-2022-JP") == 0){
			input_f = JIS_INPUT;
		    }else if(strcmp(codeset, "X-ISO2022JP-CP932") == 0 ||
		      strcmp(codeset, "CP50220") == 0 ||
		      strcmp(codeset, "CP50221") == 0 ||
		      strcmp(codeset, "CP50222") == 0){
			input_f = JIS_INPUT;
#ifdef SHIFTJIS_CP932
			cp51932_f = TRUE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_CP932;
#endif
		    }else if(strcmp(codeset, "ISO-2022-JP-1") == 0){
			input_f = JIS_INPUT;
#ifdef X0212_ENABLE
			x0212_f = TRUE;
#endif
		    }else if(strcmp(codeset, "ISO-2022-JP-3") == 0){
			input_f = JIS_INPUT;
#ifdef X0212_ENABLE
			x0212_f = TRUE;
#endif
			x0213_f = TRUE;
		    }else if(strcmp(codeset, "SHIFT_JIS") == 0){
			input_f = SJIS_INPUT;
		    }else if(strcmp(codeset, "WINDOWS-31J") == 0 ||
			     strcmp(codeset, "CSWINDOWS31J") == 0 ||
			     strcmp(codeset, "CP932") == 0 ||
			     strcmp(codeset, "MS932") == 0){
			input_f = SJIS_INPUT;
#ifdef SHIFTJIS_CP932
			cp51932_f = TRUE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_CP932;
#endif
		    }else if(strcmp(codeset, "EUCJP") == 0 ||
			     strcmp(codeset, "EUC-JP") == 0){
			input_f = EUC_INPUT;
		    }else if(strcmp(codeset, "CP51932") == 0){
			input_f = EUC_INPUT;
#ifdef SHIFTJIS_CP932
			cp51932_f = TRUE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_CP932;
#endif
		    }else if(strcmp(codeset, "EUC-JP-MS") == 0 ||
			     strcmp(codeset, "EUCJP-MS") == 0 ||
			     strcmp(codeset, "EUCJPMS") == 0){
			input_f = EUC_INPUT;
#ifdef SHIFTJIS_CP932
			cp51932_f = FALSE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_MS;
#endif
		    }else if(strcmp(codeset, "EUC-JP-ASCII") == 0 ||
			     strcmp(codeset, "EUCJP-ASCII") == 0){
			input_f = EUC_INPUT;
#ifdef SHIFTJIS_CP932
			cp51932_f = FALSE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_ASCII;
#endif
		    }else if(strcmp(codeset, "SHIFT_JISX0213") == 0 ||
			     strcmp(codeset, "SHIFT_JIS-2004") == 0){
			input_f = SJIS_INPUT;
			x0213_f = TRUE;
#ifdef SHIFTJIS_CP932
			cp51932_f = FALSE;
#endif
		    }else if(strcmp(codeset, "EUC-JISX0213") == 0 ||
			     strcmp(codeset, "EUC-JIS-2004") == 0){
			input_f = EUC_INPUT;
			x0213_f = TRUE;
#ifdef SHIFTJIS_CP932
			cp51932_f = FALSE;
#endif
#ifdef UTF8_INPUT_ENABLE
		    }else if(strcmp(codeset, "UTF-8") == 0 ||
			     strcmp(codeset, "UTF-8N") == 0 ||
			     strcmp(codeset, "UTF-8-BOM") == 0){
			input_f = UTF8_INPUT;
#ifdef UNICODE_NORMALIZATION
		    }else if(strcmp(codeset, "UTF8-MAC") == 0 ||
			     strcmp(codeset, "UTF-8-MAC") == 0){
			input_f = UTF8_INPUT;
			nfc_f = TRUE;
#endif
		    }else if(strcmp(codeset, "UTF-16") == 0 ||
			     strcmp(codeset, "UTF-16BE") == 0 ||
			     strcmp(codeset, "UTF-16BE-BOM") == 0){
			input_f = UTF16_INPUT;
			input_endian = ENDIAN_BIG;
		    }else if(strcmp(codeset, "UTF-16LE") == 0 ||
			     strcmp(codeset, "UTF-16LE-BOM") == 0){
			input_f = UTF16_INPUT;
			input_endian = ENDIAN_LITTLE;
		    }else if(strcmp(codeset, "UTF-32") == 0 ||
			     strcmp(codeset, "UTF-32BE") == 0 ||
			     strcmp(codeset, "UTF-32BE-BOM") == 0){
			input_f = UTF32_INPUT;
			input_endian = ENDIAN_BIG;
		    }else if(strcmp(codeset, "UTF-32LE") == 0 ||
			     strcmp(codeset, "UTF-32LE-BOM") == 0){
			input_f = UTF32_INPUT;
			input_endian = ENDIAN_LITTLE;
#endif
		    }
                    continue;
		}
                if (strcmp(long_option[i].name, "oc=") == 0){
		    x0201_f = FALSE;
		    for (i=0; i < 16 && SPACE < p[i] && p[i] < DEL; i++){
			codeset[i] = nkf_toupper(p[i]);
		    }
		    codeset[i] = 0;
		    if(strcmp(codeset, "ISO-2022-JP") == 0){
			output_conv = j_oconv;
		    }else if(strcmp(codeset, "X-ISO2022JP-CP932") == 0){
			output_conv = j_oconv;
			no_cp932ext_f = TRUE;
#ifdef SHIFTJIS_CP932
			cp932inv_f = FALSE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_CP932;
#endif
		    }else if(strcmp(codeset, "CP50220") == 0){
			output_conv = j_oconv;
			x0201_f = TRUE;
#ifdef SHIFTJIS_CP932
			cp932inv_f = FALSE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_CP932;
#endif
		    }else if(strcmp(codeset, "CP50221") == 0){
			output_conv = j_oconv;
#ifdef SHIFTJIS_CP932
			cp932inv_f = FALSE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_CP932;
#endif
		    }else if(strcmp(codeset, "ISO-2022-JP-1") == 0){
			output_conv = j_oconv;
#ifdef X0212_ENABLE
			x0212_f = TRUE;
#endif
#ifdef SHIFTJIS_CP932
			cp932inv_f = FALSE;
#endif
		    }else if(strcmp(codeset, "ISO-2022-JP-3") == 0){
			output_conv = j_oconv;
#ifdef X0212_ENABLE
			x0212_f = TRUE;
#endif
			x0213_f = TRUE;
#ifdef SHIFTJIS_CP932
			cp932inv_f = FALSE;
#endif
		    }else if(strcmp(codeset, "SHIFT_JIS") == 0){
			output_conv = s_oconv;
		    }else if(strcmp(codeset, "WINDOWS-31J") == 0 ||
			     strcmp(codeset, "CSWINDOWS31J") == 0 ||
			     strcmp(codeset, "CP932") == 0 ||
			     strcmp(codeset, "MS932") == 0){
			output_conv = s_oconv;
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_CP932;
#endif
		    }else if(strcmp(codeset, "EUCJP") == 0 ||
			     strcmp(codeset, "EUC-JP") == 0){
			output_conv = e_oconv;
		    }else if(strcmp(codeset, "CP51932") == 0){
			output_conv = e_oconv;
#ifdef SHIFTJIS_CP932
			cp932inv_f = FALSE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_CP932;
#endif
		    }else if(strcmp(codeset, "EUC-JP-MS") == 0 ||
			     strcmp(codeset, "EUCJP-MS") == 0 ||
			     strcmp(codeset, "EUCJPMS") == 0){
			output_conv = e_oconv;
#ifdef X0212_ENABLE
			x0212_f = TRUE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_MS;
#endif
		    }else if(strcmp(codeset, "EUC-JP-ASCII") == 0 ||
			     strcmp(codeset, "EUCJP-ASCII") == 0){
			output_conv = e_oconv;
#ifdef X0212_ENABLE
			x0212_f = TRUE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
			ms_ucs_map_f = UCS_MAP_ASCII;
#endif
		    }else if(strcmp(codeset, "SHIFT_JISX0213") == 0 ||
			     strcmp(codeset, "SHIFT_JIS-2004") == 0){
			output_conv = s_oconv;
			x0213_f = TRUE;
#ifdef SHIFTJIS_CP932
			cp932inv_f = FALSE;
#endif
		    }else if(strcmp(codeset, "EUC-JISX0213") == 0 ||
			     strcmp(codeset, "EUC-JIS-2004") == 0){
			output_conv = e_oconv;
#ifdef X0212_ENABLE
			x0212_f = TRUE;
#endif
			x0213_f = TRUE;
#ifdef SHIFTJIS_CP932
			cp932inv_f = FALSE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
		    }else if(strcmp(codeset, "UTF-8") == 0){
			output_conv = w_oconv;
		    }else if(strcmp(codeset, "UTF-8N") == 0){
			output_conv = w_oconv;
		    }else if(strcmp(codeset, "UTF-8-BOM") == 0){
			output_conv = w_oconv;
			output_bom_f = TRUE;
		    }else if(strcmp(codeset, "UTF-16BE") == 0){
			output_conv = w_oconv16;
		    }else if(strcmp(codeset, "UTF-16") == 0 ||
			     strcmp(codeset, "UTF-16BE-BOM") == 0){
			output_conv = w_oconv16;
			output_bom_f = TRUE;
		    }else if(strcmp(codeset, "UTF-16LE") == 0){
			output_conv = w_oconv16;
			output_endian = ENDIAN_LITTLE;
		    }else if(strcmp(codeset, "UTF-16LE-BOM") == 0){
			output_conv = w_oconv16;
			output_endian = ENDIAN_LITTLE;
			output_bom_f = TRUE;
		    }else if(strcmp(codeset, "UTF-32") == 0 ||
			     strcmp(codeset, "UTF-32BE") == 0){
			output_conv = w_oconv32;
		    }else if(strcmp(codeset, "UTF-32BE-BOM") == 0){
			output_conv = w_oconv32;
			output_bom_f = TRUE;
		    }else if(strcmp(codeset, "UTF-32LE") == 0){
			output_conv = w_oconv32;
			output_endian = ENDIAN_LITTLE;
		    }else if(strcmp(codeset, "UTF-32LE-BOM") == 0){
			output_conv = w_oconv32;
			output_endian = ENDIAN_LITTLE;
			output_bom_f = TRUE;
#endif
		    }
                    continue;
		}
#ifdef OVERWRITE
                if (strcmp(long_option[i].name, "overwrite") == 0){
                    file_out_f = TRUE;
                    overwrite_f = TRUE;
		    preserve_time_f = TRUE;
                    continue;
                }
                if (strcmp(long_option[i].name, "overwrite=") == 0){
                    file_out_f = TRUE;
                    overwrite_f = TRUE;
		    preserve_time_f = TRUE;
		    backup_f = TRUE;
		    backup_suffix = malloc(strlen((char *) p) + 1);
		    strcpy(backup_suffix, (char *) p);
                    continue;
                }
                if (strcmp(long_option[i].name, "in-place") == 0){
                    file_out_f = TRUE;
                    overwrite_f = TRUE;
		    preserve_time_f = FALSE;
		    continue;
                }
                if (strcmp(long_option[i].name, "in-place=") == 0){
                    file_out_f = TRUE;
                    overwrite_f = TRUE;
		    preserve_time_f = FALSE;
		    backup_f = TRUE;
		    backup_suffix = malloc(strlen((char *) p) + 1);
		    strcpy(backup_suffix, (char *) p);
		    continue;
                }
#endif
#ifdef INPUT_OPTION
                if (strcmp(long_option[i].name, "cap-input") == 0){
                    cap_f = TRUE;
                    continue;
                }
                if (strcmp(long_option[i].name, "url-input") == 0){
                    url_f = TRUE;
                    continue;
                }
#endif
#ifdef NUMCHAR_OPTION
                if (strcmp(long_option[i].name, "numchar-input") == 0){
                    numchar_f = TRUE;
                    continue;
                }
#endif
#ifdef CHECK_OPTION
                if (strcmp(long_option[i].name, "no-output") == 0){
                    noout_f = TRUE;
                    continue;
                }
                if (strcmp(long_option[i].name, "debug") == 0){
                    debug_f = TRUE;
                    continue;
                }
#endif
                if (strcmp(long_option[i].name, "cp932") == 0){
#ifdef SHIFTJIS_CP932
                    cp51932_f = TRUE;
                    cp932inv_f = TRUE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
                    ms_ucs_map_f = UCS_MAP_CP932;
#endif
                    continue;
                }
                if (strcmp(long_option[i].name, "no-cp932") == 0){
#ifdef SHIFTJIS_CP932
                    cp51932_f = FALSE;
                    cp932inv_f = FALSE;
#endif
#ifdef UTF8_OUTPUT_ENABLE
                    ms_ucs_map_f = UCS_MAP_ASCII;
#endif
                    continue;
                }
#ifdef SHIFTJIS_CP932
                if (strcmp(long_option[i].name, "cp932inv") == 0){
                    cp932inv_f = TRUE;
                    continue;
                }
#endif

#ifdef X0212_ENABLE
                if (strcmp(long_option[i].name, "x0212") == 0){
                    x0212_f = TRUE;
                    continue;
                }
#endif

#ifdef EXEC_IO
                  if (strcmp(long_option[i].name, "exec-in") == 0){
                      exec_f = 1;
                      return;
                  }
                  if (strcmp(long_option[i].name, "exec-out") == 0){
                      exec_f = -1;
                      return;
                  }
#endif
#if defined(UTF8_OUTPUT_ENABLE) && defined(UTF8_INPUT_ENABLE)
                if (strcmp(long_option[i].name, "no-cp932ext") == 0){
		    no_cp932ext_f = TRUE;
                    continue;
                }
		if (strcmp(long_option[i].name, "no-best-fit-chars") == 0){
		    no_best_fit_chars_f = TRUE;
		    continue;
		}
                if (strcmp(long_option[i].name, "fb-skip") == 0){
		    encode_fallback = NULL;
                    continue;
                }
                if (strcmp(long_option[i].name, "fb-html") == 0){
		    encode_fallback = encode_fallback_html;
                    continue;
                }
                if (strcmp(long_option[i].name, "fb-xml" ) == 0){
		    encode_fallback = encode_fallback_xml;
                    continue;
                }
                if (strcmp(long_option[i].name, "fb-java") == 0){
		    encode_fallback = encode_fallback_java;
                    continue;
                }
                if (strcmp(long_option[i].name, "fb-perl") == 0){
		    encode_fallback = encode_fallback_perl;
                    continue;
                }
                if (strcmp(long_option[i].name, "fb-subchar") == 0){
		    encode_fallback = encode_fallback_subchar;
                    continue;
                }
                if (strcmp(long_option[i].name, "fb-subchar=") == 0){
		    encode_fallback = encode_fallback_subchar;
		    unicode_subchar = 0;
		    if (p[0] != '0'){
			/* decimal number */
			for (i = 0; i < 7 && nkf_isdigit(p[i]); i++){
			    unicode_subchar *= 10;
			    unicode_subchar += hex2bin(p[i]);
			}
		    }else if(p[1] == 'x' || p[1] == 'X'){
			/* hexadecimal number */
			for (i = 2; i < 8 && nkf_isxdigit(p[i]); i++){
			    unicode_subchar <<= 4;
			    unicode_subchar |= hex2bin(p[i]);
			}
		    }else{
			/* octal number */
			for (i = 1; i < 8 && nkf_isoctal(p[i]); i++){
			    unicode_subchar *= 8;
			    unicode_subchar += hex2bin(p[i]);
			}
		    }
		    w16e_conv(unicode_subchar, &i, &j);
		    unicode_subchar = i<<8 | j;
                    continue;
                }
#endif
#ifdef UTF8_OUTPUT_ENABLE
                if (strcmp(long_option[i].name, "ms-ucs-map") == 0){
                    ms_ucs_map_f = UCS_MAP_MS;
                    continue;
                }
#endif
#ifdef UNICODE_NORMALIZATION
		if (strcmp(long_option[i].name, "utf8mac-input") == 0){
		    input_f = UTF8_INPUT;
		    nfc_f = TRUE;
		    continue;
		}
#endif
                if (strcmp(long_option[i].name, "prefix=") == 0){
                    if (nkf_isgraph(p[0])){
                        for (i = 1; nkf_isgraph(p[i]); i++){
                            prefix_table[p[i]] = p[0];
                        }
                    }
                    continue;
                }
            }
            continue;
        case 'b':           /* buffered mode */
            unbuf_f = FALSE;
            continue;
        case 'u':           /* non bufferd mode */
            unbuf_f = TRUE;
            continue;
        case 't':           /* transparent mode */
            if (*cp=='1') {
		/* alias of -t */
		nop_f = TRUE;
		*cp++;
	    } else if (*cp=='2') {
		/*
		 * -t with put/get
		 *
		 * nkf -t2MB hoge.bin | nkf -t2mB | diff -s - hoge.bin
		 *
		 */
		nop_f = 2;
		*cp++;
            } else
		nop_f = TRUE;
            continue;
        case 'j':           /* JIS output */
        case 'n':
            output_conv = j_oconv;
            continue;
        case 'e':           /* AT&T EUC output */
            output_conv = e_oconv;
            cp932inv_f = FALSE;
            continue;
        case 's':           /* SJIS output */
            output_conv = s_oconv;
            continue;
        case 'l':           /* ISO8859 Latin-1 support, no conversion */
            iso8859_f = TRUE;  /* Only compatible with ISO-2022-JP */
            input_f = LATIN1_INPUT;
            continue;
        case 'i':           /* Kanji IN ESC-$-@/B */
            if (*cp=='@'||*cp=='B') 
                kanji_intro = *cp++;
            continue;
        case 'o':           /* ASCII IN ESC-(-J/B */
            if (*cp=='J'||*cp=='B'||*cp=='H') 
                ascii_intro = *cp++;
            continue;
        case 'h':
            /*  
                bit:1   katakana->hiragana
                bit:2   hiragana->katakana
            */
            if ('9'>= *cp && *cp>='0') 
                hira_f |= (*cp++ -'0');
            else 
                hira_f |= 1;
            continue;
        case 'r':
            rot_f = TRUE;
            continue;
#if defined(MSDOS) || defined(__OS2__) 
        case 'T':
            binmode_f = FALSE;
            continue;
#endif
#ifndef PERL_XS
        case 'V':
            version();
            exit(1);
            break;
        case 'v':
            usage();
            exit(1);
            break;
#endif
#ifdef UTF8_OUTPUT_ENABLE
        case 'w':           /* UTF-8 output */
            if (cp[0] == '8') {
		output_conv = w_oconv; cp++;
		if (cp[0] == '0'){
		    cp++;
		} else {
		    output_bom_f = TRUE;
		}
	    } else {
		if ('1'== cp[0] && '6'==cp[1]) {
		    output_conv = w_oconv16; cp+=2;
		} else if ('3'== cp[0] && '2'==cp[1]) {
		    output_conv = w_oconv32; cp+=2;
		} else {
		    output_conv = w_oconv;
		    continue;
		}
		if (cp[0]=='L') {
		    cp++;
		    output_endian = ENDIAN_LITTLE;
		} else if (cp[0] == 'B') {
		    cp++;
                } else {
		    continue;
                }
		if (cp[0] == '0'){
		    cp++;
		} else {
		    output_bom_f = TRUE;
		}
	    }
            continue;
#endif
#ifdef UTF8_INPUT_ENABLE
        case 'W':           /* UTF input */
	    if (cp[0] == '8') {
		cp++;
		input_f = UTF8_INPUT;
	    }else{
		if ('1'== cp[0] && '6'==cp[1]) {
		    cp += 2;
		    input_f = UTF16_INPUT;
		    input_endian = ENDIAN_BIG;
		} else if ('3'== cp[0] && '2'==cp[1]) {
		    cp += 2;
		    input_f = UTF32_INPUT;
		    input_endian = ENDIAN_BIG;
		} else {
		    input_f = UTF8_INPUT;
		    continue;
		}
		if (cp[0]=='L') {
		    cp++;
		    input_endian = ENDIAN_LITTLE;
		} else if (cp[0] == 'B') {
		    cp++;
		}
	    }
            continue;
#endif
        /* Input code assumption */
        case 'J':   /* JIS input */
            input_f = JIS_INPUT;
            continue;
        case 'E':   /* AT&T EUC input */
            input_f = EUC_INPUT;
            continue;
        case 'S':   /* MS Kanji input */
            input_f = SJIS_INPUT;
            if (x0201_f==NO_X0201) x0201_f=TRUE;
            continue;
        case 'Z':   /* Convert X0208 alphabet to asii */
            /*  bit:0   Convert X0208
                bit:1   Convert Kankaku to one space
                bit:2   Convert Kankaku to two spaces
                bit:3   Convert HTML Entity
            */
            if ('9'>= *cp && *cp>='0') 
                alpha_f |= 1<<(*cp++ -'0');
            else 
                alpha_f |= TRUE;
            continue;
        case 'x':   /* Convert X0201 kana to X0208 or X0201 Conversion */
            x0201_f = FALSE;    /* No X0201->X0208 conversion */
            /* accept  X0201
                    ESC-(-I     in JIS, EUC, MS Kanji
                    SI/SO       in JIS, EUC, MS Kanji
                    SSO         in EUC, JIS, not in MS Kanji
                    MS Kanji (0xa0-0xdf) 
               output  X0201
                    ESC-(-I     in JIS (0x20-0x5f)
                    SSO         in EUC (0xa0-0xdf)
                    0xa0-0xd    in MS Kanji (0xa0-0xdf) 
            */
            continue;
        case 'X':   /* Assume X0201 kana */
            /* Default value is NO_X0201 for EUC/MS-Kanji mix */
            x0201_f = TRUE;
            continue;
        case 'F':   /* prserve new lines */
	    fold_preserve_f = TRUE;
        case 'f':   /* folding -f60 or -f */
            fold_f = TRUE;
            fold_len = 0;
            while('0'<= *cp && *cp <='9') { /* we don't use atoi here */
		fold_len *= 10;
		fold_len += *cp++ - '0';
	    }
            if (!(0<fold_len && fold_len<BUFSIZ)) 
                fold_len = DEFAULT_FOLD;
	    if (*cp=='-') {
		fold_margin = 0;
		cp++;
		while('0'<= *cp && *cp <='9') { /* we don't use atoi here */
		    fold_margin *= 10;
		    fold_margin += *cp++ - '0';
		}
	    }
            continue;
        case 'm':   /* MIME support */
            /* mime_decode_f = TRUE; */ /* this has too large side effects... */
            if (*cp=='B'||*cp=='Q') {
                mime_decode_mode = *cp++;
                mimebuf_f = FIXED_MIME;
            } else if (*cp=='N') {
                mime_f = TRUE; cp++;
            } else if (*cp=='S') {
                mime_f = STRICT_MIME; cp++;
            } else if (*cp=='0') {
                mime_decode_f = FALSE;
                mime_f = FALSE; cp++;
            }
            continue;
        case 'M':   /* MIME output */
            if (*cp=='B') {
                mimeout_mode = 'B';
                mimeout_f = FIXED_MIME; cp++;
            } else if (*cp=='Q') {
                mimeout_mode = 'Q';
                mimeout_f = FIXED_MIME; cp++;
            } else {
		mimeout_f = TRUE;
	    }
            continue;
        case 'B':   /* Broken JIS support */
            /*  bit:0   no ESC JIS
                bit:1   allow any x on ESC-(-x or ESC-$-x
                bit:2   reset to ascii on NL
            */
            if ('9'>= *cp && *cp>='0') 
                broken_f |= 1<<(*cp++ -'0');
            else 
                broken_f |= TRUE;
            continue;
#ifndef PERL_XS
        case 'O':/* for Output file */
            file_out_f = TRUE;
            continue;
#endif
        case 'c':/* add cr code */
            crmode_f = CRLF;
            continue;
        case 'd':/* delete cr code */
            crmode_f = NL;
            continue;
        case 'I':   /* ISO-2022-JP output */
            iso2022jp_f = TRUE;
            continue;
        case 'L':  /* line mode */
            if (*cp=='u') {         /* unix */
                crmode_f = NL; cp++;
            } else if (*cp=='m') { /* mac */
                crmode_f = CR; cp++;
            } else if (*cp=='w') { /* windows */
                crmode_f = CRLF; cp++;
            } else if (*cp=='0') { /* no conversion  */
                crmode_f = 0; cp++;
            }
            continue;
        case 'g':
#ifndef PERL_XS
            guess_f = TRUE;
#endif
            continue;
        case ' ':    
        /* module muliple options in a string are allowed for Perl moudle  */
	    while(*cp && *cp++!='-');
            continue;
        default:
            /* bogus option but ignored */
            continue;
        }
    }
}

struct input_code * find_inputcode_byfunc(nkf_char (*iconv_func)(nkf_char c2,nkf_char c1,nkf_char c0))
{
    if (iconv_func){
        struct input_code *p = input_code_list;
        while (p->name){
            if (iconv_func == p->iconv_func){
                return p;
            }
            p++;
        }
    }
    return 0;
}

void set_iconv(nkf_char f, nkf_char (*iconv_func)(nkf_char c2,nkf_char c1,nkf_char c0))
{
#ifdef INPUT_CODE_FIX
    if (f || !input_f)
#endif
        if (estab_f != f){
            estab_f = f;
        }

    if (iconv_func
#ifdef INPUT_CODE_FIX
        && (f == -TRUE || !input_f) /* -TRUE means "FORCE" */
#endif
        ){
        iconv = iconv_func;
    }
#ifdef CHECK_OPTION
    if (estab_f && iconv_for_check != iconv){
        struct input_code *p = find_inputcode_byfunc(iconv);
        if (p){
            set_input_codename(p->name);
            debug(input_codename);
        }
        iconv_for_check = iconv;
    }
#endif
}

#define SCORE_L2       (1)                   /* 第2水準漢字 */
#define SCORE_KANA     (SCORE_L2 << 1)       /* いわゆる半角カナ */
#define SCORE_DEPEND   (SCORE_KANA << 1)     /* 機種依存文字 */
#ifdef SHIFTJIS_CP932
#define SCORE_CP932    (SCORE_DEPEND << 1)   /* CP932 による読み換え */
#define SCORE_NO_EXIST (SCORE_CP932 << 1)    /* 存在しない文字 */
#else
#define SCORE_NO_EXIST (SCORE_DEPEND << 1)   /* 存在しない文字 */
#endif
#define SCORE_iMIME    (SCORE_NO_EXIST << 1) /* MIME による指定 */
#define SCORE_ERROR    (SCORE_iMIME << 1) /* エラー */

#define SCORE_INIT (SCORE_iMIME)

const nkf_char score_table_A0[] = {
    0, 0, 0, 0,
    0, 0, 0, 0,
    0, SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND,
    SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND, SCORE_NO_EXIST,
};

const nkf_char score_table_F0[] = {
    SCORE_L2, SCORE_L2, SCORE_L2, SCORE_L2,
    SCORE_L2, SCORE_DEPEND, SCORE_NO_EXIST, SCORE_NO_EXIST,
    SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND,
    SCORE_DEPEND, SCORE_NO_EXIST, SCORE_NO_EXIST, SCORE_ERROR,
};

void set_code_score(struct input_code *ptr, nkf_char score)
{
    if (ptr){
        ptr->score |= score;
    }
}

void clr_code_score(struct input_code *ptr, nkf_char score)
{
    if (ptr){
        ptr->score &= ~score;
    }
}

void code_score(struct input_code *ptr)
{
    nkf_char c2 = ptr->buf[0];
#ifdef UTF8_OUTPUT_ENABLE
    nkf_char c1 = ptr->buf[1];
#endif
    if (c2 < 0){
        set_code_score(ptr, SCORE_ERROR);
    }else if (c2 == SSO){
        set_code_score(ptr, SCORE_KANA);
#ifdef UTF8_OUTPUT_ENABLE
    }else if (!e2w_conv(c2, c1)){
        set_code_score(ptr, SCORE_NO_EXIST);
#endif
    }else if ((c2 & 0x70) == 0x20){
        set_code_score(ptr, score_table_A0[c2 & 0x0f]);
    }else if ((c2 & 0x70) == 0x70){
        set_code_score(ptr, score_table_F0[c2 & 0x0f]);
    }else if ((c2 & 0x70) >= 0x50){
        set_code_score(ptr, SCORE_L2);
    }
}

void status_disable(struct input_code *ptr)
{
    ptr->stat = -1;
    ptr->buf[0] = -1;
    code_score(ptr);
    if (iconv == ptr->iconv_func) set_iconv(FALSE, 0);
}

void status_push_ch(struct input_code *ptr, nkf_char c)
{
    ptr->buf[ptr->index++] = c;
}

void status_clear(struct input_code *ptr)
{
    ptr->stat = 0;
    ptr->index = 0;
}

void status_reset(struct input_code *ptr)
{
    status_clear(ptr);
    ptr->score = SCORE_INIT;
}

void status_reinit(struct input_code *ptr)
{
    status_reset(ptr);
    ptr->_file_stat = 0;
}

void status_check(struct input_code *ptr, nkf_char c)
{
    if (c <= DEL && estab_f){
        status_reset(ptr);
    }
}

void s_status(struct input_code *ptr, nkf_char c)
{
    switch(ptr->stat){
      case -1:
          status_check(ptr, c);
          break;
      case 0:
          if (c <= DEL){
              break;
#ifdef NUMCHAR_OPTION
          }else if (is_unicode_capsule(c)){
              break;
#endif
          }else if (0xa1 <= c && c <= 0xdf){
              status_push_ch(ptr, SSO);
              status_push_ch(ptr, c);
              code_score(ptr);
              status_clear(ptr);
          }else if ((0x81 <= c && c < 0xa0) || (0xe0 <= c && c <= 0xef)){
              ptr->stat = 1;
              status_push_ch(ptr, c);
#ifdef SHIFTJIS_CP932
          }else if (cp51932_f
                    && is_ibmext_in_sjis(c)){
              ptr->stat = 2;
              status_push_ch(ptr, c);
#endif /* SHIFTJIS_CP932 */
#ifdef X0212_ENABLE
          }else if (x0212_f && 0xf0 <= c && c <= 0xfc){
              ptr->stat = 1;
              status_push_ch(ptr, c);
#endif /* X0212_ENABLE */
          }else{
              status_disable(ptr);
          }
          break;
      case 1:
          if ((0x40 <= c && c <= 0x7e) || (0x80 <= c && c <= 0xfc)){
              status_push_ch(ptr, c);
              s2e_conv(ptr->buf[0], ptr->buf[1], &ptr->buf[0], &ptr->buf[1]);
              code_score(ptr);
              status_clear(ptr);
          }else{
              status_disable(ptr);
          }
          break;
      case 2:
#ifdef SHIFTJIS_CP932
          if ((0x40 <= c && c <= 0x7e) || (0x80 <= c && c <= 0xfc)){
              status_push_ch(ptr, c);
              if (s2e_conv(ptr->buf[0], ptr->buf[1], &ptr->buf[0], &ptr->buf[1]) == 0){
                  set_code_score(ptr, SCORE_CP932);
                  status_clear(ptr);
                  break;
              }
          }
#endif /* SHIFTJIS_CP932 */
#ifndef X0212_ENABLE
          status_disable(ptr);
#endif
          break;
    }
}

void e_status(struct input_code *ptr, nkf_char c)
{
    switch (ptr->stat){
      case -1:
          status_check(ptr, c);
          break;
      case 0:
          if (c <= DEL){
              break;
#ifdef NUMCHAR_OPTION
          }else if (is_unicode_capsule(c)){
              break;
#endif
          }else if (SSO == c || (0xa1 <= c && c <= 0xfe)){
              ptr->stat = 1;
              status_push_ch(ptr, c);
#ifdef X0212_ENABLE
          }else if (0x8f == c){
              ptr->stat = 2;
              status_push_ch(ptr, c);
#endif /* X0212_ENABLE */
          }else{
              status_disable(ptr);
          }
          break;
      case 1:
          if (0xa1 <= c && c <= 0xfe){
              status_push_ch(ptr, c);
              code_score(ptr);
              status_clear(ptr);
          }else{
              status_disable(ptr);
          }
          break;
#ifdef X0212_ENABLE
      case 2:
          if (0xa1 <= c && c <= 0xfe){
              ptr->stat = 1;
              status_push_ch(ptr, c);
          }else{
              status_disable(ptr);
          }
#endif /* X0212_ENABLE */
    }
}

#ifdef UTF8_INPUT_ENABLE
void w_status(struct input_code *ptr, nkf_char c)
{
    switch (ptr->stat){
      case -1:
          status_check(ptr, c);
          break;
      case 0:
          if (c <= DEL){
              break;
#ifdef NUMCHAR_OPTION
          }else if (is_unicode_capsule(c)){
              break;
#endif
          }else if (0xc0 <= c && c <= 0xdf){
              ptr->stat = 1;
              status_push_ch(ptr, c);
          }else if (0xe0 <= c && c <= 0xef){
              ptr->stat = 2;
              status_push_ch(ptr, c);
          }else if (0xf0 <= c && c <= 0xf4){
              ptr->stat = 3;
              status_push_ch(ptr, c);
          }else{
              status_disable(ptr);
          }
          break;
      case 1:
      case 2:
          if (0x80 <= c && c <= 0xbf){
              status_push_ch(ptr, c);
              if (ptr->index > ptr->stat){
                  int bom = (ptr->buf[0] == 0xef && ptr->buf[1] == 0xbb
                             && ptr->buf[2] == 0xbf);
                  w2e_conv(ptr->buf[0], ptr->buf[1], ptr->buf[2],
                           &ptr->buf[0], &ptr->buf[1]);
                  if (!bom){
                      code_score(ptr);
                  }
                  status_clear(ptr);
              }
          }else{
              status_disable(ptr);
          }
          break;
      case 3:
	if (0x80 <= c && c <= 0xbf){
	    if (ptr->index < ptr->stat){
		status_push_ch(ptr, c);
	    } else {
	    	status_clear(ptr);
	    }
          }else{
              status_disable(ptr);
          }
          break;
    }
}
#endif

void code_status(nkf_char c)
{
    int action_flag = 1;
    struct input_code *result = 0;
    struct input_code *p = input_code_list;
    while (p->name){
        if (!p->status_func) {
	    ++p;
	    continue;
	}
        if (!p->status_func)
	    continue;
        (p->status_func)(p, c);
        if (p->stat > 0){
            action_flag = 0;
        }else if(p->stat == 0){
            if (result){
                action_flag = 0;
            }else{
                result = p;
            }
        }
        ++p;
    }

    if (action_flag){
        if (result && !estab_f){
            set_iconv(TRUE, result->iconv_func);
        }else if (c <= DEL){
            struct input_code *ptr = input_code_list;
            while (ptr->name){
                status_reset(ptr);
                ++ptr;
            }
        }
    }
}

#ifndef WIN32DLL
nkf_char std_getc(FILE *f)
{
    if (std_gc_ndx){
        return std_gc_buf[--std_gc_ndx];
    }
    return getc(f);
}
#endif /*WIN32DLL*/

nkf_char std_ungetc(nkf_char c, FILE *f)
{
    if (std_gc_ndx == STD_GC_BUFSIZE){
        return EOF;
    }
    std_gc_buf[std_gc_ndx++] = c;
    return c;
}

#ifndef WIN32DLL
void std_putc(nkf_char c)
{
    if(c!=EOF)
      putchar(c);
}
#endif /*WIN32DLL*/

#if !defined(PERL_XS) && !defined(WIN32DLL)
nkf_char noconvert(FILE *f)
{
    nkf_char    c;

    if (nop_f == 2)
	module_connection();
    while ((c = (*i_getc)(f)) != EOF)
      (*o_putc)(c);
    (*o_putc)(EOF);
    return 1;
}
#endif

void module_connection(void)
{
    oconv = output_conv; 
    o_putc = std_putc;

    /* replace continucation module, from output side */

    /* output redicrection */
#ifdef CHECK_OPTION
    if (noout_f || guess_f){
        o_putc = no_putc;
    }
#endif
    if (mimeout_f) {
	o_mputc = o_putc;
	o_putc = mime_putc;
	if (mimeout_f == TRUE) {
	    o_base64conv = oconv; oconv = base64_conv;
	}
	/* base64_count = 0; */
    }

    if (crmode_f) {
	o_crconv = oconv; oconv = cr_conv;
    }
    if (rot_f) {
	o_rot_conv = oconv; oconv = rot_conv;
    }
    if (iso2022jp_f) {
	o_iso2022jp_check_conv = oconv; oconv = iso2022jp_check_conv;
    }
    if (hira_f) {
	o_hira_conv = oconv; oconv = hira_conv;
    }
    if (fold_f) {
	o_fconv = oconv; oconv = fold_conv;
	f_line = 0;
    }
    if (alpha_f || x0201_f) {
	o_zconv = oconv; oconv = z_conv;
    }

    i_getc = std_getc;
    i_ungetc = std_ungetc;
    /* input redicrection */
#ifdef INPUT_OPTION
    if (cap_f){
        i_cgetc = i_getc; i_getc = cap_getc;
        i_cungetc = i_ungetc; i_ungetc= cap_ungetc;
    }
    if (url_f){
        i_ugetc = i_getc; i_getc = url_getc;
        i_uungetc = i_ungetc; i_ungetc= url_ungetc;
    }
#endif
#ifdef NUMCHAR_OPTION
    if (numchar_f){
        i_ngetc = i_getc; i_getc = numchar_getc;
        i_nungetc = i_ungetc; i_ungetc= numchar_ungetc;
    }
#endif
#ifdef UNICODE_NORMALIZATION
    if (nfc_f && input_f == UTF8_INPUT){
        i_nfc_getc = i_getc; i_getc = nfc_getc;
        i_nfc_ungetc = i_ungetc; i_ungetc= nfc_ungetc;
    }
#endif
    if (mime_f && mimebuf_f==FIXED_MIME) {
	i_mgetc = i_getc; i_getc = mime_getc;
	i_mungetc = i_ungetc; i_ungetc = mime_ungetc;
    }
    if (broken_f & 1) {
	i_bgetc = i_getc; i_getc = broken_getc;
	i_bungetc = i_ungetc; i_ungetc = broken_ungetc;
    }
    if (input_f == JIS_INPUT || input_f == EUC_INPUT || input_f == LATIN1_INPUT) {
        set_iconv(-TRUE, e_iconv);
    } else if (input_f == SJIS_INPUT) {
        set_iconv(-TRUE, s_iconv);
#ifdef UTF8_INPUT_ENABLE
    } else if (input_f == UTF8_INPUT) {
        set_iconv(-TRUE, w_iconv);
    } else if (input_f == UTF16_INPUT) {
        set_iconv(-TRUE, w_iconv16);
    } else if (input_f == UTF32_INPUT) {
        set_iconv(-TRUE, w_iconv32);
#endif
    } else {
        set_iconv(FALSE, e_iconv);
    }

    {
        struct input_code *p = input_code_list;
        while (p->name){
            status_reinit(p++);
        }
    }
}

/*
 * Check and Ignore BOM
 */
void check_bom(FILE *f)
{
    int c2;
    switch(c2 = (*i_getc)(f)){
    case 0x00:
	if((c2 = (*i_getc)(f)) == 0x00){
	    if((c2 = (*i_getc)(f)) == 0xFE){
		if((c2 = (*i_getc)(f)) == 0xFF){
		    if(!input_f){
			set_iconv(TRUE, w_iconv32);
		    }
		    if (iconv == w_iconv32) {
			input_endian = ENDIAN_BIG;
			return;
		    }
		    (*i_ungetc)(0xFF,f);
		}else (*i_ungetc)(c2,f);
		(*i_ungetc)(0xFE,f);
	    }else if(c2 == 0xFF){
		if((c2 = (*i_getc)(f)) == 0xFE){
		    if(!input_f){
			set_iconv(TRUE, w_iconv32);
		    }
		    if (iconv == w_iconv32) {
			input_endian = ENDIAN_2143;
			return;
		    }
		    (*i_ungetc)(0xFF,f);
		}else (*i_ungetc)(c2,f);
		(*i_ungetc)(0xFF,f);
	    }else (*i_ungetc)(c2,f);
	    (*i_ungetc)(0x00,f);
	}else (*i_ungetc)(c2,f);
	(*i_ungetc)(0x00,f);
	break;
    case 0xEF:
	if((c2 = (*i_getc)(f)) == 0xBB){
	    if((c2 = (*i_getc)(f)) == 0xBF){
		if(!input_f){
		    set_iconv(TRUE, w_iconv);
		}
		if (iconv == w_iconv) {
		    return;
		}
		(*i_ungetc)(0xBF,f);
	    }else (*i_ungetc)(c2,f);
	    (*i_ungetc)(0xBB,f);
	}else (*i_ungetc)(c2,f);
	(*i_ungetc)(0xEF,f);
	break;
    case 0xFE:
	if((c2 = (*i_getc)(f)) == 0xFF){
	    if((c2 = (*i_getc)(f)) == 0x00){
		if((c2 = (*i_getc)(f)) == 0x00){
		    if(!input_f){
			set_iconv(TRUE, w_iconv32);
		    }
		    if (iconv == w_iconv32) {
			input_endian = ENDIAN_3412;
			return;
		    }
		    (*i_ungetc)(0x00,f);
		}else (*i_ungetc)(c2,f);
		(*i_ungetc)(0x00,f);
	    }else (*i_ungetc)(c2,f);
	    if(!input_f){
		set_iconv(TRUE, w_iconv16);
	    }
	    if (iconv == w_iconv16) {
		input_endian = ENDIAN_BIG;
		return;
	    }
	    (*i_ungetc)(0xFF,f);
	}else (*i_ungetc)(c2,f);
	(*i_ungetc)(0xFE,f);
	break;
    case 0xFF:
	if((c2 = (*i_getc)(f)) == 0xFE){
	    if((c2 = (*i_getc)(f)) == 0x00){
		if((c2 = (*i_getc)(f)) == 0x00){
		    if(!input_f){
			set_iconv(TRUE, w_iconv32);
		    }
		    if (iconv == w_iconv32) {
			input_endian = ENDIAN_LITTLE;
			return;
		    }
		    (*i_ungetc)(0x00,f);
		}else (*i_ungetc)(c2,f);
		(*i_ungetc)(0x00,f);
	    }else (*i_ungetc)(c2,f);
	    if(!input_f){
		set_iconv(TRUE, w_iconv16);
	    }
	    if (iconv == w_iconv16) {
		input_endian = ENDIAN_LITTLE;
		return;
	    }
	    (*i_ungetc)(0xFE,f);
	}else (*i_ungetc)(c2,f);
	(*i_ungetc)(0xFF,f);
	break;
    default:
	(*i_ungetc)(c2,f);
	break;
    }
}

/*
   Conversion main loop. Code detection only. 
 */

nkf_char kanji_convert(FILE *f)
{
    nkf_char    c3, c2=0, c1, c0=0;
    int is_8bit = FALSE;

    if(input_f == SJIS_INPUT || input_f == EUC_INPUT
#ifdef UTF8_INPUT_ENABLE
       || input_f == UTF8_INPUT || input_f == UTF16_INPUT
#endif
      ){
	is_8bit = TRUE;
    }

    input_mode = ASCII;
    output_mode = ASCII;
    shift_mode = FALSE;

#define NEXT continue      /* no output, get next */
#define SEND ;             /* output c1 and c2, get next */
#define LAST break         /* end of loop, go closing  */

    module_connection();
    check_bom(f);

    while ((c1 = (*i_getc)(f)) != EOF) {
#ifdef INPUT_CODE_FIX
	if (!input_f)
#endif
	    code_status(c1);
        if (c2) {
            /* second byte */
            if (c2 > ((input_f == JIS_INPUT && ms_ucs_map_f) ? 0x92 : DEL)) {
                /* in case of 8th bit is on */
                if (!estab_f&&!mime_decode_mode) {
                    /* in case of not established yet */
                    /* It is still ambiguious */
                    if (h_conv(f, c2, c1)==EOF) 
                        LAST;
                    else 
                        c2 = 0;
                    NEXT;
                } else {
		    /* in case of already established */
		    if (c1 < AT) {
			/* ignore bogus code and not CP5022x UCD */
			c2 = 0;
			NEXT;
		    } else {
			SEND;
		    }
		}
            } else
                /* second byte, 7 bit code */
                /* it might be kanji shitfted */
                if ((c1 == DEL) || (c1 <= SPACE)) {
                    /* ignore bogus first code */
                    c2 = 0;
                    NEXT;
                } else
                    SEND;
        } else {
            /* first byte */
#ifdef UTF8_INPUT_ENABLE
	    if (iconv == w_iconv16) {
		if (input_endian == ENDIAN_BIG) {
		    c2 = c1;
		    if ((c1 = (*i_getc)(f)) != EOF) {
			if (0xD8 <= c2 && c2 <= 0xDB) {
			    if ((c0 = (*i_getc)(f)) != EOF) {
				c0 <<= 8;
				if ((c3 = (*i_getc)(f)) != EOF) {
				    c0 |= c3;
				} else c2 = EOF;
			    } else c2 = EOF;
			}
		    } else c2 = EOF;
		} else {
		    if ((c2 = (*i_getc)(f)) != EOF) {
			if (0xD8 <= c2 && c2 <= 0xDB) {
			    if ((c3 = (*i_getc)(f)) != EOF) {
				if ((c0 = (*i_getc)(f)) != EOF) {
				    c0 <<= 8;
				    c0 |= c3;
				} else c2 = EOF;
			    } else c2 = EOF;
			}
		    } else c2 = EOF;
		}
		SEND;
            } else if(iconv == w_iconv32){
		int c3 = c1;
		if((c2 = (*i_getc)(f)) != EOF &&
		   (c1 = (*i_getc)(f)) != EOF &&
		   (c0 = (*i_getc)(f)) != EOF){
		    switch(input_endian){
		    case ENDIAN_BIG:
			c1 = (c2&0xFF)<<16 | (c1&0xFF)<<8 | (c0&0xFF);
			break;
		    case ENDIAN_LITTLE:
			c1 = (c3&0xFF) | (c2&0xFF)<<8 | (c1&0xFF)<<16;
			break;
		    case ENDIAN_2143:
			c1 = (c3&0xFF)<<16 | (c1&0xFF) | (c0&0xFF)<<8;
			break;
		    case ENDIAN_3412:
			c1 = (c3&0xFF)<<8 | (c2&0xFF) | (c0&0xFF)<<16;
			break;
		    }
		    c2 = 0;
		}else{
		    c2 = EOF;
		}
		SEND;
            } else
#endif
#ifdef NUMCHAR_OPTION
            if (is_unicode_capsule(c1)){
                SEND;
	    } else
#endif
	    if (c1 > ((input_f == JIS_INPUT && ms_ucs_map_f) ? 0x92 : DEL)) {
                /* 8 bit code */
                if (!estab_f && !iso8859_f) {
                    /* not established yet */
                    c2 = c1;
                    NEXT;
                } else { /* estab_f==TRUE */
                    if (iso8859_f) {
                        c2 = ISO8859_1;
                        c1 &= 0x7f;
                        SEND;
                    } else if (SSP<=c1 && c1<0xe0 && iconv == s_iconv) {
                        /* SJIS X0201 Case... */
                        if(iso2022jp_f && x0201_f==NO_X0201) {
                            (*oconv)(GETA1, GETA2);
                            NEXT;
                        } else {
			    c2 = X0201;
			    c1 &= 0x7f;
			    SEND;
			}
                    } else if (c1==SSO && iconv != s_iconv) {
                        /* EUC X0201 Case */
                        c1 = (*i_getc)(f);  /* skip SSO */
                        code_status(c1);
                        if (SSP<=c1 && c1<0xe0) {
			    if(iso2022jp_f &&  x0201_f==NO_X0201) {
				(*oconv)(GETA1, GETA2);
				NEXT;
			    } else {
				c2 = X0201;
				c1 &= 0x7f;
				SEND;
			    }
                        } else  { /* bogus code, skip SSO and one byte */
                            NEXT;
                        }
                    } else {
                       /* already established */
                       c2 = c1;
                       NEXT;
                    }
                }
            } else if ((c1 > SPACE) && (c1 != DEL)) {
                /* in case of Roman characters */
                if (shift_mode) { 
                    /* output 1 shifted byte */
                    if (iso8859_f) {
                        c2 = ISO8859_1;
                        SEND;
                    } else if (SPACE<=c1 && c1<(0xe0&0x7f) ){
                      /* output 1 shifted byte */
			if(iso2022jp_f && x0201_f==NO_X0201) {
			    (*oconv)(GETA1, GETA2);
			    NEXT;
			} else {
			    c2 = X0201;
			    SEND;
			}
                    } else {
                        /* look like bogus code */
                        NEXT;
                    }
                } else if (input_mode == X0208 || input_mode == X0212 ||
			   input_mode == X0213_1 || input_mode == X0213_2) {
                    /* in case of Kanji shifted */
                    c2 = c1;
                    NEXT;
                } else if (c1 == '=' && mime_f && !mime_decode_mode ) {
                    /* Check MIME code */
                    if ((c1 = (*i_getc)(f)) == EOF) {
                        (*oconv)(0, '=');
                        LAST;
                    } else if (c1 == '?') {
                        /* =? is mime conversion start sequence */
			if(mime_f == STRICT_MIME) {
			    /* check in real detail */
			    if (mime_begin_strict(f) == EOF) 
				LAST;
			    else
				NEXT;
			} else if (mime_begin(f) == EOF) 
                            LAST;
                        else
                            NEXT;
                    } else {
                        (*oconv)(0, '=');
                        (*i_ungetc)(c1,f);
                        NEXT;
                    }
                } else {
                    /* normal ASCII code */ 
                    SEND;
                }
            } else if (c1 == SI && (!is_8bit || mime_decode_mode)) {
                shift_mode = FALSE; 
                NEXT;
            } else if (c1 == SO && (!is_8bit || mime_decode_mode)) {
                shift_mode = TRUE; 
                NEXT;
            } else if (c1 == ESC && (!is_8bit || mime_decode_mode)) {
                if ((c1 = (*i_getc)(f)) == EOF) {
                    /*  (*oconv)(0, ESC); don't send bogus code */
                    LAST;
                } else if (c1 == '$') {
                    if ((c1 = (*i_getc)(f)) == EOF) {
                        /*
                        (*oconv)(0, ESC); don't send bogus code 
                        (*oconv)(0, '$'); */
                        LAST;
                    } else if (c1 == '@'|| c1 == 'B') {
                        /* This is kanji introduction */
                        input_mode = X0208;
                        shift_mode = FALSE;
                        set_input_codename("ISO-2022-JP");
#ifdef CHECK_OPTION
                        debug(input_codename);
#endif
                        NEXT;
                    } else if (c1 == '(') {
                        if ((c1 = (*i_getc)(f)) == EOF) {
                            /* don't send bogus code 
                            (*oconv)(0, ESC);
                            (*oconv)(0, '$');
                            (*oconv)(0, '(');
                                */
                            LAST;
                        } else if (c1 == '@'|| c1 == 'B') {
                            /* This is kanji introduction */
                            input_mode = X0208;
                            shift_mode = FALSE;
                            NEXT;
#ifdef X0212_ENABLE
                        } else if (c1 == 'D'){
                            input_mode = X0212;
                            shift_mode = FALSE;
                            NEXT;
#endif /* X0212_ENABLE */
                        } else if (c1 == (X0213_1&0x7F)){
                            input_mode = X0213_1;
                            shift_mode = FALSE;
                            NEXT;
                        } else if (c1 == (X0213_2&0x7F)){
                            input_mode = X0213_2;
                            shift_mode = FALSE;
                            NEXT;
                        } else {
                            /* could be some special code */
                            (*oconv)(0, ESC);
                            (*oconv)(0, '$');
                            (*oconv)(0, '(');
                            (*oconv)(0, c1);
                            NEXT;
                        }
                    } else if (broken_f&0x2) {
                        /* accept any ESC-(-x as broken code ... */
                        input_mode = X0208;
                        shift_mode = FALSE;
                        NEXT;
                    } else {
                        (*oconv)(0, ESC);
                        (*oconv)(0, '$');
                        (*oconv)(0, c1);
                        NEXT;
                    }
                } else if (c1 == '(') {
                    if ((c1 = (*i_getc)(f)) == EOF) {
                        /* don't send bogus code 
                        (*oconv)(0, ESC);
                        (*oconv)(0, '('); */
                        LAST;
                    } else {
                        if (c1 == 'I') {
                            /* This is X0201 kana introduction */
                            input_mode = X0201; shift_mode = X0201;
                            NEXT;
                        } else if (c1 == 'B' || c1 == 'J' || c1 == 'H') {
                            /* This is X0208 kanji introduction */
                            input_mode = ASCII; shift_mode = FALSE;
                            NEXT;
                        } else if (broken_f&0x2) {
                            input_mode = ASCII; shift_mode = FALSE;
                            NEXT;
                        } else {
                            (*oconv)(0, ESC);
                            (*oconv)(0, '(');
                            /* maintain various input_mode here */
                            SEND;
                        }
                    }
               } else if ( c1 == 'N' || c1 == 'n' ){
                   /* SS2 */
                   c3 = (*i_getc)(f);  /* skip SS2 */
                   if ( (SPACE<=c3 && c3 < 0x60) || (0xa0<=c3 && c3 < 0xe0)){
                       c1 = c3;
                       c2 = X0201;
                       SEND;
                   }else{
                       (*i_ungetc)(c3, f);
                       /* lonely ESC  */
                       (*oconv)(0, ESC);
                       SEND;
                   }
                } else {
                    /* lonely ESC  */
                    (*oconv)(0, ESC);
                    SEND;
                }
	    } else if (c1 == ESC && iconv == s_iconv) {
		/* ESC in Shift_JIS */
		if ((c1 = (*i_getc)(f)) == EOF) {
		    /*  (*oconv)(0, ESC); don't send bogus code */
		    LAST;
		} else if (c1 == '$') {
		    /* J-PHONE emoji */
		    if ((c1 = (*i_getc)(f)) == EOF) {
			/*
			   (*oconv)(0, ESC); don't send bogus code 
			   (*oconv)(0, '$'); */
			LAST;
		    } else {
			if (('E' <= c1 && c1 <= 'G') ||
			    ('O' <= c1 && c1 <= 'Q')) {
			    /*
			       NUM : 0 1 2 3 4 5
			       BYTE: G E F O P Q
			       C%7 : 1 6 0 2 3 4
			       C%7 : 0 1 2 3 4 5 6
			       NUM : 2 0 3 4 5 X 1
			     */
			    static const int jphone_emoji_first_table[7] = {2, 0, 3, 4, 5, 0, 1};
			    c0 = (jphone_emoji_first_table[c1 % 7] << 8) - SPACE + 0xE000 + CLASS_UNICODE;
			    while ((c1 = (*i_getc)(f)) != EOF) {
				if (SPACE <= c1 && c1 <= 'z') {
				    (*oconv)(0, c1 + c0);
				} else break; /* c1 == SO */
			    }
			}
		    }
		    if (c1 == EOF) LAST;
		    NEXT;
		} else {
		    /* lonely ESC  */
		    (*oconv)(0, ESC);
		    SEND;
		}
            } else if ((c1 == NL || c1 == CR) && broken_f&4) {
                input_mode = ASCII; set_iconv(FALSE, 0);
                SEND;
	    } else if (c1 == NL && mime_decode_f && !mime_decode_mode ) {
		if ((c1=(*i_getc)(f))!=EOF && c1 == SPACE) {
		    i_ungetc(SPACE,f);
		    continue;
		} else {
		    i_ungetc(c1,f);
		}
		c1 = NL;
		SEND;
	    } else if (c1 == CR && mime_decode_f && !mime_decode_mode ) {
		if ((c1=(*i_getc)(f))!=EOF) {
		    if (c1==SPACE) {
			i_ungetc(SPACE,f);
			continue;
		    } else if (c1 == NL && (c1=(*i_getc)(f))!=EOF && c1 == SPACE) {
			i_ungetc(SPACE,f);
			continue;
		    } else {
			i_ungetc(c1,f);
		    }
		    i_ungetc(NL,f);
		} else {
		    i_ungetc(c1,f);
		}
		c1 = CR;
		SEND;
	    } else if (c1 == DEL && input_mode == X0208 ) {
		/* CP5022x */
		c2 = c1;
		NEXT;
	    } else 
                SEND;
        }
        /* send: */
	switch(input_mode){
	case ASCII:
	    switch ((*iconv)(c2, c1, c0)) {  /* can be EUC / SJIS / UTF-8 / UTF-16 */
	    case -2:
		/* 4 bytes UTF-8 */
		if ((c0 = (*i_getc)(f)) != EOF) {
		    code_status(c0);
		    c0 <<= 8;
		    if ((c3 = (*i_getc)(f)) != EOF) {
			code_status(c3);
			(*iconv)(c2, c1, c0|c3);
		    }
		}
		break;
	    case -1:
		/* 3 bytes EUC or UTF-8 */
		if ((c0 = (*i_getc)(f)) != EOF) {
		    code_status(c0);
		    (*iconv)(c2, c1, c0);
		}
		break;
	    }
	    break;
	case X0208:
	case X0213_1:
	    if (ms_ucs_map_f &&
		0x7F <= c2 && c2 <= 0x92 &&
		0x21 <= c1 && c1 <= 0x7E) {
		/* CP932 UDC */
		if(c1 == 0x7F) return 0;
		c1 = (c2 - 0x7F) * 94 + c1 - 0x21 + 0xE000 + CLASS_UNICODE;
		c2 = 0;
	    }
	    (*oconv)(c2, c1); /* this is JIS, not SJIS/EUC case */
	    break;
#ifdef X0212_ENABLE
	case X0212:
	    (*oconv)(PREFIX_EUCG3 | c2, c1);
	    break;
#endif /* X0212_ENABLE */
	case X0213_2:
	    (*oconv)(PREFIX_EUCG3 | c2, c1);
	    break;
	default:
	    (*oconv)(input_mode, c1);  /* other special case */
	}

        c2 = 0;
        c0 = 0;
        continue;
        /* goto next_word */
    }

    /* epilogue */
    (*iconv)(EOF, 0, 0);
    if (!is_inputcode_set)
    {
	if (is_8bit) {
	    struct input_code *p = input_code_list;
	    struct input_code *result = p;
	    while (p->name){
		if (p->score < result->score) result = p;
		++p;
	    }
	    set_input_codename(result->name);
	}
    }
    return 1;
}

nkf_char
h_conv(FILE *f, nkf_char c2, nkf_char c1)
{
    nkf_char ret, c3, c0;
    int hold_index;


    /** it must NOT be in the kanji shifte sequence      */
    /** it must NOT be written in JIS7                   */
    /** and it must be after 2 byte 8bit code            */

    hold_count = 0;
    push_hold_buf(c2);
    push_hold_buf(c1);

    while ((c1 = (*i_getc)(f)) != EOF) {
        if (c1 == ESC){
	    (*i_ungetc)(c1,f);
            break;
        }
        code_status(c1);
        if (push_hold_buf(c1) == EOF || estab_f){
            break;
        }
    }

    if (!estab_f){
        struct input_code *p = input_code_list;
        struct input_code *result = p;
        if (c1 == EOF){
            code_status(c1);
        }
        while (p->name){
            if (p->status_func && p->score < result->score){
                result = p;
            }
            ++p;
        }
        set_iconv(TRUE, result->iconv_func);
    }


    /** now,
     ** 1) EOF is detected, or
     ** 2) Code is established, or
     ** 3) Buffer is FULL (but last word is pushed)
     **
     ** in 1) and 3) cases, we continue to use
     ** Kanji codes by oconv and leave estab_f unchanged.
     **/

    ret = c1;
    hold_index = 0;
    while (hold_index < hold_count){
        c2 = hold_buf[hold_index++];
        if (c2 <= DEL
#ifdef NUMCHAR_OPTION
            || is_unicode_capsule(c2)
#endif
            ){
            (*iconv)(0, c2, 0);
            continue;
        }else if (iconv == s_iconv && 0xa1 <= c2 && c2 <= 0xdf){
            (*iconv)(X0201, c2, 0);
            continue;
        }
        if (hold_index < hold_count){
            c1 = hold_buf[hold_index++];
        }else{
            c1 = (*i_getc)(f);
            if (c1 == EOF){
                c3 = EOF;
                break;
            }
            code_status(c1);
        }
        c0 = 0;
        switch ((*iconv)(c2, c1, 0)) {  /* can be EUC/SJIS/UTF-8 */
	case -2:
	    /* 4 bytes UTF-8 */
            if (hold_index < hold_count){
                c0 = hold_buf[hold_index++];
            } else if ((c0 = (*i_getc)(f)) == EOF) {
		ret = EOF;
		break;
	    } else {
                code_status(c0);
		c0 <<= 8;
		if (hold_index < hold_count){
		    c3 = hold_buf[hold_index++];
		} else if ((c3 = (*i_getc)(f)) == EOF) {
		    c0 = ret = EOF;
		    break;
		} else {
		    code_status(c3);
		    (*iconv)(c2, c1, c0|c3);
		}
            }
	    break;
	case -1:
	    /* 3 bytes EUC or UTF-8 */
            if (hold_index < hold_count){
                c0 = hold_buf[hold_index++];
            } else if ((c0 = (*i_getc)(f)) == EOF) {
		ret = EOF;
		break;
	    } else {
                code_status(c0);
            }
            (*iconv)(c2, c1, c0);
            break;
	}
	if (c0 == EOF) break;
    }
    return ret;
}

nkf_char push_hold_buf(nkf_char c2)
{
    if (hold_count >= HOLD_SIZE*2)
        return (EOF);
    hold_buf[hold_count++] = (unsigned char)c2;
    return ((hold_count >= HOLD_SIZE*2) ? EOF : hold_count);
}

nkf_char s2e_conv(nkf_char c2, nkf_char c1, nkf_char *p2, nkf_char *p1)
{
#if defined(SHIFTJIS_CP932) || defined(X0212_ENABLE)
    nkf_char val;
#endif
    static const nkf_char shift_jisx0213_s1a3_table[5][2] ={ { 1, 8}, { 3, 4}, { 5,12}, {13,14}, {15, 0} };
#ifdef SHIFTJIS_CP932
    if (!cp932inv_f && is_ibmext_in_sjis(c2)){
#if 0
        extern const unsigned short shiftjis_cp932[3][189];
#endif
        val = shiftjis_cp932[c2 - CP932_TABLE_BEGIN][c1 - 0x40];
        if (val){
            c2 = val >> 8;
            c1 = val & 0xff;
        }
    }
    if (cp932inv_f
        && CP932INV_TABLE_BEGIN <= c2 && c2 <= CP932INV_TABLE_END){
#if 0
        extern const unsigned short cp932inv[2][189];
#endif
        nkf_char c = cp932inv[c2 - CP932INV_TABLE_BEGIN][c1 - 0x40];
        if (c){
            c2 = c >> 8;
            c1 = c & 0xff;
        }
    }
#endif /* SHIFTJIS_CP932 */
#ifdef X0212_ENABLE
    if (!x0213_f && is_ibmext_in_sjis(c2)){
#if 0
        extern const unsigned short shiftjis_x0212[3][189];
#endif
        val = shiftjis_x0212[c2 - 0xfa][c1 - 0x40];
        if (val){
            if (val > 0x7FFF){
                c2 = PREFIX_EUCG3 | ((val >> 8) & 0x7f);
                c1 = val & 0xff;
            }else{
                c2 = val >> 8;
                c1 = val & 0xff;
            }
            if (p2) *p2 = c2;
            if (p1) *p1 = c1;
            return 0;
        }
    }
#endif
    if(c2 >= 0x80){
	if(x0213_f && c2 >= 0xF0){
	    if(c2 <= 0xF3 || (c2 == 0xF4 && c1 < 0x9F)){ /* k=1, 3<=k<=5, k=8, 12<=k<=15 */
		c2 = PREFIX_EUCG3 | 0x20 | shift_jisx0213_s1a3_table[c2 - 0xF0][0x9E < c1];
	    }else{ /* 78<=k<=94 */
		c2 = PREFIX_EUCG3 | (c2 * 2 - 0x17B);
		if (0x9E < c1) c2++;
	    }
	}else{
	    c2 = c2 + c2 - ((c2 <= 0x9F) ? SJ0162 : SJ6394);
	    if (0x9E < c1) c2++;
	}
	if (c1 < 0x9F)
	    c1 = c1 - ((c1 > DEL) ? SPACE : 0x1F);
	else {
	    c1 = c1 - 0x7E;
	}
    }

#ifdef X0212_ENABLE
    c2 = x0212_unshift(c2);
#endif
    if (p2) *p2 = c2;
    if (p1) *p1 = c1;
    return 0;
}

nkf_char s_iconv(nkf_char c2, nkf_char c1, nkf_char c0)
{
    if (c2 == X0201) {
	c1 &= 0x7f;
    } else if ((c2 == EOF) || (c2 == 0) || c2 < SPACE) {
        /* NOP */
    } else if (!x0213_f && 0xF0 <= c2 && c2 <= 0xF9 && 0x40 <= c1 && c1 <= 0xFC) {
	/* CP932 UDC */
	if(c1 == 0x7F) return 0;
	c1 = (c2 - 0xF0) * 188 + (c1 - 0x40 - (0x7E < c1)) + 0xE000 + CLASS_UNICODE;
	c2 = 0;
    } else {
        nkf_char ret = s2e_conv(c2, c1, &c2, &c1);
        if (ret) return ret;
    }
    (*oconv)(c2, c1);
    return 0;
}

nkf_char e_iconv(nkf_char c2, nkf_char c1, nkf_char c0)
{
    if (c2 == X0201) {
	c1 &= 0x7f;
#ifdef X0212_ENABLE
    }else if (c2 == 0x8f){
        if (c0 == 0){
            return -1;
        }
	if (!cp51932_f && !x0213_f && 0xF5 <= c1 && c1 <= 0xFE && 0xA1 <= c0 && c0 <= 0xFE) {
	    /* encoding is eucJP-ms, so invert to Unicode Private User Area */
	    c1 = (c1 - 0xF5) * 94 + c0 - 0xA1 + 0xE3AC + CLASS_UNICODE;
	    c2 = 0;
	} else {
	    c2 = (c2 << 8) | (c1 & 0x7f);
	    c1 = c0 & 0x7f;
#ifdef SHIFTJIS_CP932
	    if (cp51932_f){
		nkf_char s2, s1;
		if (e2s_conv(c2, c1, &s2, &s1) == 0){
		    s2e_conv(s2, s1, &c2, &c1);
		    if (c2 < 0x100){
			c1 &= 0x7f;
			c2 &= 0x7f;
		    }
		}
	    }
#endif /* SHIFTJIS_CP932 */
        }
#endif /* X0212_ENABLE */
    } else if (c2 == SSO){
        c2 = X0201;
        c1 &= 0x7f;
    } else if ((c2 == EOF) || (c2 == 0) || c2 < SPACE) {
        /* NOP */
    } else {
	if (!cp51932_f && ms_ucs_map_f && 0xF5 <= c2 && c2 <= 0xFE && 0xA1 <= c1 && c1 <= 0xFE) {
	    /* encoding is eucJP-ms, so invert to Unicode Private User Area */
	    c1 = (c2 - 0xF5) * 94 + c1 - 0xA1 + 0xE000 + CLASS_UNICODE;
	    c2 = 0;
	} else {
	    c1 &= 0x7f;
	    c2 &= 0x7f;
#ifdef SHIFTJIS_CP932
	    if (cp51932_f && 0x79 <= c2 && c2 <= 0x7c){
		nkf_char s2, s1;
		if (e2s_conv(c2, c1, &s2, &s1) == 0){
		    s2e_conv(s2, s1, &c2, &c1);
		    if (c2 < 0x100){
			c1 &= 0x7f;
			c2 &= 0x7f;
		    }
		}
	    }
#endif /* SHIFTJIS_CP932 */
        }
    }
    (*oconv)(c2, c1);
    return 0;
}

#ifdef UTF8_INPUT_ENABLE
nkf_char w2e_conv(nkf_char c2, nkf_char c1, nkf_char c0, nkf_char *p2, nkf_char *p1)
{
    nkf_char ret = 0;

    if (!c1){
        *p2 = 0;
        *p1 = c2;
    }else if (0xc0 <= c2 && c2 <= 0xef) {
	ret =  unicode_to_jis_common(c2, c1, c0, p2, p1);
#ifdef NUMCHAR_OPTION
        if (ret > 0){
            if (p2) *p2 = 0;
            if (p1) *p1 = CLASS_UNICODE | ww16_conv(c2, c1, c0);
            ret = 0;
        }
#endif
    }
    return ret;
}

nkf_char w_iconv(nkf_char c2, nkf_char c1, nkf_char c0)
{
    nkf_char ret = 0;
    static const int w_iconv_utf8_1st_byte[] =
    { /* 0xC0 - 0xFF */
	20, 20, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
	21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
	30, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 32, 33, 33,
	40, 41, 41, 41, 42, 43, 43, 43, 50, 50, 50, 50, 60, 60, 70, 70};
    
    if (c2 < 0 || 0xff < c2) {
    }else if (c2 == 0) { /* 0 : 1 byte*/
	c0 = 0;
    } else if ((c2 & 0xc0) == 0x80) { /* 0x80-0xbf : trail byte */
	return 0;
    } else{
    	switch (w_iconv_utf8_1st_byte[c2 - 0xC0]) {
	case 21:
	    if (c1 < 0x80 || 0xBF < c1) return 0;
	    break;
	case 30:
	    if (c0 == 0) return -1;
	    if (c1 < 0xA0 || 0xBF < c1 || (c0 & 0xc0) != 0x80)
		return 0;
	    break;
	case 31:
	case 33:
	    if (c0 == 0) return -1;
	    if ((c1 & 0xc0) != 0x80 || (c0 & 0xc0) != 0x80)
		return 0;
	    break;
	case 32:
	    if (c0 == 0) return -1;
	    if (c1 < 0x80 || 0x9F < c1 || (c0 & 0xc0) != 0x80)
		return 0;
	    break;
	case 40:
	    if (c0 == 0) return -2;
	    if (c1 < 0x90 || 0xBF < c1 || (c0 & 0xc0c0) != 0x8080)
		return 0;
	    break;
	case 41:
	    if (c0 == 0) return -2;
	    if (c1 < 0x80 || 0xBF < c1 || (c0 & 0xc0c0) != 0x8080)
		return 0;
	    break;
	case 42:
	    if (c0 == 0) return -2;
	    if (c1 < 0x80 || 0x8F < c1 || (c0 & 0xc0c0) != 0x8080)
		return 0;
	    break;
	default:
	    return 0;
	    break;
	}
    }
    if (c2 == 0 || c2 == EOF){
    } else if ((c2 & 0xf8) == 0xf0) { /* 4 bytes */
	c1 = CLASS_UNICODE | ww16_conv(c2, c1, c0);
	c2 = 0;
    } else {
	ret = w2e_conv(c2, c1, c0, &c2, &c1);
    }
    if (ret == 0){
        (*oconv)(c2, c1);
    }
    return ret;
}
#endif

#if defined(UTF8_INPUT_ENABLE) || defined(UTF8_OUTPUT_ENABLE)
void w16w_conv(nkf_char val, nkf_char *p2, nkf_char *p1, nkf_char *p0)
{
    val &= VALUE_MASK;
    if (val < 0x80){
        *p2 = val;
        *p1 = 0;
        *p0 = 0;
    }else if (val < 0x800){
	*p2 = 0xc0 | (val >> 6);
	*p1 = 0x80 | (val & 0x3f);
        *p0 = 0;
    } else if (val <= NKF_INT32_C(0xFFFF)) {
        *p2 = 0xe0 | (val >> 12);
        *p1 = 0x80 | ((val >> 6) & 0x3f);
        *p0 = 0x80 | (val        & 0x3f);
    } else if (val <= NKF_INT32_C(0x10FFFF)) {
        *p2 = 0xe0 |  (val >> 16);
        *p1 = 0x80 | ((val >> 12) & 0x3f);
        *p0 = 0x8080 | ((val << 2) & 0x3f00)| (val & 0x3f);
    } else {
        *p2 = 0;
        *p1 = 0;
        *p0 = 0;
    }
}
#endif

#ifdef UTF8_INPUT_ENABLE
nkf_char ww16_conv(nkf_char c2, nkf_char c1, nkf_char c0)
{
    nkf_char val;
    if (c2 >= 0xf8) {
	val = -1;
    } else if (c2 >= 0xf0){
	/* c2: 1st, c1: 2nd, c0: 3rd/4th */
	val = (c2 & 0x0f) << 18;
        val |= (c1 & 0x3f) << 12;
        val |= (c0 & 0x3f00) >> 2;
        val |= (c0 & 0x3f);
    }else if (c2 >= 0xe0){
        val = (c2 & 0x0f) << 12;
        val |= (c1 & 0x3f) << 6;
        val |= (c0 & 0x3f);
    }else if (c2 >= 0xc0){
        val = (c2 & 0x1f) << 6;
        val |= (c1 & 0x3f);
    }else{
        val = c2;
    }
    return val;
}

nkf_char w16e_conv(nkf_char val, nkf_char *p2, nkf_char *p1)
{
    nkf_char c2, c1, c0;
    nkf_char ret = 0;
    val &= VALUE_MASK;
    if (val < 0x80){
        *p2 = 0;
        *p1 = val;
    }else{
	w16w_conv(val, &c2, &c1, &c0);
	ret =  unicode_to_jis_common(c2, c1, c0, p2, p1);
#ifdef NUMCHAR_OPTION
	if (ret > 0){
	    *p2 = 0;
	    *p1 = CLASS_UNICODE | val;
	    ret = 0;
	}
#endif
    }
    return ret;
}
#endif

#ifdef UTF8_INPUT_ENABLE
nkf_char w_iconv16(nkf_char c2, nkf_char c1, nkf_char c0)
{
    nkf_char ret = 0;
    if ((c2==0 && c1 < 0x80) || c2==EOF) {
	(*oconv)(c2, c1);
	return 0;
    }else if (0xD8 <= c2 && c2 <= 0xDB) {
	if (c0 < NKF_INT32_C(0xDC00) || NKF_INT32_C(0xDFFF) < c0)
	    return -2;
	c1 =  CLASS_UNICODE | ((c2 << 18) + (c1 << 10) + c0 - NKF_INT32_C(0x35FDC00));
	c2 = 0;
    }else if ((c2>>3) == 27) { /* unpaired surrogate */
	/*
	   return 2;
	*/
	return 1;
    }else ret = w16e_conv(((c2 & 0xff)<<8) + c1, &c2, &c1);
    if (ret) return ret;
    (*oconv)(c2, c1);
    return 0;
}

nkf_char w_iconv32(nkf_char c2, nkf_char c1, nkf_char c0)
{
    int ret = 0;

    if ((c2 == 0 && c1 < 0x80) || c2==EOF) {
    } else if (is_unicode_bmp(c1)) {
	ret = w16e_conv(c1, &c2, &c1);
    } else {
	c2 = 0;
	c1 =  CLASS_UNICODE | c1;
    }
    if (ret) return ret;
    (*oconv)(c2, c1);
    return 0;
}

nkf_char unicode_to_jis_common(nkf_char c2, nkf_char c1, nkf_char c0, nkf_char *p2, nkf_char *p1)
{
#if 0
    extern const unsigned short *const utf8_to_euc_2bytes[];
    extern const unsigned short *const utf8_to_euc_2bytes_ms[];
    extern const unsigned short *const utf8_to_euc_2bytes_932[];
    extern const unsigned short *const *const utf8_to_euc_3bytes[];
    extern const unsigned short *const *const utf8_to_euc_3bytes_ms[];
    extern const unsigned short *const *const utf8_to_euc_3bytes_932[];
#endif
    const unsigned short *const *pp;
    const unsigned short *const *const *ppp;
    static const int no_best_fit_chars_table_C2[] =
    {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 2, 1, 1, 2,
	0, 0, 1, 1, 0, 1, 0, 1, 2, 1, 1, 1, 1, 1, 1, 1};
    static const int no_best_fit_chars_table_C2_ms[] =
    {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0,
	0, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 0};
    static const int no_best_fit_chars_table_932_C2[] =
    {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1,
	0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0};
    static const int no_best_fit_chars_table_932_C3[] =
    {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1};
    nkf_char ret = 0;

    if(c2 < 0x80){
	*p2 = 0;
	*p1 = c2;
    }else if(c2 < 0xe0){
	if(no_best_fit_chars_f){
	    if(ms_ucs_map_f == UCS_MAP_CP932){
		switch(c2){
		case 0xC2:
		    if(no_best_fit_chars_table_932_C2[c1&0x3F]) return 1;
		    break;
		case 0xC3:
		    if(no_best_fit_chars_table_932_C3[c1&0x3F]) return 1;
		    break;
		}
	    }else if(!cp932inv_f){
		switch(c2){
		case 0xC2:
		    if(no_best_fit_chars_table_C2[c1&0x3F]) return 1;
		    break;
		case 0xC3:
		    if(no_best_fit_chars_table_932_C3[c1&0x3F]) return 1;
		    break;
		}
	    }else if(ms_ucs_map_f == UCS_MAP_MS){
		if(c2 == 0xC2 && no_best_fit_chars_table_C2_ms[c1&0x3F]) return 1;
	    }
	}
	pp =
	    ms_ucs_map_f == UCS_MAP_CP932 ? utf8_to_euc_2bytes_932 :
	    ms_ucs_map_f == UCS_MAP_MS ? utf8_to_euc_2bytes_ms :
	    utf8_to_euc_2bytes;
	ret =  w_iconv_common(c2, c1, pp, sizeof_utf8_to_euc_2bytes, p2, p1);
    }else if(c0 < 0xF0){
	if(no_best_fit_chars_f){
	    if(ms_ucs_map_f == UCS_MAP_CP932){
		if(c2 == 0xE3 && c1 == 0x82 && c0 == 0x94) return 1;
	    }else if(ms_ucs_map_f == UCS_MAP_MS){
		switch(c2){
		case 0xE2:
		    switch(c1){
		    case 0x80:
			if(c0 == 0x94 || c0 == 0x96 || c0 == 0xBE) return 1;
			break;
		    case 0x88:
			if(c0 == 0x92) return 1;
			break;
		    }
		    break;
		case 0xE3:
		    if(c1 == 0x80 || c0 == 0x9C) return 1;
		    break;
		}
	    }else{
		switch(c2){
		case 0xE2:
		    switch(c1){
		    case 0x80:
			if(c0 == 0x95) return 1;
			break;
		    case 0x88:
			if(c0 == 0xA5) return 1;
			break;
		    }
		    break;
		case 0xEF:
		    switch(c1){
		    case 0xBC:
			if(c0 == 0x8D) return 1;
			break;
		    case 0xBD:
			if(c0 == 0x9E && !cp932inv_f) return 1;
			break;
		    case 0xBF:
			if(0xA0 <= c0 && c0 <= 0xA5) return 1;
			break;
		    }
		    break;
		}
	    }
	}
	ppp =
	    ms_ucs_map_f == UCS_MAP_CP932 ? utf8_to_euc_3bytes_932 :
	    ms_ucs_map_f == UCS_MAP_MS ? utf8_to_euc_3bytes_ms :
	    utf8_to_euc_3bytes;
	ret = w_iconv_common(c1, c0, ppp[c2 - 0xE0], sizeof_utf8_to_euc_C2, p2, p1);
    }else return -1;
#ifdef SHIFTJIS_CP932
    if (!ret && !cp932inv_f && is_eucg3(*p2)) {
	nkf_char s2, s1;
	if (e2s_conv(*p2, *p1, &s2, &s1) == 0) {
	    s2e_conv(s2, s1, p2, p1);
	}else{
	    ret = 1;
	}
    }
#endif
    return ret;
}

nkf_char w_iconv_common(nkf_char c1, nkf_char c0, const unsigned short *const *pp, nkf_char psize, nkf_char *p2, nkf_char *p1)
{
    nkf_char c2;
    const unsigned short *p;
    unsigned short val;

    if (pp == 0) return 1;

    c1 -= 0x80;
    if (c1 < 0 || psize <= c1) return 1;
    p = pp[c1];
    if (p == 0)  return 1;

    c0 -= 0x80;
    if (c0 < 0 || sizeof_utf8_to_euc_C2 <= c0) return 1;
    val = p[c0];
    if (val == 0) return 1;
    if (no_cp932ext_f && (
	(val>>8) == 0x2D || /* NEC special characters */
	val > NKF_INT32_C(0xF300) /* IBM extended characters */
	)) return 1;

    c2 = val >> 8;
   if (val > 0x7FFF){
        c2 &= 0x7f;
        c2 |= PREFIX_EUCG3;
    }
    if (c2 == SO) c2 = X0201;
    c1 = val & 0x7f;
    if (p2) *p2 = c2;
    if (p1) *p1 = c1;
    return 0;
}

void nkf_each_char_to_hex(void (*f)(nkf_char c2,nkf_char c1), nkf_char c)
{
    const char *hex = "0123456789ABCDEF";
    int shift = 20;
    c &= VALUE_MASK;
    while(shift >= 0){
	if(c >= 1<<shift){
	    while(shift >= 0){
		(*f)(0, hex[(c>>shift)&0xF]);
		shift -= 4;
	    }
	}else{
	    shift -= 4;
	}
    }
    return;
}

void encode_fallback_html(nkf_char c)
{
    (*oconv)(0, '&');
    (*oconv)(0, '#');
    c &= VALUE_MASK;
    if(c >= NKF_INT32_C(1000000))
	(*oconv)(0, 0x30+(c/NKF_INT32_C(1000000))%10);
    if(c >= NKF_INT32_C(100000))
	(*oconv)(0, 0x30+(c/NKF_INT32_C(100000) )%10);
    if(c >= 10000)
	(*oconv)(0, 0x30+(c/10000  )%10);
    if(c >= 1000)
	(*oconv)(0, 0x30+(c/1000   )%10);
    if(c >= 100)
	(*oconv)(0, 0x30+(c/100    )%10);
    if(c >= 10)
	(*oconv)(0, 0x30+(c/10     )%10);
    if(c >= 0)
	(*oconv)(0, 0x30+ c         %10);
    (*oconv)(0, ';');
    return;
}

void encode_fallback_xml(nkf_char c)
{
    (*oconv)(0, '&');
    (*oconv)(0, '#');
    (*oconv)(0, 'x');
    nkf_each_char_to_hex(oconv, c);
    (*oconv)(0, ';');
    return;
}

void encode_fallback_java(nkf_char c)
{
    const char *hex = "0123456789ABCDEF";
    (*oconv)(0, '\\');
    c &= VALUE_MASK;
    if(!is_unicode_bmp(c)){
	(*oconv)(0, 'U');
	(*oconv)(0, '0');
	(*oconv)(0, '0');
	(*oconv)(0, hex[(c>>20)&0xF]);
	(*oconv)(0, hex[(c>>16)&0xF]);
    }else{
	(*oconv)(0, 'u');
    }
    (*oconv)(0, hex[(c>>12)&0xF]);
    (*oconv)(0, hex[(c>> 8)&0xF]);
    (*oconv)(0, hex[(c>> 4)&0xF]);
    (*oconv)(0, hex[ c     &0xF]);
    return;
}

void encode_fallback_perl(nkf_char c)
{
    (*oconv)(0, '\\');
    (*oconv)(0, 'x');
    (*oconv)(0, '{');
    nkf_each_char_to_hex(oconv, c);
    (*oconv)(0, '}');
    return;
}

void encode_fallback_subchar(nkf_char c)
{
    c = unicode_subchar;
    (*oconv)((c>>8)&0xFF, c&0xFF);
    return;
}
#endif

#ifdef UTF8_OUTPUT_ENABLE
nkf_char e2w_conv(nkf_char c2, nkf_char c1)
{
#if 0
    extern const unsigned short euc_to_utf8_1byte[];
    extern const unsigned short *const euc_to_utf8_2bytes[];
    extern const unsigned short *const euc_to_utf8_2bytes_ms[];
    extern const unsigned short *const x0212_to_utf8_2bytes[];
#endif
    const unsigned short *p;

    if (c2 == X0201) {
        p = euc_to_utf8_1byte;
#ifdef X0212_ENABLE
    } else if (is_eucg3(c2)){
	if(ms_ucs_map_f == UCS_MAP_ASCII&& c2 == NKF_INT32_C(0x8F22) && c1 == 0x43){
	    return 0xA6;
	}
        c2 = (c2&0x7f) - 0x21;
        if (0<=c2 && c2<sizeof_euc_to_utf8_2bytes)
	    p = x0212_to_utf8_2bytes[c2];
        else
            return 0;
#endif
    } else {
        c2 &= 0x7f;
        c2 = (c2&0x7f) - 0x21;
        if (0<=c2 && c2<sizeof_euc_to_utf8_2bytes)
            p = ms_ucs_map_f != UCS_MAP_ASCII ? euc_to_utf8_2bytes_ms[c2] : euc_to_utf8_2bytes[c2];
	else
	    return 0;
    }
    if (!p) return 0;
    c1 = (c1 & 0x7f) - 0x21;
    if (0<=c1 && c1<sizeof_euc_to_utf8_1byte)
	return p[c1];
    return 0;
}

void w_oconv(nkf_char c2, nkf_char c1)
{
    nkf_char c0;
    nkf_char val;

    if (output_bom_f) {
	output_bom_f = FALSE;
    	(*o_putc)('\357');
	(*o_putc)('\273');
	(*o_putc)('\277');
    }

    if (c2 == EOF) {
        (*o_putc)(EOF);
        return;
    }

#ifdef NUMCHAR_OPTION
    if (c2 == 0 && is_unicode_capsule(c1)){
        val = c1 & VALUE_MASK;
        if (val < 0x80){
            (*o_putc)(val);
        }else if (val < 0x800){
            (*o_putc)(0xC0 | (val >> 6));
            (*o_putc)(0x80 | (val & 0x3f));
        } else if (val <= NKF_INT32_C(0xFFFF)) {
            (*o_putc)(0xE0 | (val >> 12));
            (*o_putc)(0x80 | ((val >> 6) & 0x3f));
            (*o_putc)(0x80 | (val        & 0x3f));
        } else if (val <= NKF_INT32_C(0x10FFFF)) {
            (*o_putc)(0xF0 | ( val>>18));
            (*o_putc)(0x80 | ((val>>12) & 0x3f));
            (*o_putc)(0x80 | ((val>> 6) & 0x3f));
            (*o_putc)(0x80 | ( val      & 0x3f));
        }
        return;
    }
#endif

    if (c2 == 0) { 
	output_mode = ASCII;
        (*o_putc)(c1);
    } else if (c2 == ISO8859_1) {
	output_mode = ISO8859_1;
        (*o_putc)(c1 | 0x080);
    } else {
        output_mode = UTF8;
	val = e2w_conv(c2, c1);
        if (val){
            w16w_conv(val, &c2, &c1, &c0);
            (*o_putc)(c2);
            if (c1){
                (*o_putc)(c1);
                if (c0) (*o_putc)(c0);
            }
        }
    }
}

void w_oconv16(nkf_char c2, nkf_char c1)
{
    if (output_bom_f) {
	output_bom_f = FALSE;
        if (output_endian == ENDIAN_LITTLE){
            (*o_putc)((unsigned char)'\377');
            (*o_putc)('\376');
        }else{
            (*o_putc)('\376');
            (*o_putc)((unsigned char)'\377');
        }
    }

    if (c2 == EOF) {
        (*o_putc)(EOF);
        return;
    }

    if (c2 == ISO8859_1) {
        c2 = 0;
        c1 |= 0x80;
#ifdef NUMCHAR_OPTION
    } else if (c2 == 0 && is_unicode_capsule(c1)) {
        if (is_unicode_bmp(c1)) {
            c2 = (c1 >> 8) & 0xff;
            c1 &= 0xff;
        } else {
            c1 &= VALUE_MASK;
            if (c1 <= UNICODE_MAX) {
                c2 = (c1 >> 10) + NKF_INT32_C(0xD7C0);   /* high surrogate */
                c1 = (c1 & 0x3FF) + NKF_INT32_C(0xDC00); /* low surrogate */
                if (output_endian == ENDIAN_LITTLE){
                    (*o_putc)(c2 & 0xff);
                    (*o_putc)((c2 >> 8) & 0xff);
                    (*o_putc)(c1 & 0xff);
                    (*o_putc)((c1 >> 8) & 0xff);
                }else{
                    (*o_putc)((c2 >> 8) & 0xff);
                    (*o_putc)(c2 & 0xff);
                    (*o_putc)((c1 >> 8) & 0xff);
                    (*o_putc)(c1 & 0xff);
                }
            }
            return;
        }
#endif
    } else if (c2) {
        nkf_char val = e2w_conv(c2, c1);
        c2 = (val >> 8) & 0xff;
        c1 = val & 0xff;
	if (!val) return;
    }
    if (output_endian == ENDIAN_LITTLE){
        (*o_putc)(c1);
        (*o_putc)(c2);
    }else{
        (*o_putc)(c2);
        (*o_putc)(c1);
    }
}

void w_oconv32(nkf_char c2, nkf_char c1)
{
    if (output_bom_f) {
	output_bom_f = FALSE;
        if (output_endian == ENDIAN_LITTLE){
            (*o_putc)((unsigned char)'\377');
            (*o_putc)('\376');
	    (*o_putc)('\000');
	    (*o_putc)('\000');
        }else{
	    (*o_putc)('\000');
	    (*o_putc)('\000');
            (*o_putc)('\376');
            (*o_putc)((unsigned char)'\377');
        }
    }

    if (c2 == EOF) {
        (*o_putc)(EOF);
        return;
    }

    if (c2 == ISO8859_1) {
        c1 |= 0x80;
#ifdef NUMCHAR_OPTION
    } else if (c2 == 0 && is_unicode_capsule(c1)) {
	c1 &= VALUE_MASK;
#endif
    } else if (c2) {
        c1 = e2w_conv(c2, c1);
	if (!c1) return;
    }
    if (output_endian == ENDIAN_LITTLE){
        (*o_putc)( c1 & NKF_INT32_C(0x000000FF));
        (*o_putc)((c1 & NKF_INT32_C(0x0000FF00)) >>  8);
        (*o_putc)((c1 & NKF_INT32_C(0x00FF0000)) >> 16);
	(*o_putc)('\000');
    }else{
	(*o_putc)('\000');
        (*o_putc)((c1 & NKF_INT32_C(0x00FF0000)) >> 16);
        (*o_putc)((c1 & NKF_INT32_C(0x0000FF00)) >>  8);
        (*o_putc)( c1 & NKF_INT32_C(0x000000FF));
    }
}
#endif

void e_oconv(nkf_char c2, nkf_char c1)
{
#ifdef NUMCHAR_OPTION
    if (c2 == 0 && is_unicode_capsule(c1)){
        w16e_conv(c1, &c2, &c1);
        if (c2 == 0 && is_unicode_capsule(c1)){
	    c2 = c1 & VALUE_MASK;
	    if (x0212_f && 0xE000 <= c2 && c2 <= 0xE757) {
		/* eucJP-ms UDC */
		c1 &= 0xFFF;
		c2 = c1 / 94;
		c2 += c2 < 10 ? 0x75 : 0x8FEB;
		c1 = 0x21 + c1 % 94;
		if (is_eucg3(c2)){
		    (*o_putc)(0x8f);
		    (*o_putc)((c2 & 0x7f) | 0x080);
		    (*o_putc)(c1 | 0x080);
		}else{
		    (*o_putc)((c2 & 0x7f) | 0x080);
		    (*o_putc)(c1 | 0x080);
		}
		return;
	    } else {
		if (encode_fallback) (*encode_fallback)(c1);
		return;
	    }
        }
    }
#endif
    if (c2 == EOF) {
        (*o_putc)(EOF);
        return;
    } else if (c2 == 0) { 
	output_mode = ASCII;
        (*o_putc)(c1);
    } else if (c2 == X0201) {
	output_mode = JAPANESE_EUC;
        (*o_putc)(SSO); (*o_putc)(c1|0x80);
    } else if (c2 == ISO8859_1) {
	output_mode = ISO8859_1;
        (*o_putc)(c1 | 0x080);
#ifdef X0212_ENABLE
    } else if (is_eucg3(c2)){
	output_mode = JAPANESE_EUC;
#ifdef SHIFTJIS_CP932
        if (!cp932inv_f){
            nkf_char s2, s1;
            if (e2s_conv(c2, c1, &s2, &s1) == 0){
                s2e_conv(s2, s1, &c2, &c1);
            }
        }
#endif
        if (c2 == 0) {
	    output_mode = ASCII;
	    (*o_putc)(c1);
	}else if (is_eucg3(c2)){
            if (x0212_f){
                (*o_putc)(0x8f);
                (*o_putc)((c2 & 0x7f) | 0x080);
                (*o_putc)(c1 | 0x080);
            }
        }else{
            (*o_putc)((c2 & 0x7f) | 0x080);
            (*o_putc)(c1 | 0x080);
        }
#endif
    } else {
        if (!nkf_isgraph(c1) || !nkf_isgraph(c2)) {
            set_iconv(FALSE, 0);
            return; /* too late to rescue this char */
        }
	output_mode = JAPANESE_EUC;
        (*o_putc)(c2 | 0x080);
        (*o_putc)(c1 | 0x080);
    }
}

#ifdef X0212_ENABLE
nkf_char x0212_shift(nkf_char c)
{
    nkf_char ret = c;
    c &= 0x7f;
    if (is_eucg3(ret)){
        if (0x75 <= c && c <= 0x7f){
            ret = c + (0x109 - 0x75);
        }
    }else{
        if (0x75 <= c && c <= 0x7f){
            ret = c + (0x113 - 0x75);
        }
    }
    return ret;
}


nkf_char x0212_unshift(nkf_char c)
{
    nkf_char ret = c;
    if (0x7f <= c && c <= 0x88){
        ret = c + (0x75 - 0x7f);
    }else if (0x89 <= c && c <= 0x92){
        ret = PREFIX_EUCG3 | 0x80 | (c + (0x75 - 0x89));
    }
    return ret;
}
#endif /* X0212_ENABLE */

nkf_char e2s_conv(nkf_char c2, nkf_char c1, nkf_char *p2, nkf_char *p1)
{
    nkf_char ndx;
    if (is_eucg3(c2)){
	ndx = c2 & 0x7f;
	if (x0213_f){
	    if((0x21 <= ndx && ndx <= 0x2F)){
		if (p2) *p2 = ((ndx - 1) >> 1) + 0xec - ndx / 8 * 3;
		if (p1) *p1 = c1 + ((ndx & 1) ? ((c1 < 0x60) ? 0x1f : 0x20) : 0x7e);
		return 0;
	    }else if(0x6E <= ndx && ndx <= 0x7E){
		if (p2) *p2 = ((ndx - 1) >> 1) + 0xbe;
		if (p1) *p1 = c1 + ((ndx & 1) ? ((c1 < 0x60) ? 0x1f : 0x20) : 0x7e);
		return 0;
	    }
	    return 1;
	}
#ifdef X0212_ENABLE
	else if(nkf_isgraph(ndx)){
	    nkf_char val = 0;
	    const unsigned short *ptr;
#if 0
	    extern const unsigned short *const x0212_shiftjis[];
#endif
	    ptr = x0212_shiftjis[ndx - 0x21];
	    if (ptr){
		val = ptr[(c1 & 0x7f) - 0x21];
	    }
	    if (val){
		c2 = val >> 8;
		c1 = val & 0xff;
		if (p2) *p2 = c2;
		if (p1) *p1 = c1;
		return 0;
	    }
	    c2 = x0212_shift(c2);
	}
#endif /* X0212_ENABLE */
    }
    if(0x7F < c2) return 1;
    if (p2) *p2 = ((c2 - 1) >> 1) + ((c2 <= 0x5e) ? 0x71 : 0xb1);
    if (p1) *p1 = c1 + ((c2 & 1) ? ((c1 < 0x60) ? 0x1f : 0x20) : 0x7e);
    return 0;
}

void s_oconv(nkf_char c2, nkf_char c1)
{
#ifdef NUMCHAR_OPTION
    if (c2 == 0 && is_unicode_capsule(c1)){
        w16e_conv(c1, &c2, &c1);
        if (c2 == 0 && is_unicode_capsule(c1)){
	    c2 = c1 & VALUE_MASK;
	    if (!x0213_f && 0xE000 <= c2 && c2 <= 0xE757) {
		/* CP932 UDC */
		c1 &= 0xFFF;
		c2 = c1 / 188 + 0xF0;
		c1 = c1 % 188;
		c1 += 0x40 + (c1 > 0x3e);
		(*o_putc)(c2);
		(*o_putc)(c1);
		return;
	    } else {
		if(encode_fallback)(*encode_fallback)(c1);
		return;
	    }
	}
    }
#endif
    if (c2 == EOF) {
        (*o_putc)(EOF);
        return;
    } else if (c2 == 0) {
	output_mode = ASCII;
        (*o_putc)(c1);
    } else if (c2 == X0201) {
	output_mode = SHIFT_JIS;
        (*o_putc)(c1|0x80);
    } else if (c2 == ISO8859_1) {
	output_mode = ISO8859_1;
        (*o_putc)(c1 | 0x080);
#ifdef X0212_ENABLE
    } else if (is_eucg3(c2)){
	output_mode = SHIFT_JIS;
        if (e2s_conv(c2, c1, &c2, &c1) == 0){
            (*o_putc)(c2);
            (*o_putc)(c1);
        }
#endif
    } else {
        if (!nkf_isprint(c1) || !nkf_isprint(c2)) {
            set_iconv(FALSE, 0);
            return; /* too late to rescue this char */
        }
	output_mode = SHIFT_JIS;
        e2s_conv(c2, c1, &c2, &c1);

#ifdef SHIFTJIS_CP932
        if (cp932inv_f
            && CP932INV_TABLE_BEGIN <= c2 && c2 <= CP932INV_TABLE_END){
#if 0
            extern const unsigned short cp932inv[2][189];
#endif
            nkf_char c = cp932inv[c2 - CP932INV_TABLE_BEGIN][c1 - 0x40];
            if (c){
                c2 = c >> 8;
                c1 = c & 0xff;
            }
        }
#endif /* SHIFTJIS_CP932 */

        (*o_putc)(c2);
	if (prefix_table[(unsigned char)c1]){
            (*o_putc)(prefix_table[(unsigned char)c1]);
	}
        (*o_putc)(c1);
    }
}

void j_oconv(nkf_char c2, nkf_char c1)
{
#ifdef NUMCHAR_OPTION
    if (c2 == 0 && is_unicode_capsule(c1)){
        w16e_conv(c1, &c2, &c1);
        if (c2 == 0 && is_unicode_capsule(c1)){
	    c2 = c1 & VALUE_MASK;
	    if (ms_ucs_map_f && 0xE000 <= c2 && c2 <= 0xE757) {
		/* CP5022x UDC */
		c1 &= 0xFFF;
		c2 = 0x7F + c1 / 94;
		c1 = 0x21 + c1 % 94;
	    } else {
		if (encode_fallback) (*encode_fallback)(c1);
		return;
	    }
        }
    }
#endif
    if (c2 == EOF) {
        if (output_mode !=ASCII && output_mode!=ISO8859_1) {
            (*o_putc)(ESC);
            (*o_putc)('(');
            (*o_putc)(ascii_intro);
	    output_mode = ASCII;
        }
        (*o_putc)(EOF);
#ifdef X0212_ENABLE
    } else if (is_eucg3(c2)){
	if(x0213_f){
	    if(output_mode!=X0213_2){
		output_mode = X0213_2;
		(*o_putc)(ESC);
		(*o_putc)('$');
		(*o_putc)('(');
		(*o_putc)(X0213_2&0x7F);
	    }
	}else{
	    if(output_mode!=X0212){
		output_mode = X0212;
		(*o_putc)(ESC);
		(*o_putc)('$');
		(*o_putc)('(');
		(*o_putc)(X0212&0x7F);
	    }
        }
        (*o_putc)(c2 & 0x7f);
        (*o_putc)(c1);
#endif
    } else if (c2==X0201) {
        if (output_mode!=X0201) {
            output_mode = X0201;
            (*o_putc)(ESC);
            (*o_putc)('(');
            (*o_putc)('I');
        }
        (*o_putc)(c1);
    } else if (c2==ISO8859_1) {
            /* iso8859 introduction, or 8th bit on */
            /* Can we convert in 7bit form using ESC-'-'-A ? 
               Is this popular? */
	output_mode = ISO8859_1;
        (*o_putc)(c1|0x80);
    } else if (c2 == 0) {
        if (output_mode !=ASCII && output_mode!=ISO8859_1) {
            (*o_putc)(ESC);
            (*o_putc)('(');
            (*o_putc)(ascii_intro);
            output_mode = ASCII;
        }
        (*o_putc)(c1);
    } else {
	if(ms_ucs_map_f
	   ? c2<0x20 || 0x92<c2 || c1<0x20 || 0x7e<c1
	   : c2<0x20 || 0x7e<c2 || c1<0x20 || 0x7e<c1) return;
	if(x0213_f){
	    if (output_mode!=X0213_1) {
		output_mode = X0213_1;
		(*o_putc)(ESC);
		(*o_putc)('$');
		(*o_putc)('(');
		(*o_putc)(X0213_1&0x7F);
	    }
	}else if (output_mode != X0208) {
            output_mode = X0208;
            (*o_putc)(ESC);
            (*o_putc)('$');
            (*o_putc)(kanji_intro);
        }
        (*o_putc)(c2);
        (*o_putc)(c1);
    }
}

void base64_conv(nkf_char c2, nkf_char c1)
{
    mime_prechar(c2, c1);
    (*o_base64conv)(c2,c1);
}


static nkf_char broken_buf[3];
static int broken_counter = 0;
static int broken_last = 0;
nkf_char broken_getc(FILE *f)
{
    nkf_char c,c1;

    if (broken_counter>0) {
	return broken_buf[--broken_counter];
    }
    c= (*i_bgetc)(f);
    if (c=='$' && broken_last != ESC 
            && (input_mode==ASCII || input_mode==X0201)) {
	c1= (*i_bgetc)(f);
	broken_last = 0;
	if (c1=='@'|| c1=='B') {
	    broken_buf[0]=c1; broken_buf[1]=c; 
	    broken_counter=2;
	    return ESC;
	} else {
	    (*i_bungetc)(c1,f);
	    return c;
	}
    } else if (c=='(' && broken_last != ESC 
            && (input_mode==X0208 || input_mode==X0201)) { /* ) */
	c1= (*i_bgetc)(f);
	broken_last = 0;
	if (c1=='J'|| c1=='B') {
	    broken_buf[0]=c1; broken_buf[1]=c;
	    broken_counter=2;
	    return ESC;
	} else {
	    (*i_bungetc)(c1,f);
	    return c;
	}
    } else {
	broken_last = c;
	return c;
    }
}

nkf_char broken_ungetc(nkf_char c, FILE *f)
{
    if (broken_counter<2)
	broken_buf[broken_counter++]=c;
    return c;
}

static nkf_char prev_cr = 0;

void cr_conv(nkf_char c2, nkf_char c1)
{
    if (prev_cr) {
	prev_cr = 0;
	if (! (c2==0&&c1==NL) ) {
	    cr_conv(0,'\n');
	}
    }
    if (c2) {
        (*o_crconv)(c2,c1);
    } else if (c1=='\r') {
	prev_cr = c1;
    } else if (c1=='\n') {
        if (crmode_f==CRLF) {
            (*o_crconv)(0,'\r');
	} else if (crmode_f==CR) {
            (*o_crconv)(0,'\r');
	    return;
	} 
	(*o_crconv)(0,NL);
    } else if (c1!='\032' || crmode_f!=NL){
        (*o_crconv)(c2,c1);
    }
}

/* 
  Return value of fold_conv()

       \n  add newline  and output char
       \r  add newline  and output nothing
       ' ' space
       0   skip  
       1   (or else) normal output 

  fold state in prev (previous character)

      >0x80 Japanese (X0208/X0201)
      <0x80 ASCII
      \n    new line 
      ' '   space

  This fold algorthm does not preserve heading space in a line.
  This is the main difference from fmt.
*/

#define char_size(c2,c1) (c2?2:1)

void fold_conv(nkf_char c2, nkf_char c1)
{ 
    nkf_char prev0;
    nkf_char fold_state;

    if (c1== '\r' && !fold_preserve_f) {
    	fold_state=0;  /* ignore cr */
    }else if (c1== '\n'&&f_prev=='\r' && fold_preserve_f) {
        f_prev = '\n';
     	fold_state=0;  /* ignore cr */
    } else if (c1== BS) {
        if (f_line>0) f_line--;
        fold_state =  1;
    } else if (c2==EOF && f_line != 0) {    /* close open last line */
            fold_state = '\n';
    } else if ((c1=='\n' && !fold_preserve_f)
               || ((c1=='\r'||(c1=='\n'&&f_prev!='\r'))
                   && fold_preserve_f)) {
        /* new line */
        if (fold_preserve_f) { 
            f_prev = c1;
            f_line = 0;
            fold_state =  '\r';
	} else if ((f_prev == c1 && !fold_preserve_f)
                   || (f_prev == '\n' && fold_preserve_f)
                   ) {        /* duplicate newline */
            if (f_line) {
                f_line = 0;
                fold_state =  '\n';    /* output two newline */
            } else {
                f_line = 0;
                fold_state =  1;
            }
        } else  {
            if (f_prev&0x80) {     /* Japanese? */
                f_prev = c1;
                fold_state =  0;       /* ignore given single newline */
            } else if (f_prev==' ') {
                fold_state =  0;
            } else {
                f_prev = c1;
                if (++f_line<=fold_len) 
                    fold_state =  ' ';
                else {
                    f_line = 0;
                    fold_state =  '\r';        /* fold and output nothing */
                }
            }
        }
    } else if (c1=='\f') {
        f_prev = '\n';
        f_line = 0;
        fold_state =  '\n';            /* output newline and clear */
    } else if ( (c2==0  && c1==' ')||
               (c2==0  && c1=='\t')||
               (c2=='!'&& c1=='!')) {
        /* X0208 kankaku or ascii space */
            if (f_prev == ' ') {
                fold_state = 0;         /* remove duplicate spaces */
            } else {
                f_prev = ' ';    
                if (++f_line<=fold_len) 
                    fold_state = ' ';         /* output ASCII space only */
                else {
                    f_prev = ' '; f_line = 0;
                    fold_state = '\r';        /* fold and output nothing */
                }
            }
    } else {
        prev0 = f_prev; /* we still need this one... , but almost done */
        f_prev = c1;
        if (c2 || c2==X0201) 
            f_prev |= 0x80;  /* this is Japanese */
        f_line += char_size(c2,c1);
        if (f_line<=fold_len) {   /* normal case */
            fold_state = 1;
        } else {
            if (f_line>fold_len+fold_margin) { /* too many kinsoku suspension */
                f_line = char_size(c2,c1);
                fold_state =  '\n';       /* We can't wait, do fold now */
            } else if (c2==X0201) {
            /* simple kinsoku rules  return 1 means no folding  */
                if (c1==(0xde&0x7f)) fold_state = 1; /* ゛*/
                else if (c1==(0xdf&0x7f)) fold_state = 1; /* ゜*/
                else if (c1==(0xa4&0x7f)) fold_state = 1; /* 。*/
                else if (c1==(0xa3&0x7f)) fold_state = 1; /* ，*/
                else if (c1==(0xa1&0x7f)) fold_state = 1; /* 」*/
                else if (c1==(0xb0&0x7f)) fold_state = 1; /* - */
                else if (SPACE<=c1 && c1<=(0xdf&0x7f)) {      /* X0201 */
		    f_line = 1;
		    fold_state = '\n';/* add one new f_line before this character */
		} else {
		    f_line = 1;
		    fold_state = '\n';/* add one new f_line before this character */
		}
            } else if (c2==0) {
                /* kinsoku point in ASCII */ 
		if (  c1==')'||    /* { [ ( */
                     c1==']'||
                     c1=='}'||
                     c1=='.'||
                     c1==','||
                     c1=='!'||
                     c1=='?'||
                     c1=='/'||
                     c1==':'||
                     c1==';' ) {
		    fold_state = 1;
		/* just after special */
		} else if (!is_alnum(prev0)) {
		    f_line = char_size(c2,c1);
		    fold_state = '\n';
		} else if ((prev0==' ') ||   /* ignored new f_line */
                      (prev0=='\n')||        /* ignored new f_line */
                      (prev0&0x80)) {        /* X0208 - ASCII */
		    f_line = char_size(c2,c1);
                    fold_state = '\n';/* add one new f_line before this character */
                } else {
                    fold_state = 1;  /* default no fold in ASCII */
                }
            } else {
                if (c2=='!') {
                    if (c1=='"')  fold_state = 1; /* 、 */
                    else if (c1=='#')  fold_state = 1; /* 。 */
                    else if (c1=='W')  fold_state = 1; /* 」 */
                    else if (c1=='K')  fold_state = 1; /* ） */
                    else if (c1=='$')  fold_state = 1; /* ， */
                    else if (c1=='%')  fold_state = 1; /* ． */
                    else if (c1=='\'') fold_state = 1; /* ＋ */
                    else if (c1=='(')  fold_state = 1; /* ； */
                    else if (c1==')')  fold_state = 1; /* ？ */
                    else if (c1=='*')  fold_state = 1; /* ！ */
                    else if (c1=='+')  fold_state = 1; /* ゛ */
                    else if (c1==',')  fold_state = 1; /* ゜ */
                         /* default no fold in kinsoku */
		    else { 
			fold_state = '\n';
			f_line = char_size(c2,c1);
			/* add one new f_line before this character */
		    }
                } else {
		    f_line = char_size(c2,c1);
                    fold_state = '\n'; 
                    /* add one new f_line before this character */
                }
            }
        }
    }
    /* terminator process */
    switch(fold_state) {
        case '\n': 
            (*o_fconv)(0,'\n');
            (*o_fconv)(c2,c1);
            break;
        case 0:    
            return;
        case '\r': 
            (*o_fconv)(0,'\n');
            break;
        case '\t': 
        case ' ': 
            (*o_fconv)(0,' ');
            break;
        default:
            (*o_fconv)(c2,c1);
    }
}

nkf_char z_prev2=0,z_prev1=0;

void z_conv(nkf_char c2, nkf_char c1)
{

    /* if (c2) c1 &= 0x7f; assertion */

    if (x0201_f && z_prev2==X0201) {  /* X0201 */
        if (c1==(0xde&0x7f)) { /* 濁点 */
            z_prev2=0;
            (*o_zconv)(dv[(z_prev1-SPACE)*2],dv[(z_prev1-SPACE)*2+1]);
            return;
        } else if (c1==(0xdf&0x7f)&&ev[(z_prev1-SPACE)*2]) {  /* 半濁点 */
            z_prev2=0;
            (*o_zconv)(ev[(z_prev1-SPACE)*2],ev[(z_prev1-SPACE)*2+1]);
            return;
        } else {
            z_prev2=0;
            (*o_zconv)(cv[(z_prev1-SPACE)*2],cv[(z_prev1-SPACE)*2+1]);
        }
    }

    if (c2==EOF) {
        (*o_zconv)(c2,c1);
        return;
    }

    if (x0201_f && c2==X0201) {
        if (dv[(c1-SPACE)*2]||ev[(c1-SPACE)*2]) {
            /* wait for 濁点 or 半濁点 */
            z_prev1 = c1; z_prev2 = c2;
            return;
        } else {
            (*o_zconv)(cv[(c1-SPACE)*2],cv[(c1-SPACE)*2+1]);
            return;
        }
    }

    /* JISX0208 Alphabet */
    if (alpha_f && c2 == 0x23 ) {
        c2 = 0;
    } else if (alpha_f && c2 == 0x21 ) { 
    /* JISX0208 Kigou */
       if (0x21==c1) {
           if (alpha_f&0x2) {
               c1 = ' ';
               c2 = 0;
           } else if (alpha_f&0x4) {
                (*o_zconv)(0,' ');
                (*o_zconv)(0,' ');
                return;
           } 
       } else if (0x20<c1 && c1<0x7f && fv[c1-0x20]) {
           c1 = fv[c1-0x20];
           c2 =  0;
           if (alpha_f&0x8) {
               char *entity = 0;
               switch (c1){
                 case '>': entity = "&gt;"; break;
                 case '<': entity = "&lt;"; break;
                 case '\"': entity = "&quot;"; break;
                 case '&': entity = "&amp;"; break;
               }
               if (entity){
                   while (*entity) (*o_zconv)(0, *entity++);
                   return;
               }
           }
       } 
    }
    (*o_zconv)(c2,c1);
}


#define rot13(c)  ( \
      ( c < 'A' ) ? c: \
      (c <= 'M')  ? (c + 13): \
      (c <= 'Z')  ? (c - 13): \
      (c < 'a')   ? (c): \
      (c <= 'm')  ? (c + 13): \
      (c <= 'z')  ? (c - 13): \
      (c) \
)

#define  rot47(c) ( \
      ( c < '!' ) ? c: \
      ( c <= 'O' ) ? (c + 47) : \
      ( c <= '~' ) ?  (c - 47) : \
      c \
)

void rot_conv(nkf_char c2, nkf_char c1)
{
    if (c2==0 || c2==X0201 || c2==ISO8859_1) {
	c1 = rot13(c1);
    } else if (c2) {
	c1 = rot47(c1);
	c2 = rot47(c2);
    }
    (*o_rot_conv)(c2,c1);
}

void hira_conv(nkf_char c2, nkf_char c1)
{
    if (hira_f & 1) {
        if (c2 == 0x25) {
            if (0x20 < c1 && c1 < 0x74) {
                c2 = 0x24;
                (*o_hira_conv)(c2,c1);
                return;
            } else if (c1 == 0x74 && (output_conv == w_oconv || output_conv == w_oconv16)) {
                c2 = 0;
                c1 = CLASS_UNICODE | 0x3094;
                (*o_hira_conv)(c2,c1);
                return;
            }
        } else if (c2 == 0x21 && (c1 == 0x33 || c1 == 0x34)) {
            c1 += 2;
            (*o_hira_conv)(c2,c1);
            return;
        }
    }
    if (hira_f & 2) {
        if (c2 == 0 && c1 == (CLASS_UNICODE | 0x3094)) {
            c2 = 0x25;
            c1 = 0x74;
        } else if (c2 == 0x24 && 0x20 < c1 && c1 < 0x74) {
            c2 = 0x25;
        } else if (c2 == 0x21 && (c1 == 0x35 || c1 == 0x36)) {
            c1 -= 2;
        }
    }
    (*o_hira_conv)(c2,c1);
}


void iso2022jp_check_conv(nkf_char c2, nkf_char c1)
{
    static const nkf_char range[RANGE_NUM_MAX][2] = {
        {0x222f, 0x2239,},
        {0x2242, 0x2249,},
        {0x2251, 0x225b,},
        {0x226b, 0x2271,},
        {0x227a, 0x227d,},
        {0x2321, 0x232f,},
        {0x233a, 0x2340,},
        {0x235b, 0x2360,},
        {0x237b, 0x237e,},
        {0x2474, 0x247e,},
        {0x2577, 0x257e,},
        {0x2639, 0x2640,},
        {0x2659, 0x267e,},
        {0x2742, 0x2750,},
        {0x2772, 0x277e,},
        {0x2841, 0x287e,},
        {0x4f54, 0x4f7e,},
        {0x7425, 0x747e},
    };
    nkf_char i;
    nkf_char start, end, c;

    if(c2 >= 0x00 && c2 <= 0x20 && c1 >= 0x7f && c1 <= 0xff) {
	c2 = GETA1;
	c1 = GETA2;
    }
    if((c2 >= 0x29 && c2 <= 0x2f) || (c2 >= 0x75 && c2 <= 0x7e)) {
	c2 = GETA1;
	c1 = GETA2;
    }

    for (i = 0; i < RANGE_NUM_MAX; i++) {
	start = range[i][0];
	end   = range[i][1];
	c     = (c2 << 8) + c1;
	if (c >= start && c <= end) {
	    c2 = GETA1;
	    c1 = GETA2;
	}
    }
    (*o_iso2022jp_check_conv)(c2,c1);
}


/* This converts  =?ISO-2022-JP?B?HOGE HOGE?= */

const unsigned char *mime_pattern[] = {
    (const unsigned char *)"\075?EUC-JP?B?",
    (const unsigned char *)"\075?SHIFT_JIS?B?",
    (const unsigned char *)"\075?ISO-8859-1?Q?",
    (const unsigned char *)"\075?ISO-8859-1?B?",
    (const unsigned char *)"\075?ISO-2022-JP?B?",
    (const unsigned char *)"\075?ISO-2022-JP?Q?",
#if defined(UTF8_INPUT_ENABLE)
    (const unsigned char *)"\075?UTF-8?B?",
    (const unsigned char *)"\075?UTF-8?Q?",
#endif
    (const unsigned char *)"\075?US-ASCII?Q?",
    NULL
};


/* 該当するコードの優先度を上げるための目印 */
nkf_char (*mime_priority_func[])(nkf_char c2, nkf_char c1, nkf_char c0) = {
    e_iconv, s_iconv, 0, 0, 0, 0,
#if defined(UTF8_INPUT_ENABLE)
    w_iconv, w_iconv,
#endif
    0,
};

const nkf_char mime_encode[] = {
    JAPANESE_EUC, SHIFT_JIS,ISO8859_1, ISO8859_1, X0208, X0201,
#if defined(UTF8_INPUT_ENABLE)
    UTF8, UTF8,
#endif
    ASCII,
    0
};

const nkf_char mime_encode_method[] = {
    'B', 'B','Q', 'B', 'B', 'Q',
#if defined(UTF8_INPUT_ENABLE)
    'B', 'Q',
#endif
    'Q',
    0
};


#define MAXRECOVER 20

void switch_mime_getc(void)
{
    if (i_getc!=mime_getc) {
	i_mgetc = i_getc; i_getc = mime_getc;
	i_mungetc = i_ungetc; i_ungetc = mime_ungetc;
	if(mime_f==STRICT_MIME) {
	    i_mgetc_buf = i_mgetc; i_mgetc = mime_getc_buf;
	    i_mungetc_buf = i_mungetc; i_mungetc = mime_ungetc_buf;
	}
    }
}

void unswitch_mime_getc(void)
{
    if(mime_f==STRICT_MIME) {
	i_mgetc = i_mgetc_buf;
	i_mungetc = i_mungetc_buf;
    }
    i_getc = i_mgetc;
    i_ungetc = i_mungetc;
    if(mime_iconv_back)set_iconv(FALSE, mime_iconv_back);
    mime_iconv_back = NULL;
}

nkf_char mime_begin_strict(FILE *f)
{
    nkf_char c1 = 0;
    int i,j,k;
    const unsigned char *p,*q;
    nkf_char r[MAXRECOVER];    /* recovery buffer, max mime pattern length */

    mime_decode_mode = FALSE;
    /* =? has been checked */
    j = 0;
    p = mime_pattern[j];
    r[0]='='; r[1]='?';

    for(i=2;p[i]>' ';i++) {                   /* start at =? */
        if ( ((r[i] = c1 = (*i_getc)(f))==EOF) || nkf_toupper(c1) != p[i] ) {
            /* pattern fails, try next one */
            q = p;
            while (mime_pattern[++j]) {
		p = mime_pattern[j];
                for(k=2;k<i;k++)              /* assume length(p) > i */
                    if (p[k]!=q[k]) break;
                if (k==i && nkf_toupper(c1)==p[k]) break;
            }
	    p = mime_pattern[j];
            if (p) continue;  /* found next one, continue */
            /* all fails, output from recovery buffer */
            (*i_ungetc)(c1,f);
            for(j=0;j<i;j++) {
                (*oconv)(0,r[j]);
            }
            return c1;
        }
    }
    mime_decode_mode = p[i-2];

    mime_iconv_back = iconv;
    set_iconv(FALSE, mime_priority_func[j]);
    clr_code_score(find_inputcode_byfunc(mime_priority_func[j]), SCORE_iMIME);

    if (mime_decode_mode=='B') {
        mimebuf_f = unbuf_f;
        if (!unbuf_f) {
            /* do MIME integrity check */
            return mime_integrity(f,mime_pattern[j]);
        } 
    }
    switch_mime_getc();
    mimebuf_f = TRUE;
    return c1;
}

nkf_char mime_getc_buf(FILE *f)
{
    /* we don't keep eof of Fifo, becase it contains ?= as
       a terminator. It was checked in mime_integrity. */
    return ((mimebuf_f)?
        (*i_mgetc_buf)(f):Fifo(mime_input++));
}

nkf_char mime_ungetc_buf(nkf_char c, FILE *f)
{
    if (mimebuf_f)
	(*i_mungetc_buf)(c,f);
    else 
	Fifo(--mime_input) = (unsigned char)c;
    return c;
}

nkf_char mime_begin(FILE *f)
{
    nkf_char c1;
    int i,k;

    /* In NONSTRICT mode, only =? is checked. In case of failure, we  */
    /* re-read and convert again from mime_buffer.  */

    /* =? has been checked */
    k = mime_last;
    Fifo(mime_last++)='='; Fifo(mime_last++)='?';
    for(i=2;i<MAXRECOVER;i++) {                   /* start at =? */
        /* We accept any character type even if it is breaked by new lines */
        c1 = (*i_getc)(f); Fifo(mime_last++) = (unsigned char)c1;
        if (c1=='\n'||c1==' '||c1=='\r'||
                c1=='-'||c1=='_'||is_alnum(c1) ) continue;
        if (c1=='=') {
            /* Failed. But this could be another MIME preemble */
            (*i_ungetc)(c1,f);
            mime_last--;
            break;
        }
        if (c1!='?') break;
        else {
            /* c1=='?' */
            c1 = (*i_getc)(f); Fifo(mime_last++) = (unsigned char)c1;
            if (!(++i<MAXRECOVER) || c1==EOF) break;
            if (c1=='b'||c1=='B') {
                mime_decode_mode = 'B';
            } else if (c1=='q'||c1=='Q') {
                mime_decode_mode = 'Q';
            } else {
                break;
            }
            c1 = (*i_getc)(f); Fifo(mime_last++) = (unsigned char)c1;
            if (!(++i<MAXRECOVER) || c1==EOF) break;
            if (c1!='?') {
                mime_decode_mode = FALSE;
            }
            break;
        }
    }
    switch_mime_getc();
    if (!mime_decode_mode) {
        /* false MIME premble, restart from mime_buffer */
        mime_decode_mode = 1;  /* no decode, but read from the mime_buffer */
        /* Since we are in MIME mode until buffer becomes empty,    */
        /* we never go into mime_begin again for a while.           */
        return c1;
    }
    /* discard mime preemble, and goto MIME mode */
    mime_last = k;
    /* do no MIME integrity check */
    return c1;   /* used only for checking EOF */
}

#ifdef CHECK_OPTION
void no_putc(nkf_char c)
{
    ;
}

void debug(const char *str)
{
    if (debug_f){
        fprintf(stderr, "%s\n", str);
    }
}
#endif

void set_input_codename(char *codename)
{
    if (guess_f && 
        is_inputcode_set &&
        strcmp(codename, "") != 0 && 
        strcmp(codename, input_codename) != 0)
    {
        is_inputcode_mixed = TRUE;
    }
    input_codename = codename;
    is_inputcode_set = TRUE;
}

#if !defined(PERL_XS) && !defined(WIN32DLL)
void print_guessed_code(char *filename)
{
    char *codename = "BINARY";
    if (!is_inputcode_mixed) {
        if (strcmp(input_codename, "") == 0) {
            codename = "ASCII";
        } else {
            codename = input_codename;
        }
    }
    if (filename != NULL) printf("%s:", filename);
    printf("%s\n", codename);
}
#endif /*WIN32DLL*/

#ifdef INPUT_OPTION 

nkf_char hex_getc(nkf_char ch, FILE *f, nkf_char (*g)(FILE *f), nkf_char (*u)(nkf_char c, FILE *f))
{
    nkf_char c1, c2, c3;
    c1 = (*g)(f);
    if (c1 != ch){
        return c1;
    }
    c2 = (*g)(f);
    if (!nkf_isxdigit(c2)){
        (*u)(c2, f);
        return c1;
    }
    c3 = (*g)(f);
    if (!nkf_isxdigit(c3)){
        (*u)(c2, f);
        (*u)(c3, f);
        return c1;
    }
    return (hex2bin(c2) << 4) | hex2bin(c3);
}

nkf_char cap_getc(FILE *f)
{
    return hex_getc(':', f, i_cgetc, i_cungetc);
}

nkf_char cap_ungetc(nkf_char c, FILE *f)
{
    return (*i_cungetc)(c, f);
}

nkf_char url_getc(FILE *f)
{
    return hex_getc('%', f, i_ugetc, i_uungetc);
}

nkf_char url_ungetc(nkf_char c, FILE *f)
{
    return (*i_uungetc)(c, f);
}
#endif

#ifdef NUMCHAR_OPTION
nkf_char numchar_getc(FILE *f)
{
    nkf_char (*g)(FILE *) = i_ngetc;
    nkf_char (*u)(nkf_char c ,FILE *f) = i_nungetc;
    int i = 0, j;
    nkf_char buf[10];
    long c = -1;

    buf[i] = (*g)(f);
    if (buf[i] == '&'){
        buf[++i] = (*g)(f);
        if (buf[i] == '#'){
            c = 0;
            buf[++i] = (*g)(f);
            if (buf[i] == 'x' || buf[i] == 'X'){
                for (j = 0; j < 7; j++){
                    buf[++i] = (*g)(f);
                    if (!nkf_isxdigit(buf[i])){
                        if (buf[i] != ';'){
                            c = -1;
                        }
                        break;
                    }
                    c <<= 4;
                    c |= hex2bin(buf[i]);
                }
            }else{
                for (j = 0; j < 8; j++){
                    if (j){
                        buf[++i] = (*g)(f);
                    }
                    if (!nkf_isdigit(buf[i])){
                        if (buf[i] != ';'){
                            c = -1;
                        }
                        break;
                    }
                    c *= 10;
                    c += hex2bin(buf[i]);
                }
            }
        }
    }
    if (c != -1){
        return CLASS_UNICODE | c;
    }
    while (i > 0){
        (*u)(buf[i], f);
        --i;
    }
    return buf[0];
}

nkf_char numchar_ungetc(nkf_char c, FILE *f)
{
    return (*i_nungetc)(c, f);
}
#endif

#ifdef UNICODE_NORMALIZATION

/* Normalization Form C */
nkf_char nfc_getc(FILE *f)
{
    nkf_char (*g)(FILE *f) = i_nfc_getc;
    nkf_char (*u)(nkf_char c ,FILE *f) = i_nfc_ungetc;
    int i=0, j, k=1, lower, upper;
    nkf_char buf[9];
    const nkf_nfchar *array;
#if 0
    extern const struct normalization_pair normalization_table[];
#endif
    
    buf[i] = (*g)(f);
    while (k > 0 && ((buf[i] & 0xc0) != 0x80)){
	lower=0, upper=NORMALIZATION_TABLE_LENGTH-1;
	while (upper >= lower) {
	    j = (lower+upper) / 2;
	    array = normalization_table[j].nfd;
	    for (k=0; k < NORMALIZATION_TABLE_NFD_LENGTH && array[k]; k++){
		if (array[k] != buf[k]){
		    array[k] < buf[k] ? (lower = j + 1) : (upper = j - 1);
		    k = 0;
		    break;
		} else if (k >= i)
		    buf[++i] = (*g)(f);
	    }
	    if (k > 0){
		array = normalization_table[j].nfc;
		for (i=0; i < NORMALIZATION_TABLE_NFC_LENGTH && array[i]; i++)
		    buf[i] = (nkf_char)(array[i]);
		i--;
		break;
	    }
	}
	while (i > 0)
	    (*u)(buf[i--], f);
    }
    return buf[0];
}

nkf_char nfc_ungetc(nkf_char c, FILE *f)
{
    return (*i_nfc_ungetc)(c, f);
}
#endif /* UNICODE_NORMALIZATION */


nkf_char 
mime_getc(FILE *f)
{
    nkf_char c1, c2, c3, c4, cc;
    nkf_char t1, t2, t3, t4, mode, exit_mode;
    nkf_char lwsp_count;
    char *lwsp_buf;
    char *lwsp_buf_new;
    nkf_char lwsp_size = 128;

    if (mime_top != mime_last) {  /* Something is in FIFO */
        return  Fifo(mime_top++);
    }
    if (mime_decode_mode==1 ||mime_decode_mode==FALSE) {
	mime_decode_mode=FALSE;
	unswitch_mime_getc();
	return (*i_getc)(f);
    }

    if (mimebuf_f == FIXED_MIME)
        exit_mode = mime_decode_mode;
    else
        exit_mode = FALSE;
    if (mime_decode_mode == 'Q') {
        if ((c1 = (*i_mgetc)(f)) == EOF) return (EOF);
restart_mime_q:
        if (c1=='_' && mimebuf_f != FIXED_MIME) return ' ';
	if (c1<=' ' || DEL<=c1) {
	    mime_decode_mode = exit_mode; /* prepare for quit */
	    return c1;
	}
        if (c1!='=' && (c1!='?' || mimebuf_f == FIXED_MIME)) {
	    return c1;
	}
                
        mime_decode_mode = exit_mode; /* prepare for quit */
        if ((c2 = (*i_mgetc)(f)) == EOF) return (EOF);
        if (c1=='?'&&c2=='=' && mimebuf_f != FIXED_MIME) {
            /* end Q encoding */
            input_mode = exit_mode;
	    lwsp_count = 0;
	    lwsp_buf = malloc((lwsp_size+5)*sizeof(char));
	    if (lwsp_buf==NULL) {
		perror("can't malloc");
		return -1;
	    }
	    while ((c1=(*i_getc)(f))!=EOF) {
		switch (c1) {
		case NL:
		case CR:
		    if (c1==NL) {
			if ((c1=(*i_getc)(f))!=EOF && (c1==SPACE||c1==TAB)) {
			    i_ungetc(SPACE,f);
			    continue;
			} else {
			    i_ungetc(c1,f);
			}
			c1 = NL;
		    } else {
			if ((c1=(*i_getc)(f))!=EOF && c1 == NL) {
			    if ((c1=(*i_getc)(f))!=EOF && (c1==SPACE||c1==TAB)) {
				i_ungetc(SPACE,f);
				continue;
			    } else {
				i_ungetc(c1,f);
			    }
			    i_ungetc(NL,f);
			} else {
			    i_ungetc(c1,f);
			}
			c1 = CR;
		    }
		    break;
		case SPACE:
		case TAB:
		    lwsp_buf[lwsp_count] = (unsigned char)c1;
		    if (lwsp_count++>lwsp_size){
			lwsp_size <<= 1;
			lwsp_buf_new = realloc(lwsp_buf, (lwsp_size+5)*sizeof(char));
			if (lwsp_buf_new==NULL) {
			    free(lwsp_buf);
			    perror("can't realloc");
			    return -1;
			}
			lwsp_buf = lwsp_buf_new;
		    }
		    continue;
		}
		break;
	    }
	    if (lwsp_count > 0 && (c1 != '=' || (lwsp_buf[lwsp_count-1] != SPACE && lwsp_buf[lwsp_count-1] != TAB))) {
		i_ungetc(c1,f);
		for(lwsp_count--;lwsp_count>0;lwsp_count--)
		    i_ungetc(lwsp_buf[lwsp_count],f);
		c1 = lwsp_buf[0];
	    }
	    free(lwsp_buf);
            return c1;
        }
        if (c1=='='&&c2<' ') { /* this is soft wrap */
            while((c1 =  (*i_mgetc)(f)) <=' ') {
		if ((c1 = (*i_mgetc)(f)) == EOF) return (EOF);
	    }
            mime_decode_mode = 'Q'; /* still in MIME */
	    goto restart_mime_q;
	}
        if (c1=='?') {
            mime_decode_mode = 'Q'; /* still in MIME */
            (*i_mungetc)(c2,f);
            return c1;
        }
        if ((c3 = (*i_mgetc)(f)) == EOF) return (EOF);
        if (c2<=' ') return c2;
        mime_decode_mode = 'Q'; /* still in MIME */
        return ((hex2bin(c2)<<4) + hex2bin(c3));
    }

    if (mime_decode_mode != 'B') {
        mime_decode_mode = FALSE;
        return (*i_mgetc)(f);
    }


    /* Base64 encoding */
    /* 
        MIME allows line break in the middle of 
        Base64, but we are very pessimistic in decoding
        in unbuf mode because MIME encoded code may broken by 
        less or editor's control sequence (such as ESC-[-K in unbuffered
        mode. ignore incomplete MIME.
    */
    mode = mime_decode_mode;
    mime_decode_mode = exit_mode;  /* prepare for quit */

    while ((c1 = (*i_mgetc)(f))<=' ') {
        if (c1==EOF)
            return (EOF);
    }
mime_c2_retry:
    if ((c2 = (*i_mgetc)(f))<=' ') {
        if (c2==EOF)
            return (EOF);
	if (mime_f != STRICT_MIME) goto mime_c2_retry;
        if (mimebuf_f!=FIXED_MIME) input_mode = ASCII;  
        return c2;
    }
    if ((c1 == '?') && (c2 == '=')) {
        input_mode = ASCII;
	lwsp_count = 0;
	lwsp_buf = malloc((lwsp_size+5)*sizeof(char));
	if (lwsp_buf==NULL) {
	    perror("can't malloc");
	    return -1;
	}
	while ((c1=(*i_getc)(f))!=EOF) {
	    switch (c1) {
	    case NL:
	    case CR:
		if (c1==NL) {
		    if ((c1=(*i_getc)(f))!=EOF && (c1==SPACE||c1==TAB)) {
			i_ungetc(SPACE,f);
			continue;
		    } else {
			i_ungetc(c1,f);
		    }
		    c1 = NL;
		} else {
		    if ((c1=(*i_getc)(f))!=EOF) {
			if (c1==SPACE) {
			    i_ungetc(SPACE,f);
			    continue;
			} else if ((c1=(*i_getc)(f))!=EOF && (c1==SPACE||c1==TAB)) {
			    i_ungetc(SPACE,f);
			    continue;
			} else {
			    i_ungetc(c1,f);
			}
			i_ungetc(NL,f);
		    } else {
			i_ungetc(c1,f);
		    }
		    c1 = CR;
		}
		break;
	    case SPACE:
	    case TAB:
		lwsp_buf[lwsp_count] = (unsigned char)c1;
		if (lwsp_count++>lwsp_size){
		    lwsp_size <<= 1;
		    lwsp_buf_new = realloc(lwsp_buf, (lwsp_size+5)*sizeof(char));
		    if (lwsp_buf_new==NULL) {
			free(lwsp_buf);
			perror("can't realloc");
			return -1;
		    }
		    lwsp_buf = lwsp_buf_new;
		}
		continue;
	    }
	    break;
	}
	if (lwsp_count > 0 && (c1 != '=' || (lwsp_buf[lwsp_count-1] != SPACE && lwsp_buf[lwsp_count-1] != TAB))) {
	    i_ungetc(c1,f);
	    for(lwsp_count--;lwsp_count>0;lwsp_count--)
		i_ungetc(lwsp_buf[lwsp_count],f);
	    c1 = lwsp_buf[0];
	}
	free(lwsp_buf);
        return c1;
    }
mime_c3_retry:
    if ((c3 = (*i_mgetc)(f))<=' ') {
        if (c3==EOF)
            return (EOF);
	if (mime_f != STRICT_MIME) goto mime_c3_retry;
        if (mimebuf_f!=FIXED_MIME) input_mode = ASCII;  
        return c3;
    }
mime_c4_retry:
    if ((c4 = (*i_mgetc)(f))<=' ') {
        if (c4==EOF)
            return (EOF);
	if (mime_f != STRICT_MIME) goto mime_c4_retry;
        if (mimebuf_f!=FIXED_MIME) input_mode = ASCII;  
        return c4;
    }

    mime_decode_mode = mode; /* still in MIME sigh... */

    /* BASE 64 decoding */

    t1 = 0x3f & base64decode(c1);
    t2 = 0x3f & base64decode(c2);
    t3 = 0x3f & base64decode(c3);
    t4 = 0x3f & base64decode(c4);
    cc = ((t1 << 2) & 0x0fc) | ((t2 >> 4) & 0x03);
    if (c2 != '=') {
        Fifo(mime_last++) = (unsigned char)cc;
        cc = ((t2 << 4) & 0x0f0) | ((t3 >> 2) & 0x0f);
        if (c3 != '=') {
            Fifo(mime_last++) = (unsigned char)cc;
            cc = ((t3 << 6) & 0x0c0) | (t4 & 0x3f);
            if (c4 != '=') 
                Fifo(mime_last++) = (unsigned char)cc;
        }
    } else {
        return c1;
    }
    return  Fifo(mime_top++);
}

nkf_char mime_ungetc(nkf_char c, FILE *f)
{
    Fifo(--mime_top) = (unsigned char)c;
    return c;
}

nkf_char mime_integrity(FILE *f, const unsigned char *p)
{
    nkf_char c,d;
    unsigned int q;
    /* In buffered mode, read until =? or NL or buffer full
     */
    mime_input = mime_top;
    mime_last = mime_top;
    
    while(*p) Fifo(mime_input++) = *p++;
    d = 0;
    q = mime_input;
    while((c=(*i_getc)(f))!=EOF) {
        if (((mime_input-mime_top)&MIME_BUF_MASK)==0) {
	    break;   /* buffer full */
	}
        if (c=='=' && d=='?') {
            /* checked. skip header, start decode */
            Fifo(mime_input++) = (unsigned char)c;
            /* mime_last_input = mime_input; */
            mime_input = q; 
	    switch_mime_getc();
            return 1;
        }
        if (!( (c=='+'||c=='/'|| c=='=' || c=='?' || is_alnum(c))))
            break;
        /* Should we check length mod 4? */
        Fifo(mime_input++) = (unsigned char)c;
        d=c;
    }
    /* In case of Incomplete MIME, no MIME decode  */
    Fifo(mime_input++) = (unsigned char)c;
    mime_last = mime_input;     /* point undecoded buffer */
    mime_decode_mode = 1;              /* no decode on Fifo last in mime_getc */
    switch_mime_getc();         /* anyway we need buffered getc */
    return 1;
}

nkf_char base64decode(nkf_char c)
{
    int             i;
    if (c > '@') {
        if (c < '[') {
            i = c - 'A';                        /* A..Z 0-25 */
        } else {
            i = c - 'G'     /* - 'a' + 26 */ ;  /* a..z 26-51 */
	}
    } else if (c > '/') {
        i = c - '0' + '4'   /* - '0' + 52 */ ;  /* 0..9 52-61 */
    } else if (c == '+') {
        i = '>'             /* 62 */ ;          /* +  62 */
    } else {
        i = '?'             /* 63 */ ;          /* / 63 */
    }
    return (i);
}

static const char basis_64[] =
   "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static nkf_char b64c;
#define MIMEOUT_BUF_LENGTH (60)
char mimeout_buf[MIMEOUT_BUF_LENGTH+1];
int mimeout_buf_count = 0;
int mimeout_preserve_space = 0;
#define itoh4(c)   (c>=10?c+'A'-10:c+'0')

void open_mime(nkf_char mode)
{
    const unsigned char *p;
    int i;
    int j;
    p  = mime_pattern[0];
    for(i=0;mime_encode[i];i++) {
	if (mode == mime_encode[i]) {
	    p = mime_pattern[i];
	    break;
	}
    }
    mimeout_mode = mime_encode_method[i];
    
    i = 0;
    if (base64_count>45) {
	if (mimeout_buf_count>0 && nkf_isblank(mimeout_buf[i])){
            (*o_mputc)(mimeout_buf[i]);
	    i++;
	}
	(*o_mputc)(NL);
	(*o_mputc)(SPACE);
	base64_count = 1;
	if (!mimeout_preserve_space && mimeout_buf_count>0
	    && (mimeout_buf[i]==SPACE || mimeout_buf[i]==TAB
	    	|| mimeout_buf[i]==CR || mimeout_buf[i]==NL )) {
	    i++;
	}
    }
    if (!mimeout_preserve_space) {
	for (;i<mimeout_buf_count;i++) {
	    if (mimeout_buf[i]==SPACE || mimeout_buf[i]==TAB
		|| mimeout_buf[i]==CR || mimeout_buf[i]==NL ) {
		(*o_mputc)(mimeout_buf[i]);
		base64_count ++;
	    } else {
		break;
	    }
	}
    }
    mimeout_preserve_space = FALSE;
    
    while(*p) {
        (*o_mputc)(*p++);
        base64_count ++;
    }
    j = mimeout_buf_count;
    mimeout_buf_count = 0;
    for (;i<j;i++) {
	mime_putc(mimeout_buf[i]);
    }
}

void close_mime(void)
{
    (*o_mputc)('?');
    (*o_mputc)('=');
    base64_count += 2;
    mimeout_mode = 0;
}

void eof_mime(void)
{
    switch(mimeout_mode) {
    case 'Q':
    case 'B':
	break;
    case 2:
	(*o_mputc)(basis_64[((b64c & 0x3)<< 4)]);
	(*o_mputc)('=');
	(*o_mputc)('=');
	base64_count += 3;
	break;
    case 1:
	(*o_mputc)(basis_64[((b64c & 0xF) << 2)]);
	(*o_mputc)('=');
	base64_count += 2;
	break;
    }
    if (mimeout_mode) {
	if (mimeout_f!=FIXED_MIME) {
	    close_mime(); 
	} else if (mimeout_mode != 'Q')
	    mimeout_mode = 'B';
    }
}

void mimeout_addchar(nkf_char c)
{
    switch(mimeout_mode) {
    case 'Q':
	if (c==CR||c==NL) {
	    (*o_mputc)(c);
	    base64_count = 0;
	} else if(!nkf_isalnum(c)) {
	    (*o_mputc)('=');
	    (*o_mputc)(itoh4(((c>>4)&0xf)));
	    (*o_mputc)(itoh4((c&0xf)));
	    base64_count += 3;
	} else {
	    (*o_mputc)(c);
	    base64_count++;
	}
        break;
    case 'B':
        b64c=c;
        (*o_mputc)(basis_64[c>>2]);
        mimeout_mode=2;
        base64_count ++;
        break;
    case 2:
        (*o_mputc)(basis_64[((b64c & 0x3)<< 4) | ((c & 0xF0) >> 4)]);
        b64c=c;
        mimeout_mode=1;
        base64_count ++;
        break;
    case 1:
        (*o_mputc)(basis_64[((b64c & 0xF) << 2) | ((c & 0xC0) >>6)]);
        (*o_mputc)(basis_64[c & 0x3F]);
        mimeout_mode='B';
        base64_count += 2;
        break;
    default:
	(*o_mputc)(c);
	base64_count++;
        break;
    }
}

nkf_char mime_lastchar2, mime_lastchar1;

void mime_prechar(nkf_char c2, nkf_char c1)
{
    if (mimeout_mode){
        if (c2){
            if (base64_count + mimeout_buf_count/3*4> 66){
                (*o_base64conv)(EOF,0);
                (*o_base64conv)(0,NL);
                (*o_base64conv)(0,SPACE);
            }
        }/*else if (mime_lastchar2){
            if (c1 <=DEL && !nkf_isspace(c1)){
                (*o_base64conv)(0,SPACE);
            }
        }*/
    }/*else{
        if (c2 && mime_lastchar2 == 0
            && mime_lastchar1 && !nkf_isspace(mime_lastchar1)){
            (*o_base64conv)(0,SPACE);
        }
    }*/
    mime_lastchar2 = c2;
    mime_lastchar1 = c1;
}

void mime_putc(nkf_char c)
{
    int i, j;
    nkf_char lastchar;

    if (mimeout_f == FIXED_MIME){
        if (mimeout_mode == 'Q'){
            if (base64_count > 71){
                if (c!=CR && c!=NL) {
                    (*o_mputc)('=');
                    (*o_mputc)(NL);
                }
                base64_count = 0;
            }
        }else{
            if (base64_count > 71){
                eof_mime();
                (*o_mputc)(NL);
                base64_count = 0;
            }
            if (c == EOF) { /* c==EOF */
                eof_mime();
            }
        }
        if (c != EOF) { /* c==EOF */
            mimeout_addchar(c);
        }
        return;
    }
    
    /* mimeout_f != FIXED_MIME */

    if (c == EOF) { /* c==EOF */
	j = mimeout_buf_count;
	mimeout_buf_count = 0;
	i = 0;
	if (mimeout_mode) {
	    for (;i<j;i++) {
		if (nkf_isspace(mimeout_buf[i]) && base64_count < 71){
		    break;
		}
		mimeout_addchar(mimeout_buf[i]);
	    }
	    eof_mime();
	    for (;i<j;i++) {
		mimeout_addchar(mimeout_buf[i]);
	    }
	} else {
	    for (;i<j;i++) {
		mimeout_addchar(mimeout_buf[i]);
	    }
	}
        return;
    }

    if (mimeout_mode=='Q') {
        if (c <= DEL && (output_mode==ASCII ||output_mode == ISO8859_1 ) ) {
            if (c <= SPACE) {
                close_mime();
                (*o_mputc)(SPACE);
                base64_count++;
            }
            (*o_mputc)(c);
            base64_count++;
        }
        return;
    }

    if (mimeout_buf_count > 0){
        lastchar = mimeout_buf[mimeout_buf_count - 1];
    }else{
        lastchar = -1;
    }

    if (!mimeout_mode) {
        if (c <= DEL && (output_mode==ASCII ||output_mode == ISO8859_1)) {
            if (nkf_isspace(c)) {
                if (c==CR || c==NL) {
                    base64_count=0;
                }
                for (i=0;i<mimeout_buf_count;i++) {
                    (*o_mputc)(mimeout_buf[i]);
                    if (mimeout_buf[i] == CR || mimeout_buf[i] == NL){
                        base64_count = 0;
                    }else{
                        base64_count++;
                    }
                }
                mimeout_buf[0] = (char)c;
                mimeout_buf_count = 1;
            }else{
                if (base64_count > 1
                    && base64_count + mimeout_buf_count > 76){
                    (*o_mputc)(NL);
                    base64_count = 0;
                    if (!nkf_isspace(mimeout_buf[0])){
                        (*o_mputc)(SPACE);
                        base64_count++;
                    }
                }
                mimeout_buf[mimeout_buf_count++] = (char)c;
                if (mimeout_buf_count>MIMEOUT_BUF_LENGTH) {
                    open_mime(output_mode);
                }
            }
            return;
        }else{
            if (lastchar==CR || lastchar == NL){
                for (i=0;i<mimeout_buf_count;i++) {
                    (*o_mputc)(mimeout_buf[i]);
                }
                base64_count = 0;
                mimeout_buf_count = 0;
            }
            if (lastchar==SPACE) {
                for (i=0;i<mimeout_buf_count-1;i++) {
                    (*o_mputc)(mimeout_buf[i]);
                    base64_count++;
                }
                mimeout_buf[0] = SPACE;
                mimeout_buf_count = 1;
            }
            open_mime(output_mode);
        }
    }else{
        /* mimeout_mode == 'B', 1, 2 */
        if ( c<=DEL && (output_mode==ASCII ||output_mode == ISO8859_1 ) ) {
            if (lastchar == CR || lastchar == NL){
                if (nkf_isblank(c)) {
                    for (i=0;i<mimeout_buf_count;i++) {
                        mimeout_addchar(mimeout_buf[i]);
                    }
                    mimeout_buf_count = 0;
                } else if (SPACE<c && c<DEL) {
                    eof_mime();
                    for (i=0;i<mimeout_buf_count;i++) {
                        (*o_mputc)(mimeout_buf[i]);
                    }
                    base64_count = 0;
                    mimeout_buf_count = 0;
                }
            }
            if (c==SPACE || c==TAB || c==CR || c==NL) {
                for (i=0;i<mimeout_buf_count;i++) {
                    if (SPACE<mimeout_buf[i] && mimeout_buf[i]<DEL) {
                        eof_mime();
                        for (i=0;i<mimeout_buf_count;i++) {
                            (*o_mputc)(mimeout_buf[i]);
                            base64_count++;
                        }
                        mimeout_buf_count = 0;
                    }
                }
                mimeout_buf[mimeout_buf_count++] = (char)c;
                if (mimeout_buf_count>MIMEOUT_BUF_LENGTH) {
                    eof_mime();
                    for (i=0;i<mimeout_buf_count;i++) {
                        (*o_mputc)(mimeout_buf[i]);
                        base64_count++;
                    }
                    mimeout_buf_count = 0;
                }
                return;
            }
            if (mimeout_buf_count>0 && SPACE<c && c!='=') {
                mimeout_buf[mimeout_buf_count++] = (char)c;
                if (mimeout_buf_count>MIMEOUT_BUF_LENGTH) {
                    j = mimeout_buf_count;
                    mimeout_buf_count = 0;
                    for (i=0;i<j;i++) {
                        mimeout_addchar(mimeout_buf[i]);
                    }
                }
                return;
            }
        }
    }
    if (mimeout_buf_count>0) {
	j = mimeout_buf_count;
	mimeout_buf_count = 0;
	for (i=0;i<j;i++) {
	    if (mimeout_buf[i]==CR || mimeout_buf[i]==NL)
		break;
	    mimeout_addchar(mimeout_buf[i]);
	}
	if (i<j) {
	    eof_mime();
	    base64_count=0;
	    for (;i<j;i++) {
		(*o_mputc)(mimeout_buf[i]);
	    }
	    open_mime(output_mode);
	}
    }
    mimeout_addchar(c);
}


#if defined(PERL_XS) || defined(WIN32DLL)
void reinit(void)
{
    {
        struct input_code *p = input_code_list;
        while (p->name){
            status_reinit(p++);
        }
    }
    unbuf_f = FALSE;
    estab_f = FALSE;
    nop_f = FALSE;
    binmode_f = TRUE;
    rot_f = FALSE;
    hira_f = FALSE;
    input_f = FALSE;
    alpha_f = FALSE;
    mime_f = STRICT_MIME;
    mime_decode_f = FALSE;
    mimebuf_f = FALSE;
    broken_f = FALSE;
    iso8859_f = FALSE;
    mimeout_f = FALSE;
#if defined(MSDOS) || defined(__OS2__)
     x0201_f = TRUE;
#else
     x0201_f = NO_X0201;
#endif
    iso2022jp_f = FALSE;
#if defined(UTF8_INPUT_ENABLE) || defined(UTF8_OUTPUT_ENABLE)
    ms_ucs_map_f = UCS_MAP_ASCII;
#endif
#ifdef UTF8_INPUT_ENABLE
    no_cp932ext_f = FALSE;
    no_best_fit_chars_f = FALSE;
    encode_fallback = NULL;
    unicode_subchar  = '?';
    input_endian = ENDIAN_BIG;
#endif
#ifdef UTF8_OUTPUT_ENABLE
    output_bom_f = FALSE;
    output_endian = ENDIAN_BIG;
#endif
#ifdef UNICODE_NORMALIZATION
    nfc_f = FALSE;
#endif
#ifdef INPUT_OPTION
    cap_f = FALSE;
    url_f = FALSE;
    numchar_f = FALSE;
#endif
#ifdef CHECK_OPTION
    noout_f = FALSE;
    debug_f = FALSE;
#endif
    guess_f = FALSE;
    is_inputcode_mixed = FALSE;
    is_inputcode_set   = FALSE;
#ifdef EXEC_IO
    exec_f = 0;
#endif
#ifdef SHIFTJIS_CP932
    cp51932_f = TRUE;
    cp932inv_f = TRUE;
#endif
#ifdef X0212_ENABLE
    x0212_f = FALSE;
    x0213_f = FALSE;
#endif
    {
        int i;
        for (i = 0; i < 256; i++){
            prefix_table[i] = 0;
        }
    }
    hold_count = 0;
    mimeout_buf_count = 0;
    mimeout_mode = 0;
    base64_count = 0;
    f_line = 0;
    f_prev = 0;
    fold_preserve_f = FALSE;
    fold_f = FALSE;
    fold_len = 0;
    kanji_intro = DEFAULT_J;
    ascii_intro = DEFAULT_R;
    fold_margin  = FOLD_MARGIN;
    output_conv = DEFAULT_CONV;
    oconv = DEFAULT_CONV;
    o_zconv = no_connection;
    o_fconv = no_connection;
    o_crconv = no_connection;
    o_rot_conv = no_connection;
    o_hira_conv = no_connection;
    o_base64conv = no_connection;
    o_iso2022jp_check_conv = no_connection;
    o_putc = std_putc;
    i_getc = std_getc;
    i_ungetc = std_ungetc;
    i_bgetc = std_getc;
    i_bungetc = std_ungetc;
    o_mputc = std_putc;
    i_mgetc = std_getc;
    i_mungetc  = std_ungetc;
    i_mgetc_buf = std_getc;
    i_mungetc_buf = std_ungetc;
    output_mode = ASCII;
    input_mode =  ASCII;
    shift_mode =  FALSE;
    mime_decode_mode = FALSE;
    file_out_f = FALSE;
    crmode_f = 0;
    option_mode = 0;
    broken_counter = 0;
    broken_last = 0;
    z_prev2=0,z_prev1=0;
#ifdef CHECK_OPTION
    iconv_for_check = 0;
#endif
    input_codename = "";
#ifdef WIN32DLL
    reinitdll();
#endif /*WIN32DLL*/
}
#endif

void no_connection(nkf_char c2, nkf_char c1)
{
    no_connection2(c2,c1,0);
}

nkf_char no_connection2(nkf_char c2, nkf_char c1, nkf_char c0)
{
    fprintf(stderr,"nkf internal module connection failure.\n");
    exit(1);
    return 0; /* LINT */
}

#ifndef PERL_XS
#ifdef WIN32DLL
#define fprintf dllprintf
#endif
void usage(void)
{
    fprintf(stderr,"USAGE:  nkf(nkf32,wnkf,nkf2) -[flags] [in file] .. [out file for -O flag]\n");
    fprintf(stderr,"Flags:\n");
    fprintf(stderr,"b,u      Output is buffered (DEFAULT),Output is unbuffered\n");
#ifdef DEFAULT_CODE_SJIS
    fprintf(stderr,"j,s,e,w  Output code is JIS 7 bit, Shift_JIS (DEFAULT), EUC-JP, UTF-8N\n");
#endif
#ifdef DEFAULT_CODE_JIS
    fprintf(stderr,"j,s,e,w  Output code is JIS 7 bit (DEFAULT), Shift JIS, EUC-JP, UTF-8N\n");
#endif
#ifdef DEFAULT_CODE_EUC
    fprintf(stderr,"j,s,e,w  Output code is JIS 7 bit, Shift JIS, EUC-JP (DEFAULT), UTF-8N\n");
#endif
#ifdef DEFAULT_CODE_UTF8
    fprintf(stderr,"j,s,e,w  Output code is JIS 7 bit, Shift JIS, EUC-JP, UTF-8N (DEFAULT)\n");
#endif
#ifdef UTF8_OUTPUT_ENABLE
    fprintf(stderr,"         After 'w' you can add more options. -w[ 8 [0], 16 [[BL] [0]] ]\n");
#endif
    fprintf(stderr,"J,S,E,W  Input assumption is JIS 7 bit , Shift JIS, EUC-JP, UTF-8\n");
#ifdef UTF8_INPUT_ENABLE
    fprintf(stderr,"         After 'W' you can add more options. -W[ 8, 16 [BL] ] \n");
#endif
    fprintf(stderr,"t        no conversion\n");
    fprintf(stderr,"i[@B]    Specify the Esc Seq for JIS X 0208-1978/83 (DEFAULT B)\n");
    fprintf(stderr,"o[BJH]   Specify the Esc Seq for ASCII/Roman        (DEFAULT B)\n");
    fprintf(stderr,"r        {de/en}crypt ROT13/47\n");
    fprintf(stderr,"h        1 katakana->hiragana, 2 hiragana->katakana, 3 both\n");
    fprintf(stderr,"v        Show this usage. V: show version\n");
    fprintf(stderr,"m[BQN0]  MIME decode [B:base64,Q:quoted,N:non-strict,0:no decode]\n");
    fprintf(stderr,"M[BQ]    MIME encode [B:base64 Q:quoted]\n");
    fprintf(stderr,"l        ISO8859-1 (Latin-1) support\n");
    fprintf(stderr,"f/F      Folding: -f60 or -f or -f60-10 (fold margin 10) F preserve nl\n");
    fprintf(stderr,"Z[0-3]   Convert X0208 alphabet to ASCII\n");
    fprintf(stderr,"         1: Kankaku to 1 space  2: to 2 spaces  3: Convert to HTML Entity\n");
    fprintf(stderr,"X,x      Assume X0201 kana in MS-Kanji, -x preserves X0201\n");
    fprintf(stderr,"B[0-2]   Broken input  0: missing ESC,1: any X on ESC-[($]-X,2: ASCII on NL\n");
#ifdef MSDOS
    fprintf(stderr,"T        Text mode output\n");
#endif
    fprintf(stderr,"O        Output to File (DEFAULT 'nkf.out')\n");
    fprintf(stderr,"I        Convert non ISO-2022-JP charactor to GETA\n");
    fprintf(stderr,"d,c      Convert line breaks  -d: LF  -c: CRLF\n");
    fprintf(stderr,"-L[uwm]  line mode u:LF w:CRLF m:CR (DEFAULT noconversion)\n");
    fprintf(stderr,"\n");
    fprintf(stderr,"Long name options\n");
    fprintf(stderr," --ic=<input codeset>  --oc=<output codeset>\n");
    fprintf(stderr,"                   Specify the input or output codeset\n");
    fprintf(stderr," --fj  --unix --mac  --windows\n");
    fprintf(stderr," --jis  --euc  --sjis  --utf8  --utf16  --mime  --base64\n");
    fprintf(stderr,"                   Convert for the system or code\n");
    fprintf(stderr," --hiragana  --katakana  --katakana-hiragana\n");
    fprintf(stderr,"                   To Hiragana/Katakana Conversion\n");
    fprintf(stderr," --prefix=         Insert escape before troublesome characters of Shift_JIS\n");
#ifdef INPUT_OPTION
    fprintf(stderr," --cap-input, --url-input  Convert hex after ':' or '%%'\n");
#endif
#ifdef NUMCHAR_OPTION
    fprintf(stderr," --numchar-input   Convert Unicode Character Reference\n");
#endif
#ifdef UTF8_INPUT_ENABLE
    fprintf(stderr," --fb-{skip, html, xml, perl, java, subchar}\n");
    fprintf(stderr,"                   Specify how nkf handles unassigned characters\n");
#endif
#ifdef OVERWRITE
    fprintf(stderr," --in-place[=SUFFIX]  --overwrite[=SUFFIX]\n");
    fprintf(stderr,"                   Overwrite original listed files by filtered result\n");
    fprintf(stderr,"                   --overwrite preserves timestamp of original files\n");
#endif
    fprintf(stderr," -g  --guess       Guess the input code\n");
    fprintf(stderr," --help  --version Show this help/the version\n");
    fprintf(stderr,"                   For more information, see also man nkf\n");
    fprintf(stderr,"\n");
    version();
}

void version(void)
{
    fprintf(stderr,"Network Kanji Filter Version %s (%s) "
#if defined(MSDOS) && !defined(__WIN32__) && !defined(__WIN16__) && !defined(__OS2__)
                  "for DOS"
#endif
#if defined(MSDOS) && defined(__WIN16__)
                  "for Win16"
#endif
#if defined(MSDOS) && defined(__WIN32__)
                  "for Win32"
#endif
#ifdef __OS2__
                  "for OS/2"
#endif
                  ,NKF_VERSION,NKF_RELEASE_DATE);
    fprintf(stderr,"\n%s\n",CopyRight);
}
#endif /*PERL_XS*/

/**
 ** パッチ制作者
 **  void@merope.pleiades.or.jp (Kusakabe Youichi)
 **  NIDE Naoyuki <nide@ics.nara-wu.ac.jp>
 **  ohta@src.ricoh.co.jp (Junn Ohta)
 **  inouet@strl.nhk.or.jp (Tomoyuki Inoue)
 **  kiri@pulser.win.or.jp (Tetsuaki Kiriyama)
 **  Kimihiko Sato <sato@sail.t.u-tokyo.ac.jp>
 **  a_kuroe@kuroe.aoba.yokohama.jp (Akihiko Kuroe)
 **  kono@ie.u-ryukyu.ac.jp (Shinji Kono)
 **  GHG00637@nifty-serve.or.jp (COW)
 **
 **/

/* end */
