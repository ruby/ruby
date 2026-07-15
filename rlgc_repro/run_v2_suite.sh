#!/bin/bash
# RLGCv2 oracle suite runner (CI building block).
#
#   rlgc_repro/run_v2_suite.sh [RUBY] [mode]
#
#   RUBY  : ruby binary to test (default: ./ruby next to this repo's root)
#   mode  : plain | stress | tiny | stress-tiny   (default: plain)
#
# Exit status: number of failing oracles (0 = green).
# Sanitizer runs: build with ASAN/TSan and pass that binary as RUBY;
# for TSan also export
#   TSAN_OPTIONS="suppressions=$srcdir/RLGC_DOC/tsan_suppressions.txt"
# (any unsuppressed report fails the oracle via the default exit code).
set -u

srcdir=$(cd "$(dirname "$0")/.." && pwd)
RUBY=${1:-$srcdir/ruby}
mode=${2:-plain}

declare -a env_prefix=()
case "$mode" in
  plain) ;;
  stress)      env_prefix=(RUBY_GC_STRESS=1) ;;
  tiny)        env_prefix=(RUBY_GC_HEAP_INIT_SLOTS=2000) ;;
  stress-tiny) env_prefix=(RUBY_GC_STRESS=1 RUBY_GC_HEAP_INIT_SLOTS=2000) ;;
  *) echo "unknown mode: $mode" >&2; exit 99 ;;
esac

declare -A expect=(
  [v2_clone_freeze_lazy_global]=':ok'
  [v2_concurrent_local_gc_mix]='M1B_MIX_OK'
  [v2_fstring_table_resize]='100000100000'
  [v2_incremental_vs_multi_objspace]='INC_VS_MULTI_OK'
  [v2_orphan_merge_pjob]='ORPHAN_MERGE_PJOB_OK'
  [v2_reachable_redirect]='REACHABLE_REDIRECT_OK'
  [v2_shape_edges_dup_unshareable]='M1B_GEN_OK'
  [v2_shutdown_inherit_flush]='OK'
  [v2_verify_consistency]='VERIFY_CONSISTENCY_OK'
  [v2_zombie_pages_trigger]='ZOMBIE_PAGES_TRIGGER_OK'
)

fails=0
for name in $(printf '%s\n' "${!expect[@]}" | sort); do
  script="$srcdir/rlgc_repro/$name.rb"
  out=$(env "${env_prefix[@]}" timeout 1800 "$RUBY" "$script" 2>&1)
  ec=$?
  if [ $ec -eq 0 ] && printf '%s' "$out" | grep -q "${expect[$name]}"; then
    echo "ok   $name"
  else
    fails=$((fails + 1))
    echo "FAIL $name (ec=$ec)"
    printf '%s\n' "$out" | grep -E '\[BUG\]|Segmentation|WARNING: (Thread|Address)Sanitizer|Error' | head -4 | sed 's/^/     /'
  fi
done

echo "---"
echo "v2 suite: $((${#expect[@]} - fails))/${#expect[@]} ok (mode=$mode)"
exit $fails
