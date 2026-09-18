plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}

subprojects {
    plugins.withId("org.jetbrains.kotlin.jvm") {
        apply(plugin = "jacoco")

        /**
         * Process giris noktalari olcumden cikarilir.
         *
         * `main()` gercek bir listener acar, shutdown hook kurar ve process'i
         * bloklar; test icinde calistirilamaz. Denominatorde birakmak kapsam
         * oranini anlamsiz kilardi. Geri kalan her sey olculur.
         */
        val coverageExclusions = listOf(
            "**/ApplicationKt.class",
            "**/ApplicationKt\$*.class",
        )

        tasks.withType<JacocoReport>().configureEach {
            reports {
                xml.required.set(true)
                html.required.set(true)
            }
            classDirectories.setFrom(
                files(classDirectories.files.map { fileTree(it) { exclude(coverageExclusions) } }),
            )
        }

        /**
         * Kapsam kapisi.
         *
         * Esikler bugunku olculen degerin hemen altindadir: amac bir hedefi
         * ilan etmek degil, ulasilan seviyenin sessizce gerilemesini
         * engellemektir. Yeni kod geldikce esikler yukseltilir.
         */
        tasks.register<JacocoCoverageVerification>("coverageGate") {
            dependsOn(tasks.named("test"))
            executionData.setFrom(fileTree(layout.buildDirectory).include("jacoco/test.exec"))
            sourceDirectories.setFrom(files("src/main/kotlin"))
            classDirectories.setFrom(
                files(
                    fileTree(layout.buildDirectory.dir("classes/kotlin/main")) {
                        exclude(coverageExclusions)
                    },
                ),
            )
            violationRules {
                rule {
                    limit {
                        counter = "LINE"
                        value = "COVEREDRATIO"
                        minimum = "0.70".toBigDecimal()
                    }
                    limit {
                        counter = "BRANCH"
                        value = "COVEREDRATIO"
                        minimum = "0.50".toBigDecimal()
                    }
                }
            }
        }

        tasks.named("check") { dependsOn(tasks.named("coverageGate")) }
    }
}
