dnl -*- Autoconf -*-
dnl RUBY_REPLACE_TYPE [typename] [default type] [macro type] [included]
AC_DEFUN([RUBY_REPLACE_TYPE], [dnl
    AC_CHECK_TYPES([$1],
		  [n="patsubst([$1],["],[\\"])"],
		  [n="patsubst([$2],["],[\\"])"],
		  [$4])
    AC_CACHE_CHECK([for convertible type of [$1]], rb_cv_[$1]_convertible, [
	AC_COMPILE_IFELSE(
	    [AC_LANG_BOOL_COMPILE_TRY([AC_INCLUDES_DEFAULT([$4])]
		[typedef $n rbcv_conftest_target_type;
		extern rbcv_conftest_target_type rbcv_conftest_var;
		], [sizeof(&*rbcv_conftest_var)])],
	[rb_cv_[$1]_convertible=PTR],
	[
	u= t=
	AS_CASE(["$n "],
	  [*" signed "*], [ ],
	  [*" unsigned "*], [
	    u=U],
	  [RUBY_CHECK_SIGNEDNESS($n, [], [u=U], [$4])])
	AS_IF([test x"$t" = x], [
	    for t in "long long" long int short; do
		test -n "$u" && t="unsigned $t"
		AC_COMPILE_IFELSE(
		    [AC_LANG_BOOL_COMPILE_TRY([AC_INCLUDES_DEFAULT([$4])]
			[typedef $n rbcv_conftest_target_type;
			typedef $t rbcv_conftest_replace_type;
			extern rbcv_conftest_target_type rbcv_conftest_var;
			extern rbcv_conftest_replace_type rbcv_conftest_var;
			extern rbcv_conftest_target_type rbcv_conftest_func(void);
			extern rbcv_conftest_replace_type rbcv_conftest_func(void);
			], [sizeof(rbcv_conftest_target_type) == sizeof(rbcv_conftest_replace_type)])],
		    [n="$t"; break])
	    done
	])
	AS_CASE([" $n "],
	  [*" long long "*], [
	    t=LL],
	  [*" long "*], [
	    t=LONG],
	  [*" short "*], [
	    t=SHORT],
	  [
	    t=INT])
	rb_cv_[$1]_convertible=${u}${t}])
    ])
    AS_IF([test "${AS_TR_SH(ac_cv_type_[$1])}" = "yes"], [
	n="$1"
    ], [
	AS_CASE(["${rb_cv_[$1]_convertible}"],
		[*LL], [n="long long"],
		[*LONG], [n="long"],
		[*SHORT], [n="short"],
		[n="int"])
	AS_CASE(["${rb_cv_[$1]_convertible}"],
		[U*], [n="unsigned $n"])
    ])
    AS_CASE("${rb_cv_[$1]_convertible}", [PTR], [u=], [U*], [u=+1], [u=-1])
    AC_DEFINE_UNQUOTED(rb_[$1], $n)
    AS_IF([test $u], [
    AC_DEFINE_UNQUOTED([SIGNEDNESS_OF_]AS_TR_CPP($1), $u)
    AC_DEFINE_UNQUOTED([$3]2NUM[(v)], [${rb_cv_[$1]_convertible}2NUM(v)])
    AC_DEFINE_UNQUOTED(NUM2[$3][(v)], [NUM2${rb_cv_[$1]_convertible}(v)])
    AC_DEFINE_UNQUOTED(PRI_[$3]_PREFIX,
	[PRI_`echo ${rb_cv_[$1]_convertible} | sed ['s/^U//']`_PREFIX])
    ])
])dnl
