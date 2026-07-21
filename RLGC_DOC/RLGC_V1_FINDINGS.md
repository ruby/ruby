# RLGC v1 課題カタログ(v2 への入力)

date: 2026-06-10

v1(本 branch の実装)の開発・監査で見つかった課題を、**v2 設計([design_v2.md](design_v2.md))と
将来のレビューの入力**として保存する。証拠・実装の詳細は v1 文書
([RACTOR_LOCAL_GC_DESIGN.md](RACTOR_LOCAL_GC_DESIGN.md))と各コミットを参照。
ID(A-1 等)は design_v2.md から参照される。

## A. v1 で解決したが、v2 では「構造で」消すもの

- **A-1 孤児 objspace(v1 最大の根本原因)**: 終了 Ractor の objspace が GC の巡回対象から
  外れ、そこに住む shareable(クラス等)の mark ビットが stale のまま残る → 次の global GC の
  統一 mark が「マーク済み」と誤認して children(main 在住の cc_tbl)を辿らない → sweep が
  使用中の cc_tbl を解放 → lock-free メソッドキャッシュ参照で UAF。ASAN で確定。
  v1 は orphan リスト(global GC が巡回)で修正。**v2: registry + 継承併合により
  「巡回されない objspace」「stale mark bit の残る殻」が存在し得ない。**
- **A-2 孤児の殻リークと zombie の行き止まり**: orphan 修正後も objspace 殻は永遠にリーク。
  「空になったら解放」を実装しても**全孤児で発火ゼロ** — 各孤児に T_ZOMBIE が最低 3 個残り
  (deferred finalizer / T_DATA の dfree 待ち)、**それを実行するスレッドが終了 Ractor には
  無い**。**v2: ページ併合により zombie は継承側スレッドの通常 finalize 機構で実行され、
  殻も解放される。**
- **A-3 newobj の VM ロック直列化(性能の根本原因)**: cache-miss ごとに process 唯一の
  VM ロックを取得し、全 Ractor の割り当てと GC が直列化(2.6 実効コア)。v1 は lock-free
  alloc + lock-free local GC で 4.7 実効コアまで回復。二次原因として per-page mmap/munmap が
  kernel の process-wide mmap_lock を直列化 → per-objspace アリーナで回避。
  **v2: cache 層自体を持たず(single-writer ヒープ直割り当て)、ページは global pool
  (mmap はアリーナ単位で稀)。**
- **A-4 `Ractor#value` の by-ref passthrough**: 戻り値をコピーせず返すため、終了 Ractor の
  objspace 内サブツリーへの cross-objspace 参照が恒常的に生じ、orphan 巡回が生存の前提に
  なっていた(= A-1/A-2 への依存を再生産)。**v2: value/join/port も copy 規律に統一。**
- **A-5 objspace 列挙の同期の曖昧さ**: 「生きている objspace の集合」を `vm->ractor.set`
  走査 + 別建て orphan リストで合成しており、列挙の安全性が「VM barrier 保持」という
  呼び出し側規約頼み。lock-free local GC からの `rb_gc_conservative_owner` 等では規約が
  成立しない構造だった。**v2: registry 一本 + leaf lock の明文規約。**

## B. v1 で解決し、v2 でも同じ防御を維持するもの

- **B-1 global GC の root 完全性(単一の根から 3 連発)**: 「global GC は全 objspace を
  clear+sweep するのに、root mark は駆動 Ractor の分しか辿らない」が 3 つの別症状で噴出:
  (1) in-flight メッセージの pin が global GC で全クリアされ、queued/materialize 中の
  コピーが送信側 local GC に解放される(→ basket mark 時の再 stamp + 受信側
  `in_flight_materializing` スロットの 2 層で修正)。
  (2) per-objspace `finalizer_table` が駆動側しか mark されず、worker の finalizer 値 Array が
  sweep される(→ global GC 中に全 objspace の table を pin)。
  (3) 子 Ractor の root fiber wrapper が main objspace 在住(生成は親スレッド)で、worker の
  local GC が foreign-skip → suspended root fiber のスタック未マーク(→ thread roots から
  cont を直接 mark)。
  **教訓**: STW 中なら駆動 Ractor から他 objspace への re-root / re-pin は健全
  (local GC 中は不健全)。**v2 は per-os root チェックリストを一元化し、local/global が
  同じ表から root を引く設計にする。**
- **B-2 lock-free bitmap の RMW race(TSan で確定)**: lock-free WB と並行 local GC が同一
  bitmap 語に `bits[i] |= mask` して片方の set が消失 → 他オブジェクトの remembered/shared
  bit が落ち、young の子が解放される(~0.4% の負荷依存 race)。修正 = atomic CAS の bit set、
  drain は atomic exchange、cross-Ractor の page flag はビットフィールドをやめ byte store。
  **教訓**: lock-free モデルでは多スレッド書き込みの語は全て atomic。snapshot 型検証器
  (RGENGC_CHECK_MODE)は barrier が窓を隠すため**並行 race を検出できない** — TSan を使う。
