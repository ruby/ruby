# RLGCv2 — 10h 検証 campaign 所見と改修予想 (2026-06-15)

検証対象 = HEAD(コミット済み thgroup + clone 修正、move/rec は stash で除外)。
plain/ASAN/mega/btest/test-all = 実クラッシュ 0(test-all は test/ruby を verify 下で
~160 周、毎回 10770 tests / 0 failures)。以下は TSan が拾った **pre-existing な
M1b lock-free 並行面**の分類と改修予想。**2 修正のロジックは全 race の racing access に
一度も現れない**(clone は割り当て provenance に出るのみ)。

凡例: 重大度 = [REAL UB] 実害は薄いが未定義動作 / [BENIGN] 設計上無害 / [REAL?] 要オーナー確認。

---

## A. 修正済み・コミット済み
- `e344d556b` thgroup: Ractor の Thread が belongings 全体を root(`rb_thread_mark_owned_roots`)。
- `7c507438b` clone(freeze:): freeze_*_hash を register→CAS publish で race-free 化。

---

## B. IC(inline constant cache)族 — 約 470 report — [REAL UB], effect は概ね benign
`rb_vm_opt_getconstant_path` / `vm_ic_hit_p` / `vm_ic_update`。2 つの競合面:

1. **`ic->entry` ポインタの publish/load**: writer `RB_OBJ_WRITE(iseq,&ic->entry,ice)`
   (vm_ic_update:6555 → rb_obj_write gc.h:672) vs reader `ice = ic->entry`
   (getconstant_path:6566)。ポインタ語の非同期 load/store。
2. **entry スロットの read-after-reuse**: reader `ice->flags/ice->value`(vm_ic_hit_p:6528)
   vs writer `newobj_init` が**同一スロットを新オブジェクトとして初期化**。
   = reader の `ice` が解放→再利用されたスロットを指す = freed GC スロット read。

**重要な含意**: TSan が報告した = 2 アクセス間に STW barrier が無い(= happens-before 無し)。
shareable な IC entry は「global GC(STW)でのみ解放」のはずで、その間 reader は安全点で停止し
保守スキャンで entry が pin される想定。**それでも reuse が起きている**= entry の生存保証に穴が
ある(reader が保持中の entry が STW 非経由で解放/再利用される経路)。effect は薄い(再利用
スロットは hit 判定 false → cache miss → 再計算、誤定数値にはなりにくい)が UB。**ASAN 不可視**
(GC スロットは freelist 復帰で poison されない)。

**改修予想**:
- load を `RUBY_ATOMIC_VALUE_LOAD(ic->entry)` に(publish は既に RB_OBJ_WRITE)。
- 生存: (a) load 後の再検証 — `vm_ic_hit_p` 内/後で `IMEMO_TYPE_P(ice, imemo_constcache)` を
  再確認し、不一致なら miss 扱い(reuse を検出して捨てる、低コスト・hot path 安全)。
  (b) entry の解放を真に global STW のみへ限定できているか、free 経路を点検(根治)。
- 効率/リスク: hot path。まず (a) の防御的再検証で UB を無害化、(b) は機構解明後。
- 効果: 約 470 report の大半を解消。**唯一 effect が UB なので潰す価値が最も高い族**。

---

## C. Ractor 終了時の objspace 併合(absorb) — absorb:8202 vs gc_mark:5151 — 約 95 report — [REAL?]
`rlgc_objspace_absorb` が heap_page 構造(2648B)の `page->objspace` 等を書き換える(main が
mutex M0 保持)一方、別 Ractor の `gc_mark`(default.c:5151 の containment 判定
`GET_HEAP_OBJSPACE(obj) != objspace`)が同じフィールドを lock 無しで読む。

**判定**: 併合は §2.3「join した者がその場で併合」。書き側は **mutex 止まりで full barrier では
ない**ように見え、その間に他 Ractor の local GC が page 所有を読む。読む値が併合前/後で
containment 判定が変わる → 該当 object の mark をスキップ(早期回収)or 異 objspace bitmap 書き
の可能性。**設計が absorb を STW 想定なら、それが効いていない実バグ。**

**改修予想**:
- `objspace_absorb` を global STW barrier 下で実行(全 Ractor 停止、§2.3 の意図通り)。
- または `page->objspace` を atomic 化 + 「どちらの値でも安全」を保証(併合中の object は
  どちらの objspace から見ても leaf なら可)。
