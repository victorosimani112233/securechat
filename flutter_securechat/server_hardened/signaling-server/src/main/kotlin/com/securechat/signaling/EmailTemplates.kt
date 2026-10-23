package com.securechat.signaling

/**
 * Tek kullanimlik kod e-postalarinin ortak Turkce bicimi (QA 2026-10-13 T9).
 *
 * Kayit dogrulama e-postasi Turkce ve bicimliydi; hesap kurtarma ve kurtarma
 * e-postasi dogrulama e-postalari Ingilizce tek satirdi. Uc amac da ayni
 * sablonu kullanir, yalniz baslik ve aciklama degisir.
 */
internal object EmailTemplates {

    enum class Purpose(val subject: String, val heading: String, val intro: String) {
        REGISTRATION(
            subject = "SecureChat — Doğrulama Kodu",
            heading = "SecureChat Doğrulama",
            intro = "Hesabınızı doğrulamak için aşağıdaki kodu kullanın:",
        ),
        ACCOUNT_RECOVERY(
            subject = "SecureChat — Hesap Kurtarma Kodu",
            heading = "SecureChat Hesap Kurtarma",
            intro = "Hesabınıza yeniden giriş yapmak için aşağıdaki kodu kullanın:",
        ),
        RECOVERY_ENROLLMENT(
            subject = "SecureChat — Kurtarma E-postası Doğrulama",
            heading = "SecureChat Kurtarma E-postası",
            intro = "Bu adresi hesabınızın kurtarma e-postası yapmak için aşağıdaki kodu kullanın:",
        ),
    }

    data class Mail(val subject: String, val html: String, val text: String)

    /** Hesap yeni bir cihazda kurtarildiginda giden kodsuz bildirim. */
    fun recoveredOnNewDevice(): Mail {
        val heading = "SecureChat Hesap Kurtarıldı"
        val body = "Hesabınız bu e-posta adresiyle yeni bir cihazda kurtarıldı. " +
            "Önceki cihazınızdaki oturum kapatıldı."
        val warning = "Bunu siz yapmadıysanız hesabınızı hemen yeniden kurtarın ve " +
            "kurtarma e-postanızın parolasını değiştirin."
        val html = """
            <html><body style="font-family:Arial,sans-serif">
              <h2 style="color:#1a73e8">$heading</h2>
              <p>$body</p>
              <p style="color:#b3261e">$warning</p>
            </body></html>
        """.trimIndent()
        return Mail("SecureChat — Hesabınız yeni bir cihazda kurtarıldı", html, "$heading\n\n$body\n\n$warning")
    }

    fun code(purpose: Purpose, code: String): Mail {
        // Kod sunucuda uretilir (6 rakam); yine de HTML'e yalniz rakam girer.
        val safe = code.filter(Char::isDigit)
        val html = """
            <html><body style="font-family:Arial,sans-serif">
              <h2 style="color:#1a73e8">${purpose.heading}</h2>
              <p>${purpose.intro}</p>
              <h1 style="font-size:32px;letter-spacing:4px;color:#1a73e8">$safe</h1>
              <p style="color:#666;font-size:13px">Bu kod 10 dakika içinde sona erer. Bu isteği siz yapmadıysanız bu e-postayı görmezden gelin.</p>
            </body></html>
        """.trimIndent()
        val text = "${purpose.heading}\n\n${purpose.intro} $safe\n\n" +
            "Bu kod 10 dakika içinde sona erer. Bu isteği siz yapmadıysanız bu e-postayı görmezden gelin."
        return Mail(purpose.subject, html, text)
    }
}
