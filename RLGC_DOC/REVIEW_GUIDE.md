# RLGC コードレビュー副読本 (REVIEW_GUIDE.md)

> **注意(2026-07-04)**: 本書は初期の RLGC 実装スナップショット(`de5545202` からの 43 コミット)を
> コードに即して解説した副読本で、**その時点の diff に固定**されている。以降 RLGCv2 は大きく進み、
> 一部の記述(特に cross-Ractor 列挙 `rb_objspace_each_objects_all`・shareable の mark-only 化・
> imemo の born-shareable 確定など)は**現行と異なる**。
> **最新の仕様は `design_v2.md` 冒頭「現在の到達点(最新仕様サマリ)」、進捗は `STATUS_v2.md` を正**とする。
> 本書は「初期実装をコード単位で追う」用途の歴史的資料として残す。

Ractor-Local GC (RLGC) の実装 diff を**コードに即して**読むための副読本。
`git diff de5545202 HEAD`(= master..ractor-local-gc)と**並べて**読むことを想定しています。
箇条書き中心の `RACTOR_LOCAL_GC_DESIGN.md`(設計の経緯)に対し、本書は**変更された実コードを引用し、
何を・なぜ・どう設計に合うか・レビュー時の注意点**を関心ごとに解説します。
現状の到達点・残課題のサマリは `STATUS_v2.md`(最新)/ `design_v2.md`「現在の到達点」を参照。

ベースコミット `de5545202`(master, RLGC 無し)から **43 コミット**(当時)。

## diff 一覧(コード、master..HEAD)

| ファイル | 規模 | 役割 | 本書の § |
|---------|------|------|---------|
| `gc/default/default.c` | ~1200 | RLGC の中核 GC エンジン | §1–4 |
| `gc.c` | ~400 | GC インターフェース層(roots/orphan/keep-alive/id2ref) | §5 |
| `ractor_sync.c` | 90 | メッセージ所有権(materialize-on-receive / in-flight pin) | §6 |
| `variable.c` | 81 | Face B(`rb_const_remove`)+ generic ivar | §7 |
| `ractor.c` | 46 | コピー走査 / foreign EC skip | §6 |
| `vm.c` | 45 | root-fiber / thread-roots マーク | §7 |
| `thread.c` | 23 | Face G/G-2(thread 起動時の re-home) | §7 |
| `symbol.c` | 23 | Face D(symbol set/ids アクセサ + bucket pin) | §7 |
| `ractor_core.h` | 15 | `rb_ractor_sync` の in_flight_materializing | §6 |
| `string.c` | 9 | Face D(fstring table アクセサ) | §7 |
| `iseq.c` | 6 | coverage iseq | §7 |
| `internal/symbol.h` | 2 | アクセサ宣言 | §7 |

計 16 ファイル、+1844 / −154。

## 設計モデル(レビュー前の前提)

- **Ractor ごとに独立した objspace(ヒープ)**。worker のオブジェクトは worker の objspace に住む。
- **ローカル minor GC**: **ロックフリー・VM バリアなし・confined**。マークするのは (a) 自 Ractor の ec/roots、
  (b) shared_bits remset 経由の shareable roots のみで、終わったら **return**。他 objspace のオブジェクトは
  **foreign-skip**(他 objspace のメモリを読まない)。VM-global root は**マークしない**(歴史的に「VM globals は
  main に住む」前提)。
- **グローバル/フル GC**: **STW**(`rb_gc_vm_barrier` で全 Ractor 停止)。全 objspace(orphan 含む)をマーク。
  並行ライタが居ないので**安全に再ルート可**(ガード: `rlgc_global_gc_active` / `rb_gc_during_local_gc_p`)。
- **不変条件**: ① shareable は home objspace で pin され、ローカル GC は**決して shareable を解放しない**
  (sweep guard);② shared_bits = 「shareable から参照される unshareable」の per-page remset、WB が立て
  `gc_mark_shared_roots` がローカル GC でマーク;③ **compaction は RLGC 下で無効**;④ 終了 Ractor は
  **orphan objspace** としてリストに残り、グローバル GC が走査。

## クラッシュ修正(Face)→ コミット対応表

confinement-miss 等の **7 面を修正済**(詳細は各 § と `RLGC_STATUS.md`)。レビュー時はまずこの 7 コミットを
個別に見ると差分が小さく追いやすい:

| Face | 修正概要 | commit | 本書 § |
|------|---------|--------|--------|
| E | `GC.auto_compact` を `!rlgc_has_local` でガード | `95c551e7b` | §4 |
| F | `define/undefine_finalizer` を key 所有者 objspace へルーティング | `72ad765aa` | §4 |
| D | VM-global concurrent_set の if-local keep-alive + symbol bucket pin | `f100f23ba` | §5, §7 |
| B | `rb_const_remove` の lookup+削除を VM ロックで atomic 化 | `808e41fd9` | §7 |
| G | thread 割り込み queue/mask-stack を子 objspace へ re-home | `f8885699f` | §7 |
| G-2 | fiber-storage Hash を re-home | `c0e1c99fe` | §7 |
| trap | signal-trap handler を `trap_list.cmd[]` if-local keep-alive | `51819fc7b` | §5, §7 |

元の RLGC 実装本体は `14047e008`「per-Ractor objspace + lock-free local GC」以降の一連のコミット。

## 推奨レビュー順

1. **§1**(objspace ライフサイクル・ロックフリー確保)で「per-Ractor objspace + span」のメンタルモデルを掴む
2. **§2**(confined mark / sweep guard)で「foreign-skip と shareable pin」= 安全性の要を見る
3. **§3**(shared_bits / WB / remset)で「cross-objspace 参照をどう生かすか」を見る
4. **§4**(global GC / compaction guard / finalizer)で STW 経路と Face E/F
5. **§5**(`gc.c` interface)で roots / orphan / keep-alive(Face D/trap)/ id2ref
6. **§6**(メッセージ所有権)で materialize-on-receive と in-flight pin
7. **§7**(satellite)で Face B/G/G-2/D の各サブシステム修正

---
## 1. Ractor ごとの objspace ライフサイクルとロックフリー割り当て

本セクションは `gc/default/default.c` を扱う。各 Ractor がどのように自身の objspace を持つか、その objspace がどのように per-objspace の mmap アリーナからロックフリーにヒープページを割り当てるか、VM グローバルなメモリ span がどのようにして任意のスレッドがロックなしでヒープポインタからその所有 objspace を解決できるようにするか、一度限りのプロセスグローバル初期化ガード、そして `gc_enter` がどのようにロック不要のローカルパスと STW のグローバルパスを選択するか、を扱う。このサブシステム全体は `RACTOR_LOCAL_GC` によってゲートされ、既定値は `1` である(default.c:268-270)。

### 1.1 2 つの新しい objspace の種別: `local`、および `local_gc` / `global_gc`

default.c:553-557(およびフラグのビットフィールド 570-580)
```c
#if RACTOR_LOCAL_GC
    /* true for a per-Ractor (non-main) objspace: collected locally without a STW barrier. */
    bool local;
#endif
```
```c
        unsigned int local_gc : 1;   /* set while THIS objspace is being collected in local mode */
        unsigned int global_gc : 1;  /* set while a GLOBAL all-Ractor STW GC is in progress */
```

**What(何を):** `objspace->local` は「この objspace は非メイン Ractor に属する」という*静的*な性質である。`flags.local_gc` / `flags.global_gc` は*一時的*なものであり、1 回の collection の期間中だけ設定される。**Why(なぜ):** これら 3 つの真偽値は、ファイルの残りの部分が分岐の基準とするマスタースイッチである(`objspace->local || rlgc_has_local`、`!rlgc_global_gc_active` など)。**How it fits(どう組み合わさるか):** `local` は collection が confined かつロックフリーで実行できるかを決定する。`global_gc` はそれを上書きし、ローカルな objspace 上であっても STW の統一パスを強制する。**Gotcha(注意点):** `objspace->local`(per-objspace)とファイルスタティックな `rlgc_has_local`(プロセス全体での「少なくとも 1 つのローカル objspace が存在する」)との非対称性に注意。レビュアーは各使用箇所を確認すべきである。メイン objspace は `local == false` だが、一度でもワーカーが存在すれば*同時に* RLGC を意識した振る舞いをしなければならない(ゆえに繰り返し現れる `objspace->local || rlgc_has_local`)。

### 1.2 Ractor の objspace が生まれる場所: `objspace_init` の分岐

`rb_gc_impl_objspace_alloc` 自体は変更されていない(default.c:10653、依然として単なる `calloc1(sizeof(rb_objspace_t))`)。per-Ractor のロジックはすべて `rb_gc_impl_objspace_init` にあり、これは objspace ごとに 1 回実行される(default.c:10665-10687)。
```c
    if (rlgc_main_objspace == NULL) {
        rlgc_main_objspace = objspace;            /* first objspace == the main Ractor's */
    }
    else {
        objspace->local = TRUE;
        objspace->flags.dont_incremental = TRUE;  /* local GC = single self-contained STW-of-one */
        if (!rlgc_has_local) {
            /* First worker: main GCs must also become atomic so the global barrier never
             * catches main mid-incremental-mark / lazy-sweep. */
            gc_rest(rlgc_main_objspace);
            rlgc_main_objspace->flags.dont_incremental = TRUE;
        }
        rlgc_has_local = true;
    }
```

**What(何を):** 初めて初期化された objspace は `rlgc_main_objspace` として記録され、以降のものはすべて `local` フラグが立てられる。**Why `dont_incremental`(なぜ `dont_incremental` か):** ローカル GC は、mutator や兄弟 Ractor の実行をまたいで GC 状態を*一切*生かしたまま残してはならない(バリアなしで実行されるため)。したがって即時(非インクリメンタル)の mark と即時 sweep に強制される。`dont_incremental` は `gc_start` を通じて即時 sweep を含意する。**Why finish main's in-flight GC(なぜメインの進行中の GC を完了させるか):** いったんグローバル GC が可能になると、その STW バリアはメイン objspace をインクリメンタル collection の途中で凍結してはならない(統一 mark/sweep は他者の部分的な状態を再開できない)。そのためメインも atomic に格下げされ、保留中のメインの collection は `gc_rest` でフラッシュされる。**Gotcha(注意点):** この遷移が安全なのは、ひとえに*明示された*前提「ここではメイン Ractor 上にいる(最初の非メイン Ractor は常にメインによって作成される)し、他の Ractor は走っていない」によってである。この VM 不変条件が将来変わる(ワーカーがまさに最初の兄弟を生成する)ようなことがあれば、外部 objspace に対するガードなしの `gc_rest(rlgc_main_objspace)` はデータ競合になる。レビュアーが指摘する価値がある。

### 1.3 VM グローバルなヒープ span: ロックフリーなポインタ → objspace 解決

default.c(diff 行 189-247)。ファイルスタティック群:
```c
static rb_objspace_t *rlgc_main_objspace = NULL;
static bool rlgc_has_local = false;
static bool rlgc_global_gc_active = false;
static size_t rlgc_global_lomem = 0;   /* grow-only VM-global heap span */
static size_t rlgc_global_himem = 0;
```
grow-only な更新処理と所属判定:
```c
static inline void
rlgc_span_extend(uintptr_t lo, uintptr_t hi)
{
    size_t cur;
    while ((cur = rlgc_span_load(&rlgc_global_lomem)) == 0 || lo < cur) {
        if (RUBY_ATOMIC_SIZE_CAS(rlgc_global_lomem, cur, (size_t)lo) == cur) break;
    }
    while ((cur = rlgc_span_load(&rlgc_global_himem)) < hi) {
        if (RUBY_ATOMIC_SIZE_CAS(rlgc_global_himem, cur, (size_t)hi) == cur) break;
    }
}
```
```c
static inline bool
rlgc_obj_in_any_heap(VALUE obj)
{
    const uintptr_t p = (uintptr_t)obj;
    if (p % sizeof(VALUE) != 0) return false;
    const uintptr_t body = (uintptr_t)GET_PAGE_BODY(p);
    if (body < rlgc_span_load(&rlgc_global_lomem) || p >= rlgc_span_load(&rlgc_global_himem)) return false;
    struct heap_page *const page = GET_HEAP_PAGE(p);
    return page != NULL && (uintptr_t)page->body == body; /* page back-pointer round-trips */
}
```

**What(何を):** `[lomem, himem)` は*すべての* objspace のページボディに対する単一の合併バウンディングボックスである。任意のスレッドはポインタをこれに対して範囲判定し、その後アラインされたページボディ(`GET_PAGE_BODY`)へマスクダウンして `page->objspace`(新しいバックポインタ、§1.4)を読める。**Why(なぜ):** 代替案 — per-objspace のソート済みページ配列(`is_pointer_to_heap`)— は*1 つの* objspace のページしか知らず、その objspace のロックを必要とする。span は 2 つの relaxed なアトミックロードで*すべて*を知ることができ、これが objspace をまたいだ参照認識(例: default.c diff 行 ~1670 の `check_rvalue_consistency_force`)をロックフリーにしている。**How it's kept correct under concurrency(並行下でどう正しさを保つか):** 生産者は `rlgc_span_extend`(アリーナ拡張ごとに 1 回、§1.5、および `heap_page_allocate` ごとに 1 回、default.c:2441 付近)であり、CAS ループを使うため、アリーナを拡張する並行 Ractor が更新を取りこぼすことはない。span は grow-only(`lomem` は縮むだけ、`himem` は伸びるだけ)であるため、古い relaxed な読み取りは*追加されたばかりのページを含み損ねることはあっても、既存のページを除外することは決してない*。そして span が実際に marking をゲートする STW グローバル GC の間は、span は安定している。**Gotcha(注意点):** `rlgc_obj_in_any_heap` は*本物の*オブジェクトポインタに対してのみ安全であると文書化されている。これはページボディ(`page->body`)をデリファレンスするためである。これは保守的スキャナでは*ない*。任意のワードに対してはコードは `rb_gc_conservative_owner`(diff 冒頭で宣言、gc.c で実装)を使う。また `lomem` がページの `start` ではなくページの*ボディ*基底を使うことに注意。マスクダウンされたポインタは正当に `start` より下に位置しうるためである(`heap_page_allocate` 内の `rlgc_span_extend` 呼び出し箇所のコメント)。レビュアーは、span がページアラインメントより細かい精度を期待して*読まれる*ことが決してないことを確認すべきである。

### 1.4 ページ → objspace バックポインタとページごとの共有 remset

default.c(diff 行 ~888-910):
```c
#if RACTOR_LOCAL_GC
    /* Owning objspace. ... lets a local GC tell its own objects from objects living in
     * another Ractor's (or the main) objspace. */
    rb_objspace_t *objspace;
#endif
    ...
    bits_t shared_bits[HEAP_PAGE_BITMAP_LIMIT];   /* boundary remset */
```
そしてページフラグのビットフィールドから完全な `unsigned char` への拡幅(diff ~875-887):
```c
    unsigned char has_remembered_objects;
    unsigned char has_uncollectible_wb_unprotected_objects;
    unsigned char has_shared_objects;  /* RLGC only */
```

**What(何を):** すべてのページが `objspace`(`heap_page_allocate`、default.c:2455 付近で設定: `page->objspace = objspace;`)に加えて、`shared_bits` 境界 remset と `has_shared_objects` サマリフラグを得る。**Why the bitfield→byte change(なぜビットフィールド→バイトへ変更するか):** これらのフラグは今や任意の Ractor スレッドから*ロックフリーな write barrier* によって書かれる。ビットフィールド `flags.has_x = TRUE` はワード全体の read-modify-write にコンパイルされるため、2 つの Ractor が兄弟フラグを並行して設定すると一方の更新が失われる。各フラグを独自のバイトに昇格させることで、ストアは分離によりアトミックになる。同じ理屈が `shared_bits`/`remembered_bits` に対する `MARK_IN_BITMAP_ATOMIC` / `gc_bitmap_atomic_set`(diff ~1010-1040)を駆動している。これらは 1 つの `bits_t` ワードを多数のスロットで共有するため、本物の CAS を必要とする。**How it fits §1(§1 にどう組み合わさるか):** `page->objspace` は span ルックアップ(§1.3)が返すペイロードであり、confined なローカル GC が所有しないオブジェクトを「foreign-skip」する仕組みである。**Gotcha(注意点):** これはまさに MEMORY ノートにある TSan 確認済みのビットマップ RMW バグの領域である。レビュアーは、複数 Ractor から書かれる*すべての*ページビットマップ/フラグが、素の `|=` やビットフィールド代入ではなくアトミックパスを通ることを確認すべきである。

### 1.5 per-objspace アリーナアロケータ(並列性のアンロック)

default.c(フィールドは diff 行 ~602-614、アロケータは ~2120-2200)。objspace は以下を得る:
```c
struct rlgc_page_arena *arenas;        /* mmap'd arenas, munmap at objspace free */
char *arena_cursor; char *arena_end;   /* bump pointer */
struct heap_page_body *arena_freelist; /* recycled bodies (link stored in the body) */
```
ボディ ~256 個ごとに 1 つの大きなアリーナを予約する:
```c
#define RLGC_PAGE_ARENA_BODIES 256
#define RLGC_ARENA_ALIGN (2u * 1024 * 1024)
...
    char *const ptr = mmap(NULL, mmap_size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    ...
    char *aligned = ptr + RLGC_ARENA_ALIGN;
    aligned -= ((uintptr_t)aligned & (RLGC_ARENA_ALIGN - 1));
#ifdef MADV_HUGEPAGE
    madvise(aligned, arena_size, MADV_HUGEPAGE);
#endif
    ...
    rlgc_span_extend((uintptr_t)aligned, (uintptr_t)aligned + arena_size);
```
ボディの切り出し(`heap_page_body_allocate` 内、今や `objspace` を取る、diff ~2311-2340):
```c
    if (objspace->heap_pages.arena_freelist != NULL) {
        page_body = objspace->heap_pages.arena_freelist;
        objspace->heap_pages.arena_freelist = *(struct heap_page_body **)page_body;
    }
    else {
        if (objspace->heap_pages.arena_cursor + HEAP_PAGE_SIZE > objspace->heap_pages.arena_end) {
            if (!rlgc_page_arena_grow(objspace)) return NULL;
        }
        page_body = (struct heap_page_body *)objspace->heap_pages.arena_cursor;
        objspace->heap_pages.arena_cursor += HEAP_PAGE_SIZE;
    }
```
解放は `munmap` ではなくリサイクルする(`heap_page_body_free`、今や `objspace` を取る、diff ~2188-2200):
```c
    asan_unpoison_memory_region(page_body, sizeof(struct heap_page_body *), false);
    *(struct heap_page_body **)page_body = objspace->heap_pages.arena_freelist;
    objspace->heap_pages.arena_freelist = page_body;
```

