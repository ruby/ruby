/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      C counterpart of include/backward/cxxanyargs.hpp
 *
 * With those  complex macro  overlays defined  in this header  file, use  of a
 * function  pointer gets  checked  against the  corresponding arity  argument.
 * This of course improves overall code quality.
 */
#ifndef  RUBY3_ANYARGS_H
#define  RUBY3_ANYARGS_H
#include "ruby/3/config.h"
#include "ruby/3/value.h"
#include "ruby/3/method.h"
#include "ruby/3/intern/class.h"
#include "ruby/3/intern/vm.h"
#include "ruby/backward/2/stdarg.h"

#if defined(__cplusplus)
#include "ruby/backward/cxxanyargs.hpp"
#else

#if !defined(__has_attribute)
#define __has_attribute(x) 0
#endif

#if defined(HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P)
# define rb_f_notimplement_p(f) __builtin_types_compatible_p(__typeof__(f),__typeof__(rb_f_notimplement))
#else
# define rb_f_notimplement_p(f) 0
#endif

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
#define rb_define_method_if_constexpr(x, t, f)    __builtin_choose_expr(__builtin_choose_expr(__builtin_constant_p(x),(x),0),(t),(f))
#endif

#if defined(__has_attribute) && __has_attribute(transparent_union) && __has_attribute(unused) && __has_attribute(weakref) && __has_attribute(nonnull)
#define RB_METHOD_DEFINITION_DECL(def, nonnull, ...) \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## m3(__VA_ARGS__, VALUE(*)(ANYARGS), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## m2(__VA_ARGS__, VALUE(*)(VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## m1(__VA_ARGS__, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  0(__VA_ARGS__, VALUE(*)(VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  1(__VA_ARGS__, VALUE(*)(VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  2(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  3(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  4(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  5(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  6(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  7(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  8(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ##  9(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## 10(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## 11(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## 12(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## 13(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## 14(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
__attribute__((__unused__, __weakref__(#def), __nonnull__ nonnull)) static void def ## 15(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
#endif

#if defined(RB_METHOD_DEFINITION_DECL) && !defined(_WIN32) && !defined(__CYGWIN__)

RB_METHOD_DEFINITION_DECL(rb_define_method_id, (3), VALUE klass, ID name)
#define rb_define_method_id_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_method_id15,rb_define_method_idm3)
#define rb_define_method_id_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_method_id14,rb_define_method_id_choose_prototype15(n))
#define rb_define_method_id_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_method_id13,rb_define_method_id_choose_prototype14(n))
#define rb_define_method_id_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_method_id12,rb_define_method_id_choose_prototype13(n))
#define rb_define_method_id_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_method_id11,rb_define_method_id_choose_prototype12(n))
#define rb_define_method_id_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_method_id10,rb_define_method_id_choose_prototype11(n))
#define rb_define_method_id_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_method_id9, rb_define_method_id_choose_prototype10(n))
#define rb_define_method_id_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_method_id8, rb_define_method_id_choose_prototype9(n))
#define rb_define_method_id_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_method_id7, rb_define_method_id_choose_prototype8(n))
#define rb_define_method_id_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_method_id6, rb_define_method_id_choose_prototype7(n))
#define rb_define_method_id_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_method_id5, rb_define_method_id_choose_prototype6(n))
#define rb_define_method_id_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_method_id4, rb_define_method_id_choose_prototype5(n))
#define rb_define_method_id_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_method_id3, rb_define_method_id_choose_prototype4(n))
#define rb_define_method_id_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_method_id2, rb_define_method_id_choose_prototype3(n))
#define rb_define_method_id_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_method_id1, rb_define_method_id_choose_prototype2(n))
#define rb_define_method_id_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_method_id0, rb_define_method_id_choose_prototype1(n))
#define rb_define_method_id_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_method_idm1,rb_define_method_id_choose_prototype0(n))
#define rb_define_method_id_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_method_idm2,rb_define_method_id_choose_prototypem1(n))
#define rb_define_method_id_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_method_idm3,rb_define_method_id_choose_prototypem2(n))
#define rb_define_method_id(klass, mid, func, arity) rb_define_method_id_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));

RB_METHOD_DEFINITION_DECL(rb_define_protected_method, (2,3), VALUE klass, const char *name)
#define rb_define_protected_method_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_protected_method15,rb_define_protected_methodm3)
#define rb_define_protected_method_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_protected_method14,rb_define_protected_method_choose_prototype15(n))
#define rb_define_protected_method_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_protected_method13,rb_define_protected_method_choose_prototype14(n))
#define rb_define_protected_method_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_protected_method12,rb_define_protected_method_choose_prototype13(n))
#define rb_define_protected_method_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_protected_method11,rb_define_protected_method_choose_prototype12(n))
#define rb_define_protected_method_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_protected_method10,rb_define_protected_method_choose_prototype11(n))
#define rb_define_protected_method_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_protected_method9, rb_define_protected_method_choose_prototype10(n))
#define rb_define_protected_method_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_protected_method8, rb_define_protected_method_choose_prototype9(n))
#define rb_define_protected_method_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_protected_method7, rb_define_protected_method_choose_prototype8(n))
#define rb_define_protected_method_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_protected_method6, rb_define_protected_method_choose_prototype7(n))
#define rb_define_protected_method_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_protected_method5, rb_define_protected_method_choose_prototype6(n))
#define rb_define_protected_method_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_protected_method4, rb_define_protected_method_choose_prototype5(n))
#define rb_define_protected_method_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_protected_method3, rb_define_protected_method_choose_prototype4(n))
#define rb_define_protected_method_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_protected_method2, rb_define_protected_method_choose_prototype3(n))
#define rb_define_protected_method_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_protected_method1, rb_define_protected_method_choose_prototype2(n))
#define rb_define_protected_method_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_protected_method0, rb_define_protected_method_choose_prototype1(n))
#define rb_define_protected_method_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_protected_methodm1,rb_define_protected_method_choose_prototype0(n))
#define rb_define_protected_method_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_protected_methodm2,rb_define_protected_method_choose_prototypem1(n))
#define rb_define_protected_method_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_protected_methodm3,rb_define_protected_method_choose_prototypem2(n))
#define rb_define_protected_method(klass, mid, func, arity) rb_define_protected_method_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));

RB_METHOD_DEFINITION_DECL(rb_define_private_method, (2,3), VALUE klass, const char *name)
#define rb_define_private_method_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_private_method15,rb_define_private_methodm3)
#define rb_define_private_method_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_private_method14,rb_define_private_method_choose_prototype15(n))
#define rb_define_private_method_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_private_method13,rb_define_private_method_choose_prototype14(n))
#define rb_define_private_method_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_private_method12,rb_define_private_method_choose_prototype13(n))
#define rb_define_private_method_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_private_method11,rb_define_private_method_choose_prototype12(n))
#define rb_define_private_method_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_private_method10,rb_define_private_method_choose_prototype11(n))
#define rb_define_private_method_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_private_method9, rb_define_private_method_choose_prototype10(n))
#define rb_define_private_method_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_private_method8, rb_define_private_method_choose_prototype9(n))
#define rb_define_private_method_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_private_method7, rb_define_private_method_choose_prototype8(n))
#define rb_define_private_method_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_private_method6, rb_define_private_method_choose_prototype7(n))
#define rb_define_private_method_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_private_method5, rb_define_private_method_choose_prototype6(n))
#define rb_define_private_method_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_private_method4, rb_define_private_method_choose_prototype5(n))
#define rb_define_private_method_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_private_method3, rb_define_private_method_choose_prototype4(n))
#define rb_define_private_method_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_private_method2, rb_define_private_method_choose_prototype3(n))
#define rb_define_private_method_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_private_method1, rb_define_private_method_choose_prototype2(n))
#define rb_define_private_method_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_private_method0, rb_define_private_method_choose_prototype1(n))
#define rb_define_private_method_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_private_methodm1,rb_define_private_method_choose_prototype0(n))
#define rb_define_private_method_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_private_methodm2,rb_define_private_method_choose_prototypem1(n))
#define rb_define_private_method_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_private_methodm3,rb_define_private_method_choose_prototypem2(n))
#define rb_define_private_method(klass, mid, func, arity) rb_define_private_method_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));

RB_METHOD_DEFINITION_DECL(rb_define_singleton_method, (2,3), VALUE klass, const char *name)
#define rb_define_singleton_method_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_singleton_method15,rb_define_singleton_methodm3)
#define rb_define_singleton_method_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_singleton_method14,rb_define_singleton_method_choose_prototype15(n))
#define rb_define_singleton_method_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_singleton_method13,rb_define_singleton_method_choose_prototype14(n))
#define rb_define_singleton_method_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_singleton_method12,rb_define_singleton_method_choose_prototype13(n))
#define rb_define_singleton_method_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_singleton_method11,rb_define_singleton_method_choose_prototype12(n))
#define rb_define_singleton_method_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_singleton_method10,rb_define_singleton_method_choose_prototype11(n))
#define rb_define_singleton_method_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_singleton_method9, rb_define_singleton_method_choose_prototype10(n))
#define rb_define_singleton_method_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_singleton_method8, rb_define_singleton_method_choose_prototype9(n))
#define rb_define_singleton_method_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_singleton_method7, rb_define_singleton_method_choose_prototype8(n))
#define rb_define_singleton_method_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_singleton_method6, rb_define_singleton_method_choose_prototype7(n))
#define rb_define_singleton_method_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_singleton_method5, rb_define_singleton_method_choose_prototype6(n))
#define rb_define_singleton_method_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_singleton_method4, rb_define_singleton_method_choose_prototype5(n))
#define rb_define_singleton_method_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_singleton_method3, rb_define_singleton_method_choose_prototype4(n))
#define rb_define_singleton_method_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_singleton_method2, rb_define_singleton_method_choose_prototype3(n))
#define rb_define_singleton_method_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_singleton_method1, rb_define_singleton_method_choose_prototype2(n))
#define rb_define_singleton_method_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_singleton_method0, rb_define_singleton_method_choose_prototype1(n))
#define rb_define_singleton_method_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_singleton_methodm1,rb_define_singleton_method_choose_prototype0(n))
#define rb_define_singleton_method_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_singleton_methodm2,rb_define_singleton_method_choose_prototypem1(n))
#define rb_define_singleton_method_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_singleton_methodm3,rb_define_singleton_method_choose_prototypem2(n))
#define rb_define_singleton_method(klass, mid, func, arity) rb_define_singleton_method_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));

RB_METHOD_DEFINITION_DECL(rb_define_method, (2,3), VALUE klass, const char *name)
#define rb_define_method_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_method15,rb_define_methodm3)
#define rb_define_method_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_method14,rb_define_method_choose_prototype15(n))
#define rb_define_method_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_method13,rb_define_method_choose_prototype14(n))
#define rb_define_method_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_method12,rb_define_method_choose_prototype13(n))
#define rb_define_method_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_method11,rb_define_method_choose_prototype12(n))
#define rb_define_method_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_method10,rb_define_method_choose_prototype11(n))
#define rb_define_method_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_method9, rb_define_method_choose_prototype10(n))
#define rb_define_method_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_method8, rb_define_method_choose_prototype9(n))
#define rb_define_method_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_method7, rb_define_method_choose_prototype8(n))
#define rb_define_method_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_method6, rb_define_method_choose_prototype7(n))
#define rb_define_method_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_method5, rb_define_method_choose_prototype6(n))
#define rb_define_method_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_method4, rb_define_method_choose_prototype5(n))
#define rb_define_method_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_method3, rb_define_method_choose_prototype4(n))
#define rb_define_method_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_method2, rb_define_method_choose_prototype3(n))
#define rb_define_method_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_method1, rb_define_method_choose_prototype2(n))
#define rb_define_method_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_method0, rb_define_method_choose_prototype1(n))
#define rb_define_method_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_methodm1,rb_define_method_choose_prototype0(n))
#define rb_define_method_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_methodm2,rb_define_method_choose_prototypem1(n))
#define rb_define_method_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_methodm3,rb_define_method_choose_prototypem2(n))
#define rb_define_method(klass, mid, func, arity) rb_define_method_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));

RB_METHOD_DEFINITION_DECL(rb_define_module_function, (2,3), VALUE klass, const char *name)
#define rb_define_module_function_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_module_function15,rb_define_module_functionm3)
#define rb_define_module_function_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_module_function14,rb_define_module_function_choose_prototype15(n))
#define rb_define_module_function_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_module_function13,rb_define_module_function_choose_prototype14(n))
#define rb_define_module_function_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_module_function12,rb_define_module_function_choose_prototype13(n))
#define rb_define_module_function_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_module_function11,rb_define_module_function_choose_prototype12(n))
#define rb_define_module_function_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_module_function10,rb_define_module_function_choose_prototype11(n))
#define rb_define_module_function_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_module_function9, rb_define_module_function_choose_prototype10(n))
#define rb_define_module_function_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_module_function8, rb_define_module_function_choose_prototype9(n))
#define rb_define_module_function_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_module_function7, rb_define_module_function_choose_prototype8(n))
#define rb_define_module_function_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_module_function6, rb_define_module_function_choose_prototype7(n))
#define rb_define_module_function_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_module_function5, rb_define_module_function_choose_prototype6(n))
#define rb_define_module_function_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_module_function4, rb_define_module_function_choose_prototype5(n))
#define rb_define_module_function_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_module_function3, rb_define_module_function_choose_prototype4(n))
#define rb_define_module_function_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_module_function2, rb_define_module_function_choose_prototype3(n))
#define rb_define_module_function_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_module_function1, rb_define_module_function_choose_prototype2(n))
#define rb_define_module_function_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_module_function0, rb_define_module_function_choose_prototype1(n))
#define rb_define_module_function_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_module_functionm1,rb_define_module_function_choose_prototype0(n))
#define rb_define_module_function_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_module_functionm2,rb_define_module_function_choose_prototypem1(n))
#define rb_define_module_function_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_module_functionm3,rb_define_module_function_choose_prototypem2(n))
#define rb_define_module_function(klass, mid, func, arity) rb_define_module_function_choose_prototypem3((arity),(func))((klass),(mid),(func),(arity));

RB_METHOD_DEFINITION_DECL(rb_define_global_function, (1,2), const char *name)
#define rb_define_global_function_choose_prototype15(n)    rb_define_method_if_constexpr((n)==15,rb_define_global_function15,rb_define_global_functionm3)
#define rb_define_global_function_choose_prototype14(n)    rb_define_method_if_constexpr((n)==14,rb_define_global_function14,rb_define_global_function_choose_prototype15(n))
#define rb_define_global_function_choose_prototype13(n)    rb_define_method_if_constexpr((n)==13,rb_define_global_function13,rb_define_global_function_choose_prototype14(n))
#define rb_define_global_function_choose_prototype12(n)    rb_define_method_if_constexpr((n)==12,rb_define_global_function12,rb_define_global_function_choose_prototype13(n))
#define rb_define_global_function_choose_prototype11(n)    rb_define_method_if_constexpr((n)==11,rb_define_global_function11,rb_define_global_function_choose_prototype12(n))
#define rb_define_global_function_choose_prototype10(n)    rb_define_method_if_constexpr((n)==10,rb_define_global_function10,rb_define_global_function_choose_prototype11(n))
#define rb_define_global_function_choose_prototype9(n)     rb_define_method_if_constexpr((n)== 9,rb_define_global_function9, rb_define_global_function_choose_prototype10(n))
#define rb_define_global_function_choose_prototype8(n)     rb_define_method_if_constexpr((n)== 8,rb_define_global_function8, rb_define_global_function_choose_prototype9(n))
#define rb_define_global_function_choose_prototype7(n)     rb_define_method_if_constexpr((n)== 7,rb_define_global_function7, rb_define_global_function_choose_prototype8(n))
#define rb_define_global_function_choose_prototype6(n)     rb_define_method_if_constexpr((n)== 6,rb_define_global_function6, rb_define_global_function_choose_prototype7(n))
#define rb_define_global_function_choose_prototype5(n)     rb_define_method_if_constexpr((n)== 5,rb_define_global_function5, rb_define_global_function_choose_prototype6(n))
#define rb_define_global_function_choose_prototype4(n)     rb_define_method_if_constexpr((n)== 4,rb_define_global_function4, rb_define_global_function_choose_prototype5(n))
#define rb_define_global_function_choose_prototype3(n)     rb_define_method_if_constexpr((n)== 3,rb_define_global_function3, rb_define_global_function_choose_prototype4(n))
#define rb_define_global_function_choose_prototype2(n)     rb_define_method_if_constexpr((n)== 2,rb_define_global_function2, rb_define_global_function_choose_prototype3(n))
#define rb_define_global_function_choose_prototype1(n)     rb_define_method_if_constexpr((n)== 1,rb_define_global_function1, rb_define_global_function_choose_prototype2(n))
#define rb_define_global_function_choose_prototype0(n)     rb_define_method_if_constexpr((n)== 0,rb_define_global_function0, rb_define_global_function_choose_prototype1(n))
#define rb_define_global_function_choose_prototypem1(n)    rb_define_method_if_constexpr((n)==-1,rb_define_global_functionm1,rb_define_global_function_choose_prototype0(n))
#define rb_define_global_function_choose_prototypem2(n)    rb_define_method_if_constexpr((n)==-2,rb_define_global_functionm2,rb_define_global_function_choose_prototypem1(n))
#define rb_define_global_function_choose_prototypem3(n, f) rb_define_method_if_constexpr(rb_f_notimplement_p(f),rb_define_global_functionm3,rb_define_global_function_choose_prototypem2(n))
#define rb_define_global_function(mid, func, arity) rb_define_global_function_choose_prototypem3((arity),(func))((mid),(func),(arity));

#endif  /* ! _WIN32 && ! __CYGWIN__ */

#endif /* __cplusplus */

#if defined(RUBY_DEVEL) && RUBY_DEVEL && (!defined(__cplusplus) || defined(RB_METHOD_DEFINITION_DECL))
# define RUBY_METHOD_FUNC(func) (func)
#else
# define RUBY_METHOD_FUNC(func) ((VALUE (*)(ANYARGS))(func))
#endif

#endif /* RUBY3_ANYARGS_H */
