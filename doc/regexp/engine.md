# Regexp engine written in Rust

This is an experimental port of Onigmo's parser, compiler and matcher
(`regparse.c`, `regcomp.c`, `regexec.c`) to safe Rust, living in `regexp/`.
The goal is that a defect in the engine ends in a Ruby exception or a crash
instead of memory corruption. The encoding layer (`OnigEncodingType`,
`enc/*.c`, `regenc.c`) stays in C and is called through its function table.

Both engines are built into the same ruby while the port is in progress.
Each Regexp records which engine compiled it.

## Building

The crate needs rustc 1.85.0 or later (edition 2024) and GNU make. It is
built by default on the same platforms as YJIT and ZJIT (x86-64 and arm64 on
macOS, Linux and BSD, not cross-compiling).

    ./configure --enable-rust-regexp                     # release build with rustc only
    ./configure --enable-rust-regexp=dev                 # debug build through cargo
    ./configure --enable-rust-regexp --with-regexp-engine=rust   # make it the default

At run time `--regexp-engine=onigmo|rust` selects the engine for new Regexp
objects. `ruby -v` shows `+RUST_REGEXP` when the Rust engine is selected.

When more than one Rust crate is enabled (YJIT, ZJIT, this engine), release
builds compile each crate as an rlib and combine them through `ruby.rs` into
one static library, as before.

## Testing

    make regexp-check                              # cargo test and test_regexp.rb on the Rust engine
    make check RUN_OPTS=--regexp-engine=rust SPECOPTS='-T --regexp-engine=rust'

`test/lib/regexp_engine_support.rb` tells tests which engine is active.
`EnvUtil.invoke_ruby` passes `--regexp-engine` on to child processes.

## Open problems

Problems found while porting. Each one needs a decision before the Rust
engine can become the default or Onigmo can be removed.

1. **Platforms.** Rust code is built only where YJIT is (`JIT_TARGET_OK` in
   `configure.ac`). There is no Rust build for mswin, mingw or cygwin
   (`win32/` has no rules), for cross-compiling, or for ppc64le, s390x,
   riscv64, armv7 and i686. Removing Onigmo needs all of these, plus `ld -r`
   and `objcopy` on each ELF platform for the partial link in `defs/jit.mk`.
2. **Minimum rustc.** The crate uses edition 2024 (rustc 1.85.0) like ZJIT,
   while YJIT still builds with 1.58.0. Once Onigmo is removed, 1.85.0
   becomes the minimum for every Ruby build, which distributions must ship.
3. **Two regexp parsers already exist.** Prism parses regexp literals with
   its own `prism/regexp.c` to extract named captures and to report syntax
   errors with copies of Onigmo's messages, while `prism_compile.c` still
   compiles the literal with the engine to raise SyntaxError. parse.y takes
   names from the engine. A third parser must agree with both on what is a
   named capture and what is an error.
4. **Public C API exposes engine types.** `rb_reg_prepare_re` returns a
   `regex_t *`, and `rb_reg_onig_match` hands one to a callback that is
   expected to call `onig_search` or `onig_match` itself (strscan and
   racer-rb do). `RREGEXP_PTR` returns the `regex_t` embedded in the object
   slot. `onig_new`, `onig_search` and the `onig_region_*` functions are used
   by panko_serializer and strscan. These need a C shim over the Rust engine.
5. **The encoding layer depends on the engine.** `enc/unicode.c`,
   `enc/euc_jp.c` and `enc/shift_jis.h` call `onig_is_in_code_range`, which
   is defined in `regcomp.c`.
6. **Interrupts longjmp out of the matcher.** `CHECK_INTERRUPT_IN_MATCH_AT`
   calls `rb_thread_check_ints()`, which may raise. A longjmp across Rust
   frames is undefined behaviour, so the Rust engine returns to C first and
   C re-raises.
7. **`tool/lib/envutil.rb` is a copy** of ruby/test-unit-ruby-core. The
   `--regexp-engine` propagation has to go upstream as well.
