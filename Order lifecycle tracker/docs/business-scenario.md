# Business Scenario — Sales Order Lifecycle Tracker

## The problem

A sales order is never really a single event — it's a chain of them. An order gets created, then a delivery gets created against it, then goods actually go out the door, then eventually an invoice gets raised. Any one of those steps can stall, quietly, without anyone deciding it should. When a customer calls asking "where's my order?", or finance asks "why hasn't this been invoiced yet?", there's no single screen that answers either question — instead, someone opens VA03 to check the order, VL03N to check the delivery, VF03 to check the billing document, and maybe the document flow view to see how they all connect, and does this one order at a time, by hand, because that's the only way to piece the picture together. Multiply that by a few hundred open orders and it stops being something anyone can realistically do proactively — it only happens reactively, order by order, when someone already has a reason to be worried. In the meantime, orders quietly stall: a delivery gets created but goods issue never happens, or an order gets fully delivered but the invoice never follows. Nobody notices until a customer complains, or until month-end closing surfaces a pile of orders that should have been billed weeks ago.

## Why this fails

The status of any given order is real — it's just scattered. VBAK and VBAP hold the order itself, LIKP and LIPS hold the delivery, VBRK and VBRP hold the billing document, and VBFA is the only thing tying them together as a chain of follow-on documents. Standard delivery/billing status fields (on the order and the individual item) tell you *where* an order stands, but not *how long* it's been standing there, and there's no ranked, single list of "these are the orders that have been waiting the longest at each stage." Checking is something a person does when prompted, not something the system surfaces before it becomes a complaint. And because different steps of the chain naturally belong to different teams — the warehouse cares about goods issue, finance cares about invoicing, sales cares about the customer relationship — no single person or team is actually watching the whole chain end to end. Everyone owns a piece; nobody owns the order's journey.

## The solution

The Sales Order Lifecycle Tracker puts every sales order into one list, each one already classified into its current stage — Order Created, Partially Delivered, Delivered, Goods Issued, Partially Invoiced, or Invoiced — so nobody has to reconstruct that stage by hand from three transactions. For every order it also calculates how many days it's been sitting in that stage, using whichever reference date actually makes sense for that stage: the order's creation date while it's waiting on a delivery, the actual goods-issue date once it's waiting on an invoice. A traffic-light criticality color — red, yellow, green — flags the orders that have waited too long, and the thresholds are deliberately different per stage, because an order sitting 5 days between delivery and goods issue is a very different situation from an invoice sitting unbilled for 5 days. Clicking into any order opens its detail, including an item-by-item breakdown, so you can see exactly which item is the one holding the whole order back while the rest have already moved on. The whole thing is built on CDS view entities exposed through OData V4, rendered as a Fiori Elements List Report and Object Page — there is no hand-written UI code anywhere, the filter bar, the colored columns, and the item table all come straight from annotations on the views. Sales-organization authorization is enforced through DCL, so a user only ever sees the orders their sales org access actually covers.

## Stakeholders

| Role | Need |
|---|---|
| Sales representative / customer service | Answer "where's my order?" on the spot, without opening three different transactions to piece it together |
| Warehouse / logistics | See which orders are delivered but not yet goods-issued, before they sit long enough to become a problem |
| Finance / billing | Spot orders that are goods-issued but still not invoiced, before month-end closing surfaces them the hard way |
| Sales manager | One prioritized view of every stalled order across the whole team, with the worst-waiting ones already flagged red |
| Internal audit | A consistent, rule-based read on order progression, instead of whatever a manual spot-check happens to catch |

None of this depends on anyone remembering to go check three transactions — the stage and the day-count are computed the same way for every order, every time, the coloring is annotation-driven rather than hardcoded into a screen, and sales-org authorization means each person only ever sees the slice of the business that's actually theirs to watch.

---

# İş Senaryosu — Sales Order Lifecycle Tracker

## Sorun

Bir satış siparişi aslında hiçbir zaman tek bir olay değildir — bir zincirdir. Önce sipariş oluşturulur, sonra ona karşılık bir teslimat oluşturulur, sonra mal fiilen depodan çıkar, en sonunda da bir fatura kesilir. Bu adımlardan herhangi biri, kimse fark etmeden, sessizce takılıp kalabilir. Bir müşteri "siparişim nerede?" diye aradığında, ya da finans "bu neden hâlâ faturalanmadı?" diye sorduğunda, ikisine de tek bir ekrandan cevap veren bir yer yoktur — bunun yerine biri VA03'ü açıp siparişe bakar, VL03N'i açıp teslimata bakar, VF03'ü açıp fatura belgesine bakar, belki bir de document flow ekranından hepsinin nasıl bağlandığına bakar, ve bunu tek seferde tek bir sipariş için, elle yapar — çünkü resmi tamamlamanın başka yolu yoktur. Bunu açık birkaç yüz siparişle çarpın, artık kimsenin proaktif olarak yapabileceği bir şey olmaktan çıkar — sadece reaktif olarak, sipariş sipariş, biri zaten endişelenmeye başladığında yapılır. Bu arada siparişler sessizce takılır: bir teslimat oluşturulur ama mal çıkışı hiç yapılmaz, ya da bir sipariş tamamen teslim edilir ama faturası hiç kesilmez. Bir müşteri şikayet edene, ya da ay sonu kapanışı haftalar önce faturalanması gereken bir siparişler yığınını ortaya çıkarana kadar kimse fark etmez.

