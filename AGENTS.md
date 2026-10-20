# Developer & AI Agent Guidelines (AGENTS.md)

Welcome to the **Ruby on Rust** repository. This document provides instructions, rules, and workflows for both human contributors and AI agents working on porting CRuby C source files to Rust.

---

## 1. Architecture & Cargo Setup

This repository contains the CRuby codebase incrementally migrating core C components to Rust.

- **Cargo Workspace**: The root `Cargo.toml` defines a workspace containing crates such as `yjit`, `zjit`, and `jit`.
- **Static Library Integration**: Cargo compiles a single static library target defined in `ruby.rs` (`crate-type = ["staticlib"]`) to integrate Rust modules into the C runtime.
- **Cargo Features**:
  - `yjit`: Enables YJIT Rust compiler module (`yjit/`).
  - `zjit`: Enables ZJIT experimental tier-2 compiler module (`zjit/`).
  - `disasm`: Enables disassembly output features.
  - `runtime_checks`: Enables runtime invariant checks.

---

## 2. Build Commands

### Rust Workspace Build
To compile the Rust workspace crates:
```bash
# Build debug artifacts across all workspace crates
cargo build --workspace

# Build optimized release artifacts
cargo build --release --workspace
```

### Full Ruby Build Workflow
To build the complete Ruby binary with Rust integration:
```bash
# 1. Generate configure script (if needed)
./autogen.sh

# 2. Configure build environment (enabling desired Rust JIT engines)
./configure --enable-yjit

# 3. Build Ruby executable and static library
make -j$(nproc)
```

---

## 3. Test Workflows

To verify changes across Rust and Ruby components, run the following test suites:

### Rust Unit & Integration Tests
```bash
cargo test --workspace
```

### Ruby Test Suites
```bash
# Fast bootstrap test suite
make test

# Full Ruby unit test suite
make test-all

# Ruby specification suite (ruby/spec)
make test-spec
```

### Porting Ledger Drift Verification
Before pushing changes, ensure the migration ledger `PORTING.md` is synchronized with `tool/porting_status.yml` and top-level C source files:
```bash
ruby tool/generate_porting_ledger.rb --check
```

---

## 4. C-to-Rust Porting Workflow

When porting or updating a C source file:

1. **Keep Baseline C Files Intact**: Core C source files in the repository root serve as the baseline reference and must remain unchanged unless required for C runtime linkage.
2. **Update Status Configuration**: Modify `tool/porting_status.yml` to reflect changes in file porting status:
   - Valid status values: `Not Started`, `In Progress`, `Ported`, `Blocked`, `N/A`.
   - Update target Rust crate/module name (e.g., `yjit`, `zjit`, `crate::array`).
   - Add notes or description as appropriate.
3. **Regenerate Ledger**: Run the ledger generation tool to update `PORTING.md`:
   ```bash
   ruby tool/generate_porting_ledger.rb
   ```
4. **Verify Ledger Freshness**: Run the check command to ensure `PORTING.md` has no drift:
   ```bash
   ruby tool/generate_porting_ledger.rb --check
   ```

---

## 5. Rules & Guardrails for AI Agents

- **Follow Workspace Rules**: Always observe instructions in `AGENTS.md` and any subdirectory `AGENTS.md` files.
- **Do Not Mask Test Failures**: Do not modify test assertions or delete test cases to pass CI unless explicitly intended.
- **Standard Ruby Tooling**: Scripts placed in `tool/` must rely strictly on standard Ruby libraries (`yaml`, `optparse`, etc.) without external gem dependencies.
- **Path Resolution**: Tools and scripts should resolve repository paths relative to `__dir__` to work reliably across environments.

---

## 6. Core Rust Architecture (standing decisions)

These decisions are fixed. A PR that deviates from them will be sent back. If you think one is wrong, say so in a PR comment. Do not work around it.

