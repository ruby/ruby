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
#define INVALID_IGNORE 0x1
#define INVALID_REPLACE 0x2
#define UNDEF_IGNORE 0x10
#define UNDEF_REPLACE 0x20
#define PARTIAL_INPUT 0x100

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

static const rb_transcoder *
load_transcoder(transcoder_entry_t *entry)
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
get_replacement_character(rb_encoding *enc, int *len_ret)
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
        return "\xEF\xBF\xBD";
    }
    else if (utf16be_encoding == enc) {
        *len_ret = 2;
        return "\xFF\xFD";
    }
    else if (utf16le_encoding == enc) {
        *len_ret = 2;
        return "\xFD\xFF";
    }
    else if (utf32be_encoding == enc) {
        *len_ret = 4;
        return "\x00\x00\xFF\xFD";
    }
    else if (utf32le_encoding == enc) {
        *len_ret = 4;
        return "\xFD\xFF\x00\x00";
    }
    else {
        *len_ret = 1;
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

static rb_trans_result_t
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
    const BYTE_LOOKUP *next_table;
    VALUE next_info;
    unsigned char next_byte;

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
    next_table = tc->next_table;
    next_info = tc->next_info;
    next_byte = tc->next_byte;

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
        tc->next_table = next_table; \
        tc->next_info = next_info; \
        tc->next_byte = next_byte; \
        return ret; \
        resume_label ## num:; \
    } while (0)

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
    }

    while (1) {
        if (in_stop <= in_p) {
            if (!(opt & PARTIAL_INPUT))
                break;
            SUSPEND(transcode_ibuf_empty, 7);
            continue;
        }

        tc->recognized_len = 0;
        inchar_start = in_p;
	next_table = tr->conv_tree_start;
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
            while (out_stop - out_p < 1) { SUSPEND(transcode_obuf_full, 3); }
	    *out_p++ = next_byte;
	    continue;
	  case 0x00: case 0x04: case 0x08: case 0x0C:
	  case 0x10: case 0x14: case 0x18: case 0x1C:
	    while (in_p >= in_stop) {
                if (!(opt & PARTIAL_INPUT))
                    goto invalid;
                SUSPEND(transcode_ibuf_empty, 5);
	    }
	    next_byte = (unsigned char)*in_p++;
	    next_table = (const BYTE_LOOKUP *)next_info;
	    goto follow_byte;
	  case ZERObt: /* drop input */
	    continue;
	  case ONEbt:
            while (out_stop - out_p < 1) { SUSPEND(transcode_obuf_full, 9); }
	    *out_p++ = getBT1(next_info);
	    continue;
	  case TWObt:
            while (out_stop - out_p < 2) { SUSPEND(transcode_obuf_full, 10); }
	    *out_p++ = getBT1(next_info);
	    *out_p++ = getBT2(next_info);
	    continue;
	  case THREEbt:
            while (out_stop - out_p < 3) { SUSPEND(transcode_obuf_full, 11); }
	    *out_p++ = getBT1(next_info);
	    *out_p++ = getBT2(next_info);
	    *out_p++ = getBT3(next_info);
	    continue;
	  case FOURbt:
            while (out_stop - out_p < 4) { SUSPEND(transcode_obuf_full, 12); }
	    *out_p++ = getBT0(next_info);
	    *out_p++ = getBT1(next_info);
	    *out_p++ = getBT2(next_info);
	    *out_p++ = getBT3(next_info);
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
            while (out_stop - out_p < tr->max_output) { SUSPEND(transcode_obuf_full, 13); }
	    out_p += (VALUE)(*tr->func_io)(tc, next_info, out_p);
	    break;
	  case FUNso:
            {
                const unsigned char *char_start;
                size_t char_len;
                while (out_stop - out_p < tr->max_output) { SUSPEND(transcode_obuf_full, 14); }
                char_start = transcode_char_start(tc, *in_pos, inchar_start, in_p, &char_len);
                out_p += (VALUE)(*tr->func_so)(tc, char_start, (size_t)char_len, out_p);
                break;
            }
	  case INVALID:
            if (tc->recognized_len + (in_p - inchar_start) <= unitlen) {
                while ((opt & PARTIAL_INPUT) && tc->recognized_len + (in_stop - inchar_start) < unitlen) {
                    in_p = in_stop;
                    SUSPEND(transcode_ibuf_empty, 8);
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
        SUSPEND(transcode_invalid_input, 1);
        continue;

      undef:
        SUSPEND(transcode_undefined_conversion, 2);
        continue;
    }

    /* cleanup */
    if (tr->finish_func) {
	while (out_stop - out_p < tr->max_output) {
            SUSPEND(transcode_obuf_full, 4);
	}
        out_p += tr->finish_func(tc, out_p);
    }
    while (1)
        SUSPEND(transcode_finished, 6);
#undef SUSPEND
}

static rb_trans_result_t
transcode_restartable(const unsigned char **in_pos, unsigned char **out_pos,
                      const unsigned char *in_stop, unsigned char *out_stop,
                      rb_transcoding *tc,
                      const int opt)
{
    if (tc->readagain_len) {
        unsigned char *readagain_buf = ALLOCA_N(unsigned char, tc->readagain_len);
        const unsigned char *readagain_pos = readagain_buf;
        const unsigned char *readagain_stop = readagain_buf + tc->readagain_len;
        rb_trans_result_t res;

        MEMCPY(readagain_buf, TRANSCODING_READBUF(tc) + tc->recognized_len,
               unsigned char, tc->readagain_len);
        tc->readagain_len = 0;
        res = transcode_restartable0(&readagain_pos, out_pos, readagain_stop, out_stop, tc, opt|PARTIAL_INPUT);
        if (res != transcode_ibuf_empty) {
            MEMCPY(TRANSCODING_READBUF(tc) + tc->recognized_len + tc->readagain_len,
                   readagain_pos, unsigned char, readagain_stop - readagain_pos);
            tc->readagain_len += readagain_stop - readagain_pos;
            return res;
        }
    }
    return transcode_restartable0(in_pos, out_pos, in_stop, out_stop, tc, opt);
}

static rb_transcoding *
rb_transcoding_open(const char *from, const char *to, int flags)
{
    rb_transcoding *tc;
    const rb_transcoder *tr;

    transcoder_entry_t *entry;

    entry = get_transcoder_entry(from, to);
    if (!entry)
        return NULL;

    tr = load_transcoder(entry);
    if (!tr)
        return NULL;

    tc = ALLOC(rb_transcoding);
    tc->transcoder = tr;
    tc->flags = flags;
    memset(tc->stateful, 0, sizeof(tc->stateful));
    tc->resume_position = 0;
    tc->recognized_len = 0;
    tc->readagain_len = 0;
    if (sizeof(tc->readbuf.ary) < tr->max_input) {
        tc->readbuf.ptr = xmalloc(tr->max_input);
    }
    return tc;
}

static rb_trans_result_t
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
    xfree(tc);
}

