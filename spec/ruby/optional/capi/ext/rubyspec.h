#ifndef RUBYSPEC_H
#define RUBYSPEC_H

/* Define convenience macros similar to the mspec
 * guards to assist with version incompatibilities. */

#include <ruby.h>
#include <ruby/version.h>

/* copied from ext/-test-/cxxanyargs/cxxanyargs.cpp */
#if 0 /* Ignore deprecation warnings */

#elif defined(_MSC_VER)
#pragma warning(disable : 4996)

#elif defined(__INTEL_COMPILER)
#pragma warning(disable : 1786)

#elif defined(__clang__)
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#elif defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#elif defined(__SUNPRO_CC)
#pragma error_messages (off,symdeprecated)

#else
// :FIXME: improve here for your compiler.

#endif

#define RUBY_VERSION_BEFORE(major,minor) \
  ((RUBY_API_VERSION_MAJOR < (major)) || \
   (RUBY_API_VERSION_MAJOR == (major) && RUBY_API_VERSION_MINOR < (minor)))
#define RUBY_VERSION_SINCE(major,minor) (!RUBY_VERSION_BEFORE(major, minor))

#if RUBY_VERSION_SINCE(3, 5)
#define RUBY_VERSION_IS_3_5
#endif

#if RUBY_VERSION_SINCE(3, 4)
#define RUBY_VERSION_IS_3_4
#endif

#if RUBY_VERSION_SINCE(3, 3)
#define RUBY_VERSION_IS_3_3
#endif

#endif