1. **New Rust code lives in `core_rs/`.** It is a `no_std` crate with edition 2024, rustc 1.85.0+, **no external crates** and no allocation. It is independent of the JIT crates and of `ruby.rs`: build rules are in `core_rs/core_rs.mk`, and the crate is partially linked into its own object (`target/core_rs/core_rs.o`) that joins `COMMONOBJS`. Add every new source file to `CORE_RS_SRCS` in `core_rs/core_rs.mk`.
2. **core_rs is compiled with `rustc` only.** Cargo is never required for it, and builds must work offline. Unit tests run with `make core-rs-test`, which also needs only rustc.
3. **One switch controls core Rust**, and it sets `USE_RUST_PORTS` (0/1) in `config.h` and `RbConfig::CONFIG["USE_RUST_PORTS"]`:
   - `--with-rust-ports`: the ports are required, and configure fails if they cannot be built.
   - `--without-rust-ports`: the original C only.
   - Default `auto`: the ports are used when rustc 1.85.0+ works for the target (Linux, macOS and FreeBSD, not cross-compiling). Otherwise configure prints a warning naming the reason.

   CI asserts that the main Linux and macOS jobs really build with the ports, so an `auto` fallback can never go unnoticed there.
4. **Keep the original C behind the switch.** A ported function's C body stays in place, wrapped in `#if !USE_RUST_PORTS` ... `#endif`. Do not delete the C, and never select the implementation with `USE_YJIT` / `USE_ZJIT`.
5. **Faithful first.** The Rust version must behave byte-for-byte like the C version: same output, same flushing, same encoding handling, and the same build-time macros honoured (e.g. `RB_DEFAULT_PARSER` / `--with-parser`). Do not add "safety" behaviour such as silently ignoring `NULL` in a port. Document the precondition instead.
6. **Do not modify upstream-owned code.** `yjit/`, `zjit/`, `jit/`, their `Cargo.toml` editions/MSRV and their `bindgen/` crates are synced from upstream CRuby. If you find a bug there, report it in the PR description.
7. **No new exported symbols.** `nm -D --defined-only libruby.so` (from an `--enable-shared` build) must match `master`, unless the task explicitly adds public API. Symbols that cross the C↔Rust boundary use the internal `rb_` prefix and are declared in `internal/*.h`. `ruby_` is the public embedding-API namespace. Do not rename a symbol into it to get past `test-leaked-globals`. A ported `static` C function that unported C still calls is exported as `rb_core_<file>_<name>`, declared in `internal/core_rs.h` (which gives it hidden visibility) and mapped with a `#define` in the C file's `#if USE_RUST_PORTS` branch; `make core-rs-check-hidden` must pass. Helpers called only by other ported functions stay private to the Rust module.
8. **Ledger.** Change statuses only through `tool/porting_status.yml`, then regenerate. A file is `In Progress` only once a port from this project has merged, and `Ported` only when no C implementation of it remains in use.
9. **Ruby objects and exception safety (Wave B).** Ports that take or return `VALUE`s use the bindings in `core_rs/src/ffi/` (`VALUE`, the special constants and fixnum helpers, public C API declarations, `protect`/`jump_tag`). Do not declare C API functions elsewhere, and declare only public API (`include/ruby/`) there, with the prototype copied from the header. A Ruby exception leaves C with `longjmp()`, which discards Rust frames without running destructors. Therefore **a Rust frame that calls a C function that can raise holds no live `Drop` value at the call, and neither does any Rust frame between it and the C caller; otherwise the raising code goes through `ffi::protect::protect` (`rb_protect`) and the port re-raises with `ffi::protect::jump_tag` after cleanup.** A Rust panic is never a Ruby exception: raise with `rb_raise()` exactly where the C does, with the same class and message.

---

## 7. Scope Discipline

- **One PR = one outcome.** Touch only the files the task names. If you believe another file must change, stop and explain why in a PR comment.
- **Respect dependencies.** If the task says "blocked on #N", do not push until #N is merged. Then rebase onto `master`.
- **Never fix a problem owned by another PR inside yours.** For example, build plumbing belongs to the build-foundation PR, not to a function port.

---

## 8. CI Integrity (non-negotiable)

- **Never remove, skip, `if: false`, comment out, loosen or re-version a CI step or test** to make a PR pass. This includes the "Remove cargo" step and the `RUSTC='rustc +1.58.0'` job, which exist to prove rustc-only and MSRV builds.
- **Never edit existing tests or expectations.** New tests may be added in new files.
- **Unit tests must exercise real code.** A `#[cfg(test)]` stub that replaces the function under test makes the test meaningless. Do not write them.
- **Allowed CI workflow edits** are only those your task explicitly allows. List each one and its reason in the PR description.

---

