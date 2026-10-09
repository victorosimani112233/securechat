//! Elçim kripto çekirdeğinin C ABI yüzeyi.
//!
//! Neden el yazımı dar bir ABI: bu katman uygulamanın güvenlik çekirdeği.
//! Üretilmiş binlerce satır yerine okunup denetlenebilecek ~20 fonksiyon
//! tutuluyor. vodozemac senkron ve değer tabanlı çalıştığı için (pickle gir,
//! pickle çık) Rust'ın Dart'a geri çağırmasına gerek yok; libsignal'ın
//! store-callback mimarisinin yarattığı senkron/async çıkmazı burada yok.
//!
//! Sözleşme:
//! - Pointer dönen fonksiyonlarda `null` = hata. Ayrıntı `sc_last_error()`.
//! - `isize` dönenlerde `-1` = hata, `i32` dönenlerde `-1` = hata.
//! - Dönen her `*mut c_char` çağıran tarafından `sc_string_free` ile
//!   serbest bırakılır.
//! - Handle'lar opak: `sc_account_free` / `sc_session_free` ile yok edilir.
//! - İkili veri sınırda base64 taşınır.
//!
//! TODO(megolm): grup akışı (GroupSession / InboundGroupSession) ayrı görev.
//! TODO(zeroize): plaintext şu an base64 ara kopyası üretiyor. Üretim öncesi
//!   ham bayt + uzunluk imzasına geçilip ara tamponlar sıfırlanmalı.

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use std::cell::{Cell, RefCell};
use std::ffi::{c_char, CStr, CString};
use std::ptr;

mod megolm;

use vodozemac::olm::{Account, OlmMessage, PreKeyMessage, Session, SessionConfig};
use vodozemac::Curve25519PublicKey;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
    static LAST_ERROR_CODE: Cell<u32> = const { Cell::new(ERROR_NONE) };
}

/// Hata siniflari.
///
/// NEDEN KOD VAR: cagiran, cozme hatasinin oturumu YOK ETMEYI gerektirip
/// gerektirmedigine karar vermek zorunda. Bu karari hata MESAJINA bakarak
/// vermek kirilgan: bir metin degisikligi sessizce guvenlik davranisini
/// degistirir. Ozellikle `MissingMessageKey` tekrar teslim edilen ya da
/// sirasiz gelen bir cerceveyi isaret eder ve saglikli bir oturumda da
/// olagandir — onu "oturum olu" saymak, tekrar oynatilan bir cerceveyle
/// oturumu sifirlatmak demek olurdu.
pub(crate) const ERROR_NONE: u32 = 0;
pub(crate) const ERROR_GENERIC: u32 = 1;
pub(crate) const ERROR_PICKLE: u32 = 2;
pub(crate) const ERROR_DECODE: u32 = 3;
/// Mesaj anahtari yok: tuketilmis veya ratchet ilerlemis. Oturum SAGLAM.
pub(crate) const ERROR_DECRYPT_MISSING_KEY: u32 = 4;
/// MAC veya padding gecersiz: yanlis anahtar, yanlis oturum veya oynama.
pub(crate) const ERROR_DECRYPT_INVALID: u32 = 5;
/// Mesaj araligi cok buyuk; oturum yetisemez.
pub(crate) const ERROR_DECRYPT_GAP: u32 = 6;
/// Oturum kurulamadi.
pub(crate) const ERROR_SESSION: u32 = 7;
/// Gelen PreKey mesajinin kimligi pinlenen kimlikle uyusmuyor. Bu bir GUVEN
/// olayidir, olu oturum degil: mevcut oturumlar saglam ve silinmemeli.
/// Ayri sinif olmasa `ERROR_SESSION` ile karisir ve tek bir mesaj (karsi
/// tarafin yeni cihazi ya da araya giren biri) saglikli oturumu yok ederdi.
pub(crate) const ERROR_IDENTITY_MISMATCH: u32 = 8;

/// Son hatanin sinifi. `sc_last_error()` ile ayni cagri icin gecerlidir.
#[no_mangle]
pub extern "C" fn sc_last_error_code() -> u32 {
    LAST_ERROR_CODE.with(|slot| slot.get())
}

pub(crate) fn set_error_code(code: u32) {
    LAST_ERROR_CODE.with(|slot| slot.set(code));
}

pub(crate) fn set_error(message: impl Into<String>) {
    let text = message.into();
    let encoded = CString::new(text)
        .unwrap_or_else(|_| CString::new("hata mesaji NUL bayti tasiyordu").expect("statik mesaj"));
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some(encoded));
    // Varsayilan sinif; cagri yeri daha ozel bir kod verebilir.
    if sc_last_error_code() == ERROR_NONE {
        set_error_code(ERROR_GENERIC);
    }
}

