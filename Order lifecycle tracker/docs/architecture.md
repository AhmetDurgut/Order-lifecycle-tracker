# Technical Architecture — Sales Order Lifecycle Tracker

## 1. Why it's built this way

The guiding idea here is the standard SAP VDM (Virtual Data Model) layering, applied deliberately rather than out of habit: interface views read the raw tables and do nothing else, composite views are where joins, aggregation, and calculation happen, and consumption views are the only thing the UI is allowed to know about. Each layer has exactly one job, and — this is the part that actually pays off later — a UI change never has to touch anything below the consumption view, and a calculation change never has to touch anything above the composite layer. If tomorrow someone wants to add a new column to the List Report, that's a metadata extension change; if someone wants to change what counts as "delivered," that's a change in one base view, and every consumer of it (the header view, the item view, and eventually any report built on top) picks it up automatically.

- **Read-only by design.** Every view in this project is a plain `define view entity` — there is no RAP behavior definition, no draft handling, no `EML` write operations anywhere. That's not a limitation that got left unfinished; it's the honest shape of the problem. This app answers a question ("where is this order in its lifecycle, and for how long has it been there?") — it doesn't need to let anyone change an order's status, because changing that status is what VA02/VA01 are already for. Keeping it read-only also makes it the natural first half of a bigger project: if this ever grew an "approve," "escalate," or "nudge the warehouse" action, that's exactly the kind of thing a RAP-managed business object would sit on top of this same data model to provide, without the read side needing to change at all.
- **Calculation centralized in the base views.** `ZI_SO_LIFECYCLE_BASE` and `ZI_SO_LIFECYCLE_ITEM_BASE` are the only two places in the whole stack that decide what stage an order is in and how many days it's been there — the consumption views just read `LifecycleStage` and `DaysInCurrentStage` as plain fields. This split exists because of a genuine CDS limitation, not stylistic preference: a calculated field in a `SELECT` list cannot reference another calculated field defined next to it in the same view. `DaysInCurrentStage` needs the exact same "which date counts as the stage's start" logic that `StageReferenceDate` computes, but it can't just write `StageReferenceDate` inside `dats_days_between(...)` — CDS won't allow one sibling field to call another. The only way to reuse that logic instead of copy-pasting it forward into every future consumer is to push it down into its own base view and read it back up as an already-computed field. Both base views still have to repeat the CASE expression three times internally (once for the standalone field, twice more inside `DaysInCurrentStage`'s guard and its `dats_days_between` call) — but that repetition is contained to one file each, instead of leaking into every downstream view that ever wants the day count.
- **Annotation-driven UI, nothing hand-written.** The List Report filter bar, the colored table columns, and the Object Page facets all come from `@UI` annotations in `ZC_SO_LIFECYCLE.ddlx` and `ZC_SO_LIFECYCLE_ITEM.ddlx` — there's no custom controller, no manually built OData handler, no JavaScript. `@Semantics` annotations (currency codes, units of measure) live in the consumption views themselves, not the metadata extensions, because semantics describe what the *data* actually is — an amount, tied to a currency field — regardless of which app happens to be looking at it; `@UI` annotations describe how one particular app chooses to *lay it out*, which is exactly the kind of decision that should be swappable without re-activating the underlying view. Keeping them apart also isn't just a style choice: putting the same annotation on the same field in both the view and its metadata extension is a duplicate-annotation conflict that fails activation outright, so the separation is enforced by the tooling, not just convention.
- **Targets S/4HANA specifically.** `ZI_SO_HEADER` and `ZI_SO_ITEM` read the delivery/billing status fields (`LFSTK`/`FKSTK` on VBAK, `LFSTA`/`FKSTA` on VBAP) directly off the order tables. That's an S/4HANA simplification — on ECC those statuses lived on the separate status tables VBUK (header) and VBUP (item), and this single-source approach wouldn't have worked there. Every interface view's header comment says so explicitly, so nobody tries to backport this to an ECC system expecting it to just work.

## 2. The layers and what lives where

| Object | Layer | Responsibility |
|---|---|---|
| `ZI_SO_HEADER` | Interface | Order header over VBAK — sales org, customer, net value, creation date, delivery/billing status |
| `ZI_SO_ITEM` | Interface | Order item over VBAP — material, quantity, item value, item-level delivery/billing status |
| `ZI_DLV_ITEM` | Interface | Delivery items over LIPS, with header dates (planned/actual goods issue, delivery date) pulled in from LIKP |
| `ZI_BIL_ITEM` | Interface | Billing items over VBRP, with header fields (billing date, type, currency) pulled in from VBRK |
| `ZI_DOC_FLOW` | Interface | Document flow over VBFA, filtered to delivery (`J`) and invoice (`M`) follow-on documents only |
| `ZI_SO_DELIVERY_AGGR` | Composite | Delivery quantities and latest goods-issue date, rolled up per sales order **item** |
| `ZI_SO_DELIVERY_AGGR_HDR` | Composite | The above rolled up one level further, per sales order **header** |
| `ZI_SO_LIFECYCLE_BASE` | Composite | Header stage, stage reference date, and days-in-stage — the single source of truth for the header lifecycle logic |
| `ZI_SO_LIFECYCLE_ITEM_BASE` | Composite | Same calculation, at item level, using the item's own status fields |
| `ZC_SO_LIFECYCLE` | Consumption | Header projection plus `StageCriticality`, one row per sales order |
| `ZC_SO_LIFECYCLE_ITEM` | Consumption | Item projection plus `StageCriticality`, one row per sales order item |
| `ZC_SO_LIFECYCLE.ddlx` / `ZC_SO_LIFECYCLE_ITEM.ddlx` | Metadata Extension | `@UI` annotations driving the List Report and the Object Page (facets, line items, criticality coloring) |
| `ZC_SO_LIFECYCLE_AUTH` / `ZC_SO_LIFECYCLE_ITEM_AUTH` (`.dcl`) | Access Control | Sales-organization-based row-level authorization |
| `ZUI_SO_LIFECYCLE` (`.srvd`) | Service | Exposes the two consumption views as an OData V4 service |

