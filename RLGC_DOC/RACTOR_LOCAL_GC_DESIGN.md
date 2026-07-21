# Ractor-local GC 設計ドキュメント【v1・凍結】

> **これは v1(ブランチ `ractor-local-gc`)の設計記録で凍結**。現行 RLGCv2 の設計正典は
> `design_v2.md`(最新仕様サマリは同書「現在の到達点」)。本書は v1 の設計経緯・タクソノミの
> 歴史的資料として残す。

CRuby の GC を **Ractor ごとに独立した objspace** へ分割し、各 Ractor が自分のヒープを
**Stop-The-World なしで並行に** mark/sweep する実験実装。`gc/default/default.c` のみ対象
(mmtk/wbcheck は対象外)。本ドキュメントだけで第三者が同等実装を再現できることを狙う。

**ステータス**: 実験実装。ブランチ `ractor-local-gc` に3コミット(`master` は無改変)。

- 既定 OFF。`RUBY_RACTOR_LOCAL_GC=1` で有効化。
- 性能: bench.rb N=8 で **~4.7 実効コア**(直列ベースライン比 4.75倍)、最大8個のローカル GC が同時実行。
- 正しさ: `make test-all` env-on **34849 / 0 failures**、env-off 0 failures。`make btest`
  `test_ractor.rb` **159/161**(残り2は miniruby/Tempfile の既存環境要因で本実装と無関係)。
- 既知の課題: 極限並行ストレスの主要 UAF は **孤児 objspace(終了 Ractor の local objspace が global GC 非巡回)**
  が真因と判明し、孤児を GC 巡回に含める**ローカル修正で解決**(§5.1; main-routing 不要)。残存は ~4% の稀な系統
  (§3.10 message コピー等)+空孤児 objspace 殻のリーク(§5.4)。通常〜型多様ワークロードはクラッシュ無し。

---

## 1. 一般的なデザイン

### 1.1 中心アイデア
- **per-Ractor objspace**: 非 main Ractor は各自 `rb_objspace_t` を持つ。`rb_gc_get_objspace()`
  は「現在の Ractor の objspace」を返す。main Ractor の objspace = VM 全体の objspace。
- **3 種類の GC**:
  1. **ローカル minor / major GC** — その Ractor の objspace だけを mark/sweep。VM ロックも
     バリアも取らず、他 Ractor の実行・他 Ractor のローカル GC と**並行**に走る。
  2. **グローバル GC** — full/major のとき全 Ractor を STW バリアで止め、**全 objspace を
     統一 mark/sweep**。shareable を「到達性」で回収する唯一の機会。
- **ロックフリー割り当て** — ローカル objspace は Ractor 専有なので `newobj` は VM ロックを
  取らない(これが元々のスケーリング・ボトルネックだった)。

### 1.2 不変条件 (これを守れば正しい)
1. **objspace 解決はアラインメント**: ヒープページは 64KiB (`HEAP_PAGE_ALIGN`) アライン。
   任意のポインタ `p` から `GET_HEAP_PAGE(p)->objspace` で所有 objspace が分かる
   (`page->objspace` 後方ポインタ)。**ただし精密マークのみ**。保守的スキャン(任意ワード)は
   アラインしたページ本体を**デリファレンスしてはならない**(ページは個別 mmap でギャップが
   unmap されていて SEGV する) → `rb_gc_conservative_owner()`(各 objspace の安全な
   sorted-array bsearch)を使う。
2. **封じ込め (confinement)**: ローカル GC の `gc_mark` は
   `GET_HEAP_OBJSPACE(obj) != objspace` のオブジェクトを**辿らない**(live leaf 扱い)。
   他 objspace のオブジェクトはその所有者の GC が生かす。
3. **shareable のピン**: ローカル GC は「他 objspace から参照されているか」を判定できないため
   **shareable を絶対に解放しない**(pin)。回収はグローバル GC のみ。
4. **shared_bits remset**: 「shareable から**直接**参照される unshareable 境界オブジェクト」を
   per-page ビットマップで記録。これがローカル GC のルートになる(shareable 親が別 objspace に
   居ても、その境界の子を所有者のローカル GC が生かせる)。WB で維持、グローバル full mark で
   全クリア+再計算。境界の子の subtree は通常の `local` オブジェクトなのでローカル回収可能。
   soundness: s→u エッジは常に **u の所有者**が作る(隔離則: 他 Ractor の unshareable 参照は
   持てない)ので、自分のオブジェクト u にビットを立てれば良い(親 s は触らない)。
5. **VM 内部キャッシュのピン**: method/inline cache 等は shareable で cross-Ractor に共有され
   弱インラインキャッシュ等で辿れるので、ローカル GC が回収しないよう「born-shareable は
   shared_bits」+ 「sweep で cc/cme/callinfo の imemo は常にピン」。**ただしこのピンには既知の
   寿命バグがある(§5.1)。**
6. **共有可変構造へのアクセスは同期**: 並行ローカル GC が触らざるを得ない VM グローバル/Ractor 固有の
   可変構造は **NON_BARRIER ロック**(VM ロックだがグローバル GC バリアに途中参加しない版)等で同期
   (§3.7)。
7. **EC/fiber の封じ込め**: ローカル GC は**自 Ractor の実行コンテキスト(EC)のみ**を歩く。他 Ractor の
   EC は並行実行中でフレームスタックが不安定なので走査してはならない(§3.11)。

### 1.3 性能の考え方
- 元のボトルネック: `newobj_cache_miss` が `RB_GC_CR_LOCK()`(プロセス全体で1個の
  `vm->ractor.sync.lock`)を**毎キャッシュミス**で取得 → 全 Ractor の割り当てとローカル GC が
  直列化。`perf` で ctx-switch の 98% が `rb_native_mutex_lock` と判明 (2.6 実効コア)。
- 対策: ローカル objspace ではこのロックを除去(フルロックフリー)。→ 4.7 実効コア。
- 二次対策: ページ本体の per-page `mmap`+`munmap`(64KiB アライン用)が kernel の process-wide
  `mmap_lock` を直列化 → **per-objspace アリーナ**(2MiB アライン・THP・no-trim-munmap)。

### 1.4 ランタイムトグル (env)
- `RUBY_RACTOR_LOCAL_GC=1` — per-Ractor objspace 機能全体を有効化(既定 OFF、つまり既定は従来通り)。
- `RUBY_RACTOR_GLOBAL_GC=0` — グローバル GC を無効化(major も ローカルになり shareable は
  objspace 寿命まで pin/leak)。既定 ON。
- `RUBY_RACTOR_LOCAL_GC_LOCKFREE=0` — ロックフリー割り当てを無効化。既定 ON。
- `RLGC_STATS=1` — 終了時にローカル GC 回数 / 最大同時実行数 / グローバル GC 回数を表示。
- `RACTOR_LOCAL_GC_AUDIT`(コンパイル時 1) — confinement 監査(s→u WB 完全性 + u→s sweep 不変条件、§3.12)。

---

## 2. 変更点一覧 (master との diff, コード分)

```
 gc.c                 | 298 +    VM 側グルー: objspace ルーティング, conservative_owner,
                       |          全 objspace 走査, 各種同期, ローカルルート, 各種ヘルパー
 gc/default/default.c | 863 +    GC 本体: per-objspace objspace, local mark, shared_bits,
                       |          global GC, lock-free alloc + arena, 並行 race 修正
 ractor.c             |  38 +    per-Ractor objspace 生成, ローカルルートマーク, cache_free(r)
 ractor_core.h        |   9 +    rb_ractor_t に local_gc_objspace / main_newobj_cache
 ractor_sync.c        |  56 +    メッセージポートのマークを per-Ractor ロック, in-flight pin,
                       |          materialize-on-receive (§3.10)
 cont.c               |  12 +    ローカル GC で他 Ractor の fiber/EC を歩かない (§3.11)
 vm.c                 |  32 +    gen_fields_cache を強ルート化, thread roots, EC-confinement assert
 variable.c           |   6 +    generic_fields_tbl sweep-delete を NON_BARRIER
 id_table.c           |   5 +    managed_id_table_dup に RB_OBJ_SET_SHAREABLE (グローバル GC 根本修正)
 iseq.c               |   6 +    TracePoint/cc クリアを全 objspace に
 internal/gc.h        |  22 +    新 API の宣言
 bootstraptest/...    |  44 +    materialize-on-receive の決定的回帰テスト
```

機能対応:
- **per-Ractor objspace ライフサイクル**: ractor.c, gc.c, ractor_core.h, default.c — §3.1
- **local mark / 封じ込め**: default.c, gc.c — §3.2
- **shared_bits + WB**: default.c — §3.3
- **global GC**: default.c, gc.c — §3.4
- **lock-free alloc + arena**: default.c — §3.5, §3.6
- **並行 GC race 修正(8件)**: §3.7
- **根本バグ修正**: id_table.c, vm.c, default.c — §3.8
- **全 objspace 走査**: gc.c, iseq.c — §3.9
- **メッセージ所有権(materialize-on-receive)**: ractor_sync.c, gc.c, test — §3.10
- **EC/fiber 封じ込め**: cont.c, gc.c, vm.c — §3.11
- **confinement アサーション**: vm.c, default.c, gc.c — §3.12

---

## 3. 変更点詳細

### 3.1 per-Ractor objspace ライフサイクル

**`rb_ractor_t` に2フィールド追加** (ractor_core.h):
```c
void *local_gc_objspace;   /* この Ractor の objspace。main は VM の objspace を別名参照 */
void *main_newobj_cache;   /* main objspace 割り当て用の足場 (現状 未配線・休眠。§A.2/§5.4) */
```

**生成** (ractor.c `vm_insert_ractor0`): 非 main Ractor 作成時、`rb_gc_rlgc_enabled() && r != main`
なら `r->local_gc_objspace = rb_gc_objspace_alloc_local()`。main は `rb_ractor_main_alloc` で
`r->local_gc_objspace = GET_VM()->gc.objspace`。

**ルーティング** (gc.c `rb_gc_get_objspace`): 現在 Ractor の `local_gc_objspace`(無ければ VM objspace)。

**newobj cache は所有 objspace に紐づく** (gc.c `rb_gc_ractor_cache_alloc/free`):
cache はその Ractor の objspace からページを引く。`rb_gc_ractor_cache_free(rb_ractor_t *r)`
は **r->local_gc_objspace に対して**解放。シグネチャを `(void *cache)` から `(rb_ractor_t *r)` に変更。

**objspace 初期化の特別処理** (default.c `rb_gc_impl_objspace_init`): 最初の per-Ractor objspace が
出来た瞬間から `rlgc_has_local=true` とし、`objspace->local=TRUE` / `dont_incremental=TRUE`、main も
`gc_rest`+`dont_incremental`。理由: その瞬間から「どの objspace の major もグローバル STW GC」になり、
グローバル GC のバリアが main を**コレクション途中で**捕まえると統一 mark/sweep が破綻するため、main も
incremental/lazy を切ってアトミックにする。

