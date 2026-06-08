plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.hilt) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}

// JaCoCo agregat raporu — her modulun :testDebugUnitTest sonrasi
// kendi raporunu uretir, root'tan ./gradlew jacocoFullReport ile
// hepsinin birlestirilmis raporu (gelecekte gerekirse).
//
// Modul basina coverage'i gormek icin:
//   ./gradlew :crypto:jacocoTestReport
//   open crypto/build/reports/jacoco/jacocoTestReport/html/index.html
//
// Pure-JVM modullerde (crypto, common, network, storage, media, contacts):
//   build.gradle.kts'e: id("jacoco") + tasks.register<JacocoReport>("jacocoTestReport")
// Android modul Hilt + KSP nedeniyle ayri konfig gerektirir (sonraki sprint).
subprojects {
    plugins.withId("org.jetbrains.kotlin.jvm") {
        apply(plugin = "jacoco")
        extensions.configure<org.gradle.testing.jacoco.plugins.JacocoPluginExtension> {
            toolVersion = "0.8.11"
        }
        // JVM modullerinde otomatik jacocoTestReport task'i kayit et;
        // ama modul build.gradle.kts kendi register ettiyse skip (signaling-server gibi).
        if (tasks.findByName("jacocoTestReport") == null) {
            tasks.register<JacocoReport>("jacocoTestReport") {
                dependsOn("test")
                reports {
                    xml.required.set(true)
                    html.required.set(true)
                }
                classDirectories.setFrom(fileTree("${layout.buildDirectory.get()}/classes/kotlin/main"))
                sourceDirectories.setFrom(files("src/main/kotlin", "src/main/java"))
                executionData.setFrom(fileTree(layout.buildDirectory).include("/jacoco/test.exec"))
            }
        }
    }
}
