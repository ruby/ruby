/**********************************************************************

  m17n.h -

  $Author$
  $Date$
  created at: Thu Dec 28 16:19:43 JST 2000

  Copyright (C) 1993-2001 Yukihiro Matsumoto

**********************************************************************/

#ifndef M17N_H
#define M17N_H

#ifndef _
#ifdef HAVE_PROTOTYPES
# define _(args) args
#else
# define _(args) ()
#endif
#ifdef HAVE_STDARG_PROTOTYPES
# define __(args) args
#else
# define __(args) ()
#endif
#endif

void m17n_init _((void));

typedef struct m17n_encoding {
    const char *name;
    int index;

    int mbmaxlen;

    int (*strlen) _((const unsigned char *p, const unsigned char *e, const struct m17n_encoding* enc));
    int (*mbclen) _((int c, const struct m17n_encoding* enc));
    int (*codelen) _((unsigned int c, const struct m17n_encoding* enc));
    int (*mbcspan) _((const unsigned char *p, const unsigned char *e, const struct m17n_encoding* enc));
    int (*islead) _((int c, struct m17n_encoding* enc));
    unsigned char *(*nth) _((unsigned char *p, const unsigned char *e, int n, const struct m17n_encoding* enc));
    int (*ctype) _((const unsigned int c, const unsigned int code, const struct m17n_encoding* enc));
    unsigned int (*toupper) _((unsigned int c, const struct m17n_encoding* enc));
    unsigned int (*tolower) _((unsigned int c, const struct m17n_encoding* enc));
    unsigned int (*codepoint) _((const unsigned char *p, const unsigned char *e, const struct m17n_encoding* enc));
    int (*firstbyte) _((unsigned int c, const struct m17n_encoding* enc));
    void (*mbcput) _((unsigned int c, unsigned char *p, const struct m17n_encoding* enc));
} m17n_encoding;

extern m17n_encoding **m17n_encoding_table;

m17n_encoding *m17n_define_encoding _((const char *name));

#define m17n_encoding_to_index(enc) (enc)->index
#define m17n_index_to_encoding(index) m17n_encoding_table[index]
m17n_encoding *m17n_find_encoding _((const char *name));

#define m17n_encoding_mbmaxlen(enc,n) (enc)->mbmaxlen = (n)
#define m17n_encoding_func_strlen(enc,func) (enc)->strlen = (func)
#define m17n_encoding_func_mbclen(enc,func) (enc)->mbclen = (func)
#define m17n_encoding_func_codelen(enc,func) (enc)->codelen = (func)
#define m17n_encoding_func_mbcspan(enc,func) (enc)->mbcspan = (func)
#define m17n_encoding_func_islead(enc,func) (enc)->islead = (func)
#define m17n_encoding_func_nth(enc,func) (enc)->nth = (func)
#define m17n_encoding_func_ctype(enc,func) (enc)->ctype = (func)
#define m17n_encoding_func_toupper(enc,func) (enc)->toupper = (func)
#define m17n_encoding_func_tolower(enc,func) (enc)->tolower = (func)
#define m17n_encoding_func_codepoint(enc,func) (enc)->codepoint = (func)
#define m17n_encoding_func_firstbyte(enc,func) (enc)->firstbyte = (func)
#define m17n_encoding_func_mbcput(enc,func) (enc)->mbcput = (func)

#define m17n_mbmaxlen(enc) (enc)->mbmaxlen
#define m17n_strlen(enc,p,e) (*(enc)->strlen)((p),(e),(enc))
#define m17n_mbclen(enc,c) (*(enc)->mbclen)((c)&0xff,(enc))
#define m17n_codelen(enc,c) (*(enc)->codelen)((c),(enc))
#define m17n_mbcspan(enc,p,e) (*(enc)->mbcspan)((p),(e),(enc))
#define m17n_islead(enc,c) (*(enc)->islead)((c)&0xff,(enc))
#define m17n_nth(enc,p,e,n) (*(enc)->nth)((p),(e),(n),(enc))
#define m17n_codepoint(enc,p,e) (*(enc)->codepoint)((p),(e),(enc))
#define m17n_firstbyte(enc,c) (*(enc)->firstbyte)((c),(enc))
#define m17n_mbcput(enc,c,p) (*(enc)->mbcput)((c),(p),(enc))

#define M17N_U      01      /* Upper case */
#define M17N_L      02      /* Lower case */
#define M17N_N      04      /* Numeral (digit) */
#define M17N_S      010     /* Spacing character */
#define M17N_P      020     /* Punctuation */
#define M17N_C      040     /* Control character */
#define M17N_B      0100    /* Blank */
#define M17N_X      0200    /* heXadecimal digit */

#define m17n_isprint(enc,c) (*(enc)->ctype)((c),(M17N_P|M17N_U|M17N_L|M17N_N|M17N_B),(enc))
#define m17n_isspace(enc,c) (*(enc)->ctype)((c),(M17N_S),(enc))
#define m17n_isblank(enc,c) (*(enc)->ctype)((c),(M17N_B),(enc))
#define m17n_ispunct(enc,c) (*(enc)->ctype)((c),(M17N_P),(enc))
#define m17n_isupper(enc,c) (*(enc)->ctype)((c),(M17N_U),(enc))
#define m17n_islower(enc,c) (*(enc)->ctype)((c),(M17N_L),(enc))
#define m17n_isalnum(enc,c) (*(enc)->ctype)((c),(M17N_U|M17N_L|M17N_N),(enc))
#define m17n_isalpha(enc,c) (*(enc)->ctype)((c),(M17N_U|M17N_L),(enc))
#define m17n_isdigit(enc,c) (*(enc)->ctype)((c),(M17N_N),(enc))
#define m17n_isxdigit(enc,c) (*(enc)->ctype)((c),(M17N_X),(enc))
#define m17n_iscntrl(enc,c) (*(enc)->ctype)((c),(M17N_C),(enc))
#define m17n_toupper(enc,c) (*(enc)->toupper)((c),(enc))
#define m17n_tolower(enc,c) (*(enc)->tolower)((c),(enc))

int m17n_memcmp _((const char *p1, const char *p2, long len, const m17n_encoding *enc));

#endif /* M17N_H */
