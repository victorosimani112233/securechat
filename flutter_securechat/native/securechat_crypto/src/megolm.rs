//! Megolm grup ratchet'inin C ABI yüzeyi.
//!
//! Sözleşme `lib.rs` ile aynı: pointer dönenlerde `null` = hata, ayrıntı
//! `sc_last_error()`, dönen stringler `sc_string_free` ile bırakılır,
//! handle'lar `*_free` ile yok edilir.
//!
//! GEÇMİŞ PAYLAŞIMI BİLEREK YOK: vodozemac `export_at` ve `import` ile bir
//! oturum anahtarının DAHA ERKEN bir indeksten paylaşılmasına izin veriyor.
//! Bu, yeni katılan birine geçmiş mesajları açma imkânı verir ve 2016 NCC
//! Group denetiminin Megolm'da işaret ettiği zayıflığın dayandığı yer de
//! burası. Ürün geçmiş paylaşmadığı için o iki fonksiyon ABI'ye hiç
//! konmadı: yalnızca güncel `session_key` dağıtılabilir.

use std::ffi::c_char;
use std::ptr;

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use vodozemac::megolm::{
    GroupSession, GroupSessionPickle, InboundGroupSession, InboundGroupSessionPickle,
    MegolmMessage, SessionConfig, SessionKey,
};

use crate::{borrow_bytes, borrow_key, borrow_str, clear_error, set_error, to_c_string};

// ---------------------------------------------------------------------------
// GroupSession — giden
// ---------------------------------------------------------------------------

/// Yeni bir giden grup oturumu açar. Oluşturan taraf mesajları bununla
/// şifreler ve `sc_group_session_key` ile üyelere dağıtır.
#[no_mangle]
pub extern "C" fn sc_group_session_new() -> *mut GroupSession {
    clear_error();
    Box::into_raw(Box::new(GroupSession::new(SessionConfig::version_2())))
}

/// # Safety
///
/// `session` `sc_group_session_new` / `_from_pickle` dönüşü olmalı ve bir kez
/// serbest bırakılmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_group_session_free(session: *mut GroupSession) {
    if !session.is_null() {
        drop(Box::from_raw(session));
    }
}

/// # Safety
///
/// `pickle` NUL sonlu geçerli bir string, `pickle_key` tam 32 okunabilir
/// bayt olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_group_session_from_pickle(
    pickle: *const c_char,
    pickle_key: *const u8,
) -> *mut GroupSession {
    clear_error();
    let Some(pickle) = borrow_str(pickle, "pickle") else {
        return ptr::null_mut();
    };
    let Some(key) = borrow_key(pickle_key) else {
        return ptr::null_mut();
    };
    match GroupSessionPickle::from_encrypted(pickle, key) {
        Ok(decoded) => Box::into_raw(Box::new(GroupSession::from_pickle(decoded))),
        Err(error) => {
            set_error(format!("group session pickle acilamadi: {error}"));
            ptr::null_mut()
        }
    }
}

/// # Safety
///
/// `session` geçerli, `pickle_key` tam 32 okunabilir bayt olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_group_session_pickle(
    session: *const GroupSession,
    pickle_key: *const u8,
) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("group session null olamaz");
        return ptr::null_mut();
    }
    let Some(key) = borrow_key(pickle_key) else {
        return ptr::null_mut();
    };
    to_c_string((*session).pickle().encrypt(key))
}

/// # Safety
///
/// `session` geçerli bir grup oturumu handle'ı olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_group_session_id(session: *const GroupSession) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("group session null olamaz");
        return ptr::null_mut();
    }
    to_c_string((*session).session_id())
}

/// Üyelere dağıtılacak oturum anahtarı, base64.
///
/// libsignal'daki `SenderKeyDistributionMessage` karşılığı. Her alıcıya
/// ayrı ayrı, uçtan uca şifreli direct kanal üzerinden gönderilir.
///
/// # Safety
///
/// `session` geçerli bir grup oturumu handle'ı olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_group_session_key(session: *const GroupSession) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("group session null olamaz");
        return ptr::null_mut();
    }
    to_c_string((*session).session_key().to_base64())
}

/// Şifreler; dönen base64 `MegolmMessage`.
///
/// Mesaj indeksini ilerletir; çağıran oturumu yeniden pickle'layıp saklamak
/// ZORUNDA, aksi halde aynı indeks tekrar kullanılır.
///
/// # Safety
///
/// `session` geçerli; `plaintext`/`plaintext_len` okunabilir bir aralık
/// tanımlamalı.
#[no_mangle]
pub unsafe extern "C" fn sc_group_session_encrypt(
    session: *mut GroupSession,
    plaintext: *const u8,
    plaintext_len: usize,
) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("group session null olamaz");
        return ptr::null_mut();
    }
    let Some(bytes) = borrow_bytes(plaintext, plaintext_len) else {
        return ptr::null_mut();
    };
    to_c_string((*session).encrypt(bytes).to_base64())
}

// ---------------------------------------------------------------------------
// InboundGroupSession — gelen
// ---------------------------------------------------------------------------

