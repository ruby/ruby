/** Network Kanji Filter. (PDS Version)
************************************************************************
** Copyright (C) 1987, Fujitsu LTD. (Itaru ICHIKAWA)
** 連絡先： （株）富士通研究所　ソフト３研　市川　至 
** （E-Mail Address: ichikawa@flab.fujitsu.co.jp）
** Copyright (C) 1996,1998
** 連絡先： 琉球大学情報工学科 河野 真治  mine/X0208 support
** （E-Mail Address: kono@ie.u-ryukyu.ac.jp）
** 連絡先： COW for DOS & Win16 & Win32 & OS/2
** （E-Mail Address: GHG00637@niftyserve.or.p）
**    このソースのいかなる複写，改変，修正も許諾します。ただし、
**    その際には、誰が貢献したを示すこの部分を残すこと。
**    再配布や雑誌の付録などの問い合わせも必要ありません。
**    このプログラムについては特に何の保証もしない、悪しからず。
**    Everyone is permitted to do anything on this program 
**    including copying, modifying, improving.
**    as long as you don't try to pretend that you wrote it.
**    i.e., the above copyright notice has to appear in all copies.
**    You don't have to ask before copying or publishing.
**    THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE.
***********************************************************************/

static char *CopyRight =
      "Copyright (C) 1987, FUJITSU LTD. (I.Ichikawa),1998 S. Kono, COW";
static char *Version =
      "1.7";
static char *Patchlevel =
      "0/9711/Shinji Kono";

/*
**
**
**
** USAGE:       nkf [flags] [file] 
**
** Flags:
** b    Output is bufferred             (DEFAULT)
** u    Output is unbufferred
**
** t    no operation
**
** j    Outout code is JIS 7 bit        (DEFAULT SELECT) 
** s    Output code is MS Kanji         (DEFAULT SELECT) 
** e    Output code is AT&T JIS         (DEFAULT SELECT) 
** l    Output code is JIS 7bit and ISO8859-1 Latin-1
**
** m    MIME conversion for ISO-2022-JP
** i_ Output sequence to designate JIS-kanji (DEFAULT_J)
** o_ Output sequence to designate single-byte roman characters (DEFAULT_R)
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
** O   Output to 'nkf.out' file 
** d   Delete \r in line feed 
** c   Add \r in line feed 
**/
/******************************/
/* デフォルトの出力コード選択 */
/* Select DEFAULT_CODE */
#define DEFAULT_CODE_JIS
/* #define DEFAULT_CODE_SJIS */
/* #define DEFAULT_CODE_EUC */
/******************************/

#if (defined(__TURBOC__) || defined(LSI_C)) && !defined(MSDOS)
#define MSDOS
#endif

#ifndef PERL_XS
#include <stdio.h>
#endif

#if defined(MSDOS) || defined(__OS2__) 
#include <stdlib.h>
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

#ifdef _IOFBF /* SysV and MSDOS */
#define       setvbuffer(fp, buf, size)       setvbuf(fp, buf, _IOFBF, size)
#else /* BSD */
#define       setvbuffer(fp, buf, size)       setbuffer(fp, buf, size)
#endif

/*Borland C++ 4.5 EasyWin*/
#if defined(__TURBOC__) && defined(_Windows) && !defined(__WIN32__) /*Easy Win */
#define         EASYWIN
#include <windows.h>
#endif

#define         FALSE   0
#define         TRUE    1

/* state of output_mode and input_mode  */

#define         ASCII           0
#define         X0208           1
#define         X0201           2
#define         NO_X0201        3
#define         JIS_INPUT       4
#define         SJIS_INPUT      5
#define         LATIN1_INPUT    6
#define         FIXED_MIME      7
#define         DOUBLE_SPACE    -2

#define         NL      0x0a
#define         ESC     0x1b
#define         SPACE   0x20
#define         AT      0x40
#define         SSP     0xa0
#define         DEL     0x7f
#define         SI      0x0f
#define         SO      0x0e
#define         SSO     0x8e

#define         HOLD_SIZE       32
#define         IOBUF_SIZE      16384

#define         DEFAULT_J       'B'
#define         DEFAULT_R       'B'

#define         SJ0162  0x00e1          /* 01 - 62 ku offset */
#define         SJ6394  0x0161          /* 63 - 94 ku offset */


/* MIME preprocessor */

#undef STRICT_MIME       /* do stupid strict mime integrity check */
#define GETC(p) ((!mime_mode)?getc(p):mime_getc(p))
#define UNGETC(c,p)     ((!mime_mode)?ungetc(c,p):mime_ungetc(c))


#ifdef EASYWIN /*Easy Win */
extern POINT _BufferSize;
#endif

/*      function prototype  */

#ifndef _
# ifdef __STDC__
#  define _(args) args
# else
#  define _(args) ()
# endif
#endif

#ifndef PERL_XS
static  void    noconvert _((FILE *f));
static  int     mime_integrity _((FILE *f,unsigned char *p));
static  int     usage _((void));
static char            stdibuf[IOBUF_SIZE];
static char            stdobuf[IOBUF_SIZE];
static unsigned int            mime_input = 0; /* undecoded */
static int             end_check;
#endif

static  void    kanji_convert _((FILE *f));
static  void    h_conv _((FILE *f,int c2,int c1));
static  int     push_hold_buf _((int c2,int c1));
static  void    s_iconv _((int c2,int c1));
static  void    e_oconv _((int c2,int c1));
static  void    s_oconv _((int c2,int c1));
static  void    j_oconv _((int c2,int c1));
static  int     line_fold _((int c2,int c1));
static  int     pre_convert _((int c1,int c2));
static  int     mime_begin _((FILE *f));
static  int     mime_getc _((FILE *f));
static  int     mime_ungetc _((unsigned int c));
static  int     base64decode _((int c));
static  void    arguments _((char *c));
static  void    reinit _((void));

/* buffers */

static unsigned char   hold_buf[HOLD_SIZE*2];
static int             hold_count;

/* MIME preprocessor fifo */

#define MIME_BUF_SIZE   (1024)    /* 2^n ring buffer */
#define MIME_BUF_MASK   (MIME_BUF_SIZE-1)   
#define Fifo(n)         mime_buf[(n)&MIME_BUF_MASK]
static unsigned char           mime_buf[MIME_BUF_SIZE];
static unsigned int            mime_top = 0;
static unsigned int            mime_last = 0;  /* decoded */

