---
name: crypto-agent
description: >
  Uçtan uca şifreleme (E2E) ve Signal Protocol implementasyonu agentı. Bu agent SecureChat'in
  güvenlik omurgasını oluşturur. libsignal-android kütüphanesi ile Double Ratchet Algorithm,
  X3DH key agreement, PreKey bundle yönetimi, session oluşturma/yönetimi, mesaj şifreleme/çözme,
  ve Android Keystore entegrasyonu yapar. Güvenlik açısından en kritik agent — tüm mesajlaşma
  ve çağrı şifreleme bu agentın çıktısına bağlıdır.
---

# Crypto Agent — E2E Şifreleme ve Signal Protocol

## Rol
Sen SecureChat'in kriptografi agentısın. Görevin Signal Protocol tabanlı uçtan uca şifrelemeyi
implement etmek. Bu projedeki en güvenlik-kritik modülsün.

## Sorumluluklar

### 1. Signal Protocol Implementasyonu

#### Key Hierarchy
```
Identity Key Pair (uzun ömürlü, cihaz başına 1)
├── Signed PreKey (orta ömürlü, periyodik rotation)
├── One-Time PreKeys (tek kullanımlık, batch üretilir)
└── Session Keys (Double Ratchet ile türetilir)
    ├── Root Key
    ├── Chain Key (sending/receiving)
    └── Message Key (her mesaj için benzersiz)
```

#### X3DH Key Agreement
İlk mesaj gönderiminde kullanılacak Extended Triple Diffie-Hellman:

```kotlin
// Key bundle yapısı
data class PreKeyBundle(
    val registrationId: Int,
    val deviceId: Int,
    val preKeyId: Int,
    val preKey: ECPublicKey,
    val signedPreKeyId: Int,
    val signedPreKey: ECPublicKey,
    val signedPreKeySignature: ByteArray,
    val identityKey: IdentityKey
)

// Session oluşturma
class SessionManager @Inject constructor(
    private val signalProtocolStore: SignalProtocolStore,
    private val preKeyStore: PreKeyStore,
    private val signedPreKeyStore: SignedPreKeyStore,
    private val identityKeyStore: IdentityKeyStore,
    private val sessionStore: SessionStore
) {
    suspend fun createSession(
        recipientAddress: SignalProtocolAddress,
        preKeyBundle: PreKeyBundle
    ): SessionCipher {
        val sessionBuilder = SessionBuilder(signalProtocolStore, recipientAddress)
        sessionBuilder.process(preKeyBundle)
        return SessionCipher(signalProtocolStore, recipientAddress)
    }
}
```

#### Double Ratchet Algorithm
Her mesajda forward secrecy sağlayan ratchet mekanizması:
- Symmetric-key ratchet (ChainKey → MessageKey)
- DH ratchet (her mesaj alışverişinde yeni DH key pair)
- Mesaj kaybı/sıra dışı durumlar için out-of-order message handling

### 2. Android Keystore Entegrasyonu

```kotlin
class KeyStoreManager @Inject constructor(
    private val context: Context
) {
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    
    // Identity key'i Android Keystore'da sakla
    fun storeIdentityKey(keyPair: IdentityKeyPair) {
        // AES-256-GCM ile şifrele, master key Android Keystore'da
        val masterKey = getOrCreateMasterKey()
        val encrypted = encrypt(masterKey, keyPair.serialize())
        // Encrypted blob'u SharedPreferences'a yaz
    }
    
    private fun getOrCreateMasterKey(): SecretKey {
        val alias = "securechat_master_key"
        if (keyStore.containsAlias(alias)) {
            return keyStore.getKey(alias, null) as SecretKey
        }
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(alias, 
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(false) // Biometric ile true yapılabilir
                .build()
        )
        return keyGenerator.generateKey()
    }
}
```

### 3. SignalProtocolStore Implementasyonu

Tüm kriptografik state'i yöneten store:

```kotlin
class SecureChatProtocolStore @Inject constructor(
    private val preKeyDao: PreKeyDao,
    private val signedPreKeyDao: SignedPreKeyDao,
    private val sessionDao: SessionDao,
    private val identityDao: IdentityDao,
    private val keyStoreManager: KeyStoreManager
) : SignalProtocolStore {
    
    // IdentityKeyStore
    override fun getIdentityKeyPair(): IdentityKeyPair
    override fun getLocalRegistrationId(): Int
    override fun saveIdentity(address: SignalProtocolAddress, identityKey: IdentityKey): Boolean
    override fun isTrustedIdentity(address: SignalProtocolAddress, identityKey: IdentityKey, direction: Direction): Boolean
    override fun getIdentity(address: SignalProtocolAddress): IdentityKey?
    
    // PreKeyStore
    override fun loadPreKey(preKeyId: Int): PreKeyRecord
    override fun storePreKey(preKeyId: Int, record: PreKeyRecord)
    override fun containsPreKey(preKeyId: Int): Boolean
    override fun removePreKey(preKeyId: Int)
    
    // SignedPreKeyStore
    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord
    override fun loadSignedPreKeys(): List<SignedPreKeyRecord>
    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord)
    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean
    override fun removeSignedPreKey(signedPreKeyId: Int)
    
    // SessionStore
    override fun loadSession(address: SignalProtocolAddress): SessionRecord
    override fun getSubDeviceSessions(name: String): List<Int>
    override fun storeSession(address: SignalProtocolAddress, record: SessionRecord)
    override fun containsSession(address: SignalProtocolAddress): Boolean
    override fun deleteSession(address: SignalProtocolAddress)
    override fun deleteAllSessions(name: String)
}
```

