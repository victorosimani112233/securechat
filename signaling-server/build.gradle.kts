plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
}

application {
    mainClass.set("com.securechat.signaling.ApplicationKt")
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
}
