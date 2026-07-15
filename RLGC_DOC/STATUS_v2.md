# RLGCv2 現状サマリ(2026-07-04)

設計の正典は `design_v2.md`(最新仕様サマリは同書冒頭「現在の到達点」)。本書は「いまどこまで出来ていて、何が残っていて、どう検証するか」だけをまとめる。v1 の記録は `RACTOR_LOCAL_GC_DESIGN.md` / `RLGC_STATUS.md`(凍結)。

## 直近(2026-07-04)の変更

- **local GC の shareable を mark-only 化(明示)**: `rlgc_pinned_roots_mark` は shareable に mark bit だけを立て(old objects と同じ)、**辿らない**。shref(shareable-referenced unshareable)のみ root として traverse する。old shareable は `uncollectible→mark_bits` の pre-mark で既 marked なので pinned-roots を短絡。設計(§2.1「shareable は解放せず mark で root 化・辿るのは子=shref」)を実装で徹底した。
- **imemo の dead pin switch 撤去**: ment/callcache/callinfo/constcache/iseq は全て `SHAREABLE_IMEMO_NEW`(born FL_SHAREABLE、決定 17)なので、`rb_imemo_new` 内の「is_shareable=false 時に became_shareable する switch」は到達不能な dead code だった → 削除し `rb_imemo_new` は upstream と逐語一致。「pin だが FL_SHAREABLE 無し」という中間状態は存在しない(**FL_SHAREABLE ⟺ shareable_bits**)。
- **cross-Ractor 列挙の再設計(§2.4 更新)**: `rb_objspace_each_objects_all` を撤去。`rb_objspace_each_objects` が callee で barrier を取り「自 objspace 全 + 他 live Ractor の shareable のみ(1 スロット単位)」を歩く。zombie/creating skip で列挙 SEGV を閉じた。current のみ版 `rb_objspace_each_objects_local` を新設。cross-Ractor 走査は callback が C コードの sweep 系のみ(TracePoint/attr-bf-cc/coverage)。`ObjectSpace.each_object`・dump_all・objspace ext・JIT・method coverage は `_local`(each_object は他 Ractor の shareable をユーザブロックへ yield すると barrier 保持中の safepoint で VM lock 所有が乱れるため cross-Ractor 化せず。cross-Ractor each_object は collect-then-yield が要り未実装)。
- **上流先出し(マージ済)**: `gc: take the VM barrier inside rb_objspace_each_objects` / `iseq: use RB_OBJ_WRITE for the lazy-load loader object` / Ractor 宛て postponed job — いずれも RLGC 非依存として origin/master に merge 済み(rebase で dedup)。

## 現在地

| マイルストーン | 状態 | 主要コミット |
|---|---|---|
| M0 土台(global objspace+page pool / cache 層撤去) | 完了 | 〜M0c |
| M1a per-Ractor objspace+封じ込め(STW 段階) | 完了 | 〜cbc3944d6 |
| M3 message send(受信側実体化・決定 11) | 完了 | d0affd097, 9fbe6af32 |
| M2 global GC(STW 一括・自動起動) | 完了 | d1f504b6e, 981664710 |
| M4 終了と引き継ぎ(value 併合 / orphan / shutdown) | 完了 | 1f8318f1f, b977ac426, 80f227d52 |
| **M1b local GC 並行化(バリア外し)** | **完了** | 2bc3fc1b6〜df4f2e0b3 |
| M5 堅牢化・調整 | 主要部完了 | e3bd4e939〜d2f855dcf |
| origin/master 追従 rebase(b765d9489 = upstream バンプポインタ・アロケータ) | 完了 | 全 36 コミット転写 |
| 決定 18: Ractor 宛て postponed job | 完了 | 独立ブランチ ractor-targeted-pjob 5f537434c(upstream 提案用)+ v2 へ cherry-pick 70cf4b6df |
| incremental marking × 単一→複数遷移の整合(設計 2.1 step 0 の未実装文) | 完了 | 730392475 |
| キュー2: orphan 併合の pjob 化(+ absorb GC 禁止ガード) | 完了 | ae6a8da90 |

