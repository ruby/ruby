#ifndef INTERNAL_REGEXP_RUST_H                           /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_REGEXP_RUST_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Functions exported by the Rust regexp engine (regexp/src/ffi.rs).
 */
#include <stddef.h>
#include <stdint.h>
#include "ruby/onigmo.h"

/* Must match regexp::ffi::ABI_VERSION. */
#define RB_REGEXP_RUST_ABI_VERSION 2

#define RB_REGEXP_WARN_ENABLED 1
#define RB_REGEXP_WARN_VERBOSE 2

/* Codes of the Rust engine beyond Onigmo's (-24 and -25 are unused there). */
#define RB_REGEXP_INTERRUPTED (-24)
#define RB_REGEXP_PANICKED    (-25)

typedef struct rb_regexp_rust rb_regexp_rust_t;

struct rb_regexp_compile_result {
    int code;
    unsigned char message[ONIG_MAX_ERROR_MESSAGE_LEN];
    /* NUL-terminated messages one after another; free with rb_regexp_rust_free_bytes. */
    unsigned char *warnings;
    size_t warnings_len;
};

/* The compiled form, for comparing the engines in tests. */
struct rb_regexp_rust_info {
    int num_mem;
    int num_repeat;
    int num_null_check;
    int num_call;
    uint32_t capture_history;
    uint32_t bt_mem_start;
    uint32_t bt_mem_end;
    int stack_pop_level;
    uint32_t options;
    int optimize;
    int threshold_len;
    int anchor;
    size_t anchor_dmin;
    size_t anchor_dmax;
    int sub_anchor;
    size_t dmin;
    size_t dmax;
    const unsigned char *program;
    size_t program_len;
    const unsigned char *exact;
    size_t exact_len;
    const unsigned char *map;
    const int *repeat_range;
    size_t repeat_range_len;
};

uint32_t rb_regexp_rust_abi_version(void);
void rb_regexp_rust_init(const OnigEncodingType *ascii);
int rb_regexp_rust_take_panic_message(char *buf, size_t len);
unsigned int rb_regexp_rust_get_parse_depth_limit(void);
int rb_regexp_rust_set_parse_depth_limit(unsigned int depth);

int rb_regexp_rust_compile(const unsigned char *pat, size_t len, uint32_t options,
                           const OnigEncodingType *enc, int warn_flags,
                           rb_regexp_rust_t **out, struct rb_regexp_compile_result *res);
void rb_regexp_rust_free(rb_regexp_rust_t *h);
void rb_regexp_rust_free_bytes(unsigned char *ptr, size_t len);
int rb_regexp_rust_num_mem(const rb_regexp_rust_t *h);
int rb_regexp_rust_error_str(unsigned char *buf, int code);
void rb_regexp_rust_info(const rb_regexp_rust_t *h, struct rb_regexp_rust_info *info);
size_t rb_regexp_rust_name_count(const rb_regexp_rust_t *h);
int rb_regexp_rust_name_at(const rb_regexp_rust_t *h, size_t i,
                           const unsigned char **name, size_t *name_len,
                           int *ngroups, const int **groups);

#endif /* INTERNAL_REGEXP_RUST_H */