static void
trans_open_i(const char *from, const char *to, int depth, void *arg)
{
    rb_trans_t **tsp = (rb_trans_t **)arg;
    rb_trans_t *ts;
    int i;

    if (!*tsp) {
        ts = *tsp = ALLOC(rb_trans_t);
        ts->num_trans = depth+1;
        ts->elems = ALLOC_N(rb_trans_elem_t, ts->num_trans);
        ts->num_finished = 0;
        for (i = 0; i < ts->num_trans; i++) {
            ts->elems[i].from = NULL;
            ts->elems[i].to = NULL;
            ts->elems[i].tc = NULL;
            ts->elems[i].out_buf_start = NULL;
            ts->elems[i].out_data_start = NULL;
            ts->elems[i].out_data_end = NULL;
            ts->elems[i].out_buf_end = NULL;
            ts->elems[i].last_result = transcode_ibuf_empty;
        }
    }
    else {
        ts = *tsp;
    }
    ts->elems[depth].from = from;
    ts->elems[depth].to = to;

}

static rb_trans_t *
rb_trans_open(const char *from, const char *to, int flags)
{
    rb_trans_t *ts = NULL;
    int i;
    rb_transcoding *tc;

    transcode_search_path(from, to, trans_open_i, (void *)&ts);

    if (!ts)
        return NULL;

    for (i = 0; i < ts->num_trans; i++) {
        tc = rb_transcoding_open(ts->elems[i].from, ts->elems[i].to, 0);
        if (!tc) {
            xfree(ts);
            rb_raise(rb_eArgError, "converter open failed (from %s to %s)", from, to);
        }
        ts->elems[i].tc = tc;
    }

    for (i = 0; i < ts->num_trans-1; i++) {
        int bufsize = 4096;
        unsigned char *p;
        p = xmalloc(bufsize);
        ts->elems[i].out_buf_start = p;
        ts->elems[i].out_buf_end = p + bufsize;
        ts->elems[i].out_data_start = p;
        ts->elems[i].out_data_end = p;
    }

    return ts;
}

