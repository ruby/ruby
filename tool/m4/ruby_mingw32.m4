# -*- Autoconf -*-
AC_DEFUN([RUBY_MINGW32],
[AS_CASE(["$host_os"],
[cygwin*], [
AC_CACHE_CHECK(for mingw32 environment, rb_cv_mingw32,
[AC_TRY_CPP([
#ifndef __MINGW32__
# error
#endif
], rb_cv_mingw32=yes,rb_cv_mingw32=no)
rm -f conftest*])
AS_IF([test "$rb_cv_mingw32" = yes], [
    target_os="mingw32"
    : ${ac_tool_prefix:="`expr "$CC" : ['\(.*-\)g\?cc[^/]*$']`"}
])
])
AS_CASE(["$target_os"], [mingw*msvc], [
target_os="`echo ${target_os} | sed 's/msvc$//'`"
])
AS_CASE(["$target_cpu-$target_os"], [x86_64-mingw*], [
target_cpu=x64
])
])dnl
