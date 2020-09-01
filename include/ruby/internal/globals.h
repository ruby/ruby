#ifndef RBIMPL_GLOBALS_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_GLOBALS_H
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
 *             extension libraries. They could be written in C++98.
 * @brief      Ruby-level global variables / constants, visible from C.
 */
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

#define RUBY_INTEGER_UNIFICATION 1

RUBY_EXTERN VALUE rb_mKernel;
RUBY_EXTERN VALUE rb_mComparable;
RUBY_EXTERN VALUE rb_mEnumerable;
RUBY_EXTERN VALUE rb_mErrno;
RUBY_EXTERN VALUE rb_mFileTest;
RUBY_EXTERN VALUE rb_mGC;
RUBY_EXTERN VALUE rb_mMath;
RUBY_EXTERN VALUE rb_mProcess;
RUBY_EXTERN VALUE rb_mWaitReadable;
RUBY_EXTERN VALUE rb_mWaitWritable;

RUBY_EXTERN VALUE rb_cBasicObject;
RUBY_EXTERN VALUE rb_cObject;
RUBY_EXTERN VALUE rb_cArray;
RUBY_EXTERN VALUE rb_cBinding;
RUBY_EXTERN VALUE rb_cClass;
RUBY_EXTERN VALUE rb_cCont;
RBIMPL_ATTR_DEPRECATED(("by: rb_cObject.  Will be removed in 3.1."))
RUBY_EXTERN VALUE rb_cData;
RUBY_EXTERN VALUE rb_cDir;
RUBY_EXTERN VALUE rb_cEncoding;
RUBY_EXTERN VALUE rb_cEnumerator;
RUBY_EXTERN VALUE rb_cFalseClass;
RUBY_EXTERN VALUE rb_cFile;
RUBY_EXTERN VALUE rb_cComplex;
RUBY_EXTERN VALUE rb_cFloat;
RUBY_EXTERN VALUE rb_cHash;
RUBY_EXTERN VALUE rb_cIO;
RUBY_EXTERN VALUE rb_cInteger;
RUBY_EXTERN VALUE rb_cMatch;
RUBY_EXTERN VALUE rb_cMethod;
RUBY_EXTERN VALUE rb_cModule;
RUBY_EXTERN VALUE rb_cNameErrorMesg;
RUBY_EXTERN VALUE rb_cNilClass;
RUBY_EXTERN VALUE rb_cNumeric;
RUBY_EXTERN VALUE rb_cProc;
RUBY_EXTERN VALUE rb_cRandom;
RUBY_EXTERN VALUE rb_cRange;
RUBY_EXTERN VALUE rb_cRational;
RUBY_EXTERN VALUE rb_cRegexp;
RUBY_EXTERN VALUE rb_cStat;
RUBY_EXTERN VALUE rb_cString;
RUBY_EXTERN VALUE rb_cStruct;
RUBY_EXTERN VALUE rb_cSymbol;
RUBY_EXTERN VALUE rb_cThread;
RUBY_EXTERN VALUE rb_cTime;
RUBY_EXTERN VALUE rb_cTrueClass;
RUBY_EXTERN VALUE rb_cUnboundMethod;

RUBY_EXTERN VALUE rb_eException;
RUBY_EXTERN VALUE rb_eStandardError;
RUBY_EXTERN VALUE rb_eSystemExit;
RUBY_EXTERN VALUE rb_eInterrupt;
RUBY_EXTERN VALUE rb_eSignal;
RUBY_EXTERN VALUE rb_eFatal;
RUBY_EXTERN VALUE rb_eArgError;
RUBY_EXTERN VALUE rb_eEOFError;
RUBY_EXTERN VALUE rb_eIndexError;
RUBY_EXTERN VALUE rb_eStopIteration;
RUBY_EXTERN VALUE rb_eKeyError;
RUBY_EXTERN VALUE rb_eRangeError;
RUBY_EXTERN VALUE rb_eIOError;
RUBY_EXTERN VALUE rb_eRuntimeError;
RUBY_EXTERN VALUE rb_eFrozenError;
RUBY_EXTERN VALUE rb_eSecurityError;
RUBY_EXTERN VALUE rb_eSystemCallError;
RUBY_EXTERN VALUE rb_eThreadError;
RUBY_EXTERN VALUE rb_eTypeError;
RUBY_EXTERN VALUE rb_eZeroDivError;
RUBY_EXTERN VALUE rb_eNotImpError;
RUBY_EXTERN VALUE rb_eNoMemError;
RUBY_EXTERN VALUE rb_eNoMethodError;
RUBY_EXTERN VALUE rb_eFloatDomainError;
RUBY_EXTERN VALUE rb_eLocalJumpError;
RUBY_EXTERN VALUE rb_eSysStackError;
RUBY_EXTERN VALUE rb_eRegexpError;
RUBY_EXTERN VALUE rb_eEncodingError;
RUBY_EXTERN VALUE rb_eEncCompatError;
RUBY_EXTERN VALUE rb_eNoMatchingPatternError;

RUBY_EXTERN VALUE rb_eScriptError;
RUBY_EXTERN VALUE rb_eNameError;
RUBY_EXTERN VALUE rb_eSyntaxError;
RUBY_EXTERN VALUE rb_eLoadError;

RUBY_EXTERN VALUE rb_eMathDomainError;

RUBY_EXTERN VALUE rb_stdin, rb_stdout, rb_stderr;

RBIMPL_ATTR_PURE()
static inline VALUE
rb_class_of(VALUE obj)
{
    if (! RB_SPECIAL_CONST_P(obj)) {
        return RBASIC_CLASS(obj);
    }
    else if (obj == RUBY_Qfalse) {
        return rb_cFalseClass;
    }
    else if (obj == RUBY_Qnil) {
        return rb_cNilClass;
    }
    else if (obj == RUBY_Qtrue) {
        return rb_cTrueClass;
    }
    else if (RB_FIXNUM_P(obj)) {
        return rb_cInteger;
    }
    else if (RB_STATIC_SYM_P(obj)) {
        return rb_cSymbol;
    }
    else if (RB_FLONUM_P(obj)) {
        return rb_cFloat;
    }

#if !RUBY_DEBUG
    RBIMPL_UNREACHABLE_RETURN(Qfalse);
#else
    RUBY_ASSERT_FAIL("unexpected type");
#endif
}

#define CLASS_OF rb_class_of

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_GLOBALS_H */
