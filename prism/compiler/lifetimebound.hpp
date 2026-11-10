/**
 * @file compiler/lifetimebound.hpp
 */
#ifndef PRISM_COMPILER_LIFETIMEBOUND_HPP
#define PRISM_COMPILER_LIFETIMEBOUND_HPP

/**
 * Mark a parameter that the return value points into, so that the compiler
 * warns if a temporary is passed and the return value outlives it. If it is
 * placed after the qualifiers of a member function, it marks the object
 * instead.
 */
#if defined(__has_cpp_attribute)
#   if __has_cpp_attribute(clang::lifetimebound)
#       define PRISM_LIFETIMEBOUND [[clang::lifetimebound]]
#   elif __has_cpp_attribute(msvc::lifetimebound)
#       define PRISM_LIFETIMEBOUND [[msvc::lifetimebound]]
#   endif
#endif

#ifndef PRISM_LIFETIMEBOUND
#   define PRISM_LIFETIMEBOUND
#endif

#endif