pub(crate) fn clear_error() {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = None);
    set_error_code(ERROR_NONE);
}

/// Son hatayı döndürür; hata yoksa `null`. Çağıran `sc_string_free` çağırır.
#[no_mangle]
pub extern "C" fn sc_last_error() -> *mut c_char {
    LAST_ERROR.with(|slot| match slot.borrow().as_ref() {
        Some(message) => message.clone().into_raw(),
        None => ptr::null_mut(),
    })
}

/// Bu kütüphanenin döndürdüğü her stringi serbest bırakır.
#[no_mangle]
///
/// # Safety
///
/// Pointer bu kutuphanenin dondurdugu bir string olmali ve bir kez serbest birakilmali.
pub unsafe extern "C" fn sc_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe { drop(CString::from_raw(value)) };
    }
}

/// ABI sürümü. Dart tarafı yüklediği kütüphanenin beklediği sürüm olduğunu
/// doğrular; eşleşmezse yanlış `.so` ile sessizce çalışmak yerine açık hata.
#[no_mangle]
pub extern "C" fn sc_abi_version() -> u32 {
    3
}

// ---------------------------------------------------------------------------
// Yardimcilar
// ---------------------------------------------------------------------------

pub(crate) fn to_c_string(value: String) -> *mut c_char {
    match CString::new(value) {
        Ok(encoded) => encoded.into_raw(),
        Err(_) => {
            set_error("donus degeri NUL bayti tasiyordu");
            ptr::null_mut()
        }
    }
}

pub(crate) unsafe fn borrow_str<'a>(value: *const c_char, name: &str) -> Option<&'a str> {
    if value.is_null() {
        set_error(format!("{name} null olamaz"));
        return None;
    }
    match CStr::from_ptr(value).to_str() {
        Ok(text) => Some(text),
        Err(_) => {
            set_error(format!("{name} gecerli UTF-8 degil"));
            None
        }
    }
}

pub(crate) unsafe fn borrow_key<'a>(value: *const u8) -> Option<&'a [u8; 32]> {
    if value.is_null() {
        set_error("pickle anahtari null olamaz");
        return None;
    }
    Some(&*(value as *const [u8; 32]))
}

pub(crate) unsafe fn borrow_bytes<'a>(value: *const u8, len: usize) -> Option<&'a [u8]> {
    if value.is_null() && len != 0 {
        set_error("bayt tamponu null olamaz");
        return None;
    }
    if len == 0 {
        return Some(&[]);
    }
    Some(std::slice::from_raw_parts(value, len))
}

fn parse_curve_key(value: &str, name: &str) -> Option<Curve25519PublicKey> {
    match Curve25519PublicKey::from_base64(value) {
        Ok(key) => Some(key),
        Err(error) => {
            set_error(format!("{name} cozulemedi: {error}"));
            None
        }
    }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

/// Yeni bir Olm hesabı (identity anahtar çifti) üretir.
#[no_mangle]
pub extern "C" fn sc_account_new() -> *mut Account {
    clear_error();
    Box::into_raw(Box::new(Account::new()))
}

#[no_mangle]
///
/// # Safety
///
/// `account` `sc_account_new` / `sc_account_from_pickle` donusu olmali ve bir kez serbest birakilmali.
pub unsafe extern "C" fn sc_account_free(account: *mut Account) {
    if !account.is_null() {
        unsafe { drop(Box::from_raw(account)) };
    }
}

/// Şifreli pickle'dan hesabı geri yükler. `pickle_key` tam 32 bayt olmalı.
#[no_mangle]
///
/// # Safety
///
/// `pickle` NUL sonlu gecerli bir string, `pickle_key` tam 32 okunabilir bayt olmali.
pub unsafe extern "C" fn sc_account_from_pickle(
    pickle: *const c_char,
    pickle_key: *const u8,
) -> *mut Account {
    clear_error();
    let Some(pickle) = borrow_str(pickle, "pickle") else {
        return ptr::null_mut();
    };
    let Some(key) = borrow_key(pickle_key) else {
        return ptr::null_mut();
    };
    match vodozemac::olm::AccountPickle::from_encrypted(pickle, key) {
        Ok(decoded) => Box::into_raw(Box::new(Account::from_pickle(decoded))),
        Err(error) => {
            set_error_code(ERROR_PICKLE);
            set_error(format!("account pickle acilamadi: {error}"));
            ptr::null_mut()
        }
    }
}

/// Hesabı şifreli pickle olarak serileştirir.
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli bir hesap handle'i, `pickle_key` tam 32 okunabilir bayt olmali.
pub unsafe extern "C" fn sc_account_pickle(
    account: *const Account,
    pickle_key: *const u8,
) -> *mut c_char {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return ptr::null_mut();
    }
    let Some(key) = borrow_key(pickle_key) else {
        return ptr::null_mut();
    };
    to_c_string((*account).pickle().encrypt(key))
}

