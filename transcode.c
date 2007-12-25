/**********************************************************************

  transcode.c -

  $Author$
  $Date$
  created at: Tue Oct 30 16:10:22 JST 2007

  Copyright (C) 2007 Martin Duerst

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#define PType (int)
#include "transcode_data.h"
#include <ctype.h>

VALUE rb_str_tmp_new(long);
VALUE rb_str_shared_replace(VALUE, VALUE);

/*
 *  Dispatch data and logic
 */

static st_table *transcoder_table, *transcoder_lib_table;

#define TRANSCODER_INTERNAL_SEPARATOR '\t'

static char *
transcoder_key(const char *from_e, const char *to_e)
{
    int to_len = strlen(to_e);
    int from_len = strlen(from_e);
    char *const key = xmalloc(to_len + from_len + 2);

    memcpy(key, to_e, to_len);
    memcpy(key + to_len + 1, from_e, from_len + 1);
    key[to_len] = TRANSCODER_INTERNAL_SEPARATOR;
    return key;
}

void
rb_register_transcoder(const rb_transcoder *tr)
{
    st_data_t k, val = 0;
    const char *const from_e = tr->from_encoding;
    const char *const to_e = tr->to_encoding;
    char *const key = transcoder_key(from_e, to_e);

    if (st_lookup(transcoder_table, (st_data_t)key, &val)) {
	xfree(key);
	rb_raise(rb_eArgError, "transcoder from %s to %s has been already registered",
		 from_e, to_e);
    }
    k = (st_data_t)key;
    if (st_delete(transcoder_lib_table, &k, &val)) {
	xfree((char *)k);
    }
    st_insert(transcoder_table, (st_data_t)key, (st_data_t)tr);
}

static void
declare_transcoder(const char *to, const char *from, const char *lib)
{
    const char *const key = transcoder_key(to, from);
    st_data_t k = (st_data_t)key, val;

    if (st_delete(transcoder_lib_table, &k, &val)) {
	xfree((char *)k);
    }
    st_insert(transcoder_lib_table, (st_data_t)key, (st_data_t)lib);
}

#define MAX_TRANSCODER_LIBNAME_LEN 64
static const char transcoder_lib_prefix[] = "enc/trans/";

void
rb_declare_transcoder(const char *enc1, const char *enc2, const char *lib)
{
    if (!lib || strlen(lib) > MAX_TRANSCODER_LIBNAME_LEN) {
	rb_raise(rb_eArgError, "invalid library name - %s",
		 lib ? lib : "(null)");
    }
    declare_transcoder(enc1, enc2, lib);
    declare_transcoder(enc2, enc1, lib);
}

static void
init_transcoder_table(void)
{
    rb_declare_transcoder("ISO-8859-1",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-2",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-3",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-4",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-5",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-6",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-7",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-8",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-9",  "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-10", "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-11", "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-13", "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-14", "UTF-8", "single_byte");
    rb_declare_transcoder("ISO-8859-15", "UTF-8", "single_byte");
    rb_declare_transcoder("SHIFT_JIS",   "UTF-8", "japanese");
    rb_declare_transcoder("EUC-JP",      "UTF-8", "japanese");
    rb_declare_transcoder("ISO-2022-JP", "UTF-8", "japanese");
}

#define encoding_equal(enc1, enc2) (strcasecmp(enc1, enc2) == 0)

static rb_transcoder *
transcode_dispatch(const char* from_encoding, const char* to_encoding)
{
    char *const key = transcoder_key(from_encoding, to_encoding);
    st_data_t k, val = 0;

    k = (st_data_t)key;
    if (!st_lookup(transcoder_table, k, &val) &&
	st_delete(transcoder_lib_table, &k, &val)) {
	const char *const lib = (const char *)val;
	int len = strlen(lib);
	char path[sizeof(transcoder_lib_prefix) + MAX_TRANSCODER_LIBNAME_LEN];

	xfree((char *)k);
	if (len > MAX_TRANSCODER_LIBNAME_LEN) return NULL;
	memcpy(path, transcoder_lib_prefix, sizeof(transcoder_lib_prefix) - 1);
	memcpy(path + sizeof(transcoder_lib_prefix) - 1, lib, len + 1);
	if (!rb_require(path)) return NULL;
	if (!st_lookup(transcoder_table, (st_data_t)key, &val)) {
	    /* multistep logic, via UTF-8 */
	    if (!encoding_equal(from_encoding, "UTF-8") &&
		!encoding_equal(to_encoding, "UTF-8") &&
		transcode_dispatch("UTF-8", to_encoding)) {  /* check that we have a second step */
		return transcode_dispatch(from_encoding, "UTF-8"); /* return first step */
	    }
	    return NULL;
	}
    }
    return (rb_transcoder *)val;
}


/*
 *  Transcoding engine logic
 */
static void
transcode_loop(char **in_pos, char **out_pos,
	       char *in_stop, char *out_stop,
	       const rb_transcoder *my_transcoder,
	       rb_transcoding *my_transcoding)
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
str_transcoding_resize(rb_transcoding *my_transcoding, int len, int new_len)
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
    rb_transcoder *my_transcoder;
    rb_transcoding my_transcoding;
    int final_encoding = 0;

    if (argc<1 || argc>2) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 2)", argc);
    }
    if ((to_encidx = rb_to_encoding_index(to_encval = argv[0])) < 0) {
	to_enc = 0;
	to_encidx = 0;
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

	if (my_transcoder->preprocessor)
	{
	    fromp = sp = RSTRING_PTR(str);
	    slen = RSTRING_LEN(str);
	    blen = slen + 30; /* len + margin */
	    dest = rb_str_tmp_new(blen);
	    bp = RSTRING_PTR(dest);
	    my_transcoding.ruby_string_dest = dest;
	    (*my_transcoder->preprocessor)(&fromp, &bp, (sp+slen), (bp+blen), my_transcoder, &my_transcoding);
	    if (fromp != sp+slen) {
		rb_raise(rb_eArgError, "not fully converted, %d bytes left", sp+slen-fromp);
	    }
	    buf = RSTRING_PTR(dest);
	    *bp = '\0';
	    rb_str_set_len(dest, bp - buf);
	    str = dest;
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
	if (my_transcoder->postprocessor)
	{
	    str = dest;
	    fromp = sp = RSTRING_PTR(str);
	    slen = RSTRING_LEN(str);
	    blen = slen + 30; /* len + margin */
	    dest = rb_str_tmp_new(blen);
	    bp = RSTRING_PTR(dest);
	    my_transcoding.ruby_string_dest = dest;
	    (*my_transcoder->postprocessor)(&fromp, &bp, (sp+slen), (bp+blen), my_transcoder, &my_transcoding);
	    if (fromp != sp+slen) {
		rb_raise(rb_eArgError, "not fully converted, %d bytes left", sp+slen-fromp);
	    }
	    buf = RSTRING_PTR(dest);
	    *bp = '\0';
	    rb_str_set_len(dest, bp - buf);
	}

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
	to_encidx = rb_define_dummy_encoding(to_e);
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
    transcoder_table = st_init_strcasetable();
    transcoder_lib_table = st_init_strcasetable();
    init_transcoder_table();

    rb_define_method(rb_cString, "encode", rb_str_transcode, -1);
    rb_define_method(rb_cString, "encode!", rb_str_transcode_bang, -1);
}