/// Dağıtılan oturum anahtarından gelen grup oturumu kurar.
///
/// # Safety
///
/// `session_key` NUL sonlu geçerli bir string olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_inbound_group_session_new(
    session_key: *const c_char,
) -> *mut InboundGroupSession {
    clear_error();
    let Some(encoded) = borrow_str(session_key, "session_key") else {
        return ptr::null_mut();
    };
    let key = match SessionKey::from_base64(encoded) {
        Ok(key) => key,
        Err(error) => {
            set_error(format!("oturum anahtari cozulemedi: {error}"));
            return ptr::null_mut();
        }
    };
    Box::into_raw(Box::new(InboundGroupSession::new(
        &key,
        SessionConfig::version_2(),
    )))
}

/// # Safety
///
/// `session` bir gelen grup oturumu kurucusunun dönüşü olmalı ve bir kez
/// serbest bırakılmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_inbound_group_session_free(session: *mut InboundGroupSession) {
    if !session.is_null() {
        drop(Box::from_raw(session));
    }
}

/// # Safety
///
/// `pickle` NUL sonlu geçerli bir string, `pickle_key` tam 32 okunabilir
/// bayt olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_inbound_group_session_from_pickle(
    pickle: *const c_char,
    pickle_key: *const u8,
) -> *mut InboundGroupSession {
    clear_error();
    let Some(pickle) = borrow_str(pickle, "pickle") else {
        return ptr::null_mut();
    };
    let Some(key) = borrow_key(pickle_key) else {
        return ptr::null_mut();
    };
    match InboundGroupSessionPickle::from_encrypted(pickle, key) {
        Ok(decoded) => Box::into_raw(Box::new(InboundGroupSession::from_pickle(decoded))),
        Err(error) => {
            set_error(format!("inbound group session pickle acilamadi: {error}"));
            ptr::null_mut()
        }
    }
}

/// # Safety
///
/// `session` geçerli, `pickle_key` tam 32 okunabilir bayt olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_inbound_group_session_pickle(
    session: *const InboundGroupSession,
    pickle_key: *const u8,
) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("inbound group session null olamaz");
        return ptr::null_mut();
    }
    let Some(key) = borrow_key(pickle_key) else {
        return ptr::null_mut();
    };
    to_c_string((*session).pickle().encrypt(key))
}

/// # Safety
///
/// `session` geçerli bir gelen grup oturumu handle'ı olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_inbound_group_session_id(
    session: *const InboundGroupSession,
) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("inbound group session null olamaz");
        return ptr::null_mut();
    }
    to_c_string((*session).session_id())
}

/// Çözer. Dönen: `{"plaintext":"<b64>","messageIndex":<u32>}`
///
/// `messageIndex` REPLAY TESPITI icindir: her plaintext bir oturumda tek bir
/// indeksle şifrelenir, yani aynı indeksin ikinci kez görülmesi tekrar
/// oynatmadır. Çağıran bunu saklayıp kontrol etmek zorunda; kütüphane
/// kendisi takip etmiyor.
///
/// # Safety
///
/// `session` geçerli, `message` NUL sonlu geçerli bir string olmalı.
#[no_mangle]
pub unsafe extern "C" fn sc_inbound_group_session_decrypt(
    session: *mut InboundGroupSession,
    message: *const c_char,
) -> *mut c_char {
    clear_error();
    if session.is_null() {
        set_error("inbound group session null olamaz");
        return ptr::null_mut();
    }
    let Some(encoded) = borrow_str(message, "message") else {
        return ptr::null_mut();
    };
    let parsed = match MegolmMessage::from_base64(encoded) {
        Ok(parsed) => parsed,
        Err(error) => {
            set_error(format!("megolm mesaji cozulemedi: {error}"));
            return ptr::null_mut();
        }
    };
    match (*session).decrypt(&parsed) {
        Ok(decrypted) => to_c_string(
            serde_json::json!({
                "plaintext": B64.encode(decrypted.plaintext),
                "messageIndex": decrypted.message_index,
            })
            .to_string(),
        ),
        Err(error) => {
            set_error(format!("grup sifre cozme basarisiz: {error}"));
            ptr::null_mut()
        }
    }
}

