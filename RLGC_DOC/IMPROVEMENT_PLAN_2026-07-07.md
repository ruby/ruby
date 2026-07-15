# REVIEW_2026-07-04 の妥当性検証と改善計画 (2026-07-07)

対象: `RLGC_DOC/REVIEW_2026-07-04.md`(以下「レビュー」)。
方法: **全主張をドキュメントではなく実装(現ブランチのコード・コミット・実行結果)に
対して検証**した。検証時 tip = 4b75d2f0d(origin/master c51b1596c へ rebase 済み)。

---

## 1. 結論: レビューは適切(高精度)。ただし進捗により陳腐化した項目と、判定を訂正すべき項目がある

### 1.1 妥当性の根拠(実装で確認)

- **A-1〜A-7 / C-1 / C-2 / B-1,3,4,7,10,11,14,15 は全て修正コミットが実在**し、
  多くは「修正前 repro が決定論 crash → 修正後 clean」の実証つき。subject で照合済:
  `8b10fdd92`(A-1 shared-root) / `be6e9dc4b`(A-2 reap STW 限定) /
  `f0fdd9d10`(A-3 creating_child) / `5ca1ad3a8`+`be186e93a`(A-4 IO courier) /
  `a2cc8a44d`(A-5 昇格順序) / `d99cfc5bb`(A-6 例外安全) / `d353fc361`(A-7 merge GC窓) /
  `f2713a689`(C-2) / `01e0aed1e`(B-1) / `158c5fcf3`(B-3) / `19c7f80f7`(B-4) /
  `060b85d17`+`2388421b1`(B-7) / `e5c2a92d2`(B-11) / `3a26311e2`(B-14) /
  `27da91cc1`(B-15) / `3f1b8edfe`+`f628a9870`+`6b29b0c59`(C-1)。
  レビューが「実バグ」とした指摘はことごとく実バグだった。
- 未対応と記された項目(B-2/5/6/8/9/12/13, C-3, 改善群)も、**今回コードで再確認した
  結果、記述どおり open だった**(下記 §3)。誤検出は見つからなかった。

### 1.2 判定を訂正すべき項目

- **B-9(define_finalizer の shareable 一律拒否)**: 「効いていない」は表現が不正確。
  実装(`e11013b5f`)は**所有権ベース**(`GET_HEAP_OBJSPACE(obj) != objspace` →
  IsolationError、foreign なら shareable 含め拒否)で、**own-shareable への登録は許可**
  かつ**正しく機能する**ことを実測で確認した(child が自作 shareable Class に finalizer
  → child 終了 → absorb がエントリ移送 → main の GC で発火 = flag file で確認)。
  つまりバグではなく **design_v2.md 決定12 の文言(一律拒否)と実装(所有権ベース)の
  乖離**であり、доc を実装に合わせるのが正しい(実装のほうが機能的に優れている)。
- **総評の「compaction の multi-Ractor 無効化は現段階のトレードオフ」**: その後
  Stage 2(`0b23f634c` 系)で**実 compaction を実装済み**。将来請求書の懸念は解消。
- **each_object collect-then-yield「保留」**: その後実装済み(`a0a5ad5ac` 系)。
  自 objspace 全 + 他 Ractor shareable を列挙する。

---

## 2. 対応状況の総括(実装検証ベース)

| 群 | 状態 |
|---|---|
| A-1〜A-7(UAF 級) | **全て修正済み・実証つき** |
| C-1, C-2 | 修正済み |
| B-1,3,4,7,10,11,14,15 | 修正済み |
| **B-6** | **本日修正(38c24f753)** — §4.1 |
| **C-3** | **本日修正(同コミット)** — empty_page ループに free_next 前進を追加 |
| **B-2** | **07-07 解決**(ko1 決定「全 Ractor が保守的に見る」= S-2 単一リスト復帰) |
| **B-9** | **07-07 解決**(ko1 決定「自 Ractor のオブジェクトなら通す」= doc を所有権ベースに改訂) |
| B-5 | ko1 判断: 当面無視 |
| B-8, B-12, B-13 | open(§3 で計画) |
| 改善 1〜9 | 一部済(9 の repro 群は fix batch で追加)、残は §3 |
| doc 問題群 | 一部済(lock model, compaction, §3.1/3.2 追記等)。残あり |

---

