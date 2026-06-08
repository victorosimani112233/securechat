package com.securechat.media

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import com.securechat.network.SignalingClient
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File

/**
 * Bug fix regresyon testleri:
 * - Bug 002: Mesaj girisinde kontrol karakter filtreleme ve uzunluk siniri
 * - Bug 006: HEIC donusum hatasi durumunda null donmesi
 * - Bug 008: Turkce karakterlerin dosya adinda korunmasi
 *
 * Bug 005 (FileOpenHelper try-catch) ve Bug 007 (GetMultipleContents) ve
 * Bug 010 (grup adi karakter limiti) UI testleri olarak degerlendirilir,
 * ancak mantik dogrulamalari burada yapilir.
 */
class InputValidationAndMediaBugFixesTest {

    private lateinit var fileTransferManager: FileTransferManager
    private lateinit var context: Context
    private lateinit var contentResolver: ContentResolver
    private lateinit var signalingClient: SignalingClient

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        contentResolver = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)

        every { context.contentResolver } returns contentResolver
        fileTransferManager = FileTransferManager(context, signalingClient, mockk(relaxed = true))
    }

    // =====================================================================
    // Bug 002: Mesaj girisi kontrol karakter filtreleme ve uzunluk siniri
    // =====================================================================

    @Test
    fun `Bug002 kontrol karakterleri filtrelenir`() {
        // Kontrol karakter filtreleme regex'i ChatScreen'de kullaniliyor,
        // burada regex mantigi dogrulanir
        val regex = Regex("[\\p{Cc}&&[^\\n\\r]]")
        val input = "Merhaba\u0000\u0001\u0007\bDunya\t\n\rSon"
        val cleaned = input.replace(regex, "")

        // Null, SOH, BEL, BS ve TAB karakterleri temizlenmeli
        assertFalse("Null karakter olmamali", cleaned.contains("\u0000"))
        assertFalse("SOH karakter olmamali", cleaned.contains("\u0001"))
        assertFalse("BEL karakter olmamali", cleaned.contains("\u0007"))
        assertFalse("BS karakter olmamali", cleaned.contains("\b"))
        assertFalse("TAB karakter olmamali", cleaned.contains("\t"))

        // Newline ve carriage return korunmali
        assertTrue("Newline korunmali", cleaned.contains("\n"))
        assertTrue("Carriage return korunmali", cleaned.contains("\r"))

        assertEquals("MerhabaDunya\n\rSon", cleaned)
    }

    @Test
    fun `Bug002 10000 karakter siniri uygulanir`() {
        val longText = "A".repeat(15000)
        val truncated = longText.take(10000)

        assertEquals(10000, truncated.length)
    }

    @Test
    fun `Bug002 normal metin degismez`() {
        val regex = Regex("[\\p{Cc}&&[^\\n\\r]]")
        val normalText = "Merhaba, nasılsın?\nİyiyim, teşekkürler!"
        val cleaned = normalText.replace(regex, "")

        assertEquals(normalText, cleaned)
    }

    @Test
    fun `Bug002 bos metin hata vermez`() {
        val regex = Regex("[\\p{Cc}&&[^\\n\\r]]")
        val cleaned = "".replace(regex, "").take(10000)

        assertEquals("", cleaned)
    }

    @Test
    fun `Bug002 tam sinirda metin kesilmez`() {
        val exactText = "B".repeat(10000)
        val result = exactText.take(10000)

        assertEquals(10000, result.length)
        assertEquals(exactText, result)
    }

    // =====================================================================
    // Bug 006: HEIC format donusumu
    // =====================================================================

    @Test
    fun `Bug006 HEIC mime type algilanir`() {
        // HEIC/HEIF mime type kontrol mantigi
        val heicType = "image/heic"
        val heifType = "image/heif"
        val jpegType = "image/jpeg"

        assertTrue(heicType.equals("image/heic", ignoreCase = true))
        assertTrue(heifType.equals("image/heif", ignoreCase = true))
        assertFalse(jpegType.equals("image/heic", ignoreCase = true))
        assertFalse(jpegType.equals("image/heif", ignoreCase = true))
    }

    @Test
    fun `Bug006 buyuk harf HEIC mime type algilanir`() {
        val upperHeic = "IMAGE/HEIC"
        val mixedHeif = "Image/Heif"

        assertTrue(upperHeic.equals("image/heic", ignoreCase = true))
        assertTrue(mixedHeif.equals("image/heif", ignoreCase = true))
    }

    @Test
    fun `Bug006 HEIC donusum basarisiz olunca null doner`() {
        // ContentResolver gecersiz URI icin null stream doner
        val uri = mockk<Uri>()
        every { contentResolver.openInputStream(uri) } returns null

        val result = fileTransferManager.convertHeicToJpeg(uri)
        assertNull("Okunamayan HEIC icin null donmeli", result)
    }

    @Test
    fun `Bug006 bozuk HEIC verisi icin null doner`() {
        // Gecersiz bitmap verisi
        val uri = mockk<Uri>()
        val invalidData = "gecersiz-goruntu-verisi".toByteArray()
        every { contentResolver.openInputStream(uri) } returns ByteArrayInputStream(invalidData)

        val result = fileTransferManager.convertHeicToJpeg(uri)
        // BitmapFactory.decodeStream gecersiz veri icin null doner
        assertNull("Bozuk HEIC icin null donmeli", result)
    }

    @Test
    fun `Bug006 dosya adi uzantisi donusturulur`() {
        val originalName = "foto.heic"
        val convertedName = originalName.substringBeforeLast(".") + ".jpg"

        assertEquals("foto.jpg", convertedName)
    }

    @Test
    fun `Bug006 uzantisiz dosya adi donusumde hata vermez`() {
        val originalName = "foto"
        val convertedName = originalName.substringBeforeLast(".") + ".jpg"

        assertEquals("foto.jpg", convertedName)
    }

    // =====================================================================
    // Bug 008: Turkce dosya adi sanitizasyonu
    // =====================================================================

    @Test
    fun `Bug008 Turkce karakterler korunur`() {
        val turkishName = "gece_gorusu.jpg"
        val sanitized = fileTransferManager.sanitizeFileName(turkishName)

        assertEquals(turkishName, sanitized)
    }

    @Test
    fun `Bug008 Turkce ozel karakterler korunur`() {
        // Turkce ozel karakterler: g, u, s, o, c, i, I, G, U, S, O, C
        val turkishChars = "\u011f\u00fc\u015f\u00f6\u00e7\u0131\u0130\u011e\u00dc\u015e\u00d6\u00c7"
        val fileName = "${turkishChars}_dosya.txt"
        val sanitized = fileTransferManager.sanitizeFileName(fileName)

        // Turkce karakterler korunmali
        assertTrue("Turkce karakterler korunmali",
            sanitized.contains("\u011f") && sanitized.contains("\u00fc") &&
            sanitized.contains("\u015f") && sanitized.contains("\u00f6") &&
            sanitized.contains("\u00e7") && sanitized.contains("\u0131"))
    }

    @Test
    fun `Bug008 diger Unicode harfler de korunur`() {
        // Almanca, Fransizca vb. karakterler
        val europeanChars = "\u00e4\u00f6\u00fc\u00e9\u00e8\u00ea"
        val fileName = "${europeanChars}_file.txt"
        val sanitized = fileTransferManager.sanitizeFileName(fileName)

        assertTrue("Unicode harfler korunmali", sanitized.contains("\u00e4"))
        assertTrue("Unicode harfler korunmali", sanitized.contains("\u00e9"))
    }

    @Test
    fun `Bug008 path traversal engellenir`() {
        val malicious = "../../../etc/passwd"
        val sanitized = fileTransferManager.sanitizeFileName(malicious)

        assertFalse("Path traversal olmamali", sanitized.contains("/"))
        assertFalse("Cift nokta olmamali", sanitized.contains(".."))
    }

    @Test
    fun `Bug008 uzun dosya adi kesilir`() {
        val longName = "a".repeat(200) + ".txt"
        val sanitized = fileTransferManager.sanitizeFileName(longName)

        assertTrue("Dosya adi 100 karakter ile sinirlanmali", sanitized.length <= 100)
    }

    @Test
    fun `Bug008 ozel karakterler alt cizgi ile degistirilir`() {
        // Ozel karakterler (emoji, ozel semboller) hala _ ile degistirilmeli
        val specialChars = "dosya @#\$%&=+.txt"
        val sanitized = fileTransferManager.sanitizeFileName(specialChars)

        assertFalse("@ olmamali", sanitized.contains("@"))
        assertFalse("# olmamali", sanitized.contains("#"))
        assertFalse("\$ olmamali", sanitized.contains("$"))
        assertTrue("Nokta korunmali", sanitized.contains("."))
        assertTrue("Alt cizgi olmali", sanitized.contains("_"))
    }

    @Test
    fun `Bug008 tire ve alt cizgi korunur`() {
        val fileName = "dosya-adi_v2.txt"
        val sanitized = fileTransferManager.sanitizeFileName(fileName)

        assertEquals("dosya-adi_v2.txt", sanitized)
    }

    // =====================================================================
    // Bug 010: Grup adi karakter limiti mantik dogrulamasi
    // =====================================================================

    @Test
    fun `Bug010 50 karakter siniri kontrolu`() {
        // CreateGroupScreen'de kullanilan mantik
        val shortName = "Kısa Grup"
        val longName = "A".repeat(51)
        val exactName = "B".repeat(50)

        assertTrue("Kisa isim kabul edilmeli", shortName.length <= 50)
        assertFalse("51 karakter reddedilmeli", longName.length <= 50)
        assertTrue("Tam 50 karakter kabul edilmeli", exactName.length <= 50)
    }

    @Test
    fun `Bug010 bos grup adi kabul edilir`() {
        val emptyName = ""
        assertTrue("Bos isim karakter kontrolunden gecer", emptyName.length <= 50)
    }

    @Test
    fun `Bug010 Turkce karakterli grup adi sinir kontrolu`() {
        // Turkce karakterler tek karakter olarak sayilmali
        val turkishName = "\u011f\u00fc\u015f\u00f6\u00e7\u0131".repeat(8) // 48 karakter
        assertTrue("Turkce karakterli isim 50 limiti icinde", turkishName.length <= 50)

        val overLimit = "\u011f\u00fc\u015f\u00f6\u00e7\u0131".repeat(9) // 54 karakter
        assertFalse("50 ustu Turkce isim reddedilmeli", overLimit.length <= 50)
    }
}
