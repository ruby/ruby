/**********************************************************************

  transcode.c -

  $Author: duerst $
  $Date: 2007-10-30 16:10:22 +0900 (Tue, 30 Oct 2007) $
  created at: Tue Oct 30 16:10:22 JST 2007

  Copyright (C) 2007 Martin Duerst

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"

#include "transcode_data.h"


/*
 * prototypes and macros copied from string.c (temporarily !!!)
 */
VALUE str_new(VALUE klass, const char *ptr, long len);
int str_independent(VALUE str);
#define STR_NOCAPA_P(s) (FL_TEST(s,STR_NOEMBED) && FL_ANY(s,ELTS_SHARED|STR_ASSOC))
#define STR_NOEMBED FL_USER1
#define STR_ASSOC   FL_USER3
#define STR_SET_NOEMBED(str) do {\
    FL_SET(str, STR_NOEMBED);\
    STR_SET_EMBED_LEN(str, 0);\
} while (0)
#define STR_UNSET_NOCAPA(s) do {\
    if (FL_TEST(s,STR_NOEMBED)) FL_UNSET(s,(ELTS_SHARED|STR_ASSOC));\
} while (0)
#define STR_SET_EMBED_LEN(str, n) do { \
    long tmp_n = (n);\
    RBASIC(str)->flags &= ~RSTRING_EMBED_LEN_MASK;\
    RBASIC(str)->flags |= (tmp_n) << RSTRING_EMBED_LEN_SHIFT;\
} while (0)
#define STR_SET_LEN(str, n) do { \
    if (STR_EMBED_P(str)) {\
	STR_SET_EMBED_LEN(str, n);\
    }\
    else {\
	RSTRING(str)->as.heap.len = (n);\
    }\
} while (0) 
#define STR_EMBED_P(str) (!FL_TEST(str, STR_NOEMBED))
#define RESIZE_CAPA(str,capacity) do {\
    if (STR_EMBED_P(str)) {\
	if ((capacity) > RSTRING_EMBED_LEN_MAX) {\
	    char *tmp = ALLOC_N(char, capacity+1);\
	    memcpy(tmp, RSTRING_PTR(str), RSTRING_LEN(str));\
	    RSTRING(str)->as.heap.ptr = tmp;\
	    RSTRING(str)->as.heap.len = RSTRING_LEN(str);\
            STR_SET_NOEMBED(str);\
	    RSTRING(str)->as.heap.aux.capa = (capacity);\
	}\
    }\
    else {\
	REALLOC_N(RSTRING(str)->as.heap.ptr, char, (capacity)+1);\
	if (!STR_NOCAPA_P(str))\
	    RSTRING(str)->as.heap.aux.capa = (capacity);\
    }\
} while (0)
/* end of copied prototypes and macros */



/*
 *  Dispatch data and logic
 */

/* extern declarations, should use some include file here */
extern const BYTE_LOOKUP from_ISO_8859_1;
extern const BYTE_LOOKUP from_ISO_8859_2;
extern const BYTE_LOOKUP from_ISO_8859_3;
extern const BYTE_LOOKUP from_ISO_8859_4;
extern const BYTE_LOOKUP from_ISO_8859_5;
extern const BYTE_LOOKUP from_ISO_8859_6;
extern const BYTE_LOOKUP from_ISO_8859_7;
extern const BYTE_LOOKUP from_ISO_8859_8;
extern const BYTE_LOOKUP from_ISO_8859_9;
extern const BYTE_LOOKUP from_ISO_8859_10;
extern const BYTE_LOOKUP from_ISO_8859_11;
extern const BYTE_LOOKUP from_ISO_8859_13;
extern const BYTE_LOOKUP from_ISO_8859_14;
extern const BYTE_LOOKUP from_ISO_8859_15;

extern const BYTE_LOOKUP to_ISO_8859_1;
extern const BYTE_LOOKUP to_ISO_8859_2;
extern const BYTE_LOOKUP to_ISO_8859_3;
extern const BYTE_LOOKUP to_ISO_8859_4;
extern const BYTE_LOOKUP to_ISO_8859_5;
extern const BYTE_LOOKUP to_ISO_8859_6;
extern const BYTE_LOOKUP to_ISO_8859_7;
extern const BYTE_LOOKUP to_ISO_8859_8;
extern const BYTE_LOOKUP to_ISO_8859_9;
extern const BYTE_LOOKUP to_ISO_8859_10;
extern const BYTE_LOOKUP to_ISO_8859_11;
extern const BYTE_LOOKUP to_ISO_8859_13;
extern const BYTE_LOOKUP to_ISO_8859_14;
extern const BYTE_LOOKUP to_ISO_8859_15;


