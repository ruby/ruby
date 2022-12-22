# MJIT

This document has some tips that might be useful when you work on MJIT.

## Supported platforms

The following platforms are either tested on CI or assumed to work.

* OS: Linux, macOS
* Arch: x86\_64, aarch64, arm64, i686, i386

### Not supported

The MJIT support for the following platforms is no longer maintained.

* OS: Windows (mswin, MinGW), Solaris
* Arch: SPARC, s390x

## Developing MJIT

### Bindgen

If you see an "MJIT bindgen" GitHub Actions failure, please commit the `git diff` shown on the failed job.

For doing the same thing locally, run `make mjit-bindgen` after installing libclang.
macOS seems to have libclang by default. On Ubuntu, you can install it with `apt install libclang1`.

### Always run make install

Always run `make install` before running MJIT. It could easily cause a SEGV if you don't.
MJIT looks for the installed header for security reasons.

### --mjit-debug vs --mjit-debug=-ggdb3

`--mjit-debug=[flags]` allows you to specify arbitrary flags while keeping other compiler flags like `-O3`,
which is useful for profiling benchmarks.

`--mjit-debug` alone, on the other hand, disables `-O3` and adds debug flags.
If you're debugging MJIT, what you need to use is not `--mjit-debug=-ggdb3` but `--mjit-debug`.