/* flags */
static int             unbuf_f = FALSE;
static int             estab_f = FALSE;
static int             nop_f = FALSE;
static int             binmode_f = TRUE;       /* binary mode */
static int             rot_f = FALSE;          /* rot14/43 mode */
static int             input_f = FALSE;        /* non fixed input code  */
static int             alpha_f = FALSE;        /* convert JIx0208 alphbet to ASCII */
static int             mime_f = TRUE;         /* convert MIME B base64 or Q */
static int             mimebuf_f = FALSE;      /* MIME buffered input */
static int             broken_f = FALSE;       /* convert ESC-less broken JIS */
static int             iso8859_f = FALSE;      /* ISO8859 through */
#if defined(MSDOS) || defined(__OS2__) 
static int             x0201_f = TRUE;         /* Assume JISX0201 kana */
#else
static int             x0201_f = NO_X0201;     /* Assume NO JISX0201 */
#endif

/* X0208 -> ASCII converter */

static int             c1_return;

/* fold parameter */
static int line = 0;    /* chars in line */
static int prev = 0;
static int             fold_f  = FALSE;
static int             fold_len  = 0;

/* options */
static char            kanji_intro = DEFAULT_J,
                ascii_intro = DEFAULT_R;

/* Folding */

int line_fold();
#define FOLD_MARGIN  10
#define DEFAULT_FOLD 60

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

static void            (*iconv) _((int c2,int c1));
					/* s_iconv or oconv */
static void            (*oconv) _((int c2,int c1)) = DEFAULT_CONV; 
					  /* [ejs]_oconv */

/* Global states */
static int             output_mode = ASCII,    /* output kanji mode */
                input_mode =  ASCII,    /* input kanji mode */
                shift_mode =  FALSE;    /* TRUE shift out, or X0201  */
static int             mime_mode =   FALSE;    /* MIME mode B base64, Q hex */

/* X0201 / X0208 conversion tables */

