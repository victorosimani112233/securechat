plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.securechat.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.securechat.app"
        minSdk = 26
        targetSdk = 34
        // Versiyon priority: gradle property > VERSION dosyasi > git komutu > 1
        //
        // Online makine: git komutu calistirir, commit count + short SHA otomatik.
        // Offline makine (git veya .git yok): VERSION dosyasini okur (online'da
        //   refresh-version.sh ile guncellenir, repo'ya commit edilir).
        // CI/manuel override: ./gradlew assembleDevRelease -PversionCode=49 -PversionName=1.0.49-abc
        //
        // Bu zincir sayesinde offline build "downgrade" olmaz; her zaman ya VERSION
        // dosyasindaki guncel deger ya da explicit override kullanilir.
        val gradlePropVc = providers.gradleProperty("versionCode").orNull?.toIntOrNull()
        val gradlePropVn = providers.gradleProperty("versionName").orNull

        val versionFile = rootDir.resolve("VERSION")
        val (fileVc, fileVn) = if (versionFile.exists()) {
            val lines = versionFile.readLines().map { it.trim() }.filter { it.isNotEmpty() }
            val vc = lines.firstOrNull { it.startsWith("versionCode=") }?.substringAfter("=")?.toIntOrNull()
            val vn = lines.firstOrNull { it.startsWith("versionName=") }?.substringAfter("=")
            vc to vn
        } else null to null

        val gitVc = runCatching {
            providers.exec {
                commandLine("git", "rev-list", "--count", "HEAD")
                workingDir = rootDir
            }.standardOutput.asText.get().trim().toInt()
        }.getOrNull()
        val gitSha = runCatching {
            providers.exec {
                commandLine("git", "rev-parse", "--short", "HEAD")
                workingDir = rootDir
            }.standardOutput.asText.get().trim()
        }.getOrNull()
        val gitVn = if (gitVc != null && gitSha != null) "1.0.$gitVc-$gitSha" else null

        versionCode = gradlePropVc ?: fileVc ?: gitVc ?: 1
        versionName = gradlePropVn ?: fileVn ?: gitVn ?: "1.0.0-dev"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        vectorDrawables {
            useSupportLibrary = true
        }
    }

    signingConfigs {
        create("release") {
            val localProps = rootProject.file("local.properties")
            // local.properties satirlarini oku (java.util.Properties yerine — uyumluluk)
            val propsMap = mutableMapOf<String, String>()
            if (localProps.exists()) {
                localProps.readLines().forEach { line ->
                    val trimmed = line.trim()
                    if (trimmed.isNotEmpty() && !trimmed.startsWith("#") && trimmed.contains("=")) {
                        val key = trimmed.substringBefore("=").trim()
                        val value = trimmed.substringAfter("=").trim()
                        propsMap[key] = value
                    }
                }
            }

            val ksPath = propsMap["RELEASE_STORE_FILE"] ?: ""
            if (ksPath.isNotBlank()) {
                try {
                    val ksFile = file(ksPath)
                    if (ksFile.exists()) {
                        storeFile = ksFile
                        storePassword = propsMap["RELEASE_STORE_PASSWORD"] ?: ""
                        keyAlias = propsMap["RELEASE_KEY_ALIAS"] ?: ""
                        keyPassword = propsMap["RELEASE_KEY_PASSWORD"] ?: ""
                    }
                } catch (_: Exception) {
                    // Keystore path gecersiz veya baska platformda — atla
                }
            }
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            applicationIdSuffix = ".debug"
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            buildConfigField("String", "SIGNALING_URL", "\"wss://94.73.180.226\"")
            buildConfigField("String", "API_BASE_URL", "\"https://94.73.180.226\"")
            buildConfigField("String", "STUN_URL", "\"stun:94.73.180.226:3478\"")
            // 94.73.180.226 self-signed cert pin'leri (2026-05-13 fresh install)
            buildConfigField("String", "CERT_PIN_HOST", "\"94.73.180.226\"")
            buildConfigField("String", "CERT_PIN_SHA256", "\"DLws9D1beDKBVkETgqo4rb0U9qXZx+AUVGKwaDXQiSA=\"")
            buildConfigField("String", "CERT_PIN_SHA256_BACKUP", "\"4oaRg+Six29KZ2tcFLyoYT+FKUZhYPzp1pI5BoK5RI4=\"")
        }
        create("prod") {
            dimension = "environment"
            buildConfigField("String", "SIGNALING_URL", "\"wss://94.73.180.226\"")
            buildConfigField("String", "API_BASE_URL", "\"https://94.73.180.226\"")
            buildConfigField("String", "STUN_URL", "\"stun:94.73.180.226:3478\"")
            // YENI SUNUCU TASIMA: cert pin asagiya yazilmali.
            // Pin almak icin: openssl s_client -connect signal.securechat.app:443 -servername signal.securechat.app \
            //   < /dev/null 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | \
            //   openssl dgst -sha256 -binary | openssl enc -base64
            // Format: "sha256/<base64-hash>"
            // ZORUNLU: backup pin de set edilmeli — cert rotation sirasinda eski APK'lar brick olmasin.
            buildConfigField("String", "CERT_PIN_HOST", "\"94.73.180.226\"")
            buildConfigField("String", "CERT_PIN_SHA256", "\"DLws9D1beDKBVkETgqo4rb0U9qXZx+AUVGKwaDXQiSA=\"")          // 94.73.180.226 primary
            buildConfigField("String", "CERT_PIN_SHA256_BACKUP", "\"4oaRg+Six29KZ2tcFLyoYT+FKUZhYPzp1pI5BoK5RI4=\"")   // rotation icin yedek
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = libs.versions.compose.compiler.get()
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    @Suppress("UnstableApiUsage")
    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.all {
            it.maxHeapSize = "4096m"
            it.jvmArgs("-XX:MaxMetaspaceSize=512m")
            // Her test class kendi JVM forkunda calissin. forkEvery=4 oldugunda
            // bir test class JVM agent assertion ile cokunce sonraki testler de
            // yutuluyordu; izole fork OOM/agent crashlerinin etki alanini sinirlar.
            it.forkEvery = 1
            // Paralel test runner kapali — mockk JVM agent paralelde "can't create
            // name string" assertion ile cokuyordu (JPLISAgent.c thread-unsafe).
            // Sirali calisma yavas ama deterministik.
            it.maxParallelForks = 1
        }
    }
}

