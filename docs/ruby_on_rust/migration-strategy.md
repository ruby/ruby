# Ruby on Rust: Migration Strategy & Architectural Decisions

This document details the strategy, function classification waves, phase criteria, and architectural decisions (D1–D8) governing the incremental conversion of CRuby's C core to Rust (`core_rs`).

---

## 1. Overview & Strategy

The Ruby on Rust project incrementally ports the CRuby C core to Rust. The primary objective is to improve memory safety and performance while preserving 100% behavioral fidelity with original CRuby C code.

To ensure safety, maintainability, and continuous verification:
1. Every ported function retains its original C implementation behind an `#if !USE_RUST_PORTS` guard.
2. Rust implementations live in `core_rs/`, a `no_std` crate built strictly using `rustc` with no external crate dependencies.
3. Symbol exports from `libruby.so` remain unchanged; internal Rust functions called by C use hidden `rb_core_<file>_<name>` symbols.
4. Each ported function is verified with differential fuzzing (1M iterations, zero mismatches).

---

## 2. Function Classification Waves

Functions in CRuby's top-level C source files are inventoried (`tool/core_rs/inventory.rb`) and classified into five waves:

### Wave A — Leaf Functions
- **Definition**: Functions that never touch Ruby objects (`VALUE`, `ID`, `Qnil`, `Qtrue`, `Qfalse`, raising, or VM state).
- **Properties**: Pure byte/integer/string/math algorithms. Can be fuzzed as pure functions without VM or garbage collector initialization.
- **Examples**: Scanning/parsing helpers (`ruby_scan_digits`, `ruby_scan_hex`), memory comparison (`rb_memsearch`), SipHash calculation.

### Wave B — Public C API Functions
- **Definition**: Functions declared in public C headers (`include/ruby/`) that interact with Ruby objects (`VALUE`) strictly through public C API functions, without accessing internal struct layouts directly.
- **Properties**: Safe interaction with Ruby runtime through public C FFI bindings (`core_rs/src/ffi/`). Exception safety strictly adheres to the rule that no live Rust `Drop` allocations cross C frame calls that can raise exceptions.

### Wave C — Interpreter Internals
- **Definition**: Functions outside Wave D that access internal struct layouts (e.g. `RSTRING`, `RARRAY`, `RBASIC`), write barriers (`RB_OBJ_WRITE`), GC state, or VM state (`GET_EC`, `GET_VM`).
- **Properties**: Requires verified struct mirrors (pending struct-layout design RR-P4-01), GC safety rules, and VM thread-context accessors. Targeted in Phase 2.

### Wave D — Complex Core Subsystems
- **Definition**: Core subsystems deferred from Phase 1 by Decision D3:
  - Onigmo regular expression engine (`reg*.c`)
  - Compilers and parser glue (`compile.c`, `parse.y`, `prism`)
  - Virtual Machine loop and thread execution (`vm*.c`, `iseq.c`)
  - Garbage Collector (`gc.c`)
  - JIT engine glue (`jit.c`, `yjit`, `zjit`)
- **Properties**: Highly coupled core engine subsystems requiring dedicated architectural designs before porting.

### Wave X — Non-Library Entry Points & Stubs
- **Definition**: Executable entry points, test stubs, and build runner stubs (`main.c`, `goruby.c`, `ruby-runner.c`, `rubystub.c`, `dmydln.c`, `dmyenc.c`, etc.).
- **Properties**: Out of conversion library scope.

---

## 3. Standing Architectural Decisions (D1–D8)

### Decision D1: Incremental C-to-Rust Migration Scope & Architecture
- **Decision**: Port CRuby's C core incrementally function by function into a dedicated Rust library (`core_rs/`), maintaining full compatibility with the existing C runtime and build environment.
- **Rationale**: Rewriting the entire interpreter at once is high risk. Incremental porting allows continuous verification via standard CRuby test suites (`make test`, `make test-all`, `make test-spec`).

### Decision D2: Wave Classification of Interpreter Functions
- **Decision**: Inventory and classify all interpreter functions into Waves A, B, C, D, and X based on object dependency, API exposure, and engine coupling (`tool/core_rs/inventory.rb`).
- **Rationale**: Enables phased porting by complexity, starting with isolated leaf functions and progressing to object APIs and complex VM internals.

### Decision D3: Phase 1 Scope & Wave Deferral
- **Decision**: Phase 1 scope is strictly limited to the core infrastructure, build integration, differential fuzzing harness, FFI bindings, Wave A (leaf functions), and Wave B (public C API functions). Wave C and Wave D (Onigmo, parser, VM, GC, JIT) are deferred to Phase 2.
- **Phase 1 Exit Criteria**:
  - Wave A: ≥ 90% ported (target: ≥ 1,086 of ~1,206 functions).
  - Wave B: ≥ 25% ported (stretch target: ≥ 201 of ~803 functions).
  - Exported C API symbols from `libruby.so` remain byte-for-byte identical.
  - Dual build modes (`--with-rust-ports` and `--without-rust-ports`) build cleanly and pass test suites.

### Decision D4: Dual-Implementation & Single Build Switch
- **Decision**: Original C code is never deleted during porting. Every ported function retains its original C implementation in place, wrapped in `#if !USE_RUST_PORTS` ... `#endif`. Controlled by a single configure/build switch: `--with-rust-ports`, `--without-rust-ports`, or default `auto`.
- **Rationale**: Guarantees instant fallback to pure C implementation for debugging, regression isolation, and platforms without rustc support.

### Decision D5: `core_rs` Environment & Constraints
- **Decision**: `core_rs` is a `no_std` Rust crate (edition 2024, rustc 1.85.0+) with zero external crate dependencies. It builds strictly with `rustc` (no Cargo required) and allocates exclusively via Ruby's GC-backed allocator (`ruby_xmalloc`/`ruby_xfree` in `core_rs/src/alloc.rs`).
- **Rationale**: Ensures fast, deterministic, offline builds without external crate dependency risks or memory allocation mismatches with the Ruby runtime.

### Decision D6: Public C Symbol & Visibility Discipline
- **Decision**: Porting Rust functions must export zero new public C symbols (`libruby.so`). Internal C-to-Rust boundary functions use the `rb_core_<file>_<name>` naming convention, declared in `internal/core_rs.h` with hidden visibility, verified by `make core-rs-check-hidden` and `nm -D` comparisons.
- **Rationale**: Prevents ABI pollution or unintended symbol leakage to external C extensions or embedding applications.

### Decision D7: Differential Fuzzing & Behavioral Parity
- **Decision**: Ported Rust functions must match C behavior byte-for-byte under all inputs. Every ported unit requires differential fuzz testing in `core_rs/fuzz/` (1,000,000 test cases per unit, 0 mismatches, plus mutation validation).
- **Rationale**: High-throughput fuzzing guarantees complete behavioral equivalence and edge-case correctness before merging.

### Decision D8: Fixed Quality Bar vs Variable Scope
- **Decision**: "The quality bar is fixed and scope is the variable." Under no circumstances may quality checks, fuzz tests, or test suites be loosened, skipped, or bypassed to meet timeline or volume goals.
- **Rationale**: Correctness and stability take absolute precedence over total ported function count. Unverified or failing code will not merge.

---

## 4. Phase 2 Roadmap Reference

For the prioritized backlog of Phase 1 pipeline fixes, Wave A/B throughput, platform support, Wave C design, and Wave D scope decisions, refer to the project roadmap:
- `docs/ruby_on_rust/ROADMAP.md`