/// `{"curve25519":"<b64>","ed25519":"<b64>"}`
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli bir hesap handle'i olmali.
pub unsafe extern "C" fn sc_account_identity_keys(account: *const Account) -> *mut c_char {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return ptr::null_mut();
    }
    let keys = (*account).identity_keys();
    to_c_string(
        serde_json::json!({
            "curve25519": keys.curve25519.to_base64(),
            "ed25519": keys.ed25519.to_base64(),
        })
        .to_string(),
    )
}

/// Ed25519 imzası, base64.
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli olmali; `message`/`message_len` okunabilir bir aralik tanimlamali.
pub unsafe extern "C" fn sc_account_sign(
    account: *const Account,
    message: *const u8,
    message_len: usize,
) -> *mut c_char {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return ptr::null_mut();
    }
    let Some(bytes) = borrow_bytes(message, message_len) else {
        return ptr::null_mut();
    };
    to_c_string((*account).sign(bytes).to_base64())
}

/// `count` tek kullanımlık anahtar üretir ve YAYINLANMAMIŞ havuzun tamamını
/// `{"<keyId>":"<b64>"}` olarak döndürür.
///
/// Not: libsignal'ın aksine tek kullanımlık anahtarlar ayrı kayıtlarda değil,
/// hesabın kendi içinde tutuluyor. Yani üretim sonrası hesabı yeniden
/// pickle'layıp saklamak ZORUNLU; aksi halde anahtarlar kaybolur.
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli ve tek bir thread'den kullanilan bir handle olmali.
pub unsafe extern "C" fn sc_account_generate_one_time_keys(
    account: *mut Account,
    count: usize,
) -> *mut c_char {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return ptr::null_mut();
    }
    (*account).generate_one_time_keys(count);
    sc_account_one_time_keys(account)
}

/// Yayınlanmamış tek kullanımlık anahtarlar: `{"<keyId>":"<b64>"}`
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli bir hesap handle'i olmali.
pub unsafe extern "C" fn sc_account_one_time_keys(account: *const Account) -> *mut c_char {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return ptr::null_mut();
    }
    let map: serde_json::Map<String, serde_json::Value> = (*account)
        .one_time_keys()
        .into_iter()
        .map(|(id, key)| (id.to_base64(), serde_json::Value::String(key.to_base64())))
        .collect();
    to_c_string(serde_json::Value::Object(map).to_string())
}

/// Sunucudaki havuzun yerel karşılığı. Hata halinde -1.
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli bir hesap handle'i olmali.
pub unsafe extern "C" fn sc_account_stored_one_time_key_count(account: *const Account) -> isize {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return -1;
    }
    (*account).stored_one_time_key_count() as isize
}

/// Yüklenen anahtarları "yayınlandı" olarak işaretler; bundan sonra
/// `sc_account_one_time_keys` onları döndürmez.
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli ve tek bir thread'den kullanilan bir handle olmali.
pub unsafe extern "C" fn sc_account_mark_keys_as_published(account: *mut Account) -> i32 {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return -1;
    }
    (*account).mark_keys_as_published();
    0
}

/// Last-resort fallback anahtarı üretir ve geçerli olanı döndürür.
/// libsignal'daki signed prekey'in karşılığı.
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli ve tek bir thread'den kullanilan bir handle olmali.
pub unsafe extern "C" fn sc_account_generate_fallback_key(account: *mut Account) -> *mut c_char {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return ptr::null_mut();
    }
    (*account).generate_fallback_key();
    let map: serde_json::Map<String, serde_json::Value> = (*account)
        .fallback_key()
        .into_iter()
        .map(|(id, key)| (id.to_base64(), serde_json::Value::String(key.to_base64())))
        .collect();
    to_c_string(serde_json::Value::Object(map).to_string())
}

