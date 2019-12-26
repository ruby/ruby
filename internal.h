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

#endif /* RUBY_INTERNAL_H */
