#ifndef RUBY_BACKWARD_CXXANYARGS_HPP // -*- C++ -*-
#define RUBY_BACKWARD_CXXANYARGS_HPP
/// @file
/// @brief      Provides old prototypes for C++ programs.
/// @author     \@shyouhei
/// @copyright  This  file  is  a  part   of  the  programming  language  Ruby.
///             Permission  is hereby  granted, to  either redistribute  and/or
///             modify this file, provided that the conditions mentioned in the
///             file COPYING are met.  Consult the file for details.
/// @note       DO NOT  MODERNIZE THIS FILE!   As the  file name implies  it is
///             meant to  be a backwards  compatibility shim.  Please  stick to
///             C++ 98 and never use newer features, like `constexpr`.

/// @brief  The main namespace.
/// @note   The name  "ruby" might  already be  taken, but that  must not  be a
///         problem because namespaces are allowed to reopen.
namespace ruby {

/// @brief  Backwards compatibility layer.
namespace backward {

/// @brief  Provides ANYARGS deprecation warnings.
///
/// In C,  ANYARGS means there  is no function prototype.   Literally anything,
/// even including  nothing, can be  a valid  ANYARGS.  So passing  a correctly
/// prototyped function pointer  to an ANYARGS-ed function  parameter is valid,
/// at the same time passing an ANYARGS-ed function pointer to a granular typed
/// function  parameter is  also  valid.  However  on the  other  hand in  C++,
/// ANYARGS doesn't actually mean any number of arguments.  C++'s ANYARGS means
/// _variadic_ number of arguments.  This is incompatible with ordinal, correct
/// function prototypes.
///
/// Luckily, function  prototypes being distinct  each other means they  can be
/// overloaded.  We can provide a compatibility layer for older Ruby APIs which
/// used to have ANYARGS.  This namespace includes such attempts.
namespace cxxanyargs {

/// @brief ANYARGS-ed function type.
typedef VALUE type(ANYARGS);

/// @brief ANYARGS-ed function type, void variant.
typedef void void_type(ANYARGS);

/// @brief ANYARGS-ed function type, int variant.
typedef int int_type(ANYARGS);

/// @name Hooking global variables
/// @{

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Define a function-backended global variable.
/// @param[in]   q  Name of the variable.
/// @param[in]   w  Getter function.
/// @param[in]   e  Setter function.
/// @note        Both functions can be nullptr.
/// @see         rb_define_hooked_variable()
/// @deprecated  Use glanular typed overload instead.
inline void
rb_define_virtual_variable(const char *q, type *w, void_type *e)
{
    rb_gvar_getter_t *r = reinterpret_cast<rb_gvar_getter_t*>(w);
    rb_gvar_setter_t *t = reinterpret_cast<rb_gvar_setter_t*>(e);
    ::rb_define_virtual_variable(q, r, t);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Define a function-backended global variable.
/// @param[in]   q  Name of the variable.
/// @param[in]   w  Getter function.
/// @param[in]   e  Setter function.
/// @note        Both functions can be nullptr.
/// @see         rb_define_hooked_variable()
/// @deprecated  Use glanular typed overload instead.
inline void
rb_define_virtual_variable(const char *q, rb_gvar_getter_t *w, void_type *e)
{
    rb_gvar_setter_t *t = reinterpret_cast<rb_gvar_setter_t*>(e);
    ::rb_define_virtual_variable(q, w, t);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Define a function-backended global variable.
/// @param[in]   q  Name of the variable.
/// @param[in]   w  Getter function.
/// @param[in]   e  Setter function.
/// @note        Both functions can be nullptr.
/// @see         rb_define_hooked_variable()
/// @deprecated  Use glanular typed overload instead.
inline void
rb_define_virtual_variable(const char *q, type *w, rb_gvar_setter_t *e)
{
    rb_gvar_getter_t *r = reinterpret_cast<rb_gvar_getter_t*>(w);
    ::rb_define_virtual_variable(q, r, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Define a function-backended global variable.
/// @param[in]   q  Name of the variable.
/// @param[in]   w  Variable storage.
/// @param[in]   e  Getter function.
/// @param[in]   r  Setter function.
/// @note        Both functions can be nullptr.
/// @see         rb_define_virtual_variable()
/// @deprecated  Use glanular typed overload instead.
inline void
rb_define_hooked_variable(const char *q, VALUE *w, type *e, void_type *r)
{
    rb_gvar_getter_t *t = reinterpret_cast<rb_gvar_getter_t*>(e);
    rb_gvar_setter_t *y = reinterpret_cast<rb_gvar_setter_t*>(r);
    ::rb_define_hooked_variable(q, w, t, y);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Define a function-backended global variable.
/// @param[in]   q  Name of the variable.
/// @param[in]   w  Variable storage.
/// @param[in]   e  Getter function.
/// @param[in]   r  Setter function.
/// @note        Both functions can be nullptr.
/// @see         rb_define_virtual_variable()
/// @deprecated  Use glanular typed overload instead.
inline void
rb_define_hooked_variable(const char *q, VALUE *w, rb_gvar_getter_t *e, void_type *r)
{
    rb_gvar_setter_t *y = reinterpret_cast<rb_gvar_setter_t*>(r);
    ::rb_define_hooked_variable(q, w, e, y);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Define a function-backended global variable.
/// @param[in]   q  Name of the variable.
/// @param[in]   w  Variable storage.
/// @param[in]   e  Getter function.
/// @param[in]   r  Setter function.
/// @note        Both functions can be nullptr.
/// @see         rb_define_virtual_variable()
/// @deprecated  Use glanular typed overload instead.
inline void
rb_define_hooked_variable(const char *q, VALUE *w, type *e, rb_gvar_setter_t *r)
{
    rb_gvar_getter_t *t = reinterpret_cast<rb_gvar_getter_t*>(e);
    ::rb_define_hooked_variable(q, w, t, r);
}

/// @}
/// @name Exceptions and tag jumps
/// @{

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Old way to implement iterators.
/// @param[in]   q  A function that can yield.
/// @param[in]   w  Passed to `q`.
/// @param[in]   e  What is to be yielded.
/// @param[in]   r  Passed to `e`.
/// @return      The return value of `q`.
/// @note        `e` can be nullptr.
/// @deprecated  This function is obsolated since  long before 2.x era.  Do not
///              use it any longer.  rb_block_call() is provided instead.
inline VALUE
rb_iterate(VALUE(*q)(VALUE), VALUE w, type *e, VALUE r)
{
    rb_block_call_func_t t = reinterpret_cast<rb_block_call_func_t>(e);
    return ::rb_iterate(q, w, t, r);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Call a method with a block.
/// @param[in]   q  The self.
/// @param[in]   w  The method.
/// @param[in]   e  The # of elems of `r`
/// @param[in]   r  The arguments.
/// @param[in]   t  What is to be yielded.
/// @param[in]   y  Passed to `t`
/// @return      Return value of `q#w(*r,&t)`
/// @note        't' can be nullptr.
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_block_call(VALUE q, ID w, int e, const VALUE *r, type *t, VALUE y)
{
    rb_block_call_func_t u = reinterpret_cast<rb_block_call_func_t>(t);
    return ::rb_block_call(q, w, e, r, u, y);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       An equivalent of `rescue` clause.
/// @param[in]   q  A function that can raise.
/// @param[in]   w  Passed to `q`.
/// @param[in]   e  A function that cleans-up.
/// @param[in]   r  Passed to `e`.
/// @return      The return value of `q` if  no exception occurs, or the return
///              value of `e` if otherwise.
/// @note        `e` can be nullptr.
/// @see         rb_ensure()
/// @see         rb_rescue2()
/// @see         rb_protect()
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_rescue(type *q, VALUE w, type *e, VALUE r)
{
    typedef VALUE func1_t(VALUE);
    typedef VALUE func2_t(VALUE, VALUE);
    func1_t *t = reinterpret_cast<func1_t*>(q);
    func2_t *y = reinterpret_cast<func2_t*>(e);
    return ::rb_rescue(t, w, y, r);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       An equivalent of `rescue` clause.
/// @param[in]   q    A function that can raise.
/// @param[in]   w    Passed to `q`.
/// @param[in]   e    A function that cleans-up.
/// @param[in]   r    Passed to `e`.
/// @param[in]   ...  0-terminated list of subclass of @ref rb_eException.
/// @return      The return value of `q` if  no exception occurs, or the return
///              value of `e` if otherwise.
/// @note        `e` can be nullptr.
/// @see         rb_ensure()
/// @see         rb_rescue()
/// @see         rb_protect()
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_rescue2(type *q, VALUE w, type *e, VALUE r, ...)
{
    typedef VALUE func1_t(VALUE);
    typedef VALUE func2_t(VALUE, VALUE);
    func1_t *t = reinterpret_cast<func1_t*>(q);
    func2_t *y = reinterpret_cast<func2_t*>(e);
    va_list ap;
    va_start(ap, r);
    return ::rb_vrescue2(t, w, y, r, ap);
    va_end(ap);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       An equivalent of `ensure` clause.
/// @param[in]   q  A function that can raise.
/// @param[in]   w  Passed to `q`.
/// @param[in]   e  A function that ensures.
/// @param[in]   r  Passed to `e`.
/// @return      The return value of `q`.
/// @note        It makes no sense to pass nullptr to `e`.
/// @see         rb_rescue()
/// @see         rb_rescue2()
/// @see         rb_protect()
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_ensure(type *q, VALUE w, type *e, VALUE r)
{
    typedef VALUE func1_t(VALUE);
    func1_t *t = reinterpret_cast<func1_t*>(q);
    func1_t *y = reinterpret_cast<func1_t*>(e);
    return ::rb_ensure(t, w, y, r);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       An equivalent of `Kernel#catch`.
/// @param[in]   q  The "tag" string.
/// @param[in]   w  A function that can throw.
/// @param[in]   e  Passed to `w`.
/// @return      What was thrown.
/// @note        `q` can be a nullptr but makes no sense to pass nullptr to`w`.
/// @see         rb_block_call()
/// @see         rb_protect()
/// @see         rb_rb_catch_obj()
/// @see         rb_rescue()
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_catch(const char *q, type *w, VALUE e)
{
    rb_block_call_func_t r = reinterpret_cast<rb_block_call_func_t>(w);
    return ::rb_catch(q, r, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       An equivalent of `Kernel#catch`.
/// @param[in]   q  The "tag" object.
/// @param[in]   w  A function that can throw.
/// @param[in]   e  Passed to `w`.
/// @return      What was thrown.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         rb_block_call()
/// @see         rb_protect()
/// @see         rb_rb_catch_obj()
/// @see         rb_rescue()
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_catch_obj(VALUE q, type *w, VALUE e)
{
    rb_block_call_func_t r = reinterpret_cast<rb_block_call_func_t>(w);
    return ::rb_catch_obj(q, r, e);
}

/// @}
/// @name Procs, Fibers and Threads
/// @{

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Creates a @ref rb_cFiber instance.
/// @param[in]   q  The fiber body.
/// @param[in]   w  Passed to `q`.
/// @return      What was allocated.
/// @note        It makes no sense to pass nullptr to`q`.
/// @see         rb_proc_new()
/// @see         rb_thread_creatr()
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_fiber_new(type *q, VALUE w)
{
    rb_block_call_func_t e = reinterpret_cast<rb_block_call_func_t>(q);
    return ::rb_fiber_new(e, w);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Creates a @ref rb_cProc instance.
/// @param[in]   q  The proc body.
/// @param[in]   w  Passed to `q`.
/// @return      What was allocated.
/// @note        It makes no sense to pass nullptr to`q`.
/// @see         rb_fiber_new()
/// @see         rb_thread_creatr()
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_proc_new(type *q, VALUE w)
{
    rb_block_call_func_t e = reinterpret_cast<rb_block_call_func_t>(q);
    return ::rb_proc_new(e, w);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Creates a @ref rb_cThread instance.
/// @param[in]   q  The thread body.
/// @param[in]   w  Passed to `q`.
/// @return      What was allocated.
/// @note        It makes no sense to pass nullptr to`q`.
/// @see         rb_proc_new()
/// @see         rb_fiber_new()
/// @deprecated  Use glanular typed overload instead.
inline VALUE
rb_thread_create(type *q, void *w)
{
    typedef VALUE ptr_t(void*);
    ptr_t *e = reinterpret_cast<ptr_t*>(q);
    return ::rb_thread_create(e, w);
}

/// @}
/// @name Hash and st_table
/// @{

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Iteration over the given table.
/// @param[in]   q  A table to scan.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @retval      0  Always returns 0.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach_check()
/// @see         rb_hash_foreach()
/// @deprecated  Use glanular typed overload instead.
inline int
st_foreach(st_table *q, int_type *w, st_data_t e)
{
    st_foreach_callback_func *r =
        reinterpret_cast<st_foreach_callback_func*>(w);
    return ::st_foreach(q, r, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Iteration over the given table.
/// @param[in]   q  A table to scan.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @retval      0  Successful end of iteration.
/// @retval      1  Element removed during traversing.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach()
/// @deprecated  Use glanular typed overload instead.
inline int
st_foreach_check(st_table *q, int_type *w, st_data_t e, st_data_t)
{
    st_foreach_check_callback_func *t =
        reinterpret_cast<st_foreach_check_callback_func*>(w);
    return ::st_foreach_check(q, t, e, 0);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Iteration over the given table.
/// @param[in]   q  A table to scan.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach_check()
/// @deprecated  Use glanular typed overload instead.
inline void
st_foreach_safe(st_table *q, int_type *w, st_data_t e)
{
    st_foreach_callback_func *r =
        reinterpret_cast<st_foreach_callback_func*>(w);
    ::st_foreach_safe(q, r, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Iteration over the given hash.
/// @param[in]   q  A hash to scan.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach()
/// @deprecated  Use glanular typed overload instead.
inline void
rb_hash_foreach(VALUE q, int_type *w, VALUE e)
{
    st_foreach_callback_func *r =
        reinterpret_cast<st_foreach_callback_func*>(w);
    ::rb_hash_foreach(q, r, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprected")
/// @brief       Iteration over each instance variable of the object.
/// @param[in]   q  An object.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach()
/// @deprecated  Use glanular typed overload instead.
inline void
rb_ivar_foreach(VALUE q, int_type *w, VALUE e)
{
    st_foreach_callback_func *r =
        reinterpret_cast<st_foreach_callback_func*>(w);
    ::rb_ivar_foreach(q, r, e);
}

/// @}
}}}

using namespace ruby::backward::cxxanyargs;
#endif // RUBY_BACKWARD_CXXANYARGS_HPP
