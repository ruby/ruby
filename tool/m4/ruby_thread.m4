dnl -*- Autoconf -*-
AC_DEFUN([RUBY_THREAD], [
AC_ARG_WITH(thread,
    AS_HELP_STRING([--with-thread=IMPLEMENTATION], [specify the thread implementation to use]),
    [THREAD_MODEL=$withval], [
    THREAD_MODEL=
    AS_CASE(["$target_os"],
        [freebsd*], [
            AC_CACHE_CHECK([whether pthread should be enabled by default],
                rb_cv_enable_pthread_default,
                [AC_PREPROC_IFELSE([AC_LANG_SOURCE([[
@%:@include <osreldate.h>
@%:@if __FreeBSD_version < 502102
@%:@error pthread should be disabled on this platform
@%:@endif
                    ]])],
                    rb_cv_enable_pthread_default=yes,
                    rb_cv_enable_pthread_default=no)])
            AS_IF([test $rb_cv_enable_pthread_default = yes],
                [THREAD_MODEL=pthread],
                [THREAD_MODEL=none])
        ],
        [mingw*], [
            THREAD_MODEL=win32
        ],
        [wasi*], [
            THREAD_MODEL=none
        ],
        [
            THREAD_MODEL=pthread
        ]
    )
])

AS_IF([test x"$THREAD_MODEL" = xpthread], [
    AC_CHECK_HEADERS(pthread.h)
    AS_IF([test x"$ac_cv_header_pthread_h" = xyes], [], [
	AC_MSG_WARN("Don't know how to find pthread header on your system -- thread support disabled")
        THREAD_MODEL=none
    ])
])
AS_IF([test x"$THREAD_MODEL" = xpthread], [
    THREAD_MODEL=none
    for pthread_lib in thr pthread pthreads c c_r root; do
	AC_CHECK_LIB($pthread_lib, pthread_create,
		     [THREAD_MODEL=pthread; break])
    done
    AS_IF([test x"$THREAD_MODEL" = xpthread], [
	AC_DEFINE(_REENTRANT)
	AC_DEFINE(_THREAD_SAFE)
	AC_DEFINE(HAVE_LIBPTHREAD)
	AC_CHECK_HEADERS(pthread_np.h, [], [], [@%:@include <pthread.h>])
	AS_CASE(["$pthread_lib:$target_os"],
		[c:*], [],
		[root:*], [],
		[c_r:*|*:openbsd*|*:mirbsd*],  [LIBS="-pthread $LIBS"],
		[LIBS="-l$pthread_lib $LIBS"])
    ], [
	AC_MSG_WARN("Don't know how to find pthread library on your system -- thread support disabled")
    ])
])

AS_CASE(["$THREAD_MODEL"],
[pthread], [],
[win32],   [],
[none],    [],
[""],      [AC_MSG_ERROR(thread model is missing)],
           [AC_MSG_ERROR(unknown thread model $THREAD_MODEL)])
AC_MSG_CHECKING(thread model)
AC_MSG_RESULT($THREAD_MODEL)

THREAD_IMPL_H=thread_$THREAD_MODEL.h
AS_IF([test ! -f "$srcdir/$THREAD_IMPL_H"],
      [AC_MSG_ERROR('$srcdir/$THREAD_IMPL_H' must exist)])
THREAD_IMPL_SRC=thread_$THREAD_MODEL.c
AS_IF([test ! -f "$srcdir/$THREAD_IMPL_SRC"],
      [AC_MSG_ERROR('$srcdir/$THREAD_IMPL_SRC' must exist)])
AC_DEFINE_UNQUOTED(THREAD_IMPL_H, ["$THREAD_IMPL_H"])
AC_DEFINE_UNQUOTED(THREAD_IMPL_SRC, ["$THREAD_IMPL_SRC"])
])dnl