// ---------------------------------------------------------------------------
// Testler: C ABI uzerinden, Dart'in gordugu yoldan.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::{CStr, CString};

    fn c(value: &str) -> CString {
        CString::new(value).expect("NUL yok")
    }

    unsafe fn take_string(ptr: *mut c_char) -> String {
        assert!(!ptr.is_null(), "beklenmeyen null; hata: {:?}", last_error());
        let text = CStr::from_ptr(ptr).to_str().expect("utf8").to_owned();
        crate::sc_string_free(ptr);
        text
    }

    unsafe fn last_error() -> Option<String> {
        let ptr = crate::sc_last_error();
        if ptr.is_null() {
            return None;
        }
        let text = CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_owned());
        crate::sc_string_free(ptr);
        text
    }

    #[test]
    fn grup_akisi_dagitim_sifrele_coz() {
        unsafe {
            let outbound = sc_group_session_new();
            let session_key = take_string(sc_group_session_key(outbound));
            let outbound_id = take_string(sc_group_session_id(outbound));

            // Uye, dagitilan anahtardan gelen oturumu kurar.
            let inbound = sc_inbound_group_session_new(c(&session_key).as_ptr());
            assert!(!inbound.is_null(), "kurulamadi: {:?}", last_error());
            assert_eq!(
                take_string(sc_inbound_group_session_id(inbound)),
                outbound_id
            );

            let plaintext = b"gruba megolm uzerinden";
            let message = take_string(sc_group_session_encrypt(
                outbound,
                plaintext.as_ptr(),
                plaintext.len(),
            ));

            let decrypted: serde_json::Value = serde_json::from_str(&take_string(
                sc_inbound_group_session_decrypt(inbound, c(&message).as_ptr()),
            ))
            .expect("json");
            assert_eq!(
                B64.decode(decrypted["plaintext"].as_str().expect("b64"))
                    .expect("cozulebilir"),
                plaintext
            );
            assert_eq!(decrypted["messageIndex"].as_u64(), Some(0));

            sc_inbound_group_session_free(inbound);
            sc_group_session_free(outbound);
        }
    }

    #[test]
    fn mesaj_indeksi_her_sifrelemede_ilerler() {
        unsafe {
            let outbound = sc_group_session_new();
            let session_key = take_string(sc_group_session_key(outbound));
            let inbound = sc_inbound_group_session_new(c(&session_key).as_ptr());

            let mut indices = Vec::new();
            for _ in 0..3 {
                let message = take_string(sc_group_session_encrypt(outbound, b"x".as_ptr(), 1));
                let decrypted: serde_json::Value = serde_json::from_str(&take_string(
                    sc_inbound_group_session_decrypt(inbound, c(&message).as_ptr()),
                ))
                .expect("json");
                indices.push(decrypted["messageIndex"].as_u64().expect("index"));
            }

            // Replay tespiti buna dayaniyor: indeks tekrar etmemeli.
            assert_eq!(indices, vec![0, 1, 2]);

            sc_inbound_group_session_free(inbound);
            sc_group_session_free(outbound);
        }
    }

    #[test]
    fn pickle_gidip_gelince_oturum_devam_eder() {
        unsafe {
            let key = [5u8; 32];
            let outbound = sc_group_session_new();
            let session_key = take_string(sc_group_session_key(outbound));
            let inbound = sc_inbound_group_session_new(c(&session_key).as_ptr());

            // Giden tarafta bir mesaj uretip indeksi ilerlet.
            take_string(sc_group_session_encrypt(outbound, b"ilk".as_ptr(), 3));

            let outbound_pickle = take_string(sc_group_session_pickle(outbound, key.as_ptr()));
            let restored_outbound =
                sc_group_session_from_pickle(c(&outbound_pickle).as_ptr(), key.as_ptr());
            assert!(!restored_outbound.is_null(), "{:?}", last_error());

            let inbound_pickle =
                take_string(sc_inbound_group_session_pickle(inbound, key.as_ptr()));
            let restored_inbound =
                sc_inbound_group_session_from_pickle(c(&inbound_pickle).as_ptr(), key.as_ptr());
            assert!(!restored_inbound.is_null(), "{:?}", last_error());

            // Geri yuklenen giden oturum, geri yuklenen gelen oturumun
            // cozebilecegi mesaj uretmeye devam ediyor: indeks kayipsiz tasindi.
            let message = take_string(sc_group_session_encrypt(
                restored_outbound,
                b"ikinci".as_ptr(),
                6,
            ));
            let decrypted: serde_json::Value = serde_json::from_str(&take_string(
                sc_inbound_group_session_decrypt(restored_inbound, c(&message).as_ptr()),
            ))
            .expect("json");
            assert_eq!(decrypted["messageIndex"].as_u64(), Some(1));

            sc_inbound_group_session_free(restored_inbound);
            sc_inbound_group_session_free(inbound);
            sc_group_session_free(restored_outbound);
            sc_group_session_free(outbound);
        }
    }

    #[test]
    fn baska_oturumun_mesaji_cozulmez() {
        unsafe {
            let first = sc_group_session_new();
            let second = sc_group_session_new();
            let second_key = take_string(sc_group_session_key(second));
            let inbound = sc_inbound_group_session_new(c(&second_key).as_ptr());

            // Birinci oturumun mesaji, ikinci oturumun anahtariyla kurulan
            // gelen oturumda cozulmemeli.
            let message = take_string(sc_group_session_encrypt(first, b"yabanci".as_ptr(), 7));
            let result = sc_inbound_group_session_decrypt(inbound, c(&message).as_ptr());
            assert!(result.is_null());
            assert!(last_error().is_some());

            sc_inbound_group_session_free(inbound);
            sc_group_session_free(second);
            sc_group_session_free(first);
        }
    }

    #[test]
    fn gecersiz_oturum_anahtari_reddedilir() {
        unsafe {
            let session = sc_inbound_group_session_new(c("bu-anahtar-degil").as_ptr());
            assert!(session.is_null());
            let message = last_error().expect("hata mesaji bekleniyordu");
            assert!(message.contains("cozulemedi"), "{message}");
        }
    }
}
