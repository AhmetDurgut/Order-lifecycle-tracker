# Sales Order Lifecycle Tracker — CDS + OData Setup Guide

# ENGLISH

## 1. Overview

This project is a stack of CDS views that turns raw sales order tables (VBAK, VBAP, LIPS, VBRP, VBFA...) into a "lifecycle" reading of every sales order and every sales order item — what stage it's in (created, delivered, invoiced...), how many days it's been sitting there, and whether that's still healthy or worth a look. It ends in a Fiori Elements List Report + Object Page, built entirely from annotations, with no hand-written UI code.

What we're deploying, in total:

| Layer | Count | Objects |
|---|---|---|
| Interface views (I_) | 9 | ZI_SO_HEADER, ZI_SO_ITEM, ZI_DLV_ITEM, ZI_BIL_ITEM, ZI_DOC_FLOW, ZI_SO_DELIVERY_AGGR, ZI_SO_DELIVERY_AGGR_HDR, ZI_SO_LIFECYCLE_BASE, ZI_SO_LIFECYCLE_ITEM_BASE |
| Consumption views (C_) | 2 | ZC_SO_LIFECYCLE, ZC_SO_LIFECYCLE_ITEM |
| Metadata extensions | 2 | ZC_SO_LIFECYCLE (.ddlx), ZC_SO_LIFECYCLE_ITEM (.ddlx) |
| Access control (DCL) | 2 | ZC_SO_LIFECYCLE_AUTH, ZC_SO_LIFECYCLE_ITEM_AUTH |
| Service definition | 1 | ZUI_SO_LIFECYCLE |
| Service binding | 1 | ZUI_SO_LIFECYCLE_O4 (created directly in the system — not a file in this repo) |

**Why order matters:** CDS objects form a dependency chain, exactly like ABAP classes do. A view that selects from another view, or has an association pointing at one, cannot be activated until that other view already exists as an active object in the system. Try it out of order and ADT will refuse to activate, with an error like *"Data source ZI_SO_HEADER is unknown"* or *"Type ZI_SO_ITEM is not active"*. The fix is never to "work around" the error — it's simply to go activate the dependency first, then come back. Sections 3–7 below give you the exact order that avoids this entirely.

