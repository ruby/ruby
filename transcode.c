/**********************************************************************

  transcode.c -

  $Author$
  created at: Tue Oct 30 16:10:22 JST 2007

  Copyright (C) 2007 Martin Duerst

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#define PType (int)
#include "transcode_data.h"
#include <ctype.h>

static VALUE sym_invalid, sym_undef, sym_ignore, sym_replace;
#define INVALID_IGNORE 0x1
#define INVALID_REPLACE 0x2
#define UNDEF_IGNORE 0x10
#define UNDEF_REPLACE 0x20

/*
 *  Dispatch data and logic
 */

typedef struct {
    const char *from;
    const char *to;
    const char *lib; /* maybe null.  it means that don't load the library. */
    const rb_transcoder *transcoder;
} transcoder_entry_t;

static st_table *transcoder_table;

static transcoder_entry_t *
make_transcoder_entry(const char *from, const char *to)
{
    st_data_t val;
    st_table *table2;

    if (!st_lookup(transcoder_table, (st_data_t)from, &val)) {
        val = (st_data_t)st_init_strcasetable();
        st_add_direct(transcoder_table, (st_data_t)from, val);
    }
    table2 = (st_table *)val;
    if (!st_lookup(table2, (st_data_t)to, &val)) {
        transcoder_entry_t *entry = ALLOC(transcoder_entry_t);
        entry->from = from;
        entry->to = to;
        entry->lib = NULL;
        entry->transcoder = NULL;
        val = (st_data_t)entry;
        st_add_direct(table2, (st_data_t)to, val);
    }
    return (transcoder_entry_t *)val;
}

static transcoder_entry_t *
get_transcoder_entry(const char *from, const char *to)
{
    st_data_t val;
    st_table *table2;

    if (!st_lookup(transcoder_table, (st_data_t)from, &val)) {
        return NULL;
    }
    table2 = (st_table *)val;
    if (!st_lookup(table2, (st_data_t)to, &val)) {
        return NULL;
    }
    return (transcoder_entry_t *)val;
}

void
rb_register_transcoder(const rb_transcoder *tr)
{
    const char *const from_e = tr->from_encoding;
    const char *const to_e = tr->to_encoding;

    transcoder_entry_t *entry;

    entry = make_transcoder_entry(from_e, to_e);
    if (entry->transcoder) {
	rb_raise(rb_eArgError, "transcoder from %s to %s has been already registered",
		 from_e, to_e);
    }

    entry->transcoder = tr;
}

