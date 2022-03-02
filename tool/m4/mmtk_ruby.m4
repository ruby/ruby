dnl -*- Autoconf -*-
AC_DEFUN([MMTK_RUBY], [
AC_MSG_CHECKING([for MMTk binding for Ruby (mmtk-ruby)])
AC_ARG_WITH(mmtk-ruby,
    AS_HELP_STRING([--with-mmtk-ruby=DIR],
    [path to the MMTk binding for Ruby (mmtk-ruby)]),
    [
	mmtk_ruby_dir="$withval"
	gc_support="MMTk ($mmtk_ruby_dir)"
	AC_DEFINE([USE_THIRD_PARTY_HEAP])
	AC_DEFINE([USE_TRANSIENT_HEAP], [0])
	AC_MSG_RESULT([$mmtk_ruby_dir])
    ],
    [
	gc_support="Ruby's built-in GC"
	AC_MSG_RESULT([no])
    ]
)
])dnl
