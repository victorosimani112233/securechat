package com.securechat.crypto

/**
 * Sensitive byte array'leri kullanim sonrasi otomatik sifirlayan extension.
 *
 * Manuel `try/finally { fill(0) }` yerine kullanin — exception'larda da
 * temizlik garanti edilir. Plaintext mesajlar, password/passphrase'ler,
 * sifreleme anahtarlari icin standart pattern.
 *
 * Ornek:
 *   val plaintext = decrypt(envelope)
 *   plaintext.useAndZeroize { bytes ->
 *       processMessage(String(bytes, Charsets.UTF_8))
 *   }
 *   // plaintext artik {0, 0, 0, ...}
 *
 * NOT: Block icinde plaintext'in REFERANSINI kopyalamayin (immutable kopya
 * olusturup `bytes`'i terk ederseniz bu extension sadece original'i sifirlar,
 * kopya RAM'de kalir).
 */
inline fun <R> ByteArray.useAndZeroize(block: (ByteArray) -> R): R {
    return try {
        block(this)
    } finally {
        fill(0)
    }
}

/**
 * String -> ByteArray donusumu icin guvenli helper.
 * Geri donen ByteArray useAndZeroize ile sarilmali.
 */
fun String.toSensitiveBytes(charset: java.nio.charset.Charset = Charsets.UTF_8): ByteArray =
    toByteArray(charset)
