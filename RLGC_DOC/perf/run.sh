#!/bin/bash
# Driver for the RLGCv2 vs stock-master performance comparison.
# Produces the scaling tables in ../PERF_2026-07-06.md.
#
# Build the two binaries (see README.md), then:
#   RUBY_RLGC=<src>/ruby   RUBY_MASTER=<mbase-build>/ruby \
#   JSON_RLGC="--disable-gems -I ..."  JSON_MASTER="--disable-gems -I ..." \
#   ./run.sh
#
# Each cell = min wall-clock over REPEAT runs (default 3). Env: NS="1 2 4 8".

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${RUBY_RLGC:?set RUBY_RLGC to the rlgc-v2 ruby}"
: "${RUBY_MASTER:?set RUBY_MASTER to the stock-master ruby}"
: "${JSON_RLGC:=}"; : "${JSON_MASTER:=}"
NS="${NS:-1 2 4 8}"; REPEAT="${REPEAT:-3}"

# minrun <bin> <flags> <script> <env assignments...>
minrun() {
  local bin="$1" flags="$2" script="$3"; shift 3
  local m=999 t
  for _ in $(seq "$REPEAT"); do
    t=$(env "$@" timeout -s KILL 120 "$bin" $flags -W0 "$HERE/$script" 2>&1 \
        | grep -vi "were not loaded" | tail -1)
    awk "BEGIN{exit !($t < $m)}" && m="$t"
  done
  echo "$m"
}

# Four rows (rlgc/master x Ractor/process) for one JSON/BT scaling benchmark.
scaling() { # <title> <script> <extra env, e.g. "REP=8000">
  echo "## $1"
  printf "%-24s"; for n in $NS; do printf "%9s" "N=$n"; done; echo
  #        name                bin            flags          mode
  for row in "RLGC   Ractor|$RUBY_RLGC|$JSON_RLGC|ractor" \
             "RLGC   process|$RUBY_RLGC|$JSON_RLGC|fork" \
             "master Ractor|$RUBY_MASTER|$JSON_MASTER|ractor" \
             "master process|$RUBY_MASTER|$JSON_MASTER|fork"; do
    IFS='|' read -r name bin flags mode <<<"$row"
    printf "%-24s" "$name"
    for n in $NS; do
      printf "%9s" "$(minrun "$bin" "$flags" "$2" N="$n" MODE="$mode" $3)"
    done
    echo
  done
  echo
}

echo "machine: $(nproc) logical CPUs; REPEAT=$REPEAT"; echo
scaling "binary-trees (D=16, GC-heavy)"        binary_trees.rb "D=16"
scaling "JSON parse (embarrassingly parallel)" json_parse.rb   "REP=8000"
scaling "JSON producer/consumer (move vs IPC)" json_pc.rb      "REP=20000 RECS=50"

echo "## pure-CPU hardware ceiling (no alloc/GC)"
printf "%-24s" "pure_cpu"
for n in $NS; do printf "%9s" "$(minrun "$RUBY_RLGC" "" pure_cpu.rb N="$n")"; done; echo