## 3. How the data flows

```
Raw SAP tables
  VBAK ─────────────► ZI_SO_HEADER
  VBAP ─────────────► ZI_SO_ITEM  ──(_SalesOrder)──► ZI_SO_HEADER
  LIPS + LIKP ───────► ZI_DLV_ITEM ─(_SalesOrderItem)──► ZI_SO_ITEM
  VBRP + VBRK ───────► ZI_BIL_ITEM ─(_SalesOrderItem)──► ZI_SO_ITEM
  VBFA (J/M only) ───► ZI_DOC_FLOW ─(_SalesOrderItem)──► ZI_SO_ITEM
                                       │
                                       ▼
                        ZI_SO_DELIVERY_AGGR
                (delivery qty + latest goods-issue date,
                 grouped by SalesOrder + SalesOrderItem)
                                       │
                                       ▼
                     ZI_SO_DELIVERY_AGGR_HDR
                (the same, rolled up once more per SalesOrder)
                                       │
             ┌─────────────────────────┴──────────────────────────┐
             ▼                                                    ▼
   ZI_SO_LIFECYCLE_BASE                             ZI_SO_LIFECYCLE_ITEM_BASE
   (header: LifecycleStage,                         (item: LifecycleStage,
    StageReferenceDate,                               StageReferenceDate,
    DaysInCurrentStage)                                DaysInCurrentStage)
             │                                                    │
             ▼                                                    ▼
     ZC_SO_LIFECYCLE  ─────────────── _Item ────────────►  ZC_SO_LIFECYCLE_ITEM
   (+ StageCriticality)              _SalesOrder  ◄────────────    (+ StageCriticality)
             │                                                    │
   ZC_SO_LIFECYCLE.ddlx                                ZC_SO_LIFECYCLE_ITEM.ddlx
   (List Report + Object Page facets)                  (Object Page item table)
             │                                                    │
             └────────────────────────┬───────────────────────────┘
                                       ▼
                          ZUI_SO_LIFECYCLE (Service Definition)
                                       │
                                       ▼
                     OData V4 Service Binding (activated + published)
                                       │
                                       ▼
                       Fiori Elements List Report + Object Page
```

The `_Item` association on `ZC_SO_LIFECYCLE` and the `_SalesOrder` association on `ZC_SO_LIFECYCLE_ITEM` point at each other — that mutual link is exactly what lets the Object Page's "Order Items" facet navigate from one order down to its items, and it's also the one place in the whole model with a genuine circular dependency (covered in the setup guide, since it affects activation order).

## 4. The lifecycle stages

Both base views run the same six-stage classification — the header view reads it off VBAK's `LFSTK`/`FKSTK`, the item view off VBAP's `LFSTA`/`FKSTA` (same values, item-level source) — and both pick a reference date appropriate to the stage the order is actually in, since "how long has this been waiting" only means something once you know what it's been waiting *for*.

| Stage | Condition | Reference date |
|---|---|---|
| `ORDER_CREATED` | Delivery status = `A` (not yet delivered) | Creation date |
| `PARTIALLY_DELIVERED` | Delivery status = `B` | Creation date |
| `DELIVERED` | Delivery status = `C`, but goods issue hasn't actually happened yet | Creation date |
| `GOODS_ISSUED` | Delivery status = `C`, goods issue has happened, billing status = `A` (not yet billed) | Latest goods-issue date |
| `PARTIALLY_INVOICED` | Billing status = `B` | Latest goods-issue date |
| `INVOICED` | Billing status = `C` | n/a — day count is forced to `0` regardless of what the reference date would otherwise be |

