#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

#define defconstfunc(name) \
static VALUE constants_spec_##name(VALUE self) { return name; }

defconstfunc(rb_cArray)
defconstfunc(rb_cBasicObject)
defconstfunc(rb_cBinding)
defconstfunc(rb_cClass)
defconstfunc(rb_cComplex)
defconstfunc(rb_mComparable)
defconstfunc(rb_cDir)
defconstfunc(rb_cEncoding)
defconstfunc(rb_mEnumerable)
defconstfunc(rb_cEnumerator)
defconstfunc(rb_cFalseClass)
defconstfunc(rb_cFile)
defconstfunc(rb_mFileTest)
defconstfunc(rb_cFloat)
defconstfunc(rb_mGC)
defconstfunc(rb_cHash)
defconstfunc(rb_cInteger)
defconstfunc(rb_cIO)
defconstfunc(rb_mKernel)
defconstfunc(rb_mMath)
defconstfunc(rb_cMatch)
defconstfunc(rb_cMethod)
defconstfunc(rb_cModule)
defconstfunc(rb_cNilClass)
defconstfunc(rb_cNumeric)
defconstfunc(rb_cObject)
defconstfunc(rb_cProc)
defconstfunc(rb_mProcess)
defconstfunc(rb_cRandom)
defconstfunc(rb_cRange)
defconstfunc(rb_cRational)
defconstfunc(rb_cRegexp)
defconstfunc(rb_cStat)
defconstfunc(rb_cString)
defconstfunc(rb_cStruct)
defconstfunc(rb_cSymbol)
defconstfunc(rb_cTime)
defconstfunc(rb_cThread)
defconstfunc(rb_cTrueClass)
defconstfunc(rb_cUnboundMethod)
defconstfunc(rb_eArgError)
defconstfunc(rb_eEncodingError)
defconstfunc(rb_eEncCompatError)
defconstfunc(rb_eEOFError)
defconstfunc(rb_mErrno)
defconstfunc(rb_eException)
defconstfunc(rb_eFatal)
defconstfunc(rb_eFloatDomainError)
defconstfunc(rb_eFrozenError)
defconstfunc(rb_eIndexError)
defconstfunc(rb_eInterrupt)
defconstfunc(rb_eIOError)
defconstfunc(rb_eKeyError)
defconstfunc(rb_eLoadError)
defconstfunc(rb_eLocalJumpError)
defconstfunc(rb_eMathDomainError)
defconstfunc(rb_eNameError)
defconstfunc(rb_eNoMemError)
defconstfunc(rb_eNoMethodError)
defconstfunc(rb_eNotImpError)
defconstfunc(rb_eRangeError)
defconstfunc(rb_eRegexpError)
defconstfunc(rb_eRuntimeError)
defconstfunc(rb_eScriptError)
defconstfunc(rb_eSecurityError)
defconstfunc(rb_eSignal)
defconstfunc(rb_eStandardError)
defconstfunc(rb_eStopIteration)
defconstfunc(rb_eSyntaxError)
defconstfunc(rb_eSystemCallError)
defconstfunc(rb_eSystemExit)
defconstfunc(rb_eSysStackError)
defconstfunc(rb_eTypeError)
defconstfunc(rb_eThreadError)
defconstfunc(rb_mWaitReadable)
defconstfunc(rb_mWaitWritable)
defconstfunc(rb_eZeroDivError)

