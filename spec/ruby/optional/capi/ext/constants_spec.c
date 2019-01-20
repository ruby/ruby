#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE constants_spec_rb_cArray(VALUE self) {
  return rb_cArray;
}

#ifndef RUBY_INTEGER_UNIFICATION
static VALUE constants_spec_rb_cBignum(VALUE self) {
  return rb_cBignum;
}
#endif

static VALUE constants_spec_rb_cClass(VALUE self) {
  return rb_cClass;
}

static VALUE constants_spec_rb_cData(VALUE self) {
  return rb_cData;
}

static VALUE constants_spec_rb_cFalseClass(VALUE self) {
  return rb_cFalseClass;
}

static VALUE constants_spec_rb_cFile(VALUE self) {
  return rb_cFile;
}

#ifndef RUBY_INTEGER_UNIFICATION
static VALUE constants_spec_rb_cFixnum(VALUE self) {
  return rb_cFixnum;
}
#endif

static VALUE constants_spec_rb_cFloat(VALUE self) {
  return rb_cFloat;
}

static VALUE constants_spec_rb_cHash(VALUE self) {
  return rb_cHash;
}

static VALUE constants_spec_rb_cInteger(VALUE self) {
  return rb_cInteger;
}

static VALUE constants_spec_rb_cIO(VALUE self) {
  return rb_cIO;
}

static VALUE constants_spec_rb_cModule(VALUE self) {
  return rb_cModule;
}

static VALUE constants_spec_rb_cMatch(VALUE self) {
  return rb_cMatch;
}

static VALUE constants_spec_rb_cNilClass(VALUE self) {
  return rb_cNilClass;
}

static VALUE constants_spec_rb_cNumeric(VALUE self) {
  return rb_cNumeric;
}

static VALUE constants_spec_rb_cObject(VALUE self) {
  return rb_cObject;
}

static VALUE constants_spec_rb_cRange(VALUE self) {
  return rb_cRange;
}

static VALUE constants_spec_rb_cRegexp(VALUE self) {
  return rb_cRegexp;
}

static VALUE constants_spec_rb_cString(VALUE self) {
  return rb_cString;
}

static VALUE constants_spec_rb_cStruct(VALUE self) {
  return rb_cStruct;
}

static VALUE constants_spec_rb_cSymbol(VALUE self) {
  return rb_cSymbol;
}

static VALUE constants_spec_rb_cTime(VALUE self) {
  return rb_cTime;
}

static VALUE constants_spec_rb_cThread(VALUE self) {
  return rb_cThread;
}

static VALUE constants_spec_rb_cTrueClass(VALUE self) {
  return rb_cTrueClass;
}

static VALUE constants_spec_rb_cProc(VALUE self) {
  return rb_cProc;
}

static VALUE constants_spec_rb_cMethod(VALUE self) {
  return rb_cMethod;
}

static VALUE constants_spec_rb_cEnumerator(VALUE self) {
  return rb_cEnumerator;
}

static VALUE constants_spec_rb_mComparable(VALUE self) {
  return rb_mComparable;
}

static VALUE constants_spec_rb_mEnumerable(VALUE self) {
  return rb_mEnumerable;
}

static VALUE constants_spec_rb_mKernel(VALUE self) {
  return rb_mKernel;
}

static VALUE constants_spec_rb_eArgError(VALUE self) {
  return rb_eArgError;
}

static VALUE constants_spec_rb_eEOFError(VALUE self) {
  return rb_eEOFError;
}

static VALUE constants_spec_rb_mErrno(VALUE self) {
  return rb_mErrno;
}

static VALUE constants_spec_rb_eException(VALUE self) {
  return rb_eException;
}

static VALUE constants_spec_rb_eFloatDomainError(VALUE self) {
  return rb_eFloatDomainError;
}

static VALUE constants_spec_rb_eIndexError(VALUE self) {
  return rb_eIndexError;
}

static VALUE constants_spec_rb_eInterrupt(VALUE self) {
  return rb_eInterrupt;
}

static VALUE constants_spec_rb_eIOError(VALUE self) {
  return rb_eIOError;
}

static VALUE constants_spec_rb_eLoadError(VALUE self) {
  return rb_eLoadError;
}

static VALUE constants_spec_rb_eLocalJumpError(VALUE self) {
  return rb_eLocalJumpError;
}

static VALUE constants_spec_rb_eNameError(VALUE self) {
  return rb_eNameError;
}

static VALUE constants_spec_rb_eNoMemError(VALUE self) {
  return rb_eNoMemError;
}