## Neden işe yaramıyor

Herhangi bir siparişin durumu gerçek bir bilgidir — sadece dağınıktır. VBAK ve VBAP siparişin kendisini tutar, LIKP ve LIPS teslimatı tutar, VBRK ve VBRP fatura belgesini tutar, ve bunları bir zincir halinde birbirine bağlayan tek şey VBFA'dır. Standart teslimat/fatura durum alanları (hem sipariş hem kalem seviyesinde) bir siparişin *nerede* durduğunu söyler, ama *ne kadar süredir* orada durduğunu söylemez, ve "her aşamada en uzun süredir bekleyen siparişler bunlar" diyen sıralı, tek bir liste yoktur. Kontrol etmek, biri hatırlattığında yapılan bir şeydir, sistemin şikayete dönüşmeden önce kendiliğinden ortaya çıkardığı bir şey değildir. Ayrıca zincirin farklı adımları doğal olarak farklı ekiplere ait olduğu için — depo mal çıkışıyla ilgilenir, finans faturalamayla ilgilenir, satış müşteri ilişkisiyle ilgilenir — zincirin tamamını baştan sona izleyen tek bir kişi ya da ekip yoktur. Herkes bir parçaya sahip çıkar; siparişin tüm yolculuğuna kimse sahip çıkmaz.

## Çözüm

Sales Order Lifecycle Tracker, her satış siparişini tek bir listeye koyar ve her birini şimdiden mevcut aşamasına göre sınıflandırır — Order Created, Partially Delivered, Delivered, Goods Issued, Partially Invoiced ya da Invoiced — böylece kimsenin bu aşamayı üç farklı transaction'dan elle yeniden kurmasına gerek kalmaz. Her sipariş için ayrıca o aşamada kaç gündür beklediğini de hesaplar, bunu yaparken o aşama için gerçekten anlamlı olan referans tarihini kullanır: teslimat beklenirken siparişin oluşturulma tarihini, fatura beklenirken gerçek mal çıkış tarihini. Kırmızı/sarı/yeşil bir trafik ışığı rengi, çok uzun süre bekleyen siparişleri işaretler, ve bu eşikler her aşama için bilerek farklıdır — çünkü teslimat ile mal çıkışı arasında 5 gün bekleyen bir sipariş ile 5 gündür faturalanmamış bir sipariş çok farklı iki durumdur. Herhangi bir siparişe tıklamak, kalem bazında bir döküm de dahil olmak üzere detayını açar, böylece diğer kalemler çoktan ilerlemişken tam olarak hangi kalemin tüm siparişi geride tuttuğunu görebilirsiniz. Bunların hepsi OData V4 üzerinden dışarı açılan CDS view entity'leri üzerine kurulu, bir Fiori Elements List Report ve Object Page olarak render ediliyor — hiçbir yerde elle yazılmış UI kodu yok, filtre çubuğu, renkli sütunlar ve kalem tablosu doğrudan view'ler üzerindeki annotation'lardan geliyor. Satış organizasyonu bazlı yetkilendirme DCL üzerinden zorunlu kılınıyor, yani bir kullanıcı her zaman sadece kendi satış organizasyonu erişiminin kapsadığı siparişleri görüyor.

## Paydaşlar

| Rol | İhtiyaç |
|---|---|
| Satış temsilcisi / müşteri hizmetleri | "Siparişim nerede?" sorusunu, üç farklı transaction açıp resmi birleştirmeden, anında yanıtlayabilmek |
| Depo / lojistik | Teslim edilmiş ama henüz mal çıkışı yapılmamış siparişleri, bir sorun haline gelecek kadar beklemeden görebilmek |
| Finans / faturalama | Mal çıkışı yapılmış ama hâlâ faturalanmamış siparişleri, ay sonu kapanışı bunları zor yoldan ortaya çıkarmadan önce yakalayabilmek |
| Satış müdürü | Tüm ekip genelinde takılı kalmış her siparişin, en uzun bekleyenleri zaten kırmızıyla işaretlenmiş, tek ve önceliklendirilmiş bir görünümü |
| İç denetim | Manuel bir spot-check'in yakaladığı kadarı yerine, sipariş ilerleyişine dair tutarlı, kurala dayalı bir okuma |

Bunların hiçbiri kimsenin üç farklı transaction'a bakmayı hatırlamasına bağlı değil — aşama ve gün sayısı her sipariş için, her seferinde aynı şekilde hesaplanıyor, renklendirme bir ekrana gömülü olmak yerine annotation'lardan geliyor, ve satış organizasyonu yetkilendirmesi sayesinde herkes işin sadece kendi izlemesi gereken dilimini görüyor.