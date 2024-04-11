dnl -*- Autoconf -*-
AC_DEFUN([MMTK_RUBY], [

[MMTK_RUBY_SO_NAME=libmmtk_ruby.$SOEXT]

AC_ARG_WITH(mmtk-ruby,
    AS_HELP_STRING([--with-mmtk-ruby=DIR],
    [Path to the mmtk-ruby repoitory, the MMTk binding for Ruby.]),
    [], []
)

AC_ARG_WITH(mmtk-ruby-debug,
    AS_HELP_STRING([--with-mmtk-ruby-debug],
    [Use the debug build of mmtk-ruby]),
    [], [with_mmtk_ruby_debug=no]
)

AC_ARG_WITH(mmtk-ruby-so,
    AS_HELP_STRING([--with-mmtk-ruby-so=/path/to/$libmmtk_ruby.so],
    [Override auto-detected path to $libmmtk_ruby.so]),
    [], []
)

AC_SUBST([with_mmtk_ruby])

AC_MSG_CHECKING([if the Ruby MMTk binding is enabled])
AS_IF([test -n "$with_mmtk_ruby"], [
    AC_MSG_RESULT([yes])

    AS_IF([test -n "$with_mmtk_ruby_so"], [
        AC_MSG_NOTICE([User specified the path to $MMTK_RUBY_SO_NAME: $with_mmtk_ruby_so])
        mmtk_ruby_so_basename=$(basename $with_mmtk_ruby_so)
        AS_IF([test "x$mmtk_ruby_so_basename" != "x$MMTK_RUBY_SO_NAME"],[
            AC_MSG_ERROR([The base name must be $MMTK_RUBY_SO_NAME. Found: $mmtk_ruby_so_basename])
        ])
        mmtk_ruby_so_path="$with_mmtk_ruby_so"
        mmtk_ruby_build_suggestion="Please build it first"
    ], [
        mmtk_ruby_repo_path="$with_mmtk_ruby"

        AC_MSG_CHECKING([for mmtk-ruby repository])
        AS_IF([test -f "$mmtk_ruby_repo_path/mmtk/Cargo.toml"], [
            AC_MSG_RESULT([$mmtk_ruby_repo_path])
        ], [
            AC_MSG_ERROR([$mmtk_ruby_repo_path doesn't look like an mmtk-ruby repository])
        ])

        AC_MSG_CHECKING([if we use the debug or release build of $MMTK_RUBY_SO_NAME])
        AS_IF([test "x$with_mmtk_ruby_debug" != xno], [
            AC_MSG_RESULT([debug])
            mmtk_ruby_so_path=$mmtk_ruby_repo_path/mmtk/target/debug/$MMTK_RUBY_SO_NAME
            mmtk_ruby_build_command="cargo build"
        ], [
            AC_MSG_RESULT([release])
            mmtk_ruby_so_path=$mmtk_ruby_repo_path/mmtk/target/release/$MMTK_RUBY_SO_NAME
            mmtk_ruby_build_command="cargo build --release"
        ])
        mmtk_ruby_build_suggestion="Please build it with \`$mmtk_ruby_build_command\` in $mmtk_ruby_repo_path/mmtk"
    ])

    AC_MSG_CHECKING([for built $MMTK_RUBY_SO_NAME library ($mmtk_ruby_so_path)])
    AS_IF([test -f "$mmtk_ruby_so_path"], [
        AC_MSG_RESULT([yes])
    ], [
        AC_MSG_RESULT([no])
        AC_MSG_ERROR([$MMTK_RUBY_SO_NAME does not exist. $mmtk_ruby_build_suggestion])
    ])

    AC_DEFINE([USE_MMTK], [1])
    AC_DEFINE([USE_TRANSIENT_HEAP], [0])

    mmtk_ruby_so_realpath=$(realpath $mmtk_ruby_so_path)
    mmtk_ruby_lib_dir=$(dirname $mmtk_ruby_so_realpath)
    gc_support="MMTk ($mmtk_ruby_so_realpath)"
    LIBS="-L ${mmtk_ruby_lib_dir} -lmmtk_ruby -Wl,-rpath,${mmtk_ruby_lib_dir} $LIBS"

    AC_SUBST([mmtk_ruby_so_realpath])
    AC_SUBST([mmtk_ruby_lib_dir])
], [
    AC_MSG_RESULT([no])
    AC_DEFINE([USE_MMTK], [0])
    gc_support="Ruby's built-in GC"
])

])dnl
