/*
 * Not compiled: core_rs/core_rs.mk runs this file through the C preprocessor
 * with the same flags as the C sources ($(XCFLAGS) $(CPPFLAGS)), and turns
 * the result into rustc --cfg options.  So core_rs/src/ffi/value.rs uses the
 * configuration the C build really has, including overrides passed with
 * cppflags (e.g. cppflags=-DUSE_FLONUM=0, which CI builds).
 */
#include "ruby/internal/special_consts.h"

core_rs_cfg_use_flonum USE_FLONUM

core_rs_cfg_sizeof_value SIZEOF_VALUE
core_rs_cfg_sizeof_long SIZEOF_LONG
core_rs_cfg_sizeof_voidp SIZEOF_VOIDP

#if USE_FLONUM
core_rs_cfg_qfalse 0x00
core_rs_cfg_qnil 0x04
core_rs_cfg_qtrue 0x14
core_rs_cfg_qundef 0x24
core_rs_cfg_immediate_mask 0x07
core_rs_cfg_fixnum_flag 0x01
core_rs_cfg_flonum_mask 0x03
core_rs_cfg_flonum_flag 0x02
core_rs_cfg_symbol_flag 0x0c
#else
core_rs_cfg_qfalse 0x00
core_rs_cfg_qnil 0x02
core_rs_cfg_qtrue 0x06
core_rs_cfg_qundef 0x0a
core_rs_cfg_immediate_mask 0x03
core_rs_cfg_fixnum_flag 0x01
core_rs_cfg_flonum_mask 0x00
core_rs_cfg_flonum_flag 0x02
core_rs_cfg_symbol_flag 0x0e
#endif

core_rs_cfg_special_shift 8
