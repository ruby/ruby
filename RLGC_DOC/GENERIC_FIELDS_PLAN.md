# generic_fields ロック撤去プラン（設計確定 2026-07-02, ko1 と協働）

## 方針（確定）
`generic_fields_tbl` は **VM の機能（ivar 格納）であって GC の機能ではない** → 表は
GC-impl(`rb_objspace`)ではなく **VM 側 `rb_ractor_t` に per-Ractor で持つ**。無ロックの
根拠（owner の GVL 直列で mutator×confined-GC が排他）とも一致。`generic_fields_lock`
を撤去する（registered_globals / id2ref / zombie_threads に続く4本目）。

## 表の割り当て
| 種別 | 格納 | ロック |
|---|---|---|
| **unshareable** | **per-Ractor 表 `r->generic_fields_tbl`** | **無し**（owner のみ） |
| **shareable** | 既存 global 表 + narrow lock（当面維持。稀ケース） | 有り |

unshareable の insert/read/delete は containment により **常に owner=`GET_RACTOR()`** なので
`GET_RACTOR()->generic_fields_tbl` で引ける（ロック不要）。

## mark 経路 = (A) 弱参照を per-Ractor 表スキャンに寄せる
`generic_fields` は **weak-KEY**（key=obj が死んだら entry 削除。値 fields_obj は live obj の
strong child）。
- **confined GC**: per-object の `rb_mark_generic_ivar(obj)` を維持（`GET_RACTOR()`=owner なので
  自 Ractor 表を引ける）。mark fixpoint に自然に乗る。
- **global GC(STW)**: per-object 引きは driver の `GET_RACTOR()`≠owner で壊れる（finding-B 系）。
  なので global GC 中は per-object mark を **やらず**、**mark 後に per-Ractor 表を全 Ractor 分
  舐めて「live(marked) な obj の fields_obj だけ mark + drain」** する weak pass にする。
  → obj→foreign-Ractor の解決が原理的に不要。
- sweep(`rb_free_generic_ivar`)/ compaction(weak foreach): 同様に per-Ractor 表を対象化。

## absorb（Ractor#value / orphan）
src Ractor の表を dst へ移送（registered_globals と同じパターン）。objspace merge と同じ
`objspace_absorb_merge`（VM lock + gc-disabled）の窓の中でやれば、freeze-hash で学んだ
「objspace は移ったが登録情報が未移送」の窓が閉じる。

## make_shareable（unshareable→shareable への昇格）
obj が shareable 化した瞬間、entry を **owner の per-Ractor 表 → global(shared)表へ移送**。
owner スレッド上・delete/insert 間に alloc(GC)を挟まなければ atomic。

## 段階
- **Stage 1**: per-Ractor 表 + init/free + absorb 移送 + mark を (A) 化 + compaction 対応。
  unshareable=per-Ractor(無ロック)、shareable=global+lock 維持。test-all / CHECK / ASAN / oracle 緑。
- **Stage 2**（任意）: shareable も共有表 narrow lock に整理。稀ケースなので優先度低。

## 検証
build / btest / test-all（ivar/marshal/clone/struct/data/objectspace 広範）/ CHECK verify /
ASAN(ivar churn × 多 Ractor × make_shareable) / oracle 全14。