### 3.2 local mark (封じ込め)

**`gc_mark` の入口ガード** (default.c):
```c
if (objspace->flags.local_gc && GET_HEAP_OBJSPACE(obj) != objspace) {
    return;   /* 他 objspace のオブジェクトは辿らない(その所有者が生かす) */
}
```

**ローカルルートマーク** (gc.c `rb_gc_mark_roots` 冒頭、`objspace != vm->gc.objspace && !rlgc_global_gc_active` のとき):
- `rb_gc_mark_ractor_local_roots(cr)` — Ractor 自身の内部状態(受信キュー/local storage/std IO/スレッド)。
- `mark_current_machine_context(ec)` — GC を起こしたスレッドの保守的マシンスタック。
- VM グローバルルート(`rb_vm_mark` 等)は**マークしない** → `return`。それらは main objspace に居て
  main/グローバル GC が生かす。`global_hooks` もここでは触らない(§3.7 #8)。

**ローカルルートの肝** (ractor.c `rb_gc_mark_ractor_local_roots`, vm.c `rb_gc_mark_thread_roots`):
VM スタックを持つ ec を直接マークする(`thread_mark`→`rb_execution_context_mark(th->ec)`)。
これが「object-heavy なローカル Ractor が全部クラッシュ」していた根本原因の修正:
VM スタック上の live local が fiber wrapper(main objspace, foreign)経由でしか辿れず、local mark が
skip して use-after-free していた。

### 3.3 shared_bits remset + write barrier

**データ構造** (default.c): `heap_page::shared_bits[]` + `flags.has_shared_objects`、`GET_HEAP_SHARED_BITS`。

**WB** (`rb_gc_impl_writebarrier(a, b)`): 通常の世代別 WB の**前**に、`b` が shareable なら `b` に、
あるいは `a` が shareable(or shared)で `b` が unshareable なら境界の子 `b` に shared_bit を立てる。

**born-shareable** (`newobj_init`): `FL_SHAREABLE` なら生成時に shared_bits をセット。

**ルートパス** (`mark_roots` → `gc_mark_shared_roots`): `has_shared_objects` なページの shared_bits を
走査し各境界オブジェクトを `gc_mark`(subtree も辿る)。

**full mark 中の再計算** (`gc_mark`→`gc_shared_relation`): 親 `rgengc.parent_object` が shareable で
子が unshareable なら shared_bits を立て直す(AUDIT モードは WB 漏れを `gc_shared_wb_miss` で報告、§3.12)。

**クリア規則** (`rgengc_mark_and_rememberset_clear`): `!rlgc_has_local || rlgc_global_gc_active`
のときのみ shared_bits クリア。**ローカル GC はクリアしない**。**移動時** (`gc_move`): shared_bit を src→dest。

### 3.4 global GC

**判定** (`gc_start`, gc_enter の前): `rlgc_has_local && rlgc_global_gc_enabled()` かつ full mark に
なるなら `objspace->flags.global_gc = TRUE`。minor は ローカルのまま。

**gc_enter / gc_exit**: ローカル minor は `lock_lev=0` + `flags.local_gc=TRUE`(VM ロックもバリアも取らない)。
グローバル/main は `RB_GC_VM_LOCK()` + `rb_gc_vm_barrier()`(STW)。

**駆動** (`gc_start`): `rlgc_global_gc_active = flags.global_gc;` → `gc_marks` は VM 全ルート + 全 objspace
横断トレース(全 Ractor 停止済み)。完了後 `gc_global_sweep` = `rb_gc_foreach_objspace(gc_global_sweep_one)`
で全 objspace を sweep(dead shareable 回収)。clear も `gc_marks_start` で全 objspace 化。

**保守的マーク** (`rb_gc_impl_mark_maybe`): グローバル時は `rb_gc_conservative_owner()` で全 objspace 横断の
安全な所属判定(ワードをデリファレンスしない)。

**sweep の pin ガード** (`gc_sweep_plane`):
```c
if (objspace->local && RB_OBJ_SHAREABLE_P(vp) && !rlgc_global_gc_active) break; /* ローカルは shareable 不解放 */
if (rlgc_has_local && !rlgc_global_gc_active && RB_OBJ_SHAREABLE_P(vp) && T_IMEMO && (callcache|callinfo|ment)) break;
                                                              /* cc/cme/ci ピン。global GC では guard を外す(§5.1): dead クラスと一緒に回収 */
```

### 3.5 lock-free allocation
`newobj_cache_miss`: ローカル objspace かつ lockfree 有効なら **VM ロックを取らない**(`main` objspace のみ
`RB_GC_CR_LOCK`)。ローカル objspace は Ractor 専有 → 空きページ確保もローカル GC も自スレッドのみ(Ractor GVL
で直列)+グローバル GC はバリアで先に止める、ので VM グローバルロック不要。

### 3.6 per-objspace arena allocator
per-page `mmap`+`munmap`(64KiB アライン用)が process-wide `mmap_lock` を直列化する対策。
`RLGC_PAGE_ARENA_BODIES 256`(=16MiB)・`RLGC_ARENA_ALIGN 2MiB`、`mmap` を 2MiB アラインへ切上げ slack は
**munmap せず**放置、`madvise(MADV_HUGEPAGE)`、freelist は本体メモリ自身に next を格納、objspace 解放時に
arena を munmap。VM グローバル span `[lomem, himem)` を `rlgc_span_extend`(atomic CAS)で更新。

### 3.7 並行ローカル GC が共有データを触る競合の修正(計8件)

根本パターン: ローカル GC が並行実行されると VM グローバル/Ractor 固有の可変構造を他 Ractor の mutator/GC と
同時に触る。**無同期** or **barrier-aware ロック**(`RB_VM_LOCKING` は保留中グローバル GC バリアに途中参加 →
objspace を中途半端な状態で渡す)or **VM グローバル GC スクラッチの読み**は競合する。鍵: グローバル GC バリア
発行側(`rb_ractor_sched_barrier_start`)は待機前に VM mutex を**解放**するので、ローカル GC が **NON_BARRIER**
で VM ロックを取ってもデッドロックしない。

| # | 構造 | 競合 | 修正 |
|---|------|------|------|
| 1 | `generic_fields_tbl_` | mark lookup / sweep delete が writer の rehash と競合 | **NON_BARRIER VM ロック** (gc.c `gc_mark_generic_ivar_sync`, variable.c) |
| 2 | `id2ref_tbl` | sweep delete が無同期 | **NON_BARRIER VM ロック** (gc.c `obj_free_object_id`) |
| 3 | Ractor ポート `recv_queue`/`ports`/`monitors` | foreign sender が per-Ractor mutex で変更、ローカル GC が無ロック走査 | **生 `rb_native_mutex_lock(&r->sync.lock)`** を `rb_gc_during_local_gc_p()` のとき取得 (ractor_sync.c) |
| 4 | in-flight メッセージコピー | 送信側 objspace に居るが受信側 basket からのみ参照 → 両 ローカル GC が skip → 解放 | 送信側で **shared_bits pin** (gc.c `rb_gc_pin_in_flight_message`) |
| 5 | `vm->gc.mark_func_data` | S の reachability チェックが R の実 GC マークを乗っ取り | 実 GC は `during_gc` で判定し無視 (gc.c `RB_GC_MARK_OR_TRAVERSE`) |
| 6 | per-EC `gen_fields_cache` | weak 参照で sweep に解放され得る | **強 movable ルート化** (vm.c `rb_execution_context_mark`) |
| 7 | `freed_ractor_local_keys` | `rb_ractor_finish_marking` が毎回 free+clear → 二重 free | STW のみ実行 (default.c `gc_marks_finish`) |
| 8 | `vm->global_hooks` | ローカル GC が無ロック走査、writer も無ロック | ローカルルート枝から**除去**(user hook は `r->pub.hooks`=`ractor_mark`、global_hooks は STW グローバル GC) (gc.c) |

### 3.8 根本バグ修正(クラッシュ駆動で発見)
- **id_table.c `rb_managed_id_table_dup`**: `RB_OBJ_SET_SHAREABLE(obj)` 追加。dup された shape-tree
  edge テーブルが unshareable のままだとローカル GC が回収 → グローバル GC の `shape_tree_mark` が T_NONE。
  **これがグローバル GC を default-on にできた根本修正**。
- **default.c `rb_gc_impl_copy_finalizer`**: obj/dest が別 objspace のとき各々の finalizer_table を使う。
- **vm.c thread roots (§3.2)**: VM スタックを直接マーク。

### 3.9 全 objspace 走査
`rb_objspace_each_objects_all_ractors`(gc.c, バリア保持下)を新設し、iseq.c の TracePoint 有効化 / cc クリアが
全 Ractor の iseq を対象にするよう変更(従来は現 Ractor の objspace のみ)。

### 3.10 メッセージの所有権: materialize-on-receive

> **注(v2 で置換済み)**: 以下は v1 の機構で、receive 側が `ractor_copy`(=ユーザ `#clone`)を
> **もう一度**走らせるため copy 意味論が 2 回発火する(`initialize_clone` の副作用が観測 2 回)。
> **v2 はこれをやめ、send/receive とも native 構造コピー**(`ractor_native_shallow_copy` /
> `ractor_copy_native_try`、ユーザ `#clone` を呼ばない。singleton 等は Marshal に fall through)
> に置換した(design_v2.md 決定 11 / §4.4)。したがって v2 では native-copyable 型は
> **ユーザコピーフック 0 回**、Marshal 経路は `marshal_dump`/`marshal_load` が各 1 回
> (標準プロトコル)で、「2 回発火」は起きない。この §3.10 は v1 の歴史的記述として残す。

**背景の問題**: Ractor 間で送ったコピー(`basket_type_copy`/`move`)は、送信側 S のコンテキストで `ractor_copy`
(=`#clone`)が走るため **S の objspace に物理的に確保**される。受信(`ractor_basket_accept`)は
`reset_belonging` で所有を受信側 R にするだけで再配置しない。結果「物理的には S・論理的所有は R」という
不変条件(§1.2-2「オブジェクトは所有者の objspace に住む」)違反のオブジェクトが生じる。in-flight 中は fix #4
+グローバル GC 再ピン(Ractor→recv_queue→basket→copy, parent=shareable Ractor)で生存するが、`basket_free`
後にこの経路が消えると、グローバル GC が shared_bit をクリアし(R の root は unshareable で `gc_shared_relation`
が再付与しない)、S のローカル GC がコピーを解放 → R 参照で **UAF**。

**修正(実装済み)**: 受信時に**受信側 objspace へ再 materialize** する。`ractor_basket_accept`
(ractor_sync.c):
```c
VALUE v = ractor_basket_value(b);
const enum ractor_basket_type type = b->type;
const bool exception = b->p.exception;
const VALUE sender = b->sender;
ractor_basket_free(b);                          /* 先に free(再コピー/raise でのリーク防止) */
if ((type == basket_type_copy || type == basket_type_move) &&
    !rb_gc_object_in_current_objspace_p(v)) {
    v = ractor_copy(v);                          /* 受信スレッド=受信側 objspace へ再 clone */
}
if (exception) rb_exc_raise(ractor_make_remote_exception(v, sender));
return v;
```
- `ractor_copy` は受信スレッドで走るので確保先は受信側 objspace。`rb_gc_object_in_current_objspace_p(VALUE)`
  (gc.c) は現在 objspace のページ集合のみ参照(`rb_gc_impl_pointer_to_heap_p`)で **VM バリア不要**、非RLGC・
  self-send では常に true で自動 no-op。受信側からは shared_bits を**再設定しない**(送信側 objspace への
  cross-objspace write race になるため)。in-flight 窓のため送信側の `rb_gc_pin_in_flight_message` は残す。
- **正しさ**: accept 後オブジェクトは受信側 objspace に住み受信側 root が保持 → 受信側ローカル GC が通常回収。
  送信側クローンは通常ゴミになり S が回収。
- **コスト/互換**: copy/move 1件につき `#clone` がもう1回(send+receive で計2回)。ユーザ
  `clone`/`initialize_clone` の副作用が2回発火する(観測可能な互換変化)。
- **検証**: 決定的再現テスト(`bootstraptest/test_ractor.rb`、orchestrated に global GC でピンを消し
  ローカル minor で young 未ピン copy を掃いて slot を上書き)。修正無し 6/6 SIGABRT
  (`try to mark T_NONE`)→ 修正有り 6/6 ok。
- **残存**: 極限並行ストレス(4並行送信+毎メッセージ global GC+大量 clobber+長期保持)でのみ ~7.5% で別系統の
  UAF が出る。受信側 `ractor_copy` が並行 global GC 下で破損クローンを生成するもので、§5.1 と同系統。

### 3.11 ローカル GC と他 Ractor の fiber/EC (バグ修正済)

**症状**: 子を生成した親 Ractor の ローカル GC 中に SEGV(`rb_execution_context_mark` →
`cont_mark` → `fiber_mark`)。**最小再現(決定的・10/10 crash)**:
```ruby
parent = Ractor.new do
  child = Ractor.new { 200_000.times { [Object.new, "s" * 5] }; :child }
  300.times { GC.start(full_mark: false); 300.times { "x" * 50 } }
  child.value; :done
end
parent.value
```
**根本原因**: `Ractor.new` は親スレッド上で子の root fiber を確保するため、**子の fiber オブジェクトが
物理的に親の objspace に在住**する(§3.10 と同型)。親の ローカル GC がそれをマーク →
`rb_execution_context_mark` が**子の並行実行中のフレームスタック**を歩く → 壊れた EP で SEGV。二分で確定:
GLOBAL_GC=0/LOCKFREE=0 でも発生(ローカル GC 固有)、RLGC OFF で消滅。

**修正**: `cont_mark`(cont.c) で、ローカル GC 中に**別 Ractor 所有**の cont/fiber は
saved_ec/VM スタック/machine スタックの走査を**スキップ**(その Ractor 自身の GC が自分の EC をマーク;
cont オブジェクトと thread 参照は生かす)。所有判定は `cont->saved_ec.thread_ptr->ractor` を新ヘルパー
`rb_gc_local_gc_foreign_ractor_p(owner)`(gc.c: ローカル GC 中かつ owner≠driver で true、global STW 中は
常に false)で行う。検証: 最小再現 **0/30**、s2(non-main↔non-main+GC bomb) GLOBAL_GC=0 で **5/5→0/12**、
btest 159/161。

### 3.12 confinement アサーション (RACTOR_LOCAL_GC_AUDIT / VM_CHECK_MODE)
- **EC-confinement** (vm.c `rb_execution_context_mark` 先頭, `VM_ASSERT`): ローカル GC は自 Ractor の EC のみ
  歩く(`ec->thread_ptr==NULL || !rb_gc_local_gc_foreign_ractor_p(ec->thread_ptr->ractor)`)。§3.11 種別を捕捉。
- **u→s liveness** (default.c sweep, AUDIT, rb_bug): ローカル GC は shareable を決して free しない
  (sweep pin 迂回の検出)。
- **s→u WB-miss** (default.c `gc_shared_wb_miss`, AUDIT): shareable→unshareable で shared_bit 未記録の
  境界エッジを報告。
- 検証: VM_CHECK_MODE=1 + AUDIT=1 でコンパイル成功、正常系で誤発火 0。これらは §5.1 の診断に有用
  (例: s→u WB ミスが 0 ＝ cc/cme バグは WB 系ではない、と確定できた)。

---

## 4. 成果

### 4.1 ベンチマーク
ワークロード: N Ractor が各自 `300 回 { a=[]; 3000.times{ a << [i, "s#{i}", {k=>i}] }; a.clear }`。
AMD Ryzen 9 5900HX (8 物理/16 HT)。

| 構成 | N=1 | N=8 | 実効コア | CPU% |
|------|-----|-----|------|------|
| env-off (共有 objspace・直列) | 0.199 | 1.568 | **1.0** | 244% |
| RLGC 修正前 (cache-miss ロックあり) | 0.186 | 0.562 | 2.6 | 362% |
| **RLGC フルロックフリー (本実装)** | 0.189 | **0.330** | **~4.7** | 658% |

直列比 **4.75倍**。`RLGC_STATS`: `local GCs: 431 (max 8 ran concurrently), global GCs: 8`。
残る 8→4.7 のギャップは (a) グローバル GC の STW バリア(~13%)、(b) GC 自体の CPU コスト。

### 4.2 正しさ
- `make test-all` env-on: **34849 / 0 failures**、env-off **34837 / 0 failures**(非 RLGC 経路に回帰なし)。
- `make btest` `test_ractor.rb`: **159/161**(残り2は #118/#121 Tempfile/fileno で RLGC OFF でも同一失敗の
  既存環境要因=miniruby+Tempfile, 本実装と無関係)。
- [Bug#18117] ポート負荷(8 Ractor が共有ポートに Time.now 送信+GC churn): **0/70**(修正前 ~35-50% クラッシュ)。
- 警告なしビルド。

### 4.3 ストレステスト
コア(§3.10/§3.11)修正に対し多角的に反復:
- **クラッシュ 0**: 決定的 clobber、move、グラフ(循環/別名/shareable leaf)、shareable-ref、value 往復
  (200 Ractor)、GC.stress、fiber/EC 最小再現。
- **エキゾチック型 33/36 がクラッシュ無し・値正**(大 Bignum、Rational/Complex、Float 特殊値、各種
  エンコーディング/coderange、シンボル、Struct/Data、多 ivar、深いネスト、compare_by_identity 等)。残り 3 は
  `initialize_clone` の呼び出し回数チェック(`#clone` 2回発火、§3.10)を捕捉したもので破損ではない。
- 極限並行ストレスでのみ §5.1 の UAF が顕在化(~7.5%)。

### 4.4 発見と網羅監査
- 並行 GC race を 6 個クラッシュ駆動 + 網羅監査で 2 個(`freed_ractor_local_keys`, `global_hooks`)発見・修正。
- 偽陽性(追わなくてよい): 共有シェイプツリー(`shape_tree_mark` はグローバル GC 専用)、dsymbol/fstring
  (pin+concurrent-set)、box_classext(FL_SHAREABLE→main)。
- **generic_fields_tbl / id2ref の per-objspace 化は却下**: frozen shareable の generic ivar は生成元 Ractor の
  表に入り跨ぎ読みされるので per-objspace でも跨ぎが消えない。本質的に共有 → NON_BARRIER ロックが正しい同期。

---

## 5. 残存課題

### 5.1 mark-T_NONE 並行族 — shareable VM インフラの解放が並行 GC と非整合
2026-05-31 の徹底ストレス(36 シナリオ)で判明した最大の残存系統。「**生き残った構造が、別 objspace で
解放されたオブジェクトを参照して dangling**」が共通根で、多数の症状を生む。

**この系統の中で修正できた個別インスタンス（コミット済み）**:
- **③ ローカル GC が他 Ractor の fiber/EC を歩く**(§3.11) ── commit a19485dfc。
- **cc/cme dangling**(commit e94190497): **クラスは全て shareable**(`Ractor.shareable?(Class.new)==true`)
  なので、匿名クラス k は ローカル GC では解放されず **global GC が到達性で回収**する。バグは cc/cme pin が
  **全 GC（global 含む）**で効き、dead クラスが global GC に回収されるのに cme が pin で生き残って owner を
  dangling 参照していたこと。pin を `!rlgc_global_gc_active` でゲート(shareable pin と同じく global GC では
  guard を外す)→ r4 4/20→**0/40**、s2 2/12→**0/15**。live クラスは m_tbl/cc_tbl から cc/cme を強くマーク
  するので生存、dead クラスは subtree ごと回収される。
- **GC.compact / verify_compaction_references**(move は per-Ractor objspace と非互換): RLGC 時は non-move
  full GC にゲート ── commit b134827c5。
- **★真の根本原因 = 孤児 objspace(ASAN 実証, commit 予定)**: ストレス群(fanin / gc_stress_everywhere /
  maximize_confined …)の SEGV はすべてこれ。**`rb_gc_objspace_free_local`(gc.c)は呼び出し元ゼロ**で、worker
  Ractor 終了時 `vm_remove_ractor`(ractor.c)が `vm->ractor.set` から外すだけで local objspace を解放も併合も
  しない=**孤児化**。`rb_gc_foreach_objspace`(gc.c)は main + `vm->ractor.set` のみ巡回するので孤児 objspace は
  **mark ビットがクリアされない**。そこに住む shareable クラス C(worker で生成 → make_shareable → main の
  held[] が保持)は**前回 GC の mark ビットが stale のまま**残る。次の global GC: 統一 mark は held[] 経由で C に
  到達するが(global GC では foreign-skip しない)、`gc_mark_set` が「既に marked(stale)」で 0 を返し
  **`gc_mark_children(C)` をスキップ → `RCLASSEXT_CC_TBL` を mark しない**。cc_tbl は main objspace 在住で mark
  ビットはクリア済 → unmarked → sweep で解放、なのに `RCLASS_WRITABLE_CC_TBL(C)` はまだそれを指す → 次の
  **lock-free cc lookup(`vm_lookup_cc`→`rb_id_table_lookup`)が解放済み `items` バッファを読む UAF**。ASAN の
  free スタック(`gc_global_sweep_one`→`vm_cc_table_free`→`rb_id_table_free_items`→`xfree(items)`)が地の真実。
  **修正(ローカル, main 不使用)**: 孤児 objspace を VM レベルのリストに保持し、`rb_gc_foreach_objspace` /
  `rb_gc_conservative_owner` / `rb_objspace_each_objects_all_ractors` がそれも巡回(`vm_remove_ractor` で
  `rb_gc_orphan_local_objspace` に渡す)。→ 次の global GC が孤児の mark ビットをクリア(C の stale ビット解消)→
  統一 mark が C を辿り cc_tbl を mark、sweep も巡回。**fanin/gc_stress/maximize_confined 12/12 → 0/12、
  btest_ractor 161/161、r4/③/msg 0**。これは §5.4 の「終了 objspace リーク」そのものだった。

  *誤診の記録(教訓)*: この系統を当初「cc/cme/inline-cache の cross-objspace dangling」「cc-table が freed cc を
  伝播」と読み、WB の T_NONE ガード(Layer-1)や cc-table の T_NONE-drop/skip ガード(mark_cc_entry_i /
  vm_cc_table_dup_i)を入れたが、いずれも**症状(witness)を叩くだけで根治せず**(fanin は 12/12 のまま、cc-table
  ガードはむしろ NULL deref を誘発)。自作の "ccs free-ring" も malloc アドレス再利用で交絡し site を誤指した。
  **ASAN が「解放されるのは ccs ではなく cc_tbl の items バッファ」「freed by = global sweep」を確定**して初めて
  孤児 objspace に辿り着いた。Layer-1(WB の T_NONE ガード)/ cc-table ガードは孤児修正後は**冗長と実測で確認し
  撤去済み**(orphan-only で fanin/gc_stress/maximize_global/longheld すべて 0/15、btest 161/161)。症状叩きの
  ガードを残すと将来のバグを隠すため、根治を入れたら撤去するのが正。

- **GC.compact / verify_compaction_references**(move は per-Ractor objspace と非互換): RLGC 時は non-move
  full GC にゲート ── commit b134827c5。

**残存(極小)**: 孤児修正が露呈した**空孤児 objspace の sweep クラッシュ**(`heap_pages_free_unused_pages` が
0-page objspace で `rb_darray_get(sorted,-1)`)は別途ガードで解消(nested_workers ~12% → 0/40)。残るのは
fiber_heavy 等 ~4% で、バックトレース上 **`<internal:ractor> receive` → `rb_obj_clone_setup` →
`rb_singleton_class_clone_and_attach`(class.c)** ── これは §3.10 の**メッセージコピー(受信側 clone)の
cross-objspace 寿命**族で、孤児修正とは独立の既知残存(別途 ASAN 調査が要る)。通常〜型多様ワークロードは 0。

**重要(再試行不要)**:
- 真因特定は **ASAN(または VM_CHECK_MODE+RGENGC debug)が決定打**。推論・アドレス交絡リングでは閉じない。
- **WB/mark/キャッシュ層のガードは全て症状叩きで失敗**(5連敗+Layer-1/cc-table)。根治は GC の objspace 巡回の
  カバレッジ(孤児を含める)であって、shareable の寿命判定や cc キャッシュ整合ではなかった。
- 孤児 objspace の**完全解放**(空になったら `rb_gc_objspace_free_local`)は未実装=objspace 殻はリーク継続
  (中身は回収される)。§5.4。

### 5.2 未監査で原理的に残るカテゴリ
1. **ユーザ定義 T_DATA の `dmark`/`dfree`** — ローカル GC 中に任意の C 拡張コードが走り任意の共有 C
   状態を触りうる(封じ込めモデルの根本的な穴)。要設計: custom-dmark を持つ T_DATA はローカル GC でマーク
   せずグローバル GC に委ねる等。
2. **JIT (YJIT/ZJIT)** — Rust 側の per-Ractor 相互作用・GC 外の共有表アクセスは未確認。
3. **`RUBY_INTERNAL_EVENT_FREEOBJ` フック** — ローカル sweep 中の発火で共有状態アクセス未追跡。

### 5.3 性能の follow-up
- グローバル GC の STW バリア(N=8 で ~13%)。major を「メモリ圧 or N 回ごと」だけグローバルにするスロットルは
  race 修正済みの現在なら再投入可。
- NON_BARRIER ロックを消す唯一の道: `generic_fields_tbl` を**並行ハッシュマップ**化(obj→fields の並行マップ
  インフラ新設が要る大作業)。

### 5.4 機能の follow-up
- **Ractor 終了時の objspace ハンドオフ/解放**: §5.1 の真因。**部分対応済み**: 終了 Ractor の local objspace は
  孤児リストに移し global GC が巡回(mark-clear/mark/sweep)するので、中身の死オブジェクトは回収され stale mark
  ビットも消える(UAF 解消)。**残: 空になった孤児 objspace 殻の解放**(`rb_gc_objspace_free_local` を空検出時に
  呼ぶ)は未実装で殻はリーク継続。設計案「最初に join した Ractor が継承(no-move)」は更に先。
- **cc/cme/cc_tbl/shape-edge の main objspace ルーティング**(足場=`main_newobj_cache` は未配線・休眠、
  `rb_gc_ractor_cache_alloc_on_main` 呼び出し元ゼロ)。これは **§5.1 の UAF の修正には不要**(孤児巡回で解決)で、
  純粋な**最適化/高速化**の選択肢として後回し。
- **`GC.stat`/`GC.total_time`** の per-objspace 集計未実装。
- make_shareable したユーザ shareable はローカル objspace に pin-while-live、グローバル GC でのみ回収。

### 5.5 既知の制約
- `RGENGC_CHECK_MODE`/`check_rvalue_consistency` は RLGC 非対応(cross-objspace 参照を偽陽性で報告)→ RLGC
  デバッグには信用しない(`rlgc_obj_in_any_heap` で緩和済みだが完全ではない)。confinement の検証は §3.12 の
  AUDIT を使う。
- 保守的マーク中の "out-of-heap" 表示は「**現在の(driver)objspace に無い**」の意味(別 objspace の有効
  オブジェクトでも出る)であって「解放済み」ではない。

---

## 付録A. 検討して棄却した設計案

§5.1/§3.10 に至る過程で検討し、実証付きで棄却した案を記録(再検討の出発点として)。

### A.1 メッセージを受信側へ「単一 clone で直接」確保 — 不可能(トリレンマ)
**(I) スナップショット意味論**(コピーは send 時確定)/**(II) lock-free ローカル GC**/**(III) 単一トラバース
で受信側着地** の3つは同時に取れない:
- send 時にコピー(I) ⇒ 送信スレッドで走る ⇒ 受信側 objspace へ確保するには foreign allocation(受信側の
  無ロックヒープへ第2スレッドが書込)= **(II) 破壊**。確保先は暗黙(`rb_gc_get_objspace()`)で `#clone` の全
  newobj が暗黙先へ行くため「出力だけ」を向けるのも不可能。
- receive 時に単一 clone(III) ⇒ **(I) 破壊**(send 後の変更が漏れる)+ 受信キューが送信側の生きた
  unshareable を参照(より悪い)。
→ (I)+(II) を守る道は「2回目のトラバースを受信側で」= 採用した **materialize-on-receive**(§3.10)のみ。
`main_newobj_cache` の足場が安全な前例に見えるが、main は `local==FALSE`+CR ロック+STW でしか回収されない
=受信側ローカルヒープの真逆で、転用不可。

### A.2 「ウルトラC」: 送信スレッド T1 を一瞬 R2 に所属させる — 不可能
T1 の「現在 Ractor」を clone の間だけ R2 にすれば単一 clone で受信側着地、という案。検証済みキラー:
(1) objspace と newobj_cache は密結合で objspace だけ向けると元バグ再現+cross-heap 破壊; (2)「Ractor 1個
だけ止める」プリミティブが無い(唯一の停止=全 Ractor STW barrier=削除した直列化); (3) ローカル GC のルート
集合は駆動スレッドの EC に固定で、T1 駆動の R2 GC は R2 の生存ルートをマークせず UAF; (4) V1(全身分フリップ)
は user `#clone` が R2 身分で走り `Ractor.receive` がメッセージ窃取等; (5) 非同期 send が同期ランデブー化し
相互 send でデッドロック。境界の論拠: 本実装は recv_queue/ports だけ foreign-writer-safe にし、allocation
ヒープは意図的に lock-free・foreign-writer 非対応のまま — borrow-R2 はこの境界を侵犯する。

### A.3 materialize-on-receive の「holder」追補(再コピー窓の堅牢化) — 無効・撤回
§3.10 残存(再コピー中に global GC でピンが消え source が解放される窓)を、再コピー中だけ source を受信側
Ractor(shareable)から辿れる holder に載せて `gc_shared_relation` で再ピンする案。実装し 60回 A/B 比較 →
holder有 4/60 vs holder無 5/60 で**有意差なし(無効)** → 撤回・コード除去。残存は holder では閉じない
(§5.1 と同系統)。

### A.4 cc/cme を「shareable クラス限定」で pin — 悪化・撤回
§5.1 の cc/cme dangling を「unshareable クラスの cc/cme は pin しない」で直す案。実装し実測 → r4 が
**4/20→8/20 と悪化**(dangling する子が owner→def-body→inline-cache へ移るだけ)。トレードオフを動かすだけで
解決しない → 撤回(コメントに記録)。

### A.5 メッセージコピーの他案
- **B: コピーを main objspace に確保** — UAF は直るが in-flight+受信済みコピーが main に浮遊し global GC まで
  回収されず main 肥大・STW 頻発でコスト不可。
- **F1: 明示 export darray + global 照合** — 正しいが永続ルート集合・reconcile・多段転送・終了リークの追加
  機構が重い。
- **F2: shared_bits を cross-objspace エッジへ一般化** — root エッジが不可視(`parent_object=Qundef`、
  `gc_shared_relation` は `SPECIAL_CONST_P(parent)` で早期 return)で `basket_free` 後の root 参照を救えず
  **不完全**。

---

## 6. 外部レビュー所見と要設計判断 (2026-06-01)

別レビュアーの総評: 性能方向(per-Ractor objspace + STW なし local GC + alloc cache-miss で VM lock 不取得)は
有望。ただし正しさは「少数の race を潰せば終わる」種ではなく、**CRuby 内部の shareable VM object の配置と寿命を
再設計し、local GC に参加できる object / callback / C-API の境界を明確化**する必要。本流に入れるなら少なくとも
**デフォルト OFF の実験機能**として、未解決の cross-objspace lifetime 問題を明示の上で。現在の shared_bits /
pin / T_NONE guard 等は妥当な防御だが根本解ではない(特に inline cache の弱い cross-objspace pointer は mark
時に完全補正できない)。

### 6.1 本セッションで解決済み(コミット済み)
- 主要 extreme-stress UAF = **孤児 objspace**(§5.1, ASAN 確定)→ orphan-list を global GC 巡回に含める
  (be9ea0120)+ 空 0-page sweep ガード(55c0578d4)+ 誤診ベースの masker(WB/cc-table guard)撤去(ec478dc4f)。
  36 ストレスシナリオ中 32 が 0/10、btest 161/161 + 2050/2050。
- 命名統一(confined→local, ebcf79309)、ASAN-buildable 化(arena recycle の unpoison)。

### 6.2 要設計判断(後で決定。優先順はレビュー準拠)
1. **shareable VM infra の寿命を VM root と揃える(最優先)**: cc/cme/cc_tbl/callinfo/shape-edge/classext は
   弱参照・キャッシュ参照・raw pointer を多く持ち、guard 積み増しでは別 call path で再発。レビューは
   main-objspace routing を本筋とするが、**ユーザ方針: main routing は「正しさ」のためには使わない(性能最適化の
   後回し選択肢)**。→ 「main に頼らず寿命を揃える機構」をどう設計するかが核心の論点。
2. **Ractor 終了時 objspace handoff 【ユーザ決定済】**: join した Ractor が継承 / 未 join のまま Ractor が
   GC されたら main が継承。**未実装**(現状は orphan-list で global GC が回収するが objspace 殻はリーク継続)。
   - `rb_gc_impl_objspace_free` の `heap_pages_lomem/himem=0` は **per-objspace マクロ**(=その objspace の
     `heap_pages.range`)なので mid-run の単一 objspace 解放自体は安全(当初の懸念は誤り)。
   - **真の壁(本セッションで実測判明)**: 「空になったら解放(free-when-empty)」を実装したが**全孤児で発火ゼロ**。
     計測すると各孤児に **T_ZOMBIE が最低 3 個**残り `total_allocated != total_freed` が永遠に成立しない。
     T_ZOMBIE = deferred finalizer / T_DATA の `dfree` 待ちで、**終了 Ractor にはそれを実行するスレッドが無い**
     ため永久に処理されない(ユーザ finalizer 無しの orphan_churn でも内部 T_DATA の dfree で発生)。
     → handoff は「**終了 Ractor の deferred finalizer / zombie を誰が実行/flush するか**」を決めないと
     リークが閉じない。#5(finalizer×RLGC)および §6.3 の d_finalizer/each_object と**同根・一体**。
   - サブ判断: (a) ページ併合(no-move で joiner の objspace に吸収=joiner の local GC が zombie 含め回収)
     vs (b) adopt(別 objspace のまま joiner/main が所有・zombie を実行してから global GC が回収・空で解放)。
     いずれも zombie 実行の主体(joiner スレッド? main?)の決定が前提。
3. **message copy の clone 二回呼び互換性**: materialize-on-receive で clone / initialize_clone が send 時と
   receive 時の二回呼ばれ、ユーザ観測可能な仕様変更。受容(仕様変更明示)/ 副作用なし内部 materialization /
   別の所有権移転、のいずれか。§6.3 の §3.10 UAF 根因とも一体。
4. **T_DATA / dmark / dfree / FREEOBJ hook の境界**: 任意 C 拡張が他 Ractor mutator と並行に走る前提でない。
   local GC 対象 T_DATA を declarative-marked / RLGC-safe 宣言型に限定し、他は global GC のみ mark/free。
5. **process-wide API semantics**: GC.stat / GC.total_time / profiler / ObjectSpace.each_object / GC.disable /
   GC.stress / malloc counters / finalizer / object_id / weakref / event hook が current objspace の意味に
   変質。各々 current か全 objspace かを決定。`rb_gc_register_mark_object()` 等 current-objspace heap 判定で
   foreign object を弾く箇所は正しさにも影響。
6. **root set 完全性**: VM global root / C API global registration からのみ参照される local object の生存策。
   JIT state / coverage / debug gem / objspace ext / `rb_objspace_each_objects()` 利用箇所が current か全
   objspace かを個別決定。
7. **shared_bits soundness の C 全体監査**: 「s→u edge は u の owner が作る」前提を、raw write / MEMCPY /
   clone-move / generic ivar / classext / managed id table / shape tree / JIT pointer update 等の**非 WB
   経路**で監査(現状は Ruby レベル隔離規則に依拠、C 実装全体の監査は不足)。

### 6.3 本セッションで判明し**修正完了**したバグ(設計判断不要・ローカル健全修正)
3つとも「**global GC は全 objspace を clear+sweep するのに root mark が driver 分しか辿らない**」という
**単一の根**の別現れだった。共通の健全修正パターン = 各 per-objspace root を **global GC(STW)中に**辿る/
再 pin する。STW なので他 objspace のビットマップへ書いても**並行 writer が居らず race しない**(従来「受信側
re-pin は cross-objspace data race で不健全」と判断していたが、それは**local GC 中**の話。global GC 限定なら健全、
が突破口だった)。判定は `rb_gc_during_local_gc_p()`(global GC のとき false)。

- **§3.10 受信クローン UAF(解決)**: in-flight copy `v`(送信側 objspace 在住)の送信時 pin(shared_bit)を
  途中の global GC が全クリアし、`gc_shared_relation` の再 stamp 対象でもないため、v が **queued のまま** unpin
  になる。送信側 local GC は受信側 queue を走査しないので、unpin かつ送信側 root でない v を sweep →
  受信側が解放済み v を dequeue → `ractor_copy(v)` で SEGV(`ractor.c:2156`←`ractor_basket_accept`)。
  **修正(2層, 両方 global GC 限定で re-pin = race-free)**:
  - **A. queued 窓**: `ractor_basket_mark`(ractor_sync.c)で `!rb_gc_during_local_gc_p()` のとき
    `rb_gc_pin_in_flight_message(b->p.v)` を再 stamp → 全ての in-flight メッセージの pin が global GC を跨いで
    恒久化。
  - **B. gap 窓(dequeue 後〜`ractor_copy` 完了)**: queue 外なので A が効かない。受信側 Ractor に
    `sync.in_flight_materializing` スロットを追加し(`ractor_core.h`)、`ractor_basket_accept` が `ractor_copy`
    の前後で set/restore、`ractor_sync_mark` がこれを mark + (global GC 限定で) 再 pin。→ `ractor_copy` 中に
    global GC が来ても v が再 pin され、続く送信側 local GC が解放できない。
  - 検証: `d_frozen_in_unfrozen_compact` 1/10→**0/60**、#161/fiber_heavy/fanin/deep_graph/move 等 §3.10 系
    **全て 0**。
- **finalizer × RLGC(解決)**: `finalizer_table` は **per-objspace**。worker が `define_finalizer` すると
  隠し値 Array `[obj_id,proc]` が worker の table からのみ到達可能。global GC は全 objspace を clear+sweep する
  のに root mark は driver の table しか辿らない(`mark_roots` default.c)→ worker の値 Array が sweep されて
  table がダングリング →(A) `run_final` の UAF /(B) worker の次の local GC で `pin_value` が T_NONE を mark。
  **修正**: `mark_roots` 内で `rlgc_global_gc_active` のとき `rb_gc_foreach_objspace` で**全 objspace の
  finalizer_table を driver 文脈で `pin_value`**(`gc_mark_other_objspace_finalizer_table_i`)。pin は値自身の
  ページに付くので cross-objspace でも健全。→ `d_finalizer_churn` 10/10→**0/20**、`d_objectspace_each_object`
  10/10→**0/20**。
- **§3.10 と finalizer の絡み(解消)**: かつて finalizer 修正単体を入れると #161 が 0→~100% で壊れた。これは
  finalizer 修正の僅かな timing 摂動が §3.10 の脆弱なレースを常に負けさせていたため。§3.10 を A/B で堅牢化した
  今は **両修正を同時に入れても #161=0/40・btest_ractor 161/161・btest 2051/2051**。entanglement は解消。

**回帰**: btest **2051/2051**、btest_ractor **161/161**、警告なし。

### 6.4 root fiber の saved stack が local GC で未マーク(解決, pre-existing)
`fiber_transfer_coroutine_hammer` が ~6% で `[BUG] try to mark T_NONE (obj: out-of-heap, parent:
fiber/Fiber)`(`cont_mark` cont.c:1145 → `rb_execution_context_mark` vm.c:3715, suspended fiber の VM
スタック `p[i]` マーク中)。**§3.10/finalizer 修正を stash したコミット状態でも 3/50 再現 → 別の独立バグ**。
**根本原因**: child Ractor の **root fiber の wrapper オブジェクトは親(main)スレッドで `Ractor.new` 時に生成
され main objspace に在住**(cont.c:1155-1160 のコメント既述)。worker の **非 root fiber が走行中**に
worker が local GC すると、`rb_gc_mark_thread_roots`(vm.c)は走行中 fiber(`th->ec`)を直接マークするが、
root fiber は wrapper 経由でしか辿られず、その wrapper は foreign(main)なので `gc_mark`(default.c:5088)で
skip → `cont_mark` 未実行 → **root fiber の saved stack 未マーク** → そこにしか無い worker オブジェクトを
worker local GC が解放 → 後続 global GC が root fiber をマーク(global では skip 無し)して T_NONE 検出。
**修正**: `rb_gc_mark_thread_roots` で、root fiber が suspended(`th->root_fiber != th->ec->fiber_ptr`)の
とき、その cont を **直接マーク**(`rb_gc_mark_fiber_saved_context` → `cont_mark`)。`cont_mark` の owner
ベース foreign 判定(owner=worker=marker)は通るので正しくマークされ、fiber グラフ全体が再 root 化される。
→ `fiber_transfer_coroutine_hammer` 3/50→**0/80**、fiber 系全シナリオ 0、test_fiber/test_gc/test_gc_compact
/test_thread/ractor(`-j1`)0 failures、btest 2051/btest_ractor 161 維持。
（注: `make test-all -j`(並列ワーカー)では Ractor-local storage builtin 解決の pre-existing な並列レースで
`uninitialized constant Ractor::Primitive` が散発。`-j1` で消える=テストハーネス側の別問題、本修正と無関係。）

### 6.5 worker 内 old→young remembered-set 漏れ → **TSan で根本特定・解決**(pre-existing concurrent race)
`fibers_escaping_objs_reuse_hammer`(`Fiber.yield`/`resume` + 各 fiber が `longlived` に obj を蓄積 +
main で hammer global GC)が **~0.4%** で `[BUG] try to mark T_NONE (obj: out-of-heap, parent:
out-of-heap)`。backtrace = global(major)GC の `gc_mark_children`(gc.c:3703 → default.c:5313)で、
**生存中の worker オブジェクト P の子 C が T_NONE**(cont_mark/fiber EC ではない=§6.4 とは別)。P も C も
同一 worker objspace 在住(両方 main から見て out-of-heap)→ **worker 内の old→young エッジの remembered-set
漏れ**。仮説: hammer の頻繁な global(major)GC 後に worker の若い生存者が昇格しきれず、old 親 P が worker の
remembered-set に無い状態で次の worker minor GC(`full_mark:false`)が young 子 C を解放 → 後続 global GC が
P をマークして T_NONE 検出。= 「global GC が per-objspace 構造(ここでは世代/remembered-set)を全 objspace 分
正しく再構築できていない」同系統の可能性。
- **再現困難**: ~0.4%(0/120 等で頻繁に空振り、増幅シナリオでも 0/40)。HEAD/§3.10+finalizer-only/baseline
  4e8768968 いずれも ~0/100超 で**私の3修正とは無関係(pre-existing)**と bisect 確認。
- **RLGC 対応 verify を整備した(commit 2e9b8445f, §A 更新)が、このバグは捕捉できなかった**:
  `gc_verify_internal_consistency` を RLGC 対応化(cross-objspace エッジskip / current-objspace の during_gc
  も一時 FALSE / 会計系 assert を multi-ractor で skip)し、`RUBY_GC_VERIFY=1` で通常ビルドから有効化可能に。
  これで `check_generation_i`(old→young remembered-set 漏れ)を毎 GC の marks_finish で検査できるが、
  **`RUBY_GC_VERIFY=1` で fibers_escaping を 665 回流して 0 catch**(0.4% なら 665回で0は ~7%、precondition が
  より高頻度なら更に低確率)。
- **∴ これは steady-state の remembered-set ロジック違反ではなく、負荷依存の concurrent race**:
  - verify は `RB_GC_VM_LOCK`+`rb_gc_vm_barrier`(全 Ractor 停止)で snapshot 検査するため、**並行 GC の
    timing 窓をマスク**して捕捉できない。
  - クラッシュ率が**負荷依存**(重いセッション負荷時 ~1/30、idle 時 0/372、並行多重実行 0/72)。
  - 機構の推定: worker の世代/remembered/age/mark ビット等のメタデータを、worker の lock-free local GC と
    global GC(または並行する別 local GC)が**同期なしに並行アクセス**するデータレース。RLGC は「max 8
    concurrent local GC + STW global GC」で、既に 6 件の concurrent-GC レースを修正済み(memory 参照)— 本件は
    その同族の残り。
- **ThreadSanitizer で根本原因を確定(out-of-tree tsan build, multi-Ractor old→young workload)**:
  非 fiber の純粋 repro(`nofiber_oldyoung_race`)を TSan 実行 → **page bitmap の非アトミック RMW レース**を直接
  検出。`MARK_IN_BITMAP` は `bits[i] |= mask` で、**lock-free write barrier が全 Ractor の mutator で並行実行**+
  並行 local GC が、同じ `remembered_bits`/`shared_bits` ワードを同期なしに RMW。1 ワード=`BITS_BITLENGTH`
  スロットなので、**並行 set の lost update が同ワードの別オブジェクトの remember/shared bit を落とす** →
  その old object が次の minor GC で scan されず young 子が解放 → 後続 global GC が T_NONE。TSan が
  `rgengc_remembersetbits_set` / WB の `GET_HEAP_SHARED_BITS` set を複数スレッド同時書込として報告。
  これが**負荷依存**(並行度が上がるほど lost update 発生)+ **verify(barrier）で捕捉不能**(STW が窓を消す)
  の説明。
- **修正(2 commit)**: (1) `7fb4d8385` 並行書込される bitmap(shared_bits/remembered_bits)を **atomic CAS**
  で set(`gc_bitmap_atomic_set`/`MARK_IN_BITMAP_ATOMIC`、bits_t はポインタ幅=size_t CAS)、remembered-set の
  drain を **atomic exchange**(read-and-clear)化、`has_remembered_objects` を bit set の後にセット +
  rememberset_mark は drain 前にクリア。 (2) `596402873` 並行書込される **page→flags(has_remembered/
  has_uncollectible/has_shared)を bitfield → `unsigned char`** に(各自バイト=full-byte store はアトミックで
  sibling フラグを失わない;bitfield ワードの RMW lost update を解消)。
- **検証**: btest 2051/btest_ractor 161 維持・警告なし;**TSan: remembered/shared/flag の write-write
  lost-update 消滅**(131→95、残りは has_shared の冪等 TRUE/TRUE バイト書込・bit テストの read-vs-atomic-write・
  pre-existing な heap-page-allocation report=別系統);**高負荷 crash repro 0/128**(修正前は負荷時 ~1/30)。
- 副産物: RGENGC_CHECK_MODE(snapshot verify）は **concurrent race には原理的に不適**(barrier が窓を消す)と
  実証。RLGC の lock-free 設計では並行書込される全メタデータの atomicity を TSan で継続監査すべき
  (残る pre-existing race: heap_page_allocate 系、gc_aging の shared object flags 書込など=別タスク)。

### 6.6 TSan 監査(継続)— 残レースの分類と対処
§6.5 の bitmap lost-update を潰した後、`nofiber_oldyoung_race` を TSan で再走し残レース(~95)を 6 カテゴリに
分けて triage(並列分析)。**real は 2 件のみ、他は verified-benign**:
- **REAL ① gc_aging が shareable の flags を非アトミック RMW**(local GC)→ local GC では shareable を aging
  しない(`26aed2c45`)。
- **REAL ② rb_gc_impl_objspace_init が process-global を子 Ractor init 毎に再書込**(`init_size_to_heap_idx`/
  `heap_page_alloc_use_mmap`/`gc_params.heap_init_bytes`)→ 一度きり guard + heap_init_bytes 書込削除(`26aed2c45`)。
- **hygiene**: grow-only な heap span 境界(`rlgc_global_lomem/himem`)の読みを relaxed atomic 化(`631c09673`)。
- **benign(high-confidence で確認, 修正不要)**:
  - `has_shared_objects` バイトフラグの read/write: global STW GC 以外では **FALSE→TRUE 単調 + 冪等 TRUE 書込**、
    危険対象(unshareable 境界子)は GC 駆動中の所有 Ractor の program order、かつ local sweep は shareable を
    解放しない(default.c の sweep pin)。
  - WB の shared_bits 1-bit テスト読み: `||` 短絡で `a` が unshareable のときだけ読み、`a` の bit の唯一の
    writer は同一スレッド(program order)か STW global GC(barrier happens-before)。1-bit テストは old-or-new
    を許容。
- **残 ~87 の TSan report の正体**: 大半は **VM の lock-free callcache/inline-cache dispatch(`vm_sendish`,
  shareable VM インフラ=GC 外)の atomic-write vs non-atomic-read** と、上記 benign な GC フラグ/bitmap の
  read-vs-atomic-write。完全な TSan-clean 化には、意図的 lock-free 設計の read 側を全 atomic 化/annotate する
  必要があり、cc/ic のメモリモデルを把握した上で**別途**行うべき(GC 側の lost-update 系 real race は解消済み)。
- **検証**: btest 2051/btest_ractor 161 維持・警告なし;全36シナリオバッテリ 720回 0;高負荷 crash repro 0/128。

### 6.7 バグあぶり出しで発掘した3つの新規・高再現クラッシュ(secondary face 修正済、dominant face は OPEN)
TSan を多様パスに展開 + 未開拓 RLGC 相互作用を狙う adversarial シナリオを生成して、既存36シナリオが
見逃していた**確実に再現する新規クラッシュ3件**を発掘(repro: `$TMPDIR/gen2/`)。triage(ASAN+コード)で
各々の real な secondary face を修正(`13f6db3a5`、回帰なし)したが、**支配的 face は RLGC の shareable
寿命に関わる深い問題で未解決**:
- **`compact_xractor_sharedbits_fullgc_hammer`(~100%)** `mark T_NONE`(parent out-of-heap=worker, child
  T_NONE=main)。**fixed face**: main の非 global GC が、worker からのみ live な shareable(Ractor body の
  isolated env 等)を解放(sweep guard が `objspace->local` で main を除外)→ guard を `(local||rlgc_has_local)`
  に拡張。**dominant OPEN face**: `GC.compact`(+full GC)が **cross-objspace 参照される main の shareable を
  移動/その subtree を解放し、worker 側の参照が未更新** → dangling。= compaction × cross-objspace 参照更新、
  または shareable の subtree liveness(shareable は sweep guard でピンされるが自 objspace の root から到達せず
  マークされないため子が辿られない)。design レベル。
- **`termination_orphan_vs_global_gc`(~100%)** message clone の method search で **解放済み class の m_tbl
  (id_table)を参照**して SEGV(`vm_search_cc`→`rb_id_table_lookup`)。**dominant OPEN face**: 終了/orphan
  Ractor の objspace に作られた shareable class(cc_tbl/m_tbl 付き)が cross-objspace 保持されたまま、その
  m_tbl/subtree が GC に解放 → 後の dispatch が dangling。= cc/cme lifetime 残課題(§5.1、no-main-routing 制約下で hard)。
- **`id2ref_cross_ractor_idtable_gc_race`(~100%)** `object_id0`→`st_insert` SEGV。**fixed faces**:
  id2ref_tbl の free/insert を VM ロックで直列化(SEGV 解消)+ worker local GC が自 objspace の VM-global
  `id2ref_value` を解放しないよう keep-alive。**dominant OPEN residual**: `Object ID seen, but not in
  _id2ref table`(id2ref_value が最初に `_id2ref` を呼んだ worker objspace に置かれ、その寿命管理が完全でない;
  VM-global を worker objspace に置く設計上の齟齬)。
→ 3件とも **「shareable / VM-global オブジェクトが worker(または orphan)objspace に住み、cross-objspace で
live なのに、非 global GC / compaction がその subtree や寿命を正しく扱えない」** という同一の設計領域に収束。
**設計判断パス(shareable 寿命・objspace 所有・handoff)と一体で扱うべき**。repro は永続回帰テストとして保存。

**残課題(設計判断が要る別件、クラッシュではない)**: handoff(#2)を阻む終了 Ractor の T_ZOMBIE(未実行
deferred finalizer/dfree の実行主体)、§5.4 空孤児殻リーク、d_shape_churn の compact+stress 下の遅さ(perf)、
TSan の cc/ic lock-free read 側 annotate(by-design, 別タスク)。

### 6.8 網羅サーフェシング(batch 3–4, 26 サブシステム×adversarial シナリオ)
「あぶり出しフェーズ」として、未開拓サブシステム×cross-feature 組合せを 26 シナリオ生成し、HEAD バイナリ
(ractor-local-gc, `RUBY_RACTOR_LOCAL_GC=1`)で各 5 回再現確認。**4 件が確実に再現**(repro 永続化: `rlgc_repro/`):

- **`embed-to-heap-transition`(4/5)** `mark T_NONE`(parent `T_ARRAY` out-of-heap=worker, child out-of-heap)。
  Ractor receive/copy 経由(`<internal:ractor>`)。→ **Face A**(§6.7 dominant・§5.1 と同根)。
- **`proc-binding-eval-iseq`(2/5)** `mark T_NONE`(parent/child とも out-of-heap)。`GC.start` 中、binding/proc/
  iseq subtree のノードが cross-objspace 参照下で解放。→ **Face A**。
- **`combo-terminate-compact`(5/5)** `SEGV@0x38`。終了 Ractor の orphan objspace × `GC.compact`。→ **Face C**
  (§6.7 `compact_xractor` dominant OPEN と同根)。
- **`autoload-const-cc`(5/5)** `[BUG] Aborted`(corrupted VALUE `0x3e8...`)、`remove_const` CFUNC 経由。**T_NONE
  ではない新系統 = Face B**: autoload/const-cache(IC/`vm->constant_cache`)が cross-objspace const 操作 + GC で
  dangling。cc lifetime(§5.1)に隣接する**未記録の独立 face**。

**clean(頑健性を確認した主要サブシステム, 20 件)**: regexp/MatchData, IO/StringIO, Marshal deep-graph,
Enumerator::Lazy+Fiber, Bignum/Rational malloc, refinement cc, TracePoint-during-GC, singleton-method churn,
generic-ivars storm, Encoding/coderange, Fiber scheduler, deep machine-stack, ObjectSpace.dump/memsize,
**Mutex/Queue/SizedQueue/CV(~45 runs 0)**, **Method/UnboundMethod/cme/cc_tbl(~50 runs 0)**, Thread variables,
Comparable/sort, Set, frozen-string dedup, weak/finalizer×terminate。
重要なネガティブ知見: **shareable Method/UnboundMethod は cme/def/iseq/owner subtree を home objspace に pin する**
ため u→s liveness 不変条件が保たれクラッシュしない(§1.2 の裏付け)。エージェント報告の `freeze-dup-clone-edge` /
`hooks-inherited-added` は HEAD 5 回で再現せず(低頻度/環境差)。

→ **収束**: 新規 4 件は **Face A(cross-objspace subtree liveness → mark T_NONE; dominant)**, **Face B(const/IC
cache lifetime; 新規・独立)**, **Face C(orphan × compaction SEGV)** の 3 面に整理。A/C は §6.7・§5.1 の設計判断と
一体、**B は cc lifetime 隣接の新タスク**として記録。いずれも非クラッシュの data-only サブシステムは全て clean で、
バグは「VM 内部参照(iseq/cme/IC)を持つ or VM-global なオブジェクトが worker/orphan objspace に住み、cross-objspace
で live なのに非 global GC / compaction が subtree 寿命を扱えない」領域に限局する、という §6.7 の結論を強化。

### 6.9 網羅サーフェシング(batch 5–6, 24 サブシステム)+ クラッシュ全 face 分類(A–F)
batch 5(14, 未開拓 VM-global テーブル + Ractor 機構)+ batch 6(10, 残り VM-global テーブル + Port/finalizer)
で **12 CRASH / 12 clean**。全クラッシュを **6 face** に確定分類。**うち B/D/E/F は設計判断不要・コード裏取り済の
tractable バグ**(local-sound な修正方針あり)、A/C のみ設計判断と一体。repro は `rlgc_repro/`(b4/b5/b6)に永続化。

| Face | 種別 | 根本(コード裏取り) | repro / HEAD 再現 | Task | 修正方針 |
|---|---|---|---|---|---|
| **A** | design | cross-objspace の object subtree(Array/Struct/Data/iseq/binding/backtrace T_DATA)を非 global GC / compaction が解放 → `mark T_NONE` | `move_embedded_struct`(5/5), `ractor_select_recv_copy`(5/5), `exc_backtrace`(8/8 既知), `s7`(~11%) | #3 | (設計: §5.1) |
| **B** | locking | `Module#remove_const`(object.c:4682, **無ロック CFUNC**)→ rb_const_remove(variable.c:3649)が ① const cache の `rb_clear_constant_cache_for_id`(:3675)を**無ロック** `set_table_foreach`、concurrent な locked `set_insert`(vm_insnhelper.c:6412)の rehash と競合 → garbage IC → SEGV(vm_method.c:323)/Aborted ② `autoload_delete`(:3072)が `autoload_features` VM-global hash を**無ロック** `rb_hash_delete`、concurrent autoload と競合 | `b4_autoload-const-cc`(**5/5**), `b5/const_cache_…`(低頻度), `b6/autoload_features_…` | #6 | remove_const に VM ロック(const_set:3957 / const_tbl_update:4033 に倣う) |
| **C** | design | orphan 終了 Ractor の objspace × `GC.compact` → SEGV | `b4_combo-terminate-compact`(5/5) | #3 | (設計) |
| **D** | mark gap | VM-global `concurrent_set` の backing(NOT WB_PROTECTED)が resize 時に **load-factor を超えた Ractor の objspace** に確保 → その worker の lock-free local GC が `rb_gc_mark_roots`(gc.c:3445)で `rb_vm_mark`/`global_symbols`(:3484/:3513)の前に return するため未マーク → sweep → UAF。`id2ref_value` keep-alive(gc.c:3476)と**完全同根** | `b5/fstring_table_…`(確認中), `b5/dsym_…`(**7/30** SEGV@0x4), `b6/symbol_id_entry_bucket_…` | #7 | id2ref keep-alive を fstring_table_obj / ruby_global_symbols へ拡張(自 objspace 在住時にマーク) |
| **E** | missing guard | `GC.auto_compact=true`(gc_set_auto_compact, default.c:10152)が立てる `ruby_enable_autocompact` を 6615/7428 で**無ガード**参照 → `during_compacting=TRUE` → RLGC 下で full/global GC が compaction → corruption。`gc_compact`(:10286)/`gc_verify_compaction_references`(:10366)は `if(rlgc_has_local) compact=false` でガード済なのにここだけ抜け | `b6/autocompact_…`(**agent 15/15**, code-verified) | #8 | 同じ `rlgc_has_local` ガードを auto_compact 参照点に追加 |
| **F** | ownership routing | `define_finalizer`(gc.c:2079)が `rb_gc_get_objspace()`=**呼び出し元 Ractor の objspace** に登録(key の所有者でなく)+ foreign object に `FL_FINALIZE` → `run_final`(default.c:3398)が**所有者の** finalizer_table を `st_delete` → entry 不在 → `rb_bug`(:3417)。`copy_finalizer`(:3360)は RLGC ルーティング修正済だが `define_finalizer` は未修正 | `b6/cross_objspace_define_finalizer_…` | (新) | copy_finalizer 同様に key 所有者の objspace へルーティング |

加えて **`port_inflight_copy_global_gc_unpinned`**(Ractor::Port 明示 API の in-flight copy message が global GC
跨ぎで unpin)= §3.10/§6.3(1)の in-flight pin 再 stamp が Port 経路で取りこぼす**残 face**(Face A 系、要追確認)。

**clean(頑健・強い negative, 12 件)**: $グローバル変数表(全 worker 書込が IsolationError or per-Ractor slot;
共有 slot に入る $/, $-i は frozen-shareable で pin され安全 ⇒ §3447 の "VM globals live in main" 仮定が $globals
には**成立**), gccct, overloaded_cme(shareable-pin), loaded_features, encoding 表, shape tree(edge table が
`RB_OBJ_SET_SHAREABLE` で local GC 回収不可), cvar cache, WeakMap/WeakKeyMap, eval/iseq/env, ObjectSpace.each_object
(concurrent global GC 下), fiber storage, identity-hash rehash(compaction)。
ネガティブの要点: **shareable がその subtree を home objspace に pin する不変条件(§1.2)が効く領域は全て clean**;
クラッシュは「① shareable でない or pin が効かない cross-objspace 参照(A/C)」「② VM-global テーブルが
worker/orphan objspace を前提していない(B/D/E/F)」の 2 系統に限局する、と確定。

**サーフェシング結論**: 設計判断と一体なのは **A(cross-objspace shareable/object subtree liveness)** と
**C(orphan × compaction)** の 2 面のみ。残る **B(remove_const 無ロック)・D(VM-global concurrent_set の worker
所有)・E(auto_compact 未ガード)・F(define_finalizer ルーティング)** は**いずれも local-sound に修正可能**で、設計
判断を待たずに着手できる。E は最も再現性が高く修正も最小(1 ガード)、D は既存 id2ref 修正の素直な一般化。

### 6.10 設計判断不要の 4 面(B/D/E/F)を修正(本セッション、あぶり出し→修正ループ)
§6.9 で「local-sound に修正可能」と整理した 4 面を、各々「repro 再現確認 → 修正 → リビルド → repro 消滅を多数回
検証 → 回帰(btest/btest_ractor + 機能テスト)→ コミット」のループで実装。全て **btest 2045 / btest_ractor 161 で
機能的回帰ゼロ**(失敗は partial build の stdlib `LoadError` 4 件=tempfile/tmpdir のみ、修正前後で同一)。

- **Face E**(`95c551e7b`, gc/default/default.c): `gc_marks_start`/`gc_start` の `ruby_enable_autocompact` 参照点に
  `&& !rlgc_has_local` を追加(gc_compact と同一ガード)。auto_compact が RLGC 下で compaction を起こさない。
  repro **6/6 → 0/12**(tiny 0/8)。非RLGC の auto_compact は従来通り動作。
- **Face F**(`72ad765aa`, gc/default/default.c): `rb_gc_impl_define_finalizer`/`undefine_finalizer` を
  `rlgc_finalizer_table(GET_HEAP_OBJSPACE(obj))`=**key 所有者の table** にルーティング(copy_finalizer と同型)。
  `run_final` の table と一致し `rb_bug` 解消。repro **8/8 → 0/12**。finalizer 実行/undefine は機能維持。
- **Face D**(`f100f23ba`, gc.c + string.c + symbol.c + internal/{string,symbol}.h): ① local-GC root branch に
  `gc_keepalive_vm_global_if_local()` を追加し id2ref_value + fstring 表 + symbol set/ids を「自 objspace 在住時
  のみ」マーク(concurrent_set の dmark は no-op なので entries 非伝播=leak 無し)。② symbol id-entry bucket は
  main の `ids` 経由でしか辿れないため、`set_id_entry` で `RB_OBJ_SET_SHAREABLE`(shape edge table と同型)し
  local-sweep からピン。repro **dsym 7/30→0/30, fstring 0/30, symbol-bucket 20/20→0/20**。symbol/sym2id/fstring
  dedup/cross-Ractor intern は機能維持。`rb_concurrent_set_new` 呼出元は sym_set/fstring の 2 箇所のみ=網羅。
- **Face B**(`808e41fd9`, variable.c): `rb_const_remove` の **lookup+削除を `RB_VM_LOCKING()` 内で atomic 化**
  (const_set と同型)。並行 remove の `rb_const_entry_t` 二重 free と、`rb_clear_constant_cache_for_id` の
  set_table walk × 並行 insert rehash を解消。not-found raise と deprecation 警告(Ruby コードを走らせ得る)は
  ロック外へ遅延(deprecated フラグはロック内で捕捉)。repro **autoload-const-cc 15/15→0/12**。

**Face B から分離した残 1 件(設計案件・defer)**: `autoload_delete`(rb_hash_delete)が VM ロック下、`Module#autoload`
(rb_hash_aset)が autoload_mutex 下で **異なるロック**のまま `autoload_features` ident hash を変更 → heap corruption
(repro `b6/autoload_features_…` 9/15)。autoload の LOAD 経路(require)が autoload_mutex 下で VM ロックを取り得る
ため、単純に一方へロックを足すと **VM-lock↔autoload_mutex の順序逆転 → デッドロック**。autoload サブシステム全体の
ロック順序を統一する設計が要る(別タスク)。**残る設計案件は A / C / autoload_features の 3 つ**。

### 6.11 confinement-miss 族の新面 Face G(thread 割り込み mask-stack)を修正(batch 7)
未開拓サブシステム14領域の adversarial サーフェシング(batch 7)で、**決定的に再現する新面1件**を発掘(他に低頻度
未確認2件、clean 12件)。新面は §6.4 root-fiber と同じ **「foreign edge 経由でしか辿れない子オブジェクトを confined
local GC が回収する」confinement-miss 族**で、同型の re-homing で修正:

- **Face G**(`f8885699f`, thread.c): `thread_create_core`(thread.c:885-888)が Ractor main thread の
  `pending_interrupt_queue`/`pending_interrupt_mask_stack` を、**spawn 元(親)スレッド上で・子 objspace 生成
  (`rb_ractor_living_threads_insert`)より前に確保** → 両配列が親 objspace に住む。`Thread.handle_interrupt` が
  子 objspace の(非shareable)mask Hash をその foreign 配列に push → 子の confined local GC が親 objspace の配列を
  foreign-skip(default.c:5162)し、その配列経由でしか辿れない mask Hash を未マーク → sweep → 割り込み配送で
  `rb_threadptr_pending_interrupt_check_mask` が UAF(決定的 SEGV)。**修正**: `thread_start_func_2`(新スレッド上
  =子 objspace で実行)冒頭で両配列を re-dup(`RBASIC_CLEAR_CLASS` で hidden 維持、`thread_invoke_type_ractor_proc`
  限定)。継承マスク/キュー済み割り込みは保持。repro **15/15 → 0/15**(stress/tiny 含む)、handle_interrupt の
  マスク/遅延セマンティクス維持、btest 2045 / btest_ractor 161 回帰なし。
- **clean(頑健、12件)**: refinement cc/cref/cme(orphan 含め 101+ runs 0; 理由=refinement cc は shareable imemo で
  sweep guard にピンされ、weak-set prune は global STW で sweep 前に走る)、m_tbl/cme/cc churn、method hooks、
  singleton class、Ractor-local storage、imemo env/cref/svar/throw_data、ruby2_keywords flagged hash、pattern-match
  deconstruct、GC/ObjectSpace introspection × global STW、make_shareable cyclic/deep half-shared orphan、orphan storm。
  → cc/cme/m_tbl/imemo の機構は RLGC 下で概ね robust(shareable-pin + global-STW-prune で守られている)。
- **未確認2件**(HEAD 全構成 0/12、エージェント環境差/極低頻度): `concurrent_include_prepend`(shareable な非frozen
  class への並行 include/prepend が iclass を破壊 — make_shareable は Class を freeze せず `rb_class_modify_check` は
  frozen のみ阻止、の主張)、`marshal_usrmarshal…mark_tnone`。前者は TSan 向き候補として repro 保存。

**修正済みクラッシュ面の総括(本作業)**: B(remove_const lock)・D(VM-global concurrent_set keep-alive + symbol
bucket pin)・E(auto_compact guard)・F(define_finalizer routing)・G(thread 割り込み re-homing)。**残る設計案件は
A / C / autoload_features**。

### 6.12 confinement-miss 体系監査(batch 8)— 2件追加修正、4件は delicate/design として記録
batch 8(12領域、confinement-miss 族 + copy/send + 未カバー)で **新規クラッシュ6件**(5件決定的・1件低頻度)、
clean 6件。**#12 の「親 objspace で確保される thread/ractor フィールド」体系監査**が効き、Face G の兄弟を複数発掘。
2件を同型で修正、残4件は tractable の境界を越えるため task 化:

- **fiber_storage(Face G-2)**(`c0e1c99fe`, thread.c): Ractor main thread の `ec->storage`(fiber storage Hash)を
  `rb_fiber_inherit_storage` が親で確保 → 子 objspace の Fiber[] 値が foreign Hash 経由でしか辿れず sweep。
  Face G ブロックを拡張し `ec->storage` も `rb_obj_dup` で re-home。**12/12 → 0/12**、継承/子ストレージ機能維持。
- **trap handler**(`51819fc7b`, gc.c): 非main Ractor の `Signal.trap` String command handler が worker objspace 在住で
  VM-global `vm->trap_list.cmd[]`(`rb_vm_mark` 非confined パスのみ)からしか辿れず sweep → 信号配送で freed String を
  eval。local branch で `trap_list.cmd[]` を `gc_keepalive_vm_global_if_local`(Face D helper)で if-local マーク(固定
  配列・pointer-atomic read)。**12/12 → 0/12**、Proc/String handler 発火維持。
- **clean 6件**: fiber_scheduler、WeakMap/WeakKeyMap、Encoding::Converter、Proc/Method callable(curry/compose/
  to_proc/UnboundMethod/define_method — 非shareable Proc は send 不可、唯一の脱出 Ractor#value も既存 orphan 経路で
  処理済)、enumerator-fiber、TracePoint。

**残4件(tractable の境界外、task #14-16/#4)**:
- **at_exit/END proc**(#14, 12/12 mark-T_NONE): worker の at_exit proc が VM-global `end_procs`(`rb_mark_end_proc`
  非confined のみ)からしか辿れず sweep。trap と違い `end_procs` は **lock-free prepend のリンクリスト**(eval_jump.c:60、
  ロック無し)。固定配列の trap と異なり **weak-memory での publication ordering(`link->next` 可視性)**が絡むため、
  単純 iteration は弱メモリで不安全 → release/acquire か rb_set_end_proc のロック化が要る(delicate)。
- **thread_variable**(#15, 12/12 SEGV): `Thread#thread_variable_set` の locals Hash は **th->self(Thread obj)の ivar**
  (thread.c:128 `rb_ivar_set(thread, idLocals, ...)`)。Ractor main thread の th->self は親で `rb_thread_alloc` され
  foreign。worker が作る Hash(worker objspace)が foreign th->self の ivar 経由でしか辿れず sweep。fiber-storage(直接
  C field)と違い foreign オブジェクトの ivar 経由なので、th->self の re-home(invasive)か locals の C-field 化(refactor)
  が要る → design。
- **id2ref**(#4, 12/12「Object ID seen, but not in _id2ref table」): 既知 §6.7 residual。id2ref st_table を最初に
  `_id2ref` を呼んだ objspace(worker かも)に lazy 構築する設計齟齬。VM ロック直列化 + keep-alive 済でも残る → design。
- **wait_receive**(#16, 1/12 mark-T_NONE): `ractor_wait_receive` がロック外で in-flight basket を C-stack-local queue に
  再配分、`ractor_sync_mark` が未マーク → 並行 global GC が cross-objspace payload を解放。§3.10 in-flight pin 族の residual
  (過去に entanglement)。

**確定タクソノミー(本作業の到達点)**: クラッシュ面は **(I) confinement-miss 族**(親 objspace 確保フィールド / VM-global
root を confined local GC が未マーク = G, G-2, trap, D, at_exit, thread_variable, id2ref)と **(II) cross-objspace
subtree liveness 族**(A, C, wait_receive, §3.10)に大別。(I) の直接 C field / 固定配列ケースは re-home / if-local-mark で
**local-sound に修正可能**(B/D/E/F/G/G-2/trap = 7件修正済)。残りは foreign-object-ivar・lock-free-list・lazy-VM-table・
in-flight-pin という、より深いライフタイム設計を要する。

### 6.13 batch 9(体系監査拡張 + 新規14領域)— 新機構 Family III(generational WB × cross-objspace)を発見
体系監査3軸(VM-global root / per-thread-fiber-ec field / foreign-object-ivar)+ 新規11領域。**8 crash / 6 clean**。
clean が安全境界を確証(Ractor.select+monitor in-flight pin、chilled/fstring dedup、WeakMap×finalizer×orphan、
sync-primitive で blocked のまま終了、introspection×並行 confined-local-GC、make_shareable/isolate proc env mixed
[91 runs 0、shareable env の唯一の非shareable 子=ME_CREF imemo は home objspace の local GC が辿る/global STW が
foreign-only ケースを担保])。クラッシュは既知族の変種 + **新機構 Family III**:

- **Family III(generational WB × cross-objspace; 新)**: confined **minor** local GC の remembered-set が、cross-objspace
  / copy 経路で生じた old→young edge をカバーしない。`generic_ivar_host_sendcopy`(**15/15 決定的**、単一 worker でも、
  非RLGC 0/4): `Ractor#send` COPY(`obj_traverse_replace_i` ractor.c:1812 + `rb_copy_generic_ivar` variable.c:2270)で
  生成した dest-objspace の generic-ivar-host 深グラフが、copy 中の minor GC で promote → `rgengc_rememberset_mark` が
  freed child(T_NONE)を walk。`shareable_env_svar`(11/15、非RLGC 0/12): svar($~/$_)値が `imemo_svar` 経由で同様。
  **default.c:5743-5749 が「cross-objspace old→young は意図的に remembered set 外」と明記**しており、本族はその設計前提が
  copy/svar 経路で破れるケース。**1行 WB 追加では直らず、世代別GC×cross-objspace の設計判断が要る**(Task #17/#18)。
- **Family I 追加(VM-global root; coverages)**: `vm->coverages`/`me2counter`(Coverage.start、main 固定)に worker が
  自 objspace の per-file coverage Array を `rb_hash_aset` → worker confined GC が未マーク → sweep(6/15、main-only 0/20)。
  trap と違い **Hash の値が各 worker objspace に散在**するため if-local-mark 不可 — symbol bucket 同様に値を shareable 化
  する等の所有設計が要る(Task #19、niche)。
- **既知再確認**: thread_variable(8/15, #15)、s7 Family-A(低頻度)、backtrace T_DATA passthrough(15/15, Family-A)。

**到達点の更新**: クラッシュ機構は **(I) confinement-miss**(direct C field/固定配列 = 修正済7件; foreign-object-ivar /
VM-global-Hash-散在値 = 設計)、**(II) cross-objspace subtree liveness**(A/C/§3.10 = 設計)、**(III) generational WB ×
cross-objspace**(copy/svar の remembered-set = 設計)の3族。**local-sound に直せる範囲(I の直接ケース)は出し切った**。
残る (I)-間接 / (II) / (III) は、cross-objspace のオブジェクト寿命・世代別 remembered-set・VM-global table 所有という
RLGC の中核設計判断に属する。