## 3. 残項目の改善計画(優先度順)

### P1 — 実装する(小〜中、設計判断不要)

1. **B-13: pjob flush 例外パスの宛先**(vm_trace.c) — 残ビットを global
   `triggered_bitset` でなく flush 中 Ractor 自身のマスクへ再投入。現状は
   `RUBY_ATOMIC_OR(pjq->triggered_bitset, ...)` のまま(確認済)。小修正。
2. **改善5: `rb_replace_generic_ivar` の削除** — caller ゼロを確認済(variable.c:2483)。
   dead code + 未文書前提(同 shareability class)を抱えるため削除。
3. **改善6: `newobj_init` に決定13 の誕生時 assert**(shareable ⇒ wb_protected)。
   CHECK 限定・規律の構造化。
4. **改善9 残り: 回帰テスト** — 追加済 repro(v2_stillborn_ractor,
   v2_move_shared_root_str 等)を btest/test-all の恒久テストへ昇格する。

### P2 — 実装する(中、軽い設計確認つき)

5. **B-8: move が String/Array/Hash のサブクラスを落とす** — courier の
   MOVE_K_STRING/ARRAY/HASH ノードに klass が無いことを確認済(ractor.c:2399-2401、
   u.obj/strct/match/io のみ klass 保持)。ノードに klass を載せ materialize で
   allocate。upstream 互換の後退なので直す価値が高い。T_STRUCT singleton も同時に。
6. **改善3: global sweep が作った他 objspace の zombie finalizer** — owner 宛て
   `rb_postponed_job_trigger_for_ractor` を撃ち、quiescent worker での無期限遅延を解消。
7. **改善4: objspace 殻の解放漏れ**(weak_references darray / profile records /
   malloc_increase) — absorb に free を足す。bounded leak の解消。
8. **改善8: moved T_OBJECT の singleton attached_object** — move での singleton
   拒否 or re-attach。B-8 と同時に扱うと安い。

### P3 — 設計判断が必要(ko1 判断待ち。実装はどれも小さい)

9. ~~B-2: registered address の契約~~ **解決(2026-07-07, ko1 決定=「全 Ractor が保守的に見る」)**:
   S-2 を実装 — 登録リストを VM 単一(vm->gc.registered_globals + leaf lock)へ復帰し、
   **全 Ractor の root walk が全登録を走査**(mark_maybe の own-objspace filter が選別)。
   per-Ractor 分割・absorb 移送・zombie-owner 特例・B-1 観測罠を撤去(cross-Ractor
   unregister は単一リストで自然に動作)。design §2.1 手順 3.e と実装が再び一致。
10. ~~B-9: 決定12 の文言~~ **解決(2026-07-07, ko1 決定=「自 Ractor のオブジェクトなら通す」)**:
    design_v2.md 決定12 を所有権ベース(実装 e11013b5f どおり)に改訂済み。
11. **B-5: at_exit/END 非 main エラー化** — 仕様確定済(Matz 合意)・実装未着手。
    **2026-07-07 ko1 判断: 当面無視**(実装しない)。
12. **改善1: 会計系 pacing**(single→multi 遷移の shareable_objects 再計数、
    stalled_shareables の過大計上) — 性能チューニングとして一括で。
13. **改善2: move の「ゼロコピー」方針** — steal をやめるか adopt を実装するか。
    A-1 修正(shared-root はバイトコピー)後の残り(通常 String)の話。
14. **改善7: FREEOBJ hook を worker objspace に立てない構造的強制** — mask/assert。
15. **B-12: modular GC(mmtk)整合** — 当面「このブランチでは modular GC 非対応」を
    明示するだけで良い(USE_MODULAR_GC=0 が既定)。upstream 化の際に表を揃える。

### P4 — doc 反映(レビュー §3 の残り)

16. ~~§2.1 3.e の反映~~ **不要になった**: S-2 実装で per-Ractor 分割を撤去し、
    実装が §2.1 3.e の記述(単一リスト・全走査)に復帰したため doc は正確に戻った。
17. 決定16(T_DATA 宣言機構)に【未実装・現状は全 T_DATA が local GC 参加】を明記。
18. id2ref の user-visible 非互換(非 main の `_id2ref` = RangeError)を決定として記録。
19. STATUS_2026-06-28.md に superseded 注記(現況表は STATUS_v2 に一本化)。
20. GENERIC_FIELDS_PLAN.md に完了ヘッダ。REVIEW_GUIDE.md の stale 免責更新。

