import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions
import java.security.KeyPairGenerator
import java.util.Base64

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

    // Official Signal certificate wire implementation for Sealed Sender.
    implementation(libs.libsignal.client)

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
    // Linearizability testi (JVM ici concurrent yapilar).
    testImplementation("org.jetbrains.kotlinx:lincheck:2.34")
    testImplementation("org.junit.jupiter:junit-jupiter-engine:5.10.2")
    testImplementation(libs.testcontainers.postgres)
    testImplementation(libs.testcontainers.junit)
    // Uctan uca HTTP/WebSocket senaryolari icin gercek Ktor motoru.
    testImplementation(libs.ktor.server.test.host)
    testImplementation(libs.ktor.client.websockets)
    testImplementation(libs.ktor.client.content.negotiation)
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

/**
 * Test-only directory OPRF anahtari.
 *
 * Uctan uca testler gercek `PrivateDirectory.oprf` global'ini kullanir; o da
 * anahtari `SecretSource` uzerinden okur. Anahtar build dizinine yazilir ve
 * owner-only yapilir, boylece production'daki dosya tabanli secret yolu da
 * ayni testlerde calisir. Repoda hicbir anahtar materyali durmaz.
 */
val testDirectoryOprfKey = layout.buildDirectory.file("test-secrets/directory-oprf.pkcs8.b64")

val generateTestDirectoryOprfKey by tasks.registering {
    outputs.file(testDirectoryOprfKey)
    doLast {
        val target = testDirectoryOprfKey.get().asFile
        target.parentFile.mkdirs()
        Files.setPosixFilePermissions(
            target.parentFile.toPath(),
            PosixFilePermissions.fromString("rwx------"),
        )
        if (!target.exists() || target.length() == 0L) {
            val generator = KeyPairGenerator.getInstance("RSA")
            generator.initialize(3072)
            target.writeText(
                Base64.getEncoder()
                    .encodeToString(generator.generateKeyPair().private.encoded),
            )
        }
        Files.setPosixFilePermissions(
            target.toPath(),
            PosixFilePermissions.fromString("rw-------"),
        )
    }
}

/**
 * Yerel guvenlik testi hedefi. `signalingModule`'u gercek PostgreSQL/Redis
 * ile gercek bir portta ayaga kaldirir; yalniz laboratuvar taramasi icin.
 * Uretim `main()`'inin sikilastirilmis kapisini (PKCS11/verify-full) atlar
 * cunku o kapi bir laboratuvarda saglanamaz.
 */
val runDummyServer by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Yerel signaling sunucusunu tarama icin ayaga kaldirir"
    dependsOn(generateTestDirectoryOprfKey, "testClasses")
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.securechat.signaling.DummyServerLauncher")
    systemProperty(
        "serverMigrationDir",
        rootProject.file("signaling-server/src/main/resources/db/migration").absolutePath,
    )
    environment("JWT_SECRET", "dummy-lab-signing-secret-not-for-any-deployment")
    environment("PRIVACY_INDEX_KEY", "PeN+mhUNrGTskTKEAc8g3/2luUhvhE6vy1l4257smsQ=")
    environment("OFFLINE_QUEUE_ENCRYPTION_KEY", "IIYFEByJTRH/+XqO6PZAFrSHWX5+TiM869Sj+Qx7OvY=")
    environment("FCM_TOKEN_ENCRYPTION_KEY", "/S+tBmY1nyurGJL5fluwJqUbzB+BPc4cWY/efLAPxuw=")
    // Testler gelistirme profilinde kosar: cevrimdisi imzalanmis bir Sealed
    // Sender sertifikasi uretmek yerine process icinde uretilmesine izin
    // verilir. Kriptografik kapilar bu profilde de aynen calisir.
    environment("SECURECHAT_PROFILE", "development")
    environment("SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY", "FaT7FztZJFeV2XBCOua92iOGPCIj9Y4UxBwjAuB8eeY=")
    environment("SEALED_SENDER_SERVER_PRIVATE_KEY", "QVMkIVDGd2LvS1mMhd4sFGurRHkQClX1DgaCIvpIncc=")
    environment("METRICS_BEARER_TOKEN", "dummy-lab-metrics-bearer-token-32-characters")
    environment("TURN_SECRET", "dummy-lab-turn-shared-secret-with-32-bytes")
    environment("TURN_HOST", "turn.lab.invalid")
    environment(
        "DIRECTORY_OPRF_PRIVATE_KEY_FILE",
        testDirectoryOprfKey.get().asFile.absolutePath,
    )
    environment("DUMMY_BIND_HOST", System.getenv("DUMMY_BIND_HOST") ?: "0.0.0.0")
    environment("DUMMY_BIND_PORT", System.getenv("DUMMY_BIND_PORT") ?: "8080")
}

tasks.test {
    useJUnitPlatform()
    environment("RECOVERY_INDEX_KEY", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=")
    environment("RECOVERY_ENCRYPTION_KEY", "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=")
    dependsOn(generateTestDirectoryOprfKey)
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
    // Testler gelistirme profilinde kosar: cevrimdisi imzalanmis bir Sealed
    // Sender sertifikasi uretmek yerine process icinde uretilmesine izin
    // verilir. Kriptografik kapilar bu profilde de aynen calisir.
    environment("SECURECHAT_PROFILE", "development")
    environment("SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY", "FaT7FztZJFeV2XBCOua92iOGPCIj9Y4UxBwjAuB8eeY=")
    environment("SEALED_SENDER_SERVER_PRIVATE_KEY", "QVMkIVDGd2LvS1mMhd4sFGurRHkQClX1DgaCIvpIncc=")
    environment("JANUS_API_SECRET", "test-only-janus-api-secret-material-32-bytes")
    environment("JANUS_ADMIN_SECRET", "test-only-janus-admin-secret-material-32-bytes")
    // Sahte Janus sunucusu bu adreste ayaga kalkar; SFU kontrol duzlemi
    // gercek bir WebSocket uzerinden surulur.
    environment("JANUS_WS_URL", "ws://127.0.0.1:18188/janus")
    environment("JANUS_PUBLIC_WS_URL", "wss://janus.test.invalid/janus")
    environment("METRICS_BEARER_TOKEN", "test-only-metrics-bearer-token-32-characters")
    environment("TURN_SECRET", "test-only-turn-shared-secret-with-32-bytes")
    environment("TURN_HOST", "turn.test.invalid")
    environment(
        "DIRECTORY_OPRF_PRIVATE_KEY_FILE",
        testDirectoryOprfKey.get().asFile.absolutePath,
    )
}

/**
 * Release'e giren ucuncu parti bilesenler.
 *
 * SBOM dogrulama manifestinden uretilir, fakat manifest test bagimliliklarini
 * da tasir. Calisan artefakti anlatan bir belge icin runtime classpath'in
 * kendisi listelenir; SCA kapisi boylece yalniz gercekten dagitilan
 * bilesenlere bakar.
 */
val writeRuntimeArtifacts by tasks.registering {
    val output = layout.buildDirectory.file("runtime-artifacts.txt")
    val runtime = configurations.named("runtimeClasspath")
    outputs.file(output)
    doLast {
        val coordinates = runtime.get().incoming.resolutionResult.allComponents
            .mapNotNull { component ->
                (component.id as? org.gradle.api.artifacts.component.ModuleComponentIdentifier)
                    ?.let { "${it.group}:${it.module}:${it.version}" }
            }
            .distinct()
            .sorted()
        val target = output.get().asFile
        target.parentFile.mkdirs()
        target.writeText(coordinates.joinToString("\n") + "\n")
    }
}