The `DELIVERED` vs. `GOODS_ISSUED` split is the one that isn't obvious from the standard status fields alone: `LFSTK`/`LFSTA` = `C` just means "a delivery document exists for the full quantity," not that goods have actually left the warehouse. That's why both base views also check `LatestGoodsIssueDate` (sourced from the delivery aggregation, ultimately from LIKP's actual goods-issue date `WADAT_IST`) before deciding between the two — a delivery sitting there with no goods movement yet is a materially different situation from one that's actually shipped.

## 5. Stage criticality

`ZC_SO_LIFECYCLE` and `ZC_SO_LIFECYCLE_ITEM` both turn `DaysInCurrentStage` into a Fiori criticality code (1 = red, 2 = yellow, 3 = green) using thresholds that are deliberately different per stage:

| Stage | Green (3) | Yellow (2) | Red (1) |
|---|---|---|---|
| `ORDER_CREATED` | 0–1 days | 2–4 days | 5+ days |
| `PARTIALLY_DELIVERED` | 0–2 days | 3–6 days | 7+ days |
| `DELIVERED` | 0 days | 1–2 days | 3+ days |
| `GOODS_ISSUED` | 0–2 days | 3–6 days | 7+ days |
| `PARTIALLY_INVOICED` | 0–4 days | 5–9 days | 10+ days |
| `INVOICED` | always green | — | — |

The thresholds aren't the same number repeated six times because the stages don't carry the same urgency. Sitting in `DELIVERED` — a delivery exists but goods haven't physically moved — is meant to turn red almost immediately (day 3), because that's usually a warehouse execution problem that should get attention fast. `PARTIALLY_INVOICED`, by contrast, gets the most slack (up to 9 days before turning red), because invoicing cycles often run on a batch or periodic schedule, and flagging every invoice-in-progress order as urgent on day 2 would just be noise. `INVOICED` is always green because there's nothing left to chase — the order finished its journey.

## 6. The delivery aggregation (why two levels)

`ZI_SO_DELIVERY_AGGR` groups `ZI_DLV_ITEM` by `SalesOrder` + `SalesOrderItem`, giving exactly one row per order item — the latest goods-issue date and total delivered quantity for that specific item. That's the right grain for `ZI_SO_LIFECYCLE_ITEM_BASE` to associate to directly with `[0..1]` cardinality: one order item can have many delivery item rows behind it (partial deliveries, several LIPS lines), but the aggregation collapses them back to one row per (order, item) pair before the item lifecycle view ever sees them.

The header view has a different problem: an order can have many items, and each item can have many delivery rows, so grouping only by `SalesOrder` is a second, coarser aggregation on top of the first — `ZI_SO_DELIVERY_AGGR_HDR` rolls `ZI_SO_DELIVERY_AGGR` up once more, by `SalesOrder` alone, specifically so it collapses to exactly one row per order. Without that second roll-up, a `[0..1]` association from the header view down to the item-grained aggregation would either be technically wrong (an order with three items could match three aggregation rows) or would silently pick an arbitrary one — neither of which is something you want hiding inside a "how long has this order been stuck" calculation. Two aggregation views exist because the header and the item lifecycle views each need the data collapsed to their *own* grain, not the same grain reused twice.

## 7. Authorization (DCL)

`ZC_SO_LIFECYCLE_AUTH` grants access to `ZC_SO_LIFECYCLE` based on the standard SD authorization object **V_VBAK_VKO** (Sales Organization / Distribution Channel / Division), checked against activity `03` (display) — a user only sees rows whose `SalesOrganization`/`DistributionChannel`/`Division` combination matches what their PFCG role actually grants them for that object. This is exactly why `VKORG`/`VTWEG`/`SPART` get projected all the way through `ZI_SO_HEADER` → `ZI_SO_LIFECYCLE_BASE` → `ZC_SO_LIFECYCLE`, even though nothing in the lifecycle *calculation* itself needs them — a DCL can only filter on fields the view actually exposes, so those three fields are carried up through every layer purely so this authorization check has something to reference at the top.

`ZC_SO_LIFECYCLE_ITEM_AUTH` doesn't repeat that check. It has no sales-org fields of its own to filter on — VBAP doesn't carry them — so instead it uses `inheriting conditions from entity ZC_SO_LIFECYCLE via association _SalesOrder`, which means an item is visible exactly when its parent order (reached through the `_SalesOrder` association) is visible under the header's own rule. There's exactly one authorization rule in this whole project, not two kept in sync by hand — if the header rule ever changes, the item view's visibility changes automatically with it, because it was never a second, independent rule to begin with.

## 8. A few UI notes

- The red/yellow/green coloring on `LifecycleStage` and `DaysInCurrentStage` comes from `@UI.lineItem: [{ ..., criticality: 'StageCriticality' }]` in the metadata extensions, pointing at the `StageCriticality` field computed in the consumption views. `StageCriticality` itself is marked `@UI.hidden: true` — it exists purely to drive coloring and is never meant to appear as its own column.
- `@Semantics.amount.currencyCode` / `@Semantics.quantity.unitOfMeasure` sit on the consumption views (`NetValue`/`Currency`, `OrderQuantity`/`SalesUnit`, `ItemNetValue`/`Currency`), while every `@UI` annotation sits in the metadata extensions — the split described in §1. It also means the same consumption view could, in principle, be reused by a second Fiori app with a completely different layout, without touching what the data itself semantically is.
- The Object Page's "Order Items" facet is a `#LINEITEM_REFERENCE` facet with `targetElement: '_Item'` in `ZC_SO_LIFECYCLE.ddlx` — it doesn't duplicate any item data into the header view, it just tells Fiori Elements "render a table here, sourced from this association," and the actual columns for that table come from `ZC_SO_LIFECYCLE_ITEM.ddlx`'s own `@UI.lineItem` annotations.

## 9. What's simplified on purpose

- **Read-only, no RAP behavior.** Covered in §1 — this app reads, it doesn't write. Any future "act on a stalled order" feature belongs in a RAP layer on top, not bolted onto these views.
- **The chain stops at invoicing.** Payment and clearing (`BKPF`, `BSID`/`BSAD`) aren't part of this model. `BSID` is itself a compatibility view in S/4HANA rather than a real table, and the link from an invoice back to its accounting document runs through `BKPF-AWKEY`, which is a messier, less direct join than anything else in this stack — it's left out deliberately rather than modeled poorly, and called out here as the natural next step (§10).
- **`$session.system_date` for "today."** Both base views use it to compute "days as of right now." It's the simplest option and works on current S/4HANA releases; on a release where it isn't accepted inside a view entity, the fallback is a date input parameter on the base views instead (`with parameters p_key_date : abap.dats`), with every consumer supplying it explicitly.
- **No value helps beyond the customer name.** `CustomerName` (from KNA1 via `_Customer`) is the only bit of text enrichment in the model — there's no F4 value help defined for material, sales organization, or anything else. Filtering in the List Report today works on raw codes.

## 10. Possible extensions

- **Add the payment/clearing step** to complete the order-to-cash picture — an `INVOICED_UNPAID` / `PAID` distinction sourced from `BSID`/`BSAD`, closing the gap noted in §9.
- **A RAP-based writable layer** on top of this same model — actions like "escalate," "nudge warehouse," or "mark as followed up," logged against the order without touching how the lifecycle itself is calculated.
- **An Analytical List Page** with aggregated stage counts (how many orders are in each stage, sales-org by sales-org) as a management-level view sitting above the current order-by-order List Report.
- **Alerting when an order crosses its own stage threshold** — an order that just turned red could trigger an e-mail or a SAP Business Workflow item instead of waiting for someone to open the app and notice.
- **Value helps and text associations** for material, sales organization, and distribution channel, to make the filter bar friendlier than raw codes.

---

# Teknik Mimari — Sales Order Lifecycle Tracker

## 1. Neden bu şekilde kurgulandı

Buradaki temel fikir, standart SAP VDM (Virtual Data Model) katmanlamasının alışkanlıktan değil bilinçli bir tercihle uygulanması: interface view'ler ham tabloları okur ve başka hiçbir şey yapmaz, composite view'ler join'lerin, aggregation'ların ve hesaplamaların yapıldığı yerdir, consumption view'ler ise UI'ın bilmesine izin verilen tek şeydir. Her katmanın tam olarak tek bir işi var, ve — asıl kazancı burada — bir UI değişikliği hiçbir zaman consumption view'in altındaki hiçbir şeye dokunmak zorunda kalmıyor, bir hesaplama değişikliği de hiçbir zaman composite katmanın üstündeki hiçbir şeye dokunmak zorunda kalmıyor. Yarın biri List Report'a yeni bir sütun eklemek isterse, bu bir metadata extension değişikliği; biri "delivered" sayılmanın ne anlama geldiğini değiştirmek isterse, bu tek bir base view'de yapılan bir değişiklik, ve onu tüketen her şey (header view, item view, ve ileride bunun üzerine kurulacak her rapor) bunu otomatik olarak alıyor.

- **Bilinçli olarak salt okunur (read-only).** Bu projedeki her view düz bir `define view entity` — hiçbir yerde RAP behavior definition, draft yönetimi ya da `EML` yazma işlemi yok. Bu, yarım bırakılmış bir eksiklik değil; sorunun dürüst şekli. Bu uygulama bir soruyu yanıtlıyor ("bu sipariş yaşam döngüsünün neresinde, ve orada ne kadar süredir?") — kimsenin bir siparişin durumunu değiştirmesine izin vermesi gerekmiyor, çünkü o durumu değiştirmek zaten VA02/VA01'in işi. Salt okunur kalmak, aynı zamanda bunu daha büyük bir projenin doğal ilk yarısı haline getiriyor: eğer bir gün buraya "onayla", "yükselt" ya da "depoyu dürt" gibi bir aksiyon eklenecek olursa, bu tam olarak bir RAP-yönetimli business object'in, okuma tarafına hiç dokunmadan, aynı veri modelinin üzerine oturarak sağlayacağı türden bir şey.
- **Hesaplama base view'lerde merkezileştirilmiş.** `ZI_SO_LIFECYCLE_BASE` ve `ZI_SO_LIFECYCLE_ITEM_BASE`, tüm yığın içinde bir siparişin hangi aşamada olduğuna ve orada kaç gündür bulunduğuna karar veren tek iki yer — consumption view'ler `LifecycleStage` ve `DaysInCurrentStage`'i düz birer alan olarak okuyor sadece. Bu ayrım, üsluba dair bir tercih değil, gerçek bir CDS kısıtlamasından geliyor: bir `SELECT` listesindeki hesaplanmış bir alan, aynı view içinde yanına tanımlanmış başka bir hesaplanmış alana referans veremez. `DaysInCurrentStage`, `StageReferenceDate`'in hesapladığı "hangi tarih bu aşamanın başlangıcı sayılır" mantığının aynısına ihtiyaç duyuyor, ama `dats_days_between(...)` içine doğrudan `StageReferenceDate` yazamıyor — CDS bir sibling alanın diğerini çağırmasına izin vermiyor. Bu mantığı kopyala-yapıştır yapmak yerine yeniden kullanabilmenin tek yolu, onu kendi base view'ine indirip zaten hesaplanmış bir alan olarak geri okumak. İki base view de CASE ifadesini kendi içinde hâlâ üç kez tekrarlamak zorunda (bir kez tek başına duran alan için, iki kez daha `DaysInCurrentStage`'in koruma kontrolü ve `dats_days_between` çağrısı içinde) — ama bu tekrar her dosyada kendi içine hapsedilmiş durumda, gün sayısını isteyen her downstream view'e sızmak yerine.
- **Annotation'dan üretilen UI, elle yazılmış hiçbir şey yok.** List Report'un filtre çubuğu, renkli tablo sütunları ve Object Page facet'lerinin hepsi `ZC_SO_LIFECYCLE.ddlx` ve `ZC_SO_LIFECYCLE_ITEM.ddlx` içindeki `@UI` annotation'larından geliyor — özel bir controller yok, elle yazılmış bir OData handler yok, JavaScript yok. `@Semantics` annotation'ları (para birimi kodları, ölçü birimleri) metadata extension'larda değil, consumption view'lerin kendisinde duruyor, çünkü semantics, hangi uygulamanın baktığından bağımsız olarak *verinin* aslında ne olduğunu tanımlıyor — bir para birimi alanına bağlı bir tutar; `@UI` annotation'ları ise bir uygulamanın bunu nasıl *düzenlemeyi tercih ettiğini* tanımlıyor, ki bu da alttaki view'i yeniden aktive etmeden değiştirilebilir olması gereken tam da o türden bir karar. Bunları ayrı tutmak sadece bir stil tercihi de değil: aynı annotation'ı hem view'e hem onun metadata extension'ına aynı alan üzerinde koymak, doğrudan aktivasyonu başarısız kılan bir duplicate-annotation çakışması — yani bu ayrım sadece bir gelenekle değil, araç tarafından da zorunlu kılınıyor.
- **Özellikle S/4HANA'yı hedefliyor.** `ZI_SO_HEADER` ve `ZI_SO_ITEM`, teslimat/fatura durum alanlarını (VBAK'ta `LFSTK`/`FKSTK`, VBAP'ta `LFSTA`/`FKSTA`) doğrudan sipariş tablolarından okuyor. Bu bir S/4HANA basitleştirmesi — ECC'de bu durumlar ayrı status tablolarında, VBUK (header) ve VBUP (item) üzerinde dururdu, ve bu tek-kaynaklı yaklaşım orada işe yaramazdı. Her interface view'in başlık yorumu bunu açıkça söylüyor, ki kimse bunu bir ECC sistemine, olduğu gibi çalışacağını umarak taşımaya kalkmasın.

