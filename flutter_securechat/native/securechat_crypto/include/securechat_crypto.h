/* Elcim kripto cekirdeginin C ABI'si.
 *
 * Kaynak: native/securechat_crypto/src/lib.rs
 * Temel:  vodozemac 0.9 (Apache-2.0) — Olm + Megolm
 *
 * Bu baslik iki ise yarar: iOS XCFramework'u icin gerekli, ve ABI'nin
 * otoritatif beyani. Dart tarafi `securechat_crypto_ffi.dart` icinde el
 * yazimi baglanti tutuyor; bu dosya ile birlikte guncel kalmali.
 *
 * SOZLESME
 *   - Pointer donen fonksiyonlarda NULL = hata. Ayrinti sc_last_error().
 *   - int donenlerde -1 = hata.
 *   - Donen her char* cagiran tarafindan sc_string_free ile birakilir.
 *   - Handle'lar opak; sc_account_free / sc_session_free ile yok edilir.
 *   - Ikili veri sinirda base64 tasinir. vodozemac PADDING'SIZ base64
 *     uretir (Matrix/libolm konvansiyonu).
 *   - pickle_key her zaman tam 32 bayt.
 *   - Bir handle ayni anda tek thread'den kullanilmali.
 */

#ifndef SECURECHAT_CRYPTO_H
#define SECURECHAT_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opak handle'lar. */
typedef struct ScAccount ScAccount;
typedef struct ScSession ScSession;

/* Dart tarafinin bekledigi surumle eslesmeli; eslesmezse yanlis kutuphane
 * sessizce calismak yerine acik hata verir. */
uint32_t sc_abi_version(void);

char *sc_last_error(void);
void sc_string_free(char *value);

/* --- Account ----------------------------------------------------------- */

ScAccount *sc_account_new(void);
void sc_account_free(ScAccount *account);

ScAccount *sc_account_from_pickle(const char *pickle, const uint8_t *pickle_key);
char *sc_account_pickle(const ScAccount *account, const uint8_t *pickle_key);

/* {"curve25519":"<b64>","ed25519":"<b64>"} */
char *sc_account_identity_keys(const ScAccount *account);

/* Ed25519 imzasi, base64. */
char *sc_account_sign(const ScAccount *account,
                      const uint8_t *message,
                      size_t message_len);

/* Tek kullanimlik anahtarlar HESABIN ICINDE tutulur. Uretimden sonra hesabi
 * yeniden pickle'layip saklamak ZORUNLU, aksi halde anahtarlar kaybolur. */
char *sc_account_generate_one_time_keys(ScAccount *account, size_t count);
char *sc_account_one_time_keys(const ScAccount *account);
intptr_t sc_account_stored_one_time_key_count(const ScAccount *account);
int32_t sc_account_mark_keys_as_published(ScAccount *account);

/* Last-resort fallback anahtari; signed prekey karsiligi. */
char *sc_account_generate_fallback_key(ScAccount *account);

ScSession *sc_account_create_outbound_session(const ScAccount *account,
                                             const char *their_identity_key,
                                             const char *their_one_time_key);

/* Basaride base64 plaintext doner ve *out_session doldurulur.
 * Hatada NULL doner ve *out_session degismez. */
char *sc_account_create_inbound_session(ScAccount *account,
                                        const char *their_identity_key,
                                        const char *pre_key_message,
                                        ScSession **out_session);

/* --- Session ----------------------------------------------------------- */

void sc_session_free(ScSession *session);

ScSession *sc_session_from_pickle(const char *pickle, const uint8_t *pickle_key);
char *sc_session_pickle(const ScSession *session, const uint8_t *pickle_key);
char *sc_session_id(const ScSession *session);

/* {"type":0|1,"body":"<b64>"}  — type 0 = PreKey, 1 = normal mesaj.
 * Sifreleme ratchet'i ilerletir; cagiran oturumu yeniden pickle'layip
 * saklamak ZORUNDA, aksi halde ayni mesaj anahtari tekrar kullanilir. */
char *sc_session_encrypt(ScSession *session,
                         const uint8_t *plaintext,
                         size_t plaintext_len);

/* Base64 plaintext doner. */
char *sc_session_decrypt(ScSession *session,
                         size_t message_type,
                         const char *body);

#ifdef __cplusplus
}
#endif

#endif /* SECURECHAT_CRYPTO_H */