- リスク: 終了/join 経路。要オーナー確認(設計意図 = STW か否か)。

---

## D. fstring / concurrent_set の cross-objspace bitmap 読み — 約 250 report — [REAL UB] だが pin で実害なし
`rb_concurrent_set_find` → `rb_gc_impl_garbage_object_p`(default.c:1986) が**他 Ractor 所有
ページ**の `flags.before_sweep`(gc_sweep_start_heap:4338 が書く)+ mark bit(RVALUE_MARKED:1605)
を読む。関連: gc_sweep_page(11)/gc_pin:5191(7)/RVALUE_REMEMBERED(1)。

**判定**: fstring 表エントリは born-shareable で pin、実際には解放されない → racy bit は
「not garbage」の判定を変えない。**effect は benign**、ただし freed/sweeping 中ページの
flags を cross-objspace で読むのは UB。

**改修予想(最もきれいな実改善)**:
- `rb_concurrent_set_find` の garbage チェックを **shareable/pin 済みエントリでは短絡**
  (shareable は定義上 live → `garbage_object_p` を呼ばない)。cross-objspace bitmap 読みが
  消える。低リスク・低工数で約 250 report を解消。
- 効率/リスク: 低。fstring/sym 表に限定。

---

## E. call cache 派生 — vm_cc_bf_set vs vm_call_single_noarg_leaf_builtin — 25 report — [BENIGN]
`vm_cc_bf_set`(cc の builtin 関数ポインタ書き)vs 別 Ractor の builtin 呼び read。
suppressions 既載 `race:vm_cc_call_set` と**同族**(同じ cme に同じ値を書く・old/new 両 valid・
生存は born-shareable pin)。

**改修予想**: `race:vm_cc_bf_set` を tsan_suppressions.txt に追記。trivial。

---

## F. postponed_job_queue — flush:1984(非 atomic read)vs preregister(atomic exchange) — 約 13 — [BENIGN, atomic 不整合]
新 objspace 初期化(Ractor 生成)で `rb_postponed_job_preregister` が atomic 書き、稼働中
Ractor の `rb_postponed_job_flush` が同 global を非 atomic read。

**改修予想**: flush 側の当該 read を `RUBY_ATOMIC_*_LOAD` に(writer は既に atomic)。
または preregister を boot 時に全枠確保。低工数。

---

## G. keyword_ids 遅延 ID 初期化 — rb_get_freeze_opt:460 — 7 — [BENIGN, 冪等]
`static ID keyword_ids[1]; if(!keyword_ids[0]) CONST_ID(...,"freeze");`。並列 Ractor が同じ
intern ID を書くので冪等・無害。Ruby C 全域に多数ある idiom。

**改修予想**: suppress(family)or 起動時 eager `CONST_ID`。trivial。clone 修正(freeze_hash)
とは別 static(freeze 引数パース側)で無関係。

---

