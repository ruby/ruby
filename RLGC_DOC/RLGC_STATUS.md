# Ractor-Local GC (RLGC v1) — 現状サマリ【凍結】

> **これは v1(ブランチ `ractor-local-gc`)の凍結記録**。現行は RLGCv2(ブランチ `rlgc-v2`)で、
> **最新の仕様は `design_v2.md`「現在の到達点」、進捗は `STATUS_v2.md`**。本書は v1 の歴史的資料。

ブランチ `ractor-local-gc`。クラッシュ駆動のバグ修正 + adversarial サーフェシングの到達点。
詳細な経緯は `RACTOR_LOCAL_GC_DESIGN.md`(§6.x)、再現コードは `rlgc_repro/`。

---

## 1. 修正完了:7 クラッシュ面(コミット済・回帰なし)

いずれも「confinement-miss の直接ケース」= **local-sound に修正可能(設計判断不要)**。
検証はすべて btest 2045 / btest_ractor 161 で機能的回帰ゼロ(失敗は partial build の
stdlib `LoadError` = tempfile/tmpdir のみ、修正前後で同一)+ 各機能テスト通過。

| Face | 根本 | 修正 | commit | repro (before→after) |
|------|------|------|--------|------|
| E | `GC.auto_compact=true` が `ruby_enable_autocompact` 経由で RLGC 下の full/global GC を compaction 化 → corruption | `gc_marks_start`/`gc_start` の参照点に `&& !rlgc_has_local`(gc_compact と同型) | `95c551e7b` | 6/6 → 0 |
| F | `define/undefine_finalizer` が呼び出し元 objspace の `finalizer_table` に登録 → `run_final` が所有者の table を見て `rb_bug` | key 所有者の objspace へルーティング(`copy_finalizer` 同型) | `72ad765aa` | 8/8 → 0 |
| D | VM-global `concurrent_set`(fstring表/symbol set/ids)が worker objspace に resize 確保され worker local GC に sweep / symbol id-entry bucket が main の `ids` 経由でしか辿れず sweep | local mark_roots branch で `gc_keepalive_vm_global_if_local` if-local マーク + bucket を `RB_OBJ_SET_SHAREABLE` で pin | `f100f23ba` | dsym 7/30→0, bucket 20/20→0 |
| B | `rb_const_remove` が無ロックで const-entry を二重 free / cache-clear が concurrent insert の rehash と競合 | lookup+削除を `RB_VM_LOCKING` で atomic 化(`const_set` 同型)、raise/warn はロック外へ遅延 | `808e41fd9` | 15/15 → 0 |
| G | Ractor main thread の割り込み `pending_interrupt_queue`/`mask_stack` が親 objspace 確保 → 子の `handle_interrupt` mask hash を confined GC が sweep | `thread_start_func_2`(子 objspace で実行)で re-dup re-home | `f8885699f` | 15/15 → 0 |
| G-2 | 同上の fiber-storage Hash(`ec->storage`、`rb_fiber_inherit_storage` が親確保) | G の re-home ブロックに `ec->storage` re-dup を追加 | `c0e1c99fe` | 12/12 → 0 |
| trap | 非main Ractor の signal-trap String handler が worker objspace 在住、VM-global `vm->trap_list.cmd[]` からしか辿れず sweep → 信号配送で eval freed | local branch で `trap_list.cmd[]` を if-local マーク | `51819fc7b` | 12/12 → 0 |

---

## 2. クラッシュ機構の地図(3 族)

サーフェシング batch 1–10(~88 サブシステム)で、全クラッシュが 3 機構に収束。

### Family I — confinement-miss
オブジェクト X(Ractor R の objspace)が、(a) 親 objspace で確保された per-thread/fiber/ec フィールド、
(b) VM-global root、(c) foreign オブジェクトの ivar、のいずれか経由でしか辿れず、R の confined local GC が
foreign-skip / VM-global mark スキップして X を sweep。
- **直接ケース(C field / 固定配列 / 単一 backing)= 修正済**(G, G-2, trap, D, F)。
- **間接ケース = 設計**: foreign-object-ivar(thread_variable)、VM-global container の散在要素(mark_object_ary, coverages)。

### Family II — cross-objspace subtree liveness
non-global local GC が cross-objspace 参照される subtree を解放 / orphan × compaction / in-flight message の未 pin。**全て設計**(A=shareable Struct/Data deep graph, C=orphan×compact, §3.10=ractor_wait_receive)。