**What(何を):** 64 KiB ページごとに 1 回の `mmap` + 2 回の `munmap` を行う代わりに、各 objspace は ~16 MiB のアリーナを予約し、自身のプライベートな状態の中だけでボディを bump アロケート/リサイクルする。**Why(なぜ):** 文書化された根本原因 — 64 KiB アラインメントのための per-page の `mmap`/`munmap` がカーネルのプロセス全体の `mmap_lock` 上で全 Ractor を直列化していたこと、そして匿名メモリのファーストタッチのフォールト率(帯域ではなく)が並列性の天井であったこと。2 MiB アラインで `MADV_HUGEPAGE` なアリーナは 2 MiB あたり 1 フォールトでファーストタッチする(512 倍少ない)。そしてアラインメントの余剰は意図的に `munmap` *しない*(各 `munmap` は書き込みのために `mmap_lock` を再取得し、加えて TLB シュートダウンを引き起こすため)。**How it fits(どう組み合わさるか):** アリーナは per-objspace なので、ページ取得のファストパスはロックを必要としない — これはロックフリー割り当て(§1.7)の前提条件である。各拡張は VM グローバル span(§1.3)を伸ばすので、新しいボディは解決可能になる。**Gotchas(注意点):** (1) freelist のリンクは解放されたボディの*内部*に置かれ、これは sweep 後に ASAN poison されている可能性がある。リンクを書き込む前の明示的な `asan_unpoison_memory_region` に注意。これを省くと ASAN の偽陽性クラッシュになる。(2) `heap_page_body_allocate` と `heap_page_body_free` の両方が、今や正しい所有 `objspace` を必要とする。誤ったものを渡すと Ractor 間で freelist をクロスリンクし、2 つのヒープを破壊する。すべての呼び出し箇所が更新された(`heap_page_free`、`heap_page_allocate`)。レビュアーは残存する引数なし呼び出し元がないか grep すべきである。(3) ワーカーのページの物理メモリは、objspace 全体が解放されたときにのみ OS に返却される(`rlgc_page_arenas_free`、§1.6)— 激しく使われてからアイドルになった Ractor は、終了するまでアリーナを保持する。

### 1.6 objspace のティアダウンと orphan の許容

`rb_gc_impl_objspace_free`(diff ~10478-10500):
```c
    if (objspace == rlgc_main_objspace && getenv("RLGC_STATS")) { fprintf(...); }
    ...
#if RACTOR_LOCAL_GC && defined(HAVE_MMAP)
    if (HEAP_PAGE_ALLOC_USE_MMAP) rlgc_page_arenas_free(objspace); /* munmap the page arenas */
#endif
```
`rlgc_page_arenas_free`(diff ~363-374)はアリーナリストを走査し、各 `mmap_base` を `munmap` し、カーソルを null にする。`heap_pages_free_unused_pages` の orphan 許容修正(diff ~2257-2278):
```c
    /* An objspace can legitimately have ZERO pages here under Ractor-local GC: an orphaned
     * (terminated-Ractor) objspace whose last live object has been reclaimed ... rb_darray_get(
     * sorted, -1) would then read out of bounds ... Only recompute bounds when pages remain. */
    if (rb_darray_size(objspace->heap_pages.sorted) > 0) {
        ... heap_pages_himem = ...; heap_pages_lomem = ...;
    }
```

**What(何を):** objspace の解放は今やアリーナを解放し、未使用ページの回収処理はもはや 1 ページ以上を仮定しない。**Why(なぜ):** 終了した Ractor は、グローバル GC が依然として走査するリスト上に*孤立した(orphaned)* objspace を残す。グローバル GC はその最後の生きた shareable を回収しうるため、空の `sorted` 配列が残る。RLGC 以前のコードは無条件に `rb_darray_get(sorted, size-1)` を行っていた — `rb_darray_get(sorted, -1)` は範囲外を読み、NULL ページをデリファレンスする。**How it fits(どう組み合わさるか):** これは MEMORY ノートを支配する孤立 objspace の話の、割り当て層側の半分である(mark 側の半分は gc.c の orphan リスト走査)。**Gotcha(注意点):** コメントは*空の orphan の殻を解放すること*をフォローアップ(RACTOR_LOCAL_GC_DESIGN.md 5.4)へ明示的に先送りしている — そのため、アイドルなプロセスは空の orphan objspace 構造体を蓄積する。未解決の「deep-graph mark-T_NONE」クラッシュを追っているレビュアーは、これがまさに orphan × 回収済みページの相互作用領域であることに留意すべきである。

### 1.7 `newobj_cache_miss` におけるロックフリー割り当てパスの選択

default.c:2914(diff ~2892-2917):
```c
    if (!vm_locked && !(objspace->local && rlgc_lockfree_alloc_enabled())) {
        lev = RB_GC_CR_LOCK();
        unlock_vm = true;
    }
```
`rlgc_lockfree_alloc_enabled()`(diff ~265-285)は `RUBY_RACTOR_LOCAL_GC_LOCKFREE`(既定 ON、`"0"` のときのみ無効)である。

**What(何を):** ロックフリー割り当てが有効なローカル objspace では、キャッシュミス時のページ取得は VM ロックを**まったく**取らない。**Why(なぜ):** *すべての* newobj キャッシュミスで取られる単一の `vm->ractor.sync.lock` が、支配的なスケーリングのボトルネックだった — それが全 Ractor の割り当てを直列化していた。ページ取得は今やこの Ractor のプライベートなヒープ/freelist(§1.5)にしか触れないため、並列化する。**How it fits the design(設計にどう組み合わさるか):** 2 番目のコメントブロック(最初のものを取って代わる「完全にロックフリー」なもの)が、正しさを支える要のステートメントである — リフィルによって引き起こされる*ローカル GC* でさえ VM ロックなしで走る。これが健全であるのは、ひとえにそのような GC が触れるすべての VM グローバル構造(`generic_fields_tbl`、`id2ref`、finalizer/symbol テーブル、Ractor ポート)が、その mutator と共有される*非バリア*ロックによって独立に Ractor-GC-safe にされているからである。**Gotchas(注意点):** (1) 2 つのコメントブロックが存在する — 最初のものは初期の「GC は依然としてバリアを意識したロックを取る」設計を記述しており、今や古く誤解を招く。実際のコードは*2 番目*のブロック(ローカル GC を含め完全にロックフリー)に一致する。レビュアーは最初のブロックを歴史的なものとして扱い、削除を検討すべきである。(2) メイン objspace(`local == false`)は常にロックする — 多数の Ractor がそこに割り当てるので、これは正しい。(3) `newobj_slowpath`(diff ~2963-2975)は意図的にロックフリーに*されていない* — `lev` は今や `0` に初期化され、常に `RB_GC_CR_LOCK()` を取る。`during_gc`/stress のスローパスはまれであり、排他アクセスを必要とするためである。その objspace で `during_gc` が設定されている間にロックフリーのファスト割り当てに到達するパスがないことを確認すること。

### 1.8 Ractor newobj-cache フラッシュのルーティング(所有権の正しさ)

`gc_ractor_newobj_cache_clear` は今や `rb_gc_get_objspace()` ではなく `data` 経由でターゲット objspace を取る(diff ~4323-4340):
```c
static void
gc_ractor_newobj_cache_clear(void *c, void *data)
{
    rb_objspace_t *objspace = (rb_objspace_t *)data;   /* was: rb_gc_get_objspace() */
    ...
```
そして `gc_sweep_start` がどのキャッシュをフラッシュするかをルーティングする(default.c:4385-4400):
```c
    if (rlgc_global_gc_active) {
        rb_gc_ractor_newobj_cache_foreach_for_objspace(objspace, gc_ractor_newobj_cache_clear, objspace);
    }
    else if (objspace->local) {
        rb_gc_ractor_newobj_current_cache_foreach(gc_ractor_newobj_cache_clear, objspace);
    }
    else {
        rb_gc_ractor_newobj_cache_foreach(gc_ractor_newobj_cache_clear, objspace);
    }
```

**What(何を):** キャッシュは常に*それが割り当てる先の objspace* へフラッシュされる。グローバル GC は現在 sweep 中の objspace に属するキャッシュのみをフラッシュする。ローカル GC は自身の Ractor の現在のキャッシュのみをフラッシュする。レガシーな単一 objspace パスはすべてをその 1 つの objspace へフラッシュする。**Why(なぜ):** newobj キャッシュの freelist は*それ自身の* objspace に存在するスロットを保持している。それを外部のヒープに追加すると両方を破壊する。古い `gc_ractor_newobj_cache_clear` は `rb_gc_get_objspace()` をハードコードしていたが、これはキャッシュと objspace が 1:N になった途端に誤りである。**How it fits(どう組み合わさるか):** アリーナ freelist(§1.5)と同じ所有権の規律を反映している — スロットは決して objspace の境界を越えない。**Gotcha(注意点):** この修正は 4 つの呼び出し箇所に触れる — `gc_sweep_start`、`rb_gc_impl_ractor_cache_free`(diff ~1426: 今や `NULL` ではなく `objspace` を渡す)、そして `rb_gc_impl_after_fork`(diff ~10580-10595、これは `rlgc_has_local` の下では全キャッシュをメインに投棄するのではなく `rb_gc_foreach_objspace` を通じて*すべての* objspace を反復する)。レビュアーは、`data` として `NULL` を渡す呼び出し元が残っていないことを確認すべきである。今やそれは現在の objspace を黙って使うのではなく NULL をデリファレンスするからである。

### 1.9 `gc_enter` / `gc_exit`: ローカル(ロック不要)対 グローバル(STW)の選択

`gc_enter`(default.c:7700-7740、diff ~7697-7745):
```c
    if (objspace->local && !objspace->flags.global_gc) {
        /* Ractor-local MINOR GC: ... Do NOT take the VM lock and do NOT stop other Ractors. */
        *lock_lev = 0;
        objspace->flags.local_gc = TRUE;
        ... rlgc_concurrent_local_gc++ / max tracking ...
    }
    else {
        *lock_lev = RB_GC_VM_LOCK();
        switch (event) { case ...start/rest/continue: rb_gc_vm_barrier(); ... }
        /* GLOBAL or main GC: UNCONFINED unified mark across all (barrier-stopped) objspaces. */
    }
```
`gc_exit` はそれを鏡映する(default.c:7755-7773): ローカルブランチは `local_gc` をクリアして並行カウンタをデクリメントするだけであり、グローバルブランチは両方のフラグをクリアして `RB_GC_VM_UNLOCK(*lock_lev)` を呼ぶ。

**What(何を):** collection を次の 2 つに分ける単一の決定点である: (a) confined なローカル minor GC — `RB_GC_VM_LOCK` なし、`rb_gc_vm_barrier` なし、`lock_lev = 0`、そして (b) それ以外すべて — グローバル/フル GC および任意のメイン objspace GC のための完全な VM ロック + バリア(全 Ractor 停止)。**Why(なぜ):** ローカルパスこそが N 個の Ractor が自身のヒープを同時に mark + sweep できるようにするものである。`rlgc_concurrent_local_gc` / `rlgc_max_concurrent_local_gc` カウンタ(`RLGC_STATS` 経由でシャットダウン時に出力される)は、まさにオーバーラップを*証明する*ために存在する(max > 1 は実時間での真の並行性を意味する)。**How it fits(どう組み合わさるか):** `global_gc` は `gc_enter` の*前に* `gc_start`(diff ~7384-7407)で予測される。バリアの判断は前もって分かっていなければならないからである — フル/メジャー collection(`will_full_mark`)はグローバル STW GC へ昇格され、minor はローカルのままになる。`gc_start` はその後 `gc_global_sweep` と `gc_sweep` を使い分け、統一 mark の周囲で `rlgc_global_gc_active` をトグルする。**Gotchas(注意点):** (1) ローカルパスでの `lock_lev = 0` は、`gc_exit` が `RB_GC_VM_UNLOCK(0)` を呼んではならないことを意味する — ブランチの対称性が保たれていることを確認すること(保たれている: ローカル exit はアンロックをスキップする)。(2) ローカルパスの `local_gc`/`global_gc` フラグのハンドシェイクは例外安全でなければならない — もしローカル GC が `gc_enter` と `gc_exit` の間で longjmp で抜け出せるなら、フラグと並行カウンタがリークする。レビュアーは collection 本体が非局所的に脱出できないことを確認すべきである。(3)「メイン objspace の GC は unconfined で走る」という規則は、§1.2 がメインを `dont_incremental` に強制していることに依存している。もしメインが再びインクリメンタルに走るようなことがあれば、グローバルバリアがそれを mark の途中で捕まえうる。

### 1.10 一度限りのプロセスグローバル初期化ガード

`rb_gc_impl_objspace_init`、per-Ractor のブランチの後(diff ~10713-10735):
```c
    {
        static bool process_globals_initialized = false;
        if (!process_globals_initialized) {
            init_size_to_heap_idx();
#if defined(INIT_HEAP_PAGE_ALLOC_USE_MMAP)
            heap_page_alloc_use_mmap = INIT_HEAP_PAGE_ALLOC_USE_MMAP;
#endif
            process_globals_initialized = true;
        }
    }
```
そして `gc_params.heap_init_bytes = GC_HEAP_INIT_BYTES;` はこの関数から完全に*削除*された。

**What(何を):** objspace に依存しないプロセスグローバルな初期化処理(`init_size_to_heap_idx`、ランタイムの `heap_page_alloc_use_mmap` プローブ)は、今や objspace の初期化のたびにではなく正確に 1 回だけ走る。**Why(なぜ):** `objspace_init` は Ractor ごとに走るが、これらは他の Ractor が既にロックフリーに読んでいる*プロセスグローバル*を書く。子 Ractor の init ごとにそれらを書き直すと、それらの読み手と競合し、`heap_init_bytes` の再設定は `RUBY_GC_HEAP_INIT_BYTES` でチューニングされた値を上書きしてしまう。最初の呼び出しはブート時のメイン objspace(他の Ractor は走っていない)であり、後の呼び出しは VM ロックを保持しているため、素の `static bool` ガードはクリーンな happens-before で公開される。`heap_init_bytes` がここで削除されたのは、その静的初期化子 + `rb_gc_impl_set_params` が既にそれを設定しているからである。**How it fits(どう組み合わさるか):** §1.7/§1.3 を補完する — ワーカーがロックフリーに読むものは、並行して再初期化されてはならない。**Gotcha(注意点):** `static bool` は同期されていない。その安全性はひとえに「最初の呼び出しはブート時にシングルスレッドである」という明示された前提に依存している。もしワーカー Ractor が `objspace_init` を*最初に*呼ぶことがありうるなら(§1.2 と同じ脆弱性)、ガードは競合する。レビュアーは §1.2 と §1.10 が 1 つの要となる前提条件を共有しているものとして扱うべきである: メイン Ractor の objspace は常に、単独で、最初に初期化される。

---

## 2. 限定的なローカル mark & sweep のガード（`gc/default/default.c`）

これらは、限定的なローカル GC を*安全*にするための要となるガードである。すなわち、どうマークするか（foreign なオブジェクトをスキップし、それらへの参照を生きた葉として扱う）、shareable をどう変更せずにエイジング/ピンするか、どう sweep するか（「ローカル GC は shareable を絶対に解放してはならない」という絶対のルール）、そして STW なグローバル GC がそれらのガードをどう解除して本当に死んだ shareable を回収するか、である。本節は Section 1（フラグ/ビットマップ/RLGC の足場）と併せて読むこと。`objspace->flags.local_gc`、`rlgc_global_gc_active`、`rlgc_has_local`、`shared_bits`/`GET_HEAP_SHARED_BITS`、`GET_HEAP_OBJSPACE` はいずれもそこで導入されている。

### 2.1 `gc_mark`: foreign-skip（confinement）

`gc/default/default.c:5157`（関数は `:5152`）

```c
#if RACTOR_LOCAL_GC
    /* Confined local GC: skip objects owned by another objspace ... */
    if (objspace->flags.local_gc && GET_HEAP_OBJSPACE(obj) != objspace) {
        return;
    }
#endif

    rgengc_check_relation(objspace, obj);
#if RACTOR_LOCAL_GC
    gc_shared_relation(objspace, obj);
#endif
    if (!gc_mark_set(objspace, obj)) return; /* already marked */
```

**何を:** Ractor ごとのローカル GC（`flags.local_gc`）の間、到達したオブジェクトが*別の* objspace に属する（`page->objspace != objspace`）場合、`gc_mark` は即座に return する。マークもせず、mark ビットも立てず、グレーにもしない（つまりその子は決して辿られない）。この参照は実質的に生きた葉となる。

**なぜ:** これが「CONFINED（限定的）」マーキングの核心である。ローカル GC は VM バリアなしでロックフリーに走るため、他の Ractor（`obj` の所有者を含む）が並行して自分のヒープを変更している。foreign なオブジェクトの mark ビット / flags / 子を読み書きすれば、それらのミューテータと競合する。foreign なオブジェクトは*自分自身の* objspace のルートによって生かされており、この GC がその生死を決める筋合いはない。チェックは `GET_HEAP_OBJSPACE`（Section 1 の `page->objspace` 逆ポインタ）によるアラインメント経由なので O(1) であり、`obj` の中身を決して参照しない。

**どう噛み合うか:** これこそが、minor GC が「自分の ec/roots + shared_bits roots だけをマークして RETURN する」ことを可能にしている。本当に objspace をまたぐがそれでもマークが必要なオブジェクトの例外的な経路は*グローバル* GC であり、そこでは `flags.local_gc` が false なのでこの分岐はスキップされ、統合された mark がすべてを辿る。

**レビュアーへの注意点:**
- このスキップは `objspace->local` ではなく `flags.local_gc` でゲートされている。*グローバル* GC 中、ドライバの objspace は `local` だが `local_gc` は **false** である（Section 1 の `gc_enter` を参照）。そのためグローバル mark は正しく foreign-skip を*行わない*。これは意図的かつ本質的であり、さもなければ統合 mark は最初の objspace 越えのエッジで止まってしまう。
- `GET_HEAP_OBJSPACE(obj)` は本物のヒープオブジェクトに対してのみ有効である。`gc_mark` は検証済みの参照に対してのみ到達するので、ここでは問題ない。ただし `rb_gc_impl_mark_maybe`（保守的スキャン）との対比に注意すること。あちらは代わりに安全な `rb_gc_conservative_owner` / `rlgc_obj_in_any_heap` を使わねばならない。

### 2.2 `gc_shared_relation`: （グローバル）mark 中に `shared_bits` の真実を再構築する

`gc/default/default.c:5038`、`gc_mark` の `:5169` から呼ばれる

```c
static inline void
gc_shared_relation(rb_objspace_t *objspace, VALUE obj)
{
    VALUE parent = objspace->rgengc.parent_object;
    if (!SPECIAL_CONST_P(parent) &&
        RB_OBJ_SHAREABLE_P(parent) &&
        !RB_OBJ_SHAREABLE_P(obj)) {
#if RACTOR_LOCAL_GC_AUDIT
        if (!MARKED_IN_BITMAP(GET_HEAP_SHARED_BITS(obj), obj)) {
            gc_shared_wb_miss(objspace, parent, obj);
        }
#endif
        MARK_IN_BITMAP_ATOMIC(GET_HEAP_SHARED_BITS(obj), obj);
        GET_HEAP_PAGE(obj)->flags.has_shared_objects = TRUE;
    }
}
```

**何を:** マークされる*すべての*エッジで呼ばれる（`parent` = `rgengc.parent_object`、`obj` = 子）。**shareable な親**が**unshareable な子**を直接参照しているとき、その子は shareable→unshareable の*境界*オブジェクトである。`gc_shared_relation` はそれを `shared_bits` に記録し、ページに `has_shared_objects` フラグを立てる。

**なぜ:** `shared_bits` は、shareable が参照しているがゆえにのみ生かされている unshareable なオブジェクトの remset である。コレクションとコレクションの間は、*write barrier*（`rb_gc_impl_writebarrier`、Section 3）がこれを維持する。しかし WB には漏れがありうるし、この集合は権威ある（authoritative）ものでなければならない。そこで、**フル mark は走査しながら `shared_bits` をゼロから再構築する** — mark 自体が真実なのである。`shared_bits` は `gc_marks_start` でクリアされ（すべての shareable な親が見えているときのみ — 単一 objspace か、グローバル STW GC の場合。2.6 を参照）、`gc_shared_relation` がそれを再投入する。

**どう噛み合うか:** これは `gc_mark_shared_roots`（Section 1 / 2.6）とループを閉じる。*次の* minor GC は、この mark が書いた `shared_bits` を読み、shareable な親が見えない別の objspace に住んでいる境界オブジェクトをルート化する。

