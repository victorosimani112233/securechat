plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
    // Shadow plugin KALDIRILDI:
    //  - infra/Dockerfile.bot-api zaten 'build/install/bot-api/lib + bin'
    //    (application plugin'in installDist task'i) kullaniyor, fat JAR'a
    //    ihtiyac yok.
    //  - Shadow transitif BOM zinciri (jackson-bom, junit-bom, spring-bom,
    //    jakartaee-bom, log4j-bom, ant-parent vs.) offline build ortamlarinda
    //    configuration asamasinda sorun cikariyordu (50+ pom indirme).
    //  - Application + installDist multi-layer Docker caching ile de daha verimli.
}

application {
    mainClass.set("com.securechat.botapi.ApplicationKt")
}

// fatJar alias — eski deploy komutlariyla uyum. Artik 'installDist' altinda
// build/install/bot-api/ uretir (lib/*.jar + bin/bot-api launcher).
tasks.register("fatJar") {
    dependsOn("installDist")
    description = "Eski deploy script uyumlulugu — installDist'e yonlendirir."
}

dependencies {
    // Ktor server
    implementation(libs.ktor.server.core)
    implementation(libs.ktor.server.netty)
    implementation(libs.ktor.server.content.negotiation)
    implementation(libs.ktor.serialization)
    implementation(libs.ktor.client.okhttp)
    implementation("io.ktor:ktor-client-core:2.3.7")
    implementation("io.ktor:ktor-client-content-negotiation:2.3.7")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.7")

    // Netty native epoll — Unix domain socket binding (Linux only)
    implementation(libs.netty.transport.native.epoll) {
        artifact { classifier = "linux-x86_64" }
    }

    // Coroutines + serialization
    implementation(libs.coroutines.core)
    implementation(libs.logback)
    implementation(libs.serialization.json)

    // EdDSA JWT — Nimbus JOSE+JWT (sadece JWT parse/claims icin; imza dogrulama
    // JDK 17 native Signature("Ed25519") ile yapilir, Tink/BouncyCastle gerektirmez).
    implementation(libs.nimbus.jose.jwt)

    // Signal Protocol — pure Java variant (Android bagimliliği yok, JNI yok).
    // crypto modulu (signal-protocol-android 2.8.1) ile wire-format birebir uyumlu.
    implementation(libs.signal.protocol.java)

    // OkHttp — WebSocket client (signaling-server'a bot baglantisi)
    implementation(libs.okhttp)

    // PostgreSQL + Hikari pool
    implementation(libs.postgresql)
    implementation(libs.hikaricp)

    // Redis
    implementation(libs.jedis)

    // NOT: HS256 JWT mint kutuphanesi bilincli olarak kaldirildi. Bot artik
    // kullanici token'i uretemez; signaling'e karsi kimligi JDK 17 native
    // Ed25519 ile imzalanan dar kapsamli servis assertion'idir.

    // Prometheus metrics
    implementation(libs.micrometer.prometheus)
    implementation(libs.micrometer.core)

    // Test
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.truth)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.testcontainers.postgres)
    testImplementation(libs.testcontainers.junit)
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.junit.jupiter:junit-jupiter-engine:5.10.2")
}

tasks.test {
    useJUnitPlatform()
    systemProperty(
        "serverMigrationDir",
        rootProject.file("signaling-server/src/main/resources/db/migration").absolutePath
    )
}

kotlin {
    jvmToolchain(17)
}
