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
#include "config.h"

static char *CopyRight =
      "Copyright (C) 1987, FUJITSU LTD. (I.Ichikawa),2000 S. Kono, COW, 2002-2004 Kono, Furukawa";
static char *Version =
      "2.0";
static char *Patchlevel =
      "4/0410/Shinji Kono";

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
** j    Outout code is JIS 7 bit        (DEFAULT SELECT) 
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

#if (defined(__TURBOC__) || defined(_MSC_VER) || defined(LSI_C) || defined(__MINGW32__)) && !defined(MSDOS)
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

#if defined(MSDOS) || defined(__OS2__) 
#include <fcntl.h>
#include <io.h>
#endif

#ifdef MSDOS
#ifdef LSI_C
#define setbinmode(fp) fsetbin(fp)
#else /* Microsoft C, Turbo C */
#define setbinmode(fp) setmode(fileno(fp), O_BINARY)
#endif
#else /* UNIX,OS/2 */
#define setbinmode(fp)
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
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#ifndef MSDOS /* UNIX, OS/2 */
#include <unistd.h>
#include <utime.h>
#else
#if defined(_MSC_VER) || defined(__MINGW32__) /* VC++, MinGW */
#include <sys/utime.h>
#elif defined(__TURBOC__) /* BCC */
#include <utime.h>
#elif defined(LSI_C) /* LSI C */
#endif
#endif
#endif 

#ifdef INT_IS_SHORT
#define int long
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

/* Input Assumption */

#define         JIS_INPUT       4
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
#define		UTF16LE_INPUT  14
#define		UTF16BE_INPUT  15

#define         WISH_TRUE      15

/* ASCII CODE */

#define         BS      0x08
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

#define		is_alnum(c)  \
            (('a'<=c && c<='z')||('A'<= c && c<='Z')||('0'<=c && c<='9'))

#define         HOLD_SIZE       1024
#define         IOBUF_SIZE      16384

#define         DEFAULT_J       'B'
#define         DEFAULT_R       'B'

#define         SJ0162  0x00e1          /* 01 - 62 ku offset */
#define         SJ6394  0x0161          /* 63 - 94 ku offset */

#define         RANGE_NUM_MAX   18
#define         GETA1   0x22
#define         GETA2   0x2e


#if defined( UTF8_OUTPUT_ENABLE ) || defined( UTF8_INPUT_ENABLE )
#define sizeof_euc_utf8 94
#define sizeof_euc_to_utf8_1byte 94
#define sizeof_euc_to_utf8_2bytes 94
#define sizeof_utf8_to_euc_C2 64
#define sizeof_utf8_to_euc_E5B8 64
#define sizeof_utf8_to_euc_2bytes 112
#define sizeof_utf8_to_euc_3bytes 112
#endif

/* MIME preprocessor */


#ifdef EASYWIN /*Easy Win */
extern POINT _BufferSize;
#endif

/*      function prototype  */

#ifdef ANSI_C_PROTOTYPE
#define PROTO(x)  x 
#define STATIC static
#else
#define PROTO(x)  ()
#define STATIC
#endif

struct input_code{
    char *name;
    int stat;
    int score;
    int index;
    int buf[3];
    void (*status_func)PROTO((struct input_code *, int));
    int (*iconv_func)PROTO((int c2, int c1, int c0));
    int _file_stat;
};

STATIC char *input_codename = "";

STATIC  int     noconvert PROTO((FILE *f));
STATIC  int     kanji_convert PROTO((FILE *f));
STATIC  int     h_conv PROTO((FILE *f,int c2,int c1));
STATIC  int     push_hold_buf PROTO((int c2));
STATIC  void    set_iconv PROTO((int f, int (*iconv_func)()));
STATIC  int     s_iconv PROTO((int c2,int c1,int c0));
STATIC  int     s2e_conv PROTO((int c2, int c1, int *p2, int *p1));
STATIC  int     e_iconv PROTO((int c2,int c1,int c0));
#ifdef UTF8_INPUT_ENABLE
STATIC  int     w2e_conv PROTO((int c2,int c1,int c0,int *p2,int *p1));
STATIC  int     w_iconv PROTO((int c2,int c1,int c0));
STATIC  int     w_iconv16 PROTO((int c2,int c1,int c0));
STATIC  int	w_iconv_common PROTO((int c1,int c0,unsigned short **pp,int psize,int *p2,int *p1));
STATIC  int     ww16_conv PROTO((int c2, int c1, int c0));
#endif
#ifdef UTF8_OUTPUT_ENABLE
STATIC  int     e2w_conv PROTO((int c2,int c1));
STATIC  void    w_oconv PROTO((int c2,int c1));
STATIC  void    w_oconv16 PROTO((int c2,int c1));
#endif
STATIC  void    e_oconv PROTO((int c2,int c1));
STATIC  void    e2s_conv PROTO((int c2, int c1, int *p2, int *p1));
STATIC  void    s_oconv PROTO((int c2,int c1));
STATIC  void    j_oconv PROTO((int c2,int c1));
STATIC  void    fold_conv PROTO((int c2,int c1));
STATIC  void    cr_conv PROTO((int c2,int c1));
STATIC  void    z_conv PROTO((int c2,int c1));
STATIC  void    rot_conv PROTO((int c2,int c1));
STATIC  void    hira_conv PROTO((int c2,int c1));
STATIC  void    base64_conv PROTO((int c2,int c1));
STATIC  void    iso2022jp_check_conv PROTO((int c2,int c1));
STATIC  void    no_connection PROTO((int c2,int c1));
STATIC  int     no_connection2 PROTO((int c2,int c1,int c0));

STATIC  void    code_score PROTO((struct input_code *ptr));
STATIC  void    code_status PROTO((int c));

STATIC  void    std_putc PROTO((int c));
STATIC  int     std_getc PROTO((FILE *f));
STATIC  int     std_ungetc PROTO((int c,FILE *f));

STATIC  int     broken_getc PROTO((FILE *f));
STATIC  int     broken_ungetc PROTO((int c,FILE *f));

STATIC  int     mime_begin PROTO((FILE *f));
STATIC  int     mime_getc PROTO((FILE *f));
STATIC  int     mime_ungetc PROTO((int c,FILE *f));

STATIC  int     mime_begin_strict PROTO((FILE *f));
STATIC  int     mime_getc_buf PROTO((FILE *f));
STATIC  int     mime_ungetc_buf  PROTO((int c,FILE *f));
STATIC  int     mime_integrity PROTO((FILE *f,unsigned char *p));

STATIC  int     base64decode PROTO((int c));
STATIC  void    mime_putc PROTO((int c));
STATIC  void    open_mime PROTO((int c));
STATIC  void    close_mime PROTO(());
STATIC  void    usage PROTO(());
STATIC  void    version PROTO(());
STATIC  void    options PROTO((unsigned char *c));
#ifdef PERL_XS
STATIC  void    reinit PROTO(());
#endif

/* buffers */

static unsigned char   stdibuf[IOBUF_SIZE];
static unsigned char   stdobuf[IOBUF_SIZE];
static unsigned char   hold_buf[HOLD_SIZE*2];
static int             hold_count;

/* MIME preprocessor fifo */

#define MIME_BUF_SIZE   (1024)    /* 2^n ring buffer */
#define MIME_BUF_MASK   (MIME_BUF_SIZE-1)   
#define Fifo(n)         mime_buf[(n)&MIME_BUF_MASK]
static unsigned char           mime_buf[MIME_BUF_SIZE];
static unsigned int            mime_top = 0;
static unsigned int            mime_last = 0;  /* decoded */
static unsigned int            mime_input = 0; /* undecoded */

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
#ifdef UTF8_OUTPUT_ENABLE
static int             unicode_bom_f= 0;   /* Output Unicode BOM */
static int             w_oconv16_LE = 0;   /* utf-16 little endian */
static int             ms_ucs_map_f = FALSE;   /* Microsoft UCS Mapping Compatible */
#endif


#ifdef NUMCHAR_OPTION

#define CLASS_MASK  0x0f000000
#define CLASS_UTF16 0x01000000
#endif

#ifdef INPUT_OPTION
static int cap_f = FALSE;
static int (*i_cgetc)PROTO((FILE *)) = std_getc; /* input of cgetc */
static int (*i_cungetc)PROTO((int c ,FILE *f)) = std_ungetc;
STATIC int cap_getc PROTO((FILE *f));
STATIC int cap_ungetc PROTO((int c,FILE *f));

