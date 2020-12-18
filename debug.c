/**********************************************************************

  debug.c -

  $Author$
  created at: 04/08/25 02:31:54 JST

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/

#include "ruby/internal/config.h"

#include <stdio.h>

#include "eval_intern.h"
#include "id.h"
#include "internal/signal.h"
#include "internal/util.h"
#include "ruby/encoding.h"
#include "ruby/io.h"
#include "ruby/ruby.h"
#include "ruby/util.h"
#include "symbol.h"
#include "vm_core.h"
#include "vm_debug.h"
#include "vm_callinfo.h"
#include "ruby/thread_native.h"
#include "ractor_core.h"

/* This is the only place struct RIMemo is actually used */
struct RIMemo {
    VALUE flags;
    VALUE v0;
    VALUE v1;
    VALUE v2;
    VALUE v3;
};

/* for gdb */
const union {
    enum ruby_special_consts    special_consts;
    enum ruby_value_type        value_type;
    enum ruby_tag_type          tag_type;
    enum node_type              node_type;
    enum ruby_method_ids        method_ids;
    enum ruby_id_types          id_types;
    enum ruby_fl_type           fl_types;
    enum ruby_fl_ushift         fl_ushift;
    enum ruby_encoding_consts   encoding_consts;
    enum ruby_coderange_type    enc_coderange_types;
    enum ruby_econv_flag_type   econv_flag_types;
    rb_econv_result_t           econv_result;
    enum ruby_robject_flags     robject_flags;
    enum ruby_robject_consts    robject_consts;
    enum ruby_rmodule_flags     rmodule_flags;
    enum ruby_rstring_flags     rstring_flags;
    enum ruby_rstring_consts    rstring_consts;
    enum ruby_rarray_flags      rarray_flags;
    enum ruby_rarray_consts     rarray_consts;
    enum {
	RUBY_FMODE_READABLE		= FMODE_READABLE,
	RUBY_FMODE_WRITABLE		= FMODE_WRITABLE,
	RUBY_FMODE_READWRITE		= FMODE_READWRITE,
	RUBY_FMODE_BINMODE		= FMODE_BINMODE,
	RUBY_FMODE_SYNC 		= FMODE_SYNC,
	RUBY_FMODE_TTY			= FMODE_TTY,
	RUBY_FMODE_DUPLEX		= FMODE_DUPLEX,
	RUBY_FMODE_APPEND		= FMODE_APPEND,
	RUBY_FMODE_CREATE		= FMODE_CREATE,
	RUBY_FMODE_NOREVLOOKUP		= 0x00000100,
	RUBY_FMODE_TRUNC		= FMODE_TRUNC,
	RUBY_FMODE_TEXTMODE		= FMODE_TEXTMODE,
	RUBY_FMODE_PREP 		= 0x00010000,
	RUBY_FMODE_SETENC_BY_BOM	= FMODE_SETENC_BY_BOM,
	RUBY_FMODE_UNIX 		= 0x00200000,
	RUBY_FMODE_INET 		= 0x00400000,
	RUBY_FMODE_INET6		= 0x00800000,

        RUBY_NODE_TYPESHIFT = NODE_TYPESHIFT,
        RUBY_NODE_TYPEMASK  = NODE_TYPEMASK,
        RUBY_NODE_LSHIFT    = NODE_LSHIFT,
        RUBY_NODE_FL_NEWLINE   = NODE_FL_NEWLINE
    } various;
    union {
	enum imemo_type                     types;
	enum {RUBY_IMEMO_MASK = IMEMO_MASK} mask;
	struct RIMemo                      *ptr;
    } imemo;
    struct RSymbol *symbol_ptr;
    enum vm_call_flag_bits vm_call_flags;
} ruby_dummy_gdb_enums;

const SIGNED_VALUE RUBY_NODE_LMASK = NODE_LMASK;

int
ruby_debug_print_indent(int level, int debug_level, int indent_level)
{
    if (level < debug_level) {
	fprintf(stderr, "%*s", indent_level, "");
	fflush(stderr);
	return TRUE;
    }
    return FALSE;
}

void
ruby_debug_printf(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    vfprintf(stderr, format, ap);
    va_end(ap);
}

#include "gc.h"

VALUE
ruby_debug_print_value(int level, int debug_level, const char *header, VALUE obj)
{
    if (level < debug_level) {
	char buff[0x100];
	rb_raw_obj_info(buff, 0x100, obj);

	fprintf(stderr, "DBG> %s: %s\n", header, buff);
	fflush(stderr);
    }
    return obj;
}

