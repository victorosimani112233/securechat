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
}