**レビュアーへの注意点:**
- この set が `MARK_IN_BITMAP_ATOMIC` なのは、`shared_bits` がロックフリーな WB と重なり合うローカル GC とによって並行して書かれるからである。非アトミックな `|=` は同じワード内の兄弟オブジェクトのビットを失わせる（これは ThreadSanitizer で確認されたビットマップ RMW 系のバグである）。`MARK_IN_BITMAP` に「最適化」して戻してはならない。
- `RACTOR_LOCAL_GC_AUDIT`（デフォルトでは off）はこれを **WB 完全性チェッカ**に変える。mark が、WB が*まだ*記録していなかった境界エッジを見つけた場合、`gc_shared_wb_miss`（`:5021`）がそれを報告する。これが WB-miss バグ（Family I/III）を追う方法である。
- これは `rgengc.parent_object` をキーにしており、これは mark の経路に沿って正しく設定されていなければならない。`gc_mark_set_parent_invalid`/`_raw` がルートパスを括っている。

### 2.3 `gc_aging`: shareable はピンされ、その場でエイジングされることはない

`gc/default/default.c:5076`

```c
#if RACTOR_LOCAL_GC
    /* A shareable object is concurrently read by other Ractors' mutators ...
       A lock-free per-Ractor LOCAL GC must NOT read-modify-write its flags word ... */
    if (objspace->flags.local_gc && RB_OBJ_SHAREABLE_P(obj)) {
        objspace->marked_slots++;
        return;
    }
#endif
```

**何を:** ローカル GC において、マークが shareable なオブジェクトに到達したとき、`gc_aging` は `marked_slots` をインクリメントし（生きている*のは確か*なので会計を一貫させる）、オブジェクトの age/flags に触れる*前に* return する。

**なぜ:** エイジングは `RVALUE_AGE_INC` / `RVALUE_OLD_UNCOLLECTIBLE_SET` / `FL_PROMOTED` を行う、すなわち**オブジェクトの flags ワードの read-modify-write** である。shareable の flags は他の Ractor によって並行して読まれており（例 `vm_ic_hit_p`）、その世代状態は STW なグローバル GC に属する。ここでロックフリーに RMW すれば flags ワードを破壊（tear）してしまう。よって shareable の世代状態はグローバル GC が排他的に所有する。

**どう噛み合うか:** 「ローカル GC 中、shareable はそのホーム objspace でピンされる」という不変条件全体と整合している — 生きているとマークされるが、それ以外は手をつけられない。早めの `marked_slots++` は関数の通常の末尾（`:5132`）を反映しており、objspace ごとのスロット会計がずれないようにしている。

**レビュアーへの注意点:** ここでもまた `local` ではなく `flags.local_gc` でゲートされている — グローバル GC のもとでは shareable は通常通りエイジング*される*（STW なグローバル GC はそれを行ってよい唯一の場所である）。これは 2.4 の *sweep 時*の shareable ピンに対する mark 時のカウンターパートである点に注意。両方が必要である。

### 2.4 重要な sweep ガード: ローカル GC は shareable を絶対に解放してはならない

`gc/default/default.c:4057`（`gc_sweep_plane` 内、関数は `:4023`）

```c
#if RACTOR_LOCAL_GC
    if ((objspace->local || rlgc_has_local) && RB_OBJ_SHAREABLE_P(vp) && !rlgc_global_gc_active) {
        /* A NON-global GC cannot tell whether a shareable object is still referenced
           from another objspace ... so it must never free shareables — they stay
           pinned until a GLOBAL GC. ... */
        break;
    }
    if (rlgc_has_local && !rlgc_global_gc_active && RB_OBJ_SHAREABLE_P(vp) &&
        BUILTIN_TYPE(vp) == T_IMEMO &&
        (imemo_type(vp) == imemo_callcache || imemo_type(vp) == imemo_callinfo ||
         imemo_type(vp) == imemo_ment)) {
        /* cc / ci / cme imemo: shared VM infra reached cross-Ractor via WEAK inline
           caches a confined GC cannot trace ... so keep them pinned too ...
           but the GLOBAL GC LIFTS the guard. */
        break;
    }
#endif
```

（`break` はスロットごとの `switch` を抜けて次のスロットへ進む — つまり free の経路には*フォールスルーしない*。）

**何を:** グローバルでない sweep のいずれにおいても、マークされていない shareable なオブジェクトは**スキップされ、解放されない**。2 つのケースがある: (a) すべての shareable、(b) shareable であり弱い（weak）インラインキャッシュ経由で到達される 3 つの VM インフラ imemo 型（callcache / callinfo / method-entry）に対する念のための保険（belt-and-suspenders）。

**なぜ:** これは RLGC 不変条件 #3 を実装に落とし込んだものである。限定的な GC には shareable が死んでいるかどうかを知る術がない。それはクラスの cc-table、shape のエッジテーブル、インラインキャッシュ、Ractor オブジェクト、あるいは別の Ractor から参照されているかもしれず、そのいずれもローカル mark は辿っていない。これを解放すれば、それらの objspace 越えの参照*と*、（`shared_bits` が生かしていた）自身の unshareable な子がダングリングする。よって shareable は objspace の生存期間中ピンされ、グローバル GC だけがそれらを回収する。

**広げられた条件 `(objspace->local || rlgc_has_local)` が、微妙だが重要な部分である。** shareable をピンするのが*ワーカー*（`local`）の objspace だけでは不十分である。**main** の objspace は、ワーカーが 1 つでも存在すれば（`rlgc_has_local`）グローバルで*ない*通常の minor/compaction GC を走らせる。main 内の shareable が、main 自身のルートが到達しないワーカー（Ractor 本体の隔離された env、送られた shareable グラフ）経由で*のみ*生きていることがありうる。もし main の minor GC がそれを解放すれば、それはワーカーの UAF / objspace 越えの mark-T_NONE として表面化する。よってこのピンは main の objspace のグローバルでない GC にも適用されなければならない — ゆえに `rlgc_has_local` である。

**`!rlgc_global_gc_active` がグローバル GC に対してこのガードを解除する。** STW な統合 mark は真の objspace 越え到達可能性を*確かに*確立するので、そこではマークされていない shareable は本当に死んでおり、いまや死んだサブツリーとともに**回収されなければならない**。決定的に重要なのは、cc/ci/cme imemo のピンも*同様に*グローバルでは解除され、そう**しなければならない**点である。クラスは shareable であり、死んだクラスはグローバル GC が回収する。グローバル GC を通してピンされた cc/cme は、その解放されたクラスへの強い owner/def 参照を保持したまま生き残ってしまう → ダングリング（これが cc_tbl UAF ファミリである）。

**どう噛み合うか:** `gc_aging` の mark 時の shareable スキップ（2.3）と対になる。shareable は、グローバルでないコレクションのいずれにおいても、mark 時には生かされ手をつけられず、sweep 時には決して解放されない。

**レビュアーへの注意点:**
- ガード全体が `!rlgc_global_gc_active` である。もしグローバル GC の入口を変更して `gc_global_sweep_one` の間にこのフラグが立たないようにしてしまうと、VM 全体で死んだ shareable がすべて静かにリークする。このフラグは `gc_start` の mark+sweep の周囲で立てられ、その後クリアされる（Section 1）。
- 最初の節がすでに*すべての* shareable にマッチするので、2 番目の cc/ci/cme の節は**最初の節が発火しないときにのみ到達可能**である — つまり `objspace->local` が false *かつ* `rlgc_has_local` が false のときであり、RLGC のデフォルトのもとでは shareable に対してこれは起こりえない…実際には防御的/監査的な冗長性である。レビュアーへのメモとして書く価値がある: これが論理の穴を覆い隠すデッドコードではなく、念のための保険として意図されたものであることを確認すること。区別された、より具体的なコメント（弱い IC、objspace 越えの remember ビット競合）が、*なぜ*これら 3 つの型が危険なのかを記録している。
- この条件は `vp` の型/`imemo_type` を読む — sweep のこの時点ではスロットの flags がまだ無傷なので安全である（オブジェクトはまだゼロ化されていない）。

### 2.5 監査の最後の砦: グローバルでない GC が shareable で free の経路に到達したら `rb_bug`

`gc/default/default.c:4115`（ピンの数行後、実際の free の前）

```c
#if RACTOR_LOCAL_GC_AUDIT
    /* u->s liveness invariant: a per-Ractor local GC must NEVER free a shareable object ... */
    if ((objspace->local || rlgc_has_local) && !rlgc_global_gc_active && RB_OBJ_SHAREABLE_P(vp)) {
        rb_bug("RLGC-AUDIT: non-global GC freeing a shareable object: %s", rb_obj_info(vp));
    }
#endif
```

**何を / なぜ:** `RACTOR_LOCAL_GC_AUDIT` のもとで、これは 2.4 の不変条件を*構成的に*アサートする。グローバルでない GC で shareable に対して free の経路に到達することがあれば、上のピンがバイパスされたということであり、即座にオブジェクト情報とともに `rb_bug` する — 静かにそれを解放して後で遠く離れた場所でクラッシュする（ダングリングした unshareable な子、原因究明が困難）のではなく。これはピンとまったく同じ述語を使うので、ピンのロジックとこのチェックが食い違ったとき、すなわち本物のバグのときにのみ発火しうる。

**レビュアーへの注意点:** これは*監査ビルド専用*（デフォルトでは off）なので、本番ビルドを保護しない — 開発時のワイヤ（tripwire）である。同じ述語が 2 度現れるのは意図的である（ガードと、ガードのアサーション）。一方を編集するなら両方を編集すること。

### 2.6 `gc_marks_start` / `gc_marks_finish`: ローカル対グローバルの mark の振る舞い

`gc_marks_start` — `gc/default/default.c:6615`、クリア処理は `gc_full_mark_clear_objspace`（`:6585`）に切り出された:

```c
#if RACTOR_LOCAL_GC
        if (rlgc_global_gc_active) {
            /* GLOBAL GC: the unified mark below repopulates mark/old/remembered/shared
               bits and counters across EVERY objspace, so clear them everywhere first. */
            rb_gc_foreach_objspace(gc_full_mark_clear_thunk, NULL);
        }
        else
#endif
        {
            gc_full_mark_clear_objspace(objspace);
        }
```

**何を:** フル mark のリセット（カウンタのゼロ化、`rgengc_mark_and_rememberset_clear`、プールされたページ→空きページへの移動）は `gc_full_mark_clear_objspace` に切り出された。これにより、グローバル GC は単一の統合 mark がすべてを再投入する前に、それを（`rb_gc_foreach_objspace` 経由で）**すべての** objspace に適用できる。ローカル/単一のフル mark は自分の objspace だけをクリアする。

**なぜ:** グローバル GC はすべての objspace を 1 つのグラフとしてクリア*かつ再 mark* するので、それらのビットマップはすべて事前にリセットされなければならない。クリアのうち shareable に関わる部分が微妙なところである — `rgengc_mark_and_rememberset_clear`（`:6940` 付近）を参照:

```c
#if RACTOR_LOCAL_GC && !RACTOR_LOCAL_GC_AUDIT
    /* shared_bits ... may only be cleared+recomputed when ALL shareable parents are visible:
       either the pure single-objspace case, or a GLOBAL all-objspace GC. ...
       A per-Ractor LOCAL GC must NOT clear it (it cannot see foreign parents) ... */
    if (!rlgc_has_local || rlgc_global_gc_active) {
        memset(&page->shared_bits[0], 0, HEAP_PAGE_BITMAP_SIZE);
        page->flags.has_shared_objects = FALSE;
    }
#endif
```

ローカル GC が `shared_bits` をクリアすれば破滅的である。それらのビットを正当化する foreign な shareable の親が見えないため、`gc_shared_relation` はそれらを再構築できず、境界オブジェクトが sweep されてしまう。よって `shared_bits` は、*すべての*親が見えているときにのみクリア+再構築される。

また、`gc_marks_start` では自動 compaction が無効化される（`&& !rlgc_has_local`、`:6635` 付近）点にも注意 — compaction はオブジェクトを動かすため、objspace 越えの参照 / `shared_bits` / shareable を動かさない不変条件と両立しない。（compaction は Section 5 で扱う。）

`gc_marks_finish` — `gc/default/default.c:6224`。RLGC 向けの調整が 2 つある:

```c
        /* RLGC: during a global GC the driver objspace's marked_slots accumulates objects
           marked in EVERY objspace ... so it is an aggregate that can exceed this one
           objspace's available slots. */
        GC_ASSERT(rlgc_global_gc_active || objspace_available_slots(objspace) >= objspace->marked_slots);
```

```c
    if (!objspace->local || objspace->flags.global_gc) {
        rb_ractor_finish_marking();
    }
```

**何を/なぜ:** (1) `marked_slots >= available` の不変条件は objspace ごとのものである。グローバル GC のもとではドライバの `marked_slots` は VM 全体の集計値である（すべての objspace のマークが `gc_aging` 経由でドライバのカウンタに合流する）ので、`rlgc_global_gc_active` のときアサートは緩められる。(2) `rb_ractor_finish_marking` は VM ロックのもとで VM グローバルな配列を解放/クリアする。ロックフリーなローカル GC はこれを実行してはならない（2 つの並行ローカル GC がそれを二重解放してしまう）ので、STW なコレクション（main の objspace の GC、またはグローバル GC）でのみ実行され、ローカル GC はそれを先送りする。

**どう噛み合うか:** これは mark-finish の記帳においてグローバル対ローカルの分岐が表面化したものである。同じコードが、限定的な Ractor ごとの minor と、統合された STW なグローバル mark の両方を駆動し、`rlgc_global_gc_active` / `objspace->local` がそのつど正しい不変条件を選ぶ。

**レビュアーへの注意点:**
- `GC_ASSERT` を緩めることは常に精査に値する。集計カウンタという理屈が超過しうる*唯一の*理由であること、そして objspace ごとの経路（ローカル GC）が依然としてそれを強制していることを確認すること。ローカル GC に本物の過剰カウントのバグが存在すれば、それは依然として捕捉される。
- `gc_full_mark_clear_thunk` は `data` 引数を無視し、無条件にクリアする — これは `rlgc_global_gc_active`（STW）のもとでのみ呼ばれるので問題ない。並行する書き手がいないからである。
- `shared_bits` のクリアは `RACTOR_LOCAL_GC_AUDIT` のもとでは抑制される（`&& !RACTOR_LOCAL_GC_AUDIT`）。監査モードはビットを残しておき、`gc_shared_relation` が WB が記録したものと mark が発見したものを比較できるようにしたいからである（2.2）。

### 2.7 `gc_mark_check_t_none`: これらのガードが満たすために存在する、変更されていないワイヤ

`gc/default/default.c:5136`（`gc_mark` の `:5179` から呼ばれる） — **この関数はこの diff によって変更されていない**（ベース `de5545202` と同一）:

```c
static inline void
gc_mark_check_t_none(rb_objspace_t *objspace, VALUE obj)
{
    if (RB_UNLIKELY(BUILTIN_TYPE(obj) == T_NONE)) {
        ...
        rb_bug("try to mark T_NONE object (obj: %s, parent: %s)", obj_info_buf, parent_obj_info_buf);
    }
}
```

**なぜ本節に属するか:** これは、上記のガードのいずれかに穴があるときに発火するアサーションである。`BUILTIN_TYPE(obj) == T_NONE` は、マークが既に**解放された**スロット（sweep されて `T_NONE` に戻された）に到達したことを意味する — つまり、まだ参照されているオブジェクトが誤って回収されたのである。RLGC のもとでは、あらゆる confinement/liveness のバグ（Family I confinement-miss、Family II objspace 越えサブツリー、Family III 世代別 WB）は最終的にここで `try to mark T_NONE object` として現れる — そして付加された `parent: %s` が、ターゲットが誤って解放されたエッジを指し示す診断情報である。これが*変更されていない*という事実こそが要点である。RLGC のガード（foreign-skip、shared-roots、sweep ピン）は、まさにこのチェックを弱めることなくこの不変条件を真に保つために存在する。

**レビュアーへの注意点:**
- `gc_mark` 内の順序が重要である。foreign-skip（2.1）は `gc_mark_check_t_none` の*前に* return する。これは正しい — foreign なオブジェクトは決して読まれないので、それに対してアサートすることはない — が、同時にそれは、confinement の*ミス*（foreign-skip されるべきだったのにされなかったオブジェクト、または生かされるべきだったのに sweep されたオブジェクト）こそがこれを発火させる、ということでもある。RLGC のもとで T_NONE バグをトリアージするとき、問いは常に「どの objspace が `obj` を所有しているか、そしてなぜその objspace のルート/shared_bits によって生かされなかったのか」である。
- メッセージが有用であるためには `parent_object` が正確でなければならない。ルートパスは `gc_mark_set_parent_invalid`/`_raw` でそれを括っている。

---

## 3. shared_bits remset、write barrier、remembered set

このスライスでは、RLGC が **shareable -> unshareable 境界** を追跡するために追加するデータ構造（`shared_bits` remset）、write barrier がそれをどう構築するか、local GC がそこからどう root を辿るか、そして並行 local GC を安全にする ThreadSanitizer 由来のハードニング（アトミックなビットマップ操作 + バイト幅のページフラグ）について扱う。これらはすべて `gc/default/default.c` にある。

### 3.1 ページレイアウト: `shared_bits`、`objspace`、バイト幅フラグ

`gc/default/default.c:871-913`（diff `@@ -829,11 +871`）

```c
    struct {
        unsigned int before_sweep : 1;
        /* ... single atomic byte store that cannot lose a concurrent set ... */
        unsigned char has_remembered_objects;
        unsigned char has_uncollectible_wb_unprotected_objects;
#if RACTOR_LOCAL_GC
        unsigned char has_shared_objects;
#endif
    } flags;
    rb_heap_t *heap;
#if RACTOR_LOCAL_GC
    rb_objspace_t *objspace;   /* owning objspace */
#endif
    ...
    bits_t remembered_bits[HEAP_PAGE_BITMAP_LIMIT];
#if RACTOR_LOCAL_GC
    bits_t shared_bits[HEAP_PAGE_BITMAP_LIMIT];   /* boundary remset */
#endif
```

**何を:** 各ページに `shared_bits` ビットマップ（`remembered_bits` と同様、スロット 1 つにつき 1 ビット）と、所有元の `objspace` への逆ポインタが追加される。また、ページフラグのビットフィールド `has_remembered_objects` / `has_uncollectible_wb_unprotected_objects` が **`:1` のビットフィールドから完全な `unsigned char` バイトへと拡張され**、新たに `has_shared_objects` バイトが追加される。

**なぜ:** `shared_bits` は、RLGC が追跡しなければならない新たな境界、すなわち *shareable* なオブジェクトから直接参照される *unshareable* なオブジェクトのための remset である。`objspace` 逆ポインタは、confined な local GC が自分のオブジェクトと foreign なオブジェクトを区別するためのものである（マクロブロックの 1010 行目、`GET_HEAP_OBJSPACE`）。

ビットフィールド -> バイトへの変更は **見た目の問題ではなく TSan の修正である**。従来の `:1` フラグは 1 つのストレージワードを共有していた。RLGC 下では、lock-free な write barrier と並行する local GC が、*同時に異なる Ractor スレッドから* これらのフラグを設定する。ビットフィールドに対する `flags.has_x = TRUE` の書き込みはワード全体の非アトミックな read-modify-write であるため、*隣接する* フラグへの並行設定が失われうる。各フラグをそれぞれ独立したバイトに昇格させることで、`flags.has_x = TRUE` は単一の独立したバイトストアになる。`:881` のコメントがこれを明示し、後述の `shared_bits` / `remembered_bits` のアトミック修正を相互参照している。