void
ruby_debug_print_v(VALUE v)
{
    ruby_debug_print_value(0, 1, "", v);
}

ID
ruby_debug_print_id(int level, int debug_level, const char *header, ID id)
{
    if (level < debug_level) {
	fprintf(stderr, "DBG> %s: %s\n", header, rb_id2name(id));
	fflush(stderr);
    }
    return id;
}

NODE *
ruby_debug_print_node(int level, int debug_level, const char *header, const NODE *node)
{
    if (level < debug_level) {
	fprintf(stderr, "DBG> %s: %s (%u)\n", header,
		ruby_node_name(nd_type(node)), nd_line(node));
    }
    return (NODE *)node;
}

void
ruby_debug_breakpoint(void)
{
    /* */
}

#if defined _WIN32
# if RUBY_MSVCRT_VERSION >= 80
extern int ruby_w32_rtc_error;
# endif
#endif
#if defined _WIN32 || defined __CYGWIN__
#include <windows.h>
UINT ruby_w32_codepage[2];
#endif
extern int ruby_rgengc_debug;
extern int ruby_on_ci;

int
ruby_env_debug_option(const char *str, int len, void *arg)
{
    int ov;
    size_t retlen;
    unsigned long n;
#define SET_WHEN(name, var, val) do {	    \
	if (len == sizeof(name) - 1 &&	    \
	    strncmp(str, (name), len) == 0) { \
	    (var) = (val);		    \
	    return 1;			    \
	}				    \
    } while (0)
#define NAME_MATCH_VALUE(name)				\
    ((size_t)len >= sizeof(name)-1 &&			\
     strncmp(str, (name), sizeof(name)-1) == 0 &&	\
     ((len == sizeof(name)-1 && !(len = 0)) ||		\
      (str[sizeof(name)-1] == '=' &&			\
       (str += sizeof(name), len -= sizeof(name), 1))))
#define SET_UINT(val) do { \
	n = ruby_scan_digits(str, len, 10, &retlen, &ov); \
	if (!ov && retlen) { \
	    val = (unsigned int)n; \
	} \
	str += retlen; \
	len -= retlen; \
    } while (0)
#define SET_UINT_LIST(name, vals, num) do { \
	int i; \
	for (i = 0; i < (num); ++i) { \
	    SET_UINT((vals)[i]); \
	    if (!len || *str != ':') break; \
	    ++str; \
	    --len; \
	} \
	if (len > 0) { \
	    fprintf(stderr, "ignored "name" option: `%.*s'\n", len, str); \
	} \
    } while (0)
#define SET_WHEN_UINT(name, vals, num, req) \
    if (NAME_MATCH_VALUE(name)) SET_UINT_LIST(name, vals, num);

    SET_WHEN("gc_stress", *ruby_initial_gc_stress_ptr, Qtrue);
    SET_WHEN("core", ruby_enable_coredump, 1);
    SET_WHEN("ci", ruby_on_ci, 1);
    if (NAME_MATCH_VALUE("rgengc")) {
	if (!len) ruby_rgengc_debug = 1;
	else SET_UINT_LIST("rgengc", &ruby_rgengc_debug, 1);
	return 1;
    }
#if defined _WIN32
# if RUBY_MSVCRT_VERSION >= 80
    SET_WHEN("rtc_error", ruby_w32_rtc_error, 1);
# endif
#endif
#if defined _WIN32 || defined __CYGWIN__
    if (NAME_MATCH_VALUE("codepage")) {
	if (!len) fprintf(stderr, "missing codepage argument");
	else SET_UINT_LIST("codepage", ruby_w32_codepage, numberof(ruby_w32_codepage));
	return 1;
    }
#endif
    return 0;
}

static void
set_debug_option(const char *str, int len, void *arg)
{
    if (!ruby_env_debug_option(str, len, arg)) {
	fprintf(stderr, "unexpected debug option: %.*s\n", len, str);
    }
}

STATIC_ASSERT(USE_RUBY_DEBUG_LOG, USE_RUBY_DEBUG_LOG ? RUBY_DEVEL : 1);

#if RUBY_DEVEL
static void setup_debug_log(void);
#else
#define setup_debug_log()
#endif

void
ruby_set_debug_option(const char *str)
{
    ruby_each_words(str, set_debug_option, 0);
    setup_debug_log();
}

#if RUBY_DEVEL

// RUBY_DEBUG_LOG features
// See vm_debug.h comments for details.

#define MAX_DEBUG_LOG             0x1000
#define MAX_DEBUG_LOG_MESSAGE_LEN 0x0200
#define MAX_DEBUG_LOG_FILTER      0x0010

