# YYYY-MM-DD — <Konu>

> **Bu dosyayı kopyala**: `cp TEMPLATE.md YYYY-MM-DD-<kisa-konu>.md` ile yeni postmortem oluştur.
> **Amaç**: Her bug/incident için **kök neden + tekrar olmasını engelleme** kayıt altına alınsın.

## Özet

Bir cümlede ne oldu. (Örn: "Sureli mesaj timer'ı race window nedeniyle alıcıda 5sn erken expire ediyordu.")

## Etki

- **Etkilenen kullanıcı sayısı:** (bilinmiyorsa "bilinmiyor")
- **Etkilenen süre:** (örn. "X commit'ten Y commit'e kadar, ~3 gün")
- **Etkilenen feature:** (örn. "Sureli mesaj — sadece grup sohbetlerinde")
- **Severity:** P0 (data loss/security) / P1 (broken core feature) / P2 (degraded UX) / P3 (minor)

## Zaman çizelgesi

| Tarih/Saat (UTC+3) | Olay |
|---|---|
| YYYY-MM-DD HH:MM | Bug rapor edildi / commit pushlandı |
| YYYY-MM-DD HH:MM | İlk teşhis |
| YYYY-MM-DD HH:MM | İlk fix denemesi (başarısız) |
| YYYY-MM-DD HH:MM | Kök neden tespit |
| YYYY-MM-DD HH:MM | Kalıcı fix push |
| YYYY-MM-DD HH:MM | Verify (kullanıcı / test) |

## Kök neden

Neden olduğu **teknik** sebep. Sembolik kod referansları ile. (file_path:line_number)

Örnek:
> `SendMessageUseCase.kt:84` envelope prefix'lerini yanlış sırada yazdığımız için (POLL: önce, EXP: sonra) `parseMessageEnvelope` POLL gördükten sonra kalan her şeyi content sayıp EXP'i içerikte bırakıyordu. Sonuç: alıcı tarafta absoluteExpiresAt parse edilemiyor → null → lokal duration fallback'i kullanılıyor → sender ile alıcı arasında 5sn fark.

## Nasıl tespit edildi

Bug nasıl ortaya çıktı: kullanıcı raporu / monitoring alarm / test fail / log inspection.

## Geçici çözüm (varsa)

Hemen uygulanan workaround (örn. Redis queue temizleme, manuel cache invalidation).

## Kalıcı çözüm

Asıl fix'in özeti + commit hash.

Örnek:
> `SendMessageUseCase.kt:84` envelope sırası düzeltildi: `EXP:` POLL'den ÖNCE yerleştirildi. Parser POLL'den önce EXP'i tüketir, böylece content saf metin kalır.
> 
> Commit: `f556e1c — fix(sureli-mesaj): asama 3 — gonderici ve alicida ayni expiresAt`

## Önleme — Tekrar olmaması için ne yapmalı

1. **Test eklendi mi?**
   - [ ] Unit test (file:line)
   - [ ] Integration test (file:line)
   - [ ] Regression test (file:line)
2. **Process değişikliği?**
   - [ ] PR template'inde checklist
   - [ ] CI'a yeni kontrol
   - [ ] Monitoring/alarm
3. **Mimari değişikliği?**
   - [ ] Refactor planı (`docs/IMPROVEMENT_ROADMAP.md` Faz X)

## Çıkarılan dersler

Bu incident'tan öğrenilen genel prensipler. (Örn: "Wire format değişikliği yapılırken hem gönderici hem alıcı tarafta sıra-bağımlı parser logic'i için snapshot testler şart.")

## İlgili linkler

- Bug rapor: (varsa GitHub issue / kullanıcı mesajı)
- İlgili commit'ler: hash1, hash2
- Memory entry: `~/.claude/projects/.../memory/project_YYYY_MM_DD_xxx.md`