## 2. Katmanlar ve neyin nerede durduğu

| Nesne | Katman | Sorumluluk |
|---|---|---|
| `ZI_SO_HEADER` | Interface | VBAK üzerinden sipariş başlığı — satış organizasyonu, müşteri, net değer, oluşturulma tarihi, teslimat/fatura durumu |
| `ZI_SO_ITEM` | Interface | VBAP üzerinden sipariş kalemi — malzeme, miktar, kalem değeri, kalem bazlı teslimat/fatura durumu |
| `ZI_DLV_ITEM` | Interface | LIPS üzerinden teslimat kalemleri, LIKP'ten gelen header tarihleriyle (planlanan/gerçek mal çıkışı, teslimat tarihi) birlikte |
| `ZI_BIL_ITEM` | Interface | VBRP üzerinden fatura kalemleri, VBRK'ten gelen header alanlarıyla (fatura tarihi, tipi, para birimi) birlikte |
| `ZI_DOC_FLOW` | Interface | VBFA üzerinden belge akışı, sadece teslimat (`J`) ve fatura (`M`) takip belgelerine filtrelenmiş |
| `ZI_SO_DELIVERY_AGGR` | Composite | Teslimat miktarları ve en son mal çıkış tarihi, sipariş **kalemi** bazında toplanmış |
| `ZI_SO_DELIVERY_AGGR_HDR` | Composite | Yukarıdakinin bir seviye daha, sipariş **başlığı** bazında toplanmışı |
| `ZI_SO_LIFECYCLE_BASE` | Composite | Başlık aşaması, aşama referans tarihi ve aşamadaki gün sayısı — header yaşam döngüsü mantığının tek doğru kaynağı |
| `ZI_SO_LIFECYCLE_ITEM_BASE` | Composite | Aynı hesaplama, kalem seviyesinde, kalemin kendi durum alanlarını kullanarak |
| `ZC_SO_LIFECYCLE` | Consumption | Başlık projeksiyonu artı `StageCriticality`, sipariş başına bir satır |
| `ZC_SO_LIFECYCLE_ITEM` | Consumption | Kalem projeksiyonu artı `StageCriticality`, sipariş kalemi başına bir satır |
| `ZC_SO_LIFECYCLE.ddlx` / `ZC_SO_LIFECYCLE_ITEM.ddlx` | Metadata Extension | List Report ve Object Page'i süren `@UI` annotation'ları (facet'ler, satır öğeleri, criticality renklendirmesi) |
| `ZC_SO_LIFECYCLE_AUTH` / `ZC_SO_LIFECYCLE_ITEM_AUTH` (`.dcl`) | Access Control | Satış organizasyonu bazlı satır seviyesinde yetkilendirme |
| `ZUI_SO_LIFECYCLE` (`.srvd`) | Service | İki consumption view'i bir OData V4 servisi olarak dışarı açar |

## 3. Veri nasıl akıyor

```
Ham SAP tabloları
  VBAK ─────────────► ZI_SO_HEADER
  VBAP ─────────────► ZI_SO_ITEM  ──(_SalesOrder)──► ZI_SO_HEADER
  LIPS + LIKP ───────► ZI_DLV_ITEM ─(_SalesOrderItem)──► ZI_SO_ITEM
  VBRP + VBRK ───────► ZI_BIL_ITEM ─(_SalesOrderItem)──► ZI_SO_ITEM
  VBFA (sadece J/M) ─► ZI_DOC_FLOW ─(_SalesOrderItem)──► ZI_SO_ITEM
                                       │
                                       ▼
                        ZI_SO_DELIVERY_AGGR
                (teslimat miktarı + en son mal çıkış tarihi,
                 SalesOrder + SalesOrderItem bazında gruplanmış)
                                       │
                                       ▼
                     ZI_SO_DELIVERY_AGGR_HDR
                (aynısı, bir kez daha SalesOrder bazında toplanmış)
                                       │
             ┌─────────────────────────┴──────────────────────────┐
             ▼                                                    ▼
   ZI_SO_LIFECYCLE_BASE                             ZI_SO_LIFECYCLE_ITEM_BASE
   (header: LifecycleStage,                         (item: LifecycleStage,
    StageReferenceDate,                               StageReferenceDate,
    DaysInCurrentStage)                                DaysInCurrentStage)
             │                                                    │
             ▼                                                    ▼
     ZC_SO_LIFECYCLE  ─────────────── _Item ────────────►  ZC_SO_LIFECYCLE_ITEM
   (+ StageCriticality)              _SalesOrder  ◄────────────    (+ StageCriticality)
             │                                                    │
   ZC_SO_LIFECYCLE.ddlx                                ZC_SO_LIFECYCLE_ITEM.ddlx
   (List Report + Object Page facet'leri)               (Object Page item tablosu)
             │                                                    │
             └────────────────────────┬───────────────────────────┘
                                       ▼
                          ZUI_SO_LIFECYCLE (Service Definition)
                                       │
                                       ▼
                    OData V4 Service Binding (aktive + publish edilmiş)
                                       │
                                       ▼
                       Fiori Elements List Report + Object Page
```

`ZC_SO_LIFECYCLE` üzerindeki `_Item` association'ı ile `ZC_SO_LIFECYCLE_ITEM` üzerindeki `_SalesOrder` association'ı birbirine bakıyor — bu karşılıklı bağlantı, Object Page'in "Order Items" facet'inin bir siparişten kendi kalemlerine inebilmesini sağlayan tam olarak o şey, ve aynı zamanda tüm modelde gerçek bir döngüsel bağımlılığın olduğu tek yer (bu, aktivasyon sırasını etkilediği için kurulum rehberinde ele alınıyor).

## 4. Yaşam döngüsü aşamaları

İki base view de aynı altı aşamalı sınıflandırmayı çalıştırıyor — header view bunu VBAK'ın `LFSTK`/`FKSTK`'sinden okuyor, item view VBAP'ın `LFSTA`/`FKSTA`'sından (aynı değerler, kalem seviyesinde kaynak) — ve ikisi de siparişin fiilen içinde bulunduğu aşamaya uygun bir referans tarihi seçiyor, çünkü "bu ne kadar süredir bekliyor" sorusu ancak *neyi* beklediğini bildiğinizde bir anlam ifade ediyor.

| Aşama | Koşul | Referans tarihi |
|---|---|---|
| `ORDER_CREATED` | Teslimat durumu = `A` (henüz teslim edilmemiş) | Oluşturulma tarihi |
| `PARTIALLY_DELIVERED` | Teslimat durumu = `B` | Oluşturulma tarihi |
| `DELIVERED` | Teslimat durumu = `C`, ama mal çıkışı henüz fiilen gerçekleşmemiş | Oluşturulma tarihi |
| `GOODS_ISSUED` | Teslimat durumu = `C`, mal çıkışı gerçekleşmiş, fatura durumu = `A` (henüz faturalanmamış) | En son mal çıkış tarihi |
| `PARTIALLY_INVOICED` | Fatura durumu = `B` | En son mal çıkış tarihi |
| `INVOICED` | Fatura durumu = `C` | yok — gün sayısı, referans tarihi ne olursa olsun `0`'a zorlanıyor |

`DELIVERED` ile `GOODS_ISSUED` arasındaki ayrım, standart durum alanlarından tek başına anlaşılmayan kısım: `LFSTK`/`LFSTA` = `C` sadece "tam miktar için bir teslimat belgesi var" demek, malın fiilen depodan çıktığı anlamına gelmiyor. İki base view de bu yüzden ikisi arasında karar vermeden önce `LatestGoodsIssueDate`'i de kontrol ediyor (teslimat aggregation'ından geliyor, en nihayetinde LIKP'in gerçek mal çıkış tarihi `WADAT_IST`'inden) — henüz hiçbir mal hareketi olmamış bir teslimat, fiilen sevk edilmiş bir teslimattan maddi olarak farklı bir durum.

