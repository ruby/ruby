# Ruby on Rust 0.2 (Migration Phase 1)

Closed on 2026-10-15. Base commit: `master` at `10e26f3`.

Phase 1 was planned as the foundation plus Wave A (leaf functions that never touch Ruby objects) and as much of Wave B (functions that use objects only through the public C API) as passed the gate. The foundation landed. The porting waves did not get going: the port units dispatched to the coding agent were never picked up. Under decision D8 ("the quality bar is fixed and scope is the variable", see `docs/ruby_on_rust/migration-strategy.md`), only verified ports merged.

## What is in 0.2

### The `core_rs` crate (#12)
- `core_rs/` is a `no_std` Rust crate (edition 2024, rustc 1.85.0+) with no external crates and no allocation. It is built with `rustc` alone, with no Cargo, and works offline. Build rules are in `core_rs/core_rs.mk`. The crate is partially linked into `target/core_rs/core_rs.o`, which joins `COMMONOBJS`.
- **One build switch:** `--with-rust-ports`, `--without-rust-ports`, or the default `auto`. It sets `USE_RUST_PORTS` in `config.h` and `RbConfig::CONFIG["USE_RUST_PORTS"]`. Every ported function keeps its C body behind `#if !USE_RUST_PORTS`.
- **Ported functions:**
  - `util.c`: `ruby_scan_digits`, `ruby_scan_oct`, `ruby_scan_hex`, `ruby_strtoul`, `ruby_each_words`.
  - `re.c`: `rb_memsearch` (all search algorithms) and `rb_memcicmp`.
  - `complex.c`: the static string-scanner functions (complex-A-01). They are exported as hidden `rb_core_complex_*` symbols, declared in `internal/core_rs.h`.

### Verification tooling (#12, #13, #14, #15)
- **The `Rust ports` workflow (the Port gate):** Linux and macOS, each built with and without the ports; a mode check; `make core-rs-test`; btest and test-all in both modes; and the `port-proofs` job. `port-proofs` runs differential fuzzing (1M cases per unit, 0 mismatches required, plus a mutation check), compares the `nm -D` export set across the two modes, and runs `core-rs-check-hidden` and the ledger and inventory checks.
- **Differential fuzz harness:** `core_rs/fuzz/`, with the units `util_scan`, `re_memsearch` and `complex_scan`.
- **`tool/core_rs/inventory.rb`:** an exact function inventory classified into Waves A–D. It also generates the port-unit kits.
- **Visibility control:** `rb_core_<file>_<name>` symbols with hidden visibility, checked by `make core-rs-check-hidden`.

### FFI bindings for Wave B (#16)
- `core_rs/src/ffi/` (`value`, `api`, `protect`): `VALUE`, the special constants, fixnum helpers, public C API declarations, and `rb_protect` / `rb_jump_tag`.
- The exception-safety rule is in AGENTS.md §6.9: a Rust frame that calls C code that can raise holds no live `Drop` value.

### Fork decoupling and CI (#17, #115)
- **No more upstream syncs:** `UPSTREAM.md` records the final upstream base (ruby/ruby `e4672be48`, synced 2026-10-08). AGENTS.md §12 forbids upstream merges; security fixes are cherry-picked as `security-backport` PRs.
- **CI capacity:** the upstream test matrix runs nightly plus on manual dispatch. The upstream-only automations are manual. It has been green on master every night from Oct 10 to Oct 15; the Windows `nmake` steps flaked three times and passed on their one re-run each time.

## Coverage

Measured with `ruby tool/core_rs/inventory.rb` on `10e26f3`:

| Wave | Functions | Ported | Share | Phase 1 target |
|---|---|---|---|---|
| A (leaf) | 1,206 | 22 | 1.8% | ≥ 1,086 (90%) |
| B (C API) | 803 | 1 | 0.1% | ≥ 201 (25%) |
| C | 5,976 | 2 | 0.0% | Phase 2 |
| D | 3,088 | 0 | 0.0% | Phase 2 |
| all | 11,108 | 25 | 0.2% | |

## Exit criteria

| # | Criterion | Result |
|---|---|---|
| 1 | Fork decoupled: UPSTREAM.md, Port gate required on master, nightly matrix green | **Partly met.** UPSTREAM.md ✔. Nightly matrix green ✔. The Port gate is **not yet a required check** on master (owner setting). |
| 2 | Wave A ≥ 90% | **Not met** (1.8%). |
| 3 | Wave B ≥ 25% (stretch) | **Not met** (0.1%). |
| 4 | `libruby.so` exports unchanged; `--without-rust-ports` builds and passes | **Met.** 1,916 symbols, identical in both modes. |
| 5 | Ledger and README report coverage; release notes; tag `v0.2.0` | **Partly met.** Ledger ✔, release notes ✔. README does not report coverage. The tag is an owner action. |

## Verification on `10e26f3`

Both trees are out-of-tree `--enable-shared` builds, one with the ports and one with `--without-rust-ports`.

- btest: 2,100 / 2,100 in both modes.
- test-all on `test_string`, `test_integer`, `test_numeric`, `test_pack`, `test_time`, `test_bignum`, `test_hash` and `test_m17n`: 1,211 tests, 0 failures, 0 errors in both modes.
- `make core-rs-test`: 21 passed. `make core-rs-check-hidden`: OK. These two targets exist only in a ports build.
- Fuzz: 1M differential cases per unit, 0 mismatches. The mutation check detects faults in every unit.
- `generate_porting_ledger.rb --check` and `inventory.rb --check`: OK.

## Not done: Phase 2 backlog
- The five pilot units, 44 Wave A functions: siphash-A-01, numeric-A-01, strftime-A-01, pack-A-01 and bignum-A-03 (issues #110–#114). The kits are still valid for this base.
- The remaining Wave A and Wave B units (generate them with `inventory.rb --units --open`).
- Waves C and D: Onigmo, prism, parse.y, the VM loop, compile.c, GC, and internals that need struct layouts. These need design work first.

## Known issues
- The coding agent's issue-label trigger (`jules`) no longer starts tasks: the successor app (Stitch) opens PRs from its own workspace instead. On Oct 8–9 it opened 91 unrequested PRs, and all were closed for breaking repository rules. Phase 2 needs a working dispatch path before any wave can scale.
- Windows `nmake check` and `nmake extract-gems` are occasionally flaky in the upstream nightly jobs. Windows does not build `core_rs`.