static VALUE constants_spec_rb_eNoMethodError(VALUE self) {
  return rb_eNoMethodError;
}

static VALUE constants_spec_rb_eNotImpError(VALUE self) {
  return rb_eNotImpError;
}

static VALUE constants_spec_rb_eRangeError(VALUE self) {
  return rb_eRangeError;
}

static VALUE constants_spec_rb_eRegexpError(VALUE self) {
  return rb_eRegexpError;
}

static VALUE constants_spec_rb_eRuntimeError(VALUE self) {
  return rb_eRuntimeError;
}

static VALUE constants_spec_rb_eScriptError(VALUE self) {
  return rb_eScriptError;
}

static VALUE constants_spec_rb_eSecurityError(VALUE self) {
  return rb_eSecurityError;
}

static VALUE constants_spec_rb_eSignal(VALUE self) {
  return rb_eSignal;
}

static VALUE constants_spec_rb_eStandardError(VALUE self) {
  return rb_eStandardError;
}

static VALUE constants_spec_rb_eSyntaxError(VALUE self) {
  return rb_eSyntaxError;
}

static VALUE constants_spec_rb_eSystemCallError(VALUE self) {
  return rb_eSystemCallError;
}

static VALUE constants_spec_rb_eSystemExit(VALUE self) {
  return rb_eSystemExit;
}

static VALUE constants_spec_rb_eSysStackError(VALUE self) {
  return rb_eSysStackError;
}

static VALUE constants_spec_rb_eTypeError(VALUE self) {
  return rb_eTypeError;
}

static VALUE constants_spec_rb_eThreadError(VALUE self) {
  return rb_eThreadError;
}

static VALUE constants_spec_rb_eZeroDivError(VALUE self) {
  return rb_eZeroDivError;
}

static VALUE constants_spec_rb_eMathDomainError(VALUE self) {
  return rb_eMathDomainError;
}

static VALUE constants_spec_rb_eEncCompatError(VALUE self) {
  return rb_eEncCompatError;
}

static VALUE constants_spec_rb_mWaitReadable(VALUE self) {
  return rb_mWaitReadable;
}

static VALUE constants_spec_rb_mWaitWritable(VALUE self) {
  return rb_mWaitWritable;
}

static VALUE constants_spec_rb_cDir(VALUE self) {
  return rb_cDir;
}

