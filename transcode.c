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

VALUE rb_eConversionUndefined;
VALUE rb_eInvalidByteSequence;

VALUE rb_cEncodingConverter;

static VALUE sym_invalid, sym_undef, sym_ignore, sym_replace;
#define INVALID_IGNORE                  0x1
#define INVALID_REPLACE                 0x2
#define UNDEF_IGNORE                    0x10
#define UNDEF_REPLACE                   0x20

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
    int pathlen;

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
        int depth;
        pathlen = 0;
        while (1) {
            st_lookup(bfs.visited, (st_data_t)enc, &val);
            if (!val)
                break;
            pathlen++;
            enc = (const char *)val;
        }
        depth = pathlen;
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

    if (found)
        return pathlen;
    else
        return -1;
}

static const rb_transcoder *
load_transcoder_entry(transcoder_entry_t *entry)
{
    if (entry->transcoder)
        return entry->transcoder;

    if (entry->lib) {
        const char *lib = entry->lib;
        int len = strlen(lib);
        char path[sizeof(transcoder_lib_prefix) + MAX_TRANSCODER_LIBNAME_LEN];

        entry->lib = NULL;

        if (len > MAX_TRANSCODER_LIBNAME_LEN)
            return NULL;
        memcpy(path, transcoder_lib_prefix, sizeof(transcoder_lib_prefix) - 1);
        memcpy(path + sizeof(transcoder_lib_prefix) - 1, lib, len + 1);
        if (!rb_require(path))
            return NULL;
    }

    if (entry->transcoder)
        return entry->transcoder;

    return NULL;
}

static const char*
get_replacement_character(rb_encoding *enc, int *len_ret, const char **repl_enc_ptr)
{
    static rb_encoding *utf16be_encoding, *utf16le_encoding;
    static rb_encoding *utf32be_encoding, *utf32le_encoding;
    if (!utf16be_encoding) {
	utf16be_encoding = rb_enc_find("UTF-16BE");
	utf16le_encoding = rb_enc_find("UTF-16LE");
	utf32be_encoding = rb_enc_find("UTF-32BE");
	utf32le_encoding = rb_enc_find("UTF-32LE");
    }
    if (rb_utf8_encoding() == enc) {
        *len_ret = 3;
        *repl_enc_ptr = "UTF-8";
        return "\xEF\xBF\xBD";
    }
    else if (utf16be_encoding == enc) {
        *len_ret = 2;
        *repl_enc_ptr = "UTF-16BE";
        return "\xFF\xFD";
    }
    else if (utf16le_encoding == enc) {
        *len_ret = 2;
        *repl_enc_ptr = "UTF-16LE";
        return "\xFD\xFF";
    }
    else if (utf32be_encoding == enc) {
        *len_ret = 4;
        *repl_enc_ptr = "UTF-32BE";
        return "\x00\x00\xFF\xFD";
    }
    else if (utf32le_encoding == enc) {
        *len_ret = 4;
        *repl_enc_ptr = "UTF-32LE";
        return "\xFD\xFF\x00\x00";
    }
    else {
        *len_ret = 1;
        *repl_enc_ptr = "US-ASCII";
        return "?";
    }
}

/*
 *  Transcoding engine logic
 */

static const unsigned char *
transcode_char_start(rb_transcoding *tc,
                         const unsigned char *in_start,
                         const unsigned char *inchar_start,
                         const unsigned char *in_p,
                         size_t *char_len_ptr)
{
    const unsigned char *ptr;
    if (inchar_start - in_start < tc->recognized_len) {
        MEMCPY(TRANSCODING_READBUF(tc) + tc->recognized_len,
               inchar_start, unsigned char, in_p - inchar_start);
        ptr = TRANSCODING_READBUF(tc);
    }
    else {
        ptr = inchar_start - tc->recognized_len;
    }
    *char_len_ptr = tc->recognized_len + (in_p - inchar_start);
    return ptr;
}

static rb_econv_result_t
transcode_restartable0(const unsigned char **in_pos, unsigned char **out_pos,
                      const unsigned char *in_stop, unsigned char *out_stop,
                      rb_transcoding *tc,
                      const int opt)

