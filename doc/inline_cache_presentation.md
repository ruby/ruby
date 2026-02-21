# Ruby Inline Cache 完全解説

> 対象: Ruby 4.1 dev (`include/ruby/version.h`)
> ソース参照: `vm_core.h`, `vm_callinfo.h`, `vm_insnhelper.c`, `insns.def`, `shape.c`, `variable.c`, `vm_method.c`

---

## Inline Cache とは

Ruby VM (YARV) は命令を実行するたびに「次に何をすべきか」を毎回探索するコストを避けるため、**命令列 (ISEQ) の中に直接キャッシュ領域を埋め込む**。これを **Inline Cache (広義)** と呼ぶ。

```
ISEQ (命令列)
┌─────────────────────────────────────┐
│ opt_send_without_block  [CALL_DATA] │  ← CC がここに埋め込まれる
│ getinstancevariable     [@x, IVC]   │  ← IVC がここに埋め込まれる
│ opt_getconstant_path    [IC]        │  ← IC がここに埋め込まれる
│ getclassvariable        [@@x,ICVARC]│  ← ICVARC がここに埋め込まれる
│ once                    [ISE]       │  ← ISE がここに埋め込まれる
└─────────────────────────────────────┘
```

ISEQ 本体のインラインストレージ領域 (`is_entries`) はメモリ上で以下の順に配置される:

```c
// vm_core.h:380
/* [ TS_IVC | TS_ICVARC | TS_ISE | TS_IC ] */
union iseq_inline_storage_entry *is_entries;
```

CC だけは `CALL_DATA` (`cd->cc`) として別管理される。

---

## 5種類のインラインキャッシュ

### 1. IC — Inline Constant Cache

| 項目 | 内容 |
|------|------|
| 型定義 | `typedef struct iseq_inline_constant_cache *IC;` |
| 使用命令 | `opt_getconstant_path` |
| 目的 | 定数ルックアップの高速化 |
| キャッシュキー | `ic_cref` (字句スコープ参照) |
| キャッシュ値 | `ice->value` (定数の値) + `ice->ic_cref` |

#### 構造体 (`vm_core.h:261-286`)

```c
struct iseq_inline_constant_cache_entry {
    VALUE flags;
    VALUE value;           // キャッシュされた定数値
    const rb_cref_t *ic_cref; // 字句スコープ参照
};

struct iseq_inline_constant_cache {
    struct iseq_inline_constant_cache_entry *entry;
    const ID *segments;    // 定数パス: FOO::BAR → {id_FOO, id_BAR, 0}
};
```

#### ヒット条件 (`vm_insnhelper.c:6558-6562`)

```c
static bool vm_ic_hit_p(const struct iseq_inline_constant_cache_entry *ice, const VALUE *reg_ep)
{
    // SHAREABLE (Ractor で共有可能) か、メイン Ractor の場合
    // かつ ic_cref が NULL (スコープ不問) or 現在の cref と一致
    return (flags & IMEMO_CONST_CACHE_SHAREABLE) || rb_ractor_main_p())
        && (ic_cref == NULL || ic_cref == vm_get_cref(reg_ep));
}
```

#### 無効化パターン (`vm_method.c:322-342`)

```c
// ic->entry = NULL にするだけでキャッシュクリア
static int rb_clear_constant_cache_for_id_i(st_data_t ic, st_data_t arg) {
    ((IC) ic)->entry = NULL;
    return ST_CONTINUE;
}

void rb_clear_constant_cache_for_id(ID id) {
    // vm->constant_cache テーブルから id に紐づく全 IC をクリア
}
```

**無効化トリガー:**
- 定数の再代入 (`FOO = 42` → `FOO = 99`)
- モジュール/クラスのネスト変更 (`module A; end` の再オープン)
- `include`, `prepend` によるモジュール階層変更

---

### 2. IVC — Inline Variable Cache (Instance Variable)

