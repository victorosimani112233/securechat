plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
}

application {
    mainClass.set("com.securechat.botapi.ApplicationKt")
}

// Fat JAR — bot-api konteynerinde tek dosyalik calistirilabilir
tasks.register<Jar>("fatJar") {
    archiveClassifier.set("all")
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    manifest {
        attributes["Main-Class"] = "com.securechat.botapi.ApplicationKt"
    }
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    with(tasks.jar.get())
    // JAR imza dosyalarini exclude et — ClassNotFoundException onlemi
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
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

    // EdDSA JWT — Nimbus JOSE+JWT (java-jwt EdDSA desteklemiyor)
    implementation(libs.nimbus.jose.jwt)

    // libsignal-client — JVM, native JNI binding'leri ile gelir
    implementation(libs.libsignal.client)

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