/// Karşı tarafın identity + tek kullanımlık anahtarıyla giden oturum kurar.
/// libsignal'daki `SessionBuilder.process(PreKeyBundle)` karşılığı.
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli, iki anahtar argumani NUL sonlu gecerli string olmali.
pub unsafe extern "C" fn sc_account_create_outbound_session(
    account: *const Account,
    their_identity_key: *const c_char,
    their_one_time_key: *const c_char,
) -> *mut Session {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return ptr::null_mut();
    }
    let Some(identity) = borrow_str(their_identity_key, "their_identity_key") else {
        return ptr::null_mut();
    };
    let Some(one_time) = borrow_str(their_one_time_key, "their_one_time_key") else {
        return ptr::null_mut();
    };
    let Some(identity) = parse_curve_key(identity, "their_identity_key") else {
        return ptr::null_mut();
    };
    let Some(one_time) = parse_curve_key(one_time, "their_one_time_key") else {
        return ptr::null_mut();
    };
    let session =
        (*account).create_outbound_session(SessionConfig::version_2(), identity, one_time);
    Box::into_raw(Box::new(session))
}

/// Gelen PreKey mesajından oturum kurar ve ilk mesajın plaintext'ini base64
/// olarak döndürür. Oturum `out_session` ile verilir.
///
/// Başarıda `out_session` doldurulur ve base64 plaintext döner. Hata halinde
/// `null` döner ve `out_session` değişmez.
#[no_mangle]
///
/// # Safety
///
/// `account` gecerli, string argumanlar NUL sonlu, `out_session` yazilabilir bir pointer olmali.
pub unsafe extern "C" fn sc_account_create_inbound_session(
    account: *mut Account,
    their_identity_key: *const c_char,
    pre_key_message: *const c_char,
    out_session: *mut *mut Session,
) -> *mut c_char {
    clear_error();
    if account.is_null() {
        set_error("account null olamaz");
        return ptr::null_mut();
    }
    if out_session.is_null() {
        set_error("out_session null olamaz");
        return ptr::null_mut();
    }
    let Some(identity) = borrow_str(their_identity_key, "their_identity_key") else {
        return ptr::null_mut();
    };
    let Some(message) = borrow_str(pre_key_message, "pre_key_message") else {
        return ptr::null_mut();
    };
    let Some(identity) = parse_curve_key(identity, "their_identity_key") else {
        return ptr::null_mut();
    };
    let message = match PreKeyMessage::from_base64(message) {
        Ok(decoded) => decoded,
        Err(error) => {
            set_error_code(ERROR_DECODE);
            set_error(format!("pre-key mesaji cozulemedi: {error}"));
            return ptr::null_mut();
        }
    };
    // Kimlik once ve AYRI kontrol edilir: uyusmazlik bir oturum hatasi
    // degil, guven olayidir. Hesap durumu degismez (tek kullanimlik anahtar
    // tuketilmez), boylece kullanici yeni kimligi onayladiktan sonra AYNI
    // mesaj cozulebilir.
    if message.identity_key() != identity {
        set_error_code(ERROR_IDENTITY_MISMATCH);
        set_error("gelen mesajin kimligi pinlenen kimlikle uyusmuyor");
        return ptr::null_mut();
    }
    match (*account).create_inbound_session(identity, &message) {
        Ok(result) => {
            let plaintext = B64.encode(result.plaintext);
            *out_session = Box::into_raw(Box::new(result.session));
            to_c_string(plaintext)
        }
        Err(error) => {
            set_error_code(ERROR_SESSION);
            set_error(format!("gelen oturum kurulamadi: {error}"));
            ptr::null_mut()
        }
    }
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

#[no_mangle]
///
/// # Safety
///
/// `session` bir oturum kurucusunun donusu olmali ve bir kez serbest birakilmali.
pub unsafe extern "C" fn sc_session_free(session: *mut Session) {
    if !session.is_null() {
        unsafe { drop(Box::from_raw(session)) };
    }
}

#[no_mangle]
///
/// # Safety
///
/// `session` gecerli, `pickle_key` tam 32 okunabilir bayt olmali.
pub unsafe extern "C" fn sc_session_pickle(
    session: *const Session,
    pickle_key: *const u8,
) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("session null olamaz");
        return ptr::null_mut();
    }
    let Some(key) = borrow_key(pickle_key) else {
        return ptr::null_mut();
    };
    to_c_string((*session).pickle().encrypt(key))
}

#[no_mangle]
///
/// # Safety
///
/// `pickle` NUL sonlu gecerli string, `pickle_key` tam 32 okunabilir bayt olmali.
pub unsafe extern "C" fn sc_session_from_pickle(
    pickle: *const c_char,
    pickle_key: *const u8,
) -> *mut Session {
    clear_error();
    let Some(pickle) = borrow_str(pickle, "pickle") else {
        return ptr::null_mut();
    };
    let Some(key) = borrow_key(pickle_key) else {
        return ptr::null_mut();
    };
    match vodozemac::olm::SessionPickle::from_encrypted(pickle, key) {
        Ok(decoded) => Box::into_raw(Box::new(Session::from_pickle(decoded))),
        Err(error) => {
            set_error_code(ERROR_PICKLE);
            set_error(format!("session pickle acilamadi: {error}"));
            ptr::null_mut()
        }
    }
}

