# SecureChat — Güvenli Haberleşme Uygulaması

## Proje Hakkında
WhatsApp benzeri, uçtan uca şifreli, P2P güvenli haberleşme Android uygulaması.

## Teknoloji Stack
- **Platform:** Android (Kotlin, min SDK 26, target SDK 34)
- **UI:** Jetpack Compose + Material 3
- **Şifreleme:** Signal Protocol (libsignal-android)
- **P2P/Arama:** WebRTC
- **Veritabanı:** Room + SQLCipher (yalnızca lokal)
- **DI:** Hilt
- **Async:** Kotlin Coroutines + Flow
- **Signaling:** Ktor WebSocket server

## Mimari
- Multi-module Android projesi (app, crypto, network, storage, media, contacts, common)
- Clean Architecture: UI → ViewModel → UseCase → Repository → DataSource
- Interface kontratları modüller arası iletişimi tanımlar

## Güvenlik Kuralları
- Plaintext mesaj içeriği ASLA loga yazılmaz
- Private key'ler yalnızca Android Keystore'da saklanır
- Mesaj içeriği sunucuya ASLA gönderilmez
- SQLite veritabanı SQLCipher ile şifrelenir
- Hassas veriler kullanım sonrası bellekten sıfırlanır
- FLAG_SECURE varsayılan olarak açık
- Certificate pinning zorunlu

## Dil
- Kod: İngilizce (değişken, sınıf, fonksiyon isimleri)
- Yorum ve dokümantasyon: Türkçe
- UI metinleri: Türkçe (strings.xml)

## Konvansiyonlar
- Kotlin coding conventions
- Conventional commits (feat:, fix:, refactor:, docs:, test:)
- Her modül kendi testlerini içerir
- Minimum %80 unit test coverage hedefi

## Skill Referansları
Proje skill'leri `.claude/skills/` altında. Her agent kendi SKILL.md'sini okur.