**レビュアー向け注意点:**
- `has_shared_objects` と `shared_bits` は「このオブジェクトは別 objspace の shareable 経由でしか到達できないか?」というシグナルである。これらは WB（3.4）、audit モードの mark 再計算（3.3）、`rb_gc_impl_pin_shared`（3.6）、そして compaction の move 後処理（diff の 1623 行目）によって書き込まれ、`gc_mark_shared_roots`（3.5）によって読み込まれる。
- バイトフラグは依然として `_Atomic` ではなく単なるバイトである点に注意。正しさは、各フラグが *独立した* アドレスであり隣接バイトが torn になりえないことに依存している。*同じ* フラグへの並行設定は冪等である（常に `TRUE`）。

### 3.2 アトミックなビットマップヘルパ `gc_bitmap_atomic_set` / `MARK_IN_BITMAP_ATOMIC`

`gc/default/default.c:1003-1015`（diff の 136-149 行目）

```c
static inline bool
gc_bitmap_atomic_set(bits_t *bits, const struct heap_page *page, VALUE obj)
{
    volatile size_t *const word = (volatile size_t *)&bits[SLOT_BITMAP_INDEX(page, obj)];
    const size_t mask = (size_t)SLOT_BITMAP_BIT(page, obj);
    size_t old = 0;
    while ((old & mask) != mask) {
        const size_t prev = RUBY_ATOMIC_SIZE_CAS(*word, old, old | mask);
        if (prev == old) return true;
        old = prev;
    }
    return false;
}
#define MARK_IN_BITMAP_ATOMIC(bits, p)  gc_bitmap_atomic_set((bits), GET_HEAP_PAGE(p), (p))
```

**何を:** アトミックな `bitmap_word |= bit` であり、*この* 呼び出しがビットをクリア状態から立てた場合に限り `true` を返す。

**なぜ:** 1 つの `bits_t` ワードは `BITS_BITLENGTH` 個のスロットをカバーする。素の `MARK_IN_BITMAP` は非アトミックな RMW であるため、*異なるオブジェクトに対して同じワード* への 2 つの並行設定があると一方の更新が失われる。そして失われたビットは、*たまたまそのワードを共有している別のオブジェクト* のものである。`remembered_bits` の場合、これは依然として参照されている若いオブジェクトが次の minor GC で見落とされ解放されることを意味する。コメントはこれを ThreadSanitizer で確認済みであると記している（load-dependent な `fibers_escaping` の "mark T_NONE"）。これは MEMORY に記録されたものと同じ根本原因である。lock-free な RLGC モデル下では、*複数スレッドから書き込まれるすべてのビットマップワードにアトミック操作が必要* なのだ。

**どう噛み合うか:** `bits_t` はポインタ幅なので、`size_t` の CAS でワード全体をカバーできる。巧妙な点（`:1009` のコメント）は、ループが `old = 0` から開始することで、ワードへの **唯一の** アクセスが CAS そのものになる点である。並行する設定処理と競合しうる別個の非アトミックロードが存在しない。最初の空振りがあっても、CAS がアトミックに観測した値を読み直すだけである。

**レビュアー向け注意点:**
- `volatile size_t *` へのキャストは `bits_t` 配列をエイリアスしており、`sizeof(bits_t) == sizeof(size_t)`（ポインタ幅）に依存している。これが成り立たないプラットフォームでは確認する価値がある。
- *別の* スレッドが先に設定した場合と、既に設定済みだった場合の両方で `false` を返す。呼び出し側（3.7）は、`remembered_bits` のカウント後処理についてのみ「自分が新たに設定した」か否かを区別する。

### 3.3 global mark 中の境界再計算: `gc_shared_relation`

`gc/default/default.c:861-876`（diff の 861-876 行目）

```c
static inline void
gc_shared_relation(rb_objspace_t *objspace, VALUE obj)
{
    VALUE parent = objspace->rgengc.parent_object;
    if (!SPECIAL_CONST_P(parent) &&
        RB_OBJ_SHAREABLE_P(parent) && !RB_OBJ_SHAREABLE_P(obj)) {
#if RACTOR_LOCAL_GC_AUDIT
        if (!MARKED_IN_BITMAP(GET_HEAP_SHARED_BITS(obj), obj)) gc_shared_wb_miss(...);
#endif
        MARK_IN_BITMAP_ATOMIC(GET_HEAP_SHARED_BITS(obj), obj);
        GET_HEAP_PAGE(obj)->flags.has_shared_objects = TRUE;
    }
}
```

**何を:** marking 中に辿る各エッジごとに呼ばれる。*shareable* な parent が *unshareable* な child を指しているときは必ず、その child を `shared_bits` に（再）記録する。

**なぜ / どう噛み合うか:** `shared_bits` は global GC の統合 mark によって一括クリアされ、ゼロから再構築される（3.8 を参照。クリアされ、ここで再導出される）。WB は global GC の間、これをインクリメンタルに維持する。`RACTOR_LOCAL_GC_AUDIT` ビルドでは、これは WB の *相互チェック* も行う。WB が記録し損ねた境界エッジはすべて write-barrier miss として報告される。この audit パスこそが、メモリログにある Family I/III の confinement-miss バグを表面化させた手段である。

### 3.4 Write barrier: `shared_bits` の構築

`gc/default/default.c:7044-7066`（diff `@@ -6248,6 +7041`）

```c
#if RACTOR_LOCAL_GC
    if (RB_OBJ_SHAREABLE_P(b)) {
        MARK_IN_BITMAP_ATOMIC(GET_HEAP_SHARED_BITS(b), b);
        GET_HEAP_PAGE(b)->flags.has_shared_objects = TRUE;
    }
    else if (RB_OBJ_SHAREABLE_P(a) || MARKED_IN_BITMAP(GET_HEAP_SHARED_BITS(a), a)) {
        MARK_IN_BITMAP_ATOMIC(GET_HEAP_SHARED_BITS(b), b);
        GET_HEAP_PAGE(b)->flags.has_shared_objects = TRUE;
        rlgc_wb_shared_sets++;
        if (GET_HEAP_OBJSPACE(b) != rlgc_main_objspace) rlgc_wb_local_sets++;
    }
#endif
```

これは `rb_gc_impl_writebarrier(a, b)`（a が b への参照を獲得する）の中で、既存の世代別リトライロジックの *前に* 実行される。分岐は 2 つある:

- **`b` が shareable の場合:** `b` 自身を shared としてマークする。shareable は別の Ractor から参照されうる（例: shareable な iseq 内のインラインキャッシュ経由で到達する callcache）ため、`b` の所有元の local GC は `b`（およびその部分木）を生かし続けなければならない。shareable は global GC まで pin されるので、`b` を `shared_bits` に記録することで `b` が local GC の root になる。
- **`b` が unshareable だが `a` が shareable の場合（または `a` 自身が shared な境界オブジェクトの場合）:** `b` を shared としてマークする。これが境界ケースの核心である。`b` は、local GC が決して辿らない objspace に存在する shareable な参照元から（直接、あるいは別の shared オブジェクト、たとえばクラスの per-Ractor classext を介して推移的に）到達可能である。`MARKED_IN_BITMAP(... a)` のテストは、shareable からぶら下がる unshareable オブジェクトの連鎖をたどって「shared 性」を推移的に伝播させる。

**なぜこれが健全か（鍵となる不変条件、`:7045` のコメント）:** このストアは `b` の所有元によってしか実行されえない。Ractor 隔離により、Ractor をまたいだ *unshareable* な参照を保持することは禁じられているからである。したがって WB は常に *自分自身の* オブジェクトにビットを立てる。shareable な `a` は別の Ractor の空間に存在しうるが **決して触られない**。これが lock-free な WB を confined に保つ要点である。

**レビュアー向け注意点:**
- `else if` の中の `MARKED_IN_BITMAP(GET_HEAP_SHARED_BITS(a), a)` の読み出しは、別スレッドによる書き込みの可能性に対する *非アトミックな読み出し* であるが、`a` は所有元自身のオブジェクトである（隔離の議論による）ため、unshareable パスではこの読み出しは実際には Ractor をまたがない。ここで `a` が決して foreign になりえないことは確認する価値がある。
- このブロックは GC モードに *無条件* である。local GC が存在しないときでも実行される。コストは、barrier 対象となる各ストアにつき 2 回の読み出し +（まれに）アトミックな CAS 1 回である。`rlgc_wb_*_sets` カウンタはデバッグ専用である。

### 3.5 local GC で remset から root を辿る: `gc_mark_shared_roots`

`gc/default/default.c:6808-6843`（diff の 1281-1331 行目）

```c
static void
gc_mark_shared_roots(rb_objspace_t *objspace)
{
    ... ccan_list_for_each(&heap->pages, page, page_node) {
        if (!page->flags.has_shared_objects) continue;
        ... for each set bit in page->shared_bits:
            VALUE sobj = (VALUE)pp;
            gc_mark(objspace, sobj);
            if (RVALUE_OLD_P(objspace, sobj)) {
                gc_mark_children(objspace, sobj);
            }
```

root マーキングのパスから `gc/default/default.c:5365-5372`（diff 1002-1006）で呼び出され、`(objspace->local || rlgc_has_local) && !rlgc_global_gc_active` でガードされる:

```c
    if ((objspace->local || rlgc_has_local) && !rlgc_global_gc_active) {
        MARK_CHECKPOINT("shared_roots");
        gc_mark_set_parent_raw(objspace, Qundef, false);
        gc_mark_shared_roots(objspace);
    }
```

**何を:** local GC の root パスである。この objspace のうち `has_shared_objects` が立っているページを走査し、`shared_bits` でフラグが立っている各スロットをマークする。これにより、*別の* objspace にある shareable な parent（クラスのメソッド/定数キャッシュなど）経由でしか到達できず、この Ractor の通常の root では到達できない境界オブジェクトを生かし続ける。

**OLD 境界の再走査（`:6826` のコメント）が、微妙な正しさの修正である。** OLD まで歳をとった shared-root オブジェクトは uncollectible であるため、`gc_mark` は短絡する（`gc_mark_set` が「マーク済み」を返す）**が grey にはしない**。その結果、その若い子は minor GC で決して辿られなくなる。通常の old オブジェクトと異なり、shared-root オブジェクトは remembered set ではなく `shared_bits` 経由で root されているため、`rgengc_rememberset_mark` もこれをカバーしない。明示的な `gc_mark_children` がなければ、その若い部分木は、objspace をまたぐ shareable が依然それを参照しているにもかかわらず sweep されてしまう。これがまさに「dangling cross-objspace child / mark-T_NONE / 解放されたクラスの m_tbl, cc」のクラッシュファミリーである。そこで `gc_mark_shared_roots` は OLD な shared root の子を直接再走査し、`rgengc_rememberset_mark` が remembered な old オブジェクトに対して行うことを模倣する。

**global GC が意図的にこれをスキップする理由**（`:5374` のコメント）: global STW GC 下では、統合 mark が VM の全 root + objspace をまたぐエッジを辿り、shareable の生存を *到達可能性* によって判定するため、死んだ shareable をついに回収できる。`gc_shared_relation` が mark しながら `shared_bits` をゼロから再構築する（ビットは marks 開始時にクリアされている）。ここで `shared_bits` から root を辿ると、死んだ shareable を永久に誤って pin してしまう。

**レビュアー向け注意点:**
- ガード `objspace->local || rlgc_has_local` は、local objspace が 1 つでも存在すれば *main* objspace の GC でさえ `shared_bits` から root を辿ることを意味する。main-objspace の shareable が worker からしか参照されないことがありうるため、これは必要である。
- 呼び出しごとの `getenv("RLGC_DEBUG")` 行はデバッグ用の `fprintf` である。問題はないが、shared-roots パスのたびに `getenv` を呼ぶことになる。

### 3.6 `rb_gc_impl_pin_shared` — 明示的な境界 pin

`gc/default/default.c:6845-6859`（diff の 1338-1343 行目）

```c
void
rb_gc_impl_pin_shared(VALUE obj)
{
    MARK_IN_BITMAP_ATOMIC(GET_HEAP_SHARED_BITS(obj), obj);
    GET_HEAP_PAGE(obj)->flags.has_shared_objects = TRUE;
}
```

VM ロック下で生成され（メソッド/インラインキャッシュ、クラス拡張）、local GC が決して辿らない shareable 経由でしか到達できない VM 内部インフラを、境界 remset に強制的に入れて、所有元の local GC がそれを生かし続けられるようにする。これは WB の自動記録に対応する明示的 pin であり、いくつかの confinement-miss 修正（タスクリストの Faces B/D 等）を支えている。

### 3.7 remembered-set のプロデューサをアトミックに: `rgengc_remembersetbits_set`

`gc/default/default.c:6738-6748`（diff `@@ -6031,14 +6738`）

```c
    const bool newly = gc_bitmap_atomic_set(bits, page, obj);
    page->flags.has_remembered_objects = TRUE;
    return newly ? TRUE : FALSE;
```

**何を:** 従来の `MARKED_IN_BITMAP` テスト + 非アトミックな `MARK_IN_BITMAP` を、アトミックなヘルパに置き換える。

**なぜ / 順序:** 従来の非アトミックな test-then-`|=` は、ワードを共有する他のオブジェクトのビットを取りこぼしていた（3.2）。決定的に重要なのは、新しいコードが **まずビットを立て、それからページフラグを立てる** 点である。これは `rgengc_rememberset_mark`（3.8）との競合プロトコルのプロデューサ側である。コンシューマは *ビットを drain する前にフラグをクリアする* ので、ここでビット -> フラグの順に設定することで、並行する drain は我々のフラグを見る（そして再スキャンする）か、我々のビットが drain がアトミックにゼロ化しようとしている/した直後のワードに着地する、のいずれかになり、決して黙って取りこぼされることはない。

### 3.8 remembered-set のコンシューマ drain: `rgengc_rememberset_mark`

`gc/default/default.c:6894-6912`（diff `@@ -6122,11 +6894`）

```c
            page->flags.has_remembered_objects = FALSE;   /* clear flag BEFORE draining */
            for (j=0; j < (size_t)bitmap_plane_count; j++) {
#if RACTOR_LOCAL_GC
                const bits_t rem = (bits_t)RUBY_ATOMIC_SIZE_EXCHANGE(*(volatile size_t *)&remembered_bits[j], 0);
#else
                const bits_t rem = remembered_bits[j];
                remembered_bits[j] = 0;
#endif
                bits[j] = rem | (uncollectible_bits[j] & wb_unprotected_bits[j]);
            }
```

**何を:** 変更は 2 つ。(1) `has_remembered_objects = FALSE` がビット drain の **前に移動された**（以前は後だった。diff 1369 の削除行を参照）。(2) ワードごとの「remembered ビットを読んでからゼロ化する」処理が、RLGC 下では単一の `RUBY_ATOMIC_SIZE_EXCHANGE`（アトミックな read-and-clear）になった。

**なぜ（`:6896` のコメント）:** 別の Ractor 上の並行する lock-free WB は、このページ上のオブジェクトを *ビット -> フラグ* の順で remember する（3.7）。ここで先にフラグをクリアするということは、もしそのような設定が我々のフラグクリアの *後に* 競合してきたら、フラグが `TRUE` に戻り、ページは次回再スキャンされる、つまり何も失われないということである。アトミックな exchange により、競合する `MARK_IN_BITMAP_ATOMIC` は exchange の前に着地する（今回 drain される）か、後に着地する（ゼロ化されたワードに着地し、次回パスのために保持される）かのいずれかになり、決して lost-update の tear にはならない。これは 3.7 の順序とちょうど対になり、完全な lock-free のプロデューサ/コンシューマのハンドシェイクを形成する。

**レビュアー向け注意点:**
- 「drain の前にフラグをクリアする」順序は load-bearing であり、つい従来の位置に「整理」して戻しがちである。必ずループの前に置かなければならない。
- 非 RLGC パスは変更されていない（素の `= 0`）ので、アトミックなコストは RLGC のみに発生する。

### 3.9 安全なときのみ `shared_bits` をクリア/再計算する

`gc/default/default.c:6940-6956`（diff `@@ -6158,6 +6940`）

```c
#if RACTOR_LOCAL_GC && !RACTOR_LOCAL_GC_AUDIT
    if (!rlgc_has_local || rlgc_global_gc_active) {
        memset(&page->shared_bits[0], 0, HEAP_PAGE_BITMAP_SIZE);
        page->flags.has_shared_objects = FALSE;
    }
#endif
```

`rgengc_mark_and_rememberset_clear` の中にある。**何を:** `shared_bits` は、純粋な単一 objspace のケース、または *global* GC 下に **限って** 消去される（その後、統合 mark 中に `gc_shared_relation` によって再構築される）。**なぜ:** per-Ractor の *local* GC は foreign な shareable parent を見ることができないため、境界 remset をクリアしてはならない。shareable は、次の global GC が回収するまで `shared_bits` 経由で pin され続ける。これは 3.5 の root 側のガードに対応するクリア側のものである。local GC は `shared_bits` を *読むがクリアは決してしない*。全 objspace が見える global mark だけがそれを再計算する。AUDIT ビルドでもスキップされる点に注意（audit が WB 維持のビットと mark を比較できるようにするため）。

### 3.10 認識された設計上の選択: objspace をまたぐ old -> young エッジは remember しない

`gc/default/default.c:5743-5750`（diff `@@ -5124,6 +5740`）

```c
#if RACTOR_LOCAL_GC
    /* RLGC: a cross-objspace old->young edge is NOT covered by the generational remembered set. ... */
    if (!SPECIAL_CONST_P(child) && GET_HEAP_OBJSPACE(child) != GET_HEAP_OBJSPACE(parent)) return;
#endif
```

これは `check_generation_i`、すなわちすべての old -> young エッジが remembered set に入っていることを表明する `RGENGC_CHECK_MODE` の verifier の中にある。**何を:** RLGC 下では、objspace をまたぐ old -> young エッジは *意図的に* 除外される。child は別の objspace に存在し、そこで生かされている。unshareable -> shareable の境界は `shared_bits` が扱い、local GC は foreign なオブジェクトを foreign-skip する。したがってそのようなエッジは write-barrier miss では **なく**、verifier はこれを報告してはならない。

**レビュアー向け注意点:** これは 2 つの機構の明示的な境界である。*objspace 内* のエッジ -> 世代別 remembered set（3.7/3.8）、*objspace をまたぐ* 境界 -> `shared_bits`（3.4/3.5）。レビュアーは、objspace をまたぐ生存を remembered set に依存しているものが何もないこと（それは `shared_bits` の仕事である）、およびこの早期 `return` が *本物の* objspace 内の miss を覆い隠していないこと（2 つの objspace が異なるときにのみ return する）を sanity check すべきである。MEMORY のメモにある通り、`RGENGC_CHECK_MODE` の verifier はいずれにせよ並行性の競合を捕捉できない。それらには TSan が適したツールである（3.2）。

---

**このスライス全体にわたるレビュアー向けメモ:**
- この設計全体は 1 つの隔離不変条件に依存している。unshareable なオブジェクトはその所有元 Ractor によってしか書き込まれないため、WB は常に *local* なオブジェクトに `shared_bits` を立て、foreign な shareable 参照元には決して触れない。この不変条件が破られると、lock-free な WB は Ractor をまたぐデータ競合になる。
- いまや 3 つのビットマップワードがマルチライタである。`shared_bits`、`remembered_bits`（いずれもアトミックな CAS/exchange 経由）、そしてページのバイトフラグ（独立したバイト）である。WB または並行する local GC が書き込む *新しい* ページビットマップは、いずれも同じアトミックの規律に従わなければならない。これが TSan 修正から得られる一般化された教訓である。
- `gc_mark_shared_roots` の OLD 再走査（3.5）と、`gc_shared_relation` / クリアのガード（3.3、3.9）は、合わせて「local GC は shareable を pin し、global GC がそれを回収する」を実装している。どちらかの側で `rlgc_global_gc_active` のガードを壊すと、死んだ shareable をリークする（local GC でクリアする場合）か、生きている境界部分木を解放する（global GC で root を辿る場合）かのいずれかになる。