void Init_constants_spec(void) {
  VALUE cls = rb_define_class("CApiConstantsSpecs", rb_cObject);
  rb_define_method(cls, "rb_cArray", constants_spec_rb_cArray, 0);
#ifndef RUBY_INTEGER_UNIFICATION
  rb_define_method(cls, "rb_cBignum", constants_spec_rb_cBignum, 0);
#endif

  rb_define_method(cls, "rb_cClass", constants_spec_rb_cClass, 0);
  rb_define_method(cls, "rb_cData", constants_spec_rb_cData, 0);
  rb_define_method(cls, "rb_cFalseClass", constants_spec_rb_cFalseClass, 0);
  rb_define_method(cls, "rb_cFile", constants_spec_rb_cFile, 0);
#ifndef RUBY_INTEGER_UNIFICATION
  rb_define_method(cls, "rb_cFixnum", constants_spec_rb_cFixnum, 0);
#endif

  rb_define_method(cls, "rb_cFloat", constants_spec_rb_cFloat, 0);
  rb_define_method(cls, "rb_cHash", constants_spec_rb_cHash, 0);
  rb_define_method(cls, "rb_cInteger", constants_spec_rb_cInteger, 0);
  rb_define_method(cls, "rb_cIO", constants_spec_rb_cIO, 0);
  rb_define_method(cls, "rb_cMatch", constants_spec_rb_cMatch, 0);
  rb_define_method(cls, "rb_cModule", constants_spec_rb_cModule, 0);
  rb_define_method(cls, "rb_cNilClass", constants_spec_rb_cNilClass, 0);
  rb_define_method(cls, "rb_cNumeric", constants_spec_rb_cNumeric, 0);
  rb_define_method(cls, "rb_cObject", constants_spec_rb_cObject, 0);
  rb_define_method(cls, "rb_cRange", constants_spec_rb_cRange, 0);
  rb_define_method(cls, "rb_cRegexp", constants_spec_rb_cRegexp, 0);
  rb_define_method(cls, "rb_cString", constants_spec_rb_cString, 0);
  rb_define_method(cls, "rb_cStruct", constants_spec_rb_cStruct, 0);
  rb_define_method(cls, "rb_cSymbol", constants_spec_rb_cSymbol, 0);
  rb_define_method(cls, "rb_cTime", constants_spec_rb_cTime, 0);
  rb_define_method(cls, "rb_cThread", constants_spec_rb_cThread, 0);
  rb_define_method(cls, "rb_cTrueClass", constants_spec_rb_cTrueClass, 0);
  rb_define_method(cls, "rb_cProc", constants_spec_rb_cProc, 0);
  rb_define_method(cls, "rb_cMethod", constants_spec_rb_cMethod, 0);
  rb_define_method(cls, "rb_cEnumerator", constants_spec_rb_cEnumerator, 0);
  rb_define_method(cls, "rb_mComparable", constants_spec_rb_mComparable, 0);
  rb_define_method(cls, "rb_mEnumerable", constants_spec_rb_mEnumerable, 0);
  rb_define_method(cls, "rb_mKernel", constants_spec_rb_mKernel, 0);
  rb_define_method(cls, "rb_eArgError", constants_spec_rb_eArgError, 0);
  rb_define_method(cls, "rb_eEOFError", constants_spec_rb_eEOFError, 0);
  rb_define_method(cls, "rb_mErrno", constants_spec_rb_mErrno, 0);
  rb_define_method(cls, "rb_eException", constants_spec_rb_eException, 0);
  rb_define_method(cls, "rb_eFloatDomainError", constants_spec_rb_eFloatDomainError, 0);
  rb_define_method(cls, "rb_eIndexError", constants_spec_rb_eIndexError, 0);
  rb_define_method(cls, "rb_eInterrupt", constants_spec_rb_eInterrupt, 0);
  rb_define_method(cls, "rb_eIOError", constants_spec_rb_eIOError, 0);
  rb_define_method(cls, "rb_eLoadError", constants_spec_rb_eLoadError, 0);
  rb_define_method(cls, "rb_eLocalJumpError", constants_spec_rb_eLocalJumpError, 0);
  rb_define_method(cls, "rb_eNameError", constants_spec_rb_eNameError, 0);
  rb_define_method(cls, "rb_eNoMemError", constants_spec_rb_eNoMemError, 0);
  rb_define_method(cls, "rb_eNoMethodError", constants_spec_rb_eNoMethodError, 0);
  rb_define_method(cls, "rb_eNotImpError", constants_spec_rb_eNotImpError, 0);
  rb_define_method(cls, "rb_eRangeError", constants_spec_rb_eRangeError, 0);
  rb_define_method(cls, "rb_eRegexpError", constants_spec_rb_eRegexpError, 0);
  rb_define_method(cls, "rb_eRuntimeError", constants_spec_rb_eRuntimeError, 0);
  rb_define_method(cls, "rb_eScriptError", constants_spec_rb_eScriptError, 0);
  rb_define_method(cls, "rb_eSecurityError", constants_spec_rb_eSecurityError, 0);
  rb_define_method(cls, "rb_eSignal", constants_spec_rb_eSignal, 0);
  rb_define_method(cls, "rb_eStandardError", constants_spec_rb_eStandardError, 0);
  rb_define_method(cls, "rb_eSyntaxError", constants_spec_rb_eSyntaxError, 0);
  rb_define_method(cls, "rb_eSystemCallError", constants_spec_rb_eSystemCallError, 0);
  rb_define_method(cls, "rb_eSystemExit", constants_spec_rb_eSystemExit, 0);
  rb_define_method(cls, "rb_eSysStackError", constants_spec_rb_eSysStackError, 0);
  rb_define_method(cls, "rb_eTypeError", constants_spec_rb_eTypeError, 0);
  rb_define_method(cls, "rb_eThreadError", constants_spec_rb_eThreadError, 0);
  rb_define_method(cls, "rb_eZeroDivError", constants_spec_rb_eZeroDivError, 0);
  rb_define_method(cls, "rb_eMathDomainError", constants_spec_rb_eMathDomainError, 0);
  rb_define_method(cls, "rb_eEncCompatError", constants_spec_rb_eEncCompatError, 0);
  rb_define_method(cls, "rb_mWaitReadable", constants_spec_rb_mWaitReadable, 0);
  rb_define_method(cls, "rb_mWaitWritable", constants_spec_rb_mWaitWritable, 0);
  rb_define_method(cls, "rb_cDir", constants_spec_rb_cDir, 0);
}

#ifdef __cplusplus
}
#endif
