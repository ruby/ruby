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

`test/ruby/test_regexp_engines.rb` compiles the regexp literals of the
regexp tests with both engines and compares the programs byte for byte,
through `Bug::Regexp.compile_info`. Matching is compared by fuzzing, and
performance by a set of workloads:

    ruby tool/regexp-fuzz.rb --ruby=./ruby --seeds=1..8 --count=5000 [--encodings]
    benchmark-driver benchmark/regexp_engine.yml \
      -e 'onigmo::./ruby --regexp-engine=onigmo' -e 'rust::./ruby --regexp-engine=rust'

## Status

Measured on arm64 macOS:

* The programs and optimizer choices are identical to Onigmo's for the
  2798 regexp literals of the test suite in six encodings.
* `test/ruby`, the regexp, string and matchdata specs and the tests of the
  default gems pass on the Rust engine; the failures left are the RSS-based
  leak checks, which fail on Onigmo the same way on this machine.
* Fuzzing found no difference in about 70,000 patterns, each matched
  against several subjects, in seven encodings.
* The workloads above take 1.36 times as long as on Onigmo (geometric mean).
  Compiling is 1.8 times slower, matching 1.1 to 2 times.

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
   RHEL 8.10, 9.8 and 10.2 have 1.92.0 in AppStream, but outside the
   "Development Tools" group, so building Ruby there needs one more package.
   Rust Toolset moves with each minor release (from 1.75 to 1.92 during
   8.10), so a system pinned to an older one may lack 1.85.
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
8. **The JIT panic hooks abort on any panic.** YJIT (`yjit/src/yjit.rs`)
   and ZJIT (`zjit/src/cruby.rs`) replace the process-wide panic hook with
   one that calls `rb_bug()`. The hook runs before unwinding starts, so with
   a JIT enabled a panic in this engine aborts the process even though the
   FFI boundary catches it. The crates linked into one ruby need a shared
   hook that knows which component panicked.
9. **Warnings run Ruby code.** Onigmo calls `rb_warn` from inside the
   parser, and `Warning.warn` may raise, which longjmps out of
   `onig_compile`. The Rust engine collects warnings during compilation and
   C emits them after it returns.
10. **Deep patterns overflow the machine stack.** Parsing, the tree passes
    and the optimizer recurse once per nesting level, up to the parse depth
    limit of 4096. Threads may run on 128KB machine stacks (M:N threads),
    where Onigmo compiles up to 199 nested groups and then relies on Ruby
    turning the overflow into SystemStackError by longjmp from its SIGSEGV
    handler. That cannot cross Rust frames, so the Rust engine compares its
    frame address with a limit taken from the execution context and returns
    before the stack runs out; C raises SystemStackError. Its frames are
    larger than Onigmo's, so it stops at 104 nested groups in such a thread.
    Matching Onigmo needs smaller frames or an explicit stack in the parser.
    On the main thread both engines reach the parse depth limit.
