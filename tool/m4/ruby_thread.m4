dnl -*- Autoconf -*-
AC_DEFUN([RUBY_THREAD], [
AS_CASE(["$target_os"],
    [mingw*], [
        THREAD_MODEL=win32
    ],
    [
        AS_IF([test "$rb_with_pthread" = "yes"], [
            THREAD_MODEL=pthread
        ])
    ]
)

AS_CASE(["$THREAD_MODEL"],
[pthread], [AC_CHECK_HEADERS(pthread.h)],
[win32],   [],
[""],      [AC_MSG_ERROR(thread model is missing)],
           [AC_MSG_ERROR(unknown thread model $THREAD_MODEL)])

THREAD_IMPL_H=thread_$THREAD_MODEL.h
AS_IF([test ! -f "$srcdir/$THREAD_IMPL_H"],
      [AC_MSG_ERROR('$srcdir/$THREAD_IMPL_H' must exist)])
THREAD_IMPL_SRC=thread_$THREAD_MODEL.c
AS_IF([test ! -f "$srcdir/$THREAD_IMPL_SRC"],
      [AC_MSG_ERROR('$srcdir/$THREAD_IMPL_SRC' must exist)])
AC_DEFINE_UNQUOTED(THREAD_IMPL_H, ["$THREAD_IMPL_H"])
AC_DEFINE_UNQUOTED(THREAD_IMPL_SRC, ["$THREAD_IMPL_SRC"])
])dnl
