/**********************************************************************

  transcode.c -

  $Author$
  $Date$
  created at: Tue Oct 30 16:10:22 JST 2007

  Copyright (C) 2007 Martin Duerst

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"

#include "transcode_data.h"


VALUE rb_str_tmp_new(long);
VALUE rb_str_shared_replace(VALUE, VALUE);

/*
 *  Dispatch data and logic
 */

/* extern declarations, should use some include file here */
extern const BYTE_LOOKUP rb_from_ISO_8859_1;
extern const BYTE_LOOKUP rb_from_ISO_8859_2;
extern const BYTE_LOOKUP rb_from_ISO_8859_3;
extern const BYTE_LOOKUP rb_from_ISO_8859_4;
extern const BYTE_LOOKUP rb_from_ISO_8859_5;
extern const BYTE_LOOKUP rb_from_ISO_8859_6;
extern const BYTE_LOOKUP rb_from_ISO_8859_7;
extern const BYTE_LOOKUP rb_from_ISO_8859_8;
extern const BYTE_LOOKUP rb_from_ISO_8859_9;
extern const BYTE_LOOKUP rb_from_ISO_8859_10;
extern const BYTE_LOOKUP rb_from_ISO_8859_11;
extern const BYTE_LOOKUP rb_from_ISO_8859_13;
extern const BYTE_LOOKUP rb_from_ISO_8859_14;
extern const BYTE_LOOKUP rb_from_ISO_8859_15;

extern const BYTE_LOOKUP rb_to_ISO_8859_1;
extern const BYTE_LOOKUP rb_to_ISO_8859_2;
extern const BYTE_LOOKUP rb_to_ISO_8859_3;
extern const BYTE_LOOKUP rb_to_ISO_8859_4;
extern const BYTE_LOOKUP rb_to_ISO_8859_5;
extern const BYTE_LOOKUP rb_to_ISO_8859_6;
extern const BYTE_LOOKUP rb_to_ISO_8859_7;
extern const BYTE_LOOKUP rb_to_ISO_8859_8;
extern const BYTE_LOOKUP rb_to_ISO_8859_9;
extern const BYTE_LOOKUP rb_to_ISO_8859_10;
extern const BYTE_LOOKUP rb_to_ISO_8859_11;
extern const BYTE_LOOKUP rb_to_ISO_8859_13;
extern const BYTE_LOOKUP rb_to_ISO_8859_14;
extern const BYTE_LOOKUP rb_to_ISO_8859_15;

extern const BYTE_LOOKUP rb_from_SHIFT_JIS;
extern const BYTE_LOOKUP rb_from_EUC_JP;

extern const BYTE_LOOKUP rb_to_SHIFT_JIS;
extern const BYTE_LOOKUP rb_to_EUC_JP;


/* declarations probably need to go into separate header file, e.g. transcode.h */

/* static structure, one per supported encoding pair */
typedef struct {
    const char *from_encoding;
    const char *to_encoding;
    const BYTE_LOOKUP *conv_tree_start;
    int max_output;
    int from_utf8;
} transcoder;

/* todo: dynamic structure, one per conversion (stream) */

/* in the future, add some mechanism for dynamically adding stuff here */
#define MAX_TRANSCODERS 33  /* todo: fix: this number has to be adjusted by hand */
static transcoder transcoder_table[MAX_TRANSCODERS];

/* not sure why it's not possible to do relocatable initializations */
/* maybe the code here can be removed (changed to simple initialization) */
/* if we move this to another file???? */
static void
register_transcoder(const char *from_e, const char *to_e,
    const BYTE_LOOKUP *tree_start, int max_output, int from_utf8)
{
    static int n = 0;
    if (n >= MAX_TRANSCODERS) {
	/* we are initializing, is it okay to use rb_raise here? */
	rb_raise(rb_eRuntimeError /*change exception*/, "not enough transcoder slots");
    }
    transcoder_table[n].from_encoding = from_e;
    transcoder_table[n].to_encoding = to_e;
    transcoder_table[n].conv_tree_start = tree_start;
    transcoder_table[n].max_output = max_output;
    transcoder_table[n].from_utf8 = from_utf8;

    n++;
}

