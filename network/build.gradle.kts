plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.securechat.network"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    @Suppress("UnstableApiUsage")
    testOptions {
        // android.util.Log gibi mocklenmemis Android API'leri icin
        // default deger donmesini sagla (exception firlatmak yerine)
        unitTests.isReturnDefaultValues = true
        unitTests.all {
            it.maxHeapSize = "4096m"
        }
    }
}

dependencies {
    implementation(project(":common"))
    implementation(project(":crypto"))
    implementation(project(":storage"))

    // WebRTC — api ile expose ediliyor, app modulu SurfaceViewRenderer kullanir
    api(libs.webrtc)

    // OkHttp — api olarak expose ediyoruz: CallManager (media modulu) shared OkHttpClient'i
    // dogrudan kullaniyor (JanusClient'a cert pinning ile gecirmek icin).
    api(libs.okhttp)
    implementation(libs.okhttp.logging)

    // Kotlinx Serialization
    implementation(libs.serialization.json)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    // Coroutines
    implementation(libs.coroutines.core)
    implementation(libs.coroutines.android)

    // Testing
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.truth)
    testImplementation(libs.turbine)
}