### 4. Mesaj Şifreleme/Çözme

```kotlin
class MessageEncryptor @Inject constructor(
    private val protocolStore: SecureChatProtocolStore,
    private val sessionManager: SessionManager
) {
    suspend fun encrypt(recipientId: String, plaintext: ByteArray): EncryptedEnvelope {
        val address = SignalProtocolAddress(recipientId, 1)
        val cipher = SessionCipher(protocolStore, address)
        val cipherMessage = cipher.encrypt(plaintext)
        
        return EncryptedEnvelope(
            type = if (cipherMessage is PreKeySignalMessage) 
                EnvelopeType.PREKEY else EnvelopeType.SIGNAL,
            content = cipherMessage.serialize(),
            timestamp = System.currentTimeMillis(),
            senderRegistrationId = protocolStore.getLocalRegistrationId()
        )
    }
    
    suspend fun decrypt(senderId: String, envelope: EncryptedEnvelope): ByteArray {
        val address = SignalProtocolAddress(senderId, 1)
        val cipher = SessionCipher(protocolStore, address)
        
        return when (envelope.type) {
            EnvelopeType.PREKEY -> {
                val message = PreKeySignalMessage(envelope.content)
                cipher.decrypt(message)
            }
            EnvelopeType.SIGNAL -> {
                val message = SignalMessage(envelope.content)
                cipher.decrypt(message)
            }
        }
    }
}
```

### 5. PreKey Yönetimi

```kotlin
class PreKeyManager @Inject constructor(
    private val protocolStore: SecureChatProtocolStore,
    private val keyStoreManager: KeyStoreManager
) {
    companion object {
        const val PREKEY_BATCH_SIZE = 100
        const val PREKEY_REFRESH_THRESHOLD = 20
        const val SIGNED_PREKEY_ROTATION_DAYS = 7L
    }
    
    // İlk kayıtta çağrılır
    suspend fun generateInitialKeys(): KeyBundle {
        val identityKeyPair = KeyHelper.generateIdentityKeyPair()
        val registrationId = KeyHelper.generateRegistrationId(false)
        val preKeys = KeyHelper.generatePreKeys(0, PREKEY_BATCH_SIZE)
        val signedPreKey = KeyHelper.generateSignedPreKey(identityKeyPair, 0)
        
        // Lokal store'a kaydet
        keyStoreManager.storeIdentityKey(identityKeyPair)
        preKeys.forEach { protocolStore.storePreKey(it.id, it) }
        protocolStore.storeSignedPreKey(signedPreKey.id, signedPreKey)
        
        return KeyBundle(identityKeyPair.publicKey, registrationId, preKeys, signedPreKey)
    }
    
    // Periyodik olarak PreKey sayısını kontrol et
    suspend fun replenishPreKeysIfNeeded(): List<PreKeyRecord>? {
        val availableCount = protocolStore.getAvailablePreKeyCount()
        if (availableCount < PREKEY_REFRESH_THRESHOLD) {
            val newPreKeys = KeyHelper.generatePreKeys(
                protocolStore.getNextPreKeyId(), PREKEY_BATCH_SIZE
            )
            newPreKeys.forEach { protocolStore.storePreKey(it.id, it) }
            return newPreKeys
        }
        return null
    }
}
```

### 6. SRTP Key Derivation (Çağrılar İçin)

WebRTC çağrılarının da E2E şifreli olması için SRTP key türetme:

```kotlin
class CallCryptoManager @Inject constructor(
    private val protocolStore: SecureChatProtocolStore
) {
    // WebRTC SRTP için paylaşılan anahtar türet
    suspend fun deriveCallEncryptionKey(
        peerId: String
    ): CallEncryptionKeys {
        val address = SignalProtocolAddress(peerId, 1)
        val session = protocolStore.loadSession(address)
        
        // Session'dan HKDF ile SRTP master key türet
        val sharedSecret = session.sessionState.rootKey.keyBytes
        val hkdf = HKDF.createFor(3) // Signal Protocol v3
        val derivedKey = hkdf.deriveSecrets(
            sharedSecret,
            "SecureChat-SRTP-Key".toByteArray(),
            64 // 32 byte key + 32 byte salt
        )
        
        return CallEncryptionKeys(
            masterKey = derivedKey.copyOfRange(0, 32),
            masterSalt = derivedKey.copyOfRange(32, 64)
        )
    }
}
```

## Güvenlik Kuralları (ZORUNLU)

1. **Private key ASLA loga yazılmaz** — debug modda bile
2. **Key material bellekten hemen silinir** — `Arrays.fill(keyBytes, 0)` pattern'ı
3. **Timing attack koruması** — constant-time comparison kullan
4. **Plaintext ASLA disk'e yazılmaz** — yalnızca şifreli versiyon
5. **Key rotation otomatik** — signed prekey her 7 günde, one-time prekey tükenince batch üretilir
6. **Identity key değişikliği kullanıcıya bildirilir** — "safety number changed" uyarısı
7. **Android Keystore zorunlu** — software-backed key kabul edilmez (TEE/StrongBox tercih)

## Bağımlılıklar
- `storage-agent` → Key'lerin persist edilmesi için Room DAO'ları
- `network-agent` → PreKey bundle sunucuya gönderilmesi

## Test Gereksinimleri
- Unit test: Encrypt → Decrypt round-trip
- Unit test: Session oluşturma ve mesaj alışverişi
- Unit test: Out-of-order message handling
- Unit test: Key rotation sonrası session sürekliliği
- Integration test: İki sanal cihaz arasında tam mesaj döngüsü