---

## 4. 追加レビュー(2026-07-07、現状に対して新たに実施・修正済み)

### 4.1 B-6 が ObjectSpace.each_object でユーザ到達可能になっていた(修正済 38c24f753)

- each_object の cross-Ractor 化(相2)は `rb_gc_impl_each_objects_shareable` を使うが、
  これが foreign objspace を **protected walk(gc_rest)** で歩いていた =
  barrier で止まった owner の**中断中 lazy sweep を walker スレッドが完走**させ、
  owner のオブジェクトの obj_free / T_DATA dfree を **walker の Ractor identity** で
  実行(per-Ractor 表を誤参照する finding-B と同型)。TracePoint enable 経路でも同じ。
- 修正: foreign walk を unprotected 化し、settle の代わりに **unswept ページの
  未 mark オブジェクト(= sweep が解放予定の死骸)を走査側で skip**。死骸を
  each_object に渡すと resurrection(barrier 解除直後に owner の sweep が解放する
  参照をユーザに渡す)になるため、skip が意味的にも正しい。
- 検証: TracePoint×parked-worker×each_object stress CHECK 0/5、each_object
  セマンティクス不変、test_settracefunc/test_ractor/test_gc/objspace green。

### 4.2 C-3(CHECK 診断の無限ループ)修正済(同コミット)

`check_rvalue_consistency_force` の `while (empty_page)` に `free_next` 前進が
無かった(upstream 由来)。upstream へも送る価値あり。

### 4.3 each_object の新セマンティクスと btest の不整合(修正済 4b75d2f0d)

旧仕様(「Ractor 内 each_object は unshareable を見せない」)を明文化した
bootstraptest/test_ractor.rb:1252 が新仕様(自 objspace は全列挙)で fail。
新契約(自分のオブジェクトは見える)に書き換え。
**教訓: セマンティクス変更時は btest まで回す**(test-all だけでは拾えなかった)。

### 4.4 origin/master(c51b1596c)への rebase 完了(182 commits、衝突3回)

- upstream が allocation を再構築(d9b4ab5b4: bump-pointer cache に incremental 窓 /
  jit_cursor / atomic flush、**ZJIT inline GC fastpath**)。RLGC は M0b で cache を
  撤去し heap-direct + counter 方式のため、M0b の解決は「衝突領域を M0b テキストで
  再構成 + upstream 新規要素の移植」で行った。
- **`rb_gc_impl_zjit_new_obj_fastpath` は stub(return false)** — RLGC の heap は
  per-objspace で、ZJIT の fastpath 機構は per-Ractor cache 構造体前提のため。
  wbcheck と同じ正規の fallback(inline 割り当てだけ無効、意味論は不変)。
  **heap-direct fastpath(heap は single-writer なので可能)は将来課題**。
- upstream の他の default.c 変更(DTRACE GC hook / max_allocation_size)は保持を確認。
- 検証: btest 2050 PASS(each_object 更新後) / test-all(gc/ractor/compact/objspace)
  0F0E / 全5ビルド green / Stage2・each_object・GC.disable のサニティ 0 fail。

### 4.5 レビュー自体への補足(今回の視点)

- レビューの構造的指摘 2 点(「plain-store 論証の脆さ」「異常系の後始末」)は
  fix batch 後も**新規コードに対する監査観点として有効**。実際 4.1 は
  「foreign を触る walk の後始末(settle)が owner の文脈を要する」という
  同族第3例だった。**「他 objspace に対して GC 作業(settle/sweep/free)を
  走らせる箇所は、実行スレッドの Ractor identity を要確認」をレビュー観点に追加**すべき。

---

## 5. 実行順序の提案

1. ~~B-6 / C-3~~(本日完了)
2. P1(B-13 / dead code / assert / テスト昇格) — 半日
3. P2(B-8 サブクラス / zombie finalizer pjob / 殻 leak / singleton) — 1〜2日
4. P3 の設計判断を ko1 と確定(B-2 は S-2 案、B-9 は doc 改訂、B-5 は実装時期)
5. P4 doc 反映(判断確定分から)
6. 長時間 soak(rebase 後の全構成)で 4.4 の安定性を確定