static void
init_transcoder_table(void)
{
    register_transcoder("ISO-8859-1",  "UTF-8", &rb_from_ISO_8859_1, 2, 0);
    register_transcoder("ISO-8859-2",  "UTF-8", &rb_from_ISO_8859_2, 2, 0);
    register_transcoder("ISO-8859-3",  "UTF-8", &rb_from_ISO_8859_3, 2, 0);
    register_transcoder("ISO-8859-4",  "UTF-8", &rb_from_ISO_8859_4, 2, 0);
    register_transcoder("ISO-8859-5",  "UTF-8", &rb_from_ISO_8859_5, 3, 0);
    register_transcoder("ISO-8859-6",  "UTF-8", &rb_from_ISO_8859_6, 2, 0);
    register_transcoder("ISO-8859-7",  "UTF-8", &rb_from_ISO_8859_7, 3, 0);
    register_transcoder("ISO-8859-8",  "UTF-8", &rb_from_ISO_8859_8, 3, 0);
    register_transcoder("ISO-8859-9",  "UTF-8", &rb_from_ISO_8859_9, 2, 0);
    register_transcoder("ISO-8859-10", "UTF-8", &rb_from_ISO_8859_10, 3, 0);
    register_transcoder("ISO-8859-11", "UTF-8", &rb_from_ISO_8859_11, 3, 0);
    register_transcoder("ISO-8859-13", "UTF-8", &rb_from_ISO_8859_13, 3, 0);
    register_transcoder("ISO-8859-14", "UTF-8", &rb_from_ISO_8859_14, 3, 0);
    register_transcoder("ISO-8859-15", "UTF-8", &rb_from_ISO_8859_15, 3, 0);
    register_transcoder("UTF-8", "ISO-8859-1",  &rb_to_ISO_8859_1, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-2",  &rb_to_ISO_8859_2, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-3",  &rb_to_ISO_8859_3, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-4",  &rb_to_ISO_8859_4, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-5",  &rb_to_ISO_8859_5, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-6",  &rb_to_ISO_8859_6, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-7",  &rb_to_ISO_8859_7, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-8",  &rb_to_ISO_8859_8, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-9",  &rb_to_ISO_8859_9, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-10", &rb_to_ISO_8859_10, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-11", &rb_to_ISO_8859_11, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-13", &rb_to_ISO_8859_13, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-14", &rb_to_ISO_8859_14, 1, 1);
    register_transcoder("UTF-8", "ISO-8859-15", &rb_to_ISO_8859_15, 1, 1);

    register_transcoder("SHIFT_JIS", "UTF-8",   &rb_from_SHIFT_JIS, 3, 0);
    register_transcoder("EUC-JP", "UTF-8",      &rb_from_EUC_JP, 3, 0);
    register_transcoder("UTF-8", "SHIFT_JIS",   &rb_to_SHIFT_JIS, 2, 1);
    register_transcoder("UTF-8", "EUC-JP",      &rb_to_EUC_JP, 2, 1);

    register_transcoder(NULL, NULL, NULL, 0, 0);
}

static int
encoding_equal(const char* encoding1, const char* encoding2)
{
    return 0==strcasecmp(encoding1, encoding2);
}

static transcoder*
transcode_dispatch(const char* from_encoding, const char* to_encoding)
{
    transcoder *candidate = transcoder_table;
    
    for (candidate = transcoder_table; candidate->from_encoding; candidate++) {
	if (encoding_equal(from_encoding, candidate->from_encoding)
	    && encoding_equal(to_encoding, candidate->to_encoding)) {
		return candidate;
	}
    }
    /* multistep logic, via UTF-8 */
    if (!encoding_equal(from_encoding, "UTF-8")
	&& !encoding_equal(to_encoding, "UTF-8")
	&& transcode_dispatch("UTF-8", to_encoding)) {  /* check that we have a second step */
	    return transcode_dispatch(from_encoding, "UTF-8"); /* return first step */
    }
    return NULL;
}

/* dynamic structure, one per conversion (similar to iconv_t) */
/* may carry conversion state (e.g. for iso-2022-jp) */
typedef struct transcoding {
    VALUE ruby_string_dest; /* the String used as the conversion destination,
			       or NULL if something else is being converted */
    char *(*flush_func)(struct transcoding*, int, int);
} transcoding;


/*
 *  Transcoding engine logic
 */
