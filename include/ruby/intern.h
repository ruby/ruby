/**********************************************************************

  intern.h -

  $Author$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#ifndef RUBY_INTERN_H
#define RUBY_INTERN_H 1

#include "ruby/3/config.h"
#include "ruby/defines.h"

#ifdef HAVE_STDARG_PROTOTYPES
# include <stdarg.h>
#else
# include <varargs.h>
#endif

#include "ruby/st.h"

/*
 * Functions and variables that are used by more than one source file of
 * the kernel.
 */

#include "ruby/3/intern/array.h"
#include "ruby/3/intern/bignum.h"
#include "ruby/3/intern/class.h"
#include "ruby/3/intern/compar.h"
#include "ruby/3/intern/complex.h"
#include "ruby/3/intern/cont.h"
#include "ruby/3/intern/dir.h"
#include "ruby/3/intern/enum.h"
#include "ruby/3/intern/enumerator.h"
#include "ruby/3/intern/error.h"
#include "ruby/3/intern/eval.h"
#include "ruby/3/intern/file.h"
#include "ruby/3/intern/gc.h"
#include "ruby/3/intern/hash.h"
#include "ruby/3/intern/io.h"
#include "ruby/3/intern/load.h"
#include "ruby/3/intern/marshal.h"
#include "ruby/3/intern/numeric.h"
#include "ruby/3/intern/object.h"
#include "ruby/3/intern/parse.h"
#include "ruby/3/intern/proc.h"
#include "ruby/3/intern/process.h"
#include "ruby/3/intern/random.h"
#include "ruby/3/intern/range.h"
#include "ruby/3/intern/rational.h"
#include "ruby/3/intern/re.h"
#include "ruby/3/intern/ruby.h"
#include "ruby/3/intern/select.h"
#include "ruby/3/intern/signal.h"
#include "ruby/3/intern/sprintf.h"
#include "ruby/3/intern/string.h"
#include "ruby/3/intern/struct.h"
#include "ruby/3/intern/thread.h"
#include "ruby/3/intern/time.h"
#include "ruby/3/intern/variable.h"
#include "ruby/3/intern/vm.h"

#endif /* RUBY_INTERN_H */