**Tools you need:**
- **Eclipse with ABAP Development Tools (ADT)** installed. If you don't have it yet: open Eclipse → **Help → Install New Software...** → add the SAP ADT update site (`https://tools.hana.ondemand.com/latest`) → select "ABAP Development Tools" → Install → restart Eclipse.
- A working connection to an **S/4HANA system** (a system alias / connection already configured in ADT's Project Explorer, with a user that has developer authorization).
- An **ABAP package** to put all the objects in.

## 2. Prerequisites

1. Open the **ABAP Perspective** in Eclipse (top-right corner, or Window → Perspective → Open Perspective → Other → ABAP).
2. In the **Project Explorer**, expand your system connection, right-click your favorite packages node (or the system node) → **New → ABAP Package**.
3. Name it something like `ZORDER_LIFECYCLE`, give it a short description ("Sales Order Lifecycle Tracker"), and choose **Add to favorite packages** so it's easy to find again.
4. If your system prompts for a **transport request** when you save the package (this is normal on a real development system — it's how changes travel from Dev to QA to Production), create a new one or reuse an existing one for this project. On a personal trial/practice system you may instead be offered `$TMP` (local object, no transport) — that's fine for a portfolio project.
5. **Every object in this guide goes into this one package.** Keeping it all in one place makes the dependency order easy to see in the Project Explorer tree, and makes it trivial to transport the whole feature together later.

## 3. Creating the CDS Views (the dependency order)

### How to create a Data Definition in ADT (repeat for every view below)

1. Right-click your package (`ZORDER_LIFECYCLE`) → **New → Other ABAP Repository Object**.
2. In the search box, type `Data Definition` and select it → **Next**.
3. Enter the exact name (e.g. `ZI_SO_HEADER`) and a short description → **Next**.
4. ADT offers a template picker. Choose **"Define View Entity"** (or simply pick an empty/blank template if your version doesn't show this exact wording) → **Finish**.
5. A skeleton opens in the editor. Select everything (Ctrl+A), delete it, and paste in the **full contents** of the matching `.ddls` file from `src/interface/` or `src/consumption/`.
6. Save (Ctrl+S) — pick your transport request/package if asked.
7. Activate with **Ctrl+F3**, or the green/yellow "Activate" toolbar icon. Watch the **Problems** view at the bottom for errors.

### The order that avoids dependency errors

**Group 1 — read the raw tables directly.** These only need VBAK/VBAP/LIPS/VBRP/VBFA to exist (which they always do, they're standard SAP tables), but two of them also associate to each other, so there's a small order inside this group too:

1. `ZI_SO_HEADER` (reads VBAK) — no dependencies, create this first.
2. `ZI_SO_ITEM` (reads VBAP) — its `_SalesOrder` association points at `ZI_SO_HEADER`, so `ZI_SO_HEADER` must already be active.
3. `ZI_DLV_ITEM`, `ZI_BIL_ITEM`, `ZI_DOC_FLOW` — each of these associates to `ZI_SO_ITEM`, so they need it active first. The three of them don't depend on each other, so any order among these three is fine.

**Group 2 — the delivery aggregation, item level:**

4. `ZI_SO_DELIVERY_AGGR` — selects from `ZI_DLV_ITEM` and groups it by sales order + item, so `ZI_DLV_ITEM` must be active first.

**Group 3 — the delivery aggregation, header level:**

5. `ZI_SO_DELIVERY_AGGR_HDR` — rolls `ZI_SO_DELIVERY_AGGR` up one more level (by sales order only), so it needs step 4 done first.

**Group 4 — the lifecycle base views (the calculation layer):**

6. `ZI_SO_LIFECYCLE_BASE` — depends on `ZI_SO_HEADER` and `ZI_SO_DELIVERY_AGGR_HDR`.
7. `ZI_SO_LIFECYCLE_ITEM_BASE` — depends on `ZI_SO_ITEM`, `ZI_SO_DELIVERY_AGGR`, **and** `ZI_SO_HEADER` (it falls back to the header's `CreationDate` via its own `_SalesOrder` association, since VBAP has no item-level creation date). Make sure all three are active before this one.

**Group 5 — the consumption views:**

8. `ZC_SO_LIFECYCLE` and `ZC_SO_LIFECYCLE_ITEM` — both depend on everything above, **and on each other** (the header view has an association to the item view, and the item view has an association back to the header view). This is a genuine circular reference between the two, so treat them as a pair rather than a strict "first/second" order:
   - Create both Data Definition objects and paste their content in (steps 1–6 of "How to create a Data Definition" above), and **save both**, but don't try to activate just one yet.
   - Then select **both** of them together in the Project Explorer (Ctrl+click each one) → right-click → **Activate**. Because ADT now knows about both (even if neither was active before), it can resolve the mutual reference in a single pass.
   - If you activate only one of them in isolation while the other doesn't exist in the system at all yet, you'll get an error like *"Data source ZC_SO_LIFECYCLE_ITEM is unknown"* (or the mirror image for the other view) — that's expected, not a bug. Save both first, then activate together.

**If you get it out of order:** the error message always names the missing dependency (e.g. *"View ZI_SO_DELIVERY_AGGR_HDR is not active"*). Go find that object in the Project Explorer, activate it, and come back to retry the one that failed — nothing is broken, you just did two steps in the wrong sequence.

## 4. Creating the Metadata Extensions

Metadata Extensions carry the `@UI...` annotations (facets, line items, criticality colors) *without* touching the consumption view's own source — that's exactly why `ZC_SO_LIFECYCLE` and `ZC_SO_LIFECYCLE_ITEM` both declare `@Metadata.allowExtensions: true`. Without that annotation on the view, an extension targeting it simply cannot activate.

**Steps (repeat for both):**

1. Right-click your package → **New → Other ABAP Repository Object** → search `Metadata Extension` → **Next**.
2. Name it `ZC_SO_LIFECYCLE` (matching the view it extends makes it easy to find later), short description, → when asked which Data Definition it extends, pick `ZC_SO_LIFECYCLE` → **Finish**.
3. Delete the generated skeleton, paste in the full content of `src/metadata/ZC_SO_LIFECYCLE.ddlx`.
4. Save and activate (Ctrl+F3).
5. Repeat the same three steps for `ZC_SO_LIFECYCLE_ITEM.ddlx`, extending the `ZC_SO_LIFECYCLE_ITEM` view.

**Common mistake:** if the consumption view is missing `@Metadata.allowExtensions: true`, activating the extension fails with something like *"View ZC_SO_LIFECYCLE does not allow metadata extensions"*. The fix is to open the view, add the annotation, reactivate the view, then retry the extension. In this project both consumption views already carry the annotation, so this shouldn't come up — but it's the first thing to check if it does.

## 5. Creating the Access Controls (DCL)

**Steps (repeat for both):**

1. Right-click your package → **New → Other ABAP Repository Object** → search `Access Control` → **Next**.
2. For the name, use the name that appears after `define role` **inside** the file — not the file's own name. The header file is named `ZC_SO_LIFECYCLE.dcl` for readability, but its content says `define role ZC_SO_LIFECYCLE_AUTH { ... }` — so the ADT object name you type here is **`ZC_SO_LIFECYCLE_AUTH`**. Likewise the item one is **`ZC_SO_LIFECYCLE_ITEM_AUTH`**.
3. Paste in the file's full content, save, activate (Ctrl+F3).

**Order:** create `ZC_SO_LIFECYCLE_AUTH` (the header role) first, then `ZC_SO_LIFECYCLE_ITEM_AUTH`. The item role's `where inheriting conditions from entity ZC_SO_LIFECYCLE via association _SalesOrder` clause reads the header's authorization rule through the `_SalesOrder` association, so the header role needs to already exist and be active.

**What this actually does:** the header DCL uses the standard SD authorization object **V_VBAK_VKO** (Sales Organization / Distribution Channel / Division, activity `03` = display). For any user to see a single row through this service, that user's **PFCG role** must grant them `V_VBAK_VKO` with at least one Sales Org / Distribution Channel / Division combination and activity `03`. This is a real authorization check, not a formality — set it up in the test user's role before you go looking for "missing" data.

**Important thing to remember:** with `@AccessControl.authorizationCheck: #CHECK` on the view and this DCL in place, a user who has *no* `V_VBAK_VKO` authorization at all will simply see an **empty list** — no error, no warning, just zero rows. That's the DCL working exactly as designed, not a bug to chase.

## 6. Creating the Service Definition

The service definition is already written for you at `src/service/ZUI_SO_LIFECYCLE.srvd` — you just need to bring it into the system the same way as the views above.

1. Right-click your package → **New → Other ABAP Repository Object** → search `Service Definition` → **Next**.
2. Name it `ZUI_SO_LIFECYCLE`, short description "Sales Order Lifecycle Service" → **Finish**.
3. Delete the generated skeleton, paste in the full content of `src/service/ZUI_SO_LIFECYCLE.srvd`.
4. Save and activate.

This exposes `ZC_SO_LIFECYCLE` as the OData entity set `SalesOrderLifecycle`, and `ZC_SO_LIFECYCLE_ITEM` as `SalesOrderLifecycleItem`. Both consumption views (and therefore the whole chain beneath them) must already be active before this step, since the service definition references them by name.

## 7. Creating and Publishing the Service Binding (the part that isn't in Git)

This is the most important hands-on section, and the one bit of this whole project you will **not** find as a file anywhere in the repo. Here's why: a service binding's job is to say "this service definition is now reachable, at this specific URL, in this specific system" — and that reachable/published state is something the system tracks internally (like a light switch), not a piece of source code. There's nothing meaningful to check into Git; every system you deploy to needs its own binding created and published locally.

**Steps:**

1. In the Project Explorer, find your activated `ZUI_SO_LIFECYCLE` service definition, right-click it → **New Service Binding**.
2. Name: `ZUI_SO_LIFECYCLE_O4`. Description: "Sales Order Lifecycle OData V4 Service".
3. **Binding Type:** from the dropdown, choose **"OData V4 - UI"** (not "OData V2 - UI" — this project targets V4).
4. Click **Finish**. The Service Binding editor opens, listing the entity sets that come from the service definition — `SalesOrderLifecycle` and `SalesOrderLifecycleItem`.
5. **Activate** the binding first (Ctrl+F3, or the Activate toolbar button) — this makes the binding object itself a valid repository object.
6. Now click **Publish** (sometimes shown as "Publish Locally" or "Publish Local Service Endpoint") in the editor's toolbar. **This step is easy to forget, and skipping it is the #1 reason a freshly built service "doesn't work"** — an activated-but-unpublished binding exists as an object in the system, but no HTTP endpoint is actually switched on for it, so nothing outside ADT can reach it and the Fiori preview will fail to load.
7. Once published, the entity sets in the editor show a green "Published" status, and each row gets a little **Preview** icon next to it.

## 8. Previewing the Fiori Elements App

1. In the Service Binding editor, click on the `SalesOrderLifecycle` entity set row, then click the **Preview** button (or the preview icon next to the row).
2. This opens a browser tab running a full Fiori Elements **List Report**, generated entirely from the `@UI` annotations in `ZC_SO_LIFECYCLE.ddlx` — you didn't write a single line of UI code for this.
3. What to expect:
   - A **filter bar** with Sales Order, Customer, Lifecycle Stage, Sales Organization, and Creation Date (these are the fields marked `@UI.selectionField`).
   - A **table** with the lifecycle columns, where `LifecycleStage` and `DaysInCurrentStage` are colored red/yellow/green according to `StageCriticality`.
   - Clicking a row opens the **Object Page**, with a "General Information" section, a "Lifecycle Status" section, and an "Order Items" table (the item facet, driven by the `_Item` association) showing each item's own stage and criticality.
4. **If the list comes back empty ("No data found"):** this is almost always one of two things, and neither is a code bug — either the underlying tables (VBAK/VBAP/LIKP/VBRK/...) genuinely have no sales orders that match, or the logged-in user isn't authorized for any Sales Organization under `V_VBAK_VKO` (see Section 5). Check the authorization first, since it fails silently.

## 9. Checking the OData Service Directly (optional)

If you want to confirm the service is reachable outside of the ADT preview:

- **Metadata URL pattern** for an OData V4 UI service looks roughly like:
  `/sap/opu/odata4/sap/zui_so_lifecycle/srvd_a2x/sap/zui_so_lifecycle/0001/$metadata`
  The exact path segments (service group ID, version number) can differ slightly by system and release, so don't type this from memory — copy the actual URL shown next to the entity set in the Service Binding editor (there's usually a "copy URL" or "show endpoint" action), and just append `/$metadata` to the service root.
- Opening that `$metadata` URL directly in a browser should return an XML (EDMX) document describing the `SalesOrderLifecycle` and `SalesOrderLifecycleItem` entity sets, their properties, and the navigation between them.
- To double-check the service is registered and active from the Gateway/administration side, you can look it up via `/IWFND/MAINT_SERVICE` (the classic OData service registry) — though for OData V4 services created this way, the **Service Binding editor's own "Published" status is the more direct and reliable source of truth**; treat the Gateway transaction as a secondary sanity check, not the primary one.

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "View not active" / "does not exist" during activation | You activated a view before one of its dependencies (wrong order) | Find the named dependency in Section 3's order, activate it first, then retry |
| Metadata extension won't activate | The consumption view is missing `@Metadata.allowExtensions: true` | Add the annotation to the view, reactivate the view, then the extension |
| "Data source ... is unknown" when activating `ZC_SO_LIFECYCLE` or `ZC_SO_LIFECYCLE_ITEM` alone | The two consumption views reference each other (circular association) and only one exists so far | Create and save both first, then select both and activate together (Section 3, Group 5) |
| List Report preview shows "No data found" | Either no matching rows in VBAK/VBAP/etc., or the user lacks `V_VBAK_VKO` authorization | Check the user's PFCG role for `V_VBAK_VKO` (Section 5) before assuming it's a code problem |
| Preview won't load / service unreachable | The binding was activated but never **Published** (Section 7, step 6) | Open the Service Binding editor and click Publish |
| Criticality colors (red/yellow/green) not showing | `@UI.criticality` doesn't point at `StageCriticality`, or the view doesn't expose that field | Check the `.ddlx` file's `criticality:` references and that `StageCriticality` is in the view's field list |
| `dats_days_between` / `$session.system_date` behaves oddly or isn't accepted on an older release | Some older S/4HANA releases restrict `$session.system_date` usage inside a view entity | As a fallback, add a date **input parameter** to the base view (`with parameters p_key_date : abap.dats`) and reference `$parameters.p_key_date` instead — the consuming views would then need to supply it |

---

---

# TÜRKÇE

## 1. Genel Bakış

Bu proje, ham satış siparişi tablolarını (VBAK, VBAP, LIPS, VBRP, VBFA...) her satış siparişi ve her sipariş kalemi için bir "yaşam döngüsü" okumasına dönüştüren bir CDS view yığınıdır — hangi aşamada olduğu (oluşturuldu, teslim edildi, faturalandı...), o aşamada kaç gündür beklediği ve bunun hâlâ normal mi yoksa dikkat gerektiren bir durum mu olduğu. Sonuç, tamamen annotation'lardan üretilen, tek satır elle yazılmış UI kodu içermeyen bir Fiori Elements List Report + Object Page uygulamasıdır.

Toplamda kuracağımız nesneler:

| Katman | Adet | Nesneler |
|---|---|---|
| Interface view'ler (I_) | 9 | ZI_SO_HEADER, ZI_SO_ITEM, ZI_DLV_ITEM, ZI_BIL_ITEM, ZI_DOC_FLOW, ZI_SO_DELIVERY_AGGR, ZI_SO_DELIVERY_AGGR_HDR, ZI_SO_LIFECYCLE_BASE, ZI_SO_LIFECYCLE_ITEM_BASE |
| Consumption view'ler (C_) | 2 | ZC_SO_LIFECYCLE, ZC_SO_LIFECYCLE_ITEM |
| Metadata Extension | 2 | ZC_SO_LIFECYCLE (.ddlx), ZC_SO_LIFECYCLE_ITEM (.ddlx) |
| Access Control (DCL) | 2 | ZC_SO_LIFECYCLE_AUTH, ZC_SO_LIFECYCLE_ITEM_AUTH |
| Service Definition | 1 | ZUI_SO_LIFECYCLE |
| Service Binding | 1 | ZUI_SO_LIFECYCLE_O4 (doğrudan sistemde oluşturulur — bu repoda bir dosya olarak bulunmaz) |

**Sıranın neden önemli olduğu:** CDS nesneleri de, ABAP sınıfları gibi, bir bağımlılık zinciri oluşturur. Bir view, başka bir view'den veri okuyorsa (select from) ya da ona bir association ile bağlanıyorsa, o diğer view sistemde zaten aktif bir nesne olarak durmadan aktive edilemez. Sırayı bozup denerseniz ADT aktivasyonu reddeder ve *"Data source ZI_SO_HEADER is unknown"* ya da *"Type ZI_SO_ITEM is not active"* gibi bir hata verir. Bu hatanın çözümü asla bir "atlatma" yolu bulmak değildir — sadece önce eksik olan bağımlılığı gidip aktive etmek, sonra geri dönmektir. Aşağıdaki 3–7. bölümler, bu hatayı baştan tamamen önleyen doğru sırayı veriyor.

**İhtiyacınız olan araçlar:**
- **ABAP Development Tools (ADT) yüklü bir Eclipse.** Henüz yoksa: Eclipse'i açın → **Help → Install New Software...** → SAP ADT update site'ını ekleyin (`https://tools.hana.ondemand.com/latest`) → "ABAP Development Tools" seçin → Install → Eclipse'i yeniden başlatın.
- Çalışan bir **S/4HANA sistem bağlantısı** (ADT'nin Project Explorer'ında zaten tanımlı bir sistem/bağlantı, geliştirici yetkisi olan bir kullanıcıyla).
- Tüm nesnelerin içine konacağı bir **ABAP paketi**.

## 2. Ön Koşullar

1. Eclipse'te **ABAP Perspective**'ini açın (sağ üst köşe, ya da Window → Perspective → Open Perspective → Other → ABAP).
2. **Project Explorer**'da sistem bağlantınızı genişletin, favori paketler düğümüne (ya da sistem düğümüne) sağ tıklayın → **New → ABAP Package**.
3. Paketi `ZORDER_LIFECYCLE` gibi bir isimle oluşturun, kısa bir açıklama girin ("Sales Order Lifecycle Tracker") ve **Add to favorite packages** seçeneğini işaretleyin ki sonra kolayca bulabilesiniz.
4. Paketi kaydederken sisteminiz bir **transport request** isterse (gerçek bir geliştirme sisteminde bu normaldir — değişikliklerin Dev'den QA'ya, oradan Production'a taşınma yoludur), yeni bir tane oluşturun ya da bu proje için var olan birini kullanın. Kişisel/deneme bir sistemdeyseniz size `$TMP` (lokal nesne, transport gerektirmez) önerilebilir — portföy projesi için bu gayet uygundur.
5. **Bu rehberdeki her nesne tek bir bu pakete girecek.** Her şeyi tek yerde tutmak, Project Explorer ağacında bağımlılık sırasını görmeyi kolaylaştırır ve ileride tüm özelliği birlikte transport etmeyi de basitleştirir.

## 3. CDS View'lerinin Oluşturulması (bağımlılık sırası)

### ADT'de bir Data Definition nasıl oluşturulur (aşağıdaki her view için tekrarlanacak)

1. Paketinize (`ZORDER_LIFECYCLE`) sağ tıklayın → **New → Other ABAP Repository Object**.
2. Arama kutusuna `Data Definition` yazın ve seçin → **Next**.
3. Tam ismi girin (örn. `ZI_SO_HEADER`) ve kısa bir açıklama yazın → **Next**.
4. ADT size bir şablon seçimi sunar. **"Define View Entity"** seçin (sürümünüzde bu tam ifade görünmüyorsa boş/basit bir şablon da yeterlidir) → **Finish**.
5. Editörde bir iskelet açılır. Tümünü seçip (Ctrl+A) silin, `src/interface/` ya da `src/consumption/` klasöründeki karşılık gelen `.ddls` dosyasının **tüm içeriğini** yapıştırın.
6. Kaydedin (Ctrl+S) — sorulursa transport request/paketinizi seçin.
7. **Ctrl+F3** ile ya da araç çubuğundaki yeşil-sarı "Activate" ikonuyla aktive edin. Alt taraftaki **Problems** görünümünü hatalar için kontrol edin.

### Bağımlılık hatasına düşmeyen sıra

**Grup 1 — doğrudan ham tabloları okuyanlar.** Bunlar sadece VBAK/VBAP/LIPS/VBRP/VBFA'nın var olmasını gerektirir (bunlar zaten her sistemde standart olarak bulunur), ama ikisi birbirine de bağlandığı için bu grubun içinde de küçük bir sıra var:

1. `ZI_SO_HEADER` (VBAK'ı okur) — hiçbir bağımlılığı yok, önce bunu oluşturun.
2. `ZI_SO_ITEM` (VBAP'ı okur) — `_SalesOrder` association'ı `ZI_SO_HEADER`'a bakıyor, o yüzden `ZI_SO_HEADER` önce aktif olmalı.
3. `ZI_DLV_ITEM`, `ZI_BIL_ITEM`, `ZI_DOC_FLOW` — her biri `ZI_SO_ITEM`'a bağlanıyor, dolayısıyla onun önce aktif olması gerekiyor. Bu üçü birbirine bağımlı değil, aralarındaki sıra önemsiz.

**Grup 2 — teslimat toplulaştırması, kalem seviyesi:**

4. `ZI_SO_DELIVERY_AGGR` — `ZI_DLV_ITEM`'dan veri okuyup sipariş + kalem bazında gruplandırır, o yüzden `ZI_DLV_ITEM` önce aktif olmalı.

**Grup 3 — teslimat toplulaştırması, header seviyesi:**

5. `ZI_SO_DELIVERY_AGGR_HDR` — `ZI_SO_DELIVERY_AGGR`'ı bir seviye daha (sadece sipariş bazında) toplar, o yüzden 4. adım tamamlanmış olmalı.

**Grup 4 — yaşam döngüsü temel (base) view'leri (hesaplama katmanı):**

6. `ZI_SO_LIFECYCLE_BASE` — `ZI_SO_HEADER` ve `ZI_SO_DELIVERY_AGGR_HDR`'a bağımlı.
7. `ZI_SO_LIFECYCLE_ITEM_BASE` — `ZI_SO_ITEM`, `ZI_SO_DELIVERY_AGGR` **ve** `ZI_SO_HEADER`'a bağımlı (VBAP'ta kalem seviyesinde bir oluşturulma tarihi olmadığı için, kendi `_SalesOrder` association'ı üzerinden header'ın `CreationDate`'ine geri düşer). Bu üçünün de aktif olduğundan emin olun.

**Grup 5 — consumption view'leri:**

8. `ZC_SO_LIFECYCLE` ve `ZC_SO_LIFECYCLE_ITEM` — ikisi de yukarıdaki her şeye **ve birbirine** bağımlı (header view'in item view'e bir association'ı var, item view'in de header view'e geri dönen bir association'ı var). Bu, aralarında gerçek bir döngüsel (circular) referans demek, dolayısıyla bunları katı bir "önce/sonra" sırasıyla değil, bir çift olarak ele alın:
   - İkisinin de Data Definition nesnesini oluşturup içeriklerini yapıştırın (yukarıdaki "Data Definition nasıl oluşturulur" adımları 1–6), **ikisini de kaydedin**, ama henüz sadece birini aktive etmeye çalışmayın.
   - Ardından Project Explorer'da **ikisini birlikte** seçin (her birine Ctrl+tıklayarak) → sağ tıklayın → **Activate**. ADT artık ikisini de bildiği için (hiçbiri daha önce aktif olmasa bile), karşılıklı referansı tek bir geçişte çözebilir.
   - Diğeri sistemde henüz hiç yokken sadece birini tek başına aktive etmeye çalışırsanız, *"Data source ZC_SO_LIFECYCLE_ITEM is unknown"* (ya da diğer view için aynısının tersi) gibi bir hata alırsınız — bu beklenen bir durumdur, hata değil. Önce ikisini de kaydedin, sonra birlikte aktive edin.

**Sırayı bozarsanız:** hata mesajı her zaman eksik olan bağımlılığın adını verir (örn. *"View ZI_SO_DELIVERY_AGGR_HDR is not active"*). Project Explorer'da o nesneyi bulun, aktive edin, sonra başarısız olan adıma geri dönüp tekrar deneyin — hiçbir şey bozulmadı, sadece iki adımı yanlış sırada yaptınız.

## 4. Metadata Extension'ların Oluşturulması

Metadata Extension'lar, `@UI...` annotation'larını (facet'ler, satır öğeleri, criticality renkleri) consumption view'in **kendi kaynak koduna dokunmadan** taşır — `ZC_SO_LIFECYCLE` ve `ZC_SO_LIFECYCLE_ITEM`'ın ikisinin de `@Metadata.allowExtensions: true` tanımlamasının nedeni tam olarak budur. View üzerinde bu annotation yoksa, ona yönelik bir extension hiçbir şekilde aktive edilemez.

**Adımlar (ikisi için de tekrarlayın):**

1. Paketinize sağ tıklayın → **New → Other ABAP Repository Object** → `Metadata Extension` arayın → **Next**.
2. İsim olarak `ZC_SO_LIFECYCLE` girin (uzattığı view ile aynı isim olması sonradan bulmayı kolaylaştırır), kısa açıklama girin → hangi Data Definition'ı uzattığı sorulduğunda `ZC_SO_LIFECYCLE`'ı seçin → **Finish**.
3. Oluşan iskeleti silin, `src/metadata/ZC_SO_LIFECYCLE.ddlx` dosyasının tüm içeriğini yapıştırın.
4. Kaydedin ve aktive edin (Ctrl+F3).
5. Aynı üç adımı `ZC_SO_LIFECYCLE_ITEM.ddlx` için, `ZC_SO_LIFECYCLE_ITEM` view'ini uzatacak şekilde tekrarlayın.

**Sık yapılan hata:** consumption view'de `@Metadata.allowExtensions: true` eksikse, extension'ı aktive etmeye çalıştığınızda *"View ZC_SO_LIFECYCLE does not allow metadata extensions"* gibi bir hata alırsınız. Çözüm: view'i açın, annotation'ı ekleyin, view'i yeniden aktive edin, sonra extension'ı tekrar deneyin. Bu projede her iki consumption view'de de bu annotation zaten mevcut, yani normalde bu sorunla karşılaşmamalısınız — ama karşılaşırsanız ilk kontrol edeceğiniz yer burasıdır.

## 5. Access Control'lerin (DCL) Oluşturulması

**Adımlar (ikisi için de tekrarlayın):**

1. Paketinize sağ tıklayın → **New → Other ABAP Repository Object** → `Access Control` arayın → **Next**.
2. İsim olarak, dosyanın kendi adını değil, dosyanın **içinde** `define role` ifadesinden sonra gelen ismi kullanın. Header dosyası okunabilirlik için `ZC_SO_LIFECYCLE.dcl` olarak adlandırılmış, ama içeriği `define role ZC_SO_LIFECYCLE_AUTH { ... }` diyor — yani burada gireceğiniz ADT nesne adı **`ZC_SO_LIFECYCLE_AUTH`** olmalı. Aynı şekilde item için de **`ZC_SO_LIFECYCLE_ITEM_AUTH`**.
3. Dosyanın tüm içeriğini yapıştırın, kaydedin, aktive edin (Ctrl+F3).

**Sıra:** önce `ZC_SO_LIFECYCLE_AUTH`'ı (header rolü), sonra `ZC_SO_LIFECYCLE_ITEM_AUTH`'ı oluşturun. Item rolündeki `where inheriting conditions from entity ZC_SO_LIFECYCLE via association _SalesOrder` ifadesi, header'ın yetkilendirme kuralını `_SalesOrder` association'ı üzerinden okuduğu için, header rolünün önceden var ve aktif olması gerekir.

**Bunun gerçekte ne yaptığı:** header DCL, standart SD yetki nesnesi **V_VBAK_VKO**'yu kullanıyor (Satış Organizasyonu / Dağıtım Kanalı / Bölüm, aktivite `03` = görüntüleme). Bu servis üzerinden herhangi bir kullanıcının tek bir satır görebilmesi için, o kullanıcının **PFCG rolünde** en az bir Satış Organizasyonu / Dağıtım Kanalı / Bölüm kombinasyonu için `V_VBAK_VKO` yetkisi ve `03` aktivitesi tanımlı olmalı. Bu gerçek bir yetki kontrolüdür, formalite değildir — "kayıp" veri aramaya başlamadan önce test kullanıcınızın rolünde bunu ayarlayın.

**Aklınızda tutmanız gereken önemli nokta:** view üzerinde `@AccessControl.authorizationCheck: #CHECK` ve bu DCL yerindeyken, `V_VBAK_VKO` yetkisi hiç olmayan bir kullanıcı basitçe **boş bir liste** görür — hata yok, uyarı yok, sadece sıfır satır. Bu, DCL'in tam olarak tasarlandığı gibi çalıştığının göstergesidir, peşine düşülecek bir hata değildir.

## 6. Service Definition'ın Oluşturulması

Service definition sizin için zaten `src/service/ZUI_SO_LIFECYCLE.srvd` dosyasında hazır — sadece yukarıdaki view'lerle aynı şekilde sisteme taşımanız gerekiyor.

1. Paketinize sağ tıklayın → **New → Other ABAP Repository Object** → `Service Definition` arayın → **Next**.
2. İsim olarak `ZUI_SO_LIFECYCLE`, kısa açıklama "Sales Order Lifecycle Service" girin → **Finish**.
3. Oluşan iskeleti silin, `src/service/ZUI_SO_LIFECYCLE.srvd` dosyasının tüm içeriğini yapıştırın.
4. Kaydedin ve aktive edin.

Bu, `ZC_SO_LIFECYCLE`'ı `SalesOrderLifecycle` adlı OData entity set'i olarak, `ZC_SO_LIFECYCLE_ITEM`'ı da `SalesOrderLifecycleItem` olarak dışarı açar. Service definition ikisine de isimleriyle referans verdiği için, bu adımdan önce her iki consumption view'in de (ve dolayısıyla altlarındaki tüm zincirin de) aktif olması gerekir.

## 7. Service Binding'in Oluşturulması ve Publish Edilmesi (Git'te bulunmayan kısım)

Bu, elle yapılan işlemler arasında en kritik bölüm ve bu projenin, repo içinde **bir dosya olarak hiçbir yerde bulamayacağınız** tek parçası. Nedeni şu: bir service binding'in görevi "bu service definition artık şu sistemde, şu belirli URL'de erişilebilir durumda" demektir — ve bu erişilebilir/publish edilmiş durum, sistemin dahili olarak takip ettiği bir şeydir (bir elektrik anahtarı gibi), kaynak kod parçası değildir. Git'e commit edilecek anlamlı bir şey yoktur; deploy ettiğiniz her sistemde binding'in kendi kendine, yerel olarak oluşturulup publish edilmesi gerekir.

**Adımlar:**

1. Project Explorer'da aktive ettiğiniz `ZUI_SO_LIFECYCLE` service definition'ını bulun, sağ tıklayın → **New Service Binding**.
2. İsim: `ZUI_SO_LIFECYCLE_O4`. Açıklama: "Sales Order Lifecycle OData V4 Service".
3. **Binding Type:** açılır listeden **"OData V4 - UI"** seçin ("OData V2 - UI" değil — bu proje V4 hedefliyor).
4. **Finish**'e tıklayın. Service Binding editörü açılır ve service definition'dan gelen entity set'leri listeler — `SalesOrderLifecycle` ve `SalesOrderLifecycleItem`.
5. Önce binding'i **Activate** edin (Ctrl+F3, ya da Activate araç çubuğu düğmesi) — bu, binding nesnesinin kendisini geçerli bir repository nesnesi haline getirir.
6. Şimdi editörün araç çubuğunda **Publish** düğmesine tıklayın (bazı sürümlerde "Publish Locally" ya da "Publish Local Service Endpoint" olarak görünür). **Bu adım unutulması çok kolay bir adımdır ve yeni oluşturulmuş bir servisin "çalışmamasının" bir numaralı nedenidir** — aktive edilmiş ama publish edilmemiş bir binding sistemde bir nesne olarak durur, ama onun için gerçekten açılmış bir HTTP endpoint'i yoktur; bu yüzden ADT dışından hiçbir şey ona ulaşamaz ve Fiori önizlemesi yüklenmez.
7. Publish edildikten sonra, editördeki entity set'ler yeşil bir "Published" durumu gösterir ve her satırın yanında küçük bir **Preview** ikonu belirir.

## 8. Fiori Elements Uygulamasını Önizleme

1. Service Binding editöründe `SalesOrderLifecycle` entity set satırına tıklayın, ardından **Preview** düğmesine (ya da satırın yanındaki önizleme ikonuna) tıklayın.
2. Bu, tamamen `ZC_SO_LIFECYCLE.ddlx` içindeki `@UI` annotation'larından üretilmiş, tam bir Fiori Elements **List Report**'unu bir tarayıcı sekmesinde açar — bunun için tek bir satır UI kodu yazmadınız.
3. Beklenecekler:
   - Sales Order, Customer, Lifecycle Stage, Sales Organization ve Creation Date alanlarını içeren bir **filtre çubuğu** (bunlar `@UI.selectionField` ile işaretlenmiş alanlar).
   - `LifecycleStage` ve `DaysInCurrentStage`'in `StageCriticality`'e göre kırmızı/sarı/yeşil renklendiği bir **tablo**.
   - Bir satıra tıklandığında açılan, "General Information", "Lifecycle Status" bölümlerini ve her kalemin kendi aşamasını/renk kodunu gösteren "Order Items" tablosunu (`_Item` association'ından gelen facet) içeren bir **Object Page**.
4. **Liste boş dönerse ("No data found"):** bunun neredeyse her zaman iki nedeninden biri vardır ve ikisi de kod hatası değildir — ya altta yatan tablolarda (VBAK/VBAP/LIKP/VBRK/...) gerçekten eşleşen bir sipariş yoktur, ya da giriş yapan kullanıcı `V_VBAK_VKO` altında hiçbir Satış Organizasyonu için yetkili değildir (bkz. Bölüm 5). Bu sessizce başarısız olduğu için önce yetkilendirmeyi kontrol edin.

## 9. OData Servisini Doğrudan Kontrol Etme (opsiyonel)

Servisin ADT önizlemesi dışında da erişilebilir olduğunu doğrulamak isterseniz:

- Bir OData V4 UI servisi için **metadata URL kalıbı** kabaca şuna benzer:
  `/sap/opu/odata4/sap/zui_so_lifecycle/srvd_a2x/sap/zui_so_lifecycle/0001/$metadata`
  Tam yol parçaları (service group ID, versiyon numarası) sisteme ve sürüme göre hafifçe değişebilir, bu yüzden bunu ezberden yazmayın — Service Binding editöründe entity set'in yanında gösterilen gerçek URL'yi kopyalayın (genelde bir "copy URL" ya da "show endpoint" seçeneği vardır) ve servis kökünün sonuna `/$metadata` ekleyin.
- Bu `$metadata` URL'sini bir tarayıcıda doğrudan açmak, `SalesOrderLifecycle` ve `SalesOrderLifecycleItem` entity set'lerini, özelliklerini ve aralarındaki navigasyonu tanımlayan bir XML (EDMX) belgesi döndürmelidir.
- Servisin Gateway/yönetim tarafından da kayıtlı ve aktif olduğunu kontrol etmek isterseniz `/IWFND/MAINT_SERVICE`'e (klasik OData servis kayıt ekranı) bakabilirsiniz — ancak bu şekilde oluşturulan OData V4 servisleri için **en doğrudan ve güvenilir bilgi kaynağı Service Binding editörünün kendi "Published" durumudur**; Gateway işlem kodunu birincil değil, ikincil bir kontrol olarak görün.

## 10. Sorun Giderme

| Belirti | Olası Neden | Çözüm |
|---|---|---|
| Aktivasyon sırasında "View not active" / "does not exist" | Bir view, bağımlılıklarından biri aktive edilmeden aktive edilmeye çalışıldı (yanlış sıra) | Bölüm 3'teki sırada adı geçen bağımlılığı bulun, önce onu aktive edin, sonra tekrar deneyin |
| Metadata extension aktive edilemiyor | Consumption view'de `@Metadata.allowExtensions: true` eksik | Annotation'ı view'e ekleyin, view'i yeniden aktive edin, sonra extension'ı tekrar deneyin |
| `ZC_SO_LIFECYCLE` ya da `ZC_SO_LIFECYCLE_ITEM`'ı tek başına aktive ederken "Data source ... is unknown" | İki consumption view birbirine referans veriyor (döngüsel association) ve şu ana kadar sadece biri var | Önce ikisini de oluşturup kaydedin, sonra ikisini birlikte seçip aktive edin (Bölüm 3, Grup 5) |
| List Report önizlemesi "No data found" gösteriyor | Ya VBAK/VBAP vb.'de eşleşen satır yok, ya da kullanıcının `V_VBAK_VKO` yetkisi yok | Kod sorunu olduğunu varsaymadan önce kullanıcının PFCG rolünde `V_VBAK_VKO`'yu kontrol edin (Bölüm 5) |
| Önizleme yüklenmiyor / servise ulaşılamıyor | Binding aktive edildi ama hiç **Publish** edilmedi (Bölüm 7, adım 6) | Service Binding editörünü açıp Publish'e tıklayın |
| Criticality renkleri (kırmızı/sarı/yeşil) görünmüyor | `@UI.criticality`, `StageCriticality`'e işaret etmiyor, ya da view bu alanı dışarı açmıyor | `.ddlx` dosyasındaki `criticality:` referanslarını ve `StageCriticality`'in view'in alan listesinde olduğunu kontrol edin |
| `dats_days_between` / `$session.system_date` eski bir sürümde garip davranıyor ya da kabul edilmiyor | Bazı eski S/4HANA sürümleri, `$session.system_date`'in bir view entity içinde kullanımını kısıtlar | Alternatif olarak base view'e bir tarih **input parameter**'ı ekleyin (`with parameters p_key_date : abap.dats`) ve `$session.system_date` yerine `$parameters.p_key_date`'i kullanın — bu durumda üzerine kurulu view'lerin de bu parametreyi sağlaması gerekir |