static void
transcode_loop(char **in_pos, char **out_pos,
	       char *in_stop, char *out_stop,
	       transcoder *my_transcoder,
	       transcoding *my_transcoding)
{
    char *in_p = *in_pos, *out_p = *out_pos;
    const BYTE_LOOKUP *conv_tree_start = my_transcoder->conv_tree_start;
    const BYTE_LOOKUP *next_table;
    unsigned int next_offset;
    VALUE next_info;
    unsigned char next_byte;
    int from_utf8 = my_transcoder->from_utf8;
    char *out_s = out_stop - my_transcoder->max_output + 1;
    while (in_p < in_stop) {
	next_table = conv_tree_start;
	if (out_p >= out_s) {
	    int len = (out_p - *out_pos);
	    int new_len = (len + my_transcoder->max_output) * 2;
	    *out_pos = (*my_transcoding->flush_func)(my_transcoding, len, new_len);
	    out_p = *out_pos + len;
	    out_s = *out_pos + new_len - my_transcoder->max_output;
	}
	next_byte = (unsigned char)*in_p++;
      follow_byte:
	next_offset = next_table->base[next_byte];
	next_info = (VALUE)next_table->info[next_offset];
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
	    next_byte = (unsigned char)*in_p++;
	    if (from_utf8) {
		if ((next_byte&0xC0) == 0x80)
		    next_byte -= 0x80;
		else
		    goto illegal;
	    }
	    next_table = next_table->info[next_offset];
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
	    rb_raise(rb_eRuntimeError /*@@@change exception*/, "conversion undefined for byte sequence (maybe illegal byte sequence)");
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

static char *
str_transcoding_resize(transcoding *my_transcoding, int len, int new_len)
{
    VALUE dest_string = my_transcoding->ruby_string_dest;
    rb_str_resize(dest_string, new_len);
    return RSTRING_PTR(dest_string);
}

static int
str_transcode(int argc, VALUE *argv, VALUE *self)
{
    VALUE dest;
    VALUE str = *self;
    long blen, slen;
    char *buf, *bp, *sp, *fromp;
    rb_encoding *from_enc, *to_enc;
    const char *from_e, *to_e;
    int from_encidx, to_encidx;
    VALUE from_encval, to_encval;
    transcoder *my_transcoder;
    transcoding my_transcoding;
    int final_encoding = 0;

    if (argc<1 || argc>2) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 2)", argc);
    }
    if ((to_encidx = rb_to_encoding_index(to_encval = argv[0])) < 0) {
	to_enc = 0;
	to_e = StringValueCStr(to_encval);
    }
    else {
	to_enc = rb_enc_from_index(to_encidx);
	to_e = rb_enc_name(to_enc);
    }
    if (argc==1) {
	from_encidx = rb_enc_get_index(str);
	from_enc = rb_enc_from_index(from_encidx);
	from_e = rb_enc_name(from_enc);
    }
    else if ((from_encidx = rb_to_encoding_index(from_encval = argv[1])) < 0) {
	from_enc = 0;
	from_e = StringValueCStr(from_encval);
    }
    else {
	from_enc = rb_enc_from_index(from_encidx);
	from_e = rb_enc_name(from_enc);
    }

    if (from_enc && from_enc == to_enc) {
	return -1;
    }
    if (from_enc && to_enc && rb_enc_asciicompat(from_enc) && rb_enc_asciicompat(to_enc)) {
	if (ENC_CODERANGE(str) == ENC_CODERANGE_7BIT) {
	    return to_encidx;
	}
    }
    if (strcasecmp(from_e, to_e) == 0) {
	return -1;
    }

    while (!final_encoding) /* loop for multistep transcoding */
    {                       /* later, maybe use smaller intermediate strings for very long strings */
	if (!(my_transcoder = transcode_dispatch(from_e, to_e))) {
	    rb_raise(rb_eArgError, "transcoding not supported (from %s to %s)", from_e, to_e);
	}

	fromp = sp = RSTRING_PTR(str);
	slen = RSTRING_LEN(str);
	blen = slen + 30; /* len + margin */
	dest = rb_str_tmp_new(blen);
	bp = RSTRING_PTR(dest);
	my_transcoding.ruby_string_dest = dest;
	my_transcoding.flush_func = str_transcoding_resize;

	transcode_loop(&fromp, &bp, (sp+slen), (bp+blen), my_transcoder, &my_transcoding);
	if (fromp != sp+slen) {
	    rb_raise(rb_eArgError, "not fully converted, %d bytes left", sp+slen-fromp);
	}
	buf = RSTRING_PTR(dest);
	*bp = '\0';
	rb_str_set_len(dest, bp - buf);

	if (encoding_equal(my_transcoder->to_encoding, to_e)) {
	    final_encoding = 1;
	}
	else {
	    from_e = my_transcoder->to_encoding;
	    str = dest;
	}
    }
    /* set encoding */
    if (!to_enc) {
	to_encidx = rb_enc_replicate(to_e, rb_ascii8bit_encoding());
    }
    *self = dest;

    return to_encidx;
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
    VALUE newstr = str;
    int encidx = str_transcode(argc, argv, &newstr);

    if (encidx < 0) return str;
    rb_str_shared_replace(str, newstr);
    rb_enc_associate_index(str, encidx);
    return str;
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
    VALUE newstr = str;
    int encidx = str_transcode(argc, argv, &newstr);

    if (newstr == str) {
	newstr = rb_str_new3(str);
	if (encidx >= 0) rb_enc_associate_index(newstr, encidx);
    }
    else {
	RBASIC(newstr)->klass = rb_obj_class(str);
	OBJ_INFECT(newstr, str);
	rb_enc_associate_index(newstr, encidx);
    }
    return newstr;
}

void
Init_transcode(void)
{
    init_transcoder_table();
    rb_define_method(rb_cString, "encode", rb_str_transcode, -1);
    rb_define_method(rb_cString, "encode!", rb_str_transcode_bang, -1);
}