void Init_constants_spec(void) {
  VALUE cls = rb_define_class("CApiConstantsSpecs", rb_cObject);
  rb_define_method(cls, "rb_cArray", constants_spec_rb_cArray, 0);
  rb_define_method(cls, "rb_cBasicObject", constants_spec_rb_cBasicObject, 0);
  rb_define_method(cls, "rb_cBinding", constants_spec_rb_cBinding, 0);
  rb_define_method(cls, "rb_cClass", constants_spec_rb_cClass, 0);
  rb_define_method(cls, "rb_cComplex", constants_spec_rb_cComplex, 0);
  rb_define_method(cls, "rb_mComparable", constants_spec_rb_mComparable, 0);
  rb_define_method(cls, "rb_cDir", constants_spec_rb_cDir, 0);
  rb_define_method(cls, "rb_cEncoding", constants_spec_rb_cEncoding, 0);
  rb_define_method(cls, "rb_mEnumerable", constants_spec_rb_mEnumerable, 0);
  rb_define_method(cls, "rb_cEnumerator", constants_spec_rb_cEnumerator, 0);
  rb_define_method(cls, "rb_cFalseClass", constants_spec_rb_cFalseClass, 0);
  rb_define_method(cls, "rb_cFile", constants_spec_rb_cFile, 0);
  rb_define_method(cls, "rb_mFileTest", constants_spec_rb_mFileTest, 0);
  rb_define_method(cls, "rb_cFloat", constants_spec_rb_cFloat, 0);
  rb_define_method(cls, "rb_mGC", constants_spec_rb_mGC, 0);
  rb_define_method(cls, "rb_cHash", constants_spec_rb_cHash, 0);
  rb_define_method(cls, "rb_cInteger", constants_spec_rb_cInteger, 0);
  rb_define_method(cls, "rb_cIO", constants_spec_rb_cIO, 0);
  rb_define_method(cls, "rb_mKernel", constants_spec_rb_mKernel, 0);
  rb_define_method(cls, "rb_mMath", constants_spec_rb_mMath, 0);
  rb_define_method(cls, "rb_cMatch", constants_spec_rb_cMatch, 0);
  rb_define_method(cls, "rb_cMethod", constants_spec_rb_cMethod, 0);
  rb_define_method(cls, "rb_cModule", constants_spec_rb_cModule, 0);
  rb_define_method(cls, "rb_cNilClass", constants_spec_rb_cNilClass, 0);
  rb_define_method(cls, "rb_cNumeric", constants_spec_rb_cNumeric, 0);
  rb_define_method(cls, "rb_cObject", constants_spec_rb_cObject, 0);
  rb_define_method(cls, "rb_cProc", constants_spec_rb_cProc, 0);
  rb_define_method(cls, "rb_mProcess", constants_spec_rb_mProcess, 0);
  rb_define_method(cls, "rb_cRandom", constants_spec_rb_cRandom, 0);
  rb_define_method(cls, "rb_cRange", constants_spec_rb_cRange, 0);
  rb_define_method(cls, "rb_cRational", constants_spec_rb_cRational, 0);
  rb_define_method(cls, "rb_cRegexp", constants_spec_rb_cRegexp, 0);
  rb_define_method(cls, "rb_cStat", constants_spec_rb_cStat, 0);
  rb_define_method(cls, "rb_cString", constants_spec_rb_cString, 0);
  rb_define_method(cls, "rb_cStruct", constants_spec_rb_cStruct, 0);
  rb_define_method(cls, "rb_cSymbol", constants_spec_rb_cSymbol, 0);
  rb_define_method(cls, "rb_cTime", constants_spec_rb_cTime, 0);
  rb_define_method(cls, "rb_cThread", constants_spec_rb_cThread, 0);
  rb_define_method(cls, "rb_cTrueClass", constants_spec_rb_cTrueClass, 0);
  rb_define_method(cls, "rb_cUnboundMethod", constants_spec_rb_cUnboundMethod, 0);
  rb_define_method(cls, "rb_eArgError", constants_spec_rb_eArgError, 0);
  rb_define_method(cls, "rb_eEncodingError", constants_spec_rb_eEncodingError, 0);
  rb_define_method(cls, "rb_eEncCompatError", constants_spec_rb_eEncCompatError, 0);
  rb_define_method(cls, "rb_eEOFError", constants_spec_rb_eEOFError, 0);
  rb_define_method(cls, "rb_mErrno", constants_spec_rb_mErrno, 0);
  rb_define_method(cls, "rb_eException", constants_spec_rb_eException, 0);
  rb_define_method(cls, "rb_eFatal", constants_spec_rb_eFatal, 0);
  rb_define_method(cls, "rb_eFloatDomainError", constants_spec_rb_eFloatDomainError, 0);
  rb_define_method(cls, "rb_eFrozenError", constants_spec_rb_eFrozenError, 0);
  rb_define_method(cls, "rb_eIndexError", constants_spec_rb_eIndexError, 0);
  rb_define_method(cls, "rb_eInterrupt", constants_spec_rb_eInterrupt, 0);
  rb_define_method(cls, "rb_eIOError", constants_spec_rb_eIOError, 0);
  rb_define_method(cls, "rb_eKeyError", constants_spec_rb_eKeyError, 0);
  rb_define_method(cls, "rb_eLoadError", constants_spec_rb_eLoadError, 0);
  rb_define_method(cls, "rb_eLocalJumpError", constants_spec_rb_eLocalJumpError, 0);
  rb_define_method(cls, "rb_eMathDomainError", constants_spec_rb_eMathDomainError, 0);
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
  rb_define_method(cls, "rb_eStopIteration", constants_spec_rb_eStopIteration, 0);
  rb_define_method(cls, "rb_eSyntaxError", constants_spec_rb_eSyntaxError, 0);
  rb_define_method(cls, "rb_eSystemCallError", constants_spec_rb_eSystemCallError, 0);
  rb_define_method(cls, "rb_eSystemExit", constants_spec_rb_eSystemExit, 0);
  rb_define_method(cls, "rb_eSysStackError", constants_spec_rb_eSysStackError, 0);
  rb_define_method(cls, "rb_eTypeError", constants_spec_rb_eTypeError, 0);
  rb_define_method(cls, "rb_eThreadError", constants_spec_rb_eThreadError, 0);
  rb_define_method(cls, "rb_mWaitReadable", constants_spec_rb_mWaitReadable, 0);
  rb_define_method(cls, "rb_mWaitWritable", constants_spec_rb_mWaitWritable, 0);
  rb_define_method(cls, "rb_eZeroDivError", constants_spec_rb_eZeroDivError, 0);
}

#ifdef __cplusplus
}
#endif
