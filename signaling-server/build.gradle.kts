plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
}

application {
    mainClass.set("com.securechat.signaling.ApplicationKt")
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
}