/// Oturum kimliği. Aynı iki taraf arasındaki oturumları ayırt etmek için.
#[no_mangle]
///
/// # Safety
///
/// `session` gecerli bir oturum handle'i olmali.
pub unsafe extern "C" fn sc_session_id(session: *const Session) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("session null olamaz");
        return ptr::null_mut();
    }
    to_c_string((*session).session_id())
}

/// Şifreler. Dönen: `{"type":0|1,"body":"<b64>"}`
/// `type` 0 = PreKey mesajı (oturumun ilk mesajı), 1 = normal mesaj.
///
/// Şifreleme ratchet durumunu ilerletir; çağıran oturumu yeniden pickle'layıp
/// saklamak ZORUNDA, aksi halde aynı mesaj anahtarı tekrar kullanılır.
#[no_mangle]
///
/// # Safety
///
/// `session` gecerli; `plaintext`/`plaintext_len` okunabilir bir aralik tanimlamali.
pub unsafe extern "C" fn sc_session_encrypt(
    session: *mut Session,
    plaintext: *const u8,
    plaintext_len: usize,
) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("session null olamaz");
        return ptr::null_mut();
    }
    let Some(bytes) = borrow_bytes(plaintext, plaintext_len) else {
        return ptr::null_mut();
    };
    let message = (*session).encrypt(bytes);
    let (message_type, ciphertext) = message.to_parts();
    to_c_string(
        serde_json::json!({
            "type": message_type,
            "body": B64.encode(ciphertext),
        })
        .to_string(),
    )
}

/// Çözer. `message_type` ve `body` `sc_session_encrypt` çıktısından gelir.
/// Dönen: base64 plaintext.
#[no_mangle]
///
/// # Safety
///
/// `session` gecerli, `body` NUL sonlu gecerli bir string olmali.
pub unsafe extern "C" fn sc_session_decrypt(
    session: *mut Session,
    message_type: usize,
    body: *const c_char,
) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("session null olamaz");
        return ptr::null_mut();
    }
    let Some(body) = borrow_str(body, "body") else {
        return ptr::null_mut();
    };
    let ciphertext = match B64.decode(body) {
        Ok(decoded) => decoded,
        Err(error) => {
            set_error(format!("body base64 degil: {error}"));
            return ptr::null_mut();
        }
    };
    let message = match OlmMessage::from_parts(message_type, &ciphertext) {
        Ok(decoded) => decoded,
        Err(error) => {
            set_error_code(ERROR_DECODE);
            set_error(format!("mesaj cozulemedi: {error}"));
            return ptr::null_mut();
        }
    };
    match (*session).decrypt(&message) {
        Ok(plaintext) => to_c_string(B64.encode(plaintext)),
        Err(error) => {
            use vodozemac::olm::DecryptionError as E;
            set_error_code(match error {
                // Tuketilmis veya atlanmis anahtar: tekrar teslim ya da
                // sirasiz cerceve. Oturum saglam, SIFIRLANMAMALI.
                E::MissingMessageKey(_) => ERROR_DECRYPT_MISSING_KEY,
                E::TooBigMessageGap(_, _) => ERROR_DECRYPT_GAP,
                E::InvalidMAC(_) | E::InvalidMACLength(_, _) | E::InvalidPadding(_) => {
                    ERROR_DECRYPT_INVALID
                }
            });
            set_error(format!("sifre cozme basarisiz: {error}"));
            ptr::null_mut()
        }
    }
}

