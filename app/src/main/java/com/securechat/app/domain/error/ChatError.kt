package com.securechat.app.domain.error

/**
 * Sohbet ve mesajlasma akislarinda kullanici-facing hatalar.
 *
 * Generic "Hata olustu, tekrar deneyin" snackbar'lar yerine bu sealed class
 * kullanilir. Her tip somut bir user message + opsiyonel cause tasir.
 *
 * Kullanim pattern'i:
 *   sealed class Result<out T> {
 *     data class Ok<T>(val value: T) : Result<T>()
 *     data class Err(val error: ChatError) : Result<Nothing>()
 *   }
 *
 *   UseCase: suspend operator fun invoke(...): Result<Unit>
 *   ViewModel:
 *     when (val r = useCase(...)) {
 *       is Result.Ok -> ...
 *       is Result.Err -> _snackbar.emit(r.error.userMessage)
 *     }
 *
 * NOT: userMessage Turkce + kullaniciya kisa, eylem yonlendirici.
 * cause sadece log/Crashlytics'e gider, kullaniciya gosterilmez.
 */
sealed class ChatError(
    val userMessage: String,
    val cause: Throwable? = null
) {
    object NetworkUnavailable : ChatError("İnternet bağlantısı yok. Bağlantıyı kontrol edip tekrar deneyin.")
    object NotAuthorized : ChatError("Bu işlem için yetkiniz yok.")
    object NotGroupMember : ChatError("Bu grup üyesi değilsiniz.")
    object SessionExpired : ChatError("Oturumunuzun süresi dolmuş. Lütfen tekrar giriş yapın.")
    object SignalingDisconnected : ChatError("Sunucuya bağlanılamadı. Lütfen tekrar deneyin.")

    data class FileTooLarge(val maxMb: Int) : ChatError("Dosya çok büyük. Maksimum $maxMb MB.")
    data class FileReadError(val fileName: String) : ChatError("Dosya okunamadı: $fileName")
    data class RecipientNotFound(val name: String?) :
        ChatError("Alıcı bulunamadı${if (name != null) " ($name)" else ""}.")
    data class GroupNotFound(val groupId: String) : ChatError("Grup bulunamadı.")
    data class MessageTooLong(val maxChars: Int) : ChatError("Mesaj çok uzun. En fazla $maxChars karakter.")
    data class ServerError(val code: Int, val detail: String? = null) :
        ChatError("Sunucu hatası ($code)${if (detail != null) ": $detail" else ""}")

    data class Unknown(val ex: Throwable) :
        ChatError("Beklenmedik bir hata oluştu. Daha sonra tekrar deneyin.", ex)
}

/**
 * UseCase'ler icin sade Result tipi. Kotlin stdlib'in Result'i ile karistirilmamali —
 * burada Err tipi her zaman ChatError. Bu sayede ViewModel'de exhaustive `when`.
 */
sealed class ChatResult<out T> {
    data class Ok<T>(val value: T) : ChatResult<T>()
    data class Err(val error: ChatError) : ChatResult<Nothing>()

    fun isOk(): Boolean = this is Ok
    fun isErr(): Boolean = this is Err

    inline fun onOk(block: (T) -> Unit): ChatResult<T> {
        if (this is Ok) block(value)
        return this
    }
    inline fun onErr(block: (ChatError) -> Unit): ChatResult<T> {
        if (this is Err) block(error)
        return this
    }

    companion object {
        fun <T> ok(value: T): ChatResult<T> = Ok(value)
        fun err(error: ChatError): ChatResult<Nothing> = Err(error)

        /**
         * Yardimci: bir suspend block'unu Result'a sarmaliyor. Generic exception'lari
         * ChatError.Unknown'a cevirir; bilinen exception tiplerini ozel mapping ile
         * mappingFn ile zenginlestirebilirsiniz.
         */
        inline fun <T> catching(
            crossinline mapping: (Throwable) -> ChatError = { ChatError.Unknown(it) },
            crossinline block: () -> T
        ): ChatResult<T> = try {
            Ok(block())
        } catch (e: Throwable) {
            Err(mapping(e))
        }
    }
}
