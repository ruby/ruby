# -*- Autoconf -*-
AC_DEFUN([RUBY_PROG_TOOLCHAINS],[
AC_PROG_CC_C99
AS_CASE([$CC],
[*ccache*], [
    # Should not modify for instance `ccache gcc ...`
],
[*distcc*], [
    # Ditto for distcc
],
[*clang*], [
    # Recent LLVM has LTO.  It tends to come with its own linker etc.
    path=`echo "${CC}" | sed 's,clang.*$,,'`
    ver=`echo "${CC}" | sed 's,^.*clang\(@<:@^ @:>@*\).*$,\1,'`
    argv=`echo "${CC}" | sed 's,^.*clang@<:@^ @:>@*\(.*\)$,\1,'`
    clang="${path}clang${ver}"
    clangpp="${path}clang++${ver}"
    llvm_ar="${path}llvm-ar${ver}"
    llvm_ranlib="${path}llvm-ranlib${ver}"
    llvm_nm="${path}llvm-nm${ver}"
#   llvm_as="${path}/llvm-as{ver}"
    AC_PROG_CXX(["${clangpp}"])
    AC_CHECK_TOOLS(LD, ["${clang}"], [ld])
    AC_CHECK_TOOLS(AR, ["${llvm_ar}" aal], [ar])
    AC_CHECK_TOOLS(RANLIB, ["${llvm_ranlib}" ranlib], [:])
    AC_CHECK_TOOLS(NM, ["${llvm_nm}"], [nm])
    AC_CHECK_TOOLS(AS, [as])
],
[*gcc*], [
    # Ditto for GNU.
    path=`echo "${CC}" | sed 's,gcc.*$,,'`
    ver=`echo "${CC}" | sed 's,^.*gcc\(@<:@^ @:>@*\).*$,\1,'`
    argv=`echo "${CC}" | sed 's,^.*gcc@<:@^ @:>@*\(.*\)$,\1,'`
    gcc="${path}gcc${ver}"
    gpp="${path}g++${ver}"
    gcc_ar="${path}gcc-ar${ver}"
    gcc_ranlib="${path}gcc-ranlib${ver}"
    gcc_nm="${path}gcc-nm${ver}"
    AC_PROG_CXX(["${gpp}"])
    AC_CHECK_TOOLS(LD, ["${gcc}"], [ld])
    AC_CHECK_TOOLS(AR, ["${gcc_ar}" aal], [ar])
    AC_CHECK_TOOLS(RANLIB, ["${gcc_ranlib}" ranlib], [:])
    AC_CHECK_TOOLS(NM, ["${gcc_nm}"], [nm])
    AC_CHECK_TOOLS(AS, [gas as])
],
[*icc*], [
    path=`echo "${CC}" | sed "s,icc.*$,,"`
    icc="${path}icc"
    icpc="${path}icpc"
#   xiar="${path}xiar"
#   xild="${path}xild"
    AC_PROG_CXX(["${icpc}"])
    AC_CHECK_TOOLS(LD, ["${icc}"],[ld])
    AC_CHECK_TOOLS(AR, [ar])
    AC_CHECK_TOOLS(RANLIB, [ranlib], [:])
    AC_CHECK_TOOLS(NM, [nm])
    AC_CHECK_TOOLS(AS, [as])
])
])dnl