---

## 4. compaction の無効化、finalizer の所有権ルーティング、その他 (`gc/default/default.c`)

このファイルが受け持つ RLGC diff の範囲には、独立した 3 つの関心事がある。(1) per-Ractor objspace が存在する場合は常に **compaction を強制的に無効化する**。オブジェクトの移動は objspace 間参照と本質的に相容れないからである。(2) **finalizer は所有者 objspace のテーブルへルーティングされる**。`obj` は呼び出し元とは別の Ractor に所有されている場合があるためである。(3) global GC がすべての objspace を一度に sweep する必要があることに伴う、散在した **per-objspace の配管処理**(newobj キャッシュの flush、finalizer テーブルの marking、整合性チェックの gating)。以下のすべては `#if RACTOR_LOCAL_GC` でガードされており、stock の CRuby では no-op になる。

finalizer のルーティングの土台には小さなインフラがある。これを最初に押さえておく。なぜなら、それがルーティングコードがあのような形になっている理由を説明するからである。

### そもそもなぜ `rlgc_finalizer_table()` アクセサが存在するのか
`gc/default/default.c:165`
```c
/* Accessor for ANOTHER objspace's finalizer_table — must be defined BEFORE the macro below, which
 * rewrites the bare token `finalizer_table` to `objspace->finalizer_table`. */
static inline st_table *rlgc_finalizer_table(rb_objspace_t *os) { return os->finalizer_table; }
#define finalizer_table 	objspace->finalizer_table
```
このファイルでは `#define finalizer_table objspace->finalizer_table` が随所で使われており、修飾なしのコードは「現在の objspace のテーブル」を読む形になっている。だが *別の* objspace のテーブルが必要になった瞬間、このマクロは明確に誤りとなる。`finalizer_table` は常にローカルの `objspace` しか指せないからである。inline アクセサはその逃げ道であり、これは意図的にマクロの 1 行 **上** に定義されている(さもなければマクロがアクセサ本体内の `os->finalizer_table` まで書き換えてしまう)。同じパターンが 158 行目の `rlgc_get_during_gc`/`rlgc_set_during_gc` でも使われている。**レビュアーへの注意点:** 新たに objspace 間のフィールドアクセスを追加する場合は、必ずその `#define` より前に宣言したアクセサを使わなければならない。素のマクロに頼ると、黙って誤った objspace を対象にしてしまう。

---

### compaction の無効化 — `GC.compact` (Face-E の兄弟)
`gc/default/default.c` (diff line 1640, function `gc_compact`)
```c
bool compact = true;
#if RACTOR_LOCAL_GC
    if (rlgc_has_local) compact = false;
#endif
    rb_gc_impl_start(objspace, true, true, true, compact);
```
**何を:** `GC.compact` は通常 `compact=true` で full GC を走らせる。RLGC 下では非移動の full GC に格下げされ、それでも `gc_compact_stats(self)` を返す(これは正直に「移動オブジェクト 0」を報告する)。**なぜ:** compaction はオブジェクトを再配置する。RLGC 下ではそれが objspace 間ポインタ、(スロットアドレスをキーとする)per-page の `shared_bits` remset、および shareable は自身のホーム objspace から決して移動しないという不変条件を無効化してしまう。**どう収まるか:** エラーにするのではなく、`GC.compact` は「collect はするが move はしない」へと優雅に degrade する。**注意点:** ゲートは「自分はローカル Ractor か」ではなく `rlgc_has_local`(非 main objspace が初めて生成された時点でセットされる)である。いったん *いずれかの* Ractor が存在すれば、main-Ractor の `GC.compact` であっても move してはならない。

### compaction の無効化 — `GC.verify_compaction_references`
`gc/default/default.c` (diff line 1661)
```c
if (rlgc_has_local) {
    rb_gc_impl_start(objspace, true, true, true, false);
    return gc_compact_stats(self);
}
```
理由は同じで、関数の冒頭で早期 return している。これにより、move-and-verify の機構(objspace 間参照でクラッシュするであろうもの)には決して入らない。

### auto-compaction の無効化 — `ruby_enable_autocompact` の 2 つの使用箇所 (実際の Face-E の修正)
`gc/default/default.c` (diff lines 1210 and 1475)
```c
if (ruby_enable_autocompact
#if RACTOR_LOCAL_GC
    && !rlgc_has_local
#endif
    ) {
    objspace->flags.during_compacting |= TRUE;
}
```
これは、auto-compact フラグから `during_compacting` が立てられる **両方の** 箇所、すなわち `gc_marks_start`(major-GC 経路)と `gc_start`(明示的に有効化する経路)に追加された同一の `&& !rlgc_has_local` ガードである。**なぜ setter ではなく使用箇所でゲートするのか:** `GC.auto_compact=true` は起動時、つまりいかなる Ractor よりも前に(したがって `rlgc_has_local` が true になる前に)設定されうる。そのため setter でゲートすると早すぎる。コメントがこの点を明記している。これはまさに設計サマリでいう Face E(以前、ガードされていない `auto_compact=true` が RLGC 下で compaction を走らせ heap を破壊していた問題)である。**レビュアーへの注意点:** これらが arming 箇所の *完全な* 集合である。将来のパッチが autocompact から `during_compacting` をセットする 3 つ目の箇所を追加するなら、同じガードを携えなければならない。さもないと RLGC 下で compaction が黙って再有効化される。なお `gc_is_moveable_obj` と残りの compaction 機構は **変更されていない**。今は単に到達不能になっているだけであり、これにより diff が小さく保たれ、かつ非 RLGC ビルド向けに移動コード経路もそのまま残る。

---

### finalizer のルーティング — `rb_gc_impl_define_finalizer` (Face F)
`gc/default/default.c:3307` (diff line 587)
```c
#if RACTOR_LOCAL_GC
    /* The finalizer entry must live in obj's OWNER objspace's table: run_final() looks it up there
     * during that objspace's sweep, and obj may be owned by a different Ractor than the caller (e.g.
     * a finalizer defined on a shareable object). Mirrors rb_gc_impl_copy_finalizer(). */
    st_table *const ftbl = rlgc_finalizer_table(GET_HEAP_OBJSPACE(obj));
#else
    rb_objspace_t *objspace = objspace_ptr;
    st_table *const ftbl = finalizer_table;
#endif
```
**何を:** エントリ `[obj_id, proc]` は、呼び出し元の `objspace_ptr` ではなく、*`obj` を所有する* objspace のテーブル(`GET_HEAP_OBJSPACE(obj)` は `obj` のページをたどって所有 objspace に至る)に挿入される。関数の残りはその後ローカルの `ftbl` を使う。**なぜ:** finalizer は所有者の sweep 中に発火する(3416 行目の `run_final` は素の `finalizer_table` マクロ、すなわち *自分の* objspace のテーブルを介してエントリを引く)。**shareable** オブジェクト(これは main/home objspace に存在する)に対して worker Ractor から finalizer を定義すると、呼び出し元の `objspace_ptr` は worker のものだが、そのオブジェクトを sweep するのは home objspace である。`GET_HEAP_OBJSPACE(obj)` へルーティングすることで、定義側と sweep 側が同じテーブルを見るようになる。これが Face F である。

### finalizer のルーティング — `rb_gc_impl_undefine_finalizer`
`gc/default/default.c:3374` (diff line 621)
```c
st_table *const ftbl = rlgc_finalizer_table(GET_HEAP_OBJSPACE(obj));
...
st_delete(ftbl, &data, 0);
```
所有者のテーブルからの対称な削除である。なお、非 RLGC 用の `objspace` ローカルは関数先頭から *削除* され、`#else` の内側にのみ再導入されている。これにより、RLGC 下で素の `finalizer_table` マクロを誤って使うと、黙って誤ったテーブルを対象にするのではなくコンパイルに失敗する。これは意図的なコンパイル時ガードである。

### finalizer のルーティング — `rb_gc_impl_copy_finalizer` (2 つの objspace が関わるケース)
`gc/default/default.c:3374` (diff line 647)
```c
rb_objspace_t *const src_objspace  = GET_HEAP_OBJSPACE(obj);
rb_objspace_t *const dest_objspace = GET_HEAP_OBJSPACE(dest);
...
if (RB_LIKELY(st_lookup(rlgc_finalizer_table(src_objspace), obj, &data))) {
    table = rb_ary_dup((VALUE)data);
    RARRAY_ASET(table, 0, rb_obj_id(dest));
    st_insert(rlgc_finalizer_table(dest_objspace), dest, table);
```
**何を:** copy は、2 つの異なる objspace が同時に関与しうる唯一の finalizer 操作である。`obj` のテーブルから読み、`dest` のテーブルへ書き込む。**なぜ:** copy は、たとえば Ractor が main objspace に存在する shareable オブジェクトを clone するときに起きる。元のエントリは main のテーブルにあるが、clone は Ractor に所有され、Ractor の sweep の下で finalize されなければならない。よって新しいエントリは `dest` のテーブルに入る。単一の `finalizer_table` マクロでは「2 つの異なるテーブル」を表現できず、まさにそのためにアクセサが存在する。**レビュアーへの注意点:** これが走る時点で `dest` はすでにページを解決できる heap オブジェクトでなければならない(実際そうなっている。copy は割り当て後に起きる)。まだページに載っていない値に対する `GET_HEAP_OBJSPACE` は未定義となる。

### global GC 下での per-objspace finalizer テーブルの marking
`gc/default/default.c` (diff lines 958 and 987)
```c
static void
gc_mark_other_objspace_finalizer_table_i(void *os_ptr, void *driver_ptr)
{
    rb_objspace_t *const os = os_ptr;
    if (os == driver_ptr) return; // the driver's own table is marked by mark_roots
    st_table *const ft = rlgc_finalizer_table(os);
    if (ft != NULL) st_foreach(ft, pin_value, (st_data_t)driver_ptr);
}
...
// in mark_roots():
if (rlgc_global_gc_active) {
    rb_gc_foreach_objspace(gc_mark_other_objspace_finalizer_table_i, objspace);
}
```
**何を:** `finalizer_table` は per-objspace である。`mark_roots` は *driver* objspace のテーブルしか pin しない(すぐ上にある既存の `st_foreach(finalizer_table, pin_value, ...)` がそれ)。global GC は **すべての** objspace を clear して sweep するため、これがないと、*各 worker* の finalizer 配列(これは通常の root から到達できない内部の隠し配列で、その worker のテーブルを介してのみ live である)が sweep されてしまい、テーブルが dangling になって `run_final` での UAF、あるいはその worker の次の local GC での「mark T_NONE」を引き起こす。**どう収まるか:** ルーティングの修正(Face F)はエントリを正しいテーブルに置いた。こちらは global GC がそれらのテーブルの値を実際に *生かし続ける* ことを保証する。この 2 つは対になっている。ここで objspace 間の marking が健全なのは、まさに `rlgc_global_gc_active` がセットされている(STW、foreign-skip が解除され、`pin_value` は値自身のページ上に pin する)からである。**注意点:** これは `rlgc_global_gc_active` のときにのみ走る。*local* GC は自分のテーブルだけを mark する(正しい。local GC は自分の objspace だけを sweep するからである)。

---

### 整合性チェックの gating — `gc_verify_internal_consistency_maybe`
`gc/default/default.c` (diff lines 676, 1108, 1151, 1162, 1467, 1522)
この diff は、`#if RGENGC_CHECK_MODE >= 2 / gc_verify_internal_consistency(objspace) / #endif` のブロックをすべて単一の `gc_verify_internal_consistency_maybe(objspace)` 呼び出しに置き換える。**なぜ:** この verifier は RLGC を意識している(write barrier が意図的に追跡しない objspace 間のエッジをスキップしなければならない。diff lines 1020/1035 の `check_generation_i`/`check_color_i` を参照。これらは `GET_HEAP_OBJSPACE(child) != GET_HEAP_OBJSPACE(parent)` のとき早期 `return` する)し、実行時に切り替えられる(MEMORY のメモにあるとおり `RUBY_GC_VERIFY=1`)。コンパイル時の `#if` を 1 つのヘルパに畳み込むことで、その gating を集約している。**レビュアーへの注意点:** MEMORY のエントリが記録しているとおり、このスナップショット verifier は並行性レースを *捕捉できない*(GC barrier がその窓を覆い隠す)。これは構造チェックにすぎない。その存在をレース対策の網羅と読み取ってはならない。

### newobj キャッシュの flush は明示的な objspace を取る
`gc/default/default.c` (diff line 750, `gc_ractor_newobj_cache_clear`)
```c
-    rb_objspace_t *objspace = rb_gc_get_objspace();
+    rb_objspace_t *objspace = (rb_objspace_t *)data;
```
**何を:** キャッシュ flush のコールバックは、`rb_gc_get_objspace()` ではなく `data` として渡された objspace へ flush するようになった。**なぜ:** Ractor の newobj キャッシュは、スロットが物理的に *その Ractor の* objspace に存在する進行中ページ + freelist を保持している。それらを別の heap に追加すると両方が壊れる。呼び出し元はいまや所有 objspace を渡す。`gc_sweep_start`(diff 762)と `after_fork`(diff 1716、`gc_after_fork_flush_objspace` 経由)は、global sweep の間、各キャッシュをそれ自身の objspace にのみ flush する。**注意点:** これが「global GC が全 objspace を順に sweep する」を正しくする要(かなめ)である。各キャッシュは、*その* objspace が sweep されるときに、ちょうど一度だけ flush され、決して driver のものに flush されることはない。

### 「objspace をまたぐ each_objects」についてのメモ
`rb_gc_impl_each_objects` (`default.c:3278`) 自体は **変更されていない**。依然として `objspace_each_objects` を介して単一の objspace を反復する。この diff における objspace 間の反復は、1 段上の `rb_gc_foreach_objspace(thunk, …)` で行われる(たとえば diff 1196 の `gc_full_mark_clear_thunk` は、global mark の開始時に全 objspace で mark/old/remembered/shared の各ビットを clear し、上記の finalizer テーブル thunk もこれである)。したがって「global GC が全 objspace に触れる」は、変更された `each_objects` からではなく、per-objspace のプリミティブ群と foreach のドライバの組み合わせから構成されている。「global GC は本当に全 objspace を網羅するのか」を監査するレビュアーは、いずれも `rlgc_global_gc_active` でゲートされている `rb_gc_foreach_objspace` の呼び出し箇所をたどるべきである。

---

## 5. `gc.c` — インターフェース層: ルート、orphan リスト、keep-alive、id2ref

`gc.c` は VM と差し替え可能な GC バックエンド (`gc/default/default.c`, MMTk) との間にある、GC 実装に依存しないインターフェースである。RLGC のもとでのその役割は、(1) アロケーション/マーキングを *現在の Ractor の* objspace へルーティングすること、(2) global GC のために *すべての* objspace に対する反復を提供すること、(3) confined な local GC が共有状態を読み出したり解放したりしてしまうあらゆる箇所で、従来からの「VM のグローバルは main objspace に存在する」という前提を修正することである。gate に用いる 2 つのプライベートフラグは default 実装で定義されている。すなわち `rlgc_has_local` (何らかの local objspace が存在する) と `rlgc_global_gc_active` (STW の global GC が走行中である) であり、`gc/default/default.c:1558-1559` にある。

### 5.1 Objspace のルーティング: `rb_gc_get_objspace`

`gc.c:246-252`
```c
rb_ractor_t *cr = rb_current_ractor_raw(false);
if (cr != NULL && cr->local_gc_objspace != NULL) {
    return cr->local_gc_objspace;
}
return GET_VM()->gc.objspace;
```
**何を/なぜ:** 最も負荷を担う中心的な変更である。`gc.c` 内のすべての `rb_gc_get_objspace()` 呼び出し元は、いまや VM 全体のものではなく *呼び出し元 Ractor 自身のヒープ* に解決される。早期ブート時 (まだ main Ractor が存在しない) や、現在の Ractor を持たないスレッドに対しては `vm->gc.objspace` にフォールバックする。**注意点:** これがいまや Ractor 相対であるため、`obj` を所有する Ractor とは *別の* Ractor からこれを呼び出すコードパスはすべて潜在的な confinement バグである。本セクションの残りの大半は、それらを修復するために存在している。

### 5.2 orphan リスト: `rb_gc_orphan_local_objspace` + `rb_gc_foreach_objspace`

`gc.c:301-313` (orphan エントリ + 引き渡し)
```c
struct rb_orphan_objspace_entry { void *objspace; struct ccan_list_node node; };
static CCAN_LIST_HEAD(rb_gc_orphaned_objspaces);
...
void rb_gc_orphan_local_objspace(void *objspace) {
    if (objspace == NULL || objspace == GET_VM()->gc.objspace) return;
    struct rb_orphan_objspace_entry *e = malloc(sizeof(struct rb_orphan_objspace_entry));
    if (e == NULL) return; /* out of memory: leave it as before (unwalked) */
    e->objspace = objspace;
    ccan_list_add_tail(&rb_gc_orphaned_objspaces, &e->node);
}
```
`gc.c:319-340` (`rb_gc_foreach_objspace`)
```c
func(main_objspace, data);
if (!ruby_single_main_ractor) {
    ccan_list_for_each(&vm->ractor.set, r, vmlr_node) {
        if (r->local_gc_objspace != NULL && r->local_gc_objspace != main_objspace)
            func(r->local_gc_objspace, data);
    }
}
ccan_list_for_each(&rb_gc_orphaned_objspaces, e, node) { func(e->objspace, data); }
```
**なぜこれが中核的な修正なのか (Family I / cc_tbl UAF):** ファイル内のコメント (`gc.c:283-298`) が、これが防いでいる正確なクラッシュを説明している。Ractor が終了すると、`vm_remove_ractor` はそれを `vm->ractor.set` から外すが、その objspace は *解放されない* —— それはまだ shareable (例えば main へ送られたクラス) を所有している可能性がある。もし global GC がその orphan 化された objspace に到達できないと、そのクラスの mark ビットは決してクリアされず、統合された global mark は「すでにマークされている」クラスのところで短絡し、global sweep はまだインストールされている `cc_tbl` を解放する → 次のメソッドキャッシュのルックアップで UAF となる。orphan リストはそうした objspace を walk 可能な状態に保つ。`rb_gc_foreach_objspace` は「すべての生きたヒープ」の正準的なイテレータである。すなわち main + 各生存 Ractor + 各 orphan である。

**設計上の位置づけ:** orphan 化された objspace は global GC (STW、全 Ractor 停止) によって *のみ* walk される。だからこそ引き渡しのコメントは「global-GC バリアのもとでのみ反復されるので、呼び出し元が保持する VM ロック以上の追加のロックはここでは不要である」と述べている。`malloc` (Ruby のアロケータではない) は意図的であり —— これはteardown の途中で走るため、GC を発火させてはならない。

