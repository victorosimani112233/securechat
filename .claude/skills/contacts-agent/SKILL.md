---
name: contacts-agent
description: >
  Android rehber erişimi ve kullanıcı keşfi agentı. ContactsContract API ile telefon rehberine
  erişim, runtime permission yönetimi, telefon numarası normalizasyonu (E.164 formatı),
  hash tabanlı kullanıcı eşleştirme (sunucuya plaintext numara gönderilmez), rehber
  değişiklik dinleme (ContentObserver), ve kayıtlı kullanıcı listesi yönetimi yapar.
  Gizlilik-first yaklaşımla çalışır — sunucuya yalnızca hash gönderilir.
---

# Contacts Agent — Rehber Erişimi ve Kullanıcı Keşfi

## Rol
Sen SecureChat'in rehber agentısın. Görevin kullanıcının telefon rehberine güvenli şekilde
erişmek ve SecureChat kullanan kişileri bulmak. Gizlilik öncelikli çalışırsın.

## Sorumluluklar

### 1. Runtime Permission Yönetimi

```kotlin
class ContactPermissionManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    // Activity'den çağrılır
    fun createPermissionLauncher(
        activity: ComponentActivity,
        onGranted: () -> Unit,
        onDenied: () -> Unit
    ): ActivityResultLauncher<String> {
        return activity.registerForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { isGranted ->
            if (isGranted) onGranted() else onDenied()
        }
    }
}
```

### 2. Rehber Okuma

```kotlin
@Singleton
class ContactsProvider @Inject constructor(
    @ApplicationContext private val context: Context,
    private val phoneNumberUtil: PhoneNumberUtil
) {
    suspend fun getAllContacts(): List<DeviceContact> = withContext(Dispatchers.IO) {
        val contacts = mutableListOf<DeviceContact>()
        
        val cursor = context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.PHOTO_THUMBNAIL_URI
            ),
            null, null,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
        )
        
        cursor?.use {
            val idIndex = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            val nameIndex = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberIndex = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val photoIndex = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.PHOTO_THUMBNAIL_URI)
            
            while (it.moveToNext()) {
                val rawNumber = it.getString(numberIndex) ?: continue
                val normalizedNumber = normalizePhoneNumber(rawNumber)
                
                if (normalizedNumber != null) {
                    contacts.add(
                        DeviceContact(
                            id = it.getString(idIndex),
                            displayName = it.getString(nameIndex) ?: "Bilinmeyen",
                            phoneNumber = normalizedNumber,
                            avatarUri = it.getString(photoIndex)
                        )
                    )
                }
            }
        }
        
        // Aynı numaraları deduplicate et
        contacts.distinctBy { it.phoneNumber }
    }
    
    // E.164 formatına normalize et
    private fun normalizePhoneNumber(rawNumber: String): String? {
        return try {
            val parsed = phoneNumberUtil.parse(rawNumber, getDefaultCountryCode())
            if (phoneNumberUtil.isValidNumber(parsed)) {
                phoneNumberUtil.format(parsed, PhoneNumberUtil.PhoneNumberFormat.E164)
            } else null
        } catch (e: NumberParseException) {
            null
        }
    }
    
    private fun getDefaultCountryCode(): String {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        return tm.simCountryIso?.uppercase() ?: "TR"
    }
}

data class DeviceContact(
    val id: String,
    val displayName: String,
    val phoneNumber: String, // E.164 format
    val avatarUri: String?
)
```

### 3. Privacy-First Kullanıcı Keşfi

Sunucuya plaintext telefon numarası GÖNDERİLMEZ. Hash tabanlı eşleştirme:

