package com.securechat.contacts

import android.content.Context
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import com.google.i18n.phonenumbers.NumberParseException
import com.google.i18n.phonenumbers.PhoneNumberUtil
import com.securechat.contacts.model.DeviceContact
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Cihaz rehberinden kisileri okur ve telefon numaralarini E.164 formatina normalize eder.
 * Ayni numaraya sahip tekrar eden kayitlar otomatik olarak filtrelenir.
 */
@Singleton
class ContactsProvider @Inject constructor(
    @ApplicationContext private val context: Context,
    private val phoneNumberUtil: PhoneNumberUtil
) {
    /**
     * Tum rehber kisilerini okur, numaralari normalize eder ve tekrarlari temizler.
     */
    suspend fun getAllContacts(): List<DeviceContact> = withContext(Dispatchers.IO) {
        android.util.Log.d("ContactsProvider", "getAllContacts basladi")
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

        android.util.Log.d("ContactsProvider", "cursor null mu: ${cursor == null}, count: ${cursor?.count ?: -1}")
        cursor?.use {
            val idIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val photoIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.PHOTO_THUMBNAIL_URI)

            while (it.moveToNext()) {
                val rawNumber = it.getString(numberIdx) ?: continue
                // Oncelikle E.164 normalizasyon dene, basarisizsa ham numarayi temizle
                val phoneNumber = normalizePhoneNumber(rawNumber)
                    ?: rawNumber.replace(" ", "").replace("-", "").replace("(", "").replace(")", "")
                android.util.Log.d("ContactsProvider", "Kisi bulundu: ${it.getString(nameIdx)} - $phoneNumber")
                contacts.add(
                    DeviceContact(
                        id = it.getString(idIdx),
                        displayName = it.getString(nameIdx) ?: "Bilinmeyen",
                        phoneNumber = phoneNumber,
                        avatarUri = it.getString(photoIdx)
                    )
                )
            }
        }
        // Ayni numaraya sahip tekrar eden kayitlari filtrele
        contacts.distinctBy { it.phoneNumber }
    }

    /**
     * Ham telefon numarasini E.164 formatina normalize eder.
     * Gecersiz numaralar icin null doner.
     */
    fun normalizePhoneNumber(rawNumber: String): String? {
        return try {
            val parsed = phoneNumberUtil.parse(rawNumber, getDefaultCountryCode())
            if (phoneNumberUtil.isValidNumber(parsed)) {
                phoneNumberUtil.format(parsed, PhoneNumberUtil.PhoneNumberFormat.E164)
            } else null
        } catch (e: NumberParseException) {
            null
        }
    }

    /**
     * SIM kart bilgisinden varsayilan ulke kodunu alir.
     * SIM bilgisi alinamazsa Turkiye (TR) kullanilir.
     */
    fun getDefaultCountryCode(): String {
        return try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            tm.simCountryIso?.uppercase() ?: "TR"
        } catch (_: Exception) {
            "TR"
        }
    }
}
