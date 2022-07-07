dnl -*- Autoconf -*-
m4_defun([RUBY_PROG_MAKEDIRS],
    [m4_bpatsubst(m4_defn([AC_PROG_MKDIR_P]),
        [MKDIR_P=\"$ac_install_sh -d\"], [
        AS_IF([test "x$MKDIR_P" = "xfalse"], [AC_MSG_ERROR([mkdir -p is required])])
        MKDIR_P="mkdir -p"])
    ]dnl
    AC_SUBST(MAKEDIRS, ["$MKDIR_P"])
)
