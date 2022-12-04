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

#ifndef RUBY_VERSION_MAJOR
#define RUBY_VERSION_MAJOR RUBY_API_VERSION_MAJOR
#define RUBY_VERSION_MINOR RUBY_API_VERSION_MINOR
#define RUBY_VERSION_TEENY RUBY_API_VERSION_TEENY
#endif

#define RUBY_VERSION_BEFORE(major,minor,teeny) \
  ((RUBY_VERSION_MAJOR < (major)) || \
   (RUBY_VERSION_MAJOR == (major) && RUBY_VERSION_MINOR < (minor)) || \
   (RUBY_VERSION_MAJOR == (major) && RUBY_VERSION_MINOR == (minor) && RUBY_VERSION_TEENY < (teeny)))

#if RUBY_VERSION_MAJOR > 3 || (RUBY_VERSION_MAJOR == 3 && RUBY_VERSION_MINOR >= 2)
#define RUBY_VERSION_IS_3_2
#endif

#if RUBY_VERSION_MAJOR > 3 || (RUBY_VERSION_MAJOR == 3 && RUBY_VERSION_MINOR >= 1)
#define RUBY_VERSION_IS_3_1
#endif

#if RUBY_VERSION_MAJOR > 3 || (RUBY_VERSION_MAJOR == 3 && RUBY_VERSION_MINOR >= 0)
#define RUBY_VERSION_IS_3_0
#endif

#endif
