# Ruby on Rust: conversion roadmap

The prioritized backlog for converting CRuby's C core to Rust. This file is the
single source of truth for *what to do next*; `AGENTS.md` is the source of truth
for *how to do it*. Read both before starting a task.

Status of this document: written 2026-10-20, after release 0.2
(`docs/ruby_on_rust/RELEASE-0.2.md`). Numbers below are from that release plus
the ledger on `master`; `RR-P0-01` re-measures them.

---

## 1. Where the project actually is

| | |
|---|---|
| C in the conversion scope (top-level `*.c`) | 113 files, 317,465 LOC |
| Functions inventoried | 11,108 |
| Functions ported | **25 (0.2%)**, measured at `10e26f3` |
| Ledger statuses | 0 `Ported`, 3 `In Progress` (`complex.c`, `re.c`, `util.c`), 103 `Not Started` |
| Rust written | ~2,800 lines in `core_rs/` |
| Differential fuzz units | 3 (`util_scan`, `re_memsearch`, `complex_scan`) |

Wave coverage at 0.2 (`tool/core_rs/inventory.rb`):

| Wave | What it is | Functions | Ported |
|---|---|---|---|
| A | leaf functions, never touch Ruby objects | 1,206 | 22 |
| B | public C API, objects only through the C API | 803 | 1 |
| C | internals needing struct layouts, write barriers or VM state | 5,976 | 2 |
| D | Onigmo, parser, VM, GC, JIT glue | 3,088 | 0 |

**The foundation is done and it is good.** The build switch, the ledger, the
wave inventory, the port-kit generator, the differential fuzz harness, the
visibility control and the FFI/exception-safety layer all exist and work.

**Phase 1 did not fail on planning. It failed on dispatch.** Release 0.2 records
that the port units "were never picked up", that the coding agent's label
trigger is dead, and that on Oct 8-9 the successor agent opened 91 unrequested
PRs which were all closed for breaking repository rules. Fixing the pipeline is
therefore P0, ahead of any porting.

### Scope that is not yet tracked anywhere

The ledger covers top-level `*.c` only. Full conversion also implies:

| Area | LOC | Note |
|---|---|---|
| `ext/**/*.c` | ~99,800 | C extensions in the stdlib, not in the ledger |
| `prism/` | ~38,900 | upstream-owned vendored parser; porting it forks it |
| `reg*.c` (Onigmo) | ~20,800 | third-party regex engine |
| `parse.y` | 524 KB | generated parser; not a `.c` file |
| `ccan/`, `missing/` | ~7,900 | vendored helpers and platform shims |

Decisions on these are `RR-P5-01`.

---

## 2. How a task gets picked up

Jules reads `AGENTS.md` automatically, but it does **not** scan this file and
start work on its own. One task per agent session, dispatched explicitly:

```
Read docs/ruby_on_rust/ROADMAP.md and AGENTS.md, then do task RR-P1-03.
Open one PR for that task only. Do not touch anything the task does not name.
```

For a porting task, name the port unit and let the agent generate its own brief
in its own VM:

```
Read docs/ruby_on_rust/ROADMAP.md and AGENTS.md, then do task RR-P1-01,
which is port unit siphash-A-01. Run
`ruby tool/core_rs/inventory.rb --kit siphash-A-01` first and follow its
output exactly. Open one PR for that unit only.
```

The kit prints the full task body: functions, line ranges, scope, fidelity
rules, required evidence and acceptance criteria. To list units that still have
work:

```bash
ruby tool/core_rs/inventory.rb --units --wave A --open
```

`inventory.rb` needs Ruby 3.0+ (it uses endless method definitions). That is
consistent with the repository, whose BASERUBY matrix is Ruby 3.1-3.3, so the
tool is not expected to run on macOS's system Ruby 2.6. Do not downgrade it.

Task IDs are stable and are never renumbered. A task is **pickup-ready** only
when it names its files, its acceptance criteria and what it is blocked on.

Dispatch is orchestrated by Claude Code rather than driven by hand; the
orchestration layer is bootstrapped with
`docs/ruby_on_rust/orchestrator-bootstrap-prompt.md` and lives in `.claude/rr/`.

