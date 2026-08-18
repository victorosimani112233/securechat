plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
}

application {
    mainClass.set("com.securechat.signaling.ApplicationKt")
}

// Server JDK 17 (production Docker image); lokal JDK farkli olabilir.
// Bu hedef olmadan local JDK 21 ile derlenmis sinif dosyalari sunucuda
// UnsupportedClassVersionError firlatir.
java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions.jvmTarget = "17"
}

// Fat JAR olustur — tum dependency'leri tek JAR'a paketle
tasks.register<Jar>("fatJar") {
    archiveClassifier.set("all")
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    manifest {
        attributes["Main-Class"] = "com.securechat.signaling.ApplicationKt"
    }
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    with(tasks.jar.get())
    // JAR imza dosyalarini exclude et — ClassNotFoundException onlemi
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
}

dependencies {
    implementation(libs.ktor.server.core)
    implementation(libs.ktor.server.netty)
    implementation(libs.ktor.server.websockets)
    implementation(libs.ktor.server.content.negotiation)
    // implementation(libs.ktor.server.call.logging)
    implementation(libs.ktor.serialization)
    implementation(libs.coroutines.core)
    implementation(libs.logback)
    implementation(libs.serialization.json)

    // Firebase Admin SDK — sunucu tarafindan FCM push gondermek icin
    implementation("com.google.firebase:firebase-admin:9.2.0")

    // PostgreSQL + HikariCP connection pool
    implementation("org.postgresql:postgresql:42.7.3")
    implementation("com.zaxxer:HikariCP:5.1.0")

    // Redis
    implementation("redis.clients:jedis:5.1.2")

    // JWT auth — auth0/java-jwt
    implementation("com.auth0:java-jwt:4.4.0")

    // SMTP email gonderimi (OTP)
    implementation("com.sun.mail:jakarta.mail:2.0.1")

    // Flyway DB migration (9.x — daha forgiving filename validation)
    implementation("org.flywaydb:flyway-core:9.22.3")

    // Prometheus metrics — 1.12 paketleri io.micrometer.prometheus altinda
    implementation("io.micrometer:micrometer-registry-prometheus:1.12.4")
    implementation("io.micrometer:micrometer-core:1.12.4")

    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.junit.jupiter:junit-jupiter-engine:5.10.2")
    testImplementation(libs.testcontainers.postgres)
    testImplementation(libs.testcontainers.junit)
}

// Artefaktin hangi commit'ten ciktigini image icine gomer. Deger build
// ortamindan gelir; yoksa "unknown" kalir ve production startup'i durur.
val generateBuildInfo = tasks.register("generateBuildInfo") {
    val outputDir = layout.buildDirectory.dir("generated/buildinfo")
    val commit = providers.gradleProperty("sourceCommit").orElse(
        providers.environmentVariable("SOURCE_COMMIT"),
    ).orElse("")
    val builtAt = providers.gradleProperty("sourceBuiltAt").orElse(
        providers.environmentVariable("SOURCE_BUILT_AT"),
    ).orElse("")
    val migrationTarget = providers.provider {
        file("src/main/resources/db/migration")
            .listFiles { f -> f.name.startsWith("V") && f.name.endsWith(".sql") }
            ?.mapNotNull { Regex("^V(\\d+)__").find(it.name)?.groupValues?.get(1)?.toIntOrNull() }
            ?.maxOrNull()
            ?.let { "V$it" }
            ?: ""
    }
    inputs.property("commit", commit)
    inputs.property("builtAt", builtAt)
    inputs.property("migrationTarget", migrationTarget)
    outputs.dir(outputDir)
    doLast {
        val dir = outputDir.get().asFile
        dir.mkdirs()
        dir.resolve("build-info.properties").writeText(
            buildString {
                appendLine("commit=${commit.get()}")
                appendLine("builtAt=${builtAt.get()}")
                appendLine("migrationTarget=${migrationTarget.get()}")
            },
        )
    }
}

sourceSets.main {
    resources.srcDir(generateBuildInfo)
}

tasks.test {
    useJUnitPlatform()
    systemProperty(
        "serverMigrationDir",
        rootProject.file("signaling-server/src/main/resources/db/migration").absolutePath
    )
    // Test-only key material. Production degerleri yalniz read-only
    // NAME_FILE secret'larindan gelir; bunlar hicbir ortamda kullanilmaz.
    environment("JWT_SECRET", "test-only-signing-secret-not-for-any-deployment")
    environment("PRIVACY_INDEX_KEY", "PeN+mhUNrGTskTKEAc8g3/2luUhvhE6vy1l4257smsQ=")
    environment("OFFLINE_QUEUE_ENCRYPTION_KEY", "IIYFEByJTRH/+XqO6PZAFrSHWX5+TiM869Sj+Qx7OvY=")
    environment("FCM_TOKEN_ENCRYPTION_KEY", "/S+tBmY1nyurGJL5fluwJqUbzB+BPc4cWY/efLAPxuw=")
}