/* declarations probably need to go into separate header file, e.g. transcode.h */

/* static structure, one per supported encoding pair */
typedef struct {
    const char *from_encoding;
    const char *to_encoding;
    BYTE_LOOKUP *conv_tree_start;
    int max_output;
    int from_utf8;
} transcoder;

/* todo: dynamic structure, one per conversion (stream) */

/* in the future, add some mechanism for dynamically adding stuff here */
#define MAX_TRANSCODERS 29  /* todo: fix: this number has to be adjusted by hand */
static transcoder transcoder_table[MAX_TRANSCODERS];

/* not sure why it's not possible to do relocatable initializations */
/* maybe the code here can be removed (changed to simple initialization) */
/* if we move this to another file???? */
static void
register_transcoder (const char *from_e, const char *to_e,
    const BYTE_LOOKUP *tree_start, int max_output, int from_utf8)
{
    static int n = 0;
    if (n >= MAX_TRANSCODERS) {
        /* we are initializing, is it okay to use rb_raise here? */
        rb_raise(rb_eRuntimeError /*change exception*/, "not enough transcoder slots");
    }
    transcoder_table[n].from_encoding = from_e;
    transcoder_table[n].to_encoding = to_e;
    transcoder_table[n].conv_tree_start = (BYTE_LOOKUP *)tree_start;
    transcoder_table[n].max_output = max_output;
    transcoder_table[n].from_utf8 = from_utf8;

    n++;
}