static void
declare_transcoder(const char *to, const char *from, const char *lib)
{
    transcoder_entry_t *entry;

    entry = make_transcoder_entry(from, to);
    entry->lib = lib;
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

#define encoding_equal(enc1, enc2) (STRCASECMP(enc1, enc2) == 0)

typedef struct search_path_queue_tag {
    struct search_path_queue_tag *next;
    const char *enc;
} search_path_queue_t;

typedef struct {
    st_table *visited;
    search_path_queue_t *queue;
    search_path_queue_t **queue_last_ptr;
    const char *base_enc;
} search_path_bfs_t;

static int
transcode_search_path_i(st_data_t key, st_data_t val, st_data_t arg)
{
    const char *to = (const char *)key;
    search_path_bfs_t *bfs = (search_path_bfs_t *)arg;
    search_path_queue_t *q;

    if (st_lookup(bfs->visited, (st_data_t)to, &val)) {
        return ST_CONTINUE;
    }

    q = ALLOC(search_path_queue_t);
    q->enc = to;
    q->next = NULL;
    *bfs->queue_last_ptr = q;
    bfs->queue_last_ptr = &q->next;

    st_add_direct(bfs->visited, (st_data_t)to, (st_data_t)bfs->base_enc);
    return ST_CONTINUE;
}

static int
transcode_search_path(const char *from, const char *to,
    void (*callback)(const char *from, const char *to, int depth, void *arg),
    void *arg)
{
    search_path_bfs_t bfs;
    search_path_queue_t *q;
    st_data_t val;
    st_table *table2;
    int found;

    q = ALLOC(search_path_queue_t);
    q->enc = from;
    q->next = NULL;
    bfs.queue_last_ptr = &q->next;
    bfs.queue = q;

    bfs.visited = st_init_strcasetable();
    st_add_direct(bfs.visited, (st_data_t)from, (st_data_t)NULL);

    while (bfs.queue) {
        q = bfs.queue;
        bfs.queue = q->next;
        if (!bfs.queue)
            bfs.queue_last_ptr = &bfs.queue;

        if (!st_lookup(transcoder_table, (st_data_t)q->enc, &val)) {
            xfree(q);
            continue;
        }
        table2 = (st_table *)val;

        if (st_lookup(table2, (st_data_t)to, &val)) {
            st_add_direct(bfs.visited, (st_data_t)to, (st_data_t)q->enc);
            xfree(q);
            found = 1;
            goto cleanup;
        }

        bfs.base_enc = q->enc;
        st_foreach(table2, transcode_search_path_i, (st_data_t)&bfs);
        bfs.base_enc = NULL;

        xfree(q);
    }
    found = 0;

cleanup:
    while (bfs.queue) {
        q = bfs.queue;
        bfs.queue = q->next;
        xfree(q);
    }

    if (found) {
        const char *enc = to;
        int depth = 0;
        while (1) {
            st_lookup(bfs.visited, (st_data_t)enc, &val);
            if (!val)
                break;
            depth++;
            enc = (const char *)val;
        }
        enc = to;
        while (1) {
            st_lookup(bfs.visited, (st_data_t)enc, &val);
            if (!val)
                break;
            callback((const char *)val, enc, --depth, arg);
            enc = (const char *)val;
        }
    }

    st_free_table(bfs.visited);

    return found;
}

static void
transcode_dispatch_cb(const char *from, const char *to, int depth, void *arg)
{
    const rb_transcoder **first_transcoder_ptr = (const rb_transcoder **)arg;

    transcoder_entry_t *entry;

    if (!*first_transcoder_ptr)
        return;

    entry = get_transcoder_entry(from, to);
    if (!entry)
        goto failed;

    if (!entry->transcoder && entry->lib) {
        const char *lib = entry->lib;
        int len = strlen(lib);
        char path[sizeof(transcoder_lib_prefix) + MAX_TRANSCODER_LIBNAME_LEN];

        entry->lib = NULL;

        if (len > MAX_TRANSCODER_LIBNAME_LEN) goto failed;
        memcpy(path, transcoder_lib_prefix, sizeof(transcoder_lib_prefix) - 1);
        memcpy(path + sizeof(transcoder_lib_prefix) - 1, lib, len + 1);
        if (!rb_require(path)) goto failed;
    }
    if (!entry->transcoder)
        goto failed;

    if (depth == 0)
        *first_transcoder_ptr = entry->transcoder;

    return;

failed:
    *first_transcoder_ptr = NULL;
    return;
}

static const rb_transcoder *
transcode_dispatch(const char *from_encoding, const char *to_encoding)
{
    const rb_transcoder *first_transcoder = (rb_transcoder *)1;

    if (transcode_search_path(from_encoding, to_encoding, transcode_dispatch_cb, (void *)&first_transcoder)) {
        return first_transcoder;
    }
    return NULL;
}

static void
output_replacement_character(unsigned char **out_pp, rb_encoding *enc)
{
    unsigned char *out_p = *out_pp;
    static rb_encoding *utf16be_encoding, *utf16le_encoding;
    static rb_encoding *utf32be_encoding, *utf32le_encoding;
    if (!utf16be_encoding) {
	utf16be_encoding = rb_enc_find("UTF-16BE");
	utf16le_encoding = rb_enc_find("UTF-16LE");
	utf32be_encoding = rb_enc_find("UTF-32BE");
	utf32le_encoding = rb_enc_find("UTF-32LE");
    }
    if (rb_utf8_encoding() == enc) {
	*out_p++ = 0xEF;
	*out_p++ = 0xBF;
	*out_p++ = 0xBD;
    }
    else if (utf16be_encoding == enc) {
	*out_p++ = 0xFF;
	*out_p++ = 0xFD;
    }
    else if (utf16le_encoding == enc) {
	*out_p++ = 0xFD;
	*out_p++ = 0xFF;
    }
    else if (utf32be_encoding == enc) {
	*out_p++ = 0x00;
	*out_p++ = 0x00;
	*out_p++ = 0xFF;
	*out_p++ = 0xFD;
    }
    else if (utf32le_encoding == enc) {
	*out_p++ = 0xFD;
	*out_p++ = 0xFF;
	*out_p++ = 0x00;
	*out_p++ = 0x00;
    }
    else {
	*out_p++ = '?';
    }
    *out_pp = out_p;
    return;
}

/*
 *  Transcoding engine logic
 */
static void
transcode_loop(const unsigned char **in_pos, unsigned char **out_pos,
	       const unsigned char *in_stop, unsigned char *out_stop,
	       const rb_transcoder *my_transcoder,
	       rb_transcoding *my_transcoding,
	       const int opt)
{
    const unsigned char *in_p = *in_pos;
    unsigned char *out_p = *out_pos;
    const BYTE_LOOKUP *conv_tree_start = my_transcoder->conv_tree_start;
    const BYTE_LOOKUP *next_table;
    const unsigned char *char_start;
    VALUE next_info;
    unsigned char next_byte;
    unsigned char *out_s = out_stop - my_transcoder->max_output + 1;
    rb_encoding *to_encoding = rb_enc_find(my_transcoder->to_encoding);

    while (in_p < in_stop) {
	char_start = in_p;
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
        if (next_byte < next_table->base[0] || next_table->base[1] < next_byte)
            next_info = INVALID;
        else {
            unsigned int next_offset = next_table->base[2+next_byte-next_table->base[0]];
            next_info = (VALUE)next_table->info[next_offset];
        }
      follow_info:
	switch (next_info & 0x1F) {
	  case NOMAP:
	    *out_p++ = next_byte;
	    continue;
	  case 0x00: case 0x04: case 0x08: case 0x0C:
	  case 0x10: case 0x14: case 0x18: case 0x1C:
	    if (in_p >= in_stop) {
		/* todo: deal with the case of backtracking */
		/* todo: deal with incomplete input (streaming) */
		goto invalid;
	    }
	    next_byte = (unsigned char)*in_p++;
	    next_table = (const BYTE_LOOKUP *)next_info;
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
	  case FUNii:
	    next_info = (VALUE)(*my_transcoder->func_ii)(my_transcoding, next_info);
	    goto follow_info;
	  case FUNsi:
	    next_info = (VALUE)(*my_transcoder->func_si)(my_transcoding, char_start, (size_t)(in_p-char_start));
	    goto follow_info;
	    break;
	  case FUNio:
	    out_p += (VALUE)(*my_transcoder->func_io)(my_transcoding, next_info, out_p);
	    break;
	  case FUNso:
	    out_p += (VALUE)(*my_transcoder->func_so)(my_transcoding, char_start, (size_t)(in_p-char_start), out_p);
	    break;
	  case INVALID:
            {
                int unitlen = my_transcoder->from_unit_length;
                if (in_stop - char_start <= unitlen)
                    in_p = in_stop;
                else if (in_p - char_start <= unitlen)
                    in_p = char_start + unitlen;
                else
                    in_p = char_start + ((in_p - char_start - 1) / unitlen) * unitlen;
                goto invalid;
            }
	  case UNDEF:
	    goto undef;
	}
	continue;
      invalid:
	/* deal with invalid byte sequence */
	/* todo: add more alternative behaviors */
	if (opt&INVALID_IGNORE) {
	    continue;
	}
	else if (opt&INVALID_REPLACE) {
	    output_replacement_character(&out_p, to_encoding);
	    continue;
	}
	rb_raise(TRANSCODE_ERROR, "invalid byte sequence");
	continue;
      undef:
	/* valid character in from encoding
	 * but no related character(s) in to encoding */
	/* todo: add more alternative behaviors */
	if (opt&UNDEF_IGNORE) {
	    continue;
	}
	else if (opt&UNDEF_REPLACE) {
	    output_replacement_character(&out_p, to_encoding);
	    continue;
	}
	rb_raise(TRANSCODE_ERROR, "conversion undefined for byte sequence (maybe invalid byte sequence)");
	continue;
    }
    /* cleanup */
    if (my_transcoder->finish_func) {
	if (out_p >= out_s) {
	    int len = (out_p - *out_pos);
	    int new_len = (len + my_transcoder->max_output) * 2;
	    *out_pos = (*my_transcoding->flush_func)(my_transcoding, len, new_len);
	    out_p = *out_pos + len;
	    out_s = *out_pos + new_len - my_transcoder->max_output;
	}
        out_p += my_transcoder->finish_func(my_transcoding, out_p);
    }
    *in_pos  = in_p;
    *out_pos = out_p;
}


/*
 *  String-specific code
 */

static unsigned char *
str_transcoding_resize(rb_transcoding *my_transcoding, int len, int new_len)
{
    VALUE dest_string = my_transcoding->ruby_string_dest;
    rb_str_resize(dest_string, new_len);
    return (unsigned char *)RSTRING_PTR(dest_string);
}

static int
str_transcode(int argc, VALUE *argv, VALUE *self)
{
    VALUE dest;
    VALUE str = *self;
    long blen, slen;
    unsigned char *buf, *bp, *sp;
    const unsigned char *fromp;
    rb_encoding *from_enc, *to_enc;
    const char *from_e, *to_e;
    int from_encidx, to_encidx;
    VALUE from_encval, to_encval;
    const rb_transcoder *my_transcoder;
    rb_transcoding my_transcoding;
    int final_encoding = 0;
    VALUE opt;
    int options = 0;

    opt = rb_check_convert_type(argv[argc-1], T_HASH, "Hash", "to_hash");
    if (!NIL_P(opt)) {
	VALUE v;

	argc--;
	v = rb_hash_aref(opt, sym_invalid);
	if (NIL_P(v)) {
	}
	else if (v==sym_ignore) {
	    options |= INVALID_IGNORE;
	}
	else if (v==sym_replace) {
	    options |= INVALID_REPLACE;
	    v = rb_hash_aref(opt, sym_replace);
	}
	else {
	    rb_raise(rb_eArgError, "unknown value for invalid: setting");
	}
	v = rb_hash_aref(opt, sym_undef);
	if (NIL_P(v)) {
	}
	else if (v==sym_ignore) {
	    options |= UNDEF_IGNORE;
	}
	else if (v==sym_replace) {
	    options |= UNDEF_REPLACE;
	}
	else {
	    rb_raise(rb_eArgError, "unknown value for undef: setting");
	}
    }
    if (argc < 1 || argc > 2) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for 1..2)", argc);
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
    if (encoding_equal(from_e, to_e)) {
	return -1;
    }

    do { /* loop for multistep transcoding */
	/* later, maybe use smaller intermediate strings for very long strings */
	if (!(my_transcoder = transcode_dispatch(from_e, to_e))) {
	    rb_raise(rb_eArgError, "transcoding not supported (from %s to %s)", from_e, to_e);
	}

	my_transcoding.transcoder = my_transcoder;
        memset(my_transcoding.stateful, 0, sizeof(my_transcoding.stateful));

	fromp = sp = (unsigned char *)RSTRING_PTR(str);
	slen = RSTRING_LEN(str);
	blen = slen + 30; /* len + margin */
	dest = rb_str_tmp_new(blen);
	bp = (unsigned char *)RSTRING_PTR(dest);
	my_transcoding.ruby_string_dest = dest;
	my_transcoding.flush_func = str_transcoding_resize;

	transcode_loop(&fromp, &bp, (sp+slen), (bp+blen), my_transcoder, &my_transcoding, options);
	if (fromp != sp+slen) {
	    rb_raise(rb_eArgError, "not fully converted, %"PRIdPTRDIFF" bytes left", sp+slen-fromp);
	}
	buf = (unsigned char *)RSTRING_PTR(dest);
	*bp = '\0';
	rb_str_set_len(dest, bp - buf);

	if (encoding_equal(my_transcoder->to_encoding, to_e)) {
	    final_encoding = 1;
	}
	else {
	    from_e = my_transcoder->to_encoding;
	    str = dest;
	}
    } while (!final_encoding);
    /* set encoding */
    if (!to_enc) {
	to_encidx = rb_define_dummy_encoding(to_e);
    }
    *self = dest;

    return to_encidx;
}