enum ruby_debug_log_mode ruby_debug_log_mode;

static struct {
    char *mem;
    unsigned int cnt;
    char filters[MAX_DEBUG_LOG_FILTER][MAX_DEBUG_LOG_FILTER];
    unsigned int filters_num;
    rb_nativethread_lock_t lock;
    FILE *output;
} debug_log;

static char *
RUBY_DEBUG_LOG_MEM_ENTRY(unsigned int index)
{
    return &debug_log.mem[MAX_DEBUG_LOG_MESSAGE_LEN * index];
}

static void
setup_debug_log(void)
{
    // check RUBY_DEBUG_LOG
    const char *log_config = getenv("RUBY_DEBUG_LOG");
    if (log_config) {
        fprintf(stderr, "RUBY_DEBUG_LOG=%s\n", log_config);

        if  (strcmp(log_config, "mem") == 0) {
            debug_log.mem = (char *)malloc(MAX_DEBUG_LOG * MAX_DEBUG_LOG_MESSAGE_LEN);
            if (debug_log.mem == NULL) {
                fprintf(stderr, "setup_debug_log failed (can't allocate memory)\n");
                exit(1);
            }
            ruby_debug_log_mode |= ruby_debug_log_memory;
        }
        else if (strcmp(log_config, "stderr") == 0) {
            ruby_debug_log_mode |= ruby_debug_log_stderr;
        }
        else {
            ruby_debug_log_mode |= ruby_debug_log_file;
            if ((debug_log.output = fopen(log_config, "w")) == NULL) {
                fprintf(stderr, "can not open %s for RUBY_DEBUG_LOG\n", log_config);
                exit(1);
            }
            setvbuf(debug_log.output, NULL, _IONBF, 0);
        }

        rb_nativethread_lock_initialize(&debug_log.lock);
    }

    // check RUBY_DEBUG_LOG_FILTER
    const char *filter_config = getenv("RUBY_DEBUG_LOG_FILTER");
    if (filter_config && strlen(filter_config) > 0) {
        unsigned int i;
        for (i=0; i<MAX_DEBUG_LOG_FILTER; i++) {
            const char *p;
            if ((p = strchr(filter_config, ',')) == NULL) {
                if (strlen(filter_config) >= MAX_DEBUG_LOG_FILTER) {
                    fprintf(stderr, "too long: %s (max:%d)\n", filter_config, MAX_DEBUG_LOG_FILTER);
                    exit(1);
                }
                strncpy(debug_log.filters[i], filter_config, MAX_DEBUG_LOG_FILTER - 1);
                i++;
                break;
            }
            else {
                size_t n = p - filter_config;
                if (n >= MAX_DEBUG_LOG_FILTER) {
                    fprintf(stderr, "too long: %s (max:%d)\n", filter_config, MAX_DEBUG_LOG_FILTER);
                    exit(1);
                }
                strncpy(debug_log.filters[i], filter_config, n);
                filter_config = p+1;
            }
        }
        debug_log.filters_num = i;
        for (i=0; i<debug_log.filters_num; i++) {
            fprintf(stderr, "RUBY_DEBUG_LOG_FILTER[%d]=%s\n", i, debug_log.filters[i]);
        }
    }
}

bool
ruby_debug_log_filter(const char *func_name)
{
    if (debug_log.filters_num > 0) {
        for (unsigned int i = 0; i<debug_log.filters_num; i++) {
            if (strstr(func_name, debug_log.filters[i]) != NULL) {
                return true;
            }
        }
        return false;
    }
    else {
        return true;
    }
}

static const char *
pretty_filename(const char *path)
{
    // basename is one idea.
    const char *s;
    while ((s = strchr(path, '/')) != NULL) {
        path = s+1;
    }
    return path;
}