static void
init_transcoder_table (void)
{
    register_transcoder("ISO-8859-1",  "UTF-8", &from_ISO_8859_1, 2, 0);
    register_transcoder("ISO-8859-2",  "UTF-8", &from_ISO_8859_2, 2, 0);
    register_transcoder("ISO-8859-3",  "UTF-8", &from_ISO_8859_3, 2, 0);
    register_transcoder("ISO-8859-4",  "UTF-8", &from_ISO_8859_4, 2, 0);
    register_transcoder("ISO-8859-5",  "UTF-8", &from_ISO_8859_5, 3, 0);
    register_transcoder("ISO-8859-6",  "UTF-8", &from_ISO_8859_6, 2, 0);
    register_transcoder("ISO-8859-7",  "UTF-8", &from_ISO_8859_7, 3, 0);
    register_transcoder("ISO-8859-8",  "UTF-8", &from_ISO_8859_8, 3, 0);
    register_transcoder("ISO-8859-9",  "UTF-8", &from_ISO_8859_9, 2, 0);
    register_transcoder("ISO-8859-10", "UTF-8", &from_ISO_8859_10, 3, 0);
    register_transcoder("ISO-8859-11", "UTF-8", &from_ISO_8859_11, 3, 0);
    register_transcoder("ISO-8859-13", "UTF-8", &from_ISO_8859_13, 3, 0);
    register_transcoder("ISO-8859-14", "UTF-8", &from_ISO_8859_14, 3, 0);
    register_transcoder("ISO-8859-15", "UTF-8", &from_ISO_8859_15, 3, 0);
    register_transcoder("UTF-8", "ISO-8859-1",  &to_ISO_8859_1, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-2",  &to_ISO_8859_2, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-3",  &to_ISO_8859_3, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-4",  &to_ISO_8859_4, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-5",  &to_ISO_8859_5, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-6",  &to_ISO_8859_6, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-7",  &to_ISO_8859_7, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-8",  &to_ISO_8859_8, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-9",  &to_ISO_8859_9, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-10", &to_ISO_8859_10, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-11", &to_ISO_8859_11, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-13", &to_ISO_8859_13, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-14", &to_ISO_8859_14, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-15", &to_ISO_8859_15, 1, 1);
    register_transcoder(NULL, NULL, NULL, 0, 0);
}


static transcoder*
transcode_dispatch (char* from_encoding, char* to_encoding)
{
    transcoder *candidate = transcoder_table;
    
    for (candidate = transcoder_table; candidate->from_encoding; candidate++)
        if (0==strcasecmp(from_encoding, candidate->from_encoding)
            && 0==strcasecmp(to_encoding, candidate->to_encoding))
                break;
    /* in the future, add multistep transcoding logic here */
    return candidate->from_encoding ? candidate : NULL;
}

/* dynamic structure, one per conversion (similar to iconv_t) */
/* may carry conversion state (e.g. for iso-2022-jp) */
typedef struct {
    VALUE ruby_string_dest; /* the String used as the conversion destination,
                               or NULL if something else is being converted */
} transcoding;


/*
 *  Transcoding engine logic
 */
static void
transcode_loop (unsigned char **in_pos, unsigned char **out_pos,
                unsigned char *in_stop, unsigned char *out_stop,
                transcoder *my_transcoder,
                transcoding *my_transcoding)
{
    unsigned char *input = *in_pos, *output = *out_pos;
    unsigned char *in_p = *in_pos, *out_p = *out_pos;
    BYTE_LOOKUP *conv_tree_start = my_transcoder->conv_tree_start;
    BYTE_LOOKUP *next_table;
    unsigned int next_offset;
    unsigned int next_info;
    unsigned char next_byte;
    int from_utf8 = my_transcoder->from_utf8;
    unsigned char *out_s = out_stop - my_transcoder->max_output + 1;
    while (in_p < in_stop) {
        unsigned char *char_start = in_p;
        next_table = conv_tree_start;
        if (out_p >= out_s) {
            VALUE dest_string = my_transcoding->ruby_string_dest;
            if (!dest_string) {
	        rb_raise(rb_eArgError /*@@@change exception*/, "Unable to obtain more space for transcoding");
	    }
	    else {
	        int len = (out_p - *out_pos);
	        int new_len = (len + my_transcoder->max_output) * 2;
		RESIZE_CAPA(dest_string, new_len);
		STR_SET_LEN(dest_string, new_len);
		*out_pos = RSTRING_PTR(dest_string);
		out_p = *out_pos + len;
		out_s = *out_pos + new_len - my_transcoder->max_output;
	    }
        }
        next_byte = *in_p++;
      follow_byte:
        next_offset = next_table->base[next_byte];
        next_info = (unsigned int)next_table->info[next_offset];
        switch (next_info & 0x1F) {
            case NOMAP:
                *out_p++ = next_byte;
                continue;
            case 0x00: case 0x04: case 0x08: case 0x0C:
            case 0x10: case 0x14: case 0x18: case 0x1C:
                if (in_p >= in_stop) {
                    /* todo: deal with the case of backtracking */
                    /* todo: deal with incomplete input (streaming) */
                    goto illegal;
                }
                next_byte = *in_p++;
                if (from_utf8) {
                    if ((next_byte&0xC0) == 0x80)
                        next_byte -= 0x80;
                    else
                        goto illegal;
                }
                next_table = (BYTE_LOOKUP*)next_info;
                goto follow_byte;
            /* maybe rewrite the following cases to use fallthrough???? */
            case ZERObt: /* drop input */
                continue;
            case ONEbt:
                *out_p++ = getBT1(next_info);
                continue;
            case TWObt:
                *out_p++ = getBT1(next_info);
                *out_p++ = getBT2(next_info);
                continue;
            case FOURbt:
                *out_p++ = getBT0(next_info);
            case THREEbt: /* fall through */
                *out_p++ = getBT1(next_info);
                *out_p++ = getBT2(next_info);
                *out_p++ = getBT3(next_info);
                continue;
            case ILLEGAL:
                goto illegal;
            case UNDEF:
                /* todo: add code for alternative behaviors */
                rb_raise(rb_eRuntimeError /*@@@change exception*/, "conversion undefined for byte sequence");
                continue;
        }
        continue;
      illegal:
        /* deal with illegal byte sequence */
        /* todo: add code for alternative behaviors */
        rb_raise(rb_eRuntimeError /*change exception*/, "illegal byte sequence");
        continue;
    }
    /* cleanup */
    *in_pos  = in_p;
    *out_pos = out_p;
}


/*
 *  String-specific code
 */

static VALUE
str_transcode(int argc, VALUE *argv, VALUE str, int bang)
{
    VALUE dest;
    long blen, slen, len;
    char *buf, *bp, *sp, *fromp;
    int tainted = 0;
    rb_encoding *from_enc, *to_enc;
    char *from_e, *to_e;
    transcoder *my_transcoder;
    int idx;
    transcoding my_transcoding;

    if (argc<1 || argc>2) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 2)", argc);
    }
    to_enc = NULL; /* todo: work out later, 'to' parameter may be Encoding,
                      or we want an encoding to set on result */
    to_e = RSTRING_PTR(StringValue(argv[0]));
    if (argc==1) {
        from_enc = rb_enc_get(str);
        from_e = (char *)rb_enc_name(from_enc);
    }
    else {
        from_enc = NULL; /* todo: work out later, 'from' parameter may be Encoding */
        from_e = RSTRING_PTR(StringValue(argv[1]));
    }

    /* strcasecmp: hope we are in C locale or locale-insensitive */
    if (0==strcasecmp(from_e, to_e)) { /* TODO: add tests for US-ASCII-clean data and ASCII-compatible encodings */
	if (bang) return str;
	return rb_str_dup(str);
    }
    if (!(my_transcoder = transcode_dispatch(from_e, to_e))) {
	rb_raise(rb_eArgError, "transcoding not supported (from %s to %s)", from_e, to_e);
    }

    fromp = sp = RSTRING_PTR(str);
    slen = RSTRING_LEN(str);
    blen = slen + 30; /* len + margin */
    dest = str_new(0, 0, blen);
    bp = buf = RSTRING_PTR(dest);
    my_transcoding.ruby_string_dest = dest;

    rb_str_locktmp(dest);
    
    /* for simple testing: */
    transcode_loop((unsigned char **)&fromp, (unsigned char **)&bp,
                   (unsigned char*)(sp+slen), (unsigned char*)(bp+blen),
                   my_transcoder, &my_transcoding);
    if (fromp != sp+slen) {
	rb_raise(rb_eArgError, "not fully converted, %d bytes left", sp+slen-fromp);
    }
    buf = RSTRING_PTR(dest);
    blen = RSTRING_LEN(dest);
    *bp = '\0';
    rb_str_unlocktmp(dest);
    if (bang) {
	if (str_independent(str) && !STR_EMBED_P(str)) {
	    free(RSTRING_PTR(str));
	}
	STR_SET_NOEMBED(str);
	STR_UNSET_NOCAPA(str);
	RSTRING(str)->as.heap.ptr = buf;
	RSTRING(str)->as.heap.aux.capa = blen;
	RSTRING(dest)->as.heap.ptr = 0;
	RSTRING(dest)->as.heap.len = 0;
    }
    else {
	RBASIC(dest)->klass = rb_obj_class(str);
	OBJ_INFECT(dest, str);
	str = dest;
    }
    STR_SET_LEN(str, bp - buf);

    /* set encoding */ /* would like to have an easier way to do this */
    if ((idx = rb_enc_find_index(to_e)) < 0) {
        if ((idx = rb_enc_find_index("ASCII-8BIT")) < 0) {
	    rb_raise(rb_eArgError, "unknown encoding name: ASCII-8BIT");
	}
    }
    rb_enc_associate(str, rb_enc_from_index(idx));

    if (tainted) OBJ_TAINT(str); /* is this needed??? */
    return str;
}