The delegation target is the Jules v2alpha pipeline in workspace
`e09b7edc-9ec5-48e1-b8dd-c7dc8cdeb46e` ("Ruby on Rust"), driven with the `jules`
CLI: a roadmap priority band becomes a Jules **goal**, a roadmap task or port
unit becomes a **task** under it, and the computed priority state is published
as a **context**. `autonomyLevel` is the safety dial: `CREATE_SUGGESTIONS` yields insights and
assessments only, while `CREATE_ASSETS` already opens PRs and `SUBMIT_ASSETS` is
fully autonomous. No goal should leave `CREATE_SUGGESTIONS` before `RR-OWN-01`
makes the Port gate a required check.
`stitch` is Google's UI design product and has no role in this migration.

---

## 3. Owner actions (an agent cannot do these)

These gate everything below and need the repository owner.

| ID | Action | Why it blocks |
|---|---|---|
| `RR-OWN-01` | Make the **Rust ports** workflow a required status check on `master` | Unmet exit criterion 1 of 0.2. Without it a rule-breaking PR can merge, which is how the 91-PR incident did damage. |
| `RR-OWN-02` | Configure the agent's workspace so it can only open PRs against branches, with the Port gate required | The dispatch path has to be safe before throughput matters. |
| `RR-OWN-03` | Tag `v0.2.0` | Unmet exit criterion 5. |
| `RR-OWN-04` | Decide the end state: does the C get deleted eventually, or does `--without-rust-ports` stay forever? | Determines whether P3 and P5 are mandatory. See `RR-P5-04`. |

---

## 4. P0 — Fix the pipeline

Nothing in P1-P5 should start before P0 is done. These are small, and they are
what makes the next 11,000 functions dispatchable.