void
ruby_debug_log(const char *file, int line, const char *func_name, const char *fmt, ...)
{
    char buff[MAX_DEBUG_LOG_MESSAGE_LEN] = {0};
    int len = 0;
    int r = 0;

    // message title
    if (func_name && len < MAX_DEBUG_LOG_MESSAGE_LEN) {
        r = snprintf(buff + len, MAX_DEBUG_LOG_MESSAGE_LEN, "%s\t", func_name);
        if (r < 0) rb_bug("ruby_debug_log returns %d\n", r);
        len += r;
    }

    // message
    if (fmt && len < MAX_DEBUG_LOG_MESSAGE_LEN) {
        va_list args;
        va_start(args, fmt);
        r = vsnprintf(buff + len, MAX_DEBUG_LOG_MESSAGE_LEN - len, fmt, args);
        va_end(args);
        if (r < 0) rb_bug("ruby_debug_log vsnprintf() returns %d", r);
        len += r;
    }

    // optional information

    // C location
    if (file && len < MAX_DEBUG_LOG_MESSAGE_LEN) {
        r = snprintf(buff + len, MAX_DEBUG_LOG_MESSAGE_LEN, "\t%s:%d", pretty_filename(file), line);
        if (r < 0) rb_bug("ruby_debug_log returns %d\n", r);
        len += r;
    }

    // Ruby location
    int ruby_line;
    const char *ruby_file = rb_source_location_cstr(&ruby_line);
    if (len < MAX_DEBUG_LOG_MESSAGE_LEN) {
        if (ruby_file) {
            r = snprintf(buff + len, MAX_DEBUG_LOG_MESSAGE_LEN - len, "\t%s:%d", pretty_filename(ruby_file), ruby_line);
        }
        else {
            r = snprintf(buff + len, MAX_DEBUG_LOG_MESSAGE_LEN - len, "\t");
        }
        if (r < 0) rb_bug("ruby_debug_log returns %d\n", r);
        len += r;
    }

    // ractor information
    if (ruby_single_main_ractor == NULL) {
        rb_ractor_t *cr = GET_RACTOR();
        if (r && len < MAX_DEBUG_LOG_MESSAGE_LEN) {
            r = snprintf(buff + len, MAX_DEBUG_LOG_MESSAGE_LEN - len, "\tr:#%u/%u",
                         (unsigned int)rb_ractor_id(cr), GET_VM()->ractor.cnt);
            if (r < 0) rb_bug("ruby_debug_log returns %d\n", r);
            len += r;
        }
    }

    // thread information
    if (!rb_thread_alone()) {
        const rb_thread_t *th = GET_THREAD();
        if (r && len < MAX_DEBUG_LOG_MESSAGE_LEN) {
            r = snprintf(buff + len, MAX_DEBUG_LOG_MESSAGE_LEN - len, "\tth:%p", (void *)th);
            if (r < 0) rb_bug("ruby_debug_log returns %d\n", r);
            len += r;
        }
    }

    rb_nativethread_lock_lock(&debug_log.lock);
    {
        unsigned int cnt = debug_log.cnt++;

        if (ruby_debug_log_mode & ruby_debug_log_memory) {
            unsigned int index = cnt % MAX_DEBUG_LOG;
            char *dst = RUBY_DEBUG_LOG_MEM_ENTRY(index);
            strncpy(dst, buff, MAX_DEBUG_LOG_MESSAGE_LEN);
        }
        if (ruby_debug_log_mode & ruby_debug_log_stderr) {
            fprintf(stderr, "%4u: %s\n", cnt, buff);
        }
        if (ruby_debug_log_mode & ruby_debug_log_file) {
            fprintf(debug_log.output, "%u\t%s\n", cnt, buff);
        }
    }
    rb_nativethread_lock_unlock(&debug_log.lock);
}

// for debugger
static void
debug_log_dump(FILE *out, unsigned int n)
{
    if (ruby_debug_log_mode & ruby_debug_log_memory) {
        unsigned int size = debug_log.cnt > MAX_DEBUG_LOG ? MAX_DEBUG_LOG : debug_log.cnt;
        unsigned int current_index = debug_log.cnt % MAX_DEBUG_LOG;
        if (n == 0) n = size;
        if (n > size) n = size;

        for (unsigned int i=0; i<n; i++) {
            int index = current_index - size + i;
            if (index < 0) index += MAX_DEBUG_LOG;
            VM_ASSERT(index <= MAX_DEBUG_LOG);
            const char *mesg = RUBY_DEBUG_LOG_MEM_ENTRY(index);;
            fprintf(out, "%4u: %s\n", debug_log.cnt - size + i, mesg);
        }
    }
    else {
        fprintf(stderr, "RUBY_DEBUG_LOG=mem is not specified.");
    }
}

// for debuggers

void
ruby_debug_log_print(unsigned int n)
{
    debug_log_dump(stderr, n);
}

void
ruby_debug_log_dump(const char *fname, unsigned int n)
{
    FILE *fp = fopen(fname, "w");
    if (fp == NULL) {
        fprintf(stderr, "can't open %s. give up.\n", fname);
    }
    else {
        debug_log_dump(fp, n);
        fclose(fp);
    }
}
#endif // #if RUBY_DEVEL