**レビュアー向けの注意点:**
- orphan は決して取り除かれず、その死んでいない殻は永遠に残り続ける (「完全に空の orphan を解放するのは将来の最適化である」)。shareable を保持する多数の Ractor を生成し殺す長命なプログラムは objspace の殻を蓄積する。*オブジェクト* は回収されるが、リストは単調に成長する。既知のリークとして指摘する価値がある。
- `rb_gc_foreach_objspace`、`rb_objspace_each_objects_all_ractors` (`gc.c:4170-4189`)、`rb_gc_conservative_owner` (`gc.c:3389-3413`)、`rb_gc_ractor_newobj_cache_foreach_for_objspace` (`gc.c:351-365`) はいずれも *同じ* 3 部構成の walk (main / `ractor.set` / orphan リスト) を *同じ* バリア事前条件のもとで手書きで実装している。これらは正しいが重複している —— そのいずれか一つでバリアなしの誤用があれば、Ractor セットに対するデータレースとなる。すべての呼び出し元が STW パス上にあることを確認すること。

### 5.3 `rb_gc_object_in_current_objspace_p` と `rb_gc_conservative_owner`

`gc.c:3422-3427`
```c
bool rb_gc_object_in_current_objspace_p(VALUE obj) {
    if (SPECIAL_CONST_P(obj)) return true;
    return rb_gc_impl_pointer_to_heap_p(rb_gc_get_objspace(), (const void *)obj);
}
```
**何を/なぜ:** *バリアフリー* な「このオブジェクトは自分のヒープに存在するか?」というテストである。現在の objspace 自身のページセットのみを調べ、それは所有スレッド上では安定している —— したがって (全 objspace を walk し VM バリアを *必要とする* ) `rb_gc_conservative_owner` (`gc.c:3389-3413`) とは異なり、走行中の Ractor から呼び出しても安全である。これは Ractor の receive パスでの再マテリアライズの判断と、以下の keep-alive ヘルパの両方を支えている。**注意点:** 非 RLGC ビルドでのセマンティクスは「常に true」(単一 objspace) である —— 呼び出し元が `true` を「クロス objspace のアクションは不要」として扱っていることを確認すること。これはまさに receive パスが行っていることである (再マテリアライズを正しくスキップする)。

### 5.4 `rb_gc_mark_roots` の local-GC 分岐 (confinement の心臓部)

`gc.c:3460-3511`。この早期 return が confined マーキングの契約そのものである。
```c
if (objspace != vm->gc.objspace && !rlgc_global_gc_active) {
    rb_ractor_t *cr = rb_ec_ractor_ptr(ec);
    MARK_CHECKPOINT("local_ractor");
    rb_gc_mark_ractor_local_roots(cr);            // received msgs, local storage, std IO, this Ractor's threads
    MARK_CHECKPOINT("machine_context");
    mark_current_machine_context(ec);             // conservative stack of the GC-triggering thread
    ...keep-alives (Face D + trap)...
    return;                                        // <-- never reaches rb_vm_mark / global roots
}
```
**なぜ:** local GC は (a) main objspace ではなく、かつ (b) global GC ではない。それは *現在の Ractor の* 実行ルートと自身のマシンコンテキストのみをマークし、`rb_vm_mark(vm)`、`end_proc`、`global_tbl`、`vm->mark_object_ary` などに到達する *前に* return する。これは設計の核心的前提を符号化している。すなわち **VM のグローバルなルートは main objspace に存在し、main/global GC によって生き続ける** のであり、ワーカの confined GC はそれらをスキップしなければならない (別の objspace のルートを読んだり、たまたま所有している共有テーブルを解放したりすることが、この分岐全体が回避するために存在するバグクラスである)。`mark_current_machine_context(ec)` は *現在の* スレッドのスタックに限定されている —— Ractor のその他のスレッドは `rb_gc_mark_ractor_local_roots` (`ractor.c:274` で定義され、これがスレッドごとに `rb_gc_mark_thread_roots` も呼び出す) を介して構造的に到達される。

**keep-alive リスト —— 「VM のグローバルは main に存在する」の例外 (Face D + trap):** `gc.c:3493-3506`
```c
gc_keepalive_vm_global_if_local(id2ref_value);
gc_keepalive_vm_global_if_local(rb_gc_vm_global_fstring_table());
gc_keepalive_vm_global_if_local(rb_gc_vm_global_symbol_set());
gc_keepalive_vm_global_if_local(rb_gc_vm_global_symbol_ids());
for (int i = 0; i < RUBY_NSIG; i++) {
    gc_keepalive_vm_global_if_local(vm->trap_list.cmd[i]);
}
```
ヘルパは以下である (`gc.c:3416-3421`)。
```c
static void gc_keepalive_vm_global_if_local(VALUE obj) {
    if (obj && rb_gc_object_in_current_objspace_p(obj)) rb_gc_mark(obj);
}
```
**なぜこれら特定のオブジェクトなのか:** 「VM のグローバルは main に存在する」という前提には *例外* がある —— WB-protected ではなく、*リサイズ/負荷率の閾値を跨いだ Ractor へ再アロケートされる* テーブル群である。
- `id2ref_value` —— `_id2ref` の st_table ラッパであり、最初に `_id2ref` を呼んだ objspace にアロケートされる。
- fstring の重複排除テーブルと symbol set/ids —— リサイズによって grow を引き起こした Ractor へ再配置される `concurrent_set`/配列のバッキングである。
- `vm->trap_list.cmd[]` (trap の例外): `Signal.trap` は main Ractor 以外でも許可されている。Proc ハンドラは shareable (ピン留め) にされるが、**String** のコマンドハンドラは VM グローバルのスロットを通じて *のみ* 到達可能な、ありふれた this-objspace の String である。

global ルートのマークは早期の `return` によってスキップされたため、これらのうち *この* ワーカの objspace に物理的に存在するものは、インストールされたまま、かつ他の Ractor によって並行使用されている最中に sweep されてしまう → 「st_insert で SEGV」、「Object ID は見えるが `_id2ref` テーブルには無い」、あるいはシグナル配送が解放済みの String を eval する、といった事態になる。ヘルパは *local の場合にのみ* (`rb_gc_object_in_current_objspace_p`) それをマークする。foreign なコピーは、その真の所有者 / global GC に委ねられる。

**レビュアー向けの注意点:**
- この keep-alive リストは *既知の* 再配置されうる VM グローバルの denylist である —— これまでに見つかった confinement 漏れの face の集合とちょうど一致する。オープンなタスクリスト (`end_procs`、`vm->coverages`、`mark_object_ary`、スレッド変数ホストの Face) が示すように、このリストは **構造上 incomplete** である。すなわち、要素がワーカの objspace に着地しうる他のあらゆる非 WB-protected な VM グローバルのコンテナは、この分岐が *捕捉しない* 潜在的な UAF である。レビューの際は「このリストに無く、ワーカが所有しうる VM グローバルのルートはあるか?」を常に問うべき問いとして扱うこと。
- `vm->global_hooks` はここで *意図的に* マークされていない (`gc.c:3476-3483`): これは foreign な Ractor によってロックフリーに変更される (`hook_list_connect`) 共有リストであり、confined GC がそれを反復すると writer とレースする。これは STW の global GC に委ねられている。将来の変更が「親切心で」これを追加しないよう注意すること。
- `vm->trap_list.cmd[i]` の読み出しは並行する `Signal.trap` とレースするが、コメントはその読み出しが単一のアラインされたポインタ (アトミック) であることに依拠している —— サポート対象のプラットフォームでは正しいが、これは *非同期化* された読み出しである。アトミックなポインタロードを持たないプラットフォームへの移植性が範囲に入る場合は指摘すること。

### 5.5 `id2ref_tbl` のロック + keep-alive (ワーカによって sweep される VM グローバルテーブル)

`_id2ref` テーブルは `global_object_list` に登録されており、これはロックフリーな local GC のルートが *マークしない* —— したがって、VM-lock で保護された inserter/reader が走っている最中に、そのラッパがワーカの GC によって sweep されうる。あらゆるアクセスは、いまや **non-barrier** ロックでガードされ、グローバルポインタを再チェックする。

`gc.c:2192-2204` (`id2ref_tbl_free`)
```c
RB_VM_LOCKING_NO_BARRIER() {
    id2ref_tbl = NULL; // clear under the lock so inserters re-checking inside the lock skip it
    st_free_table(table);
}
```
`gc.c:2278-2280` (`object_id0`) と `gc.c:2144-2146` (`rb_gc_obj_id_moved`) はいずれも *ロック内での再チェック* を追加する。
```c
RB_VM_LOCKING() { if (id2ref_tbl) st_insert(id2ref_tbl, ...); }   // re-check under lock
```
`gc.c:2420-2428` (`obj_free_object_id`) は `st_delete` を non-barrier ロックの下に移し、結果を捕捉する。
```c
int id2ref_deleted;
RB_VM_LOCKING_NO_BARRIER() { id2ref_deleted = st_delete(id2ref_tbl, (st_data_t *)&obj_id, NULL); }
if (!id2ref_deleted) { ... }
```
**なぜ `NO_BARRIER` なのか:** `id2ref_tbl_free` と `obj_free_object_id` は *GC sweep の内部* で走るが、これは **safepoint ではない**。バリアアウェアな `RB_VM_LOCKING` は、もし global GC が保留中であれば、*sweep の途中でバリアに合流* してしまい、objspace を半分回収された状態のまま global GC に walk させてしまう。non-barrier ロックは、バリアに合流することなく、inserter/reader および他の local GC との相互排他 (すべて `vm->ractor.sync` 上で直列化される) を依然として提供する。**この double-check パターンは必須であり、間違えやすい:** free はロックの下で `id2ref_tbl = NULL` をクリアするので、すべての inserter はロック取得 *後に* `id2ref_tbl` を再テストしなければならない (外側の `RB_UNLIKELY(id2ref_tbl)` の高速チェックとロック内本体との間の TOCTOU)。**注意点:** *新規* の `id2ref_tbl` アクセスはすべて、この正確な「ロック + 非 NULL 再チェック」の形に従わなければならない。その外でのむき出しの `st_insert` はレースを再導入する。

### 5.6 `gc_mark_generic_ivar_sync` (Family III の隣接領域 —— generic ivar)

