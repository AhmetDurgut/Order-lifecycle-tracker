# Sales Order Lifecycle Tracker

A portfolio project that simulates a real SAP application: a read-only
CDS + OData V4 + Fiori Elements app that shows every sales order's exact
position in the order-to-invoice chain — created, delivered, goods issued,
invoiced — how many days it's been sitting at that stage, and which ones
have been waiting long enough to actually need a look. Built entirely on
CDS view entities exposed through OData V4, with the whole UI generated
from annotations.

## Business scenario

A sales order is a chain, not a single event, and any link in it can stall
without anyone deciding it should — a delivery created but never
goods-issued, an order fully delivered but never invoiced. Today, answering
"where's my order?" means opening VA03, VL03N, and VF03 one order at a
time and piecing it together by hand, so stalled orders usually surface
only when a customer complains or month-end closing turns up a pile of
them. This tracker puts every order's stage, wait time, and urgency in one
list instead.

Full write-up: [docs/business-scenario.md](docs/business-scenario.md)

## What it does

- One list of every sales order, each already classified into its current
  lifecycle stage: **Order Created**, **Partially Delivered**,
  **Delivered**, **Goods Issued**, **Partially Invoiced**, **Invoiced**.
- Calculates how many days each order has sat in that stage, using
  whichever reference date actually makes sense for it — creation date
  while waiting on a delivery, actual goods-issue date while waiting on an
  invoice.
- Flags orders with a red/yellow/green criticality color, using
  stage-specific thresholds — a delivery waiting 5 days isn't the same
  situation as an invoice waiting 5 days, so the thresholds aren't either.
- Drilling into an order opens an Object Page with an item-level
  breakdown, so you can see exactly which item is holding the whole order
  back while the rest have already moved on.
- Sales-organization authorization is enforced through DCL, so a user only
  ever sees the orders their own sales org access actually covers.
- Entirely annotation-driven: the List Report and Object Page come from
  `@UI` annotations in the metadata extensions — there's no hand-written
  UI code anywhere.

## Technical architecture

Standard SAP VDM layering: 9 interface views reading the raw order,
delivery, billing, and document-flow tables; 2 composite views rolling
deliveries up per item and per order; 2 base views centralizing the stage
and day-count calculation so it's computed exactly once; 2 consumption
views adding criticality on top; 2 metadata extensions carrying every `@UI`
annotation; 2 DCL roles for authorization; and 1 service definition
exposing it all as OData V4. Every view is a plain, read-only
`define view entity` — there's no RAP behavior definition anywhere, which
makes this the natural first half of a future writable app rather than an
oversight. The stage and day-count logic lives in exactly one place (the
two base views) because of a real CDS constraint: a calculated field can't
reference a sibling calculated field in the same view, so the day count
had to move down a layer to be reused instead of copy-pasted into every
consumer. It also targets S/4HANA specifically — delivery/billing status
is read straight off VBAK/VBAP, which only works because S/4HANA merged
what ECC used to split across VBUK/VBUP.

Full write-up: [docs/architecture.md](docs/architecture.md)

## Project structure

```
04-order-lifecycle-tracker/
├── src/
│   ├── interface/
│   │   ├── ZI_SO_HEADER.ddls               # order header over VBAK
│   │   ├── ZI_SO_ITEM.ddls                 # order item over VBAP
│   │   ├── ZI_DLV_ITEM.ddls                # delivery items over LIPS + LIKP
│   │   ├── ZI_BIL_ITEM.ddls                # billing items over VBRP + VBRK
│   │   ├── ZI_DOC_FLOW.ddls                # document flow over VBFA (deliveries/invoices)
│   │   ├── ZI_SO_DELIVERY_AGGR.ddls        # delivery rolled up per order item
│   │   ├── ZI_SO_DELIVERY_AGGR_HDR.ddls    # delivery rolled up per order header
│   │   ├── ZI_SO_LIFECYCLE_BASE.ddls       # header stage + reference date + days-in-stage
│   │   └── ZI_SO_LIFECYCLE_ITEM_BASE.ddls  # item stage + reference date + days-in-stage
│   ├── consumption/
│   │   ├── ZC_SO_LIFECYCLE.ddls            # header projection + criticality
│   │   └── ZC_SO_LIFECYCLE_ITEM.ddls       # item projection + criticality
│   ├── metadata/
│   │   ├── ZC_SO_LIFECYCLE.ddlx            # List Report + Object Page facets
│   │   └── ZC_SO_LIFECYCLE_ITEM.ddlx       # Object Page item table
│   ├── auth/
│   │   ├── ZC_SO_LIFECYCLE.dcl             # sales-org authorization (header)
│   │   └── ZC_SO_LIFECYCLE_ITEM.dcl        # inherits from header via _SalesOrder
│   └── service/
│       ├── ZUI_SO_LIFECYCLE.srvd           # OData V4 service definition
│       └── README.md                       # why there's no service binding file here
├── docs/
│   ├── architecture.md
│   ├── business-scenario.md
│   └── cds-odata-setup-guide.md
└── README.md
```