{
    const rb_transcoder *tr = tc->transcoder;
    int unitlen = tr->input_unit_length;
    int readagain_len = 0;

    const unsigned char *inchar_start;
    const unsigned char *in_p;

    unsigned char *out_p;

    unsigned char empty_buf;
    unsigned char *empty_ptr = &empty_buf;

    if (!in_pos) {
        in_pos = (const unsigned char **)&empty_ptr;
        in_stop = empty_ptr;
    }

    if (!out_pos) {
        out_pos = &empty_ptr;
        out_stop = empty_ptr;
    }

    in_p = inchar_start = *in_pos;

    out_p = *out_pos;

#define SUSPEND(ret, num) \
    do { \
        tc->resume_position = (num); \
        if (0 < in_p - inchar_start) \
            MEMMOVE(TRANSCODING_READBUF(tc)+tc->recognized_len, \
                   inchar_start, unsigned char, in_p - inchar_start); \
        *in_pos = in_p; \
        *out_pos = out_p; \
        tc->recognized_len += in_p - inchar_start; \
        if (readagain_len) { \
            tc->recognized_len -= readagain_len; \
            tc->readagain_len = readagain_len; \
        } \
        return ret; \
        resume_label ## num:; \
    } while (0)
#define SUSPEND_OBUF(num) \
    do { \
        while (out_stop - out_p < 1) { SUSPEND(econv_destination_buffer_full, num); } \
    } while (0)

#define SUSPEND_OUTPUT_FOLLOWED_BY_INPUT(num) \
    if ((opt & ECONV_OUTPUT_FOLLOWED_BY_INPUT) && *out_pos != out_p) { \
        SUSPEND(econv_output_followed_by_input, num); \
    }

#define next_table (tc->next_table)
#define next_info (tc->next_info)
#define next_byte (tc->next_byte)
#define writebuf_len (tc->writebuf_len)
#define writebuf_off (tc->writebuf_off)

    switch (tc->resume_position) {
      case 0: break;
      case 1: goto resume_label1;
      case 2: goto resume_label2;
      case 3: goto resume_label3;
      case 4: goto resume_label4;
      case 5: goto resume_label5;
      case 6: goto resume_label6;
      case 7: goto resume_label7;
      case 8: goto resume_label8;
      case 9: goto resume_label9;
      case 10: goto resume_label10;
      case 11: goto resume_label11;
      case 12: goto resume_label12;
      case 13: goto resume_label13;
      case 14: goto resume_label14;
      case 15: goto resume_label15;
      case 16: goto resume_label16;
      case 17: goto resume_label17;
      case 18: goto resume_label18;
      case 19: goto resume_label19;
      case 20: goto resume_label20;
      case 21: goto resume_label21;
      case 22: goto resume_label22;
      case 23: goto resume_label23;
      case 24: goto resume_label24;
      case 25: goto resume_label25;
      case 26: goto resume_label26;
    }

    while (1) {
        inchar_start = in_p;
        tc->recognized_len = 0;
	next_table = tr->conv_tree_start;

        SUSPEND_OUTPUT_FOLLOWED_BY_INPUT(24);

        if (in_stop <= in_p) {
            if (!(opt & ECONV_PARTIAL_INPUT))
                break;
            SUSPEND(econv_source_buffer_empty, 7);
            continue;
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
          case NOMAP: /* xxx: copy last byte only? */
            SUSPEND_OBUF(3); *out_p++ = next_byte;
	    continue;
	  case 0x00: case 0x04: case 0x08: case 0x0C:
	  case 0x10: case 0x14: case 0x18: case 0x1C:
            SUSPEND_OUTPUT_FOLLOWED_BY_INPUT(25);
	    while (in_p >= in_stop) {
                if (!(opt & ECONV_PARTIAL_INPUT))
                    goto invalid;
                SUSPEND(econv_source_buffer_empty, 5);
	    }
	    next_byte = (unsigned char)*in_p++;
	    next_table = (const BYTE_LOOKUP *)next_info;
	    goto follow_byte;
	  case ZERObt: /* drop input */
	    continue;
	  case ONEbt:
            SUSPEND_OBUF(9); *out_p++ = getBT1(next_info);
	    continue;
	  case TWObt:
            SUSPEND_OBUF(10); *out_p++ = getBT1(next_info);
            SUSPEND_OBUF(21); *out_p++ = getBT2(next_info);
	    continue;
	  case THREEbt:
            SUSPEND_OBUF(11); *out_p++ = getBT1(next_info);
            SUSPEND_OBUF(15); *out_p++ = getBT2(next_info);
            SUSPEND_OBUF(16); *out_p++ = getBT3(next_info);
	    continue;
	  case FOURbt:
            SUSPEND_OBUF(12); *out_p++ = getBT0(next_info);
            SUSPEND_OBUF(17); *out_p++ = getBT1(next_info);
            SUSPEND_OBUF(18); *out_p++ = getBT2(next_info);
            SUSPEND_OBUF(19); *out_p++ = getBT3(next_info);
	    continue;
	  case FUNii:
	    next_info = (VALUE)(*tr->func_ii)(tc, next_info);
	    goto follow_info;
	  case FUNsi:
            {
                const unsigned char *char_start;
                size_t char_len;
                char_start = transcode_char_start(tc, *in_pos, inchar_start, in_p, &char_len);
                next_info = (VALUE)(*tr->func_si)(tc, char_start, (size_t)char_len);
                goto follow_info;
            }
	  case FUNio:
            SUSPEND_OBUF(13);
            if (tr->max_output <= out_stop - out_p)
                out_p += (VALUE)(*tr->func_io)(tc, next_info, out_p);
            else {
                writebuf_len = (VALUE)(*tr->func_io)(tc, next_info, TRANSCODING_WRITEBUF(tc));
                writebuf_off = 0;
                while (writebuf_off < writebuf_len) {
                    SUSPEND_OBUF(20);
                    *out_p++ = TRANSCODING_WRITEBUF(tc)[writebuf_off++];
                }
            }
	    break;
	  case FUNso:
            {
                const unsigned char *char_start;
                size_t char_len;
                SUSPEND_OBUF(14);
                if (tr->max_output <= out_stop - out_p) {
                    char_start = transcode_char_start(tc, *in_pos, inchar_start, in_p, &char_len);
                    out_p += (VALUE)(*tr->func_so)(tc, char_start, (size_t)char_len, out_p);
                }
                else {
                    char_start = transcode_char_start(tc, *in_pos, inchar_start, in_p, &char_len);
                    writebuf_len = (VALUE)(*tr->func_so)(tc, char_start, (size_t)char_len, TRANSCODING_WRITEBUF(tc));
                    writebuf_off = 0;
                    while (writebuf_off < writebuf_len) {
                        SUSPEND_OBUF(22);
                        *out_p++ = TRANSCODING_WRITEBUF(tc)[writebuf_off++];
                    }
                }
                break;
            }
	  case INVALID:
            if (tc->recognized_len + (in_p - inchar_start) <= unitlen) {
                if (tc->recognized_len + (in_p - inchar_start) < unitlen)
                    SUSPEND_OUTPUT_FOLLOWED_BY_INPUT(26);
                while ((opt & ECONV_PARTIAL_INPUT) && tc->recognized_len + (in_stop - inchar_start) < unitlen) {
                    in_p = in_stop;
                    SUSPEND(econv_source_buffer_empty, 8);
                }
                if (tc->recognized_len + (in_stop - inchar_start) <= unitlen) {
                    in_p = in_stop;
                }
                else {
                    in_p = inchar_start + (unitlen - tc->recognized_len);
                }
            }
            else {
                int invalid_len; /* including the last byte which causes invalid */
                int discard_len;
                invalid_len = tc->recognized_len + (in_p - inchar_start);
                discard_len = ((invalid_len - 1) / unitlen) * unitlen;
                readagain_len = invalid_len - discard_len;
            }
            goto invalid;
	  case UNDEF:
	    goto undef;
	}
	continue;

      invalid:
        SUSPEND(econv_invalid_byte_sequence, 1);
        continue;

      undef:
        SUSPEND(econv_undefined_conversion, 2);
        continue;
    }

    /* cleanup */
    if (tr->finish_func) {
        SUSPEND_OBUF(4);
        if (tr->max_output <= out_stop - out_p) {
            out_p += tr->finish_func(tc, out_p);
        }
        else {
            writebuf_len = tr->finish_func(tc, TRANSCODING_WRITEBUF(tc));
            writebuf_off = 0;
            while (writebuf_off < writebuf_len) {
                SUSPEND_OBUF(23);
                *out_p++ = TRANSCODING_WRITEBUF(tc)[writebuf_off++];
            }
        }
    }
    while (1)
        SUSPEND(econv_finished, 6);
#undef SUSPEND
#undef next_table
#undef next_info
#undef next_byte
#undef writebuf_len
#undef writebuf_off
}

static rb_econv_result_t
transcode_restartable(const unsigned char **in_pos, unsigned char **out_pos,
                      const unsigned char *in_stop, unsigned char *out_stop,
                      rb_transcoding *tc,
                      const int opt)
{
    if (tc->readagain_len) {
        unsigned char *readagain_buf = ALLOCA_N(unsigned char, tc->readagain_len);
        const unsigned char *readagain_pos = readagain_buf;
        const unsigned char *readagain_stop = readagain_buf + tc->readagain_len;
        rb_econv_result_t res;

        MEMCPY(readagain_buf, TRANSCODING_READBUF(tc) + tc->recognized_len,
               unsigned char, tc->readagain_len);
        tc->readagain_len = 0;
        res = transcode_restartable0(&readagain_pos, out_pos, readagain_stop, out_stop, tc, opt|ECONV_PARTIAL_INPUT);
        if (res != econv_source_buffer_empty) {
            MEMCPY(TRANSCODING_READBUF(tc) + tc->recognized_len + tc->readagain_len,
                   readagain_pos, unsigned char, readagain_stop - readagain_pos);
            tc->readagain_len += readagain_stop - readagain_pos;
            return res;
        }
    }
    return transcode_restartable0(in_pos, out_pos, in_stop, out_stop, tc, opt);
}

static rb_transcoding *
rb_transcoding_open_by_transcoder(const rb_transcoder *tr, int flags)
{
    rb_transcoding *tc;

    tc = ALLOC(rb_transcoding);
    tc->transcoder = tr;
    tc->flags = flags;
    memset(tc->stateful, 0, sizeof(tc->stateful));
    tc->resume_position = 0;
    tc->recognized_len = 0;
    tc->readagain_len = 0;
    tc->writebuf_len = 0;
    tc->writebuf_off = 0;
    if (sizeof(tc->readbuf.ary) < tr->max_input) {
        tc->readbuf.ptr = xmalloc(tr->max_input);
    }
    if (sizeof(tc->writebuf.ary) < tr->max_output) {
        tc->writebuf.ptr = xmalloc(tr->max_output);
    }
    return tc;
}

static rb_econv_result_t
rb_transcoding_convert(rb_transcoding *tc,
  const unsigned char **input_ptr, const unsigned char *input_stop,
  unsigned char **output_ptr, unsigned char *output_stop,
  int flags)
{
    return transcode_restartable(
                input_ptr, output_ptr,
                input_stop, output_stop,
                tc, flags);
}

static void
rb_transcoding_close(rb_transcoding *tc)
{
    const rb_transcoder *tr = tc->transcoder;
    if (sizeof(tc->readbuf.ary) < tr->max_input)
        xfree(tc->readbuf.ptr);
    if (sizeof(tc->writebuf.ary) < tr->max_output)
        xfree(tc->writebuf.ptr);
    xfree(tc);
}