### Family III — generational WB × cross-objspace
confined **minor** GC の per-objspace remembered-set が、copy/cross-objspace 経路で生じた old→young edge を
カバーしない(`gc/default/default.c:5743-5749` が「cross-objspace old→young は意図的に remembered-set 外」と明記)。
**設計**(generic-ivar send-COPY, svar)。

---

## 3. clean / robust(安全境界の確証 = 重要なネガティブ結果)

- **shared_bits write-barrier / 境界 remset = 健全**: 全 WB edge 型(ivar/array/hash/struct field)で
  cross-objspace の unshareable subtree を正しく延命。s→u 書込は必ず u の所有者が行う不変条件が成立。
- **compaction = RLGC 下で完全に無効化**: `GC.compact` / `verify_compaction_references` / `auto_compact`(=Face E)
  の全 entry が `rlgc_has_local` でガード。オブジェクト移動による cross-objspace 参照破壊は起きない。
- robust 確認済: proc/method callable(curry/compose/to_proc/UnboundMethod/define_method)、refinement cc/cme、
  m_tbl/cme/cc churn、singleton class、Ractor-local storage、WeakMap/WeakKeyMap、Encoding::Converter、
  arena/heap-growth race、too_complex ivar、IO buffer、fiber scheduler、TracePoint、Mutex/Queue/CV、
  introspection × 並行 local GC、make_shareable cyclic/isolate-proc、Ractor#value multihop orphan、等。

---

## 4. 残る設計案件(open)

いずれも cross-objspace のオブジェクト寿命・世代別 remembered-set・VM-global table 所有・lock-free 再利用に
属し、1 行修正の範囲外(無理な local 修正は正しさを損なう)。

| 領域 | 内容 | 族 |
|------|------|-----|
| s7 / A | shareable Struct/Data deep-graph mark-T_NONE | II |
| C | orphan 終了 Ractor × `GC.compact` | II |
| ractor_wait_receive | in-flight basket の transient queue が `ractor_sync_mark` 未マーク | II(§3.10) |
| Ractor#value orphan | 返り値 subtree が死んだ producer の orphan objspace | II |
| generic-ivar send-COPY | copy 中 promote した old array が freed young child を walk | III |
| shareable env svar | svar 値が cross-objspace で remembered-set 外 | III |
| thread_variable | locals Hash が foreign th->self の ivar | I-間接 |
| mark_object_ary / coverages | VM-global container の要素が worker objspace に散在(if-local-mark 不可) | I-間接 |
| id2ref lazy-build | object_id-in-shape の lazy `_id2ref` 構築が main objspace のみ走査 | (id2ref) |
| concurrent_set 旧backing | resize の旧 backing を所有者 GC が free、別 objspace の reader が probe 中 | (lock-free 再利用) |
| autoload_features | `autoload_delete`(VM lock)vs `Module#autoload`(autoload_mutex)の異ロック race | (lock 順序) |
| at_exit `end_procs` | VM-global lock-free list を confined GC が未マーク(weak-memory ordering) | I(変種) |

設計の論点(共通根):
- **II/III**: cross-objspace edge を持つ非shareable オブジェクトの寿命を、global-GC 専用 remembered-set 補完 /
  参照時 pin / copy 時の世代リセット、のどれで担保するか。
- **I-間接**: VM-global container/ivar の所有を、worker 登録時 pin(shareable 化)で統一するか。

---

## 5. 成果物

- コード修正: 7 面(上記)。GC 中核 = `gc.c` / `gc/default/default.c`、周辺 = `thread.c` / `variable.c` /
  `string.c` / `symbol.c` / internal headers。
- ドキュメント: `RACTOR_LOCAL_GC_DESIGN.md` §6.9–6.13(face タクソノミー + batch 結果)。
- 再現コード: `rlgc_repro/`(b4–b10、計 ~82 本)。
- メモリ: `rlgc-vm-global-table-faces.md` / `rlgc-thread-mask-stack-foreign.md` ほか。

**到達点**: 設計判断不要で local-sound に直せるクラッシュ面は出し切った(7 面)。残りは RLGC の
中核設計判断(cross-objspace 寿命)に収束しており、次の最大の価値はその設計を詰めること。