## How to deploy

The complete, click-by-click walkthrough — creating the CDS views in ADT in
the right dependency order, the metadata extensions, the DCL roles,
activating the service definition, and creating + publishing the OData V4
service binding — is in
[docs/cds-odata-setup-guide.md](docs/cds-odata-setup-guide.md). It's
written for someone who's never built a CDS + Fiori Elements service
before, so it explains the "why" at each step, not just the clicks.

Short version, if you already know your way around ADT:

1. Create the 9 interface views, then the 2 delivery-aggregation composite
   views, then the 2 lifecycle base views — **in that dependency order**,
   since a view can't activate before whatever it selects from or
   associates to already exists.
2. Create the 2 consumption views. These two associate to *each other*
   (header → item and item → header), so save both first and activate
   them together rather than one at a time.
3. Create the 2 metadata extensions (`ZC_SO_LIFECYCLE.ddlx`,
   `ZC_SO_LIFECYCLE_ITEM.ddlx`) — this only works because both consumption
   views already declare `@Metadata.allowExtensions: true`.
4. Create the 2 DCL roles, header (`ZC_SO_LIFECYCLE_AUTH`) before item
   (`ZC_SO_LIFECYCLE_ITEM_AUTH`, which inherits from it).
5. Activate the service definition `ZUI_SO_LIFECYCLE`.
6. Create an OData V4 service binding on top of it, activate it, and
   **publish** it — the binding itself isn't a file in this repo, since a
   published/activated state is something the system tracks, not source
   code (see [src/service/README.md](src/service/README.md) for why).
7. Preview the Fiori Elements List Report straight from the service
   binding editor.

## Roadmap

- Add the payment/clearing step to complete the order-to-cash picture.
- A RAP-based writable version — actions to escalate or chase a stalled
  step, sitting on top of this same read model.
- An Analytical List Page with aggregated stage counts per sales
  organization.
- Alerting when an order crosses its own stage threshold, instead of
  waiting for someone to open the app and notice.
- Value helps and text associations for material, sales organization, and
  distribution channel, for richer filtering.

---

# Sales Order Lifecycle Tracker

Gerçek bir SAP uygulamasını taklit eden bir portfolyo çalışması: her satış
siparişinin sipariş-fatura zincirinde tam olarak nerede durduğunu —
oluşturuldu, teslim edildi, mal çıkışı yapıldı, faturalandı — o aşamada kaç
gündür beklediğini ve hangilerinin gerçekten bakılmayı hak edecek kadar
uzun süredir beklediğini gösteren, salt okunur bir
CDS + OData V4 + Fiori Elements uygulaması. Tamamen OData V4 üzerinden
dışarı açılan CDS view entity'leri üzerine kurulu, tüm UI'ı annotation'lardan
üretilmiş.

## İş senaryosu

Bir satış siparişi tek bir olay değil, bir zincirdir, ve bu zincirdeki
herhangi bir halka, kimse fark etmeden takılabilir — bir teslimat
oluşturulur ama mal çıkışı hiç yapılmaz, bir sipariş tamamen teslim edilir
ama faturası hiç kesilmez. Bugün "siparişim nerede?" sorusuna cevap vermek,
VA03'ü, VL03N'i ve VF03'ü tek tek açıp resmi elle birleştirmek anlamına
geliyor, bu yüzden takılı kalmış siparişler genelde ancak bir müşteri
şikayet ettiğinde ya da ay sonu kapanışı bir yığınını ortaya çıkardığında
fark ediliyor. Bu tracker, her siparişin aşamasını, bekleme süresini ve
aciliyetini tek bir listede topluyor.

