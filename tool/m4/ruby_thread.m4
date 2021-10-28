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
])dnl
