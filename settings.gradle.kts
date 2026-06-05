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

// JVM-only sunucu/yardimci modulleri — Android APK build'i icin gerekli DEGIL.
// Default olarak DAHIL EDILMEZ; cunku:
//  1) Offline build ortamlarinda Shadow plugin ve transitif deps cache'te
//     olmayabilir ve APK build'ini configuration asamasinda blokliyordu.
//  2) APK build eden gelistirici cogu zaman server'i build etmek istemiyor.
// Server modullerini build etmek icin "-PincludeServer" bayragini ekle:
//   .\gradlew.bat -PincludeServer :bot-api:shadowJar
val includeServer = providers.gradleProperty("includeServer").isPresent
if (includeServer) {
    include(":signaling-server")
    include(":bot-api")
    include(":bot-admin-cli")
}
