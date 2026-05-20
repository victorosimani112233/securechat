plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
}

application {
    mainClass.set("com.securechat.botadmin.MainKt")
    applicationName = "bot-admin"
}

// Fat JAR — taşinabilir tek dosyalik CLI
tasks.register<Jar>("fatJar") {
    archiveClassifier.set("all")
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    manifest {
        attributes["Main-Class"] = "com.securechat.botadmin.MainKt"
    }
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
    with(tasks.jar.get())
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
}

dependencies {
    // CLI parser
    implementation(libs.clikt)

    // OkHttp + junixsocket — Unix domain socket uzerinden HTTP
    implementation(libs.okhttp)
    implementation(libs.junixsocket.core)
    implementation(libs.junixsocket.native.common)

    // JSON
    implementation(libs.serialization.json)
    implementation(libs.coroutines.core)
    implementation(libs.logback)

    // Test
    testImplementation(libs.junit)
    testImplementation(libs.truth)
}

kotlin {
    jvmToolchain(17)
}
