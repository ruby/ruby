dnl -*- Autoconf -*-
AC_DEFUN([RUBY_WASM_TOOLS],
[AS_CASE(["$target_os"],
[wasi*], [
    AC_CHECK_TOOL(WASMOPT, wasm-opt)
    AS_IF([test x"${WASMOPT}" = x], [
        AC_MSG_ERROR([wasm-opt is required])
    ])
    AC_SUBST(wasmoptflags)
    : ${wasmoptflags=-O3}

    AC_MSG_CHECKING([wheather \$WASI_SDK_PATH is set])
    AS_IF([test x"${WASI_SDK_PATH}" = x], [
        AC_MSG_RESULT([no])
	AC_MSG_ERROR([WASI_SDK_PATH environment variable is required])
    ], [
        AC_MSG_RESULT([yes])
        CC="${CC:-${WASI_SDK_PATH}/bin/clang}"
        LD="${LD:-${WASI_SDK_PATH}/bin/clang}"
        AR="${AR:-${WASI_SDK_PATH}/bin/llvm-ar}"
        RANLIB="${RANLIB:-${WASI_SDK_PATH}/bin/llvm-ranlib}"
        OBJCOPY="${OBJCOPY:-${WASI_SDK_PATH}/bin/llvm-objcopy}"
    ])
])
])dnl
