# Signal Protocol
-keep class org.signal.** { *; }
-keep class org.whispersystems.** { *; }
-dontwarn org.signal.**
-dontwarn org.whispersystems.**

# WebRTC
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Room
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-dontwarn androidx.room.paging.**

# Hilt
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }

# SQLCipher
-keep class net.sqlcipher.** { *; }
-dontwarn net.sqlcipher.**

# OkHttp
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Retrofit
-keepattributes Signature
-keepattributes *Annotation*
-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

# Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# Kotlin Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

# SignalMessage hiyerarsisi — logcat'te tip isimleri obfuscated cikmasin
# (decrypt fail tanisinda "Sinyal geldi: i3" yerine gercek isim okunsun).
-keepnames class com.securechat.network.SignalMessage
-keepnames class com.securechat.network.SignalMessage$* { *; }

# Genel kurallar
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
