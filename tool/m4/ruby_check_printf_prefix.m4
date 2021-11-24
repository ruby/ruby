# -*- Autoconf -*-
AC_DEFUN([RUBY_CHECK_PRINTF_PREFIX], [
AC_CACHE_CHECK([for printf prefix for $1], [rb_cv_pri_prefix_]AS_TR_SH($1),[
    [rb_cv_pri_prefix_]AS_TR_SH($1)=[NONE]
    RUBY_WERROR_FLAG(RUBY_APPEND_OPTIONS(CFLAGS, $rb_cv_wsuppress_flags)
    for pri in $2; do
        AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[@%:@include <stdio.h>
	    @%:@include <stddef.h>
            @%:@ifdef __GNUC__
            @%:@if defined __MINGW_PRINTF_FORMAT
            @%:@define PRINTF_ARGS(decl, string_index, first_to_check) \
              decl __attribute__((format(__MINGW_PRINTF_FORMAT, string_index, first_to_check)))
            @%:@else
            @%:@define PRINTF_ARGS(decl, string_index, first_to_check) \
              decl __attribute__((format(printf, string_index, first_to_check)))
            @%:@endif
            @%:@else
            @%:@define PRINTF_ARGS(decl, string_index, first_to_check) decl
            @%:@endif
	    PRINTF_ARGS(void test_sprintf(const char*, ...), 1, 2);]],
            [[printf("%]${pri}[d", (]$1[)42);
             test_sprintf("%]${pri}[d", (]$1[)42);]])],
            [rb_cv_pri_prefix_]AS_TR_SH($1)[=[$pri]; break])
    done)])
AS_IF([test "[$rb_cv_pri_prefix_]AS_TR_SH($1)" != NONE], [
    AC_DEFINE_UNQUOTED([PRI_]m4_ifval($3,$3,AS_TR_CPP(m4_bpatsubst([$1],[_t$])))[_PREFIX],
        "[$rb_cv_pri_prefix_]AS_TR_SH($1)")
])
])dnl