static int url_f = FALSE;
static int (*i_ugetc)PROTO((FILE *)) = std_getc; /* input of ugetc */
static int (*i_uungetc)PROTO((int c ,FILE *f)) = std_ungetc;
STATIC int url_getc PROTO((FILE *f));
STATIC int url_ungetc PROTO((int c,FILE *f));

static int numchar_f = FALSE;
static int (*i_ngetc)PROTO((FILE *)) = std_getc; /* input of ugetc */
static int (*i_nungetc)PROTO((int c ,FILE *f)) = std_ungetc;
STATIC int numchar_getc PROTO((FILE *f));
STATIC int numchar_ungetc PROTO((int c,FILE *f));
#endif

#ifdef CHECK_OPTION
static int noout_f = FALSE;
STATIC void no_putc PROTO((int c));
static int debug_f = FALSE;
STATIC void debug PROTO((char *str));
#endif

static int guess_f = FALSE;
STATIC  void    print_guessed_code PROTO((char *filename));
STATIC  void    set_input_codename PROTO((char *codename));
static int is_inputcode_mixed = FALSE;
static int is_inputcode_set   = FALSE;

#ifdef EXEC_IO
static int exec_f = 0;
#endif

#ifdef SHIFTJIS_CP932
STATIC int cp932_f = TRUE;
#define CP932_TABLE_BEGIN (0xfa)
#define CP932_TABLE_END   (0xfc)

STATIC int cp932inv_f = FALSE;
#define CP932INV_TABLE_BEGIN (0xed)
#define CP932INV_TABLE_END   (0xee)

#endif /* SHIFTJIS_CP932 */

STATIC unsigned char prefix_table[256];

STATIC void e_status PROTO((struct input_code *, int));
STATIC void s_status PROTO((struct input_code *, int));

#ifdef UTF8_INPUT_ENABLE
STATIC void w_status PROTO((struct input_code *, int));
STATIC void w16_status PROTO((struct input_code *, int));
static int             utf16_mode = UTF16LE_INPUT;
#endif

