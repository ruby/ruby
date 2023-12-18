dnl -*- Autoconf -*-
AC_DEFUN([RUBY_DEFAULT_ARCH], [
# Set ARCH_FLAG for different width but family CPU
AC_MSG_CHECKING([arch option])
AS_CASE([$1:"$host_cpu"],
    [arm64:arm*],        [ARCH_FLAG=-m64],
    [arm*:arm*],         [ARCH_FLAG=-m32],
    [x86_64:[i[3-6]86]], [ARCH_FLAG=-m64],
    [x64:x86_64],        [],
    [[i[3-6]86]:x86_64], [ARCH_FLAG=-m32],
    [ppc64:ppc*],        [ARCH_FLAG=-m64],
    [ppc*:ppc64],        [ARCH_FLAG=-m32],
    AS_CASE([$build_os],
        [darwin*], [ARCH_FLAG="-arch "$1],
        [ARCH_FLAG=-march=$1]
    )
)
AC_MSG_RESULT([$ARCH_FLAG])
])dnl