static int
trans_sweep(rb_trans_t *ts,
    const unsigned char **input_ptr, const unsigned char *input_stop,
    unsigned char **output_ptr, unsigned char *output_stop,
    int flags,
    int start)
{
    int try;
    int i, f;

    const unsigned char **ipp, *is, *iold;
    unsigned char **opp, *os, *oold;
    rb_trans_result_t res;

    try = 1;
    while (try) {
        try = 0;
        for (i = start; i < ts->num_trans; i++) {
            rb_trans_elem_t *te = &ts->elems[i];

            if (i == 0) {
                ipp = input_ptr;
                is = input_stop;
            }
            else {
                rb_trans_elem_t *prev_te = &ts->elems[i-1];
                ipp = (const unsigned char **)&prev_te->out_data_start;
                is = prev_te->out_data_end;
            }

            if (!te->out_buf_start) {
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
            if (ts->num_finished != i)
                f |= PARTIAL_INPUT;
            iold = *ipp;
            oold = *opp;
            te->last_result = res = rb_transcoding_convert(te->tc, ipp, is, opp, os, f);
            if (iold != *ipp || oold != *opp)
                try = 1;

            switch (res) {
              case transcode_invalid_input:
              case transcode_undefined_conversion:
                return i;

              case transcode_obuf_full:
              case transcode_ibuf_empty:
                break;

              case transcode_finished:
                ts->num_finished = i+1;
                break;
            }
        }
    }
    return -1;
}

static rb_trans_result_t
rb_trans_conv(rb_trans_t *ts,
    const unsigned char **input_ptr, const unsigned char *input_stop,
    unsigned char **output_ptr, unsigned char *output_stop,
    int flags)
{
    int i;
    int start, err_index;

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

    err_index = -1;
    for (i = ts->num_trans-1; 0 <= i; i--) {
        if (ts->elems[i].last_result != transcode_ibuf_empty) {
            err_index = i;
            break;
        }
    }

    do {
        start = err_index + 1;
        err_index = trans_sweep(ts, input_ptr, input_stop, output_ptr, output_stop, flags, start);
    } while (err_index != -1 && err_index != ts->num_trans-1);

    for (i = ts->num_trans-1; 0 <= i; i--) {
        if (ts->elems[i].last_result != transcode_ibuf_empty) {
            rb_trans_result_t res = ts->elems[i].last_result;
            ts->elems[i].last_result = transcode_ibuf_empty;
            return res;
        }
    }
    return transcode_ibuf_empty;
}

static void
rb_trans_close(rb_trans_t *ts)
{
    int i;

    for (i = 0; i < ts->num_trans; i++) {
        rb_transcoding_close(ts->elems[i].tc);
        if (ts->elems[i].out_buf_start)
            xfree(ts->elems[i].out_buf_start);
    }

    xfree(ts->elems);
    xfree(ts);
}

static void
more_output_buffer(
        VALUE destination,
        unsigned char *(*resize_destination)(VALUE, int, int),
        rb_trans_t *ts,
        unsigned char **out_start_ptr,
        unsigned char **out_pos,
        unsigned char **out_stop_ptr)
{
    size_t len = (*out_pos - *out_start_ptr);
    size_t new_len = (len + ts->elems[ts->num_trans-1].tc->transcoder->max_output) * 2;
    *out_start_ptr = resize_destination(destination, len, new_len);
    *out_pos = *out_start_ptr + len;
    *out_stop_ptr = *out_start_ptr + new_len;
}

static void
output_replacement_character(
        VALUE destination,
        unsigned char *(*resize_destination)(VALUE, int, int),
        rb_trans_t *ts,
        unsigned char **out_start_ptr,
        unsigned char **out_pos,
        unsigned char **out_stop_ptr)

{
    rb_transcoding *tc;
    const rb_transcoder *tr;
    int max_output;
    rb_encoding *enc;
    const char *replacement;
    int len;

    tc = ts->elems[ts->num_trans-1].tc;
    tr = tc->transcoder;
    max_output = tr->max_output;
    enc = rb_enc_find(tr->to_encoding);

    /*
     * Assumption for stateful encoding:
     *
     * - The replacement character can be output on resetted state and doesn't
     *   change the state.
     * - it is acceptable that extra state changing sequence if the replacement
     *   character contains a state changing sequence.
     *
     * Currently the replacement character for stateful encoding such as
     * ISO-2022-JP is "?" and it has no state changing sequence.
     * So the extra state changing sequence don't occur.
     *
     * Thease assumption may be removed in future.
     * It needs to scan the replacement character to check
     * state changing sequences in the replacement character.
     */

    if (tr->resetstate_func) {
        if (*out_stop_ptr - *out_pos < max_output)
            more_output_buffer(destination, resize_destination, ts, out_start_ptr, out_pos, out_stop_ptr);
        *out_pos += tr->resetstate_func(tc, *out_pos);
    }

    if (*out_stop_ptr - *out_pos < max_output)
        more_output_buffer(destination, resize_destination, ts, out_start_ptr, out_pos, out_stop_ptr);

    replacement = get_replacement_character(enc, &len);

    memcpy(*out_pos, replacement, len);

    *out_pos += len;
    return;
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
    rb_trans_t *ts;
    rb_trans_result_t ret;
    unsigned char *out_start = *out_pos;
    int max_output;

    ts = rb_trans_open(from_encoding, to_encoding, 0);
    if (!ts)
        rb_raise(rb_eArgError, "transcoding not supported (from %s to %s)", from_encoding, to_encoding);

    max_output = ts->elems[ts->num_trans-1].tc->transcoder->max_output;

resume:
    ret = rb_trans_conv(ts, in_pos, in_stop, out_pos, out_stop, opt);
    if (ret == transcode_invalid_input) {
	/* deal with invalid byte sequence */
	/* todo: add more alternative behaviors */
	if (opt&INVALID_IGNORE) {
            goto resume;
	}
	else if (opt&INVALID_REPLACE) {
	    output_replacement_character(destination, resize_destination, ts, &out_start, out_pos, &out_stop);
            goto resume;
	}
        rb_trans_close(ts);
	rb_raise(rb_eInvalidByteSequence, "invalid byte sequence");
    }
    if (ret == transcode_undefined_conversion) {
	/* valid character in from encoding
	 * but no related character(s) in to encoding */
	/* todo: add more alternative behaviors */
	if (opt&UNDEF_IGNORE) {
	    goto resume;
	}
	else if (opt&UNDEF_REPLACE) {
	    output_replacement_character(destination, resize_destination, ts, &out_start, out_pos, &out_stop);
	    goto resume;
	}
        rb_trans_close(ts);
        rb_raise(rb_eConversionUndefined, "conversion undefined for byte sequence (maybe invalid byte sequence)");
    }
    if (ret == transcode_obuf_full) {
        more_output_buffer(destination, resize_destination, ts, &out_start, out_pos, &out_stop);
        goto resume;
    }

    rb_trans_close(ts);
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
    rb_trans_t *ts;
    rb_trans_result_t ret;
    unsigned char *out_start = *out_pos;
    const unsigned char *ptr;
    int max_output;

    ts = rb_trans_open(from_encoding, to_encoding, 0);
    if (!ts)
        rb_raise(rb_eArgError, "transcoding not supported (from %s to %s)", from_encoding, to_encoding);

    max_output = ts->elems[ts->num_trans-1].tc->transcoder->max_output;

    ret = transcode_ibuf_empty;
    ptr = *in_pos;
    while (ret != transcode_finished) {
        unsigned char input_byte;
        const unsigned char *p = &input_byte;

        if (ret == transcode_ibuf_empty) {
            if (ptr < in_stop) {
                input_byte = *ptr;
                ret = rb_trans_conv(ts, &p, p+1, out_pos, out_stop, PARTIAL_INPUT);
            }
            else {
                ret = rb_trans_conv(ts, NULL, NULL, out_pos, out_stop, 0);
            }
        }
        else {
            ret = rb_trans_conv(ts, NULL, NULL, out_pos, out_stop, PARTIAL_INPUT);
        }
        if (&input_byte != p)
            ptr += p - &input_byte;
        switch (ret) {
          case transcode_invalid_input:
            /* deal with invalid byte sequence */
            /* todo: add more alternative behaviors */
            if (opt&INVALID_IGNORE) {
                break;
            }
            else if (opt&INVALID_REPLACE) {
                output_replacement_character(destination, resize_destination, ts, &out_start, out_pos, &out_stop);
                break;
            }
            rb_trans_close(ts);
            rb_raise(rb_eInvalidByteSequence, "invalid byte sequence");
            break;

          case transcode_undefined_conversion:
            /* valid character in from encoding
             * but no related character(s) in to encoding */
            /* todo: add more alternative behaviors */
            if (opt&UNDEF_IGNORE) {
                break;
            }
            else if (opt&UNDEF_REPLACE) {
                output_replacement_character(destination, resize_destination, ts, &out_start, out_pos, &out_stop);
                break;
            }
            rb_trans_close(ts);
            rb_raise(rb_eConversionUndefined, "conversion undefined for byte sequence (maybe invalid byte sequence)");
            break;

          case transcode_obuf_full:
            more_output_buffer(destination, resize_destination, ts, &out_start, out_pos, &out_stop);
            break;

          case transcode_ibuf_empty:
            break;

          case transcode_finished:
            break;
        }
    }
    rb_trans_close(ts);
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
econv_free(rb_trans_t *ts)
{
    rb_trans_close(ts);
}

static VALUE
econv_s_allocate(VALUE klass)
{
    return Data_Wrap_Struct(klass, NULL, econv_free, NULL);
}

static VALUE
econv_init(VALUE self, VALUE from_encoding, VALUE to_encoding)
{
    const char *from_e, *to_e;
    rb_trans_t *ts;

    from_e = StringValueCStr(from_encoding);
    to_e = StringValueCStr(to_encoding);

    if (DATA_PTR(self)) {
        rb_raise(rb_eTypeError, "already initialized");
    }

    ts = rb_trans_open(from_e, to_e, 0);
    if (!ts) {
        rb_raise(rb_eArgError, "encoding convewrter not supported (from %s to %s)", from_e, to_e);
    }

    DATA_PTR(self) = ts;

    return self;
}

#define IS_ECONV(obj) (RDATA(obj)->dfree == (RUBY_DATA_FUNC)econv_free)

static rb_trans_t *
check_econv(VALUE self)
{
    Check_Type(self, T_DATA);
    if (!IS_ECONV(self)) {
        rb_raise(rb_eTypeError, "wrong argument type %s (expected Encoding::Converter)",
                 rb_class2name(CLASS_OF(self)));
    }
    return DATA_PTR(self);
}

static VALUE
econv_primitive_convert(VALUE self, VALUE input, VALUE output, VALUE flags_v)
{
    rb_trans_t *ts = check_econv(self);
    rb_trans_result_t res;
    const unsigned char *ip, *is;
    unsigned char *op, *os;
    int flags;

    StringValue(input);
    StringValue(output);
    rb_str_modify(output);
    flags = NUM2INT(flags_v);

    ip = (const unsigned char *)RSTRING_PTR(input);
    is = ip + RSTRING_LEN(input);

    op = (unsigned char *)RSTRING_PTR(output);
    os = op + RSTRING_LEN(output);

    res = rb_trans_conv(ts, &ip, is, &op, os, flags);
    rb_str_set_len(output, op-(unsigned char *)RSTRING_PTR(output));
    rb_str_drop_bytes(input, ip - (unsigned char *)RSTRING_PTR(input));

    switch (res) {
      case transcode_invalid_input: return ID2SYM(rb_intern("invalid_input"));
      case transcode_undefined_conversion: return ID2SYM(rb_intern("undefined_conversion"));
      case transcode_obuf_full: return ID2SYM(rb_intern("obuf_full"));
      case transcode_ibuf_empty: return ID2SYM(rb_intern("ibuf_empty"));
      case transcode_finished: return ID2SYM(rb_intern("finished"));
      default: return INT2NUM(res);
    }
}

static VALUE
econv_max_output(VALUE self)
{
    rb_trans_t *ts = check_econv(self);
    int n;
    n = ts->elems[ts->num_trans-1].tc->transcoder->max_output;

    return INT2FIX(n);
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
    rb_define_method(rb_cEncodingConverter, "initialize", econv_init, 2);
    rb_define_method(rb_cEncodingConverter, "primitive_convert", econv_primitive_convert, 3);
    rb_define_method(rb_cEncodingConverter, "max_output", econv_max_output, 0);
    rb_define_const(rb_cEncodingConverter, "PARTIAL_INPUT", INT2FIX(PARTIAL_INPUT));
}
