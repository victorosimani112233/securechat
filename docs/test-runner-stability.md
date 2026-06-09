# Test runner kararliligi — JVM agent crash investigation

## Belirti
`./gradlew :app:testDevDebugUnitTest` calistirildiginda full test takimi
JVM crash ile yutuluyor:

```
Exception: java.lang.OutOfMemoryError thrown from the UncaughtExceptionHandler
*** java.lang.instrument ASSERTION FAILED ***: "!errorOutstanding" with message
can't create name string at ./src/java.instrument/share/native/libinstrument/JPLISAgent.c
> Process 'Gradle Test Executor X' finished with non-zero exit value 1
```

22 test sinifindan tipik olarak ilk 7'si gectikten sonra JVM cokuyor, kalan
testler hic calismiyor.

## Root cause hipotezi
mockk 1.13.9 (kullanilan version) `mockk-agent-jvm` artifact'i `java.lang.instrument`
JVM Tool Interface'i kullaniyor. Paralel test runner ile birden fazla test sinifi
ayni JVM agent'a load oldugunda JNI native code (`JPLISAgent.c`) thread-unsafe
sekilde isim string'leri yaratamiyor — assertion fail, JVM coker.

## Mevcut workaround (Sprint 4)
1. **`app/build.gradle.kts` testOptions**:
   - `forkEvery = 1` (her test class kendi JVM)
   - `maxParallelForks = 1` (paralel runner kapali)
   - `maxHeapSize = "4096m"`, `-XX:MaxMetaspaceSize=512m`

2. **`scripts/test-app-stable.sh`**: paket-bazli rerun.
   Crash etse bile diger paketler bagimsiz JVM'de calisir.

Yine de full `:app:testDevDebugUnitTest` non-deterministik fail eder. Storage,
crypto, media, network modul testleri etkilenmez (kucuk test takimi, JVM
oturum suresi crash threshold'unun altinda).

## Onerilen kalici cozumler (oncelik sirasiyla)

### A) mockk 1.13.13+ yukseltmesi
mockk 1.13.10+ JVM agent thread safety duzeltmeleri icerir. Online ortamda:

```diff
- mockk = "1.13.9"
+ mockk = "1.13.13"
```

Offline build (`/home/user497`'nin local-repo) icin once mockk 1.13.13
artifact'larini Maven Central'dan indir, local-repo'ya yerlestir.

### B) Inline mock konfigurasyonu
mockk JVM agent'i devre disi birakip ByteBuddy inline mock kullanan
implementasyona gec:

```kotlin
// Her test class'in init blok'unda:
mockkSettings {
    // Agent kullanma — inline mock subclasses olusturur
}
```

Bu agent thread-safety sorunundan kacinir, ancak `final` class mock'lari
icin Java agent yine de gerekli olabilir (Signal Protocol final class'lari
zaten data class veya open).

### C) Junit5 + dynamic test isolation
Junit4 yerine Junit5 kullanmak. `@TestInstance(PER_CLASS)` ile mockk
state'i temizler. Sprint 4'te junit4-style yontemini koruduk; junit5 gecisi
ayri bir refactor.

### D) Robolectric ile alternative
Compose ekran test'leri icin Robolectric (in-process Android) kullanilirsa
mockk JVM agent gerekmeyebilir. Ancak Robolectric kendi heavy infrastructure.

## CI/local kullanim
1. Modul-spesifik testler dogrudan calisir:
   ```
   ./gradlew :storage:testDebugUnitTest :crypto:testDebugUnitTest \
            :media:testDebugUnitTest :network:testDebugUnitTest
   ```
2. `:app:testDevDebugUnitTest` icin script kullan:
   ```
   ./scripts/test-app-stable.sh
   ```

Hicbir Sprint 1-6 kod commiti `:app:testDevDebugUnitTest` full takim
gecmesini engellemez — workaround mevcut, root cause sonraki Sprint'lere.
