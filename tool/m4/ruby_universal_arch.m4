dnl -*- Autoconf -*-
AC_DEFUN([RUBY_UNIVERSAL_ARCH], [
# RUBY_UNIVERSAL_ARCH begin
ARCH_FLAG=`expr " $CXXFLAGS " : ['.* \(-m[0-9][0-9]*\) ']`
test ${CXXFLAGS+set} && CXXFLAGS=`echo "$CXXFLAGS" | sed [-e 's/ *-arch  *[^ ]*//g' -e 's/ *-m32//g' -e 's/ *-m64//g']`
ARCH_FLAG=`expr " $CFLAGS " : ['.* \(-m[0-9][0-9]*\) ']`
test ${CFLAGS+set} && CFLAGS=`echo "$CFLAGS" | sed [-e 's/ *-arch  *[^ ]*//g' -e 's/ *-m32//g' -e 's/ *-m64//g']`
test ${LDFLAGS+set} && LDFLAGS=`echo "$LDFLAGS" | sed [-e 's/ *-arch  *[^ ]*//g' -e 's/ *-m32//g' -e 's/ *-m64//g']`
unset universal_binary universal_archnames
AS_IF([test ${target_archs+set}], [
    AC_MSG_CHECKING([target architectures])
    target_archs=`echo $target_archs | tr , ' '`
    # /usr/lib/arch_tool -archify_list $TARGET_ARCHS
    for archs in $target_archs
    do
	AS_CASE([",$universal_binary,"],[*",$archs,"*], [],[
	    cpu=$archs
	    cpu=`echo $cpu | sed 's/-.*-.*//'`
	    universal_binary="${universal_binary+$universal_binary,}$cpu"
	    universal_archnames="${universal_archnames} ${archs}=${cpu}"
	    ARCH_FLAG="${ARCH_FLAG+$ARCH_FLAG }-arch $archs"
	    ])
    done
    target_archs="$universal_binary"
    unset universal_binary
    AS_CASE(["$target_archs"],
      [*,*], [universal_binary=yes],
             [unset universal_archnames])
    AC_MSG_RESULT([$target_archs])

    target=`echo $target | sed "s/^$target_cpu-/-/"`
    target_alias=`echo $target_alias | sed "s/^$target_cpu-/-/"`
    AS_IF([test "${universal_binary-no}" = yes], [
	AC_SUBST(try_header,try_compile)
	target_cpu=universal
	real_cross_compiling=$cross_compiling
    ], [
	AS_IF([test x"$target_cpu" != x"${target_archs}"], [
	    echo 'int main(){return 0;}' > conftest.c
	    AS_IF([$CC $CFLAGS $ARCH_FLAG -o conftest conftest.c > /dev/null 2>&1], [
		rm -fr conftest.*
	    ], [test -z "$ARCH_FLAG"], [
		RUBY_DEFAULT_ARCH("$target_archs")
	    ])
	])
	target_cpu=${target_archs}
    ])
    AS_CASE(["$target"], [-*], [ target="$target_cpu${target}"])
    AS_CASE(["$target_alias"], [-*], [ target_alias="$target_cpu${target_alias}"])
], [
    AS_IF([test x"$target_alias" = x], [
	AS_CASE(["$target_os"],
	  [darwin*], [
	    AC_MSG_CHECKING([for real target cpu])
	    target=`echo $target | sed "s/^$target_cpu-/-/"`
	    target_cpu=`$CC -E - 2>/dev/null <<EOF |
#ifdef __x86_64__
"processor-name=x86_64"
#endif
#ifdef __i386__
"processor-name=i386"
#endif
#ifdef __ppc__
"processor-name=powerpc"
#endif
#ifdef __ppc64__
"processor-name=powerpc64"
#endif
#ifdef __arm64__
"processor-name=arm64"
#endif
EOF
	    sed -n 's/^"processor-name=\(.*\)"/\1/p'`
	    target="$target_cpu${target}"
	    AC_MSG_RESULT([$target_cpu])
	    ])
    ])
    target_archs="$target_cpu"
])
AS_IF([test "${target_archs}" != "${rb_cv_target_archs-${target_archs}}"], [
    AC_MSG_ERROR([target arch(s) has changed from ${rb_cv_target_archs-nothing} to ${target_archs}])
], [
    rb_cv_target_archs=${target_archs}
])
AS_IF([test "x${ARCH_FLAG}" != x], [
    CFLAGS="${CFLAGS:+$CFLAGS }${ARCH_FLAG}"
    LDFLAGS="${LDFLAGS:+$LDFLAGS }${ARCH_FLAG}"
])
# RUBY_UNIVERSAL_ARCH end
])dnl
dnl
AC_DEFUN([RUBY_UNIVERSAL_CHECK_HEADER_COND], [ dnl
  AC_CACHE_CHECK([for $2 when $1], [$3],
    AC_COMPILE_IFELSE([AC_LANG_PROGRAM(
        [AC_INCLUDES_DEFAULT([$6])[
          @%:@if ]$1[
          @%:@include <]$2[>
          @%:@endif]], [[]])],
      [AS_VAR_SET($3, yes)],
      [AS_VAR_SET($3, no)]))
  AS_VAR_IF([$3], [yes], [dnl
    printf "@%:@if %s\n" "$1" >>confdefs.h
    AC_DEFINE_UNQUOTED(HAVE_[]AS_TR_CPP($2), 1)dnl
    printf "@%:@endif\n" >>confdefs.h dnl
  $4], [$5])
])dnl
dnl
dnl RUBY_UNIVERSAL_CHECK_HEADER(CPU-LIST, HEADER,
dnl                      [ACTION-IF-FOUND], [ACTION-IF-NOT-FOUND],
dnl                      [INCLUDES = DEFAULT-INCLUDES])
AC_DEFUN([RUBY_UNIVERSAL_CHECK_HEADER], [ dnl
  m4_if([$# dnl
  ], [0], [], [ dnl
    m4_foreach([rb_Header], [$1],
      [AS_CASE([",$target_archs,"], [*,]rb_Header[,*],
        [RUBY_UNIVERSAL_CHECK_HEADER_COND]([defined(__[]rb_Header[]__)],
          [$2], [rb_cv_header_[]AS_TR_SH($2)_on_[]AS_TR_SH(rb_Header)],
          [$3], [$4], [$5])
        )
      ])
  ])dnl
])dnl
