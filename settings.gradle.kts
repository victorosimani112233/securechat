pluginManagement {
    repositories {
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
include(":signaling-server")
include(":bot-api")
include(":bot-admin-cli")