| 項目 | 内容 |
|------|------|
| 型定義 | `typedef struct iseq_inline_iv_cache_entry *IVC;` |
| 使用命令 | `getinstancevariable`, `setinstancevariable` |
| 目的 | インスタンス変数の高速 indexed access |
| キャッシュキー | オブジェクトの `shape_id` |
| キャッシュ値 | `shape_id` + `attr_index` (uint64_t にパック) |

#### 構造体 (`vm_core.h:288-291`)

```c
struct iseq_inline_iv_cache_entry {
    uint64_t value;   // shape_id (前半32bit) + attr_index (後半32bit)
    ID iv_set_name;
};
```

#### Object Shape とは (Ruby 3.2+)

インスタンス変数を**どの順番で最初に代入したか**が同じオブジェクトは同じ `shape_id` を持つ。IVC はこの `shape_id` をキーにして、「このオブジェクトの `@x` は ivar 配列の index 0 にある」とキャッシュする。

```
shape_id=1: { }            (初期状態)
shape_id=2: { @x }         (@x を最初に代入)
shape_id=3: { @x, @y }     (@y を 2 番目に代入)
```

#### ヒット条件 (`vm_insnhelper.c:1299-1326`)

```c
shape_id_t shape_id = RBASIC_SHAPE_ID_FOR_READ(obj);
vm_ic_atomic_shape_and_index(ic, &cached_id, &index);

if (LIKELY(cached_id == shape_id)) {
    // キャッシュヒット: ivar 配列から直接 index アクセス
    val = ivar_list[index];
}
```

#### 無効化パターン

| パターン | 理由 |
|---------|------|
| 条件分岐で異なるivarを定義 | shape がフォーク → 異なる shape_id |
| `initialize` の外で `@x` を初めて代入 | 呼び出しサイトごとに shape_id が違う可能性 |
| `SHAPE_MAX_VARIATIONS` (8) を超えた | `too_complex` 状態へ遷移 → ハッシュ検索にフォールバック |

```ruby
# NG: 条件によって shape が分岐
class Bad
  def initialize(flag)
    @a = 1
    @b = 2 if flag   # ← shape がフォーク。同じクラスで2種のshapeが生まれる
    @c = 3
  end
end

# OK: 常に同じ順序で定義
class Good
  def initialize
    @a = 1
    @b = nil   # 使わなくても nil で確保しておく
    @c = 3
  end
end
```

---

### 3. ICVARC — Inline Class Variable Cache

| 項目 | 内容 |
|------|------|
| 型定義 | `typedef struct iseq_inline_cvar_cache_entry *ICVARC;` |
| 使用命令 | `getclassvariable`, `setclassvariable` |
| 目的 | クラス変数ルックアップの高速化 |
| キャッシュキー | `global_cvar_state` + `cref` |
| キャッシュ値 | `rb_cvar_class_tbl_entry *entry` (クラスへの参照含む) |

#### 構造体 (`vm_core.h:293-295`)

```c
struct iseq_inline_cvar_cache_entry {
    struct rb_cvar_class_tbl_entry *entry;
    // entry には: global_cvar_state, cref, class_value が入る
};
```

#### ヒット条件 (`vm_insnhelper.c:1637`)

```c
if (ic->entry &&
    ic->entry->global_cvar_state == GET_GLOBAL_CVAR_STATE() &&
    ic->entry->cref == cref &&
    LIKELY(rb_ractor_main_p()))   // メインRactorのみ
{
    // キャッシュヒット: class_value から直接 ivar 読み取り
    VALUE v = rb_ivar_lookup(ic->entry->class_value, id, Qundef);
}
```

#### 無効化パターン (`variable.c:4240-4251`)

```c
static void check_for_cvar_table(VALUE subclass, VALUE key) {
    if (!RB_TYPE_P(subclass, T_ICLASS) &&
        RTEST(rb_ivar_defined(subclass, key))) {
        ruby_vm_global_cvar_state++;  // ← 全 ICVARC を一括無効化
        return;
    }
    rb_class_foreach_subclass(subclass, check_for_cvar_table, key);
}
```