// ---------------------------------------------------------------------------
// Testler: C ABI'nin kendisi uzerinden, Dart'in gordugu yoldan.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn c(value: &str) -> CString {
        CString::new(value).expect("NUL yok")
    }

    unsafe fn take_string(ptr: *mut c_char) -> String {
        assert!(!ptr.is_null(), "beklenmeyen null; hata: {:?}", last_error());
        let text = CStr::from_ptr(ptr).to_str().expect("utf8").to_owned();
        sc_string_free(ptr);
        text
    }

    unsafe fn last_error() -> Option<String> {
        let ptr = sc_last_error();
        if ptr.is_null() {
            return None;
        }
        let text = CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_owned());
        sc_string_free(ptr);
        text
    }

    #[test]
    fn abi_surumu_sabit() {
        // 1 = Olm. 2 = Megolm. 3 = sc_last_error_code() eklendi.
        // Degistirilirse `include/securechat_crypto.h` ve Dart tarafindaki
        // `expectedAbiVersion` birlikte guncellenmeli; Dart testi ucunu de
        // birbirine bagliyor.
        assert_eq!(sc_abi_version(), 3);
    }

    #[test]
    fn kimlik_uyusmazligi_ayri_siniftir_ve_hesabi_degistirmez() {
        // Pinlenen kimlikle uyusmayan bir PreKey mesaji oturum hatasi DEGIL,
        // guven olayidir: ayri sinif doner, tek kullanimlik anahtar
        // tuketilmez ve dogru kimlik onaylaninca AYNI mesaj cozulur.
        unsafe {
            let alice = sc_account_new();
            let bob = sc_account_new();
            let mallory = sc_account_new();
            let bob_keys: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_generate_one_time_keys(bob, 1)))
                    .expect("json");
            let bob_otk = bob_keys.as_object().expect("obje").values().next()
                .expect("anahtar").as_str().expect("b64").to_owned();
            let identity = |account: *const Account| -> String {
                let keys: serde_json::Value =
                    serde_json::from_str(&take_string(sc_account_identity_keys(account)))
                        .expect("json");
                keys["curve25519"].as_str().expect("curve").to_owned()
            };
            let session = sc_account_create_outbound_session(
                alice,
                c(&identity(bob)).as_ptr(),
                c(&bob_otk).as_ptr(),
            );
            assert!(!session.is_null());
            let envelope: serde_json::Value = serde_json::from_str(&take_string(
                sc_session_encrypt(session, b"yeni cihaz".as_ptr(), 10),
            ))
            .expect("json");
            let body = envelope["body"].as_str().expect("body").to_owned();
            let prekey_b64 = match OlmMessage::from_parts(0, &B64.decode(&body).expect("b64"))
                .expect("mesaj")
            {
                OlmMessage::PreKey(message) => message.to_base64(),
                _ => panic!("PreKey bekleniyordu"),
            };

            // Bob baska bir kimligi (mallory) pinlemis.
            let mut out: *mut Session = ptr::null_mut();
            let result = sc_account_create_inbound_session(
                bob,
                c(&identity(mallory)).as_ptr(),
                c(&prekey_b64).as_ptr(),
                &mut out,
            );
            assert!(result.is_null());
            assert!(out.is_null());
            assert_eq!(sc_last_error_code(), ERROR_IDENTITY_MISMATCH);
            assert_eq!(sc_account_stored_one_time_key_count(bob), 1, "OTK tuketilmemeli");

            // Kimlik onaylandiktan sonra AYNI mesaj cozulur.
            let decrypted = take_string(sc_account_create_inbound_session(
                bob,
                c(&identity(alice)).as_ptr(),
                c(&prekey_b64).as_ptr(),
                &mut out,
            ));
            assert!(!out.is_null());
            assert_eq!(B64.decode(decrypted).expect("b64"), b"yeni cihaz");

            sc_session_free(out);
            sc_session_free(session);
            sc_account_free(alice);
            sc_account_free(bob);
            sc_account_free(mallory);
        }
    }

    #[test]
    fn tam_olm_akisi_c_abi_uzerinden() {
        unsafe {
            let key = [9u8; 32];
            let alice = sc_account_new();
            let bob = sc_account_new();

            // Bob prekey havuzunu doldurur ve sunucuya yukleyecegi degerleri verir.
            let bob_keys: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_generate_one_time_keys(bob, 5)))
                    .expect("json");
            assert_eq!(bob_keys.as_object().expect("obje").len(), 5);
            assert_eq!(sc_account_stored_one_time_key_count(bob), 5);

            let bob_identity: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_identity_keys(bob))).expect("json");
            let bob_curve = bob_identity["curve25519"]
                .as_str()
                .expect("curve")
                .to_owned();
            let bob_otk = bob_keys
                .as_object()
                .expect("obje")
                .values()
                .next()
                .expect("anahtar")
                .as_str()
                .expect("b64")
                .to_owned();

            // Alice giden oturumu kurar ve ilk mesaji sifreler.
            let session = sc_account_create_outbound_session(
                alice,
                c(&bob_curve).as_ptr(),
                c(&bob_otk).as_ptr(),
            );
            assert!(!session.is_null(), "oturum kurulamadi: {:?}", last_error());

            let plaintext = b"vodozemac uzerinden ilk mesaj";
            let envelope: serde_json::Value = serde_json::from_str(&take_string(
                sc_session_encrypt(session, plaintext.as_ptr(), plaintext.len()),
            ))
            .expect("json");
            assert_eq!(
                envelope["type"].as_u64(),
                Some(0),
                "ilk mesaj PreKey olmali"
            );
            let body = envelope["body"].as_str().expect("body").to_owned();

            // Bob gelen oturumu kurar ve cozer.
            let alice_identity: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_identity_keys(alice))).expect("json");
            let alice_curve = alice_identity["curve25519"].as_str().expect("curve");

            let prekey_b64 = {
                let ciphertext = B64.decode(&body).expect("b64");
                match OlmMessage::from_parts(0, &ciphertext).expect("mesaj") {
                    OlmMessage::PreKey(message) => message.to_base64(),
                    _ => panic!("PreKey bekleniyordu"),
                }
            };

            let mut bob_session: *mut Session = ptr::null_mut();
            let decrypted = take_string(sc_account_create_inbound_session(
                bob,
                c(alice_curve).as_ptr(),
                c(&prekey_b64).as_ptr(),
                &mut bob_session,
            ));
            assert!(!bob_session.is_null());
            assert_eq!(B64.decode(decrypted).expect("b64"), plaintext);

            // Ters yon: Bob cevap verir, Alice cozer. Ratchet iki yonlu.
            let reply = b"cevap";
            let reply_envelope: serde_json::Value = serde_json::from_str(&take_string(
                sc_session_encrypt(bob_session, reply.as_ptr(), reply.len()),
            ))
            .expect("json");
            let reply_type = reply_envelope["type"].as_u64().expect("type") as usize;
            let reply_body = reply_envelope["body"].as_str().expect("body").to_owned();
            let alice_got = take_string(sc_session_decrypt(
                session,
                reply_type,
                c(&reply_body).as_ptr(),
            ));
            assert_eq!(B64.decode(alice_got).expect("b64"), reply);

            // Pickle gidip gelince oturum calismaya devam ediyor.
            let pickled = take_string(sc_session_pickle(session, key.as_ptr()));
            let restored = sc_session_from_pickle(c(&pickled).as_ptr(), key.as_ptr());
            assert!(!restored.is_null(), "pickle acilamadi: {:?}", last_error());
            assert_eq!(
                take_string(sc_session_id(restored)),
                take_string(sc_session_id(session))
            );

            sc_session_free(restored);
            sc_session_free(bob_session);
            sc_session_free(session);
            sc_account_free(alice);
            sc_account_free(bob);
        }
    }

    #[test]
    fn hesap_pickle_gidip_gelir_ve_anahtarlar_korunur() {
        unsafe {
            let key = [3u8; 32];
            let account = sc_account_new();
            take_string(sc_account_generate_one_time_keys(account, 4));
            take_string(sc_account_generate_fallback_key(account));
            let before = take_string(sc_account_identity_keys(account));

            let pickled = take_string(sc_account_pickle(account, key.as_ptr()));
            let restored = sc_account_from_pickle(c(&pickled).as_ptr(), key.as_ptr());
            assert!(!restored.is_null(), "acilamadi: {:?}", last_error());

            assert_eq!(take_string(sc_account_identity_keys(restored)), before);
            assert_eq!(sc_account_stored_one_time_key_count(restored), 4);

            sc_account_free(restored);
            sc_account_free(account);
        }
    }

    #[test]
    fn yayinlanan_anahtarlar_bir_daha_dondurulmez() {
        unsafe {
            let account = sc_account_new();
            take_string(sc_account_generate_one_time_keys(account, 3));
            assert_eq!(sc_account_mark_keys_as_published(account), 0);
            let remaining: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_one_time_keys(account)))
                    .expect("json");
            assert!(remaining.as_object().expect("obje").is_empty());
            // Havuz sunucu tarafinda hala dolu; yalnizca "yayinlanmamis" listesi bosaldi.
            assert_eq!(sc_account_stored_one_time_key_count(account), 3);
            sc_account_free(account);
        }
    }

    /// Tekrar teslim edilen cerceve oturumu OLDURMEMELI.
    ///
    /// Eski libsignal kodu `DuplicateMessageException`'i bilerek "oturum
    /// kullanilamaz" sinifinin DISINDA tutuyordu: tekrar teslim saglikli bir
    /// oturumda da olagan ve oturumu sifirlamak tekrar oynatilan tek bir
    /// cerceveyle oturumu yok etme imkani verirdi. vodozemac'ta ayni durum
    /// `MissingMessageKey` olarak geliyor; kodun bunu ayri siniflandirdigi
    /// burada kanitlanir.
    #[test]
    fn tekrar_teslim_missing_key_olarak_siniflanir() {
        unsafe {
            let alice = sc_account_new();
            let bob = sc_account_new();
            let bob_keys: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_generate_one_time_keys(bob, 1)))
                    .expect("json");
            let bob_identity: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_identity_keys(bob))).expect("json");
            let alice_identity: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_identity_keys(alice))).expect("json");

            let session = sc_account_create_outbound_session(
                alice,
                c(bob_identity["curve25519"].as_str().expect("curve")).as_ptr(),
                c(bob_keys
                    .as_object()
                    .expect("obje")
                    .values()
                    .next()
                    .expect("anahtar")
                    .as_str()
                    .expect("b64"))
                .as_ptr(),
            );

            // Bob gelen oturumu kurar ve ilk mesaji cozer.
            let envelope: serde_json::Value = serde_json::from_str(&take_string(
                sc_session_encrypt(session, b"bir".as_ptr(), 3),
            ))
            .expect("json");
            let body = envelope["body"].as_str().expect("body").to_owned();
            let prekey_b64 = {
                let ciphertext = B64.decode(&body).expect("b64");
                match OlmMessage::from_parts(0, &ciphertext).expect("mesaj") {
                    OlmMessage::PreKey(message) => message.to_base64(),
                    _ => panic!("PreKey bekleniyordu"),
                }
            };
            let mut bob_session: *mut Session = ptr::null_mut();
            take_string(sc_account_create_inbound_session(
                bob,
                c(alice_identity["curve25519"].as_str().expect("curve")).as_ptr(),
                c(&prekey_b64).as_ptr(),
                &mut bob_session,
            ));

            // Alice ikinci mesaji gonderir, Bob cozer.
            let second: serde_json::Value = serde_json::from_str(&take_string(sc_session_encrypt(
                session,
                b"iki".as_ptr(),
                3,
            )))
            .expect("json");
            let second_type = second["type"].as_u64().expect("type") as usize;
            let second_body = second["body"].as_str().expect("body").to_owned();
            take_string(sc_session_decrypt(
                bob_session,
                second_type,
                c(&second_body).as_ptr(),
            ));

            // AYNI cerceve tekrar: anahtar tuketilmis.
            let replay = sc_session_decrypt(bob_session, second_type, c(&second_body).as_ptr());
            assert!(replay.is_null());
            assert_eq!(
                sc_last_error_code(),
                ERROR_DECRYPT_MISSING_KEY,
                "tekrar teslim MissingMessageKey olarak siniflanmali, hata: {:?}",
                last_error()
            );

            sc_session_free(bob_session);
            sc_session_free(session);
            sc_account_free(bob);
            sc_account_free(alice);
        }
    }

    /// Bozulmus ciphertext MAC hatasi verir ve oturum kullanilamaz sayilir.
    #[test]
    fn bozulmus_mesaj_invalid_olarak_siniflanir() {
        unsafe {
            let alice = sc_account_new();
            let bob = sc_account_new();
            let bob_keys: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_generate_one_time_keys(bob, 1)))
                    .expect("json");
            let bob_identity: serde_json::Value =
                serde_json::from_str(&take_string(sc_account_identity_keys(bob))).expect("json");
            let session = sc_account_create_outbound_session(
                alice,
                c(bob_identity["curve25519"].as_str().expect("curve")).as_ptr(),
                c(bob_keys
                    .as_object()
                    .expect("obje")
                    .values()
                    .next()
                    .expect("anahtar")
                    .as_str()
                    .expect("b64"))
                .as_ptr(),
            );

            // Alice kendi oturumunda, kendi urettigi mesaji cozmeye calisir:
            // anahtar zinciri uymaz ve MAC dogrulanmaz.
            let envelope: serde_json::Value =
                serde_json::from_str(&take_string(sc_session_encrypt(session, b"x".as_ptr(), 1)))
                    .expect("json");
            let body = envelope["body"].as_str().expect("body").to_owned();
            let result = sc_session_decrypt(session, 1, c(&body).as_ptr());
            assert!(result.is_null());
            let code = sc_last_error_code();
            assert!(
                code == ERROR_DECRYPT_INVALID || code == ERROR_DECODE,
                "beklenen INVALID/DECODE, bulunan {code}; hata: {:?}",
                last_error()
            );

            sc_session_free(session);
            sc_account_free(bob);
            sc_account_free(alice);
        }
    }

    #[test]
    fn hatalar_null_ve_mesajla_bildirilir() {
        unsafe {
            let account = sc_account_new();
            let session = sc_account_create_outbound_session(
                account,
                c("gecersiz-anahtar").as_ptr(),
                c("gecersiz-anahtar").as_ptr(),
            );
            assert!(session.is_null());
            let message = last_error().expect("hata mesaji bekleniyordu");
            assert!(message.contains("cozulemedi"), "{message}");
            sc_account_free(account);
        }
    }
}