| ID | Task | Scope | Acceptance |
|---|---|---|---|
| `RR-P0-01` **Done** (#125) | **Re-measure and commit a coverage baseline.** Run the inventory on current `master`, commit the snapshot, and add a `make core-rs-inventory` target plus a CI step that fails if the committed snapshot drifts. | `tool/core_rs/inventory.rb` (add `--snapshot`), `docs/ruby_on_rust/inventory-snapshot.tsv` (new), `core_rs/core_rs.mk`, `.github/workflows/rust_ports.yml` | Snapshot committed; `make core-rs-inventory` reproduces it byte for byte; CI fails on drift. |
| `RR-P0-02` **Done** (#124) | **Resolve the allocation rule drift in AGENTS.md.** §6.1 says core_rs has "no allocation", but `core_rs/src/lib.rs` declares `extern crate alloc` and `core_rs/src/alloc.rs` implements a `GlobalAlloc` over `ruby_xmalloc`. An agent reading §6.1 will either refuse to allocate or silently break a stated rule. Rewrite §6.1 to state the actual rule: `no_std`, no external crates, and allocation only through `crate::alloc`'s Ruby-GC-backed allocator. | `AGENTS.md` §6.1 only | §6.1 matches the code; `core_rs/src/alloc.rs` is referenced from it. |
| `RR-P0-03` **Done** (#126) | **Restore the missing strategy document.** `tool/core_rs/inventory.rb:422` and `RELEASE-0.2.md` both cite `claude/migration-strategy.md`, which is not in the repository, and reference decisions D1-D8 that are recorded nowhere. Either restore it at `docs/ruby_on_rust/migration-strategy.md` with the wave definitions and the D-decisions written out, or repoint both references at this roadmap. | `docs/ruby_on_rust/migration-strategy.md` (new), `tool/core_rs/inventory.rb` (the one citation), `docs/ruby_on_rust/RELEASE-0.2.md` | No reference in the repository points at a non-existent document. |
| `RR-P0-04` **Done** (#128) | **Add a performance gate to the Port gate.** A faithful port that is measurably slower is a failed port, and nothing currently measures that. Add a job that runs a fixed `benchmark/` subset in both build modes and fails if the ports build regresses beyond a stated threshold. | `.github/workflows/rust_ports.yml`, `tool/core_rs/bench_compare.rb` (new) | The job runs in both modes, prints both numbers, and fails on a regression past the documented threshold. |
| `RR-P0-05` | **Generate fuzz-unit scaffolding.** Every port needs a differential fuzz unit, and today each is hand-written from `core_rs/fuzz/template.c`. Add `inventory.rb --fuzz-unit <id>` that emits the harness skeleton with the unit's signatures filled in. | `tool/core_rs/inventory.rb`, `core_rs/fuzz/template.c` | Generated unit for an existing port compiles and reproduces the committed unit's behaviour. |
| `RR-P0-06` | ~~Write the dispatch protocol into AGENTS.md.~~ **Done** — landed as `AGENTS.md` §13 together with this roadmap. | `AGENTS.md` §13 | An agent reading AGENTS.md alone can tell whether it is allowed to open a PR. |
| `RR-P0-07` **Done** (#127) | **Restore a green `master`.** Every `Rust ports` run on `master` since #122 (merge `59d1603654`, 2026-10-20) fails at `building core_rs`: `error[E0428]: the name ruby_xfree is defined multiple times` (`core_rs/src/ffi/api/non_raising.rs:21` and `:102`). #121 and #122 both declared the Ruby allocator functions and merged cleanly into duplicates: #121 put `ruby_xmalloc`/`ruby_xrealloc`/`ruby_xfree` in `ffi/api/non_raising.rs` (with wrappers), and #122 added `ruby_xfree` again in `non_raising.rs` and `ruby_xmalloc`/`ruby_xrealloc` in `ffi/api/raising.rs`. Keep one declaration of each, in the module whose raising classification is correct per AGENTS.md (`ruby_xmalloc` and `ruby_xrealloc` can raise `NoMemoryError`), and point `core_rs/src/alloc.rs` and the `ffi/api.rs` signature tests at it. Also carry `50aa36114a` ("handle zero-sized layout in RubyGlobalAlloc::realloc"), a fix pushed to #122's branch after the merge that never reached `master`. | `core_rs/src/ffi/api/non_raising.rs`, `core_rs/src/ffi/api/raising.rs`, `core_rs/src/ffi/api.rs`, `core_rs/src/alloc.rs`; new test files only | Every `Rust ports` job is green on the PR's head commit; `make core-rs-test` passes; the PR quotes the E0428 error it removed. |
| `RR-P0-08` | **Remove the dangling struct-layout reference.** `docs/ruby_on_rust/migration-strategy.md` (restored by #126) cites `docs/ruby_on_rust/design-struct-layouts.md`, which does not exist; it is the future output of `RR-P4-01`. Replace the path with plain text naming `RR-P4-01` as the pending struct-layout design, so the reference becomes a real link once that design lands. | `docs/ruby_on_rust/migration-strategy.md` only | `git grep design-struct-layouts` finds no path reference to a file that does not exist. |
| `RR-P0-09` | **Make the performance gate trustworthy.** On `master` `afd3366d1e` the gate from #128 failed with `app_fib.rb` at +24.11% while the other benchmarks moved between -6% and +1% and the total was +3.12%. It also printed "regressed by +3.12% (threshold: 10.0%)" and failed anyway, because any one benchmark over the threshold fails the run. Each figure is the minimum of 3 sub-second whole-process runs on a shared runner. Interleave the two builds, run each benchmark enough times for a stable median (at least 10), subtract `ruby -e0` startup, and fail on the geometric mean of the per-benchmark ratios, reporting individual benchmarks as warnings. State the threshold and the method in the script header. Then show whether `app_fib` really regresses: if it does, name the ported function responsible. | `tool/core_rs/bench_compare.rb`, `.github/workflows/rust_ports.yml` (the performance gate job only) | The gate passes on unchanged `master` in 3 consecutive runs, fails on an injected 20% slowdown, and its failure message matches its decision. |
| `RR-P0-10` | **Keep compiled-out C out of port units.** `inventory.rb` ignores the preprocessor, so kits list functions that CRuby never compiles, and ports then export them unconditionally. Two cases surfaced on 2026-10-21. `numeric-A-01` lists `round`, which exists only under `#ifndef HAVE_ROUND` (#133 exported a global `round` that competes with libm). `siphash-A-01` lists `int_sip_dump`, `int_sip_init` and `sip_hash_dump`, which sit under `#if SIP_HASH_STREAMING`, and `random.c` sets that to 0 before `#include "siphash.c"` (#134 exported a new `sip_hash_dump`). Mark functions inside conditional blocks in the inventory: excluded when the condition is known false in every supported build, otherwise listed with their condition, and the kit tells the porter to keep the same condition. Regenerate the snapshot. | `tool/core_rs/inventory.rb`, `docs/ruby_on_rust/inventory-snapshot.tsv` | `--kit siphash-A-01` no longer marks the three streaming functions "to port"; `--kit numeric-A-01` shows `round` with its `HAVE_ROUND` condition or excludes it; `--check` passes; the snapshot diff lists exactly the functions whose classification changed. |

---

## 5. P1 — Wave A throughput (1,184 functions left)

Mechanical, pure, fuzzable, and parallel across files: this is where coverage
moves. Each task is one port unit from `inventory.rb --units --wave A --open`,
dispatched with its generated kit. Units in the same file are serialized;
different files run in parallel.

**Start with the five units that already have kits** (issues #110-#114, 44
functions, still valid for this base):

| ID | Unit | File |
|---|---|---|
| `RR-P1-01` | `siphash-A-01` | `siphash.c` |
| `RR-P1-02` | `numeric-A-01` | `numeric.c` |
| `RR-P1-03` | `strftime-A-01` | `strftime.c` |
| `RR-P1-04` | `pack-A-01` | `pack.c` |
| `RR-P1-05` | `bignum-A-03` | `bignum.c` |

Then, in this order (each file's units in source order, regenerate IDs with
`--units`):

| ID | Files | Rationale |
|---|---|---|
| `RR-P1-06` | finish `util.c`, `re.c`, `complex.c` | Three files are `In Progress` and none is `Ported`. Closing a file first proves the end-to-end path, including dropping an `rb_core_*` export once its last C caller is gone. |
| `RR-P1-07` | `sprintf.c`, `strftime.c`, `util.c` remainder | Pure formatting and scanning; the highest fuzz value per function. |
| `RR-P1-08` | `bignum.c`, `rational.c`, `complex.c`, `numeric.c` leaves | Dense arithmetic kernels, exactly expressible, and overflow behaviour is checkable. |
| `RR-P1-09` | `st.c`, `siphash.c`, `random.c`, `sort.c` | Self-contained data-structure and hashing leaves. |
| `RR-P1-10` | `pack.c`, `time.c`, `enc/*` leaves reachable from top level | Byte-level encode/decode; high regression risk, so high fuzz payoff. |
| `RR-P1-11` | every remaining Wave A unit | Sweep. Add `--open` to the dispatch loop until it prints nothing. |

Exit: Wave A ≥ 90% ported (the 0.2 target, still unmet at 1.8%).

---

## 6. P2 — Wave B (802 functions left)

Public C API functions that touch objects only through the C API. The FFI layer
exists; it needs breadth and a stronger gate before volume.

| ID | Task | Scope |
|---|---|---|
| `RR-P2-01` | Extend `ffi/api.rs` coverage to the C API surface Wave B actually calls, driven by a list generated from the inventory. Prototypes copied from `include/ruby/`; public API only. | `core_rs/src/ffi/api*.rs`, `tool/core_rs/inventory.rb` |
| `RR-P2-02` | Teach the fuzz harness to compare **raised exceptions**: run both sides under `rb_protect` and compare `rb_errinfo()` class and message. Required by the Wave B rules the kit already prints, but not yet implemented in `core_rs/fuzz/`. | `core_rs/fuzz/template.c`, `core_rs/fuzz/run.rb` |
| `RR-P2-03` | Add a `Drop`-across-raise lint: a check that fails if a port holds a live `Drop` value across a call that can raise (AGENTS.md §6.9). Static grep of `ffi::api::raising::*` call sites is enough to start. | `tool/core_rs/`, `.github/workflows/rust_ports.yml` |
| `RR-P2-04` | Wave B unit sweep, one unit per session, after `RR-P2-01`-`03`. | per `--units --wave B --open` |

Exit: Wave B ≥ 25% (the 0.2 stretch target), then 100%.

---

## 7. P3 — Platform completeness

`configure.ac` builds the ports only on `linux*`, `darwin*` and `freebsd*`, and
never when cross-compiling; Windows does not build `core_rs` at all. While that
holds, **the C can never be deleted** and every port is permanent dual
maintenance. If `RR-OWN-04` says the C goes away, this priority is mandatory and
moves ahead of P4.

| ID | Task | Scope |
|---|---|---|
| `RR-P3-01` | Build `core_rs` on Windows/MSVC under `nmake`. | `win32/Makefile.sub`, `core_rs/core_rs.mk`, `.github/workflows/windows.yml` |
| `RR-P3-02` | Support cross-compilation by passing `--target=<triple>` to rustc and threading the target through configure. | `configure.ac`, `core_rs/core_rs.mk`, `.github/workflows/crosscompile.yml` |
| `RR-P3-03` | WebAssembly target (`wasm32-wasi`). | `configure.ac`, `.github/workflows/wasm.yml` |
| `RR-P3-04` | Remaining targets configure rejects today, one PR each, after `RR-P3-02`. | `configure.ac` |

---

## 8. P4 — Wave C (5,974 functions)

The hard half: internals that need struct layouts, write barriers and VM state.
**Design first; do not dispatch port units until the three design tasks land.**

| ID | Task | Scope |
|---|---|---|
| `RR-P4-01` | **Struct layout strategy without bindgen.** core_rs may not use external crates and must build offline, so `bindgen` is out. Decide between hand-written `#[repr(C)]` mirrors guarded by generated static assertions (the existing `core_rs/cfg.c` mechanism already does this for `cfg` flags) or generating the mirrors from the headers at build time with rustc-only tooling. Write it up with a worked example. | `docs/ruby_on_rust/design-struct-layouts.md` (new), `core_rs/cfg.c`, `core_rs/src/ffi/` |
| `RR-P4-02` | **GC and write-barrier design.** How a Rust port marks, pins and write-barriers (`RB_OBJ_WRITE`), and how `core_rs/src/alloc.rs` interacts with GC compaction. | `docs/ruby_on_rust/design-gc.md` (new), `core_rs/src/ffi/` |
| `RR-P4-03` | **VM state access design.** `GET_EC`/`GET_VM`/`GET_RACTOR`, frame walking, and the `rb_core_*` export rules at this scale. | `docs/ruby_on_rust/design-vm-state.md` (new) |
| `RR-P4-04` | Extend the inventory to split Wave C into dispatchable sub-waves once the above land, then sweep. | `tool/core_rs/inventory.rb` |

---

## 9. P5 — Wave D and the endgame

| ID | Task | Scope |
|---|---|---|
| `RR-P5-01` | **Scope decisions, written down.** For each of `prism/` (upstream-owned: porting it forks a separately maintained library), `reg*.c` (Onigmo), `parse.y` (generated), `ext/**` (~99,800 LOC, untracked), `ccan/` and `missing/`: in scope, out of scope, or replaced? Record the decision and the reason; add the in-scope ones to the ledger. | `docs/ruby_on_rust/migration-strategy.md`, `tool/porting_status.yml`, `tool/generate_porting_ledger.rb` |
| `RR-P5-02` | Wave D design docs for the pieces that survive `RR-P5-01`: the bytecode compiler (`compile.c`, 15,441 LOC), the VM loop (`vm*.c`), `gc.c`, and the parser. One doc each, no code. | `docs/ruby_on_rust/` |
| `RR-P5-03` | Wave D execution, gated on `RR-P5-02`. | per design docs |
| `RR-P5-04` | **The C-removal phase.** Only once P3 is complete and a subsystem is 100% ported on every supported platform: delete the `#if !USE_RUST_PORTS` branch for that subsystem, flip the configure default to `--with-rust-ports`, and mark the files `Ported` in the ledger. Needs `RR-OWN-04`. | `configure.ac`, the C files, `tool/porting_status.yml` |
| `RR-P5-05` | Report coverage in `README.md` (unmet exit criterion 5 of 0.2). | `README.md`, `tool/generate_porting_ledger.rb` |

---

## 10. Standing rules for every task here

From `AGENTS.md`, repeated because they are what the 91 closed PRs violated:

- One PR, one outcome. Touch only the files the task names (§7).
- Never weaken, skip or re-version a CI step or an existing test (§8).
- Never delete the C body of a ported function; it stays behind
  `#if !USE_RUST_PORTS` (§6.4).
- Never modify `yjit/`, `zjit/`, `jit/` or their `bindgen/` crates (§6.6).
- No new exported symbols from `libruby.so` (§6.7).
- Never merge `ruby/ruby` master (§12).
- After two failed attempts at the same check, stop and post a `BLOCKED:`
  comment with evidence (§11).
- Every PR description ends with an Evidence section (§9).
