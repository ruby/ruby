/**********************************************************************

  transcode_data.h -

  $Author$
  created at: Mon 10 Dec 2007 14:01:47 JST 2007

  Copyright (C) 2007 Martin Duerst

**********************************************************************/

#include "ruby/ruby.h"

#ifndef RUBY_TRANSCODE_DATA_H
#define RUBY_TRANSCODE_DATA_H 1

#define WORDINDEX_SHIFT_BITS 2
#define WORDINDEX2INFO(widx)      ((widx) << WORDINDEX_SHIFT_BITS)
#define INFO2WORDINDEX(info)      ((info) >> WORDINDEX_SHIFT_BITS)
#define BYTE_LOOKUP_BASE(bl) ((bl)[0])
#define BYTE_LOOKUP_INFO(bl) ((bl)[1])

#ifndef PType
/* data file needs to treat this as a pointer, to remove warnings */
#define PType (unsigned int)
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
#define o3(b1,b2,b3)	(PType(((((unsigned char)(b1))<<8)|(((unsigned char)(b2))<<16)|(((unsigned char)(b3))<<24)|THREEbt)&0xffffffffU))
#define o4(b0,b1,b2,b3)	(PType(((((unsigned char)(b1))<< 8)|(((unsigned char)(b2))<<16)|(((unsigned char)(b3))<<24)|((((unsigned char)(b0))&0x07)<<5)|FOURbt)&0xffffffffU))

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

/* static structure, one per supported encoding pair */
struct rb_transcoder {
    const char *from_encoding;
    const char *to_encoding;
    unsigned int conv_tree_start;
    const unsigned char *byte_array;
    unsigned int byte_array_length;
    const unsigned int *word_array;
    unsigned int word_array_length;
    int word_size;
    int input_unit_length;
    int max_input;
    int max_output;
    rb_transcoder_stateful_type_t stateful_type;
    size_t state_size;
    int (*state_init_func)(void*); /* 0:success !=0:failure(errno) */
    int (*state_fini_func)(void*); /* 0:success !=0:failure(errno) */
    VALUE (*func_ii)(void*, VALUE); /* info  -> info   */
    VALUE (*func_si)(void*, const unsigned char*, size_t); /* start -> info   */
    int (*func_io)(void*, VALUE, const unsigned char*); /* info  -> output */
    int (*func_so)(void*, const unsigned char*, size_t, unsigned char*); /* start -> output */
    int (*finish_func)(void*, unsigned char*); /* -> output */
    int (*resetsize_func)(void*); /* -> len */
    int (*resetstate_func)(void*, unsigned char*); /* -> output */
};

void rb_declare_transcoder(const char *enc1, const char *enc2, const char *lib);
void rb_register_transcoder(const rb_transcoder *);

#endif /* RUBY_TRANSCODE_DATA_H */
