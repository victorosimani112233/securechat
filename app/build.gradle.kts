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
        versionCode = 1
        versionName = "1.0.0"

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
            buildConfigField("String", "SIGNALING_URL", "\"ws://185.48.182.124:9090\"")
            buildConfigField("String", "API_BASE_URL", "\"http://185.48.182.124:9090\"")
            // CERT_PIN bos = pinning disabled (dev/HTTP). Production'da nginx cert'inin
            // SHA-256 SPKI pin'i set edilir (asagidaki prod flavor'a bak).
            buildConfigField("String", "CERT_PIN_HOST", "\"\"")
            buildConfigField("String", "CERT_PIN_SHA256", "\"\"")
        }
        create("prod") {
            dimension = "environment"
            buildConfigField("String", "SIGNALING_URL", "\"wss://signal.securechat.app\"")
            buildConfigField("String", "API_BASE_URL", "\"https://signal.securechat.app\"")
            // YENI SUNUCU TASIMA: cert pin asagiya yazilmali.
            // Pin almak icin: openssl s_client -connect signal.securechat.app:443 -servername signal.securechat.app \
            //   < /dev/null 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | \
            //   openssl dgst -sha256 -binary | openssl enc -base64
            // Format: "sha256/<base64-hash>"
            buildConfigField("String", "CERT_PIN_HOST", "\"signal.securechat.app\"")
            buildConfigField("String", "CERT_PIN_SHA256", "\"\"")  // TODO: yeni sunucu pin'i set et
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
            it.forkEvery = 4
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