| 無効化トリガー | 理由 |
|--------------|------|
| サブクラスで同名 `@@cvar` を新規定義 | `global_cvar_state` がインクリメントされる |
| 字句スコープ (cref) が変わった場合 | `ic->entry->cref != cref` |
| メインRactor以外のRactor | キャッシュ不使用 (安全のため) |

**重要:** `global_cvar_state` は**グローバルなモノトニックカウンタ**。どこかで新しいクラス変数が「祖先との競合」を起こすと、全クラスの全 ICVARC が一括無効化される。クラス変数がパフォーマンスに悪影響を与える主因。

---

### 4. ISE — Inline Storage Entry

| 項目 | 内容 |
|------|------|
| 型定義 | `typedef union iseq_inline_storage_entry *ISE;` |
| 使用命令 | `once` |
| 目的 | 一度だけ実行される処理の結果をキャッシュ |
| キャッシュキー | `running_thread` フラグ |
| キャッシュ値 | `is->once.value` (実行結果) |

#### 構造体 (`vm_core.h:297-304`)

```c
union iseq_inline_storage_entry {
    struct {
        struct rb_thread_struct *running_thread;
        VALUE value;  // キャッシュされた結果
    } once;
    struct iseq_inline_constant_cache ic_cache;
    struct iseq_inline_iv_cache_entry iv_cache;
};
```

#### ヒット条件 (`vm_insnhelper.c:6618-6650`)

```c
static VALUE vm_once_dispatch(rb_execution_context_t *ec, ISEQ iseq, ISE is)
{
    rb_thread_t *const DONE = (rb_thread_t *)(0x1); // センチネル値

    if (is->once.running_thread == DONE) {
        return is->once.value;  // ← 2回目以降は即リターン
    }
    else if (is->once.running_thread == NULL) {
        // 初回実行: ブロックを評価してキャッシュ
        VALUE val = rb_ensure(vm_once_exec, (VALUE)iseq, vm_once_clear, (VALUE)is);
        is->once.running_thread = DONE;
        return val;
    }
    // ...スレッド競合ハンドリング省略
}
```

#### 使用例

```ruby
# /regex/ リテラル → once 命令でコンパイル済み Regexp を1回だけ生成
def check(str)
  str.match?(/foo+bar/)  # 内部的に once でキャッシュ
end

# 明示的な once (BEGIN ブロック内など)
```

**ISE は一度設定されると絶対に無効化されない** (ISEQ が GC されるまで保持)。

---

### 5. CC — Call Cache (Method Dispatch Cache)

| 項目 | 内容 |
|------|------|
| 型定義 | `typedef const struct rb_callcache *CALL_CACHE;` |
| 使用命令 | `opt_send_without_block`, `send`, `invokesuper` 等 |
| 目的 | メソッドディスパッチの高速化 |
| キャッシュキー | `cc->klass` (レシーバのクラス) |
| キャッシュ値 | `cme_` (callable method entry) + `call_` (ハンドラ関数ポインタ) |

#### 構造体 (`vm_callinfo.h:278-296`)

```c
struct rb_callcache {
    const VALUE flags;
    const VALUE klass;   // ← キー: レシーバのクラス (弱参照)
    const struct rb_callable_method_entry_struct *const cme_;  // ← 検索済みメソッドエントリ
    const vm_call_handler call_;  // ← 実際のディスパッチ関数ポインタ
    union {
        struct { uint64_t value; } attr; // shape_id + ivar_index (attr_accessor 用)
        const enum method_missing_reason method_missing_reason;
        const struct rb_builtin_function *bf;
    } aux_;
};
```

#### ヒット条件 (`vm_insnhelper.c:2357-2380`)

```c
static const struct rb_callcache *
vm_search_method_fastpath(VALUE cd_owner, struct rb_call_data *cd, VALUE klass)
{
    const struct rb_callcache *cc = cd->cc;

    if (LIKELY(vm_cc_class_check(cc, klass))) {          // klass が一致?
        if (LIKELY(!METHOD_ENTRY_INVALIDATED(vm_cc_cme(cc)))) { // CME が有効?
            return cc;  // ← キャッシュヒット!
        }
    }
    return vm_search_method_slowpath0(cd_owner, cd, klass); // ミス: 再検索
}
```