static inline VALUE
str_encode_associate(VALUE str, int encidx)
{
    int cr = 0;

    rb_enc_associate_index(str, encidx);

    /* transcoded string never be broken. */
    if (rb_enc_asciicompat(rb_enc_from_index(encidx))) {
	rb_str_coderange_scan_restartable(RSTRING_PTR(str), RSTRING_END(str), 0, &cr);
    }
    else {
	cr = ENC_CODERANGE_VALID;
    }
    ENC_CODERANGE_SET(str, cr);
    return str;
}

/*
 *  call-seq:
 *     str.encode!(encoding [, options] )   => str
 *     str.encode!(to_encoding, from_encoding [, options] )   => str
 *
 *  The first form transcodes the contents of <i>str</i> from
 *  str.encoding to +encoding+.
 *  The second form transcodes the contents of <i>str</i> from
 *  from_encoding to to_encoding.
 *  The options Hash gives details for conversion. See String#encode
 *  for details.
 *  Returns the string even if no changes were made.
 */

static VALUE
str_encode_bang(int argc, VALUE *argv, VALUE str)
{
    VALUE newstr = str;
    int encidx = str_transcode(argc, argv, &newstr);

    if (encidx < 0) return str;
    rb_str_shared_replace(str, newstr);
    return str_encode_associate(str, encidx);
}

