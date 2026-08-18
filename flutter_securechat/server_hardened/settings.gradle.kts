pluginManagement {
    repositories {
        maven { url = uri("${rootDir}/../../local-repo") }
        maven { url = uri("${rootDir}/local-repo") }
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
        maven { url = uri("${rootDir}/../../local-repo") }
        maven { url = uri("${rootDir}/local-repo") }
    }
}

rootProject.name = "SecureChatHardenedServer"
include(":signaling-server")
include(":bot-api")