static rb_econv_t *
rb_econv_open_by_transcoder_entries(int n, transcoder_entry_t **entries)
{
    rb_econv_t *ec;
    int i;

    for (i = 0; i < n; i++) {
        const rb_transcoder *tr;
        tr = load_transcoder_entry(entries[i]);
        if (!tr)
            return NULL;
    }

    ec = ALLOC(rb_econv_t);
    ec->source_encoding_name = NULL;
    ec->destination_encoding_name = NULL;
    ec->in_buf_start = NULL;
    ec->in_data_start = NULL;
    ec->in_data_end = NULL;
    ec->in_buf_end = NULL;
    ec->num_trans = n;
    ec->elems = ALLOC_N(rb_econv_elem_t, ec->num_trans);
    ec->num_finished = 0;
    ec->last_tc = NULL;
    ec->last_trans_index = -1;
    ec->source_encoding = NULL;
    ec->destination_encoding = NULL;
    for (i = 0; i < ec->num_trans; i++) {
        const rb_transcoder *tr = load_transcoder_entry(entries[i]);
        ec->elems[i].tc = rb_transcoding_open_by_transcoder(tr, 0);
        ec->elems[i].out_buf_start = NULL;
        ec->elems[i].out_data_start = NULL;
        ec->elems[i].out_data_end = NULL;
        ec->elems[i].out_buf_end = NULL;
        ec->elems[i].last_result = econv_source_buffer_empty;
    }
    ec->last_tc = ec->elems[ec->num_trans-1].tc;
    ec->last_trans_index = ec->num_trans-1;

    for (i = 0; i < ec->num_trans-1; i++) {
        int bufsize = 4096;
        unsigned char *p;
        p = xmalloc(bufsize);
        ec->elems[i].out_buf_start = p;
        ec->elems[i].out_buf_end = p + bufsize;
        ec->elems[i].out_data_start = p;
        ec->elems[i].out_data_end = p;
    }

    return ec;
}

static void
trans_open_i(const char *from, const char *to, int depth, void *arg)
{
    transcoder_entry_t ***entries_ptr = arg;
    transcoder_entry_t **entries;

    if (!*entries_ptr) {
        entries = ALLOC_N(transcoder_entry_t *, depth+1+2);
        *entries_ptr = entries;
    }
    else {
        entries = *entries_ptr;
    }
    entries[depth] = get_transcoder_entry(from, to);
}

rb_econv_t *
rb_econv_open(const char *from, const char *to, int flags)
{
    transcoder_entry_t **entries = NULL;
    int num_trans;
    static rb_econv_t *ec;

    num_trans = transcode_search_path(from, to, trans_open_i, (void *)&entries);

    if (num_trans < 0 || !entries)
        return NULL;

    if (flags & (ECONV_CRLF_NEWLINE_ENCODER|ECONV_CR_NEWLINE_ENCODER)) {
        const char *name = (flags & ECONV_CRLF_NEWLINE_ENCODER) ? "crlf_newline" : "cr_newline";
        transcoder_entry_t *e = get_transcoder_entry("", name);
        if (!e)
            return NULL;
        MEMMOVE(entries+1, entries, transcoder_entry_t *, num_trans);
        entries[0] = e;
        num_trans++;
    }

    if (flags & ECONV_UNIVERSAL_NEWLINE_DECODER) {
        transcoder_entry_t *e = get_transcoder_entry("universal_newline", "");
        if (!e)
            return NULL;
        entries[num_trans++] = e;
    }

    ec = rb_econv_open_by_transcoder_entries(num_trans, entries);
    if (!ec)
        rb_raise(rb_eArgError, "encoding conversion not supported (from %s to %s)", from, to);

    ec->source_encoding_name = from;
    ec->destination_encoding_name = to;

    if (flags & ECONV_UNIVERSAL_NEWLINE_DECODER) {
        ec->last_tc = ec->elems[ec->num_trans-2].tc;
        ec->last_trans_index = ec->num_trans-2;
    }

    return ec;
}

static int
trans_sweep(rb_econv_t *ec,
    const unsigned char **input_ptr, const unsigned char *input_stop,
    unsigned char **output_ptr, unsigned char *output_stop,
    int flags,
    int start)
{
    int try;
    int i, f;

    const unsigned char **ipp, *is, *iold;
    unsigned char **opp, *os, *oold;
    rb_econv_result_t res;

    try = 1;
    while (try) {
        try = 0;
        for (i = start; i < ec->num_trans; i++) {
            rb_econv_elem_t *te = &ec->elems[i];

            if (i == 0) {
                ipp = input_ptr;
                is = input_stop;
            }
            else {
                rb_econv_elem_t *prev_te = &ec->elems[i-1];
                ipp = (const unsigned char **)&prev_te->out_data_start;
                is = prev_te->out_data_end;
            }

            if (i == ec->num_trans-1) {
                opp = output_ptr;
                os = output_stop;
            }
            else {
                if (te->out_buf_start != te->out_data_start) {
                    int len = te->out_data_end - te->out_data_start;
                    int off = te->out_data_start - te->out_buf_start;
                    MEMMOVE(te->out_buf_start, te->out_data_start, unsigned char, len);
                    te->out_data_start = te->out_buf_start;
                    te->out_data_end -= off;
                }
                opp = &te->out_data_end;
                os = te->out_buf_end;
            }

            f = flags;
            if (ec->num_finished != i)
                f |= ECONV_PARTIAL_INPUT;
            if (i == 0 && (flags & ECONV_OUTPUT_FOLLOWED_BY_INPUT)) {
                start = 1;
                flags &= ~ECONV_OUTPUT_FOLLOWED_BY_INPUT;
            }
            if (i != 0)
                f &= ~ECONV_OUTPUT_FOLLOWED_BY_INPUT;
            iold = *ipp;
            oold = *opp;
            te->last_result = res = rb_transcoding_convert(te->tc, ipp, is, opp, os, f);
            if (iold != *ipp || oold != *opp)
                try = 1;

            switch (res) {
              case econv_invalid_byte_sequence:
              case econv_undefined_conversion:
              case econv_output_followed_by_input:
                return i;

              case econv_destination_buffer_full:
              case econv_source_buffer_empty:
                break;

              case econv_finished:
                ec->num_finished = i+1;
                break;
            }
        }
    }
    return -1;
}

static rb_econv_result_t
rb_trans_conv(rb_econv_t *ec,
    const unsigned char **input_ptr, const unsigned char *input_stop,
    unsigned char **output_ptr, unsigned char *output_stop,
    int flags,
    int *result_position_ptr)
{
    int i;
    int needreport_index;
    int sweep_start;

    unsigned char empty_buf;
    unsigned char *empty_ptr = &empty_buf;

    if (!input_ptr) {
        input_ptr = (const unsigned char **)&empty_ptr;
        input_stop = empty_ptr;
    }

    if (!output_ptr) {
        output_ptr = &empty_ptr;
        output_stop = empty_ptr;
    }

    if (ec->elems[0].last_result == econv_output_followed_by_input)
        ec->elems[0].last_result = econv_source_buffer_empty;

    needreport_index = -1;
    for (i = ec->num_trans-1; 0 <= i; i--) {
        switch (ec->elems[i].last_result) {
          case econv_invalid_byte_sequence:
          case econv_undefined_conversion:
          case econv_output_followed_by_input:
          case econv_finished:
            sweep_start = i+1;
            needreport_index = i;
            goto found_needreport;

          case econv_destination_buffer_full:
          case econv_source_buffer_empty:
            break;

          default:
            rb_bug("unexpected transcode last result");
        }
    }

    /* /^[sd]+$/ is confirmed.  but actually /^s*d*$/. */

    if (ec->elems[ec->num_trans-1].last_result == econv_destination_buffer_full &&
        (flags & ECONV_OUTPUT_FOLLOWED_BY_INPUT)) {
        rb_econv_result_t res;

        res = rb_trans_conv(ec, NULL, NULL, output_ptr, output_stop,
                (flags & ~ECONV_OUTPUT_FOLLOWED_BY_INPUT)|ECONV_PARTIAL_INPUT,
                result_position_ptr);

        if (res == econv_source_buffer_empty)
            return econv_output_followed_by_input;
        return res;
    }

    sweep_start = 0;

found_needreport:

    do {
        needreport_index = trans_sweep(ec, input_ptr, input_stop, output_ptr, output_stop, flags, sweep_start);
        sweep_start = needreport_index + 1;
    } while (needreport_index != -1 && needreport_index != ec->num_trans-1);

    for (i = ec->num_trans-1; 0 <= i; i--) {
        if (ec->elems[i].last_result != econv_source_buffer_empty) {
            rb_econv_result_t res = ec->elems[i].last_result;
            if (res == econv_invalid_byte_sequence ||
                res == econv_undefined_conversion ||
                res == econv_output_followed_by_input) {
                ec->elems[i].last_result = econv_source_buffer_empty;
            }
            if (result_position_ptr)
                *result_position_ptr = i;
            return res;
        }
    }
    if (result_position_ptr)
        *result_position_ptr = -1;
    return econv_source_buffer_empty;
}