## H. TSan 以外の未決(handoff 由来、campaign 非検出)
- **move/rec(現 stash)**: campaign 対象外。戻して独自検証パス(send/move の deep graph)を
  通してから commit(#18)。
- **C-1 send-copy remember 漏れ**: shape_edges では誤帰属(真因=thgroup)と判明し棚卸し済。
  別個に実在するかは **deep generic-ivar グラフの send-copy 専用オラクル**で確認推奨
  (現オラクル群は send-copy を強く叩いていない)。
- **generic_fields per-objspace 分割**: 現状 global 表 + lock(§2.4-2 未達)。性能/競合面。
- **compaction global-STW 化** / **N=1 税(~11%)**: ロードマップ。

---

## I. 推奨着手順(リスク低→高、効果大優先)
1. **D**(shareable 短絡): 低リスク・約250 report 解消・実 UB 除去。
2. **E, G**(suppress 追記): trivial。
3. **F**(flush の atomic load): 低工数。
4. **C**(absorb の STW 化): 設計意図確認の上。
5. **B**(IC): hot path。まず防御的再検証(B-a)で UB 無害化、機構根治(B-b)は別途。

---

## 実施結果 (2026-06-15) — 6 コミット、v2 スイート TSan クリーン化

| 項目 | 対応 | コミット |
|---|---|---|
| (既) thgroup mark 漏れ | fix | e344d556b |
| (既) clone(freeze:) race | fix | 7c507438b |
| **D** fstring/concurrent_set cross-objspace bitmap | **fix**(containment: foreign は非garbage) | a20f6607d |
| **F** postponed_job atomic 不整合 | **fix**(reader を atomic load) | 599f11ac1 |
| **G** keyword_ids 遅延ID | **fix**(idFreeze 直接使用) | d341d5c3f |
| **B** 定数IC | **benign 確定→suppress**(born-shareable+STW バリア同期、TSan 不可視の happens-before) | 58ff16e00 |
| **C** absorb | **benign 確定→suppress**(marker≠src,dst→foreign 判定不変) | 58ff16e00 |
| **E** call cache (bf_set) | **benign→suppress**(vm_cc_call_set sibling) | 58ff16e00 |

検証: D/F/G 各々 ASAN 0 + btest + suite green、当該 race 族の消滅を TSan で確認。
最終: **8R×10oracle×stress で未抑制 TSan race = 0**、btest 2049、ASAN 0、v2 suite 10/10。

B の当初「real UB」評価は撤回(born-shareable + global GC バリアが reader を待つので freed read は
起きない。詳細はメモリ rlgc-v2-tsan-ic-uaf)。

### 未対応(別タスク)
- **move/rec**(handoff #18): working tree に復元済み、独自検証後コミット。
- **C-1 send-copy**: shape_edges では誤帰属と判明。実在確認は deep generic-ivar send オラクル推奨。
- generic_fields per-objspace 分割 / compaction global-STW / N=1 税: ロードマップ。

## 2026-06-16 OPEN: move-courier SEGV, TSan+stress only

`v2_move_rehome.rb:70` / `v2_move_churn.rb:21` SEGV (`memcpy(dest=NULL,
src=<stack 0x7fff...>, size≈-1)`) while the receiver walks a just-received
moved graph -- `m` is a corrupt/freed Array.

Characterisation:
- MOVE-ONLY: ~12 instances across rehome/churn/edge; ZERO on any copy oracle.
  So it is in the off-heap move path, not a general RLGCv2 race.
- TSan+stress ONLY: never on plain (~45k runs) nor ASAN (clean). Timing race.
- Invisible to both sanitizers as a memory error: a freed GC slot returns to
  the freelist (not malloc-freed), so neither TSan (no data-race report with
  suppressions) nor ASAN (no poison) flags it. It surfaces only as a downstream
  SEGV when the reused slot holds incompatible data.
- A graph node is collected though logically reachable -> a GC-lifetime bug.

Tried, did NOT fix: RB_GC_GUARD(result) in ractor_basket_value to root the
materialized graph across ractor_move_courier_free/reset_belonging (the result
otherwise lived only in the malloc'd basket's p.v). Kept as a defensive
improvement; the SEGV persists -> root cause is elsewhere (build/materialize,
or a containment edge, or a pre-existing GC race the move pattern triggers).

Localization blocked: Ruby's [BUG] C-backtrace is truncated under TSan; cores
go to apport (no sudo to redirect core_pattern); gdb perturbs the timing race
away; an LD_PRELOAD sigaction shim disabled TSan's own handler too.

Next ideas: a dedicated debug build that (a) keeps a C backtrace under TSan, or
(b) asserts graph integrity at receive-return vs walk-time to bisect the
window; or instrument newobj/sweep to log when a known in-flight node's slot is
freed.

---

## 2026-06-16 (session 2): move-courier SEGV characterised further

Non-TSan campaign verdict = CLEAN. The 401 "fails" on the move arm and 306 on
the nosend arm were ALL ec=126 (text-file-busy): the soaks exec the in-tree
./ruby while a rebuild relinks it. Zero real crashes across ~24k move runs, ~3.9k
nosend runs, ASAN 0/862, plain 0, test-all 0 failures. (Campaign hygiene: snapshot
the binary per arm, or pause arms during rebuild, to stop polluting crash logs.)

The SEGV is RELIABLE under TSan -- it fires in 1-2 oracle runs, not "rare".
The earlier "rare" reading was plain builds only; TSan widens the window enough
that it is essentially per-run. So iteration is fast.

Why the C backtrace is always truncated: Ruby's [BUG] reporter RE-FAULTS while
unwinding -- stderr shows
  rehome.rb:70: [BUG] Segmentation fault at 0x0
  SEGV received in SEGV handler
  ABRT received in SEGV handler
i.e. the unwinder touches corrupt/freed state and segfaults again. RUBY_ON_BUG
(gdb attach on crash, ptrace_scope=0 confirmed) also fails: "ptrace: No such
process" -- the process dies in the recursive fault before gdb attaches. The
working capture is to run the oracle UNDER gdb so gdb stops at the FIRST SIGSEGV
at the faulting instruction (in progress).

Ruled OUT this session: write-barrier bypass in materialize. Every reference
store materialize makes goes through the WB --
  rb_ary_push / rb_hash_aset / rb_ivar_set : WB ok
  RSTRUCT_SET -> rb_struct_aset            : WB ok
  rb_match_move_load                       : RB_OBJ_WRITE (str, regexp) ok
The rehome:70 crash is a pure nested-array+string graph (all MOVE_K_ARRAY /
MOVE_K_STRING nodes, no per-type oddity), and the lost child is RANDOM -> points
to a marking-COVERAGE race in the move window (global GC vs the receiver's local
GC / stack-scan of `shells`+`result`), not a per-node structural bug. design_v2
line 722 requires every materialize store to pass the receiver WB (satisfied);
lines 780-785 record the OLD design's identical symptom ("young children freed,
re-mark rule mismatch").

HARNESS NOTE: each Bash tool call runs in its own PID namespace (PID 1 = the
wrapper); backgrounded jobs die when the call returns. Use the Bash tool's
run_in_background for anything long-lived. The autonomous campaign runs outside
these namespaces (cron/user session) -- readable via status files, not signalable
from a tool call.

### RESOLVED 2026-06-16: the "move SEGV / #18 blocker" is a libtsan-internal crash

Ran the move oracle UNDER gdb (ptrace_scope=0) so gdb stops at the FIRST SIGSEGV
before Ruby's (re-faulting) bug reporter. Captured 3 crashes -- ALL fault inside
ThreadSanitizer's own runtime, two distinct co-occurring signatures:

  (A) #0 __sanitizer_internal_memcpy   movups %xmm0,(%rax,%rdi,1) rax=0,rdi=0 -> memcpy into NULL
      #1 __tsan::VarSizeStackTrace::Init
      #2 __tsan::ReportRace
      #3 vm_search_method_slowpath0  vm_insnhelper.c:2255  (cd->cc = cc)
         / vm_lookup_cc             vm_insnhelper.c:2149  (ccs->len)
      si_addr = 0x0. libtsan's trace reconstruction allocates a NULL buffer and
      memcpys into it while building a race report -- under many Ractors reporting
      concurrently (several threads simultaneously inside __tsan::ReportRace).

  (B) #0 __tsan_func_entry           (per-call shadow-stack push)
      #1 rb_current_ec_noinline  vm.c:688  <- ractor_unlock_self <- ractor_wait
      si_addr ~ 0x7fffdb57fff8 (8 bytes below a page boundary = shadow-stack edge);
      another thread in __tsan::DD::GetReport (deadlock detector). libtsan's own
      shadow-stack / bookkeeping faulting.

The race in (A) is the benign lock-free inline method/call cache (cd->cc), ALREADY
in tsan_suppressions.txt (race:vm_search_method_slowpath0 / _fastpath /
rb_iseq_mark_and_move). A runtime suppression CANNOT prevent this crash: libtsan
builds the report's stack traces BEFORE checking suppressions, and dies during the
build.

This is NOT a Ruby / RLGCv2 / move-courier bug:
 - the move-courier graph is valid (the materialize-end integrity check never
   fired across many crashing runs);
 - ASAN build clean 0/862, plain build clean ~45k runs -- the SAME Ruby code is
   memory-safe; the crash exists ONLY when libtsan is linked;
 - every fault is inside libtsan's own internal memory (its NULL trace buffer, its
   shadow stack) -- addresses Ruby never writes; a wild Ruby write there would show
   under ASAN, which is clean.
 - toolchain is STABLE clang 18.1.3 / compiler-rt (not experimental) -- so this is
   a genuine libtsan capacity/robustness limit under the RLGCv2 multi-Ractor
   workload (8 Ractors, rapid create/destroy, heavy shared-ISeq dispatch + GC
   stress), not a flaky build.

Mitigation tried: added RLGC_DOC/tsan_ignorelist.txt and rebuilt vm.o (where
vm_insnhelper.c is #included) with -fsanitize-ignorelist=... to EXCLUDE the benign
IC accessors from instrumentation (no shadow access recorded -> no report built ->
reporter (A) never runs). This removed signature (A), but signature (B)
(__tsan_func_entry / shadow stack) still fires at a similar rate -> libtsan remains
unstable on these heavy oracles regardless.

RECOMMENDATION (for the GC author to decide):
 - Treat the move/churn/rehome oracles as covered by ASAN + plain (both clean) and
   the courier as DONE. Reserve TSan for LIGHTER oracles (fewer Ractors / less
   dispatch volume) where libtsan stays stable and its race-detection is trustworthy.
 - Keep or drop the ignorelist (it cleans up signature (A) noise on a known-benign
   race; it slightly narrows IC-function coverage, all already classified benign).
 - Optional: try a newer compiler-rt, lower history_size, or fewer concurrent
   Ractors in the heavy oracles, to see if libtsan's internal crashes abate.

### CONFIRMED FIX 2026-06-17: coroutine TSan-fiber annotations eliminate the SEGV

Root cause of (B)/(C) confirmed by the minimal fix working: Ruby's coroutine
context switches (Context_swap via coroutine_transfer, co_start) are not annotated
for TSan, so libtsan's per-OS-thread shadow stack / trace / stack depot leak across
switches and overflow -> internal crash. Added (minimal, MN scheduler only):
  coroutine/amd64/Context.h : COROUTINE_SANITIZE_THREAD guard + void *tsan_fiber;
      coroutine_initialize -> __tsan_create_fiber; _main -> __tsan_get_current_fiber;
      coroutine_destroy -> __tsan_destroy_fiber.
  thread_pthread.c coroutine_transfer0 : __tsan_switch_to_fiber(transfer_to->tsan_fiber,0)
      before coroutine_transfer (the single switch chokepoint).
  Makefile cflags : -fsanitize-ignorelist=.../tsan_ignorelist.txt made permanent.

Result on the move oracles under TSan+GC_STRESS:
  before any fix      : SEGV in 1-2 runs
  ignorelist only     : still SEGV run 1 (signature B)
  fiber + ignorelist  : crash 0/40, MOVE_CHURN_OK / MOVE_REHOME_OK printed.
=> (B)/(C) were the coroutine-annotation gap. NOT a Ruby/RLGC/courier bug.

Cascade (each fix unmasks the next, all now that libtsan is stable):
 1. "unlock of an unlocked mutex (or by a wrong thread)" at thread_sched_unlock_
    <- co_start. The M:N scheduler HANDS OFF sched->lock_ across a coroutine switch
    (lock before transfer, unlock in the resumed co_start). Same OS thread, valid
    POSIX, but once fibers are annotated TSan sees lock-on-fiber-A / unlock-on-fiber-B.
    Suppressed: mutex:thread_sched_unlock_ / mutex:thread_sched_lock_.
 2. After that suppression: data races in the scheduler (thread_sched_set_running:692
    write, thread_sched_wait_running_turn:845 read on sched->running). BOTH sides hold
    M1 = sched->lock_ -> they ARE mutually excluded; the report is a FALSE POSITIVE.
    Cause: the wrong-fiber unlock of sched->lock_ corrupts TSan's happens-before model
    of that mutex, so all sched->lock_-protected state then looks racy. The lock-handoff
    idiom is fundamentally at odds with TSan's "unlock by the locking thread" model once
    fibers are visible.

KEY: thread_pthread.c / thread_pthread_mn.c / coroutine/ are NOT modified by RLGC
(branch diff vs merge-base touches only cont.c + thread.c). The lock-handoff and the
racing scheduler state are pure UPSTREAM M:N scheduler code; origin/master HEAD ==
rlgc-v2 merge-base (26f09eb6a). Upstream-vs-RLGC empirical split: building stock
master+TSan and running a generic 8-Ractor send/receive+GC test (no move:) — in
progress.

### UPSTREAM-CONFIRMED 2026-06-17: the crash is stock Ruby+TSan, not RLGC

Built clean upstream master (origin/master == rlgc-v2 merge-base 26f09eb6a) with
TSan (clang-18, -fsanitize=thread -O1 -g), NO RLGC, NO fiber annotation. Ran a
generic 8-Ractor send/receive + GC.start test (/tmp/claude/generic_ractor.rb,
public Ractor API only, no move:). Result over 8 runs:
    crash=3  hang=5  clean=0
    CRASH: [BUG] Segmentation fault at 0x0            (signature A, libtsan ReportRace)
    CRASH: [BUG] Segmentation fault at 0x7fffdbb00000 (signature C, libtsan StackDepot)
    HANG x5 (TSan deadlock / swallowed SIGTERM)
=> stock upstream Ruby + TSan cannot run a multi-Ractor workload: same crash
   signatures, zero RLGC code involved. The #18 "move SEGV" is an UPSTREAM
   Ruby x ThreadSanitizer integration bug (coroutine switches unannotated for
   TSan). RLGC / the move courier are entirely innocent; the move oracles were
   merely the workload that exercised the upstream M:N coroutine scheduler.

### STAGE 2 UPSTREAM 2026-06-17: fix works on upstream; handoff races are upstream too

Upstream master + TSan + the full fix (fiber annotation in coroutine/amd64/Context.h
& thread_pthread.c + -fsanitize-ignorelist for the IC family). Generic 8-Ractor test,
no suppressions, 8 runs:
    crash=0  hang=0  all GENERIC_RACTOR_OK
Distinct TSan reports remaining are ALL upstream:
  - sched->lock_ handoff false-races: thread_sched_set_running:692,
    thread_sched_wakeup_running_thread:775, thread_sched_to_ready_common:810,
    rb_ractor_sched_wakeup:1443  (identical to what RLGC showed -> upstream).
  - already-classified-benign VM races: gccct_method_search, vm_search_method_fastpath,
    vm_ic_hit_p, rb_vm_opt_getconstant_path, vm_lock_enter, rb_ec_vm_lock_rec, rb_obj_write.

CONCLUSION: the entire "#18 move SEGV" phenomenon is upstream Ruby x ThreadSanitizer:
  (1) crash = coroutine switches unannotated for TSan -> reproduces on stock master;
  (2) fix = the TSan fiber annotation -> works on stock master (crash 0);
  (3) residual handoff false-races = upstream M:N scheduler lock-handoff vs TSan's
      fiber-aware mutex model.
RLGC and the move courier are fully exonerated. The fiber annotation is an
upstream-valuable contribution (makes TSan usable for any multi-Ractor testing).
Reproduction artifacts: /tmp/claude/wt-up (clean upstream 26f09eb6a),
/tmp/claude/build-up-tsan, /tmp/claude/generic_ractor.rb, stage1.sh, stage2.sh.

### RLGC BUG-FINDING 2026-06-17 (TSan now stable)

With the coroutine fiber annotation + IC ignorelist + handoff suppression in
place, TSan finally runs the RLGC oracles without crashing in libtsan, so it can
report RLGC's own races. Findings:

1. REAL RLGC BUG (fixed -- commit "lock the recv_queue against senders ..."):
   ractor_queue_mark vs ractor_queue_enq. ractor_sync_mark walked a Ractor's
   recv_queue in the r==cr case (own concurrent local GC) without the sync lock,
   while foreign senders append to it under that lock. Marker could follow a
   half-linked ccan node -> miss/UAF an in-flight basket. Fixed by taking
   RACTOR_LOCK around the recv_queue+ports walk in the r==cr non-global-GC case
   (deadlock-free: holding a ractor lock disables malloc-GC, so the marker never
   already holds it).

2. NOT RLGC -- TSan tooling: v2_incremental_vs_multi_objspace "hangs" under TSan
   because libtsan's deadlock detector caps simultaneously-held locks at 64
   (sanitizer_deadlock_detector.h:67 CHECK n_all_locks_ < 64) and RLGCv2 holds
   more (per-objspace/per-Ractor locks). Run TSan with detect_deadlocks=0:
   then it completes clean (INC_VS_MULTI_OK, 0 unsuppressed races).

3. NOT RLGC -- my own fiber annotation gap (fixed, folded into the coroutine
   commit): coroutine_destroy must not __tsan_destroy_fiber a borrowed
   __tsan_get_current_fiber() handle (the OS thread's implicit fiber, used by
   Ruby Fibers' root context via coroutine_initialize_main). Destroying it aborts
   libtsan (FiberDestroy->ProcWire CHECK). Added tsan_fiber_owned: only destroy
   handles we created.

STANDING TSAN RECIPE for the RLGC oracles (multi-Ractor):
  TSAN_OPTIONS="suppressions=RLGC_DOC/tsan_suppressions.txt history_size=7 \
                report_signal_unsafe=0 detect_deadlocks=0"
  build with cflags ... -fsanitize-ignorelist=RLGC_DOC/tsan_ignorelist.txt
  (plus the coroutine fiber annotation, now in the base "coroutine: annotate
  fiber context switches for ThreadSanitizer" commit).

### RLGC BUG #2 (open, characterised): orphan-merge teardown UAF (M1b-specific)

v2_orphan_merge_pjob, found by the now-stable TSan. Two races, one root cause:
  - main: ractor_free (gc.c rb_data_free) frees the ractor incl. its sched lock
    M2 (r->threads.sched.lock_); also rb_threadptr_sched_free / thread_free.
  - nt (T2/T3): co_start native_thread_assign(NULL,th) / nt_start
    thread_sched_unlock_ -- the dying thread's final teardown, which UNLOCKS the
    handed-off sched lock M2 AFTER co_start set th->sched.finished = true.
The zombie ledger (rb_thread_sched_mark_zombies) keeps the thread (and via
th->ractor, the ractor) marked until sched.finished; once it flips, the thread
+ ractor become collectable. But sched.finished is set in co_start BEFORE the
terminal coroutine_transfer0 that HANDS OFF M2 (still locked) to nt_context, and
the nt unlocks M2 only after. So between finished=true and the nt's unlock, a
concurrent collector frees M2 -> unlock-after-free.

UPSTREAM SPLIT: stock master + TSan + unjoined-ractor churn = 0/15 hits.
Upstream GC is STW, so the dying ractor's nt is stopped at a safepoint during
the GC that frees it -- no concurrent free. M1b (barrier-free local GC) removed
that barrier, so main's concurrent GC races the nt teardown. The teardown code
(co_start, the handoff, sched.finished) is upstream-unmodified; M1b is what
exposes the premature signal. => fix on the RLGC side: the signal that gates the
concurrent free must reflect the nt's LAST release of the ractor's resources,
not be set before the handed-off unlock.

### RLGC BUG #2 fix (2026-06-17): teardown UAF -- dominant case fixed (dying_th)

Fixed via commit "publish a terminating thread's 'finished' after its nt's last
sched-lock release": co_start records the dying thread in sched->dying_th before
the terminal handoff; thread_sched_unlock_ publishes th->sched.finished only
after releasing the handed-off lock. The zombie ledger then frees the
thread/Ractor strictly after every teardown write. No new lock (a free-path lock
risks inverting with the scheduler's sched-lock->VM-lock order -> deadlock), so
the fix is lock-free.

Verified under TSan (orphan/churn/rehome/nosend x stress x tiny, dozens of runs):
the dominant teardown races are gone -- ractor_free vs the nt's M2 unlock, and
rb_threadptr_sched_free vs native_thread_assign are now correctly ordered (no
concurrent access). crash=0, hang=0. Plain orphan_merge 6/6 (no zombie leak).

Residual TSan reports are coroutine-handoff blind spots, now classified benign in
tsan_suppressions.txt (the sched lock is handed off across the coroutine switch,
so TSan sees no happens-before for it even though the accesses are really
mutually excluded / correctly ordered): race:thread_sched_unlock_ (the dying_th
field), the sched-handoff family (thread_sched_set_running etc., confirmed on
stock upstream), and race:rb_threadptr_sched_free / race:native_thread_assign
(ordered by dying_th, but the handoff hides the HB).

REMAINING (rare, ~1/24): ractor_free vs co_start:478 thread_sched_lock, from the
oracle's "never-started Ractor" section -- a Ractor whose creation failed is
freed by a SINGLE-WORLD local GC (not the global barrier) while its thread is
entering co_start and locking the sched lock. This is a distinct, narrower window
(local-GC free vs co_start lock-acquire) not covered by the dying_th signal;
needs separate handling (e.g. the local-GC free of a never-started Ractor must
also wait out / order against its nt's co_start). Left open and documented.

### RLGC BUG #3 fixed + verify-as-oracle findings (2026-06-17)

Interleaving GC.verify_internal_consistency on every Ractor#send receive (and
across compaction / shareable / lifecycle stress) is a strong oracle for
concurrent RLGC heap corruption. Findings:

REAL, FIXED (commit "dedup before enter_func in obj_traverse_replace_i"):
  Copy-path containment violation. obj_traverse_replace_i ran enter_func (the
  shallow copy) BEFORE the dedup st_lookup, so revisiting a shared/cyclic node
  allocated a throwaway copy whose children still point at the source -- a live
  cross-objspace-edged object until swept (containment violation). Minimal repro:
  send([a, a]). Fix: dedup first. Verified: make_shareable DAG/cycle + test_ractor
  green.

BENIGN (verify stricter than the design's liveness):
  cc_table generational WB miss "WB miss (O->Y) VM/cc_table -> T_IMEMO" (and
  T_CLASS/T_ICLASS -> cc/cme), under concurrent multi-Ractor dispatch + send. The
  cc/cme are kept alive by the born-shareable pin (per the inline-cache
  suppressions), not the remember set, so the missing O->Y entry causes no UAF:
  no-verify + RUBY_GC_STRESS=1 (forces minor GCs) = 6/6 clean, and a full mark
  before verify reconciles it (5/5). verify_internal_consistency's generational
  WB check does not model the pin. Pre-existing.

METHOD NOTE: don't blanket GC.start(full) before verify -- it reconciles BOTH the
benign cc-WB miss AND real transient corruption (the copy garbage above cleared
under a full GC too). Verify without a preceding full GC, then triage: real
containment/T_NONE corruption is fixable; cc-WB misses are the benign pin family.

### ASAN sweep clean 2026-06-17

Rebuilt ASAN on the current tree (all fixes) and swept move/copy/compact/
lifecycle/shareable/fiber + the existing oracles x {stress, stress-tiny} x2,
GC-stressed: 88 runs, ZERO AddressSanitizer errors (no heap-use-after-free,
heap-buffer-overflow, or stack-use-after-return). The only aborts were the
benign cc-WB verify family on the verify-on-receive oracles. The move courier's
xmalloc buffers, the copy/move re-home, the recv_queue + teardown fixes are
memory-clean under ASAN.

CONVERGENCE: across TSan (stabilized) + GC.verify_internal_consistency + ASAN,
over move / copy / compact / shareable / fiber / lifecycle / finalizer /
exception / ports / deep-DAG patterns under GC stress, the real RLGC bugs found
were the three fixed this session (recv_queue race, teardown UAF, copy
containment). Remaining reports are benign (cc-WB pin family, coroutine-handoff
false positives) or the open rare never-started-Ractor teardown edge.

### never-started edge resolved + upstream exception/longjmp TSan limit (2026-06-17)

The "never-started Ractor" residual splits into two non-RLGC items, both closed:
 1. ractor_free vs co_start thread_sched_lock_ (the local-GC free of a
    failed-creation Ractor vs its nt's sched-lock acquire) -- benign coroutine
    handoff false positive (ASAN over GC-stress failed-creation churn = no UAF;
    dying_th orders the free after teardown). Suppressed (race:thread_sched_lock_).
 2. The TSan SEGV on heavy failed-creation churn is NOT a teardown bug at all:
    it is libtsan's shadow stack overflowing because Ruby exceptions longjmp past
    __tsan_func_exit, leaking shadow-stack frames per raise. CONFIRMED on stock
    upstream master + TSan: pure raise/rescue x200k (no Ractors, no GC) crashes in
    __tsan_func_entry identically on upstream and rlgc-v2 (ec=139). An upstream
    Ruby x TSan integration limit (Ruby's setjmp/longjmp not resetting TSan's
    shadow stack); real fix is to route rb_longjmp through TSan's interceptor or
    annotate it. Affects only exception-storm oracles under TSan; not RLGC.

FINAL STATE: 3 real RLGC concurrency bugs found and fixed this session
(recv_queue mark-vs-enqueue race, terminating-thread teardown UAF, copy-traversal
containment). #18 "move SEGV" resolved as the upstream coroutine-not-annotated
TSan crash (fixed by the fiber annotation). All other reports across TSan +
verify + ASAN over move/copy/compact/shareable/fiber/lifecycle/finalizer/
exception/ports/select/deep/types/callable/zombie patterns are benign (cc-WB pin
family, coroutine-handoff false positives, lazy-static IDs) or upstream tooling
limits (exception/longjmp shadow stack). ASAN: 0 memory errors.
