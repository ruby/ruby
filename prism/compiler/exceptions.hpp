/**
 * @file compiler/exceptions.hpp
 */
#ifndef PRISM_COMPILER_EXCEPTIONS_HPP
#define PRISM_COMPILER_EXCEPTIONS_HPP

/**
 * Defined when C++ exceptions are enabled, so that code which catches them can
 * still compile in builds that disable them, such as with -fno-exceptions.
 * __cpp_exceptions is the standard feature test macro, and older versions of
 * GCC and MSVC define __EXCEPTIONS and _CPPUNWIND instead.
 */
#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
#   define PRISM_HAS_EXCEPTIONS
#endif

#endif
