/**
 * @file compiler/cplusplus.hpp
 */
#ifndef PRISM_COMPILER_CPLUSPLUS_HPP
#define PRISM_COMPILER_CPLUSPLUS_HPP

/**
 * The C++ interface relies on C++17 for inline variables, std::string_view,
 * std::void_t, and std::is_invocable_r_v. MSVC reports __cplusplus as 199711L
 * unless /Zc:__cplusplus is passed, so its own _MSVC_LANG is checked as well.
 */
#if !defined(__cplusplus) || ((__cplusplus < 201703L) && (!defined(_MSVC_LANG) || (_MSVC_LANG < 201703L)))
#   error "the prism C++ interface requires C++17 or later"
#endif

#endif
