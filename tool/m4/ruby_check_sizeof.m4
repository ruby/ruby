dnl -*- Autoconf -*-
dnl RUBY_CHECK_SIZEOF [typename], [maybe same size types], [macros], [include]
AC_DEFUN([RUBY_CHECK_SIZEOF],
[dnl
AS_VAR_PUSHDEF([rbcv_var], [rbcv_sizeof_var])dnl
AS_VAR_PUSHDEF([cond], [rbcv_sizeof_cond])dnl
AS_VAR_PUSHDEF([t], [rbcv_sizeof_type])dnl
AS_VAR_PUSHDEF([s], [rbcv_sizeof_size])dnl
]
[m4_bmatch([$1], [\.], [], [if test "$universal_binary" = yes; then])
AC_CACHE_CHECK([size of $1], [AS_TR_SH([ac_cv_sizeof_$1])], [
    unset AS_TR_SH(ac_cv_sizeof_$1)
    rbcv_var="
typedef m4_bpatsubst([$1], [\..*]) ac__type_sizeof_;
static ac__type_sizeof_ *rbcv_ptr;
@%:@define AS_TR_CPP(SIZEOF_$1) sizeof((*rbcv_ptr)[]m4_bmatch([$1], [\.], .m4_bpatsubst([$1], [^[^.]*\.])))
"
    m4_ifval([$2], [test -z "${AS_TR_SH(ac_cv_sizeof_$1)+set}" && {
    for t in $2; do
	AC_COMPILE_IFELSE(
	    [AC_LANG_BOOL_COMPILE_TRY(AC_INCLUDES_DEFAULT([$4]
		[$rbcv_var]),
		[AS_TR_CPP(SIZEOF_$1) == sizeof($t)])], [
		AS_TR_SH(ac_cv_sizeof_$1)=AS_TR_CPP([SIZEOF_]$t)
		break])
    done
    }], [
	AC_COMPUTE_INT([AS_TR_SH(ac_cv_sizeof_$1)], [AS_TR_CPP(SIZEOF_$1)],
	    [AC_INCLUDES_DEFAULT([$4])
$rbcv_var],
	    [AS_TR_SH(ac_cv_sizeof_$1)=])
    ])
    unset cond
    m4_ifval([$3], [test -z "${AS_TR_SH(ac_cv_sizeof_$1)+set}" && {
    for s in 32 64 128; do
	for t in $3; do
	    cond="${cond}
@%:@${cond+el}if defined(__${t}${s}__) || defined(__${t}${s}) || defined(_${t}${s}) || defined(${t}${s})"
	    hdr="AC_INCLUDES_DEFAULT([$4
@%:@if defined(__${t}${s}__) || defined(__${t}${s}) || defined(_${t}${s}) || defined(${t}${s})
@%:@ define AS_TR_CPP(HAVE_$1) 1
@%:@else
@%:@ define AS_TR_CPP(HAVE_$1) 0
@%:@endif])"
	    AC_COMPILE_IFELSE([AC_LANG_BOOL_COMPILE_TRY([$hdr], [!AS_TR_CPP(HAVE_$1)])], [continue])
	    AC_COMPILE_IFELSE([AC_LANG_BOOL_COMPILE_TRY([$hdr]
				[$rbcv_var],
				[AS_TR_CPP(HAVE_$1) == (AS_TR_CPP(SIZEOF_$1) == ($s / $rb_cv_char_bit))])],
		[AS_TR_SH(ac_cv_sizeof_$1)="${AS_TR_SH(ac_cv_sizeof_$1)+${AS_TR_SH(ac_cv_sizeof_$1)-} }${t}${s}"; continue])
	    AC_COMPILE_IFELSE([AC_LANG_BOOL_COMPILE_TRY([$hdr]
[
@%:@if AS_TR_CPP(HAVE_$1)
$rbcv_var
@%:@else
@%:@define AS_TR_CPP(SIZEOF_$1) 0
@%:@endif
],
		    [AS_TR_CPP(HAVE_$1) == (AS_TR_CPP(SIZEOF_$1) == (m4_bmatch([$2], [^[0-9][0-9]*$], [$2], [($s / $rb_cv_char_bit)])))])],
		[AS_TR_SH(ac_cv_sizeof_$1)="${AS_TR_SH(ac_cv_sizeof_$1)+${AS_TR_SH(ac_cv_sizeof_$1)-} }${t}${s}m4_bmatch([$2], [^[0-9][0-9]*$], [:$2])"])
	done
    done
    }])
    test "${AS_TR_SH(ac_cv_sizeof_$1)@%:@@<:@1-9@:>@}" = "${AS_TR_SH(ac_cv_sizeof_$1)}" &&
    m4_ifval([$2][$3],
	[test "${AS_TR_SH(ac_cv_sizeof_$1)@%:@SIZEOF_}" = "${AS_TR_SH(ac_cv_sizeof_$1)}" && ]){
    test "$universal_binary" = yes && cross_compiling=yes
    AC_COMPUTE_INT([t], AS_TR_CPP(SIZEOF_$1), [AC_INCLUDES_DEFAULT([$4])]
[${cond+$cond
@%:@else}
$rbcv_var
${cond+@%:@endif}
@%:@ifndef AS_TR_CPP(SIZEOF_$1)
@%:@define AS_TR_CPP(SIZEOF_$1) 0
@%:@endif], [t=0])
    test "$universal_binary" = yes && cross_compiling=$real_cross_compiling
    AS_IF([test ${t-0} != 0], [
	AS_TR_SH(ac_cv_sizeof_$1)="${AS_TR_SH(ac_cv_sizeof_$1)+${AS_TR_SH(ac_cv_sizeof_$1)-} }${t}"
    ])
    }
    : ${AS_TR_SH(ac_cv_sizeof_$1)=0}
])
{
    unset cond
    for t in ${AS_TR_SH(ac_cv_sizeof_$1)-}; do
	AS_CASE(["$t"],
	[[[0-9]*|SIZEOF_*]], [
	    ${cond+echo "@%:@else"}
	    echo "[@%:@define ]AS_TR_CPP(SIZEOF_$1) $t"
	    break
	    ],
	[
	    s=`expr $t : ['.*[^0-9]\([0-9][0-9]*\)$']`
	    AS_CASE([$t], [*:*], [t="${t%:*}"], [s=`expr $s / $rb_cv_char_bit`])
	    echo "@%:@${cond+el}if defined(__${t}__) || defined(__${t}) || defined(_${t}) || defined($t)"
	    echo "@%:@define AS_TR_CPP(SIZEOF_$1) $s"
	    cond=1
	    ])
    done
    ${cond+echo "@%:@endif"}
} >> confdefs.h
m4_bmatch([$1], [\.], [], [else
AC_CHECK_SIZEOF([$1], 0, [$4])
fi])
AS_VAR_POPDEF([rbcv_var])dnl
AS_VAR_POPDEF([cond])dnl
AS_VAR_POPDEF([t])dnl
AS_VAR_POPDEF([s])dnl
])dnl
