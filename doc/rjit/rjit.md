# RJIT: Ruby JIT

This document has some tips that might be useful when you work on RJIT.

## Project purpose

This project is for experimental purposes.
For production deployment, consider using YJIT instead.

## Supported platforms

The following platforms are assumed to work. `linux-x86_64` is tested on CI.

* OS: Linux, macOS, BSD
* Arch: x86\_64

## configure
### --enable-rjit

On supported platforms, `--enable-rjit` is set by default. You usually don't need to specify this.
You may still manually pass `--enable-rjit` to try RJIT on unsupported platforms.

### --enable-rjit=dev

`--enable-rjit=dev` makes the interpreter slower, but enables `ruby --rjit-stats` to work.

## make
### rjit-bindgen

If you see an "RJIT bindgen" GitHub Actions failure, please commit the `git diff` shown on the failed job.

For doing the same thing locally, run `make rjit-bindgen` after installing libclang.
macOS seems to have libclang by default. On Ubuntu, you can install it with `apt install libclang1`.

## ruby
### --rjit-stats

This prints RJIT stats at exit. Available with `--enable-rjit=dev` on configure.

### --rjit-dump-disasm

This dumps all JIT code. You need to install libcapstone before configure.

* Ubuntu: `sudo apt-get install -y libcapstone-dev`
* macOS: `brew install capstone`