struct input_code input_code_list[] = {
    {"EUC-JP",    0, 0, 0, {0, 0, 0}, e_status, e_iconv, 0},
    {"Shift_JIS", 0, 0, 0, {0, 0, 0}, s_status, s_iconv, 0},
    {"UTF-8",     0, 0, 0, {0, 0, 0}, w_status, w_iconv, 0},
    {"UTF-16",    0, 0, 0, {0, 0, 0}, w16_status, w_iconv16, 0},
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
static unsigned char   kanji_intro = DEFAULT_J,
                       ascii_intro = DEFAULT_R;

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
static void (*output_conv)PROTO((int c2,int c1)) = DEFAULT_CONV;   

static void (*oconv)PROTO((int c2,int c1)) = no_connection; 
/* s_iconv or oconv */
static int (*iconv)PROTO((int c2,int c1,int c0)) = no_connection2;   

static void (*o_zconv)PROTO((int c2,int c1)) = no_connection; 
static void (*o_fconv)PROTO((int c2,int c1)) = no_connection; 
static void (*o_crconv)PROTO((int c2,int c1)) = no_connection; 
static void (*o_rot_conv)PROTO((int c2,int c1)) = no_connection; 
static void (*o_hira_conv)PROTO((int c2,int c1)) = no_connection; 
static void (*o_base64conv)PROTO((int c2,int c1)) = no_connection;
static void (*o_iso2022jp_check_conv)PROTO((int c2,int c1)) = no_connection;

/* static redirections */

static  void   (*o_putc)PROTO((int c)) = std_putc;

static  int    (*i_getc)PROTO((FILE *f)) = std_getc; /* general input */
static  int    (*i_ungetc)PROTO((int c,FILE *f)) =std_ungetc;

static  int    (*i_bgetc)PROTO((FILE *)) = std_getc; /* input of mgetc */
static  int    (*i_bungetc)PROTO((int c ,FILE *f)) = std_ungetc;

static  void   (*o_mputc)PROTO((int c)) = std_putc ; /* output of mputc */

static  int    (*i_mgetc)PROTO((FILE *)) = std_getc; /* input of mgetc */
static  int    (*i_mungetc)PROTO((int c ,FILE *f)) = std_ungetc;

/* for strict mime */
static  int    (*i_mgetc_buf)PROTO((FILE *)) = std_getc; /* input of mgetc_buf */
static  int    (*i_mungetc_buf)PROTO((int c,FILE *f)) = std_ungetc;

/* Global states */
static int output_mode = ASCII,    /* output kanji mode */
           input_mode =  ASCII,    /* input kanji mode */
           shift_mode =  FALSE;    /* TRUE shift out, or X0201  */
static int mime_decode_mode =   FALSE;    /* MIME mode B base64, Q hex */

/* X0201 / X0208 conversion tables */

/* X0201 kana conversion table */
/* 90-9F A0-DF */
static
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
static
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
static
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
static
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

static int             file_out = FALSE;
#ifdef OVERWRITE
static int             overwrite = FALSE;
#endif

static int             crmode_f = 0;   /* CR, NL, CRLF */
#ifdef EASYWIN /*Easy Win */
static int             end_check;
#endif /*Easy Win */

#ifndef PERL_XS
int
main(argc, argv)
    int             argc;
    char          **argv;
{
    FILE  *fin;
    unsigned char  *cp;

    char *outfname;
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
#ifdef __OS2__
    if (freopen("","wb",stdout) == NULL) 
        return (-1);
#else
    setbinmode(stdout);
#endif

    if (unbuf_f)
      setbuf(stdout, (char *) NULL);
    else
      setvbuffer(stdout, stdobuf, IOBUF_SIZE);

    if (argc == 0) {
      if (binmode_f == TRUE)
#ifdef __OS2__
      if (freopen("","rb",stdin) == NULL) return (-1);
#else
      setbinmode(stdin);
#endif
      setvbuffer(stdin, stdibuf, IOBUF_SIZE);
      if (nop_f)
          noconvert(stdin);
      else {
          kanji_convert(stdin);
          if (guess_f) print_guessed_code(NULL);
      }
    } else {
      int nfiles = argc;
      while (argc--) {
          if ((fin = fopen((origfname = *argv++), "r")) == NULL) {
              perror(*--argv);
              return(-1);
          } else {
#ifdef OVERWRITE
              int fd;
              int fd_backup;
#endif

/* reopen file for stdout */
              if (file_out == TRUE) {
#ifdef OVERWRITE
                  if (overwrite){
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
                      fd = open(outfname, O_WRONLY | O_CREAT | O_TRUNC,
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
#ifdef __OS2__
                      if (freopen("","wb",stdout) == NULL) 
                           return (-1);
#else
                      setbinmode(stdout);
#endif
                  }
              }
              if (binmode_f == TRUE)
#ifdef __OS2__
                 if (freopen("","rb",fin) == NULL) 
                    return (-1);
#else
                 setbinmode(fin);
#endif 
              setvbuffer(fin, stdibuf, IOBUF_SIZE);
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
              if (overwrite) {
                  struct stat     sb;
#if defined(MSDOS) && !defined(__MINGW32__)
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
#if defined(MSDOS) && !defined(__MINGW32__)
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
#ifdef MSDOS
                  if (unlink(origfname)){
                      perror(origfname);
                  }
#endif
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
    }
#ifdef EASYWIN /*Easy Win */
    if (file_out == FALSE) 
        scanf("%d",&end_check);
    else 
        fclose(stdout);
#else /* for Other OS */
    if (file_out == TRUE) 
        fclose(stdout);
#endif 
    return (0);
}
#endif

static 
struct {
    char *name;
    char *alias;
} long_option[] = {
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
#ifdef UTF8_OUTPUT_ENABLE
    {"utf8", "w"},
    {"utf16", "w16"},
    {"ms-ucs-map", ""},
#endif
#ifdef UTF8_INPUT_ENABLE
    {"utf8-input", "W"},
    {"utf16-input", "W16"},
#endif
#ifdef OVERWRITE
    {"overwrite", ""},
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
    {"no-cp932", ""},
    {"cp932inv", ""},
#endif
#ifdef EXEC_IO
    {"exec-in", ""},
    {"exec-out", ""},
#endif
    {"prefix=", ""},
};

static int option_mode;

void
options(cp) 
     unsigned char *cp;
{
    int i;
    unsigned char *p;

    if (option_mode==1)
	return;
    if (*cp++ != '-') 
	return;
    while (*cp) {
        switch (*cp++) {
        case '-':  /* literal options */
	    if (!*cp) {        /* ignore the rest of arguments */
		option_mode = 1;
		return;
	    }
            for (i=0;i<sizeof(long_option)/sizeof(long_option[0]);i++) {
		int j;
                p = (unsigned char *)long_option[i].name;
                for (j=0;*p && (*p != '=') && *p == cp[j];p++, j++);
		if (*p == cp[j]){
		  p = &cp[j];
		  break;
		}
		p = 0;
            }
	    if (p == 0) return;
            cp = (unsigned char *)long_option[i].alias;
            if (!*cp){
#ifdef OVERWRITE
                if (strcmp(long_option[i].name, "overwrite") == 0){
                    file_out = TRUE;
                    overwrite = TRUE;
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
#ifdef SHIFTJIS_CP932
                if (strcmp(long_option[i].name, "no-cp932") == 0){
                    cp932_f = FALSE;
                    continue;
                }
                if (strcmp(long_option[i].name, "cp932inv") == 0){
                    cp932inv_f = TRUE;
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
#ifdef UTF8_OUTPUT_ENABLE
                if (strcmp(long_option[i].name, "ms-ucs-map") == 0){
                    ms_ucs_map_f = TRUE;
                    continue;
                }
#endif
                if (strcmp(long_option[i].name, "prefix=") == 0){
                    if (*p == '=' && ' ' < p[1] && p[1] < 128){
                        for (i = 2; ' ' < p[i] && p[i] < 128; i++){
                            prefix_table[p[i]] = p[1];
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
            nop_f = TRUE;
            continue;
        case 'j':           /* JIS output */
        case 'n':
            output_conv = j_oconv;
            continue;
        case 'e':           /* AT&T EUC output */
            output_conv = e_oconv;
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
                bit:1   hira -> kata
                bit:2   kata -> hira
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
            if ('1'== cp[0] && '6'==cp[1]) {
		output_conv = w_oconv16; cp+=2;
		if (cp[0]=='L') {
		    unicode_bom_f=2; cp++;
		    w_oconv16_LE = 1;
                    if (cp[0] == '0'){
                        unicode_bom_f=1; cp++;
                    }
		} else if (cp[0] == 'B') {
		    unicode_bom_f=2; cp++;
                    if (cp[0] == '0'){
                        unicode_bom_f=1; cp++;
                    }
                } 
	    } else if (cp[0] == '8') {
		output_conv = w_oconv; cp++;
		unicode_bom_f=2;
		if (cp[0] == '0'){
		    unicode_bom_f=1; cp++;
		}
	    } else
                output_conv = w_oconv;
            continue;
#endif
#ifdef UTF8_INPUT_ENABLE
        case 'W':           /* UTF-8 input */
            if ('1'== cp[0] && '6'==cp[1]) {
		input_f = UTF16LE_INPUT;
		if (cp[0]=='L') {
		    cp++;
		} else if (cp[0] == 'B') {
		    cp++;
		    input_f = UTF16BE_INPUT;
		}
	    } else if (cp[0] == '8') {
		cp++;
		input_f = UTF8_INPUT;
	    } else
                input_f = UTF8_INPUT;
            continue;
#endif
        /* Input code assumption */
        case 'J':   /* JIS input */
        case 'E':   /* AT&T EUC input */
            input_f = JIS_INPUT;
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
            if (*cp=='B'||*cp=='Q') {
                mime_decode_mode = *cp++;
                mimebuf_f = FIXED_MIME;
            } else if (*cp=='N') {
                mime_f = TRUE; cp++;
            } else if (*cp=='S') {
                mime_f = STRICT_MIME; cp++;
            } else if (*cp=='0') {
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
            file_out = TRUE;
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
	    while(*cp && *cp!='-') cp++;
            if(*cp=='-') cp++;
            continue;
        default:
            /* bogus option but ignored */
            continue;
        }
    }
}

#ifdef ANSI_C_PROTOTYPE
struct input_code * find_inputcode_byfunc(int (*iconv_func)(int c2,int c1,int c0))
#else
struct input_code * find_inputcode_byfunc(iconv_func)
     int (*iconv_func)();
#endif
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

#ifdef ANSI_C_PROTOTYPE
void set_iconv(int f, int (*iconv_func)(int c2,int c1,int c0))
#else
void set_iconv(f, iconv_func)
     int f;
     int (*iconv_func)();
#endif
{
#ifdef CHECK_OPTION
    static int (*iconv_for_check)() = 0;
#endif
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

int score_table_A0[] = {
    0, 0, 0, 0,
    0, 0, 0, 0,
    0, SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND,
    SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND, SCORE_NO_EXIST,
};

int score_table_F0[] = {
    SCORE_L2, SCORE_L2, SCORE_L2, SCORE_L2,
    SCORE_L2, SCORE_DEPEND, SCORE_NO_EXIST, SCORE_NO_EXIST,
    SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND,
    SCORE_DEPEND, SCORE_NO_EXIST, SCORE_NO_EXIST, SCORE_ERROR,
};

void set_code_score(ptr, score)
     struct input_code *ptr;
     int score;
{
    if (ptr){
        ptr->score |= score;
    }
}

void clr_code_score(ptr, score)
     struct input_code *ptr;
     int score;
{
    if (ptr){
        ptr->score &= ~score;
    }
}

void code_score(ptr)
     struct input_code *ptr;
{
    int c2 = ptr->buf[0];
    int c1 = ptr->buf[1];
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

void status_disable(ptr)
struct input_code *ptr;
{
    ptr->stat = -1;
    ptr->buf[0] = -1;
    code_score(ptr);
    if (iconv == ptr->iconv_func) set_iconv(FALSE, 0);
}

void status_push_ch(ptr, c)
     struct input_code *ptr;
     int c;
{
    ptr->buf[ptr->index++] = c;
}

void status_clear(ptr)
     struct input_code *ptr;
{
    ptr->stat = 0;
    ptr->index = 0;
}

void status_reset(ptr)
     struct input_code *ptr;
{
    status_clear(ptr);
    ptr->score = SCORE_INIT;
}

void status_reinit(ptr)
     struct input_code *ptr;
{
    status_reset(ptr);
    ptr->_file_stat = 0;
}

void status_check(ptr, c)
     struct input_code *ptr;
     int c;
{
    if (c <= DEL && estab_f){
        status_reset(ptr);
    }
}

void s_status(ptr, c)
     struct input_code *ptr;
     int c;
{
    switch(ptr->stat){
      case -1:
          status_check(ptr, c);
          break;
      case 0:
          if (c <= DEL){
              break;
#ifdef NUMCHAR_OPTION
          }else if ((c & CLASS_MASK) == CLASS_UTF16){
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
          }else if (cp932_f
                    && CP932_TABLE_BEGIN <= c && c <= CP932_TABLE_END){
              ptr->stat = 2;
              status_push_ch(ptr, c);
#endif /* SHIFTJIS_CP932 */
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
#ifdef SHIFTJIS_CP932
      case 2:
          if ((0x40 <= c && c <= 0x7e) || (0x80 <= c && c <= 0xfc)){
              status_push_ch(ptr, c);
              if (s2e_conv(ptr->buf[0], ptr->buf[1], &ptr->buf[0], &ptr->buf[1]) == 0){
                  set_code_score(ptr, SCORE_CP932);
                  status_clear(ptr);
                  break;
              }
          }
          status_disable(ptr);
          break;
#endif /* SHIFTJIS_CP932 */
    }
}

void e_status(ptr, c)
     struct input_code *ptr;
     int c;
{
    switch (ptr->stat){
      case -1:
          status_check(ptr, c);
          break;
      case 0:
          if (c <= DEL){
              break;
#ifdef NUMCHAR_OPTION
          }else if ((c & CLASS_MASK) == CLASS_UTF16){
              break;
#endif
          }else if (SSO == c || (0xa1 <= c && c <= 0xfe)){
              ptr->stat = 1;
              status_push_ch(ptr, c);
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
    }
}

#ifdef UTF8_INPUT_ENABLE
void w16_status(ptr, c)
     struct input_code *ptr;
     int c;
{
    switch (ptr->stat){
      case -1:
          break;
      case 0:
          if (ptr->_file_stat == 0){
              if (c == 0xfe || c == 0xff){
                  ptr->stat = c;
                  status_push_ch(ptr, c);
                  ptr->_file_stat = 1;
              }else{
                  status_disable(ptr);
                  ptr->_file_stat = -1;
              }
          }else if (ptr->_file_stat > 0){
              ptr->stat = 1;
              status_push_ch(ptr, c);
          }else if (ptr->_file_stat < 0){
              status_disable(ptr);
          }
          break;

      case 1:
          if (c == EOF){
              status_disable(ptr);
              ptr->_file_stat = -1;
          }else{
              status_push_ch(ptr, c);
              status_clear(ptr);
          }
          break;

      case 0xfe:
      case 0xff:
          if (ptr->stat != c && (c == 0xfe || c == 0xff)){
              status_push_ch(ptr, c);
              status_clear(ptr);
          }else{
              status_disable(ptr);
              ptr->_file_stat = -1;
          }
          break;
    }
}

void w_status(ptr, c)
     struct input_code *ptr;
     int c;
{
    switch (ptr->stat){
      case -1:
          status_check(ptr, c);
          break;
      case 0:
          if (c <= DEL){
              break;
#ifdef NUMCHAR_OPTION
          }else if ((c & CLASS_MASK) == CLASS_UTF16){
              break;
#endif
          }else if (0xc0 <= c && c <= 0xdf){
              ptr->stat = 1;
              status_push_ch(ptr, c);
          }else if (0xe0 <= c && c <= 0xef){
              ptr->stat = 2;
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
    }
}
#endif

void
code_status(c)
     int c;
{
    int action_flag = 1;
    struct input_code *result = 0;
    struct input_code *p = input_code_list;
    while (p->name){
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

#ifdef PERL_XS
#define STD_GC_BUFSIZE (256)
int std_gc_buf[STD_GC_BUFSIZE];
int std_gc_ndx;
#endif

int 
std_getc(f)
FILE *f;
{
#ifdef PERL_XS
    if (std_gc_ndx){
        return std_gc_buf[--std_gc_ndx];
    }
#endif
    return getc(f);
}

int 
std_ungetc(c,f)
int c;
FILE *f;
{
#ifdef PERL_XS
    if (std_gc_ndx == STD_GC_BUFSIZE){
        return EOF;
    }
    std_gc_buf[std_gc_ndx++] = c;
    return c;
#endif
    return ungetc(c,f);
}

void 
std_putc(c)
int c;
{
    if(c!=EOF)
      putchar(c);
}

int
noconvert(f)
    FILE  *f;
{
    int    c;

    while ((c = (*i_getc)(f)) != EOF)
      (*o_putc)(c);
    return 1;
}


void
module_connection()
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
    if (mime_f && mimebuf_f==FIXED_MIME) {
	i_mgetc = i_getc; i_getc = mime_getc;
	i_mungetc = i_ungetc; i_ungetc = mime_ungetc;
    }
    if (broken_f & 1) {
	i_bgetc = i_getc; i_getc = broken_getc;
	i_bungetc = i_ungetc; i_ungetc = broken_ungetc;
    }
    if (input_f == JIS_INPUT || input_f == LATIN1_INPUT) {
        set_iconv(-TRUE, e_iconv);
    } else if (input_f == SJIS_INPUT) {
        set_iconv(-TRUE, s_iconv);
#ifdef UTF8_INPUT_ENABLE
    } else if (input_f == UTF8_INPUT) {
        set_iconv(-TRUE, w_iconv);
    } else if (input_f == UTF16LE_INPUT) {
        set_iconv(-TRUE, w_iconv16);
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
   Conversion main loop. Code detection only. 
 */

int
kanji_convert(f)
    FILE  *f;
{
    int    c1,
                    c2, c3;

    module_connection();
    c2 = 0;


    input_mode = ASCII;
    output_mode = ASCII;
    shift_mode = FALSE;

#define NEXT continue      /* no output, get next */
#define SEND ;             /* output c1 and c2, get next */
#define LAST break         /* end of loop, go closing  */

    while ((c1 = (*i_getc)(f)) != EOF) {
        code_status(c1);
        if (c2) {
            /* second byte */
            if (c2 > DEL) {
                /* in case of 8th bit is on */
                if (!estab_f) {
                    /* in case of not established yet */
                    /* It is still ambiguious */
                    if (h_conv(f, c2, c1)==EOF) 
                        LAST;
                    else 
                        c2 = 0;
                    NEXT;
                } else
                    /* in case of already established */
                    if (c1 < AT) {
                        /* ignore bogus code */
                        c2 = 0;
                        NEXT;
                    } else
                        SEND;
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
	    if (
#ifdef UTF8_INPUT_ENABLE
                iconv == w_iconv16
#else
                0
#endif
                ) {
		c2 = c1;
		c1 = (*i_getc)(f);
		SEND;
#ifdef NUMCHAR_OPTION
            } else if ((c1 & CLASS_MASK) == CLASS_UTF16){
                SEND;
#endif
	    } else if (c1 > DEL) {
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
                } else if (input_mode == X0208) {
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
            } else if (c1 == SI) {
                shift_mode = FALSE; 
                NEXT;
            } else if (c1 == SO) {
                shift_mode = TRUE; 
                NEXT;
            } else if (c1 == ESC ) {
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
                        debug(input_codename);
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
            } else if ((c1 == NL || c1 == CR) && broken_f&4) {
                input_mode = ASCII; set_iconv(FALSE, 0);
                SEND;
	    } else 
                SEND;
        }
        /* send: */
        if (input_mode == X0208) 
            (*oconv)(c2, c1);  /* this is JIS, not SJIS/EUC case */
        else if (input_mode) 
            (*oconv)(input_mode, c1);  /* other special case */
        else if ((*iconv)(c2, c1, 0) < 0){  /* can be EUC/SJIS */
            int c0 = (*i_getc)(f);
            if (c0 != EOF){
                code_status(c0);
                (*iconv)(c2, c1, c0);
            }
        }

        c2 = 0;
        continue;
        /* goto next_word */
    }

    /* epilogue */
    (*iconv)(EOF, 0, 0);
    return 1;
}

int
h_conv(f, c2, c1)
    FILE  *f;
    int    c1,
                    c2;
{
    int    wc,c3;


    /** it must NOT be in the kanji shifte sequence      */
    /** it must NOT be written in JIS7                   */
    /** and it must be after 2 byte 8bit code            */

    hold_count = 0;
    push_hold_buf(c2);
    push_hold_buf(c1);
    c2 = 0;

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
            if (p->score < result->score){
                result = p;
            }
            ++p;
        }
        set_iconv(FALSE, result->iconv_func);
    }


    /** now,
     ** 1) EOF is detected, or
     ** 2) Code is established, or
     ** 3) Buffer is FULL (but last word is pushed)
     **
     ** in 1) and 3) cases, we continue to use
     ** Kanji codes by oconv and leave estab_f unchanged.
     **/

    c3=c1;
    wc = 0;
    while (wc < hold_count){
        c2 = hold_buf[wc++];
        if (c2 <= DEL
#ifdef NUMCHAR_OPTION
            || (c2 & CLASS_MASK) == CLASS_UTF16
#endif
            ){
            (*iconv)(0, c2, 0);
            continue;
        }else if (iconv == s_iconv && 0xa1 <= c2 && c2 <= 0xdf){
            (*iconv)(X0201, c2, 0);
            continue;
        }
        if (wc < hold_count){
            c1 = hold_buf[wc++];
        }else{
            c1 = (*i_getc)(f);
            if (c1 == EOF){
                c3 = EOF;
                break;
            }
            code_status(c1);
        }
        if ((*iconv)(c2, c1, 0) < 0){
            int c0;
            if (wc < hold_count){
                c0 = hold_buf[wc++];
            }else{
                c0 = (*i_getc)(f);
                if (c0 == EOF){
                    c3 = EOF;
                    break;
                }
                code_status(c0);
            }
            (*iconv)(c2, c1, c0);
            c1 = c0;
        }
    }
    return c3;
}



int
push_hold_buf(c2)
     int             c2;
{
    if (hold_count >= HOLD_SIZE*2)
        return (EOF);
    hold_buf[hold_count++] = c2;
    return ((hold_count >= HOLD_SIZE*2) ? EOF : hold_count);
}

int s2e_conv(c2, c1, p2, p1)
     int c2, c1;
     int *p2, *p1;
{
#ifdef SHIFTJIS_CP932
    if (cp932_f && CP932_TABLE_BEGIN <= c2 && c2 <= CP932_TABLE_END){
        extern unsigned short shiftjis_cp932[3][189];
        c1 = shiftjis_cp932[c2 - CP932_TABLE_BEGIN][c1 - 0x40];
        if (c1 == 0) return 1;
        c2 = c1 >> 8;
        c1 &= 0xff;
    }
#endif /* SHIFTJIS_CP932 */
    c2 = c2 + c2 - ((c2 <= 0x9f) ? SJ0162 : SJ6394);
    if (c1 < 0x9f)
        c1 = c1 - ((c1 > DEL) ? SPACE : 0x1f);
    else {
        c1 = c1 - 0x7e;
        c2++;
    }
    if (p2) *p2 = c2;
    if (p1) *p1 = c1;
    return 0;
}

int
s_iconv(c2, c1, c0)
    int    c2,
                    c1, c0;
{
    if (c2 == X0201) {
	c1 &= 0x7f;
    } else if ((c2 == EOF) || (c2 == 0) || c2 < SPACE) {
        /* NOP */
    } else {
        int ret = s2e_conv(c2, c1, &c2, &c1);
        if (ret) return ret;
    }
    (*oconv)(c2, c1);
    return 0;
}

int
e_iconv(c2, c1, c0)
    int    c2,
                    c1, c0;
{
    if (c2 == X0201) {
	c1 &= 0x7f;
    } else if (c2 == SSO){
        c2 = X0201;
        c1 &= 0x7f;
    } else if ((c2 == EOF) || (c2 == 0) || c2 < SPACE) {
        /* NOP */
    } else {
        c1 &= 0x7f;
        c2 &= 0x7f;
    }
    (*oconv)(c2, c1);
    return 0;
}

#ifdef UTF8_INPUT_ENABLE
int
w2e_conv(c2, c1, c0, p2, p1)
    int    c2, c1, c0;
    int *p2, *p1;
{
    extern unsigned short * utf8_to_euc_2bytes[];
    extern unsigned short ** utf8_to_euc_3bytes[];
    int ret = 0;

    if (0xc0 <= c2 && c2 <= 0xef) {
        unsigned short **pp;

        if (0xe0 <= c2) {
            if (c0 == 0) return -1;
            pp = utf8_to_euc_3bytes[c2 - 0x80];
            ret = w_iconv_common(c1, c0, pp, sizeof_utf8_to_euc_C2, p2, p1);
        } else {
            ret =  w_iconv_common(c2, c1, utf8_to_euc_2bytes, sizeof_utf8_to_euc_2bytes, p2, p1);
        }
#ifdef NUMCHAR_OPTION
        if (ret){
            if (p2) *p2 = 0;
            if (p1) *p1 = CLASS_UTF16 | ww16_conv(c2, c1, c0);
            ret = 0;
        }
#endif
        return ret;
    } else if (c2 == X0201) {
        c1 &= 0x7f;
    }
    if (p2) *p2 = c2;
    if (p1) *p1 = c1;
    return ret;
}

int
w_iconv(c2, c1, c0)
    int    c2,
                    c1, c0;
{
    int ret = w2e_conv(c2, c1, c0, &c2, &c1);
    if (ret == 0){
        (*oconv)(c2, c1);
    }
    return ret;
}

void
w16w_conv(val, p2, p1, p0)
     unsigned short val;
     int *p2, *p1, *p0;
{
    if (val < 0x80){
        *p2 = val;
        *p1 = 0;
        *p0 = 0;
    }else if (val < 0x800){
	*p2 = 0xc0 | (val >> 6);
	*p1 = 0x80 | (val & 0x3f);
        *p0 = 0;
    }else{
        *p2 = 0xe0 | (val >> 12);
        *p1 = 0x80 | ((val >> 6) & 0x3f);
        *p0 = 0x80 | (val        & 0x3f);
    }
}

int
ww16_conv(c2, c1, c0)
     int c2, c1, c0;
{
    unsigned short val;
    if (c2 >= 0xe0){
        val = (c2 & 0x0f) << 12;
        val |= (c1 & 0x3f) << 6;
        val |= (c0 & 0x3f);
    }else if (c2 >= 0xc0){
        val = (c2 & 0x1f) << 6;
        val |= (c1 & 0x3f) << 6;
    }else{
        val = c2;
    }
    return val;
}

int
w16e_conv(val, p2, p1)
     unsigned short val;
     int *p2, *p1;
{
    extern unsigned short * utf8_to_euc_2bytes[];
    extern unsigned short ** utf8_to_euc_3bytes[];
    int c2, c1, c0;
    unsigned short **pp;
    int psize;
    int ret = 0;

    w16w_conv(val, &c2, &c1, &c0);
    if (c1){
        if (c0){
            pp = utf8_to_euc_3bytes[c2 - 0x80];
            psize = sizeof_utf8_to_euc_C2;
            ret =  w_iconv_common(c1, c0, pp, psize, p2, p1);
        }else{
            pp = utf8_to_euc_2bytes;
            psize = sizeof_utf8_to_euc_2bytes;
            ret =  w_iconv_common(c2, c1, pp, psize, p2, p1);
        }
#ifdef NUMCHAR_OPTION
        if (ret){
            *p2 = 0;
            *p1 = CLASS_UTF16 | val;
            ret = 0;
        }
#endif
    }
    return ret;
}

int
w_iconv16(c2, c1, c0)
    int    c2, c1,c0;
{
    int ret;

    if (c2==0376 && c1==0377){
	utf16_mode = UTF16LE_INPUT;
	return 0;    
    } else if (c2==0377 && c1==0376){
	utf16_mode = UTF16BE_INPUT;
	return 0;    
    }
    if (c2 != EOF && utf16_mode == UTF16BE_INPUT) {
	int tmp;
	tmp=c1; c1=c2; c2=tmp;
    }
    if ((c2==0 && c1 < 0x80) || c2==EOF) {
	(*oconv)(c2, c1);
	return 0;
    }
    ret = w16e_conv(((c2<<8)&0xff00) + c1, &c2, &c1);
    if (ret) return ret;
    (*oconv)(c2, c1);
    return 0;
}

int
w_iconv_common(c1, c0, pp, psize, p2, p1)
    int    c1,c0;
    unsigned short **pp;
    int psize;
    int *p2, *p1;
{
    int c2;
    unsigned short *p ;
    unsigned short val;

    if (pp == 0) return 1;

    c1 -= 0x80;
    if (c1 < 0 || psize <= c1) return 1;
    p = pp[c1];
    if (p == 0)  return 1;

    c0 -= 0x80;
    if (c0 < 0 || sizeof_utf8_to_euc_E5B8 <= c0) return 1;
    val = p[c0];
    if (val == 0) return 1;

    c2 = val >> 8;
    if (c2 == SO) c2 = X0201;
    c1 = val & 0x7f;
    if (p2) *p2 = c2;
    if (p1) *p1 = c1;
    return 0;
}

#endif

#ifdef UTF8_OUTPUT_ENABLE
int
e2w_conv(c2, c1)
    int    c2, c1;
{
    extern unsigned short euc_to_utf8_1byte[];
    extern unsigned short * euc_to_utf8_2bytes[];
    extern unsigned short * euc_to_utf8_2bytes_ms[];
    unsigned short *p;

    if (c2 == X0201) {
        p = euc_to_utf8_1byte;
    } else {
        c2 &= 0x7f;
        c2 = (c2&0x7f) - 0x21;
        if (0<=c2 && c2<sizeof_euc_to_utf8_2bytes)
            p = ms_ucs_map_f ? euc_to_utf8_2bytes_ms[c2] : euc_to_utf8_2bytes[c2];
	else
	    return 0;
    }
    if (!p) return 0;
    c1 = (c1 & 0x7f) - 0x21;
    if (0<=c1 && c1<sizeof_euc_to_utf8_1byte)
	return p[c1];
    return 0;
}

void
w_oconv(c2, c1)
    int    c2,
                    c1;
{
    int c0;
#ifdef NUMCHAR_OPTION
    if (c2 == 0 && (c1 & CLASS_MASK) == CLASS_UTF16){
        w16w_conv(c1, &c2, &c1, &c0);
        (*o_putc)(c2);
        if (c1){
            (*o_putc)(c1);
            if (c0) (*o_putc)(c0);
        }
    }
#endif
    if (c2 == EOF) {
        (*o_putc)(EOF);
        return;
    }

    if (unicode_bom_f==2) {
	(*o_putc)('\357');
	(*o_putc)('\273');
	(*o_putc)('\277');
	unicode_bom_f=1;
    }

    if (c2 == 0) { 
	output_mode = ASCII;
        (*o_putc)(c1);
    } else if (c2 == ISO8859_1) {
	output_mode = ISO8859_1;
        (*o_putc)(c1 | 0x080);
    } else {
        output_mode = UTF8;
        w16w_conv((unsigned short)e2w_conv(c2, c1), &c2, &c1, &c0);
        (*o_putc)(c2);
        if (c1){
            (*o_putc)(c1);
            if (c0) (*o_putc)(c0);
        }
    }
}

void
w_oconv16(c2, c1)
    int    c2,
                    c1;
{
    if (c2 == EOF) {
        (*o_putc)(EOF);
        return;
    }    

    if (unicode_bom_f==2) {
        if (w_oconv16_LE){
            (*o_putc)((unsigned char)'\377');
            (*o_putc)('\376');
        }else{
            (*o_putc)('\376');
            (*o_putc)((unsigned char)'\377');
        }
	unicode_bom_f=1;
    }

    if (c2 == ISO8859_1) {
        c2 = 0;
        c1 |= 0x80;
#ifdef NUMCHAR_OPTION
    } else if (c2 == 0 && (c1 & CLASS_MASK) == CLASS_UTF16) {
        c2 = (c1 >> 8) & 0xff;
        c1 &= 0xff;
#endif
    } else if (c2) {
        unsigned short val = (unsigned short)e2w_conv(c2, c1);
        c2 = (val >> 8) & 0xff;
        c1 = val & 0xff;
    }
    if (w_oconv16_LE){
        (*o_putc)(c1);
        (*o_putc)(c2);
    }else{
        (*o_putc)(c2);
        (*o_putc)(c1);
    }
}

#endif

void
e_oconv(c2, c1)
    int    c2,
                    c1;
{
#ifdef NUMCHAR_OPTION
    if (c2 == 0 && (c1 & CLASS_MASK) == CLASS_UTF16){
        w16e_conv(c1, &c2, &c1);
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
    } else {
        if ((c1<0x21 || 0x7e<c1) ||
           (c2<0x21 || 0x7e<c2)) {
            set_iconv(FALSE, 0);
            return; /* too late to rescue this char */
        }
	output_mode = JAPANESE_EUC;
        (*o_putc)(c2 | 0x080);
        (*o_putc)(c1 | 0x080);
    }
}

void
e2s_conv(c2, c1, p2, p1)
     int c2, c1, *p2, *p1;
{
    if (p2) *p2 = ((c2 - 1) >> 1) + ((c2 <= 0x5e) ? 0x71 : 0xb1);
    if (p1) *p1 = c1 + ((c2 & 1) ? ((c1 < 0x60) ? 0x1f : 0x20) : 0x7e);
}

void
s_oconv(c2, c1)
    int    c2,
                    c1;
{
#ifdef NUMCHAR_OPTION
    if (c2 == 0 && (c1 & CLASS_MASK) == CLASS_UTF16){
        w16e_conv(c1, &c2, &c1);
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
    } else {
        if ((c1<0x20 || 0x7e<c1) ||
           (c2<0x20 || 0x7e<c2)) {
            set_iconv(FALSE, 0);
            return; /* too late to rescue this char */
        }
	output_mode = SHIFT_JIS;
        e2s_conv(c2, c1, &c2, &c1);

#ifdef SHIFTJIS_CP932
        if (cp932inv_f
            && CP932INV_TABLE_BEGIN <= c2 && c2 <= CP932INV_TABLE_END){
            extern unsigned short cp932inv[2][189];
            int c = cp932inv[c2 - CP932INV_TABLE_BEGIN][c1 - 0x40];
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

void
j_oconv(c2, c1)
    int    c2,
                    c1;
{
#ifdef NUMCHAR_OPTION
    if ((c1 & CLASS_MASK) == CLASS_UTF16){
        w16e_conv(c1, &c2, &c1);
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
        if (output_mode != X0208) {
            output_mode = X0208;
            (*o_putc)(ESC);
            (*o_putc)('$');
            (*o_putc)(kanji_intro);
        }
        if (c1<0x20 || 0x7e<c1) 
            return;
        if (c2<0x20 || 0x7e<c2) 
            return;
        (*o_putc)(c2);
        (*o_putc)(c1);
    }
}

void
base64_conv(c2, c1)
    int    c2,
                    c1;
{
    if (base64_count>50 && !mimeout_mode && c2==0 && c1==SPACE) {
	(*o_putc)(NL);
    } else if (base64_count>66 && mimeout_mode) {
	(*o_base64conv)(EOF,0);
	(*o_putc)(NL);
	(*o_putc)('\t'); base64_count += 7;
    }
    (*o_base64conv)(c2,c1);
}


static int broken_buf[3];
static int broken_counter = 0;
static int broken_last = 0;
int
broken_getc(f)
FILE *f;
{
    int c,c1;

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

int
broken_ungetc(c,f)
int c;
FILE *f;
{
    if (broken_counter<2)
	broken_buf[broken_counter++]=c;
    return c;
}

static int prev_cr = 0;

void
cr_conv(c2,c1) 
int c2,c1;
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

void
fold_conv(c2,c1) 
int c2,c1;
{ 
    int prev0;
    int fold_state=0;

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
        if (f_line==0)
            fold_state =  1;
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
            if (f_line>=fold_len+fold_margin) { /* too many kinsou suspension */
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

int z_prev2=0,z_prev1=0;

void
z_conv(c2,c1)
int c2,c1;
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

void
rot_conv(c2,c1)
int c2,c1;
{
    if (c2==0 || c2==X0201 || c2==ISO8859_1) {
	c1 = rot13(c1);
    } else if (c2) {
	c1 = rot47(c1);
	c2 = rot47(c2);
    }
    (*o_rot_conv)(c2,c1);
}

void
hira_conv(c2,c1)
int c2,c1;
{
    if ((hira_f & 1) && c2==0x25 && 0x20<c1 && c1<0x74) {
	c2 = 0x24;
    } else if ((hira_f & 2) && c2==0x24 && 0x20<c1 && c1<0x74) {
	c2 = 0x25;
    } 
    (*o_hira_conv)(c2,c1);
}


void
iso2022jp_check_conv(c2,c1)
int    c2, c1;
{
    static int range[RANGE_NUM_MAX][2] = {
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
    int i;
    int start, end, c;

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

unsigned char *mime_pattern[] = {
   (unsigned char *)"\075?EUC-JP?B?",
   (unsigned char *)"\075?SHIFT_JIS?B?",
   (unsigned char *)"\075?ISO-8859-1?Q?",
   (unsigned char *)"\075?ISO-8859-1?B?",
   (unsigned char *)"\075?ISO-2022-JP?B?",
   (unsigned char *)"\075?ISO-2022-JP?Q?",
#if defined(UTF8_INPUT_ENABLE) || defined(UTF8_OUTPUT_ENABLE)
   (unsigned char *)"\075?UTF-8?B?",
   (unsigned char *)"\075?UTF-8?Q?",
#endif
   (unsigned char *)"\075?US-ASCII?Q?",
   NULL
};


/* 該当するコードの優先度を上げるための目印 */
int (*mime_priority_func[])PROTO((int c2, int c1, int c0)) = {
    e_iconv, s_iconv, 0, 0, 0, 0,
#if defined(UTF8_INPUT_ENABLE) || defined(UTF8_OUTPUT_ENABLE)
    w_iconv, w_iconv,
#endif
    0,
};

int      mime_encode[] = {
    JAPANESE_EUC, SHIFT_JIS,ISO8859_1, ISO8859_1, X0208, X0201,
#if defined(UTF8_INPUT_ENABLE) || defined(UTF8_OUTPUT_ENABLE)
    UTF8, UTF8,
#endif
    ASCII,
    0
};

int      mime_encode_method[] = {
    'B', 'B','Q', 'B', 'B', 'Q',
#if defined(UTF8_INPUT_ENABLE) || defined(UTF8_OUTPUT_ENABLE)
    'B', 'Q',
#endif
    'Q',
    0
};


#define MAXRECOVER 20

/* I don't trust portablity of toupper */
#define nkf_toupper(c)  (('a'<=c && c<='z')?(c-('a'-'A')):c)
#define nkf_isdigit(c)  ('0'<=c && c<='9')
#define nkf_isxdigit(c)  (nkf_isdigit(c) || ('a'<=c && c<='f') || ('A'<=c && c <= 'F'))

void
switch_mime_getc()
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

void
unswitch_mime_getc()
{
    if(mime_f==STRICT_MIME) {
	i_mgetc = i_mgetc_buf;
	i_mungetc = i_mungetc_buf;
    }
    i_getc = i_mgetc;
    i_ungetc = i_mungetc;
}

int
mime_begin_strict(f)
FILE *f;
{
    int c1 = 0;
    int i,j,k;
    unsigned char *p,*q;
    int r[MAXRECOVER];    /* recovery buffer, max mime pattern lenght */

    mime_decode_mode = FALSE;
    /* =? has been checked */
    j = 0;
    p = mime_pattern[j];
    r[0]='='; r[1]='?';

    for(i=2;p[i]>' ';i++) {                   /* start at =? */
        if ( ((r[i] = c1 = (*i_getc)(f))==EOF) || nkf_toupper(c1) != p[i] ) {
            /* pattern fails, try next one */
            q = p;
            while ((p = mime_pattern[++j])) {
                for(k=2;k<i;k++)              /* assume length(p) > i */
                    if (p[k]!=q[k]) break;
                if (k==i && nkf_toupper(c1)==p[k]) break;
            }
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

int
mime_getc_buf(f) 
FILE *f;
{
    /* we don't keep eof of Fifo, becase it contains ?= as
       a terminator. It was checked in mime_integrity. */
    return ((mimebuf_f)?
        (*i_mgetc_buf)(f):Fifo(mime_input++));
}

int
mime_ungetc_buf(c,f) 
FILE *f;
int c;
{
    if (mimebuf_f)
	(*i_mungetc_buf)(c,f);
    else 
	Fifo(--mime_input)=c;
    return c;
}

int
mime_begin(f)
FILE *f;
{
    int c1;
    int i,k;

    /* In NONSTRICT mode, only =? is checked. In case of failure, we  */
    /* re-read and convert again from mime_buffer.  */

    /* =? has been checked */
    k = mime_last;
    Fifo(mime_last++)='='; Fifo(mime_last++)='?';
    for(i=2;i<MAXRECOVER;i++) {                   /* start at =? */
        /* We accept any character type even if it is breaked by new lines */
        c1 = (*i_getc)(f); Fifo(mime_last++)= c1 ;
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
            c1 = (*i_getc)(f); Fifo(mime_last++) = c1;
            if (!(++i<MAXRECOVER) || c1==EOF) break;
            if (c1=='b'||c1=='B') {
                mime_decode_mode = 'B';
            } else if (c1=='q'||c1=='Q') {
                mime_decode_mode = 'Q';
            } else {
                break;
            }
            c1 = (*i_getc)(f); Fifo(mime_last++) = c1;
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
void
no_putc(c)
     int c;
{
    ;
}

void debug(str)
     char *str;
{
    if (debug_f){
        fprintf(stderr, "%s\n", str);
    }
}
#endif

void
set_input_codename (codename)
    char *codename;
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

void
print_guessed_code (filename)
    char *filename;
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

int
hex2bin(x)
     int x;
{
    if (nkf_isdigit(x)) return x - '0';
    return nkf_toupper(x) - 'A' + 10;
}

#ifdef INPUT_OPTION 

#ifdef ANSI_C_PROTOTYPE
int hex_getc(int ch, FILE *f, int (*g)(FILE *f), int (*u)(int c, FILE *f))
#else
int
hex_getc(ch, f, g, u)
     int ch;
     FILE *f;
     int (*g)();
     int (*u)();
#endif
{
    int c1, c2, c3;
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

int
cap_getc(f)
     FILE *f;
{
    return hex_getc(':', f, i_cgetc, i_cungetc);
}

int
cap_ungetc(c, f)
     int c;
     FILE *f;
{
    return (*i_cungetc)(c, f);
}

int
url_getc(f)
     FILE *f;
{
    return hex_getc('%', f, i_ugetc, i_uungetc);
}

int
url_ungetc(c, f)
     int c;
     FILE *f;
{
    return (*i_uungetc)(c, f);
}
#endif

#ifdef NUMCHAR_OPTION
int
numchar_getc(f)
     FILE *f;
{
    int (*g)() = i_ngetc;
    int (*u)() = i_nungetc;
    int i = 0, j;
    int buf[8];
    long c = -1;

    buf[i] = (*g)(f);
    if (buf[i] == '&'){
        buf[++i] = (*g)(f);
        if (buf[i] == '#'){
            c = 0;
            buf[++i] = (*g)(f);
            if (buf[i] == 'x' || buf[i] == 'X'){
                for (j = 0; j < 5; j++){
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
                for (j = 0; j < 6; j++){
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
        return CLASS_UTF16 | c;
    }
    while (i > 0){
        (*u)(buf[i], f);
        --i;
    }
    return buf[0];
}

int
numchar_ungetc(c, f)
     int c;
     FILE *f;
{
    return (*i_nungetc)(c, f);
}
#endif


int 
mime_getc(f)
FILE *f;
{
    int c1, c2, c3, c4, cc;
    int t1, t2, t3, t4, mode, exit_mode;

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
        if (c1=='_') return ' ';
        if (c1!='=' && c1!='?') {
	    return c1;
	}
                
        mime_decode_mode = exit_mode; /* prepare for quit */
        if (c1<=' ') return c1;
        if ((c2 = (*i_mgetc)(f)) == EOF) return (EOF);
        if (c1=='?'&&c2=='=' && mimebuf_f != FIXED_MIME) {
            /* end Q encoding */
            input_mode = exit_mode;
            while((c1=(*i_getc)(f))!=EOF && c1==SPACE 
                        /* && (c1==NL||c1==TAB||c1=='\r') */ ) ;
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
#define hex(c)   (('0'<=c&&c<='9')?(c-'0'):\
     ('A'<=c&&c<='F')?(c-'A'+10):('a'<=c&&c<='f')?(c-'a'+10):0)
        return ((hex(c2)<<4) + hex(c3));
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
        while((c1=(*i_getc)(f))!=EOF && c1==SPACE 
                    /* && (c1==NL||c1==TAB||c1=='\r') */ ) ;
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
        Fifo(mime_last++) = cc;
        cc = ((t2 << 4) & 0x0f0) | ((t3 >> 2) & 0x0f);
        if (c3 != '=') {
            Fifo(mime_last++) = cc;
            cc = ((t3 << 6) & 0x0c0) | (t4 & 0x3f);
            if (c4 != '=') 
                Fifo(mime_last++) = cc;
        }
    } else {
        return c1;
    }
    return  Fifo(mime_top++);
}

int
mime_ungetc(c,f) 
int   c;
FILE  *f;
{
    Fifo(--mime_top) = c;
    return c;
}

int
mime_integrity(f,p)
FILE *f;
unsigned char *p;
{
    int c,d;
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
            Fifo(mime_input++) = c;
            /* mime_last_input = mime_input; */
            mime_input = q; 
	    switch_mime_getc();
            return 1;
        }
        if (!( (c=='+'||c=='/'|| c=='=' || c=='?' || is_alnum(c))))
            break;
        /* Should we check length mod 4? */
        Fifo(mime_input++) = c;
        d=c;
    }
    /* In case of Incomplete MIME, no MIME decode  */
    Fifo(mime_input++) = c;
    mime_last = mime_input;     /* point undecoded buffer */
    mime_decode_mode = 1;              /* no decode on Fifo last in mime_getc */
    switch_mime_getc();         /* anyway we need buffered getc */
    return 1;
}

int
base64decode(c)
    int            c;
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

static char basis_64[] =
   "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static int b64c;

void
open_mime(mode)
int mode;
{
    unsigned char *p;
    int i;
    p  = mime_pattern[0];
    for(i=0;mime_encode[i];i++) {
	if (mode == mime_encode[i]) {
	    p = mime_pattern[i];
		break;
	}
    }
    mimeout_mode = mime_encode_method[i];
	    
    /* (*o_mputc)(' '); */
    while(*p) {
        (*o_mputc)(*p++);
        base64_count ++;
    }
}

void
close_mime()
{
    (*o_mputc)('?');
    (*o_mputc)('=');
    (*o_mputc)(' ');
    base64_count += 3;
    mimeout_mode = 0;
}

#define itoh4(c)   (c>=10?c+'A'-10:c+'0')

void
mime_putc(c)
    int            c;
{
    if (mimeout_f==FIXED_MIME) {
	if (base64_count>71) {
            (*o_mputc)('\n');
            base64_count=0;
        }
    } else if (c==NL) {
	base64_count=0;
    } 
    if (c!=EOF) {
        if ( c<=DEL &&(output_mode==ASCII ||output_mode == ISO8859_1 )
		&& mimeout_f!=FIXED_MIME) {
	    if (mimeout_mode=='Q') {
		if (c<=SPACE) {
		    close_mime();
		}
		(*o_mputc)(c);
		return;
	    }
            if (mimeout_mode!='B' || c!=SPACE) {
		if (mimeout_mode) {
		    mime_putc(EOF);
		    mimeout_mode=0;
		}
		(*o_mputc)(c);
		base64_count ++;
		return;
	    }
        } else if (!mimeout_mode && mimeout_f!=FIXED_MIME) {
	    open_mime(output_mode);
        }
    } else { /* c==EOF */
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
        return;
    }
    switch(mimeout_mode) {
    case 'Q':
	if(c>=DEL) {
	    (*o_mputc)('=');
	    (*o_mputc)(itoh4(((c>>4)&0xf)));
	    (*o_mputc)(itoh4((c&0xf)));
	} else {
	    (*o_mputc)(c);
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
    }
}


#ifdef PERL_XS
void 
reinit()
{
    unbuf_f = FALSE;
    estab_f = FALSE;
    nop_f = FALSE;
    binmode_f = TRUE;       
    rot_f = FALSE;         
    hira_f = FALSE;         
    input_f = FALSE;      
    alpha_f = FALSE;     
    mime_f = STRICT_MIME; 
    mimebuf_f = FALSE; 
    broken_f = FALSE;  
    iso8859_f = FALSE; 
#if defined(MSDOS) || defined(__OS2__) 
     x0201_f = TRUE;   
#else
     x0201_f = NO_X0201;
#endif
    iso2022jp_f = FALSE;

    kanji_intro = DEFAULT_J;
    ascii_intro = DEFAULT_R;

    output_conv = DEFAULT_CONV; 
    oconv = DEFAULT_CONV; 

    i_mgetc  = std_getc; 
    i_mungetc  = std_ungetc;
    i_mgetc_buf = std_getc; 
    i_mungetc_buf = std_ungetc;

    i_getc= std_getc; 
    i_ungetc=std_ungetc;

    i_bgetc= std_getc;
    i_bungetc= std_ungetc;

    o_putc = std_putc;
    o_mputc = std_putc;
    o_crconv = no_connection; 
    o_rot_conv = no_connection; 
    o_iso2022jp_check_conv = no_connection;
    o_hira_conv = no_connection; 
    o_fconv = no_connection; 
    o_zconv = no_connection;

    i_getc = std_getc;
    i_ungetc = std_ungetc;
    i_mgetc = std_getc; 
    i_mungetc = std_ungetc; 

    output_mode = ASCII;
    input_mode =  ASCII;
    shift_mode =  FALSE;
    mime_decode_mode =   FALSE;
    file_out = FALSE;
    mimeout_mode = 0;
    mimeout_f = FALSE;
    base64_count = 0;
    option_mode = 0;
    crmode_f = 0;

    {
        struct input_code *p = input_code_list;
        while (p->name){
            status_reinit(p++);
        }
    }
#ifdef UTF8_OUTPUT_ENABLE
    if (unicode_bom_f) {
	unicode_bom_f = 2;
    }
#endif
    f_line = 0;    
    f_prev = 0;
    fold_preserve_f = FALSE; 
    fold_f  = FALSE;
    fold_len  = 0;
    fold_margin  = FOLD_MARGIN;
    broken_counter = 0;
    broken_last = 0;
    z_prev2=0,z_prev1=0;

    {
        int i;
        for (i = 0; i < 256; i++){
            prefix_table[i] = 0;
        }
    }
    input_codename = "";
    is_inputcode_mixed = FALSE;
    is_inputcode_set   = FALSE;
}
#endif

void 
no_connection(c2,c1) 
int c2,c1;
{
    no_connection2(c2,c1,0);
}

int
no_connection2(c2,c1,c0) 
int c2,c1,c0;
{
    fprintf(stderr,"nkf internal module connection failure.\n");
    exit(1);
}

#ifndef PERL_XS
void 
usage()   
{
    fprintf(stderr,"USAGE:  nkf(nkf32,wnkf,nkf2) -[flags] [in file] .. [out file for -O flag]\n");
    fprintf(stderr,"Flags:\n");
    fprintf(stderr,"b,u      Output is buffered (DEFAULT),Output is unbuffered\n");
#ifdef DEFAULT_CODE_SJIS
    fprintf(stderr,"j,s,e,w  Outout code is JIS 7 bit, Shift JIS (DEFAULT), AT&T JIS (EUC), UTF-8\n");
#endif
#ifdef DEFAULT_CODE_JIS
    fprintf(stderr,"j,s,e,w  Outout code is JIS 7 bit (DEFAULT), Shift JIS, AT&T JIS (EUC), UTF-8\n");
#endif
#ifdef DEFAULT_CODE_EUC
    fprintf(stderr,"j,s,e,w  Outout code is JIS 7 bit, Shift JIS, AT&T JIS (EUC) (DEFAULT), UTF-8\n");
#endif
#ifdef DEFAULT_CODE_UTF8
    fprintf(stderr,"j,s,e,w  Outout code is JIS 7 bit, Shift JIS, AT&T JIS (EUC), UTF-8 (DEFAULT)\n");
#endif
#ifdef UTF8_OUTPUT_ENABLE
    fprintf(stderr,"         After 'w' you can add more options. (80?|16((B|L)0?)?) \n");
#endif
    fprintf(stderr,"J,S,E,W  Input assumption is JIS 7 bit , Shift JIS, AT&T JIS (EUC), UTF-8\n");
#ifdef UTF8_INPUT_ENABLE
    fprintf(stderr,"         After 'W' you can add more options. (8|16(B|L)?) \n");
#endif
    fprintf(stderr,"t        no conversion\n");
    fprintf(stderr,"i_/o_    Output sequence to designate JIS-kanji/ASCII (DEFAULT B)\n");
    fprintf(stderr,"r        {de/en}crypt ROT13/47\n");
    fprintf(stderr,"h        1 hirakana->katakana, 2 katakana->hirakana,3 both\n");
    fprintf(stderr,"v        Show this usage. V: show version\n");
    fprintf(stderr,"m[BQN0]  MIME decode [B:base64,Q:quoted,N:non-strict,0:no decode]\n");
    fprintf(stderr,"M[BQ]    MIME encode [B:base64 Q:quoted]\n");
    fprintf(stderr,"l        ISO8859-1 (Latin-1) support\n");
    fprintf(stderr,"f/F      Folding: -f60 or -f or -f60-10 (fold margin 10) F preserve nl\n");
    fprintf(stderr,"Z[0-3]   Convert X0208 alphabet to ASCII  1: Kankaku to space,2: 2 spaces,\n");
    fprintf(stderr,"                                          3: Convert HTML Entity\n");
    fprintf(stderr,"X,x      Assume X0201 kana in MS-Kanji, -x preserves X0201\n");
    fprintf(stderr,"B[0-2]   Broken input  0: missing ESC,1: any X on ESC-[($]-X,2: ASCII on NL\n");
#ifdef MSDOS
    fprintf(stderr,"T        Text mode output\n");
#endif
    fprintf(stderr,"O        Output to File (DEFAULT 'nkf.out')\n");
    fprintf(stderr,"d,c      Delete \\r in line feed and \\032, Add \\r in line feed\n");
    fprintf(stderr,"I        Convert non ISO-2022-JP charactor to GETA\n");
    fprintf(stderr,"-L[uwm]  line mode u:LF w:CRLF m:CR (DEFAULT noconversion)\n");
    fprintf(stderr,"long name options\n");
    fprintf(stderr," --fj,--unix,--mac,--windows                        convert for the system\n");
    fprintf(stderr," --jis,--euc,--sjis,--utf8,--utf16,--mime,--base64  convert for the code\n");
    fprintf(stderr," --hiragana, --katakana    Hiragana/Katakana Conversion\n");
#ifdef INPUT_OPTION
    fprintf(stderr," --cap-input, --url-input  Convert hex after ':' or '%'\n");
#endif
#ifdef NUMCHAR_OPTION
    fprintf(stderr," --numchar-input      Convert Unicode Character Reference\n");
#endif
#ifdef SHIFTJIS_CP932
    fprintf(stderr," --no-cp932           Don't convert Shift_JIS FAxx-FCxx to equivalnet CP932\n");
#endif
#ifdef UTF8_OUTPUT_ENABLE
    fprintf(stderr," --ms-ucs-map         Microsoft UCS Mapping Compatible\n");
#endif
#ifdef OVERWRITE
    fprintf(stderr," --overwrite          Overwrite original listed files by filtered result\n");
#endif
    fprintf(stderr," -g, --guess          Guess the input code\n");
    fprintf(stderr," --help,--version\n");
    version();
}

void
version()
{
    fprintf(stderr,"Network Kanji Filter Version %s (%s) "
#if defined(MSDOS) && !defined(__WIN32__) && !defined(__WIN16__)
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
                  ,Version,Patchlevel);
    fprintf(stderr,"\n%s\n",CopyRight);
}
#endif

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