rb_econv_result_t
rb_econv_convert(rb_econv_t *ec,
    const unsigned char **input_ptr, const unsigned char *input_stop,
    unsigned char **output_ptr, unsigned char *output_stop,
    int flags)
{
    rb_econv_result_t res;
    int result_position;
    int has_output = 0;

    memset(&ec->last_error, 0, sizeof(ec->last_error));

    if (ec->elems[ec->num_trans-1].out_data_start) {
        unsigned char *data_start = ec->elems[ec->num_trans-1].out_data_start;
        unsigned char *data_end = ec->elems[ec->num_trans-1].out_data_end;
        if (data_start != data_end) {
            size_t len;
            if (output_stop - *output_ptr < data_end - data_start) {
                len = output_stop - *output_ptr;
                memcpy(*output_ptr, data_start, len);
                *output_ptr = output_stop;
                ec->elems[ec->num_trans-1].out_data_start += len;
                res = econv_destination_buffer_full;
                goto gotresult;
            }
            len = data_end - data_start;
            memcpy(*output_ptr, data_start, len);
            *output_ptr += len;
            ec->elems[ec->num_trans-1].out_data_start =
                ec->elems[ec->num_trans-1].out_data_end = 
                ec->elems[ec->num_trans-1].out_buf_start;
            has_output = 1;
        }
    }

    if (ec->in_buf_start && 
        ec->in_data_start != ec->in_data_end) {
        res = rb_trans_conv(ec, (const unsigned char **)&ec->in_data_start, ec->in_data_end, output_ptr, output_stop,
                (flags&~ECONV_OUTPUT_FOLLOWED_BY_INPUT)|ECONV_PARTIAL_INPUT, &result_position);
        if (res != econv_source_buffer_empty)
            goto gotresult;
    }

    if (has_output &&
        (flags & ECONV_OUTPUT_FOLLOWED_BY_INPUT) &&
        *input_ptr != input_stop) {
        input_stop = *input_ptr;
        res = rb_trans_conv(ec, input_ptr, input_stop, output_ptr, output_stop, flags, &result_position);
        if (res == econv_source_buffer_empty)
            res = econv_output_followed_by_input;
    }
    else if ((flags & ECONV_OUTPUT_FOLLOWED_BY_INPUT) ||
        ec->num_trans == 1) {
        res = rb_trans_conv(ec, input_ptr, input_stop, output_ptr, output_stop, flags, &result_position);
    }
    else {
        flags |= ECONV_OUTPUT_FOLLOWED_BY_INPUT;
        do {
            res = rb_trans_conv(ec, input_ptr, input_stop, output_ptr, output_stop, flags, &result_position);
        } while (res == econv_output_followed_by_input);
    }

gotresult:
    ec->last_error.result = res;
    ec->last_error.partial_input = flags & ECONV_PARTIAL_INPUT;
    if (res == econv_invalid_byte_sequence ||
        res == econv_undefined_conversion) {
        rb_transcoding *error_tc = ec->elems[result_position].tc;
        ec->last_error.error_tc = error_tc;
        ec->last_error.source_encoding = error_tc->transcoder->from_encoding;
        ec->last_error.destination_encoding = error_tc->transcoder->to_encoding;
        ec->last_error.error_bytes_start = TRANSCODING_READBUF(error_tc);
        ec->last_error.error_bytes_len = error_tc->recognized_len;
        ec->last_error.readagain_len = error_tc->readagain_len;
    }

    return res;
}

const char *
rb_econv_encoding_to_insert_output(rb_econv_t *ec)
{
    rb_transcoding *tc = ec->last_tc;
    const rb_transcoder *tr = tc->transcoder;

    if (tr->stateful_type == stateful_encoder)
        return tr->from_encoding;
    return tr->to_encoding;
}

static unsigned char *
allocate_converted_string(const char *str_encoding, const char *insert_encoding,
        const unsigned char *str, size_t len,
        size_t *dst_len_ptr)
{
    unsigned char *dst_str;
    size_t dst_len;
    size_t dst_bufsize = len;

    rb_econv_t *ec;
    rb_econv_result_t res;

    const unsigned char *sp;
    unsigned char *dp;

    if (dst_bufsize == 0)
        dst_bufsize += 1;

    ec = rb_econv_open(str_encoding, insert_encoding, 0);
    if (ec == NULL)
        return NULL;
    dst_str = xmalloc(dst_bufsize);
    dst_len = 0;
    sp = str;
    dp = dst_str+dst_len;
    res = rb_econv_convert(ec, &sp, str+len, &dp, dst_str+dst_bufsize, 0);
    dst_len = dp - dst_str;
    while (res == econv_destination_buffer_full) {
        if (dst_bufsize * 2 < dst_bufsize) {
            xfree(dst_str);
            rb_econv_close(ec);
            return NULL;
        }
        dst_bufsize *= 2;
        dst_str = xrealloc(dst_str, dst_bufsize);
        dp = dst_str+dst_len;
        res = rb_econv_convert(ec, &sp, str+len, &dp, dst_str+dst_bufsize, 0);
        dst_len = dp - dst_str;
    }
    if (res != econv_finished) {
        xfree(dst_str);
        rb_econv_close(ec);
        return NULL;
    }
    rb_econv_close(ec);
    *dst_len_ptr = dst_len;
    return dst_str;
}

/* result: 0:success -1:failure */
int
rb_econv_insert_output(rb_econv_t *ec, 
    const unsigned char *str, size_t len, const char *str_encoding)
{
    const char *insert_encoding = rb_econv_encoding_to_insert_output(ec);
    const unsigned char *insert_str;
    size_t insert_len;

    rb_transcoding *tc;
    const rb_transcoder *tr;

    unsigned char **buf_start_p;
    unsigned char **data_start_p;
    unsigned char **data_end_p;
    unsigned char **buf_end_p;

    size_t need;

    if (len == 0)
        return 0;

    if (encoding_equal(insert_encoding, str_encoding)) {
        insert_str = str;
        insert_len = len;
    }
    else {
        insert_str = allocate_converted_string(str_encoding, insert_encoding, str, len, &insert_len);
        if (insert_str == NULL)
            return -1;
    }

    tc = ec->last_tc;
    tr = tc->transcoder;

    need = insert_len;
    if (tr->stateful_type == stateful_encoder) {
        need += tc->readagain_len;
        if (need < insert_len)
            goto fail;
        if (ec->last_trans_index == 0) {
            buf_start_p = &ec->in_buf_start;
            data_start_p = &ec->in_data_start;
            data_end_p = &ec->in_data_end;
            buf_end_p = &ec->in_buf_end;
        }
        else {
            rb_econv_elem_t *ee = &ec->elems[ec->last_trans_index-1];
            buf_start_p = &ee->out_buf_start;
            data_start_p = &ee->out_data_start;
            data_end_p = &ee->out_data_end;
            buf_end_p = &ee->out_buf_end;
        }
    }
    else {
        rb_econv_elem_t *ee = &ec->elems[ec->last_trans_index];
        buf_start_p = &ee->out_buf_start;
        data_start_p = &ee->out_data_start;
        data_end_p = &ee->out_data_end;
        buf_end_p = &ee->out_buf_end;
    }

    if (*buf_start_p == NULL) {
        unsigned char *buf = xmalloc(need);
        *buf_start_p = buf;
        *data_start_p = buf;
        *data_end_p = buf;
        *buf_end_p = buf+need;
    }
    else if (*buf_end_p - *data_end_p < need) {
        MEMMOVE(*buf_start_p, *data_start_p, unsigned char, *data_end_p - *data_start_p);
        *data_end_p = *buf_start_p + (*data_end_p - *data_start_p);
        *data_start_p = *buf_start_p;
        if (*buf_end_p - *data_end_p < need) {
            unsigned char *buf;
            size_t s = (*data_end_p - *buf_start_p) + need;
            if (s < need)
                goto fail;
            buf = xrealloc(*buf_start_p, s);
            *data_start_p = buf;
            *data_end_p = buf + (*data_end_p - *buf_start_p);
            *buf_start_p = buf;
            *buf_end_p = buf + s;
        }
    }

    if (tr->stateful_type == stateful_encoder) {
        memcpy(*data_end_p, TRANSCODING_READBUF(tc)+tc->recognized_len, tc->readagain_len);
        *data_end_p += tc->readagain_len;
        tc->readagain_len = 0;
    }
    memcpy(*data_end_p, insert_str, insert_len);
    *data_end_p += insert_len;

    if (insert_str != str)
        xfree((void*)insert_str);
    return 0;

fail:
    if (insert_str != str)
        xfree((void*)insert_str);
    return -1;
}

