#ifndef RUBYSPEC_H
#define RUBYSPEC_H

/* Define convenience macros similar to the mspec
 * guards to assist with version incompatibilities. */

#include <ruby.h>
#ifdef HAVE_RUBY_VERSION_H
# include <ruby/version.h>
#else
# include <version.h>
#endif

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

#ifndef RUBY_VERSION_MAJOR
#define RUBY_VERSION_MAJOR RUBY_API_VERSION_MAJOR
#define RUBY_VERSION_MINOR RUBY_API_VERSION_MINOR
#define RUBY_VERSION_TEENY RUBY_API_VERSION_TEENY
#endif

#define RUBY_VERSION_BEFORE(major,minor,teeny) \
  ((RUBY_VERSION_MAJOR < (major)) || \
   (RUBY_VERSION_MAJOR == (major) && RUBY_VERSION_MINOR < (minor)) || \
   (RUBY_VERSION_MAJOR == (major) && RUBY_VERSION_MINOR == (minor) && RUBY_VERSION_TEENY < (teeny)))
#define RUBY_VERSION_SINCE(major,minor,teeny) (!RUBY_VERSION_BEFORE(major, minor, teeny))

#if RUBY_VERSION_SINCE(3, 4, 0)
#define RUBY_VERSION_IS_3_4
#endif

#if RUBY_VERSION_SINCE(3, 3, 0)
#define RUBY_VERSION_IS_3_3
#endif

#if RUBY_VERSION_SINCE(3, 2, 0)
#define RUBY_VERSION_IS_3_2
#endif

#if RUBY_VERSION_SINCE(3, 1, 0)
#define RUBY_VERSION_IS_3_1
#endif

#if RUBY_VERSION_SINCE(3, 0, 0)
#define RUBY_VERSION_IS_3_0
#endif

#endif