dependencies {
    implementation(project(":common"))
    implementation(project(":crypto"))
    implementation(project(":network"))
    implementation(project(":storage"))
    implementation(project(":media"))
    implementation(project(":contacts"))

    // AndroidX Core
    implementation(libs.core.ktx)
    implementation(libs.appcompat)
    implementation(libs.activity.compose)
    implementation(files("libs/core-splashscreen-1.0.1.aar"))

    // Compose
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.icons.extended)
    implementation(libs.compose.navigation)
    debugImplementation(libs.compose.ui.tooling)

    // Lifecycle
    implementation(libs.lifecycle.runtime.ktx)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)

    // Coroutines
    implementation(libs.coroutines.core)
    implementation(libs.coroutines.android)

    // DataStore for preferences
    implementation("androidx.datastore:datastore-preferences:1.0.0")

    // Coil — gorsel yukleme
    implementation("io.coil-kt:coil-compose:2.6.0")

    // Firebase — FCM push notification
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-messaging")

    // Faz 15: WindowSizeClass dependency offline build'lerde sorun cikardi
    // (multi-variant module, AAR 197 byte stub + variant-specific JAR'lar)
    // ResponsiveLayout.kt ile birlikte geri alindi. Tablet/foldable layout
    // gercekten kullanilirken (Sprint 6) tekrar eklenir + local-repo'ya
    // tum variant'lar dahil edilir.
    // implementation("androidx.compose.material3:material3-window-size-class:1.2.1")

    // WorkManager — arka plan gorevleri (FCM drain, sureli mesaj temizligi)
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    implementation("androidx.hilt:hilt-work:1.1.0")
    ksp("androidx.hilt:hilt-compiler:1.1.0")

    // Lifecycle Process — app on plan/arka plan tespiti
    implementation("androidx.lifecycle:lifecycle-process:2.7.0")

    // Biyometrik dogrulama — sohbet kilidi
    implementation("androidx.biometric:biometric:1.1.0")

    // Testing
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.truth)
    testImplementation(libs.turbine)
}
