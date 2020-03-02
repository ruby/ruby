/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Compile-time static implementation of ::rb_scan_args().
 *
 * This  is a  beast.  It  statically analyses  the argument  spec string,  and
 * expands the assignment of variables into dedicated codes.
 */
#ifndef  RUBY3_SCAN_ARGS_H
#define  RUBY3_SCAN_ARGS_H
#include "ruby/3/config.h"
#include "ruby/3/has/attribute.h"
#include "ruby/3/value.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

#define UNLIMITED_ARGUMENTS (-1)

int rb_scan_args(int, const VALUE*, const char*, ...);
#define RB_SCAN_ARGS_PASS_CALLED_KEYWORDS 0
#define RB_SCAN_ARGS_KEYWORDS 1
#define RB_SCAN_ARGS_LAST_HASH_KEYWORDS 3
int rb_scan_args_kw(int, int, const VALUE*, const char*, ...);
#define RB_NO_KEYWORDS 0
#define RB_PASS_KEYWORDS 1
#define RB_PASS_CALLED_KEYWORDS rb_keyword_given_p()
int rb_keyword_given_p(void);
int rb_block_given_p(void);

VALUE rb_hash_dup(VALUE);
VALUE rb_ary_new(void);
VALUE rb_ary_new_from_values(long n, const VALUE *elts);
VALUE rb_block_proc(void);
NORETURN(MJIT_STATIC void rb_error_arity(int, int, int));

/* rb_scan_args() format allows ':' for optional hash */
#define HAVE_RB_SCAN_ARGS_OPTIONAL_HASH 1