## 5. Aşama kritikliği (StageCriticality)

`ZC_SO_LIFECYCLE` ve `ZC_SO_LIFECYCLE_ITEM`'ın ikisi de `DaysInCurrentStage`'i, her aşama için bilerek farklı belirlenmiş eşiklerle bir Fiori criticality koduna (1 = kırmızı, 2 = sarı, 3 = yeşil) çeviriyor:

| Aşama | Yeşil (3) | Sarı (2) | Kırmızı (1) |
|---|---|---|---|
| `ORDER_CREATED` | 0–1 gün | 2–4 gün | 5+ gün |
| `PARTIALLY_DELIVERED` | 0–2 gün | 3–6 gün | 7+ gün |
| `DELIVERED` | 0 gün | 1–2 gün | 3+ gün |
| `GOODS_ISSUED` | 0–2 gün | 3–6 gün | 7+ gün |
| `PARTIALLY_INVOICED` | 0–4 gün | 5–9 gün | 10+ gün |
| `INVOICED` | her zaman yeşil | — | — |

Eşikler altı yerde aynı sayının tekrarı değil, çünkü aşamalar aynı aciliyeti taşımıyor. `DELIVERED`'da beklemek — bir teslimat var ama mal fiilen hareket etmemiş — neredeyse hemen (3. günde) kırmızıya dönecek şekilde tasarlanmış, çünkü bu genelde hızlıca dikkat çekmesi gereken bir depo yürütme sorunu. `PARTIALLY_INVOICED` ise tam tersine en fazla payı alıyor (kırmızıya dönmeden önce 9 güne kadar), çünkü faturalama döngüleri genelde toplu ya da periyodik bir takvimde çalışır, ve devam eden her faturayı 2. günde acil diye işaretlemek sadece gürültü olurdu. `INVOICED` her zaman yeşil çünkü artık peşine düşülecek bir şey kalmamış — sipariş yolculuğunu tamamlamış.

