/**********************************************************************

  transcode_data.h -

  $Author$
  created at: Mon 10 Dec 2007 14:01:47 JST 2007

  Copyright (C) 2007 Martin Duerst

**********************************************************************/

#include "ruby/ruby.h"

#ifndef RUBY_TRANSCODE_DATA_H
#define RUBY_TRANSCODE_DATA_H 1

typedef unsigned char base_element;

typedef uintptr_t BYTE_LOOKUP[2];

#define BYTE_LOOKUP_BASE(bl) (((uintptr_t *)(bl))[0])
#define BYTE_LOOKUP_INFO(bl) (((uintptr_t *)(bl))[1])

#ifndef PType
/* data file needs to treat this as a pointer, to remove warnings */
#define PType (uintptr_t)
#endif

#define NOMAP	(PType 0x01)	/* single byte direct map */
#define ONEbt	(0x02)		/* one byte payload */
#define TWObt	(0x03)		/* two bytes payload */
#define THREEbt	(0x05)		/* three bytes payload */
#define FOURbt	(0x06)		/* four bytes payload, UTF-8 only, macros start at getBT0 */
#define INVALID	(PType 0x07)	/* invalid byte sequence */
#define UNDEF	(PType 0x09)	/* legal but undefined */
#define ZERObt	(PType 0x0A)	/* zero bytes of payload, i.e. remove */
#define FUNii	(PType 0x0B)	/* function from info to info */
#define FUNsi	(PType 0x0D)	/* function from start to info */
#define FUNio	(PType 0x0E)	/* function from info to output */
#define FUNso	(PType 0x0F)	/* function from start to output */

#define o1(b1)		(PType((((unsigned char)(b1))<<8)|ONEbt))
#define o2(b1,b2)	(PType((((unsigned char)(b1))<<8)|(((unsigned char)(b2))<<16)|TWObt))
#define o3(b1,b2,b3)	(PType((((unsigned char)(b1))<<8)|(((unsigned char)(b2))<<16)|(((unsigned char)(b3))<<24)|THREEbt))
#define o4(b0,b1,b2,b3)	(PType((((unsigned char)(b1))<< 8)|(((unsigned char)(b2))<<16)|(((unsigned char)(b3))<<24)|((((unsigned char)(b0))&0x07)<<5)|FOURbt))

#define getBT1(a)	(((a)>> 8)&0xFF)
#define getBT2(a)	(((a)>>16)&0xFF)
#define getBT3(a)	(((a)>>24)&0xFF)
#define getBT0(a)	((((a)>> 5)&0x07)|0xF0)   /* for UTF-8 only!!! */

#define o2FUNii(b1,b2)	(PType((((unsigned char)(b1))<<8)|(((unsigned char)(b2))<<16)|FUNii))

/* do we need these??? maybe not, can be done with simple tables */
#define ONETRAIL       /* legal but undefined if one more trailing UTF-8 */
#define TWOTRAIL       /* legal but undefined if two more trailing UTF-8 */
#define THREETRAIL     /* legal but undefined if three more trailing UTF-8 */

typedef enum {
  stateless_converter,  /* stateless -> stateless */
  stateful_decoder,     /* stateful -> stateless */
  stateful_encoder      /* stateless -> stateful */
  /* stateful -> stateful is intentionally ommitted. */
} rb_transcoder_stateful_type_t;

typedef struct rb_transcoder rb_transcoder;

/* dynamic structure, one per conversion (similar to iconv_t) */
/* may carry conversion state (e.g. for iso-2022-jp) */
typedef struct rb_transcoding {
    const rb_transcoder *transcoder;

    int flags;

    int resume_position;
    uintptr_t next_table;
    VALUE next_info;
    unsigned char next_byte;

    int recognized_len; /* already interpreted */
    int readagain_len; /* not yet interpreted */
    union {
        unsigned char ary[8]; /* max_input <= sizeof(ary) */
        unsigned char *ptr; /* length: max_input */
    } readbuf; /* recognized_len + readagain_len used */

    int writebuf_off;
    int writebuf_len;
    union {
        unsigned char ary[8]; /* max_output <= sizeof(ary) */
        unsigned char *ptr; /* length: max_output */
    } writebuf;

    unsigned char stateful[256]; /* opaque data for stateful encoding */
} rb_transcoding;
#define TRANSCODING_READBUF(tc) \
    ((tc)->transcoder->max_input <= sizeof((tc)->readbuf.ary) ? \
     (tc)->readbuf.ary : \
     (tc)->readbuf.ptr)
#define TRANSCODING_WRITEBUF(tc) \
    ((tc)->transcoder->max_output <= sizeof((tc)->writebuf.ary) ? \
     (tc)->writebuf.ary : \
     (tc)->writebuf.ptr)

/* static structure, one per supported encoding pair */
struct rb_transcoder {
    const char *from_encoding;
    const char *to_encoding;
    uintptr_t conv_tree_start;
    const unsigned char *byte_array;
    const uintptr_t *word_array;
    int word_size;
    int input_unit_length;
    int max_input;
    int max_output;
    rb_transcoder_stateful_type_t stateful_type;
    VALUE (*func_ii)(rb_transcoding*, VALUE); /* info  -> info   */
    VALUE (*func_si)(rb_transcoding*, const unsigned char*, size_t); /* start -> info   */
    int (*func_io)(rb_transcoding*, VALUE, const unsigned char*); /* info  -> output */
    int (*func_so)(rb_transcoding*, const unsigned char*, size_t, unsigned char*); /* start -> output */
    int (*finish_func)(rb_transcoding*, unsigned char*); /* -> output */
    int (*resetsize_func)(rb_transcoding*); /* -> len */
    int (*resetstate_func)(rb_transcoding*, unsigned char*); /* -> output */
};

void rb_declare_transcoder(const char *enc1, const char *enc2, const char *lib);
void rb_register_transcoder(const rb_transcoder *);

#endif /* RUBY_TRANSCODE_DATA_H */