static inline int
rb_scan_args_keyword_p(int kw_flag, VALUE last)
{
    switch (kw_flag) {
      case RB_SCAN_ARGS_PASS_CALLED_KEYWORDS:
        return rb_keyword_given_p();
      case RB_SCAN_ARGS_KEYWORDS:
        return 1;
      case RB_SCAN_ARGS_LAST_HASH_KEYWORDS:
        return RB_TYPE_P(last, T_HASH);
    }
    return 0;
}

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P) && defined(HAVE_VA_ARGS_MACRO) && defined(__OPTIMIZE__)
# define rb_scan_args(argc,argvp,fmt,...)            \
    __builtin_choose_expr(__builtin_constant_p(fmt), \
        rb_scan_args0(argc,argvp,fmt,\
                      (sizeof((VALUE*[]){__VA_ARGS__})/sizeof(VALUE*)), \
                      ((VALUE*[]){__VA_ARGS__})), \
        rb_scan_args(argc,argvp,fmt,##__VA_ARGS__))
# define rb_scan_args_kw(kw_flag,argc,argvp,fmt,...) \
    __builtin_choose_expr(__builtin_constant_p(fmt), \
        rb_scan_args_kw0(kw_flag,argc,argvp,fmt,        \
                      (sizeof((VALUE*[]){__VA_ARGS__})/sizeof(VALUE*)), \
                      ((VALUE*[]){__VA_ARGS__})), \
        rb_scan_args_kw(kw_flag,argc,argvp,fmt,##__VA_ARGS__))
# if HAVE_ATTRIBUTE_ERRORFUNC
ERRORFUNC(("bad scan arg format"), void rb_scan_args_bad_format(const char*));
ERRORFUNC(("variable argument length doesn't match"), void rb_scan_args_length_mismatch(const char*,int));
# else
#   define rb_scan_args_bad_format(fmt) ((void)0)
#   define rb_scan_args_length_mismatch(fmt, varc) ((void)0)
# endif

# define rb_scan_args_isdigit(c) ((unsigned char)((c)-'0')<10)

#  define rb_scan_args_count_end(fmt, ofs, vari) \
     ((fmt)[ofs] ? -1 : (vari))

# define rb_scan_args_count_block(fmt, ofs, vari) \
    ((fmt)[ofs]!='&' ? \
     rb_scan_args_count_end(fmt, ofs, vari) : \
     rb_scan_args_count_end(fmt, (ofs)+1, (vari)+1))

# define rb_scan_args_count_hash(fmt, ofs, vari) \
    ((fmt)[ofs]!=':' ? \
     rb_scan_args_count_block(fmt, ofs, vari) : \
     rb_scan_args_count_block(fmt, (ofs)+1, (vari)+1))

# define rb_scan_args_count_trail(fmt, ofs, vari) \
    (!rb_scan_args_isdigit((fmt)[ofs]) ? \
     rb_scan_args_count_hash(fmt, ofs, vari) : \
     rb_scan_args_count_hash(fmt, (ofs)+1, (vari)+((fmt)[ofs]-'0')))

# define rb_scan_args_count_var(fmt, ofs, vari) \
    ((fmt)[ofs]!='*' ? \
     rb_scan_args_count_trail(fmt, ofs, vari) : \
     rb_scan_args_count_trail(fmt, (ofs)+1, (vari)+1))

# define rb_scan_args_count_opt(fmt, ofs, vari) \
    (!rb_scan_args_isdigit((fmt)[ofs]) ? \
     rb_scan_args_count_var(fmt, ofs, vari) : \
     rb_scan_args_count_var(fmt, (ofs)+1, (vari)+(fmt)[ofs]-'0'))

# define rb_scan_args_count_lead(fmt, ofs, vari) \
    (!rb_scan_args_isdigit((fmt)[ofs]) ? \
     rb_scan_args_count_var(fmt, ofs, vari) : \
     rb_scan_args_count_opt(fmt, (ofs)+1, (vari)+(fmt)[ofs]-'0'))

# define rb_scan_args_count(fmt) rb_scan_args_count_lead(fmt, 0, 0)

# if RUBY3_HAS_ATTRIBUTE(diagnose_if)
#  define rb_scan_args_verify(fmt, varc) (void)0
# else
# define rb_scan_args_verify(fmt, varc) \
    (sizeof(char[1-2*(rb_scan_args_count(fmt)<0)])!=1 ? \
     rb_scan_args_bad_format(fmt) : \
     sizeof(char[1-2*(rb_scan_args_count(fmt)!=(varc))])!=1 ? \
     rb_scan_args_length_mismatch(fmt, varc) : \
     (void)0)
# endif

ALWAYS_INLINE(static int rb_scan_args_lead_p(const char *fmt));
static inline int
rb_scan_args_lead_p(const char *fmt)
{
    return rb_scan_args_isdigit(fmt[0]);
}

ALWAYS_INLINE(static int rb_scan_args_n_lead(const char *fmt));
static inline int
rb_scan_args_n_lead(const char *fmt)
{
    return (rb_scan_args_lead_p(fmt) ? fmt[0]-'0' : 0);
}

ALWAYS_INLINE(static int rb_scan_args_opt_p(const char *fmt));
static inline int
rb_scan_args_opt_p(const char *fmt)
{
    return (rb_scan_args_lead_p(fmt) && rb_scan_args_isdigit(fmt[1]));
}

ALWAYS_INLINE(static int rb_scan_args_n_opt(const char *fmt));
static inline int
rb_scan_args_n_opt(const char *fmt)
{
    return (rb_scan_args_opt_p(fmt) ? fmt[1]-'0' : 0);
}

ALWAYS_INLINE(static int rb_scan_args_var_idx(const char *fmt));
static inline int
rb_scan_args_var_idx(const char *fmt)
{
    return (!rb_scan_args_lead_p(fmt) ? 0 : !rb_scan_args_isdigit(fmt[1]) ? 1 : 2);
}

ALWAYS_INLINE(static int rb_scan_args_f_var(const char *fmt));
static inline int
rb_scan_args_f_var(const char *fmt)
{
    return (fmt[rb_scan_args_var_idx(fmt)]=='*');
}

ALWAYS_INLINE(static int rb_scan_args_trail_idx(const char *fmt));
static inline int
rb_scan_args_trail_idx(const char *fmt)
{
    const int idx = rb_scan_args_var_idx(fmt);
    return idx+(fmt[idx]=='*');
}

ALWAYS_INLINE(static int rb_scan_args_n_trail(const char *fmt));
static inline int
rb_scan_args_n_trail(const char *fmt)
{
    const int idx = rb_scan_args_trail_idx(fmt);
    return (rb_scan_args_isdigit(fmt[idx]) ? fmt[idx]-'0' : 0);
}

ALWAYS_INLINE(static int rb_scan_args_hash_idx(const char *fmt));
static inline int
rb_scan_args_hash_idx(const char *fmt)
{
    const int idx = rb_scan_args_trail_idx(fmt);
    return idx+rb_scan_args_isdigit(fmt[idx]);
}

ALWAYS_INLINE(static int rb_scan_args_f_hash(const char *fmt));
static inline int
rb_scan_args_f_hash(const char *fmt)
{
    return (fmt[rb_scan_args_hash_idx(fmt)]==':');
}

ALWAYS_INLINE(static int rb_scan_args_block_idx(const char *fmt));
static inline int
rb_scan_args_block_idx(const char *fmt)
{
    const int idx = rb_scan_args_hash_idx(fmt);
    return idx+(fmt[idx]==':');
}

ALWAYS_INLINE(static int rb_scan_args_f_block(const char *fmt));
static inline int
rb_scan_args_f_block(const char *fmt)
{
    return (fmt[rb_scan_args_block_idx(fmt)]=='&');
}

# if 0
ALWAYS_INLINE(static int rb_scan_args_end_idx(const char *fmt));
static inline int
rb_scan_args_end_idx(const char *fmt)
{
    const int idx = rb_scan_args_block_idx(fmt);
    return idx+(fmt[idx]=='&');
}
# endif

/* NOTE: Use `char *fmt` instead of `const char *fmt` because of clang's bug*/
/* https://bugs.llvm.org/show_bug.cgi?id=38095 */
# define rb_scan_args0(argc, argv, fmt, varc, vars) \
    rb_scan_args_set(RB_SCAN_ARGS_PASS_CALLED_KEYWORDS, argc, argv, \
                     rb_scan_args_n_lead(fmt), \
                     rb_scan_args_n_opt(fmt), \
                     rb_scan_args_n_trail(fmt), \
                     rb_scan_args_f_var(fmt), \
                     rb_scan_args_f_hash(fmt), \
                     rb_scan_args_f_block(fmt), \
                     (rb_scan_args_verify(fmt, varc), vars), (char *)fmt, varc)
# define rb_scan_args_kw0(kw_flag, argc, argv, fmt, varc, vars) \
    rb_scan_args_set(kw_flag, argc, argv, \
                     rb_scan_args_n_lead(fmt), \
                     rb_scan_args_n_opt(fmt), \
                     rb_scan_args_n_trail(fmt), \
                     rb_scan_args_f_var(fmt), \
                     rb_scan_args_f_hash(fmt), \
                     rb_scan_args_f_block(fmt), \
                     (rb_scan_args_verify(fmt, varc), vars), (char *)fmt, varc)
ALWAYS_INLINE(static int
rb_scan_args_set(int kw_flag, int argc, const VALUE *argv,
                 int n_lead, int n_opt, int n_trail,
                 int f_var, int f_hash, int f_block,
                 VALUE *vars[], const char *fmt, int varc));

inline int
rb_scan_args_set(int kw_flag, int argc, const VALUE *argv,
                 int n_lead, int n_opt, int n_trail,
                 int f_var, int f_hash, int f_block,
                 VALUE *vars[], RB_UNUSED_VAR(const char *fmt), RB_UNUSED_VAR(int varc))
# if RUBY3_HAS_ATTRIBUTE(diagnose_if)
    __attribute__((diagnose_if(rb_scan_args_count(fmt)<0,"bad scan arg format","error")))
    __attribute__((diagnose_if(rb_scan_args_count(fmt)!=varc,"variable argument length doesn't match","error")))
# endif
{
    int i, argi = 0, vari = 0;
    VALUE *var, hash = Qnil;
    const int n_mand = n_lead + n_trail;

    if (f_hash && argc > 0) {
        VALUE last = argv[argc - 1];
        if (rb_scan_args_keyword_p(kw_flag, last)) {
            hash = rb_hash_dup(last);
            argc--;
        }
    }

    if (argc < n_mand) {
        goto argc_error;
    }

    /* capture leading mandatory arguments */
    for (i = n_lead; i-- > 0; ) {
        var = vars[vari++];
        if (var) *var = argv[argi];
        argi++;
    }
    /* capture optional arguments */
    for (i = n_opt; i-- > 0; ) {
        var = vars[vari++];
        if (argi < argc - n_trail) {
            if (var) *var = argv[argi];
            argi++;
        }
        else {
            if (var) *var = Qnil;
        }
    }
    /* capture variable length arguments */
    if (f_var) {
        int n_var = argc - argi - n_trail;

        var = vars[vari++];
        if (0 < n_var) {
            if (var) *var = rb_ary_new_from_values(n_var, &argv[argi]);
            argi += n_var;
        }
        else {
            if (var) *var = rb_ary_new();
        }
    }
    /* capture trailing mandatory arguments */
    for (i = n_trail; i-- > 0; ) {
        var = vars[vari++];
        if (var) *var = argv[argi];
        argi++;
    }
    /* capture an option hash - phase 2: assignment */
    if (f_hash) {
        var = vars[vari++];
        if (var) *var = hash;
    }
    /* capture iterator block */
    if (f_block) {
        var = vars[vari++];
        if (rb_block_given_p()) {
            *var = rb_block_proc();
        }
        else {
            *var = Qnil;
        }
    }

    if (argi < argc) {
      argc_error:
        rb_error_arity(argc, n_mand, f_var ? UNLIMITED_ARGUMENTS : n_mand + n_opt);
    }

    return argc;
}
#endif

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_SCAN_ARGS_H */
