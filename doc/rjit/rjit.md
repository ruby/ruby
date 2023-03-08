# RJIT

This document has some tips that might be useful when you work on RJIT.

## Supported platforms

The following platforms are assumed to work. `linux-x86_64` is tested on CI.

* OS: Linux, macOS, BSD
* Arch: x86\_64

## Developing RJIT

### Bindgen

If you see an "RJIT bindgen" GitHub Actions failure, please commit the `git diff` shown on the failed job.

For doing the same thing locally, run `make rjit-bindgen` after installing libclang.
macOS seems to have libclang by default. On Ubuntu, you can install it with `apt install libclang1`.

### --enable-rjit

On supported platforms, `--enable-rjit` is set by default. You usually don't need to specify this.
You may still manually pass `--enable-rjit` to try RJIT on unsupported platforms.

### --enable-rjit=dev

`--enable-rjit=dev` makes the interpreter slower, but enables the following two features:

* `--rjit-dump-disasm`: Dump all JIT code.
* `--rjit-stats`: Print RJIT stats.
