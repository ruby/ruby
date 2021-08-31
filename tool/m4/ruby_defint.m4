dnl -*- Autoconf -*-
dnl RUBY_DEFINT TYPENAME, SIZE, [UNSIGNED], [INCLUDES = DEFAULT-INCLUDES]
AC_DEFUN([RUBY_DEFINT], [dnl
AS_VAR_PUSHDEF([cond], [rb_defint_cond])dnl
AS_VAR_PUSHDEF([type], [rb_defint_type])dnl
AC_CACHE_CHECK([for $1], [rb_cv_type_$1],
[AC_COMPILE_IFELSE([AC_LANG_PROGRAM([AC_INCLUDES_DEFAULT([$4])
typedef $1 t; int s = sizeof(t) == 42;])],
   [rb_cv_type_$1=yes],
   [AS_CASE([m4_bmatch([$2], [^[1-9][0-9]*$], $2, [$ac_cv_sizeof_]AS_TR_SH($2))],
    ["1"], [ rb_cv_type_$1="m4_if([$3], [], [signed ], [$3 ])char"],
    ["$ac_cv_sizeof_short"], [ rb_cv_type_$1="m4_if([$3], [], [], [$3 ])short"],
    ["$ac_cv_sizeof_int"], [ rb_cv_type_$1="m4_if([$3], [], [], [$3 ])int"],
    ["$ac_cv_sizeof_long"], [ rb_cv_type_$1="m4_if([$3], [], [], [$3 ])long"],
    ["$ac_cv_sizeof_long_long"], [ rb_cv_type_$1="m4_if([$3], [], [], [$3 ])long long"],
    ["${ac_cv_sizeof___int64@%:@*:}"], [ rb_cv_type_$1="m4_if([$3], [], [], [$3 ])__int64"],
    ["${ac_cv_sizeof___int128@%:@*:}"], [ rb_cv_type_$1="m4_if([$3], [], [], [$3 ])__int128"],
    [ rb_cv_type_$1=no])])])
AS_IF([test "${rb_cv_type_$1}" != no], [
    type="${rb_cv_type_$1@%:@@%:@unsigned }"
    AS_IF([test "$type" != yes && eval 'test -n "${ac_cv_sizeof_'$type'+set}"'], [
	eval cond='"${ac_cv_sizeof_'$type'}"'
	AS_CASE([$cond], [*:*], [
	    cond=AS_TR_CPP($type)
	    echo "@%:@if defined SIZEOF_"$cond" && SIZEOF_"$cond" > 0" >> confdefs.h
	], [cond=])
    ], [cond=])
    AC_DEFINE([HAVE_]AS_TR_CPP($1), 1)
    AS_IF([test "${rb_cv_type_$1}" = yes], [
	m4_bmatch([$2], [^[1-9][0-9]*$], [AC_CHECK_SIZEOF([$1], 0, [AC_INCLUDES_DEFAULT([$4])])],
			[RUBY_CHECK_SIZEOF([$1], [$2], [], [AC_INCLUDES_DEFAULT([$4])])])
    ], [
	AC_DEFINE_UNQUOTED($1, [$rb_cv_type_$1])
	AC_DEFINE_UNQUOTED([SIZEOF_]AS_TR_CPP($1), [SIZEOF_]AS_TR_CPP([$type]))
    ])
    test -n "$cond" && echo "@%:@endif /* $cond */" >> confdefs.h
])
AS_VAR_POPDEF([cond])dnl
AS_VAR_POPDEF([type])dnl
])dnl