void
rb_econv_close(rb_econv_t *ec)
{
    int i;

    for (i = 0; i < ec->num_trans; i++) {
        rb_transcoding_close(ec->elems[i].tc);
        if (ec->elems[i].out_buf_start)
            xfree(ec->elems[i].out_buf_start);
    }

    xfree(ec->elems);
    xfree(ec);
}

int
rb_econv_putbackable(rb_econv_t *ec)
{
    return ec->elems[0].tc->readagain_len;
}

void
rb_econv_putback(rb_econv_t *ec, unsigned char *p, int n)
{
    rb_transcoding *tc = ec->elems[0].tc;
    memcpy(p, TRANSCODING_READBUF(tc) + tc->recognized_len, n);
    tc->readagain_len -= n;
}

static VALUE
make_econv_exception(rb_econv_t *ec)
{
    VALUE mesg, exc;
    if (ec->last_error.result == econv_invalid_byte_sequence) {
        VALUE bytes = rb_str_new((const char *)ec->last_error.error_bytes_start,
                                 ec->last_error.error_bytes_len);
        VALUE dumped;
        dumped = rb_str_dump(bytes);
        mesg = rb_sprintf("invalid byte sequence: %s on %s",
                StringValueCStr(dumped),
                ec->last_error.source_encoding);
        exc = rb_exc_new3(rb_eInvalidByteSequence, mesg);
        rb_ivar_set(exc, rb_intern("source_encoding"), rb_str_new2(ec->last_error.source_encoding));
        rb_ivar_set(exc, rb_intern("destination_encoding"), rb_str_new2(ec->last_error.destination_encoding));
        rb_ivar_set(exc, rb_intern("error_bytes"), bytes);
        return exc;
    }
    if (ec->last_error.result == econv_undefined_conversion) {
        VALUE bytes = rb_str_new((const char *)ec->last_error.error_bytes_start,
                                 ec->last_error.error_bytes_len);
        VALUE dumped;
        int idx;
        dumped = rb_str_dump(bytes);
        mesg = rb_sprintf("conversion undefined: %s from %s to %s",
                StringValueCStr(dumped),
                ec->last_error.source_encoding,
                ec->last_error.destination_encoding);
        exc = rb_exc_new3(rb_eConversionUndefined, mesg);
        idx = rb_enc_find_index(ec->last_error.source_encoding);
        rb_ivar_set(exc, rb_intern("source_encoding"), rb_str_new2(ec->last_error.source_encoding));
        rb_ivar_set(exc, rb_intern("destination_encoding"), rb_str_new2(ec->last_error.destination_encoding));
        idx = rb_enc_find_index(ec->last_error.source_encoding);
        if (0 <= idx)
            rb_enc_associate_index(bytes, idx);
        rb_ivar_set(exc, rb_intern("error_char"), bytes);
        return exc;
    }
    return Qnil;
}

static void
more_output_buffer(
        VALUE destination,
        unsigned char *(*resize_destination)(VALUE, int, int),
        int max_output,
        unsigned char **out_start_ptr,
        unsigned char **out_pos,
        unsigned char **out_stop_ptr)
{
    size_t len = (*out_pos - *out_start_ptr);
    size_t new_len = (len + max_output) * 2;
    *out_start_ptr = resize_destination(destination, len, new_len);
    *out_pos = *out_start_ptr + len;
    *out_stop_ptr = *out_start_ptr + new_len;
}

static int
output_replacement_character(rb_econv_t *ec)
{
    rb_transcoding *tc = ec->last_tc;
    const rb_transcoder *tr;
    rb_encoding *enc;
    const unsigned char *replacement;
    const char *repl_enc;
    int len;
    int ret;

    tr = tc->transcoder;
    enc = rb_enc_find(tr->to_encoding);

    replacement = (const unsigned char *)get_replacement_character(enc, &len, &repl_enc);

    ret = rb_econv_insert_output(ec, replacement, len, repl_enc);
    if (ret == -1)
        return -1;

    return 0;
}

#if 1
static void
transcode_loop(const unsigned char **in_pos, unsigned char **out_pos,
	       const unsigned char *in_stop, unsigned char *out_stop,
               VALUE destination,
               unsigned char *(*resize_destination)(VALUE, int, int),
               const char *from_encoding,
               const char *to_encoding,
	       const int opt)
{
    rb_econv_t *ec;
    rb_transcoding *last_tc;
    rb_econv_result_t ret;
    unsigned char *out_start = *out_pos;
    int max_output;
    VALUE exc;

    ec = rb_econv_open(from_encoding, to_encoding, 0);
    if (!ec)
        rb_raise(rb_eArgError, "transcoding not supported (from %s to %s)", from_encoding, to_encoding);

    last_tc = ec->last_tc;
    max_output = last_tc->transcoder->max_output;

resume:
    ret = rb_econv_convert(ec, in_pos, in_stop, out_pos, out_stop, opt);
    if (ret == econv_invalid_byte_sequence) {
	/* deal with invalid byte sequence */
	/* todo: add more alternative behaviors */
	if (opt&INVALID_IGNORE) {
            goto resume;
	}
	else if (opt&INVALID_REPLACE) {
	    if (output_replacement_character(ec) == 0)
                goto resume;
	}
        exc = make_econv_exception(ec);
        rb_econv_close(ec);
	rb_exc_raise(exc);
    }
    if (ret == econv_undefined_conversion) {
	/* valid character in from encoding
	 * but no related character(s) in to encoding */
	/* todo: add more alternative behaviors */
	if (opt&UNDEF_IGNORE) {
	    goto resume;
	}
	else if (opt&UNDEF_REPLACE) {
	    if (output_replacement_character(ec) == 0)
                goto resume;
	}
        exc = make_econv_exception(ec);
        rb_econv_close(ec);
	rb_exc_raise(exc);
    }
    if (ret == econv_destination_buffer_full) {
        more_output_buffer(destination, resize_destination, max_output, &out_start, out_pos, &out_stop);
        goto resume;
    }

    rb_econv_close(ec);
    return;
}
#else
/* sample transcode_loop implementation in byte-by-byte stream style */
static void
transcode_loop(const unsigned char **in_pos, unsigned char **out_pos,
	       const unsigned char *in_stop, unsigned char *out_stop,
               VALUE destination,
               unsigned char *(*resize_destination)(VALUE, int, int),
               const char *from_encoding,
               const char *to_encoding,
	       const int opt)
{
    rb_econv_t *ec;
    rb_transcoding *last_tc;
    rb_econv_result_t ret;
    unsigned char *out_start = *out_pos;
    const unsigned char *ptr;
    int max_output;
    VALUE exc;

    ec = rb_econv_open(from_encoding, to_encoding, 0);
    if (!ec)
        rb_raise(rb_eArgError, "transcoding not supported (from %s to %s)", from_encoding, to_encoding);

    last_tc = ec->last_tc;
    max_output = ec->elems[ec->num_trans-1].tc->transcoder->max_output;

    ret = econv_source_buffer_empty;
    ptr = *in_pos;
    while (ret != econv_finished) {
        unsigned char input_byte;
        const unsigned char *p = &input_byte;

        if (ret == econv_source_buffer_empty) {
            if (ptr < in_stop) {
                input_byte = *ptr;
                ret = rb_econv_convert(ec, &p, p+1, out_pos, out_stop, ECONV_PARTIAL_INPUT);
            }
            else {
                ret = rb_econv_convert(ec, NULL, NULL, out_pos, out_stop, 0);
            }
        }
        else {
            ret = rb_econv_convert(ec, NULL, NULL, out_pos, out_stop, ECONV_PARTIAL_INPUT);
        }
        if (&input_byte != p)
            ptr += p - &input_byte;
        switch (ret) {
          case econv_invalid_byte_sequence:
            /* deal with invalid byte sequence */
            /* todo: add more alternative behaviors */
            if (opt&INVALID_IGNORE) {
                break;
            }
            else if (opt&INVALID_REPLACE) {
                if (output_replacement_character(ec) == 0)
                    break;
            }
            exc = make_econv_exception(ec);
            rb_econv_close(ec);
            rb_exc_raise(exc);
            break;

          case econv_undefined_conversion:
            /* valid character in from encoding
             * but no related character(s) in to encoding */
            /* todo: add more alternative behaviors */
            if (opt&UNDEF_IGNORE) {
                break;
            }
            else if (opt&UNDEF_REPLACE) {
                if (output_replacement_character(ec) == 0)
                    break;
            }
            exc = make_econv_exception(ec);
            rb_econv_close(ec);
            rb_exc_raise(exc);
            break;

          case econv_destination_buffer_full:
            more_output_buffer(destination, resize_destination, max_output, &out_start, out_pos, &out_stop);
            break;

          case econv_source_buffer_empty:
            break;

          case econv_finished:
            break;
        }
    }
    rb_econv_close(ec);
    *in_pos = in_stop;
    return;
}
#endif


