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

    buildTypes {
        debug {
            isDebuggable = true
            applicationIdSuffix = ".debug"
        }
        release {
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
        }
        create("prod") {
            dimension = "environment"
            buildConfigField("String", "SIGNALING_URL", "\"wss://signal.securechat.app\"")
            buildConfigField("String", "API_BASE_URL", "\"https://signal.securechat.app\"")
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

    // Testing
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.truth)
    testImplementation(libs.turbine)
}
