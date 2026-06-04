plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

application {
    mainClass.set("com.securechat.botapi.ApplicationKt")
}

// Shadow JAR — META-INF/services'i mergeServiceFiles ile birlestirir.
// libsignal/protobuf reflection meta'sinin korunmasi icin standart fat JAR
// yetmiyor; protobuf'in GeneratedMessageLite reflection cagrilari fail olur.
tasks.named<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("shadowJar") {
    archiveClassifier.set("all")
    archiveFileName.set("bot-api-all.jar")
    mergeServiceFiles()
    manifest {
        attributes["Main-Class"] = "com.securechat.botapi.ApplicationKt"
    }
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
}

// fatJar alias — eski deploy komutlariyla uyum
tasks.register("fatJar") {
    dependsOn("shadowJar")
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

    // signaling-server icin HS256 JWT mint — bot kendi access token'ini uretir
    implementation("com.auth0:java-jwt:4.4.0")

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
}

kotlin {
    jvmToolchain(17)
}