- **B-3 confinement-miss 族(VM インフラが「他人の objspace」に生まれる)**: Ractor の
  インフラを親スレッドが先に確保するため、子の objspace 外に子専用構造が住み、子の local GC
  からは foreign、親の local GC からは無 root になる。実例: thread の
  `pending_interrupt_mask_stack`(親 objspace の Array に子 objspace の Hash を push →
  UAF。thread 開始時に re-dup で修正)、root fiber wrapper(B-1(3))、fiber-storage、
  signal-trap handler。**教訓 / v2 規約**: Ractor を跨いで生成される VM インフラは
  (a) 所有者の objspace に生成し直す(re-home)か (b) 所有者の root から直接辿れるように
  する。新しいインフラ追加時のレビュー観点。
- **B-4 cc/cme ピンの global ゲート**: クラスは全て shareable なので local GC は解放しない
  =回収は global GC。cc/cme の sweep ピンが global GC でも効いてしまい、dead クラスが
  回収されるのに cme が残って owner を dangling 参照 → ピンを「global GC 中は外す」で解決。
- **B-5 並行 local GC × VM 共有可変構造(8 件)**: generic_fields_tbl / id2ref 等は
  NON_BARRIER ロック(バリアに途中参加しない VM ロック)で mutator と同期、Ractor port は
  per-Ractor ロック、等。**教訓**: local GC が触る VM 共有構造を列挙し、各々に同期戦略を
  明示する(暗黙の「GC 中だから安全」は成立しない)。
- **B-6 `vm->gc.mark_func_data` の乗っ取り窓**: VM-global な mark redirect
  (ObjectSpace.reachable_objects_from 等)が並行 local GC の mark を横取りし得た →
  `during_gc` ゲートで「本物の GC 中は redirect を無視」。
- **B-7 空 objspace の sweep 境界**: 0 ページの objspace で
  `heap_pages_free_unused_pages` が `sorted[-1]` を読む → ガード。v2 ではページ併合 +
  pool 返却で「0 ページの居残り objspace」自体が出にくいが、境界条件としては残る。
- **B-8 introspection の load-bearing なガード(負の結果から)**: ext/objspace 系を
  並行 local GC 下で総当たりして全クリーン。ただし安全性は偶然ではなく
  (a) `_dump`/`_dump_all` の STW バリア、(b) tracepoint(trace_object_allocations)の
  main-Ractor 限定(worker objspace に FREEOBJ hook が立たない)、(c) B-6 の during_gc
  ゲート、に依存している。**これらを外すと壊れる**ことを v2 でも前提として維持する。

## C. OPEN(v1 未修正。v2 は設計段階で潰す)