## 6. Teslimat aggregation'ı (neden iki seviye)

`ZI_SO_DELIVERY_AGGR`, `ZI_DLV_ITEM`'ı `SalesOrder` + `SalesOrderItem` bazında gruplayarak, sipariş kalemi başına tam olarak bir satır veriyor — o belirli kalemin en son mal çıkış tarihi ve toplam teslim edilen miktarı. Bu, `ZI_SO_LIFECYCLE_ITEM_BASE`'in `[0..1]` kardinalitesiyle doğrudan bağlanması için doğru granülarite: bir sipariş kaleminin arkasında birçok teslimat kalemi satırı olabilir (kısmi teslimatlar, birden fazla LIPS satırı), ama aggregation bunları item lifecycle view'ine ulaşmadan önce (sipariş, kalem) çifti başına tek bir satıra indirgemiş oluyor.

Header view'in farklı bir sorunu var: bir siparişin birçok kalemi olabilir, her kalemin de birçok teslimat satırı olabilir, yani sadece `SalesOrder` bazında gruplamak, ilkinin üzerine ikinci, daha kaba bir aggregation daha demek — `ZI_SO_DELIVERY_AGGR_HDR`, `ZI_SO_DELIVERY_AGGR`'ı bir kez daha, sadece `SalesOrder` bazında topluyor, özellikle sipariş başına tam olarak bir satıra indirgemek için. Bu ikinci toplama olmadan, header view'den kalem bazlı aggregation'a doğrudan bir `[0..1]` association ya teknik olarak yanlış olurdu (üç kalemli bir sipariş üç aggregation satırıyla eşleşebilirdi) ya da sessizce rastgele birini seçerdi — ikisi de "bu sipariş ne kadar süredir takılı kaldı" hesabının içinde saklanmasını istemeyeceğiniz türden şeyler. İki aggregation view'inin var olma sebebi, header ve item lifecycle view'lerinin her birinin veriyi *kendi* granülaritesine indirgenmiş olarak ihtiyaç duyması, aynı granülaritenin iki kez yeniden kullanılması değil.

