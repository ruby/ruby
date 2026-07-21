# RLGCv2 設計

status: DESIGN — これを元に origin/master から実装する
date: 2026-06-10

Ractor ごとに独立した GC(Ractor-local GC)の設計。

## 全体像

- Ractor ごとに独立した objspace(ヒープ + GC 状態)を持つ。**main Ractor も同じ**で、
  特別な「VM の objspace」は存在しない。
- VM が直接指す GC のデータは `rb_global_objspace` ただ一つ。その中身は実質
  **ページプール(全 Ractor 共通のページ供給源)だけ**である。
- GC は「自分の objspace だけを、他の Ractor を止めずに回収する local GC」と、
  「全 Ractor を止めて全 objspace を一括回収する global GC」の二本立て。
- Ractor をまたぐオブジェクトの受け渡しは「shareable は参照のまま、unshareable はコピー」。
  これに例外を作らないことが GC の単純さを支える(§4)。
- Ractor が終了したら、その objspace は **join した Ractor が、いなければ main が
  ページごと引き継ぐ**(§2.3)。回収の主体を失う objspace は存在しない。

基本となる約束は次の 2 つ。以後の設計はすべてここから導かれる。

1. **封じ込め**: unshareable なオブジェクトへの参照は、その所有 Ractor の objspace の中に
   しか存在しない。(例外は送信中のメッセージだけ。pin で保護する。§4)
2. **single writer**: ある objspace のヒープ(freelist・ページリスト・各種カウンタ)を
   触るのは、その所有 Ractor のスレッドだけ。Ractor 内のスレッドは Ractor ごとの GVL で
   直列なので、ヒープ操作にロックは一切不要になる。

封じ込めから「local GC は自分の objspace の中だけ見れば生死を決められる」が出て、
single writer から「割り当ても GC もロック不要」が出る。

## 決定事項

1. objspace を rb_global_objspace(VM が唯一指す)と rb_objspace(Ractor ごと、main 含む)に
   分割する。
2. コンパイル時マクロや機能を切る環境変数は作らない(常時有効の一本道)。
3. newobj cache 層(master の `rb_ractor_newobj_cache_t` 相当)は作らない。割り当て状態は
   objspace のヒープに直接置く(single writer なので不要、§3)。
4. 空きページは global のページプールに返し、確保もそこから。Ractor は空きページを抱えない。
5. 終了した Ractor の objspace は、join(`Ractor#value`)した Ractor が**その場で**併合して
   引き継ぐ。join されないまま Ractor オブジェクトが回収されたら main が引き継ぐ。
6. 「unshareable はコピーでしか Ractor を渡れない」を守る。master に「同じオブジェクトを
   そのまま埋め込む例外」は存在しない: master の copy は unshareable を必ず `#clone` で複製する
   (`ractor_obj_clone`)。`obj_traverse_replace_i` の T_DATA ケースの
   `obj_refer_only_shareables_p` は「参照先が全部 shareable なら copy を許可する条件」であって
   (make_shareable 判定と同じ述語)、埋め込み例外ではない。すり抜けの実体は別で、`#clone` が
   T_DATA(例外の backtrace)の内部の生ポインタ(locations 配列)を複製と共有する点にある:
   master(単一ヒープ)では locations が全部 shareable なら無害だが、RLGC では objspace を跨ぐ
   生ポインタになり containment を破る。RLGC は backtrace を専用 deep-copy(`rb_backtrace_dup`,
   `ractor_native_shallow_copy` の T_DATA ケース)で複製して解消(§4.4)。`_dump` を持たない他の
   T_DATA は Marshal fallback、それも無理なら送信エラー。`Ractor#value` は「併合してから返す」
   ので例外にならない(§4.3)。
7. GC.stress / config / measure_total_time / stat / count は呼んだ Ractor の
   objspace に対する操作・表示。ただし **GC.disable / GC.enable は process 全体**
   (§3.1)。「GC を止めたい」という要求は普通 process-wide なので、呼んだ Ractor だけ
   止めても他 Ractor の割り当てが global GC を駆動してしまう。
8. fork は「自分以外の Ractor を殺してから」と同じ意味にする(子プロセスで他 Ractor の
   objspace は引き継ぎ機構で main に併合される)。専用機構なし。
9. VM 終了も「全 Ractor を殺す」だけ。全部が main に併合され、従来どおり main が
   finalizer を流して終わる。専用機構なし。
10. 統計カウンタは global に持たない。GC 回数等は objspace ごとの profile で足りる。
11. コピーはユーザ可視の `#clone` / `#initialize_clone` を呼ばない。コア型(String / Array /
    Hash など)は C の専用深コピーで書き、それ以外は当面 Marshal dump/load(Marshal の既存
    フック仕様には従う)。どちらにも乗らない型は送信エラー。残りは後で考える(§4.2)。
12. `define_finalizer` できるのは対象オブジェクトの所有 objspace(= 生成した objspace)
    だけ。他の Ractor から設定しようとしたらエラー。登録・テーブル・実行のすべてが所有
    Ractor に閉じる(§2.1)。2026-07-07 確定(所有権ベース、実装 e11013b5f どおり):
    **自 Ractor のオブジェクトなら shareable(非 frozen = Class/Module)でも許可**し、
    foreign なら shareable 含め Ractor::IsolationError(undefine も対称)。own-shareable の
    finalizer エントリは所有 objspace の表に住み、Ractor 終了時は継承(absorb)先へ
    移送されて正しく発火する(実測済み)。(旧 2026-06-12 案の「shareable 一律拒否」は
    所有権ベースに置き換え。)**clone/dup は cross-objspace では finalizer を引き継がない**(Ruby の clone は
    元々 finalizer を運ばない — 公開 C API rb_gc_copy_finalizer の cross-objspace 呼び出し
    だけが対象で、no-op にする)。
13. **WB-unprotected な shareable は unshareable を参照しない**、を不変条件とする。
    これにより shareable → unshareable の store の親は常に WB-protected で、この store は
    必ず write barrier を通る(shref の完全性が既存の世代別 WB と同じ規律に帰着する、
    §2.1)。この不変条件が成り立つ限り shref は壊れない。実装では make_shareable /
    FROZEN_SHAREABLE 系の既存検査(参照先がすべて shareable であること)に加え、
    shareable への wb_unprotect を assert で禁じて担保する。(より強い不変条件として、
    現行実装では `FL_SHAREABLE ⟺ shareable_bits` を 1:1 に保ち、shareable が参照するのは
    shareable か shref 付き unshareable のみ、を CHECK モード verifier で検査する
    — §現在の到達点 4a/4b。)
14. **local major と global GC の起動要件は独立**。major は毎回 global へ昇格しない。
    local major は自分の旧世代(unshareable)の増加で、global GC は **shareable の世界の
    増加・滞留**(と終了済み Ractor の堆積)で起動する(§2.2)。
15. ページに **shareable_bits** を追加し、「local GC が解放してはならないオブジェクト」
    (shareable + 共有され得る VM 内部 imemo)をビットマップ化する。confined GC は
    これを索引に shareable を **root として mark bit を立てて**生かす(traverse は
    しない = mark-only。§2.1 — sweep で除外する方式は、生かしたオブジェクトの世代が
    進まず世代不変条件と衝突するため不採用)。
    ページ上の RLGC 追加ビットはオブジェクトあたり shref と合わせて 2 bit(§1.4)。