## 9. Definition of Done and Required Evidence

A PR is **done** only when **every required check on the final commit is green** and the acceptance criteria in the task or review comment are met. Do **not** write "verified", "ready to merge" or "all tests pass" while any check is red, queued or in progress. Report the actual state instead.

Every PR description must end with an **Evidence** section containing:
- the exact commands you ran and the last lines of their output;
- for each acceptance criterion, the command that demonstrates it;
- the `git diff master --stat` file list;
- for ports, test results in **both** `./configure` and `./configure --without-rust-ports` builds.

---

## 10. Reproducing CI Failures Locally

Before pushing a fix, reproduce the **exact failing job**. Passing `make btest` is not evidence that a different job is fixed. Job names encode their configuration:

| Failing job | Reproduce with |
| :--- | :--- |
| `make (check, --disable-yjit)` | `./configure --disable-yjit && make check` |
| `make (check, RUSTC='rustc +1.58.0', 1.58.0)` | `rustup install 1.58.0` and remove `cargo` from PATH, then `./configure RUSTC='rustc +1.58.0' && make check` |
| `make (zjit-check, ..., 1.85.0)` / ZJIT jobs | `./configure --enable-zjit=dev` plus the flags in the job name, then the named make target |
| parse.y workflow (`EnvUtil.current_parser == %[parse.y]`) | `./configure --with-parser=parse.y && make && make TESTRUN_SCRIPT='-renvutil -v -e "exit EnvUtil.current_parser == %[parse.y]"' run` |
| `omnibus compilations, #NN` | Matrix entry NN in `.github/workflows/compilers.yml` (compiler and flags), built **out of tree** |
| `Windows ...` | `win32/Makefile.sub` (nmake). Unix-only Makefile rules do not apply |
| `Cross compile` / `WebAssembly` | Host ≠ target. rustc needs `--target=<triple>` |
| `Miscellaneous checks` | `ruby tool/generate_porting_ledger.rb --check` and the other steps in `.github/workflows/check_misc.yml` |

Out-of-tree builds (`mkdir build && cd build && ../configure && make`) catch path bugs that in-tree builds hide.

---

## 11. When You Are Stuck

If the same check fails after **two** fix attempts, stop changing code. Post a PR comment starting with `BLOCKED:` that names the check, the hypotheses you tested, the evidence for each, and what you need. Do not alternate between two settings, for example edition 2021 ↔ 2024.

---

## 12. Upstream (ruby/ruby)

The fork stopped syncing from ruby/ruby on 2026-10-07; the base commit and the policy are in `UPSTREAM.md`.

- **Never merge ruby/ruby `master` into this repository.**
- Security fixes are cherry-picked as single PRs labelled `security-backport`. When the affected function has a Rust port, fix both the C (behind `#if !USE_RUST_PORTS`) and the Rust port, and add a regression test.
- After any change to top-level C files, run `ruby tool/generate_porting_ledger.rb` to refresh `PORTING.md`. `--check` ignores line-count drift but fails on file-list, status, target, subsystem or note differences.

---

## 13. What to Work On, and When You May Open a PR

**The backlog is `docs/ruby_on_rust/ROADMAP.md`.** It holds every task needed for
the conversion, in priority order, with a stable ID per task (`RR-P1-03`,
`RR-P0-02`, ...). This file tells you *how* to work; the roadmap tells you
*what*.

- **Work only on a task you were dispatched.** Your instructions name a roadmap
  task ID, or they paste a port-unit brief. If they name neither, ask for one —
  do not pick something yourself, and do not open a PR. Undispatched PRs are
  closed unread.
- **One task per session, one PR per task.** Touch only the files that task
  names (§7).
- **For a porting task, the brief is generated, not improvised:**
  ```
  ruby tool/core_rs/inventory.rb --kit <unit-id>     # the full task body
  ruby tool/core_rs/inventory.rb --units --open      # units with work left
  ```
  The kit prints the functions, their line ranges, the scope, the fidelity
  rules, the required evidence and the acceptance criteria. It is binding. The
  tool needs Ruby 3.0+.
- **Do not edit the roadmap as a side effect.** Changing a task's status is its
  own one-line change, made when that task's PR merges.
- **If the task conflicts with this file, this file wins.** Say so in the PR
  description instead of working around it (§6).
