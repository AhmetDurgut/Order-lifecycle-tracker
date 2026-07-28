# Service Layer

This folder holds the OData service definition `ZUI_SO_LIFECYCLE.srvd`, which declares
which CDS views are exposed as the service — the header lifecycle view and the item
lifecycle view.

You'll notice there is intentionally **no service binding file** here. In ABAP, a
service binding isn't a hand-written source file — it's an ADT (Eclipse) object that
you create visually, choose a protocol for (here: OData V4 - UI), and then publish.
Its activation/publish state lives in the system itself, not in a portable text file,
so committing one to Git wouldn't be meaningful or reusable.

To expose this service on a real system, follow the step-by-step instructions in
[docs/cds-odata-setup-guide.md](../../docs/cds-odata-setup-guide.md) — it covers
creating the service binding, choosing OData V4, publishing it, and previewing the
Fiori Elements app.

---

# Servis Katmanı

Bu klasör, hangi CDS view'lerin servis olarak yayınlandığını (header lifecycle view
ve item lifecycle view) tanımlayan `ZUI_SO_LIFECYCLE.srvd` servis tanımını içerir.

Burada kasıtlı olarak **service binding dosyası bulunmuyor**. ABAP'ta service binding
elle yazılan bir kaynak kod dosyası değildir; ADT (Eclipse) üzerinde görsel olarak
oluşturduğunuz, bir protokol seçtiğiniz (burada: OData V4 - UI) ve ardından publish
ettiğiniz bir nesnedir. Aktivasyon/publish durumu taşınabilir bir metin dosyasında
değil, doğrudan sistemde tutulur; bu yüzden Git'e böyle bir dosya eklemek anlamlı ya
da yeniden kullanılabilir olmaz.

Bu servisi gerçek bir sistemde yayınlamak için
[docs/cds-odata-setup-guide.md](../../docs/cds-odata-setup-guide.md) dosyasındaki
adım adım talimatları takip edin — service binding oluşturma, OData V4 seçimi,
publish etme ve Fiori Elements uygulamasını önizleme adımlarını kapsar.