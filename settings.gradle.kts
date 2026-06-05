pluginManagement {
    repositories {
        // local-repo PLUGIN resolution icin ilk siraya alinir — offline ortamda
        // Shadow plugin gibi server-only plugin'ler bu klasorden cozulur.
        // (dependencyResolutionManagement bloku sadece compile dependencies icin
        // calisir; plugin'ler ayri bir resolution path'i kullanir.)
        maven {
            url = uri("${rootDir}/local-repo")
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("${rootProject.projectDir}/local-repo")
        }
    }
}

rootProject.name = "SecureChat"

include(":app")
include(":crypto")
include(":network")
include(":storage")
include(":media")
include(":contacts")
include(":common")

// JVM-only sunucu/yardimci modulleri — Android APK build'i icin gerekli degil.
// Offline ortamda (Shadow plugin gibi server-only bagimliliklar cache'te yoksa)
// "-PandroidOnly" property'si ile bu modulleri devre disi birakabilirsin:
//   .\gradlew.bat -PandroidOnly assembleDevDebug
// Default olarak (CI / online build) hepsi dahildir.
val androidOnly = (extra.has("androidOnly") || providers.gradleProperty("androidOnly").isPresent)
if (!androidOnly) {
    include(":signaling-server")
    include(":bot-api")
    include(":bot-admin-cli")
}
