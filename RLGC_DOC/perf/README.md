# RLGCv2 performance benchmarks

Reproducible scripts for the RLGCv2-vs-stock-master comparison written up in
[`../PERF_2026-07-06.md`](../PERF_2026-07-06.md).

## What each script measures

| script | measures |
| --- | --- |
| `binary_trees.rb`  | GC-heavy weak scaling (`MODE=single\|ractor\|fork`, `N`, `D`) |
| `json_parse.rb`    | embarrassingly-parallel JSON parse (`MODE`, `N`, `REP`) |
| `json_pc.rb`       | producer/consumer JSON: Ractor `move` vs fork pipe-IPC (`MODE=ractor\|fork`, `N`, `REP`, `RECS`) |
| `pure_cpu.rb`      | hardware ceiling: pure compute, no alloc/GC (`N`, `W`) |
| `newobj.rb`        | single-Ractor allocation cost for `perf stat` (`CNT`, `GC=on\|off`, `BASE=1`) |
| `tail_latency.rb`  | max VM-lock stall on a non-main Ractor during a main-Ractor GC (`LIVE`, `ITER`) |

All timing scripts print one number: wall-clock seconds (`tail_latency.rb`
prints milliseconds). Weak scaling: each worker does the FULL workload, so
total work grows with `N`; ideal parallelism keeps the wall time flat.

## Building the two binaries (fair comparison)

The point is to isolate the RLGC changes, so both binaries are built from the
**same base commit** with the **same configure flags** (`-O3`, `RUBY_DEBUG`
off). RLGCv2's merge-base with `origin/master` is `e5518bee2`.

```sh
# --- RLGCv2 (the branch under test) ---
cd <ruby-src>                 # the rlgc-v2 worktree
git checkout rlgc-v2
./configure --prefix=/tmp/rlgc --disable-install-doc
make -j$(nproc) ruby         # => ./ruby   (this is RUBY_RLGC)

# --- stock master at RLGCv2's base commit ---
git worktree add --detach ../mbase e5518bee2
cd ../mbase && ./autogen.sh
mkdir -p ../build-mbase && cd ../build-mbase
../mbase/configure --prefix=/tmp/mbase --disable-install-doc
make -j$(nproc)              # => ./ruby   (this is RUBY_MASTER)
```

Do NOT compare against an unrelated prebuilt `trunk`/`ractor_port` tree: a
different base commit mixes in ~a year of unrelated Ruby changes.

## JSON load path

These builds run the benchmarks with `--disable-gems` (rubygems' `gem_prelude`
needs `rbconfig`, which isn't on this minimal load path). Point `-I` at the
json C extension and its Ruby part:

```sh
# RLGCv2 (in-place build of <src>)
JSON_RLGC="--disable-gems -I <src>/ext/json/lib -I <src>/.ext/x86_64-linux -I <src>/lib"

# stock master (out-of-tree build)
JSON_MASTER="--disable-gems -I <mbase-src>/ext/json/lib -I <mbase-build>/.ext/x86_64-linux -I <mbase-src>/lib"
```

Sanity check: `ruby $JSON_RLGC -e 'require "json"; p JSON.parse("[1,2,3]")'`.

## Running

```sh
export RUBY_RLGC=<src>/ruby
export RUBY_MASTER=<mbase-build>/ruby
export JSON_RLGC="..." JSON_MASTER="..."
./run.sh                     # prints the scaling tables (min of 3 runs)
```

Individual runs, e.g.:

```sh
N=8 D=16 MODE=ractor $RUBY_RLGC -W0 binary_trees.rb
N=8 REP=20000 MODE=ractor $RUBY_RLGC $JSON_RLGC -W0 json_pc.rb
N=8 REP=20000 MODE=fork   $RUBY_RLGC $JSON_RLGC -W0 json_pc.rb

# newobj cost per Object.new (pure, GC off), via perf:
CNT=30000000 GC=off perf stat -e cycles,instructions $RUBY_RLGC -W0 newobj.rb
CNT=30000000 BASE=1 perf stat -e cycles,instructions $RUBY_RLGC -W0 newobj.rb

# tail latency of the fine-grained lock:
$RUBY_RLGC -W0 tail_latency.rb      # ~0.8 ms  (before the change: ~55 ms)
```

## Machine used for the recorded numbers

AMD Ryzen 9 5900HX — 8 physical cores, SMT (16 logical), turbo 4.68 GHz,
30 GiB RAM. Numbers are min-of-3; absolute values are machine-specific, the
ratios are the point.