/*
 *  call-seq:
 *     str.encode(encoding [, options] )   => str
 *     str.encode(to_encoding, from_encoding [, options] )   => str
 *
 *  The first form returns a copy of <i>str</i> transcoded
 *  to encoding +encoding+.
 *  The second form returns a copy of <i>str</i> transcoded
 *  from from_encoding to to_encoding.
 *  The options Hash gives details for conversion. Details
 *  to be added.
 */

static VALUE
str_encode(int argc, VALUE *argv, VALUE str)
{
    VALUE newstr = str;
    int encidx = str_transcode(argc, argv, &newstr);

    if (encidx < 0) return rb_str_dup(str);
    RBASIC(newstr)->klass = rb_obj_class(str);
    return str_encode_associate(newstr, encidx);
}

VALUE
rb_str_transcode(VALUE str, VALUE to)
{
    return str_encode(1, &to, str);
}

void
Init_transcode(void)
{
    transcoder_table = st_init_strcasetable();

    sym_invalid = ID2SYM(rb_intern("invalid"));
    sym_undef = ID2SYM(rb_intern("undef"));
    sym_ignore = ID2SYM(rb_intern("ignore"));
    sym_replace = ID2SYM(rb_intern("replace"));

    rb_define_method(rb_cString, "encode", str_encode, -1);
    rb_define_method(rb_cString, "encode!", str_encode_bang, -1);
}