`gc.c:3651-3670`
```c
static inline void gc_mark_generic_ivar_sync(VALUE obj) {
#if RACTOR_LOCAL_GC
    if (rlgc_has_local && !rlgc_global_gc_active) {
        RB_VM_LOCKING_NO_BARRIER() { rb_mark_generic_ivar(obj); }
        return;
    }
#endif
    rb_mark_generic_ivar(obj);
}
```
いまや、むき出しの `rb_mark_generic_ivar` の代わりに `rb_gc_mark_children` と `rb_gc_move_obj_during_marking` から呼び出される (`gc.c:3688`, `gc.c:3724`)。**なぜ:** writer は VM ロックの下で VM グローバルの `generic_fields_tbl_` を変更する (これは共有 st_table を rehash/realloc しうる)。confined な local GC は STW ロック *なしで*、それらの writer と並行してマークするため、そのロックフリーな `st_lookup` は writer が移動中のバケットを読みうる → 解放済みのスロットをマークする torn read となる。non-barrier ロックは、このルックアップを writer および他の local GC と相互排他にする。**なぜ non-barrier なのか (5.5 と同じ理屈):** バリアアウェアなロックは保留中の global-GC バリアに *マークの途中で* 合流してしまい、その `imemo_fields` がすでに sweep された古い `generic_fields_tbl` のエントリを残す → 「mark T_NONE」となる。local objspace が存在しないとき (単一 Ractor / MMTk: `rlgc_has_local` が false) と global GC の最中 (ロックはすでに保持されており、writer は走らない) には、正しくスキップされる。**注意点:** これは *generic ivar テーブル* の読み出しをガードするが、オープンな Family-III の remembered set/WB の face (タスク #17/#18) とは直交している —— これがクロス objspace の世代別ライトバリアの正しさをカバーすると仮定してはならない。これはテーブルの読み出しを直列化するのみである。

### 5.7 `RB_GC_MARK_OR_TRAVERSE` —— foreign な `mark_func_data` の gating

`gc.c:2975-2986`
```c
void *objspace = rb_gc_get_objspace();           // was: vm->gc.objspace
if (LIKELY(vm->gc.mark_func_data == NULL) || rb_gc_impl_during_gc_p(objspace)) {
    GC_ASSERT(rb_gc_impl_during_gc_p(objspace));
    (func)(objspace, (obj_or_ptr));
}
```
**なぜ:** `vm->gc.mark_func_data` はマーキングをコールバック (`ObjectSpace.reachable_objects_from`、Ractor の shareability チェック) へリダイレクトするものであり、**VM グローバル** である。ロックフリーな Ractor ごとの GC のもとでは、Ractor A が (GC 中 *でない* ときに) これをセットするのが、Ractor B の実際の local GC と並行に起こりうる —— これは B のマーキングを foreign なコールバックへ乗っ取ってしまう (そしてそのコールバックは *アロケートする* → 「GC 中のアロケーション」/破損となる)。この修正は `during_gc_p(objspace)` で gate する。すなわち、実際の GC は常に自身の objspace に `during_gc` がセットされているので、foreign な `mark_func_data` に関わらず実際にマークする。ホットパス (`mark_func_data == NULL`) は依然として短絡するので、`during_gc_p` はリダイレクトパスでのみ評価される。objspace のソースも `rb_gc_get_objspace()` に変更され、`during_gc` チェックが *正しい* (現在の Ractor の) objspace に対して読まれるようになっている点に注意。

### 5.8 Newobj キャッシュと objspace のライフサイクルヘルパ (脇役)

これらはアロケーション/teardown を「現在のスレッドの objspace」基準ではなく objspace 基準で正しくする。
- `rb_gc_ractor_cache_alloc` / `rb_gc_ractor_cache_free` (`gc.c:3994-4006`) は、いまや Ractor の newobj キャッシュを、teardown スレッド上でたまたま現在となっている objspace ではなく `ractor->local_gc_objspace` (その *自身の* ヒープ) に対してアロケート/解放する —— さもないと freelist のスロットが誤ったヒープへ返される。**注意点:** `rb_gc_ractor_cache_free` のシグネチャが、正しい objspace を回復できるよう `(void *cache)` から `(rb_ractor_t *r)` へ変更された。すべての呼び出し元が更新されたか確認すること。
- `rb_gc_ractor_newobj_current_cache_foreach` (`gc.c:280-288`) は local GC の最中に *現在の* Ractor のキャッシュ *のみ* をフラッシュする —— すべてのキャッシュを反復すると他の Ractor の freelist を誤って扱う (それらは他の objspace を指している)。その兄弟である `..._for_objspace` (`gc.c:351-365`) は global-GC 版であり、各キャッシュを *それが属する objspace へ* フラッシュする。
- `rb_gc_objspace_alloc_local` / `rb_gc_objspace_free_local` / `rb_gc_ractor_cache_alloc_on_main` / `rb_gc_rlgc_enabled` (`gc.c:4007-4047`) はライフサイクルと `RUBY_RACTOR_LOCAL_GC` 環境トグルである。5.2 の設計コメントが `rb_gc_objspace_free_local` を「未使用」と述べている点に注意 (orphan は決して解放されない) —— これは存在するが orphan パスが殻を生かし続けるので、実際にこれを呼び出すパスがあるかどうか確認すること (デッドコードか将来の用途か)。

### 5.9 スライス外のクロスリファレンス (`gc.c` 内にはない)

タスクの概要は `rb_gc_mark_thread_roots` と root-fiber の保存コンテキスト (`cont_mark`) のマーキングに言及している。これらは **`gc.c` 内にはない** —— `rb_gc_mark_thread_roots` は `vm.c:3851` で定義され、`rb_gc_mark_ractor_local_roots` (本セクションの `rb_gc_mark_roots` 分岐が `gc.c:3470` で呼び出す local-roots のエントリポイント) の内部から `ractor.c:286` で呼び出される。`vm.c`/`ractor.c`/`cont.c` をカバーするコンパニオンセクションが root-fiber の保存コンテキストのマーキングを詳述すべきである。`gc.c` 側から検証すべきことは、local-GC 分岐における `rb_gc_mark_ractor_local_roots(cr)` への単一の呼び出しが Ractor のスレッド/ファイバへの *唯一の* 構造的エントリであること、そしてスレッドラッパオブジェクト (`th->self`) が foreign (main の中) に存在し confined マークによってスキップされうるため、それが現在のスレッドのマシンスタックを `mark_current_machine_context(ec)` を介して別途マークすること、のみである。

---

## 6. メッセージの所有権: 受信時のマテリアライズと in-flight ピン

*コピー*または*ムーブ*される Ractor メッセージ（shareable な `ref` ではない）は、RLGC にとって最も難しいケースである。なぜなら、本設計では各 Ractor が別々のヒープを所有しており、confined な local GC は他の objspace 内のオブジェクトを読んだり解放したりして**はならない**にもかかわらず、コピーされたペイロードは本質的に新しい*unshareable*なオブジェクトであり、ある objspace に一時的に存在しながら別の objspace から参照されるからである。§3.10（`RACTOR_LOCAL_GC_DESIGN.md` 6.x）の**所有権のトリレンマ**は次のとおりである。コピー/ムーブのペイロード `v` は

1. **送信側の objspace に割り当てられる**（`ractor_copy`/`ractor_move` は送信側スレッドで実行される）が、
2. **受信側のバスケットキューからのみ**到達可能である — これは*両方*の local GC がスキップする objspace 間のエッジである（送信側の local GC は foreign な受信側のキューを決して走査しないし、受信側の local GC は送信側の objspace へ読み込まない）。そして
3. その唯一の本当の keep-alive（ページごとの `shared_bits` remset）は、すべてのグローバル STW GC によって shareable→unshareable エッジのみから**ゼロから再構築される** — そして in-flight なコピーはそのようなエッジではない。

したがって `v` は、まだキューに積まれている間に送信側の次の local GC によって解放され得る（dangling なバスケット → "mark T_NONE"/UAF）。また、たとえピンされていても、グローバル GC はそのピンを落としてしまう。このスライスは、2 つのメカニズムでトリレンマを解決する。すなわち、**in-flight の間ピンする**（shared-bits remset で、グローバル GC をまたいで再スタンプする）ことと、**受信時にマテリアライズする**（受信側自身のヒープへ再クローンし、所有権を物理的な位置に一致させる）ことである。新しいフィールド `rb_ractor_sync::in_flight_materializing` は、キュー走査ではカバーできない唯一の窓を塞ぐ。

### 6.1 送信時に送信側 objspace でペイロードをピンする

`ractor_sync.c:834`（`ractor_basket_new` 内）

```c
    if (type == basket_type_copy || type == basket_type_move) {
        rb_gc_pin_in_flight_message(v);
    }
```

**何を。** `ractor_prepare_payload` がコピー/ムーブされたペイロード `v` を生成した直後に、それを送信側 objspace の `shared_bits` remset にマークする。`rb_gc_pin_in_flight_message`（`gc.c:3645`）は、ページごとの shared ビットを*アトミックに*セットし、ページに `has_shared_objects` フラグを立てる。

```c
void rb_gc_pin_in_flight_message(VALUE obj) {
    if (!rlgc_has_local) return;
    if (SPECIAL_CONST_P(obj) || RB_OBJ_SHAREABLE_P(obj)) return;
    MARK_IN_BITMAP_ATOMIC(GET_HEAP_SHARED_BITS(obj), obj); // sender mutator sets concurrently with other Ractors
    GET_HEAP_PAGE(obj)->flags.has_shared_objects = TRUE;
}
```

**なぜ。** これがないと `v` は（foreign な）受信側キュー経由でしか到達できないため、送信側の objspace を*実際に*走査する送信側自身の local GC が、まだキューに積まれている間にそれを解放してしまう。shared-bits remset は、まさに local GC が「外部から参照されている unshareable オブジェクト」を判定するために参照するメカニズムであり、それを再利用することで `v` を自分の home objspace にピンする。

**どう組み合わさるか。** これは*home-objspace ピン*の側面である。これは、objspace 境界をまたいで参照される unshareable オブジェクトは `shared_bits` で追跡されなければならないという設計上の不変条件を反映している。送信側は自身のスレッド上で自身が作りたてのオブジェクトをピンするので、objspace 間のレースは存在しない（アトミックなセットが守るのは、同じビットマップワードに書き込む*他の* Ractor に対してのみ — これは TSan で発見された非アトミック RMW のクラスである）。

**注意点。** ピンは `MARK_IN_BITMAP_ATOMIC` を使う。素の `|=` だと、並行する送信側のもとで lost-update バグになる。これは `ractor_prepare_payload` がすでに shareable なオブジェクトに対して `basket_type_copy`→`basket_type_ref` に*ダウングレード*した*後の* `type` をキーにしている（`ractor_sync.c:818`）点に注意。したがって shareable なペイロードは正しくピンをスキップする（そもそも `rb_gc_pin_in_flight_message` は `RB_OBJ_SHAREABLE_P` で early-return する）。

### 6.2 キューに積まれたバスケットのピンをグローバル GC をまたいで再スタンプする

`ractor_sync.c:212`（`ractor_basket_mark`）

```c
    rb_gc_mark(b->p.v);
    /* ... a GLOBAL GC clears every shared bit up front and rebuilds the remset solely from
     * shareable->unshareable edges; an in-flight message ... is not such an edge, so its pin
     * would be lost. ... */
    if (!rb_gc_during_local_gc_p()) {
        rb_gc_pin_in_flight_message(b->p.v);
    }
```

**何を。** 受信側の `recv_queue`/ポートにまだ残っているすべてのバスケットは、`ractor_queue_mark`→`ractor_basket_mark` によって訪問される。マーク自体は元から存在していた。新しい行は in-flight ピンを*再適用*する — ただし `!rb_gc_during_local_gc_p()` のとき、すなわちグローバル STW GC の間だけである。

**なぜ。** 6.1 の側面のピンは、グローバル GC の冒頭での shared-bits クリアによって消され、再生成されない（`v` を指す shareable→unshareable エッジは存在しない）。グローバル GC は `v` を live としてマークする（`rb_gc_mark`）が、それが終わって送信側が再開すると、送信側の*次の local GC* は shared ビットのない `v` を見て、まだキューに積まれている間にそれを回収してしまう。グローバル STW パスの間に再スタンプすることで、ピンを復元し、グローバル GC 後の世界へ生き延びさせる。

**どう組み合わさるか / なぜこのガードか。** `rb_gc_during_local_gc_p()`（`gc.c:3620`）は `rlgc_has_local && !rlgc_global_gc_active` であり、**グローバル GC の間にまさに false** になる（そして非 RLGC ビルドでも false で、そこでは `rb_gc_pin_in_flight_message` は no-op である）。このガードは load-bearing である。すなわち、グローバル STW GC のみが*別の objspace*（送信側）のビットマップに書き込んでよい。なぜなら、すべての Ractor が停止しているため、その書き込みは何ともレースしないからである。*local* GC が foreign な objspace のビットマップに書き込むのは confinement 違反になるため、それは正しく抑制されている。

### 6.3 `in_flight_materializing` スロット — デキュー済みの窓をカバーする

`ractor_core.h:30`

```c
    // Ractor-local GC: a copy/move message currently being materialized (cloned) into this Ractor
    // by ractor_basket_accept. It has left the receiver queue, so the queue walk that re-pins
    // in-flight messages across a global GC (ractor_basket_mark) no longer covers it; ractor_sync_mark
    // re-pins this slot instead. 0 when not materializing. (RACTOR_LOCAL_GC_DESIGN.md 6.3)
    VALUE in_flight_materializing;
```

`ractor_sync.c:866`（`ractor_basket_accept`、受信パス）

```c
    ractor_basket_free(b);   // free the basket struct now (never the payload v); safe before a raise

    if ((type == basket_type_copy || type == basket_type_move) &&
        !rb_gc_object_in_current_objspace_p(v)) {
        rb_ractor_t *const cr = GET_RACTOR();
        const VALUE prev = cr->sync.in_flight_materializing;
        cr->sync.in_flight_materializing = v;
        v = ractor_copy(v);          // re-clone into the RECEIVER's objspace (runs on receiver thread)
        cr->sync.in_flight_materializing = prev;
    }
    if (exception) {
        rb_exc_raise(ractor_make_remote_exception(v, sender));
    }
    return v;
```

**何を — 受信時のマテリアライズ。** 受信側が、自身の objspace にまだ存在し**ない**コピー/ムーブのペイロードをデキューしたとき（`!rb_gc_object_in_current_objspace_p(v)`、`gc.c:3427` — 現在の objspace の安定したページ集合のみをチェックし、バリアは不要）、`ractor_copy(v)` を再実行する。これは*受信側*スレッドで走るため、ディープクローン（`rb_obj_traverse_replace`→`copy_enter`→`ractor_obj_clone`、`ractor.c:2134`）は受信側の lock-free な newobj パスを通じて割り当てを行い、結果として得られるグラフは物理的に受信側のヒープに存在する — これにより物理的な位置が所有権に一致する。`rb_gc_object_in_current_objspace_p` ガードにより、これは自己送信および非 RLGC の単一 objspace ビルド（そこでは常に true）では no-op になる。

**何を — スロット。** `ractor_copy` は*割り当てを行う*ため、クローンの途中でグローバル GC が発火し得る。その瞬間、`v` はすでに受信側キューを離れている（したがって 6.2 のキュー走査はもはやカバーしない）が、新しいクローンはまだ完了していない — `v` は GC がスキャンするどこからも到達できない。クローンの前に `v` を `cr->sync.in_flight_materializing` に publish し、その後にクリアすることで、`ractor_sync_mark` にそれをマークし再ピンする場所を与える。`prev` の save/restore により、あらゆる再入が許容される。

**なぜ両方の側面か。** 6.1/6.2 の側面は*キューに積まれた*メッセージを生かし続ける。6.3 は*まさに受信されている最中の*メッセージを生かし続ける。両者を合わせると、送信から完全にマテリアライズされた所有権までの、ペイロードの全寿命をカバーする。

### 6.4 `ractor_sync_mark`: スロットをマーク+再ピンし、foreign に変更されるキューをロックする

`ractor_sync.c:669`

```c
    rb_gc_mark(r->sync.in_flight_materializing);
    if (!rb_gc_during_local_gc_p()) {
        rb_gc_pin_in_flight_message(r->sync.in_flight_materializing);
    }

    const bool sync_lock = rb_gc_during_local_gc_p();
    if (sync_lock) rb_native_mutex_lock(&r->sync.lock);
    {
        if (r->sync.ports) {
            ractor_queue_mark(r->sync.recv_queue);
            st_foreach(r->sync.ports, ractor_mark_ports_i, 0);
        }
        ractor_mark_monitors(r);
    }
    if (sync_lock) rb_native_mutex_unlock(&r->sync.lock);
```

**何を（スロット）。** マテリアライズ用スロットに対して 6.2 をそのまま反映する。すなわち、常に `rb_gc_mark` し（`0`/`Qfalse` のスロットは無害にマークされる）、グローバル STW GC の間だけ送信側 objspace に再ピンする。`r` はこのフィールドを所有し、自身のスレッド上でのみ書き込むので、ここではレースなしで読まれる（`r` 自身の local GC か、あるいはすべての Ractor が停止したグローバル GC のいずれかによって読まれる）。

**何を（ロック）。** `recv_queue`/`ports`/`monitors` は**foreign** な Ractor によって変更される — 例えば送信側の `ractor_send_basket` は、ターゲットの Ractor ごとのミューテックス `r->sync.lock` のもとで `recv_queue` に `ccan_list_add_tail` する（`ractor_sync.c:1222`）。confined な*local* GC はこれらを lock-free に、かつそれらの送信側と並行してマークするため、splice の途中のリストノードや rehash 途中の `st_table` を観測し、half-linked/未初期化のバスケットをマークしてしまう可能性がある → "mark T_NONE"/SEGV。新しいコードは走査の周囲で**同じ** `r->sync.lock` を取得する。ただし `sync_lock` のとき（すなわち local GC の間だけ）である。

**どう組み合わさるか / 注意点。**
- ロックは **`RACTOR_LOCK` ではなく生の `rb_native_mutex_lock`** で取得される — `RACTOR_LOCK` は加えて `malloc_gc_disabled`/`locked_by` のブックキーピングをセットするが、これは GC の内部から触るのは誤りである。これは意図的で微妙な区別であり、レビュアーは生のネイティブロックのままであることを確認すべきである。
- **自己デッドロックはない。** `RACTOR_LOCK`（このロックを保持するミューテータが使う）は `malloc_gc_disabled` をセットするので、あるスレッドがすでに `r->sync.lock` を保持している間に GC が発火することは決してない — したがって GC が、すでに保持しているロックに再入することは決してない。
- **グローバル** STW GC の間はロックはスキップされる（`sync_lock` が false）。すべての Ractor が停止しており、送信側は走らず、ロックを取得しても無意味だからである（そしてグローバル GC はすでに VM バリアを保持している）。

### 6.5 初期化

`ractor_sync.c:747`（`ractor_sync_init`）

```c
    r->sync.recv_queue = ractor_queue_new();
    r->sync.in_flight_materializing = 0; // no copy/move message is being materialized yet
```

**何を/なぜ。** 新しいフィールドはゼロ初期化されるので、実際の `ractor_basket_accept` がペイロードを publish するまでは `ractor_sync_mark` は `0`（no-op）をマークする。些細だが必要である。これがないと、フィールドは未初期化のゴミを読み、`rb_gc_mark` が非オブジェクトをマークしかねない。

### 6.6 foreign な Ractor のファイバー/EC スキップ（なぜそもそも受信側が再クローンするのか）

受信時のマテリアライズ設計は、`rb_gc_local_gc_foreign_ractor_p`（`gc.c:3631`）に具現化された confinement ルールによって強制される。

```c
bool rb_gc_local_gc_foreign_ractor_p(const rb_ractor_t *owner) {
    if (!rb_gc_during_local_gc_p()) return false;
    return owner != rb_ec_ractor_ptr(rb_gc_get_ec());
}
```

local GC は、**foreign** な Ractor の実行中のエグゼキューション状態（そのスレッド/ファイバーの制御フレームとマシンスタック）を走査してはならない（それらは別の live なスレッド上で不安定 → 読み込みがレースする → SEGV）。その結果、confined な GC は*自身の* Ractor のルートにしか到達せず、objspace 間メッセージエッジの producer 側には決して到達しない — これこそが、ペイロードを境界をまたいで参照されたままにするのではなく、受信側の objspace に re-home しなければならない（6.3）理由である。これは `rb_gc_mark_ractor_local_roots`（`ractor.c`）の背後にある同じ confinement 原則であり、そこでは local mark がスレッドの*ラッパー*オブジェクト（`th->self`、これは main objspace に foreign に存在し得る）を意図的にスキップする一方、スレッド自身の objspace 内のマシン/VM スタックのルートを `rb_gc_mark_thread_roots` 経由で直接マークする。

**このスライス全体にわたるレビュアー向けの注意点。**
- すべての `rb_gc_pin_in_flight_message` の呼び出し箇所は、ヘルパー内部でビルド/locality（`rlgc_has_local`）によって、あるいは呼び出し箇所で `!rb_gc_during_local_gc_p()` によってゲートされている — *local* GC が *foreign* な objspace の shared ビットに書き込むパスがないことを確認すること。
- `in_flight_materializing` スロットは、割り当てを行う `ractor_copy` の**前に**セットし、その**後に**復元しなければならない。`prev` の save/restore こそが、ネストした/再入する受信を安全にしている — これを無条件の 0 クリアに「単純化」してはならない。
- `ractor_basket_free(b)` は、起こり得る `rb_exc_raise` の**前に**呼ばれるようになった（バスケット構造体は冒頭で解放されるので、raise がそれをリークさせることはない）。これはバスケットノードのみを解放し、ペイロード `v` は決して解放しない。後続のコードが `b` をデリファレンスしないことを確認すること。
- ピン/再ピンは正しさに不可欠だが*保守的*である。すなわち、オブジェクトをより長く生かすことしかしない。後続のグローバル GC は実際のエッジから `shared_bits` を再計算し、`v` が真に参照されなくなれば回収するので、恒久的なリークはない。

---

## 7. 周辺的な修正(サブシステムごと)

これらは RLGC モデルから派生する、サブシステムごとの confinement ミスおよび並行性の修正である。*confined* な local GC は自分自身の Ractor のルートだけをマークし、それ以外はすべて foreign-skip する。したがって、**親/メイン objspace のコンテナ、VM グローバルなテーブル、あるいは foreign オブジェクトのフィールドを経由してのみ到達可能な**オブジェクトは、その local GC からは見えず、生きているにもかかわらず sweep されてしまう。以下の各修正は、(a) そうしたオブジェクトを正しい objspace に re-home するか、(b) local GC から生かし続けるか、(c) lock-free な read/mutate のレースを塞ぐかのいずれかである。これらは Face B, D, G, G-2 と、スレッド/ファイバーのルートをマークする機構に対応する。

---

### 7.1 `rb_const_remove`: VM ロック下でのアトミックな lookup+削除 (Face B)

`variable.c:3648`

```c
VALUE
rb_const_remove(VALUE mod, ID id)
{
    VALUE val = Qnil;
    bool not_found = false;
    bool deprecated = false;

    rb_check_frozen(mod);

    RB_VM_LOCKING() {
        rb_const_entry_t *ce = rb_const_lookup(mod, id);
        if (!ce) { not_found = true; }
        else {
            deprecated = RB_CONST_DEPRECATED_P(ce);
            ...
            rb_clear_constant_cache_for_id(id);
            val = ce->value;
            if (UNDEF_P(val)) { autoload_delete(mod, id); val = Qnil; }
            if (ce != const_lookup(RCLASS_PRIME_CONST_TBL(mod), id)) { SIZED_FREE(ce); }
        }
    }

    if (not_found) { ... rb_name_err_raise(...); undefined_constant(...); }
    if (deprecated && rb_warning_category_enabled_p(...)) { rb_category_warn(...); }
    return val;
}
```

**何を.** lookup→delete→キャッシュクリア→free という一連のシーケンス全体を、単一の `RB_VM_LOCKING()` クリティカルセクションで囲むようにした。元のコードは `rb_const_lookup` をどのロックの*外*でも実行し、その後ロックなしで `ce` を変更し free していた。これまでインラインで実行されていた 2 つの処理結果が、**アンロック後まで遅延される**ようになった。not-found 時の `rb_name_err_raise`/`undefined_constant` と、deprecation 時の `rb_category_warn` である。これらはロック内で `not_found` / `deprecated` フラグに取り込まれ、ロック外で実際の処理が行われる。

**なぜ.** 定数テーブルは複数の Ractor から並行に変更される。*shareable* な値の `rb_const_set` はメイン Ractor 以外でも許可されており、それ自体が VM ロックされている(diff のコメントには "Mirrors `rb_const_set()`/`const_tbl_update()`" とある)。ロックなしの lookup を許すと、2 つの並行する remove が**同一の** `rb_const_entry_t` を取得して double-free してしまうし、remove が `const_set` とレースして free 済みメモリへ書き込ませてしまう。キャッシュ整合性の観点ではさらに深刻で、`rb_clear_constant_cache_for_id()` は id ごとのインラインキャッシュ `set_table` を(`set_table_foreach` で)walk するが、他の Ractor は定数キャッシュミス時に*ロック下でこのテーブルへ挿入する*。ロックなしで walk すると、並行する挿入の rehash が walk の足元で `entries[]` を再確保してしまい、ダングリングなインラインキャッシュポインタが残る。`autoload_delete()` も VM グローバルな `autoload_features` ハッシュを変更する。

**どう位置づけられるか.** これは典型的な Face-B の IC 寿命の修正である。定数キャッシュの `set_table` と const エントリは多数の Ractor から read/write される VM グローバルな状態なので、すべての変更を VM ロックでシリアライズしなければならず、これは既存の write パスと一致する。

**レビュアー向けの注意点.**
- この遅延は*必須*であって見た目の問題ではない。`rb_name_err_raise` と `rb_category_warn` は Ruby コードを実行しうる(raise する/カスタムの warner を呼ぶ)ため、`RB_VM_LOCKING()` を保持したまま実行してはならない(再入/デッドロック)。ロック内でフラグが立つ前に raise しうるものが何もないことを確認すること。
- `val` のデフォルトは `Qnil` で、意味を持つのは `!not_found` のときだけである点に注意。not-found のブランチは決して正常に return しない(常に raise する)ため、ロック後の `return val` に到達するのは成功時のみである。
- autoload-features ハッシュのレース自体はここでは**塞がれていない**(オープン項目として追跡中。lock-ordering の設計が必要)。この修正は const パスの残りが使うのと同じ VM ロックを取るだけである。

---

### 7.2 `rb_free_generic_ivar`: sweep 中の non-barrier ロック

`variable.c:1339`

```c
/* NON-BARRIER: this runs during a (possibly Ractor-local, lock-free) GC sweep,
 * which is not at a safepoint. A barrier-aware lock here could join a pending
 * global-GC barrier mid-sweep, leaving the objspace half-swept for the global GC to
 * mark. The non-barrier lock still serializes with concurrent table accessors. */
RB_VM_LOCKING_NO_BARRIER() {
    if (!st_delete(generic_fields_tbl_no_ractor_check(), &key, &value)) {
        rb_bug("Object is missing entry in generic_fields_tbl");
    }
}
```

**何を.** VM グローバルな `generic_fields_tbl` からの `st_delete` を囲むロックを `RB_VM_LOCKING()` → `RB_VM_LOCKING_NO_BARRIER()` に変更した。

**なぜ.** この削除は*sweep*中に発生するが、RLGC では sweep はどの safepoint の外でも動く lock-free な local GC である。barrier-aware なロック(`RB_VM_LOCKING`)は、取得時に*pending な global-GC barrier に参加*しうる。つまり sweep 中の Ractor が barrier で sweep の途中で止まり、その後 global GC が中途半端に sweep された objspace(一部のオブジェクトは既に free 済み、一部はそうでない)をマークしてしまう。non-barrier の変種は、並行する `generic_fields_tbl` のアクセサとは依然として相互排他するが、barrier に対しては決して譲歩しない。

**どう位置づけられるか.** これは RLGC の作業が `gc.c` で(local GC が mark/sweep 中に触れるあらゆる VM グローバル構造に対して `RB_VM_LOCKING_NO_BARRIER()` を gc.c:2144/2201/2425/3668 で)適用しているのと同じパターンである。メモリのノートにはこれが確立されたルールとして記録されている。confined な GC は writer とはシリアライズしなければならないが、barrier でブロックしてはならない。

**レビュアー向けの注意点.** 正しさは `RB_VM_LOCKING_NO_BARRIER` が本当に barrier に*参加しない*ことに依存している。もしこのマクロのセマンティクスが変われば、これは sweep の途中の STW ハザードになる。エントリ欠落時の `rb_bug` は変更されておらず、どこか別の場所でロックが取り損なわれてテーブルが壊れた場合のカナリアとなる。

---

### 7.3 シンボル・文字列の VM グローバルテーブルのアクセサ + keep-alive (Face D, part 2)

`internal/symbol.h:21`, `symbol.c:445`, `string.c:572`

```c
/* symbol.c */
VALUE rb_gc_vm_global_symbol_set(void) { return ruby_global_symbols.sym_set; }
VALUE rb_gc_vm_global_symbol_ids(void) { return ruby_global_symbols.ids; }

/* string.c */
VALUE rb_gc_vm_global_fstring_table(void) { return fstring_table_obj; }
```

**何を.** VM グローバルな dedup テーブルを公開する 3 つの自明なアクセサである。シンボルの `str->sym` の `concurrent_set`(`sym_set`)、`serial->sym` の配列(`ids`)、そして frozen-string の dedup `concurrent_set`(`fstring_table_obj`)である。シンボル用の 2 つのプロトタイプは `internal/symbol.h` に追加され、fstring 用のものは `gc.c` から見える場所に既に宣言されている。

**なぜ / どう位置づけられるか.** これらのバックストアは **WB-protected ではなく**、resize は backing を*ロードファクタを超えたいずれの Ractor*の objspace へも再確保しうる。つまり非メインワーカーの objspace である。confined パスでは global-roots のマークがスキップされるため、何もしなければそのワーカーの local GC は、他の Ractor が並行して使っているテーブルを sweep してしまう。そのため `gc.c` の confined な `rb_gc_mark_roots` は、return する前に次を呼ぶ。

```c
gc_keepalive_vm_global_if_local(id2ref_value);
gc_keepalive_vm_global_if_local(rb_gc_vm_global_fstring_table());
gc_keepalive_vm_global_if_local(rb_gc_vm_global_symbol_set());
gc_keepalive_vm_global_if_local(rb_gc_vm_global_symbol_ids());
```

ここで `gc_keepalive_vm_global_if_local` は、オブジェクトが**現在の objspace に存在する場合にのみ**(`rb_gc_object_in_current_objspace_p`)それをマークする。したがって各 Ractor は、re-home されたテーブルのうち*自分自身の*コピーを生かし続け、foreign なものはその所有者 / global GC に委ねる。これは Face D の後半部分である(前半は元々の VM グローバル concurrent_set の keep-alive)。

**レビュアー向けの注意点.**
- これらのアクセサは可変な VM グローバル状態を値として(`VALUE` として)公開する。これらは GC 用の read-only なスナップショットであり、所有パスの外でテーブルを*変更する*ために使ってはならない。
- この keep-alive は*粗い*修正である。個々のエントリではなく backing の配列/set オブジェクト全体を pin する。これは意図的である(エントリは別途 pin される。7.4 を参照)が、レビュアーは*内容*が独立して root されていることを確認すべきである。テーブルオブジェクトが生きているだけでは、confined GC 下でその unshareable なエントリを生かし続けることにはそれ自体ならない。

---

### 7.4 シンボルの id-entry バケットを shareable としてマーク (Face D, part 2)

`symbol.c:281`

```c
rb_darray_make(&entries, ID_ENTRY_UNIT);
id_entry_list = TypedData_Wrap_Struct(0, &sym_id_entry_list_type, entries);
/* ... a worker's confined local GC would not mark it and would sweep it -- yet it holds
 * permanent (immortal-symbol) state shared VM-wide. Mark it shareable so the local-GC sweep
 * pins it; the global GC reclaims it via ids normally. */
RB_OBJ_SET_SHAREABLE(id_entry_list);
rb_ary_store(ids, (long)idx, id_entry_list);
```

**何を.** 新たに確保された各 id-entry バケット(`ID_ENTRY_UNIT` 個のスロットを持つ `darray` を保持する `TypedData` ラッパー)に、生成直後に `RB_OBJ_SET_SHAREABLE` フラグを立てる。

**なぜ.** バケットは**現在の Ractor の** objspace で確保される(そのシリアル範囲のシンボルを最初に intern した者)が、そこへ到達できるのは**メイン** objspace に存在する `symbols->ids` を経由してのみである。ワーカーの confined な local GC は `ids`(foreign)も、推移的にバケットもマークしない。したがって、VM 全体で使われる permanent な immortal-symbol 状態を保持する構造を sweep してしまう。shareable フラグによって、**sweep ガード**がそれを自分のホーム objspace で pin する(local GC は決して shareable を free しない)一方で、global GC は依然として `ids` 経由で通常どおり回収する。コメントによれば、これは shareable なシンボルと frozen string しか保持しないので、shareable とフラグを立てるのは健全である。

**どう位置づけられるか.** これはコメントが shape edge テーブルや `rb_managed_id_table_create` について相互参照している、shareable を sweep-pin として使う同じトリックである。これは 7.3 の**テーブル全体**の keep-alive に対する**エントリごと**の補完である。7.3 は re-home されたときに `ids`/`sym_set` を生かし、7.4 はどのワーカーが確保したかにかかわらず個々のバケットを生かす。

**レビュアー向けの注意点.**
- 正しさは、バケットが shareable な内容(immortal シンボル + frozen string)*のみ*を格納するという不変条件に依存する。もし非 shareable な VALUE が shareable フラグの付いたコンテナへ挿入されることがあれば、それは shareability の不変条件に違反する。`set_id_entry` の呼び出し元が shareable なシンボル/fstring だけを格納していることを検証すること。
- これは新しいバケットすべての*確保*パスにあり、メイン Ractor だけではない。それが狙いだが、これはシングル Ractor モードでもフラグが無条件に立てられることを意味する(無害で、単に no-op の pin になるだけ)。

---

### 7.5 スレッドのメインスレッドコンテナの re-home: 割り込みキューとマスクスタック (Face G)、`ec->storage` (Face G-2)

`thread.c:687`

```c
if (th->invoke_type == thread_invoke_type_ractor_proc) {
    VALUE q = rb_ary_dup(th->pending_interrupt_queue);
    RBASIC_CLEAR_CLASS(q);
    th->pending_interrupt_queue = q;
    VALUE m = rb_ary_dup(th->pending_interrupt_mask_stack);
    RBASIC_CLEAR_CLASS(m);
    th->pending_interrupt_mask_stack = m;
    /* fiber-storage Hash inherited from the parent by rb_fiber_inherit_storage() */
    if (!NIL_P(th->ec->storage)) {
        th->ec->storage = rb_obj_dup(th->ec->storage);
    }
}
```

**何を.** `thread_start_func_2` の早い段階で、つまり*この Ractor 自身の objspace の中で実行中*になった時点で、新しい Ractor メインスレッドが、継承した 3 つのコンテナをその場で re-dup する。pending-interrupt キュー、割り込みマスクスタック(Face G)、そして fiber-storage Hash `ec->storage`(Face G-2)である。`invoke_type == thread_invoke_type_ractor_proc` でガードされており、真の Ractor-proc スレッドだけがこのコストを払う。通常のスレッドは spawn 元の objspace を共有するため何も必要としない。

**なぜ.** `thread_create_core()` は `pending_interrupt_queue` / `pending_interrupt_mask_stack` を、*この Ractor の objspace がまだ存在しないうちに*(それは `rb_ractor_living_threads_insert` によって生成される)、**spawn する(親)Ractor の**スレッド上で確保する。したがってこれらのコンテナは物理的には**親**の objspace に存在する。その後、新しいスレッドは**自分自身の**(この objspace の、非 shareable な)オブジェクトをそこへ格納する。`Thread.handle_interrupt` はマスクのハッシュをマスクスタックへ push し、`Fiber[]=` / `storage=` は継承した fiber-storage Hash へ書き込む。*この* Ractor の confined な local GC は親 objspace のコンテナを foreign-skip するため、それを経由してのみ到達可能なこの objspace のオブジェクトには決して到達しない → それらは生きているのに sweep される → 割り込み配送時や `Fiber[]` 読み出し時に UAF となる。ここで、この objspace で re-dup すると、コンテナが再配置されて local GC がそれを所有しマークするようになる。一方 `rb_ary_dup`/`rb_obj_dup` は継承した内容を保持する。

**どう位置づけられるか.** これは*re-home*による典型的な Family-I の confinement ミスの治療である。local GC に foreign ポインタを追わせようとするのではなく、その内容をマークしなければならない GC を持つ objspace へコンテナを移動させる。

**レビュアー向けの注意点.**
- `RBASIC_CLEAR_CLASS(q)` / `RBASIC_CLEAR_CLASS(m)` は意図的である。これらは class を持たないままでなければならない内部配列であり(元のものがそうだったように)、そうしないと `rb_ary_dup` が class を持ち込んでしまう。元のものも class-less であって挙動が同一であることを確認すること。
- `ec->storage` は `rb_obj_dup`(Hash)を使い、`!NIL_P` でガードされている。fiber storage が継承されなかった場合(`rb_fiber_inherit_storage`)、storage Hash は nil でありうる。これが**シャローな** dup であることに注意。storage Hash の*内容*は依然として継承されたままのものであり、正しさはそれらの内容が shareable であること(継承された storage は shareable)に依存しているので、それらは re-home を必要としない。
- タイミングが重要である。これはその上の `RB_VM_UNLOCK()` ブロックの*後*だが、スレッドが何らかのユーザー処理を行う前に実行されるので、まだどの `handle_interrupt`/`Fiber[]=` も*古い*コンテナを埋めることはできていない。dup は手付かずの継承された状態を捉える。もしこのブロックがこれより後ろに移動すれば、書き込みを失う可能性がある。
- メモリのノートは*関連する*未解決のケースを指摘している。`thread_variable_set` の locals Hash は親 objspace の `Thread`(`th->self`)の ivar であり、ここでは**カバーされていない**。レビュアーは、すべてのスレッドローカルなコンテナがこのブロックで re-home されると仮定すべきではない。

---

### 7.6 `vm.c`: confinement のアサーション + EC マークでの gen-fields キャッシュの強いルート

`vm.c:3700` および `vm.c:3768`

```c
/* Ractor-local GC invariant: a local GC must only ever walk an EC belonging to its OWN Ractor. */
VM_ASSERT(ec->thread_ptr == NULL || !rb_gc_local_gc_foreign_ractor_p(ec->thread_ptr->ractor));
...
rb_gc_mark_movable(ec->gen_fields_cache.obj);
rb_gc_mark_movable(ec->gen_fields_cache.fields_obj);
```

**何を.** `rb_execution_context_mark` への 2 つの追加。第一に、マークされている EC が foreign な(並行して実行中の)Ractor の EC で**ない**ことのアサーション。`rb_gc_local_gc_foreign_ractor_p` は local GC 中に所有者が他の Ractor である場合に限り true を返す。第二に、generic-ivar の高速パスのキャッシュスロット `{obj, fields_obj}` を**強い movable ルート**としてマークするようにした。

**なぜ(アサーション).** foreign な EC を walk すると、その生きた制御フレームやマシンスタックをレースして → SEGV になる。呼び出し元(`cont_mark`、Ractor ごとの root パス)は foreign な EC を*スキップするはず*である。この `VM_ASSERT` は、それを忘れたパスを捕捉する。`ec->thread_ptr == NULL` の短絡は、まだスレッドにアタッチされていない EC をカバーする。

**なぜ(gen-fields キャッシュ).** キャッシュされた `fields_obj`(`imemo_fields`)は、*この* EC と `generic_fields_tbl` からのみ参照される。これは真に**強い**参照であって weak ではない。もしマークされなければ、生きた EC がまだ保持しているのに sweep がそれを free しうるし、後の `rb_mark_generic_ivar` が free 済み(T_NONE)の `imemo_fields` をマークしてしまう。diff のコメントは、これを並行な lock-free local GC が動くようになって一度現れた flaky なクラッシュとして記録している。*生きた* EC のキャッシュは決して weak-clear されなかった(weak-clear されるのは cont/fiber に*保存された* ec だけ)。コストはせいぜい GC 1 サイクル分のフロートで、キャッシュが次に上書きされたときに解放される。compaction パスは既にこれらのスロットを movable として扱っているので、`rb_gc_mark_movable` が対応するマーカーである。

**どう位置づけられるか.** Family III / generic-ivar の正しさである。gen-fields キャッシュは EC 自身のルートの一部なので、EC マークに属し、confined な local パス(自分の EC)と global パスの両方から到達される。

**レビュアー向けの注意点.**
- 2 つのキャッシュスロットは、同じ関数の上方にある `ec->gen_fields_cache` の compaction 更新と整合させるため、**movable** としてマークしなければならない(pin ではない)。pin すると compaction が同期しなくなる。なお RLGC 下では compaction は無効化されているので、movable マークは保守的/将来互換な選択である。
- このアサーションは `VM_ASSERT`(デバッグビルドのみ)である。リリースビルドでは foreign-skip の忘れは潜在的なレースになり、クラッシュにはならない。したがって*呼び出し元*の foreign ガードは依然として要となる。

---

### 7.7 `vm.c`: `rb_gc_mark_thread_roots` — confined GC 向けのスレッド/ルートファイバーの直接マーク

`vm.c:3851`

```c
void
rb_gc_mark_thread_roots(rb_thread_t *th)
{
    thread_mark((void *)th);
    if (th->ec) rb_execution_context_mark(th->ec);

    if (th->ec && th->root_fiber && th->root_fiber != th->ec->fiber_ptr) {
        rb_gc_mark_fiber_saved_context(th->root_fiber);
    }
}
```

**何を.** スレッドのルートを**直接**マークする新しいエントリポイント(`ractor.c` で宣言され、`ractor.c:286` から呼ばれる)と、前方宣言 `void rb_gc_mark_fiber_saved_context(rb_fiber_t *fib);`(`cont.c:1286` で `cont_mark(&fiber->cont)` の薄いラッパーとして定義)である。

**なぜ.** これは、**ラッパーオブジェクトがメイン/親 objspace に存在する** Ractor のスレッド/ファイバーに対する、2 層の confinement ミスを塞ぐ。

1. `rb_thread_t` のラッパー `th->self` はメイン objspace に存在しうる(この Ractor の local objspace にとって foreign)。したがって local マークは `th->self` をスキップし、`thread_mark` は決して実行されず、*この* objspace に存在するスレッドのルートに到達しない。`thread_mark((void*)th)` を直接呼ぶことでこれが修正される。
2. `thread_mark` が EC の VM スタックに到達するのは**ファイバーラッパー**(`rb_fiber_mark_self`)を経由してのみである。そのラッパーもまた foreign でスキップされうる。そこで追加で、実行中の `th->ec` を直接マークする。そのスタックは Ractor の生きたローカル変数を保持している。
3. **ルートファイバーの**ラッパーは `Ractor.new` の際に*親*スレッド上で生成されるので、親(例えばメイン)objspace に存在し foreign-skip される。*非ルート*のファイバーが実行中のとき、ルートファイバーの*保存された*スタック(この Ractor のトップレベルローカルを保持し、そのファイバーグラフ全体を再 root する)はマークされないまま残る。すると local GC がオブジェクトを free し、後の global GC がそれをマークしてしまう(「mark T_NONE」、親 fiber/Fiber)。`rb_gc_mark_fiber_saved_context(th->root_fiber)` はその suspend された保存コンテキストを直接マークする。

**どう位置づけられるか.** これは Face G のより広い confinement の話のスレッド/ファイバー側であり、メモリのノートにある「mark T_NONE parent fiber」クラッシュファミリーに対する要である。これは保存 EC 側の `cont.c:1161` の foreign ガードのロジックを反映している。

**レビュアー向けの注意点.**
- `th->root_fiber != th->ec->fiber_ptr` のガードは必須である。もしルートファイバーが*まさに*実行中のファイバーであるなら、その**保存された**コンテキストは*古い*(生きた状態は `th->ec` にあり、項目 2 で既にマーク済み)。古い保存コンテキストをマークすると、ゴミをマークしたり二重にカバーしたりしうる。このガードはまさにそのケースをスキップする。レビュアーは、`rb_gc_mark_fiber_saved_context` が常に真に**suspend された**ファイバーだけを渡されることを確認すべきである。`cont.c` のコメントはこれを文書化された事前条件にしている。
- `cont_mark` は所有者ベースの独自の foreign ガード(`cont.c:1161`: `rb_gc_local_gc_foreign_ractor_p(...)`)を保持しているので、ここで真に foreign なファイバーを渡しても防御的に依然スキップされる。ただし*意図された*契約は、呼び出し元(`ractor.c`)がこの Ractor 自身のスレッドに対してのみこれを呼ぶことである。
- この関数は `rb_execution_context_mark(th->ec)` を呼び、それには今や 7.6 の `VM_ASSERT` が含まれる。したがって誤った foreign な呼び出しはデバッグビルドでそのアサーションを発火させる。これが意図された安全網である。

---

### 7.8 `iseq.c`: VM グローバルな iseq/callcache の sweep が*すべての* objspace を walk する

`iseq.c:4266`, `iseq.c:4287`, `iseq.c:4318`

```c
-        rb_objspace_each_objects(clear_attr_ccs_i, NULL);
+        rb_objspace_each_objects_all_ractors(clear_attr_ccs_i, NULL);
...
-        rb_objspace_each_objects(clear_bf_ccs_i, NULL);
+        rb_objspace_each_objects_all_ractors(clear_bf_ccs_i, NULL);
...
-        rb_objspace_each_objects(trace_set_i, &turnon_events);
+        rb_objspace_each_objects_all_ractors(trace_set_i, &turnon_events);
```

**何を.** 3 つの VM グローバルな iseq/callcache の走査 — `rb_clear_attr_ccs`、`rb_clear_bf_ccs`、`rb_iseq_trace_set_all` — を、`rb_objspace_each_objects`(呼び出し元の objspace のみ)から新しい `rb_objspace_each_objects_all_ractors`(gc.c:4170)へ切り替える。これはメイン objspace、すべての生きた Ractor の `local_gc_objspace`、**そして orphan リスト上のすべての orphaned objspace** を走査する。

**なぜ.** これらは VM グローバルな操作であり、**どの Ractor が確保したかにかかわらず、ヒープに常駐するあらゆる iseq/callcache に到達**しなければならない。例えば TracePoint を有効化するには*すべての* iseq をパッチしなければならず(ワーカー Ractor でコンパイルされた iseq も、そのトレースバイトコードを設定する必要がある)、attr/bf callcache をクリアするにはすべての objspace のキャッシュを無効化しなければならない。RLGC 下では、iseq と callcache は Ractor ごとの objspace に散らばっているので、単一 objspace の walk では他の Ractor が確保したものを静かに取りこぼす。これは発火しない TracePoint や、古い callcache になる。

**どう位置づけられるか.** これら 3 つの箇所はいずれも既に VM barrier を保持している(`RB_VM_LOCKING()` 内の `rb_vm_barrier()`、または `rb_clear_bf_ccs` の場合は `ASSERT_vm_locking_with_barrier()`)。これはまさに `rb_objspace_each_objects_all_ractors` が文書化している事前条件である(「呼び出し元はオブジェクト集合が安定であるよう VM barrier を保持しなければならない」)。これはモデルの global/STW 側である。すべての Ractor が停止していれば、すべての objspace(orphaned なものを含む)を walk するのは安全である。

**レビュアー向けの注意点.**
- 新しいヘルパーの安全性は、ひとえに **barrier の事前条件**にかかっている。`rb_clear_bf_ccs` は自身ではロックを取らず、`ASSERT_vm_locking_with_barrier()` をアサートするだけなので、呼び出し元がそれを確立しなければならない。もし将来のどの呼び出し元かが barrier なしでこれらのいずれかを呼べば、Ractor ごとのオブジェクト集合は不安定であり、walk はクラッシュしうる。すべての呼び出し元を検証すること。
- orphaned objspace を含めるのは意図的であり重要である。終了した Ractor の orphaned objspace は、他の場所から参照される生きた shareable な iseq/callcache を依然保持しうるので、それをスキップすると orphaned-objspace のバグファミリーを再導入してしまう。ヘルパー内の orphan リストの walk に並行する mutator がいないことを確認すること(これは同じ STW 保証に依存している)。

---

*この副読本は実 diff (`git diff de5545202 HEAD`) を読みながら参照してください。残課題・現状サマリは `RLGC_STATUS.md`、設計の経緯は `RACTOR_LOCAL_GC_DESIGN.md` §6.x。*