Tam yazı: [docs/business-scenario.md](docs/business-scenario.md)

## Ne yapar

- Her satış siparişini, şimdiden mevcut yaşam döngüsü aşamasına
  sınıflandırılmış tek bir listede gösterir: **Order Created**,
  **Partially Delivered**, **Delivered**, **Goods Issued**,
  **Partially Invoiced**, **Invoiced**.
- Her siparişin o aşamada kaç gündür beklediğini, o aşama için gerçekten
  anlamlı olan referans tarihini kullanarak hesaplar — teslimat
  beklenirken oluşturulma tarihini, fatura beklenirken gerçek mal çıkış
  tarihini.
- Siparişleri kırmızı/sarı/yeşil bir kritiklik rengiyle işaretler, ve bu
  eşikler aşamaya göre değişir — 5 gündür bekleyen bir teslimat ile 5
  gündür bekleyen bir fatura aynı durum değildir, eşikler de bu yüzden
  aynı değildir.
- Bir siparişe tıklamak, kalem bazında bir dökümü de içeren bir Object
  Page açar, böylece diğer kalemler çoktan ilerlemişken tam olarak hangi
  kalemin tüm siparişi geride tuttuğunu görebilirsiniz.
- Satış organizasyonu bazlı yetkilendirme DCL üzerinden zorunlu kılınır,
  yani bir kullanıcı her zaman sadece kendi satış organizasyonu
  erişiminin kapsadığı siparişleri görür.
- Tamamen annotation'lardan üretilir: List Report ve Object Page, metadata
  extension'lardaki `@UI` annotation'larından geliyor — hiçbir yerde elle
  yazılmış UI kodu yok.

## Teknik mimari