/*
 *  String-specific code
 */

static unsigned char *
str_transcoding_resize(VALUE destination, int len, int new_len)
{
    rb_str_resize(destination, new_len);
    return (unsigned char *)RSTRING_PTR(destination);
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
	    rb_raise(rb_eArgError, "unknown value for invalid character option");
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
	    rb_raise(rb_eArgError, "unknown value for undefined character option");
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

    fromp = sp = (unsigned char *)RSTRING_PTR(str);
    slen = RSTRING_LEN(str);
    blen = slen + 30; /* len + margin */
    dest = rb_str_tmp_new(blen);
    bp = (unsigned char *)RSTRING_PTR(dest);

    transcode_loop(&fromp, &bp, (sp+slen), (bp+blen), dest, str_transcoding_resize, from_e, to_e, options);
    if (fromp != sp+slen) {
        rb_raise(rb_eArgError, "not fully converted, %"PRIdPTRDIFF" bytes left", sp+slen-fromp);
    }
    buf = (unsigned char *)RSTRING_PTR(dest);
    *bp = '\0';
    rb_str_set_len(dest, bp - buf);

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

static void
econv_free(rb_econv_t *ec)
{
    rb_econv_close(ec);
}

static VALUE
econv_s_allocate(VALUE klass)
{
    return Data_Wrap_Struct(klass, NULL, econv_free, NULL);
}

static rb_encoding *
make_dummy_encoding(const char *name)
{
    rb_encoding *enc;
    int idx;
    idx = rb_define_dummy_encoding(name);
    enc = rb_enc_from_index(idx);
    return enc;
}

/*
 * call-seq:
 *   Encoding::Converter.new(source_encoding, destination_encoding)
 *   Encoding::Converter.new(source_encoding, destination_encoding, flags)
 *
 * possible flags:
 *   Encoding::Converter::UNIVERSAL_NEWLINE_DECODER # convert CRLF and CR to LF at last
 *   Encoding::Converter::CRLF_NEWLINE_ENCODER      # convert LF to CRLF at first
 *   Encoding::Converter::CR_NEWLINE_ENCODER        # convert LF to CR at first
 *
 * Encoding::Converter.new creates an instance of Encoding::Converter.
 *
 * source_encoding and destination_encoding should be a string.
 * flags should be an integer.
 *
 * example:
 *   # UTF-16BE to UTF-8
 *   ec = Encoding::Converter.new("UTF-16BE", "UTF-8")
 *
 *   # (1) convert UTF-16BE to UTF-8
 *   # (2) convert CRLF and CR to LF
 *   ec = Encoding::Converter.new("UTF-16BE", "UTF-8", Encoding::Converter::UNIVERSAL_NEWLINE_DECODER)
 *
 *   # (1) convert LF to CRLF
 *   # (2) convert UTF-8 to UTF-16BE 
 *   ec = Encoding::Converter.new("UTF-8", "UTF-16BE", Encoding::Converter::CRLF_NEWLINE_ENCODER)
 *
 */
static VALUE
econv_init(int argc, VALUE *argv, VALUE self)
{
    VALUE source_encoding, destination_encoding, flags_v;
    int sidx, didx;
    const char *sname, *dname;
    rb_encoding *senc, *denc;
    rb_econv_t *ec;
    int flags;

    rb_scan_args(argc, argv, "21", &source_encoding, &destination_encoding, &flags_v);

    if (flags_v == Qnil)
        flags = 0;
    else
        flags = NUM2INT(flags_v);

    senc = NULL;
    sidx = rb_to_encoding_index(source_encoding);
    if (0 <= sidx) {
        senc = rb_enc_from_index(sidx);
    }
    else {
        StringValue(source_encoding);
    }

    denc = NULL;
    didx = rb_to_encoding_index(destination_encoding);
    if (0 <= didx) {
        denc = rb_enc_from_index(didx);
    }
    else {
        StringValue(destination_encoding);
    }

    sname = senc ? senc->name : StringValueCStr(source_encoding);
    dname = denc ? denc->name : StringValueCStr(destination_encoding);

    if (DATA_PTR(self)) {
        rb_raise(rb_eTypeError, "already initialized");
    }

    ec = rb_econv_open(sname, dname, flags);
    if (!ec) {
        rb_raise(rb_eArgError, "encoding convewrter not supported (from %s to %s)", sname, dname);
    }

    if (*sname && *dname) { /* check "" to "universal_newline" */
        if (!senc)
            senc = make_dummy_encoding(sname);
        if (!denc)
            denc = make_dummy_encoding(dname);
    }

    ec->source_encoding = senc;
    ec->destination_encoding = denc;

    ec->source_encoding_name = ec->elems[0].tc->transcoder->from_encoding;
    ec->destination_encoding_name = ec->last_tc->transcoder->to_encoding;

    DATA_PTR(self) = ec;

    return self;
}

static VALUE
econv_inspect(VALUE self)
{
    const char *cname = rb_obj_classname(self);
    rb_econv_t *ec = DATA_PTR(self);

    if (!ec)
        return rb_sprintf("#<%s: uninitialized>", cname);
    else
        return rb_sprintf("#<%s: %s to %s>", cname,
            ec->source_encoding_name,
            ec->destination_encoding_name);
}

#define IS_ECONV(obj) (RDATA(obj)->dfree == (RUBY_DATA_FUNC)econv_free)

static rb_econv_t *
check_econv(VALUE self)
{
    Check_Type(self, T_DATA);
    if (!IS_ECONV(self)) {
        rb_raise(rb_eTypeError, "wrong argument type %s (expected Encoding::Converter)",
                 rb_class2name(CLASS_OF(self)));
    }
    if (!DATA_PTR(self)) {
        rb_raise(rb_eTypeError, "uninitialized encoding converter");
    }
    return DATA_PTR(self);
}

/*
 * call-seq:
 *   source_encoding -> encoding
 *
 * returns source encoding as Encoding object.
 */
static VALUE
econv_source_encoding(VALUE self)
{
    rb_econv_t *ec = check_econv(self);
    if (!ec->source_encoding) 
        return Qnil;
    return rb_enc_from_encoding(ec->source_encoding);
}

/*
 * call-seq:
 *   destination_encoding -> encoding
 *
 * returns destination encoding as Encoding object.
 */
static VALUE
econv_destination_encoding(VALUE self)
{
    rb_econv_t *ec = check_econv(self);
    if (!ec->destination_encoding) 
        return Qnil;
    return rb_enc_from_encoding(ec->destination_encoding);
}

static VALUE
econv_result_to_symbol(rb_econv_result_t res)
{
    switch (res) {
      case econv_invalid_byte_sequence: return ID2SYM(rb_intern("invalid_byte_sequence"));
      case econv_undefined_conversion: return ID2SYM(rb_intern("undefined_conversion"));
      case econv_destination_buffer_full: return ID2SYM(rb_intern("destination_buffer_full"));
      case econv_source_buffer_empty: return ID2SYM(rb_intern("source_buffer_empty"));
      case econv_finished: return ID2SYM(rb_intern("finished"));
      case econv_output_followed_by_input: return ID2SYM(rb_intern("output_followed_by_input"));
      default: return INT2NUM(res); /* should not be reached */
    }
}

/*
 * call-seq:
 *   primitive_convert(source_buffer, destination_buffer, destination_byteoffset, destination_bytesize) -> symbol
 *   primitive_convert(source_buffer, destination_buffer, destination_byteoffset, destination_bytesize, flags) -> symbol
 *
 * possible flags:
 *   Encoding::Converter::PARTIAL_INPUT # source buffer may be part of larger source
 *   Encoding::Converter::OUTPUT_FOLLOWED_BY_INPUT # stop conversion after output before input
 *
 * possible results:
 *    :invalid_byte_sequence
 *    :undefined_conversion
 *    :output_followed_by_input
 *    :destination_buffer_full
 *    :source_buffer_empty
 *    :finished
 *
 * primitive_convert converts source_buffer into destination_buffer.
 *
 * source_buffer and destination_buffer should be a string.
 * destination_byteoffset should be an integer or nil.
 * destination_bytesize and flags should be an integer.
 *
 * primitive_convert convert the content of source_buffer from beginning
 * and store the result into destination_buffer.
 *
 * destination_byteoffset and destination_bytesize specify the region which
 * the converted result is stored.
 * destination_byteoffset specifies the start position in destination_buffer in bytes.
 * If destination_byteoffset is nil,
 * destination_buffer.bytesize is used for appending the result.
 * destination_bytesize specifies maximum number of bytes.
 * After conversion, destination_buffer is resized to
 * destination_byteoffset + actually converted number of bytes.
 * Also destination_buffer's encoding is set to destination_encoding.
 *
 * primitive_convert drops the first part of source_buffer.
 * the dropped part is converted in destination_buffer or
 * buffered in Encoding::Converter object.
 *
 * primitive_convert stops conversion when one of following condition met.
 * - invalid byte sequence found in source buffer (:invalid_byte_sequence)
 * - character not representable in output encoding (:undefined_conversion)
 * - after some output is generated, before input is done (:output_followed_by_input)
 *   this occur only when OUTPUT_FOLLOWED_BY_INPUT is specified.
 * - destination buffer is full (:destination_buffer_full)
 * - source buffer is empty (:source_buffer_empty)
 *   this occur only when PARTIAL_INPUT is specified.
 * - conversion is finished (:finished)
 *
 * example:
 *   ec = Encoding::Converter.new("UTF-8", "UTF-16BE")
 *   ret = ec.primitive_convert(src="pi", dst="", 100)
 *   p [ret, src, dst] #=> [:finished, "", "\x00p\x00i"]
 *
 *   ec = Encoding::Converter.new("UTF-8", "UTF-16BE")
 *   ret = ec.primitive_convert(src="pi", dst="", 1)
 *   p [ret, src, dst] #=> [:destination_buffer_full, "i", "\x00"]
 *   ret = ec.primitive_convert(src, dst="", 1)
 *   p [ret, src, dst] #=> [:destination_buffer_full, "", "p"]
 *   ret = ec.primitive_convert(src, dst="", 1)
 *   p [ret, src, dst] #=> [:destination_buffer_full, "", "\x00"]
 *   ret = ec.primitive_convert(src, dst="", 1)
 *   p [ret, src, dst] #=> [:finished, "", "i"]
 *
 */
static VALUE
econv_primitive_convert(int argc, VALUE *argv, VALUE self)
{
    VALUE input, output, output_byteoffset_v, output_bytesize_v, flags_v;
    rb_econv_t *ec = check_econv(self);
    rb_econv_result_t res;
    const unsigned char *ip, *is;
    unsigned char *op, *os;
    long output_byteoffset, output_bytesize;
    unsigned long output_byteend;
    int flags;

    rb_scan_args(argc, argv, "41", &input, &output, &output_byteoffset_v, &output_bytesize_v, &flags_v);

    if (output_byteoffset_v == Qnil)
        output_byteoffset = 0;
    else
        output_byteoffset = NUM2LONG(output_byteoffset_v);

    output_bytesize = NUM2LONG(output_bytesize_v);

    if (flags_v == Qnil)
        flags = 0;
    else
        flags = NUM2INT(flags_v);

    StringValue(output);
    StringValue(input);
    rb_str_modify(output);

    if (output_byteoffset_v == Qnil)
        output_byteoffset = RSTRING_LEN(output);

    if (output_byteoffset < 0)
        rb_raise(rb_eArgError, "negative output_byteoffset");

    if (RSTRING_LEN(output) < output_byteoffset)
        rb_raise(rb_eArgError, "output_byteoffset too big");

    if (output_bytesize < 0)
        rb_raise(rb_eArgError, "negative output_bytesize");

    output_byteend = (unsigned long)output_byteoffset +
                     (unsigned long)output_bytesize;

    if (output_byteend < (unsigned long)output_byteoffset ||
        LONG_MAX < output_byteend)
        rb_raise(rb_eArgError, "output_byteoffset+output_bytesize too big");

    if (rb_str_capacity(output) < output_byteend)
        rb_str_resize(output, output_byteend);

    ip = (const unsigned char *)RSTRING_PTR(input);
    is = ip + RSTRING_LEN(input);

    op = (unsigned char *)RSTRING_PTR(output) + output_byteoffset;
    os = op + output_bytesize;

    res = rb_econv_convert(ec, &ip, is, &op, os, flags);
    rb_str_set_len(output, op-(unsigned char *)RSTRING_PTR(output));
    rb_str_drop_bytes(input, ip - (unsigned char *)RSTRING_PTR(input));

    if (ec->destination_encoding) {
        rb_enc_associate(output, ec->destination_encoding);
    }

    return econv_result_to_symbol(res);
}

/*
 * call-seq:
 *   primitive_errinfo -> array
 *
 * primitive_errinfo returns a precious information of last error result
 * as a 6-elements array:
 *
 *   [result, enc1, enc2, error_bytes, readagain_bytes, partial_input]
 *
 * result is the last result of primitive_convert.
 *
 * partial_input is :partial_input or nil.
 * :partial_input means that Encoding::Converter::PARTIAL_INPUT is specified
 * for primitive_convert.
 *
 * Other elements are only meaningful when result is
 * :invalid_byte_sequence or :undefined_conversion.
 *
 * enc1 and enc2 indicats a conversion step as pair of strings.
 * For example, EUC-JP to ISO-8859-1 is
 * converted as EUC-JP -> UTF-8 -> ISO-8859-1.
 * So [enc1, enc2] is ["EUC-JP", "UTF-8"] or ["UTF-8", "ISO-8859-1"].
 *
 * error_bytes and readagain_bytes indicats the byte sequences which causes the error.
 * error_bytes is discarded portion.
 * readagain_bytes is buffered portion which is read again on next conversion.
 *
 * Example:
 *
 *   # \xff is invalid as EUC-JP.
 *   ec = Encoding::Converter.new("EUC-JP", "Shift_JIS")
 *   ec.primitive_convert(src="\xff", dst="", nil, 10)                       
 *   p ec.primitive_errinfo
 *   #=> [:invalid_byte_sequence, "EUC-JP", "UTF-8", "\xFF", "", nil]
 *
 *   # HIRAGANA LETTER A (\xa4\xa2 in EUC-JP) is not representable in ISO-8859-1.
 *   # Since this error is occur in UTF-8 to ISO-8859-1 conversion,
 *   # error_bytes is HIRAGANA LETTER A in UTF-8 (\xE3\x81\x82).
 *   ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
 *   ec.primitive_convert(src="\xa4\xa2", dst="", nil, 10)
 *   p ec.primitive_errinfo
 *   #=> [:undefined_conversion, "UTF-8", "ISO-8859-1", "\xE3\x81\x82", "", nil]
 *
 *   # partial character is invalid
 *   ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
 *   ec.primitive_convert(src="\xa4", dst="", nil, 10)
 *   p ec.primitive_errinfo
 *   #=> [:invalid_byte_sequence, "EUC-JP", "UTF-8", "\xA4", "", nil]
 *
 *   # Encoding::Converter::PARTIAL_INPUT prevents invalid errors by
 *   # partial characters.
 *   ec = Encoding::Converter.new("EUC-JP", "ISO-8859-1")
 *   ec.primitive_convert(src="\xa4", dst="", nil, 10, Encoding::Converter::PARTIAL_INPUT)                 
 *   p ec.primitive_errinfo
 *   #=> [:source_buffer_empty, nil, nil, nil, nil, :partial_input]
 *
 *   # \xd8\x00\x00@ is invalid as UTF-16BE because
 *   # no low surrogate after high surrogate (\xd8\x00).
 *   # It is detected by 3rd byte (\00) which is part of next character.
 *   # So the high surrogate (\xd8\x00) is discarded and
 *   # the 3rd byte is read again later.
 *   # Since the byte is buffered in ec, it is dropped from src.
 *   ec = Encoding::Converter.new("UTF-16BE", "UTF-8")
 *   ec.primitive_convert(src="\xd8\x00\x00@", dst="", nil, 10)
 *   p ec.primitive_errinfo
 *   #=> [:invalid_byte_sequence, "UTF-16BE", "UTF-8", "\xD8\x00", "\x00", nil]
 *   p src
 *   #=> "@"
 *
 *   # Similar to UTF-16BE, \x00\xd8@\x00 is invalid as UTF-16LE.
 *   # The problem is detected by 4th byte.
 *   ec = Encoding::Converter.new("UTF-16LE", "UTF-8")
 *   ec.primitive_convert(src="\x00\xd8@\x00", dst="", nil, 10)
 *   p ec.primitive_errinfo
 *   #=> [:invalid_byte_sequence, "UTF-16LE", "UTF-8", "\x00\xD8", "@\x00", nil]
 *   p src
 *   #=> ""
 *
 */
static VALUE
econv_primitive_errinfo(VALUE self)
{
    rb_econv_t *ec = check_econv(self);

    VALUE ary;

    ary = rb_ary_new2(6);

    rb_ary_store(ary, 0, econv_result_to_symbol(ec->last_error.result));

    if (ec->last_error.source_encoding)
        rb_ary_store(ary, 1, rb_str_new2(ec->last_error.source_encoding));

    if (ec->last_error.destination_encoding)
        rb_ary_store(ary, 2, rb_str_new2(ec->last_error.destination_encoding));

    if (ec->last_error.error_bytes_start) {
        rb_ary_store(ary, 3, rb_str_new((const char *)ec->last_error.error_bytes_start, ec->last_error.error_bytes_len));
        rb_ary_store(ary, 4, rb_str_new((const char *)ec->last_error.error_bytes_start + ec->last_error.error_bytes_len, ec->last_error.readagain_len));
    }

    rb_ary_store(ary, 5, ec->last_error.partial_input ? ID2SYM(rb_intern("partial_input")) : Qnil);

    return ary;
}

static VALUE
econv_primitive_insert_output(VALUE self, VALUE string)
{
    const char *insert_enc;

    int ret;

    rb_econv_t *ec = check_econv(self);

    StringValue(string);
    insert_enc = rb_econv_encoding_to_insert_output(ec);
    string = rb_str_transcode(string, rb_enc_from_encoding(rb_enc_find(insert_enc)));

    ret = rb_econv_insert_output(ec, (const unsigned char *)RSTRING_PTR(string), RSTRING_LEN(string), insert_enc);

    if (ret == -1)
        return Qfalse;
    return Qtrue;
}

void
rb_econv_check_error(rb_econv_t *ec)
{
    VALUE exc;

    exc = make_econv_exception(ec);
    if (NIL_P(exc))
        return;
    rb_exc_raise(exc);
}

static VALUE
ecerr_source_encoding(VALUE self)
{
    return rb_attr_get(self, rb_intern("source_encoding"));
}

static VALUE
ecerr_destination_encoding(VALUE self)
{
    return rb_attr_get(self, rb_intern("destination_encoding"));
}

static VALUE
ecerr_error_char(VALUE self)
{
    return rb_attr_get(self, rb_intern("error_char"));
}

static VALUE
ecerr_error_bytes(VALUE self)
{
    return rb_attr_get(self, rb_intern("error_bytes"));
}

void
Init_transcode(void)
{
    rb_eConversionUndefined = rb_define_class_under(rb_cEncoding, "ConversionUndefined", rb_eStandardError);
    rb_eInvalidByteSequence = rb_define_class_under(rb_cEncoding, "InvalidByteSequence", rb_eStandardError);

    transcoder_table = st_init_strcasetable();

    sym_invalid = ID2SYM(rb_intern("invalid"));
    sym_undef = ID2SYM(rb_intern("undef"));
    sym_ignore = ID2SYM(rb_intern("ignore"));
    sym_replace = ID2SYM(rb_intern("replace"));

    rb_define_method(rb_cString, "encode", str_encode, -1);
    rb_define_method(rb_cString, "encode!", str_encode_bang, -1);

    rb_cEncodingConverter = rb_define_class_under(rb_cEncoding, "Converter", rb_cData);
    rb_define_alloc_func(rb_cEncodingConverter, econv_s_allocate);
    rb_define_method(rb_cEncodingConverter, "initialize", econv_init, -1);
    rb_define_method(rb_cEncodingConverter, "inspect", econv_inspect, 0);
    rb_define_method(rb_cEncodingConverter, "source_encoding", econv_source_encoding, 0);
    rb_define_method(rb_cEncodingConverter, "destination_encoding", econv_destination_encoding, 0);
    rb_define_method(rb_cEncodingConverter, "primitive_convert", econv_primitive_convert, -1);
    rb_define_method(rb_cEncodingConverter, "primitive_errinfo", econv_primitive_errinfo, 0);
    rb_define_method(rb_cEncodingConverter, "primitive_insert_output", econv_primitive_insert_output, 1);
    rb_define_const(rb_cEncodingConverter, "PARTIAL_INPUT", INT2FIX(ECONV_PARTIAL_INPUT));
    rb_define_const(rb_cEncodingConverter, "OUTPUT_FOLLOWED_BY_INPUT", INT2FIX(ECONV_OUTPUT_FOLLOWED_BY_INPUT));
    rb_define_const(rb_cEncodingConverter, "UNIVERSAL_NEWLINE_DECODER", INT2FIX(ECONV_UNIVERSAL_NEWLINE_DECODER));
    rb_define_const(rb_cEncodingConverter, "CRLF_NEWLINE_ENCODER", INT2FIX(ECONV_CRLF_NEWLINE_ENCODER));
    rb_define_const(rb_cEncodingConverter, "CR_NEWLINE_ENCODER", INT2FIX(ECONV_CR_NEWLINE_ENCODER));

    rb_define_method(rb_eConversionUndefined, "source_encoding", ecerr_source_encoding, 0);
    rb_define_method(rb_eConversionUndefined, "destination_encoding", ecerr_destination_encoding, 0);
    rb_define_method(rb_eConversionUndefined, "error_char", ecerr_error_char, 0);

    rb_define_method(rb_eInvalidByteSequence, "source_encoding", ecerr_source_encoding, 0);
    rb_define_method(rb_eInvalidByteSequence, "destination_encoding", ecerr_destination_encoding, 0);
    rb_define_method(rb_eInvalidByteSequence, "error_bytes", ecerr_error_bytes, 0);
}