## 7. Yetkilendirme (DCL)

`ZC_SO_LIFECYCLE_AUTH`, `ZC_SO_LIFECYCLE`'a erişimi standart SD yetki nesnesi **V_VBAK_VKO** (Satış Organizasyonu / Dağıtım Kanalı / Bölüm) üzerinden, `03` (görüntüleme) aktivitesine karşı kontrol ederek veriyor — bir kullanıcı sadece `SalesOrganization`/`DistributionChannel`/`Division` kombinasyonu kendi PFCG rolünün o nesne için gerçekten verdiğiyle eşleşen satırları görüyor. `VKORG`/`VTWEG`/`SPART`'ın `ZI_SO_HEADER` → `ZI_SO_LIFECYCLE_BASE` → `ZC_SO_LIFECYCLE` boyunca sonuna kadar taşınmasının nedeni tam olarak bu — yaşam döngüsü *hesaplamasının* kendisi bunlara hiç ihtiyaç duymasa bile — çünkü bir DCL sadece view'in fiilen dışarı açtığı alanlar üzerinde filtre yapabilir, yani bu üç alan, en tepedeki bu yetki kontrolünün referans verebileceği bir şey olsun diye her katman boyunca taşınıyor.

`ZC_SO_LIFECYCLE_ITEM_AUTH` bu kontrolü tekrarlamıyor. Filtre yapacağı kendi satış organizasyonu alanları yok — VBAP bunları taşımıyor — bunun yerine `inheriting conditions from entity ZC_SO_LIFECYCLE via association _SalesOrder` kullanıyor, yani bir kalem, kendi üst siparişi (`_SalesOrder` association'ı üzerinden ulaşılan) header'ın kendi kuralı altında görünür olduğunda görünür oluyor. Bu projenin tamamında elle senkronize tutulan iki değil, tam olarak tek bir yetkilendirme kuralı var — header kuralı bir gün değişirse, item view'in görünürlüğü de otomatik olarak onunla birlikte değişiyor, çünkü baştan beri ikinci, bağımsız bir kural değildi zaten.

## 8. Birkaç UI notu

- `LifecycleStage` ve `DaysInCurrentStage` üzerindeki kırmızı/sarı/yeşil renklendirme, metadata extension'lardaki `@UI.lineItem: [{ ..., criticality: 'StageCriticality' }]`'den geliyor ve consumption view'lerde hesaplanan `StageCriticality` alanına işaret ediyor. `StageCriticality`'nin kendisi `@UI.hidden: true` ile işaretli — sadece renklendirmeyi sürmek için var ve kendi başına bir sütun olarak hiç görünmesi amaçlanmıyor.
- `@Semantics.amount.currencyCode` / `@Semantics.quantity.unitOfMeasure`, consumption view'lerde duruyor (`NetValue`/`Currency`, `OrderQuantity`/`SalesUnit`, `ItemNetValue`/`Currency`), her `@UI` annotation'ı ise metadata extension'larda — bu, §1'de anlatılan ayrım. Bu aynı zamanda, prensipte, aynı consumption view'in tamamen farklı bir düzene sahip ikinci bir Fiori uygulaması tarafından, verinin semantik olarak ne olduğuna hiç dokunmadan yeniden kullanılabileceği anlamına geliyor.
- Object Page'in "Order Items" facet'i, `ZC_SO_LIFECYCLE.ddlx` içinde `targetElement: '_Item'` ile bir `#LINEITEM_REFERENCE` facet'i — header view'e hiçbir kalem verisini kopyalamıyor, sadece Fiori Elements'e "buraya, bu association'dan beslenen bir tablo çiz" diyor, o tablonun gerçek sütunları da `ZC_SO_LIFECYCLE_ITEM.ddlx`'in kendi `@UI.lineItem` annotation'larından geliyor.

## 9. Bilinçli olarak basitleştirilenler

- **Salt okunur, RAP behavior yok.** §1'de anlatıldı — bu uygulama okuyor, yazmıyor. İleride "takılı kalmış bir siparişe müdahale et" türünden bir özellik gelirse, bunun yeri bu view'lerin üzerine değil, üstüne oturacak bir RAP katmanı.
- **Zincir faturalamada bitiyor.** Ödeme ve mahsup (`BKPF`, `BSID`/`BSAD`) bu modelin parçası değil. `BSID`'nin kendisi S/4HANA'da gerçek bir tablo değil, bir uyumluluk (compatibility) view'i, ve bir faturadan kendi muhasebe belgesine giden bağlantı `BKPF-AWKEY` üzerinden geçiyor ki bu, bu yığındaki başka herhangi bir join'den daha dağınık ve daha az doğrudan. Kötü modellenmek yerine bilinçli olarak dışarıda bırakıldı ve burada doğal bir sonraki adım olarak not ediliyor (§10).
- **"Bugün" için `$session.system_date`.** İki base view de "şu an itibarıyla kaç gün" hesabı için bunu kullanıyor. En basit seçenek ve güncel S/4HANA sürümlerinde çalışıyor; bunun bir view entity içinde kabul edilmediği bir sürümde, yedek plan base view'lere bir tarih input parameter'ı eklemek (`with parameters p_key_date : abap.dats`) ve her tüketicinin bunu açıkça sağlaması.
- **Müşteri adı dışında value help yok.** `CustomerName` (KNA1'den `_Customer` üzerinden), modeldeki tek metin zenginleştirmesi — malzeme, satış organizasyonu ya da başka hiçbir şey için tanımlı bir F4 value help yok. List Report'ta filtreleme bugün ham kodlar üzerinden çalışıyor.

## 10. Olası genişletmeler

- **Ödeme/mahsup adımını eklemek**, order-to-cash resmini tamamlamak için — `BSID`/`BSAD`'den beslenen bir `INVOICED_UNPAID` / `PAID` ayrımı, §9'da belirtilen boşluğu kapatarak.
- **Aynı modelin üzerine RAP tabanlı, yazılabilir bir katman** — "yükselt", "depoyu dürt" ya da "takip edildi olarak işaretle" gibi aksiyonlar, yaşam döngüsünün kendisinin nasıl hesaplandığına dokunmadan siparişe karşı loglanarak.
- **Toplu aşama sayılarını gösteren bir Analytical List Page** (her aşamada kaç sipariş var, satış organizasyonu bazında) — mevcut sipariş-sipariş List Report'un üzerine oturan, yönetim seviyesinde bir görünüm olarak.
- **Bir sipariş kendi aşama eşiğini aştığında uyarı** — az önce kırmızıya dönmüş bir sipariş, birinin uygulamayı açıp fark etmesini beklemek yerine bir e-posta ya da bir SAP Business Workflow öğesi tetikleyebilir.
- **Malzeme, satış organizasyonu ve dağıtım kanalı için value help ve text association'lar**, filtre çubuğunu ham kodlardan daha kullanıcı dostu hale getirmek için.