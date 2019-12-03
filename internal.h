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

#include "ruby/encoding.h"
#include "ruby/io.h"
#include "internal/stdbool.h"
#include "internal/bits.h"

#define LIKELY(x) RB_LIKELY(x)
#define UNLIKELY(x) RB_UNLIKELY(x)

#include "internal/compilers.h"
#include "internal/sanitizers.h"

#define numberof(array) ((int)(sizeof(array) / sizeof((array)[0])))
#define roomof(x, y) (((x) + (y) - 1) / (y))
#define type_roomof(x, y) roomof(sizeof(x), sizeof(y))

/* Prevent compiler from reordering access */
#define ACCESS_ONCE(type,x) (*((volatile type *)&(x)))

#include "internal/serial.h"
#include "internal/static_assert.h"
#include "internal/time.h"
#include "internal/fixnum.h"
#include "internal/bignum.h"
#include "internal/rational.h"
#include "internal/numeric.h"
#include "internal/complex.h"
#include "internal/hash.h"
#include "internal/missing.h"
#include "internal/struct.h"
#include "internal/class.h"
#include "internal/imemo.h"
#include "internal/compar.h"
#include "internal/variable.h"
#include "internal/array.h"
#include "internal/debug.h"
#include "internal/compile.h"
#include "internal/cont.h"
#include "internal/dir.h"
#include "internal/encoding.h"
#include "internal/enum.h"
#include "internal/eval.h"
#include "internal/error.h"
#include "internal/file.h"
#include "internal/gc.h"
#include "internal/io.h"
#include "internal/load.h"
#include "internal/loadpath.h"
#include "internal/math.h"
#include "internal/mjit.h"
#include "internal/object.h"
#include "internal/parse.h"
#include "internal/proc.h"
#include "internal/process.h"
#include "internal/range.h"
#include "internal/re.h"
#include "internal/signal.h"
#include "internal/string.h"
#include "internal/symbol.h"
#include "internal/thread.h"
#include "internal/transcode.h"
#include "internal/enc.h"
#include "internal/util.h"
#include "internal/vm.h"
#include "internal/enumerator.h"
#include "internal/random.h"
#include "internal/inits.h"
#include "internal/warnings.h"

#endif /* RUBY_INTERNAL_H */
