#ifndef INTERNAL_CORE_RS_H                               /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_CORE_RS_H
/**
 * @author     Ruby on Rust contributors
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either  redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal (non-public) functions implemented in core_rs.
 *
 * When a static C function is ported to core_rs/ and C code outside the
 * port still calls it, the Rust port exports it as
 * `rb_core_<file>_<name>` and the C file maps the old name to it with a
 * `#define` in its `#if USE_RUST_PORTS` branch.  Those symbols must not
 * become part of libruby's ABI (AGENTS.md §6.7), so they are declared here
 * with hidden visibility: on ELF the linker gives the definition the most
 * constraining visibility of all references, which drops it from the
 * dynamic symbol table.  On macOS, LIBRUBY_DLDFLAGS unexports `_rb_core_*`.
 *
 * Every rb_core_* function core_rs exports must be declared here.
 * `make core-rs-check-hidden` fails if one is visible in libruby.so.
 */
#include "ruby/internal/config.h"

#ifndef USE_RUST_PORTS
# define USE_RUST_PORTS 0
#endif

#if USE_RUST_PORTS

#include "ruby/internal/special_consts.h"
#include "ruby/internal/static_assert.h"

/* core_rs/src/ffi/value.rs transcribes the special constants (selected by
 * USE_FLONUM, which core_rs/core_rs.mk takes from this preprocessor) and
 * assumes `long` is as wide as VALUE.  Fail the C build if the headers
 * disagree with the transcription. */
RBIMPL_STATIC_ASSERT(core_rs_long_is_value_sized, SIZEOF_LONG == SIZEOF_VALUE);
RBIMPL_STATIC_ASSERT(core_rs_qnil, RUBY_Qnil == (USE_FLONUM ? 0x04 : 0x02));
RBIMPL_STATIC_ASSERT(core_rs_qtrue, RUBY_Qtrue == (USE_FLONUM ? 0x14 : 0x06));
RBIMPL_STATIC_ASSERT(core_rs_qundef, RUBY_Qundef == (USE_FLONUM ? 0x24 : 0x0a));
RBIMPL_STATIC_ASSERT(core_rs_qfalse, RUBY_Qfalse == 0);
RBIMPL_STATIC_ASSERT(core_rs_immediate_mask, RUBY_IMMEDIATE_MASK == (USE_FLONUM ? 0x07 : 0x03));
RBIMPL_STATIC_ASSERT(core_rs_fixnum_flag, RUBY_FIXNUM_FLAG == 0x01);
RBIMPL_STATIC_ASSERT(core_rs_flonum_mask, RUBY_FLONUM_MASK == (USE_FLONUM ? 0x03 : 0x00));
RBIMPL_STATIC_ASSERT(core_rs_flonum_flag, RUBY_FLONUM_FLAG == 0x02);
RBIMPL_STATIC_ASSERT(core_rs_symbol_flag, RUBY_SYMBOL_FLAG == (USE_FLONUM ? 0x0c : 0x0e));
RBIMPL_STATIC_ASSERT(core_rs_special_shift, RUBY_SPECIAL_SHIFT == 8);

#if defined(__ELF__) && (defined(__GNUC__) || defined(__clang__))
# pragma GCC visibility push(hidden)
#endif

/* complex.c (core_rs/src/complex.rs) */
int rb_core_complex_issign(int c);
int rb_core_complex_isdecimal(int c);
int rb_core_complex_isimagunit(int c);
int rb_core_complex_read_sign(const char **s, char **b);
int rb_core_complex_read_rat_nos(const char **s, int strict, char **b);
int rb_core_complex_read_rat(const char **s, int strict, char **b);
void rb_core_complex_skip_ws(const char **s);


/* pack.c (core_rs/src/pack.rs) */
int rb_core_pack_is_bigendian(void);
char *rb_core_pack_skip_to_eol(const char *p, const char *pend);
size_t rb_core_pack_pack_alignof(char type, int natint);
int rb_core_pack_hex2num(char c);

/* re.c (core_rs/src/re.rs) */
int rb_core_re_check_unicode_range(unsigned long code, char *err);

#if defined(__ELF__) && (defined(__GNUC__) || defined(__clang__))
# pragma GCC visibility pop
#endif

#endif /* USE_RUST_PORTS */
#endif /* INTERNAL_CORE_RS_H */