```kotlin
@Singleton
class UserDiscoveryService @Inject constructor(
    private val contactsProvider: ContactsProvider,
    private val contactDao: ContactDao,
    private val apiService: DiscoveryApiService
) {
    // SHA-256 hash ile sunucuya sorgula
    suspend fun discoverRegisteredUsers(): List<RegisteredContact> {
        val deviceContacts = contactsProvider.getAllContacts()
        
        // Telefon numaralarını hash'le
        val hashMap = deviceContacts.associate { contact ->
            hashPhoneNumber(contact.phoneNumber) to contact
        }
        
        // Hash'leri sunucuya gönder
        val registeredHashes = apiService.checkRegisteredUsers(
            CheckUsersRequest(hashes = hashMap.keys.toList())
        )
        
        // Eşleşenleri bul
        val registered = registeredHashes.users.mapNotNull { serverUser ->
            val deviceContact = hashMap[serverUser.phoneHash] ?: return@mapNotNull null
            RegisteredContact(
                userId = serverUser.userId,
                displayName = deviceContact.displayName,
                phoneNumber = deviceContact.phoneNumber,
                phoneHash = serverUser.phoneHash,
                avatarUri = deviceContact.avatarUri
            )
        }
        
        // Lokale kaydet
        registered.forEach { contact ->
            contactDao.insert(
                ContactEntity(
                    id = contact.userId,
                    phoneNumber = contact.phoneNumber,
                    phoneHash = contact.phoneHash,
                    displayName = contact.displayName,
                    isRegistered = true,
                    avatarUri = contact.avatarUri
                )
            )
        }
        
        return registered
    }
    
    private fun hashPhoneNumber(phoneNumber: String): String {
        // Truncated SHA-256 — sunucu tam numarayı öğrenemesin
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(phoneNumber.toByteArray(Charsets.UTF_8))
        return hash.toHexString()
    }
}

data class RegisteredContact(
    val userId: String,
    val displayName: String,
    val phoneNumber: String,
    val phoneHash: String,
    val avatarUri: String?
)
```

### 4. Rehber Değişiklik Dinleme

```kotlin
class ContactsObserver @Inject constructor(
    @ApplicationContext private val context: Context,
    private val userDiscoveryService: UserDiscoveryService
) {
    private var contentObserver: ContentObserver? = null
    
    fun startObserving() {
        contentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                // Rehber değişti, yeniden senkronize et
                CoroutineScope(Dispatchers.IO).launch {
                    userDiscoveryService.discoverRegisteredUsers()
                }
            }
        }
        
        context.contentResolver.registerContentObserver(
            ContactsContract.Contacts.CONTENT_URI,
            true,
            contentObserver!!
        )
    }
    
    fun stopObserving() {
        contentObserver?.let {
            context.contentResolver.unregisterContentObserver(it)
        }
    }
}
```

### 5. Discovery API

```kotlin
interface DiscoveryApiService {
    @POST("api/v1/users/check")
    suspend fun checkRegisteredUsers(
        @Body request: CheckUsersRequest
    ): CheckUsersResponse
}

@Serializable
data class CheckUsersRequest(
    val hashes: List<String>
)

@Serializable
data class CheckUsersResponse(
    val users: List<ServerUser>
)

@Serializable
data class ServerUser(
    val userId: String,
    val phoneHash: String
)
```

### 6. Arama ve Filtreleme

```kotlin
class ContactSearchManager @Inject constructor(
    private val contactDao: ContactDao
) {
    fun searchContacts(query: String): Flow<List<RegisteredContact>> {
        return contactDao.search("%$query%").map { entities ->
            entities.filter { it.isRegistered }.map { it.toRegisteredContact() }
        }
    }
    
    fun getRegisteredContacts(): Flow<List<RegisteredContact>> {
        return contactDao.getRegistered().map { entities ->
            entities.map { it.toRegisteredContact() }
        }
    }
}
```

## Gizlilik Kuralları (ZORUNLU)
1. **Plaintext telefon numarası sunucuya GÖNDERİLMEZ** — yalnızca hash
2. **Rehber verisi cihazdan çıkmaz** — eşleştirme client-side yapılır
3. **İzin yoksa graceful degrade** — rehber olmadan da çalışmalı (manuel numara girişi)
4. **ContentObserver temizliği** — lifecycle-aware olmalı, leak olmamalı
5. **Batch sorgulama** — büyük rehberlerde pagination kullan

## Bağımlılıklar
- `storage-agent` → ContactEntity persist
- `network-agent` → Discovery API çağrıları
- `ui-agent` → Kişi listesi ekranı

## Test Gereksinimleri
- Unit test: Telefon numarası normalizasyonu (çeşitli formatlar)
- Unit test: Hash eşleştirme doğruluğu
- Unit test: Arama/filtreleme
- Unit test: Permission state yönetimi
- Integration test: ContentResolver mock ile rehber okuma
