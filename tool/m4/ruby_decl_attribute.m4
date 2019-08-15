# -*- Autoconf -*-
dnl RUBY_DECL_ATTRIBUTE(attrib, macroname, cachevar, condition, type, code)
AC_DEFUN([RUBY_DECL_ATTRIBUTE], [dnl
m4_ifval([$2], dnl
  [AS_VAR_PUSHDEF([attrib], m4_bpatsubst([$2], [(.*)], []))], dnl
  [AS_VAR_PUSHDEF([attrib], m4_toupper(m4_format(%.4s, [$5]))[_]AS_TR_CPP($1))] dnl
)dnl
m4_ifval([$3], dnl
  [AS_VAR_PUSHDEF([rbcv],[$3])], dnl
  [AS_VAR_PUSHDEF([rbcv],[rb_cv_]m4_format(%.4s, [$5])[_][$1])]dnl
)dnl
m4_pushdef([attrib_code],[m4_bpatsubst([$1],["],[\\"])])dnl
m4_pushdef([attrib_params],[m4_bpatsubst([$2(x)],[^[^()]*(\([^()]*\)).*],[\1])])dnl
m4_ifval([$4], [rbcv_cond=["$4"]; test "$rbcv_cond" || unset rbcv_cond])
AC_CACHE_CHECK(for m4_ifval([$2],[m4_bpatsubst([$2], [(.*)], [])],[$1]) [$5] attribute, rbcv, dnl
[rbcv=x
RUBY_WERROR_FLAG([
for mac in \
    "__attribute__ ((attrib_code)) x" \
    "x __attribute__ ((attrib_code))" \
    "__declspec(attrib_code) x" \
    x; do
  m4_ifval([$4],mac="$mac"${rbcv_cond+" /* only if $rbcv_cond */"})
  AC_TRY_COMPILE(
    m4_ifval([$4],${rbcv_cond+[@%:@if ]$rbcv_cond})
[@%:@define ]attrib[](attrib_params)[ $mac]
m4_ifval([$4],${rbcv_cond+[@%:@else]}
${rbcv_cond+[@%:@define ]attrib[](attrib_params)[ x]}
${rbcv_cond+[@%:@endif]})
$6
@%:@define mesg ("")
@%:@define san "address"
    attrib[](attrib_params)[;], [],
    [rbcv="$mac"; break])
done
])])
AS_IF([test "$rbcv" != x], [
    RUBY_DEFINE_IF(m4_ifval([$4],[${rbcv_cond}]), attrib[](attrib_params)[], $rbcv)
])
m4_ifval([$4], [unset rbcv_cond]) dnl
m4_popdef([attrib_params])dnl
m4_popdef([attrib_code])dnl
AS_VAR_POPDEF([attrib])dnl
AS_VAR_POPDEF([rbcv])dnl
])dnl
