/**********************************************************************

  internal.h -

  $Author$
  created at: Tue May 17 11:42:20 JST 2011

  Copyright (C) 2011 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_INTERNAL_H
#define RUBY_INTERNAL_H 1

#include "ruby/config.h"

#ifdef __cplusplus
# error not for C++
#endif

#define LIKELY(x) RB_LIKELY(x)
#define UNLIKELY(x) RB_UNLIKELY(x)

#define numberof(array) ((int)(sizeof(array) / sizeof((array)[0])))
#define roomof(x, y) (((x) + (y) - 1) / (y))
#define type_roomof(x, y) roomof(sizeof(x), sizeof(y))

/* Prevent compiler from reordering access */
#define ACCESS_ONCE(type,x) (*((volatile type *)&(x)))

#include "ruby/ruby.h"

/* Folowing macros were formerlly defined in this header but moved to somewhere
 * else.  In order to detect them we undef here. */

/* internal/error.h */
#undef Check_Type

/* internal/class.h */
#undef RClass
#undef RCLASS_SUPER

/* internal/gc.h */
#undef NEWOBJ_OF
#undef RB_NEWOBJ_OF
#undef RB_OBJ_WRITE

/* internal/hash.h */
#undef RHASH_IFNONE
#undef RHASH_SIZE

/* internal/struct.h */
#undef RSTRUCT_LEN
#undef RSTRUCT_PTR
#undef RSTRUCT_SET
#undef RSTRUCT_GET

/* Also,  we  keep  the  following  macros  here.   They  are  expected  to  be
 * overridden in each headers. */

/* internal/array.h */
#define rb_ary_new_from_args(...) rb_nonexistent_symbol(__VA_ARGS__)

/* internal/io.h */
#define rb_io_fptr_finalize(...) rb_nonexistent_symbol(__VA_ARGS__)

/* internal/string.h */
#define rb_fstring_cstr(...) rb_nonexistent_symbol(__VA_ARGS__)

/* internal/symbol.h */
#define rb_sym_intern_ascii_cstr(...) rb_nonexistent_symbol(__VA_ARGS__)

/* internal/vm.h */
#define rb_funcallv(...) rb_nonexistent_symbol(__VA_ARGS__)
#define rb_method_basic_definition_p(...) rb_nonexistent_symbol(__VA_ARGS__)


/* MRI debug support */

/* gc.c */
void rb_obj_info_dump(VALUE obj);
void rb_obj_info_dump_loc(VALUE obj, const char *file, int line, const char *func);

/* debug.c */
void ruby_debug_breakpoint(void);
PRINTF_ARGS(void ruby_debug_printf(const char*, ...), 1, 2);

// show obj data structure without any side-effect
#define rp(obj) rb_obj_info_dump_loc((VALUE)(obj), __FILE__, __LINE__, __func__)

// same as rp, but add message header
#define rp_m(msg, obj) do { \
    fprintf(stderr, "%s", (msg)); \
    rb_obj_info_dump((VALUE)obj); \
} while (0)

// `ruby_debug_breakpoint()` does nothing,
// but breakpoint is set in run.gdb, so `make gdb` can stop here.
#define bp() ruby_debug_breakpoint()

#endif /* RUBY_INTERNAL_H */
