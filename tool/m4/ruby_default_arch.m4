dnl -*- Autoconf -*-
AC_DEFUN([RUBY_DEFAULT_ARCH], [
AC_MSG_CHECKING([arch option])
AS_CASE([$1],
	[arm64],      [],
	[*64],        [ARCH_FLAG=-m64],
	[[i[3-6]86]], [ARCH_FLAG=-m32],
	[AC_MSG_ERROR(unknown target architecture: $target_archs)]
	)
AC_MSG_RESULT([$ARCH_FLAG])
])dnl