/*
 *  call-seq:
 *     str.encode!(encoding)   => str
 *     str.encode!(to_encoding, from_encoding)   => str
 *
 *  With one argument, transcodes the contents of <i>str</i> from
 *  str.encoding to +encoding+.
 *  With two arguments, transcodes the contents of <i>str</i> from
 *  from_encoding to to_encoding.
 *  Returns the string even if no changes were made.
 */

static VALUE
rb_str_transcode_bang(int argc, VALUE *argv, VALUE str)
{
    return str_transcode(argc, argv, str, 1);
}

/*
 *  call-seq:
 *     str.encode(encoding)   => str
 *
 *  With one argument, returns a copy of <i>str</i> transcoded
 *  to encoding +encoding+.
 *  With two arguments, returns a copy of <i>str</i> transcoded
 *  from from_encoding to to_encoding.
 */

static VALUE
rb_str_transcode(int argc, VALUE *argv, VALUE str)
{
    return str_transcode(argc, argv, str, 0);
}

/* function to fool the optimizer (avoid inlining transcode_loop) */
void
transcode_fool_the_optimizer (void)
{
    unsigned char **in_pos, **out_pos, *in_stop, *out_stop;
    transcoder *my_transcoder;
    transcoding *my_transcoding;
    transcode_loop(in_pos, out_pos, in_stop, out_stop,
                   my_transcoder, my_transcoding);
}

void
Init_transcode(void)
{
    init_transcoder_table();
    rb_define_method(rb_cString, "encode", rb_str_transcode, -1);
    rb_define_method(rb_cString, "encode!", rb_str_transcode_bang, -1);
}