すべてのコミットは full gate(`make btest` 2050 + `make test-all` 34892〜34904/0F/0E)を通過してから入れている。

## 性能(merge-base `aa4d4c450` 対照、10M iter 割り当て churn)

| | master | RLGCv2 | 比 |
|---|---|---|---|
| N=1 | 0.97s | 1.08–1.13s | 約 -11%(封じ込め税) |
| N=8 | 4.50s | 1.5–1.6s | **約 2.9 倍速**(実効 ~7.6 コア) |

このマイクロベンチはコードレイアウトで ±3–5% 揺れる。N=8 のスケーリングは自比 ~5.7×。

## ロック模型(M1b 後の最終形)

- worker の local GC: **無ロック**(封じ込め+atomic bitmap)
- main の local GC: **no-barrier VM lock**(VM グローバル root walk の保護)
- global GC: VM lock + barrier(`gc_enter_event_global`)
- **GC の内側では barrier 参加型の VM lock を取らない**(pending barrier に mid-GC で合流=半回収ヒープ露出)。NO_BARRIER の VM lock は機能的には安全(barrier owner は join 待ちの間 mutex を手放す=thread_pthread.c rb_ractor_sched_barrier_start)だが、hot な GC 経路が取ると全 Ractor が global lock に再直列化するので、**頻度で使い分ける**: hot 経路(root walk 等)が触る VM 共有構造は専用 leaf mutex(registered globals / id2ref / shareable generic fields / ページプール)、**稀な free 経路(shared fiber pool の stack release 等)は NO_BARRIER VM lock で足りる**。leaf lock のクリティカルセクションは「確保しない・ブロックしない」規律(確保が要る挿入は GC 禁止区間か二相)

## global GC の起動条件(§2.2、全 3 種実装済み)

1. shareable 増加: `shareable_objects > limit`(survivors×2.0、下限 1<<16)
2. 滞留: `stalled_shareables > limit/2` — mark 完了後の pin walk が数える「自 root から届かない shareable」(M5(7) で pin を gc_marks_finish へ移設し意味を厳密化)
3. zombie 保持ページ ≥ 256(`vm->gc.zombie_total_pages` — retire 時記録、global cycle がバリア内で実測 refresh。a6d47bd3d で個数 8 から置換)

評価は **gc_start 冒頭**(割り当てスローパス含む全 GC 入口の合流点 — a6d47bd3d で配線漏れ修正)。

## 検証手段

- **repro スイート**: `rlgc_repro/v2_*.rb`(自己完結 10 本)+ ランナー
  `rlgc_repro/run_v2_suite.sh [RUBY] [plain|stress|tiny|stress-tiny]`(exit = 失敗本数。
  sanitizer ビルドの ruby を渡せばそのまま ASAN/TSan バッテリになる)
  + v1 オラクル `rlgc_repro/b7–b11`(65 本)。
- **per-test verify モード**: `RUBY_TEST_GC_VERIFY=N make test-all TESTOPTS=-j16` — 各テスト
  終端で N 個毎に GC.verify_internal_consistency(素数 N + ランダム順で回毎に別標本)。
  CI 候補ジョブ: N=7 / j16 で 1 ラウンド ~15 分。
- **sanitizer 環境(ディスク常設)**: src worktree `~/ruby/src/wt-sani` +
  build `~/ruby/build/v2-tsan`(clang-18 `-fsanitize=thread -O1`)/ `v2-asan`。
  **TSan はビルド時も** `TSAN_OPTIONS="suppressions=…/tsan_suppressions.txt exitcode=0"`
  が必要(mkmf が system() を呼び、miniruby の TSan 既定 exit 66 で ext configure が落ちる)。
  バッテリ実行は exitcode 既定(未分類レース = 即失敗)で run_v2_suite.sh を流す。