Standart SAP VDM katmanlaması: ham sipariş, teslimat, fatura ve belge akışı
tablolarını okuyan 9 interface view; teslimatları kalem ve sipariş bazında
toplayan 2 composite view; aşama ve gün sayısı hesaplamasını tam olarak tek
bir yerde merkezileştiren 2 base view; bunun üzerine kritiklik ekleyen 2
consumption view; her `@UI` annotation'ını taşıyan 2 metadata extension;
yetkilendirme için 2 DCL rolü; ve hepsini OData V4 olarak dışarı açan 1
service definition. Her view düz, salt okunur bir `define view entity` —
hiçbir yerde bir RAP behavior definition yok, ki bu bir eksiklik değil,
ileride yazılabilir bir uygulamanın doğal ilk yarısı olması. Aşama ve gün
sayısı mantığı tam olarak tek bir yerde (iki base view'de) yaşıyor, çünkü
gerçek bir CDS kısıtlaması bunu gerektiriyor: hesaplanmış bir alan, aynı
view içindeki bir sibling hesaplanmış alana referans veremiyor, o yüzden
gün sayısının her tüketiciye kopyalanması yerine bir katman aşağı inip
yeniden kullanılması gerekiyor. Ayrıca özellikle S/4HANA'yı hedefliyor —
teslimat/fatura durumu doğrudan VBAK/VBAP'tan okunuyor, ki bu sadece
S/4HANA'nın ECC'de VBUK/VBUP'a bölünmüş olanı birleştirmiş olması
sayesinde işe yarıyor.

Tam yazı: [docs/architecture.md](docs/architecture.md)

## Proje yapısı

```
04-order-lifecycle-tracker/
├── src/
│   ├── interface/
│   │   ├── ZI_SO_HEADER.ddls               # VBAK üzerinden sipariş başlığı
│   │   ├── ZI_SO_ITEM.ddls                 # VBAP üzerinden sipariş kalemi
│   │   ├── ZI_DLV_ITEM.ddls                # LIPS + LIKP üzerinden teslimat kalemleri
│   │   ├── ZI_BIL_ITEM.ddls                # VBRP + VBRK üzerinden fatura kalemleri
│   │   ├── ZI_DOC_FLOW.ddls                # VBFA üzerinden belge akışı (teslimat/fatura)
│   │   ├── ZI_SO_DELIVERY_AGGR.ddls        # teslimat, sipariş kalemi bazında toplanmış
│   │   ├── ZI_SO_DELIVERY_AGGR_HDR.ddls    # teslimat, sipariş başlığı bazında toplanmış
│   │   ├── ZI_SO_LIFECYCLE_BASE.ddls       # header aşaması + referans tarihi + aşamadaki gün
│   │   └── ZI_SO_LIFECYCLE_ITEM_BASE.ddls  # item aşaması + referans tarihi + aşamadaki gün
│   ├── consumption/
│   │   ├── ZC_SO_LIFECYCLE.ddls            # header projeksiyonu + kritiklik
│   │   └── ZC_SO_LIFECYCLE_ITEM.ddls       # item projeksiyonu + kritiklik
│   ├── metadata/
│   │   ├── ZC_SO_LIFECYCLE.ddlx            # List Report + Object Page facet'leri
│   │   └── ZC_SO_LIFECYCLE_ITEM.ddlx       # Object Page kalem tablosu
│   ├── auth/
│   │   ├── ZC_SO_LIFECYCLE.dcl             # satış organizasyonu yetkilendirmesi (header)
│   │   └── ZC_SO_LIFECYCLE_ITEM.dcl        # _SalesOrder üzerinden header'dan miras alır
│   └── service/
│       ├── ZUI_SO_LIFECYCLE.srvd           # OData V4 service definition
│       └── README.md                       # burada neden bir service binding dosyası olmadığı
├── docs/
│   ├── architecture.md
│   ├── business-scenario.md
│   └── cds-odata-setup-guide.md
└── README.md
```

## Nasıl deploy edilir

CDS view'lerinin ADT'de doğru bağımlılık sırasıyla oluşturulmasından
metadata extension'lara, DCL rollerine, service definition'ın aktive
edilmesine ve OData V4 service binding'inin oluşturulup publish
edilmesine kadar tüm adımları içeren eksiksiz rehber
[docs/cds-odata-setup-guide.md](docs/cds-odata-setup-guide.md) içinde.
Daha önce hiç CDS + Fiori Elements servisi kurmamış biri için yazıldı,
yani her adımda sadece ne tıklanacağını değil, nedenini de anlatıyor.

ADT'ye zaten aşinaysan, kısa versiyon şu:

1. Önce 9 interface view'i, sonra 2 teslimat-aggregation composite
   view'ini, sonra 2 lifecycle base view'ini — **tam olarak bu bağımlılık
   sırasıyla** oluştur, çünkü bir view, select ettiği ya da bağlandığı şey
   zaten var olmadan aktive edilemez.
2. 2 consumption view'ini oluştur. Bu ikisi *birbirine* bağlanıyor (header
   → item ve item → header), o yüzden ikisini de önce kaydet, sonra tek
   tek değil birlikte aktive et.
3. 2 metadata extension'ı oluştur (`ZC_SO_LIFECYCLE.ddlx`,
   `ZC_SO_LIFECYCLE_ITEM.ddlx`) — bu sadece iki consumption view de zaten
   `@Metadata.allowExtensions: true` tanımladığı için çalışır.
4. 2 DCL rolünü oluştur, önce header (`ZC_SO_LIFECYCLE_AUTH`), sonra ondan
   miras alan item (`ZC_SO_LIFECYCLE_ITEM_AUTH`).
5. `ZUI_SO_LIFECYCLE` service definition'ını aktive et.
6. Bunun üzerine bir OData V4 service binding oluştur, aktive et, ve
   **publish** et — binding'in kendisi bu repoda bir dosya değil, çünkü
   publish/aktivasyon durumu kaynak kod değil, sistemin takip ettiği bir
   şey (nedenini [src/service/README.md](src/service/README.md) içinde
   görebilirsiniz).
7. Fiori Elements List Report'unu doğrudan service binding editöründen
   önizle.

## Yol haritası

- Order-to-cash resmini tamamlamak için ödeme/mahsup adımını eklemek.
- Aynı okuma modelinin üzerine oturan, RAP tabanlı yazılabilir bir versiyon
  — takılı kalmış bir adımı yükseltmek/takip etmek için aksiyonlar.
- Satış organizasyonu bazında toplu aşama sayılarını gösteren bir
  Analytical List Page.
- Bir sipariş kendi aşama eşiğini aştığında, birinin uygulamayı açıp fark
  etmesini beklemek yerine uyarı göndermek.
- Daha zengin filtreleme için malzeme, satış organizasyonu ve dağıtım
  kanalı için value help ve text association'lar.