/* X0201 kana conversion table */
/* 90-9F A0-DF */
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
unsigned char dv[]= { 
0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
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


static int             file_out = FALSE;
static int             add_cr = FALSE;
static int             del_cr = FALSE;

#ifndef PERL_XS
int
main(argc, argv)
    int             argc;
    char          **argv;
{
    FILE  *fin;
    char  *cp;

#ifdef EASYWIN /*Easy Win */
    _BufferSize.y = 400;/*Set Scroll Buffer Size*/
#endif

    for (argc--,argv++; (argc > 0) && **argv == '-'; argc--, argv++) {
        cp = *argv;
	arguments(cp);
    }

    if(iso8859_f && (oconv != j_oconv || !x0201_f )) {
        fprintf(stderr,"Mixed ISO8859/JISX0201/SJIS/EUC output is not allowed.\n");
        exit(1);
    }

    if(binmode_f == TRUE)
#ifdef __OS2__
    if(freopen("","wb",stdout) == NULL) 
        return (-1);
#else
    setbinmode(stdout);
#endif

    if(unbuf_f)
      setbuf(stdout, (char *) NULL);
    else
      setvbuffer(stdout, stdobuf, IOBUF_SIZE);

    if(argc == 0) {
      if(binmode_f == TRUE)
#ifdef __OS2__
      if(freopen("","rb",stdin) == NULL) return (-1);
#else
      setbinmode(stdin);
#endif
      setvbuffer(stdin, stdibuf, IOBUF_SIZE);
      if(nop_f)
          noconvert(stdin);
      else
          kanji_convert(stdin);
    } else {
      while (argc--) {
          if((fin = fopen(*argv++, "r")) == NULL) {
              perror(*--argv);
              return(-1);
          } else {
/* reopen file for stdout */
              if(file_out == TRUE){ 
                  if(argc == 1 ) {
                      if(freopen(*argv++, "w", stdout) == NULL) {
                          perror(*--argv);
                          return (-1);
                      }
                      argc--;
                  } else {
                      if(freopen("nkf.out", "w", stdout) == NULL) {
                         perror(*--argv);
                         return (-1);
                      }
                  }
                  if(binmode_f == TRUE) {
#ifdef __OS2__
                      if(freopen("","wb",stdout) == NULL) 
                           return (-1);
#else
                      setbinmode(stdout);
#endif
                  }
              }
              if(binmode_f == TRUE)
#ifdef __OS2__
                 if(freopen("","rb",fin) == NULL) 
                    return (-1);
#else
                 setbinmode(fin);
#endif 
              setvbuffer(fin, stdibuf, IOBUF_SIZE);
              if(nop_f)
                  noconvert(fin);
              else
                  kanji_convert(fin);
              fclose(fin);
          }
      }
    }
#ifdef EASYWIN /*Easy Win */
    if(file_out == FALSE) 
        scanf("%d",&end_check);
    else 
        fclose(stdout);
#else /* for Other OS */
    if(file_out == TRUE) 
        fclose(stdout);
#endif 
    return (0);
}
#endif

static void
arguments(cp) 
    char *cp;
{
    while (*cp) {
	switch (*cp++) {
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
	    oconv = j_oconv;
	    continue;
	case 'e':           /* AT&T EUC output */
	    oconv = e_oconv;
	    continue;
	case 's':           /* SJIS output */
	    oconv = s_oconv;
	    continue;
	case 'l':           /* ISO8859 Latin-1 support, no conversion */
	    iso8859_f = TRUE;  /* Only compatible with ISO-2022-JP */
	    input_f = LATIN1_INPUT;
	    continue;
	case 'i':           /* Kanji IN ESC-$-@/B */
	    if(*cp=='@'||*cp=='B') 
		kanji_intro = *cp++;
	    continue;
	case 'o':           /* ASCII IN ESC-(-J/B */
	    if(*cp=='J'||*cp=='B'||*cp=='H') 
		ascii_intro = *cp++;
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
	case 'v':
	    usage();
	    exit(1);
	    break;
#endif
	/* Input code assumption */
	case 'J':   /* JIS input */
	case 'E':   /* AT&T EUC input */
	    input_f = JIS_INPUT;
	    continue;
	case 'S':   /* MS Kanji input */
	    input_f = SJIS_INPUT;
	    if(x0201_f==NO_X0201) x0201_f=TRUE;
	    continue;
	case 'Z':   /* Convert X0208 alphabet to asii */
	    /*  bit:0   Convert X0208
		bit:1   Convert Kankaku to one space
		bit:2   Convert Kankaku to two spaces
	    */
	    if('9'>= *cp && *cp>='0') 
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
	case 'f':   /* folding -f60 or -f */
	    fold_f = TRUE;
	    fold_len = atoi(cp);
	    if(!(0<fold_len && fold_len<BUFSIZ)) 
		fold_len = DEFAULT_FOLD;
	    while('0'<= *cp && *cp <='9') cp++;
	    continue;
	case 'm':   /* MIME support */
	    mime_f = TRUE;
	    if(*cp=='B'||*cp=='Q') {
		mime_mode = *cp++;
		mimebuf_f = FIXED_MIME;
	    } else if (*cp=='0') {
		mime_f = FALSE;
	    }
	    continue;
	case 'M':   /* MIME output */
	    oconv = j_oconv;    /* sorry... not yet done.. */
	    continue;
	case 'B':   /* Broken JIS support */
	    /*  bit:0   no ESC JIS
		bit:1   allow any x on ESC-(-x or ESC-$-x
		bit:2   reset to ascii on NL
	    */
	    if('9'>= *cp && *cp>='0') 
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
	    add_cr = TRUE;
	    continue;
	case 'd':/* delete cr code */
	    del_cr = TRUE;
	    continue;
	default:
	    /* bogus option but ignored */
	    continue;
	}
    }
}

#ifndef PERL_XS
static void
noconvert(f)
    FILE  *f;
{
    int    c;

    while ((c = getc(f)) != EOF)
      putchar(c);
}
#endif


static void
kanji_convert(f)
    FILE  *f;
{
    int    c1, c2;

    c2 = 0;

    if(input_f == JIS_INPUT || input_f == LATIN1_INPUT) {
        estab_f = TRUE; iconv = oconv;
    } else if(input_f == SJIS_INPUT) {
        estab_f = TRUE;  iconv = s_iconv;
    } else {
        estab_f = FALSE; iconv = oconv;
    }
    input_mode = ASCII;
    output_mode = ASCII;
    shift_mode = FALSE;

#define NEXT continue      /* no output, get next */
#define SEND ;             /* output c1 and c2, get next */
#define LAST break         /* end of loop, go closing  */

    while ((c1 = GETC(f)) != EOF) {
        if(c2) {
            /* second byte */
            if(c2 > DEL) {
                /* in case of 8th bit is on */
                if(!estab_f) {
                    /* in case of not established yet */
                    if(c1 > SSP) {
                        /* It is still ambiguious */
                        h_conv(f, c2, c1);
                        c2 = 0;
                        NEXT;
                    } else if(c1 < AT) {
                        /* ignore bogus code */
                        c2 = 0;
                        NEXT;
                    } else {
                        /* established */
                        /* it seems to be MS Kanji */
                        estab_f = TRUE;
                        iconv = s_iconv;
                        SEND;
                    }
                } else
                    /* in case of already established */
                    if(c1 < AT) {
                        /* ignore bogus code */
                        c2 = 0;
                        NEXT;
                    } else
                        SEND;
            } else
                /* 7 bit code */
                /* it might be kanji shitfted */
                if((c1 == DEL) || (c1 <= SPACE)) {
                    /* ignore bogus first code */
                    c2 = 0;
                    NEXT;
                } else
                    SEND;
        } else {
            /* first byte */
            if(c1 > DEL) {
                /* 8 bit code */
                if(!estab_f && !iso8859_f) {
                    /* not established yet */
                    if(c1 < SSP) {
                        /* it seems to be MS Kanji */
                        estab_f = TRUE;
                        iconv = s_iconv;
                    } else if(c1 < 0xe0) {
                        /* it seems to be EUC */
                        estab_f = TRUE;
                        iconv = oconv;
                    } else {
                        /* still ambiguious */
                    }
                    c2 = c1;
                    NEXT;
                } else { /* estab_f==TRUE */
                    if(iso8859_f) {
                        SEND;
                    } else if(SSP<=c1 && c1<0xe0 && iconv == s_iconv) {
                        /* SJIS X0201 Case... */
                        /* This is too arrogant, but ... */
                        if(x0201_f==NO_X0201) {
                            iconv = oconv;
                            c2 = c1;
                            NEXT;
                        } else 
                        if(x0201_f) {
                            if(dv[(c1-SSP)*2]||ev[(c1-SSP)*2]) {
                            /* look ahead for X0201/X0208conversion */
                                if((c2 = GETC(f)) == EOF) {
                                    (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                                    LAST;
                                } else if(c2==(0xde)) { /* 濁点 */
                                    (*oconv)(dv[(c1-SSP)*2],dv[(c1-SSP)*2+1]);
                                    c2=0; 
                                    NEXT;
                                } else if(c2==(0xdf)&&ev[(c1-SSP)*2]) { 
                                    /* 半濁点 */
                                    (*oconv)(ev[(c1-SSP)*2],ev[(c1-SSP)*2+1]);
                                    c2=0; 
                                    NEXT;
                                } 
                                UNGETC(c2,f); c2 = 0;
                            }
                            (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                            NEXT;
                        } else
                            SEND;
                    } else if(c1==SSO && iconv != s_iconv) {
                        /* EUC X0201 Case */
                        /* This is too arrogant
                        if(x0201_f == NO_X0201) {
                            estab_f = FALSE; 
                            c2 = 0;  
                            NEXT;
                        } */
                        c1 = GETC(f);  /* skip SSO */
                        euc_1byte_check:
                        if(x0201_f && SSP<=c1 && c1<0xe0) {
                            if(dv[(c1-SSP)*2]||ev[(c1-SSP)*2]) {
                                if((c2 = GETC(f)) == EOF) {
                                    (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                                    LAST;
                                }
                                /* forward lookup 濁点/半濁点 */
                                if(c2 != SSO) {
                                    UNGETC(c2,f); c2 = 0; 
                                    (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                                    NEXT;
                                } else if((c2 = GETC(f)) == EOF) {
                                    (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                                    (*oconv)(0,SSO); 
                                    LAST;
                                } else if(c2==(0xde)) { /* 濁点 */
                                    (*oconv)(dv[(c1-SSP)*2],dv[(c1-SSP)*2+1]);
                                    c2=0; 
                                    NEXT;
                                } else if(c2==(0xdf)&&ev[(c1-SSP)*2]) { 
                                    /* 半濁点 */
                                    (*oconv)(ev[(c1-SSP)*2],ev[(c1-SSP)*2+1]);
                                    c2=0; 
                                    NEXT;
                                } else {
                                    (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                                    /* we have to check this c2 */
                                    /* and no way to push back SSO */
                                    c1 = c2; c2 = 0;
                                    goto euc_1byte_check;
                                }
                            }
                            (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                            NEXT;
                        } else 
                            SEND;
                    } else if(c1 < SSP && iconv != s_iconv) {
                        /* strange code in EUC */
                        iconv = s_iconv;  /* try SJIS */
                        c2 = c1;
                        NEXT;
                    } else {
                       /* already established */
                       c2 = c1;
                       NEXT;
                    }
                }
            } else if((c1 > SPACE) && (c1 != DEL)) {
                /* in case of Roman characters */
                if(shift_mode) { 
                    c1 |= 0x80;
                    /* output 1 shifted byte */
                    if(x0201_f && (!iso8859_f||input_mode==X0201) && 
                            SSP<=c1 && c1<0xe0 ) {
                        if(dv[(c1-SSP)*2]||ev[(c1-SSP)*2]) {
                            if((c2 = GETC(f)) == EOF) {
                                (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                                LAST;
                            } else if(c2==(0xde&0x7f)) { /* 濁点 */
                                (*oconv)(dv[(c1-SSP)*2],dv[(c1-SSP)*2+1]);
                                c2=0; 
                                NEXT;
                            } else if(c2==(0xdf&0x7f)&&ev[(c1-SSP)*2]) {  
                                /* 半濁点 */
                                (*oconv)(ev[(c1-SSP)*2],ev[(c1-SSP)*2+1]);
                                c2=0; 
                                NEXT;
                            }
                            UNGETC(c2,f); c2 = 0;
                        }
                        (*oconv)(cv[(c1-SSP)*2],cv[(c1-SSP)*2+1]);
                        NEXT;
                    } else
                        SEND;
                } else if(c1 == '(' && broken_f && input_mode == X0208
                        && !mime_mode ) {
                    /* Try to recover missing escape */
                    if((c1 = GETC(f)) == EOF) {
                        (*oconv)(0, '(');
                        LAST;
                    } else {
                        if(c1 == 'B' || c1 == 'J' || c1 == 'H') {
                            input_mode = ASCII; shift_mode = FALSE;
                            NEXT;
                        } else {
                            (*oconv)(0, '(');
                            /* do not modify various input_mode */
                            /* It can be vt100 sequence */
                            SEND;
                        }
                    }
                } else if(input_mode == X0208) {
                    /* in case of Kanji shifted */
                    c2 = c1;
                    NEXT;
                    /* goto next_byte */
                } else if(c1 == '=' && mime_f && !mime_mode ) {
                    if((c1 = getc(f)) == EOF) {
                        (*oconv)(0, '=');
                        LAST;
                    } else if(c1 == '?') {
                        /* =? is mime conversiooon start sequence */
                        if(mime_begin(f) == EOF) /* check in detail */
                            LAST;
                        else
                            NEXT;
                    } else {
                        (*oconv)(0, '=');
                        ungetc(c1,f);
                        NEXT;
                    }
                } else if(c1 == '$' && broken_f && !mime_mode) {
                    /* try to recover missing escape */
                    if((c1 = GETC(f)) == EOF) {
                        (*oconv)(0, '$');
                        LAST;
                    } else if(c1 == '@'|| c1 == 'B') {
                        /* in case of Kanji in ESC sequence */
                        input_mode = X0208;
                        shift_mode = FALSE;
                        NEXT;
                    } else {
                        /* sorry */
                        (*oconv)(0, '$');
                        (*oconv)(0, c1);
                        NEXT;
                    }
                } else
                    SEND;
            } else if(c1 == SI) {
                shift_mode = FALSE; 
                NEXT;
            } else if(c1 == SO) {
                shift_mode = TRUE; 
                NEXT;
            } else if(c1 == ESC) {
                if((c1 = GETC(f)) == EOF) {
                    (*oconv)(0, ESC);
                    LAST;
                } else if(c1 == '$') {
                    if((c1 = GETC(f)) == EOF) {
                        (*oconv)(0, ESC);
                        (*oconv)(0, '$');
                        LAST;
                    } else if(c1 == '@'|| c1 == 'B') {
                        /* This is kanji introduction */
                        input_mode = X0208;
                        shift_mode = FALSE;
                        NEXT;
                    } else if(c1 == '(') {
			if((c1 = GETC(f)) == EOF) {
			    (*oconv)(0, ESC);
			    (*oconv)(0, '$');
			    (*oconv)(0, '(');
			    LAST;
			} else if(c1 == '@'|| c1 == 'B') {
			    /* This is kanji introduction */
			    input_mode = X0208;
			    shift_mode = FALSE;
			    NEXT;
			} else {
			    (*oconv)(0, ESC);
			    (*oconv)(0, '$');
			    (*oconv)(0, '(');
			    (*oconv)(0, c1);
			    NEXT;
			}
                    } else if(broken_f&0x2) {
                        input_mode = X0208;
                        shift_mode = FALSE;
                        NEXT;
                    } else {
                        (*oconv)(0, ESC);
                        (*oconv)(0, '$');
                        (*oconv)(0, c1);
                        NEXT;
                    }
                } else if(c1 == '(') {
                    if((c1 = GETC(f)) == EOF) {
                        (*oconv)(0, ESC);
                        (*oconv)(0, '(');
                        LAST;
                    } else {
                        if(c1 == 'I') {
                            /* This is X0201 kana introduction */
                            input_mode = X0201; shift_mode = X0201;
                            NEXT;
                        } else if(c1 == 'B' || c1 == 'J' || c1 == 'H') {
                            /* This is X0208 kanji introduction */
                            input_mode = ASCII; shift_mode = FALSE;
                            NEXT;
                        } else if(broken_f&0x2) {
                            input_mode = ASCII; shift_mode = FALSE;
                            NEXT;
                        } else {
                            (*oconv)(0, ESC);
                            (*oconv)(0, '(');
                            /* maintain various input_mode here */
                            SEND;
                        }
                    }
                } else {
                    /* lonely ESC  */
                    (*oconv)(0, ESC);
                    SEND;
                }
            } else if(c1 == NL && broken_f&4) {
                input_mode = ASCII; 
                SEND;
            } else
                SEND;
        }
        /* send: */
        if(input_mode == X0208) 
            (*oconv)(c2, c1);  /* this is JIS, not SJIS/EUC case */
        else
            (*iconv)(c2, c1);  /* can be EUC/SJIS */
        c2 = 0;
        continue;
        /* goto next_word */
    }

    /* epilogue */
    (*iconv)(EOF, 0);
}




static void
h_conv(f, c2, c1)
    FILE  *f;
    int    c1, c2;
{
    int    wc;


    /** it must NOT be in the kanji shifte sequence      */
    /** it must NOT be written in JIS7                   */
    /** and it must be after 2 byte 8bit code            */

    hold_count = 0;
    push_hold_buf(c2, c1);
    c2 = 0;

    while ((c1 = GETC(f)) != EOF) {
        if(c2) {
            /* second byte */
            if(!estab_f) {
                /* not established */
                if(c1 > SSP) {
                    /* it is still ambiguious yet */
                    SEND;
                } else if(c1 < AT) {
                    /* ignore bogus first byte */
                    c2 = 0;
                    SEND;
                } else {
                    /* now established */
                    /* it seems to be MS Kanji */
                    estab_f = TRUE;
                    iconv = s_iconv;
                    SEND;
                }
            } else
                SEND;
        } else {
            /* First byte */
            if(c1 > DEL) {
                /* 8th bit is on */
                if(c1 < SSP) {
                    /* it seems to be MS Kanji */
                    estab_f = TRUE;
                    iconv = s_iconv;
                } else if(c1 < 0xe0) {
                    /* it seems to be EUC */
                    estab_f = TRUE;
                    iconv = oconv;
                } else {
                    /* still ambiguious */
                }
                c2 = c1;
                NEXT;
            } else
            /* 7 bit code , then send without any process */
                SEND;
        }
        /* send: */
        if((push_hold_buf(c2, c1) == EOF) || estab_f)
            break;
        c2 = 0;
        continue;
    }

    /** now,
     ** 1) EOF is detected, or
     ** 2) Code is established, or
     ** 3) Buffer is FULL (but last word is pushed)
     **
     ** in 1) and 3) cases, we continue to use
     ** Kanji codes by oconv and leave estab_f unchanged.
     **/

    for (wc = 0; wc < hold_count; wc += 2) {
        c2 = hold_buf[wc];
        c1 = hold_buf[wc+1];
        (*iconv)(c2, c1);
    }
    return;
}



static int
push_hold_buf(c2, c1)
    int c2, c1;
{
    if(hold_count >= HOLD_SIZE*2)
        return (EOF);
    hold_buf[hold_count++] = c2;
    hold_buf[hold_count++] = c1;
    return ((hold_count >= HOLD_SIZE*2) ? EOF : hold_count);
}


static void
s_iconv(c2, c1)
    int    c2,
                    c1;
{
    if((c2 == EOF) || (c2 == 0)) {
        /* NOP */
    } else {
        c2 = c2 + c2 - ((c2 <= 0x9f) ? SJ0162 : SJ6394);
        if(c1 < 0x9f)
            c1 = c1 - ((c1 > DEL) ? SPACE : 0x1f);
        else {
            c1 = c1 - 0x7e;
            c2++;
        }
    }
    (*oconv)(c2, c1);
}


static void
e_oconv(c2, c1)
    int    c2, c1;
{
    c2 = pre_convert(c1,c2); c1 = c1_return;
    if(fold_f) {
        switch(line_fold(c2,c1)) {
            case '\n': 
                if(add_cr == TRUE) {
                    putchar('\r');
                    c1 = '\n';
                }
                putchar('\n');
                break;
            case 0:    return;
            case '\r': 
                c1 = '\n'; c2 = 0;
                break;
            case '\t': 
            case ' ': 
                c1 = ' '; c2 = 0;
                break;
        }
    }
    if(c2==DOUBLE_SPACE) {
        putchar(' '); putchar(' ');
        return;
    }
    if(c2 == EOF)
        return;
    else if(c2 == 0 && (c1&0x80)) {
        putchar(SSO); putchar(c1);
    } else if(c2 == 0) {
        if(c1 == '\n' && add_cr == TRUE) 
            putchar('\r');
        if(c1 != '\r') 
            putchar(c1);
        else if(del_cr == FALSE) 
            putchar(c1);
    } else {
        if((c1<0x20 || 0x7e<c1) ||
           (c2<0x20 || 0x7e<c2)) {
            estab_f = FALSE;
            return; /* too late to rescue this char */
        }
        putchar(c2 | 0x080);
        putchar(c1 | 0x080);
    }
    return;
}


static void
s_oconv(c2, c1)
    int    c2, c1;
{
    c2 = pre_convert(c1,c2); c1 = c1_return;
    if(fold_f) {
        switch(line_fold(c2,c1)) {
            case '\n': 
                if(add_cr == TRUE) {
                   putchar('\r');
                   c1 = '\n';
                }
                putchar('\n');
                break;
            case '\r': 
                c1 = '\n'; c2 = 0;
                break;
            case 0:    return;
            case '\t': 
            case ' ': 
                c1 = ' '; c2 = 0;
                break;
        }
    }
    if(c2==DOUBLE_SPACE) {
        putchar(' '); putchar(' ');
        return;
    }
    if(c2 == EOF)
        return;
    else if(c2 == 0) {
        if(c1 == '\n' && add_cr == TRUE) 
            putchar('\r');
        if(c1 != '\r') 
            putchar(c1);
        else if(del_cr == FALSE) 
            putchar(c1);
    } else {
        if((c1<0x20 || 0x7e<c1) ||
           (c2<0x20 || 0x7e<c2)) {
            estab_f = FALSE;
            return; /* too late to rescue this char */
        }
        putchar((((c2 - 1) >> 1) + ((c2 <= 0x5e) ? 0x71 : 0xb1)));
        putchar((c1 + ((c2 & 1) ? ((c1 < 0x60) ? 0x1f : 0x20) : 0x7e)));
    }
    return;
}


static void
j_oconv(c2, c1)
    int    c2, c1;
{
    c2 = pre_convert(c1,c2); c1 = c1_return;
    if(fold_f) {
        switch(line_fold(c2,c1)) {
            case '\n': 
                if(output_mode) {
                    putchar(ESC);
                    putchar('(');
                    putchar(ascii_intro);
                }
                if(add_cr == TRUE) {
                    putchar('\r');
                    c1 = '\n';
                }
                putchar('\n');
                output_mode = ASCII;
                break;
            case '\r': 
                c1 = '\n'; c2 = 0;
                break;
            case '\t': 
            case ' ': 
                c1 = ' '; c2 = 0;
                break;
            case 0:    return;
        }
     }
    if(c2 == EOF) {
        if(output_mode) {
            putchar(ESC);
            putchar('(');
            putchar(ascii_intro);
        }
    } else if(c2 == 0 && (c1 & 0x80)) {
        if(input_mode==X0201 || !iso8859_f) {
            if(output_mode!=X0201) {
                putchar(ESC);
                putchar('(');
                putchar('I');
                output_mode = X0201;
            }
            c1 &= 0x7f;
        } else {
            /* iso8859 introduction, or 8th bit on */
            /* Can we convert in 7bit form using ESC-'-'-A ? 
               Is this popular? */
        }
        putchar(c1);
    } else if(c2 == 0) {
        if(output_mode) {
            putchar(ESC);
            putchar('(');
            putchar(ascii_intro);
            output_mode = ASCII;
        }
        if(c1 == '\n' && add_cr == TRUE) 
            putchar('\r');
        if(c1 != '\r') 
            putchar(c1);
        else if(del_cr == FALSE) 
            putchar(c1);
    } else if(c2 == DOUBLE_SPACE) {
        if(output_mode) {
            putchar(ESC);
            putchar('(');
            putchar(ascii_intro);
            output_mode = ASCII;
        }
        putchar(' ');
        if(c1 == '\n' && add_cr == TRUE) 
            putchar('\r');
        if(c1 != '\r') 
            putchar(c1);
        else if(del_cr == FALSE) 
            putchar(c1);
    } else {
        if(output_mode != X0208) {
            putchar(ESC);
            putchar('$');
            putchar(kanji_intro);
            output_mode = X0208;
        }
        if(c1<0x20 || 0x7e<c1) 
            return;
        if(c2<0x20 || 0x7e<c2) 
            return;
        putchar(c2);
        if(c1 == '\n' && add_cr == TRUE) 
            putchar('\r');
        if(c1 != '\r') 
            putchar(c1);
        else if(del_cr == FALSE) 
            putchar(c1);
    }
    return;
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


/* 
  Return value of line_fold()

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

static int
line_fold(c2,c1) 
int c2,c1;
{ 
    int prev0;
    if(c1=='\r') 
        return 0;               /* ignore cr */
    if(c1== 8) {
        if(line>0) line--;
        return 1;
    }
    if(c2==EOF && line != 0)    /* close open last line */
        return '\n';
    /* new line */
    if(c1=='\n') {
        if(prev == c1) {        /* duplicate newline */
            if(line) {
                line = 0;
                return '\n';    /* output two newline */
            } else {
                line = 0;
                return 1;
            }
        } else  {
            if(prev&0x80) {     /* Japanese? */
                prev = c1;
                return 0;       /* ignore given single newline */
            } else if(prev==' ') {
                return 0;
            } else {
                prev = c1;
                if(++line<=fold_len) 
                    return ' ';
                else {
                    line = 0;
                    return '\r';        /* fold and output nothing */
                }
            }
        }
    }
    if(c1=='\f') {
        prev = '\n';
        if(line==0)
            return 1;
        line = 0;
        return '\n';            /* output newline and clear */
    }
    /* X0208 kankaku or ascii space */
    if( (c2==0&&c1==' ')||
        (c2==0&&c1=='\t')||
        (c2==DOUBLE_SPACE)||
        (c2=='!'&& c1=='!')) {
        if(prev == ' ') {
            return 0;           /* remove duplicate spaces */
        } 
        prev = ' ';    
        if(++line<=fold_len) 
            return ' ';         /* output ASCII space only */
        else {
            prev = ' '; line = 0;
            return '\r';        /* fold and output nothing */
        }
    } 
    prev0 = prev; /* we still need this one... , but almost done */
    prev = c1;
    if(c2 || (SSP<=c1 && c1<=0xdf)) 
        prev |= 0x80;  /* this is Japanese */
    line += (c2==0)?1:2;
    if(line<=fold_len) {   /* normal case */
        return 1;
    }
    if(line>=fold_len+FOLD_MARGIN) { /* too many kinsou suspension */
        line = (c2==0)?1:2;
        return '\n';       /* We can't wait, do fold now */
    }
    /* simple kinsoku rules  return 1 means no folding  */
    if(c2==0) {
        if(c1==0xde) return 1; /* ゛*/
        if(c1==0xdf) return 1; /* ゜*/
        if(c1==0xa4) return 1; /* 。*/
        if(c1==0xa3) return 1; /* ，*/
        if(c1==0xa1) return 1; /* 」*/
        if(c1==0xb0) return 1; /* - */
        if(SSP<=c1 && c1<=0xdf) {               /* X0201 */
            line = 1;
            return '\n';/* add one new line before this character */
        }
        /* fold point in ASCII { [ ( */
        if(( c1!=')'&&
             c1!=']'&&
             c1!='}'&&
             c1!='.'&&
             c1!=','&&
             c1!='!'&&
             c1!='?'&&
             c1!='/'&&
             c1!=':'&&
             c1!=';')&&
            ((prev0=='\n')|| (prev0==' ')||     /* ignored new line */
            (prev0&0x80))                       /* X0208 - ASCII */
            ) {
            line = 1;
            return '\n';/* add one new line before this character */
        }
        return 1;  /* default no fold in ASCII */
    } else {
        if(c2=='!') {
            if(c1=='"')  return 1; /* 、 */
            if(c1=='#')  return 1; /* 。 */
            if(c1=='$')  return 1; /* ， */
            if(c1=='%')  return 1; /* ． */
            if(c1=='\'') return 1; /* ＋ */
            if(c1=='(')  return 1; /* ； */
            if(c1==')')  return 1; /* ？ */
            if(c1=='*')  return 1; /* ！ */
            if(c1=='+')  return 1; /* ゛ */
            if(c1==',')  return 1; /* ゜ */
        }
        line = 2;
        return '\n'; /* add one new line before this character */
    }
}

static int
pre_convert(c1,c2)
    int c1,c2;
{
        if(c2) c1 &= 0x7f;
        c1_return = c1;
        if(c2==EOF) return c2;
        c2 &= 0x7f;
        if(rot_f) {
            if(c2) {
                c1 = rot47(c1);
                c2 = rot47(c2);
            } else {
                if(!(c1 & 0x80)) 
                    c1 = rot13(c1);
            }
            c1_return = c1;
        }
        /* JISX0208 Alphabet */
        if(alpha_f && c2 == 0x23 ) return 0; 
        /* JISX0208 Kigou */
        if(alpha_f && c2 == 0x21 ) { 
           if(0x21==c1) {
               if(alpha_f&0x2) {
                   c1_return = ' ';
                   return 0;
               } else if(alpha_f&0x4) {
                   c1_return = ' ';
                   return DOUBLE_SPACE;
               } else {
                   return c2;
               }
           } else if(0x20<c1 && c1<0x7f && fv[c1-0x20]) {
               c1_return = fv[c1-0x20];
               return 0;
           } 
        }
        return c2;
}


#ifdef STRICT_MIME
/* This converts  */

unsigned char *mime_pattern[] = {
   (unsigned char *)"\075?ISO-8859-1?Q?",
   (unsigned char *)"\075?ISO-2022-JP?B?",
   (unsigned char *)"\075?ISO-2022-JP?Q?",
   (unsigned char *)"\075?JAPANESE_EUC?B?",
   (unsigned char *)"\075?SHIFT_JIS?B?",
   NULL
};

int      mime_encode[] = {
    'Q', 'B', 'Q',
    0
};
#endif

#define MAXRECOVER 20
int iso8859_f_save;

#ifdef STRICT_MIME

#define nkf_toupper(c)  (('a'<=c && c<='z')?(c-('a'-'A')):c)
/* I don't trust portablity of toupper */

static int
mime_begin(f)
    FILE *f;
{
    int c1;
    int i,j,k;
    unsigned char *p,*q;
    int r[MAXRECOVER];    /* recovery buffer, max mime pattern lenght */

    mime_mode = FALSE;
    /* =? has been checked   */
    j = 0;
    p = mime_pattern[j];
    r[0]='='; r[1]='?';

    for(i=2;p[i]>' ';i++) {                   /* start at =? */
        if( ((((r[i] = c1 = getc(f))==EOF) || nkf_toupper(c1) != p[i] ) {
            /* pattern fails, try next one */
            q = p;
            while (p = mime_pattern[++j]) {
                for(k=2;k<i;k++)              /* assume length(p) > i */
                    if(p[k]!=q[k]) break;
                if(k==i && nkf_toupper(c1)==p[k]) break;
            }
            if(p) continue;  /* found next one, continue */
            /* all fails, output from recovery buffer */
            ungetc(c1,f);
            for(j=0;j<i;j++) {
                (*oconv)(0,r[j]);
            }
            return c1;
        }
    }
    mime_mode = mime_encode[j];
    iso8859_f_save = iso8859_f;
    if(j==0) {
        iso8859_f = TRUE;
    }
    if(mime_mode=='B') {
        mimebuf_f = unbuf_f;
        if(!unbuf_f) {
            /* do MIME integrity check */
            return mime_integrity(f,mime_pattern[j]);
        } 
    }
    mimebuf_f = TRUE;
    return c1;
}

#define mime_getc0(f)   (mimebuf_f?getc(f):Fifo(mime_input++))
#define mime_ungetc0(c,f) (mimebuf_f?ungetc(c,f):mime_input--)

#else
static int
mime_begin(f)
FILE *f;
{
    int c1;
    int i,j;
    int r[MAXRECOVER];    /* recovery buffer, max mime pattern lenght */

    mime_mode = FALSE;
    /* =? has been checked   */
    j = 0;
    r[0]='='; r[1]='?';
    for(i=2;i<MAXRECOVER;i++) {                   /* start at =? */
	/* We accept any charcter type even if it is breaked by new lines */
        if( (r[i] = c1 = getc(f))==EOF) break;
	if(c1=='=') break;
	if(c1<' '&& c1!='\r' && c1!='\n') break;
	if(c1=='?') {
	    i++;
	    if(!(i<MAXRECOVER) || (r[i] = c1 = getc(f))==EOF) break;
	    if(c1=='b'||c1=='B') {
		mime_mode = 'B';
	    } else if(c1=='q'||c1=='Q') {
		mime_mode = 'Q';
	    } else {
		break;
	    }
	    i++;
	    if(!(i<MAXRECOVER) || (r[i] = c1 = getc(f))==EOF) break;
	    if(c1=='?') {
		break;
	    } else {
		mime_mode = FALSE;
	    }
	    break;
	}
    }
    if(!mime_mode || c1==EOF || i==MAXRECOVER) {
	ungetc(c1,f);
	if (i == MAXRECOVER)
	    i--;
	for(j=0;j<i;j++) {
	    (*oconv)(0,r[j]);
	}
	return c1;
    }
    iso8859_f_save = iso8859_f;
    /* do no MIME integrity check */
    return c1;   /* used only for checking EOF */
}

#define mime_getc0(f)   getc(f)
#define mime_ungetc0(c,f) ungetc(c,f)

#endif

static int 
mime_getc(f)
    FILE *f;
{
    int c1, c2, c3, c4, cc;
    int t1, t2, t3, t4, mode, exit_mode;

    if(mime_top != mime_last) {  /* Something is in FIFO */
        return  Fifo(mime_top++);
    }

    if(mimebuf_f == FIXED_MIME)
        exit_mode = mime_mode;
    else
        exit_mode = FALSE;
    if(mime_mode == 'Q') {
        if((c1 = mime_getc0(f)) == EOF) return (EOF);
        if(c1=='_') return ' ';
        if(c1!='=' && c1!='?') 
            return c1;
        mime_mode = exit_mode; /* prepare for quit */
        if(c1<=' ') return c1;
        if((c2 = mime_getc0(f)) == EOF) return (EOF);
        if(c2<=' ') return c2;
        if(c1=='?'&&c2=='=') {
            /* end Q encoding */
            input_mode = exit_mode;
            iso8859_f = iso8859_f_save;
            return getc(f);
        }
        if(c1=='?') {
            mime_mode = 'Q'; /* still in MIME */
            mime_ungetc0(c2,f);
            return c1;
        }
        if((c3 = mime_getc0(f)) == EOF) return (EOF);
        if(c2<=' ') return c2;
        mime_mode = 'Q'; /* still in MIME */
#define hex(c)   (('0'<=c&&c<='9')?(c-'0'):\
     ('A'<=c&&c<='F')?(c-'A'+10):('a'<=c&&c<='f')?(c-'a'+10):0)
        return ((hex(c2)<<4) + hex(c3));
    }

    if(mime_mode != 'B') {
        mime_mode = FALSE;
        return getc(f);
    }


    /* Base64 encoding */
    /* 
        MIME allows line break in the middle of 
        Base64, but we are very pessimistic in decoding
        in unbuf mode because MIME encoded code may broken by 
        less or editor's control sequence (such as ESC-[-K in unbuffered
        mode. ignore incomplete MIME.
    */
    mode = mime_mode;
    mime_mode = exit_mode;  /* prepare for quit */

    while ((c1 = mime_getc0(f))<=' ') {
        if(c1==EOF)
            return (EOF);
    }
    if((c2 = mime_getc0(f))<=' ') {
        if(c2==EOF)
            return (EOF);
        if(mimebuf_f!=FIXED_MIME) input_mode = ASCII;  
        return c2;
    }
    if((c1 == '?') && (c2 == '=')) {
        input_mode = ASCII;
        while((c1 =  getc(f))==' ' /* || c1=='\n' || c1=='\r' */);
        return c1;
    }
    if((c3 = mime_getc0(f))<=' ') {
        if(c3==EOF)
            return (EOF);
        if(mimebuf_f!=FIXED_MIME) input_mode = ASCII;  
        return c3;
    }
    if((c4 = mime_getc0(f))<=' ') {
        if(c4==EOF)
            return (EOF);
        if(mimebuf_f!=FIXED_MIME) input_mode = ASCII;  
        return c4;
    }

    mime_mode = mode; /* still in MIME sigh... */

    /* BASE 64 decoding */

    t1 = 0x3f & base64decode(c1);
    t2 = 0x3f & base64decode(c2);
    t3 = 0x3f & base64decode(c3);
    t4 = 0x3f & base64decode(c4);
    cc = ((t1 << 2) & 0x0fc) | ((t2 >> 4) & 0x03);
    if(c2 != '=') {
        Fifo(mime_last++) = cc;
        cc = ((t2 << 4) & 0x0f0) | ((t3 >> 2) & 0x0f);
        if(c3 != '=') {
            Fifo(mime_last++) = cc;
            cc = ((t3 << 6) & 0x0c0) | (t4 & 0x3f);
            if(c4 != '=') 
                Fifo(mime_last++) = cc;
        }
    } else {
        return c1;
    }
    return  Fifo(mime_top++);
}

static int
mime_ungetc(c) 
    unsigned int c;
{
    Fifo(mime_last++) = c;
    return c;
}

#ifdef STRICT_MIME
int
mime_integrity(f,p)
    FILE *f;
    unsigned char *p;
{
    int c,d;
    unsigned int q;
    /* In buffered mode, read until =? or NL or buffer fffull
     */
    mime_input = mime_top;
    mime_last = mime_top;
    while(*p) Fifo(mime_input++) = *p++;
    d = 0;
    q = mime_input;
    while((c=getc(f))!=EOF) {
        if(((mime_input-mime_top)&MIME_BUF_MASK)==0) break;
        if(c=='=' && d=='?') {
            /* checked. skip header, start decode */
            Fifo(mime_input++) = c;
            mime_input = q; 
            return 1;
        }
        if(!( (c=='+'||c=='/'|| c=='=' || c=='?' ||
            ('a'<=c && c<='z')||('A'<= c && c<='Z')||('0'<=c && c<='9'))))
            break;
        /* Should we check length mod 4? */
        Fifo(mime_input++) = c;
        d=c;
    }
    /* In case of Incomplete MIME, no MIME decode  */
    Fifo(mime_input++) = c;
    mime_last = mime_input;     /* point undecoded buffer */
    mime_mode = 1;              /* no decode on Fifo last in mime_getc */
    return 1;
}
#endif

static int
base64decode(c)
    int c;
{
    int             i;
    if(c > '@')
        if(c < '[')
            i = c - 'A';                        /* A..Z 0-25 */
        else
            i = c - 'G'     /* - 'a' + 26 */ ;  /* a..z 26-51 */
    else if(c > '/')
        i = c - '0' + '4'   /* - '0' + 52 */ ;  /* 0..9 52-61 */
    else if(c == '+')
        i = '>'             /* 62 */ ;          /* +  62 */
    else
        i = '?'             /* 63 */ ;          /* / 63 */
    return (i);
}

static void 
reinit()
{
    unbuf_f = FALSE;
    estab_f = FALSE;
    nop_f = FALSE;
    binmode_f = TRUE;       
    rot_f = FALSE;         
    input_f = FALSE;      
    alpha_f = FALSE;     
    mime_f = TRUE;      
    mimebuf_f = FALSE; 
    broken_f = FALSE;  
    iso8859_f = FALSE; 
    x0201_f = TRUE;    
    x0201_f = NO_X0201; 
    fold_f  = FALSE;
    kanji_intro = DEFAULT_J;
    ascii_intro = DEFAULT_R;
    oconv = DEFAULT_CONV; 
    output_mode = ASCII;
    input_mode =  ASCII;
    shift_mode =  FALSE;
    mime_mode =   FALSE;
    file_out = FALSE;
    add_cr = FALSE;
    del_cr = FALSE;
    line = 0;
}

#ifndef PERL_XS
int 
usage()   
{
    fprintf(stderr,"USAGE:  nkf(nkf32,wnkf,nkf2) -[flags] [in file] .. [out file for -O flag]\n");
    fprintf(stderr,"Flags:\n");
    fprintf(stderr,"b,u      Output is bufferred (DEFAULT),Output is unbufferred\n");
#ifdef DEFAULT_CODE_SJIS
    fprintf(stderr,"j,s,e    Outout code is JIS 7 bit, Shift JIS (DEFAULT), AT&T JIS (EUC)\n");
#endif
#ifdef DEFAULT_CODE_JIS
    fprintf(stderr,"j,s,e    Outout code is JIS 7 bit (DEFAULT), Shift JIS, AT&T JIS (EUC)\n");
#endif
#ifdef DEFAULT_CODE_EUC
    fprintf(stderr,"j,s,e    Outout code is JIS 7 bit, Shift JIS, AT&T JIS (EUC) (DEFAULT)\n");
#endif
    fprintf(stderr,"J,S,E    Input assumption is JIS 7 bit , Shift JIS, AT&T JIS (EUC)\n");
    fprintf(stderr,"t        no conversion\n");
    fprintf(stderr,"i_       Output sequence to designate JIS-kanji (DEFAULT B)\n");
    fprintf(stderr,"o_       Output sequence to designate ASCII (DEFAULT B)\n");
    fprintf(stderr,"r        {de/en}crypt ROT13/47\n");
    fprintf(stderr,"v        Show this usage\n");
    fprintf(stderr,"m[BQ0]   MIME decode [B:base64,Q:quoted,0:no decode]\n");
    fprintf(stderr,"l        ISO8859-1 (Latin-1) support\n");
    fprintf(stderr,"f        Folding: -f60 or -f\n");
    fprintf(stderr,"Z[0-2]   Convert X0208 alphabet to ASCII  1: Kankaku to space,2: 2 spaces\n");
    fprintf(stderr,"X,x      Assume X0201 kana in MS-Kanji, -x preserves X0201\n");
    fprintf(stderr,"B[0-2]   Broken input  0: missing ESC,1: any X on ESC-[($]-X,2: ASCII on NL\n");
#ifdef MSDOS
    fprintf(stderr,"T        Text mode output\n");
#endif
    fprintf(stderr,"O        Output to File (DEFAULT 'nkf.out')\n");
    fprintf(stderr,"d,c      Delete \\r in line feed, Add \\r in line feed\n");
    fprintf(stderr,"Network Kanji Filter Version %s (%s) "
#if defined(MSDOS) && !defined(_Windows)
                  "for DOS"
#endif
#if !defined(__WIN32__) && defined(_Windows)
                  "for Win16"
#endif
#if defined(__WIN32__) && defined(_Windows)
                  "for Win32"
#endif
#ifdef __OS2__
                  "for OS/2"
#endif
                  ,Version,Patchlevel);
    fprintf(stderr,"\n%s\n",CopyRight);
    return 0;
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
 ** 最終更新日
 **  1998.11.7
 **/

/* end */