- **RLGC 不変条件 verifier**: `GC.verify_internal_consistency` が s→u=shref 検査・
  shref⟹unshareable・bitmap⟺FL_SHAREABLE・T_NONE ビット衛生・封じ込め(u→外部 u 禁止、
  例外 box->top_self)・呼び出し Ractor の root スコープ(machine_context と設計上
  クロスルートな VM 大域は除外)を検査する。
  最終掃引: **ok 57 / timeout 8 / crash 0**(timeout は cpu≈wall の全力 spin = adversarial 設計、v1 期から master でも完走しない)
- **TSan**: worktree ビルド(`git worktree add` → clang-18 `-fsanitize=thread -O1`; in-tree srcdir 直は VPATH が in-tree .o を拾い破綻)。
  `TSAN_OPTIONS="suppressions=RLGC_DOC/tsan_suppressions.txt"` で**未分類 0**(suppression は全件根拠コメント付き; 非マッチ=新規=要調査)
- **ASAN**: 同 worktree 方式。mix/gen/g2/m42 バッテリ緑
- **ストレス**: `rlgc_repro/v2_concurrent_local_gc_mix.rb`(12 worker 並行 GC+終了/併合+global)を GC_STRESS / tiny-heap / stress+tiny の 3 条件でも緑

## 今日見つけて直した代表バグ(詳細は各コミットログ)

- M1b 系: Ractor dmark が他 Ractor の owner 変異構造を歩く(threads/EC ×1、queues/ports ×1)、deleted-key 機構の STW 前提、gc_enter の main 判定揺れ、interrupt queue の create→start 窓(v1 §6.4 残存面)、process-wide static の再書込
- M5 系: end_procs / trap_list の封じ込め漏れ、_id2ref build の単一 objspace 走査、**圧縮ガード未移植**(multi-objspace で full GC に degrade。→ その後 commit 0b23f634c で degrade を撤廃し実 compaction を実装、残項目 1 参照)、**value 継承物の到達性穴**(legacy/stdio/Thread wrapper → 併合直後 shref pin)、**mark_func_data redirect 乗っ取り**(v1 during_gc ゲート未移植 — 4 オラクル一括治癒)、**svar 封じ込め**(shref 不発 + Ractor 間共有 svar の per-EC 退避 = `$~` 漏れ解消)、**昇格カウンタの driver 偏り**(major ペーシング歪み)

## 残項目(2026-06-11 設計合意済みの実装キュー — 上から順に)

1. ~~compaction の global-STW 実装~~ **完了(commit 0b23f634c)**: 複数 objspace でも
   global GC(STW)の一部として全 objspace を 3 相(move→update→free)で実 compact する
   (§2.2 末尾)。degrade は撤廃。CHECK/ASAN/TSAN/YJIT stress・verify_compaction multi-Ractor
   ・単一 objspace 回帰すべて green。
2. generic_fields の per-objspace 分割(§2.4-2): 性能最適化(現ベンチでは非ホット)
3. ASAN/TSan の CI 常設化(レシピ・suppression は完備)+ v1 オラクル 65 本の再掃引
4. N=1 の残オーバーヘッド(~11%)/ TSan watch: `VM_FORCE_WRITE` 単発(ペア未捕獲)

## 既知の乖離(要修正)

- **isolated proc の env の svar($~/$_)**: 設計(§2.1)どおり、**escaped な shareable env の
  svar は per-EC(`ec->root_svar`)にルート済み**(`lep_svar_in_env_p`)。ただし
  `vm_env_write_slowpath` の FL_SHAREABLE 分岐が**残余の env-slot write を WB で通して
  GC-safe にしているだけ**の経路として残っており、そこを通ると shareable env 自身の svar
  スロットへ書き得る。GC 的には安全だが、isolated Proc を複数 Ractor で共有した場合に
  共有 env の svar を相互書き込みする**意味論の穴($~ の Ractor 間混じり)は残る**。
  正しい修正は残余経路も per-EC 化(または当該変異の禁止)。列挙変更(§2.4)とは独立の
  Ractor 正しさバグ。
