import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertiesFile = rootProject.file("signing.properties")
val releaseSigningProperties = Properties().apply {
    if (signingPropertiesFile.exists()) {
        signingPropertiesFile.inputStream().use(::load)
    }
}

android {
    namespace = "com.securechat.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.securechat.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Matches the Kotlin application and is required by self-managed Telecom.
        minSdk = 26
        // Toolchain degeri yerine acik surum: Flutter yukseldiginde hedef
        // sessizce kaymasin ve davranis degisiklikleri fark edilmeden
        // gelmesin. Play yeni uygulamalar icin 35+ istiyor.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Flutter limits its own binaries, but plugin AARs also contain other
        // ABIs. Keep the non-split APK consistent with --target-platform.
        if (providers.gradleProperty("split-per-abi").orNull != "true") {
            providers.gradleProperty("target-platform").orNull?.let { targets ->
                val abiByTarget = mapOf(
                    "android-arm" to "armeabi-v7a",
                    "android-arm64" to "arm64-v8a",
                    "android-x64" to "x86_64",
                )
                ndk.abiFilters.clear()
                ndk.abiFilters.addAll(targets.split(",").map { target ->
                    requireNotNull(abiByTarget[target]) { "Unsupported Android target: $target" }
                })
            }
        }
    }

    packaging {
        jniLibs {
            // Dosya olarak dagitilan APK'de .so kutuphaneleri (~37 MB, WebRTC +
            // Flutter + SQLCipher) sikistirilir: APK ~46 MB'tan ~24 MB'a iner.
            // Play AAB'de sikistirilmaz: Play indirmeyi kendisi sikistirir ve
            // cihazda kutuphaneler ikinci kez acilip yer kaplamaz.
            useLegacyPackaging = gradle.startParameter.taskNames.none {
                it.contains("bundle", ignoreCase = true)
            }
        }
    }

    signingConfigs {
        if (signingPropertiesFile.exists()) {
            create("release") {
                storeFile = file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Device/integration QA must never uninstall or overwrite the
            // user's release-like app session on the same phone.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            // Release signing is supplied by the air-gapped build environment.
            if (signingPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core:1.18.0")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.sqlite:sqlite:2.5.0")
    // Exact SQLCipher generation used by the Kotlin Room v22 database. It is
    // opened read-only by the one-time upgrade importer; Flutter runtime data
    // remains in the encrypted snapshot database.
    implementation("net.zetetic:sqlcipher-android:4.5.6")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