#### 無効化パターン (`vm_method.c:544-561`)

```c
void rb_clear_method_cache(VALUE klass_or_module, ID mid) {
    // モジュールなら全サブクラスのキャッシュを無効化
    rb_class_foreach_subclass(module, clear_iclass_method_cache_by_id, mid);
}
```

| 無効化トリガー | 具体例 |
|--------------|--------|
| メソッドの再定義 | `def foo; end` を再度 `def foo; end` |
| `include` / `prepend` | 祖先チェーンが変わる |
| `remove_method` | メソッドの削除 |
| `undef_method` | メソッドの無効化 |
| Refinements | `using SomeModule` |
| レシーバのクラスが変わる | 多相呼び出し (ポリモーフィズム) |

#### Monomorphic vs Megamorphic

```
モノモーフィック: 同じクラスのオブジェクトだけが呼ぶ
  → CC が常にヒット → 最速

メガモーフィック: 3種以上の異なるクラスが同じ call site を使う
  → CC は1エントリしか保持できないため、毎回ミス → 低速
```

---

## キャッシュ無効化まとめ表

| キャッシュ | 無効化トリガー | 無効化方法 |
|-----------|--------------|-----------|
| **IC** | 定数の再代入、モジュール再オープン、`include`/`prepend` | `ic->entry = NULL` |
| **IVC** | オブジェクトの shape 変化 (ivar の動的追加、too_complex 遷移) | shape_id 不一致で自動ミス |
| **ICVARC** | 孫クラスで同名 cvar を新規定義 → `global_cvar_state++` | グローバルカウンタ不一致で自動ミス |
| **ISE** | **無効化されない** | — |
| **CC** | メソッド再定義、`include`/`prepend`/`remove_method`/`undef_method`/Refinements | `cc->klass = Qundef` |

---

## ベンチマーク実行方法

```bash
gem install benchmark-ips
ruby benchmark/inline_cache_demo.rb
```

### 期待される結果のポイント

| ベンチ | 期待 |
|--------|------|
| IC hit vs 定数 | ほぼ同等 (ともにキャッシュヒット) |
| IVC: consistent vs alternating shapes | consistent が大幅に速い |
| ICVARC: stable hierarchy | 安定した hierarchy では高速 |
| ISE: literal /regex/ vs Regexp.new | literal が 2〜5x 速い |
| CC: monomorphic vs megamorphic | monomorphic が 1.5〜3x 速い |

---

## 発表のポイント

### 「なぜ inline なのか」

通常のキャッシュはグローバルな hash table に保存するが、それだとルックアップ自体にコストがかかる。Inline cache は**命令の引数として埋め込む**ことで、ポインタ1本のデリファレンスだけでキャッシュにアクセスできる。

### 「なぜ Ruby の定数参照は速いのか」

`FOO` を参照するたびに「`Object::FOO` はあるか? `Kernel::FOO` はあるか?...」と探索するのではなく、IC に `{ value: 42, cref: <scope> }` がキャッシュされていれば、**1命令でその値を返せる**。

### 「Object Shape とは」(IVC の前提知識)

Ruby 3.2 で導入。同じ順序で ivar を定義したオブジェクトは同じ shape tree パスを辿り、**同じ shape_id** を持つ。shape_id が一致すれば、`@x` の位置は ivar 配列の何番目かが確定しており、インデックスアクセスで取得できる。

```
shape_id=0 (root)
  └─ @x assigned → shape_id=1
       └─ @y assigned → shape_id=2  ← ConsistentShape のオブジェクト全員がここ
```

### 「なぜクラス変数は遅いか」

ICVARC のキャッシュキーが `global_cvar_state` という**グローバルなカウンタ**であるため、どこかのサブクラスで新しいクラス変数が定義されると**全クラスの全キャッシュが一括無効化**される。この「グローバルな副作用」がクラス変数のパフォーマンス問題の核心。