- **C-1 send-copy の old→young remembered-set 漏れ(決定的クラッシュ)**: 深い非 shareable
  グラフ(generic ivar に Array 値を持つホスト)を `Ractor#send` → 受信側 re-clone +
  昇格圧 + confined minor GC で、remembered な old Array の子が T_NONE
  (`rgengc_rememberset_mark` / `gc_mark_stacked_objects_all` で `[BUG] try to mark T_NONE`)。
  受信側 materialization(rb_copy_generic_ivar 等)が作る old→young エッジが受信側
  remembered set に入らない。repro: f3_min.rb 12/12(非 RLGC 0/12、単一 Ractor 0/15)。
  rebase(shape layout 変更 PR#17139/#17158)でも不変。世代 WB × cross-objspace は
  独立ファミリ(v1 §6.13 Family III)。**→ v2 design §4.3(materialization の全ストアを
  WB/remember 経由にする)。**
- **C-2 T_DATA の by-ref passthrough(backtrace)**: 「move 不可かつ即値参照が全 shareable
  なら同ポインタを渡す」例外により、unshareable な backtrace T_DATA が送信側(→孤児)
  objspace に残ったまま受信側から参照され、strary の遅延生成と相まって mark-T_NONE。
  repro: b5_bt1.rb 8/8。**→ v2 design §4.5(passthrough 撤廃、copy 不可ならエラー)。**
- **C-3 `GC.auto_compact=` の未ガード**: GC.compact / verify_compaction_references は
  RLGC 時に move を禁止しているのに、auto_compact 経路だけガードが無く、worker 存在下の
  full GC が compaction を実行してヒープ破壊(cme/cc/class 全般の mark-T_NONE、SEGV)。
  repro: g8_nosend.rb 8/15。**→ v2 design §2.5(3 経路すべてガード)。**

## D. 未監査・未決定領域(v2 でも要対応)

- **D-1 ユーザ T_DATA の `dmark`/`dfree`**: local GC 中に任意の C 拡張コードが走り、共有 C
  状態を触り得る(封じ込めモデルの穴)。案: RLGC-safe 宣言型のみ local 参加、他は global 委任。
- **D-2 JIT(YJIT/ZJIT)**: Rust 側の per-Ractor 相互作用・GC 外の共有表は未監査。
- **D-3 `RUBY_INTERNAL_EVENT_FREEOBJ`**: local sweep 中のフック発火と共有状態アクセス。
  v1 は「worker objspace に FREEOBJ hook を立てない」ことで安全(B-8)— v2 でも維持。
- **D-4 shared_bits soundness の C 全体監査**: 「s→u エッジは u の所有者が作る」(C8)を
  非 WB 経路(memcpy / clone-move / generic ivar / classext / managed id table / shape /
  JIT のポインタ更新)で網羅監査していない。
- **D-5 process-wide API の細部**: GC.* 系は per-Ractor で決定済み(design_v2 決定事項 7-9)。
  残: `rb_gc_register_mark_object` 等「current objspace のヒープ判定で foreign を弾く」箇所の
  個別確認、ObjectSpace.each_object の全 objspace 走査(_dump 系は STW バリアで対応済み)。

## E. 検討して棄却した設計(再検討の出発点)

- **E-1 受信側へ単一 clone で直接確保 — 不可能(トリレンマ)**: (I) snapshot 意味論
  (コピー内容は send 時確定)、(II) lock-free local GC、(III) 単一トラバースで受信側着地、
  は同時に満たせない。send 時にやれば送信スレッドが受信側の無ロックヒープへ書く(II 破壊)、
  receive 時にやれば send 後の変更が漏れる(I 破壊)。→ materialize-on-receive(2 回
  トラバース)が唯一解。v2 もこれ。
- **E-2 送信スレッドを一瞬受信 Ractor に所属させる — 不可能**: objspace と割り当て文脈の
  密結合、「1 Ractor だけ止める」プリミティブの不在、local GC の root が駆動スレッドの EC に
  固定、身分フリップ中のユーザコード誤動作、相互 send のデッドロック。
- **E-3 materialize 中の holder で再ピン補強 — 無効を実測**: 60 回 A/B で有意差なし。撤回。
  (真因は B-1 の global GC root 不完全性だった。)
- **E-4 cc/cme ピンを shareable クラス限定に — 悪化を実測**: dangling が owner→def-body→
  inline-cache へ移るだけ(4/20 → 8/20)。撤回。
- **E-5 コピーの main objspace 確保 / 明示 export 表 / shared_bits の汎用 cross-objspace
  remset 化**: それぞれ main 肥大・STW 頻発 / 永続 root 集合と reconcile 機構が過大 /
  root エッジ(parent 無し)を表現できず不完全、で棄却。

## F. 方法論の教訓

- **F-1 サニタイザが決定打**: A-1 は ASAN、B-2 は TSan で確定。推論・アドレス交絡リング・
  snapshot 検証器では閉じなかった。v2 の CI に ASAN/TSan ストレスを常設する。
- **F-2 症状ガードは入れたら根治後に撤去**: WB の T_NONE ガード、cc-table の drop/skip 等
  「witness 叩き」は 5 連敗し、根治(A-1)後に冗長と実測して撤去した。残すと次のバグを隠す。
- **F-3 GC_STRESS はタイミングを変えて隠すことがある**: C-1 の最小再現は GC_STRESS で
  消える(昇格窓が変わる)。stress あり/なし両方でテストする。
- **F-4 `RGENGC_CHECK_MODE` は RLGC 非対応**: cross-objspace 参照を偽陽性で報告し、
  並行 race は barrier が隠す。封じ込めの検証は専用 AUDIT(s→u WB 完全性 + u→s sweep
  不変条件)を使う。
- **F-5 負の結果も資産**: proc/env の isolate・make_shareable(91 runs)、callable 族
  (curry/compose/bind、~200 runs。そもそも proc は send できず、escape 経路は value のみ
  と判明 — v2 の §4.4 の根拠)、ext/objspace introspection(B-8)はクリーン。
  「どのガードが load-bearing か」の記録として v2 のレビュー観点に使う。

## G. 再現スクリプト索引

- リポジトリ内: `rlgc_repro/`(b7: thread mask-stack UAF / b8: callable 族 / b9: isolate 族 /
  b10, b11: 監査バッチ)。
- 未収容(/tmp、要 `rlgc_repro/` への移送): f3_min.rb(C-1 決定的)、b5_bt1.rb(C-2)、
  g8_nosend.rb・g6_autocompact.rb(C-3)、o1〜o12+ofinal(B-8 負の結果)、FINAL.rb /
  MIN_final.rb(C-1 旧形)。
- ベースライン: btest 2051 / btest_ractor 161 / test-all、v1 の 36 ストレスシナリオ
  (fanin / gc_stress_everywhere / maximize_confined / fiber_transfer / nested_workers …)。
  **v2 の M5 はこれら全部をテストオラクルにする。**
