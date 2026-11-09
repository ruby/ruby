# ZJIT PR instruction-count comparisons

`../workflows/zjit-callgrind.yml` runs on PRs to master that touch ZJIT,
shared JIT code, or this benchmarking infrastructure. It builds the exact PR
base SHA and head SHA with identical release options (`--enable-zjit
--disable-yjit`), then runs ruby-bench with `--zjit` and its Callgrind harness.
This compares the PR's own changes, not a synthetic merge commit.

The workflow pins ruby/ruby-bench PR #576's tip to
`01e54d3307d4bf4687fbef3538258dad46bccabd`. After that PR merges, update
`RUBY_BENCH_REV` to a reviewed upstream commit containing the harness.

## Measurement

The bounded suite is configured in `BENCHMARKS` in the workflow. ruby-bench
interprets these as name filters (so `getivar` also selects `getivar-module`).
Each process runs 10 uninstrumented warmup iterations followed by one measured
iteration. Callgrind's `Ir` event counts executed native instructions, including
JIT code and C code. `--smc-check=all` handles generated code at reused addresses.

`zjit_callgrind.rb` locates each benchmark's profile via the recorded command
line and reads the first explicit client-request dump (`.1`). It deliberately
ignores the final process-exit dump. Missing, empty, duplicate, or mismatched
results fail the report rather than silently showing a partial comparison.

The percentage is `(PR / base - 1) * 100`; negative means fewer instructions.
It is not a wall-clock speedup. Setup and warmup are excluded, but compilation
and GC occurring during the measured iteration are included. GC, code layout,
and nondeterministic workloads can still cause differences.

## PR comments and permissions

The benchmarking workflow has a read-only token and no secrets. It uploads the
report and raw data as an artifact. A separate `workflow_run` workflow,
`../workflows/zjit-callgrind-comment.yml`, has permission to update PR comments.
It never checks out PR code or executes artifact contents. It derives the PR
number from GitHub's run/commit metadata, rejects closed or stale PR heads,
and updates one marked bot comment instead of creating a comment per push.

The commenting workflow must be merged onto the default branch before GitHub
will dispatch it. Fork PR benchmark jobs may also require the repository's
normal workflow approval. Failed runs retain available raw data but do not
publish a successful comparison comment; an existing comment keeps its explicit
commit SHAs so it cannot be mistaken for a newer result.

## Local validation

```sh
ruby .github/scripts/zjit_callgrind_test.rb --verbose
actionlint .github/workflows/zjit-callgrind.yml .github/workflows/zjit-callgrind-comment.yml
```

A full benchmark smoke test requires Linux, Valgrind, and two installed ZJIT
release builds. Raw profiles are retained in the workflow artifact for 14 days.