16. ユーザ定義 T_DATA の `dmark` / `dfree` は、upstream で導入予定の
    [Feature #22067](https://bugs.ruby-lang.org/issues/22067) の宣言機構に従う:
    宣言済みの型のみ local GC に参加し、未宣言の型は global GC だけが mark / free する
    (local GC 中に任意の C 拡張コードが他 Ractor と並行に走ることを防ぐ)。
17. **shareable から参照されるものは、例外を除いて shareable にする**。cc / cme /
    callinfo / iseq などメソッド・キャッシュ系の VM 内部オブジェクトは born-shareable に
    し、shareable_bits は FL_SHAREABLE と 1:1 に保つ。shareable → unshareable を許す
    例外は明示的なリストで管理する(§2.1)。【達成済み】ment / callcache / callinfo /
    constcache / iseq(および cref / cvar_entry)は `SHAREABLE_IMEMO_NEW`(is_shareable=true)
    で生成され、誕生時から完全な FL_SHAREABLE + shareable_bits を持つ(pin のみで
    FL_SHAREABLE を立てない中間状態は無い)。
18. **postponed job を特定の Ractor(まずは main)宛てに配送できる機構**を、GC とは
    独立の汎用 VM 機構として新設する。トリガ側は宛先 Ractor の triggered マスクに
    ビットを立てて宛先 EC に POSTPONED_JOB 割込みフラグを立てるだけ(ubf では
    起こさない — ブロック中なら次に自然な safepoint へ戻ったときに実行される)。
    flush は従来の「自分宛て(トリガしたスレッド)」のジョブに加えて自 Ractor 宛ての
    マスクを drain する。最初の利用者は orphan objspace の main 併合(§2.3)。

---

## 現在の到達点(最新仕様サマリ)

この節は「最新の確定仕様がどこにあるか」を一目で掴むためのアンカーである。確定済みの
事項についてはこの節を正とする(機序・理由の詳細は各節)。当初の設計メモには「予定 /
これから決める」という段階的な書き方が残っている箇所があるが、以下はすべて**実装済み**で
ある。

- **ロック模型(達成済み。旧 M1a→M1b 完了)** — 通常ビルド(production):
  - **非 main Ractor の local GC**: ロックもバリアも取らない(封じ込めで single-writer、
    cross-objspace の bitmap 書き込みは atomic)。
  - **main objspace の local GC**: no-barrier の VM lock を取る(barrier は張らず他 Ractor は
    止めない)。main は VM グローバル root(boot オブジェクト)を持ち、その local GC が
    `rb_vm_mark` でそれを歩くが、root は他 Ractor が VM lock 下で変異させるため。
    (この main の特別扱いは排除の検討対象 — root を shareable-pin 化して global GC へ
    寄せれば落とせる見込み。)
  - **global GC**: VM lock + barrier(STW)。local GC ではなく別 mode。barrier が in-flight の
    local GC を待つ(GC は safepoint を持たず gc_exit まで合流しない)。
  - GC の内側では VM lock を取らない(待機者が保留中バリアに合流し半回収ヒープを晒す)。
    GC 経路が触る VM 共有構造は専用 native mutex(id2ref / registered globals /
    generic fields)かページプールのロックで守る。**この不変条件は CHECK ビルドも守る**:
    `gc_local_gc_holds_vm_lock` は main objspace のみ(CHECK でも非 main は lock-free)。
  - (2026-07-05 修正・05f28c86d: 以前は `RGENGC_CHECK_MODE >= 2` で全 objspace の local GC に
    no-barrier VM lock を取らせていたが、これは **CHECK verify のバグをマスクしていただけ**だった。
    真因 = `gc_verify_internal_consistency` を **GC の内側**(gc_marks_finish / gc_sweep_finish /
    gc_sweep_compact / gc_start 先頭)で呼び、その verify が `rb_objspace_reachable_objects_from`
    (=GC 中使用不可を自ら rb_bug する非GC用API・barrier VM lock を取る)を呼ぶため、非 main local GC
    が **他 Ractor の global-GC barrier に mid-collection で合流** → global GC が half-collected heap を
    破壊(`inconsistent old slot`/`gc_mode_transition none->sweeping dgg=0`)。**修正 = verify を GC の
    外(gc_exit 後の独立ステップ、during_gc 自然 FALSE)に集約**。これで local GC は safepoint を持たず、
    global GC の barrier が gc_exit まで待つ(設計どおり)。CHECK lock は不要になり撤去。詳細
    [[rlgc-v2-global-vs-local-gc-race]]。)
- **local GC は shareable の生存を traverse に依存しない(mark-only 設計)**。shareable_bits
  でのみ生かされる(local root から届かない)shareable は、pinned-roots パス
  (`rlgc_pinned_roots_mark`)が(old と同じく)mark bit を立てて sweep から守り、
  **traverse はしない**。その unshareable な子は、子自身の **shref ビット**が別途 root として
  mark + traverse して生かす(foreign な子は所有者の責務)。old な shareable は
  uncollectible→mark_bits のコピーで事前マーク済みなので pinned-roots パスは短絡する。
  shref が立ったオブジェクトは root として **辿る**。
- **shareable グラフの 2 不変条件**:
  1. `FL_SHAREABLE ⟺ shareable_bits`。誕生時(newobj)・昇格時
     (`RB_OBJ_SET_SHAREABLE` / `rb_obj_set_shareable_no_assert`)に同時に立て、move が保存し、
     解放時に同時に消す。**「pin されているが FL_SHAREABLE でない」状態はもう無い**。
  2. shareable が参照するのは **shareable、または shref ビットを持つ unshareable** に限る。
     cross-objspace 辺は CHECK モードの verifier が検査し、規律面は WB が担う
     (shareable→unshareable の store は必ず write barrier を通って shref を立てる)。
- **imemo は born-shareable(決定 17、達成済み)**。ment / callcache / callinfo / constcache /
  iseq は `SHAREABLE_IMEMO_NEW`(is_shareable=true)で生成され、誕生時から FL_SHAREABLE +
  shareable_bits を持つ(pinned-without-flag ではなく完全な FL_SHAREABLE)。それらが持つ
  unshareable な子(bmethod の proc、constcache の ice->value、iseq の once/coverage スロット、
  attr.location など)は WB(RB_OBJ_WRITE / RB_OBJ_WRITTEN)経由で記録される shref が守る。
- **列挙モデル(§2.4、達成済み)**: 素名 `rb_objspace_each_objects` は callee 側で VM barrier を
  取り、**upstream セマンティクス = 全 live Ractor の全オブジェクト**(unshareable 含む)を
  歩く。being-created / zombie の objspace は歩かない(列挙 SEGV を閉じる)。foreign の
  中断中 lazy sweep は settle せず(owner の obj_free/dfree をこのスレッドで走らせない)、
  unswept ページの未 mark(死骸)は walk 側で skip。**callback は純 C で yield しないこと**
  が caller 契約(TracePoint 計装・attr/bf コールキャッシュ一掃・coverage・JIT iseq 走査・
  `ObjectSpace.dump_all`・objspace 拡張の memsize_of_all / count_*)。
  自分の objspace だけ見たい caller は `rb_objspace_each_objects_local`。
  他 Ractor の **shareable だけ**を 1 スロット単位で歩く impl 層の
  `rb_gc_impl_each_objects_shareable`(`shareable_bits` 索引)は、ユーザブロックへ
  yield する `ObjectSpace.each_object` の相2 collect 専用(§3.2)。

- **compaction は複数 objspace でも動く(global GC の一部として実装済み、commit 0b23f634c)**:
  `GC.compact` / `GC.auto_compact=` / `GC.verify_compaction_references` は、Ractor が 1 個の
  ときは従来どおり local compaction、複数のときはバリアで全 Ractor を止めた global GC が
  ①全 objspace 移動 → ②全 objspace 参照更新 → ③全 objspace sweep の 3 相で実行する
  (§2.2 末尾)。所有権は変えない。かつては複数 objspace で非移動 full GC に degrade して
  いたが、その制約は撤廃された。
- **既知の設計逸脱が 1 つ**: shareable(isolated-proc)env の特殊変数($~ / $_)。設計意図は
  per-EC(`ec->root_svar`)で、escaped な shareable env については per-EC 化が実装済み
  (`lep_svar_in_env_p` → `ec->root_svar`)。しかし shareable env スロットへ直接書く残存経路
  (`vm_env_write_slowpath` の FL_SHAREABLE 枝)は WB で shref を立てて **GC 安全にしている
  だけ**であり、共有された isolated Proc が cross-Ractor で svar($~)を共有・競合し得る
  **意味的ギャップは未修正**(§2.1)。

上流へ抽出済みの非 RLGC 固有の前提(origin/master にマージ済み): `rb_objspace_each_objects`
の中へ VM barrier を移動、iseq の遅延ロードローダオブジェクトの `RB_OBJ_WRITE` 化、
per-Ractor 宛ての postponed job(`rb_postponed_job_trigger_for_ractor`)。

---

## 1. データ構造

### 1.1 全体図

```
rb_vm_t
  .gc.global_objspace ────→ rb_global_objspace(1 per VM)
                               └ page_pool(空きページ本体 + mmap アリーナ + アリーナ索引)

rb_ractor_t.objspace ───→ rb_objspace(1 per Ractor、main も同じ)
                              ├ heaps[size pool]: 割り当て用 freelist / 使用中ページ /
                              │   生きているページのリスト
                              ├ 世代別 GC の状態(remembered set 等)・mark stack
                              ├ malloc カウンタ(この Ractor の GC トリガ)
                              ├ finalizer テーブル・deferred finalizer
                              ├ GC ノブ(stress / config / measure …)・profile / 統計
                              └ mark_func_data(ObjectSpace 系の mark リダイレクト)

heap_page.objspace ─────→ そのページを所有する rb_objspace
```

「全 objspace の一覧」を持つ専用のデータ構造は**作らない**。objspace は必ずどれかの
Ractor の `r->objspace` であり(終了済み・未引き継ぎの Ractor も、引き継ぎが済むまで
VM の Ractor 一覧に「終了済み」として残す — §2.3)、`vm->ractor.set` を歩けば全部辿れる。
全 objspace の列挙が必要になるのは全 Ractor が停止しているとき(global GC、ObjectSpace の
ダンプ系、VM 終了)だけなので、この walk は常に安全な文脈でしか起きない。main objspace も
`vm->ractor.main_ractor->objspace` で辿れるため、専用ポインタは持たない。

### 1.2 rb_global_objspace = ページプール

```c
typedef struct rb_global_objspace {
    struct {
        rb_nativethread_lock_t lock;     /* ページ単位の操作のみ。保持は短い */
        struct heap_page_body *freelist; /* 返却された空きページ本体 */
        /* mmap した大きなアリーナ(2MiB アライン)群。ここからページ本体を切り出す。
         * アリーナの索引(ソート済み・追加のみ)が「このアドレスはヒープか?」の判定も担う */
        struct page_arena *arenas;
        char *arena_cursor, *arena_end;
    } page_pool;
} rb_global_objspace_t;
```

これだけである。次のものは global に**持たない**:

- 全 objspace の一覧 — VM の Ractor 一覧から辿る(§1.1)
- main objspace へのポインタ — `vm->ractor.main_ractor->objspace` で辿る
- 「Ractor が複数か」のフラグ — VM の multi-Ractor 判定(one-way)をそのまま使う
- 「global GC 中」のフラグ — バリア内で各 objspace に印を付ける(§2.2)
- ヒープのアドレス範囲 — ページプールのアリーナ索引が兼ねる
- 統計カウンタ — objspace ごとの profile で足りる(決定 10)
- チューニングパラメータ(RUBY_GC_* env)— master と同じ file static のまま

ページプールの役割:

- **確保**: freelist から pop → 無ければ現アリーナから切り出し → 無ければ新アリーナを mmap。
- **返却**: sweep で完全に空になったページは即ここへ返す(所有 Ractor は抱え込まない)。
  あるワークロードで膨らんだ Ractor のメモリを、他の・将来の Ractor が再利用できる。
- **アドレス判定**: アリーナは連続した mmap なので、「アリーナ範囲内のアドレスなら、64KiB
  アラインのページヘッダを安全に読める」が成立する。保守的スキャンは「アリーナ索引に
  当たる → ページヘッダの `objspace` を読む → 自分のものなら候補」と一直線になる。
  プール内のページと未切り出し領域はヘッダの objspace を NULL にしておく。
- ロックは leaf(保持中に割り当ても GC もしない)。操作はページ単位なのでオブジェクト
  割り当ての数千分の一以下の頻度であり、競合しない。注意点はページごとに mmap / munmap
  しないこと — それはカーネルの process-wide mmap_lock を直列化点にしてしまう。mmap は
  アリーナ単位(稀)に集約し、ページの再利用はユーザ空間の freelist で行う。

### 1.3 rb_objspace(Ractor ごと)

中身は master の objspace とほぼ同じ。違いは:

- `r->objspace` として全 Ractor が 1 個ずつ持つ(main も)。生成は Ractor 生成時。
- 割り当て状態(freelist・使用中ページ)を size pool ごとのヒープ構造が直接持つ
  (per-Ractor の newobj cache は存在しない。single writer なので不要)。
- 空きページ・アリーナを持たない(ページプールへ)。
- GC ノブ(stress / config / measure …)は objspace ごと。新しい Ractor は生成時に
  親 Ractor の設定を引き継ぐ。
- GC の internal event(GC_START / GC_END_MARK / GC_END_SWEEP / GC_ENTER / GC_EXIT)は
  **有効化した Ractor の objspace の GC でのみ発火**する。他 Ractor の並行 local GC が
  VM 共有の hook list を辿らないための封じ込めであり、当面の確定仕様とする。
- finalizer テーブルは objspace ごとで、**finalizer の実行もその Ractor のスレッドだけ**で
  行う(他の Ractor 上で勝手に走ることはない)。
- malloc カウンタも objspace ごとで、その Ractor の GC トリガを駆動する。
- `mark_func_data`(`ObjectSpace.reachable_objects_from` 等が mark を横取りして参照を列挙
  するためのリダイレクト)は **VM 共有にせず Ractor ごと**に持つ。VM 共有にすると、他の
  Ractor の並行 local GC の mark がリダイレクトに吸われる窓ができてしまう(ゲートで塞ぐ
  羽目になる)。Ractor ごとなら他人の GC を乗っ取る余地が構造的に無い(自分自身の GC との
  重なりだけ、従来どおり during_gc で無視する)。

### 1.4 ページとビットマップ

`heap_page` は master のもの + 次の拡張:

- **`page->objspace`**: 各ページのヘッダに、そのページを所有する objspace へのポインタを
  置く。オブジェクトのアドレスを 64KiB 境界に丸めるとページヘッダが得られるので、任意の
  オブジェクトについて「誰のものか」が 1 ロードで分かる(mark 中の自他判定がこれ)。
  `page->ractor` にしない理由: ページは GC の構造なので gc/ 層を VM の rb_ractor_t に
  依存させない、引き継ぎ待ち(所有 Ractor 不在)の期間や将来の「どの Ractor にも属さない
  共有ヒープ」でも指す先が常に実在する、の 2 点。Ractor が必要なら `objspace->owner` で
  1 段辿る。
- **shref_bits**: **shref**(= **sh**areable-**ref**erenced。shareable から参照されている
  unshareable、§2.1 で定義)に立てるページ上のビットマップ。
- **shareable_bits**: shareable に立てるページ上のビットマップ(意味は「**local GC が
  解放してはならない**」)。FL_SHAREABLE と 1:1 — cc / cme / callinfo 等の VM 内部
  オブジェクトも born-shareable にする(決定 17)ので、特別扱いの対象は無い。
  born-shareable な割り当てと `RB_OBJ_SET_SHAREABLE`(make_shareable)が header の
  フラグと同時に立てる。書き手は常に所有 Ractor のスレッド(封じ込めにより、どちらの
  操作も所有 Ractor 上でしか起きない)なので atomic は不要。bit を消すのは global sweep
  (`shareable_bits &= mark_bits`)と slot の解放時だけ。confined GC はこのビットマップを
  索引に shareable を root として **mark bit を立てる(traverse しない mark-only)**(§2.1)。
- 複数スレッドが書き得るビットマップ(remembered set / shref_bits)への set は atomic CAS、
  ページ単位のフラグはビットフィールドでなく byte にする。非 atomic の `bits[i] |= mask`
  は並行する set を片方消し、関係ないオブジェクトの bit を落とす(young な子が解放される)。

### 1.5 Ractor 生成と VM インフラの置き場

割り当ては常に「実行中のスレッドの Ractor の objspace」へ入る(§3)。したがって Ractor の
生成で親スレッドが「子のための VM インフラ」を作ると、それは**親の objspace** に入る。
子専用の可変構造が親の objspace に居ると、子の local GC からは foreign(辿らない)、
親の local GC からは root が無い(親の物ではないから)、という宙ぶらりんになり、
use-after-free の温床になる。規則:

- 子 Ractor 専用の VM インフラは**子の objspace に確保する**。手段は 2 つ:
  1. **親が子の objspace へ直接確保する**(推奨)。子のスレッドが起動するまで子の
     objspace の writer は親だけなので、生成時に一時的に割り当て先を子へ切り替えるのは
     single-writer を破らない(stress GC が走っても、封じ込めガードにより空ヒープへの
     誤 root GC は no-op)。Thread / root Fiber の wrapper はこの方法で生成時から
     子の物にする — **オブジェクトの同一性が生涯変わらない**ことが重要
     (途中で作り直すと、起動初期に C レベルで掴まれた旧 wrapper と以後の wrapper が
     別オブジェクトになり、thread instrumentation のような identity ベースの API が壊れる)。
  2. 親の objspace に作られた物を**子の起動時に子側で作り直す**(割り込みキュー・
     mask スタックなど、identity が外部に出ない物はこちらで足りる)。
- Ractor 関連のインフラを新設するときは必ず「これはどの objspace に入り、誰の root から
  辿られるか」を確認する。レビュー観点として固定する。

## 2. mark & sweep 戦略

### 2.1 local GC — 自分だけを、止めずに回収する

各 Ractor は自分の objspace に対して minor / major GC を行う。**VM ロックもバリアも取らず、
他の Ractor の実行とも他の Ractor の local GC とも並行に走る。**

**root**: その Ractor が実行のために持っている参照の一式。具体的には各スレッド・fiber の
VM スタックとマシンスタック(保守的)、Ractor ローカル変数、この objspace の finalizer
テーブル。minor GC ではこれに remembered set が加わる。さらに RLGC 特有の root として
**shref(shref_bits の立ったオブジェクト)**が加わる(後述)。
他の Ractor のスタックは歩かない(並行実行中で不安定だから)。

**mark**: 自分の objspace の中だけを辿る。他の objspace のオブジェクトに行き当たったら
「生きている葉」として扱い、**辿らずに止まる**。相手の生死は相手の所有者(あるいは
global GC)が決める。**shareable の unshareable な子の生存を、local GC は「shareable を
辿ること」に依存しない** — それを保証するのは子自身に立った **shref ビット**である
(shref は root として別途 mark + traverse される、後述)。理由: ある shareable s は
自分の local root からは到達できず、shareable_bits でのみ生かされる(他 objspace から
参照されているだけ)ことがあり、その s は下記の pinned-roots パスで **mark bit を
立てるだけ・traverse しない**扱いになるからである(§2.1 手順 3.f、`rlgc_pinned_roots_mark`)。
逆に、local root から通常辺で到達した同 objspace の shareable は普通に traverse され得る
(それは安全だが冗長で、子の生存はどのみち shref が独立に担保している)。この設計により
「shareable の mark 関数が他 objspace に散る foreign な子へ踏み込む」事故も、shareable の
可変スロットを他 Ractor と競合して読むことも避けられる。ユーザ定義 T_DATA の `dmark` は
決定 16 に従う(宣言済みの型のみ local で mark し、未宣言の型は global GC に委ねる)。

**shref と shref_bits**: shareable から参照されている unshareable を **shref**
(**sh**areable-**ref**erenced)と呼ぶ — shareable の世界から、ある Ractor の私有グラフへ
参照が踏み込んでくる入口である(`Ractor.make_shareable` した構造の直下、送信中メッセージの
中身など)。封じ込めの例外的な向きはここに集中する: 親の shareable s は**他の objspace に
居るかもしれない**ので、shref u の所有者の local GC は s を辿らず(foreign だから)、
u への参照を**見つけられない**。そこで「`s.f = u` という代入が起きた瞬間に、u のページの
shref_bits に印を付け、所有者の local GC は shref を root 扱いする」ことで u を生かす。
これが維持できる理由も封じ込めにある: `s.f = u` と書けるのは u への参照を持つスレッド、
つまり **u の所有 Ractor 自身**だけ。だから write barrier は「自分のページに印を付ける」
だけでよく、他の Ractor のビットマップに書きに行く必要がない。
shref_bits は global GC の full mark のたびに全消去して付け直す(write barrier が維持し、
global GC が掃除する)。印の付け漏れ = 即誤回収、なのでここが封じ込めモデルの急所だが、
**s→u store の親になる shareable は常に WB-protected**(決定 13: WB-unprotected な
shareable は unshareable を参照しない)なので、「WB を通らない s→u store」は存在しない。
つまり shref の完全性が要求する規律は、既存の世代別 WB が要求するもの(バルクコピーの
後は remember を打つ、等)と同一であり、shref のための新しい監査項目は増えない。

**s→u が生じる場所(例外リスト)**: 原則として shareable から参照されるものは shareable に
する(決定 17)ので、s→u の例外は次に限られる。それぞれ生存機構が違う:

- **Class / Module のインスタンス変数・定数**に入る unshareable 値。これらは main Ractor
  からしかアクセスできない(既存の Ractor 仕様)ので「main の unshareable」であり、書くのも
  main 自身 → **shref**(WB が main のページに立てる。上の規律どおり)。同型(WB が書く
  s→u → shref)のものに: **定数インラインキャッシュ**(ice->value)、**singleton class →
  attached object**、**bmethod の cme → unshareable proc**(define_method。起動は定義
  Ractor のみ)。verifier(GC.verify_internal_consistency)はこれらの辺を辿り、
  unshareable 側に shref 記録があることを検査する。
- **送信中メッセージ**(§4.2): 受信側のキューから、送信側 objspace の snapshot への参照。
  → **shref**(送信時に送信側が自分のページに立てる)。
- **Ractor オブジェクト**(shareable)は、その Ractor 専属の unshareable(`Ractor#[]` の
  storage、stdin / stdout / stderr など)を参照する。これは shref では扱わず、所有 Ractor の
  **root** にする(手順 3.c: rb_ractor_t から直接辿る。Ractor オブジェクト自体は生成元の
  objspace に居て、所有者から見ると foreign なので、オブジェクト経由ではなく C 構造体から
  root を引くのが正しい)。
- **shareable な env(isolate 済み proc)のフレームの特殊変数**($~ / $_ の svar)。
  env の svar slot に置くと、proc を共有する全 Ractor が 1 つの unshareable svar を
  相互に読み書きしてしまう(封じ込めの「u に書けるのは所有者だけ」が崩れる上、$~ が
  Ractor 間で混ざる)。そこで lep が shareable env のフレームは特殊変数を **per-EC
  (`ec->root_svar`)に置く** — 割当て分類は「root で守る(EC = Ractor の C 構造)」。
  cref は従来どおり env slot に残る。
  **【既知の設計逸脱・未修正】** この per-EC 化は escaped な shareable env については
  実装済み(`lep_svar_in_env_p` → `ec->root_svar`。vm_insnhelper.c)。しかし shareable env
  スロットへ直接 svar を書き込む残存経路(`vm_env_write_slowpath` の FL_SHAREABLE 枝)が
  あり、そこは svar 値が unshareable なら **write barrier で shref を立てて GC 安全に
  しているだけ**(WB_REQUIRED も維持して以後の store も必ずバリアを通す)。つまり
  「延命は正しいが意味は正しくない」状態で、共有された isolated Proc が cross-Ractor で
  同じ svar スロット($~)を競合・共有し得る **意味的なギャップは残っている**。正しくは
  全経路を per-EC に寄せるべきで、これは将来修正する既知バグ。
- 他にもあり得る(候補: iseq が持つ実行時の可変スロット — once キャッシュ、coverage 等)。
  実装時に「shareable の mark 関数が辿る先」を監査し、見つけたものはこのリストに追加して
  「shareable にする / shref で守る(WB で書かれる物)/ root で守る(所有者の構造から
  辿れる物)」のどれかに割り当てる。

shref のライフサイクル: **オブジェクトが shareable に昇格したら shref 記録は廃止**
(rb_gc_impl_obj_became_shareable がクリアする — 以後は shareable pin が生存を担い、
shref は常に「unshareable を指す」を保つ)。なお u→u の機械的例外が一つ:
**box->top_self**(全 thread の th->top_self が objspace を跨いで参照する VM 永続
オブジェクト。box の root が生涯 root するので生存は独立に保証され、verifier は
明示的に許可する)。

**sweep**: lazy でよい。ただし:

- **shareable は解放しない。** 他の objspace から参照されているかどうかを local GC は
  判定できないから。shareable の回収は global GC だけが行う。
  (クラスはもともと shareable。メソッドエントリ・コールキャッシュ等の VM 内部
  オブジェクトも born-shareable にする(決定 17)ので、同じ扱いに自然に含まれる。)
  実現方法は「**mark フェーズで shareable_bits を索引に mark bit を立てる(root 扱い)**」
  (shref と同じ walk。ただし shareable は mark + 老化だけで **traverse はしない** —
  §2.1 mark 参照)。sweep 側でビット演算により除外する方式は採らない —
  生かしたオブジェクトがマークされないと age が進まず、「old の親 → 永遠に young の子」
  という remember されない O→Y エッジが生じて世代不変条件
  (GC.verify_internal_consistency)と衝突する。mark で生かせば shareable 自身は普通に
  老化・昇格する(その unshareable な子は traversal ではなく子の shref ビットが生かす)。
  滞留計数(§2.2)は「この root 化で**新たに**マークされた数」(= 自分の root からは
  届かなかった shareable の数)として同じ walk で得られる。
  例外として、Ractor が 1 個しか居なければ local GC = 全体 GC なのでこの root 化ごと
  スキップし、shareable も普通に死ぬ。引き継ぎ(§2.3)で objspace は main 1 個に戻り
  得るので、この最適化は復帰可能にしておく。
- 完全に空になったページは**即ページプールへ返す**(直近 1 ページの保持などの
  ヒステリシスは実装の裁量)。
- finalizer 付きオブジェクトの zombie 化と deferred finalizer の実行は、この objspace の
  所有 Ractor のスレッドだけで行う。**登録も所有 objspace からのみ**: 他の Ractor の
  オブジェクト(shareable 含む)に `define_finalizer` しようとしたらエラー(決定 12)。
  これで finalizer は登録から実行まで完全に Ractor 内に閉じ、cross-objspace の置き場
  問題が消える。

#### 手順: local GC

minor / major とも自スレッドで実行し、ロックもバリアも取らない。master の GC との差分に
★を付ける。
(実装は 2 段階を踏んだ: M1a では従来どおり VM lock + barrier の下で動かして封じ込めの
正しさを固め、非 main Ractor の local GC が「ロックもバリアも取らない」のは M1b で達成済み
— §5 の順序と理由を参照。ロック模型の全体は「現在の到達点」参照。通常ビルドで完全無ロック
なのは非 main Ractor の local GC だけで、main objspace の local GC は VM グローバル root を
歩くため常に no-barrier の VM lock を取る(他 Ractor は止めない)。global GC は local GC では
なく別 mode で、VM lock + barrier を取る。`RGENGC_CHECK_MODE ≥ 2` では非 main Ractor の
local GC も verify のため no-barrier VM lock を取る。GC の内側では VM lock を決して取らない —
待機者は保留中バリアに合流するので、mark/sweep 途中の合流は半回収ヒープを global GC に晒す。
GC 経路が触る VM 共有構造は専用の native mutex(id2ref・registered globals・generic fields)か
ページプールのロックで守る。)

0. 前提: 自分の lazy sweep が残っていれば先に完走させる(master と同じ)。`during_gc` を
   立てて再入を防ぐ。incremental marking は objspace が複数ある間は使わない★
   (単一 Ractor のときだけ master のまま。2 個目の Ractor を作る時点で、進行中の
   incremental marking は完走させてから移行する)。
1. minor / major の選択は master と同じ基準(自分の旧世代の増加・malloc 量・明示指定)。
   ★major は local のまま実行する — 目的は自分の unshareable の旧世代の回収であり、
   STW は要らない。global GC の起動は別の基準(shareable の増加・滞留、§2.2)で判断し、
   その条件を満たしているときだけ local major の代わりに global GC を要求する。
2. mark の準備:
   - minor: master と同じ。旧世代(昇格済み + remembered な wb-unprotected)は生存前提
     から始め、mark bit はクリアしない。
   - major: 自分の全ページの mark / marking / uncollectible / remembered bit をクリア
     (master の major と同じ)。★ただし shref_bits はクリアしない — 「外の shareable が
     自分の誰を参照しているか」は自分からは列挙できないため、shref の再計算は global GC に
     しかできない。local major は WB が維持してきた値をそのまま信じる。
3. root を mark する。すべて「自分のもの」だけ★:
   a. 自 Ractor の各スレッド・各 fiber の VM スタック / EC。suspended な root fiber も
      wrapper 経由でなく直接辿る★(wrapper オブジェクトは他 objspace に居ることがある)。
   b. 自スレッドのマシンスタック・レジスタ(保守的)。word ごとに「ページプールの
      アリーナ範囲内か → ページヘッダの objspace == 自分か → 有効な slot 先頭か」で
      ★**自分の**オブジェクトだけを候補にし、mark + pin する。foreign を指す word は
      無視する(その生存は所有者か global GC の責任)。
   c. Ractor self と Ractor-local storage。
   d. 自 objspace の finalizer テーブル(値を pin)。
   e. VM-global の registered roots★(`rb_global_variable` / `rb_gc_register_mark_object`)。
      登録リストは VM に 1 つのまま、**全 objspace の root 走査が C レベルで全エントリを
      なめる** — mark 側の foreign-skip が「自分の objspace のエントリ」だけを自然に
      選別する(リストのチャンク自体も登録した Ractor の objspace 生まれなので、所有者が
      mark して生かす)。こうしないと「VM グローバルな表に入れた worker のオブジェクトを
      誰も root にしない」という穴が開く(lazy 初期化の static 変数を worker が先に踏む
      ケースで実証済み: `clone(freeze: true)` の freeze_true_hash 等)。
      per-objspace の登録表に分割する案は不採用 — `rb_global_variable(VALUE *)` は
      アドレス登録で、スロットには後から**別の objspace の値**が代入され得るため、
      表の所有 objspace を決められない。走査コストは O(全登録数) × objspace 数だが、
      登録物は定数規模(チューニングは M5)。
   f. ★shareable と shref を root 化(`rlgc_pinned_roots_mark`):
      `has_shareable_objects` / `has_shref_objects` の立った自分のページを走査し、
      `(shareable_bits | shref_bits) & ~mark_bits` の立ったオブジェクトだけを処理する
      (bit の在処は自分のページなので走査は自己完結)。すでにマーク済み — traversal で
      到達済み、または old で事前マーク済み(minor では uncollectible→mark_bits コピー、
      major の前 cycle で昇格したもの)— は短絡する。
      - **shref**(unshareable): `gc_mark` で mark **かつ traverse**(remembered な
        old→young ターゲットと同じ。これを辿らないと、参照元の shareable を辿らない
        本設計では到達不能に見えてしまう)。
      - **shareable**: mark bit を立てて `gc_aging`(**老化のみ、traverse しない**)。
      このとき「新たにマークされた shareable の数」を数えておく — 滞留推定(§2.2)。
   g. minor のみ: remembered set(master と同じ。remembered ページの旧世代の子を再走査し、
      wb-unprotected な uncollectible も再走査する)。
4. 推移的 mark(mark stack が空になるまで):
   - 子 c を辿る前に★ `GET_HEAP_PAGE(c)->objspace` を見る。自分でなければ**何もしない**
     (bit も立てず、子も辿らない)。これが封じ込めの実行点。
   - 自分のものなら master と同じ: mark bit を立て、age を進めて昇格を判定し、子を積む。
     local root からこの通常辺で到達した同 objspace の shareable は普通に辿られる(安全)。
     ただし設計は shareable の traversal に依存せず、local root から届かない shareable は
     手順 3.f の pinned-roots パスで mark-only(辿らない)になる — shareable の unshareable な
     子の生存を保証するのは常に shref である(§2.1 mark)。weak 参照は後処理用に積む。
   - bitmap の書き込み規律★: mark / marking / uncollectible 系を触るのは自スレッドだけ
     (plain store 可)。remembered / shref は他 Ractor の WB が並行に書くので atomic。
5. mark の終了処理: weak 参照のうち対象が**自分の** unmarked のものをクリアする。
   ★対象が foreign のものは触らない(global GC が処理する)。世代カウンタの更新は
   master と同じ。
6. sweep(lazy 可。master の枠組みに以下の差分):
   - shareable は手順 3.f の root 化により必ずマーク済みなので、sweep 自体は master の
     「unmarked を解放する」のままでよい(★sweep に shareable の特別扱いは無い)。
   - finalizer 持ちは zombie 化して自分の deferred リストへ(実行も自スレッド)。
   - ★解放した slot の shareable / shref ビットはクリアする(再利用に引き継がない)。
   - ★完全に空になったページは `page->objspace = NULL` にして global page pool へ返す。
7. 終了: `during_gc` を下ろし、deferred finalizer を通常の機構で実行する。

#### 手順: write barrier(GC の外で動く維持機構)

`RB_OBJ_WRITE(a, &slot, b)` のとき:

1. 世代: a が旧世代で b が新世代なら a を remember する(master と同じ)。ただし★
   shareable への store は他 Ractor のスレッドからも来るので、remembered_bits と
   ページフラグは atomic に立てる。
2. ★shref: a が shareable で b が unshareable なら、b のページの shref_bits を立てる。
   封じ込めにより、この store を実行できるのは b の所有 Ractor のスレッドだけなので、
   これは常に「自分のページへの書き込み」で済む。

前提(決定 13): s→u エッジの親になる shareable は必ず WB-protected — つまり
WB-unprotected な shareable は unshareable を参照しない(FROZEN_SHAREABLE 系の T_DATA は
make_shareable 時に「参照先がすべて shareable」を検査済みのうえ frozen であり、
shareable への wb_unprotect は assert で禁じる)。よって上の 2 経路が WB で漏れなく
踏まれることは、既存の世代別 WB と同じ規律で保証される。

### 2.2 global GC — 全部を止めて、全部を回収する

VM バリアで全 Ractor を停止し、全 objspace を一括で mark & sweep する。shareable・
VM 内部オブジェクト・「自分からは辿れないが他の objspace からは生きている」ものを
到達性どおりに回収できる唯一の機会である。

**起動要件は local GC とは独立**。local major が「自分の旧世代(unshareable)が育った」
ことを見るのに対し、global GC は「**shareable の世界が育った**」ことを見る — shareable は
local GC では回収できず、global GC まで滞留し続けるからである。起動条件(いずれかを
満たすと、気づいた Ractor が driver になって要求する):

1. **shareable の増加**: 自分の objspace の shareable 数 `shareable_objects` が
   `shareable_objects_limit` を超えた。旧世代の `old_objects > old_objects_limit` と
   同型のルールである。計数は born-shareable な割り当てと `RB_OBJ_SET_SHAREABLE` での
   increment(どちらも所有スレッド上、plain でよい)+ 引き継ぎ併合(§2.3)での加算。
   local GC は shareable を解放しないので、この計数は global GC 間で正確な生存数を保つ。
   limit は global sweep が shareable_bits の popcount で正確な生存数を取り直し、
   `生存数 × factor(既定 2.0 — 旧世代の GC_HEAP_OLDOBJECT_LIMIT_FACTOR と同じ)+ 下限`
   で再設定する(下限が無いと新しい Ractor が 1 → 2 で即発火してしまう)。
2. **滞留の観測**: 自分の local GC が数えている「shareable の root 化(§2.1 手順 3.f)で
   **新たに**マークされた数」 — 自分の root からは届かない shareable、すなわち自分の
   ヒープに滞留している「local では回収できないゴミ」の上界推定(cc / cme 等の VM 内部
   オブジェクトも含む)— の比率が閾値を超えた。
3. **終了済み・未 join の Ractor の objspace が保持するページ総量**が閾値を超えた
   (回収・併合できるのは global GC だけ、§2.3)。個数ではなく量で測る — 小さな
   Ractor を大量に使い捨てるパターンで個数基準はすぐ発火してしまうし、困るのは
   結局メモリなので。VM が retire / 併合時に増減させる合計ページ数
   (`vm->gc.zombie_total_pages`)を見る。既定の閾値・下限は M5 で確定する。
4. 明示(`GC.start`)と VM 終了。

判定に使う計数はすべて**自分の objspace のもの**なので、global な状態も他 objspace の
読み取りも要らない。条件 1 は per-Ractor 判定のため「全 Ractor が一様に 2 倍未満ずつ
育つ」ケースを取りこぼすが、それは条件 2(滞留比率)が拾う。係数・下限の既定値は
実装しながら調整する(M5)。global GC は STW を伴うので頻度が性能に直結する(毎 major
昇格にした場合の実測例: N=8 で STW コスト ~13%)— 起動条件をこのように分離するのが
その対策である。

- barrier 内で driver はまず全 objspace に「global GC 中」の印を付ける(全員止まっている
  ので安全)。mark / sweep の各判定はこの per-objspace の印を見る。global 専用の状態は
  持たない。barrier を出る前に全部下ろす。
- mark は封じ込めを解除して全 objspace を 1 本の mark stack で辿る。shref_bits は全消去
  してこの full mark 中に付け直す。
- **root は全 objspace 分を漏れなく**。「sweep は全空間一括なのに root mark が一部の
  objspace の分しか辿られない」という非対称は、そのまま use-after-free になる(この設計で
  最も事故りやすい点)。そこで「objspace の root 一覧」を 1 箇所に表として持ち、local GC と
  global GC が**同じ表**から root を引く実装にする(片方にだけ root を足して漏らす事故を
  構造的に防ぐ)。
- sweep も barrier 内で全 objspace に対して行う。空きページはページプールへ。

なお STW 中は並行する書き手が居ないので、driver が他 objspace のビットマップへ書く
(pin の付け直し等)のは安全である。local GC 中は不可。この区別のための述語を 1 つ用意する
(「いま local GC か?」)。

#### 手順: global GC

1. 契機: 上記の起動条件(shareable の増加・滞留・zombie Ractor の堆積・明示)を満たした
   Ractor が driver になる。Ractor が 1 個のときは local major で足りるので起動しない。
2. VM バリアを取る。進行中の local GC は完走を待つ(local GC は途中でバリアに合流
   しない)。バリア成立後は、mutator も他の GC も一切動いていない。
3. 全 objspace の残っている lazy sweep を driver が完走させる(STW 中なので他人の
   objspace を触って安全。mark bit の意味を次のクリアの前に確定させるため)。
4. 全 objspace に「global GC 中」の印を付ける。
5. クリア — **全 objspace の全ページ**について、mark / marking / uncollectible /
   remembered / shref_bits をクリアし、世代カウンタをリセットする(major のクリア +
   shref)。全列挙は VM の Ractor 一覧で行う(終了済み・未引き継ぎの Ractor を含む)。
   ※ ここで objspace を 1 つでも取りこぼすと、stale な mark bit の残ったオブジェクトが
   「既マーク」扱いになって子が辿られず、使用中の表(メソッドキャッシュ等)が sweep されて
   UAF に至る — 最悪の壊れ方をするので、全列挙の完全性はこの設計の生命線。
6. root を mark — root 表(local GC と共通の一覧)を**全 Ractor / 全 objspace 分**処理する:
   - VM グローバル root(vm 本体、グローバル変数、trap、…)
   - 全 Ractor のスレッド / fiber のスタック(マシンスタックの保守的 scan は、word の
     所有 objspace をアリーナ索引 → ページヘッダで特定し、**その objspace の**ページに
     mark + pin する)
   - 全 objspace の finalizer テーブルと registered roots
   - 全 Ractor のキュー / port 上の送信中メッセージ: クリア(5)で pin が消えているので、
     shref を立て直して mark する。受信側で実体化中のメッセージも同様。
   - suspended な root fiber
7. 統一 mark: mark stack は 1 本、封じ込めは解除。子がどの objspace に居ても、その
   ページに bit を立てて辿る(STW なので他空間のビットマップへの書き込みも安全)。
   mark 中に shareable → unshareable のエッジを踏んだら、その場で子の shref_bits を
   立て直す — これが shref の再計算で、以後は WB が次の global GC まで維持する。
8. weak 参照を全空間分処理する。
9. global sweep — バリア内で完結させ、lazy にしない。全 objspace の全ページについて:
   - ここでは shareable も解放する(統一 mark の到達性は正確): 解放候補 =
     `有効 slot & ~mark_bits`(shareable_bits は見ない。cc / cme 等も shareable として
     ここで回収される)。ページごとに `shareable_bits &= mark_bits` と畳んで生存分だけに
     更新する。
   - zombie は各 objspace の deferred リストへ(実行はその所有 Ractor のスレッド。
     終了済み objspace の分は引き継いだ側が実行する)。
   - 空ページはページプールへ返す。
   - 後始末: この cycle で Ractor オブジェクトが回収された「終了済み・未 join」の
     objspace を main に併合する(§2.3)。
10. 全 objspace の「global GC 中」の印を下ろし、バリアを解除する。

**compaction について**(実装済み commit 0b23f634c): GC.compact / GC.auto_compact= /
GC.verify_compaction_references は、オブジェクトの移動が全空間の参照更新を要する。
objspace が 1 個のときは従来どおり local compaction。**複数のときは global GC(STW)の
一部として実行する**。single-objspace の「move → 参照更新 → free」を、全 Ractor を
バリアで止めたうえで全 objspace に **相ごとにループ**して適用する:

1. **相①(move)**: 全 objspace を relocate し、移動元に T_MOVED forwarding を残す。
2. **相②(update)**: 全 objspace の参照を更新する。相①で全 forwarding が確定しているので、
   別 objspace の移動済みオブジェクトを指す cross-objspace 参照も解決できる。
3. **相③(free)**: 全 objspace を page-sweep し、移動元ページと死オブジェクトを解放する。

所有権は変えない。バリア内なので参照更新は安全。**per-objspace で move/free を交互に
実行してはならない**(ある objspace の相③ free が別 objspace の相② update より先に T_MOVED
source を解放すると壊れる)ので、必ず相ごとに全 objspace をループする。実装上の要点
(mark/location/pin の objspace-context は driver の flag を見る、参照更新の VM-global 半分は
1 回だけ、`rb_gc_impl_location` は全 objspace の T_MOVED を辿る 等)はコミットログ参照。

### 2.3 Ractor 終了 — objspace は join した者が、いなければ main が引き継ぐ

終了した Ractor の objspace は、その場では誰にも併合されず、終了済みの Ractor に
ぶら下がったまま残る(ブロックの戻り値もそこに入っている)。専用の管理リストは作らない。
引き継ぎが実行されるのは次のどちらかの時点で、**どちらも「引き継ぐ側が安全に自分の
ヒープを触れる文脈」に最初からある**:

- **join された場合**: `Ractor#value` を呼んだ Ractor R は、相手の終了を待ったあと、
  **R 自身のスレッドの中で**死んだ objspace を自分のヒープに併合し、それから戻り値を返す
  (§4.3)。併合は自分のヒープへの書き込みなので single writer はそのまま守られる。
  value の呼び出し自体が引き継ぎの実行場所であり、受け渡しの仕掛けは何も要らない。
- **join されないまま Ractor オブジェクトが回収された場合**: Ractor オブジェクトは
  shareable なので、回収するのは通常 global GC(STW 中)= ここが「もう誰も join
  できない」ことの判定を兼ねる。ractor_free は zombie 帳簿(下記)の entry の
  owner slot を NULL にする(= disown; 専用の侵入リストは持たない)だけにし、
  **main 宛て postponed job(決定 18)をトリガ**する。実際の併合は main が自分の
  次の safepoint で **main 自身のスレッド**として行う。これで 3 経路すべて
  (value = joiner / orphan = main / shutdown = main)が「併合は継承者自身の
  スレッドで」という同一の形になり、「STW 中だけ single writer が免除される」
  という特例が設計から消える。併合されるまでの間も disown 済み objspace は
  zombie 帳簿に残り、global GC の列挙から漏れない。fork の子では disown 済み
  entry が残っていれば子の main へ再トリガする。shutdown は disown 済みを同期
  drain してから、残り(owner slot 付き)を従来どおり併合する。

  例外が一つ: **起動前に生成が失敗した Ractor**(objspace は出来たがスレッドは
  一度も走らなかった)は retire を経ないので帳簿に居らず、しかも単一 objspace の
  世界で local GC に回収され得る。この場合は ractor_free が sweep 内から slot 無し
  entry を帳簿へ直接 push する(帳簿は plain realloc で伸ばす — sweep 内では
  会計付きアロケータを使えない)。push の瞬間に世界が複数 objspace 扱いへ変わる
  ため、sweep の pinned-free 検査は「いまの世界」ではなく「この cycle の mark が
  pin walk を実行したか」(`rlgc.last_cycle_pinned`; global の統一 mark は pin
  しないので global cycle が各 objspace で 0 化)に束縛している。

併合の作業内容はどちらも同じ: ページを size pool ごとに引き継ぎ側のヒープへ繋ぎ替え、
各ページの `page->objspace` を書き換え、finalizer テーブル・zombie・カウンタ類を併合し、
空きページはページプールへ返し、objspace の殻を解放する。**併合の間は継承側の GC を
禁止する**(per-objspace の local disable — §3.1。generic_fields の表併合なら
`rb_gc_local_disable_no_rest`、ページ繋ぎ替えなら `rb_gc_impl_gc_disable(dst, false)`)—
併合内部の表挿入は確保を伴い得るので、放っておくと継承側の local GC がページ半繋ぎの
状態で起動し得る。死んだ Ractor の deferred
finalizer は以後**引き継いだ側のスレッド**が実行する(終了した Ractor にはそれを実行する
スレッドが無い — 放置すると zombie が永遠に残り、objspace は決して空にならない。
引き継ぎがその答えになっている)。

終了から引き継ぎまでの間:

- この objspace を local GC する者は居ない(所有者不在)。中のゴミは global GC が回収し
  続ける。戻り値とそこから辿れるものは、終了済み Ractor 経由で生きている。
- 「全 objspace は列挙から漏れない」を保つため、終了した Ractor の objspace は
  `vm->gc.zombie_objspaces`(objspace と、継承時にクリアする owner slot =
  `&r->objspace` の組)に登録し、引き継ぎ完了で外す。プロセスで言う zombie と同じ
  構図(join = wait、main = init への reparent)。Ractor 自体は終了時に VM の一覧から
  外す — 一覧に残す案も等価だが、その場合は Ractor 数の計数・バリア参加・単一 Ractor
  判定のすべてに「終了済みを除く」例外が要る。帳簿の本質は全 objspace 列挙の完全性で、
  それは別帳簿で満たせるので、計数系を無傷に保てる方を採る。orphan 化(Ractor
  オブジェクト回収)で rb_ractor_t が解放されたら entry の owner slot は NULL に
  しておく(shutdown の一括併合は slot なしでも併合できる形にする)。
- 封じ込めにより、この objspace の unshareable に外から刺さる参照は無い(戻り値は併合後に
  しか Ruby コードへ返らない、§4.3)。外から参照され得るのは shareable だけで、それは
  誰の local GC も解放しない。だからこの待機状態は安全。

fork(決定 8)は「子プロセスで他の全 Ractor をこの『未 join 終了』扱いにする」、VM 終了
(決定 9)は「全 Ractor を終了させて main が引き継ぐ」で、どちらも専用機構なしにこの上に
乗る。Ractor が main 1 個に戻れば local GC = 全体 GC なので shareable も回収できる。

### 2.4 VM 共有テーブルと local GC

local GC はロックを取らずに走るため、「local GC のコードパスが読み書きする VM 共有の
可変構造」は、一つずつ扱いを決めておく必要がある(漏れ = 並行クラッシュ)。原則は 3 分類:

1. **shareable しか載らない表は、同期不要**。fstring(frozen string interning)表や
   dynamic symbol 表のエントリは shareable であり、local GC は shareable を解放しない
   (shareable_bits)。つまり**これらの表からの削除は global GC(STW)中にしか起きない**
   ので、mutator 側の挿入(既存の同期のまま)と local GC が競合する経路が存在しない。

   注意: エントリだけでなく**表の入れ物(コンテナオブジェクト)自体も shareable で
   なければならない**。concurrent set(fstring 表・sym 表の実体)は resize 時に
   「resize したスレッド」の objspace に新世代の T_DATA を確保して C グローバルを
   差し替える。worker の objspace に生まれた表は worker の local root から届かず、
   main から見れば foreign なので、shareable 化しないと worker の local GC が
   生きた表ごと回収してしまう(実際に M1a で fstring 表がこの経路で壊れた)。
   同型: symbol の id→(str,sym) 逆引きに使う `id_entry_list`(T_DATA)も intern した
   Ractor の objspace に生まれ、main 在住の `symbols->ids` Array からしか参照されない。
   どちらも born-shareable にして所有 objspace の pin で守る。代償として、resize で
   不要になった旧世代の表は global GC まで回収されない(retention)が、旧世代の合計は
   最終サイズの定数倍で抑えられるので許容する。
   一般則: **「VM グローバル(C global / VM 構造体)から届く GC オブジェクトを
   main 以外のスレッドが確保する」箇所は、必ず born-shareable にする**(決定 17 の系)。
   born-shareable にできない(意味的に unshareable な)ものは、§2.1 手順 3.e の
   VM-global 登録リスト(全 objspace が C 走査)に載せる — 例: `clone(freeze:)` の
   freeze_true/false_hash や `<cfunc>` 文字列のような lazy 初期化 static。
2. **オブジェクトに紐づく表は per-objspace に分割する**。generic ivar の表
   (非 T_OBJECT ホストの ivar 置き場)はホストごとのエントリなので、ホストの所有
   objspace の表に分ける。挿入・削除(local sweep での解放時)・mark 中の参照がすべて
   single writer に戻り、同期が消える。
3. **分割できない表は短い専用ロック**。`object_id` の対応表(id → obj)は「任意の id を
   引ける」ことが意味なので VM 全体で 1 つ。id を持つ unshareable の解放(local sweep)
   時の削除と、`_id2ref` / id 付与の挿入・参照を専用ロックで同期する(global GC バリアに
   合流しない種類のロックにすること — local GC の途中でバリアに巻き込まれてはならない。
   頻度は「id を持つオブジェクトの解放時」だけなので低い)。

実装では「local GC から触る VM 共有構造」を列挙し、必ずこの 3 分類のどれかに割り当てる。

補足: **cross-Ractor のヒープ走査**。iseq/callcache 等は born-shareable(決定 17)なので、
ある Ractor の iseq を触る操作(TracePoint 計装 `rb_iseq_trace_set_all`・attr/bf コール
キャッシュ一掃・coverage 削除)は「自分の objspace の全オブジェクト + **他の生きている
Ractor の shareable**」を歩く必要がある(per-objspace のままだと worker で TracePoint を
enable しても main の iseq が計装されない)。これを `rb_objspace_each_objects` 自身が担う:

- **barrier は callee 側**が取る(`rb_objspace_each_objects` の中で `rb_vm_barrier`)。
  ヒープ walk は「ページ集合が動かないこと」を要求し、他 Ractor の STW GC が walk 途中に
   page を free / move すると壊れるため。これは master でも正しい硬化なので上流に取り込んだ
  (`gc: take the VM barrier inside rb_objspace_each_objects`)。呼び出し側は自前の
  `RB_VM_LOCKING+rb_vm_barrier` を持たない(上流の iseq sweep 群と逐語一致)。
- **全 live Ractor の全オブジェクト**を渡す(upstream セマンティクス)。callback は
  純 C・yield 無しが契約で、型チェック(iseq/cc/クラス等)で対象を選別する — barrier 下で
  foreign unshareable の header/型を読むのは安全。foreign の中断中 lazy sweep は
  settle しない(B-6)ので、unswept ページは 1 スロット単位で歩き未 mark(死骸)を skip。
  yield が要る caller(`ObjectSpace.each_object`)はこの walk を使えず、impl 層の
  shareable-only walk で collect-then-yield する(§3.2)。
- **being-created / zombie の objspace は歩かない**(生成途中・撤収途中で heap が
  walkable でない — 従来の全 objspace 走査(`rb_gc_vm_each_objspace` 経由)がここを
  踏んで発生していた列挙 SEGV を、生きている Ractor だけに絞ることで閉じる)。
- cross-Ractor 走査の caller は **callback が純 C で yield しないものだけ**
  (TracePoint 計装 `rb_iseq_trace_set_all`・attr/bf コールキャッシュ一掃・coverage 削除・
  JIT iseq 走査・dump_all / objspace 拡張)。
- caller が「自分の objspace だけを見たい」場合は **`rb_objspace_each_objects_local`**
  (barrier は取るが cross-Ractor 走査はしない)。JIT の iseq 走査 / method coverage はこれ。
- **素名 `rb_objspace_each_objects` = 全 live Ractor の全オブジェクト**(callback 純 C・
  barrier 下・foreign は settle せず unswept-dead skip)。TracePoint 計装・cc 一掃・coverage・
  JIT iseq 走査・dump_all・objspace 拡張がこれ。
- **`ObjectSpace.each_object` は cross-Ractor 化済み(§3.2、collect-then-yield)**。ユーザ
  ブロックへ yield するので単純な cross-Ractor 走査は使えない — 他 Ractor の shareable を
  barrier 保持中に yield すると、その yield が safepoint(trace 有効時など)で **同 Ractor の
  別スレッド**に制御を渡し、per-Ractor VM lock を乱す(`vm_lock_leave` の `vm_locked` アサート
  / production では lock 不整合)/barrier を早期終了させる。だから barrier 下では collect
  だけ行い、yield は barrier の外で行う(§3.2)。

旧 `rb_objspace_each_objects_all`(全 objspace を無差別に走査)は撤去済み。素名
`rb_objspace_each_objects` がその安全形(barrier 下・live set のみ・creating/zombie skip・
foreign は settle せず unswept-dead skip)に相当する。注意:
`cr->objspace` はこの走査の入力なので、一時的に差し替える処理(Ractor 生成時の子
objspace への割り当て)は必ず VM lock 下で行い、barrier を張った walker から差し替え中の
状態が見えないようにする。

### 2.5 compaction (実装済み commit 0b23f634c)

objspace が 1 個のときは従来どおり local compaction。**複数のときは global GC(STW)の
一部として全 objspace を実 compact する**(§2.2 末尾に相構成)。以前は「動かすと他 objspace
からの参照・shref_bits・『shareable は動かない』前提が壊れる」ため 3 経路
(`GC.compact` / `GC.verify_compaction_references` / `GC.auto_compact=`)を非移動 full GC に
degrade していたが、**global GC は既に全 Ractor をバリアで止めている**ので、その中でなら
shareable も含めて安全に動かせる — 動かした後にバリア内で全 objspace の参照
(cross-objspace 参照・shref 経由の子・VM-global root)を更新すればよい。

要点(かつて「前提が壊れる」と言っていた各点が、バリア内でどう解決されるか):

- **他 objspace からの参照**: 相①で全 objspace を move してから相②で全 objspace の参照を
  更新するので、cross-objspace 参照も T_MOVED forwarding を辿って解決できる。相ごとに
  全 objspace をループするのが必須(per-objspace 交互だと free が他 objspace の update を追い越す)。
- **「shareable は動かない」前提**: これが崩れる箇所を global GC 時だけ全 objspace 対応に
  した。特に `rb_gc_impl_location` は「foreign 参照は動かない」と即 return していたが、
  global GC 中は `rlgc_global_pointer_to_heap_p` で全 objspace の T_MOVED を辿る。
- **mark/pin/move の objspace-context**: `RB_GC_MARK_OR_TRAVERSE` / `gc_pin` は
  `rb_gc_get_objspace()`(=driver)の flag を見るので、`during_reference_updating` /
  `during_compacting` は全 objspace に立てる。pinned_slots reset や参照更新の VM-global
  半分(1 回だけ)など、local compaction が gc_marks_start / gc_sweep で担う後始末を global GC
  側で明示的に補う。

検証: CHECK/ASAN/TSAN/YJIT の multi-Ractor compaction stress・`GC.verify_compaction_references`
の multi-Ractor 実行・単一 objspace 回帰(test_gc_compact/gc/objspace/ractor)すべて green。

## 3. newobj 戦略

割り当ては自分の objspace から、ロックなしで行う。これがこの設計の存在理由である
(master では cache miss のたびに VM 全体のロックを取るため、全 Ractor の割り当てが
直列化してスケールしない)。

```c
static VALUE
newobj(rb_objspace_t *os, size_t heap_idx)
{
    rb_heap_t *heap = &os->heaps[heap_idx];
    struct free_slot *p = heap->freelist;     /* 触るのは所有 Ractor だけ(single writer) */
    if (LIKELY(p != NULL)) {
        heap->freelist = p->next;
        return (VALUE)p;
    }
    return newobj_refill(os, heap);           /* ここもロックなし */
}
```

freelist が尽きたときの補充も全部「自分の物」で進む:

1. 自分の sweep 済みページ(空きスロットを持つ生きページ)に割り当て先を切り替える。
   lazy sweep 中なら自分の sweep を一歩進める。
2. 無ければ、成長してよいか判定して(チューニングパラメータと自分の状況)、
   **ページプールから 1 ページもらう**。
3. 成長させないなら、**自分の local GC を実行**(同じスレッドで。再入は objspace の
   `during_gc` で防ぐ)。major が必要で Ractor が複数いるなら global GC へ昇格 —
   バリアを取るのはこのときだけ。
4. それでも足りなければ memerror。

そのほか:

- malloc 量の計上も objspace ごとで、その Ractor の malloc トリガ GC を駆動する。
- GC.stress は自分の objspace のノブで、自分の local GC を起こすだけ。
- boot 最初期(main Ractor 生成前)は main の objspace に直接割り当てる。
- クラス・メソッドエントリ・コールキャッシュ等の VM 内部オブジェクトも、作った Ractor の
  objspace に置く(正しさのために main へ寄せる方式は採らない。性能のための共有ヒープは
  将来課題)。
- NEWOBJ / FREEOBJ の tracepoint: NEWOBJ は従来どおり(フック有効時のみ VM ロック下)。
  FREEOBJ のフックは worker の objspace には立てない(worker の local sweep 中に任意の
  Ruby / C コードが走ることを防ぐ。これが立たないことは安全性の前提)。

### 3.1 GC.disable / GC.enable — process-wide と per-objspace の 2 枚のフラグ

`GC.disable` は「GC を止めたい」という要求で、意味は **process 全体**である(呼んだ Ractor
だけ止めても、他 Ractor の割り当てが global GC を駆動してしまう)。一方、内部コードには
「いま自分の割り当てで GC が再入すると困る」ため一時的に GC を止める critical section が
多数あり(autoload / const / cvar 表の splice、Ractor 生成窓、signal handler、NEWOBJ フック、
id2ref 挿入、malloc-during-GC 領域など)、これらが止めたいのは **自 objspace の再入 GC だけ**
(他 Ractor は VM ロック / バリアが排除済み)。よってフラグを 2 枚持つ:

- **process 全体フラグ**(`ruby_gc_disabled_global`, gc.c) — ユーザの `GC.disable` /
  `GC.enable` だけが読み書きする。どの Ractor が触っても効くので atomic
  (`RUBY_ATOMIC_LOAD` / `SET`)。
- **per-objspace フラグ**(`objspace->flags.dont_gc`, 既存) — 内部の critical section 用。

**READ 側**: 自動 GC トリガの判定 3 点(`ready_to_gc`・`garbage_collect_with_gvl`・
malloc 増加トリガ)で **両方を見て、どちらも false のときだけ** local GC を走らせる。
`ready_to_gc` は global GC への昇格判定より前にあるので、process 全体フラグを立てると
**全 Ractor の local GC も global GC 昇格も止まる** = 真に process-wide。明示 `GC.start` /
`GC.compact` と method-cache GC(`GPR_FLAG_METHOD`)はどちらのフラグも貫通する(従来どおり)。

**API の対応**:

| 関数 | フラグ | 用途 |
|---|---|---|
| `GC.disable` / `GC.enable`、公開 C API `rb_gc_disable` / `rb_gc_enable` / `rb_gc_disable_no_rest` | process 全体 | ユーザの「GC を止める」 |
| `rb_gc_local_disable` / `rb_gc_local_enable` / `rb_gc_local_disable_no_rest` | per-objspace(current) | 内部 critical section |
| `rb_objspace_gc_disable` / `rb_objspace_gc_enable`(明示 objspace 引数) | per-objspace(指定) | verifier / VM 初期化 |

内部 caller は per-objspace 側に置く。malloc-during-GC の guard は per-objspace の `dont_gc`
を見るので、process 全体フラグでは満たされない(`[BUG] Cannot malloc during GC` になる)。
process 全体フラグを内部が触らないことで、cross-Ractor の save/restore レースも生じない。

### 3.2 ObjectSpace.each_object — collect-then-yield

`each_object` は「呼んだ Ractor の objspace の全オブジェクト + 他の生きている Ractor の
shareable」を列挙する。この 2 つは扱いが逆になる:

- **相1(自 objspace)**: barrier 無しで直接 yield ＝ single-Ractor の each_object と同一。
  walk(`rb_gc_impl_each_objects`)はページ一覧をスナップショットし、各ページを live list と
  突き合わせて歩くので、並行 page-free に耐える。VM lock も不要で、ブロックは alloc / GC /
  ブロックを自由に行える。

- **相2(他 Ractor の shareable)**: 他 objspace は single-writer なので **barrier 下でしか
  読めない**。だが **barrier 中にユーザブロックを yield してはいけない**(§2.4 の理由 —
  safepoint で同 Ractor の別スレッドが per-Ractor VM lock を乱す/barrier を早期終了、または
  ブロック系呼び出しで parked Ractor と deadlock)。よって **collect-then-yield**:
  1. `GC.disable`(process 全体、§3.1)。
  2. `RB_VM_LOCKING` + `rb_vm_barrier` の下で、`ractor.set` の各 objspace(self 除く)を
     `each_objects_shareable`(`shareable_bits` 索引・shareable のみ)で歩き、Array に
     `rb_ary_push` で **集めるだけ**(純 C — `internal_object_p` / `rb_obj_is_kind_of` /
     `rb_ary_push` は object を作らず safepoint を踏まない。backing 成長は malloc だが
     GC.disable で malloc-GC を抑止)。
  3. barrier 解放 → `GC.enable`。
  4. Array から yield(barrier 外＝通常実行。Array が shareable を root し、以降の GC / 
     compaction でも生存・参照更新される)。

  自 objspace に既にある shareable は相1 で yield 済み、相2 は self を除外するので重複しない。

## 4. message send 戦略

### 4.1 三つの経路

| 渡すもの | 経路 | 生存の保証 |
|---|---|---|
| shareable | 参照のまま | local GC は shareable を解放しない + global GC が到達性で回収 |
| unshareable の send / yield | **コピー**(§4.2) | 送信中 pin + 受信側で実体化 |
| unshareable の `Ractor#value` | **参照のまま**(併合してから返す、§4.3) | 返る時点で受け手自身のオブジェクト |

`move:` はコピーと同じ流れで、送信側の元グラフを無効化する点だけが違う。

### 4.2 コピーは「受信側で実体化」

コピーを 1 回のトラバースで受信側の objspace に直接作ることは**できない**。
送信時に作るなら送信スレッドが受信側のロックなしヒープに書くことになり single writer が
壊れる。受信時に 1 回で作るなら send 後の変更がコピーに混ざり snapshot 意味論が壊れる。

よって 2 段階にする:

1. **send 時**(送信スレッド): 自分の objspace に snapshot コピーを作り、キューに積み、
   **送信中 pin** を付ける(shref_bits を立てる。キューに積まれている間、メッセージは
   「共有の世界から参照されている」= shref そのものなので、同じ仕組みで守れる)。
2. **receive 時**(受信スレッド): snapshot を自分の objspace へ実体化して受け取る。
   snapshot は送信側のゴミになる。

コピーの実装はユーザ可視の `#clone` / `#initialize_clone` を**呼ばない**(決定 11):

- String / Array / Hash などのコア型は、C で専用の深コピーを書く(上の 2 トラバース)。
- それ以外の型は当面 **Marshal**: send 時に `Marshal.dump`(snapshot がバイト列 =
  送信側の String 1 本になり、それが in-flight pin の対象)、receive 時に受信側で
  `Marshal.load`。load は通常の割り当て・WB 経路を通るので、下の世代の整合も自然に満たす。
- どちらにも乗らない型(`_dump` を持たない T_DATA 等)は送信エラー(§4.4 と同じ規則)。
  残りの細部は後で考える。

pin は global GC をまたいでも維持する(global GC は shref_bits を全消去するので、
キュー上のメッセージは global GC 中に付け直す。キューから外れて実体化中のものは
受信 Ractor 側に「実体化中スロット」を設けてそこから付け直す)。

**世代の整合**: 受信側での実体化は「old な親 → young な子」の参照を受信側 objspace の
中に作る。このとき remembered set に登録されないと、次の minor GC が子を解放して即
クラッシュになる(例: generic ivar に Array 値を持つ深いグラフの送信は、登録漏れがあると
決定的に再現する)。**実体化が作るすべての参照ストアは受信側の write barrier を通す**ことを
実装の要件とする(generic ivar の構築や Array / Hash の充填のような「生ストア」も含めて)。

### 4.3 `Ractor#value` は「併合してから返す」

`Ractor#value` は successor(最初に value を要求した唯一の Ractor。二人目はエラー)に
ブロックの戻り値を**コピーせず**返す。これが封じ込めと矛盾しない理由は順序にある:

```
相手の終了を待つ → 死んだ objspace を自分のヒープに併合する(§2.3)→ 戻り値を返す
```

value から返った時点で、戻り値はすでに successor 自身の objspace のオブジェクトであり、
「他人の unshareable への参照」が Ruby コードに渡る瞬間は存在しない。ゼロコピーのまま、
封じ込めの例外にもならない。例外終了の場合(value が raise する側)も同じで、併合してから
raise する。

誰も value を呼ばなければ、戻り値は終了済み Ractor の objspace に入ったまま global GC に
管理され(§2.3)、Ractor オブジェクトの回収と同時に main へ行く。その時点で value は
二度と呼べない(Ractor オブジェクトへの参照が無い)ので、取り損ねは起きない。

### 4.4 参照のすり抜けを許さない

master の copy は unshareable を必ず `#clone` で複製する(`ractor_obj_clone`)。
`obj_traverse_replace_i` の T_DATA ケースの `obj_refer_only_shareables_p` は
「参照先が全部 shareable なら copy を許可する条件」(make_shareable と同じ述語)であって、
「同じオブジェクトをそのまま埋め込む」例外ではない。

すり抜けの実体はこれとは別で、`#clone` が T_DATA(例外の backtrace)の**内部の生データ
(locations 配列などの `rb_backtrace_t*`)を複製ラッパと共有**する点にある。単一ヒープの master
では、その内部が全部 shareable(`obj_refer_only_shareables_p` が保証)なら無害。だが per-Ractor
objspace では「受信側のコピー済みグラフ(clone)の内部から、送信側 objspace の unshareable
データへの生ポインタが残る」ことを意味し、どの生存保証にも引っかからず UAF になる
(例外の backtrace が該当)。

扱いは型ごとに 3 通り:

- **backtrace は専用のネイティブ複製**(`rb_backtrace_dup`)。フレームが参照するのは
  iseq / メソッドエントリ(決定 17 で shareable)だけなので、複製は封じ込めに反しない。
  文字列配列・Location 配列は受信側で lazy に再生成される。これにより例外の送信で
  `backtrace` / `backtrace_locations` の両方が保たれる(エラー化すると例外伝搬そのものが
  壊れるため、この型だけは複製で救う)。
- それ以外の unshareable T_DATA は **Marshal に乗れば乗せ、乗らなければ送信エラー**
  (`_dump` 系を持つ型は受信側で別オブジェクトとして実体化される)。
- shareable な T_DATA は従来どおり参照渡しで問題ない。

ネイティブコピーの enter は対応型以外で即 stop して Marshal 経路へ落ちるので、
**by-ref passthrough にはコピー経路から到達できない**(move 経路は従来どおり
「move できない T_DATA はエラー」)。今後も「コピーをサボって参照を渡す」最適化を
send 系に入れないこと。なお `Ractor#value` がコピー無しで済むのはすり抜けではなく、
参照を返す前に objspace ごと併合するからである(§4.3)。

### 4.5 move は「off-heap courier(変則 Marshal)」で運ぶ(2026-06-16 確定)

#### 旧案(二段 traverse)が破綻した理由

当初は「send 時に送信側 objspace へ snapshot を作り(move_enter+move_leave)、
receive 時にもう一度 move traverse して受信側へ再ホーム」する二段案だった。しかし
M1b(local GC のバリア外し)では破綻する:

- snapshot は**送信側 objspace の GC オブジェクト**で、送信中ピン(shref)で延命する。
- shref オブジェクトは送信側 local GC の **`rlgc_pinned_roots_mark` がルートとして
  descend(traverse)** し、compaction では**移動もされ得る**(shref ビットは gc_move で
  移送される)。
- ところが receive 側の二段目 traverse は **snapshot をその場で書き換える**
  (`obj_traverse_replace_i` の move 枝で `RB_OBJ_WRITE`、`rb_ary_cancel_sharing` 等)。
- 結果、**送信側 GC が snapshot を辿る × 受信側が書き換える** のデータ競合(TSan 実証)
  と、compaction による移動で受信側の生ポインタが dangling、が起きる。VM バリアは
  local GC を止めないので無力。flat-mark(descend しない延命)も世代別 GC の
  re-mark 規則と噛み合わず young 子が解放される。

#### 確定案:in-flight ペイロードを GC オブジェクトにしない

> **送信中の move ペイロードを「どの objspace のヒープにも置かない」**=
> xmalloc した off-heap の **move courier** に直列化する。

in-flight が GC オブジェクトでなくなるので、**延命・競合・compaction の問題が一括で
消滅**する(送信側 GC は courier を mark/sweep/move しない)。実体は「**変則 Marshal**」:

- グラフ構造をノード配列に直列化。ノード間参照は **node id**(src→id の dedup マップで
  **共有部分グラフと循環参照を解決**)。
- malloc バッファは**コピーせずポインタ移管**(String の char バッファ、IO の fd/fptr)
  — move のゼロコピー性をここで担保。
- ユーザの `marshal_dump`/`_dump` フックは**呼ばない**(決定 11 と同じ)。
- 原本は捕捉と同時に **RactorMovedObject 化**(move 意味論)。

**送信**(`ractor_move_courier_build`): obj を辿って courier を構築、各原本を husk 化。
**受信**(`ractor_move_courier_materialize`): 受信側 objspace で **2 パス**
(全ノードのシェルを確保 → 中身を充填)で再構築し循環を解く。完了後 `xfree`。
courier が保持する VALUE は **shareable/immediate のみ**(REF ノードとクラス)なので、
それだけを mark すれば足り(`ractor_move_courier_mark`、basket / in_flight_courier
経由)、shareable の mark は read-only で競合しない。

対応型: String / Array / Hash / Object / Struct / MatchData / IO / immediate・shareable、
+ インスタンス/汎用 ivar(全型共通)/ 凍結 / 共有特異クラスの再アタッチ。MatchData は
re.c に専用ヘルパ(`rb_match_move_dump`/`_alloc`/`_load`/`_free`)を置き、レジスタを
onig 非依存の blob に取り出して再構築する。

**コンテナ buffer 流用**(Array の `VALUE*`、Hash の st_table、Object の ivar buffer を
ポインタ移管して受信側で再利用)は**後続の最適化**(現状は構造を再構築し、String/IO
のみゼロコピー)。

## 5. 実装計画(origin/master から。各段で全テスト green)

順序は **M0 → M1a → M3 → M2 → M4 → M1b → M5**。local GC の並行化(M1b)を
最後尾近くまで遅らせるのが要点(理由は M1b の項)。並列性能が出るのは M1b 以降で、
それまでの各段は「master と同等性能・正しさは段ごとに full green」を保って進める。

**現状(2026-07)**: M0〜M1b はすべて実装済み(下記各段の【達成済み】参照)。本 branch は
mark-only shareable + shref rooting + born-shareable imemo + cross-Ractor 列挙まで含む
「§現在の到達点」の仕様で動作しており、残るのは M5(堅牢化・チューニング)と、既知逸脱
(svar-in-shareable-env、§2.1)の是正である。以下は各段の意図と、実装で得た知見の記録。

- **M0 土台**: rb_global_objspace(ページプール)新設、`vm->gc.objspace` を
  `vm->gc.global_objspace` に差し替え、main objspace を main Ractor 持ちに、newobj cache を
  剥がしてヒープ直割り当てに(単一 Ractor なら自明に single writer)。master と性能比較。
  【達成済み】
- **M1a per-Ractor objspace と local GC(STW 段階)**: Ractor 生成で objspace 生成、
  封じ込め mark、shareable / shref の root 化 pin(§2.1 手順 3.f)、shref_bits と
  write barrier。**この段階では gc_enter が従来どおり VM lock + barrier を取る** —
  「自分のヒープしか刈らないが、刈る間は全 Ractor が停止する」。§2.1 冒頭の
  「ロックもバリアも取らない」はこの段階ではまだ実現せず、M1b で達成した。並行性バグが存在しない
  世界で、封じ込め・pin・root 集合の正しさだけを固めるための分割。
  (global GC がまだ無いので shareable は滞留する。M2 で解消。)【達成済み。以後 M1b で
  この VM lock + barrier は撤去された(§2.1 手順の M1a/M1b 注記)。】
- **M3 message send**: 受信側実体化(コア型の C 深コピー + Marshal 経路)、送信中 pin
  (global GC またぎ含む)、**受信側 write barrier の徹底**(§4.2 世代の整合)、
  T_DATA passthrough の廃止、value の successor 規則(§4.3。併合本体は M4)。
  M2 より先に行う: 実体化と pin の形が決まらないと、global GC が in-flight メッセージを
  どう扱うか(pin の付け直し先)を確定できないため。【達成済み。move は §4.5 の
  off-heap courier に置き換わった。】
- **M2 global GC**: バリア、root 表(local と共有)、全 objspace の一括 mark/sweep、
  shref_bits の再計算、global の起動条件(shareable 増加・滞留・zombie Ractor)。【達成済み】
- **M4 終了と引き継ぎ**: join 時のその場併合、未 join の global GC 内 main 併合、
  終了済み Ractor の一覧延命、finalizer / zombie の引き継ぎ実行、単一 Ractor 復帰時の
  shareable 回収、fork / shutdown の接続。【達成済み(zombie 帳簿 = §2.3、main 併合は
  決定 18 の per-Ractor postponed job 経由)】
- **M1b local GC の並行化(バリア外し)**: gc_enter / gc_exit から VM lock と barrier を
  外し、§2.1 本文どおり「local GC はロックもバリアも取らない」を実現する。
  **並列性能はここで出る**(それまでは GC が STW なので、GC を踏む負荷では master と
  同等止まり)。最後尾に置く理由:
  1. **競合面を開くのは一度だけにする。** M1a〜M4 の green は「GC 中は誰も動かない」
     前提で検証されている。バリアを外すと、バリアが隠していた競合面(§1.4 の
     ビットマップ書き込み、§2.4 の VM 共有構造、§4.2 の in-flight メッセージの読み書き)が
     一斉に表に出る。ここは経験的に最もバグ密度が高く、再現が確率的で TSan でしか
     根本原因に辿れない領域なので、機能追加と混ぜずに単独で開けたい。
  2. **手戻りの回避。** M2 / M4 は「全 Ractor を止めて全 objspace を見る・併合する」
     STW コードであり、M1b の有無にほぼ影響されない。逆に M1b を先にやると、M2 / M4 を
     足すたびに「並行中の local GC と global GC の遷移プロトコル」を再設計・再検証する
     ことになり、いちばん高い検証コストを複数回払う。
  3. **遷移プロトコルは global GC が無いと設計できない。** 「global 開始時に進行中の
     local GC を完走させてから全停止する」「local 側は global の進行中フラグを見て退避する」
     といった排他は、相手(M2)が存在して初めて書ける・試せる。M1b が先だと、その時点の
     並行性検証は M2 導入で陳腐化する。
  4. **機能完結が先。** M2 / M4 が無い間は shareable と終了 Ractor の objspace が
     貯まり続ける。その状態で性能を測っても「リークする処理系の速度」になり、
     チューニングの判断材料にならない。
  【達成済み 2026-06-11】上記の読みどおり、開いた競合面から実バグ 8 件が出た(Ractor
  オブジェクトの dmark が他 Ractor の owner 変異構造を歩く 2 面、shape edge 表の
  born-shareable 漏れ、deleted-key 機構の STW 前提、main 判定の swap 揺れ、process-wide
  static の再書込、interrupt queue の create→start 窓、linkage)。TSan/ASAN が決め手。
  性能は 8 Ractor 割り当て負荷で実効 ~7.7 コア(M1a 比 4 倍超)。
  なお M0 時点で master と同等性能(割り当て経路に退行なし)は確認済み。性能の伸び代は
  M1b 完了後にまとめて測り直す。
- **M5 堅牢化・調整(現在ここ・進行中)**: 既知のクラッシュ再現スクリプト群(`rlgc_repro/`)と多 Ractor
  ストレスシナリオをテストオラクルに常用する。btest / test-all に加え、**ASAN / TSan を
  CI に常設**する(並行 GC のバグは再現が確率的で、サニタイザでないと根本原因まで
  辿れない — 特に M1b の検証は TSan が主武器)。GC_STRESS はタイミングを変えて
  昇格依存のバグを隠すことがあるので、stress あり / なしの両方を回す。global GC
  起動条件の係数・下限(§2.2)と born-shareable の increment 箇所の網羅
  (クラス生成・fstring・freeze 等)もここで確定。
