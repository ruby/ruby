#ifndef RBIMPL_INTERN_SET_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SET_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Public APIs related to ::rb_cSet.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* set.c */

RBIMPL_ATTR_NONNULL(())
/**
 * Iterates   over  a   set.  Calls func with each element of the set and the
 * argument given. func should return ST_CONTINUE, ST_STOP, or ST_DELETE.
 *
 * @param[in]  set               An instance of ::rb_cSet to iterate over.
 * @param[in]  func              Callback function to yield.
 * @param[in]  arg               Passed as-is to `func`.
 * @exception  rb_eRuntimeError  `set` was tampered during iterating.
 */
void rb_set_foreach(VALUE set, int (*func)(VALUE element, VALUE arg), VALUE arg);

/**
 * Creates a new, empty set object.
 *
 * @return  An allocated new instance of ::rb_cSet.
 */
VALUE rb_set_new(void);

/**
 * Identical to rb_set_new(), except it additionally specifies how many elements
 * it is expected to contain. This way you can create a set that is large enough
 * for your need. For large sets, it means it won't need to be reallocated
 * much, improving performance.
 *
 * @param[in]  capa  Designed capacity of the set.
 * @return     An empty Set, whose capacity is `capa`.
 */
VALUE rb_set_new_capa(size_t capa);

/**
 * Whether the set contains the given element.
 *
 * @param[in]  set      Set to look into.
 * @param[in]  element  Set element to look for.
 * @return     true if element is in the set, falst otherwise.
 */
bool rb_set_lookup(VALUE set, VALUE element);

/**
 * Adds element to set.
 *
 * @param[in]   set              Target set table to modify.
 * @param[in]   element          Arbitrary Ruby object.
 * @exception   rb_eFrozenError  `set` is frozen.
 * @return      true if element was not already in set, false otherwise
 * @post        `element` is in `set`.
 */
bool rb_set_add(VALUE set, VALUE element);

/**
 * Removes all entries from set.
 *
 * @param[out]  set             Target to clear.
 * @exception   rb_eFrozenError  `set`is frozen.
 * @return      The passed `set`
 * @post        `set` has no elements.
 */
VALUE rb_set_clear(VALUE set);

/**
 * Removes the element from from set.
 *
 * @param[in]   set        Target set to modify.
 * @param[in]   element    Key to delete.
 * @retval      true if element was already in set, false otherwise
 * @post        `set` does not have `element` as an element.
 */
bool rb_set_delete(VALUE set, VALUE element);

/**
 * Returns the number of elements in the set.
 *
 * @param[in]  set  A set object.
 * @return     The size of the set.
 */
size_t rb_set_size(VALUE set);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_SET_H */
