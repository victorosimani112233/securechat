pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // Plugin build scripts may declare extra repositories (flutter_webrtc
    // currently adds JitPack). They are deliberately ignored: application
    // dependencies resolve only from this reviewed allow-list.
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        maven {
            name = "securechatVendored"
            url = uri("vendor/maven")
            content { includeGroup("com.github.davidliu") }
        }
        maven {
            name = "flutterEngine"
            url = uri("https://storage.googleapis.com/download.flutter.io")
            content { includeGroup("io.flutter") }
        }
        google()
        mavenCentral()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
